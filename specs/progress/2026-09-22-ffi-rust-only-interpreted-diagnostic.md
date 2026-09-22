# Interpreted runs of a `[ffi.rust]`-only project now warn that Rust FFI is compiled-only

Option 3 of `specs/todos/2026-08-18-ffi-rust-only-projects-cannot-run-interpreted.md`.
That todo stays open for options 1/2 (making the interpreter able to load the Rust
code at all).

## Before

`forge run` on a project with only `[ffi.rust]` built the crate, passed
`--ffi-link <crate>/target/release/lib<name>.a` to an interpreted `march`, and the
program died at its first Rust extern with the same message as a genuinely missing
symbol:

```
extern rusty:rusty_rusty_add — symbol not found for interpreter FFI (build the runtime, or run with --compile)
```

## After

Every interpreted entry point in forge prints one warning before the program runs:

```
warning: [ffi.rust] crate "native/rusty" is only available in compiled mode.
  forge builds it as a static archive (librusty.a), which the interpreter cannot load,
  so every extern it provides will fail with "symbol not found for interpreter FFI".
  Run it compiled instead: `forge run --compiled`, `forge build`, or `forge test`
  (without --coverage or MARCH_TEST_INTERPRETER=1).
```

The warning is **non-fatal**. A program, or an interpreted test file, that never
reaches a Rust extern still runs; failing the run up front would break those for no
gain, and the interpreter already stops at the first unresolved extern, so the user
sees the warning plus one error, not one error per extern.

## Where the check lives, and why forge

- `Cmd_build.interpreted_rust_ffi_diagnostic ~interpreted proj` (pure: returns the
  message or `None`) and `Cmd_build.warn_interpreted_rust_ffi` (prints it to stderr).
- Called from the interpreted paths only: `Cmd_run.run`'s `(false, _)` arm (through
  `resolve_entry ~interpreted:true`), `Cmd_test.run_files`'s `use_interp` branch, and
  `Cmd_interactive.run` (the REPL preloads the entry through the interpreter).
  `forge build`, `forge run --compiled` and compiled `forge test` never call it.

The compiler could not make this call well: all it receives is an opaque
`--ffi-link <path>`, and it cannot tell a Rust archive from any other linker flag
(`-lsqlite3`, a hand-built `.a`). Forge has the parsed `forge.toml`, knows the
archive came from `[ffi.rust]`, knows the crate name, and knows whether the run is
interpreted, so it can name the crate and the right compiled command.

It fires only when `ffi_rust` is set **and** `[ffi] sources` is empty. With C
sources present the compiler does build a shim `.so` with the archive on its link
line, so the interpreter path is not wholesale dead; whether the Rust symbols reach
it depends on the shim referencing them (noted in the open todo).

## Verification

- `forge/test/test_forge.ml`, group `interp_command`, four new cases on real
  `forge.toml` files loaded by `Project.load_from_dir` (no cargo build runs):
  Rust-only interpreted gets the diagnostic (crate, archive name, `forge run
  --compiled`, `warning:` prefix); Rust-only compiled gets none; Rust plus `[ffi]
  sources` gets none; C-only and no-FFI get none.
- Red controls: against `origin/main` the cases do not compile (the function does
  not exist). Perturbing the guard to `when false && ...` fails case 11 ("expected
  the compile-only diagnostic for a [ffi.rust]-only project"); perturbing it to
  always fire fails cases 12 and 13.
- End to end: a scratch project with only `[ffi.rust]`, a fake `cargo` on `PATH`
  that just creates `target/release/librusty.a`, and the dev `march`. The
  `origin/main` forge printed only the `symbol not found for interpreter FFI` error;
  this branch's forge printed the warning above first, then the same error.
- `dune build --root . @forge/test/runtest` exit 0.

The `forge bench` gap mentioned in the old todo was confirmed and filed as
`specs/todos/2026-09-22-forge-bench-ignores-ffi-flags.md`.
