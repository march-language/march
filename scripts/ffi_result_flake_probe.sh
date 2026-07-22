#!/usr/bin/env bash
# ffi_result_flake_probe.sh — stress-compile probe for the intermittent
# GH-Actions-only `ffi_result` flake (parse("zz") occasionally prints "bad int"
# instead of "nan").  See test/dune (ffi_result quarantine block) and
# runtime/march_ffi.c (ffi_layout_probe_guard) for the full analysis.
#
# What it does, ITER times:
#   1. clears the march CAS artifact cache AND disables dune's build cache, then
#      --force-rebuilds native_ffi_result / native_ffi_result_diag so each
#      iteration is a genuinely fresh clang invocation (the flake is across
#      COMPILES of identical IR, so caching would mask it);
#   2. records the sha256 of each freshly-built binary and its stdout.
#
# It then answers the single question that bisects the whole problem:
#   * binaries DIFFER across iterations  => clang codegen/link NON-DETERMINISM
#     (identical inputs -> different objects: a runner-toolchain artifact);
#   * binaries IDENTICAL but output varies => execution-time UB / environment.
#
# On any wrong output it dumps the smoking gun: the diag binary's stderr
# (decoded Err cell tag/len/bytes), plus nm + objdump of the three adjacent
# shims (ffi_test_parse / ffi_layout_probe_guard / ffi_raise_parse) so a
# fall-through into the adjacent sibling is visible.
#
# Exits non-zero if the flake reproduces (so the CI step shows a red X and the
# evidence is easy to find); run the step with continue-on-error so it never
# blocks the pipeline.
#
# Usage:  scripts/ffi_result_flake_probe.sh [ITER]   (default 40)
set -u

ITER="${1:-40}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

DUNE="${DUNE:-dune}"
# Portable sha256 (Linux: sha256sum; macOS: shasum -a 256).
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi; }
EXPECT_MAIN=$'7\nnan'
EXPECT_DIAG=$'7\nnan\n3'
MAIN_TGT="test/native_ffi_result"
DIAG_TGT="test/native_ffi_result_diag"
MAIN_BIN="_build/default/test/native_ffi_result"
DIAG_BIN="_build/default/test/native_ffi_result_diag"

# objdump on Linux, otool on macOS (for local dry-runs).  Dump both the C shims
# AND the March-emitted callers (march_main / shown / println) — the miscompile
# is memory-safe and the shims + IR are provably correct, so the wrong codegen
# must be in how clang lowers the (correct) IR of these functions.  objdump
# separates functions with a blank line, so print each matching header block up
# to the next blank line.
dump_fn() {  # $1 = binary
  local fns='ffi_test_parse|ffi_layout_probe_guard|ffi_raise_parse|march_main|shown|println.String|march_int_to_string'
  if command -v objdump >/dev/null 2>&1; then
    echo "--- nm (fn addresses) ---"
    nm "$1" 2>/dev/null | grep -iE "$fns" | sort
    echo "--- objdump -d (C shims + March callers) ---"
    objdump -d "$1" 2>/dev/null | awk -v F="$fns" '
      $0 ~ ("^[0-9a-f]+ <("F")>:") {p=1}
      p && /^[[:space:]]*$/ {p=0}
      p {print}'
  elif command -v otool >/dev/null 2>&1; then
    nm "$1" 2>/dev/null | grep -iE "$fns" | sort
    otool -tv "$1" 2>/dev/null | awk '/^_ffi_test_parse:/{p=1} p{print} /^_ffi_raise_fdiv:/{exit}'
  fi
}

# Collect binary shas in a temp file (portable to bash 3.2 — no associative arrays).
SHAFILE="$(mktemp)"; trap 'rm -f "$SHAFILE"' EXIT
flaked=0
echo "== ffi_result flake probe: $ITER iterations =="
echo "== compiler: $(command -v clang) =="
clang --version 2>/dev/null | head -1

for i in $(seq 1 "$ITER"); do
  rm -rf .march/cas/artifacts
  DUNE_CACHE=disabled "$DUNE" build --root . --force "$MAIN_TGT" "$DIAG_TGT" >/dev/null 2>&1

  main_out="$("$MAIN_BIN" 2>/dev/null)"
  main_sha="$(sha256 "$MAIN_BIN" 2>/dev/null | cut -d' ' -f1)"
  echo "$main_sha" >> "$SHAFILE"

  tag="ok"
  if [ "$main_out" != "$EXPECT_MAIN" ]; then tag="FLAKE"; flaked=1; fi
  echo "iter=$i sha=${main_sha:0:12} out=$(printf '%q' "$main_out") [$tag]"

  if [ "$tag" = "FLAKE" ]; then
    echo "############ FLAKE REPRODUCED (iter $i) ############"
    echo "expected: $(printf '%q' "$EXPECT_MAIN")"
    echo "got:      $(printf '%q' "$main_out")"
    echo "---- diag binary stderr (decoded Err cell) ----"
    diag_out="$("$DIAG_BIN" 2>/tmp/ffi_diag_stderr)"; echo "diag stdout: $(printf '%q' "$diag_out")"
    cat /tmp/ffi_diag_stderr 2>/dev/null
    echo "---- MARCH_ECHO_CC (this iteration's clang command) ----"
    rm -rf .march/cas/artifacts
    MARCH_ECHO_CC=1 DUNE_CACHE=disabled "$DUNE" build --root . --force "$MAIN_TGT" 2>&1 | grep MARCH_CC_CMD | head -1
    echo "---- shim layout / disassembly ----"
    dump_fn "$MAIN_BIN"
    echo "###################################################"
  fi
done

echo "== summary =="
distinct="$(sort -u "$SHAFILE" | grep -c .)"
echo "distinct native_ffi_result binaries across $ITER compiles: $distinct"
if [ "$distinct" -gt 1 ]; then
  echo ">> binaries DIFFER across identical-input compiles => clang codegen/link NON-DETERMINISM"
  sort -u "$SHAFILE" | sed 's/^/   sha: /'
else
  echo ">> all binaries byte-identical => any output flake is execution-time UB / environment, not codegen"
fi

if [ "$flaked" -ne 0 ]; then
  echo "RESULT: flake REPRODUCED (see FLAKE blocks above)"
  exit 1
fi
echo "RESULT: no flake in $ITER iterations"
exit 0
