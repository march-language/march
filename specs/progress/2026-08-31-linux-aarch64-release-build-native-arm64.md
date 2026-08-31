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

## This leg IS reproducible locally — natively, in minutes

The claim earlier in this file that it "cannot be diagnosed from here without an
arm64 runner" is wrong, and cost a 100-minute CI round trip per attempt. This
Mac is arm64, so `alpine:3.21` runs **natively** under Docker — no QEMU, no
emulation penalty — with the exact toolchain the CI leg uses
(`llvm19-dev` = LLVM 19.1.4, gcc 14 aarch64-alpine-linux-musl):

```bash
open -a Docker                       # daemon is not running by default
docker run --rm --platform linux/arm64 -v "$PWD:/work" -w /work alpine:3.21 sh -c '...'
```

Both fixes below were verified this way in under two minutes each, with a RED
control proving the check actually fires before trusting the GREEN. Note the
bind-mount ownership bug (the `safe.directory` one) does **not** reproduce here
— Docker Desktop's virtiofs maps ownership to the container user, so that fix
still rests on the CI run.

**Test A — blake3 NEON.** The first attempt at a control was worthless: it
linked a `int main(void){return 0;}` that never references blake3, so the
linker had no reason to resolve anything and the broken `.so` "passed". With a
program that actually calls `blake3_hasher_update`:

```
A1 (portable-only .so):     undefined reference to `blake3_hash_many_neon'   <- exact CI error
A2 (+ blake3_neon.c):       linked, ran, correct digest
```

**Test B — the LLVM guard**, compiled against real LLVM 19.1.4 headers:

```
B1 (pre-fix guard >= 19):   error: implicit declaration of function
                            'LLVMOrcCreateNewThreadSafeContextFromLLVMContext'  <- exact CI error
B2 (fixed guard >= 21):     compiled clean
```

So the LLVM fix is now compile-verified against LLVM 19, not merely inferred
from reading upstream headers.

## Why this stayed open (superseded — see the resolution below)

*Everything in this section was true when written and is kept for the record.
All three conditions it lists were met on 2026-08-31.*

The blake3 and LLVM-guard fixes are verified in isolation but
**unverified end to end against the real leg**. It cannot be reproduced or tested locally (no arm64
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

## Resolution 2026-08-31: native arm64 runner, verified end to end

The "fourth failure behind these two" the section above warned about did not
materialise. With the three fixes in place — `safe.directory`, the LLVM 21
guard, and blake3 NEON — the leg builds clean.

### The leg moved off QEMU onto a native arm64 runner

`ubuntu-24.04-arm` is available to this repo (public repo, free-plan org), and
that was confirmed on a live run rather than assumed: runner image
`ubuntu24-arm64/20260823.101`, `uname -m` = `aarch64`, docker server arch
`arm64`.

The Alpine container **stays** — it is what makes the artifact musl — but on an
arm64 host it is a plain native `docker run`, so `docker/setup-qemu-action` and
`--platform linux/arm64` are both gone. They only ever made sense together with
an x86_64 `os:`; the workflow now carries a comment saying so, because
reintroducing either one alone would silently re-emulate.

The `cross: true` matrix flag became `alpine: true`. Nothing about this leg is
a cross-compile any more; what the flag actually selects — and always actually
selected — is "built inside the container" versus "built on the runner host".
The `!matrix.cross` → `!matrix.alpine` gates preserve the exact same partition
(host legs get `opam-deps` and the native build steps, the container leg does
not). `Install musl toolchain` is now additionally skipped on this leg, where
installing musl-tools on the host was pure waste.

**Wall-clock.** Installing `ocaml-compiler.5.3.0` alone took **52 minutes**
under emulation. The whole leg — apk, blake3 from source, opam init, a
from-source 5.3.0 switch, every opam dep, and `dune build` of both binaries —
now takes **4m51s** (run 33410265258). The 100-minute CI round trip per attempt
that made this item so expensive to work on is gone.

This also removes the motivation for caching the container's opam root across
the docker-run boundary: the switch is cheap to rebuild natively.

## Acceptance — met

A `linux-aarch64` archive whose `bin/march` and `bin/forge` are present,
non-empty, and executable; and a deliberately broken build leg fails the job
rather than publishing.

Verified on run 33410265258 (all three legs green, so the LLVM guard change
regressed neither x86_64 nor macOS), artifact `march-probe-linux-aarch64.tar.gz`
— **12.8 MB**, against 692 KB for the empty v0.3.0 one:

```
bin/march  24,113,976 bytes  ELF 64-bit LSB pie executable, ARM aarch64,
                             interpreter /lib/ld-musl-aarch64.so.1
bin/forge  16,457,880 bytes  (same)
```

Both binaries were then actually **run** — not merely inspected — in a native
arm64 `alpine:3.21` container on an Apple Silicon host, the same local-repro
technique recorded above: `march --version` → `march 0.3.0`, `forge --version`
→ `0.3.0`, and a hello-world module interpreted correctly
(`hello from aarch64`).

This is the first working ARM Linux build artifact the project has produced.

Verification deliberately did **not** go through a `nightly.yml` dispatch: that
publishes a public release tag, and `nightly.yml` hardcodes `ref: main`, so it
would have built main's source rather than the branch's. A temporary workflow
called `build.yml` directly instead, and was removed afterwards. (The
`TEMP(test scaffold)` edit to `nightly.yml` on the fix branch solves the same
problem a different way and is still marked REVERT BEFORE MERGE.)

## Three things found while verifying — all pre-existing, all still open

None of these were introduced by this work and none block the acceptance above,
but they were observed directly and should not be lost.

1. **Neither Linux leg is actually statically linked**, despite `static: true`.
   Both come out `dynamically linked` with `NEEDED` entries for
   `libLLVM.so.{18,19}.1`, `libblake3.so`, `libz`, `libzstd` and brotli —
   `libblake3.so` being one the workflow itself builds from source and that
   exists on no user's machine. On a bare `alpine:3.21` the aarch64 binary
   aborts with ~20 `symbol not found` relocations; it runs once those libraries
   are installed. `static: true` today gates only the `musl-tools` install.
   Since x86_64 has the identical shape and has shipped that way for two
   releases, this is a general release-portability problem, not an ARM one.
   → `specs/todos/2026-08-31-linux-release-binaries-are-not-static.md`

2. **`strip` silently does nothing on the container leg.** `_dist` is written
   by root inside the container as mode `-r-xr-xr-x`; the host `strip` runs as
   uid 1001, cannot write the files, and the failure is eaten by `|| true` —
   the same swallowing pattern this item was originally filed about. The step
   reports success and the binaries ship `not stripped` with debug_info, hence
   24 MB.

3. **The bundled C runtime does not compile on musl**, so `march --compile`
   from the aarch64 prebuilt fails at `march_runtime.c:27: fatal error:
   'execinfo.h' file not found`. `execinfo.h` is a glibc extension. Confirmed
   to be the *only* remaining blocker once zlib/openssl/zstd dev headers are
   present. The interpreter is unaffected — the prebuilt can interpret March
   but not compile it.
   → `specs/todos/2026-08-31-runtime-execinfo-h-breaks-musl-compile.md`

## Note on the currently-published assets

v0.3.0 and v0.2.0 both carry the broken aarch64 asset. The guard prevents
recurrence but does not repair what is already published — that needs the
underlying build fixed and the asset replaced.
