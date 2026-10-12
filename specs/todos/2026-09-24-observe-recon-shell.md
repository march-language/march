`[P2]` **Observe / Recon / remote shell / release bundle: operator tooling for running nodes.**

Design: [`specs/2026-09-24-observe-recon-shell-design.md`](../2026-09-24-observe-recon-shell-design.md).
Plan (authoritative where they differ): [`specs/plans/2026-09-28-observe-recon-shell-plan.md`](../plans/2026-09-28-observe-recon-shell-plan.md).
Builds on the per-actor introspection design
([`2026-08-12-per-actor-introspection-and-alarms.md`](2026-08-12-per-actor-introspection-and-alarms.md));
the plan's R4 and R8 deliver its stages B1 and C.

Items, each its own PR; tick as they land and add a dated
`specs/progress/YYYY-MM-DD-observe-rN-<slug>.md` per item:

- [x] R0 observe socket thread, JSON writer, test harness ([progress](../progress/2026-10-01-observe-r0-socket.md))
- [x] R1 snapshot layer + observe verbs (no new counters) ([progress](../progress/2026-10-02-observe-r1-snapshot-verbs.md); the cluster section split out to [its own todo](2026-10-02-observe-r1-cluster-section.md))
- [x] R2 counters, scheduler idle time, crash ring (A/B per commit) ([progress](../progress/2026-10-02-observe-r2-counters-crash-ring.md))
- [x] R3 `Recon` observe tier, `forge top`, `forge diagnose`, `forge status` ([R3a](../progress/2026-10-04-observe-r3a-recon.md), [R3b-d](../progress/2026-10-04-observe-r3b-diagnose-top-status.md))
- [x] R4 debug tier: `Actor.Debug`, `inspect_state`, signed `STATE`/`CRASHES_FULL`, nonces, policy, audit ([R4a](../progress/2026-10-05-observe-r4a-inspect-state.md), [R4b](../progress/2026-10-05-observe-r4b-signed-debug-verbs.md); `MESSAGES` split out to [its own todo](2026-10-05-observe-messages-verb.md))
- [x] R5 shell groundwork, adapted to self-contained fragments (2026-10-06/08): the cap manifest ([progress](../progress/2026-10-06-shell-cap-manifest-library-caps.md)), build identity by source hash ([progress](../progress/2026-10-07-shell-build-identity.md)), fragments calling the node's own functions ([progress](../progress/2026-10-07-shell-calls-node-functions.md)), limit-aware rendering ([progress](../progress/2026-10-07-shell-render.md)). Not built: pinned NAME_IDs (fragments call nothing through dispatch). The security review is still to do: [packet](../reviews/2026-10-07-shell-r5-review-packet.md)
- [x] R6 `forge rpc` / `forge shell` (2026-10-06/08): [node listener](../progress/2026-10-06-shell-node-listener.md), [client](../progress/2026-10-06-shell-client-march-shell.md), [program lowered once](../progress/2026-10-06-shell-program-lowered-once.md), [Linux latency gate met](../progress/2026-10-07-shell-latency-linux-gate.md) (p50 110 ms, gate 300), [spawning actors](../progress/2026-10-07-shell-spawn-actors.md), [`--force`](../progress/2026-10-07-shell-force.md), [line editing](../progress/2026-10-08-shell-line-editing.md), [review fixes F1-F4](../progress/2026-10-08-shell-review-findings-f1-f4.md). `forge eval` is not built
- [ ] R7 `forge observe` TUI, `WATCH`, crash dumps
- [ ] R8 tracing with mandatory limits + boundary call tracing
- [ ] R9 `forge release build` + `bin/<app>`
- [ ] R10 `Recon.which` / `Recon.source`

Move this file to `specs/progress/` when R10 lands; the R11 items (transcripts,
`--env` fan-out, notebook attach, `Observe.serve_http`) get their own todos then.

Related: [`2026-09-26-compiled-logger-appenders-are-no-ops.md`](2026-09-26-compiled-logger-appenders-are-no-ops.md)
blocks any events bus, which this work does not include.

Quick-win results (2026-09-29): [`progress/2026-09-29-observe-quick-wins-results.md`](../progress/2026-09-29-observe-quick-wins-results.md).
All four passed; they found three pre-existing bugs (one since fixed by #709, two filed as 2026-09-29 todos).
