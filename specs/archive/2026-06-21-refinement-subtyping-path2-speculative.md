# Refinement Subtyping in Unification — Path 2 (SPECULATIVE)

**Date:** 2026-06-21
**Status:** 🔬 **SPECULATIVE — not approved, not scheduled, not costed beyond rough order-of-magnitude.** This document explores a *possible* future direction. Nothing here should be built without a separate approval, a prototype, and a Lean soundness check first (see §7). Treat every design choice below as a hypothesis, not a decision.

> **Why this exists.** The shipped refinement checker (`lib/refinecheck`, a sound post-typecheck pass — see `2026-06-21-refinement-types-state-and-forward-design.md`) has one structural ceiling: it cannot check **higher-order / polymorphic** refinement flow, because the transparent-`repr` `TRefine` design strips refinements during unification. This document sketches the only known route past that ceiling — making refinements *participate* in unification as a **subtyping** relation. It is written so a future implementer (or a future us) can decide whether the prize is worth the cost. The honest current answer is "probably not yet."

---

## 1. The one-paragraph idea

Today `unify(a, {Int | p})` calls `repr` on both sides, strips the refinement, and binds `a := Int` — the predicate is lost. Path 2 replaces stripping with a **directional subtyping check**: when a value of type `{T | p}` is required to have type `{T | q}`, unify the bases **and emit an obligation** `assumptions ∧ p ⟹ q` to the SMT backend, instead of discarding `p`. Once refinements survive unification, they flow through function application, polymorphic instantiation, data structures, and interface dispatch — so `apply(take_n, -3)` (the canonical higher-order failure) becomes checkable, and a function's body can be verified against a refined *return* type structurally. One mechanism subsumes preconditions, postconditions, bounds, and higher-order checking.

This is the design the original `2026-06-20` spec gestured at ("directional discharge in `check_expr`") but did **not** confront at the level of unification. Confronting it is the whole job.

---

## 2. Why this is hard (the parts the paper design skipped)

These are the load-bearing difficulties. Each is a research-grade subproblem in March's specific setting.

### 2.1 March has no path/assumption context in the typechecker
The shipped checker's single most valuable feature — **path sensitivity** (a guard `if i < len(xs)` becomes an assumption) — lives in the separate AST pass, which threads a path context. `typecheck.ml` has **none**. A subtyping obligation `p ⟹ q` is nearly useless without the surrounding assumptions (`i >= 0` from a guard, `n != 0` from an `assert`). So Path 2 must **add an assumption context threaded through `infer_expr`/`check_expr`** — a pervasive change to a 7,400-line bidirectional checker, touching every binder, branch, and match. This is arguably bigger than the subtyping mechanism itself.

### 2.2 Where to *check* vs. merely *propagate*
Bidirectional typing localises obligations to the *checking* direction. But unification is called from both directions and from contexts with no expected type. Naively emitting an obligation at every `unify` site would produce false positives (unifying two unconstrained vars, inferring an intermediate type) and a storm of trivial/unknown VCs. The design must decide precisely **which unification sites are subtyping boundaries** (function argument vs. parameter, return value vs. declared return, value vs. refined `let`/field) and which are mere propagation. Getting this wrong yields either unsoundness (missed checks) or unusability (false positives) — the exact failure mode the shipped checker avoided with its definite-failure stance.

### 2.3 The soundness contract flips
The shipped checker reports a violation only when a predicate can **never** hold (definite-failure) — incomplete but false-positive-free, which is what lets it run on every build. A subtyping check **proves** obligations (`p ⟹ q` must be *valid*), so an *un*proven obligation is a candidate error. That re-introduces exactly the false-positive risk on every value whose facts aren't statically known. Path 2 needs a deliberate answer: graded checking (`--strict` proves, default stays definite-failure?), or universal `assume`/lemma ergonomics good enough that "unproven ⇒ error" is tolerable. Unresolved, this sinks usability.

### 2.4 Interaction with generalization, linearity, and error recovery
- **Generalization:** a refined type can be generalized (`fn id_pos(x : {Int|_>0}) -> {Int|_>0}`). The scheme must carry the predicate (increments 1+2a already do the carrying), and instantiation must rename predicate variables consistently with the type. Subtyping between *schemes* is its own subtlety.
- **Linear/affine types:** obligations must not duplicate or drop linear resources; a predicate mentioning a linear value is delicate.
- **Error recovery / typed holes:** March continues after errors with `TError`/holes. Subtyping obligations involving error types must degrade to "skip", not crash or cascade.

### 2.5 Performance
Refinements participating in unification means SMT queries inside the inner inference loop. Whole-program monomorphization re-checks specialisations. The CAS VC cache (already built, A0) helps, but query *volume* could explode. Needs measurement on a real codebase before committing.

---

## 3. A *possible* shape (hypothesis, not a plan)

If pursued, the least-bad decomposition we can currently imagine:

- **S0 — Assumption context.** Thread an `assumptions : pred list` through `infer_expr`/`check_expr`, populated by `if`/`when`/`match`/`assert`/refined-`let`. No obligations emitted yet; purely additive; regression-green. *This alone is a large change and a useful prerequisite even if S1+ never happen.*
- **S1 — Subtyping at checking boundaries.** Define `subtype env ~assumptions {T|p} {T|q}`: unify bases, emit `assumptions ∧ p ⟹ q` via the A0 bridge. Call it **only** at the identified checking boundaries (§2.2), not from `unify` generally. Reuse the predicate→SMT translation (extracted to a shared lib — the layering decision from the state spec).
- **S2 — Higher-order & polymorphic flow.** Function-type subtyping (contravariant params, covariant result); refinement-preserving instantiation. This is where `apply(take_n, -3)` starts working — and where the hard cases live.
- **S3 — Retire/merge the separate pass.** Once S1–S2 cover preconditions/postconditions/bounds *with* the S0 assumptions, the AST pass becomes redundant; fold its remaining unique value (e.g. measure handling) into the type-driven path and delete the duplication.

Each step is individually large. S0 and S1 might be worth it on their own (a single, path-sensitive, type-integrated checker) even if S2 (true higher-order) proves too costly.

---

## 4. What it would buy

- **Higher-order / indirect / interface-dispatch checking** — the capability the separate pass structurally cannot have.
- **Postconditions checked in the type**, uniformly with preconditions, instead of a bespoke tail-walk.
- **One checker** with full context (types + path), instead of two artifacts that must be kept from double-reporting.
- A foundation that **generalises toward Phase B** (indexed families, propositional equality) far more naturally than a side-pass.

---

## 5. What it would cost / risk (honest)

- A pervasive change to the core typechecker (§2.1, §2.2) — the single most complex and most-depended-on file in the compiler.
- A flipped soundness contract (§2.3) that could regress usability if the ergonomics aren't solved.
- Real performance risk (§2.5).
- Multi-month, multi-prototype effort with a genuine chance of being abandoned mid-way if S2 proves intractable.
- Opportunity cost: the shipped checker already delivers most of the *practical* value (preconditions, bounds, path sensitivity, postconditions) at a fraction of the risk.

**Rough order of magnitude:** S0 alone is comparable to a major typechecker feature; S0–S3 together is a quarter-scale project, not an increment. This estimate is itself speculative.

---

## 6. Decision criteria (when, if ever, to start)

Pursue Path 2 only if **all** of these hold:
1. Real users hit the higher-order limit often enough to matter (evidence, not speculation).
2. The shipped separate-pass checker has been pushed through Path 1 (measures, robust resolution) and *still* leaves a gap that demonstrably needs the type integration.
3. There is appetite for a quarter-scale core-compiler project with abandonment risk.
4. The soundness/usability contract (§2.3) has a credible answer on paper.

Until then, the recommendation in the state-of-implementation spec stands: **ship the separate pass, pursue Path 1, keep increments 1(+2a) as dormant foundation, and do not build the discarded transparent-`repr` `infer_app` consumer.**

---

## 7. Mandatory before any OCaml: metatheory first

March already has a Lean 4 mechanization track (`specs/lean4-metatheory-plan.md`, `2026-04-14-lean4-fbip-mechanization.md`). Refinement subtyping is precisely the kind of change whose soundness is easy to get subtly wrong (the §2.2 boundary choice; variance in §2.4). **Any serious Path 2 effort must begin by formalising the subtyping judgment and its soundness (progress/preservation with the refinement obligations) in Lean, and only then port the validated rules to OCaml.** A prototype that typechecks examples is *not* evidence of soundness here.

---

## 8. Relationship to existing specs

- Supersedes nothing — it is purely forward-looking and explicitly speculative.
- Builds on the carrying foundation from `2026-06-21-refinement-types-state-and-forward-design.md` (increments 1 + 2a) and the A0 SMT bridge.
- Phase B (indexed families / GADTs / propositional equality) from `2026-06-20-dependent-types-refinements-design.md` sits *beyond* even this; Path 2 is a prerequisite for doing Phase B in the type rather than as another side-pass.

*Reminder: this is a sketch of a road not (yet) taken. No part of it is committed.*
