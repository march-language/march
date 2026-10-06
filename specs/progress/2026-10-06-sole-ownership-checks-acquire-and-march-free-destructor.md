# Sole-ownership checks are acquire loads, and `march_free` runs a resource cell's destructor (Part C, Phase C0)

**Landed 2026-10-06.** Phase C0 of
`specs/plans/2026-09-25-send-data-race-freedom-plan.md`; the semantics are
`specs/2026-10-06-linear-ringbuf-and-sendable-arrays-design.md` §2.3 and §4.
The todo `specs/todos/2026-09-25-send-marker-and-closure-capture-checks.md`
stays open until C5.

## What was wrong

Every in-place write in March is gated on reading `rc == 1`: FBIP `reuse`,
native-array `set`/`sort` at all five widths and their fast paths, the SIMD
vector store. The C runtime read the header word with a plain load (nine
`((march_hdr *)arr)->rc == 1` sites in `runtime/march_runtime.c`), and the
LLVM emitter with `load atomic i64 … monotonic`. `march_decrc` is an `acq_rel`
RMW, so a thread dropping its last reference *releases* its earlier reads of
the object, but a relaxed load on the writer's side does not *acquire* them:
under the C11 model the writer that then mutates in place has no
happens-before edge with those reads, a formal data race. It does not bite on
x86, and on arm64 the control dependency has covered it in practice; it is the
pattern Rust's `Arc::get_mut` uses `Acquire` for. C1 makes native arrays an
advertised cross-thread value, so this went first.

Separately, Perceus frees a dead linear binding through `EFree`, which lowers
to `march_free`, and `march_free` was a plain `free` that ignored
`MARCH_RESOURCE_TAG`. `march_decrc` at zero runs the resource destructor;
`march_free` skipped it, so a dead resource cell (a `RingBuf` once one can be
dead; any FFI resource) would have shallow-freed its 40-byte cell and leaked
the native store and every element it still held. No accepted program reached
the path while every resource cell was unrestricted or must-consume, so this
was a latent leak, not an observed one.

## What changed

- `runtime/march_runtime.h`: `march_rc_is_unique(p)`, an `__atomic_load_n(…,
  __ATOMIC_ACQUIRE) == 1` on the header word, with the reasoning in its
  comment. The nine C sites call it (grep `march_rc_is_unique`); no `->rc == 1`
  on a header remains in `runtime/`.
- `lib/tir/llvm_emit_alloc.ml` (three FBIP reuse sites), `llvm_emit_simd.ml`
  (the vector store) and `llvm_case.ml` (the reuse-counterpart scrutinee read
  that decides whether to dup extracted fields): `monotonic` → `acquire`. The
  plan counted four emit sites; `llvm_case.ml:1272` is a fifth with the same
  shape (read the count, then move fields out without an inc on the unique
  path), so it changed too. `lib/tir/llvm_rc_inline.ml`'s two `monotonic`
  loads are immortal-bit checks ahead of the `acq_rel` RMW, not ownership
  gates, and stay as they are.
- `runtime/march_runtime.c` `march_free`: after the immortal guard, run
  `march_run_resource_dtor` on a heap cell before `free`, the same tag check
  `march_decrc` makes at zero.

Cost: free on x86-64 (an acquire load is a plain `mov`), one `ldar` instead of
`ldr` on arm64.

## Verification

- `scripts/ir-oracle.sh baseline` at `262fea07` (the Phase 0 base) and `check`
  after: every program whose IR changed differs only in `monotonic` →
  `acquire` on the ownership loads (the oracle's diff was read, not just
  counted; see the PR description for the number).
- `scripts/check-actor-rc-stores.sh` passes (it polices stores to the actor
  refcount word; the new helper only loads).
- `scripts/run-tests.sh` (full) and the compiled `test/native/` goldens.
- `bench/tree_transform.march` (FBIP) and `bench/array_sort.march` compiled
  at `--opt 2` before and after, on this x86-64 box: numbers in the PR
  description. arm64 numbers are still owed; the change is one `ldar` there.
