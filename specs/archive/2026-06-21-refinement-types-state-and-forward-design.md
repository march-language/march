# Refinement Types — State of Implementation & Forward Design

**Date:** 2026-06-21
**Status:** Draft (supersedes the forward-looking portions of `2026-06-20-dependent-types-refinements-design.md`)

## Why this spec

The original design (`2026-06-20-dependent-types-refinements-design.md`) proposed refinement types `{T | predicate}` discharged by Z3, integrated into the bidirectional typechecker. We then *built* a working slice and learned things the paper design could not anticipate — most importantly an architectural ceiling that reframes the roadmap. This spec takes stock of what exists, records the key findings, and charts the forward path. It is written to be read on its own.

---

## 1. What exists today (on `main`, except increment 2a as noted)

Refinement checking is implemented and shipping as **two cooperating libraries plus a thin type-system hook**:

### `lib/refine/` — the SMT bridge (Phase A0)
A standalone, AST-free Z3 bridge: an `Smt` term language (Int/Bool linear arithmetic + EUF), an SMT-LIB2 renderer, a long-lived `z3 -in` driver (one process per compilation, `push`/`pop` per query), a `(get-model)` s-expression parser, and a BLAKE3-keyed verdict cache under `.march/cas/vc/`. `Refine.discharge` ties cache → solver → outcome (`Verified` / `Refuted` model / `Unverified`). Graceful when `z3` is absent. 14 unit tests.

### `lib/refinecheck/` — the checker (Phases A1, A2, path sensitivity, postconditions)
A **post-typecheck pass over the AST** that does the actual reasoning:
- **Preconditions** — at each call to a function with `{Int | p}` parameters, reflect the actual argument into SMT and discharge `p`.
- **The `len` measure + bounds** — `len(xs)` is the length of a list literal (static) or a symbolic non-negative constant; **cross-argument** predicates resolve sibling parameters (`{Int | _ >= 0 && _ < len(xs)}`).
- **Path sensitivity** — `if`/`when`/`match` guards become assumptions (then-branch gets the condition, else its negation); variable arguments are reflected as stable constants so a guard about `i` discharges a precondition about `i`.
- **Postconditions** — each return-position (tail) expression of a function with a refined return type is checked against the predicate, under the path/scope reaching it.

### Surface syntax & the type carry (`ast.ml`, `parser.mly`, `typecheck.ml`, `lower.ml`)
- `{T | p}` and `{v : T | p}` parse to `Ast.TyRefine` (moved into `expr`'s recursive group so the predicate is an ordinary expression; `_` is a legal expression atom for the refinement value). 11 exhaustive `Ast.ty` matches erase it to the base where appropriate; the formatter renders the predicate faithfully.
- `TRefine of ty * string * Ast.expr` lives in the **internal** typechecker type (increment 1, merged). It is **transparent to unification**: `repr` strips it to the base, so inference, `occurs`, `generalize`, `instantiate`, exhaustiveness, and TIR lowering are unchanged. A follow-up (increment 2a, *committed on branch, not yet merged*) makes `generalize`/`instantiate` preserve the wrapper so the predicate survives into schemes and back out at instantiation.

### Stdlib adoption
Two genuine consumers: `List.chunks(xs, size : {Int | _ > 0})` (size ≤ 0 never terminates) and `Decimal.div(.., precision : {Int | _ >= 0})`.

### Test surface
23 tests in `test/test_refinecheck.ml` (5 preconditions + 6 bounds + 5 path-sensitivity + 7 postconditions) + 14 in `test/test_refine.ml`. Full project suite green.

---

## 2. The soundness model — *definite-failure discharge*

This is the load-bearing design decision that makes everything else viable, and it deserves to be stated plainly because it is not in the original spec.

A naïve checker reports a violation when it cannot *prove* a precondition holds. That produces false positives on every argument whose value isn't statically known — which is almost all of them — making the checker unusable on real code.

Instead, the checker reports a violation **only when the predicate can never hold** under the known assumptions:

```
discharge(goal=G)          Verified  =>  G always holds            => pass, silent
otherwise discharge(¬G)    Verified  =>  G can never hold          => REPORT violation
otherwise (depends / unknown)        =>  unprovable either way     => skip, silent
```

Consequences:
- **No false positives.** An unconstrained or symbolic value (`at(ys, i)` with unknown `len(ys)`) is skipped, not flagged.
- It catches **definite** violations: literal out-of-bounds, a guard that contradicts the precondition, a branch that always returns a violating value.
- It is **incomplete** by construction — it misses violations that merely *might* occur. That is the correct trade for a checker that must run on every build without annoying anyone.

This is why the checker can run across the **entire stdlib** (all 57 modules, every `--check`/`--compile`) and produce **zero false positives**, while still catching real violations (`List.chunks(xs, 0)`).

---

## 3. The key architectural finding

The original spec assumed refinements would integrate into the typechecker and that this would, among other things, deliver **higher-order** checking (a refined function passed to `map`, a refined value flowing through a polymorphic boundary). Implementing the type carry (`TRefine` in the internal type) revealed why that does not follow.

**To keep the type integration tractable, `repr` must strip `TRefine`.** That is what kept the blast radius to 8 match sites instead of 35: nearly everything canonicalises through `repr`, so making `repr` transparent makes refinements invisible to unification, `occurs`, generalization, and so on. Without that, every one of ~35 sites would need bespoke refinement handling.

**But the same transparency defeats higher-order checking.** Consider `apply(take_n, -3)` with `apply(f, x) = f(x)` and `take_n : {Int | _ >= 0} -> Int`:

1. The argument `take_n` forces unification of `apply`'s parameter `a -> b` with `{Int|_>=0} -> Int`.
2. Unification `repr`s both sides → **strips the refinement** → `a := Int`.
3. `apply`'s `x` parameter is now plain `Int`; `-3` is a valid `Int`; **no obligation is emitted.** The refinement never crossed the higher-order boundary.

The conclusion is structural, not a bug:

> **A refinement survives only where it is *not unified* — i.e., on a function's own declared parameters, read at *direct* call sites.** Transparent-`repr` `TRefine` therefore cannot express higher-order or polymorphic refinement flow.

And direct-call-with-own-parameters is *exactly* what the separate `refinecheck` pass already covers — and it covers it **with path sensitivity**, which `typecheck.ml` has no machinery for. So a type-based `infer_app` emission (the planned "increment 2b") would be **strictly worse** than the separate pass: it would lose path sensitivity and still not add higher-order checking.

**Corollary.** True higher-order/polymorphic refinement checking requires refinements to *participate in unification* — refinement **subtyping**, `{T | p} <: {T | q}` discharged as a real obligation during unification, not stripped. That is a fundamentally larger change (the original spec's §"Refinements in the Type System" gestured at a directional check but did not confront unification). It is the real fork in the road.

---

## 4. What the as-built checker does well, and its limits

**Strengths (keep these):**
- Direct-call preconditions and postconditions, sound (definite-failure), false-positive-free at stdlib scale.
- Path sensitivity — the single most practically important feature, since real defensive code is guarded.
- The `len` measure + cross-argument bounds — the genuine array-safety win.
- Cleanly isolated (`lib/refinecheck`), no surgery on the HM core, fast to iterate.

**Limits (the honest list):**
1. **No higher-order / indirect / interface-dispatch checking** (§3).
2. **Name-based call resolution** — the pass matches callees by bare/qualified name and can collide across modules; it does not use the typechecker's resolved binding.
3. **No inductive reasoning** — a recursive function's result is an unconstrained symbol, so most "always non-negative" stdlib functions (`length`, counts) cannot be *proved*; clean stdlib consumers are consequently rare.
4. **Int/Bool only** — `Float` value-refinements are deferred (IEEE-754-as-`Real` is unsound; the FP theory is heavy).
5. **Fixed builtin measures** — no user-defined measures yet.
6. **Two artifacts** — the AST pass and the (currently unused-for-checking) type carry are separate; the type carry's `generalize`/`instantiate` preservation is foundation for a consumer that, per §3, should *not* be the planned 2b.

---

## 5. Forward design

There are two coherent directions. They are not mutually exclusive, but they have very different cost and reward.

### Path 1 — Deepen the separate pass (incremental, low-risk)
Harvest the remaining value the current architecture *can* deliver:

- **P1a — Robust call resolution.** Replace name-matching with the typechecker's resolved callee identity (thread the type map / a callee→refinement table keyed by binding, not string). Removes the bare-name-collision foot-gun and makes cross-module checking reliable. *Small.*
- **P1b — User-defined measures.** An `@measure` annotation on a pure, structurally-recursive, total function, axiomatised into the SMT preamble (the original spec §Measures, deferred). Unlocks domain invariants (`balance`, `depth`, `size`). *Medium.*
- **P1c — `assume`/lemma escape hatch.** Surface-level `assume(p)` (already designed in the original spec) plus simple user lemmas to bridge the inductive-reasoning gap (e.g. assert `length(xs) >= 0` once). *Small–medium.*
- **P1d — Diagnostics.** Carry counterexample models through more paths; show the failing guard/branch. *Small.*

Path 1 keeps the definite-failure soundness stance and the false-positive-free property throughout.

### Path 2 — Refinement subtyping in unification (the principled core)
The only route to higher-order/polymorphic checking, postconditions-checked-in-the-type, and a *single* checker with full context (types **and** path). The shape:

- `unify` (or a dedicated `subtype`) treats `{T | p}` and `{T | q}` by unifying bases **and emitting an implication obligation** `path ∧ p ⟹ q`, instead of stripping. Refinements then flow through application, polymorphic instantiation, and data.
- This requires: a path/assumption context threaded through `infer_expr`/`check_expr` (March does not have one today); a decision on *where* refinements are checked vs. merely propagated (bidirectional localisation); and careful interaction with generalization (a refined scheme), linear types, and error recovery.
- It subsumes the separate pass: preconditions, postconditions, bounds, **and** higher-order all fall out of one mechanism — but it is a deep change to the 7,400-line core with a real correctness and performance burden.

This is the change the original spec under-scoped. It should not be attempted as an "increment"; it is its own project with its own spec, prototype, and metatheory check (March already has a Lean mechanization track — see `specs/lean4-metatheory-plan.md` — which is the right place to validate refinement-subtyping soundness before committing the OCaml).

### The `TRefine`-in-type foundation (increments 1 + 2a)
Increment 1 (carry, merged) is harmless and a genuine asset for Path 2 — the constructor, `repr` transparency, and the 8 handled sites are exactly the scaffolding refinement subtyping needs. Increment 2a (preserve through generalize/instantiate, committed on branch, **not merged**) is preservation for a consumer that, per §3, should be the Path-2 subtyping check, not the discarded 2b. **Recommendation: merge 2a as dormant foundation** (it is behavior-preserving and on the Path-2 critical path) *or* leave it on the branch until Path 2 begins. Either is fine; do **not** build the transparent-`repr` `infer_app` consumer (2b).

---

## 6. Recommendation

1. **Ship and stabilise the separate pass** as the production refinement checker. It is sound, useful, hardened, and false-positive-free.
2. **Pursue Path 1** for near-term value, in order: **P1a (robust call resolution)** → **P1b (user measures)** → **P1c (assume/lemmas)**. These are independent, low-risk, and each enables more real-world annotations.
3. **Treat Path 2 (refinement subtyping) as a separate future project** with its own spec and a Lean soundness check first. Keep increments 1 (+ optionally 2a) on `main` as its foundation.
4. **Do not implement type-based `infer_app` precondition emission** (the discarded 2b) — it regresses path sensitivity without adding higher-order checking.

This sequencing maximises delivered correctness value per unit of risk and defers the one genuinely large, genuinely principled change until it is scoped and validated on its own terms.

---

## 7. Scope, soundness, testing

- **Soundness:** every phase preserves *definite-failure* discharge — report only when a predicate can never hold — so the checker stays false-positive-free and safe to run on every build. Path 2 changes this contract (it *proves* obligations) and therefore needs the metatheory check before landing.
- **Out of scope (unchanged):** Float value-refinements; quantifiers / nonlinear arithmetic / induction in user predicates; termination/totality checking; indexed families / GADTs / propositional equality (the original spec's "Phase B", still further out).
- **Testing:** keep the gated (z3-present) `test/test_refinecheck.ml` model — pure translation tests always run; solver-dependent assertions skip cleanly without `z3`. Add a stdlib-wide "zero false positives" regression for Path 1 changes. Path 2 needs property-based tests against the Lean spec.

## 8. Consultation sites (current code)

| Area | Location |
|------|----------|
| SMT bridge | `lib/refine/{smt,model,solver,vc_cache,refine}.ml` |
| The checker (preconditions, bounds, path, postconditions) | `lib/refinecheck/refine_check.ml` |
| Pass invocation | `bin/main.ml` (after `check_module_full`) |
| Surface syntax | `lib/ast/ast.ml` (`TyRefine`), `lib/parser/parser.mly` (`{T \| p}`, `_` atom) |
| Internal type carry | `lib/typecheck/typecheck.ml` (`TRefine`, `repr`, `surface_ty`, `generalize`/`instantiate`) |
| Erasure to TIR | `lib/tir/lower.ml` (`convert_ty`) |
| Stdlib consumers | `stdlib/list.march` (`chunks`), `stdlib/decimal.march` (`div`) |
| Original design | `specs/2026-06-20-dependent-types-refinements-design.md` |
