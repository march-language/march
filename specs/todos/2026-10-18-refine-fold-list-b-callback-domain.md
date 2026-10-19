`[P4]` Refinement: a callback parameter typed `List(b)` gets no accumulator hypothesis

Filed 2026-10-18 with phase 2 of `specs/2026-10-18-fold-accumulator-invariants-design.md`
(§2.2's second corollary and §7). The invariant hypothesis is given only to a callback
parameter whose declared domain is EXACTLY a demanded type variable (`invariant_params`,
`lib/refinecheck/refine_check.ml`). For a callee like

```march
fn collect(xs : List(a), z : b, f : List(b) -> a -> b) : b do …
```

the step's first parameter holds values of `b` the callee already held, so by the same
induction it could assume the demand on `b` of every ELEMENT (`List({b | D})`, a container
entry with the demand in its slot). Not built: v1 declines it, and the step is then checked
without the hypothesis (a skip, never a false proof). No stdlib combinator has this shape
today; build it when one does. Anything under a domain's own domain is refused by
`consumer_only` and stays so.
