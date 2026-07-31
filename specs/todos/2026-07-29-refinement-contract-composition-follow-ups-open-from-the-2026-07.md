# Refinement contract composition follow-ups (OPEN, from the 2026-07-29 call-boundary composition work)


- **A caller-established runtime GUARD is a different mechanism** from a
  caller's declared contract. `if List.length(ys) > 0 do head(ys)` already
  worked (the `len` alias, 2026-07-28) and is untouched. Which shape you have
  decides which machinery you get.
- **Postconditions compose no measure through a return refinement.** Narrowed
  2026-07-30: `check_post` now *files* an obligation at every exit (so
  `--refine-report` counts return refinements) and `cap verified` escalates an
  undischarged one. What remains open is composition — a list or ADT measure
  still does not carry through a return refinement to a caller's goal.
- **The measure-alias gates are still unit-global**, except the selector-less
  `use X.List` arm, which since 2026-07-31 resolves its target and withdraws
  only if some match can provide the aliased member. The member gate,
  `alias … as List`, `import X.{List}` and the glob fuel bound stay coarse on
  purpose — no measurement implicated them.

**Follow-ups.**
- ~~**A tag refinement still does not forward.** `{Option(Int) | is_Some(_)}`
  passed on to a callee with the identical contract stays skipped
  (`1 proved, 1 skipped`, the proof being the outer literal). Tag facts are
  established at the call site by a constructor literal or a `match` narrowing,
  not carried by a binding, so this is the one refined form composition does not
  cover.~~
  **CLOSED 2026-07-29** — `load_scope_tester_facts` (`lib/refinecheck/refine_check.ml`,
  the tester analogue of `load_scope_measure_facts`, wired into `check_call`'s
  `resolve_tester` before it reflects the actual) loads the caller's own tag
  promise over the same `Const x` datatype term the goal side builds, so
  `fn outer(p : {Option(Int) | is_Some(_)}) do inner(p) end` now reports
  `2 proved, 0 violated, 0 skipped`. All three spellings of the refined value
  compose (`_`, a declared binder, the parameter's own name). Deliberately
  narrow: the loader fires only when the caller promises the SAME constructor
  the goal tests — a caller promising `is_None(_)` into a callee wanting
  `is_Some(_)` loads nothing and stays skipped (assuming it verbatim would also
  be sound and would report the call, but it is a wider claim than "the caller
  already promised the goal"). Rebinding (`let p = None`) or a `match`-arm
  binder of the same name retires the fact. Bracketed by `accept/t129` /
  `reject/t130`; +6 refinecheck tests (352 → 358).
- **No local `let` carries a value forward into a later goal, for ANY type.**
  `let u = 5` then `take_pos(u)` against `{Int | _ > 0}` is skipped, and the
  `List` analogue behaves identically. Pre-existing and general (it is also why
  rebinding a refined parameter leaves the call skipped rather than reported);
  the workarounds are to pass the value directly or restate the fact with
  `assert`.

---
