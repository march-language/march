# Per-actor introspection: push mailbox alarm, state inspection, tracing

**Date:** 2026-09-23
**Status:** design, nothing built.
**Closes (when built):** the three open pieces of
[`specs/todos/2026-08-12-per-actor-introspection-and-alarms.md`](todos/2026-08-12-per-actor-introspection-and-alarms.md).
**Method:** every claim in §1 was checked on 2026-09-23 against `origin/main`
`154cf1754` by opening the cited file. Where something could not be checked, the
text says so. The benchmark numbers in §1.6 were taken on the shared development
Mac at load average 69–86, and they carry that caveat.

---

## Decisions needed

1. **Build order.** *Recommendation:* (a) the push alarm first, then (b) state
   inspection as a rendered `String`, then (c) tracing. The typed state snapshot
   (b2) comes last, or never. *Why:* (a) is the smallest piece and needs no
   compiler change. Its check sits under a lock the sender already holds and
   reads a counter that already exists (§1.2), so the argument that the disabled
   feature costs nothing is almost free to make. (b) as a string shares no heap
   value across actors, so it has no linearity or RC hazard. It also replaces
   `get_actor_field`, which is racy (§1.4). (c) is the largest piece and touches
   the most event sites.
2. **Who may inspect or trace.** *Recommendation:* the alarm takes the existing
   `Cap(Actor.Introspect)`, because it answers the same question as
   `Actor.over_mailbox`, which already takes that cap. State inspection and
   tracing take a **new proof cap `Cap(Actor.Debug)`**, minted from `Cap(IO)`
   the same way. *Why:* enumeration tells you that an actor exists and how deep
   its queue is. State and message payloads tell you what it holds, which can
   include session keys, credentials or user data. A monitoring role that
   legitimately holds `Introspect` should not be able to read those. The
   alternative is to reuse `Introspect` for everything: one fewer cap, and all
   three features ride the D31 decision (distributed-authority plan) unchanged.
3. **What `get_state` returns.** *Recommendation:* v1 returns a `String`
   rendering (`Actor.inspect_state(c, pid, timeout_ms) : Result(String,
   InspectError)`). A typed `Result(s, InspectError)` on a `Pid(s)` follows only
   with a runtime shape check (§4.3). *Why:* a `Pid(a)` from
   `Actor.pid_from_int` or `Actor.list` has a caller-chosen `a`, the same
   minting door `Config` closed with codecs (§1.5). A hot reload can also change
   the state's shape under a `Pid(s)` whose `s` is the old type. Returning a
   typed value without a check is memory-unsafe on the compiled backend.
4. **Trace delivery: push or pull.** *Recommendation:* pull. The runtime keeps
   a bounded ring of trace events per trace session and counts what it drops.
   March code drains it with `Trace.drain(session)`. A small stdlib actor can
   turn that into push on a timer. *Why:* push means building a March value and
   sending it from the traced actor's own send path, which puts allocation,
   RC traffic and a second mailbox lock on exactly the path being observed. A
   ring slot write is a fixed-size store plus one fetch-add, paid only while
   tracing is on.
5. **`get_actor_field`'s future.** *Recommendation:* move it to the
   stdlib-only gate (`Typecheck_builtins.stdlib_only`) behind the Debug cap
   once `inspect_state` lands, and migrate the ~20 test fixtures that use it to
   read supervisor child pids. *Why:* see §1.4. This is a follow-up, not part of
   any stage here. It needs its own todo if accepted.
6. **Acceptance bound for "the disabled feature costs nothing".** *Recommendation:*
   the instruction-level argument (no new atomic RMW, no new cache line written
   on the send path) is the primary gate. The measured gate is a same-box
   interleaved A/B of `bench/actors/fanin_flood.march`, n ≥ 40 per arm, taken at
   load average < 10. It fails if the `MARCH_NUM_SCHEDULERS=1` median moves by
   more than 1%, or the 8-scheduler median by more than the base's own p25–p75
   half-width. *Why:* at today's load the 8-scheduler IQR is about ±10% (§1.6),
   so a flat "≤ 1%" at 8 schedulers cannot be measured on this box. The
   1-scheduler run is where a per-send instruction cost shows up without lock
   hand-off noise.

---

## 0. The problem

The todo asks for three things BEAM has and March lacks:

- **(a)** `erlang:system_monitor`'s `long_message_queue`: a notification *when* a
  mailbox crosses a threshold. Today March can only poll for it.
- **(b)** `sys:get_state/1`: read a live actor's state without editing the
  program.
- **(c)** `erlang:trace`: watch one actor's message flow (send, receive, spawn,
  exit) without editing the program.

There is one hard constraint, the todo's own: **none of this may re-serialise
the send path.** Task 10 took `find_meta` off `g_tbl_mu` to keep sends off the
global mutex, and the process-enumeration work (2026-09-08) was built around not
undoing that.

Since the todo was filed, four things have landed that constrain the design:
epoch reclamation of proc structs, the `on_stop` callback, typed Config keys, and
the distributed-authority/hot-reload epoch plan. §1 covers each.

---

## 1. Ground truth

### 1.1 What already shipped from this todo

- **Enumeration, `Actor.list(c)`** (`specs/progress/2026-09-08-process-enumeration.md`).
  The builtin is `actor_pid_indices() : List(Int)` (`runtime/march_runtime.c:8582`),
  a lock-free walk of `g_actor_tbl`'s bucket heads, the same walk `find_meta` does.
  The list is sorted and deduplicated, and a meta is skipped when
  `terminal_set` is set (`:8606`). It deliberately does *not* gate on
  `is_alive`, which is 0 until a just-spawned actor's thread first runs. The
  stdlib wrapper is `Actor.list(_c : Cap(Actor.Introspect))`
  (`stdlib/actor.march:202`), which maps `pid_of_int` over the list.
- **The polled alarm** (`specs/progress/2026-09-10-mailbox-alarm-polled.md`).
  `Actor.top_by_mailbox(c, n)` (`stdlib/actor.march:221`) and
  `Actor.over_mailbox(c, threshold)` (`:241`) are stdlib-only. Each one is
  `List.map` of `mailbox_size` over `Actor.list(c)`, then a sort or a filter.
  `mailbox_size` is `march_mailbox_size` (`runtime/march_runtime.c:8262`): a
  `find_meta`, then an acquire load of `green_thread` and
  `march_sched_mbox_count` inside one reclamation critical section.
- **The gate on both.** `Cap(Actor.Introspect)` is a proof cap declared at
  `stdlib/actor.march:62` and minted only by `Actor.introspect(io : Cap(IO))`.
  The raw builtins (`pid_of_int`, `actor_pid_indices`, `actor_whereis`,
  `actor_registered`) are on the stdlib-only list
  (`lib/typecheck/typecheck_builtins.ml`, `stdlib_only`). This is D31 of
  `specs/plans/2026-09-21-distributed-authority-and-deploys-plan.md`.
  `mailbox_size` itself is **not** gated. It needs a Pid, and holding a Pid is
  already authority.

### 1.2 The send path, precisely

"Lock-free send" is true of the **lookup**, not of the enqueue. The whole path:

1. `march_send` (`runtime/march_runtime.c:5816`) checks `actor_alive_load`,
   then calls `find_meta(actor)`. `find_meta` (`:2742`) is a lock-free
   acquire-load walk of the bucket chain, never `g_tbl_mu`. Next come an acquire
   load of `meta->draining` and, inside `march_reclaim_enter/exit`, an acquire
   load of `meta->green_thread` and the call to `march_sched_send`.
2. `march_sched_send` (`runtime/march_scheduler.c:2636`) mallocs a node, then
   takes the **target's own spinlock** `mbox_lock` (`mbox_lock_acquire`,
   `:998`, a CAS spin). Under it, it checks the limit and policy, rechecks
   PROC_DEAD, calls `mbox_push_node`, reads the status, and releases. The wake
   happens after the release.
3. `mbox_push_node` (`:1019`) links the node into a plain singly-linked FIFO
   (`mailbox`/`mbox_tail`) and does
   `atomic_fetch_add_explicit(&p->mbox_count, 1, relaxed)` plus the same on
   `p->user_mbox_count` for user messages.

So:

- **There is a length counter today, and it is exact.** `mbox_count` (user plus
  control) and `user_mbox_count` (user only) are `_Atomic int64_t` fields on
  `march_proc` (`runtime/march_scheduler.h:232`, `:238`). They are modified
  **only under `mbox_lock`** (push `:1030`, pop `mbox_pop_queue` `:1044`) and
  read lock-free by `mailbox_size`, `wait_idle` and the idle daemons. The
  atomics exist for those lock-free readers. Every writer is already serialised
  by the lock.
- **The mailbox is not a lock-free MPSC queue.** It is a spinlocked list, and
  senders to one target already serialise on that target's `mbox_lock`. Global
  serialisation is what was removed (`g_tbl_mu`). Per-target serialisation was
  never removed. The reclaim progress note measured fanin_flood as "dominated
  by `mbox_lock` spinning on the sink" (`specs/progress/2026-09-22-proc-struct-reclaimed.md`).
- **Consequence for (a):** a threshold check placed inside `mbox_push_node`
  reads a count the sender has just computed, under a lock it already holds,
  and a threshold field on a cache line it has just written. It adds no new
  atomic RMW and no new contended line. It also re-serialises nothing, because
  the lock is already there.

### 1.3 Proc lifetime: epoch reclamation

`runtime/march_reclaim.{c,h}` (`specs/progress/2026-09-22-proc-struct-reclaimed.md`)
states the rule this design must follow:

> A resolved `march_proc *` is valid only inside the reader's critical section,
> and never across a context switch.

Scheduler threads are in an implicit critical section between quiescent
states. `march_reclaim_quiescent()` is announced at the top of every
`sched_loop` iteration (`runtime/march_scheduler.c:1690`), immediately before
`march_signal_drain()` (`:1699`). Other threads bracket reads with
`march_reclaim_enter/exit`. Every suspending `swapcontext` aborts if the thread
is inside a critical section.

Constraints this puts on the design:

- **An inspector cannot resolve a pid to a proc and then wait.** Any wait
  parks, and a park inside a critical section aborts. So (b) cannot "resolve,
  lock, copy the state, unlock". It must either finish entirely inside one
  critical section with no park, or go **by message to the actor**. §4 does the
  latter for a separate reason (§1.4).
- **Anything queued for later processing must hold a pid, not a proc
  pointer.** The timer heap, reply refs and task word 2 were all converted to
  pids for this reason (reclaim note, table rows "Timer heap", "Reply-ref
  field 0"). The alarm's pending list (§3) follows the same rule.

### 1.4 Actor state: representation and the existing reader

**Compiled.** `lower_actor` (`lib/tir/lower_actor.ml:55-68`) lays an actor out
as one record, `Name_Actor`:

- field 0 is `$d_dispatch` and field 1 is `$e_alive`;
- then come the state fields, **inline and sorted by name**;
- under `--hot-reload` there is instead a single field `$f_state`, a pointer to a
  separate `Name_State` record.

A handler **moves** the state fields out of the `Lin` actor record, runs the
body, and writes the new fields back with an in-place `EReuse` (`:70-80`, and
`lib/tir/llvm_emit_alloc.ml:630-660`). While a handler runs, the struct's field
words therefore name values the handler may already have consumed.

The header `pad` word holds the record's **shape id**:

- It is stamped once at allocation (`llvm_emit_alloc.ml:247-259`, via
  `emit_set_shape`, for actor structs only).
- It survives every state update, because the actor-struct `EReuse` arm stores
  the tag with `emit_store_tag_keep_pad` (`:640-652`).
- The shape registry is `march_record_shape_intern` (`runtime/march_extras.c:2236`).
- The pad word's meanings are listed in `runtime/march_runtime.h:14-35`:
  > 0 is a shape id, < 0 a boxed ADT type id, 0 means nothing is known.

**`get_actor_field` exists** (`runtime/march_extras.c:2678`). Its type is
`Pid(a) -> String -> Option(b)` (`lib/typecheck/typecheck_builtins.ml:910`),
with `b` fully unconstrained. It finds the field by name through the struct's
shape id and returns the raw word, with an `'i'` field tagged. Three problems,
all verified by reading the code:

- It reads another actor's struct **from the caller's thread with no
  synchronisation** against that actor's handler, which moves and rewrites the
  same words.
- It returns a pointer field **without `march_incrc`**. Its arguments are listed
  as borrowed (`lib/tir/borrow.ml:368`). Whether the caller then treats the
  result as owned, which would make this a double-decrement as well as a race,
  was **not verified**.
- `b` is caller-chosen, so `get_actor_field(p, "count")` can be read at any
  type.

It is not cap-gated. It is used by about 20 `test/native/` fixtures, mostly to
read supervisor child pids out of supervisor state. None of this is fixed here
(Decision 5). It is why (b) must not be built by generalising `get_actor_field`.

**Interpreter.** `actor_inst` (`lib/eval/eval_runtime.ml:207`) holds
`ai_state : value`, the whole state as a `VRecord`, plus `ai_mailbox : value
Queue.t`. Despite its doc comment ("pending Down/Crashed messages"), that queue
is the **only** mailbox: user messages are enqueued by `mailbox_enqueue`
(`:1359`) and popped by `run_scheduler` (`lib/eval/eval.ml:2602`, pop at
`:2636`). The interpreter is single-threaded. `run_scheduler` marks the actor
whose handler is running in `busy_actors` (`eval.ml:2596`). Between handlers,
`ai_state` is always consistent. The interpreter's `get_actor_field`
(`lib/eval/eval_builtins.ml:363`) reads it directly.

**`Pid` is typed by the state.** `spawn(Counter)` has type `Pid({ count : Int })`,
and a surface annotation `Pid({ name : String })` is enforced against it. I
checked this with `--check` on a scratch program: passing a spawned `Counter` to
`fn want_named(p : Pid({ name : String }))` is rejected with ``expected `{ name
: String }` but got `{ count : Int }` ``. The same program with the matching
annotation checks clean. `specs/lang/core-march-types.md` §2.6.3 contradicts
itself on this: its first bullet says "FIXED", while its "Net" paragraph still
says the parameter is a fresh variable. The first bullet is the true one. That
doc drift is out of scope here.

### 1.5 The other landed pieces

- **`on_stop`** (`specs/progress/2026-09-22-actor-on-stop-terminate-callback.md`).
  - Lowered as `Name_on_stop(actor)` through the handler glue.
  - Registered per actor *type* with
    `march_register_actor_on_stop(dispatch_clo, on_stop_clo)`
    (`runtime/march_runtime.c:3269`), a mutex-protected table keyed by the
    dispatch closure that every record of the type holds in word 2. Run by
    `actor_run_on_stop` (`:3321`) under its own crash trap.
  - **Relevance:** it is the working precedent for "the compiler generates one
    extra per-type function, and the runtime finds it by dispatch closure".
    (b)'s per-type snapshot and render functions register the same way (§4.2).
- **Typed Config keys** (`specs/progress/2026-09-22-config-typed-keys.md`).
  `Config.key(ns, name, codec) : Config.Key(v)` over a `Vault(Config.Value)`.
  - **Relevance, twice.** First, Config is a stdlib Vault. The C runtime cannot
    read it, and it must never be read on a send path. It is a fine home for
    *application defaults* that stdlib code reads once, when a watch or trace is
    armed. Second, it is the precedent for closing a "caller chooses the type"
    door. The key carries a codec value because March has no runtime type
    information, which is the same problem (b2) faces (§4.3).
- **Hot-reload epochs** (`specs/plans/2026-09-21-distributed-authority-and-deploys-plan.md`
  §6.1–6.3, D10/D12/D30).
  - An actor moves to a new code version at its **marker**, a malloc'd
    `march_migrate_msg_t` with `MARCH_MIGRATE_TAG` in word 1, placed in the
    user mailbox (`hcr_inject_marker`, `runtime/march_runtime.c:5226`). The
    receive loop recognises it at a message boundary (`:3514-3531`) and runs
    `migrate_state`.
  - **Relevance:** a state read taken at a message boundary always sees a state
    of exactly one epoch's shape, but the shape can differ from the one the
    inspector's code was compiled against. The plan's §6.6 also wants "capture
    actor state from a running old version and run the real migration on it",
    which is (b2)'s typed snapshot.
  - The marker is also the precedent for a **runtime system message delivered
    in-band through the user mailbox and intercepted by the receive loop before
    dispatch**. (b) uses it.
- **Remote actors.** A local `Pid` is always local. Cross-node addressing is
  `GlobalPid`, sent through `Node.send` / `NodeSend` with a codec, and
  `Node.send`'s derive refuses a `Pid` payload
  (`specs/progress/2026-09-15-remote-actor-dispatch.md`). Nothing here reaches
  across nodes (§7).

### 1.6 Baseline measurements (2026-09-23)

`bench/actors/fanin_flood.march`: 8 producer tasks × 50,000 `send`s into one
`Sink` with `set_queue_limit(pid, 1024, 3)` (BLOCK). Compiled `--opt 2` with the
worktree's `_build/default/bin/main.exe` at `154cf1754`. It prints `delivered
400000`. Wall time per process, measured by a Perl fork/wait harness. 14-core
Apple Silicon, **shared box, load average 69.5 → 86 during the runs**.

| config | n | median | p25 | p75 | min | max |
|---|---|---|---|---|---|---|
| default schedulers, batch 1 | 15 | 160.0 ms | 152.5 | 181.1 | 124.8 | 368.1 |
| default schedulers, batch 2 | 15 | 176.3 ms | 159.9 | 182.8 | 152.6 | 231.0 |
| `MARCH_NUM_SCHEDULERS=1` | 15 | 60.4 ms | 56.3 | 77.3 | 53.7 | 94.3 |

- The two default batches differ by 10% at identical code, which is the noise
  floor at this load.
- The single-scheduler run is 2.7× faster than the default. That fits the
  reclaim note's `mbox_lock`-contention finding, and it is why the
  1-scheduler variant is the sensitive A/B arm (Decision 6).
- The reclaim note's own numbers (129.8 ms base, n=60, load 11–50) are not
  comparable with these: different load, and a later tree.

**Cost of one predictable branch under the lock.** This was a scratch C
microbenchmark, not the runtime. It has a spinlocked FIFO push with the two
relaxed `fetch_add`s `mbox_push_node` does. Variant 1 adds
`hi = load_relaxed(&p->alarm_hi); if (unlikely(hi && c == hi)) …` under the
lock, with `alarm_hi = 0` (disabled). Built with `cc -O2` and run interleaved.

| threads | n per arm | variant 0 median | variant 1 median | spread |
|---|---|---|---|---|
| 1 | 7 | 19.25 ns/push | 19.38 ns/push | both 17.9–25.5 |
| 8 (same target) | 21 | 138.9 ns/push | 146.1 ns/push | IQR 121–168 vs 126–159 |

- Single-threaded, the difference is 0.7%, inside the spread.
- Contended, the difference is inside an IQR of ±15%. It is not resolvable at
  load 83.
- The branch reads a field on the line the lock holder has just written. It
  cannot add a coherence miss. It can only add an instruction or two.

---

## 2. Design principles shared by all three

1. **One global arm word, read relaxed, gates everything on the send path.**
   `_Atomic uint32_t g_introspect_armed` is a bitmask: ALARM (any watch
   exists), TRACE (any trace session exists). Nothing writes it except arming
   and disarming, so it is a read-mostly line held Shared in every core's cache.
   When it is 0 the send path pays one relaxed load and one predictable branch,
   and touches no per-actor field it would not otherwise touch. (The alarm needs
   no global gate: its per-proc field sits on a line the lock holder already
   owns, §3.)
2. **No March code runs on the sender's path.** No closure calls, no March
   allocation and no second send happen while the target's `mbox_lock` is held
   or on the sender's thread at all, except a fixed-size C store. Work that
   needs March (building a message, rendering a string, sending to a watcher)
   is deferred:
   - to a scheduler thread's control-plane point, next to `march_signal_drain`
     at `runtime/march_scheduler.c:1699`, which is how `Signal.watch` already
     runs March closures safely; or
   - to the **target actor's own thread**, at a message boundary.
3. **Queued work names pids.** No proc pointer outlives a critical section (§1.3).
4. **Both backends, one `.expected`.** Every stage ships a `test/native/`
   fixture run interpreted and compiled, like `actor_enumeration.march`.
   Divergences are named in the fixture and in `specs/lang/actors.md`, as the
   BLOCK policy's interpreter divergence already is.

---

## 3. (a) Push-style mailbox alarm

### 3.1 Options for where the edge is detected

| Option | Send-path cost when enabled | Cost when disabled | Exactness | Verdict |
|---|---|---|---|---|
| A. A new atomic counter per target, `fetch_add` on every send | a second contended RMW on the target line | the same RMW always, unless gated | exact | **no.** It duplicates `user_mbox_count`, which already exists under the lock |
| B. Approximate or per-sender batched counter | cheap | cheap | approximate, and a batch can hide a crossing | **no.** It solves a problem we don't have (§1.2: there is already an exact counter) |
| C. **Compare the count already computed in `mbox_push_node`, under `mbox_lock`** | one field load plus a compare, a rare pending-push on the edge | one field load plus a predictable branch, same line | exact: the count moves by ±1 under the lock, so `== hi` is hit exactly once per upward crossing | **chosen** |
| D. Polling from a runtime daemon (the in-runtime version of `over_mailbox`) | none | none | misses short spikes; latency is the poll period | this is what already exists, in stdlib form |
| E. A callback run on the sender's thread | arbitrary: runs March code under or near the lock | — | exact | **no.** It breaks principle 2 |

### 3.2 Chosen design

**Per-proc state**, placed next to `user_mbox_count` so it shares the line the
push already dirties. All of it is read and written only under `mbox_lock`,
except `alarm_rec`, which is set under the lock too.

```c
int64_t        alarm_hi;      /* 0 = no watch (calloc default) */
int64_t        alarm_lo;      /* re-arm at or below this (hysteresis) */
uint8_t        alarm_high;    /* 1 between an upward and a downward crossing */
struct march_alarm_rec *alarm_rec; /* the watch; NULL when none */
```

**Edge detection**, in `mbox_push_node` for user messages:

```c
int64_t c = atomic_fetch_add_explicit(&p->user_mbox_count, 1, relaxed) + 1;
if (__builtin_expect(p->alarm_hi != 0, 0) && c >= p->alarm_hi && !p->alarm_high) {
    p->alarm_high = 1;
    alarm_enqueue(p->alarm_rec, /*high=*/1, c);   /* lock-free push, no March code */
}
```

The low edge goes in `mbox_pop_queue` for user messages. It is the same shape
with `c <= alarm_lo && alarm_high`. It runs on the receiver's side, which is not
the send path at all.

`>=` rather than `==` makes the check robust to a limit change or to DROP_OLD's
pop-then-push, at no extra cost. `alarm_high` makes it fire once per crossing.

**The pending queue.**

- `march_alarm_rec` is malloc'd and holds:
  - the target **pid** (never a proc pointer);
  - the watcher **pid**;
  - the owned message-building closure `f : (Pid, Int, Bool) -> m`, with
    `Bool` meaning high or low;
  - an atomic refcount (one for attachment to the proc, one while queued);
  - an intrusive `next` link and an atomic `queued` flag.
- `alarm_enqueue` records the edge and depth in the rec. It then pushes the rec
  onto a global Treiber stack `g_alarm_pending` with one CAS, only if a CAS on
  `queued` goes from 0 to 1, and sets `g_alarm_any = 1`. A rec is on the stack
  at most once. If a second edge arrives before the drain, it overwrites the
  recorded edge and depth, so the drain reports the latest state (see §3.5 on
  coalescing).
- The drain runs in `sched_loop` beside `march_signal_drain`, on a scheduler
  thread's normal stack, inside its implicit critical section. It exchanges the
  stack head to NULL, then for each rec:
  - clears `queued`;
  - calls `f(pid_of(target), depth, high)` exactly as `march_signal_drain` calls
    a watcher, with an `incrc` before the apply to balance the per-call `$clo`
    drop (`runtime/march_runtime.c:8995-9020` explains why);
  - `march_send`s the result to the watcher pid;
  - drops the queued ref.
  A watcher that is dead gets `MARCH_SEND_DEAD`, and the value is disposed.

**Arming and disarming.**

- Resolve target pid → meta → `green_thread` inside a critical section, take
  its `mbox_lock`, set `alarm_hi/lo/rec`, set `alarm_high` from the current
  count (so arming over an already-deep mailbox fires immediately, once), and
  release.
- Disarm is the reverse: clear the fields under the lock and drop the proc's ref.
- The PROC_DEAD reap drain, which already holds the lock
  (`mbox_wake_send_waiters_if_low`'s neighbour), drops the rec's attachment
  ref. The watch is on **this incarnation**, like a monitor. A supervised
  restart's new proc is unwatched. The stdlib notes this and points to
  `whereis` plus re-arming, which is the §9 "hold names, not Pids" rule of
  `specs/lang/actors.md`.

**Validation at arm time.** `lo < hi`, and `hi ≥ 1`. If the target has a limit,
`hi ≤ limit`: at `hi > limit` the count can never reach `hi`, so arming is
refused with an error rather than silently never firing. This is checked in C
under the lock, because the limit can change afterwards. A later
`set_queue_limit` that puts the limit below `hi` also disarms and reports.

**Which count.** `user_mbox_count`, not `mbox_count`. Control-plane Downs are
not load, and the BLOCK and limit logic already uses the user count.

**Interpreter.** `mailbox_enqueue` (`lib/eval/eval_runtime.ml:1359`) is the only
enqueue. Add the same `>= hi && not high` check after the push, and append
`(rec, depth, high)` to a pending list. The pops need a single `mailbox_pop`
helper for the low edge. Today `Queue.pop inst.ai_mailbox` is called directly
at `eval.ml:2636`, `eval.ml:3190`, `eval_builtins.ml:431` and the drain at
`eval_runtime.ml:1266`. `run_scheduler` delivers the pending list at the top of
each pass, before dispatching. Eager and single-threaded, so the order is
deterministic.

### 3.3 Surface

```march
-- stdlib/actor.march
type AlarmRef = AlarmRef(Int)

fn watch_mailbox(c : Cap(Actor.Introspect), target : Pid(s), watcher : Pid(w),
                 high : Int, low : Int,
                 f : (Pid(s), Int, Bool) -> m) : Result(AlarmRef, String)
fn unwatch_mailbox(c : Cap(Actor.Introspect), r : AlarmRef) : Unit
```

The watcher is an ordinary actor with an ordinary handler. `f` builds its
message, as `Signal.watch`'s closure does (`on Overloaded(p, depth, is_high)`).
The message type the watcher accepts is not checked against `w` today, because
`send`'s target type is discarded (`specs/lang/core-march-types.md` §2.6.4). The
same caveat applies here and is no worse than `send`.

**Global mode.** This is `system_monitor`'s real shape: "tell me about ANY actor
that crosses N". It is Stage A2, not A1:

- `Actor.watch_all_mailboxes(c, watcher, high, low, f)` sets a process-wide
  default. `march_spawn_common` copies it into each new proc, which costs one
  relaxed load at spawn, not at send.
- Arming walks existing actors with the lock-free enumeration, setting each one
  under its own lock.
- An actor spawned during the walk is covered by the spawn-time copy.
- The watcher itself is exempt, so an overloaded watcher cannot alarm about
  itself in a loop.
- Application defaults for `high`/`low` can live in typed Config keys that the
  stdlib reads at arm time, e.g. `Config.key(:march, :mailbox_alarm_high,
  Config.int())`. The runtime never reads Config.

### 3.4 Cost

- **Disabled:** one load of `p->alarm_hi` from the line `mbox_push_node` just
  wrote, and one never-taken branch, inside the lock. No new RMW, no new line.
  §1.6's microbenchmark could not tell it from noise.
- **Enabled, not crossing:** the same, plus a compare against `hi`.
- **Crossing:** two CASes (on `queued` and the stack head) on lines no other
  sender touches, once per crossing. The March work happens on a scheduler
  thread later.
- **Receive side:** the symmetric check in `mbox_pop_queue`.

### 3.5 Risks

- **Coalescing.** A high → low → high burst between two drains reports only
  the latest edge. That is acceptable for an alarm: the watcher learns the
  current state. It is documented, and the fixture asserts only the final edge.
- **A watcher that is itself the congested actor**, in global mode: exempted
  (above).
- **The foreign-thread send path** (evloop) reaches `mbox_push_node` like any
  other. `alarm_enqueue` is lock-free and allocation-free, so it is safe there.
  The drain never runs on a foreign thread.

---

## 4. (b) Per-actor state inspection

### 4.1 Options

| Option | Consistency | Cost to others | Verdict |
|---|---|---|---|
| A. Read the actor struct from the inspector's thread (generalise `get_actor_field`) | none: races the handler's move and write-back (§1.4) | none | **no** |
| B. Stop the world, or take a per-actor "state lock" the handler also takes | consistent | a lock on every handler invocation | **no.** It puts a lock on the dispatch path |
| C. **A system request through the actor's own mailbox, answered by the actor at a message boundary** (OTP `sys`) | consistent by construction: between handlers there is exactly one state | none until used. The request queues behind the backlog | **chosen** |
| D. Read through the control plane (`march_sched_send_control`) | same as C | — | **no.** The dispatch loop waits for user traffic only (`mbox_wait_mode == 2`, `runtime/march_scheduler.c:2825-2834`), so a control request to an idle actor is never seen |

C has a real downside: the answer waits behind every queued message, so for
the actor you most want to inspect (the one that is behind) you get a timeout.
That is also OTP's behaviour. The mitigation is §4.5.

### 4.2 Chosen design

**Request.**

- The caller builds a reply-ref exactly as `march_actor_call` does
  (`runtime/march_runtime.c:6101-6180`): tag `MARCH_CALL_REPLY_TAG`, caller pid,
  correlation id.
- It sends a request cell tagged **`MARCH_SYS_INSPECT_TAG`**, a new reserved tag
  `0x7F000004` in the monitor ABI range (`runtime/march_runtime.h:240-254`),
  which bumps `MARCH_RESERVED_CTOR_TAG_LIMIT` and its `#error` check and is kept
  in sync with `lib/tir/llvm_builtins.ml`. The cell's field 0 is the reply-ref
  and field 1 is the request kind (render or typed, §4.3).
- Being a reserved tag above `MARCH_ORDINARY_CTOR_TAG_LIMIT`, it cannot collide
  with a user constructor. Unlike the migrate marker, it needs no
  `dispatch_name_id` gate.
- It is sent through a **policy-bypassing push**: the user queue, but not
  subject to DROP_NEW/DROP_OLD/BLOCK. Otherwise a full DROP_NEW mailbox would
  drop the request, and a BLOCK one would park the inspector. It is FIFO with
  user messages, so it answers from a state no earlier than every message sent
  before it.
- The caller then waits with a timeout on `march_sched_recv_user_seq` and
  `march_actor_call_unwrap`, the same loop `Actor.call` uses. Everything that
  parks happens outside a critical section (§1.3).

**Interception** happens in `actor_green_thread`'s loop right after
`march_sched_recv_user` (`runtime/march_runtime.c:3508`), next to the migrate
check:

```c
if (IS_HEAP_PTR(msg) && ((march_hdr *)msg)->tag == MARCH_SYS_INSPECT_TAG) {
    actor_answer_inspect(meta, a, msg);   /* own thread, between handlers */
    continue;
}
```

This is receive-side cost only: one header load the dispatch would do anyway,
and one compare. It is **not on the send path.**

**Answering.** The compiler emits one more per-type function beside
`Name_on_stop`: `Name_inspect(actor) : String`. Its body loads the state fields
(or `$f_state` under hot reload), builds the state record, calls `to_string` on
it (the same erased renderer as `march_value_to_string`,
`runtime/march_runtime.h:813`), and writes the fields back with the same
`EReuse` a handler ends with. This is exactly the `on_stop` lowering trick
(`on_stop` progress note, "Implementation"), and it keeps field ownership
balanced.

- It is registered with a `march_register_actor_inspect(dispatch_clo, fn)`
  table keyed like `on_stop`'s.
- `actor_answer_inspect` calls it under a crash trap like `actor_run_on_stop`'s,
  because a render that panics must not kill the actor, and replies through
  `march_actor_reply`. A caller that already timed out resolves to NULL, which
  is a dead send, as today.
- **Only a String leaves the actor.** No heap value is shared, so a linear state
  field (possible since 2026-09-10) is read, never aliased.

**Nested receives.** A handler can receive while the request is queued:

- `march_actor_recv` (`:3737`), the user `receive()` inside a handler;
- `Actor.call`'s wait inside a handler.

Either could pop the request. Both must not hand it to user code, and must not
answer it mid-handler, because the fields are moved out at that point. They
requeue it with `march_sched_requeue_user_front` (`runtime/march_scheduler.h:739`)
and it is answered at the next boundary. **This is the trap most likely to ship
unnoticed.** Stage B1's fixture pins it (§8).

**Self-inspection** (`inspect_state(c, self(), t)` from the actor's own handler)
would wait on itself. It returns `Err(InspectSelf)` immediately on both
backends.

**Interpreter.**

- `run_scheduler`'s dispatch recognises `VCon("$sys_inspect", [reply])` before
  the handler lookup (`lib/eval/eval.ml:2637-2650`), renders `ai_state` with
  `value_to_string`, and replies.
- The eager scheduler could just read `ai_state` directly. It must not, because
  that would answer ahead of the queued backlog and change the observable order
  relative to the compiled backend.
- `$sys_inspect` cannot be a user constructor name (`$` is not an identifier
  start), which is the same argument `$d_dispatch` relies on.

**Rendering parity.** The compiled `to_string` of a record and the interpreter's
`value_to_string` must print the same text for the fixture's state types:
records, lists, Options, a nested ADT and a string with quotes. Float rendering
is a known five-backend hazard (memory: "float→string backends"). The fixture
avoids floats, or pins them with the reference formatter.

### 4.3 (b2) The typed snapshot: why it is later, and what it needs

`Actor.get_state(c, pid : Pid(s), t) : Result(s, InspectError)` is what
`migrate_state` testing wants (plan §6.6). Two things make an unchecked version
unsound:

1. **Forged `s`.** `Actor.pid_from_int(c, n) : Pid(a)` and `Actor.list(c)`
   give a `Pid` whose parameter the caller picks. Compiled, reading a `{ count :
   Int }` state as `{ name : String }` dereferences an integer.
2. **Reload drift.** After a migration the state has the new epoch's shape, but
   the inspector's `Pid(s)` was typed against the old one.

The shape id resolves both. The request carries the **expected shape
descriptor** of `s`: the compiler emits the same `"name:k;…"` string
`emit_set_shape` uses, at the monomorphic call site. The actor compares it with
its current state shape (the actor struct's pad, or the `$f_state` record's)
before building the value. On a mismatch it replies
`Err(StateShapeMismatch(expected, found))`. On a match it builds the record with
every field `incrc`'d and replies with it.

Open costs of b2, each needing a decision when b2 is scheduled:

- **The descriptor must be concrete at emit time.** If `s` is still a type
  variable (an erased generic helper, the case `get_actor_field`'s comment
  describes), there is no descriptor. The choices are a compile error ("the
  state type of `pid` is not known here") or `Err(StateTypeUnknown)`.
  *Leaning:* compile error.
- **Linear state fields.** `incrc`-sharing a linear value breaks linearity.
  An actor whose state has a linear field is refused at compile time.
- **FBIP.** The shared fields have `rc > 1` until the inspector drops them, so
  the actor's next in-place update of a large List or Map field copies instead.
  This costs performance, not correctness. Document it.
- **Interpreter.** There is no runtime type. The typechecker would have to
  record the expected field set at the call site (an annotation on the `EApp`)
  for the builtin to compare against the `VRecord`'s field names. That is new
  plumbing, and it is why b2 is not in the first wave.
- **Is the hot-reload `Name_State` record shape-stamped at allocation?** I
  **could not verify** this. `emit_set_shape` is scoped to actor structs
  (`llvm_emit_alloc.ml:256`), and whether ordinary `ERecord` allocation also
  calls `march_record_set_shape` was not traced. If it does not, b2 needs a
  stamp there too.

### 4.4 Surface

```march
type InspectError = InspectTimeout | InspectDead | InspectSelf
                  | InspectFailed(String)          -- the render panicked

-- stdlib/actor.march
fn inspect_state(c : Cap(Actor.Debug), pid : Pid(s), timeout_ms : Int)
    : Result(String, InspectError)
-- b2, later:
fn get_state(c : Cap(Actor.Debug), pid : Pid(s), timeout_ms : Int)
    : Result(s, InspectError)            -- + StateShapeMismatch(String, String)
```

`Actor.Debug` is declared as `proof cap Debug` in `mod Actor`, with
`fn debug(io : Cap(IO)) : Cap(Actor.Debug) do mint_cap(io) end`, mirroring
`introspect` (Decision 2). The raw builtin `actor_inspect` goes on the
stdlib-only list.

### 4.5 Busy, blocked and backlogged actors

- **Busy in a long handler:** the request waits for the handler to return.
  `InspectTimeout`.
- **Blocked in a nested `receive()` or `Actor.call`:** the request is requeued
  (§4.2), so the result is still `InspectTimeout`, never a mid-handler state.
- **Backlogged** (the interesting case): the request queues behind N messages.
  A *priority* inspect would jump the queue: push at the head, not the tail,
  under the same lock. It still waits for the current handler, but not for the
  backlog. That is a second request kind, and it is an **open question** (§9).
  It trades FIFO consistency ("a state no earlier than my last send") for
  latency. OTP has no such mode.
- **Draining** (`Actor.stop` in progress): `march_send` rejects new user sends
  while `meta->draining` is set (`runtime/march_runtime.c:5839`). The inspect
  push is not a user send, so it is accepted and answered during the drain.
  After death: `InspectDead`.

---

## 5. (c) Tracing

### 5.1 Event points

| Event | Where (compiled) | Where (interpreter) | Thread |
|---|---|---|---|
| `Sent(from, to, msg)` | `march_send` after `find_meta`, before `march_sched_send`. Also `march_actor_call`'s send (kind `Call`) and `march_send_after`'s fire (kind `Timer`) | `mailbox_enqueue` | sender |
| `Received(pid, msg)` | `actor_green_thread` after the migrate and inspect checks, before dispatch | `run_scheduler` before the handler call | receiver |
| `Spawned(parent, child)` | `march_spawn_common` (`runtime/march_runtime.c:5071`) | `spawn_child_actor` and the `ESpawn` arm | parent |
| `Exited(pid, reason)` | `do_actor_death` (`:4675`), which has the reason | `stop_actor` / crash / kill | dying actor or killer |
| `Dropped(to, msg)` | the DROP_NEW/DROP_OLD arms (`runtime/march_scheduler.c:2673-2690`) | `mailbox_enqueue`'s drop arms | sender |

`Call` and `Reply` events come from the reply-ref tag already in the message, so
they need no new site. Scheduling events (run, park) are out of scope.

### 5.2 Flags and cost when off

- **Per-proc** `_Atomic uint32_t trace_flags` (SEND, RECV, SPAWN, EXIT, DROP,
  PAYLOAD).
- **Global** `g_introspect_armed & TRACE`, as in principle 1.
- The send-side check:

```c
if (__builtin_expect(atomic_load_explicit(&g_introspect_armed, relaxed) & ARM_TRACE, 0))
    trace_send(meta, gt, msg);          /* out of line, cold */
```

- **Off:** one relaxed load of a line nobody writes, and one never-taken
  branch. Measured against the §1.6 acceptance rule.
- **On:** `trace_send` checks the target's flags (`gt->trace_flags`, the target
  proc it already holds) and the sender's (`march_sched_current()->trace_flags`,
  or none on a foreign thread). Only if either is set does it write an event.
- **The trace check does not go under `mbox_lock`.** It runs before
  `march_sched_send`, with the message still owned by the sender, so a payload
  render sees a value nobody else can touch yet.
- **Receive side:** one relaxed load of `self->trace_flags` per message, on the
  actor's own proc line. The global gate is not needed there.
- **Inheritance.** OTP's `set_on_spawn` (a traced actor's children are traced)
  is a flag copied in `march_spawn_common` when the parent has an INHERIT bit.
  One load at spawn. Stage C2.

### 5.3 The sink

- **A ring per trace session:** malloc'd, a fixed number of fixed-size slots
  (kind, from pid, to pid, monotonic ns, sequence number, and an optional owned
  `march_string *` payload).
- **Multi-producer reservation:** `fetch_add` on the ring's `head`. If
  `head - tail` is at or above capacity, the event is **dropped and counted**
  (`fetch_add` on `dropped`), never waited for: a traced actor is never
  backpressured by its tracer.
- **One consumer:** `Trace.drain` copies the published slots into a March
  `List(TraceEvent)` and advances `tail`. A per-slot `ready` sequence word
  handles a producer that reserved but has not yet written.
- The ring's `head` is contended **only while tracing is on**. That is the
  accepted price. The send path pays nothing for it when off.
- **Payload:** only with the PAYLOAD flag. The message is rendered with the
  erased renderer **on the sender's thread before the push**, and the
  `march_string` is stored in the slot. That renders a message, not state, so a
  linear payload is read, not shared. Without PAYLOAD, the event carries the
  constructor name from the header's type id (`runtime/march_runtime.h:14-35`;
  `march_ctor_table_ensure`), or `"<immediate>"` for a niche-encoded message.
  Verification must cover niche messages (`NULL`, odd scalars): the migrate
  check's comment (`runtime/march_runtime.c:3504-3512`) records that
  dereferencing them SIGSEGVs.
- **The tracer is never traced.** An actor that drains a session has its own
  sends and receives to that session suppressed, so tracing a tracer cannot
  feed back.

**Interpreter:** an OCaml bounded `Queue` per session, with the same drop
counter and the same event record. Timestamps are the only field the fixture
does not pin.

### 5.4 Surface

```march
-- stdlib/trace.march (new module)
type TraceEvent = Sent(Pid, Pid, String, Int)       -- from, to, msg, ns
                | Received(Pid, String, Int)
                | Spawned(Pid, Pid, Int)
                | Exited(Pid, String, Int)
                | Dropped(Pid, String, Int)
type TraceSession = TraceSession(Int)
type TraceFlag = Sends | Receives | Spawns | Exits | Drops | Payloads | Inherit

fn start(c : Cap(Actor.Debug), capacity : Int) : TraceSession
fn trace(c : Cap(Actor.Debug), s : TraceSession, pid : Pid(a), flags : List(TraceFlag)) : Unit
fn untrace(c : Cap(Actor.Debug), s : TraceSession, pid : Pid(a)) : Unit
fn drain(s : TraceSession) : List(TraceEvent)       -- holding the session is the authority
fn dropped(s : TraceSession) : Int
fn stop(s : TraceSession) : Unit
```

v1 has one active session per process. `trace` on a pid already traced by
another session is an error. Multiple sessions would need a flags-to-session
map on the hot path. That is deferred and noted in §9.

### 5.5 Interaction with the lock-free send

The trace hook runs **before** `march_sched_send`. It does not hold any mailbox
lock and takes no global lock. It resolves nothing a normal send does not
already resolve. It writes only to the ring. The one place a trace event is
emitted under a lock is `Dropped`, which fires inside the DROP arms while
`mbox_lock` is held. That site is rewritten to record the drop and emit the
event after `mbox_lock_release`, the same "dispose after unlock" discipline the
DROP_OLD arm already follows (`runtime/march_scheduler.c:2680-2690`).

---

## 6. Build plan (each stage lands on its own)

| Stage | Contents | Compiler change? |
|---|---|---|
| **A1** | Per-target push alarm: proc fields, edge checks in push and pop, Treiber pending stack, drain beside `march_signal_drain`, `Actor.watch_mailbox`/`unwatch_mailbox`, interpreter `mailbox_pop` helper + pending list. Docs in `specs/lang/actors.md` (regenerate `docs/`), `docs/overload-resilience.md` step 2 shows push next to poll. | builtins only (typecheck entry, llvm_builtins decl, eval builtin; the "nine sites" checklist) |
| **A2** | Global mode `watch_all_mailboxes`, spawn-time copy, watcher exemption, Config-key defaults read by the stdlib. | no |
| **B1** | `inspect_state` as String: `MARCH_SYS_INSPECT_TAG`, policy-bypassing push, loop interception, nested-receive requeue, `Name_inspect` lowering + registration, `Cap(Actor.Debug)`, interpreter `$sys_inspect`. | yes (`lower_actor`, `Tir_names`, the `$clo_wrap` borrowed-arg exemption `on_stop` needed: `Tir_names.is_actor_on_stop_fn`'s sibling) |
| **C1** | Trace ring, `Sent`/`Received`/`Spawned`/`Exited`/`Dropped` without payload, `stdlib/trace.march`. | builtins only |
| **C2** | PAYLOAD rendering, INHERIT. | no |
| **B2** | Typed `get_state` with a shape-descriptor check. | yes (call-site descriptor emission, interpreter annotation) |
| **D** (follow-up todo, Decision 5) | Gate or retire `get_actor_field`. | typecheck gate + fixture migration |

Each stage adds its CHANGELOG `### Added` bullet and moves or trims the todo in
the same commit, per `CLAUDE.md`.

---

## 7. Out of scope

- **Remote inspection or tracing.** A local `Pid` cannot name a remote actor,
  and a cross-node version is a new `NodeSend` control message plus an
  authority question the distributed plan's §3 (segregation) must answer first.
  Nothing in this design prevents it later.
- **Scheduler-level tracing** (run, park, migrate between threads).
- **Changing `mailbox_size`'s semantics.** It keeps counting user plus control
  messages (`mbox_count`). The alarm counts user messages only, and the doc
  says so.

---

## 8. Verification plan, including how each test is shown to go red

Every fixture runs **interpreted and compiled against one `.expected`**. Each
red control below is a deliberate perturbation of the new code, run once,
reverted, and recorded in the stage's progress note.

**A1.**

- `test/native/actor_mailbox_push_alarm.march`:
  - A sink paused by a gate message: a producer sends `hi + 5` messages, so
    exactly one `Overloaded(_, _, true)` arrives.
  - Release the gate and drain below `lo`, so exactly one `(_, _, false)`
    arrives.
  - Refill, and a second high arrives (hysteresis re-arm).
  - `unwatch`, refill, and nothing arrives.
  - Arm over an already-deep mailbox, and it fires once immediately.
  - `hi > limit` is refused.
  - Depths are not in the golden, since they race compiled. Only the counts
    and the ordering are.
- *Red controls:* (1) drop the `!alarm_high` guard: the high count becomes > 1;
  (2) drop the pop-side re-arm: the second high never arrives; (3) make
  `alarm_enqueue` a no-op: no alarm at all, on the compiled leg only, which
  proves the compiled leg is not vacuously satisfied by the interpreter; (4)
  reap without dropping the rec: ASAN in the Linux container
  (memory: "ASAN needs Docker locally") reports a leak or UAF under a
  kill-while-queued variant.
- **Send-path cost:**
  - fanin_flood A/B per Decision 6, with the watch **unarmed**, and a second
    arm armed on the sink with `hi` above the BLOCK limit (the "enabled, never
    crosses" cost).
  - Show the benchmark can go red: a deliberately slow variant (an extra
    `fetch_add` on a global counter in `mbox_push_node`) must be detected by
    the same harness at the same n. If it is not, the harness is too noisy to
    certify anything and the result is reported as inconclusive rather than
    as a pass.
  - Also re-run `proc_reclaim_kill_respawn.march` (ASAN and TSAN) with
    watches armed on its workers.

**B1.**

- `test/native/actor_inspect_state.march`:
  - Render of a record with a list, an Option, a nested ADT and a quoted
    string.
  - FIFO: send `Inc(1)` ×3, then inspect, which shows `count: 3`.
  - Inspect of a DROP_NEW-full actor is answered, not dropped.
  - Inspect of a BLOCK-full actor does not park the inspector.
  - An actor blocked in a nested `receive()` gives `InspectTimeout`, and the
    actor's own `receive()` still gets its real message.
  - Self-inspect gives `InspectSelf`.
  - A dead pid gives `InspectDead`.
  - A render panic gives `InspectFailed`, and the actor survives.
- *Red controls:*
  - Remove the nested-receive requeue: the user `receive()` gets the request,
    and the fixture's type-confused line changes (compiled) or errors
    (interpreted).
  - Answer from the inspector's thread (option A): TSAN reports a race on the
    struct words in the container.
  - Normal push instead of the bypass: the DROP_NEW case times out.
- `--check` reject corpus: `inspect_state` without `Cap(Actor.Debug)`, and a
  direct `actor_inspect` from user code (the stdlib-only gate), each with a
  witness that is accepted when the cap is present.

**C1.**

- `test/native/actor_trace.march`:
  - Trace one actor, then send, receive, spawn a child and kill it. The drained
    events, with timestamps stripped, match on both backends.
  - A capacity-4 session with 100 sends: `dropped` is 96, and the traced
    actor's throughput is not bounded by the tracer (it completes).
  - Niche messages (a nullary ctor, an `Inc(10)` scalar) trace without a crash.
- *Red controls:* block instead of drop when full, so the fixture's completion
  line times out; skip the niche guard, so it SIGSEGVs compiled; trace the
  tracer, so the fixture's drained count grows without bound (a bounded loop
  asserts it does not).

**All stages:** `scripts/run-tests.sh` (full), `dune build @runtest --root .`
for the dune-rule goldens the script skips, and `scripts/check-docs.sh`.

---

## 9. Risks and open questions

- **The alarm fires on a scheduler thread's control-plane point.** Delivery
  latency is up to one `sched_loop` iteration. With every scheduler busy in
  long-running green threads, that is a preemption quantum. It is acceptable
  for an alarm, and the same as `Signal.watch`.
- **Priority inspect** (§4.5): whether to offer a head-of-queue request kind.
  Undecided. It is a semantic choice, not a mechanism problem.
- **Multiple trace sessions** (§5.4): v1 allows one. Several sessions would
  need per-proc session ids and a small table on the hot path.
- **`to_string` parity for state rendering** across the two backends is only
  as good as today's renderers. B1's fixture exercises the state shapes a real
  actor holds. A divergence it finds is a renderer bug, filed separately, not
  a reason to add a second renderer.
- **The Debug cap and stdlib callers.** If a stdlib module (e.g. a future
  observer or supervisor dashboard) needs inspection, it must be handed the
  cap. The stdlib-only filter hides missing-`needs` diagnostics in stdlib
  modules (memory: "stdlib-span diagnostics silently filtered"), so check
  `--check stdlib/<mod>.march` on every such module.
- **Not verified here:** whether `get_actor_field`'s caller treats the returned
  pointer as owned (§1.4); whether the hot-reload `Name_State` record carries a
  shape id (§4.3); the contended-case cost of the alarm branch at low load
  (§1.6 was taken at load 69–86).
