# The committed Pagefind index conflicts between any two PRs that regenerate it

Filed 2026-08-03, hit while merging #164.

## Problem

`docs/pagefind/` is committed, and `scripts/gen-docs-search-index.sh` documents
why its contents cannot be byte-compared:

> Pagefind's output is deliberately NOT reproducible (filenames and the entry
> hash embed a per-run content hash — verified: two consecutive runs over
> identical input produce different `en_*.pf_filter` names)

That is fine for the staleness check, which hashes *sources* rather than output.
It is not fine for merging. Two branches that each regenerate the index produce
disjoint sets of hash-named files, so git sees renames-vs-deletes plus a
conflict in `pagefind-entry.json` — **even when neither branch changed a single
docs source**.

Observed: #160 regenerated the index without touching any page (both sides
carried the identical source digest `d705094287c1…`), and #164 still had to
resolve a three-way conflict across `filter/en_*.pf_filter`,
`pagefind.en_*.pf_meta`, and `pagefind-entry.json`.

The resolution is always the same and always mechanical — discard both indexes,
regenerate from merged sources — but it is not obvious to someone meeting it for
the first time, and hand-merging hash-named binaries is worse than useless.

## Options

1. **Stop committing the index; build it in CI.** The GitHub Pages workflow
   already builds the site, so it could run Pagefind there and publish the
   output as part of the deploy. Removes the class of conflict entirely and
   deletes ~200 tracked files. Cost: the index no longer exists in a local
   `docs/` preview unless the developer runs the script.
2. **Keep it committed, add a merge driver.** A `.gitattributes` entry marking
   `docs/pagefind/**` with a custom merge driver that resolves by regenerating.
   Keeps local previews working; costs a driver everyone must have configured,
   which fails open for anyone who does not.
3. **Document the resolution** in the script header and CONTRIBUTING: on any
   conflict under `docs/pagefind/`, run
   `git checkout origin/main -- docs/pagefind && scripts/gen-docs-search-index.sh`.
   Cheapest, does not remove the friction.

Option 1 looks right — the index is a build artifact, and the only reason to
track it is that Pages serves straight from the repo. Worth checking whether the
Pages workflow can run Pagefind before committing to it.

## Note

This is friction, not breakage: the staleness gate still works correctly, and it
correctly caught a real problem in #162. The complaint is only that the artifact
it guards is unmergeable in parallel.
