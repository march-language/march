#!/usr/bin/env bash
# HCR Phase 0 spike driver -- THROWAWAY.
#
#   run.sh OUT_DIR BASE_HANDLER [PATCH_HANDLER ...]
#
# Builds the base binary (app.march.in + handlers/BASE_HANDLER.march, with
# --hot-reload App) and one --compile-so patch per PATCH_HANDLER, then runs
# the base with HCR0_PATCH_<k> pointing at the k-th patch.  The program swaps
# to patch k at request HCR0_EVERY * k (default every = N / (#patches + 1)).
#
# Env: MARCH (compiler, default ../../../_build/default/bin/main.exe),
#      HCR0_N (requests, default 20000), OPT (default 2),
#      MARCH_SANITIZE=1 for an ASan/UBSan build (base and patches alike).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="$1"; shift
base="$1"; shift
MARCH="${MARCH:-$here/../../../_build/default/bin/main.exe}"
OPT="${OPT:-2}"
N="${HCR0_N:-20000}"
mkdir -p "$out"
# Private HOME: the shared ~/.cache/march and ~/.march/cas must not leak in.
export HOME="${HCR0_HOME:-/tmp/hcr0-home}"
mkdir -p "$HOME"
gen() {  # gen HANDLER -> $out/<handler>.march (always named app.march inside a per-handler dir)
  local h="$1" d="$out/src-$1"
  mkdir -p "$d"
  awk -v hf="$here/handlers/$h.march" '
    /^@HANDLER@$/ { while ((getline l < hf) > 0) print l; next } { print }' \
    "$here/app.march.in" > "$d/app.march"
  echo "$d/app.march"
}
src="$(gen "$base")"
"$MARCH" --compile ${EXTRA:-} --opt "$OPT" --hot-reload App --ffi-c "$here/swap_shim.c" \
  -o "$out/base" "$src" > "$out/build-base.log" 2>&1 || { cat "$out/build-base.log"; exit 2; }
k=0
for p in "$@"; do
  k=$((k + 1))
  psrc="$(gen "$p")"
  "$MARCH" --compile --compile-so ${EXTRA:-} --opt "$OPT" --hot-reload App --ffi-c "$here/swap_shim.c" \
    -o "$out/patch$k.so" "$psrc" > "$out/build-patch$k.log" 2>&1 || { cat "$out/build-patch$k.log"; exit 2; }
  export "HCR0_PATCH_$k=$out/patch$k.so"
done
export HCR0_NAMES="${HCR0_NAMES:-Handler.handle,Handler.mk,Handler.tag,Handler.count}"
export HCR0_N="$N"
export HCR0_EVERY="${HCR0_EVERY:-$(( k > 0 ? N / (k + 1) : 0 ))}"
set +e
"$out/base" > "$out/run.out" 2> "$out/run.err"
rc=$?
set -e
cat "$out/run.out"
echo "exit=$rc"
if [ -s "$out/run.err" ]; then echo "--- stderr (first 40 lines) ---"; head -40 "$out/run.err"; fi
exit 0
