# `[P2]` Reclaiming the `march_proc` struct — and what the survey says it is really part of

Filed 2026-09-17 as the design for item 5 of
[[2026-08-11-actor-hardening-distributed-plane]] ("full epoch-based proc reclamation,
replacing leak-don't-free"), the last open item in that file. Written survey-first, as the
parent asked.

**Phase 1 shipped 2026-09-17** ([[2026-09-17-proc-ctx-released-at-death]]): the
execution context is freed at proc death. What remains below is Phase 2 and the decision
in front of it, with the measurements now taken.

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
   mechanism": procs first (one PR), then metas and tombstones (one PR).

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
