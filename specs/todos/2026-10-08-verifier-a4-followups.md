# A1/A4 follow-ups left after checks 2-3 and pass bisection

Logged 2026-10-08, from `specs/progress/2026-10-07-verify-rc-types-and-pass-bisect.md`.

- **Leak reporting.** `MARCH_VERIFY_TIR_LEAKS=1` has not been swept. Expect the drop-glue
  fallbacks the module doc lists as accepted leaks.
- **Check 5's post-escape contract** ("`EStackAlloc` values do not escape", plan §6). Checks 4 and
  5's Defun contracts landed (`specs/progress/2026-10-12-verifier-check4-repr.md`,
  `specs/progress/2026-10-11-verifier-defun-contracts.md`); this one needs a checking mode in
  `Escape.escape_analysis`, which is a transform.
- ~~**Leak reporting.** `MARCH_VERIFY_TIR_LEAKS=1` has not been swept.~~ Done 2026-10-12:
  `specs/progress/2026-10-12-verifier-leak-sweep.md`. Results:

  | sweep (586 programs: test/native, specs/lang/types/accept, examples) | origin/main | after |
  |---|---|---|
  | leaks off | 0 findings | 0 findings |
  | leaks on | 258-263 per program (258 stdlib), 126,125 over 485 programs | 7 per program (distributed stdlib), plus 15 functions in 11 programs |

  The ~257 stdlib false positives per program were three model gaps, now fixed in
  `tir_verify_rc.ml`: a discarded unit result, a niche `None` arm at a join, and `Some(i)` of a
  tagged `Option(Int)`. The 5 real stdlib leaks were three Perceus bugs, now fixed.

  What is left from the sweep:
  - 7 distributed-stdlib findings: `specs/todos/2026-10-12-distributed-stdlib-leaks-from-verifier-sweep.md`.
  - **False positive, not fixed (verifier design):** `kfst`/`ksnd`
    (`test/native/generic_fn_closure_unused_param_leak_probe.march`). An unused erased parameter
    is borrowed by the `$clo_wrap` protocol (`Clo_flags`), but the verifier reads only the
    borrow map. Fixing the underlying leak
    (`specs/todos/2026-10-12-unused-owned-closure-param-leak.md`) via the borrow map would clear
    this too.
  - **Not triaged**, all leaks-on only: `addr` (`branch_alias_tail_drop`: an erased-type
    parameter holding 2), `dup_pair` (`tuple_destructure_rc`), `width`
    (`record_pattern_partial`), `boxed$own0`/`wrapped$own0` (`record_pattern`), `wild`
    (`niche_aggregate_payload_leak_probe`), three `main` lambdas (`closure_bool_field`: owned
    parameter `r`), and `LedgerActor_spawn`/`CounterActor_spawn` (`examples/lab_app`,
    `examples/topology_app`: a borrowed `env` that ends holding 1). Each needs a `live_allocs()`
    loop to tell a leak from a model gap.
  - **Verifier miss:** a constructor arm with binders on a non-pointer `Atom` scrutinee reached
    codegen as an ICE (`specs/todos/2026-10-12-payload-atom-match-compiled-ice.md`). This is a
    check-4 rule.
  - **Sweep trap:** `MARCH_VERIFY_TIR_LEAKS` is not in the CAS key (only `verify-tir` is). A
    leaks-on compile after a leaks-off one is a cache hit and checks nothing. Clear
    `$HOME/.march/cas` and the cwd `.march/cas` between passes, or key on it.
- **Checks 4 (repr invariants) and 5 (pass contracts)** from plan §6. Check 5 has its Defun
  slice (`specs/progress/2026-10-11-verifier-defun-contracts.md`).
- **`test_oracle` integration (plan §9).** On a compiled-vs-interpreted mismatch, run
  `--bisect-pass` and attach the blamed passes. The reducer needs an oracle command per
  failure, so it is probably opt-in. In the leak sweep, every finding was at `tir-perceus`, a
  mandatory pass, so `--bisect-pass` had nothing to say. For RC findings, `march query fn NAME
  FILE --at tir-perceus` was the useful tool.
- **Expression-level reduction** (plan §9): replace an expression with a literal of its
  inferred type, inline a `let`, drop an unused match arm. `--reduce` only removes
  declarations and lines today.
