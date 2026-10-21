# One runtime member per compression codec; a missing codec library is a compile error (static output, Stage 3)

Landed 2026-10-18. Stage 3 of `specs/2026-09-23-static-compile-output-design.md` (decision
D3, approved 2026-10-18), under the still-open
`specs/todos/2026-09-02-march-compile-output-is-not-static.md`.

**Before.** `runtime/march_compress.c` held all four codecs. zstd and brotli were compiled in
when the build host had their headers (`-DMARCH_HAVE_ZSTD` / `-DMARCH_HAVE_BROTLI`), else as
stubs answering `Err("Compress.Zstd: libzstd not available — install libzstd and rebuild")`
at run time. So the same source built a working program on one machine and a failing one on
another, and (after Stage 2) a gzip program still loaded libzstd and libbrotli because the
codecs shared a member.

**Now.**

- `runtime/march_compress.c` is gzip/deflate over zlib; `march_compress_zstd.c` and
  `march_compress_brotli.c` hold the other two; their shared caps and Bytes/Result helpers
  are `static inline` in `march_compress_common.h`, so no codec member pulls another. All
  three are archive members (`Runtime_archive.archived_members`).
- The driver compiles a codec file only when its library resolves (`zstd_probe`,
  `brotli_probe` in `bin/main.ml`; never for a cross target), and before any runtime C is
  compiled, `check_codecs_available` refuses a program whose emitted code calls a codec it
  cannot have (read from `Llvm_builtins.called_c_symbols`):
  `march: Compress.Zstd is used, but libzstd was not found on this host (apk add zstd-dev |
  apt install libzstd-dev | brew install zstd)`. A program that never calls a codec is never
  refused for lacking it.
- The REPL/JIT runtime `.so` (`Toolchain.ensure_runtime_so`), which serves any program and
  has none to refuse, always builds both codec files, as their not-available stubs
  (`-DMARCH_ZSTD_STUB` / `-DMARCH_BROTLI_STUB`) when the library is missing. The interpreter's
  own stubs (`lib/eval/compress_stubs.c`) are unchanged.
- `runtime/sources.list` gains a `codec` role, which `scripts/check-runtime-sources.sh` treats
  like `core` (both drivers must name the file; every `--compile` dune rule must depend on it,
  which they all do by globbing `../runtime/*.c`).

Measured on macOS arm64 (non-libSystem load commands): a gzip round trip loads `libz` only
(it loaded libz, libzstd, libbrotlienc and libbrotlidec); a zstd round trip loads `libzstd`
only, not even libz.

**Tests.** `test/test_link_deps.ml`: the gzip program's set is exactly `[z]` and a zstd
program's exactly `[zstd]`; and "a codec this host lacks is a compile error naming the
package" builds the zstd program with `MARCH_TEST_LIBPROBE_ROOT` (the probe finds nothing)
and asserts a non-zero exit, the `Compress.Zstd ... libzstd` line and the package names, and
no compiler or linker error text. Red with the check removed: the build then dies compiling
the runtime instead, and the named-codec assertion fails.

Every CI leg installs libzstd and libbrotli, so `test_stdlib_suite`'s compiled-vs-interpreted
compression case keeps building its zstd/brotli half there.
