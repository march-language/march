`[P3]` Reflected arithmetic is over mathematical integers; compiled `Int` is 63-bit and wraps.

Decision D8 and fact F18 of `specs/2026-10-29-refinement-reflection-design.md` (§9.1 "Int overflow",
§9.3, and phase 6 in §10).

- The checker's `Int` is unbounded; the runtime normalises to 63 bits. A reflected `inc(n) = n + 1`
  makes `{Unit | inc(n) > n}` true in the logic and false at the maximum `Int`.
- D8 keeps the logic mathematical and says so in the reference; the overflow obligations come later.
  From phase 2 the `known_overflow` test pins the lemma as PROVED, labelled a known gap, so this phase
  has to flip it on purpose.
- Phase 6 decides the model for reflected bodies: a 63-bit wrap encoding (bit-vectors or `mod`
  arithmetic) for reflected arithmetic only, or an overflow obligation at every reflected `+ - *`.
  Bit operations (`int_and`, `int_shl`, …) can then join the R6 table (§2.3).
- The D16 parity net marks a boundary-input mismatch `overflow?` rather than a mismatch (§9.2); that
  mark is what this phase retires.
