# Lab app: a canary step, a failing canary and a state migration

The distributed explainer (`specs/2026-11-05-distributed-explainer-design.md`) shows a
canary step, a halted release and an actor state migration for `examples/lab_app`. The lab
app does none of them today:

- `scripts/lab` deploys with `forge deploy --env lab --yes` and no `--canary`;
- no lab scenario covers a canary that fails its gate;
- the lab app has no `migrate_state`, and its only actor on a work node (the ledger) hosts
  sessions, so it takes an epoch hold instead of migrating at its marker.

Decided 2026-11-05: extend the lab app and its scripts so those cards are real.

To do, and to plan before building:

- deploy the lab with a canary step and record the window it uses;
- add a scenario where the canary fails its gate and the release halts;
- add one actor that does not host sessions, with a state shape change and its
  `<actor>_migrate_state`, and a scenario that deploys the change;
- re-run the lab. `hot_role`, `restart_persist` and `failover` still carry expected-fail
  markers naming items that have moved to `specs/progress/`; remove each marker whose
  scenario now passes;
- note the new scenarios in `docs/lab.md`.

Three things to settle in that plan: which actor carries the migration and how its state is
observed from outside; how a scenario switches the lab app's source to the second version;
and how a canary failure is induced.

Task 13 of `specs/plans/2026-11-05-distributed-explainer-page-plan.md` is blocked on this.
