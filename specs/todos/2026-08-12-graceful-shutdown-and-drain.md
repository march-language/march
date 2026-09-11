`[P2]` # Graceful shutdown: the `terminate` callback and reload drain-first

> **Partially landed 2026-09-08.** `Actor.stop(pid, timeout_ms)` now marks an
> actor draining (new sends refused), works off the queued messages until the
> mailbox empties or the deadline passes, and ends in a NORMAL death; a
> supervisor stops its children first in reverse declaration order, each with
> its own `shutdown` budget from the child spec. See
> `specs/progress/2026-09-08-graceful-shutdown-and-drain.md`. This file is
> trimmed to the two pieces that did NOT land.

## What remains

### 1. No `terminate`-style callback

An actor can finish the messages it has queued, but it cannot run code of its
own at shutdown — it cannot flush a buffer, checkpoint state, or hand
unfinished work back to a queue. That needs a new actor-level declaration (an
`on_stop`-shaped handler) and a decision about what it may do: whether it can
send, whether its own failure aborts the shutdown, and whether it runs on the
brutal path as well as the drained one.

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

An actor with N queued messages that is `stop`ped processes all N (or hits a
stated deadline) before dying; a supervision tree stops children in reverse
declaration order; `kill` keeps today's immediate semantics.
