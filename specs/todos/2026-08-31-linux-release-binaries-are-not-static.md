`[P1]` # Both Linux release legs are dynamically linked despite `static: true`

Found 2026-08-31 while verifying the first working `linux-aarch64` artifact
(see `specs/progress/2026-08-31-linux-aarch64-release-build-native-arm64.md`).

## The defect

`.github/workflows/build.yml` marks both Linux legs `static: true`, and
`specs/github_release_builds.md` promises "the resulting binary has zero
runtime dependencies and runs on any Linux kernel 3.2+". Neither is true.
`readelf -d` on the artifacts of run 33410265258:

```
linux-x86_64   NEEDED libLLVM.so.18.1, libblake3.so, libz.so.1, libzstd.so.1,
                      libbrotlienc.so.1, libbrotlidec.so.1, libm.so.6, libc.so.6
linux-aarch64  NEEDED libLLVM.so.19.1, libblake3.so, libz.so.1, libzstd.so.1,
                      libbrotlienc.so.1, libbrotlidec.so.1, libc.musl-aarch64.so.1
```

`libblake3.so` in particular is built from source *by the workflow* and exists
on no user's machine at all.

Observed directly: on a bare `alpine:3.21` the aarch64 binary does not start —
it aborts with ~20 `Error relocating ... symbol not found` lines for the LLVM,
zstd and blake3 symbols. It runs correctly once those libraries are installed.

## Why it is like this

`static: true` today gates exactly two things: the `musl-tools` apt install and
the choice of build step. Nothing in the workflow passes `-static` to anything.
The old illustrative snippet in `specs/github_release_builds.md` still shows
`OCAMLPARAM='_,ccopt=-static' dune build --force`; the real workflow has plain
`dune build --force`. Whenever that flag was dropped, the legs kept the label.

This is a *general* release-portability problem, not an ARM one — x86_64 has
the identical shape and has been shipping to users for two releases.

## Acceptance

Either the Linux archives genuinely link statically (and a CI check runs the
produced binary in a scratch container with no dev packages installed), or the
`static: true` label and the "zero runtime dependencies" claim in
`specs/github_release_builds.md` are corrected to say what actually ships and
`install.sh` grows the dependency list.

A test that would have caught this: run `bin/march --version` inside a bare
`alpine:3.21` / `debian:stable-slim` as part of the build job.
