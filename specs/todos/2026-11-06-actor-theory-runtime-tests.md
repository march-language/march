`[P2]` Actor.Theory: the rest of the runtime tests (A3 fixture, A4 RC fixtures, trace-driven M8)

Progress `2026-11-06-actor-theory` proves A1-A3 on the mailbox model and tests A1 (and, via
existing fixtures, A2) against the runtime. The guarantee report labels `DOWN` delivery
`proved (model)` only. Open:

1. **A3 runtime fixture.** A watcher with a capped mailbox (`Actor.set_queue_limit`, drop_new)
   kept busy while it fills, monitoring an actor that then dies: its `Down` must arrive
   (bypassing the limit, specs/lang/actors.md "Monitoring Actor Death") exactly once, and a
   second death path (demonitor, kill) adds none. Then the report's `DOWN delivery` line becomes
   `proved (model) · tested (runtime)`.
2. **A4: one RC-trace fixture per send path** (design §4.6): `send`, `Actor.cast`,
   `Actor.call`'s envelope, `Node.send`, `migrate_msg`'s consumed message, the `None` drop;
   each asserts zero live objects at exit under `--rc-trace` + `scripts/gc-trace-report.py`.
3. **Trace-driven conformance.** Replace the application-level log with the observe trace's
   `received` events (stdlib/trace.march): needs the `received` event to carry the sender
   (today `peer` is only set on `sent`), so a conformance run can rebuild the queue without
   instrumenting the handler.
