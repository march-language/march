# Inference-lite, phase 2: element slots (K3, K4, tuple components)

Landed 2026-10-21. Design §1.2 (K3/K4), §2 (`elem_ret_holds`). Plan Task 7. Not yet reachable from
the CLI (plan Task 11).

## What landed

- `Infer_slot.install`: writes a candidate at any slot (a parameter, the return, an element of a
  one-argument container, a tuple component) in every clause. Element slots are enumerated only for
  one-argument containers.
- `Infer_oracle`: K3 (element parameter) uses the precondition rules; K4 (element return, incl.
  `Elem (Tuple (i, Return))`) is TRUE when `Refine_check.gate_elem_returns` (now exported) admits
  the hypothesis, read from `Refine_param.elem_ret_proved`, and USEFUL when a caller site closes.
- Two probe-state fixes every kind now benefits from: the hypothesis is swapped into
  `Refine_param.fn_defs_tbl` for the probe (callers read a callee's element return from the
  DEFINITION table, registered once by `check_module`), and `elem_ret_proved` is saved/restored.
- `Ledger_diff` matches a site by (span, predicate, kind) — the callee label changes once a value
  carries an element entry — and, failing that, pairs an after-site with an enclosing/enclosed
  before-site of the same predicate (the demand moves from the call's span to the argument's).

## Tests

Group `infer-elements` (5): E1 (`xs : List({Int | _ > 0})`), E2 (`pos_only : List({Int | _ > 0})`),
a tuple component (`(List({Int | _ > 0}), Int)` read through `let (a, _b) = split(ys)`), R2 and O1
rejected `not-true`. The fixture now typechecks (element sorts come from the span → type table) and
can include `stdlib/list.march` as a sibling module (`~stdlib:true`), the shape the driver produces.
