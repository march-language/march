# Nightly runs only when main is green and has moved (2026-09-21)

`nightly.yml` rebuilt and republished every night whatever state main was in:
a red main shipped as a nightly, and a quiet day produced a byte-for-byte
rebuild of yesterday's commit under a new tag.

A new `gate` job runs first; every other job needs it and checks out the commit
it picks (`needs.gate.outputs.sha`), so `version`, `build`, `publish` and the
rolling `nightly` tag all agree on one commit instead of each reading main's
HEAD at a different moment.

- **Green:** CI's push runs on main, newest first. In-progress runs are skipped
  over, so a merge just before midnight does not cost the night; the first
  completed run decides: `success` makes its commit the candidate;
  `failure`/`timed_out`/`startup_failure` means main is red and nothing runs.
  Cancelled runs are skipped over (main runs never cancel each other since
  the CI `concurrency` group keys main pushes by run id).
- **Changed:** the candidate must be `ahead` (or `diverged`) of the rolling
  `nightly` tag per the compare API. `publish` moves that tag to what it
  shipped, and a failed build leaves it alone, so the next night retries.
- **Escape hatch:** `workflow_dispatch` with `force: true` builds main's HEAD
  and skips both checks.

Needed `actions: read` added to the workflow's `permissions` (setting
`permissions` at all zeroes every unlisted scope).

Checked on 2026-09-21 by running the gate script locally against the live
repo: it reported "main is red (CI failure on cf686bc2d)" while the four newer
main commits were still queued; `force` picked HEAD; the compare call returned
`ahead` / `identical` / `behind` for a newer commit, the tag's own commit and an
older one. Not yet exercised by a scheduled run.
