# `[P2]` Role module: a consumer for a closed parked value (`take_closed`)

Filed 2026-09-20 while shipping hosted offers
([[2026-09-20-choreography-access-points-a2]]).

`<P>_<Role>.finish(s, st)` and `cancel(p)` return a `Parked_<Role>` in its
`Closed_<Role>` state. The value is linear, nothing can resume it, and an actor that
hosts many sessions in a `LinearMap` must drop it to vacate the session's slot. But:

- matching `<P>_<Role>.Closed_<Role>(_)` from the user's module fails with "I cannot find
  `Secret`": the constructor's payload type is private to the generated role module;
- the role module has `take_idle(p)` for an `Idle_<Role>` but no consumer for a
  `Closed_<Role>`.

The fixtures (`test/two_node/cluster_ap_hosted*`) and the guide drop it through a
user-side `pfn retire(linear p : a) : () do let _ = p; () end`, which works only because
the checker does not check the body of a function for its `linear` parameter's use (the
error for a generic drop says to "mark it `linear` where it is defined", and that is
taken on trust). Two things to do:

1. Generate `take_closed(p : Parked_<Role>) : ()` in the role module (beside `take_idle`;
   `lib/desugar/desugar_endpoints.ml`, `role_module`), matching `Closed_<Role>(_)` and
   panicking on the other constructors; switch the fixtures and the guide's `retire` to
   it.
2. Decide whether a `linear` parameter's body should be checked for exactly one use
   (today it is not), or document that `linear x : a` is an opt-in the caller trusts.
