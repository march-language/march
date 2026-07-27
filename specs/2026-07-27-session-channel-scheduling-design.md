# Scheduler-Backed Session Channels

**Date:** 2026-07-27
**Status:** Draft — design only. No compiler, runtime or stdlib change is proposed
by this document; nothing here has been implemented.
**Area:** Concurrency / Session types
**Resolves:** finding **F6** (`specs/lang/core-march.md` §4.11.6; `specs/todos.md:1259`)
**Explicitly not about:** protocol *conformance*. Static session checking is
thorough and was just hardened — see `CHANGELOG.md` `[Unreleased]` and
`specs/plans/2026-07-24-session-types-fixes.md`. This document is entirely about
the runtime execution model.

**Depends on / touches:**

- `lib/eval/eval.ml` — the interpreted channel runtime and actor scheduler
- `runtime/march_extras.c` — the compiled channel runtime
- `runtime/march_scheduler.c` — the M:N green-thread scheduler (park/wake)
- `lib/tir/lower.ml`, `lib/tir/llvm_builtins.ml`, `lib/tir/defun.ml` — `Chan.*` lowering
- `specs/lang/golden/` (`g38`, `g39`), `specs/lang/types/` (t30–t35, t41–t44, t74–t76, t79, t91–t104)

---

## 1. Problem statement and the current model

### 1.1 One line

A session channel is a pair of FIFO queues with **no scheduler behind it**.
`Chan.recv` on an empty queue is a *fatal error*, not a suspension, on both
backends. Therefore both endpoints of a session must be driven from a single
control flow with every `send` textually before its matching `recv`. Two
functions each holding one endpoint cannot be called in sequence; two actors
cannot conduct a session unless their message-driven control flow already
happens to order every `send` before its matching `recv`.

This is the boundary documented in `specs/lang/session-types.md` (the "Runtime
note" and the "Session types and actors" section) and filed as F6.

### 1.2 The interpreted model

An endpoint is `VChan of chan_endpoint` (`lib/eval/eval.ml:66`), with the record
at `lib/eval/eval.ml:87–95`:

```ocaml
and chan_endpoint = {
  ce_id      : int;
  ce_role    : string;
  ce_proto   : string;
  mutable ce_closed   : bool;
  ce_out_q   : value Queue.t;
  ce_in_q    : value Queue.t;
}
```

`chan_new` (`eval.ml:3395`) allocates two plain OCaml `Queue.t` values and
crosses them: endpoint A's `ce_out_q` *is* endpoint B's `ce_in_q`.

- `chan_send` (`eval.ml:3408`) — `Queue.push v ce.ce_out_q`, return the same
  endpoint. Never blocks, never inspects the peer.
- `chan_recv` (`eval.ml:3418`) — **if `ce_in_q` is empty, `eval_error`**:
  `Chan.recv: channel %s#%d has no pending value — did you run the sender first?`
  There is no retry, no suspension, no registration of a waiter.
- `chan_close` (`eval.ml:3429`) — sets `ce_closed <- true`; second close is an error.
- `Chan.choose`/`Chan.offer` are *literally* `chan_send`/`chan_recv` of the label
  (`eval.ml:6385`, `:6392`). Branch selection has zero runtime representation.

**The decisive fact about the interpreter, which the existing F6 write-up does
not state: the interpreter has no green threads at all.**

- `task_spawn` (`eval.ml:8588`) *eagerly applies the thunk* — "Phase 1: eagerly
  evaluate the thunk. Phase 2+ will enqueue on the run queue instead." A spawned
  task runs to completion at its spawn point, on the caller's OCaml stack.
- Actors are not coroutines either. `run_scheduler` (`eval.ml:8478`) is a
  message-drain loop that applies handler bodies. `receive()` (`eval.ml:3889`)
  pops the mailbox, and if empty raises `BlockedOnReceive` (`eval.ml:980`); the
  scheduler catches it, **pushes the triggering message back to the front of the
  mailbox and re-runs the whole handler later** (`eval.ml:8551–8562`). It is
  restart-on-block, not suspend-and-resume — and the code says so: "LIMITATION:
  only the FIRST receive() call in a handler is safe."
- `grep` for `Effect.` in `lib/eval/` returns nothing: the interpreter is a plain
  recursive `eval_expr` with no OCaml 5 effect handlers, though the switch is
  OCaml 5.3.0, so effect handlers *are* available.

So the interpreter cannot park a March call stack today by any mechanism, and
the actor restart trick cannot be borrowed for channels: replaying a handler
would replay its already-performed `Chan.send`s, duplicating queue entries.

### 1.3 The compiled model

`runtime/march_extras.c:1302–1477`. A channel is a `march_chan_pair`
(`:1308–1318`) holding a `pthread_mutex_t lock`, two singly-linked queues
(`ab_head/tail`, `ba_head/tail`) and an `int64_t refcount`. An endpoint is a
3-field March heap object `(pair_ptr, role, closed)` (`chan_make_endpoint`,
`:1398`); `send`/`recv` allocate a *fresh* endpoint each time and release the old
one's share of the pair refcount (`:1430`, `:1445`).

- `chan_enqueue` (`:1348`) — malloc a node, take `p->lock`, append, release.
- `chan_dequeue` (`:1365`) — take `p->lock`, pop the head, release; **and if the
  queue was empty**:

  ```c
  fprintf(stderr, "march: Chan.recv on empty channel queue (role %lld)\n", role);
  abort();
  ```

  (`march_extras.c:1384–1391`). Exit 134.
- `march_chan_close` (`:1461`) only calls `chan_pair_release`; it does **not** set
  the endpoint's `closed` field, so the compiled backend has no double-close
  check where the interpreter has one. (Not user-visible today: the typechecker
  rejects double-close. Noted because a scheduler design must decide what `close`
  means to a parked peer.)

Lowering is a straight builtin call: `lower.ml:414–456` emits `chan_new` /
`chan_send` / `chan_recv` / `chan_close` / `chan_choose` / `chan_offer`;
`llvm_builtins.ml:681–692` maps each to the `march_chan_*` C symbol with a fixed
`declare` signature; `defun.ml:177` lists them as builtin names. **No codegen
change is required to make `recv` block** — the C entry point keeps its
signature; only its body changes. That is a significant cost saving and is
called out again in §7.

Unlike the interpreter, the compiled backend *does* have real concurrency:
actors and tasks are green threads on the M:N work-stealing scheduler
(`runtime/march_scheduler.c`), and compiled `main` is itself a green thread
(`llvm_toplevel.ml:571` → `march_spawn_main` → `march_runtime.c:1478`
`march_sched_spawn(main_fn_green_thread, …)`).

### 1.4 The park/wake precedent

The closest precedent is the `task_await` fix (`specs/todos.md:444`,
`specs/progress.md:835`, commit `21c8a0b0`). `task_wait_done` used to busy-spin
`while(!done) march_sched_yield();`, which cost a full `swapcontext` per
iteration and interacted with LIFO deque dispatch to starve siblings — `par_fib(40)`
took 54.5 minutes. It was replaced with a real park/wake mirroring the actor
mailbox: `march_sched_park_self()` (`march_scheduler.c:1417`) sets `PROC_PARKED`,
`swapcontext`s back to the owning scheduler, and returns only when woken;
`march_sched_wake()` (`:1335`) deposits a wake permit, CASes `WAITING→RUNNABLE`
and pushes to the global runq. Result: 0.73–0.80s, ~4500x.

The mailbox version of the same sequence is `march_sched_recv`
(`march_scheduler.c:1256`), and it is the better model for channels because it
performs its emptiness check *and* its `PROC_PARKED` store **under the same
`mbox_lock`** (`:1273–1286`), which is exactly what the sender's
`march_sched_send` (`:1237`) takes before deciding to wake. A channel pair
already has a `pthread_mutex_t`, so it can hold the same discipline for free.

**Caveat, load-bearing for §8:** `specs/todos.md:433–441` records an **open P0
missed-wakeup deadlock in `task_await`/`task_spawn`** that survives the park/wake
fix — 24 hangs / 500 runs of `test/native/task_burst_await.march`. The todo's own
analysis says `recv` is immune "only because it holds `mbox_lock` across both its
emptiness check and its `PROC_PARKED` store; `task_wait_done` has no such lock."
That is the repo's reasoning, not a measurement I made. It is the single
strongest argument for modelling channel parking on `march_sched_recv` rather
than on `task_wait_done`, and the single largest risk to this whole design.

### 1.5 Observed behavior (probes run for this document)

All five probes were compiled and run at `main` `dbd8bd56` with
`_build/default/bin/main.exe`.

| Probe | Shape | Interpreted | Compiled |
|---|---|---|---|
| `p1_twofn` | tutorial `client`/`server`, called in sequence from `main` | exit 1, `Chan.recv: channel Echo#0 has no pending value` at `client`'s recv | exit 134, `march: Chan.recv on empty channel queue (role 0)` |
| `p2_interleaved` | the same steps hand-interleaved in `main` | exit 0, `echo: hello` | exit 0, `echo: hello` |
| `p3_spawn` | `task_spawn(fn _ -> server(bob))` then `client(alice)` | exit 1, fails inside **`server`** (spawn is eager, so the receiver runs first) | exit 134, fails inside **`client`**, role 0 (the spawned task has not been scheduled yet) |
| `p4_actor` | endpoint passed in an actor message `Go(ch : Chan(Bob, Echo))`, `send` before the handler runs | exit 0, `43` | exit 0, `43` |
| `p5_actor_rev` | same, but the handler's `recv` is reached before `main`'s `send` | exit 1, same error | exit 134, `… (role 1)` |

Three things worth extracting:

1. **`p3` fails on *different sides* on the two backends** — the interpreter's
   eager `task_spawn` runs the receiver first, the compiled scheduler runs the
   sender first. Same source, same class of failure, different diagnostic. Any
   design that only fixes one backend widens that divergence.
2. **`p4` already works, on both backends.** A channel endpoint survives being
   carried through an actor mailbox and used from inside a handler, with correct
   refcounting, today. The plumbing for "a session between two actors" exists;
   only the blocking is missing.
3. **`p2` is the shape the whole golden corpus is written in**, and it never
   touches an empty queue. That is why the parity property in §4.5 is achievable.

---

## 2. Design options

### Option A — park the receiver on the channel, wake it from `send`

`Chan.recv` on an empty queue registers the calling green thread as the pair's
waiter (under the pair lock), parks it, and returns when a `send` on the other
endpoint wakes it. Directly the `march_sched_recv`/`march_sched_send` pattern,
applied to `march_chan_pair` instead of `march_proc`'s mailbox.

**What changes.**

*Compiled.* `march_chan_pair` grows two `march_proc *` waiter slots (one per
role — a binary channel has at most one receiver per direction, because the
endpoint is linear, so a single slot per role suffices and no waiter *queue* is
needed). `chan_dequeue` becomes: take the lock; if non-empty, pop and return
unchanged; if empty, store `self` in the waiter slot, store `PROC_PARKED`,
release the lock, `march_sched_park_self()`, re-acquire and re-loop.
`chan_enqueue` becomes: take the lock, append, read the peer's waiter slot,
release, and `march_sched_wake(peer)` if non-NULL. The abort at
`march_extras.c:1391` is deleted and replaced by the park loop — reached only
when a proc is not running under the scheduler at all (see §4.4).
`march_chan_close` must additionally wake a parked peer with a distinguished
"peer closed" result so the peer errors instead of hanging.

**No lowering or codegen change at all**: `march_chan_recv` keeps its
`declare ptr @march_chan_recv(ptr %ep)` signature (`llvm_builtins.ml:685–686`).

*Interpreted.* This is where Option A gets expensive, and where every previous
survey of F6 has stopped. The interpreter has no coroutines (§1.2), so there is
nothing to park. Two sub-options:

- **A1 — OCaml 5.3 effect handlers.** Declare an effect (conceptually
  `Chan_blocked of chan_endpoint`), perform it from `chan_recv` when `ce_in_q` is
  empty, and install a deep handler around each schedulable unit — a spawned
  task's thunk, an actor handler body, and `main`. The captured continuation is
  stored on the channel; a later `chan_send` on the peer makes it runnable. This
  makes the interpreter a genuine (single-threaded, cooperative) green-thread
  scheduler, which is *also* the prerequisite for making `task_spawn` lazy and
  for fixing the "only the FIRST `receive()` in a handler is safe" limitation at
  `eval.ml:8551`. Large, but it buys three things at once.
- **A2 — compiled-only, interpreted diagnoses.** Compiled `recv` parks;
  interpreted `recv` keeps failing, with a message that says the program needs
  the compiled backend. This *breaks the interp==compiled property* that
  `g38`/`g39` pin, for the new class of programs. Cheap, and dishonest about it.

**Cost.** A: ~200–350 lines of careful C plus the deadlock detector (§4.2);
A1 adds a substantial interpreter restructuring — every path that can run a
March body (`apply`, actor dispatch, the HTTP drain at `eval.ml:3093+`, the DAP
`maybe_pause` hook) has to be effect-safe, and any OCaml-side `try ... with`
that currently spans a March call has to be re-examined, because an effect
performed under it and resumed later changes when handlers run. Estimated
1000+ lines and the real schedule risk.

**What it makes impossible.** Nothing in the language. It does introduce
*nondeterministic interleaving* into channel programs compiled (the scheduler is
work-stealing, `MARCH_NUM_SCHEDULERS` OS threads), which means a channel program
whose *output order* depends on interleaving is no longer a candidate for the
golden corpus. It also makes a genuine hang possible where today there is an
immediate abort — a real regression in debuggability unless §4.2 lands with it.

### Option B — make the limitation a static rule instead of a runtime crash

Leave both runtimes untouched. Extend the typechecker so that a program which
*could* reach a `recv` before its matching `send` does not compile: require both
endpoints of a `Chan.new` to be consumed within one function body, in an order
the checker can verify, and reject any program that passes an endpoint across a
`task_spawn` boundary, an actor message payload, or a function return.

**What changes.** `lib/typecheck/typecheck.ml` only — a whole-program (or at
least whole-function) ordering analysis over channel operations, on top of the
existing per-operation session-state advancement. No runtime work.

**Cost.** Deceptively high. The existing session checker is *local*: each
`Chan.*` arm advances one `TChan` ref's state (`typecheck.ml:307` and the
`Chan.*` arms of `infer_expr`). B needs a *global* ordering property, which is
a different kind of analysis — effectively a small model check over control
flow. And the four recently-closed laundering routes
(`specs/todos.md:1261`; witnesses `t98`–`t103`) are a warning: every
"the compiler tracks channel identity through the program" invariant in this
subsystem has been falsified in practice, repeatedly, by a construct nobody
thought of. A global ordering analysis has strictly more surface to launder.

**What it makes impossible.** The thing the user asked for. It permanently
forecloses a session spanning two green threads or two actor handlers, and it
would **reject `p4_actor`, which works correctly on both backends today** — the
analysis cannot see that the actor's `Go(ch)` handler runs after `main`'s send.
It also converts today's clear runtime diagnostic into a compile-time rejection
of some programs that would have run fine. B is worth stating precisely so it
can be rejected on the record, not adopted.

### Option C — build sessions on actor mailboxes

Delete the channel queues. `Chan.new` allocates two hidden actor-like procs (or
reuses the calling procs' mailboxes with a session tag); `Chan.send` becomes a
tagged `march_send` to the peer proc; `Chan.recv` becomes a selective
`march_sched_recv` filtered to that session id.

**What changes.** `march_extras.c`'s channel section largely disappears
compiled; `eval.ml`'s `chan_*` collapse onto the existing actor mailbox
(including its restart-on-block behavior, which is *wrong* for channels — §1.2).
Blocking comes for free compiled, because `march_sched_recv` already parks.

**Cost.** The endpoint stops being a value that can be freely moved: mailboxes
belong to procs, so an endpoint would become "a right to receive on *this
proc's* mailbox with *this* tag", and moving an endpoint between procs (which
`p4_actor` does today, and which is the point of the feature) requires
re-plumbing the tag. Selective receive over a mailbox that also carries ordinary
actor messages needs a filter and a save-queue, which the compiled mailbox does
not have (`march_sched_recv` pops the head unconditionally, `:1288–1299`), and
which the interpreter has only in the restart-with-requeue form. The
crossed-queue representation is also what makes the two backends byte-identical
today (§4.5); rebuilding on mailboxes puts the parity property back on the table
in both backends at once.

**What it makes impossible.** Cleanly: nothing, in principle. In practice it
couples session lifetime to proc lifetime — a session held across an actor
restart, or between a task and the main thread, becomes awkward — and it
discards the one part of the current implementation (the crossed queues) that is
already correct, verified and pinned.

### Option D (considered, rejected quickly) — bounded spin with a timeout

Keep `recv` non-blocking but retry with `march_sched_yield()` for N ms before
aborting. This is exactly the shape `task_await` used to have and that
`specs/todos.md:444` root-caused as a 54.5-minute perf cliff: each yield is a
full `swapcontext`, which on macOS is real syscalls, and LIFO deque dispatch
re-runs the spinner ahead of the sibling it is waiting for. It would also give
the interpreter nothing (no coroutines to yield to). Rejected on the strength of
that existing measurement; not re-measured here.

---

## 3. Recommendation

**Adopt Option A, compiled-first, with A1 (OCaml effect handlers) as the
interpreter's path — and do not ship the compiled half alone as the final
state.**

Reasons, in order of weight:

1. **It is the only option that delivers the requested capability.** B forecloses
   it by construction. C delivers it but by demolishing and rebuilding the one
   piece that currently works.
2. **The compiled half is small and mechanically precedented.** The pair already
   has a mutex; `march_sched_recv` already demonstrates the exact
   check-park-under-lock / send-and-wake handshake; `march_sched_park_self` and
   `march_sched_wake` are public and in use. Crucially, **no TIR, lowering,
   monomorphization, Perceus or LLVM change is needed** — the C entry points keep
   their signatures (`llvm_builtins.ml:681–692`), so the blast radius stops at
   `march_extras.c` plus a header.
3. **It preserves every program that works today.** A non-empty queue takes the
   identical path it takes now; the hand-interleaved style (§1.5 `p2`, every
   golden, every `accept/` corpus program) never reaches the park branch. This is
   a hard requirement, restated in §5.
4. **It composes with what already works.** `p4_actor` shows an endpoint already
   travels through a mailbox correctly. Option A turns that from "works if you
   get the ordering right" into "works".

**Why not B:** it makes the current limitation permanent and additionally
rejects a working program (`p4_actor`). It also asks the session checker to hold
a *global* invariant when its *local* invariants have been laundered four times
in the last week (`t98`–`t103`).

**Why not C:** it trades a correct, parity-pinned representation for one whose
parity is unestablished, and it couples endpoint mobility to proc identity —
directly against the feature's goal.

**Why not A2 (compiled-only):** the binary channel plane's byte-identical
interp-vs-compiled property is a documented, mechanically-pinned language
guarantee (`session-types.md`; `core-march.md` §4.11.5; `g38`/`g39`). Shipping a
class of programs that run compiled and fail interpreted retires that guarantee
for the newest, most-likely-to-be-copied shape in the chapter. A2 is acceptable
as a *phase boundary* (Phase 1 below), never as the destination — and the phase
must be documented as such in `session-types.md` while it lasts.

---

## 4. Semantics the recommendation implies

### 4.1 Typing rules: unchanged

No typing rule changes. Session-state advancement is a per-operation static
check on a `TChan` ref (`typecheck.ml:307` and the `Chan.*` arms); it is already
oblivious to call order — that obliviousness is precisely what F6 records
(`specs/todos.md:1259`: "session-state advancement is a per-op static check,
oblivious to call order"). Making `recv` block does not change what any operation
is *allowed* to do next; it changes only whether the program reaches the next
operation. `p1_twofn` typechecks today and would keep typechecking; it would
simply also *run*.

Two second-order typing questions do arise, and both are answered "no change":

- **Linearity.** Parking does not duplicate or alias an endpoint. Compiled, `recv`
  still allocates exactly one fresh endpoint on resume and releases the old
  share; interpreted, it still returns the same record. The linear/affine
  tracking added for F7 (`t75`, `t76`) is untouched.
- **The unrefined-`offer` mark.** `Chan.offer` is `chan_recv` of a label
  (`eval.ml:6392`; `march_extras.c:1475`). It would park like any other `recv`.
  The refinement mark is a compile-time table keyed on channel identity
  (`specs/todos.md:1261`); it never reaches the runtime. No interaction.

### 4.2 Deadlock: detected, not hung

Today a mis-ordered session *aborts immediately* with a precise message
(`p1`, `p5`). Blocking `recv` would turn that into a silent hang. **That is a
regression in developer experience and the design must not ship without a
detector.** Recommended semantics:

- **Global quiescence detection, reusing the existing shutdown endgame.**
  `sched_loop`'s idle branch already computes exactly the needed condition:
  nothing runnable in any deque, `g_live_procs > 0`
  (`march_scheduler.c:860–890`). Extend it: if nothing is runnable, no proc is
  RUNNABLE or RUNNING, and at least one proc is parked *on a channel*, the
  program cannot make progress. Report and abort with a diagnostic naming the
  blocked sessions:

  ```
  march: deadlock — every green thread is blocked.
    proc 3 blocked in Chan.recv on Echo#0 (role Bob)
    proc 1 blocked in Chan.recv on Echo#0 (role Alice)
  ```

  This is strictly more informative than today's abort, which names only a role
  index. It requires the parked proc to record *why* it parked — a small
  addition to `march_proc` or a side table keyed by proc.
- **Not timeouts.** A wall-clock timeout on `recv` would make correct programs
  fail under load and would need a user-visible knob. Quiescence is exact for
  the closed-world case (no I/O outstanding). It is *not* exact when a proc is
  blocked in a syscall (an HTTP evloop thread, a socket read): there, quiescence
  can be false-negative — we simply do not detect, and the program waits, which
  is the correct behavior. False *positives* are the danger, and avoiding them
  is the hard part of the detector; see §8 Q3.
- **Interpreted (A1).** With effect handlers the same condition is trivially
  checkable and exact: the interpreter's run queue is a data structure it fully
  owns. If the run queue is empty and at least one continuation is suspended on a
  channel, that is a deadlock — report with the same message shape.

### 4.3 Program exit with a parked session

Today an endpoint can be abandoned mid-protocol and the program exits cleanly
(this is F7's residual, `session-types.md`). Under Option A, abandoning one side
can leave the *other* side parked forever, which under the current shutdown path
would strand `g_live_procs` above zero and hang at
`march_scheduler.c:872`.

The existing daemon endgame is the model. `wake_idle_daemons`
(`march_scheduler.c:754`) already exists precisely so "any program that ends
`main()` while an actor is still alive would [not] hang forever right here"
(`:880`). Proposed rule, symmetric with it:

> Once shutdown is requested and no non-daemon proc remains runnable, every proc
> parked on a channel is woken with a **`peer gone`** result. `Chan.recv` then
> fails with `Chan.recv: the other end of Echo#0 was abandoned`, which is a
> normal March runtime error (exit 1 interpreted / a clean abort compiled), not a
> hang and not a silent success.

`Chan.close` should do the same thing eagerly for its own peer: closing an
endpoint whose peer is parked in `recv` wakes it with `peer gone`. That is a
behavior change relative to today (today `march_chan_close` at
`march_extras.c:1461` only drops a refcount), but only for programs that cannot
currently exist.

### 4.4 Main vs. spawned green threads

*Compiled:* no difference. `main` is a green thread
(`llvm_toplevel.ml:571` → `march_runtime.c:1478`), so `march_sched_park_self()`
works from `main` exactly as from a spawned task. Verified from source, not
measured.

*Foreign threads:* a `recv` executed on a non-scheduler pthread (an FFI callback,
an HTTP evloop thread before B1 lands — `specs/2026-07-09-http-handlers-as-green-threads.md`)
has no `march_proc` to park. `march_sched_park_self` returns immediately in that
case (`march_scheduler.c:1419`, "not running inside the scheduler: nothing to
park"). The design must handle this explicitly rather than spin: mirror the
existing foreign-thread `task_await`, which uses a condvar-based timed wait
(`specs/todos.md:444`, "Foreign-thread (non-scheduler) `task_await` callers are
unaffected — they already used a condvar-based timed wait"). A per-pair condvar
alongside the existing mutex is the natural fit.

*Interpreted:* under A1, `main` must run under the same handler as spawned units,
or a `recv` in `main` would escape the handler and raise
`Effect.Unhandled`. That is a strict requirement on the A1 restructuring, and it
is the main reason A1 cannot be scoped to "just actors".

### 4.5 Interpreted-vs-compiled parity

The binary channel plane is currently byte-identical across backends and pinned
by `g38_chan_int_echo` and `g39_chan_choose_offer` under
`specs/lang/golden/verify.sh` (`core-march.md` §4.11.5). Preserving that requires
four things:

1. **The non-empty-queue path must stay bit-for-bit what it is now.** No extra
   allocation, no changed tagging. The payload tagging symmetry fixed by F1/F2
   (send-site tagging matching `recv`'s conditional `ashr`) is what makes odd
   `Int`s and `Bool`s survive; the park branch must not touch that code path.
   `g38` deliberately carries an *odd* `Int` for exactly this reason.
2. **Both backends must block, or the property is retired for blocking
   programs.** This is the A1-vs-A2 argument in §3. During Phase 1 (compiled
   only), any new golden must remain in the hand-interleaved style.
3. **A golden program must have deterministic output.** A session across two
   green threads has nondeterministic *interleaving* compiled. A golden witness
   for it must therefore print only after a join point — e.g. the spawned side
   prints nothing and `main` prints the received value after `task_await` — so
   that the output is a function of the protocol, not of the scheduler. Under
   A1 the interpreter's cooperative scheduler will make a *different* choice than
   the compiled work-stealing one; only join-point-determined output is safe to
   pin.
4. **Deadlock diagnostics must be identical in text** if a deadlock golden is
   added, which means the interpreter and the C runtime must share the message
   format verbatim (as `Chan.recv:` messages do not today — compare
   `eval.ml:3423` with `march_extras.c:1387`). Aligning those two messages is a
   small, independently shippable improvement and should be Phase 0.

`verify.sh` diffs interpreted against compiled output with **no timeout**
(`specs/lang/golden/verify.sh:24–33`); `sanitize.sh` has a 25s per-run guard
(`sanitize.sh:12`). A hanging golden would wedge `verify.sh` indefinitely.
Adding a per-run guard to `verify.sh` is a prerequisite of any phase that can
produce a hang — see §6.

### 4.6 MPST

Out of scope. `MPST.*` shares the queue idea (N×(N−1) directed queues,
`march_extras.c:1490+`; `eval.ml:96–110`) but is not golden-pinned, and
multiparty `choose`/`offer` do not exist. The same park/wake shape should
generalize, but nothing in this design commits to it. Multiparty deadlock
detection is materially harder (a cycle across ≥3 roles), which is a reason to
defer rather than to bundle.

---

## 5. Blast radius

**Hard constraint: the hand-interleaved style must keep working, unchanged.**
It is the style of every golden, every corpus program, and the runnable example
in `session-types.md`. Under Option A those programs never reach the park branch,
so they are unaffected by construction — but this must be an explicit assertion
in the test plan, not an assumption.

### Programs that would behave differently

| File | Today | After |
|---|---|---|
| `specs/lang/golden/g38_chan_int_echo.march` | MATCH | unchanged (never hits an empty queue) |
| `specs/lang/golden/g39_chan_choose_offer.march` | MATCH | unchanged |
| `specs/lang/types/accept/t41,t42,t43,t44,t79,t92,t104` | `--check` only, never run | unchanged (`check_types.sh` does not execute) |
| `specs/lang/types/reject/t30–t35,t74–t76,t91,t94–t103` | `--check` rejects | unchanged (all are static rejections) |
| `test/test_compiler.ml` (~274 `Chan.` occurrences, `session` suite ~line 8548) | typecheck-level unit tests | unchanged — none execute a channel program |
| `test/test_codegen.ml`, `test/test_helpers.ml:127` | assert `Chan.*` lowers to `march_chan_*` calls | unchanged — signatures are preserved (§3.2) |

**Nothing in `stdlib/` uses `Chan.*` or `protocol`** (verified by grep across
`stdlib/`). **Nothing in `bench/` does either.** There are no `test/native/`
channel programs.

So: **zero existing programs change behavior.** Everything that would behave
differently is a program that today crashes — and there are none of those
checked in, because the corpora were deliberately written to avoid F6
(`core-march.md` §4.11.6: "every golden witness in this corpus is therefore
written with strict send-before-recv program order, by construction, not by
accident").

### Code the change touches

- `runtime/march_extras.c:1302–1477` — the binary channel section (Phases 1–2)
- `runtime/march_scheduler.{c,h}` — quiescence detection; possibly a park-reason
  field on `march_proc` (Phase 2)
- `lib/eval/eval.ml` — `chan_recv`/`chan_send`/`chan_close`, and under A1 a
  substantial scheduler restructuring (Phase 3)
- `specs/lang/session-types.md`, `specs/lang/core-march.md` §4.11 — the Runtime
  note, the "Session types and actors" paragraph, and F6's status (every phase)
- `specs/lang/golden/verify.sh` — add a per-run timeout (Phase 0)

---

## 6. Test plan

Existing harnesses, used as-is unless noted:

- `specs/lang/golden/verify.sh` — interp-vs-compiled byte-identity over the
  golden corpus. **Needs a per-run wall-clock guard added first** (§4.5).
- `specs/lang/golden/sanitize.sh` — ASAN over the same corpus, 25s guard already
  present.
- `specs/lang/types/check_types.sh` — `--check` accept/reject conformance.
- `scripts/run-tests.sh` (or the four direct binaries `run_compiler`, `run_eval`,
  `run_codegen`, `run_stdlib`) — never bare `dune runtest`; judge by `$?`.
- `test/native/` + `test/dune` — compile-and-run native fixtures with pinned
  stdout, the right home for the concurrency cases.

### What proves it works

1. **The tutorial `client`/`server` shape actually runs.** Take `p1_twofn`
   verbatim from `session-types.md` and make it a `test/native/` fixture asserting
   `echo: hello`. This is the headline: the chapter's own example, which today
   crashes on both backends, must run. Once the interpreter blocks too (Phase 3),
   promote it to `specs/lang/golden/g43_chan_two_function_session.march`.
2. **A session across two spawned tasks.** `task_spawn` the server side, run the
   client in `main`, `task_await` the task, print after the join so output is
   interleaving-independent (§4.5 item 3). Run it under
   `MARCH_NUM_SCHEDULERS=1` **and** the default, and repeat it in a loop
   (≥500 iterations, as `specs/todos.md:439` does for `task_burst_await`) — a
   missed wakeup here is a *hang*, and hangs are rate-based, so a single green run
   proves nothing.
3. **A session between two actor handlers.** Extend `p4_actor` so the *server*
   handler's `recv` is reached before the client's `send` (i.e. `p5_actor_rev`,
   which aborts today) and assert it completes. This is the case
   `session-types.md`'s "Session types and actors" section currently says is
   impossible; the doc edit and this test land together.
4. **A deliberate deadlock.** Both sides `recv` first. Assert a **non-zero exit
   within a bounded time** and the deadlock diagnostic text — not a hang. Add it
   to `test/native/` with an explicit timeout, and *not* to the golden corpus
   unless the two backends' diagnostics are made verbatim-identical (§4.5 item 4).
5. **An abandoned-peer exit.** One side parks, the other side is never driven,
   `main` returns. Assert the process exits (does not hang) with the `peer gone`
   error from §4.3.
6. **Regression, non-negotiable:** `verify.sh` and `check_types.sh` both exit 0,
   and `g38`/`g39` still report `MATCH`, at the end of every phase.
7. **ASAN.** `sanitize.sh` over the corpus including the new goldens. The park
   path adds a cross-thread pointer (the waiter slot) into a refcounted structure
   that Perceus frees — precisely the shape that produced the RC/UAF findings in
   `specs/todos.md`. Also run the concurrency fixtures under `MARCH_SANITIZE=1`
   directly, since they will not be in the golden corpus during Phase 1–2.
8. **Benchmarks.** No `bench/` program uses channels, so there is no channel
   benchmark to regress. But Phase 2 touches `sched_loop`'s idle branch, which is
   on every concurrent program's path: run `bench/par_fib.march` compiled
   (`--opt 2`) before and after, since that is the benchmark the park/wake work
   was measured on.

---

## 7. Staged implementation plan

Each phase ends somewhere shippable. Sizes are rough and assume the
`march_extras.c`/`march_scheduler.c` conventions are followed exactly.

**Phase 0 — align the two backends' diagnostics, and guard `verify.sh`.**
Make `eval.ml:3423`'s message and `march_extras.c:1387`'s message identical in
wording, and add a per-run wall-clock guard to `verify.sh` mirroring
`sanitize.sh:12`. No behavior change; makes every later phase's parity claim
checkable and makes a hang fail loudly instead of wedging CI.
*~40 lines. Independently shippable, worth doing regardless of the rest.*

**Phase 1 — compiled `recv` parks; compiled `send`/`close` wake.**
Waiter slots on `march_chan_pair`, check-and-park under the pair lock, wake from
`chan_enqueue` and from `march_chan_close`, condvar fallback for foreign threads
(§4.4). Deletes the abort at `march_extras.c:1384–1391`. Interpreted is untouched and
still errors. Ships with the `test/native/` fixtures 1–3 and 5 from §6, and a
documented, temporary parity note in `session-types.md`.
*~250 lines C + ~150 lines tests. The parity gap is the reason this is not the
end state.*

**Phase 2 — deadlock detection and clean shutdown.**
Park-reason recording, the quiescence check in `sched_loop`'s idle branch, the
`peer gone` wake at shutdown mirroring `wake_idle_daemons`. Ships fixture 4.
This is the phase that converts "can hang" into "reports and exits", and the
phase most likely to surface a false positive under I/O (§8 Q3).
*~200 lines C + tests. Must not ship long after Phase 1.*

**Phase 3 — interpreted blocking via OCaml 5.3 effect handlers (A1).**
Effect + deep handler + a run queue in `eval.ml`; `chan_recv` performs the
effect; `chan_send` makes the peer's continuation runnable. Necessarily also
makes `task_spawn` lazy and can retire the "only the FIRST `receive()` is safe"
limitation at `eval.ml:8551`, though neither is required to ship the channel
work. Restores full interp==compiled parity; promotes the Phase-1 fixtures to
goldens.
*Largest and riskiest: 800–1500 lines and a broad review of every OCaml
`try ... with` spanning a March call. Worth splitting into "introduce the
scheduler + handler skeleton" and "move channels onto it" as two reviewable
commits.*

**Phase 4 — documentation and ledger.**
Rewrite the `session-types.md` Runtime note and the "Session types and actors"
paragraph; close F6 in `core-march.md` §4.11.6 and `specs/todos.md:1259`; add
`CHANGELOG.md` `### Added`; update `specs/progress.md`. Per `CLAUDE.md` these
land *with* the phases, not after — Phase 4 is the residue (the reference-chapter
rewrite), not the whole doc burden.

**Phase 5 (optional, deferred) — MPST.**
Generalize park/wake to the N×(N−1) queues, plus multi-role deadlock detection.
Only worth starting after MPST has a golden witness of its own, which
`core-march.md` §4.11.5 lists as outstanding.

---

## 8. Open questions

1. **Does the open `task_await` missed-wakeup P0 (`specs/todos.md:433–441`) share
   a root cause that would also afflict channel parking?** The todo argues `recv`
   is immune because it holds `mbox_lock` across both its emptiness check and its
   `PROC_PARKED` store, and the channel design copies that discipline — but the
   todo also records that a wake-permit fix which "was necessary-looking but not
   sufficient" measured identically to baseline, i.e. the missed edge is
   *unknown*. Should Phase 1 be gated on root-causing that bug first? I could not
   settle this; I did not attempt to reproduce it.

2. **Interpreted (A1): can effect handlers be introduced without breaking the
   existing exception-based control flow?** `eval.ml` uses OCaml exceptions for
   `BlockedOnReceive`, `Yield`, March-level errors, and the DAP pause hook. An
   effect performed inside a `try` and resumed later re-enters that `try`'s
   dynamic extent at a different time. I did not audit every such site; the count
   and shape of the affected sites is the single biggest unknown in the Phase 3
   estimate.

3. **What exactly makes a quiescence check false-positive-free?** A proc blocked
   in a socket read, an FFI call, or an HTTP evloop thread is not visible to the
   green-thread scheduler as "runnable". Declaring deadlock while an I/O
   completion is in flight would abort a correct program. What is the precise
   predicate — and does it need an explicit "outstanding external work" counter
   that the HTTP/socket/FFI paths maintain?

4. **What should `Chan.close` mean to a parked peer?** §4.3 proposes waking it
   with an error. The alternative is to make `close` on an incomplete protocol
   unrepresentable — but the type system already permits mid-protocol
   abandonment (F7 residual), so the runtime must have *some* answer. Is "peer
   gone" an error, or should the session type gain a failure branch (which is the
   direction `specs/epochs-design.md` takes for supervision)?

5. **Should a blocking `recv` interact with supervision/epochs?** If a session
   endpoint is held by an actor that crashes and is restarted, the peer is parked
   on a channel whose owner no longer exists. `specs/epochs-design.md` designs an
   epoch-stamped `Chan` for exactly this. Does this design need to anticipate it,
   or can epochs be layered on later without re-opening the runtime?

6. **Does the compiled scheduler's work-stealing make any currently-deterministic
   channel program nondeterministic?** I believe not — today no compiled channel
   program can survive a scheduler-dependent interleaving at all, since one side
   aborts. But that is an inference from "nothing in the repo does this", not a
   proof about user code.

7. **A binary channel has one receiver per direction because the endpoint is
   linear — is a single waiter slot per role therefore sound in all cases,
   including after a `Chan.offer` whose continuation is still unrefined?** I
   believe yes (the mark is compile-time only, §4.1), but the "single waiter"
   assumption deserves an explicit argument before it is coded, given how many
   times channel-identity invariants in this subsystem have been falsified.

---

## Appendix: probe programs

The five probes in §1.5 are small enough to reconstruct; they are not checked in.
`p1_twofn` is the `client`/`server` example from `specs/lang/session-types.md`
verbatim, with a `main` that calls `client(alice)` then `server(bob)`.
`p2_interleaved` is the Runtime note's `main` verbatim. `p3_spawn` is `p1` with
`task_spawn(fn _ -> server(bob))`. `p4_actor` puts the server side in an
`actor Server do … on Go(ch : Chan(Bob, Echo)) do … end end` and sends `Go(b)`
after `main`'s `Chan.send`; `p5_actor_rev` sends `Go(b)` before it.
