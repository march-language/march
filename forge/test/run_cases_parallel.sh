#!/usr/bin/env bash
# run_cases_parallel.sh EXE [JOBS]
#
# Runs every case of the alcotest binary EXE as its own process, JOBS at a
# time (default: $MARCH_TEST_JOBS, else 3), then prints each case's output in
# order and exits 1 if any case failed.
#
# For suites whose cases are independent end-to-end runs that each build and
# drive real processes: run one after another they were the long pole of
# CI's `rest` shard (test_upgrade_from, 913 s for 7 cases, 2026-10-07). Separate
# processes, not domains: those tests Unix.fork, which OCaml 5 refuses once a
# second domain exists.
#
# Each case gets `-e` and its own alcotest log dir. A case selector that
# matches nothing is an error, not a pass: the case list comes from
# `EXE list`, and each process must report exactly one test run.
set -u

exe=${1:?usage: run_cases_parallel.sh EXE [JOBS]}
# dune's %{exe:x.exe}, passed as an argument, is the bare name: bash would
# look it up on PATH. A bare name means this directory.
case $exe in */*) ;; *) exe=./$exe ;; esac
jobs=${2:-${MARCH_TEST_JOBS:-3}}
work=$(mktemp -d "${TMPDIR:-/tmp}/run_cases_parallel.XXXXXX")
trap 'rm -rf "$work"' EXIT

# `list` prints "<group> <index> <description>" per case, with ANSI colour.
"$exe" list 2>"$work/list.err" | sed 's/\x1b\[[0-9;]*m//g' \
  | awk 1 > "$work/list"   # awk 1: BSD sed drops the newline a last line lacks
sed -nE 's/^[[:space:]]*(.*[^[:space:]])[[:space:]]+([0-9]+)[[:space:]]{2,}.*$/\1\t\2/p' \
  "$work/list" | awk 1 > "$work/cases"
n=$(awk 'END { print NR }' "$work/cases")
# Cross-check the parse against a plain count of case lines, so a format
# change can't quietly drop cases (as a missing final newline once did).
listed=$(grep -cE '[[:space:]][0-9]+[[:space:]]{2,}' "$work/list" || true)
if [ "$n" -eq 0 ]; then
  echo "run_cases_parallel: $exe lists no cases. Its \`list\` output and stderr:" >&2
  cat "$work/list" "$work/list.err" >&2
  exit 2
fi
[ "$n" -eq "$listed" ] || { echo "run_cases_parallel: parsed $n cases but $exe lists $listed" >&2; exit 2; }

# One worker per case: <k> <group> <index>. The group goes through as an
# anchored, regex-escaped selector so it names exactly that group.
run_one() {
  local k=$1 group=$2 idx=$3 re
  re="^$(printf '%s' "$group" | sed 's/[][\.*^$+?(){}|]/\\&/g')\$"
  mkdir -p "$work/o$k"
  "$exe" test "$re" "$idx" -e -o "$work/o$k" > "$work/$k.log" 2>&1
  echo $? > "$work/$k.rc"
}
export -f run_one
export exe work

awk -F'\t' '{ printf "%d\t%s\t%s\n", NR, $1, $2 }' "$work/cases" \
  | while IFS=$'\t' read -r k group idx; do printf '%s\0%s\0%s\0' "$k" "$group" "$idx"; done \
  | xargs -0 -n 3 -P "$jobs" bash -c 'run_one "$@"' _

rc=0
k=0
while IFS=$'\t' read -r group idx; do
  k=$((k + 1))
  echo "=== $group #$idx (exit $(cat "$work/$k.rc" 2>/dev/null || echo '?'))"
  cat "$work/$k.log" 2>/dev/null
  # Alcotest's summary counts only the selected cases: a selector that
  # matched nothing says "0 tests run" and still exits 0.
  if [ "$(cat "$work/$k.rc" 2>/dev/null || echo 1)" != 0 ]; then rc=1
  elif ! sed 's/\x1b\[[0-9;]*m//g' "$work/$k.log" | grep -qE 'Test Successful in .* 1 test run'; then
    echo "run_cases_parallel: case $group #$idx did not run exactly one test" >&2; rc=1
  fi
done < "$work/cases"
echo "run_cases_parallel: $n case(s), $jobs at a time, $([ $rc = 0 ] && echo all passed || echo FAILED)"
exit $rc
