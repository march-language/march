#!/usr/bin/env bash
# HCR regression: a reclaimed version's closures still run, and a patch's
# closures release their captures.
#
#   test/hcr_closure_pin/run.sh MARCH_BIN OUT_DIR
#
# Builds the base (handler_v1, --hot-reload App) and four --compile-so
# patches (v2, v1, v2, v1; four distinct files, so each deploy maps its own
# image), runs the base, and prints its stdout and exit status.  The base
# deploys patch k at request N/5 * k, keeps the closures every version built,
# and calls them after the fourth deploy, by which time the 3-version ring has
# reclaimed patch 1.  Expected output: test/hcr_closure_pin/expected.
#
# MARCH_SANITIZE=1 builds the base and the patches with ASan/UBSan (run it
# in the Linux CI image; specs/lang/golden/sanitize.sh does). The test/dune
# rule runs the plain build.
#
# specs/progress/2026-10-13-hcr-reclaimed-patch-unmaps-live-closure-code.md
# specs/progress/2026-10-13-hcr-patch-closures-not-in-drop-table.md
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
march="$1"; out="$2"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
# A private HOME: the shared ~/.cache/march and ~/.march/cas must not serve a
# binary built by another compiler or runtime.
export HOME="$out/home"
mkdir -p "$HOME"

gen() {  # gen V -> $out/src-V/app.march (same entry-file name for every build)
  local d="$out/src-$1"
  mkdir -p "$d"
  awk -v hf="$here/handler_$1.march" '
    /^@HANDLER@$/ { while ((getline l < hf) > 0) print l; next } { print }' \
    "$here/app.march.in" > "$d/app.march"
  echo "$d/app.march"
}

build() {  # build LOG ARGS...  (never piped: a piped --compile can hang)
  local log="$1"; shift
  if ! "$march" "$@" > "$log" 2>&1; then
    echo "BUILD FAILED: $*"; cat "$log"; exit 1
  fi
}

build "$out/build-base.log" --compile --opt 2 --hot-reload App \
  --ffi-c "$here/shim.c" -o "$out/base" "$(gen v1)"
for v in v1 v2; do
  build "$out/build-$v.log" --compile --compile-so --opt 2 --hot-reload App \
    --ffi-c "$here/shim.c" -o "$out/patch-$v.so" "$(gen $v)"
done
k=0
for v in v2 v1 v2 v1; do
  k=$((k + 1))
  cp "$out/patch-$v.so" "$out/patch$k.so"
  export "HCRPIN_PATCH_$k=$out/patch$k.so"
done

set +e
HCRPIN_N=5000 HCRPIN_DEPLOYS=4 "$out/base" > "$out/run.out" 2> "$out/run.err"
rc=$?
set -e
cat "$out/run.out"
echo "exit=$rc"
if [ $rc -ne 0 ] || grep -qE "AddressSanitizer|LeakSanitizer|runtime error:" "$out/run.err"; then
  echo "--- stderr ---"
  head -60 "$out/run.err"
fi
