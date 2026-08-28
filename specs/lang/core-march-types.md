# Core March: Static Semantics reference v1 (core fragment complete)

**Date:** 2026-07-05
**Status:** Reference v1: the Core March **type system**'s core fragment is
now complete end-to-end, the companion to the operational semantics in
`core-march.md`. Built incrementally as a walking skeleton (Tasks 1–6, see §5
for the per-task provenance) and consolidated into this single reference by
Task 7: assembly + versioning only, no new typing rules were added in this pass.
**Companion:** `specs/lang/core-march.md` (operational semantics, "what programs
mean"). This document is "which programs are well-typed."
**Depends on:** `specs/archive/2026-07-04-language-specification-roadmap-design.md` §4.3.

---

## 0. What this is (and is not)

`core-march.md` documented the interpreter's *operational* rules. This document
documents the *typechecker's* rules, the `Γ ⊢ e : τ` judgment, for the core
fragment: literals, variables, `let` (with generalization), lambda,
application, the `+`/`==` primitives, `if`, **ADT constructors and `match`**
(Task 1), **tuples and records** (Task 2), **atoms** (Task 3), **match guards
and scrutinee-less `match do` (`ECond`)** (Task 4), **local recursive
functions (`ELetFn`)** (Task 5), and **the interface-constraint model**
(`Num`/`Eq`/`Ord`/`Show` discharge, §2.1/§2.1a/§2.1b) and the boolean
primitives `&&`/`||`/`not` (Task 6). Task 7 (this pass) added no new typing
rules: it re-titled/re-scoped this document from "walking skeleton, first
vertical slice" to "reference v1, core fragment complete," unified §2 into one
rule set grouped by construct, collected the accumulated findings into a
single §4 subsection, refreshed the deferred list against the roadmap's
Phase-2b/3 queue, and wired `check_types.sh` into a CI lane (see
`specs/lang/types/INDEX.md`). Same discipline as the operational skeleton:
**every rule is transcribed arm-for-arm from `lib/typecheck/typecheck.ml` and
cited by line**, and a conformance corpus keeps it accurate.

The conformance mechanism differs from the operational side. There is only **one**
typechecker (it runs before both `eval` and `--compile`), so there is no output to
*differentially* diff. Instead the anchor is the compiler's own `--check` mode
(`march --check file.march`: exit 0 = well-typed, exit 1 + a `-- ERROR --`
diagnostic = rejected). The corpus (§3) is split into **`accept/`** programs
(must typecheck) and **`reject/`** programs (must be rejected *with a specific
error message*). This catches both a spec that misdescribes the typechecker and a
typechecker regression.

**Widening slice (2026-07-06):** §2.3 extends the built-in-only constraint
material above with user-defined **`interface`/`impl` DECLARATION checking**
itself: what makes an `interface Iface(a) do ... end` or `impl Iface(T) do
... end` well-formed, as opposed to how a `Num`/`Eq`/`Ord`/`Show` constraint is
*discharged* against the built-in seed table (§2.1a, unchanged). §2.3 also
covers superclass/`requires` and `when`-clause discharge (both MANDATORY
enforcement, not conditional gaps) and names the `impl_matches_ty` structural
match as its own rule, `(T-ImplMatch)`: the judgment both discharge paths
share, and the reason generic/parameterized impls work at all. §2.4 covers
`derive`/`satisfy` as `DImpl` *generators*. **STALE (2026-07-06) →
CORRECTED (2026-07-22):** the coherence/overlap story (what happens when TWO
impls both match the same target) used to be documented here as an open,
logged interpreter/compiled runtime-selection divergence, cross-referenced to
`core-march.md` §4.4.3. That divergence was **closed 2026-07-17**: a
coherence check (`register_impl_shape`, `lib/typecheck/typecheck.ml`) now
REJECTS overlapping impls of the same interface/type-head at typecheck, so
the question "which of two matching impls runs" no longer arises for a
program that passes `--check` (mod the built-in-overlap and
same-short-name-different-module carve-outs; see §2.3 item 1 and
`core-march.md` §4.4.3, both rewritten 2026-07-22 with live-reproduced
current behavior).

**Deferred to later phases** (the roadmap's Phase-2b/3 queue, §6): refinements
(z3-discharged), effects, and most of the capability lattice (`lib/caps/`);
see §6 for the full deferred-set breakdown and its roadmap citations; §2.8
(added 2026-07-07) lands the capability lattice's first layer (IO permission
hierarchy, `needs`, `Cap(X)` signature enforcement), with the rest of the
system still queued. Impl-coherence is no longer in scope as a queued
design decision either; it was made (Rust-style: reject overlap entirely)
and landed 2026-07-17, per the correction above.

**Widening slice 2 (2026-07-06, modules):** §2.5 adds **module visibility as
a typecheck concept**: `pub_set`-filtered export, the cross-file
`load_module_into_env` gate (`ExFn`/`ExValue`, fixed by this slice's Task 1),
and the **opaque-type imbalance** it intentionally preserves (`ExType`/
`ExRecord` skip the visibility gate, so a private `ptype`'s bare NAME is nominally
referenceable cross-module even though its declaring module never marked it
public), together with the **no-per-module-type-namespace design point**
(types resolve by bare name only, so two sibling modules' same-named types
are literally one nominal type, not just visually similar) and the
`9001e4c0` qualified-type-path unification that is the flip side of the same
design. §2.5 also files a real, precisely-traced enforcement gap found while
verifying the imbalance live: `opaque type`'s constructor-hiding is NOT
actually enforced against qualified construction (a `prebind_mod_members`
forward-reference pass registers the qualified ctor key with no gate on
`var_vis`, before the later, correctly-filtered `DMod` export step's result
is merged in), in structure the same class of bug Task 1 fixed for
`ExFn`/`ExValue`, but on a different registration path; logged, not fixed
(out of this docs-only task's scope). `core-march.md` §4.7 (this slice's
Task 2) is the operational companion: `own_names`-gated export, bare-fails/
qualified-works name resolution, and the lexical-scoping nuance for a
directly-nested module.

**Widening slice (session types, 2026-07-06):** §2.7 adds **session-typed
channel/protocol typing**: greenfield content, the first coverage this
document has for `protocol`/`Chan`/`MPST`. `protocol Name do ... end`
declaration (three step forms: `ProtoMsg`/`ProtoLoop`/`ProtoChoice`), the
per-role local `session_ty` a protocol PROJECTS onto (`project_steps`/
`project_protocol`), binary duality (`dual_session_ty`, the `dual(A) == B`
check), MPST send/recv-pair consistency (documented as TYPING-ONLY: the
compiled MPST runtime is broken, a separate finding logged by the operational
widening task; **F3 was re-checked 2026-07-27 and no longer recurs:** a
3-role and a 4-role MPST protocol both compile and run correctly,
interp == compiled; what truly remains unimplemented is multiparty
`choose`/`offer`; see §2.7.4), and the `Chan(Role, Proto)` linear endpoint
type. Also files
**F4**: a real typing bug where the MPST merge rule (meant to let a
non-chooser role skip an irrelevant choice) leaks into the BINARY duality
check, wrongly rejecting a legal binary protocol with two `choose` branches that
happen to carry the same payload type. **F4 is now FIXED**; see §2.7.5 and
§4.1 finding 20. Per-op channel state-ADVANCEMENT
(`Chan.send`/`recv`/`choose`/`offer`/`close` typing) is a separate, later
widening task; §2.7 documents the protocol/projection/duality layer only.

**Widening slice (session types, Task 3, 2026-07-06):** §2.7.8 extends §2.7
with the per-operation channel typing that Task 2 explicitly deferred: the
required incoming session state, what each op checks, and the advanced
outgoing state for `Chan.new`/`send`/`recv`/`close`/`choose`/`offer` (cite
the exact arm for each). Also files **F5** (§2.7.9): `Chan.offer` always
returns the FIRST branch's continuation type regardless of which branch the
peer actually chose at runtime: a documented conservative approximation
that is a real (if narrow) soundness gap for `offer` over branches with
DIFFERENT continuations. Six new `reject/` programs (`t30`–`t35`) pin the
live per-op violation messages, plus one new `accept/` program (`t43`) for a
full `choose`/`offer` round-trip. **F5 is now FIXED** (session-types
correctness fixes, Task 4, 2026-07-24); see §2.7.9 and §4.1 finding 21.
That same later effort also re-checked **F3** (§2.7.4) as no longer
reproducing, and fixed two further session-type projection/typing gaps not
found until then; see §4.1 findings 22–24.

**Capabilities widening, Task 1 (2026-07-07):** §2.8 adds the FIRST
capability/effect-system content this document has: greenfield, like §2.7's
session-types debut. It covers the IO permission hierarchy (18 entries, one
tree rooted at `IO`), `cap_subsumes`/`normalize` subsumption, the `needs`
module manifest, and **Check 1**: every `Cap(X)` in a function/actor/extern
signature must be covered by a declared `needs`, else ERROR. Files a live
scoping finding: only 10 of the 18 hierarchy entries are registered as valid
`Cap(X)` type ARGUMENTS today (`builtin_types`, `typecheck.ml:1858-1861`);
the other 8 are valid `needs` targets but reject as `` Unknown module `IO` ``
if written inside `Cap(...)`; the corpus draws only from the 10 that work.
Four new `accept/` programs (`t45`–`t48`: bare-covered, root-covers-child
subsumption, sibling independence, a second mid-tier subsumption shape) and
three new `reject/` programs (`t36`–`t38`: uncovered, narrow-does-not-cover-
broad, sibling-does-not-cover-sibling). Task 2 (§2.8.6-§2.8.7) added
transitive `use`/extern-implied caps (Checks 4/1c/5); Task 3 (§2.8.8-§2.8.9)
added `cap_narrow`/`root_cap` threading, the effect-inference two
projections, migrate_state IO-freedom (Check 8), and realtime exclusion
(Check 7); Task 4 (§2.8.11-§2.8.12) added the five BEHAVIORAL module caps
(`no_panic`/`no_alloc`/`no_extern`/`pure`/`deterministic`) and logged two
soundness gaps (F2, F3) as open; Tasks 5 and 6 then FIXED F2 and F3
respectively (real compiler fixes, gated on the full test suite), each with
its own now-possible `reject/` witness. Task 7 (closeout) finalized §2.8 to
describe F2/F3 as fixed, reconciled the `capabilities.md` tutorial, and logged
two further findings (the proof-cap mint mismatch, intentionally unlabeled
since `F1`–`F8` are all already in use elsewhere in this document, deferred
to a later proof-caps slice; and a residual guarded-match exhaustiveness
gap F3 inherited but did not introduce). The guarded-match gap was
subsequently FIXED (fix-campaign batch 3, 2026-07-07): `check_exhaustiveness`
now computes coverage over the GUARDLESS branches of a guarded match and
records the span when they are non-exhaustive, so a guarded non-exhaustive
match in a `cap no_panic` module is now an ERROR (§2.8.11, §2.1a; witnesses
`reject/t50`, `accept/t59`). **Proof-cap mint/forge is now FIXED too** (widening
slice 6, 2026-07-08): a dedicated §2.8.13 gives proof capabilities their first
rule-numbered treatment (Check 1 self-declaration, Check 6 pass-through, the
gated `mint_cap` mint surface, and the `cap_narrow` proof-cap restriction) and
§2.5.1's `(T-QualRef)` establishes the general soundness property (an
intra-module reference is checked against the function's real body-checked
scheme regardless of nesting) that the proof-cap forge's deepest exploitation
depended on. Witnesses `reject/t51`–`t57`, `accept/t60`–`t63`.

## 1. The typing judgment

March's typechecker is **bidirectional Hindley–Milner**: two mutually-recursive
modes over the desugared AST (`typecheck.ml`):

- **synthesis** `infer_expr env e : ty` (:3236): "compute `e`'s type", written `Γ ⊢ e ⇒ τ`.
- **checking** `check_expr env e expected ~reason` (:4164): "check `e` against a
  known type", written `Γ ⊢ e ⇐ τ`.

Types `τ`, schemes `σ`, and environment `Γ`:

```
τ ::= Int | Float | Bool | String | Atom      -- TCon(name,[])          typecheck.ml:943–948
    | τ → τ                                    -- TArrow
    | α                                        -- TVar (unification var, carries a level)
    | C(τ…) | (τ,…) | { l:τ,… }                -- TCon(C,args) / TTuple (§2, T-Tuple) / TRecord (§2, T-Record)

σ ::= τ | ∀ᾱ [C̄]. τ                            -- Mono τ | Poly(ids, constraints, τ)
```

A scheme `σ` may carry **interface constraints** `C̄` (e.g. `Num a`, `Eq a`),
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

- **`instantiate level env sch` (:901–937)**: `∀ᾱ[C̄].τ` → a monotype by
  replacing each quantified `αᵢ` with a *fresh unification variable at the
  current level* (:904, `subst`); each constraint in `C̄` has its own type
  argument substituted the same way (:929–934, `inst_cs`) and the resulting,
  freshly-instantiated constraints are prepended onto
  `env.pending_constraints` (:936); **this is the CREATION site**: every
  occurrence of a constraint-carrying variable (`+`, `==`, `<`, `show`, …,
  §2.1) pushes a fresh obligation here, exactly like `EVar`'s ordinary T-Var
  instantiation (§1 above); constraint creation is not a special case of
  `EVar`/T-Var, it is a side effect woven into the SAME function.
- **`generalize level τ` (:845–895)**: quantify every unbound unification
  variable in `τ` with level `> level` (the ones "born inside" the current
  `let`), yielding a `Poly` scheme. Uses a **level** discipline (each `let`
  RHS is typed at a bumped level via `enter_level`) instead of a global
  free-variable scan. **Critical subtlety:** `generalize` ALWAYS returns
  `Poly (ids, [], copy ty)`, an EMPTY constraint list (:894), regardless of
  what constraints are pending; it also allocates **fresh, isolated `TVar`
  refs** for each quantified id (:866–869, "so a later function body can
  unify the original TVar" without corrupting an already-stored scheme) that
  share only the *integer id*, not the ref cell, with whatever `TVar` a
  constraint elsewhere still points at. `generalize` itself never attaches a
  constraint to the scheme it builds; callers that want a constraint to
  survive generalization must re-attach it explicitly afterward (this is
  exactly what `check_fn`'s `when`-clause handling does, and where it can go
  wrong; see the §4 finding on `when`-bound constraints below).

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
          --   and `specs/todos/` ("Compiler: Type System") for the full
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
          --   Not fixed here (docs-only task); noted in `specs/todos/`.
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

**(T-Guard)**: the guard clause of T-Match, stated separately for the `when g`
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

**Exhaustiveness and redundancy: WARNING, NOT AN ERROR.** This note is part
of (T-Match): both checks run unconditionally at the end of every `match`
(`typecheck.ml:4288–4289`, and the `EMatch` arm of `check_expr`,
`typecheck.ml:4199`), but neither can fail typechecking.

```
check_exhaustiveness env span scrut_ty branches                      typecheck.ml:3159–3185 (defn), 4288 (call site)
check_redundant_arms  env      scrut_ty branches                     typecheck.ml:3131–3155 (defn), 4289 (call site)
```

Both diagnostics are constructed with `severity = Warning`:
  - non-exhaustive, with a concrete missing-case example: message
    `"Non-exhaustive pattern match — missing case: %s"`              (typecheck.ml:3172–3177)
  - non-exhaustive, no concrete example available: message
    `"Non-exhaustive pattern match"`                                 (typecheck.ml:3179–3184)
  - a redundant (unreachable) arm: message
    `"This pattern can never be reached."`                           (typecheck.ml:3143–3151)

**⚠ THIS IS THE BRITTLE, CRITICAL FACT OF THIS SLICE:** `--check`'s exit
code is driven by `has_user_errors`, which filters strictly on `d.severity =
March_errors.Errors.Error` (`bin/main.ml:819–821`) — a `Warning`-severity
diagnostic (either of the above two kinds) NEVER sets `has_user_errors`, so a
non-exhaustive `match` or a redundant arm **typechecks (`--check` exits 0)**.
This is NOT "the typechecker forgot to check exhaustiveness":
`check_exhaustiveness` runs on EVERY `match` (unconditionally, at the end of
both `infer_match` and the `EMatch` arm of `check_expr`, typecheck.ml:
4199/4288) and DOES emit a diagnostic for a missing case; that diagnostic is
simply non-fatal by design.

When ANY branch of the match has a guard, the ordinary Warning is SKIPPED
(exact coverage is undecidable once a guard is present: a guard can make an
otherwise-total pattern set partial at runtime via E-Match's guard-false
fall-through, core-march.md:741–751). But a guarded match can still DEFINITELY
panic, so `check_exhaustiveness` no longer returns immediately in the guarded
case: it computes coverage over the GUARDLESS branches ONLY (`let
guardless_matrix = List.filter_map (fun br -> match br.branch_guard with None ->
Some [norm_pat br.branch_pat] | Some _ -> None) branches`, typecheck.ml:3315–
3332). A branch reachable only behind a guard cannot be relied on to match, so
it contributes no GUARANTEED coverage; if the guardless branches by themselves
are non-exhaustive the match can panic when every guard fails at runtime. In
that case the span is RECORDED into `env.nonexhaustive_match_spans` (so
`check_no_panic_module` promotes it to an error inside a `cap no_panic` module,
§2.8.11) but NO global Warning is emitted: guarded matches are common in
ordinary code and get no warning today, so only `cap no_panic` modules (which
opt into strictness) are made stricter. (An all-guarded match yields an empty
guardless matrix, which `find_missing_mc` correctly reports as non-exhaustive
rather than crashing.) Redundancy checking, by contrast, only skips INDIVIDUAL
guarded arms (`if br.branch_guard = None then …`, typecheck.ml:3136) while still
checking the unguarded ones against the accumulated prefix.

**Conformance-corpus consequence:** an `accept/` program with a intentionally
non-exhaustive `match` is CORRECT: it is SUPPOSED to typecheck
(`accept/t14_nonexhaustive_match_still_typechecks` is the witness). Under
`march --check`, the mode `check_types.sh` uses (§3), the program **exits 0
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
(interpreted) or panic (compiled) on an uncovered value at RUNTIME; the
Warning is the typechecker's only static signal that this is possible, and it
is advisory, not enforced.

### 2.1 Primitive typing (δ-typing)

`+`, `-`, `*`, `/`, `negate`, `<`, `>`, `<=`, `>=`, `==`, `!=` are **not**
magic: they are ordinary variables bound in the base environment
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
overloading resolved by the parser: a truly critical fact (a program
`1 + "x"` fails because `+`'s two args must share one `a`, and `Int`/`String`
don't unify, **not** because `+` is "the Int operator"). `%` (Int-only
modulo), `+.`/`-.`/`*.`/`/.` (the Float-only dotted arithmetic operators) are
**not** constrained at all: `Mono` schemes over concrete `Int`/`Float`
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

**Two constraint kinds, two different discharge strategies: the critical
distinction of this task.** Despite both being written `∀a [Iface a]. …` in
the rules above, `Num` and `Ord`/`Eq`/`Show` are checked by TRULY
DIFFERENT code paths inside `discharge_constraints` (§2.1a below):

- **`CNum`** (`+`/`-`/`*`/`/`/`negate`) is checked by a HARDCODED match on the
  concrete type's `TCon` name: `"Int"` or `"Float"`, and no other name, at any time
  (`typecheck.ml:4952–4956`). There is no `env.impls` lookup, no user-facing
  `impl Num(T)` declaration form exists, and `Num` is not even a member of
  `env.interfaces` (confirmed live: `fn f(a,b) when Num(a) do a + b end`
  rejects with `` I don't know a constructor called `Num`. ``; `Num` cannot
  be named in a `when`-clause at all). `Num` is a CLOSED, compiler-builtin
  set of exactly two types.
- **`Ord`/`Eq`/`Show`/`Hash`** (`<`/`>`/`<=`/`>=`, `==`/`!=`, `show`, `hash`)
  are checked via `CInterface(iface_name, t)` against `env.impls`: an
  OPEN, extensible table seeded with built-ins (§2.1b) but extensible by any
  user `impl Ord(MyType) do ... end` block (`typecheck.ml:6915–7050`, the
  `DImpl` arm, which calls `register_impl_shape`-style insertion into
  `env.impls`; see §2.1b for the exact seed list).

**A THIRD constraint kind, `COrd`, exists in the type but is DEAD: not used
by any live scheme.** `constraint_`'s `COrd` variant (`typecheck.ml:130`) and
its constructor helper `_poly1_ord` (`typecheck.ml:1212–1214`, underscore-
prefixed to suppress the unused-value warning) are fully implemented:
`discharge_constraints` has real logic for `COrd` (`typecheck.ml:4952,
4959, 4966`, "String is Ord" / "COrd unresolved — leave polymorphic");
but `_poly1_ord` is never called anywhere in `builtin_bindings`: `<`/`>`/`<=`/
`>=` all use `poly1_iface "Ord"` → `CInterface("Ord", a)` (confirmed above),
NOT `COrd`. This is a real, if harmless, piece of dead code in the live
compiler: the comment at `typecheck.ml:1211` ("legacy COrd path") documents
the fact: `Ord` migrated from a `CNum`-style hardcoded-type-name check to
the general `CInterface`/`env.impls` mechanism at some point, and the old
path was left in place rather than deleted. No March program can
exercise a live `COrd` constraint at all.

### 2.1a Constraint discharge: `(T-Discharge)`

`discharge_constraints env span` (`typecheck.ml:4932–5049`) drains
`env.pending_constraints`, resetting it to `[]` when done (:5049), and is
called at every **declaration boundary**, NOT after every expression or
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
(below) is reported at the `fn`'s own span, not at the `+` call site's span:
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

- `1 + "x"` (direct): actually does **NOT** produce the Num message; `+`'s
  T-App argument unification (`a := Int` pinned by the first arg) conflicts
  with `"x" : String` in argument position #2 BEFORE `discharge_constraints`
  runs at all, giving the ordinary unify-mismatch headline `` expected `Int`
  but got `String`. `` (same shape as `reject/t01`). To reach the
  **CNum-specific** message, BOTH operands must already unify to one
  non-Num type with no earlier unify conflict, e.g. `let x = "a"; let y =
  "b"; x + y` (both `String`, agree with each other, only `+`'s OWN `Num`
  constraint is violated) gives, verbatim:
  ```
  String does not implement Num (only Int and Float do).
  ```
  reported at the enclosing `fn`'s span (per the discharge-at-declaration-
  boundary rule above), not at the `x + y` sub-expression's span.
- `Bool < Bool` (an `Ord` violation: `Bool` has no `Ord` impl, §2.1b) or a
  bare 0-arg ADT value compared with `<` (`type Hue = Rood | Bloo; Rood <
  Bloo`) both give the `CInterface` no-impl shape, verbatim (ADT case):
  ```
  `Hue` does not implement interface `Ord`.
  Add `impl Ord(Hue) do ... end` to provide an implementation.
  ```
- `show(f)` where `f : Int -> Int` (a function value: no `Show` impl for
  `TArrow`, §2.1b) gives, verbatim:
  ```
  `Int -> Int` does not implement interface `Show`.
  Add `impl Show(Int -> Int) do ... end` to provide an implementation.
  ```

### 2.1b Built-in instances, and the boolean primitives `&&`/`||`/`not`

**Which concrete types satisfy which built-in interface**: the seed table
`builtin_impls : (string * ty) list` (`typecheck.ml:1150–1167`), folded into
`env.impls` by `base_env` (`typecheck.ml:1857–1867`, every module starts with
this table pre-loaded):

| Interface | Built-in instances | cite |
|---|---|---|
| `Num` (via `CNum`, hardcoded; not in `env.impls`, no `impl Num` form exists) | **Int, Float only** | `typecheck.ml:4952–4956` |
| `Eq` | Int, Float, String, Bool, Unit, Atom | `typecheck.ml:1152–1153` |
| `Ord` | Int, Float, String | `typecheck.ml:1155` |
| `Show` | Int, Float, String, Bool, Unit, Atom | `typecheck.ml:1162–1163` |
| `Hash` | Int, Float, String, Bool | `typecheck.ml:1165–1166` |

Notably: `Eq` covers **strictly more** types than `Ord` (Bool/Unit/Atom are
equality-comparable but not ordered: there is no built-in `Bool < Bool`, no
`impl Ord(Bool)` shipped, confirmed live above), and `Ord` covers **strictly
fewer** than `Num` overlaps with (`Ord` ⊃ `{Int,Float}` ∩ `Num`, plus
`String`, which `Num` never includes; `String` is Ord but never Num, the
imbalance the live `1+"x"`-shaped probes above exploit). None of the four
built-in interfaces cover function types (`TArrow`), tuples, records, or
user-defined ADTs out of the box; those all require an explicit `impl …
do … end` (or, for a single-method interface over an anonymous record only,
the field-auto-satisfy path in (T-Discharge) above).

`builtin_interfaces` (`typecheck.ml:1127–1145`) is the companion table
declaring `Eq`/`Ord`/`Show`/`Hash`'s single-method SHAPE (`eq : a → a → Bool`,
`compare : a → a → Int`, `show : a → String`, `hash : a → Int`) so that a
user `impl Eq(MyType) do fn eq(a, b) do ... end end` block has something to
validate its method signature against (`typecheck.ml:6985–7030`, the `DImpl`
arm's per-method check); `Num` has NO entry in `builtin_interfaces` (it is
not a `CInterface`-based check at all, per §2.1's `Num`-vs-`Ord/Eq/Show`
split), which is exactly why `when Num(a)` cannot be written in a
`when`-clause (§2.1's live-verified finding).

**`&&`, `||`, `not` are NOT interface-constrained: plain monomorphic `Mono`
schemes**, the ordinary (unconstrained) case of T-Var/`instantiate` (§1):

```
(δT-And)  && : Bool → Bool → Bool              typecheck.ml:1245  (Mono, base_env)
(δT-Or)   || : Bool → Bool → Bool              typecheck.ml:1246  (Mono, base_env)
(δT-Not)  not : Bool → Bool                     typecheck.ml:1288  (Mono, base_env)
```

Since these are plain `Mono` bindings, a non-Bool operand is rejected by the
SAME ordinary T-App/unify infrastructure as any other monomorphic function call
(§2, T-App); no constraint is pushed for them at any point, and
`discharge_constraints` is never involved. There IS a distinctive wrinkle in
the ERROR TEXT, though: `report_mismatch`'s `common_hint` table
(`typecheck.ml:1936–1961`) special-cases the `(provided = Int, required =
Bool)` pairing with a dedicated remediation note (`typecheck.ml:1946–1949`):

```
"March does not coerce Int to Bool.
 Try an explicit comparison, e.g. `x != 0`."
```

so `1 && true` (verified live) reports the ordinary mismatch headline
`expected \`Bool\` but got \`Int\`.` WITH this hint appended, a general
common-mistake decoration on `report_mismatch`, not anything `&&`-specific
(the identical hint fires for `if 1 do … end` or any other Int-where-Bool-
expected site). `&&`/`||` are BINARY, so a non-Bool SECOND argument is
reported independently too (both arg positions are checked against `Bool`
via ordinary T-App per-argument checking, §2); verified live for `1 || 2`:
two separate diagnostics, one per argument.

**Cross-reference to the operational side:** `core-march.md` §4.4.1
documents `&&`/`||` as **strict, not short-circuiting** at the value level
(both operands are always evaluated); that is a RUNTIME/evaluation fact
about `δ-And`/`δ-Or`, orthogonal to this section: on the TYPE side `&&`/`||`
are simply fixed `Bool → Bool → Bool` functions like any other binary
builtin, and no part of their strict evaluation order affects how they
are typed (both operands are ⇐-checked against `Bool` via ordinary left-to-
right T-App argument checking, §2, exactly as strictness evaluates them
left-to-right at runtime; the two properties happen to agree in direction
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
scrutinee/argument type so an ambiguous bare constructor name (one shared by
two types) can be disambiguated by matching the expected type's head `TCon`,
typecheck.ml:2593–2603) computes both the type a pattern *expects* to match
AND the bindings (`(name, scheme) list`) it introduces into `Γ'` for the branch
body / rest of the match. Written `Γ ⊢ p : τ ⊣ Γ'` (`Γ'` = `Γ` extended with the
pattern's bindings).

**This is now the COMPLETE relation**: every arm of `infer_pattern`
(typecheck.ml:2566–2685) is accounted for below, one way or the other:
`PatWild`/`PatVar`/`PatLit`/`PatCon`/`PatTuple`/`PatAtom` each get a
live rule ((P-Wild)/(P-Var)/(P-Lit)/(P-Con)/(P-Tuple)/(P-Atom) added across
Tasks 1–3; (P-As) added 2026-07-24, once `parser.mly` gained an as-pattern
production; see the note after it below for the reachability history);
(P-Record) was added the same day, once `parser.mly` gained a record-pattern
production; see the note after (P-As) below. (P-Or) was added in the
record-matching-gaps plan's Task 5 (2026-07-24), the only one of these that
adds a truly NEW `Ast.pattern` constructor rather than wiring up one
that already existed; see the rule itself, just above the note after
(P-Record), for the binding restriction and its rationale.

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

(P-As)    Γ ⊢ p : τ ⊣ Γ'                            typecheck.ml:3554–3557
          ──────────────────────────────────────────────────────────────
          Γ ⊢ (p as x) : τ ⊣ Γ', x:τ
          -- binds x to the SAME type τ as the inner pattern p, IN ADDITION
          --   to whatever bindings p itself introduces (Γ') — the
          --   pattern-typing analog of (P-Var)'s binding, layered on top of
          --   an arbitrary sub-pattern rather than replacing it. x's type is
          --   also recorded in env.type_map at x's span (same convention as
          --   (P-Var)), so lower.ml/LSP hover can resolve it.
          -- no arity or shape check of its own — τ is whatever `p`
          --   independently infers to; (p as x) never constrains p beyond
          --   what p's own rule already does.
          -- cf. operational match(PatAs(p, x), v) = match(p, v) ∪ {x ↦ v},
          --   core-march.md:864 (eval.ml:826–829, unchanged by this rule's
          --   addition — the interpreter already implemented this; only the
          --   grammar production was missing)

(P-Record, expected known)
           expand(expected) = TRecord [(f₁,τ₁)…(fₙ,τₙ)]   (n ≥ k, the         typecheck.ml:3557–3596
             SCRUTINEE's full field set)
           ∀(fⱼ,pⱼ) ∈ pattern: Γ ⊢ pⱼ : τⱼ' ⊣ Γⱼ,  τⱼ' ~ τⱼ   (else "no field fⱼ")
           ──────────────────────────────────────────────────────────────
           Γ ⊢ PatRecord [(f₁,p₁)…(fₖ,pₖ)] : TRecord [(f₁,τ₁)…(fₙ,τₙ)] ⊣ Γ, Γ₁, …, Γₖ
           -- OPEN field list: k ≤ n — the pattern names some prefix (in the
           --   general case, some SUBSET) of the scrutinee's fields, and the
           --   pattern's type is the scrutinee's FULL (expected) record type,
           --   not a type synthesized from only the mentioned fields. Fields
           --   the pattern doesn't mention are simply not bound (no Γᵢ
           --   contribution), mirroring the operational match(PatRecord)
           --   rule (core-march.md), which already looked fields up by name
           --   in the value's full field list rather than requiring an exact
           --   match.
           -- `expected` is threaded in from the same places (P-Con)'s
           --   `arg_ty` is: (P-Tuple)'s per-element expected type (itself
           --   only available when ITS OWN `expected` resolves to a
           --   `TTuple`), a `match`'s scrutinee type, or a constructor
           --   argument's declared type. `expand` is `expand_record`
           --   (typecheck.ml:3156): it accepts either a structural
           --   `TRecord` directly or a nominal `TCon` naming one.
           -- naming a field fⱼ absent from the expected record's field list
           --   is a hard error (`unknown_record_field`), reported per-field
           --   at that field name's span — not a unification failure, and
           --   not silently ignored.
           -- a bare punned field `f` is parsed as `(f, PatVar f)`
           --   (parser.mly's `record_field_pat`), so it flows through this
           --   rule identically to a spelled-out `f: f`.

(P-Record, expected unknown)
           ∀i: Γ ⊢ pᵢ : τᵢ ⊣ Γᵢ   (i = 1..k, componentwise recursion,          typecheck.ml:3597–3607
             one field per (name, sub-pattern) pair)
           ──────────────────────────────────────────────────────────────
           Γ ⊢ PatRecord [(f₁,p₁)…(fₖ,pₖ)] : TRecord (sort [(f₁,τ₁)…(fₖ,τₖ)]) ⊣ Γ, Γ₁, …, Γₖ
           -- fallback when `expected` doesn't resolve to a record at all
           --   (e.g. an unannotated `let` pattern, or a bare record pattern
           --   used directly as a function parameter — that grammar position
           --   has no annotation slot, so the parameter's type has no source
           --   but the pattern itself): the ORIGINAL rule, unchanged.  The
           --   pattern's type is a FRESH, CLOSED `TRecord` built purely from
           --   the fields the pattern mentions, sorted by name (same
           --   sort-by-name convention as T-Record's literal typing, §2).
           -- because March records require EXACT field-set equality to unify
           --   (no width subtyping — typecheck.ml:2789), this synthesized
           --   `TRecord` only unifies against a scrutinee whose own record
           --   type has PRECISELY these k fields, no more, no fewer — so a
           --   partial pattern reaching this fallback (rather than the
           --   expected-known rule above) is still closed, the same
           --   restriction (P-Tuple) has for arity.

(P-Or)    ∀i: Γ ⊢ pᵢ : τᵢ ⊣ Γᵢ  (i = 1..n, n ≥ 1)                   typecheck.ml:3609–3642
          unify(τ₁, τᵢ)  for each i > 1
          Γ₁, …, Γₙ each bind ZERO names, else reject
          ──────────────────────────────────────────────────────────────
          Γ ⊢ PatOr [p₁…pₙ] : τ₁ ⊣ Γ
          -- every alternative is inferred independently (threading the same
          --   `~expected`, if any, into each) and unified against the FIRST
          --   alternative's type, so `1 | 2 | 3` and `Red | Green` both
          --   require every alternative to agree on one type — a mismatched
          --   alternative (e.g. `1 | "x"`) is an ordinary unify error, not a
          --   dedicated diagnostic.
          -- the bindings check is NOT a type-level constraint (nothing to
          --   unify) — it is a hard reject of ANY alternative that binds a
          --   variable at all: "Or-pattern alternatives cannot bind
          --   variables (`x`)." (code `or_pattern_binding`). The reason is
          --   operational, not type-theoretic: the arm body is shared across
          --   every alternative via a single 0-arg join point in lowering
          --   (`lower_match.ml`'s `expand_or_rows`/`hoist_fallback_jp`),
          --   which has nowhere to carry a per-alternative binding into that
          --   shared call — `A(x) | B(x) -> x` would need a DIFFERENT `x`
          --   bound depending on which alternative matched, and the compiler
          --   has no mechanism (yet — an n-ary join point would suffice,
          --   filed in `specs/todos/`) to pass one in. Consequently the
          --   overall result binding list is always `Γ` unchanged (`[]`),
          --   never `Γ, x:τ` — this is the one pattern-typing rule that can
          --   never introduce a name, unlike every other rule above.
          -- cf. operational match(PatOr, v), core-march.md — tries each
          --   alternative in order, first match wins, exactly mirroring
          --   `is_useful`/`norm_pat_rows`'s (§4.1) treatment of an or-pattern
          --   as several exhaustiveness/redundancy ROWS rather than one.
```

**`(P-As)` and `(P-Record)` became live rules 2026-07-24** (see both rules
above, between (P-Atom) and this note). Through 2026-07-23 `PatAs` (`p as
x`) and `PatRecord` (`{ f, … }`) were both unreachable from surface syntax,
even though `infer_pattern` already had a working arm for each
(typecheck.ml:3554–3557 for `PatAs`, typecheck.ml:3544–3553 for
`PatRecord`, unchanged by this update: only `parser.mly` was missing a
production for either). `pattern` gained an as-pattern layer
(`pattern_no_as AS lower_name`, `parser.mly:1441` era) and `simple_pattern`
gained a record-pattern production (`LBRACE record_field_pat,* RBRACE`);
see `specs/lang/grammar.md` §6.3 for the grammar-side detail of both. `Some(x) as
whole` and `{ x, y: p } -> …` now parse and typecheck via the `(P-As)` and
`(P-Record)` rules above, respectively. Before this change, `core-march.md`'s
golden corpus used guarded branches reading their own pattern's bindings
(`g27_guard_binding.march`) as "the reachable substitute for the
unparseable as-pattern" (`core-march.md:1247`), and used field-access
guards as the substitute for the unparseable record pattern; neither
historical workaround is the only option anymore, though both remain valid
March and `core-march.md` has not yet been revisited to update that framing
(out of scope for this pass).

**`(P-Record)` gained an open field list 2026-07-24**, the same day, as a
follow-on to the note above: the original rule (now "expected unknown"
above) synthesized a CLOSED `TRecord` from only the fields the pattern
mentioned, and since March records require exact field-set equality to
unify, a pattern naming a strict subset of a record's fields (`{ x }`
against `{ x : Int, y : Int }`) was rejected. `infer_pattern` already threads
an optional `expected` type through recursive calls: used, before this
change, only to disambiguate an ambiguous bare constructor name in (P-Con).
The fix ("expected known" above) drives `PatRecord`'s sub-patterns from that
expected type instead of synthesizing one, when it resolves (through
`expand_record`) to a record; naming an absent field is now a dedicated
`unknown_record_field` error rather than a unification mismatch. (P-Tuple)
was extended in the same change to thread a per-element expected type to its
sub-patterns (from its OWN `expected`, when that resolves to a `TTuple`),
needed for a record pattern nested inside a tuple pattern with a
known-in-advance element type, e.g. a tuple built from two independently
type-annotated bindings (a `let`'s type ascription, or two annotated function
parameters matched together in one `match`) where one element is destructured
by a partial record pattern.

Two positions still hit the "expected unknown" fallback, and so remain
closed to exactly the fields the pattern names, because neither has an
independent expected type to give the pattern: a `let` pattern (the binding
IS what establishes the type, so no typed context precedes it to drive from) and a
bare pattern used directly as a function parameter (that grammar position,
`fn_param: p = pattern { FPPat p }`, parser.mly, has no annotation slot, so
the desugared match's scrutinee, `EVar __argN`, has only a fresh
unconstrained type variable into (P-Record) as `expected`, which
`expand_record` cannot resolve to anything). The latter is why the
motivating `fn area({ w, h })`-shaped case only reopens when the record
parameter is instead given a name and an annotation, and destructured by an
explicit `match` in the body: `fn f(r : {w:Int, h:Int}) do match r do {w:w} -> w end end`.

`instantiate_ctor` (typecheck.ml:2387) is called from BOTH T-Con (§2, expression
side) and P-Con (pattern side): the same fresh-vars-per-type-param instantiation
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
other side: what the typechecker validates when a program itself **declares**
a user-defined `interface Iface(a) do ... end` and writes an
`impl Iface(T) do ... end` for it. Cited to `typecheck.ml`'s `DInterface` and
`DImpl` arms of `check_decl`, re-grepped live against this worktree.

**`(T-Interface)`: interface declaration is pure registration.**

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
interface-qualified name (`Speak.speak`); the qualified binding is what makes
`Iface.method(x)` call syntax resolve (the `EField`-as-module-path lookup
path). Occurrences of either name later push a fresh `CInterface(iface, τ)`
obligation onto `env.pending_constraints` at the ordinary T-Var/`instantiate`
site (§1); a `DInterface`'s own method schemes are constructed exactly like
`show`/`eq`/`compare`/`hash`'s built-in schemes (§2.1's `mk_iface_method_scheme`
shape), just built per-declaration instead of once at `base_env` time.

**Almost no case is rejectable at the interface declaration itself.** There is
no check that a method's declared type actually mentions the interface's own
type parameter `a` (an interface method signature that never uses `a` still
typechecks, with the `CInterface` constraint simply attached to a fresh,
otherwise-unconstrained variable) and no rejection of a duplicate interface
name in the same module (a second `interface Speak(a) do ... end` just calls
`StrMap.add` again, silently replacing the first entry in `env.interfaces`,
consistent with `env.impls`'s "insert, never check" registration shape,
confirmed for impls below). `DInterface` is registration, not validation.

**Two pre-pass duplicates exist for cross-module declaration ordering.**
`prebind_interface_decl` (typecheck.ml:5050–5087) reconstructs the identical
scheme-building logic as a pass-1 walk (called from `check_module_core`/
`check_module_with_env`'s first pass, typecheck.ml:8072, 8272, and from
`check_decl`'s own `DMod`/top-level pass-1 prebind, :8146–8147, 8337–8338) so
that a **sibling module checked before the interface's own defining module**
can still see `Iface`, `Iface.method`, and the bare `method` name; the doc
comment at typecheck.ml:5042–5049 ties this directly to a real, previously-
fixed LSP bug (per-file analysis hiding sibling-module interfaces). It is not
shared code with the full `DInterface` arm (an intentional duplication, not a
refactor gap) for the same reason `register_impl_shape` (below) duplicates
`DImpl`'s registration step: pass-1 must run with a still-incomplete
environment, so it cannot simply call the pass-2 function.

**`(T-Impl)`: the ordered checks of an impl declaration.** `Ast.DImpl`'s arm
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
interface existence, missing-method, extra-method, and signature-match,
plus the final `discharge_constraints` call every declaration arm makes
(§2.1a). The `when`-clause and superclass checks share the identical
discharge shape (both search `env.impls` via the `(T-ImplMatch)` judgment,
named and detailed below); they are documented together immediately after
item 1.

1. **Instantiate the impl head, then register, WITH a coherence
   lookup-before-insert as of 2026-07-17 (STALE → CORRECTED, 2026-07-22).**
   This item originally described `env.impls : ty list StrMap.t` registration
   (`typecheck.ml:7081`–`7084`, still `inst_ty :: existing_list`, a list keyed
   by interface name and searched via `impl_matches_ty`) as unconditional:
   "no dedup, no uniqueness check," with overlapping impls of the same
   interface for the same type NOT rejected at typecheck, deferring to
   `core-march.md` §4.4.3's then-open interp-vs-compiled runtime-selection
   divergence. **That is no longer accurate.** `register_impl_shape`
   (`lib/typecheck/typecheck.ml:6164`–`6323`, called from the Pass-1 fold loops
   that walk every `DImpl`, e.g. `:9882`, `:9936`, `:10173`) now runs a
   coherence check BEFORE the registration step above: it searches the
   existing-impls list for a DIFFERENT-span entry (same-span = a harmless
   Pass-1 re-registration of the same `DImpl`, not a duplicate) with a head that
   **overlaps** the new one via `types_overlap` (unifiability-based: this
   subsumes exact duplicates AND generic-vs-specific overlap, e.g. `List(a)`
   vs `List(Int)`), and, unless the two heads resolve to two distinct
   DECLARING MODULES of a same-short-name type with disjoint constructor sets
   (the FQN dispatch-identity relaxation, `:6279`–`6290`, sound because the
   native/interp backends now route same-short-name-but-different-module
   types through globally-unique runtime tags and a qualified dispatch table),
   REJECTS the program:
   ```
   Overlapping implementation: `impl Speak(Dog)` conflicts with the
   implementation at <file>:8:7 — their heads overlap.
   A type may implement an interface at most once (coherence). If you meant
   a different behavior, wrap the type in a newtype and implement the
   interface on that.
   ```
   confirmed live this task, `--check` exit 1, for the exact repro
   `core-march.md` §4.4.3 originally used to demonstrate the divergence; that
   repro no longer typechecks on either backend, so the runtime split it
   demonstrated cannot arise. See `core-march.md` §4.4.3 (rewritten
   2026-07-22) for the full current account, live-reproduced evidence for the
   generic-vs-specific and derive-vs-manual overlap cases too, and the
   `specs/todos/` closeout entries ("impl-coherence" Stage 1+2,
   2026-07-17). **One scoped exception, unchanged from before and NOT a
   residual divergence:** a user impl overlapping a BUILT-IN seeded impl
   (`env.impls` seeds built-ins with `Ast.dummy_span`, `:6302`–`6306`) is
   still skipped by the check: `impl Eq(Int)` alongside the built-in `Eq`
   still typechecks, intentionally deferred as its own follow-on (DECIDE-1)
   since several interface-machinery test fixtures rely on it.

**`(T-ImplMatch)`: the impl-head-matching judgment (typecheck.ml:4964–4984).**
Both the `when`-clause check and the superclass check above (and, at the use
site, `CInterface` constraint discharge itself, §2.1a) all reduce to the same
question: *"is there an impl in `env.impls` with a head type that covers this
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
wildcard-tolerant shape match**: it never returns a substitution or binds a
type variable, only a boolean "does this impl head cover that target." This
single judgment is the crux of two, otherwise-unrelated-looking facts about
March's impl system:

- **It is why generic/parameterized impls work at all.** An impl head with
  its own free type variable, `impl Speak(a)` (a blanket impl over every
  type, `accept/t19_eq_ord_constraint_discharged`-adjacent shape) or
  `impl Describe(Box(a))` (a generic impl over a parameterized type,
  `accept/t24_interface_impl_generic_head`, witnessed at both `Box(Int)` and
  `Box(String)`), matches because the `TVar _, _ -> true` case (typecheck.ml
  :4970) treats the impl's own unresolved type parameter as a wildcard, not
  as "must unify with." There is no separate "instantiate the impl head at
  the target type" step; matching and instantiation are conflated into one
  permissive boolean check.
- **STALE (2026-07-06) → CORRECTED (2026-07-22): "why coherence does not
  exist" is no longer true: coherence is now enforced UPSTREAM of this
  judgment, at registration time, not by `impl_matches_ty` itself.**
  `impl_matches_ty` still answers only "does impl I cover target T,"
  never "which of several covering impls is most specific"; that part of
  the description is accurate and unchanged: `(T-ImplMatch)` itself has no
  specificity ordering, and `env.impls`'s discharge-time search (`List.exists`,
  stopping at the first structural match) still has none either. **But** the
  scenario this bullet used to illustrate, "a fully generic `impl Iface(a)`
  and a fully concrete `impl Iface(Dog)` can both match a `Dog` target
  simultaneously, decided by registration order per backend", can no longer
  arise for a program that passes `--check`: `register_impl_shape` (item 1
  above, corrected 2026-07-22) now rejects a second impl with a head that OVERLAPS
  an already-registered one via `types_overlap` (unifiability-based) BEFORE
  either impl reaches `env.impls`'s searchable list; confirmed live, `impl
  Speak(Box(a))` followed by `impl Speak(Box(Int))` fails `--check` with an
  `Overlapping implementation` error citing the generic impl as the
  conflict. So by the time a well-typed program's `env.impls` is searched at
  a discharge site, at most one registered impl can cover any given concrete
  target (mod the built-in-overlap and FQN-cross-module carve-outs item 1
  names); `impl_matches_ty`'s lack of specificity resolution is therefore no
  longer separately critical for "which impl runs": coherence upstream
  already guarantees there is never more than one candidate to find.
  `core-march.md` §4.4.3 (rewritten 2026-07-22) has the full current account
  and live evidence; this bullet is kept, corrected, because the matching
  judgment itself is still worth naming and its lack of specificity ordering
  is still a true fact about `(T-ImplMatch)`; it just no longer implies a
  live cross-backend divergence the way it used to.
- **Linearity qualifiers are ignored for matching purposes**
  (`TLin (_, t1), TLin (_, t2) -> impl_matches_ty t1 t2`, typecheck.ml:4982):
  an impl declared for `linear T` matches a search for plain `T` and vice
  versa: the linearity annotation itself is stripped away before the
  structural comparison, not treated as part of the type's identity.

**Superclass/`requires` bounds ARE enforced: this is a mandatory rejection,
not a conditional gap.** `interface Greet(a) requires Speak(a) do ... end`
records `Speak` in `Greet`'s `iface_superclasses` (parsed at
`lib/parser/parser.mly:769-786`); when `impl Greet(T)` is declared, the
superclass-discharge step (typecheck.ml:7118–7143) instantiates each
required superclass's type arguments against the SAME impl type
(`sc_tvars = [(interface.iface_param, inst_ty)]`, :7120) and, for each
resulting concrete type, requires `env.impls` to already contain a matching
impl for that superclass via `(T-ImplMatch)`, the identical search shape as
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
superclasses "not yet supported"**: `sc_inst_tys` is matched against a
single-element list pattern (`| [sc_inst_ty] -> ... | _ -> ()`, :7124,
:7141), so a hypothetical superclass with more than one type argument would
silently skip the check entirely; this mirrors the identical single-argument
limitation described just below for `when`-clauses, and is not separately
tested since March's interface grammar only supports one type parameter per
interface in the first place (`parser.mly:769-786`), so a multi-argument
superclass constraint cannot arise from any interface declaration the parser
accepts today.

**The `when`-clause check (typecheck.ml:7086–7103) is the identical
mechanism, applied to an impl's own constraints rather than its interface's
superclasses.** `impl Iface(T) when Other(T) do ... end` requires `Other(T)`
already implemented, using the same `(T-ImplMatch)` search against
`env.impls`; if the constrained type is a bare, still-unresolved `TVar`
(a generic `when` clause, e.g. `impl Wrap(a) when Speak(a)`), the check is
skipped (`TVar _ -> ()` at :7091), deferring to the ordinary use-site
`CInterface` discharge instead (§2.1a), since there is no concrete type to
search for yet. Unsatisfied `when` message (already pinned in the existing
corpus, `reject/t10`-shaped): `` Constraint `C(T)` in `when` clause is not
satisfied. No `impl C(T)` is in scope. `` Only single-argument constraints
are handled here too: the `_ -> ()` fallthrough at :7102 is likely
unreachable in practice rather than a live gap, since the grammar for
`constraint_expr` (`parser.mly:823-826`) always produces a one-element
type-argument list.

2. **Interface existence** (typecheck.ml:7105–7117): `idef.impl_iface` must be
   a key of `env.interfaces`, UNLESS its name starts with `"Json"`: `derive`'s
   `JsonTo`/`JsonFrom` pseudo-interfaces are intentionally never registered in
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
   impl provides must match some `iface_m.md_name`; an impl cannot add
   methods the interface never declared. Live message
   (`reject/t19_impl_extra_method`):
   ```
   Interface `Speak` does not declare a method `bark`.
   ```
   This check applies even to the four built-in dispatched interfaces: a
   hand-written `impl Eq(T) do ... end` with an extra `neq` method is rejected
   here too, since `Eq`'s `builtin_interfaces` shape only declares `eq`
   (cross-referenced by the dispatch-operational task: this static rejection
   is what makes a defensive dispatch-key-collision guard on the `eval.ml`
   side unreachable for the four built-ins today).
5. **Signature match: `impl_matches_ty` for the impl HEAD, ordinary `unify`
   for each METHOD** (typecheck.ml:7166–7189): for each provided method, the
   interface's declared signature is instantiated by substituting the
   interface's type parameter with the impl's own concrete head type
   (`expected_ty`, :7168–7172), then the method body's actual type, from
   `check_fn` + `instantiate`, or from `check_expr` directly for an
   already-zero-param default body (see below), is `unify`'d against it. Live
   message (`reject/t20_impl_signature_mismatch`):
   ```
   `speak` in `impl Speak` must match the interface signature
   ```
   (the full diagnostic also includes the ordinary `expected \`String\` but got
   \`Int\`.` unify-mismatch headline above this note, per `report_mismatch`'s
   usual shape, §2.1a).

**Default methods (`md_default`): an impl that omits one is not an error.**
An interface method may carry a default body:
`interface Foo(a) do fn bar : a -> Int do fn self -> 42 end end`. If an impl
of `Foo` omits `bar`, step 3 above is a no-op for it (`md_default <> None`), so
no "missing method" diagnostic fires. Mechanically, this is NOT a fallback
inside `check_decl`'s own missing-method check: desugar's `inject_defaults`
(`lib/desugar/desugar.ml:897–931`) runs BEFORE typecheck sees the `DImpl` at all
and **splices a synthesized method into `idef.impl_methods`** for every
interface method the impl omits that has a default: it wraps the default
expression in a single zero-parameter `fn_clauses` clause
(`fc_params = []`, desugar.ml:918–923) and appends it to the impl's method
list. By the time `check_decl`'s `DImpl` arm runs, the impl already "has" the
method: the missing-method check simply never sees it as absent, and the
signature-match step (item 5 above) type-checks the injected zero-param clause
directly via `check_expr` against `expected_ty` (typecheck.ml:7176–7182), the
same branch a hand-provided method would only take if it, too, happened to be
a zero-param clause.

One consequence worth calling out because it is easy to get wrong writing a
default body: **the default expression's type is the method's FULL ARROW
TYPE** (`a -> Int` in the example above), not the return type after applying
`self`, because the zero-param clause's body IS the default expression
verbatim (desugar.ml:921, `fc_body = desugar_expr default_expr`), so
`expected_ty` (the whole instantiated method type) is checked directly against
it. A default body that is just a bare value (`do 42 end`) fails to typecheck
with an arrow-vs-concrete-type mismatch; the default body must itself be a
value of the arrow type, ordinarily a lambda over the interface's own
parameter (`fn self -> 42`). Confirmed live: `accept/t25_interface_default_method`
declares `fn greeting : a -> Int do fn self -> 42 end`, an impl that provides
only `name` (omitting `greeting`), and `println(int_to_string(greeting(Cat("Tom"))))`
both typechecks (`--check` exit 0) and RUNS to print `42`: the default,
not a value from the impl (which never defined `greeting` at all).

**Corpus:**

- `accept/t23_interface_impl_basic`: a minimal `interface Speak(a) do fn
  speak : a -> String end` + `impl Speak(Dog)` providing exactly `speak`;
  typechecks and (run) prints `"Rex"`.
- `accept/t24_interface_impl_generic_head`: `impl Describe(Box(a))`, a
  parameterized/generic impl head, used at both `Box(Int)` and `Box(String)`
  (witnesses `impl_matches_ty`'s wildcard treatment of the impl's own free
  type variable, named and detailed above as `(T-ImplMatch)`).
- `accept/t25_interface_default_method`: the default-method witness above.
- `accept/t26_impl_superclass_satisfied`: `interface Greet(a) requires
  Speak(a)`, with `impl Speak(Dog)` declared before `impl Greet(Dog)`;
  typechecks and (run) prints `"Hello, Rex"`: the superclass bound
  SATISFIED.
- `reject/t18_impl_missing_method`: a required, non-default method omitted.
- `reject/t19_impl_extra_method`: an impl method the interface never
  declared.
- `reject/t20_impl_signature_mismatch`: a provided method with an inferred
  body type that disagrees with the interface's declared signature.
- `reject/t21_impl_unknown_interface`: `impl` of an interface name that was
  never declared.
- `reject/t22_impl_superclass_unsatisfied`: the same `Greet requires Speak`
  interface shape, but `impl Greet(Dog)` with no `impl Speak(Dog)` anywhere
  in scope: the superclass bound UNSATISFIED (mandatory rejection, not a
  conditional gap).

**Added 2026-07-17/2026-07-22 (not part of the original Task-3 corpus
above, but directly relevant to item 1's correction):** `reject/
t79_impl_coherence_duplicate` (two `impl Speak(Dog)` blocks: exact-head
overlap), `reject/t80_impl_parametric_overlap` (`impl Speak(Box(a))` then
`impl Speak(Box(Int))`: generic-vs-specific overlap via `types_overlap`),
`accept/t83_impl_distinct_types`/`t84_impl_distinct_ifaces` (impls that do
NOT overlap: different concrete types, or different interfaces, still
coexist freely), and `reject/t82_impl_coherence_shared_ctor_double_collision`
/ `accept/t88_impl_distinct_modules`/`t89_impl_general_iface_collision` (the
FQN dispatch-identity same-short-name-different-module exception and its own
residual double-collision stopgap; see `specs/todos/`'s "FQN dispatch
identity" entries for the full staged story, out of this subsection's scope
to restate).

### 2.4 `derive` and `satisfy`: two ways to get a `DImpl` without writing one

§2.3 documented `(T-Interface)`/`(T-Impl)` as they apply to a hand-written
`interface`/`impl` pair. This subsection covers March's two *generators* of
`DImpl` blocks (`derive Iface1, Iface2 for Type` and
`satisfy Iface1, Iface2 for Type1, Type2`), both expanded entirely at
**DESUGAR time**, strictly before typecheck runs at all. `typecheck.ml`'s own
`check_decl` confirms this in code structure: its `DDeriving`/`DSatisfy` arms
(`typecheck.ml:7393–7395`, `:7519–7521`) are bare no-ops: by the time
`check_decl` walks the declaration list, `desugar_module` has already
replaced every `DDeriving`/`DSatisfy` node with the `DImpl` block(s) it
expands to (or with no output at all, per the no-op gap documented below). Both
generators live in `lib/desugar/desugar.ml`, re-grepped live in this
worktree.

**`derive`: a CLOSED set of five hardcoded interfaces, dispatched by a flat
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
**closed, hardcoded set of exactly five derivable interfaces**, not a
general mechanism a user can extend by declaring their own `interface` and
hoping `derive` notices it. An interface name outside the five is rejected,
live-captured (`reject/t23_derive_unknown_interface`):

```
Unknown derive target `Frobnicate` for type `Color`.
Supported interfaces: Eq, Show, Hash, Ord, Json
```

- **`Eq`/`Show`/`Hash`/`Ord`** each produce exactly ONE `DImpl` via the local
  `impl_one` helper (`desugar.ml:1116–1126`), targeting the REAL interface
  name (`impl_iface = mk_name iface`): these desugar to `DImpl` blocks that
  `(T-Impl)` (§2.3) cannot distinguish from a hand-written `impl Eq(Color) do
  … end`. That indistinguishability is exactly why a `derive`-generated impl
  can collide with a hand-written one for the same `(interface, type)` pair;
  cross-referenced, not repeated, at `core-march.md` §4.4.3's derive-vs-manual
  overlap probe. Each generator walks the type's own definition
  by structure: a `TDVariant` produces a match over pairs of constructors
  (`Eq`'s body, `desugar.ml:1134–…`, matching each constructor against
  itself and folding `&&` over payload-wise `==`; a mismatched pair of
  constructors falls to a wildcard `false`), a `TDRecord` compares/derives
  field-by-field, and a `TDAlias` DELEGATES directly to the aliased type's
  own operators (e.g. `desugar.ml:1194–1196` for `Eq`) rather than
  regenerating logic for the alias itself.
- **`Json` is special-cased: it produces TWO `DImpl` blocks under PSEUDO-
  interface names `"JsonTo"`/`"JsonFrom"`**, not the real interface name
  (`desugar.ml:1623–1639`, `mk_json_impl` building `impl_iface = mk_name
  "JsonTo"` / `"JsonFrom"`). These two names are intentionally never entries
  in `env.interfaces`: `(T-Impl)`'s interface-existence check (§2.3, item 2)
  has an explicit escape hatch for exactly this: `` idef.impl_iface.txt ``
  starting with the 4-character prefix `"Json"` skips the "unknown
  interface" rejection AND the normal method-signature validation entirely
  (`typecheck.ml:7105–7117`'s `is_json_derive` guard, mirrored again at
  `typecheck.ml:7196–7210` for the "don't rebind the polymorphic
  `to_json`/`from_json` builtin" step); method bodies are still
  type-checked standalone via `check_fn`/`check_expr` for local correctness
  (`typecheck.ml:7202–7204`), but never unified against a declared interface
  signature the way an ordinary impl's methods are (§2.3 item 5). `Json`
  derive is thus architecturally a special case bolted onto the general impl
  infrastructure, worth naming explicitly as an exception to `(T-Impl)`, not
  folded silently into its general rule.

**LOGGED GAP: `derive X for UnknownType` silently no-ops: exit 0, no
diagnostic of any kind.** `expand_derive`'s `None` branch
(`desugar.ml:1659`, quoted above) is a bare `[]`: if `type_name` is not a
key of `type_defs` (the module's own collected type definitions,
`desugar.ml:2110`), the ENTIRE `derive` declaration silently vanishes: no
`DImpl` is generated at all, and, critically, **no error is raised at any point**,
unlike every other "the target doesn't exist" case in this document (`impl`
of an undeclared interface IS rejected, §2.3 item 2; `satisfy` of an
undeclared interface IS rejected, below). Re-checked live for this task:

```
mod M do
  derive Eq for Ghost           -- `Ghost` is never defined anywhere

  fn main() do
    println("no error, no Ghost type defined")
  end
end
```

`--check` on this program exits **0**: no diagnostic, no warning. Running it
also exits **0** and prints `no error, no Ghost type defined`; the program
behaves exactly as if the `derive Eq for Ghost` line were not present at all.
This is logged as an open gap in `specs/todos/` ("Compiler: Type System",
finding 17 in this document's §4.1), with this exact repro and the
`desugar.ml:1659` citation; fixing it (making an unknown derive TARGET TYPE
an error, symmetric with the unknown derive TARGET INTERFACE case already
handled above) is a compiler change, out of scope for this documentation
slice.

**`satisfy`: wires EXISTING top-level functions to an interface by NAME
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
`desugar.ml:2111`), so `satisfy` can target ANY user-declared interface, not
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
underlying problem: once as `expand_satisfy`'s own "no function found"
error, and again from `(T-Impl)`'s missing-method check (§2.3, item 3) if a
partial `DImpl` had been emitted and passed to `check_decl` anyway.

**Corpus:**

- `accept/t29_derive_eq_show`: `derive Eq, Show for Color` on a 3-constructor
  variant type, used via `show(Red)`/`Red == Red`/`Red == Blue`; typechecks
  and (run) prints `Red` / `true` / `false`.
- `accept/t30_satisfy_wiring`: `satisfy Named for Person` wiring an existing
  top-level `fn name` to `interface Named(a)`'s one method; typechecks and
  (run) prints `Ada`.
- `reject/t23_derive_unknown_interface`: `derive Frobnicate for Color`, an
  interface name outside the closed five-name set.
- `reject/t24_satisfy_missing_function`: `satisfy Named for Person` where no
  top-level `fn name` exists anywhere in the module.

**Note (dead AST surface): associated types are not a real feature.**
`interface_def.iface_assoc_types : assoc_type_decl list` and
`impl_def.impl_assoc_types : (name * ty) list` (`ast.ml:302`, `:324`) are
populated with `[]` UNCONDITIONALLY by the parser (`parser.mly:779`, `:809`);
there is no grammar production anywhere that fills either field with
anything else (no `type Output = …` associated-type syntax exists inside an
`interface`/`impl` block), and neither `typecheck.ml` nor `eval.ml` at any point
reads either field (confirmed by grep: the only other occurrence is the same
`[]` literal at `typecheck.ml:1120`, in `mk_builtin_iface`). **Associated
types are AST scaffolding for a future extension, not a currently-working
feature**, worth this one-line note so a reader who spots the fields in
`ast.ml` doesn't assume otherwise.

### 2.5 Module visibility, the opaque-type imbalance, and the no-per-module-type-namespace design point

**Widening slice 2, Task 3.** `core-march.md` §4.7 documented `DMod`'s
OPERATIONAL side: how a module's declared names get re-exported as
`"Name.member"` at eval time, gated on `own_names` (everything declared,
public or private). This subsection is the TYPING counterpart: what
`typecheck.ml`'s `DMod` arm (`Ast.DMod (name, _vis, decls, _sp)`,
`typecheck.ml:6823`) and its cross-file sibling `load_module_into_env`
(`typecheck.ml:657–692`) actually gate on, and (the critical content of
this subsection) the precise, INTENTIONAL imbalance between how a private
FUNCTION/VALUE is hidden and how a private TYPE stays nominally visible.
Every claim below was re-run live against this worktree's
`_build/default/bin/main.exe --check` (and, where noted, run to a printed
value), not inferred from reading the source by itself.

**`pub_set`: visibility is a `DMod`-local, typecheck-only export filter.**
The same-file (or same-compilation-unit, since `use`/`MARCH_LIB_PATH`-resolved
siblings are spliced in as real `DMod`s before typecheck runs at all) case:

```
pub_set = { n | DFn(n, Public) ∈ decls } ∪ { n | DLet(Public, n, …) ∈ decls }
          ∪ { n | DType(Public, n, …) ∈ decls } ∪ …                          typecheck.ml:6841–6862
is_pub_key k  = ∃ n ∈ pub_set. k = n ∨ k starts-with (n ^ ".")               typecheck.ml:6895–6901
new_names     = { (Name^"."^k, σ) | (k, σ) ∈ inner_env.vars, is_pub_key k }  typecheck.ml:6904–6908
new_types     = { (k, arity) | (k, arity) ∈ inner_env.types, k ∈ pub_set }   typecheck.ml:6915–6917
new_ctors     = filter each ci: ci.ci_type ∈ pub_set ∧ ci.ci_vis = Public    typecheck.ml:6918–6927
```

A name never in `pub_set` (a `pfn`, a private `let`, a `ptype`) simply never
gets a `"Name.member"` key written into the outer scope's `vars`/`ctors`,
the SAME absence-not-rejection shape `core-march.md` §4.7 describes for
`own_names`, just filtered one predicate narrower (`pub_set` ⊆ `own_names`,
strictly narrower for any module with at least one private member). This is
why a same-file private access surfaces as "Unknown module `A`" rather than a
dedicated "is private" diagnostic when `A` has no public surface at all: the
qualified lookup falls through to the registry fallback below, which reports
based on what a DIFFERENT, independently-loaded copy of "module A" contains
(see the cross-file case next).

**The cross-file/registry gate: `load_module_into_env`, Task 1's fix.**
A qualified reference that misses the primary `env.vars`/`env.types`/
`env.ctors` lookup (e.g. any qualified name from a module that was never
spliced in as a sibling `DMod` in THIS compilation, which in practice is any
stdlib module reached only via the registry fallback rather than `use`) falls
to `resolve_qualified_var`/`resolve_qualified_type`/`resolve_qualified_ctor`
(`typecheck.ml:707–739`), which call `Module_registry.ensure_loaded` (an
INDEPENDENT re-parse of the module's `.march` file from disk) and then
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
fix, landed earlier in this widening slice: before it, ALL four kinds loaded
unconditionally and `reject/t25`'s `Array.lst_rev(...)` (a real `pfn`,
`stdlib/array.march:39`) typechecked, compiled, and ran cross-module. Now:

```
reject/t26_cross_module_private_fn.march  →  "Function `lst_rev` is private to module `Array`."
```

re-confirmed live at this exact text (`typecheck.ml`'s `qualified_error_msg`,
line 778); exit 1, both the same shape the `ExCtor` arm already produced for
a private constructor.

**The opaque-type imbalance, stated exactly (and re-checked, not as
assumed).** `ExType`/`ExRecord` staying gate-free means a private `ptype`'s
BARE TYPE NAME is nominally referenceable in a cross-module annotation even
though the type was never added to its module's `pub_set`. `accept/t34`
witnesses this directly: `ConsistentHash.HashRing(a)` is declared
`ptype HashRing(a) = HashRing(…)` (`stdlib/consistent_hash.march:19`,
private), yet `fn ring_arity(_ring : ConsistentHash.HashRing(String)) : Int`
typechecks and, called on a real ring built through the module's own public
`new`/`add` API, runs and prints `1`. `accept/t31` (Task 1's corpus) already
pins the same pattern; `t34` is an independent second witness that exercises
the annotation specifically (not just an otherwise-unused param) and a
different stdlib module.

The design intent (`specs/lang/modules.md`'s "Visibility" section) is: `ptype`
hides everything (name AND constructor); a separate `opaque type` form hides
ONLY the constructor while keeping the type name public. **Live re-probing
for this task found the CURRENT implementation does not draw the line where
either of those two docs claims:**

- A plain `ptype`'s single (or multi-variant) constructor is **NOT hidden
  at all**: every stdlib `ptype` surveyed (`ConsistentHash.HashRing`,
  `Decimal.Decimal`, `Array.TrieEmpty`/`TrieLeaf`/`TrieBranch`) constructs and
  RUNS cross-module (e.g. `ConsistentHash.HashRing(Nil, Map.empty(), 3)` and
  `Decimal.Decimal(3, 2)`, both value-witnessed: exit 0, construct a real
  value). The grammar is the direct cause: every `variant` production
  defaults `var_vis = Public` (`parser.mly:964–972`); `ptype`'s own grammar
  rule (`parser.mly:453–460`, `DType (Private, …)`) sets the TYPE's `vis` to
  `Private` but never touches `var_vis` on its variants; only the SEPARATE
  `opaque type` rule (`parser.mly:436–440`) does
  (`List.map (fun v -> { v with var_vis = Private }) variants`). So
  `specs/lang/modules.md`'s "`ptype` makes both the type name and its
  constructors private" is not accurate against the current implementation;
  logged below.
- Even `opaque type` itself, though its grammar DOES force `var_vis = Private`
  (hence `ci_vis = Private`, since `ci_vis = v.var_vis` is copied verbatim at
  every registration site, e.g. `typecheck.ml:6686`), does **not** actually
  reject cross-module construction of its constructor either; tested live
  against `test/imports/opaque_qual/{oq_token,oq_entry}.march` (a real
  `MARCH_LIB_PATH`-discovered `opaque type Token = Token(String)`):
  `OqToken.Token("direct-bypass")` from unrelated code typechecks (exit 0)
  AND runs, constructing a real value that matches its own pattern and prints
  `"direct-bypass"`. Root cause traced exactly: a Pass-1 forward-reference
  pass, `prebind_mod_members` (`typecheck.ml:8067–8110`, called for every
  sibling `DMod` at `:8105`; the entry module's own top-level types get the
  same treatment at `:8110–8129`), registers each variant's qualified
  constructor key (`"Mod.CtorName"`) via `add_ctor qctor ci acc.ctors`
  (`:8056`) **unconditionally on `v.var_vis`**; only the SEPARATE
  disambiguated `"Mod.TypeName.CtorName"` key a few lines later checks
  `v.var_vis <> Ast.Public` before registering (`:8065–8070`). This Pass-1
  registration runs BEFORE `check_decl`'s `DMod` arm computes its own,
  correctly-`ci_vis`-filtered `new_ctors`/`qual_ctors` (§2.5 above), and the
  two results are MERGED (`typecheck.ml:6963–6969`, `StrMap.union` prepending
  the later pass's entries onto the earlier one's) rather than the later
  pass's filtering replacing the earlier, so the Pass-1 gate-free entry for the
  bare qualified key persists into the final environment regardless. **This
  is the exact same shape as the pre-Task-1 `ExFn`/`ExValue` bug** (an
  earlier, gate-free registration site shadows a later, correctly-gated one),
  but for `opaque type`'s constructor, reached via the SAME-COMPILATION-UNIT
  `DMod` prebind path rather than the cross-file `Module_registry` path Task
  1 fixed. **This is a real, confirmed compiler gap, logged (not fixed:
  out of Task 3's docs-only scope and beyond Task 1's `load_module_into_env`
  fix), in `specs/todos/`.** The PatCon (pattern-matching) side is
  differently, and also incorrectly, affected: matching `Mod.Ctor(…)`
  against a value produced by the module's own public API hits the
  UNRELATED, separately-filed qualified-type-unification gap for match
  scrutinees (`expected `Mod.Type` but got `Type``, the pattern-typing
  analog of the `9001e4c0` fix below, which only covers type ANNOTATIONS, not
  match-arm scrutinee unification) rather than a visibility diagnostic,
  live-probed but not committed as corpus (it would conflate two different
  logged gaps in one program).
- The one piece that DOES work as documented: a `ptype`'s bare type NAME
  (not its constructor) is opaque-referenceable cross-module, exactly as
  `accept/t31`/`t34` witness, because `ExType` is truly, intentionally
  gate-free in `load_module_into_env`: this side of the imbalance is real and
  intentional, not a gap.

**The no-per-module-type-namespace design point (a design fact, not a
bug).** Types are exported and resolved by their BARE name only: the `DMod`
export step never qualifies a type name beyond the `pub_set` gate itself
("Types defined in a module … are referred to by their bare name throughout
user code, not prefixed", the comment at `typecheck.ml:6909–6911`
immediately above `new_types`'s definition). One direct, silent consequence:
**two sibling modules declaring a same-named type do not collide, because
they are not just similarly-named: they are typechecked as the identical
nominal `TCon`.** `accept/t35` witnesses this exactly:

```march
mod A do type Foo = MkA(Int) fn make() : Foo do MkA(1) end end
mod B do type Foo = MkB(String) fn make() : Foo do MkB("x") end end
fn take_a(_x : A.Foo) : Int do 7 end
fn main() do println(int_to_string(take_a(B.make()))) end   -- accepts B.Foo where A.Foo is annotated
```

`--check` exits 0 with no diagnostic at all (re-confirmed live, exactly as
the survey found), and running it prints `7`, proving the substitution is
not just un-flagged at check time but truly accepted end-to-end.

> **Reconciled 2026-07-10 (post `d95fe942`, order-independent multi-module
> resolution):** the witness originally named BOTH sibling ctors `Mk`. That
> version no longer typechecks, not because per-module type identity
> appeared (it did not; the design point above is unchanged), but because a
> same-named constructor in a sibling module now shadows a module's OWN
> constructor inside its own body (`Mk(1)` in `A.make` resolves against B's
> `Mk(String)` → `expected `String` but got `Int``). Logged as
> "sibling-module constructor shadowing" in `specs/todos/`; the witness now
> uses distinct ctor names (`MkA`/`MkB`), which isolates the type-identity
> fact this section documents.
**This is documented here as ONE intentional design point, not logged as a
bug:** March has no per-module type namespace; a module boundary partitions
FUNCTION/VALUE names (via `pub_set`) but never partitions TYPE identity.
Qualified type syntax (`A.Foo`) is sugar that always unifies with the bare
name `Foo`: there is no way to write two distinct, module-scoped types that
happen to share a bare name. (Cross-ref: this is the same underlying fact
the memory-flagged "app types collide with stdlib" note describes at the
application level: a user type bare-named the same as a stdlib type
collides with it for the identical reason.)

**Qualified-type-path unification (`9001e4c0`): the mechanism that makes
the above possible, verified live in both directions.** Before this fix
(same-day as the modules survey), a qualified type annotation like
`Token.Token` resolved to a DISTINCT nominal `TCon("Token.Token", [])`,
different from the bare `TCon("Token", [])` every constructor/value actually
has, so a value produced inside a module failed to unify against its
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
`A.B.Type` (`typecheck.ml:2317–2327`, comment). Re-checked live, BOTH
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
bare-`Token`-annotated param), also exit 0. Both directions produce only an
unused-variable warning, no type-mismatch diagnostic. **The qualified-record
case (`Cfg.Site`), the survey's A10, flagged as "verify still green, don't
assume a gap" rather than a confirmed open item, was re-checked live for
this task and remains fully green**, both as a same-file nested-module
program (`accept/t36`) and via the pre-existing `test/whole_program/{cfg,
app}.march` MARCH_LIB_PATH fixture (`test/dune:614–626`'s dedicated
regression rule): `MARCH_LIB_PATH=test/whole_program ./_build/default/bin/
main.exe --check test/whole_program/{cfg,app}.march` both exit 0, re-run for
this task. `accept/t36` pins the identical shape same-file, in this corpus,
value-witnessed (prints `Site`, the record's own field, read back through
the cross-module qualified annotation `s : Cfg.Site`): no gap found; Task 1's
`ExFn`/`ExValue` gate does not touch this case (`Site`/`default`/`site_title`
are all public here), and the record path canonicalizes through the same
`surface_ty` infrastructure as the ordinary named-type case above.

**Corpus (this task):**

- `accept/t34_opaque_ptype_qualified_annotation`: `ConsistentHash.HashRing`
  (a private `ptype`) used as a cross-module param annotation; value-witnessed
  (prints `1`). Second, independent witness for the opaque-type-NAME side of
  the imbalance (`accept/t31` is the first, for `Array`).
- `accept/t35_no_per_module_type_namespace`: the `A.Foo`/`B.Foo` collision;
  value-witnessed (prints `7`), pinning the design point as a tested behavior
  rather than a discoverable surprise.
- `accept/t36_qualified_record_type_still_green`: the A10 record case,
  same-file nested-module form; value-witnessed (prints `Site`), confirming
  no regression from either `9001e4c0` or Task 1's visibility fix.
- The private-FUNCTION reject (`reject/t26_cross_module_private_fn`) and the
  narrow-gate accept witness (`accept/t31_cross_module_public_and_opaque_
  ptype`) both already live in Task 1's corpus; cross-referenced above, not
  duplicated here.

**Logged, not fixed (out of this task's docs-only scope):** the `opaque
type` constructor-hiding gap found above (`prebind_mod_members`'s gate-free
qualified-ctor registration at `typecheck.ml:8091`, persisting the later,
correctly-filtered `DMod` export step's merge), a real enforcement hole
identical in structure to the bug Task 1 fixed for `ExFn`/`ExValue`, but on
the same-compilation-unit path rather than the `Module_registry` path, and
for the `ExCtor`/`ci_vis` gate rather than the `ExFn`/`ExValue` gate. Also
logged: `specs/lang/modules.md`'s "Visibility" section overclaims `ptype`
constructor-hiding (claims `ptype` hides "both the type name and its
constructors": live-verified false, the constructor is public by grammar
default) and should be corrected to match the verified current behavior
(only `opaque type`'s constructor is marked private AT ALL, and even that
marking is not actually enforced against qualified construction, per the
gap just logged).

**Cross-reference: `use`/`import`'s selective-name rejection is the SAME
`pub_set` gate, one layer up (widening slice 2, Task 4).** `core-march.md`
§4.7.1 documents `use X.{name}`/`import X, only: […]`: the surface forms
that rebind an already-exported qualified name (`"X.name"`) as a bare name in
the CURRENT scope. Their selective-name lookup (`typecheck.ml`'s `DUse`
`UseNames`/`UseExcept` arms) reads the identical `env.vars` entries this
subsection's `pub_set` gate populates, so a selective `use` of a private
member (`use Array.{lst_rev}`, `lst_rev` a real `pfn`) is rejected for
exactly the reason a bare qualified reference to it is (`reject/t26` above):
the key was never written. The message text differs (`` Module `Array` does
not export `lst_rev`. `` vs. `reject/t26`'s `` … is private to module
`Array`. ``, since `UseNames`'s lookup cannot distinguish "absent" from
"private" the way `qualified_error_msg` can, but the OUTCOME is identically
a hard reject), confirmed live and pinned as
`reject/t27_use_selector_private_name`. This is not a second, independent
enforcement mechanism: it is the same `pub_set` absence surfacing through a
second syntactic front door.

#### 2.5.1 Intra-module reference soundness: `(T-QualRef)`, nesting does not weaken type checking

This is the headline correctness property module nesting must satisfy, and it
is worth stating as its own rule because it was for a time **not** true (a P0
soundness fix, 2026-07-08, restored it):

> **`(T-QualRef)`.** An intra-module reference to a function is checked against
> that function's **real, body-checked scheme** (the possibly-polymorphic type
> `check_fn` infers and generalizes for the function's actual body),
> **regardless of module nesting depth, and regardless of whether the reference
> is written bare (`id`) or module-qualified (`App.id`, `Main.id`).** Nesting a
> function inside a `mod` never gives a caller a weaker (more permissive) view
> of its type than a top-level definition would.

**Why this needs saying: the mechanism.** March resolves names in two passes.
A forward-reference *pre-pass* (`prebind_mod_members`, `lib/typecheck/typecheck.ml`)
seeds every module member's **qualified** key (`App.id`, and for the entry
module its own `Main.id`) into the environment so siblings can typecheck against
each other before their own declarations are reached; for an *unannotated* fn,
`prebind_fn_scheme` returns `None`, so the qualified key is seeded as a fresh
`Mono (fresh_var)` **placeholder**. Meanwhile desugar's `qualify_module_refs`
(`lib/desugar/desugar.ml`) rewrites every intra-nested-module reference to that
qualified form. The main check pass then runs `check_fn` on each declaration and
**reconciles** the placeholder to the real body-checked scheme. `(T-QualRef)`
is the guarantee that this reconciliation reaches **every** qualified key the
pre-pass can seed: at every nesting level, including the entry module's
self-qualified key.

**The hole `(T-QualRef)` closes (the P0 fix).** Before the fix, `check_decl`'s
`DFn` branch reconciled only the **bare** name. A sibling resolving the
desugar-qualified `App.id` reference therefore kept the stale
`Mono '_v` placeholder, which `infer_app`'s `TVar` branch turns into a decoupled
`?a -> ?b`, **erasing the type of anything laundered through the nested
function.** This was not `Cap`-specific and not a `unify` bug (`unify`'s `TCon`
arm is strict and never reached): a plain `Int` laundered through a nested
unannotated `fn id(x) do x end` into a `String` parameter typechecked at
`--check` exit 0: a real memory-safety break. The same erasure hit ADT
arguments (`Box(String)` → `Box(Int)`), IO-cap coercions, and proof caps
(the proof-cap forge was one exploitation of this general hole). The fix
(`check_decl` `DFn` branch, `reconcile_qkey`) binds every qualified fn key,
both the enclosing-nested key (`cap_qual_prefix ^ "." ^ fn`) and the entry
module's own self-qualified key (`current_module ^ "." ^ fn`, reached at the
entry level where `cap_qual_prefix` is `""`), to `check_fn`'s real scheme, and
`dependency_order_dfn_run` orders forward references so the reconcile runs
before a caller is checked. `unify` is untouched, so cap subsumption, the
`needs` gate, and actor `Cap` dispatch are unaffected in structure.

**Witnesses.** The reject corpus pins the erasure in every shape that was
type-correct (hence ACCEPTED, exit 0) before the fix and is now caught; IMPOSSIBLE to
reject before the fix, which is the whole point of these witnesses:

- **`reject/t51_nested_id_launder_int_to_string`**: the clearest general
  memory-safety witness: a nested unannotated `id` launders `Int` → `String`
  (`takes_str(id(42))`, `takes_str` calling `string_length`). Pinned:
  `` expected `String` but got `Int` ``.
- **`reject/t52_nested_id_launder_box`**: the ADT-argument shape,
  `Box(String)` → `Box(Int)`. Pinned: `` expected `Int` but got `String` ``.
- **`reject/t53_nested_distinct_tvar_launder`**: a nested `fn launder(x:a):b`
  with two DISTINCT signature tvars that give it an un-body-validated `a -> b`
  prebind never unified against the body constraint `a ~ b`. Pinned:
  `` expected `String` but got `Int` ``.
- **`reject/t54_entry_self_qualified_launder`**: the entry-module variant,
  `Main.id(42)` laundered through the entry module's own self-qualified key.
  Pinned: `` expected `String` but got `Int` ``.

And the positive counterpart proves the fix RESTORES (rather than over-
restricts) legitimate polymorphism: nested `id` was accidentally *monomorphic*
before the fix (the placeholder pinned to its first use), so this ALSO errored before
the fix:

- **`accept/t60_nested_id_polymorphic`**: a nested unannotated `id` used at
  both `Int` and `String` in the same nested module. `--check` exit 0.

(Full root-cause narrative and the 25-case `nested_mod_prebind_erasure` unit
group: `.superpowers/sdd/prebind-fix-report.md`; the `specs/todos/`
"Nested-module qualified-prebind type-erasure" Done entry.)

### 2.6 Actors: declaration, spawn, and `Pid` typing

March's actor construct (`actor Name do state { … } init { … } on Msg(…) do
… end end`) is checked by `typecheck.ml`'s `DActor` arm (`Ast.DActor (_vis,
name, actor, _sp)`, `typecheck.ml:6742`). This subsection pins **what that arm
verifies** and, separately, **what type `spawn(Name)` actually produces**; the
two are governed by different code and, as it turns out, disagree about the
`Pid` type parameter in a way worth stating clearly.

#### 2.6.1 What the actor declaration checks

The `DActor` arm performs, in order (`typecheck.ml:6742–6821`):

1. **State type construction (`:6744–6748`).** The `state { f : T, … }` field
   declarations are turned into a canonical `TRecord`: each field's surface
   annotation resolved by `surface_ty`, then the fields **sorted by name** so
   the state type has a stable structural identity regardless of source order.
   This record type is the actor's *state type*, written `state_ty` below.

2. **Duplicate-handler rejection (`:6752–6760`).** Two `on Msg(…)` arms with the
   *same* message name are a hard error (`` actor '…' defines handler '…' more
   than once ``), the only diagnostic the arm raises unconditionally.

3. **Constructor registration (`:6768–6784`).** Two kinds of constructor are
   added to the environment:
   - the **actor name itself** as a *nullary* constructor with a result type that is
     the actor's own name (`add_ctor name.txt { ci_type = name.txt; ci_arg_tys
     = []; … }`, `:6769`) — this is what makes a bare `spawn(Counter)` /
     `Counter` resolve at all as an `ECon(_, [], _)`;
   - one **message constructor per handler** (`ci_type = name.txt ^ "_Msg"`,
     `:6781`), so `send(pid, Msg(x))` typechecks. Unannotated handler params get
     a per-`(handler, position)` placeholder tyvar (`"$p<i>_<Msg>"`, `:6778`)
     that instantiates to a fresh variable, so an omitted annotation does not
     block `send`.

4. **`init` checked against the state type (`:6785–6787`).** The `init { … }`
   expression is checked (not just inferred) against `state_ty`, with the
   reason `` actor init must return the initial state record ``, so an `init`
   with a record shape that disagrees with the declared `state {…}` fields is
   rejected here.

5. **Each handler body checked to RETURN the state type (`:6789–6820`).** Every
   `on Msg(…) do … end` body is typechecked in an environment where `state` is
   bound to `state_ty` (`:6790`: the field is read as `state.field`, *not*
   `self.field`) and each declared message param is in scope (`:6792–6798`). The
   body's inferred type is then unified against `state_ty` (`:6805–6806`); a
   mismatch produces the rich `` handler '…' in actor '…' must return the state
   type `` diagnostic (`:6811–6819`); this is what enforces the convention that
   a handler ends by returning the *new* state record.

#### 2.6.2 `spawn`: resolved by literal actor name at compile time

`spawn` is typed by the `ESpawn` arm (`Ast.ESpawn (actor, _)`,
`typecheck.ml:4185`). It first infers the argument (`ignore (infer_expr env
actor)`, `:4186`) and then **requires the argument to be a bare actor name**:
only `ECon(_, [], _)` or `EVar` are accepted (`:4194–4202`). Anything else (an
`if`, a `match`, a function call, or a payload-carrying `A(x)`) is rejected
with the fixed diagnostic (`:4197–4202`, verified live):

> `` `spawn` needs a plain actor name written directly, like `spawn(Counter)`. ``
> A computed actor expression (from an `if`, `match`, or function call) isn't
> supported: March resolves which actor to spawn at compile time from its name.

The rationale is in the source comment (`:4187–4193`): both backends dispatch
`spawn` by the actor's *name*, resolved at compile time to a statically
generated `<Actor>_spawn` function; there is no runtime actor-descriptor value,
and the TIR lowering assumes exactly the `ECon(_, [], _)` / `EVar` shape, so
the typechecker rejects a computed actor expression up front rather than letting
a well-typed program reach the internal `failwith` in lowering. This is
witnessed by `reject/t28_spawn_computed_actor` (`spawn(pick())`, pinning the
first line of the message).

#### 2.6.3 The `Pid` type parameter: the truthful account (a finding)

`spawn(Counter)` yields `Pid[state]`, i.e. a `Pid` parameterized by the actor's
STATE type, **as of 2026-07-18** (finding 18, FIXED). What is true today:

- **`spawn` returns `Pid[state]`.** The `ESpawn` arm resolves the plain actor
  name against `env.vars` directly, reaching the `Pid[state_ty]` binding the
  `DActor` arm makes for the actor name (which is shadowed at ordinary `ECon`
  occurrences by the nullary-constructor registration), and returns its
  instantiation; only an unknown name (error recovery) still yields a fresh
  var. Probe: `let p = if true do spawn(Counter) else spawn(Named) end`, where
  `Counter`'s state is `{ count : Int }` and `Named`'s is `{ name : String }`,
  is now **rejected** by T-If (`Pid({count:Int})` vs `Pid({name:String})`),
  witnessed by `types/reject/t81` (cross-actor pid list) with the accept-side
  propagation witness `types/accept/t87`. Historically the result was
  `TCon ("Pid", [fresh_var env.level])`: a fresh, unconstrained variable that
  let any two spawns unify opportunistically.

- **The `Pid[state_ty]` binding at `:6821` exists but is effectively
  unobservable.** After checking the handlers, `DActor` does `bind_var name.txt
  (Mono (TCon ("Pid", [state_ty]))) env_with_ctors` (`:6821`): the actor *name*
  is var-bound to `Pid[state]`. But a bare occurrence of the actor name never
  reaches this binding: the *constructor* registration at `:6769` (the actor as
  a nullary `ECon` of type `<Name>`) takes precedence, so a bare `Counter` is
  typed `Counter`, not `Pid[state]`. Probe: `is_alive(Counter)` (where
  `is_alive : Pid(a) -> Bool`) is **rejected** with `` expected `Pid(r3)` but
  got `Counter` ``: the name resolves to the nullary ctor's `Counter` type, not
  the `Pid[state]` value binding.

- **Even an explicit `Pid[T]` annotation is impossible today.** The built-in
  `Pid` is registered at arity 1 (`builtin_types`, `typecheck.ml:1849`), but the
  stdlib module `GlobalPid` declares `type Pid = { node_id : String, local_pid :
  Int, creation : Int }` (`stdlib/global_pid.march:11`), a *0-arity record*.
  Because March has a single global type namespace with no per-module type
  identity (§2.5, the no-per-module-type-namespace design point), that bare
  `Pid` **shadows** the built-in in `env.types`, so a surface annotation
  `Pid(T)` is rejected with `` `Pid` expects 0 type argument(s) but got 1. ``
  (arity check, `:2348–2351`). There is thus no annotation the surface can write
  to *force* a `Pid`'s parameter to the state type either.

**Net:** the state type is truly *checked*: `init` and every handler must
conform to it (§2.6.1); but it does **not** propagate to any observable `Pid`
at a `spawn` site. `spawn(Counter) : Pid[α]` for a fresh `α`; the `α` unifies
opportunistically with whatever the surrounding builtins demand (e.g. the `a` in
`is_alive : Pid(a) -> Bool`, `:1341`), and stays free otherwise. The
"`Pid[state]`" phrasing is therefore aspirational, not a fact about the current
typechecker; `accept/t39_actor_spawn_pid` witnesses the accept path (`is_alive`
on a fresh `spawn` result), and this finding is logged in §4.1.

#### 2.6.4 Message-payload typing, and the actor-affinity non-guarantee

`send(target, Msg(args))` is typed by the `ESend` arm (`Ast.ESend (cap, msg,
sp)`, `typecheck.ml:4177`). It does exactly three things, in order:

1. **Infers and DISCARDS the target's type**: `ignore (infer_expr env cap)`
   (`:4178`). The `cap` Pid is typed (so a truly ill-typed target expression
   still errors) but its type is thrown away: `send` never consults *which actor*
   the target is, nor any accepted-message set.
2. **Infers the message type**: `let msg_ty = infer_expr env msg` (`:4179`).
   This is the payload-typing rule: because `msg` is an ordinary expression,
   `Msg(args)` runs the **ordinary `ECon` constructor arm** (T-Con, §2). Each
   handler `on Msg(p : T)` registered a message constructor `Msg` of payload type
   `T` (message ctor `<Actor>_Msg`, §2.6.1 step 3), so `Msg(args)` is checked
   exactly like any other constructor application: a wrong-typed argument is a
   plain unification mismatch, no actor-specific infrastructure involved.
3. **Runs `check_sendable`**: `check_sendable env.errors sp msg_ty` (`:4180`,
   def `:3335`). This walks the structure of `msg_ty` and errors ONLY on a
   `RingBuf`-family constructor (`let non_sendable_types = ["RingBuf"]`, `:3331`),
   a hardcoded denylist of types that must stay owned by one actor. It is *not*
   a message-acceptance check.

`send` then returns `fresh_var env.level` (`:4183`): an unconstrained result, so
a caller may `match` on it (drop/`Option` semantics) or read state fields.

**(T-Send): the message-payload typing rule.**
```
Γ ⊢ cap ⇒ τ_cap        (τ_cap inferred, then discarded)
Γ ⊢ msg ⇒ τ_msg        (ordinary ECon; the message ctor's payload type is checked)
check_sendable(τ_msg)  (errors iff τ_msg mentions RingBuf)
─────────────────────────────────────────────────────────  (T-Send)
Γ ⊢ send(cap, msg) ⇒ β        (β fresh)
```

So the payload *shape* IS statically checked: `send(counter, Inc("x"))` where the
handler is `on Inc(x : Int)` is rejected with the ordinary constructor-argument
mismatch `` expected `Int` but got `String`. `` (witness
`reject/t29_actor_send_wrong_payload`, captured live); a correctly-typed
`send(counter, Inc(3))` typechecks (witness `accept/t40_actor_send_typed_payload`).

**The actor-affinity non-guarantee: a `send` is NOT checked against the target
actor's message set (finding 19).** Because step 1 discards `τ_cap` and step 3
only denylists `RingBuf`, **no check confirms that the target actor actually handles
the message you send it.** Sending a message that a *different* actor declares (
`send(counter, Log("stray"))` where `Log` is a `Logger` handler, not a `Counter`
one) `--check`s clean (exit 0). The `Pid`'s parameter cannot gate this even in
principle: per §2.6.3, `spawn` yields `Pid[state]` (finding 18, fixed
2026-07-18), and the STATE record type reveals no fact about the actor's
accepted-MESSAGE set. This is distinct from finding 18: finding 18 was "the Pid
is unparameterized after spawn / a `Pid(T)` annotation is impossible" (the
former part now fixed); **this** finding is "`send`
does not gate the message by the target actor", rooted at `:4178` (target type
discarded) and `:3331`/`:3335` (`check_sendable` is a `RingBuf` denylist, not an
acceptance check), and it would remain true even if the Pid *did* carry a state
type, because `send` never reads `τ_cap`.

The **runtime consequence diverges by backend** (both verified live; see
`§4.1` finding 19 for the exact captured output):

- **Interpreted:** the message is dispatched by matching its tag against the
  actor's handler *names* by string equality (`h.ah_msg.txt = msg_tag`,
  `eval.ml:7545`); a foreign message matches no handler, so the `None ->`
  branch **silently drops** it (`eval.ml:7547-7549`). No output, no crash.
- **Compiled:** the message is lowered to a per-actor `<Actor>_Msg` variant in
  *handler-declaration order* (`lower_actor.ml:17`) and dispatched by an
  `ECase` on that variant's discriminant with **no default arm** (`ECase(msg,
  branches, None)`, `lower_actor.ml:256`). A foreign message's discriminant
  indexes into the *target* actor's branch table and hits whatever handler
  occupies that slot: the `Log("stray")` above lands in `Counter`'s first
  handler `Inc`, and its body then reinterprets the `String` payload pointer as an
  `Int` (garbage, non-deterministic). It is **misrouted, not dropped**: a
  memory-unsafe outcome, not a benign no-op.

This backend split makes the non-guarantee sharper than "messages are best-effort
dropped": in compiled code a wrong-actor send is undefined behavior. It is
documented, not corpus-encoded: it typechecks (exit 0), so it cannot be a
`reject/` witness; the accept path (`send(counter, Inc(3))`) is
`accept/t40_actor_send_typed_payload`, and the non-guarantee itself is logged as
an open gap (finding 19, `specs/todos/`).

**The message-name flat global namespace: a design point, not a bug.** Message
and handler constructor names (`Inc`, `Log`, …) live in the **single flat global
constructor namespace**, like every other constructor: there is no per-actor
message namespace, exactly analogous to the no-per-module-type-namespace design
point (§2.5). Two actors may not both declare a handler of the same name in a way
that resolves ambiguously; a collision requires the ordinary qualified-name form
(`Actor_Msg.Report`-style qualification) to disambiguate, just as a colliding
type name across modules requires a qualified path (§2.5). This is intentional and
uniform with the rest of the constructor namespace; it is not logged as a gap.
(It also underlies the compiled misroute above: because message constructors
share one namespace and the compiled dispatch is by per-actor-variant
discriminant *position*, a message from actor A's variant and a message from
actor B's variant can occupy the same discriminant slot and look
the same to B's dispatch `ECase`.)

### 2.7 Session types: protocols, projection, and channels

March has a **session-typed channel** construct: a `protocol` declares a
global choreography between named roles, the typechecker **projects** that
global choreography onto each role's own point of view (a `session_ty`), and
a `Chan(Role, Proto)` value is a **linear** endpoint that stores that local view
as live, mutable type-state: every channel operation both checks the current
state and advances it. This subsection covers the DECLARATIVE side: what a
`protocol` looks like, how projection computes each role's local type, how
binary duality and MPST consistency are verified, and what `Chan(Role, Proto)`
resolves to as a surface type. **Per-operation typing** (what `Chan.send`/
`Chan.recv`/`Chan.choose`/`Chan.offer`/`Chan.close` each require and how they
advance the state) is a different arm of `typecheck.ml` and is covered by a
later widening task, not here.

#### 2.7.1 `protocol` declaration: three step forms

A protocol is a top-level declaration, `DProtocol of name * protocol_def *
span` (`lib/ast/ast.ml:151`), where `protocol_def = { proto_steps :
protocol_step list }` (`ast.ml:287–289`). `protocol_step` has **four**
variants (`ast.ml:291–295`): there is no separate "receive" step (send/recv
are the two ends of one `ProtoMsg`) and no `ProtoEnd`/`ProtoVar` (those are
synthesized only during projection, §2.7.2):

```
and protocol_step =
  | ProtoMsg    of name * name * ty                         (* Sender -> Receiver : T *)
  | ProtoLoop   of protocol_step list                        (* loop do ... end *)
  | ProtoChoice of name * (name * protocol_step list) list   (* choose by Role: label -> steps *)
  | ProtoStop   of span                                      (* stop -- exits an enclosing loop *)
```

The parser (`lib/parser/parser.mly`) mirrors this one-for-one: `protocol_decl`
is `PROTOCOL upper_name DO list(protocol_step) END`; `protocol_step` matches
`sender ARROW receiver COLON ty` → `ProtoMsg`, `LOOP DO ... END` →
`ProtoLoop`, `CHOOSE BY chooser COLON ... branches ... END` → `ProtoChoice`
(branches via `choose_branch: option(PIPE) label ARROW list(protocol_step)`),
and a bare `lower_name` with text `"stop"` → `ProtoStop`; any other
identifier there is a parse error naming `stop` as the only valid step
(`` I don't recognize `<name>` here — the only protocol step allowed is
`stop` (to exit an enclosing `loop`). ``). `stop` (2026-07-27) is
intentionally a **contextual** keyword, not a reserved word: it is recognized
only in the `protocol_step` position, via the same `lower_name` production
ordinary identifiers use, so `stop` remains legal everywhere else (a variable,
function, or field named `stop` is unaffected). Example (the parser's own doc comment,
`parser.mly:606–614`; **corrected here**: the doc comment itself writes
`Ack()`, but `ty`'s grammar has no zero-argument-parens type-application
production (`Name()` is a parse error, "I got stuck here", confirmed live
against both this exact protocol step and a plain `Ack()` return-type
annotation; only a bare `Name` or an at-least-one-arg `Name(t, …)` parses),
so the payload type below is written `Ack`, matching what the grammar
actually accepts:

```march
protocol Transfer do
  Client -> Server : Request(String)
  Server -> Client : Response(Int)
  loop do
    Client -> Server : More(String)
    Server -> Client : Ack
  end
end
```

Roles (`Client`, `Server` above) are bare uppercase names: there is no
separate "declare a role" syntax. A role does not need to be a declared type
(a bound `type Client = Client` or similar), and no diagnostic is reported when it
isn't: protocol roles are their own namespace, not type or actor names.

> **Changed 2026-07-24.** Until that date the typechecker emitted a non-fatal
> HINT ("participant X is not a known actor or type") during `--check`/run for
> any role without a matching declaration. It was removed: it fired on every
> ordinary protocol, including this document's own examples, and roles were
> never meant to resolve as types in the first place. This document's corpus
> programs (§2.7.6) still declare each role as its own nullary type; that is
> now stylistic, not a way to silence a diagnostic. See `core-march.md` §4.11.6
> (finding F8) for the operational-side write-up.

#### 2.7.2 `session_ty`: the local, per-role view

The type layer's representation of channel state is `session_ty`
(`typecheck.ml:105–116`, "Local session type — per-endpoint view of a binary
protocol. Computed by projecting the global `Ast.protocol_def` onto one
role."):

```
and session_ty =
  | SSend   of ty * session_ty            (* Send a value of type T, then follow S (binary) *)
  | SRecv   of ty * session_ty            (* Receive a value of type T, then follow S (binary) *)
  | SChoose of (string * session_ty) list (* Actively select a branch label *)
  | SOffer  of (string * session_ty) list (* Passively wait for the other side to pick *)
  | SEnd                                  (* Session complete -- channel must be closed *)
  | SRec    of string * session_ty        (* Recursive binding: Rec(X, S) *)
  | SVar    of string                     (* Back-reference to a recursive binder *)
  | SError                                (* Error sentinel *)
  (* MPST: role-annotated send/recv for multi-party protocols (N>2 participants). *)
  | SMSend  of string * ty * session_ty   (* Send to role: MSend(target_role, T, S) *)
  | SMRecv  of string * ty * session_ty   (* Receive from role: MRecv(source_role, T, S) *)
```

`SSend`/`SRecv`/`SChoose`/`SOffer` are the **binary** (exactly 2 roles) forms;
`SMSend`/`SMRecv` are their **MPST** (>2 roles) counterparts, each with an
explicit peer-role name instead of relying on there being only one possible
peer. `SRec`/`SVar` encode a `loop` as a named recursive binder plus
back-references to it: the standard µ-type encoding (`Rec(X, S)` /
`X`). `SEnd` means the session is complete and the channel must be closed;
`SError` is an internal sentinel for a protocol that failed to project (so a
malformed protocol doesn't cascade into unrelated unification failures
downstream).

The channel *value's* type is `TChan of session_ty ref` (`typecheck.ml:95`,
"Linear session-typed channel endpoint"): a `ty` constructor wrapping a
**mutable reference** to the endpoint's *current* local session state. This
is why a channel is not polymorphic: `TChan` is treated as closed/opaque by
`occurs`/`subst`/`ftv` (no type variables flow through it), and why each
channel operation can *mutate* the ref in place to reflect the new state
after the operation, rather than requiring the surrounding code to thread a
fresh type through by hand (the per-operation typing that reads/rewrites this
ref is the subject of the later per-op widening task).

Structural equality over `session_ty` comes in two flavors, both critical
for what follows: `session_ty_equal` (used by `unify` when two `TChan`s meet,
and by the binary duality check, §2.7.3) and the stricter
`session_ty_exact_equal` (`typecheck.ml:2058`, "Exact structural equality
including payload types. Used by MPST mergeability check to determine if
branches can be merged. Two branches can be merged only if they are
completely identical."); the latter is exactly what makes §2.7.5's F4
finding possible.

#### 2.7.3 Projection: global protocol to per-role local type

**`project_steps env ~proto_name ~multiparty steps role cont`**
(`typecheck.ml:7482`) walks a `protocol_step list` and produces the
`session_ty` that `role` observes, given a continuation `cont` for what comes
after these steps. Each step form computes its own local `rest_ty ()` (the
projection of everything textually AFTER it at the same nesting level, with
`cont` at the very end), and that `rest_ty ()`, not the raw outer `cont`, is
what the two recursive arms below actually thread through:

- **`ProtoMsg (sender, receiver, msg_ty)`**: if `role` is the sender, emit
  `SSend`/`SMSend` (binary/MPST, keyed on the `~multiparty` flag) with the
  receiver's name (MPST) and `rest_ty ()`; if `role` is the receiver, emit
  `SRecv`/`SMRecv` symmetrically; if `role` is neither, this step is invisible
  to `role` and projection just recurses into `rest_ty ()`: the role
  "doesn't participate in this step."
- **`ProtoLoop inner_steps`** (`typecheck.ml:7499–7512`): `loop do S end` is
  the µ-type `Rec X. S[X]`: the inner steps are projected with a fresh `SVar`
  back-reference (`<proto_name>_loop`) as their OWN continuation (not
  `rest_ty ()`), so the loop body's last step points back to its first, and
  the loop repeats indefinitely rather than unrolling once. **[FIXED
  2026-07-24]** An earlier version of this arm instead substituted the
  post-loop continuation into the back-reference (`subst_svar`), which
  produced a hollow `SRec` containing no actual `SVar`: one unrolled
  iteration, not a real recursive type; see finding 22 below (§4.1). If the
  role isn't involved anywhere in the loop body, the loop still collapses
  away entirely (the `inner = SVar _` case) rather than emitting a hollow
  `SRec`; otherwise the projected body is wrapped in `SRec (rec_var, ...)`.
  Because the loop's continuation is its own back-reference, control can
  never fall out of a `loop` block into steps that follow it; `DProtocol`'s
  own validation (`typecheck.ml:8936–8952`, `check_unreachable_after_loop`,
  independent of `project_steps`) walks the ORIGINAL step list before
  projection and rejects any step following a `loop` at the same nesting
  level with `` Protocol `<name>`: the steps after this `loop` can never
  run — a `loop` block repeats forever, so it must be the last step. `` This
  is an intentional rule (a `loop` must be a protocol's last step), not a gap:
  see the session-types reference's "Repetition: `loop`" section.
- **`ProtoChoice (chooser, branches)`** (`typecheck.ml:7513–7542`): **[FIXED
  2026-07-24]** each branch's steps are now projected with `after_choice =
  rest_ty ()` (the steps that FOLLOW the entire choice block) as their
  continuation, since every branch eventually rejoins the same protocol
  tail. An earlier version projected each branch with the OUTER `cont`
  directly, which at top level is `SEnd` and silently truncated every step
  written after a `choose … end` block from BOTH roles' projections (see
  finding 23 below, §4.1). If `role` is the chooser, the result is `SChoose
  branch_tys` (an active choice); otherwise it's `SOffer branch_tys` UNLESS
  `multiparty` is true AND every branch happens to project to the exact
  same local type for this role (`session_ty_exact_equal`, checked pairwise
  against the first branch), in which case the branches **merge** into
  that single shared type, because a bystander role in a 3+-role protocol
  "need not observe the choice at all." This is the standard MPST merge
  rule (`typecheck.ml:7538`, guarded on `multiparty`), and it is the
  mechanism behind the (since-fixed) F4 finding described in §2.7.5 below;
  the `multiparty` guard is exactly what closes F4: a binary protocol's
  non-chooser now always projects to `SOffer{…}`, never merges, because
  there is no bystander role for a 2-role protocol to be one of.
- **`ProtoStop _`**: **[ADDED 2026-07-27]** projects to `SEnd`, for every
  role, unconditionally; it ignores both the surrounding `cont` and
  `rest_ty ()` entirely, rather than threading either through. This is what
  gives a `loop` a way out: a `choose` branch inside a `loop` that ends in
  `stop` reaches a real terminal state instead of looping back to the
  binder, so a channel that takes that branch can `Chan.close` on both ends
  where an unconditionally-looping protocol never could. Because `stop`
  discards `rest_ty ()`, any steps written after it in the same list (or the
  tail of an enclosing `choose` a `stop`-ending branch would otherwise
  reach) are unreachable: `DProtocol`'s validation extends the same
  `check_unreachable_after_loop` walk that already rejects steps after a
  `loop` to treat `ProtoStop` identically, and separately rejects a `stop`
  found outside any enclosing `loop` (that position is a no-op: the
  protocol already ends where its step list ends, so it is flagged rather
  than silently accepted). Duality needs no special-casing: `dual_session_ty`
  already maps `SEnd` to `SEnd`, so a `stop` branch's projection is
  automatically dual to its peer's `SEnd`. See the session-types reference's
  "Exiting a loop: `stop`" section; corpus:
  `accept/t105_loop_stop_two_iterations_close` (two loop iterations, exit via
  `stop`, close both endpoints), `reject/t106_stop_outside_loop`,
  `reject/t107_steps_after_stop_unreachable`.

**`project_protocol env ~span ~proto_name pdef`** (`typecheck.ml:5952`) is the
entry point: it collects every role mentioned anywhere in the protocol
(`roles_of_steps`, walking all three step forms including branch arms), sets
`multiparty = List.length roles > 2`, and projects each role via
`project_steps ... role SEnd` (every role's local view ends in `SEnd` unless
a `loop` makes part of it recursive). The `(role, session_ty) list` result is
stored as `pi_projections` on the `proto_info` record (`typecheck.ml:428–431`,
"Computed session-type information for a declared `protocol`. Stored in
`env.protocols` after `DProtocol` is checked."), keyed by protocol name.

After projecting, `project_protocol` runs a **consistency check** that
differs by role count:

- **Binary (exactly 2 roles `[a; b]`)**: verifies **duality**: `dual(proj_a)
  == proj_b` (§2.7.4).
- **Multiparty (>2 roles)**: verifies **matching send/recv role pairs**
  (§2.7.4's MPST paragraph).

A protocol that fails either check is rejected at its OWN declaration site:
the error is attached to the `protocol` block's span, not to any later use of
`Chan.new`/`Chan(Role, Proto)`.

#### 2.7.4 Duality (binary) and consistency (MPST)

**Binary duality.** `dual_session_ty` (`typecheck.ml:5935`) computes what the
*other* endpoint of a binary session must look like: `SSend ↔ SRecv` (with the
payload type held fixed and the continuation recursively dualized), `SChoose
↔ SOffer` (branch-wise), and `SEnd`/`SVar`/`SError` are self-dual (unchanged).
`project_protocol`'s binary arm (`typecheck.ml:5972–5986`) then requires
`session_ty_equal (dual_session_ty proj_a) proj_b`, i.e. role `a`'s local
type, mechanically dualized, must equal role `b`'s ACTUAL projected local
type. A mismatch is reported with both sides rendered via `pp_session_ty`:

> `` Protocol `<name>`: the projection onto `<a>` and the projection onto
> `<b>` are not duals of each other.
> dual(<a>) = <printed dual>
> but <b> has: <printed actual projection> ``

This is exactly the diagnostic the F4 repro below produces.

**MPST consistency.** For protocols with more than two roles, there is no
single "the other side" to dualize against; instead, `project_protocol`'s
multiparty arm (`typecheck.ml:7612+`) walks every `ProtoMsg(sender, receiver,
T)` in the ORIGINAL global steps (via `gather_msgs`, recursing through
`ProtoLoop`/`ProtoChoice`) and, for each one, confirms that the sender's own
projection actually contains a matching `SMSend(receiver, T, ...)` somewhere
along its spine (`has_msend`, unfolding `SRec`s and descending into
`SChoose`/`SOffer` branches) AND the receiver's projection contains the
matching `SMRecv(sender, T, ...)` (`has_mrecv`, symmetric). This is a weaker
check than binary duality: it confirms every declared message has a sender
side and a receiver side that agree on type, but (unlike the binary case) it
does not attempt to verify the full relative ORDERING of every role's local
type against every other role's; ordering consistency for 3+ roles is
enforced only insofar as `project_steps`'s single top-down walk of the shared
global step list is definitionally what both projections are derived from.

**F3 RE-CHECKED 2026-07-24: the compiled MPST runtime is not broken for
send/recv/close.** The projection/consistency infrastructure above is real,
exercised by `--check`, and covered by an accept witness in this task's
corpus (§2.7.6, `t42`). An earlier version of this document claimed every
`MPST.*` program segfaulted compiled (exit 139); re-run live for this task, a
3-role AND a 4-role `MPST.*` protocol (`Int`/`Bool`/`String` payloads,
send/recv/close only) both compile, run, and print output identical to the
interpreter, exit 0 (full transcript in `specs/todos/`). What truly
remains unimplemented is **multiparty `choose`/`offer`**: `MPST.choose` and
`MPST.offer` do not exist as typed operations at all; calling either now gets
an explicit `` not a session-channel operation I know `` compile error
(`typecheck.ml:4756–4773`) rather than reaching the runtime, so there is no
"segfaults" story left to tell for that surface either. MPST also still has
no *golden* (`specs/lang/golden/`) conformance witness (only this ad hoc
transcript), so treat a send/recv/close-only MPST program as verified-correct
but not mechanically pinned the way the binary `Chan.*` plane is (§4.11.5 of
the operational reference).

#### 2.7.5 The F4 finding: the MPST merge rule leaks into binary duality

**[OPEN: logged, not fixed] A legal binary protocol with two `choose`
branches that carry the SAME payload type is wrongly rejected as "not duals."**
Cause: the mergeability optimization in `project_steps`'s `ProtoChoice` arm
(`typecheck.ml:5906–5919`, §2.7.3) is a correct rule for a **non-chooser role
in an MPST protocol**: if that role can't tell the branches apart, it's fine
to collapse them. But `project_steps` applies this SAME merge rule
unconditionally, including when `multiparty = false` (a plain 2-role binary
protocol). For a binary protocol, the "non-chooser" IS the chooser's sole
peer; there is no third role for whom the branches are "irrelevant." When
both `choose` branches happen to carry an identical local type
(`session_ty_exact_equal`), the peer's projection COLLAPSES from `SOffer
{...}` down to that single shared type, which is no longer the dual of the
chooser's `SChoose {...}`, so the binary duality check (§2.7.4) rejects the
protocol as malformed even though it is a perfectly sensible binary
choose/offer protocol.

**Minimal repro: rejected** (`Server`'s two branches both send an `Int`
back to `Client`, so they merge and duality breaks):

```march
protocol Decision do
  choose by Client:
    ok  -> Server -> Client : Int
    err -> Server -> Client : Int
  end
end
```

`march --check` on this protocol exits **1**:

```
Protocol `Decision`: the projection onto `Client` and the projection onto `Server` are not duals of each other.
dual(Client) = Offer{ok: Send(Int, End), err: Send(Int, End)}
but Server has: Send(Int, End)
```

(Note the diagnostic itself is evidence of the bug: `Server`'s actual
projection printed is `Send(Int, End)`, the MERGED type, not `Choose{ok:
..., err: ...}`, which is what a chooser's projection should be.)

**Same protocol shape, branches made type-distinct, accepted:**

```march
protocol Decision do
  choose by Client:
    ok  -> Server -> Client : Int
    err -> Server -> Client : String
  end
end
```

`march --check` on this variant exits **0**: because the branches no longer
satisfy `session_ty_exact_equal`, the merge doesn't fire, `Client`'s
projection stays a real `SOffer {ok: Recv(Int,End), err: Recv(String,End)}`,
and that IS the dual of `Server`'s `SChoose {ok: Send(Int,End), err:
Send(String,End)}`.

**Impact:** any binary protocol author who happens to give two `choose`
branches the same payload type (a common, unremarkable shape, e.g. both an
`ok` and an `err` branch replying with a plain `Int` status code) hits a
spurious, confusing rejection with a message that talks about "duals" rather than
anything resembling "make your branches type-distinct." The workaround
(differentiate the branch payload types, even trivially, e.g. wrap one in a
single-field record) is non-obvious from the error text by itself. This was a
real typechecker bug, **FIXED 2026-07-07** (fix-campaign pilot): the
merge-rule branch in `project_steps`'s `ProtoChoice` arm is now gated on
`multiparty`, so a binary (2-role) protocol's non-chooser always projects to
`SOffer{…}` (it always observes the choice) and only a true MPST bystander
role merges. A binary protocol with two identical-type `choose` branches now
typechecks (witnessed by `accept/t44_binary_choice_identical_branches`). The
prose above is retained to describe the historical bug; the "workaround" is
no longer necessary. See `specs/progress/` for the completed entry.

#### 2.7.6 `Chan(Role, Proto)`: the linear channel-endpoint surface type

Users write `Chan(RoleName, ProtoName)` as a type annotation (e.g. a function
parameter `ch : Chan(Client, Echo)`). The parser produces this as an ordinary
type application, `TyCon("Chan", [TyCon(RoleName,[]); TyCon(ProtoName,[])])`;
there is no dedicated channel-type grammar production. `surface_ty`
intercepts this shape as a special case (`typecheck.ml:2285–2311`, inside the
`Ast.TyCon (name, args)` arm) BEFORE the general type-lookup path:

1. Look up `proto.txt` in `env.protocols`; if it's not a declared protocol,
   error `` I don't know a protocol called `<name>`. `` and return `TChan (ref
   SError)`.
2. Otherwise, look up `role.txt` in that protocol's `pi_projections`
   (§2.7.3); if the role never appeared in the protocol, error `` Protocol
   `<proto>` has no role called `<role>`.\nKnown roles: <comma-separated list>
   `` and return `TChan (ref SError)`.
3. Otherwise, return **`TLin (Ast.Linear, TChan (ref sty))`**: the role's
   projected local `session_ty`, wrapped in a fresh mutable ref, wrapped in
   `TChan`, wrapped in a **linear** marker.

The `TLin (Linear, ...)` wrapper is not incidental: a channel endpoint MUST be
used exactly once along its session (each operation consumes the current
endpoint value and returns a new one representing the advanced state), so the
surface type is linear by construction: the same linearity infrastructure that
governs other linear values in March (letting the generic linear-`let`
tracker catch a double-use of a channel binding). `Chan.new(Proto)`
constructs a pair of such endpoints directly (returning the first two role
projections as a `(linear Chan, linear Chan)` tuple; MPST's `MPST.new`
returns an N-tuple, one endpoint per role, in role-sorted order); the exact
checks each `Chan.*`/`MPST.*` builtin performs on ITS argument's current
`session_ty` state (requiring `SSend`, requiring `SEnd`, etc.) are the
per-operation typing arms deferred to the later widening task (§2.7's
preamble).

#### 2.7.7 Corpus witnesses (this task)

Three new `accept/` programs (§3's sibling harness, `specs/lang/types/`,
`t41`–`t42`):

- **`accept/t41_binary_protocol_chan_new`**: a well-formed BINARY protocol
  (`Echo`, `Client -> Server : Int; Server -> Client : Int`), `Chan.new(Echo)`
  destructured into a `(Chan(Client,Echo), Chan(Server,Echo))` pair, both
  endpoints threaded through a straight-line send/recv/close sequence with
  send always textually before its matching recv (avoiding the unrelated
  no-scheduler recv-before-send runtime deadlock the operational widening
  task documents), a real positive witness for §2.7.1–§2.7.4 and
  §2.7.6's `Chan(Role, Proto)` annotation resolving to a real projected
  `session_ty`. `--check` exits 0; run interpreted, prints `43` (an Int
  echoed and incremented once round-trip), confirming the projected types
  actually correspond to a runnable protocol shape (not just a
  vacuously-accepted declaration).
- **`accept/t42_mpst_protocol_new`**: a well-formed 3-role MPST protocol
  (`Relay`: `Client -> Server : String; Server -> Logger : String; Logger ->
  Client : String`), `MPST.new(Relay)` destructured into a 3-tuple of role
  endpoints; witnesses §2.7.3's multiparty branch of `project_protocol`
  (role collection, `multiparty = true`, the send/recv-pair consistency
  check) and §2.7.4's MPST F3 callout: the protocol DECLARATION and the
  `MPST.new` construction both `--check` and run clean (interpreted prints a
  confirmation string). This witness is `--check`-anchored and intentionally
  does not exercise sending/receiving over the resulting endpoints, but as
  of the 2026-07-24 re-verification (§2.7.4), doing so is no longer expected
  to fail either: a full 3-role send/recv/close round-trip compiles and runs
  correctly on both backends (transcript in `specs/todos/`).

Both new programs declare every role (`Client`/`Server`/`Logger`) as its own
nullary type (`type Client = Client`, etc.), originally to avoid the
undeclared-role HINT then described in §2.7.1: a intentionally clean `--check`
run with no stderr noise at all. That HINT was removed on 2026-07-24 (see the
changed-note in §2.7.1), so the declarations are now stylistic; the programs
were left as written.

The F4 finding (§2.7.5) was NOT given its own `reject/` corpus program when
this task first found it: unlike the corpus's usual reject witnesses (which
pin a program that is CORRECTLY rejected), a `reject/` entry for F4's repro
would have required that the wrongly-rejected protocol was SUPPOSED to fail,
codifying the bug as intended behavior, exactly the anti-pattern this
document's other findings (e.g. findings 15–17, §4.1) already avoid for the
same reason. **F4 is now FIXED** (§2.7.5): the exact shape F4 used to reject
is pinned as an `accept/` witness instead,
`accept/t44_binary_choice_identical_branches`.

#### 2.7.8 Per-operation channel typing: the state-ADVANCEMENT arms

§2.7.6 named the six `Chan.*` builtins (`new`/`send`/`recv`/`close`/`choose`/
`offer`) as "the exact checks each op performs on its argument's current
`session_ty` state" without detailing them; this subsection is that detail
(widening slice, Task 3). Every op is a hard-coded `EApp (EVar "Chan.<op>",
args, sp)` case in `infer_expr` (`typecheck.ml:4323–4551`), matched BEFORE the
general application arm, immediately after a normalization step
(`typecheck.ml:4311–4318`) that rewrites the field-access surface form
`Chan.send(ch, v)` (parsed as `EApp(EField(ECon("Chan",[],_), "send", _),
[ch;v], sp)`) into the canonical `EApp(EVar "Chan.send", [ch;v], sp)` shape
every arm below matches on. Each arm follows the same three-step shape: read
the channel argument's current type, `unfold_srec` it (§2.7.2) to expose the
outermost `session_ty` constructor, and either advance (success) or report
`pp_session_ty other` in a dedicated error (failure). All six ops consume
their channel argument as a `TLin (Linear, TChan (ref sty))` (§2.7.6) and, on
success, return a FRESH `TChan (ref cont)` (a new mutable ref, not the same
one), matching the linear discipline: the old endpoint value is gone, only
the newly-returned one is live.

- **`Chan.new(Proto)` (`typecheck.ml:4323–4362`).** Not itself a state
  transition (there is no incoming channel), but the entry point that
  MANUFACTURES the first `TChan` values: the sole argument must resolve to a
  declared protocol name (`ELit(LitString _)`/`ELit(LitAtom _)`/`EVar`/
  `ECon(_,[],_)`; a bare `Chan.new(Echo)` is the `ECon` shape, `:4324–4328`);
  looked up in `env.protocols` (error `` Chan.new: protocol `<name>` is not
  declared. `` if absent, `:4336–4340`); the protocol's `pi_projections`
  (§2.7.3) must have **at least two** roles (`` protocol `<name>` has no
  roles. ``/`` protocol `<name>` has only one role. `` for 0/1, `:4348–4355`).
  For exactly 2 roles, returns a 2-tuple of both projections (in
  `pi_projections`'s stored role-sorted order, §2.7.3), each independently
  wrapped `TLin (Linear, TChan (ref sty))` (`:4341–4347`). **[FIXED
  2026-07-24]** For 3-OR-MORE roles, `Chan.new` now REJECTS the protocol
  entirely: `` Chan.new: protocol `<name>` has N roles but Chan.new needs
  exactly 2. Use MPST.new for multi-party protocols. `` (`:4356–4361`,
  `reject/t94`), rather than the earlier silent fallback of returning the
  first two projections in `pi_projections`'s sorted order as if they were a
  binary pair, which produced two endpoints that are NOT duals of each other
  (see finding 24 below, §4.1). A caller wanting all N endpoints for a
  3+-role protocol uses `MPST.new` instead (§2.7's MPST paragraph), which
  returns the full N-tuple.
- **`Chan.send(ch, v)` (`typecheck.ml:4366–4393`).** Requires the channel be
  at `SSend(payload_ty, cont)` (`:4376`); `check_expr`s `v` against
  `payload_ty` with `~reason:(Some (RBuiltin "Payload type of Chan.send"))`
  (`:4377–4378`); this is an ORDINARY checking-mode call into the same
  bidirectional engine §1/§2 describe, so a payload type mismatch renders as
  the generic mismatch diagnostic (e.g. `` expected `Int` but got `String`. ``
  with the `Payload type of Chan.send` reason line), NOT a session-specific
  message (`reject/t33`, §2.7.10). On success, returns `TLin (Linear, TChan
  (ref cont))` — the channel advances to `cont`, the continuation named in
  `SSend`. Any other incoming state is rejected: **`` Chan.send: channel is
  at `%s` but I expected `Send(T, ...)`. `` (`:4382–4385`)**, `%s` filled by
  `pp_session_ty other` (e.g. `` channel is at `Recv(Int, End)` but I
  expected `Send(T, ...)`. ``, `reject/t30`).
- **`Chan.recv(ch)` (`typecheck.ml:4397–4422`).** Requires `SRecv(payload_ty,
  cont)` (`:4407`); no payload to check (recv PRODUCES a value, it
  doesn't consume one); on success returns `TTuple [payload_ty; TLin
  (Linear, TChan (ref cont))]` (`:4408`), i.e. a `(T, Chan)` pair, advancing
  to `cont`. Wrong state: **`` Chan.recv: channel is at `%s` but I expected
  `Recv(T, ...)`. `` (`:4411–4414`)** (`reject/t34`, the mirror image of
  `t30`: calling `recv` on a channel that is actually at `Send`).
- **`Chan.close(ch)` (`typecheck.ml:4426–4450`).** Requires `SEnd` exactly
  (`:4436`); on success returns `t_unit`: there is no continuation to
  advance to, `close` is the terminal op on an endpoint (and, being
  `TLin`-typed, the linear tracker still requires the channel value ITSELF
  have been produced and consumed exactly once up to this point; `close`
  simply doesn't hand back a new channel to keep threading). Wrong state:
  **`` Chan.close: channel is at `%s` but I expected `End`. `` (`:4439–4442`)**
  (`reject/t31`: closing a channel before its session has actually reached
  `SEnd`, e.g. before the matching `recv` on the peer side has run).
- **`Chan.choose(ch, :label)` (`typecheck.ml:4454–4496`).** Requires
  `SChoose branches` (`:4469`); the label argument must be an atom LITERAL
  (`Ast.EAtom`/`Ast.ELit (LitAtom _)`, `:4460–4463`; a computed/variable
  label is rejected with `` Chan.choose: label must be an atom literal (e.g.
  :ok). ``, `:4472–4473`, since branch selection must be resolvable at
  typecheck time against the protocol's fixed branch list); the label string
  is then looked up in `branches` via `List.assoc_opt` (`:4476`); a name
  that isn't one of the protocol's declared branches is **`` Chan.choose:
  label `:%s` is not a valid branch of this protocol. `` (`:4479–4481`)**
  (`reject/t32`); a valid label returns `TLin (Linear, TChan (ref cont))`
  where `cont` is THAT branch's own continuation (`:4477`), so, unlike
  `offer` below, `choose`'s result state is always exactly correct (the
  chooser statically names which branch it's taking; there is no runtime
  uncertainty to approximate). Wrong incoming state (channel not at
  `SChoose` at all): **`` Chan.choose: channel is at `%s` but I expected
  `Choose{...}`. `` (`:4485–4488`)**.
- **`Chan.offer(ch)` (`typecheck.ml:4505–4551`).** Requires `SOffer branches`
  (`:4515`); on success returns `TTuple [t_atom; cont_ty]` where `cont_ty` is
  `TLin (Linear, TChan cont_ref)`, `cont_ref` initialized to the **FIRST**
  entry in `branches` (`:4516–4535`: `match branches with (_, sty) :: _ ->
  ... | [] -> TTuple [t_atom; TError]`). The first-branch value is always just
  the STARTING point, not necessarily the final type a use site sees; see
  the F5 paragraph below for how a subsequent `match` on the label refines
  it. Wrong incoming state: **`` Chan.offer: channel is at `%s` but I
  expected `Offer{...}`. `` (`:4540–4543`)**.

**Linearity, briefly.** Every op above both CONSUMES its `ch` argument
(reading its current `session_ty` once) and, except `close`, PRODUCES a new
`TChan` value at the advanced state: the same `TLin (Linear, ...)` wrapper
from §2.7.6 travels through every step of a session. Enforcement is the
GENERIC linear-`let` tracker (the same mechanism guarding any other linear
value in March), not a session-specific accounting pass: a `let`-bound
channel continuation used twice is caught as an ordinary double-use
(`` The linear value `<x>` is used more than once here. ``, `reject/t35`,
§2.7.10) with no session-typing-specific diagnostic at all. This is also
why linear enforcement remains PARTIAL for one shape: reusing a linear
**parameter** endpoint with a session state that coincidentally still matches
after one op (rather than threading the operation's own returned
continuation) slips through, because it isn't a double-*use* of a `let`
binding in the sense the generic tracker checks. This residual is **F7**,
logged by the operational widening task (`.superpowers/sdd/sessions-survey.md`
§4 F7); cross-referenced here, not re-filed. (The SIBLING gap F7 used to
also cover (silently dropping a `let`-bound endpoint that reached `SEnd`
without a single call to `close`) is CLOSED: a `let`-bound channel is now
tracked all the way to end-of-scope and an unclosed `SEnd` continuation is
rejected. See the session-types reference's guarantees section.)

#### 2.7.9 The F5 finding: `Chan.offer`'s continuation approximation, and
its 2026-07-24 fix (Task 4)

**[CLOSED 2026-07-24, Task 4 of the session-types correctness fixes]**
`Chan.offer` (`typecheck.ml:4505`, §2.7.8) still TYPES its immediate result
as `(Atom, Chan at the FIRST branch's continuation)`; the comment directly
above the arm (`typecheck.ml:4498–4504`) still explains why: *"the exact
continuation is not known statically without dependent types, so we return
the first branch's continuation type as a conservative approximation that
still lets users write match expressions over the returned atom."* What
changed is what happens AFTER that approximate value is produced. The
`Chan.offer` arm now also registers the fresh session ref against the FULL
branch map in `env.offer_conts` (`:4525–4526`); `infer_match`
(`:5654`/`with_offer_refinement`, `:5597–5616`) checks, for every `match`
arm, whether its scrutinee is a NAME linked in `env.offer_labels` (the
label-variable ↔ session-ref binding a `let (lbl, ch) = Chan.offer(...)`
destructure installs, `:5806–5819`); if so, it transiently repoints the
shared session ref at THAT ARM's own branch continuation (looked up in
`offer_conts`'s branch map) for the duration of checking that arm's body,
then restores it afterward. So a channel bound alongside the offer label now
types at the ACTUAL branch's continuation inside a `match` arm that
discriminates on the label, not always the first branch's.

**Before this fix**, an `offer` over branches with continuations that DIFFER
(e.g. one branch continues with `Send(Int, End)`, another with `Send(String,
End)`) was mis-typed for every branch except the first: the returned
channel's static type claimed the first branch's continuation even when the
runtime atom named a different branch, and this held whether or not the
program went on to `match` the label at all. Concretely: given
```march
protocol Decision do
  choose by Client:
    ok  -> Client -> Server : Int
    err -> Client -> Server : String
  end
end
```
`Chan.offer(sc)` on the `Server` endpoint USED TO always yield a channel
typed `Chan(Server, Send(Int, End))` (the `:ok` branch's continuation). If
the peer actually chose `:err` (so the true runtime session is at
`Send(String, End)`), driving that channel directly with `Chan.send(sc2,
"text")` was WRONGLY REJECTED (the checker insisted on `Int`), and, more damaging, a
program that instead sent an `Int` was wrongly ACCEPTED even though the
peer, having chosen `:err`, was waiting to `recv` a `String`: a real
type-confusion soundness hole (interpreted, this failed dynamically at the
`recv` call; compiled, it silently reinterpreted the `String`'s heap pointer
as an `Int`, e.g. printing a garbage value like `4328203745`).

**What the fix actually closes, and the one case it intentionally still
rejects.** The `with_offer_refinement` mechanism above makes `match`ing the
label the ONLY sound way to drive an offer channel with branches that continue
differently, so the fix doesn't just make the correct branch's type
reachable, it also makes the WRONG behavior (driving the channel before
disambiguating which branch it's actually at) a hard compile error rather
than a silent guess: `offer_unrefined_error` (§2.7.8's `Chan.send`/`recv`/
`close`/`choose`/`offer` guard clauses, `typecheck.ml:4176–4186`) rejects
any of those five ops on a channel with a session ref still flagged
"unrefined" (i.e. it came from an `offer` with differing branches and has
not yet been repointed by a `match` on the paired label) with `` <op>: this
channel came from `Chan.offer`, and the protocol's branches continue
differently, so I don't know which one the peer chose. Match on the label
first — `match lbl do :ok -> ... :err -> ... end` — and use the channel
inside each arm. `` (`reject/t95`). Rebinding the label variable's name
before the `match` (`let lbl = :ok` after destructuring it from
`Chan.offer`) does not bypass this either: `bind_var`/`bind_linear`, the
binding chokepoints every `let`/lambda-param/pattern binding funnels
through, retire any stale `offer_labels` entry the moment a name is rebound,
so the shadowed name no longer resolves to the offer's real linkage
(`reject/t97`, a follow-up fix closing exactly this bypass). When every
branch continues IDENTICALLY, none of this fires: there's only one
continuation to guess, so `offer_unrefined` is never populated for that
channel in the first place, and it can be driven without a `match` exactly
as it always could. Corpus: `accept/t43` (§2.7.10) exercises the identical-
continuation case (no match needed, approximation is exact by construction);
`reject/t95_offer_unrefined_continuation` and
`reject/t97_offer_label_shadow_bypass` (`specs/lang/types/reject/`) pin the
two unrefined-use rejections (direct, and via the name-shadowing bypass);
see `specs/progress/`'s matching entry for the full witness list this fix added.
Fixing the
STATIC-typing side needed branch-indexed / dependent typing of the returned
continuation on the returned `Atom` value: that's what `with_offer_refinement`
implements; no residual soundness gap remains for this finding.

#### 2.7.10 Corpus witnesses (Task 3: per-op reject corpus + one round-trip accept)

Six new `reject/` programs (`specs/lang/types/reject/`, `t30`–`t35`), each
pinning the live message from a distinct §2.7.8 arm (`EXPECT-ERROR`
annotation is the exact grepped substring; full text is what `--check`
actually prints, verified live for this task):

- **`t30_send_at_recv_state`**: `Chan.send` called twice in a row on the
  same protocol thread (no intervening `recv`), so the second call's
  argument is at `Recv(Int, End)`, not `SSend`. Pinned: `` Chan.send: channel
  is at `Recv(Int, End)` but I expected `Send(T, ...)`. ``
- **`t31_close_before_end`**: `Chan.close` on the receive endpoint before
  its matching `Chan.recv` has run. Pinned: `` Chan.close: channel is at
  `Recv(Int, End)` but I expected `End`. ``
- **`t32_invalid_choose_label`**: `Chan.choose(cc, :maybe)` where `:maybe`
  is not one of `Decision`'s declared branches (`:ok`/`:err`). Pinned: ``
  Chan.choose: label `:maybe` is not a valid branch of this protocol. ``
- **`t33_wrong_payload_type`**: `Chan.send(cc, "not an int")` against a
  protocol declaring `Client -> Server : Int`; the ORDINARY constructor/
  type-mismatch path, not a session-specific message (§2.7.8's `Chan.send`
  bullet). Pinned: `` expected `Int` but got `String` ``.
- **`t34_recv_at_wrong_state`**: `Chan.recv(cc)` on the Client endpoint of
  `Echo` immediately after `Chan.new`, while `cc` is still at `Send(Int,
  Recv(Int, End))` (the first op must be a send, not a recv). Pinned: ``
  Chan.recv: channel is at `Send(Int, Recv(Int, End))` but I expected
  `Recv(T, ...)`. ``
- **`t35_linear_used_twice`**: `Chan.close(cc2)` called twice on the same
  `let`-bound continuation; the generic linear-`let` tracker (§2.7.8's
  linearity paragraph), not session-specific accounting. Pinned: `` The
  linear value `cc2` is used more than once here. ``

One new `accept/` program, **`accept/t43_choose_offer_roundtrip`**: a
two-branch `Decision` protocol (`ok -> Int`, `err -> String`, intentionally
TYPE-DISTINCT branches, avoiding the F4 merge-rule pitfall, §2.7.5) driven
through a full `choose`/`send`/`close` (chooser side) and `offer`/`recv`/
`close` (offerer side) round-trip. `--check` exits 0; run interpreted, prints
`:ok` then `42`, confirming the projected per-op advancement in §2.7.8
actually corresponds to a runnable protocol shape, and (per §2.7.9) that the
`Chan.offer` approximation is exact for this witness because the chooser
always picks the first-listed branch (`:ok`).

`check_types.sh`: **78/78 (43 accept, 35 reject)**, exit 0.

### 2.8 Capabilities and effects: the IO permission lattice, `needs`, and `Cap(X)` signature enforcement

March's capability system is a **compile-time-only, static** discipline: a
`Cap(X)` value proves the holder is authorized to perform IO in the family
named by `X`, but the proof is **runtime-erased**: `Cap(X)` values compile to
`null` in LLVM IR and to `VUnit` in the interpreter (no capability check has
any effect on runtime semantics or output; a cap-threading program produces
the same results, byte for byte, interpreted and compiled). All enforcement lives
entirely in `--check` (the typechecker plus two post-typecheck refinecheck
passes, out of scope for this subsection). This subsection covers the
foundational layer: the **IO permission hierarchy**, the `needs` module
manifest, **Check 1** (every `Cap(X)` in a function/actor/extern
**signature** must be covered by a declared `needs`), and (§2.8.6) the
transitive/extern-implied checks (4, 1c, 5) plus the candid three-tier
enforcement reality (signature/transitive/extern-cap = ERROR; direct-body-
call/extern-implied = WARNING). §2.8.8-§2.8.9 further extend §2.8 with
`cap_narrow`/`root_cap` threading, the effect-inference two projections, the
`*_migrate_state` IO-free check (Check 8), and realtime exclusion (Check 7).
§2.8.11 covers a SEPARATE, orthogonal mechanism sharing only the `cap`
keyword and the `Ast.DOpts` AST node: the five **behavioral module caps**
(`no_panic`/`no_alloc`/`no_extern`/`pure`/`deterministic`): per-module
syntactic bans, not IO-permission accounting. Proof-cap minting/forging
(Check 6, `mint_cap`, and the `cap_narrow` proof-cap restriction) is a THIRD,
distinct use of the `Cap(...)` infrastructure (nominal per-module unforgeable
tokens), and is treated in full in §2.8.13.

#### 2.8.1 The capability hierarchy: 18 entries, a forest of trees

The hierarchy is a single static table, `hierarchy : (string * string option)
list` (`lib/caps/cap_lattice.ml:15-34`): each entry a dot-joined path and an
optional parent path (`None` = root). It is shared, as the single source of
truth, between `March_typecheck.Typecheck` (this subsection's body-scan/
signature checks) and `March_refinecheck.Cap_infer` (the softer inference-hint
pass); both need the identical subsumption rule. The full table, exactly as
declared:

```
IO                        (root)
├── IO.Console
├── IO.FileSystem
│   ├── IO.FileRead
│   └── IO.FileWrite
├── IO.Network
│   ├── IO.NetConnect
│   │   ├── IO.Database
│   │   └── IO.NetConnect.TLS
│   └── IO.NetListen
├── IO.Process
├── IO.Clock
├── IO.Random
├── IO.Spawn
├── IO.Mut
├── IO.Telemetry
└── IO.Foreign
    └── IO.Foreign.Blocking
```

All 18 entries share the single root `IO`: this is one tree, not a forest,
despite the surface impression that `IO.Console`/`IO.Process`/`IO.Clock`/
`IO.Random`/`IO.Spawn`/`IO.Mut`/`IO.Telemetry` are "leaves with no interesting
structure": every one of them still has `Some "IO"` as its parent, so
`needs IO` covers all eighteen. The two three-level branches are
`IO.FileSystem → {IO.FileRead, IO.FileWrite}` and `IO.Network →
{IO.NetConnect → {IO.Database, IO.NetConnect.TLS}, IO.NetListen}` — `IO.
Database` and `IO.NetConnect.TLS` are the only entries nested three deep.

**FFI caps are explicitly outside this table.** The comment at
`cap_lattice.ml:5-6` notes: "FFI caps like `LibC` are valid but not in this
table — they are their own roots and have no subtyping relationship." An FFI
capability name is checked for exact/self-subsumption only (see Check 5,
deferred to a later task); it never subsumes or is subsumed by anything in
the `IO` tree.

#### 2.8.2 Subsumption: `cap_subsumes` and `normalize`

Two pure list-walking functions define the ordering (`cap_lattice.ml:39-59`):

```ocaml
let cap_ancestors cap =
  let rec go c acc =
    let acc' = c :: acc in
    match List.assoc_opt c hierarchy with
    | Some (Some parent) -> go parent acc'
    | _ -> acc'
  in
  List.rev (go cap [])

let cap_subsumes parent child =
  List.mem parent (cap_ancestors child)

let normalize caps =
  List.filter (fun c ->
    not (List.exists (fun other -> other <> c && cap_subsumes other c) caps)
  ) caps
```

`cap_ancestors cap` returns `cap` itself plus every ancestor up to (and
including) the root, most-specific first, e.g. `cap_ancestors "IO.FileRead" =
["IO.FileRead"; "IO.FileSystem"; "IO"]`. A name absent from the table (an FFI
cap) returns just itself, the base case of `go`'s `match … | _ -> acc'` arm.

`cap_subsumes parent child` is then simply "is `parent` among `child`'s
ancestors (or `child` itself)": **reflexive** (`cap_subsumes X X` is always
true, since `cap_ancestors X` always starts with `X`) and **directional**: a
broader declared cap covers a narrower used one, never the reverse.
`cap_subsumes "IO" "IO.FileRead"` is true; `cap_subsumes "IO.FileRead" "IO"`
is false: a child capability does not grant its own parent. Two siblings
(e.g. `IO.FileRead` and `IO.FileWrite`) never subsume each other, since
neither appears in the other's ancestor chain.

`normalize caps` drops any cap in the list that is subsumed by another cap
already present, preserving relative order of the survivors, e.g.
`normalize ["IO"; "IO.FileRead"] = ["IO"]` (the broader cap absorbs the
narrower) regardless of which order they were declared in. `check_module_needs`
(§2.8.3) uses `normalize` when merging declared `needs` lists and accumulated
per-function cap closures; a code comment at `typecheck.ml:5438` notes the
merge is commutative: "merge order across the three call sites doesn't
matter."

**Typechecker alias.** `typecheck.ml:1116` re-exports the shared function
directly: `let cap_subsumes = March_caps.Cap_lattice.cap_subsumes`. Every
subsumption check in `check_module_needs` (Check 1 included) calls this one
alias; there is no separate, possibly-divergent copy of the ordering logic in
`typecheck.ml` itself.

#### 2.8.3 The `needs` manifest and `Cap(X)` signatures

A module declares which IO capability families it uses via a `needs`
statement: one or more dotted paths, each on (conventionally) its own line:

```march
mod Server do
  needs IO.Network

  fn listen(cap : Cap(IO.Network), port : Int) : Int do
    ...
  end
end
```

**AST and lexer.** `needs` parses to `Ast.DNeeds of name list list * span`
(`lib/ast/ast.ml:159`), **not** `DCapNeeds`; each element of the outer list is
one dotted path already split into its component names (so `needs IO.Network`
parses to a `DNeeds` entry `["IO"; "Network"]`, rejoined by
`cap_path_of_names` back into the dotted string `"IO.Network"` for hierarchy
lookups). The lexer recognizes the keyword directly: `("needs", NEEDS)`
(`lib/lexer/lexer.mll:50`). A module may write multiple `needs` lines, one per
capability family (as accept/t47, §2.8.5, does for two independent siblings);
`DNeeds` is collected per-declaration, not merged into one statement.

**`Cap(X)` is an ordinary parametric type**, `Cap` a built-in type constructor
of arity 1 (`builtin_types`, `typecheck.ml:1862`: `("Pid", 1); ("Cap", 1);
...`). Its argument is a **dotted type name** resolved as a single string, not
a nested type application: `Ast.TyCon (con, [arg]) when con.txt = "Cap"` then
`match arg with Ast.TyCon (name, []) -> [name.txt]` (`cap_paths_in_surface_ty`,
`typecheck.ml:1123-1138`, the helper that extracts every `Cap(X)` path
occurring anywhere in a surface type, walking through `TyArrow`/`TyTuple`/
`TyRecord`/`TyLinear`, and explicitly skipping `Tagged(X, T)`'s argument so a
realtime tag is never misread as a capability reference, `:1129-1130`). So
`Cap(IO.Network)` is parsed as `TyCon("Cap", [TyCon("IO.Network", [])])`: the
dotted string `"IO.Network"` is the type name in its own right, not a
qualified reference into a module named `IO`.

**Scoping finding: not every hierarchy entry is a valid `Cap(X)` argument
today.** `cap_paths_in_surface_ty` only extracts a path if it persists
`surface_ty`'s ordinary type-name resolution (`Ast.TyCon(name, [])` must
resolve to *some* registered 0-arity type before a `Cap(X)` reference
typechecks at all). Live probing shows only **10 of the 18** hierarchy
entries are pre-registered as valid type names for this purpose; the
`builtin_types` table (`typecheck.ml:1871-1874`) lists exactly: `IO`,
`IO.Console`, `IO.FileSystem`, `IO.FileRead`, `IO.FileWrite`, `IO.Network`,
`IO.NetConnect`, `IO.NetListen`, `IO.Process`, `IO.Clock`. The other 8 (
`IO.Random`, `IO.Database`, `IO.Spawn`, `IO.Mut`, `IO.Telemetry`,
`IO.Foreign`, `IO.Foreign.Blocking`, `IO.NetConnect.TLS`) are valid
`needs` targets (an all-string manifest, so `needs IO.Random` by itself
typechecks fine) but **cannot be written as a `Cap(X)` type annotation**:
`fn f(c : Cap(IO.Random)) : Int do 1 end` rejects with `` Unknown module `IO`.
Did you mean `Dir`? ``: `surface_ty`'s qualified-type fallback
(`resolve_qualified_type`, `typecheck.ml:742-750`) attempts to load an actual
module named `IO` (`stdlib/io.march`, which declares no types), fails to
resolve `IO.Random` as one of its exported types, and falls through to the
generic qualified-name-not-found diagnostic. This is a real, narrow gap
(worth widening `builtin_types` in a future compiler-fix task) but is out of
scope for this docs-only slice; the corpus below (§2.8.5) draws only from
the 10 names that are valid `Cap(X)` arguments today.

**Check 1** (`typecheck.ml:5578-5607`, comment "Check 1:" at `:5578`) is the
core enforcement rule this subsection pins:

> Every `Cap(X)` occurring in a function, actor-handler, or extern
> **signature** (param or return type) must be covered (via `cap_subsumes`)
> by at least one of the module's declared `needs` paths. If not, this is
> an **ERROR**.
>
> Check 1b (a body-scanned direct builtin call) is **also an ERROR** as of
> 2026-08-06; it was warning-only before, and the parenthetical here said so.
> Check 1c (an `extern` block implying `IO.Foreign`) remains warning-only and
> was intentionally not flipped.

The set of signature-occurring `Cap(X)` paths (`used_caps`,
`typecheck.ml:5468-5515`) is collected from three declaration shapes:

- **`DFn`**: every named parameter's declared type plus the return type
  (`param_tys @ ret_tys`, `:5450-5456`), scanned via `cap_paths_in_surface_ty`.
- **`DActor`**: every handler's declared parameter types (`:5483-5488`);
  actor message handlers can receive `Cap(X)` values as message arguments, and
  those are held to the same signature standard as an ordinary function's
  parameters.
- **`DExtern`**: the block's own `ext_cap_ty` (`:5492-5493`; enforced fully
  by Check 5, a later task, but the use is recorded here too so Check 2's
  "declared but unused" check doesn't misfire against an extern-implied use).

For each collected `(cap_path, span)`, Check 1 (`:5561-5587`) computes
`covered = List.exists (fun need -> cap_subsumes need cap_path) declared_needs`
and, if not covered (and the cap is not a *self-declared proof capability*;
proof caps are a later task's subject), raises an error at the signature's
span. The exact message (captured live, `--check` on a `Cap(IO.Network)`
param with no `needs` anywhere):

```
`Cap(IO.Network)` used in module `Server` but `IO.Network` is not declared in `needs`.
help: add `needs IO.Network` to the module body.
```

Subsumption means the covering `needs` need not be an exact match: declaring
the **root** `needs IO` covers *every* descendant `Cap(X)` in the signature
sense: `cap_subsumes "IO" "IO.Network"` is true because `"IO.Network"`'s
ancestor chain (§2.8.2) includes `"IO"`. The same applies one tier down: `needs
IO.Network` covers `Cap(IO.NetConnect)` (its direct child), without covering
`Cap(IO.NetListen)` (`IO.NetConnect`'s sibling); subsumption only travels
*up* the tree, never sideways. Two siblings never cover each other regardless
of tier: a module using both `Cap(IO.FileRead)` and `Cap(IO.FileWrite)` must
declare **both** `needs IO.FileRead` and `needs IO.FileWrite` (or the shared
ancestor `needs IO.FileSystem`/`needs IO`); one sibling's `needs` leaves the
other's `Cap(X)` uncovered, and Check 1 raises independently per used path
(`used_caps` is traversed with `List.iter`, one diagnostic per uncovered entry,
not a single aggregate check).

**Directionality is not symmetric**, and this is worth stating clearly because
it is the opposite of what "narrower requirement, broader capability" might
suggest: a module declaring the **narrow** `needs IO.Network` does **not**
cover a signature using the **broad** `Cap(IO)`: `cap_subsumes "IO.Network"
"IO"` is false (a child capability never subsumes its own parent). This
combination also triggers **Check 3** (`:5652`, out of this subsection's
scope in detail, deferred to a later task): a HINT suggesting the function
narrow its `Cap(IO)` root parameter to a specific sub-capability for
least-privilege, emitted *in addition to* Check 1's ERROR, not instead of
it; the HINT does not change the exit code.

#### 2.8.4 Worked example: the compiler's own demo

`examples/capabilities.march` is a runnable illustration of the same rule:
`CapDemo` declares `needs IO` once at module level, then every IO-touching
function (`greet : Cap(IO.Console) -> String -> Unit`, `simulate_fetch :
Cap(IO.Network) -> String -> String`) takes its own narrower `Cap(X)`
parameter, each covered by the single root `needs IO` via subsumption
(§2.8.2), rather than one `needs` line per sub-capability. `cap_narrow(cap)`
(§2.8.8) attenuates the ambient `root_cap : Cap(IO)` down to each narrower
type before it is threaded to `greet`/`simulate_fetch`, demonstrating that
the least-privilege *pattern* (pass the narrowest cap a callee's signature
actually declares) is a caller-side convention layered on top of Check 1's
coarser "declared `needs` covers everything used" guarantee; Check 1 does
not by itself force a caller to narrow before passing a cap onward.

#### 2.8.5 Corpus witnesses (Task 1: signature enforcement + subsumption)

Four new `accept/` programs (`specs/lang/types/accept/`, `t45`-`t48`) and
three new `reject/` programs (`t36`-`t38`), each verified live against
`--check`:

- **`t45_cap_bare_covered`**: `Cap(IO.Console)` param in a module declaring
  exactly `needs IO.Console`; `cap_subsumes IO.Console IO.Console` returns true
  reflexively. `--check` exit 0.
- **`t46_cap_broad_needs_covers_narrow`**: `Cap(IO.Network)` param covered by
  the **root** `needs IO`; the canonical subsumption shape (§2.8.3). `--check`
  exit 0.
- **`t47_cap_sibling_independence`**: `Cap(IO.FileRead)` and
  `Cap(IO.FileWrite)` (siblings under `IO.FileSystem`, §2.8.1) each covered by
  its *own* `needs` line; proves Check 1 walks each used `Cap(X)`
  independently, with no cross-sibling subsumption. `--check` exit 0.
- **`t48_cap_midtier_subsumption`**: a second, independent subsumption shape:
  `Cap(IO.NetConnect)` covered by `needs IO.Network` (`IO.NetConnect`'s direct
  parent), one tier down from `t46`'s root-covers-all case, proving
  subsumption applies at every tier of the tree, not only from the root.
  `--check` exit 0.
- **`t36_cap_sig_uncovered`**: `Cap(IO.Network)` param, no `needs` declared
  at all; `declared_needs = []` covers no cap. Pinned: `` is not declared in
  `needs` ``.
- **`t37_cap_narrow_does_not_cover_broad`**: module declares the narrow
  `needs IO.Network`; the signature uses the root `Cap(IO)`. Directionality
  (§2.8.3): a child never covers its parent. Also emits the Check 3 narrowing
  HINT ahead of the ERROR (both present in the same `--check` output; the
  pinned substring is the ERROR text). Pinned: `` `Cap(IO)` used in module
  `Server` but `IO` is not declared in `needs` ``.
- **`t38_cap_sibling_does_not_cover_sibling`**: module declares only `needs
  IO.FileRead`; a second function's signature uses `Cap(IO.FileWrite)` (its
  sibling). Companion to `t47`, which declares both siblings and accepts.
  Pinned: `` `Cap(IO.FileWrite)` used in module `Store` but `IO.FileWrite` is
  not declared in `needs` ``.

`check_types.sh` (Task 1 running total, superseded below): 86/86 (48 accept,
38 reject), exit 0.

#### 2.8.6 Transitive `use` and extern-implied caps (Checks 4, 1c, 5), and the candid three-tier enforcement reality

Check 1 (§2.8.3) is only the *first* of three truly error-level cap
checks. `check_module_needs` also enforces two more shapes at ERROR severity,
plus two shapes at WARNING-only severity that are frequently mistaken for
errors because the tutorial-level docs describe them loosely. This
subsection pins all four, and states the three-tier reality clearly because
it is the single most consequential fact for anyone relying on `needs` as a
soundness guarantee.

**Check 4: transitive `use` coverage (ERROR).** A module that `use`s another
module inherits an obligation to cover whatever capabilities the *used*
module itself declared via its own `needs`. Live cite, `typecheck.ml:5681-5703`
(comment "Check 4:" at `:5681`):

```ocaml
List.iter (function
  | Ast.DUse (ud, sp) ->
    let imported = String.concat "." (List.map (fun n -> n.Ast.txt) ud.use_path) in
    (match List.assoc_opt imported env.module_caps with
     | None | Some [] -> ()
     | Some req_caps ->
       List.iter (fun req_cap ->
         let covered =
           List.exists (fun need -> cap_subsumes need req_cap) declared_needs
         in
         if not covered then
           Err.error env.errors ~span:sp (* "module `Main` imports `Vault` which
             requires `Cap(IO.Mut)`, but `IO.Mut` is not declared in `needs`." *)
       ) req_caps)
  | _ -> ()
) decls;
```

`env.module_caps : (string * string list) list` is an association list of
`(module_name, that_module's_declared_needs)`, appended to every time a
nested `DMod` finishes checking (`(name.txt, inner_needs) :: env'.module_caps`,
`typecheck.ml:7081`). Check 4 looks up the imported module's name in this
list and, for every capability the *used* module required, checks the
*using* module's own `declared_needs` covers it via the same `cap_subsumes`
subsumption Check 1 uses, so all of §2.8.2's directionality rules (broad
covers narrow, siblings don't cover each other) apply identically here, one
hop through a `use` edge. This is a real, **error-level** propagation: an
importer cannot silently absorb an imported module's IO obligations by
omission. Live witness: `stdlib/vault.march:26` declares `needs IO.Mut`; a
module that `use`s `Vault` without declaring `needs IO.Mut` itself is
rejected:

```
module `Main` imports `Vault` which requires `Cap(IO.Mut)`, but `IO.Mut` is not declared in `needs`.
help: add `needs IO.Mut` to the module body.
```

Declaring `needs IO.Mut` (or any ancestor, e.g. the root `needs IO`) in the
importer satisfies Check 4 (`accept/t49`, §2.8.7); omitting it rejects
(`reject/t39`, §2.8.7).

**Check 5: extern `Cap(X)` must be in `needs` (ERROR).** An `extern "lib" :
Cap(X) do ... end` block (`ext_cap_ty`, `ast.ml:339`) names a capability the
FFI surface itself requires. Check 5 (`typecheck.ml:5704-5723`, comment
"Check 5:" at `:5704`) is the same shape as Check 1, applied to
`DExtern` instead of `DFn`/`DActor`:

```ocaml
List.iter (function
  | Ast.DExtern (edef, sp) ->
    let cap_paths = cap_paths_in_surface_ty edef.ext_cap_ty in
    List.iter (fun cap_path ->
      let covered =
        List.exists (fun need -> cap_subsumes need cap_path) declared_needs
      in
      if not covered then
        Err.error env.errors ~span:sp (* "extern block `\"libc\"` uses
          `Cap(IO.FileSystem)`, but `IO.FileSystem` is not declared in
          `needs`." *)
    ) cap_paths
  | _ -> ()
) decls;
```

This is an ERROR, not a warning: the extern block's own declared `Cap(X)`
must be covered by `needs` exactly as a function signature's `Cap(X)` must
be (§2.8.3). `accept/t50` (§2.8.7) declares `needs IO.FileSystem` covering an
`extern "libc" : Cap(IO.FileSystem)` block and accepts.

**Check 1c: extern blocks imply `IO.Foreign` (WARNING only).** Distinct
from Check 5's ERROR on the extern's *own declared* `Cap(X)`, Check 1c
(`typecheck.ml:5627-5642`, comment "Check 1c:" at `:5627`) additionally treats
*every* extern block, regardless of what `Cap(X)` it declares, as implying
`IO.Foreign` (an FFI call is inherently foreign-code execution); and, per
the extern-implied-caps computation feeding this check
(`typecheck.ml:5559-5570`), `IO.Foreign.Blocking` too if any of the block's
functions are marked blocking. Unlike Check 5, an uncovered `IO.Foreign`
implication is only a **WARNING**:

```ocaml
List.iter (fun (cap_path, sp) ->
  let covered = List.exists (fun need -> cap_subsumes need cap_path) declared_needs in
  if not covered then
    Err.warning_with_fix env.errors ~span:sp
      ~fix:(Err.FInsert { after_line = ...; text = "  needs " ^ cap_path })
      (* "extern block in `Bindings` requires `Cap(IO.Foreign)` but `Bindings`
         does not declare `needs IO.Foreign`." *)
) extern_cap_uses;
```

So a single `extern` block imposes **two independent capability obligations
of two different severities**: its own declared `Cap(X)` is ERROR-enforced
(Check 5), while the blanket `IO.Foreign` implication is WARNING-only (Check
1c). `accept/t50` declares both `needs IO.Foreign` and `needs IO.FileSystem`
so neither fires; dropping only the `IO.Foreign` line would still `--check`
exit 0 (a warning, not a rejection); dropping the `IO.FileSystem` line
would exit 1 (Check 5, an error). This imbalance is easy to miss because
both obligations originate from the same `extern` block and both suggest the
identical `needs <X>` fix.

**Check 1b: body-scanned builtin calls (WARNING only), the F1 crux.** A
function *body* that calls a `builtin_cap_table` builtin (`file_read`,
`tls_connect`, `vault_set`, …, `typecheck.ml:1012-1111`) without a covering
`needs` is Check 1b (`typecheck.ml:5608-5626`, comment "Check 1b:" at
`:5608`), and it is **WARNING-only**, exactly parallel in shape to Check 1c:

```ocaml
List.iter (fun (cap_path, sp) ->
  let covered = List.exists (fun need -> cap_subsumes need cap_path) declared_needs in
  let self_declared = (* proof-cap self-declaration exemption, out of scope here *) in
  if not covered && not self_declared then
    Err.warning_with_fix env.errors ~span:sp
      ~fix:(Err.FInsert { after_line = ...; text = "  needs " ^ cap_path })
      (* "function body calls a builtin that requires `Cap(IO.FileRead)` but
         `Reader` does not declare `needs IO.FileRead`." *)
) body_cap_uses;
```

**This is the critical distinction the reference must state clearly, in
contrast to `specs/lang/capabilities.md`'s tutorial framing** (`:69` "The
compiler enforces this transitively... the build fails"; `:142`/`:312`
describe the body-call case as a "hint"/"warning" correctly labeled in the
example text, but the surrounding prose, "There are no false positives"
(`:142` area) and "the type checker already enforces `needs` as an error"
(`:312`), overstates what actually happens). The truth, reproduced live
side by side:

```
=== signature Cap(IO.FileRead), no needs (Check 1, ERROR) ===
`Cap(IO.FileRead)` used in module `Reader` but `IO.FileRead` is not declared in `needs`.
help: add `needs IO.FileRead` to the module body.
EXIT=1

=== body call to file_read, no needs (Check 1b, WARNING) ===
-- HINT --
call to `file_read` requires `needs IO.FileRead` — add `needs IO.FileRead` to module `Reader`
-- WARNING --
function body calls a builtin that requires `Cap(IO.FileRead)` but `Reader` does not declare `needs IO.FileRead`.
hint: add `needs IO.FileRead` to the module body.
EXIT=0
```

So the three-tier reality is:

| Position | Check | Severity | `--check` exit on violation |
|---|---|---|---|
| `Cap(X)` in a fn/actor/extern **signature** | Check 1 | **ERROR** | 1 |
| `use`d module's declared caps uncovered | Check 4 | **ERROR** | 1 |
| extern's own declared `Cap(X)` uncovered | Check 5 | **ERROR** | 1 |
| body call to a cap-table builtin, uncovered | Check 1b | WARNING | 0 |
| extern block's blanket `IO.Foreign` implication, uncovered | Check 1c | WARNING | 0 |

"Absence of `needs` is a machine-verified guarantee of purity" (the
tutorial's framing) applies **only** for the signature/transitive/extern-cap
surface (Checks 1/4/5): a module that calls IO builtins directly in a
function body, with no `Cap(X)` anywhere in any signature, is *warned*, not
*rejected*; `--check` still exits 0. Authors who want the ERROR-level
guarantee must thread `Cap(X)` through every effectful function's signature,
not just call the builtin and rely on the warning. This gap is logged as
**F1** in `specs/todos/` (open, deferred); it is a design/enforcement
choice, not a bug in the mechanics of Checks 1/4/5 themselves, which are
sound and precise over the `builtin_cap_table` domain (§2.8.3's F6 scoping
note is a separate, narrower gap about which hierarchy entries can even be
*written* as `Cap(X)`).

#### 2.8.7 Corpus witnesses (Task 2: transitive `use` + extern-implied caps)

Two new `accept/` programs (`t49`-`t50`) and one new `reject/` program
(`t39`), each verified live against `--check`:

- **`t49_transitive_use_covered`**: `Main` declares `needs IO.Mut` and `use`s
  the real stdlib module `Vault` (`stdlib/vault.march:26`, `needs IO.Mut`).
  Check 4 walks `Main`'s single `DUse`, finds `Vault`'s declared cap
  (`IO.Mut`) in `env.module_caps`, and confirms it is covered by `Main`'s own
  `needs IO.Mut` (reflexive subsumption). `--check` exit 0.
- **`t50_extern_cap_and_foreign_covered`**: `Bindings` declares both `needs
  IO.Foreign` and `needs IO.FileSystem`, then an `extern "libc" :
  Cap(IO.FileSystem) do ... end` block. Check 5 confirms the extern's own
  declared `Cap(IO.FileSystem)` is covered; Check 1c confirms the blanket
  `IO.Foreign` implication is covered. Neither fires. `--check` exit 0.
- **`t39_transitive_use_missing_cap`**: companion to `t49` with the `needs
  IO.Mut` line removed: `Main` `use`s `Vault` but declares no `needs` at all,
  so `declared_needs = []` covers no cap and Check 4 raises. Pinned: ``
  module `Main` imports `Vault` which requires `Cap(IO.Mut)`, but `IO.Mut` is
  not declared in `needs` ``.

`check_types.sh`: **89/89 (50 accept, 39 reject)**, exit 0.

#### 2.8.8 `cap_narrow` / `root_cap`: compile-time capability threading

Two builtins power the least-privilege *pattern* §2.8.4 already gestured at
(`cap_narrow(cap)`, deferred there to "a later §2.8 extension"; this is that
extension). Both are entries in the ordinary builtin-type table, not special
forms:

```ocaml
("root_cap",   Mono (TCon ("Cap", [TCon ("IO", [])])));
("cap_narrow", poly1 (fun a -> TArrow (TCon ("Cap", [TCon ("IO", [])]), TCon ("Cap", [a]))));
```

(`typecheck.ml:1470-1471`.)

- **`root_cap : Cap(IO)`** is a *value*, not a function call: the ambient
  root IO capability, conventionally read once near a program's entry point
  (`let cap = root_cap`, as `examples/capabilities.march`'s `main` does) and
  threaded downward from there. There is no other way to conjure a `Cap(IO)`
  value out of thin air; every other `Cap(X)` in a program must ultimately
  originate from `root_cap` (directly or through a chain of `cap_narrow`
  calls and ordinary parameter-passing) or from a proof-cap mint (a separate
  mechanism: `mint_cap` gated to the declaring module's public fns, §2.8.13).
- **`cap_narrow : Cap(IO) -> Cap(a)`** takes the root capability and returns a
  value at a **polymorphic** result type `Cap(a)`: the type-application site
  (a `let`/parameter annotation, or the callee's declared parameter type)
  determines which concrete `Cap(X)` the call instantiates to. This
  polymorphic return is an intentional design choice for the *narrowing* use
  case documented here: `cap_narrow(root)` called where a `Cap(IO.Network)`
  is expected instantiates `a := IO.Network`; called where a
  `Cap(IO.Console)` is expected, the very same call instantiates
  `a := IO.Console`; the very same call instantiates `a := IO.Console`. This
  polymorphic result is confined to IO-lattice narrowing: as of the proof-cap
  slice (2026-07-08), **`cap_narrow`'s result can never be a nominal proof cap
  in any position** (`(Cap-NoNarrowForge)`, §2.8.13). Proof caps are created only
  by the dedicated, gated `mint_cap` primitive; the earlier reality that
  `cap_narrow(some_cap) : Cap(Db.Migrated)` could mint a proof cap to satisfy
  Check 6 (the "proof-cap mint mismatch" finding) is now **closed** (see
  §2.8.13 for the full mint/forge/unforgeability treatment).

Both builtins are **compile-time-only and runtime-erased**, exactly like
every other `Cap(X)` value (§2.8's opening determination, §1 above in the
document): they compile to `null` in LLVM IR and to `VUnit` in the
interpreter. Threading a cap through `cap_narrow` and a chain of function
calls has **zero runtime effect**: the entire mechanism exists so the
*static* type of a value can express a narrower obligation than the value it
came from, letting Check 1 (§2.8.3) hold each callee to exactly the
capability its own signature declares, rather than forcing every callee in a
call chain to accept the same broad `Cap(IO)` its caller happened to hold.
`cap_narrow` does not change what any `needs` declaration must cover; Check
1's subsumption rule (§2.8.2) already lets a single root `needs IO` cover
every narrower `Cap(X)` a module's functions use; narrowing is a *caller-side
typing convention* layered on top of that coarser guarantee, not a separate
enforcement mechanism. A module can freely call `cap_narrow` any number of
times against the same `root_cap`/`Cap(IO)` value; each call is independent
and side-effect-free (both dynamically, since it is erased, and statically,
since it does not consume or mutate the argument in any linear sense; `Cap(X)`
is an ordinary unrestricted type).

#### 2.8.9 Effect inference's two projections, and Checks 7/8

**The two projections.** `check_module_needs` tracks, per fully-qualified
function name, two related but distinct sets via `record_fn_caps`
(`typecheck.ml:5455-5467`):

```ocaml
let module_wide_caps : string list =
  (* Caps that apply to every function in this module regardless of which
     function's own signature/body/extern-block produced them: declared
     [needs] ... and caps propagated in from imported modules (Check 4). *)
  declared_needs @ propagated
in
let record_fn_caps (fn_qname : string) (own_caps : string list) =
  let prior = Option.value ~default:[] (Hashtbl.find_opt env.cap_closures fn_qname) in
  let merged = March_caps.Cap_lattice.normalize (module_wide_caps @ own_caps @ prior) in
  Hashtbl.replace env.cap_closures fn_qname merged;
  (* Parallel own-caps-only projection ... WITHOUT folding in
     [module_wide_caps]. This is what the migrate_state IO-free check
     needs — the merged closure would falsely blame a pure migrate_state
     for its module's handler-level [needs]. *)
  let prior_own = Option.value ~default:[] (Hashtbl.find_opt env.own_cap_closures fn_qname) in
  let merged_own = March_caps.Cap_lattice.normalize (own_caps @ prior_own) in
  Hashtbl.replace env.own_cap_closures fn_qname merged_own
```

(`typecheck.ml:5441-5467`, `module_wide_caps` at `:5441`, `record_fn_caps` at
`:5455`.) `record_fn_caps` is called once per function from each of three
sites that already walk the module's declarations for other reasons:
`used_caps` (signature `Cap(X)` scan, §2.8.3), `body_cap_uses` (Check 1b's
builtin body-scan, §2.8.6), and the extern-implied-caps computation (Check
1c), passing in only that site's own contribution (`own_caps`); the
function's `merged`/`merged_own` accumulate across all three call sites
(a comment at `:5419` notes the merge order across sites doesn't matter,
since `normalize` (§2.8.2) is idempotent and commutative over set union).

- **`cap_closures` (the merged/exported projection)**: `module_wide_caps @
  own_caps`, i.e. *every* declared `needs` and propagated `use`-cap of the
  enclosing module, folded into *every* function's entry regardless of what
  that individual function's own signature/body/extern touches. This is the
  projection intended for the hot-deploy capability-manifest consumer (the
  design comment's stated purpose, `typecheck.ml:5429-5432`), a
  conservative, whole-module-obligation view.
- **`own_cap_closures` (the own-caps-only projection)**: just `own_caps`,
  with `module_wide_caps` intentionally excluded. A function that itself
  touches no `Cap(X)` signature, no cap-table builtin call, and no extern
  block gets an **empty** entry here, even inside a module that declares
  `needs IO` for its other functions' sake.

**Why the distinction matters: the F-caveat.** A source comment at
`typecheck.ml:5462` ("would falsely blame a pure function") flags exactly the
risk the second projection exists to avoid: if migrate_state IO-freedom
(Check 8, below) were checked against the *merged* `cap_closures`, a
completely pure `*_migrate_state` function living in a `needs IO` module (as
`actor` modules with IO-touching handlers commonly are) would be wrongly
rejected for capabilities it never itself uses, purely because its module
declares them for its *other* functions. Using `own_cap_closures` instead
means Check 8 sees only what the migrate function's own signature, body,
or extern-ness actually contributes. This is verified sound *and* precise for
this one consumer (§2.8.9's corpus witnesses below, and the survey's P8c/P8d
probes): a pure migrate_state in a `needs IO` module accepts (`accept/t53`);
a migrate_state that itself calls an IO builtin is still caught (`reject/t40`).
The IO-cap *inference* itself is sound over the `builtin_cap_table` domain:
it never fails to attribute a table-listed builtin to the function that
calls it; where it can still be incomplete is orthogonal to this
own-vs-merged distinction (an effect reached only through a `Cap(X)` never
declared as a type argument, §2.8.3's F6, or a builtin outside
`builtin_cap_table` entirely).

**Check 8: `*_migrate_state` must be IO-free (ERROR).** A hot-reload
state-migration function is recognized purely by a **name-suffix
convention**: any top-level `fn`/extern-fn with a name that ends in
`_migrate_state`, checked by a small local predicate kept as an exact copy of
its TIR counterpart (`is_migrate_fn_name`, `typecheck.ml:5388-5400`, "a local
copy of `March_tir.Tir_names.is_migrate_fn_name`", duplicated because
`march_typecheck` cannot depend on `march_tir`, which itself depends on
`march_typecheck`):

```ocaml
let is_migrate_fn_name (fn_name : string) : bool =
  let sfx = "_migrate_state" in
  let nl = String.length fn_name and sl = String.length sfx in
  nl >= sl && String.sub fn_name (nl - sl) sl = sfx
```

A migrate_state function is an **ordinary module-level declaration**, a
sibling to any `actor` block in the same module, not a handler nested
*inside* `actor Name do ... end`. Check 8 (`typecheck.ml:5818-5854`) iterates
the module's flat `decls` list matching `Ast.DFn`/`Ast.DExtern` directly; it
never descends into `Ast.DActor`'s `actor_handlers`, so a migrate function
can never be written as an `on ... do ... end` arm, only as a plain `fn`
(or extern-fn) with a name that happens to end in the magic suffix:

```ocaml
let check_migrate_fn_io_free (qname : string) (sp : Ast.span) =
  let own_caps =
    Option.value ~default:[] (Hashtbl.find_opt env.own_cap_closures qname)
  in
  if own_caps <> [] then
    Err.error env.errors ~span:sp (* "migrate_state must be IO-free
      `<name>` calls capabilities that need `<caps>`.
      migrate_state runs during the hot-migration window, before user
      messages.
      hint: move side effects into a normal handler that runs after
      migration completes." *)
```

(`typecheck.ml:5827-5839`, `check_migrate_fn_io_free`.) The rationale (state
migration runs during the hot-reload window, ahead of any queued user
messages, so IO there (which could race the very reload replacing the code
that's running it) is unsafe by construction, not just undeclared) is in
the diagnostic text itself. Because the check consults `own_cap_closures`
(§2.8.9 above), a pure migrate function is accepted even in a `needs IO`
module (`accept/t53`); a migrate function with an own-body call to an
IO-attributed builtin (e.g. `println`, mapped to `IO.Console` in
`builtin_cap_table`) is rejected regardless of the module's `needs`
(`reject/t40`). The exact live message, captured against `reject/t40`:

```
migrate_state must be IO-free
`counter_migrate_state` calls capabilities that need `IO.Console`.
migrate_state runs during the hot-migration window, before user messages.
hint: move side effects into a normal handler that runs after migration completes.
```

**Check 7: realtime exclusion (ERROR).** A function with a signature that has a
`Tagged(_, Realtime)` parameter cannot *also* have a parameter typed
`Cap(Alloc)`, `Cap(IO)`, or `Cap(Panic)`: those three capability roots are
excluded from realtime contexts because allocation, IO, and panicking are all
unbounded-latency operations a hard-realtime deadline cannot tolerate.
`Tagged` is a built-in arity-2 type constructor (`("Tagged", 2)`,
`typecheck.ml:1866-1867`, "specialization tag constructor: phantom policy/width
tags") used here with a phantom `Realtime` tag as its second argument; Check
7's two predicates match on the AST's structure, not by any special
built-in identity:

```ocaml
let is_realtime_tagged = function
  | Ast.TyCon ({txt="Tagged";_}, [_; Ast.TyCon ({txt="Realtime";_}, [])]) -> true
  | _ -> false
in
let is_excluded_cap = function
  | Ast.TyCon ({txt="Cap";_}, [Ast.TyCon ({txt=("Alloc"|"IO"|"Panic");_}, [])]) -> true
  | _ -> false
in
```

(`typecheck.ml:5779-5786`.) For every `DFn` with a parameter list containing a
`Tagged(_, Realtime)`-typed parameter, Check 7 (`typecheck.ml:5787-5817`)
scans every OTHER parameter and raises if any is one of the three excluded
`Cap(X)` roots, at ERROR severity:

```
function `step` takes `Tagged(_, Realtime)` but also takes `Cap(IO)`.
Realtime functions cannot hold `Cap(IO)` — allocation, IO, and panic are excluded from realtime contexts.
hint: remove `Cap(IO)`
```

(Captured live against `reject/t41`.) **Scoping note: `Realtime` is not
itself pre-registered.** Unlike the `Alloc`/`Panic` roots (`builtin_types`,
`typecheck.ml:1868-1869`: `("Alloc", 0); ("Panic", 0)`, "future capability roots
excluded from realtime contexts"), there is no `("Realtime", 0)` entry in
`builtin_types`, so `Tagged(Int, Realtime)` does not resolve as a surface
type until a program declares its own nullary type named `Realtime` (an
ordinary `type Realtime = Realtime` one-constructor ADT suffices; the
`is_realtime_tagged` pattern above matches the type *name* `"Realtime"`
textually, not any distinguished built-in identity, so a user-declared
`Realtime` trips Check 7 exactly as a pre-registered one would). Both
`reject/t41` and any future accept witness for the *positive* case (a
`Tagged(_, Realtime)` function with no excluded cap parameter) must include
this one-line `type Realtime = Realtime` declaration to make the annotation
resolve at all; this is a narrow, cosmetic corpus-construction detail, not a
soundness or enforcement gap: Check 7 itself fires correctly once the type
resolves.

#### 2.8.10 Corpus witnesses (Task 3: `cap_narrow`/threading + Check 8 + Check 7)

Three new `accept/` programs (`t51`-`t53`) and two new `reject/` programs
(`t40`-`t41`), each verified live against `--check`:

- **`t51_cap_narrow_thread`**: `boot(root : Cap(IO))` calls
  `cap_narrow(root)` to obtain a `Cap(IO.Network)` value, threaded to
  `listen`'s stricter signature; both `Cap(IO)` (on `boot` itself) and
  `Cap(IO.Network)` (on `listen`) are covered by the module's single `needs
  IO` via subsumption. `--check` exit 0, confirmed stable across 40+ repeated
  live runs of the same binary and input, byte for byte. **Finding: the flaky
  narrowing HINT (capabilities, live-observed, not fixed here; logged in
  `specs/todos/`; NOT a §4.1 numbered entry, and distinct from the sessions
  linearity "F7" cross-referenced earlier in this doc):** the incidental Check
  3 narrowing HINT this
  program's `boot(root : Cap(IO))` parameter would be expected to also emit
  (the same HINT `reject/t37` emits alongside its ERROR, deterministically,
  100% of 20 repeated runs) is instead **flaky** on this two-function,
  `cap_narrow`-calling program shape: present in roughly 1 run out of 10,
  absent otherwise, with no change to the file, the binary, or the working
  directory between runs. A reduced repro (a single-function module with a
  bare unused `Cap(IO)` parameter, no `cap_narrow` call at all) recurs
  the same flakiness, so it is not specific to `cap_narrow`; the exact
  trigger was not isolated further (out of scope for this docs-only slice:
  the HINT is advisory, and the flakiness never changes `--check`'s exit
  code, so it does not affect this corpus's accept/reject correctness, only
  the reliability of one HINT's presence). Worth a dedicated investigation
  in a future task.
- **`t52_cap_narrow_multi`**: a second threading shape, `main` (no `Cap(X)`
  parameter of its own) reads `root_cap` directly and calls `cap_narrow`
  twice against it, minting a `Cap(IO.Console)` and a `Cap(IO.FileRead)` in
  the same function, each threaded to its own callee. `--check` exit 0 with
  **no diagnostics at all**, proving narrowing composes freely and that
  reading `root_cap` needs no ambient parameter.
- **`t53_migrate_pure_needs_io`**: the Check 8 caveat-mitigation ACCEPT
  witness, built against a real `actor`-bearing module (not just a bare
  `mod`, strengthening the survey's P8c probe): `Counter` declares `needs
  IO.Console` for its `actor CounterActor`'s `on Inc` handler (which calls
  `println`), and a sibling top-level `fn counter_migrate_state(old) do old
  end` — pure, and NOT nested inside the `actor` block. Check 8 consults
  `own_cap_closures`, which excludes the module's `needs`, so the pure
  migrate function is not blamed. `--check` exit 0.
- **`t40_migrate_state_does_io`**: companion to `t53` with the migrate
  function's body changed to call `println`; its own capability closure is
  now `["IO.Console"]`, non-empty, so Check 8 raises regardless of the
  module's `needs IO.Console`. Pinned: `` migrate_state must be IO-free ``.
- **`t41_realtime_excludes_cap_io`**: a user-declared `type Realtime =
  Realtime` (§2.8.9's scoping note) makes `Tagged(Int, Realtime)` resolve;
  `step`'s signature combines it with `Cap(IO)`. Pinned: `` takes `Tagged(_,
  Realtime)` but also takes `Cap(IO)` ``.

`check_types.sh`: **94/94 (53 accept, 41 reject)**, exit 0: the corpus's
total after Task 3 (see §2.8.11 below for the Task 4 total that supersedes
it).

#### 2.8.11 Behavioral module caps: `no_panic`, `no_alloc`, `no_extern`, `pure`, `deterministic`

A SEPARATE mechanism from everything else in §2.8: the **behavioral module
caps** are a per-module syntactic ban on certain call/construct shapes,
declared with a bare `cap <name>` statement at the top of a `mod` body,
**not** an IO-permission accounting device at all. They share only the `cap`
keyword and one AST constructor with the `needs`/`Cap(X)` infrastructure above:
`Ast.DOpts of string list * span` (`ast.ml:165`), a flat string-list "options"
declaration, quite unlike `DNeeds`'s per-path list-of-lists (§2.8.3). Five
dedicated lexer tokens recognize the five spellings directly, each requiring
exactly one intervening space (`lexer.mll:176-180`):

```ocaml
| "cap" [' ' '\t']+ "no_panic"      { CAP_NO_PANIC }
| "cap" [' ' '\t']+ "pure"          { CAP_PURE }
| "cap" [' ' '\t']+ "no_extern"     { CAP_NO_EXTERN }
| "cap" [' ' '\t']+ "deterministic" { CAP_DETERMINISTIC }
| "cap" [' ' '\t']+ "no_alloc"      { CAP_NO_ALLOC }
```

Four of the five (`no_panic`/`pure`/`no_extern`/`deterministic`) set a
boolean flag on the typechecking `env` inside `check_decl`'s `DOpts` arm
(`typecheck.ml:7634-7637`: `no_panic_mod`/`pure_mod`/`no_extern_mod`/
`deterministic_mod`), each consulted once, at the end of module checking, by
its own dedicated pass (`typecheck.ml:8312-8323`). **`cap no_alloc` is the
one exception**: it has no `env` field of its own at all; instead
`lib/refinecheck/no_alloc.ml`'s `check_decls` (`:72-83`) re-scans the raw
`Ast.decl list` for a `DOpts` entry containing `"no_alloc"` independently,
as its own free-standing post-typecheck refinecheck pass (parallel to
`Division_safety`, §2.8's opening paragraph): a module can be simultaneously
`cap no_panic` (an `env`-flag-driven `typecheck.ml` pass) and `cap no_alloc`
(a from-scratch AST re-scan in a different file), and the two checks never
share state.

**`cap no_panic`** (`check_no_panic_module`, `typecheck.ml:6523-6621`) bans
direct and TRANSITIVE calls to a fixed "panic surface" (three unioned name
sets (`:6408-6431`): `panic_surface_direct` (`panic`, `panic_`, `todo_`,
`unreachable_`; division/modulo are intentionally EXCLUDED from this set), per
its own comment, `:6409-6413`, so the syntactic scan doesn't double-report
what the separate Z3-backed `division_safety.ml` pass already adjudicates),
`panic_surface_prelude` (`unwrap`, `expect`, `head`, `tail`, `last`), and
`panic_surface_stdlib` (dotted names: `List.nth`, `Option.unwrap`,
`Result.unwrap`, `Array.get`, `String.slice_bytes`, …). The pass:

1. Collects every `DFn`'s call sites via `calls_in_expr` (`:6458`, the
   same walker `cap pure`/`cap deterministic` reuse below): a syntactic
   `EApp(EVar _, …)` / `EApp(EField(EVar _, _, _), …)` collector that
   recurses into blocks/let/match/if/field/pipe but has an explicit
   `| _ -> acc` fallthrough (no `ELam`/`ESpawn`/`ESend`/`ERecord` recursion),
   the same imbalance the capabilities survey's §2.1 `calls_in_expr` note
   flags for the IO-cap side; a panic call reachable only inside a lambda
   literal or record-field expression is invisible to this scan too).
2. Seeds a `panicky` set with every function with an OWN-body direct call to a
   panic-surface name (`:6512-6523`).
3. Runs a **fixpoint** (`:6525-6544`) that adds any LOCAL function (one
   declared as a `DFn` in this same module (`local_fns`, `:6503-6505`))
   calling an already-`panicky` function, iterating until no new function is
   added; this is the TRANSITIVE closure: `helper` calling `a/b` (unsafe
   division) makes `helper` panicky, and `caller` calling `helper` makes
   `caller` panicky too, even though `caller` itself never divides.
4. Reports one `Err.error` per panicky function, at the ORIGINAL call site's
   span, distinguishing `` calls `%s`, which can panic `` (direct) from
   `` transitively calls `%s`, which can panic `` (transitive); the exact
   wording the corpus below pins.

Unsafe integer division/modulo is handled by a SEPARATE pass entirely:
`March_refinecheck.Division_safety` (Z3-discharged), which raises its own
ERROR unless the divisor's declared type includes a `{v | v != 0}` or `v > 0`
(or `v >= 1`) refinement; this is why `panic_surface_direct` explicitly
excludes `/`/`%` (they are never `calls_in_expr`-collected as named calls in
the first place (division is an AST operator node), not an `EApp`). Both
passes independently gate on the SAME `no_panic_mod`/`env.no_panic_modules`
flag, so a `cap no_panic` module's unsafe division is caught even though
`check_no_panic_module` itself never inspects division at all.

**`cap no_alloc`** (`lib/refinecheck/no_alloc.ml:17-65`) is a purely
syntactic per-function-body scan for four heap-allocating expression shapes:
a non-empty `ETuple` (the empty tuple `()` is explicitly exempted, `:20`, as
with no heap cell), any `ERecord` literal, an `ECon` with one or more
arguments (a nullary constructor, `:29`, allocates no memory, since a
zero-arg ADT variant is represented as an immediate tag, not a boxed cell,
consistent with `core-march.md`'s niche-representation account of nullary
ADTs), and any `ELam` (closure literal, capturing a lambda's environment
requires a heap allocation). The scan recurses into every other expression
form (`if`/`match`/`let`/blocks/pipe/assert/sigil/`dbg`/`send`/record-update
(`:38-63`)), so an allocation nested arbitrarily deep inside control flow is
still caught, not just a top-level allocation. Unlike `cap no_panic`, there
is **no transitive closure across function calls**: `check_decls` visits
each `DFn` in the module independently (`:78-83`) and does not track which
LOCAL helper functions allocate, so a `cap no_alloc` module calling its own
allocating helper is flagged only at the definition site of the helper
itself, not additionally at each call site (contrast `cap no_panic`'s
fixpoint, which DOES propagate transitively through local calls).

**`cap pure`** (`check_pure_module`, `typecheck.ml:6645-6661`) and **`cap
deterministic`** (`check_deterministic_module`, `typecheck.ml:6710-6727`)
share one shape: each walks every `DFn`'s clauses via the identical
`calls_in_expr` collector `cap no_panic` uses, and raises an `Err.error` (NO
transitive closure: only the function with an OWN-body direct call to a
banned name is blamed, unlike `no_panic`'s fixpoint) for any call where the
callee name is a member of a `StringSet.t`, now **derived from the
authoritative `builtin_cap_table` effect map** rather than a hand-guessed
parallel list (the F2 fix, Task 5 of this widening slice; see below):

```ocaml
let is_nondeterministic_cap (cap : string) : bool =
  cap = "IO.Clock" || cap = "IO.Random"          (* typecheck.ml:6628-6629 *)

let pure_banned : StringSet.t =
  let from_table = builtin_cap_table |> List.map fst |> StringSet.of_list in
  StringSet.union from_table
    (StringSet.of_list [ "spawn"; "send"; "exit" ])
                                                   (* typecheck.ml:6637-6640 *)

let deterministic_banned : StringSet.t =
  builtin_cap_table
  |> List.filter (fun (_, cap) -> is_nondeterministic_cap cap)
  |> List.map fst
  |> StringSet.of_list
                                                   (* typecheck.ml:6700-6704 *)
```

`pure_banned` is every builtin the table attributes ANY effect cap to (all
≈90 registered builtins are effectful, by construction of the table) union
the three incidental non-table impure names `spawn`/`send`/`exit` (these
route through other mechanisms and were never in `builtin_cap_table` to
begin with). `deterministic_banned` is the strict subset the table maps to
one of the two nondeterminism-source caps, `IO.Clock`/`IO.Random`, so `cap
deterministic` stays correctly WEAKER than `cap pure`: it still permits an
ordinary, deterministic-ish `file_read`/`println`, banning only the clock
and RNG. **Before the Task 5 fix**, both sets were instead hardcoded,
hand-maintained lists that had fallen out of sync with the real builtin
surface; see the F2 write-up below for the exact before-fix lists (which named
builtins that do not exist) and the live before/after transcripts.

**Intended semantics** (both are documented, sound-sounding claims about the
module): `cap pure` promises the module's functions perform no observable
side effect at all: no IO, no spawn/send, no mutation, no randomness; `cap
deterministic` promises no dependence on wall-clock time or a random-number
source, so re-running the module with the same inputs always produces the
same outputs (a weaker claim than `pure`: a `deterministic` module MAY still
do ordinary IO, e.g. `println`, as long as it isn't reading the clock or an
RNG).

**F2, FIXED (Task 5 of this same widening slice, `specs/todos/`).** Both
banned sets used to be **hardcoded, hand-maintained name lists that were
never cross-checked against the actual builtin surface**. `pure_banned` named
`write_file`, `read_file`, `append_file`, `delete_file`, `random_int`,
`random_float`, `random_bool`, `now_ms`: **none of these exist as
builtins** (verified: zero occurrences as a `VBuiltin` registration in
`eval.ml`). The REAL effectful builtins are spelled differently: `file_write`,
`file_read`, `file_append`, `file_delete` (registered
`eval.ml:4038/4024/4050/4062`, mapped `IO.FileWrite`/`IO.FileRead` in
`builtin_cap_table`, `typecheck.ml:1018` and neighbors), `random_bytes`
(`eval.ml:4541`, `IO.Random`, `:1077`), and `unix_time_ms` (`eval.ml:4764`,
`IO.Clock`, `:1074`): `deterministic_banned` listed `now_ms` (nonexistent)
but not `unix_time_ms` (the real wall-clock builtin). Consequence,
live-verified BEFORE the fix: a `cap pure` module with a body that called
`file_write` typechecked with **exit 0**; only Check 1b's UNRELATED
body-scan HINT+WARNING fired (§2.8.6's own F1 finding; `` call to
`file_write` requires `needs IO.FileWrite` ``), never `cap pure`'s own ``
has side effects `` error:

```
$ march --check leaky_pure.march     # cap pure module calling file_write(...) — PRE-FIX transcript
-- HINT --    call to `file_write` requires `needs IO.FileWrite` ...
-- WARNING -- function body calls a builtin that requires `Cap(IO.FileWrite)` ...
$ echo $?
0
```

The same gap applied to `random_bytes` under `cap pure` and to
`unix_time_ms(())` under `cap deterministic` (both independently
live-verified before the fix). This was a real soundness hole: a `cap pure`/`cap
deterministic` module made a machine-checked claim that silently did not
hold for the most common effectful builtins in the language. **The fix**
(Task 5, landed in this same widening slice) derives both banned sets from
`builtin_cap_table` (the authoritative effect map both Check 1b and
`cap_infer.ml` already trust) instead of the hand-guessed parallel list:
`pure_banned` is now every builtin the table maps to any effect cap (all
≈90 are effectful) plus the incidental non-table names `spawn`/`send`/`exit`;
`deterministic_banned` is only the subset the table maps to a nondeterminism
cap (`IO.Clock`/`IO.Random`), via the new `is_nondeterministic_cap` helper;
so `cap deterministic` stays correctly weaker than `cap pure` (it still
permits an ordinary `file_read`). **Post-fix, live-verified:** the exact
program above now rejects:

```
$ march --check leaky_pure.march     # cap pure module calling file_write(...) — POST-FIX transcript
-- ERROR --  `write` in `mod LeakyPure` (declared `cap pure`) calls `file_write`, which has side effects.
$ echo $?
1
```

And the corresponding `random_bytes`-under-`cap-pure` /
`unix_time_ms`-under-`cap-deterministic` cases reject the same way, while a
genuinely-pure module (`accept/t54`) and a `cap deterministic` module calling
`file_read` both still accept (no over-rejection). Regression tests in
`test/test_compiler.ml` (`cap_pure_no_extern_det` group) pin both directions.
See §2.8.12 below for the REJECT corpus witnesses this fix made possible.

**F3, FIXED (Task 6 of this same widening slice, `specs/todos/`).**
`cap no_panic`'s `panic_surface_*` sets (above) cover every NAMED partial
function (`panic`, `unwrap`, `head`, `List.nth`, …) but used to miss the
single most common IMPLICIT panic surface in ML-family code: a non-exhaustive
`match`. March's non-exhaustiveness checker (`check_exhaustiveness`, §4.1
finding 9) already ran unconditionally and already computed the right
verdict; it only reported at `severity = Warning`, and
`check_no_panic_module` never consulted that verdict at all (it only traversed
named calls via `calls_in_expr`, which does not model `EMatch` coverage).
Consequence, live-verified BEFORE the fix: a `cap no_panic` module containing
a two-constructor `match` that covered only one constructor typechecked with
**exit 0**, emitting only the generic (module-agnostic)
non-exhaustiveness `-- WARNING --`; no `cap no_panic`-specific diagnostic at
all:

```
$ march --check guarded_partial.march   # cap no_panic; match h do Rood -> 1 end (Hue = Rood | Bloo) — PRE-FIX
-- WARNING -- Non-exhaustive pattern match — missing case: Bloo
$ echo $?
0
```

...and at RUNTIME (interpreted or compiled), calling `describe(Bloo)` aborted
with a "no matching clause" panic, exactly the class of failure `cap
no_panic` exists to rule out at compile time. **The fix** (Task 6) adds a
shared `env` field, `nonexhaustive_match_spans : Ast.span list ref`:
`check_exhaustiveness` now records the span of every non-exhaustive match it
finds (in addition to its existing Warning), and `check_no_panic_module`,
which runs only for `cap no_panic` modules, reads that side-table and
promotes any recorded span nested inside one of the module's own function
bodies to an ERROR. Exhaustiveness itself is not reimplemented; the fix only
plumbs the already-computed verdict to a second consumer. **Post-fix,
live-verified:** the exact program above now rejects:

```
$ march --check guarded_partial.march   # cap no_panic; match h do Rood -> 1 end — POST-FIX
-- ERROR --  `describe` in `mod Guarded` (declared `cap no_panic`) contains a non-exhaustive `match`, which panics at runtime when no clause matches.
$ echo $?
1
```

While an exhaustive `cap no_panic` match, and a PLAIN (non-`cap
no_panic`) module's non-exhaustive match, both still accept (`accept/t14`
pins the latter as a permanent regression guard: a bare non-exhaustive match
outside a `cap no_panic` module must never be promoted). See §2.8.12 below
for the REJECT corpus witness this fix made possible.

**The guarded-match gap F3 inherited, now FIXED (fix-campaign batch 3,
2026-07-07):** originally, `check_exhaustiveness` skipped its entire coverage
computation (including recording a span into `nonexhaustive_match_spans`)
whenever ANY arm of the match had a pattern guard, so a `cap no_panic`
module containing a guarded, truly non-exhaustive match was invisible to
*both* the ordinary warning and F3's error path (`--check` exited 0 with zero
diagnostics). The conservative, sound fix: for a guarded match,
`check_exhaustiveness` now computes coverage over the GUARDLESS branches ONLY
(`guardless_matrix`, `typecheck.ml:~3315`). A branch reachable only behind a
guard cannot be relied on to match, so it contributes no GUARANTEED
coverage; if the guardless branches by themselves are non-exhaustive, then when every
guard fails at runtime no arm matches and the match panics, so the span is
recorded (`nonexhaustive_match_spans`) and `check_no_panic_module` promotes it
to an ERROR exactly as for a guard-free non-exhaustive match. Crucially, the
guarded case RECORDS the span but emits **no global Warning** (guarded matches
are common in ordinary code and get no warning today; only `cap no_panic`
modules, which opt into strictness, are made stricter, so non-`cap no_panic`
behavior is unchanged). If the guardless branches ARE exhaustive (e.g. a
guarded arm followed by an unguarded catch-all), the match can never fall
through and still accepts. Live-verified: `Some(v) when v > 0 -> v; None -> 0`
(guardless arms `{None}`, non-exhaustive) in a `cap no_panic` module now
REJECTS with the same `contains a non-exhaustive \`match\`` error; adding an
unguarded `Some(v) -> …` arm makes it ACCEPT again. Witnesses:
`reject/t50_cap_no_panic_guarded_nonexhaustive`, `accept/t59_cap_no_panic_
guarded_guardless_catchall`. This was **not a regression** and **not in F3's
original scope**: F3 correctly consumed whatever verdict `check_exhaustiveness`
computed; batch 3 extended that verdict to the guarded case.

**F5 (open, cosmetic, logged in `specs/todos/`):** `println`/`print` are
registered in `builtin_cap_table` under `IO.Console` and DO count as a
capability use for Check 2's "declared-but-unused `needs`" accounting
(§2.8.6); yet a bare `println` call with no covering `needs IO.Console`
triggers **neither** Check 1b's warning **nor** the softer `cap_infer` HINT,
while an otherwise-identical `file_read` call in the same block triggers
both. This is unrelated to the F2/F3 soundness gaps above (it is a body-scan
COVERAGE gap, not a behavioral-cap enforcement gap: `println`/`print` are
not in `pure_banned`'s omission list; they ARE correctly listed there,
`:6571`, and `cap pure` DOES reject a bare `println` call, live-verified)
but worth noting here since it makes `IO.Console` the de-facto "free"
capability at the body-scan layer specifically. Low priority; not
investigated further in this docs-only task.

#### 2.8.12 Corpus witnesses (Task 4: behavioral caps, current-correct only)

Task 4 added three new `accept/` programs (`t54`-`t56`) and three new
`reject/` programs (`t42`-`t44`), each verified live against `--check` and
scoped to the behaviors that were already correct at the time: `cap
pure`/`cap deterministic` got prose (above) and an accurate accept witness
only, since the shapes that SHOULD reject (F2) still accepted then; those
witnesses shipped with the Task 5/6 fixes, described after this list:

- **`t54_cap_pure_arithmetic`**: `PureMath` (`cap pure`) declares `add`/
  `scale`, calling only each other and `+`/`*`; neither is a member of
  `pure_banned`, so `check_pure_module` flags no call. `--check` exit 0, no
  diagnostics. Chosen to remain a valid accept witness across the F2 fix
  (which rebuilds `pure_banned` from `builtin_cap_table`); plain arithmetic
  and an internal function call can never become effectful builtins, fixed
  or not.
- **`t55_cap_no_alloc_arithmetic`**: `NoAllocMath` (`cap no_alloc`) declares
  `max3` (nested `if`/`else`) and `abs_diff` (`let` + arithmetic negation);
  neither touches any of `no_alloc.ml`'s four allocating shapes. `--check`
  exit 0.
- **`t56_cap_no_extern_ok`**: `NoFFIService` (`cap no_extern`, `needs
  IO.Network`) declares one ordinary `fn ping(_cap : Cap(IO.Network), host :
  String) : Int` calling `string_length`; no `DExtern` block, no `needs
  IO.Foreign` path — neither of `check_no_extern_module`'s two raise sites
  fires. `--check` exit 0.
- **`t42_cap_no_panic_explicit_panic`**: `Guarded` (`cap no_panic`)
  declares `fn fail() : Int do panic("boom") end`; `panic` is in
  `panic_surface_direct`, matched directly (no fixpoint needed). Pinned: ``
  calls `panic`, which can panic ``.
- **`t43_cap_no_alloc_tuple`**: `NoAllocPair` (`cap no_alloc`) declares
  `fn make_pair(a, b) : (Int, Int) do (a, b) end`; the non-empty 2-tuple
  return trips `no_alloc.ml`'s `ETuple` arm. Pinned: `` tuple construction
  allocates in a `cap no_alloc` module ``.
- **`t44_cap_no_extern_extern_block`**: `NoFFI` (`cap no_extern`, `needs
  IO.FileSystem`) declares an `extern "libc" : Cap(IO.FileSystem) do ... end`
  block; `check_no_extern_module`'s `DExtern` arm raises unconditionally,
  regardless of the extern's own Check 5 obligation being separately
  satisfied (it is: `needs IO.FileSystem` covers it, so Check 5 itself does
  not additionally fire here; a WARNING-level Check 1c diagnostic about the
  missing `needs IO.Foreign` does fire alongside, but is not the pinned
  substring). Pinned: `` contains an `extern` block ``.

**Tasks 5 and 6 then added the F2/F3 fix-enabled `reject/` witnesses**,
programs that were IMPOSSIBLE to add earlier because they accepted
(incorrectly) before their respective fix landed:

- **`t45_cap_pure_file_write`** / **`t46_cap_pure_random_bytes`**:
  `LeakyPure` (`cap pure`) calling `file_write`/`random_bytes` respectively,
  each with a type-correct `Result`-returning signature so the ONLY
  rejection is the cap violation, not an incidental type mismatch. Pinned:
  `` which has side effects ``.
- **`t47_cap_deterministic_unix_time_ms`**: `DetLeak` (`cap deterministic`)
  calling `unix_time_ms(())`. Pinned: `` which is non-deterministic ``.
- **`t48_cap_no_panic_nonexhaustive_match`**: `Guarded` (`cap no_panic`)
  with a `match opt do Some(x) -> x end` over an `Option(Int)` scrutinee,
  missing the `None` case. Pinned: `` contains a non-exhaustive `match`,
  which panics at runtime ``.

Both fixes are verified live in both directions; the transcripts in the F2/F3
write-up above show the exact same program shapes rejecting post-fix having
accepted before the fix; `accept/t54`/`t55`/`t56` and `accept/t14` (a PLAIN
non-exhaustive match, outside any `cap no_panic` module) all continue to
accept post-fix, confirming neither fix over-rejects.

`check_types.sh`: **104/104 (56 accept, 48 reject)**, exit 0: the corpus's
current, final total for this widening slice (§3).

#### 2.8.13 Proof capabilities: minting, forging, and unforgeability

The subsections above cover **IO-permission** caps (`Cap(IO.Network)` and the
18-entry lattice) and the five **behavioral** module caps. Proof capabilities
are a THIRD, distinct use of the `Cap(...)` infrastructure: **nominal, per-module,
unforgeable tokens** that encode a *fact about the system*: "migrations have
run," "the request is authenticated", rather than an IO permission. A proof
cap is declared `proof cap Name` inside a `mod` (`DProofCap`,
`lib/ast/ast.ml`), registered in `env.proof_caps : (string * string) list`
(full cap path → declaring module, populated by the `DProofCap` arm of
`check_decl`), consumed as a type argument `Cap(Mod.Name)`, and demanded via
`needs Mod.Name`. Like every `Cap(X)`, a proof cap is **runtime-erased** (`null`
in LLVM, `VUnit` in the interpreter); it exists purely so the type system can
gate who may produce and consume it. §2.8's opening previously deferred these
rules ("(Check 6) remains out of scope here"); this subsection is where they
are treated, and the deferral is now discharged.

Four rules together make `Cap(P)` unforgeable. They are all enforced by
`check_module_needs` and two post-checking sweeps in `lib/typecheck/typecheck.ml`.

**`(Cap-SelfDeclare)`: Check 1's self-declaration exemption.** Check 1
(§2.8.3, `(* Check 1:` in `check_module_needs`) requires every `Cap(X)` in a
signature to be covered by a declared `needs` via subsumption. A proof cap is
NOT in the IO lattice, so no `needs` line *subsumes* it; instead, a proof
cap's own **declaring module implicitly satisfies its own `needs`**
(`self_declared = List.assoc_opt cap_path env.proof_caps = Some mod_name`, the
`(* Check 1:` arm; the same exemption repeats in the Check 1b body-scan). So
`mod Db` may write functions taking or returning `Cap(Db.P)` without a
`needs Db.P` line of its own; any OTHER module using `Cap(Db.P)` in a signature
must declare `needs Db.P`. Cited by `accept/t62` (the declaring module needs no
self-`needs`) and `accept/t63` (the external `relay` declares `needs
Db.Migrated`).

**`(Cap-Check6)`: the declared-return-type pass-through discipline.** Check 6
(`(* Check 6:` in `check_module_needs`) governs what a function may declare as
its **return type**: a `DFn` may not return a proof cap unless it either
*received that exact cap as a parameter* OR is a **public (`fn`) function of the
declaring module**. Consequences:

- A **public fn of the declaring module** is the *minting surface*: it may
  construct and return its own proof cap.
- A **`pfn` (private) function of the declaring module** faces the same
  restriction as external code: pass-through only. Diagnostic: `` private
  function `F` in `M` cannot mint `Cap(X)`. Only public functions of `M` can
  construct `Cap(X)`. `` (`reject/t57`).
- An **external module's function** may only pass a received cap through.
  Diagnostic: `` function `F` returns `Cap(X)` but `Cap(X)` is a proof
  capability declared in `M`. Only public functions of `M` can construct
  `Cap(X)`. `` (`reject/t56`).

Check 6 inspects only *declared function return types*, so by construction it
cannot see a proof cap produced in an *expression position* (an inline call
argument, a `let` binding). That gap is closed by `(Cap-NoNarrowForge)` below.

**`(Cap-Mint)`: the `mint_cap` rule.** `mint_cap(x) : Cap(P)` is the ONLY
sanctioned way to *construct* a proof cap. Its builtin scheme matches
`cap_narrow`'s (`Cap(IO) -> Cap(a)`), but a post-checking gate
(`check_mint_cap_sites`, run once after the whole compilation is checked so the
result type is fully pinned) accepts it **iff** the pinned result is `Cap(P)`
with `P` a proof cap with **declaring module == the enclosing module AND the
enclosing function is public** (`cur_fn_public`). The enclosing-fn/module
context is captured at the site (recorded in `mint_cap_sites`) because it is
unavailable at sweep time. Rules that fall out:

- A lambda body **inherits** the enclosing function's public-ness (a `mint_cap`
  in a lambda inside a public declaring fn accepts, when the cap type is pinned
  at the lambda's call site); a nested named `fn`/`mod` gets its own
  `check_fn`/`current_module` and so resets the flag naturally.
- A value that *cannot be pinned to a specific proof cap*, e.g. a
  let-generalized `fn _ -> mint_cap(cap)` that generalizes to `∀a. _ -> Cap(a)`
  is **rejected**, because a polymorphic mint could produce ANY cap (the exact
  forge vector); this is strictly sounder than accepting it.
- `mint_cap` at a NON-proof (IO) cap target is rejected: attenuating IO caps
  is `cap_narrow`'s job.
- `mint_cap` is **runtime-erased**: it has no eval/codegen semantics of its own
  and aliases `cap_narrow` for all downstream passes (interpreter `VUnit`,
  `defun.ml` `builtin_names`, `llvm_builtins.ml` reusing `march_cap_narrow`), so
  the security gate lives entirely in typecheck.

Cited by `accept/t62` (public declaring fn mints, exit 0), `reject/t56`
(external module), `reject/t57` (`pfn` in the declaring module).

**`(Cap-NoNarrowForge)`: `cap_narrow` can never produce a proof cap.**
`cap_narrow`'s type is polymorphic (`Cap(IO) -> Cap(a)`), which is exactly right
for IO-lattice narrowing (§2.8.8) but was, before this slice, also a **forge**:
at a `Cap(Db.P)`-typed call site it instantiated `a := Db.P` and created a
nominal proof cap from an ordinary `Cap(IO)`, in the very expression positions
Check 6 cannot see. The fix restricts `cap_narrow` so its result is **never a
nominal proof cap in ANY position**. Because `cap_narrow` is the only
polymorphic cap producer, this closes the forge everywhere; the enforcement is a
value restriction on the result var (`demote_to_monomorphic`, so a
`let`-generalized launder cannot slip through) plus a use-site `unify` hook
(`cap_producer_ivars`) that rejects the instant a `cap_narrow`-tagged var is
unified with a nominal proof cap `TCon(p,[])`, with the taint propagated through
calls/instantiation/factory functions (`cap_narrow_factory_fns`). The hook fires
ONLY for proof caps (IO caps are never in `env.proof_caps`), so IO narrowing,
in every position, including laundered through a polymorphic fn, is untouched.
Diagnostic: `` cap_narrow cannot produce `Cap(X)`: `Cap(X)` is a proof
capability, not an IO capability. `` (`reject/t55`). The regression guard
`accept/t61` confirms IO narrowing (`cap_narrow(cap) : Cap(IO.Network)`) still
accepts.

**The unforgeability property.** Combining the four rules: the only ways to
obtain a value of type `Cap(P)` for a proof cap `P` are

1. **receive it as a parameter and pass it through** (`(Cap-Check6)`;
   `accept/t63`), or
2. **`mint_cap` it inside a public function of `P`'s declaring module**
   (`(Cap-Mint)`; `accept/t62`).

`root_cap` and `cap_narrow` cannot conjure a `Cap(P)` (`(Cap-NoNarrowForge)`),
and, crucially, since the P0 nested-module fix (`(T-QualRef)`, §2.5.1),
**no polymorphic launder through a nested unannotated helper can erase the cap
type either** (`consume(id(cap))` with a decoupled `?a -> ?b` `id` was the
deeper exploitation; it is now caught). So a foreign module holding only an
ordinary `Cap(IO)` truly cannot forge `Cap(P)` by name, matching the
"unforgeable" guarantee `capabilities.md` documents.

**Candid residuals (documented, not hidden).**

- **Proof caps are runtime-erased.** Unforgeability is a *compile-time* property
  of well-typed programs; there is no runtime capability object, so a party that
  bypasses the typechecker (hand-written IR, FFI) is outside this guarantee, as
  for every `Cap(X)`.
- **The `cap_narrow` container-launder taint gap is still OPEN.**
  `tag_cap_producer_result` (the `(Cap-NoNarrowForge)` taint tagger) is shallow
  / non-recursive, so a `cap_narrow` result wrapped in a tuple/`Option` through a
  polymorphic factory can still forge in some shapes the simple single-module
  case happens to reject. This is distinct from the nested-module hole
  `(T-QualRef)` closes (that is about reference *resolution*; this is about taint
  *propagation* not recursing into `TTuple`/`TCon` payloads). Logged OPEN in
  `specs/todos/` (Capabilities/effects section) as a dedicated Batch-A-taint
  follow-up; a fix would recurse the tagger into container payload positions.

(Fix reports: `.superpowers/sdd/batch-a-report.md` for `mint_cap` +
`cap_narrow`, `.superpowers/sdd/prebind-fix-report.md` for `(T-QualRef)`.
Reconciles the §2.8.8 note that `cap_narrow` is "also the mechanism a proof-cap
mint uses"; that is now `mint_cap`; `cap_narrow` is explicitly forbidden from
producing proof caps.)

### 2.9 Linear and affine types (widening slice 7, 2026-07-10)

Everything in this section was live-verified against the checker on
2026-07-10 (20-probe survey; see
`specs/plans/archive/2026-07-10-widening-linear-types-plan.md` for the survey
record). Enforcement is **purely static**: the interpreter performs no
use-accounting and the compiled runtime never re-checks (see `core-march.md`
§4.12 for the operational account). All `typecheck.ml` line numbers drift;
re-grep the cited identifiers.

#### 2.9.1 Marking surfaces: (T-LinMark), (T-AlwaysLin)

A binding is registered with a linearity (`Ast.linearity = Unrestricted |
Linear | Affine`, `ast.ml:20-24`) through exactly these surfaces:

| Surface | Grammar | Effect |
|---|---|---|
| `fn f(linear x : T)` | `parser.mly:418`/`:988` (`param_lin = Linear`) | param registered Linear at `bind_fn_param` |
| `linear let x = e` | `parser.mly:1001` (+ lambda-body variant `:1117`) | binding registered Linear at the let arm |
| `linear T` / `affine T` type modifier | `parser.mly:938-939` (`TyLinear (Linear\|Affine, t)`, a `ty_atom` prefix) | the TYPE takes a `TLin` wrapper; a binding with a (post-unification) type that reprs to `TLin` is registered with that linearity (`bind_pattern_bindings`, `typecheck.ml:2858`) |
| `type R = { linear f : T, ... }` | `parser.mly:978` (`fld_lin = Linear`) | field access tracked via sentinels (§2.9.3) |
| `always_linear type H = ...` | `parser.mly:461-468` (`DAlwaysLinearType`) | **(T-AlwaysLin)** the type NAME (bare AND module-qualified) is added to `env.always_linear_types` (`DAlwaysLinearType` arm); every binding with type `TCon(name,_)` for which `resolves_always_linear name env` returns true is AUTO-PROMOTED to Linear at the let (auto_lin), fn-param, and lambda-param (`bind_lam_param`) sites. `resolves_always_linear` is NOT a flat `List.mem`: when the current module declares its own same-named type it defers to that type's own linearity (the L4 local-shadow fix, 2026-07-17), so a plain local `type Handle` is not infected by stdlib's `always_linear Handle` |

There is intentionally **no `affine let`** production and **no `affine`
param-keyword**: `affine` exists ONLY as the type modifier. Writing
`fn f(affine c : T)` is a PARSE error (`I got stuck here`), finding **L1**,
logged in `specs/todos/`; the tutorial previously showed this unparseable
form. The working spelling is `fn f(c : affine T)`.

**Return-position caveat (finding L8, OPEN):** the `TyLinear` row above applies
for BINDING-site annotations (`let x : linear T = e` registers `x` linear,
live-verified) but NOT for a callee's declared RETURN type: `fn mk() :
linear Res` followed by a plain `let h = mk()` does not register `h` (a
dropped `h` is silently accepted). The wrapper is stripped before the
call-site result type reaches `bind_pattern_bindings`; return-position
`linear` is currently decorative.

#### 2.9.2 The tracker: (T-LinUse), (T-LinDrop), (T-AffDrop)

The tracker is a list of mutable per-binding flags: `lin_entry = { le_name;
le_lin; le_used : bool ref }` in `env.lin` (`typecheck.ml:401`), pushed by
`bind_linear` (`:1005`). Note `le_used` is a has-been-used BOOLEAN, not a
count: "exactly once" is enforced as (used at least once, checked at scope
close) ∧ (a second use errors immediately).

- **(T-LinUse)**: every `EVar` reference calls `record_use` (`:2807`, call
  site `:3630`). If the entry is already used:
  - Linear: `` The linear value `x` is used more than once here. `` +
    `Linear values must be consumed exactly once — they cannot be copied or ignored.`
  - Affine: `` The affine value `x` is used more than once here. `` +
    `Affine values may be used at most once.`
- **(T-LinDrop)**: at fn-body close and at `linear let` scope close,
  `check_linear_all_consumed` (`:2891`) errors for every never-used entry
  with `le_lin = Linear`:
  `` The linear value `x` was never used. `` +
  `Linear values must be consumed exactly once, did you mean to pass it somewhere?`
- **(T-AffDrop)**: the same check FILTERS to `Linear` only: an affine value
  may be silently dropped (verified accept: an unused `c : affine T` param).

A message `send(pid, Ctor(x))` is an ordinary consuming use of `x` (the
`EVar` inside the payload triggers `record_use`); a linear value MAY be
sent to an actor, and using it again after the send is a (T-LinUse)
violation. (Witnesses: `accept/t68`, `reject/t66`. This corrects the
tutorial's former claim that linear values cannot be sent, finding **L6**.)

#### 2.9.3 Closures, match, fields: (T-LinClosure), (T-LinMatch), (T-LinField)

- **(T-LinClosure)**: `ELam` snapshots the outer `le_used` flags before
  checking the body and errors if a tracked outer linear var became used
  inside (`:4265`): `` The linear value `x` cannot be captured by a closure. ``
  (+ `A closure may be called multiple times, which would violate the
  exactly-once guarantee.`)
- **(T-LinMatch)**: matching on a tracked linear variable is itself a use
  (the scrutinee `EVar` passes through `record_use`), and pattern-bound
  variables INHERIT the scrutinee's linearity (`bind_pattern_bindings`,
  `:2858`: a `TLin`-typed binding uses the wrapper's linearity; otherwise
  bindings inherit from a linear scrutinee var). Using the original after
  the match is a (T-LinUse) violation.
- **(T-LinField)**: a `linear` record field is tracked via a phantom
  sentinel entry named `var#field`, registered when the record is
  **let-bound** (`bind_linear_field_sentinels`, call sites `:2846`/`:2882`);
  each `EField` access calls `record_use` on the sentinel (`:4409`).
  Diagnostics render the sentinel as `var.field` (`lin_display_name`,
  `:2800`). **Candid caveat (finding L3, OPEN):** fn-param-bound records get
  NO sentinel: a param's linear-field double access degrades to a WARNING
  (`` Field `f` has a linear type but linearity tracking is not available
  for `p` at this binding site. ``) and is NOT an error. Enforcement applies
  only for locally-let-bound records.

#### 2.9.4 Linearity transparency: (T-LinCoerce)

`linear T` is transparent everywhere EXCEPT the tracker:

- unification coerces `TLin` against bare types (the `TLin` arms near
  `typecheck.ml:2420`): a `linear Int` unifies with an expected `Int`;
- impl matching strips it (`impl_matches_ty`'s `TLin`/`TLin` arm):
  `linear T` matches an `impl I(T)` and vice versa; linearity is NOT part of
  type identity for impl search (§1's note on `TLin` still applies);
- constraint discharge strips it (`discharge_constraints`' `strip_lin`,
  `:5506`): `linear Int` satisfies `Num`/`Ord`/interface constraints
  exactly as `Int` does. **This third leg was MISSING until 2026-07-10**
  (finding **L2**, FIXED in this slice): an expression-position `linear Int`
  (a linear field access, or a `linear Int`-returning call, used in
  arithmetic) rejected with `` `linear Int` does not implement Num. `` before
  the tracker ran at all. Var-position `TLin` never leaked: binding sites
  strip the wrapper and store the inner type.

#### 2.9.5 Known gaps (all logged in `specs/todos/`)

- **L1**: `affine` param-keyword is a parse error (§2.9.1).
- **L3**: param-bound linear-field tracking is warning-only (§2.9.3).
- **L4**: FIXED 2026-07-17 (both parts). The linearity
  infection is closed: `always_linear`-promotion no longer keys on the BARE
  type name globally. It routes through `resolves_always_linear`
  (`typecheck.ml`), which, when the current module declares its own
  same-named type, promotes iff *that* module's own qualified type is
  `always_linear` (both bare and qualified names are registered by
  `DAlwaysLinearType`, so the qualified membership check disambiguates a plain
  local shadow from a genuinely-linear local type). So a user
  `type Handle = H(Int)` no longer inherits linearity from stdlib's
  `always_linear type Handle` (`stdlib/handle.march`); `accept/t81` witnesses
  it, and a `let h = Handle(1)` with NO local shadow still resolves to the
  stdlib linear `Handle` and correctly errors (`reject/t65`). The
  *constructor*-namespace side is ALSO closed now: constructors carry a
  `ci_module` (declaring module) and `ctors_for_type` restricts the
  exhaustiveness universe to the current module's own ctors when it declares its
  own same-named type, so `match h do H(n) -> .. end` on the user's `Handle` no
  longer warns `missing case: Handle(_)` (`accept/t82`). `ci_module` is additive
  metadata; it feeds ONLY this diagnostic, not codegen/mangling/dispatch (the
  `.ll` goldens match byte for byte), and it is the first metadata slice of the
  module-qualified constructor identity
  (`specs/plans/archive/2026-07-17-fqn-type-ctor-identity.md`, Stage 4). A real
  cross-module ctor clash where NEITHER type is local still merges (conservative,
  pending the full resolver).
- **L7**: FIXED 2026-07-10: escape analysis stack-promoted erased-repr
  (Newtype/Niche) allocs, so any non-escaping local construction consumed by
  a direct `match` read garbage compiled (the annotation in the original
  filing was a red herring; the plain form was equally broken). No longer
  promotion candidates (`escape.ml`); `g41` regression-witnesses the fixed
  direct-match shape (see `core-march.md` §4.12).
- **L8**: a `linear` qualifier on a fn RETURN type does not propagate to a
  plain `let` of the result (§2.9.1's return-position caveat);
  return-position `linear` is currently decorative.
- **F7** (session types, §2.7.8): session-channel linearity applies only for
  `let`-threaded continuations: reusing a linear PARAMETER endpoint at a
  coincidentally-matching state, and dropping an unclosed `SEnd` channel,
  both slip through. The generic tracker described here is the ONLY
  session-linearity enforcement.

#### 2.9.6 Corpus witnesses

Accept: `t64_linear_let_single_use`, `t65_linear_param_single_use`,
`t66_affine_ty_param_drop`, `t67_linear_field_arith_single` (requires the L2
fix), `t68_linear_send_consumes`. Reject (with pinned diagnostics):
`t58`–`t66` per `types/INDEX.md` (drop, double-use, match-reuse, closure
capture, let-bound field double-access, affine double-use, `always_linear`
drop, use-after-send). Pre-existing: `reject/t35` (session double-close via
the same generic tracker).

### 2.10 `let?`: Result-propagation binding (widening slice 8, 2026-07-10)

`let? p = e` binds the `Ok` payload of a `Result`-typed `e` and short-circuits
on `Err`. It is a distinct AST node, `ELetQ (p, result, body, span)`
(`ast.ml`), **typechecked NATIVELY** in `infer_expr` (`typecheck.ml:4651`),
not desugared to a `match` before typing, so the rule and its diagnostics can
speak about `let?` exactly. All line numbers drift; re-grep `ELetQ`.

The node is continuation-carrying: `body` is the *rest of the block*. The
parser (`parser.mly:1003`, `LET QUESTION simple_pattern EQUALS expr`) emits an
`ELetQ` with a placeholder empty body, and `block_body`'s fold splices each
`let?`'s continuation into its `body` field, right-associatively.

#### 2.10.1 (T-LetQ)

For `let? p = result; body` with the whole expression at type `Result(τ_r, ε)`:

```
  Γ ⊢ result : Result(τ_ok, ε)      Γ ⊢ p : τ_ok ⊣ Γ'      Γ' ⊢ body : Result(τ_r, ε)
  ────────────────────────────────────────────────────────────────────────────────────
                          Γ ⊢ (let? p = result; body) : Result(τ_r, ε)
```

- `result` must unify with `Result(τ_ok, ε)`: a fresh Ok/Err pair.
- `p` is a `simple_pattern` (var / wildcard / tuple / literal, the SAME
  patterns plain `let` accepts, so the Ok-arm bind is irrefutable), bound at
  `τ_ok` for `body`. No type annotation is permitted (§2.10.2).
- `body` (the continuation) must ALSO be a `Result`, and with the **SAME error
  type** `ε` as the RHS, because `let?` propagates that `Err` upward
  unchanged. The whole expression yields `body`'s type.

#### 2.10.2 Diagnostics

Three native errors (all live-pinned 2026-07-10; corpus in §2.10.3):

- **(E-LetQ-Last)**: a `let?` may not be the last expression in a block (its
  `body` would be empty, no value to return on Ok):
  `` `let?` cannot be the last expression in a block. `` (`typecheck.ml:4658`).
  The parser makes a trailing `let?` impossible by construction in a lambda body
  (which always ends in a real `expr`), so this fires only in `block_body`.
- **(E-LetQ-RHS)**: the RHS must be a `Result`:
  `The right-hand side of `let?` must be a Result value.` (unification reason
  at `:4671`).
- **(E-LetQ-Body)**: the continuation must be a `Result` with the same error
  type: `The code after `let?` must produce a Result with the same error
  type.` (unification reason at `:4681`).

**No type annotation.** `let? x : T = e` is rejected, but by the parser's
GENERIC missing-`=` error recovery (`` I was expecting `=` in the let? binding
here: ``, `parser.mly:1005`), NOT by a dedicated "cannot have a type
annotation" message. The `let-propagation.md` tutorial §5.2 shows a dedicated
`LET QUESTION simple_pattern COLON error` production that was never
implemented; the annotation is still correctly rejected, just with the
less-specific message. Logged and reconciled 2026-07-10 (see `specs/todos/`).

#### 2.10.3 Corpus witnesses

Accept: `t70_letq_chain_value` (a two-step chain yielding a value),
`t71_letq_tuple_pattern` (tuple `simple_pattern` on the Ok payload),
`t72_letq_wildcard` (`let? _ =`: propagate-but-discard). Reject:
`t67_letq_last_expr` (E-LetQ-Last), `t68_letq_rhs_not_result` (E-LetQ-RHS),
`t69_letq_body_not_result` (E-LetQ-Body), `t70_letq_type_annotation` (no
annotation). Operational witness + Err-short-circuit: golden `g42`
(`core-march.md` §4.13).

### 2.11 Data parallelism: no new typing rules (widening slice 9, 2026-07-10)

The data-parallel combinators (`List.pmap`/`pfilter`/`preduce` and the RRB
`Parallel` module (`pmap`/`pmap_n`/`preduce`/`preduce_n`, `psum`/`pcount`/
`pany`/`pall`)) **add no typing rules**. They are ordinary polymorphic stdlib
functions, typed by the existing application/HOF rules (§2.1). The critical
type-level fact is an *identity*:

```
  List.pmap : (List(a), a -> b) -> List(b)          -- same scheme as List.map
  Parallel.preduce : (Vec(a), b, a -> b, (b,b) -> b) -> b   -- a fold's scheme
```

`List.pmap` is interchangeable with `List.map` at the type level (so a program
comparing their results, `pmap xs f == map xs f`, is well-typed at `List(b)`).
The **associativity of `merge`** that `preduce` requires for a deterministic
result (`core-march.md` §4.14) is a *semantic* obligation, **not** enforced by
the type system: the checker accepts a non-associative `merge` of the right
type, and the resulting backend-dependence is a runtime concern (finding P1),
not a type error. Accept witness: `t73_parallel_typed_as_sequential`. The
determinism guarantee itself is operational: golden `g43`.

### 2.12 Distributed CRDTs and node identity: no new typing rules (widening slice 10, 2026-07-10)

The distributed/OTP surface (CRDT states: `GCounter`/`PNCounter`/`LWWRegister`/
`ORSet`), `VectorClock`/`ClockOrder`, `Membership`, `GlobalRegistry`,
`GlobalPid`, and the `RemoteCall` verdicts (`CallError`, `Verdict`)) is a set
of **ordinary ADTs** typed by the §2.1 constructor/`match` rules; it introduces
no new typing judgment. Two honesty notes belong in a *static-semantics*
reference:

- **Cross-node type-safety is not a static property.** A `RemoteCall.RemoteRef`
  includes a `sig_hash`/`impl_hash`; `RemoteCall.verify` accepts a call only when
  those content-addressed digests match (rejecting `TypeMismatch`/`VersionSkew`/
  `NoTarget`). This is the mechanism that keeps a remote invocation type-safe
  across a node boundary the local type-checker cannot see: it runs at
  **runtime**, not in the type system. The type system's job ends at the local
  `RemoteRef` ADT; the digest check is what a distributed program relies on.
- **The qualified-type-path limitation bites here.** Nested-module type paths
  like `CRDT.GCounter.T`, `RRB.Vec(Int)`, or `VectorClock.ClockOrder` do **not**
  resolve in a type annotation (they report "Unknown module" / wrong arity);
  the same global-type-namespace limitation noted for app types. Programs over
  this surface must lean on inference rather than annotating with qualified
  paths (both accept witnesses do).

Accept witness: `t74_crdt_identity_typed` (was typecheck-only when written;
its `VectorClock.compare` crashed *compiled* on disjoint clocks, finding C1,
FIXED 2026-07-11, `lib/tir/llvm_case.ml`'s `strip_scrut_decrc`; the `--check`
harness never ran it compiled either way). Convergence is operational:
golden `g44`, now including the disjoint-clock case unconditionally.

### 2.13 Perceus reference counting: no new typing rules (widening slice 11, 2026-07-11)

The Perceus RC discipline (`dup`/`drop` (`EIncRC`/`EDecRC`) insertion,
owned-vs-borrowed parameter classification, and functional-but-in-place
reuse (FBIP)) **adds no typing rules**. It operates entirely on **TIR**,
the already-monomorphized, already-erased intermediate form Lower/Mono/
Defun produce, several passes downstream of `typecheck.ml`. No part of the
surface type system (`Ast.ty`, the bidirectional rules of §2.1, or any
interface/capability/linearity annotation) constrains or is constrained by
RC insertion: a well-typed program's RC discipline is entirely a
*codegen* concern, not a *typing* one.

The one place representation and RC truly interact is `lib/tir/
rc_types.ml`'s two predicates, `needs_rc` and `borrow_eligible`, which
**intentionally disagree** on four constructor patterns (`TFn`/bare `TVar`:
RC yes, borrow-eligible no: closures are always Perceus-managed, never
borrow-inferred; `TTuple`/`TRecord`: RC no at the aggregate level, borrow-
eligible yes: fields are reconciled individually). This divergence is a
property of `Tir.ty` (the erased representation), not `Ast.ty`, so even
this lives downstream of typing; see `core-march.md` §4.16 for the
operational account and `specs/perceus-invariants.md` §1 for the full
fix-history-backed truth table.

### 2.14 Refinement types: erasure in `typecheck.ml`, checked by a separate pass (widening slice 12, 2026-07-11)

`{T | predicate}` and `{v : T | predicate}` (surface `Ast.TyRefine`,
internal `TRefine of ty * string * Ast.expr`) are, from `typecheck.ml`'s own
point of view, **completely transparent**: `repr (TRefine (base,_,_)) =
repr base` (`typecheck.ml:168`), so every unification, subsumption, and
inference decision in the bidirectional core (§2.1) treats a refined type
identically to its base type. A refinement annotation therefore adds **no
typing rule of its own**: it is a *proof obligation* layered on top of an
otherwise unaffected typing derivation, discharged (or not) by a wholly
separate mechanism.

```
        Γ ⊢ e : T          (ordinary bidirectional typing, §2.1, erasing {T | p})
  (T-Refine-Erase)  ──────────────────────────────────────────────────────
        Γ ⊢ e : {T | p}     ⟺     Γ ⊢ e : T     (identical derivation)
```

**The separate discharge pass (`lib/refinecheck`).** After `typecheck.ml`
finishes, an independent walk over the (already desugared) AST re-parses
`TyRefine` annotations and proves obligations against them via Z3
(`March_refine.Refine.discharge`, an Int/Bool linear-arithmetic + EUF
fragment, BLAKE3-cached under `.march/cas/vc/`). Two obligations are
checked, at two different sites:

- **(Check-Refine-Precond)**: a **direct** call `f(e)` where `f`'s
  parameter is declared `{T | p}`: the argument `e` is symbolically
  evaluated and `p[e/v]` must be verifiably true (`Verified`), else `--check`
  rejects (`Refuted`, or conservatively on `Unverified`; no Z3, or the
  fragment can't decide). Live-verified (2026-07-11): `take_n(n : {Int |
  _ >= 0})` called as `take_n(5)` accepts; `take_n(-3)` rejects with
  `refinement violation: argument does not satisfy precondition`. Witnesses:
  accept `t75_refine_precondition_satisfied`, reject
  `t71_refine_precondition_violated`.
- **(Check-Refine-Postcond)**: a function declared with a refined
  **return** type `{T | p}`: **every path through the function's own body**
  must verifiably satisfy `p`, checked once at the function's definition site,
  independent of any caller. Live-verified: a body guarded so both branches
  satisfy `_ >= 0` accepts; an unguarded branch that can return a negative
  value rejects with `` `f` does not satisfy its return type constraint on
  all code paths `` and Z3 supplies a concrete counterexample (e.g. `n =
  -1`) in the diagnostic. Witnesses: accept
  `t76_refine_postcondition_satisfied`, reject
  `t72_refine_postcondition_violated`.

**The candid scope boundary: direct calls only.** `refine_check` recognizes
a **named** direct call; it does not trace a refined function passed as a
first-class value through a higher-order call or interface dispatch.
Live-verified: `apply(take_n, -3)` (calling `take_n` indirectly through a
`HOF` parameter `f`) **accepts**, even though the identical literal at a
direct `take_n(-3)` call site is rejected (reject/t71), because
`refine_check` never associates `-3` with `take_n`'s precondition through
the indirection. This is a real, documented limitation
(`specs/lang/refinement-types.md`'s own "Limitations" section), not
unsoundness: per (T-Refine-Erase) above, no runtime check is promised
either, so an unverified call is just *unverified*, never *unsafe*.
Witness: accept `t77_refine_hof_bypass_limitation`.

**A second, specialized consumer: `cap no_panic`'s division-safety check**
(`lib/refinecheck/division_safety.ml`) reuses the identical
`Refine.discharge` infrastructure to approve `a / d` inside a `cap no_panic`
module only when `d`'s refinement verifiably excludes zero (a hybrid pass
(fast syntactic matching for common shapes like `_ != 0`/`_ > 0`, falling
back to Z3 for anything the fast path doesn't recognize). This is
*independent* of, not a special case of, (Check-Refine-Precond); it is
gated by the `cap no_panic` module annotation (§2.8.11 already covers that
capability's exhaustiveness plane; this is its refinement-discharge plane).
Live-verified: `{Int | _ != 0}` divisor accepts; `{Int | _ >= 0}` (a real
predicate that simply doesn't rule out zero) rejects with `` division by
`d` in `cap no_panic` module: refinement does not rule out zero ``.
Witnesses: accept `t78_refine_divsafety_approved`, reject
`t73_refine_divsafety_insufficient`.

**Zero runtime footprint.** Since (T-Refine-Erase) applies throughout typing
and neither backend inserts any runtime predicate check, a program that
*passes* `--check` (every obligation verifiably discharged) must run
byte-identically interpreted and compiled, the same erasure property golden
`g41` established for linear/affine annotations. Golden
`g46_refinement_erasure` witnesses this: a `clamp_nonneg`/`take_n` pair
with a postcondition and precondition that both verifiably hold, run interp vs
compiled, matching byte for byte.

## 3. Conformance corpus

`specs/lang/types/` (split by expected outcome, run by `check_types.sh`, the
type-side analog of `golden/verify.sh`):

- **`accept/*.march`**: must typecheck (`march --check` exit 0).
- **`reject/*.march`**: must be rejected (exit 1) **and** the `--check` output must
  contain the substring in the program's `-- EXPECT-ERROR: <substring>` first line.

Run: `dune build bin/main.exe && MARCH_BIN=… specs/lang/types/check_types.sh`.

| Program | Kind | Anchors | Outcome |
|---|---|---|---|
| `accept/t01_literals` | accept | T-Lit (Int/Bool/String) | typechecks |
| `accept/t02_lambda_app` | accept | T-Abs, T-App, annotated `Int -> Int` param | typechecks |
| `accept/t03_let_poly` | accept | **T-Let generalization**: a local `id = fn x -> x` used at both `Int` and `String` | typechecks (proves let-polymorphism) |
| `accept/t04_if` | accept | T-If (Bool cond, matching branches) | typechecks |
| `reject/t01_int_vs_string` | reject | unification mismatch | `expected \`Int\` but got \`String\`` |
| `reject/t02_unbound_var` | reject | T-Var, `x ∉ Γ` | `I cannot find \`undefined_var\`` |
| `reject/t03_arity` | reject | T-App arity (no partial application) | `expects 1 argument, but got 2` |
| `reject/t04_if_branch_mismatch` | reject | T-If branch unification | `Both branches of an if expression must return the same type` |
| `accept/t05_adt_construct_match` | accept | T-Con + T-Match: a 2-ctor ADT (`Hue = Rood \| Bloo`) constructed and matched exhaustively | typechecks |
| `accept/t06_payload_ctor_branch` | accept | P-Con: a payload-carrying ctor (`Circle(Int)`) bound to a pattern var in a branch | typechecks |
| `accept/t07_generic_option_two_types` | accept | T-Con/P-Con with a fresh instantiation per occurrence: a generic `Box(a) = Full(a) \| Vacant` used at both `Int` and `String` | typechecks |
| `reject/t05_ctor_arity` | reject | T-Con arity (`ECon` arm) | `` Constructor `Circle` expects 1 argument(s) but I got 2. `` |
| `reject/t06_match_branch_mismatch` | reject | T-Match branch-body unification | `All branches of a match must have the same type.` |
| `accept/t08_tuple_construct_destructure` | accept | T-Tuple + P-Tuple: a tuple built and destructured both by a `match` and by a function-arg `PatTuple` | typechecks |
| `accept/t09_record_literal_field` | accept | T-Record + T-Field: a record literal built (`{ x: 1, y: 2 }`) and both fields read via `EField` | typechecks |
| `accept/t10_record_update_existing_field` | accept | T-Update: `{ p with x: 100 }` on an existing field, result type unchanged | typechecks |
| `reject/t07_field_missing` | reject | T-Field "no such field" (`EField` arm) | `` This record does not have a field called `z`. `` |
| `reject/t08_tuple_arity_mismatch` | reject | T-Tuple/unify length mismatch, via T-App checking a `(Int,Int)`-annotated param against a 3-tuple argument | `` expected `(Int, Int)` but got `(Int, Int, Int)`. `` |
| `reject/t09_record_update_missing_field` | reject | T-Update "no such field" (`ERecordUpdate` arm, concrete-`TRecord` base) | `` This record does not have a field called `z`. `` |
| `accept/t11_atom_nullary_eq_match` | accept | T-Atom-0 + P-Atom: a nullary `:ok` returned, compared via `==`, and matched by a nullary `PatAtom` | typechecks |
| `accept/t12_atom_payload_and_name_erasure` | accept | T-Atom-N + P-Atom: a payload atom `:count(n+1)` matched with its payload bound, AND two DIFFERENT-named nullary atoms (`:red`/`:blue`) returned from the two arms of one `if`, proving name-erasure (both branches synthesize the identical `Atom`) | typechecks |
| `accept/t13_match_guard` | accept | (T-Guard): three `when`-guarded `PatVar` arms (`n when n > 0`/`n when n < 0`/`_`), guard checked against `Bool` in the pattern-extended env | typechecks |
| `accept/t14_nonexhaustive_match_still_typechecks` | accept | **(T-Match: Exhaustiveness), the brittleness witness**: a 2-ctor ADT `match` covering only ONE ctor (`Rood`, no `Bloo`, no `_`) | typechecks; `--check` exits 0 **silently** (the exhaustiveness `Warning` is computed but not rendered in `--check`; the `-- WARNING --` "missing case: Bloo" block shows only on run/compile); proves exhaustiveness is advisory, not enforced |
| `accept/t15_econd_chain` | accept | (T-Cond): a 3-arm `match do` boolean chain (`n > 0`/`n < 0`/`_`), all conditions `Bool`, all bodies `String` | typechecks |
| `reject/t10_guard_not_bool` | reject | (T-Guard) non-Bool guard (`n when n + 1 -> …`, an `Int` guard) | `Match guards must be Bool.` |
| `reject/t11_econd_condition_not_bool` | reject | (T-Cond) non-Bool condition (bare `n -> …` where `n : Int`) | `` Each condition in `match do` must be Bool. `` |
| `accept/t16_letfn_factorial` | accept | (T-LetFn): a local self-recursive `fn go(k, acc)` (factorial via an accumulator), `go` monomorphic inside its own body, called after the block | typechecks; runs to `120` for `compute(5)` |
| `accept/t17_letfn_generalized_after_block` | accept | **(T-LetFn) generalization**: a local `fn id_rec(x)` used at both `Int` and `String` in the REST of the block (after the `ELetFn`, not inside its own body) | typechecks (proves `ELetFn`'s post-body `generalize(env.level - 1, …)` fires, mirroring `t03_let_poly` for local recursive fns) |
| `reject/t12_letfn_ret_annot_conflict` | reject | (T-LetFn) declared return-type annotation (`fn go(k) : Int`) conflicts with the body's actual (self-recursion-consistent) inferred type `String` | `expected \`Int\` but got \`String\`` |
| `accept/t18_num_constraint_discharged` | accept | (δT-Add, T-Discharge): `1 + 2` (Int) and `1.0 +. 2.0` (Float, the monomorphic dotted form) both discharge/typecheck cleanly | typechecks |
| `accept/t19_eq_ord_constraint_discharged` | accept | (δT-Eq, δT-Ord, T-Discharge): `x == y` and `x < y` on two `Int`s discharge `Eq Int`/`Ord Int` against the built-in instances (§2.1b) | typechecks |
| `accept/t20_bool_ops` | accept | (δT-And, δT-Or, δT-Not): `&&`/`||`/`not` combined over `Bool`-typed comparisons (`>`/`<`/`<=`/`>=`), all monomorphic `Bool → Bool → Bool` / `Bool → Bool` | typechecks |
| `reject/t13_num_no_impl_string` | reject | (T-Discharge, `CNum`): `x + y` on two `String`s (agree with each other, so no earlier unify conflict; the `CNum` obligation itself is violated at the enclosing `fn`'s discharge point) | `String does not implement Num (only Int and Float do)` |
| `reject/t14_ord_no_impl_adt` | reject | (T-Discharge, `CInterface "Ord"`): `a < b` on a bare 2-ctor ADT (`Hue = Rood \| Bloo`, no built-in or user `impl Ord(Hue)`) | `` `Hue` does not implement interface `Ord` `` |
| `reject/t15_and_non_bool_operand` | reject | (δT-And): `1 && true`, an `Int` first operand against `&&`'s fixed `Mono Bool → Bool → Bool`, an ordinary T-App/unify rejection (no constraint infrastructure involved), decorated with the `report_mismatch` common-hint text | `March does not coerce Int to Bool` |

**Result: 35 / 35 (20 accept typecheck, 15 reject with the declared error).**

**No atom-specific `reject/` program.** Every `EAtom`/`PatAtom` occurrence,
nullary or payload-carrying, whatever the tag, synthesizes the single bare
`Atom` type (T-Atom-0/T-Atom-N, P-Atom, §2/§2.2); there is no per-tag or
per-arity typing distinction for atoms to violate, so atoms cannot originate a
type error in isolation. A payload sub-expression can still fail to typecheck
(e.g. `:count(1 + "x")`), but that failure comes from `+`'s own `Num`
constraint (δT-Add, §2.1), an ordinary unification/interface error already
covered by the existing corpus, not from anything atom-specific, so it would
not add coverage as a *new* reject program here.

## 4. Faithfulness + the key findings

The rules were transcribed arm-for-arm from `typecheck.ml` at the cited lines
(human-reviewed, not mechanically verified; the roadmap §7 faithfulness risk);
the `accept/reject` corpus is the executable anchor.

### 4.1 Known typing divergences / findings (Tasks 1–6, consolidated)

Every "the typechecker actually does X, which is easy to get wrong" discovery
made while building this reference lives HERE, in this one subsection, collected
by Task 7 from where each was originally pinned inline (Tasks 1–6). Two are
real, logged, open gaps against the current implementation (findings 15 and
16, both cross-referenced to their `specs/todos/` entry under "Compiler:
Type System"); the rest are faithful-but-surprising facts about the existing
typechecker that this document exists to pin down, not bugs:

1. **No value restriction.** `generalize` runs whenever the `let` binds a simple
   `PatVar`, regardless of whether the RHS is a syntactic value (`infer_block`
   :4318–4324). March relies on its purity/level discipline rather than the
   ML value restriction. (`t03_let_poly` is the witness.)
2. **`+`/`==` are interface-constrained polymorphic**, resolved as ordinary
   variables, not monomorphic, not parser-overloaded (§2.1).
3. **No partial application.** A call site must saturate the function (`reject/t03`
   is the witness; the error explicitly reports as much).
4. **One instantiation engine for both directions.** `instantiate_ctor`
   (typecheck.ml:2387) is called from the `ECon` arm (expression side, T-Con)
   AND from `PatCon`'s arm in `infer_pattern` (pattern side, P-Con); a
   constructor's `arg_tys → result_ty` shape (with fresh vars per type param)
   is computed exactly once per occurrence and reused for both directions, which
   is why `match`ing a freshly-constructed value type-checks without any special
   ADT-specific unification logic (`t07_generic_option_two_types` is the witness
   `Full(5)` and `Full("hi")` each get their OWN fresh `β`, exactly like
   `instantiate` for `T-Var`, §1). Non-exhaustive `match` is a WARNING
   (`check_exhaustiveness`, typecheck.ml:4288), not a typing error: it does not
   affect accept/reject in this corpus.
5. **Structural, order-independent records.** `ERecord` sorts its field list by
   name at construction (typecheck.ml:3857) and `PatRecord` does likewise
   (typecheck.ml:2679), so two `TRecord`s are compared fieldwise by plain list
   equality (`unify`'s `TRecord` case, typecheck.ml:2125–2137) rather than a
   set/row comparison: `{ y: 2, x: 1 }` and `{ x: 1, y: 2 }` are the identical
   type. There is no row-polymorphism: a record's exact field set must be known
   (or the base type is an unconstrained `TVar`, in which case field checks are
   deferred entirely (the `EField`/`ERecordUpdate` `TVar` branches, §2 above).
6. **`ERecordUpdate` rejects an absent field STATICALLY, for a concrete base
   type**: this is the type-side part of `core-march.md` §4.2.1's
   interpreter/compiled divergence adjudication. The runtime "no field ... in
   record" error the operational spec discusses is only reachable when the
   base's type is an erased `TVar` (e.g. flowing through a fully polymorphic
   stdlib builtin like `record_from_list`); for any program where the record base
   has a concrete, resolvable `TRecord` shape, a missing-field update is a
   typecheck-time rejection and never reaches eval/codegen at all
   (`reject/t09_record_update_missing_field` is the witness).
7. **No tuple/record arity error text; mismatches fall through to the generic
   unify diagnostic.** Unlike `T-Con`/`P-Con` ("Constructor `C` expects N
   argument(s)..."), a `TTuple` length mismatch has no dedicated message: the
   guarded `unify` case only fires `when List.length ts1 = List.length ts2`
   (typecheck.ml:2122), so a length mismatch instead falls to the catch-all
   `report_mismatch` and renders as a generic `expected \`(τ…)\` but got
   \`(τ…)\`.` (`reject/t08_tuple_arity_mismatch` is the witness).
8. **Atoms are fully type-erased: name AND payload both.** Unlike every other
   construct in this document, `EAtom`/`PatAtom` carry NO information into the
   type system beyond "this is an atom": `t_atom = TCon("Atom",[])` is the
   entire type, for `:ok` and `:count(1,2,3)` alike (T-Atom-0/T-Atom-N, P-Atom,
   §2/§2.2). The payload IS still typechecked on both sides: `EAtom`'s
   arguments via ordinary `infer_expr` (typecheck.ml:4050–4052) and `PatAtom`'s
   sub-patterns via ordinary `infer_pattern` (typecheck.ml:2666–2669), so a
   malformed payload expression or sub-pattern still errors; only the
   *resulting* payload type(s) are discarded rather than folded into the
   atom's own type or unified against anything. This is exactly the
   mechanism `core-march.md:1354–1359` traces as the root cause of the
   (since-fixed) compiled `Show(Atom)`/`println(:ok)` link bug: an atom
   payload binding (e.g. `msg` in `:error(msg) -> …`) gets no type from the
   atom infrastructure itself, only from how the branch body later uses it; if
   unused, it stays an unresolved type variable all the way to codegen.
   `t12_atom_payload_and_name_erasure` is the witness for the erasure itself
   (two differently-tagged nullary atoms, `:red`/`:blue`, both typecheck as
   plain `Atom` from the two arms of one `if`); no dedicated `reject/`
   program exists because there is no atom-specific way to violate this;
   every atom, by construction, already has the one type this rule assigns.
9. **Exhaustiveness and redundancy are Warnings, not typing errors, the
   single most brittle fact in this document.** `check_exhaustiveness`
   (typecheck.ml:3159–3185) and `check_redundant_arms` (typecheck.ml:3131–3155)
   both construct their diagnostics with `severity = Warning` (typecheck.ml:
   3143/3172/3179, every branch of both functions), and `--check`'s exit code
   (`bin/main.ml:819–821`, `has_user_errors`) filters strictly on `severity =
   Error`. **A `match` that does not cover every constructor of its scrutinee's
   type is WELL-TYPED: `--check` exits 0, emitting only a `-- WARNING --`
   block.** This is easy to get backwards: it is tempting to assume a
   "non-exhaustive match" program belongs in `reject/`, but doing so would
   produce a `reject/` program that this corpus's own harness (`check_types.sh`,
   §3, keyed on exit code) would immediately flag as wrong; the harness would
   see exit 0 and mark it "should be rejected but typechecked." Compounding
   this: exhaustiveness checking is SKIPPED ENTIRELY (not run at all, not even
   as a Warning) the moment ANY branch of the match has a guard
   (typecheck.ml:3161–3164, "coverage becomes undecidable"), so a guarded
   match gets no exhaustiveness signal whatsoever, Warning or Error.
   `accept/t14_nonexhaustive_match_still_typechecks` is the witness: a 2-ctor
   `Hue = Rood | Bloo` matched with only a `Rood` arm exits 0 with the exact
   message "Non-exhaustive pattern match: missing case: Bloo".
10. **Guards are ⇐-checked against `Bool` in the pattern-extended
    environment, at both typing entry points.** `infer_match`
    (typecheck.ml:4280–4284) and the `EMatch` arm of `check_expr`
    (typecheck.ml:4192–4196) both check `br.branch_guard` (when present)
    against `t_bool` in `env'` (Γ already extended with the SAME branch's own
    pattern bindings), so a guard can read variables its own pattern just
    bound (`P(a, b) when a == b -> …`, the substitute historically used in
    place of `PatAs` back when it was unparseable; see finding 11 below,
    RESOLVED 2026-07-24, and `core-march.md:1247`). A
    non-Bool guard is rejected with "Match guards must be Bool."
    (`reject/t10_guard_not_bool` is the witness), the exact same `RBuiltin`
    reason-string shape `ECond`'s non-Bool-condition rejection uses (finding
    12), just with different wording.
11. **[RESOLVED 2026-07-24]**: `PatAs` had a live, correct `infer_pattern`
    arm (now typecheck.ml:3554–3557) but was unreachable from surface
    grammar (confirmed fresh at the time, zero `PatAs` occurrences in
    `parser.mly`). `pattern` gained an as-pattern production
    (`pattern_no_as AS lower_name`), so `p as x` now parses and typechecks
    via the `(P-As)` rule (§2.2). This is the same disposition
    `core-march.md` still gives `PatAs` operationally as of this pass
    (§4.3.1, not yet updated) and the same shape as this document's
    pre-existing `PatRecord` finding (real code, unreachable input), which
    remains open; only `PatAs` closed.
12. **`ECond` (`match do c -> b … end`) checks every condition against `Bool`
    and unifies every body into ONE result type anchored at the FIRST arm**
    (T-Cond, §2.1c, typecheck.ml:4020–4036), but, unlike `EMatch`, never runs
    exhaustiveness/redundancy checking at all (neither function is called from
    the `ECond` arm). This matches the operational finding that `ECond` is NOT
    statically total (`core-march.md:492–498`): an all-false chain typechecks
    with no Warning and panics at runtime unless closed off with a final
    `true ->`/`_ ->` arm. A non-Bool condition is rejected with "Each condition
    in `match do` must be Bool." (`reject/t11_econd_condition_not_bool` is the
    witness); a branch-body mismatch falls through to the same "All branches of
    a match must have the same type." text `EMatch` uses (no `ECond`-specific
    branch-mismatch message exists).
13. **[RESOLVED 2026-07-05, commit `7e40dc5b`]**: the duplicate-diagnostic
    quirk noted at the end of this finding is fixed: the `ELetFn` arm now
    measures the `env.errors` count before/after the return-annotation unify
    and, if it grew, routes the later self-type/arrow reconciliation through a
    scratch (discarded) error context, so the identical mismatch is reported
    ONCE (verified via `--check-json`; two genuinely-distinct errors still both
    report). Corpus witness `reject/t12` unchanged. The typing-rule description
    below (monomorphic-then-generalized `ELetFn`) is unaffected and remains
    accurate. **A local recursive function (`ELetFn`) is monomorphic inside its
    own body and generalized only afterward, but via a DIFFERENT mechanism than
    `T-Let`'s.** `infer_block`'s `ELetFn` arm (T-LetFn, typecheck.ml:4371–4399)
    binds the function's own name to a bare `Mono β` (fresh, ungeneralized)
    BEFORE typing the body, so a recursive call inside the body resolves via
    `instantiate` on a `Mono` scheme (a no-op: same `β`, not a fresh copy):
    every recursive call shares one monomorphic type, so **polymorphic
    recursion is rejected** exactly as standard HM predicts (verified live: a
    local `go` with two same-body recursive calls at `Int` then `String`
    fails with an ordinary T-App argument-mismatch). Unlike T-Let's RHS,
    which is typed under a bumped level (`enter_level`, typecheck.ml:4305)
    and then generalized via `generalize env.level`, the `ELetFn` arm never
    bumps the level at all; it types `β`, the params, and the body all at
    the SAME `env.level`, then compensates by generalizing with a
    **shifted-down threshold**, `generalize (env.level - 1) arrow_ty`
    (typecheck.ml:4397), which is what actually quantifies those
    same-level TVars. The net effect matches T-Let (monomorphic during its
    own definition, polymorphic afterward (`accept/t17_letfn_generalized_
    after_block` is the witness, `id_rec` used at `Int` then `String` in the
    rest of the block) via a mechanically different route. `ELetFn` also
    shares the "bind a fresh self-type, generalize once the body is fully
    checked" SHAPE with `check_fn`'s handling of a top-level recursive `fn`
    (typecheck.ml:4544–4574), but `check_fn` DOES call `enter_level`
    (typecheck.ml:4545), so it reaches the ordinary `generalize env.level`
    form; `ELetFn`'s omission of that bump, and its compensating
    `env.level - 1`, is unique to the local/block-scoped construct. A
    declared return-type annotation on a local recursive fn is enforced
    exactly as strictly as a top-level one's (`unify body_ty expected`,
    typecheck.ml:4392); `reject/t12_letfn_ret_annot_conflict` is the
    witness, and also surfaces a minor, non-blocking diagnostic-quality
    quirk: the identical mismatch is reported TWICE (see (T-LetFn)'s note,
    §2, and the `specs/todos/` entry) because the annotation-unify and the
    final self-type/arrow-type reconciliation unify independently
    rediscover the same conflict once it flows through the self-reference.
14. **An unresolved `CNum` constraint silently DEFAULTS to `Int` at its
    enclosing declaration's discharge point; but this defaulting is
    effectively INVISIBLE to a fully generic function, because `generalize`
    already quantified the type variable away with a fresh, isolated ref
    before discharge runs at all.** Verified live: `fn add_poly(a, b) do a + b
    end` (no annotations, no `when`-clause) typechecks with `--check` exit 0
    even though `add_poly` is never called anywhere, and, more
    surprisingly, remains callable at BOTH `Int` and `Float` afterward
    (`add_poly(1.0, 2.0)` also typechecks). The mechanism: `check_fn`
    generalizes `add_poly`'s inferred type (`typecheck.ml:4751`,
    `generalize env.level fn_ty`) BEFORE `check_decl`'s `discharge_constraints`
    call runs at all (`typecheck.ml:6468`, strictly after `check_fn` returns);
    and `generalize` (§1) always allocates a brand-new, isolated `TVar` ref
    for each quantified id (`typecheck.ml:866–869`), sharing only the
    integer id with whatever ref the pending `CNum` constraint still points
    at. So when `discharge_constraints` later finds that `CNum`'s type
    variable still `Unbound` and defaults it: `r := Link (TCon ("Int", []))`
    (`typecheck.ml:4965`); it mutates the OLD, already-superseded ref; the
    function's actual stored scheme (`Poly([a_new], [], a_new → a_new →
    a_new)`, fully UNCONSTRAINED — `check_fn`'s `all_constraints` is empty
    here since there is no explicit `when`-clause, so `generalize`'s own
    `Poly(ids, [], t)` output passes through unchanged, `typecheck.ml:4752–
    4753`) is untouched by that mutation and instantiates a truly fresh
    variable, unconstrained, at every call site. The net, surprising result:
    **a `Num`-constrained primitive used inside a fully generic local/
    top-level function elides the constraint entirely**: there is no way,
    short of an explicit type annotation, to make such a function reject a
    non-Num instantiation, because `Num` cannot even be spelled in a
    `when`-clause to force it to survive generalization (§2.1: `when
    Num(a)` itself errors, "I don't know a constructor called `Num`" — `Num`
    is not in `env.interfaces`). This is DIFFERENT from, and easy to
    conflate with, the ordinary "generic function, constraint resolved per
    call site" story that works correctly for `CInterface`-based constraints
    with an explicit `when`-clause on a MONOMORPHIC-at-the-constrained-
    position function (see finding 15): here there is no `when`-clause at
    all, `a`/`b` are simply unannotated params, and the `Num` obligation
    both arises AND evaporates within `add_poly`'s own declaration, never
    reaching a call site to be re-checked.
15. **[RESOLVED 2026-07-05, commit `8cbd6dd2`]**: root cause found and fixed.
    The `when Eq(a)` argument `a` (an unannotated VALUE parameter) was resolved
    only against `fn_tvars` (signature type-variable names), which has no entry
    for a value-parameter name, so `check_fn` created a FRESH placeholder var
    disconnected from the parameter's actual type and attached the constraint to
    THAT, a phantom `generalize` quantified away, so at each call site
    `instantiate` substituted it with an independent fresh var never bound to the
    argument, and `discharge_constraints` always saw an `Unbound` TVar and
    skipped it. Fix (`lib/typecheck/typecheck.ml`): when the `when`-clause name
    isn't a signature type var, resolve it against the value-parameter binding in
    `body_env` and attach the constraint to the parameter's own type variable, so
    it persists generalization, passes through `instantiate` onto the caller's
    `pending_constraints`, and is discharged at the call site. `same(Rood,Rood)`
    now rejects; satisfiable generic constraints still accept (corpus
    `accept/t22`, `reject/t17`). The soundness-gap analysis below is retained for
    the record. **A `when Interface(a)` constraint on an explicit function bound
    is correctly enforced when it can be discharged AT THE FUNCTION'S OWN
    DECLARATION (a concretely-annotated parameter), but is SILENTLY NOT
    RE-CHECKED at call sites when the bound type variable is left generic,
    a real, reproducible typechecker gap, distinct from finding 14's
    `Num`-specific defaulting.** Verified live, three ways:
    (a) `fn same(a : Hue, b : Hue) when Eq(a) do a == b end` (param
    concretely annotated to a no-`Eq`-impl ADT `Hue`) correctly rejects at
    `same`'s OWN declaration with `` `Hue` does not implement interface
    `Eq`. `` The constraint IS enforced when it can be checked immediately.
    (b) `fn same(a, b) when Eq(a) do a == b end` (UNANNOTATED, `a`'s type
    stays a generic type variable at `same`'s own declaration, so
    `discharge_constraints` sees `CInterface("Eq", TVar _)` and skips it,
    "still polymorphic, cannot check yet", `typecheck.ml:4973`) then
    `same(Rood, Rood)`, where `Rood` is a variant of the SAME no-`Eq`-impl
    `Hue` ADT from (a), **typechecks with exit 0**, even though a direct
    `Rood == Rood` (bypassing the `same` wrapper) correctly rejects with the
    identical `` `Hue` does not implement interface `Eq`. `` message. The
    constraint is silently lost, not just deferred: `same`'s scheme is
    truly `Poly([a_id], [CInterface("Eq", a_tv)], a → a → Bool)`
    (`check_fn`'s `all_constraints` non-empty branch, `typecheck.ml:4752–
    4757`, DOES attach the `when`-clause's constraint here, unlike finding
    14's unconstrained case), but calling `same(Rood, Rood)` should
    `instantiate` that `Poly` scheme (§1), substitute `a := Hue`, and push a
    FRESH `CInterface("Eq", Hue)` onto `main`'s own `pending_constraints`,
    which `main`'s own `discharge_constraints` call should then reject. It
    does not. (c) Ruled out `TArrow`-specific behavior in `impl_matches_ty`
    by reproducing the identical gap with a plain ADT value instead of a
    function value, and ruled out "the constraint never gets attached to
    the scheme at all" by confirming (a) DOES enforce it when the violation
    is visible at `same`'s own declaration. **Root cause not fully
    pinned down in this task** (this is a docs-only task; `typecheck.ml` was
    not modified); the most likely candidate, given `instantiate`'s
    id-keyed substitution (§1) and `generalize`'s fresh-ref-per-id copy
    (`typecheck.ml:866–869`, the same mechanism implicated in finding 14),
    is some interaction between the ORIGINAL constraint-bearing `TVar` ref
    (captured once, while processing the `when`-clause, `typecheck.ml:4687–
    4712`, BEFORE `generalize` runs) and the COPIED ref `generalize` installs
    into the returned type, both share the integer id, which is what
    `instantiate`'s `List.assoc_opt id subst` keys on (§1), so in principle
    the constraint's stale `TVar` SHOULD still resolve to the same fresh
    substitution var when `instantiate` walks `inst_cs` (`typecheck.ml:929–
    934`) at a later call site; something about the ORDER those two events
    happen in, or a difference between the immediate-declaration path (a)
    and the deferred generic-call path (b)/(c), breaks that expectation.
    **This is a real typechecker soundness gap** (an explicit `when
    Iface(a)` bound on a generic parameter is not actually enforced
    polymorphically); logged in `specs/todos/` under "Compiler: Type
    System" (2026-07-05) with this exact repro, since fixing it is out of
    scope for this docs-only task. Not exercised by this corpus's `reject/`
    programs (a `reject/` program built on it would need to codify a
    behavior this document identifies as WRONG, which would defeat the
    corpus's purpose; the corpus instead uses the primitive, always-correctly
    -enforced `Ord`/`Num` constraints for its `reject/` witnesses, findings
    above).
16. **[RESOLVED 2026-07-05, commit `f0f5299c`]**: the annotation is now a
    CHECKING context. A new `infer_let_annotated` helper resolves `bind_ty` via
    `surface_ty` and checks the RHS against it with `check_expr` (so a
    polymorphic RHS bound at a more specific instance still works), falling back
    to plain inference only when the annotation isn't a resolvable type (a
    phantom/typestate tag). `let x : Int = "foo"` now rejects; `accept/t21` +
    `reject/t16` pin both directions. The gap analysis below is retained for the
    record. **`let`-binding type annotations (`let x : T = e`) WERE parsed but
    never enforced by the typechecker, the second logged, open gap.** Found while
    building Task 2's tuple/record corpus. The parser accepts a type
    annotation on a `let` binding and stores it as `Ast.bind_ty`, but
    (T-Let)'s `infer_block` arm (§2, typecheck.ml:4293–4324) never consults it
    (`grep -c bind_ty lib/typecheck/typecheck.ml` = 0): τ₁ is inferred from
    the RHS by itself and the annotation is silently discarded, so `let x : Int =
    "foo"` and `let pair : (Int, Int) = (1, 2, 3)` both `--check` at exit 0.
    **Not a soundness hole**: the inferred type still governs, so a LATER use
    of `x` at the annotated-but-wrong type is still caught by ordinary
    unification; the annotation is just decorative rather than a checking
    context. This corpus routes around it intentionally: the tuple-arity
    reject witness (`reject/t08_tuple_arity_mismatch`) uses a
    FUNCTION-PARAMETER annotation (enforced via ordinary T-App param-vs-arg
    unification, §2) rather than a `let` annotation to elicit its mismatch,
    specifically because a `let`-annotation mismatch would NOT be rejected.
    Logged in `specs/todos/` under "Compiler: Type System" with the fix
    direction (check the RHS against `bind_ty` via `check_expr` at the `ELet`
    arm, when present, instead of unconditionally inferring); not fixed here
    (docs-only task). A `reject/let_annotation_mismatch`-style program should
    be added to this corpus once the enforcement lands.
17. **[OPEN, logged, not fixed] `derive X for UnknownType` silently no-ops: no
    diagnostic, exit 0, program runs as if the `derive` line were absent.**
    Found while building §2.4's `derive`/`satisfy` widening. `expand_derive`'s
    `None` branch (`desugar.ml:1659`) returns a bare `[]` when the target type
    name isn't found in the module's collected `type_defs`; no `Err.error`
    call, unlike the symmetric "unknown INTERFACE" case in the very same
    function (the `_ -> Err.error …` catch-all in `derive_impl`,
    `desugar.ml:1641–1647`) and unlike `satisfy`'s own unknown-interface and
    missing-function checks (§2.4), both of which DO reject. Minimal repro,
    re-checked live for this task:
    ```
    mod M do
      derive Eq for Ghost           -- `Ghost` is never defined anywhere

      fn main() do
        println("no error, no Ghost type defined")
      end
    end
    ```
    `--check` exits **0** (no diagnostic); running it also exits **0** and
    prints `no error, no Ghost type defined`; the `derive` line has zero
    observable effect, silently. Logged in `specs/todos/` under "Compiler:
    Type System" with this repro and the `desugar.ml:1659` citation; fixing it
    (rejecting an unknown derive TARGET TYPE the same way an unknown derive
    target INTERFACE already is) is a compiler change, intentionally out of
    scope for this documentation slice. Not encoded as a `reject/` corpus
    program for the same reason findings 15–16 aren't: a `reject/` witness
    would assert behavior this finding identifies as WRONG (the program
    currently, incorrectly, `--check`s clean); once fixed, a
    `reject/derive_unknown_type`-style program should be added here.

18. **[OPEN, logged, not fixed] `spawn(Actor)` does NOT yield `Pid[state]`; the
    `Pid` parameter is an unconstrained fresh variable, and the state type never
    reaches an observable `Pid`.** Found while building §2.6 (actors widening,
    Task 1). The `ESpawn` arm returns `TCon ("Pid", [fresh_var env.level])`
    (`typecheck.ml:4203`), a fresh var computed with no reference to the actor's
    state type. The `bind_var name.txt (Mono (TCon ("Pid", [state_ty])))` at
    `:6821` *does* record the state type against the actor name, but that binding
    is unreachable from a bare occurrence: the nullary-constructor registration
    at `:6769` (actor name ⇒ type `<Name>`) shadows it, so a bare `Counter` is
    typed `Counter`, not `Pid[state]`. Live probes (re-checked for this task):
    `let p = if true do spawn(Counter) else spawn(Named) end` typechecks clean
    with `Counter`/`Named` with *different* state records (proving each
    `spawn` yields an independent free var, not `Pid[state]`); `is_alive(Counter)`
    is rejected `` expected `Pid(r3)` but got `Counter` `` (the name is the
    nullary ctor, not the `Pid[state]` value). Compounding it, no surface
    annotation can pin the parameter either: the built-in arity-1 `Pid`
    (`typecheck.ml:1849`) is shadowed in the single global type namespace (§2.5)
    by stdlib `GlobalPid`'s 0-arity `type Pid` record (`stdlib/global_pid.march:
    11`), so `Pid(T)` annotations reject `` `Pid` expects 0 type argument(s) but
    got 1. ``. So the state type is *checked* inside the actor decl (init +
    handler conformance, §2.6.1) but is not stored on the `Pid` at any `spawn`
    site. This is a faithfulness note, not a corpus reject (there is no
    *incorrect* program to pin (`accept/t39_actor_spawn_pid` witnesses the
    actual, fresh-var accept behavior)); tightening `spawn`'s result to
    `Pid[state]` (or making the actor name resolve to its `:6821` `Pid[state]`
    binding) would be a compiler change, out of scope for this docs slice. See
    §2.6.3 for the full account.

19. **[OPEN, logged, not fixed] `send` does NOT check the message against the
    target actor's accepted-message set; a wrong-actor send typechecks (exit 0)
    and, at RUNTIME, is silently DROPPED interpreted but MISROUTED (memory-unsafe)
    compiled.** Found while building §2.6.4 (message-payload typing, Task 3).
    Distinct from finding 18 (which is about the `Pid` being unparameterized after
    `spawn`); this finding is about the `send` *typing arm itself* ignoring the
    target. The `ESend` arm (`typecheck.ml:4177`) infers the target Pid's type
    and immediately discards it (`ignore (infer_expr env cap)`, `:4178`), so
    `send` never consults which actor `cap` is; the only send-side check is
    `check_sendable` (`:3335`), a hardcoded `RingBuf` denylist (`non_sendable_types
    = ["RingBuf"]`, `:3331`), NOT a message-acceptance check. The message payload
    *shape* IS checked (ordinary `ECon` typing on `infer_expr env msg`, `:4179`;
    that is finding-19's *complement*, witnessed by `reject/t29`), but *which
    handler the target actually has* is not. Note this would remain true even if
    the Pid stored its state type (cf. finding 18): `send` doesn't read the
    target's type at all. Minimal repro (`Counter` handles only `Inc`, `Logger`
    handles `Log`; send `Log` to the `Counter` Pid), re-checked live BOTH
    backends for this task:
    ```
    mod Main do
      actor Counter do
        state { count : Int }
        init  { count: 0 }
        on Inc(x : Int) do
          println("Counter.Inc -> " ++ int_to_string(state.count + x))
          { count: state.count + x }
        end
      end
      actor Logger do
        state { seen : Int }
        init  { seen: 0 }
        on Log(m : String) do
          println("Logger.Log -> " ++ m)
          { seen: state.seen + 1 }
        end
      end
      fn main() do
        let counter = spawn(Counter)
        send(counter, Inc(3))
        send(counter, Log("stray"))   -- Log is a Logger message, not Counter's
        run_until_idle()
        println("done")
      end
    end
    ```
    `--check` exits **0**. Interpreted run prints only `Counter.Inc -> 3` then
    `done`; the stray `Log` matched no `Counter` handler name and was silently
    dropped (`eval.ml:7545` string-equality tag match; `None -> ()`,
    `eval.ml:7547-7549`). Compiled run (`--compile --opt 2`) prints `Counter.Inc
    -> 3`, then `Counter.Inc -> <garbage int, e.g. 2796564219>`, then `done`: the
    stray message was MISROUTED into `Counter`'s first handler slot (the compiled
    dispatch is an `ECase` on a per-actor `<Actor>_Msg` variant discriminant, in
    handler-declaration order, with **no default arm** (`ECase(msg, branches,
    None)`, `lower_actor.ml:256`, variant order `lower_actor.ml:17`), and the
    `String` payload pointer was reinterpreted as the `Int` param of `Inc`),
    non-deterministic, memory-unsafe. Logged in `specs/todos/` under "Compiler:
    Type System" (2026-07-06) with this repro; fixing it (typing Pids by their
    accepted-message set so `send` can gate the message against the target actor)
    is a significant type-system design decision, deferred, out of scope for this
    docs-only slice. Not a corpus `reject/` (it typechecks; a `reject/` witness
    would codify behavior this finding calls WRONG); the correctly-typed accept
    path is `accept/t40_actor_send_typed_payload`. Cross-ref §2.6.4 and finding
    18.

20. **[FIXED 2026-07-07, STALE "[OPEN, logged, not fixed]" tag corrected
    2026-07-22, was inconsistent with this document's own §2.7.5, which
    already recorded the fix] F4: the MPST merge rule leaked into binary
    duality: a `choose` with two structurally-identical-type branches used to
    be wrongly rejected as "not duals of each other."** Re-checked live this
    task: the exact repro below now typechecks (`--check` exit **0**), not
    exit 1; the merge-rule branch in `project_steps`'s `ProtoChoice` arm is
    now gated on `multiparty`, so a binary protocol's non-chooser always
    projects to `SOffer{…}` and the spurious rejection does not fire (witness
    `accept/t44_binary_choice_identical_branches`). The repro and root-cause
    analysis below are kept as the historical description of the bug. Found
    while building §2.7
    (session-types widening, this task). `project_steps`'s `ProtoChoice` arm
    (`typecheck.ml:5906–5919`) applies the standard MPST "merge branches that
    project to the exact same local type for a non-participating role" rule
    UNCONDITIONALLY, including for a plain 2-role BINARY protocol, where the
    "non-chooser" role is the chooser's only peer, not a bystander the merge
    rule was designed for. When both `choose` branches happen to carry the
    same payload type (`session_ty_exact_equal`, `:2058`), the peer's
    projection silently collapses from `SOffer {...}` to that one shared type
    which is then no longer the dual of the chooser's `SChoose {...}`, so
    `project_protocol`'s binary duality check (`:5972–5986`) rejects the
    protocol. Minimal repro (re-checked live for this task):
    ```march
    protocol Decision do
      choose by Client:
        ok  -> Server -> Client : Int
        err -> Server -> Client : Int
      end
    end
    ```
    `--check` USED TO exit **1** (now exits **0**, confirmed live this task):
    `` Protocol `Decision`: the projection onto `Client`
    and the projection onto `Server` are not duals of each other.\ndual(Client)
    = Offer{ok: Send(Int, End), err: Send(Int, End)}\nbut Server has:
    Send(Int, End) `` (note the printed `Server` projection was already the
    MERGED `Send(Int, End)`, not a `Choose{...}`, which was the tell). Making
    the branches type-distinct (`err -> Server -> Client : String`) also
    typechecks clean (exit 0), as it always did. See §2.7.5 for the full
    writeup and the fix citation. Correctly NOT a corpus `reject/` program;
    since the fix, it is also not an `accept/` witness for THIS exact repro
    under this finding number, but the equivalent shape is pinned by
    `accept/t44_binary_choice_identical_branches`.
21. **[FIXED 2026-07-24, Task 4 of the session-types correctness fixes] F5:
    `Chan.offer` used to always return the FIRST branch's continuation
    type, regardless of which branch the peer actually chose at runtime.**
    Found while extending §2.7 with per-op channel typing (session-types
    widening, Task 3); closed by a later task in the same overall effort.
    `Chan.offer`'s arm (`typecheck.ml:4505`, §2.7.8/§2.7.9) still requires
    the channel be at `SOffer branches` and still returns `(Atom, Chan at
    branches's FIRST entry's continuation)` as its immediate result
    (`:4516–4535`); the arm's own comment (`:4498–4504`) still calls this
    "a conservative approximation" since the true continuation depends on
    the peer's runtime choice, which is not statically knowable without
    dependent types. What changed: `match`ing the label an `offer` returns
    now REFINES the channel per-arm to that arm's actual branch continuation
    (`with_offer_refinement`, `typecheck.ml:5597–5616`, driven by
    `env.offer_conts`/`env.offer_labels`), and, this is what makes the fix,
    SOUND, not just more precise, driving an offer channel with branches that
    continue differently WITHOUT first matching the label is now a hard
    compile error (`offer_unrefined_error`, `typecheck.ml:4176–4186`):
    `` <op>: this channel came from `Chan.offer`, and the protocol's
    branches continue differently, so I don't know which one the peer
    chose. Match on the label first — `match lbl do :ok -> ... :err -> ...
    end` — and use the channel inside each arm. `` A follow-up fix in the
    same task closed a bypass where rebinding the label variable's name
    (`let lbl = :ok` after the `Chan.offer` destructure) left the stale
    label→ref linkage reachable, letting the exact type confusion back in
    through a shadowed name instead of a missing `match`
    (`reject/t97_offer_label_shadow_bypass`). Corpus:
    `reject/t95_offer_unrefined_continuation` (driving an unrefined offer
    channel directly), `reject/t97_offer_label_shadow_bypass` (the shadow
    bypass), `accept/t43_choose_offer_roundtrip` (the identical-continuation
    case, where none of this restriction applies). See §2.7.9 for the full
    writeup, the worked example, and the exact refinement mechanism.
22. **[FIXED 2026-07-24, Task 2 of the session-types correctness fixes] A
    `loop do … end` block used to project to ONE unrolled iteration, not a
    real recursive session type.** Found while widening §2.7's projection
    coverage. `project_steps`'s `ProtoLoop` arm (`typecheck.ml:7499–7512`)
    projects the loop body with a fresh `SVar` back-reference as the body's
    OWN continuation, then wraps the result in `SRec (rec_var, body)`, the
    standard µ-type encoding `Rec X. S[X]`, where the back-reference inside
    `body` really does point at `body` itself, so the session repeats
    indefinitely. The earlier version of this arm instead SUBSTITUTED the
    loop's outer (post-loop) continuation into the back-reference before
    wrapping (`subst_svar outer_cont`), which produced an `SRec` binder
    with no `SVar` actually inside it: in form a recursive type, but
    semantically just one unrolled pass through the body followed by
    whatever came after the loop. A protocol declaring `loop do A -> B :
    Int; B -> A : Bool end` used to type as "exactly one round-trip," so a
    program driving a SECOND iteration was wrongly rejected (`` channel is
    at `End` ``); it now type-checks for any number of iterations. Because a
    real `Rec X. S[X]` never reaches `SEnd` on its own, a step written
    after a `loop` block at the same nesting level can never run; this is
    now enforced as a protocol-declaration error, not a limitation:
    `check_unreachable_after_loop` (`typecheck.ml:8936–8952`) rejects it with
    `` Protocol `<name>`: the steps after this `loop` can never run — a
    `loop` block repeats forever, so it must be the last step. `` Corpus:
    `accept/t92_loop_protocol_two_iterations` (two round-trips through a
    looping protocol, previously rejected, now accepted),
    `reject/t93_steps_after_loop_unreachable` (a step after `loop`, now
    rejected). See the session-types reference's "Repetition: `loop`"
    section for the user-facing writeup.
23. **[FIXED 2026-07-24, Task 1 of the session-types correctness fixes] A
    protocol's steps AFTER a `choose … end` block used to silently vanish
    from BOTH roles' projections.** Found while widening §2.7's projection
    coverage. `project_steps`'s `ProtoChoice` arm (`typecheck.ml:7513–7542`)
    now projects each branch with `after_choice = rest_ty ()`, the
    projection of the steps that textually follow the entire `choose`
    block, as that branch's continuation, since every branch eventually
    rejoins the same protocol tail. The earlier version projected each
    branch with the OUTER `cont` argument directly; at the top level of a
    protocol that outer `cont` is `SEnd`, so every branch's continuation
    was simply "the protocol is over" regardless of what steps were
    actually written after the `choose` block. Both roles' projections
    dropped the trailing steps CONSISTENTLY (same wrong answer on both
    sides), so binary duality still held and the protocol typechecked
    clean; a program could skip the post-choice steps entirely and still
    pass `--check`, and conversely a program that correctly implemented
    the trailing steps could be wrongly rejected once it tried to use them
    (a channel that should still be mid-protocol was typed as already at
    `SEnd`). Corpus: `reject/t91_choice_tail_step_required` (a program that
    closes the channel instead of running the protocol's trailing step,
    now correctly rejected once the trailing step is visible in the
    projection). See §2.7.3 above for the projection detail.
24. **[FIXED 2026-07-24, Task 3 of the session-types correctness fixes]
    `Chan.new` used to silently accept protocols with more than two roles,
    returning a non-dual pair.** Found while widening §2.7's per-op typing
    coverage. `Chan.new`'s arm (`typecheck.ml:4323–4362`) requires the
    looked-up protocol's `pi_projections` (§2.7.3) to have EXACTLY two
    entries; for 3-or-more roles it now rejects with `` Chan.new: protocol
    `<name>` has N roles but Chan.new needs exactly 2. Use MPST.new for
    multi-party protocols. `` The earlier version instead matched a THREE-OR-
    MORE-role `pi_projections` list against a pattern expecting only the
    two-element case to succeed as a pattern match, falling through to silently
    return the first two role projections (in `pi_projections`'s
    alphabetically-sorted order, §2.7.3) as if they formed a valid binary
    pair, but two projections drawn from a 3+-role protocol are not
    duals of each other (each one's `SMSend`/`SMRecv` steps name OTHER
    roles the two-endpoint model has no way to represent), so the resulting
    `Chan` pair was unsound: operations on it would type-check against a
    session shape that does not correspond to what the third (and further)
    role(s) actually do. Corpus: `reject/t94_chan_new_multiparty_protocol`
    (a 3-role protocol passed to `Chan.new`, now rejected; use `MPST.new`
    instead). See the `Chan.new` bullet in §2.7.8 above.

## 5. What this validated, and what's next

**Validated:** the type-side methodology works end-to-end: the bidirectional HM
judgment is transcribable arm-for-arm from `typecheck.ml`, the `--check`-based
`accept/reject` harness is a workable conformance anchor (with exact-error-message
pinning), and the doc format (judgment → cited rules → accept/reject table) is a
replicable template. `check_types.sh` is the committed anchor; Task 7 wired it
into its own `types-check` dune alias, a separate slow CI lane, run alongside
(not merged into) `@oracle`/`@runtest`; see `specs/lang/types/INDEX.md` for
the harness model and why `reject/` programs cannot ride the operational
side's both-ways `@oracle` sweep.

**Task 1 added:** ADT constructor + `match` typing: (T-Con),
(T-Match), and the pattern-typing relation `Γ ⊢ p : τ ⊣ Γ'` for `PatCon`/
`PatVar`/`PatWild`/`PatLit` (§2, §2.2), transcribed from `instantiate_ctor`
(typecheck.ml:2387), the `ECon` arm of `infer_expr` (typecheck.ml:3737),
`infer_match` (typecheck.ml:4273), and `infer_pattern` (typecheck.ml:2566).

**Task 2 (this slice) added:** tuples + records typing: (T-Tuple), (T-Record),
(T-Field), (T-Update), and the pattern-typing relation extended with
`(P-Tuple)` (§2, §2.2), transcribed from the `ETuple`/`ERecord`/`EField`/
`ERecordUpdate` arms of `infer_expr` (typecheck.ml:3851, 3855, 3900, 3860) and
the `PatTuple` arm of `infer_pattern` (typecheck.ml:2582). `PatRecord` was
confirmed unreachable from surface syntax (zero `parser.mly` occurrences,
matching `core-march.md`'s prior finding for the operational side), so no
`(P-Record)` rule was invented; only a one-line note pointing at its
(unreachable) `infer_pattern` arm (typecheck.ml:2671). The static/runtime
missing-field-on-update divergence adjudicated operationally in
`core-march.md` §4.2.1 is now also pinned on the type side: a concrete-base
missing-field update is a typecheck-time rejection (T-Update, §2), and the
runtime error path is only live for an erased `TVar` base.

**Task 3 (this slice) added:** atoms typing: (T-Atom-0), (T-Atom-N), and the
pattern-typing relation extended with `(P-Atom)` (§2, §2.2), transcribed from
the `EAtom` arm of `infer_expr` (typecheck.ml:4050–4052) and the `PatAtom` arm
of `infer_pattern` (typecheck.ml:2666–2669). The key finding: March's type
layer collapses EVERY atom (nullary or payload-carrying, any tag) to the
one monomorphic `Atom` type; the tag name and payload are typechecked (for
their own sub-expression/sub-pattern errors) but their types are discarded
rather than folded into the atom's type. This is the same erasure
`core-march.md:1354–1359` already traces as the root cause of a (since-fixed)
compiled `Show(Atom)` bug. No `reject/` program was added: because every atom
already has the one type this rule assigns, there is no atom-specific way to
violate it (§3, §4 finding 8).

**Task 4 (this slice) added:** the pattern-typing relation `Γ ⊢ p : τ ⊣ Γ'` is
now presented as COMPLETE (§2.2 preamble): every `infer_pattern` arm is
accounted for, with `PatAs` newly confirmed unreachable-from-surface-grammar
(zero `parser.mly` occurrences, verified fresh; the `AS` token's one grammar
use is in `soft_lower_name`, letting `as` be a variable name, not an
as-pattern) and documented that way rather than given a `(P-As)` rule,
mirroring `PatRecord`'s existing disposition. Also added: (T-Guard), the
`when g` clause is ⇐-checked against `Bool` in the pattern-extended
environment, at both `infer_match` (typecheck.ml:4280–4284) and the `EMatch`
arm of `check_expr` (typecheck.ml:4192–4196); (T-Cond), the scrutinee-less
`match do c -> b … end` boolean chain, transcribed from the `ECond` arm of
`infer_expr` (typecheck.ml:4020–4036), each condition ⇐ `Bool`, every body
unified into one result type anchored at the first arm. **The critical
finding this slice pins:** `check_exhaustiveness`/`check_redundant_arms`
(typecheck.ml:3159–3185 / 3131–3155) both report at `severity = Warning`
(never `Error`), and `--check`'s exit code (`bin/main.ml:819–821`) filters
strictly on `Error`, so a non-exhaustive `match` (or a redundant arm)
**typechecks**, exit 0, with only an advisory `-- WARNING --` block. This
governs the conformance corpus directly:
`accept/t14_nonexhaustive_match_still_typechecks` intentionally covers only one
arm of a 2-ctor ADT and is CORRECT to sit in `accept/`, not `reject/`: a
non-exhaustive match can never be used to construct a passing `reject/`
program in this harness, since `check_types.sh` (§3) keys purely on the
process exit code. Exhaustiveness checking is also skipped entirely (not
just downgraded) whenever any branch has a guard (typecheck.ml:
3161–3164). Two new `reject/` programs exercise truly new-to-this-task
error text: a non-Bool guard ("Match guards must be Bool.",
`reject/t10_guard_not_bool`) and a non-Bool `ECond` condition ("Each condition
in `match do` must be Bool.", `reject/t11_econd_condition_not_bool`); neither
restates an earlier task's reject message. `check_types.sh`: 26/26 (15 accept,
11 reject), exit 0.

**Task 5 (this slice) added:** local recursive functions typing: (T-LetFn)
(§2), transcribed from the `ELetFn` arm of `infer_block` (typecheck.ml:
4371–4399; the singleton/standalone counterpart at typecheck.ml:4101–4119 is
cited alongside as the same shape, reached only when the local fn is the
last/only statement of a block). **The critical finding this slice
pins:** the function's own name is bound to a bare, fresh, UNGENERALIZED
`Mono β` before its body is typed (typecheck.ml:4373–4374), so every
recursive call inside the body shares one monomorphic type; polymorphic
recursion is REJECTED, standard HM (verified live, not committed as a
separate reject program since it would restate `reject/t01`'s mismatch
shape). Generalization does happen, but only once the body is fully checked
and only for the REST of the enclosing block (never inside the function's
own body), via `generalize (env.level - 1) arrow_ty` (typecheck.ml:4397), a
mechanically different route from T-Let's (T-Let bumps the level with
`enter_level` before typing the RHS then generalizes at the ordinary
`env.level`; `ELetFn` never bumps the level at all, instead shifting the
generalization threshold down by one to compensate) that reaches the same
observable result. `ELetFn` shares its "bind a fresh self-type, generalize
after the body is checked" shape with `check_fn`'s top-level recursive `fn`
handling (typecheck.ml:4544–4574) but not that function's `enter_level` call
A real, uncommented divergence between the two recursive-binding paths,
pinned here for the first time. Two new `accept/` programs: a self-recursive
local `fn go(k, acc)` computing factorial (`accept/t16_letfn_factorial`,
monomorphic-in-body recursion) and a local `fn id_rec` used at both `Int` and
`String` in the block's continuation (`accept/t17_letfn_generalized_
after_block`, proving the post-body generalization actually fires, the
`ELetFn` analog of `t03_let_poly`). One new `reject/` program,
`reject/t12_letfn_ret_annot_conflict`: a declared return-type annotation
(`fn go(k) : Int`) on a local recursive fn conflicts with the body's actual,
internally-self-consistent inferred type (`String`, consistent across the
recursive call), truly new coverage (neither a T-App arity restatement
nor a T-Match branch-mismatch restatement: both match branches agree with
each other; only the annotation disagrees with what they agree on).
Discovered in the course of building that witness: a minor, non-blocking
diagnostic-quality quirk where the identical mismatch is reported TWICE
(same span, same text) because the annotation-conflict unify
(typecheck.ml:4392) and the final self-type/arrow-type unify
(typecheck.ml:4396) each independently rediscover the same conflict once it
flows through the self-reference `β`, noted in (T-LetFn)'s rule (§2), §4
finding 13, and `specs/todos/` (cosmetic; does not affect this corpus's
pass/fail, and does not reproduce for the equivalent top-level `fn`, which
reports once with a better message). `check_types.sh`: 29/29 (17 accept, 12
reject), exit 0.

**Task 6 (this slice) added:** the interface-constraint MODEL itself: how a
`Num`/`Eq`/`Ord`/`Show` obligation is represented (`constraint_`,
`typecheck.ml:128–133`), CREATED (`instantiate`, §1, pushing onto
`env.pending_constraints`), and DISCHARGED (**T-Discharge**, §2.1a,
transcribed from `discharge_constraints`, `typecheck.ml:4932–5049`, called at
every `DFn`/`DLet`/`DImpl` declaration boundary (`typecheck.ml:6468, 6477,
7045, 7048`), plus the trivial, unconstrained **(δT-And)**/**(δT-Or)**/
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
masks it first): `1 + "x"` directly instead falls through the ordinary
unify-mismatch path, a finding worth pinning since the plan's own text
assumed the direct form reaches the Num-specific message and it does not; an
`Ord`/`Eq`/`Show` violation on a type with no impl (a bare ADT, or a function
value) gives the `CInterface`-shaped `` `<τ>` does not implement interface
`<iface>`. `` + remediation hint. Also discovered that `COrd` (§2.1, a
constraint kind with real, working `discharge_constraints` logic) is DEAD:
`<`/`>`/`<=`/`>=` all resolve via `CInterface "Ord"`, never `COrd`; its only
constructor helper is underscore-prefixed and uncalled. Two further findings,
both about constraint SURVIVAL through `generalize`: (14) a `Num` constraint
on a fully generic, un-annotated function (no `when`-clause, impossible to
write one for `Num`, since `Num` is not in `env.interfaces`) is silently
defaulted-then-discarded, leaving the function's stored scheme truly
UNCONSTRAINED at every call site (verified: `add_poly(a,b) = a+b` typechecks
called at both `Int` and `Float`); (15) a REAL typechecker bug, an explicit
`when Eq(a)` (or `Ord`/`Show`) bound is correctly enforced when violated at
its OWN declaration (a concretely-annotated param) but is silently NOT
re-discharged at a call site when the bound variable is left generic
(`same(a,b) when Eq(a) do a==b end; same(Rood, Rood)` typechecks even though
`Hue` has no `Eq` impl and a direct `Rood == Rood` correctly rejects); logged
in `specs/todos/` under "Compiler: Type System" with the exact repro, not
fixed (docs-only task). Three new `accept/` programs (Num/Eq/Ord discharge
succeeding on built-in instances, and a `&&`/`||`/`not` boolean-logic
program) and three new `reject/` programs (the live-verified Num/Ord/Bool-
coercion error text, §2.1a/§2.1b). `check_types.sh`: 35/35 (20 accept, 15
reject), exit 0.

**Task 7 (this pass) added:** no new typing rules; pure consolidation.
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
`types-check` dune alias, a separate, slow, opt-in CI lane (`dune build
@types-check`), deliberately NOT folded into the default `@runtest` (see
`specs/lang/types/INDEX.md` for the harness model and CI-wiring rationale).
`check_types.sh`: unchanged at 35/35 (20 accept, 15 reject), exit 0; no
corpus programs were added or modified by this task.

**Session-types widening, Task 2 (this pass) added:** §2.7, this document's
FIRST session-type content: `protocol` declaration (three step forms,
`DProtocol`/`protocol_def`/`protocol_step`, `ast.ml:151`/`287–294`, parser
`parser.mly:606–627`); the local per-role `session_ty` representation
(`typecheck.ml:105–116`) and the channel value type `TChan of session_ty ref`
(`:95`); projection (`project_steps`, `:5870`; `project_protocol`, `:5952`);
binary duality (`dual_session_ty`, `:5935`, the `dual(A) == B` check,
`:5972–5986`); MPST send/recv-pair consistency (documented as TYPING-ONLY:
the compiled MPST runtime segfaults, F3, logged by the operational widening
task, not this one; **F3 is now RE-CHECKED (2026-07-27) and no longer
recurs**, see §2.7.4); and the `Chan(Role, Proto)` linear surface type
(`surface_ty`'s `TyCon("Chan", ...)` special case, `:2285–2311`). Logged **F4**
(§2.7.5, §4.1 finding 20): the MPST merge rule (`:5906–5919`) leaks into the
binary duality check, wrongly rejecting a legal binary `choose` protocol with
two branches that carry the same payload type, reproduced live both ways
(rejected identical-type / accepted type-distinct), not fixed (docs-only
slice at the time). **F4 is now FIXED**; see §2.7.5 and §4.1 finding 20.
Two new `accept/` programs: `accept/t41_binary_protocol_chan_new` (a
binary `Echo` protocol, `Chan.new`, straight-line send/recv/close, run-
witnessed printing `43`) and `accept/t42_mpst_protocol_new` (a 3-role `Relay`
protocol, `MPST.new`, run-witnessed printing a confirmation string), after
this task's two programs, `check_types.sh` stood at 71/71 (42 accept, 29
reject), exit 0. Per-operation channel typing (`Chan.send`/`recv`/`choose`/
`offer`/`close` state advancement) and the corresponding `reject/` corpus were
explicitly OUT of scope for this task; the next session-types widening
task's subject (see the Task 3 entry immediately below for where the corpus
went from there).

**Session-types widening, Task 3 (2026-07-06) added:** §2.7.8, the per-
operation channel typing Task 2 explicitly deferred above: the required
incoming session state, what each op checks, and the advanced outgoing state
for `Chan.new`/`send`/`recv`/`close`/`choose`/`offer` (each transcribed from
its own `typecheck.ml` arm, cited in §2.7.8). Logged **F5** (§2.7.9):
`Chan.offer` always returns the FIRST branch's continuation type regardless of
which branch the peer actually chose at runtime, a documented conservative
approximation that is a real (if narrow) soundness gap for `offer` over
branches with DIFFERENT continuations (at the time; **F5 is now FIXED**,
session-types correctness fixes Task 4, 2026-07-24; see §2.7.9 and §4.1
finding 21). Six new `reject/` programs
(`t30`–`t35`) pin the live per-op violation messages (send-at-wrong-state,
close-before-`End`, invalid `choose` label, wrong payload type, recv-at-
wrong-state, a linear channel continuation used twice), plus one new
`accept/` program (`t43_choose_offer_roundtrip`) for a full `choose`/`send`/
`close` + `offer`/`recv`/`close` round-trip, run-witnessed printing `:ok` then
`42`. `check_types.sh`: **78/78 (43 accept, 35 reject)**, exit 0; the
corpus's total after Task 3 (see below for the capabilities-widening total
that supersedes it).

**Capabilities widening, Task 1 (2026-07-07) added:** §2.8, the FIRST
capability/effect-system content in this document: the 18-entry IO
permission hierarchy (`lib/caps/cap_lattice.ml:15-34`, one tree rooted at
`IO`), `cap_subsumes`/`normalize` subsumption (`:50`/`:56`, aliased at
`typecheck.ml:1103`), the `needs` module manifest (`DNeeds`,
`ast.ml:159`), and **Check 1** (`typecheck.ml:5558-5587`): every `Cap(X)` in
a function/actor/extern signature must be covered (via subsumption) by a
declared `needs`, else ERROR. Logged a live scoping finding while verifying
the corpus: only 10 of the 18 hierarchy entries are registered as valid
`Cap(X)` type ARGUMENTS (`builtin_types`, `typecheck.ml:1858-1861`); the
other 8 (`IO.Random`, `IO.Database`, `IO.Spawn`, `IO.Mut`, `IO.Telemetry`,
`IO.Foreign`(`.Blocking`), `IO.NetConnect.TLS`) are valid `needs` targets
but reject as `` Unknown module `IO` `` if written inside `Cap(...)`; the
qualified-type-resolution fallback tries to load an actual `IO` module and
finds no matching exported type. Four new `accept/` programs (`t45`–`t48`:
bare-covered reflexive case, root-covers-child subsumption, sibling
independence: two siblings each need their own `needs`, and a second
mid-tier subsumption shape) and three new `reject/` programs (`t36`–`t38`:
uncovered `Cap(X)`, narrow `needs` does not cover a broader `Cap` (directional
imbalance, and sibling does not cover sibling). `check_types.sh`: **86/86
(48 accept, 38 reject)**, exit 0; the corpus's total after Task 1 (see below
for the Task 2 total that supersedes it).

**Capabilities widening, Task 2 (2026-07-07) added:** §2.8.6-§2.8.7:
transitive `use` coverage (**Check 4**, `typecheck.ml:5661-5681`: every
module a given module `use`s must have its own declared `needs` covered,
transitively, via the same `cap_subsumes` subsumption, ERROR on violation),
extern `Cap(X)` coverage (**Check 5**, `typecheck.ml:5684-5701`, ERROR), and
the extern-implies-`IO.Foreign` obligation (**Check 1c**,
`typecheck.ml:5607-5620`, WARNING-only), plus the honestly-stated three-tier
enforcement reality that reconciles `specs/lang/capabilities.md`'s tutorial
overclaim (F1, logged): Checks 1/4/5 (signature/transitive/extern-cap) are
true ERRORs, exit 1; Checks 1b (body-scanned builtin call, `typecheck.ml:5588
-5605`) and 1c (extern-implied `IO.Foreign`) are WARNING-only, exit 0;
reproduced live side by side (a `Cap(IO.FileRead)` signature with no `needs`
rejects; a body call to `file_read` with no `needs` only warns and
`--check`s clean). Two new `accept/` programs (`t49`: an importer declaring
the imported stdlib module `Vault`'s (`needs IO.Mut`) transitive obligation;
`t50`: a well-formed `extern` block covered on both its Check 5 and Check 1c
obligations) and one new `reject/` program (`t39`: companion to `t49` with
the covering `needs IO.Mut` removed, pinning Check 4's ERROR). Also files
**F6** (found while widening Task 1, logged now): only 10 of the 18 hierarchy
entries are registered as valid `Cap(X)` type ARGUMENTS (`builtin_types`,
`typecheck.ml:1858-1861`); see §2.8.3's scoping note, unchanged by this
task. `check_types.sh`: **89/89 (50 accept, 39 reject)**, exit 0; the
corpus's total after Task 2 (see below for the Task 3 total that
supersedes it).

**Capabilities widening, Task 3 (2026-07-07) added:** §2.8.8-§2.8.9:
`cap_narrow`/`root_cap` compile-time capability threading
(`root_cap : Cap(IO)` a value, `cap_narrow : Cap(IO) -> Cap(a)` a
POLYMORPHIC-return builtin, both `typecheck.ml:1457-1458`, both
runtime-erased); the effect-inference two projections `record_fn_caps`
computes per function (`typecheck.ml:5421-5447`): `cap_closures` (own +
module-wide `needs`) and `own_cap_closures` (own only); **Check 8**
(`typecheck.ml:5798-5834`): a `*_migrate_state`-suffixed fn (recognized by
name only, `is_migrate_fn_name`, `:5368-5378`, an ordinary module-level
sibling declaration, never nested inside an `actor` block) must be IO-free,
checked against `own_cap_closures` so a module's handler-level `needs`
cannot false-blame a pure migrate function (the F-caveat comment at `:5442`,
verified sound and precise for this consumer); **Check 7**
(`typecheck.ml:5755-5793`): a `Tagged(_, Realtime)` parameter excludes
`Cap(Alloc|IO|Panic)` parameters on the same signature. Files a scoping
note: `Realtime` is not itself pre-registered in `builtin_types` (unlike
`Alloc`/`Panic`), so a program must declare its own nullary `Realtime` type
before `Tagged(_, Realtime)` resolves at all; cosmetic, not a soundness
gap, since Check 7 fires correctly once the annotation resolves. Three new
`accept/` programs (`t51`: narrow-and-thread to a stricter callee; `t52`:
`root_cap` narrowed twice to two sibling sub-caps in one function; `t53`:
a pure `*_migrate_state` fn beside a real `actor` in a `needs IO.Console`
module, the caveat-mitigation witness) and two new `reject/` programs
(`t40`: a migrate_state fn calling `println`, Check 8; `t41`: a
user-declared `Tagged(Int, Realtime)` alongside `Cap(IO)`, Check 7).
`check_types.sh`: **94/94 (53 accept, 41 reject)**, exit 0; the corpus's
total after Task 3 (see below for the Task 4 total that supersedes it).

**Capabilities widening, Task 4 (2026-07-07) added:** §2.8.11-§2.8.12: the
five BEHAVIORAL module caps (`cap no_panic`/`no_alloc`/`no_extern`/`pure`/
`deterministic`), a mechanism orthogonal to the IO-permission `needs`/`Cap(X)`
infrastructure Tasks 1–3 cover (shares only the `cap` keyword and the `Ast.DOpts`
AST node). `cap no_panic` (`check_no_panic_module`, `typecheck.ml:6489-6566`)
and `cap no_alloc` (`lib/refinecheck/no_alloc.ml`) are CORRECT for the shapes
this task's corpus witnesses (explicit `panic`/unsafe division; non-empty
tuple/record/`ECon`/`ELam` construction). `cap no_extern`
(`check_no_extern_module`, `typecheck.ml:6604-6628`) is likewise correct for
both its raise sites (a `DExtern` block; a `needs IO.Foreign` path). Files
two headline UNSOUND under-approximations, both live-verified and both left
UNFIXED by this docs-only task (their fixes and REJECT witnesses are Tasks 5
and 6 of this same widening slice): **F2**: `pure_banned`
(`typecheck.ml:6570-6576`) and `deterministic_banned` (`:6632-6635`) are
hardcoded name lists that reference builtins which do not exist (`write_file`,
`random_int`, `now_ms`, …) while missing the real effectful ones
(`file_write`, `random_bytes`, `unix_time_ms`, …), so a `cap pure` module
calling `file_write` (or `random_bytes`), or a `cap deterministic` module
calling `unix_time_ms(())`, typechecks clean today; **F3**: `cap no_panic`'s
`panic_surface_*` sets cover named partial functions but never consult the
exhaustiveness checker's already-computed verdict, so a non-exhaustive
`match` inside a `cap no_panic` module typechecks clean and panics at
runtime. Also notes **F5** (cosmetic): `println`/`print` skip the Check-1b
body-scan diagnostic entirely despite being registered in
`builtin_cap_table`. Three new `accept/` programs (`t54`: a genuinely-pure
`cap pure` arithmetic module, valid across the coming F2 fix; `t55`: a valid
`cap no_alloc` module; `t56`: a valid `cap no_extern` module) and three new
`reject/` programs (`t42`: `cap no_panic` + explicit `panic`; `t43`: `cap
no_alloc` + tuple construction; `t44`: `cap no_extern` + an `extern` block).
`check_types.sh`: **100/100 (56 accept, 44 reject)**, exit 0; the corpus's
total after Task 4 (see below for the Task 5/6 totals that supersede it).

**Capabilities widening, Task 5 (2026-07-07): FIXED F2.** `pure_banned` and
`deterministic_banned` are now derived from `builtin_cap_table` (the
authoritative effect map) instead of the hand-guessed name lists Task 4
found and logged. `cap pure` now bans every effectful builtin the table
knows about (plus the incidental non-table `spawn`/`send`/`exit`); `cap
deterministic` bans only the nondeterminism-cap subset (`IO.Clock`/
`IO.Random`, via the new `is_nondeterministic_cap` helper), staying
correctly weaker than `cap pure`. Three new `reject/` programs made possible
by the fix (`t45`: `cap pure` + `file_write`; `t46`: `cap pure` +
`random_bytes`; `t47`: `cap deterministic` + `unix_time_ms`), each
type-correct so the cap ban is the sole rejection. Regression tests in
`test/test_compiler.ml` pin both the newly-rejecting programs and continued
acceptance of truly pure/deterministic modules. `scripts/run-tests.sh`
full six-runner suite verified GREEN. `check_types.sh`: **103/103 (56
accept, 47 reject)**, exit 0; the corpus's total after Task 5 (see below
for the Task 6 total that supersedes it).

**Capabilities widening, Task 6 (2026-07-07): FIXED F3.**
`check_no_panic_module` now consumes the exhaustiveness checker's verdict: a
new `env.nonexhaustive_match_spans` side-table records every non-exhaustive
match's span (populated by `check_exhaustiveness`, which already computed
this and only reported a Warning before), and `check_no_panic_module` reads
it, promoting any span nested inside one of the module's own function
bodies to an ERROR. One new `reject/` program made possible by the fix
(`t48`: `cap no_panic` + a non-exhaustive `match` over `Option(Int)`).
`accept/t14` (a PLAIN non-exhaustive match outside any `cap no_panic`
module) continues to accept, confirming the fix does not over-reject
ordinary code. `scripts/run-tests.sh` full six-runner suite verified GREEN.
`check_types.sh`: **104/104 (56 accept, 48 reject)**, exit 0; the corpus's
final total for this widening slice (§2.8.12, §3).

**Capabilities widening, Task 7 (2026-07-07): closeout, no new corpus.**
Finalized §2.8 to describe F2/F3 as FIXED throughout (rather than the
mid-slice "open"/"UNSOUND" framing Task 4 wrote before Tasks 5–6 landed);
corrected this section's own stale illustrative counts to the final
104/104; updated §6's roadmap bullet from "Tasks 1-3 landed, behavioral caps
still deferred" to reflect all seven tasks landed; reconciled the
`specs/lang/capabilities.md` tutorial's F1-overclaiming prose (see
`specs/todos/`'s slice-5 closeout entry for the full list of corrected
claims) and extended its behavioral-caps section to document all five caps
(previously only `no_panic`/`no_alloc`); logged **the proof-cap mint
mismatch** (intentionally unlabeled rather than a letter; `F1`–`F8` are all
already in use elsewhere in this document, including by the UNRELATED
session-types-slice linearity/diagnostic-noise findings, between the
tutorial's documented idiom and the actual, unrestricted `cap_narrow`-based
mechanism, deferred to a later proof-caps slice per the widening plan) and a
residual **guarded-match exhaustiveness gap** (a
pattern guard short-circuits `check_exhaustiveness` before it can record a
span, so a guarded non-exhaustive match in a `cap no_panic` module is
invisible to both the ordinary warning and F3's new error path, inherited
from the pre-existing exhaustiveness checker, not a regression, not in F3's
scope). `check_types.sh` reconfirmed 104/104; `check-docs.sh` reconfirmed
exit 0.

## 6. Deferred: the roadmap's Phase-2b/3 queue

This document is **Level-1 for the Core March fragment's type system**
(`specs/archive/2026-07-04-language-specification-roadmap-design.md` §2's "descriptive
reference, kept accurate by tests"; the level `core-march.md` already reached
operationally). What is explicitly OUT of scope for this document, and where
each item resurfaces in the roadmap's phasing (§5 of the roadmap doc):

- **User-defined `impl`/interface DECLARATION syntax, beyond the four
  built-ins, LANDED (§2.3/§2.4, 2026-07-06).** §2.1a/§2.1b document how a
  `Num`/`Eq`/`Ord`/`Show` CONSTRAINT is discharged against the seed table
  (`builtin_impls`, `builtin_interfaces`); §2.3 covers the general
  `interface`/`impl` declaration-checking infrastructure itself: registration,
  missing/extra-method rejection, signature-match, default methods,
  superclass/`requires` and `when`-clause discharge (both mandatory
  enforcement), and the `impl_matches_ty` structural-match judgment as its
  own named rule, `(T-ImplMatch)`; §2.4 covers `derive`/`satisfy` as `DImpl`
  generators. Coherence/overlap: no rejection of overlapping impls exists at
  all, and `(T-ImplMatch)` performs no specificity resolution between two
  simultaneously-matching impls, is noted on the typing side (§2.3, `(T-Impl)`
  step 1) and documented in full, with live-captured interpreter-vs-compiled
  evidence, in the operational companion `core-march.md` §4.4.3 as an open,
  deliberately-unresolved divergence (logged in `specs/todos/`, not fixed by
  this documentation slice). Roadmap: an extension of Phase 2 (§4.3's
  "declarative typing rules... extracted from `typecheck.ml`'s algorithm").
- **The constraint-survival soundness gap itself (finding 15, §4)**: RESOLVED
  2026-07-05 (commit `8cbd6dd2`): the `when`-clause now attaches the constraint
  to the value parameter's own type variable, so it persists generalization and
  is re-checked at call sites. The general `impl Iface(T)` declaration-checking
  infrastructure (previous bullet) remains the Phase-2 widening item.
- **Refinement types (z3-discharged).** Roadmap Phase 3 (§4.5/§6): "the
  refinement/capability soundness claims are machine-checked in Lean 4" is the
  acceptance criterion; this document's bidirectional HM judgment (§1) is the
  Level-1 substrate that Phase 3's refinement layer would extend, not
  something this pass attempts.
- **Linearity/capabilities: MOSTLY LANDED (§2.8, capabilities widening
  Tasks 1-7, 2026-07-07).** The capability lattice (`lib/caps/`) is named
  explicitly in the roadmap's Phase 3 scope (§4.5, "refinement/capability
  soundness"). §2.8 lands the IO-cap spine: the 18-entry IO permission
  hierarchy, `cap_subsumes`/`normalize` subsumption, the `needs` manifest and
  Check 1 (Task 1); transitive `use`/extern-implied caps, Checks 4/1c/5
  (Task 2); `cap_narrow`/`root_cap` compile-time threading, the
  effect-inference two projections, migrate_state IO-freedom (Check 8), and
  realtime exclusion (Check 7) (Task 3); **and the five *behavioral* module
  caps** (`cap no_panic`/`no_alloc`/`no_extern`/`pure`/`deterministic`,
  Task 4), **including two real compiler fixes** for soundness gaps the
  survey found: F2 (`cap pure`/`cap deterministic`'s banned-builtin sets
  now derived from `builtin_cap_table`, Task 5) and F3 (`cap no_panic` now
  rejects non-exhaustive matches via a recorded-span side-table, Task 6),
  both gated on the full test suite. **Proof-cap mint/forge, now LANDED
  (widening slice 6, §2.5.1 + §2.8.13, 2026-07-08).** "The proof-cap mint
  mismatch" is closed by two real compiler fixes: the gated `mint_cap` primitive
  + the `cap_narrow` proof-cap restriction (Batch A), and the general
  nested-module qualified-prebind soundness fix (`(T-QualRef)`) that closed the
  deeper polymorphic-launder exploitation. `Cap(P)` is now truly
  unforgeable. One documented residual stays OPEN: the `cap_narrow`
  container-launder taint gap (`tag_cap_producer_result` is shallow), logged in
  `specs/todos/`. Linear/uniqueness typing beyond the
  session-channel linearity
  already covered in §2.7.6/§2.7.8 is not separately named in the roadmap
  and is narrower still; grouped with capabilities as a Phase-3-or-later
  concern.
- **Effects.** Named alongside refinements/capabilities in the roadmap's
  problem statement (§4.3: "bidirectional HM inference + refinements + the
  capability lattice + effects") as part of the ambitious claim set a full
  spec needs; Phase 3 territory, not attempted here.
- **NOT deferred (a correction against the original skeleton's placeholder
  list):** records. The walking-skeleton v0 header listed "records" as a
  deferred later slice; Task 2 completed tuples+records typing in full
  (T-Tuple/T-Record/T-Field/T-Update, §2; P-Tuple, §2.2), so records are
  fully in-scope and covered by this reference; they are removed from the
  deferred set here.

Together, `core-march.md` (operational) + this document (typing) are
**Level-1 for the Core March fragment** per the roadmap's leveling (§2); the
next phase of BOTH documents is the Level-2 conformance work already underway
(the golden corpus + this document's `accept`/`reject` corpus) plus, per §4.4
of the roadmap, adjudicating the operational side's `known_divergence` queue.
This document's queue of logged typechecker gaps has **one truly open
item**, added by the interfaces/impls widening slice: **finding 17** (§4.1,
`derive X for UnknownType` silently no-ops) is OPEN, logged in
`specs/todos/` under "Compiler: Type System," intentionally NOT fixed by this
documentation-only slice. The three PRIOR logged gaps (findings 13, 15, and
16) were all RESOLVED 2026-07-05 (commits `7e40dc5b`, `8cbd6dd2`,
`f0f5299c`), with corpus witnesses (`reject/t16`, `reject/t17`, `accept/t21`,
`accept/t22`) and unit tests. The widening slice's operational companion,
`core-march.md` §4.4.3, also logged a second open item this slice: the
impl-coherence/overlap interpreter-vs-compiled divergence, documented there in
full with both backends' outputs and logged in `specs/todos/` alongside
finding 17.
