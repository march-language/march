Refinements: `HashMap.filter` carries an assumed two-argument entry fact

Closes `specs/progress/2026-10-21-hashmap-filter-two-argument-abstract.md` (moved from
`specs/todos/`). Container-gap batch, gap 1 of 4, branch `claude/refine-container-gaps`.

## Root cause

`HashMap.filter(m, pred)` was unannotated (`fn filter(m, pred)`), so no abstract
refinement was declared, P1 had nothing to align, and a demand on its result was an
`unreflectable-subject` skip. The checker machinery (the `@[assume]` element return of
multi-arg phase 4, `elem_ret_assumed`, `abstract_flow_n`) already handled `Map.filter`;
only the signature was missing.

## Fix

Stdlib only, no OCaml in `lib/` changed. `stdlib/hash_map.march`:

```march
@[assume]
fn filter(m : HashMap(k, v), pred : k -> v -> Bool[p]) : HashMap(k[p], v[p]) do
```

The body is unchanged. Unlike `Map.filter` there is no container predicate to keep:
`HashMap` has no `keys` measure. The `doc` paragraph says that the entry fact is
assumed, why (the body goes through `entries`, a list of tuples, and a curried call),
and where the runtime witness lives.

## Tests

New group `hashmap-filter` in `test/test_refinecheck.ml` (14 cases), on a new local
harness `container_gap_harness` (the abstract-map harness shape, parameterised by the
stdlib files to load; here the REAL `stdlib/list.march` and `stdlib/hash_map.march` plus
the prelude). RED with the test written and the stdlib not yet edited:
`13 failures! in 0.251s. 14 tests run.`

| # | Case | RED (Expected → Received) | GREEN |
|---|---|---|---|
| 0 | h-m1 value filter → `need_vals` | `[proved]` → `[(skipped, unreflectable-subject)]` | proved |
| 1 | h-m2 key filter → `need_keys` | same | proved |
| 2 | h-m3 `v > k` → `need_rel` | same | proved |
| 3 | h-m4 `v >= 0` → too-weak, detail names the lambda and `_ > 0` | `[too-weak]` → `[unreflectable-subject]` | too-weak |
| 4 | h-m5 `k > 0 && v > k` → `need_ivals` (projection) | `[proved]` → `[unreflectable-subject]` | proved |
| 5 | h-m6 `v > k` → `need_ivals` | `[too-weak]` → same | too-weak |
| 6 | h-m7 captures `now` | `[uninstantiated]` → same | uninstantiated; after merging #1028 (the n-ary capture rule) `solver-undecided`, as abstract-map m7 |
| 6b | h-m7b captures `now : {Int \| _ >= 0}` (added with the #1028 merge, mirroring abstract-map m7b) | — | proved |
| 7 | h-m8 through a `let` | `[proved]` → same | proved |
| 8 | name capture: caller params `pred : HashMap(…)`, `m : Int`; lambda `fn m -> fn k -> k > m` | `[proved]` → same | proved |
| 9 | capture control: `fn m -> fn k -> m > k` | `[too-weak]` → same | too-weak |
| 10 | h-m9 refined parameter (unchanged row) | passes on base | proved |
| 11 | `cap verified` control: h-m6 is an `abstract-refinement-too-weak` error | `true` → `false` (base: the unreflectable-subject error) | error |
| 12 | `cap verified`: h-m3 leaves no error | `[]` → one "cannot verify element refinement `true` on `need_rel` (unreflectable-subject…)" | `[]` |
| 13 | one trusted postcondition `p($s0, $s1)` at `filter` in `hash_map.march`, no `return of filter` obligation | `[(trusted, p($s0, $s1))]` → `[]` | as expected |

Every accept has a skip or error control (3, 5, 6, 9, 11).

**Runtime witness.** `test/stdlib/test_hash_map.march`, describe "filter":
- "every entry HashMap.filter keeps satisfies pred (the assumed entry fact)": over
  `Gen.tuple2(Gen.list(Gen.tuple2(Gen.int(-20, 20), Gen.int(-20, 20))), Gen.int(-10, 10))`
  it filters `HashMap.from_list(pairs)` with `fn k -> fn v -> v > k + t` and checks
  every entry of `to_list` (helper `above`, as in `test_map.march`);
- "HashMap.filter keeps every entry that satisfies pred": the converse, so a filter that
  drops everything does not pass the first property vacuously.

Perturbation: `if p(v)` inverted to `if !p(v)` in `stdlib/hash_map.march`, restaged
(`dune build --root . stdlib/hash_map.march`), `march test test/stdlib/test_hash_map.march`:

```
FAIL: "filter filter keeps only matching entries"
FAIL: "filter every entry HashMap.filter keeps satisfies pred (the assumed entry fact)"
  error: panic: property failed after 2 run(s)
  counterexample: ([(0, -8)], 0)
FAIL: "filter HashMap.filter keeps every entry that satisfies pred"
  counterexample: ([(0, 0)], 0)
FAIL: "doctest HashMap.filter (1)"
=== 1/1 file, 4/2433 tests failed ===
```

Restored from a saved copy (`grep -c 'if !p(v)'` = 0), restaged: `=== 1 file, 2433 tests passed ===`.

## Verification

- **Refine oracle.** Baseline at `bc1fef6f1` (origin/main) in this worktree before any
  edit: 552 fixtures, 8750 lines. After: `DIAGNOSTICS CHANGED — 2212 differing lines`.
  A script applying `+1 trusted` to every fixture's `user + stdlib` line and `+1
  postcondition` to its `by kind` line accounts for every pair but one:
  `stdlib_hash_map`'s own `user code` line goes from 0 to 1 trusted (and its by-kind
  from 0 to 1 postcondition). No proved, violated or skipped count moved. The oracle
  going red is this run itself.
- **Real programs.** No program in `examples/`, `test/native/` or `stdlib/` calls
  `HashMap.filter` (grep); the stdlib callers of other `HashMap` functions
  (`enum.march`, `shell_render.march`) are oracle fixtures and moved only by the bump.
- **Refine audit baselines** regenerated (`UPDATE_SNAPSHOTS=1 … audit-baseline`).
  Reason: the new signature has five refinement sites (the definer's two domains and
  its codomain, the return's two slots), all Enforced, as for `Map.filter`. Every
  `user + stdlib` line goes from 180 to 185 enforced (the holes baseline's line too,
  its 1 unenforced unchanged), and `stdlib_hash_map`'s user code from 0 to 5. No Inert
  or Unenforced line appeared.
- `scripts/run-tests.sh refinecheck compiler stdlib_march` (z3 on PATH): `All suites
  passed.` refinecheck 1699 tests, run_compiler 1453 (the stdlib ratchet), test_stdlib_march
  81. The full suite runs once at the end of the batch.
- `stdlib/list.march` skip ratchet: unchanged (no skip count moved anywhere in the oracle).

## Rulings

- Ruling: `@[assume]` on `HashMap.filter` although no other `HashMap` function is
  `@[assume]`d — the todo and the design (§7.1) prescribe the `Map.filter` recipe, the
  body is opaque to the checker for the same two reasons (tuples, a curried call), and
  the fact is witnessed at run time in both directions — cost if wrong: one trusted
  postcondition that a future tuple-element model could prove instead.
- Ruling: no container predicate on the return — `HashMap` has no key-set measure, and
  inventing one here would be a new assumed contract with no witness — cost if wrong:
  none; `Map.filter`'s `subset(keys(_), keys(m))` has no `HashMap` counterpart to lose.
