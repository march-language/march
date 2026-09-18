# A record field that holds a linear value is tracked like a linear field

Shipped 2026-09-19. A soundness hole left by
[[2026-09-13-linear-generic-code-and-containers]], found while designing multi-session
hosting for choreography ([[2026-09-18-choreography-access-points]]).

## The hole

Per-field linearity tracking (the move-out rules for record and actor-state fields,
`bind_linear_field_sentinels` and friends) asked one question of a field: is its *own*
type linear? `field_linearity` answered yes for a `linear`/`affine` qualifier or an
`always_linear` type, and no for everything else. The containment rule that shipped on
2026-09-13 promoted a *binding* whose type holds a linear value (a tuple component, a list
element, a variant payload) but deliberately left records out, because their fields are
tracked individually. Nothing connected the two, so a field of type `Option(S1)`,
`List(S1)` or `(S1, Int)` was an ordinary field:

```march
actor Holder do
  state { slot : Option(S1) }
  on Forget() do
    { slot: None }                 -- accepted: the S1 inside is dropped
  end
end
```

For choreography this is the difference between an actor that holds one session in
`parked : Parked_B`, which was protected, and one that holds `Option(Parked_B)`, which
could lose a live session silently. It applied to plain records too: `r.slot` could be
read twice, handing out the one `S1` twice.

## The fix

`field_linearity` (`lib/typecheck/typecheck_unify.ml`) now also returns `Linear` for a
tuple or a `TCon` that holds a linear value by ownership, using the same
`contains_linear ~records:false` test that `holds_linear` uses for bindings. The two
functions become mutually recursive. Every existing per-field rule then applies unchanged:
the field must be consumed exactly once per turn and replaced before the handler returns.

A field whose type is itself a record is not promoted. Its own linear fields would need
their own sentinels, and promoting the whole nested record would count every read of an
ordinary inner field (`state.inner.n`) as a use of it. That case is unchanged and remains
open; it did not come up in anything the corpus or stdlib contains.

## Evidence

- `reject/t244` (an actor drops its `Option(S1)` field) and `reject/t246` (a record's
  `Option(S1)` field read twice): both **accepted by `main`'s checker** (the hole) and
  rejected by this one, checked by swapping in `main`'s `typecheck_unify.ml` and
  rebuilding.
- `accept/t245`: the legal shapes (the field consumed and replaced; ordinary fields still
  read freely).
- The static-semantics corpus is otherwise unmoved (365/365), and the full test tree and
  alcotest suite pass.

**Note for the merge:** new `reject/` fixtures must also be mirrored in
march-language/march-lean (the corpus INDEX's two-repo rule): after this lands, confirm the
dispatch run there is green or ledger a skip.
