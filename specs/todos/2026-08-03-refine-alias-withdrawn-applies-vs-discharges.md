`[P4]` **`alias-withdrawn` attribution: "applies the spelling" ≠ "would have discharged".**

The verdict is `Skipped` — only the *reason* string is at stake. This is the
sole remaining item from a family of three; the other two (one-`let`-deep
laundering, and the direct-path subject-shadowing bug) were closed
2026-08-03 — see
`specs/progress/2026-08-03-refine-alias-withdrawn-attribution-shadow-fixes.md`.

Condition 3 of `alias_withdrawal_cause` tests that the guard applies the
withdrawn spelling to the argument, not that it would have proved the
obligation — so `if List.length(ys) >= 0 do head(ys)` blames the withdrawal
although `len >= 0` proves nothing about `len > 0`. Pre-existing, and identical
in the direct and laundered spellings (verified at both commits).
