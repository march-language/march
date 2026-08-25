# bench/interp — scaled corpus for interpreted / REPL-JIT / compiled A-B

`bench/*.march` sizes are tuned for compiled code (fib(40), 100k-element
strings). The interpreter is 100–400× slower, so this directory holds the
same workloads at sizes that finish in 1–20 s interpreted.

Rules:
- every program prints exactly one `checksum=<int>` line; the runner diffs it
  across modes and fails on mismatch;
- `main` takes the narrowest capability grant it needs;
- no timing inside the program — the runner times the whole process.

Modes: `interp` (tree-walking interpreter), `jit` (`--jit`, whole-program
in-process ORC JIT — experimental), `compiled` (`--compile --opt 2`, ahead of
time), `repl-clang`/`repl-orc` (REPL session A-B, separate section of the
runner). A mode that crashes is recorded as a `FAILED` row (`ok=false`) and
does **not** abort the run or count as a checksum mismatch — only two modes
that both produced a checksum and disagree is a hard failure.

Caveats on `jit`:
- **Actor programs fall back to the interpreter.** `--jit` does not support
  actor programs yet; `actor_pingpong` and `actor_call_storm` print
  `march: --jit does not support actor programs yet; running interpreted` to
  stderr and then run through the tree-walking interpreter. Their checksum
  is correct (so the cross-check passes), but their `jit` timing column is
  measuring the interpreter, not an actual JIT compilation — don't read it
  as JIT throughput.
- **`json_stream` is excluded** — it SIGBUSes (rc=138) under `--jit` on both
  the ORC and clang JIT backends, while `--compile` of the same file is
  green. See `specs/todos/2026-08-25-jit-whole-program-json-stream-sigbus.md`
  for the repro and status.

Run: `bash bench/run_interp_bench.sh` (all modes) or
`bash bench/run_interp_bench.sh --modes interp,jit,compiled --only fib,json_stream`.
