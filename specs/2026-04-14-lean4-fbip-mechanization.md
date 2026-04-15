# Lean 4 Mechanization: Perceus, Linear Contexts, and FBIP Soundness

> **Status: implemented.** 22 definitions + theorems, no `sorry`s, builds
> cleanly under `leanprover/lean4:v4.29.0`.

This document records the first completed chunk of the plan in
[`lean4-metatheory-plan.md`](./lean4-metatheory-plan.md): a mechanized
proof that March's Perceus + linearity + FBIP story is internally coherent
from the static type system down to the heap's reference count.

---

## 1. What exists

A standalone Lean 4 project at `/Users/80197052/code/march-lean/`:

```
march-lean/
├── lakefile.toml
├── lean-toolchain               leanprover/lean4:v4.29.0
├── MarchLean.lean               root — imports the three modules below
└── MarchLean/
    ├── Perceus.lean             RC-insertion decision
    ├── LinearContext.lean       Split relation + FBIP uniqueness
    └── Heap.lean                Runtime heap model + FBIP soundness
```

No dependencies beyond core Lean 4 (no Mathlib).

---

## 2. The chain that is proved

The end-to-end claim, expressed informally:

> For any Lin-qualified binding `x : τ` with `needs_rc τ = true`:
>
> 1. **Static uniqueness** — under any context split, `x` ends up in
>    *exactly* one half (never both, never neither).
> 2. **Perceus correctness** — when `x` is dropped, RC-insertion emits
>    `EFree (AVar x)`, not `EDecRC (AVar x)`.
> 3. **Heap uniqueness** — in any RC-consistent runtime state, the heap
>    cell at `x`'s address has `rc = 1`.
> 4. **In-place reuse soundness** — overwriting that cell does not affect
>    rc at any other address; no other binding could have observed it.

Each link is a mechanized theorem. The chain is fully formal; see §5 for
the gaps between this chain and "March's compiler is correct."

---

## 3. What is proved, file by file

### 3.1 `MarchLean/Perceus.lean`

Transcribes `lib/tir/perceus.ml` lines 438–446 — the `drop_var` decision
for RC insertion.

| Theorem | Statement |
|---|---|
| `lin_drop_is_free` | `v.v_lin = Lin ∧ needs_rc v.v_ty → drop_var v e = ESeq (EFree (AVar v)) e` |
| `aff_drop_is_free` | Same conclusion for `Aff` — affine bindings also get `EFree` |
| `decrc_implies_unr` | Contrapositive: `drop_var` emits `EDecRC` *only* for `Unr` |
| `drop_scalar_noop` | If `needs_rc = false`, `drop_var v e = e` regardless of linearity |

These establish that the OCaml compiler's RC-insertion decision matches
the type-system's intended semantics — Lin = unique ownership = direct
free, Unr = shared = reference-counted decrement.

### 3.2 `MarchLean/LinearContext.lean`

Formalizes the substructural context-splitting rules. Uses the classical
`Split Γ Γ₁ Γ₂` inductive relation rather than March's mutable "used
flag" implementation; the two are equivalent and the inductive form
produces cleaner proofs.

| Theorem | Statement |
|---|---|
| `Split.comm` | Splitting is commutative: `Split Γ Γ₁ Γ₂ → Split Γ Γ₂ Γ₁` |
| `Split.lin_preserved` | Lin entries go to *at least one* side (never dropped) |
| `Split.unr_in_both` | Unr entries go to *both* sides (contraction) |
| `Split.weaken_aff` | Aff entries *can* be dropped (weakening) |
| `Split.lin_countIf` | For Lin-only predicates, splitting preserves the exact count: `\|Γ\|_p = \|Γ₁\|_p + \|Γ₂\|_p` |
| `Split.fbip_uniqueness` | A singleton Lin entry goes to *exactly one* of `Γ₁`, `Γ₂` — the no-aliasing invariant |

`Split.fbip_uniqueness` is the headline result: "exactly one" at the type
level is what makes in-place reuse possible at all.

**Proof technique note.** The count theorem `Split.lin_countIf` is
parameterized by a predicate `p : Entry → Bool` rather than by equality
on `Entry`. This sidesteps the need for `DecidableEq` on `Ty`, whose
nested `List Ty` makes structural `deriving DecidableEq` fail in Lean
4.29. In practice, `p` instantiates to "matches this name" or "matches
this specific entry" — exactly the scenarios needed to state FBIP.

### 3.3 `MarchLean/Heap.lean`

Bridges from the static type system to runtime reference counting.

**Data:**

| Declaration | Meaning |
|---|---|
| `Addr := Nat` | Heap addresses |
| `HeapCell { rc : Nat }` | A heap cell carrying an rc (payload omitted — irrelevant to uniqueness) |
| `Heap := List (Option HeapCell)` | Heap indexed by address |
| `RBinding { entry : Entry, addr : Addr }` | Static typing entry paired with its storage address |
| `RCtx := List RBinding` | The dynamic counterpart of `Ctx` |
| `RCtx.aliases (a)` | Number of runtime bindings pointing to `a` |
| `RCtx.Consistent h` | `∀ a r, h.rcAt a = some r → r = Γr.aliases a` — rc tracks alias count |

**Theorems:**

| Theorem | Statement |
|---|---|
| `RCtx.aliases_eq_countP` | Connects the abstract `aliases` to `List.countP` via a core lemma |
| `RCtx.aliases_eq_one` | Static uniqueness transfers: `countP = 1 → aliases = 1` |
| `fbip_rc_one` | **Core heap theorem.** Consistent heap + alias count 1 + Lin binding → `h.rcAt b.addr = some 1` |
| `fbip_soundness` | `fbip_rc_one` packaged with the uniqueness hypothesis expressed at the `countP` level |
| `fbip_chain_complete` | Explicit bridge from `Split.fbip_uniqueness` (static) through alias-count equality to `rc = 1` (heap) |
| `overwrite_preserves_other_rc` | In-place mutation at address `a` preserves rc at every `a' ≠ a` — the operational "payoff" of FBIP |

The last theorem is what justifies in-place reuse operationally: if you
have proved via `fbip_soundness` that `rc = 1` at the matched cell, and
no other address is touched by the overwrite, then no consistency
invariant is broken for any *other* binding.

---

## 4. The static-to-dynamic bridge — why it matters

The plan document (§2.4 in `lean4-metatheory-plan.md`) poses FBIP
correctness as: "if a variable has `Lin` or `Aff` qualifier, its RC is
guaranteed to be 1 when consumed, and `reuse` is safe."

The plan treats this as a *single* claim. In the mechanization it's
visible as two distinct pieces:

- **Static half** (`Split.fbip_uniqueness`) — no *typing derivation*
  can place a Lin binding on both sides of a context split. This is a
  property of the type system, provable by induction on the split
  relation alone.

- **Dynamic half** (`fbip_soundness`) — in any heap state where rc
  consistently tracks alias count, a Lin binding backed by exactly one
  alias has `rc = 1`.

The bridge (`fbip_chain_complete`) says: if the compiler emits runtime
bindings that respect the static uniqueness — i.e., each static Lin
binding corresponds to a distinct runtime address — then the two halves
compose and FBIP reuse is sound.

Making this decomposition explicit is one of the payoffs of
mechanization: the informal claim bundles several invariants that are
worth keeping separate.

---

## 5. Honest limitations

What is *not* proved, ordered from most to least important:

1. **Operational semantics of TIR.** There is no reduction relation
   `e → e'`. Consistency (`RCtx.Consistent h`) is a standing hypothesis,
   not an invariant preserved under evaluation. A full proof would
   define small-step rules for `alloc`, `incRC`, `decRC`, `free`,
   `reuse`, and show each preserves consistency.

2. **Typing judgment.** There is no `Γ ⊨ e : τ` relation in Lean. The
   connection between March's typechecker and the `Split` relation is
   informal: we claim (not prove) that well-typed programs produce
   derivations respecting `Split`.

3. **Allocator correctness.** `fbip_chain_complete` takes
   `RCtx.AddrInjective` as a hypothesis — that distinct bindings have
   distinct addresses. A full proof would show that `malloc` returns
   fresh addresses and that `free`/`reuse` maintain injectivity.

4. **Subject reduction.** The classical "types are preserved under
   reduction" claim is absent. This is where the plan's §2.1 lives; we
   haven't touched it.

5. **Progress.** Same.

6. **HM polymorphism, session types, effects, concurrency** — all
   orthogonal and untouched. See the plan for scope of a full effort.

The chunk that *is* proved covers the invariants that connect
linearity-at-the-type-system-level to the RC discipline the compiler
actually emits. This is the most dense interaction in March's design,
and where informal reasoning was weakest.

---

## 6. Building and verifying

Requirements:

- `elan` (Lean toolchain manager) — auto-installs Lean 4.29.0 from
  `lean-toolchain`
- No other dependencies (no Mathlib)

Build:

```bash
cd /Users/80197052/code/march-lean
~/.elan/bin/lake build
```

Expected output: `Build completed successfully`. Any `sorry`, `admit`,
or warning is a regression.

Check for regressions:

```bash
cd /Users/80197052/code/march-lean
grep -n 'sorry\|admit' MarchLean/*.lean   # should return nothing
~/.elan/bin/lake build 2>&1 | grep -iE 'warn|error|sorry'   # should return nothing
```

---

## 7. Where to go next

In descending order of value-per-effort:

- **(multi-session)** Formalize the TIR operational semantics and prove
  `RCtx.Consistent` preservation under each reduction step. This turns
  the current *static* bridge into an operational claim about the full
  Perceus RC discipline.

- **(multi-session)** Prove subject reduction and progress for the core
  ANF calculus. Mostly textbook; the payoff is catching interaction
  bugs with linearity that informal proofs don't cover.

- **(multi-week)** Session types. Binary session duality is a one-hour
  proof; progress and subject reduction for the process calculus is
  much harder. MPST is research-paper-scale and should be deferred.

- **(low priority)** Generalize the Lin-only count theorem to a full
  count-preservation statement across all linearity qualifiers (Unr
  doubles, Aff bounds). Interesting for completeness; unlocks nothing
  concrete.

What is *not* a good next step: proving that trivial peephole rewrites
like string constant folding are semantics-preserving. The rewrites are
obvious by inspection; the proofs teach nothing. Pick targets where
getting it wrong has non-obvious consequences — that's where
mechanization actually earns its keep.
