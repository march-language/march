# Closing the postcondition-`let` self-rebinding hole

Filed 2026-09-02. Status: landed 2026-09-02 (`ebdebca6`, `4c1b090e`).
Landed notes, including the corpus measurements and the record arm's status as
a forward guard rather than a live reproduction:
`specs/progress/2026-08-04-postcond-let-self-rebinding-holes.md`.

## Problem

A `let` whose right-hand side is a call with a refined return type files the
callee's return predicate under the `let`'s binder (`scope_add_binding`,
`lib/refinecheck/refine_scope.ml:773-863`). `postcond_of`
(`refine_resolve.ml:204-229`) has already substituted the call's actuals for
the callee's formals, so a name in the stored predicate denotes the value
BEFORE the binding. When the `let` rebinds a name the predicate mentions, the
fact loaders accept the entry's own name as a spelling of the promised value:

- `load_scope_measure_facts`, `refine_call.ml:1393-1486`, `is_self_spelling`
  at `:1403` (`n = b || n = "_" || n = x`);
- `load_scope_tester_facts`, `refine_call.ml:1535+`, the same test at `:1543`;
- `reflect_scalar`'s variable arm, `refine_resolve.ml:480-514`, `rv` at `:496`.

The pre-binding and post-binding values collapse onto one SMT symbol. The
result is not lost precision but a contradictory assumption, and a
contradiction discharges every goal.

Reproduction, still live at `a51a4fc7` (scalar arm):

```march
mod PreScalar do
  fn incr(n : Int) : {Int | _ == n + 1} do n + 1 end
  fn needs_lt(u : Int, v : {Int | _ < u}) : Int do 0 end
  fn go(n : Int, u : Int) : Int do
    let n = incr(n)
    needs_lt(u, n)        -- demands n < u for an ARBITRARY u
  end
end
```

`--check --refine-report`: `2 proved, 0 violated, 0 trusted, 0 skipped`. The
assumption is `n == n + 1`, false, so the impossible goal is proved.

The ADT/measure arm (`refine_scope.ml:857-860`) was closed on 2026-08-04 with
`not (expr_mentions (pat_binders b.A.bind_pat) pred)`, pinned by
`post-compose-relational` case 3. The scalar arm (`:853-854`) and the record
arm (`:855-856`) have no guard. `scope` entries carry no provenance
(`refine_scope.ml:295`, a bare `name -> (binder, pred, sort)` triple), so a
consumer cannot tell a parameter entry from a postcondition-derived one.

## Non-goals

- No provenance tag on `scope`. It would touch the type, three producers and
  three consumers, and it cannot recover the pre-binding value either (the old
  symbol is retired by `scope_shadow` at `:778` before the new entry is made).
  The guard reaches the same precision with one change.
- No change to parameter entries (`scope_add_param`) or to the annotated
  `let` arm (`:780`). An annotation mentioning its own binder means the NEW
  value, which is correct.

## Design

Guard the two remaining postcondition sub-arms exactly as the ADT arm is
guarded. In `scope_add_binding`:

```ocaml
| Some (binder, pred, m)
  when scalar_sort_of_marker m <> None
       && not (expr_mentions (pat_binders b.A.bind_pat) pred) -> ...
| Some (binder, pred, Some srt)
  when is_record_sort srt
       && not (expr_mentions (pat_binders b.A.bind_pat) pred) -> ...
```

When the predicate mentions the binder, no entry is filed and the obligation
falls through to the existing skip path. The tester loader and
`reflect_scalar`'s `rv` need no change: a self-mentioning postcondition entry
is never created, so no consumer can see one.

Factor the guard into one helper, `self_mentioning pat pred`, used by all
three arms, so the next arm added cannot forget it.

## Testing

- The `PreScalar` reproduction: `2 proved, 0 skipped` becomes
  `1 proved, 1 skipped` (the postcondition of `incr` still proves; the call
  is undecided). Assert on the ledger, not on a boolean.
- A record-arm reproduction of the same shape, built from an existing
  `post-compose-relational` record fixture, with the same assertion.
- Mutation: remove the guard from either arm and the corresponding case must
  fail. The existing ADT case stays green throughout.
- A positive control: a `let` that rebinds a name the predicate does NOT
  mention keeps its entry and its obligation stays proved. Without this the
  guard could be widened to "always decline" and the suite would not notice.

## Measurement and oracle

Run `scripts/refine-oracle.sh` (baseline from `origin/main`, RED-proof first).
The expected diff is small. Every `proved` that becomes `skipped` must be a
self-mentioning rebind; list each in the progress note. A `proved` lost for
any other reason is a bug in the guard. Corpus-wide `proved` counts before and
after go in the progress note.

## Cost

One `expr_mentions` walk per postcondition-derived `let`. Negligible.
