# P6 — Unboxed Single-Field Constructors (v1)

**Status:** Design approved 2026-06-20. Supersedes the "Research" framing in
`specs/optimizations.md` §P6 for the v1 scope defined here.

## Motivation

Single-field constructors — newtype wrappers (`type UserId = UserId(Int)`) and
the pervasive `Option` type — currently heap-allocate a cell with a
reference-count word on every construction, even when the value merely crosses
a function boundary. `None` itself allocates (`march_alloc(16)`, tag 0).

A measurement on this codebase: a tight loop where a function returns
`Option(Int)` and the caller pattern-matches it ran **~12× slower** than the
identical arithmetic without the `Some` wrapper (1.58s vs 0.13s) — pure
allocation + RC + pointer-chase cost. `Option`/`Result`/newtypes are everywhere
in idiomatic March, so this is broad, real, *dynamic* work (unlike P1, whose
static-only change measured ~0%).

The local "construct-then-immediately-match" case is already handled by P11
(beta-adt). The remaining value is entirely in the **boundary-crossing** case —
`Option` returned from a function, stored in a list, held in a record — which
requires a genuine type-level representation change, not escape-gating.

## Scope (v1)

In scope:

- **Newtypes** — exactly one variant, exactly one field
  (`type T = T(payload)`). Represented as the raw payload everywhere, for **any**
  payload type. Zero-cost: no allocation, no tag, no sentinel (there is nothing
  to disambiguate).
- **Option-shaped niche** — exactly two variants, one nullary and one
  single-field (the shape of `type Option = None | Some('a)`). Represented as
  `None = 0`, `Some(x) = x`, using the guaranteed-free raw-`0` niche.

Out of scope (remain boxed, unchanged):

- `Result` (two payload-carrying variants — the raw-`0` niche cannot distinguish
  the two payloads).
- Multi-field unboxing (`type Point = Point(Int, Int)`).
- Single-field variants inside larger (3+ variant) ADTs.

## Soundness: the raw-`0` niche

March uses a uniform `i64` value model: odd low bit = tagged immediate
(`(n<<1)|1`), even = heap pointer, and `march_alloc` never returns `0`.
Therefore **raw `0` is a value no valid March value occupies**, and it is the
niche for `None`.

The niche is sound for `None | Some(payload)` only when a valid `Some` payload
can never be raw `0` in its slot:

| Payload class | In-slot form | Niche? | Cost |
|---|---|---|---|
| Pointer (`String`, `List`, records, user ADTs, tuples, closures) | heap ptr, always nonzero | **yes** | zero-cost |
| `Int` | tagged `(v<<1)|1`, always odd → never 0 | **yes** | one shift per access |
| `Float` | `0.0` bitcasts to raw `0` | no → **boxed fallback** | — |
| `Unit` | represented as `i64 0` | no → **boxed fallback** | — |
| `Bool` | `false` may be raw `0` | no → **boxed fallback** | — |
| nested `Option` (`Some(None)`) | `None = 0` | no → **boxed fallback** | — |

Newtypes need no soundness check — with a single variant there is never a
sentinel to collide with, so the payload may be anything (including `Float`,
`Unit`, or another newtype).

`Option(UserId)` where `UserId` is itself a newtype-over-`Int` resolves
recursively: the payload's *effective* representation (tagged `Int`) is what the
niche rule sees, so it niches with `tagged = true`.

## Architecture: derived representation table (post-mono)

March fully monomorphizes, so representation is a pure function of the concrete
type and can be derived without changing the TIR `ty` algebra.

New module `lib/tir/repr.ml`:

```
type repr =
  | Boxed                                   (* today's heap cell *)
  | Newtype of Tir.ty                       (* represented as the raw payload *)
  | Niche   of { payload : Tir.ty; tagged : bool }   (* None=0, Some(x)=x *)

val repr_of_ty : type_defs -> Tir.ty -> repr
```

Properties:

- **Pure + memoized.** Same monomorphic type → same `repr`, so all consultation
  sites agree by construction; no state is threaded.
- **Terminating.** Classification of a `TCon` may recurse into its payload's
  repr (e.g. `Option(UserId)`). An in-progress guard returns `Boxed` on any
  cyclic dependency, so the function always terminates. Practical newtype/niche
  types are non-recursive (a recursive single-field type is an infinite type and
  will not typecheck), so the guard only ever fires defensively.
- **`ty` is unchanged.** It is matched in dozens of places; leaving it alone
  keeps the blast radius to the three consultation sites below.

## Three consultation sites

### 1. Construction — `lib/tir/llvm_emit.ml` (EAlloc)

- `Newtype(_)`: emit the payload atom directly. No `march_alloc`.
- `Niche{tagged}`: `None` → constant `0`; `Some(x)` → `x`, tagged `(v<<1)|1`
  iff `tagged`.

### 2. Pattern match — `lib/tir/llvm_emit.ml` (`emit_case`)

- `Newtype(_)`: bind the single field variable directly to the scrutinee; one
  branch, no tag load.
- `Niche{tagged}`: `if scrut == 0 then <None branch> else { v = (untag iff
  tagged) scrut; <Some branch> }`.

### 3. Reference counting — `lib/tir/perceus.ml`

Consult `repr` to decide heap-ness:

- `Niche{tagged=false}` and `Newtype` over a pointer payload → the value *is* the
  payload pointer; RC forwards to it. `None = 0` is an automatic no-op
  (`march_incrc`/`decrc` already early-return on `!IS_HEAP_PTR`).
- `Niche{tagged=true}` and `Newtype` over a scalar payload → scalar value; insert
  no RC.

## Runtime ABI

Runtime `Option` construction already funnels through three helpers
(`runtime/march_runtime.c`):

- `make_none()` → return `0`.
- `make_some_i64(v)` → return `(v<<1)|1`.
- `make_some_ptr(p)` → return `p`.

Plus: convert the ~3 inline sites that bypass these helpers (e.g. the
`march_alloc(16); /* tag stays 0 = None */` in the int parser) to call them; add
`MARCH_IS_NONE(o) ((o)==0)` and payload-extract macros and route any C code that
*reads* `Option` by tag/offset through them (the riskier surface — must be
audited).

This must land atomically with the codegen change: compiled code and the runtime
must agree on representation within a single build. (The CAS cache already keys
on runtime source digests, so rebuilds invalidate correctly.)

## Interaction with existing passes

- **beta-adt (P11):** becomes mostly moot for niched/newtype types (there is no
  `EAlloc` left to fuse) but remains correct. The repr rewrite happens in emit,
  downstream of the opt fixed-point loop, so cprop/fold/inline are unperturbed.
- **FBIP / constructor reuse (P8):** simply does not apply — there is no heap
  cell to reuse.

## Phasing

Each phase is independently mergeable.

1. **`Repr` module + classification + unit tests.** Pure analysis, no behavior
   change. Tests assert the classification of each shape (newtype, Option-of-ptr,
   Option(Int), Option(Float/Unit/Bool/nested) → Boxed, Result → Boxed, recursive
   `Option(UserId)`).
2. **Newtype unboxing.** Construct + match + RC consultation for `Newtype` only.
   No sentinel, lowest risk. Ships as its own milestone.
3. **Option niche.** Construct + match + RC for `Niche`; runtime helper/macro
   flip + tag-reader audit. End-to-end tests under ASan / `MARCH_SANITIZE`:
   Option-of-ptr, Option(Int), nested-Option fallback, Option(Float) fallback,
   Option-in-list, cross-boundary return, RC stress. Full stdlib suite is the
   integration gate.
4. **Validation.** Re-run the 12× microbenchmark to confirm the win; update
   `specs/optimizations.md` §P6, `specs/todos.md`, `specs/progress.md`.

## Testing & risk

The highest-risk area is RC correctness on niched `Option`-of-pointer crossing
boundaries — the double-free / use-after-free class this codebase has fought
(see the `is_apply_fn` Perceus guard and the `sort_by` history).

Mitigations:

- Phase 1 is pure analysis (no risk); phase 2 (newtypes) carries no sentinel and
  no runtime change, so it is low-risk and lands first.
- Every phase-3 end-to-end test runs under the sanitizer.
- The stdlib suite is dense with `Option`/`Result` usage and is the regression
  gate for phase 3.
- Classification is conservative: anything not provably sound falls back to
  `Boxed`. Correctness is never traded for unboxing.

## Success criteria

- The 12× microbenchmark (Option(Int) across a boundary) shows a large speedup
  (target: within a small constant of the unwrapped arithmetic).
- Full test suite green, including under the sanitizer for the phase-3 e2e set.
- No representation change observable in program semantics: every in-scope type
  behaves identically to its boxed form, only faster.
