#!/usr/bin/env bash
# Core March walking-skeleton golden check (see ../core-march.md §5).
# Runs every golden program through BOTH the interpreter and the compiled
# backend and asserts identical output — the executable anchor for the
# operational-semantics rules. Exit 0 iff all programs match.
#
#   MARCH_BIN=/path/to/main.exe specs/lang/golden/verify.sh
# (defaults MARCH_BIN to _build/default/bin/main.exe relative to the repo root)

set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
bin="${MARCH_BIN:-$root/_build/default/bin/main.exe}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [ ! -x "$bin" ]; then
  echo "march binary not found at $bin — build it (dune build bin/main.exe) or set MARCH_BIN" >&2
  exit 2
fi

# `--compile` drops a `.march/` CAS directory in the process's CWD, so running
# this script from the golden directory (the natural thing to do) left one
# behind next to the corpus.  It is gitignored, so `git status` stays clean —
# but `scripts/check-docs.sh` counts the corpus with `find -name '*.march'`, and
# the glob's `*` matches the empty string, so the directory was counted as a
# 47th golden program and the doc lint failed with a corpus-count mismatch that
# looked like someone had added a file.  Run from $work instead: the CAS lands
# in the temp dir the EXIT trap already removes.  $here, $work and $bin are all
# absolute, so nothing below depends on the original CWD.
cd "$work" || exit 2

pass=0; fail=0
for f in "$here"/*.march; do
  b="$(basename "$f" .march)"
  "$bin" "$f" > "$work/$b.interp" 2>"$work/$b.interp.err"; ir=$?
  "$bin" --compile "$f" -o "$work/$b.bin" > "$work/$b.compile.log" 2>&1; cr=$?
  if [ $ir -ne 0 ]; then echo "  [$b] INTERP FAIL ($ir)"; fail=$((fail+1)); continue; fi
  if [ $cr -ne 0 ]; then echo "  [$b] COMPILE FAIL ($cr)"; fail=$((fail+1)); continue; fi
  "$work/$b.bin" > "$work/$b.compiled" 2>&1
  if diff -q "$work/$b.interp" "$work/$b.compiled" >/dev/null; then
    echo "  [$b] MATCH"; pass=$((pass+1))
  else
    echo "  [$b] MISMATCH"
    echo "    interp:   $(tr '\n' '|' < "$work/$b.interp")"
    echo "    compiled: $(tr '\n' '|' < "$work/$b.compiled")"
    fail=$((fail+1))
  fi
done

echo "=== core-march golden: $pass matched, $fail failed ==="
[ $fail -eq 0 ]
