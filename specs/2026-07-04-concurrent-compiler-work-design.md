# Enabling Concurrent Compiler Work — Design Spec

**Date:** 2026-07-04
**Status:** Design — not yet scheduled
**Author:** deep-review program follow-up.
**Motivating evidence:** the campaign ran dozens of parallel agent sessions
against one checkout and hit the same environment friction repeatedly. These
are not compiler bugs; they are a maintainability tax that makes the compiler
hostile to concurrent work — human or agent.

---

## 1. Problem

Multiple sessions (agents, or humans in separate worktrees) working on the
March compiler at the same time collide on **shared, unscoped, mutable global
state** in the developer environment. Over the deep-review campaign these
collisions caused: builds that wedged for hours, thousands of orphaned solver
processes, silently reverted edits, and false "hang" diagnoses that cost real
investigation time. Every incident was recoverable, but each one interrupted
work and several nearly caused wrong conclusions (a wedged test read as a
product failure; a stale-binary probe read as a real bug).

The compiler *supports* worktrees (each session gets its own branch and source
tree), but the surrounding tooling assumes a single writer. The shared state
that leaks across sessions:

| Shared resource | Location | Failure observed |
|---|---|---|
| JIT test runtime `.so` cache | `~/.cache/march/libmarch_rt_test_<key>.so` | A concurrent session poisons/rebuilds it mid-run → the other session's JIT tests **fake-hang** for hours at 0% CPU (killed manually 3+ times) |
| git stash stack | one stack shared by main repo + **all** its worktrees | `git stash pop` in one session popped **another** session's WIP → silent edit reversion + merge conflict; happened 3× incl. once inside a subagent |
| Refinement solver (z3) processes | spawned from `lib/refine/solver.ml` etc. | **1,174 orphaned z3 processes** (reparented to PID 1) accumulated across sessions — never reaped on parent exit; had to be mass-killed |
| CAS artifact cache | `<getcwd>/.march/cas/` (keyed on CWD) | mostly OK (per-worktree CWD), but env-gated flags (`MARCH_SANITIZE`, pass gates) aren't in the key → stale artifacts silently reused (memory: `project_cas_cache_key_flags`) |
| dune build daemon | per-project RPC daemon | stale zombie daemons from prior sessions block new runs and freeze log files (documented in CLAUDE.md's parallel-agent note) |
| `/tmp` scratch filenames | generic names (`/tmp/rc_repro`, `march_*`) | concurrent sessions clobber each other's temp binaries/logs (memory: `feedback_tmp_name_collisions`) |
| the checked-out main repo | `/Users/80197052/code/march` | a concurrent session's `git reset`/`checkout` in the main checkout silently reverts main-repo edits another session made (memory: `feedback_worktree_not_main_repo`) |

The cost is real and repeated: much of the campaign's process-hardening memory
(`jit_so_cache_cross_session`, `git_dash_c_for_stash`, `tmp_name_collisions`,
`subagent_dispatch_march`) exists *only* to help future sessions dodge these
traps by discipline. This spec proposes closing the classes so discipline
isn't required.

## 2. Goals

1. **Two sessions building/testing the same repo concurrently never corrupt or
   wedge each other** — no shared mutable state that one writer can poison for
   another.
2. **Processes the compiler spawns are reaped** when their parent exits — no
   orphan accumulation.
3. **Failures are loud and local**, not silent-and-shared — a cache miss
   rebuilds locally; it never hangs or poisons a peer.
4. Preserve the *performance* benefit of caching (the shared dune/CAS caches
   exist to cut cross-worktree rebuild time — see the recent
   `f65cec95`/`8290a53d` shared-dune-cache work); isolation must not mean "no
   cache," it means "no *unsafely-shared* cache."

Non-goals: distributed/multi-machine builds; sandboxing untrusted code;
changing the worktree model itself (it works — the tooling around it doesn't).

## 3. Approach — by resource

### 3.1 JIT test-runtime `.so` cache (highest pain)

Today `~/.cache/march/libmarch_rt_test_<key>.so` is written and read by any
session; a concurrent rebuild of the same key mid-read is the fake-hang.

Options, in preference order:
- **Content-hash the key completely** so two sessions building the *same* bytes
  share a *read-only, atomically-published* artifact (write to a temp path,
  `rename` into place — `rename` is atomic, so a reader sees either the old or
  the new file, never a half-written one), and two sessions building
  *different* bytes get *different* keys and never collide. The current key is
  partial; make it total over every input that affects the `.so`.
- **Or**, if total keying is impractical, **per-session cache dir**
  (`$MARCH_JIT_CACHE` defaulting to a session/PID-scoped path) so sessions
  never share the file at all — trades cache reuse for isolation. The campaign
  already used `HOME` override as a manual version of this; make it first-class
  and automatic.
- Either way: a build failure must return a **loud error**, never leave a
  partial file that the next reader blocks on. Add a lock-with-timeout (flock)
  around the *build* step so a second builder waits briefly then builds its own
  rather than hanging indefinitely.

### 3.2 git stash → forbid it in tooling; use worktree-scoped alternatives

The stash stack is shared across a repo and all its worktrees by git's design;
this cannot be fixed in git config. The fix is to **stop using stash in any
automated flow**. The campaign already learned this (memory:
`git_dash_c_for_stash`) — codify it:
- Any script/agent flow that needs to temporarily set a file aside uses a
  **file copy** (`cp file /tmp/<slug>-keep && … && cp back`) with absolute
  paths, or `git checkout <sha> -- <file>` + restore, never `git stash`.
- Add a repo pre-commit or CI lint that flags `git stash` in committed scripts.
- Document it in CLAUDE.md's parallel-agent section (partly there already).

### 3.3 Refinement solver (z3) process lifecycle — a real leak to fix in `lib/`

This is the one item that is a genuine compiler bug, not just env hygiene: the
refinement checker spawns z3 (`lib/refine/solver.ml`, `smt.ml`, `model.ml`) and
does not reliably terminate/reap the child on every exit path. 1,174 orphans
accumulated. Fix:
- Terminate the solver child when its solving scope ends (`kill` + `waitpid`),
  and install an `at_exit` / exception-path cleanup so an abnormal parent exit
  (typecheck error, panic, Ctrl-C) still reaps it.
- If the LSP holds a persistent solver, make it exactly **one supervised,
  reused** process with restart-on-death, not one-per-analysis.
- Add a spawn-count regression test (run N refinement typechecks in-process,
  assert zero z3 children remain — `pgrep`-based, loud-skip if z3 absent).

*(A background chip for this was spawned during the campaign — `task_c65d2c46`,
reported fixed. This spec section is the durable record of the requirement and
its regression test; verify the fix covers all exit paths and the test exists.)*

### 3.4 CAS cache key completeness

Mostly per-CWD-safe already, but codegen-affecting env/flags aren't in the key
(memory: `project_cas_cache_key_flags` — flags must be added to `cas_flags` in
`bin/main.ml` at both sites or cached binaries silently ignore them). Audit the
key: it must include every input that changes the output artifact —
compiler-executable digest, runtime-source digest (already present),
`--opt` level, `MARCH_SANITIZE`, target, and any env-gated pass toggle. A stale
CAS hit is a silent wrong-binary, the worst failure mode for a test.

### 3.5 dune daemon + `/tmp` scratch + main-checkout protection (process hygiene)

- **dune daemon**: the agent-safe `scripts/run-tests.sh` already shuts down
  stale daemons; ensure every documented test path routes through it or uses
  direct binary invocation. The worktree `--root .` fix (`4c1eea4f`) is landed;
  keep it.
- **`/tmp` scratch**: standardize a session-scoped scratch prefix
  (worktree-slug or PID suffix) for all temp binaries/logs the tooling and the
  oracle produce, so concurrent sessions can't clobber. Provide a helper rather
  than relying on each call site to remember (memory:
  `feedback_tmp_name_collisions`).
- **Main-checkout edits**: document forcefully (and, where possible, lint) that
  sessions edit/build *in their worktree*, never the shared main checkout — a
  concurrent `git reset` there silently reverts another session's work (memory:
  `feedback_worktree_not_main_repo`). Consider making the main checkout's
  working tree the merge-integration point only, never an edit surface.

## 4. Phasing

- **Phase 1 — the z3 leak** (§3.3): a real `lib/` bug with a spawn-count test.
  Highest correctness value; smallest blast radius. (Possibly already landed via
  `task_c65d2c46` — Phase 1 is then "verify + lock in the regression test.")
- **Phase 2 — JIT cache isolation** (§3.1): the highest *pain* item; closes the
  fake-hang class. Total-key + atomic-rename is the durable fix.
- **Phase 3 — CAS key audit** (§3.4): prevents silent wrong-binary test results.
- **Phase 4 — process hygiene + lints** (§3.2, §3.5): stash lint, scratch-prefix
  helper, main-checkout protection, dune-daemon routing. Mostly documentation +
  small tooling; codifies the campaign's hard-won discipline so it's enforced,
  not remembered.

## 5. Acceptance criteria

- Two worktree sessions running the full test suite simultaneously both pass,
  repeatably, with no hang and no cross-corruption (the concrete regression
  test for this whole spec: a CI job that launches two suite runs in parallel
  worktrees and asserts both green).
- After a run of the refinement/LSP tests, zero orphaned z3 processes remain.
- A JIT-cache build failure surfaces as a loud error in the failing session and
  leaves peers unaffected; two sessions with identical inputs share the artifact
  safely (atomic publish), two with different inputs never collide.
- A CAS hit is provably a hit only when every codegen-affecting input matches
  (verified with a value-revealing program across two flag settings, not a
  parity check — per the memory note).
- No committed script uses `git stash`.

## 6. Risks / open questions

- **Cache isolation vs reuse tension** (§3.1). Total content-keying preserves
  reuse *and* isolation but requires enumerating every input that affects the
  `.so` — miss one and you get either false sharing (a bug) or false misses (a
  slowdown). Per-session dirs are simpler and safe but give up cross-session
  reuse. Measure the reuse win before choosing; the recent shared-dune-cache
  work suggests reuse matters here.
- **Atomicity portability.** `rename`-into-place is atomic on local POSIX
  filesystems; verify on the actual dev filesystem (macOS APFS — fine) and note
  it won't hold on network mounts if that ever matters.
- **flock timeout tuning** (§3.1). Too short → spurious parallel rebuilds; too
  long → the hang returns in a slower form. Needs a measured default.
- **The main-checkout-as-edit-surface** problem (§3.5) is partly social/agent
  convention; a hard technical guard (e.g. a pre-commit hook refusing edits on
  the integration checkout) may be too blunt. Open question whether to enforce
  or only document.

## 7. Relationship to existing work

- Formalizes the process-hardening lessons currently living only in session
  memory (`jit_so_cache_cross_session`, `git_dash_c_for_stash`,
  `tmp_name_collisions`, `worktree_not_main_repo`, `cas_cache_key_flags`,
  `subagent_dispatch_march`).
- Builds on the landed shared-dune-cache work (`f65cec95`, `8290a53d`) and the
  worktree `--root .` test fix (`4c1eea4f`).
- Shares the cache-isolation concern with the differential-oracle spec
  (`2026-07-04-differential-oracle-design.md` §7) — the oracle compiles many
  one-off programs and is a heavy client of exactly the caches this spec
  isolates; the two should land the JIT/CAS isolation before the oracle's
  full-corpus sweep runs at scale.
