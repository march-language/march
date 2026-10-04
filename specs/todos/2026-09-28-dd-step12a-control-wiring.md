# `[P3]` Distributed deploys, step 12a: wire the control plane's core into the cluster

**Design:** `specs/plans/2026-09-28-dd-step12-control-plane-design.md`,
sections 6–10. **Built so far:** [../progress/2026-09-28-dd-step12a-control-core.md](../progress/2026-09-28-dd-step12a-control-core.md)
(`stdlib/control.march`: release format, executor, leader memory, `agent_apply`, the
protocols' payloads; the `Ctl` and `CtlFetch` protocols and their role bodies in
`test/session/control_peers.march`; all tested in one process).

Everything below was held back while PR #671 (12-pre) was open, since it touches
`runtime/march_reload.c`, `stdlib/topology.march`, `forge/lib/cmd_deploy_hot.ml`
or `test/test_reload_activate4.c`, or needs a running cluster. #671 has since
merged, so it is unblocked.

**Landed:** see [../progress/2026-09-30-dd-step12a-control-wiring.md](../progress/2026-09-30-dd-step12a-control-wiring.md)
and, for `forge deploy` on the cluster backend, the `forge test --upgrade-from` fixture and the
leader's audit log, [../progress/2026-10-01-dd-step12a-forge-cluster-backend.md](../progress/2026-10-01-dd-step12a-forge-cluster-backend.md).

**What remains.**

- The plan on the cluster backend sees less than over ssh: STATUS carries no node's live
  sessions, hot slots or patch stack, so the drain counts, the "no dispatch slot" check and
  automatic compaction (`compact_after`) work from forge's records (`--compact` still forces
  one). A `NODE` line (or a `DETAIL <node>` verb) carrying them would close it.
- A build whose hosts span two targets is refused on the cluster backend: a release names one
  patch per build. Builds per target (`build web@linux/arm64 ...`, selected by the agent's
  `HCR_INFO` target) would lift it; it touches the release format.
- `CtlFetch` is not in the wiring: a session message costs far more than its bytes
  ([2026-10-01-session-message-encoding-leak.md](2026-10-01-session-message-encoding-leak.md)),
  so artifacts go over the control API as raw bytes (`CAS_GET`). A byte payload type for
  sessions would let a chunked fetch over a session come back.
- `forge cluster cert --control-agent/--control-candidate` conveniences (the roles are
  Ctl.Agent:initiate; candidates add Ctl.Control:offer).
- A provoked skipped-gate report (STATUS has `NOTE` lines for it; the partition scenario heals
  without the old leader racing ahead).
- The two compiled-only record-update misbehaviours the wiring works around:
  [2026-10-01-compiled-record-with-projection-sigsegv.md](2026-10-01-compiled-record-with-projection-sigsegv.md).
- The session-runtime leaks the wiring routes around:
  [2026-10-01-session-node-vault-tables-leak.md](2026-10-01-session-node-vault-tables-leak.md).

## Moving `Ctl` and `CtlFetch` into `stdlib/control.march` (unblocked 2026-10-03)

A protocol in a stdlib module now works, including for a program whose entry module is
named like a stdlib module (`mod Test`), and a stdlib protocol no longer makes a user's
bare `from_json` ambiguous:
[../progress/2026-10-03-endpoints-protocol-in-nested-module.md](../progress/2026-10-03-endpoints-protocol-in-nested-module.md).
The move was tried on a copy of the stdlib (not landed, since
`lib/desugar/control_wiring.march` was being edited in parallel): `control_peers` printed
its golden on both backends, and the `mod Test` native fixtures, `from_json_dispatch`,
`derive_json_dispatch_codegen` and `interpreter_only_dsl` passed. To do it:

1. Move `control_peers.march`'s protocol section (the `Wire*` records with their
   `derive Json`, the converters, `Ctl`, `CtlFetch`, and the role bodies `agent_role`
   ... `fetch_done`) into `Control`, dropping the `Control.` qualifiers. Rename the
   converters: `result_of` already exists in `Control` (the experiment used a `ctl_`
   prefix). Make the role bodies the wiring calls public (`fn`).
2. In `control_peers.march`, qualify what moved: `Control.Ctl_Agent`,
   `Control.CtlFetch_Server`, `Control.WireReport`, `Control.agent_role(...)`.
3. In `lib/desugar/control_wiring.march`, stop splicing the protocols into the entry
   module and call `Control.Ctl_Run.*` / `Control.agent_role` instead; drop the
   "typechecks only at an entry module's top level" comment.
4. Re-bless nothing: the goldens should not change.

**Cost.** Every program pays for an eagerly loaded protocol. Measured 2026-10-03 on
`examples/hello.march` (14 cores, load 6.5-7, median of 7), stock stdlib vs one with
both protocols, the `Wire*` records and the role bodies in `Control`: warm run 0.618 s
-> 0.692 s (+0.074 s, +12%), cold run (empty `~/.cache/march`) 1.399 s -> 1.598 s
(+0.20 s, +14%), warm `--check` 0.451 s -> 0.502 s (+0.051 s). The warm cost is still
#677's +0.07 s; cold is down from +0.8 s (the frontend fix of 2026-09-28). That is too
much to put on every program for code only topology apps use. Proposal: load
`control.march` lazily, on a reference to `Control` (or only when the driver builds a
topology app, `--topology`), with a FULL body typecheck rather than the
`Module_registry.ensure_loaded` export-shape path, whose generic-representation
miscompile is why the manifest is exhaustive
(`lib/modules/stdlib_manifest.ml`). An opt-in group in the manifest that the driver
adds when the entry program or its topology names `Control` would do it.

**Name clash.** After the move, `Ctl_Message`, `CtlFetch_Message` and the `Wire*`
records are short names in every program; a user protocol named `Ctl` would stop
compiling ([2026-10-03-derive-json-same-short-name-two-modules.md](2026-10-03-derive-json-same-short-name-two-modules.md)).
Fix that first, or give the moved names a `Control`-specific prefix.
