# Completed Work Log

One file per completed item: `YYYY-MM-DD-slug.md`, dated by when the work
landed. This replaced a single monolithic `specs/progress.md` that every PR
prepended a new "Current State" entry to, which produced constant merge
conflicts and a file too large to read cheaply.

- `ls -t specs/progress` for newest-first.
- This is implementer-level detail — every fix, every internal refactor, at
  whatever granularity the author wrote it. For the user-facing digest of
  what shipped, see root `CHANGELOG.md` instead (different audience, see
  `CLAUDE.md`).
- When you finish a todo, `git mv` its file from `specs/todos/` into here
  rather than rewriting it from scratch — keep the filename's date as the
  filing date or update it to the completion date, either is fine, but don't
  lose the item's history mid-move.
- Test-count / "Current State" snapshots no longer live in one place that
  everyone edits; if you need the current test count, run the suite
  (`scripts/run-tests.sh`) rather than trusting a stale prose number.

See `specs/todos/README.md` for the open-items list.
