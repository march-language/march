Termination checking, phase 0: the call graph, the COUNT classifier, `--termination-report`

Design: `specs/2026-10-26-termination-checking-design.md` §8 phase 0 (with §0.5, §3.2).
Branch `claude/termination`. Inert: nothing but the new flag reads the result.

## What changed

- **`lib/refinecheck/refine_term.ml` (new).** It holds three things:
  - The §3.2 call graph over every unit: a top-level `fn` at any `mod` depth, a local
    `fn` (named `outer/inner`), and an actor handler (named `Actor.Msg`).
  - Three edge kinds: a direct call; a call inside a lambda or a `let*`
    continuation (a lambda edge); and a function named as a value (a reference edge,
    no arguments).
  - Tarjan SCCs over that graph, and the COUNT classifier of §0.5.
- **`--termination-report`** (`bin/flags.ml`, `bin/main.ml`). It prints one tab-separated row
  per recursive user unit: class, shape (`structural`, `int-dec`, `int-asc`, `lex`,
  `lambda`, `ref`, `none`, plus `mutual`), site, name, kind and SCC size, then a per-class
  count. Like `--refine-report`, it bypasses the early CAS exit, so a warm cache cannot
  silence it.
- **Todos filed:**
  - the two F3 stack-safety gaps:
    - `specs/todos/2026-10-27-tailcall-local-fn-in-nonrecursive-fn-unchecked.md` (t10b);
    - `specs/todos/2026-10-27-tailcall-actor-handlers-unchecked.md` (t12);
  - the four §0.4 stdlib divergences, s1-s4, per D5:
    - `2026-10-27-list-range-step-zero-loops.md`;
    - `2026-10-27-range-to-list-step-zero-loops.md`;
    - `2026-10-27-control-chunks-size-zero-loops.md`;
    - `2026-10-27-duration-format-min-int-overflows.md`.
  - The c4 mutual-measure cycle is not filed: phase 1 fixes it.
- `specs/lang/refinement-types.md`: a new section, "Termination: `--termination-report`". The
  docs were regenerated with `scripts/gen-lang-docs.py`. A CHANGELOG `### Added` bullet was added.

## Tests (group `termination-report`, `test/test_refine_term.ml`, 17 cases)

Each case asserts a `(shape, class, mutual)` triple. The rows are:
- t1, t2, t3 (both members, `mutual`), t4, t5, t7, t8 (`lex`/D), t9;
- t9b: all three of `bits1`, `same` and `grow` are `none`. `grow` is also asserted to draw the stack pass's
  "structurally recursive" warning (§3.1 separation);
- t10b: `h/go3` is a unit, and `h` is not;
- t11 (`ref`/F); t11b (`lambda`/F);
- shadowing: the local `length/go` is structural, while the top-level `go` and `length` have no row;
- nested `mod`: `Inner.boom`;
- lexical resolution (below);
- the report's lines and summary.

RED, watched first against a stub `analyze` that returned no rows: all 16 cases then present failed.
The first failing line was:

```
FAIL spin (shape, class, mutual)
   Expected: `("none", "?", false)'
   Received: `("<no row>", "", false)'
16 failures! in 0.009s. 16 tests run.
```

The lexical-resolution case came out of the sweep (below). It was watched RED by reversing the
lookup order (top level first): `FAIL L.fold_left has no row; rows: `. GREEN: 17/17.

## The sweep, against the design's §0.5 table

`--check --termination-report` was run over all 135 `stdlib/*.march` and all 417 `test/native/*.march`.
Each run had a private `HOME`, and the rows were deduplicated by declaration site.

| Class | stdlib, this pass | stdlib, §0.5 | test/native, this pass | test/native, §0.5 |
|---|---|---|---|---|
| units | 763 | 762 | 523 | 522 |
| A structural | 466 | 465 | 74 | 74 |
| B Int metric, bounded | 84 | 85 | 346 | 346 |
| C Int metric, unbounded | 51 | 54 | 79 | 80 |
| D lexicographic | 3 | 24 (6 syntactic + 18 hand-classified parsers) | 0 | 0 |
| E external-event loop | 35 (`E?`, name heuristic) | 41 (hand) | 4 | 8 |
| F function value / lambda | 12 | 25 | 0 | 0 |
| G, H, I and the rest | 112 (`?`) | 29 + 33 + 6 (hand) | 20 | 14 (G) |

stdlib breakdown: 410 top-level and 353 local units; 82 rows in a multi-member SCC.

The syntactic classes (A, B, C) agree within the design's ±10% "regex-grade" tolerance.
The hand-classified classes (D's parsers, E, G, H, I) fall into `?`/`E?`, as §8 phase 0 says
("the hand-classified ones by heuristic plus `?`").

There are two differences, both explained:
- **F: 12 here, 25 in §0.5.** A unit with both a lambda edge and a direct edge is F here.
  A unit that captures its own name inside a lambda *without* a cycle through it has no
  intra-SCC edge, so it is not recursive by §3.2.
- **82 mutual rows, against §0.5's 47 mutual-SCC members.** A local `fn` that calls its enclosing
  function forms a two-member SCC with it (`hamt_insert` ↔ `hamt_insert/coll_expand`).
  §0.5 counted only top-level members.

## Rulings

- **Ruling: the graph is global across `mod` nesting, and a name resolves lexically** —
  the order is a local binder, then the enclosing module's declarations, then outward to the
  top level.
  - Why: the driver prepends the stdlib with bare intra-module calls inside its `DMod`s. The
    first sweep resolved top level first, and that tied `List.fold_left`'s own recursion to
    `Deque`'s entry-file `fold_left`. That first sweep reported 777 stdlib units and 97 mutual rows. With lexical lookup
    it reports 763 and 82: 14 units were recursive only through a forged edge, and 15 mutual
    rows were forged (`Deque.fold_left`, `Range.map`, `Deque.any`, …).
  - Cost if wrong: a name that genuinely means an outer declaration while a same-named inner one
    exists would be misattributed. Lexical scoping is March's own rule, so that should not happen.
- **Ruling: the tail pass's call graph is not moved to `lib/typecheck/callgraph.ml` (§3.1).**
  `Refine_term` has its own graph.
  - Why: §3.1's move is a typechecker refactor with no behavioural payoff in phases 0-1. It
    would put the tail pass in this PR's blast radius, along with a types-oracle run for no
    change. The two graphs already differ by design: lambda and reference edges, lexical
    cross-module resolution, local units.
  - Cost if wrong: two resolvers to keep in step. The shadowing and nested-`mod` tests pin
    the shared cases.
- **Ruling: the phase-0 classifier's "structural" is its own syntactic sub-component set**
  (a match on a parameter or a component, including a merged multi-head function's tuple
  scrutinee). It does not use `structural_subvars`.
  - Why: §0.5's numbers were measured that way. It is a measurement, and nothing trusts it;
    phase 1's certificate uses `structural_subvars`.
  - Cost if wrong: class A over-counts by the shadowing cases `structural_subvars` drops.
- **Ruling: "bounded" means an ordering comparison (`<`, `<=`, `>`, `>=`) on the parameter, or a
  refinement on it.** `==` does not count.
  - Why: §0.5 puts `if i == 0 … go(i - 1)` in C.
  - Cost if wrong: misfiled B/C units, which are report-only.

## Oracles

- `scripts/refine-oracle.sh`: the baseline was taken before the first edit, then checked
  after: `REFINEMENT DIAGNOSTICS IDENTICAL (7861 lines over 552 fixtures)`.
- `scripts/ir-oracle.sh`: the baseline was taken with a frozen pristine `c918d14ca` compiler
  (`MARCH_ORACLE_EXE`), because a mid-run rebuild would have mixed two compilers into one
  manifest. Checked after, with a frozen copy of the phase-0 exe: `IR IDENTICAL across 497 programs`.
- The typechecker is untouched, so no types-oracle run was needed.
