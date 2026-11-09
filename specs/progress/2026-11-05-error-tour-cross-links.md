Cross-links from the language docs to the Error Messages tour

Follow-up to march-language/march#1113, which added the tour (`docs/error-messages.md`).

- **Anchors.** Each of the 34 tour examples has an `<a id="<name>"></a>` line (the example's
  name without its `NN-` prefix) before its `### ` heading, outside the
  `<!-- error-tour -->` marker blocks that `scripts/gen-error-tour.py` rewrites.
- **Chapters.** `specs/lang/{type-system,capabilities,linear-types,actors,session-types,
  choreography,refinement-types}.md` each end with an "Errors you'll see" list, one plain
  link per tour example in that area (the Names and Types sections both go to Types). The
  syntax examples have no chapter to land in (`surface-syntax.md` is not published).
  `capability-enforcement.md` is about the OS sandbox, not the compile-time errors the tour
  shows, so it gets none.
- **Explain pages.** `scripts/gen-lang-docs.py` reads the tour page itself: for each example,
  its anchor, its `### ` title and the `[code]` tags in its ```text output. Every generated
  `docs/errors/<code>.md` with at least one example gains a "See it in the error tour" list.
  The list is added to the site page only; `specs/lang/errors/` (embedded for
  `march --explain`) is unchanged. An example with no anchor or heading is a generator error,
  and doc-lint Check F reports an explain page that is stale against the tour.
  Codes the tour shows that have no explain page yet (`unknown_record_field`,
  `unknown_constructor`, `arity_mismatch`, `missing_impl`, `cap_mismatch`,
  `linear_mixed_consumption`, `linear_captured`, `return_refinement_violated`,
  `division_by_zero`, `role_grant_exceeded`) get the link as soon as a page is added.
