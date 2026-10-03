# Hot reload: a patch's slot ids by name; changed new slots carried by their callers

**Date:** 2026-10-02

## Symptom

The two-node scenario `protocol_expand_contract` failed on main from #751
("entry-module top-level functions are slots") on: both nodes died with
`march: fatal SIGSEGV si_code=2 addr=0x62 ... fault outside its stack` during
the expand/contract hot deploy. This failed `two-node (2/2)` on every PR (e.g.
PR #748's run 37028812203). Bisected: 521d77eca passes, a525bdb45 (#751) fails.

## Cause 1: a patch .so called slots by its OWN table's ids

A boundary call is `march_dispatch_enter_unit(NAME_ID)`, and NAME_IDs are dense
in sorted-name order over the build's slot set (`Hot_reload.Name_table`). The
base binary's ids are the running table's. A patch `.so` emitted ids from its
own build's table, which is a different one as soon as the new version adds or
removes a slot. Version 2 of the scenario adds `may_choose_later` (sorting
between `host_tick` and `node_a`), so every later id moved up by one: the patched
`shop`'s call to `shop_phase` (patch id 20) entered `start_driver`'s slot (base
id 20). Before #751 the entry module's functions had no slots, so the patch's
shifted ids were never used.

Fix (`Llvm_ctx.hr_slot_id`): in a hot-reload `--compile-so`, every slot id at a
call site (`llvm_emit_call.ml`) and at an actor's `march_actor_set_dispatch_id`
(`llvm_emit_alloc.ml`) is loaded from a private per-name cell. `__march_init`,
which the reload server calls after dlopen and before activating anything in the
`.so`, fills each cell with `march_dispatch_name_to_id` against the running
table. A name the running binary has no slot for stays 0, a slot never
published, so the call takes the existing direct path into the `.so`'s own
definition. The base binary keeps constant ids.

## Cause 2: a changed slot the running build lacks reached no one

With the crash gone, the contract deploy activated `shop` and `host_tick` but
not `shop_phase`. A slot's impl_hash folds in its unslotted callees but stops at
a slot callee, so `may_choose_later` (a slot in the patch, changed between the
expand and the contract) changed no caller's hash. The server has no slot for it
(new since its last restart), so it could not be activated either. The contract
`shop` chose `later` while the expand's `shop_phase` reported phase 2.

Fix: the manifest gains a `# slots <a>,<b>` header (the patch's own slots,
`Hot_reload.is_slot_fn`; older parsers ignore it).
`Cmd_deploy_hot.unslotted_carriers` names the running-build slots that call
(through `callers:`, up through unregistered names) a patch slot the server
lacks and whose hash differs from the prior manifest (or no prior manifest is
given). `run` activates them with the changed slots ("NOTE: redeploying
shop_phase: it carries may_choose_later ..."). `Deploy_plan.undeliverable`
agrees: such a function is deliverable once a running slot calls it.

## The scenario's expectation

"v2 Buyer with a v1 Shop" (`pair:2/1`) is now "v2 Buyer with an expand Shop"
(`pair:2/2`). A session pins the epoch it forms in (plan 6.1); the old offer's
`OfferActor` moves to the expand's epoch at its marker, so a session formed on
that offer after the deploy runs the expand's `shop`, still on version 1's
fingerprint. `pair:2/1` held only while the entry module had no slots: the old
offer's handler direct-called version 1's `shop` whatever epoch its session
formed in.

## Regression checks

- `test/test_hot_reload.ml` "compile_so resolves slot ids by name": no constant
  id at a `.so` call site, the cell and its `__march_init` resolution are
  emitted, and the base binary keeps constant ids. Red with `hr_slot_id`
  returning the constant.
- `forge/test/test_deploy_plan.ml` "a changed slot the running base lacks: its
  callers carry it": `unslotted_carriers` and `undeliverable`.
- `scripts/two-node.sh protocol_expand_contract` passes, and so do
  `protocol_evolve`, `hcr_new_code_session`, `hcr_remote_msg_epoch` and
  `hosted_protocol_change`.
