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

## Update 2026-08-31 (later): safe.directory confirmed, two more failures behind it

Dispatched Nightly manually on the fix branch — run 33393710751, job
99493165055. The `safe.directory` fix **works**: no `git ls-files` exit 128
anywhere in the log, `opam install` completed, and the leg ran 101 minutes (vs
55) before failing further downstream, inside `dune build`. `publish` was
skipped, so no release was cut.

Two more failures, independent of each other and of the git one. Both are now
fixed on the same branch:

**(a) blake3 built without NEON.**

```
libblake3.so: undefined reference to `blake3_hash_many_neon'
```

The Alpine block compiled only `blake3.c blake3_dispatch.c blake3_portable.c`
under the comment "portable C only — no x86 SIMD on aarch64". Dropping the x86
SIMD units is right; dropping `blake3_neon.c` is not. NEON is baseline on
aarch64, so `blake3_dispatch.c` references `blake3_hash_many_neon`
unconditionally with no runtime check to skip it. The resulting `.so` links
fine and breaks every consumer. The macOS leg 40 lines below already compiled
`blake3_neon.c`; the aarch64 one now does too.

**(b) `lib/jit/jit_orc_stubs.c` cannot compile against LLVM 19 or 20.**

```
error: implicit declaration of function 'LLVMOrcCreateNewThreadSafeContextFromLLVMContext'
```

The version guard was `LLVM_MAJOR_VERSION >= 19`. The real threshold is **21**.
Verified directly against `llvm/include/llvm-c/Orc.h` on the upstream release
branches:

| LLVM | `…ThreadSafeContextGetContext` | `…CreateNewThreadSafeContextFromLLVMContext` |
|------|-------------------------------|----------------------------------------------|
| 18   | present                       | absent                                        |
| 19   | present                       | absent                                        |
| 20   | present                       | absent                                        |
| 21   | absent                        | present                                       |

So 19 and 20 took the newer branch and referenced a function that does not
exist yet. **This is not aarch64-specific** — any build against LLVM 19 or 20
on any platform hits it. It survived this long because CI only ever built
against LLVM 18 (Ubuntu) and 22 (Homebrew), one either side of the broken
range; the Alpine `llvm19-dev` leg is the first build to land inside it.

Guard corrected to `>= 21`, with the branch comments and `detect_llvm.sh`'s
header comment fixed to match. Local `dune build` and all 24 `test_jit` cases
still pass on LLVM 22 — but note that only re-exercises the `>= 21` path, the
one CI already covered. The 19/20 path is verified by the upstream header
inspection above, not by a compile; no LLVM 19 or 20 toolchain is available
locally to build against.

## Why this stays open

The blake3 and LLVM-guard fixes are **unverified against the real leg**. It cannot be reproduced or tested locally (no arm64
Alpine runner, and Docker Desktop's bind mounts do not reproduce the host uid
mismatch), so the next nightly or release run is the first real test. Two
things must still be seen before this item closes:

1. the aarch64 leg getting through `dune build` (past `opam install` is now
   confirmed), and
2. a published archive whose `bin/march` and `bin/forge` are non-empty.

There may of course be a fourth failure behind these two; nothing has ever
built this leg to completion, so each fix only reveals the next error.

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
