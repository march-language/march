#!/usr/bin/env bash
# Saturation gates for the actor system. Usage: scripts/actor-load.sh [scenario ...]
# Scenarios: fanin churn callstorm crashloop   (default: all)
# Prints one line per scenario:  SCENARIO <name> rss_mb=<n> wall_ms=<n> status=PASS|FAIL|XFAIL
set -u
cd "$(dirname "$0")/.."
MARCH=./_build/default/bin/main.exe
OUT=/tmp/actor-load-$$
mkdir -p "$OUT"
fail=0

# Scenarios that are known to fail against today's runtime (baseline recorded
# in the commit that introduced this script). A FAIL for one of these prints
# as XFAIL and does not flip the script's exit code -- the tasks that fix the
# underlying runtime issue are expected to remove entries here as they land.
EXPECTED_FAIL="${EXPECTED_FAIL:-churn}"

is_expected_fail() {
  local name=$1
  for x in $EXPECTED_FAIL; do
    [ "$x" = "$name" ] && return 0
  done
  return 1
}

# run_with_bound SECS CMD... -- runs CMD, and if it is still alive after SECS
# wall-clock seconds, kills the whole process group (not just the immediate
# child) so a genuine hang -- as opposed to merely slow -- cannot wedge the
# harness forever. macOS has no `timeout(1)` by default, so this is done with
# a small perl helper that puts the child in its own process group via
# setpgrp and sends SIGKILL to that group on SIGALRM.
run_with_bound() {
  local secs=$1; shift
  perl -e '
    my $secs = shift @ARGV;
    my $pid = fork();
    if (!defined $pid) { die "fork failed: $!"; }
    if ($pid == 0) {
      setpgrp(0, 0);
      exec(@ARGV) or exit(127);
    }
    local $SIG{ALRM} = sub { kill(9, -$pid); };
    alarm($secs);
    waitpid($pid, 0);
    my $rc = $?;
    alarm(0);
    if ($rc == -1) { exit(124); }
    exit($rc & 127 ? 128 + ($rc & 127) : ($rc >> 8));
  ' "$secs" "$@"
}

run_gated() { # name file rss_limit_mb wall_limit_ms expect_grep
  local name=$1 file=$2 rss_limit=$3 wall_limit=$4 expect=$5
  local bin="$OUT/$name"
  "$MARCH" --compile --opt 2 "bench/actors/$file" -o "$bin" > "$OUT/$name.compile.log" 2>&1
  if [ $? -ne 0 ]; then
    echo "SCENARIO $name status=FAIL (compile)"
    if is_expected_fail "$name"; then :; else fail=1; fi
    return
  fi
  local t0=$(($(date +%s%N)/1000000))
  # Hard wall-clock bound: 3x the gate, floor 30s -- generous enough that a
  # merely-slow (but passing) run always finishes, tight enough that a real
  # hang doesn't wedge the whole harness. A timeout counts as FAIL.
  local bound_secs=$(( (wall_limit * 3) / 1000 ))
  [ "$bound_secs" -lt 30 ] && bound_secs=30
  # /usr/bin/time -l on macOS reports max RSS in bytes; -v on Linux in KB.
  # A killed-on-timeout run never lets /usr/bin/time flush its stats line, so
  # the awk extraction can come back empty -- guard with :-0 before the
  # arithmetic expansion, or bash's `$(( <empty> / N ))` is a syntax error
  # that aborts the rest of this function (silently dropping the SCENARIO
  # line for exactly the hang case this harness exists to catch).
  local rss_raw
  if [ "$(uname)" = "Darwin" ]; then
    run_with_bound "$bound_secs" /usr/bin/time -l "$bin" > "$OUT/$name.out" 2> "$OUT/$name.time"
    rc=$?
    rss_raw=$(awk '/maximum resident set size/{print $1}' "$OUT/$name.time")
    rss_mb=$(( ${rss_raw:-0} / 1048576 ))
  else
    run_with_bound "$bound_secs" /usr/bin/time -v "$bin" > "$OUT/$name.out" 2> "$OUT/$name.time"
    rc=$?
    rss_raw=$(awk -F: '/Maximum resident set size/{print $2}' "$OUT/$name.time")
    rss_mb=$(( ${rss_raw:-0} / 1024 ))
  fi
  local t1=$(($(date +%s%N)/1000000))
  local wall=$((t1 - t0))
  local status=PASS
  local timed_out=0
  [ $rc -eq 124 ] && timed_out=1
  [ $rc -ne 0 ] && status=FAIL
  [ "${rss_mb:-0}" -gt "$rss_limit" ] 2>/dev/null && status=FAIL
  [ "$wall" -gt "$wall_limit" ] && status=FAIL
  grep -q "$expect" "$OUT/$name.out" || status=FAIL
  if [ "$status" = FAIL ] && is_expected_fail "$name"; then
    status=XFAIL
  elif [ "$status" = FAIL ]; then
    fail=1
  fi
  local note=""
  [ "$timed_out" -eq 1 ] && note=" (timeout at ${bound_secs}s)"
  echo "SCENARIO $name rss_mb=${rss_mb:-0} wall_ms=$wall status=$status$note"
}

# want NAME SELECTED... -- true if NAME was requested (or nothing was
# requested, meaning "run everything"). NAME must NOT be folded into the
# haystack it's searched against, or it trivially matches itself regardless
# of what was actually selected. Takes the script's own positional params
# directly ("$@") rather than caching them in an array -- bash 3.2 (macOS's
# default /bin/bash) mishandles `"${arr[@]}"` under `set -u` when the array
# is empty ("unbound variable"), so this sidesteps that entirely.
want() {
  local name=$1; shift
  [ $# -eq 0 ] && return 0
  printf '%s\n' "$@" | grep -qx "$name"
}

# Gates. EXPECTED_FAIL scenarios (see the allowlist above) run, report, but do
# not fail the script -- until the task that fixes the underlying runtime
# issue removes them from the allowlist.
want fanin     "$@" && run_gated fanin     fanin_flood.march 512  60000  "delivered"
want churn     "$@" && run_gated churn     spawn_churn.march 1024 120000 "post-churn spawn OK"
want callstorm "$@" && run_gated callstorm call_storm.march  512  60000  "completed 3200"
want crashloop "$@" && run_gated crashloop crash_loop.march  512  60000  "self-healed"

exit $fail
