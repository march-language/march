# Zed extension: stale grammar pin left `pfn`/`needs` unhighlighted

**Filed / fixed:** 2026-08-12

## Symptom

`pfn` (and `needs` capability declarations) rendered as plain unhighlighted
text in a Zed editor running the March extension, even though the compiler
(`lib/lexer/lexer.mll`) has recognized `PFN` as a distinct token all along.

## Root cause

Not a current grammar bug. `tree-sitter-march/grammar.js` and its
`highlights.scm` already support `pfn` and `needs` — added in commit
`fc8f94ae8` (PR #175, 2026-08-04). The bug was in `zed-march/extension.toml`:
`[grammars.march].rev` was still pinned to `ad60a650` (2026-03-26), a commit
four and a half months older than the grammar fix. Zed builds the grammar
from that pinned commit, not from whatever `tree-sitter-march/` currently
contains on disk, so any editor that built the extension after 2026-03-26
but is still running that build never picked up the fix.

## Fix

Bumped `rev` in `zed-march/extension.toml` to current `main`
(`281261a5f46c5bcbcfe12d0526b2b888e286777a`). Users with the dev extension
installed need to reload/reinstall it in Zed to rebuild against the new pin.

## Note for future sessions

`tree-sitter-march/` exists in two places in this repo tree:
`/tree-sitter-march/` (canonical, tracked) and
`zed-march/grammars/march/` (a gitignored local clone Zed's build step
creates at the pinned `rev`, purely a build cache — never edit it directly).
When debugging grammar/highlighting issues, confirm `git rev-parse
--show-toplevel` matches the intended worktree before editing — an earlier
pass in this same investigation edited `tree-sitter-march/` via an absolute
path that resolved to a *different* checkout of this repo
(`/Users/80197052/code/march`, a separate non-worktree clone on an unrelated
branch) and only discovered the mistake after `git blame` showed the "fix"
already existed on `main` since 2026-08-04.
