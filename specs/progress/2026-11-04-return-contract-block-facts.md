# A function's own `Int` result contract uses the facts before it (2026-11-04)

Closes the todo filed 2026-11-03 while writing `specs/lang/lemmas.md`, which this file replaces.
Every one of these used to skip (`march --check --refine-report-sites=all`):

```march
fn grow(n : {Int | _ >= 0}) : {Int | _ >= n} do
  let r = n + n          -- was solver-undecided
  r
end

fn grow2(n : {Int | _ >= 0}) : {Int | _ >= n} do
  twice_grows(n)         -- a proved lemma {Unit | twice(n) >= n}
  twice(n)               -- was unreflectable-subject
end
```

The same facts already proved a call's precondition. A function's result contract went through
the tail engine instead (`Refine_post.check_post`), which reads the path conditions and
`let r = f(..)` callee contracts, but not:
- a `let`'s equation;
- the lemma calls and `assert`s before the result;
- the unfolding of a reflected call as the result.

## What changed

- **Fallback walk.** When the tail engine leaves an `Int` result unproved,
  `Refine_post.check_fn_post_verdict_core` asks `post_walk_verdict`, which
  `Refine_check.post_scratch_verdict` installs.
  - The fallback runs only for a `post_walk_candidate`: one clause, and a statement before a
    tail or a call as a tail.
  - That walk is the lemma walk's, with `lw_ret = true`. It quietly walks the body
    (`scratch_walk`, the machinery `lemma_scratch_verdict` already used) and checks the
    predicate at every tail with `check_call`. The tail itself is the argument of the
    synthetic `$t` parameter, so the check sees exactly what a precondition at that tail
    would see.
- **Proved verdict.** The contract is proved when every tail is. One `Postcondition` row is
  then recorded at the clause span.
- **Skips and hints only when both fail.** The engine runs quietly first, so its skip and
  hint are filed only when the walk fails too.
- **The gate uses the same function.** A contract proved this way is admitted by
  `gate_unverified_posts` and becomes a fact at callers.
- **`assert` in the walk.** In a lemma, an `assert` is a fact only once proved, because nothing
  runs. In this walk it is a fact unconditionally, since the function runs and checks it
  (`lw_ret` in `visit`'s `EAssert` arm).
- **Only a module-level function.** A block-local `fn` walked on its own would resolve its
  calls at module level. A sibling local `uor` returning `-5` was then read as the module's
  `uor`, and the local's false `> 0` result proved (caught by `elemflow-local-fn` 15). The walk
  runs only for a function in `Refine_param.fn_defs_tbl`. A local keeps its own check
  (`visit_local_fn`).
- **Refused: a body that rebinds a parameter's name.** The walk reads the contract's parameter
  names at the tail, where a rebinding (`let n = n - 5`) would mean the inner value
  (`binder_occurrences`, moved from `refine_param.ml` to `refine_post.ml` so the candidate
  test can use it).
- **Cost:** one extra quiet engine run and one body walk, only for a candidate whose engine
  check failed. The VC cache serves the repeats.

## Not covered (still open, no separate todo)
- Results that are not `Int` (`List`, `Bool`, `Float`, `String`, records). Their contracts have
  their own engines (elts, induction, record reflection).
- Multi-clause functions.
- `--refine-infer` proposing a lemma call for a postcondition. The obligation's span is the
  clause, so `Infer_lemma.find_site` has no statement to place a call before (comment at
  `Infer_lemma.is_target`).

## Verification

| Check | Result |
|---|---|
| `return-block-facts` (10 cases: `let` result, lemma + reflected result, reflected result, `assert`, branches, false contract, rebound parameter, unproved lemma, block-local `fn` with a shadowing sibling, propagation to a caller under `@[opaque]`) | 10/10 |
| RED: fallback switched off | cases 0–4 and 8 fail |
| RED: rebinding guard removed | case 6 fails (`let n = n - 5; n` proved `_ >= n`) |
| RED: propagation, fallback off (`@[opaque] grow` called as `need_ge(n, grow(n))`) | the caller row goes from `proved` to `unreflectable-subject` |
| RED: the module-level guard removed | the new local-`fn` control fails, as does `elemflow-local-fn` 15 (`(3, 0, 0)`: the false result proved) |
| `scripts/run-tests.sh` (full, first run) | 7 failures, each read. Four lending controls (`gap-let-call-tail` 3 and 6, `demand-chains` 2 and 3) now prove a TRUE contract by unfolding the callee; they get `@[opaque]` on the callee so they keep testing what the contract alone lends. `elemflow-local-fn` 15 was the local-`fn` bug above. Golden `refinement_unverified_1` proved its true contract; it is re-based with `@[opaque] av`, its fourth re-base, and the style-allowlist failure followed from it |
| `scripts/oracle-base.sh refine` against merge-base 673ff42c04 | IDENTICAL (570 fixtures, 8145 lines) |

## Expectations that moved (each a true contract, now proved)
- `gap-let-call-tail` 3 and 6 and `demand-chains` 2 and 3: `b`'s result follows from `a`'s body
  (`a(x) = x`, `a(x) = x + 1`), which the walk unfolds.
- `test/errors/refinement_unverified_1`: `mk(z) = av(z)` with `av` the absolute value.
