# forge tests skip, rather than fail, on two missing local prerequisites

Found running `scripts/bump-version.sh --dry-run 0.6.0`, which runs
`dune build @forge/test/runtest` and aborted on two forge cases that failed for
reasons of the machine, not the code.

- **`host-init` / container** (`forge/test/test_host_init.ml`). The Dockerfile's
  `... && passwd -u root 2>/dev/null || true` applied `|| true` to the whole
  `RUN` chain, so when `apk add openssh-server` failed (the container could not
  reach dl-cdn.alpinelinux.org), `docker build` still succeeded with an image
  that has no sshd, and the case FAILED at `docker run` instead of taking its
  documented "the sshd image did not build (no network?)" skip. The `|| true`
  is now scoped to `passwd`, the build ends with `test -x /usr/sbin/sshd`, and
  the image tag moved from `:1` to `:2` so an sshd-less image cached under the
  old tag is not reused.
- **`release build` / cross build linux/amd64** (`forge/test/test_release_build.ml`).
  It skipped only when zig was missing; with zig but no linux/amd64 sysroot
  (`~/.cache/march/cross-sysroot/linux-amd64` or `MARCH_CROSS_SYSROOT[_AMD64]`)
  march refuses the cross build and the case failed. It now skips in that case
  too, except under `CI`, where the setup action fetches a sysroot and its
  absence must stay a failure (checked: `CI=1` still fails it).
