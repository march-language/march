# DONE 2026-10-07: D3, a code on every diagnostic, and `march --explain`

Diagnostics plan (`specs/plans/diagnostics-and-triage-plan.md`) §7.

## What landed

- **`lib/errors/code.ml` (`March_errors.Code`, re-exported as `Errors.Code`)**:
  one constant per slug, `all`, `with_arg`/`slug_of`. 162 slugs at landing:
  the 15 already in use (`unused_binding`, `unused_import`, `cap_grant`,
  `no_alloc*`, `unknown_record_field`, `or_pattern_binding`,
  `curried_lambda_over_tuple`, `annotated_tyvar_fixed`, `redundant_arm`,
  `redundant_csrf_token`, D0's `parse_error`/`syntax_error`/`lex_error`) plus one
  per condition at every previously code-less site. Codes stay slugs, as the plan
  decided; nothing that keyed on an existing slug changed.
- **`code : string` is non-optional** on `Errors.diagnostic`. Every helper
  (`error`, `warning`, `hint`, `error_with_fix`, `warning_with_fix`, …) takes a
  required `~code`. All ~290 construction sites were migrated (typecheck and its
  submodules, caps, modcaps, tailcall, session, exhaustiveness, refinecheck,
  division safety, abstract refinements, desugar and its endpoint/derive/remote
  passes, `vectorize_check`, `alloc_contract`, prelude collisions, the parser via
  D0's `Parse`, the CLI's own diagnostics). Helpers that report several
  conditions (`desugar_expr_error`/`_warning`) take `~code` at each call site.
- **Two codes carry an argument**: `cap_needs:<caps>` and `cap_ceiling:<cap>`,
  built with `Code.with_arg`. `bin/toolchain.ml`'s hint de-duplication parses
  the capability set out of `cap_needs:`, so the argument stays; the slug
  (`Code.slug_of`) is what the renderer, `--explain` and Check G see.
- **Renderer**: the headline (the message's first line) ends in ` [slug]`. It
  is appended to the line, never inserted, so every `grep -qF` fragment in the
  `EXPECT-ERROR` corpora and the alcotest message assertions still matches. The
  first time a run renders a code that **has a page**, the diagnostic adds
  ``run `march --explain <slug>` ``; later diagnostics with that code don't
  repeat it. The CLI's compact `file:line:col: error: msg` form (desugar
  diagnostics, `march caps`) carries the same suffix. (Deliberate narrowing of the plan's "once per distinct code": a
  pointer to a page that does not exist yet would be noise.) `--check-json`'s
  `"code"` is now always a string, never `null`.
- **`march --explain <slug>`** prints `specs/lang/errors/<slug>.md` (front matter
  stripped) or `no page yet for <slug>`. The pages are embedded at build time by
  a dune rule (`lib/errors/gen/gen_explain_pages.exe` over
  `specs/lang/errors/*.md` → `explain_pages.ml`), so an installed compiler needs
  no repo beside it.
- **Ten pages**, chosen by counting the first diagnostic's slug over the
  `specs/lang/{types,grammar}/reject/` corpora: `cap_grant` (33), 
  `linear_never_used` (24), `linear_used_twice` (21), `type_mismatch` (20),
  `refinement_violated` (12), `unknown_qualified_name` (10), `linear_discarded`
  (10), `parse_error` (9), `linear_generic_param` (8), `cap_needs` (8). Each has
  the plan's shape (meaning, minimal failing program, fixed program, why); every
  failing program was checked to produce exactly its slug and every fixed one to
  pass `march --check`.
- **`scripts/gen-lang-docs.py`** renders `specs/lang/errors/*.md` →
  `docs/errors/<slug>.md` (no table: the file name is the slug), with relative
  links re-resolved from `docs/errors/`; orphaned generated pages are an error.
  Check F covers them.
- **doc-lint Check G**: `code.ml`'s `all` equals its constants; every page names a
  registered slug (pages ⊆ `Code.all`; the converse is not required while pages
  accrue); no `code = "…"`, `code = Some "…"` or `~code:"…"` literal in `lib/`,
  `bin/`, `lsp/lib/`, `forge/lib/` outside `code.ml`. Each of the three was
  shown red on a throwaway perturbation.
- **LSP**: `code` is always set; `codeDescription.href` points at the page on
  march-lang.org for codes that have one; `code_actions_diag.ml` matches
  `Code.unused_binding`/`Code.unused_import` instead of literals.

## Verification

- `scripts/types-oracle.sh`: baseline recorded with `main`'s compiler (c31ef539a)
  **in this same checkout** (derive-generated spans hash the absolute path, so a
  baseline from another checkout differs on 55 fixtures for that reason alone),
  checked with a one-off `MARCH_DIAG_NO_CODE=1` switch that disabled the suffix
  and the explain line (the switch was removed before commit). Result: **Tier 2
  (all diagnostic text) identical, 9525 lines over 906 fixtures**; Tier 1
  differs on 320 fixtures, and in every one the only difference is
  `diagnostics[].code` going from `null` to its slug (checked structurally with
  the `code` field removed). Red: with the suffix on, Tier 2 reports 4169
  differing lines. The baseline was then re-recorded with the suffix on.
- Grammar/type `check_*.sh` corpora still green (fragments are substrings of
  the headline; the suffix is appended after them).

## Next D3 step (out of scope here)

Lowering still rejects with `failwith "file:line:col: error: …"` strings (16
sites in `lib/tir/lower*.ml`, caught in `bin/main.ml`), and the resolver and
module registry report through strings/exceptions. They become diagnostics with
codes next; until then they carry no code and no `[slug]`.
