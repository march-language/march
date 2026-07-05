# Core March — Static Semantics (typing walking skeleton, v0)

**Date:** 2026-07-05
**Status:** Walking skeleton — the FIRST vertical slice of Core March's **type
system**, the companion to the operational semantics in `core-march.md`.
Deliberately a tiny fragment taken end-to-end to prove the type-side methodology
(and a new conformance-harness shape) before scaling.
**Companion:** `specs/lang/core-march.md` (operational semantics — "what programs
mean"). This document is "which programs are well-typed."
**Depends on:** `specs/2026-07-04-language-specification-roadmap-design.md` §4.3.

---

## 0. What this is (and is not)

`core-march.md` documented the interpreter's *operational* rules. This document
documents the *typechecker's* rules — the `Γ ⊢ e : τ` judgment — for the same
kind of small fragment: literals, variables, `let` (with generalization), lambda,
application, the `+`/`==` primitives, and `if`. Same discipline as the operational
skeleton: **every rule is transcribed arm-for-arm from `lib/typecheck/typecheck.ml`
and cited by line**, and a conformance corpus keeps it honest.

The conformance mechanism differs from the operational side. There is only **one**
typechecker (it runs before both `eval` and `--compile`), so there is nothing to
*differentially* diff. Instead the anchor is the compiler's own `--check` mode
(`march --check file.march`: exit 0 = well-typed, exit 1 + a `-- ERROR --`
diagnostic = rejected). The corpus (§3) is split into **`accept/`** programs
(must typecheck) and **`reject/`** programs (must be rejected *with a specific
error message*). This catches both a spec that misdescribes the typechecker and a
typechecker regression.

Deferred (later typing slices, matching `core-march.md`'s deferred set): ADT
constructors + `match` typing, records/tuples/atoms typing, the interface/impl
resolution machinery, refinements, linearity, capabilities, effects.

## 1. The typing judgment

March's typechecker is **bidirectional Hindley–Milner**: two mutually-recursive
modes over the desugared AST (`typecheck.ml`):

- **synthesis** `infer_expr env e : ty` (:3236) — "compute `e`'s type", written `Γ ⊢ e ⇒ τ`.
- **checking** `check_expr env e expected ~reason` (:4164) — "check `e` against a
  known type", written `Γ ⊢ e ⇐ τ`.

Types `τ`, schemes `σ`, and environment `Γ`:

```
τ ::= Int | Float | Bool | String | Atom      -- TCon(name,[])          typecheck.ml:943–948
    | τ → τ                                    -- TArrow
    | α                                        -- TVar (unification var, carries a level)
    | C(τ…) | (τ,…) | { l:τ,… }                -- TCon(C,args) / TTuple / TRecord (later slices)

σ ::= τ | ∀ᾱ [C̄]. τ                            -- Mono τ | Poly(ids, constraints, τ)
```

A scheme `σ` may carry **interface constraints** `C̄` (e.g. `Num a`, `Eq a`) —
discharged separately from unification. Two HM operations move between `τ` and `σ`:

- **`instantiate` (:897)** — `∀ᾱ[C̄].τ` → a monotype by replacing each quantified
  `αᵢ` with a *fresh unification variable at the current level*; the constraints
  are instantiated onto `env.pending_constraints`.
- **`generalize level τ` (:845)** — quantify every unbound unification variable in
  `τ` whose level `> level` (the ones "born inside" the current `let`), yielding a
  `Poly` scheme. Uses a **level** discipline (each `let` RHS is typed at a bumped
  level via `enter_level`) instead of a global free-variable scan.

## 2. Typing rules (the fragment)

Each rule cites the `typecheck.ml` arm it is transcribed from.

```
(T-Lit)   ─────────────────────────                          typecheck.ml:2687–2692, 3240
          Γ ⊢ ELit ℓ ⇒ 𝒯(ℓ)
          where 𝒯(LitInt)=Int, 𝒯(LitFloat)=Float, 𝒯(LitBool)=Bool,
                𝒯(LitString)=String, 𝒯(LitAtom)=Atom

(T-Var)   (x : σ) ∈ Γ                                         typecheck.ml:3244–3280, 897
          ─────────────────────────
          Γ ⊢ EVar x ⇒ instantiate(σ)
          -- x ∉ Γ ⇒ error "I cannot find `x`." (typecheck.ml:3273)

(T-Abs)   Γ, x₁:τ₁, …, xₙ:τₙ ⊢ e ⇒ τ                          typecheck.ml:3797–3824, 4405
          each τᵢ = the param's annotation if present (surface_ty),
                    else a FRESH unification variable
          ────────────────────────────────────────────────
          Γ ⊢ ELam [x₁…xₙ] e ⇒ τ₁ → ⋯ → τₙ → τ

(T-App)   Γ ⊢ f ⇒ φ    then fold left-to-right over args:     typecheck.ml:4246–4270
          if φ ▹ TArrow(π, ρ):  Γ ⊢ aᵢ ⇐ π ,  continue with ρ
          if φ is an unbound α: unify α = (τ_aᵢ → ρ_fresh),  continue with ρ_fresh
          ────────────────────────────────────────────────
          Γ ⊢ EApp f [a₁…aₙ] ⇒ ρ   (ρ = the type left after consuming all args)
          -- φ not arrow-like ⇒ error "This is not a function — it has type `…`."
          -- a call must supply ALL args (no partial application); wrong arity ⇒
          --   "Function `f` expects N argument(s), but got M."

(T-Let)   Γ ⊢ e₁ ⇒ τ₁  at level L+1  (enter_level)            typecheck.ml:4293–4324, 845
          σ = if pat is a bare `PatVar` then generalize(L, τ₁) else Mono τ₁
          Γ, x:σ ⊢ (rest of block) ⇒ τ₂
          ────────────────────────────────────────────────
          Γ ⊢ EBlock(ELet(x = e₁) :: rest) ⇒ τ₂
          -- generalization is gated on a SIMPLE-VARIABLE pattern, NOT on e₁ being
          --   a syntactic value: March has NO value restriction (see §4).

(T-If)    Γ ⊢ c ⇐ Bool    Γ ⊢ t ⇒ τ    Γ ⊢ e ⇒ τ'   unify τ' = τ   typecheck.ml:4004–4017
          ────────────────────────────────────────────────
          Γ ⊢ EIf c t e ⇒ τ
          -- non-Bool cond ⇒ "The condition of an if expression must be Bool."
          -- τ ≠ τ' ⇒ "Both branches of an if expression must return the same type."
```

### 2.1 Primitive typing (δ-typing)

`+` and `==` are **not** magic — they are ordinary variables bound in the base
environment to **interface-constrained polymorphic schemes** (`typecheck.ml:1206–1249`),
resolved and instantiated exactly like any `EVar` (T-Var):

```
(δT-Add)  + : ∀a [Num a]. a → a → a            typecheck.ml:1229   (poly1_num)
(δT-Eq)   == : ∀a [Eq a]. a → a → Bool          typecheck.ml:1248   (poly1_iface "Eq")
```

So `2 + 3` instantiates `a := Int` and discharges `Num Int`; `x == y` instantiates
`a` to the operand type and discharges `Eq a`. This is *ad-hoc polymorphism via
interfaces layered on HM*, not overloading resolved by the parser — a genuinely
load-bearing fact (a program `1 + "x"` fails because `+`'s two args must share one
`a`, and `Int`/`String` don't unify, **not** because `+` is "the Int operator").

## 3. Conformance corpus

`specs/lang/types/` — split by expected outcome, run by `check_types.sh` (the
type-side analog of `golden/verify.sh`):

- **`accept/*.march`** — must typecheck (`march --check` exit 0).
- **`reject/*.march`** — must be rejected (exit 1) **and** the `--check` output must
  contain the substring in the program's `-- EXPECT-ERROR: <substring>` first line.

Run: `dune build bin/main.exe && MARCH_BIN=… specs/lang/types/check_types.sh`.

| Program | Kind | Anchors | Outcome |
|---|---|---|---|
| `accept/t01_literals` | accept | T-Lit (Int/Bool/String) | typechecks |
| `accept/t02_lambda_app` | accept | T-Abs, T-App, annotated `Int -> Int` param | typechecks |
| `accept/t03_let_poly` | accept | **T-Let generalization** — a local `id = fn x -> x` used at both `Int` and `String` | typechecks (proves let-polymorphism) |
| `accept/t04_if` | accept | T-If (Bool cond, matching branches) | typechecks |
| `reject/t01_int_vs_string` | reject | unification mismatch | `expected \`Int\` but got \`String\`` |
| `reject/t02_unbound_var` | reject | T-Var, `x ∉ Γ` | `I cannot find \`undefined_var\`` |
| `reject/t03_arity` | reject | T-App arity (no partial application) | `expects 1 argument, but got 2` |
| `reject/t04_if_branch_mismatch` | reject | T-If branch unification | `Both branches of an if expression must return the same type` |

**Result: 8 / 8 (4 accept typecheck, 4 reject with the declared error).**

## 4. Faithfulness + the key findings

The rules were transcribed arm-for-arm from `typecheck.ml` at the cited lines
(human-reviewed, not mechanically verified — the roadmap §7 faithfulness risk);
the `accept/reject` corpus is the executable anchor. Three findings this skeleton
pins that are easy to get wrong and are load-bearing:

1. **No value restriction.** `generalize` runs whenever the `let` binds a simple
   `PatVar`, regardless of whether the RHS is a syntactic value (`infer_block`
   :4318–4324). March relies on its purity/level discipline rather than the
   ML value restriction. (`t03_let_poly` is the witness.)
2. **`+`/`==` are interface-constrained polymorphic**, resolved as ordinary
   variables — not monomorphic, not parser-overloaded (§2.1).
3. **No partial application.** A call site must saturate the function (`reject/t03`
   is the witness — the error explicitly says so).

## 5. What this validated, and what's next

**Validated:** the type-side methodology works end-to-end — the bidirectional HM
judgment is transcribable arm-for-arm from `typecheck.ml`, the `--check`-based
`accept/reject` harness is a workable conformance anchor (with exact-error-message
pinning), and the doc format (judgment → cited rules → accept/reject table) is a
replicable template. `check_types.sh` is the committed anchor; it belongs in a
slow CI lane alongside `@oracle`.

**Next (widening slices, each like this one):** ADT constructor + `match` typing
(`infer_pattern` :2566, `instantiate_ctor` :2387); records/tuples/atoms typing;
then the interface/impl resolution that discharges the `Num`/`Eq` constraints
(§2.1) — the richest and most bug-prone part, and the type-side complement to the
operational core. Together, `core-march.md` (operational) + this document (typing)
are **Level-1 for the Core March fragment**.
