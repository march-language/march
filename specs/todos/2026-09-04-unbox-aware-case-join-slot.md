# Type a case join slot as the struct when every arm is the same unboxed aggregate

**Filed:** 2026-09-04, as the optimisation deferred by
`specs/progress/2026-09-04-unboxed-aggregate-branch-join-leak.md`. This is a
performance item, not a correctness one — the leak it grew out of is fixed.

## What

`lib/tir/llvm_case.ml` gives every `ECase`/`if` merge a `ptr`-typed result
slot. An arm producing an unboxed small scalar aggregate is therefore boxed on
the way in (`march_alloc(16 + 8n)`) and unboxed again at the merge, which
`Llvm_case.finish_ptr_merge` now also frees. That is allocation parity with the
pre-Milestone-3 boxed representation, but the representation's whole point is
that these values never reach the allocator: the straight-line and
across-a-call shapes already move `march_live_allocs` by **zero**, and only the
branch-built shape pays a cell.

When every arm that reaches the merge produces the SAME unboxed struct type,
the slot could simply be typed as that struct — no box, nothing to free, and
one fewer allocation per construction.

## Why it was not done in the fix

The result-slot `alloca` is emitted **before** any arm is emitted, and
`Tir.ECase` carries no result type, so the slot's type cannot be chosen from
what the arms turn out to produce. Getting there needs one of:

- a pure "LLVM type of this TIR expression" pre-pass (duplicates `emit_expr`'s
  type logic; a wrong prediction is a type-mismatched `store`, i.e. a
  miscompile rather than a leak — this is the risk that deferred it), or
- buffered emission of the arms so the `alloca` can be chosen afterwards
  (`Llvm_ctx.emit` writes straight through today).

## Scope caution

Not every join can drop the box. Generic ADT payloads, closure fields, task
trampolines and apply wrappers genuinely need the boxed form — that is the
whole reason the coerce arm exists. Any change here must keep the box for
those and only elide it where all arms agree on one unboxed struct type, with
`finish_ptr_merge` staying as the fallback for everything else.

## Measurement to take first

`bench/` has no branch-built-aggregate benchmark. Before implementing, write
one (the loop in the progress entry's reproducer is the right shape) and
measure compiled, so the win is a number rather than an assumption.
