`[P2]` Object capabilities phase 8: capture checking (2026-11-12)

Implement the static layer of the ocap design: capture sets on function types and on
values that hold function values or scoped handles, inferred everywhere except public
signatures; scoped-handle escape checking; the public-signature rule with the stdlib
migration and `forge fix`. Waits on phase 4 (run-time authority).

Design: `specs/2026-11-11-ocap-capture-checking-design.md` (approved 2026-11-12). It ships
in three steps, 8a (inference and display, no new errors), 8b (`scoped` parameters and
escape), 8c (public signatures). Parent design: `specs/2026-11-10-object-capability-design.md`
§13 and the phases table in §17.
