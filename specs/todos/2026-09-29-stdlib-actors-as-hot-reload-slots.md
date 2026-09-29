`[P3]` Should a stdlib actor be a hot-reload slot at all?

Split out of `specs/progress/2026-09-29-hot-deploy-swim-default-timeout.md`
(item 3 of the todo it closed). An owner decision; not decided there.

`is_actor_dispatch_fn` puts every `*_dispatch` on the hot-reload boundary,
stdlib actors included (lib/tir/llvm_toplevel.ml, `hr_names`); only app actors
need to be. Before #663 that meant every deploy re-activated the stdlib's own
actors (`ClusterNodeActor_dispatch`, which runs SWIM, and `Endpoint_dispatch`),
each migrating to a new epoch at its next marker.

Evidence so far (2026-09-29): with #663's canonical lambda-hash fold, the
per-node audit logs of six ASan deploys in `hcr_new_code_session` show only
the app's changed functions activated (`Buy.version`; `Host.version`,
`Host.host_tick`), no stdlib actor. So today a stdlib actor is re-activated
only when its own code changes, i.e. when a patch is built against a
different stdlib. Whether that should be possible at all (a patch that
changes the node's SWIM or session machinery live) is the question.
