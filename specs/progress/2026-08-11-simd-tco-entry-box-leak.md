# SIMD self-TCO entry prologue leaks one vector box per call (unbounded) — FIXED 2026-08-12

## Fix summary (2026-08-12)

Fixed **caller-side, narrowly**: the call site releases the temp box IT created
for the call, but ONLY when the callee is known to give that parameter a native
`<N x T>` vector TCO slot. Such a callee's entry prologue provably does one
`getelementptr` + `load` of the payload and never stores the pointer anywhere,
so the box cannot escape into it and releasing after the call is sound.

- `Llvm_ctx.ctx.native_vec_params : (string, int list) Hashtbl.t` — callee name
  → parameter indices with a native vector slot. Filled by a **pre-pass** in
  `Llvm_toplevel.emit_module` before ANY function body is emitted (a caller can
  be emitted before its callee), recomputing `emit_fn`'s own `native_vec_slot`
  decision from the same `is_tco` + `vec_ty_of_tir` predicates. Mutual-TCO group
  members are excluded — `Llvm_tco.emit_mutual_tco_group` has no native-slot arm.
- `Llvm_emit`'s `EApp` arm records the boxed register whenever an argument at
  such an index is coerced native → `ptr`, and emits `call void @march_decrc`
  for each immediately after the call, in the same basic block. Arguments that
  were already `ptr` (a vector at rest) are never recorded: no box was created.

**Measured:** `test/native/simd_leak_probe.march`, 2,000,000 calls,
`--compile --opt 2`, `/usr/bin/time -l` max RSS
**67,092,480 B (64 MB) → 2,818,048 B (2.7 MB)**, i.e. 33.5 B/call → ~0.
Committed as a dune `runtest` rule asserting max RSS < 32 MB (Darwin-gated:
`/usr/bin/time -l` is macOS-specific, the rule skips with exit 0 elsewhere).

### Ownership map — which call shapes transfer vs. retain

The table the design turns on. "Boxed by the caller" means the argument's
emitted type was a native `<N x T>` (an `ELet` vector slot or a SIMD builtin
result) and `coerce`'s `(vec, "ptr")` arm allocated a fresh `march_simd_alloc`
cell with rc = 1. Established by reading `perceus.ml` / `borrow.ml` /
`rc_types.ml` and confirmed against emitted IR for each row.

| # | Callee shape | What the callee does with the incoming box | Who releases it | Caller-release verdict |
|---|---|---|---|---|
| A | self-TCO fn with a vector param (`native_vec_slot`) | GEP + load of the payload at entry; pointer never stored | **nobody → this leak** | **safe — what we now do** |
| B | non-TCO fn, vector param slot stays `ptr`, param only read | unboxes at each use; no `EDecRC` emitted in any branch | **nobody → leaks too** | safe in principle, NOT done (see scope below) |
| C | non-TCO fn whose vector param **escapes** into an ADT / list / closure field | `store ptr %v.arg, ptr %field` — the aggregate takes ownership | the aggregate's drop | **DOUBLE FREE / UAF — must not release** |
| D | apply fn / closure ABI ("Boundary B") | B or C depending on the body | same as B/C | same as B/C |

Supporting facts: `Rc_types.needs_rc (TCon "F32x4") = true` and
`borrow_eligible = true` (the generic `TCon _` arms), so a vector is an ordinary
RC'd heap value to Perceus and Borrow; `llvm_ty (TCon "F32x4") = "ptr"`, so a
slot is native only where the emitter deliberately makes it so (`ELet` vector
RHS, and this native TCO slot); every RC arm in `llvm_emit.ml` is guarded by
`if ty = "ptr"`, so RC ops on a native slot are inert — which is what ate the
one dec that would otherwise have balanced row A. The borrow map is not
reachable from the LLVM layer at all, which is why the answer had to come from a
shape the emitter can see rather than from a borrow query.

Row C is what makes the narrow scope mandatory rather than conservative, and it
is reachable from plain March (`fn wrap(v, k) = Cons(v, ...)`).

### Call paths deliberately EXCLUDED from the release

Even for a row-A callee, the release is emitted only on the two plain call arms
of `llvm_emit.ml`'s `EApp` (void and value-returning). Three paths are skipped
and still leak:

- **`raises`-extern wrapper** (`emit_raises_wrapper`) — the call is wrapped in
  error-routing scaffolding rather than emitted inline.
- **blocking extern** (`Llvm_calls.emit_blocking_call`) — likewise.
- **hot-reload dispatch** — the call is split across two basic blocks
  (`hr_direct` / `hr_disp`) and merged by a phi, so "same block as the call"
  does not hold without picking a merge point.

Skipping them keeps today's behavior (leak, never crash), which is the safe
direction. Adding them means reasoning about a second control-flow shape; folded
into the follow-up item rather than done blind.

**Scope — the leak is NOT fully closed.** A vector parameter that does *not* get
a native slot (any non-tail-recursive fn, apply fn/closure, mutual-TCO member)
still leaks one box per call when the callee only reads it: neither side
releases. Tracked in
`specs/todos/2026-08-12-simd-nontco-vector-param-leak.md` — it needs
Perceus-level ownership accounting, not another emitter special case.

**Why the release is narrow, and what proved it.** The obvious generalization —
release every box the call site created — is a use-after-free. A callee whose
vector parameter stays `ptr` may store that exact pointer into a heap aggregate
that then owns it (`fn wrap(v) = Cons(v, Nil)` compiles to
`store ptr %v.arg, ptr %cons.field`); releasing frees a live list element.
Built and measured: reproducible exit 139/133, while `simd_vector_core`,
`simd_nested_closure_acc` **and** `simd_poly_eq` all still passed — the existing
fixture set could not see it. Pinned now by
`test/native/simd_vector_escape_arg.march` (with `k = 0` on purpose, so the
escaped box has rc = 1 and the bad dec frees it outright rather than merely
under-counting).

This also answers the "why the one-line fix is wrong" section below: the
ownership question the backend could not answer for an arbitrary parameter *is*
answerable for the native-slot case specifically, because there the callee's
treatment of the pointer is fixed by construction rather than by its body.

---

## Original report (2026-08-11)


Filed 2026-08-11, review finding on Task 4b (commit `08c02ebb`). **Not a
regression** — the code this replaced leaked strictly more — but it is an
unbounded leak with no other record in the repo, so it is filed rather than
left in a commit message.

## What leaks

`08c02ebb` gave a self-tail-recursive function's SIMD-vector parameter a
native `<N x T>` TCO slot. The function's signature stays `ptr` (so callers are
unaffected), which means the entry prologue must unbox the incoming argument
once per call:

```ocaml
(* lib/tir/llvm_toplevel.ml, emit_fn's param_slots, the native_vec_slot arm *)
let nv = Llvm_ctx.coerce ctx "ptr" (Printf.sprintf "%%%s.arg" vn) vty in
Llvm_ctx.emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr, align 16" vty nv slot);
```

`coerce`'s `("ptr", vec)` arm is a `getelementptr` + `load` of the payload. It
never releases the box it read from. The box was created by the caller's
`(vec, "ptr")` coerce via `march_simd_alloc` with rc=1, and after this point
nothing holds or drops it — so one 32-byte cell is leaked per invocation.

Note this is **per call**, not per loop iteration. The loop body itself is now
allocation-free; do not read the "the loop allocates nothing" claim in
`bench/RESULTS.md` / the emit-site comment as meaning the leak is gone.

## Measurement

Probe: a trivial SIMD self-TCO kernel (4-element array, one 4-lane iteration)
called N times from a driver loop, against a scalar control of the same driver
shape with no vector parameter. `--compile --opt 2`, `/usr/bin/time -l`,
N = 20,000,000.

| | max RSS |
|---|---|
| SIMD kernel (vector TCO param) | 1,287,847,936 B (1.29 GB) |
| scalar control (no vector param) | 645,349,376 B (645 MB) |
| **delta attributable to the vector param** | **+642 MB = +32.1 B/call** |

32 bytes/call matches the `march_simd_alloc` cell size exactly.

(The control's own 645 MB of growth is a *separate*, pre-existing issue in the
scalar driver shape and is not part of this item — the vector-attributable
number is the delta. Worth a look by whoever picks this up, but do not conflate
the two.)

Impact: bounded and harmless for a batch program that calls a kernel a handful
of times; unbounded for a long-lived process that calls one per request or per
tick.

## Why the one-line fix is wrong

Emitting `march_decrc_local` on `%<param>.arg` after the unbox is the obvious
patch and is a **use-after-free**. A vector argument is usually a fresh
temporary the call site just boxed (safe to consume), but it can also be a
borrowed reference to a box someone else owns — e.g. a vector stored in an ADT
field, or a record field, passed straight into the call. Dropping that frees it
out from under the owner.

The backend cannot tell the two apart at this point: `emit_fn` sees only the
parameter's `Tir.ty`, not whether the caller transferred ownership.

## Fix direction

Get the ownership answer from the pass that already computes it, rather than
guessing in the emitter:

1. **Borrow inference** (`lib/tir/borrow.ml`) already classifies parameters as
   borrowed vs owned, and `Rc_types.borrow_eligible` returns true for these
   `TCon`s. If a vector param is proven *owned*, the entry prologue can safely
   `march_decrc_local` the box after unboxing it; if borrowed, it must not.
   Check whether the per-fn `borrowed` set is reachable from `emit_fn` — note
   the "dual borrowed notion" hazard in repo memory
   (`project_closure_borrow_map_dual_notion`): the caller-side borrow map and
   the callee-side `borrowed` set are independent, and flipping only one breaks
   both sides.
2. **Or** have Perceus emit an explicit `EDecRC` on the parameter for the owned
   case, so the emitter stays dumb — but note the existing `if ty = "ptr"`
   guard on every RC arm in `llvm_emit.ml` makes RC ops on a vector-typed slot
   inert by design (that inertness is what keeps the native slot sound today),
   so this route needs the drop to reference the incoming `.arg` value rather
   than the slot.

Whichever route: the regression net is an RSS-growth assertion, since a
correctness test will not catch a leak. The probe above is the shape to use.

## Related

- `specs/progress/2026-08-11-simd-nested-closure-vector-accumulator-segfault.md`
  — the Task 4b fix this came out of.
- `specs/todos/2026-08-11-march-index-loop-per-iteration-overhead.md` — the
  other open item from the same review (why `dot_simd` still loses to
  `dot_composed`).
