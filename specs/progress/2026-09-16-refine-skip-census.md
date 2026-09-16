# Census of refinement skips (`--refine-report-sites`)

**Landed 2026-09-16.** Plan: `specs/plans/2026-09-16-refinement-precision-plan.md`
(Part A, phase A0). Open item:
`specs/todos/2026-09-16-refine-local-value-facts.md`.

## The flag

`--refine-report-sites` prints one line per SKIPPED obligation:

```
skip<TAB>user|stdlib<TAB>file:line:col<TAB>reason<TAB>kind<TAB>callee<TAB>predicate
```

`--refine-report`'s per-reason counts answer "how many", which is the wrong
question when deciding what to build next — a bucket of 42 says nothing about
whether those 42 share a cause. The hint text cannot substitute: residual
hints are throttled to one per module, so most skips never print one.

## What the census found

Over `stdlib/list.march` (which prepends the whole stdlib): 46 skips — 42
`unconstrained-subject`, 2 `partial-conjunct`, 2 `solver-undecided`. The 42
attribute as:

| Count | Site | Cause |
|---|---|---|
| 16 | `dataframe.march:2661-2724` | **A real bug.** `col_describe_column` calls `Stats.mean`/`min_val`/`max_val`/`percentile` (all `{List(Float) | len(_) > 0}`) on a column's values with no emptiness guard. |
| 11 | `aho_corasick.march` | `Array.get(nodes, state)` where `state` is an unannotated parameter of an internal helper (`child_of`, `get_fail`, `get_outputs`). Needs a declared param refinement, not a local-value fact. |
| 6 | `stats.march` | Wrappers forwarding to a contracted callee without declaring the same contract: `median(xs : List(Float))` calls `percentile(xs, 50.0)`, whose parameter is `{List(Float) | len(_) > 0}`. The doc string already says "Panics on empty list"; the signature does not. |
| 4 | `list.march:321,344,363,395` | 3 are `let t = pmap_threshold()`, a builtin with no contract; 1 is an `if`-shaped `let` RHS. |
| 2 | `datetime.march:547,555` | **A real bug.** `fixed_zone_hm(sign * h, m)` takes `{Int | _ >= 0 && _ < 60}`; `m` comes from `parse_digits(r, 2)`, which admits 60–99. *Fixed 2026-09-16: both skips are now one proved obligation — see `2026-09-16-datetime-parse-offset-panics-on-malformed-offset.md`.* |
| 3 | `seq.march:388`, `flow.march:113`, `gen.march:390` | Same wrapper-contract shape as `stats.march`. |

## Both "real bug" rows were confirmed by execution

```
DataFrame.head(df, 0) -- a frame with 1 column and 0 rows
DataFrame.col_describe(empty)
  => panic: Stats.mean: empty list

DateTime.parse_offset("2026-01-02T03:04:05+01:75")
  => panic: DateTime.fixed_zone_hm: minutes must be in [0, 60)
```

A parser that panics on malformed input rather than returning `Err` is the
sharper of the two. Both are filed as their own work; neither is a checker
defect — in both cases the checker was right and the code is wrong, which is
the strongest possible argument for keeping these skips visible.

## What this does to Part A of the plan

The plan's A0 existed to falsify its own estimate, and it did.

**"42 of 46 skips are `unconstrained-subject`, so local-value facts are the
highest-value work" does not survive contact with the data.** Exactly **one**
of the 42 is a pure let-flow case (`list.march:344`, an `if`-shaped RHS).
The dominant category — 20 of 42 across `aho_corasick`, `stats`, `seq`,
`flow` and `gen` — is a **missing declared contract on a wrapper or helper
parameter**, which is a stdlib API fix that `--refine-suggest` already
proposes, not an encoder change. 18 more are two genuine bugs.

Revised ordering for Part A:

1. **A2 (builtin contracts)** — closes 3 of 4 in `list.march`, and is the only
   category where the checker genuinely cannot see a fact that exists.
2. **Wrapper/helper param contracts in the stdlib** — a new phase the census
   created; ~20 sites. Each is honest work: the contract is already true and
   already documented in prose, it is simply not declared.
3. **A1 (`if`-shaped RHS)** — still worth doing, now correctly sized at one
   site rather than "the largest bucket".
4. The two bugs, separately.
