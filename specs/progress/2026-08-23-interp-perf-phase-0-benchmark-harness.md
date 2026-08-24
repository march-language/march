# Interpreter/REPL-JIT A-B benchmark harness (Phase 0, task 0.7)

**What:** `bench/run_interp_bench.sh`, an A-B runner over `bench/interp/` that
times each benchmark under `interp` (tree-walking eval), `compiled`
(`--compile --opt 2`), and the REPL under both JIT backends (`repl-clang`,
`repl-orc`), cross-checking `checksum=` output between `interp` and
`compiled` and failing hard on any mismatch. Also drives `http_server` (start
server, hammer it with `bench/interp/http_client.py`, kill it, verify no
survivor process) and a fixed `repl_session.txt` transcript. Emits one JSON
line per run to stdout/`bench/results/<date>-interp-<arch>.jsonl` and a
markdown min/median table to stderr.

**Why:** the interpreter-performance and REPL-JIT work (this SDD) needs a
repeatable, checksum-verified way to catch a regression or confirm a win
across all three execution modes before/after each phase's changes, without
hand-timing individual `.march` files.

**How to run:**
```bash
bash bench/run_interp_bench.sh --runs 3                      # full A-B, all modes
bash bench/run_interp_bench.sh --only fib,string_split --runs 1   # quick smoke
bash bench/run_interp_bench.sh --modes repl-clang,repl-orc --runs 3
```

The runner and 1-run smoke validation (ok=true across every row, all modes
including `http_server` and both REPL backends) landed 2026-08-24 at commit
`8bfe5455`. The 3-run committed baseline capture (`--runs 3`, tag
`baseline-8bfe5455`) is **deferred** to a quiet-box window — a concurrent
session on this shared machine was running `steady_state_ring` benchmarks
from another worktree during this session, which would have contaminated a
timing baseline (see `project_bench_load_contamination` in memory). See
`.superpowers/sdd/2026-08-23-interpreter-and-repl-jit-performance/task-0.7-report.md`
for the smoke-run table and deferral details.
