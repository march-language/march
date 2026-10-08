---
name: steward
description: Repo-specific guidance for driving a March pull request to green — known flaky CI checks and the policy for each, how to find the real failure in a CI log, what CI enforces that agents forget, commit/PR attribution footers, and the standard preamble for a spawned task prompt.
---

# Driving a March PR

The map of every CI job and what a red one means is `.github/workflows/README.md`.
This skill is the part that map leaves out: which reds are noise, how to read
the long logs, and what the gate checks that is easy to forget.

## The one-re-run rule

A failure on a **known timing flake** (list below) gets **one** re-run of the
failed jobs (`gh run rerun <run-id> --failed`) and a PR comment naming the flake.
A second red on the same check is treated as real. Anything not on the list is
real until a control proves otherwise: the same job on `main`'s own recent runs,
or the same commit re-run. **Never skip, disable or quarantine a test to get
green.**

## Known flaky checks and the policy for each

| Check | Symptom | Policy |
|---|---|---|
| `test (macos-15, all)` | Times out, or one suite dies with nothing failing. It runs the whole `dune runtest` unsharded: 37–49 min on `main` with a 75 min ceiling; `run_codegen` alone takes ~28 min on a slow runner. | Check whether it timed out (grep the log for `timed out`) and whether `main`'s own run of the same day did too. One re-run. Never split the macOS shard to dodge the timeout (it doubled its runner-minutes; `.github/workflows/README.md`, "Runner budget"). |
| `two-node (K/3)`: `cluster_sessions` | node-a prints `A: links 0` where the golden pins `1` (a stop/print race). | One re-run. |
| `sanitize-gate`: two-node `cluster_takeover` | `node-a: leader bound to ?` then a timeout, under ASan. | One re-run; grep `main`'s recent sanitize-gate logs for the same scenario. |
| `sanitize-gate`: other two-node scenarios | A deadline inside a node expires under ASan with no sanitizer report. In-node deadlines are now scaled by `TWO_NODE_ASAN_SCALE` (`specs/progress/2026-10-05-two-node-asan-time-scale.md`). | A new one is a missing scale: file a todo naming the deadline, don't raise a timeout blindly. |
| `conformance`: `@vault-scale` | Was a wall-clock ratio. Since 2026-10-04 it counts lock acquisitions and is deterministic (`specs/progress/2026-10-04-vault-write-scale-and-observe-sched-flakes.md`). | A red now is real. |
| `test/native/observe_sched` (macOS) | Idle readings over 50 ms. Since 2026-10-04 it fails only on a majority of slow samples. | A red now is very likely real (a stale clock). |
| Other one-sighting flakes | `Signal.watch ... (25x)`, `stream_actor_restart` x86 segfault, `two-node[restart]` exit 137, `test_upgrade_from` traffic driver SIGKILL. Each has a `specs/todos/2026-09-*-flake-*.md`. | One re-run; append the run URL and log excerpt to that todo. |

## Finding the real failure in a CI log

- `gh run view --log` **truncates**. Fetch a job's full log with
  `gh api repos/march-language/march/actions/jobs/<job-id>/logs > job.log`.
  A finished job's log is readable while the rest of the run is still going.
- The macOS `all` shard runs every alcotest suite, and every one of them reports
  its summary, so "Test Successful" lines prove nothing about the job. Golden-rule
  failures (native goldens, snapshots) show up as `File "…expected", line 1`
  followed by a `git diff` of expected vs actual: **`grep -n 'File "' job.log`**
  finds them. Alcotest failures: `grep -n '\[FAIL\]' job.log`.
- A CONFLICTING PR gets no CI run at all; resolve the conflict first.
- Wait for CI by run id, not the PR's status rollup (it can show one entry while
  others are still queued).

## What CI enforces that agents forget

- **CHANGELOG bullet** under `## [Unreleased]` for any user-visible change.
- **`specs/progress/` entry** for every finished item, and the matching
  `specs/todos/` file `git mv`'d, not left stale.
- **Tree-sitter rule**: a PR touching `lib/parser/parser.mly` or
  `lib/lexer/lexer.mll` extends `tree-sitter-march/grammar.js` or lists its new
  fixtures in `tree-sitter-march/known-failures.txt` (`scripts/check-tree-sitter.sh`).
  A change to `lib/parser/token_filter.ml` alone does not trigger it.
- **doc-lint**: dead compiler-source pointers in current docs (CLAUDE.md, `docs/`,
  `specs/lang`, `specs/features`, `specs/impl`, the skills), stale stdlib counts,
  hand-edited `docs/` language chapters (edit `specs/lang/`, run
  `scripts/gen-lang-docs.py`), and any change to bot-owned `docs/pagefind/`.
  Run `scripts/check-docs.sh` before pushing.
- **A new `bench/*.march` must be registered in `test/test_bench_gate.ml`**
  (gated with its expected output, or in the skip list with a reason), or
  `bench-gate` goes red for everyone.
- **A new `test/native` fixture** needs the refine audit baseline regenerated in
  the same commit.
- Stage files by name: never `git add -A`, `git add .` or `git commit -a`.

## Attribution footers

Every commit message ends with exactly:
```
Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_<id>
```
Every PR body ends with:
```
🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_<id>
```
Use the session id of the session doing the work. A PR body also states which
oracle(s) were run and their result, or why none applies.

## Card-prompt preamble

The standard opening paragraph of a `spawn_task` prompt for this repo, so the
spawned session starts with the same rules:

> Read `CLAUDE.md` first and follow it throughout: no `eval $(opam env)`; build
> and test with `--root .` or `scripts/run-tests.sh`; stage files by name; add a
> `specs/progress/` entry and a CHANGELOG bullet with the change. If anything
> fails or misbehaves, load the `march-debug` skill and run `scripts/triage.sh`
> before guessing. If you use an oracle to prove a refactor moved nothing, make
> it go red on a deliberate perturbation first. End every commit and PR body
> with the attribution footers in the `steward` skill, and state in the PR body
> which oracle you ran and its result.
