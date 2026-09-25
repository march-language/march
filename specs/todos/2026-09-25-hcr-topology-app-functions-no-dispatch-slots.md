# `[P2]` Hot reload: a topology app's own functions get no dispatch slot, and generated names renumber

Found by `forge deploy`'s end-to-end test (distributed-deploys build step 10b,
[../progress/2026-09-22-dd-step10-ssh-backend-and-plan.md](../progress/2026-09-22-dd-step10-ssh-backend-and-plan.md)).
Compiler side (bin/, lib/tir/); forge works around both and says so in `--plan`.

1. **No slots for the entry module's functions.** In a topology app the entry
   module's declarations reach TIR without the entry module's name
   (`Back.serve_one`, `Front.start`, `main`), so `--hot-reload <entry module>`
   (`Hot_reload.is_reloadable`, `under app_prefix`) covers none of them. A running
   `examples/topology_app` base answers `ABI_QUERY` with ten slots, all actor
   dispatchers. Either name them under the entry module, or let `--hot-reload` take
   several prefixes (`Hot_reload.config.includes` exists but has no flag).
2. **Generated names come from a global counter.** A one-token edit
   (`state.total + n` → `state.total + n + 1` in a handler) renumbers every later
   `$lam<n>`/`$jp<n>`, and every function that references one gets a new impl hash
   (`Front.count`, `Front.start` (a hook), `main`), although its code is unchanged.
   Two fresh builds of the same source are identical, so this is edit-driven, not
   nondeterminism. A handler's own body lives in `<Actor>_<Msg>` (e.g.
   `CounterActor_Deliver`), which has no slot; `<Actor>_dispatch` did not change.

Effect today: almost any edit to a topology app plans a restart (`Deploy_plan`
restarts when a changed function has no slot and no changed slotted caller). Hot
patches work for code under a pool-module prefix (`[hot-reload] module_prefix =
"Back"`) and edits that make no new generated names.

**Acceptance.** Editing a role body of `examples/topology_app` plans and deploys as a
hot patch (`forge/test/test_deploy_e2e.ml` without the `module_prefix` override).
