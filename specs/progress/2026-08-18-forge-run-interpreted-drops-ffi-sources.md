# `forge run` (interpreted) never passed forge.toml `[ffi]` sources to the compiler

An app whose `forge.toml` declares `[ffi] sources = [...]` could not be run
interpreted at all. Every extern call died at runtime with:

```
extern sqlite:depot_sqlite_open — symbol not found for interpreter FFI
(build the runtime, or run with --compile)
```

## Root cause

The compiler resolves interpreter-FFI symbols by building a shim `.so` from
the `--ffi-c` sources it is given (`setup_interpreter_ffi`, `bin/main.ml`
~999-1062) and registering it as `Eval.ffi_shim_so`. That function correctly
no-ops when it receives no C sources (`bin/main.ml:1003`) — with nothing to
compile there is genuinely no shim to build. `march --ffi-c foo.c app.march`
has always worked.

The break was entirely on the forge side. Every other command that shells out
to `march` threads the manifest's FFI flags through:

- `forge build`      → `forge/lib/cmd_build.ml:751-763`
- `forge test` (compiled)    → `forge/lib/cmd_test.ml:189-192`
- `forge test` (interpreted) → `forge/lib/cmd_test.ml:158-161`

`forge run`'s interpreted branch did not — it built its command line as
`"%smarch%s %s"` (lib-path env, dump flag, entry) with no FFI flags at all
(`forge/lib/cmd_run.ml:41-42`). So `ffi_c_files` arrived empty, no shim was
built, and `dynamic_ffi_call` failed both its `dlsym` lookups
(`lib/eval/eval.ml:2145-2150`) and raised the message above.

`forge run --compiled` was never affected: it delegates to `Cmd_build.build`.
There is no evidence `run` was ever *intended* to be FFI-less — `cmd_run.ml`
simply predates the wiring `cmd_test.ml` received.

## Fix

`forge/lib/cmd_run.ml`: call `Cmd_build.ffi_flags_full proj` in the
interpreted branch and splice the flags into the command, mirroring
`Cmd_test.invoke_march_interp` exactly. `ffi_flags_full` (rather than the
cheaper `ffi_flags_of`) is deliberate — it is what interpreted `forge test`
uses, so `run` and `test` now behave identically on the same manifest, and a
`[ffi.rust]` crate is built rather than silently ignored.

## Regression test

`forge/test/test_build_check.ml`, suite `"forge run"`, case
`"interpreted run passes [ffi] sources to the compiler"`. It scaffolds a real
app with a C shim (`forge_run_ffi_triple`) that exists **nowhere in the
runtime**, declares it under `[ffi]`, and calls it via `extern`.

The assertion is on the program's **stdout** (`14 * 3 = 42`), not on
`Cmd_run.run` returning `Ok`: the extern is only reached and executed if the
shim was actually built and dlopened, so no constant or short-circuit
satisfies it, and a run that never reached the extern cannot pass.

Verified non-vacuous: with the two-line fix reverted the test fails with the
exact production error (`extern shim:forge_run_ffi_triple — symbol not found
for interpreter FFI`); with it restored the test passes. It rides in
`test_build_check.exe`, which is hermetic (the dune rule passes the
just-built compiler as `MARCH_TEST_BIN`), so it exercises the build under
test rather than an installed release.

## Known remaining gaps (not fixed here)

1. **Closure/callback arguments still require `--compile`.** `lib/eval/eval.ml`
   ~2124-2131 rejects any `TyArrow` FFI argument, so a shim taking a callback
   remains compile-only. Pre-existing and separately documented as "Gap 2".
2. **`[ffi.rust]`-only projects remain broken under the interpreter.**
   `ffi_flags_full` contributes only `--ffi-link <archive>` for a Rust crate
   (`cmd_build.ml:464`), but the shim gate keys on `ffi_c_files` alone
   (`bin/main.ml:1003`). With no C source nothing is built, and a `.a` cannot
   be `dlopen`ed regardless — it would need to be a `cdylib`.
3. **`forge bench` still hardcodes `~ffi_flags:""`** (`forge/lib/cmd_bench.ml:61`),
   so benchmarks of FFI code have the same gap.
4. A shim that fails to compile is only a **warning** (`bin/main.ml:1052-1054`),
   so a broken shim degrades into this same "symbol not found" message rather
   than a clear `cc` error.
