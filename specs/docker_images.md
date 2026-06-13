# Docker Images

This spec defines the official Docker images March should publish, how they are built and tagged, and the recommended container patterns for building and deploying March programs. It builds on the prebuilt-release pipeline ([github_release_builds.md](github_release_builds.md)), the `install.sh` installer, and the `forge toolchain` version manager.

**Status: Proposed — not yet implemented.** Nothing in this document has been built; it is a design to be reviewed before any work starts.

## Motivation

`march --compile` shells out to `clang` + LLVM to build the bundled C runtime, so native compilation needs a C toolchain on the host — the one prerequisite that is awkward to install and version-pin reliably across machines. A published toolchain image removes that friction: pull one image and `forge build` works, identically, on any host with Docker, in CI, and on a contributor's laptop.

Separately, March compiles to a **statically linked** native binary (musl on Linux). A compiled March program — most usefully a [bastion](bastion/architecture.md)/conduit web server — therefore needs **no runtime base image at all**: the binary can be copied into `scratch` or a distroless image, producing a deploy image of a few megabytes with zero runtime dependencies. This is a strong, distinctive deployment story that the project should make turnkey.

## Goals

- A published, multi-arch **toolchain image** that can `forge build` / `march --compile` out of the box.
- A documented, copy-pasteable **multi-stage deploy pattern** that yields a minimal static-binary image for web apps.
- Images built from the **prebuilt release artifacts** (fast, reproducible) rather than compiled from source per build.
- Multi-architecture (`linux/amd64`, `linux/arm64`) matching the release platform matrix.

## Non-Goals

- A standalone "runtime" image. Compiled March binaries are self-contained; the multi-stage deploy pattern covers running them without a dedicated image.
- Replacing `ci/Dockerfile.ubuntu`. That image builds the compiler **from source** to reproduce the CI environment for contributors — a different audience and lifecycle. It stays as-is.
- Windows containers. Out of scope until a Windows native target exists.

## Images

### 1. Toolchain image — `ghcr.io/march-language/march`

A ready-to-use March development/build environment.

**Contents**
- `march`, `forge`, the standard library, and the C runtime sources — installed from the prebuilt release for the image's architecture (the same tarball `install.sh` consumes), under `/opt/march` with `/opt/march/bin` on `PATH`.
- `clang` + LLVM and a minimal C toolchain (required by `march --compile`).
- `git` and `curl` (forge fetches git/registry dependencies).

**Base image.** A slim Debian/Ubuntu base (`debian:stable-slim` or `ubuntu:24.04`) — LLVM packaging is reliable there and it matches the `linux-x86_64` release toolchain. Alpine is rejected for the toolchain image because LLVM/clang on musl is more fragile; the *output* binary is still static and Alpine-friendly.

**Install method.** The Dockerfile installs `clang`/`llvm`/`git`/`curl` via the base package manager, then runs the published `install.sh` pinned to the image's version (`MARCH_VERSION=<tag>`), so the image tracks releases automatically with no source build.

**User.** Runs as a non-root `march` user with a writable `~/.march` (so `forge toolchain` and the CAS cache work inside the container).

**Sketch** (`ci/Dockerfile.toolchain`, illustrative — not final):

```dockerfile
FROM debian:stable-slim
ARG MARCH_VERSION=latest
RUN apt-get update && apt-get install -y --no-install-recommends \
      clang llvm git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN useradd -m march
USER march
RUN curl -fsSL https://raw.githubusercontent.com/march-language/march/main/install.sh | sh
ENV PATH="/home/march/.march/bin:${PATH}"
WORKDIR /work
CMD ["forge", "build"]
```

### 2. Multi-stage deploy pattern (documentation + template)

Not a published image — a documented `Dockerfile` users add to their project, plus optionally a `forge new --docker` stub that scaffolds it. It builds in the toolchain image and copies the **static binary** into a minimal final stage:

```dockerfile
# ---- build stage ----
FROM ghcr.io/march-language/march:latest AS build
WORKDIR /app
COPY . .
RUN forge build --release            # produces a static native binary

# ---- runtime stage ----
FROM gcc:distroless    # or: scratch
COPY --from=build /app/bin/myapp /usr/local/bin/myapp
ENTRYPOINT ["/usr/local/bin/myapp"]
```

Because the Linux binary is musl-static, `scratch` works for pure-compute programs; distroless (with CA certs) is recommended for servers that make TLS connections. The exact `forge build` output path and a `--release` flag are dependencies to confirm (see Open Questions).

## Tags

| Tag | Points at | Updated |
|-----|-----------|---------|
| `latest` | newest stable release | on each stable `v*` release |
| `<version>` (e.g. `0.1.0`) | that exact release | once, immutable |
| `<major>.<minor>` (e.g. `0.1`) | newest patch in that line | on matching releases |
| `nightly` | newest nightly build | daily |

All tags are multi-arch manifests covering `linux/amd64` and `linux/arm64`.

## Build & Publish

- Built with `docker buildx` for `linux/amd64,linux/arm64` and pushed to **GHCR** (`ghcr.io/march-language/march`).
- A new `docker` job is added to `release.yml` (stable tags) and `nightly.yml` (`nightly` tag). It runs **after** the release artifacts are published, since the image installs from them.
- Authenticates with the workflow `GITHUB_TOKEN` (needs `packages: write`).
- The `arm64` layer can build natively on an arm runner or via QEMU, mirroring the existing aarch64 release job.

## Size & Caching

- The toolchain image is large (LLVM is ~1 GB). Acceptable for a build image; documented so users aren't surprised.
- Layer order puts the slow, rarely-changing apt install first and the `install.sh` step last, so version bumps only rebuild the small final layer.
- The deploy-pattern final image is a few MB (just the static binary + optional CA certs).

## Security

- Images run as a non-root user.
- Base images are pinned by digest in the committed Dockerfile and refreshed deliberately.
- The published image embeds the release it was built from; the `install.sh` checksum verification (fail-closed) covers artifact integrity during the build.
- Document `docker pull ghcr.io/march-language/march@sha256:…` for users who want to pin by digest.

## Relationship to Existing Artifacts

- **`ci/Dockerfile.ubuntu`** — unchanged. From-source CI reproduction for contributors.
- **`install.sh`** — reused verbatim inside the toolchain Dockerfile; the image is "a host with `install.sh` already run + clang."
- **`forge toolchain`** — works inside the container (writable `~/.march`), so users can switch March versions within an image if needed.
- **Static linking** ([progress.md](progress.md), 2026-06-13 entries) — the reason the deploy stage can be `scratch`/distroless.

## Open Questions

1. **`forge build --release` and output path.** The deploy pattern assumes a release build mode and a predictable binary path. Confirm/define `forge build`'s output location and whether a `--release` flag exists.
2. **CA certificates in the deploy image.** Servers doing outbound TLS need certs; decide whether to recommend distroless-with-certs by default and document the `scratch` caveat.
3. **`forge new --docker`.** Worth scaffolding the multi-stage Dockerfile from `forge new`, or leave it as docs only?
4. **Image namespace.** `ghcr.io/march-language/march` vs. a dedicated `…/toolchain` repo if more images appear later.
5. **glibc vs musl in the toolchain image.** The image's *own* `march`/`forge` come from the `linux-x86_64`/`linux-aarch64` musl-static release, so they run on any base; confirm clang in a glibc base compiles user programs to musl-static as the release builds do, or document that container-built binaries are glibc-dynamic unless a musl target is selected.

## Implementation Plan (when approved)

1. **Toolchain Dockerfile** (`ci/Dockerfile.toolchain`) + local `docker build`/`buildx` validation on both arches.
2. **GHCR publish job** in `release.yml` and `nightly.yml` (buildx, multi-arch, `packages: write`), gated to run after artifacts publish.
3. **Deploy-pattern docs** — a section in `docs/` (and a link from the README) with the multi-stage `Dockerfile`, resolving Open Question #1/#2 first.
4. **(Optional) `forge new --docker`** scaffold.
5. Update `docs/installation.md` / README with a "Run March in Docker" section and update `specs/progress.md` + `specs/todos.md`.
