`[P2]` # Graceful shutdown: the `terminate` callback and reload drain-first

> **Partially landed 2026-09-08.** `Actor.stop(pid, timeout_ms)` now marks an
> actor draining (new sends refused), works off the queued messages until the
> mailbox empties or the deadline passes, and ends in a NORMAL death; a
> supervisor stops its children first in reverse declaration order, each with
> its own `shutdown` budget from the child spec. See
> `specs/progress/2026-09-08-graceful-shutdown-and-drain.md`. This file is
> trimmed to the two pieces that did NOT land.

## What remains

> Reviewed 2026-09-10, unchanged: both pieces below are still open. The
> `terminate` callback is a full pipeline feature (parser, desugar,
> typecheck, eval, lower, codegen, runtime) and the reload drain-first story
> needs a *pause* state distinct from `draining` (a reloading actor must keep
> accepting sends, not refuse them), so neither fit the batch that closed the
> neighbouring actor todos.


### 1. No `terminate`-style callback

An actor can finish the messages it has queued, but it cannot run code of its
own at shutdown — it cannot flush a buffer, checkpoint state, or hand
unfinished work back to a queue. That needs a new actor-level declaration (an
`on_stop`-shaped handler) and a decision about what it may do: whether it can
send, whether its own failure aborts the shutdown, and whether it runs on the
brutal path as well as the drained one.

**Semantics decided (repo owner, 2026-09-22), modelled on OTP's `terminate/2`:**

1. **It may send messages.** A terminate callback is ordinary handler code;
   `send` works from it (to hand work back, notify a peer, flush to a sink).
2. **A failure inside it is logged and shutdown continues.** The actor is dying
   anyway; a panic/exception in terminate is reported and the death proceeds
   as if terminate had returned. A broken terminate must never wedge a
   shutdown, and it does not turn a NORMAL death into a crash that a
   supervisor would restart.
3. **It does NOT run on the brutal-kill path.** `kill` (and a child spec's
   `shutdown brutal`) means "stop now, run nothing" — that is what brutal is.
4. **It is bounded by the existing stop timeout.** `Actor.stop(pid,
   timeout_ms)` (and a supervisor's per-child `shutdown <ms>`) is the budget
   for drain AND terminate together: if terminate has not finished by the
   deadline, the actor is killed.

It is also the missing observability channel for teardown ORDER. Reverse
declaration order is implemented and asserted today only via a
`MARCH_SUP_TRACE` stderr line (`test/native/actor_stop_tree.order.expected`),
because there is no in-language event at teardown time to observe it with: a
child that printed from a handler races main on the compiled backend.

### 2. Hot code reload has no drain-first story

`runtime/march_reload.c` migration carries state across a code swap but does
not drain the queue first. The draining flag now exists; wiring migration to
stop-then-swap-then-resume is untouched.

## The original gap, for context

Actor death is immediate and lossy. The 2026-08-12 hardening (Task 14) added a
reap-time mailbox drain, but that drain **disposes** queued messages — it frees
them to fix a leak, it does not process them. There is also:

- no `terminate`-style callback (an actor cannot flush, checkpoint, or hand
  work back before dying);
- no shutdown *timeout* — nothing waits for an actor to finish the message it
  is currently handling;
- no ordered shutdown of a supervision tree (OTP stops children in reverse
  start order; March has no ordering at all).

## Why it matters

This is the deploy story. Rolling a node means: stop accepting new work, let
in-flight work finish, then exit. Today the only way to stop an actor is
`kill`, which drops whatever was queued — so a deploy loses exactly the
requests that were waiting. The bounded-mailbox work made overload *survivable*;
this is the other half, making shutdown *lossless*.

Note the interaction with hot code reload (`runtime/march_reload.c`): migration
already has a story for carrying state across a code swap, but not for draining
the queue first.

## Sketch

A `stop(pid)` distinct from `kill(pid)`: mark the actor as draining (rejects
new sends with a distinct result — cf. the `MARCH_SEND_*` codes added in Task
7), let the recv loop run until the mailbox empties or a deadline passes, then
die. The Task 2 timer heap gives the deadline for free.

For trees, shutdown order needs the child ordering the supervisor already
stores (`sup_children` is in declaration order — the same order
`rest_for_one` relies on), walked in reverse.

Interacts with `2026-08-12-supervisor-restart-types-and-child-specs.md`: OTP
packages the per-child shutdown timeout in the same child spec as the restart
type, so design them together.

## Acceptance

The drain half is met and shipped (2026-09-08, see the progress file above):
`Actor.stop` works a queued mailbox off (or hits its deadline) before a NORMAL
death, a supervision tree stops children in reverse declaration order, and
`kill` keeps its immediate semantics.

Still to meet:

- **terminate:** an actor-level on-stop callback that runs on `Actor.stop` and
  on a NORMAL death, sees the final state, may send; a failure inside it is
  logged and the actor still dies (its supervisor proceeds); it does not run
  on brutal kill; it is cut off by the stop deadline. Both backends agree.
- **reload drain:** a reload waits for the in-flight handler and queue under a
  pause state (sends still accepted) before swapping code.
