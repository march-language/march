# Release mechanism: what exists, and the scripts that now drive it

**Filed 2026-09-10**, while planning the 0.4.0 release; implemented the same
day. This is not a new design — [`specs/march_versioning.md`](march_versioning.md)
decided the shape and [`specs/march_versioning_plan.md`](march_versioning_plan.md)
laid out nine tasks. Tasks 1–4 landed; **tasks 5–8 did not**, so 0.2.0 and 0.3.0
were both cut by hand.

This file records the measured state, the one decision that was revisited, and
what the scripts do.

## What already worked

`dune-project`'s `(version …)` is a genuine single source of truth:

```
dune-project (version 0.3.0)
  └─ generate_opam_files true  →  march.opam / forge.opam / march-lsp.opam
       └─ %{version:march}     →  bin/version.ml, forge/bin/version.ml
            └─ march --version →  "march 0.3.0"     [verified against the binary]
```

`release.yml` triggers on `v*` tags, calls `build.yml`, publishes
`march-<tag>-<platform>.tar.gz` plus `march-<tag>-checksums.txt`, and
force-moves a `latest` tag. `install.sh` and `forge toolchain` consume that
shape. Unchanged.

## The defect this fixes

The in-tree version stayed at `0.3.0` after release, and `nightly.yml` derived
its version from that field, so **every nightly published between 2026-08-23 and
2026-09-10 was labelled `0.3.0-nightly.YYYYMMDD`** — a version that sorts *below*
the release it postdates, while containing 200+ commits of later work.

**Severity, measured rather than assumed.** This is an ordering and honesty
problem, not a resolution failure:

- `install.sh` and `forge toolchain install latest` resolve through the GitHub
  Releases API's stable/pre-release classification, not by sorting versions.
- `forge.toml`'s `march = "~> X.Y"` never selects a nightly under any labelling.
  `resolver_constraint.ml` states it outright: *"a non-pre-release constraint
  does NOT select pre-release versions. `~> 1.0` does not select `1.1.0-beta`."*
  Every nightly is a pre-release by construction.
- `Toolchain.check_constraint` receives the resolved *tag* (`nightly-YYYYMMDD`),
  which is not semver, and returns `Ok ()` unevaluated.

So nothing was resolving wrongly. What was wrong is that the published version
string lied about where the build sits in history.

## The decision that was revisited: no `-dev` suffix

`march_versioning.md` § Decisions chose *"in-tree version = the next, in-development
version"*, i.e. `0.4.1-dev` on `main`. **That is superseded.** The in-tree version
is the **last released version**, and the nightly script patch-increments it:

```
dune-project 0.3.0  →  scripts/nightly-version.sh  →  0.3.1-nightly.20260910
```

That sorts above `0.3.0` and below any plausible next release, which is the only
claim a nightly needs to make. Verified against forge's own comparator, which is
semver-correct (`resolver_version.ml`: *"absent pre > present pre"*, and
`test_resolver.ml` asserts `1.0.0-alpha < 1.0.0`). Note `sort -V` disagrees — it
is not semver-aware and orders the pre-release *after* the release; do not use it
to check this.

Two arguments originally made for `-dev` did not survive checking, and are
recorded so they are not re-made:

- *"Without `-dev`, a `~> 0.4` pin will reject every nightly once 0.4.0 ships."*
  False — `~>` rejects every nightly regardless, by design (above).
- *"Without `-dev`, the tag guard degenerates, because every commit matches the
  last tag."* False — the guard compares the **tag** to the in-tree version.
  Tagging `v0.4.0` on a tree still reading `0.3.0` mismatches and fails, which is
  exactly the forgotten-bump case.

What `-dev` would genuinely have bought is *declaring intent* — a tree at
`0.4.0-dev` says "heading to 0.4.0", where patch-incrementing from `0.3.0` says
"heading to 0.3.1" even when the next release is 0.4.0. Since nightlies are
excluded from constraint resolution either way, that is a cosmetic difference in
a string, not worth carrying a suffix on every dev build and a strip step in the
nightly path.

## What was built

| script | does |
|---|---|
| `scripts/version.sh` | Reads `(version …)` from `dune-project`. Sourced by the rest, so the extraction exists once instead of inline in a workflow. |
| `scripts/nightly-version.sh` | Prints `X.Y.(Z+1)-nightly.YYYYMMDD`. Rejects an in-tree version carrying a pre-release suffix. |
| `scripts/check-version-tag.sh` | `vX.Y.Z` must equal the in-tree version. Wired as the **first** step of `release.yml`'s publish job. |
| `scripts/changelog-section.sh` | Prints one version's CHANGELOG section; `--max-bytes N` truncates at a line boundary with a pointer to the full log. |
| `scripts/bump-version.sh` | The ritual: preconditions → build → tests → finalize CHANGELOG → set version → verify the built binary agrees → commit → tag. Prints push commands; does not push. |

### Workflow wiring

- `release.yml`: tag guard runs **before any artifact is downloaded**, so a
  mismatched tag fails before anything is published. The release body is now the
  version's CHANGELOG section plus the install blurb, via `body_path`.
- `nightly.yml`: the inline `grep`/`sed` is replaced by `scripts/nightly-version.sh`.

### The release-body size cap, found while building this

A GitHub release body is capped at **125,000 characters**. The 0.3.0 CHANGELOG
section is **321,778 bytes** — 2.5× over. An untruncated body would be rejected
by the API *at publish time, after the artifacts had been built and uploaded*.
Hence `--max-bytes 100000`, which leaves room for the install blurb; the measured
total for a 0.3.0-shaped release is 100,289 bytes.

The current `[Unreleased]` section is already 65KB and grows every merge, so this
cap is load-bearing for 0.4.0, not a future concern.

## What stays manual

`bump-version.sh` prints these rather than editing them, because no script
should own them:

- `docs/upgrading-to-0-N-0.md` — the migration guide, the part adopters need.
- `docs/_layouts/landing.html:466` — the hero badge. Missed at 0.2.0, caught
  late at 0.3.0.
- `docs/tooling.md` — four examples pin a concrete version.

Also: `docs/upgrading-to-0-3-0.md` is linked from nowhere on the site. The 0.4.0
guide should be linked from the docs nav, and the 0.3.0 one retroactively.

## Traps hit while building this, kept because they recur

- **`set -o pipefail` plus a pipe into an early-exiting `awk` aborts the script
  silently.** The truncation path piped a section into an `awk` that `exit`s once
  its budget is spent; `awk` closing the pipe SIGPIPEs the upstream `printf`, and
  under `pipefail` + `set -e` the script died *before emitting the trailer*. The
  output was still under budget, so a size-only check passed while the truncation
  notice was missing. Fixed with a here-string. **Assert the content, not just
  the size.**
- **Prove each guard goes RED.** Three release-oracle scripts in this repo
  shipped broken because a `${1:?usage … {a|b} …}` expansion ends at the *first*
  `}`, mangling the mode argument — and one was reviewed and certified in that
  state. `check-version-tag.sh` deliberately avoids that form. Every guard here
  was proven red and green before landing.
- **`scripts/run-tests.sh` is not the release gate.** It is alcotest-only: no
  `forge/test/`, no `@types-check`/`@grammar-check`. A fully green `run-tests.sh`
  has already coexisted with a red `main` (`db44fbb3`). `bump-version.sh` runs
  all four, and `--force` on the two aliases is load-bearing — without it they
  exit 0 having done nothing.
- **`sort -V` is not semver.** See above.
- This repo's shell is **zsh**; `${PIPESTATUS[0]}` is bash. Checking an exit code
  through a pipe silently reports nothing.
