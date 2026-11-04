`[P2]` Lemmas for hot code reload, actors and choreography: build the plan

Design: `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` (plan only, filed
2026-11-04 on `b86c86a63`). Ordered for app developers first: a user states an invariant,
handler contract or protocol, and the compiler proves it or shows a counterexample, with
the compiler-owned laws proved once in the stdlib.

Phases (design §7):

- **A0.** Close the HCR variance hole: refinements in `.schemas.json`, old ⇒ new checks at
  deploy, unproved refused unless overridden with an audited flag, no silent skips. Landed in PR #1100 (progress
  `2026-11-04-hcr-refinement-variance-check`); reply covariance, H2 and the audit-log
  override remain.
- **A.** Never silent: `@invariant` outside the grammar is an error (todo
  `2026-11-04-invariant-unsupported-expression-silently-dropped`). Field refinements of an
  anonymous-record `migrate_state` parameter reach `old.f`. Actor message constructors are
  resolved by datatype (todo `2026-10-15-actor-message-ctor-cannot-be-qualified`). HCR
  counterexamples for the migration obligations.
- **A2.** Dry-run `migrate_state` on copies of the live states before `ACTIVATE`; derive
  mechanical migrations from the schema diff, each derivation rule proved once.
- **B.** `march --check --guarantees` / `forge hot-reload check`: one labelled line per actor
  and protocol (`proved`, `proved (model) · tested (runtime)`,
  `proved (spec) · validated (compiler)`, `assumed`).
- **C.** `stdlib/session_theory.march` with duality, projection, pairwise duality,
  composition and deadlock freedom for the synchronous, crash-free, informed-bystander
  fragment. Translation validation of both OCaml projectors (`typecheck_session.ml`,
  `desugar_endpoints.ml`) against it, by interpreter evaluation.
- **D.** `stdlib/actor_theory.march` (per-sender FIFO, `Actor.call` correlation, DOWN
  delivery: proved today on the model, design §2 P2), plus trace conformance against the
  runtime and RC-trace fixtures for each send path.
- **E.** Lemma ergonomics: todos `2026-11-04-lemma-hypothesis-reflected-call-not-assumed`,
  `2026-11-04-unreflectable-predicate-hides-name-clash`,
  `2026-11-03-return-contract-ignores-block-facts`.
- **F.** Baseline invariants as migration hypotheses, handlers reflected as `<Actor>.step`,
  the migration-simulation law, rollback round trip, chained `migrate_msg`, tag checks at
  deploy.

Move this file to `specs/progress/` when phase F lands, or split it per phase as phases land.
