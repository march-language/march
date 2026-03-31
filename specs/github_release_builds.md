# GitHub Release Builds

This spec defines how March compiler binaries are built, packaged, and published via GitHub Actions. It covers the CI/CD pipeline, artifact structure, release process, nightly builds, and the `marchup` bootstrap script. Everything here is designed to integrate with the [forge version manager](forge_version_manager.md) — forge is the consumer of these artifacts.

## Build Matrix

All builds target OCaml 5.3.0 and produce native binaries for four platforms:

| OS    | Architecture | Runner              | Platform string  | Linking    |
|-------|-------------|---------------------|------------------|------------|
| macOS | Apple Silicon | `macos-14`          | `darwin-arm64`   | dynamic    |
| macOS | Intel        | `macos-13`          | `darwin-x86_64`  | dynamic    |
| Linux | x86-64       | `ubuntu-22.04`      | `linux-x86_64`   | static (musl) |
| Linux | AArch64      | `ubuntu-22.04` + QEMU | `linux-aarch64`  | static (musl) |

Platform strings match the forge version manager's platform detection table exactly (see `forge_version_manager.md § Platform Detection`).

### Why Static Linking on Linux

Linux distributions vary wildly in glibc version. A binary linked against glibc 2.35 won't run on a system with glibc 2.31. Static linking via musl eliminates this entirely — the resulting binary has zero runtime dependencies and runs on any Linux kernel 3.2+. macOS doesn't have this problem (dynamic linking against system libraries is stable across OS versions), and Apple discourages static linking anyway.

## Artifact Structure

Each platform produces a tar.gz archive with a consistent internal layout:

```
march-{version}-{os}-{arch}.tar.gz
└── march-{version}-{os}-{arch}/
    ├── bin/
    │   ├── march          # compiler binary
    │   └── forge          # package manager / version manager binary
    ├── stdlib/            # standard library source modules
    │   ├── core.march
    │   ├── io.march
    │   ├── collections.march
    │   └── ...
    └── LICENSE
```

This layout maps directly to what forge expects when unpacking into `~/.march/versions/<version>/` — forge strips the top-level directory and links the contents into the version directory.

Each release also includes a checksums file:

```
march-{version}-checksums.txt
```

Format (one line per archive, matching forge's expected checksum format):

```
sha256:abc123def456...  march-0.1.0-darwin-arm64.tar.gz
sha256:789abc012def...  march-0.1.0-darwin-x86_64.tar.gz
sha256:fedcba987654...  march-0.1.0-linux-x86_64.tar.gz
sha256:012345abcdef...  march-0.1.0-linux-aarch64.tar.gz
```

Note the `sha256:` prefix — this matches the hash format used throughout forge's CAS system.

## GitHub Actions Workflows

### Reusable Build Job

The core build logic lives in a reusable workflow that both the release and nightly workflows call.

```yaml
# .github/workflows/build.yml
name: Build

on:
  workflow_call:
    inputs:
      version:
        required: true
        type: string
      ref:
        required: true
        type: string
        description: "Git ref to build (tag, branch, or SHA)"

jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: macos-14
            platform: darwin-arm64
            ocaml-compiler: 5.3.0
          - os: macos-13
            platform: darwin-x86_64
            ocaml-compiler: 5.3.0
          - os: ubuntu-22.04
            platform: linux-x86_64
            ocaml-compiler: 5.3.0
            static: true
          - os: ubuntu-22.04
            platform: linux-aarch64
            ocaml-compiler: 5.3.0
            static: true
            cross: true

    runs-on: ${{ matrix.os }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          ref: ${{ inputs.ref }}

      # --- Linux static builds (musl) ---

      - name: Install musl toolchain (Linux)
        if: matrix.static
        run: |
          sudo apt-get update
          sudo apt-get install -y musl-tools

      - name: Set up QEMU (Linux aarch64 cross)
        if: matrix.cross
        uses: docker/setup-qemu-action@v3
        with:
          platforms: arm64

      # For aarch64, we build inside Alpine (musl-native) under QEMU.
      # This avoids cross-compilation complexity with OCaml.
      - name: Build in Alpine container (Linux aarch64)
        if: matrix.cross
        uses: addnab/docker-run-action@v3
        with:
          image: alpine:3.19
          options: >-
            --platform linux/arm64
            -v ${{ github.workspace }}:/work
            -w /work
          run: |
            apk add --no-cache bash opam ocaml build-base git
            opam init --disable-sandboxing --bare -y
            opam switch create 5.3.0 ocaml-base-compiler.5.3.0
            eval $(opam env)
            opam install --deps-only -y .
            dune build --force
            mkdir -p _dist/bin _dist/stdlib
            cp _build/default/bin/main.exe _dist/bin/march
            cp _build/default/forge/bin/main.exe _dist/bin/forge
            cp stdlib/*.march _dist/stdlib/
            cp LICENSE _dist/

      # --- macOS and Linux x86_64 native builds ---

      - name: Set up OCaml (native)
        if: "!matrix.cross"
        uses: ocaml/setup-ocaml@v3
        with:
          ocaml-compiler: ${{ matrix.ocaml-compiler }}

      - name: Install dependencies (native)
        if: "!matrix.cross"
        run: opam install --deps-only -y .

      - name: Build (Linux x86_64 static)
        if: matrix.static && !matrix.cross
        run: |
          eval $(opam env)
          OCAMLPARAM='_,ccopt=-static' dune build --force
          mkdir -p _dist/bin _dist/stdlib
          cp _build/default/bin/main.exe _dist/bin/march
          cp _build/default/forge/bin/main.exe _dist/bin/forge
          cp stdlib/*.march _dist/stdlib/
          cp LICENSE _dist/

      - name: Build (macOS)
        if: "!matrix.static"
        run: |
          eval $(opam env)
          dune build
          mkdir -p _dist/bin _dist/stdlib
          cp _build/default/bin/main.exe _dist/bin/march
          cp _build/default/forge/bin/main.exe _dist/bin/forge
          cp stdlib/*.march _dist/stdlib/
          cp LICENSE _dist/

      # --- Package ---

      - name: Strip binary
        run: |
          if command -v strip &> /dev/null; then
            strip _dist/bin/march || true
            strip _dist/bin/forge || true
          fi

      - name: Package archive
        run: |
          ARCHIVE_NAME="march-${{ inputs.version }}-${{ matrix.platform }}"
          mv _dist "${ARCHIVE_NAME}"
          tar czf "${ARCHIVE_NAME}.tar.gz" "${ARCHIVE_NAME}"

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: march-${{ inputs.version }}-${{ matrix.platform }}
          path: march-${{ inputs.version }}-${{ matrix.platform }}.tar.gz

  checksums:
    needs: build
    runs-on: ubuntu-22.04
    steps:
      - name: Download all artifacts
        uses: actions/download-artifact@v4
        with:
          path: artifacts
          merge-multiple: true

      - name: Generate checksums
        run: |
          cd artifacts
          for f in *.tar.gz; do
            hash=$(sha256sum "$f" | cut -d' ' -f1)
            echo "sha256:${hash}  ${f}" >> ../march-${{ inputs.version }}-checksums.txt
          done

      - name: Upload checksums
        uses: actions/upload-artifact@v4
        with:
          name: march-${{ inputs.version }}-checksums
          path: march-${{ inputs.version }}-checksums.txt
```

### Tagged Release Workflow

Triggered when a version tag is pushed. Creates a GitHub Release with all platform archives and checksums.

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    tags:
      - "v*"

permissions:
  contents: write

jobs:
  build:
    uses: ./.github/workflows/build.yml
    with:
      version: ${{ github.ref_name }}  # e.g. "v0.1.0"
      ref: ${{ github.ref }}

  publish:
    needs: build
    runs-on: ubuntu-22.04
    steps:
      - name: Download all artifacts
        uses: actions/download-artifact@v4
        with:
          path: artifacts
          merge-multiple: true

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ github.ref_name }}
          name: March ${{ github.ref_name }}
          body: |
            ## Installation

            ```
            curl -sSf https://march-lang.org/install | sh
            ```

            Or if you already have forge:

            ```
            forge install ${{ github.ref_name }}
            forge use ${{ github.ref_name }}
            ```

            ## Checksums

            Verify your download:

            ```
            sha256sum -c march-${{ github.ref_name }}-checksums.txt
            ```
          files: artifacts/*
          draft: false
          prerelease: false

      - name: Update latest tag
        run: |
          git tag -f latest ${{ github.ref_name }}
          git push -f origin latest
```

### Nightly Build Workflow

Runs daily at midnight UTC. Produces a nightly release with a date-stamped version.

```yaml
# .github/workflows/nightly.yml
name: Nightly

on:
  schedule:
    - cron: "0 0 * * *"  # midnight UTC daily
  workflow_dispatch:        # allow manual trigger

permissions:
  contents: write

jobs:
  version:
    runs-on: ubuntu-22.04
    outputs:
      version: ${{ steps.version.outputs.version }}
      date: ${{ steps.version.outputs.date }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Compute nightly version
        id: version
        run: |
          # Extract base version from dune-project
          BASE=$(grep '(version' dune-project | head -1 | sed 's/.*version \(.*\))/\1/')
          DATE=$(date -u +%Y%m%d)
          echo "version=${BASE}-nightly.${DATE}" >> "$GITHUB_OUTPUT"
          echo "date=${DATE}" >> "$GITHUB_OUTPUT"

  build:
    needs: version
    uses: ./.github/workflows/build.yml
    with:
      version: ${{ needs.version.outputs.version }}
      ref: main

  publish:
    needs: [version, build]
    runs-on: ubuntu-22.04
    steps:
      - name: Download all artifacts
        uses: actions/download-artifact@v4
        with:
          path: artifacts
          merge-multiple: true

      - name: Generate nightly manifest
        run: |
          VERSION="${{ needs.version.outputs.version }}"
          DATE="${{ needs.version.outputs.date }}"
          COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
          REPO="https://github.com/march-lang/march/releases/download"

          cat > nightly-manifest.json << MANIFEST
          {
            "version": "${VERSION}",
            "date": "${DATE}",
            "commit": "${COMMIT}",
            "assets": {
              "darwin-arm64": {
                "url": "${REPO}/nightly-${DATE}/march-${VERSION}-darwin-arm64.tar.gz",
                "sha256": "$(grep darwin-arm64 artifacts/march-${VERSION}-checksums.txt | cut -d' ' -f1)"
              },
              "darwin-x86_64": {
                "url": "${REPO}/nightly-${DATE}/march-${VERSION}-darwin-x86_64.tar.gz",
                "sha256": "$(grep darwin-x86_64 artifacts/march-${VERSION}-checksums.txt | cut -d' ' -f1)"
              },
              "linux-x86_64": {
                "url": "${REPO}/nightly-${DATE}/march-${VERSION}-linux-x86_64.tar.gz",
                "sha256": "$(grep linux-x86_64 artifacts/march-${VERSION}-checksums.txt | cut -d' ' -f1)"
              },
              "linux-aarch64": {
                "url": "${REPO}/nightly-${DATE}/march-${VERSION}-linux-aarch64.tar.gz",
                "sha256": "$(grep linux-aarch64 artifacts/march-${VERSION}-checksums.txt | cut -d' ' -f1)"
              }
            }
          }
          MANIFEST

      - name: Create nightly release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: nightly-${{ needs.version.outputs.date }}
          name: "Nightly ${{ needs.version.outputs.version }}"
          body: |
            Automated nightly build from `main` branch.

            **Version:** ${{ needs.version.outputs.version }}
            **Date:** ${{ needs.version.outputs.date }}

            Install with forge:
            ```
            forge install ${{ needs.version.outputs.version }}
            ```
          files: |
            artifacts/*
            nightly-manifest.json
          prerelease: true

      - name: Update rolling nightly tag
        run: |
          git tag -f nightly nightly-${{ needs.version.outputs.date }}
          git push -f origin nightly

  prune:
    needs: publish
    runs-on: ubuntu-22.04
    steps:
      - name: Prune old nightlies
        uses: actions/github-script@v7
        with:
          script: |
            const { data: releases } = await github.rest.repos.listReleases({
              owner: context.repo.owner,
              repo: context.repo.repo,
              per_page: 100,
            });

            const nightlies = releases
              .filter(r => r.tag_name.startsWith('nightly-') && r.tag_name !== 'nightly')
              .sort((a, b) => b.created_at.localeCompare(a.created_at));

            const toDelete = nightlies.slice(30);  // keep last 30
            for (const release of toDelete) {
              console.log(`Pruning ${release.tag_name}`);
              await github.rest.repos.deleteRelease({
                owner: context.repo.owner,
                repo: context.repo.repo,
                release_id: release.id,
              });
              try {
                await github.rest.git.deleteRef({
                  owner: context.repo.owner,
                  repo: context.repo.repo,
                  ref: `tags/${release.tag_name}`,
                });
              } catch (e) {
                console.log(`Tag ${release.tag_name} already deleted`);
              }
            }

            console.log(`Pruned ${toDelete.length} old nightlies, kept ${Math.min(nightlies.length, 30)}`);
```

## Release Process

### Creating a Stable Release

1. Update the version in `dune-project` and any other version references.
2. Commit and push to `main`.
3. Tag the commit and push the tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The `release.yml` workflow triggers automatically. It builds all four platform archives, generates checksums, and creates a GitHub Release. It also force-updates the `latest` tag to point at this release.

### Tag Semantics

| Tag | Points to | Updated by |
|-----|-----------|------------|
| `v0.1.0` (etc.) | Specific release commit | Never moved once created |
| `latest` | Most recent stable release tag | `release.yml` on each stable release |
| `nightly` | Most recent nightly release tag | `nightly.yml` daily |
| `nightly-20260328` (etc.) | Specific nightly build | Never moved once created |

### Version String Format

Stable releases: `0.1.0`, `0.2.0`, `1.0.0` — plain semver, no prefix in the version string itself. Git tags use the `v` prefix (`v0.1.0`) but the version embedded in the binary and archive names does not.

Nightly builds: `0.1.0-nightly.20260328` — base version from `dune-project` with a `-nightly.YYYYMMDD` pre-release suffix. This follows semver pre-release semantics, so `0.1.0-nightly.20260328 < 0.1.0` (any pre-release is less than the release), which is exactly the ordering forge's version resolver needs.

## GitHub Releases API Integration

Forge queries GitHub Releases to discover available versions. Here's how each forge command maps to API calls.

### `forge list-all`

```
GET /repos/march-lang/march/releases
```

Forge fetches the release list (paginated), filters to releases with assets matching the `march-*-.tar.gz` pattern, and extracts version strings from tag names. The response is cached at `~/.march/cache/releases.json` for 1 hour.

Stable releases have `prerelease: false`. Nightly releases have `prerelease: true` and tag names starting with `nightly-`.

### `forge install <version>`

1. **Find the release.** If the version is `latest`, fetch the release tagged `latest`. If nightly, find the release tagged `nightly-YYYYMMDD`. Otherwise, find the release tagged `v{version}`.

2. **Find the right asset.** Look for an asset named `march-{version}-{platform}.tar.gz` where `{platform}` matches the detected platform string.

3. **Download the checksums file.** Fetch `march-{version}-checksums.txt` from the same release.

4. **Download the archive.** Fetch the platform archive via the asset's `browser_download_url`.

5. **Verify.** Compute SHA-256 of the downloaded archive, compare against the checksums file. The hash must match the `sha256:{hex}` entry for this archive.

6. **Unpack.** Extract into `~/.march/versions/{version}/`, link files into CAS per the forge version manager spec.

### Rate Limiting

The GitHub API has rate limits (60 requests/hour unauthenticated, 5000/hour with a token). Forge handles this by:

- Caching the release list locally (`~/.march/cache/releases.json`, 1-hour TTL).
- Using conditional requests (`If-None-Match` with the ETag from the last response) to avoid counting against the limit when the cache is warm.
- If rate-limited, forge prints a message suggesting the user set `GITHUB_TOKEN` for higher limits.

## CAS Integration

Every artifact published in a release has a SHA-256 hash recorded in the checksums file. This integrates with forge's CAS as follows:

1. **Archive-level hash.** The checksums file records the hash of each `.tar.gz` archive. Forge verifies this after download, before unpacking. This hash is stored in the version manifest as `archive_hash`.

2. **File-level hashes.** After unpacking, forge computes SHA-256 of each individual file (`bin/march`, `bin/forge`, each `stdlib/*.march`, `LICENSE`) and stores them as CAS blobs at `~/.march/cas/blobs/<sha256>`. These per-file hashes enable deduplication across versions — if `stdlib/core.march` hasn't changed between v0.1.0 and v0.1.1, the blob is shared.

3. **Manifest.** Each installed version gets a `.forge-manifest.toml` recording archive hash, per-file hashes, download URL, and timestamp. See `forge_version_manager.md § CAS Integration` for the manifest format.

The build pipeline doesn't need to compute per-file hashes at build time — forge handles that on the client side during installation. The build pipeline only needs to produce the archive-level checksums file.

## The `marchup` Bootstrap Script

`marchup` is a POSIX shell script that bootstraps a fresh March installation. It's the entry point for new users.

### Installation One-Liner

```bash
curl -sSf https://march-lang.org/install | sh
```

The URL `https://march-lang.org/install` serves the `marchup` script. Alternatively, users can download it directly from the GitHub release:

```bash
curl -sSfL https://github.com/march-lang/march/releases/latest/download/marchup.sh -o marchup.sh
sh marchup.sh
```

### What `marchup` Does

```bash
#!/bin/sh
set -euo pipefail

MARCH_HOME="${MARCH_HOME:-$HOME/.march}"
REPO="march-lang/march"
BASE_URL="https://github.com/${REPO}/releases"

main() {
    echo "marchup: installing March compiler"
    echo ""

    # 1. Detect platform
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$OS" in
        darwin) OS="darwin" ;;
        linux)  OS="linux" ;;
        *)      err "unsupported OS: $OS" ;;
    esac

    case "$ARCH" in
        x86_64|amd64)   ARCH="x86_64" ;;
        arm64|aarch64)
            if [ "$OS" = "darwin" ]; then
                ARCH="arm64"
            else
                ARCH="aarch64"
            fi
            ;;
        *)  err "unsupported architecture: $ARCH" ;;
    esac

    PLATFORM="${OS}-${ARCH}"
    echo "Detected platform: ${PLATFORM}"

    # 2. Fetch latest version
    VERSION=$(curl -sSf "${BASE_URL}/latest" -o /dev/null -w '%{redirect_url}' \
        | grep -oE '[^/]+$' \
        | sed 's/^v//')

    if [ -z "$VERSION" ]; then
        err "could not determine latest version"
    fi

    echo "Latest version: ${VERSION}"

    ARCHIVE="march-${VERSION}-${PLATFORM}.tar.gz"
    CHECKSUMS="march-${VERSION}-checksums.txt"

    # 3. Download archive and checksums
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT

    echo "Downloading ${ARCHIVE}..."
    curl -sSfL "${BASE_URL}/download/v${VERSION}/${ARCHIVE}" -o "${TMPDIR}/${ARCHIVE}"
    curl -sSfL "${BASE_URL}/download/v${VERSION}/${CHECKSUMS}" -o "${TMPDIR}/${CHECKSUMS}"

    # 4. Verify checksum
    echo "Verifying checksum..."
    EXPECTED=$(grep "${ARCHIVE}" "${TMPDIR}/${CHECKSUMS}" | cut -d' ' -f1 | sed 's/^sha256://')
    ACTUAL=$(sha256sum "${TMPDIR}/${ARCHIVE}" 2>/dev/null \
        || shasum -a 256 "${TMPDIR}/${ARCHIVE}" | cut -d' ' -f1)
    ACTUAL=$(echo "$ACTUAL" | cut -d' ' -f1)

    if [ "$EXPECTED" != "$ACTUAL" ]; then
        err "checksum mismatch (expected ${EXPECTED}, got ${ACTUAL})"
    fi
    echo "Checksum verified."

    # 5. Extract to version directory
    VERSION_DIR="${MARCH_HOME}/versions/${VERSION}"
    mkdir -p "${VERSION_DIR}"
    tar xzf "${TMPDIR}/${ARCHIVE}" -C "${VERSION_DIR}" --strip-components=1

    chmod +x "${VERSION_DIR}/bin/march"
    chmod +x "${VERSION_DIR}/bin/forge"

    # 6. Set as active version
    echo "${VERSION}" > "${MARCH_HOME}/version"
    ln -sfn "${VERSION_DIR}" "${MARCH_HOME}/current"

    # 7. Verify installation
    echo ""
    "${VERSION_DIR}/bin/march" --version
    "${VERSION_DIR}/bin/forge" --version

    echo ""
    echo "March ${VERSION} installed successfully!"
    echo ""

    # 8. PATH instructions
    BINDIR="${MARCH_HOME}/current/bin"
    case "$SHELL" in
        */zsh)  PROFILE="$HOME/.zshrc" ;;
        */bash) PROFILE="$HOME/.bashrc" ;;
        *)      PROFILE="$HOME/.profile" ;;
    esac

    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BINDIR"; then
        echo "Add March to your PATH by adding this to ${PROFILE}:"
        echo ""
        echo "  export PATH=\"${BINDIR}:\$PATH\""
        echo ""
        echo "Then restart your shell or run:"
        echo ""
        echo "  source ${PROFILE}"
    fi
}

err() {
    echo "marchup: error: $1" >&2
    exit 1
}

main "$@"
```

### Precompiled `marchup` Binaries

For environments where `curl | sh` is undesirable, static `marchup` binaries are included in each release:

```
marchup-darwin-arm64
marchup-darwin-x86_64
marchup-linux-x86_64
marchup-linux-aarch64
```

These are tiny statically-linked binaries that do the same thing as the shell script. They're built as part of the release workflow and attached as release assets. (Implementation detail: these can be simple compiled shell-wrappers or small OCaml/C programs. They're a nice-to-have and can be deferred.)

## CI Pipeline (Non-Release)

In addition to the release and nightly workflows, a standard CI workflow runs on every push and pull request to catch build failures early.

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: macos-14
            ocaml-compiler: 5.3.0
          - os: ubuntu-22.04
            ocaml-compiler: 5.3.0

    runs-on: ${{ matrix.os }}

    steps:
      - uses: actions/checkout@v4

      - name: Set up OCaml
        uses: ocaml/setup-ocaml@v3
        with:
          ocaml-compiler: ${{ matrix.ocaml-compiler }}

      - name: Install dependencies
        run: opam install --deps-only --with-test -y .

      - name: Build
        run: |
          eval $(opam env)
          dune build

      - name: Test
        run: |
          eval $(opam env)
          dune runtest

      - name: Check formatting
        run: |
          eval $(opam env)
          dune fmt 2>&1 || true
```

## Implementation Plan

### Phase 1: CI Foundation
1. Add `.github/workflows/ci.yml` for build/test on push and PR.
2. Verify OCaml 5.3.0 builds work on macOS and Linux runners.
3. Ensure `dune build` produces `bin/main.exe` (march) and `forge/bin/main.exe` (forge).

### Phase 2: Release Workflow
4. Add `.github/workflows/build.yml` (reusable build job).
5. Add `.github/workflows/release.yml` (triggered by version tags).
6. Test with a `v0.1.0-rc1` tag to validate the full pipeline without publishing a "real" release.
7. Create the first real release (`v0.1.0`).

### Phase 3: Nightly Builds
8. Add `.github/workflows/nightly.yml`.
9. Run it via `workflow_dispatch` to validate before enabling the cron schedule.
10. Enable the midnight UTC cron schedule.
11. Verify forge can discover and install nightly builds.

### Phase 4: Bootstrap
12. Write `marchup.sh` and host it (either in the repo or on march-lang.org).
13. Add `marchup` precompiled binaries to the release workflow (optional, can defer).
14. Test the full bootstrap flow: `curl | sh` → `march --version` → `forge install` → `forge use`.

### Phase 5: Hardening
15. Add GPG signing for release archives (optional, can defer).
16. Add Sigstore/cosign signatures for supply chain security (optional, can defer).
17. Set up caching for opam dependencies in CI to speed up builds.
18. Monitor nightly build success rate and set up notifications for failures.

## Open Questions

- **Linux aarch64 build time.** QEMU emulation is slow. If builds take too long, consider using a native ARM runner (GitHub offers `ubuntu-22.04-arm` runners now) or cross-compiling OCaml with an aarch64-musl target. Cross-compiling OCaml is notoriously tricky, so QEMU is the safer starting point.

- **macOS code signing.** Unsigned macOS binaries trigger Gatekeeper warnings. For now, users can run `xattr -d com.apple.quarantine march` to clear the flag. Proper code signing requires an Apple Developer account and can be added later.

- **march-lang.org hosting.** The `marchup` shell script URL (`https://march-lang.org/install`) requires either a website or a redirect. A GitHub Pages site on the `march-lang` org works fine — it just serves the shell script with the right `Content-Type`.

- **Forge binary bootstrapping.** Currently forge is assumed to be built from the March repo alongside the compiler. If forge eventually becomes its own repo or binary, the release workflow needs adjustment.
