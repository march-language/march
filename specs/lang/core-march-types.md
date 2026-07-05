# Core March — Static Semantics reference v1 (core fragment complete)

**Date:** 2026-07-05
**Status:** Reference v1 — the Core March **type system**'s core fragment is
now complete end-to-end, the companion to the operational semantics in
`core-march.md`. Built incrementally as a walking skeleton (Tasks 1–6, see §5
for the per-task provenance) and consolidated into this single reference by
Task 7 — assembly + versioning only, no new typing rules were added in this pass.
**Companion:** `specs/lang/core-march.md` (operational semantics — "what programs
mean"). This document is "which programs are well-typed."
**Depends on:** `specs/2026-07-04-language-specification-roadmap-design.md` §4.3.

---

## 0. What this is (and is not)

`core-march.md` documented the interpreter's *operational* rules. This document
documents the *typechecker's* rules — the `Γ ⊢ e : τ` judgment — for the core
fragment: literals, variables, `let` (with generalization), lambda,
application, the `+`/`==` primitives, `if`, **ADT constructors and `match`**
(Task 1), **tuples and records** (Task 2), **atoms** (Task 3), **match guards
and scrutinee-less `match do` (`ECond`)** (Task 4), **local recursive
functions (`ELetFn`)** (Task 5), and **the interface-constraint model**
(`Num`/`Eq`/`Ord`/`Show` discharge, §2.1/§2.1a/§2.1b) and the boolean
primitives `&&`/`||`/`not` (Task 6). Task 7 (this pass) added no new typing
rules — it re-titled/re-scoped this document from "walking skeleton, first
vertical slice" to "reference v1, core fragment complete," unified §2 into one
rule set grouped by construct, collected the accumulated findings into a
single §4 subsection, refreshed the deferred list against the roadmap's
Phase-2b/3 queue, and wired `check_types.sh` into a CI lane (see
`specs/lang/types/INDEX.md`). Same discipline as the operational skeleton:
**every rule is transcribed arm-for-arm from `lib/typecheck/typecheck.ml` and
cited by line**, and a conformance corpus keeps it honest.

The conformance mechanism differs from the operational side. There is only **one**
typechecker (it runs before both `eval` and `--compile`), so there is nothing to
*differentially* diff. Instead the anchor is the compiler's own `--check` mode
(`march --check file.march`: exit 0 = well-typed, exit 1 + a `-- ERROR --`
diagnostic = rejected). The corpus (§3) is split into **`accept/`** programs
(must typecheck) and **`reject/`** programs (must be rejected *with a specific
error message*). This catches both a spec that misdescribes the typechecker and a
typechecker regression.

**Deferred to later phases** (the roadmap's Phase-2b/3 queue, §6): user-defined
`impl`/interface DECLARATION syntax and superclass/coherence rules beyond the
four built-in interfaces (this document covers how a `Num`/`Eq`/`Ord`/`Show`
constraint is DISCHARGED against the built-in seed table, not the full
generality of user-declared interfaces — see §2.1a's scope note), refinements
(z3-discharged), the capability lattice (`lib/caps/`), and effects — see §6 for
the full deferred-set breakdown and its roadmap citations.

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
discharged separately from unification. The constraint type itself
(`typecheck.ml:128–133`):

```
type constraint_ =
  | CNum of ty                  -- t must be Int or Float (arithmetic)
  | COrd of ty                  -- t must be Int, Float, or String (LEGACY — see §2.1b, dead)
  | CInterface of string * ty   -- t must implement the named interface (via env.impls)
  | CADTBound of string * ty    -- t must be a constructor of the named ADT (bounded type params, §2.1b)
  | CTNatBound of ty            -- t must be a type-level Nat (bounded type params, §2.1b)
```

and the scheme type (`typecheck.ml:139–141`): `Poly of int list * constraint_
list * ty` — the quantified variable ids, the constraint list `C̄`, and the
body type. `env.pending_constraints : constraint_ list ref`
(`typecheck.ml:445`) is the accumulator every constraint is pushed onto as it
arises; it is drained (and reset to `[]`) by `discharge_constraints` (§2.1a)
at each declaration boundary.

Two HM operations move between `τ` and `σ`, and are where a constraint
respectively **arises** and is **quantified away**:

- **`instantiate level env sch` (:901–937)** — `∀ᾱ[C̄].τ` → a monotype by
  replacing each quantified `αᵢ` with a *fresh unification variable at the
  current level* (:904, `subst`); each constraint in `C̄` has its own type
  argument substituted the same way (:929–934, `inst_cs`) and the resulting,
  freshly-instantiated constraints are prepended onto
  `env.pending_constraints` (:936) — **this is the CREATION site**: every
  occurrence of a constraint-carrying variable (`+`, `==`, `<`, `show`, …,
  §2.1) pushes a fresh obligation here, exactly like `EVar`'s ordinary T-Var
  instantiation (§1 above) — constraint creation is not a special case of
  `EVar`/T-Var, it is a side effect woven into the SAME function.
- **`generalize level τ` (:845–895)** — quantify every unbound unification
  variable in `τ` whose level `> level` (the ones "born inside" the current
  `let`), yielding a `Poly` scheme. Uses a **level** discipline (each `let`
  RHS is typed at a bumped level via `enter_level`) instead of a global
  free-variable scan. **Load-bearing subtlety:** `generalize` ALWAYS returns
  `Poly (ids, [], copy ty)` — an EMPTY constraint list (:894) — regardless of
  what constraints are pending; it also allocates **fresh, isolated `TVar`
  refs** for each quantified id (:866–869, "so a later function body can
  unify the original TVar" without corrupting an already-stored scheme) that
  share only the *integer id*, not the ref cell, with whatever `TVar` a
  constraint elsewhere still points at. `generalize` itself never attaches a
  constraint to the scheme it builds — callers that want a constraint to
  survive generalization must re-attach it explicitly afterward (this is
  exactly what `check_fn`'s `when`-clause handling does, and where it can go
  wrong — see the §4 finding on `when`-bound constraints below).

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
          --   a syntactic value: March has NO value restriction (see §4 finding 1).
          -- ⚠ KNOWN TYPING DIVERGENCE — a `let`'s OWN type annotation
          --   (`let x : T = e₁`, parsed into `Ast.bind_ty`) is never consulted
          --   by this arm: `grep -c bind_ty lib/typecheck/typecheck.ml` = 0.
          --   τ₁ is inferred from `e₁` alone and the annotation is silently
          --   discarded — NOT a soundness hole (a later use of `x` at the
          --   wrong type is still caught via ordinary unification), but
          --   `let x : Int = "foo"` typechecks at exit 0 instead of being
          --   checked against `Int` at the binding site. See §4.1 finding 16
          --   and `specs/todos.md` ("Compiler: Type System") for the full
          --   writeup and fix direction.

(T-LetFn) β fresh (at env.level — NO enter_level bump, unlike T-Let)    typecheck.ml:4373
          Γ_self = Γ, f:β                                               typecheck.ml:4374
          Γ_inner, τ̄ = bind_lam_params(Γ_self, params)                  typecheck.ml:4375 (§2 T-Abs machinery)
          Γ_inner ⊢ e_b ⇒ τ_b                                           typecheck.ml:4386
          τ_ret = if no return annotation then τ_b                      typecheck.ml:4387–4394
                  else (ann = surface_ty(annotation);
                        unify(τ_b, ann); ann)
          τ_arrow = τ̄ → τ_ret                                           typecheck.ml:4395
          unify(β, τ_arrow)                                             typecheck.ml:4396
          σ_f = generalize(env.level - 1, τ_arrow)                      typecheck.ml:4397
          Γ, f:σ_f ⊢ (rest of block) ⇒ τ₂                                typecheck.ml:4398–4399
          ────────────────────────────────────────────────────────────────
          Γ ⊢ EBlock(ELetFn(f, params, ret_ann?, e_b) :: rest) ⇒ τ₂      typecheck.ml:4371–4399 (infer_block arm)
          -- THE RECURSION KNOT: `f` is bound in Γ_self to a bare, fresh
          --   unification variable `β` (`Mono β`, NOT generalized) BEFORE
          --   `e_b` is typed (typecheck.ml:4373–4374). Any occurrence of
          --   `f(...)` inside `e_b` resolves via T-Var/`instantiate` on a
          --   `Mono` scheme — `instantiate` returns a `Mono` type UNCHANGED,
          --   no fresh copy — so every recursive call inside the body shares
          --   the SAME `β`/`τ_arrow` as the function itself: `f` is
          --   MONOMORPHIC inside its own body, exactly like ML `let rec`
          --   (standard HM — this is what makes polymorphic recursion a type
          --   error rather than silently unsound; witness below).
          -- `f`'s param types `τ̄` come from `bind_lam_params` — THE SAME
          --   helper T-Abs uses (§2) for an ordinary lambda: one fresh
          --   unification variable per param, upgraded to the param's own
          --   annotation (if present) by `bind_lam_param`'s `p.param_ty,
          --   ann_ty` match (typecheck.ml:4413–4420) — `ELetFn` params
          --   support the identical `x : T` annotation syntax T-Abs params
          --   do, checked the identical way; no ELetFn-specific param logic
          --   exists beyond re-recording each param's span in `env.type_map`
          --   (typecheck.ml:4383–4385, a bookkeeping fix so `lower.ml`'s
          --   monomorphizer sees each param's real type instead of a shared
          --   dummy-span placeholder — noted in-line as fixing a real
          --   `Map.from_list`-inner-`go` monomorphization bug).
          -- GENERALIZATION HAPPENS, BUT ONLY *AFTER* THE BODY IS FULLY
          --   TYPED, and BEFORE the block's `rest` is typed — never inside
          --   `e_b` itself. `generalize (env.level - 1) arrow_ty`
          --   (typecheck.ml:4397) quantifies every unbound TVar whose level
          --   is `> env.level - 1`. Because the `ELetFn` arm does **not**
          --   call `enter_level` (contrast T-Let's `env_rhs = enter_level
          --   env`, typecheck.ml:4305, which bumps to `env.level + 1` before
          --   typing the RHS) — `β`, every param TVar, and every TVar born
          --   while typing `e_b` are all created at the SAME level,
          --   `env.level` — the threshold is shifted down by one
          --   (`env.level - 1` rather than T-Let's plain `env.level`) to
          --   land on exactly that generation. This is a DIFFERENT mechanism
          --   from T-Let's (a shifted threshold instead of a level bump) that
          --   arrives at the same generalize-after-the-binding-completes
          --   shape; `t17_letfn_generalized_after_block` is the witness that
          --   it actually fires (`id_rec` used at both `Int` and `String` in
          --   the rest of the block).
          -- the visible-name/visible-type split, precisely: inside `e_b`,
          --   `f` resolves to `Mono β` (monomorphic, pre-generalization);
          --   in `rest` (the block continuation) and everywhere after,
          --   `f` resolves to `σ_f = generalize(env.level - 1, τ_arrow)` — a
          --   `Poly` scheme if `τ_arrow` contains any level-`env.level`
          --   TVars still unbound after the body was checked, else the same
          --   `Mono τ_arrow` unchanged (`generalize` returns `Mono ty` when
          --   its `ids` accumulator is empty, typecheck.ml:864).
          -- shares its "bind self at a fresh monotype, generalize after"
          --   SHAPE with `check_fn`'s handling of a top-level recursive `fn`
          --   (typecheck.ml:4553–4574, the `self_ty`/`env_rec` setup) — but
          --   NOT its level mechanics: `check_fn` DOES call `enter_level`
          --   (typecheck.ml:4545, `env' = enter_level env`) before binding
          --   the self-reference, so a top-level recursive fn is generalized
          --   via the ordinary `generalize env.level` shape once its clause
          --   is fully checked; `ELetFn` gets the same end result via the
          --   `env.level - 1` compensation instead, because it deliberately
          --   skips the level bump (no comment in the code states why the
          --   two diverge here; both converge on "generalize the completed
          --   arrow type before the caller's continuation sees it").
          -- POLYMORPHIC RECURSION IS REJECTED, as standard HM predicts: a
          --   local `fn go(x) do let a = go(1); let b = go("s"); x end`
          --   (two recursive self-calls at DIFFERENT argument types inside
          --   `go`'s own body) fails to typecheck — `go("s")`'s `String`
          --   argument conflicts with the `Int` already unified onto `β`'s
          --   param slot by `go(1)`, reported as an ordinary T-App argument
          --   mismatch (`expected `Int` but got `String`.`) — captured live
          --   for this task, not committed as a corpus program (it would
          --   duplicate `reject/t01`'s mismatch shape rather than add new
          --   coverage; see §3 note on `t12_letfn_ret_annot_conflict` for the
          --   reject program that WAS added).
          -- a declared return-type annotation is CHECKED (⇐, via `unify`),
          --   not just recorded — `t_b`'s inferred type must unify with the
          --   annotation (typecheck.ml:4392) — so a local recursive fn's
          --   return annotation is exactly as load-bearing as a top-level
          --   fn's; `reject/t12_letfn_ret_annot_conflict` is the witness (a
          --   `fn go(k) : Int` whose body — self-consistent across the
          --   recursive call, inferring `String` throughout — conflicts with
          --   the declared `Int`).
          -- ⚠ MINOR DIAGNOSTIC-QUALITY QUIRK found while building the reject
          --   witness above (not a false accept/reject, does not affect this
          --   corpus's pass/fail): the SAME mismatch is reported TWICE with
          --   IDENTICAL text when a return annotation conflicts with a
          --   self-recursive body. The `unify body_ty expected`
          --   (typecheck.ml:4392) reports it once directly; separately, the
          --   in-body recursive call `go(...)` already unified `β` (via
          --   T-App's `TVar _` case, typecheck.ml:4253–4259) to
          --   `τ̄ → body_ty`, so the LATER `unify β arrow_ty`
          --   (typecheck.ml:4396, `arrow_ty`'s return slot = the annotation)
          --   independently re-discovers the identical conflict through
          --   `β`'s already-bound arrow. `--check-json` on
          --   `t12_letfn_ret_annot_conflict` shows two byte-identical
          --   `"message":"expected \`Int\` but got \`String\`."` diagnostics
          --   at the same span. Cosmetic (both `check_types.sh`'s
          --   substring-containment test and a human reading `--check`'s
          --   text output see the right message either way), and does NOT
          --   reproduce for a top-level `fn go(n) : Int` with the identical
          --   shape (`check_fn`'s single `unify` against `fn_ret_ty` reports
          --   once, with a BETTER message pointing at the specific offending
          --   branch — "This is the declared return type of `go`.") — so
          --   this is `ELetFn`-arm-specific: its two independent `unify`
          --   calls (the ret-annotation check, and the final self/arrow
          --   reconciliation) can both observe the same already-manifested
          --   conflict when the conflict flows through the self-reference.
          --   Not fixed here (docs-only task); noted in `specs/todos.md`.
          -- cf. operational (E-LetFn), core-march.md:650–663 — eval's
          --   `ELetFn` arm ties the SAME recursive knot at the VALUE level,
          --   with a mutable `env_ref` back-patched AFTER the closure is
          --   built so the closure's deferred environment read sees itself
          --   (core-march.md:679–702's "why ELetFn needs a mutable ref");
          --   this rule is the type-level analog — no mutation is needed
          --   here because a unification variable `β` can be bound (not
          --   read-then-fixed) after the fact: `f`'s TYPE is established by
          --   binding a placeholder `β` first and unifying it once `e_b` is
          --   fully typed, the same "placeholder now, resolve later" shape
          --   the operational side needs a `ref` for, but achieved here via
          --   ordinary unification instead of environment mutation.
          -- like T-Let (and unlike a bare, block-final `ELetFn` — see the
          --   `EBlock [ELetFn ...]` case at typecheck.ml:4101, a distinct
          --   arm reachable when the local fn is the LAST/ONLY statement of
          --   a block, which types the SAME way but simply returns
          --   `arrow_ty` as the block's value instead of binding `f` into an
          --   env for further statements to see — mirroring
          --   core-march.md:672–677's identical operational split), the
          --   binding here is visible to `rest`, i.e. the REST of the
          --   enclosing block, not just `e_b`.

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
(`accept/t14_nonexhaustive_match_still_typechecks` is the witness). Under
`march --check` — the mode `check_types.sh` uses (§3) — the program **exits 0
silently**: the `--check` printer only renders `severity = Error` diagnostics
for user files (`bin/main.ml:819–824`), so the exhaustiveness `Warning` is
computed but NOT displayed. The rendered `-- WARNING --` block ("Non-exhaustive
pattern match — missing case: Bloo") is emitted only on the *run/compile* paths
(e.g. a plain `march file.march`, which prints the block to stderr and still
exits 0). Either way the exit code is 0, which is all the harness keys on. A
non-exhaustive match can NEVER be used to construct a `reject/` program in this
corpus, because `check_types.sh` keys purely on the process exit code (§3) and a
Warning never changes it.

This is the type-side counterpart of `core-march.md`'s §4.3
`Match_failure`/panic rule: an accepted-but-non-exhaustive `match` is exactly
the program shape that can raise a runtime "no matching branch" error
(interpreted) or panic (compiled) on an uncovered value at RUNTIME — the
Warning is the typechecker's only static signal that this is possible, and it
is advisory, not enforced.

### 2.1 Primitive typing (δ-typing)

`+`, `-`, `*`, `/`, `negate`, `<`, `>`, `<=`, `>=`, `==`, `!=` are **not**
magic — they are ordinary variables bound in the base environment
(`builtin_bindings`, `typecheck.ml:1195–1288`) to **interface-constrained
polymorphic schemes**, resolved and instantiated exactly like any `EVar`
(T-Var, §1):

```
(δT-Add)  +, -, *, / : ∀a [Num a]. a → a → a       typecheck.ml:1229–1232  (poly1_num)
(δT-Neg)  negate      : ∀a [Num a]. a → a          typecheck.ml:1234       (poly1_num)
(δT-Ord)  <, >, <=, >= : ∀a [Ord a]. a → a → Bool  typecheck.ml:1241–1244  (poly1_iface "Ord")
(δT-Eq)   ==, !=      : ∀a [Eq a]. a → a → Bool    typecheck.ml:1248–1249  (poly1_iface "Eq")
```

So `2 + 3` instantiates `a := Int` and pushes a pending `CNum Int` obligation;
`x == y` instantiates `a` to the operand type and pushes `CInterface("Eq",
a)`. This is *ad-hoc polymorphism via interfaces layered on HM*, not
overloading resolved by the parser — a genuinely load-bearing fact (a program
`1 + "x"` fails because `+`'s two args must share one `a`, and `Int`/`String`
don't unify, **not** because `+` is "the Int operator"). `%` (Int-only
modulo), `+.`/`-.`/`*.`/`/.` (the Float-only dotted arithmetic operators) are
**not** constrained at all — `Mono` schemes over concrete `Int`/`Float`
(`typecheck.ml:1233, 1236–1239`), exactly like ordinary monomorphic
functions; only the OVERLOADED (works-on-either-Int-or-Float, or
works-on-any-Ord/Eq-type) forms carry a constraint.

`show`, `eq`, `compare`, `hash` (and their qualified forms `Show.show`,
`Eq.eq`, `Ord.compare`, `Hash.hash`) are the same shape, one level up: each is
built by `mk_iface_method_scheme` (`typecheck.ml:1171–1173`,
`Poly([a], [CInterface(iface,a)], mk_ty a)`) and registered in
`builtin_interface_bindings` (`typecheck.ml:1180–1190`):

```
(δT-Show) show : ∀a [Show a]. a → String           typecheck.ml:1171, 1183
```

`println(x)`'s stdlib-level polymorphism over `Show` (`stdlib/prelude.march`,
outside this fragment) ultimately bottoms out at this same `show` binding.

**Two constraint kinds, two different discharge strategies — the load-bearing
distinction of this task.** Despite both being written `∀a [Iface a]. …` in
the rules above, `Num` and `Ord`/`Eq`/`Show` are checked by GENUINELY
DIFFERENT code paths inside `discharge_constraints` (§2.1a below):

- **`CNum`** (`+`/`-`/`*`/`/`/`negate`) is checked by a HARDCODED match on the
  concrete type's `TCon` name — `"Int"` or `"Float"`, nothing else, ever
  (`typecheck.ml:4952–4956`). There is no `env.impls` lookup, no user-facing
  `impl Num(T)` declaration form exists, and `Num` is not even a member of
  `env.interfaces` (confirmed live: `fn f(a,b) when Num(a) do a + b end`
  rejects with `` I don't know a constructor called `Num`. `` — `Num` cannot
  be named in a `when`-clause at all). `Num` is a CLOSED, compiler-builtin
  set of exactly two types.
- **`Ord`/`Eq`/`Show`/`Hash`** (`<`/`>`/`<=`/`>=`, `==`/`!=`, `show`, `hash`)
  are checked via `CInterface(iface_name, t)` against `env.impls` — an
  OPEN, extensible table seeded with built-ins (§2.1b) but extensible by any
  user `impl Ord(MyType) do ... end` block (`typecheck.ml:6915–7050`, the
  `DImpl` arm, which calls `register_impl_shape`-style insertion into
  `env.impls` — see §2.1b for the exact seed list).

**A THIRD constraint kind, `COrd`, exists in the type but is DEAD — not used
by any live scheme.** `constraint_`'s `COrd` variant (`typecheck.ml:130`) and
its constructor helper `_poly1_ord` (`typecheck.ml:1212–1214`, underscore-
prefixed to suppress the unused-value warning) are fully implemented —
`discharge_constraints` has real logic for `COrd` (`typecheck.ml:4952,
4959, 4966`, "String is Ord" / "COrd unresolved — leave polymorphic") —
but `_poly1_ord` is never called anywhere in `builtin_bindings`: `<`/`>`/`<=`/
`>=` all use `poly1_iface "Ord"` → `CInterface("Ord", a)` (confirmed above),
NOT `COrd`. This is a real, if harmless, piece of dead code in the live
compiler: the comment at `typecheck.ml:1211` ("legacy COrd path") documents
the fact — `Ord` migrated from a `CNum`-style hardcoded-type-name check to
the general `CInterface`/`env.impls` mechanism at some point, and the old
path was left in place rather than deleted. No March program can ever
exercise a live `COrd` constraint.

### 2.1a Constraint discharge: `(T-Discharge)`

`discharge_constraints env span` (`typecheck.ml:4932–5049`) drains
`env.pending_constraints`, resetting it to `[]` when done (:5049), and is
called at every **declaration boundary** — NOT after every expression or
every call to `+`/`==`/etc.:

```
discharge_constraints env sp   -- Ast.DFn arm of check_decl     typecheck.ml:6468
discharge_constraints env sp   -- Ast.DLet arm of check_decl     typecheck.ml:6477
discharge_constraints env_with_impl _sp  -- Ast.DImpl arm (both branches)  typecheck.ml:7045, 7048
```

So a constraint created while typing a `DFn`'s body (via `instantiate`, §1)
sits on `env.pending_constraints` until that WHOLE function's `check_fn` call
returns, then is resolved all at once by the single `discharge_constraints`
call following it. This is why the "String does not implement Num" error
(below) is reported at the `fn`'s own span, not at the `+` call site's span —
the constraint is bound to a span only at the discharge call, which uses the
DECLARATION's span (`sp`/`fn_span`), not the constraint's point of origin.

```
(T-Discharge)  ∀ c ∈ !(env.pending_constraints):                         typecheck.ml:4932–5049 (discharge_constraints)
               match c with
               | CNum t | COrd t                                          typecheck.ml:4952–4969
                 → repr t = TCon("Int"|"Float", [])         ⇒ OK (both kinds)
                 → repr t = TCon("String", [])               ⇒ OK if COrd, ERROR if CNum:
                     "String does not implement Num (only Int and Float do)."
                 → repr t = TVar _ (still unresolved)         ⇒ CNum DEFAULTS the var
                     to Int (`r := Link (TCon ("Int", []))`, :4946); COrd
                     leaves it polymorphic (no-op, :4947)
                 → repr t = anything else concrete            ⇒ ERROR:
                     "`<τ>` does not implement <Num|Ord>."
               | CInterface (iface, t)                                    typecheck.ml:4970–5010
                 → repr t = TVar _ (still unresolved)         ⇒ skip ("cannot check yet")
                 → repr t = concrete τ, ∃ impl_ty ∈ env.impls[iface]
                     with impl_matches_ty impl_ty τ            ⇒ OK
                 → else, if τ is an anonymous TRecord and iface has EXACTLY
                     ONE method shaped `a → T` matching one of τ's fields
                     by name+type                              ⇒ OK (record
                     field auto-satisfy, :4962–4990 — a NAMED TCon type
                     never auto-satisfies this way, only a bare TRecord)
                 → else                                        ⇒ ERROR:
                     "`<τ>` does not implement interface `<iface>`.
                      Add `impl <iface>(<τ>) do ... end` to provide an
                      implementation."
               | CADTBound/CTNatBound (out of §2.1's Num/Eq/Ord/Show scope —
                 these back `fn f[s : Bound](...)` explicit type-parameter
                 bounds, a separate feature; see typecheck.ml:5011–5047)
               ────────────────────────────────────────────────────────────
               each satisfied constraint is silently dropped; each violated
               one calls Err.error at `span` (the DECLARATION's span, not the
               constraint's origin site) and the constraint is otherwise
               DISCARDED either way (there is no "sticky" re-check later)
               -- Deduplication: `CInterface` constraints on the SAME
               --   (iface, pp_ty τ) pair are checked only ONCE per
               --   `discharge_constraints` call — a `seen` Hashtbl keyed on
               --   `iface ^ ":" ^ pp_ty τ` skips repeats (:4934–4947,
               --   "10 calls to Storage.get on the same storage variable").
               --   `CNum`/`COrd` are NOT deduplicated this way (the
               --   `dominated` check only special-cases `CInterface`,
               --   :4939–4949) — harmless, since re-checking `CNum Int`
               --   twice is idempotent, just slightly redundant work.
               -- An UNRESOLVED constraint on a still-unbound type variable
               --   is NOT an error — it is either (a) silently DEFAULTED
               --   (CNum → Int, unconditionally, with no user control) or
               --   (b) left polymorphic and simply DROPPED once
               --   `pending_constraints` is reset to `[]` (:5049) — for
               --   CInterface and COrd, "cannot check yet" (:4973, :5014,
               --   :5041) means the constraint is skipped, not deferred:
               --   nothing carries it forward to a LATER discharge point.
               --   Whether that variable's eventual concrete type actually
               --   satisfies the constraint is never re-verified UNLESS the
               --   variable is later specifically re-constrained by another
               --   instantiate call before its own enclosing declaration's
               --   discharge point — see the §4 finding on `when`-bound
               --   constraints silently not propagating to callers, which is
               --   the direct consequence of this "check once, at THIS
               --   declaration's boundary, then discard" design.
```

**Live-verified messages** (re-run for this task, `march --check`, exact text):

- `1 + "x"` (direct): actually does **NOT** produce the Num message — `+`'s
  T-App argument unification (`a := Int` pinned by the first arg) conflicts
  with `"x" : String` in argument position #2 BEFORE `discharge_constraints`
  ever runs, giving the ordinary unify-mismatch headline `` expected `Int`
  but got `String`. `` (same shape as `reject/t01`). To reach the
  **CNum-specific** message, BOTH operands must already unify to one
  non-Num type with no earlier unify conflict — e.g. `let x = "a"; let y =
  "b"; x + y` (both `String`, agree with each other, only `+`'s OWN `Num`
  constraint is violated) gives, verbatim:
  ```
  String does not implement Num (only Int and Float do).
  ```
  reported at the enclosing `fn`'s span (per the discharge-at-declaration-
  boundary rule above), not at the `x + y` sub-expression's span.
- `Bool < Bool` (an `Ord` violation — `Bool` has no `Ord` impl, §2.1b) or a
  bare 0-arg ADT value compared with `<` (`type Hue = Rood | Bloo; Rood <
  Bloo`) both give the `CInterface` no-impl shape, verbatim (ADT case):
  ```
  `Hue` does not implement interface `Ord`.
  Add `impl Ord(Hue) do ... end` to provide an implementation.
  ```
- `show(f)` where `f : Int -> Int` (a function value — no `Show` impl for
  `TArrow`, §2.1b) gives, verbatim:
  ```
  `Int -> Int` does not implement interface `Show`.
  Add `impl Show(Int -> Int) do ... end` to provide an implementation.
  ```

### 2.1b Built-in instances, and the boolean primitives `&&`/`||`/`not`

**Which concrete types satisfy which built-in interface** — the seed table
`builtin_impls : (string * ty) list` (`typecheck.ml:1150–1167`), folded into
`env.impls` by `base_env` (`typecheck.ml:1857–1867`, every module starts with
this table pre-loaded):

| Interface | Built-in instances | cite |
|---|---|---|
| `Num` (via `CNum`, hardcoded — not in `env.impls`, no `impl Num` form exists) | **Int, Float only** | `typecheck.ml:4952–4956` |
| `Eq` | Int, Float, String, Bool, Unit, Atom | `typecheck.ml:1152–1153` |
| `Ord` | Int, Float, String | `typecheck.ml:1155` |
| `Show` | Int, Float, String, Bool, Unit, Atom | `typecheck.ml:1162–1163` |
| `Hash` | Int, Float, String, Bool | `typecheck.ml:1165–1166` |

Notably: `Eq` covers **strictly more** types than `Ord` (Bool/Unit/Atom are
equality-comparable but not ordered — there is no built-in `Bool < Bool`, no
`impl Ord(Bool)` shipped, confirmed live above), and `Ord` covers **strictly
fewer** than `Num` overlaps with (`Ord` ⊃ `{Int,Float}` ∩ `Num`, plus
`String`, which `Num` never includes — `String` is Ord but never Num, the
asymmetry the live `1+"x"`-shaped probes above exploit). None of the four
built-in interfaces cover function types (`TArrow`), tuples, records, or
user-defined ADTs out of the box — those all require an explicit `impl …
do … end` (or, for a single-method interface over an anonymous record only,
the field-auto-satisfy path in (T-Discharge) above).

`builtin_interfaces` (`typecheck.ml:1127–1145`) is the companion table
declaring `Eq`/`Ord`/`Show`/`Hash`'s single-method SHAPE (`eq : a → a → Bool`,
`compare : a → a → Int`, `show : a → String`, `hash : a → Int`) so that a
user `impl Eq(MyType) do fn eq(a, b) do ... end end` block has something to
validate its method signature against (`typecheck.ml:6985–7030`, the `DImpl`
arm's per-method check) — `Num` has NO entry in `builtin_interfaces` (it is
not a `CInterface`-based check at all, per §2.1's `Num`-vs-`Ord/Eq/Show`
split), which is exactly why `when Num(a)` cannot be written in a
`when`-clause (§2.1's live-verified finding).

**`&&`, `||`, `not` are NOT interface-constrained — plain monomorphic `Mono`
schemes**, the ordinary (unconstrained) case of T-Var/`instantiate` (§1):

```
(δT-And)  && : Bool → Bool → Bool              typecheck.ml:1245  (Mono, base_env)
(δT-Or)   || : Bool → Bool → Bool              typecheck.ml:1246  (Mono, base_env)
(δT-Not)  not : Bool → Bool                     typecheck.ml:1288  (Mono, base_env)
```

Since these are plain `Mono` bindings, a non-Bool operand is rejected by the
SAME ordinary T-App/unify machinery as any other monomorphic function call
(§2, T-App) — no constraint is ever pushed for them, and
`discharge_constraints` is never involved. There IS a distinctive wrinkle in
the ERROR TEXT, though: `report_mismatch`'s `common_hint` table
(`typecheck.ml:1936–1961`) special-cases the `(provided = Int, required =
Bool)` pairing with a dedicated remediation note (`typecheck.ml:1946–1949`):

```
"March does not coerce Int to Bool.
 Try an explicit comparison, e.g. `x != 0`."
```

so `1 && true` (verified live) reports the ordinary mismatch headline
`expected \`Bool\` but got \`Int\`.` WITH this hint appended — a general
common-mistake decoration on `report_mismatch`, not anything `&&`-specific
(the identical hint fires for `if 1 do … end` or any other Int-where-Bool-
expected site). `&&`/`||` are BINARY, so a non-Bool SECOND argument is
reported independently too (both arg positions are checked against `Bool`
via ordinary T-App per-argument checking, §2) — verified live for `1 || 2`:
two separate diagnostics, one per argument.

**Cross-reference to the operational side:** `core-march.md` §4.4.1
documents `&&`/`||` as **strict, not short-circuiting** at the value level
(both operands are always evaluated) — that is a RUNTIME/evaluation fact
about `δ-And`/`δ-Or`, orthogonal to this section: on the TYPE side `&&`/`||`
are simply fixed `Bool → Bool → Bool` functions like any other binary
builtin, and nothing about their strict evaluation order affects how they
are typed (both operands are ⇐-checked against `Bool` via ordinary left-to-
right T-App argument checking, §2, exactly as strictness evaluates them
left-to-right at runtime — the two properties happen to agree in direction
but are independently-stated facts, one operational and one static).

### 2.1c Conditionals without a scrutinee: `ECond` (`match do c -> b … end`)

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
| `accept/t14_nonexhaustive_match_still_typechecks` | accept | **(T-Match: Exhaustiveness) — the brittleness witness**: a 2-ctor ADT `match` covering only ONE ctor (`Rood`, no `Bloo`, no `_`) | typechecks — `--check` exits 0 **silently** (the exhaustiveness `Warning` is computed but not rendered in `--check`; the `-- WARNING --` "missing case: Bloo" block shows only on run/compile); proves exhaustiveness is advisory, not enforced |
| `accept/t15_econd_chain` | accept | (T-Cond) — a 3-arm `match do` boolean chain (`n > 0`/`n < 0`/`_`), all conditions `Bool`, all bodies `String` | typechecks |
| `reject/t10_guard_not_bool` | reject | (T-Guard) non-Bool guard (`n when n + 1 -> …`, an `Int` guard) | `Match guards must be Bool.` |
| `reject/t11_econd_condition_not_bool` | reject | (T-Cond) non-Bool condition (bare `n -> …` where `n : Int`) | `` Each condition in `match do` must be Bool. `` |
| `accept/t16_letfn_factorial` | accept | (T-LetFn) — a local self-recursive `fn go(k, acc)` (factorial via an accumulator), `go` monomorphic inside its own body, called after the block | typechecks — runs to `120` for `compute(5)` |
| `accept/t17_letfn_generalized_after_block` | accept | **(T-LetFn) generalization** — a local `fn id_rec(x)` used at both `Int` and `String` in the REST of the block (after the `ELetFn`, not inside its own body) | typechecks (proves `ELetFn`'s post-body `generalize(env.level - 1, …)` fires, mirroring `t03_let_poly` for local recursive fns) |
| `reject/t12_letfn_ret_annot_conflict` | reject | (T-LetFn) declared return-type annotation (`fn go(k) : Int`) conflicts with the body's actual (self-recursion-consistent) inferred type `String` | `expected \`Int\` but got \`String\`` |
| `accept/t18_num_constraint_discharged` | accept | (δT-Add, T-Discharge) — `1 + 2` (Int) and `1.0 +. 2.0` (Float, the monomorphic dotted form) both discharge/typecheck cleanly | typechecks |
| `accept/t19_eq_ord_constraint_discharged` | accept | (δT-Eq, δT-Ord, T-Discharge) — `x == y` and `x < y` on two `Int`s discharge `Eq Int`/`Ord Int` against the built-in instances (§2.1b) | typechecks |
| `accept/t20_bool_ops` | accept | (δT-And, δT-Or, δT-Not) — `&&`/`||`/`not` combined over `Bool`-typed comparisons (`>`/`<`/`<=`/`>=`), all monomorphic `Bool → Bool → Bool` / `Bool → Bool` | typechecks |
| `reject/t13_num_no_impl_string` | reject | (T-Discharge, `CNum`) — `x + y` on two `String`s (agree with each other, so no earlier unify conflict; the `CNum` obligation itself is violated at the enclosing `fn`'s discharge point) | `String does not implement Num (only Int and Float do)` |
| `reject/t14_ord_no_impl_adt` | reject | (T-Discharge, `CInterface "Ord"`) — `a < b` on a bare 2-ctor ADT (`Hue = Rood \| Bloo`, no built-in or user `impl Ord(Hue)`) | `` `Hue` does not implement interface `Ord` `` |
| `reject/t15_and_non_bool_operand` | reject | (δT-And) — `1 && true`, an `Int` first operand against `&&`'s fixed `Mono Bool → Bool → Bool` — an ordinary T-App/unify rejection (no constraint machinery involved), decorated with the `report_mismatch` common-hint text | `March does not coerce Int to Bool` |

**Result: 35 / 35 (20 accept typecheck, 15 reject with the declared error).**

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
the `accept/reject` corpus is the executable anchor.

### 4.1 Known typing divergences / findings (Tasks 1–6, consolidated)

Every "the typechecker actually does X, which is easy to get wrong" discovery
made while building this reference lives HERE, in this one subsection — collected
by Task 7 from where each was originally pinned inline (Tasks 1–6). Two are
genuine, filed, open gaps against the current implementation (findings 15 and
16, both cross-referenced to their `specs/todos.md` entry under "Compiler:
Type System"); the rest are faithful-but-surprising facts about the existing
typechecker that this document exists to pin down, not defects:

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
    (T-Cond, §2.1c, typecheck.ml:4020–4036) — but, unlike `EMatch`, never runs
    exhaustiveness/redundancy checking at all (neither function is called from
    the `ECond` arm). This matches the operational finding that `ECond` is NOT
    statically total (`core-march.md:492–498`): an all-false chain typechecks
    with no Warning and panics at runtime unless closed off with a final
    `true ->`/`_ ->` arm. A non-Bool condition is rejected with "Each condition
    in `match do` must be Bool." (`reject/t11_econd_condition_not_bool` is the
    witness); a branch-body mismatch falls through to the same "All branches of
    a match must have the same type." text `EMatch` uses (no `ECond`-specific
    branch-mismatch message exists).
13. **A local recursive function (`ELetFn`) is monomorphic inside its own body
    and generalized only afterward — but via a DIFFERENT mechanism than
    `T-Let`'s.** `infer_block`'s `ELetFn` arm (T-LetFn, typecheck.ml:4371–4399)
    binds the function's own name to a bare `Mono β` (fresh, ungeneralized)
    BEFORE typing the body, so a recursive call inside the body resolves via
    `instantiate` on a `Mono` scheme (a no-op — same `β`, not a fresh copy):
    every recursive call shares one monomorphic type, so **polymorphic
    recursion is rejected** exactly as standard HM predicts (verified live: a
    local `go` with two same-body recursive calls at `Int` then `String`
    fails with an ordinary T-App argument-mismatch). Unlike T-Let's RHS,
    which is typed under a bumped level (`enter_level`, typecheck.ml:4305)
    and then generalized via `generalize env.level`, the `ELetFn` arm never
    bumps the level at all — it types `β`, the params, and the body all at
    the SAME `env.level`, then compensates by generalizing with a
    **shifted-down threshold**, `generalize (env.level - 1) arrow_ty`
    (typecheck.ml:4397), which is what actually quantifies those
    same-level TVars. The net effect matches T-Let (monomorphic during its
    own definition, polymorphic afterward — `accept/t17_letfn_generalized_
    after_block` is the witness, `id_rec` used at `Int` then `String` in the
    rest of the block) via a mechanically different route. `ELetFn` also
    shares the "bind a fresh self-type, generalize once the body is fully
    checked" SHAPE with `check_fn`'s handling of a top-level recursive `fn`
    (typecheck.ml:4544–4574) — but `check_fn` DOES call `enter_level`
    (typecheck.ml:4545), so it reaches the ordinary `generalize env.level`
    form; `ELetFn`'s omission of that bump, and its compensating
    `env.level - 1`, is unique to the local/block-scoped construct. A
    declared return-type annotation on a local recursive fn is enforced
    exactly as strictly as a top-level one's (`unify body_ty expected`,
    typecheck.ml:4392) — `reject/t12_letfn_ret_annot_conflict` is the
    witness, and also surfaces a minor, non-blocking diagnostic-quality
    quirk: the identical mismatch is reported TWICE (see (T-LetFn)'s note,
    §2, and the `specs/todos.md` entry) because the annotation-unify and the
    final self-type/arrow-type reconciliation unify independently
    rediscover the same conflict once it flows through the self-reference.
14. **An unresolved `CNum` constraint silently DEFAULTS to `Int` at its
    enclosing declaration's discharge point — but this defaulting is
    effectively INVISIBLE to a fully generic function, because `generalize`
    already quantified the type variable away with a fresh, isolated ref
    before discharge ever runs.** Verified live: `fn add_poly(a, b) do a + b
    end` (no annotations, no `when`-clause) typechecks with `--check` exit 0
    even though `add_poly` is never called anywhere — and, more
    surprisingly, remains callable at BOTH `Int` and `Float` afterward
    (`add_poly(1.0, 2.0)` also typechecks). The mechanism: `check_fn`
    generalizes `add_poly`'s inferred type (`typecheck.ml:4751`,
    `generalize env.level fn_ty`) BEFORE `check_decl`'s `discharge_constraints`
    call ever runs (`typecheck.ml:6468`, strictly after `check_fn` returns) —
    and `generalize` (§1) always allocates a brand-new, isolated `TVar` ref
    for each quantified id (`typecheck.ml:866–869`), sharing only the
    integer id with whatever ref the pending `CNum` constraint still points
    at. So when `discharge_constraints` later finds that `CNum`'s type
    variable still `Unbound` and defaults it — `r := Link (TCon ("Int", []))`
    (`typecheck.ml:4965`) — it mutates the OLD, already-superseded ref; the
    function's actual stored scheme (`Poly([a_new], [], a_new → a_new →
    a_new)`, fully UNCONSTRAINED — `check_fn`'s `all_constraints` is empty
    here since there is no explicit `when`-clause, so `generalize`'s own
    `Poly(ids, [], t)` output passes through unchanged, `typecheck.ml:4752–
    4753`) is untouched by that mutation and instantiates a genuinely fresh
    variable, unconstrained, at every call site. The net, surprising result:
    **a `Num`-constrained primitive used inside a fully generic local/
    top-level function elides the constraint entirely** — there is no way,
    short of an explicit type annotation, to make such a function reject a
    non-Num instantiation, because `Num` cannot even be spelled in a
    `when`-clause to force it to survive generalization (§2.1: `when
    Num(a)` itself errors, "I don't know a constructor called `Num`" — `Num`
    is not in `env.interfaces`). This is DIFFERENT from, and easy to
    conflate with, the ordinary "generic function, constraint resolved per
    call site" story that works correctly for `CInterface`-based constraints
    with an explicit `when`-clause on a MONOMORPHIC-at-the-constrained-
    position function (see finding 15) — here there is no `when`-clause at
    all, `a`/`b` are simply unannotated params, and the `Num` obligation
    both arises AND evaporates within `add_poly`'s own declaration, never
    reaching a call site to be re-checked.
15. **A `when Interface(a)` constraint on an explicit function bound is
    correctly enforced when it can be discharged AT THE FUNCTION'S OWN
    DECLARATION (a concretely-annotated parameter), but is SILENTLY NOT
    RE-CHECKED at call sites when the bound type variable is left generic —
    a genuine, reproducible typechecker gap, distinct from finding 14's
    `Num`-specific defaulting.** Verified live, three ways:
    (a) `fn same(a : Hue, b : Hue) when Eq(a) do a == b end` (param
    concretely annotated to a no-`Eq`-impl ADT `Hue`) correctly rejects at
    `same`'s OWN declaration with `` `Hue` does not implement interface
    `Eq`. `` — the constraint IS enforced when it can be checked immediately.
    (b) `fn same(a, b) when Eq(a) do a == b end` (UNANNOTATED — `a`'s type
    stays a generic type variable at `same`'s own declaration, so
    `discharge_constraints` sees `CInterface("Eq", TVar _)` and skips it,
    "still polymorphic — cannot check yet", `typecheck.ml:4973`) then
    `same(Rood, Rood)` — where `Rood` is a variant of the SAME no-`Eq`-impl
    `Hue` ADT from (a) — **typechecks with exit 0**, even though a direct
    `Rood == Rood` (bypassing the `same` wrapper) correctly rejects with the
    identical `` `Hue` does not implement interface `Eq`. `` message. The
    constraint is silently lost, not merely deferred: `same`'s scheme is
    genuinely `Poly([a_id], [CInterface("Eq", a_tv)], a → a → Bool)`
    (`check_fn`'s `all_constraints` non-empty branch, `typecheck.ml:4752–
    4757`, DOES attach the `when`-clause's constraint here, unlike finding
    14's unconstrained case) — but calling `same(Rood, Rood)` should
    `instantiate` that `Poly` scheme (§1), substitute `a := Hue`, and push a
    FRESH `CInterface("Eq", Hue)` onto `main`'s own `pending_constraints`,
    which `main`'s own `discharge_constraints` call should then reject. It
    does not. (c) Ruled out `TArrow`-specific behavior in `impl_matches_ty`
    by reproducing the identical gap with a plain ADT value instead of a
    function value, and ruled out "the constraint never gets attached to
    the scheme at all" by confirming (a) DOES enforce it when the violation
    is visible at `same`'s own declaration. **Root cause not fully
    pinned down in this task** (this is a docs-only task; `typecheck.ml` was
    not modified) — the most likely candidate, given `instantiate`'s
    id-keyed substitution (§1) and `generalize`'s fresh-ref-per-id copy
    (`typecheck.ml:866–869`, the same mechanism implicated in finding 14),
    is some interaction between the ORIGINAL constraint-bearing `TVar` ref
    (captured once, while processing the `when`-clause, `typecheck.ml:4687–
    4712`, BEFORE `generalize` runs) and the COPIED ref `generalize` installs
    into the returned type — both share the integer id, which is what
    `instantiate`'s `List.assoc_opt id subst` keys on (§1), so in principle
    the constraint's stale `TVar` SHOULD still resolve to the same fresh
    substitution var when `instantiate` walks `inst_cs` (`typecheck.ml:929–
    934`) at a later call site; something about the ORDER those two events
    happen in, or a difference between the immediate-declaration path (a)
    and the deferred generic-call path (b)/(c), breaks that expectation.
    **This is a real typechecker soundness gap** (an explicit `when
    Iface(a)` bound on a generic parameter is not actually enforced
    polymorphically) — filed in `specs/todos.md` under "Compiler: Type
    System" (2026-07-05) with this exact repro, since fixing it is out of
    scope for this docs-only task. Not exercised by this corpus's `reject/`
    programs (a `reject/` program built on it would need to codify a
    behavior this document identifies as WRONG, which would defeat the
    corpus's purpose — the corpus instead uses the primitive, always-correctly
    -enforced `Ord`/`Num` constraints for its `reject/` witnesses, findings
    above).
16. **`let`-binding type annotations (`let x : T = e`) are parsed but never
    enforced by the typechecker — the second filed, open gap.** Found while
    building Task 2's tuple/record corpus. The parser accepts a type
    annotation on a `let` binding and stores it as `Ast.bind_ty`, but
    (T-Let)'s `infer_block` arm (§2, typecheck.ml:4293–4324) never consults it
    (`grep -c bind_ty lib/typecheck/typecheck.ml` = 0): τ₁ is inferred from
    the RHS alone and the annotation is silently discarded, so `let x : Int =
    "foo"` and `let pair : (Int, Int) = (1, 2, 3)` both `--check` at exit 0.
    **Not a soundness hole** — the inferred type still governs, so a LATER use
    of `x` at the annotated-but-wrong type is still caught by ordinary
    unification; the annotation is merely decorative rather than a checking
    context. This corpus routes around it deliberately: the tuple-arity
    reject witness (`reject/t08_tuple_arity_mismatch`) uses a
    FUNCTION-PARAMETER annotation (enforced via ordinary T-App param-vs-arg
    unification, §2) rather than a `let` annotation to elicit its mismatch,
    specifically because a `let`-annotation mismatch would NOT be rejected.
    Filed in `specs/todos.md` under "Compiler: Type System" with the fix
    direction (check the RHS against `bind_ty` via `check_expr` at the `ELet`
    arm, when present, instead of unconditionally inferring); not fixed here
    (docs-only task). A `reject/let_annotation_mismatch`-style program should
    be added to this corpus once the enforcement lands.

## 5. What this validated, and what's next

**Validated:** the type-side methodology works end-to-end — the bidirectional HM
judgment is transcribable arm-for-arm from `typecheck.ml`, the `--check`-based
`accept/reject` harness is a workable conformance anchor (with exact-error-message
pinning), and the doc format (judgment → cited rules → accept/reject table) is a
replicable template. `check_types.sh` is the committed anchor; Task 7 wired it
into its own `types-check` dune alias — a separate slow CI lane, run alongside
(not merged into) `@oracle`/`@runtest` — see `specs/lang/types/INDEX.md` for
the harness model and why `reject/` programs cannot ride the operational
side's both-ways `@oracle` sweep.

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

**Task 5 (this slice) added:** local recursive functions typing — (T-LetFn)
(§2), transcribed from the `ELetFn` arm of `infer_block` (typecheck.ml:
4371–4399; the singleton/standalone counterpart at typecheck.ml:4101–4119 is
cited alongside as the same shape, reached only when the local fn is the
last/only statement of a block). **The load-bearing finding this slice
pins:** the function's own name is bound to a bare, fresh, UNGENERALIZED
`Mono β` before its body is typed (typecheck.ml:4373–4374), so every
recursive call inside the body shares one monomorphic type — polymorphic
recursion is REJECTED, standard HM (verified live, not committed as a
separate reject program since it would restate `reject/t01`'s mismatch
shape). Generalization does happen, but only once the body is fully checked
and only for the REST of the enclosing block (never inside the function's
own body) — via `generalize (env.level - 1) arrow_ty` (typecheck.ml:4397), a
mechanically different route from T-Let's (T-Let bumps the level with
`enter_level` before typing the RHS then generalizes at the ordinary
`env.level`; `ELetFn` never bumps the level at all, instead shifting the
generalization threshold down by one to compensate) that reaches the same
observable result. `ELetFn` shares its "bind a fresh self-type, generalize
after the body is checked" shape with `check_fn`'s top-level recursive `fn`
handling (typecheck.ml:4544–4574) but not that function's `enter_level` call
— a genuine, uncommented divergence between the two recursive-binding paths,
pinned here for the first time. Two new `accept/` programs: a self-recursive
local `fn go(k, acc)` computing factorial (`accept/t16_letfn_factorial`,
monomorphic-in-body recursion) and a local `fn id_rec` used at both `Int` and
`String` in the block's continuation (`accept/t17_letfn_generalized_
after_block`, proving the post-body generalization actually fires — the
`ELetFn` analog of `t03_let_poly`). One new `reject/` program,
`reject/t12_letfn_ret_annot_conflict`: a declared return-type annotation
(`fn go(k) : Int`) on a local recursive fn conflicts with the body's actual,
internally-self-consistent inferred type (`String`, consistent across the
recursive call) — genuinely new coverage (neither a T-App arity restatement
nor a T-Match branch-mismatch restatement: both match branches agree with
each other; only the annotation disagrees with what they agree on).
Discovered in the course of building that witness: a minor, non-blocking
diagnostic-quality quirk where the identical mismatch is reported TWICE
(same span, same text) because the annotation-conflict unify
(typecheck.ml:4392) and the final self-type/arrow-type unify
(typecheck.ml:4396) each independently rediscover the same conflict once it
flows through the self-reference `β` — noted in (T-LetFn)'s rule (§2), §4
finding 13, and `specs/todos.md` (cosmetic; does not affect this corpus's
pass/fail, and does not reproduce for the equivalent top-level `fn`, which
reports once with a better message). `check_types.sh`: 29/29 (17 accept, 12
reject), exit 0.

**Task 6 (this slice) added:** the interface-constraint MODEL itself — how a
`Num`/`Eq`/`Ord`/`Show` obligation is represented (`constraint_`,
`typecheck.ml:128–133`), CREATED (`instantiate`, §1, pushing onto
`env.pending_constraints`), and DISCHARGED (**T-Discharge**, §2.1a,
transcribed from `discharge_constraints`, `typecheck.ml:4932–5049`, called at
every `DFn`/`DLet`/`DImpl` declaration boundary — `typecheck.ml:6468, 6477,
7045, 7048`) — plus the trivial, unconstrained **(δT-And)**/**(δT-Or)**/
**(δT-Not)** `Bool`-primitive typings (§2.1b). Pinned the built-in-instance
table (§2.1b): `Num` = {Int, Float} only, hardcoded (not `env.impls`-based,
no user `impl Num` form exists); `Eq` = {Int, Float, String, Bool, Unit,
Atom}; `Ord` = {Int, Float, String}; `Show` = {Int, Float, String, Bool,
Unit, Atom} (`builtin_impls`, `typecheck.ml:1150–1167`, seeded into every module's
`env.impls` by `base_env`, `typecheck.ml:1857–1867`). Live-verified (not
trusted from the plan) the no-impl error shapes: a `Num` violation only
surfaces its OWN distinct message
(`` String does not implement Num (only Int and Float do). ``) when both
operands already agree with each other (no earlier T-App unify conflict
masks it first) — `1 + "x"` directly instead falls through the ordinary
unify-mismatch path, a finding worth pinning since the plan's own text
assumed the direct form reaches the Num-specific message and it does not; an
`Ord`/`Eq`/`Show` violation on a type with no impl (a bare ADT, or a function
value) gives the `CInterface`-shaped `` `<τ>` does not implement interface
`<iface>`. `` + remediation hint. Also discovered that `COrd` (§2.1, a
constraint kind with real, working `discharge_constraints` logic) is DEAD —
`<`/`>`/`<=`/`>=` all resolve via `CInterface "Ord"`, never `COrd`; its only
constructor helper is underscore-prefixed and uncalled. Two further findings,
both about constraint SURVIVAL through `generalize`: (14) a `Num` constraint
on a fully generic, un-annotated function (no `when`-clause — impossible to
write one for `Num`, since `Num` is not in `env.interfaces`) is silently
defaulted-then-discarded, leaving the function's stored scheme genuinely
UNCONSTRAINED at every call site (verified: `add_poly(a,b) = a+b` typechecks
called at both `Int` and `Float`); (15) a REAL typechecker bug — an explicit
`when Eq(a)` (or `Ord`/`Show`) bound is correctly enforced when violated at
its OWN declaration (a concretely-annotated param) but is silently NOT
re-discharged at a call site when the bound variable is left generic
(`same(a,b) when Eq(a) do a==b end; same(Rood, Rood)` typechecks even though
`Hue` has no `Eq` impl and a direct `Rood == Rood` correctly rejects) — filed
in `specs/todos.md` under "Compiler: Type System" with the exact repro, not
fixed (docs-only task). Three new `accept/` programs (Num/Eq/Ord discharge
succeeding on built-in instances, and a `&&`/`||`/`not` boolean-logic
program) and three new `reject/` programs (the live-verified Num/Ord/Bool-
coercion error text, §2.1a/§2.1b). `check_types.sh`: 35/35 (20 accept, 15
reject), exit 0.

**Task 7 (this pass) added:** no new typing rules — pure consolidation.
Re-titled/re-scoped the document header and §0 from "walking skeleton, first
vertical slice" to "reference v1, core fragment complete"; confirmed every
`typecheck.ml:` citation present before the restructure is still present after
(the self-check is a strict superset, run via `grep -oE
'typecheck\.ml:[0-9]+' specs/lang/core-march-types.md | sort -u` pre- vs
post-restructure); refreshed the deferred list (§0, §6 below) against the
roadmap's Phase-2b/3 queue instead of the original skeleton's placeholder set
(records, which Task 2 completed, is no longer listed as deferred); added
finding 16 (the `let`-annotation-ignored gap, previously only noted inline at
(T-Let), §2) to the single consolidated §4.1 findings subsection alongside
findings 1–15; and created `specs/lang/types/INDEX.md` (mirroring
`specs/lang/golden/INDEX.md`'s shape) plus wired `check_types.sh` into its own
`types-check` dune alias — a separate, slow, opt-in CI lane (`dune build
@types-check`), deliberately NOT folded into the default `@runtest` (see
`specs/lang/types/INDEX.md` for the harness model and CI-wiring rationale).
`check_types.sh`: unchanged at 35/35 (20 accept, 15 reject), exit 0 — no
corpus programs were added or modified by this task.

## 6. Deferred — the roadmap's Phase-2b/3 queue

This document is **Level-1 for the Core March fragment's type system**
(`specs/2026-07-04-language-specification-roadmap-design.md` §2's "descriptive
reference, kept honest by tests" — the level `core-march.md` already reached
operationally). What is explicitly OUT of scope for this document, and where
each item resurfaces in the roadmap's phasing (§5 of the roadmap doc):

- **User-defined `impl`/interface DECLARATION syntax, beyond the four
  built-ins.** §2.1a/§2.1b document how a `Num`/`Eq`/`Ord`/`Show` CONSTRAINT is
  discharged against the seed table (`builtin_impls`, `builtin_interfaces`) —
  not the general `impl Iface(T) do ... end` declaration-checking machinery
  itself (method-signature validation, coherence/overlap rules), nor
  superclass bounds across multiple interfaces. Roadmap: an extension of
  Phase 2 (§4.3's "declarative typing rules... extracted from `typecheck.ml`'s
  algorithm") — the natural next widening slice after this one (see the
  now-superseded "Next" prose two paragraphs above, kept as historical
  provenance).
- **The constraint-survival soundness gap itself (finding 15, §4)** — a proper
  fix (not just documentation) and a regression test belong with that Phase-2
  widening, since fixing `typecheck.ml` is out of scope for a docs-only task.
- **Refinement types (z3-discharged).** Roadmap Phase 3 (§4.5/§6): "the
  refinement/capability soundness claims are machine-checked in Lean 4" is the
  acceptance criterion; this document's bidirectional HM judgment (§1) is the
  Level-1 substrate that Phase 3's refinement layer would extend, not
  something this pass attempts.
- **Linearity/capabilities.** The capability lattice (`lib/caps/`) is named
  explicitly in the roadmap's Phase 3 scope (§4.5, "refinement/capability
  soundness") — deferred here for the same reason as refinements.
  Linear/uniqueness typing is not separately named in the roadmap and is
  narrower still; grouped with capabilities as a Phase-3-or-later concern.
- **Effects.** Named alongside refinements/capabilities in the roadmap's
  problem statement (§4.3: "bidirectional HM inference + refinements + the
  capability lattice + effects") as part of the ambitious claim set a full
  spec needs — Phase 3 territory, not attempted here.
- **NOT deferred (a correction against the original skeleton's placeholder
  list):** records. The walking-skeleton v0 header listed "records" as a
  deferred later slice; Task 2 completed tuples+records typing in full
  (T-Tuple/T-Record/T-Field/T-Update, §2; P-Tuple, §2.2), so records are
  fully in-scope and covered by this reference — they are removed from the
  deferred set here.

Together, `core-march.md` (operational) + this document (typing) are
**Level-1 for the Core March fragment** per the roadmap's leveling (§2); the
next phase of BOTH documents is the Level-2 conformance work already underway
(the golden corpus + this document's `accept`/`reject` corpus) plus, per §4.4
of the roadmap, adjudicating the operational side's `known_divergence` queue —
this document's own analogous queue is the single open item, finding 15.
