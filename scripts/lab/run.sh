#!/usr/bin/env bash
# The multi-host lab's runner (docs/lab.md): forge, run from this machine,
# deploys examples/lab_app to four containers (scripts/lab/up.sh) over real
# ssh and through the in-cluster control plane, and each scenario asserts
# what happened.
#
#   scripts/lab/run.sh                      every scenario but soak, in order
#   scripts/lab/run.sh deploy hot_role      these, in this order
#   scripts/lab/run.sh soak --minutes 60    the soak (opt-in)
#   scripts/lab/run.sh --list               the scenarios
#
# `deploy` starts from nothing: fresh hosts, `forge host init`, the first
# `forge deploy`. Every other scenario needs a deployed lab and runs `deploy`
# first when there is none (or with --fresh). The containers are left up
# when it ends (scripts/lab/down.sh removes them).
#
# Exit status: 0 when every scenario passed or failed as expected (an
# expected failure names its todo), 1 when one failed, 2 when a prerequisite
# is missing (nothing was tested), 3 when nothing failed but a scenario ran
# with this machine's 1-minute load above LAB_MAX_LOAD (default 20): its
# result is reported "unreliable", since most scenarios assert on timing.
set -u
here=$(cd "$(dirname "$0")" && pwd)
source "$here/lib.sh"

all=
for s in deploy hot_role protocol_change restart_persist failover partition leader_kill cert_rotate; do
  [ -f "$here/scenarios/$s.sh" ] && all="$all $s"
done
want=(); fresh=; LAB_SOAK_MINUTES=${LAB_SOAK_MINUTES:-30}
while [ $# -gt 0 ]; do
  case $1 in
    --list) for s in $all $([ -f "$here/scenarios/soak.sh" ] && echo soak); do printf '%-16s %s\n' "$s" "$(sed -n 's/^# lab-scenario: //p' "$here/scenarios/$s.sh")"; done; exit 0 ;;
    --fresh) fresh=1 ;;
    --minutes) LAB_SOAK_MINUTES=$2; shift ;;
    -h | --help) sed -n '2,20p' "$0"; exit 0 ;;
    -*) echo "run.sh: unknown option $1" >&2; exit 2 ;;
    *) [ -f "$here/scenarios/$1.sh" ] || { echo "run.sh: no scenario '$1' (--list)" >&2; exit 2; }; want+=("$1") ;;
  esac
  shift
done
[ ${#want[@]} -gt 0 ] || want=($all)
export LAB_SOAK_MINUTES

lab_prereqs
mkdir -p "$LAB_DIR/logs"
rm -f "$LAB_DIR"/logs/forge-*.log "$LAB_DIR"/logs/scenario-*.log "$LAB_DIR/forge-n"
lab_build
lab_env
: > "$LAB_DIR/notes"

deployed() {
  [ -f "$LAB_DIR/deployed" ] || return 1
  local h
  for h in $LAB_HOSTS; do lab_running "$h" || return 1; done
}

# One scenario in a subshell: its own `fail` ends only it. An expected
# failure (LAB_XFAIL=<todo> in the scenario file) is reported, not counted;
# an unexpected pass of one is a failure, so a fixed bug gets its marker
# removed.
results=(); bad=0; unreliable=0; deploy_failed=; LAB_MAX_LOAD=${LAB_MAX_LOAD:-20}
run_one() {
  local s=$1 t0=$SECONDS rc xfail l0 l1
  xfail=$(sed -n 's/^LAB_XFAIL=//p' "$here/scenarios/$s.sh" | tr -d '"')
  l0=$(lab_load)
  local oom0; oom0=$(lab_oom_kills)
  lab_say "==> scenario $s (load $l0)"
  ( export LAB_SCENARIO=$s; source "$here/scenarios/$s.sh" ) 2>&1 | tee "$LAB_DIR/logs/scenario-$s.log"
  rc=${PIPESTATUS[0]}
  local took=$((SECONDS - t0))
  l1=$(lab_load); [ "$l1" -gt "$l0" ] && l0=$l1
  local oom1; oom1=$(lab_oom_kills)
  # The count is the whole Docker VM's: another project's container counts too.
  [ "$oom1" -gt "$oom0" ] && echo "$s: $((oom1 - oom0)) process(es) OOM-killed in the Docker VM during the scenario" >> "$LAB_DIR/notes"
  if [ "$rc" = 2 ]; then exit 2; fi
  if [ "$rc" = 4 ]; then results+=("SKIP  $s: $(sed -n 's/^lab: SKIP: //p' "$LAB_DIR/logs/scenario-$s.log" | tail -1)"); return; fi
  # Timing is the point of most scenarios: on a machine this busy a result
  # says nothing either way.
  if [ "$l0" -gt "$LAB_MAX_LOAD" ]; then
    results+=("UNRELIABLE $s (${took}s): load $l0 (above LAB_MAX_LOAD=$LAB_MAX_LOAD); it exited $rc"); unreliable=1
  elif [ -n "$xfail" ]; then
    # LAB_XFAIL_AT=<text>[|<text>...]: the expected failure is one whose
    # message has one of the texts; any other failure is a real one.
    local at why a matched=
    at=$(sed -n 's/^LAB_XFAIL_AT=//p' "$here/scenarios/$s.sh" | tr -d '"')
    why=$(sed -n 's/^lab: FAIL: //p' "$LAB_DIR/logs/scenario-$s.log" | tail -1)
    if [ -z "$at" ]; then matched=1; else
      local IFS='|'
      for a in $at; do [ "${why#*"$a"}" != "$why" ] && matched=1; done
      unset IFS
    fi
    if [ "$rc" = 0 ]; then results+=("XPASS $s (${took}s): passed but is marked expected-fail ($xfail); remove the marker"); bad=1
    elif [ -z "$matched" ]; then results+=("FAIL  $s (${took}s): not the expected failure ($at): $why"); bad=1
    else results+=("XFAIL $s (${took}s): $why ($xfail)"); fi
  elif [ "$rc" = 0 ]; then results+=("PASS  $s (${took}s)")
  else results+=("FAIL  $s (${took}s): see $LAB_DIR/logs/scenario-$s.log"); bad=1; fi
}

for s in "${want[@]}"; do
  # A scenario needs a deployed lab: deploy first when there is none (a
  # scenario before may have left a host down). Once a deploy has failed in
  # this run, the rest are not run.
  if [ "$s" != deploy ] && [ -n "$deploy_failed" ]; then
    results+=("SKIP  $s: no deployed lab (deploy failed)"); bad=1; continue
  fi
  if [ "$s" != deploy ] && { [ -n "$fresh" ] || ! deployed; }; then
    lab_say "no deployed lab${fresh:+ (--fresh)}: running deploy first"
    fresh=
    run_one deploy
    deployed || { deploy_failed=1; results+=("SKIP  $s: no deployed lab (deploy failed)"); bad=1; continue; }
  fi
  run_one "$s"
  [ "$s" = deploy ] && ! deployed && deploy_failed=1
done

echo
echo "lab results ($LAB_DIR):"
for r in "${results[@]}"; do echo "  $r"; done
[ -s "$LAB_DIR/notes" ] && { echo "notes:"; sed 's/^/  /' "$LAB_DIR/notes"; }
[ "${LAB_KEEP:-1}" = 1 ] || "$here/down.sh"
[ "$bad" = 0 ] && [ "$unreliable" = 1 ] && exit 3
exit $bad
