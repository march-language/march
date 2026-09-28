# Distributed deploys: step 9's expand/contract split in `forge deploy` (D21)

**LANDED 2026-09-28.** Closes item 3 of
[2026-09-22-dd-step09-protocol-evolution.md](2026-09-22-dd-step09-protocol-evolution.md)
(moved here: the step is done) and the "Step 9's split in the deploy" item of
[../todos/2026-09-25-dd-step10b-followups.md](../todos/2026-09-25-dd-step10b-followups.md).
Parent: [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md),
4.2, 6.4, 6.8, D21.

## What changed

**The planner (`forge/lib/deploy_plan.ml`).** forge's own view of a protocol (its step
structure read from the parse, `wire_names`, `one_branch_added`, and the D21 split that
held the chooser role's functions back to a second deploy) is gone. A protocol is now the
compiler's *version* (build step 9's wire view and fingerprint), and `classify_proto` is
`Desugar_endpoints.compare_versions`: `Same | Added | Removed | Choice_added | Breaking
why`. Renumbered unlabelled messages are the compiler's `Incompatible` ("Msg_A_C_1 is now
Msg_A_C_2 ... Label them"), so they are breaking, not a compatible change with a
footnote. `splits_of` builds `Protocol_split.build`s from the plan's builds (each the
union of its pools' served and initiated roles), calls `Protocol_split.plan`, and returns
one `split` per protocol a build both chooses and receives, with its phase: `Expand`,
unless `pending_split.json` records that the expand for this very version (same label,
same new fingerprint) already went out, then `Contract`. `expand_flags` and
`pending_after` are what the executor needs from it. Block 3 of the render shows the two
deploys, which one this is, the flag, the receivers, the chooser, both fingerprints, and
why; a breaking change says every node offers both fingerprints while it rolls through; a
stale pending entry is named. Block 2 and the drains say which offers close in each half
(the receivers' in the expand, the chooser's in the contract).

**`Protocol_split`.** `plan` no longer returns `Breaking` when one protocol is breaking and
another compatible: the split is still decided for the compatible one, and the breaking
ones ride along in `d_breaking`. `deploy` also carries `d_protocols`. New readers:
`baselines_of_dir`, `versions_of_dir`, `changes_of_dirs ~deployed ~now`; a file that does
not read as a baseline (an older forge's structure file) is skipped.

**The executor (`forge/lib/cmd_deploy.ml`).** Before building, `protocol_versions` runs
`march --check --topology ... --protocol-baseline <each deploy baseline> --emit-protocols
<work>/protocols` (`check_protocols`); its output is this version. The split is decided
from that and the deploy baselines BEFORE any build, and `protocol_build_flags` (the deploy
baselines plus each expand's `--protocol-expand P:label`) goes into every patch
(`build_patch`) and every base image (`build_base`, through the new `?protocol_flags` of
`Cmd_build.build`, which replaces the build's own `.forge/protocols/` flags; the base-image
cache is keyed by it). After a deploy that completes, `advance_baselines` makes the emitted
files the deploy baselines, except a protocol this deploy expanded, which keeps the old one
until its contract, and removes the baseline of a protocol the program no longer declares.
`pending_split.json` is now `{format: 2, pending: [{protocol, label, fingerprint,
builds}]}`; a step-10b file reads as nothing pending, with a note. Deploy baselines live
only in `.forge/deploy/<env>/protocols/`, in the compiler's baseline format; a deploy
neither reads nor writes `.forge/protocols/`.

A side effect worth naming: the patches were built with no `--protocol-baseline` at all
before this, so a patch's `<P>_Msg.compat()` table was empty and mixed-version sessions were
refused during any rollout forge did; the base image used the compiler's build-to-build
baselines. Both now use what the environment runs.

**The compiler (`bin/main.ml`).** `--check`'s early source-level cache key now includes the
protocol baselines' digest and the `--protocol-expand` labels, as `build_cas_key` does for
`--compile`. Before, a clean `--check` with a baseline and an expand satisfied the same
check with no baseline, which the compiler refuses: it exited 0 silently (found by the new
test_topology_run case; reproduced by hand, then fixed, the warm check now exits 1).

## Tests

- `forge/test/test_deploy_plan.ml`: fixtures are now compiler versions from March source
  (parse, `annotate`, `wire_of`, `fingerprint_of`, as `--emit-protocols` records them).
  Monolith split: the expand (flags, phase, the chooser's old fingerprint, the render,
  the chooser's offer kept), the contract on the next plan (no flags, nothing pending, the
  chooser's offer closes), the pending JSON round trip, and a stale pending entry (expand
  again, noted). Across builds: one deploy, receivers' build first, no split. Breaking:
  drain, both fingerprints offered. Renumbering: breaking, the moved tag named, a label
  suggested, reported under "What may be lost". No deploy baseline (an older forge's
  environment): the fingerprint function's hash still tells a change from none. Red when
  the contract phase is disabled (the split test fails on "this is the contract").
- `forge/test/test_forge.ml` +2: a breaking change alongside a compatible one keeps the
  split and names the breaking one; `changes_of_dirs` reads the deploy baselines, skips an
  older forge's file, and ignores `.forge/protocols/`.
- `forge/test/test_topology_run.ml` +1 (`forge deploy`, Quick, the real compiler):
  `check_protocols` emits version 1; `advance_baselines` records it (and
  `.forge/protocols/` is never created); version 2's check and `splits_of` give
  `--protocol-expand Order:later`; `protocol_flags_of_dir` typechecks under the compiler
  and the expand alone is refused ("needs the protocol's previous version"); the expand
  keeps the baseline, the contract's flags are plain and typecheck, the contract advances
  it; a dropped protocol loses it. Red when the flags leave out the deploy baselines.
- `test/two_node/protocol_expand_contract` (new, CI runs every scenario there): ONE
  program (`node_b.march` links to `node_a.march`; the script checks they are the same),
  holding Shop (chooser) and Buyer (receiver) of `Order`; version 2 adds `later`, built
  as forge builds it: against version 1's baseline, once with `--protocol-expand
  Order:later`, once plain. Expand to node-a (the chooser's node) FIRST, then node-b;
  contract to node-a, then node-b; sessions every 150 ms throughout. No session lost or
  refused, every one Finished or Drained, v1/v1, v2 Buyer/v1 Shop and v2 Buyer/contract
  Shop seen, `later` only from a contract Shop, never a v1 Buyer with a contract Shop,
  reload counters clean. Red control: the contract build deployed where the expand goes
  (one plain deploy, chooser first): formation refused 27 sessions ("protocol differs")
  and the v2-Buyer/v1-Shop pairing never happened.

## Deviations and findings

1. **The expand's Shop keeps serving on the code its offer was opened with.** The expand
   leaves Shop's fingerprint where it was, so nothing re-offers it (`Topology.reoffer`
   sees the same fingerprint too), and the open offer's sessions run the version that
   opened it (6.1). That is safe, and it is what the scenario asserts; the expand's own
   Shop code only runs for an offer opened after the expand (a restart, a new pool node).
2. **Chooser code must ask whether it may choose.** In the expand, `choose_<label>`
   panics; the scenario guards it with
   `role_fingerprint(role_Shop()) == fingerprint()`. Filed:
   [../todos/2026-09-28-dd-expand-may-choose-predicate.md](../todos/2026-09-28-dd-expand-may-choose-predicate.md).
3. **`Cmd_build.build` gained `?protocol_flags`** (outside the files this work owned, one
   optional argument; every other caller is unchanged).
4. **The end-to-end test drives the compiler and `hcr_deploy`, not `forge deploy` itself:**
   `forge deploy` needs the ssh backend, whose end-to-end test
   (`forge/test/test_deploy_e2e.ml`) needs Docker, zig and the cross sysroot. The executor's
   steps are covered by the test_topology_run case against the real compiler; the
   scenario builds exactly what `protocol_build_flags` produces.
