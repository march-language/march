# Vendored mimalloc

Source: https://github.com/microsoft/mimalloc
Tag: v2.2.4
Commit: fbd8b99c2b828428947d70fdc046bb55609be93e

Copied: `src/` (minus `prim/windows`, `prim/emscripten`, `prim/wasi`), `include/`,
`LICENSE` (MIT). No local modifications.

March compiles ONLY `src/static.c`, as one object, with `-DMI_DEBUG=0` and
`-I runtime/third_party/mimalloc/include`. libc malloc is NOT globally overridden
(a static override is not possible on macOS): only `march_alloc` allocates from
mimalloc, and every `free()`/`realloc()` in the runtime and user FFI shims is
routed by pointer provenance through `march_free_any`/`march_realloc_any`
(`runtime/march_alloc.h`, defined in `runtime/march_runtime.c`).

Off under any sanitizer (`MARCH_SANITIZE`), for `--compile-so` patches, for non-native
targets, in the REPL/JIT runtime .so, in the WASM runtime, and when
`MARCH_MALLOC=libc` is set at compile time.
