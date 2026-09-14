# Set-inclusion refinements (Liquid-Haskell-parallel set theory)

Landed 2026-09-13. Design: `specs/2026-09-13-set-refinements-design.md`;
plan: `specs/plans/set-refinements-plan.md`. User-facing reference: "Set
Refinements" in `specs/lang/refinement-types.md` and `docs/refinement-types.md`.
Filed and closed the same day, so no `specs/todos/` entry ever existed for it.

## What landed

- **Phase A1, logic core.** `Smt.SSet` sort and seven set term constructors
  (`lib/refine/smt.ml`), rendered as Z3 `(Array elem Bool)` with `map`
  combinators; subset is defined by union, so no user VC has a quantifier.
  The predicate vocabulary `member union inter diff subset singleton empty`
  and the built-in measure `elts` (`lib/refinecheck/refine_encode.ml`,
  `refine_scope.ml`). Element sorts are UNIFIED per VC by
  `Refine_encode.resolve_set_sorts` after the declarations are final (a
  literal pins its set to `Int`/`$Str`, unions and equalities make operands
  agree, an unpinned set is the opaque `Elem`, a contradiction is a
  `Sort_conflict` skip), which is what removed every piece of element-type
  plumbing the plan sketched. `elts` folds a LITERAL list to a concrete set
  and is otherwise a per-name constant `elts$x`, the non-axiom `len`
  treatment, so it is deliberately NOT axiomatised over `Cons`/`Nil`
  (the built-in list's head field is `Elem`, so an `Int` list is not a
  datatype term anyway).
- **Phase A2, set-valued user measures.** A `@[measure]` declared `: Set(T)`
  is axiomatised at `MSet$Int`/`MSet$Elem`; the typechecker binds the seven
  logic names for that body only (`lib/typecheck/typecheck.ml`, `check_fn`);
  the refinement checker rejects any expression-position call of such a
  measure. An `Int` literal constructor payload is now reflected as itself
  at a call site (`reflect_field`), which is what makes
  `free_vars(Lam(1, Var(1))) == empty` provable.
- **Phase B, `@[assume]` + stdlib `Set` contracts.** `@[assume]` propagates a
  return refinement without a proof and skips the body check
  (`refine_post.ml`, `check_fn_post_verdict`; ledger verdict `Trusted`, kind
  postcondition). Thirteen `stdlib/set.march` functions carry `elts`
  contracts; `test/stdlib/test_set.march` gains one `Check.all` witness per
  contract against a list oracle.
- **Phase C, `keys` over `Map`.** Eleven `stdlib/map.march` functions carry
  `keys` contracts (including `get : {Option(v) | is_Some(_) == member(key,
  keys(m))}`); witnesses in `test/stdlib/test_map.march`.
- **Phase D, set counterexamples.** A z3 `store` chain over an all-false
  constant array renders as `{4}` / `{}`; a `$set<N>`/`$dt<N>` result symbol
  renders as "`f()` can return …" (`refine_scope.ml`, `pretty_smt_value`).

## Departures from the plan, and fixes found on the way

- **Unannotated parameters were nameless in every signature.** `param_name_of`
  recorded an `FPPat (PatVar s)` parameter as `_`, so a relational
  postcondition over `fn insert(s, elem, cmp)` classified as Unusable and
  never propagated. Fixed generally; every unannotated function's relational
  contract now travels.
- **Guards that are calls, and Bool locals bound to calls.** `check_call`'s
  path-condition translation dropped `if Set.contains(s, x, cmp)` (no arm for
  a call) and reflected `if present` as an unconstrained Int. Both now go
  through `reflect_scalar`'s Bool call arm / the scope entry's own fact.
- **Substituted contracts with nested calls and foreign variables.**
  `elts(Set.empty())` inside an instantiated contract needed a
  `resolve_measure_call` hook in `smt_of_r`; `singleton(x)` needed the caller's
  `foreign_var`; and a caller name inside a substituted contract must load its
  own scope promise (forward ref `load_scope_measure_facts_ref`).
- **List returns over an `Int` measure keep Tier 2 induction.** The first
  version routed every `{List(_) | …}` return to the elts path and broke the
  `tier2-induction` "a measure over List propagates" case; the elts path is
  taken only when the predicate mentions a built-in set measure.
- **String payloads stay opaque.** Making `String` constructor fields reflect
  at `$Str` would change every record/ADT preamble; the design's `Set(String)`
  measure example therefore reasons symbolically only, and the tests use
  `Int`-named variables.

## Review fixes (2026-09-14)

A high-effort review of the uncommitted change confirmed eight defects; two
were fixed before landing, with RED-then-GREEN regression tests in the
`set-refinements` suite:

- **Record fast path reported inputs a contract forbids.**
  `Refine_post.check_post` treats a satisfiable model as a definite violation
  whenever a record-refined parameter is in scope. `scope_facts` now also
  returns whether EVERY scope entry's predicate loaded, and the fast path
  requires it. The new `list_ret` path exposed it (`xs : {List(Int) | len(_) >
  0 && member(1, elts(_))}` returned under `{List(Int) | member(1, elts(_))}`
  reported `elts(xs) = {}`), but the same hole predates sets:
  `{Int | _ < len(xs)}` beside a record reported `0` as a violation.
- **`empty` was reserved outright.** A parameter named `empty` reflected as
  the empty set in guards and contracts, masking a definite violation.
  `Refine_encode.mark_set_empty` now rewrites `empty` to an internal literal
  only in a set position; `classify_pred`, `subst_params` and `smt_of_r` mark
  before they look.

The other six were fixed in a follow-up (below). Still open: set-free VCs
pay for `resolve_set_sorts`/`set_preamble`.

## Follow-up review fixes (2026-09-14)

Each with a regression test in `set-refinements` (or `audit-classify`) shown
RED against the unfixed branch first, every accept beside a reject:

- **The set vocabulary hijacked same-named program functions.** A guard
  `if keys(r) == []` over a module's own `fn keys` reflected `keys(r)` as a
  set, the element sorts clashed, and the whole call was skipped as a sort
  conflict, hiding `need(0)`. Path conditions are program text, so
  `Refine_scope.smt_of_r ~vocab:false` (used by the guard reflectors in
  `refine_call.ml` and `refine_post.ml`) reads the vocabulary names as the
  opaque calls they are. Independently, `Refine_encode.resolve_set_sorts` now
  drops an ASSUMPTION that brings in a set-sort clash instead of skipping the
  VC (only a clash inside the goal is still a `Sort_conflict`). Inside a
  predicate the vocabulary stays reserved: a non-set-shaped application
  (`member(xs, 3)`) draws the vocabulary warning again
  (`set_app_well_formed`), and `measure_shape_error` rejects a `@[measure]`
  named `elts`/`keys`/`member`/…/`empty`.
- **`Set(Bool)` and mismatched-payload set measures poisoned the preamble.**
  `set_ret_elem` maps `Set(Bool)` to `Bool`, and `arm_axiom` now checks the
  translated arm's sorts (`axiom_body_sort`) and refuses the arm — hence the
  measure's axiomatisation — when they disagree, so `fv : Expr(Int) ->
  Set(Int)` over `Var(a)` degrades to symbolic instead of putting an
  ill-sorted `forall` in every query of the module.
- **A record selector used as a set element was pinned to `Int`.**
  `resolve_set_sorts` looks the selector's field sort up
  (`selector_field_sort`), so `member(v.name, singleton(v.name))` proves.
- **Set-valued measure calls escaped rejection outside `fn` bodies.**
  `reject_set_measure_calls` walks `impl` methods, interface defaults, actor
  init/handlers, top-level `let`s, `app` bodies and `describe`/`test`/`setup`
  blocks, the same containers `warn_predicate_decls` walks.
- **`--refine-audit` over-reported Enforced returns.** It now asks
  `Refine_post.return_refinement_checked`, which follows
  `check_fn_post_verdict`'s routing: a `{List(_) | …}` predicate without
  `elts`/`keys` goes to Tier 2, and Tier 2 checks only a constructor-literal
  body or a match on a parameter with a declared ADT type
  (`post_induction_checks`, sharing `induction_match_adt` with Shape 2).
- **Chained `let`-bound set promises were not transitive.** The non-self
  branch of `load_scope_measure_facts`'s `rm` loads the name's own promise
  before `measure_of_var`; the `scope_facts_loaded` memo keeps it
  terminating. The forward `ref` cell stays: `set_of_call` and the loader are
  separated by definitions the loader uses, so a `let rec … and` would move a
  large block for no behavioural gain.

## Verification

`test/test_refinecheck.ml`, suite `set-refinements` (26 cases after the review fixes, 35 after the follow-up), every accept
beside a reject; the RED-first control (membership rendered as `true`) went
red on seven of them before the encoding was trusted. `scripts/run-tests.sh
-q`, the full z3 suite, and the stdlib `test_set`/`test_map` files all green
at landing.
