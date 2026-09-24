#!/bin/sh
set -eu
target=${1:-linux/amd64}
case "$target" in linux/amd64|linux/arm64) ;; *) exit 2 ;; esac
runner=${MARCH_HCR_RUNNER:-}
if [ -n "$runner" ]; then
  $runner dune exec ./forge/test/test_cross_hcr_e2e.exe -- --target "$target"
else
  dune exec ./forge/test/test_cross_hcr_e2e.exe -- --target "$target"
fi
