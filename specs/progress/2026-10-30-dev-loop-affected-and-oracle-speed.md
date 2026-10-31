# Tighter local dev loop: affected-suite selection, parallel oracles, cached baselines

Logged 2026-10-30. Local loops were re-running the whole suite and recording a
fresh oracle baseline for changes that could reach a fraction of either.

## What landed

- **`scripts/affected.sh`** maps the paths changed since the merge-base with
  `origin/main` (committed, uncommitted and untracked) to `run-tests.sh` suites,
  dune aliases, oracles and check scripts, prints why each file selected what, and
  runs the plan with `--run`. Dune cannot do this: every alcotest runner links
  nearly every `march_*` library (`test/dune`), so any lib edit relinks all of
  them. Test modules (`test/<m>.ml`) resolve through the `test/dune` stanza whose
  `(modules ...)` lists them. **Any path without a rule selects FULL**, so the
  failure mode is over-testing, never a silent hole.
- **`scripts/test-affected.sh`** pins the mapping in both directions (narrow plans
  stay narrow, unknown paths go FULL); runs in doc-lint. Verified red by disabling
  the `lsp/*` rule.
- **`ir-oracle.sh` and `refine-oracle.sh` are parallel** (`MARCH_ORACLE_JOBS`,
  default CPU count), following `types-oracle.sh`: per-fixture output parts, a
  sorted manifest, one serial warm-up compile so the private `HOME`'s stdlib blob
  is written once, and `MARCH_STDLIB` pinned to the source tree against a
  concurrent restage.
  - `ir-oracle` now runs under a private `HOME` inside `<dir>` (it used the real
    one, which CLAUDE.md already warned against).
  - `refine-oracle` runs every fixture from its own fresh cwd, so the compile-path
    CAS and the VC cache (`<cwd>/.march/cas/{artifacts-v2,vc}`) are cold for every
    fixture. The serial version shared one cache in the repo root that warmed across
    fixtures in corpus order. **Baselines recorded by the old script are not
    comparable to the new one; re-record.** It also gains `MARCH_ORACLE_EXE`.
- **`scripts/oracle-base.sh ir|refine|types|all [--base REF] [--refresh]`** records
  the baseline at the merge-base once (a `git archive` export, built with the shared
  dune cache, recorded with THIS tree's oracle script) and caches only the manifests
  under `~/.cache/march-oracle-base/<sha>-<script-hash>/<oracle>/`. Each later
  iteration runs only the check half. A `mkdir` lock serialises two sessions
  recording the same base.

## Measurements (2026-10-30, 14 cores, host load 11-22)

| Oracle | Serial | Parallel (14 jobs) | Equivalence |
|---|---|---|---|
| `ir-oracle` (502 programs) | ~255 programs in 30 min, killed (~60 min projected) | 5m02s | 255/255 finished programs byte-identical once the embedded work-dir path (and its string lengths) is normalised |
| `refine-oracle` (553 fixtures) | 12m35s | 2m42s | 552/553 identical; `stdlib_prelude` differs, see below |

`oracle-base.sh ir refine types` against a base with the same compiler source:
all three IDENTICAL (24m12s cold, i.e. recording all three base baselines plus the
checks). After appending a division and changing a string literal in one
`test/native` fixture, a warm run (checks only) reported all three CHANGED, every
differing line attributed to that fixture (11m55s).

Findings from the equivalence checks:

- **`ir-oracle` hashes depended on `<dir>`.** The `.ll` embeds the source path as
  given (panic locations, string literals and their lengths), and the old script
  compiled by absolute path, so a baseline could only be checked from the same
  directory. The new script compiles by relative path from inside the work dir;
  verified identical from two different directories.
- **`refine-oracle`'s `stdlib_prelude` lines were an artifact.** Unpinned, the
  compiler loads the prelude from the staged `_build/default/stdlib` copy and the
  fixture `stdlib/prelude.march` is a second copy at a different path, so the
  checker reported 11 `overlapping_impl` errors of the prelude against itself
  (and a shortened refinement report). `types-oracle`'s baseline carried the same
  11 lines. The fixture path and the loaded prelude have to be the same string:
  both oracles now run with `MARCH_STDLIB=stdlib`, relative, through the cwd's
  symlink to the source tree (which also keeps the pin against a concurrent
  restage). 0 overlaps that way; output for the other fixtures is unchanged.
- **`xargs -I{}` silently truncated a sweep.** macOS xargs refuses a `-I` line
  over 255 bytes ("command line cannot be assembled, too long") and stops; with a
  long `<dir>` the first `oracle-base.sh` run recorded an ir baseline of 175 of
  502 programs, which the `emitted >= 100` vacuity guard let through.
  `types-oracle.sh` had the same latent bug. All three now use `xargs -0 -n 1`,
  fail on a non-zero xargs status, and require exactly one result per fixture.
- **`types-oracle` output depended on VC-cache state.** It ran every fixture from
  the repo root, sharing (and never clearing) `.march/cas/vc`. A cached VC replays
  a stored z3 counterexample, so `reject/t351`'s diagnostic read `h = 4` cold and
  `h = 3` warm: the first `oracle-base.sh types` run reported a change between two
  identical compilers. It now runs each fixture from its own fresh cwd, like
  `refine-oracle`.
- **Output must not depend on where the tree lives.** A first fresh-cwd attempt
  passed absolute paths, and two identical compilers then differed in 60 core-AST
  hashes and 8 diagnostic lines: rendered headers pad with dashes to the path's
  length (`-- WARNING ----` vs `-- WARNING --`), and derive-generated spans hash
  the path (`"start_col":635640932` vs `166492170`), so stripping the prefix
  afterwards is not enough. Both oracles now symlink the corpus roots into the
  fresh cwd and pass the same relative path as a repo-root run; verified
  byte-identical to a repo-root run, and identical between two different cwds.

## Not done

- Parallelising alcotest groups inside `run_codegen` (the slowest suite). Its
  cases share `/tmp` paths and the CAS; doing it needs those isolated first.
