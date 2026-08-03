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
