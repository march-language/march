`[P2]` Isolated solver modes: `assert P by bitvector`, `by nonlinear`, `by compute`.

Source: `specs/2026-11-08-auto-active-verifier-lessons.md` (research survey, 2026-11-08), recommendation 4.

## Why

Verus discharges `assert P by(bit_vector)`, `by(nonlinear_arith)`, `by(integer_ring)` and
`by(compute)` as separate queries that see no ambient facts unless they are passed in. Hard
theories then stay out of every other query, which keeps the default context linear and fast.
Step 11 needs it: proving `Set`/`Map`'s lookup and remove contracts needs bit-level facts
about `bitmap_set`/`bitmap_has`/`bitmap_rank`/`int_popcount`
(`2026-11-06-prove-map-set-contracts`, stage C). Today those can only be trusted laws.

## Wanted

- `assert P by bitvector(x, y) do … end`: P is checked in a bit-vector encoding of March's
  Int. That encoding must model the 63-bit normalisation of compiled Int,
  with only the named facts imported. On success P is available as an ordinary
  fact.
- `by nonlinear`: P checked with nonlinear arithmetic enabled, isolated.
- `by compute`: P is closed and decided by evaluation (reflection/PLE), with no SMT at all.
- Each mode's VC is cached like any other.

## Done when

The bitmap rank/set laws the HAMT proof needs are proved with `by bitvector`, not assumed. There
are negative controls (a wrong mask, off-by-one shift). An unsupported operation in a
bit-vector block is a clear error, not an `unknown`.
