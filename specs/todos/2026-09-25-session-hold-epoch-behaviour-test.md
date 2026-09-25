# `[P3]` No behavioural test of SessionNode's HoldEpoch / ReleaseEpoch

**Filed** 2026-09-25, split out of the DD review's step-6 test-gap item (closed in
`specs/progress/2026-09-25-dd-review-step6-untested-behaviours.md`). Only
`stdlib/session_node.march` names `HoldEpoch`/`ReleaseEpoch`; the hosted-API test
checks generated call counts, not behaviour. Deferred while D27 (session drains, PR
#648) rewrote the hold code; D27 has since landed and covers the release by counting
live procs in `cluster_ap_local` (`2026-09-24-dd-review-cluster-party-never-releases-epoch-hold.md`),
noting that a PINS-through-a-deploy test "needs a local reload client". One exists
now: `test_hcr_migrate_msg_converts_real_old_message` (test/test_stdlib_suite.ml)
deploys through a local socket with `Cmd_deploy_hot.run ~tunnel:false`.

**Do.** A compiled session test through the reload socket: a session spanning a
deploy holds its endpoint's epoch (PINS shows the old epoch pinned by it) and
releases it when the session ends (the old epoch's pins reach 0); it must go red with
the hold or the release removed.
