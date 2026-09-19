# FIXED 2026-09-18 — TRMC's reuse_hole mutated a cell another holder still had

Found by the cluster node service's session frames
([[2026-09-18-cluster-node-service]], phase 4): `Msgpack.encode` of an array
holding `Msgpack.bin(payload)` crashed ("non-exhaustive pattern match" / RC
underflow) the second time the same `payload` was encoded.

## The bug

TRMC turns `Cons(h, lapp(t, ys))` into a loop that allocates each cell with a
hole (`EAllocHole`), reusing the scrutinee's cell when it is unique
(`reuse_hole xs as Cons(h, _)`, Llvm_emit_alloc.emit_alloc_hole: rc = 1 takes
the cell over, otherwise ONE box-level `march_decrc` and a fresh cell). The
arm has already moved the cell's fields into its binders (`h`, `t`). On the
SHARED path those fields are then held by both the old cell (still alive for
its other holder) and the binders, so each needs an increment. `EReuse` gets
exactly that from `Llvm_case`: when the arm's body reuses the scrutinee
(`body_reuses_scrut`), the case emits `rb_shared` (rc > 1: `march_incrc` every
extracted heap field). `body_reuses_scrut` recognised only `EReuse`, not
`EAllocHole` with a reuse token, so a TRMC arm on a shared cell moved the
tail with no increment. The tail then looked unique to the next iteration,
which reused it in place: the loop MUTATED a list someone else still held.

Smallest trigger: `let front = lapp([1, 2], shared)` then
`lapp(front, [9])` and `lapp(front, [8])` -- walking a list whose cells are
shared. In Msgpack: `encode_val(Bin(bs))` returns `header ++ bs`, sharing
`bs`'s cells with the caller's payload; the array encoder then appends that
list to the rest with the TRMC'd `list_append`, walking into the shared
cells. `--no-trmc` was correct throughout.

## The fix

One arm in `body_reuses_scrut`: `EAllocHole (Some (AVar v), ...)` reuses the
scrutinee iff `v` is it. The shared-path dup is the same as EReuse's, and the
hole's fresh path already performs the matching single box-level decrement.

## Verification

- `test/native/trmc_shared_tail_reuse.march` (dune runtest): the shared-tail
  append walked twice, and the Msgpack encode of a reused Bin payload. Output
  equals the interpreter's. The same programs as probes: pre-fix RC underflow
  (append) and "non-exhaustive pattern match" (Msgpack), `--no-trmc` correct.
- Plain FBIP reuse was never affected (`bump_head`, a recursive `inc_all` on a
  shared list: correct before and after).
- Benchmarks: `bench/list_ops`, `tree_transform`, `binary_trees` emit the same
  number of `rb_shared` paths with and without the fix, and their IR differs
  only in fresh-name numbering (compiler at 0dade8cde vs this change), so
  their hot paths did not change; not timed (load average 19).
- Full suite: see the phase-4 commit.
