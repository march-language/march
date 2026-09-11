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

---

## Investigated 2026-09-08 — NOT implemented; both offered options are refuted

Picked up as a "mechanical" item (implement option 1 or option 2). It is not
one: option 1 breaks production, and option 2 does not fire in the case this
file reports. Recording the evidence so the next person does not re-derive it.

### Option 1 (stop committing; build in CI) would break march-lang.org

The "Options" section above says option 1 "looks right" and asks whether the
Pages workflow can run Pagefind. It can — `deploy-pages.yml` already does, at
the `Build search index (Pagefind)` step. **That does not help, because that
workflow does not serve march-lang.org.** It publishes a built site to a
*different* repo, `march-language/march-language.github.io`.

`scripts/gen-docs-search-index.sh`'s own header — written after this todo was
filed — states it directly:

> march-lang.org is NOT served by .github/workflows/deploy-pages.yml. That
> workflow publishes a fully-built site to the march-language.github.io repo,
> but the production domain is served by *this* repo's own GitHub Pages,
> configured as: repo march-language/march, cname march-lang.org, source
> {branch: main, path: /docs}

and `docs/CNAME` contains `march-lang.org`, confirming it. GitHub's legacy
Jekyll over `docs/` has no post-build hook, so an index can only reach
production by being committed. Deleting `docs/pagefind/` would silently kill
⌘K search on the live site. **Option 1 is off the table until the Pages source
itself is changed**, which is a separate decision about how the site is served.

(Two other headers disagree with each other about this. `gen-stdlib-docs.sh`'s
header claims `deploy-pages.yml` serves march-lang.org — `gen-docs-search-index.sh`
flags that as incorrect — and `sync-docs-search-index.yml`'s header has it
right. Worth reconciling.)

### Option 2 (a merge driver) does not fire where the conflict happens

Measured in a scratch repo (git 2.50.1), reproducing this file's exact scenario
— two branches that each regenerate the index, adding differently hash-named
files and both editing `pagefind-entry.json`:

| setup | result |
| --- | --- |
| no `.gitattributes` (control) | `CONFLICT (content) in pagefind-entry.json` |
| `docs/pagefind/** merge=ours` | **still conflicts** — the built-in `ours` name alone did not resolve it |
| `merge=pagefind`, driver **not** configured | **still conflicts** (this is the fail-open the Options section predicts) |
| `merge=pagefind`, driver configured locally | clean merge, exit 0 |

So a driver works only for contributors who have run the `git config` — and,
decisively, **not for GitHub's own merge**. This repo merges via the GitHub PR
button (every recent commit is a `Merge pull request #NNN`), and GitHub's
server-side merge does not read a local `merge.<driver>.driver` config. A
merge driver would therefore leave the reported situation — #160 and #164 —
exactly as it is. This should be confirmed against GitHub's behaviour directly
before it is dismissed for good, but it is the reason not to ship it blind.

### What has changed since filing, and what is actually left

`sync-docs-search-index.yml` landed 2026-08-16 (#294), after this was filed. It
regenerates and pushes the index on every push to main that touches docs, with
a `--check` fast path and a rebase-retry loop. That closes the **staleness**
half of this problem — including the merge-interaction staleness no PR check
could catch.

What remains is only the **conflict** half: two PRs that each regenerate still
collide at merge time. Given the above, the plausible resolutions are now:

1. Change the Pages source so the index need not be committed (makes option 1
   available, but is a decision about site serving, not about this file).
2. Stop asking contributors to regenerate at all: drop the index from PRs by
   convention and let `sync-docs-search-index.yml` be the only writer, so two
   PRs rarely touch `docs/pagefind/` in the first place. This is the cheapest
   real fix and needs no new machinery, but it means relaxing doc-lint's
   `--check` from a PR-blocking gate to something advisory — a policy call.
3. Option 3 from the original list (document the resolution), which remains
   valid and cheap and is the only one with no downside.

**Left open deliberately.** Every remaining path is a policy or
site-architecture decision, not a mechanical edit.

> **Design spec (2026-09-11):** `specs/2026-09-11-ci-tooling-fixes-design.md` — root cause re-verified against the tree, chosen fix, test plan with a RED control, effort and risk.
