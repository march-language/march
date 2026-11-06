`[P2]` Diagnostics: run-time failures in the compile-error style (interpreter)

Filed and done 2026-11-05, from the diagnostics work ("runtime crashes in the same style").

Before: an interpreted panic printed `panic: <msg>` and a numbered `Stack trace` of
`name() file:line`; an unsupervised actor whose handler raised printed nothing at all (the
actor died, the program carried on and exited 0).

- `lib/eval/eval.ml`: `march_frame` gains `mf_span` (the call expression's whole span, already in
  hand at `march_stack_push`). New `actor_crash_hook`, called from the scheduler's handler
  exception path when the actor has no supervisor, with the actor's name, the message tag and
  arguments, the state, the handler's frames and the exception. A no-op unless the driver sets it.
- `bin/main.ml`: `report_runtime_failure` builds an `Errors.diagnostic` (codes `panic`,
  `runtime_error`, `actor_crashed`, category RUNTIME): the innermost user frame's span is the
  primary excerpt, each caller frame a label "`f` was called here". Stdlib frames are left out
  unless `MARCH_BACKTRACE=full` (the note about that is skipped when the only hidden frames are
  the prelude's panic wrappers). Up to 8 callers are shown. With no frame in a showable file it
  falls back to the old text. Exit codes unchanged.
- Corpus: `-- MARCH-MODE: run` in `test/run_errors.ml` runs a case and pins its stderr
  (`panic_1`, `runtime_error_1`, `actor_crashed_1`); `scripts/error-one-turn.sh` skips
  `MARCH-MODE` cases, which are not `--check` failures.
- Error Messages tour: section 11, two examples; `scripts/gen-error-tour.py` markers accept
  `--run`.

Not done (see `specs/todos/2026-10-14-diagnostics-backtrace-followups.md`): compiled programs
(still `panic: <msg>` only), supervised crashes (not printed, by choice: the supervisor handles
them), the value of the failing operands (`sum / n` with `n = 0`), JSON output.
