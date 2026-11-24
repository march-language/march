`[P2]` Object capabilities phase 8: capture checking (2026-11-12)

Implement the static layer of the ocap design: capture sets on function types and on
values that hold function values or scoped handles, inferred everywhere except public
signatures; scoped-handle escape checking; the public-signature rule with the stdlib
migration and `forge fix`. Unblocked: phase 4 (run-time authority) landed 2026-11-17
(`specs/progress/2026-11-15-ocap-p4-runtime.md`).

Design: `specs/2026-11-11-ocap-capture-checking-design.md` (approved 2026-11-12). It ships
in three steps, 8a (inference and display, no new errors), 8b (`scoped` parameters and
escape), 8c (public signatures). Parent design: `specs/2026-11-10-object-capability-design.md`
§13 and the phases table in §17.

**Status (2026-11-24).** 8a is done: `specs/progress/2026-11-24-ocap-p8a-capture-sets.md`
(inference, hover, `march --dump-captures`, the soundness oracle; no new errors). Open: 8b and
8c. Before 8b: `specs/todos/2026-11-24-ocap-capture-pass-always-on-prerequisites.md`.
