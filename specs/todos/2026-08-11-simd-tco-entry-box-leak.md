# SIMD self-TCO entry prologue leaks one vector box per call (unbounded)

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
