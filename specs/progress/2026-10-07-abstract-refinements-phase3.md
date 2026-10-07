# Abstract refinements, phase 3: named predicates, callback and `let`-bound lambdas, three more combinators

Landed 2026-10-07. Plan: `specs/plans/2026-10-07-abstract-refinements-phase3-plan.md`.
Design: `specs/2026-09-20-abstract-refinements-design.md` (phase 3). Builds on
phase 2 (`2026-10-06-abstract-refinements-phase2.md`).

## What a user sees

```march
fn is_pos(n : Int) : {Bool | _ == (n > 0)} do n > 0 end
sum_pos(List.filter(ys, is_pos))              -- proved (was uninstantiated)
sum_pos(List.filter(ys, fn y -> is_pos(y)))   -- proved (eta)
let keep = fn y -> y > 0
sum_pos(List.filter(ys, keep))                -- proved
fn keep_pos(ys, k : ({x : Int | true}) -> {Bool | _ == (x > 0)}) = sum_pos(List.filter(ys, k))   -- proved
one_pos(List.find(ys, fn y -> y > 0))         -- proved (List.find : Option({a | p(_)}))
one_pos(Option.filter(o, is_pos))             -- proved
sum_pos(List.take_while(ys, is_pos))          -- proved
one_pos(List.find(ys, nonneg))                -- skip: `nonneg` (`n >= 0`) does not imply `_ > 0`
```

## Pressure test, before and after

Each row was probed on the CLI before planning; each is now a test.

| # | Shape | Before | After |
|---|---|---|---|
| q01/q03 | named predicate, either `==` orientation | uninstantiated | **proved** |
| q02 | named predicate with no contract | uninstantiated | uninstantiated |
| r5 | named predicate whose return is NOT proved | uninstantiated | uninstantiated (never used) |
| q04 | callback parameter passed through | uninstantiated | **proved** |
| q05 | `let`-bound lambda (and an alias of it) | uninstantiated | **proved** |
| q06 | `fn y -> gt(y, 0)`, two-parameter callee | uninstantiated | uninstantiated |
| q07 | `fn y -> is_pos(y)` | uninstantiated | **proved** |
| — | local `let is_pos = fn y -> y >= 0` shadowing a top-level `is_pos` | uninstantiated | too-weak (the LOCAL lambda is read) |
| r2–r4 | `find` / `Option.filter` / `take_while` user copies | proved | the stdlib now carries them |

## What landed, per commit

| Commit | Change |
|---|---|
| `feat(refinecheck): a named predicate, a callback parameter, or fn y -> g(y) …` | `named_predicate` reads a callable's proved `{Bool \| _ == e}` return through `callee_sig` (which hides unproved returns); `instantiate_abstract ~named`; a bare `fn y -> g(y)` is `g` |
| `feat(refinecheck): a let-bound lambda …` | `lets` also records `name → ELam` (aliases copy it, `launder_shadow` retires it); `instantiate_abstract ~local_lambda` consults it first; `alias_withdrawal_cause` reads application entries only |
| `feat(stdlib): List.find, Option.filter and List.take_while …` | the three signatures; `take_while` rewritten in natural style; a too-weak skip names a named predicate |

## Tests

`test_refinecheck`, group `abstract-phase3` (15):
- C1, ten cases, six red first. Disabling `named_predicate` reddens exactly those six.
- C2, five cases. Disabling the `ELam` arm reddens exactly the three that need it.

Phase 2's "a lambda that calls a function is uninstantiated" guard moves to a
non-eta body (`fn y -> is_pos(y) && y < 100`), since a bare `is_pos(y)` now
proves.

`test/stdlib/test_list.march` gained two `take_while` cases, pinned on the
OLD body first and shown live by a perturbation: stopping at the first failure
even when later elements pass, and an empty list.

The conformance pair `accept/t310` (all PROVED under `cap verified`, plus a
`String` row) and `reject/t311` (a weaker named predicate) bring the corpus to
432/432.

## Verification

- Refinement oracle vs `main` (#844 merged):
  - 962 count lines `+5 proved` / `+5 precondition` (the five new definition-side proofs: `find` 2, `take_while` 2, `Option.filter` 1);
  - `stdlib_list` user code +4 and `stdlib_option` +1;
  - 9 new lines, one `non_tail_recursion` warning on the natural-style `take_while`. It's the same warning `append`, `filter_map` and `flat_map_go` already carry on `main`.
  - No skipped, violated or trusted count moved anywhere.
- Audit baselines: every line `+9 enforced` (3 contract sites × 3 functions); `list.march` 17 → 23, `option.march` 2 → 5; 0 unenforced.
- CI ratchet (`stdlib/list.march`, user + stdlib), against main's own copy: 58 → 63 proved, **37 → 37 skipped**.
- Ecosystem (`conduit` + `depot`, 77 lib files, base vs branch): byte-identical.
- `take_while`, compiled `--opt 2`, 60 × a 150k prefix of 200k, interleaved, warm runs: base 0.21–0.23 s, branch 0.17–0.20 s, same output.
- `bench/list_ops.march`: identical output; 0.04–0.07 s both.
- Cold `--check --stdlib-source stdlib/list.march`: base median 3.32 s, branch 3.52 s (+6%). The load average was 48 throughout, so this is noisy; it's within the 110% budget.
- Full suite (`scripts/run-tests.sh`): all passing. Compiler 1372, eval 288, codegen 681, stdlib 894, stdlib_march 77, jit 33, lsp 379 + 5 + 37 + 10 + 7, refinecheck 1020, errors 269.

## Environment note

The run hit ENOSPC mid-way: `~/.cache/dune` had grown to 182 GB.
`dune cache trim --size 20GB` (CLAUDE.md's prescription) freed 146 GB. The
suites and oracle that overlapped it finished, and their results are fully
accounted for above.

## Still open

- `Deque.filter` (would need `@[assume]` plus a runtime witness).
- `List.partition` (`p` inside a tuple and under `not`).
- `drop_while` (no element fact).
- Arity > 1 (`Map.filter`, a `fold_left` invariant; `2026-09-20-abstract-refinements-multi-arg-callbacks.md`).
- A lambda calling anything but a single eta-reducible call.
- Phase 4: the `a[p]` shorthand.
