# Docker Images

This spec defines the official Docker images March should publish, how they are built and tagged, and the recommended container patterns for building and deploying March programs. It builds on the prebuilt-release pipeline ([github_release_builds.md](github_release_builds.md)), the `install.sh` installer, and the `forge toolchain` version manager.

**Status: Proposed — not yet implemented.** Nothing in this document has been built; it is a design to be reviewed before any work starts.

## Motivation

`march --compile` shells out to `clang` + LLVM to build the bundled C runtime, so native compilation needs a C toolchain on the host — the one prerequisite that is awkward to install and version-pin reliably across machines. A published toolchain image removes that friction: pull one image and `forge build` works, identically, on any host with Docker, in CI, and on a contributor's laptop.

Separately, a compiled March program — most usefully a [bastion](bastion/architecture.md)/conduit web server — wants a small, boring deploy image. Today that image is a **slim distro base**, not `scratch`: `march --compile` links the bundled C runtime **dynamically** against the host's TLS, compression and hashing libraries (see [What `march --compile` actually links](#what-march---compile-actually-links) below). Making the output binary self-contained enough for `scratch` is real, tractable work — tracked separately as the static-musl profile — and would be a strong, distinctive deployment story; this spec documents the deploy pattern that works **now** and marks the `scratch` variant as a dependency, not an assumption.

## Goals

- A published, multi-arch **toolchain image** that can `forge build` / `march --compile` out of the box.
- A documented, copy-pasteable **multi-stage deploy pattern** that yields a minimal deploy image for web apps — a slim distro base today, `scratch`/distroless once the static-musl profile lands.
- Images built from the **prebuilt release artifacts** (fast, reproducible) rather than compiled from source per build.
- Multi-architecture (`linux/amd64`, `linux/arm64`) matching the release platform matrix.

## Non-Goals

- A standalone "runtime" image. The multi-stage deploy pattern's final stage is a stock slim base plus a short `apt`/`apk` line, which is cheaper to document than to publish and version.
- **Making `march --compile` emit a static binary.** That is the static-musl profile (a `--static`/`--target linux/<arch> static` mode), scoped as future work in [2026-07-04-cross-compile-linux-hot-deploy-design.md](2026-07-04-cross-compile-linux-hot-deploy-design.md) and filed as [`specs/todos/2026-09-02-march-compile-output-is-not-static.md`](todos/2026-09-02-march-compile-output-is-not-static.md). This spec depends on it for the `scratch` variant; it does not deliver it.
- Replacing `ci/Dockerfile.ubuntu`. That image builds the compiler **from source** to reproduce the CI environment for contributors — a different audience and lifecycle. It stays as-is.
- Windows containers. Out of scope until a Windows native target exists.

## Images

### 1. Toolchain image — `ghcr.io/march-language/march`

A ready-to-use March development/build environment.

**Contents**
- `march`, `forge`, the standard library, and the C runtime sources — installed from the prebuilt release for the image's architecture (the same tarball `install.sh` consumes), under `/opt/march` with `/opt/march/bin` on `PATH`.
- `clang` + LLVM and a minimal C toolchain (required by `march --compile`).
- `git` and `curl` (forge fetches git/registry dependencies).

**Base image.** A slim Debian/Ubuntu base (`debian:stable-slim` or `ubuntu:24.04`) — LLVM packaging is reliable there and it matches the `linux-x86_64` release toolchain. Alpine is rejected for the toolchain image because LLVM/clang on musl is more fragile. Note this choice also fixes the ABI of every binary the image produces: a glibc toolchain image emits glibc-dynamic programs, so the deploy stage must be a glibc base too.

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

Not a published image — a documented `Dockerfile` users add to their project, plus optionally a `forge new --docker` stub that scaffolds it. It builds in the toolchain image and copies the binary into a small final stage that carries the runtime's shared libraries:

```dockerfile
# ---- build stage ----
FROM ghcr.io/march-language/march:latest AS build
WORKDIR /app
COPY . .
RUN forge build --release

# ---- runtime stage ----
FROM debian:stable-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      libssl3 zlib1g libzstd1 libbrotli1 ca-certificates \
 && rm -rf /var/lib/apt/lists/*
# libblake3 has no distro package — carry it over from the build stage.
COPY --from=build /usr/lib/libblake3.so* /usr/lib/
COPY --from=build /app/bin/myapp /usr/local/bin/myapp
ENTRYPOINT ["/usr/local/bin/myapp"]
```

`scratch` and `distroless-static` do **not** work today, and a stock slim base
does not work on its own either — hence both the package line and the
`libblake3` copy. The next section says where each of those comes from.

### What `march --compile` actually links

The link command is assembled in `bin/main.ml` (the `Printf.sprintf` that builds
`cmd`, around the `math_flag` binding) with helpers in `bin/toolchain.ml`. It
passes **no `-static`** on any path. The cross path goes further and links
positional `.so` paths precisely so the target soname is recorded in
`DT_NEEDED`. Every library below is a `DT_NEEDED` entry on the output binary.

| Library | Comes from | Notes |
|---------|-----------|-------|
| `libssl`, `libcrypto` | `runtime/march_tls.c` | linked whenever the runtime source is present — i.e. always, not only for programs that use TLS |
| `libz` | `runtime/march_compress.c` | mandatory (gzip/deflate) |
| `libzstd`, `libbrotlienc`, `libbrotlidec` | `runtime/march_compress.c` | added when the build host has the headers, so the dependency set varies by build machine |
| `libblake3` | `runtime/march_blake3.c` | see below |
| `libucontext` (musl only) | scheduler green threads | musl has no `ucontext` in libc |
| `libc` / `libc.musl-<arch>` | always | |

Verified 2026-09-02 two ways. On `alpine:3.21` aarch64 under Docker, `readelf -d`
on a compiled hello-world lists `libssl.so.3`, `libcrypto.so.3`, `libz.so.1`,
`libzstd.so.1`, `libbrotlienc.so.1`, `libbrotlidec.so.1`, `libblake3.so`,
`libucontext.so.1` and `libc.musl-aarch64.so.1`. On macOS arm64 the same program
gives the identical set via `otool -L` (`libSystem` and no `libucontext` in place
of the musl pair) — this is a property of the link command, not of one host.

**`libblake3` is the sharp edge.** There is no `libblake3` package to install on
the distro bases March itself uses: `.github/workflows/build.yml` clones
BLAKE3 and compiles `libblake3.so` from source on **both** Linux release legs,
and builds a static `libblake3.a` on macOS because Homebrew ships only the dylib.
So the `apt`/`apk` line above cannot supply it, and a user's compiled program
depends on a library they have no packaged way to install — which is why the
deploy stage above copies it out of the build stage explicitly. That `COPY`
path is whatever the toolchain image put it at (`/usr/lib` for the Linux
release build); confirm it when the toolchain Dockerfile is written.

The durable fix is to stop emitting the dependency at all — link the static
`libblake3.a` (which `lib/cas/discover.ml` already prefers on macOS when one is
present) or vendor the BLAKE3 C sources into `runtime/` the way `tweetnacl.c` is
vendored — rather than shipping the `.so` around.

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
- The deploy-pattern final image is a slim base (~30 MB for `debian:stable-slim`) plus the binary, its shared libraries and CA certs — not the "few MB" a `scratch` image would give. The static-musl profile is what closes that gap.

## Security

- Images run as a non-root user.
- Base images are pinned by digest in the committed Dockerfile and refreshed deliberately.
- The published image embeds the release it was built from; the `install.sh` checksum verification (fail-closed) covers artifact integrity during the build.
- Document `docker pull ghcr.io/march-language/march@sha256:…` for users who want to pin by digest.

## Relationship to Existing Artifacts

- **`ci/Dockerfile.ubuntu`** — unchanged. From-source CI reproduction for contributors.
- **`install.sh`** — reused verbatim inside the toolchain Dockerfile; the image is "a host with `install.sh` already run + clang."
- **`forge toolchain`** — works inside the container (writable `~/.march`), so users can switch March versions within an image if needed.
- **Static linking** — applies to the *distributed compiler* binaries (`march`/`forge`), not to the output of `march --compile`. Making the deploy stage `scratch`/distroless-capable is the separate static-musl profile; until it lands the deploy stage needs a base with the libraries listed above.

## Open Questions

1. **`forge build --release` and output path.** The deploy pattern assumes a release build mode and a predictable binary path. Confirm/define `forge build`'s output location and whether a `--release` flag exists.
2. **CA certificates in the deploy image.** Servers doing outbound TLS need certs. The pattern above installs `ca-certificates`; decide whether that stays the default recommendation and how it carries over to a future `scratch` image, which would need the bundle copied in explicitly.
3. **`forge new --docker`.** Worth scaffolding the multi-stage Dockerfile from `forge new`, or leave it as docs only?
4. **Image namespace.** `ghcr.io/march-language/march` vs. a dedicated `…/toolchain` repo if more images appear later.
5. **glibc vs musl in the toolchain image.** Resolved as far as this spec is concerned: the image's *own* `march`/`forge` come from the release tarball and run on any base, but user programs built in it are **glibc-dynamic** (see [What `march --compile` actually links](#what-march---compile-actually-links)) — the toolchain image's base therefore fixes the ABI of everything it builds, and the deploy stage must match it. Documented rather than changed.
6. **Ordering vs. the static-musl profile.** Publishing the toolchain image does not depend on static output and should not wait for it; the `scratch` deploy variant is a documentation follow-up once [`specs/todos/2026-09-02-march-compile-output-is-not-static.md`](todos/2026-09-02-march-compile-output-is-not-static.md) lands.

## Implementation Plan (when approved)

1. **Toolchain Dockerfile** (`ci/Dockerfile.toolchain`) + local `docker build`/`buildx` validation on both arches.
2. **GHCR publish job** in `release.yml` and `nightly.yml` (buildx, multi-arch, `packages: write`), gated to run after artifacts publish.
3. **Deploy-pattern docs** — a section in `docs/` (and a link from the README) with the multi-stage `Dockerfile`, resolving Open Question #1/#2 first.
4. **(Optional) `forge new --docker`** scaffold.
5. Update `docs/installation.md` / README with a "Run March in Docker" section and update `specs/progress.md` + `specs/todos.md`.
