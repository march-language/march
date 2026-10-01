# Stdlib actors are not hot-reload slots

Done 2026-09-30. The owner's decision on point 3 of
[../todos/2026-09-25-hot-deploy-stalls-node-past-swim-timeout.md](../todos/2026-09-25-hot-deploy-stalls-node-past-swim-timeout.md)
(that todo stays open for its points 1 and 2; the full record of this change is
under its point 3).

- **Rule.** `Hot_reload.is_slot_actor_dispatch` (lib/tir/hot_reload.ml): every
  `*_dispatch` except a stdlib actor's. It replaces the suffix-only
  `Tir_names.is_actor_dispatch_fn` at every boundary site: `hr_names` and the
  patch `.so` visibility exemption in lib/tir/llvm_toplevel.ml, the mutual-TCO
  wrapper visibility in lib/tir/llvm_tco.ml, and `is_slot` in bin/main.ml's
  slot-hash fold (#663), which also stops folding a stdlib actor's glue into an
  app root. `Llvm_emit.clo_wrap_borrowed` keeps the suffix predicate: the
  message loop's calling convention is the same for every actor.
- **Provenance.** `Lower` records every fn `Lower_actor.lower_actor` returns
  with `Typecheck_builtins.span_is_stdlib` of the `DActor`'s span (the
  stdlib-only builtin gate's predicate: the file came from the stdlib loader or
  lies under the root it loaded from). Never a basename or a name. A bare name
  claimed by both a stdlib and a user actor keeps its slot.
- **No silent undeploy.** The manifest gains `# stdlib_hash <stdlib source
  digest>`. `Cmd_deploy_hot.stdlib_change` compares two manifests;
  `Deploy_plan.classify` adds it as a restart reason for the build's pools, and
  `Cmd_deploy_hot.run` refuses with it before connecting. Measured before the
  forge side: the same app compiled against a stdlib whose `Writer.Credit`
  handler changed differs in 2148 functions, none of them slotted, so deploy
  hot answered "No changes detected" and `--plan` (slots unknown) planned a hot
  patch of "2 function(s) changed" in the unit fixture.
- **A `--hot-reload` binary with no slot still runs its reload server.** The
  `march_reload_server_start` call was emitted with the slot table and skipped
  at zero slots. An app whose code all lives in the entry module (bare-named,
  off the boundary) used to have slots only because the stdlib's session
  actors did; with those gone it had none and never opened its reload socket
  (run_stdlib's "HCR ACTIVATE6 ... end to end" failed with "reload server
  never listened"). The setup is now emitted unconditionally under
  `--hot-reload`. That test's control activation had been swapping a stdlib
  session actor, the very thing this change rules out; its serving fixture now
  declares an app actor (`Tick`) for the control slot.
- **Measured.** `forge/test/fixtures/upgrade/v1` under `--hot-reload
  UpgradeApp`: 12 published slots before (nine stdlib actors), 3 after
  (`Tally_dispatch` and two `UpgradeApp.*` functions).

Tests: test/test_hcr_stdlib_actors.ml (run_compiler), test/test_hot_reload.ml
(`actor_provenance`), forge/test/test_deploy_plan.ml (two cases). Each was run
red against a perturbation (suffix-only predicate; no manifest header; a
`stdlib_change` that never fires).
