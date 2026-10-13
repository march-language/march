# The v0.5.0 release archives could not compile programs

## Fixed 2026-10-13 (`.github/workflows/build.yml`, `.github/workflows/release.yml`)

Installing the published v0.5.0 (`forge toolchain install v0.5.0`) and compiling any
program failed: `march_blake3.c` includes `third_party/blake3/blake3.h`, and the
archives had no `runtime/third_party/`. `build.yml` packaged `runtime/*.c runtime/*.h`
only; BLAKE3 (2026-09-23, 8b25477ec) and mimalloc were vendored under
`runtime/third_party/` after 0.4.0, and every release check ran the packaged
binaries with `--version` alone, so all three legs published green.

- Both packaging steps now `cp -R runtime/third_party _dist/runtime/` (sources and
  the vendored licenses).
- New step on every leg, "Verify the archive compiles and runs a program": compile
  and run a small program with the packaged compiler from a temp directory, with a
  private `HOME` and `MARCH_RUNTIME_DIR` / `MARCH_STDLIB` unset. Proven locally
  against the real v0.5.0 install: RED as shipped ("cannot compile a program"),
  GREEN with `third_party/` added ("smoke 3").
- `release.yml` gained a `workflow_dispatch` path (`-f tag=vX.Y.Z`) that rebuilds an
  existing tag's sources with the current `build.yml` and replaces that release's
  archives and checksums with `gh release upload --clobber`. The tag-push path is
  unchanged. Used to replace v0.5.0's archives.
