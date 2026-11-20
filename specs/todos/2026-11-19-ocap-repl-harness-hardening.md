# Run-time authority REPL and conformance harness hardening (2026-11-19)

Found by the ocap phase 4 Task 7 review; one item, several small cleanups:

- `eval_prompt_decl` duplicates the `DLet` match block of `eval_decl`
  (lib/eval); share it.
- `repl_jit.ml` (around line 1325): the removed `List.hd` fallback also covered a
  single body with another name; say so in a comment.
- `test/run_cap_conformance.ml` REPL mode derives the grant from `main`'s request,
  so the `request_*` fixtures exercise `--grant` in the REPL rather than the
  request itself; document it or give the REPL a way to take the request.
- `spawn_mut_allowed` was restructured around the REPL prompt's typing limits;
  revisit once prompt typing can see the preloaded declarations.
- `repl_error_line` recognises errors by prefix, so a capitalised `Error:` or a
  differently worded message slips through; match the REPL's own error marker.
- `main_body` / `without_main` in the conformance runner assume `main` ends at
  the first two-space `  end`; parse the file instead.
