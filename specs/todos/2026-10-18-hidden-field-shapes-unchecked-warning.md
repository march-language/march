`[P3]` Element refinements on a type whose fields hide a parameter: warn at the declaration

Filed 2026-10-18 by phase E of
`specs/2026-10-18-abstract-refinements-leftovers-design.md` (§7, the ✱ "silent hole in
Q4 for shapes `Within` does not cover").

Phase E models a constructor field `C(args)` of another registered container whose
arguments are bare parameters or parameter-free (role `Within`,
`lib/refinecheck/refine_encode.ml`). Every other field that holds a type parameter
still hides it:

- a function field: `type Box(b) = Box(Int -> b)`;
- a nested container: `type LL(a) = LL(List(List(a)))` (one level only, design
  decision 7);
- a tuple or record inside a container: `type Wrap(k, v) = Wrap(List((k, v)))`,
  stdlib `Map`'s `HamtMap(HEntry(k, v))`;
- a mixed argument: `type Mq(a) = Mq(Result(a, List(a)))`;
- a field of a container that itself hides the slot: `type Hw(a) = Hw(Hid(a))`
  with `type Hid(a) = Hid(Int -> a)`;
- a permuted or non-parameter self-reference: `N(T(b, a))`, `UN(U(List(a)))`;
- a self-reference under another container: `type Rose(a) = Rose(a, List(Rose(a)))`
  (the `List(Rose(a))` argument is not a bare parameter).

None of these is silent any more: since the multi-arg design's phase 0 a construction
against a refined slot is a recorded `unreflectable-subject` skip (an error under
`cap verified`), and a `match` binder at such a field gets no fact. But the skip
appears only in `--refine-report` and under `cap verified`; a user who writes
`fn mk() : Box({Int | _ > 0})` gets no default-mode diagnostic that the refinement
cannot be enforced.

Wanted: a `refinement_unchecked` warning at the refined type argument
(`Box({Int | _ > 0})`) when the instantiated parameter is in the type's
`ctor_hidden_params`, naming the hiding field (the text `record_elem_skip` already
builds: "`Box`'s field holds `b` inside `Int -> b`, which the element model does not
see into"). Once per declaration site, beside the other `refinement_unchecked`
warnings in `warn_predicate_expr`'s neighbourhood. Check it does not fire on stdlib
signatures that never refine a hidden slot (the oracle's stdlib lines must not move).

Related, separately filed: `2026-10-18-record-element-slot-refinements-unchecked.md`
(records are not registered as containers at all, so `type R(a) = { xs : List(a) }`
is outside both phase 0 and phase E).

Also out of scope for phase E and not filed separately: modelling `Rose`-shaped
fields (a self-reference inside a container) would need the slot map to compose with
`Self`; `List(List(a))` would need `Within` to nest.
