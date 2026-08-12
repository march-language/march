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
