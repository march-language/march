# Design: abstract refinements, the leftovers (richer lambdas, `not p`, tuples, the other filters)

**Date:** 2026-10-18
**Status:** phase A (richer lambda bodies) landed 2026-10-18
(`specs/progress/2026-10-18-abstract-refinements-leftovers-phaseA.md`); phase B (negation,
generalized slots, concrete bases, the erased sort) landed 2026-10-18
(`specs/progress/2026-10-18-abstract-refinements-leftovers-phaseB.md`); phase C (tuple element
returns, destructuring, `List.partition`) landed 2026-10-18
(`specs/progress/2026-10-18-abstract-refinements-leftovers-phaseC.md`); phase D (the stdlib
sweep: `Prelude`/`Enum`/`Iterable`/`Range` filters and finds) landed 2026-10-18
(`specs/progress/2026-10-18-abstract-refinements-leftovers-phaseD.md`); E not started.
Five phases (§8), one PR each. Phase E was decided "go" (see the trailing user decisions).
**Continues:** `specs/2026-09-20-abstract-refinements-design.md`. All four of its phases have
landed (records: `specs/progress/2026-09-20-…-phase1.md`, `2026-10-06-…-phase2.md`,
`2026-10-07-…-phase3.md`, `2026-10-08-…-phase4.md`).
**Closes:** three of the four "what is still open" items at the end of
`specs/progress/2026-10-08-abstract-refinements-phase4.md`:
- `List.partition`: `p` inside a tuple and under `not`.
- `Deque.filter`.
- a lambda body that is more than one eta-reducible call.

The fourth item, two-argument predicates (`Map.filter`, a `fold_left` invariant), belongs to
sibling designs and `specs/todos/2026-09-20-abstract-refinements-multi-arg-callbacks.md`.
Nothing here touches arity.

The 2026-09-20 design keeps its vocabulary: *definer* (`pred : a -> Bool[p]`), *positive
occurrence* (`List(a[p])` in the return), *negative occurrence* (in a parameter), *instantiation*
(`q`, the concrete predicate a call substitutes for `p`), *too-weak* (a refuted `q ⇒ D`, a skip and
never a violation, decision 9.2 there).

---

## 0. Where things stand (probed 2026-10-18 at `ba8db5805`, binary built 2026-10-18 10:12)

Each probe is a module with `sum_pos(xs : List({Int | _ > 0}))`,
`sum_nonpos(xs : List({Int | _ <= 0}))`, `is_pos(n) : {Bool | _ == (n > 0)}`,
`is_neg(n) : {Bool | _ == (n < 0)}` and `gt(n, m) : {Bool | _ == (n > m)}` where used. Each was run
`HOME=$SP/home march --check --refine-report --refine-report-sites probe.march`. The *Today* column is
the measured verdict at the demanding call. The reason detail came from re-running the same module
under `cap verified`, which prints it. The *After* column is the phase that changes it (§8).

### 0.1 Lambda bodies (item 3)

| Row | Passed for `p` (to `List.filter`) | Today | After |
|---|---|---|---|
| L1 | `fn y -> is_pos(y) && y < 100` | uninstantiated ("calls `is_pos`, whose result is not reflected there (yet)") | **proved** (A) |
| L1c | `fn y -> is_pos(y) \|\| y < 100` | uninstantiated | **too-weak** (A) |
| L2 | `fn y -> if y > 0 do y < 100 else false end` | uninstantiated ("mentions a name other than its own parameter"; that reason is wrong) | **proved** (A) |
| L2c | `fn y -> if y > 0 do true else y > -5 end` | uninstantiated | **too-weak** (A) |
| L3 | `fn y -> not(is_neg(y)) && y != 0` | uninstantiated | **proved** (A) |
| L3c | `fn y -> not(is_neg(y))` | uninstantiated | **too-weak**: admits `0` (A) |
| L4 | `fn y -> match y > 0 do true -> y < 100  false -> false end` | uninstantiated | **proved** (A) |
| L5 | `fn y -> gt(y, 0)` (phase-3 row q06) | uninstantiated | **proved** (A) |
| L5c | `fn y -> gt(0, y)` | uninstantiated | **too-weak**: shows the arguments are substituted in order (A) |
| L5k | `fn y -> gt(y, k)`, `k` a caller parameter | uninstantiated | uninstantiated, unchanged (§2.4 rule C1) |
| L6 | `small_pos(n) : {Bool \| _ == (is_pos(n) && n < 100)}` passed by name | `small_pos`'s own contract is an `unreflectable-subject` skip, plus a `refinement_unchecked` warning; the call is uninstantiated | unchanged: a contract cannot call a non-measure, so the contract a helper exposes is pure vocabulary (§2.3) |
| L7 | `fn y -> !(y <= 0)` | **proved** already | proved |
| L8 | `let f = fn y -> y > 0`, then `fn y -> f(y) && y < 100` | uninstantiated | **proved** (A) |
| L9 | callback `k : ({x : Int \| true}) -> {Bool \| _ == (x > 0)}`, `fn y -> k(y) && y < 100` | uninstantiated ("calls `k`") | **proved** (A) |
| L10 | `fn y -> is_pos(y + 1)` | uninstantiated | **too-weak**: `y + 1 > 0` admits `y = 0` (A) |
| L11 | `fn y -> (let z = y * 2; z > 0)` (a block body) | uninstantiated | uninstantiated, unchanged (§7, my call) |

### 0.2 Negation, tuples, concrete bases (item 1)

| Row | Program | Today | After |
|---|---|---|---|
| P1 | `let (pos, neg) = List.partition(ys, fn y -> y > 0)`; `sum_pos(pos) + sum_nonpos(neg)` | 2 × `unreflectable-subject` ("the elements of `pos` are not known to satisfy it") | **proved, proved** (C) |
| Z3 | `match List.partition(ys, fn y -> y > 0) do (pos, _) -> sum_pos(pos) end` | `unreflectable-subject` | **proved** (C) |
| P2 | user `part(xs, pred : a -> Bool[p]) : (List(a[p]), List({a \| !p(_)}))`, natural style | **hard error** `abstract_refinement_misuse` "applied inside another application" on `!p(_)`; the tuple return is never checked; calls are `unreflectable-subject` | body proved, calls proved (B+C) |
| P3 | user `rej(xs, pred : a -> Bool[p]) : List({a \| !p(_)})`, correct body | the same hard error (rule 5), although the body's 4 element obligations already PROVE under `$abs_p`; the call `sum_nonpos(rej(ys, fn y -> y > 0))` is `parametric-source-unproved` | no error; call **proved** (B) |
| P3c | `rej` with the branches swapped (wrong) | **violation** (witness `pred()` true, `h = 2`), plus the rule-5 error | violation, no rule-5 error (B). Negation already works on the definition side. |
| Z2 | `{a \| not(p(_))}` spelled with `not(…)` | the same rule-5 error | accepted (B) |
| D2 | top-level `pfn filt_go(lst, pred : a -> Bool[p], acc : List(a[p])) : List(a[p])`, accumulator + `List.reverse` | 3 × uninstantiated at the `acc` slot: "the element type of the argument passed for `p`'s parameter is not known here" | **proved** (B) |
| D2c | `filt_go` pushing `h` on the *failing* branch (wrong) | the same 3 uninstantiated, **and the caller's demand is still proved**: the bug sits behind those skips | **violation** at `Cons(h, acc)` (B) |
| R1 | `ifilter(xs : List(Int), f : Int -> Bool[p]) : List(Int[p])` (a concrete base) | definition proves; the call is `unreflectable-subject` | **proved** (B) |

### 0.3 The other one-argument combinators (item 2)

| Row | Program | Today | After |
|---|---|---|---|
| D1 | `myfilter(xs, pred : a -> Bool[p]) : List(a[p]) do List.filter(xs, pred) end` (delegation) | **proved**: body and caller | proved. Delegation is a proof route that already works (§4). |
| D1c | the same with `List.filter(xs, fn y -> true)` | `abstract-refinement-too-weak` at the return | unchanged |
| W1 | user `dw` with `drop_while`'s body declaring `List(a[p])` | the return skips (uninstantiated, unreflectable); the call is uninstantiated | unchanged: the control for §4.2's "not a candidate" |
| B1 | bare `filter(ys, fn y -> y > 0)` (that is `Prelude.filter`) | `parametric-source-unproved` | **proved** (D) |
| B2 | `Enum.filter(…)`, `Iterable.filter(…)` | 2 × `parametric-source-unproved` | **proved** (D) |
| E1 | `one_pos(Enum.find(ys, fn y -> y > 0))` | `parametric-source-unproved` (`List.find` beside it: proved) | **proved** (D) |
| R2 | `sum_pos(Range.filter(Range.new(0, 10), fn y -> y > 0))` | `unreflectable-subject` | **proved** (D) |
| Q1 | `sum_pos(Deque.to_list(Deque.filter(d, fn y -> y > 0)))` | `parametric-source-unproved` ("some way a value of `a` enters `Deque.to_list` cannot be traced") | **proved** (E) |
| Q4 | `type Dq(a) = Dq(Int, List(a), List(a))`; `fn mk_bad() : Dq({Int \| _ > 0}) do Dq(1, [0 - 1], []) end` | **0 obligations, no skip, no warning**: the refinement is silently unenforced | **violation** (E) |
| Q5 | `match d do Dq(_, f, _) -> sum_pos(f) end`, `d : Dq({Int \| _ > 0})` | `unreflectable-subject` | **proved** (E) |

Facts this design rests on, each measured above or read in the code:

- **Negation already works on the definition side.** `smt_of_r_marked` maps `not` to `Smt.Not`
  (`lib/refinecheck/refine_scope.ml:399`), and the abstract arm sits beside it at
  `refine_scope.ml:310`. P3 proves its body and P3c refutes, both in the presence of the error.
  Only phase 1's rule 5 blocks it. `nested_apps` (`lib/refinecheck/refine_abstract.ml:93-108`)
  treats any one-argument application whose argument is a one-argument application as nesting, so
  `not(p(_))` reads as `p` inside `not`.
- **The call-site slot shape is exact-match only.** `abstract_slot_of_ty`
  (`lib/refinecheck/refine_check.ml:837-852`) admits `C({tyvar | p(v)})` and nothing else, so neither
  `!p(_)` nor a concrete base (`Int[p]`) reaches `abstract_flow` (`refine_check.ml:962-1049`).
- **A tuple return is invisible to the element machinery.** `elem_refinement`
  (`refine_scope.ml:1426`) only matches `TyCon` containers, and `is_container_type`
  (`refine_scope.ml:1405`) says a tuple is not one. So `has_elem_return` (`refine_check.ml:3958`) is
  false and `gate_elem_returns` (`:3965-4008`) never visits it. A `let (a, b) = …` records
  nothing in `lets` (`refine_check.ml:1788-1811`, `PatVar` only).
- **The lambda reader is one-construct deep.** `instantiate_abstract`'s `of_lambda`
  (`refine_check.ml:899-934`) accepts a body that is vocabulary-only (`classify_pred y [] body =
  Closed` and no `opaque_call`) or exactly `g(y)`. `classify_pred`
  (`lib/refinecheck/refine_encode.ml:588-627`) calls `EIf`/`EMatch` `Unusable`, which is where L2's
  misleading "mentions a name other than its own parameter" comes from.
- **`named_predicate` is one-parameter.** `refine_check.ml:864-880` requires `param_names = [n]`.
  Its source, `callee_sig` (`refine_check.ml:202`), returns only proved returns (phase-3 probe r5).
- **A helper's contract is pure vocabulary.** L6: a contract that calls a non-measure is itself
  unreflectable, so its `ret` never reaches `callee_sig` as proved. Inlining a helper's contract
  therefore never yields another call to inline. The recursion in §2 comes only from `let`-bound
  lambdas and callback parameters.
- **The parameter-slot path needs the argument's element sort.** `abstract_param_entry`
  (`refine_check.ml:1408-1430`) declines when `elem_marker_of_arg` (`:1388-1403`) finds no SMT sort.
  Inside a declaring definition the argument's elements are the rigid type variable `a`, so it
  always declines there (D2). `abstract_tyvar_slot` (`refine_scope.ml:1417-1424`) already uses the
  erased sort (`None`, Int) for exactly those elements, so that is the sort to use.
- **A type whose elements sit only inside other containers has no element model.** Field roles
  are `Param i | Self | Other` (`refine_encode.ml:1429`). A `List(a)` field is `Other`, its parameter
  is recorded as hidden (`refine_encode.ml:1797-1815`), and the parametric rule refuses that slot
  (`lib/refinecheck/refine_param.ml:503-517`). The `ECon` arm of `check_elements`
  (`refine_check.ml:1099-1115`) treats `Other` as `true`, so a refinement on such a slot is
  **silently unenforced** (Q4). `Deque` is exactly this shape: `ptype Deque(a) = Deque(Int,
  List(a), List(a))` (`stdlib/deque.march:18`).
- **Delegation already proves.** D1: a callback parameter whose codomain is the caller's own
  `p` instantiates the callee's `p` to `p` (phase 3's callback route), which translates to `$abs_p`
  under `current_abstracts` (`refine_encode.ml:117`). Several stdlib bodies below can therefore just
  call `List.filter`.
- **Through a parametric function the flow already works.** `sum_pos(List.reverse(List.filter(…)))`
  and `List.reverse(zs)` with `zs` let-bound to a filter both prove today.

---

## 1. Surface (no grammar change)

Nothing new to parse. Each line below is accepted today; phase B only removes rule 5's error for
the negation forms:

```march
fn partition(xs : List(a), pred : a -> Bool[p]) : (List(a[p]), List({a | !p(_)}))
fn rej(xs : List(a), pred : a -> Bool[p]) : List({a | !p(_)})
fn filter(r : {start: Int, stop: Int, step: Int}, f : Int -> Bool[p]) : List(Int[p])
fn filter(d : Deque(a), pred : a -> Bool[p]) : Deque(a[p])
```

- **`not p` is spelled `{a | !p(_)}` or `{a | not(p(_))}`.** `{a | not p(_)}` is a syntax error,
  because `not` is a function and needs parentheses. No `a[!p]` shorthand: it would be a grammar
  change with tree-sitter fallout for one stdlib signature. *(My call; filed as a follow-up only if
  someone asks.)*
- **A slot predicate** is any Boolean combination (`&&`, `||`, `!`/`not`) of `p(binder)` and
  ordinary vocabulary over the binder. Today's exact `p(_)` is the special case. Rule 2 (applied to
  the binder) and rule 4 (one sort) are unchanged. Rule 5 still rejects `p(q(_))` and `p(f(_))` when
  the inner name is a declared abstract refinement or the argument is computed.

---

## 2. Lambda bodies: the inliner (item 3, phase A)

### 2.1 The judgment

`q` must be **exactly** what the callback returns, as an ordinary predicate over its one
parameter: `∀y. cb(y) = q(y)`. Phases 2 and 3 obtain it only from a vocabulary-only body or one
eta call. This phase defines a translation `⟦·⟧` from a lambda body to such a `q`, or a reason it
cannot. It is a partial function. Each arm states an equivalence, never an implication.

Write `Δ` for the inlining depth (starting at 0, bounded by `Δmax = 4`), `y` for the lambda's
binder, and `B` for the set of names bound by the lambda itself (just `{y}` for v1).

| Body form | `⟦·⟧` | Why it is exact |
|---|---|---|
| a literal, `y` | itself | — |
| `op(e₁, …, eₙ)`, `op` with `known_predicate_fn op` (`refine_encode.ml:1339`): operators, measures, testers, constant functions | `op(⟦e₁⟧, …)` | vocabulary is reflected as itself |
| `if c do t else e end` | `(⟦c⟧ && ⟦t⟧) \|\| (!⟦c⟧ && ⟦e⟧)` | Boolean `ite`. `definedness` (`refine_scope.ml:238-251`) follows `&&`/`\|\|` short-circuiting, so `if d != 0 do x / d > 0 else false end` stays defined everywhere, as it is at runtime. |
| `match s do true -> t  false -> e end`, arms in either order, or one `true`/`false` arm plus `_`; no guards; nothing else | as the `if` with `c = ⟦s⟧` | the same `ite` |
| `g(a₁, …, aₙ)`, where `g` resolves (§2.2) to a **local lambda** `fn (z₁, …, zₙ) -> b` | `⟦b[z⃗ := ⟦a⃗⟧]⟧` at `Δ + 1` | β-reduction of a pure expression (the inliner only accepts pure forms) |
| `g(a₁, …, aₙ)`, where `g` resolves to a **proved contract** `{Bool \| _ == e}` over `n` parameters `x⃗` | `e[x⃗ := ⟦a⃗⟧]` | the definition proved `g(x⃗) = e` for every return (`callee_sig` hides an unproved one) |
| `e : T`, a one-element block `do e end` | `⟦e⟧` | — |
| anything else (`let` in a block, a `match` on a non-Bool, a lambda, a call that resolves to nothing proved) | **decline**, naming the construct | — |

When `⟦body⟧` succeeds, its result is classified with `classify_pred y [] r`. It must be `Closed`,
or the call declines with today's "mentions a name other than its own parameter" (§2.4, C1).

Phase 3's eta case `fn y -> g(y)` becomes the one-argument instance of the proved-contract row.
`by_name` keeps its own error text for the bare-name case.

### 2.2 Name resolution inside the body

A call head `g` is resolved in this order. The first hit decides, and a hit that is not inlinable
is a decline. It never falls through to an outer meaning.

1. `g ∈ B` (the lambda's own parameter, say an element that is itself a function): **decline**.
2. `local_lambda_of lets g` (`refine_check.ml:892`): the `let`-bound lambda, read in the `lets`
   channel at the *call* (phase 3's rule: it shadows a top-level function of the name).
3. `callee_sig ctx defs cb g` (`refine_check.ml:202`), which honours `ctx.locals` and the callback
   env. It covers a top-level function, a callback parameter (signature over `$cb_arg`) and a local
   `fn`. Only a proved `{Bool | _ == e}` return is used (`named_predicate_n`, §6.1).
4. Otherwise, decline: "calls `g`, whose result is not reflected there".

### 2.3 Termination and depth

A proved contract's `e` is vocabulary (§0, L6), so the contract row never recurses. A local
lambda's body may call another local lambda, so that row recurses. `Δmax = 4`; at `Δ = Δmax` the
call declines with "inlining `g` would exceed the depth bound (4)". *(My call. Four covers every
realistic chain of let-bound helpers, and the bound exists for termination, not precision.)*

### 2.4 Capture-freedom rules (each one a decline when violated)

- **C1 Closed result.** After inlining, `q` mentions no free variable but `y`. A caller local, a
  captured `k`, or a let-bound lambda's captured variable all decline (L5k). Admitting them would
  put a caller name into a `contenv` entry, and `entry_is_closed` exists to stop exactly that.
- **C2 Simultaneous substitution.** Formals are replaced with `subst_params`
  (`refine_encode.ml:656`, simultaneous by construction; see the comment at `:643-655`). With
  `gt(y, 0)` against `n > m` that gives `y > 0`. Sequential substitution would capture when an actual
  mentions a later formal's name.
- **C3 The result binder stays out.** In a contract `{Bool | b == e}`, `e` must not mention `b`
  (or `_`). Today's `named_predicate` admits `Relational [_]`, which lets `e` mention the binder.
  The n-ary version requires `Closed` or `Relational ps` with `ps ⊆ x⃗` and `b ∉ fv(e)`.
- **C4 The head is not a value.** `subst_params` never rewrites an application head
  (`refine_encode.ml:660`), so a parameter that shares a measure's name cannot turn into a call.
  The inliner relies on that, and on §2.2 step 1.
- **C5 No self-reference.** A let-bound lambda whose body mentions its own bound name
  (`let f = fn y -> f(y) && …`, where the inner `f` is an *outer* binding) declines. The `lets`
  channel would return the new lambda for the inner `f`, which is the wrong binding.
  `launder_shadow` (`refine_scope.ml:1304-1309`) already retires entries whose right-hand side
  mentions a rebound name. This rule covers the one entry it cannot see: the binding itself.
- **C6 Actuals are inlined first.** `is_pos(is_pos_int(y))` inlines the actual (and declines if
  the actual declines) before substituting, so no un-inlined call reaches the solver.

### 2.5 Diagnostics

A too-weak skip today names the lambda as `fn y -> <q>`. After this phase it prints the source
lambda and its reading: ``fn y -> is_pos(y) || y < 100` (read as `y > 0 || y < 100`) does not imply
`_ > 0` ``. *(My call: the reading is what the user needs to see what was assumed.)* The reason text
of an uninstantiated skip names the construct that declined (`if` arms that are not Bool, `match`
on a non-Bool, a block with `let`, the depth bound), never the misleading catch-all L2 gets today.

---

## 3. Negation, generalized slots, concrete bases (item 1, part 1; phase B)

### 3.1 Rule 5 exemption

`Refine_abstract.nested_apps` (`refine_abstract.ml:93-108`) skips an application whose head is
`not` (the AST name for both `!` and `not(…)`; `pred_str` prints it back as `!`,
`refine_scope.ml:526`). It still descends into the argument, so `not(p(q(_)))` is still rejected.
`applications` (`:75-91`) already finds `p(_)` under `not` with the right binder, and `not` itself is
filtered by `is_known`. Rules 2 and 4 need no change.

### 3.2 The generalized slot

`abstract_slot_of_ty` becomes `abstract_slot_of_ty : A.ty -> (string * string * A.expr * A.ty) option`,
returning `(container, binder, slot predicate, base)`. It accepts `C({τ | S})` where:
- `C` is a registered container;
- `τ` is a type variable **or a scalar base with an SMT sort** (`Int`, `Bool`, `Float`, `String`,
  or a registered ADT);
- `S` mentions a declared abstract refinement only as `p(binder)`, possibly under `&&`, `||` and
  `not`.

`abstract_return_slot` and `abstract_param_entry` both go through it. The instantiation is
substitution:

```
inst(S, p ↦ (y, q))  =  S with every p(v) replaced by q[y := v]
```

done by a new `Refine_abstract.subst_abstract : string -> string * A.expr -> A.expr -> A.expr`.
It shares the traversal shape of `applications` and uses `subst_params` for `q[y := v]`. The
discharge in `abstract_flow` is unchanged except that `body` becomes `inst(S, …)` over the slot's
binder. It stays one `inst ⇒ D` query per demand.

**§3.4 (the incoming fact) is conjoined outside**: `body' = incoming && inst(S, p ↦ q)`. It is
never substituted inside as `p ↦ (incoming && q)`. Under `!p` that would give `!(incoming && q)`:
true of every kept element, but far weaker than what holds.

**A concrete base skips the parametric gate and §3.4.** `parametric_ok ctx g [a]`
(`refine_check.ml:986`, `refine_param.ml:463`) and the `sources_of` trace exist for a *type
variable's* provenance. With base `Int` the fact comes from the callee's proved body alone. The
demand's sort is the declared base's (`refined_param_ty` of `{Int | …}`), never defaulted.

### 3.3 The erased element sort inside a declaring definition

`elem_marker_of_arg` (`refine_check.ml:1388-1403`) returns `Some None` (erased, Int) when all of
these hold:
- `!current_abstracts <> []`;
- the type map's element type is an unresolved type variable;
- the instantiated predicate mentions a current abstract (`$abs_`-bound).

That is the sort `abstract_tyvar_slot` gives the same elements, so a parameter-slot obligation and
the callee's own slot agree. Anything else keeps today's decline (and phase-2 probe q09b's reason for
it: never default a sort at a call site). This turns D2 into a proof and D2c into a violation. It is
also what lets an accumulator helper prove, which phase C relies on.

### 3.4 Ordering at a parameter (a soundness constraint, not a refactor)

`check_arg_elements` (`refine_check.ml:1435-1456`) tries the abstract slot **before**
`elem_refinement`, because a caller that declares its own `p` would otherwise read the callee's
`p` as its own (the comment at `:1432-1434`). The generalized slot must keep that order for the new
shapes, `!p(_)` included. Rule 5 hard-errors on `!p(_)` today, so the unsound reading is
unreachable. **The rule-5 exemption and the generalized slot must land in the same PR**, with a test
in which a caller declaring its own `p` passes a *different* predicate for the callee's `p` (§9.2,
B7).

---

## 4. Definition side for the stdlib, and the survey (item 2)

### 4.1 Proof routes, in order of preference

1. **Natural style**, as `List.filter`/`find`/`take_while` already are: `Cons(h, f(t, pred))`
   under `if pred(h)`, proved by the branch fact and the self-call hypothesis. TRMC makes it a loop.
2. **Delegation**: call an already-proved combinator with the callback passed through (D1).
3. **A top-level `pfn` accumulator helper** that carries the definer and has `List(a[p])` slots
   (D2, after §3.3). A *local* `fn` cannot be used: its container return is checked by nothing
   (`specs/lang/refinement-types.md`, "What element refinements do not do").
4. `@[assume]` plus a runtime property witness, the 2026-09-20 §4.2 precedent. **No function in
   this design needs it.**

### 4.2 The survey

Every stdlib function whose callback is a one-argument Bool predicate (the grep in §11), plus
`find`/`take_while`/`drop_while`/`filter_map`/`find_index`-shaped names:

| Function | Signature after | Proof | Phase |
|---|---|---|---|
| `List.partition` | `(List(a[p]), List({a \| !p(_)}))` | route 3: `pfn partition_go` (§5.4) | C |
| `Enum.find` (`stdlib/enum.march:208`) | `Option(a[p])` | route 1; the body is already natural style, so only the signature changes | D |
| `Iterable.find` (`stdlib/iterable.march:137`) | `Option(a[p])` | the same | D |
| `Enum.filter` (`enum.march:79`) | `List(a[p])` | route 1: rewrite to `List.filter`'s natural body (it uses an accumulator and `rev` today). No dependency on `List` is introduced: the module's comment says it avoids one. | D |
| `Enum.take_while` (`enum.march:577`) | `List(a[p])` | route 1: `List.take_while`'s natural body | D |
| `Iterable.filter` (`iterable.march:72`) | `List(a[p])` | route 1 | D |
| `Prelude.filter` (`stdlib/prelude.march:134`) | `List(a[p])` | route 1. **The highest-value row**: a bare `filter(xs, f)` in user code is this function (B1). | D |
| `Range.filter` (`stdlib/range.march:89`) | `f : Int -> Bool[p]`, `: List(Int[p])` | route 2: the body is already `List.filter(to_list(r), f)`; needs §3.2's concrete base (R1/R2) | D |
| `Deque.filter` (`stdlib/deque.march:130`) | `Deque(a[p])` | route 1 over the fields, after phase E (§6.5) | E |

**Not candidates, and why:**

| Function | Why not |
|---|---|
| `List.drop_while`, `Enum.drop_while` | The result is the suffix starting at the first element that *fails* `p`. Nothing holds of all its elements. The only fact is "a non-empty result's head satisfies `!p`", a scalar fact about one position, not an element slot. W1 is the control that keeps it unproved. |
| `List.filter_map` | The callback returns `Option(b)`, not `Bool`, so nothing defines `p`. The interesting fact (`f : a -> Option(b[q])` gives `List(b[q])`) is a definer on a *container codomain*, a different mechanism. Filed (§7). |
| `List.find_index` | The result is an index. "`p(nth(xs, i))`" needs an `nth` measure. No element slot. |
| `List.any` / `List.all`, `Deque.any` / `all`, `Range.any` / `all` | A Bool result. `all(xs, pred) == true ⇒ every element satisfies p` is a quantified fact about the *input*, not an element return. A different design. |
| `Gen.filter`, `Gen.tree_filter` | True in the semantics (`filter_attempt` panics after 100 rejections instead of returning a failing value, `stdlib/gen.march:341-353`), but `Generator(a)` holds its values inside a closure and `GenTree` holds them in a `Thunk`. The parameter is hidden even after phase E, which models only registered-container fields. Unstatable, not unsound. |
| `Seq.filter` / `Seq.find`, `Flow.filter` / `Flow.find` | Unannotated and closure-based (`Seq(fold)`). Nothing to attach a slot to. |
| `Map.filter`, `HashMap.filter`, `OrderedMap.filter`, `Sort.partition3` | Two-argument callbacks (or `cmp : a -> a -> Bool`). Sibling design. |
| `Parser.take_while` | Returns `Parser(String)`. The predicate is over code points of a string, so there is no element slot. |
| `Option` / `Result` helpers other than `Option.filter` | None takes a Bool callback (`option.march`, `result.march`). |
| `Set`, `Array` (`PVec`), `SortedSet`, `NativeArray` | No `filter` exists. Adding API is out of scope. |

---

## 5. Tuples (item 1, part 2; phase C)

### 5.1 The shape

A function has a **tuple element return** when its return type (under any container-level
refinement) is `TyTuple [T₁; …; Tₙ]` and at least one `Tᵢ` has an element entry
(`elem_refinement (Some Tᵢ) <> None`, read under the function's own `current_abstracts` as
`has_elem_return` does). Add, beside `elem_refinement` in `refine_scope.ml`:

```ocaml
type ret_elems =
  | Single of string * elem option list                 (* today's container return *)
  | Tuple of (string * elem option list) option list    (* one entry per component *)
val ret_elems_of_ty : A.ty option -> ret_elems option
```

Nested tuples (`((List(a[p]), Int), …)`) and a tuple inside a container are out of scope
*(my call)*. Their component reads `None`.

### 5.2 Definition side

`visit_fn`'s demand (`refine_check.ml:2955-2963`), `last_elem_return_proved` (`:2945`) and
`has_elem_return` (`:3958`) switch from `elem_refinement` to `ret_elems_of_ty`. The `Single` path is
the existing code, unchanged. A `Tuple` demand checks each tail `t` with a new `check_ret_elems`:

| Tail | Check |
|---|---|
| `ETuple (e₁…eₙ)`, arity matching | `check_elements` of `eᵢ` against component `i`, for each `i` with an entry |
| a self-call with a structural argument | the **tuple hypothesis**: `elem_ret_hyp` (`:2966-2990`) generalizes its third component from an entry to `ret_elems`, under the same structural-subvar condition |
| a call `g(args)` | per component: `abstract_flow ~component:i` (§5.3), else a **declared proved tuple return** (`elem_ret_proved` for `g`, entries closed and free of `g`'s abstracts, the `declared_elem_return` conditions at `:761-775` per component) |
| anything else (a variable, a `match` result bound earlier) | `record_elem_skip`, reason `unreflectable-subject`, "the tuple's components are not traced here" |

`gate_elem_returns` needs no change beyond `has_elem_return`. Its rounds already prove
`partition_go` first and `partition` next.

### 5.3 Call side: `abstract_flow ~component`

`abstract_flow` gains `?component:int`. It reads the callee's return through `ret_elems_of_ty`,
takes component `i`, and proceeds exactly as today: the slot (§3.2), instantiate, the §3.4
conjunction, one query. With no `~component`, a `Tuple` return yields `None`, as now.

### 5.4 Destructuring: how a component gets to a demand

Phase 2 deliberately gives an abstract call **no `contenv` entry**. A demand re-examines the call
through the `lets` channel (`check_elements`' `via_let` arm, `refine_check.ml:1163-1180`). Tuples
follow the same precedent:

- `let (x₁, …, xₙ) = g(args)`, each `xᵢ` a `PatVar` or `PatWild`: after `launder_shadow` with
  all binders, push `(xᵢ, $tuple_proj(i, g(args)))` for each `PatVar`, where `$tuple_proj(i, e)` is
  `A.EApp (A.EVar "$tuple_proj", [A.ELit (LitInt i); e])`. The `$` prefix cannot be a March
  identifier (the `$strlen` precedent, `refine_encode.ml:99-115`). Hook: `lets'` at
  `refine_check.ml:1788-1811`.
- `match g(args) do (x₁, …, xₙ) -> body end`, with **exactly one** branch, an irrefutable tuple of
  `PatVar`/`PatWild`, and no guard: the same entries for `body`. Hook: the `EMatch` arm at
  `refine_check.ml:1914`, where branch binders are shadowed (`:1925`). *(My call: that is the idiom
  in `test/stdlib/test_list.march:395` and `test_properties.march:605`.)*
- `via_let` gains a `$tuple_proj(i, EApp (g, args))` arm, **before** its generic `EApp` arm. It
  tries three things in order:
  1. the **tuple self-hypothesis**: `g` is the function being walked and an argument is a structural
     subvariable, the same condition as `container_entry_of_expr`'s hypothesis arm at `:731-740`.
     Component `i` of the hypothesis is then compared Refined-vs-Refined. This is what makes a
     natural-style user `part` (P2) prove.
  2. `abstract_flow ~component:i`.
  3. the declared proved tuple return's component `i`, through `check_elements` (Refined-vs-Refined,
     as for a `contenv` entry).
- The alias arm (`let y = x₁`) copies a projection entry forward unchanged.
- **The other `lets` consumers are unaffected, checked one by one:** `local_lambda_of` matches only
  `ELam`; `refine_call.ml:425` matches only an application whose head is a measure spelling;
  `alias_withdrawal_cause` reads application entries whose head resolves, and `$tuple_proj` resolves
  to nothing. The builder re-greps `lets` consumers (`grep -n 'assoc_opt .* lets'
  lib/refinecheck/*.ml`) in the PR and lists them in the progress note.

A declared proved tuple return of a **non-abstract** function (`fn split(xs) : (List({Int | _ > 0}),
List(Int))`) gets the same treatment, at no extra cost. *(My call.)* `Tuple.first(g(…))`, `fst`,
and a tuple flowing into another function stay out (§7).

### 5.5 `List.partition`

```march
doc "Splits into (elements satisfying pred, elements not satisfying pred). Every element of the
first list satisfies `pred` and none of the second does (an abstract refinement `p`, as for `filter`)."
fn partition(xs : List(a), pred : a -> Bool[p]) : (List(a[p]), List({a | !p(_)})) do
  partition_go(xs, pred, Nil, Nil)
end

pfn partition_go(lst : List(a), pred : a -> Bool[p], yes : List(a[p]), no : List({a | !p(_)}))
    : (List(a[p]), List({a | !p(_)})) do
  match lst do
  Nil        -> (reverse(yes), reverse(no))
  Cons(h, t) ->
    if pred(h) do partition_go(t, pred, Cons(h, yes), no)
    else partition_go(t, pred, yes, Cons(h, no)) end
  end
end
```

This is the same algorithm as today's (`stdlib/list.march:656-668`): one pass, two accumulators,
two reverses, tail-recursive. The only change is that `pred` is an argument instead of a captured
variable. The natural style (`let (yes, no) = partition(t, pred)`) would need the tuple hypothesis
through a `let` and is **not tail-recursive**, an O(n)-stack regression on a stdlib function.
*(My call: route 3.)*

The obligations it raises, each provable by an existing rule plus phases B and C:
- **`Cons(h, yes)` against `yes : List(a[p])`.** The generalized param slot (exact `p`) instantiates
  `partition_go`'s `p` with the callback parameter `pred`, giving `p($cb_arg)` and so `$abs_p`
  (D1's route), with the element sort from §3.3. The head proves from the branch fact `pred(h) ==
  true` and the codomain `pred(h) == $abs_p(h)`. The tail proves Refined-vs-Refined from `yes`'s own
  slot.
- **`Cons(h, no)` against `no : List({a | !p(_)})`.** A generalized slot under `not`. The `else`
  branch gives `!$abs_p(h)`.
- **The tail `(reverse(yes), reverse(no))`.** An `ETuple` tail, componentwise. `reverse` is
  parametric (z1/z4).
- **The tail `partition_go(t, …)`.** The tuple hypothesis (`t` is structural in `lst`).
- **`partition`'s tail `partition_go(xs, pred, Nil, Nil)`.** `abstract_flow ~component` for each
  component (`$abs_p ⇒ $abs_p`, `!$abs_p ⇒ !$abs_p`). The `Nil` arguments are trivially in their
  slots.

At a call (P1): `pos` gets `y > 0` and `neg` gets `!(y > 0)`. With `pos0 : List({Int | _ > 0})`
as input and `fn y -> y > 5`, `neg` gets `_ > 0 && !(y > 5)` (§3.4, conjoined outside).

---

## 6. Hook points and code changes, by phase

### 6.1 Phase A (inliner)

- `refine_check.ml:864-880`: `named_predicate` becomes `named_predicate_n : (string -> fn_sig
  option) -> string -> (string list * A.expr) option` with §2.4 C3. The one-parameter caller keeps
  its shape through a wrapper.
- `refine_check.ml:895-956`: `instantiate_abstract`'s `of_lambda` calls a new `inline_bool_body
  ~named ~local_lambda ~depth ~binder body : (A.expr, string) result`, defined just above it. The
  `opaque_call` scan goes away; its decline text becomes the inliner's "calls `g`" arm.
- `abstract_flow`'s too-weak text (`:1027-1041`) prints the source lambda and its reading (§2.5).
- Nothing in `Refine_scope`/`Refine_encode` changes: the output is ordinary vocabulary.

### 6.2 Phase B (negation, generalized slot, concrete base, erased sort)

- `refine_abstract.ml:93-108` (`nested_apps`): the `not` exemption (§3.1).
- `refine_abstract.ml`: new `subst_abstract` (§3.2) and `slot_mentions_only_applied : string list ->
  string -> A.expr -> bool` (`p` occurs only as `p(binder)`).
- `refine_check.ml:837-856`: `abstract_slot_of_ty` / `abstract_return_slot` widened (§3.2).
- `refine_check.ml:962-1049` (`abstract_flow`): `body := inst(S, …)`; for a non-tyvar base, skip
  `parametric_ok` and the §3.4 block.
- `refine_check.ml:1408-1430` (`abstract_param_entry`): uses the widened slot and `inst`.
- `refine_check.ml:1388-1403` (`elem_marker_of_arg`): §3.3.
- `refine_audit.ml:540-549` reads abstract slots through `Refine_abstract.names`. Confirm the audit
  still classifies a `!p(_)` slot as enforced. The audit test asserts it.

### 6.3 Phase C (tuples, `List.partition`)

- `refine_scope.ml` near `:1426`: `ret_elems`, `ret_elems_of_ty`.
- `refine_check.ml`: `has_elem_return` (`:3958`); `visit_fn` demand, hypothesis and final tail
  loop (`:2945-3030`); `container_entry_of_expr`'s hypothesis arm (`:731-740`), which keeps
  `Single`. The tuple hypothesis is consumed by `check_ret_elems`, not by `container_entry_of_expr`.
  Also `check_ret_elems` (new, beside `check_elements`), `abstract_flow ?component`, the `lets'`
  `PatTuple` arm (`:1788-1811`), the `EMatch` single-tuple-arm entries (`:1914-1930`), and the
  `via_let` `$tuple_proj` arm (`:1163-1180`).
- `stdlib/list.march:656-668`: §5.5.

### 6.4 Phase D (stdlib sweep)

Signatures and bodies per §4.2's table, nothing in OCaml. `Range.filter` depends on phase B.
Each rewritten body (Enum.filter, Enum.take_while, Iterable.filter, Prelude.filter) is
`List.filter`'s or `List.take_while`'s natural body verbatim, renamed.

### 6.5 Phase E (nested container fields, `Deque.filter`): only if open decision 1 says go

- `refine_encode.ml:1429`: `type field_role = Param of int | Self | Within of string * int option
  list | Other`. `Within (C, m)` means the field has type `C(args)`, and `m.(k) = Some j` when `C`'s
  slot `k` holds this type's parameter `j`.
- `register_field_sorts`'s `role_of` (`:1776-1785`) admits `Within` only when all of these hold:
  - `C` is a registered container other than the type itself;
  - every argument of `C` is either a bare parameter or free of parameters;
  - `C`'s own hidden list (`ctor_hidden_params`) excludes each mapped slot;
  - depth is one: `List(List(a))` stays `Other` and hidden. *(My call.)*

  The hidden computation (`:1797-1815`) stops counting a parameter that occurs only in `Within`
  fields.
- `refine_check.ml:1099-1115` (the `ECon` arm of `check_elements`): `Within (C, m)` checks the field
  with `check_elements` against `(C, m mapped over slots)`. This is where Q4 becomes a violation:
  **new obligations appear**, not only new facts.
- `refine_check.ml:2118-2140` (match binder facts): a `PatVar` at a `Within` field gets the
  `contenv` entry `(C, mapped slots)`.
- `refine_param.ml:503-517` (`container_paths`): needs no change once the slot is not hidden.
  Re-read it in the PR to confirm.
- `stdlib/deque.march:130`:
  ```march
  fn filter(d : Deque(a), pred : a -> Bool[p]) : Deque(a[p]) do
    match d do
    Deque(_, f, b) ->
      let f2 = List.filter(f, pred)
      let b2 = List.filter(b, pred)
      Deque(List.length(f2) + List.length(b2), f2, b2)
    end
  end
  ```
  The order is preserved: `to_list = f ++ reverse(b)`, and filtering commutes with both. It also
  skips today's `to_list` (an append and a reverse) and `from_list` (a closure fold of `push_back`).
  The construction proves through `Within` and the `via_let` abstract re-examination of `f2`/`b2`.
- **Risk, stated.** Whether `Deque.to_list` passes P1/P2 (`parametric_ok`) for Q1 is unmeasured,
  because it cannot be probed before `Within` exists. If it does not, Q1 stays a skip (never
  unsound) and the progress note says so. `Q2` (`to_list(from_list(pos))`) is **not claimed**:
  `from_list` folds a closure.

---

## 7. Scope

In scope: §2 (every row of its table), §3, §5 for one level of tuple at the return, `let`/
single-arm `match` destructuring, §4.2's "after" rows, and §6.5 if decided.

Out of scope, each named so no guarantee is read into its absence (the builder files a todo for
the ones marked ✱, one file each, in the phase where it surfaces):

- ✱ **The silent hole in Q4 for shapes `Within` does not cover** (`type Box(b) = Box(Int -> b)`,
  `List(List(a))` fields): a refinement on a hidden parameter records no obligation and no warning.
  Phase E closes the `List(a)`-field case. The rest wants at least a `refinement_unchecked` warning.
  File it in phase E, or in phase B if E is declined.
- **A block lambda body with `let`s** (L11). A substitution pass over sequential lets is easy but
  widens the inliner's surface. *(My call: not now.)*
- **Int-valued helpers inside a lambda** (`fn y -> score(y) > 3` with `score : {Int | _ == e}`):
  only Bool-result contracts are inlined.
- ✱ **A container-codomain definer** (`filter_map`'s `f : a -> Option(b[q])`).
- **Tuple components through anything but destructuring** (`Tuple.first`, passing the tuple
  on), nested tuples, tuples inside containers.
- **A `List.reject` or any new API.** *(My call.)*
- **An `a[!p]` shorthand** (§1).
- Arity > 1, `fold` invariants, `impl` dispatch, inference: unchanged from 2026-09-20 §6.

---

## 8. Phases, one PR each

Conventions are the phase-3 plan's (`specs/plans/2026-10-07-abstract-refinements-phase3-plan.md`,
"Global Constraints"):
- `--root .` and `scripts/run-tests.sh`, with z3 on PATH;
- restage `stdlib/*.march` after editing it, and probe under a fresh private `HOME`;
- capture exit codes immediately;
- every new rule gets a fixture that fails without it, shown by a one-line perturbation;
- assert ledger triples or verdict lists, never exit codes alone;
- `opaque`, `use`, `loop`, `init`, `within` and `app` are keywords, so don't name probe functions
  after them.

Every PR ships, in the same commit set:
- its `specs/progress/2026-MM-DD-abstract-refinements-leftovers-<letter>.md`;
- its CHANGELOG bullet under `## [Unreleased]` (`### Added`, or `### Fixed` for Q4);
- the `specs/lang/refinement-types.md` change, then `scripts/gen-lang-docs.py`, committing both
  (`docs/refinement-types.md` is generated);
- this design's **Status** line updated.

| Phase | Content | Depends on | Rows it moves |
|---|---|---|---|
| **A** | the inliner (§2, §6.1) | — | L1–L5c, L8–L10 |
| **B** | rule-5 `not` exemption, generalized slot, concrete base, erased sort (§3, §6.2) | — | P3, P3c, Z2, D2, D2c, R1 |
| **C** | tuple element returns, destructuring, `List.partition` (§5, §6.3) | B | P1, P2, Z3 |
| **D** | Enum/Iterable/Prelude/Range (§4.2, §6.4) | B (Range only) | B1, B2, E1, R2 |
| **E** | `Within` field roles, `Deque.filter` (§6.5) | B; **open decision 1** | Q1, Q4, Q5 |

A and B are independent and can go in either order. C needs B, because `partition`'s second
component is `!p`.

### Docs changes, per phase

Edit only `specs/lang/refinement-types.md`, in the "Abstract refinements" section
(`:2154-2265` today) and "What element refinements do not do" (`:2267`). Then run
`scripts/gen-lang-docs.py` and commit the regenerated `docs/refinement-types.md`. Never hand-edit
`docs/`; doc-lint Check F fails on that.

- **A.** In "What can instantiate `p`", add a short block showing L1, L2 and L5, the closed-result
  rule (L5k) and the depth bound. Replace the bullet "A lambda that mentions any name besides its
  parameter … single eta-reducible call" with the new decline list. Change the "two-parameter
  function … is declined" clause: it is now inlined inside a lambda, and still declined as a bare
  name for `p`, because a bare two-parameter name has no one-argument meaning.
- **B.** A paragraph on a slot predicate as a Boolean combination of `p(_)` (`!p(_)`), with `rej`
  as the example and the note that `not p(_)` needs parentheses. One sentence on a concrete base
  (`List(Int[p])`).
- **C.** In "The standard library", add `List.partition`'s signature and P1. Add to the decline
  list that only `let`/single-arm `match` destructuring carries a component. Remove the
  "`List.partition` would need `p` inside a tuple and under `not`" clause.
- **D.** Extend "The standard library" list, and the first bullet of "What element refinements do
  not do", which today says "Only four combinators". Name `drop_while`, `filter_map` and
  `find_index` as deliberately not carrying `p` (§4.2's reasons, one line each).
- **E.** Remove "`Deque.filter` does not declare one". Add one sentence on element refinements of
  a type whose elements sit in `List` fields (Q4/Q5).

### Verification each phase reports in its progress note

- `scripts/refine-oracle.sh check` against `main`, under a private `HOME`, **diff explained line
  by line**. Phase A should move no stdlib line (no stdlib call passes a compound lambda to a
  demanded combinator), so any move needs a sentence. B: also none, since no stdlib signature
  changes. C, D and E: `+proved` count lines for each new definition-side proof. Nothing may move
  from proved to skipped or violated.
- `test/refine_audit/*.baseline` regenerated (`enforced` rises by the new contract sites; 0
  unenforced).
- The CI ratchet for `stdlib/list.march`: (user + stdlib) skipped ≤ the ceiling in
  `.github/workflows/ci.yml:598`. It is **37 today** (measured 2026-10-18) and must not rise.
- The ecosystem repos (`conduit`, `depot`) compared base vs branch: byte-identical, or explained.
- The full `scripts/run-tests.sh`.
- Phases C, D and E: every rewritten stdlib body gets runtime tests in its
  `test/stdlib/test_<module>.march`, **pinned on the old body first** (they must pass before the
  rewrite): order preserved, empty input, all-pass, all-fail, and for `partition` that the two
  halves' union is the input.
- Phase E: `test/stdlib/test_deque.march` as well (the existing filter test is at `:206-210`).

---

## 9. Tests, RED first

New alcotest groups in `test/test_refinecheck.ml`, registered beside `abstract-phase3`
(`:18883`): `abstract-leftovers-a` … `-e`. They use the existing helpers `gated`, `typed_ledger`,
`typed_obligations` and `ar2_filt` (`:17609`), and each row is a §0 probe made into a fixture.
"RED" means the test fails on `main`. Each phase's progress note names the one-line perturbation
that reddens exactly its RED set.

### 9.1 Phase A

| # | Fixture | Expect | RED? |
|---|---|---|---|
| A1 | L1 | proved | yes |
| A2 | L1c | too-weak, and the message contains the reading `y > 0 \|\| y < 100` | yes |
| A3 | L2, L4 | proved | yes |
| A4 | L2c | too-weak | yes |
| A5 | L3 / L3c | proved / too-weak | yes |
| A6 | L5 (the q06 test at `:17921` **flips** to proved; rename it) | proved | yes |
| A7 | L5c | too-weak (argument order) | yes |
| A8 | L5k | uninstantiated, not too-weak | no (a guard) |
| A9 | L8, L9 | proved | yes |
| A10 | L10 | too-weak | yes |
| A11 | C5: `let f = fn y -> y > 0`, `let f = fn y -> f(y) && y < 5`, pass `f` | uninstantiated (self-reference) | no |
| A12 | depth: five chained let-lambdas | uninstantiated, reason names the bound; four chained: proved | the 4-chain is RED |
| A13 | a helper with an **unproved** `{Bool \| _ == e}` (body calls a contract-less helper, phase-3 r5 shape) inside `&&` | uninstantiated | no |
| A14 | lambda parameter shadowing a top-level predicate: `fn is_pos -> is_pos > 0` passed for `p` | proved, read as the parameter (no call) | no |
| A15 | a lambda-local `let` shadowing: `let is_pos = fn y -> y >= 0`, then `fn y -> is_pos(y) && y < 100` | too-weak (the LOCAL is read, the phase-3 rule) | yes |
| A16 | VC cache: two calls in one module, `fn y -> gt(y, 0)` and `fn y -> gt(y, -1)` | first proved, second too-weak | yes |
| A17 | `cap verified`: A1 compiles; A2 is a `refinement_unverified` error | as stated | yes |
| A18 | `if` with a division: `fn y -> if y != 0 do 10 / y > 0 else false end` | instantiates, no `solver-undecided`, no definedness skip | yes |

**Re-pointed, not deleted:** the phase-2 guard "a lambda that calls a function is uninstantiated,
not too weak" (`:17861-17876`) moves to `fn y -> mystery(y) && y < 100`, with `mystery : Int ->
Bool` and no contract. It must stay uninstantiated and not too-weak.

### 9.2 Phase B

| # | Fixture | Expect | RED? |
|---|---|---|---|
| B1 | P3: `rej` with `!p(_)` | no `abstract_refinement_misuse`; `sum_nonpos(rej(ys, fn y -> y > 0))` proved | yes |
| B2 | P3c | a violation at the return, no misuse error | yes (the error goes away) |
| B3 | Z2, `not(p(_))` spelling | same as B1 | yes |
| B4 | `not(p(q(_)))` and `!p(y + 1)` | still `abstract_refinement_misuse` | no (guards rule 5) |
| B5 | D2 | `(proved, 0 violated, 0 skipped)` for `filt_go`'s slots and the caller | yes |
| B6 | D2c | violation at `Cons(h, acc)` | yes |
| B7 | **ordering**: callee `need_not(xs : List({a \| !p(_)}), keep : a -> Bool[p])`; a caller that declares its own `p` calls `need_not(ys, fn y -> y > 0)` with `ys : List(a[p])` | the callee's `p` is instantiated to `y > 0` (a skip or a violation depending on `ys`), **never** discharged by the caller's `$abs_p` | yes |
| B8 | R1 | proved; with `fn y -> y >= 0`, too-weak | yes |
| B9 | the §3.4 conjunction under `not`: input `List({Int \| _ > 0})`, `rej(pos, fn y -> y > 5)`, demand `{Int \| _ > 0 && _ <= 5}` | proved (so the incoming fact was conjoined outside) | yes |
| B10 | the erased sort does not leak: a call site outside any declaring definition with a polymorphic argument still declines with "element type … not known" | uninstantiated | no |
| B11 | a mixed slot `{a \| p(_) && len(_) > 0}` at a `String` base, rule 4 | proves with the `String` sort | yes |

### 9.3 Phase C

| # | Fixture | Expect | RED? |
|---|---|---|---|
| C1 | P1 against the new `List.partition` | proved, proved | yes |
| C2 | Z3 (single-arm `match`) | proved | yes |
| C3 | P2 (the user's natural-style `part` with `let (yes, no) = part(t, pred)`) | body proved through the `$tuple_proj` arm's self-hypothesis step (§5.4); calls proved | yes |
| C4 | a wrong `partition_go` (the halves swapped) | violation at the `Cons` | yes |
| C5 | a component swap at the caller: `sum_pos(neg)` | too-weak | yes |
| C6 | rebinding retires a projection: `let (pos, neg) = …`, `let pos = ys`, `sum_pos(pos)` | not proved | no |
| C7 | rebinding a name the RHS mentions: `let (pos, _) = List.partition(ys, f)`, `let ys = …`, `sum_pos(pos)` | still proved (it is `pos`'s value, not `ys`'s) or retired. **Pin the retirement**: `launder_shadow` is deliberately strict. | no |
| C8 | a two-arm `match` on a partition | not proved (out of scope) | no |
| C9 | a declared, proved, non-abstract tuple return (`split_pos`) and its destructured use | proved; with a wrong body, the caller is not proved | yes |
| C10 | `cap verified` on C1 | compiles | yes |

### 9.4 Phase D

One accept row per function in §4.2's phase-D rows (B1, B2, E1, R2, and `Enum.take_while`), each
RED, plus a too-weak control per module. The runtime tests listed in §8.

### 9.5 Phase E

Q4 → violation (RED); `mk_ok` → proved; Q5 → proved (RED); Q1 → proved, or the progress note's
stated skip; a `List(List(a))` field type stays unchecked (and its ✱ todo is filed); `Deque.filter`'s
definition side proved; `stdlib/node_queue.march:281`'s `Deque.filter` call unchanged in the oracle.

### 9.6 Conformance corpus

`specs/lang/types/accept/` and `reject/` pairs, at the next free numbers when each phase lands
(t324 is the highest today):
- A: an accept with L1, L2 and L5 under `cap verified`, and a reject with L1c.
- B: an accept with `rej` and a concrete-base combinator, and a reject with P3c.
- C: an accept with `partition` under `cap verified`, and a reject with C5.
- D: an accept with bare `filter` under `cap verified`.

Update `specs/lang/types/INDEX.md` counts (doc-lint checks them).

---

## 10. Soundness

| New assumption | Justified by | Guarded by | Control (test) |
|---|---|---|---|
| A call to `g` inside a lambda equals `e[x⃗ := a⃗]` | `g`'s **proved** `{Bool \| _ == e}`; `callee_sig` hides unproved returns | `named_predicate_n` reads only `callee_sig`; C2 simultaneous substitution; C3 the binder stays out of `e`; C6 actuals are inlined first | A13, A7 |
| `if`/Bool-`match` is `(c ∧ t) ∨ (¬c ∧ e)` | Boolean logic, and the inliner admits pure forms only | only Bool-literal patterns, exhaustive, no guards; `definedness` follows the connectives' order | A3, A4, A18 |
| A `let`-bound lambda name denotes that lambda | the `lets` shadow discipline (`launder_shadow`) | C5 no self-reference; §2.2 order (own parameter, then local lambda, then `callee_sig`); `Δmax` | A11, A12, A14, A15 |
| `q` contains no caller state | — | C1 `classify_pred … = Closed` after inlining | A8 |
| `!q` holds of the elements a callback rejected | **instantiation is exact** (`cb(y) = q(y)`): every source of `q` is an equality, a lambda read by `⟦·⟧` (equivalences only) or a proved `_ == e` contract | no implication-shaped source is ever admitted (`named_predicate_n` requires `==`); §3.4 is conjoined outside `inst` | B2, B9, C4, C5 |
| A generalized slot at a parameter is the CALLEE's `p` | instantiation at this call | abstract slot tried before `elem_refinement`; rule-5 relaxation lands with it | B7 |
| `Int[p]` without the parametric gate | the callee's proved body (`elem_ret_proved`) | sort from the declared base, never defaulted | B8 |
| An argument's type-variable elements have the erased sort inside a declaring definition | `abstract_tyvar_slot` gives the same elements that sort | only with `current_abstracts ≠ []`, an unresolved tyvar, and an instantiated predicate over a current abstract | B5, B6, B10 |
| Tuple component `i` of a call holds its entry | the callee's per-component proof (gate), or instantiation as for a container | `elem_ret_proved`; structural self-hypothesis only; arity check | C4, C9 |
| A destructured binder denotes component `i` of that call | the `lets` channel, a `$`-named marker | `launder_shadow` on binders and RHS; the single-arm, guard-free, irrefutable `match` only | C6, C7, C8 |
| Every value of parameter `j` of a `Within` type lives in a mapped slot of a nested container field (E) | the type's definition: those fields are the only occurrences once `Within` stops counting them hidden | `role_of`'s four conditions; constructions are now *checked* | Q4, the `List(List(a))` row |

What is **not** claimed:
- `partition` says nothing about order, about the halves' union, or about lengths.
- `Deque.filter` says nothing about size beyond what `Deque`'s own contracts say.
- A too-weak skip stays a skip (decision 9.2 of the 2026-09-20 design).

---

## 11. Performance

- **A.** The inliner is OCaml-side, bounded by `Δmax`, and adds **no query**. `q` gets longer, so
  the one `q ⇒ D` query gets larger. The VC cache key already includes the query text, so different
  inlinings never share a verdict (A16).
- **B.** No new queries. Previously declined parameter slots (D2) now cost one query each, and only
  inside declaring definitions.
- **C.** One query per demanded tuple component, the same per-demand cost as a container. Gate
  rounds: `partition_go` then `partition`, so one extra round in `list.march`.
- **E.** New construction obligations, but only where a type argument is refined (`Deque({Int |
  …})`), which is rare in stdlib code. Facts at `match` binders cost nothing unless demanded. Measure
  the stdlib-wide `--check` along with `list.march`.
- **Runtime.** `partition` (pred passed instead of captured) and `Deque.filter` (rewritten): compile
  `--opt 2`, run interleaved base and branch over a 200k-element list ×50, warm, three runs each,
  median. Expect parity for `partition` and an improvement for `Deque.filter`. Also run
  `bench/list_ops.march` (the closure/HOF mapping in `specs/benchmarks.md`) and confirm the output is
  identical. Phase D's natural rewrites are `List.filter`'s TRMC shape, so run `list_ops` and a
  200k `Enum.filter` / `Prelude.filter` micro-run.
- **Budget**, the 2026-09-20 §8 protocol: cold `march --check --refine-report --stdlib-source
  stdlib/list.march`, private `HOME`, three runs, median. Measured **1.22 s** on 2026-10-18 (runs
  1.24 / 1.18 / 1.22, load average about 8). The project-local `.march/cas/vc` was not cleared,
  because other agents share the worktree, so re-measure base and branch back to back on the same
  machine. Each phase stays within **110%** of its base.

---

## 12. Decisions

Settled here (*my call*, change in review if wrong):
1. `not p` is spelled `{a | !p(_)}` / `not(p(_))`, with no shorthand (§1).
2. `List.partition` keeps a tail-recursive accumulator, moved to a top-level `pfn partition_go`
   (§5.5).
3. The inliner's depth bound is 4 (§2.3). Only Bool-result contracts are inlined. Lambda-local
   `let` is out (§7).
4. A too-weak message prints the lambda and its reading (§2.5).
5. Single-arm tuple `match` is in scope, alongside `let` (§5.4). A non-abstract proved tuple
   return gets the same treatment (§5.4).
6. No new stdlib API (`List.reject`).
7. `Within` is one level deep only (§6.5).

Open, for the user:
1. **Phase E**: whether to build `Within` field roles to give `Deque.filter` a meaningful
   `Deque(a[p])`. The alternative drops `Deque.filter` from the leftovers and files only the Q4
   silent-hole todo.
2. **Phase D's rewrites** of `Enum.filter`, `Enum.take_while`, `Iterable.filter` and
   `Prelude.filter` to natural style.

---

## Appendix: the survey grep

```
grep -n -E '^\s*p?fn (filter|find|take_while|drop_while|partition|reject|filter_map|find_index|find_map|retain|find_last|span)\b' stdlib/*.march
grep -n -E '^\s*fn \w+\(.*-> Bool' stdlib/{set,sorted_set,array,native_array,result,option,seq,hash_map,gen,range}.march
```

Run 2026-10-18. Every hit is classified in §4.2.

---

## Decisions settled by the user (2026-10-18)

1. **Phase E goes ahead**, last in this design's order. It also closes the silent-unenforcement hole for any user type with `List(a)` fields. (The multi-arg design's phase 0, landed 2026-10-18, already turns that hole into a recorded skip; phase E makes those fields checkable.)
2. **Phase D rewrites** `Enum.filter`, `Enum.take_while`, `Iterable.filter` and `Prelude.filter` so a bare `filter(...)` carries the predicate.
