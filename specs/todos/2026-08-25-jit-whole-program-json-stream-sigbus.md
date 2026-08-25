# `--jit` SIGBUS on json_stream (bench/interp/json_stream.march)

Filed: 2026-08-25

## Repro

```bash
./_build/default/bin/main.exe --jit bench/interp/json_stream.march
# rc=138 (SIGBUS) on both MARCH_JIT_BACKEND=orc (default) and =clang
```

`--compile` of the exact same file is green (checksum=28000, ~60-220ms), and
`--jit` is green on every other `bench/interp/*.march` program (fib,
binary_trees, float_loop, string_pipeline, string_split, par_fib, par_map all
match the interp/compiled checksum; actor_pingpong/actor_call_storm fall back
to the interpreter and also match). So this is not a whole-program-ORC
codegen problem in general — it is specific to something json_stream does
along the JIT'd fragment/module-construction path that `--compile`'s
ahead-of-time pipeline doesn't hit.

## Hint

Fragment-path-specific: `--jit`'s whole-program run still goes through
`Repl_jit.run_program` (see lib/jit/repl_jit.ml), which shares machinery with
the REPL's per-fragment JIT compilation/linking path. `--compile` uses the
separate ahead-of-time `lib/tir/llvm_emit` -> object file -> link pipeline and
does not crash on this file. The bug is therefore likely in something
specific to the ORC/ in-process linking or module layout that
`Repl_jit.run_program` uses for a whole program, not in TIR lowering or
codegen shared by both paths (which is exonerated by `--compile` being
clean).

json_stream.march is heavier on record/JSON-decode paths than the other
bench/interp programs that pass; worth diffing what it does differently
(nested records, recursive descent parsing, `Bytes`/`String` conversions) once
someone reproduces the SIGBUS under a debugger (`lldb -- ./_build/default/bin/main.exe --jit bench/interp/json_stream.march`, then `bt` at the signal) to
get past the "which allocation/relocation" question this note leaves open.

## Status

Excluded from the whole-program-ORC default-flip criteria (see
`specs/progress/2026-08-25-interp-perf-phase-4-whole-program-orc.md`): "every
`bench/interp` program passes under `--jit`" is not yet met because of this
file. `bench/run_interp_bench.sh`'s checksum cross-check tolerates this as a
FAILED row (ok=false) without hard-failing the whole benchmark run — see the
per-mode exclusion logic added in the same commit that filed this todo.
