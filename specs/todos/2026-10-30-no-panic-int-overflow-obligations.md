`[P2]` `cap no_panic` must prove Int `+ - *` and negation cannot overflow

Filed 2026-10-30 with the Int overflow trap
(`specs/progress/2026-10-30-int-overflow-trap.md`). Since then `+`, `-`, `*` and
unary `-` on `Int` panic when the result leaves [-2^62, 2^62), so they are panic
sites like `/` and `%`. A module declared `cap no_panic` promises none of its
functions can panic, but nothing checks the new sites: `fn inc(x : Int) : Int do
x + 1 end` in a `cap no_panic` module is accepted and panics at `int_max_value()`.

The trap made the checker's unbounded-integer model sound for programs that run
(every reached `x + 1` is in range, so `x + 1 > x` holds); this item is the other
half, that `cap no_panic` code never takes the trap.

**What to do.** Mirror `lib/refinecheck/division_safety.ml`, which finds every
divisor in a `cap no_panic` module and discharges `divisor != 0` with Z3 under the
path conditions and the operands' refinements:

- For each Int `a + b`, `a - b`, `a * b` and `-a` in a `cap no_panic` module, emit
  the obligation `-2^62 <= result < 2^62` (with `result` the unbounded value the
  checker already models), under the same facts `division_safety` uses.
- Literal-only operands settle syntactically; `x + 1` under `x < n` with `n` an
  array length or another bounded measure is the common case to make cheap.
- Do not emit obligations for `int_wrapping_add`/`_sub`/`_mul`, `int_abs`,
  `int_pow`, `int_shl` or `/` (they wrap, see `specs/lang/type-system.md`, "Int
  width and overflow"); `int_abs`/`int_pow`/`int_shl` may want their own trap first.
- Expect many obligations in stdlib `cap no_panic` code to be unprovable as
  written (counters with no upper bound); measure how many before choosing
  between a refinement on the counter and an `int_wrapping_*` spelling.

**Related, not done with the trap.** `int_abs`, `int_pow`, `int_shl`, the
`-2^62 / -1` quotient, `NativeArray.sum_int` (and the fused map-sum loop in
`lib/tir/llvm_emit_nmap.ml`) still wrap. Each is a separate decision: trap like
`+`, or keep wrapping and say so in the reference.
