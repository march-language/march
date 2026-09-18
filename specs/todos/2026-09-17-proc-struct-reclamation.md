# `[P2]` Reclaiming the `march_proc` struct — and what the survey says it is really part of

Filed 2026-09-17 as the design for item 5 of
[[2026-08-11-actor-hardening-distributed-plane]] ("full epoch-based proc reclamation,
replacing leak-don't-free"), the last open item in that file. Written survey-first, as the
parent asked.

**The survey changed the item.** Three findings, each of which moves the design:

1. **Procs are not the only thing retained per actor.** `march_actor_meta` and the
   `pid_index` side-table entry are leak-don't-free too, for the *same* reason and with
   the same comment. Reclaiming procs alone does not give a churning node its memory back;
   it removes one of three terms.
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
sizeof(march_proc)  = 1136 B     of which ucontext_t = 880 B (77%)     residue = 256 B
registry slot       =    8 B
sizeof(march_actor_meta)  = NOT MEASURED — ~53 fields; it is file-static in
                            march_runtime.c, so the measurement wants a temporary
                            printf or a dwarfdump of a built object
sizeof(ucontext_t) on ubuntu-24.04 / alpine-aarch64 = NOT MEASURED (Docker was down)
```

Take the two missing numbers first; they decide how much of this file is worth doing.
glibc's `ucontext_t` embeds an extended FP-state reservation on aarch64, so the ctx share
on the Linux legs is expected to be *higher* than 77%, which would make Phase 1 alone
close to sufficient for procs.

At 1136 B, 50 000 peak procs retain 57 MB forever; 1 M spawns over a week retain 1.1 GB —
plus the meta and pididx terms, unmeasured. It is not reachable garbage (it is bounded by
peak concurrency and intentional), which is why nothing has forced it; a long-lived node
simply pays its high-water mark permanently.

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

## Phase 1: move the `ucontext_t` out of the struct (independent, no discipline change)

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
it precisely: reader-side cost is two relaxed stores (enter / exit a critical section)
versus a contended mutex acquisition, and the reclaimer does the waiting. The shape:

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

1. Measure: `sizeof(march_actor_meta)`; `sizeof(ucontext_t)` on ubuntu-24.04 and
   alpine/aarch64. Record all three here. One command each.
2. Phase 1 (`ctx` into a slab). Witness: a C unit test that spawns and reaps 100 000 procs
   and asserts RSS growth under a bound — `march_stat_counters` already counts
   `STACKS_RECYCLED`; add `CTX_RECYCLED` beside it. `scripts/actor-load.sh`'s four
   scenarios unmoved.
3. **Decide from that number whether to continue, and record the decision here either
   way.** A closed item with a measurement is a better outcome than an epoch nobody needed.
4. If continuing: cost question 2 above (mailbox reachable without the proc). It is a
   read of `march_send` / `march_actor_call` / `march_sched_send`, not a change.
5. Only then the epoch scheme, and only for whichever holders question 4 leaves hot.

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
