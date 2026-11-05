# A scrolling explainer page for distributed March

Build the long-form docs page designed in
`specs/2026-11-05-distributed-explainer-design.md`: one read of at most
20 minutes that follows `examples/lab_app` from its 16-line `protocol Order` to a running,
failing-over, hot-deployed cluster, with pinned graphics that change as the reader scrolls.

**Status (2026-11-05):** published without its deploy chapter. Built and live in the
sidebar (Concurrency, after Choreography): the data generator, the scroll engine, the
figures and simulations, a line-by-line walkthrough of the protocol, chapters 1 to 4 and
the close, with generated fallback images. `CHANGELOG.md` has its bullet.

Still open, which is why this file is not in `specs/progress/` yet:

- chapter 5, "Deploying while it runs" (plan Task 13), blocked on the lab-app item below.
  Its simulation core and renderer are built and tested. Until it lands the page says the
  section is not written yet, and a test forbids the page from promising it;
- the minors the branch review deferred (listed in the pull request);
- not checked in a browser: reduced motion, JavaScript disabled, a timed read-through.

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
