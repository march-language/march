# Reflection phase 7: `--refine-infer` proposes lemma calls (2026-11-04)

Spec `specs/2026-10-29-refinement-reflection-design.md` §10 "Phase 7" (D19); plan
`specs/plans/2026-11-04-reflection-phase7-infer-lemmas-plan.md`, whose rulings this follows.

## What it does

At a user-code precondition whose verdict is `skip:reflect-fuel` or `skip:reflect-budget`,
`march --check --refine-infer` (and `forge refine --infer`) proposes a statement-position call of
an existing lemma, user or stdlib, that closes it. When no lemma closes it, it prints the lemma
that would.

```
inferred lemma calls: 1 proposed, 0 not inferred
  use_it (s.march:5)  List.reverse_reverse(xs)  [closes the precondition `b == a` on `need_same`, 1 of 4 candidates checked]
```

- **Search** (`lib/refinecheck/infer_lemma.ml`):
  - The pool is the call subterms of the call's arguments, plus the right-hand sides of the
    `let`s they read, transitively.
  - A lemma is a candidate when a call in its theorem matches a pool term by first-order
    matching; heads compare by last name segment, and every parameter must be bound.
  - The call goes before the innermost block statement holding the call. A non-block arm,
    branch or lambda body is wrapped in a block in the tree.
- **Check** (`Refine_infer.infer_lemmas`): each candidate, at most 8 per obligation, is installed
  in the tree and the module is re-checked with `Refine_check.check_module`. It is kept only if
  all of these hold:
  - the target proves;
  - the inserted call gave its fact (`lemma_fact_spans`, so its preconditions proved);
  - no user proof is lost;
  - no error is added.

  Kept proposals are then confirmed together, with up to 3 retries. The confirmed tree's ledger
  is the prediction `--refine-infer-apply` checks. The metric search runs after, on the tree
  that has the calls.
- **Skeleton:** the goal is the callee's predicate at the call's arguments, with `let`s inlined,
  over the function's typed parameters. It is checked by inserting `assert <goal>` and
  re-checking. It is printed with `March_format.Format`, and is never applied.
- **Output:** a text block, the JSON keys `lemma_calls` / `lemma_none`, and
  `--refine-infer-apply` / `-diff` through `Refine_edit.insert_statement`, which places the call
  on its own line at the statement's indentation, or `apply-by-hand` otherwise. The kind name is
  `lemma`.
- **Cost:** none unless the caller's check left a reflection skip (gated in `Refine_infer.run`
  on the caller's ledger). Each candidate costs one module re-check.

## Rulings made while building (beyond the plan)

1. **Postconditions are not targets.** A function's own postcondition is checked without its
   body's lemma facts (todo `2026-11-03-return-contract-ignores-block-facts`). Measured:
   `List.len_reverse(xs)` above a returned `List.reverse(xs)` leaves `len(_) == len(xs)`
   `solver-undecided`. When that todo closes, add `Postcondition` to `Infer_lemma.is_target`,
   with a test.
2. **The skeleton is checked with `assert`, not by installing it.** An unproved lemma's call gives
   no fact (`lemma_unproved`), so installing the skeleton could never prove the target. A
   runtime `assert` before the statement is a fact to the checker, and it is exactly "assume the
   theorem here".
3. **`Nil` prints as `[]`** in a skeleton (the formatter's spelling). `[]` is accepted in a
   predicate and means `Nil` (checked: the theorem is reported back as `cat(xs, Nil) == xs`).
4. **Same-file lemmas are called by their short name**, others by the qualified name from
   `Refine_check.lemma_defs`. A wrong spelling would fail its re-check, never be offered.

## Verification

| Check | Result |
|---|---|
| `reflect-infer-lemma` (12 cases: stdlib, user, unhelpful lemma + skeleton, shadowed name, two skeletons, REJECT control, postcondition not a target, `let` pool, arm body, gating and kinds, JSON, apply round trip) | 12/12 |
| RED control: the candidate check and the confirmation made to accept everything | cases 1, 2, 3 fail (an unhelpful `len_cat`, an unprovable `List.len_take` precondition) |
| RED control: skeleton names ignore the ones already given this run | case 5 fails (`f_lemma_2(ys)` missing) |
| RED control: `rebind`/`once` switched off | case 4 still passes: the `assert` re-check also refuses a goal built across a rebinding, so that case pins the behaviour, not that layer |
| `scripts/run-tests.sh` (full, before merging main) | all suites pass except `audit-baseline` 0/1, the stdlib count drift (198 → 214 enforced) that #1088 regenerated on main |
