#!/usr/bin/env bash
# test-ci-evidence.sh: scripts/ci-evidence.sh against a fake job.
#
# The script only runs for real when a CI job has already failed, which is the
# worst time to find out it copies nothing. This stages what a failed job
# leaves behind (a two-node work directory with a fifo in it, a crash report
# newer than setup and one older, a core file whose executable still exists)
# and asserts what `collect` keeps. No root, no network; gdb is not required.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
ok()   { echo "ok: $1"; }
bad()  { echo "FAIL: $1"; fails=$((fails + 1)); }
want() { if [ -e "$2" ]; then ok "$1"; else bad "$1 (missing: ${2#"$T"/})"; fi; }
wantnot() { if [ -e "$2" ] || [ -p "$2" ]; then bad "$1 (present: ${2#"$T"/})"; else ok "$1"; fi; }

export RUNNER_TEMP="$T/runner" TMPDIR="$T/tmp" GITHUB_ENV="$T/github_env"
export MARCH_EVIDENCE_NO_SYSCTL=1 MARCH_CRASH_REPORT_DIR="$T/reports" MARCH_CRASH_REPORT_WAIT=0
unset MARCH_EVIDENCE_DIR
mkdir -p "$RUNNER_TEMP" "$TMPDIR" "$MARCH_CRASH_REPORT_DIR"

echo old > "$MARCH_CRASH_REPORT_DIR/old-crash.ips"
# `find -newer` compares whole seconds on some filesystems.
touch -t 200001010000 "$MARCH_CRASH_REPORT_DIR/old-crash.ips"

"$HERE/ci-evidence.sh" setup > "$T/setup.out"
dir="$RUNNER_TEMP/march-evidence"
want "setup creates the evidence directory" "$dir/cores"
if grep -qx "MARCH_EVIDENCE_DIR=$dir" "$GITHUB_ENV"; then ok "setup exports MARCH_EVIDENCE_DIR to later steps"
else bad "setup exports MARCH_EVIDENCE_DIR to later steps"; fi
export MARCH_EVIDENCE_DIR="$dir"

# What the failed job left behind.
echo "the step's output" > "$dir/test.log"
w="$TMPDIR/two-node-restart.Ab12Cd"; mkdir -p "$w"
echo "A: links 0" > "$w/a.out"; echo binary > "$w/node_a"; mkfifo "$w/ctl.fifo"
mkdir -p "$TMPDIR/two-node-prebuilt"; echo x > "$TMPDIR/two-node-prebuilt/stamp"
sleep 1; echo new > "$MARCH_CRASH_REPORT_DIR/native_x-2026-11-11.ips"
exe="$T/bin/native_crash"; mkdir -p "$T/bin"; echo '#!/bin/sh' > "$exe"
echo core > "$dir/cores/core.4242.$(printf '%s' "$exe" | tr / '!')"

"$HERE/ci-evidence.sh" collect > "$T/collect.out" 2>&1 || { bad "collect exits 0"; sed 's/^/    /' "$T/collect.out"; }

want "the step log is still there" "$dir/test.log"
want "a failed two-node scenario's output is kept" "$dir/two-node/two-node-restart.Ab12Cd/a.out"
want "... and its node binary" "$dir/two-node/two-node-restart.Ab12Cd/node_a"
wantnot "... but not its fifo" "$dir/two-node/two-node-restart.Ab12Cd/ctl.fifo"
wantnot "a directory that is not a scenario work directory is left alone" "$dir/two-node/two-node-prebuilt"
want "the core's executable is copied" "$dir/binaries/native_crash.4242"
want "a backtrace file is written" "$dir/cores/backtraces.txt"
if grep -qF "executable: $exe" "$dir/cores/backtraces.txt"; then ok "the core's executable path is decoded from its name"
else bad "the core's executable path is decoded from its name"; fi
if [ "$(uname -s)" = Darwin ]; then
  want "a crash report written since setup is kept" "$dir/crash-reports/native_x-2026-11-11.ips"
  wantnot "an older crash report is not" "$dir/crash-reports/old-crash.ips"
fi

unset MARCH_EVIDENCE_DIR
if "$HERE/ci-evidence.sh" collect > /dev/null 2>&1; then bad "collect without setup fails"; else ok "collect without setup fails"; fi

echo
if [ "$fails" -gt 0 ]; then echo "test-ci-evidence: $fails FAILED"; sed 's/^/    /' "$T/collect.out"; exit 1; fi
echo "test-ci-evidence: all passed"
