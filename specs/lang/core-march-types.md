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
application, the `+`/`==` primitives, `if`, and (as of Task 1) **ADT constructors
and `match`**. Same discipline as the operational skeleton: **every rule is
transcribed arm-for-arm from `lib/typecheck/typecheck.ml` and cited by line**,
and a conformance corpus keeps it honest.

The conformance mechanism differs from the operational side. There is only **one**
typechecker (it runs before both `eval` and `--compile`), so there is nothing to
*differentially* diff. Instead the anchor is the compiler's own `--check` mode
(`march --check file.march`: exit 0 = well-typed, exit 1 + a `-- ERROR --`
diagnostic = rejected). The corpus (§3) is split into **`accept/`** programs
(must typecheck) and **`reject/`** programs (must be rejected *with a specific
error message*). This catches both a spec that misdescribes the typechecker and a
typechecker regression.

Deferred (later typing slices, matching `core-march.md`'s deferred set):
records/tuples/atoms typing, the interface/impl resolution machinery,
refinements, linearity, capabilities, effects.

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

(T-Con)   ctor_info(C) = { ci_type = T; ci_params = ᾱ; ci_arg_tys = τ̄₀ }        typecheck.ml:410–415
          β̄ fresh                        (one fresh var per αᵢ, at env.level)  typecheck.ml:2387–2395
          τ̄ = τ̄₀[β̄ / ᾱ]                  (surface_ty substitutes ᾱ ↦ β̄ into each declared arg type)
          |args| = |τ̄|                    Γ ⊢ aᵢ ⇐ τᵢ  (i = 1..|τ̄|, left-to-right)
          ────────────────────────────────────────────────────────────────
          Γ ⊢ ECon C [a₁…aₙ] ⇒ T(β̄)                     typecheck.ml:3737–3794 (ECon arm), 3777 (instantiate_ctor call)
          -- C unresolved (not in env.ctors, not a qualified `Mod.C`) ⇒
          --   "I don't know a constructor called `C`." (+ suggestion hint)      typecheck.ml:3746–3759
          -- |args| ≠ |τ̄| ⇒ "Constructor `C` expects N argument(s) but I got M."  typecheck.ml:3780–3784
          -- each aᵢ is CHECKED (⇐), not inferred, against the instantiated τᵢ    typecheck.ml:3788–3792
          -- cf. operational (E-Con), core-march.md:366–368 — eval's ECon arm evaluates
          --   args left-to-right into a VCon; this rule is its typing counterpart.

          `instantiate_ctor` (typecheck.ml:2387–2395) is the shared instantiation
          engine — the SAME function underlies both T-Con here and the PatCon rule
          below (§2.2): one fresh unification variable per declared type parameter
          `ci_params`, then `surface_ty` converts the constructor's declared surface
          arg types with those fresh vars substituted in, and the result type is
          `TCon(ci_type, β̄)`. A 2-ctor ADT `type Shape = Circle(Int) | Square(Int)`
          has `ci_params = []` (no type params) so β̄ is empty and both `Circle`/
          `Square` simply get `arg_tys = [Int]`, `result_ty = TCon("Shape",[])`; a
          generic `type Box(a) = Full(a) | Vacant` gives `Full`'s `ci_params = ["a"]`
          a fresh `β`, so `instantiate_ctor` yields `arg_tys=[β]`, `result_ty =
          Box(β)` — a FRESH β per occurrence, which is what lets `Full(5)` and
          `Full("hi")` coexist (cf. T-Var/`instantiate`, §1).

(T-Match) Γ ⊢ e_s ⇒ τ_s                                                        typecheck.ml:3846–3848
          ρ fresh                                                              typecheck.ml:4274
          ∀(pᵢ → gᵢ? → bᵢ) ∈ branches:
              Γ ⊢ pᵢ : τ_s ⊣ Γᵢ   (pattern-typing relation, §2.2; unified against τ_s)  typecheck.ml:4276–4277
              Γ, Γᵢ ⊢ gᵢ ⇐ Bool   (if a guard is present)                       typecheck.ml:4280–4284
              Γ, Γᵢ ⊢ bᵢ ⇐ ρ                                                   typecheck.ml:4285–4286
          ──────────────────────────────────────────────────────────────
          Γ ⊢ EMatch e_s [(p₁,g₁?,b₁) … (pₙ,gₙ?,bₙ)] ⇒ ρ         typecheck.ml:4273–4290 (infer_match)
          -- one branch's body type disagreeing with another's ⇒ "All branches of
          --   a match must have the same type." (RMatchArm, typecheck.ml:47,67)
          -- non-exhaustive patterns ⇒ a separate WARNING (check_exhaustiveness,
          --   typecheck.ml:4288), not a typing error — does not block accept/reject.
          -- cf. operational (E-Match), core-march.md:504 — eval's EMatch arm selects
          --   the first branch whose pattern matches the scrutinee value; this rule
          --   is its typing counterpart (every branch must ⇐-check against ONE
          --   shared fresh result type `ρ`, unified branch-by-branch via `check_expr`).
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

### 2.2 Pattern typing: `Γ ⊢ p : τ ⊣ Γ'`

`infer_pattern` (typecheck.ml:2566, `?expected` optionally threads in the
scrutinee/argument type so an ambiguous bare constructor name — one shared by
two types — can be disambiguated by matching the expected type's head `TCon`,
typecheck.ml:2593–2603) computes both the type a pattern *expects* to match
AND the bindings (`(name, scheme) list`) it introduces into `Γ'` for the branch
body / rest of the match. Written `Γ ⊢ p : τ ⊣ Γ'` (`Γ'` = `Γ` extended with the
pattern's bindings):

```
(P-Wild)  ──────────────────────────────           typecheck.ml:2569–2570
          Γ ⊢ PatWild : β ⊣ Γ                       (β fresh; matches anything, binds nothing)

(P-Var)   β fresh                                   typecheck.ml:2572–2577
          ──────────────────────────────
          Γ ⊢ PatVar x : β ⊣ Γ, x:β
          -- β is recorded in env.type_map at x's span (for LSP hover); the
          --   binding is Mono β here — generalization (if any) happens later,
          --   at the ELet/branch call site, exactly as for T-Let (§2).

(P-Lit)   ──────────────────────────────           typecheck.ml:2579–2580
          Γ ⊢ PatLit ℓ : 𝒯(ℓ) ⊣ Γ                   (𝒯 as in T-Lit, §2)

(P-Con)   ctor_info(C) = ci   (resolved via `expected`'s head TCon if given,   typecheck.ml:2588–2612
             else `lookup_ctor`, else qualified `Mod.C` lookup)
          (τ̄, T(β̄)) = instantiate_ctor env ci                                 typecheck.ml:2642
          |ps| = |τ̄|
          ∀i: Γ ⊢ pᵢ : τᵢ ⊣ Γᵢ  (threading `~expected:τᵢ` into the recursive call)  typecheck.ml:2652–2662
          unify(τᵢ, type_of(pᵢ))  for each i
          ──────────────────────────────────────────────────────────────
          Γ ⊢ PatCon(C, [p₁…pₙ]) : T(β̄) ⊣ Γ, Γ₁, …, Γₙ                        typecheck.ml:2588–2664
          -- C unresolved ⇒ "I don't know a constructor called `C`."           typecheck.ml:2613–2629
          -- |ps| ≠ |τ̄| ⇒ "Constructor `C` expects N argument(s) in a pattern
          --   but I got M."                                                   typecheck.ml:2645–2651
          -- ambiguous bare `C` (multiple types define it) ⇒ a HINT (not an
          --   error) suggesting the qualified form `Type.C`                   typecheck.ml:2631–2641
```

`instantiate_ctor` (typecheck.ml:2387) is called from BOTH T-Con (§2, expression
side) and P-Con (pattern side) — the same fresh-vars-per-type-param instantiation
underlies `Some(5)` (an `ECon`) and `Some(x) -> …` (a `PatCon`) alike, which is
why a `match`'s scrutinee type and its constructor patterns unify cleanly: both
sides go through `instantiate_ctor` against the same `ctor_info`.

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
| `accept/t05_adt_construct_match` | accept | T-Con + T-Match — a 2-ctor ADT (`Hue = Rood \| Bloo`) constructed and matched exhaustively | typechecks |
| `accept/t06_payload_ctor_branch` | accept | P-Con — a payload-carrying ctor (`Circle(Int)`) bound to a pattern var in a branch | typechecks |
| `accept/t07_generic_option_two_types` | accept | T-Con/P-Con with a fresh instantiation per occurrence — a generic `Box(a) = Full(a) \| Vacant` used at both `Int` and `String` | typechecks |
| `reject/t05_ctor_arity` | reject | T-Con arity (`ECon` arm) | `` Constructor `Circle` expects 1 argument(s) but I got 2. `` |
| `reject/t06_match_branch_mismatch` | reject | T-Match branch-body unification | `All branches of a match must have the same type.` |

**Result: 13 / 13 (7 accept typecheck, 6 reject with the declared error).**

## 4. Faithfulness + the key findings

The rules were transcribed arm-for-arm from `typecheck.ml` at the cited lines
(human-reviewed, not mechanically verified — the roadmap §7 faithfulness risk);
the `accept/reject` corpus is the executable anchor. Four findings this skeleton
pins that are easy to get wrong and are load-bearing:

1. **No value restriction.** `generalize` runs whenever the `let` binds a simple
   `PatVar`, regardless of whether the RHS is a syntactic value (`infer_block`
   :4318–4324). March relies on its purity/level discipline rather than the
   ML value restriction. (`t03_let_poly` is the witness.)
2. **`+`/`==` are interface-constrained polymorphic**, resolved as ordinary
   variables — not monomorphic, not parser-overloaded (§2.1).
3. **No partial application.** A call site must saturate the function (`reject/t03`
   is the witness — the error explicitly says so).
4. **One instantiation engine for both directions.** `instantiate_ctor`
   (typecheck.ml:2387) is called from the `ECon` arm (expression side, T-Con)
   AND from `PatCon`'s arm in `infer_pattern` (pattern side, P-Con) — a
   constructor's `arg_tys → result_ty` shape (with fresh vars per type param)
   is computed exactly once per occurrence and reused for both directions, which
   is why `match`ing a freshly-constructed value type-checks without any special
   ADT-specific unification logic (`t07_generic_option_two_types` is the witness
   — `Full(5)` and `Full("hi")` each get their OWN fresh `β`, exactly like
   `instantiate` for `T-Var`, §1). Non-exhaustive `match` is a WARNING
   (`check_exhaustiveness`, typecheck.ml:4288), not a typing error — it does not
   affect accept/reject in this corpus.

## 5. What this validated, and what's next

**Validated:** the type-side methodology works end-to-end — the bidirectional HM
judgment is transcribable arm-for-arm from `typecheck.ml`, the `--check`-based
`accept/reject` harness is a workable conformance anchor (with exact-error-message
pinning), and the doc format (judgment → cited rules → accept/reject table) is a
replicable template. `check_types.sh` is the committed anchor; it belongs in a
slow CI lane alongside `@oracle`.

**Task 1 (this slice) added:** ADT constructor + `match` typing — (T-Con),
(T-Match), and the pattern-typing relation `Γ ⊢ p : τ ⊣ Γ'` for `PatCon`/
`PatVar`/`PatWild`/`PatLit` (§2, §2.2), transcribed from `instantiate_ctor`
(typecheck.ml:2387), the `ECon` arm of `infer_expr` (typecheck.ml:3737),
`infer_match` (typecheck.ml:4273), and `infer_pattern` (typecheck.ml:2566).

**Next (widening slices, each like this one):** records/tuples/atoms typing
(`PatTuple`/`PatRecord`/`PatAtom`, `TTuple`/`TRecord`, already sketched in
`infer_pattern` typecheck.ml:2582–2680 but not yet given rules here); then the
interface/impl resolution that discharges the `Num`/`Eq` constraints (§2.1) —
the richest and most bug-prone part, and the type-side complement to the
operational core. Together, `core-march.md` (operational) + this document (typing)
are **Level-1 for the Core March fragment**.
