# O(1) `find_meta_by_pid_index` via insert-only pid_index -> meta table

Task 15 of the actor-system-hardening plan
(`.superpowers/sdd/2026-08-11-actor-system-hardening/`).

## The fix

`runtime/march_runtime.c`:

- Added `g_pididx_tbl[256]` (`_Atomic(march_actor_meta *)`), a second
  side table keyed by `pid_index` alongside the existing `g_actor_tbl`
  (keyed by actor pointer). Same insert-only, lock-free-read discipline as
  `g_actor_tbl` (Task 10): metas are never unlinked or freed, so a reader
  that acquire-loads a bucket head and walks the new `pididx_next` chain
  link needs no lock.
- `pididx_insert(meta)`: under `g_tbl_mu` (same lock `g_actor_tbl`'s writer
  uses), links `meta` onto its `pid_index % 256` bucket and release-stores
  the new head. Called from `march_spawn` immediately after
  `meta->pid_index` is assigned.
- `find_meta_by_pid_index` replaced its old O(total actors) body — a full
  scan of every `g_actor_tbl` bucket, under `g_tbl_mu` for the whole
  walk — with an O(1) acquire-load of one `g_pididx_tbl` bucket followed by
  a walk of that bucket's (typically short) chain. No lock held during the
  walk.
- **Duplicate-match semantics preserved:** the old scan returned the
  *last* match if `pid_index` were ever duplicated; `pid_index` is drawn
  from `g_next_pid_index`, an atomic counter, so it's unique per spawn —
  first-match (what the new O(1) lookup returns) was always equivalent.

### Bonus fix (pre-existing, flagged in Task 10's review)

`march_spawn` wrote `meta->pid_index` as a plain (non-atomic, unlocked)
store, while the old `find_meta_by_pid_index` read it under `g_tbl_mu` —
one-sided locking, formally a data race/UB, and (independent of locking) a
real window where a meta reachable via `g_actor_tbl` between
`find_or_create_meta` and the `pid_index` write still read `pid_index==0`.

Fixed two ways:
1. **Structural, for the pididx lookup path:** `pididx_insert` is called
   right after the `pid_index` write, in the same thread, so every meta
   reachable via `g_pididx_tbl` was fully assigned its `pid_index` before
   the insert's release store published it — `find_meta_by_pid_index`'s
   readers get a correct value by construction, no atomics needed for that
   specific comparison.
2. **`pid_index` is now `_Atomic int64_t`** (relaxed load/store) to close
   the race for every OTHER (non-pididx) reader that looks up a *foreign*
   actor's meta and reads `pid_index` directly — see the audit below.

#### `pid_index` reader audit

| Site | Reads whose meta? | Cross-thread? | Fix |
|---|---|---|---|
| `find_meta_by_pid_index` (comparison inside the pididx walk) | via `g_pididx_tbl` chain | Ordered by pididx insert's release/acquire | relaxed load (ordering already provided by the chain) |
| `march_respawn_child` → `new_meta->pid_index` | own supervisor-thread's just-spawned child | No — same thread wrote it moments earlier via `march_spawn` | relaxed load (belt-and-suspenders) |
| `do_actor_death` → `meta->pid_index` (dist-monitor fire) | actor's own meta, read on its own green thread at exit | Written by the spawning thread before the green thread started; visibility relies on the (unsynchronized) thread-start handoff | relaxed load — closes the formal race |
| `march_pid_index_of` (`march_actor_register_child`'s Pid-store path) | just-spawned child, read by the spawning/supervisor thread | No — synchronous, same thread as `march_spawn` | relaxed load |
| `march_get_cap` → `w[3] = meta->pid_index` | **arbitrary/foreign actor**, `pid` argument can be any live Pid another actor holds | **Yes** — the actor that issues the cap is generally not the actor that was spawned | relaxed load — genuine fix |
| `march_send_checked` → `meta->pid_index != pidx` | **foreign actor** named by a Cap that arrived via message from elsewhere | **Yes** | relaxed load — genuine fix |
| `march_value_to_string` (`Pid(n)` display) → `meta->pid_index` | **any actor whose Pid value is being shown**, including Pids received in messages from other actors | **Yes** | relaxed load — genuine fix |

Three sites (`march_get_cap`, `march_send_checked`, `march_value_to_string`)
are genuine cross-thread foreign-meta reads that never go through the
pididx table's publication — given that, `pid_index` was made `_Atomic`
outright (relaxed ops suffice: the write always happens before any other
actor could obtain a Pid/Cap referencing the meta, since `march_spawn` is
synchronous and returns only after the write; the atomic conversion exists
to remove the formal data race / UB, not to fix an observed staleness bug).

### `march_sched_init`/harness re-init

`g_pididx_tbl` lives in `runtime/march_runtime.c`, not
`runtime/march_scheduler.c` — the C scheduler-churn test harnesses
(`test_scheduler_churn.c` etc.) that re-init the scheduler for repeated
in-process segments never touch this table. A compiled March program or
the interpreter runs `march_spawn` (and thus `pididx_insert`) once per
process, so no re-init path is needed.

### `find_meta_by_pid_index` callers audited (all still correct)

`march_respawn_child`, the `one_for_all`/`rest_for_one` restart loops, and
`march_pid_of_int` (`march_is_cap_valid` too) all call
`find_meta_by_pid_index` expecting the single actor that currently owns a
given `pid_index` — none relied on the old scan's last-match-wins duplicate
behavior, which (as above) was always vacuous since `pid_index` is unique.

## Verification

- `dune build --root . bin/main.exe` — clean build.
- `scripts/run-tests.sh -q` — all suites passed (58 stdlib tests + others).
- `dune build @test/runtest --root .` — 572 tests run, all green (march-codegen suite).
- `bash scripts/actor-load.sh crashloop` — `PASS` before and after the fix.
  Wall time: pre-fix (temporary file-swap to the base commit's O(n) scan,
  not committed) 146-213ms across 3 runs; post-fix 146-213ms across 3 runs
  — flat, within noise, as expected: the crashloop scenario's actor count
  is small enough that the O(n) vs O(1) difference doesn't show up in wall
  time. The fix's value is asymptotic (bounded lookup cost regardless of
  total actor count ever spawned in the process), not a measured win at
  this scale.

## Fix-up: actor heap-address reuse corrupted the pididx chains

A follow-up review caught a Critical bug in the fix above: `march_spawn`'s
`find_or_create_meta(actor)` matches by raw pointer, and march-heap objects
are plain `malloc`/`free` — a dead actor's freed address can be reused by a
new actor (kill/respawn churn, exactly the crashloop shape, makes
same-size reuse likely). `find_or_create_meta` then returns the DEAD
incarnation's meta; the original patch overwrote its `pid_index` and
called `pididx_insert` on it a SECOND time. `g_pididx_tbl` is insert-only
(readers walk it lock-free assuming a node is linked exactly once); a
second insert overwrites `pididx_next`, silently splicing the meta's old
bucket chain into its new bucket's tail — any lock-free walker of the old
bucket wanders into the new bucket instead of stopping, and repeated reuse
could even close a cycle, hanging `find_meta_by_pid_index`. The OLD O(n)
scan was immune (it re-walked `g_actor_tbl` and compared the field fresh
every call, no linking involved).

Fix: added `int pididx_linked` to `march_actor_meta`, set the first time a
meta is linked into `g_pididx_tbl`. `march_spawn` now does
reuse-detection + `pid_index` assignment + the pididx publish inside one
`g_tbl_mu` critical section; `pididx_insert` was split into a `_locked`
core so the sequence is atomic. When `find_or_create_meta` hands back an
already-linked (stale) meta, `replace_stale_meta_locked(actor, stale)`
allocates a FRESH meta for the new incarnation, copies over
`dispatch_name_id`/`call_tag_base` (the only two fields compiled code can
write onto a not-yet-spawned meta, via `march_actor_set_dispatch_id`/
`march_actor_set_call_base`, both of which always run before `march_spawn`
per their own existing comments), and PREPENDS it to the actor's
`g_actor_tbl` bucket without unlinking the stale meta — `g_actor_tbl`
stays insert-only, `find_meta` returns the fresh meta first (shadowing the
stale one) for every future lookup. The stale meta's `green_thread` was
already `NULL` (release-stored on both of `actor_green_thread`'s exit
paths, before `do_actor_death` — which is what makes the freed address
eligible for reuse in the first place), so any reader still reaching the
stale meta during the shadow window sees "no green thread" and returns
`None`, matching pre-existing already-dead-actor behavior.

Also fixed: a stale comment at `g_actor_tbl`'s declaration still listed
`find_meta_by_pid_index` among the walkers that take `g_tbl_mu` (no longer
true — it's lock-free since this task).

Full detail (including the `pid_index==0` pre-spawn-window closure
argument, the `test_scheduler_churn.c` grep evidence for the no-re-init
claim, and the fanin-flake investigation) is in
`.superpowers/sdd/2026-08-11-actor-system-hardening/task-15-report.md`.

Re-verification: `dune build --root . bin/main.exe`; `scripts/run-tests.sh
-q` (58 stdlib tests, green); `dune build @test/runtest --root . --force`
(849 compiler + 572 codegen tests, green); `bash scripts/actor-load.sh
crashloop` x5 (all PASS, 152-213ms); `bash scripts/actor-load.sh` (full
harness) x2 (all four scenarios PASS both times).
