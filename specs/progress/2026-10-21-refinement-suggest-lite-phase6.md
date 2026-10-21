# Inference-lite, phase 6: LSP and report integration

Landed 2026-10-21. Design §4.4-§4.5. Plan Task 13.

- JSON v1 `edit` is now filled: the driver runs the same `Refine_edit` splice `--refine-infer-apply`
  writes and emits the minimal byte range against the original file.
- `lsp/lib/refine_command.ml`: `infer_byte_edits` (from the JSON), `workspace_edit_of` (annotated
  edits + a `needsConfirmation` change annotation, label `adds an unproven obligation at k callers`,
  for a precondition/element-param/accumulator with new caller skips), `run_infer`.
- Code actions "Infer refinements for `f`" and "Infer refinements in this file"
  (`march.inferRefinements`, commands not edits); the server handles and advertises the command.
- `--refine-report --refine-infer`: `refinement obligations (user code, if applied): V violated,
  S skipped`, plus `closes k of m cap verified error(s)` for a `cap verified` module.

Tests: `lsp/test` group "infer-refinements code action" (offered; editor bytes equal
`--refine-infer-apply`; confirmation label); `test_refinecheck` `infer-apply` "if applied equals the
report after --apply". Full LSP suites green.
