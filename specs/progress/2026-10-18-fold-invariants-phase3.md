# Accumulator invariants for fold-shaped calls, phase 3 (stdlib signatures)

Landed 2026-10-18. Design: `specs/2026-10-18-fold-accumulator-invariants-design.md`, phase 3
of §8 (§6's survey, row f16 of §0; user decision 3: change the public signatures, one module
per commit, each followed by the compiler suite). Built on `0d2afa8f6` (phases 1 and 2).

## What a user sees

```march
need_nn(Map.fold(m, 0, fn (acc, _k, _v) -> acc + 1))          -- was a skip; proved
need_nn(Deque.fold_left(d, 0, fn (acc, _x) -> acc + 1))       -- was a skip; proved
need_nn(Deque.fold_left(d, 0, fn (acc, _x) -> acc - 1))       -- skip, accumulator-step-unproved
```

No checker change. The rule of phases 1-2 needs the callee's DECLARED `b` and callback arrow
(P1, `generic_in_inferred`, aligns every declared parameter type with its inferred one; an
unannotated parameter, or no declared `b` at all, answers no). Each fold below now declares
the types it already inferred. Bodies are unchanged: no runtime pin was needed.

## Per module

Each row: one commit (signature line(s), the module's `fold-invariants-3` rows), then the
named-target build, `scripts/run-tests.sh -q compiler` (1348 pass each time) and `-q stdlib`
(825 pass each time). "Base" is the row on `0d2afa8f6`, measured by running the final test
binary against the base version of that one stdlib file.

| Module | Commit | Before | After | P1 / P2 | Proof row (base → now) | Control row (base → now) |
|---|---|---|---|---|---|---|
| `Map.fold` | `ab8eda689` | `fold(m, acc, f)` | `fold(m : Map(k, v), acc : b, f : b -> k -> v -> b) : b` | yes / yes (through unannotated `node_fold`, a `Dep` that is safe) | (0,0,1) `unreflectable-subject` → (1,0,0) | `unreflectable-subject` → step skip |
| `Set.fold` | `2beedef44` | `fold(s, acc, f)` | `fold(s : Set(a), acc : b, f : b -> a -> b) : b` | yes / yes (`node_fold`) | same | same |
| `HashMap.fold` | `50362c03c` | `fold(m, acc, f)` | `fold(m : HashMap(k, v), acc : b, f : b -> k -> v -> b) : b` | yes / yes (`node_fold`) | same | same |
| `Array.fold_left` | `20bc7e9b7` | `fold_left(v, acc, f)` | `fold_left(v : PVec(a), acc : b, f : b -> a -> b) : b` | yes / yes (`trie_fold`) | same | same |
| `RRB.fold`, `RRB.fold_left` | `6c2aba807` | `f` unannotated | `f: b -> a -> b` on both | yes / yes (`Array.get`, `slice`, `length`) | (0,0,1) `parametric-source-unproved` → (1,0,0), each | `parametric-source-unproved` → step skip, each |
| `Deque.fold_left`, `Deque.fold_right` | `6e8973711` | `f` unannotated | `f : b -> a -> b` / `f : a -> b -> b` | yes / yes (`List.fold_left` / `fold_right`) | same as RRB | same as RRB |

The step control is `fn (a, …) -> a - 1` against `need_nn` with base `0`: `(0, 0, 1)`,
reason `accumulator-step-unproved`, never a violation.

The Deque commit touches only the two signature lines (`stdlib/deque.march:135`, `:140`);
another branch (abstract-refinement leftovers phase E) edits `Deque.filter` in the same file,
so that merge needs a look.

## Probed and not covered (pinned as skips in the group)

| Fold | Verdict | Why |
|---|---|---|
| `NativeArray.fold_int` (and the other kinds) | `unreflectable-subject` | unannotated, body is one creating builtin; stays skip by decision 5, no `@[assume]` |
| `Seq.fold` / `fold_while` | `unreflectable-subject` | church-encoded; stays skip by decision 5 |
| `SortedSet.fold`, `OrderedMap.fold` | `parametric-source-unproved` | §6 said "phase 1, if P2 holds for `tree_fold`; probe". P2 is not the problem: the collection parameter is a record type and `Refine_param.align` has no `TyRecord` case, so P1 answers no (a user fold with `s : {t: List(a)}` skips, its tuple twin proves). Filed: `specs/todos/2026-10-18-refine-p1-record-typed-parameter.md`. Not fixed here: it is a checker change, not a signature. |
| `Hamt.fold` | not probed | not in §6's survey (found by a re-sweep); unannotated with a CURRIED callback. Filed: `specs/todos/2026-10-18-refine-hamt-fold-unannotated.md`, which also records that `JsonStream.fold` and `Flow.reduce` delegate to `Seq.fold` |

Also probed, already covered and unchanged: the prelude's `fold_left`, `Iterable.fold`,
`Range.reduce` (each proved).

## Tests

`test/test_refinecheck.ml`, group `fold-invariants-3` (20 cases): per fold a proof and a step
control (16), plus the four skip pins above. The harness loads the REAL stdlib files
(`list`, `map`, `set`, `hash_map`, `array`, `rrb_vec`, `deque`, `native_array`, `seq`,
`sorted_set`, `ordered_map`, prelude) from `stdlib/` relative to the cwd, as
`abstract-leftovers-d` does, so the proof rows are red on a base stdlib. Every one of the 16
was red against the base version of its file (proof `(0, 0, 1)`, control reason
`unreflectable-subject` / `parametric-source-unproved`).

No conformance pair: the design calls for none in phase 3, and the corpus is unchanged (480).

## Verification

- `test_refinecheck.exe -e` (private `HOME`, VC cache cleared once), in three parts by
  group-name initial (the foreground limit): `^[a-e]` 556 + `^[f-o]` 329 + `^[p-z]` 423 =
  1308 tests, all pass, none run twice. `audit-baseline` (part 1) passes: no `test/refine_audit`
  baseline moved, as expected (the annotations are unrefined, so they add no contract site).
  `z3-well-formed` ran in part 3 and saw only that part's queries.
- `scripts/run-tests.sh -q compiler`: 1348 pass after every module commit.
- `scripts/run-tests.sh -q stdlib`: 825 pass after every module commit.
- `test_stdlib_march.exe -e`: 80 pass.
- `specs/lang/types/check_types.sh` (private `HOME`): 480 passed, 0 failed.
- `scripts/refine-oracle.sh`: baseline from a detached `0d2afa8f6` worktree at the same
  directory depth (stdlib re-staged), check here: **identical**, 8717 lines over 549
  fixtures. No corpus file puts a demand on one of these folds, and the stdlib's own fold
  calls (e.g. `crdt.march`'s `Map.fold`) carry none, so nothing moves; the group is what sees it.
- `stdlib/list.march` `--check --refine-report`, private `HOME`, caches cleared: byte-identical
  to the base after path normalisation (35 proved, 0 violated, 1 skipped for user code; 100 /
  0 / 33 trusted / 37 skipped with stdlib). The ratchet does not move. (Both exit 1 on the
  pre-existing `cap_needs` error for checking `List` alone.)
- `scripts/check-docs.sh` passes.
- The bookkeeping commit adds one doc-string sentence to the `Map`/`Set`/`HashMap`/`Array`/
  `RRB` folds (not `Deque`, to keep that file's diff to the signatures); after it, `-q
  compiler` 1348, `-q stdlib` 825, `test_stdlib_march` 80 and the group, all pass.

## Left open

- `SortedSet.fold` / `OrderedMap.fold` (P1 and record-typed parameters), and `Hamt.fold`:
  the two todos above.
- Phase 4 (the annotated accumulator).
