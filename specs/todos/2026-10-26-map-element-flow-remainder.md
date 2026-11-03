`[P3]` Element flow through the rest of `Map`, and through `HashMap` / `Set`

Filed 2026-10-26 by `specs/progress/2026-10-26-map-element-flow.md`, which closed
`map-element-flow-through-combinators`: `insert`, `get`, `get_or`, `remove`, `keys`,
`values`, `merge`, `map_values` and `singleton` now carry a refined map's key and value
facts by parametricity, through the opaque-container source rule.

Still a skip:

```march
need_vals(Map.insert(Map.empty(), "a", 3, Map.str_cmp))   -- parametric-source-unproved
```

- **`Map.empty()`** has no parameter, so P1 (`generic_in_inferred`) has no witness for
  `k`/`v` and answers no. A zero-parameter function generic in its return's variables
  cannot make a value of them (P2 still applies), so a P1 rule "a variable no parameter
  mentions is vacuously generic, with no sources" would make it a source with no
  sources. That needs its own soundness check (P1 exists because annotation variables
  unify: `fn e() : Map(k, v) do Map.singleton("a", 0 - 5) end` typechecks).
- **`merge_with(a, b, f, cmp)`**: unannotated; `f : v -> v -> v` (curried) is a codomain
  source as well as `a` and `b`.
- **`from_list`, `to_list`, `entries`**: their element side is `List((k, v))`, and tuple
  elements are not modelled (`2026-10-21-tuple-elements-list-of-pairs-abstract.md`).
- **`HashMap`** (`put`, `get`, `delete`, `values`, `merge`, `map_values`, …) and **`Set`**
  are `ptype`s too, so the rule applies once their functions are annotated with their
  generic types, each with a `Check.all` witness as in `test/stdlib/test_map.march`. Not
  done in the same PR, to keep the stdlib diff reviewable.
