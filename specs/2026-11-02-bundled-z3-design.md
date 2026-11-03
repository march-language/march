# Bundled z3: refinements that work on a fresh install

Status: design, 2026-11-02. Road to 1.0, Pillar 4 / Phase 2 ("z3 bundled and pinned, with an
`rlimit` and a loud missing-z3 error"); decision 4 of 2026-09-29 ("ships in the toolchain").

## Intent

Someone who installs a March release and writes a refinement gets it checked, with nothing
else to install. Every machine proves with the same z3 and the same limit, so a verdict
does not depend on the platform, the package manager or the load on the machine. When
z3 is missing or broken, the user is told so, with install instructions, instead of every
obligation quietly coming back "solver-undecided".

## Today

- `Solver.find_z3` (`lib/refine/solver.ml`) tries `MARCH_Z3`, then `PATH`. Nothing else.
- Release archives (`.github/workflows/build.yml`) hold `bin/march`, `bin/forge`, `stdlib/`
  and `runtime/`, and no z3. CI installs whatever brew or apt ships
  (`.github/actions/march-setup/action.yml`): 4.16 on macOS, 4.8.12 on Ubuntu.
- Each query runs under a wall-clock `:timeout` (3000 ms, and 1000 ms for stage-2
  queries: `stage2_timeout_ms` in `lib/refine/refine.ml`). A loaded machine can turn a
  provable obligation into `unknown`, which under `cap verified` turns a build red.
  Because of that, `unknown` is never cached.
- A missing z3 is not reported. The only sign is that every obligation is
  `solver-undecided`. The build cache tags only whether z3 is absent (`z3_cas_tag`,
  `bin/main.ml`); the VC cache key (`lib/refine/vc_cache.ml`) has no z3 version. (The
  in-memory stage-2 negative cache in `lib/refine/refine.ml` does key on the z3 path.)

## Goals

1. **A pinned z3 ships in every release archive**, for the three tier-1 platforms
   (darwin-arm64, linux-x86_64, linux-aarch64), with its MIT license.
2. **One lookup, used by everything:** `MARCH_Z3` first (an explicit override), then the z3
   next to the running `march`, then `PATH`. The CLI, `forge` (which runs `march`) and the editor's
   background check (which runs `march --check`) all get it the same way.
3. **CI uses the pinned version on every platform**, not the distro's.
4. **`rlimit` replaces the wall-clock timeout** as the limit on a query (owner, 2026-11-02).
   A verdict is then a function of the query, the z3 version and the limit.
5. **The z3 version and the `rlimit` are part of the cache keys**, both the VC cache and the
   build (CAS) cache, so an upgrade can never replay a stale verdict.
6. **Missing or broken z3 is loud, and the build still succeeds** (owner, 2026-11-02): an
   ordinary compile or check builds and prints one warning with install instructions.
   Under `cap verified`, where an undischarged obligation is already an error, the error
   says z3 is the reason.

## Non-goals

- The editor: turning refinement diagnostics on by default (`MARCH_LSP_REFINE=1` today),
  shipping `march-lsp` in the archive, LSP install work. Separate project (owner,
  2026-11-02). This design only makes sure the editor's `march --check` finds the bundled
  z3, which goal 2 gives it for free.
- Tier-2/3 platforms (Intel macOS, Windows, WASM). They keep the `MARCH_Z3`/`PATH` lookup.
- Other solvers, or linking z3 as a library.
- Changing what refinements check, or the definite-failure-only default.

## Anti-goals

- A proof that passes on a developer's laptop and fails in CI (or the reverse) because of
  load or z3 version. That is what this exists to remove.
- An install that "works" but silently checks nothing.
- Breaking the static Linux release: `march` on Linux is a static musl binary that runs on
  any distribution, and the z3 next to it must run everywhere `march` does.
- A z3 on `PATH` shadowed by ours: the bundled z3 must not land on the user's `PATH`.

## Decisions

### Owner's

- Bundle z3; it is not a separate component (2026-09-29).
- `rlimit` replaces the 3-second wall clock (2026-11-02).
- When z3 is missing or broken, build and print install instructions (2026-11-02).
- The editor is out of scope (2026-11-02).
- **Compile-time budget** (2026-11-02): z3 is reset before every query, so a verdict depends
  only on the query, the z3 version and the limit. The default `rlimit` is accepted only if
  the refinecheck suite and the stdlib build get no more than about 25% slower than today; if
  10x the hardest proof would exceed that, use a lower multiplier, as long as nothing that
  proves today stops proving.
- **Cross-platform agreement is enforced** (2026-11-02): a CI job proves the whole corpus
  (test, conformance and stdlib obligations) with the pinned z3 on all three tier-1
  platforms and fails on any verdict that differs. It extends the refinement determinism
  job Phase 3 plans. The platform enters the cache key for cached `rlimit`-unknown verdicts.

### Mine (the builder may revisit, saying why)

- **Build z3 from source in release CI, statically on Linux**, inside the same Alpine
  containers that build `march`, and cache the result keyed on the z3 version and the
  build recipe. z3's official Linux downloads link glibc and would not run everywhere the
  static `march` does. macOS builds it natively (arm64). Cost: a cold z3 build is a long
  CI step, so the cache matters; expect roughly 30-40 MB more per archive.
- **Pin a current 4.16.x release** (macOS CI is already on 4.16), in one file that CI,
  release builds and the version check all read. Bumping z3 means editing that file.
- **Archive layout:** `libexec/z3` and `licenses/z3-LICENSE.txt`, not `bin/z3`, so putting
  the toolchain's `bin/` on `PATH` does not shadow a user's own z3. The exe-relative lookup
  mirrors how `bin/toolchain.ml` finds `stdlib/` and `runtime/`. It also finds z3 through
  forge's `~/.march/current` symlink, since it resolves the real exe path.
- **A z3 of a different version from `MARCH_Z3`/`PATH` is used, with a warning** naming
  both versions, not refused. People who manage z3 themselves keep working. The version
  goes into the cache keys either way.
- **A wall-clock backstop stays, but only for hangs:** a long limit (about 60 s per query)
  that never fires on a healthy solver. If it fires, the report says "z3 stopped
  responding", not "unproved", and the result is not cached.
- **Choosing the default `rlimit`:** with the pinned z3 and a reset per query, measure the
  `rlimit` each obligation in the test corpus, the conformance corpus and the stdlib actually
  uses, and set the default about 10x above the largest, within the owner's time budget. The
  measurement goes in `specs/progress/` with the number.
- **Stage-2 queries** (the 1000 ms ones) get their own, smaller `rlimit`, chosen the same
  way.
- **`unknown` becomes cacheable** when it came from the `rlimit` (deterministic), and stays
  uncached when it came from the backstop, a crash or a malformed query.
- **A per-project override** in `forge.toml` (and a `--refine-rlimit` flag) for a known-hard
  proof. The value is part of the cache key.
- **"Broken" means:** z3 fails to start, exits or stops answering mid-run, or
  `z3 --version` doesn't parse. A version mismatch is a warning, not "broken".
- **The diagnostic** is one warning per run, not per obligation. It names the path tried
  (or "no z3 found next to `march`, in `MARCH_Z3` or on `PATH`"), the reason, and the fix:
  reinstall the toolchain (`forge toolchain install …`), or set `MARCH_Z3` to a z3 of the
  pinned version. It has a stable error code and an `--explain` page.
- **Lookup order puts `MARCH_Z3` first**, so the diagnostic's "set `MARCH_Z3`" fix works on
  a bundled install, people who manage z3 themselves can override it, and tests can point a
  packaged `march` at a fake z3.
- **When the warning fires:** only on a run that has at least one obligation to send to z3.
  A program with no refinements never probes z3 and never warns, so hello-world on a
  tier-2 platform or a dev build stays quiet. A CAS cache hit replays the build's stored
  diagnostics, so the warning is not lost on a cached build.
- **The z3 version enters the build key** only through the probe, which is cached per z3
  path and mtime; a program with no obligations keys exactly as today.
- **Source installs** (`dune install`, opam) are in scope only as the fallback: no
  `libexec/z3`, so they use `MARCH_Z3`/`PATH` and get the warning if neither has z3. The
  install docs say to install the pinned z3.
- **The build stays fast:** the version is probed once per process, and cached per z3 path
  and mtime if the probe shows up in compile time.

## Constraints

- The Linux release binaries stay static (`build.yml`'s scratch-image checks must stay
  green), and `release.yml`'s smoke compile of each archive gains a refinement check that
  needs z3.
- `scripts/check-docs.sh`, `scripts/determinism-oracle.sh` and the refine oracle must stay
  green; the determinism oracle must not see the z3 path (only its version) in any key.
- `scripts/run-tests.sh refinecheck` must still fail loudly when z3 is missing.
- Docs: the refinement chapter of `specs/lang/` and `specs/lang/claim-refinements.md` state
  the pinned version, the lookup order and the limit; `docs/` is regenerated from them.
  CHANGELOG entries under Added (bundled z3) and Changed (`rlimit`, cache keys).

## Left to the builder

- The z3 build recipe (cmake flags, static link details on musl and macOS) and the CI cache
  mechanics.
- Where the pin file lives and its format.
- How the version probe and the diagnostic are wired into `Solver`/`Refine`.
- The exact default `rlimit` values, from the measurement.
- Test design, including a fake z3 (a script that crashes, hangs or reports a wrong version)
  to pin each diagnostic.
