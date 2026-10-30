---
layout: docs
title: Supported Platforms
nav_order: 20.1
permalink: /docs/platforms/
---

> Part of the March Language Reference; see [specs/lang/index.md](index.md).

# Supported Platforms

March sorts platforms into three tiers. The tier says what you can rely on: whether a
prebuilt toolchain exists, whether CI tests it, and whether a bug on it can hold back a
release. The three tier-1 platforms were decided on 2026-10-30.

## The tiers

| | Tier 1 | Tier 2 | Tier 3 |
|---|---|---|---|
| Prebuilt toolchain (`install.sh`, `forge toolchain`) | Yes | No | No |
| Tested in CI | Yes (one gap, below) | No | No |
| A bug on it blocks a release | Yes | No | No |
| The four [1.0 claims]({{ site.baseurl }}/docs/claim-deploys/) apply | Yes | No | No |
| Fixes accepted | Yes | Yes | Yes, as best effort |
| Expected to work | Yes | Usually, built from source | Partly, or not at all |

## Tier 1

| Platform | What it is | How it is built | CI tests |
|---|---|---|---|
| `darwin-arm64` | macOS on Apple silicon | Native; links only system libraries at run time | Full suite on macOS 15 (`test (macos-15, all)`, `macos-checks`), except the suites whose answers don't depend on the OS (refinement checker, golden diagnostics, LSP), which run on Linux only |
| `linux-x86_64` | 64-bit Intel/AMD Linux | Built on Alpine, fully static (musl), so it runs on any distribution | Full suite, plus the two-node cluster scenarios, AddressSanitizer, the property oracle and the determinism oracle |
| `linux-aarch64` | 64-bit ARM Linux | Built on Alpine, fully static (musl) | **Built and smoke-tested only**: CI builds the archive and checks that its compiler compiles and runs a program, but runs no test suite on it |

The linux-aarch64 gap is known and must close before 1.0: a tier-1 platform must run the
test suite in CI.

What tier 1 gives you on every tier-1 platform:

- **The toolchain**: `march` and `forge`, with the runtime and standard library, from one
  archive, checksum-verified on install.
- **Compiling to a native binary** (`march --compile`). You need a C toolchain: `clang` and
  LLVM (see [Installation]({{ site.baseurl }}/docs/installation/)).
- **`--static`**: on Linux, a fully static binary when the host uses musl (it is refused on
  glibc); on macOS, a binary that needs nothing outside `/usr/lib` and `/System`.
- **The OS sandbox** (`--cap-sandbox`, `forge cap run`): Seatbelt on macOS, seccomp-bpf
  (x86_64 and aarch64) or bubblewrap on Linux. A binary built with `--cap-sandbox` refuses to
  start on any other platform or CPU architecture rather than running unconfined.
- **Cross-compiling to Linux** (`--target linux/amd64`, `--target linux/arm64`) with
  `zig cc`. These produce dynamically linked glibc binaries. CI checks that cross-compiled
  linux/amd64 output matches the native build byte for byte.

## Tier 2

| Platform | Status |
|---|---|
| `darwin-x86_64` (Intel macOS) | No prebuilt toolchain: `install.sh` says so and points to building from source. Not built or tested by CI. The code has no known reason not to work, but nothing checks it. |

Tier 2 means: you build March yourself, it is expected to work, nobody checks that it does,
and a bug that only happens there does not hold back a release. Fixes are welcome.

## Tier 3

| Platform | Status |
|---|---|
| Windows | **Not supported.** The runtime is written for POSIX (threads, signals, Unix sockets), and no Windows port exists. March is not expected to build there. |
| WASM (`--target wasm32-wasi`, `wasm64-wasi`, `wasm32-unknown-unknown`) | **Experimental.** The compiler can emit WebAssembly. For the browser target (`wasm32-unknown-unknown`) it links a minimal runtime (`runtime/march_runtime_wasm.c`) with no actors, networking, file IO or threads, and memory that is never freed. Some compiler tests check the code it emits; CI runs no program on a WASM runtime. |
| JavaScript (`--target js`) | **Experimental.** Emits an ES module for browsers and Node.js. `Int` there is a 53-bit subset of March's 63-bit `Int`; a CI test checks that subset matches the interpreter. |
| The browser playground | **A demo, not a platform.** It runs the March interpreter compiled to JavaScript. Its `Int` is 32-bit and reports overflow as an error. It has no compatibility promise. |

Tier 3 means: it may work partly or not at all, nothing is promised, and nothing about it
holds back a release. The 1.0 plan lists WASM, Windows and Intel macOS as out of scope for
1.0.

## Moving a platform up a tier

A platform moves to tier 1 when CI builds a prebuilt archive for it, runs the full test suite
on it, and the four 1.0 claims hold there (including `--cap-sandbox`). A platform moves to
tier 2 when it builds from source and someone is willing to keep it building.
