# Growing-mailbox alarm, polled: `Actor.top_by_mailbox` / `Actor.over_mailbox`

Landed 2026-09-10. Partial completion of
`specs/todos/2026-08-12-per-actor-introspection-and-alarms.md`, which stays
open, trimmed, for the push-style alarm, per-actor state inspection, and
tracing.

Both are stdlib-only, on top of `Actor.list()` and `mailbox_size`:

- `Actor.top_by_mailbox(n) : List((Pid, Int))` — the `n` deepest mailboxes,
  deepest first (stable, so ties keep spawn order).
- `Actor.over_mailbox(threshold) : List((Pid, Int))` — every actor deeper
  than the threshold, in spawn order; empty is the healthy case.

The todo suggested doing the walk inside the runtime to avoid materialising
every actor. Not done: `Actor.list()` already materialises a list of ints, and
a monitor calls this from a timer, so the extra map+sort is not on any path
that matters. If a profile ever shows otherwise, the runtime walk can replace
the body without changing the signature.

`test/native/actor_mailbox_alarm.march` pins the shape (ordering, cut, filter,
empty-when-healthy) on both backends; exact depths race on the compiled
backend, so they are deliberately not in the golden. Documented in
`specs/lang/actors.md`, `docs/actors.md`, and `docs/overload-resilience.md`
step 2.
