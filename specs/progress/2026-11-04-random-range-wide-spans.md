Fixed (found 2026-11-04 in the nightly `stdlib-properties` job, red on 2026-11-03 and
2026-11-04; no todo was filed): `Random.range(rng, lo, hi)` computed `hi - lo + 1`, which
overflows when the span is wider than the largest Int. Since Int `+ - *` panic on overflow
(`specs/progress/2026-10-30-int-overflow-trap.md`), the property "Msgpack Int int64 range
round-trips" (`test/stdlib/test_properties.march`, `Gen.int(-4611686018427387903,
4611686018427387903)`) panicked with "attempt to subtract with overflow".

A second, silent problem in the same function: `range` took one 52-bit `next_int` draw mod the
span. Its doc already said "Spans up to 2^52", so any wider span only produced `lo + [0, 2^52)`.
That int64 property never tested a positive value.

Fix (`stdlib/random.march`): `range` computes the span with `int_wrapping_sub` (negative means
2^62 or more) and takes one of three paths:
- span < 2^52: unchanged (same draw, same value for a given seed).
- 2^52 <= span < 2^62: `range_wide` draws 62 bits (`next62`: 31 bits from each of two
  `next_int` draws), masks them to the span's bit width, and retries until the draw is <= span.
- span >= 2^62: `range_full` draws a uniform value over the whole Int range (an extra bit picks
  the sign half: `bits` or `-1 - bits`) and retries until it lands in `[lo, hi]`.
Each retry succeeds with probability at least 1/2. No intermediate value overflows.

Tests (`test/stdlib/test_random.march`): a 0..2^62-1 range stays in bounds and reaches values
above 2^52; a -(2^62-1)..2^62-1 range does not panic and produces large values of both signs;
a narrow span still equals `int_mod(next_int(seed), span)`. The first two failed against the old
stdlib (the panics above). Checked interpreted and compiled.
