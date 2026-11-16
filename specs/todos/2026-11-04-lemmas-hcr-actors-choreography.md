`[P2]` Lemmas for hot code reload, actors and choreography: build the plan

Design: `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` (plan only, filed
2026-11-04 on `b86c86a63`). Ordered for app developers first: a user states an invariant,
handler contract or protocol, and the compiler proves it or shows a counterexample, with
the compiler-owned laws proved once in the stdlib.

Phases (design §7):

- **A0.** Close the HCR variance hole: refinements in `.schemas.json`, old ⇒ new checks at
  deploy, unproved refused unless overridden with an audited flag, no silent skips. Landed in PR #1100 (progress
  `2026-11-04-hcr-refinement-variance-check`); the audited override in progress
  `2026-11-04-hcr-accept-unproved-audited`. Reply covariance waits on typed replies (todo
  `2026-11-04-actor-call-reply-untyped`); H2 moves to phase A.
- **A.** Never silent: `@invariant` outside the grammar is an error (done: progress
  `2026-11-04-invariant-unsupported-expression-silently-dropped`). Field refinements of an
  anonymous-record `migrate_state` parameter reach `old.f` (done: progress
  `2026-11-04-anon-record-param-field-refinements`). Actor message constructors are
  resolved by datatype. HCR counterexamples for the migration obligations. G4 done (progress
  `2026-10-15-actor-message-ctor-cannot-be-qualified`,
  `2026-11-04-interp-actor-dispatch-by-name`): `<Actor>.<Msg>` resolves, a shared name is
  obliged per actor, and both backends drop a same-named foreign message, so the handler
  body assumes its refinements. HCR counterexamples for H1/H2, run on every
  build against the deployed baseline: done (progress
  `2026-11-05-hcr-migration-counterexamples`); its residuals (named-record parameters,
  binder hypotheses for `migrate_msg`, multi-field invariants) carry into phase F.
- **A2.** Dry-run `migrate_state` on copies of the live states before `ACTIVATE`: done
  (progress `2026-11-05-hcr-live-data-migration-check`, M10, with the converted-message
  contract check). Derived migrations for a state that only gained fields, each rule proved
  once (M11): done (progress `2026-11-06-hcr-derived-state-migrations`); moving data between
  fields in one deploy is designed (todo `2026-11-06-hcr-derive-field-rename`).
- **B.** `march --check --guarantees` / `forge hot-reload check`: one labelled line per actor
  and protocol (`proved`, `proved (model) · tested (runtime)`,
  `proved (spec) · validated (compiler)`, `assumed`). Done with today's labels (`proved`, `violated`, `not proved`,
  `not checked`, `checked (compiler)`, `assumed`; progress `2026-11-06-hcr-guarantees-report`);
  the model labels arrive with C and D. It found that `@invariant` is never checked on `init`
  or handler results (todo `2026-11-06-invariant-unchecked-on-init-and-handlers`).
- **C.** `stdlib/session_theory.march` with duality, projection, pairwise duality,
  composition and deadlock freedom for the synchronous, crash-free, informed-bystander
  fragment. Translation validation of both OCaml projectors (`typecheck_session.ml`,
  `desugar_endpoints.ml`) against it, by interpreter evaluation. C0 (mutual-SCC lemmas over an n-ary
  branch list: they prove), M5 with C1 and C2, and M6 for both projectors: done (progress
  `2026-11-06-session-theory-and-projection-validation`). M6 found the `@[endpoints]` merge
  bug in todo `2026-11-06-endpoints-merge-compares-synthesised-ctors`. C3, C4 and C5 for the
  fragment (loop-free, crash-free, directed choices with merged bystanders; synchronous):
  done (progress `2026-11-06-session-theory-c3-c5`). Open: loops, crash branches, told-later
  bystanders, and replacing `project_protocol`'s existence check (todo
  `2026-11-06-session-theory-loops-crash`).
- **D.** `stdlib/actor_theory.march` (per-sender FIFO, `Actor.call` correlation, DOWN
  delivery: proved today on the model, design §2 P2), plus trace conformance against the
  runtime and RC-trace fixtures for each send path. Part one done (progress `2026-11-06-actor-theory`):
  `Actor.Theory` with A1-A3 proved, A1 conformance fixture, report labels. Open: the A3
  runtime fixture, A4 RC fixtures, trace-driven conformance (todo
  `2026-11-06-actor-theory-runtime-tests`).
- **E.** Lemma ergonomics: landed 2026-11-04 (progress
  `2026-11-04-lemma-hypothesis-reflected-call-not-assumed`,
  `2026-11-04-unreflectable-predicate-hides-name-clash`,
  `2026-11-04-return-contract-block-facts`); user type names the stdlib also declares
  remain (todo `2026-11-03-reflect-type-name-clash-with-stdlib`).
- **F.** Baseline invariants as migration hypotheses, the migration-simulation law, rollback
  round trip, chained `migrate_msg`, tag checks at deploy. Handlers reflected as
  `<Actor>.step` with an inductive `@invariant` moved to its own todo
  (`2026-11-06-actor-inductive-invariants`), which F builds on. Started 2026-11-08: the
  `@invariant` is obliged at `init` and at every handler's result on every build (progress
  `2026-11-08-invariant-unchecked-on-init-and-handlers`), so a deployed baseline's
  invariant is now a checked fact, not only an assumption. The rest landed 2026-11-08 on
  `feat/hcr-phase-f`: M2 (an invariant calling the program's functions, progress
  `2026-11-08-invariant-unchecked-on-init-and-handlers`), H5 (`2026-11-08-hcr-rollback-roundtrip`),
  M3 with H3 behind `@compat(simulation)` (`2026-11-08-hcr-simulation-law`), M7 with H6
  (`2026-11-08-hcr-chained-migrate-msg`) and C6's tag check (`2026-11-08-hcr-tag-consistency-check`).
  Residuals are in each progress file; the user-facing `<Actor>.step` for hand-written
  lemmas and `proved (inductive)` stay in `2026-11-06-actor-inductive-invariants`.

Move this file to `specs/progress/` when phase F lands, or split it per phase as phases land.
