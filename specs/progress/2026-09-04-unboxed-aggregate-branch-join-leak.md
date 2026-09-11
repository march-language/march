# Unboxed small aggregate built inside a branch leaked one cell per construction

**Landed:** 2026-09-04. Regression in the unboxed-small-scalar-aggregates
feature (`specs/progress/2026-09-03-unboxed-small-scalar-aggregates.md`,
commit `c0275445`, merged as `7419c689`). Found by an external project
building against `main`.

## Symptom

A single-constructor variant whose fields are all scalars and whose arity is
2..4 is represented as an inline LLVM struct value. Constructing one **inside a
branch** leaked one heap object per construction. Measured with the runtime's
own live-object gauge (`march_live_allocs` through an extern), 5 000
iterations, against the same program built at `137737f3` (before the feature):

| shape | before | after (`7419c689`) | fixed |
|---|---|---|---|
| built straight-line | 3 | 3 | 3 |
| built in an `if` | 1 | **5 001** | 1 |
| built in a callee | 1 | 1 | 1 |

A leak, not a transient: the delta scaled exactly with the loop count
(100 → 103, 1 000 → 1 001, 10 000 → 10 001).

## Root cause

`lib/tir/llvm_case.ml`'s merges store every arm through a `ptr`-typed result
slot, so an arm producing an inline aggregate is boxed on the way in
(`Llvm_ctx.coerce`'s `(sty, "ptr")` arm: `march_alloc(16 + 8n)`, the type's own
ctor tag, one field per slot) and read back out at the merge. Nobody owns that
box:

- `Rc_types.needs_rc` is false for the aggregate, so Perceus emits no drop —
  unlike a boxed `Float`, for which `needs_rc` is true. The coerce arm's own
  comment claimed "the same position a boxed Float is in"; that analogy is what
  was wrong.
- The value the caller sees is the struct, not the box, so no successor
  reference exists to carry the obligation forward.

Confirmed by reading the emitted IR: the `137737f3` build emitted seven
`march_decrc_local` in the loop function, the `7419c689` build one — the
`%ubbox` cell was never decremented. `MARCH_NO_UNBOX=1` (the representation
escape hatch) is a clean control: the identical program's gauge stays flat.

## Fix

`Llvm_case.finish_ptr_merge` — one helper shared by the boxed-path and
niche-path merges, replacing the two hand-inlined `all arms were "double"`
checks with a **uniform non-`ptr` arm type** check that dispatches on what that
type is:

- `"double"` → `march_unbox_float` + `march_decrc_local` (unchanged behaviour).
- an unboxed aggregate's struct type → coerce `ptr` → struct (the existing
  unbox arm) + `march_decrc_local`.
- anything else, or a non-uniform mix → hand the loaded pointer back untouched,
  exactly as before.

**Why this and not the alternatives.** Two other fixes were considered:

1. *Give the RC pass a case for the materialised box.* Rejected as the primary
   mechanism: `needs_rc` is a property of a **type**, and flipping it for
   unboxed aggregates would make Perceus emit inc/dec around every value of
   that type — including the register-resident ones that have no refcount at
   all — which is the opposite of what the representation is for
   (`lib/tir/rc_types.ml`'s divergence table). The box is created by codegen,
   is invisible in TIR, and is therefore codegen's to free. The snapshot
   fixture added below exists partly to make that visible: a drop appearing in
   `test/snapshots/perceus/unboxed_aggregate_branch_join.expected` would mean
   someone moved the fix into the RC pass.

2. *Type the join slot as the struct so no box exists.* Strictly better where
   it applies and worth doing later, but not available as a local change: the
   `alloca` for the result slot is emitted **before** any arm is emitted, and
   `Tir.ECase` carries no result type, so choosing a non-`ptr` slot type needs
   a pure "LLVM type of this expression" pre-pass duplicating `emit_expr`'s
   type logic. A wrong prediction there is a type-mismatched `store`, i.e. a
   miscompile, rather than a leak. Filed as
   `specs/todos/2026-09-04-unbox-aware-case-join-slot.md`.

The chosen fix restores exact pre-feature allocation behaviour rather than
being a pessimisation: under the boxed representation this shape allocated one
cell per construction too (in the arm, rather than at the merge), and freed it.

## What it also fixed

The same helper is used by the niche-path merge, so the fix covers both. A
sweep over seven join shapes — `if`, 3-arm `match`, arity 2/3/4, mixed
Int/Float/Bool fields, nested joins, and one arm building while the other calls
a constructor function — went from leaking 1/iteration in all seven to 0 in all
seven, matching the `MARCH_NO_UNBOX=1` control row for row.

## What it did NOT fix

An aggregate stored into a **niche-encoded ADT payload** (`Some(P2(1.0, 2.0))`)
still leaks one cell per construction, with or without a branch. Same feature,
same "nobody owns the box" root cause, different boundary: the niche `Some`
arm binds the payload as a raw `ptr` and strips the scrutinee `DecRC`, so the
box has no owner and no successor. `MARCH_NO_UNBOX=1` is flat, so it is
attributable to this feature. Filed separately as
`specs/todos/2026-09-04-unboxed-aggregate-niche-payload-leak.md` rather than
folded in here — it needs a change in the niche arm's binder handling (the
counterpart of the boxed path's `boxed_float_field_vals` machinery), which is a
different and more delicate edit than the merge.

Two leaks found during the sweep are **pre-existing and unrelated** — an
aggregate in a tuple element (2 cells/iteration) and in a closure capture
(1 cell/iteration) leak identically with `MARCH_NO_UNBOX=1`, i.e. under the
boxed representation too.

## Tests

A leak has no failing assertion, so output-only tests cannot pin it. Three
things were added, and each was proven RED before the fix and GREEN after:

- `test/test_codegen.ml`, `unboxed_aggregates` group, **"branch-join box is
  released at the merge"** (`Quick`, IR-level). Structural rather than a raw
  call count: for each case-merge load that is unboxed back into an inline
  aggregate (a field read at +16 off the loaded pointer, which only the
  ptr→struct coerce arm emits), the same SSA value must also be released.
  Pre-fix: `FAIL … the box loaded at %case_r36 is unboxed into a struct and
  then released`. Guarded against vacuity by asserting the join really does
  box (exactly two `march_alloc(i64 32)`, one per arm).
- Same group, **"compiled branch-built aggregate loop does not leak"**
  (`Slow`, runtime gauge). Warms the site, samples `march_live_allocs`, runs
  20 000 iterations, asserts the gauge has not moved. Pre-fix:
  `Expected "ZERO", Received "GREW 20000"`.
- `test/snapshots/src/unboxed_aggregate_branch_join.march` + corpus entry. The
  fix is **below TIR**, so this snapshot deliberately shows no change from it —
  what it pins is the absence of inc/dec around the aggregate, so that moving
  the fix into the RC pass would show up here as a readable diff.

## Verification

- `dune build @runtest` — clean.
- `./_build/default/test/run_snapshots.exe -e` — 37/37, existing 17 fixtures
  unchanged, one added.
- `./_build/default/test/test_properties.exe -e` — the differential oracle.
- `dune build @oracle` — no new divergences.
- The reproducer prints a flat delta for all three rows, at 5 000 and 20 000
  iterations.
