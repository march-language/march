`[P2]` Diagnostics: wrong hints and leaked internals. `List.filter(fn (x, y) -> …)` advises a curried
`fn a -> fn b -> …` (wrong: `pred` takes one argument); `x(x)` stacks four contradictory notes;
`refinement_violated_2` shows `$cb_arg` and suggests `if _ >= 0`; `cap_root_broad` on a type says "this
function". Make hint selection exclusive, fail `run_errors` on a fix that doesn't fix, and lint rendered
output for `$`, generated `S_`/`_Msg`/`_Run.` names and unwritten constructors. specs/plans/2026-11-02-diagnostics-depth-plan.md §X4.
