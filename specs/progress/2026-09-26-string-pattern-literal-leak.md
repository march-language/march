# DONE String-pattern `match` leaked one string per arm compared (compiled)

Found 2026-09-26: LeakSanitizer on `test/native/tco_fresh_arg_decrc.march`
(Linux `march-amdr-repro` container, `MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1`)
reported 29 direct leaks, all `march_string_alloc <- march_string_lit <-
str_to_int`. Fixed the same day.

## The bug

A `match` on a `String` scrutinee with literal patterns compiles (in
`lib/tir/llvm_case.ml`, the `is_string_case` chain) to one
`march_string_eq(scrutinee, lit)` per arm, tried in order. The `lit` operand
was built with `march_string_lit`: a fresh rc=1 heap string for **each
comparison**. Nothing released it. The pattern literal is an arm tag
(`br_tag = "\"0\""`), not a TIR value, so Perceus never sees it, and the TIR
dump for the function looks fine. The leak is only visible in `--emit-llvm`.

Each evaluation leaked one string for every arm it tried. A match on the
first arm leaked one; a fall-through to `_` past ten arms leaked ten. For
`tco_fresh_arg_decrc`, the digits of "9000", "42" and "7" try
10+1+1+1 + 5+3 + 8 = 29 arms, which is the reported count.

## Fix

Each arm now uses the same immortal per-site literal that an `ALit
(LitString)` operand already gets (`Llvm_ctx.intern_string_site` +
`march_string_lit_static`, see its doc comment in `lib/tir/llvm_ctx.ml`). The
string is materialised once per site and never freed.
`march_string_eq` borrows both operands. A string-pattern match no longer
allocates at all, which is what `Alloc_contract` already assumed.

## Test

`test/native/string_pattern_literal_leak_probe.march` (golden +
`test/refine_audit/corpus.baseline` lines). Over 20,000 calls it checks
`live_allocs` growth when the match hits the first arm, the last arm, the
default, and the tco_fresh_arg_decrc shape inlined into a tail-recursive
walk. An Int-pattern loop is the control.

- RED on 7b56b9e0e: all four string legs read `flat: false`; the control
  reads `flat: true`. Under ASAN, 680,000 leaked allocations.
- GREEN: all `flat: true`, and ASAN reports no leaks on the probe.

After the fix, `tco_fresh_arg_decrc` under ASAN is down from 936 B / 36
allocs to 182 B / 7 allocs. The remaining 7 are `march_string_join` results
leaked by the self-TCO forwarded-fresh-argument path, a separate bug
addressed by PR #668 (`specs/todos/2026-09-20-mutual-tco-borrowed-forwarded-arg.md`).
