# Lean 4 Mechanized Metatheory for March — Planning Document

> **Status: PLAN ONLY — no implementation started.**
> This document explores what it would take to formally verify March's type
> system and key compiler passes in Lean 4. The goal is to answer "is this
> worth doing?" before committing any engineering time.

---

## 0. Motivation

March combines several non-trivial type-system features:

- Bidirectional HM inference with provenance tracking
- Linear and affine types for resource safety
- Session types for protocol compliance
- Perceus reference counting with FBIP (Functional But In-Place) reuse
- A TIR pipeline (mono → defun → Perceus → escape → LLVM emit) where each
  pass must preserve semantics

Any one of these features is complex enough that bugs creep in. The combination
multiplies the risk: the interaction between linear types and Perceus RC, for
instance, is subtle enough that informal argument is not convincing. Mechanized
proofs would give us:

1. A ground-truth specification that the OCaml implementation can be audited
   against.
2. Machine-checked evidence that the core design is sound (before investing
   in a full production compiler).
3. A forcing function for making implicit invariants explicit — the act of
   formalizing always surfaces ambiguities in a design document.

---

## 1. Scope — "Core March"

Formalizing the full surface language (pipe syntax, string interpolation,
module system, actor model, content-addressed versioning, REPL) is not the
goal. The target is a **core calculus** that preserves the semantically
interesting features while shedding surface sugar.

### 1.1 What Is In Core March

| Feature | Why Include |
|---|---|
| Simply-typed lambda calculus (functions, application, variables) | Everything builds on this |
| Let-bindings (non-recursive and recursive) | Pervasive; drives linearity |
| Algebraic data types — sum and product | Pattern matching is central to the language |
| Pattern matching / `case` expressions | Exhaustiveness + binding structure |
| HM polymorphism (type variables, universal quantification) | Core of the type system |
| Linearity qualifiers: `Lin \| Aff \| Unr` | Resource safety, Perceus |
| Affine/linear type rules (use-exactly/at-most once) | Main safety guarantee |
| Session types (binary: `Send`, `Recv`, `Choose`, `Offer`, `End`, `Rec`) | Protocol safety |
| Perceus RC operations: alloc, incRC, decRC, free, reuse | Memory safety |
| A-normal form (ANF) for the TIR | Enables clean Perceus formalization |

### 1.2 What Is Out of Scope

| Feature | Reason to Exclude |
|---|---|
| Surface syntax / parsing | Not semantically interesting for soundness |
| Module system, signatures, coherence | Large, mostly orthogonal |
| Actor model / mailboxes | Would require concurrency semantics |
| Multi-party session types | v1 defers these; add later |
| Type-level naturals / sized vectors | Interesting but large; save for a follow-on |
| Full HM inference algorithm | Proving the *algorithm* (not just the type system) doubles the work |
| LLVM IR emission | Too low-level; stop at TIR → TIR+RC |
| Standard library | Not relevant to soundness |

### 1.3 Core March Grammar (informal)

```
-- Types
τ ::= Int | Bool | Unit | String       -- base types
    | τ → τ                             -- function type
    | α                                 -- type variable
    | ∀α. τ                             -- universal quantification (HM)
    | T(τ₁, …, τₙ)                     -- algebraic type (named, monomorphic at TIR level)
    | τ ⊗ τ                             -- product (tuple)
    | q τ                               -- qualified type (q ∈ {Lin, Aff, Unr})
    | S                                 -- session type (see below)

-- Session types
S ::= Send(τ, S) | Recv(τ, S)
    | Choose { lᵢ: Sᵢ } | Offer { lᵢ: Sᵢ }
    | End | Rec(X, S) | X

-- Linearity qualifiers
q ::= Lin | Aff | Unr

-- Terms (surface)
e ::= x | λx:τ.e | e e
    | let x = e in e | letrec x:τ = e in e
    | Ctor(e₁, …, eₙ)
    | case e of { pᵢ → eᵢ }
    | Λα.e | e[τ]                       -- type abstraction/application (System F style)

-- Patterns
p ::= x | Ctor(p₁, …, pₙ) | _

-- TIR atoms / expressions (ANF)
a ::= x | lit
t ::= a | f(a₁,…,aₙ) | let x:τ = t in t
    | case a of { Ctorᵢ(xᵢ) → tᵢ }
    | alloc(T, a₁,…,aₙ)
    | free(a) | incRC(a) | decRC(a) | reuse(a, T, a₁,…,aₙ)
```

---

## 2. What We Would Prove

### 2.1 Type Soundness — Progress + Preservation

The classical two-part theorem for the core simply-typed + HM calculus.

**Progress**: A well-typed, closed term is either a value or can take a step.
```
∀ e τ, ⊢ e : τ → (value e) ∨ (∃ e', e →_β e')
```

**Preservation** (Subject Reduction): Reduction preserves types.
```
∀ e e' τ, ⊢ e : τ → e →_β e' → ⊢ e' : τ
```

These are proved for the **surface calculus** (pre-TIR). We use a small-step
operational semantics.

### 2.2 Linear Type Safety

For the linearity extension, the key theorem is:

**Linear Resource Usage**: Every variable annotated `Lin` is used exactly once
on every execution path. In a term `Γ ⊢ e : τ` where `Γ` maps `x` to
`Lin τ'`, every reduction sequence that terminates uses `x` exactly once.

This is usually phrased as a **linearity invariant** on typing derivations
rather than as a runtime theorem (because linearity is a static property).
The mechanized proof would show:

1. The typing rules are *linearity-respecting*: the context-splitting rules
   (used in the introduction rules for function application, let, etc.) always
   partition linear resources rather than duplicating or dropping them.
2. Weakening holds only for `Unr`-qualified types.
3. Contraction holds only for `Unr`-qualified types.

**Affine weakening**: For `Aff`-qualified bindings, weakening is permitted
(you may discard an affine value), but contraction is not. This is a
strictly weaker discipline than linearity.

### 2.3 Session Type Duality and Protocol Compliance

**Duality**: For every session type `S`, `dual(dual(S)) = S`. The dual
of `Send(τ, S)` is `Recv(τ, dual(S))`, and so on. This is a structural
induction on session types.

**Protocol compliance**: If `c : Chan(Client, P)` and `c' : Chan(Server, P)`,
and both sides follow their respective local types (projections of `P` onto
their role), then the channel will never deadlock and all messages are
well-typed.

Formally this is proved as a **session type safety** theorem:
a pair of processes typing under dual session types can communicate without
type errors and will eventually reach `End` (assuming the processes terminate
individually). This requires a concurrent reduction relation or a
canonical form theorem.

### 2.4 Perceus RC Correctness

This is the hardest and most novel theorem. The Perceus pass (see
`specs/perceus.md` and `lib/tir/perceus.ml`) inserts `incRC`/`decRC`/`free`/`reuse`
into the TIR. We would prove:

**Allocation safety**: Every allocated heap cell is eventually freed exactly
once on every terminating execution path.

More specifically, the Perceus pass produces a term where:
- No cell is freed twice (no double-free).
- No cell is accessed after being freed (no use-after-free).
- No cell is leaked (every cell allocated is eventually freed, modulo cycles).

The formal statement requires a **resource-annotated operational semantics**
where the heap is explicit. The key invariant is:

```
If Γ ⊢ₚ e : τ under heap H, and (H, e) →* (H', v),
then H' = H_initial ∖ H_freed where H_freed ⊆ dom(H_initial)
and every cell allocated during the reduction is either reachable from v
or in H_freed (freed exactly once).
```

**FBIP reuse correctness**: The `reuse(cell, T, args)` operation is semantically
equivalent to `alloc(T, args)` when `cell` is dead at that point. The proof
shows that replacing `alloc` + `decRC` with `reuse` produces the same value
with the same heap footprint.

**RC ↔ linear interaction**: Linear (`Lin`) and affine (`Aff`) bindings bypass
the RC machinery entirely — the type system guarantees uniqueness, so the
Perceus pass can insert `free` directly (no `incRC`/`decRC` needed). The
proof obligation is:

```
For a term e where all occurrences of x are Lin-typed:
  RC(e) = e[free(x) at last-use]
```
where `RC(·)` is the Perceus insertion function. The correctness of this
optimization reduces to the linear type safety theorem (§2.2).

### 2.5 Semantic Preservation — Compiler Pass Correctness

For each TIR pass we would prove that the output is semantically equivalent
to the input. This requires a denotational or big-step semantics that both
source and target interpret into.

**Lowering (AST → TIR / ANF conversion)**: The ANF conversion commutes with
evaluation — applying a substitution before or after ANF-conversion gives the
same result.

**Monomorphization**: Every call to a polymorphic function `f[T]` in the
source evaluates to the same value as the corresponding monomorphized
function `f_T` in the output.

**Defunctionalization**: The defunctionalized program evaluates to the same
result as the source program with closures. This is a well-known theorem (see
§7 for prior art) but needs to be instantiated to March's specific IR.

---

## 3. Lean 4 Project Structure

### 3.1 Directory Layout

```
march-lean/
├── lakefile.toml              # Lake build config
├── MarchLean.lean             # Root module re-exporting all submodules
│
├── MarchLean/
│   ├── Syntax/
│   │   ├── Ty.lean            # Type grammar (ty, linearity, session types)
│   │   ├── Term.lean          # Term grammar (surface calculus)
│   │   ├── Pattern.lean       # Pattern grammar and binding
│   │   └── TIR.lean           # ANF term grammar (atom, expr, fn_def)
│   │
│   ├── Semantics/
│   │   ├── SmallStep.lean     # Small-step reduction for surface calculus
│   │   ├── BigStep.lean       # Big-step (for compiler pass correctness)
│   │   ├── Heap.lean          # Heap model (finite maps, cell lifecycle)
│   │   └── RCSemantics.lean   # RC-annotated semantics for Perceus proofs
│   │
│   ├── Typing/
│   │   ├── LinearContext.lean # Context splitting, contraction, weakening
│   │   ├── TypeRules.lean     # Typing judgment ⊢ e : τ
│   │   ├── LinearityRules.lean # Linear/affine typing rules
│   │   ├── SessionTypes.lean  # Session type rules, duality
│   │   └── Polymorphism.lean  # HM schemes, generalization, instantiation
│   │
│   ├── Metatheory/
│   │   ├── Progress.lean      # Progress theorem
│   │   ├── Preservation.lean  # Subject reduction
│   │   ├── LinearSafety.lean  # Linear resource usage invariant
│   │   ├── SessionSafety.lean # Session duality + protocol compliance
│   │   └── PerceusCorrect.lean # RC insertion correctness
│   │
│   ├── Passes/
│   │   ├── ANF.lean           # ANF conversion + correctness
│   │   ├── Mono.lean          # Monomorphization + correctness
│   │   ├── Defun.lean         # Defunctionalization + correctness
│   │   └── Perceus.lean       # Perceus algorithm + correctness proof
│   │
│   └── Util/
│       ├── Finmap.lean        # Finite maps (if not using Mathlib's)
│       ├── Multiset.lean      # Multisets (for linear context as bag)
│       └── WellFounded.lean   # Termination lemmas
```

### 3.2 Dependencies

| Library | Needed For | Notes |
|---|---|---|
| `Mathlib` | Finite maps, multisets, well-founded recursion, `Finset`, decidability | Large (~200k LOC) but essential |
| `std4` | Basic utilities | Included transitively via Mathlib |
| No others | — | Avoid extra dependencies; Mathlib covers everything needed |

We do **not** need a Lean FFI to the OCaml compiler. The proofs are
purely about the mathematical model. Any correspondence to the OCaml
source (`lib/typecheck/typecheck.ml`, `lib/tir/perceus.ml`, etc.) is
established by informal audit, not by extraction or reflection.

### 3.3 Relation to the OCaml Compiler

The Lean formalization is a *model* of what the OCaml compiler implements.
The OCaml source files are the reference implementation:

| OCaml file | Lean model |
|---|---|
| `lib/ast/ast.ml` | `MarchLean.Syntax.{Ty, Term, Pattern}` |
| `lib/typecheck/typecheck.ml` (§12 Linearity) | `MarchLean.Typing.LinearityRules` |
| `lib/typecheck/typecheck.ml` (§10 Unification) | Unification is not directly modeled — we model the *type system*, not the algorithm |
| `lib/tir/tir.ml` | `MarchLean.Syntax.TIR` |
| `lib/tir/perceus.ml` | `MarchLean.Passes.Perceus` + `MarchLean.Metatheory.PerceusCorrect` |
| `lib/tir/lower.ml`, `mono.ml`, `defun.ml` | `MarchLean.Passes.{ANF, Mono, Defun}` |

---

## 4. Formalization Strategy

### 4.1 Intrinsically vs. Extrinsically Typed

**Extrinsically typed** (two-sorted): Terms are defined without types; the
typing judgment is a separate relation. Well-typedness is a predicate on terms.
This mirrors the paper presentation and is easier to relate to the OCaml source.

**Intrinsically typed** (PHOAS / well-typed by construction): Terms carry their
types in the Lean type — ill-typed terms are not representable. Preservation
comes "for free" because reductions preserve the type by construction.

**Recommendation**: Start **extrinsic**. The intrinsic approach pays off only
if you need to extract executable code from the proofs (§6). For a metatheory
verification, the extrinsic style is more tractable, especially once we add
linearity (where the context splitting complicates intrinsic representations
significantly).

**For the TIR / Perceus work**, consider switching to **intrinsically-typed ANF**
in the TIR layer. Because the TIR is in ANF and fully monomorphic, the types
are much simpler (no polymorphism, no type variables), making the intrinsic
style practical.

### 4.2 Variable Representation

**De Bruijn indices**: No alpha-equivalence issues; substitution is structural.
Works well in Lean 4. The standard choice for Lean metatheory work.

**Named variables**: More readable proofs; requires quotienting by alpha-equivalence
or a freshness monad. Harder in Lean 4.

**PHOAS (Parametric HOAS)**: Eliminates substitution lemmas entirely; works
beautifully for simply-typed calculi. Becomes complex with linear types because
the variable tracking interacts with the host (Lean) type system in subtle ways.

**Recommendation**: **De Bruijn indices** for the surface calculus.
Use a well-established Lean 4 library style (see CakeML port in Lean, or the
`Mathlib` grammar utilities). For the TIR (ANF, monomorphic), named variables
are more readable since there is no binding complexity — just flat let-chains.

### 4.3 Modeling Linear and Affine Resource Tracking

This is the most non-standard aspect of the formalization. Options:

**Option A — Typed context as a list with usage flags**
The typing context `Γ` is a list of `(name, ty, linearity, used_flag)`. The
typing rules pass `Γ` in and return a new `Γ` with usage flags updated. Linear
variables that appear in two different subterms cause the second to fail.

- Pros: Direct mirror of the OCaml implementation (see `typecheck.ml` §12 which
  uses a mutable `bool ref` "used" flag).
- Cons: Reasoning about context mutation is awkward in Lean's pure setting;
  proofs about context splitting require careful bookkeeping.

**Option B — Context splitting (substructural logic style)**
The standard theoretical presentation: the typing judgment is
`Γ₁ + Γ₂ ⊢ e₁ e₂ : τ` where `+` denotes linear context union (disjoint for
linear vars; any for unrestricted). Splitting is formalized as a ternary
relation `Split Γ Γ₁ Γ₂`.

- Pros: Clean, well-understood, mirrors the literature (Wadler, Girard).
  Proofs are compositional.
- Cons: More verbose; every rule carries explicit splits.

**Recommendation**: **Option B (context splitting)**. It is harder to set up
initially but produces cleaner metatheory proofs. There is good prior art in
Lean 4: see e.g. the Linear Haskell formalization attempts and the `lngen`
toolchain approach.

The `LinearContext.lean` module would define:

```lean4
-- A context entry with its linearity
structure Entry where
  name : Name
  ty   : Ty
  lin  : Linearity

-- Context as a list of entries
def Ctx := List Entry

-- Splitting: Γ splits into Γ₁ and Γ₂
-- Linear vars appear in exactly one of Γ₁, Γ₂
-- Unr vars appear in both (or either)
inductive Split : Ctx → Ctx → Ctx → Prop
  | nil   : Split [] [] []
  | unr   : Split Γ Γ₁ Γ₂ → Split (⟨n, τ, Unr⟩ :: Γ) (⟨n, τ, Unr⟩ :: Γ₁) (⟨n, τ, Unr⟩ :: Γ₂)
  | lin_l : Split Γ Γ₁ Γ₂ → Split (⟨n, τ, Lin⟩ :: Γ) (⟨n, τ, Lin⟩ :: Γ₁) Γ₂
  | lin_r : Split Γ Γ₁ Γ₂ → Split (⟨n, τ, Lin⟩ :: Γ) Γ₁ (⟨n, τ, Lin⟩ :: Γ₂)
  | aff_l : Split Γ Γ₁ Γ₂ → Split (⟨n, τ, Aff⟩ :: Γ) (⟨n, τ, Aff⟩ :: Γ₁) Γ₂
  | aff_r : Split Γ Γ₁ Γ₂ → Split (⟨n, τ, Aff⟩ :: Γ) Γ₁ (⟨n, τ, Aff⟩ :: Γ₂)
  | aff_drop : Split Γ Γ₁ Γ₂ → Split (⟨n, τ, Aff⟩ :: Γ) Γ₁ Γ₂  -- affine may be dropped
```

### 4.4 Small-Step vs. Big-Step Semantics

**Small-step**: Easier to prove progress (show the next step exists). More
natural for modeling loops and divergence. Required if you want to talk about
intermediate states (which matters for Perceus heap reasoning).

**Big-step**: Easier to prove semantic preservation across compiler passes
(show source and target evaluate to the same value). More concise for call-by-value.

**Recommendation**: Use **both**:
- Small-step for the surface calculus (progress + preservation).
- Big-step for the TIR and compiler pass correctness.
- Prove equivalence between the two for the surface calculus (the "adequacy" bridge).

### 4.5 Modeling Perceus RC as a Refinement

The key insight is that Perceus RC is a **bisimulation refinement** of the
abstract semantics. The abstract semantics has `alloc(T, args)` returning a
fresh opaque cell reference; the RC semantics additionally tracks a reference
count per cell and performs `free` when it reaches zero.

The formalization strategy:

1. Define an **abstract heap semantics** where cells are never freed
   (GC handles it abstractly — just a finite map from address to value).

2. Define an **RC heap semantics** where cells have counts and `free` is
   explicit.

3. Prove a **simulation**: for every run of the RC semantics, there is a
   corresponding run of the abstract semantics producing the same value, with
   the same observable behavior (modulo heap addresses). This is the correctness
   of Perceus RC insertion.

4. Prove **no double-free**: in the RC semantics, `free(addr)` is never called
   on an address with count 0. This requires showing the Perceus insertion
   algorithm maintains the invariant that each address's count equals the number
   of live references to it.

5. Prove **no use-after-free**: an address is never accessed after being freed.
   This follows from the count invariant: if count = 0, it's freed; if it's
   used, count was ≥ 1 before use.

The trickiest part is formalizing **FBIP reuse**: `reuse(dead_cell, T, args)`
is semantically a fresh allocation (since `dead_cell` is dead). The proof
obligation is that `dead_cell` is indeed dead (its RC reached 0) at the reuse
point, which requires showing the Perceus analysis correctly identifies
coincident decrement + allocate pairs.

---

## 5. Phased Roadmap with Effort Estimates

### Phase 1 — Core Simply-Typed Lambda Calculus + ADTs

**Goal**: Type soundness (progress + preservation) for STLC + algebraic data
types + pattern matching. No polymorphism, no linearity.

**Theorems**:
- `progress : ∀ e τ, ⊢ e : τ → value e ∨ ∃ e', e → e'`
- `preservation : ∀ e e' τ, ⊢ e : τ → e → e' → ⊢ e' : τ`
- Substitution lemma (required by preservation)
- Canonical forms lemma (required by progress)
- Pattern matching exhaustiveness is a typing invariant

**Lean LOC estimate**: ~1,500–2,500 LOC
- Type grammar + term grammar: ~300
- Small-step semantics: ~300
- Typing rules: ~400
- Substitution lemma: ~400 (this is always the painful part)
- Progress + preservation: ~600

**Effort estimate**: 4–6 person-weeks
(Setup is expensive: De Bruijn machinery, Lean 4 project skeleton, Mathlib
imports. Everything after this phase builds on the same scaffold.)

**OCaml reference**: `lib/ast/ast.ml` for the term structure;
`lib/typecheck/typecheck.ml` §14 for the typing rules.

**Dependencies**: None (this is the baseline).

---

### Phase 2 — HM Polymorphism

**Goal**: Extend Phase 1 with universal quantification (System F style),
type schemes, and instantiation. Prove type soundness for the polymorphic
calculus.

**Theorems**:
- Preservation holds through type application (`e[τ]`)
- Progress holds (values include type-abstracted terms)
- Substitution lemma for types (separate from term substitution)
- Principal type theorem (optional — hard, probably skip)

**Note**: We model HM as System F with explicit type abstraction/application
at the core level, not the full W/M inference algorithm. Proving the algorithm
correct (i.e., that it produces the principal type) is a separate, large
project that is probably not worth doing — the interesting safety properties
follow from the type system, not the algorithm.

**Lean LOC estimate**: ~1,000–1,500 additional LOC
- Type substitution and kind-checking: ~400
- Updated typing rules: ~300
- Updated proofs (updated substitution lemma, updated progress/preservation): ~800

**Effort estimate**: 3–4 person-weeks

**OCaml reference**: `lib/typecheck/typecheck.ml` §8 (generalization and
instantiation).

**Dependencies**: Phase 1.

---

### Phase 3 — Linear and Affine Types

**Goal**: Extend the calculus with linearity qualifiers and prove linear
resource safety.

**Theorems**:
- **Linearity invariant**: Every `Lin`-qualified variable in a well-typed
  term is used exactly once in any evaluation of that term.
- **Affine weakening**: Weakening holds for `Aff` and `Unr` variables; not
  for `Lin`.
- **Affine contraction**: Contraction holds only for `Unr`; not for `Lin`
  or `Aff`.
- **Split correctness**: The `Split` relation is sound (every valid split
  correctly partitions linear resources).

**Key challenge**: The substitution lemma must be extended to respect
linearity — substituting a linear value for a linear variable must preserve
the usage count. This is the standard "substitution preserves typing" lemma
for linear type systems, but it requires careful induction.

**Lean LOC estimate**: ~2,000–3,000 additional LOC
- Linear context and splitting: ~600
- Updated typing rules with splits: ~500
- Weakening/contraction/exchange lemmas: ~400
- Updated preservation (now must track context splitting across steps): ~800
- Linear invariant theorem: ~700

**Effort estimate**: 5–8 person-weeks
(Linear types significantly complicate every proof because the context is
consumed rather than copied. Expect the substitution lemma to be the hardest
part — it typically takes 2–3 weeks alone in a linear type formalization.)

**OCaml reference**: `lib/typecheck/typecheck.ml` §12 (linearity tracking);
`lib/tir/tir.ml` (`linearity` type); `lib/tir/perceus.ml` (the invariant
"non-last uses of a linear value are a type error" at line ~148).

**Dependencies**: Phase 1, Phase 2.

---

### Phase 4 — Session Types

**Goal**: Add binary session types (`Send`, `Recv`, `Choose`, `Offer`, `End`,
`Rec`) and prove session safety.

**Theorems**:
- **Duality**: `dual(dual(S)) = S` for all session types `S`.
- **Duality inversion**: `dual(Send(τ, S)) = Recv(τ, dual(S))`, etc.
- **Channel typing**: A pair of processes with dual session types can
  communicate without type errors.
- **Deadlock freedom** (restricted): For the simply-structured session
  types without interleaving, show that no pair of well-typed processes
  can deadlock (both waiting to receive simultaneously).

**Note**: Full deadlock freedom for interleaved sessions requires modeling
concurrent reduction — significantly more complex. The restricted version for
binary, sequential protocols is tractable.

**Lean LOC estimate**: ~2,000–3,000 additional LOC
- Session type grammar and duality: ~400
- Projection from global protocol to local type: ~500
- Channel typing rules: ~600
- Duality + protocol compliance proofs: ~1,000
- Deadlock freedom (simplified): ~800

**Effort estimate**: 5–8 person-weeks
(Session types are well-studied but the mechanization is non-trivial because
you need a concurrent or interleaved reduction relation. The deadlock-freedom
proof is the hardest part. Start with just duality and compliance; deadlock
freedom can be Phase 4b.)

**OCaml reference**: `specs/session-types-plan.md` (the design document);
`lib/typecheck/typecheck.ml` (session types are not yet fully implemented in
the OCaml source at time of writing — the formalization would be ahead of the
implementation).

**Dependencies**: Phase 1, Phase 3 (session channels are linear).

---

### Phase 5 — Perceus RC Verification

**Goal**: Prove the Perceus RC insertion algorithm correct — every allocation
is eventually freed, no double-free, no use-after-free.

**Theorems**:
- **RC insertion correctness (semantic)**: `eval(RC(e)) = eval(e)` under
  the abstract heap semantics (Perceus output is observationally equivalent
  to the source).
- **No double-free**: In the RC heap semantics, `free(addr)` is never called
  on an address that has already been freed.
- **No use-after-free**: `read(addr)` is never called on an address that has
  been freed.
- **FBIP reuse soundness**: `eval(reuse(dead, T, args)) = eval(alloc(T, args))`
  when `dead` is dead at that program point.
- **RC-linear interaction**: For a `Lin`-typed binding, Perceus inserts
  `free` (not `decRC`), and this is sound because the type system guarantees
  uniqueness (no other live reference).

**Key challenges**:
- The heap model is a finite map; `alloc` produces a fresh address. In Lean
  this requires a monad or a state-passing style.
- The liveness analysis underlying Perceus (backwards dataflow) must be
  formalized as a computable function and proved correct against the
  operational semantics notion of "last use".
- FBIP requires showing the dead cell is indeed dead — the RC insertion
  algorithm's coincident-decrement detection must be proved sound.

**Lean LOC estimate**: ~4,000–6,000 additional LOC
- Heap model (finite map, fresh address generation): ~600
- RC-annotated operational semantics: ~800
- Liveness analysis formalization + correctness: ~1,200
- RC insertion algorithm (Lean implementation): ~800
- Semantic equivalence proof: ~1,500
- No-double-free + no-use-after-free: ~1,000
- FBIP reuse soundness: ~500

**Effort estimate**: 10–16 person-weeks
(This is the highest-risk phase. Perceus is original research; there is no
existing mechanized proof to reference. The liveness-analysis correctness
proof is the core technical challenge — expect it to be 30–40% of the work.)

**OCaml reference**: `lib/tir/perceus.ml` (the algorithm — the Lean
formalization should closely follow this file's structure); `specs/perceus.md`
(the algorithm spec); `lib/tir/tir.ml` (the `EIncRC`, `EDecRC`, `EFree`,
`EReuse` constructors).

**Dependencies**: Phase 1, Phase 3 (linear/affine types and Perceus are
deeply intertwined).

---

### Phase 6 — Compiler Pass Correctness

**Goal**: Prove semantic preservation for the three main TIR passes: ANF
lowering, monomorphization, defunctionalization.

**Theorems per pass**:

**ANF lowering** (`lib/tir/lower.ml`):
- The ANF conversion of `e` evaluates to the same value as `e`.
- Formally: `eval_source(e) = eval_tir(anf(e))` under the big-step semantics.
- The key lemma is that let-floating commutes with evaluation in a
  call-by-value setting.

**Monomorphization** (`lib/tir/mono.ml`):
- `eval_tir(mono(f[T])) = eval_tir(f)[T]` — specialized function evaluates
  the same as the generic function instantiated at `T`.
- Requires showing type substitution commutes with evaluation.

**Defunctionalization** (`lib/tir/defun.ml`):
- The defunctionalized program evaluates to the same result as the source
  with first-class closures.
- This is a classic result (Reynolds 1972) but the mechanized proof is
  non-trivial, especially for higher-order functions. See Guillemette &
  Monnier (2007) for a typed defunctionalization formalization.

**Lean LOC estimate**: ~3,000–5,000 additional LOC
- Big-step semantics for TIR: ~600
- ANF correctness: ~800
- Mono correctness: ~1,000
- Defun correctness: ~1,500
- Infrastructure (bisimulation, simulation lemmas): ~500

**Effort estimate**: 8–14 person-weeks
(Defunctionalization correctness is the hardest; it requires a logical
relation argument for the higher-order case.)

**OCaml reference**: `lib/tir/lower.ml`, `lib/tir/mono.ml`, `lib/tir/defun.ml`.

**Dependencies**: Phase 1, Phase 2 (for monomorphization), Phase 5 (Perceus
runs after defunctionalization, so the pass order matters).

---

### Summary Table

| Phase | Theorems | Est. LOC | Est. Weeks | Depends On |
|---|---|---|---|---|
| 1: STLC + ADTs | Progress, Preservation | 1,500–2,500 | 4–6 | — |
| 2: HM Polymorphism | Preservation for ∀ | 1,000–1,500 | 3–4 | 1 |
| 3: Linear + Affine Types | Linearity invariant | 2,000–3,000 | 5–8 | 1, 2 |
| 4: Session Types | Duality, compliance | 2,000–3,000 | 5–8 | 1, 3 |
| 5: Perceus RC | No double-free, FBIP | 4,000–6,000 | 10–16 | 1, 3 |
| 6: Pass Correctness | ANF/mono/defun equiv | 3,000–5,000 | 8–14 | 1, 2, 5 |
| **Total** | | **~13,500–21,000** | **35–56 weeks** | |

These are optimistic estimates for someone already fluent in Lean 4 and
substructural type theory. For a team ramping up on both, multiply by 1.5–2×.

---

## 6. Extraction Strategy

Can we extract executable OCaml from the Lean proofs?

**Short answer**: Partially, but it's probably not worth the effort.

### 6.1 What Lean 4 Can Extract

Lean 4 compiles to C via a native code generator. It cannot directly extract
to OCaml. To get OCaml-executable code from Lean proofs, you would need to:

1. Write the Lean algorithms (the Perceus insertion function, the
   liveness analysis, etc.) in **definitional/computational** style (not just
   as propositions), so Lean can evaluate them.
2. Use `#eval` in Lean to test the algorithms.
3. Port the verified algorithms to OCaml by hand, using the Lean proofs as a
   specification.

### 6.2 What Is Realistic

The most valuable outcome is **not extraction** but **specification clarity**:

- The Lean formalization serves as a ground-truth spec.
- Each time the OCaml implementation is changed (e.g., a new FBIP optimization,
  a change to the linearity rules), the Lean spec documents what invariants
  must hold.
- Bugs in the OCaml implementation can be found by checking them against the
  Lean spec.

### 6.3 Reflexion / Proof-Carrying Code

An alternative to extraction is **proof-carrying code**: the Lean proofs are
attached to the compiled binary as certificates. This is theoretically possible
but practically not done outside academic prototypes.

**Recommendation**: Treat the Lean proofs as a **design specification and
audit tool**, not as a source of executable code. The OCaml compiler remains
the implementation; the Lean proofs verify the design.

---

## 7. Prior Art

### 7.1 CompCert (Leroy, 2006–present)

The gold standard for verified compilers. CompCert proves semantic
preservation for a significant subset of C, compiled all the way to PowerPC
assembly. Key lessons:

- Use **semantic preservation by simulation**: a forward or backward
  simulation between the source and target semantics.
- **Every compiler pass** gets its own simulation proof. The overall
  correctness follows by composition.
- The Coq/Lean mechanization is ~100,000 LOC for a production-quality compiler.
  Expect March's Lean proofs to be at least 20,000 LOC for complete coverage.
- CompCert's biggest lesson: **start with the simplest core and extend
  incrementally**. They spent years on the base before adding optimizations.

### 7.2 CakeML (Kumar et al., 2014–present)

A verified ML compiler in HOL4. CakeML proves a full verified stack from
source language to machine code. Key lessons:

- Formalizing a **realistic ML-like language** (with polymorphism, closures,
  garbage collection) is much harder than formalizing STLC. Expect CakeML-scale
  effort for a full March formalization.
- CakeML's **big-step semantics with a fuel parameter** handles
  non-termination cleanly.
- Their **defunctionalization correctness** proof is directly relevant to
  Phase 6 of this plan.

### 7.3 Linear Haskell Formalization (Bernardy et al.)

The core calculus of Linear Haskell uses the same context-splitting approach
recommended in §4.3. Their mechanized proofs (in Agda) demonstrate:
- The substitution lemma for linear type systems requires a split-compatible
  formulation.
- Linearity interacts with polymorphism in subtle ways — the instantiation of
  a polymorphic function must respect the linearity of the argument.

Directly applicable to Phase 3.

### 7.4 Stacked Borrows (Jung et al., 2020)

Rust's alias analysis model verified in Coq (via Iris). Key lessons for
March's Perceus work:

- **Ownership reasoning** for heap-allocated values requires a rich semantic
  model (Iris uses a step-indexed, higher-order separation logic).
- For Perceus (which is simpler than Stacked Borrows — no borrowing, just
  RC), a simpler heap model suffices. But the key insight from Stacked Borrows
  applies: **the invariant must be stated in terms of an abstract model of the
  heap** (what cells exist, who owns them), not in terms of the concrete
  reference-count numbers.
- The "no use-after-free" theorem for Stacked Borrows is the closest existing
  mechanized proof to what Phase 5 needs.

### 7.5 Typed Defunctionalization (Guillemette & Monnier, 2007)

A mechanized proof of defunctionalization correctness for a polymorphic
lambda calculus, using a logical relations argument. This is the primary
reference for Phase 6's defunctionalization correctness proof.

### 7.6 Koka + Perceus (Reinking et al., 2021)

The original Perceus paper ("Perceus: Garbage Free Reference Counting with
Reuse", PLDI 2021) by the Koka team. It includes informal correctness
arguments but **no mechanized proofs**. March's Phase 5 would be the first
mechanized Perceus correctness proof, if completed — potentially publishable
as a standalone research contribution.

### 7.7 Session Types Formalization (Gay & Hole; Wadler; Lindley & Morris)

Multiple mechanized session type formalizations exist:
- Gay & Hole (2005): original session type safety proof — no mechanization.
- Wadler (2012): "Propositions as Sessions" — relates session types to
  linear logic, mechanized in Agda.
- Lindley & Morris (2016): CP (Classical Processes) mechanized in Coq.

The Lean 4 formalization would most closely follow the approach of
Wadler (2012), adapted to March's concrete protocol syntax.

---

## 8. Risks and Alternatives

### 8.1 Technical Risks

**Risk: Linear types complicate every proof.**
Linear type systems famously multiply the proof burden. The substitution
lemma — trivial for simple type systems — becomes a 100-line proof for
linear systems. Every theorem that works by induction on typing derivations
must thread context splitting throughout the induction. **Mitigation**: Use
established patterns (Wadler, Bernardy et al.) rather than inventing new
approaches. Allocate extra time to Phase 3 before proceeding.

**Risk: Perceus liveness analysis is hard to formalize.**
The liveness analysis is a backwards dataflow over the ANF term structure.
Proving it correct — that its output agrees with the operational notion of
"last use" — is the core technical challenge of Phase 5. There is no prior
mechanized work on Perceus to reference. **Mitigation**: Formalize a simpler
"obvious" Perceus that inserts RC ops without optimization first; prove it
correct; then separately prove the elision/FBIP optimizations preserve
correctness.

**Risk: FBIP reuse is more complex than expected.**
The FBIP detection algorithm (`specs/perceus.md` Phase 3 — RC Elision and
FBIP) requires reasoning about the *simultaneity* of a decrement and an
allocation of the same shape. Formalizing "same shape" (same constructor,
same argument types) in the presence of monomorphization is non-trivial.
**Mitigation**: Scope Phase 5 to cover just the basic RC correctness; treat
FBIP as a separate sub-phase (Phase 5b) that can be deferred.

**Risk: Session type deadlock freedom requires concurrent reduction.**
Deadlock freedom for binary session types traditionally requires reasoning
about two concurrent processes. Formalizing a concurrent reduction relation
in Lean 4 is significantly harder than sequential reduction. **Mitigation**:
Prove a weaker "protocol compliance" property first (each side's actions
match their local session type) and defer the full deadlock-freedom theorem.

**Risk: Scale.**
Even Phase 1 alone is 1,500–2,500 LOC and 4–6 weeks. The full plan is
35–56 weeks minimum. **Mitigation**: Each phase is independently valuable.
Stopping after Phase 1 still gives you verified type soundness for the core
calculus. Stopping after Phase 3 gives you verified linear type safety —
probably the highest-value milestone.

### 8.2 The "Separation" Risk

March's OCaml implementation and the Lean formalization would inevitably
diverge as the compiler evolves. Each change to the type checker
(`lib/typecheck/typecheck.ml`) or TIR (`lib/tir/`) that is not reflected in
the Lean proofs reduces the value of the proofs. **Mitigation**: Keep the
Lean formalization at the "core calculus" level, which changes more slowly
than the surface language. Accept that the proofs verify the *design*, not
the *implementation*.

### 8.3 Alternatives to Full Mechanization

If the full Lean project is too expensive, consider these intermediate options:

| Alternative | Effort | What You Get |
|---|---|---|
| **QuickCheck / fuzz testing** of the type checker | 1–2 weeks | Bug-finding, not proof |
| **Property-based testing** of Perceus RC insertion | 2–4 weeks | Increases confidence in Perceus, not a proof |
| **Paper proof** of core soundness (published) | 8–12 weeks | Peer-reviewed argument; no machine-checking |
| **Mechanize Phase 1 only** | 4–6 weeks | Verified STLC + ADTs; useful baseline |
| **Mechanize Phase 1 + Phase 3** | ~16 weeks | Verified linear type safety; probably the sweet spot |
| **Full Phase 1–6** | 35–56+ weeks | Complete verified core; research-grade |

---

## 9. Decision Criteria — Cost-Benefit Analysis

### 9.1 Benefits

| Benefit | Phases That Provide It |
|---|---|
| Machine-checked type soundness (progress + preservation) | 1 |
| Verified linear resource safety — no leaked resources | 3 |
| Verified session type duality — no protocol violations | 4 |
| Verified Perceus RC — no double-free, no UAF | 5 |
| Verified compiler passes — output semantics = input semantics | 6 |
| Design clarity — formalization forces ambiguities to surface | All |
| Research novelty (first mechanized Perceus correctness proof) | 5 |
| Publication-worthy result | 3, 4, or 5 individually |

### 9.2 Costs

| Cost | Phases |
|---|---|
| ~4–6 weeks of infrastructure setup (Lean 4 project, De Bruijn, Mathlib) | 1 |
| ~35–56 total person-weeks for the full plan | All |
| Ongoing maintenance as the language evolves | All |
| Risk of getting stuck on hard lemmas (linear substitution, Perceus liveness) | 3, 5 |

### 9.3 When to Do This

**Do it now** if:
- The core type system design (linear types + session types + Perceus) is
  considered stable. Formalizing a moving target wastes effort.
- There is at least one person with Lean 4 and substructural type theory
  experience, or willingness to acquire it.
- The goal is research publication (mechanized Perceus would be novel) or
  high-assurance safety (the kind of language where a type safety bug would
  be catastrophic).
- Phase 1–3 can be done as a bounded spike (16 weeks) to determine whether
  the approach is tractable before committing to Phases 4–6.

**Defer** if:
- The core design is still actively changing (linear types, session type
  syntax, Perceus FBIP heuristics).
- The implementation is not yet stable enough to know what to verify.
- Engineering bandwidth is needed for the compiler itself.
- The primary goal is "a working compiler" rather than "a verified compiler".

### 9.4 Recommended Decision Path

1. **Now**: Do nothing. Let the language design stabilize.
2. **When linear types + session types are feature-complete in the OCaml
   compiler**: Commission a 2-week spike to build Phase 1 and get a real
   estimate of difficulty.
3. **After the spike**: Decide whether to invest in Phase 3 (linear type
   safety, ~8–16 weeks) as the first publishable milestone.
4. **Phase 5 (Perceus)**: Only if Phase 3 is successful and there is research
   appetite. This is the most novel and most risky part.

---

## Appendix A — Relevant OCaml Source Files

| Lean module | OCaml source | Notes |
|---|---|---|
| `MarchLean.Syntax.Ty` | `lib/ast/ast.ml` (type `ty`) | Surface type grammar |
| `MarchLean.Syntax.Term` | `lib/ast/ast.ml` (type `expr`) | Surface expression grammar |
| `MarchLean.Typing.TypeRules` | `lib/typecheck/typecheck.ml` §14 | `infer_expr`, `check_expr` |
| `MarchLean.Typing.LinearityRules` | `lib/typecheck/typecheck.ml` §12 | `enter_linear`, `check_used` |
| `MarchLean.Syntax.TIR` | `lib/tir/tir.ml` | `ty`, `var`, `atom`, `expr`, `fn_def` |
| `MarchLean.Passes.Perceus` | `lib/tir/perceus.ml` | Liveness + RC insertion algorithm |
| `MarchLean.Typing.SessionTypes` | `specs/session-types-plan.md` | Session types not yet in OCaml source |
| `MarchLean.Passes.ANF` | `lib/tir/lower.ml` | ANF conversion |
| `MarchLean.Passes.Mono` | `lib/tir/mono.ml` | Monomorphization |
| `MarchLean.Passes.Defun` | `lib/tir/defun.ml` | Defunctionalization |

## Appendix B — Key References

- Leroy, X. (2009). "Formal verification of a realistic compiler." *CACM*. (CompCert)
- Kumar et al. (2014). "CakeML: A Verified Implementation of ML." *POPL*. (CakeML)
- Bernardy et al. (2018). "Linear Haskell." *POPL*. (Linear types formalization)
- Reinking et al. (2021). "Perceus: Garbage Free Reference Counting with Reuse." *PLDI*.
- Jung et al. (2020). "Stacked Borrows." *POPL*. (Ownership/aliasing verification)
- Guillemette & Monnier (2007). "A Type-Preserving Defunctionalization Translation in Haskell." *ICFP*.
- Wadler (2012). "Propositions as Sessions." *ICFP*. (Session types + linear logic)
- Gay & Hole (2005). "Subtyping for Session Types in the Pi Calculus." *Acta Informatica*.
- Girard (1987). "Linear Logic." *Theoretical Computer Science*. (Original linear logic)
