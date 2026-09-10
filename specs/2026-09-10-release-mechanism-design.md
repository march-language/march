# Release mechanism: what exists, what is missing, what to build

**Filed 2026-09-10**, while planning the 0.4.0 release. This is not a new
design — [`specs/march_versioning.md`](march_versioning.md) already decided the
shape, and [`specs/march_versioning_plan.md`](march_versioning_plan.md) laid out
nine tasks. Tasks 1–4 landed (in a simpler form than written). **Tasks 5–8
never did**, so 0.2.0 and 0.3.0 were both cut by hand, and one consequence is
live in every nightly published since 2026-08-23.

This file records the measured current state and specifies exactly what to
build, so the next release is a script rather than a remembered ritual.

## Current state, measured on `e45abff0`

### What works

`dune-project`'s `(version …)` is a genuine single source of truth:

```
dune-project (version 0.3.0)
  └─ generate_opam_files true  →  march.opam / forge.opam / march-lsp.opam  version: "0.3.0"
       └─ %{version:march}     →  bin/version.ml, forge/bin/version.ml  (dune rule)
            └─ march --version →  "march 0.3.0"     [verified against the built binary]
```

`release.yml` triggers on `v*` tags, calls `build.yml`, publishes
`march-<tag>-<platform>.tar.gz` plus `march-<tag>-checksums.txt`, and
force-moves a `latest` tag. `install.sh` and `forge toolchain` both consume
that shape. None of this needs changing.

### What is missing

| Plan task | Artifact | Status |
|---|---|---|
| 5 | `scripts/changelog-section.sh` | **absent** |
| 6 | `scripts/check-version-tag.sh` + CI wiring | **absent** |
| 7 | `scripts/nightly-version.sh` | **absent** — `nightly.yml` inlines a `grep`/`sed` |
| 8 | `scripts/bump-version.sh` | **absent** |

`scripts/` contains no version, release, changelog, bump or tag script of any
kind. There is no CI guard that a pushed `vX.Y.Z` tag matches the in-tree
version. `release.yml`'s GitHub Release body is a fixed install blurb; it never
quotes the version's CHANGELOG section.

### The live defect

`specs/march_versioning.md` § Decisions chose: *in-tree version means the
**next, in-development** version*. That decision never landed. After the 0.3.0
release, `dune-project` stayed at `0.3.0` rather than moving to `0.4.0-dev`.

`nightly.yml` derives its version from that field, so **every nightly published
since 2026-08-23 is labelled `0.3.0-nightly.YYYYMMDD`** — a version that
semver-sorts *below* the released `0.3.0`, while containing 200+ commits of
work that postdates it.

**Severity, measured rather than assumed.** Neither `install.sh` nor
`forge toolchain install latest` is broken by this: both resolve through the
GitHub Releases API's stable/pre-release classification, not by sorting version
strings. The real bite is `forge.toml`'s `march = "~> X.Y"` constraint, which
*is* evaluated as semver (`Toolchain.check_constraint`). `Toolchain` lets a
non-semver tag through unevaluated — but `0.3.0-nightly.20260910` **is**
parseable semver, so it is evaluated, and it fails `~> 0.4`. Once 0.4.0 ships,
a project pinning `~> 0.4` will reject every nightly until this is fixed.

## Decision to confirm before building

The `-dev` convention is the one open question, because it is the thing that
was decided and then not done. Two coherent options:

**A. In-tree version is the next in-development version (`0.4.1-dev`).**
What `march_versioning.md` chose; matches Rust and Go. `main` always says what
it is becoming, nightlies derive correctly, and the tag guard is meaningful
because `-dev` can never match a release tag.
*Cost:* `march --version` on a dev build reads `0.4.1-dev`, and the nightly
derivation must strip the suffix (below).

**B. In-tree version is the last released version (status quo).**
`march --version` on `main` matches the last release.
*Cost:* nightlies are mislabelled by construction, and the tag guard degenerates
— every commit matches the last tag, so it cannot catch a forgotten bump.

**Recommend A**, because B has no mechanism that catches the exact mistake made
after 0.3.0. If A is adopted, say so in `march_versioning.md` § Decisions rather
than leaving the row unchanged for a third release.

### Nightly derivation under A

`0.4.1-dev` must not be pasted into a nightly string directly:
`0.4.1-dev-nightly.20260910` parses as semver but sorts by the identifier
`dev-nightly`, which is not what anyone means. Strip the suffix first:

```
BASE=$(sed -n 's/^(version \(.*\))$/\1/p' dune-project)   # 0.4.1-dev
BASE=${BASE%-dev}                                          # 0.4.1
echo "${BASE}-nightly.$(date -u +%Y%m%d)"                  # 0.4.1-nightly.20260910
```

That sorts above `0.4.0` and below `0.4.1`, which is the correct claim for a
build heading toward 0.4.1.

## What to build

### 1. `scripts/version.sh` (shared helper)

One reader for the in-tree version, sourced by everything below, so the
`grep`/`sed` currently inlined in `nightly.yml` exists once. Exposes the raw
value and the `-dev`-stripped base.

### 2. `scripts/check-version-tag.sh` — the guard that matters most

Given a tag `vX.Y.Z`, assert the in-tree version is exactly `X.Y.Z` (no `-dev`).
Wire into `release.yml` as the **first** step of the `publish` job, before any
artifact is uploaded, so a mismatched tag fails loudly instead of shipping a
binary whose `--version` disagrees with its own release page.

This is the producer↔consumer contract `march_versioning.md` § 5.1 calls out:
forge resolves `march = "~> X.Y"` and `.march-version` against release *tags*,
so a tag that disagrees with the in-tree version makes forge's resolver silently
lie.

### 3. `scripts/changelog-section.sh X.Y.Z`

Print the `## [X.Y.Z]` section of `CHANGELOG.md` up to the next `## [`. Used by
`release.yml` to build the release body: the current fixed install blurb should
become the changelog section *plus* that blurb. Must exit non-zero on a missing
section, so a release cannot publish empty notes.

### 4. `scripts/bump-version.sh X.Y.Z` — the ritual

Per `march_versioning.md` § 4, in order, aborting on any failure:

1. Require a clean tree, and require being on `main` up to date with
   `origin/main` (fetch first — a stale `main` ref is a known trap in this repo).
2. Build, and run the full suite. **Include the suites `scripts/run-tests.sh`
   does not cover** — it is alcotest-only, and misses `forge/test/`,
   `@types-check` and `@grammar-check`. A green `run-tests.sh` has already been
   demonstrated to coexist with a red `main` (`db44fbb3`). At minimum:
   `dune build @forge/test/runtest`, and `@types-check`/`@grammar-check` **with
   `--force`** (without it they exit 0 having done nothing).
3. Finalize `CHANGELOG.md`: `[Unreleased]` → `[X.Y.Z] - <today>`, and open a
   fresh empty `[Unreleased]` above it.
4. Set `dune-project` to `X.Y.Z`.
5. Commit, then create annotated tag `vX.Y.Z`.
6. Set `dune-project` to the next in-development version and commit, so `main`
   carries `-dev` again.
7. Print the push commands rather than pushing. Pushing a tag starts a
   publish; that stays a human decision.

### 5. `nightly.yml`

Replace the inline extraction with `scripts/nightly-version.sh` (or
`version.sh --nightly`), including the `-dev` strip.

## What stays manual, and should be written down as such

The 0.3.0 release commit (`3206b316`) also touched things no script should own:

- `docs/upgrading-to-0-N-0.md` — the migration guide. This is the part that
  actually matters to adopters and cannot be generated.
- `docs/_layouts/landing.html` — the hero badge (`Early Access · vX.Y.Z`). Was
  missed at 0.2.0 and caught late at 0.3.0.
- `docs/tooling.md` — four example invocations pin a concrete version.

`bump-version.sh` should **print a reminder listing these**, with the badge line
number, rather than editing them. Also note that `docs/upgrading-to-0-3-0.md` is
linked from nowhere on the site; whatever guide 0.4.0 ships should be linked
from the docs nav, and the 0.3.0 one linked retroactively.

## Acceptance

- `scripts/check-version-tag.sh v0.4.0` fails on a tree at `0.4.1-dev` and
  passes on a tree at `0.4.0` — proven both ways, not just the passing one.
- `scripts/changelog-section.sh 0.4.0` prints exactly that section, and exits
  non-zero for a version with no section.
- A nightly built from a `0.4.1-dev` tree is labelled `0.4.1-nightly.YYYYMMDD`,
  and `Toolchain.check_constraint` accepts it for `march = "~> 0.4"`. This is
  the regression that motivated the work; assert it directly rather than
  inferring it from the string.
- `bump-version.sh` refuses on a dirty tree, on a non-`main` branch, on a `main`
  behind `origin/main`, and on any failing suite — each proven with a
  deliberately broken input.

## Traps specific to this work

- **Prove each guard goes RED.** Three release-oracle scripts in this repo
  shipped broken because a `${1:?usage … {a|b} …}` bash expansion ends at the
  *first* `}`, mangling the mode argument; one was reviewed and certified while
  in that state. A guard that has only ever been seen to pass is not a guard.
- **`scripts/run-tests.sh` is not the release gate.** See step 2 above.
- **`gh pr merge --auto` merges immediately** when the repo has auto-merge off.
  Read the run's conclusion and assert the green sha equals the PR head before
  merging, and merge without `--auto`.
- **Verify the CHANGELOG bullet union after any merge** during release prep — a
  merge has previously dropped four entries with no conflict.
- Changing the version invalidates the CAS compiler identity, so the first build
  after a bump is cold. Expected, not a fault.
