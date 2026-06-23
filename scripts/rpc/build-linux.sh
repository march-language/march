#!/usr/bin/env bash
# Cross-compile the two-node RPC demo for linux/amd64 via Docker.
#
# Reuses the `march-builder` toolchain image — a deps-ready ocaml/opam image
# (dune + menhir + clang-18 + llvm-18). The march compiler itself is built
# inside the container from the mounted worktree, so the binaries reflect the
# current source — including the RPC name-resolution + hash fixes.
#
# The image must already exist. Build it ONCE from the MAIN repo (not a git
# worktree — `opam install` there runs `git ls-files`, which fails on the
# worktree's `.git` pointer file inside the container):
#   docker build --platform linux/amd64 -f ci/Dockerfile.ubuntu -t march-builder:latest .
#
# Output: dist/two_node_server_linux, dist/two_node_client_linux
#
# Usage:
#   scripts/rpc/build-linux.sh
#
# Env:
#   IMAGE   builder image (default: march-builder:latest)
#   BD      in-container dune build dir, cached in a named volume (default: /lbuild)
#   VOL     named volume backing BD (default: march-lbuild)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE=${IMAGE:-march-builder:latest}
BD=${BD:-/lbuild}
VOL=${VOL:-march-lbuild}
DIST="$ROOT/dist"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "ERROR: builder image '$IMAGE' not found." >&2
  echo "Build it once from the MAIN repo (not a worktree):" >&2
  echo "  docker build --platform linux/amd64 -f ci/Dockerfile.ubuntu -t $IMAGE ." >&2
  exit 1
fi

mkdir -p "$DIST"

# The named volume is created root-owned; the image runs as user 'opam'. Make it
# writable for the build (idempotent; runs as root just for the chown).
echo "==> preparing cache volume $VOL"
docker run --rm --platform linux/amd64 --user root \
  -v "$VOL":"$BD" "$IMAGE" chown -R opam:opam "$BD"

echo "==> cross-compiling demo binaries (linux/amd64) — first run builds the compiler in-container"
# We build only the compiler with dune, then invoke it directly against a
# COMPLETE runtime dir. Building a single demo target in a fresh dune build-dir
# would only materialize that rule's explicitly-listed deps, missing the rest of
# the runtime closure (march_http.c and friends), which other rules materialize
# in a full `dune build`. Giving the compiler the whole source runtime avoids
# that fragility. march_tls.c is excluded: the demo uses plain TCP, and the
# compiler's OpenSSL header detection is macOS-pathed.
docker run --rm --platform linux/amd64 \
  -v "$ROOT":/march \
  -v "$VOL":"$BD" \
  -v "$DIST":/out \
  "$IMAGE" \
  bash -lc "
    set -euo pipefail
    cd /march
    export MARCH_STDLIB=/march/stdlib
    dune build --build-dir=$BD bin/main.exe
    # Stage a complete runtime dir next to the compiler (exe-relative ../runtime).
    RT=$BD/default/runtime
    mkdir -p \"\$RT\"
    cp -f /march/runtime/*.c /march/runtime/*.h \"\$RT\"/
    rm -f \"\$RT\"/march_tls.c \"\$RT\"/march_tls.h
    MC=$BD/default/bin/main.exe
    \"\$MC\" --compile -o /out/two_node_server_linux demo/two_node_server.march
    \"\$MC\" --compile -o /out/two_node_client_linux demo/two_node_client.march
    chmod +x /out/two_node_server_linux /out/two_node_client_linux
    head -c4 /out/two_node_server_linux | od -An -tx1   # expect 7f 45 4c 46 (ELF)
  "

echo "==> built:"
ls -la "$DIST"/two_node_server_linux "$DIST"/two_node_client_linux
