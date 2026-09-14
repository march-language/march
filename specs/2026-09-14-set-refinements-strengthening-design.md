# Set Refinements — strengthening the weak points

**Date:** 2026-09-14
**Status:** Accepted 2026-09-14; Phase 1 in progress.
**Builds on:** `specs/2026-09-13-set-refinements-design.md` (landed in PR #452)
and `specs/progress/2026-09-13-set-inclusion-refinements.md`.
**Open item:** `specs/todos/2026-09-14-set-refinements-strengthening.md`.

## 1. Where set refinements are weak today

The landed feature is well defined (a decidable, quantifier-free array
encoding; no known false proofs) but only moderately strong. The gaps, in
order of how much real code they block:

1. **`elts` does not follow list structure.** It folds a literal list and
   names a per-variable constant otherwise, so no function body that walks
   `Cons` cells can be proved: `reverse`, `append`, `filter`, `dedup` are all
   out of reach. This is Liquid Haskell's headline use (`listElts`).
2. **Element sorts are guessed, then reconciled.** Leaf sorts come from
   defaults (`Int` for a type-parameter value, `Elem` for every polymorphic
   payload) and `Refine_encode.resolve_set_sorts` reconciles them per query.
   Every one of the six review defects was a leaf with the wrong sort, and it
   is why string and polymorphic payloads are opaque inside measures.
3. **The stdlib `Set` and `Map` contracts are assumed.** Thirteen `@[assume]`
   contracts on a hash trie, all conditional on the comparator being lawful,
   witnessed only by property tests.
4. **No cardinality.** `Set.size` has no contract, and no contract can relate
   a set's size to `len`.

The six review defects were fixed point-wise (PR #453). Phase 1 removes the
mechanism behind them, replacing the point fixes for the wrong-sort leaves
with one derivation.

## 2. Phase 1 — typed element sorts (generalize the checks)

**Decided 2026-09-14:** generalize the sort machinery instead of boxing every
non-Int value into one universe. A set holds elements of one March type, and
the checker derives every term's SMT sort from the program's types. Boxing
(recorded in §8 as the rejected alternative) would have hidden the imprecision
instead of removing it.

### Problem

Element sorts are guessed, not derived. A value whose March type is a type
parameter is declared `Int` (`Refine_scope.scalar_sort_of_param_ty` defaults
every non-Bool, non-Float type to `Int`); a constructor payload of a type
parameter is the opaque `Elem` whatever the instantiation
(`smt_sort_of_field`); the built-in `List` is one datatype whose head is
`Elem`, so a `List(Int)` literal is not a well-sorted datatype term; and
`resolve_set_sorts` reconciles the resulting mismatches per verification
condition. Each of the six review defects was a leaf that got the wrong sort.

### 2.1 One function from March types to SMT sorts

`Refine_types.sort_of_ty : ty -> Smt.sort`, used at every leaf:

| March type | SMT sort |
| --- | --- |
| `Int`, `Bool`, `Float` | `Int`, `Bool`, `Float64` |
| `String` | `$Str` |
| a registered record `R` | `M_R` |
| a registered variant `T(t1, …, tn)`, incl. `List`, `Option`, `Result` | `(M_T ⟦t1⟧ … ⟦tn⟧)` |
| `Set(t)` in a predicate | `(Array ⟦t⟧ Bool)` |
| a type variable, an arrow, anything unmodelled | `Elem` |

The leaf sites that call it, each replacing a guess:

- a parameter: its declared type, else the typechecker's type at the
  binder's span (unannotated stdlib parameters);
- a `let` binder and a pattern variable: the typechecker's type at its span;
- a call result: the typechecker's type at the call's span;
- a constructor payload: the constructor's declared field type with the
  datatype's type arguments substituted;
- a refinement binder: its refinement's base type.

Where no type table exists (most of the test harness), the fallback is the
current behaviour, and a typed harness helper is added so new tests exercise
the real path.

### 2.2 Parametric datatypes and per-instance measures

z3 accepts SMT-LIB 2.6 parametric datatypes on both 4.8.12 (CI) and 4.16
(local), but 4.8.12 segfaults on a satisfiable query that carries a recursion
axiom over a `par` datatype with two recursive fields (`Tree(a)`), at every
instance. So each instance used is declared as a monomorphic datatype of its
own, with the same constructor names; the all-`Elem` instance keeps the bare
name and is byte-identical to the declaration used before instances existed:

```smt
(declare-datatypes ((M_List 0)) (((Nil) (Cons (Cons_0 Elem) (Cons_1 M_List)))))
(declare-datatypes ((M_List$Int 0)) (((Nil) (Cons (Cons_0 Int) (Cons_1 M_List$Int)))))
```

`Smt.sort`'s datatype case gains type arguments (`SData of string * sort
list`). SMT-LIB has no polymorphic functions, so a measure over a parametric
datatype is declared and axiomatised per instance actually used in a query
(`len$List$Int`, `elts$List$Elem`), and the measure preamble becomes a cache
keyed by the instance set rather than one global string. Instances are
generated from the same axiom templates, so a new instance cannot drift from
the others.

### 2.3 Polymorphic contracts transfer by re-reflection

A contract proved for `List(a)` is proved at the opaque `Elem`. At a call site
it is substituted into the caller's namespace and reflected again at the
caller's concrete sort. This is sound for the quantifier-free, arithmetic-free
use an element sort gets: a formula valid over an uninterpreted sort is valid
over every domain, `Int` included.

### 2.4 The single-type rule, enforced

A set predicate whose operands have known, different element types
(`member("a", elts(ints))`, `elts(xs) == keys(m)` with differing types) is a
reported error at the predicate, not a skip. An unknown element type on
either side is not an error; the query simply does not prove it.

### 2.5 What is deleted, what stays

- Deleted: the `Int` default for non-scalar parameter sorts, the single
  `M_List`/`M_Option`/`M_Result` datatypes with `Elem` payloads, the placeholder
  element sort for set terms whose element type is now known, and the
  per-review point fixes this replaces (`selector_field_sort`,
  `axiom_body_sort`'s refusal path becomes unreachable for well-typed code).
- Stays: `resolve_set_sorts`, narrowed to inferring the element sort of
  literals with no typed operand (`empty`, `singleton(1)` on its own) and to a
  final well-sortedness gate. A mismatch it finds in a typed query is a bug in
  a leaf site: it is recorded as a skip with its own reason and fails the test
  suite through a debug assertion.

### Cost and risk

This touches every leaf site in `refine_call.ml`, `refine_post.ml`,
`refine_scope.ml` and `refine_resolve.ml`, and every datatype preamble. A wrong
leaf sort is a z3 error, which the solver channel reports as a skip, so the
gate in §2.5 is not optional. The refinement oracle must be run against
`main` under a private `HOME`, and every verdict change explained; changes
must be skips becoming proofs or reports, never the reverse, unless the
explanation is a previously wrong sort. VC cache keys change for every query
that mentions a datatype, so the cache misses once.

## 3. Phase 2 — structural `elts` and `len`, and induction that reaches the stdlib

### 3.1 Axioms

With Phase 1, `(M_List T)` is well-sorted for every element type, so both
built-in list measures become ordinary axiomatised measures, instantiated per
element sort:

```smt
(assert (= (elts$List$Int (as Nil (M_List Int))) ((as const (Array Int Bool)) false)))
(assert (forall ((h Int) (t (M_List Int)))
  (! (= (elts$List$Int (Cons h t)) (store (elts$List$Int t) h true))
     :pattern ((elts$List$Int (Cons h t))))))
```

and the matching `len` equations. They register through
`build_measure_preamble`, so `--no-measure-axioms` degrades both to the
current symbolic behaviour. This lifts the documented frontier "the built-in
`len` does not yet carry Tier 2 induction" (test
`the built-in len does not yet carry Tier 2 induction`, which must flip).

### 3.2 Induction

Tier 2 (`Refine_post.check_post_induction`) needs three extensions to reach
the stdlib as written, without changing any stdlib body:

1. **Set-sorted measure applications** in its per-VC declarations, so a
   predicate `elts(_) == union(elts(xs), elts(ys))` is a Tier 2 goal.
2. **Local functions.** `List.reverse`, `append`, `filter` and `dedup` do their
   work in a block-level `fn go(lst, acc)`. `visit_local_fn` must run the
   postcondition check, including Tier 2 with the induction hypothesis keyed
   on the local name, for a local `fn` with a refined return.
3. **Verdict recording for the match shape.** Shape 2 is verdict-only today,
   so a proved or failed inductive postcondition files no obligation and the
   audit cannot tell it from an unchecked one. Record it exactly once, as
   Shape 1 does.

The accumulator form needs nothing new: the hypothesis at `go(t, Cons(h, acc))`
is instantiated with the call's actuals, and `t` is structurally smaller.

### 3.3 Proved stdlib contracts

| Function | Contract | How |
| --- | --- | --- |
| `reverse` | `elts(_) == elts(xs) && len(_) == len(xs)` | `go : elts(_) == union(elts(lst), elts(acc))` by induction |
| `append` | `elts(_) == union(elts(xs), elts(ys))` | `reverse`'s propagated contract plus `go` |
| `filter` | `subset(elts(_), elts(xs))` | both `if` branches of `go`, guard opaque |
| `dedup` | `elts(_) == elts(xs)` | `go` plus `reverse` |

`map` stays out of scope: the image of an arbitrary callback has no set
expression. These contracts are proved, not assumed, so they carry no
`@[assume]` and no comparator caveat.

## 4. Phase 3 — cardinality by ground instantiation

### Vocabulary

`card(s)`: the number of elements of a set. Predicate-only, like the rest.

### Encoding

`card` is an uninterpreted `(Array Elem Bool) -> Int`. No quantified axiom is
emitted. Instead, when a VC is final, the encoder walks its set terms and adds
ground facts, each a theorem of finite sets:

| Term in the VC | Facts added |
| --- | --- |
| any set term `s` | `card(s) >= 0` |
| `empty` | `card = 0` |
| `singleton(x)` | `card = 1` |
| `union(a, singleton(x))` | `member(x, a) => card = card(a)`; `not member(x, a) => card = card(a) + 1` |
| `diff(a, singleton(x))` | the mirror image |
| `union(a, b)` | `card(a) <= card`, `card(b) <= card`, `card <= card(a) + card(b)`; `inter(a, b) == empty => card = card(a) + card(b)` |
| an atom `subset(a, b)` | `subset(a, b) => card(a) <= card(b)` |
| an atom `a == b` | `a == b => card(a) = card(b)` |
| `elts(xs)` beside `len(xs)` | `card(elts(xs)) <= len(xs)` |

Every fact is true of the intended finite-set model, so anything proved is
true; the scheme is incomplete by design. `card` is declared per element sort
used, like the Phase 1 measures.

### Contracts

- `Set.size : {Int | _ == card(elts(s))}` and `Map.size : {Int | _ == card(keys(m))}`,
  assumed, with property witnesses.
- Provable at call sites: `Set.size(Set.insert(Set.empty(), x, cmp)) == 1`,
  size after inserting a present element is unchanged, `size(remove(s, x)) <=
  size(s)`.
- Not provable: `card(elts(dedup(xs))) == len(dedup(xs))` needs "no
  duplicates", a quantified property.

## 5. Phase 4 — prove `SortedSet` as far as the unordered fragment allows

### Target

`stdlib/sorted_set.march`'s AVL tree, with a set-valued measure over it:

```march
@[measure]
pfn tree_elts(t : Tree(a)) : Set(a) do
  match t do
    Leaf -> empty
    Node(l, k, r, _) -> union(tree_elts(l), union(singleton(k), tree_elts(r)))
  end
end
```

### The comparator law, stated once

Every public operation's correctness depends on `cmp(x, k) == 0` meaning
`x == k`. Today that trust is spread over thirteen assumed contracts. Here it
is one:

```march
@[assume]
pfn compare(cmp : a -> a -> Int, x : a, k : a) : {Int | (_ == 0) == (x == k)} do
  cmp(x, k)
end
```

and every `let c = cmp(x, k)` in the tree functions becomes
`let c = compare(cmp, x, k)`. This is the only stdlib body change in the whole
design; it adds one call that the optimiser inlines, which a compiled
benchmark of `bench/` set workloads must confirm.

### Checker prerequisites

1. **Nested constructor patterns** in Tier 2's match shape
   (`rotate_right`: `Node(Node(ll, lk, lr, _), k, r, _)`), by conjoining one
   pattern equation per nesting level.
2. **Catch-all arms** whose tail needs no pattern equation (`_ -> t` under
   `tree_elts(_) == tree_elts(t)`).
3. **Non-recursive helper postconditions** (`make_node`, `rotate_*`,
   `balance`) proved by unfolding and propagated through `let` bindings in arm
   bodies, which the existing ADT scope-binding path already carries.
4. **Element equality at the element sort** in path facts, so `c == 0` from
   the equal branch plus `compare`'s contract yields `x == k`; with Phase 1,
   `x` and `k` are declared at the tree's element sort, not `Int`.

### What is proved, and what stays assumed

| Function | Contract | Status |
| --- | --- | --- |
| `tree_insert` | `tree_elts(_) == union(tree_elts(t), singleton(x))` | proved (law used in the equal branch) |
| `tree_to_list` | `elts(_) == union(tree_elts(t), elts(acc))` | proved |
| `balance`, `rotate_*`, `make_node` | `tree_elts(_) == tree_elts(t)` (or of the parts) | proved |
| `tree_member` | `not _ \|\| member(x, tree_elts(t))` | proved (soundness direction only) |
| `tree_delete` | `subset(tree_elts(_), tree_elts(t))` | proved |
| `tree_member` exact, `tree_delete` exact, `size` | full equality | **assumed** |

The assumed rows need the search-tree ordering invariant: every element of the
left subtree compares below `k`. That is a universally quantified property of
a set, outside the quantifier-free fragment, and this design does not attempt
it. They stay `@[assume]`, now over a partly verified structure.

`union`, `intersect` and `difference` fold a closure over `List.fold_left`;
proving them needs a fold invariant, also out of scope. They stay assumed.

The hash-trie `Set` and `Map` stay assumed. A new differential property test
checks `Set` against `SortedSet` on random operation sequences, so the
assumed contracts are witnessed against a partly proved reference, not only a
list oracle.

## 6. Ordering and dependencies

1. The six in-flight defect fixes land first.
2. **Phase 1** (typed element sorts). It replaces the point fixes for defects
   2 and 3 and must keep their regression tests green.
3. **Phase 2** (structural `elts`/`len`, Tier 2 for local fns and sets).
   Needs Phase 1.
4. **Phase 3** (cardinality). Needs Phase 1 only; can run in parallel with
   Phase 2.
5. **Phase 4** (`SortedSet`). Needs Phases 1 and 2.

Each phase is one PR.

## 7. Verification, per phase

- Every new accept case sits beside a reject case, and each new test is shown
  to fail on the unfixed code before it is trusted.
- Phase 1: every existing `set-refinements` case keeps its ledger triple or
  improves it with an explanation; a debug build asserts no query reaching z3
  is ill-sorted across the whole refinement suite; a `List(Int)` literal and a
  generic `List(a)` value both reflect as well-sorted datatype terms; the
  single-type error has accept and reject fixtures; `--refine-report`
  wall time over the stdlib is measured before and after.
- Phase 2: a mutated `go` that drops `h` must be violated for `reverse`; the
  `len` frontier test flips; the stdlib List contracts appear as proved, not
  trusted, in `--refine-report` on `stdlib/list.march`.
- Phase 3: reject controls such as `Set.size(Set.insert(Set.empty(), x, cmp)) == 2`.
- Phase 4: a mutated `tree_insert` that drops `x` in the `Leaf` arm must be
  violated; compiled benchmark before and after the `compare` change.
- All phases: full `test_refinecheck.exe`, `scripts/run-tests.sh -q`,
  `@types-check --force`, `scripts/refine-oracle.sh` under a private `HOME`
  with a baseline from `main`, regenerated audit baselines with the diff
  explained, and "What sets do not do" updated in both
  `docs/refinement-types.md` and `specs/lang/refinement-types.md`.

## 8. Decisions

1. **Typed sorts, not boxing.** Decided 2026-09-14. Boxing every non-Int value
   into one opaque universe (one list datatype, one set sort, injective box
   functions with a quantified inverse axiom each) was the smaller change, but
   it kept guessed leaf sorts, added quantified axioms to every set query,
   kept element arithmetic out of reach, and turned type mistakes into skips.
   Sets hold a single element type; mixed-type set predicates are errors.
2. **The comparator law is an assumed `compare` helper.** Adopted as
   recommended: dependent codomains on callback types would need dependent
   arrows, which March does not have.
3. **The search-tree ordering invariant is out of scope.** Adopted as
   recommended; revisit only with a measured prototype of quantified set
   reasoning.
