# Current State (as of 2026-07-30, the REPL capture-free closure leak is closed)


**Counts:** `run_codegen` 518 tests (was 517 — one new
`repl_jit_cross_line` regression), `run_eval` / `run_compiler` /
`run_stdlib` unchanged. Known failure: `adversarial-regressions` 39
(`MARCH_SANITIZE` 30s timeout) — pre-existing and environmental, reproduced
on a base tree with these changes reverted.

**A capture-free closure materialized under the REPL/JIT no longer leaks one
allocation per materialization.** Natively such a closure is a single
immortal global (`Llvm_ctx.intern_static_closure`), so nothing needs to
release it; `Llvm_emit.static_closure_ok` is `not ctx.repl && ..`, so under
the REPL the very same closure falls back to a fresh `march_alloc` per
materialization — and nothing ever released THAT.

Two prior attempts at this both crashed with `EXC_BAD_ACCESS` at `0x0`,
frame #0 = `0x0`, in `repl_jit_cross_line`'s "stdlib List.length via
precompile", and both diagnosed the crash by pattern-matching rather than by
looking. An actual `lldb` backtrace named it immediately:
`List.length$List_Int -> go$apply$218 -> 0x0`. `go` is `List.length`'s inner
**self-recursive** helper — capture-free, hence caught by a blanket
"drop capture-free apply fns" rule, but it already releases its own
reference through `lift_lambda`'s self-binding alias under completely
ordinary RC insertion (`let go = $clo in case .. of Nil -> dec_rc go; ..`).
The added drop was a second release of the same reference: freed on call 1,
the recursive dispatch then read a zeroed apply-fn slot.

**Fixed in two places, one per capture-free shape** — the second found by
measurement after the first was already green, and independent of it:

- `Perceus.insert_apply_fn_clo_drop ~repl` (threaded via `insert_rc` ←
  `perceus ~repl` ← `Repl_jit.lower_module`, which passes `~repl:true` so
  the flag tracks `ctx.repl` exactly) drops `$clo` for an apply fn whose
  body mentions `$clo` **nowhere**. That test is what excludes the
  self-recursive case above. Covers capture-free lambdas.
- `Llvm_calls.clo_wrap_define ~drop_clo` (`~drop_clo:ctx.repl` at all three
  emission sites) covers capture-free top-level function values, whose
  `@<fn>$clo_wrap` trampoline is synthesized at LLVM emission and has no TIR
  apply fn for Perceus to reach. Sound alongside the slot-read `incrc` from
  the "REPL variable slots now RC-correct" entry below.

Measured over 2,000 materializations in a REPL fragment: `march_live_allocs`
grew by exactly 2,000 before and 0 after, for each shape independently.
Native output is unchanged and provably so — a program exercising both
shapes plus `List.length` emits byte-identical `--emit-llvm --opt 2` IR
before and after. `repl_jit_cross_line` green 20/20 consecutive runs.
