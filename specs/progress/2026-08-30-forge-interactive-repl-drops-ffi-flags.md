# `forge interactive` / `march repl` dropped the forge.toml `[ffi]` flags

Sibling of `specs/progress/2026-08-18-forge-run-interpreted-drops-ffi-sources.md`,
which fixed the same omission in `forge run`. The audit that fix asked for
("check whether any other interpreter entry point in `forge/lib/` has the same
omission") turned up one more: the project REPL.

`forge interactive` shells out to `march repl <entry>` with `MARCH_REPL_INTERP=1`,
so the preloaded project is evaluated by the interpreter. It never called
`Cmd_build.ffi_flags_full`, so no `--ffi-c` / `--ffi-link` reached the compiler,
`setup_interpreter_ffi` took its `ffi_c_files = []` no-op branch, no shim `.so`
was built, and any extern from a dependency's `[[ffi]]` C sources failed with
"symbol not found for interpreter FFI".

The compiler side was broken too, in a way `forge run` never exposed: the `repl`
subcommand is handled in `bin/main.ml` **before** `Arg.parse`, so it had no
`--ffi-c` parsing at all and never called `setup_interpreter_ffi`. The bare
no-file REPL (`march` with no arguments) reaches its branch *after* `Arg.parse`
and so did parse the flags, but likewise never called `setup_interpreter_ffi`.

## Fix

- `bin/main.ml`, `repl` subcommand: peel `--ffi-c` / `--ffi-link` / `--ffi-so`
  out of `argv[2..]` (the first non-flag argument stays the preload file, as
  before) and call `setup_interpreter_ffi ()`.
- `bin/main.ml`, bare-REPL branch (`| [] ->` after `Arg.parse`): call
  `setup_interpreter_ffi ()`.
- `forge/lib/cmd_interactive.ml`: thread `Cmd_build.ffi_flags_full` into the
  command, matching `Cmd_run.run`'s error handling.

The flags are appended **after** the entry file, not before it: an older `march`
reads `argv.(2)` positionally as the preload path, so a flag in that slot would
regress it. Newer `march` skips flags wherever they appear.

Both command builders are now small pure helpers (`Cmd_run.interp_command`,
`Cmd_interactive.repl_command`) with unit tests in `forge/test/test_forge.ml`
("interp_command"), so the flag threading and the entry-before-flags ordering
are pinned.

## Evidence

Against the envoy app (`forge.toml` declares depot's `sqlite_shim.c` and
`-lsqlite3`), each run under a private `HOME` so `~/.cache/march` starts empty:

- `forge run`: boots, logs `Envoy listening on http://localhost:4555`, `curl /`
  returns 200, and `march_ffi_shim_407dc38d674860f7.so` appears in the cache.
- `forge interactive` (fixed): `march_ffi_shim_407dc38d674860f7.so` appears.
- `forge interactive` (RED control — same commit with only
  `cmd_interactive.ml` reverted, rebuilt, same clean baseline): **no**
  `march_ffi_shim_*.so` in the cache.

## Still open

`forge bench` hardcodes `~ffi_flags:""` (`forge/lib/cmd_bench.ml:61`). That is
the compiled path, not an interpreted one, but it is the same omission; tracked
in `specs/todos/2026-08-18-ffi-rust-only-projects-cannot-run-interpreted.md`.
