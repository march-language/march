#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

key=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
out_dir=${MARCH_HCR_TEST_TMP:-${TMPDIR:-/tmp}}

for target in linux/amd64 linux/arm64; do
  arch=${target##*/}
  base="$out_dir/march-hcr-$arch"
  dune exec ./bin/main.exe -- --compile --target "$target" \
    --hot-reload HcrSmoke --signing-pubkey "$key" \
    -o "$base" test/native/hcr_smoke.march
  dune exec ./bin/main.exe -- --compile --compile-so --target "$target" \
    --hot-reload HcrSmoke -o "$base.so" test/native/hcr_smoke.march
  grep -q '^# march-hcr-manifest v2$' "$base.so.hcr_manifest"
  grep -q "^# target $target$" "$base.so.hcr_manifest"
  grep -q '^# module_prefix HcrSmoke$' "$base.so.hcr_manifest"
  base_info=$(file "$base")
  so_info=$(file "$base.so")
  case "$arch:$base_info:$so_info" in
    amd64:*x86-64*:*shared\ object*) ;;
    arm64:*aarch64*:*shared\ object*) ;;
    *) echo "unexpected cross-HCR artifacts for $target: $base_info / $so_info" >&2; exit 1 ;;
  esac
  case "$base_info" in *executable*) ;; *) echo "baseline is not executable: $base_info" >&2; exit 1 ;; esac
done
