`[P3]` Refinement: P1 cannot see through a record-typed parameter, so `SortedSet.fold` / `OrderedMap.fold` get no accumulator invariant

Filed 2026-10-18 with phase 3 of `specs/2026-10-18-fold-accumulator-invariants-design.md`
(§6 asked for a probe of these two, "phase 1, if P2 holds for `tree_fold`"). Probed on the
phase-3 branch: both are annotated, but a demand through either is a skip,

```march
need_nn(SortedSet.fold(SortedSet.from_list(xs, icmp), 0, fn (a, _x) -> a + 1))       -- parametric-source-unproved
need_nn(OrderedMap.fold(OrderedMap.from_list(xs, icmp), 0, fn (a, _k, _v) -> a + 1)) -- parametric-source-unproved
```

with the detail "`SortedSet.fold` is not known to be parametric in its return type". The cause
is P1, not P2: the collection parameter is a RECORD type (`s : {cmp: a -> a -> Int, tree:
AvlTree(a)}`), and `Refine_param.align` has no `TyRecord` case, so a declared record that
mentions a type variable does not align and `generic_in_inferred` answers no. A user fold
shows the same split: `fn rf(s : {t: List(a)}, acc : b, f : b -> a -> b) : b` is a skip,
the tuple twin `fn tf(s : (List(a), Int), acc : b, f : b -> a -> b) : b` proves.

A lost proof, never a false one. Fix: an `align` case for `A.TyRecord` against `T.TRecord`
(fields matched by name, same count; anything else keeps answering no), with a P1
perturbation row (a record parameter whose field type variable is unified with the return
variable must still be rejected). Pinned as skips in `test/test_refinecheck.ml` group
`fold-invariants-3`; flip those pins to proofs when this lands.
