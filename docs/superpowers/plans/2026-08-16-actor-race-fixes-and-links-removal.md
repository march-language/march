# Actor Race Fixes and Links Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the two genuinely-open supervision races, finish the half-fixed death-cleanup race, retire two stale todos, and remove the unreachable `link` builtin with a documented rationale.

**Architecture:** Four independent changes to `runtime/march_runtime.c` plus one interpreter/doc change. The supervision fixes follow the existing leaf-lock discipline around `g_supervise_mu` (claim a marker under the lock, run the strategy with the lock released) and the existing incarnation-precise lookup helper `find_meta_by_pid_index`. The cleanup fix follows the detach-under-lock-then-run-unlocked pattern that `monitor_head` already uses two lines above it. Nothing here changes the supervision *semantics* a working program observes — every change is about what happens when two OS threads arrive at the same place at once.

**Tech Stack:** C11 runtime (`runtime/march_runtime.c`), OCaml interpreter (`lib/eval/eval.ml`), Alcotest suites under `test/`, native March fixtures under `test/native/`, dune.

**Spec:** the four todo files named per-task below. Read the task's todo before starting it — each contains the original discovery context and a suggested fix shape.

## Global Constraints

- `--root .` is MANDATORY on every dune command. Worktrees live inside the main repo; a bare `dune build` silently builds `/Users/80197052/code/march`.
- After editing `runtime/*.c`: `dune build --root . @bin/warm-cache`. `dune build bin/main.exe` does NOT restage `_build/default/runtime`, so the edit silently will not be in the binary. After editing `stdlib/*.march`: `dune build --root . @install`.
- Clear the CAS before comparing compiled behavior: `rm -rf .march/cas/artifacts-v2/`.
- Use `DUNE_CACHE=disabled dune build --root . --force` for anything you intend to trust. Never hand-write into `_build/` — it writes through a hardlink into the user-global dune cache.
- Never `git stash` (shared stash stack across worktrees; four prior incidents). To compare against base, copy the file aside and copy it back.
- Stage explicitly by filename. Never `git add -A`, `git add .`, `git add *`, or `git commit -am`. No `Co-Authored-By` lines.
- Never `eval $(opam env ...)`. Never pipe `march --compile` — redirect to a file and judge by `$?`. Never judge any exit code through a pipe (`cmd | tail` gives you `tail`'s status).
- `timeout` does not exist on this macOS box. Foreground commands only.
- `test_trmc` lives in `run_codegen.exe`, not `run_compiler.exe`. Know which driver owns a test before claiming it passed.
- `native_node_discovery`, `native_tuple_destructure_rc` and `llvm_ir_validity_gate` fixtures flake under host load, usually as a SIGKILL the harness labels "OOM killer or an external kill". Check `uptime`; re-run in isolation before reporting one as a regression.
- Every task updates `specs/todos/` and `specs/progress/` in the same commit that lands the change, per `CLAUDE.md`.

## File Map

- `runtime/march_runtime.c` — all three runtime fixes. Tasks 2, 3, 4 each touch a different function (`do_actor_death`, `march_supervisor_notify`, `delayed_restart_thread` + `march_delayed_restart`), so they do not overlap textually, but they must still land in sequence because each rebuilds the runtime.
- `lib/eval/eval.ml` — Task 5 only (remove `link` builtin, `link_actors`, `ai_links`).
- `test/test_supervision.ml` — Tasks 3 and 4 regression coverage.
- `test/native/` — Task 2 native fixture.
- `specs/todos/`, `specs/progress/`, `docs/actors.md`, `specs/lang/actors.md`, `CHANGELOG.md` — Tasks 1 and 5.

---

### Task 1: Retire two stale todos (verification only, no code)

Two of the four filed races are already fixed in `main`. This task proves that and moves the ledger, so nobody plans work that is already done. **No code changes.**

**Files:**
- Delete (via `git mv`): `specs/todos/2026-08-12-supervised-child-registration-race.md` → `specs/progress/2026-08-16-supervised-child-registration-race.md`
- Modify: `specs/todos/2026-08-12-do-actor-death-unlocked-cleanup-monitor-heads.md`

**Interfaces:**
- Consumes: nothing.
- Produces: an accurate todo set for Tasks 2–4.

- [ ] **Step 1: Confirm the registration race is fixed**

Read `runtime/march_runtime.c` `march_respawn_child` and confirm all three properties hold:

```
grep -n "march_spawn_supervised\|new_meta->supervisor = supervisor\|activate_actor_green_thread(new_meta)" runtime/march_runtime.c
```

Expected: `march_spawn_supervised(raw)` (deferred activation), then `new_meta->supervisor = supervisor;` inside a `pthread_mutex_lock(&g_tbl_mu)` / `unlock` pair, then `activate_actor_green_thread(new_meta);` AFTER that publication. Also confirm codegen emits the deferred entry point for supervise-block children:

```
grep -n "march_spawn_supervised" test/test_eval.ml test/test_codegen.ml
```

Expected: both assert the emitted IR calls `march_spawn_supervised`. Together these close the window the todo describes — the green thread cannot read `meta->supervisor` before it is written, because the green thread does not exist until after the write.

- [ ] **Step 2: Write the progress entry**

`git mv specs/todos/2026-08-12-supervised-child-registration-race.md specs/progress/2026-08-16-supervised-child-registration-race.md`, then append a "## Resolved" section recording: the fix is deferred activation (`march_spawn_common(actor, defer_activation)`, exposed as `march_spawn_supervised`) plus the locked `supervisor` write, so both the ordering gap AND the unlocked-write half of the todo are closed; the todo's own suggested shape ("`march_spawn` accepts the supervisor pointer directly, so `meta->supervisor` is set BEFORE the green thread is started") is what landed, in the equivalent deferred-activation form. State that this was verified by reading the code, not by re-running the timing-sensitive `rfo_widen.march` repro, and that the structural argument (no green thread exists before publication) is stronger than a race-and-hope loop.

- [ ] **Step 3: Correct the monitor-heads todo to reflect what #284 already fixed**

Edit `specs/todos/2026-08-12-do-actor-death-unlocked-cleanup-monitor-heads.md`. Add a section at the top:

```markdown
## Partially fixed 2026-08-15 (#284)

The `monitor_head` half is CLOSED. `do_actor_death` now detaches the list
under `g_tbl_mu`:

    monitors = meta->monitor_head;
    meta->monitor_head = NULL;

and walks the detached list after unlocking, so `march_monitor`'s locked
prepend can no longer write into a list being freed.

The `cleanup_head` half is STILL OPEN and is what remains of this todo. It
cannot simply take the lock: cleanup closures run arbitrary March code via
`fn_ptr(clo, unit_arg)`, which can re-enter the runtime and re-acquire
`g_tbl_mu`. The fix is the same detach-then-run shape the monitor half now
uses.
```

- [ ] **Step 4: Commit**

```bash
git add specs/progress/2026-08-16-supervised-child-registration-race.md specs/todos/2026-08-12-do-actor-death-unlocked-cleanup-monitor-heads.md
git commit -m "specs: retire the fixed registration race; scope the cleanup-head todo to what remains"
```

---

### Task 2: Detach cleanup_head under g_tbl_mu before running closures

**Files:**
- Modify: `runtime/march_runtime.c` (`do_actor_death`, the `cleanup_head` block that currently follows the `pthread_mutex_unlock(&g_tbl_mu)` after the monitor detach)
- Modify: `specs/todos/2026-08-12-do-actor-death-unlocked-cleanup-monitor-heads.md` → `git mv` to `specs/progress/2026-08-16-do-actor-death-cleanup-detach.md`

**No new test.** Ruling 2026-08-16: this race cannot be forced deterministically
across two OS threads, so any fixture here would pass identically before and
after the fix. A test that cannot fail against the broken code is not evidence,
and the project standard is not to ship one. The correctness argument for this
task is structural (Steps 2-3) and the existing suites are the regression net.

**Interfaces:**
- Consumes: Task 1's corrected todo.
- Produces: no new public symbols. `do_actor_death` keeps its existing signature `static void do_actor_death(void *actor, march_death_reason reason, const char *message, size_t message_len)`.

- [ ] **Step 1: Apply the detach**

In `do_actor_death`, the monitor detach already happens under `g_tbl_mu`. Extend that same locked section to also detach the cleanup list, and walk the detached head afterwards. Replace:

```c
        monitors = meta->monitor_head;
        meta->monitor_head = NULL;
    }
    pthread_mutex_unlock(&g_tbl_mu);
```

with:

```c
        monitors = meta->monitor_head;
        meta->monitor_head = NULL;
        /* Detach the cleanup list under the SAME lock, for the same reason
         * the monitor list is detached here: march_on_cleanup prepends to
         * meta->cleanup_head under g_tbl_mu, so an unlocked walk-and-free
         * here can race a concurrent prepend and free a node the other
         * thread just linked. The closures themselves must NOT run under
         * the lock — they are arbitrary March code and can re-enter the
         * runtime and re-acquire g_tbl_mu — so this detaches the head and
         * the walk below runs on a list nothing else can still reach. */
        cleanups = meta->cleanup_head;
        meta->cleanup_head = NULL;
    }
    pthread_mutex_unlock(&g_tbl_mu);
```

Declare `march_cleanup_node *cleanups = NULL;` beside the existing `monitors` declaration. Then change the walk below from `if (meta && meta->cleanup_head) { ... march_cleanup_node *node = meta->cleanup_head;` to operate on the detached local, and delete the now-redundant trailing `meta->cleanup_head = NULL;`:

```c
    if (cleanups) {
        march_cleanup_node *node = cleanups;
        while (node) {
            march_cleanup_node *next = node->next;
            void *clo = node->cleanup_fn;
            if (clo && IS_HEAP_PTR(clo)) {
                typedef void *(*clo_fn_t)(void *, void *);
                void **clo_fields = (void **)((char *)clo + 16);
                clo_fn_t fn_ptr = (clo_fn_t)(*(clo_fields));
                if (fn_ptr) {
                    void *unit_arg = march_alloc(16);
                    fn_ptr(clo, unit_arg);
                    march_decrc(unit_arg);
                }
            }
            free(node);
            node = next;
        }
    }
```

- [ ] **Step 2: Verify no lock is held across the closure call**

Read the final code and confirm `pthread_mutex_unlock(&g_tbl_mu)` precedes the `fn_ptr(clo, unit_arg)` call. This is the whole safety argument for the change — if the unlock ever moves below the walk, a cleanup closure that touches any actor API self-deadlocks. State this explicitly in the task report.

- [ ] **Step 3: Rebuild and run**

```bash
DUNE_CACHE=disabled dune build --root . @bin/warm-cache --force
rm -rf .march/cas/artifacts-v2/
./_build/default/test/run_stdlib.exe -e > /tmp/t2-stdlib.log 2>&1; echo "exit=$?"
grep -c "^  \[FAIL\]" /tmp/t2-stdlib.log
dune build --root . @test/runtest 2>&1 | tail -5
```
Expected: exit 0, zero FAIL lines, runtest clean.

- [ ] **Step 4: Move the todo and commit**

```bash
git mv specs/todos/2026-08-12-do-actor-death-unlocked-cleanup-monitor-heads.md specs/progress/2026-08-16-do-actor-death-cleanup-detach.md
```
Append a "## Resolved" section stating both halves are now closed (monitor half by #284, cleanup half here), that the fix is detach-under-lock rather than hold-lock-across-closures, and why that distinction is load-bearing.

```bash
git add runtime/march_runtime.c specs/progress/2026-08-16-do-actor-death-cleanup-detach.md
git commit -m "runtime(actor): detach the cleanup list under g_tbl_mu before running closures"
```

---

### Task 3: Claim an in-flight marker before a synchronous batch restart

**Files:**
- Modify: `runtime/march_runtime.c` — the `march_actor_meta` supervisor fields block (~line 1896, beside `delayed_batch_pending`), and `march_supervisor_notify`'s leaf-lock section and synchronous branch
- Modify: `test/test_supervision.ml`
- Modify: `specs/todos/2026-08-12-concurrent-first-crash-batch-restarts-unsynchronized.md` → `git mv` to `specs/progress/`

**Interfaces:**
- Consumes: nothing from Tasks 1–2.
- Produces: a new `march_actor_meta` field `int batch_restart_in_flight;` (zeroed by the existing `calloc`), read and written only under `g_supervise_mu`.

- [ ] **Step 1: Read the todo and the existing claim logic**

Read `specs/todos/2026-08-12-concurrent-first-crash-batch-restarts-unsynchronized.md` in full, then `march_supervisor_notify`'s leaf-lock section. The gap: `delayed_batch_pending` is claimed only in the `else if (is_batch && streak > 1)` branch. A first crash (`streak == 1`) of a batch supervisor claims nothing and falls through to the `if (delay == 0)` synchronous branch, so two different children crashing for the first time on two OS threads can both call a strategy function concurrently against the same `sup_children` array.

- [ ] **Step 2: Add the field**

Beside `int delayed_batch_pending;` in `march_actor_meta`, add:

```c
    /* Set for the entire in-flight duration of a SYNCHRONOUS batch restart
     * (one_for_all / rest_for_one, streak == 1, delay == 0), so a second
     * first-time crash of a DIFFERENT child cannot call a strategy function
     * concurrently against the same sup_children array. delayed_batch_pending
     * does not cover this: a streak==1 crash never claims it (by design —
     * round 1 kept every first crash on the original synchronous path), so
     * two first crashes both observed "not pending" and both ran a strategy.
     * Mutated only under g_supervise_mu; zeroed by calloc. */
    int                          batch_restart_in_flight;
```

- [ ] **Step 3: Claim it in the leaf-lock section**

In the leaf-lock section, extend the skip condition and add a synchronous claim. Change:

```c
    skip_due_to_pending = is_batch && sup_meta->delayed_batch_pending;
```
to:
```c
    skip_due_to_pending = is_batch && (sup_meta->delayed_batch_pending
                                       || sup_meta->batch_restart_in_flight);
```

and add a new branch after the existing `else if (is_batch && streak > 1)` block:

```c
    } else if (is_batch) {
        /* streak == 1: this crash will take the synchronous delay==0 path
         * below. Claim the in-flight marker HERE, inside the same critical
         * section that decided we are not skipping, so a sibling's
         * first crash arriving on another thread sees it and is deflected
         * into skip_due_to_pending (widening pending_min_child_idx and
         * counting the drop) exactly as it would be for a delayed restart. */
        sup_meta->batch_restart_in_flight = 1;
        sup_meta->pending_min_child_idx = child_idx;
        claimed_sync_batch = 1;
    }
```

Declare `int claimed_sync_batch = 0;` beside `claimed_batch`.

- [ ] **Step 4: Release it after the strategy returns**

In the `if (delay == 0)` branch, release the marker after the strategy call — never before, and never while holding it across the call:

```c
    if (delay == 0) {
        switch (strategy) { /* today's immediate path */
            case 0: march_one_for_one_restart(supervisor, sup_meta, child_idx); break;
            case 1: march_one_for_all_restart(supervisor, sup_meta, child_idx); break;
            case 2: march_rest_for_one_restart(supervisor, sup_meta, child_idx); break;
            default: break;
        }
        if (claimed_sync_batch) {
            /* Released only after the strategy has fully returned, so the
             * window a sibling can be deflected through covers the whole
             * call, not just its start — the same invariant the delayed
             * path maintains with delayed_batch_pending. */
            pthread_mutex_lock(&g_supervise_mu);
            sup_meta->batch_restart_in_flight = 0;
            pthread_mutex_unlock(&g_supervise_mu);
        }
        return;
    }
```

- [ ] **Step 5: Verify the deflected sibling is not lost**

A sibling deflected by the new marker takes the `skip_due_to_pending` path, which widens `pending_min_child_idx` and increments `pending_drop_count` — but for a SYNCHRONOUS restart there is no `delayed_restart_thread` absorb loop to consume those. Read the `skip_due_to_pending` block and decide, then state in the report which of these holds:
  - for `one_for_all`, the in-flight restart already covers every child, so a deflected sibling needs nothing; or
  - for `rest_for_one`, a deflected sibling with a LOWER index would be outside the in-flight `[child_idx, n)` window and left dead.

If the second case is reachable, the release in Step 4 must re-check `pending_drop_count` and re-run the strategy at the widened `pending_min_child_idx`, mirroring `delayed_restart_thread`'s absorb loop. **Do not skip this step** — it is the difference between fixing the race and trading it for a silently-dead child. Whatever you conclude, write the argument down.

- [ ] **Step 6: Add a regression test ONLY if it genuinely fails pre-fix**

In `test/test_supervision.ml`, attempt a test asserting that a `one_for_all` supervisor whose two children both crash for the first time performs exactly ONE batch restart, not two. Assert on the restart count the supervision tests already use — copy the assertion style from the nearest existing batch-strategy test rather than inventing one.

**Then prove it discriminates.** Copy `runtime/march_runtime.c` aside, revert your Step 2-4 changes in the working copy (never `git stash`), rebuild with `dune build --root . @bin/warm-cache`, and run the new test. Report the result:

- If it FAILS pre-fix and passes post-fix, keep it and report both outputs.
- If it PASSES both ways, **delete it** and say so plainly in the report. Ruling 2026-08-16: a test that cannot fail against the broken code is not evidence, and this project does not ship one as a placeholder. The fix then rests on its structural argument, which you must state explicitly in the report.

A race-and-hope loop is not an acceptable substitute in either case.

- [ ] **Step 7: Rebuild, run, commit**

```bash
DUNE_CACHE=disabled dune build --root . @bin/warm-cache --force
rm -rf .march/cas/artifacts-v2/
./_build/default/test/run_stdlib.exe -e > /tmp/t3-stdlib.log 2>&1; echo "exit=$?"
grep -c "^  \[FAIL\]" /tmp/t3-stdlib.log
dune build --root . @test/runtest 2>&1 | tail -5
```
Expected: exit 0, zero FAIL lines, and the three pre-existing supervision goldens still byte-match.

```bash
git mv specs/todos/2026-08-12-concurrent-first-crash-batch-restarts-unsynchronized.md specs/progress/2026-08-16-sync-batch-restart-in-flight-marker.md
git add runtime/march_runtime.c test/test_supervision.ml specs/progress/2026-08-16-sync-batch-restart-in-flight-marker.md
git commit -m "runtime(supervisor): claim an in-flight marker across synchronous batch restarts"
```

---

### Task 4: Make the delayed-restart liveness check incarnation-precise

**Files:**
- Modify: `runtime/march_runtime.c` — `march_delayed_restart` struct (~3272) and `delayed_restart_thread` (~3340)
- Modify: `specs/todos/2026-08-12-delayed-restart-supervisor-address-reuse.md` → `git mv` to `specs/progress/`

**No new test.** Ruling 2026-08-16: address reuse cannot be forced on demand, so
any probe here would pass identically before and after the fix. A test that
cannot fail against the broken code is not evidence. The correctness argument is
structural (a pid_index lookup is incarnation-precise where an address probe is
not) and the backoff goldens are the regression net for timing behaviour.

**Interfaces:**
- Consumes: nothing from Tasks 1–3.
- Produces: `march_delayed_restart` gains `int64_t sup_pid_index;`. Uses the existing `static march_actor_meta *find_meta_by_pid_index(int64_t pid_index)`.

- [ ] **Step 1: Read the todo**

Read `specs/todos/2026-08-12-delayed-restart-supervisor-address-reuse.md`. The bug: `delayed_restart_thread` re-validates the supervisor with `march_is_alive(supervisor)`, an ADDRESS probe. Across a backoff window of up to ~3.2s, the original supervisor can die and the allocator can hand its address to a brand-new, unrelated actor — which reads as alive, so the restart runs against the wrong actor.

- [ ] **Step 2: Stamp the pid_index at schedule time**

Add to `march_delayed_restart`:

```c
typedef struct {
    void   *supervisor;
    int64_t sup_pid_index;  /* incarnation-precise identity; see delayed_restart_thread */
    int     child_idx;
    int     strategy;       /* 0/1/2 — mirrors supervisor_strategy */
    int64_t not_before_ms;
} march_delayed_restart;
```

At the `malloc` site in `march_supervisor_notify`, populate it alongside the existing fields:

```c
    dr->sup_pid_index = atomic_load_explicit(&sup_meta->pid_index,
                                             memory_order_relaxed);
```

- [ ] **Step 3: Replace all three liveness checks**

`delayed_restart_thread` probes liveness in three places: the initial check, the `strategy == 0` recheck, and the per-pass recheck inside the batch loop. Replace each address probe with an incarnation-precise resolve. Add near the top of the function, after `free(dr)` (capture `sup_pid_index` into a local BEFORE the free, alongside the existing `supervisor`/`child_idx`/`strategy` captures):

```c
    /* Incarnation-precise liveness. march_is_alive(supervisor) is an ADDRESS
     * probe: across a backoff window of up to ~3.2s the original supervisor
     * can die and the allocator can hand its address to an unrelated new
     * actor, which reads as alive — and the restart then runs against the
     * wrong actor. find_meta_by_pid_index is keyed off the per-spawn
     * pid_index table, so a successful lookup that still maps to this
     * address is proof the ORIGINAL incarnation is the one being addressed. */
    #define SUP_STILL_LIVE() \
        (find_meta_by_pid_index(sup_pid_index) == sup_meta \
         && march_is_alive(supervisor))
```

Use `SUP_STILL_LIVE()` at all three sites in place of `march_is_alive(supervisor)`, and `#undef SUP_STILL_LIVE` at the end of the function. If a macro is against house style in this file, write a `static int sup_still_live(int64_t pid_index, march_actor_meta *sup_meta, void *supervisor)` helper instead — check the surrounding code and match it.

Note `sup_meta` is resolved by `find_meta(supervisor)` AFTER the first check today; you will need to resolve it before the first check, or compare `find_meta_by_pid_index(sup_pid_index)` against non-NULL and derive `supervisor` from it. Either is fine — say which you chose and why.

- [ ] **Step 4: Rebuild and run**

```bash
DUNE_CACHE=disabled dune build --root . @bin/warm-cache --force
rm -rf .march/cas/artifacts-v2/
./_build/default/test/run_stdlib.exe -e > /tmp/t4-stdlib.log 2>&1; echo "exit=$?"
grep -c "^  \[FAIL\]" /tmp/t4-stdlib.log
dune build --root . @test/runtest 2>&1 | tail -5
```
Expected: exit 0, zero FAIL lines. The backoff goldens must still byte-match — this change must not alter WHEN a restart fires, only WHETHER it fires against the right supervisor.

- [ ] **Step 5: Move the todo and commit**

```bash
git mv specs/todos/2026-08-12-delayed-restart-supervisor-address-reuse.md specs/progress/2026-08-16-delayed-restart-incarnation-precise.md
git add runtime/march_runtime.c specs/progress/2026-08-16-delayed-restart-incarnation-precise.md
git commit -m "runtime(supervisor): resolve the delayed-restart supervisor by pid_index, not address"
```

---

### Task 5: Remove the unreachable link builtin and document the fault model

The runtime carries half a fault-propagation model no program can reach: `lib/eval/eval.ml` defines a `link` builtin but the typechecker has no entry for it (`grep -c '"link"' lib/typecheck/typecheck.ml` returns 0), so `link(a, b)` fails with "I cannot find `link`". **Decision taken 2026-08-16: remove it.** March's fault model is monitors + supervisors, Akka-style. #284 strengthened this case by giving monitors reason-carrying `Down` messages, which was the main thing links offered that monitors did not.

**Files:**
- Modify: `lib/eval/eval.ml` — remove the `("link", VBuiltin ...)` entry (~4424), `link_actors` (~2656), the `ai_links` field (~138) and its initializers (~1052, ~2240), and the crash-propagation block that walks `inst.ai_links` (~2576-2587)
- Modify: `docs/actors.md` AND `specs/lang/actors.md` (drifted duplicates — both must be edited)
- Modify: `CHANGELOG.md`
- Modify: `specs/todos/2026-08-12-links-and-exit-signals-unreachable.md` → `git mv` to `specs/progress/`

**Interfaces:**
- Consumes: nothing.
- Produces: removal only. No new symbols.

- [ ] **Step 1: Confirm nothing reaches it**

```bash
grep -rn "\blink\b" --include='*.march' stdlib/ test/ | grep -v "dist_link\|permalink\|linked" | head
grep -c '"link"' lib/typecheck/typecheck.ml
```
Expected: the second returns 0. If the first finds a `.march` file calling `link`, STOP and report — the premise is wrong and the decision needs revisiting.

- [ ] **Step 2: Remove the builtin and its machinery**

Delete these, in this order (compile after each if you prefer smaller steps):

```
lib/eval/eval.ml:4424   ; ("link", VBuiltin ("link", function ... ))
lib/eval/eval.ml:2656   let link_actors (pid_a : int) (pid_b : int) : unit = ...
lib/eval/eval.ml:2576-2587   the "Propagate crash to all linked actors" block
lib/eval/eval.ml:138    mutable ai_links : int list;
lib/eval/eval.ml:1052   ai_links = [];
lib/eval/eval.ml:2240   ai_links = [];
```

The crash-propagation block to delete is the one beginning `(* Propagate crash to all linked actors *)` and ending with the `) links;` that closes its `List.iter`. Deleting the `ai_links` field will make the compiler point at every remaining reference — let it drive you rather than grepping.

- [ ] **Step 3: Build and confirm it compiles**

```bash
DUNE_CACHE=disabled dune build --root . --force > /tmp/t5-build.log 2>&1; echo "exit=$?"
tail -20 /tmp/t5-build.log
```
Expected: exit 0. Any error naming `ai_links` means a reference was missed.

- [ ] **Step 4: Document the fault model in BOTH doc copies**

Add to the actors chapter, after the monitors section, in the chapter's existing voice — identically in `docs/actors.md` and `specs/lang/actors.md`:

```markdown
### Why there are no links

March's fault model is **monitors plus supervisors**, not BEAM's links and exit
signals. A monitor is one-directional and observational: the watcher receives
`Down(ref, pid, reason)` carrying `Normal`, `Killed`, or `Crash(msg)`, and
decides for itself what to do. Failure propagates *downward* through supervision
trees, never sideways between peers.

This is the same choice Akka made in dropping links for DeathWatch plus
supervision strategies. A reason-carrying `Down` gives a watcher everything a
link's exit signal would have told it, without the bidirectional coupling — and
without needing a `trap_exit` escape hatch to make that coupling survivable.
```

Verify the two copies match:
```bash
diff <(sed -n '/### Why there are no links/,/^## /p' docs/actors.md) <(sed -n '/### Why there are no links/,/^## /p' specs/lang/actors.md)
```
Expected: no output.

- [ ] **Step 5: CHANGELOG and lint**

Add under `## [Unreleased]`, `### Removed`:

```markdown
- **The unreachable `link` builtin is gone.** The interpreter carried a `link`
  builtin and `ai_links` crash-propagation machinery that the typechecker never
  exposed, so no March program could call it — `link(a, b)` failed with "I cannot
  find `link`". Rather than finish it, March commits to monitors plus supervisors
  as its fault model (see the actors chapter): a monitor's `Down(ref, pid, reason)`
  now carries `Normal`/`Killed`/`Crash(msg)`, which is what a link's exit signal
  would have told a peer, without bidirectional coupling or a `trap_exit` escape
  hatch. No program can regress, because none could reach it.
```

```bash
bash scripts/check-docs.sh
bash scripts/gen-docs-search-index.sh && bash scripts/gen-docs-search-index.sh --check
```
Expected: both exit 0.

- [ ] **Step 6: Run the suites**

```bash
./_build/default/test/run_eval.exe -e > /tmp/t5-eval.log 2>&1; echo "exit=$?"
grep -c "^  \[FAIL\]" /tmp/t5-eval.log
./_build/default/test/run_stdlib.exe -e > /tmp/t5-stdlib.log 2>&1; echo "exit=$?"
grep -c "^  \[FAIL\]" /tmp/t5-stdlib.log
```
Expected: both exit 0 with zero FAIL lines.

- [ ] **Step 7: Move the todo and commit**

`git mv specs/todos/2026-08-12-links-and-exit-signals-unreachable.md specs/progress/2026-08-16-links-removed-monitors-are-the-fault-model.md` and rewrite it as a decision record: the fork the todo posed, which option was taken, and the reason (#284's reason-carrying `Down` closed the capability gap that made links attractive). Record that option 1 remains available if peer-to-peer propagation is ever genuinely needed.

```bash
git add lib/eval/eval.ml docs/actors.md specs/lang/actors.md CHANGELOG.md docs/pagefind specs/progress/2026-08-16-links-removed-monitors-are-the-fault-model.md
git commit -m "eval+docs: remove the unreachable link builtin; monitors are the fault model"
```

---

### Task 6: Close-out and full verification

**Files:**
- Modify: `specs/progress/` entries from Tasks 1–5 if the final run contradicts anything they claim
- No code changes

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces: the verification record.

- [ ] **Step 1: Run the full battery**

```bash
uptime
DUNE_CACHE=disabled dune build --root . --force > /tmp/t6-build.log 2>&1; echo "build=$?"
scripts/run-tests.sh > /tmp/t6-suite.log 2>&1; echo "suite=$?"; tail -3 /tmp/t6-suite.log
dune build --root . @test/runtest 2>&1 | tail -5
bash scripts/actor-load.sh > /tmp/t6-load.log 2>&1; echo "load=$?"; grep -E "PASS|FAIL" /tmp/t6-load.log
bash scripts/check-docs.sh; echo "doclint=$?"
dune build --root . @types-check --force > /tmp/t6-types.log 2>&1; echo "types=$?"; grep -oE "[0-9]+ passed, [0-9]+ failed" /tmp/t6-types.log | tail -1
dune build --root . @grammar-check --force > /tmp/t6-gram.log 2>&1; echo "grammar=$?"
dune build --root . test/run_snapshots.exe && ./_build/default/test/run_snapshots.exe -e; echo "snapshots=$?"
git diff --stat test/snapshots/
```

All must pass. `@types-check` and `@grammar-check` MUST use `--force` — without it `@types-check` exits 0 on a zero-byte log and proves nothing. If a TIR snapshot diffs, STOP AND REPORT: nothing in this plan should change lowering.

Check `uptime` first. If load is above ~20, the `llvm_ir_validity_gate` and `native_node_discovery` fixtures may SIGKILL under memory pressure; the harness labels this "OOM killer or an external kill". Re-run any such failure in isolation before reporting it.

- [ ] **Step 2: Reconcile the ledger**

Confirm `specs/todos/` no longer contains any of the four race files and that `specs/progress/` has an entry for each. Confirm every progress entry's claims match what Step 1 actually produced — if a suite count differs, fix the entry rather than the memory of it.

- [ ] **Step 3: Commit and open the PR**

```bash
git add <the specific progress files you corrected>
git commit -m "specs: reconcile the actor race-fix ledger against the final verification run"
```

Open one PR for the whole branch. The description must state: which two todos were retired as already-fixed (Task 1) and on what evidence; which two races were genuinely fixed and how; that the cleanup-detach fixture is a guard rather than a red-green witness; and the links removal decision with its rationale.

---

## Self-Review Notes

- **Spec coverage:** four race todos → Tasks 1 (two retired), 2, 3, 4; links todo → Task 5; verification → Task 6. The `2026-07-24` memory-ordering audit todo is deliberately NOT in scope — it is a standing audit, not a defect, and folding it in would make this branch unreviewable.
- **Riskiest tasks:** Task 3 (Step 5 in particular — the deflected-sibling question is where this fix could trade a race for a silently-dead child) and Task 2 (if the unlock ever moves below the closure walk, any cleanup closure touching an actor API self-deadlocks).
- **Ordering:** Task 1 first (it changes what Tasks 2–4 believe is open). Tasks 2, 3, 4 touch different functions in the same file and must land in sequence to avoid rebuild conflicts, but are otherwise independent. Task 5 is fully independent of 1–4 and could run in parallel in a separate worktree. Task 6 last.
- **Evidence ruling (2026-08-16, human decision):** the review rubric governs over the plan's original guard-test approach. Tasks 2 and 4 ship NO new test, because neither race can be forced across two OS threads and a fixture there would pass identically before and after the fix. Task 3's test is kept only if the implementer proves it fails against the pre-fix runtime; otherwise it is deleted. Those fixes rest on their structural arguments, stated explicitly in each report. This is deliberate: a test that cannot fail against the broken code is not evidence, and shipping one implies a reproduction that never happened.
