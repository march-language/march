`[P3]` # A `[ffi.rust]`-only project still cannot run interpreted

Follow-up to `specs/progress/2026-08-18-forge-run-interpreted-drops-ffi-sources.md`,
which fixed the C-source half of this (`forge run` now passes `--ffi-c`).

**Partly addressed (2026-09-22):** option 3 below, the honest diagnostic, has
landed; see `specs/progress/2026-09-22-ffi-rust-only-interpreted-diagnostic.md`.
Interpreted runs of a `[ffi.rust]`-only project now print a compile-only
warning up front. The project still *cannot* run interpreted. What remains is
making it work.

A project that declares **only** `[ffi.rust]` and no `[ffi] sources` remains
broken under the interpreter:

- `Cmd_build.ffi_flags_full` contributes only `--ffi-link <archive>` for a Rust
  crate (`forge/lib/cmd_build.ml`, the `ffi_rust` arm).
- The compiler's interpreter-FFI shim gate keys on `ffi_c_files` alone
  (`setup_interpreter_ffi` in `bin/main.ml`). With no C source there is nothing
  to `cc -shared`, so `Eval.ffi_shim_so` stays `None` and every extern fails to
  resolve.

Fixing it needs more than a flag: `cargo build --release` produces a **static**
`lib<name>.a`, and a `.a` cannot be `dlopen`ed. Remaining options:

1. Have `[ffi.rust]` also emit a `cdylib` and dlopen that under the interpreter
   (needs a `crate-type` requirement on the user's crate, or a generated
   wrapper).
2. Generate a tiny C shim that links the archive and `cc -shared` that, so the
   existing `ffi_c_files` path is reused. Note that a plain `cc -shared` with
   the `.a` on the link line pulls in only the archive members that resolve an
   undefined symbol, so the shim must reference the Rust symbols (or link with
   `-Wl,-force_load` / `--whole-archive`).

Related gap, same root: a **mixed** project (`[ffi] sources` *and*
`[ffi.rust]`) is not warned, because a C shim does get built and the archive is
on its link line; but for the reason in option 2 the Rust symbols reach the
interpreter only if the C shim itself references them. Whichever option lands
should cover that case too.

When this is fixed, delete `Cmd_build.interpreted_rust_ffi_diagnostic` and its
call sites (`cmd_run.ml`, `cmd_test.ml`, `cmd_interactive.ml`) and the
"interp_command" tests that pin it in `forge/test/test_forge.ml`, and update the
"Interpreter mode" section of `docs/ffi.md`.

The `forge bench` half of the original note is filed separately as
`specs/todos/2026-09-22-forge-bench-ignores-ffi-flags.md`.
