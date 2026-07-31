# `alias-withdrawn` attribution follows a guard laundered through one `let`

Landed 2026-07-31.

**At landing:** `test_refinecheck` 403 (was 395: +6 — one laundered witness and five
wrong-attribution controls — then +2 review follow-ups, the lambda-param
collision control and its free-occurrence companion). Typing corpus 241/241,
grammar corpus 45/45 — no
corpus witness, deliberately: this change alters only the REASON on a skip, and
`check_types.sh` cannot pin message text on an accept, so the reason is pinned
in alcotest instead. CI obligation ratchet unchanged: `t118`'s user-code slice
still `1 proved, 0 violated, 0 trusted, 0 skipped` (floor 1) and
`stdlib/list.march`'s whole-program slice still `8 proved, 0 violated,
0 trusted, 28 skipped` (ceiling 28).

**What changed.** `alias_withdrawal_cause`
(`lib/refinecheck/refine_check.ml`) attributes a `cap verified` skip to a
withdrawn measure alias only under four conjunctive conditions, and condition 3
— "a positive path condition applies the withdrawn spelling to this
obligation's own argument" — accepted only the DIRECT spelling. The everyday
`let n = List.length(ys)` / `if n > 0` shape fell back to the generic
`solver-undecided` text, which points at z3 and advises the exact guard the
author had already written, while the real cause was a name-shadowing decision
possibly in a `MARCH_LIB_PATH` dependency they never opened. `visit` now
threads a fourth shadow-disciplined channel, `launder : (string * A.expr) list`
— single-name `let`s whose RHS is a direct application — and condition 3
additionally accepts a positive guard that mentions such a name when the
RECORDED APPLICATION applies the withdrawn spelling to the obligation's own
argument. One level only; the verdict stays `Skipped`, and the re-attribution
happens before `Obligation.record`, so the ledger and the diagnostic agree as
before.

**A wrong attribution is worse than a vague one, so every wrong-attribution
shape got its own control**, each green before the change (proving the walk
widened nothing else) and green after: a laundered guard on a DIFFERENT
collection (`let n = List.length(zs)`, obligation about `ys`) stays general,
because the walk consults `expr_applies_to` with the original argument, never
the let-bound name; a REBOUND laundering name (`let n = 5` between the `let`
and the guard) retires the fact; a REBOUND collection (`let ys = zs` in
between) retires it too — `launder_shadow` tests both the entry's key and its
RHS's mentions, the both-channels discipline this file has now shipped without
three times; a two-`let` chain stays general; and a negated laundered guard is
never blamed, through the existing polarity gate. The laundered witness was
RED before the fix (reported `solver-undecided`). One pre-existing
approximation is deliberately unchanged and now documented + filed: condition 3
tests that the guard *applies the spelling*, not that it would have
*discharged* the obligation, so `if List.length(ys) >= 0` over-attributes
identically in the direct and laundered spellings (probed empirically: both
report `alias-withdrawn`, direct behavior identical at the parent commit).

**Review follow-up (same day): the laundered mention check must be FREE.** The
review demonstrated a NEW wrong attribution (probe PE): `guard_applies` tested
the laundering name with `expr_mentions`, whose own doc comment says it is safe
only in a DISCARDING position because it counts a lambda parameter as a
mention. Used acceptingly, `let n = List.length(ys)` then
`if any_pos(zs, fn n -> n > 0) do head(ys)` blamed the withdrawal for a guard
that never used the length — the guard's `n` is the lambda's own parameter.
Fixed with `expr_mentions_free` (an occurrence not captured by an intervening
binder — lambda/`let fn` params, `let`/`let?` pattern binders with sequential
block scoping, match binders), used only in the accepting position; every
discarding site keeps the over-approximate helper, per its contract. The PE
control was verified RED against the unfixed code, and a companion pins the
other direction: `fn q -> q > n` — a genuine free use of the laundered length
under a non-colliding binder — must still attribute, so the fix cannot
over-retire. The review also surfaced the DIRECT path's mirror-image
pre-existing hole (`expr_applies_to` under a subject-shadowing binder, probe
PI, identical at parent) — filed in `specs/todos.md` rather than fixed, since
fixing it changes behavior that predates the laundering work.
