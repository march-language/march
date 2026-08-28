# `refine_check.ml` decomposed (R1–R5)

**Date:** 2026-08-28
**Plan:** `specs/plans/2026-08-28-refine-check-decomposition.md`
**Closes:** the one target `specs/2026-08-25-file-decomposition-analysis.md` named and never
executed. It was the largest file in the compiler and had *grown* 7,416 → 7,583 during the
project while every other target shrank.

| File | Sections | Lines |
|---|---|---:|
| `refine_check.ml` | §19–§23 (orchestrator) | 7,583 → **1,881** |
| `refine_encode.ml` | §1–§6 SMT encoding, sort discipline | 1,412 |
| `refine_scope.ml` | §7–§11 reflection, rendering, fact channels | 1,050 |
| `refine_resolve.ml` | §12–§13 name resolution, argument reflection | 550 |
| `refine_call.ml` | §14–§15 verdict state, `check_call` | 1,901 |
| `refine_post.ml` | §16–§18 postconditions, induction, gating | 941 |

R6–R7 (§19–§23: the visitor, warnings, the declaration walk, `check_module`) were left in
place, as the plan recommended: R5 already removes 75%, and those sections hold every
*mutation site* for the shared cells.

## Structure

The file is a strictly linear pipeline — all seven candidate bands measured **zero forward
dependencies**. Each module `include`s the one below it, and `refine_check.ml` holds a
single `include Refine_post` that brings the whole chain back in its original order.
Top-down was forced, not chosen: `check_call` has 39 backward dependencies, so extracting
it first would have needed names still living in `refine_check.ml` while `refine_check.ml`
included it — a dune cycle.

Bands were cut on the file's **own 23-section table of contents**, not by eye. A first
draft of the plan drew them by hand and split `§12` in half.

## The 20 mutable cells

`include` re-exports the *same ref cell*; re-declaring one would silently create a second,
leaving a late-section writer setting a ref nobody reads. This is not theoretical — the
cells are defined early and mutated late (`ret_ctr` defined §13, reset §22;
`registered_measures` defined §5, cleared §22; `strict_verified` defined §14, set §21).
Asserted after every task, on comment-stripped code: **all 20 defined exactly once
tree-wide**. 16 now live in `refine_encode`, 3 in `refine_call`, 1 in `refine_resolve`.

The `strict_verified` / `trusted_fn` case is the one that would have been hardest to
catch: those flags only *relax or tighten reporting*, so a corpus of accepting programs
cannot distinguish a writer that sets a dead ref.

## Oracle findings — the part worth keeping

**`ir-oracle` proves nothing here.** A checker that stopped checking emits byte-identical
IR. It was not run and must not be cited for this file.

**`scripts/refine-oracle.sh` is necessary but NOT sufficient.** Its 298 fixtures all
*accept*, so it cannot see a check that silently stopped firing. Measured twice, not
assumed:

| Probe | refine-oracle | `@types-check` (reject corpus) |
|---|---|---|
| `term_fits_sort` → `false` (R3) | **IDENTICAL** | **FAILS** |
| `check_post` → `true` (R5) | **IDENTICAL** | **FAILS** |

So the reject corpus — `specs/lang/types/reject`, 157 fixtures, run only by
`dune build @types-check --force` — is the channel that catches a dropped check. It is
CI-only, and **vacuous without `--force`** (exit 0, zero-byte log). Assert on the log.

**Perturb decisions, not names.** Four probes were inert and are worth not repeating:
`measure_gate_errors` → `[]` (only 1 of 157 reject fixtures uses `@measure`),
`adt_sort_name` prefix rename (renames the sort *consistently*, so the SMT problem is
isomorphic), `contract_is_enforced` → `false`, and — from the finding-3 work — three
`derive_impl` renames. What goes RED is changing a verdict: `formula_wellsorted` → `false`
(R1), `refined_param_ty` → `None` (R2), `term_fits_sort` → `false` (R3), `check_call`
no-op (R4), `check_post` → `true` (R5).

**Two apparatus traps.** `@types-check`'s log carries menhir shift/reduce warnings whenever
the parser is rebuilt in that invocation — filter them or a clean run reads as a 3-line
regression. And a probe whose build FAILS makes every oracle result meaningless (the
binary is stale); check the build's exit code before reading any oracle.

## Verification

Every task was verified against the **pre-R1** baselines, so the final state proves
R1+R2+R3+R4+R5 together are a no-op, not merely each against its predecessor:

- splice check vs the original file: **EMPTY ordered diff, 3,940 code lines**, at every task
- `refine-oracle` IDENTICAL (5,476 lines / 298 fixtures)
- `types-oracle` Tier 1 (601 fixtures) + Tier 2 (7,252 diagnostic lines) IDENTICAL
- `@types-check --force`: 303 verdicts byte-identical
- `scripts/run-tests.sh`: 3,177 tests, all suites passed, exit 0

`scripts/strip-comments.py` was landed in R1: the splice checks and the single-definition
assertions both need a nesting- and string-literal-aware stripper, and a plain `grep`
matches the module headers' own prose about the very names being counted.

One suite run (R4) reported `march_iolist_deep_flatten` failing with **SIGKILL / EXIT:137
and correct output** (`25000/25000`) at load 8.14. It passes in isolation, the codegen
suite passes alone (593 tests), and the R5 run over the same code is clean. Environmental,
same signature as the one seen on #375.
