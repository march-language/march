# Non-TCO SIMD vector parameters leak one box per call (neither side releases)

Filed 2026-08-12, discovered while fixing
`specs/progress/2026-08-11-simd-tco-entry-box-leak.md` (the TCO-entry variant).
Same 32-byte `march_simd_alloc` cell, different shape, **not covered** by that
fix — which is deliberately narrowed to callees whose vector parameter got a
native `<N x T>` TCO slot.

## What leaks

A function whose SIMD-vector parameter does NOT get a native TCO slot — any
non-tail-recursive fn, an apply fn / closure wrapper, a mutual-TCO group
member — keeps the parameter as an ordinary `ptr` slot. When such a function is
called with a NATIVE vector SSA value (an `ELet` vector slot or a SIMD builtin
result), the call site boxes it via `coerce`'s `(vec, "ptr")` arm, and then:

- the **caller** does not release it — the narrowed fix only releases boxes for
  callees in `ctx.native_vec_params`, and Perceus's own caller-side drop (for a
  borrow-classified parameter position) lands on the argument *variable*, whose
  slot is the native vector type, so llvm_emit's `if ty = "ptr"` RC guard makes
  it inert;
- the **callee** does not release it either — no `EDecRC` is emitted on the
  parameter in any branch.

Witness (`--compile --opt 2 --emit-llvm`), a non-tail-recursive `nt(v, k)`:

```llvm
case_br5:                      ; base case
  %ld9  = load ptr, ptr %v.addr
  %vpay10 = getelementptr i8, ptr %ld9, i64 16
  %vunbox11 = load <4 x float>, ptr %vpay10, align 16
  ...                          ; no decrc of %v.addr anywhere
```

and the caller allocates `%vbox = call ptr @march_simd_alloc(i64 0)` per call
with no matching release.

Unless the callee **escapes** the pointer into a heap aggregate (`fn wrap(v) =
Cons(v, Nil)` stores `%v.arg` into the cons cell, which then owns it), in which
case there is no leak — the aggregate's drop releases it. That escaping shape is
also precisely why the caller must NOT release blindly: doing so is a
use-after-free, pinned by `test/native/simd_vector_escape_arg.march`.

## Why the narrow fix does not cover it

The call site cannot tell shape from shape. "Does this callee retain the
pointer?" is answerable in the emitter for exactly one case — a native TCO slot,
whose entry prologue provably does one GEP + load and drops the pointer — which
is what `ctx.native_vec_params` tabulates. For a `ptr`-slotted vector parameter
the answer depends on the callee's body (escape vs. read-only), and the two
demand opposite caller behavior.

The principled fix is ownership accounting, not another emitter special case:

1. **Borrow-guarded callee-side release.** If borrow inference proves the
   parameter *owned*, the callee may `march_decrc` it at last use — that is just
   the standard owned-parameter convention, which the erasure boundary currently
   swallows. Requires threading the per-fn borrow classification into
   `Llvm_toplevel.emit_fn`; mind the "dual borrowed notion" hazard
   (`project_closure_borrow_map_dual_notion` in repo memory): the caller-side
   borrow map and the callee-side `borrowed` set are independent, and flipping
   only one breaks both.
2. **Or** make the box visible to Perceus at all: today it is created by
   `coerce` *between* the argument emission and the call, so it never enters a
   TIR variable and no pass accounts for it. Materializing it as a real TIR
   binding would let ordinary Perceus RC insertion handle every shape uniformly.

## Also open: three call paths excluded even for native-slot callees

The narrow fix emits its release only on the two plain call arms of
`llvm_emit.ml`'s `EApp` (void and value-returning). A call to a native-slot
callee that goes through any of these three paths still leaks one box per call:

- **`raises`-extern wrapper** (`emit_raises_wrapper`) — the call is wrapped in
  error-routing scaffolding instead of being emitted inline.
- **blocking extern** (`Llvm_calls.emit_blocking_call`) — same.
- **hot-reload dispatch** (`needs_dispatch`, `--hot-reload` / `--compile-so`) —
  the call is split across two basic blocks (`hr_direct` / `hr_disp`) and merged
  by a phi, so the "release in the same block as the call" invariant needs a
  chosen merge point (`hr_cont` is the obvious one: both predecessors pass the
  same box and neither can skip it).

These were skipped deliberately — leaking is the safe direction, and each adds a
control-flow shape to reason about — not overlooked. Whoever fixes the general
case should sweep them in the same pass; the hot-reload one is the only one
needing real thought.

## Measurement shape

Same as the TCO variant: a driver loop calling the kernel N times,
`--compile --opt 2`, `/usr/bin/time -l`, delta against a scalar control of the
same driver shape. `test/native/simd_leak_probe.march` is the ready-made
harness — swap its `go` for a non-tail-recursive callee and the RSS assertion
(< 32 MB) fails again.

## Related

- `specs/progress/2026-08-11-simd-tco-entry-box-leak.md` — the narrow fix, and
  the full ownership map of which call shapes transfer vs. retain.
- `test/native/simd_vector_escape_arg.march` — the canary that makes the naive
  "release every box the call site created" fix fail loudly.
