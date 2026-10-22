# Inference-lite, phase 5: the fixpoint, `--refine-infer`, JSON v1, `--apply`

Landed 2026-10-21. Design §3-§4. Plan Tasks 10-12.

## What a user sees

```
$ march --check --refine-infer app.march
inferred refinements: 1 proposed, 0 refused; user skips 1 -> 0 (104 probes, 2 rounds)
  pos_only (app.march:3)  return/elem : List({Int | _ > 0})  [element-return, closes 1]
$ march --check --refine-infer --refine-infer-apply app.march
...
applied 1 proposal(s) to 1 file(s); the re-check matches the prediction
```

`--refine-infer-json` (v1), `--refine-infer-diff`, `--refine-infer-kinds`, `--refine-infer-budget`,
`--refine-infer-stdlib`, `--allow-caller-violations`, `--apply-public`; `forge refine --infer
[--apply] [--diff]` (and `--fixpoint` as an alias). Nothing is proposed for a program that does not
check. The legacy `--refine-suggest*` flags are unchanged in output (pinned golden).

## What landed

- `Refine_infer.run`: rounds until none accepts (cap 10, budget 3000). Facts first (returns and K6,
  callees-first by Tarjan SCCs), then parameter slots, then accumulators; demand chains through a
  return's tail callee (depth 3), tentatively installed; accepted hypotheses installed in the tree
  and in the checker's definition tables (restored at the end). SCCs > 1 whose members all fail
  are noted `scc-unsupported` (uniform hypotheses deferred).
- `Infer_json`: JSON v1, stable order, closed reason set; `after_counts` (raw user-code skipped and
  violated) is what the post-apply re-check compares with `--refine-report`.
- `bin/main.ml`: printer, `--refine-infer-apply` (splice via `Refine_edit`, re-check, revert +
  exit 3 on mismatch; `MARCH_INFER_CORRUPT_PREDICTION=1` forces one for tests), `--refine-infer-diff`.
- Vocabulary fixes found by the first CLI run: candidates are sort-filtered (an ill-sorted stdlib
  predicate held the solver to its timeout, E1 took 267 s), and the house vocabulary is user code
  plus the slot's callees.

## Tests

Groups `infer-fixpoint` (9: two-hop chain, facts before demands, C1 gap, G1 nothing, termination +
G0 refused, SCC note, JSON schema, stable output, closed reasons), `infer-cli` (3: type error, E1
through the binary, legacy JSON golden), `infer-apply` (7: apply + clean re-check, idempotent with a
warm cache, mismatch revert, multi-line signature, external-callers guard, stdlib guard, diff).

## Perf

20 `test/native` files, cold: `--refine-infer` / `--check` median 1.78×, max 2.67× (budget 3×).
