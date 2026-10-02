# Lazy 63-bit Int normalisation: the wrap no longer blocks LLVM's accumulator TRE

Filed 2026-10-01 as `specs/todos/2026-10-01-int63-wrap-blocks-accumulator-tre.md`;
landed 2026-10-02.

## The problem (as filed)

`specs/progress/2026-09-30-int-63-bit-overflow-parity.md` made compiled `Int`
arithmetic wrap to 63 bits (`Llvm_ctx.emit_wrap_int63`, `shl 1` + `ashr exact 1`
after `+ - *` etc.). On `bench/fib.march` (`fib(n-1) + fib(n-2)`) the result then
reached `ret` as `sbfx x0, x19, #0, #63`, and LLVM's accumulator tail-recursion
elimination no longer fired: two recursive `bl _fib` per level instead of one call
plus a loop. Same-box A/B (wrap stubbed to the identity vs. on, `--opt 2`, 5
interleaved runs, 2026-10-01): fib ~450 -> ~540 ms.

## Why the "narrow peephole" cannot exist

LLVM's `TailRecursionElimination::eliminateCall` walks the instructions between
the recursive call and the `ret`; each must either be movable above the call or be
THE accumulator instruction (an associative+commutative binary op whose operand is
the call itself). Verified on the emitted IR with the system clang (`-O2 -c`,
count `bl` to `fib`):

| IR | recursive `bl` |
|---|---|
| as emitted (wrap between `add` and `ret`) | 2 |
| same, only the return-path wrap removed | 1 (TRE fires) |

So the ONLY blocker is a normalisation between the final `add` and `ret`. There is
no place to put it: normalising at the `ret` blocks TRE; normalising the call
results at the call site (`add(wrap(call), ..)`) also blocks it, because the call
must be the add's direct operand. A hand-written accumulator form in March source
(`fib_acc(n - 2, acc + fib(n - 1))`) measured identical to the two-call form (0.52 s
vs 0.52 s): the self-TCO loop pays a wrap on the accumulator per iteration plus a
second preemption check per iteration, which eats the saved call. The win needs the
return path to be bare, i.e. a different convention.

## The design: normalise where observed

Representation contract for a monomorphic `Int` in an `i64` register (and in a
function's i64 parameters and return value): the low 63 bits are the value, bit 63
is unspecified. `+ - *`, unary `-`, `int_shl` (and `int_pow`, `int_div`, `int_abs`,
whose only out-of-range result is 2^62) are ring operations modulo 2^63, so they
are emitted bare and left bare. Normalisation (`emit_wrap_int63`, unchanged) runs
at observation points, and there are exactly three kinds:

1. **Every i64 variable load.** `Llvm_emit.emit_atom` is the single funnel every
   consumer reads an operand through, because TIR is ANF: an `icmp` operand, a
   C-call argument, a NativeIntArr store, `sitofp`, a switch scrutinee, ... all
   read atoms. `emit_atom_raw` is the same read without the normalisation; it is
   used (a) for a tail-position atom (`ctx.norm_ret_pos`, the value goes straight
   to `ret`, which returns bare) and (b) for the operands of `+ - *` and negate,
   where a bare operand gives the same bare result. (b) is not just the saved
   shift pair: `fib(n-1) + fib(n-2)` must consume the call results DIRECTLY or TRE
   does not recognise the accumulator. Bool and Atom variables skip the pair (0/1;
   atom hashes are minted with bit 63 == bit 62).
2. **Tagging.** `emit_tag_scalar` is now a plain `shl` (was `shl nsw`): the shift
   drops bit 63, so a tagged word is always the canonical pattern and the ashr-1
   untag reads back the normalised value. `shl nsw` on a bare value would be
   poison, and LLVM may use an nsw fact to delete a normalisation downstream. The
   two trampoline tags in `llvm_calls.ml` (`$clo_wrap` result, `Ok` payload) follow.
   This also covers the C wire ABI: `clo_call_int_int`, `march_list_sort_by_int_key`
   etc. receive a tagged word and `>> 1` it.
3. **The REPL slot store.** `Llvm_repl.emit_store_to_slot` normalises a `TInt`
   fragment result before `march_repl_set`, since the C side prints it.

Plus one codegen change the win depends on: `Llvm_case.predicted_unboxed_tail` now
also predicts an **`i64` case-join slot** when every reaching arm's tail is
syntactically an Int/Bool scalar (literal, Int/Bool variable, `+ - * / %` with an
Int operand, a comparison or connective, or a call to a builtin / top-level function
returning Int/Bool). fib's `if` previously merged through a `ptr` slot (tag, then
conditional untag at `ret`), which under a plain `shl` is itself a sign-truncating
round trip between the `add` and the `ret`. A wrong prediction stays well-typed:
the arm store goes through `coerce`'s conditional untag.

What is deliberately NOT an observation point: a user-function argument or return
(bare in both directions; the callee's loads normalise), `and/or/xor/not` (bitwise,
commute with truncation — their operands are still read normalised, LLVM folds the
redundant pairs), `phi`/slot merges.

Cost model: a round trip through an erased slot of a value LLVM cannot prove
normalised (a parameter, a C result) is now one `sbfx` where the nsw fold made it
free; a fresh arithmetic result stored to a data structure is now `lsl` only where it
was `sbfx` + `lsl`. LLVM removes a normalisation whose input has two known sign bits
and CSEs the ones a variable's repeated uses emit, and folds `wrap(n) < 2` into a
shifted compare, which is why fib's compare costs nothing.

ABI note: a function compiled by this compiler returns a bare i64 to C
(`--compile-so` exports, `dllexport` HCR entries). The value differs from the old
one only when the March result overflowed 63 bits; a C host that interprets it
should sign-extend from bit 62. Code from before this change mixed with code after
it (an old host, a new patch) sees the same difference, only on overflow.

## Verification

- `test_compiled_int_overflow_parity` (the existing gate) stays green; the new
  `test_compiled_int_overflow_lazy_norm_parity` reaches every observation point
  through a bare, actually-overflowing value: a caller's compare and int-literal
  match on a bare call result, the checked division helpers, right shift, popcount,
  `int_to_string`, `int_to_float`, a NativeArray store, a closure result over the C
  wire ABI (`NativeArray.map_int`), the C key sort (`Array.sort_by_key`, where raw
  keys would order the two elements the other way), a list cell, and the i64
  case-join slot. `test_jit`'s `orc_lazy_int_normalisation` pins the REPL slot store.
- `test_codegen`'s two `shl nsw` pins now assert a plain `shl` (and the absence of
  `nsw`).
- Cross-function tail calls still compile to sibling calls (a 20M-deep
  `ping`/`pong` runs in constant stack), since a tail atom is returned bare.
- TIR snapshots are unchanged (the change is entirely in `llvm_*`).

## Measurements

Same box (Apple Silicon, 1-min load average 8–13 — shared machine, above the <5
target; the fib delta is large and consistent, the others are within noise and
should be read as "no regression", not as a number). `--compile --opt 2`,
origin/main compiler (commit 8ee63159c, its own runtime and stdlib copies) vs this
branch, interleaved runs, first position discarded as warmup, wall time of the
whole process.

| bench | main min / med | lazy min / med | n |
|---|---|---|---|
| fib 40 | 530 / 530 ms | 430 / 440 ms (-19% / -17%) | 5 |
| list_ops | 40 / 50 ms | 40 / 50 ms (flat; below `time`'s 10 ms resolution) | 5 |
| tree_transform | 670 / 680 ms | 660 / 680 ms (flat) | 5 |

`fib`: the hot loop went from 23 instructions with two recursive `bl` and one
`sbfx` to 27 with one `bl`, zero `sbfx` and an accumulator (`add x20, x0, x20`).
