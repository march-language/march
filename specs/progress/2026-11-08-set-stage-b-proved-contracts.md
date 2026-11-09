Six of `Set`'s contracts proved against its HAMT (stage B of
`specs/todos/2026-11-06-prove-map-set-contracts.md`): `empty`, `singleton`,
`insert`, `union`, `to_list`, `from_list`. They trust one law, `cmp_eq`'s
`{Bool | _ == (x == y)}`: the comparator is a strict total order that agrees
with `==`, which every comparator-taking function already documented.

## The abstraction: `@[abstraction(elts)]`

`elts(s)` of an opaque `Set` was a constant per name, unconnected to the value,
so nothing inside `stdlib/set.march` could prove a contract about it. An
axiomatised `@[measure]` marked `@[abstraction(elts)]` (or `keys`) over one of
its module's datatypes now stands for the built-in measure on that type, inside
that module only ([Refine_post.abstraction_measure], registered by
[Refine_check] per module check). The induction engine's measure resolvers map
`elts(t)` of a term of that datatype to the abstraction measure. A caller in
another module keeps the opaque view and proves through the contracts, so no
caller's proof changes. Errors: no `@[measure]`, a name other than
`elts`/`keys`, a parameter that is not one of the module's datatypes, a measure
that is not axiomatised.

## Checker rules the trie needed (each found by prototyping the insert)

- **List match arms state `elts`** (`Refine_scope.list_pattern_fact`, pushed by
  `tails_bound`): a `Nil` arm of `match xs` gives `elts(xs) == empty`, a
  `Cons(h, t)` arm `elts(xs) == union(singleton(h), elts(t))`. The walk used to
  push only the opaque marker, so `_ == member(x, elts(xs))` over a list match
  was undecided. The fact is a predicate, tagged so the path translators read it
  with the set vocabulary on.
- **`if f(args) do` reads `f`'s `Bool` contract** (`check_post_stage`'s path
  loop, via `call_at`, the generalised `scalar_call`). `let b = f(args)` then
  `if b` already worked; the direct form learned nothing.
- **A constructor result in an `if` branch reflects for `elts`**
  (`ctor_elts`): `Cons(h, t)` is `{h} ∪ elts(t)` whatever `t` is. Only
  all-literal lists folded before.
- **A diverging tail proves vacuously** (`diverging_tail`, both engines):
  `panic`, `todo`, `unreachable`, `exit` never return, and a return contract is
  a claim about the returned value.
- **A mutual-cycle call carries the cycle's hypothesis** in the induction
  engine: the datatype-call branch reads `call_post` (the IH at an eligible
  span) instead of the proved-contract lookup, and a call in a list ELEMENT
  position (`Elem` sort) is reflected at the datatype its contract measures, so
  `Cons(node_insert(c, ..), rest)` carries `node_insert`'s hypothesis. The
  `tier2-induction` test that pinned "mutual recursion gets no induction
  hypothesis" now asserts the definite violation the proved contract exposes.

## `stdlib/set.march`

The insert path is first-order and passes `cmp`, not an `eq` closure:
`insert_at` replaces `list_insert_at`; `branch_nodes` (`@[decreases(7 - lvl)]`)
replaces `make_branch` and `expand`, placing a collision that meets a new hash
beside the new leaf instead of re-inserting each element; `insert_child` inserts
into the indexed child in one pass (it used to `list_nth_safe` then
`list_replace_at`); `coll_mem`/`coll_add` replace `coll_insert_elem`.
`insert` counts with `node_mem`/`child_mem`, a first-order membership walk:
`node_contains` recurses through a closure and through `list_nth_safe`'s
result, which the checker cannot certify, and a function that reaches an
uncertified SCC gets no induction hypothesis, so `union`'s walk (which calls
`insert`) proved nothing. `union`, `from_list` and `to_list` are plain mutual
walks (`insert_node`/`insert_children`, `insert_list`,
`node_rev_onto`/`children_rev_onto`, `list_rev_onto`) visiting elements in
`node_fold`'s order, so `to_list`'s order is unchanged. The unreachable
`lvl > 6` arm (two distinct 30-bit hashes differ below level 6) now panics
instead of building a collision of two hashes.

`contains`, `remove`, `size`, `is_empty`, `intersection`, `difference`,
`is_subset` and `eq` stay `@[assume]`: they need the hash-path invariant
(stage C).

## Tests

`nested-measure` group (`test/test_refine_nested_measure.ml`): each rule with a
REJECT control; a copy of the trie insert with three wrong variants that stay
unproved; `@[abstraction]` positive, REJECT and the three misuse errors; a
`Set.insert` caller; each of the six Set contracts proved in the stdlib. Each
of the five checker rules was switched off in turn and its test (and the trie
test) went red.

Workarounds noted in the code, filed as
`specs/todos/2026-11-08-refine-let-opaque-int-in-ctor-argument.md`: a
constructor passed as a call argument whose field mentions a `let` of an
unreflected `Int` call fails to reflect (hence `wrap_pair` taking the bitmap as
a parameter).
