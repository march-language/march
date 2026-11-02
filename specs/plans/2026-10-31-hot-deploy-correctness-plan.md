# Hot-deploy correctness implementation plan

> Execute the approved design task by task, with failing regression tests before fixes.

**Goal:** Deliver trustworthy first deployment, running-frame ABI safety, drain/callback handling, sandbox diagnostics, and rollback.
**Spec:** `2026-10-31-hot-deploy-correctness-design.md` (approved in chat).
**Architecture:** Embedded deterministic artifact metadata supplies an authoritative runtime schema baseline. Green-thread frame contexts retain routing versions; Forge uses server metadata before migration checks.
**Tech stack:** OCaml compiler/Forge, C runtime, LLVM, native and two-node tests.

## Global constraints

- Use existing worktree; no push or merge required.
- Require IO.FileWrite for sandbox reload writes, with diagnostics; do not relax filters.
- Preserve signature upgrades using frame pins, not blanket refusal.
- Rollback is a new signed release; state reversal requires a migration.
- Update canonical todos/progress and changelog with completed behavior.

## Review focus

Malformed/unsupported metadata responses must differ; failed batches must not change schemas; partial activation must preserve unrelated actors; panic/cancellation must unwind pins; rollback must not rewind release counters or erase newer state.

## Task 1: Schema metadata and first deployment

Files: bin/main.ml; runtime/march_reload.c; forge/lib/cmd_deploy_hot.ml; related tests.
Interface: exported const char arrays `__march_hcr_schemas` (sidecar JSON) and `__march_hcr_manifest` (sidecar text). SCHEMAS returns versioned JSON with schemas and actor release identifiers.
- [x] Add native base/patch embedding and server-query regression tests; demonstrate failure.
- [x] Share deterministic serialization across sidecars and embedded globals; include metadata in CAS identity.
- [x] Query and persist activated per-actor schema baselines; test failed batches and replay.
- [x] Forge uses server baseline, warns on stale local baseline, refuses missing legacy baseline.
- [x] Verify compile, Forge, runtime and first migration scenario.

## Task 2: Per-frame routing and lifetime

Files: runtime/march_dispatch.*, march_scheduler.*, march_runtime.c; lib/tir code generation; dedicated tests.
- [x] Reproduce retyped callee reached by running old caller.
- [x] Implement per-green-thread frame routing/pins, entry frames, and unwind cleanup.
- [x] Test nested/direct/tail/closure paths, scheduler migration, exception and cancellation, reclamation pressure.
- [x] Verify fresh eligible work observes new code while old work stays compatible.

## Task 3: Drain and shutdown callback

Files: runtime/march_runtime.c and dispatch activation contracts, actor tests.
- [x] Baseline epoch drain runner: 94 passed, zero failed.
- [x] Reproduce migrated actor invoking stale on_stop.
- [x] Resolve active-version callback; reject unavailable compatible callback at migration admission.
- [x] Verify callback, mailbox ordering and deadlines; reconcile stale todo.

## Task 4: Sandbox writes

Files: bin/main.ml; test/test_cap_sandbox_runtime.ml.
- [x] Assert diagnostic and actual CAS_PUT rejection without IO.FileWrite, success with it.
- [x] Add missing-grant warning while retaining read-only listener behavior and existing OS filter.
- [x] Run relevant native sandbox tests; record platform limitations accurately.

## Task 5: Rollback and integration

Files: test/two_node scenarios; Forge tests; docs/progress/todos.
- [x] Add v1 -> faulty compatible v2 -> v1-as-v3 through normal signed deploy.
- [x] Verify behavior, service continuity, monotone counters, authoritative schemas.
- [x] Test state-changing rollback with reverse migration and refusal without one.
- [x] Run affected suites/checks and determinism coverage; review final changes and fix findings.

## Execution record

2026-10-31: user approved implementation. Separate workers own frame runtime, schema server, and sandbox tests; root owns compiler serialization, Forge integration and rollback. Shared files are coordinated explicitly.

Validation recorded so far:
- Actual base/patch globals match sidecars; cold/warm builds in separate directories
  produce identical embedded metadata (`test/check_hcr_metadata.py`).
- Runtime schema activation/replay/policy: six modes pass, including a 500 KB reply
  and injected post-publication directory-sync failure (exit 74 before ACK).
- Forge schema protocol: 7 cases; capability gate: 56 cases; reconciler: 22 cases.
- First deploy with no `.prev` and signed state-changing rollback scenarios pass.
- Native macOS sandbox denial/granted-write cases pass. Linux sandbox execution
  remains unverified locally because the Docker daemon is unavailable.
- Review fixes cover NULL callback environments, NULL closure disown, raw versus
  tracked dispatch leave, baseline main replay reservation and durable rename ACKs.
- Closure regressions pass at opt0 and opt2: old captured/function-value ABI,
  recursive panic cleanup, optimized NULL environments, 200,000 tail iterations;
  C tests retain a sole closure epoch pin across 30 replacements.
- Multi-hop v1 → v2 → v3 → original-base restart passes, including both state
  migrations and active-version shutdown. Native migration runner: 102/0.
- Broad run exercised compiler (1,456), evaluator (289), codegen (723), stdlib
  (900), March stdlib (84), and JIT (43) cases. It exposed a macOS optional-metadata
  shared-library link failure, stale declaration goldens, an old main-pin expectation,
  and one cache miss during concurrent source changes. These were fixed; the cache
  rerun and full evaluator (289) pass. Final affected codegen groups (87), full
  JIT (43), and stdlib parity/message-migration/restart reruns (34) pass. All
  failures from the broad run are resolved; these are targeted reruns, not a claim
  that the entire broad command was rerun unchanged in one invocation.
- Complete native sandbox suite: 12 passed. Runtime-source/actor-RC checks and
  generated documentation lint pass.

Final integration reruns pass with the final runtime: `hcr_spawn_site_layout` and
`hcr_rollback`. All five requested workstreams are complete. The implementation is on `codex/hot-deploy-correctness`. The user requested a
pull request after verification; no deployment was requested or performed. HCR ABI v5 requires rebuilding/restarting the base once.
Long-lived old frames/closures can exhaust bounded version capacity; no automatic
rollback is provided. Linux sandbox validation remains a CI/platform follow-up.
