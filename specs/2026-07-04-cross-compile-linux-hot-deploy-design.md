# Cross-Compilation to Linux (Go-style) for Hot Deploy

## Status: P1 shipped (cross-build main binary, compute/HTTP, no TLS); P3 shipped (OpenSSL/TLS + zlib/gzip for the main binary). P2 (`forge deploy hot --target`) still pending.

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
3. **De-host-ify the build path — the load-bearing, and largest, workstream.**
   The `march --compile` build path is riddled with assumptions that the build
   host *is* the target. Each must key off the **target config**, not the host.
   These are not a handful of one-liners; they are the dominant risk and effort
   of this feature. Known instances (audit for more — grep `Sys.file_exists`,
   `Sys.os_type`, `/opt/homebrew`, `-m`, `/proc/`):
   - **Arch-specific codegen flags.** `-msse4.2` is passed unconditionally at
     **two** sites (`bin/main.ml:500` runtime `.so` precompile, `bin/main.ml:2117`
     final link). SSE4.2 is x86-only; on `linux/arm64` `zig cc` rejects it. Gate
     `-m*` flags by **target arch** (SSE/AVX only on x86_64; arm64 gets NEON by
     default, no flag). This breaks arm64 on the very first compile if missed.
   - **`--compile-so` link flags.** Selected by probing the build host:
     `if Sys.file_exists "/proc/version" then -Wl,--allow-shlib-undefined else
     -undefined dynamic_lookup` (`bin/main.ml:2033`). A Mac building a Linux `.so`
     picks the macOS flag. Key off target OS instead.
   - **External-lib discovery embeds host paths.** OpenSSL (`bin/main.ml:413`) and
     zstd/brotli (`bin/main.ml:470`) are found by probing the host filesystem and
     then linked with **macOS lib paths** baked in (`-L/opt/homebrew/lib`). For a
     cross target these must resolve against the *target* sysroot/vendored libs,
     never `/opt/homebrew`. (See §5.)
   - **Dynamic-linker flags.** `-rdynamic`/`-export_dynamic` must follow the
     target, and `-ldl` (needed on Linux for `dlopen`, absent on macOS libc) is
     *also* gated on a host probe today: `... && Sys.file_exists "/proc/version"`
     (`bin/main.ml:2041`) — so a cross Linux main binary would **omit `-ldl` and
     fail to link `dlopen`**. Gate on target OS.

   Enforcement: these host probes are scattered `if`s, not a single switch. When
   the `target_config` gains the Linux variants, thread the target through to
   each site and prefer making the OS/arch decision a **total function over
   `target_config`** so OCaml's exhaustiveness warning flags any site that still
   silently assumes the host.
4. **Runtime linking from source (main binary only).** The host build reuses a
   precompiled `libmarch_runtime.so` cache (`bin/main.ml:337`), which is host-only.
   For a cross **main binary**, compile the runtime C sources **from source** with
   `zig cc` into the artifact (the native path already links runtime sources
   directly), keyed per target in the cache. The reload **`.so`** is the opposite:
   it links **no** runtime and **no** external C libs — its runtime/OpenSSL/zlib
   symbols are left undefined and resolved at `dlopen` time from the running main
   binary's process image. So a cross reload `.so` needs only the correct target
   triple, `zig cc -target`, and the target-OS undefined-symbol flag from §3.3 —
   not a sysroot's worth of libraries.

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

### 5. External C link dependencies (OpenSSL, zlib, zstd, brotli)

The **main binary** dynamically links several external C libraries — OpenSSL
(`libssl`/`libcrypto`), zlib (`-lz`, **always** linked, `bin/main.ml:484`), and
optionally zstd/brotli. On the host these are found by probing the local
filesystem and linked with homebrew paths; for a cross target that is wrong on
two counts (host paths, host arch). Handling:

- The main **executable cannot defer undefined symbols** the way a `.so` can, so
  the cross-linker genuinely needs a *target* copy of each library at link time
  — not just at runtime. Provide them per arch, cached under `~/.cache/march`
  keyed by arch + library versions, via either:
  - **extracting `.so` + headers from the target distro package** (e.g. unpack
    Ubuntu's `libssl3`/`zlib1g` `.deb`) — easiest, and guarantees the soname/ABI
    matches the droplet; or
  - **cross-building with `zig cc`** — more control, more fiddle. Recommend
    extraction first; keep cross-build as the fallback for libs not packaged
    conveniently.
- Replace host-path discovery (OpenSSL `bin/main.ml:413`; zstd/brotli
  `bin/main.ml:470`) with a target-aware resolver: host → homebrew/system as
  today; cross → the vendored target libs. Never emit `-L/opt/homebrew/lib` on a
  cross link.
- **Simplest scoping for a first cut:** compression is optional
  (`march_compress.c` guards zstd/brotli behind `-DMARCH_HAVE_*`, and zlib is the
  only mandatory one). P1 may **disable zstd/brotli** for cross and provide only
  target `libz` + OpenSSL, adding the optional codecs later.
- **Reload `.so`s need none of this at link time** — the runtime opens them with
  `dlopen(path, RTLD_NOW | RTLD_GLOBAL | RTLD_DEEPBIND)` (`runtime/march_reload.c:293`),
  so their undefined `libssl`/`libz`/runtime symbols resolve against the
  process-wide dynamic symbol table — i.e. libraries already loaded as `NEEDED`
  dependencies of the main binary (not "from the main binary" itself, unless a
  lib were statically embedded). This is why reload units cross-compile with zero
  external libs. **Caveat:** because resolution is by *symbol name*, the reload
  `.so` must be built against the **same OpenSSL/zlib major (soname + version)**
  as the main binary — an OpenSSL 1.1-vs-3.x mismatch surfaces as a cryptic
  `dlopen` "undefined symbol" at activation, not a link error. The main binary
  and reload `.so` sharing one target config (the ABI invariant) already enforces
  this; state it so nobody builds a reload `.so` against different headers.
- Match the droplet's OpenSSL major (**3.x**) and zlib soname. Record the
  assumption; a mismatch (e.g. a droplet still on OpenSSL 1.1, or LibreSSL) is a
  clear, early error, not a runtime surprise. Post-P1, record the linked
  OpenSSL/zlib sonames in the deploy manifest and verify them before activating a
  reload — turning the cryptic `dlopen` failure into an actionable message.

### 6. FFI cross-compilation

Projects with C shims (`[ffi]`) or a Rust binding crate (`[ffi.rust]`) currently
build those deps **for the host**, unconditionally:

- `[ffi.rust]` runs `cargo build --release` with **no `--target`**
  (`forge/lib/cmd_build.ml:350`) → an `…-apple-darwin` staticlib that cannot link
  into a Linux binary.
- `[ffi]` C shims are compiled with the host compiler/flags.

For a cross build these must target Linux too:

- **C shims** → compile with `zig cc -target <triple>` (same driver as the main
  build).
- **Rust staticlib** → `cargo build --release --target <rust-linux-triple>` with
  a cross-linker. The clean way is **`cargo-zigbuild`** (or setting
  `CARGO_TARGET_*_LINKER="zig cc -target …"`), reusing the same `zig` we already
  depend on, so no separate C cross-toolchain is introduced. The Rust target
  (`x86_64-unknown-linux-gnu` / `aarch64-unknown-linux-gnu`) must be installed
  via rustup — forge should detect and hint.

**Scope decision (needs confirmation):** cross-building FFI deps — especially the
Rust path — is real, separable work. Recommend **v1 supports FFI-less apps and C
shims; `[ffi.rust]` cross-build lands in a follow-up (P2/P3)**, with a clear
error ("this project uses [ffi.rust]; cross-compilation of Rust bindings is not
yet supported — build on Linux or use `--so`") rather than a silent host-arch
link failure. A full-server app may well use FFI, so this must be an explicit,
visible limitation, not an omission.

### 7. forge changes

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
  overrides (see §6). Keep it optional — flags work with zero config.
- **`forge deploy hot` integration** (`cmd_deploy_hot.ml`): teach `build_so`
  (`cmd_deploy_hot.ml:803`) to pass the cross `--target` into
  `march --compile --compile-so`, so the deployed `.so` is Linux-native. The
  existing `--so` escape hatch stays for anyone still pre-building elsewhere.
  Ensure the main binary and reload `.so` are built with the **same** target
  config (the ABI invariant above).

### 8. Cache

The CAS key already folds in a `target_label` (`bin/main.ml:1152-1166`,
`compilation_hash ... ~target:target_label ~flags:cas_flags`), but that label
today enumerates only `native`/`wasm*`/`js` — the new Linux variants must extend
it, and **must be distinct per arch + glibc floor** (a `linux/amd64` and
`linux/arm64` build of the same source must not alias, nor alias `native`). Make
the label a total function over `target_config` so OCaml's exhaustiveness warning
forces the new cases in. Additionally fold the **cross-toolchain identity** — zig
version, glibc floor, and the target OpenSSL/zlib versions — into `cas_flags`,
since two builds identical except for the bundled toolchain are not
interchangeable. Verify with a value-revealing program across two targets (e.g.
one that prints `sizeof`/arch-dependent output), not a parity check.

## Phasing

Even though TLS is required for the end state, phase so the cross-toolchain is
proven before OpenSSL:

1. **P1 — cross-build the dynamic main binary, compute/CLI + plain HTTP, no TLS.**
   Proves `zig cc` + glibc target + the compiler driver + forge plumbing
   end-to-end. This is where the §3.3 de-host-ify audit happens: gate `-msse4.2`
   by arch (required for arm64 to build at all), fix the `so_flag`/`-ldl` host
   probes, fix host-path lib discovery, and provide target **zlib** (`-lz` is
   linked even for plain HTTP). Defer zstd/brotli. **P1 also lands the compiler's
   `--target` acceptance for *both* `--compile` and `--compile-so`** (they share
   the driver) and the forge threading — including the `[ffi.rust]` **guard error**
   (§6), so an FFI project fails loudly instead of silently linking a host-arch
   staticlib. Smoke-test the ELF under Docker/QEMU on both arches.
2. **P2 — `forge deploy hot --target` end-to-end (the reload path).** With the
   `--compile-so` cross support already in from P1, P2 wires it into `build_so`
   (`cmd_deploy_hot.ml:803`, which today drops `--target`) and proves a live
   Mac→(QEMU/Docker droplet) hot swap: validates the ABI invariant and the
   target-aware `so_flag` fix against a running server.
3. **P3 — OpenSSL/TLS + zlib/gzip. ✅ DONE (2026-07-07).** Cross-linked target
   OpenSSL 3 + zlib for the main binary. Optional zstd/brotli codecs,
   soname-manifest and glibc-floor runtime checks remain deferred. What shipped:
   - **Sysroot cache + fetch helper.** `scripts/fetch-cross-sysroot.sh
     <amd64|arm64>` populates `~/.cache/march/cross-sysroot/linux-<arch>/{lib,include}`
     by extracting Debian **bookworm** `libssl3`/`libssl-dev`/`zlib1g`/`zlib1g-dev`
     `.deb`s (via `ar` + `tar` — `dpkg-deb` not required) so the soname/ABI
     matches `debian:bookworm-slim` (OpenSSL `libssl.so.3`/`libcrypto.so.3`, zlib
     `libz.so.1`). It resolves exact filenames from the suite `Packages.gz` index
     (pinned to bookworm — the flat pool dir mixes in trixie/sid), with pinned
     known-good fallbacks, and copies the multiarch `openssl/opensslconf.h`
     (Debian ships it under `usr/include/<multiarch>/openssl`, not
     `usr/include/openssl`) into `include/openssl/`.
   - **Compiler resolver + error** (`bin/main.ml` `cross_sysroot_dir`): env
     override `MARCH_CROSS_SYSROOT_<ARCH>` / `MARCH_CROSS_SYSROOT` → `~/.cache`
     cache; a cache miss emits a clear, actionable error naming the fetch script
     (no silent auto-download).
   - **Link path** (`bin/main.ml`, `is_cross` block): keeps `march_tls.c` +
     `march_compress.c` (they cross-compile against the target headers), still
     drops `march_blake3.c` (needs a target `libblake3` we don't vendor) and
     `march_reload.c` (HCR-over-cross is out of scope). OpenSSL/zlib are linked by
     **direct positional `.so` paths** (`<sr>/lib/libssl.so.3` etc., NOT `-l:` /
     `-L` — lld can't find them via `-l:`), with `-I<sr>/include`, and **no**
     `-L/opt/homebrew/lib` host paths. zstd/brotli stay off for cross (zlib is the
     only mandatory codec; gzip/deflate is pure zlib).
   - **glibc floor 2.36.** Bumped the `LinuxGnu` default from `2.31`→`2.36`
     (`parse_target`). This is mandatory for TLS: the target `libcrypto.so.3`
     references `GLIBC_2.34` symbols (`pthread_getspecific`, `dlsym`/`dlclose` —
     where libdl merged into libc) plus `stat@2.33`; a lower floor's libc doesn't
     provide them, so `ld.lld --no-allow-shlib-undefined` rejects the link. 2.36
     exactly matches bookworm. **Portability implication:** cross binaries now
     require glibc ≥ 2.36 (bookworm+); pre-bookworm distros are no longer a
     target. `zig_target` already appends the floor (`x86_64-linux-gnu.2.36`).
   - **CAS key.** A 12-hex digest of the three sysroot `.so` files is folded into
     `cas_flags` (both the source-level early cache and the inner link cache), so
     a sysroot re-fetch that changes the linked OpenSSL/zlib invalidates cached
     cross binaries (the glibc floor is already in `target_label`).
   - **Validation is link-structure only on the Mac** (`file` + `DT_NEEDED` lists
     `libssl.so.3`/`libcrypto.so.3`/`libz.so.1` for both amd64 and arm64;
     regression test `test_codegen.ml` "cross_compile"). **Runtime** (not just
     link) validation of the HTTPS/gzip round-trip happens on the actual droplet
     at deploy time — the cross host can't execute the Linux ELF.

## Testing

The strongest correctness lever is **already on main**: the differential oracle
(`test/test_oracle.ml`, `test/test_properties.ml:703` `oracle_check`) runs every
`.march` in `bench/`, `examples/`, and the curated golden corpus
(`specs/lang/golden/`, spec'd by `specs/lang/core-march.md`) through the
**interpreter vs native-compiled** backends and diffs stdout, with a skip
allowlist for actors/servers/nondeterminism. Comparison is backend-agnostic
(string equality); executor invocation is a plain subprocess. We extend it rather
than inventing ad-hoc smoke tests.

- **Differential cross-compile gate (primary).** Add a **third executor**:
  `march --compile --target linux/<arch> … && run under Docker/QEMU`, diffed
  against the interpreter oracle exactly as the native path is. This turns the
  entire deterministic corpus into a cross-arch codegen conformance suite — it is
  precisely what catches datalayout/endianness/arch-flag/ABI divergences on the
  target (e.g. a wrong `-m` flag, a struct-layout or integer/float-printing bug
  that only manifests on aarch64). The comparison layer is unchanged; only the
  executor invocation is new, and the existing skip allowlist already excludes
  the categories a cross binary can't run headless (actors, networking). This is
  the highest-value, lowest-effort test win and should land with P1.
  - Formalize the currently-hardcoded interp/native invocations into a small
    `executor` abstraction (the oracle has no such interface yet) so a third
    backend drops in cleanly and a fourth (WASM/JS) is free later.
  - Deterministic-output normalization is already the corpus's job — reuse it;
    do not build a parallel normalization path.
- **Link/shape gate.** Assert cross output is a valid Linux ELF of the right arch
  (`file`/`readelf`) — a cheap pre-filter on macOS before paying for QEMU.
- **Hot-reload gate.** End-to-end `forge deploy hot --target` against a container
  "droplet": deploy, activate, hit the swapped function, assert new behavior — the
  real proof the ABI invariant (and the `so_flag`/soname story) holds cross-target.
  Not expressible in the oracle (it needs a running server + control plane), so it
  stays a dedicated integration test.
- **TLS/HTTP integration gate (P3).** HTTPS round-trip on the cross binary under a
  container — also outside the oracle's pure-stdout model.
- **CI.** Run the differential cross gate on **macOS runners** (so the actual
  macOS→Linux cross path is exercised, not a native-Linux build) with QEMU for
  arm64; keep a native-Linux job as a control.

## Risks & mitigations

- **Host-probe leaks — the biggest correctness risk AND biggest effort.** The
  build path assumes host == target in many places: `-msse4.2` (breaks arm64),
  `so_flag` host probe, homebrew OpenSSL/zstd/brotli paths (`-L/opt/homebrew/lib`
  into an ELF), `-ldl`/`-rdynamic` vs `-export_dynamic`, host `cargo` target. →
  Systematic audit (Design §3.3) is the core of P1; the arch-flag one fails
  immediately on arm64, the hot-reload gate catches `so_flag`, and a
  wrong-arch-lib link fails loudly.
- **ABI drift between main binary and reload `.so`** → single source of target
  config in forge, passed identically to both invocations; assert triple/flags
  match in the deploy manifest.
- **External-lib cross-linking (OpenSSL, zlib, zstd, brotli)** → prefer extracting
  target `.so`+headers from the distro package over cross-building; P1 may ship
  zlib+OpenSSL only and defer optional codecs. Reload `.so`s sidestep it entirely
  (§4, §5).
- **FFI cross (esp. Rust)** → host-pinned `cargo build` today; v1 limitation with
  a clear error, `cargo-zigbuild` in a follow-up (§6).
- **glibc floor too high** → configurable; default conservative (2.31); surfaced
  in `forge.toml`. Deploying to an *older* target than the floor fails with a
  cryptic `dlopen`/loader "version `GLIBC_2.xx' not found". Post-P1, add a
  `march_check_glibc_version()` at runtime init (compare `gnu_get_libc_version`
  against the built floor) for an actionable startup error.
- **Soname/version mismatch of OpenSSL/zlib** between build and droplet →
  cryptic `dlopen` "undefined symbol" at reload activation. Record linked sonames
  in the deploy manifest and verify pre-activation (§5).
- **zig version skew** (bundled clang/glibc changes across zig releases) →
  pin/record a known-good floor; test against it in CI.
- **Runtime C regressions leaking macOS-only APIs** (unguarded `sysctlbyname`,
  `mach_*`, `CommonCrypto`) → current code is correctly `#ifdef __APPLE__`-guarded;
  add a CI lint that greps cross builds for unguarded macOS symbols to prevent
  future regressions.
- **Testing without native arm64 Linux** → QEMU for arm64; document the slower
  path.

## Related work / dependencies

Builds directly on the **differential oracle + executable language spec** landed
on main (`specs/archive/2026-07-04-differential-oracle-design.md`,
`specs/archive/2026-07-04-language-specification-roadmap-design.md`, `test/test_oracle.ml`,
`specs/lang/`). This feature's primary test gate is a third oracle executor (see
Testing); conversely, extending the oracle to cross-compiled binaries stresses the
corpus on real arch diversity and feeds the language-spec conformance effort.

## Future work (explicitly out of scope now)

- **Static-musl "ship-a-`scratch`-image" profile** — the immutable-container
  sibling. Reuses the zig driver + target model; adds musl-cleanliness (small
  thread-stack fix, `backtrace()` gaps, musl-built FFI + OpenSSL) and drops HCR.
  Would surface as a second deployment profile (`--target linux/arm64` static +
  no-HCR) alongside this dynamic one.
- **`forge`-built Docker images** — a thin wrapper over the emitted binary.
- **Windows / BSD targets.**
