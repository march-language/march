# Both Linux release legs are genuinely static now

Filed 2026-08-31 as `[P1]`, fixed 2026-09-02. Background:
`specs/progress/2026-08-31-linux-aarch64-release-build-native-arm64.md`.

## The defect

`.github/workflows/build.yml` marked both Linux legs `static: true` and
`specs/github_release_builds.md` promised "zero runtime dependencies and runs
on any Linux kernel 3.2+". Neither was true. `static: true` gated exactly two
things — an apt install and the choice of build step — and nothing passed
`-static` to anything. Both legs shipped binaries `NEEDED`ing libLLVM,
libblake3, libz, libzstd, libbrotli{enc,dec} and libc, for two releases.

Reproduced locally, byte for byte with the filed report: a `march` built in the
Alpine leg's own configuration lists exactly the seven NEEDED entries in the
report, and on a bare `alpine:3.21` aborts before `main`:

```
Error loading shared library libLLVM.so.19.1: No such file or directory
Error relocating /b/march: BrotliEncoderCompress: symbol not found
...
```

`libblake3.so` is the sharpest edge: it is built from source *by this workflow*
and is packaged by neither Alpine nor Ubuntu 24.04. That also rules out the
cheap alternative of correcting the label and documenting a dependency list —
there is no list a user could act on for libblake3.

This was never an ARM problem. x86_64 had the identical shape.

## The decision

Two options were on the table: (a) make the archives genuinely static, or
(b) correct the label and the docs. (a) was chosen after being demonstrated to
work end to end locally — (b) is not actually actionable for libblake3, per
above.

Feasibility was established before committing to it. The hard part, static
libLLVM, links cleanly: a C probe using the LLVM 19 C API (ORC/LLJIT + native
target) links fully static on `alpine:3.21` aarch64 against the `llvm19-static`
archives.

## What changed

- **`lib/jit/detect_llvm.sh`** — with `MARCH_STATIC_LLVM=1`, emit
  `llvm-config --link-static --libs orcjit native` plus `--system-libs` and
  `-lstdc++`, instead of `-lLLVM-<n>`. `-lstdc++` is needed because the
  archives are C++ objects that `libLLVM.so` used to carry. A plain dev build
  does not set the variable and links dynamically exactly as before.

- **`lib/eval/discover_compress.ml`** — the Linux branch now lists
  `-lbrotlicommon` last. Against shared objects the loader follows brotli's own
  `DT_NEEDED` and this is a no-op, which is why its absence went unnoticed;
  against `.a` archives it is ~30 undefined references
  (`BrotliDefaultAllocFunc`, `_kBrotliPrefixCodeRanges`, ...). The macOS branch
  already did this.

- **`.github/workflows/build.yml`** —
  - **The x86_64 leg moved into Alpine**, joining aarch64. It previously built
    on the Ubuntu host against glibc, and a static *glibc* link is a trap
    rather than a fix: it succeeds, then `getaddrinfo`/NSS fail at runtime
    because the NSS modules are dlopened. Both legs are still native-arch; no
    QEMU is involved on either.
  - The Alpine step installs the `*-static` packages (`llvm19-static`,
    `brotli-static`, `zlib-static`, `zstd-static`, `libxml2-static`,
    `openssl-libs-static`, `g++`/`libstdc++-dev`), builds `libblake3.a`
    alongside the existing `.so`, picks blake3's SIMD sources by `uname -m`,
    and builds with `MARCH_STATIC_LLVM=1 OCAMLPARAM='_,ccopt=-static'`.
    `--force` is load-bearing: the flag sexps are dune *rule* outputs and a
    cached one would be reused with the old dynamic flags.
  - The now-dead `musl-tools` install and host x86_64 build step are gone, as
    is the unreachable Linux branch of the host system-dependency step.

- **`specs/github_release_builds.md`** — the "Linking" column, a new
  § "What 'static' costs, and how it is enforced", and the archive layout
  (which had never listed the bundled `runtime/`).

## The acceptance test — the actual point

New build-job step, **`Verify the archive runs on a bare system`**, running the
produced `march` and `forge` inside bare `alpine:3.21` *and*
`debian:stable-slim` with `--entrypoint`, plus a `readelf -d` assertion of no
`NEEDED` entries. It runs before `strip`, like the binaries-exist check above
it, and for the same reason.

Both images earn their place, and this is measured, not assumed: alpine catches
a binary that still wants a shared library; debian additionally catches one
that is merely musl-*dynamic*, which alpine runs happily.

Every check that existed before ran on the build machine — where libLLVM,
libblake3, libzstd and libbrotli are installed *because this same job installed
them*. That is precisely why the defect survived two releases and a checksum
verification.

The oracle was proven in both directions against the two real artifacts, rather
than assumed:

| artifact | alpine march/forge | debian march/forge | `readelf -d` | verdict |
|----------|--------------------|--------------------|--------------|---------|
| today's dynamic build | fail / fail | fail / fail | 7 NEEDED | exit 1 |
| the static build      | ok / ok      | ok / ok      | none        | exit 0 |

The static binary additionally runs on `ubuntu:22.04` and
`gcr.io/distroless/static-debian12`, and can still `--compile` and run a
hello-world when a C toolchain is present.

## Cost, stated plainly

- **Size.** `march` 24.5 MB dynamic → **57 MB stripped** static (the LLVM
  archives). `forge` is 7.2 MB stripped.
- **No `dlopen`.** musl's static libc returns "Dynamic loading not supported"
  (verified with a C probe: identical source, dynamic vs `-static`). On the
  **Linux prebuilts only**, that means interpreted `extern` FFI
  (`lib/eval/eval.ml`'s dlopen-based marshal layer) does not work, and the
  REPL's `--jit` falls back to the interpreter — a graceful degradation, since
  `repl_jit` already treats a failed dlopen as "not compiled".
  Both are lazy paths: plain interpretation never reaches them, which is why
  `march hello.march` works fine on the static binary.
- Interpreting, `--compile`, and `forge` are unaffected. macOS prebuilts and
  builds from source keep both features.

## Method note

All of the above was established in Docker on an arm64 Mac, where
`alpine:3.21` runs natively — minutes per iteration instead of ~100-minute CI
round trips. `march-alpine-base` / `march-alpine-deps` images (Alpine + the
opam 5.3.0 switch + deps) make a full compiler rebuild about five minutes.

## Related

`2026-09-02-runtime-execinfo-h-breaks-musl-compile.md` — the same
investigation; `march --compile` did not work on musl at all.

## Known adjacent, NOT fixed here

`specs/docker_images.md` claims a *compiled March program* is "a statically
linked native binary (musl on Linux)". It is not: a hello-world compiled on
Alpine still needs libssl, libcrypto, libz, libzstd, libbrotli{enc,dec},
libblake3, libucontext and libc. That is a separate defect about user program
output, not about the compiler archives, and is untouched by this change.
