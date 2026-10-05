# `scripts/triage.sh`: the compiler-bug triage ladder in one command

**Date:** 2026-10-05
**Plan:** `specs/plans/diagnostics-and-triage-plan.md` (branch `plan/diagnostics-triage`), §12-§13, item **T1**.

## What it does

`scripts/triage.sh FILE [--opt N] [--expect OUT] [--fn NAME] [--deep] [--timeout N]`
runs the rungs that already exist in the compiler and prints a one-screen report.
It keeps every artifact in a temp dir whose path it prints, and it ends with the
next command to run.

1. **Compiler or program?** `march FILE` vs `march --compile --opt N FILE`. It
   compares stdout and exit code and reports `MATCH` or `DIFFER at line N
   (interp: … / compiled: …)`. `--expect OUT` compares both against a
   known-good stdout instead.
2. **Which optional pass?** It recompiles with `MARCH_NO_UNBOX=1`,
   `MARCH_NO_HOF_SPEC=1`, `MARCH_NO_INLINE_RC=1` and `--no-opt` in turn, and
   the first switch whose output matches the reference is blamed. These four
   are every optional-pass switch: a grep of `contract_pipeline.ml`,
   `llvm_rc_inline.ml` and `bin/main.ml` for `MARCH_NO_` / `--no-` finds only
   them plus unrelated knobs (`--no-cap-strict`, `--no-measure-axioms`,
   `--no-copy-runtime`, `MARCH_NO_RUNTIME_CACHE`). `MARCH_NO_TRMC` is gone. If
   no switch fixes the output, the report names the mandatory passes. This
   rung runs only when the outputs diverged, or with `--deep`.
3. **Which stage?** It makes one `MARCH_DUMP_TXT=all` compile and splits the
   output into `stages/<label>.txt`. For each stage it reports the function
   count and the number of functions added and removed; the names are in
   `stages/summary.txt`. The labels come from the dump itself, not a
   hard-coded list. At `--opt ≥ 1` there are 15 of them, from `tir-lower`
   through `tir-hof-unboxed`. `tir-opt` is printed only under `--no-opt`,
   because Opt's per-pass snaps go to `--dump-phases`, not to
   `MARCH_DUMP_TXT`. So the `tir-escape → tir-native-map-inline` step
   includes Opt and DCE, and the report says so. `--fn NAME` reports the
   first stage where that function's printed body changed. It sorts the
   functions by name and normalises fresh-name digits before comparing, and
   it skips defun's `NAME$apply$N` wrappers.
4. **Sanitizer.** If the compiled run crashed (exit ≥ 128), or with `--deep`,
   it does a `MARCH_SANITIZE=1` rebuild and rerun. It uses
   `ASAN_OPTIONS=detect_leaks=0:halt_on_error=1:abort_on_error=0` unless
   `ASAN_OPTIONS` is already set, and prints 20 lines of the findings. It also
   prints the `MARCH_TRACE_GC=1` + `march analyze-trace` command for leak
   symptoms.

**Isolation.** FILE and its sibling `.march` files are copied into the temp
dir. Every run uses a private `HOME`, the temp dir as its project (so the CAS
there starts cold), and an environment scrubbed of the triage knobs. The
stage-dump compile has its own copy so a warm CAS can't skip the pipeline.

**Timeouts.** Each run is limited to `--timeout` seconds (default 60) and
each compile to `TRIAGE_COMPILE_TIMEOUT` (default 600). A run that times out
gets SIGTERM and then a 5 s grace period. Only the compiler or interpreter is
then SIGKILLed. A compiled March binary that ignores SIGTERM is left running
and its pid is printed, because SIGKILL on a binary wedged in a green-thread
fault path is the state that kernel-panicked a Mac before (see the
`run_capped` comment).

## How it was tested

The compiler was built in the worktree at `fb7e11ff3`, and the script was run
under macOS `/bin/bash` 3.2.57. `bash -n` passes.

- **Matching program** (`hello.march`, a tail-recursive `go` plus `println`):
  `interp exit 0, 2 lines`, `compiled … → outputs MATCH (interp)`, switches
  skipped with the reason given, and all 15 stages with counts. `--fn go`
  reports `body unchanged across all stages` (an Int-only loop that no pass
  rewrites). `--fn main` reports `first changes at tir-mono`, and the next
  line is the `diff` of its two stage files. With `--deep`, all four switch lines
  print `matches interp` and nothing is blamed.
- **Divergence**: a wrapper `MARCH_BIN` runs the real compiler, but for a
  `--compile` without `MARCH_NO_UNBOX` it wraps the produced binary to rewrite
  `55` to `54`. Report: `outputs DIFFER at line 1 (interp: sum 55 / compiled:
  sum 54)`, `MARCH_NO_UNBOX=1 → matches interp ← blamed: unboxing`, and the
  other three `still differs`. This is a fake bug. Everything except the
  output rewrite is the real pipeline.
- **`--expect`** (hello vs a file with `DONE` where the program prints
  `done`): both runs `DIFFER at line 2`, the report marks compiled `(= interp)`,
  skips the switches (the interpreter never sees TIR, so no pass is to blame),
  and next is `diff expect interp.out`.
- **Timeout** (an infinite tail loop, `--timeout 5`): both runs `TIMED OUT
  after 5s (stopped)`, switches `skipped (no reference output)`, and next
  suggests `--expect`. SIGTERM was enough; no pid was left behind.
- **Panicking program with `--deep`**: interp and compiled both `exit 1, 1
  lines`, `MATCH`; the four switches `matches interp`; stages render. The
  sanitizer rung built the ASAN binary and **timed out running it**. It could
  not be checked for findings on this host, where ASAN itself is broken: a
  trivial C `puts("hi")` built with `clang -fsanitize=address,undefined`
  spins at ~100% CPU for over 20 s, inside the agent sandbox and outside it,
  at load averages from 10 to 260. The rung's failure path (timeout reported,
  the leak hint still printed) is what was exercised, not its findings path.
- **Timing**, at a load average of ~10: 40 s for a matching program and 46 s
  for the diverging one with all four switch recompiles. A `--deep` run
  including the 30 s sanitizer timeout took 88 s. During testing, other
  sessions sometimes pushed the load average to 250, and the same runs then
  took up to 40 minutes. That was CPU starvation (the awk got 12 s of CPU in
  32 minutes), not a script problem.

## What it does not do

- It does not bisect commits. That is T2 (`bisect-ir.sh` / `bisect-output.sh`).
- It does not shrink the program, and it does not diff the per-stage TIR
  between the switched and unswitched compiles.
- Stderr is not compared. Interpreted panics print a March stack trace and
  compiled ones don't, so only stdout and exit code count.
- Only sibling `.march` files are copied. A project that needs
  `MARCH_LIB_PATH` deps inherits that variable from the caller's environment.
- When A4's `--disable-pass` / `--list-passes` lands, rung 2 should enumerate
  passes from the compiler instead of using the hard-coded four.
