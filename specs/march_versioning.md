# March Versioning — Make Versions Real & Visible

**Status:** Design (approved 2026-06-18)
**Scope:** Compiler/language versioning only. Stdlib-as-a-unit and the third-party
library ecosystem are explicitly out of scope (see [Out of Scope](#out-of-scope)).

## Motivation

March's version is currently a decorative constant. `0.1.0` is hand-copied into
six places — `dune-project`, the three generated `.opam` files, the `forge` CLI
(`forge/bin/main.ml:888`), and `bin/main.ml:1672` (whose `march --version` prints
a hardcoded `"march 0.1.0\n"` with a "keep in sync" comment). Meanwhile
`release.yml` derives the *real* release version from the pushed git tag
(`github.ref_name`), which never touches the in-tree `0.1.0`. So the in-tree
version drifts from what actually ships, and every dev build is indistinguishable.

This matters more than cosmetics because **forge already implements a complete,
rustup-style toolchain manager** (`forge toolchain install/use/pin/which`,
`.march-version` pins, `march = "~> X.Y"` constraint enforcement, `forge.lock`
`[toolchain]` drift detection — all built, see `specs/forge_version_manager.md`).
That subsystem is **dormant** because the supply side never moves the version off
`0.1.0` and never cuts releases with a moving, tag-matched number. Every constraint
trivially passes; `latest` is meaningless; drift never fires. This plan is the
*producer* side that makes the existing *consumer* side do something.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| What's versioned | Compiler + language, lockstep | Pre-1.0; one number is simplest |
| Version model | **Lockstep** — one number covers `march`, `forge`, `march-lsp` | They ship as one toolchain from one `dune-project` |
| Ambition | **Real & visible** — no formal compatibility policy yet | Appropriate pre-1.0; policy deferred |
| Mechanism | Generated `Version` module via a dune `(rule)` | One source of truth, embeds git hash, no new dependency |
| In-tree version meaning | The **next, in-development** version | Lets nightlies derive `X.Y.Z-nightly.YYYYMMDD`; matches Rust/Go |

## Design

### 1. Single source of truth

`dune-project`'s `(version …)` field is canonical. A dune `(rule)` generates
`lib/version/version.ml` at build time, exposing:

- `semver` — read from the `dune-project` version field
- `git_hash` — `git rev-parse --short HEAD` (empty when git is absent)
- `build_date` — commit date, or build date
- `string` — composed display string (see §2)

The rule must **degrade gracefully** when git is unavailable (release tarballs,
vendored source): fall back to the bare `semver`. The three `.opam` files already
inherit the version via `generate_opam_files`, so they need no further handling.

Both consumers drop their hardcodes and read the generated module:
- `bin/main.ml:1672` → `Version.string`
- `forge/bin/main.ml:888` (`~version`) → `Version.string`

All six hand-synced copies collapse to one.

### 2. `--version` output

- `march --version` → `march 0.2.0-dev (a1b2c3d 2026-06-18)` for a dev/git build;
  `march 0.2.0` for a release build with no git context.
- `march --version --verbose` (and/or `-V`) → semver, git hash, build date, OCaml
  compiler version, and host/target triple.
- `forge --version` consumes the same `Version.string`, so `march` and `forge`
  always report the same number (lockstep, by construction).

### 3. CHANGELOG

Add `CHANGELOG.md` at the repo root in [Keep a Changelog](https://keepachangelog.com)
format, with an `## [Unreleased]` section at the top. The release ritual (§4)
finalizes that section under the new version number with the release date.
`release.yml`'s hand-written `body:` block is replaced by extracting the released
version's section from `CHANGELOG.md`, so release notes live in exactly one place.

### 4. Release ritual

`scripts/bump-version.sh X.Y.Z` performs a guarded release that mirrors the
*shape* of `forge release` (clean tree → build → test → finalize → tag):

1. Require a clean working tree.
2. Build (release) and run the full test suite; abort on failure.
3. Finalize `CHANGELOG.md`: rename `[Unreleased]` → `[X.Y.Z]` with today's date.
4. Set `dune-project` version to the release version `X.Y.Z`.
5. Commit and create the annotated tag `vX.Y.Z` (which `release.yml` already keys on).
6. Bump `dune-project` to the **next** in-development version (e.g. `X.Y.(Z+1)-dev`)
   and commit, so `main` always carries the next version.

**Not a forge subcommand.** `forge release` and `forge version` bump a forge
project's `forge.toml [package].version`. The compiler is *not* a forge project —
its version lives in `dune-project`. A forge subcommand bumping `dune-project`
would force forge to special-case its own build system. The script is the correct
layering: library authors run `forge release`; compiler releases run the script.
Same ritual shape, separate tools.

### 5. forge interaction & contracts

This plan feeds forge's already-built toolchain manager. Three producer↔consumer
contracts the implementation must honor:

1. **Tag = in-tree released version.** forge resolves `march = "~> 0.2"` and
   `.march-version` pins against GitHub release tags. If the released
   `dune-project` version and the pushed `vX.Y.Z` tag diverge, forge's resolver
   silently lies. A **CI guard** asserts the pushed tag matches the in-tree
   released version. This is a correctness contract *for forge*, not tidiness.
2. **Release asset shape.** `forge toolchain install` reads the GitHub Releases
   API and expects `march-X.Y.Z-<platform>.tar.gz`, a `march-X.Y.Z-checksums.txt`,
   and a moving `latest`. `release.yml` must keep producing exactly those.
3. **Nightly version derivation.** With `dune-project` holding the next in-dev
   version, the nightly workflow derives `X.Y.Z-nightly.YYYYMMDD` from it (matching
   `specs/forge_version_manager.md`), rather than the opaque `nightly-YYYYMMDD`
   tag alone.

## Prior Art

These conventions deliberately follow Rust and Go, and deliberately reject the
TypeScript model. They are not bikeshed-able preferences — they align March with
the most battle-tested toolchain-versioning camp, and they pre-stage a post-1.0
compatibility story.

| Dimension | **March (this plan)** | **Rust** | **Go** | **TypeScript (rejected)** |
|---|---|---|---|---|
| Version string | `march X.Y.Z (hash date)` | `rustc 1.75.0 (82e1608df 2023-12-21)` — identical shape | `go1.21.5 darwin/arm64` | `Version 5.3.3` |
| Source of truth | `dune-project` (manifest) | repo version + `RELEASES.md` | `VERSION` file | `package.json` |
| Compiler ↔ pkg-mgr | Lockstep, bundled (march+forge+lsp) | Lockstep (rustc+cargo) | One binary | Compiler is just an npm dep |
| Toolchain manager | Built into forge (`forge toolchain`) | rustup | Built into `go` | None — npm pins it |
| Pin file | `.march-version` | `rust-toolchain.toml` | `go` line in `go.mod` | `package.json` devDep |
| Manifest constraint | `march = "~> X.Y"` | `rust-version` (MSRV) | `go 1.21` directive | (pinned version) |
| Nightly scheme | `nightly-YYYYMMDD` | `nightly-YYYY-MM-DD` | `devel go1.22-<hash>` | n/a |
| Main = next-dev version | Yes | Yes | Yes (`devel`) | Often `-dev`/`-beta` |
| Breaking-change story | Deferred (pre-1.0) | Editions (opt-in) | Compat promise + `go` directive | "Marketing semver" — minors break |

**Key takeaways:**

- The `X.Y.Z (git-hash date)` string, dedicated pin file, `~>` MSRV-style
  constraint, date-stamped nightlies, and main-carries-next-dev convention all
  match **rustc** feature-for-feature. March converges on a proven model.
- forge's built-in toolchain manager puts March in the Rust/Go camp — already more
  capable than Elixir (asdf/mise) or TypeScript (npm), but dormant until this plan
  makes versions move.
- **TypeScript is the anti-pattern.** Its numbers look like semver but carry no
  compat meaning (4.9 → 5.0 is just "next release"; minors break type-checking).
  Because March wires the compiler version into forge's *constraint resolver*,
  TS-style meaningless numbers would make `march = "~> 0.2"` constraints lie.
- The deferred compatibility policy is exactly what Rust/Go invest in *after* 1.0.
  The "decouple later via editions" path (opt-in `edition = "2026"` in forge.toml)
  is Rust's model; this plan's producer-side decisions (single source of truth,
  moving version) are its prerequisites.

## Out of Scope

Deferred deliberately, consistent with the "real & visible" ambition:

- A formal semver/compatibility policy, deprecation process, or road-to-1.0 doc.
- Language **editions** (the post-1.0 decoupling path; this plan only pre-stages it).
- Stdlib-as-a-unit versioning.
- All open forge **registry** items from `specs/forge_version_manager.md`: network
  publish + registry server (#7), `forge yank` (#8), `forge outdated` (#9),
  workspaces (#11), vendoring (#12), full AST-based semver checking (#14).

## Acceptance Criteria

1. `0.1.0` appears in exactly one place (`dune-project`); no other hardcoded copies.
2. `march --version` and `forge --version` report the same number, sourced from the
   generated module, with git hash + date on dev builds and bare semver on release
   builds. `march --version --verbose` prints the extended fields.
3. `CHANGELOG.md` exists; `release.yml` sources release notes from it.
4. `scripts/bump-version.sh X.Y.Z` runs the guarded ritual and leaves `main` on the
   next `-dev` version.
5. A CI guard fails the build when a pushed `vX.Y.Z` tag does not match the in-tree
   released version.
6. `release.yml` still emits `march-X.Y.Z-<platform>.tar.gz` + checksums + `latest`
   exactly as `forge toolchain install` consumes them.
7. `specs/todos.md` and `specs/progress.md` updated per `CLAUDE.md`.
