#!/bin/sh
# Run a cross-built glibc Linux binary in a matching container.
# Usage: run_under_docker.sh <amd64|arm64> <binary-path>
set -e
arch="$1"; bin="$2"
case "$arch" in
  amd64) platform="linux/amd64" ;;
  arm64) platform="linux/arm64" ;;
  *) echo "unknown arch: $arch" >&2; exit 2 ;;
esac
# debian:bookworm-slim ships glibc 2.36 (>= our 2.31 floor). Mount the binary read-only.
dir=$(cd "$(dirname "$bin")" && pwd)
base=$(basename "$bin")
exec docker run --rm --platform "$platform" \
  -v "$dir/$base":/work/prog:ro \
  debian:bookworm-slim /work/prog
