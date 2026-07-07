---
name: spec-search
description: Full-text search over the March language reference (specs/lang), internals reference (specs/impl), and feature design docs (specs/features) — ~44 files, ~20-25k lines. Use this whenever a March language/semantics/design question isn't answered by march-lang's condensed quick-reference: deeper actor/supervision semantics, refinement types, session types, module system, capabilities, linear types, or any "how does March handle X" question. Works in any March project — the docs and index are bundled with this skill, not read from the current repo.
---

# March Spec Search

A SQLite FTS5 index over March's language/design docs, bundled with this
skill so it works in any March project without that project needing its own
copy of `specs/lang/`.

## When to use this vs. `march-lang`

- `march-lang` — always-loaded quick-reference for the most common syntax
  mistakes (conditionals, lambdas, visibility, etc). Check there first.
- `spec-search` (this skill) — on-demand deep search when the question goes
  beyond that quick-reference: full semantics, design rationale, actor
  supervision trees, refinement predicates, session types, capabilities,
  module/interface resolution rules, etc.

## How to search

Run the bundled query script, using this skill's own base directory (shown
in the tool result when this skill was invoked):

```bash
<skill-base-dir>/spec-search.sh --json -n 5 "<query>"
```

This returns a JSON array of hits, each with `file`, `heading_path`,
`lineno`, `end_lineno`, `snippet`, `score` (lower `score` = better bm25
match, results are already sorted best-first).

Query tips:
- Use a few keywords, not a full sentence — e.g. `"actor supervision restart"`,
  not `"how do actors restart after a crash"`.
- Each word is matched as a literal token ANDed together; there's no need to
  quote or escape anything yourself.

## Reading the matched section

Do **not** read the whole file — some chapters are 1000+ lines. For each
promising hit, `Read` only the matched section using `lineno`/`end_lineno`:

```
Read(file_path="<skill-base-dir>/docs/<hit.file>", offset=<hit.lineno>, limit=<hit.end_lineno - hit.lineno>)
```

`<hit.file>` is relative to `<skill-base-dir>/docs/`, e.g. `lang/actors.md` or
`features/module-system.md`.

If the top hit's section doesn't fully answer the question, check the next
1-2 hits, or re-run the search with different keywords — don't guess past
what the index actually returned.

## Notes

- This skill's `docs/` and `spec-search.db` are a point-in-time snapshot
  (see `<skill-base-dir>/spec-search.db`'s `meta` table for the source
  commit/date), refreshed manually from the March compiler repo. If an
  answer seems inconsistent with the actual installed March compiler's
  behavior, prefer the compiler's own error messages and `specs/` if
  present in the current project over this snapshot.
