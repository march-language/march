# A case join whose arms all build one unboxed aggregate is typed as the struct (done 2026-09-30)

Filed 2026-09-04 as the optimisation deferred by
`specs/progress/2026-09-04-unboxed-aggregate-branch-join-leak.md`.

## Measured first

New `bench/branch_aggregate.march`: 50,000,000 iterations of
`let p = if i % 2 == 0 do P2(i, 1) else P2(1, i) end` (alternating arms,
`P2(Int, Int)`), then both fields are read. As a ceiling for the win, it was
compared with the same loop building `P2(x, y)` after two scalar-only `if`s,
a shape that never boxes. Compiled `--opt 2`, 11 interleaved runs,
origin/main 771430bf3:

| | median | min |
|---|---:|---:|
| branch-built, origin/main (`alloca ptr`, 2 `march_alloc(i64 32)` in the loop) | 1.61 s | 1.54 s |
| straight-line control, origin/main (no box) | 0.105 s | 0.102 s |
| **branch-built, this change (`alloca %ub.P2`, no `march_alloc`)** | **0.070 s** | 0.067 s |

That is about 23x on the shape the todo named. Load average was 9-11, so
read the ratios, not the absolute times.

## What changed (`lib/tir/llvm_case.ml`)

The slot's `alloca` is emitted before any arm, so the type has to be
predicted. The todo feared a general "LLVM type of this expression"
pre-pass, and this change avoids one. `predicted_unboxed_join` is
deliberately narrow: an arm counts only if its tail, through `ELet`/`ESeq`, is
an `EAlloc` of a type `Kind.repr_of` classifies `Unboxed`. That is exactly the
test `Llvm_emit_alloc.emit_alloc_ctor` makes before returning the struct. A
nested `ECase` also counts when all of its own arms predict the same type
(that case returns the struct itself). Arms that cannot reach the merge
(`arm_diverges`) are ignored, and at least one arm must reach it. When every
reaching arm agrees on one struct type `S`:

- the boxed-path and niche-path slots are `alloca S`
- every arm stores `Llvm_ctx.coerce ... S`
- the merge loads `S` and returns it, with no `finish_ptr_merge` and nothing
  to free.

Everything else keeps the `ptr` slot and `finish_ptr_merge` as before: calls,
variables, reuse, generic payloads, closure fields, and mixed joins.

Safety if a prediction were ever wrong: the stores go through `coerce` to `S`,
whose ptr->struct arm unboxes a boxed cell of that same type, so a mismatch
still produces well-typed IR. It would not be a type-mismatched `store`, the
miscompile the todo worried about.

Not covered, possible follow-ups: an arm whose tail is a CALL returning the
struct, or a variable bound to one (the "mixed join" shape), still boxes.

## Verification

- `test/test_codegen.ml` `unboxed_aggregates`:
  - new: `branch-built join slot is typed as the struct` (`alloca %ub.P2`, zero
    `march_alloc`, no unboxing merge);
  - new: `3-arm match and else-if chain joins are struct-typed`;
  - both FAIL on origin/main and pass here;
  - `branch-join box is released at the merge` now uses a mixed join (one arm
    builds, the other returns a variable). That shape still takes the `ptr`
    slot, so the release-at-merge guarantee stays pinned.
  - Full `run_codegen`: 643/643, the LLVM IR validity gate included.
- `test/native/unboxed_join_slot.march`: parity golden (`.expected` is the
  interpreter's output; native and `interp_` rules). It covers a two-arm `if`,
  a three-arm `match` (Int/Float/Bool fields), an `else if` chain, an `Option`
  match (niche slot, confirmed `load %ub.P2` from the niche slot in the IR),
  and a mixed join, each alternating and each checking `live_allocs` stays flat.
- `test/native/niche_aggregate_payload_leak_probe` still matches.
- ASAN (Linux container, ubuntu arm64). The new golden and
  `niche_aggregate_payload_leak_probe` are clean with leak detection on, at
  `--compile` and `--opt 2`. `specs/lang/golden/sanitize.sh` is 142 clean,
  0 failed (golden 47, native 32, two-node 63, 4 skipped for root).
- `dune build --root . @test/runtest` (every dune-rule golden): exit 0.
- TIR snapshots are unchanged (this is below TIR).
- Standard benchmarks, `--opt 2`, 9 interleaved runs, origin/main vs branch
  medians: `tree_transform` 0.704 s / 0.703 s, `list_ops` 0.085 s /
  0.086 s, `binary_trees` 0.239 s / 0.235 s. The outputs are identical.
