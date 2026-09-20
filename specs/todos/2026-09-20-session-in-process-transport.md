# `[P3]` A stdlib in-process session transport

Filed 2026-09-20 by the choreography UX pass ([[2026-09-20-choreography-ux-hardening]]).

The guide's "Testing without a network" says to attach an in-process transport and points
at a hand-written `Session.Ops`. Every test that does this carries its own copy
(`test/session/stream_actor_events.march` has a complete one in about sixty lines: a
mailbox per endpoint, `suspend` installing the handler, `emit` delivering in the same
turn or parking). Ship it once, as `Session.in_process()` (or `SessionNode.loopback()`),
returning the `Ops` and a way to drive parked deliveries, so a role can be unit-tested
with `Session.attach(c, Session.in_process())` and nothing else. Include cancellation
(`on_cancel`, `leave`, `fail`) so the failure paths are testable in-process too.
