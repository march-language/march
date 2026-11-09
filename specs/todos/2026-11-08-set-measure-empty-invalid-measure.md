`[P2]` A set-valued `@[measure]` that uses `empty` is refused: "is not reflected: it names empty as a value".

Found while writing the ghost-code worked example (2026-11-08).

```march
type Tree = Leaf | Node(Tree, Int, Tree)

@[measure]
pfn content(t : Tree) : Set(Int) do
  match t do
  Leaf -> empty
  Node(l, v, r) -> union(content(l), union(singleton(v), content(r)))
  end
end
```

`march --check` reports `invalid_measure`: `` @[measure] `content` is not reflected: it names
empty as a value ``. The measure's axioms still work (a postcondition stated with `content`
proves), so the error is in the attempt to also reflect the body: R7
(`lib/refinecheck/refine_reflect.ml`, `site_events`) treats the set vocabulary's nullary
`empty` as a reference to a function value. `stdlib/sorted_set.march`'s `sorted_set_elts`
has the same shape, and its diagnostic is filtered as stdlib-internal.

Fix: accept the set vocabulary (`empty`, and any other nullary set constructor) in a set-valued
measure's body, as the body's own vocabulary binding already does. Add a reject/accept pair to
the reflection suite.
