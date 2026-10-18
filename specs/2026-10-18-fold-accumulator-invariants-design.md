# Design: accumulator invariants for fold-shaped combinators

**Date:** 2026-10-18
**Status:** design. Nothing is built. Probed on `ba8db5805` (0.6.0 + docs), z3 4.16.0.
Its dependency on sibling (a)'s scalar entry point has landed (2026-10-18, element-flow phase 2,
`specs/progress/2026-10-18-element-flow-phase2-scalar-demands.md`): `Refine_check.scalar_demand`
and `discharge_pairs` exist, `check_call` reaches them through `call_ctx.demand`, and a top-level
function's return tail reaches them through `Refine_post.tail_demand` (§3.1's third row), so
phase 1 needs no entry point of its own. Closed demands only; `invariant_params` goes inside
`discharge_pairs`' `lambda_ok`.
**Closes, when phase 2 lands:** the accumulator half of item 2 of
`specs/todos/2026-09-18-refine-element-flow-followups.md` ("`fold_left`'s
accumulator is also where a demand on `b` would act as an invariant (its
negative occurrence), a separate soundness argument"). It also closes the
`fold_left` bullet of `specs/todos/2026-09-20-abstract-refinements-multi-arg-callbacks.md`,
whose `Map.filter` bullet stays open for sibling design (b).
**Prior designs this continues:** `specs/2026-09-18-parametric-element-flow-design.md`
(§4: sources, P1/P2. Its §4.5 deferred this case.) and
`specs/2026-09-20-abstract-refinements-design.md` (the format here, and the
"refuted is skip" stance, §3.3 / decision 9.2).

**Sibling designs being written at the same time, and where the line falls:**

| Sibling | Owns | This design |
|---|---|---|
| (a) element-flow follow-ups | domain facts for multi-parameter lambdas (`x` in `fn (acc, x) -> …` receives the element fact of `xs`); the **scalar demand entry point**: a demand on a call whose declared return is a bare type variable (`need_pos(Option.unwrap_or(o, 1))`), discharged over the callee's sources | adds **one** thing to (a)'s source discharge, and to the existing container one: the *invariant hypothesis* on callback parameters typed with the demanded variable (§2). It owns no new entry point. |
| (b) two-argument abstract predicates | `p(k, v)` for `Map.filter` | disjoint. Fold signatures carry no abstract refinement, and this design adds none. |

**Assumption, stated once:** (a) lands first. Phase 1 below needs (a)'s scalar
entry point. Phase 2 needs (a)'s multi-parameter domain facts. If (a) slips,
phase 1 builds the minimal scalar entry point itself: a bare-`TyVar` return
plus the existing `discharge` (§3.1). (a) then rebases onto it. Nothing else
in this design depends on (a).

---

## 0. Where things stand (probed 2026-10-18 on `ba8db5805`)

Every row is a scratch program run as `HOME=<private> march --check
--refine-report-sites probe.march`. Each verdict is the ledger line for that
call, not an exit code. The `sum_pos`, `need_pos`, `need_nn` and `one_pos`
helpers are the usual one-liners (`{Int | _ > 0}`, `{Int | _ >= 0}`,
`List({Int | _ > 0})`, `Option({Int | _ > 0})`). `pos : List({Int | _ > 0})`,
`nn : List({Int | _ >= 0})`, `ys : List(Int)`.

| Row | Program | Today (measured) | After |
|---|---|---|---|
| f1 | `need_pos(List.fold_left(pos, 1, fn (acc, x) -> acc * x))` (positive product) | skip, `unreflectable-subject` | **proved** (phase 2: needs `x > 0` from (a)) |
| f2 | `need_nn(List.fold_left(nn, 0, fn (acc, x) -> acc + x))` (nonneg sum) | skip, `unreflectable-subject` | **proved** (phase 2) |
| f3 | `need_nn(List.fold_left(ys, 0, fn (acc, _x) -> acc + 1))` (length counter) | skip, `unreflectable-subject` | **proved** (phase 1) |
| f4 | `fn h(ys) : {Int \| _ >= 0} do List.fold_left(ys, 0, fn (a, x) -> if x > a do x else a end) end` (max ≥ init, return position) | skip, `unreflectable-subject` (postcondition) | **proved** (phase 1) |
| f5 | same as f4 with `lo` for `0` and return `{Int \| _ >= lo}` (relational) | skip, `unreflectable-subject` | **proved** (phase 1) |
| f6 | control: `need_nn(List.fold_left(pos, 0, fn (acc, x) -> acc - x))` (step breaks it) | skip, `unreflectable-subject` | **skip**, `accumulator-step-unproved`, witness `acc = 0, x = 1` |
| f7 | control: `need_pos(List.fold_left(pos, 0, fn (acc, x) -> acc + x))` (base fails) | skip, `unreflectable-subject` | **skip**, `accumulator-base-unproved` (`0` does not satisfy `_ > 0`) |
| f8 | control: `need_pos(List.fold_left(pos, 1, fn (acc, x) -> acc + m))`, `m : Int` captured | skip, `unreflectable-subject` | **skip**, `accumulator-step-unproved`, witness `acc = 1, m = -1` |
| f9 | f8 with `m : {Int \| _ > 0}` | skip, `unreflectable-subject` | **proved** (phase 1: a capture is read in place, §4.3) |
| f10 | control: `fn sh(ys, lo) : {Int \| _ >= lo} do List.fold_left(ys, lo, fn (lo, x) -> lo - 1) end` (lambda parameter shadows the demand's `lo`) | **violated**, witness-confirmed: `sh([0], 0) returns -1` | **unchanged**: the rule declines (§4.3), and the existing witness path still reports it |
| f11 | `let s = List.fold_left(nn, 0, fn (acc, x) -> acc + x)` then `need_nn(s)` | skip, `unconstrained-subject` | proved **iff** (a)'s scalar entry reads the `lets` channel the way phase 2's B7 does for containers. Otherwise it stays skip. Not this design's to fix. |
| f12 | `need_nn(List.fold_right(ys, 0, fn (x, a) -> a + 1))` | skip, `unreflectable-subject` | **proved** (phase 1; the accumulator is the *second* parameter) |
| f13 | `need_nn(Enum.fold(ys, 0, fn a -> fn _x -> a + 1))` (curried call) | skip, `unreflectable-subject` | **proved** (phase 1: curried peel, §3.3) |
| f14 | `one_pos(Enum.reduce(pos, fn a -> fn x -> a + x))` (no init) | skip, `parametric-source-unproved` | **proved** (phase 1: existing container path plus the hypothesis; the base is `pos`'s elements) |
| f15 | `need_nn(myfold(ys, 0, fn (a, x) -> a + 1))`, a user-written fold, annotated `(List(a), b, b -> a -> b) : b` | skip, `unreflectable-subject` | **proved** (phase 1; nothing fold-specific about the rule) |
| f16 | `need_nn(Map.fold(m, 0, fn (a, _k, _v) -> a + 1))`, same for `Set.fold`, `Array.fold_left` | skip, `unreflectable-subject` | **proved** (phase 3: the stdlib signatures gain types, §6) |
| f17 | `sum_pos(List.fold_left(pos, [], fn (acc, x) -> Cons(x, acc)))` (container accumulator) | skip, `unreflectable-subject` | **proved** (phase 2: the hypothesis is a `contenv` entry, and `x` needs (a)) |
| f18 | `List.fold_left(ys, 1, fn (acc : {Int \| _ > 0}, x) -> need_pos(acc) + 1)` (annotated accumulator) | skip, `unconstrained-subject` on `need_pos(acc)`. The annotation is **silently neither checked nor assumed.** | phase 4 (option iii, open decision 1): checked as the invariant and assumed in the body |
| f19 | `fn sum_nn(xs : List({Int \| _ >= 0}), acc : {Int \| _ >= 0}) : {Int \| _ >= 0}`, hand-written accumulator recursion | skip, `unreflectable-subject` (postcondition); a `let r = …; r` variant is `solver-undecided` | **unchanged**: out of scope (§7). Filed. |
| f20 | f3 in a `cap verified` module | **error** (`unreflectable-subject`) | accepted |
| f21 | `match List.fold_left(ys, (0, 0), fn (cs, x) -> …) do (c, _) -> need_nn(c)` (tuple accumulator) | skip, `unconstrained-subject` | unchanged (§7) |

Facts the design rests on, each checked on this commit rather than assumed:

- **The step and the base prove on their own.** `fn mul_ok(a : {Int | _ > 0}, x : {Int | _ > 0}) : {Int | _ > 0} do a * x end`
  and `fn st(a : {Int | _ >= 0}, x : Int) : {Int | _ >= 0} do if x > a do x else a end end`
  are both **proved** today. All that is missing is the connection from the
  call to these two judgments.
- **`sources_of` already returns exactly the base and the step for a fold.**
  For `fold_left(xs : List(a), acc : b, f : b -> a -> b) : b` and `v = b`,
  `per_param` (`refine_param.ml:540-567`) gives `Src_bare 1` (the `acc`
  argument) and `Src_cod (2, [])` (the result of `f`). `consumer_only b b` is
  `true` (`refine_param.ml:533-538`), so the negative occurrence in `f`'s
  domain is *accepted as a consumer position*. The machinery already counts
  that occurrence as "handed out, not a source". This design gives that
  classification its consequence.
- **`demand_flow`'s lambda check gives the accumulator no fact.** `lambda_ok`
  (`refine_check.ml:1288-1306`) shadows the lambda's parameters and asks only
  for `lambda_domain_params` (`:786-807`), which admits **one** parameter and
  only the element-source fact. That is why f14 is `parametric-source-unproved`
  today: `pos` (the base) meets the demand, but `a + x` with `a` unconstrained
  does not.
- **A scalar demand on a fold result never reaches a source discharge.**
  `demand_flow` requires the declared return to be a registered container
  (`refine_check.ml:1236`) and answers `Na` otherwise. `check_call`
  (`refine_call.ml:682`) then finds no postcondition for the subject
  (`postcond_of`, `refine_resolve.ml:263-305`, has no `ret` for a bare `b`)
  and records `Unreflectable_subject` (`refine_call.ml:2612-2618`). This is
  (a)'s entry point.
- **P1 already guards an unannotated callback.** `generic_in_inferred`
  (`refine_param.ml:425-458`) rejects a type variable that also occurs in an
  unannotated parameter's inferred type. So `Deque.fold_left(d : Deque(a), acc : b, f) : b`
  (`f` unannotated, `stdlib/deque.march:135`) is *not* parametric in `b`, and
  the rule cannot be fooled by a callback whose type it cannot see. Unannotated
  `Map.fold(m, acc, f)` / `Set.fold` / `Array.fold_left` have no declared `b`
  at all, so they offer nothing.
- **Captures are already checked in place.** `demand_flow` checks a lambda's
  tails in the *caller's* path and scope (`refine_check.ml:1297-1305`), unlike
  `instantiate_abstract` (`:895-960`), which substitutes a lambda body into
  another scope and so must decline any capture.
- **A false return-position fold contract is already caught by execution**
  (f10: `sh([0], 0) returns -1`). The rule only adds a proof route. When it
  fails, control falls through unchanged, so this violation must survive.

---

## 1. Where the invariant comes from: three options

### (i) The caller's demand, as an instantiation of `b`. **Recommended, v1.**

At a call `g(…)` whose result position demands `D` (a precondition
`need_pos(·)`, a return tail, an annotated `let`, an element slot), and where
`D` lands on a type variable `b` of `g`'s declared return, read the demand as
the instantiation `b := {b | D}`. That instantiation type-checks iff every
**source** of `b` meets `D`, and every callback parameter typed `b` may
**assume** `D`. For a fold that is precisely:

- **base**: `D(init)`, which is the `Src_bare` discharge that exists today;
- **step**: `D(acc) ∧ [element facts on x] ⇒ D(body)` for fresh `acc`, `x`,
  which is the `Src_cod` discharge that exists today **plus the hypothesis**.

No new entry point. No definition-side proof. No signature change for any
already-annotated fold. It applies to every parametric function of the
shape, not to a list of "folds" (f15).

### (ii) An abstract refinement on the fold's signature

`fold_left(xs : List(a), init : b[p], f : (b[p], a) -> b[p]) : b[p]`, with `p`
uninterpreted inside the body and proved once by induction, then instantiated
per call. Rejected for v1, on four counts:

1. **It needs a definition-side mechanism that does not exist.** The body's
   recursive tail `fold_left(t, f(acc, h), f)` must use the function's own
   *scalar* return as an induction hypothesis. Tier 2's self-call hypothesis
   is for ADT returns only (`post_induction_shape`, `refine_post.ml:901-919`
   requires an ADT base), and f19 shows a scalar accumulator recursion is
   `unreflectable-subject` today.
2. **`p` here has no definer.** Abstract refinements are *defined* by a
   callback codomain `{Bool | _ == p(x)}` (design 2026-09-20 §1 rule 3). A fold
   has no predicate callback. `p` would have to be instantiated from the
   *demand*, which is option (i) with extra steps.
3. **A scalar `b[p]` is out of the abstract-refinement scope** (§6 of that
   design: "`p` over a type variable that is not an element").
4. **It buys nothing (i) does not.** The definition-side proof that (ii) would
   do once is, for a parametric `g`, a free theorem: it holds for every body
   that P1 and P2 admit. §2 makes that precise.

**What Liquid Haskell does, and why the simpler form is sound here.** LH's
`foldr` with an abstract refinement is the **indexed** (inductive) form:

```haskell
{-@ foldr :: forall a b <p :: L a -> b -> Prop>.
      (xs:_ -> x:_ -> b<p xs> -> b<p (C x xs)>) -> b<p N> -> ys:L a -> b<p ys> @-}
```

There `p` relates the accumulator to the *list consumed so far*, and the step
is passed that list explicitly. It is needed for facts like `size xs == llen xs`,
which no fixed invariant expresses (the LH slides say exactly this of `add`:
the property "holds only after the last iteration"). The **non-indexed**
invariant this design implements is not an abstract refinement in LH at all.
It is ordinary refinement polymorphism: Liquid inference instantiates `b`
with `{v:b | I}`, and soundness is the soundness of instantiating a type
variable at a refined type. March's P1/P2 gates are what make "the type
variable is really generic" true, since a March signature's type variables
are not rigid (element-flow design §1). Indexed invariants (`_ == len(xs)`
for a counter) need a step that receives the prefix, and March's folds do not
pass one. Out of scope, filed (§7).

### (iii) An explicit annotation on the accumulator parameter

`fn (acc : {Int | _ > 0}, x) -> …` states `I` directly. It is the only option
that yields a **fact without a demand**: a `let`-bound result used twice, and
`acc`'s refinement assumed *inside* the lambda body (f18). Today that
annotation is silently inert: not checked at the pass site (the callee's
domain `b` is unrefined, so `pass_site_obligation` is `None`) and not assumed
(`visit_lambda ~assume:false` strips it, `refine_check.ml:2296-2310`). That is
a small hole of its own: a user who writes it believes something is checked.

**Recommendation:** (i) as v1 (phases 1-3). (iii) as phase 4, built on the
same judgment with `I` read from the annotation instead of the demand. Whether
to ship (iii) at all is open decision 1.

---

## 2. The judgment

### 2.1 Statement

Let `g` be a callee with declared signature `σ`, and `b` one of `σ`'s type
variables with **P1** (`generic_in_inferred`) and **P2** (`parametric_safe`)
holding, no bound on `b`, and `sources_of σ b = Some srcs`
(`refine_param.ml:540`). Let the call's result position demand `D` on `b`
(scalar `Refined (β, D, sort)` or `Container (c, slots)`), with `D` already in
the **caller's** namespace (the demanding callee's actuals substituted, as
`check_call` does).

The call meets the demand if, for every `s ∈ srcs`:

- `Src_bare i`: the actual at `i` meets `D` (unchanged);
- `Src_elem (i, path)`: the actual's elements at `path` meet `D` (unchanged);
- `Src_cod (i, path)`: the callable passed at `i` returns values meeting `D`
  **when each of its parameters whose declared domain is exactly `b` is
  assumed to meet `D`**. This is the *invariant hypothesis*, the one new
  rule. Its other parameters keep whatever facts they had (none, or (a)'s
  element-domain facts).

For a fold, the first source is the **base** and the second is the **step**.
For `reduce(xs : List(a), f : a -> a -> a) : Option(a)` with the demand on
`a`, the base is `Src_elem 0` (every element of `xs`) and the step assumes `D`
on *both* parameters. There is no init, and the first element is just another
source.

### 2.2 Soundness: why a negative occurrence is fine here

The abstract-refinements design treats `p` in a *parameter's* element slot as
an **obligation on the caller** (§3.5 there). The occurrence here is the other
polarity of the other party. From the caller's side, `b` in `f`'s domain is a
value `g` **hands to** the caller's lambda: an assumption the lambda may make,
whose obligation falls on `g`. The argument that `g` meets it:

> **Claim.** If `g` is parametric in `b` (P1, P2, no bound, `sources_of ≠ None`),
> every non-callback source of `b` meets `D`, and every callback with codomain
> `b` maps `D`-satisfying `b`-arguments to `D`-satisfying results, then every
> value of type `b` that `g` ever holds, and in particular its result, meets `D`.
>
> **Proof sketch (induction on evaluation).** Order the `b`-values `g` holds by
> when they come into existence. By P1/P2 and `sources_of`, a `b`-value can
> come into existence inside `g` only (1) as an argument at a `Src_bare` /
> `Src_elem` position, or (2) as the result of applying a `Src_cod` callback.
> `g`'s body cannot synthesise one: P2 excludes creating builtins, FFI and
> `impl` methods that return a type variable, and P1 excludes a body that
> fixed `b` to a concrete type. Case (1) meets `D` by hypothesis. In case (2),
> every `b`-argument the callback receives is a value `g` already held, so by
> the induction hypothesis it meets `D`, and the callback's contract gives a
> `D` result. ∎

This is the free theorem for `∀b`, specialised to the subset relation
`{b | D}`. Equivalently, `g` type-checks at the instance `b := {b | D}`. That
is the standard justification for refinement polymorphism, and why LH needs
no abstract refinement for a non-indexed invariant.

Three corollaries the builder must not "optimise" away:

- **All sources, or nothing.** The hypothesis is justified only by the
  conjunction. A proved step with an unproved base proves nothing (f7).
- **Only parameters whose declared domain is *exactly* `b`.** A `List(b)`
  domain (`f : List(b) -> b`) is also sound by the same argument, but it needs
  an element-entry hypothesis rather than a scalar one. v1 declines it.
  Anything under a domain's own domain is already refused by `consumer_only`.
- **Simultaneous variables.** When a demand pairs several variables (`b ↦ D₁`,
  `c ↦ D₂`), each callback parameter typed `b` assumes `D₁` and each typed `c`
  assumes `D₂`, at once. The joint instantiation justifies it, but only if
  *every* source of *every* paired variable is discharged, which
  `demand_flow` already requires (`refine_check.ml:1366-1377`).

### 2.3 What the rule does not claim

Nothing about **how many times** or **in what order** the step runs: zero
times is the base case. This is why `fold_left`, `fold_right`, a hash-order
`Map.fold` and a sorted `SortedSet.fold` are all the same case and no
traversal order is modelled. Nothing **indexed** (`_ == len(xs)`). Nothing
about values `g` produces that are *not* its result.

---

## 3. Call sites: where the obligations hook in

### 3.1 Entry points (none new)

| Demand reaches the call through | Path today | Change |
|---|---|---|
| container demand on a container return (`one_pos(Enum.reduce(…))`, f14) | `check_elements` → `demand_flow` (`refine_check.ml:1227`) | hypothesis in `lambda_ok` (§3.2) |
| scalar demand on a bare-`b` return, argument position (`need_nn(fold_left(…))`) | `check_call` → `postcond_of = None` → `Unreflectable_subject` (`refine_call.ml:2612`) | **(a)'s** scalar entry, which calls the same `discharge` |
| scalar demand at a return tail (f4, f5) | `check_post` (`refine_post.ml:282`) on the tail | (a)'s scalar entry must be reached from here as well as from `check_call`. Flag this to (a); if (a) covers only arguments, phase 1 adds the tail hook. |
| container demand on a bare-`b` return (f17) | `demand_flow` answers `Na` (`:1236`), since the return is not a `TyCon` | phase 2: let the bare-`TyVar` return pair the whole demand with `b` (`pairs := [(b, Container …)]`) |

Layering: `check_call` lives in `refine_call.ml`, below `refine_check.ml`
where `demand_flow` lives. (a)'s entry point is reached from `check_call`
through a forward reference, the same pattern as `post_lookup`
(`refine_post.ml:250-258`). If (a) slips, phase 1 adds that ref
(`scalar_demand_hook : (… -> [ `Na | `Proved | `Unproved of reason ]) ref`,
set by `Refine_check` at module init) and calls it in `check_call` just before
the `Unreflectable_subject` arm. On `Na` the existing skip is recorded
unchanged.

### 3.2 The hypothesis: `invariant_params`

A new helper in `refine_check.ml`, next to `lambda_domain_params` (`:786`):

```ocaml
(* Callback parameters a Src_cod discharge may assume the demand on (design
   2026-10-18 §2): the lambda's parameter at each arrow-chain position whose
   declared domain is exactly a demanded type variable.  [pairs] is
   demand_flow's (variable, demand) list.  [Error why] declines (§4.3). *)
val invariant_params :
  sg:fn_sig -> i:int -> pairs:(string * elem) list -> A.param list
  -> (A.param list * (string * elem) list, string) result
```

It returns the parameters with each hypothesised one put back with the
demand: a scalar `D` becomes `param_ty = Some {T | D[β := name]}` via
`ty_of_refined` (`refine_param.ml:575`). A container `D` (phase 2) becomes a
`cont_add_param` entry. `lambda_ok` (`refine_check.ml:1288`) then:

1. calls `lambda_domain_params` (or (a)'s multi-parameter successor) for the
   element facts on the non-`b` parameters;
2. calls `invariant_params` and **overlays** its parameters, which are
   disjoint by construction: a parameter is typed `b` or `a`, never both;
3. proceeds as today. `scope_add_param` makes each hypothesis an assumption
   for every tail.

The named-callable arm of `Src_cod` (`refine_check.ml:1343-1350`) is
unchanged. A named step function proves only through its own proved
**closed** return, as today. Reading a named step's parameter refinement as
the invariant is a phase-4 refinement at most (my call: not v1).

### 3.3 Curried lambdas

`Enum.fold`/`Enum.reduce` call `f(acc)(x)` (`stdlib/enum.march:105-107`), and
the typechecker requires `fn a -> fn x -> …` there (probed: a two-parameter
lambda is `callback_arity_mismatch`). `List.fold_left` declares the *same*
type `b -> a -> b` but calls `f(acc, h)`, and takes `fn (acc, x) -> …`. The
discharge must not care which. `lambda_ok` **peels** nested `ELam`s whose
total parameter count equals the arrow chain's length (`arrow_chain`,
`refine_param.ml:522`), maps parameters to positions in order, and checks the
innermost body's tails. A mismatch in count declines (`U`, as today).

### 3.4 Verdicts and reasons (`--refine-report`)

Two new `Obligation.reason`s (`obligation.ml:111-131`, names at `:301-304`,
detail at `:342-347`, and every exhaustive match on reasons:
`refine_call.ml:857-900`, `Refine_audit`, the LSP code-action classifier).
Filed by `demand_flow` (and (a)'s entry) **only when the hypothesis was used**:

| Slug | When | Detail (rendered) |
|---|---|---|
| `accumulator-base-unproved` | a `Src_bare` / `Src_elem` source of a variable that some `Src_cod` callback also *consumes* (an accumulator) is not proved to meet `D` | "the initial value `0` (argument 2 of `List.fold_left`) does not satisfy `_ > 0`" |
| `accumulator-step-unproved` | the `Src_cod` discharge with the hypothesis is not proved | "`fn (acc, x) -> acc - x` can break `_ >= 0`: `acc = 0, x = 1` gives `-1`", or, for a decline, its reason (§4.3) |

A variable no callback consumes keeps `parametric-source-unproved`
(`List.map`'s demand, unchanged). Both new reasons are classified like
`Parametric_source_unproved` (reported per site, escalated under `cap verified`).
A `Solver_undecided` sub-result stays `solver-undecided`.

### 3.5 Refuted is skip, not violation: yes, and more firmly

Decision 9.2 of the abstract design applies, for two independent reasons:

1. **Data dependence** (as there). A failing base on `fold_left(xs, 0, …)`
   demanded `> 0` can still be right whenever `xs` is non-empty and the step
   makes it positive. A failing step is harmless on `[]`.
2. **The method is incomplete.** A true property need not be inductive:
   `fold_left(ys, 0, fn (a, _) -> a + 1)` never returns `-1`, but the step
   `a != -1 ⇒ a + 1 != -1` is refuted at `a = -2`. A refuted step is a fact
   about the *invariant candidate*, never about the program.

So both new reasons are skips with a witness in the detail. No promotion
through `confirm_precond_reachable`. The **existing** witness machinery is
untouched, and it still reports a genuine, execution-confirmed violation of a
return contract (f10). The rule returns `U` and the obligation falls through
to exactly today's path.

---

## 4. Soundness table and guards

| New assumption | Justified by | Guarded by (each gets a RED control test) |
|---|---|---|
| a callback parameter typed `b` meets `D` | §2.2's induction / free theorem | P1 `generic_in_inferred`, P2 `parametric_safe`, no `fn_bounds` on `b` (`parametric_ok`, `refine_param.ml:463-471`); `sources_of ≠ None`; **every** source discharged |
| the call's result meets `D` | same, concluded | same; recorded `Proved` only when all sources are `P` |
| captured names in the step mean what they mean at the call | March bindings are immutable, and the closure is created at the call | lambda checked in the caller's scope (`lambda_ok`'s existing shadowing); the shadowing guard below |
| the hypothesis names the lambda's parameter, not a caller name | substitution of `D`'s binder only | **decline** when a lambda parameter's name is free in `D` (f10: `fn (lo, x)` against `_ >= lo`) |
| every tail of the step is checked | `tails` (`refine_post.ml:78-116`) enumerates the return positions | **decline** when the step body contains `let?` / `let*` (`ELetQ` / `ELetStar`): `tails` does not enumerate their early-exit tail (my call: decline, not extend `tails`, in v1) |
| the curried peel maps parameters to positions | arrow-chain order | total parameter count must equal the chain length |

### 4.1 Effects and early exit

A step that panics, loops or does IO produces no result: partial correctness,
the stance of every postcondition here. A step that *receives* a `b` from an
actor or a decoder is fine. That value is a tail of the lambda, so it must
meet `D`, and it does not (step unproved). P2 constrains the callee `g`, not
the caller's lambda. Mutable cells holding a `b` exist only behind builtins,
FFI or actors, and P2 taints those in `g`.

### 4.2 Integer model

`acc * x > 0` from `acc > 0 ∧ x > 0` is true over SMT `Int` and false under
63-bit wraparound. The checker already proves `mul_ok` on this model today,
so this design adds no new exposure. It is mentioned so that nobody reads a
new one into it. Nonlinear steps run on CI's z3 4.8.12: f1's test must pin
the verdict that CI actually returns, `proved` or `nonlinear-goal`. Probe both
z3 versions before writing the assertion (phase 2).

### 4.3 What the step may capture

Anything in scope (f8 vs f9). This is the deliberate contrast with
`instantiate_abstract`'s capture-free decline (`refine_check.ml:938-941`),
which exists because a `q` there is substituted into *another* function's
query. Here the step is discharged where it is written.

---

## 5. Definition side

None, for (i). The stdlib needs **no `@[assume]`** and **no proof** for any
fold: the guarantee is parametricity, which the gates check. This is the main
practical advantage over (ii). What the stdlib does need is for each fold to
**expose `b`** in its declared signature, with P1/P2 holding.

---

## 6. Which stdlib folds get it

Surveyed on `ba8db5805`. "Gets it" means P1 and P2 hold and `sources_of` sees
the base and the step. Verify each in phase 3 with a probe; don't take this
table's word for it.

| Fold | Signature today | Gets it | Change |
|---|---|---|---|
| `List.fold_left` (`list.march:447`), `Prelude` copy (`prelude.march:126`) | `(List(a), b, b -> a -> b) : b` | phase 1 | none |
| `List.fold_right` (`list.march:455`) | `(List(a), b, a -> b -> b) : b`; body is `reverse` + `fold_left` + a wrapper lambda, all P2-safe | phase 1 | none |
| `Enum.fold` (`enum.march:100`), `Iterable.fold` (`iterable.march:93`) | `(List(a), b, b -> a -> b) : b`, curried call | phase 1 (§3.3) | none |
| `Enum.reduce` (`enum.march:120`) | `(List(a), a -> a -> a) : Option(a)` | phase 1 (container path) | none |
| `Range.reduce` (`range.march:116`) | `(record, b, b -> Int -> b) : b` | phase 1 | none |
| `SortedSet.fold` (`sorted_set.march:268`), `OrderedMap.fold` (`ordered_map.march:293`, `b -> k -> v -> b`) | annotated | phase 1, if P2 holds for `tree_fold` | probe |
| `Map.fold` (`map.march:595`), `Set.fold` (`set.march:610`), `HashMap.fold` (`hash_map.march:465`) | **unannotated** `(m, acc, f)` | phase 3 | annotate `(m : Map(k, v), acc : b, f : b -> k -> v -> b) : b` (and `Set(a)` / `HashMap(k, v)`); P2 through `node_fold` |
| `Array.fold_left` (`array.march:536`) | unannotated | phase 3 | annotate; P2 through `trie_fold` |
| `RRB.fold` / `fold_left` (`rrb_vec.march:179`, `:293`) | `f` unannotated | phase 3 | annotate `f : b -> a -> b` |
| `Deque.fold_left` / `fold_right` (`deque.march:135`, `:140`) | `f` unannotated, so **P1 rejects `b`** (§0) | phase 3 | annotate `f` |
| `NativeArray.fold_int` & co (`native_array.march:154`, …) | body is one builtin (`native_int_arr_fold`) | **no**, expected: a creating builtin taints P2 | none. Stays skip, documented (my call: no `@[assume]`; a parametricity fact has no runtime witness worth the name) |
| `Seq.fold` / `fold_while` (`seq.march:202`, `:212`) | church-encoded: `b` flows through a closure stored in data | **no**: `sources_of` cannot see it | none, documented |
| `List.sum_int`, `product_int`, `Enum.sum`/`product`, `Stats.sum` | monomorphic local `go` recursion | **no**: nothing parametric. It is f19's gap (§7) | none |
| String folds | none exist in `stdlib/` | — | — |

Each annotation is the kind of change memory flags as dangerous. A wrong
arrow shape (`(b, a) -> b` instead of `b -> a -> b`) type-checks a stdlib file
into an internal error that only the compiler suite's stdlib ratchet reports.
So phase 3 runs `scripts/run-tests.sh compiler` after every signature edit,
not just `--check`.

---

## 7. Scope

In scope: a demand on a type variable of a parametric callee's return, met
by its sources, with callback parameters typed exactly that variable assuming
the demand. Scalar demands (phase 1), container demands and container
accumulators (phase 2), curried and uncurried callbacks, any arity.

Out of scope. Each is filed at phase 2 as a `specs/todos/` entry, so that
nobody reads a guarantee into its absence:

- **Indexed invariants** (`_ == len(xs)`, LH's `<p :: L a -> b -> Prop>`):
  the step would need the consumed prefix.
- **Hand-written accumulator recursion** (f19): a *scalar* self-call induction
  hypothesis on the definition side. It is a Tier 2 extension in
  `refine_post.ml`, unrelated to callers. Probed: `unreflectable-subject`, and
  `solver-undecided` with a `let`.
- **Tuple and record accumulators** (f21): the demand lands on a component
  after a `match`, not on `b`.
- **A `List(b)` callback domain** (§2.2, second corollary).
- **The accumulator's fact inside the lambda body without a demand**: phase 4,
  option (iii).
- **`impl`/`interface` dispatch**, unchecked generally.
- **Inferring** an invariant when no demand exists: never.

---

## 8. Phases, one PR each

Conventions as in the element-flow and abstract plans. Every step keeps
`test_refinecheck.exe` green. Every new rule lands with a fixture that goes
RED without it. Assert ledger triples, not exit codes. Use `--root .` and
have z3 on PATH. CI runs z3 4.8.12 and local is 4.16.

**Phase 1: the hypothesis (scalar and the existing container path).**
`invariant_params`, the curried peel, the two reasons, the guards (§4).
Plus, if (a) has not landed, the minimal scalar entry and its `check_call` /
`check_post` hooks (§3.1).
Tests, `test_refinecheck` group `fold-invariant`, all written first and seen RED:
- proves: f3, f4, f5, f9, f12, f13, f14, f15, f20 (`cap verified` accepts f3);
- control skips, each with its reason and detail asserted: f6 (step), f7
  (base), f8 (capture), a `let?` step (decline);
- f10 stays **violated** with today's witness text (the fall-through pin);
- **perturbation**: with `invariant_params` returning no parameters, exactly
  the proved rows go red. With the shadowing guard removed, f10's *obligation*
  turns proved, so the test catches the unsoundness. With P1 forced true, a
  fixture with an unannotated `f` turns proved, and must not;
- a callee with `b` inside `Task(b)` declines (`sources_of = None`).
Conformance pair `specs/lang/types/accept/t325_fold_invariant.march` (f3, f4,
f14 under `cap verified`) and `reject/t326_fold_invariant_step.march` (f6
under `cap verified`). Use whatever numbers are next at the time.
Oracle: `scripts/refine-oracle.sh check` against main. Every changed line is
a `skipped → proved` on a fold call, or the reason rename
`parametric-source-unproved → accumulator-*`, explained line by line.
**No `violated` count moves.** Full sweep (`stdlib`, `test/native`,
`test/stdlib`, conduit + depot): a new fact can expose a latent violation
elsewhere, and any such case is investigated, not baselined.

**Phase 2: element facts on the step, and container accumulators.** Needs
(a)'s multi-parameter domain facts. f1, f2 (pin the CI z3 verdict, §4.2),
f17. A bare-`TyVar` return pairs a container demand (§3.1, last row). A
container hypothesis enters as a `contenv` entry. Close the accumulator half
of follow-ups item 2. Drop the `fold_left` bullet from the multi-arg todo.
File §7's todos.

**Phase 3: stdlib signatures.** §6's annotations, one commit per module, each
followed by the compiler suite (§6's warning). Each module gets a probe row
(f16) in `fold-invariant` and is listed in the progress note with its P1/P2
verdict. `NativeArray`/`Seq` controls stay skip. Audit baselines regenerate
only if an annotation adds a contract site. It should add none, since the
annotations are unrefined types.

**Phase 4 (open decision 1): the annotated accumulator.** `I` read from a
lambda parameter's own refinement at a `b`-typed position. The base and the
step are the same two discharges with `I` for `D`. On success, (1) the lambda
body is walked `~assume:true` for that parameter, and (2) the call's result
gets the fact `I`, through a per-lambda-span table that `postcond_of`
consults (a pure lookup filled at visit time, because `postcond_of` must stay
solver-free). On failure, the annotation's obligation is recorded with the
`accumulator-*` reason and **not** assumed. This also makes f18's inert
annotation enforced, so `refine_audit` must count it.

**Docs at each phase.** In `specs/lang/refinement-types.md`, add a subsection
"### Folds: an accumulator invariant" after "Abstract refinements" (the
judgment in user terms, the f3/f6/f7 trio, "refuted is a skip, never a
violation", the stdlib list). Edit "What element refinements do not do": drop
"the result of `fold_left`" from the scalar bullet when (a)/phase 1 land, and
replace the "`fold_left`'s two-parameter callback" bullet in phase 2. Rewrite
the abstract-refinements "One argument only" bullet so it no longer names the
fold. Then run `scripts/gen-lang-docs.py` and commit `docs/refinement-types.md`
with it (doc-lint Check F). Add a CHANGELOG `### Added` bullet per phase.
Each phase adds a `specs/progress/` note, plus the `git mv` / todo edits named
above.

---

## 9. Performance

The hypothesis adds assumptions to queries that already run. It adds no query.
The new cost is that calls which used to stop at `Na` / `Unreflectable_subject`
now run their source discharges: one query for the base, one per step tail.
That cost falls only at a fold call *with a demand* (106 fold-call lines in
`stdlib/` in total, few with a demand). Budget: cold
`--check --stdlib-source stdlib/list.march` within 110% of main. Measure it
under a private `HOME`, with `.march/cas/vc` cleared once, interleaved A/B,
median of 5, and record the load average. The CI skip ceiling on
`stdlib/list.march` (42) must not rise. The VC cache key is the full query
text (verified for abstract phase 2), and the hypothesis is in that text, so
two folds with different demands cannot share a verdict. One test pins that
anyway: the same lambda under `_ >= 0` and then `_ > 0`, where the second
must not inherit the first's proof.

---

## 10. Decisions

Settled by the author of this design (marked so they can be overturned in review):

1. **(i) is v1; (ii) is rejected** (§1). The guarantee comes from
   parametricity, so no fold gets a proof or an `@[assume]`.
2. **Refuted base or step is a skip, never a violation** (§3.5), with two new
   reasons rather than reusing `parametric-source-unproved`. The user needs to
   know *which half* failed.
3. **Shadowing and early-exit steps decline** rather than rename or extend
   `tails` (§4).
4. **A named step function contributes only its closed return**, as today.
5. **`NativeArray` and `Seq` folds stay skip**, documented. No `@[assume]`.

Open, for the user:

1. **Ship phase 4 (the annotated accumulator, option iii)?** Recommendation:
   yes, after phases 1-3, as its own PR. It is the only way to get a fact on a
   let-bound fold result with no demand, and today the annotation is silently
   inert (f18).
2. **Wait for sibling (a), or absorb its scalar entry point into phase 1?**
   Recommendation: wait. Absorb it only if (a) has not landed by the time
   phase 1 is ready, and then hand it back to (a) to extend.
3. **Annotate the unannotated stdlib folds (`Map`/`Set`/`HashMap.fold`,
   `Array.fold_left`, `RRB`, `Deque`) in phase 3?** This is a public-signature
   change, though no behaviour changes. Recommendation: yes, one module per
   commit, each followed by the compiler suite.

---

## Decisions settled by the user (2026-10-18)

1. **Phase 4 (the annotated accumulator) ships**, as its own PR after phases 1-3.
2. **Wait for the element-flow design's scalar entry point** (its phase 2); absorb it into phase 1 only if that has not landed when phase 1 is ready.
3. **Phase 3 changes the public signatures** of the unannotated stdlib folds, one module per commit, each followed by the compiler suite.
