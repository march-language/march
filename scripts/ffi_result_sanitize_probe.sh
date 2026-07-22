#!/usr/bin/env bash
# ffi_result_sanitize_probe.sh — pinpoint the ffi_result flake's UB now that it
# reproduces (deterministically, on GH ubuntu clang 18.1.3; see
# scripts/ffi_result_flake_probe.sh, which proved byte-identical binaries =>
# execution-time UB, not codegen).  Two passes:
#
#   1. VALGRIND on the UN-instrumented binary.  Valgrind does not change the
#      binary's code/layout, so it preserves the exact conditions that
#      reproduce the flake — the best shot at naming the UB (uninitialised
#      read / invalid access) without a Heisenberg layout shift.
#   2. ASAN + UBSan (MARCH_SANITIZE=1).  Stronger diagnostics, BUT -fsanitize
#      changes layout, so it may mask the flake — if the output also reverts to
#      "nan" with no report, that itself confirms layout-sensitive UB.
#
# Each iteration clears the CAS + disables dune's cache and --force-rebuilds, so
# every compile is fresh (the flake is layout/compile-sensitive).  Always exits
# 0 — this is a non-blocking diagnostic; the evidence is the point.
#
# Usage:  scripts/ffi_result_sanitize_probe.sh [ITER]   (default 6)
set -u

ITER="${1:-6}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

DUNE="${DUNE:-dune}"
MAIN_TGT="test/native_ffi_result"
BIN="_build/default/test/native_ffi_result"
EXPECT=$'7\nnan'
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "== ffi_result sanitize probe: $ITER iterations/pass =="
clang --version 2>/dev/null | head -1

# ── Pass 1: valgrind on the un-instrumented binary (layout preserved) ────────
echo
echo "===== VALGRIND (un-instrumented; preserves the reproducing layout) ====="
if command -v valgrind >/dev/null 2>&1; then
  vg_found=0
  for i in $(seq 1 "$ITER"); do
    rm -rf .march/cas/artifacts
    DUNE_CACHE=disabled "$DUNE" build --root . --force "$MAIN_TGT" >/dev/null 2>&1
    plain="$("$BIN" 2>/dev/null)"
    valgrind --error-exitcode=99 --track-origins=yes --num-callers=40 \
             --log-file="$TMP/vg_$i.log" "$BIN" >/dev/null 2>&1
    vrc=$?
    echo "valgrind iter=$i plain_out=$(printf '%q' "$plain") valgrind_rc=$vrc"
    if [ "$vrc" = "99" ] || grep -qiE 'Invalid read|Invalid write|uninitiali|Conditional jump' "$TMP/vg_$i.log"; then
      vg_found=1
      echo ">>>>> VALGRIND FLAGGED ERRORS (iter $i) >>>>>"
      cat "$TMP/vg_$i.log"
      echo "<<<<<"
    else
      grep -E 'ERROR SUMMARY|definitely lost|indirectly lost' "$TMP/vg_$i.log" | sed 's/^/  /' | head -3
    fi
  done
  [ "$vg_found" = 0 ] && echo "valgrind: no memory errors flagged across $ITER runs"
else
  echo "valgrind not installed — skipping (install: apt-get install -y valgrind)"
fi

# ── Pass 2: ASAN + UBSan (changes layout — may mask) ─────────────────────────
echo
echo "===== ASAN + UBSan (MARCH_SANITIZE=1; NOTE: -fsanitize changes layout) ====="
export ASAN_OPTIONS="abort_on_error=0:halt_on_error=0:detect_leaks=0:print_stacktrace=1"
export UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=0"
asan_found=0
for i in $(seq 1 "$ITER"); do
  rm -rf .march/cas/artifacts
  MARCH_SANITIZE=1 DUNE_CACHE=disabled "$DUNE" build --root . --force "$MAIN_TGT" >/dev/null 2>&1
  out="$("$BIN" 2>"$TMP/asan_$i.log")"
  tag="ok"; [ "$out" != "$EXPECT" ] && tag="wrong-output"
  san="$(grep -iE 'runtime error|AddressSanitizer|ERROR:|SUMMARY:|heap-|stack-|use-after' "$TMP/asan_$i.log" | head -1)"
  if [ -n "$san" ]; then asan_found=1; tag="SANITIZER HIT"; fi
  echo "asan iter=$i out=$(printf '%q' "$out") [$tag]"
  if [ -n "$san" ] || [ "$out" != "$EXPECT" ]; then
    echo "----- sanitizer stderr (iter $i) -----"; cat "$TMP/asan_$i.log"; echo "-----"
  fi
done
if [ "$asan_found" = 0 ]; then
  echo "ASAN/UBSan: no sanitizer report across $ITER runs"
  echo "  (if output also stayed 'nan', the sanitizer masked the flake => layout-sensitive UB confirmed)"
fi

echo
echo "== sanitize probe done =="
exit 0
