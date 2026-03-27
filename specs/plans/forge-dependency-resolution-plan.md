# Forge — Dependency Resolution and Versioning System Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Design and implement a production-grade dependency resolution system for Forge — covering version constraints, a PubGrub-based solver, lockfile semantics, CAS content verification, fork handling, and API-surface-enforced semver — so that March packages can be published, resolved, and built reproducibly.

**Architecture:** A new `lib/resolver/` OCaml library contains the PubGrub solver core, version constraint parsing, lockfile serialization, and API surface diffing. Forge's existing CAS (`lib/cas/`) is extended with content-addressed package archiving. The `forge publish` command gains an API surface diffing step before upload.

**Tech Stack:** OCaml 5.3, TOML parsing (toml-of-sexp or ez_toml), BLAKE3 (existing CAS), Alcotest (tests), dune build system.

---

## Background

### 1.1 Why Dependency Resolution Is Hard

Dependency resolution is NP-complete in the general case (it reduces to 3-SAT when packages have disjoint version ranges). Most package managers paper over this with heuristics (npm's tree duplication, Go's MVS) or slow backtracking SAT solvers (older Bundler, pip). The result is either subtly wrong (duplicate incompatible versions in the tree) or opaque (solver times out on large graphs with no explanation).

March deserves better. The error philosophy established in the Elm-style diagnostics plan applies to the package manager too: if the solver cannot find a solution, it must tell you *exactly why* in human terms — which package constraint is in conflict, which dependency introduced it, and what you need to change. This rules out SAT solvers (their refutation proofs are not human-readable) and plain backtracking (it gives up with no explanation).

### 1.2 Why PubGrub

PubGrub was invented by Natalie Weizenbaum for Dart's pub package manager (2018). It is now also used by Cargo (via `cargo-resolver` since 2022) and Poetry 2.0.

**The key insight:** PubGrub is a DPLL-style conflict-driven solver that constructs a *derivation tree* as it runs. When it finds a conflict, it can walk the derivation tree and produce a human-readable explanation chain: "Version A of X requires Y ≥ 2.0. Version B of Z requires Y < 2.0. Since you require both X A and Z B, there is no valid version of Y."

Comparison to alternatives:

| Approach | Human errors | Speed | Correct | Used by |
|----------|-------------|-------|---------|---------|
| Backtracking | No | Exponential worst case | Yes | Old Bundler, Pub <v2 |
| SAT (DPLL) | No (UNSAT proof) | Fast | Yes | Mantle, old Cargo |
| MVS (Minimum Version Selection) | N/A — no conflicts by design | O(n) | No — forces duplication | Go modules |
| PubGrub | **Yes — derivation tree** | Near-linear in practice | Yes | Dart pub, Cargo 2022, Poetry 2 |

**MVS rejected:** Go's Minimum Version Selection sidesteps conflicts by silently upgrading every package to the highest version any dependency requires. This is correct only if all packages are backwards-compatible, which semver cannot guarantee. It also means a `go get` can silently pull in a newer major version of a transitive dep. For March, where the type system can express breaking changes, we want strict conflict detection with good error messages — not silent upgrades.

**PubGrub reference:** Natalie Weizenbaum, "PubGrub: Next-Generation Version Solving" (2018). https://nex3.medium.com/pubgrub-2fb6470504f

---

## 2. Version Constraints

### 2.1 Constraint Syntax

```toml
[deps]
json    = { registry = "forge", version = "~> 1.2"    }  # pessimistic (compatible)
http    = { registry = "forge", version = ">= 2.0"    }  # lower bound
logger  = { registry = "forge", version = "< 3.0"     }  # upper bound
core    = { registry = "forge", version = ">= 1.5, < 2.0" }  # range (comma-separated)
utils   = { registry = "forge", version = "1.4.2"     }  # exact pin
```

Constraints are combined with AND semantics when multiple are present (comma-separated). No OR constraints at the manifest level — if you need "either X or Y", you are solving the wrong problem (that's what [patch] is for).

### 2.2 Pessimistic Operator `~>`

Borrowed from Elixir's Hex and Ruby's Bundler, `~>` means "compatible with at the patch level for three-component versions, at the minor level for two-component versions":

| Constraint | Equivalent range |
|------------|-----------------|
| `~> 1.2.3` | `>= 1.2.3, < 1.3.0` |
| `~> 1.2`   | `>= 1.2.0, < 2.0.0` |
| `~> 1`     | `>= 1.0.0, < 2.0.0` |

This is the preferred form for most deps — it expresses "I want compatible updates but not breaking changes."

### 2.3 Version Ordering

Versions are ordered by the standard semver rules:

```
1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-beta < 1.0.0 < 1.0.1 < 1.1.0 < 2.0.0
```

Pre-release versions (`1.0.0-alpha`, `1.0.0-rc.1`) are only selected if the constraint *explicitly* includes a pre-release identifier. `~> 1.0` does not select `1.1.0-beta`. This matches Cargo and Hex behavior.

### 2.4 Version Representation (OCaml)

```ocaml
(* lib/resolver/version.ml *)
type pre = string list  (* ["alpha"; "1"] for -alpha.1 *)

type t = {
  major : int;
  minor : int;
  patch : int;
  pre   : pre;
  build : string option;  (* ignored for ordering *)
}

type constraint_ =
  | Gte of t
  | Lte of t
  | Gt  of t
  | Lt  of t
  | Eq  of t
  | And of constraint_ * constraint_

val compare : t -> t -> int
val satisfies : t -> constraint_ -> bool
val parse : string -> (t, string) result
val parse_constraint : string -> (constraint_, string) result
```

---

## 3. Dependency Sources

### 3.1 Registry Dependencies

```toml
[deps]
json = { registry = "forge", version = "~> 1.0" }
```

Registry is the primary source. The registry maps package names to a list of versions, each with a set of constraints on its own deps. The solver operates entirely on the registry's version graph.

The `registry` key defaults to `"forge"` (the official March registry). Future work could add alternative registries via a `[registries]` table, but that is out of scope here.

### 3.2 Git Dependencies

Three sub-forms, with different resolution semantics:

#### Tag (semver-resolved)

```toml
depot = { git = "https://github.com/user/depot.git", tag = "v0.2.1" }
```

- The tag is parsed as a semver version (`v0.2.1` → `0.2.1`).
- Participates in the solver as a "virtual package" at that version.
- Pinned at the tag's commit SHA in `forge.lock`.
- `forge update depot` does nothing (tag is immutable; user must change the tag string).

If the tag cannot be parsed as semver (e.g., `release-jan-2025`), Forge rejects it with an error and asks the user to use `rev` instead.

#### Branch (floating)

```toml
bastion = { git = "https://github.com/user/bastion.git", branch = "main" }
```

- Treated as an **override**: it bypasses the solver entirely.
- Resolved to HEAD of the branch at `forge deps` time; locked to that commit SHA in `forge.lock`.
- `forge update bastion` re-fetches HEAD and updates `forge.lock`.
- No version constraints can be expressed for branch deps — they are always treated as "any version, pinned to this SHA."

Branch deps are for development workflows only (e.g., using an unreleased fix). They should not appear in published libraries. `forge publish` emits a warning when branch deps are present.

#### Rev (exact pin)

```toml
foo = { git = "https://github.com/user/foo.git", rev = "abc123def456" }
```

- The commit hash is the lock. Nothing moves.
- Treated as an override (bypasses solver, like branch deps).
- `forge update foo` is a no-op and prints a notice: "foo is pinned to an exact commit. Change the rev in forge.toml to update."

### 3.3 Path Dependencies

```toml
vault = { path = "../vault" }
```

- For local development of multiple packages simultaneously.
- Treated as an override (bypasses solver).
- Not allowed in published packages — `forge publish` rejects manifests with path deps.
- CAS hash is computed from the local directory contents at build time.

### 3.4 Source Precedence

When the same package name appears in multiple sources, the rules are:

1. `[patch]` overrides take priority over everything (see section 6).
2. Path deps override git and registry deps.
3. Git deps override registry deps.
4. Registry deps are the solver's domain.

Mixed sources for the *same name* are an error (two different git URLs for `depot`, etc.).

---

## 4. The `[patch]` Section

Cargo-style fork substitution:

```toml
[patch.depot]
git = "https://github.com/myorg/depot-fork.git"
branch = "my-fix"
```

**Semantics:**
- Applied before the solver runs. Every occurrence of `depot` in the dependency graph (including transitive) is replaced with the patched version.
- The substituted version must satisfy the version constraints that other packages declare for `depot`. If `some_dep` requires `depot ~> 1.2` and the patch is at a commit that represents version `0.9.0`, the solver rejects it with a clear error.
- Patches are purely local — they are never published. `forge publish` strips `[patch]` sections and warns the user.
- Only one patch per package name. Two conflicting patches for the same name are an error.

**Use cases:**
1. Testing a bug fix in a dep before it's released.
2. Using a fork that has features not yet merged upstream.
3. Temporarily bypassing a breaking change while waiting for a downstream fix.

---

## 5. The PubGrub Solver

### 5.1 Algorithm Overview

PubGrub maintains two data structures:

1. **Partial solution** — a set of assignments: for each package, either "selected version V" or "incompatible with range R" (a negative assignment).
2. **Incompatibilities** — a set of constraints of the form "it is NOT the case that {P1 at V1 AND P2 at V2 AND ...}". Each incompatibility has a *cause* (e.g., "because P1 v1.2 depends on P2 ≥ 2.0 and P3 v3.4 depends on P2 < 2.0").

The solver iterates: pick the next unresolved package, try to derive a version consistent with all incompatibilities, and if a conflict is found, derive a new incompatibility from the derivation tree and backjump. Because each new incompatibility is stored with its cause chain, when the solver ultimately reaches a contradiction it can walk the cause chain to produce a human-readable explanation.

**Complexity:** O(n·d) in the common case where n is the number of packages and d is the depth of the dependency tree. Worst case is still exponential (unavoidable for NP-complete problems) but practically fast on real package graphs.

### 5.2 Solver Inputs

```ocaml
(* lib/resolver/solver.ml *)

type package = string  (* package name *)

type source =
  | Registry of { version : Version.t; deps : (package * Version.constraint_) list }
  | GitTag    of { version : Version.t; commit : string; url : string }
  | Override  of { commit : string option; path : string option }  (* branch/rev/path *)

(* The solver is given a function to look up available versions for a package.
   For the registry, this queries the index. For git-tag deps it returns one version.
   Overrides are pre-resolved before the solver runs. *)
type package_listing = package -> source list
```

### 5.3 Overrides Bypass the Solver

Branch deps, rev deps, and path deps are resolved *before* the solver runs:

1. Fetch or stat the source.
2. Add them to a "pre-resolved" map: `package → commit_or_path`.
3. For the solver, treat them as fixed version selections — as if the user manually pinned the exact version.
4. After solving, merge pre-resolved overrides back into the solution.

This avoids complicating the solver with non-version-comparable sources while still allowing version-constrained deps on the same package from elsewhere in the graph.

### 5.4 Error Message Format

When the solver finds an unsolvable constraint set, it produces a structured derivation tree that is formatted like Elm errors:

```
-- DEPENDENCY CONFLICT ----------------------------- forge.toml

I cannot find a version of `json` that satisfies all requirements.

Here is why:

  Your project requires `json ~> 1.0`.
  `http 2.3.0` (required by your project) requires `json >= 2.0`.

  Because `json ~> 1.0` means `json >= 1.0.0, < 2.0.0`, there is
  no version that satisfies both constraints at the same time.

To fix this, try one of:
  • Upgrade `http` to a version that supports `json ~> 1.0`.
  • Change your `json` constraint to `~> 2.0` if you can accept
    the breaking changes in json 2.0.
  • Use `[patch.json]` to substitute a fork that bridges both.
```

The diagnostic integrates with March's existing `lib/errors/errors.ml` type system (Error/Warning/Hint + span).

### 5.5 Implementation Reference

The canonical PubGrub implementation to reference is `pubgrub-rs` (Rust, MIT license) — the implementation used by Cargo. The OCaml implementation is a port following the same algorithm but adapted for March's type system and error infrastructure.

Key differences from the reference implementation:
- Error messages use March's `Diagnostic` type instead of `Display`.
- Version type uses March's semver representation.
- The registry is a local index file (initially) not a live HTTP API.

---

## 6. The Lockfile: `forge.lock`

### 6.1 Format

`forge.lock` is a TOML file committed to version control. It is the *single source of truth* for reproducible builds.

```toml
# This file is auto-generated by `forge deps`. Do not edit by hand.
# Generated by Forge 0.1.0 on 2026-03-27

[manifest_hash]
# SHA-256 of forge.toml contents — used to detect drift
value = "sha256:abc123..."

[[package]]
name    = "json"
version = "1.4.2"
source  = "registry:forge"
hash    = "blake3:deadbeef..."   # content hash of the canonical archive

[[package]]
name    = "http"
version = "2.3.0"
source  = "registry:forge"
hash    = "blake3:cafebabe..."

[[package]]
name    = "depot"
version = "0.2.1"
source  = "git:https://github.com/user/depot.git"
commit  = "f7a3b1c9e4d2..."
hash    = "blake3:11223344..."

[[package]]
name    = "bastion"
source  = "git:https://github.com/user/bastion.git"
commit  = "9901aabbcc..."
hash    = "blake3:55667788..."
# no version: branch dep has no semver version

[[package]]
name    = "vault"
source  = "path:../vault"
hash    = "blake3:99aabbcc..."  # recomputed on every build; used for invalidation only
```

### 6.2 Content Hash Semantics

The `hash` field is the BLAKE3 hash of the package's *canonical archive* (see section 7.2 on CAS). It serves two purposes:

1. **Build invalidation:** If `hash` changes between builds, the dep is stale and must be rebuilt.
2. **Integrity verification:** On every build, Forge re-hashes the CAS entry and checks it against `forge.lock`. A mismatch means the CAS was tampered with or corrupted — build aborts with an error.

### 6.3 Manifest Hash for Drift Detection

The `[manifest_hash]` entry is the SHA-256 of the current `forge.toml`. On every `forge build`:

1. Re-hash `forge.toml`.
2. Compare against `[manifest_hash].value` in `forge.lock`.
3. If they differ, print: "forge.toml has changed since the last `forge deps`. Run `forge deps` to update the lockfile."
4. Build continues with the existing lockfile (do not auto-resolve, to avoid surprises in CI).

This is inspired by Poetry's manifest hash tracking. It catches the common mistake of editing `forge.toml` without re-running `forge deps`.

### 6.4 `forge update` Behavior by Source Type

| Source type | `forge update <name>` behavior |
|-------------|-------------------------------|
| Registry    | Fetches newest version satisfying the constraint; re-runs solver |
| Git tag     | No-op (tag is a fixed point; user must change the tag string) |
| Git branch  | Fetches current HEAD of the branch; updates `commit` + `hash` |
| Git rev     | No-op (prints notice) |
| Path        | Re-hashes the directory; updates `hash` |

`forge update` (no args) updates all updatable deps (registry + git branch).

### 6.5 Lock File Policy

- **`app` and `tool` projects:** Commit `forge.lock`. It must be present in CI.
- **`lib` projects:** Do not commit `forge.lock`. Library consumers resolve the full tree.

`forge new` generates a `.gitignore` entry for `forge.lock` in lib projects and includes it for app/tool projects.

---

## 7. CAS Integration

### 7.1 Existing CAS

Forge builds on March's existing two-tier BLAKE3 CAS (`lib/cas/`):

- **Local:** `.march/cas/` (per-project, fast)
- **Global:** `~/.march/cas/` (shared across projects)

The existing CAS stores *build artifacts* (compiled modules). The new work extends it to store *package source archives* as well.

### 7.2 Canonical Archive Format

To compute a reproducible content hash for a package, Forge creates a **canonical archive** — inspired by Nix's `nix-prefetch` and Cargo's `.crate` format:

1. Collect all source files from the package root (excluding `.git/`, `.march/`, build artifacts).
2. Sort files by path (lexicographic, UTF-8 byte order).
3. For each file, serialize: `<path_length_u32_le><path_bytes><content_length_u32_le><content_bytes>`.
4. Set modification timestamps to the Unix epoch (0). Strip execute bits; normalize all permissions to 0644 for files, 0755 for directories.
5. Concatenate all serialized files.
6. BLAKE3-hash the concatenated bytes.

This produces the same hash regardless of filesystem timestamps, umask, or checkout order. Two different machines fetching the same package at the same commit will always produce the same hash.

The canonical archive is stored in the CAS by its hash. It is never stored on disk as a `.tar` or `.zip` — the CAS entry *is* the canonical form.

### 7.3 Offline Builds

A build is offline-capable if and only if:

1. `forge.lock` exists.
2. Every `hash` in `forge.lock` exists in the CAS (local or global).

If both conditions hold, `forge build` makes zero network calls. This enables:
- Air-gapped CI environments (pre-populate the global CAS).
- Fast rebuilds after dependency changes (the old version is still in the CAS).
- "Vendor" workflow: run `forge deps --cache-only` to populate the global CAS, then commit nothing (the CAS is not checked in).

### 7.4 Integrity Verification

On every `forge build`:

```
for each package in forge.lock:
  entry = cas.lookup(package.hash)
  if entry is None:
    error: "Package `{name}` not found in CAS. Run `forge deps` to fetch it."
  actual_hash = blake3(canonical_archive(entry))
  if actual_hash != package.hash:
    error: "Integrity check failed for `{name}`. Expected {package.hash}, got {actual_hash}. The CAS may be corrupted."
```

Path deps are re-hashed on every build (directory contents can change freely). Their hash in `forge.lock` is updated silently on each successful build — it is a build-invalidation hint, not an integrity check.

---

## 8. Fork Handling

### 8.1 Forks Are Separate Packages

The default treatment of a fork is: a package with a different name is a different package. If `myorg/depot` is a fork of `upstream/depot`, they are entirely separate packages — no special handling needed.

This is the correct model for permanent forks that diverge intentionally (e.g., a fork that maintains a different API contract).

### 8.2 Temporary Fork Substitution via `[patch]`

For temporary forks — "I need a bug fix that hasn't been released yet" — use `[patch]` (described in section 4).

The patch mechanism works because it replaces the package *before* the solver runs. All transitive dependencies that reference `depot` will get the patched version. The solver then verifies that the patched version satisfies all constraints.

### 8.3 Transitive Conflict Rejection

**One package name, one version.** The solver never allows two different packages with the same name to exist in the resolved tree simultaneously. This is a hard invariant — no npm-style tree duplication.

If two transitive deps require incompatible versions of the same package, the solver must find a single version that satisfies both, or fail with a derivation-tree error message. There is no fallback to duplicating the package.

**Why:** March's type system makes version duplication unsafe. If `PackageA` exports `type Foo` at version 1.0 and `PackageB` depends on `Foo` from version 2.0, passing a `PackageA.Foo` to a `PackageB` function expecting `Foo` is a type error. Silently running both versions is a runtime disaster waiting to happen.

### 8.4 `forge publish` and Forks

- `forge publish` strips `[patch]` sections before publishing. It is an error to depend on a patched version in a published package.
- The publication system records the upstream package name (not the fork name), so users can find the canonical package.

---

## 9. API Surface Diffing and Semver Enforcement

### 9.1 Motivation

Semver promises: major bumps for breaking changes, minor bumps for new features, patch bumps for bug fixes. In practice, package authors forget, misread their diff, or don't know what counts as a breaking change. The result: users get broken builds after `forge update`.

March's type system gives us everything we need to make semver enforcement *automated*. The compiler knows every public type and function signature. We can compare two versions' API surfaces and determine exactly what kind of bump is required.

This feature activates at `1.0.0`. Pre-1.0 packages (`0.x.y`) get a pass — breaking changes in minor bumps (`0.1.0` → `0.2.0`) are allowed, matching the convention in Cargo, Hex, and npm.

### 9.2 Public API Surface

The public API surface of a package is:

1. All types exported from the top-level module (those not marked `priv`).
2. All function signatures exported from the top-level module.
3. Recursively, all types and functions re-exported from submodules.

Not included: internal implementation details, private types, docstrings, comments.

```ocaml
(* lib/resolver/api_surface.ml *)

type type_def =
  | Alias   of { name : string; rhs : Type.t }
  | Variant of { name : string; constructors : (string * Type.t list) list }
  | Record  of { name : string; fields : (string * Type.t * visibility) list }
  | Opaque  of { name : string }   (* abstract type — only name matters for compat *)

type fn_sig = {
  name   : string;
  params : Type.t list;
  ret    : Type.t;
}

type surface = {
  types : type_def list;
  fns   : fn_sig list;
}

val extract : Module.t -> surface
val diff    : old:surface -> new_:surface -> Change.t list
```

### 9.3 Change Classification

| Change | Required bump |
|--------|--------------|
| Remove a public function or type | Major |
| Change a function's parameter types or return type | Major |
| Change a variant constructor (rename, add/remove/reorder fields) | Major |
| Change a record field (rename, change type, add without default) | Major |
| Add a new public function | Minor |
| Add a new variant constructor (only if exhaustive match is not required) | Minor |
| Add a new record field with a default value | Minor |
| Add a new opaque type | Minor |
| Change a docstring or comment | Patch |
| Change a private/internal implementation | Patch |
| Bug fix with no API change | Patch |

**Linear/affine type edge cases:** If a function's parameter changes from a regular type to a linear type (or vice versa), that is a breaking change (callers must update usage patterns). The diff tool must track linearity annotations as part of the signature.

**Generic types:** If a generic type parameter changes its constraint (e.g., from `T` to `T: Eq`), that is a breaking change. The diff tool compares constraint sets.

### 9.4 `forge publish` Enforcement

```
forge publish
  1. Build the package (verify it compiles).
  2. Extract API surface from the compiled output.
  3. Fetch API surface of the latest published version from the registry.
  4. Compute diff.
  5. Determine required bump based on diff rules.
  6. Compare required bump against the version bump the author declared
     (current version vs. latest published version).
  7. If under-bumped: error with diff details.
  8. If over-bumped (e.g., patch change declared as major): warning only
     (allowed, but unusual).
  9. If version is pre-1.0.0: skip bump enforcement, proceed.
 10. If no previous version exists (first publish): skip enforcement.
 11. Upload the canonical archive to the registry.
```

Example error output:

```
-- SEMVER VIOLATION -------------------------------- forge.toml

You are publishing `json 1.4.3` but your changes require a MAJOR version bump.

Breaking changes detected:

  • Function `Json.parse` changed its return type:
      was: Result(Json.Value, String)
      now: Result(Json.Value, Json.Error)

  Because `Json.Error` is a new type, callers that pattern-matched on the
  error string will no longer compile after this update.

To publish this change, bump the version to `2.0.0` in forge.toml.

If this change is intentional but you believe it is not breaking,
run `forge publish --override-semver` with a justification.
```

### 9.5 `forge api-diff` Command

A standalone command for humans to inspect API changes:

```
forge api-diff 1.3.0 1.4.0       # compare two published versions
forge api-diff 1.3.0              # compare published version against current working tree
forge api-diff                    # compare latest published against current working tree
```

Output mirrors the diff output in `forge publish` but does not enforce anything.

---

## 10. Testing Strategy

### 10.1 Unit Tests — Version Constraint Parsing and Comparison

```
test/resolver/test_version.ml
```

- [ ] Parse valid semver strings: `1.0.0`, `0.2.3-alpha.1`, `1.0.0+build.1`
- [ ] Reject invalid semver: `1.0`, `v1.0.0`, `1.0.0.0`, `latest`
- [ ] Parse constraint strings: `~> 1.2`, `>= 2.0`, `< 3.0`, `>= 1.5, < 2.0`, `1.4.2`
- [ ] Reject invalid constraints: `~> latest`, `=> 1.0`, `1.0.x`
- [ ] `~>` expansion: verify `~> 1.2` → `>= 1.2.0, < 2.0.0` and `~> 1.2.3` → `>= 1.2.3, < 1.3.0`
- [ ] `satisfies` function: exhaustive table of (version, constraint, expected_bool)
- [ ] Version ordering: compare all combinations from the semver precedence table
- [ ] Pre-release versions: `1.0.0-alpha < 1.0.0`, `~> 1.0` does not select `1.1.0-beta`

### 10.2 Unit Tests — PubGrub Solver

```
test/resolver/test_solver.ml
```

Test cases covering the full range of solver behaviors:

**Happy path:**
- [ ] Single package, exact version exists
- [ ] Two packages with no shared deps
- [ ] Diamond dependency: A→B, A→C, B→D≥1.0, C→D≥1.5 → should select D 1.5
- [ ] Transitive chain: A→B→C→D, all satisfied
- [ ] `~>` constraint resolution: `~> 1.2` selects latest `1.x.y` where `y >= 2`

**Conflict scenarios with expected derivation tree messages:**
- [ ] Direct conflict: root requires `json ~> 1.0` and `json >= 2.0`
- [ ] Transitive conflict: root requires A, A requires `json ~> 1.0`, root also requires B where B requires `json >= 2.0`
- [ ] Impossible constraint: no version exists satisfying `>= 3.0, < 2.0`
- [ ] No versions published: package exists in registry but has no versions
- [ ] Pre-release not selected by non-pre-release constraint

**Pre-1.0 packages:**
- [ ] `0.x.y` dep does not trigger major-version conflict detection
- [ ] `~> 0.2` expands to `>= 0.2.0, < 0.3.0` (not `< 1.0.0`)

**Override behavior:**
- [ ] Branch dep bypasses solver, does not conflict with registry dep for different package
- [ ] Path dep bypasses solver
- [ ] `[patch]` substitution: verify patched version is used in transitive deps
- [ ] `[patch]` with version mismatch: patched version doesn't satisfy constraint → clear error

### 10.3 Unit Tests — API Surface Extraction and Diffing

```
test/resolver/test_api_surface.ml
```

- [ ] Extract function signatures from a simple module
- [ ] Extract variant type constructors
- [ ] Extract record field types and visibility
- [ ] Opaque types: only name in surface (no internal structure)
- [ ] Re-exported submodule types included in surface
- [ ] Private functions excluded from surface

**Diff classification:**
- [ ] Removing a function → Major
- [ ] Adding a function → Minor
- [ ] Changing return type → Major
- [ ] Changing parameter type (including linearity annotation) → Major
- [ ] Adding variant constructor → Minor (non-exhaustive) vs. Major (exhaustive match required)
- [ ] Adding record field without default → Major
- [ ] No API change → Patch
- [ ] Pre-1.0 package: diff computed but enforcement skipped

### 10.4 Integration Tests — Lockfile Generation and Verification

```
test/resolver/test_lockfile.ml
```

Each test creates a temp directory with `forge.toml`, runs the resolver, and asserts on `forge.lock` contents.

- [ ] Fresh resolve: `forge.lock` created with correct versions and hashes
- [ ] Idempotent resolve: running `forge deps` twice produces identical `forge.lock`
- [ ] Manifest hash: `forge.lock` contains correct SHA-256 of `forge.toml`
- [ ] Drift detection: modify `forge.toml` after locking → build warns about drift
- [ ] `forge update <name>`: only the named package's entry changes
- [ ] `forge update` (all): all updatable deps updated, pinned deps unchanged
- [ ] Lock verification: tamper with a CAS entry → build aborts with integrity error
- [ ] Lock verification: CAS entry missing → build aborts with helpful error
- [ ] Pre-locked build: no network calls if all hashes present in CAS

### 10.5 Integration Tests — Git Dependency Resolution

```
test/resolver/test_git_deps.ml
```

These tests use a local bare git repository as the remote (no network calls):

- [ ] Tag dep: resolved to correct commit, parsed version participates in solver
- [ ] Tag dep: unparseable tag (non-semver) → clear error
- [ ] Branch dep: resolved to HEAD commit
- [ ] Branch dep: `forge update` advances to new HEAD
- [ ] Rev dep: resolved to exact commit, `forge update` is no-op
- [ ] Rev dep: invalid/unknown rev → clear error

### 10.6 Integration Tests — `[patch]` Override Behavior

- [ ] Patch substitutes for all occurrences (root + transitive)
- [ ] Patch version satisfies all constraints: build succeeds
- [ ] Patch version fails a constraint: clear error with constraint source
- [ ] Patch in published package: `forge publish` rejects it
- [ ] Two patches for same package: error

### 10.7 Edge Case Tests

- [ ] **Circular dependency:** A depends on B, B depends on A → error with clear message ("packages cannot depend on themselves transitively")
- [ ] **Diamond dep, compatible:** A→B and A→C, B→D ~> 1.0, C→D ~> 1.2 → D 1.2+ satisfies both, select latest
- [ ] **Diamond dep, incompatible:** B→D ~> 1.0, C→D ~> 2.0 → conflict error
- [ ] **Deep transitive chain:** 20-level chain, verify solver terminates in reasonable time
- [ ] **Self-dependency:** package depends on itself → error
- [ ] **Empty dep section:** `forge.lock` is empty, build succeeds
- [ ] **Dev dep isolation:** `[dev-deps]` not included in release build
- [ ] **`~> 0.x` behavior:** `~> 0.2` does not allow `0.3.0` (stays within minor)

### 10.8 Property-Based Tests

Using a random constraint graph generator (OCaml `QCheck` library):

- [ ] **Solver soundness:** For any constraint graph where a solution exists, the solver's solution satisfies every constraint.
- [ ] **Solver completeness:** If no solution exists, the solver reports an error (never returns a spurious solution).
- [ ] **Idempotence:** Running the solver twice on the same inputs produces the same result.
- [ ] **Version ordering transitivity:** `a < b` and `b < c` implies `a < c`.
- [ ] **`satisfies` consistency:** If `v satisfies c1` and `c1 implies c2`, then `v satisfies c2`.

Generate random package graphs:
- 5–200 packages
- 0–10 deps per package
- 1–20 versions per package
- Random semver constraints
- Verify solver output is consistent

### 10.9 Regression Tests (Real-World Scenarios)

Modeled after known bugs from Cargo/Hex/npm bug trackers:

- [ ] **Cargo #4309 (backtracking explosion):** Deep dependency graph with many conflicting options — verify solver terminates in < 1 second.
- [ ] **npm "phantom dep":** Package A resolves correctly in isolation but fails when B is added — verify determinism.
- [ ] **Hex duplicate resolution:** Two packages require the same dep at different compatible versions — verify single version selected, not duplicated.
- [ ] **Pre-release bleed:** `~> 1.0` should not select `2.0.0-beta.1` — regression for off-by-one in pre-release ordering.

### 10.10 Performance Tests

```
test/resolver/bench_solver.ml
```

Benchmark the solver on synthetic large graphs:

- [ ] 100 packages, average 5 transitive deps, no conflicts — should solve in < 50ms
- [ ] 500 packages, deep chains, no conflicts — should solve in < 200ms
- [ ] 100 packages with 3 conflict sites — should solve and produce error in < 100ms

These benchmarks run in CI with `--no-print-timings` (assert on correctness, not timing) but can be run locally with timing enabled. Add to `specs/benchmarks.md`.

---

## 11. Implementation Phases

### Phase 1: Version Constraint Parsing + Comparison + forge.lock Basics

**Goal:** Solid foundation. The version type and constraint language are correct and well-tested before the solver touches them.

- [ ] `lib/resolver/version.ml` — semver type, parsing, comparison, `satisfies`
- [ ] `lib/resolver/constraint.ml` — constraint parsing, `~>` expansion, AND combination
- [ ] `lib/resolver/lockfile.ml` — read/write `forge.lock` (TOML), manifest hash tracking
- [ ] Unit tests: version parsing, constraint parsing, `satisfies`, version ordering
- [ ] `forge deps` stub: reads `forge.toml`, writes `forge.lock` with placeholder hashes

**Done criteria:** `forge deps` on a project with only path deps writes a correct `forge.lock`. All version/constraint unit tests pass.

### Phase 2: PubGrub Solver Core

**Goal:** The solver works on registry deps with good error messages.

- [ ] `lib/resolver/pubgrub.ml` — partial solution, incompatibilities, conflict-driven backjump
- [ ] `lib/resolver/registry.ml` — local registry index format (flat TOML file for now), lookup function
- [ ] Solver integration in `forge deps` for registry deps
- [ ] Error formatting: derivation tree → `Diagnostic` (integrates with `lib/errors/errors.ml`)
- [ ] Unit tests: solver happy path, conflict scenarios, diamond deps, error message format
- [ ] Property-based tests: solver soundness and completeness

**Done criteria:** Solver resolves real-looking dependency graphs. Conflicts produce Elm-quality error messages. All solver unit + property-based tests pass.

### Phase 3: Git Dep Resolution + CAS Content Hashing

**Goal:** Git deps work and the CAS stores package archives with content hashes.

- [ ] `lib/resolver/git_source.ml` — fetch tags, branch HEAD, exact rev; parse tag as semver
- [ ] `lib/resolver/cas_package.ml` — canonical archive format, BLAKE3 hash computation, store/retrieve
- [ ] Extend `forge.lock` format with `commit` and `hash` fields
- [ ] `forge update <name>` for branch deps
- [ ] Build-time CAS integrity verification
- [ ] Integration tests: tag/branch/rev resolution, CAS verification, offline build

**Done criteria:** Git deps resolve correctly in all three forms. CAS stores and verifies package archives. Tampered CAS detected at build time.

### Phase 4: `[patch]` Overrides + Fork Handling

**Goal:** Developers can substitute forks without changing transitive dep declarations.

- [ ] Parse `[patch]` section in `forge.toml`
- [ ] Pre-resolution pass: apply patches before solver runs
- [ ] Validate patched version satisfies all constraints; error if not
- [ ] `forge publish` rejects manifests with `[patch]`
- [ ] Integration tests: patch substitution, version mismatch error, transitive patch

**Done criteria:** `[patch]` works for git and path substitutions. All patch integration tests pass.

### Phase 5: API Surface Extraction + Semver Enforcement

**Goal:** `forge publish` enforces correct semver bumps using the type system.

- [ ] `lib/resolver/api_surface.ml` — extract surface from typechecked module
- [ ] `lib/resolver/api_diff.ml` — diff two surfaces, classify changes
- [ ] `forge api-diff` command
- [ ] `forge publish` integration: surface diff before upload, enforcement for ≥ 1.0.0
- [ ] Unit tests: extraction, diff classification, linearity/generic edge cases
- [ ] Integration test: publish with wrong bump → error with diff output

**Done criteria:** `forge publish` catches all breaking-change categories. Pre-1.0 packages exempt. `forge api-diff` runs standalone. All API surface tests pass.

### Phase 6: Performance Optimization + Property-Based Testing

**Goal:** Solver is fast enough for large real-world graphs. Edge cases are exhaustively covered.

- [ ] Profile solver on 500-package synthetic graphs; optimize hot paths
- [ ] Implement property-based tests with QCheck
- [ ] Regression tests for known Cargo/Hex/npm bugs
- [ ] Performance benchmarks in `test/resolver/bench_solver.ml`
- [ ] Add benchmarks to `specs/benchmarks.md`
- [ ] Verify offline build (no network) works end-to-end

**Done criteria:** Solver benchmarks meet thresholds from section 10.10. Property-based tests run 10,000 random cases without failures. All regression tests pass.

---

## 12. File Layout

```
lib/resolver/
├── version.ml          # semver type, parsing, comparison, satisfies
├── constraint.ml       # constraint parsing, ~> expansion, AND
├── pubgrub.ml          # PubGrub solver algorithm
├── registry.ml         # local registry index, package lookup
├── git_source.ml       # git dep resolution (tag/branch/rev)
├── cas_package.ml      # canonical archive, BLAKE3 hash, CAS store/retrieve
├── lockfile.ml         # forge.lock read/write, manifest hash
├── api_surface.ml      # public API extraction from typechecked module
└── api_diff.ml         # surface diff, change classification

test/resolver/
├── test_version.ml     # unit: version parsing and comparison
├── test_solver.ml      # unit: PubGrub solver scenarios
├── test_api_surface.ml # unit: API extraction and diff
├── test_lockfile.ml    # integration: lockfile generation and verification
├── test_git_deps.ml    # integration: git dep resolution
├── test_patch.ml       # integration: [patch] overrides
├── test_edge_cases.ml  # edge: circular, diamond, empty, dev-deps
├── test_properties.ml  # property-based: QCheck solver soundness
├── test_regression.ml  # regression: known real-world bug scenarios
└── bench_solver.ml     # performance: large graph benchmarks
```

---

## 13. Connections to Existing Specs

- **`specs/plans/forge-spec.md`** — this plan expands sections 4.2, 6, and supersedes the "Future Work" item on "Dependency version resolution."
- **`lib/cas/`** — canonical archive format extends the existing BLAKE3 CAS without breaking changes.
- **`lib/errors/errors.ml`** — solver error messages use the existing `Diagnostic` type for consistency with compiler errors.
- **`lib/typecheck/typecheck.ml`** — API surface extraction reads typechecked module types; no new passes needed, uses existing type information.

---

## Appendix A: `forge.toml` Full Example (Extended)

```toml
[project]
name    = "my_web_app"
version = "1.2.0"
type    = "app"
march   = "0.1.0"

[deps]
json   = { registry = "forge", version = "~> 1.4"  }
http   = { registry = "forge", version = ">= 2.0"  }
depot  = { git = "https://github.com/user/depot.git", tag = "v0.2.1" }
live   = { git = "https://github.com/user/live.git", branch = "main" }
pinned = { git = "https://github.com/user/pinned.git", rev = "a1b2c3d4" }
vault  = { path = "../vault" }

[dev-deps]
mock = { registry = "forge", version = "~> 0.5" }

[patch.depot]
git    = "https://github.com/myorg/depot-fork.git"
branch = "fix/race-condition"

[profile.release]
opt_level = 3
strip     = true
```

## Appendix B: `forge.lock` Full Example (Extended)

```toml
# This file is auto-generated by `forge deps`. Do not edit by hand.

[manifest_hash]
value = "sha256:3d8f2e1a..."

[[package]]
name    = "json"
version = "1.4.7"
source  = "registry:forge"
hash    = "blake3:aabbccdd..."

[[package]]
name    = "http"
version = "2.3.1"
source  = "registry:forge"
hash    = "blake3:11223344..."

[[package]]
name    = "depot"
version = "0.2.1"
source  = "git:https://github.com/myorg/depot-fork.git"  # patched
commit  = "f9e8d7c6b5a4..."
hash    = "blake3:55667788..."

[[package]]
name    = "live"
source  = "git:https://github.com/user/live.git"
commit  = "a0b1c2d3e4f5..."
hash    = "blake3:99aabbcc..."

[[package]]
name    = "pinned"
source  = "git:https://github.com/user/pinned.git"
commit  = "a1b2c3d4"
hash    = "blake3:ddeeff00..."

[[package]]
name   = "vault"
source = "path:../vault"
hash   = "blake3:11223355..."
```
