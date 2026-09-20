# Mutual TCO: do not flatten a group that would free a forwarded argument early

Implements the fix for [[2026-09-20-mutual-tco-borrowed-forwarded-arg]] (P1). Read it
first: the repro, and why "emit the drop" (use-after-free) and "skip the drop" (leak) are
both wrong.

## Decision

**Option 1 of the todo: a mutual-TCO group is flattened only when every back edge is
safe.** A back edge is unsafe when its Perceus dec chain contains a `DecRC` (or drop-fn
call) whose target is one of the call's forwarded arguments and that argument is NOT
dup-bound (`Llvm_tco.dup_bound_vars`). For such a group, no combined `__mutco_` function
is emitted: the members are emitted as ordinary functions and their tail calls are real
calls. Correctness first; the loop is a performance feature, and this shape was
miscompiled.

Why not the other options now: a pending-drop list (option 2) is a runtime cost on the
transform's hot path and a bigger change; an owned-only rule (option 3) is option 1 with
a different predicate. Option 1 can ship today with a witness, and the todo stays open for
option 2 as a follow-up (rewrite it to say so; do not delete it).

Self-TCO is NOT changed by this: it skips the drop (the leak side) and has its own tests
(`test_tco_self_dup_arg_decref_on_live_path`). Note in the progress record that it has
the mirror problem; do not widen the scope.

## Files

`lib/tir/llvm_tco.ml`:
- `find_mutual_tco_groups` (the SCC filter, ~line 260-290) gets one more condition,
  `group_back_edges_safe`: walk each member's body for the two Perceus-wrapped shapes the
  arms handle (`ELet (tmp, EApp (f, args), body)` with `is_trivial_dec_chain_returning`,
  and `ESeq (EApp (f, args), dec_chain)` with `is_trivial_dec_chain`) where `f` is a group
  member; for each, compute the forwarded non-dup-bound arg names as
  `Llvm_emit_tcoarm` does and check no cleanup op in the chain targets one
  (`Llvm_tco.cleanup_target`). If any does, the group is not a TCO group.
- Put the predicate next to `dup_bound_vars` so the arms and the filter share the
  vocabulary; a comment must explain the tension (drop = UAF, skip = leak) in two
  sentences and point at the todo.

`lib/tir/llvm_emit_tcoarm.ml`: unchanged (the arms are only reached for safe groups now).
Do NOT add the skip rule to the mutual arms.

## Tests

- `test/native/mutual_tco_forwarded_arg.march` + `.expected` already exist (the repro,
  expected output from the interpreter). Add the `test/dune` golden rule (copy any
  `native_*` pair, e.g. `native_task_await_discarded`) and the two lines the refinement
  audit wants: `UPDATE_SNAPSHOTS=1 ./_build/default/test/test_refinecheck.exe -e
  'audit-baseline'` (needs z3 on PATH; ~8 min; run it ONCE, foreground, and diff
  `test/refine_audit/corpus.baseline` to see only the two new lines). Verify RED first:
  with the predicate disabled the golden differs (`refused: no-y; refused: no-y`).
- `test/test_codegen.ml`, group `mutual_tco_codegen`: **rewrite
  `test_mutual_tco_borrowed_arg_decref_on_live_path` ("B7")**: its fixture
  (`build_loop` / `consume_loop` forwarding `prefix` to a borrowed parameter and dropping
  it after) is exactly the unsafe shape, so the correct assertion is now that NO
  `mutual_loop` is emitted for it (and that its `march_decrc` is present as an ordinary
  post-call drop). Keep the test's name and its doc comment, appended with why it
  flipped. Add a new case proving a SAFE group still gets its loop: even/odd over ints
  (no heap args) and a group forwarding an OWNED list (`Cons(_, t)` walk where `t` is
  dup-bound, the `test_tco_self_dup_arg_decref_on_live_path` shape but mutual).
- A leak check for the refused shape: extend `test/native/mutual_tco_forwarded_arg.march`'s
  second half (it already asserts `live_allocs` delta < 1000 over a 20000-element walk)
  -- it passes when the group is not flattened, which is the point.
- Snapshots: `./_build/default/test/run_snapshots.exe -e` must pass unchanged (no fixture
  in the snapshot corpus has this shape; if one does, the diff IS the review artifact --
  regenerate with `UPDATE_SNAPSHOTS=1` and explain in the PR).
- Benchmarks, compiled only: `bench/fib.march` and `bench/list_ops.march` at `--opt 2`,
  alternating A/B against a compiler built from main, best of 3 after one warm-up run
  each. Report the numbers; a regression means a benchmark had a mutual group that is now
  refused, which the PR must call out.

## Records

`specs/progress/2026-09-20-mutual-tco-safety.md`; rewrite the todo to "option 1 shipped;
option 2 (keep the loop by deferring drops to loop exit) still open"; CHANGELOG under
Fixed: a compiled program with two mutually tail-recursive functions passing a string or
list along could read freed memory (or, with the naive fix, leak); such groups now run as
ordinary calls.
