#!/bin/sh
# P1 cross-compilation gate: cross-compile the deterministic examples corpus for
# <arch> and assert every program that runs produces byte-identical output to the
# NATIVE-compiled build (isolates cross-arch codegen bugs from pre-existing
# interpreter-vs-compiled divergences).  Requires zig + docker.
#   Usage: cross_oracle_gate.sh [amd64|arm64]   (default arm64 — native under docker on Apple Silicon)
arch="${1:-arm64}"
here=$(cd "$(dirname "$0")/../.." && pwd)
dune build --root "$here" test/test_oracle.exe 2>/dev/null || { echo "build failed"; exit 1; }
MARCH_ORACLE_CROSS="$arch" MARCH_BIN="$here/_build/default/bin/main.exe" MARCH_ROOT="$here" \
  "$here/_build/default/test/test_oracle.exe"
