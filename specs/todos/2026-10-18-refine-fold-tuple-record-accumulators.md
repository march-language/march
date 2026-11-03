`[P4]` Refinement: a tuple or record fold accumulator gets no invariant

Filed 2026-10-18 with phase 2 of `specs/2026-10-18-fold-accumulator-invariants-design.md`
(row f21 and §7, "Tuple and record accumulators"):

```march
match List.fold_left(ys, (0, 0), fn (cs, x) -> …) do
  (c, _) -> need_nn(c)          -- skip, unconstrained-subject
end
```

The demand lands on a COMPONENT after the `match`, not on the fold's result type variable
`b`, so neither the scalar entry point nor the container one (`demand_flow`) sees a demand on
`b` at all. A fix would carry a component demand back through the destructuring to the call
(the tuple path of leftovers phase C, `tuple_self_hyp` / `abstract_flow ~component`, is the
closest existing machinery) and instantiate `b` with a tuple of refinements, with each
component of the step's accumulator parameter assuming its part. Until then this is a skip,
never a false proof.
