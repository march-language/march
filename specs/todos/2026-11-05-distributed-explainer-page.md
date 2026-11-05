# A scrolling explainer page for distributed March

Build the long-form docs page designed in
`specs/2026-11-05-distributed-explainer-design.md`: one read of at most
20 minutes that follows `examples/lab_app` from its 16-line `protocol Order` to a running,
failing-over, hot-deployed cluster, with pinned graphics that change as the reader scrolls.

**Status (2026-11-05):** plan Tasks 1 to 12 and the non-publishing parts of Task 14 are
built: the data generator, the scroll engine, the figures and simulations, the opening,
chapters 1 to 4 and the close, with static fallback images. The page is at
`docs/protocol-to-cluster.md` and has no `nav_order`, so the sidebar does not link it.
Still open: chapter 5 (Task 13, blocked on the lab-app item below) and publishing (the
`nav_order`, the `CHANGELOG.md` bullet, moving this file to `specs/progress/`).

The design lists what was measured (generated modules, state types
and functions for `Order`; its fingerprint) and what still has to be verified before the
chapter that depends on it is written:

- the state-map cell counts for `Order`;
- binary sizes per pool;
- how many functions the `hot_role` edit changes;
- whether the lab's `hot_role`, `restart_persist` and `failover` scenarios pass today
  (all three still carry expected-fail markers naming items that have moved to
  `specs/progress/`, and the lab has not been re-run since 2026-10-05);
- what one `Order` message looks like on the wire.

Decided 2026-11-05: evidence for the cluster and deploy chapters comes from the two-node
CI scenarios plus labelled simulations, with lab numbers swapped in as the lab passes; and
the work includes extending `examples/lab_app` and `scripts/lab` with a canary step, a
failing-canary scenario and one actor with a state migration.

The build plan is `specs/plans/2026-11-05-distributed-explainer-page-plan.md`. Its chapter 5
task is blocked on `specs/todos/2026-11-05-lab-app-canary-and-migration.md`.

When it lands: a `### Documentation` bullet in `CHANGELOG.md`, and move this file to
`specs/progress/`.
