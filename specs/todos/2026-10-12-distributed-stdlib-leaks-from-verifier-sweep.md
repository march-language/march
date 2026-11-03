# Seven leak findings left in distributed stdlib code (verifier leak sweep)

Filed 2026-10-12 from `specs/progress/2026-10-12-verifier-leak-sweep.md`. Every program reports
these under `MARCH_VERIFY_TIR_LEAKS=1`, because every compile includes the stdlib. They were
left alone because the code is distributed.

| function | finding at `tir-perceus` |
|---|---|
| `Session.ip_step` | `st`: one arm holds one more reference than another at a join (`case $t: Some`, deep in a nested case) |
| `ClusterNode__CtlWriter_CtlWrite` | `state`: the `Err` arm holds one more than another at a join (actor handler: once per message) |
| `ClusterNode.start_writers` | `h`, an owned parameter, held at the end of the path |
| `ClusterNode.on_accepted` | `old`, bound to an `Option({ addr, cfd, .. })` match, held on the default path |
| `Control.agent_apply_certs_recording` | `o`: the `True` arm holds one more than another at a join |
| `$lam0__lam5_SessionNode_candidates$apply$6` / `$lam1_..$apply$7` | the tuple's first field `g`, typed `'_` (an erased TVar), is read for `g.node_id` and never released. A TVar is not an aggregate, so the aggregate scope-end drop skips it, and a field read is not a release |

To triage one: `march query fn NAME <any program> --at tir-perceus` shows the body. A
`live_allocs()` loop around a non-distributed reduction of the same shape, compiled versus
interpreted, tells a real leak from a model gap. The three fixed in this sweep were each
reproduced that way, outside distributed code (`test/native/partial_release_aggregate_drop.march`).
