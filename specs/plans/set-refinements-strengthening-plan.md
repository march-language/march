# Set refinements strengthening — implementation plan

**Design:** `specs/2026-09-14-set-refinements-strengthening-design.md`
**Open item:** `specs/todos/2026-09-14-set-refinements-strengthening.md`
**Date:** 2026-09-14

One PR per phase. Every step keeps the full refinement suite green and is
proven by a test that fails on the code before it.

## 0. Facts that shape the plan

1. **z3 accepts parametric datatypes, and a bare nullary constructor when the
   context fixes its instance** (`(= xs Nil)` with `xs : (M_List Int)`,
   `(Cons 1 Nil)`), on both 4.8.12 (CI) and 4.16. That turned out not to be
   enough in argument position; see fact 5.
2. **The suite sends z3 no malformed query today.** With the new rejection
   counter (step 1.0) the full `test_refinecheck.exe` run logged zero
   rejections, and a record refinement spelled with the parameter's name
   (`r : {Rec | r.n > 0}`) was confirmed to be caught. A wrong leaf sort
   introduced by this phase will therefore show up as a count, not a skip.
3. **The typechecker's span table is available in production and absent in
   most tests.** It records parameter binders (annotated or not), `let`
   binders, pattern variables and expressions. `has_refine_error_typed` is the
   only harness helper that passes it.
4. **About fifty sites construct or match a datatype sort**, across
   `refine_encode.ml`, `refine_call.ml`, `refine_post.ml`, `refine_scope.ml`,
   `refine_resolve.ml` and `lib/refine/smt.ml`.
5. **z3 has three parametric-datatype quirks, identical on 4.8.12 and 4.16**,
   found while landing 1.2: a tester applied directly to a constructor term is
   rejected; 4.8 cannot infer a constructor's instance in argument position
   (`(Some_0 (Some x))`); and one `declare-datatypes` command may not mix a
   monomorphic sort that uses a parametric instance with that parametric sort.
   Hence the typed `Smt.Ctor` term (rendered `((as C S) …)`), render-time
   folding of a tester on a literal constructor, and per-component
   declarations in dependency order.
6. **z3 4.8.12 segfaults (exit 139) on `par` datatypes in practice.** A
   satisfiable query with a quantified recursion axiom over a parametric
   datatype with two recursive fields (`Tree(a)`) crashes it at any instance,
   `Elem` included; `List`-shaped datatypes and 4.16 are unaffected. Found
   when 1.3+1.4 went RED only under the CI solver. Every instance is therefore
   declared monomorphically (`M_Tree`, `M_Tree$Int`, same constructor names),
   module preambles declare closed instance sets, and a query declares the
   instances it adds (`query_instance_preamble`).

## 1. Phase 1 — typed element sorts

### 1.0 Make a malformed query fail the suite

- `Solver.malformed_count` and `Solver.malformed_messages` record every query
  z3 rejects; `MARCH_REFINE_Z3_ERRORS=<file>` appends the query text.
- A last test group in `test_refinecheck.ml` asserts the count is zero and
  prints the messages when it is not.
- RED: the malformed record fixture above, run inside the group, must fail it.

**Landed** (commit `12626bac`): 1.0, 1.1 and 1.2, verdict-neutral (oracle
identical over 328 fixtures; full suite green; zero z3 rejections).
**Landed** on the Phase 1 branch: 1.3+1.4 (instance-typed terms, per-instance
measures, monomorphic instance declarations), 1.5 (single-element-type
error) and 1.6 as described there. Oracle identical over 331 fixtures; the
full `test_refinecheck.exe` passes all cases on z3 4.16 and on 4.8.12, with
zero rejected queries.

### 1.1 Sorts carry type arguments

- `Smt.sort`: `SData of string` becomes `SData of string * sort list`, and
  `SParam of int` names a datatype's own type parameter inside a field sort.
  `string_of_sort (SData (n, []))` is `n`; with arguments it is `(n a1 … an)`.
- Every construction and match site is updated with the compiler's help. No
  behaviour changes yet: every existing sort is built with `[]`, and the suite
  and the oracle must be unchanged.

### 1.2 Parametric datatype declarations

- `adt_arity : (string, int) Hashtbl.t` from each `type T(a, …)` declaration
  and the built-ins (`List` 1, `Option` 1, `Result` 2).
- `register_field_sorts` and `register_builtin_adts` record a type-parameter
  field as `SParam i` instead of `Elem`, using the existing `ctor_param_fields`
  roles.
- `datatype_decls` emits `(T n)` arities and `(par (T0 …) …)` bodies.
  (Superseded in 1.3+1.4 by monomorphic per-instance declarations; see fact 6.)
- `instantiate : sort list -> sort -> sort` substitutes `SParam`; every field
  consumer (`reflect_dt`, `reflect_field`, `term_fits_sort`, `arm_axiom`, Tier 2
  binder sorts, `ctor_field_sorts` readers) instantiates with the instance's
  arguments.
- Until 1.3 lands, every instance is built with `Elem` arguments, so queries
  are equivalent to today's; the oracle must be unchanged.

### 1.3 + 1.4 Instance-typed datatype terms and per-instance measures

These must land together: a term at `(M_Tree Int)` applied to a measure
declared over `(M_Tree Elem)` is ill-sorted.

- **Instances come from declared types first.** A refinement is always written
  on an annotated type, so `sg.param_tys`, `fn_ret_ty` and constructor field
  types give the instance at almost every datatype term: `reflect_dt` takes the
  instance arguments, a field recursion passes the instantiated field sort's
  arguments, and a declaration uses `SData (adt, args)`. The typechecker's span
  table is consulted only for an unannotated caller value.
- **Instance arguments today:** `Int` and `Bool` concrete, a registered
  datatype recursively, everything else (type variables, `String`, `Float`)
  `Elem`. `String` payloads stay opaque until a later step moves string fields
  to `$Str` consistently in records and datatypes.
- **Measures are instantiated after the VC is built.** A pass over the finished
  query infers each term's sort (a constant from its declaration, a `Ctor`
  from its instance, a selector from its receiver's instance) and renames a
  measure application at a non-`Elem` instance to `m$<instance tag>`, collecting
  the instances used. Their declarations and axioms are generated from the
  same arm templates with instantiated field sorts, validity-checked per
  instance (an arm ill-sorted at `Elem` may be well-sorted at `Int`), and
  attached to that query's preamble. The twenty measure-application sites stay
  unchanged.
- **New capabilities to pin with accept and reject fixtures:** a measure
  reading an `Int` payload of a parametric type (`sum : Tree(Int) -> Int`), and
  a set-valued measure over `Expr(Int)`, which the six review fixes had to
  refuse.

### 1.3 (detail) Leaf sorts from March types

- `Refine_types.sort_of_ty` (design §2.1) over `Ast.ty` and over the
  typechecker's `ty`.
- Call sites, one commit each with its own fixtures:
  1. refined and unrefined parameters (declared type, else the span table);
  2. `let` binders and pattern variables;
  3. call results in actual position;
  4. constructor payloads (field sort instantiated at the scrutinee's
     arguments);
  5. refinement binders.
- Each commit: the oracle diff is reviewed line by line; every change must be
  a skip becoming a proof or a report, explained by a sort that was wrong.

### 1.4 Measures per instance

- `measure_preamble` becomes a cache keyed by the set of `(measure, instance)`
  pairs a query uses; axioms are generated from one template per arm.
- Built-in and user measures are declared as `m$T$Int` style names; the
  `$` keeps them out of the March identifier space.

### 1.5 The single-type rule

- A set predicate whose operands have known, different element types is an
  error at the predicate, with accept and reject fixtures.
- **Landed** as a static pass over function signatures
  (`check_set_element_types`): element types are read from declared types
  only (`elts` of `List(T)`/`Set(T)`, `keys` of `Map(K, _)`, `singleton` and
  `member` operands, measures declared `: Set(T)`). A type variable, an
  unannotated value or a record field is never an error. Oracle identical.

### 1.6 Retire the guesses

- Delete the `Int` default for non-scalar parameter sorts, `selector_field_sort`
  and the placeholder element sort where the type is known; narrow
  `resolve_set_sorts` to literals and the final gate.
- Close `specs/todos/2026-09-14-set-free-vcs-pay-set-sort-resolution.md` if the
  narrowed pass is skipped for set-free queries.
- **Landed in part.** `resolve_set_sorts` is gone (replaced by
  `resolve_sorts` in 1.3) and so is the dead `selector_field_sort`. A
  set-free fast path was measured over the stdlib sweep, gave identical
  reports and no wall-time change, and was not applied; the todo is closed
  with the numbers. The `Int` default for caller values of unknown sort needs
  the span table at every producer and has no failing fixture yet, so it
  moved to `specs/todos/2026-09-14-refine-caller-values-default-to-int.md`.

### Phase 1 exit

- Full `test_refinecheck.exe` with the rejection count at zero,
  `scripts/run-tests.sh -q`, `@types-check --force`, `scripts/check-docs.sh`.
- `scripts/refine-oracle.sh check` against the baseline recorded on the
  six-fix code, every diff line explained in the PR.
- `--refine-report` wall time over `stdlib/*.march`, before and after.

## 2. Phase 2 — structural `elts` and `len`, induction that reaches the stdlib

Design §3. Call-site checking of `len` and `elts` (the per-variable
`len$x`/`elts$x` constants and literal folding) is not touched: it is correct,
cheap, and every existing contract depends on it. Structure is added only
where a proof walks list cells, the Tier 2 induction check.

### 2.1 Built-in list measures in the logic

- Two internal measures, `$len` and `$elts` (the `$` keeps them out of the
  March namespace and away from `len$x` constants), applied to list terms.
- `resolve_sorts` types them: the argument is an `M_List` instance, `$len` is
  `Int`, `$elts` is a set of the instance's element. The rewrite renames each
  to its instance (`$len$M_List$Int`) and reports it like a measure instance.
- `query_instance_preamble` declares each instance with its axioms: non-negative
  length, the `Nil` value, and one recursion equation over `Cons` with a
  `Cons`-headed pattern.

### 2.2 Tier 2 over built-in list returns and parameters

- `post_induction_shape` and `induction_match_adt` accept `List` when the
  measure preamble does not declare it, since each query now declares its list
  instances.
- In the predicate and in guards, `len`/`elts` applied to a list term reflect
  to `$len`/`$elts` (unless a user measure named `len` is registered).
- An `Elem` constructor payload that is a variable reflects as that variable
  instead of a fresh constant, so `Cons(h, acc)` keeps `h`.
- RED: the test `the built-in len does not yet carry Tier 2 induction` flips;
  new accept and reject fixtures for an `elts` contract proved by recursion.

### 2.3 Routing

- A `List` return whose predicate uses `elts` tries Tier 2 before the existing
  elts path, which still runs (and reports) when Tier 2 does not prove it.

### 2.4 Ledger for the match shape

- Shape 2 records its verdict exactly once, as Shape 1 does. Expect ledger
  count changes under existing Tier 2 fixtures; each is reviewed.

### 2.5 Local functions

- A block-level `fn` with a refined return is checked like a top-level one,
  the induction hypothesis keyed on the local name, and its proven contract
  propagates to its calls in the enclosing body.

### 2.6 Stdlib contracts

- `reverse`, `append`, `filter`, `dedup` and their `go` helpers get proved
  contracts (design §3.3), bodies unchanged. Oracle diff reviewed line by line;
  audit baselines regenerated with the reason recorded.

**Landed** on the Phase 2 branch, 2.1 to 2.6, with these additions found
necessary on the way:

- The built-in `len` of a CALL carries the callee's proved contract at call
  sites (it only existed for `elts`), without which the flipped frontier test
  could not report.
- A postcondition check uses callee contracts (`post_lookup`), so the
  verification gate became a monotone fixpoint; local `fn` contracts are
  proved first and overlaid; Tier 2 accepts leading local `fn`s and assumes
  parameter refinements (`dedup`'s helper keeps `member(prev, elts(acc))`).
- Call sites fold `elts(Cons(h, acc))` with a named tail.
- The gate took a declaration's key without checking that the declaration
  itself carried the refinement; checking `stdlib/list.march` directly (the
  CI skip ratchet) put the prelude's unrefined `reverse` beside `List`'s and
  dropped the real contract.

### Phase 2 exit

- The Phase 1 gates, including the full suite under z3 4.8.12.

## 3. Phase 3 — cardinality by ground instantiation

Design §4. Stacked on the Phase 2 branch (it reuses the per-query set
declarations and callee contracts).

### 3.1 Vocabulary and term

- `card(s)` joins the set vocabulary: predicate-only, well-formed on one set
  operand, an `empty` argument is the set literal.
- `Smt.SetCard of sort * term` carries the element sort; it renders
  `(card$<elem> s)`, and `set_preamble` declares one `card$<elem>` per element
  sort a query uses, beside that sort's `define-sort`. `resolve_sorts` types
  it (its operand is a set, its value an Int).

### 3.2 Ground facts

- Only for a query that mentions `card`, after sort resolution: every set
  subterm gets the design's facts (non-negative; `empty` 0; `singleton` 1;
  union and difference with a singleton by membership; general union, inter
  and diff bounds; `subset` monotonicity), and a set constant `elts$x` beside
  `len$x` (or `$elts`/`$len` of one term) gets `card <= len`. Equality needs
  nothing: `card` is a function, so congruence already gives it.
- Every fact is a theorem of finite sets; a query without `card` is unchanged.

### 3.3 Contracts

- `Set.size : {Int | _ == card(elts(s))}` and `Map.size : {Int | _ ==
  card(keys(m))}`, `@[assume]`d, each with a property witness in
  `test/stdlib/test_set.march` / `test_map.march`.
- Accept: `Set.size(Set.insert(Set.empty(), x, cmp)) == 1`, size unchanged by
  inserting a present element, `size(remove(s, x)) <= size(s)`. Reject
  control: `Set.size(Set.insert(Set.empty(), x, cmp)) == 2` is reported.

**Landed** on the Phase 3 branch, 3.1 to 3.3, with two additions:

- A set with a member is non-empty (`member(x, s) => card(s) >= 1`), a
  finite-set theorem the design's table lacked; without it `member(3,
  elts(ys))` did not give `card(elts(ys)) > 0`.
- A scalar callee's contract translates a measure over a NESTED call
  (`card(elts(Set.insert(…)))` in `Set.size`'s), through the same call-contract
  translation a call-site actual uses.

### Phase 3 exit

- The Phase 2 gates; the oracle diff is expected to be empty outside `Set`
  and `Map` contract counts, since no existing query mentions `card`.

## 4. Later phases

Phase 4 (`SortedSet`) gets its own step list when Phase 3 lands; the design's
§5 is the starting point.
