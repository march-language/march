# `SOfferPending`: an unrefined `offer` continuation is a session state, not a side table

Shipped 2026-09-17. The last open item of
[[2026-07-06-p2-compiler-session-types-protocols-channels]] (its "durable form of the
Finding 1 fix"), done the way that file prescribed: a survey of every `session_ty` match
first, then the constructor.

## What changed

`Chan.offer` on a protocol whose branches continue differently used to hand back a ref at
the FIRST branch's continuation and record that ref in `env.offer_unrefined`, a list
compared by physical identity, which five `Chan.*` chokepoints and the `TChan` unification
arm consulted, and which `with_offer_refinement` had to snapshot, filter and restore
around every refined `match` arm.

Now the ref holds **`SOfferPending branches`**, a `session_ty` constructor. The five
chokepoints ask `session_pending !r`; `with_offer_refinement` sets the ref to the arm's
branch and puts the pending state back after; the field, its initialiser,
`offer_ref_unrefined` and the snapshot dance are gone. The state travels with the ref
through unification, annotations and function boundaries because it *is* the ref's value.

Survey (every `session_ty` match, each extended): `pp_session_ty` (prints
`Offer{…} (branch not yet known)`), `session_ty_equal` / `session_ty_exact_equal`,
`subst_svar`, `dual_session_ty` (the dual of a pending offer is the peer's `Choose`),
`unfold_srec`'s `subst_inner`, and the two projection walks `has_msend`/`has_mrecv`.
The OCaml exhaustiveness warning did not enumerate them -- most have `_` fallbacks, as
the todo warned -- which is why the survey came first.

## What deliberately did not change

The `TChan`/`TChan` unification guard stays. With the state form it is no longer needed
for *soundness* (a fresh ref unified with a pending one is pending too, and every
`Chan.*` op refuses it), but it is the one that produces the useful diagnostic -- "match
on the label first" -- where a plain state comparison would say "session type
mismatch". `reject/t97`–`t99` (label shadowing, a laundered annotation, a laundered
`if` join) pin that wording, and the static-semantics corpus is unmoved: 362/362.

`env.offer_conts` and `env.offer_labels` (label → ref → branches, what a `match` arm
refines by) are a different table with a different job and stay.
