# Static and self-contained `march --compile` output

**Date:** 2026-09-23
**Status:** design. Nothing here is implemented.
**Closes (when all stages land):** `specs/todos/2026-09-02-march-compile-output-is-not-static.md` [P2]
**Unblocks:** the `scratch` deploy variant that `specs/docker_images.md` defers
(its §"Non-goals" bullet and open item 6 both point at the todo above).
**Method:** every claim in §2 was checked on 2026-09-23 against the tree at
`154cf1754`, either by opening the cited file or by building and running a
program. Where something could not be checked, it says so. All binary
measurements are aarch64 (this Mac is arm64; the Linux containers run natively
under Docker, no QEMU).

---

## 0. Decisions needed

Each is a question, a recommendation, and the reason. §4 has the alternatives.

**D1. What decides which runtime pieces and libraries a program links?**
*Recommendation:* the linker decides for objects, and the compiler's record of
the C symbols its output calls decides for libraries. Ship the C runtime as a
static archive (`libmarch_rt.a`) so the linker pulls in only the members the
program references. On dynamic links, add `-Wl,--as-needed` (Linux) or
`-Wl,-dead_strip_dylibs` (macOS). For `--static`, and to produce a clean
"library missing" diagnostic, choose the `-l` list from
`Llvm_builtins.called_c_symbols ()` mapped through a per-member library table.
*Why:* this is the only sound signal. Declared capabilities cannot drive it:
`Compress` declares no capability (`stdlib/compress.march:20` has no `needs`),
and `needs IO.NetConnect` covers both TLS and plaintext TCP
(`specs/lang/capabilities.md:169-170`). Measured in §2.5: the archive alone
cuts a hello-world's non-libc dependencies from seven to zero on macOS and on
both Linux libcs.

**D2. How does libblake3 leave user binaries?**
*Recommendation:* vendor upstream BLAKE3's portable C (`blake3.c`,
`blake3_dispatch.c`, `blake3_portable.c`, `blake3.h`, `blake3_impl.h`) at a
pinned tag into `runtime/vendor/blake3/`, compiled with all SIMD disabled.
*Why:* the runtime hashes one short string per hot-reload activation
(`runtime/march_reload.c:654`), so SIMD buys nothing. The portable build is
about 14 KB of text (§2.6). The license (CC0-1.0 / Apache-2.0 /
Apache-2.0-with-LLVM-exception) allows vendoring. Keep the compiler's own
`lib/cas` on the system libblake3 for now; that is the release pipeline's
concern (§3.1).

**D3. How do zstd/brotli stop depending on the build host?**
*Recommendation:* split `march_compress.c` into one file per codec. Link a
codec when, and only when, the program calls it. If the program calls a codec
whose library is missing, fail at compile time with a message naming the
package. Remove the runtime stubs that return
`Err("… not available — install … and rebuild")`.
*Why:* today the build host's headers change **both the dependency set and
program behaviour**. Measured in §2.4: the same source and the same compiler
produce a working Zstd program on one host and a program that prints
`zstd unavailable` on another, and the CAS then serves the stale binary across
the change. After this change the host decides only whether the build succeeds,
never what the binary does.

**D4. Which libc does `--static` use on Linux?**
*Recommendation:* musl only. On an Alpine/musl host, `--static` links natively.
Anywhere else it requires `--target linux/<arch>-musl` (a new target, built
with `zig cc`). On a glibc host without that target, `--static` is a clear
error, not a glibc static link.
*Why:* a static glibc link *works* for everything measured here, including DNS
in a bare `scratch` container (§2.7). But it links with three
"requires at runtime the shared libraries from the glibc version used for
linking" warnings (`getaddrinfo`, `gethostbyname`, `dlopen`). Those mean any
NSS module beyond files/dns (nss-resolve, LDAP, mDNS), plus iconv and locales,
silently depends on the host again. The release pipeline made the same call
for the compiler's own binaries (`.github/workflows/build.yml:33-39`).

**D5. What does `--static` mean on macOS?**
*Recommendation:* "self-contained". The only load commands allowed are
`/usr/lib/*` and `/System/*` dylibs. OpenSSL, zstd and brotli link from their
static archives. The mode is enforced by a post-link `otool -L`-equivalent
check that fails the build.
*Why:* a fully static Mach-O executable is not supported (`libSystem` is
always dynamic). What users actually lose today is portability to a Mac without
Homebrew: the current hello-world loads six `/opt/homebrew` dylibs (§2.3).
Homebrew already ships every archive needed except blake3, and D2 removes that
one.

**D6. Does capability-driven linking become the default for ordinary dynamic
builds?**
*Recommendation:* yes, for executables that are not built with
`--hot-reload`. Hot-reload server builds keep linking the whole runtime.
*Why:* a reload `.so` resolves OpenSSL and every runtime symbol *from the base
binary* (`-Wl,--allow-shlib-undefined`, `bin/main.ml:3148-3155`). A base binary
that dropped `march_tls.o` would reject a later patch that starts using TLS.
The dead-strip mode already carves out the same case (`bin/main.ml:3290-3299`).

**D7. Where does a static binary find CA certificates?**
*Recommendation:* do not embed a bundle. Document `SSL_CERT_FILE` /
`SSL_CERT_DIR` (OpenSSL's standard overrides, honoured by
`SSL_CTX_set_default_verify_paths`, `runtime/march_tls.c:176`) and the
`COPY --from=… ca-certificates.crt` line for `scratch` images. Embedding
becomes an opt-in flag only if users ask for it.
*Why:* measured in §2.7, TLS in `scratch` fails without a bundle and succeeds
with `SSL_CERT_FILE`. An embedded bundle would go stale inside every binary
ever built.

---

## 1. The problem

`march --compile` links every program against the full C runtime and every
library any part of it could need. A pure-compute program depends on OpenSSL,
zlib, zstd, brotli and libblake3. libblake3 has no distro package (the release
workflow clones and builds it, `.github/workflows/build.yml:110`, `:199`). The
program therefore cannot run in `scratch` or distroless, and it cannot run on a
stock slim base without hand-copying a library. The zstd/brotli part of the set
also depends on which headers the build host happened to have installed.

The todo is explicit that appending `-static` is not a fix (its
"Non-acceptance" section). §2.5 shows why concretely: on the image that happens
to have every static archive installed, a naive `-static` works. On Ubuntu it
fails on the first missing archive. On macOS it cannot work at all.

---

## 2. Ground truth (verified 2026-09-23)

### 2.1 How the driver links

All of this is the native branch of `compile` in `bin/main.ml`.

- **Runtime sources are always passed as objects.** `runtime_extra_c`
  (`bin/main.ml:3025-3052`) names every `http`, `core` and `hcr` file from
  `runtime/sources.list`. The `hcr` files are dropped only under
  `--compile-so`. That includes `march_tls.c`, `march_compress.c`,
  `march_reload.c` and `march_blake3.c`, whether or not the program uses them.
- **Library flags are probed per invocation.**
  - OpenSSL: a fixed list of Homebrew prefixes, then `pkg-config --exists
    openssl` (`:3058-3082`).
  - zlib always, plus zstd/brotli **when their headers exist at a hard-coded
    path** (`/opt/homebrew/include/…` or `/usr/include/…`, `:3092-3112`). The
    probe adds `-DMARCH_HAVE_ZSTD` / `-DMARCH_HAVE_BROTLI` as well as `-l`.
  - blake3: `Toolchain.blake3_link_flags` (`bin/toolchain.ml:648`) reads
    `March_cas.Blake3_flags`, which `lib/cas/discover.ml` generates. That
    probe prefers `libblake3.a` on macOS when one exists; none exists on this
    Mac.
  - `-lucontext` on musl (`bin/toolchain.ml:669-684`).
- **A second copy of the probes** builds the REPL/JIT runtime `.so`
  (`Toolchain.ensure_runtime_so`, `bin/toolchain.ml:770`, OpenSSL `:844`,
  compression `:877-895`). Any change here needs both copies, or one shared
  helper.
- **Dead-stripping exists but cannot remove a library.** Executables that are
  not built with `--hot-reload` get `-Wl,--gc-sections` plus
  `-ffunction-sections -fdata-sections` on Linux, and `-Wl,-dead_strip` on
  macOS (`:3290-3310`, the cap-audit "capability by absence" work). Sections
  go, but a `DT_NEEDED` / `LC_LOAD_DYLIB` is recorded for every `-l` that
  resolved any symbol of any *input object*, before stripping. `march_tls.o` is
  always an input object, so `libssl` is always needed. Measured in §2.5:
  adding `-dead_strip_dylibs` to today's macOS command changes nothing, while
  removing `march_tls.c` from the inputs drops libssl/libcrypto.
- **Precompiled runtime objects.** `March_cas.Runtime_archive.ensure`
  (`bin/main.ml:3408-3455`) caches the runtime `.o` files, keyed on cflags that
  include the `-D`/`-I` from the probes. Its header documents a deliberate
  choice: "no static-archive member-selection semantics are introduced"
  (`lib/cas/runtime_archive.ml:33-37`). D1 reverses exactly that choice, on
  purpose.
- **Cross builds** (`--target linux/<arch>`, glibc only: `LinuxGnu` is the only
  Linux variant, `lib/tir/llvm_toplevel.ml:80-89`) use `zig cc`, link
  OpenSSL/zlib against a Debian-bookworm sysroot
  (`scripts/fetch-cross-sysroot.sh`), switch zstd/brotli off, and drop
  `march_blake3.c` and `march_reload.c` (`bin/main.ml:3330-3392`).
- **`--ffi-link`** flags are appended verbatim after the runtime libraries
  (`:3125`) and enter the CAS key through `ffi_cas_tag` (`:258`).

### 2.2 What the runtime's optional parts are, and who reaches them

| Runtime file | Libraries | Referenced from other runtime C? | Reached by |
|---|---|---|---|
| `march_tls.c` | libssl, libcrypto (`:31-34`) | No. Every other `march_tls_*` hit is the unrelated `march_tls_reductions` thread-local in `march_scheduler.c`. | `stdlib/tls.march` builtins; `Cap_symbols` maps each to `IO.NetConnect.TLS` (`lib/caps/cap_symbols.ml:130-138`) |
| `march_compress.c` | libz; libzstd, libbrotli{enc,dec} under `#ifdef` (`:312`, `:398`) | No (the only hit, `march_extras.c:244`, is a comment) | `stdlib/compress.march`, which declares no capability |
| `march_blake3.c` | libblake3 | Only `march_reload.c:654` (`march_blake3_hex`) | `march_reload_server_start`, called only from the `--hot-reload` entry (`lib/tir/llvm_toplevel.ml:942`) |
| everything else | libc, libm (+ libucontext on musl) | — | always |

`Crypto.sha256` does not use OpenSSL; it is the in-house SHA-256 in
`march_extras.c` (`sha256_transform`, `:77`). No user-visible stdlib function
reaches BLAKE3: a grep of `stdlib/*.march` for `blake3` returns nothing.

**The declare preamble lists every builtin.** `hello.ll` has 467 `declare`
lines, including `@march_tls_*`, `@march_zstd_*` and
`@march_reload_server_start`. So "is it declared in the IR" is useless as a
signal. The signal that already exists is `Llvm_builtins.called_c_symbols ()`
(`lib/tir/llvm_builtins.ml:1980`): the C symbols the emitted code actually
resolved. The cap-audit markers are built from it
(`lib/tir/llvm_toplevel.ml:1480-1490`), and `forge cap inspect` already
depends on it being complete.

### 2.3 Re-measured dependency sets (today's driver)

Programs (all under this session's scratch dir, never `test/native/`):

- `hello`: `println` only.
- `pure`: `main() : Int` with no I/O.
- `tlsp`: `Tls.client_ctx(Tls.default_client_config())`.
- `gz`: a gzip round-trip.
- `zs`: a zstd round-trip.
- `sha`: `Crypto.sha256`.
- `netp`: `Tls.https_get("example.com", 443, "/")`, so DNS + TCP + TLS + a
  certificate check.

On each platform all of these compiled and ran correctly, and **all of them had
the identical dependency set.** The link line does not depend on the program.

**macOS arm64** (Apple clang 17.0.0, ld-1230.1). Worktree
`_build/default/bin/main.exe`, runtime resolved exe-relative to
`_build/default/bin/../runtime` (confirmed from `MARCH_ECHO_CC=1`;
`diff -rq runtime _build/default/runtime` is empty). Command:
`MARCH_ECHO_CC=1 main.exe --compile -o hello_mac hello.march; otool -L hello_mac`

```
/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib
/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib
/usr/lib/libz.1.dylib
/opt/homebrew/opt/zstd/lib/libzstd.1.dylib
/opt/homebrew/opt/brotli/lib/libbrotlienc.1.dylib
/opt/homebrew/opt/brotli/lib/libbrotlidec.1.dylib
/opt/homebrew/opt/blake3/lib/libblake3.0.dylib
/usr/lib/libSystem.B.dylib
```

Size: 78,520 bytes.

**Linux, Ubuntu 24.04 glibc** (`march-sbx-test-ubuntu:latest`: clang 18.1.3,
OCaml 5.3.0 opam switch, libblake3 prebuilt in `/usr/local/lib`). The compiler
was built in the container from a copy of this worktree at `154cf1754`
(`dune build --root . bin/main.exe`, container-local `_build`,
`MARCH_RUNTIME_DIR=/tmp/work/runtime`). Command:
`readelf -d /tmp/p/hello | grep NEEDED`.

```
libssl.so.3 libcrypto.so.3 libz.so.1 libzstd.so.1 libbrotlienc.so.1
libbrotlidec.so.1 libblake3.so libm.so.6 libc.so.6
```

`ldd` adds `libbrotlicommon.so.1` (transitive) and resolves `libblake3.so` to
`/usr/local/lib/libblake3.so`, which is not packaged. Size: 90,712 bytes.

**Linux, Alpine 3.21 musl** (`march-alpine-deps:1`: clang 19.1.4, the CI
leg's `*-static` packages, `libblake3.{a,so}` in `/usr/lib`; `libucontext-dev`
had to be `apk add`ed). Built the same way.

```
libssl.so.3 libcrypto.so.3 libz.so.1 libzstd.so.1 libbrotlienc.so.1
libbrotlidec.so.1 libblake3.so libucontext.so.1 libc.musl-aarch64.so.1
```

Size: 90,544 bytes. This matches the todo's 2026-09-02 list exactly.

### 2.4 The zstd/brotli probe changes behaviour, and the CAS hides it

In the Ubuntu container (`zs` program, same compiler binary throughout):

| Step | Output | NEEDED count |
|---|---|---|
| Built normally | `zstd zstd zstd zstd` | 9 |
| `mv /usr/include/zstd.h …hidden`, recompile | `compiled … (cached)`, `zstd zstd zstd zstd` | 9 |
| same, after `rm -rf .march/cas/artifacts-v2` | `zstd unavailable` | 8 (no libzstd) |

Two defects are shown here:

1. **Behaviour depends on the host.** Without the header, `march_compress.c`
   compiles its stubs (`:382-394`, `:480-492`), which return `Err` at run
   time. A program that type-checks and compiles cleanly fails in production
   only because the build box lacked a `-dev` package.
2. **The whole-binary CAS key omits the probe result.** `build_cas_key`
   (`bin/main.ml:981-1018`) folds in opt level, codegen tags, FFI, cross
   sysroot and so on, but not `compress_flags2` or `openssl_flags2`. The
   runtime *object* cache does key on them (`:3438-3446`). The whole-binary
   short-circuit runs first, though, so a stale artifact wins. This is a
   same-machine staleness bug independent of everything else here, and is
   Stage 0 below.

### 2.5 Linking through a runtime archive (measured)

The experiment: `ar rcs libmarchrt.a` over the same runtime objects the driver
compiles, then link `prog.ll libmarchrt.a <the same -l list> -lm
<gc-sections|dead_strip>`, plus `-Wl,--as-needed` placed *before* the libraries
on glibc and `-Wl,-dead_strip_dylibs` on macOS.

Non-libc dependencies of the dynamic links that result:

| Program | macOS | Ubuntu glibc | Alpine musl |
|---|---|---|---|
| hello, pure, sha | none | none | none (`libucontext` stays) |
| tlsp | libssl, libcrypto | libssl, libcrypto | libssl, libcrypto |
| gz, zs | libz, libzstd, libbrotli{enc,dec} | libz, libzstd, libbrotli{enc,dec} | same |

Every binary ran with correct output. Three observations:

- **`--as-needed` is positional, and Ubuntu's clang does not default it.** It
  must come before the `-l` flags. Placed after them, the Ubuntu link kept all
  nine entries. Alpine's toolchain defaults to as-needed, so the same test
  passed there without the flag. The driver must pass it explicitly.
- **Granularity is the source file.** `gz` needs zstd and brotli only because
  the three codecs share `march_compress.c`. Splitting that file (D3) fixes
  this.
- **macOS confirms that the object, not the flag, is the lever.**
  `-dead_strip_dylibs` added to today's command dropped nothing; the same flag
  with the archive dropped everything unused.

Static links (`-static`, archive, `--gc-sections`), sizes after `strip`:

| Program | Alpine musl | Ubuntu glibc |
|---|---|---|
| hello | 133,200 | 801,008 |
| pure | 133,200 | 735,472 |
| gz | 198,744 | 866,544 |
| tlsp | 4,284,536 | 4,887,200 |

Every one reports "statically linked" and has no `NEEDED`. The OpenSSL cost is
about 4.1 MB on musl, which is the size case for linking TLS only when it is
reached. No blake3 archive was needed on Ubuntu: the archive never pulls
`march_blake3.o` for a program without `--hot-reload`.

**macOS self-contained (D5):** `tlsp` and `netp` linked against Homebrew's
`libssl.a`/`libcrypto.a` through the archive load only
`/usr/lib/libSystem.B.dylib` (`tlsp`: 4,616,096 bytes). Both ran, and `netp`
fetched `https://example.com`. Its certificate check read Homebrew's
`OPENSSLDIR`, which a Mac without Homebrew lacks, so D7 applies on macOS too.
Homebrew has `.a` files for openssl@3, zstd and brotli. It has none for blake3.

**Naive `-static` on today's link line** (the todo's Non-acceptance):

- Ubuntu: `ld: cannot find -lblake3` for every program, including `hello`.
- Alpine (`march-alpine-deps:1`, which preinstalls CI's full `*-static`
  package list and a hand-built `libblake3.a`): it links and runs. `hello` is
  12,102,128 bytes unstripped and 133,200 stripped, the same as the archive
  build, because `--gc-sections` removes the code. So on a fully provisioned
  musl box the naive flag is not *wrong*. It demands every archive (including
  `libssl.a` for `hello`), and it fails with a raw linker error the moment any
  one is missing. That is the todo's objection, now measured.

### 2.6 BLAKE3 facts

- The runtime's only use is `march_blake3_hex` on the joined cap string of an
  `ACTIVATE` (`runtime/march_reload.c:654`). It must agree byte-for-byte with
  the compiler's `March_cas.Blake3`; `test/test_blake3_agreement.c` (rule at
  `test/dune:791-806`) proves that today.
- Upstream tag 1.8.2 (checked out for measurement): the portable set above is
  1,561 lines. Compiled with `-DBLAKE3_NO_SSE2 -DBLAKE3_NO_SSE41
  -DBLAKE3_NO_AVX2 -DBLAKE3_NO_AVX512 -DBLAKE3_USE_NEON=0` it is about 14 KB of
  text (`blake3.o` 5.8 KB, `blake3_portable.o` 8.0 KB, `blake3_dispatch.o`
  0.2 KB). It ships `LICENSE_CC0`, `LICENSE_A2` and `LICENSE_A2LLVM`. Homebrew
  here has 1.8.6. Which tag to pin is left to Stage 1.
- The release workflow clones BLAKE3 **unpinned** (`--depth 1`, default
  branch) and notes that SIMD units are mandatory once `blake3_dispatch.c` is
  compiled with SIMD enabled (`.github/workflows/build.yml:110-120`). With the
  `NO_*` defines and `USE_NEON=0` the dispatcher needs none (verified: the
  three objects compile clean on arm64 macOS). Whether the portable-only
  archive also *links* clean on x86_64 is not verified.

### 2.7 Static binaries in `scratch` (measured)

Images built by `docker import` of a tarball containing only the binary. No
shell, no libc, no `/etc` except what Docker bind-mounts (`resolv.conf`,
`hosts`).

| Binary | musl static | glibc static | today's dynamic `hello` |
|---|---|---|---|
| hello | `hi` | `hi` | `exec /hello: no such file or directory` |
| tlsp | `tls ctx ok` | `tls ctx ok` | — |
| netp, no CA bundle | `certificate verify failed` | `STORE routines::unregistered scheme` | — |
| netp, `-e SSL_CERT_FILE=/ca.pem` + bundle in image | `OK HTTP/1.1 200 OK` | `OK HTTP/1.1 200 OK` | — |

So DNS resolution worked in `scratch` under both libcs; the glibc static link
used its built-in files/dns backends. What fails is certificate lookup, which
D7 handles. The dynamic row is the red half of the CI check in §6.

**Cross-built from macOS:** `zig cc -target aarch64-linux-musl -static` (zig
0.16.0) over the core runtime members produced a static ELF that printed `hi`
in `scratch` (2,770,488 bytes unstripped, with debug info). It **failed**
first with `undefined symbol: getcontext / makecontext / swapcontext`: zig's
bundled musl has no ucontext, like every musl. It linked only after Alpine's
`libucontext.a` was copied in. The cross musl profile therefore needs either a
target `libucontext.a` in its sysroot or a runtime-owned context switch (§8).

### 2.8 The distributed-deploys plan

`specs/plans/2026-09-21-distributed-authority-and-deploys-plan.md` ships code to
hosts as **hot patches over a long-lived base binary**:

- §5: "Each runs one build … whose base image changes only when the C runtime
  or the build's make-up changes" (line 464-465).
- §6.5: when the patch stack gets long, "the reconciler rebuilds that build's
  base image" (lines 720-723).
- §6.8: `forge deploy` picks "hot patch … rolling restart (the C runtime
  changed …)" (lines 746-748).
- Host setup is `forge host init` over ssh with a generated systemd unit
  (lines 478-485).

Nowhere does it say whether the base binary is static or dynamic. It has **no
dependency on this item**. Its model does rule out one thing: patches are
`dlopen`ed `.so`s that resolve symbols from the base binary, and a fully static
executable cannot `dlopen` (the cross-compile design, "Chosen profile:
dynamic, hot-deploy-capable"). The plan's hosts must stay on the dynamic,
full-runtime profile, which D6 guarantees by exempting `--hot-reload` builds.
Its "base image changes only when the C runtime changes" does benefit from D3
(a base binary's dependency set becomes a function of the source) and from
Stage 0 (a rebuilt base cannot be a stale CAS hit).

---

## 3. Reconciliation with other specs

### 3.1 The compiler's own release binaries

The todo calls itself a sibling of
`specs/todos/2026-08-31-linux-release-binaries-are-not-static.md`. That file
is no longer on main. It closed as
`specs/progress/2026-09-02-linux-release-binaries-are-not-static.md` (#401,
`df4920f88`): both Linux release legs now build in Alpine with
`OCAMLPARAM='_,ccopt=-static'` and `MARCH_STATIC_LLVM=1`
(`.github/workflows/build.yml:152`). A step runs the archive in bare
`alpine:3.21` and `debian:stable-slim` containers and fails on any `NEEDED`
(`:262-287`). That is the pattern §6 reuses.

It is distinct from this item. It is about the `march`/`forge` executables and
their OCaml-side libblake3 link (`lib/cas/dune`). This item is about the
binary a user's program becomes. The only coupling is BLAKE3: once
`runtime/vendor/blake3/` exists, `lib/cas`'s stubs could compile the same
sources, and the release workflow's unpinned clone could go. That is listed as
an optional follow-up, not a stage, because it changes the compiler's build and
not user output.

### 3.2 The static-musl profile in the cross-compile design

`specs/2026-07-04-cross-compile-linux-hot-deploy-design.md` chose the dynamic,
glibc, hot-reload-capable profile and scoped a "Static-musl ship-a-`scratch`-
image profile" as future work. That profile "reuses the zig driver + target
model; adds musl-cleanliness … musl-built FFI + OpenSSL, and drops HCR".

**What shipped:** P1 and P3 (cross main binary, OpenSSL + zlib against a
bookworm sysroot). **What did not:** anything musl or static. There is no musl
target variant (§2.1), and the fetch script pulls glibc Debian `.so` files
only.

**What this design reuses:**

- the `target_config` variant and `zig_target` mapping: add
  `LinuxMusl { arch }` next to `LinuxGnu`;
- the sysroot cache and override convention (`cross_sysroot_dir`,
  `MARCH_CROSS_SYSROOT_<ARCH>`), with a second fetch mode that extracts
  Alpine's `openssl-libs-static`, `zlib-static`, `zstd-static`,
  `brotli-static` and `libucontext-dev` `.apk`s instead of bookworm `.deb`s;
- the cross-sysroot digest in the CAS key (`bin/main.ml:984-995`), unchanged.

The "musl-cleanliness" items it listed are partly done already:
`<execinfo.h>` is guarded (`specs/progress/2026-09-02-runtime-execinfo-h-breaks-musl-compile.md`),
and `-lucontext` is wired for native musl (`bin/toolchain.ml:676`). "Drops
HCR" matches D6.

### 3.3 `specs/docker_images.md`

It already defers its `scratch` variant to the todo (line 23 and item 6). When
Stage 4 lands, that variant becomes a documentation follow-up. The Dockerfile
needs the `ca-certificates.crt` copy from D7.

---

## 4. Options considered

### 4.1 Selection signal (D1)

| Option | Sound? | Notes |
|---|---|---|
| **A. Declared capabilities** (`needs`, `Cap(...)`) | No | Compression has no capability. `IO.NetConnect` covers TLS and plain TCP. Stdlib modules' `needs` are the stdlib's, not the program's. Useful as documentation only. |
| **B. Reachable builtins after mono/DCE** (`called_c_symbols`) | Yes for code the compiler emits. An over-approximation, because it is taken before LLVM's own DCE. | Misses runtime→runtime references. That only matters for choosing `-l` flags, and a miss shows up as a link error, never as a silently wrong binary. |
| **C. The linker** (runtime archive + as-needed / dead_strip_dylibs) | Yes by construction | Needs no table. Cannot help `--static`, where a missing archive fails before selection. |
| D. Scan the `.ll` text for call sites | Fragile | Duplicates B less reliably. |

**Chosen: C for objects and dynamic libraries, B for choosing the `-l` list and
for the missing-library diagnostic.** The one runtime-internal edge that B
cannot see, `march_reload.o → march_blake3.o`, disappears with vendoring,
because it becomes an object edge inside the archive and needs no `-l`. The
per-member library table lives in `runtime/sources.list` as a new column
(§5.2), so `check-runtime-sources.sh` can police it.

### 4.2 BLAKE3 (D2)

1. **Vendor the portable C (chosen).**
2. Vendor with SIMD: needs per-arch `.S`/NEON units and dispatch; pointless
   for one hash per activation.
3. Require `libblake3.a`: still no distro package.
4. Reimplement with the compiler's OCaml hash: impossible, the runtime is C.
5. Replace BLAKE3 in the ACTIVATE protocol: a protocol change, out of scope.

### 4.3 zstd/brotli determinism (D3)

1. **Split per codec, link on use, fail at compile time if absent (chosen).**
2. Make both mandatory: every build host needs zstd and brotli dev files, and
   every binary that compresses carries them.
3. Opt-in flag (`--with-zstd`): deterministic, but a program that calls
   `Compress.Zstd` without the flag must still be diagnosed, which is option 1
   with extra ceremony.
4. Vendor zstd/brotli sources: large and a long-term security-patch burden.
   Rejected. (Size not measured here.)
5. Keep the probe and add its result to the CAS key: fixes staleness only
   (that is Stage 0), not host-dependent behaviour.

### 4.4 libc for `--static` (D4)

| | musl | glibc |
|---|---|---|
| Static link supported upstream | yes | "works", with runtime-shared-library warnings for NSS, `dlopen`, iconv |
| DNS in `scratch` (measured) | yes | yes (files/dns built in); other NSS modules no |
| Size, hello stripped | 133 KB | 801 KB |
| Allocator | mallocng. `march_alloc` is `calloc` per object (`runtime/march_runtime.c:425`), so allocation-heavy programs feel it. | ptmalloc |
| Cross from macOS | `zig cc` bundles musl | would need a static glibc sysroot |

The glibc warnings came from `march_runtime.c` (`getaddrinfo`, core, so every
program has it) and from libcrypto (`dlopen`, `gethostbyname`).

**Allocator cost is unmeasured.** A `bench/binary_trees.march` comparison was
attempted (musl dynamic vs glibc dynamic, both containers) but runs about 0.25
s, and host load average was 22. The five-run spreads (0.22–0.32 s musl,
0.18–0.72 s glibc) overlap completely. Stage 4 must measure it properly: a
larger input, compiled, same-box A/B. If mallocng costs more than about 10%,
link mimalloc (MIT) into static builds as an open follow-up. Don't guess ahead
of the numbers.

---

## 5. Chosen design

### 5.1 Flags and meaning

- **Default (dynamic), executable, not `--hot-reload`:** the runtime links as
  `libmarch_rt.a`, and libraries are chosen from `called_c_symbols`. Linux
  gets `-Wl,--as-needed` before the `-l` list; macOS gets
  `-Wl,-dead_strip_dylibs`. The binary depends on libc (+libm, +libucontext on
  musl) plus exactly the libraries its reached members need.
- **`--hot-reload` servers and `--compile-so`:** unchanged. Full runtime as
  objects (D6).
- **`--static`:**
  - Linux: musl only. Native on a musl host, or with `--target
    linux/<arch>-musl`. On a glibc host without that target, the build stops
    with an error that names `--target linux/<arch>-musl` and the Alpine
    route.
  - macOS: self-contained per D5.
  - Incompatible with `--hot-reload` and `--compile-so`; that is an error.
  - `--ffi-link` flags pass through. A user `-lfoo` that resolves only to a
    `.so` fails the post-link check (§5.4), and the failure names it.
- **CAS:** add `static` to `cas_flags`, plus a `libsel:<sorted lib list>` tag
  (the resolved library set, including which variant: `.a`/`.so`/Homebrew
  path). Two builds that link differently can then never share an artifact.

### 5.2 `runtime/sources.list` grows a column

```
#   file                    role    jit   libs
march_tls.c                 http    -     ssl,crypto
march_compress_gzip.c       core    -     z
march_compress_zstd.c       core    -     zstd
march_compress_brotli.c     core    -     brotlienc,brotlidec,brotlicommon
march_blake3.c              hcr     -     -     (now over the vendored sources)
```

The vendored files live in `runtime/vendor/blake3/`. They get a new role,
`vendor`: linked whenever their parent member is linked, never named directly
by a driver list. `check-runtime-sources.sh` Check 1 currently globs only
`runtime/*.c`. It must also glob `runtime/vendor/**/*.c`, or a vendored file
could silently go unlisted. The driver builds `libs` into a table
`symbol → member → libs`. For each member it keeps, it emits that member's
`libs` and fails early if any of them cannot be found (§5.3). The same table
feeds `ensure_runtime_so`, whose JIT `.so` keeps linking everything; the JIT
has no symbol set to select on.

### 5.3 Library resolution and diagnostics

One OCaml module (`bin/link_libs.ml`) replaces the four hand-rolled probes
(`main.ml` OpenSSL + compression, and the same pair in `toolchain.ml`).

- **Resolution order per library:** an explicit override
  (`MARCH_LIB_<NAME>_DIR`), then `pkg-config --variable=libdir`, then the
  Homebrew prefix, then the system default. For `--static` it requires
  `lib<name>.a`.
- **A reached library that is missing is a compile error** with one line per
  library, naming the Alpine / Debian / Homebrew package that provides it.
  Example:
  `Compress.Zstd is used but libzstd.a was not found (apk add zstd-static | apt install libzstd-dev | brew install zstd)`.
  This is the todo's acceptance item 3.
- `-DMARCH_HAVE_ZSTD` / `-DMARCH_HAVE_BROTLI` and their stubs go away for
  native targets. A codec file is compiled only when its library resolves, and
  linked only when reached. wasm is unaffected; it never links
  `march_compress.c` natively.

### 5.4 Post-link self-check

After a `--static` link, the driver inspects the output itself (ELF: scan
`PT_INTERP` / `DT_NEEDED`; Mach-O: `LC_LOAD_DYLIB`). It fails if anything is
outside the allowed set: none on Linux; `/usr/lib/*` and `/System/*` on macOS.
This is cheap, and it turns "silently still dynamic" (the todo's second
Non-acceptance failure) into an error. Parse the file in OCaml rather than
shelling out to `readelf`, which macOS lacks.

---

## 6. Verification, including how each check goes red

Each check below says what it asserts and, in *Red:*, how it was or will be
shown to fail.

1. **Dependency-set golden (Stage 2).** A test compiles `hello`, `tlsp` and
   `gz` and asserts the exact non-libc `NEEDED`/`LC_LOAD_DYLIB` set of each
   (§2.5 table).
   *Red:* re-add `march_tls.o` as a loose object (today's behaviour). `hello`
   gains libssl/libcrypto (measured on macOS, §2.1). Also red: drop
   `--as-needed` on Ubuntu (measured: all nine entries return).
2. **Bare-container run (Stage 4), CI.** Modelled on
   `build.yml:262-287`. Compile `hello` and `tlsp` with `--static` in the
   Alpine CI image. Run each with `docker run --entrypoint /hello` in an image
   made from `FROM scratch` plus `COPY hello /`, and assert stdout. Also
   `readelf -d | grep NEEDED` must print nothing.
   *Red:* run the dynamic `hello` in the same image. Measured today:
   `exec /hello: no such file or directory`. A second red is the check's own
   `NEEDED` grep on that binary.
3. **TLS in `scratch` with a bundle (Stage 4).** `netp` against a local TLS
   server (not example.com; CI must not depend on the internet), with
   `SSL_CERT_FILE` pointing at the test CA.
   *Red:* omit `SSL_CERT_FILE`. Measured: `certificate verify failed`.
4. **Missing-archive diagnostic (Stage 4).** In the Alpine image, `mv
   /usr/lib/libssl.a` aside and build `tlsp --static`. Assert that the error
   names `openssl-libs-static` and that stderr has no `undefined reference`.
   *Red:* on today's driver the same move gives the raw linker error; the
   assertion fails.
5. **Compression determinism (Stage 3).** Build `zs` with the zstd header
   hidden (§2.4 recipe) and assert a compile-time error naming libzstd.
   *Red:* today's driver prints `compiled` and the binary prints `zstd
   unavailable` (measured).
6. **CAS staleness (Stage 0).** Two builds of `zs` that differ only in probe
   result must produce different `MARCH_DEBUG_CASFLAGS` keys.
   *Red:* measured today (§2.4): the second build is `(cached)`.
7. **Vendored BLAKE3 (Stage 1).** `test_blake3_agreement` switches its runtime
   side to the vendored sources, still against `lib/cas`'s libblake3, so it
   compares two implementations.
   *Red:* flip one byte of the vendored `IV` constant, and the fixture digest
   mismatches. Also `check-runtime-sources.sh` must fail when
   `runtime/vendor/blake3/blake3.c` is deleted from `sources.list`; the check
   goes red only after its glob is extended, which is the point of extending
   it. Finally `otool -L`/`readelf` of a `--hot-reload` build must not list
   libblake3; red on today's driver (measured, all three platforms).
8. **Hot-reload exemption (Stage 2).** A `--hot-reload` build of `hello`
   still exports `march_tls_client_ctx`, which a patch `.so` could need.
   *Red:* apply archive selection to hot-reload builds, and the symbol is
   absent.
9. **Weak-symbol audit (Stage 2).** Archive member selection interacts with
   weak definitions. The weak no-ops `march_signal_drain` and `march_incrc`
   (`march_scheduler.c:1628-1634`) have strong definitions in
   `march_runtime.c` (`:8988`, `:461`), an always-pulled member, so they are
   safe. `g_http_shutdown` is weak in `march_runtime.c:8924` and strong in
   `march_http.c:2260`, so the weak one is correctly used when HTTP is absent.
   Add a check that every weak definition's strong counterpart lives in
   `march_runtime.c` or is intentionally optional (listed).
   *Red:* move `march_signal_drain`'s strong definition into an optional
   member; the check flags it.

---

## 7. Staged build plan

Each stage lands on its own and leaves main better than before.

- **Stage 0: CAS key covers the probes.** Add the resolved
  OpenSSL/compression/blake3 flag strings to `cas_flags` in `build_cas_key`.
  One `bin/main.ml` change plus check 6. No dependency on anything else.
  CHANGELOG `### Fixed`.
- **Stage 1: vendor BLAKE3.** Add `runtime/vendor/blake3/` (pinned tag,
  licenses copied, portable defines). Point `march_blake3.c` at it. Drop
  `blake3_link_flags` from both user link paths (`main.ml:3123`,
  `toolchain.ml:905`) and the cross build's `march_blake3.c`/`march_reload.c`
  drop (`main.ml:3386`); cross hot-reload stays out of scope, but for other
  reasons. Update `sources.list`, `check-runtime-sources.sh` (glob), and
  `test/dune`'s agreement rule. Result: libblake3 leaves every user binary on
  every platform, and the Ubuntu naive `-static` error disappears.
- **Stage 2: runtime archive + library selection (dynamic).** Make
  `Runtime_archive` also emit `libmarch_rt.a`, and rewrite its "no archive
  semantics" header note. Add the `libs` column and `bin/link_libs.ml`.
  Executables that are not `--hot-reload` link through the archive with
  as-needed / dead_strip_dylibs. Checks 1, 8, 9. Result: `hello` depends on
  libc only.
- **Stage 3: split compression, compile-time codec diagnostics.** Three codec
  files, stubs removed on native, check 5. Result: the dependency set and
  behaviour are a function of the source.
- **Stage 4: `--static` on a native musl host + CI scratch job.** The flag,
  refusal on glibc, the post-link self-check (§5.4), diagnostics (§5.3),
  checks 2-4, and the allocator measurement (§4.4). Closes the todo's
  acceptance items 1-3 for Linux. Update `specs/docker_images.md`'s `scratch`
  variant.
- **Stage 5: `--target linux/<arch>-musl` (static cross from macOS).** Add a
  `LinuxMusl` target, an Alpine static sysroot fetch (including
  `libucontext.a`, §2.7), and `zig cc -target <arch>-linux-musl -static`.
  Extends the cross-compile design's future-work item.
- **Stage 6: macOS self-contained `--static`.** Homebrew `.a` resolution and
  the `LC_LOAD_DYLIB` self-check. Can run in parallel with Stages 4-5 once
  Stage 2 is in.

Stages 0 and 1 are independent of each other and of everything else. Stage 3
needs Stage 2's `libs` table. Stages 4-6 need 1-3.

---

## 8. Risks

- **Archive semantics change link behaviour in ways that are hard to see:**
  a member with only side effects (a constructor) would be dropped. A grep of
  `runtime/*.c` for `constructor` attributes finds none today. Check 9 covers
  weak symbols. Any future `__attribute__((constructor))` in an optional
  member must be listed.
- **`called_c_symbols` could miss a symbol** (an emission path that bypasses
  `mangle_extern`). Consequence: a *link error* in `--static` mode (the
  library was not on the line), never a wrong binary. Dynamic links do not
  depend on it (the linker selects). The cap audit has the same dependency,
  so a fix there helps here.
- **OpenSSL static licensing.** OpenSSL 3 is Apache-2.0, so static
  redistribution needs its NOTICE/license in the distributed artifact. The
  runtime is the user's program, so this is the user's obligation, but
  `--static` should print a one-line reminder when libssl is linked, and the
  docs should state it. zstd (BSD), brotli (MIT), zlib (zlib), libucontext
  (ISC), and musl (MIT) are permissive.
- **Stale TLS in static binaries.** An OpenSSL CVE means rebuilding every
  static binary. This is inherent to static linking; document it.
- **musl allocator performance.** Unmeasured (§4.4). Stage 4 gates on it.
- **libucontext for cross musl.** It is an extra target archive. The
  alternative, an in-runtime asm context switch, removes the dependency on
  every musl path, but it is new per-arch assembly in the scheduler.

## 9. Open questions

1. Should `forge.toml` get `[build] static = true`, and should `forge build
   --static` pass through? (Probably yes, in Stage 4; forge already passes
   `--target`, `forge/lib/cmd_build.ml:614-622`.)
2. Replace `libucontext` with a runtime-owned context switch (removes a
   dependency on every musl build), or carry it in the musl sysroot?
3. An opt-in `--embed-ca-bundle` for single-file deploys, or never?
4. Should `lib/cas` (the compiler) move to the vendored BLAKE3 in the same
   release, retiring `build.yml`'s unpinned clone (§3.1)?
5. Is the `-msse4.2` that `arch_cflags` passes for `Native` on arm64 hosts
   (`bin/main.ml:3328`; it is visible in every Linux arm64 `MARCH_CC_CMD`
   above and ignored only because of `-Wno-unused-command-line-argument`)
   worth fixing while this code is open? It is unrelated to linking.
6. glibc `--static` as an explicit escape hatch (`--static=glibc`) for users
   who accept the NSS caveat? §2.7 shows it works for DNS and TLS in `scratch`.
   D4 recommends against it for v1.

## 10. What could not be verified

- x86_64 behaviour. Every measurement is aarch64. The x86 BLAKE3 portable
  build and the x86 `-msse4.2` interplay are unmeasured.
- musl vs glibc allocation performance (§4.4).
- Provenance of the host `_build/default/bin/main.exe`: its mtime (15:40)
  predates `35e8e77ce` (16:16), probably because of dune-cache hardlinks. Its
  `MARCH_ECHO_CC` link line matches `bin/main.ml` as read at `154cf1754`. The
  Linux measurements used compilers built from source at `154cf1754` and are
  authoritative.
- Whether `-dead_strip_dylibs` behaves the same on older ld64 versions
  (measured only on ld-1230.1).
