# CI and automation

What each workflow in this directory runs, when, and what a red one means.
The workflow files carry the detailed history (why a timeout is what it is,
which incident a check exists for); this page is the map.

**Runner budget.** The `march-language` org is on GitHub's free plan: at most
**20 concurrent Linux jobs and 5 concurrent macOS jobs across the whole org**.
One `CI` run asks for 29 jobs (23 Linux, 6 macOS), about 224 Linux and 57
macOS job-minutes, so runs from different PRs queue behind each other. What
costs queue time is job-minutes on each pool, not job count: splitting a job
only pays if the pieces add up to about the same minutes. On macOS they did not
(one 32 min `dune runtest` became 67 min across four shards), so macOS runs the
suite unsharded. Be most careful with macOS: 5 slots for the whole org.

## Workflows at a glance

| Workflow | Trigger | Purpose |
|---|---|---|
| [`ci.yml`](ci.yml) | every PR and push to `main`, **except Markdown-only changes** | The merge gate: tests, corpora, sanitizers, property/oracle checks. |
| [`doc-lint.yml`](doc-lint.yml) | every PR and push to `main` | Seconds-long doc and source-level checks, including on Markdown-only changes. |
| [`nightly.yml`](nightly.yml) | 00:00 UTC; manual | Publishes a `nightly-YYYYMMDD` prerelease when `main` is green and has moved. |
| [`release.yml`](release.yml) | push of a `v*` tag | Builds and publishes a versioned release. |
| [`build.yml`](build.yml) | called by nightly/release | Builds the three distributable archives. Not triggered on its own. |
| [`gen-stdlib-docs.yml`](gen-stdlib-docs.yml) | push to `main` touching `stdlib/**` | Regenerates the committed stdlib API pages and search index. |
| [`sync-docs-search-index.yml`](sync-docs-search-index.yml) | push to `main` touching `docs/**` | Regenerates the committed Pagefind index (`docs/pagefind/`). |
| [`deploy-pages.yml`](deploy-pages.yml) | push to `main` touching `docs/**` | Publishes the separately built site to `march-language.github.io`. |
| [`march-lean-dispatch.yml`](march-lean-dispatch.yml) | push to `main` touching the type corpus/checker | Tells the independent Lean re-checker (`march-lean`) to re-run. |
| [`cleanup-decision-graphs.yml`](cleanup-decision-graphs.yml) | PR closed | Deletes that PR's decision-graph PNGs. |

Shared setup lives in two composite actions:
[`../actions/march-setup`](../actions/march-setup/action.yml) (OCaml + cached
opam deps, the C libraries the runtime links, z3, optionally zig and the
linux/amd64 cross sysroot) and [`../actions/opam-deps`](../actions/opam-deps/action.yml)
(caches `~/.opam`, saving ~2.3 min per job).

## `ci.yml`: the merge gate

A change whose files are all `*.md` skips `ci.yml` entirely (`paths-ignore`);
nothing in it reads the repo's Markdown. Mix in any other file and it all runs.
`doc-lint.yml` still runs on those changes, since its checks are the ones that
read Markdown.

A newer push to a PR cancels that PR's older run (`concurrency`,
`cancel-in-progress`). Pushes to `main` never cancel each other, so every
`main` commit gets a verdict; the nightly gate reads those verdicts.

Every check is its own job so the critical path is the slowest job, not the
sum. There is no required-check list in branch protection; "green" means every
job below, plus `doc-lint`, passed.

```
test (ubuntu) × codegen | refinecheck | compiler | rest
test (macos, all)
two-node (ubuntu)
bench-gate (ubuntu)
conformance (ubuntu, macos)
sanitize-gate (ubuntu)
ocaml-build (ubuntu, macos) ─┬─ property-tests (per OS) × soundness | tir | rest ─┐
                             │                                                    └─ property-coverage
             ubuntu leg only ├─ cross-linux-oracle
                             └─ property-oracle × 8
```

| Job | What it checks | If it's red |
|---|---|---|
| `doc-lint` (in `doc-lint.yml`) | `scripts/check-docs.sh` (dead source pointers, stale stdlib counts, corpus INDEX counts, quarantine inventory); `scripts/test-run-tests.sh` (the test runner's own failure reporting); PRs must not touch the bot-owned `docs/pagefind/`; `runtime/sources.list` agrees with every C link list; no plain store to an actor's refcount word. | Almost always a doc/manifest edit you forgot. The error names the file. |
| `test (macos-15, all)` | Plain `dune runtest`: all four ubuntu shards' work in one job on macOS. | Whatever suite failed; reproduce as for the matching ubuntu shard. |
| `test (ubuntu, codegen)` | `dune build @test/runtest-run_codegen`: the LLVM codegen suite (`test/test_codegen.ml` and friends), including native compile-and-run cases. | A codegen or runtime regression; reproduce with `scripts/run-tests.sh codegen`. |
| `test (ubuntu, refinecheck)` | `@test/runtest-test_refinecheck`: the z3-backed refinement checker corpus. | `scripts/run-tests.sh refinecheck` (needs z3 on PATH). |
| `test (ubuntu, compiler)` | `@test/runtest-run_compiler`: frontend, typecheck, capabilities, CAS, CLI behaviour. | `scripts/run-tests.sh compiler`. |
| `test (ubuntu, rest)` | `MARCH_CI_RUNTEST_SPLIT=1 dune runtest`: everything else under `dune runtest` (eval, stdlib, JIT, LSP, forge, the native golden rules, snapshots, C unit tests). The env var drops exactly the three suites above; see the comment over the test runners in `test/dune`. | `dune runtest --root .` locally (without the env var, which runs the other three as well). |
| `two-node` | The `node_discovery` soak (200 runs diffed against the golden, a torn-stdout guard) and every `test/two_node/<scenario>`: two real OS processes, a fault injected from outside, per-node goldens. | `scripts/two-node.sh <scenario>`. Two scenarios are known flaky on `main`; check `main`'s own runs before blaming your diff. |
| `bench-gate` | Compiles every gated `bench/*.march` at `--opt 2`, runs it, checks the printed value. The only place benchmarks run in CI. | A benchmark stopped compiling or computes a different answer (not a timing check). |
| `conformance (<os>)` | `@types-check` (static-semantics corpus) and `@grammar-check`, the two refinement coverage ratchets, `@vault-scale`, doc notebooks (`.scrollmd`) compile, stdlib `march>` doctests, formatting. | The step name says which. Ratchets fail when coverage drops, not just on errors. |
| `sanitize-gate` | AddressSanitizer over the golden corpus, a curated native list and the two-node sweep (`specs/lang/golden/sanitize.sh`). Guards RC/use-after-free bugs. Ubuntu only. | A memory-safety bug even if every test passed. On a Mac, reproduce in a Linux Docker container: ASAN binaries can hang on macOS hosts running endpoint security software. |
| `ocaml-build (<os>)` | Builds the compiler and oracle binaries once and uploads them for the jobs below. | A build break; everything downstream is skipped. |
| `property-tests (<os>, <shard>)` | QCheck property groups from `test/test_properties.ml`, split into three shards, on both OSes (macOS matters: signal/segfault classification differs). | Shrunk counterexample is in the log. |
| `property-coverage` | Asserts the three shards together cover every property group, so a new group can't silently run nowhere. | Add the group to a shard's filter in `ci.yml`. |
| `property-oracle` × 8 | The differential oracle: ~1090 generated programs, interpreted vs compiled, outputs must match. | An interpreter/compiler divergence; the log has the program. |
| `cross-linux-oracle` | Cross-compiles the golden corpus to linux/amd64 with `zig cc` and checks output is byte-identical to the native build. | A cross-compilation or target-flag regression. |

**What CI does not cover:** Linux arm64 (only built, by `build.yml`), Windows,
and the tests quarantined out of `runtest` (run informationally by the nightly).

## `nightly.yml`

1. `gate` decides whether to run and which commit to build. It walks `CI`'s
   push runs on `main` newest first, skipping runs still in progress. The first
   finished run decides: a failure means `main` is red and nothing runs; a
   success makes that commit the candidate. The candidate must also be newer
   than the rolling `nightly` tag (the last commit a nightly shipped). A manual
   run with `force: true` builds `main`'s HEAD and skips both checks.
2. `quarantined` (informational, never fails the run) runs every
   `*_quarantined` dune alias; all green is the cue to un-quarantine.
3. `stdlib-docs-smoke` checks the external `march_doc` generator still builds
   with this compiler.
4. `version` → `build` (via `build.yml`) → `publish` (GitHub prerelease +
   `nightly-manifest.json`, moves the `nightly` tag) → `prune` (keeps the last 30).

Every job checks out the commit `gate` picked.

## `build.yml` and `release.yml`

`build.yml` produces `darwin-arm64`, `linux-x86_64` and `linux-aarch64`
archives. Both Linux legs build inside Alpine and are fully static (musl);
the job fails if a "static" binary has dynamic dependencies or won't run in a
bare container. `release.yml` calls it on a `v*` tag and publishes a release.

## Docs bots

The site (`march-lang.org`) is served by GitHub's own Jekyll over `docs/`, so
generated files must be committed. Two bots keep them fresh after a merge:
`gen-stdlib-docs.yml` (stdlib pages + search index, on stdlib changes) and
`sync-docs-search-index.yml` (search index, on any docs change). PRs should not
commit `docs/pagefind/`; `doc-lint` rejects it. `deploy-pages.yml` is a
separate path that publishes to the external `march-language.github.io` repo.

## Running the same checks locally

`scripts/run-tests.sh` runs the alcotest suites (see `CLAUDE.md` for suite
names). It does not run the dune-rule tests (native goldens, C unit tests);
`dune runtest --root .` does. Conformance lanes are `dune build --root .
@types-check --force` and `@grammar-check --force` (without `--force` they can
be empty and still exit 0).
