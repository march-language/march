# Stdlib wrapper contracts: `seq`, `flow`, `gen` declared; `aho_corasick` left alone

Filed 2026-09-16 as `specs/todos/2026-09-16-refine-stdlib-wrapper-contracts.md`;
**closed 2026-09-30.** The census that sized it is
`specs/progress/2026-09-16-refine-skip-census.md`. The `Stats` row landed
2026-09-22 (`specs/progress/2026-09-22-stats-wrapper-contracts.md`).

## Decision

Repo owner, 2026-09-30: yes on all three remaining sites. `aho_corasick`
(11 sites) stays unchanged: its contract is relational
(`_ < pvec_length(nodes)`) and would push obligations onto helper callers that
they cannot discharge; those skips stay, visibly.

## What changed

Breaking change to three public signatures, with `--refine-suggest` as the
migration path (same shape as the `Stats` change):

| Function | Now declares |
|---|---|
| `Seq.batched(seq, n)` | `n : {Int \| _ > 0}` (forwards to `Seq.batch`, already contracted) |
| `Flow.batch(stage, n)` | `n : {Int \| _ > 0}` (forwards to `Seq.batch`) |
| `Gen.frequency(pairs)` | `pairs : {List((Int, Generator(a))) \| len(_) > 0}` (forwards to `Random.choice_weighted`) |

`Gen.frequency` maps `pairs` through `List.map` before calling
`Random.choice_weighted`, and the checker does not know `List.map` preserves
length, so the declared contract alone left the `choice_weighted` call
skipped (`unconstrained-subject`). The function now matches on the mapped list
(`Nil -> panic(...)`, an arm unreachable given the declared contract) so the
non-empty fact is restated on the value actually passed, rather than weakening
the signature.

## Evidence

Neutral entry, `--check --refine-report`: user + stdlib skips 46 -> **43**
(the three wrapper sites are gone; `gen.march`'s two `List.nth` skips remain).
Callers in `stdlib/`, `test/`, `bench/`, `docs/` pass literals or are
unaffected (`test_seq.march` uses `Seq.batched(xs, 2)`).

Tests: new `wrapper-contracts` group in `test/test_refinecheck.ml` (real
compiler, real stdlib): literal-positive / non-empty arguments are accepted
(rc 0); a literal `0` / `[]` is refuted at each of the three wrappers (rc 1,
"does not satisfy precondition"); an unproven argument under `cap verified`
errors with "cannot verify precondition ...".
