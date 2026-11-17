`[P3]` The `--jit` / REPL prelude cache is keyed without the runtime .so it links against

Found during ocap phase 4 Task 10b (2026-11-17), while testing a `runtime/march_runtime.c`
change under `--jit`.

`lib/jit/repl_jit.ml` caches the compiled stdlib prelude as
`~/.cache/march/stdlib_prelude_O1_tln2_ty1_<hash>.so`, with `<hash>` taken from the stdlib
content and the compiler executable's size and mtime. The runtime .so is keyed separately
(`libmarch_runtime_<hash16>.so`, `bin/toolchain.ml` `ensure_runtime_so`, by the runtime
sources). On macOS the prelude .so is linked against the runtime .so by absolute path
(`otool -L` shows `libmarch_runtime_<old hash>.so`).

So after a runtime-only edit (the compiler binary unchanged), `--jit` builds and loads the
new runtime .so, but the cached prelude still binds its runtime calls to the old one, and
both are loaded in one process. Each has its own globals and thread-locals. Observed: the
prelude's `Authority.enter_fn` pushed a frame into the old runtime's authority slot while
the user code's catch and probes read the new runtime's, so a `--jit` run printed different
authorities from the compiled binary of the same source. A fresh `HOME` (an empty cache)
gave the right output.

Test suites are unaffected (each run uses a private `HOME`). A person editing the runtime and
running `--jit` against a warm `~/.cache/march` is not.

Fix: put the runtime .so's hash (the one `ensure_runtime_so` returns) into the prelude's
cache key.
