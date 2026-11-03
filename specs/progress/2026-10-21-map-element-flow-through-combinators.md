`[P3]` `Map`'s own functions carry no element fact (`insert`, `remove`, `get`, `merge`, `map_values`)

Filed 2026-10-21 by phase 4 of the multi-arg abstract refinements design
(`specs/2026-10-18-abstract-refinements-multi-arg-design.md` §8, rows m10/m11;
`specs/progress/2026-10-21-abstract-multiarg-phase4.md`). `Map.filter` now carries an
ASSUMED entry fact (`{Map(k[p], v[p]) | …}`), but no other `Map` function keeps
anything of a refined input:

```march
fn need_vals(_m : Map(String, {Int | _ > 0})) : Int do 0 end
fn m10(m : Map(String, {Int | _ > 0})) : Int do need_vals(Map.insert(m, "b", 5, Map.str_cmp)) end  -- skip
fn m11(m : Map(String, {Int | _ > 0})) : Int do need_vals(Map.insert(m, "b", 0, Map.str_cmp)) end  -- skip, not a violation
```

Both are `parametric-source-unproved` (pinned by the `abstract-map` test "m10 control").
For the same reason `Map.filter(pos_map, fn _k -> fn v -> v < 100, cmp)` does not meet
`_ > 0 && _ < 100`: the input's own entry is not conjoined through an assumed callee
(the too-weak detail says "`m`'s own element facts are not carried through
`Map.filter`").

Why: `ptype Map(k, v) = HamtMap(HEntry(k, v))` hides both parameters (F4:
`ctor_hidden_params` is `[0; 1]`), so `container_paths` refuses every `Map` source and
`sources_of` is `None`; and the functions' parameters are unannotated, so P1 fails.

Fix direction (design §8): an opaque-container source rule, "a ptype's own module
functions are the only producers of its values", so a `Map` function generic in
`k`/`v` with annotated parameters carries its arguments' entries (insert: the input
map's entries plus the inserted key/value, each obliged against the demand; remove /
get / merge / map_values similarly), with P1 on annotated parameters and the same
runtime property witnesses `Map.filter` has in `test/stdlib/test_map.march`.

**Closed 2026-10-26** (`m10` proves, `m11` is a skip, not a violation): see
`specs/progress/2026-10-26-map-element-flow.md`. The opaque-container source rule
landed as a checker change in `Refine_param.container_paths` (a `ptype`/`opaque type`'s
hidden parameters are sources), and `insert`, `get`, `get_or`, `remove`, `keys`,
`values`, `merge`, `map_values` and `singleton` got honest generic annotations; the
element facts are checked by parametricity, not assumed. The remainder (`Map.empty()`,
`merge_with`, the list-of-pairs functions, and `HashMap`/`Set`) is
`specs/todos/2026-10-26-map-element-flow-remainder.md`.
