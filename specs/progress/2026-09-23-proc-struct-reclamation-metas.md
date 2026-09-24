# Dead actors' metadata is reclaimed (proc-struct reclamation, closed)

**Closed 2026-09-23 with mechanism PR 2 (metas and tombstones).** Filed 2026-09-17 as a
`[P2]` todo, the design for item 5 of [[2026-08-11-actor-hardening-distributed-plane]]
("full epoch-based proc reclamation, replacing leak-don't-free"), the last open item in
that file. Written survey-first, as the parent asked. The design history below is kept as
it was written; what landed, and where it differs, is in "Mechanism PR 2 as landed" just
before "Survey: every holder of a `march_proc *`".

**Phase 1 shipped 2026-09-17** ([[2026-09-17-proc-ctx-released-at-death]]): the
execution context is freed at proc death.

**Mechanism PR 1 (the reclaim module + procs) shipped 2026-09-22**
([[2026-09-22-proc-struct-reclaimed]]): `runtime/march_reclaim.{c,h}` exists, a dead
proc's struct is freed after its grace period, and every holder in the survey below was
converted or argued bounded.

**Mechanism PR 2 (metas and tombstones) shipped 2026-09-23**: a dead actor's meta is
freed after its grace period, `g_actor_tbl` holds live metas only (the send-path cliff is
gone), and what a dead pid still needs is a 56 B tombstone. The one question PR 1 left
open (the fan-in cost of the reclaim calls) moved to
[[2026-09-23-reclaim-call-cost-on-fanin]]. A reference leak found on the way is
[[2026-09-23-pid-to-int-leaks-its-pid]].

**The survey changed the item.** Three findings, each of which moves the design:

1. **Procs are not the only thing retained per actor.** `march_actor_meta` is
   leak-don't-free too, for the *same* reason and with the same comment. (The `pid_index`
   table is chained *through* the meta — its `pididx_next` field — so it is not a third
   allocation, as the first draft of this file assumed.) Reclaiming procs alone does not
   give a churning node its memory back; it removes one of two terms.
2. **The hot readers rule out a lock.** `march_send` and `march_actor_call` — the two
   hottest paths in the actor runtime — read `meta->green_thread` to find the proc. Any
   design that makes proc lookup take a mutex puts a global lock on every actor send.
   This is what makes an epoch or hazard scheme the right tool *here*, where it is the
   wrong tool for the cold holders.
3. **77% of the proc struct is reclaimable with no reader-discipline change at all**, and
   that phase is independent of everything above.

So the item is really "a reclamation discipline for the actor-lifetime structures", with a
cheap independent first phase. This file specs the first phase in full and the rest to the
point where the next decision is measurable.

## Measurements

macOS/arm64, today:

```
sizeof(march_proc)        = 1136 B   of which ucontext_t = 880 B (77%)   residue = 256 B
sizeof(march_actor_meta)  =  272 B   (the pid_index chain lives inside it)
registry slot             =    8 B
sizeof(ucontext_t) on ubuntu-24.04 / alpine-aarch64 = measured 2026-09-22, see below
```

Retained per dead proc, before and after Phase 1:

| | before | after Phase 1 |
|---|---|---|
| task / main proc | 1136 B | **256 B** (4.4×) |
| actor (proc + meta) | 1408 B | **528 B** (2.7×) |

After Phase 1 the two remaining terms are about equal (256 B proc residue, 272 B meta),
so neither alone is worth a reclamation scheme. The meta size was read from a compile-time
diagnostic (`char (*)[sizeof(march_actor_meta)] = 1` against `march_runtime.c`), which
needs no link and no build-tree change.
glibc's `ucontext_t` embeds an extended FP-state reservation on aarch64, so the ctx share
on the Linux legs is expected to be *higher* than 77%, which would make Phase 1 alone
close to sufficient for procs.

At 1136 B, 50 000 peak procs retain 57 MB forever; 1 M spawns over a week retain 1.1 GB —
plus the meta and pididx terms, unmeasured. It is not reachable garbage (it is bounded by
peak concurrency and intentional), which is why nothing has forced it; a long-lived node
simply pays its high-water mark permanently.

## Analysis, 2026-09-22: the open measurements and both cost questions

### Measurements

`sizeof` read by compiling a two-line probe against `runtime/march_scheduler.h` in each
environment. The meta size came from the same compile-time diagnostic as before. It has
**grown from 272 to 304 B** since 2026-09-17.

| environment | `ucontext_t` | `march_proc` (Phase 1 residue) | `march_actor_meta` |
|---|---|---|---|
| macOS 26 / arm64 | 880 | 256 | 304 |
| ubuntu 24.04 / aarch64 (glibc, `march-sbx-test-ubuntu`) | **4560** | 256 | 304 |
| alpine 3.21 / aarch64 (musl) | **4560** | 256 | 304 |
| ubuntu 24.04 / x86_64 (glibc, emulated) | 968 | 256 | — |
| alpine 3.21 / x86_64 (musl, emulated) | 936 | 256 | — |

So on the Linux/aarch64 legs Phase 1 released 4560 of 4816 B per proc (95%), as the
earlier note predicted. What remains is the same everywhere, because none of it is
context:

- **Dead actor: 256 (proc) + 304 (meta) + 8 (registry slot) = 568 B.**
- **Dead task or `main`: 256 + 8 = 264 B.**

Measured slope of peak RSS against churn count, compiled `--opt 2`, macOS:

- **Actors:** spawn, send, kill. 50k → 122 MB, 200k → 212 MB, so about **600 B per dead
  actor**.
- **Tasks:** `Task.async` then `Task.await`, run sequentially, so there is never more than
  one live task. 200k → 65 MB, 400k → 127 MB, so about **308 B per finished task**.

That is 1M awaited tasks ≈ 300 MB and 1M churned actors ≈ 570 MB, never returned.

**A finding the survey did not predict: the leak is also a CPU cliff on the hottest
path.** `g_actor_tbl` has 256 fixed buckets whose chains are insert-only. Every meta
ever created stays linked, including the fresh meta `replace_stale_meta_locked` prepends
on address reuse. `find_meta`, which `march_send` and `march_actor_call` call on every
message, therefore walks O(actors ever spawned / 256) nodes. A long-lived server actor
sits at the *tail* of its bucket, behind every meta created after it.

Measured with 200k sends to one long-lived actor, before and after churning N short-lived
actors (same binary, same run):

| actors churned first | 200k sends |
|---|---|
| 0 | 46–56 ms |
| 50 000 | 127 ms |
| 200 000 | **3064 ms (60× slower)** |

`sample` during the slow phase puts about 606 of the roughly 700 non-idle samples in
`march_send` self time, which is the inlined chain walk. A node that has churned 1M actors
pays about 4000 cache-missing pointer chases per send.

### Cost question 1: does Phase 1 plus shrinking the meta suffice? **No.**

The survey of every meta reader (all 35 `find_meta*` / `find_or_create_meta` call sites
and the direct table walkers in `march_runtime.c`; no other runtime file resolves metas)
separates the fields into two groups.

- **Needed indefinitely after death,** because a dead pid can be queried by `pid_index`
  (an `Int` that holds no reference) at any later time:
  - `pid_index`
  - `terminal_set`, `terminal_reason`, `terminal_message`, `terminal_message_len`
  - `epoch`
  - the key the dead actor is found by

  The readers are `march_actor_terminal_reason` (distribution, no time bound),
  `march_monitor` on an already-dead target (it must deliver the right Down reason),
  `march_value_to_string` (a dead Pid still prints `Pid(n)`), and
  `march_is_cap_valid` / `march_send_checked`.
- **Needed only transiently after death:**
  - `green_thread`, `hcr_pin`, `dispatch_name_id`: the exiting green thread's own
    epilogue, and orphaned migrate markers disposed at the reap.
  - `supervisor`, `sup_child_index`: `march_supervisor_notify` during the death.
  - `spawn_cap`, `reg_names_pending`: `march_respawn_child`, up to the backoff cap after
    death.
- **Everything else** (about 230 of the 304 B: the drain, hot-reload, supervision
  bookkeeping, name index and cleanup/monitor lists) is meaningful only while the actor
  lives.

So the indefinite residue is a **tombstone of about 56 B** (plus any crash message, which
is retained today too). That is the same order as the 8 B registry slot per pid that
"Out of scope" already accepts. Shrinking the meta in place, without reclamation, would
take a dead actor from 568 to about 320 B (the 256 B proc struct stays). That is 1.8×,
not a fix. It also leaves the tombstones linked in `g_actor_tbl`, so the send-path cliff
above is untouched: the cliff scales with *entry count*, not entry size. Shrinking is part
of the answer, not an alternative to reclaiming.

### Cost question 2: can the hot readers avoid resolving a proc? **No, not without a compiler change.**

Read of `march_send` → `march_sched_send`, `march_actor_call`, and `march_actor_reply`:

- **`march_sched_send` needs the proc, not a mailbox.** Per message it touches:
  - `status`, for the DEAD check and again for the reap-vs-push recheck;
  - `mbox_lock`, `mailbox`, `mbox_tail` and the counts;
  - `mbox_limit` / `mbox_policy`;
  - `mbox_send_waiters`, for the BLOCK registration;
  - and then `march_sched_wake(target)`, which enqueues the proc itself: `next`, the
    deques, `owner_sched`, `pinned`, `wake_pending`.

  The reap-vs-push protocol is defined by `status` under `mbox_lock`, and the wake needs
  the run-queue linkage. Everything the send path reads *is* the live proc. A mailbox
  object split out of it would have to carry status, the lock, the waiter list and a way
  to wake its owner, which is the proc again under another name.
- **The caller's actor record cannot reach the meta or proc without a layout change.**
  The record is `[rc][tag|shape][dispatch][alive][state…]`. There is no spare word:
  - The pad holds the shape id.
  - `$e_alive` is a TIR `Bool` field that every compiled handler loads and writes back
    in its in-place `EReuse` (`lib/tir/lower_actor.ml`), so no runtime data can be packed
    into it.
  - Nothing marks an actor record at free time. `march_decrc` frees it like any record,
    so "free the meta when the record dies" has no hook.

  Adding a runtime-owned word is a lowering, `EReuse`, `get_actor_field`, migrate and
  `@compat` change for a runtime problem. It would also not help the `pid_index` readers,
  which hold no record at all.
- **The reply path is a third hot reader the survey missed.** `march_actor_call` stores
  the *caller's* `march_proc *` in the reply-ref (field 0). `march_actor_reply` sends to
  it with no liveness protocol at all. A handler may keep that ref in its state across
  turns (`march_actor_reply_retain`), and a caller can time out and exit first, so this
  holder is unbounded. It fires once per `Actor.call`.

So the hot readers stay hot, and the epoch is justified for them, as the survey argued.

### Survey additions (holders the 2026-09-17 table missed)

| Holder | Bounded by | Under reclamation |
|---|---|---|
| reply-ref field 0 (caller proc) | nothing: a handler may retain the ref | convert to the caller's **pid**, resolved via `g_registry` inside a critical section |
| Task word 5 (in-scheduler waiter) | the waiter's park, *except* that `task_wait_done`'s loop-top "done" return leaves word 5 naming the waiter | clear it on that path too; the trampoline loads and wakes inside a critical section |
| `march_task_cancel_by_id` via Task word 2 | nothing (already in the table as "Task object word 2") | store the **pid** and resolve via `g_registry` |
| BLOCK-policy sender holding `target` across `march_sched_park_self` | the target's reap drains the waiter list, but the *pointer* is used again after the park (`mbox_unlink_send_waiter(target, …)`) | re-resolve by pid after the park |
| `march_is_cap_valid`, `march_pid_of_int`, the one_for_all / rest_for_one strategies, `march_actor_stop`'s child walk, `delayed_restart_thread` | nothing: all dereference **`m->actor`** of a meta found by `pid_index`, whose record may already have been freed (the live actor's own reference is dropped at green-thread exit) | **by reading, a use-after-free today, not only under reclamation.** `march_pid_of_int` `incrc`s a record that may be freed. Not yet reproduced; the metas PR must reproduce it under ASAN before claiming the fix. A tombstone that carries no dereferenceable actor pointer closes all of these. |

### Chosen mechanism

**Epoch reclamation, quiescent-state flavoured on scheduler threads and explicit on every
other thread; stored raw pointers converted to pids; dead metas collapsed to a tombstone.**
Recorded here before implementation, as step 5 required.

1. **`runtime/march_reclaim.{c,h}`.**
   - Every OS thread that can resolve an actor-lifetime structure owns a slot. Slots are
     registered lazily on first use (any thread, since `march_send` can be called from
     anywhere) and recycled at thread exit through a `pthread_key` destructor. Slots are
     never freed.
   - A **scheduler thread** announces a quiescent state at the top of every `sched_loop`
     iteration (one store and a fence per *dispatch*) and goes offline while idle-sleeping.
     No green thread is running at that point, so no resolved pointer can be live. Its
     readers pay nothing per message.
   - **Any other thread** brackets a read with `march_reclaim_enter` / `march_reclaim_exit`
     (a store and a full fence on entry, a release store on exit). Enter/exit are also
     written at scheduler-thread sites; there they cost a TLS depth counter.
   - Retired objects go on an epoch-stamped list and are freed once every online slot has
     passed a later epoch. The list is polled from the retire path (amortised) and from the
     preemption daemon's tick, so a quiesced node drains completely.
   - The rule **"a resolved pointer is valid only inside the critical section"** becomes
     **"… and never across a context switch."** Every `swapcontext` that suspends a proc
     aborts if the thread's critical-section depth is non-zero, so a violation crashes at
     its cause. A path that must wait (the BLOCK sender, a foreign thread's sleep-poll)
     suspends its critical section around the wait and re-resolves by pid afterwards.
   - Why not a lock: the lock on the hot path is what finding 2 ruled out, and the
     scheduler-thread path here costs *less* than today's `find_meta`. Why not reader
     refcounts: that is two contended RMWs per send on the target's cache line, which
     fan-in (`fanin_flood`) concentrates.
2. **Procs (first mechanism PR).** At the reap, after `registry_remove` and the drain, the
   struct is retired rather than leaked. Before that, every unbounded holder is converted
   so that nothing can reach a dead proc after it is retired:
   - reply-ref field 0 and Task word 2 become **pids**, and `march_sched_find` (today
     caller-less) becomes their resolver;
   - timer WAKE/SEND entries carry the pid and resolve at fire time;
   - Task word 5 is cleared on every waiter exit;
   - `green_thread` readers run inside a critical section. The field is NULLed by the
     actor's own thread before its proc can die, so a new reader cannot reach a retired
     proc.

   This PR alone removes the 264 B per finished task and 256 of the 568 B per dead actor.
3. **Metas (second mechanism PR).**
   - `g_actor_tbl` holds **live** metas only. The meta is unlinked at death and retired,
     which removes the send-path cliff because chain length becomes O(live actors).
   - What a dead pid still needs moves into a ~56 B **tombstone**, reachable by
     `pid_index` through a dense, grow-only slot array (the same shape and accepted cost
     as `g_registry`, since `pid_index` is a dense counter) and by address through a cold
     secondary chain that only miss paths consult.
   - The tombstone carries the address as a key only and never dereferences it, which
     closes the `m->actor` use-after-free sites above.
   - The transient post-death fields (respawn's `spawn_cap` / pending names) move to the
     restart request that consumes them.

   Behaviour a test pins today (Down reason on a dead target, `Pid(n)` display, terminal
     reason by pid, cap epoch) is preserved.

What this deliberately does not change: the 8 B registry slot per pid ever, and the
tombstone per pid ever. Both are O(pids spawned) by the language's semantics (a dead
`Int` pid can be asked for its terminal reason forever). Both are ≥10× smaller than
today's residue.

### Mechanism PR 1 as landed (2026-09-22)

Built as specified above. Evidence, measurements and the per-site argument are in
[[2026-09-22-proc-struct-reclaimed]]. Where it differs from the text above, or found
something the survey did not:

- **A quiescent state needs no fence.** Only an offline-to-online transition does (the
  store-then-load Dekker pair with the reclaimer). An already-online scheduler thread
  that announces a newer epoch late only looks older to the reclaimer, which is
  conservative. So the per-dispatch cost is one release store, and only when the epoch
  has moved. The design text allowed a fence per dispatch.
- **`march_sched_find` had a dormant data race.** It read `g_registry` slots with a plain
  load while the reaper NULLs them under `g_registry_mu`. Harmless while it had no
  callers; it is now the resolver for every pid-holder, and ThreadSanitizer reported it
  on the first run. The slots are atomic now (release on add/remove, acquire on find).
  A reader holding a pre-growth snapshot can still get a DEAD proc back. That is safe:
  it cannot be freed inside the reader's critical section, and every caller treats DEAD
  as gone.
- **`march_task_cancel_by_id` could make sched_loop reap a parked proc.** It stored
  `PROC_DEAD` blindly. Landing between a park's `PROC_PARKED` store and its
  `swapcontext`, that store made sched_loop reap a proc still registered as a waiter
  (Task word 5, a BLOCK list, an fd-wait entry, a timer). Before reclamation that
  already recycled a live stack. With reclamation it becomes a use-after-free. It is now
  a compare-exchange from RUNNABLE or RUNNING only. Both documented behaviours (a queued
  proc still runs to completion; a running one's next yield overwrites the DEAD) are
  unchanged.
- **The BLOCK sender needed a flag.** After its park, the sender must know without
  dereferencing the target whether it is still linked in the target's waiter list,
  because the target may have been reaped and freed meanwhile. `march_proc.send_wait_linked`
  is set under the target's lock at registration and cleared by every unlinker after its
  last touch of the link. The reap drain is one of those unlinkers, and it clears the flag
  before the retire. Reading 1 inside a critical section therefore proves the target is
  not yet freeable.
- **`march_actor_reply`'s "legacy raw proc pointer" path is gone.** Nothing produces a
  bare proc pointer, and storing one is what reclamation forbids. A non-reply-ref value
  is now dropped.
- **Every suspending `swapcontext` checks the critical-section depth**, and so does every
  quiescent state. Stubbing out `march_reclaim_suspend` during the benchmark ablations
  aborted every run at the next dispatch, which is the check working.
- **Not converted, by argument:** the `MARCH_DEBUG` fault handler's registry walk. It
  runs in signal context, so it cannot enter a critical section (entering may allocate).
  On a scheduler thread it is already inside the implicit one. On any other thread it is
  a best-effort diagnostic on the way to `_exit`. There is a comment at the walk.

**Open (moved to [[2026-09-23-reclaim-call-cost-on-fanin]] when this item closed): a fan-in throughput cost the design did not predict.** On
`bench/actors/fanin_flood.march`, A/B against base on the same box (shuffled, load
average 11–50):

- **+8%** median wall time (129.8 → 140.7 ms, n=60).
- **+19%** on a 10× variant.
- **+1.9%** with one scheduler thread.

A build with every `march_reclaim_*` call a no-op matches base, so the cost is the calls
themselves, not the pid conversions. Single-threaded that is ~2 ns per send: the two
TLS-touching enter/exit calls in `march_send`, which the design accepted as "a TLS depth
counter". It could not be attributed to one entry point at 8 threads, and `sample` shows
no self time in them. The run is `mbox_lock` spinning on the sink, so the multi-thread
gap is probably contention timing, but that is not proven. Decide whether this is
acceptable, or whether scheduler-thread sites should drop the depth bookkeeping and keep
it only on foreign threads. The latter loses the "critical section held across a switch"
assertion for those sites. Details: [[2026-09-22-proc-struct-reclaimed]].

**Notes for the metas PR** (all addressed by PR 2; see "Mechanism PR 2 as landed").

- The procs PR relies on "`green_thread` is NULLed by the actor's own thread before its
  proc can die". The metas PR must keep an equivalent unpublish-before-retire order for
  `g_actor_tbl`.
- The same critical sections that now cover each `green_thread` load also cover the
  `find_meta` just before it, *except* in `march_send`, `march_actor_call`,
  `deliver_monitor_down`, `march_mailbox_size` and `march_actor_set_mbox_limit`. There,
  `find_meta` runs before `march_reclaim_enter`. Widen those sections to start before
  `find_meta` when metas become reclaimable.
- `march_actor_call` still reads `meta->call_tag_base` after its critical section.
- `stop_await_death`, `march_supervisor_notify` and the `m->actor` sites in "Survey
  additions" have no critical section at all yet.
- The kill-then-respawn fixture (`test/native/proc_reclaim_kill_respawn.march`) and its
  TSAN/ASAN recipe and red control are reusable as-is. Add meta traffic to it.

### Mechanism PR 2 as landed (2026-09-23): metas and tombstones

Built on PR 1's `march_reclaim`, as step 3 of "Chosen mechanism" specifies, with the
deviations listed below. Everything is in `runtime/march_runtime.c`.

**What changed**

- **`g_actor_tbl` holds live metas only.** The death claim (`death_claim_locked`, under
  `g_tbl_mu`) unlinks the meta. The unlink swings the predecessor's `tbl_next` (now
  `_Atomic`) with a release store and leaves the node's own link intact, so a reader
  standing on it walks on. Chains are O(live actors), so the send-path cliff is gone.
- **The tombstone** (`march_pid_entry`, 56 B) holds what a dead pid still needs:
  - the pid index and the capability epoch;
  - the terminal reason and message;
  - the record address, as a key only;
  - `live`, the meta while it is linked.

  It is reachable two ways, and is never freed:
  - by pid index, through a dense two-level array (`g_pid_chunks`: a fixed top array of
    4096-entry chunks, so it never moves);
  - for a dead actor, by record address, through `g_tomb`. This is a cold hash with one
    link per *distinct* address, repointed when a later incarnation there dies, so it is
    bounded by peak heap, not by churn. It grows by rebuilding and retiring the old table
    to `march_reclaim`.
- **`g_pididx_tbl` is gone.** `pididx_next`, `pididx_linked` and
  `replace_stale_meta_locked` went with it.
- **Metas are retired by reference count, not at the unlink.** A meta has three kinds of
  owner:
  - the table (one reference while linked, inherited by the claimant at the unlink);
  - the actor's green thread (one, from activation to its last access);
  - cold holders that must keep it across a switch or a wait (a pin, `meta_tryget` inside
    a critical section).

  The last `meta_put` retires it. The hot readers never touch the count. They resolve
  inside a critical section, which is enough because the count reaches zero only after the
  unlink, so a meta is unpublished before it is retired (the order "Notes for the metas
  PR" asked for).
- **Transient post-death fields moved to the restart that consumes them.**
  `reg_names_pending` and the spawn-site capability are stashed on the supervisor's slot
  (`march_sup_child.pending_names` / `pending_spawn_cap`, under `g_supervise_mu`) by
  `stash_child_for_restart`, and taken by `march_respawn_child`. A stash that is never
  taken is freed with the supervisor's meta. It used to leak by design.
- **A child finds its supervisor by the supervisor's tombstone** (`sup_pe`), not its
  record address. That makes it incarnation-precise and closes the "known gap" the
  synchronous absorb loop documented.
- **New stats.** `Scheduler.stat(10)` counts dead actors' metas freed; `stat(11)` counts
  those retired and waiting for their grace period.

**The rule, and every meta holder read against it**

> A meta found by lookup (`find_meta`, `march_pid_entry.live`) is valid only inside the
> reader's critical section, never across a context switch, unless the reader pinned it.
> Its `actor` may be dereferenced only by a caller holding its own counted reference to
> that record, or under `g_tbl_mu` while the meta is linked (the live actor's own
> reference is dropped only after the death claim).

The rule is in the header comment on `march_actor_meta`.

| Holder | How it satisfies the rule |
|---|---|
| `march_send` | `find_meta`, the `draining` read, the `green_thread` load and `march_sched_send` in one critical section, which now starts before `find_meta`. No lock, no count. |
| `march_actor_call` | The reply-ref and call message are built first (no switch). Then `find_meta`, the `green_thread` load, the `call_tag_base` rebase and the send run in one critical section, and the waits come after it. |
| `march_send_after`, `march_mailbox_size`, `march_actor_set_mbox_limit`, `march_actor_is_draining`, `march_set_actor_caps` / `march_actor_caps` | Resolve and use inside one critical section. |
| `deliver_monitor_down` | An early-out lookup in its own critical section. Then the decisive resolve, the watcher-liveness test and `march_sched_send_control`, all inside one critical section under `g_tbl_mu`: a linked meta means not dead. |
| `do_actor_death` | Claim and unlink under `g_tbl_mu` inside a critical section. It then owns the table's reference across the cleanups, the monitor walk and the notify (March code, switches), and puts it at the end. |
| `actor_green_thread` | Its own reference, taken by `activate_actor_green_thread`, put at both exits. It sets `green_thread` to `MARCH_GT_EXITED`, not NULL (see deviations). |
| `activate_actor_green_thread` | Caller in a critical section. `meta_tryget` for the thread's reference fails once the meta is retired (a supervised child killed by pid before its activation). The proc is published with a compare-exchange from NULL. |
| `march_actor_register` / `unregister`, `registry_retire_actor` | Resolve and use inside one critical section, under `g_registry_mu`. `register` resolves the meta before writing the forward entry, and gives a record that died meanwhile no name. |
| `find_or_create_meta` callers (`set_dispatch_id`, `set_call_base`, `register_supervisor`, `register_child`, `spawn_common`, the bind test seam) | Inside one critical section. `find_or_create_meta` refuses a dead record, so no meta is linked that nothing will unlink. |
| `march_monitor` | `find_or_create_meta`, then the linked test and either the monitor-list link or the tombstone read, all under `g_tbl_mu` inside one critical section. A dead target's reason comes from its tombstone, found through the meta or by address. |
| `march_register_resource` | The meta is resolved under `g_tbl_mu` inside a critical section, so a node is only linked onto a live meta. A dead actor gets no node: its closure reference is released instead of leaked. |
| `march_get_cap`, `march_pid_index_of`, `march_value_to_string` (Pid display) | Resolve inside a critical section and read the tombstone, which is never freed. A dead record the caller holds resolves through `g_tomb`. |
| `cap_live_meta_locked` (`is_cap_valid`, `send_checked`) | `pe->live` under `g_tbl_mu`. `send_checked` `incrc`s the record there (linked means the live actor's reference is held). The epoch is read from the tombstone. |
| `march_pid_of_int` | `pe->live` and the `incrc` under `g_tbl_mu`. A dead pid gets the dead-actor sentinel (see findings). |
| `march_actor_terminal_reason` | The tombstone. |
| `march_actor_pid_indices` | The lock-free walk runs inside one critical section. |
| `march_demonitor`, `hcr_snapshot` | Walk under `g_tbl_mu`. The snapshot pins each meta (and `incrc`s its record) across the publish. |
| Migrate markers (`mm->meta`) | Each marker holds its own reference, dropped by `migrate_msg_free`. The marker can be disposed at the target's reap, after the actor died. |
| `march_supervisor_notify` | Gets the supervisor pinned by `do_actor_death` (`meta_pin`: the meta plus a counted reference to its record), because the synchronous strategies run March code. |
| `delayed_restart_thread` | Pins the supervisor by pid index after the backoff park. A dead supervisor pins as nothing. `sup_still_live` reads `pe->live`, never the record. |
| One_for_all / rest_for_one sweeps, `march_actor_stop`'s child walk | Children are pinned by pid (`meta_pin_pe`) under `g_tbl_mu` while linked. `do_actor_death`, `march_actor_stop` and `stop_await_death` then use a counted record. |
| `march_actor_stop` (its own meta) | Pinned across the child teardown and the wait. `stop_await_death` dereferences only the record its caller holds. |
| `march_respawn_child` | The epoch comes from the dead incarnation's tombstone. The new child's meta is resolved and used, through activation, in one critical section with no switch in it. |

The "Survey additions" `m->actor` use-after-free sites are closed:

- `march_pid_of_int` and the strategies' and stop's child walks take a counted reference
  under `g_tbl_mu`, or none.
- `delayed_restart_thread` no longer touches the record.
- `march_is_cap_valid` never did.

**Deviations from the design, and findings**

- **Reference counts for ownership, on cold paths only.** The design said "unlinked at
  death and retired". Three parties can still hold the meta after the unlink:
  - the dying actor's own green thread, which keeps running after a kill from another
    thread;
  - the death processing, which runs cleanups;
  - supervision, stop and hot-reload, which run March code or wait.

  So "retire at the unlink" would have been a use-after-free, and "retire when the last of
  them is done" needs a count. The send path never touches it, which is the reader-refcount
  cost "Chosen mechanism" rejected.
- **The tombstone is allocated with the meta, not at spawn or death.** The supervise
  lowering (`lower_actor.ml`) calls `register_supervisor` and `register_child` on the
  supervisor's record *before* `spawn` runs on it. With the tombstone created at spawn, a
  child was linked to a supervisor that had none yet, and so was unsupervised: its first
  panic killed the process. The pid index is still assigned at spawn (`-1` until then;
  `pe_pid_or_0` keeps the old "0 before spawn" display).
- **`green_thread` is never republished after exit.** `activate_actor_green_thread` used
  to store the new proc after `march_sched_spawn_daemon` returned. A thread that ran to
  completion first (killed before activation, or woken by shutdown) had already cleared
  the field, and the late store republished a dead, soon-freed proc. It is now a
  compare-exchange from NULL, and the exiting thread stores `MARCH_GT_EXITED` (read as
  NULL through `meta_gt`). This was a latent PR 1 hole: it needed an actor to finish
  before its own `spawn` returned.
- **`march_pid_of_int` on a dead pid returns the dead-actor sentinel.** It used to return
  the dead meta's `actor`, whose record the actor's thread had already freed. Reproduced
  under ASAN in the container before the fix, as the survey asked:
  `test/native/pid_of_int_dead_pid.march` (spawn, kill, drop the Pid, then `pid_of_int`
  the index) is a heap-use-after-free WRITE in `march_incrc` from `march_pid_of_int` on
  **5/5** base runs, and **0/5** on this change. `ffi_test_actor_rc`
  (`actor_crash_rc_restore`) relied on the old answer to read a dead record's count. It
  now reads the address from the tombstone through a test seam
  (`march_test_actor_addr_of_pid`), which is safe there because the test holds its own
  Pid to the victim.
- **`pid_to_int` leaks a reference to its Pid.** This is not fixed here. It is why a
  record ever passed to it is never freed, and why the reproduction above avoids it:
  [[2026-09-23-pid-to-int-leaks-its-pid]].
- **A supervisor's `spawn_clo` cell is released when its meta is freed.**
  `march_actor_register_child` owns one reference; before, it was held forever.
- **Pre-existing, not changed:** a non-actor heap object at an address a dead actor once
  occupied prints as `Pid(n)` and reads as a dead monitor target. That was already true
  when dead metas stayed linked, and the address table keeps the same answer.

**Evidence**

The fixture `test/native/proc_reclaim_kill_respawn.march` now also drives meta traffic
every round:

- a monitor on the worker before the kill, and one after it (the tombstone);
- a registered name;
- a capability taken while the worker is live and used as it dies;
- after the kill: Pid display, `pid_from_int(pid_to_int(prev))`, `mailbox_size` and
  `is_draining`;
- a graceful `stop` instead of a kill every 16th round;
- a supervisor whose child is poisoned every round (one_for_one, backoff base 1 ms),
  replaced every 64th round while restarts are in flight.

Its golden asserts `metas freed true`. All sanitizer runs were in `march-sbx-test-ubuntu`
(Linux/aarch64, clang 18) with `MARCH_NUM_SCHEDULERS=4`, each build checked with `nm` for
`__asan_init` / `__tsan_init`.

| build | runs | result |
|---|---|---|
| ASAN (`MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1`) | 10 | **10/10 clean**, rc 0, `metas freed true` |
| TSAN (`MARCH_SANITIZE=thread`) | 40 | **0 heap-use-after-free**; no race signature absent from base (below) |
| **Red control**: `meta_put` frees at once (no grace period), TSAN | 10 | **heap-use-after-free in 6/10** |
| Red control, ASAN | 13 | **heap-use-after-free in 3/13** |

- **Red-control sites** (the top frame of each report): `march_send` (the `draining`
  read), `meta_gt`, `find_meta`'s chain walk, `march_actor_call`, and `march_monitor`.
  These are the hot readers the grace period exists for. ASAN's own words: a 264-byte
  region (the meta) freed by `actor_green_thread` and read by `march_monitor`.
- **TSAN against base.** Ten base-runtime runs of the same fixture give the identical
  signature set:
  - the preemption-flag reports;
  - `march_sched_send | sched_loop`;
  - `rec_field_raw | march_respawn_child` (a respawn writing the supervisor's state word
    while the supervisor reads it; 9/10 base runs, 38/40 here);
  - three rare record-shape pairs.

  Nothing is new.
- **ASAN sweep.** Every actor-related native fixture (73; network and two-node ones
  excluded) was compiled with this runtime under ASAN and run at 4 schedulers.
  **Zero AddressSanitizer reports**, and every golden matched, with four exceptions,
  none of them this change:
  - `sched_stress` hits ASAN's `Failed to mmap` (250k tasks, and ASAN builds never
    recycle stacks). Base fails identically.
  - `node_discovery` and `println_line_atomic` have known nondeterministic raw output.
  - `actor_init_params_schema` is a `--compile-so` rule the plain sweep does not model.

  `supervisor_deflected_crash_absorbed` matches once run under its rule's environment,
  with ASAN's startup warning filtered from the merged stderr.
  `actor_crash_rc_restore` needed its probe changed (see the findings above).
- **Suites.** `scripts/run-tests.sh` (every alcotest suite, including the z3-backed
  refinement suite) and `dune build --root . @runtest` (the dune-rule tests the script
  skips) are green.
  - `test/refine_audit/corpus.baseline` gained the new fixture's two audit lines.
  - `native_proc_reclaim_kill_respawn` and `native_actor_crash_rc_restore` first failed
    with `Permission denied` on a stray `test/native/*.ll`, left by compiling those
    fixtures by hand. That is the known `--compile`-on-a-fixture trap; removing the
    files cleared it.
  - macOS native: the fixture ran **100/100** at `MARCH_NUM_SCHEDULERS=4`.

**Retained memory.** Compiled `--opt 2`, macOS. This is heap in use after `spawn` / `send`
/ `kill` churn has drained, read with `heap(1)` from the live process and summed from its
size histogram. Peak RSS was too noisy at load 20–60 to separate the two builds.

| churned actors | base | this change |
|---|---|---|
| 0 | 1.41 MB | 1.41 MB |
| 50,000 | 16.8 MB | 5.25 MB |
| 200,000 | 65.6 MB | 18.5 MB |
| **per dead actor (slope)** | **341 B** | **93 B** |

- `heap`'s histogram names the terms. Base holds one 320-byte block per dead actor (the
  meta, 304 B rounded up by malloc). This change holds one 64-byte block per dead actor
  (the 56 B tombstone), plus the 32 KB pid chunks.
- The rest of the 93 B is terms the todo already accepted as out of scope: the
  scheduler's 8 B registry slot per pid, and its leaked growth arrays.

**The send-path cliff.** 200k sends to one long-lived actor, before and after churning N
short-lived actors, in the same run:

| churned first | base | this change |
|---|---|---|
| 0 | 46–54 ms | 42–53 ms |
| 50,000 | 482–514 ms | 38–49 ms |
| 200,000 | **3035–3267 ms** | **38–44 ms** |

**`bench/actors/fanin_flood.march`.** Compiled `--opt 2` against a compiler built at the
base commit (PR 1 merged), on the same box, run order shuffled per pair. Load average
20–60 throughout.

| | base | this change |
|---|---|---|
| fanin_flood, n=30 | 158.7 ms | 159.6 ms |
| fanin_flood, n=60 | 164.6 ms (p10–p90 137.8–196.2) | 163.7 ms (145.1–194.9) |
| 10× variant, n=20 | 1400.8 ms (1270.9–2038.2) | 1496.4 ms (1311.2–2051.1) |
| 10× variant, n=30 | 1437.9 ms (1193.0–1803.7) | 1473.3 ms (1294.2–1787.1) |

No measurable change on the base benchmark. The 10× variant reads +2.5% and +6.8% in two
sets, well inside the spread. The hot path gained no reclaim calls (each `enter` only
moved ahead of `find_meta`) and lost the chain walk over dead metas, which a fresh
process does not have. A base run was SIGKILLed twice across these sets, a
load artifact; runs with a non-zero exit are excluded from the n above.

## Survey: every holder of a `march_proc *`

The question that decides the design is which holders can still be dereferencing after the
reap branch runs. Seven of nine are bounded; two are not, and one of those two is hot.

| Holder | Bounded by | Safe today? |
|---|---|---|
| `sched->current` | the proc is RUNNING; RUNNING procs are never reaped | yes |
| run queues (`next`, pin queue, Chase–Lev deques) | in exactly one, popped before dispatch | yes |
| `g_registry` slots | `registry_remove` under `g_registry_mu`, strictly before the reap | yes |
| `mbox_send_waiters` / `send_wait_next` | waiter is PARKED, not DEAD; the reap branch drains it | yes |
| timer heap `ent.proc` (WAKE and SEND) | `g_timer_mu`; WAKE also `park_gen` | yes, but see below |
| fd-wait entries (`g_fdwait_head`) | entry is on the waiter's own stack, listed only inside `march_sched_wait_fd` | yes |
| resolver request (`resolve_req.proc`) | the `done`/`woke` handshake ([[2026-09-17-async-getaddrinfo]]) | yes |
| **`march_actor_meta.green_thread`** | **nothing** — and `march_send` / `march_actor_call` are two of its readers | **no** |
| **Task object word 2** | **nothing** — a March heap value the program holds as long as it likes | **no** |

`green_thread` is `_Atomic(march_proc *)`, cleared to NULL at both exits of
`actor_green_thread` and read from other OS threads by `march_send`, `march_actor_call`,
`march_send_after`, `march_supervisor_notify`, `march_actor_stop`,
`activate_actor_green_thread`, `march_mailbox_size` and `march_set_mbox_limit`. Clearing
it does not help a reader that has already loaded it. **Every one of those eight sites
already guards on NULL** (`if (gt)` / `if (!gt) …`), which is the property that makes a
handle conversion cheap in Phase 3 — the "that proc is gone" case is written everywhere
already.

The timer entries are "yes, but": they are safe *because* procs are never freed. The
`park_gen` ghost check dereferences the proc to decide the proc is stale, which under any
reclamation scheme is a use-after-free, so they convert with the rest even though nothing
is wrong with them today.

Two incidental findings worth recording: **`march_sched_find` has no callers** (only the
declaration and the comments that cite it), so the registry's lock-free-reader discipline
is currently maintained for the `MARCH_DEBUG` signal-context walker alone; and the same
"never unlinked or freed" discipline governs `g_actor_tbl` and the `pid_index` table, so
finding 1 above is not an inference — it is those files' own comments.

## Phase 1: move the `ucontext_t` out of the struct — SHIPPED 2026-09-17

What landed differs from the text below in one respect: the context is a plain
`calloc`/`free`, not a slab free-list. The stack free-list exists because mmap/munmap and
VMA churn were the cost being avoided; an 880-byte malloc has no such cost next to the rest
of a spawn (`getcontext`, `makecontext`, a stack re-arm), and *freeing* is what actually
returns peak memory to the allocator, where a free-list would have kept holding it. It is
freed in every build, ASAN included — there, a stale reader of a dead proc's context
becomes a reported use-after-free.

The design as written:

77% of the proc struct is a `ucontext_t`, and it is meaningful only while the proc can be
dispatched: `swapcontext` touches it when the proc suspends or resumes, both of which
require a live, dispatchable proc. The reap branch already says exactly this — "p's
ucontext/stack_base are stale/garbage; both are fine because a DEAD proc is never
dispatched or grown again" — which is the *same* sentence that licenses stack retirement
in [[2026-08-12-stack-recycling-on-proc-death]].

So Phase 1 inherits the existing safety argument wholesale rather than making a new one:
the stale cross-thread readers enumerated above touch `p->status`, `p->pid` and mailbox
fields, never `ctx`.

- `march_proc.ctx` : `ucontext_t` → `ucontext_t *`, taken from a LIFO free-list of
  fixed-size nodes — the shape of `g_stack_free`, and for the same reason (uniform size,
  so no per-entry bookkeeping). A slab, not the stack mapping: keeping it out of the
  PROT_NONE reservation avoids any interaction with `stack_reuse`'s re-arm.
- `sched_spawn_common` takes a node before `getcontext`/`makecontext`; the reap branch
  retires it beside `stack_retire` and NULLs the field.
- A NULL `ctx` means "dead, never runs again" — assert on every dispatch path rather than
  tolerate, so a regression is a crash at the right place rather than a corrupt switch.
- `MARCH_ASAN_BUILD` keeps the fresh-allocation path, as stack recycling does (the fiber
  annotations assume no reuse).

macOS/arm64: 1136 B → 256 B retained per dead proc, **4.4×**, with no change to how any
reader synchronises. Expected to be more on Linux. **If that residue is small enough for
the workloads that matter, close the item here** and leave the rest of this file as the
record of why the remaining terms were not worth their risk.

## Phase 2 (the real question): the actor-lifetime structures together

Procs, metas and pididx entries are retained for one reason — unsynchronised cross-thread
readers — and they will be reclaimed by one mechanism or not at all. Reclaiming procs
while metas leak leaves a churning node still growing, which is the property item 5 exists
to fix, so the unit of work is all three.

The mechanism cannot be a lock, because of finding 2: `march_send` and `march_actor_call`
resolve `green_thread` on every send. A global mutex there would show up immediately on
`bench/actors/fanin_flood.march`, which is the benchmark the phase-1 hardening work used
for exactly this path.

**This is where the epoch scheme item 5 named earns its place**, and the reason to state
it precisely: reader-side cost is two stores (enter / exit a critical section)
versus a contended mutex acquisition, and the reclaimer does the waiting. (Correction,
2026-09-22: the entry store needs a full fence after it, since the announcement must be
visible before the pointer load, and release/acquire does not order a store before a later
load. See "Chosen mechanism" for how scheduler threads avoid paying that per message.) The shape:

- Each OS thread that can dereference an actor-lifetime structure registers a slot
  (scheduler threads have one already; the helper and caller threads do not — `march_send`
  can be called from any thread, so the registry must be general).
- A reader publishes "in epoch E" before the load and clears it after the last
  dereference. The rule that matters is the one the original bug broke: **a resolved
  pointer is valid only inside the critical section**, and every converted site must be
  read against that sentence.
- The reaper retires a proc/meta/pididx entry onto an epoch-stamped list and frees a batch
  once every registered thread has been observed outside the epoch that retired it.

Before building it, two cheaper questions should be answered, because either could remove
the need:

1. **Does Phase 1 plus meta-shrinking suffice?** The same trick may apply to the meta: if
   most of its 53 fields are only live while the actor is, the retained residue can shrink
   without any reclamation. Measure the meta first.
2. **Can the hot readers avoid the lookup entirely?** `march_send` needs a mailbox, not a
   proc. If the mailbox were reachable from the actor record directly (which the caller
   holds alive by construction — it has a reference to send to), the hot path would not
   resolve a proc at all, and the remaining readers are all cold enough for a lock. This
   is the option that would make the epoch unnecessary, and it is the one worth costing
   first.

## Order of work

1. ~~Measure `sizeof(march_actor_meta)`~~ (272 B then, 304 B now) ~~and `sizeof(ucontext_t)`
   on ubuntu-24.04 and alpine/aarch64~~ (4560 B on both; see "Analysis, 2026-09-22").
2. ~~Phase 1~~ — **shipped 2026-09-17**: [[2026-09-17-proc-ctx-released-at-death]].
3. ~~Decide whether to continue, and record the decision here either way.~~ **Decided
   2026-09-22 by the repo owner: continue past Phase 1.** The unit of work stays all three
   structures (procs, metas, pididx entries); steps 4–5 below proceed in order, and closing
   the item with measurements remains an acceptable outcome if the analysis says
   reclamation is not worth its risk.
4. ~~If continuing: cost question 2 above (mailbox reachable without the proc).~~ Answered
   2026-09-22: no. The send path needs the whole live proc, and the record has no word to
   reach it by. Question 1 is also answered no. See "Analysis, 2026-09-22".
5. The epoch scheme, for the holders question 4 leaves hot. Design recorded in "Chosen
   mechanism": ~~procs first (one PR)~~ **landed 2026-09-22**
   ([[2026-09-22-proc-struct-reclaimed]]), then ~~metas and tombstones (one PR)~~
   **landed 2026-09-23** (this file, "Mechanism PR 2 as landed").

## Evidence any reclamation phase must produce

A green suite is not evidence here. The original corruption was intermittent and only
showed under kill-then-immediately-respawn, so the bar is:

- that pattern under **ThreadSanitizer** (it is what identified the race as genuine, not
  benign), and
- under **ASAN in the Linux container**
  ([[2026-09-14-live-actor-rc-and-linux-container-asan-recipe]] has the recipe — and note
  `tcache_thread_shutdown(): unaligned tcache chunk` on that leg means a UAF write long
  before), and
- `bench/actors/fanin_flood.march` against a compiler built at the base commit, same box
  (absolute numbers prove nothing; see the benchmark notes in `specs/benchmarks.md`).

## Out of scope

- The deliberately leaked old registry arrays on growth — O(log₂ max pid) of them.
- Stack reservations: Task 12 recycles them; this file does not touch that.
- The registry array's own growth (8 B per pid ever spawned, since pids are monotonic and
  never reused). It only becomes the dominant term after everything above is reclaimed;
  the sparse hash-chained map `march_runtime.c` already uses for `pid_index` is the
  answer, and it should be filed separately if anyone gets there.

## What would make this fail

A reader that resolves a proc, gets a live one, and keeps the pointer across a park or a
critical-section exit. The original bug was not that someone freed a proc — it was that a
pointer outlived the fact it named. Whatever mechanism lands, that sentence goes in
`march_scheduler.h` next to the field, and every converted site is read against it.
