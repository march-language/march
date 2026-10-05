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
# is missing (nothing was tested).
set -u
here=$(cd "$(dirname "$0")" && pwd)
source "$here/lib.sh"

all="deploy hot_role protocol_change restart_persist failover partition leader_kill cert_rotate"
want=(); fresh=; LAB_SOAK_MINUTES=${LAB_SOAK_MINUTES:-30}
while [ $# -gt 0 ]; do
  case $1 in
    --list) for s in $all soak; do printf '%-16s %s\n' "$s" "$(sed -n 's/^# lab-scenario: //p' "$here/scenarios/$s.sh")"; done; exit 0 ;;
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
results=(); bad=0
run_one() {
  local s=$1 t0=$SECONDS rc xfail
  xfail=$(sed -n 's/^LAB_XFAIL=//p' "$here/scenarios/$s.sh" | tr -d '"')
  lab_say "==> scenario $s"
  ( export LAB_SCENARIO=$s; source "$here/scenarios/$s.sh" ) 2>&1 | tee "$LAB_DIR/logs/scenario-$s.log"
  rc=${PIPESTATUS[0]}
  local took=$((SECONDS - t0))
  if [ "$rc" = 2 ]; then exit 2; fi
  if [ -n "$xfail" ]; then
    if [ "$rc" = 0 ]; then results+=("XPASS $s (${took}s): passed but is marked expected-fail ($xfail); remove the marker"); bad=1
    else results+=("XFAIL $s (${took}s): $xfail"); fi
  elif [ "$rc" = 0 ]; then results+=("PASS  $s (${took}s)")
  else results+=("FAIL  $s (${took}s): see $LAB_DIR/logs/scenario-$s.log"); bad=1; fi
}

for s in "${want[@]}"; do
  if [ "$s" != deploy ] && { [ -n "$fresh" ] || ! deployed; }; then
    lab_say "no deployed lab${fresh:+ (--fresh)}: running deploy first"
    fresh=
    run_one deploy
    deployed || break
  fi
  run_one "$s"
done

echo
echo "lab results ($LAB_DIR):"
for r in "${results[@]}"; do echo "  $r"; done
[ -s "$LAB_DIR/notes" ] && { echo "notes:"; sed 's/^/  /' "$LAB_DIR/notes"; }
[ "${LAB_KEEP:-1}" = 1 ] || "$here/down.sh"
exit $bad
