# Refinement checker: generic set-valued measure instances

Shipped 2026-09-16.

## Symptom (recap)

A `@[measure]` returning `Set(a)` over `Tree(a)` is declared with an opaque
`Elem` element. Applied to a `Tree(Int)` term, `resolve_sorts` would rename
it to a `Tree(Int)` instance whose result was still `Set(Elem)`, which z3
rejects, so the query was turned into a sort-conflict skip
(`resolve_sorts_exact`'s `raise Exit` arm) rather than reaching the solver at
all.

## Fix

Two distinct defects had to be fixed, in this order — fixing only the first
still left the fixture skipped (with a MISLEADING reason), and only surfaced
the second once the first was in place.

### 1. Recording and threading the instance's concrete element sort

`lib/refinecheck/refine_encode.ml`:

- `set_ret_elem_param fd` records WHICH of a measure's own declared
  parameter-ADT type parameters its `Set(_)` result names — index `0` for
  `fn tree_elts(t : Tree(a)) : Set(a)`'s `a` — by matching the return type's
  element type-variable against the parameter type's own argument list.
  `set_measure_elem_param : (string, int) Hashtbl.t` holds it per measure,
  populated in `Refine_check.check_module` alongside the existing
  `set_measure_elem` (declared, generic element sort) table.
- `set_measure_elem_at name inst_args` is the read side: the instance's own
  argument at the recorded parameter index, falling back to the generic
  `set_measure_elem` entry when no parameter was recorded (a measure
  declared with a concrete element, `Set(Int)`, needs no substitution at
  all) or the index is out of range.
- `instance_measure_text`'s `declare-fun` result sort, `arm_axiom`'s
  `pin_set_sorts` call and its final body-sort check (both now computed
  against `inst_elem`, the instance's element from `args`, rather than the
  measure's bare declared element — `axiom_body_sort` gained an `?elem_of`
  callback so a SELF-recursive call inside the arm resolves to the SAME
  instance element rather than the generic one), and `resolve_sorts_exact`'s
  type-inference pass (a set measure's result used to be pinned
  unconditionally to the fixed name `INamed ("Elem", [])`; when
  `set_measure_elem_param` names a parameter index, the result now reuses
  the SAME inference variable the argument's own fresh instance already
  allocated for that parameter, already unified with the argument's concrete
  instance one line above) all read through this table now.
- `resolve_sorts_exact`'s rewrite pass: the `raise Exit` guard is narrowed to
  fire only when `set_measure_elem_param` has NO recorded parameter for the
  measure — the concrete case falls through to the same "declare and
  axiomatise at a fresh instance" branch a `Set(Int)`-declared measure
  already took.

### 2. The instance's `MSet$<elem>` sort was never `define-sort`ed

Fixing (1) alone still skipped the fixture, now diagnosed as
`Undecided`'s `opaque-application` for the symbol `tree_elts$M_Tree$Int` —
misleading, since the axiom text (checked by hand) was correct. The real
defect: `instance_measure_text` emits `(declare-fun tree_elts$… (M_Tree$Int)
MSet$Int)` and axioms over `MSet$Int`, but `MSet$Int` is a sort ALIAS
(`(define-sort MSet$Int () (Array Int Bool))`) that nothing was ever
emitting for a generic measure's CONCRETE instance — `set_preamble`'s own
scan for needed `MSet$<elem>` definitions is structural, over the query's
typed `Smt.vc` (`Smt.SSet` nodes), and a measure instance's element sort
never appears there: it exists only inside `instance_measure_text`'s
hand-built SMT-LIB TEXT. z3 therefore saw `MSet$Int` used but never defined.

Fixed in `query_instance_preamble` (`lib/refinecheck/refine_encode.ml`):
`measure_instance_set_elems` computes, from the resolved `measure_instance`
list, the element sort of every set-valued measure instance the query
mentions; the new `set_defs` text — deduplicated against what the caller's
`declared` preamble already defines — is inserted BEFORE the measure
instance text (`mtext`) that uses it, since SMT-LIB has no forward
declarations (an initial attempt appended it via `set_preamble` afterwards
instead, which produced valid-looking but WRONGLY ORDERED text — the
`declare-fun`/axioms referencing `MSet$Int` before its `define-sort`, so z3
still rejected it; caught only by re-inspecting the actual dumped preamble
text, not by re-deriving from the code).

## Fixtures

`test/test_refinecheck.ml`: `generic_set_measure_instance_suite` — reuses
`avl_suite`'s own `Tree(a)`/`tree_elts` shape (a generic set-valued measure)
but applies it at the CONCRETE instance `Tree(Int)` via a parameter
refinement checked at a call site (`need`, called with a literal
`Node(Leaf, 3, Leaf)`) — the same idiom `typed_instances_suite` uses for its
own (Int-valued) generic-measure-at-an-instance fixtures, exercising the
analogous SET-valued case with the same style of witness. Before the fix
both are `Sort_conflict` (then, after defect 1 alone, `opaque-application`)
skips; after the full fix the ACCEPT case (`3` is in the tree) proves and
the REJECT case (`99` is not) is refuted.

## Verification

- `--refine-audit stdlib/list.march`: 0 unenforced, 114 enforced (user +
  stdlib) — unchanged.
- `--refine-report stdlib/list.march`: 38 proved / 31 trusted / 46 skipped
  (user + stdlib) — unchanged; this fix does not touch anything
  `list.march` itself exercises, so it is a pure addition of provability
  elsewhere, not a change to this ceiling.
- Cold-check wall time on a trivial refinement-checked file (a single
  `{Int | _ > 0}` precondition, no measures involved): ~0.65s warm (CAS
  cleared each run), consistent across repeated runs — no sign of the
  global-quantified-axiom blowup this file's own comments warn about; this
  fix adds no global axiom, only per-query text.
