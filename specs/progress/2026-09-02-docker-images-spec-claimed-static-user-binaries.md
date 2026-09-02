# `specs/docker_images.md` claimed `march --compile` emits static binaries — corrected

`specs/docker_images.md` asserted, as present-tense fact, that "March compiles to
a **statically linked** native binary (musl on Linux)" and that a compiled
program "needs **no runtime base image at all**: the binary can be copied into
`scratch` or a distroless image, producing a deploy image of a few megabytes
with zero runtime dependencies." Neither is true, and the whole multi-stage
deploy pattern the spec recommended was built on it.

This is a **different** defect from the release-archive one
(`specs/todos/2026-08-31-linux-release-binaries-are-not-static.md`), which is
about the `march`/`forge` binaries we distribute. This one is about the output
of `march --compile` for a user's own program.

## What was verified

Two independent observations, both 2026-09-02:

- `alpine:3.21` aarch64 under Docker: `readelf -d` on a hello-world compiled
  with `march --compile` lists `libssl.so.3`, `libcrypto.so.3`, `libz.so.1`,
  `libzstd.so.1`, `libbrotlienc.so.1`, `libbrotlidec.so.1`, `libblake3.so`,
  `libucontext.so.1`, `libc.musl-aarch64.so.1`.
- macOS arm64, this worktree, `MARCH_ECHO_CC=1 march --compile`: the emitted
  clang line contains `-lssl -lcrypto -lz -lzstd -lbrotlienc -lbrotlidec
  -lblake3 -lm` and **no** `-static`; `otool -L` on the output shows the same
  set (`libSystem` and no `libucontext` in place of the musl pair).

The second is what makes it a property of the link command rather than of one
container: `grep` over `bin/`, `lib/` and `forge/` finds no `-static` on any
compile path (the single textual hit is the phrase "file-static" in a comment in
`lib/tir/llvm_toplevel.ml`). The cross-compile path goes the other way on
purpose — `bin/toolchain.ml`'s sysroot resolution links positional `.so` paths
specifically so the target soname lands in `DT_NEEDED`.

`libblake3` is the sharp edge: `.github/workflows/build.yml` clones BLAKE3 and
compiles `libblake3.so` from source on both Linux release legs (and builds a
static `libblake3.a` on macOS, since Homebrew ships only the dylib), because
there is no package to install on those bases. A user's compiled program
therefore depends on a library they have no packaged way to obtain.

## Decision: correct the spec, file the feature separately

The spec is marked **Status: Proposed — not yet implemented**; the static claim
was a design assumption that turned out false, not a regression against shipped
behaviour. Implementing `--static` here would mean sourcing static archives for
six libraries across two libcs, vendoring or statically linking BLAKE3, and
standing up a bare-container CI check — a feature in its own right, already
scoped as the static-musl profile under "Future work" in
`specs/2026-07-04-cross-compile-linux-hot-deploy-design.md`. Shipping a
`--static` flag that only appends `-static` to the link line would be a fake fix.

So: the spec now says what actually ships, and the feature is filed as
`specs/todos/2026-09-02-march-compile-output-is-not-static.md` with acceptance
criteria that require **running** the artifact in a `scratch` container, plus
three prerequisites worth doing on their own merits (drop the `libblake3`
dependency, make TLS/compression opt-in, make the zstd/brotli probe
deterministic rather than build-host-dependent).

## Changes to `specs/docker_images.md`

- **Motivation** — no longer claims static output; states that the deploy image
  is a slim distro base today and that `scratch` depends on the static-musl
  profile.
- **New section "What `march --compile` actually links"** — a table of every
  `DT_NEEDED` entry, where in `runtime/` it comes from, the two verifications
  above, and the `libblake3` problem with the `COPY --from=build` workaround
  and the two durable fixes.
- **Deploy pattern** — the final stage is now `debian:stable-slim` with an
  explicit `apt-get install libssl3 zlib1g libzstd1 libbrotli1 ca-certificates`,
  and the text says plainly that `scratch`/`distroless-static` do not work.
- **Non-Goals** — gained an explicit "making `march --compile` emit a static
  binary is not in this spec" bullet pointing at the new todo; the stale "compiled
  March binaries are self-contained" justification for having no runtime image
  was replaced with the real one (a stock base plus a short package line is
  cheaper to document than to publish and version).
- **Toolchain base image** — notes that the image's base fixes the ABI of every
  binary it builds, so the deploy stage must match it.
- **Size & Caching / Relationship / Open Questions** — the "few MB" figure, the
  "static linking is why the deploy stage can be `scratch`" bullet, and Open
  Question 5 (glibc vs musl) all corrected; a sixth open question records that
  the toolchain image should not wait on the static work.

Documentation only — no compiler change, no test-count change.
