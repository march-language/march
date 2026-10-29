`[P4]` Sign-selected multiplier for constant-divisor floor division (Ben Joffe, 2026). Gated.

Phase 3 of `specs/2026-10-29-floor-division-and-const-divisors-design.md`. Blocked on the
inline-const-divisors / `int_div_floor` item.

Read the article's Annexure A proof and `benjoffe.hpp` first (this design was written from a summary).
Land only if `bench/int_div_const.march` shows a win over the Phase 1 inline fix-up form, not over
today's helper call; otherwise close it into `specs/progress/` as "measured, not worth it". Constants
must come from a derivation that returns `None` when validity is not established, and be verified
exhaustively at 8/16-bit width plus a wide 64-bit divisor sweep.
