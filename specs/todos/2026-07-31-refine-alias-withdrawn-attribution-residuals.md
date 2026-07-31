`[P4]` **`alias-withdrawn` attribution: three known imprecisions, all message-quality.**

The verdict is `Skipped` in every case below — only the *reason* string is at
stake. Recorded together because they are the same family and all three trade
against the rule that a **wrong** attribution is worse than a vague one.

**1. One `let` deep, no deeper.** `let n = List.length(ys)` then `if n > 0` is
attributed to the withdrawal (done 2026-07-31); a chain
(`let a = List.length(ys)` then `let n = a`) still falls back to the general
`solver-undecided` message even when the withdrawal really was the cause.

**2. "Applies the spelling" ≠ "would have discharged".** Condition 3 tests that
the guard applies the withdrawn spelling to the argument, not that it would have
proved the obligation — so `if List.length(ys) >= 0 do head(ys)` blames the
withdrawal although `len >= 0` proves nothing about `len > 0`. Pre-existing, and
identical in the direct and laundered spellings (verified at both commits).

**3. The DIRECT path counts an application under a subject-shadowing binder.**
`if check(fn ys -> List.length(ys) > 0, zs) do head(ys)` fires `alias-withdrawn`
about the *outer* `ys`, although the guard's `ys` is the lambda's own parameter.
This is the mirror image of the laundered-path bug fixed 2026-07-31 with
`expr_mentions_free`, but the fix there was deliberately confined to the
accepting position on the laundered path: `expr_applies_to` on the direct path
behaves identically at the pre-2026-07-31 parent, so changing it alters
behavior that predates the laundering work and deserves its own decision.

If (3) is picked up, `expr_mentions_free` is the pattern to follow — and note
the distinction it documents: an over-approximate mention check is safe only in
a *discarding* position, never an accepting one.
