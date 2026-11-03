#!/usr/bin/env bash
# install-z3.sh — build the pinned z3 from source into PREFIX.
#
# Usage: scripts/install-z3.sh PREFIX [--static]
#
# Reads the version (line 1) and the source tarball's sha256 (line 2) from
# z3.version at the repo root: the one place the pin lives, read by CI, the
# release build and `march`'s own version check.  Downloads
# github.com/Z3Prover/z3/archive/refs/tags/z3-<version>.tar.gz, refuses it if
# the sha256 differs, builds the z3 executable alone with cmake, and installs
# PREFIX/z3 and PREFIX/LICENSE.txt.
#
# --static links the executable -static.  Linux release archives need it:
# `march` there is a static musl binary that runs on any distribution, and
# z3's own Linux downloads link glibc (specs/2026-11-02-bundled-z3-design.md).
# Build inside Alpine for that.  macOS has no fully static executables;
# --static is refused there.
#
# A PREFIX that already holds the pinned z3 is left alone (exit 0), so a CI
# cache restore makes this a no-op.
set -euo pipefail

usage() { sed -n '2,20p' "$0" >&2; exit 2; }
[ $# -ge 1 ] || usage
prefix="$1"; shift
static=0
while [ $# -gt 0 ]; do
  case "$1" in
    --static) static=1; shift ;;
    -h|--help) usage ;;
    *) echo "install-z3: unknown argument $1" >&2; usage ;;
  esac
done

repo=$(cd "$(dirname "$0")/.." && pwd)
version=$(sed -n 1p "$repo/z3.version" | tr -d '[:space:]')
sha256=$(sed -n 2p "$repo/z3.version" | tr -d '[:space:]')
[ -n "$version" ] && [ -n "$sha256" ] || {
  echo "install-z3: z3.version must hold the version (line 1) and the tarball sha256 (line 2)" >&2; exit 1; }

if [ "$static" = 1 ] && [ "$(uname -s)" = Darwin ]; then
  echo "install-z3: --static is for Linux (musl); macOS has no static executables" >&2; exit 2
fi

if [ -x "$prefix/z3" ] && "$prefix/z3" --version 2>/dev/null | grep -q "Z3 version $version "; then
  echo "install-z3: $prefix/z3 is already z3 $version"
  exit 0
fi

for tool in cmake python3 curl; do
  command -v "$tool" >/dev/null || { echo "install-z3: needs $tool on PATH" >&2; exit 1; }
done
sha_of() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
jobs=$( (nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2) | tr -d '[:space:]')

work=$(mktemp -d "${TMPDIR:-/tmp}/install-z3.XXXXXX")
trap 'rm -rf "$work"' EXIT
tarball="$work/z3-$version.tar.gz"
curl -sSfL --retry 3 --retry-all-errors -o "$tarball" \
  "https://github.com/Z3Prover/z3/archive/refs/tags/z3-$version.tar.gz"
got=$(sha_of "$tarball")
if [ "$got" != "$sha256" ]; then
  echo "install-z3: sha256 mismatch for z3-$version.tar.gz: got $got, z3.version says $sha256" >&2
  exit 1
fi
mkdir "$work/src"
tar -xzf "$tarball" -C "$work/src" --strip-components=1

linker_flags=""
[ "$static" = 1 ] && linker_flags="-static"
cmake -S "$work/src" -B "$work/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DZ3_BUILD_LIBZ3_SHARED=OFF \
  -DZ3_BUILD_TEST_EXECUTABLES=OFF \
  -DZ3_BUILD_PYTHON_BINDINGS=OFF \
  -DZ3_BUILD_DOCUMENTATION=OFF \
  -DZ3_ENABLE_EXAMPLE_TARGETS=OFF \
  -DCMAKE_EXE_LINKER_FLAGS="$linker_flags" > "$work/configure.log" 2>&1 || {
  tail -40 "$work/configure.log" >&2; exit 1; }
# `shell` is z3's name for the target that produces the z3 executable.
cmake --build "$work/build" --target shell -j "$jobs" > "$work/build.log" 2>&1 || {
  tail -40 "$work/build.log" >&2; exit 1; }

mkdir -p "$prefix"
cp "$work/build/z3" "$prefix/z3"
cp "$work/src/LICENSE.txt" "$prefix/LICENSE.txt"
"$prefix/z3" --version | grep -q "Z3 version $version " || {
  echo "install-z3: the built z3 does not report version $version" >&2; exit 1; }
echo "install-z3: installed z3 $version at $prefix/z3"
