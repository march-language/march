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
application, the `+`/`==` primitives, `if`, (as of Task 1) **ADT constructors
and `match`**, (as of Task 2) **tuples and records**, and (as of Task 3)
**atoms**. Same discipline as the operational skeleton: **every rule is
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

Deferred (later typing slices, matching `core-march.md`'s deferred set): the
interface/impl resolution machinery, refinements, linearity, capabilities,
effects.

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
    | C(τ…) | (τ,…) | { l:τ,… }                -- TCon(C,args) / TTuple (§2, T-Tuple) / TRecord (§2, T-Record)

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
              Γ, Γᵢ ⊢ gᵢ ⇐ Bool   (T-Guard, if a guard is present — see below)   typecheck.ml:4280–4284
              Γ, Γᵢ ⊢ bᵢ ⇐ ρ                                                   typecheck.ml:4285–4286
          ──────────────────────────────────────────────────────────────
          Γ ⊢ EMatch e_s [(p₁,g₁?,b₁) … (pₙ,gₙ?,bₙ)] ⇒ ρ         typecheck.ml:4273–4290 (infer_match)
          -- one branch's body type disagreeing with another's ⇒ "All branches of
          --   a match must have the same type." (RMatchArm, typecheck.ml:47,67)
          -- ⚠ EXHAUSTIVENESS AND REDUNDANCY ARE NON-BLOCKING WARNINGS, NOT
          --   TYPING ERRORS — see "Exhaustiveness and redundancy" below for the
          --   full finding; a non-exhaustive `match` is WELL-TYPED (`--check`
          --   exits 0).
          -- cf. operational (E-Match), core-march.md:504 — eval's EMatch arm selects
          --   the first branch whose pattern matches the scrutinee value; this rule
          --   is its typing counterpart (every branch must ⇐-check against ONE
          --   shared fresh result type `ρ`, unified branch-by-branch via `check_expr`).
```

**(T-Guard)** — the guard clause of T-Match, stated separately for the `when g`
form:

```
(T-Guard) Γ, Γᵢ ⊢ pᵢ : τ_s ⊣ Γᵢ   (pattern bindings brought into scope first)   typecheck.ml:4276–4279
          Γ, Γᵢ ⊢ gᵢ ⇐ Bool                                                    typecheck.ml:4280–4284
          ──────────────────────────────────────────────────────────────
          (the guard clause of T-Match — part of the same judgment, not a
           separate expression form)
          -- `branch_guard : expr option` (`Ast.branch`) is threaded through BOTH
          --   typing entry points for a match: the synthesis path (`infer_match`,
          --   typecheck.ml:4280–4284) AND the checking path (the `EMatch` arm of
          --   `check_expr`, typecheck.ml:4192–4196) — identical shape, identical
          --   reason string, at both sites.
          -- the guard is `check_expr`'d (⇐), NOT inferred — against the
          --   monomorphic `t_bool`, in `env'` = Γ extended with THIS branch's own
          --   pattern bindings (`bind_pattern_bindings scrut bindings env`,
          --   typecheck.ml:4191/4279, computed BEFORE the guard is checked) — so
          --   a guard can read variables its own branch's pattern just bound
          --   (e.g. `P(a, b) when a == b -> …`).
          -- non-Bool guard ⇒ the ordinary unify-mismatch headline "expected
          --   `Bool` but got `<τ>`." with the note "Match guards must be Bool."
          --   (`RBuiltin "Match guards must be Bool."`, typecheck.ml:4282–4283 /
          --   4194–4195) — e.g. `n when n + 1 -> …` (an `Int`-typed guard) is
          --   REJECTED at typecheck time with exactly this note (captured live;
          --   `reject/t10_guard_not_bool` is the witness).
          -- cf. operational (E-Match's guard clause), core-march.md:741–751 — the
          --   guard is evaluated in the SAME pattern-extended env `env'`
          --   (`eval.ml:7327,7332`) and must reduce to a `VBool` at runtime
          --   (`eval_error "guard must evaluate to a boolean"`, `eval.ml:7334`,
          --   for a non-`VBool` result) — but that runtime error is unreachable
          --   for a well-typed program: this rule is what makes it dead code for
          --   anything that passed typecheck (same shape as T-Cond's non-Bool-
          --   condition runtime check being unreachable, below).
```

**Exhaustiveness and redundancy — WARNING, NOT AN ERROR.** This note is part
of (T-Match): both checks run unconditionally at the end of every `match`
(`typecheck.ml:4288–4289`, and the `EMatch` arm of `check_expr`,
`typecheck.ml:4199`), but neither can fail typechecking.

```
check_exhaustiveness env span scrut_ty branches                      typecheck.ml:3159–3185 (defn), 4288 (call site)
check_redundant_arms  env      scrut_ty branches                     typecheck.ml:3131–3155 (defn), 4289 (call site)
```

Both diagnostics are constructed with `severity = Warning`:
  - non-exhaustive, with a concrete missing-case example — message
    `"Non-exhaustive pattern match — missing case: %s"`              (typecheck.ml:3172–3177)
  - non-exhaustive, no concrete example available — message
    `"Non-exhaustive pattern match"`                                 (typecheck.ml:3179–3184)
  - a redundant (unreachable) arm — message
    `"This pattern can never be reached."`                           (typecheck.ml:3143–3151)

**⚠ THIS IS THE BRITTLE, LOAD-BEARING FACT OF THIS SLICE:** `--check`'s exit
code is driven by `has_user_errors`, which filters strictly on `d.severity =
March_errors.Errors.Error` (`bin/main.ml:819–821`) — a `Warning`-severity
diagnostic (either of the above two kinds) NEVER sets `has_user_errors`, so a
non-exhaustive `match` or a redundant arm **typechecks (`--check` exits 0)**.
This is NOT "the typechecker forgot to check exhaustiveness" —
`check_exhaustiveness` runs on EVERY `match` (unconditionally, at the end of
both `infer_match` and the `EMatch` arm of `check_expr`, typecheck.ml:
4199/4288) and DOES emit a diagnostic for a missing case; that diagnostic is
simply non-fatal by design.

Exhaustiveness checking is also SKIPPED ENTIRELY (not merely downgraded) when
ANY branch of the match carries a guard: `let has_guards = List.exists (…
branch_guard <> None) branches in if has_guards then () else …`
(typecheck.ml:3161–3164) — "coverage becomes undecidable" once a guard is
present (the comment at typecheck.ml:3158), since a guard can make an
otherwise-total pattern set partial at runtime (E-Match's guard-false
fall-through, core-march.md:741–751). Redundancy checking, by contrast, only
skips INDIVIDUAL guarded arms (`if br.branch_guard = None then …`,
typecheck.ml:3136) while still checking the unguarded ones against the
accumulated prefix.

**Conformance-corpus consequence:** an `accept/` program with a deliberately
non-exhaustive `match` is CORRECT — it is SUPPOSED to typecheck
(`accept/t14_nonexhaustive_match_still_typechecks` is the witness: exit 0,
with a rendered `-- WARNING --` block reading "Non-exhaustive pattern match —
missing case: Bloo"). A non-exhaustive match can NEVER be used to construct a
`reject/` program in this corpus, because `check_types.sh` keys purely on the
process exit code (§3) and a Warning never changes it.

This is the type-side counterpart of `core-march.md`'s §4.3
`Match_failure`/panic rule: an accepted-but-non-exhaustive `match` is exactly
the program shape that can raise a runtime "no matching branch" error
(interpreted) or panic (compiled) on an uncovered value at RUNTIME — the
Warning is the typechecker's only static signal that this is possible, and it
is advisory, not enforced.

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

### 2.1a Conditionals without a scrutinee: `ECond` (`match do c -> b … end`)

```
(T-Cond)  arms = (c₁,b₁) … (c_n,b_n),  n ≥ 1                                    typecheck.ml:4020–4036 (ECond arm of infer_expr)
          Γ ⊢ c₁ ⇐ Bool                                                        typecheck.ml:4027–4028
          ρ = (Γ ⊢ b₁ ⇒ ·)                                                     typecheck.ml:4029
          ∀i = 2..n:  Γ ⊢ cᵢ ⇐ Bool                                             typecheck.ml:4031–4032
                      Γ ⊢ bᵢ ⇒ τᵢ    unify(ρ, τᵢ)                               typecheck.ml:4033–4034
          ──────────────────────────────────────────────────────────────
          Γ ⊢ ECond [(c₁,b₁)…(c_n,b_n)] ⇒ ρ
          -- n = 0 (an `ECond` with zero arms) ⇒ a DEDICATED error, not a
          --   unify/fallthrough one: "A `match do` expression needs at least one
          --   arm." (typecheck.ml:4022–4024) — a plain `Err.error`, not routed
          --   through `report_mismatch`/`RBuiltin`, since there is no type
          --   mismatch to report when there are no arms to synthesize a result
          --   type from.
          -- a non-Bool condition (any arm, first or later) ⇒ the ordinary
          --   unify-mismatch headline "expected `Bool` but got `<τ>`." with the
          --   note "Each condition in `match do` must be Bool." (`RBuiltin
          --   "Each condition in `match do` must be Bool."`, typecheck.ml:4028,
          --   4032) — e.g. bare `n -> "positive"` where `n : Int` is REJECTED
          --   with exactly this note (captured live;
          --   `reject/t11_econd_condition_not_bool` is the witness).
          -- branch-body type mismatch (a later arm's body doesn't unify with the
          --   FIRST arm's body type ρ) ⇒ falls to the SAME "All branches of a
          --   match must have the same type." headline `EMatch` uses (`RMatchArm
          --   sp`, typecheck.ml:4034/47/67) — `ECond` and `EMatch` share this one
          --   reason string; there is no `ECond`-specific branch-mismatch message.
          -- unlike (T-Match), there is NO exhaustiveness/redundancy check here at
          --   all — `check_exhaustiveness`/`check_redundant_arms` are called only
          --   from `infer_match`/`EMatch`'s `check_expr` arm (typecheck.ml:4199,
          --   4288–4289), never from the `ECond` arm. This matches the
          --   operational finding that `ECond` is NOT statically total
          --   (`core-march.md:492–498`, E-Cond-Fail): an all-false chain
          --   typechecks unconditionally (no Warning either — not even the
          --   advisory one (T-Match) gets) and raises a runtime
          --   "non-exhaustive `match do`" error (`eval.ml:7099`) unless a final
          --   `true ->`/`_ ->` arm is present.
          -- cf. operational (E-Cond-Sel / E-Cond-Fail), core-march.md:471–502 —
          --   eval's `ECond` arm evaluates conditions top-to-bottom and runs the
          --   first `VBool true` arm's body; this rule is its typing counterpart
          --   (every condition ⇐-checked against `Bool`, every body unified into
          --   ONE shared result type `ρ` — anchored at the FIRST arm's inferred
          --   type rather than a fresh var, unlike (T-Match)'s `ρ fresh`).
```

### 2.2 Pattern typing: `Γ ⊢ p : τ ⊣ Γ'`

`infer_pattern` (typecheck.ml:2566, `?expected` optionally threads in the
scrutinee/argument type so an ambiguous bare constructor name — one shared by
two types — can be disambiguated by matching the expected type's head `TCon`,
typecheck.ml:2593–2603) computes both the type a pattern *expects* to match
AND the bindings (`(name, scheme) list`) it introduces into `Γ'` for the branch
body / rest of the match. Written `Γ ⊢ p : τ ⊣ Γ'` (`Γ'` = `Γ` extended with the
pattern's bindings).

**This is now the COMPLETE relation** — every arm of `infer_pattern`
(typecheck.ml:2566–2685) is accounted for below, one way or the other:
`PatWild`/`PatVar`/`PatLit`/`PatCon`/`PatTuple`/`PatAtom` each get a live rule
((P-Wild)/(P-Var)/(P-Lit)/(P-Con)/(P-Tuple)/(P-Atom), added across Tasks 1–3);
`PatRecord` and `PatAs` are each documented as **unreachable from surface
grammar** instead of given a live rule (both have a real, working
`infer_pattern` arm — the code path is not dead in the OCaml sense — but no
March program a user can actually write ever constructs one, so per this
document's own methodology, §0, no rule is stated for either — see the
`PatRecord` note after (P-Atom) and the `PatAs` note immediately below):

```
(P-Wild)  ──────────────────────────────           typecheck.ml:2569–2570
          Γ ⊢ PatWild : β ⊣ Γ                       (β fresh; matches anything, binds nothing)

(P-Var)   β fresh                                   typecheck.ml:2572–2577
          ──────────────────────────────
          Γ ⊢ PatVar x : β ⊣ Γ, x:β
          -- β is recorded in env.type_map at x's span (so lower.ml can resolve
          --   the pattern var's type via ty_of_span; type_map also feeds LSP hover
          --   elsewhere — see the ELet recording at typecheck.ml:4309); the
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

(P-Tuple) ∀i: Γ ⊢ pᵢ : τᵢ ⊣ Γᵢ   (i = 1..k, componentwise recursion)  typecheck.ml:2582–2586
          ──────────────────────────────────────────────────────────────
          Γ ⊢ PatTuple [p₁…pₖ] : TTuple [τ₁…τₖ] ⊣ Γ, Γ₁, …, Γₖ
          -- unlike P-Con, there is no separate arity check IN this arm —
          --   PatTuple's result type TTuple [τ₁…τₖ] has exactly |ps|
          --   components by construction, so an arity mismatch against the
          --   scrutinee/expected type is caught later, at the unify call
          --   site that relates this pattern's type to the scrutinee (e.g.
          --   T-Let's `unify env_rhs rhs_ty pat_ty`, typecheck.ml:4308, or
          --   T-Match's per-branch pattern unification, typecheck.ml:4277)
          --   — same "no dedicated arity message, falls to the generic
          --   report_mismatch" shape as T-Tuple (§2) above
          -- cf. operational match(PatTuple, VTuple), core-march.md (the
          --   E-Tuple neighborhood) — componentwise recursion mirrors
          --   `infer_pattern`'s recursive structure exactly: each element
          --   pattern is typed independently (no `~expected` threading here,
          --   unlike P-Con, since a tuple has no declared per-slot type to
          --   thread in)

(P-Atom)  ∀i: Γ ⊢ pᵢ : τᵢ ⊣ Γᵢ   (i = 1..k, k ≥ 0, componentwise    typecheck.ml:2666–2669
          recursion — τᵢ computed but then DISCARDED, only Γᵢ kept)
          ──────────────────────────────────────────────────────────────
          Γ ⊢ PatAtom(a, [p₁…pₖ]) : Atom ⊣ Γ, Γ₁, …, Γₖ
          -- same erasure as T-Atom (§2): the OVERALL pattern type is the
          --   bare, tag-erased `Atom` regardless of `a` or `k` — verbatim
          --   `Ast.PatAtom (_, ps, _) -> let bs_tys = List.map (infer_pattern
          --   env) ps in let bindings = List.concat_map fst bs_tys in
          --   bindings, t_atom` (typecheck.ml:2666–2669). `:ok` and
          --   `:count(x)` are both, as PATTERNS, simply `Atom` — nothing
          --   about the tag name or arity survives into the type this arm
          --   returns.
          -- UNLIKE P-Con, there is no `~expected` threading into the
          --   sub-pattern recursion and no `unify(τᵢ, type_of(pᵢ))` call
          --   afterward — each `pᵢ`'s own type `τᵢ` (the `snd` of
          --   `infer_pattern`'s result pair) is computed and then silently
          --   dropped (only the *bindings*, the `fst`, are kept via
          --   `List.concat_map fst`). Concretely, a payload `PatVar x` inside
          --   `:tag(x)` is typed by the ordinary `PatVar` rule (§2.2 above:
          --   `x` bound to a FRESH, otherwise-unconstrained unification
          --   variable `β`, typecheck.ml:2572–2577) — and because this arm
          --   never unifies that `β` against anything, `x`'s type stays
          --   whatever the branch body's later use of `x` happens to pin it
          --   to (or remains an unresolved TVar if `x` goes unused) — there is
          --   NO type-level connection between an atom pattern's payload
          --   binding and the value that was actually constructed there.
          -- no arity check either: a nullary `PatAtom(a, [])` and an
          --   n-payload `PatAtom(a, [p₁…pₙ])` both simply return `Atom`;
          --   whether a given `PatAtom` can actually MATCH a given atom VALUE
          --   at runtime (nullary pattern vs. `VAtom`, or n-ary pattern vs.
          --   `VCon` of matching arity) is an operational-side concern
          --   (`match_pattern`'s two `PatAtom` cases, core-march.md:790–813),
          --   not something this typing rule enforces or even inspects.
          -- cf. operational match(PatAtom, VAtom)/match(PatAtom, VCon),
          --   core-march.md:790–813 (E-Atom-0/E-Atom-N's pattern-side mirror)
          --   — the type side collapses BOTH of those operational shapes
          --   (nullary-vs-`VAtom`, payload-vs-`VCon`) into the one judgment
          --   above, because typing never needed the nullary/payload
          --   distinction the operational rules must make to pick the right
          --   value shape.
          -- this is the SAME divergence T-Atom documents (§2): the type
          --   system tracks strictly less than the operational semantics
          --   does for atoms, in both directions (expression AND pattern) —
          --   already flagged as the root cause of a (since-fixed)
          --   `Show(Atom)` compiled-link bug in core-march.md:1354–1359,
          --   which traces through both this arm and T-Atom's `EAtom` arm.
```

**No `(P-Record)` rule: `PatRecord` is unreachable from surface syntax**, exactly
as `core-march.md` already documents for the operational side (`core-march.md:181–196`,
"`PatRecord` has no surface production at all — it is dead code, reachable
only by constructing the AST node directly"). Grepping `lib/parser/parser.mly`
for `PatRecord` finds zero occurrences; the typechecker's own `infer_pattern`
arm for it (typecheck.ml:2671–2680 — componentwise field recursion into a
sorted `TRecord`, structurally the record-analog of P-Tuple above) can
therefore never fire on a program a user actually wrote. Per this document's
own methodology (§0: "every rule is transcribed... and cited"), no `(P-Record)`
rule is stated here — inventing one would document code the parser can never
reach, mirroring exactly how `core-march.md` handled the same gap for its
`match(PatRecord …)` rule.

**No `(P-As)` rule either: `PatAs` (`p as x`) is likewise unreachable from
surface syntax**, exactly as `core-march.md` documents for the operational
side (`core-march.md:872–904`, §4.3.1 "Implemented-but-unreachable pattern
forms"). Verified fresh for this task:

- `infer_pattern` DOES have a live, working arm for it:
  ```
  | Ast.PatAs (inner, name, _) ->
    let bindings, t = infer_pattern env inner in
    Hashtbl.replace env.type_map name.span t;
    (name.txt, Mono t) :: bindings, t
  ```
  (typecheck.ml:2682–2685, verbatim) — it types the inner pattern, then binds
  `name` to that SAME type `t` in addition to whatever `inner` itself bound
  (i.e. `Γ ⊢ p as x : τ ⊣ Γ, Γ_inner, x:τ` would be the rule, were it reachable
  — the pattern-typing analog of `PatVar`'s binding, layered on top of an
  arbitrary sub-pattern rather than replacing it).
- But grepping `lib/parser/parser.mly` for `PatAs` finds **zero** occurrences
  (confirmed for this task). The `AS` token exists in the lexer (`("as",
  AS)`, `lexer.mll:48`) and appears in the grammar exactly once, in
  `soft_lower_name` (`parser.mly:1361`: `| AS { mk_name "as" $loc }`) — that
  production lets `as` be used as an ordinary VARIABLE/BINDING name (so `let
  as = 5` or a param named `as` parses), it does **not** build a `PatAs` node.
  Neither `pattern` nor `simple_pattern` (parser.mly:1311–1341) has any
  production shaped like `pattern AS lower_name` or similar. So `p as x` is
  not parseable pattern syntax at all in March — attempting it either parses
  `as` as a fresh `PatVar` (if `as` appears where a pattern is expected) or
  is a plain parse error, never a `PatAs`.
- `PatAs` is still constructed internally by the DESUGARER (three arms in
  `desugar.ml`, per `core-march.md:899–900`) — but only by recursing into an
  *already-constructed* `PatAs`, never by building a fresh one from surface
  tokens; so even post-desugar, a user-written program can never introduce
  one that wasn't already there (and none can already be there, since parsing
  never produces one).
- Consistent with this, `core-march.md` already treats `PatAs` as the
  unreachable operational counterpart (`core-march.md:200,872–904,934–968`)
  and notes the golden corpus uses guarded branches reading their own
  pattern's bindings (`g27_guard_binding.march`) as "the reachable substitute
  for the unparseable as-pattern" (`core-march.md:1247`) — this task's
  `accept/t13_match_guard` and the pre-existing `g25`/`g27` goldens are that
  same substitute on the type side: guards, not as-patterns, are how March
  programs actually read a branch's own bindings in a condition.

Per this document's methodology (§0), the `PatAs` arm above is shown ONLY to
demonstrate `infer_pattern` really does handle it (fidelity — it is not
silently omitted), exactly mirroring how `core-march.md` handles the same gap
for its operational `match(PatAs …)` rule; no `(P-As)` rule number is minted,
since inventing one would document a form no March source file can produce.

`instantiate_ctor` (typecheck.ml:2387) is called from BOTH T-Con (§2, expression
side) and P-Con (pattern side) — the same fresh-vars-per-type-param instantiation
underlies `Some(5)` (an `ECon`) and `Some(x) -> …` (a `PatCon`) alike, which is
why a `match`'s scrutinee type and its constructor patterns unify cleanly: both
sides go through `instantiate_ctor` against the same `ctor_info`.

```
(T-Tuple) Γ ⊢ eᵢ ⇒ τᵢ   (i = 1..k, k ≥ 1)                     typecheck.ml:3851–3852
          ────────────────────────────────────────────────
          Γ ⊢ ETuple [e₁…e_k] ⇒ TTuple [τ₁…τ_k]
          -- ETuple [] ⇒ t_unit (the same `()`-as-VUnit alias the operational
          --   side documents, NOT a genuine 0-ary TTuple)                    typecheck.ml:3851
          -- cf. operational (E-Tuple), core-march.md:383–389 — eval's ETuple
          --   arm builds a VTuple from the same left-to-right element order;
          --   this rule is its typing counterpart. No arity check is needed
          --   here (unlike T-Con): a tuple "constructor" has no declared
          --   shape to check arity against — TTuple's arity is simply
          --   |elements|. Two TTuples of DIFFERENT lengths are still
          --   rejected, but at unify time (see the T-Tuple mismatch note
          --   below), not in this arm.
          -- a length mismatch between a TTuple and its expected/annotated
          --   type is NOT one of unify's *guarded* structural cases — unify
          --   only iterates componentwise `when List.length ts1 = List.length
          --   ts2` (typecheck.ml:2122–2123); a length MISMATCH instead falls
          --   through to the catch-all `report_mismatch` (typecheck.ml:2172–
          --   2173), which renders the generic "expected `(τ…)` but got
          --   `(τ…)`." headline — there is no tuple-specific arity message
          --   the way T-Con/P-Con have their own "expects N argument(s)"
          --   text.

(T-Record) Γ ⊢ eᵢ ⇒ τᵢ   (i = 1..k, over the fields as written    typecheck.ml:3855–3857
           in source order)
           ────────────────────────────────────────────────────────
           Γ ⊢ ERecord [(f₁=e₁)…(f_k=e_k)] ⇒ TRecord (sort_by_name [(f₁,τ₁)…(f_k,τ_k)])
           -- the field list is SORTED BY NAME before becoming a TRecord
           --   (`List.sort (fun (a,_)(b,_) -> String.compare a b)`,
           --   typecheck.ml:3857) — TRecord's internal representation is
           --   order-independent by construction, which is exactly why
           --   `unify`'s TRecord case (typecheck.ml:2125–2137) can compare
           --   two TRecords' field-name lists with plain `<>` instead of a
           --   set comparison: both sides are always pre-sorted.
           -- NO duplicate-field-name check — a repeated field name (e.g.
           --   `{ x: 1, x: 2 }`) is not rejected at this arm; `List.sort` is
           --   stable but does not dedup, so the TRecord can carry a
           --   duplicate key, mirroring the operational side's identical gap
           --   (core-march.md:395–400, "the typechecker's ERecord case does
           --   not reject duplicate names either")
           -- surface syntax uses `:` for field bindings (`{ x: 1 }`), NOT
           --   `=`, despite what `ast.ml`'s doc comments show — the same
           --   fidelity note the operational spec already recorded
           --   (core-march.md:167–169)
           -- cf. operational (E-Record), core-march.md:391–400

(T-Field) Γ ⊢ e ⇒ τ                                                typecheck.ml:3900, 3939
          expand_record env τ = Some (TRecord flds)                typecheck.ml:2401–2435, 3940
          (l : τ_l) ∈ flds                                         typecheck.ml:3942–3943
          ────────────────────────────────────────────────────────
          Γ ⊢ EField e l ⇒ τ_l
          -- `expand_record` (typecheck.ml:2401) is what lets this rule apply
          --   not just to a literal `TRecord` but also to a NAMED record type
          --   (`TCon("Point",[])` for a `type Point = { x: Int, y: Int }`
          --   declaration) — it resolves the constructor to its structural
          --   field list (from `env.records`, or the cross-module registry
          --   for a lazily-loaded record type) before the field lookup
          -- l ∉ flds ⇒ "This record does not have a field called `l`.\nThe
          --   fields I see are: <comma-joined flds>"                         typecheck.ml:3980–3987
          -- τ resolves to neither TRecord-like nor an unbound TVar (i.e. is
          --   some OTHER concrete type, e.g. Int) ⇒ "I cannot access field
          --   `l` because this expression has type `<τ>`, which is not a
          --   record."                                                       typecheck.ml:3989–3998
          -- τ is an unbound TVar (erased/still-unknown base) ⇒ NOT an error:
          --   returns a FRESH unification variable instead, deferring the
          --   check (a row-polymorphism gap noted in-line as a TODO)         typecheck.ml:3990–3993
          -- EField ALSO doubles as qualified module-member access
          --   (`Mod.member`), tried FIRST via a dotted-path reconstruction
          --   over ECon/EField chains, before this record-field rule is even
          --   attempted                                                      typecheck.ml:3900–3935
          -- cf. operational (E-Field), core-march.md:438–449 — same
          --   first-occurrence-lookup / module-path-doubling shape

(T-Update) Γ ⊢ e_b ⇒ τ_b     Γ ⊢ eᵢ ⇒ υᵢ  (i=1..m, over updates    typecheck.ml:3860–3864
           as written in source order)
           expand_record env τ_b = Some (TRecord flds)             typecheck.ml:3865–3866
           ∀ (gᵢ, υᵢ): (gᵢ : φᵢ) ∈ flds   unify(φᵢ, υᵢ)             typecheck.ml:3867–3873
           ────────────────────────────────────────────────────────
           Γ ⊢ ERecordUpdate e_b [(g₁=e₁)…(g_m=e_m)] ⇒ τ_b
           -- gᵢ ∉ flds (for a base whose type IS a resolvable TRecord) ⇒
           --   "This record does not have a field called `gᵢ`.\nThe fields I
           --   know about are: <comma-joined flds>" — REJECTED AT TYPECHECK
           --   TIME                                                          typecheck.ml:3874–3880
           -- this is the static counterpart of the operational missing-field
           --   adjudication (core-march.md §4.2.1): for a base with a
           --   concrete, statically-known TRecord type, `ERecordUpdate` on an
           --   absent field NEVER reaches eval/codegen at all — it is
           --   rejected here, at typecheck.ml:3865–3892, exactly as
           --   core-march.md:559–567 already documents ("so E-Update's
           --   runtime behavior on an absent field is unreachable for a
           --   statically-typed base"). The runtime missing-field error
           --   (`eval_error "record update: no field '%s' in record"`,
           --   the compiled panic, etc.) is ONLY observable when `τ_b` is an
           --   erased/unconstrained TVar that `expand_record` cannot resolve
           --   (the `TVar _` branch just below, next bullet) — e.g. a base
           --   produced by a fully polymorphic stdlib builtin like
           --   `record_from_list`.
           -- τ_b is an unbound TVar (erased base, expand_record returns
           --   None) ⇒ NOT an error here: builds a PARTIAL TRecord constraint
           --   out of the update list's OWN field names and unifies τ_b
           --   against it, deferring the "does this field actually exist"
           --   question to runtime (see core-march.md §4.2.1 for the
           --   interpreter/compiled convergence on that runtime check)        typecheck.ml:3883–3891
           -- τ_b resolves to neither a TRecord-like type nor a TVar (some
           --   other concrete non-record type) ⇒ "I can only use `{ … with
           --   … }` on a record, but this expression has type `<τ_b>`."       typecheck.ml:3892–3897
           -- cf. operational (E-Update), core-march.md:402–436

(T-Atom-0) ──────────────────────────────                        typecheck.ml:4050–4052
           Γ ⊢ EAtom a [] ⇒ Atom
(T-Atom-N) Γ ⊢ eᵢ ⇒ (discarded)   (i = 1..k, k ≥ 1, typechecked    typecheck.ml:4050–4052
           left-to-right for their unification side effects only)
           ────────────────────────────────────────────────────
           Γ ⊢ EAtom a [e₁…e_k] ⇒ Atom
           -- ERASURE, the load-bearing fact: EVERY EAtom — nullary or
           --   payload-carrying, whatever its tag `a` — has ONE monomorphic
           --   type, `Atom` (`t_atom = TCon("Atom",[])`, typecheck.ml:948).
           --   The tag name `a` and the payload argument list `args` are BOTH
           --   erased at the type level: `Ast.EAtom (_, args, _) -> List.iter
           --   (fun a -> ignore (infer_expr env a)) args; t_atom`
           --   (typecheck.ml:4050–4052, verbatim). Concretely: `:ok`, `:red`,
           --   `:count(1)`, and `:count("x")` ALL synthesize the exact same
           --   type `Atom` — there is no `Atom("ok")` or `Atom(Int)` refinement
           --   anywhere in the type system (contrast `T-Con`, §2 above, where
           --   each ADT constructor keeps its OWN declared `result_ty`/
           --   `arg_tys` — atoms have no such per-tag typing at all).
           -- the payload IS typechecked, not skipped: `infer_expr env a` runs
           --   for every argument expression (so a payload type error, e.g.
           --   `:count(1 + "x")`, still fires — the `Num`/unify error comes
           --   from the `+` sub-expression itself, not from anything in this
           --   arm); but each result is `ignore`d — the payload's inferred
           --   type never flows anywhere (not into a returned type, not into
           --   any environment binding). It is computed ONLY for its
           --   unification side effects (discharging that sub-expression's own
           --   constraints/error-reporting) and then thrown away.
           -- since NOTHING distinguishes `:ok` (0 args) from `:tag(x, y)` (2
           --   args) in the result type, two atoms with DIFFERENT tags, or
           --   the same tag with structurally different payloads, freely
           --   coexist and unify at every call site — e.g. `if c do :red else
           --   :blue end : Atom` typechecks with no special-casing, the same
           --   way `if c do 1 else 2 end : Int` does, simply because both
           --   branches synthesize the identical monomorphic `Atom`.
           -- cf. operational (E-Atom-0/E-Atom-N), core-march.md:370–375 —
           --   eval's EAtom arms build a `VAtom a` (nullary) or `VCon a
           --   [v₁…v_k]` (payload-carrying) and KEEP the tag name and payload
           --   values at runtime; this rule is the typing counterpart, and the
           --   divergence is exactly the point — the operational side
           --   preserves what the type side discards. This is the same
           --   erasure already flagged in core-march.md:1354–1359 as the root
           --   cause of a (since-fixed) `Show(Atom)` compiled-link bug: an
           --   atom payload variable bound via a `match` (see P-Atom, §2.2)
           --   carries no concrete type from this rule alone, only from
           --   whatever the branch body later does with it.
```

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
| `accept/t08_tuple_construct_destructure` | accept | T-Tuple + P-Tuple — a tuple built and destructured both by a `match` and by a function-arg `PatTuple` | typechecks |
| `accept/t09_record_literal_field` | accept | T-Record + T-Field — a record literal built (`{ x: 1, y: 2 }`) and both fields read via `EField` | typechecks |
| `accept/t10_record_update_existing_field` | accept | T-Update — `{ p with x: 100 }` on an existing field, result type unchanged | typechecks |
| `reject/t07_field_missing` | reject | T-Field "no such field" (`EField` arm) | `` This record does not have a field called `z`. `` |
| `reject/t08_tuple_arity_mismatch` | reject | T-Tuple/unify length mismatch, via T-App checking a `(Int,Int)`-annotated param against a 3-tuple argument | `` expected `(Int, Int)` but got `(Int, Int, Int)`. `` |
| `reject/t09_record_update_missing_field` | reject | T-Update "no such field" (`ERecordUpdate` arm, concrete-`TRecord` base) | `` This record does not have a field called `z`. `` |
| `accept/t11_atom_nullary_eq_match` | accept | T-Atom-0 + P-Atom — a nullary `:ok` returned, compared via `==`, and matched by a nullary `PatAtom` | typechecks |
| `accept/t12_atom_payload_and_name_erasure` | accept | T-Atom-N + P-Atom — a payload atom `:count(n+1)` matched with its payload bound, AND two DIFFERENT-named nullary atoms (`:red`/`:blue`) returned from the two arms of one `if`, proving name-erasure (both branches synthesize the identical `Atom`) | typechecks |
| `accept/t13_match_guard` | accept | (T-Guard) — three `when`-guarded `PatVar` arms (`n when n > 0`/`n when n < 0`/`_`), guard checked against `Bool` in the pattern-extended env | typechecks |
| `accept/t14_nonexhaustive_match_still_typechecks` | accept | **(T-Match: Exhaustiveness) — the brittleness witness**: a 2-ctor ADT `match` covering only ONE ctor (`Rood`, no `Bloo`, no `_`) | typechecks — exit 0 WITH a rendered `-- WARNING --` ("Non-exhaustive pattern match — missing case: Bloo"); proves exhaustiveness is advisory, not enforced |
| `accept/t15_econd_chain` | accept | (T-Cond) — a 3-arm `match do` boolean chain (`n > 0`/`n < 0`/`_`), all conditions `Bool`, all bodies `String` | typechecks |
| `reject/t10_guard_not_bool` | reject | (T-Guard) non-Bool guard (`n when n + 1 -> …`, an `Int` guard) | `Match guards must be Bool.` |
| `reject/t11_econd_condition_not_bool` | reject | (T-Cond) non-Bool condition (bare `n -> …` where `n : Int`) | `` Each condition in `match do` must be Bool. `` |

**Result: 26 / 26 (15 accept typecheck, 11 reject with the declared error).**

**No atom-specific `reject/` program.** Every `EAtom`/`PatAtom` occurrence —
nullary or payload-carrying, whatever the tag — synthesizes the single bare
`Atom` type (T-Atom-0/T-Atom-N, P-Atom, §2/§2.2); there is no per-tag or
per-arity typing distinction for atoms to violate, so atoms cannot originate a
type error in isolation. A payload sub-expression can still fail to typecheck
(e.g. `:count(1 + "x")`), but that failure comes from `+`'s own `Num`
constraint (δT-Add, §2.1) — an ordinary unification/interface error already
covered by the existing corpus — not from anything atom-specific, so it would
not add coverage as a *new* reject program here.

## 4. Faithfulness + the key findings

The rules were transcribed arm-for-arm from `typecheck.ml` at the cited lines
(human-reviewed, not mechanically verified — the roadmap §7 faithfulness risk);
the `accept/reject` corpus is the executable anchor. Findings this skeleton
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
5. **Structural, order-independent records.** `ERecord` sorts its field list by
   name at construction (typecheck.ml:3857) and `PatRecord` does likewise
   (typecheck.ml:2679), so two `TRecord`s are compared fieldwise by plain list
   equality (`unify`'s `TRecord` case, typecheck.ml:2125–2137) rather than a
   set/row comparison — `{ y: 2, x: 1 }` and `{ x: 1, y: 2 }` are the identical
   type. There is no row-polymorphism: a record's exact field set must be known
   (or the base type is an unconstrained `TVar`, in which case field checks are
   deferred entirely — the `EField`/`ERecordUpdate` `TVar` branches, §2 above).
6. **`ERecordUpdate` rejects an absent field STATICALLY, for a concrete base
   type** — this is the type-side half of `core-march.md` §4.2.1's
   interpreter/compiled divergence adjudication. The runtime "no field ... in
   record" error the operational spec discusses is only reachable when the
   base's type is an erased `TVar` (e.g. flowing through a fully polymorphic
   stdlib builtin like `record_from_list`); for any program whose record base
   has a concrete, resolvable `TRecord` shape, a missing-field update is a
   typecheck-time rejection and never reaches eval/codegen at all
   (`reject/t09_record_update_missing_field` is the witness).
7. **No tuple/record arity error text — mismatches fall through to the generic
   unify diagnostic.** Unlike `T-Con`/`P-Con` ("Constructor `C` expects N
   argument(s)..."), a `TTuple` length mismatch has no dedicated message: the
   guarded `unify` case only fires `when List.length ts1 = List.length ts2`
   (typecheck.ml:2122), so a length mismatch instead falls to the catch-all
   `report_mismatch` and renders as a generic `expected \`(τ…)\` but got
   \`(τ…)\`.` (`reject/t08_tuple_arity_mismatch` is the witness).
8. **Atoms are fully type-erased — name AND payload both.** Unlike every other
   construct in this document, `EAtom`/`PatAtom` carry NO information into the
   type system beyond "this is an atom": `t_atom = TCon("Atom",[])` is the
   entire type, for `:ok` and `:count(1,2,3)` alike (T-Atom-0/T-Atom-N, P-Atom,
   §2/§2.2). The payload IS still typechecked on both sides — `EAtom`'s
   arguments via ordinary `infer_expr` (typecheck.ml:4050–4052) and `PatAtom`'s
   sub-patterns via ordinary `infer_pattern` (typecheck.ml:2666–2669) — so a
   malformed payload expression or sub-pattern still errors; only the
   *resulting* payload type(s) are discarded rather than folded into the
   atom's own type or unified against anything. This is exactly the
   mechanism `core-march.md:1354–1359` traces as the root cause of the
   (since-fixed) compiled `Show(Atom)`/`println(:ok)` link bug: an atom
   payload binding (e.g. `msg` in `:error(msg) -> …`) gets no type from the
   atom machinery itself, only from how the branch body later uses it — if
   unused, it stays an unresolved type variable all the way to codegen.
   `t12_atom_payload_and_name_erasure` is the witness for the erasure itself
   (two differently-tagged nullary atoms, `:red`/`:blue`, both typecheck as
   plain `Atom` from the two arms of one `if`); no dedicated `reject/`
   program exists because there is no atom-specific way to violate this —
   every atom, by construction, already has the one type this rule assigns.
9. **Exhaustiveness and redundancy are Warnings, not typing errors — the
   single most brittle fact in this document.** `check_exhaustiveness`
   (typecheck.ml:3159–3185) and `check_redundant_arms` (typecheck.ml:3131–3155)
   both construct their diagnostics with `severity = Warning` (typecheck.ml:
   3143/3172/3179 — every branch of both functions), and `--check`'s exit code
   (`bin/main.ml:819–821`, `has_user_errors`) filters strictly on `severity =
   Error`. **A `match` that does not cover every constructor of its scrutinee's
   type is WELL-TYPED — `--check` exits 0, emitting only a `-- WARNING --`
   block.** This is easy to get backwards: it is tempting to assume a
   "non-exhaustive match" program belongs in `reject/`, but doing so would
   produce a `reject/` program that this corpus's own harness (`check_types.sh`,
   §3, keyed on exit code) would immediately flag as wrong — the harness would
   see exit 0 and mark it "should be rejected but typechecked." Compounding
   this: exhaustiveness checking is SKIPPED OUTRIGHT (not run at all, not even
   as a Warning) the moment ANY branch of the match has a guard
   (typecheck.ml:3161–3164, "coverage becomes undecidable") — so a guarded
   match gets no exhaustiveness signal whatsoever, Warning or Error.
   `accept/t14_nonexhaustive_match_still_typechecks` is the witness: a 2-ctor
   `Hue = Rood | Bloo` matched with only a `Rood` arm exits 0 with the exact
   message "Non-exhaustive pattern match — missing case: Bloo".
10. **Guards are ⇐-checked against `Bool` in the pattern-extended
    environment, at both typing entry points.** `infer_match`
    (typecheck.ml:4280–4284) and the `EMatch` arm of `check_expr`
    (typecheck.ml:4192–4196) both check `br.branch_guard` (when present)
    against `t_bool` in `env'` — Γ already extended with the SAME branch's own
    pattern bindings — so a guard can read variables its own pattern just
    bound (`P(a, b) when a == b -> …`, the reachable substitute for the
    unparseable `PatAs`, per finding 11 below and `core-march.md:1247`). A
    non-Bool guard is rejected with "Match guards must be Bool."
    (`reject/t10_guard_not_bool` is the witness) — the exact same `RBuiltin`
    reason-string shape `ECond`'s non-Bool-condition rejection uses (finding
    12), just with different wording.
11. **`PatAs` has a live, correct `infer_pattern` arm (typecheck.ml:2682–2685)
    but is unreachable from surface grammar — confirmed fresh for this task,
    zero `PatAs` occurrences in `parser.mly`.** The lexer's `AS` token is used
    in exactly one grammar production, `soft_lower_name` (parser.mly:1361),
    which lets `as` be spelled as an ordinary variable/binding name — it does
    NOT build an as-pattern. This is the same disposition `core-march.md`
    already gives `PatAs` operationally (§4.3.1) and the same shape as this
    document's pre-existing `PatRecord` finding: real code, unreachable input.
    No `(P-As)` rule is stated (§2.2).
12. **`ECond` (`match do c -> b … end`) checks every condition against `Bool`
    and unifies every body into ONE result type anchored at the FIRST arm**
    (T-Cond, §2.1a, typecheck.ml:4020–4036) — but, unlike `EMatch`, never runs
    exhaustiveness/redundancy checking at all (neither function is called from
    the `ECond` arm). This matches the operational finding that `ECond` is NOT
    statically total (`core-march.md:492–498`): an all-false chain typechecks
    with no Warning and panics at runtime unless closed off with a final
    `true ->`/`_ ->` arm. A non-Bool condition is rejected with "Each condition
    in `match do` must be Bool." (`reject/t11_econd_condition_not_bool` is the
    witness); a branch-body mismatch falls through to the same "All branches of
    a match must have the same type." text `EMatch` uses (no `ECond`-specific
    branch-mismatch message exists).

## 5. What this validated, and what's next

**Validated:** the type-side methodology works end-to-end — the bidirectional HM
judgment is transcribable arm-for-arm from `typecheck.ml`, the `--check`-based
`accept/reject` harness is a workable conformance anchor (with exact-error-message
pinning), and the doc format (judgment → cited rules → accept/reject table) is a
replicable template. `check_types.sh` is the committed anchor; it belongs in a
slow CI lane alongside `@oracle`.

**Task 1 added:** ADT constructor + `match` typing — (T-Con),
(T-Match), and the pattern-typing relation `Γ ⊢ p : τ ⊣ Γ'` for `PatCon`/
`PatVar`/`PatWild`/`PatLit` (§2, §2.2), transcribed from `instantiate_ctor`
(typecheck.ml:2387), the `ECon` arm of `infer_expr` (typecheck.ml:3737),
`infer_match` (typecheck.ml:4273), and `infer_pattern` (typecheck.ml:2566).

**Task 2 (this slice) added:** tuples + records typing — (T-Tuple), (T-Record),
(T-Field), (T-Update), and the pattern-typing relation extended with
`(P-Tuple)` (§2, §2.2), transcribed from the `ETuple`/`ERecord`/`EField`/
`ERecordUpdate` arms of `infer_expr` (typecheck.ml:3851, 3855, 3900, 3860) and
the `PatTuple` arm of `infer_pattern` (typecheck.ml:2582). `PatRecord` was
confirmed unreachable from surface syntax (zero `parser.mly` occurrences,
matching `core-march.md`'s prior finding for the operational side), so no
`(P-Record)` rule was invented — only a one-line note pointing at its
(unreachable) `infer_pattern` arm (typecheck.ml:2671). The static/runtime
missing-field-on-update divergence adjudicated operationally in
`core-march.md` §4.2.1 is now also pinned on the type side: a concrete-base
missing-field update is a typecheck-time rejection (T-Update, §2), and the
runtime error path is only live for an erased `TVar` base.

**Task 3 (this slice) added:** atoms typing — (T-Atom-0), (T-Atom-N), and the
pattern-typing relation extended with `(P-Atom)` (§2, §2.2), transcribed from
the `EAtom` arm of `infer_expr` (typecheck.ml:4050–4052) and the `PatAtom` arm
of `infer_pattern` (typecheck.ml:2666–2669). The key finding: March's type
layer collapses EVERY atom — nullary or payload-carrying, any tag — to the
one monomorphic `Atom` type; the tag name and payload are typechecked (for
their own sub-expression/sub-pattern errors) but their types are discarded
rather than folded into the atom's type. This is the same erasure
`core-march.md:1354–1359` already traces as the root cause of a (since-fixed)
compiled `Show(Atom)` bug. No `reject/` program was added: because every atom
already has the one type this rule assigns, there is no atom-specific way to
violate it (§3, §4 finding 8).

**Task 4 (this slice) added:** the pattern-typing relation `Γ ⊢ p : τ ⊣ Γ'` is
now presented as COMPLETE (§2.2 preamble) — every `infer_pattern` arm is
accounted for, with `PatAs` newly confirmed unreachable-from-surface-grammar
(zero `parser.mly` occurrences, verified fresh; the `AS` token's one grammar
use is in `soft_lower_name`, letting `as` be a variable name, not an
as-pattern) and documented that way rather than given a `(P-As)` rule,
mirroring `PatRecord`'s existing disposition. Also added: (T-Guard) — the
`when g` clause is ⇐-checked against `Bool` in the pattern-extended
environment, at both `infer_match` (typecheck.ml:4280–4284) and the `EMatch`
arm of `check_expr` (typecheck.ml:4192–4196); (T-Cond) — the scrutinee-less
`match do c -> b … end` boolean chain, transcribed from the `ECond` arm of
`infer_expr` (typecheck.ml:4020–4036), each condition ⇐ `Bool`, every body
unified into one result type anchored at the first arm. **The load-bearing
finding this slice pins:** `check_exhaustiveness`/`check_redundant_arms`
(typecheck.ml:3159–3185 / 3131–3155) both report at `severity = Warning`
(never `Error`), and `--check`'s exit code (`bin/main.ml:819–821`) filters
strictly on `Error` — so a non-exhaustive `match` (or a redundant arm)
**typechecks**, exit 0, with only an advisory `-- WARNING --` block. This
governs the conformance corpus directly:
`accept/t14_nonexhaustive_match_still_typechecks` deliberately covers only one
arm of a 2-ctor ADT and is CORRECT to sit in `accept/`, not `reject/` — a
non-exhaustive match can never be used to construct a passing `reject/`
program in this harness, since `check_types.sh` (§3) keys purely on the
process exit code. Exhaustiveness checking is also skipped outright (not
merely downgraded) whenever any branch carries a guard (typecheck.ml:
3161–3164). Two new `reject/` programs exercise genuinely new-to-this-task
error text: a non-Bool guard ("Match guards must be Bool.",
`reject/t10_guard_not_bool`) and a non-Bool `ECond` condition ("Each condition
in `match do` must be Bool.", `reject/t11_econd_condition_not_bool`) — neither
restates an earlier task's reject message. `check_types.sh`: 26/26 (15 accept,
11 reject), exit 0.

**Next (widening slices, each like this one):** the interface/impl resolution
that discharges the `Num`/`Eq` constraints (§2.1) — the richest and most
bug-prone part, and the type-side complement to the operational core.
Together, `core-march.md` (operational) + this document (typing) are
**Level-1 for the Core March fragment**.
