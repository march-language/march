`[P2]` Diagnostics: one renderer, one house style. Done 2026-11-03
(specs/plans/2026-11-02-diagnostics-depth-plan.md §X5).

**One renderer.** Desugar's diagnostics (`endpoints_label_invalid`, `endpoints_name_clash`,
`remote_actor_unroutable`, `unknown_derive`, `satisfy_missing_fn`, `codec_missing`,
`cap_deserialize`, `pid_serialize`, `main_signature`, the redundant-CSRF warning, …) were printed
as raw `file:line:col: error: …` lines before typechecking, and were missing from `--check-json`.
They now join the typechecker's diagnostics before `suppress_cascades` (bin/main.ml), so they are
rendered with header, caret, code and explain pointer, sorted with the rest, emitted by
`--check-json`, and subject to the cascade rules (the `endpoints_label_invalid` rule could not
fire before). `march test` renders them too. The two positioned `Failure`s in lowering (a
first-class `tap`, the interpreter-only builtins) raise `Errors.Diagnostic_exn` with the new code
`compiled_unsupported`; the driver catches it once and renders it. The `": error: "` string
sniffing in the lowering handler is gone: a `Failure` there is now always an internal error. A
`Printexc` printer keeps `Diagnostic_exn` readable in generic catch-alls (REPL, contract
pipeline). The bespoke `-- CAPABILITY CEILING --` header is `-- CAPABILITY --`. Import-resolution
errors (module not found, circular import, unreadable file) render as `import_unresolved`
diagnostics, and the prelude-collision check uses the renderer too. Because desugar errors now
take part in cascade suppression, `cap_grant` no longer follows an `unknown_derive` /
`satisfy_missing_fn` error (`cap_grant_22`, `cap_grant_23` lost their `EXPECT-FIX-PARTIAL`
marker: they have no fix left). run_errors' `after fix:` line shows the first ERROR block's
headline, not a hint that renders ahead of it.

**Categories.** `Code.category_table` gives every code one of 15 categories, the header title:
SYNTAX, NAMING, TYPE MISMATCH, TYPE, INTERFACE, PATTERN, CAPABILITY, LINEARITY, ACTOR, PROTOCOL,
REFINEMENT, RECURSION, CONTRACT, UNUSED, PROGRAM. An error renders `-- TYPE MISMATCH ---- file`; a
warning or hint keeps its severity first, `-- WARNING: UNUSED ---- file`,
`-- HINT: REFINEMENT ---- file`, so "is this fatal" is still the first word for a non-error. The
header keeps its old total width. `--check-json` objects gain a trailing `"category"` field (every
existing field unchanged and in place); `--emit-core-ast`'s versioned document does not.
`Errors.header_severity` reads a header back; forge's build summary and
`scripts/check-stdlib-doctests.py` count errors by that rule instead of `-- ERROR`. The LSP builds
its diagnostics from the records, not the rendering, and is unaffected; its non-exhaustive-match
quick-fix strips the message's new terminal period. test_compiler checks every code has exactly
one category.

**House-style lint** (`test/run_errors.ml`, over each case's `--check-json` messages and notes):
`quote` (no `'ident'` outside backticks), `capital` (headline starts upper-case or with a
backticked name), `period` (headline ends `.?!:`), `prefix` (no `Warning:` inside a message).
Fixed: `actor_handler_state_type` ("The handler for `Poke` in actor `A` must return the actor's
new state, a `{ n : Int }`, but returns `Int`."; its notes backticked), `non_tail_recursion`
(no "Warning:"), the F1 subjects ("The `Inc` handler of actor `Counter` prints, …"),
`cap_ceiling`, `import_cap_missing`, `cap_root_broad`, `cap_narrow_invalid`,
`extern_needs_foreign`, `io_not_allowed`, `proof_cap_*`, `realtime_mixed`,
`role_grant_exceeded`, `unused_needs`, `unknown_attribute`, `invalid_decreases` (capital),
`satisfy_missing_fn`, `stdlib_internal`, `non_exhaustive_match` (period).
`test/errors/style-allowlist.txt` (`<slug> <rule>`, may only shrink) holds the rest:
`type_mismatch` capital (owned by the type-mismatch rewrite), the refinement/proof family
(`refinement_*`, `division_by_zero`, `int_overflow`, `lemma_*`, `invalid_lemma`,
`invalid_reflect`, `invalid_decreases`, `termination_unproved`), and `parse_error` period
(its text is matched in `parse.ml` and raised from `parser.mly`).

New corpus cases: `actor_handler_state_type_1`, `satisfy_missing_fn_1` (seeded from
`specs/lang/types/reject/t24`). `endpoints_label_invalid_{1,2}`, `remote_actor_unroutable_1`,
`unknown_derive_1` and `type_mismatch_13` (`endpoints_name_clash`) now show the standard rendering
and have `--check-json` output.

Not done here: `role_needs_invalid` / `protocol_invalid` still put the caret on the role or
`protocol` keyword rather than the step (§X5 evidence; a protocol-span change, F3); the
"no `I got` for type mismatches" rule waits on the type-mismatch rewrite.
