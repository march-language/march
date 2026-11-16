`[P1]` `@invariant` is never checked on `init` or on handler results

Found 2026-11-06 while building the guarantee report (phase B of
`specs/2026-11-04-lemmas-hcr-actors-choreography-design.md`).

```march
@invariant(count <= limit)
actor Counter do
  state { count : Int, limit : Int }
  init { count: 50, limit: 10 }
  on Inc(n : Int) do { state with count: state.count + n } end
end
```

`march --check` accepts this with no diagnostic. The refinement checker only walks the
invariant expression for its own obligations (`Refine_check`, the `DActor` arm); nothing
obliges `init` to establish it or a handler to preserve it. It is used only across a hot
deploy: as the migration's goal (the live-data check, M10, and the deploy gate's old ⇒ new
implication) and, from the deployed baseline, as a hypothesis (`Hcr_baseline`). A user who
writes `@invariant` will read it as "always true of every live actor", which the build does
not establish. That is the design's "never silent" rule (§1.3) broken for the one guarantee
it calls tier 2.

`march --check --guarantees` labels it `not checked`, so it is no longer silent there, but
the check itself is missing.

Fix: treat `@invariant` as an inductive invariant of the actor.

- `init`'s record must satisfy it (an obligation at the record, like a field refinement).
- Each handler assumes it of `state` on entry and must re-establish it of the record it
  returns (every tail position).
- A violation is a `refinement_violated` error with the handler and a counterexample state;
  an undecided one a `refinement_unverified` hint, and an error under `cap verified`.

The vocabulary is the one the deploy gate already reads (`hcr_pred_to_string`): comparisons,
arithmetic, `&&`, `||`, `not`, field access, one-argument measures. Phase F's M2 (an
invariant elaborated to a reflected `<actor>_inv(state)`) widens it later.

## Resolution — 2026-11-08

The first slice of phase F (lemmas design §7) and of todo
`2026-11-06-actor-inductive-invariants`: the `@invariant` is now an inductive invariant of
the actor, checked on every build.

- `Refine_check`, `DActor` arm, step (4): `init` and each handler are stated as a function
  returning the state under `{v : <Actor> | inv(v)}` (handlers take
  `state : {s : <Actor> | inv(s)}` plus their parameters, refined exactly when the body walk
  assumes them; `init`'s parameters stripped) and checked by `check_fn_post_verdict`. The
  predicate's bare field names (and `state.f`) are rewritten to selectors with
  `Refine_encode.subst_params`. Ledger rows `<Actor>.init` / `<Actor>.<Msg>`
  (postconditions).
- `Refine_post.post_subject` / `with_post_subject`: the violation, its note and the
  `cap verified` escalation are worded as the invariant's ("`Counter`'s handler `Dec` does
  not preserve its `@invariant`.", the predicate as written), never as a return type the
  program does not contain.
- The return-contract checker needed four fixes, each also a fix for ordinary
  record-returning functions:
  - `{ r with f: e }` over a named `r` reflects (the literal with `r.g` for the other
    fields; a variable base only, so one value's fields cannot disagree in a model);
  - a refined record parameter returned as it is (`state`) is declared at its datatype
    sort, not re-declared at `Int` (it was a `sort-conflict` skip);
  - a record return reads its simple `let`s inlined (`record_body`: call statements
    dropped, then `inline_lets`), and `expr_vars` / `subst_let` model record literals and
    updates;
  - a body-bound name the tail or its path still mentions, with no `let r = f(…)` contract
    standing for it, makes the tail `opaque_tail`: a model is then no counterexample. Before,
    `let next = c + n` ahead of `{ count: next }` was REPORTED violated with `next = -1`
    (a false positive in any record-returning function, not only actors).
- `--guarantees`: the `@invariant` line reads those rows (`proved: N sites at init and after
  each handler`, `violated`, `not proved`), no longer a fixed `not checked`.

Tests: `test_refinecheck` suite `actor-invariant` (7 cases: the guarded counter, the
unguarded decrement with its counterexample, a bad `init` and an unrefined message, two
actors sharing a message name, a call handler plus a let-bound field and the `state.f`
spelling, an undecidable invariant (skip; error under `cap verified`), and the plain-function
record fixes). Each mechanism was shown to go RED: the check disabled turns 0-5 red;
`record_body` disabled turns 4 and 6 red; `opaque_tail` ignored turns 6 red; update
reflection disabled turns 0-4 and 6 red; the record-sort `scalar_of` arm disabled turns 0, 4
and 6 red. `guarantees` case 0 now pins `@invariant proved: 2 sites`.

## Residual (todo `2026-11-06-actor-inductive-invariants`)

- Handlers are not yet reflected as `<Actor>.step`, so a lemma cannot state an invariant
  over a handler, and the migration-simulation law (H3) has nothing to name.
- The report says `proved`, not the todo's `proved (inductive)`, and lists no boundaries.
- A handler that returns through a `match` arm the walk marks opaque, or binds a field value
  through a destructuring `let`, is an honest skip, not a proof.
- The invariant's vocabulary is the refinement checker's (a function it cannot reflect is a
  skip); M2 (an invariant elaborated to a reflected `<actor>_inv`) widens it.

## M2 — 2026-11-08: an invariant may call the program's own functions

`@invariant(not_137(count))` was an `unreflectable-predicate` skip at every site, though the
same predicate proved as a plain function's record contract. Two causes, both fixed:

- `Refine_term` never walked an actor's `@invariant`, so its calls had no reflection site
  (calls resolve by span). It is now walked once, with the actor's first handler, with
  `state` and the field names bound.
- The check now runs in the context a top-level function's return check gets: the module's
  reflection prefix (`Refine_post.lemma_prefix`), proved callee returns (`with_post_lookup`)
  and the scalar tail demand. The rewritten predicate keeps each field read's own span.

Test: `actor-invariant` case 6 (`not_137` proves under a guard; without it, `Inc` reaching
137 is a violation). RED: the `Refine_term` walk off turns case 6 red. The design's M2 as
written (an invariant elaborated to a reflected `<actor>_inv(state)`) is not needed for this:
the invariant is checked as a predicate over the state, which reflection now unfolds.
