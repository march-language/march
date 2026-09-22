`[P3]` # `forge bench` never passes the project's FFI flags to the compiler

`Cmd_bench.run` (`forge/lib/cmd_bench.ml`) compiles every `bench/*.march` with

```ocaml
Cmd_build.compile_entry ~lib_path_env ~ffi_flags:"" ~output:bin ~release:true ~dump_phases:false path
```

The `~ffi_flags:""` is hardcoded (confirmed 2026-09-22). `forge build`, `forge
run` and `forge test` all get theirs from `Cmd_build.ffi_flags_full proj`, so a
benchmark that calls any extern from `[ffi] sources` or `[ffi.rust]` fails to
link, while the same code builds and tests fine. It is the same gap `forge run`
had before `specs/progress/2026-08-18-forge-run-interpreted-drops-ffi-sources.md`.

Not fixed in the same PR as the `[ffi.rust]` diagnostic because it is not a
one-liner: `ffi_flags_full` returns a `result` and runs `cargo build` for
`[ffi.rust]`, so the call has to move out of the per-benchmark `List.map` and its
`Error` has to be surfaced. A regression test needs a real native compile with an
`--ffi-c` shim; `test_compiled_run_end_to_end` in `forge/test/test_forge.ml` has the
dev-compiler PATH-shim setup to copy.

Fix sketch: in `Cmd_bench.run`, call `Cmd_build.ffi_flags_full proj` once before
compiling, return its `Error` as is, and pass the flags to every `compile_entry`.
Test: a bench project with `[ffi] sources = ["native/shim.c"]` whose benchmark
calls a shim function; assert it compiles and runs.
