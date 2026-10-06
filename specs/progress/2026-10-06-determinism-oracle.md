# A5: determinism oracle (`scripts/determinism-oracle.sh`, `--dump-impl-hashes`, CI `determinism`)

**Date:** 2026-10-06
**Plan:** [`plans/incremental-codegen-cas-plan.md`](../plans/incremental-codegen-cas-plan.md) §10 (A5).
**Feeds:** B1 (deterministic symbols) uses this as its acceptance check; §12's memo layer
uses it to audit module-level state leaking between queries.

## What landed

- **`--dump-impl-hashes`** (`bin/flags.ml`, `bin/main.ml` `write_impl_hashes`). With
  `--emit-llvm` or `--compile` it writes `<file>.hashes` beside the output: one
  `symbol<TAB>impl_hash<TAB>sig_hash` line per post-TIR definition, sorted by symbol, taken
  straight from the `Cas.hashed_def` records `Pipeline.hash_module` already produces for the
  CAS key. No new hash is computed. Type definitions are listed too, prefixed `type:`, since
  their hashes fold into every function that mentions them. The `--emit-llvm` branch
  previously called `hash_module` inline for the hot-reload map; it now binds the result once
  and both uses read it.
- **`scripts/determinism-oracle.sh [--corpus small|all] [--self-test] [-j N] [-w DIR]`.** For
  every program in `ir-oracle.sh`'s corpus (`test/native`, `test/snapshots/src`, `bench`;
  `small` is the snapshots only) it runs `--emit-llvm --dump-impl-hashes` four times, cold
  then warm under private `HOME` A from cwd X, cold then warm under private `HOME` B from cwd
  Y, and demands byte-identical `.ll` and `.hashes` across all four. Each program gets its own
  two HOMEs and two cwds so `xargs -P` workers never share cache state and "cold" never
  depends on scheduling. A failure names the program, the condition pair, the file and the
  first differing line. Negative fixtures that fail under all four conditions are `SKIP`; a
  program that compiles under some conditions but not others is a `FAIL` (that is also
  nondeterminism). A run that emits fewer than 10 (`small`) / 100 (`all`) programs exits 2
  as vacuous, like `ir-oracle`.
- **The stdlib is pinned to the source tree** (`MARCH_STDLIB=$ROOT/stdlib` unless already
  set). From `_build/default/bin` the compiler resolves `_build/default/stdlib` first, a
  copy that a targeted `dune build bin/main.exe` leaves stale after a checkout and that any
  later full build restages. During validation one full run straddled such a restage
  (`scripts/run-tests.sh -q compiler` in the same worktree): `bench/dataframe_bench` condition 4
  parsed the new bytes, got a second `stdlib_ast_*` key in its HOME and +5 on every `$apply$`
  counter, and the oracle reported it as drift. The worker now fails a program whose HOME
  holds more than one `stdlib_ast_*` key with a message naming this cause, since two keys
  under one compiler and one directory can only mean the stdlib bytes changed mid-run.
- **Nothing is normalised.** The IR embeds no path (checked by grepping a `.ll` written from
  a relative and from an absolute source path for the cwd and the source path), the
  `.hashes` file is symbol and hex only, and the CAS store location (`<cwd>/.march/cas`)
  is not an output. Any difference, including a future path-embedding change, is a finding.
- **`--self-test`** copies `stdlib/`, inserts one throwaway `pfn` with a lambda before
  `List.map`, points conditions 3/4 at the copy via `MARCH_STDLIB`
  (`MARCH_DET_PERTURB_STDLIB` is the hook) and requires the oracle to report `FAIL` on
  `closure_hof`. The counters (`$lam<n>`, `$apply$<n>`, `%$t<n>`) shift, so both the `.ll`
  and the `.hashes` differ. A green self-test exits 1: the oracle would be vacuous.
- **CI job `determinism`** (ubuntu only, `needs: [ocaml-build]`, no OCaml toolchain; runs
  the prebuilt exe like `cross-linux-oracle`): self-test first, then `--corpus all`.

## Red-then-green record

Both drift fixes (PR #805 cold/warm stdlib cache → identical TIR; PR #807 which filed the
post-TIR-hash todo) were already on `main` when this started, so the red proof came from two
sources:

1. **The known drift, on a pre-#805 compiler.** A detached worktree at `d441bec17` (the
   first parent of #805's merge) with only the `--dump-impl-hashes` patch applied, run through
   the oracle on the `small` corpus via `MARCH_ORACLE_EXE`. Result: RED on exactly
   `examples_topology_app`, condition pair (1,2) (cold vs warm `HOME` A), first differing IR
   line `@$Clo_$lam2086$1570$static_clo = …`; 1808 of 2136 hash lines and 69062 IR lines
   differ. Conditions 1 and 3 (both cold) are identical, as are 2 and 4 (both warm): the
   drift is cache warmth, exactly #805's diagnosis. The other 28 programs (the snapshot
   corpus) are GREEN on that same compiler, which is why topology_app had to join the corpus:
   ir-oracle's programs never link `Topology.actor_role`'s generic `Pid(a)`.
2. **The deliberate perturbation** (`--self-test`): RED, `conditions (1,3) .ll differ; first:
   <   %f_i18454.addr = alloca ptr`.

Green on this tree (`origin/main` at `eea23d6dc` plus this branch):
`small`: 29/29 OK, 0 skipped. `all`: 412 OK, 0 failed, 5 skipped (the three
`bench/http_get*` and `native/js_dom_timeout_callback`, `native/vault_churn_leak_probe`, which
fail to compile under every condition).

## The post-TIR-hash todo

`specs/todos/2026-10-05-post-tir-hash-depends-on-home-cache.md` asked for a cold-then-warm
compile asserting the same post-TIR `src=` digest. Its own repro (`--compile --opt 2
--topology`, three runs in one fresh `HOME`) prints identical `src=` on this tree, and the
oracle's topology_app leg is the regression test it asked for, so it moves to `progress/`
with a resolution note. `2026-10-01-cold-stdlib-cache-changes-specializations.md` stays
open: its `--emit-llvm` acceptance is met, but its `.hcr_manifest` acceptance and the
forge test's warm-up compile were not checked here.

## Cost

A warm `--emit-llvm` of a snapshot program is ~2 s, a cold one ~3 s (the stdlib parse and
typecheck). Measured over `--corpus all` on the M-series dev box (load ~70-100 from other
sessions, so a pessimistic figure): 5465 CPU-s for 417 programs, 13 CPU-s per program,
24 min wall at `-j 10`. `small` (29 programs) is ~45 s at `-j 14`, ~2 min at `-j 8`. The CI
job's timeout (70 min job, 60 min step) assumes the 4-vCPU runner is up to ~2.5x slower per
core; tighten it after a few runs. It adds ~40 Linux job-minutes to a CI run; if that is too
much for the free-plan budget, run `--corpus small` on PRs and `all` in nightly.
