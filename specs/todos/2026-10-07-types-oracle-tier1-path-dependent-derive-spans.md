# types-oracle tier 1 is path-dependent for fixtures with derived decls

**Logged:** 2026-10-07, while running `scripts/types-oracle.sh` for the D5
PR (provided-side type-error origin) against a baseline recorded in a second
worktree.

## Symptom

`TIER1 CORE-AST CHANGED — 54 fixtures` between two compilers that are
byte-identical in behaviour, every one of them a fixture with a `derive` (or
another synthesised decl). The JSON differs only in the synthesised spans'
columns: `"file":"<none>","start_col":672800795` on one side,
`973903399` on the other.

## Cause

`Desugar_derive.decl_salt` keys a generated decl's synthetic spans on
`Hashtbl.hash (salt_scope, decl)`, and the decl contains its derive-site
span, whose `file` is the source path **as passed on the command line**.
`scripts/types-oracle.sh` runs `--emit-core-ast "$f"` with `$f` absolute
(`$ROOT/specs/lang/...`), so the hash differs per worktree, and the script's
path normalisation (`sed "s|$ROOT/||g"`) runs on the output, after the hash
is already in it. Two runs from the same root agree; two worktrees never do.

Verified: re-running the 54 fixtures with paths relative to each root gives
identical tier-1 hashes under both compilers.

## Fix

In `scripts/types-oracle.sh`, run each fixture from `$ROOT` with a
root-relative path (`cd "$ROOT" && "$EXE" --emit-core-ast "${f#$ROOT/}"`),
for both tiers, so the derive salt sees the same file name on both sides.
Alternatively salt on the span's *position* only and not its file; the
file is already pinned to `"<none>"` in the synthesised span, so the key
loses nothing. Add a self-test that records a baseline in a copy of the
tree and checks against the original.
