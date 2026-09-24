# Distributed deploys, build step 5: Model B deferred, not required

**CLOSED 2026-09-23.** The decision below is the outcome of step 5: Model B does
not precede step 6 and is not required by any later step of the plan. Step 6
landed on today's dispatch (`specs/progress/2026-09-23-dd-step06-epoch-model-and-drains.md`),
with `march_dispatch_enter_unit` on the call path as II.4.1 designs it. The larger
ORC-JIT Phase 0 spike stays where it was filed, as its own optional item in
`specs/todos/2026-07-31-p2-runtime-hot-code-reloading.md`; it is not tracked here.

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), section 6.7, II.7.

**Decided (2026-09-23), from groundwork G1**
(`specs/progress/2026-09-23-hot-reload-boundary-cost.md`):

- **Model B does not precede step 6.** `--hot-reload` versus plain on `list_ops_nested`
  (the `list_ops` variant whose helpers sit on the boundary) is about +1 %, against II.7's
  10 % threshold. Hot-reloadable production builds (D8) hold on today's `enter`/`leave`
  dispatch, so steps 6–12 proceed in order.
- **The epoch read stays on the call path.** `march_dispatch_enter_unit` versus `enter` on
  `actor_ping` is within 0.5 %, inside run-to-run noise, so step 6 builds
  `enter_unit` as II.4.1 describes and does not hoist the read into the actor loop.

Both rest on samples taken at 1-minute load 6.5–7.7, not the planned 5, and on
benchmarks that make few boundary calls (`list_ops_nested`'s cost is a floor, not a
typical app's). If step 6 lands an app-shaped benchmark with many boundary calls per
unit of work, re-check the first threshold there.

**What remains, optional.** The larger Model B (ORC JIT) Phase 0 spike in
`specs/todos/2026-07-31-p2-runtime-hot-code-reloading.md`, for the ORC question on its own
merits. It is no longer a prerequisite for anything in this plan.

**Acceptance (as filed).** "Close this file when the ORC spike is either run or dropped."
Closed instead on the decision itself, as the step-6 task directed: the ORC spike
is no longer part of this plan.
