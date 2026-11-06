Diagnostics: four messages that cost a second turn (2026-11-06)

From the one-turn metric's failures on 2026-11-06
(`specs/progress/2026-11-02-diag-one-turn-metric.md`): 365/400 before, 377/400 after.

- **Syntax error hiding `cap_needs`.** `bin/main.ml`, where a failed parse is reported: when the
  source has a zero-argument `main` whose body calls `println(` / `print(`, and no `needs IO`
  line, the first parse diagnostic gets a note saying `main` will also need `needs IO.Console`
  and a `Cap(IO.Console)` parameter. It is a scan of the text, since there is no AST: comments
  are cut at `--`, `main`'s body runs to the `end` at its indentation. It misses a `main` that
  prints through a helper, and it is not shown by the LSP. A recovering parser would replace it.
- **Protocol loops.** `Protocol_states.at_loop_start` says whether a state is the first step of a
  `loop` body. `report_protocol_step_order` (`typecheck_unify.ml`) adds a note when the role
  closes there: a repeating branch comes back to this state, pass it on instead of closing.
  `report_linear_never_used` (`typecheck.ml`) adds, for a never-used value whose type is a
  protocol state, what the role must do next and the function that takes the step.
- **Crash declarations.** `may crash D` with an unknown role lists the protocol's roles and says
  what declaring one costs; a crash branch on a role not declared `may crash` says to remove the
  branch (declaring the role instead triggers the detection rules, which is where the answers
  went wrong).
- **`len(xs)` in a suggested guard.** `refine_call.ml`: the guard example for a `List.` call
  prints the measure `len(` as `List.length(`. `refinement_violated_19`'s `EXPECT-ERROR` pin
  follows.

Not done: `type_mismatch_13` (the crash-branch detection rules, reported one at a time);
unknown constructors could list the functions that build the annotated type; type names in a
mismatch that cannot be written as printed (`FileError`).
