# Every linux-aarch64 release archive ships with an empty `bin/` — RESOLVED 2026-08-31

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

## Why this stayed open (superseded by the section below)

The fix was **unverified** at the time of writing. It cannot be reproduced or tested locally (no arm64
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

## Resolution 2026-08-31: native arm64 runner, and the two real build errors

Three separate defects had to be fixed, stacked behind one another. Only the
first was known when this item was filed; the other two had never been
*reachable*, because no build had ever got far enough to hit them.

### 1. `git ls-files` exit 128 (fixed earlier, see the update above)

`git config --global --add safe.directory /work` in the Alpine block. Verified
working here — the leg now installs its opam deps and reaches `dune build`.

### 2. The leg moved off QEMU onto a native arm64 runner

`ubuntu-24.04-arm` is available to this repo (public repo, free-plan org;
confirmed on a live run: image `ubuntu24-arm64/20260823.101`, `uname -m` =
`aarch64`, docker server arch `arm64`). The matrix entry now uses it.

The Alpine container **stays** — it is what makes the artifact musl — but on an
arm64 host it is a plain native `docker run`, so `docker/setup-qemu-action` and
`--platform linux/arm64` are both gone. They only ever made sense together with
an x86_64 `os:`; the workflow now says so in a comment.

The `cross: true` matrix flag was renamed `alpine: true`. Nothing about this
leg is a cross-compile any more; what the flag actually selects, and always
actually selected, is "built inside the container" versus "built on the runner
host". The `!matrix.cross` → `!matrix.alpine` gates keep the exact same
partition (host legs get `opam-deps` and the native build steps; the container
leg does not), and `Install musl toolchain` is now additionally skipped on this
leg, where installing musl-tools on the host was pure waste.

**Effect on wall-clock:** installing `ocaml-compiler.5.3.0` alone took **52
minutes** under emulation (nightly 33358635235). The whole leg — apk, blake3
from source, opam init, a from-source 5.3.0 switch, every opam dep, and
`dune build` of both binaries — now takes **4m51s** (run 33410265258).

### 3. `LLVM_MAJOR_VERSION >= 19` was the wrong version boundary

`lib/jit/jit_orc_stubs.c` guarded the ThreadSafeContext API change at LLVM 19.
The change actually landed in LLVM **21**: `LLVMOrcThreadSafeContextGetContext`
survives through 20, and `LLVMOrcCreateNewThreadSafeContextFromLLVMContext`
replaces it in 21. So the guard was wrong for exactly LLVM 19 and 20, where it
takes the 21+ branch and fails to compile.

No leg had ever exercised a 19/20 toolchain: macOS gets Homebrew llvm (21+),
`ubuntu-24.04`'s `llvm-dev` is 18, and Alpine 3.21's `llvm19-dev` is the one
19 — on the leg that had never reached `dune build`. Moving to a native runner
is what surfaced it.

Reproduced locally before fixing, and confirmed fixed, by syntax-only
compilation against real headers at each version:

```
                        before        after
LLVM_MAJOR_VERSION=18   0 errors      0 errors
LLVM_MAJOR_VERSION=19   2 errors      0 errors   <- Alpine 3.21
LLVM_MAJOR_VERSION=20   2 errors      0 errors
LLVM_MAJOR_VERSION=21   0 errors      0 errors
LLVM_MAJOR_VERSION=22   0 errors      0 errors
```

(19 and 20 are both checked against llvm@20 headers — the two releases share
the relevant API shape, and 20 is the newest that still has the pre-21 form.)

### 4. libblake3 was built without NEON on aarch64

The Alpine block built blake3 from "portable C only", dropping the x86 `.S`
files — and also, silently, `blake3_neon.c`. But `blake3_dispatch.c` turns
`BLAKE3_USE_NEON` **on** by default for aarch64 and then calls
`blake3_hash_many_neon`, so the shared object linked cleanly and every
executable that used it died with `undefined reference to blake3_hash_many_neon`.
`blake3_neon.c` is now compiled in, matching what the macOS leg already did.

## Acceptance — met

A `linux-aarch64` archive whose `bin/march` and `bin/forge` are present,
non-empty, and executable; and a deliberately broken build leg fails the job
rather than publishing.

Verified on run 33410265258, artifact `march-probe-linux-aarch64.tar.gz`
(12.8 MB, against 692 KB for the empty v0.3.0 one):

```
bin/march  24,113,976 bytes  ELF 64-bit LSB pie executable, ARM aarch64,
                             interpreter /lib/ld-musl-aarch64.so.1
bin/forge  16,457,880 bytes  (same)
```

Both were then actually **run**, in a native arm64 `alpine:3.21` container on
an Apple Silicon host: `march --version` → `march 0.3.0`, `forge --version` →
`0.3.0`, and a hello-world module interpreted correctly (`hello from aarch64`).
This is the first working ARM Linux build artifact the project has produced.

## Three things found while verifying, all pre-existing, all still open

None of these were introduced by this change and none block the acceptance
above, but they were observed directly and should not be lost:

1. **Neither Linux leg is actually statically linked**, despite `static: true`.
   Both `linux-x86_64` and `linux-aarch64` come out `dynamically linked` with
   `NEEDED` entries for `libLLVM.so.{18,19}.1`, `libblake3.so`, `libz`,
   `libzstd` and brotli. `static: true` today gates only the `musl-tools`
   install; nothing passes `-static` (the `OCAMLPARAM='_,ccopt=-static'` in the
   old spec snippet is gone from the workflow). On a bare `alpine:3.21` the
   aarch64 binary fails to start with a wall of `symbol not found` relocations;
   it runs once llvm19-libs/brotli/zstd/blake3 are installed. Since x86_64 has
   the same shape, this is a general release-portability problem, not an ARM
   one — filed as its own todo.
2. **`strip` silently does nothing on the container leg.** `_dist` is written
   by root inside the container as mode `-r-xr-xr-x`; the host `strip` runs as
   uid 1001, cannot write them, and the failure is eaten by `|| true` — the
   same swallowing pattern this item was originally filed about. The step
   reports success and the binaries ship `not stripped` with debug_info (hence
   24 MB).
3. **The bundled C runtime does not compile on musl**, so `march --compile`
   from the aarch64 prebuilt fails: `march_runtime.c:27: fatal error:
   'execinfo.h' file not found`. `execinfo.h` is a glibc extension. Confirmed
   to be the *only* remaining blocker once zlib/openssl/zstd dev headers are
   present. The interpreter is unaffected. Filed as its own todo.

## Note on the currently-published assets

v0.3.0 and v0.2.0 both carry the broken aarch64 asset. The guard prevents
recurrence but does not repair what is already published — that needs the
underlying build fixed and the asset replaced.
