# Float-boxing case/match result-merge leak fixed (site 1 of 3)

Landed 2026-08-12, closing the case/match portion of
`specs/todos/2026-08-11-float-boxing-erasure-boundary-per-call-leak.md`
(filed 2026-08-11). The other two sites that item identified — Task/closure
trampoline return (`llvm_emit.ml:2054-2058`) and apply-wrapper Float param
unboxing (`llvm_toplevel.ml:237-242`) — are **not** fixed by this change and
remain open in `specs/todos/2026-08-12-float-boxing-trampoline-apply-wrapper-leak.md`.

## What was fixed

`lib/tir/llvm_case.ml`'s general (switch/tag) case-merge path always
represented every branch's result through a uniform `ptr` `result_slot`: a
`Float`-typed branch got boxed via `Llvm_ctx.coerce ctx "double" v "ptr"`
(a genuine `march_alloc_float` heap allocation), stored, and — after the
merge — read back and unboxed with `march_unbox_float`, with nothing ever
freeing the box. Every `if`/`match` expression producing a `Float` leaked one
box per evaluation (~32 bytes, allocator-rounded from the 24-byte
`march_float_box`), independent of TCO or SIMD — see the todo for the full
root-cause writeup and the decisive non-recursive control that proved TCO was
not the cause.

The fix stays inside `emit_case` and never touches the shared, ownership-blind
`Llvm_ctx.coerce` helper (as the todo's "why the naive fix is wrong" section
required): each branch's pre-coercion LLVM type is recorded in a new
`arm_result_tys` accumulator as it's emitted. If every arm that reaches
`merge_lbl` was `"double"`, the box sitting in `result_slot` is provably
freshly allocated by this same `emit_case` call, never escapes, and is read
by nobody else — so the merge unboxes it and immediately
`march_decrc_local`s it, returning `("double", <unboxed value>)` instead of
handing the caller an opaque, still-live `("ptr", ...)`. Any case/match with
a non-`Float` or mixed-type arm keeps the exact previous behavior (untouched
code path).

This is deliberately narrower than "fix all case/match paths": the niche
(`Option`-shaped), string-literal, atom, and float-literal-chain match
compilation strategies in the same file each have their own separate
`result_slot`/merge logic and were left alone — none of them appear in the
reproduction, and touching the niche path in particular carries real risk
given the RC-sensitive `strip_decrc_niche`/shared-vs-unique field handling
documented inline there.

## Verification

- Repro from the todo re-measured post-fix: both the TCO'd-helper case and
  the non-recursive `if n<=0 do 1.0 else 2.0 end` case dropped from
  644,793,136 B (~645 MB) peak RSS to 1,933,648–1,950,032 B (~1.9 MB) —
  matching the flat, helper-free control exactly.
- Output values unchanged (verified against a pre-fix control binary: both
  print the same accumulated total), confirming the fix is leak-only, not a
  value change.
- Full suite green post-fix: `run_compiler.exe` (844 tests), `run_eval.exe`
  (256 tests), `run_codegen.exe` (565 tests — the LLVM-IR-validity gate over
  the full `native/*.march` corpus lives here), `run_stdlib.exe` (845 tests)
  — all `Test Successful`, all exit 0, run individually to rule out a flake
  from an earlier concurrent `run-tests.sh` invocation.

## Files changed

- `lib/tir/llvm_case.ml` — `arm_result_tys` tracking + the all-`"double"`
  fast path at the case-merge point (general switch/tag branch handling
  only).
