# Refinement checker: datatype sort names are module-qualified; measure names deliberately are not

Shipped 2026-09-16.

## Symptom (recap)

`adt_sort_name` mapped a March type to `M_<bare name>` and a `@[measure]` to
its bare function name, with no module qualification at all. A program sees
the whole stdlib merged into one decl list (the driver prepends it), so two
`type Tree` in two different `mod … do end` blocks — or a user's own
`type Tree` and a stdlib one — collided on the bare key `M_Tree`: whichever
was registered LAST silently clobbered the other's constructor list in
`adt_ctors`/`adt_arity`. Two `@[measure]`s sharing one name each emitted a
`declare-fun`, and z3 rejected every query that attached the measure
preamble; the interim mitigation excluded every duplicate-named measure from
axiomatisation outright (both declarants lost their proofs), and
`stdlib/sorted_set.march`'s own tree/measure had been renamed to
`AvlTree`/`AvlLeaf`/`AvlNode`/`sorted_set_elts` to dodge
`stdlib/ordered_map.march`'s `Tree`.

## Fix (ADT sort names)

`lib/refinecheck/refine_encode.ml`:

- `adt_sort_name_at path name` computes a QUALIFIED sort key
  (`M_<path>$<name>`, or plain `M_<name>` at the top level, `path = ""`).
  `register_adt_names` (now threading its enclosing module's dotted `path`,
  mirroring `register_const_fns`'s own walk) files every declaration under
  its own qualified key and records `(path, key)` in `adt_decl_paths`, keyed
  by the plain bare name.
- `finalize_adt_canonical`, run once pass 1 (`register_adt_names`) has seen
  every declaration and before pass 2 (`register_field_sorts`) starts,
  decides what a bare name denotes: exactly one declarant anywhere -> its
  data is filed under the plain bare key too (byte-for-byte what a
  non-colliding type got before this change — the overwhelming majority of
  the codebase); two or more -> each keeps its own qualified key, no bare
  key is filed at all (unless one declarant sits at the top level, `path =
  ""` — its qualified key already IS the bare key, so it is left in place
  rather than deleted, a real bug caught only by the ACCEPT witness actually
  failing during development), and `adt_sort_name` (now a resolver, not a
  literal string-concat) resolves the bare spelling to a single preferred
  declarant — the entry/top-level one if there is one, matching the
  "current module wins an ambiguous name" convention the compiler already
  uses for ambiguous constructors elsewhere, else the first one registered.

This is deliberately not full lexical scope resolution: a reference written
INSIDE the losing module still resolves to the preferred (not its own)
declarant when a name is genuinely ambiguous. Misresolving here can only
turn a proof into a `Sort_conflict` skip elsewhere in `refine_encode.ml`,
never a false "proved" — every consumer of `adt_ctors` already treats a sort
mismatch as a reason to give up, not to guess.

## Measure names: qualification attempted and reverted

The same treatment was attempted for `@[measure]` names (`meas_qualified_key`,
`meas_decl_paths`, `finalize_meas_canonical`, a `measure_smt_name` resolver
threaded through `is_measure`/`measure_name`/`is_axiom_measure`/
`is_nonneg_measure`/`is_set_measure`, and `Refine_check.collect_measure_fns`
walking with its module path). It was **reverted**: resolving an ambiguous
bare measure NAME to one preferred declarant means every OTHER call site
sharing that bare spelling — including the LOSING declarant's own internal
recursive calls — silently picks up the winner's axioms. That can attach a
heavy quantified preamble to a query that has nothing to do with it, and one
fixture reproduced z3 grinding for minutes where it used to answer instantly
— exactly the class of regression the per-query axiom design in this file
(`measure_axioms_by_symbol`, keyed per query rather than a global preamble)
exists to prevent. `Refine_check.collect_measure_fns` keeps the pre-existing
mitigation: two `@[measure]`s sharing one bare name are BOTH excluded from
axiomatisation (a proof loss for both, but sound and cheap), documented at
its own definition.

## SortedSet rename: tried reverting, kept as-is

`stdlib/sorted_set.march`'s tree was TEMPORARILY reverted from `AvlTree`/
`AvlLeaf`/`AvlNode`/`sorted_set_elts` back to `Tree`/`Leaf`/`Node`/`tree_elts`
to test whether the ADT-sort qualification fix made the historical rename
unnecessary. `--refine-audit`/`--refine-report stdlib/list.march` alone held
at the same ceilings with the revert in place, but the full
`test_refinecheck.exe`'s `audit-baseline` suite — which sweeps `test/native`,
`stdlib`, and `test/refine_audit/holes`, i.e. every corpus fixture with the
WHOLE stdlib merged in, `OrderedMap` and `SortedSet` both always present —
went from 0 to 6 new UNENFORCED sites, all of them SortedSet's own return
refinements (`make_node`, both rotations, `balance`, `tree_insert`,
`tree_delete_min`). Reason: `OrderedMap`'s `Tree` and `SortedSet`'s reverted
`Tree` are BOTH nested (`mod OrderedMap do … end` / `mod SortedSet do …
end`), so NEITHER sits at the entry/top-level path this fix's tie-break
prefers; `finalize_adt_canonical` falls back to "the first one registered"
across the WHOLE merged corpus, and `OrderedMap` — alphabetically and
directory-walk-order first — wins. SortedSet's OWN `tree_elts` then resolves
its own parameter type `Tree` against `OrderedMap`'s (differently-shaped)
constructor list, and the induction-shape audit no longer recognises it —
degrading to an unenforced skip, not a false proof (the fix's stated
soundness property held), but a real, measured proof-coverage regression
against the checked-in `test/refine_audit/corpus.baseline`.

So the revert was undone; `stdlib/sorted_set.march` KEEPS
`AvlTree`/`AvlLeaf`/`AvlNode`/`sorted_set_elts`, and `corpus.baseline` is
therefore UNCHANGED by this fix (AvlTree never collided with anything, so
nothing about its own classification moves). This is exactly the
"reference written INSIDE the losing module still resolves to the preferred
(not its own) declarant" limitation called out below, made concrete: this
fix is a real improvement for a collision between an ENTRY-level program and
a stdlib module (the `module_qualified_measure_and_sort_suite` fixture,
which does not touch `SortedSet`), but does not yet extend to two NESTED
stdlib modules colliding with each other. Full lexical scope resolution
(matching a reference's own enclosing module first) would close that gap;
out of scope here.

The two CONSTRUCTOR NAMES `Leaf`/`Node` are also still process-wide —
`ctor_field_sorts`/`ctor_param_fields`/`ctor_field_names` are keyed by bare
constructor name only, with no module qualification, which this fix does
not touch — a second, narrower reason `OrderedMap` and a `Tree`/`Leaf`/`Node`
-shaped `SortedSet` could not safely coexist even with perfect sort-name
scoping.

## Fixtures

`test/test_refinecheck.ml`: `module_qualified_measure_and_sort_suite` — an
ACCEPT/REJECT pair with a user-level top-level `type Tree` colliding (by
SORT name only) with the real `stdlib/ordered_map.march`'s own
differently-shaped `Tree(k, v)`, prepended exactly as the production driver
prepends the whole stdlib into every module it checks, and merged in AFTER
the fixture's own decls so a pre-fix build's naive "last registered wins"
gives the collision to `OrderedMap` (the actual failure mode) rather than
accidentally leaving the fixture's own type intact by merge-order luck.
Before the fix this is a hard ERROR (the user's own `tree_elts` measure,
checked against `OrderedMap`'s clobbered constructor list, is no longer
total) — confirmed by temporarily reverting `adt_sort_name`/
`adt_sort_name_at` to a bare `"M_" ^ name` concatenation and rerunning; after
the fix, the ACCEPT witness proves and the REJECT witness is refuted.
