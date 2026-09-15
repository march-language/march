# Set refinements strengthening, Phase 4: `SortedSet` proved

Landed 2026-09-15. Design: `specs/2026-09-14-set-refinements-strengthening-design.md`
§5; plan: `specs/plans/set-refinements-strengthening-plan.md` (Phase 4).

## What landed

- **4.1 `let` in induction bodies.** `Refine_post.inline_lets` substitutes a
  simple `let` into the rest of its block when no later binder could capture
  (`subst_let`, `expr_vars`); an Int payload that does not reflect is an
  unconstrained constant.
- **4.2 Callee contracts at any datatype.** Tier 2's callee-contract
  reflection applies at every declared datatype sort, and a measure over a call
  inside a contract reflects that call (`resolve_measure_call` in
  `pred_term_as`).
- **4.3 Nested patterns and catch-all arms.** `flatten` names nested
  constructor sub-patterns and emits one equation each; `_` and variable arms
  are checked with no pattern equation.
- **4.4 Scalar contract calls in guards.** `abstract_calls` binds a call with a
  proved scalar contract to a constant carrying it, one per callee and variable
  arguments.
- **4.5 `stdlib/sorted_set.march`.** `sorted_set_elts` measure (named so a user `tree_elts` cannot collide: measure names are not module-qualified), assumed
  `compare_by` law, and proved contracts on `make_node`, `rotate_right`,
  `rotate_left`, `balance`, `tree_insert`, `tree_delete_min`, `tree_to_list`.
  `test/stdlib/test_sorted_set.march` adds basic tests and a differential
  property test against `Set` (red-checked with a no-op `remove`).
- Sort resolution fixes found on the way: a type-variable parameter is an
  opaque `Elem`; a set measure's declared `Set(Elem)` result is fixed; a
  generic set measure at a concrete instance is a skip, not a z3 rejection.

- **Quantified measure axioms attach per query.** With `SortedSet`'s
  recursion axioms in the module-wide preamble, every stdlib `Array` bounds
  check turned into a 1.5 s `unknown` and a trivial program's cold check went
  from 0.4 s to over 20 s. Datatypes, set sorts, `declare-fun`s and definitions
  stay global; each symbol's quantified axioms live in
  `measure_axioms_by_symbol` and `query_instance_preamble` attaches those a
  query mentions, closed under what they mention. The trivial check is back to
  the original time.
- **Duplicate measure names are not axiomatised.** Measure symbols are not
  module-qualified; a user measure named like a stdlib one produced two
  `declare-fun`s and 116 rejected queries on one fixture, 0 with the guard.
  The stdlib measure is `sorted_set_elts`, and
  `specs/todos/2026-09-15-refine-sort-and-measure-names-unqualified.md` tracks
  qualification.

- **`SortedSet`'s tree is `AvlTree`/`AvlLeaf`/`AvlNode`.** It shared
  `Tree`/`Leaf`/`Node` with `OrderedMap` (and with any user tree), and the
  checker keys datatypes and constructors by bare name: the audit sweep showed
  its contracts unenforced wherever another `Tree` registered last, and an axiom
  qualified `Leaf` with a user type. `arm_axiom` now prefers the measure's own
  datatype when qualifying a constructor.

## Not proved

- `tree_delete` (needs `tree_min`'s `Option` payload) and `tree_member` (a
  `Bool` return) stay unclaimed; the public API over the anonymous record type
  is unannotated.

## Verification

- `avl-induction` test group on a user copy of the tree: all five proofs, the
  comparator law's necessity, and a refuted false insert contract.
- `obligation-reasons` case 23 now uses an opaque datatype field, since an
  opaque Int payload no longer makes a tail unreflectable.
- Compiled A/B benchmark of the `compare_by` wrapper: no measurable cost.
