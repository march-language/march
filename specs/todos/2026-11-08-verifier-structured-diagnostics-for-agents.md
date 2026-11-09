`[P3]` Versioned, structured verification diagnostics for tools and AI agents.

Source: `specs/2026-11-08-auto-active-verifier-lessons.md` (research survey, 2026-11-08), recommendation 11.

## Why

AutoVerus reported 91.3% on its own benchmark. An independent reproduction got 75.3% on the
original Verus build and 52.7% on a July 2025 build, a drop attributed to prompts tied to old
error text. Verifier output is effectively an API for agent pipelines, and LLM proof repair
(DafnyBench, Laurel, AlphaVerus) is where much of the 2024–2026 progress is.

## Now

`--check-json` emits NDJSON diagnostics with codes and spans.

## Wanted

- A schema version on refinement diagnostics, plus a stable obligation id (function, site,
  conjunct), the obligation kind, the verdict, the failure kind
  (`2026-11-08-verifier-failure-triage`), the counterexample with its execution label
  (`2026-11-08-verifier-encoding-validation`), and the facts in scope.
- A documented compatibility policy, so message wording can change without breaking tools.

## Done when

The schema is documented, pinned by golden JSON tests, and versioned.
