# LSP: stale completion-resolve edits landing on the wrong line, and unbounded tvar-name growth

Diagnosed from a user's screen recording of the March LSP (in Zed) apparently
corrupting an unrelated line while they typed elsewhere, plus diagnostics
showing internal type-variable names like `Option(u52)`/`Option(y55)`
stacking up with ever-growing suffixes.

## Bug 1 — completionItem/resolve can insert an edit at a stale, wrong location

`Analysis.import_text_edit` (`lsp/lib/analysis.ml`) computes where to insert
an auto-import (`use Module.{name}`) independent of the cursor — it targets
"the first user declaration line," not wherever the user is typing. Zed (like
other LSP clients) fires `completionItem/resolve` per keystroke as the
completion list narrows, not only on accept, and the handler
(`lsp/lib/server_dispatch.ml`, `completionItem/resolve`) re-fetched the
cached `Analysis.t` for the document with no check that it was still current.
So a resolve request answered against a buffer state from before the user's
most recent edits could compute an import-insertion edit whose target line
no longer means what it did when computed — landing inserted text on an
unrelated, already-existing line instead.

Every other LSP handler (completion, code-action, hover, …) shares this same
gap: only `on_notif_doc_did_change`'s own debounce guards itself
(`server_state.ml`'s `versions`/`is_current`); nothing else checks.

**Fix (narrow, targeted at the confirmed corruption path):**
- `on_req_completion` (`server.ml`) now stashes the document's current
  version alongside `uri` in each auto-import completion item's `data`.
- `completionItem/resolve` (`server_dispatch.ml`) checks `is_current` against
  that stashed version before computing/returning the edit; a stale request
  gets no edit instead of a wrong one.

Code-action wasn't given the same guard: `CodeActionParams.textDocument` is
an unversioned `TextDocumentIdentifier` per the LSP spec, so there's no
client-supplied version to check against, and it computes ranges from the
same request's `range` (not from a cached, cursor-independent line).

## Bug 2 — diagnostic messages leak an ever-growing internal counter

`Typecheck_types`' `tvar_display_name` caches unresolved-type-variable
display names (`a`, `b`, … `y55`, …) in a global `_tvar_names` table keyed by
`_tvar_ctr`, incremented on each new one seen. A one-shot compiler run never
notices — the process exits after a single `check_module`. The LSP is a
long-lived process re-typechecking on every edit; left alone this counter
climbs for the server's entire lifetime, so an unresolved variable in a small
file can print as `y55` instead of `a`, and multiple diagnostics from
different analysis passes show wildly different-looking (but equally
meaningless) names.

**Fix:** `Typecheck_types.reset_tvar_display_names ()` (new, exported through
`typecheck_types.mli` and `typecheck.mli`) clears `_tvar_names` and resets
`_tvar_ctr` to 0. Called once per analysis pass, at the top of
`Analysis.analyse` (`lsp/lib/analysis.ml`) — deliberately NOT touching
`_counter` (the actual fresh-id source, which must stay monotonic for
unification correctness, per the file's own header) or the CLI compiler
path, which doesn't have this problem in the first place.

## Evidence

- `lsp/test/test_jsonrpc.ml`'s `completionItem/resolve` coverage test updated
  to stash a matching `version` in its hand-built completion item (the
  staleness guard now requires one); full LSP suite (354 tests) passes.
- `scripts/run-tests.sh` (full suite, including Slow) — all suites pass.
- Manually confirmed via the compiler CLI that repeated invocations don't
  regress (this fix is LSP-process-scoped, not wired into `bin/main.ml`).
