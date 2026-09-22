`[P2]` # Graceful shutdown: reload drain-first (the `terminate` callback landed)

> **Partially landed 2026-09-08.** `Actor.stop(pid, timeout_ms)` now marks an
> actor draining (new sends refused), works off the queued messages until the
> mailbox empties or the deadline passes, and ends in a NORMAL death; a
> supervisor stops its children first in reverse declaration order, each with
> its own `shutdown` budget from the child spec. See
> `specs/progress/2026-09-08-graceful-shutdown-and-drain.md`. This file is
> trimmed to what did NOT land (the `terminate` callback followed on
> 2026-09-22).

## What remains

> Updated 2026-09-22: the `terminate` callback (piece 1) has landed; only the
> reload drain-first story remains. It needs a *pause* state distinct from
> `draining` (a reloading actor must keep accepting sends, not refuse them).


### 1. ~~No `terminate`-style callback~~ — landed 2026-09-22

Actors now declare `on_stop do ... end`; see
`specs/progress/2026-09-22-actor-on-stop-terminate-callback.md` and "Stopping an
Actor" in `specs/lang/actors.md`. Semantics decided 2026-09-22 on OTP's
`terminate/2`: it may send; a failure inside it is logged and the NORMAL death
proceeds; it does not run on the brutal path; it is bounded by the stop
timeout. One interaction with the item below: under `--hot-reload` the
callback the runtime holds (`march_register_actor_on_stop`, keyed by the
dispatch closure) is the one from the code the actor was spawned with, so
after a reload that changes the state layout it would run against migrated
state. The reload work should look the callback up through the current code
version (as dispatch does via `hcr_enter`) or skip it for a migrated actor.

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

Still to meet (the `terminate` bullet was met 2026-09-22):

- **reload drain:** a reload waits for the in-flight handler and queue under a
  pause state (sends still accepted) before swapping code.
