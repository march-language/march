# bench/interp — scaled corpus for interpreted / REPL-JIT / compiled A-B

`bench/*.march` sizes are tuned for compiled code (fib(40), 100k-element
strings). The interpreter is 100–400× slower, so this directory holds the
same workloads at sizes that finish in 1–20 s interpreted.

Rules:
- every program prints exactly one `checksum=<int>` line; the runner diffs it
  across modes and fails on mismatch;
- `main` takes the narrowest capability grant it needs;
- no timing inside the program — the runner times the whole process.

Run: `bash bench/run_interp_bench.sh` (all modes) or
`bash bench/run_interp_bench.sh --modes interp,compiled --only fib,json_stream`.
