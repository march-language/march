`[P2]` Diagnostics: wrong hints and leaked internals. `List.filter(fn (x, y) -> …)` advises a curried
`fn a -> fn b -> …` (wrong: `pred` takes one argument); `x(x)` stacks four contradictory notes;
`refinement_violated_2` shows `$cb_arg` and suggests `if _ >= 0`; `cap_root_broad` on a type says "this
function". Make hint selection exclusive, fail `run_errors` on a fix that doesn't fix, and lint rendered
output for `$`, generated `S_`/`_Msg`/`_Run.` names and unwritten constructors. specs/plans/2026-11-02-diagnostics-depth-plan.md §X4.

Partly done 2026-11-02 (`specs/progress/2026-11-02-diag-hints-cascades-internals-lint.md`): the four hints above and
the internals lint (`test/errors/internals-allowlist.txt`). Open: hint exclusivity beyond `type_mismatch`, and failing
a case whose fix does not fix.

Fix-must-fix check and its triage done 2026-11-03 (`specs/progress/2026-11-03-diag-x3-x4-finish-x7-traces.md`).
What remains is the allowlisted leaks, which belong to the actor and choreography items.

Hint exclusivity beyond `type_mismatch`, closed 2026-11-05.

Survey: every `test/errors/*.json.expected` diagnostic with more than one note or message line
(about 150), plus every case where two diagnostics sit on one line. What was wrong:
- `cap_needs_7`, `proof_cap_return_1`, `proof_cap_return_2`: a `cap_root_broad` HINT ("consider
  narrowing `Cap(IO)` to e.g. `Cap(IO.FileRead)`") on the exact span of an error. In `cap_needs_7`
  it contradicts the error's fix (add `needs IO`) and names caps the module doesn't use. In the
  `proof_cap_return` cases it is about something else.
- `lemma_unproved_call_1`: a `refinement_unverified` HINT on the lemma warning's span repeats
  "precondition not proved here".
- `send_wrong_actor_2`: the note "`Counter` handles `Tally`" repeats the message's "`Tally` is also
  a handler of `Counter` … qualify it: `Counter.Tally`".
- `termination_unproved_1`: the generic note suggested "an exit such as `n <= 0`" right after the
  specific note proposed `n <= 0`, and it hardcoded `n` whatever the metric was called.
Everything else was compatible: context + cause (`In a list element.` / `This is the declared
return type…`), what / why / fix triples, or alternatives inside one `help:` line. The `List.map`
blame note in `type_mismatch_35`–`37` belongs to §X1 and was left alone.

Mechanism:
- `Errors.first_cause groups`: the first non-empty group of candidate explanations, most specific
  first. `type_mismatch` notes use it (occurs note > session > same-name > generic conversion).
- `Errors.suppress_cascades` has two new rules: an advisory HINT on the exact span of a visible
  error goes; a `refinement_unverified` hint on a `lemma_unproved_call` span goes, and the warning
  takes the precondition and the reason as one note. A final `tidy_notes` pass drops a note that
  repeats an earlier note or a message line. The LSP gets the same pass.
- `send_wrong_actor` drops the "handles" note when the qualify-it advice fires. `termination_unproved`
  drops the guard suggestion when the specific exit note fires, and otherwise names the program's
  own metric (`an exit such as `k <= 0``), or a generic exit when the metric isn't one variable.
- Hint-exclusivity lint in `test/run_errors.ml` (`check_hints`), with no allowlist: `[repeat]`,
  `[help]` (two `help:`/`hint:` lines), `[did-you-mean]` (two), `[convert]` (two conversion hints)
  and `[stacked]` (a HINT on an error's span). Shown red on a perturbed build that doubled every
  note and kept the stacked hint: `[repeat]`, `[convert]` and `[stacked]` all fired.

Failing a case whose fix does not fix: covered by `check_fix_fixes` in `test/run_errors.ml`
(2026-11-03). Re-checked 2026-11-05: dropping `cap_grant_12`'s `-- EXPECT-FIX-PARTIAL:` line fails
the case with "applying its machine fixes leaves the program rejected (exit 1)". A stale marker
fails too. The plan's "a strictly later error" allowance is not automatic: such a case needs the
marker and its reason.

Not done here: the second, wrong-direction `type_mismatch` in `type_mismatch_2` and
`cap_grant_17` (an `x ++ "no"` reported both as the return and as `x`). That is a poison-type
cascade (§X3), not a hint on one diagnostic.
