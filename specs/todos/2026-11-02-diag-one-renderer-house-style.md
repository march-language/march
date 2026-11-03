`[P2]` Diagnostics: some errors bypass the renderer. `endpoints_label_invalid` and
`remote_actor_unroutable` print `file:line:col: error:` (positioned `Failure` printed raw near
`bin/main.ml` ~4232); `actor_handler_state_type` uses `'…'` quotes and no explain pointer. Raise a structured
diagnostic exception instead, add a style lint to `run_errors`, and give headers a category
(`-- TYPE MISMATCH --`, `-- CAPABILITY --`, `-- PROTOCOL --`). specs/plans/2026-11-02-diagnostics-depth-plan.md §X5.
