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

## Acceptance

A `linux-aarch64` archive whose `bin/march` and `bin/forge` are present,
non-empty, and executable; and a deliberately broken build leg fails the job
rather than publishing.

## Note on the currently-published assets

v0.3.0 and v0.2.0 both carry the broken aarch64 asset. The guard prevents
recurrence but does not repair what is already published — that needs the
underlying build fixed and the asset replaced.
