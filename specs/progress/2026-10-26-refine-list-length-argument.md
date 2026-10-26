# `List.length(e)` as an argument or a `let` reflects as `len(e)` (L4)

Landed 2026-10-26 on `claude/refine-length-facts`. No todo tracked this half; the source is
row 5 of the 2026-10-24 stdlib refinement audit ("the `len` alias applies only in guards, not
to a call used as an argument"; its accumulator half stays
`specs/todos/2026-10-18-refine-scalar-accumulator-recursion.md`, untouched), plus the audit's
surprise that `let n = List.length(xs)` then `if i >= 0 && i < n` did not give `i < len(xs)`.

```march
need_nn(List.length(xs))                       -- was unreflectable-subject; now proved
let n = List.length(xs)
if i >= 0 && i < n do List.nth(xs, i) else 0 end   -- was partial-conjunct; now proved
```

## Root cause

A guard reflects through `smt_of`, which normalises `List.length` to the `len` measure
(`measure_alias`, the documented alias) and resolves it onto `len$xs`. A call ARGUMENT
reflects through `Refine_resolve.reflect_scalar`, whose call arm looks only for a callee
postcondition; `List.length` has none (its body is an accumulator loop), so the actual was
`unreflectable-subject`. A `let n = List.length(xs)` filed no scope entry for the same reason,
and `let_equality_rhs` admits no call, so `n` was unconnected to `len$xs`.

## Fix

- `Refine_resolve.reflect_scalar`: a new optional resolver `?foreign_len`, threaded through
  the arithmetic arms, and an arm for `List.length(a)` at Int sort, under the alias's own gate
  (`measure_alias "List.length" = Some "len"`, i.e. the stdlib's `List.length` and not
  withdrawn), that returns the caller's length term for `a`.
- `Refine_call.check_call`: `cons_len_term` (from L2) moved earlier and reached through the
  existing `load_scope_measure_facts_ref` forward cell; `foreign_len` wraps it and is passed
  at the two argument reflections in `resolve_var` (the refined value and a sibling
  parameter's actual). The argument `a` is a CALLER expression, so it is reflected in the
  caller's namespace (`len$xs` for a caller `xs`, whatever the callee calls its parameters).
- `Refine_scope.scope_add_binding`: `let n = List.length(x)` (a bare name `x`, same gate)
  files the Int entry `n : {_ == len(x)}`. Scalar consumers read it through their measure
  resolver onto `len$x`. It mentions `x`, so `scope_shadow` retires it when `x` is rebound;
  `self_mentioning` guards it as every relational entry is guarded.

## Tests (`gap-list-length-arg`, 9 cases)

RED on the base (received):

- `need_nn(List.length(xs))`: `unreflectable-subject`, expected proved.
- `need_pos(List.length(xs))` under `xs : {List(Int) | len(_) > 0}`: `unreflectable-subject`,
  expected proved (without the fact: a skip, before and after).
- `need_pos(List.length([1, 2]))`, a let-bound literal, `Cons(x, t)`, and `List.length([])`
  (expected a violation): not as expected on the base.
- `need_pos(List.length(xs) + 1)`: `unreflectable-subject`, expected proved
  (`need_nn(List.length(xs) - 1)` not proved, before and after).
- `let n = List.length(xs)` then `List.nth(xs, i)` under `i >= 0 && i < n`:
  `partial-conjunct`, expected proved (also `need_lt(i, List.length(xs))` under `i < n` and
  `need_nn(n)`).
- name capture `need_le(xs, n : {_ <= len(xs)})` called as `need_le(xs, List.length(xs))`:
  `unreflectable-subject`, expected proved; `need_le(ys, List.length(xs))` not proved.

Controls that held before and after: rebinding `xs` or `n` between the `let` and the use
leaves `List.nth` not proved; a program defining its own `List.length` (one returning `0 - 1`)
gets no `len` meaning at the argument. Perturbation: with the `measure_alias` gate removed
from the new `reflect_scalar` arm, that withdrawal control goes RED (`need_nn` proved from the
lying definition), so the gate is what the control pins.

GREEN: all 9.

## Oracle

`scripts/refine-oracle.sh check` against the pre-L1 baseline. On top of L2's diff (the stdlib
`nth` line proved in all 552 fixtures), every fixture shows +2 proved / -2 skipped and two
skips changing reason, all in the prepended stdlib, attributed by `--refine-report-sites` on
`stdlib/stats.march` with the L3 and L4 compilers:

- `stdlib/work_dispatch.march:42-43`, `List.head(fresh)` / `List.last(fresh)` after
  `let n = List.length(fresh)` and the `n < 2` guard's else arm: `unconstrained-subject` →
  proved (`len(fresh) == n >= 2`). Correct.
- `stdlib/stats.march:136` (`List.nth(sorted, i + 1)` under `not (i >= n - 1)`) and `:440`
  (`List.nth(sorted, n - 1)`), both after `let n = List.length(sorted)`:
  `solver-undecided` → `partial-conjunct`. The upper bound is now established; the lower one
  (`i + 1 >= 0`, `n - 1 >= 0`) is not, and is not provable from these facts. Still skips, with
  a more precise reason. No new skip, no new violation.

## Rulings

- Ruling: the `let` entry is for a bare-name argument only (`let n = List.length(xs)`), not
  for `List.length(f(x))` — a scalar entry's predicate is translated with a measure resolver
  over NAMES, so a call inside it would not translate — cost if wrong: a lost proof.
- Ruling: only `List.length`, not `String.byte_size` (the other `len` alias) — the gap named
  `List.length`, and a String argument takes the `Str` sort path, which this arm must not
  enter — cost if wrong: the String spelling stays unreflectable as an argument (a lost proof).
- Ruling: the alias gate is reused unchanged — whatever withdraws the alias for guards also
  withdraws it here, so the two positions cannot disagree — cost if wrong: none beyond the
  guard alias's own.
