# Set Refinements — a Liquid-Haskell-parallel set theory for the checker

**Date:** 2026-09-13
**Status:** Implemented 2026-09-13 (all five phases; see
`specs/progress/2026-09-13-set-inclusion-refinements.md` for what landed and
where it departs from this design).
**Plan:** `specs/plans/set-refinements-plan.md`
**Related:** `specs/2026-06-21-measure-axioms-design.md` (the axiom machinery
this reuses), `specs/lang/refinement-types.md` (the user-facing reference this
extends), `specs/progress/2026-09-13-set-inclusion-refinements.md`.

## 1. Motivation

Today the checker can say nothing about which elements a collection holds.
The predicate fragment is Int/Bool linear arithmetic, `len`, user `@[measure]`s
returning Int or Bool, and constructor tags. List and ADT payloads are the
opaque SMT sort `Elem`, so the solver cannot even state that two lists share an
element. The stdlib `Set(a)` (`stdlib/set.march`) is a private HAMT that no
measure can see into.

Liquid Haskell solves exactly this gap with a small, decidable extension: a
`Set` sort encoded as a Bool-valued SMT array, a handful of logic-level
operators (`Set_mem`, `Set_cup`, `Set_cap`, `Set_dif`, `Set_sub`, `Set_emp`,
`Set_sng`), one built-in measure `listElts` from lists to sets, and *assumed*
contracts on `Data.Set`'s opaque API. That design has been in production use
for a decade. This spec transplants it onto March's existing measure and
contract machinery with the smallest possible surface.

What it unlocks, in March spelling:

```march
-- permutation: sorting preserves the element set and the length
fn sort(xs : List(Int)) : {List(Int) | elts(_) == elts(xs) && len(_) == len(xs)}

-- dedupe: same elements, possibly fewer
fn dedupe(xs : List(Int)) : {List(Int) | elts(_) == elts(xs) && len(_) <= len(xs)}

-- a key that is known to be present
fn get(s : Set(Int), x : {Int | member(_, elts(s))}, cmp) : Int

-- well-scopedness: every free variable of e is bound in env
fn eval(e : Expr, env : {List(String) | subset(free_vars(e), elts(_))}) : Int

-- a filtered list is a subset of its input
fn evens(xs : List(Int)) : {List(Int) | subset(elts(_), elts(xs))}
```

Each of these is a contract Liquid Haskell users write routinely, and each is
unprovable and skipped by the checker today.

## 2. Scope and non-goals

In scope:

- A logic-level set sort with membership, union, intersection, difference,
  subset, empty, singleton, and extensional equality.
- A built-in `elts` measure over `List(a)`, axiomatised structurally.
- User `@[measure]`s whose result is a set, under the existing structural gate.
- Assumed (`@[assume]`) contracts on the stdlib `Set` API relating its operations to `elts`.
- Path facts from `Set.contains` and `Set.is_subset` in guards.

Out of scope, deliberately:

- **Set cardinality.** There is no decidable link between the array encoding
  and `|s|`. Liquid Haskell does not provide it either. `len` stays the only
  size measure, and a contract wanting both writes both, as `sort` above does.
- **Ordering facts** on `SortedSet`. Sortedness is a separate measure design.
- **Multisets / bag semantics.** `elts([1,1]) == elts([1])`, by design.
- **Map keys.** A `keys : Map(k, v) -> Set(k)` measure is the obvious follow-on
  and is listed as Phase C, not part of the first landing.
- **Quantified set predicates** written by the user. No `forall x in s`. The
  only quantifiers in any VC remain the pattern-guarded measure axioms.

## 3. The Liquid Haskell design, and the exact parallel

| Liquid Haskell | Role | March (this spec) |
| --- | --- | --- |
| `Set a` in the logic | set sort | `Set(a)` sort in predicates, distinct from the stdlib type |
| `Set_mem x s` | membership | `member(x, s)` |
| `Set_cup a b` | union | `union(a, b)` |
| `Set_cap a b` | intersection | `inter(a, b)` |
| `Set_dif a b` | difference | `diff(a, b)` |
| `Set_sub a b` | subset | `subset(a, b)` |
| `Set_emp` | empty set | `empty` |
| `Set_sng x` | singleton | `singleton(x)` |
| `==` on sets | extensional equality | `==` / `!=` |
| `listElts xs` | list to set measure | `elts(xs)` |
| `assume` specs on `Data.Set` | opaque API contracts | `@[assume]` return refinements on `stdlib/set.march` |
| `(Array Elem Bool)` in liquid-fixpoint | SMT encoding | identical |

The names are the measure-namespace style already used for `len`: they are
meaningful **only inside a `{...}` predicate**, never in expression position.
A March program with a value-level function named `union` is unaffected, just
as one with a variable named `len` is today. No qualified alias (`Set.member`
inside a predicate) is added in v1; the `List.length` alias machinery and its
withdrawal rules (`specs/lang/refinement-types.md`, "`List.length` is an alias
of the `len` measure") show how much care a qualified spelling costs, and
nothing in the motivating examples needs one.

## 4. SMT encoding

### 4.1 Sort

One set sort per element sort actually used in the VC:

```smt
(define-sort MSet$Int  () (Array Int  Bool))
(define-sort MSet$Elem () (Array Elem Bool))
(define-sort MSet$Str  () (Array Str  Bool))
```

The element sort follows the existing scalar rule: an `Int` element is the
concrete `Int`, a `String` element is the existing uninterpreted `Str` sort
with its literal-distinctness constants, everything else is opaque `Elem`. So
`member(3, elts([1, 2, 3]))` is decided by arithmetic, and
`member("a", elts(["a"]))` by the literal-distinctness assertions the String
encoding already emits. The `$` in the sort names follows the `len$`
convention: legal in SMT-LIB, impossible in a March identifier, so no user
symbol can collide.

### 4.2 Operators

All quantifier-free, all inside Z3's decidable extensional array fragment with
the `map` combinator:

| Predicate | SMT |
| --- | --- |
| `empty` | `((as const MSet$T) false)` |
| `singleton(x)` | `(store empty x true)` |
| `member(x, s)` | `(select s x)` |
| `union(a, b)` | `((_ map or) a b)` |
| `inter(a, b)` | `((_ map and) a b)` |
| `diff(a, b)` | `((_ map and) a ((_ map not) b))` |
| `subset(a, b)` | `(= ((_ map or) a b) b)` |
| `a == b` | `(= a b)` |

`subset` is defined by union rather than a quantifier so every VC stays
quantifier-free apart from the measure axioms. Z3's array decision procedure
handles extensional equality over `map` terms, and the driver already emits no
`set-logic`, so the `ALL` tactic applies; `unknown` remains "not proved", as
everywhere else in the checker.

### 4.3 `elts` on lists

`elts` is a built-in axiomatised measure, emitted through the same preamble
builder as user measures (`refine_encode.ml`, "Measure axioms (M-a)"):

```smt
(declare-fun elts$List (M_List) MSet$Elem)
(assert (= (elts$List Nil) ((as const MSet$Elem) false)))
(assert (forall ((h Elem) (t M_List))
  (! (= (elts$List (Cons h t)) ((_ map or) (store ((as const MSet$Elem) false) h true) (elts$List t)))
     :pattern ((elts$List (Cons h t))))))
```

The `Cons` arm carries the element into the set. This is the first measure
whose value depends on a payload field, so the existing rule that replaces
non-datatype fields with fresh constants (`measure_scalar_field_dep`) does not
apply to it: `elts` is emitted by hand, not derived from a March body, and the
payload is the array index, which is sound as written.

When the list's element type is `Int` or `String`, the concrete-element sort
variant is emitted instead, so a literal list reflects to a concrete set.

### 4.4 User measures returning sets

A `@[measure]` whose declared return type is `Set(a)` is admitted under the
existing structural gate (`match` on the argument, one arm per constructor,
structurally recursive) with the arm-body fragment extended by the operators
in §4.2 and the base constant `empty`. Example, the classic scoping measure:

```march
type Expr = Var(String) | Lam(String, Expr) | App(Expr, Expr)

@[measure]
fn free_vars(e : Expr) : Set(String) do
  match e do
    Var(x)     -> singleton(x)
    Lam(x, b)  -> diff(free_vars(b), singleton(x))
    App(f, a)  -> union(free_vars(f), free_vars(a))
  end
end
```

The `Set(a)` return type is a predicate-namespace type: it names the logic
sort, and a measure so typed is not callable in expression position, which the
existing "a measure is a function of the value it measures" gate already
enforces for the non-negativity case. Payload fields of type `String` reflect
as `Str` (they are the array index); other payloads reflect as `Elem`.

## 5. Stdlib contracts

### 5.1 `Set(a)` is opaque, exactly like `Data.Set`

The HAMT in `stdlib/set.march` cannot be reflected: its structure is hash
slots and bitmaps, not elements. Liquid Haskell's answer for `Data.Set` is to
leave the type abstract, declare one uninterpreted measure from it to the logic
set, and *assume* the API's specs. March's analog is an uninterpreted
`elts : Set(a) -> Set(a)` measure (no axioms) and `@[assume]` return
refinements on the public functions:

```march
fn empty() : {Set(a) | elts(_) == empty}
fn singleton(x : a) : {Set(a) | elts(_) == singleton(x)}
fn insert(s : Set(a), x : a, cmp) : {Set(a) | elts(_) == union(elts(s), singleton(x))}
fn remove(s : Set(a), x : a, cmp) : {Set(a) | elts(_) == diff(elts(s), singleton(x))}
fn union(a : Set(a), b : Set(a), cmp) : {Set(a) | elts(_) == union(elts(a), elts(b))}
fn intersection(a, b, cmp) : {Set(a) | elts(_) == inter(elts(a), elts(b))}
fn difference(a, b, cmp) : {Set(a) | elts(_) == diff(elts(a), elts(b))}
fn contains(s : Set(a), x : a, cmp) : {Bool | _ == member(x, elts(s))}
fn is_subset(a, b, cmp) : {Bool | _ == subset(elts(a), elts(b))}
fn is_empty(s) : {Bool | _ == (elts(s) == empty)}
fn to_list(s : Set(a)) : {List(a) | elts(_) == elts(s)}
fn from_list(xs : List(a), cmp) : {Set(a) | elts(_) == elts(xs)}
```

Two `elts` measures exist, one per carrier type, resolved by the argument's
type exactly as `len` already resolves between `List` and `String`.

### 5.2 Propagation: `@[assume]`, not `@[trusted]`

The reference states that only *proven* postconditions propagate to call
sites, and the plan confirmed this in code: `gate_unverified_posts` in
`refine_post.ml` clears any return refinement the definition side did not
prove, and `@[trusted]` only relabels the recorded verdict without changing
that gate. `@[trusted]` is also a no-op outside `cap verified`, which no
stdlib module declares. So the stdlib contracts need a distinct attribute,
`@[assume]`: the return refinement propagates without a proof, the body is
not checked against it, and the ledger counts it under `trusted`. This is
Liquid Haskell's `assume` exactly. Without it the stdlib contracts would be
inert and the whole design would prove nothing. See the plan, §3.2.

### 5.3 The comparator caveat

Every stdlib `Set` operation takes an explicit `cmp`. The contracts above are
true only when `cmp` induces the same equality the logic uses. A caller who
passes an inconsistent comparator makes the trusted contract false, and the
checker cannot see that. This is the same trust boundary Liquid Haskell accepts
for `Ord` instances, and it is why the contracts are `@[assume]`d, not proved:
the trust is documented in the stdlib doc comment for each function, and §6
requires each trusted contract to be witnessed by a runtime property test so
the trust is at least exercised.

### 5.4 Path facts from guards

`if Set.contains(s, x, cmp) do … end` establishes `member(x, elts(s))` on the
then-path and its negation on the else-path, through the existing rule that a
proven (here, assumed) `Bool` postcondition propagates under the same rule as
every other postcondition. `Set.is_subset` and `List` membership helpers
follow the same route, with no new guard machinery.

## 6. Soundness gates

1. **No axiom without a witness that refutes it.** Every operator in §4.2 and
   both `elts` measures land with a REJECT fixture that fails only if the
   encoding is right. Memory note: five capability walks shipped with holes
   that only reject witnesses caught; accept-only witnesses cannot tell a
   working encoding from one that proves everything.
2. **Assumed stdlib contracts are paired with `Check.all` property tests** in
   `test/stdlib/` that check the contract at runtime over random inputs with
   the standard Int comparator. A trusted contract with no runtime witness is
   a review blocker.
3. **Sort discipline.** A VC mixing `MSet$Int` and `MSet$Elem` for the same
   variable is a sort error, which desynchronises the z3 channel and corrupts
   every later VC in the run (the failure mode documented at the top of
   `refine_encode.ml` §2). The well-sortedness pre-check that already rejects
   a `(declare-const len Int)` next to `(declare-fun len …)` is extended to
   set sorts before the VC is sent.
4. **The definite-failure stance is unchanged.** `unknown` is skipped, never
   reported. A set goal Z3 cannot decide in the array fragment is a silent
   skip, and the coverage audit counts it.
5. **Shadow discipline.** A rebound name inside a function suspends set
   measures the same way it suspends constant folding today; both fact
   channels (scope and path) must drop the fact.

## 7. Implementation plan

Files, in dependency order:

1. **`lib/refine/smt.ml`.** Add `SSet of sort` to `sort` and the term
   constructors `SetEmpty of sort`, `SetSng of term`, `SetMem of term * term`,
   `SetUnion`, `SetInter`, `SetDiff`, `SetSub`. `render_sort` emits the
   `define-sort` names from §4.1; `render` emits the table in §4.2. Set
   equality reuses `Eq`/`Ne`.
2. **`lib/refinecheck/refine_encode.ml`.** Add the seven predicate names to
   the vocabulary (`predicate_operators` for the operators, `is_measure` for
   `elts`), sort inference so `elts(xs)` picks `MSet$Int` vs `MSet$Elem` from
   the argument's type, the hand-emitted `elts$List` preamble next to
   `list_length_defs_ok`, the uninterpreted `elts$Set` declaration, the
   `Set(a)`-returning measure gate, and the set-typed arm-body translation for
   user measures. Emit each `define-sort` at most once per VC, following the
   `skip_elem` pattern in `adt_vc_preamble`.
3. **`lib/refinecheck/refine_post.ml`, `refine_call.ml`, `refine_check.ml`.**
   Add `@[assume]` (plan §3.2) so an assumed postcondition propagates; add the
   path-fact case for an assumed `Bool` postcondition in a guard if it does not
   already fall out.
4. **`stdlib/set.march`.** The contracts in §5.1, each with a doc comment
   stating the comparator assumption. **`stdlib/list.march`.** No contracts
   needed for v1; `elts` is axiomatised structurally so `List.append`,
   `List.filter` and friends are provable from their bodies where those bodies
   are in the measure fragment, and skipped otherwise.
5. **`test/test_refinecheck.ml`.** Accept and reject fixtures per §8.
   **`test/refine_audit/corpus.baseline`** moves with every new fixture.
   **`test/stdlib/`** property tests per §6.2.
6. **Docs.** A "Set Refinements" section in `specs/lang/refinement-types.md`
   after "String Refinements", mirrored into `docs/` (the site serves `docs/`,
   and the two are full copies that must both be edited). `CHANGELOG.md`
   under `### Added`. Move the todo to `specs/progress/` in the landing commit.
7. **Counterexample rendering** (`specs/2026-08-30-counterexample-surfacing-design.md`).
   Z3 models array values as `store` chains over a `const`; render them as
   `{1, 3}` and `{}` so a violated set contract reads the way the user wrote
   it. Phase D, may land separately.

Phasing:

- **Phase A.** Logic sort, operators, `elts` on lists, user set measures. No
  stdlib changes. Already unlocks `sort`, `dedupe`, `evens`, `free_vars`.
- **Phase B.** Stdlib `Set` contracts and property witnesses.
- **Phase C.** `keys` measure on `Map`, same shape as Phase B.
- **Phase D.** Set counterexamples.

## 8. Test plan

Each row is one accept fixture and one reject fixture; the reject fixture
must go red on the intentionally broken encoding before its accept twin is
trusted (prove RED, then GREEN).

| Property | Accept | Reject |
| --- | --- | --- |
| literal membership | `f([1,2,3])` against `member(2, elts(_))` | `member(4, …)` |
| union | `elts(append(xs, ys)) == union(elts(xs), elts(ys))` proved from a structural `append` | body returning `xs` |
| subset from filter | `evens` proves `subset(elts(_), elts(xs))` | body consing a literal |
| free_vars closed term | `Lam("x", Var("x"))` against `free_vars(_) == empty` | `Var("y")` |
| assumed propagation | `insert(empty(), 3, cmp)` then a callee requiring `member(3, elts(_))` proved | requiring `member(4, …)` reported |
| guard path fact | `if Set.contains(s, x, cmp) do need_member(s, x) end` proved | else-branch call skipped, not proved |
| shadowing | `let elts = …` inside a function makes a later set fact skipped | none (silence assertion) |
| sort discipline | Int and String set VCs in one module, no channel desync | a module with 200 set VCs after one deliberately ill-sorted one still reports correctly |
| cardinality is out of scope | `len(_) == 2` next to `elts(_) == elts(xs)` still proves via `len` | `len` from `elts` alone is skipped, not proved |

Plus the refinement oracle (`scripts/refine-oracle.sh`) under a private HOME,
baseline on main, check after: no existing fixture may change verdict, since
nothing in the current corpus mentions the new names.

## 9. Differences from Liquid Haskell worth knowing

- Liquid Haskell reflects `Data.Set` operations on `Ord a`; March reflects
  them on an explicit comparator, so the trust boundary is per call, not per
  instance. The contracts are the same; the doc comment says where the trust
  sits.
- Liquid Haskell allows quantified `forall` refinements over sets with its
  `--reflection` and PLE features. This spec does not, keeping every user VC in
  the quantifier-free fragment and the no-`unknown` policy intact.
- Liquid Haskell's `Set_sub` is a native subset operator in liquid-fixpoint;
  here it is defined via union so the encoding needs nothing outside Z3's
  array theory plus `map`.
- Liquid Haskell exposes `Set_add`, `Set_com` and friends; only the seven
  operators in §3 are needed for the motivating examples, and each extra
  operator is one more reject witness to write, so the surface starts small.
