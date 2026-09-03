# `unreflectable-predicate`: fix the misattribution, then name the cause

Filed 2026-09-02. Status: landed 2026-09-03, commits `082d5bf5..17aaf225`
plus the docs/record commit. Record:
`specs/progress/2026-09-02-unreflectable-predicate-attribution.md`.

## Problem

`unreflectable-predicate` is the second-largest user-code skip bucket after
the 2026-09-01 split (11 of 66). The reason text says the predicate "uses
vocabulary the checker cannot translate to SMT". Tracing all 11:

| Shape | Count | Sites |
|---|---:|---|
| Arithmetic actual, `var + 1` or `var - 1` | 7 | `decimal.march:175`, `list.march:144`, `stats.march:81,130,137,209,323` |
| Opaque call actual, a `pfn` with a plain return type | 4 | `simd_lane_panic.march:25`, `stats.march:191,213,222` |
| Any genuine predicate-vocabulary failure | 0 | |

In every case the predicate is inside the supported fragment. The failure is
in SUBJECT reflection. `reflect_scalar` (`refine_resolve.ml:443-536`)
dispatches an `EApp (EVar op, args)` actual through the named-call branch
(`:518-535`) first; a builtin operator has no postcondition, so it falls to
`plain` (`:463-478`), whose `resolve_var` is hard-coded to `None`. So
`n - 1` never reflects, the predicate's own `resolve_var "_"` returns `None`,
and the predicate is blamed.

The `Unreflectable_subject` reason exists for exactly this situation but is
filed only for record actuals (`mode = Skip`, `refine_call.ml:1967-1979`).

## Non-goals

- No reflection of division, modulo, non-linear products, symbolic float
  arithmetic, or string literals in postconditions. Those are the genuine
  `smt_of` `None` cases (`refine_scope.ml:71-148`) and none occurs in the
  corpus. They get named, not fixed.
- No change to `division_safety.ml`, which never files this reason.

## Design, in three parts

### 1. Reflect arithmetic actuals (precision)

In `reflect_scalar`, before the named-call dispatch, recognise
`EApp (EVar {txt = "+" | "-"}, [a; b])` and `*` with one literal operand, and
reflect both operands recursively through `reflect_scalar` itself, building
`Smt.Add`, `Smt.Sub`, or `Smt.MulLit`. Variables inside resolve through the
same scope the outer call uses, so `i + 1` under a guard `i >= 0` carries the
guard. This is linear arithmetic; no new solver risk.

Expected effect: 7 of the 11 skips become `proved`, `violated`, or a
diagnosed skip about the variable. Each must be audited in the measurement.

### 2. File a failed scalar subject as `Unreflectable_subject` (attribution)

When the actual is not a record and its reflection returns `None`, note
`Skipped (Unreflectable_subject)` rather than reaching the predicate at all.
Give `Unreflectable_subject` a payload naming the actual in source syntax
(`pred_str` renders expressions), following the Task 1 rule: the name rides
in `reason_detail`, the slug stays `unreflectable-subject`. The detail reads:
`the argument `lane(1)` could not be translated, so no goal was built`.

Expected effect: the remaining 4 move to `unreflectable-subject`. The
`unreflectable-predicate` bucket is then empty on this corpus, which is the
honest number.

### 3. Name the failing sub-expression for a genuine predicate failure

Add `smt_of_r`, the same function returning
`(Smt.term, A.expr) result` where the error carries the innermost
sub-expression that returned `None`. Keep `smt_of` as
`Result.to_option (smt_of_r ...)` so the 18 existing call sites do not change.
Switch only the two goal sites, `refine_call.ml:1964` and
`refine_post.ml:406`, to `smt_of_r`, and give `Unreflectable_predicate` a
payload: `reason_detail` becomes
`the predicate's `is_prime(_)` has no SMT translation`. Slug unchanged.

Per-site reporting for these two reasons follows the Task 3 rule: a reason
whose detail names the specific expression is diagnosed, so it reports at
every site; the throttle stays only for reasons that say the same thing
everywhere.

## Testing

1. `take_n(i + 1)` under `if i >= 0` is `proved`; `take_n(i - 1)` under the
   same guard is undecided and diagnosed as `unconstrained-subject` or
   `partial-conjunct`, never `unreflectable-predicate`. Mutation: revert the
   operator arm and both cases redden.
2. `Simd.extract_i32x4(v, lane(1))` files `unreflectable-subject` with
   `lane(1)` in the message text (text assertion, not slug only).
3. Synthetic fixtures for genuine predicate failures, since the corpus has
   none: `is_prime(_)`, `_ / 2 > 0`, `_ *. x > 0.0` on floats, a string
   literal in a postcondition. Each asserts the named sub-expression in the
   message. Mutation: make `smt_of_r` return the whole predicate as the error
   and the sub-expression assertions redden.
4. The existing `is_prime(_)` fixture (`test_refinecheck.ml:4977-4999`) keeps
   asserting the slug.

## Measurement and oracle

Corpus sweep before and after with the per-bucket table. The claim to verify:
`unreflectable-predicate` 11 to 0 in the user-code slice, with each of the 11
accounted for individually. `scripts/refine-oracle.sh` with RED-proof; every
moved line is a re-attribution of one of the 11, a new proof from part 1, or a
text change from parts 2 and 3. Anything else is a bug.

## Cost

Part 1 adds one reflection per operand; parts 2 and 3 run only on the failure
path. Measure cold `--check` on a trivial file against the pre-change compiler.
