# `docs/` and `specs/lang/` held two divergent copies of every language chapter

**DONE 2026-09-22 (option 1: `specs/lang/` canonical, `docs/` generated).** The original
report is kept below the line.

**What was done.**
- **Reconciled first, generated second.** There were 16 pairs, not the 5 this todo listed.
  14 share a name. `specs/lang/type-system.md` is the twin of `docs/types.md`, since both
  carry `permalink: /docs/types/`. The OS-enforcement and hot-deploy sections of
  `specs/lang/capabilities.md` were a third copy of `docs/capability-enforcement.md`, the
  page the site split out in 9b628fcfe (#553/#555/#560 edited both). They moved to a new
  canonical `specs/lang/capability-enforcement.md`. Each pair was diffed hunk by hunk.
  Content that existed only in `docs/` and was still true moved into `specs/lang/`.
  Contradictions were decided against the compiler and the source, and several claims
  wrong in both copies were rewritten. There is one commit per chapter, and each commit
  message names what moved and the evidence. The per-chapter table is in the PR
  description.
- **`specs/lang/index.md` is deliberately not generated.** `docs/index.md` is the site's
  landing page, a different document from the spec's umbrella index.
- **Generator: `scripts/gen-lang-docs.py`.** It renders every `specs/lang/*.md` that has
  Jekyll front matter into `docs/`, using an explicit `CHAPTERS` table
  (`type-system.md → types.md`). Rendering keeps the front matter, drops the specs-only
  "Part of the March Language Reference" banner, and inserts a `GENERATED from …`
  comment. It also re-resolves relative links: another chapter becomes its `docs/` name,
  a `docs/` file becomes relative to `docs/`, and anything else becomes a github.com URL.
  A dead relative link, a front-mattered chapter missing from the table, or an orphaned
  generated page is a hard error.
- **CI:** `scripts/check-docs.sh` Check F runs `gen-lang-docs.py --check` on every PR.
  Unlike stdlib Check D it is not gated: the generator is pure text, so a source edit and
  its regenerated page land in the same PR.
- **Search index:** generated pages are ordinary `docs/*.md`, so
  `sync-docs-search-index.yml` (triggered by `docs/**` on main) regenerates
  `docs/pagefind/` after merge. PRs still must not carry `docs/pagefind/`.

**How it was verified.**
- `scripts/check-docs.sh` passes. RED controls:
  - a hand-edited `docs/supervision.md` heading → Check F `STALE: docs/supervision.md …`,
    exit 1. Regenerating restores a byte-identical page and exit 0.
  - a `specs/lang/actors.md` edit without regenerating → STALE, exit 1.
  - a dead relative link → ERROR, exit 1.
  - a new front-mattered chapter missing from `CHAPTERS` → ERROR, exit 1.
- The site was built locally with the deploy-pages toolchain (Ruby 3.3, `bundle exec
  jekyll build`) at origin/main and after generation, and every internal `href` and
  `#anchor` in `_site` was checked. There were no new broken links. Three that were
  broken on chapter pages are fixed: `capabilities` → `surface-syntax.md`,
  `pattern-matching` → `../../docs/tour.md`, and `refinement-types` →
  `#cap-verified--making-silence-an-error`. The 142 remaining broken links are all on
  pages this change does not generate.

---

# `docs/` and `specs/lang/` hold two divergent copies of every language chapter

Filed 2026-08-03, found while making the phase-1 memory-model corrections.

## Problem

Every language-reference chapter exists twice, as full independent prose — not as
a page plus a redirect stub:

| chapter | `docs/` | `specs/lang/` |
|---|---|---|
| memory-model | 310 lines | 311 lines |
| linear-types | 352 | 386 |
| capabilities | 837 | 820 |
| actors | 506 | 566 |
| refinement-types | 1179 | 1927 |

They have already drifted — the two memory-model intros were differently worded
before this edit, and the refinement-types pair differs by 748 lines.

`docs/` is the Jekyll root, and these pages carry `permalink: /docs/<topic>/`, so
**`docs/` is what the website serves**. `specs/lang/` is what `specs/lang/index.md`
presents as the language reference, and what CLAUDE.md's doc-lint guards. An edit
to the reference chapter therefore does not reach a single reader unless the
`docs/` twin is edited too — which is exactly the trap the memory-model fix hit:
the correction initially landed only in `specs/lang/`, leaving the published page
still claiming "No pause."

## Fix

Pick one direction and make the other mechanical:

1. **`specs/lang/` is canonical, `docs/` generated** — add a build step that
   renders each chapter into `docs/` with its front matter, and CI-check that the
   committed output is current (same shape as the existing stdlib-docs generator).
2. **or `docs/` is canonical** and `specs/lang/*.md` become one-line pointers.

Option 1 matches how the stdlib API docs already work and keeps the reference in
the repo where the doc-lint runs.

Until then, **any language-doc edit must be applied to both files**, and doc-lint
should grow a check that the pairs have not drifted — a cheap version is to
compare section headings between each pair and fail on a mismatch.

## Note for the release-plan work

Phase 2's docs items (tiered nav, limits sections, `/docs/formalization/`,
`/docs/comparison/`) all touch these files. Resolving this first avoids doing
every one of those edits twice, or doing them once and silently shipping nothing.
