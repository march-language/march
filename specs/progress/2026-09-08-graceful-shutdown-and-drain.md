# Graceful shutdown: `Actor.stop` drains the mailbox

Landed 2026-09-08. Partial completion of
[`specs/todos/2026-08-12-graceful-shutdown-and-drain.md`](../todos/2026-08-12-graceful-shutdown-and-drain.md),
which stays open, trimmed, for the `terminate` callback and the hot-reload
drain-first story.

## What landed

`Actor.stop(pid, timeout_ms)` (builtin `actor_stop`, plus `actor_is_draining`):

1. marks the actor **draining** — `march_send` then refuses new messages with
   `MARCH_SEND_DRAINING`, distinct at the C level from `MARCH_SEND_DEAD` and
   `MARCH_SEND_DROPPED` (March's `send` reports it as `None`, the same way it
   reports a dead target: not accepted);
2. lets the actor's own green thread work the queue off — the drain gate sits
   at the top of `actor_green_thread`'s receive iteration, so an actor that was
   mid-handler finishes that handler first;
3. ends it with `MARCH_DEATH_NORMAL`, which no restart type restarts, so a
   stopped child does not fight its supervisor.

Per-child `shutdown <ms> | infinity | brutal` landed with it — surface decided
in [`specs/2026-09-08-supervise-child-spec-design.md`](../2026-09-08-supervise-child-spec-design.md),
lowered as a sixth `march_actor_register_child` argument into
`march_sup_child.shutdown_ms`. Default 5 seconds, which is safe precisely
because it is unobservable to older programs: `stop` did not exist when they
were written, and `kill` does not consult it.

Stopping a supervisor walks `sup_children` in REVERSE (declaration order is
start order), detaching each child before stopping it — an orderly teardown
must not run a restart strategy against a parent that is itself on the way
out, or the children come straight back and the tree never goes down.

## The decision worth recording: `stop` is synchronous

The first implementation returned as soon as the actor was marked draining.
That made the same program produce two different observable orderings —
the interpreter's eager scheduler drains inline, so its output was ordered,
while the compiled backend's handler output interleaved with main's — and no
single `.expected` could cover both.

It is also worse API. A deploy sequence's whole point is knowing when the
in-flight work is finished; a caller that has to poll `is_alive` afterwards has
been handed back the hard half. `march_actor_stop` now waits for the actor to
die, bounded by the same deadline, EXCEPT when the caller is the actor being
stopped (it cannot wait for the queue it is standing in — it marks itself
draining and the receive loop finishes the job).

## Tests

`test/native/actor_stop_drains_mailbox.march` and `actor_stop_tree.march`, each
run compiled AND interpreted against one `.expected`, plus
`actor_stop_tree.order.expected` which asserts the reverse teardown order off
the `MARCH_SUP_TRACE` line both backends emit.

A `kill` contrast is deliberately NOT in the drain golden. On the compiled
backend the actor's green thread races main, so whether a killed actor's queued
messages were already handled is genuinely nondeterministic — the first draft
of that fixture printed the messages on one run and not the next. Both fixtures
were checked for stability over five consecutive runs.

## A trap this change walked into

`lib/tir/cap_passing.ml` matched the `register_supervisor_child` call with a
five-element list pattern. Adding the `shutdown_ms` argument silently stopped
that arm from matching, so a supervisor nested under another supervisor quietly
lost its children's capabilities. Nothing failed except
`cap_mock_supervised_nested`. The pattern now matches by SHAPE
(`sup :: ptr :: AVar sf :: child_spec_args`), so the next field the child spec
grows passes through untouched.
