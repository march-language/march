`[P1]` # Every linux-aarch64 release archive ships with an empty `bin/`

Found 2026-08-23 while checking the v0.3.0 release assets, after noticing the
aarch64 archive was 692 KB against 11 MB for linux-x86_64.

## The defect

`march-v0.3.0-linux-aarch64.tar.gz` contains the 116 stdlib modules and the
bundled C runtime sources, and **no compiler**:

```
march-v0.3.0-linux-aarch64/bin/            <- empty directory
march-v0.3.0-linux-x86_64/bin/
march-v0.3.0-linux-x86_64/bin/march        <- present
march-v0.3.0-linux-x86_64/bin/forge        <- present
```

Both `bin/march` and `bin/forge` are absent. Anyone installing March on ARM
Linux gets a package with nothing to run.

**Not a 0.3.0 regression.** v0.2.0's aarch64 archive has the identical defect
(504 KB, zero binaries), so ARM Linux has never had a working release artifact.
It shipped a month ago and nobody noticed — which is the more useful finding
than the bug itself.

## Why nothing caught it

Three independent maskings, all now fixed in `.github/workflows/build.yml`:

1. **The Alpine container block had no `set -e`.** A `run:` block's exit status
   is that of its LAST command, which was `cp LICENSE _dist/ 2>/dev/null || true`
   — always 0. So a failure in `dune build` or in
   `cp _build/default/bin/main.exe _dist/bin/march` left the job green.
2. **`strip _dist/bin/march || true`** swallowed the absence a second time.
3. **Nothing verified the archive payload** before `tar czf`.

The checksums file is worth calling out: it verified correctly the whole time.
`sha256` proves the bytes arrived intact, not that they are the bytes anyone
wanted — a correctly-hashed empty archive passes every check the pipeline had.

## What is fixed vs what remains

Fixed here: the failure is now loud. `set -euo pipefail` in the container block,
plus a "Verify the build produced both binaries" step that runs before `strip`
and fails the job with a `::error::` naming the platform if either binary is
missing or zero-length.

**Still open: WHY the aarch64 build produces no binaries.** The copy commands
are present and correct in the workflow, and `mkdir -p _dist/bin` clearly
succeeded (the empty directory is in the archive), and `cp stdlib/*.march`
succeeded (those files are present) — so `cp` works and the failure is specific
to `_build/default/bin/main.exe` not existing. That points at
`dune build --force bin/main.exe forge/bin/main.exe` failing inside the Alpine
container, most likely a missing or mismatched dependency (the leg installs
`llvm19-dev`, builds blake3 from source, and creates its own global opam switch
— none of it shared with the native legs' cached `_opam`).

It cannot be diagnosed from here without an arm64 runner: the leg builds under
QEMU inside `alpine:3.21`, and the real error was never surfaced. With `set -e`
in place, the next release run will fail at the true error instead of
publishing an empty archive — that log is the next step.

## Update 2026-08-31: the true error, surfaced

The `set -e` guard worked as intended. Nightly run 33358635235, job
99385548165 (`build / build (ubuntu-24.04, linux-aarch64, …)`) failed loudly:

```
[WARNING] Running as root is not recommended
[ERROR] Command "/usr/bin/git ls-files" failed:
"/usr/bin/git ls-files" exited with code 128
```

The failure is **earlier than `dune build`** — it is `opam install --deps-only
-y .`, so the guess above (a missing Alpine dependency breaking the compile)
was wrong. The deps never install at all.

**Root cause.** `/work` is the host checkout bind-mounted into the container.
It is owned by the runner user (uid 1001) while the container runs as root, so
git rejects it under its `safe.directory` ownership check and exits 128 on any
plumbing command. `opam install .` shells out to `git ls-files` to enumerate
the pinned local package, so the deps install dies there. `actions/checkout`
does register a `safe.directory` entry (visible in the job log), but that is on
the host: different user, different `HOME`, and a different path (`/work`, not
`/home/runner/work/march/march`). None of it reaches the container.

opam swallows git's stderr, so the log never prints `detected dubious
ownership` verbatim — the attribution is from the exit code plus the
root-in-a-bind-mount context, not a quoted git message.

**Fix applied** in `.github/workflows/build.yml`, one line before the opam
calls in the Alpine block:

```
git config --global --add safe.directory /work
```

## Why this stays open

The fix is **unverified**. It cannot be reproduced or tested locally (no arm64
Alpine runner, and Docker Desktop's bind mounts do not reproduce the host uid
mismatch), so the next nightly or release run is the first real test. Two
things must still be seen before this item closes:

1. the aarch64 leg getting past `opam install` and through `dune build`, and
2. a published archive whose `bin/march` and `bin/forge` are non-empty.

A further hazard is visible in the same log: installing `ocaml-compiler.5.3.0`
under QEMU took **52 minutes** (04:57 → 05:49) before the leg even reached the
failure. Even with the git fix, this leg is very slow and is a plausible future
timeout; caching the container's opam root, or moving to a native arm64 runner,
is worth considering separately.

## Acceptance

A `linux-aarch64` archive whose `bin/march` and `bin/forge` are present,
non-empty, and executable; and a deliberately broken build leg fails the job
rather than publishing.

## Note on the currently-published assets

v0.3.0 and v0.2.0 both carry the broken aarch64 asset. The guard prevents
recurrence but does not repair what is already published — that needs the
underlying build fixed and the asset replaced.
