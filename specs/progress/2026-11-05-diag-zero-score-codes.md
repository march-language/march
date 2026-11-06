`[P2]` Diagnostics: the five codes the one-turn metric scored at zero

Filed and done 2026-11-05, from the one-turn re-measurement in
`specs/progress/2026-11-02-diag-one-turn-metric.md` (`protocol_same_participants`,
`division_by_zero`, `protocol_invalid`, `overlapping_impl`, `role_grant_exceeded`: 0/18).

Most of the 18 failed on the `cap_grant` error that only appeared after the first fix, which the
`cap_grant`-shown change (`specs/progress/2026-11-05-diag-cap-grant-shown.md`) addresses. With it,
13/18. The rest were messages that did not say what to write:

- `role_grant_exceeded` (`Typecheck.role_grant_help`): the help said "add `IO.X` to
  `role R needs ...`", but each granted path is a body parameter (D34, `Desugar_endpoints.grants_of`),
  so that edit alone breaks the body's arity. The help now gives the widened line and the body's
  parameter list, e.g. `fn (s, cap_console, cap_file_write, st) -> ...` (`cap_` keeps the names
  off builtins such as `file_write`), and says to pass the new one on.
- `division_by_zero` (`Division_safety.local_division_suggestion`): for a divisor that is a pattern
  binder or a `let`, "annotate the divisor parameter" named an edit that does not exist. It now says
  the value is not a parameter and spells the guard the checker reads as proof:
  `if n == 0 do <fallback> else ... / n end`. Parameter divisors keep the old wording.
- `protocol_invalid`, a step after a `choose` whose branch ends in `loop` or `stop`: it said "move
  it inside the branches that can reach it". It now names those branches (the siblings that do not
  end in `loop`/`stop`) and says a several-step branch lists its steps on the lines after the label,
  with no `do`/`end`.

New explain pages: `specs/lang/errors/role_grant_exceeded.md` and `division_by_zero.md`;
`protocol_invalid.md` gains the `choose` case. Corpus: 11 `.expected` files (the three messages and
the new explain pointers). One-turn: 13/18 → 17/18; `overlapping_impl_1` is an intent-check limit
(the correct fix renames a declared type), recorded in the metric file.
