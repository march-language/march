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
- [ ] R4 debug tier: `Actor.Debug`, `inspect_state`, signed `STATE`/`MESSAGES`, nonces
- [ ] R5 shell groundwork: body hashing, pinned NAME_IDs, per-function attach check, fragment emission, cap-marker check (security review before R6)
- [ ] R6 `forge rpc` / `forge shell` / `forge eval` over signed `EVAL`
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
