# Cross-Compilation to Linux (Go-style) for Hot Deploy

## Status: Design — not yet implemented

## Summary

Let a developer on macOS produce **Linux** artifacts — the initial dynamic
server binary **and** the `--compile-so` hot-reload units — without a Linux box,
Docker round-trip, or CI detour. The target UX mirrors Go's `GOOS=linux`:

```
forge build --target linux/arm64          # cross-build the dynamic main binary
forge deploy hot --target linux/arm64      # cross-build + ship reload .so's straight to the droplet
```

The mechanism is **`zig cc`** as the cross C toolchain (it bundles a clang plus
glibc/musl sysroots for Linux x86_64 and arm64), driven by `forge`, extending
the target machinery that already exists for the WASM/JS targets.

## Motivation

Today March is host-pinned. The native target triple is baked in at
*compiler-build time* (`lib/tir/native_triple_stub.c`), so `march --compile`
always emits for the build host. Hot deploy makes this concrete and painful:

- `forge deploy hot` builds the reload `.so` **locally** with
  `march --compile --compile-so` (`forge/lib/cmd_deploy_hot.ml:803`), CAS-uploads
  just that `.so` + manifest to the droplet (`cmd_deploy_hot.ml:451`), and the
  droplet `dlopen`s it — the **server compiles nothing**.
- On a Mac, that `.so` is `arm64-apple-macosx` and **cannot load** on a Linux
  droplet.
- The code already concedes this. `deploy`'s `--so` flag exists precisely so you
  can *"[use] a pre-built .so ... built in Docker for a remote Linux host ...
  without a local rebuild"* (`cmd_deploy_hot.ml:827`).

So the current answer to "hot-deploy from a Mac" is **"build the `.so` in Docker,
then `forge deploy hot --so linux_artifact.so`."** This feature removes that
Docker round-trip for both artifacts.

## Chosen profile: dynamic, hot-deploy-capable

Hot-code-reload is `dlopen`/`dlsym` at runtime, which a **fully static** binary
cannot do (no dynamic loader in the process). Therefore the hot-deploy path is
**dynamically linked**. Stock droplets are Ubuntu/Debian, so the default libc is
**glibc**, targeted at a configurable minimum version.

This spec covers **only** the dynamic hot-deploy profile. The static-musl
"ship-a-`scratch`-image" profile is a natural sibling but is explicitly a
**non-goal here** (see Future Work) — it can reuse most of this machinery later.

### Two artifacts, one target config

| Artifact | Compiler mode | Links OpenSSL? | Ships to droplet as |
|---|---|---|---|
| Initial main binary | `march --compile` (dynamic) | **yes**, at link time | the process (via existing deploy/scp) |
| Reload unit | `march --compile --compile-so` | **no** — resolves OpenSSL symbols from the loaded main binary at `dlopen` time | CAS-uploaded `.so` |

**Invariant:** the main binary and every reload `.so` for a given deploy MUST be
cross-built with an **identical target config** — same triple, data layout,
optimization level, and ABI — or `dlopen` symbol resolution breaks. This is
already true host-locally today; cross-compilation must preserve it across the
two invocations.

## Goals

- `forge build --target linux/{amd64,arm64}` emits a runnable dynamic ELF for
  that target from macOS.
- `forge deploy hot --target linux/{amd64,arm64}` cross-builds the reload `.so`
  and deploys it with no Docker step.
- Full server runtime intact on the target: scheduler, actors, HTTP, **TLS**.
- No new *mandatory* system dependency beyond a single self-contained `zig`
  install, discovered by forge with a clear install hint if absent.
- Host builds (`forge build` with no `--target`) are byte-for-byte unaffected.

## Non-goals (this iteration)

- Static musl / `FROM scratch` images (Future Work).
- `forge`-built Docker images (emit the binary; Dockerfiles stay the user's).
- Windows / BSD / bare-metal targets.
- Cross-compiling *to* macOS from Linux (symmetry not required for the use case).
- Server-side compilation (the droplet keeps compiling nothing).

## Background: what already exists to build on

- The codegen already emits **textual LLVM IR with a parameterized `target
  triple` header** and shells out to a C compiler — this is exactly how WASM
  cross-compiles today (`--target=... --sysroot=...`, `bin/main.ml:1893`).
- `target_config` is a pluggable enum (`lib/tir/llvm_emit.ml:167`) with per-target
  triple + pointer size; native is the only host-pinned arm.
- The CAS artifact cache key already includes a target label + runtime-source
  digests + codegen flags, so per-target artifacts won't collide (verify the
  cross triple is in the key — see Cache).
- `forge`'s `--target` flag already flows CLI → `cmd_build.compile_entry`
  (`forge/lib/cmd_build.ml:383`) → `march --compile`, and output paths already
  fork on target (`.mjs`/`.wasm`).

The dynamic-glibc choice keeps the runtime-porting cost low: the C runtime
**already compiles and runs on Linux/glibc** (that is what a Linux dev box
produces today). We are changing the *build host* and *toolchain*, not the
target libc family — so the deep musl-cleanliness audit is avoided.

## Design

### 1. Toolchain: `zig cc`

`zig cc -target <zig-triple>` is a drop-in clang that ships its own glibc/musl
headers and sysroots for Linux x86_64/arm64 — no external sysroot to fetch, no
cross-binutils. It is the standard tool the Go/cgo community reaches for to
cross-compile C to static or version-pinned-glibc Linux binaries.

- forge discovers `zig` on `PATH`; if missing, it errors with an install hint
  (`brew install zig` / download link) rather than a cryptic clang failure.
- Version floor recorded in forge (a known-good zig ≥ the version whose bundled
  glibc/musl and clang we test against).
- zig target strings: `x86_64-linux-gnu.<ver>`, `aarch64-linux-gnu.<ver>`.

### 2. Target model & naming

Accept Go-style `os/arch` aliases at the forge layer and normalize to a triple:

| forge `--target` | LLVM triple | zig `-target` |
|---|---|---|
| `linux/amd64` (aka `linux/x86_64`) | `x86_64-unknown-linux-gnu` | `x86_64-linux-gnu.<ver>` |
| `linux/arm64` (aka `linux/aarch64`) | `aarch64-unknown-linux-gnu` | `aarch64-linux-gnu.<ver>` |

`<ver>` is the **minimum glibc** version. Default targets a broad baseline
(proposed **2.31** = Ubuntu 20.04 / Debian 11-era); overridable via forge config
(`--glibc <ver>` or `forge.toml`). Higher = fewer targets but newer symbols;
lower = wider reach.

### 3. Compiler changes (`bin/main.ml`, `lib/tir/llvm_emit.ml`)

1. **Cross native targets.** Extend `target_config` / `parse_target`
   (`llvm_emit.ml:167`, `bin/main.ml:560`) with explicit Linux cross variants
   carrying an arch + triple, e.g. `LinuxGnu { arch; glibc_min }`. `target_triple`
   returns the LLVM triple instead of `Lazy.force native_triple`. Pointer size is
   8 for both arches (no data-layout change).
2. **C-compiler driver.** Today the link step hardcodes `clang`
   (`bin/main.ml:2054`). Introduce a driver abstraction: when the target is a
   cross variant, invoke `zig cc -target <zig-triple>` instead of `clang`; the
   runtime C sources, `.ll` file, and link flags pass through unchanged. Host and
   WASM paths keep their current compilers.
3. **Target-aware link flags — the load-bearing fix.** The `--compile-so` link
   step currently selects its "allow undefined, resolve at dlopen" flag by
   probing the **build host**:
   `if Sys.file_exists "/proc/version" then -Wl,--allow-shlib-undefined else
   -undefined dynamic_lookup` (`bin/main.ml:2033`). Under cross-compile this is
   wrong — a Mac building a Linux `.so` would pick the macOS flag. Switch this
   (and any other host probes: OpenSSL path discovery `bin/main.ml:413`, dynamic
   linker `-ldl`/`-rdynamic` vs `-export_dynamic`) to key off the **target
   config**, not the host OS. Audit `bin/main.ml` for `Sys.file_exists
   "/proc/..."`, `Sys.os_type`, and homebrew-path assumptions.
4. **Runtime linking from source.** The host build reuses a precompiled
   `libmarch_runtime.so` cache (`bin/main.ml:337`), which is host-only. For cross
   targets, compile the runtime C sources **from source** with `zig cc` into the
   artifact (the native path already links runtime sources directly), keyed per
   target in the cache.

### 4. Runtime C considerations (`runtime/*.c`)

Low risk because the target is glibc, which the runtime already supports. Work is
confined to making sure zig's bundled glibc headers satisfy the runtime and that
no macOS-only path leaks into a Linux build:

- `march_scheduler.c`: pthreads + `SIGUSR1` preemption — POSIX, present under
  glibc. No change expected.
- `march_http.c`: epoll on Linux is already gated (`#if defined(__linux__)`);
  cross-compiling *defines* `__linux__` via the target, so the Linux path is
  selected correctly. Apple-only `TCP_NOPUSH` etc. compile out.
- `march_extras.c`: `#ifdef __APPLE__` blocks compile out; confirm the Linux
  branches are complete (no macOS-only symbol left unguarded).
- Confirm nothing relies on a glibc version newer than the chosen floor
  (e.g. recent `statx`, `pidfd_*`, `renameat2` usage) — if so, either raise the
  floor or add a fallback.

### 5. OpenSSL / TLS

Only the **main binary** links OpenSSL; reload `.so`s resolve OpenSSL symbols
from the already-loaded main binary at `dlopen` time (that is the whole point of
`--allow-shlib-undefined`). So OpenSSL cross-support is a **main-binary-only,
one-time** cost:

- Cross-build (or vendor prebuilt) target OpenSSL 3.x with `zig cc` for each
  arch, **dynamically** (`libssl.so.3` / `libcrypto.so.3` + headers), cached
  under `~/.cache/march` keyed by arch + OpenSSL version. The dynamic droplet
  provides the runtime `.so`; we need it only to satisfy the cross-linker.
- Replace the homebrew-path OpenSSL discovery (`bin/main.ml:413`) with a
  target-aware resolver: host → homebrew as today; cross → the cached target
  OpenSSL.
- Match the droplet's OpenSSL major (3). Record the assumption; a mismatch is a
  clear, early error, not a runtime surprise.

### 6. forge changes

- **CLI/aliases** (`forge/bin/main.ml`, `forge/lib/cmd_build.ml`): accept
  `linux/amd64`|`linux/arm64` (+ `x86_64`/`aarch64` synonyms), normalize to the
  compiler's cross-target flag, thread through `compile_entry`
  (`cmd_build.ml:383`).
- **Per-target output dirs**: extend the `debug/`|`release/` split to
  `.march/build/<target>/<profile>/<name>` so a Linux binary never clobbers the
  host binary (`cmd_build.ml:561`).
- **zig discovery + hint** with actionable error if absent.
- **`forge.toml`** (`forge/lib/project.ml`): optional `[build]` (or
  `[target.<name>]`) block for default target(s), glibc floor, and per-target FFI
  overrides. Keep it optional — flags work with zero config.
- **`forge deploy hot` integration** (`cmd_deploy_hot.ml`): teach `build_so`
  (`cmd_deploy_hot.ml:803`) to pass the cross `--target` into
  `march --compile --compile-so`, so the deployed `.so` is Linux-native. The
  existing `--so` escape hatch stays for anyone still pre-building elsewhere.
  Ensure the main binary and reload `.so` are built with the **same** target
  config (the ABI invariant above).

### 7. Cache

Confirm the CAS key already distinguishes the cross triple (it includes a target
label + runtime digests + codegen flags). If the cross-toolchain identity (zig
version, glibc floor, target OpenSSL) is *not* in the key, add it — otherwise a
host artifact and a cross artifact with the same source could alias. Verify with
a value-revealing program across two targets, not a parity check.

## Phasing

Even though TLS is required for the end state, phase so the cross-toolchain is
proven before OpenSSL:

1. **P1 — cross-build the dynamic main binary, compute/CLI + plain HTTP, no TLS.**
   Proves `zig cc` + glibc target + the compiler driver + forge plumbing
   end-to-end; flushes out any host-probe leaks. Smoke-test the ELF under
   Docker/QEMU.
2. **P2 — `--compile-so` cross + `forge deploy hot --target`.** The reload path;
   validates the ABI invariant and the target-aware `so_flag` fix against a live
   (or QEMU) droplet.
3. **P3 — OpenSSL/TLS.** Cross-linked target OpenSSL for the main binary; full
   HTTPS server on the target.

## Testing

- **Link/shape gate**: assert cross-built output is a valid Linux ELF of the
  right arch (`file`/`readelf`) — catches toolchain regressions cheaply on macOS.
- **Run gate**: execute cross-built binaries under a Linux container (amd64
  native, arm64 via QEMU or an arm64 runner) — compute, HTTP, then HTTPS.
- **Hot-reload gate**: end-to-end `forge deploy hot --target` against a
  container "droplet": deploy, activate, hit the swapped function, assert new
  behavior — the real proof the ABI invariant holds cross-target.
- **CI**: add a Linux job; keep the macOS→Linux cross job on macOS runners so the
  actual cross path is exercised, not just a native Linux build.

## Risks & mitigations

- **Host-probe leaks** (biggest correctness risk): logic keyed off the build
  host instead of the target — `so_flag`, `-ldl`/`-rdynamic`, OpenSSL paths. →
  Systematic audit (Design §3.3); the hot-reload gate catches the `so_flag` case.
- **ABI drift between main binary and reload `.so`** → single source of target
  config in forge, passed identically to both invocations; assert triple/flags
  match in the deploy manifest.
- **OpenSSL cross-build friction** → isolated to P3; dynamic (not static) linking
  is the easier case, and reload `.so`s sidestep it entirely.
- **glibc floor too high** → configurable; default conservative (2.31); surfaced
  in `forge.toml`.
- **zig version skew** (bundled clang/glibc changes across zig releases) →
  pin/record a known-good floor; test against it in CI.
- **Testing without native arm64 Linux** → QEMU for arm64; document the slower
  path.

## Future work (explicitly out of scope now)

- **Static-musl "ship-a-`scratch`-image" profile** — the immutable-container
  sibling. Reuses the zig driver + target model; adds musl-cleanliness (small
  thread-stack fix, `backtrace()` gaps, musl-built FFI + OpenSSL) and drops HCR.
  Would surface as a second deployment profile (`--target linux/arm64` static +
  no-HCR) alongside this dynamic one.
- **`forge`-built Docker images** — a thin wrapper over the emitted binary.
- **Windows / BSD targets.**
