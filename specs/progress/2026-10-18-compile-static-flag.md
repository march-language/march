# `march --compile --static` (static output, Stages 4 and 6)

Landed 2026-10-18. Stages 4 (native musl Linux) and 6 (macOS) of
`specs/2026-09-23-static-compile-output-design.md` (decisions D4, D5 and D7, approved
2026-10-18), under `specs/todos/2026-09-02-march-compile-output-is-not-static.md`, which stays
open until the Linux scratch-container check below has run green in CI and for Stage 5.

**What it does** (`bin/static_link.ml`, wired into the native link in `bin/main.ml`):

- **Refusals first**, with a reason: `--hot-reload` (patches are `dlopen`ed), `--compile-so`,
  `--target` (the static musl cross target is Stage 5), and a glibc Linux host (D4: static
  glibc leaves NSS/iconv/`dlopen` depending on the host; the message names the Alpine
  packages).
- **Which libraries:** those of the runtime members the program reaches
  (`Static_link.reached`, from `Llvm_builtins.called_c_symbols`; every member when the
  runtime archive is unavailable), resolved before any runtime C is compiled. A reached
  library without its archive is an error naming the package, e.g. `march: --static: TLS is
  used, but libssl.a was not found (brew install openssl@3)` / `(apk add
  openssl-libs-static)`, and nothing else (the todo's acceptance item 3).
- **Linux (musl):** `-static`, `-l<name>` for each reached library (each checked to have
  `lib<name>.a`) plus `libucontext.a`.
- **macOS:** Homebrew's `libssl.a`/`libcrypto.a`/`libzstd.a`/`libbrotli*.a` by path; zlib
  stays the system's `/usr/lib/libz` (D5: "self-contained" = nothing outside `/usr/lib` and
  `/System`).
- **Post-link self-check** (`Static_link.verify`), before the binary is cached: ELF read in
  OCaml (no `PT_INTERP`, no `DT_NEEDED`), Mach-O through `otool -L` (every load command under
  `/usr/lib` or `/System`). A failing binary is deleted and the build fails, so "silently
  still dynamic" cannot ship.
- `static` is a CAS tag; a TLS-reaching static build prints the OpenSSL license reminder.
- CA certificates (D7): no embedded bundle; `docs/tooling.md` "Static binaries" documents
  `SSL_CERT_FILE` / `SSL_CERT_DIR` and the `scratch` Dockerfile line.

**Measured on macOS arm64** (non-system load commands, size): hello none, 249 KB; a TLS
program none, 4.8 MB; a gzip program none (system libz), 270 KB; a zstd program none, 675 KB.

**Tests.** `test/test_static_link.ml` (suite `static_link`): on macOS, hello/TLS/gzip/zstd
built `--static` run and load only system libraries (red with `--static` made a no-op: the
TLS program loads Homebrew's libssl/libcrypto); a missing archive (via
`MARCH_TEST_LIBPROBE_ROOT`) names `libssl.a` and `openssl@3` with no compiler or linker
output; `--ffi-link` of a Homebrew dylib is refused by the self-check and leaves no binary;
`--static --hot-reload` is refused; on a glibc Linux host (CI's Ubuntu legs) `--static` is
refused naming the Alpine route.

**Linux musl, not verified locally** (no Docker daemon here): `.github/workflows/build.yml`'s
Alpine legs (release and nightly) gain "Verify --static output runs in an empty container":
the packaged compiler builds hello and a TLS program `--static` inside a stock `alpine:3.21`,
`readelf -d` must show no `NEEDED`, each must print its line from a `FROM scratch` image, and
the same hello built WITHOUT `--static` must fail to start there (the check's red half). Its
first run is the first execution of the musl path.

**Not done:** Stage 5, `--target linux/<arch>-musl` (a static cross build from macOS: a
`LinuxMusl` target, an Alpine static sysroot fetch including `libucontext.a`, `zig cc
-target <arch>-linux-musl -static`). The musl allocator measurement the design asks of
Stage 4 (§4.4) is also still open.
