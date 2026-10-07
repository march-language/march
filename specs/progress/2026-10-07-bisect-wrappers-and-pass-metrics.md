# DONE 2026-10-07: T2 bisect wrappers; A6 per-pass metrics and Opt convergence

Diagnostics plan (`specs/plans/diagnostics-and-triage-plan.md`) §15 (T2) and
observability plan (`specs/plans/incremental-codegen-cas-plan.md`) §10 (A6).

## T2: `scripts/bisect-ir.sh` and `scripts/bisect-output.sh`

`GOOD BAD FILE`. Both run `git bisect run` in a throwaway `git worktree` with a
private `HOME`, so the user's checkout is untouched. A commit that does not
build is skipped (exit 125). Both print the blamed commit with its subject and
the `specs/progress/` entry its message names or (relative to its first
parent) adds. When GOOD and BAD already agree they print "no change" and
bisect nothing.

- **`bisect-ir`** keys on the sha256 of `--emit-llvm FILE`. It rebuilds
  `bin/main.exe` per step and uses the step's own stdlib (`MARCH_STDLIB`).
- **`bisect-output`** keys on the compiled program's stdout plus exit code. The
  expected behaviour is `--expect OUT`, or the behaviour at GOOD. The run is
  time-boxed with `--timeout`.

Two findings changed the design while testing:

1. **First-parent bisection.** A plain bisect over #807..#814 blamed a commit
   inside #808's branch. PR branches sit on older bases of `main`, so their
   commits differ from GOOD for reasons that have nothing to do with the change
   being hunted. Both scripts use `git bisect start --first-parent`, so the
   blamed unit is the PR or merge-train merge that brought the change onto
   `main`.
2. **Fresh-name normalisation (`bisect-ir`, default; `--exact` disables).**
   Several fresh-name counters are global (the B1 problem), so a commit that adds
   one lambda anywhere in the stdlib renumbers every `$lamN` in every program.
   Measured: 6aa0422ec (a `topology.march` edit) changed the raw IR hash of
   `test/native/closure_call_arg_ownership_probe.march`, and its whole diff was
   `$lam43315` becoming `$lam43316`. Before hashing, every `$<name><digits>` and
   numbered `%` local is renumbered by first appearance.

**Plan deviation, `bisect-output`:** the plan says "full `dune build --root .`
per step, because a targeted build does not restage `runtime/`". A target-less
build can wedge at 0% CPU on this repo, so instead each step builds
`bin/main.exe` and points the compiler at the step's own source trees,
`MARCH_RUNTIME_DIR=<worktree>/runtime` and `MARCH_STDLIB=<worktree>/stdlib`.
The guarantee is the same: every step compiles against its own runtime, and the
CAS key digests the runtime directory in use.

Tested on known pairs:

| Script | Pair | Result |
|---|---|---|
| `bisect-ir` | #807's parent → #807, `closure_hof.march` | "no change" (identical IR), 24 s |
| `bisect-ir` | #807 → #814, `closure_call_arg_ownership_probe.march` | blamed **#808**, whose merge brings `march_clo_release` calls in place of `__march_rc_decrc_local` (544 normalised IR lines differ); progress entry printed, 24 s |
| `bisect-output` | a4b01bd4e → 521d77eca, a program printing `int_max_value()` | blamed **#736** (`9223372036854775807` → `4611686018427387903`), progress entry `2026-09-30-int-63-bit-overflow-parity.md`, 65 s |
| `bisect-output --expect` | #736 → 521d77eca | "no change: BAD behaves as expected" |

## A6: per-pass counts on the `--timings` stamps

`lib/tir/tir_metrics.ml` computes static counts over a module:

| Count | Meaning |
|---|---|
| `fns` | functions |
| `allocs` | `EAlloc`/`EAllocHole` sites |
| `stack` | `EStackAlloc` |
| `inc` | RC increments |
| `dec` | RC decrements and frees |
| `reuse` | `EReuse`, and `EAllocHole` with a token |
| `jp` | `FnJoinPoint` fns plus `$jp` binders |

Under `--timings`, `Contract_pipeline.run ~stamp_metrics` puts them on the same
line as each pass's stamp (`mono`, `fusion`, `defun`, `perceus`, `drop`,
`escape`, `opt`, `alloc-contract`), and the driver adds them to its `lower`
stamp:

```
[timings]  2.813s  perceus  fns=6328 allocs=8806 stack=0 inc=5839 dec=26671 reuse=1715 jp=688
```

`scripts/compile-time-bench.sh` parses the label as `\S+`, so its parsing is
unaffected. Without `--timings` nothing is computed.

Pinned for three snapshot programs (`fbip_dead_binding_reuse`,
`trmc_modulo_cons`, `closure_hof`) at each harness stage, in
`test/snapshots/metrics/*.expected`. They regenerate with `UPDATE_SNAPSHOTS=1`.

## A6: Opt reaches its fixed point

`Opt.run` now records `last_converged` and `last_iterations`. `test_snapshots`'s
`opt_convergence` runs the whole `Contract_pipeline` with `~opt:true` over the
28-program snapshot corpus and asserts that the final iteration changed
nothing. That is convergence, not idempotence: the 5-iteration cap is the
design, and Perceus is not idempotent, so it is not tested this way. All 28
converge. Red: forcing the loop never to stop on "no change" fails it with
"guard_match: Opt converged (iterations: 5 of 5)".
