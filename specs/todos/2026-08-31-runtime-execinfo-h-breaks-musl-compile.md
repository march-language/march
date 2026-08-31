`[P2]` # `march --compile` fails on musl: `execinfo.h` is glibc-only

Found 2026-08-31 while exercising the first working `linux-aarch64` release
artifact (see
`specs/progress/2026-08-31-linux-aarch64-release-build-native-arm64.md`).

## The defect

`runtime/march_runtime.c:27` does an unconditional `#include <execinfo.h>`.
That header is a glibc extension; musl does not have it. So on Alpine — which
is exactly what the musl-targeted `linux-aarch64` prebuilt is built for and
most likely to be run on — `march --compile` dies compiling its own bundled
runtime:

```
runtime/march_runtime.c:27:10: fatal error: 'execinfo.h' file not found
   27 | #include <execinfo.h>
```

Confirmed to be the **only** remaining blocker: with `zlib-dev`, `openssl-dev`,
`zstd-dev`, `brotli-dev`, `clang19` and a locally built `libblake3.so` present
in an `alpine:3.21` container, `execinfo.h` is the single `fatal error` left.

The interpreter path is unaffected — `march file.march` runs correctly on musl.
It is only the ahead-of-time compile that breaks, i.e. the aarch64 prebuilt can
interpret March but cannot compile it.

## Likely fix

`execinfo.h` is used for `backtrace`/`backtrace_symbols` in the crash handler.
Guard it (`#if defined(__GLIBC__)`) and degrade to no symbolic backtrace on
musl, rather than dropping the feature for glibc users.

## Acceptance

`march --compile` produces and runs a binary from a hello-world module inside
`alpine:3.21` (aarch64 and x86_64), using only the runtime sources bundled in
the release archive.
