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

**Widening slice (2026-07-06):** §2.3 extends the built-in-only constraint
material above with user-defined **`interface`/`impl` DECLARATION checking**
itself — what makes an `interface Iface(a) do ... end` or `impl Iface(T) do
... end` well-formed, as opposed to how a `Num`/`Eq`/`Ord`/`Show` constraint is
*discharged* against the built-in seed table (§2.1a, unchanged). §2.3 also
covers superclass/`requires` and `when`-clause discharge (both MANDATORY
enforcement, not conditional gaps) and names the `impl_matches_ty` structural
match as its own rule, `(T-ImplMatch)` — the judgment both discharge paths
share, and the reason generic/parameterized impls work at all. §2.4 covers
`derive`/`satisfy` as `DImpl` *generators*. The coherence/overlap story (what
happens when TWO impls both match the same target, per `(T-ImplMatch)`'s lack
of specificity resolution) is documented in full as an open, filed
interpreter/compiled divergence in `core-march.md` §4.4.3 (the operational
companion, since a `--check`-only harness cannot witness a runtime
interp-vs-compiled split) — §2.3 notes it inline at the point the gap arises
(item 1 of `(T-Impl)`'s ordered checks) and cross-references that subsection
rather than repeating it here.

**Deferred to later phases** (the roadmap's Phase-2b/3 queue, §6): refinements
(z3-discharged), the capability lattice (`lib/caps/`), and effects — see §6
for the full deferred-set breakdown and its roadmap citations. Coherence/
overlap resolution between impls is NOT in this deferred set — it is a known,
intentionally OPEN divergence (documented in `core-march.md` §4.4.3 and filed
in `specs/todos.md`), not a documentation gap awaiting a later widening slice;
resolving the divergence itself (a language-design decision — add a coherence
check, or pick a shared deterministic selection policy) is what's deferred.

**Widening slice 2 (2026-07-06, modules):** §2.5 adds **module visibility as
a typecheck concept** — `pub_set`-filtered export, the cross-file
`load_module_into_env` gate (`ExFn`/`ExValue`, fixed by this slice's Task 1),
and the **opaque-type asymmetry** it deliberately preserves (`ExType`/
`ExRecord` stay ungated, so a private `ptype`'s bare NAME is nominally
referenceable cross-module even though its declaring module never marked it
public) — together with the **no-per-module-type-namespace design point**
(types resolve by bare name only, so two sibling modules' same-named types
are literally one nominal type, not merely visually similar) and the
`9001e4c0` qualified-type-path unification that is the flip side of the same
design. §2.5 also files a real, precisely-traced enforcement gap found while
verifying the asymmetry live: `opaque type`'s constructor-hiding is NOT
actually enforced against qualified construction (a `prebind_mod_members`
forward-reference pass registers the qualified ctor key ungated on
`var_vis`, before the later, correctly-filtered `DMod` export step's result
is merged in) — structurally the same class of bug Task 1 fixed for
`ExFn`/`ExValue`, but on a different registration path; filed, not fixed
(out of this docs-only task's scope). `core-march.md` §4.7 (this slice's
Task 2) is the operational companion — `own_names`-gated export, bare-fails/
qualified-works name resolution, and the lexical-scoping nuance for a
directly-nested module.

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

### 2.3 Interface & impl declarations: `(T-Interface)` and `(T-Impl)`

§2.1a documented how a `Num`/`Eq`/`Ord`/`Show` **constraint is discharged**
against a seed table of built-in instances. This subsection documents the
other half: what the typechecker validates when a program itself **declares**
a user-defined `interface Iface(a) do ... end` and writes an
`impl Iface(T) do ... end` for it. Cited to `typecheck.ml`'s `DInterface` and
`DImpl` arms of `check_decl`, re-grepped live against this worktree.

**`(T-Interface)` — interface declaration is pure registration.**

```
(T-Interface)  Γ' = Γ[interfaces := interfaces[iface_name ↦ idef]]        typecheck.ml:7045–7050
               ∀ m ∈ idef.iface_methods:
                 a fresh (at level+1)                                    typecheck.ml:7053
                 τ_m = surface_ty(m.md_ty)  with iface_param ↦ a         typecheck.ml:7054–7055
                 σ_m = generalize(level, τ_m), THEN prepend
                       CInterface(iface_name, a) to its constraint list   typecheck.ml:7060–7067
                 Γ'' = Γ'[m.md_name ↦ σ_m][iface_name^"."^m.md_name ↦ σ_m]  typecheck.ml:7068–7072
               ──────────────────────────────────────────────────────────
               Γ ⊢ DInterface(idef) ⇒ Γ''                                  typecheck.ml:7045–7073
```

Every interface method is bound as a scheme `∀a [CInterface(iface,a)]. τ`
**twice**: once under its bare name (`speak`) and once under the
interface-qualified name (`Speak.speak`) — the qualified binding is what makes
`Iface.method(x)` call syntax resolve (the `EField`-as-module-path lookup
path). Occurrences of either name later push a fresh `CInterface(iface, τ)`
obligation onto `env.pending_constraints` at the ordinary T-Var/`instantiate`
site (§1) — a `DInterface`'s own method schemes are constructed exactly like
`show`/`eq`/`compare`/`hash`'s built-in schemes (§2.1's `mk_iface_method_scheme`
shape), just built per-declaration instead of once at `base_env` time.

**Almost nothing is rejectable at the interface declaration itself.** There is
no check that a method's declared type actually mentions the interface's own
type parameter `a` (an interface method signature that never uses `a` still
typechecks, with the `CInterface` constraint simply attached to a fresh,
otherwise-unconstrained variable) and no rejection of a duplicate interface
name in the same module (a second `interface Speak(a) do ... end` just calls
`StrMap.add` again, silently replacing the first entry in `env.interfaces` —
consistent with `env.impls`'s "insert, never check" registration shape,
confirmed for impls below). `DInterface` is registration, not validation.

**Two pre-pass duplicates exist for cross-module declaration ordering.**
`prebind_interface_decl` (typecheck.ml:5050–5087) reconstructs the identical
scheme-building logic as a pass-1 walk (called from `check_module_core`/
`check_module_with_env`'s first pass, typecheck.ml:8072, 8272, and from
`check_decl`'s own `DMod`/top-level pass-1 prebind, :8146–8147, 8337–8338) so
that a **sibling module checked before the interface's own defining module**
can still see `Iface`, `Iface.method`, and the bare `method` name — the doc
comment at typecheck.ml:5042–5049 ties this directly to a real, previously-
fixed LSP bug (per-file analysis hiding sibling-module interfaces). It is not
shared code with the full `DInterface` arm (a deliberate duplication, not a
refactor gap) for the same reason `register_impl_shape` (below) duplicates
`DImpl`'s registration step: pass-1 must run with a still-incomplete
environment, so it cannot simply call the pass-2 function.

**`(T-Impl)` — the ordered checks of an impl declaration.** `Ast.DImpl`'s arm
(typecheck.ml:7075–7210) runs, in order:

```
(T-Impl)  τ_impl = surface_ty(idef.impl_ty)  sharing tvars with `when` clause   typecheck.ml:7078–7079
          Γ₁ = Γ[impls := impls[iface ↦ τ_impl :: impls[iface]]]                typecheck.ml:7081–7084
          ∀ (cname, [cty]) ∈ idef.impl_constraints, cty concrete:
            (T-ImplMatch)-search Γ₁.impls[cname] for a match against cty        typecheck.ml:7086–7103
          ∀ (sc_name, [sc_ty]) ∈ interface.iface_superclasses, sc_ty concrete:
            (T-ImplMatch)-search Γ₁.impls[sc_name] for a match against sc_ty    typecheck.ml:7118–7143
          idef.impl_iface ∈ dom(Γ.interfaces)  (or a "Json*"-prefixed pseudo-iface)  typecheck.ml:7105–7117
          ∀ iface_m ∈ interface.iface_methods:
            iface_m.md_name ∈ names(idef.impl_methods)  ∨  iface_m.md_default ≠ None  typecheck.ml:7144–7157
          ∀ (mname, def) ∈ idef.impl_methods:
            mname ∈ names(interface.iface_methods)                             typecheck.ml:7158–7165
          ∀ (mname, def) ∈ idef.impl_methods:
            expected_τ = surface_ty(iface_method.md_ty)  with iface_param ↦ τ_impl  typecheck.ml:7168–7172
            actual_τ   = instantiate(check_fn(def))     (or check_expr directly
                          for an injected zero-param default body)              typecheck.ml:7176–7189
            unify(actual_τ, expected_τ)
          discharge_constraints(Γ₁)                                             typecheck.ml:7205, 7208
          ──────────────────────────────────────────────────────────────
          Γ ⊢ DImpl(idef) ⇒ Γ₁
```

This section covers all seven checks: impl-head instantiation and
registration, `when`-clause discharge, superclass/`requires` discharge,
interface existence, missing-method, extra-method, and signature-match —
plus the final `discharge_constraints` call every declaration arm makes
(§2.1a). The `when`-clause and superclass checks share the identical
discharge shape (both search `env.impls` via the `(T-ImplMatch)` judgment,
named and detailed below) — they are documented together immediately after
item 1.

1. **Instantiate the impl head, then register — unconditionally, no dedup, no
   uniqueness check.** `env.impls : ty list StrMap.t` is keyed only by
   interface name; the value is a **list** of impl head types, and
   registration is always `inst_ty :: existing_list` (typecheck.ml:7081–7084).
   There is no "is this type already present" lookup anywhere in this step —
   `env.impls` is built to be *searched* (via `impl_matches_ty`, a structural,
   non-unifying, wildcard-tolerant shape match — its own named rule,
   `(T-ImplMatch)`, detailed just below) rather than *inserted into with a
   conflict check*. **Overlapping impls of the same interface for the same
   type are NOT rejected at typecheck** — a second `impl Speak(Dog)` typechecks
   exactly like the first, with no duplicate/coherence diagnostic of any kind;
   `core-march.md` §4.4.3 documents this fully as an open, filed divergence
   (the interpreter and compiled backend disagree at RUNTIME on which
   overlapping impl's method body actually runs — last-registered vs.
   first-registered, respectively), cross-referenced here rather than
   restated.

**`(T-ImplMatch)` — the impl-head-matching judgment (typecheck.ml:4964–4984).**
Both the `when`-clause check and the superclass check above (and, at the use
site, `CInterface` constraint discharge itself, §2.1a) all reduce to the same
question: *"is there an impl in `env.impls` whose head type covers this
target type?"* That question is answered by one function, worth naming as
its own rule:

```
(T-ImplMatch)  repr(impl_ty) = TVar _                                          typecheck.ml:4970
               ────────────────────────────────────
               impl_matches_ty(impl_ty, target_ty) = true    -- wildcard: any target

(T-ImplMatch)  repr(target_ty) = TVar _        (impl_ty not itself a TVar)      typecheck.ml:4971
               ────────────────────────────────────
               impl_matches_ty(impl_ty, target_ty) = false   -- target unresolved: no

(T-ImplMatch)  repr(impl_ty) = TCon(n, as1)   repr(target_ty) = TCon(n, as2)
               |as1| = |as2|   ∀i. impl_matches_ty(as1[i], as2[i])              typecheck.ml:4972–4974
               ────────────────────────────────────
               impl_matches_ty(impl_ty, target_ty) = true

               -- (TArrow/TTuple/TRecord: analogous same-shape pairwise recursion,
               --  typecheck.ml:4975–4981; TLin unwraps and ignores linearity,
               --  :4982; TError is permissive on either side, :4983; otherwise
               --  plain structural equality, :4984)
```

`impl_matches_ty : ty -> ty -> bool` is a **structural, non-unifying,
wildcard-tolerant shape match** — it never returns a substitution or binds a
type variable, only a boolean "does this impl head cover that target." This
single judgment is the crux of two, otherwise-unrelated-looking facts about
March's impl system:

- **It is why generic/parameterized impls work at all.** An impl head with
  its own free type variable — `impl Speak(a)` (a blanket impl over every
  type, `accept/t19_eq_ord_constraint_discharged`-adjacent shape) or
  `impl Describe(Box(a))` (a generic impl over a parameterized type,
  `accept/t24_interface_impl_generic_head`, witnessed at both `Box(Int)` and
  `Box(String)`) — matches because the `TVar _, _ -> true` case (typecheck.ml
  :4970) treats the impl's own unresolved type parameter as a wildcard, not
  as "must unify with." There is no separate "instantiate the impl head at
  the target type" step; matching and instantiation are conflated into one
  permissive boolean check.
- **It is also why coherence does not exist.** `impl_matches_ty` only answers
  "does impl I cover target T," never "which impl, of possibly several
  covering candidates, is the most specific." Nothing about the judgment (or
  its call sites) compares two matching impls against each other — `env.impls`
  is walked with `List.exists`, which stops at the first structural match and
  discards the rest, so **there is no specificity resolution**: a fully
  generic `impl Iface(a)` and a fully concrete `impl Iface(Dog)` can both
  match a `Dog` target simultaneously, and nothing in `(T-ImplMatch)` itself
  (or the discharge sites that call it) picks the more specific one — which
  one actually runs is decided entirely by registration order in the
  interpreter/codegen backends respectively, not by matching logic.
  `core-march.md` §4.4.3 documents this overlap/coherence divergence in full
  (the two-backend runtime disagreement over which of several matching impls is
  selected);
  this section's job is only to name and pin the matching judgment itself,
  since it is the single mechanism both stories flow from.
- **Linearity qualifiers are ignored for matching purposes**
  (`TLin (_, t1), TLin (_, t2) -> impl_matches_ty t1 t2`, typecheck.ml:4982):
  an impl declared for `linear T` matches a search for plain `T` and vice
  versa — the linearity annotation itself is stripped away before the
  structural comparison, not treated as part of the type's identity.

**Superclass/`requires` bounds ARE enforced — this is a mandatory rejection,
not a conditional gap.** `interface Greet(a) requires Speak(a) do ... end`
records `Speak` in `Greet`'s `iface_superclasses` (parsed at
`lib/parser/parser.mly:769-786`); when `impl Greet(T)` is declared, the
superclass-discharge step (typecheck.ml:7118–7143) instantiates each
required superclass's type arguments against the SAME impl type
(`sc_tvars = [(interface.iface_param, inst_ty)]`, :7120) and, for each
resulting concrete type, requires `env.impls` to already contain a matching
impl for that superclass via `(T-ImplMatch)` — the identical search shape as
the `when`-clause check in step (1). If no matching impl is found, the impl
is rejected:

```
Cannot implement `Greet(Dog)`: required superclass `Speak(Dog)` is not satisfied.
Add `impl Speak(Dog) do ... end` before this implementation.
```

(live-captured, `reject/t22_impl_superclass_unsatisfied`, from an
`interface Greet(a) requires Speak(a)` with an `impl Greet(Dog)` but no
`impl Speak(Dog)` anywhere in scope). Declaring `impl Speak(Dog)` before
`impl Greet(Dog)` satisfies the bound and the program typechecks
(`accept/t26_impl_superclass_satisfied`, run-witnessed: prints
`"Hello, Rex"`). The comment at typecheck.ml:7141 notes **multi-param
superclasses "not yet supported"** — `sc_inst_tys` is matched against a
single-element list pattern (`| [sc_inst_ty] -> ... | _ -> ()`, :7124,
:7141), so a hypothetical superclass with more than one type argument would
silently skip the check entirely; this mirrors the identical single-argument
limitation described just below for `when`-clauses, and is not separately
probed since March's interface grammar only supports one type parameter per
interface in the first place (`parser.mly:769-786`), so a multi-argument
superclass constraint cannot arise from any interface declaration the parser
accepts today.

**The `when`-clause check (typecheck.ml:7086–7103) is the identical
mechanism, applied to an impl's own constraints rather than its interface's
superclasses.** `impl Iface(T) when Other(T) do ... end` requires `Other(T)`
already implemented, using the same `(T-ImplMatch)` search against
`env.impls`; if the constrained type is a bare, still-unresolved `TVar`
(a generic `when` clause, e.g. `impl Wrap(a) when Speak(a)`), the check is
skipped — `TVar _ -> ()` at :7091 — deferring to the ordinary use-site
`CInterface` discharge instead (§2.1a), since there is nothing concrete to
search for yet. Unsatisfied `when` message (already pinned in the existing
corpus, `reject/t10`-shaped): `` Constraint `C(T)` in `when` clause is not
satisfied. No `impl C(T)` is in scope. `` Only single-argument constraints
are handled here too — the `_ -> ()` fallthrough at :7102 is likely
unreachable in practice rather than a live gap, since the grammar for
`constraint_expr` (`parser.mly:823-826`) only ever produces a one-element
type-argument list.

2. **Interface existence** (typecheck.ml:7105–7117): `idef.impl_iface` must be
   a key of `env.interfaces`, UNLESS its name starts with `"Json"` — `derive`'s
   `JsonTo`/`JsonFrom` pseudo-interfaces are deliberately never registered in
   `env.interfaces` and take a separate, lighter validation path (method
   bodies are still typechecked, but not against a declared signature; see
   the `derive`/`satisfy` task for the full story). Live-captured message
   (`reject/t21_impl_unknown_interface`):
   ```
   Unknown interface `NotDeclared` — is it declared above this impl?
   ```
3. **No missing required method** (typecheck.ml:7144–7157): every
   `interface.iface_methods` entry must be either present by name in
   `idef.impl_methods`, or carry `md_default <> None` (see below). Live
   message (`reject/t18_impl_missing_method`):
   ```
   Missing method `greet` in `impl Speak(Dog)`.
   Interface `Speak` requires this method to be implemented.
   ```
4. **No extra undeclared method** (typecheck.ml:7158–7165): every method the
   impl provides must match some `iface_m.md_name` — an impl cannot add
   methods the interface never declared. Live message
   (`reject/t19_impl_extra_method`):
   ```
   Interface `Speak` does not declare a method `bark`.
   ```
   This check applies even to the four built-in dispatched interfaces: a
   hand-written `impl Eq(T) do ... end` with an extra `neq` method is rejected
   here too, since `Eq`'s `builtin_interfaces` shape only declares `eq`
   (cross-referenced by the dispatch-operational task — this static rejection
   is what makes a defensive dispatch-key-collision guard on the `eval.ml`
   side unreachable for the four built-ins today).
5. **Signature match — `impl_matches_ty` for the impl HEAD, ordinary `unify`
   for each METHOD** (typecheck.ml:7166–7189): for each provided method, the
   interface's declared signature is instantiated by substituting the
   interface's type parameter with the impl's own concrete head type
   (`expected_ty`, :7168–7172), then the method body's actual type — from
   `check_fn` + `instantiate`, or from `check_expr` directly for an
   already-zero-param default body (see below) — is `unify`'d against it. Live
   message (`reject/t20_impl_signature_mismatch`):
   ```
   `speak` in `impl Speak` must match the interface signature
   ```
   (the full diagnostic also carries the ordinary `expected \`String\` but got
   \`Int\`.` unify-mismatch headline above this note, per `report_mismatch`'s
   usual shape, §2.1a).

**Default methods (`md_default`) — an impl that omits one is not an error.**
An interface method may carry a default body:
`interface Foo(a) do fn bar : a -> Int do fn self -> 42 end end`. If an impl
of `Foo` omits `bar`, step 3 above is a no-op for it (`md_default <> None`), so
no "missing method" diagnostic fires. Mechanically, this is NOT a fallback
inside `check_decl`'s own missing-method check — desugar's `inject_defaults`
(`lib/desugar/desugar.ml:897–931`) runs BEFORE typecheck ever sees the `DImpl`
and **splices a synthesized method into `idef.impl_methods`** for every
interface method the impl omits that has a default: it wraps the default
expression in a single zero-parameter `fn_clauses` clause
(`fc_params = []`, desugar.ml:918–923) and appends it to the impl's method
list. By the time `check_decl`'s `DImpl` arm runs, the impl already "has" the
method — the missing-method check simply never sees it as absent, and the
signature-match step (item 5 above) type-checks the injected zero-param clause
directly via `check_expr` against `expected_ty` (typecheck.ml:7176–7182), the
same branch a hand-provided method would only take if it, too, happened to be
a zero-param clause.

One consequence worth calling out because it is easy to get wrong writing a
default body: **the default expression's type is the method's FULL ARROW
TYPE** (`a -> Int` in the example above), not the return type after applying
`self` — because the zero-param clause's body IS the default expression
verbatim (desugar.ml:921, `fc_body = desugar_expr default_expr`), so
`expected_ty` (the whole instantiated method type) is checked directly against
it. A default body that is just a bare value (`do 42 end`) fails to typecheck
with an arrow-vs-concrete-type mismatch; the default body must itself be a
value of the arrow type — ordinarily a lambda over the interface's own
parameter (`fn self -> 42`). Confirmed live: `accept/t25_interface_default_method`
declares `fn greeting : a -> Int do fn self -> 42 end`, an impl that provides
only `name` (omitting `greeting`), and `println(int_to_string(greeting(Cat("Tom"))))`
both typechecks (`--check` exit 0) and RUNS to print `42` — the default,
not a value from the impl (which never defined `greeting` at all).

**Corpus:**

- `accept/t23_interface_impl_basic` — a minimal `interface Speak(a) do fn
  speak : a -> String end` + `impl Speak(Dog)` providing exactly `speak`;
  typechecks and (run) prints `"Rex"`.
- `accept/t24_interface_impl_generic_head` — `impl Describe(Box(a))`, a
  parameterized/generic impl head, used at both `Box(Int)` and `Box(String)`
  (witnesses `impl_matches_ty`'s wildcard treatment of the impl's own free
  type variable, named and detailed above as `(T-ImplMatch)`).
- `accept/t25_interface_default_method` — the default-method witness above.
- `accept/t26_impl_superclass_satisfied` — `interface Greet(a) requires
  Speak(a)`, with `impl Speak(Dog)` declared before `impl Greet(Dog)`;
  typechecks and (run) prints `"Hello, Rex"` — the superclass bound
  SATISFIED.
- `reject/t18_impl_missing_method` — a required, non-default method omitted.
- `reject/t19_impl_extra_method` — an impl method the interface never
  declared.
- `reject/t20_impl_signature_mismatch` — a provided method whose inferred
  body type disagrees with the interface's declared signature.
- `reject/t21_impl_unknown_interface` — `impl` of an interface name that was
  never declared.
- `reject/t22_impl_superclass_unsatisfied` — the same `Greet requires Speak`
  interface shape, but `impl Greet(Dog)` with no `impl Speak(Dog)` anywhere
  in scope — the superclass bound UNSATISFIED (mandatory rejection, not a
  conditional gap).

### 2.4 `derive` and `satisfy`: two ways to get a `DImpl` without writing one

§2.3 documented `(T-Interface)`/`(T-Impl)` as they apply to a hand-written
`interface`/`impl` pair. This subsection covers March's two *generators* of
`DImpl` blocks — `derive Iface1, Iface2 for Type` and
`satisfy Iface1, Iface2 for Type1, Type2` — both expanded entirely at
**DESUGAR time**, strictly before typecheck ever runs. `typecheck.ml`'s own
`check_decl` confirms this structurally: its `DDeriving`/`DSatisfy` arms
(`typecheck.ml:7393–7395`, `:7519–7521`) are bare no-ops — by the time
`check_decl` walks the declaration list, `desugar_module` has already
replaced every `DDeriving`/`DSatisfy` node with the `DImpl` block(s) it
expands to (or with nothing, per the no-op gap documented below). Both
generators live in `lib/desugar/desugar.ml`, re-grepped live in this
worktree.

**`derive` — a CLOSED set of five hardcoded interfaces, dispatched by a flat
string match.** `derive Iface1, Iface2 for TypeName` (`DDeriving`,
`ast.ml:178–181`) is expanded by `expand_derive` (`desugar.ml:1651–1664`):

```
expand_derive(type_name, ifaces) =
    match List.assoc_opt type_name type_defs with
    | None            -> []                              -- desugar.ml:1659 (see gap, below)
    | Some(tparams,td) -> concat_map derive_impl(iface, sp, tparams, td) ifaces
```

For each interface name, `derive_impl` (`desugar.ml:1108–1647`) dispatches on
the bare string via `match iface with | "Eq" -> … | "Show" -> … | "Hash" ->
… | "Ord" -> … | "Json" -> … | _ -> error` (branch line numbers re-grepped
live: `"Eq"` at `:1128`, `"Show"` at `:1200`, `"Hash"` at `:1260`, `"Ord"` at
`:1303`, `"Json"` at `:1398`, the catch-all error at `:1641–1647`). This is a
**closed, hardcoded set of exactly five derivable interfaces** — not a
general mechanism a user can extend by declaring their own `interface` and
hoping `derive` notices it. An interface name outside the five is rejected,
live-captured (`reject/t23_derive_unknown_interface`):

```
Unknown derive target `Frobnicate` for type `Color`.
Supported interfaces: Eq, Show, Hash, Ord, Json
```

- **`Eq`/`Show`/`Hash`/`Ord`** each produce exactly ONE `DImpl` via the local
  `impl_one` helper (`desugar.ml:1116–1126`), targeting the REAL interface
  name (`impl_iface = mk_name iface`) — these desugar to `DImpl` blocks that
  `(T-Impl)` (§2.3) cannot distinguish from a hand-written `impl Eq(Color) do
  … end`. That indistinguishability is exactly why a `derive`-generated impl
  can collide with a hand-written one for the same `(interface, type)` pair —
  cross-referenced, not restated, at `core-march.md` §4.4.3's derive-vs-manual
  overlap probe. Each generator walks the type's own definition
  structurally: a `TDVariant` produces a match over pairs of constructors
  (`Eq`'s body, `desugar.ml:1134–…`, matching each constructor against
  itself and folding `&&` over payload-wise `==`; a mismatched pair of
  constructors falls to a wildcard `false`), a `TDRecord` compares/derives
  field-by-field, and a `TDAlias` DELEGATES directly to the aliased type's
  own operators (e.g. `desugar.ml:1194–1196` for `Eq`) rather than
  regenerating logic for the alias itself.
- **`Json` is special-cased: it produces TWO `DImpl` blocks under PSEUDO-
  interface names `"JsonTo"`/`"JsonFrom"`**, not the real interface name
  (`desugar.ml:1623–1639`, `mk_json_impl` building `impl_iface = mk_name
  "JsonTo"` / `"JsonFrom"`). These two names are deliberately never entries
  in `env.interfaces` — `(T-Impl)`'s interface-existence check (§2.3, item 2)
  has an explicit escape hatch for exactly this: `` idef.impl_iface.txt ``
  starting with the 4-character prefix `"Json"` skips the "unknown
  interface" rejection AND the normal method-signature validation entirely
  (`typecheck.ml:7105–7117`'s `is_json_derive` guard, mirrored again at
  `typecheck.ml:7196–7210` for the "don't rebind the polymorphic
  `to_json`/`from_json` builtin" step) — method bodies are still
  type-checked standalone via `check_fn`/`check_expr` for local correctness
  (`typecheck.ml:7202–7204`), but never unified against a declared interface
  signature the way an ordinary impl's methods are (§2.3 item 5). `Json`
  derive is thus architecturally a special case bolted onto the general impl
  machinery — worth naming explicitly as an exception to `(T-Impl)`, not
  folded silently into its general rule.

**FILED GAP — `derive X for UnknownType` silently no-ops: exit 0, no
diagnostic of any kind.** `expand_derive`'s `None` branch
(`desugar.ml:1659`, quoted above) is a bare `[]` — if `type_name` is not a
key of `type_defs` (the module's own collected type definitions,
`desugar.ml:2110`), the ENTIRE `derive` declaration silently vanishes: no
`DImpl` is ever generated, and — critically — **no error is ever raised**,
unlike every other "the target doesn't exist" case in this document (`impl`
of an undeclared interface IS rejected, §2.3 item 2; `satisfy` of an
undeclared interface IS rejected, below). Re-verified live for this task:

```
mod M do
  derive Eq for Ghost           -- `Ghost` is never defined anywhere

  fn main() do
    println("no error, no Ghost type defined")
  end
end
```

`--check` on this program exits **0** — no diagnostic, no warning. Running it
also exits **0** and prints `no error, no Ghost type defined` — the program
behaves exactly as if the `derive Eq for Ghost` line were not present at all.
This is filed as an open gap in `specs/todos.md` ("Compiler: Type System",
finding 17 in this document's §4.1), with this exact repro and the
`desugar.ml:1659` citation — fixing it (making an unknown derive TARGET TYPE
an error, symmetric with the unknown derive TARGET INTERFACE case already
handled above) is a compiler change, out of scope for this documentation
slice.

**`satisfy` — wires EXISTING top-level functions to an interface by NAME
MATCH, all-or-nothing per `(interface, type)` pair.**
`satisfy Iface1, Iface2 for Type1, Type2` (`DSatisfy`, `ast.ml:182–185`) is
expanded by `expand_satisfy` (`desugar.ml:1676–1716`) for every
`(interface, type)` pair in the cartesian product of its two name lists:

```
expand_satisfy(iface_n, type_n) =
    match List.assoc_opt iface_n interfaces with
    | None       -> error "Unknown interface `Iface` in satisfy declaration."; []
    | Some iface ->
        methods = filter_map (fun md ->
            match List.assoc_opt md.md_name fns with
            | None    -> error "satisfy Iface for Type: no function `md_name` found in scope."; None
            | Some fn -> Some(md.md_name, fn)
          ) iface.iface_methods
        if length methods < length iface.iface_methods then []      -- desugar.ml:1703
        else [ DImpl { impl_iface = iface_n; impl_ty = TyCon(type_n, []); impl_methods = methods; … } ]
```

Unlike `derive`, `satisfy` looks up the interface in a REAL,
`env.interfaces`-sourced list (`interfaces : (string * interface_def) list`,
collected from the module's own `DInterface`s before expansion,
`desugar.ml:2111`) — so `satisfy` can target ANY user-declared interface, not
a closed set of five. Two failure modes, both rejected, both re-captured
live this task:

- **Unknown interface** (verified live this task; not separately committed
  as its own corpus program since `reject/t24_satisfy_missing_function`
  already exercises `expand_satisfy`'s rejection path and a second
  `satisfy`-rejects-unknown-interface program would restate the same
  mechanism as `reject/t21_impl_unknown_interface`'s `impl`-side analog):
  ```
  Unknown interface `Bogus` in satisfy declaration.
  ```
- **Missing function for a required method** (this task's
  `reject/t24_satisfy_missing_function`):
  ```
  satisfy Named for Person: no function `name` found in scope.
  ```

**All-or-nothing: satisfy never emits a partial impl.** If even ONE method
required by the interface has no matching same-named top-level function, the
ENTIRE `(iface, type)` pair's expansion is abandoned (`if List.length methods
< List.length iface.iface_methods then []`, `desugar.ml:1703`) — no `DImpl`
is emitted at all for that pair, not a partial one missing just the
unresolved method. This is a clean design choice, not a corner case: it
avoids a "missing method" diagnostic being reported TWICE for the same
underlying problem — once as `expand_satisfy`'s own "no function found"
error, and again from `(T-Impl)`'s missing-method check (§2.3, item 3) if a
partial `DImpl` had been emitted and handed to `check_decl` anyway.

**Corpus:**

- `accept/t29_derive_eq_show` — `derive Eq, Show for Color` on a 3-constructor
  variant type, used via `show(Red)`/`Red == Red`/`Red == Blue`; typechecks
  and (run) prints `Red` / `true` / `false`.
- `accept/t30_satisfy_wiring` — `satisfy Named for Person` wiring an existing
  top-level `fn name` to `interface Named(a)`'s one method; typechecks and
  (run) prints `Ada`.
- `reject/t23_derive_unknown_interface` — `derive Frobnicate for Color`, an
  interface name outside the closed five-name set.
- `reject/t24_satisfy_missing_function` — `satisfy Named for Person` where no
  top-level `fn name` exists anywhere in the module.

**Note — dead AST surface: associated types are not a real feature.**
`interface_def.iface_assoc_types : assoc_type_decl list` and
`impl_def.impl_assoc_types : (name * ty) list` (`ast.ml:302`, `:324`) are
populated with `[]` UNCONDITIONALLY by the parser (`parser.mly:779`, `:809`)
— there is no grammar production anywhere that fills either field with
anything else (no `type Output = …` associated-type syntax exists inside an
`interface`/`impl` block), and neither `typecheck.ml` nor `eval.ml` ever
reads either field (confirmed by grep: the only other occurrence is the same
`[]` literal at `typecheck.ml:1120`, in `mk_builtin_iface`). **Associated
types are AST scaffolding for a future extension, not a currently-working
feature** — worth this one-line note so a reader who spots the fields in
`ast.ml` doesn't assume otherwise.

### 2.5 Module visibility, the opaque-type asymmetry, and the no-per-module-type-namespace design point

**Widening slice 2, Task 3.** `core-march.md` §4.7 documented `DMod`'s
OPERATIONAL side — how a module's declared names get re-exported as
`"Name.member"` at eval time, gated on `own_names` (everything declared,
public or private). This subsection is the TYPING counterpart: what
`typecheck.ml`'s `DMod` arm (`Ast.DMod (name, _vis, decls, _sp)`,
`typecheck.ml:6823`) and its cross-file sibling `load_module_into_env`
(`typecheck.ml:657–692`) actually gate on, and — the load-bearing content of
this subsection — the precise, INTENTIONAL asymmetry between how a private
FUNCTION/VALUE is hidden and how a private TYPE stays nominally visible.
Every claim below was re-run live against this worktree's
`_build/default/bin/main.exe --check` (and, where noted, run to a printed
value), not inferred from reading the source alone.

**`pub_set` — visibility is a `DMod`-local, typecheck-only export filter.**
The same-file (or same-compilation-unit, since `use`/`MARCH_LIB_PATH`-resolved
siblings are spliced in as real `DMod`s before typecheck ever runs) case:

```
pub_set = { n | DFn(n, Public) ∈ decls } ∪ { n | DLet(Public, n, …) ∈ decls }
          ∪ { n | DType(Public, n, …) ∈ decls } ∪ …                          typecheck.ml:6841–6862
is_pub_key k  = ∃ n ∈ pub_set. k = n ∨ k starts-with (n ^ ".")               typecheck.ml:6895–6901
new_names     = { (Name^"."^k, σ) | (k, σ) ∈ inner_env.vars, is_pub_key k }  typecheck.ml:6904–6908
new_types     = { (k, arity) | (k, arity) ∈ inner_env.types, k ∈ pub_set }   typecheck.ml:6915–6917
new_ctors     = filter each ci: ci.ci_type ∈ pub_set ∧ ci.ci_vis = Public    typecheck.ml:6918–6927
```

A name never in `pub_set` (a `pfn`, a private `let`, a `ptype`) simply never
gets a `"Name.member"` key written into the outer scope's `vars`/`ctors` —
the SAME absence-not-rejection shape `core-march.md` §4.7 describes for
`own_names`, just filtered one predicate narrower (`pub_set` ⊆ `own_names`,
strictly narrower for any module with at least one private member). This is
why a same-file private access surfaces as "Unknown module `A`" rather than a
dedicated "is private" diagnostic when `A` has no public surface at all — the
qualified lookup falls through to the registry fallback below, which reports
based on what a DIFFERENT, independently-loaded copy of "module A" contains
(see the cross-file case next).

**The cross-file/registry gate — `load_module_into_env`, Task 1's fix.**
A qualified reference that misses the primary `env.vars`/`env.types`/
`env.ctors` lookup (e.g. any qualified name from a module that was never
spliced in as a sibling `DMod` in THIS compilation, which in practice is any
stdlib module reached only via the registry fallback rather than `use`) falls
to `resolve_qualified_var`/`resolve_qualified_type`/`resolve_qualified_ctor`
(`typecheck.ml:707–739`), which call `Module_registry.ensure_loaded` — an
INDEPENDENT re-parse of the module's `.march` file from disk — and then
`load_module_into_env` (`typecheck.ml:657–692`) to populate a **fresh**
environment slice from its exports:

```
| ExFn | ExValue ->                                                          typecheck.ml:662–675
    if not entry.ex_public then env                 (* SKIP — Task 1's gate *)
    else bind qname ↦ Mono(fresh_var 0)
| ExType arity ->                                                            typecheck.ml:676–678
    bind qname ↦ arity                               (* UNGATED, always *)
| ExRecord (arity, fields) ->                                                typecheck.ml:679–683
    bind qname ↦ arity; bind qname ↦ (params, fields) (* UNGATED, always *)
| ExCtor (parent_type, arity) ->                                             typecheck.ml:684–701
    ci_vis = if entry.ex_public then Public else Private;  add_ctor qname ci
```

`ExFn`/`ExValue` are the ONLY two export kinds this loader actually skips
when private (the comment at `typecheck.ml:663–672` states the design
in-line: "`ExType`/`ExRecord` stay UNGATED on purpose"). This is Task 1's
fix, landed earlier in this widening slice — before it, ALL four kinds loaded
unconditionally and `reject/t25`'s `Array.lst_rev(...)` (a real `pfn`,
`stdlib/array.march:39`) typechecked, compiled, and ran cross-module. Now:

```
reject/t26_cross_module_private_fn.march  →  "Function `lst_rev` is private to module `Array`."
```

re-confirmed live at this exact text (`typecheck.ml`'s `qualified_error_msg`,
line 778) — exit 1, both the same shape the `ExCtor` arm already produced for
a private constructor.

**The opaque-type asymmetry, stated precisely (and re-verified — not as
assumed).** `ExType`/`ExRecord` staying ungated means a private `ptype`'s
BARE TYPE NAME is nominally referenceable in a cross-module annotation even
though the type was never added to its module's `pub_set`. `accept/t34`
witnesses this directly: `ConsistentHash.HashRing(a)` is declared
`ptype HashRing(a) = HashRing(…)` (`stdlib/consistent_hash.march:19` —
private), yet `fn ring_arity(_ring : ConsistentHash.HashRing(String)) : Int`
typechecks and, called on a real ring built through the module's own public
`new`/`add` API, runs and prints `1`. `accept/t31` (Task 1's corpus) already
pins the same pattern; `t34` is an independent second witness that exercises
the annotation specifically (not merely an otherwise-unused param) and a
different stdlib module.

The design intent (`specs/lang/modules.md`'s "Visibility" section) is: `ptype`
hides everything (name AND constructor); a separate `opaque type` form hides
ONLY the constructor while keeping the type name public. **Live re-probing
for this task found the CURRENT implementation does not draw the line where
either of those two docs claims:**

- A plain `ptype`'s single (or multi-variant) constructor is **NOT hidden
  at all** — every stdlib `ptype` surveyed (`ConsistentHash.HashRing`,
  `Decimal.Decimal`, `Array.TrieEmpty`/`TrieLeaf`/`TrieBranch`) constructs and
  RUNS cross-module (e.g. `ConsistentHash.HashRing(Nil, Map.empty(), 3)` and
  `Decimal.Decimal(3, 2)`, both value-witnessed: exit 0, construct a real
  value). The grammar is the direct cause: every `variant` production
  defaults `var_vis = Public` (`parser.mly:964–972`); `ptype`'s own grammar
  rule (`parser.mly:453–460`, `DType (Private, …)`) sets the TYPE's `vis` to
  `Private` but never touches `var_vis` on its variants — only the SEPARATE
  `opaque type` rule (`parser.mly:436–440`) does
  (`List.map (fun v -> { v with var_vis = Private }) variants`). So
  `specs/lang/modules.md`'s "`ptype` makes both the type name and its
  constructors private" is not accurate against the current implementation —
  filed below.
- Even `opaque type` itself, whose grammar DOES force `var_vis = Private`
  (hence `ci_vis = Private`, since `ci_vis = v.var_vis` is copied verbatim at
  every registration site, e.g. `typecheck.ml:6686`), does **not** actually
  reject cross-module construction of its constructor either — probed live
  against `test/imports/opaque_qual/{oq_token,oq_entry}.march` (a genuine
  `MARCH_LIB_PATH`-discovered `opaque type Token = Token(String)`):
  `OqToken.Token("direct-bypass")` from unrelated code typechecks (exit 0)
  AND runs, constructing a real value that matches its own pattern and prints
  `"direct-bypass"`. Root cause traced precisely: a Pass-1 forward-reference
  pass, `prebind_mod_members` (`typecheck.ml:8067–8110`, called for every
  sibling `DMod` at `:8105`; the entry module's own top-level types get the
  same treatment at `:8110–8129`), registers each variant's qualified
  constructor key (`"Mod.CtorName"`) via `add_ctor qctor ci acc.ctors`
  (`:8056`) **unconditionally on `v.var_vis`** — only the SEPARATE
  disambiguated `"Mod.TypeName.CtorName"` key a few lines later checks
  `v.var_vis <> Ast.Public` before registering (`:8065–8070`). This Pass-1
  registration runs BEFORE `check_decl`'s `DMod` arm computes its own,
  correctly-`ci_vis`-filtered `new_ctors`/`qual_ctors` (§2.5 above), and the
  two results are MERGED (`typecheck.ml:6963–6969`, `StrMap.union` prepending
  the later pass's entries onto the earlier one's) rather than the later
  pass's filtering replacing the earlier, so the Pass-1 ungated entry for the
  bare qualified key survives into the final environment regardless. **This
  is the exact same shape as the pre-Task-1 `ExFn`/`ExValue` bug** (an
  earlier, ungated registration site shadows a later, correctly-gated one) —
  but for `opaque type`'s constructor, reached via the SAME-COMPILATION-UNIT
  `DMod` prebind path rather than the cross-file `Module_registry` path Task
  1 fixed. **This is a real, confirmed compiler gap, filed (not fixed —
  out of Task 3's docs-only scope and beyond Task 1's `load_module_into_env`
  fix), in `specs/todos.md`.** The PatCon (pattern-matching) side is
  differently, and also incorrectly, affected: matching `Mod.Ctor(…)`
  against a value produced by the module's own public API hits the
  UNRELATED, separately-filed qualified-type-unification gap for match
  scrutinees (`expected `Mod.Type` but got `Type`` — the pattern-typing
  analog of the `9001e4c0` fix below, which only covers type ANNOTATIONS, not
  match-arm scrutinee unification) rather than a visibility diagnostic,
  live-probed but not committed as corpus (it would conflate two different
  filed gaps in one program).
- The one piece that DOES work as documented: a `ptype`'s bare type NAME
  (not its constructor) is opaque-referenceable cross-module, exactly as
  `accept/t31`/`t34` witness, because `ExType` is genuinely, deliberately
  ungated in `load_module_into_env` — this half of the asymmetry is real and
  intentional, not a gap.

**The no-per-module-type-namespace design point (a design fact, not a
bug).** Types are exported and resolved by their BARE name only — the `DMod`
export step never qualifies a type name beyond the `pub_set` gate itself
("Types defined in a module … are referred to by their bare name throughout
user code, not prefixed", the comment at `typecheck.ml:6909–6911`
immediately above `new_types`'s definition). One direct, silent consequence:
**two sibling modules declaring a same-named type do not collide, because
they are not merely similarly-named — they are typechecked as the identical
nominal `TCon`.** `accept/t35` witnesses this precisely:

```march
mod A do type Foo = Mk(Int) fn make() : Foo do Mk(1) end end
mod B do type Foo = Mk(String) fn make() : Foo do Mk("x") end end
fn take_a(_x : A.Foo) : Int do 7 end
fn main() do println(int_to_string(take_a(B.make()))) end   -- accepts B.Foo where A.Foo is annotated
```

`--check` exits 0 with no diagnostic at all (re-confirmed live, exactly as
the survey found), and running it prints `7` — proving the substitution is
not merely un-flagged at check time but genuinely accepted end-to-end.
**This is documented here as ONE deliberate design point, not filed as a
bug:** March has no per-module type namespace; a module boundary partitions
FUNCTION/VALUE names (via `pub_set`) but never partitions TYPE identity.
Qualified type syntax (`A.Foo`) is sugar that always unifies with the bare
name `Foo` — there is no way to write two distinct, module-scoped types that
happen to share a bare name. (Cross-ref: this is the same underlying fact
the memory-flagged "app types collide with stdlib" note describes at the
application level — a user type bare-named the same as a stdlib type
collides with it for the identical reason.)

**Qualified-type-path unification (`9001e4c0`) — the mechanism that makes
the above possible, verified live in both directions.** Before this fix
(same-day as the modules survey), a qualified type annotation like
`Token.Token` resolved to a DISTINCT nominal `TCon("Token.Token", [])`,
different from the bare `TCon("Token", [])` every constructor/value actually
carries — so a value produced inside a module failed to unify against its
own qualified annotation from outside ("expected `Token.Token` but got
`Token`"). The fix canonicalizes a dotted type reference to its bare suffix
whenever that suffix denotes a same-arity type already in scope:

```
canon_name = match rindex_opt name '.' with                                 typecheck.ml:2317–2326
             | Some i -> let bare = suffix-after i in
                         (match lookup_type bare env with
                          | Some a when a = arity -> bare
                          | _ -> name)               (* not a valid canon target — no-op *)
             | None -> name                            (* non-dotted — no-op *)
```

using `String.rindex_opt` (the LAST `.`) rather than `split_qualified`'s
first-dot split, so it also canonicalizes arbitrarily-nested references like
`A.B.Type` (`typecheck.ml:2317–2327`, comment). Re-verified live, BOTH
directions, same-file nested module:

```march
mod Token do
  opaque type Token = Token(String)
  fn make(raw : String) : Token do Token(raw) end
end
fn process(t : Token.Token) : String do "ok" end
fn main() : String do process(Token.make("hi")) end   -- bare value -> qualified param, exit 0
```

and, reversed (a fn returning the qualified `Token.Token` consumed by a
bare-`Token`-annotated param) — also exit 0. Both directions produce only an
unused-variable warning, no type-mismatch diagnostic. **The qualified-record
case (`Cfg.Site`) — the survey's A10, flagged as "verify still green, don't
assume a gap" rather than a confirmed open item — was re-verified live for
this task and remains fully green**, both as a same-file nested-module
program (`accept/t36`) and via the pre-existing `test/whole_program/{cfg,
app}.march` MARCH_LIB_PATH fixture (`test/dune:614–626`'s dedicated
regression rule): `MARCH_LIB_PATH=test/whole_program ./_build/default/bin/
main.exe --check test/whole_program/{cfg,app}.march` both exit 0, re-run for
this task. `accept/t36` pins the identical shape same-file, in this corpus,
value-witnessed (prints `Site`, the record's own field, read back through
the cross-module qualified annotation `s : Cfg.Site`) — no gap found; Task 1's
`ExFn`/`ExValue` gate does not touch this case (`Site`/`default`/`site_title`
are all public here), and the record path canonicalizes through the same
`surface_ty` machinery as the ordinary named-type case above.

**Corpus (this task):**

- `accept/t34_opaque_ptype_qualified_annotation` — `ConsistentHash.HashRing`
  (a private `ptype`) used as a cross-module param annotation; value-witnessed
  (prints `1`). Second, independent witness for the opaque-type-NAME half of
  the asymmetry (`accept/t31` is the first, for `Array`).
- `accept/t35_no_per_module_type_namespace` — the `A.Foo`/`B.Foo` collision;
  value-witnessed (prints `7`), pinning the design point as a tested behavior
  rather than a discoverable surprise.
- `accept/t36_qualified_record_type_still_green` — the A10 record case,
  same-file nested-module form; value-witnessed (prints `Site`), confirming
  no regression from either `9001e4c0` or Task 1's visibility fix.
- The private-FUNCTION reject (`reject/t26_cross_module_private_fn`) and the
  narrow-gate accept witness (`accept/t31_cross_module_public_and_opaque_
  ptype`) both already live in Task 1's corpus — cross-referenced above, not
  duplicated here.

**Filed, not fixed (out of this task's docs-only scope):** the `opaque
type` constructor-hiding gap found above (`prebind_mod_members`'s ungated
qualified-ctor registration at `typecheck.ml:8091`, surviving the later,
correctly-filtered `DMod` export step's merge) — a real enforcement hole
structurally identical to the bug Task 1 fixed for `ExFn`/`ExValue`, but on
the same-compilation-unit path rather than the `Module_registry` path, and
for the `ExCtor`/`ci_vis` gate rather than the `ExFn`/`ExValue` gate. Also
filed: `specs/lang/modules.md`'s "Visibility" section overclaims `ptype`
constructor-hiding (says `ptype` hides "both the type name and its
constructors" — live-verified false, the constructor is public by grammar
default) and should be corrected to match the verified current behavior
(only `opaque type`'s constructor is EVER marked private, and even that
marking is not actually enforced against qualified construction, per the
gap just filed).

**Cross-reference — `use`/`import`'s selective-name rejection is the SAME
`pub_set` gate, one layer up (widening slice 2, Task 4).** `core-march.md`
§4.7.1 documents `use X.{name}`/`import X, only: […]` — the surface forms
that rebind an already-exported qualified name (`"X.name"`) as a bare name in
the CURRENT scope. Their selective-name lookup (`typecheck.ml`'s `DUse`
`UseNames`/`UseExcept` arms) reads the identical `env.vars` entries this
subsection's `pub_set` gate populates — so a selective `use` of a private
member (`use Array.{lst_rev}`, `lst_rev` a real `pfn`) is rejected for
exactly the reason a bare qualified reference to it is (`reject/t26` above):
the key was never written. The message text differs (`` Module `Array` does
not export `lst_rev`. `` vs. `reject/t26`'s `` … is private to module
`Array`. ``, since `UseNames`'s lookup cannot distinguish "absent" from
"private" the way `qualified_error_msg` can — but the OUTCOME is identically
a hard reject), confirmed live and pinned as
`reject/t27_use_selector_private_name`. This is not a second, independent
enforcement mechanism — it is the same `pub_set` absence surfacing through a
second syntactic front door.

### 2.6 Actors: declaration, spawn, and `Pid` typing

March's actor construct — `actor Name do state { … } init { … } on Msg(…) do
… end end` — is checked by `typecheck.ml`'s `DActor` arm (`Ast.DActor (_vis,
name, actor, _sp)`, `typecheck.ml:6742`). This subsection pins **what that arm
verifies** and, separately, **what type `spawn(Name)` actually produces** — the
two are governed by different code and, as it turns out, disagree about the
`Pid` type parameter in a way worth stating plainly.

#### 2.6.1 What the actor declaration checks

The `DActor` arm performs, in order (`typecheck.ml:6742–6821`):

1. **State type construction (`:6744–6748`).** The `state { f : T, … }` field
   declarations are turned into a canonical `TRecord` — each field's surface
   annotation resolved by `surface_ty`, then the fields **sorted by name** so
   the state type has a stable structural identity regardless of source order.
   This record type is the actor's *state type*, written `state_ty` below.

2. **Duplicate-handler rejection (`:6752–6760`).** Two `on Msg(…)` arms with the
   *same* message name are a hard error (`` actor '…' defines handler '…' more
   than once ``) — the only diagnostic the arm raises unconditionally.

3. **Constructor registration (`:6768–6784`).** Two kinds of constructor are
   added to the environment:
   - the **actor name itself** as a *nullary* constructor whose result type is
     the actor's own name (`add_ctor name.txt { ci_type = name.txt; ci_arg_tys
     = []; … }`, `:6769`) — this is what makes a bare `spawn(Counter)` /
     `Counter` resolve at all as an `ECon(_, [], _)`;
   - one **message constructor per handler** (`ci_type = name.txt ^ "_Msg"`,
     `:6781`), so `send(pid, Msg(x))` typechecks. Unannotated handler params get
     a per-`(handler, position)` placeholder tyvar (`"$p<i>_<Msg>"`, `:6778`)
     that instantiates to a fresh variable, so an omitted annotation does not
     block `send`.

4. **`init` checked against the state type (`:6785–6787`).** The `init { … }`
   expression is checked (not merely inferred) against `state_ty`, with the
   reason `` actor init must return the initial state record `` — so an `init`
   whose record shape disagrees with the declared `state {…}` fields is
   rejected here.

5. **Each handler body checked to RETURN the state type (`:6789–6820`).** Every
   `on Msg(…) do … end` body is typechecked in an environment where `state` is
   bound to `state_ty` (`:6790` — the field is read as `state.field`, *not*
   `self.field`) and each declared message param is in scope (`:6792–6798`). The
   body's inferred type is then unified against `state_ty` (`:6805–6806`); a
   mismatch produces the rich `` handler '…' in actor '…' must return the state
   type `` diagnostic (`:6811–6819`) — this is what enforces the convention that
   a handler ends by returning the *new* state record.

#### 2.6.2 `spawn` — resolved by literal actor name at compile time

`spawn` is typed by the `ESpawn` arm (`Ast.ESpawn (actor, _)`,
`typecheck.ml:4185`). It first infers the argument (`ignore (infer_expr env
actor)`, `:4186`) and then **requires the argument to be a bare actor name**:
only `ECon(_, [], _)` or `EVar` are accepted (`:4194–4202`). Anything else — an
`if`, a `match`, a function call, or a payload-carrying `A(x)` — is rejected
with the fixed diagnostic (`:4197–4202`, verified live):

> `` `spawn` needs a plain actor name written directly, like `spawn(Counter)`. ``
> A computed actor expression (from an `if`, `match`, or function call) isn't
> supported: March resolves which actor to spawn at compile time from its name.

The rationale is in the source comment (`:4187–4193`): both backends dispatch
`spawn` by the actor's *name*, resolved at compile time to a statically
generated `<Actor>_spawn` function; there is no runtime actor-descriptor value,
and the TIR lowering assumes exactly the `ECon(_, [], _)` / `EVar` shape — so
the typechecker rejects a computed actor expression up front rather than letting
a well-typed program reach the internal `failwith` in lowering. This is
witnessed by `reject/t28_spawn_computed_actor` (`spawn(pick())`, pinning the
first line of the message).

#### 2.6.3 The `Pid` type parameter — the truthful account (a finding)

The natural expectation — and the wording carried into this task — is that
`spawn(Counter)` yields `Pid[state]`, i.e. a `Pid` parameterized by the actor's
STATE type. **Live probing shows this is false at the surface.** What is true:

- **`spawn` returns `Pid[<fresh unification variable>]`, not `Pid[state]`.** The
  `ESpawn` arm's result is `TCon ("Pid", [fresh_var env.level])`
  (`typecheck.ml:4203`; `t_pid a = TCon ("Pid", [a])`, `:983`) — a *fresh,
  unconstrained* variable, computed with no reference to the state type. Probe:
  `let p = if true do spawn(Counter) else spawn(Named) end`, where `Counter`'s
  state is `{ count : Int }` and `Named`'s is `{ name : String }`, **typechecks
  clean** — the two `if`-branches unify only because each `spawn` produced an
  independent free var. Were the parameter the state type, the branches would be
  `Pid({count:Int})` vs `Pid({name:String})` and the `if` would be rejected by
  T-If. It is not.

- **The `Pid[state_ty]` binding at `:6821` exists but is effectively
  unobservable.** After checking the handlers, `DActor` does `bind_var name.txt
  (Mono (TCon ("Pid", [state_ty]))) env_with_ctors` (`:6821`) — the actor *name*
  is var-bound to `Pid[state]`. But a bare occurrence of the actor name never
  reaches this binding: the *constructor* registration at `:6769` (the actor as
  a nullary `ECon` of type `<Name>`) takes precedence, so a bare `Counter` is
  typed `Counter`, not `Pid[state]`. Probe: `is_alive(Counter)` (where
  `is_alive : Pid(a) -> Bool`) is **rejected** with `` expected `Pid(r3)` but
  got `Counter` `` — the name resolves to the nullary ctor's `Counter` type, not
  the `Pid[state]` value binding.

- **Even an explicit `Pid[T]` annotation is impossible today.** The built-in
  `Pid` is registered at arity 1 (`builtin_types`, `typecheck.ml:1849`), but the
  stdlib module `GlobalPid` declares `type Pid = { node_id : String, local_pid :
  Int, creation : Int }` (`stdlib/global_pid.march:11`) — a *0-arity record*.
  Because March has a single global type namespace with no per-module type
  identity (§2.5, the no-per-module-type-namespace design point), that bare
  `Pid` **shadows** the built-in in `env.types`, so a surface annotation
  `Pid(T)` is rejected with `` `Pid` expects 0 type argument(s) but got 1. ``
  (arity check, `:2348–2351`). There is thus no annotation the surface can write
  to *force* a `Pid`'s parameter to the state type either.

**Net:** the state type is genuinely *checked* — `init` and every handler must
conform to it (§2.6.1) — but it does **not** propagate to any observable `Pid`
at a `spawn` site. `spawn(Counter) : Pid[α]` for a fresh `α`; the `α` unifies
opportunistically with whatever the surrounding builtins demand (e.g. the `a` in
`is_alive : Pid(a) -> Bool`, `:1341`), and stays free otherwise. The
"`Pid[state]`" phrasing is therefore aspirational, not a fact about the current
typechecker; `accept/t39_actor_spawn_pid` witnesses the accept path (`is_alive`
on a fresh `spawn` result), and this finding is logged in §4.1.

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
13. **[RESOLVED 2026-07-05, commit `7e40dc5b`]** — the duplicate-diagnostic
    quirk noted at the end of this finding is fixed: the `ELetFn` arm now
    measures the `env.errors` count before/after the return-annotation unify
    and, if it grew, routes the later self-type/arrow reconciliation through a
    scratch (discarded) error context, so the identical mismatch is reported
    ONCE (verified via `--check-json`; two genuinely-distinct errors still both
    report). Corpus witness `reject/t12` unchanged. The typing-rule description
    below (monomorphic-then-generalized `ELetFn`) is unaffected and remains
    accurate. **A local recursive function (`ELetFn`) is monomorphic inside its
    own body and generalized only afterward — but via a DIFFERENT mechanism than
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
15. **[RESOLVED 2026-07-05, commit `8cbd6dd2`]** — root cause found and fixed.
    The `when Eq(a)` argument `a` (an unannotated VALUE parameter) was resolved
    only against `fn_tvars` (signature type-variable names), which has no entry
    for a value-parameter name, so `check_fn` minted a FRESH placeholder var
    disconnected from the parameter's actual type and attached the constraint to
    THAT — a phantom `generalize` quantified away, so at each call site
    `instantiate` substituted it with an independent fresh var never bound to the
    argument, and `discharge_constraints` always saw an `Unbound` TVar and
    skipped it. Fix (`lib/typecheck/typecheck.ml`): when the `when`-clause name
    isn't a signature type var, resolve it against the value-parameter binding in
    `body_env` and attach the constraint to the parameter's own type variable, so
    it survives generalization, rides through `instantiate` onto the caller's
    `pending_constraints`, and is discharged at the call site. `same(Rood,Rood)`
    now rejects; satisfiable generic constraints still accept (corpus
    `accept/t22`, `reject/t17`). The soundness-gap analysis below is retained for
    the record. **A `when Interface(a)` constraint on an explicit function bound
    is correctly enforced when it can be discharged AT THE FUNCTION'S OWN
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
16. **[RESOLVED 2026-07-05, commit `f0f5299c`]** — the annotation is now a
    CHECKING context. A new `infer_let_annotated` helper resolves `bind_ty` via
    `surface_ty` and checks the RHS against it with `check_expr` (so a
    polymorphic RHS bound at a more specific instance still works), falling back
    to plain inference only when the annotation isn't a resolvable type (a
    phantom/typestate tag). `let x : Int = "foo"` now rejects; `accept/t21` +
    `reject/t16` pin both directions. The gap analysis below is retained for the
    record. **`let`-binding type annotations (`let x : T = e`) WERE parsed but
    never enforced by the typechecker — the second filed, open gap.** Found while
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
17. **[OPEN — filed, not fixed] `derive X for UnknownType` silently no-ops: no
    diagnostic, exit 0, program runs as if the `derive` line were absent.**
    Found while building §2.4's `derive`/`satisfy` widening. `expand_derive`'s
    `None` branch (`desugar.ml:1659`) returns a bare `[]` when the target type
    name isn't found in the module's collected `type_defs` — no `Err.error`
    call, unlike the symmetric "unknown INTERFACE" case in the very same
    function (the `_ -> Err.error …` catch-all in `derive_impl`,
    `desugar.ml:1641–1647`) and unlike `satisfy`'s own unknown-interface and
    missing-function checks (§2.4), both of which DO reject. Minimal repro,
    re-verified live for this task:
    ```
    mod M do
      derive Eq for Ghost           -- `Ghost` is never defined anywhere

      fn main() do
        println("no error, no Ghost type defined")
      end
    end
    ```
    `--check` exits **0** (no diagnostic); running it also exits **0** and
    prints `no error, no Ghost type defined` — the `derive` line has zero
    observable effect, silently. Filed in `specs/todos.md` under "Compiler:
    Type System" with this repro and the `desugar.ml:1659` citation; fixing it
    (rejecting an unknown derive TARGET TYPE the same way an unknown derive
    target INTERFACE already is) is a compiler change, deliberately out of
    scope for this documentation slice. Not encoded as a `reject/` corpus
    program for the same reason findings 15–16 aren't: a `reject/` witness
    would assert behavior this finding identifies as WRONG (the program
    currently, incorrectly, `--check`s clean) — once fixed, a
    `reject/derive_unknown_type`-style program should be added here.

18. **[OPEN — filed, not fixed] `spawn(Actor)` does NOT yield `Pid[state]`; the
    `Pid` parameter is an unconstrained fresh variable, and the state type never
    reaches an observable `Pid`.** Found while building §2.6 (actors widening,
    Task 1). The `ESpawn` arm returns `TCon ("Pid", [fresh_var env.level])`
    (`typecheck.ml:4203`), a fresh var computed with no reference to the actor's
    state type. The `bind_var name.txt (Mono (TCon ("Pid", [state_ty])))` at
    `:6821` *does* record the state type against the actor name, but that binding
    is unreachable from a bare occurrence: the nullary-constructor registration
    at `:6769` (actor name ⇒ type `<Name>`) shadows it, so a bare `Counter` is
    typed `Counter`, not `Pid[state]`. Live probes (re-verified for this task):
    `let p = if true do spawn(Counter) else spawn(Named) end` typechecks clean
    with `Counter`/`Named` carrying *different* state records (proving each
    `spawn` yields an independent free var, not `Pid[state]`); `is_alive(Counter)`
    is rejected `` expected `Pid(r3)` but got `Counter` `` (the name is the
    nullary ctor, not the `Pid[state]` value). Compounding it, no surface
    annotation can pin the parameter either: the built-in arity-1 `Pid`
    (`typecheck.ml:1849`) is shadowed in the single global type namespace (§2.5)
    by stdlib `GlobalPid`'s 0-arity `type Pid` record (`stdlib/global_pid.march:
    11`), so `Pid(T)` annotations reject `` `Pid` expects 0 type argument(s) but
    got 1. ``. So the state type is *checked* inside the actor decl (init +
    handler conformance, §2.6.1) but is not carried by the `Pid` at any `spawn`
    site. This is a faithfulness note, not a corpus reject (there is no
    *incorrect* program to pin — `accept/t39_actor_spawn_pid` witnesses the
    actual, fresh-var accept behavior); tightening `spawn`'s result to
    `Pid[state]` (or making the actor name resolve to its `:6821` `Pid[state]`
    binding) would be a compiler change, out of scope for this docs slice. See
    §2.6.3 for the full account.

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
  built-ins — LANDED (§2.3/§2.4, 2026-07-06).** §2.1a/§2.1b document how a
  `Num`/`Eq`/`Ord`/`Show` CONSTRAINT is discharged against the seed table
  (`builtin_impls`, `builtin_interfaces`); §2.3 covers the general
  `interface`/`impl` declaration-checking machinery itself — registration,
  missing/extra-method rejection, signature-match, default methods,
  superclass/`requires` and `when`-clause discharge (both mandatory
  enforcement), and the `impl_matches_ty` structural-match judgment as its
  own named rule, `(T-ImplMatch)`; §2.4 covers `derive`/`satisfy` as `DImpl`
  generators. Coherence/overlap — no rejection of overlapping impls exists at
  all, and `(T-ImplMatch)` performs no specificity resolution between two
  simultaneously-matching impls — is noted on the typing side (§2.3, `(T-Impl)`
  step 1) and documented in full, with live-captured interpreter-vs-compiled
  evidence, in the operational companion `core-march.md` §4.4.3 as an open,
  deliberately-unresolved divergence (filed in `specs/todos.md`, not fixed by
  this documentation slice). Roadmap: an extension of Phase 2 (§4.3's
  "declarative typing rules... extracted from `typecheck.ml`'s algorithm").
- **The constraint-survival soundness gap itself (finding 15, §4)** — RESOLVED
  2026-07-05 (commit `8cbd6dd2`): the `when`-clause now attaches the constraint
  to the value parameter's own type variable, so it survives generalization and
  is re-checked at call sites. The general `impl Iface(T)` declaration-checking
  machinery (previous bullet) remains the Phase-2 widening item.
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
of the roadmap, adjudicating the operational side's `known_divergence` queue.
This document's queue of filed typechecker gaps has **one genuinely open
item**, added by the interfaces/impls widening slice: **finding 17** (§4.1,
`derive X for UnknownType` silently no-ops) is OPEN — filed in
`specs/todos.md` under "Compiler: Type System," deliberately NOT fixed by this
documentation-only slice. The three PRIOR filed gaps — findings 13, 15, and
16 — were all RESOLVED 2026-07-05 (commits `7e40dc5b`, `8cbd6dd2`,
`f0f5299c`), with corpus witnesses (`reject/t16`, `reject/t17`, `accept/t21`,
`accept/t22`) and unit tests. The widening slice's operational companion,
`core-march.md` §4.4.3, also filed a second open item this slice — the
impl-coherence/overlap interpreter-vs-compiled divergence, documented there in
full with both backends' outputs and filed in `specs/todos.md` alongside
finding 17.
