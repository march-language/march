# DONE 2026-10-12: the TIR verifier's first corpus sweep, with leaks on

The first item of `specs/todos/2026-10-08-verifier-a4-followups.md`:
`MARCH_VERIFY_TIR_LEAKS=1` had never been run across the corpus.

## Coverage

586 programs, each compiled (`--compile`, default opt) with `--verify-tir`, once with and once
without `MARCH_VERIFY_TIR_LEAKS=1`:

- the 369 `test/native/*.march` with an `.expected`;
- the 188 `specs/lang/types/accept/*.march`;
- the 43 `.march` files under `examples/` (some are libraries of multi-file apps, compiled alone).

Each compile ran from its own empty working directory, with `HOME` pointing at a scratch
directory. Two traps showed up while setting this up:

- **A warm post-TIR cache hides the leak check.** The CAS key includes `verify-tir` but not
  `MARCH_VERIFY_TIR_LEAKS`. So a leaks-on run after a leaks-off run hit the cache for every
  program that had compiled, and reported only the 11 that had not. The fix was to clear
  `$HOME/.march/cas` between the two passes.
- **Most failures are not verifier findings.** 20 programs fail with the verifier off as well:
  - 4 FFI fixtures need their C shim at link time;
  - 5 JS/wasm fixtures were compiled natively;
  - 7 `examples/` files: the stale `bastion_tests`, and `csv_server`, which has a type error;
  - `t126` and `t127`, whose entry module is named like a stdlib module (mono refuses the
    representation);
  - `t142`: `from_json` is typecheck-only;
  - `t12`: a codegen ICE, filed below.

## Results

All findings were check 3 (`rc-balance`), reported at `tir-perceus`. There were no check 1, 2
or 5 findings, and no over-release or use-after-release at all.

| pass | origin/main | this branch |
|---|---|---|
| leaks off | 0 findings; 566 compile, 20 fail for the reasons above | 0 findings |
| leaks on | every one of the 577 programs that reaches TIR fails; 485 measured: 126,125 findings, 258 to 263 per program, 258 of them in stdlib | 4,056 findings: 7 per program, all in distributed stdlib code (566 programs), plus 15 functions in 11 programs |

How the 258 stdlib findings per program break down:

| group | per program | verdict |
|---|---|---|
| a discarded unit result (`$rc_N : ()`, the post-call dec wrapper) | ~159 | false positive, fixed in the verifier |
| the nullary arm of a niche `Option` at a join (`case $t: None` holds 1 more) | ~93 | false positive, fixed in the verifier |
| `Some(i)` of a tagged `Option(Int)` holding the scrutinee | ~5 | false positive, fixed in the verifier |
| an owned parameter read in a `let`'s if-value, released by the other arm (`ClusterNode.keeps_new`, `SessionNode.fill_roles`, `Control.leader_report`) | 3 | real leak, fixed in Perceus (`2026-10-12-perceus-param-drop-past-other-candidates.md`) |
| a record destructured in a TRMC'd map with a panic default (`Plot.render_legend`) | 1 | real leak, fixed in Perceus (`2026-10-12-perceus-agg-drop-trmc-store-tail.md`) |
| a let-bound record read by an `if` statement (`ClusterNode__CtlWriter_CtlClose`) | 1 | real leak, fixed in Perceus (`2026-10-12-perceus-agg-drop-partial-release.md`) |
| `Session.ip_step`, `CtlWriter_CtlWrite`, `ClusterNode.start_writers`, `ClusterNode.on_accepted`, `Control.agent_apply_certs_recording`, two `SessionNode.candidates` lambdas | 7 | open, distributed code: `specs/todos/2026-10-12-distributed-stdlib-leaks-from-verifier-sweep.md` |

Each real leak was confirmed at run time with a `live_allocs()` loop, which was not flat
compiled and was flat interpreted. Each fix made the loop flat.

Program-specific findings left, all under `MARCH_VERIFY_TIR_LEAKS=1` only:

- `kfst` / `ksnd` (`generic_fn_closure_unused_param_leak_probe`, `generic_fn_float_closure`):
  false positives. These parameters are borrowed by the `$clo_wrap` trampoline protocol
  (`Clo_flags`), and the verifier reads only the borrow map.
- `need` (`t312`): a real leak. An unused, owned, non-borrowable (`TFn`/`TVar`) parameter of a
  named function is never released on a direct call. The `$clo_wrap` path works around it. Filed
  as `specs/todos/2026-10-12-unused-owned-closure-param-leak.md`.
- Not triaged: `addr` (`branch_alias_tail_drop`), `dup_pair` (`tuple_destructure_rc`), `width`
  (`record_pattern_partial`), `boxed$own0` / `wrapped$own0` (`record_pattern`), `wild`
  (`niche_aggregate_payload_leak_probe`), three `main` lambdas (`closure_bool_field`), and
  `LedgerActor_spawn` / `CounterActor_spawn` (`examples/lab_app`, `examples/topology_app`).
  These are listed in the followups todo.

## The verifier fixes (`lib/tir/tir_verify_rc.ml`)

All three are local and make the model agree with Perceus:

- **Unit is untracked.** `()` is typed `TTuple []`, which `Kind.needs_rc_of` counts as an
  aggregate. Its value is i64 0, and Perceus releases nothing for it
  (`Perceus_core.discarded_call_result_ty`).
- **An arm that found the object immortal holds nothing at the join.** The nullary arm of a
  payload-sharing scrutinee marks it immortal, but the join compared its `held` anyway.
- **`Some(i)` of a payload-sharing scrutinee with a scalar payload is immortal too.** The
  payload is the scrutinee, so there is no cell.

## Red

`test/test_codegen.ml` `tir_verify`, "rc: leak sweep shapes are clean". It runs the real pipeline
(unoptimised, borrow map recomputed from Perceus's input) with `~leaks:true` over one module
holding all six shapes. Against origin/main's `perceus.ml`, `perceus_core.ml` and
`tir_verify_rc.ml` it reports all six. With this branch it reports none.

## `--bisect-pass` and `--rc-trace`

Neither was needed. Every finding was at `tir-perceus`, which is a mandatory pass, so
`--bisect-pass` has nothing to switch off. And `march query fn NAME FILE --at tir-perceus`
showed the missing `dec_rc` directly.
