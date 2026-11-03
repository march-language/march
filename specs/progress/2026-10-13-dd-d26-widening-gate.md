# Distributed deploys, step 7: the widening gate for derived pool caps (D26)

Done 2026-10-13. The D26 bullet of
[../todos/2026-09-22-dd-step07-topology-file.md](../todos/2026-09-22-dd-step07-topology-file.md)
(parent: [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md),
section 4, D22, D26). That todo stays open for its other deferred items.

## Before

The compiler derives each pool's `caps` (step 3), and `forge deploy --plan` /
`forge deploy` already compared them with `.forge/deploy/<env>/derived.json`
(`Deploy_plan.classify`'s `derived caps (D26)` widening, since step 10b). But
`forge deploy hot` never looked at pool capabilities, never wrote that file,
and `forge build` said nothing.

## What changed

- **`forge/lib/pool_caps.ml`** (new). Owns `derived.json`'s format
  (`derived_of_json`/`derived_json`, moved from `cmd_deploy.ml`, which now
  aliases them) and its path (`baseline_file ~root env` =
  `Reconcile.deploy_dir`/`derived.json`, `default` without `--env`).
  `widenings ~prior ~current ~grant_caps` normalizes both sides
  (`Cap_lattice.normalize`) and reuses `Cmd_deploy_hot.compute_cap_widening`
  and `filter_granted_widening`: a grant is a plain capability name matched by
  subsumption and applies to every pool that widens to it (the plan's own
  example, `--grant-cap IO.FileWrite`, names no pool). A pool missing from the
  baseline widens by all its caps, as `Deploy_plan.classify` counts it.
- **`forge deploy hot`.** `Cmd_deploy_hot.deploy`/`deploy_env` take
  `?pool_gate`, run right after `Topology.gate` (which writes the digest the
  derivation reads) and before the build. The CLI passes
  `Pool_caps.deploy_gate`; it is a parameter because `Pool_caps` depends on
  `Topology_run` → `Reconcile` → `Cmd_deploy_hot`. The gate:
  - no `topology.toml`: no-op;
  - no baseline: permissive with a `NOTE:` (as the function gate on a first
    deploy);
  - baseline but the derivation fails: refuses (never passes blind);
  - otherwise prints `  granted widening: pool P gains C (via --grant-cap G)`
    and, for anything ungranted, the refusal in `print_widening_diagnostic`'s
    shape (`error: hot deploy would widen pool P's derived capabilities (D26)`,
    `last deployed caps:`, `new version adds:`, the `forge deploy hot [--env E]
    --grant-cap C` to re-run with), returning
    `pool capability widening — deploy aborted`.
  The returned thunk records the new derived caps, called next to
  `save_manifest_baseline` only when every server succeeded.
  The baseline key is the `--env` name as given (not collapsed to `default`
  when there is no overlay), so two fleets never share a record.
- **`forge build`** prints `Pool_caps.build_warnings` after a successful build:
  one `warning: pool P's derived caps widen since the last deploy to <env>:
  adds C; deploying it needs --grant-cap C` per pool and recorded environment.
  The derivation (`march --topology … --emit-core-ast`) only runs when some
  `derived.json` exists.

## Tests

`forge/test/test_deploy_plan.ml`, group `authority`, five new cases, all in
process with an injected derivation: a widened pool without a grant is
refused with the diagnostic (and the baseline untouched; `--env` in the
suggestion); `--grant-cap` exact and broader (`IO`) authorizes and records
only when the thunk runs, an unrelated grant does not; first deploy,
unchanged and narrowed pass and record, a baseline with no derivation fails
closed; the `forge build` warning text, per environment, silent on a
narrowing; `deploy`/`deploy_env` stop at a refusing `pool_gate` before
building. RED check: with the refusal, the build warnings and the
`pool_gate` call each disabled, four of the five fail.

Also run by hand against the real compiler on a copy of
`forge/test/fixtures/reconcile_app` with a hook taking `Cap(IO.Console)` and
an empty recorded baseline: `forge build` warned, `forge deploy hot` refused,
`forge deploy hot --grant-cap IO.Console` passed the gate (then stopped at
the missing `[hot-reload]` section).

## Docs

`docs/topology.md` (new section "Derived capabilities and the widening
gate"), `docs/hot-code-reload.md` ("Topology pools' derived capabilities"),
`specs/lang/capability-enforcement.md` (+ regenerated
`docs/capability-enforcement.md`), `specs/features/topology.md`.
