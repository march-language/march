`[P4]` Unsat-core hint replay on VC cache misses, and a pre-verified stdlib lemma library.

Source: `specs/2026-11-08-auto-active-verifier-lessons.md` (research survey, 2026-11-08), recommendation 15.

## Why

F* stores hint files, the facts each query used, and replays them when the query changes
slightly, so re-verification is fast and less sensitive to irrelevant edits. Dafny ships its
standard libraries pre-verified, so users pay nothing to use them. The evidence is weaker than
for the other items (no controlled study).

## Now

The VC cache stores verdicts keyed on exact query text, and reflection stage 2 stores its core
(`uses:`). A changed VC starts from scratch.

## Wanted

On a cache miss, find the previous VC for the same obligation id and first try the query
restricted to its core. Fall back to the full query and report the fallback. Ship stdlib lemma
verdicts with the compiler.

## Done when

Measured on edit replay over the stdlib (a one-line change per module): warm re-check time and
the stability report, with and without replay.
