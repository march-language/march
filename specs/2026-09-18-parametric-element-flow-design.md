# Design: element refinements through expressions, callbacks, and polymorphic combinators

**Date:** 2026-09-18
**Status:** landed 2026-09-18 (progress notes `specs/progress/2026-09-18-refine-*`; deviations recorded there). Plan: `specs/plans/2026-09-18-parametric-element-flow-plan.md`.
**Builds on:** container subtyping (`specs/progress/2026-09-13-container-subtyping.md`,
`-container-subtyping-other-containers.md`), arrow-position refinements
(`specs/progress/2026-09-13-arrow-position-refinements.md`), and the P3 designs
(`specs/2026-09-13-refinement-p3-designs.md` §1, §2).

Element refinements (`List({Int | _ > 0})`) are enforced for literals, for
variables that carry a declared element refinement, and through `match` binders.
They stop at the first **expression** that is neither of those, which in practice
means at almost every call. This design widens element flow in three steps and
fixes a soundness hole in the rule that already ships.

---

## 0. Where things stand (probed 2026-09-18, compiler built Sep 16 from this worktree)

Each row is a scratch program run with `--check --refine-report-sites`.

| # | Shape | Today | Wanted |
|---|---|---|---|
| a | `sum_pos([1, -2, 3])` | **violation** at `-2` | same |
| b | `Cons(h, t) -> need_pos(h)` on a refined `xs` | proved | same |
| c | `let ys = List.reverse(xs)` then `sum_pos(ys)` | proved | same |
| d | `sum_pos(List.reverse(xs))` | skip, `unreflectable-subject` | proved (Phase 1) |
| e | `match List.head_opt(xs) do Some(h) -> need_pos(h)` | skip, `unconstrained-subject` | proved (Phase 1) |
| f | `fn r(xs) : List({…}) do let ys = List.reverse(xs); ys end` | skip on the return | proved (Phase 1) |
| g | `sum_pos(single(xs))`, where `single`'s declared return is `List({Int \| _ > 0})` | skip | proved (Phase 1) |
| h | `need_pos(f(x))`, `f : (Int) -> {Int \| _ > 0}` | proved | same |
| i | `Cons(f(h), …)` as an element of a refined return | skip ("`f(h)` could not be translated") | proved (Phase 2) |
| j | `map_pos(t, f)` (self-call) as the tail of a refined return | skip | proved (Phase 2) |
| k | lambda `fn y -> y - 1` passed where `(Int) -> {Int \| _ > 0}` is expected | skip, `solver-undecided` | **violation**, witness `y = 1` (Phase 2) |
| l | `sum_pos(List.map(ys, fn y -> y * y + 1))` | skip | proved (Phase 3) — *landed as a skip: an argument using non-linear `*` is never translated; see the Phase 3 progress note* |
| m | `sum_pos(List.map(pos, fn y -> y * 2))`, `pos` refined `> 0` | skip | proved (Phase 3) |
| n | `sum_pos(List.filter(ys, fn y -> y > 0))`, `ys` unrefined | skip | **still skip** (needs abstract refinements; out of scope) |
| z | `fn bad(xs : List(a)) : List(a) do [0 - 5] end`, then `let ys = bad(pos)` and `sum_pos(ys)` | **proved** (false proof) | skip (Phase 0) |

Row **z** is a live soundness bug in the shipped §2c rule; see §1.

---

## 1. Phase 0: the parametric rule must not trust the declared type variables

### The bug

`Refine_check.parametric_return` (§2c of the P3 designs) reads the callee's
**declared** signature and reasons from parametricity: a function of type
`List(a) -> List(a)` cannot make an `a`, so its result's elements came from its
argument and keep that argument's element refinement.

March does not make annotation type variables rigid. `a` in a signature is an
ordinary unification variable, so

```march
fn bad(xs : List(a)) : List(a) do [0 - 5] end
```

typechecks, with `a` silently fixed to `Int`. Calling `bad(["x"])` is then a type
error (`expected String but got Int`), which confirms the specialization. But
`parametric_return` sees `List(a) -> List(a)` and gives `bad(pos)` the element
refinement `_ > 0`: the probe reports **1 proved** for `sum_pos(ys)` on a list
that holds `-5`. Under `cap verified` ("if it compiles, it is proved"), that
proof is false.

### The fix: two soundness preconditions, checked per callee and per type variable

A type variable `v` in callee `g`'s declared signature may be used by the
parametric rule (the existing §2c or the new Phase 3) only if both of these hold:

**(P1) `v` is really generic in `g`'s inferred type.** The driver already passes
`Refine_check.check_module` the typechecker's `type_map` (span → type), and the
typechecker records every parameter binder's type at its name span
(`lib/typecheck/typecheck.ml`, the `Hashtbl.replace env.type_map name.span t`
sites). For each parameter whose declared type mentions `v`, take the recorded
type, `repr` it, and walk it alongside the declared type. Each position that
reads `v` in the declaration must resolve to an **unbound type variable**, and
distinct declared variables must resolve to **distinct** unbound variables.
`fn f(xs : List(a), ys : List(b)) : List(b) do xs end` unifies `a` with `b`, so
it fails distinctness. With no recorded type (a unit-test fixture with no table,
a builtin, an extern), the answer is no. That costs a proof, never soundness.
`if_arm_admitted` already makes the same trade.

Step 0.1 of the plan has to confirm that `type_map` holds the binder types after
generalization and survives the driver's cached path (`bin/main.ml`, the
`cached_tm` merge). If it doesn't, the fallback is a small `fn_generic_vars`
table exported by the typechecker, keyed by declaration span.

**(P2) `g`'s body cannot create a `v`.** Parametricity holds only for code
that is itself parametric. Three things break it:

- **Externs and builtins** (FFI, or a runtime primitive whose scheme has a
  result variable absent from its parameters: a decoder, an untyped receive, a
  cast). A callee that *is* one of these fails P2.
- **Interface bounds on `v`** (`fn_bounds`, or a `where` constraint). An
  interface method can return a `v` (a `Default`-style constructor). A callee
  with any bound on `v` fails P2.
- **Transitive creation.** `g` calls something that creates a `v` for it. The
  rule: `parametric_safe g` holds when `g` has a body, has no bound on the
  variable, and every function it calls either (i) has a declared return type
  that mentions no type variable (it can't return a `v`), or (ii) is itself
  `parametric_safe`, or (iii) is a **diverging** builtin (`panic`, `todo`,
  `exit`: their `a` result never exists). Anything else taints `g`. This is
  computed once per module as a greatest fixpoint over the call graph, using
  the `calls_of` walker `gate_unverified_posts` already has.

The list of creating builtins is **computed** from the typechecker's own
builtin table (`Typecheck_builtins.builtin_bindings` and
`builtin_interface_bindings`): every builtin whose scheme's result mentions a
type variable its parameters don't, except the diverging ones. (An earlier
draft planned a hand-maintained list with a drift-guard test, on the belief
that refinecheck does not depend on `march_typecheck`. It does, so there is
nothing to drift.)

### What this changes

Row z becomes a skip. Every legitimate stdlib use of the rule (`reverse`,
`head`, `head_opt`, `first`, `take`, `drop`, `filter`, …) still passes. The CI
skip ceiling and `--refine-report` counts for `stdlib/list.march` must not move.
If they do, one of the conditions is too strict and the plan says which knob to
check.

### A language question this does not answer

Whether annotated type variables should be rigid is a typechecker decision
(OCaml makes them flexible; most users read `a` as "any type"). It's filed as
its own todo (`specs/todos/2026-09-18-typecheck-annotated-tyvars-flexible.md`).
P1 makes the refinement checker correct either way, and stays harmless if the
language later makes the variables rigid.

---

## 2. Phase 1: element facts through expressions

### 2.1 One question, asked in one place

Today, "what container entry does this value carry?" is answered separately at
four sites, and each answers it only for `EVar`:

- `check_elements`' variable arm (the obligation side);
- `parametric_return`'s `safe` / `slot_of_var` (actuals must be `EVar`s in `contenv`);
- `EMatch`'s element facts (the scrutinee must be an `EVar`);
- the `let` walker's §2c arm (the RHS must be a direct `EApp` of a name).

Phase 1 introduces one function and routes all four through it:

```
container_entry_of_expr ctx defs cb ce (e : A.expr) : (string * elem option list) option
```

| `e` | Entry |
|---|---|
| `EVar x` | `List.assoc_opt x ce` (today's behaviour) |
| `EAnnot (e', _, _)` | recurse on `e'` |
| `EApp (EVar g, args)` | (1) `parametric_return` with actuals resolved **recursively** through this function, so `reverse(reverse(xs))` and `take(reverse(xs), 2)` work; otherwise (2) `g`'s **declared** return, when `elem_refinement g.ret_ty` is `Some` and `g`'s element return is **proved** (§2.2) |
| anything else | `None` |

`parametric_return`'s `safe` changes only where an actual is read: "the actual
is an `EVar` in `ce`" becomes "`container_entry_of_expr` returns an entry of the
same container". P1/P2 from Phase 0 are checked before any of this.

### 2.2 Proved element returns

A function with a container-typed return (`: List({Int | p})`) has every tail
checked by `check_elements` at its definition (`visit_fn`, the
`elem_refinement fd.A.fn_ret_ty` block). Nothing records the verdict, so no
caller can rely on it, which is why row g is a skip. We add:

- `elem_ret_proved : (string, unit) Hashtbl.t`, keyed like `defs`, holding
  each function whose tails' element obligations were **all** proved. A
  skipped tail means the function isn't in the table. This mirrors
  `gate_unverified_posts`: only proved contracts become facts.
- It's computed in the same round structure as `gate_unverified_posts` (a
  monotone fixpoint: a function whose tail calls a not-yet-proved function is
  retried once that function proves). Recursion is Phase 2's job (§3.2). Until
  then a self-call tail stays a skip, so a recursive function simply isn't in
  the table.
- `check_elements` is called with `~emit:false` in the gating rounds, as
  `check_fn_post_verdict ~emit:false` is, so diagnostics aren't doubled.

### 2.3 Return tails see the block's facts

`visit_fn` checks container-return tails with the environment built from the
**parameters only** (`tails base c.A.fc_body` over `sc`/`ce` from
`fc_params`), so a tail naming a `let`-bound local (row f) is a skip. We move
the tail check into `visit`: `rctx` gains
`ret_elem : (string * (string * elem option list)) option` (callee label plus
demanded entry), set by `visit_fn` for a container return. `visit`'s tail
positions (the last statement of an `EBlock`, both `EIf` arms, every `EMatch`
arm) run `check_elements` with the environment **at that point**.
`visit_lambda`, `visit_local_fn` and actor handlers reset `ret_elem` to their
own (or `None`). The old pre-walk block is removed, so each tail is checked
exactly once. A ledger-count test pins that.

The same move gives a local `fn` with a container return its tail checks. It
has none today.

### 2.4 Match on a call

`EMatch (subj, …)` with a non-variable `subj` takes
`container_entry_of_expr subj` for the element facts. Binders get facts. The
tag-narrowing and record-identity channels stay variable-only, since they need
a stable name and element facts don't.

### Tests (group `element-flow`)

REJECT, one per new obligation route: `sum_pos(bad_decl(xs))`, where
`bad_decl`'s declared element return is refuted, still skips (unproved, so no
entry). A literal tail `[0]` under a `let` in a refined-return function is
reported at the tail.

ACCEPT with a control, one per new assumption: rows d, e, f, g each prove, and
each has an unrefined-source control that must **skip**, not prove.

Soundness pins: row z skips; `f(xs : List(a), ys : List(b)) : List(b) do xs end`
skips (distinctness); a callee that calls a listed manufacturing builtin skips.

---

## 3. Phase 2: callback results and self-calls as element sources

### 3.1 `check_elements` sees the callback environment (row i)

`check_elements` builds its `cx` with `postcond_of ctx defs`, without `~cb`, so
the scalar route that proves `need_pos(f(x))` (row h) is missing when the same
call sits in an element position. Thread `cb` through `check_elements`,
`check_arg_elements` and `check_field_elements` (all four callers already have
it in scope) and pass `postcond_of ~cb`.

### 3.2 A self-call as an element source (row j)

`Cons(f(h), map_pos(t, f))` needs `map_pos(t, f)`'s own element return. That is
an induction hypothesis, and it follows the house rule Tier 2 already uses:

- only for a call to the function's **own** name;
- only when the argument at the matched parameter is in
  `structural_subvars param body` (`refine_encode.ml`);
- only while checking that same function's tails (a scoped
  `current_elem_ret_hyp`, set and restored like `enclosing_fn`).

The function then enters `elem_ret_proved` if all its tails prove under that
hypothesis. Mutual recursion gets no hypothesis, as in Tier 2.

(Partial correctness alone would justify assuming the hypothesis for *any*
self-call, since a call that never returns yields no element. We still follow
Tier 2's structural restriction: one rule for both, with the relaxation
decided once, for both, elsewhere.)

### 3.3 Container-typed codomains at the pass site

`f : (Int) -> List({Int | p})` is a callback whose *result* carries an element
refinement. `check_pass_sites` handles only a `TyRefine` codomain, so nothing
obliges the passed callable to meet this one, and the result can't be assumed.
Add the element counterpart:

- **Obligation:** an inline lambda's tails are checked with `check_elements`
  against `elem_refinement cod`. A named callable must be in `elem_ret_proved`,
  with its entry implying the expected one slot by slot (the existing
  `Element_domain` implication). Anything else is a recorded skip.
- **Assumption:** `callback_sig_of_ty` records `ret_ty = Some cod`, and
  `container_entry_of_expr`'s declared-return arm accepts a `cbenv` callee
  whose codomain has an element refinement. That's sound because every pass
  of it was just obliged.

### 3.4 An inline lambda's codomain violation is reported (row k)

`check_pass_sites` verifies an inline lambda against a refined codomain with
`check_fn_post_verdict` on a synthesized `local_fn_def`. A refuted return
refinement is reported only when `Witness.confirm_post` **executes** the
failing input, and `confirm_post` looks the function up by name in the module
environment. A lambda has no name, so it's never confirmed, and row k
degrades to `solver-undecided`.

Add `Witness.confirm_lambda_post ~lam ~params ~ret_pred ~model`:

- decline (return `None`, today's behaviour) unless `free_vars lam` names only
  module-level functions. A lambda that captures a local has no closed meaning
  to run;
- evaluate the `ELam` in `module_env ()` to a closure value, decode the model
  for its parameters (`decode_model`), apply it under the same fuel, wall
  budget and effect veto as `call_fn`, and check the predicate with
  `violates_post`;
- shrink as `confirm_post` does.

Why a confirmed failure is a real violation here: the lambda's parameters range
over the expected **domain**, the domain the pass site already obliged, so any
input the solver found is one the higher-order function may pass. That's the
`Callback_domain` stance, now backed by execution the way a top-level
postcondition is.

### Tests (group `callback-elements`)

Row i proves `map_pos`, and its caller `sum_pos(map_pos(ys, fn y -> y * y + 1))`
proves. Control: the same function with an unrefined callback codomain skips.

Row j: the structural self-call proves. Control: `map_pos(xs, f)` (not a
component) gets no hypothesis and skips.

Row k: reported, with witness `1` (or the shrunk equivalent). Control: a
capturing lambda `fn y -> y - k` stays a skip (declined, not guessed).

§3.3: a lambda returning `[0]` where `(Int) -> List({Int | _ > 0})` is expected
is reported. A named callable with a proved element return passes, and one
without is a recorded skip.

---

## 4. Phase 3: demand-driven instantiation (the `map` rule)

### 4.1 The judgment

At an element obligation (`check_elements`, and therefore arguments, returns,
annotated `let`s and record fields), suppose the expression is a call
`g(args)` whose `container_entry_of_expr` is `None`. Suppose also that `g`'s
declared return has the demanded container at its head. Match the return type
against the demanded entry to get, for each type variable `b` at a demanded
slot, the **demand** `D(b)`, which is a refinement or a nested entry.

The call satisfies the demand if **every source of every demanded variable
satisfies it**. By parametricity (P1 and P2 from Phase 0 are required for
every demanded `b`), each `b` value in `g`'s result came from some source.

### 4.2 Sources: a polarity walk over the parameter types

`sources_of g v` walks each declared parameter type, tracking polarity
(parameter position is where values *enter* `g`; each arrow domain flips
polarity). It classifies every **positive** occurrence of `v`:

| Occurrence | Source | Obligation for demand `D` |
|---|---|---|
| bare parameter `x : v` | `Bare i` | the actual is checked against `D` as a scalar precondition (`check_call`) |
| `v` in a registered container parameter, any depth | `Elem (i, slot path)` | `check_elements` of the actual against the entry with `D` at that path |
| arrow parameter codomain `f : … -> v` | `Codomain (i, [])` | pass-site codomain obligation against `D` (§3.3 / §3.4 machinery) |
| arrow parameter codomain containing `v` in a container (`f : a -> List(b)`, `a -> Option(b)`) | `Codomain (i, path)` | same, against the codomain type with `D` substituted at `path` |

**Negative** occurrences (for example `v` in an arrow parameter's *domain*) are
not sources: `g` supplies those values to the caller's function and doesn't
receive them. If any positive occurrence can't be classified (inside an
unregistered type constructor such as `Task(v)` or `Chan(v)`, in a tuple, or
under a second arrow level), `sources_of` returns `None` and the rule gives up
with a recorded skip. **At least one source is required**: a `v` with no source
is vacuous by parametricity, but that vacuity is exactly what an unlisted
creating builtin would exploit, so we don't lean on it.

This polarity analysis replaces §2c's `safe`, which is stricter than necessary:
it rejects any occurrence outside a direct container argument, so today
`sort_by(xs, cmp)` doesn't keep `xs`'s refinement, because of `cmp : a -> a -> Bool`'s
negative occurrences. It also can't use a bare source (`put(xs, v)`), which
the new rule discharges by checking `v` against the demand. The §2c
**assumption** direction (flowing an entry *out* of a call with no demand, as
in `let ys = reverse(xs)`) becomes "every source is an `Elem` whose actual has
an entry, and the slot is the one they agree on". It's the same logic, with no
demand to check against.

### 4.3 Verdicts

- Every source **proved** → the element obligation is proved (one ledger
  entry at the call; sources are sub-steps, not separate obligations).
- Any source **skipped** → recorded skip, with reason
  `parametric-source-unproved` naming the source.
- A source **refuted** → recorded skip with the same reason, plus a hint
  carrying the witness (for example "`fn y -> y - 1` returns `0` for `y = 1`").
  **Not** a violation. Unlike §3.4's declared codomain, the demand here was
  never written by the user, and whether the refuted source ever runs depends
  on the caller's data (`List.map([], …)` is fine). This is the stance
  `take_pos(k)` gets for an unknown `k`. `cap verified` escalates it like any
  skip. Promoting it to a violation when the source is reached for certain
  (a literal non-empty container) is future work for the existing
  demonstrated-precondition promotion path (`confirm_precond_reachable`).

### 4.4 Domain facts for inline lambdas (row m)

When an inline lambda is passed at an arrow parameter whose domain is a type
variable `a`, and every source of `a` is an `Elem` whose actual carries the
**same** refinement `q` at that slot, the lambda is walked with its parameter
assuming `q` (`visit_lambda ~assume:true` with the parameter's type replaced
by `{base | q}`). The same fact is available when checking the lambda's body
against a codomain demand. Soundness: every `a` value `g` can hand the lambda
came from a source, and every source satisfies `q`. With sources that
disagree, nothing is assumed.

### 4.5 Scope

In scope: one-parameter callbacks (`map`, `flat_map`, `filter_map`,
`Option.map`, `Result.map`, …), bare and container sources, a container demand.

Out of scope, each named in the todo so nobody reads a guarantee into its
absence:

- **Curried or multi-parameter callbacks** (`fold_left`'s `b -> a -> b`).
  The pass-site machinery is single-parameter throughout. `fold` is also the
  case where a *negative* occurrence of `b` would carry the demand as an
  invariant (the accumulator), which is attractive but a separate soundness
  argument.
- **A scalar demand on a bare-variable return** (`need_pos(Option.unwrap_or(o, 1))`).
  That comes through `check_call`, not `check_elements`. It's the same
  judgment, a different entry point, and a follow-up.
- **`filter` producing a refinement it didn't receive** (row n). The fact
  "the predicate returned true" can't be stated without abstract refinements.
  That's the next design, not this one.

### Tests (group `demand-flow`)

- Rows l and m prove. `List.flat_map` and `List.filter_map` with lambdas
  returning refined literals prove. `Option.map` / `Result.map` into refined
  `Option`/`Result` demands prove.
- `put(xs, 0 - 1)`-shaped bare source against the demand: a skip with the
  witness hint, and **not** a violation (pins §4.3).
- `sort_by(pos, cmp)` into `sum_pos` now proves (the polarity walk). The
  control with a callee that has an interface bound on `a` skips (P2).
- A callee with `v` inside `Task(v)` skips (`sources_of = None`).
- Every §2c fixture in `container-subtyping-2` stays green unchanged. They're
  the regression set for replacing `safe`.

---

## 5. Soundness summary

| New assumption | Justified by | Guarded by |
|---|---|---|
| a call's element entry via parametric flow | parametricity | P1 (generic in the inferred type), P2 (parametric body), ≥1 source, every source proved |
| a call's element entry via declared return | the definition's tails were all proved | `elem_ret_proved` fixpoint |
| self-call's element return inside its own definition | induction on structure | `structural_subvars`, own name only |
| a callback's container codomain | every pass site obliged it | §3.3 obligation first, same PR |
| an inline lambda's parameter fact | parametricity: every `a` came from a source with `q` | single agreed `q`, P1/P2 |
| a lambda codomain **violation** | executed witness in the obliged domain | `confirm_lambda_post`, declines on capture |

Every row above has a REJECT or SKIP control in the tests, because an
accept-only witness can't tell a working rule from one that checks nothing
(`specs/lang/refinement-types.md`, "Conformance status").

## 6. Performance

Phase 1 adds no solver queries, only more obligations that now translate.
Phase 3 adds one query per source per demanded call, and sources are few
(`map` has one). The budget: cold `--check` of `stdlib/list.march` stays within
10% of the pre-change time (0.39 s on 2026-09-16), measured under a private
`HOME` with `.march/cas/vc` cleared once before the run.
