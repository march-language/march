`[P2]` # `march --compile` output is dynamically linked — no `scratch`/distroless deploy

Filed 2026-09-02 while correcting `specs/docker_images.md`, which asserted the
opposite (see `specs/progress/2026-09-02-docker-images-spec-claimed-static-user-binaries.md`).

Sibling of, and distinct from, `2026-08-31-linux-release-binaries-are-not-static.md`:
that one is about the **compiler** binaries we ship in the release archives.
This one is about the binary a **user's** program compiles to.

## The defect

`march --compile` never passes `-static`. The link command (`bin/main.ml`, the
`Printf.sprintf` building `cmd` near the `math_flag` binding; helpers in
`bin/toolchain.ml`) links the bundled C runtime against the host's shared
libraries, so every compiled March program carries `DT_NEEDED` entries for:

| Library | Source |
|---------|--------|
| `libssl`, `libcrypto` | `runtime/march_tls.c` — linked unconditionally, not only for programs that use TLS |
| `libz` | `runtime/march_compress.c` (mandatory) |
| `libzstd`, `libbrotlienc`, `libbrotlidec` | `runtime/march_compress.c`, added when the **build host** has the headers — so the dependency set varies by build machine |
| `libblake3` | `runtime/march_blake3.c` |
| `libucontext` | musl only; `runtime/march_scheduler.c` green threads (`swapcontext`) |
| `libc` / `libc.musl-<arch>` | always |

Verified 2026-09-02 on `alpine:3.21` aarch64 under Docker (`readelf -d` on a
compiled hello-world lists exactly that set) and independently on macOS arm64,
where `otool -L` on the same program gives the identical set (`libSystem`, no
`libucontext`). It is a property of the link command, not of one host.

`libblake3` is the worst of these: there is no package for it on the distro
bases March itself uses — `.github/workflows/build.yml` clones BLAKE3 and
compiles `libblake3.so` from source on both Linux release legs — so a user's
compiled program depends on a library they have no packaged way to install.

## Consequences

- A compiled March program cannot run in `scratch` or `distroless-static`, and
  will not run on a stock slim base either without an explicit `apt`/`apk` line
  **plus** a hand-copied `libblake3.so`.
- The "few megabytes, zero runtime dependencies" deploy story is not available.
- Because zstd/brotli are keyed off build-host headers, the same source can
  produce binaries with different dependency sets on different machines.

## Acceptance

A `--static` mode (or the static-musl target profile scoped as future work in
`specs/2026-07-04-cross-compile-linux-hot-deploy-design.md`) such that:

1. `march --compile --static hello.march` produces a binary with no `DT_NEEDED`
   entries (`readelf -d` shows none; `file` reports "statically linked").
2. A CI check **runs** that binary in a `scratch` (or `distroless-static`)
   container with nothing else in the image, and asserts its output. A link
   that merely succeeds is not evidence; this class of defect ships precisely
   because nobody executed the artifact in a bare environment.
3. Its failure mode when a static archive is missing is a clear diagnostic
   naming the library and the package that provides it — not a wall of
   linker `undefined reference` output.

Prerequisites worth doing on their own merits, each of which shrinks the
problem before any `-static` flag exists:

- **Stop depending on `libblake3` at all** — vendor the BLAKE3 C sources into
  `runtime/` the way `tweetnacl.c` is vendored, or link the static
  `libblake3.a` (`lib/cas/discover.ml` already prefers it on macOS when
  present). This removes the one dependency users cannot install.
- **Make TLS/compression opt-in** — `libssl`/`libcrypto` are linked into every
  program including pure-compute ones. Linking them only when the program
  reaches TLS would shrink both the dependency set and the binary.
- **Make the zstd/brotli probe deterministic** rather than build-host-dependent,
  so a program's dependency set is a function of its source and flags.

## Non-acceptance

Adding a `--static` flag that merely appends `-static` to the link line, without
the static archives being resolvable and without a bare-container run in CI, is
worse than the status quo: it converts an honest dynamic binary into a link
error or a silently-still-dynamic one.
