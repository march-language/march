# A compiled program links TLS and compression only when it reaches them (static output, Stage 2)

Landed 2026-10-18. Stage 2 of `specs/2026-09-23-static-compile-output-design.md` (decisions
D1 and D6, approved 2026-10-18), under the still-open
`specs/todos/2026-09-02-march-compile-output-is-not-static.md`.

**Before.** `march --compile` linked every runtime object positionally, so every program
recorded a load command for every library any member needed. A hello-world on macOS arm64
loaded libssl, libcrypto, libz, libzstd, libbrotlienc and libbrotlidec (re-measured
2026-10-18; libblake3 had already gone with Stage 1).

**Now.** The two members that alone need a library, `march_tls.o` (OpenSSL) and
`march_compress.o` (zlib, and zstd/brotli until Stage 3 splits the codecs), go into
`libmarch_rt_opt.a` (`Runtime_archive.ensure_opt_archive`, built beside the cached objects,
same key), linked after the program's object. The runtime's `-l` flags follow the archive,
bracketed by `-Wl,--as-needed` / `-Wl,--no-as-needed` on Linux (positional, and Ubuntu's
clang does not default it; a user's `--ffi-link` libraries keep today's semantics) or with
`-Wl,-dead_strip_dylibs` on macOS when there is no `--ffi-link` (that flag is global).
Measured on macOS arm64:

| Program | Libraries beyond libSystem |
|---|---|
| `println` only | none |
| `Tls.client_ctx` | libssl, libcrypto |
| a gzip round trip | libz, libzstd, libbrotlienc, libbrotlidec (Stage 3 narrows this to libz) |
| any `--hot-reload` build | all of them, unchanged |

**Only those two members**, not the whole runtime as the design's §5.1 sketched: a member
that strongly defines a symbol another member defines weakly (`march_observe_debug.c`'s
`march_observe_debug_install`, `march_trace.c`'s `march_trace_ev_*`, `march_dispatch.c`'s
epoch functions over `march_scheduler.c`'s weak defaults) would never be pulled from an
archive, because the weak default already satisfies the reference, and the override would
silently not link (design check 9's hazard). Every member except TLS and compression has
no library of its own, so archiving them buys nothing and risks exactly that. Neither
archived member is referenced from other runtime C (only from the stdlib's builtins) or
holds a weak/strong pair.

**Not archived** (the whole runtime as loose objects, as before): `--hot-reload` servers
(a patch `.so` resolves runtime symbols against the base, design D6) and `--compile-so`
patches, `-rdynamic` builds, the event-loop and signing builds that already bypass the object
cache, cross targets, and any build where the archive cannot be made (falls back silently;
`MARCH_ECHO_CC` says why). `MARCH_NO_RUNTIME_ARCHIVE=1` forces the old link.

**Tests.** `test/test_link_deps.ml` (suite `link_deps` in `run_compiler`): compiles a
hello-world, a TLS program and a gzip program with a private HOME, runs each, and asserts
its non-libc load commands (`otool -L` on macOS, `readelf -d` on Linux): none, exactly
OpenSSL, compression only. A second case is the red half: with `MARCH_NO_RUNTIME_ARCHIVE=1`
the hello-world loads OpenSSL (and with it set for the first case, that case fails with
`[brotlidec,brotlienc,crypto,ssl,z,zstd]`). A third checks a `--hot-reload` build still
defines `march_tls_client_ctx` for patches (design check 8). Verified on macOS arm64; the
Linux link order (archive after the object, libraries after the archive) is first exercised
by CI's Linux legs.
