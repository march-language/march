# Forge Version Manager

Forge doubles as March's version manager: it can install, switch between, and resolve multiple compiler versions so that projects pin exact toolchain versions and contributors get reproducible builds without manual setup.

## Motivation

March is a compiled language whose compiler is itself written in March (after bootstrapping from OCaml). As the language evolves, projects need to pin a specific compiler version — a library targeting 0.4.x shouldn't silently build with a 0.6 compiler that changed semantics. Forge already manages packages; extending it to manage compiler versions keeps the toolchain unified under one command and avoids yet-another-tool proliferation.

## Concepts

**Version string.** A semver triple `MAJOR.MINOR.PATCH`, optionally with a pre-release suffix (`0.5.0-nightly.20260328`). Leading `v` prefix is accepted and stripped. Build metadata (`+build`) is stripped and ignored, consistent with `Resolver_version`.

**Version alias.** The keyword `latest` always resolves to the most recent stable (non-pre-release) release. It is resolved at invocation time, never stored literally in config files.

**Nightly builds.** Pre-release versions with the form `X.Y.Z-nightly.YYYYMMDD`. Published as GitHub Actions artifacts, consumed via the GitHub Releases API or a dedicated nightly manifest.

**Global version.** The default compiler version used when no project-level pin exists. Stored in `~/.march/version` as a single semver line.

**Local version.** A `.march-version` file in a project directory containing a single semver line. Overrides the global version for that project tree.

## Directory Layout

```
~/.march/
├── version                  # global active version (plain text: "0.5.0\n")
├── current -> versions/0.5.0/  # symlink to active global version (convenience)
├── versions/
│   ├── 0.4.2/
│   │   ├── bin/
│   │   │   └── march        # compiler binary (symlink into CAS)
│   │   └── stdlib/           # standard library modules (symlinks into CAS)
│   ├── 0.5.0/
│   │   ├── bin/
│   │   │   └── march
│   │   └── stdlib/
│   └── 0.6.0-nightly.20260328/
│       ├── bin/
│       │   └── march
│       └── stdlib/
└── cas/
    ├── packages/             # existing package CAS (unchanged)
    │   └── <sha256>/
    └── blobs/                # compiler artifact CAS (new)
        └── <sha256>          # content-addressed file blobs
```

Each version directory is a thin symlink tree: its files point into `~/.march/cas/blobs/<sha256>` rather than storing data directly. This deduplicates shared artifacts across versions (e.g. stdlib modules unchanged between 0.5.0 and 0.5.1) and provides built-in integrity verification — the hash *is* the address.

## Version Resolution Order

When forge needs to determine which compiler version to use, it checks the following locations in order, using the first match:

1. **`.march-version` in the current directory.** Exact project-level pin.
2. **`.march-version` walking up parent directories.** Supports monorepos where a root `.march-version` covers all sub-projects.
3. **`~/.march/version` (global default).** The version set by `forge use <version>`.
4. **Fallback: error.** If none of the above exist, forge prints a helpful message telling the user to run `forge install` and `forge use`.

The `.march-version` file contains a single line: a semver string (e.g. `0.5.0`). No ranges, no aliases — always a resolved, exact version. This ensures reproducibility: two developers cloning the same repo with the same `.march-version` get the same compiler.

## Commands

### `forge list`

Show locally installed compiler versions. Marks the currently active version (per resolution order).

```
$ forge list
  0.4.2
* 0.5.0  (set by ~/.march/version)
  0.6.0-nightly.20260328
```

If a `.march-version` file is active, the marker reflects that:

```
$ forge list
  0.4.2
* 0.5.0  (set by .march-version)
  0.6.0-nightly.20260328
```

### `forge list-all`

Fetch the list of all available versions from the remote release manifest and display them, grouped by stability. Installed versions are marked.

```
$ forge list-all
Stable releases:
  0.3.0
✓ 0.4.2       (installed)
✓ 0.5.0       (installed)
  0.5.1

Nightly builds:
  0.6.0-nightly.20260325
  0.6.0-nightly.20260326
  0.6.0-nightly.20260327
✓ 0.6.0-nightly.20260328  (installed)
```

Implementation: GET the release manifest (see "Download Source" below), parse the version list, compare against `~/.march/versions/`.

### `forge install <version>`

Download and install a compiler version. Accepts a semver string or `latest`.

```
$ forge install 0.5.0
Downloading march 0.5.0 (darwin-arm64)...
Verifying checksum... ok
Unpacking to CAS... 47 blobs (12 new, 35 shared with 0.4.2)
Linking ~/.march/versions/0.5.0/
Done. Run `forge use 0.5.0` to activate.
```

Steps:

1. **Resolve version.** If `latest`, fetch the release manifest and pick the highest stable version. If the version is already installed, print a message and exit (unless `--force`).
2. **Detect platform.** Determine `{os}-{arch}` from runtime detection (see "Platform Detection").
3. **Download.** Fetch the archive and checksum file from the release source.
4. **Verify integrity.** Compute SHA-256 of the downloaded archive, compare against the published checksum. Abort on mismatch.
5. **Unpack into CAS.** For each file in the archive, compute its SHA-256 content hash and store it at `~/.march/cas/blobs/<sha256>` if not already present (deduplication). Record the mapping from relative path to content hash.
6. **Create version directory.** Build the symlink tree at `~/.march/versions/<version>/` with each file pointing to its CAS blob.
7. **Write manifest.** Store `~/.march/versions/<version>/.forge-manifest.toml` recording every file path, its content hash, the archive hash, download URL, and installation timestamp. Used for integrity checks and `forge doctor`.

Flags:

- `--force` — re-download and reinstall even if the version exists.
- `--no-verify` — skip checksum verification (not recommended, but useful for local testing).

### `forge use <version>`

Set the active compiler version.

**Global (default):** Sets the global default by writing the version to `~/.march/version` and updating the `~/.march/current` symlink.

```
$ forge use 0.5.0
Now using march 0.5.0 globally.
```

**Local (`--local`):** Creates or updates a `.march-version` file in the current directory.

```
$ forge use 0.5.0 --local
Wrote .march-version (0.5.0) in /home/chase/projects/myapp/
```

If the requested version is not installed, forge offers to install it:

```
$ forge use 0.7.0
march 0.7.0 is not installed. Install it? [Y/n]
```

### `forge build` (version-aware)

The existing `forge build` command gains version awareness. Before invoking the compiler, forge resolves the active version (per the resolution order above) and invokes the corresponding `march` binary.

```
$ forge build
Using march 0.5.0 (from .march-version)
Compiling myapp...
```

If the resolved version is not installed, forge prints an error with the fix:

```
$ forge build
Error: march 0.5.0 (from .march-version) is not installed.
Run `forge install 0.5.0` to install it.
```

Implementation: instead of running bare `march` from `$PATH`, forge constructs the path `~/.march/versions/<resolved>/bin/march` and invokes that directly.

### `forge upgrade`

Update forge itself to the latest release.

```
$ forge upgrade
Current: forge 0.3.0
Latest:  forge 0.4.0
Downloading forge 0.4.0 (darwin-arm64)...
Verifying checksum... ok
Installed. Restart your shell or run `hash -r` to pick up the new version.
```

Forge is distributed alongside the compiler in the same release archive. `forge upgrade` downloads the latest release archive, extracts the `forge` binary, and replaces itself. On Unix, this uses the rename-over-self pattern for atomic replacement.

### `forge uninstall <version>`

Remove an installed compiler version. Refuses to uninstall the currently active global version unless `--force` is passed.

```
$ forge uninstall 0.4.2
Removed march 0.4.2.
Cleaned 12 unreferenced CAS blobs (48 MB freed).
```

After removing the version directory, forge garbage-collects CAS blobs that are no longer referenced by any installed version.

## CAS Integration

Forge already uses content-addressed storage for package dependencies (`~/.march/cas/packages/`). The version manager extends this to compiler artifacts using a blob-level CAS store at `~/.march/cas/blobs/`.

### Design

The package CAS stores whole directory archives keyed by a single hash of the canonical archive. The compiler artifact CAS is more granular: each individual file (compiler binary, each stdlib module, etc.) is stored as an independent blob keyed by its own SHA-256 hash. This granularity enables file-level deduplication across versions.

**Hash computation.** Same algorithm as the package CAS — SHA-256 of the raw file bytes. Hash format: `sha256:<hex>`.

**Blob storage.** Flat directory at `~/.march/cas/blobs/<hex>`. No sharding by prefix initially; if the blob count grows large enough to cause filesystem performance issues, a two-character prefix sharding scheme (`~/.march/cas/blobs/ab/abcdef...`) can be introduced later without breaking the manifest format (which stores full hashes, not paths).

**Version directory as symlink tree.** `~/.march/versions/0.5.0/bin/march` is a symlink to `../../cas/blobs/<sha256>`. This means:

- Multiple versions sharing the same stdlib file don't duplicate on disk.
- Integrity is structural: if a blob's content doesn't match its filename hash, it's corrupt.
- Installing a new version that shares artifacts with an existing version is fast — only new blobs are downloaded and written.

**Manifest file.** Each version has a `.forge-manifest.toml`:

```toml
[metadata]
version = "0.5.0"
installed_at = "2026-03-28T14:30:00Z"
archive_hash = "sha256:abc123..."
source_url = "https://github.com/march-lang/march/releases/download/v0.5.0/march-0.5.0-darwin-arm64.tar.gz"

[[files]]
path = "bin/march"
hash = "sha256:def456..."
executable = true

[[files]]
path = "stdlib/core.march"
hash = "sha256:789abc..."
executable = false

# ... one entry per file
```

**Garbage collection.** When a version is uninstalled, forge scans all remaining version manifests to build the set of referenced blob hashes, then deletes any blobs in `~/.march/cas/blobs/` not in that set. This is an O(blobs × versions) operation but both counts are small enough that it's instantaneous in practice.

### Relationship to Package CAS

The two CAS stores are intentionally separate:

- `~/.march/cas/packages/<hash>/` — whole-archive CAS for dependency source trees (used by the package resolver and lockfile).
- `~/.march/cas/blobs/<hash>` — per-file CAS for compiler toolchain artifacts (used by the version manager).

They share the same hashing algorithm (SHA-256) and the same `~/.march/cas/` parent, but different granularity and structure. A future unification is possible but not worth the complexity now.

## Two-Level Dependency Caching

Dependencies are cached at two levels: a global cache shared across all projects, and a project-local tree that gives each project an isolated view of its deps.

### Global Cache

The global CAS at `~/.march/cas/packages/<sha256>/` is the single source of truth for downloaded dependency source trees. When forge resolves and fetches a dependency, it always lands here first. This means switching between projects that share dependencies doesn't re-download anything — the content hash either exists in the global cache or it doesn't.

### Project-Local Dependency Tree

Each project gets an isolated dependency tree at `<project-root>/deps/` (or `<project-root>/.march/deps/` if the project prefers hidden directories). This tree contains symlinks (or hardlinks on filesystems that don't support symlinks well) pointing back into the global CAS:

```
myapp/
├── forge.toml
├── forge.lock
├── deps/
│   ├── json/    -> ~/.march/cas/packages/abc123.../
│   ├── http/    -> ~/.march/cas/packages/def456.../
│   └── vault/   -> ~/.march/cas/packages/789abc.../
└── lib/
    └── myapp.march
```

This gives each project a self-contained deps directory that tools can inspect without understanding the CAS, while the actual bytes live in one place on disk.

### Fetch Flow

1. **Resolve.** The solver produces a lockfile (`forge.lock`) with exact versions and content hashes for every dependency.
2. **Fetch to global cache.** For each dep, if `~/.march/cas/packages/<hash>/` doesn't exist, download and unpack the source tree there. Verify the content hash matches the lockfile.
3. **Link into project.** Create symlinks from `<project-root>/deps/<name>/` to the corresponding global CAS entry.
4. **Build.** The compiler sees `deps/<name>/lib/` as a regular directory of March source files.

### Cache Eviction

The global cache has no automatic eviction — disk is cheap and dep source trees are small. `forge cache clean` removes entries not referenced by any project's lockfile that forge knows about (tracked in `~/.march/cache/projects.json`, updated every time `forge deps` runs). `forge cache clean --all` wipes the entire global cache.

## Cross-Version Dependency Compatibility

The CAS store is inherently version-agnostic: entries are keyed by content hash, not by compiler version. This has important practical consequences.

### Source Dependencies Are Always Reusable

Since the package CAS stores source trees (not compiled artifacts), a dependency fetched with march 0.4.0 is byte-for-byte identical to the same dependency fetched with march 0.5.0. The content hash is derived from the source files alone — no compiler version, platform, or build flags are mixed into the hash. Switching compiler versions never invalidates the source cache.

### Compiled Artifacts Are Version-Scoped

If forge gains a compilation cache (storing compiled `.o` or `.ll` files for dependencies to speed up builds), those artifacts must be scoped by compiler version, since different compiler versions may produce different output from the same source. The cache key for a compiled artifact would be:

```
sha256(source_hash + compiler_version + build_flags)
```

This is not implemented yet but the design leaves room for it. The important point is that the *source* CAS and the *compilation* cache are separate concerns — you never need to re-download a dependency just because you changed compiler versions.

### Lockfile Stability

The `forge.lock` file records content hashes of dependency source trees. These hashes are stable across compiler versions by construction. A lockfile generated with march 0.4.0 is valid with march 0.5.0 — the resolver doesn't need to re-run and the hashes don't change. The only reason to re-resolve is if `forge.toml` constraints change or the user explicitly runs `forge deps --update`.

### Incompatibility Detection

A dependency may declare its own `march` constraint in its `forge.toml` (e.g. `march = "~> 0.4.0"`). If you switch to march 0.5.0, `forge build` checks each dependency's `march` constraint against the active compiler version. If a dep is incompatible, forge reports the conflict clearly:

```
$ forge build
Error: dependency 'legacy-lib' requires march ~> 0.4.0, but active version is 0.5.0.
Options:
  - Update legacy-lib to a version compatible with march 0.5.0
  - Switch to an older compiler: forge use 0.4.2
```

This is a build-time check, not a fetch-time check. The source is still cached and reusable — it's the compilation step that refuses to proceed.

## Download Source

### Stable Releases

Published as GitHub Releases on `march-lang/march`. Each release includes platform-specific archives:

```
march-0.5.0-darwin-arm64.tar.gz
march-0.5.0-darwin-x86_64.tar.gz
march-0.5.0-linux-x86_64.tar.gz
march-0.5.0-linux-aarch64.tar.gz
march-0.5.0-checksums.txt
```

The checksums file contains one line per archive:

```
sha256:abc123def456...  march-0.5.0-darwin-arm64.tar.gz
sha256:789abc012def...  march-0.5.0-darwin-x86_64.tar.gz
...
```

**Release manifest.** Forge fetches available versions by querying the GitHub Releases API (`GET /repos/march-lang/march/releases`). The response is cached locally for 1 hour at `~/.march/cache/releases.json`.

### Nightly Builds

Nightly builds are produced by a scheduled GitHub Actions workflow that:

1. Builds the compiler from `main` for all supported platforms.
2. Versions the artifact as `X.Y.Z-nightly.YYYYMMDD` where `X.Y.Z` is the next unreleased version.
3. Publishes a GitHub Release tagged `nightly-YYYYMMDD` (or updates a rolling `nightly` release).
4. Includes a `nightly-manifest.json` as a release asset:

```json
{
  "version": "0.6.0-nightly.20260328",
  "date": "2026-03-28",
  "commit": "abc123f",
  "assets": {
    "darwin-arm64": {
      "url": "https://github.com/march-lang/march/releases/download/nightly-20260328/march-0.6.0-nightly.20260328-darwin-arm64.tar.gz",
      "sha256": "abc123..."
    },
    "darwin-x86_64": { "...": "..." },
    "linux-x86_64": { "...": "..." },
    "linux-aarch64": { "...": "..." }
  }
}
```

Forge discovers nightlies by fetching releases with the `nightly-` tag prefix. The `--nightly` flag on `forge list-all` filters to only show nightly builds.

## Platform Detection

Forge detects the current platform at runtime to select the correct download archive.

| OS      | Architecture | Platform string    |
|---------|-------------|-------------------|
| macOS   | Apple Silicon | `darwin-arm64`    |
| macOS   | Intel        | `darwin-x86_64`   |
| Linux   | x86-64       | `linux-x86_64`    |
| Linux   | AArch64      | `linux-aarch64`   |

Detection uses `uname -s` for OS and `uname -m` for architecture, with normalization (`x86_64`/`amd64` → `x86_64`, `aarch64`/`arm64` → the platform-canonical form). Windows is out of scope for the initial implementation.

## Bootstrapping

Forge is a March program, which creates a chicken-and-egg problem: you need a March compiler to build forge, but forge is how you install the compiler.

### `marchup` Bootstrap Script

A small POSIX shell script, `marchup`, handles the initial installation:

```
$ curl -sSf https://march-lang.org/install | sh
```

The script:

1. Detects the platform (`uname -s`, `uname -m`).
2. Fetches the latest stable release archive from GitHub Releases.
3. Verifies the SHA-256 checksum.
4. Extracts the archive to `~/.march/versions/<version>/`.
5. Creates `~/.march/version` with the installed version.
6. Creates the `~/.march/current` symlink.
7. Adds `~/.march/current/bin` to `$PATH` (prints instructions for the user's shell profile if it can't do so automatically).
8. Verifies the installation by running `march --version` and `forge --version`.

The release archive includes both `march` and `forge` as prebuilt binaries, so after `marchup` runs, both are immediately available.

### Alternative: Precompiled Bootstrap Binary

For environments where piping to `sh` is undesirable, precompiled `marchup` binaries (static, no dependencies) are available for direct download from the GitHub release:

```
$ wget https://github.com/march-lang/march/releases/latest/download/marchup-darwin-arm64
$ chmod +x marchup-darwin-arm64
$ ./marchup-darwin-arm64
```

## Self-Update

`forge upgrade` updates the forge binary itself. Since forge ships inside the compiler release archive, upgrading forge means downloading the latest release and extracting just the `forge` binary (or upgrading the entire toolchain version if the user wants).

For the common case where a user wants to update forge without switching compiler versions, `forge upgrade` operates independently: it downloads the latest release, extracts the `forge` binary, and replaces the current one in-place using atomic rename.

If forge detects that it's significantly behind the latest version, it prints a non-blocking reminder:

```
$ forge build
hint: forge 0.5.0 is available (you have 0.3.0). Run `forge upgrade` to update.
Compiling myapp...
```

## Version Constraints in forge.toml

The `forge.toml` project file gains an optional `march` field specifying the required compiler version:

```toml
[project]
name = "myapp"
version = "1.0.0"
march = "~> 0.5.0"
```

This is a **constraint**, not an exact pin — it uses the same constraint syntax as dependency versions (`~>`, `>=`, `<`, etc. from `Resolver_constraint`). The `.march-version` file is the exact pin; the `forge.toml` constraint is a compatibility guard.

When `forge build` runs:

1. Resolve the exact version from `.march-version` / global config.
2. If `forge.toml` has a `march` constraint, check that the resolved version satisfies it.
3. If not, error with a message explaining the mismatch.

This catches the case where a developer has globally switched to march 0.7.0 but the project requires `~> 0.5.0`.

## Shell Integration

For forge to work seamlessly, `~/.march/current/bin` must be on `$PATH`. The `marchup` installer handles this, but forge also provides a shell hook for version-switching on `cd`:

### Optional: Automatic Version Switching

Users can add a shell hook that automatically runs `forge use` when entering a directory with a `.march-version` file. This is opt-in and documented, not installed by default.

```bash
# ~/.bashrc or ~/.zshrc
eval "$(forge shell-hook)"
```

The hook updates the `~/.march/current` symlink when the resolved version changes, so that `which march` always points to the right binary. This is cosmetic — `forge build` always resolves the version independently — but makes direct `march` invocations from the shell use the expected version.

## Error Handling

Forge should produce clear, actionable error messages for common failure modes:

| Situation | Message |
|-----------|---------|
| Version not installed | `march 0.5.0 is not installed. Run 'forge install 0.5.0' to install it.` |
| No version configured | `No march version configured. Run 'forge install latest && forge use latest' to get started.` |
| Network failure | `Could not reach GitHub releases. Check your connection or use --offline.` |
| Checksum mismatch | `Checksum verification failed for march-0.5.0-darwin-arm64.tar.gz. The download may be corrupt. Run 'forge install 0.5.0 --force' to retry.` |
| Platform unsupported | `No prebuilt binary available for linux-riscv64. See docs for building from source.` |
| Version constraint mismatch | `march 0.7.0 (from ~/.march/version) does not satisfy 'march = "~> 0.5.0"' in forge.toml. Run 'forge install 0.5.1 && forge use 0.5.1' or update the constraint.` |

## Future Work

These are explicitly out of scope for the initial implementation but worth noting:

- **Windows support.** Requires `.exe` handling, different symlink semantics, and a PowerShell installer script.
- **Building from source.** `forge install 0.5.0 --source` could clone the repo at the tag and build locally. Requires a working compiler already installed (for self-hosting builds) or falling back to the OCaml bootstrap.
- **Version aliases.** Named aliases beyond `latest` (e.g. `stable`, `lts`) could be added if the release process introduces LTS tracks.
- **CAS blob sharding.** Prefix-based directory sharding (`ab/abcdef...`) if the flat blob directory hits filesystem limits.
- **Offline mode.** `forge install --offline` using only cached archives. Partially supported today since CAS blobs persist, but needs explicit archive caching.
