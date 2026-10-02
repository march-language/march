`[P2]` Link mimalloc as `march_alloc`'s allocator (landed 2026-10-01)

Step 1 of `specs/todos/2026-08-04-x86-benchmark-findings.md` finding 2. Numbers are
in that todo's status section. The `calloc`->`malloc` audit (step 2) is not part of
this item.

## What

- `runtime/third_party/mimalloc/`: mimalloc v2.2.4 (`src/`, `include/`, `LICENSE`),
  vendored like blake3. Only `src/static.c` is compiled, as one object, with
  `-DMI_DEBUG=0` (mimalloc defaults to its slow debug build unless `NDEBUG`, and the
  runtime's own asserts need `NDEBUG` unset).
- `march_alloc` calls `march_obj_calloc` (`runtime/march_alloc.h`): `mi_calloc` when
  built with `-DMARCH_USE_MIMALLOC`, plain `calloc` otherwise.
- `bin/main.ml`: `use_mimalloc` adds `static.c` to the runtime sources and
  `alloc_flags` to the cflags (spliced through `section_cflags`, which reaches both
  the cached runtime objects and the monolithic link line). `mimalloc_requested ()`
  also puts a `mimalloc` tag in the CAS key (`codegen_cas_tags`), so a libc-malloc
  artifact never satisfies a mimalloc build.
- Off when: `MARCH_SANITIZE` is set (ASAN/TSAN must see every allocation),
  `--compile-so` (a patch carries no runtime), a non-native target, `MARCH_MALLOC=libc`,
  or the vendored files are not all present in the resolved runtime directory (a
  partially staged `_build/default/runtime` falls back to libc instead of failing).
  The REPL/JIT runtime .so (`bin/toolchain.ml`, `test_helpers.ml`) and the WASM
  runtime are built without `MARCH_USE_MIMALLOC` and keep libc, so no new `.c` file
  entered any link list.

## Why the free path is a -D and not a header

libc malloc is not globally overridden (macOS cannot statically override it), so a
pointer may come from either allocator, and a `free()` of a March object anywhere in
the runtime or a user FFI shim must reach `mi_free`. Every TU is compiled with
`-Dfree=march_free_any -Drealloc=march_realloc_any`; `<stdlib.h>`'s own declarations
become declarations of the two routing functions (defined once in `march_runtime.c`),
which dispatch on `mi_is_in_heap_region`. Memory from `strdup`/`getline`/OpenSSL
still reaches libc `free`.

## Trap found while building it

The first attempt force-included a shim header (`-include march_alloc.h`) into every
TU. Every actor program then crashed (`_setcontext` with sp = 0). Cause: the header
pulled in `<stdlib.h>` before `march_scheduler.c`'s own `#define _XOPEN_SOURCE`
("must come before all system headers"), so `ucontext_t` had a different layout in
that TU than in the others. It crashed with mimalloc's allocation and free both
disabled, which is how it was told apart from a use-after-free. `march_alloc.h`
documents that it must never be force-included. Single-threaded `binary_trees` did
not show it; only an actor/scheduler program did, so test any allocator change with
`bench/actors/fanin_flood.march` at 8 schedulers, not just the allocation benches.

## Not done

- Cross-compiled Linux targets keep libc (the cross path is not exercised here).
  Linux native was not run on this Mac; CI covers it.
- ASAN: only verified that the sanitizer build's command line carries no mimalloc and
  keeps `-fsanitize`; no ASAN binary was run (ASAN needs Docker on this Mac).
