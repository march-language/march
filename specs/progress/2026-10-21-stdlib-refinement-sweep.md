# Stdlib refinement sweep after #1008

**Date:** 2026-10-21
**Base:** `fa70709af` (origin/main, #1011), branch `claude/refine-stdlib-sweep`

A sweep of `stdlib/*.march` for functions where the refinement features that #1008 landed
(abstract refinements `Bool[p]` / `a[p]`, element flow phases 1-4, fold accumulator invariants
phases 1-4, `Within` field roles) can be stated AND are proved by the checker. Stdlib, tests and
docs only; no OCaml in `lib/` changed.

Much of the obvious ground was already covered by #1008 itself: the abstract-refinement phase D
and E sweeps (`List`, `Enum`, `Iterable`, `Prelude`, `Option`, `Range`, `Deque.filter`) and fold
phase 3 (`Map`, `Set`, `HashMap`, `Array`, `RRB`, `Deque` folds). This sweep found what was left.

## What was annotated

Every change declares the types the function already inferred; no body changed, and no
contract is refined (so no new definition-side obligation and no audit site). Nothing is
`@[assume]`d.

| Function | Before | After | Feature it unlocks |
|---|---|---|---|
| `Hamt.fold` | `fold(node, acc, f)` | `fold(node : HEntry(k, v), acc : b, f : b -> k -> v -> b) : b` | fold invariant, curried step |
| `Enum.scan` | `scan(xs, zero, f)` | `scan(xs : List(a), zero : b, f : b -> a -> b) : List(b)` | fold invariant as an element demand |
| `Queue.*` (all 11 public functions, 3 private helpers) | unannotated | `Queue(a)` / `List(a)` / `Option(a)` / `a` signatures | element flow through `Within` fields |

The Queue signatures: `empty() : Queue(a)`, `is_empty(q : Queue(a)) : Bool`,
`push_back`/`push_front(q : Queue(a), x : a) : Queue(a)`,
`pop_front`/`pop_back(q : Queue(a)) : Option((a, Queue(a)))`,
`peek_front`/`peek_back(q : Queue(a)) : Option(a)`, `size(q : Queue(a)) : Int`,
`to_list(q : Queue(a)) : List(a)`, `from_list(xs : List(a)) : Queue(a)`, and the helpers
`rev(xs : List(a), acc : List(a)) : List(a)`, `list_len(xs : List(a), acc : Int) : Int`,
`list_append(xs : List(a), ys : List(a)) : List(a)`. The helpers were needed: with only the
public functions annotated, `to_list` and `peek_*` were still `parametric-source-unproved`
(measured), because their bodies route through the unannotated `rev`/`list_append`.

## Tests: `test/test_refinecheck.ml`, group `stdlib-refine-sweep` (13 cases)

The harness loads the REAL `stdlib/{list,option,result,enum,hamt,queue}.march` plus the
prelude, as `fold-invariants-3` does, so a proof row is red on a stdlib without the
annotation. RED was measured by running the final test binary with the three stdlib files
reverted to `fa70709af` (11 of 13 fail; the two Queue controls pass on both). GREEN after.

| Case | `fa70709af` stdlib | This branch |
|---|---|---|
| `need_nn(Hamt.fold(h, 0, fn acc -> fn _k -> fn _v -> acc + 1))` | (0,0,1) `unreflectable-subject` | **(1,0,0)** |
| the same with `acc - 1` | `unreflectable-subject` | `accumulator-step-unproved` |
| `sum_nn(Enum.scan(ys, 0, fn acc -> fn _x -> acc + 1))` | (0,0,1) `unreflectable-subject` | **(1,0,0)** |
| the same with `acc - 1` | `unreflectable-subject` | `accumulator-step-unproved` |
| the same with base `0 - 1` | `unreflectable-subject` | `accumulator-base-unproved` |
| `sum_pos(Queue.to_list(Queue.from_list(xs)))`, `xs : List({Int \| _ > 0})` | (0,0,1) `unreflectable-subject` | **(1,0,0)** |
| `one_pos(Queue.peek_front(Queue.from_list(xs)))` | (0,0,1) | **(1,0,0)** |
| `one_pos(Queue.peek_back(Queue.from_list(xs)))` | (0,0,1) | **(1,0,0)** |
| `sum_pos(Queue.to_list(Queue.push_back(Queue.from_list(xs), 3)))` | (0,0,1) | **(1,0,0)** |
| `sum_pos(Queue.to_list(Queue.push_front(Queue.from_list(xs), 3)))` | (0,0,1) | **(1,0,0)** |
| control: `push_back(…, 0 - 3)` | not proved | not proved |
| control: `Queue.from_list` of an unrefined `List(Int)` | not proved | not proved |
| pinned gap: `sum_pos(Queue.to_list(q))`, `q : Queue.Queue({Int \| _ > 0})` | `unreflectable-subject` | `parametric-source-unproved` (still a skip; see below) |

## Rejected candidates

| Candidate | Why not |
|---|---|
| `Config.validate(k, predicate : v -> Bool)` | Tried `predicate : v -> Bool[p]` and `Result(v[p], String)`: the call stays `parametric-source-unproved` ("some way a value of `v` enters `Config.validate` cannot be traced"). `v` enters through `fetch`, which decodes from the untyped store with a `Codec(v)` (a function field, so the parametric gate cannot trace it). Reverted. |
| `List.pfilter` | Body routes through `task_spawn`/`task_await_unwrap` and `concat(map(…))`; the parallel chunks are not traceable. |
| `HashMap.filter` | Curried two-argument predicate `k -> v -> Bool`: needs the two-argument rule (a curried callback defines no `p`). |
| `Map.filter`, `OrderedMap.filter` | Two-argument predicates; `Map.filter` is being done on another branch. `OrderedMap` also has a record-typed collection parameter (`specs/todos/2026-10-18-refine-p1-record-typed-parameter.md`). |
| `Seq.filter`/`find`/`fold`, `Flow.filter`/`find`/`reduce`, `JsonStream.fold` | Church-encoded: the elements travel through a closure stored in data (fold phase 3, decision 5). |
| `Gen.filter`, `Gen.tree_filter`, `Parser.take_while` | The result is a generator / parser (closures), not a container of the filtered values. |
| `List.drop_while`, `Enum.drop_while`, `find_index`, `any`/`all`, `Tuple.both` | Nothing about `p` holds of the result (abstract-refinements design §4.2). |
| `RingBuf.to_list`, `NativeArray` folds | The body is one creating builtin; no `@[assume]`. |
| `SortedSet.fold`, `OrderedMap.fold` | Record-typed parameter, a checker change (open todo above). |
| A demand through a PARAMETER typed `Queue.Queue({Int \| _ > 0})` or `Deque.Deque(…)` | A checker gap, not a signature: a module-qualified container type gives a parameter no element entry, while the same shape over a type declared in the module under check proves. Filed: `specs/todos/2026-10-21-refine-qualified-container-param-entry.md`; pinned as a skip in the group. |
| `Queue.pop_front` / `pop_back` | Annotated, but `Option((a, Queue(a)))` is a tuple inside a container, which element refinements do not model (design §7); no claim made. |

Also noted, not chased: `sum_pos(Queue.to_list(Queue.push_back(Queue.push_back(Queue.empty(), 1), 2)))`
stays `parametric-source-unproved` (a queue started from `empty()` with literal pushes); the
`from_list` shapes above prove.

## Rulings

- Ruling: annotate Queue's private helpers (`rev`, `list_len`, `list_append`) as well as its
  public API — the public signatures alone left `to_list`/`peek_*` unproved (measured), and the
  helpers' types are exactly what they inferred — cost if wrong: none at runtime; a wrong helper
  signature would be a typecheck error, which the full suite would show.
- Ruling: `Hamt.fold`'s callback is declared `b -> k -> v -> b`, not a parenthesised
  `b -> (k -> (v -> b))` — the arrow is right-associative, so the two are one type, and it is the
  spelling `Enum.fold` already uses for its curried callback; the curried doctest and the
  `DataFrame` caller (`fn acc -> fn key -> fn row_indices -> …`) still typecheck — cost if
  wrong: a stdlib typecheck failure, caught by the full suite's stdlib ratchet.
- Ruling: `Config.validate` is left as it was rather than given a `Bool[p]` that proves nothing
  at any call — a signature that only ever yields skips would advertise a contract no caller can
  use — cost if wrong: a future checker that traces `fetch` would have to add it then.
- Ruling: the qualified-container parameter gap is filed and pinned, not fixed here — the task
  is a stdlib sweep, and the fix belongs in `lib/refinecheck/`, a checker change that needs its
  own soundness review and oracle run —
  cost if wrong: Queue/Deque demands from a parameter stay skips until the todo lands.

## Docs

`specs/lang/refinement-types.md` (regenerated `docs/refinement-types.md`): `Hamt.fold` moves from
the "do not" list to the fold list, `Enum.scan`/`List.scan_left` are named as element-demand
folds, and "What element refinements do not do" gains the qualified-container parameter bullet.

## Verification

- `dune build --root .` (targetless, restages the stdlib): ok.
- `scripts/run-tests.sh` (full): **All suites passed**. run_compiler 1451, run_eval 289,
  run_codegen 719, run_stdlib 896, test_stdlib_march 80, test_jit 43, test_lsp 383, test_utf16 5,
  test_jsonrpc 37, test_incremental 10, test_query_cli 8, test_refinecheck 1392 (z3 on PATH;
  includes `audit-baseline` and the new group), run_errors 290: 5603 tests, 0 failures. The only
  `[SKIP]`s are the environment-gated `cap_sandbox_runtime` (5) and `static_link` (1) cases.
- `scripts/refine-oracle.sh`: baseline taken on `fa70709af` in this worktree BEFORE any stdlib
  edit, check after, both with `_build/default/stdlib` absent and the script's private HOME:
  **REFINEMENT DIAGNOSTICS IDENTICAL** (7849 lines over 549 fixtures). Expected: the
  annotations are unrefined, so they add no obligation, trusted contract or audit site anywhere
  (including `stdlib/hamt.march`, `enum.march` and `queue.march` as entries), and no corpus or
  stdlib caller of these functions (`dataframe`, `aho_corasick`, `shell_render`) puts a refined
  demand on them. The new proofs are seen by the test group, not the corpus.
- `stdlib/list.march` CI ratchet (`--check --stdlib-source --refine-report`, private HOME):
  user code 35 proved / 1 skipped; user + stdlib 105 proved, 33 trusted, **37 skipped**
  (ceiling 37, unchanged).
- `test/refine_audit` baselines: not regenerated; unchanged (the `audit-baseline` group passes).
- `specs/lang/types/check_types.sh` (private HOME): 488 passed, 0 failed.
- `scripts/check-docs.sh`: passed (Check F confirms the regenerated `docs/refinement-types.md`).
- Not run: benchmarks (no body changed), the ecosystem repos.
