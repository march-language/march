`[P2]` # No graceful shutdown: death discards the mailbox instead of draining it

## The gap

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
