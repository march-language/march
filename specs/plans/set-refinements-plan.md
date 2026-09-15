# Set Refinements — implementation plan

**Design:** `specs/2026-09-13-set-refinements-design.md`
**Progress entry:** `specs/progress/2026-09-13-set-inclusion-refinements.md`
**Date:** 2026-09-13
**Status:** Landed 2026-09-13, all phases. The departures from this plan are
recorded in `specs/progress/2026-09-13-set-inclusion-refinements.md`.

This plan turns the design into ordered, independently landable PRs. Each phase
has an exit criterion that is a test going from RED to GREEN, never a count
staying the same. Read the design first; this document says *where* and *in
what order*, not *why*.

## 0. Findings that shape the plan

Three facts from the code that the design only flagged:

1. **Trusted postconditions do not propagate today.** The propagation gate
   (`lib/refinecheck/refine_post.ml`, `gate_unverified_posts`) clears a
   function's return refinement unless `check_fn_post_verdict` positively
   proved it. `@[trusted]` only rewrites the recorded verdict from Skipped to
   Trusted; the boolean that gates propagation stays false. And `@[trusted]`
   is a no-op outside `cap verified` (`refine_check.ml` ~1571), which no stdlib
   module declares. So Phase B needs a new, explicit assumption mechanism. This
   is Liquid Haskell's `assume`, and the plan adds it as `@[assume]` (§3.2).
2. **Predicate contents are not typechecked.** `len(_)` is not a function, and
   predicates reach the checker as raw AST. So the seven set operators inside
   `{...}` need zero typechecker work. Set-valued *user measures* are different:
   their bodies are ordinary function bodies, so `union(a, b)` in a measure
   body would be an unbound name. That is why user set measures are split into
   their own phase (A2) with a typechecker decision.
3. **The measure-axiom builder replaces payload fields with fresh constants**
   (`measure_scalar_field_dep`). `elts` needs the payload as the array index,
   so its preamble is hand-emitted next to the string preamble, not derived
   from a March body. User set measures (A2) need the arm translator to be
   taught that a payload of the set's element sort is a first-class term.

## 1. Phase A1 — logic sort, operators, `elts` on lists

Lands on its own; no stdlib or typechecker change. Exit criterion: the eight
fixtures in §1.6 pass, and each reject fixture was shown RED against a
deliberately broken encoding first.

### 1.1 `lib/refine/smt.ml`

- `type sort`: add `SSet of sort` (element sort). `render_sort`:
  `SSet SInt -> "MSet$Int"`, `SSet (SData "Str") -> "MSet$Str"`,
  `SSet (SData "Elem") -> "MSet$Elem"`. Any other element sort is a
  construction-time failure, not a render-time one; the encoder never builds it.
- `type term`: add
  `SetEmpty of sort | SetSng of sort * term | SetMem of term * term | SetUnion of term * term | SetInter of term * term | SetDiff of term * term | SetSub of term * term`.
  `SetSng` and `SetEmpty` carry the element sort because `(as const …)`
  needs the full array sort in the rendering.
- `render`: the table in design §4.2. `SetSub (a, b)` renders as
  `(= ((_ map or) a b) b)`.
- A `set_sort_decls : sort list -> string` helper that emits each needed
  `(define-sort MSet$X () (Array X Bool))` exactly once; the encoder collects
  the element sorts a VC uses and calls it from the preamble.

### 1.2 `lib/refinecheck/refine_encode.ml`

- **Vocabulary.** Add `"member"; "union"; "inter"; "diff"; "subset";
  "singleton"` to `predicate_operators` and treat the bare identifier `empty`
  as a literal in `smt_of_r` (a variable named `empty` in scope must win, so
  check `resolve_var` first; a program with a value `empty` simply loses the
  literal, the same way a local named `len` suspends the measure). Add `elts`
  to `is_measure` next to `len`.
- **Well-sortedness.** `formula_wellsorted` currently rejects every `App` in
  Boolean position because nothing returns Bool. `SetMem` and `SetSub` are
  Bool-valued and must be accepted; `SetUnion`/`Inter`/`Diff`/`Sng`/`Empty`
  are set-valued and must be rejected there. Extend `sort_conflict` so a name
  declared at `MSet$Int` and `MSet$Elem` in the same VC is a conflict, and the
  whole VC is skipped before it reaches z3 (design §6.3; the channel-desync
  failure mode is documented at the top of §2 of this file).
- **Element sort choice.** A new `set_elem_sort : A.ty -> Smt.sort` mapping
  `Int -> SInt`, `String -> SData "Str"`, everything else `SData "Elem"`. The
  binder's declared base type decides for `elts(_)`; a parameter's declared
  type decides for `elts(xs)`.
- **`elts` preamble.** A `elts_preamble : Smt.sort -> string` emitting, per
  element sort actually used, the `declare-fun` and the two axioms from design
  §4.3 over the existing `M_List` datatype. Emitted after `measure_preamble`
  and before user axioms, only when the VC mentions `elts` (the
  `needs_axiom_preamble` flag in `refine_post.ml` already exists for exactly
  this; set it when `resolve_measure_app "elts"` fires). The `Nil` equation is
  ground; the `Cons` equation is quantified with the LHS as its pattern, the
  same trigger discipline as `build_measure_preamble`.
- **Concrete evaluation.** `concrete_len` has a sibling `concrete_elts` that
  folds a literal list into nested `SetUnion (SetSng h, …)` terms so a literal
  argument never needs the quantified axiom. Mirrors the `list_len` shortcut
  in `refine_scope.ml`'s `smt_of_r`.

### 1.3 `lib/refinecheck/refine_scope.ml`

- `smt_of_r`: cases for the seven operators, each `b2` over the new
  constructors; `empty` as described above; `elts(...)` flows through the
  existing `is_measure_app` arm, with `resolve_measure "elts" x` declaring
  `elts$x` at `SSet (elem sort of x)` rather than `SInt`. That means
  `resolve_measure`'s callers (`refine_post.ml` ~341, `refine_call.ml`'s
  equivalent) pass the declared type of `x` through; today they assume `Int`.
  This is the widest-reaching edit in A1 and the one to do first.

### 1.4 `lib/refinecheck/refine_post.ml`, `refine_call.ml`

- Both `resolve_measure` closures: sort-aware declaration for `elts`, and no
  `>= 0` assumption for it (only `is_nonneg_measure` measures get one; `elts`
  is not Int, so it must not be in that list).
- Both `resolve_measure_app` closures: the `concrete_elts` shortcut, then the
  `App ("elts$List", [arg])` fallback with `needs_axiom_preamble := true`.
- `classify_pred`: `elts(xs)` over a parameter is `Relational [xs]`, exactly
  like `len(xs)`; nothing new, but add a test that it is.

### 1.5 Docs and ledger

- `specs/lang/refinement-types.md`: new "Set Refinements" section after
  "String Refinements", listing the vocabulary, the element-sort rule, the
  cardinality non-goal, and the `empty`-shadowing rule. Update the
  fragment paragraph at line ~82 and the "Limitations" bullet at ~2431.
  Mirror into `docs/refinement-types.md`; the two files already differ, so
  apply the same hunk to both rather than copying one over the other.
- `CHANGELOG.md` `### Added`.
- Coverage audit (`refine_audit.ml`): the new operators must be in the
  "known predicate function" set or every set predicate is reported as a
  hole. `test/refine_audit/corpus.baseline` and `holes.baseline` move.

### 1.6 Tests (`test/test_refinecheck.ml`, new `set_suite`)

All `gated` (z3). Names are the fixture ids to use.

| id | shape | expect |
| --- | --- | --- |
| `set/a1` | `f([1,2,3])` against `{List(Int) \| member(2, elts(_))}` | proved |
| `set/r1` | same, `member(4, …)` | violated |
| `set/a2` | `fn app(xs, ys) : {List(Int) \| elts(_) == union(elts(xs), elts(ys))}` with a structural append body | proved |
| `set/r2` | body returns `xs` | violated |
| `set/a3` | `fn evens(xs) : {List(Int) \| subset(elts(_), elts(xs))}` via `List.filter` is **skipped** (filter body is opaque); a hand-written structural filter is proved | proved / skipped as stated |
| `set/r3` | structural filter that conses a literal `7` | violated |
| `set/a4` | `{List(String) \| member("a", elts(_))}` against `["a"]` | proved, exercises `MSet$Str` |
| `set/r4` | against `["b"]` | violated (literal distinctness) |
| `set/s1` | `let elts = fn x -> 0` inside the caller; later set predicate | skipped, and the silence is asserted |
| `set/s2` | one module with an Int-set VC, then a String-set VC, then 50 Int-set VCs | every verdict as expected; guards the channel |
| `set/s3` | `{List(Int) \| len(_) == 2}` alongside `elts(_) == elts(xs)` where `xs` is `[1,1]` | `len` proved from `len`, nothing inferred from `elts` |

RED-first discipline: before wiring the rendering, stub `SetMem` to render
`true`; `set/r1`, `r2`, `r3`, `r4` must all go red. Record that run in the PR.

Also: `scripts/refine-oracle.sh baseline` on main and `check` on the branch,
under a private `HOME`; no existing fixture may change verdict.

## 2. Phase A2 — set-valued user measures

Exit criterion: the `free_vars` fixture from design §4.4 proves a closed term
and refutes an open one.

### 2.1 Typechecker decision (open; recommendation below)

A `@[measure]` body that calls `union`/`singleton`/`diff` is an ordinary
function body to the typechecker, and those names are unbound. Options:

1. **Bind the seven names as builtin prims only while checking a body that
   carries `@[measure]` and declares a `Set(a)` return**, where `Set(a)` in a
   measure signature is the *logic* set. Localised to `typecheck.ml`'s
   function-body entry, keyed on the attribute. The measure is then
   uncallable at runtime, which the existing "a measure is a function of the
   value it measures" gate can enforce as an error at any expression-position
   call.
2. Have measure bodies call the real `Set.union(a, b, cmp)` and reflect those
   calls. Rejected: the comparator parameter has no logic meaning, and it
   drags the stdlib HAMT type into a phase meant to avoid it.
3. A distinct type name (`Elts(a)`) to dodge the stdlib `Set` name. Rejected:
   two spellings of one concept in user-facing docs.

**Recommendation: option 1.** It is the only one that keeps the user-facing
spelling identical to the predicate spelling. Confirm with the owner before
touching `lib/typecheck/`.

### 2.2 `refine_encode.ml`

- `measure_param_adt` / the return-sort inference: a measure declared
  `: Set(T)` registers with SMT result sort `SSet (set_elem_sort T)`.
- `smt_of_axiom_body`: accept the seven operators and `empty`, and allow a
  bound payload variable whose field sort equals the element sort to appear as
  a term (today payload variables are only allowed as arguments to
  sub-measure calls). This is the `measure_scalar_field_dep` exception:
  a measure that *reads* a payload into a set is well-defined, and the design
  says why (§4.3).
- `build_measure_preamble`: `declare-fun` at the set sort; the non-negativity
  axiom is skipped for set-valued measures.
- The `--no-measure-axioms` flag must degrade a set measure to an
  uninterpreted symbol, not crash; add that to the existing flag test group
  at `test_refinecheck.ml` ~930.

### 2.3 Tests

| id | expect |
| --- | --- |
| `set/m1` | `free_vars(Lam("x", Var("x"))) == empty` proved |
| `set/m2` | `Var("y")` violated |
| `set/m3` | `subset(free_vars(App(f, a)), union(free_vars(f), free_vars(a)))` proved for symbolic `f`, `a` (pure axiom instantiation) |
| `set/m4` | a set measure with a non-structural arm draws the existing gate error, no axiom emitted |
| `set/m5` | calling a set measure in expression position is a compile error |

## 3. Phase B — stdlib `Set` contracts

Exit criterion: `insert(empty(), 3, cmp)` passed to a callee requiring
`member(3, elts(_))` is proved in user code, and the same with `4` is
violated.

### 3.1 The opaque measure

`elts` over `Set(a)` is uninterpreted: `(declare-fun elts$Set (M_Set) MSet$T)`
with no axioms. The stdlib type is `ptype Set(a) = HamtSet(Int, SEntry(a))`;
register it as an ADT sort with both payloads opaque, so a `Set(a)` value can
be a term at all. `resolve_measure "elts"` dispatches on the argument's
declared type between `elts$List` and `elts$Set`, the way `len` already
dispatches between list and string.

### 3.2 `@[assume]`: an assumed postcondition

New attribute, semantics: the function's return refinement propagates to call
sites **without** a proof, and the definition side is not checked against it.
Counted in the `--refine-report` ledger under `trusted`. Legal in any module,
including outside `cap verified`, because its whole purpose is to state a
fact about an opaque body. Distinct from `@[trusted]`, whose documented
meaning is "accept my *skips* inside `cap verified`", which never propagates.

Touch points:

- `refine_check.ml` ~1571: read the attribute alongside `trusted`.
- `refine_post.ml` `gate_unverified_posts`: keep `ret` when the fn carries
  `@[assume]`; `check_fn_post_verdict` is not run for it.
- `refine_post.ml` `check_post`: record verdict `Trusted` with kind
  `Postcondition` so the ledger shows the assumption count.
- Diagnostics: `@[assume]` on a function with no refined return is a warning
  ("has no effect"), mirroring the existing `@[trusted]` no-effect warning.
- `refine_audit.ml`: an assumed contract is not a hole.

### 3.3 `stdlib/set.march`

The contracts in design §5.1, each marked `@[assume]` and each doc comment
gaining one sentence: "This contract assumes `cmp` is a strict total order
consistent with `==` on the element type." Functions: `empty`, `singleton`,
`insert`, `remove`, `union`, `intersection`, `difference`, `contains`,
`is_subset`, `is_empty`, `to_list`, `from_list`. `size` and `fold` get
nothing (cardinality is out of scope).

### 3.4 Runtime witnesses (design §6.2)

`test/stdlib/test_set.march` gains one `Check.all` property per assumed
contract, over `Gen.list(Gen.int(…))` with the standard Int comparator:
membership after insert, absence after remove, union/intersection/difference
against a list-based oracle, `to_list`/`from_list` round-trip as sets,
`is_subset` against the oracle. These run in the ordinary stdlib test block,
not the `stdlib-march-properties` alias, unless they exceed ~1s.

### 3.5 Path facts

`if Set.contains(s, x, cmp) do … end`: the assumed `Bool` postcondition
`_ == member(x, elts(s))` should already enter the then/else channels through
the existing proven-Bool-postcondition path, once §3.2 makes it count as
proven. Test it; if the guard path only consults *proved* verdicts by a
separate check, extend that check to `Trusted`.

### 3.6 Tests

| id | expect |
| --- | --- |
| `set/b1` | `insert(empty(), 3, cmp)` → callee needing `member(3, elts(_))` proved |
| `set/b2` | needing `member(4, …)` violated |
| `set/b3` | `union(a, b)` → callee needing `subset(elts(a), elts(_))` proved |
| `set/b4` | `if Set.contains(s, x, cmp) do need_member(s, x) end` proved; the else-branch call skipped |
| `set/b5` | `from_list([1,2])` then `to_list` → `elts(_) == elts([1,2])` proved |
| `set/b6` | `@[assume]` on an unrefined function warns "no effect" |
| `set/b7` | `--refine-report` counts the assumptions under `trusted` |

Plus a REJECT witness for the attribute itself: temporarily mis-state
`remove`'s contract as `union` and show `set/b2`'s sibling for `remove` goes
red. Record it in the PR.

## 4. Phase C — `keys` on `Map`

Same shape as Phase B with `keys : Map(k, v) -> Set(k)` uninterpreted and
`@[assume]` contracts on `Map.put`, `Map.delete`, `Map.get`
(`{Option(v) | is_Some(_) == member(k, keys(m))}` is the one that pays for
the phase: a `get` after a `put` of the same key is provably `Some`). Fixtures
`set/c1..c4` mirror `b1..b4`. Not designed in detail here; file it when B lands.

## 5. Phase D — set counterexamples

`specs/2026-08-30-counterexample-surfacing-design.md` renders z3 models in
source terms. A set model arrives as `(store (store ((as const …) false) 1 true) 3 true)`;
render as `{1, 3}`, an all-false const as `{}`, and an `Elem` index as the
existing opaque-element spelling. One fixture asserting the rendered text of
`set/r1`'s counterexample.

## 6. Verification checklist per phase

```bash
scripts/run-tests.sh refinecheck        # the z3 suite; read the SKIP count
scripts/run-tests.sh -q                 # everything else quick
dune build --root . @types-check --force   # then assert on the log's contents
scripts/refine-oracle.sh check <base>   # private HOME; baseline taken on main
scripts/check-docs.sh                   # doc-lint after the reference edit
```

Sizes, as a rough guide: A1 is the largest at roughly 400 lines of OCaml plus
fixtures, and touches the two resolver closures that every other phase
depends on. A2 is ~150 lines plus the typechecker decision. B is ~100 lines of
OCaml, ~60 lines of stdlib, and the property tests. C and D are each under
100 lines.

## 7. Open decisions, with recommendations

1. **`@[assume]` versus widening `@[trusted]`.** Recommend `@[assume]`; the
   two attributes answer different questions and `@[trusted]`'s no-effect
   rule outside `cap verified` is documented and tested.
2. **Typechecking set-valued measure bodies.** Recommend §2.1 option 1.
3. **Should `elts` on a `Set(a)` and on a `List(a)` share a name?** Yes; the
   design's `to_list`/`from_list` contracts read naturally only if they do,
   and `len` sets the precedent for one name over two carriers.
4. **Landing order.** A1 alone is a useful release (permutation and
   dedupe contracts). Do not hold it for A2 or B.
