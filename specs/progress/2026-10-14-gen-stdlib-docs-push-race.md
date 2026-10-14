# gen-stdlib-docs: survive the push race with sync-docs-search-index

**Landed:** 2026-10-14

## Symptom

`.github/workflows/gen-stdlib-docs.yml` failed on 9 of its 10 runs on main from
2026-10-09 to 2026-10-14 (the latest three: a5e1f7a24, 39d6d9842, 8b544115f). Every one
failed in "Commit regenerated docs" with `! [rejected] main -> main (fetch first)`.
The regenerated stdlib API pages (`docs/docs/stdlib/`) never reached main; the last bot
commit of them before this fix was b4075cadc (2026-10-13).

## Cause

A stdlib merge also touches `docs/`, so the same push starts both gen-stdlib-docs
(about 10 minutes: compiler build, `forge doc`, Jekyll, Pagefind) and
`sync-docs-search-index.yml` (about 1 to 6 minutes). The faster sync bot pushes its
index commit first. gen-stdlib-docs then did a single `git push` from the trigger
commit and was rejected. Any ordinary merge landing in those 10 minutes had the same
effect.

## Fix

The commit step is now a 5-attempt loop. On a rejected push it fetches, runs
`git reset --hard origin/main`, puts back the pages this run generated (saved to
`$RUNNER_TEMP` after Check D), and regenerates `docs/pagefind/` over the new tree. If
`stdlib/**`, `scripts/gen-stdlib-docs.sh` or the workflow changed on main since the
trigger, it exits 0 instead: a newer run is queued in the `gen-stdlib-docs`
concurrency group and will publish the right pages. The commit guard is "pages
changed, or `gen-docs-search-index.sh --check` fails", after staging the pages (the
digest covers tracked files only). The old guard was `git status docs/pagefind`, which
is always dirty after a regeneration. The standalone "Regenerate docs search index"
step moved into the loop.

## Alternatives rejected

- **`git pull --rebase` retry** (as in some docs-free bots): `docs/pagefind/` file
  names are content hashes and are not reproducible, so both bots' indexes conflict.
- **One concurrency group shared by both workflows**: a group keeps one pending run
  and cancels the older pending one when a newer one arrives. A docs push queued
  behind a running stdlib job could then drop a pending stdlib regeneration, or the
  reverse.
- **Leave the index to sync-docs-search-index**: a push made with `GITHUB_TOKEN`
  starts no `on: push` workflow. The run history shows no workflow run on any
  `github-actions[bot]` docs commit, so sync-docs would never fire on the stdlib
  bot's commit. (The same fact disproved the comments in both workflows saying the
  bot commit triggers `deploy-pages.yml`. Those comments are corrected. The live site
  is GitHub's legacy Pages build, `pages-build-deployment`, which does run on bot
  pushes.)

## Verification

The loop was simulated against a local bare remote with a stand-in index script
(digest over `git ls-files`, randomly named index files) in three cases:
(A) the sync bot and a docs merge landed first, so the first push is rejected and
the second attempt pushes the pages plus a valid index on top of both;
(B) stdlib changed upstream, so the step exits 0 with a notice;
(C) nothing changed, so nothing is committed. `actionlint` is clean apart from the
existing `eval $(opam env)` SC2046 warning.
