# Set refinements strengthening, Phase 2: structural `elts` and `len`

Landed 2026-09-15. Design: `specs/2026-09-14-set-refinements-strengthening-design.md`
§3; plan: `specs/plans/set-refinements-strengthening-plan.md` (Phase 2, steps
2.1 to 2.6). Phases 3 and 4 stay open in
`specs/todos/2026-09-14-set-refinements-strengthening.md`.

## What landed

- **2.1 Built-in list measures in the logic.** `$len` and `$elts` are
  internal measures over list terms. `Refine_encode.resolve_sorts` types them
  and renames each to its list instance; `query_instance_preamble` declares
  each instance with its recursion axioms (`list_measure_text`). Call-site
  `len$x`/`elts$x` constants are untouched.
- **2.2 Tier 2 over built-in lists.** `post_induction_shape` and
  `induction_match_adt` accept `List` (`tier2_adt`); `len`/`elts` of a list
  term reflect to the structural measures; a non-variable recursive-call
  argument is bound to a constant at its parameter's sort; `Elem` meets a
  concrete sort in the per-query declarations. The built-in `len` of a call
  now carries the callee's proved contract at call sites (`set_of_call`).
- **2.3 Routing.** An `elts` list contract is tried by induction first; the
  elts path still runs, and reports, when induction does not prove it.
- **2.4 Ledger.** Shape 2 records its verdict once.
- **2.5 Callee and local contracts.** `post_lookup` gives the elts path and
  Tier 2 a callee's proved contract; locals are proved first and overlaid;
  Tier 2 accepts leading local `fn`s (`induction_body`) and assumes parameter
  refinements. The verification gate is a monotone fixpoint. Call sites fold
  `elts(Cons(h, acc))`. Models render co-finite sets.
- **2.6 Stdlib.** `List.reverse`, `append`, `filter`, `dedup` and their `go`
  helpers carry proved contracts; bodies unchanged. `dedup`'s helper takes
  `acc : {List(a) | member(prev, elts(_))}` as its invariant.

## Verification

- `list-structure` test group: accept and reject fixtures for each step,
  including an unproved callee that proves nothing, a two-function cycle, and
  a contract chain in reverse declaration order.
- Frontier test `the built-in len does not yet carry Tier 2 induction`
  flipped to an error; the Shape 2 ledger pin and one audit classification
  (a `{List(Int) | len(_) > 0}` constructor body is now Enforced) updated on
  purpose.
- CI skip ratchet on `stdlib/list.march`: 46 skipped (ceiling 46), proved
  19 to 30 in the user + stdlib slice; 8 of 8 new postconditions proved.

## Traps

- **Checking a stdlib file directly flattens its module beside the prelude.**
  `List.reverse` and the prelude's own `reverse` share the gate key
  `reverse`; the gate checked the unrefined one and dropped the real
  contract, visible only in the CI ratchet measurement, not in any test.
- **Tier 2 queries had no set `define-sort`s.** Harmless until a callee
  contract brought a set literal (`elts(Cons(h, Nil))`) into one; the z3
  rejection counter caught it immediately.
