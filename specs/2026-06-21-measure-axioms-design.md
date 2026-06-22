# Measure Axioms — Quantified Recursion-Equation Encoding (P1b follow-up)

**Date:** 2026-06-21
**Status:** Draft design (planned follow-up, not yet scheduled). Concrete and intended-to-build, unlike the speculative Path 2 — but with a **hard soundness gate** (§4) that must be in place before any axiom is emitted.

## 1. Motivation

Today a `@[measure]` reflects **symbolically**: `size(t)` becomes an uninterpreted constant `size$t`, optionally constrained `>= 0` when the body is syntactically non-negative (the shipped P1b + non-negativity inference). The solver knows *nothing else* about `size` — not that `size(Node(l,x,r)) = 1 + size(l) + size(r)`, not that `size(Leaf) = 0`. So anything needing the measure's **defining equations** is unprovable and conservatively skipped:

- `len(append(xs, ys)) == len(xs) + len(ys)` — the canonical example from the original design, currently impossible.
- `insert(t, x)` returning `{Tree | size(_) == size(t) + 1}` — postconditions that *relate* a measure across an operation.
- `size(Node(a, x, b)) > 0` — structural lower bounds.

This spec adds the measure's recursion equations to the SMT context as **universally-quantified axioms**, so the solver can reason about measure *values structurally*, not just symbolically.

## 2. What it unlocks (concretely)

Given
```march
@[measure] fn len2(xs : List(a)) : Int do
  match xs do Nil -> 0  Cons(_, t) -> 1 + len2(t) end
end
```
the encoding asserts
```smt
(declare-datatypes ((Lst 0)) (((nil) (cons (hd Elem) (tl Lst)))))
(declare-fun len2 (Lst) Int)
(assert (= (len2 nil) 0))
(assert (forall ((h Elem) (t Lst)) (! (= (len2 (cons h t)) (+ 1 (len2 t))) :pattern ((len2 (cons h t))))))
```
which makes `len2(Cons(a, Cons(b, Nil))) = 2`, `len2(Cons(h, t)) = len2(t) + 1`, and (with an append axiom or a recursive proof) `len2(append xs ys) = len2 xs + len2 ys` provable.

## 3. The encoding

### 3.1 Model the algebraic datatype
Z3 supports algebraic datatypes natively (`declare-datatypes`), giving constructors, selectors, and testers. For each ADT referenced by an axiomatised measure, emit a `declare-datatypes` derived from the March `type` declaration.

**Polymorphism.** March ADTs are parametric (`Tree(a)`, `List(a)`). Element types are irrelevant to a measure like `size`/`len`, so encode the parameter as a single **uninterpreted element sort** `Elem` (one per parameter position is overkill for v1; a single opaque `Elem` suffices for length/size/depth measures that never inspect elements). Measures that *do* inspect elements are out of v1 scope (§6).

### 3.2 Declare the measure
`(declare-fun <m> (<DT>) Int)` (or `Bool`). One uninterpreted function per measure.

### 3.3 Generate the recursion-equation axioms
The measure body is required to be `match <arg> do <Constructor(vars) -> body>* end` (§4). For each arm:
```
(assert (forall (<vars typed by the constructor's field sorts>)
          (! (= (<m> (<ctor> <vars>)) <⟦body⟧>)
             :pattern ((<m> (<ctor> <vars>))))))
```
- `⟦body⟧` translates the arm body to SMT: integer/bool literals, `+ - *`(linear), comparisons, **recursive calls** `m(sub)` → `(<m> sub)`, calls to **other axiomatised measures**, `let`, nested `if`/`match` on the *same fragment*. (This is a strictly larger source fragment than the predicate fragment — it must handle recursion, `match`, and `let`.)
- The non-recursive base arm (`Nil -> 0`) yields a ground equation (no quantifier).
- The `:pattern` (trigger) is the LHS measure-application, so Z3 instantiates the axiom exactly when a `(<m> (<ctor> …))` term appears — keeping instantiation targeted and predictable.

### 3.4 Preamble assembly, ordering, caching
- All datatype declarations first, then measure `declare-fun`s, then axioms (so forward references resolve; mutually-recursive measures get all decls before any axiom).
- The full preamble (datatypes + measure decls + axioms) is part of the **BLAKE3 VC cache key** (already the A0 design), so it's computed once per unique VC across builds.
- Only emit declarations/axioms for measures *actually referenced* by the VC's predicate, to keep queries small.

## 4. The hard soundness gate (non-negotiable)

**A recursion-equation axiom is sound only if the measure is a total, terminating function.** If a measure is non-terminating or partial, its "equations" are unsatisfiable as a definition and the axiom set becomes **inconsistent** — from which the solver can prove *anything*, including false preconditions. That is silent unsoundness, the worst failure mode.

Therefore, before axiomatising, `@[measure]` functions **must** be verified:
1. **Structurally recursive / terminating** — every recursive call is on a structurally-smaller component of the matched argument. March already computes structural-recursion information in `lib/typecheck/typecheck.ml` (it currently emits a *warning*; for `@[measure]` it must become a hard **error** if not structurally recursive).
2. **Total** — the `match` is exhaustive (March's exhaustiveness checker), no `panic`/partial paths, no division that can trap.
3. **Pure** — no effects, no actor messaging, no FFI (a measure must be a mathematical function). March can check the body uses only the pure fragment.

A `@[measure]` failing any of these is a **compile error**, not a silently-unaxiomatised measure — because a user who wrote a predicate relying on it deserves to know it can't be trusted. (The shipped symbolic-only measures don't need this gate because they assert no equations; this gate is specific to the axiom encoding.)

**Recommendation:** prototype the encoding's soundness for the structural-recursion case against the Lean metatheory track before trusting it on real code — the gate is exactly the kind of side-condition that's easy to get subtly wrong.

## 5. The hard *engineering* parts

- **Quantifier incompleteness.** Quantified axioms put Z3 into E-matching / MBQI territory: some valid goals return `unknown` or time out. This is *tolerable* because the checker's **definite-failure** stance treats `unknown` as "skip" (no false positives, no unsoundness) — but it means structural facts that *should* prove sometimes won't, unpredictably. Good triggers (§3.3) mitigate but don't eliminate this.
- **Translating the measure-body fragment.** Bigger than the predicate fragment: `match`, `let`, recursion, multiple constructors. Needs its own translator (shared with, but distinct from, `smt_of`).
- **Datatype fidelity.** The `declare-datatypes` must exactly mirror March's constructor arities/recursion; a mismatch is unsound. Generating it from the `type` decl (resolved through modules) is fiddly.
- **Mutual recursion** between measures, and measures over mutually-recursive datatypes.
- **Performance.** Datatype theory + quantifiers raise per-query cost; measure it on a real codebase before enabling by default. Consider gating behind a flag initially.

## 6. Scope

**In scope (v1):** single-argument, structurally-recursive, total, pure measures returning `Int`/`Bool` over a (possibly polymorphic, element-opaque) ADT, body = `match arg` with arithmetic + recursive/other-measure calls + `let`/`if`.

**Out of scope (v1):** measures that inspect element values; multi-argument measures; non-structural recursion (well-founded but not structural); measures over non-ADT types; nonlinear arithmetic in bodies; cross-measure relations that need *induction* the solver can't do by E-matching alone (those may still need a user lemma — the P1c `assert`/assume hatch).

## 7. Phasing

1. ✅ **M-a — quantified recursion-equation axioms (SHIPPED 2026-06-21).** `declare-datatypes` + `declare-fun` + `:pattern`-triggered base/recursive axioms, with a 3s solver timeout (`unknown` → definite-failure skip). The implementation generalised past "lists only" directly to **user ADTs** (the `Tree`/`size` case), element types opaque. Enabled by default but **soundness-gated**: a measure is axiomatised only when its body is `match param do Ctor(vars) -> … end`, the arms cover every constructor, and every recursive call is structural — else it stays symbolic. Scope: direct-match single-arg measures.
2. ✅ **M-b — built-in `List` + the totality/termination/purity gate (SHIPPED 2026-06-21).** (a) The built-in `List(a)` is modelled (`Nil | Cons(a, List(a))`), completing the "lists" target M-a deferred, so user list measures (`length`) axiomatise like user ADTs. Datatype sort names moved to a private `M_` namespace so no ADT name collides with a z3-reserved sort (`List`, `Array`, `Seq`, …). Axiom bodies restricted to **self-recursion only** (calls to other measures / `len` would emit undeclared symbols — deferred to M-c). (b) The **hard soundness gate** (§4): a `@[measure]` that is effectful (`spawn`/`send`/`dbg`/`assert`), divergent (`panic`/`todo`/`exit`), non-total (a `/`/`%` that can divide by zero, or a non-exhaustive `match` on its ADT param), or not structurally recursive is now a **compile error** — not a silent fallback. A sound-but-unaxiomatisable measure (multi-arg, element-inspecting, `let`-bodied) is *not* an error: it still falls back to a sound symbolic reflection (only the three soundness properties are gated). Implemented as a syntactic pass in `lib/refinecheck/refine_check.ml` (`measure_gate_errors`).
3. **M-c — measures calling measures**, ordering, mutual recursion, mutually-recursive datatypes (lift the self-recursion-only restriction from M-b).
4. **M-d — relational postconditions** (`size(insert(t,x)) == size(t)+1`) where provable by E-matching; document where a user lemma is still required.

Each phase keeps the definite-failure soundness stance; the gate (§4) landed with M-b, and axioms are enabled by default only because the gate guarantees no inconsistent axiom set is emitted.

## 8. Risks / decision criteria

- The soundness gate (§4) is the crux: it must be correct and complete enough that no inconsistent axiom set is ever emitted. If that can't be guaranteed cheaply, **do not ship** — symbolic measures + path sensitivity + `assume` already cover the common cases soundly.
- Quantifier unpredictability (§5) may make the feature feel flaky; if real-world `unknown` rates are high, the value over symbolic measures is limited.
- Performance regression on every `--check` is a real risk; keep it flag-gated until measured.

**Bottom line:** this is a genuine, buildable escalation that makes measures reason *structurally* rather than symbolically — but its value hinges entirely on the soundness gate, and its UX hinges on quantifier behaviour. Build M-a as a measured prototype, validate the gate (ideally in Lean), and only then decide whether to generalise and enable by default.

## 9. Consultation sites

| Concern | Location |
|---|---|
| Measure registration + symbolic reflection (today) | `lib/refinecheck/refine_check.ml` (`registered_measures`, `measure_body_nonneg`, `resolve_measure`) |
| SMT term language (extend for datatypes/quantifiers) | `lib/refine/smt.ml` |
| Solver driver (preamble assembly, `forall`, `declare-datatypes`) | `lib/refine/solver.ml` |
| VC cache key (must cover the axiom preamble) | `lib/refine/vc_cache.ml` |
| Structural-recursion info (the soundness gate) | `lib/typecheck/typecheck.ml` |
| ADT declarations (source of `declare-datatypes`) | `lib/ast/ast.ml` (`type_def`, `variant`) |
| State of the feature | `specs/2026-06-21-refinement-types-state-and-forward-design.md` |
