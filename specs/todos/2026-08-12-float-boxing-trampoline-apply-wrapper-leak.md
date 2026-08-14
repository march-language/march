# Float-boxing erasure-boundary leak: Task trampoline + apply-wrapper sites still open

Filed 2026-08-12, split off from
`specs/todos/2026-08-11-float-boxing-erasure-boundary-per-call-leak.md` after
that item's case/match site (site 1 of 3) was fixed — see
`specs/progress/2026-08-12-float-boxing-case-merge-leak-fix.md` for the fix
and full root-cause background (same underlying gap: the Stage 2
float-boxing design's `march_alloc_float`/`march_unbox_float` pairing was
never given a free/ownership story). This item tracks the two sites that fix
did **not** touch:

1. **Task/closure trampoline return** (`lib/tir/llvm_emit.ml:2054-2058`) — a
   closure apply-fn's `double` return is boxed once by the trampoline, handed
   through `task[3]` as a tagged pointer, and unboxed on the awaiting side
   (`march_unbox_float`) with no free. Per the closed item's analysis this
   box is allocated solely to smuggle a double through `task[3]` and consumed
   exactly once — same "provably sole owner, safe to free immediately after
   unbox" shape as the case-merge fix, just in a different file/function
   (`llvm_emit.ml`'s task-await codegen rather than `llvm_case.ml`'s
   `emit_case`).
2. **Apply-wrapper Float params** (`lib/tir/llvm_toplevel.ml:237-242`) — the
   mirror direction: an apply-fn's `double` parameter arrives boxed (uniform
   ptr ABI) and is unboxed with `march_unbox_float` in the entry prologue,
   again with no free. Whether this one is safe to free immediately needs the
   same care as the case-merge fix took: confirm the caller-side box is
   always freshly allocated per-call (not a long-lived closure-captured
   value reused across calls) before adding a `march_decrc_local`.

## Why these weren't fixed alongside the case-merge site

Both are structurally similar to the fixed site (box created immediately
upstream in the same call path, consumed exactly once, no other holder) but
live in different emission functions with different surrounding invariants,
and neither was covered by the reproduction used to validate the case-merge
fix. Fixing them blind, without an equivalent measurement + full-suite
verification pass, would repeat exactly the mistake the original item's "why
the naive fix is wrong" section warned against.

## Suggested approach

Mirror the case-merge fix's shape: find the exact point in each function
where the corresponding `march_alloc_float` allocation happens (the
Task-trampoline boxing on the producing side; the caller-side box for the
apply-wrapper's incoming arg), confirm — for each — that nothing else can
observe or hold a reference to that specific box before the unbox site reads
it, then add `march_decrc_local` immediately after the unbox. Re-run the
case-merge fix's RSS probe shape (native, `--compile --opt 2`,
`/usr/bin/time -l`, ~20M calls) adapted to exercise each site specifically
(a Task-await-in-a-loop probe for site 1; a HOF/closure-call-in-a-loop probe
with a Float param for site 2), plus the full suite
(`run_compiler`/`run_eval`/`run_codegen`/`run_stdlib`, run individually) before
calling either done.

## Related

- `specs/progress/2026-08-12-float-boxing-case-merge-leak-fix.md` — the fixed
  sibling site and full verification detail.
- `specs/progress/2026-08-11-simd-tco-entry-box-leak.md` — the SIMD-specific
  sibling leak (different erasure boundary, `march_simd_alloc`), independent
  bug, independent fix, same missing-free root shape. **Now FIXED** for
  callees whose vector param got a native TCO slot; the residual case
  (vector params on non-TCO callees) is tracked separately in
  `specs/todos/2026-08-12-simd-nontco-vector-param-leak.md`. The fix there is
  a useful template for this one: same "the call site owns the temp box"
  framing.
