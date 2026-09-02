# Refinement skip-diagnosis: bucket distribution and promotion audit

Task 8 of the 2026-09-01 refinement-error-diagnosis plan. Measurement only; no
compiler code was changed for this document.

## Apparatus

| | |
|---|---|
| Baseline commit (merge-base `origin/main` HEAD) | `3ba190548d793adcf4dd5ff15d5f72d7c7cb8f47` |
| After commit (branch HEAD at measurement time) | `01c0e4d73f82b81095557d07453efe872386134f` |
| Baseline `bin/main.exe` sha256 | `3540ea4ade6d2722af61395ef297d8c2513734f88642ca37f424b45aa933e6b7` |
| After `bin/main.exe` sha256 | `2b60e3a1830335cb921961866bb7e6bd2b63dbc59493e98aeede6ff3ffbcc02d` |
| Corpus | `stdlib/*.march` (116) + `test/native/*.march` (182) = 298 entry files |
| Files that emitted a report | 298 / 298, on both builds |

`stdlib/` and `test/native/` are byte-identical between the two commits
(`git diff --stat 3ba19054 HEAD -- stdlib/ test/native/` is empty), so both
sweeps ran over the same corpus; only the compiler differs.

### Exact commands

The baseline compiler was built in a throwaway worktree checked out at the
merge-base, not at branch HEAD:

```bash
git worktree add "$SCRATCH/base-3ba19054" 3ba190548d793adcf4dd5ff15d5f72d7c7cb8f47
cd "$SCRATCH/base-3ba19054" && HOME=$SCRATCH/home-base dune build --root . bin/main.exe
```

Each sweep (one foreground process, nothing else compiling concurrently):

```bash
rm -rf .march/cas/artifacts-v2 .march/cas/vc          # once, before the sweep
for f in stdlib/*.march test/native/*.march; do
  echo "===== FILE: $f"
  ./_build/default/bin/main.exe --check --refine-report "$f" 2>&1
done > sweep.txt
```

Environment discipline: every build and every sweep ran under a private `HOME`
inside the session scratchpad (`home-head` / `home-base`), because
`~/.cache/march` is shared across worktrees on this machine and its marshalled
stdlib spans carry the populating worktree's absolute paths. Both caches
(`.march/cas/artifacts-v2` and `.march/cas/vc`) were cleared once before each
sweep and never during one — a warm `artifacts-v2` short-circuits before
`--refine-report` prints anything, which looks like "no skips".

Wall clock: 2m57s (after), 3m00s (baseline).

## Deliverable 1 — bucket distribution, before and after

### Table (a) — `user code` section, summed over the 298 entry files (the clean number)

Each file's `user code` section counts only that file's own obligations, so
this sum counts every obligation exactly once.

| bucket | baseline | after | delta |
|---|---:|---:|---:|
| `unconstrained-subject` | 0 | **41** | +41 |
| `unreflectable-predicate` | 11 | 11 | 0 |
| `solver-undecided` | 59 | **8** | −51 |
| `partial-conjunct` | 0 | **6** | +6 |
| **total skipped** | **70** | **66** | −4 |
| proved | 95 | 95 | 0 |
| violated | 0 | **4** | +4 |
| trusted | 0 | 0 | 0 |
| obligations by kind | 165 pre / 0 post / 0 div | 165 pre / 0 post / 0 div | — |

The accounting closes exactly: the baseline's 59 undiagnosed
`solver-undecided` skips split into 41 `unconstrained-subject` + 8
`solver-undecided` + 6 `partial-conjunct` = 55, plus the 4 skips that became
promotions and are now counted as `violated` (70 − 66 = 4 = the violated
delta).

### Table (b) — `user + stdlib` section, summed over the 298 entry files (INFLATED — do not quote as a corpus count)

Every entry file re-reports every stdlib obligation it transitively pulls in,
so a stdlib obligation is counted once per importing file. This table is
included only to show the same shape holds at scale; it is not a count of
distinct obligations in the corpus.

| bucket | baseline | after | delta |
|---|---:|---:|---:|
| `unconstrained-subject` | 0 | **13375** | +13375 |
| `unreflectable-predicate` | 2973 | 2973 | 0 |
| `partial-conjunct` | 0 | **1782** | +1782 |
| `solver-undecided` | 15465 | **304** | −15161 |
| **total skipped** | **18438** | **18434** | −4 |
| proved | 5432 | 5432 | 0 |
| violated | 0 | 4 | +4 |

### Grouping sanity check

The Task 1 correction requires `--refine-report` to group by cause, not by
payload. Across all 311 report blocks in the after-sweep, **no block repeats a
slug on more than one line** (checked programmatically). The distribution is
measuring what it claims to.

### Is `solver-undecided` still the largest bucket?

**No.** After the change the largest bucket is `unconstrained-subject`
(41 of 66 user-code skips, 62%). `solver-undecided` is now the *third*
largest at 8 of 66 (12%), down from 59 of 70 (84%) at baseline. The same
ordering holds in the inflated `user + stdlib` slice
(`unconstrained-subject` 13375 > `unreflectable-predicate` 2973 >
`partial-conjunct` 1782 > `solver-undecided` 304).

The plan's stop condition ("if `solver-undecided` is still the largest bucket,
the taxonomy is wrong and the three variants need revisiting before Task 9")
is **not** triggered. The residual `solver-undecided` bucket is 12% of user-code
skips, which is the intended shape: a genuine "the solver returned unknown"
remainder rather than an undifferentiated catch-all.

Note on the mid-plan number: a mid-implementation measurement put
`unconstrained-subject` at ~308 and `solver-undecided` at ~301 on per-file
sums. Those were sums over the *inflated* `user + stdlib` slice of a smaller
sample; the final clean user-code numbers above (41 vs 8) supersede them.

## Caveats that must accompany any number quoted from this report

1. **The `violated` total conflates two different verdicts.** A promotion is
   recorded as `Obligation.Violated`, the same verdict the solver emits for a
   contract that can *never* hold; `refine_post` already used `Violated` for
   some-input return failures. So `violated: 4` above means "4 obligations for
   which some input demonstrably fails", not "4 obligations that never hold".
   The report cannot currently distinguish the two shapes.

2. **Promotion is deliberately not attempted at stdlib spans.** Diagnostics at
   spans in `stdlib_files` are filtered out of the printed stream, so a
   promotion there produced an unexplained `violated` count and paid the
   interpreter reachability cost for nothing. The stdlib slice of every report
   therefore reflects the **pre-promotion baseline by design**. The four
   promotions found below are visible only because `stdlib/stats.march` is
   itself an entry file in this corpus — when a module is the entry file its
   own spans are user spans, not filtered stdlib spans. In any normal
   compilation that imports `Stats`, these four sites are silent.

## Deliverable 2 — every promotion, hand-audited

```bash
grep -c "propagates a requirement it doesn't declare" after-sweep.txt   # 4
grep -c "propagates a requirement it doesn't declare" base-sweep.txt    # 0
```

**Total promotions across the corpus: 4. False positives: 0.**

All four are in `stdlib/stats.march` when that file is the entry file — the
same four sites Task 6 identified as true-but-invisible. No other file in the
corpus produced a promotion.

### 1. `median` — `stdlib/stats.march:91`

```
`median` propagates a requirement it doesn't declare.

`percentile` requires  len(_) > 0
but median([]) panics — "Stats.percentile: empty list"

help: declare what `median` actually needs —
        fn median(xs : {List(Float) | len(_) > 0}) : Float
```

`fn median(xs : List(Float)) : Float do percentile(xs, 50.0) end`
(line 90–92). `percentile` is declared
`fn percentile(xs : {List(Float) | len(_) > 0}, p : {Float | _ >= 0.0 && _ <= 100.0})`
and its body's first match arm is `Nil -> panic("Stats.percentile: empty list")`.

**Genuine.** `median` is public, its parameter is unrefined, so `median([])`
is callable and reaches the `Nil` arm. `50.0` satisfies the `p` precondition,
so `len(_) > 0` is the only requirement `median` fails to forward.
**Suggested signature correct** — same name, arity and result type, the one
missing refinement added; declaring it removes the panic by making `median([])`
a type error at the caller.

### 2. `quantile_default` — `stdlib/stats.march:271`

```
`quantile_default` propagates a requirement it doesn't declare.

`quantile` requires  len(_) > 0
but quantile_default([], 0.0) panics — "Stats.quantile: empty list"
```

`fn quantile_default(xs : List(Float), q : Float) : Float do quantile(xs, q, Linear) end`
(line 270–272). `quantile` is declared
`fn quantile(xs : {List(Float) | len(_) > 0}, q : {Float | _ >= 0.0 && _ <= 1.0}, method : QuantileMethod)`
with `Nil -> panic("Stats.quantile: empty list")`.

**Genuine.** `quantile_default([], 0.0)` reaches the `Nil` arm; the witness
`q = 0.0` satisfies `quantile`'s `q` precondition, so the reported panic is
exactly the one attributed.

**No `help:` signature was offered for this one** (verified by reading the
full diagnostic block, not a truncated grep window). This is a *gap*, not a
false positive: the claim made is true and no wrong signature is proposed.
The likely cause is that `quantile` has a *second* unforwarded precondition
(`q : {Float | _ >= 0.0 && _ <= 1.0}`, separately reported as an
`unconstrained-subject` hint on the same line 271), so no single-parameter
suggestion is unambiguously correct here. The other three promotions, whose
callees have exactly one unforwarded precondition, all carry a `help:`.
Worth filing as a follow-up (suggest the multi-parameter signature, or say
explicitly why no fix is offered); it does not block shipping.

### 3. `iqr` — `stdlib/stats.march:298`

```
`iqr` propagates a requirement it doesn't declare.

`quantiles` requires  len(_) > 0
but iqr([], InvertedCdf) panics — "Stats.quantiles: empty list"

help: declare what `iqr` actually needs —
        fn iqr(xs : {List(Float) | len(_) > 0}, method : QuantileMethod) : Float
```

`fn iqr(xs : List(Float), method : QuantileMethod) : Float` calls
`quantiles(xs, [0.25, 0.75], method)`; `quantiles` is declared
`fn quantiles(xs : {List(Float) | len(_) > 0}, qs : List(Float), method : QuantileMethod)`
with `Nil -> panic("Stats.quantiles: empty list")`.

**Genuine.** The `Nil` arm is reached before `qs` is ever inspected, so the
witness `InvertedCdf` for `method` is immaterial and the panic string matches.
**Suggested signature correct** — both parameters preserved in order, only
`xs` refined.

### 4. `std_dev` — `stdlib/stats.march:400`

```
`std_dev` propagates a requirement it doesn't declare.

`variance` requires  len(_) > 0
but std_dev([]) panics — "Stats.variance: empty list"

help: declare what `std_dev` actually needs —
        fn std_dev(xs : {List(Float) | len(_) > 0}) : Float
```

`fn std_dev(xs : List(Float)) : Float do math_sqrt(variance(xs)) end`
(line 398–401). `variance` is declared
`fn variance(xs : {List(Float) | len(_) > 0}) : Float` with
`Nil -> panic("Stats.variance: empty list")`.

**Genuine.** `std_dev([])` reaches the `Nil` arm; `math_sqrt` is never
entered. **Suggested signature correct.**

### Audit summary

| # | function | callee | genuine latent panic? | `help:` offered? | signature correct? |
|---|---|---|---|---|---|
| 1 | `median` | `percentile` | yes | yes | yes |
| 2 | `quantile_default` | `quantile` | yes | **no (gap)** | n/a |
| 3 | `iqr` | `quantiles` | yes | yes | yes |
| 4 | `std_dev` | `variance` | yes | yes | yes |

Every panic message quoted in a promotion matches the literal `panic(...)`
string in the callee's `Nil` arm, and every promoted caller declares an
unrefined `List(Float)` parameter that a caller can legitimately instantiate
with `[]`. **Zero false positives.**

## Verdict

**SHIP.**

- The promotion count is 4 corpus-wide, all in one module, all hand-verified
  genuine. The reachability gate is not firing broadly; 0 false positives, so
  the stop-ship gate is not triggered.
- `solver-undecided` is no longer the largest bucket (8 of 66 user-code skips,
  down from 59 of 70). The taxonomy stop condition is not triggered and
  Task 9 may proceed.
- No obligation changed classification other than the intended split: `proved`
  is unchanged at 95 (user) / 5432 (user+stdlib), and total skipped fell by
  exactly the 4 promotions.

Two follow-ups, neither blocking:

1. `--refine-report` should distinguish "never holds" from "some input
   demonstrably fails" in the `violated` count (caveat 1 above).
2. `quantile_default` gets a true promotion with no `help:` signature because
   its callee has two unforwarded preconditions (audit item 2).

## Task 9 — oracle classification and the CI-only gates

### `refine-oracle`: RED proof first

`scripts/refine-oracle.sh` was expected to move on this branch (hint text
changed on nearly every skip, `--refine-report` slugs regrouped, four
promotions appeared), so it is not a pass/fail gate here.  An oracle that
cannot go red proves nothing either way, so its sensitivity to a *verdict*
change — not merely to text — was established before the real diff was read.

Baseline recorded from the merge-base `3ba190548d793adcf4dd5ff15d5f72d7c7cb8f47`
built in a throwaway worktree under the session scratchpad:
**5476 report lines over 298 fixtures**.

| build | report lines | vs baseline |
|---|---:|---|
| baseline `3ba19054` | 5476 | — (recorded) |
| branch HEAD | 6512 | 1710 differing lines |
| branch HEAD + deliberate perturbation | 5036 | **1080 differing lines** |

The perturbation was one line in `lib/refinecheck/refine_call.ml`: the
precondition discharge was forced to `Refine.Verified`, so every obligation is
noted `Proved`.  It produces a diff that is different from the branch's own
(1080 lines, and a report-line total 1476 lines *below* the branch's), which is
the RED evidence: the oracle discriminates verdicts, not just message text.
The perturbation was reverted (`git checkout lib/refinecheck/refine_call.ml`,
tree clean) and the compiler rebuilt before any other measurement.

### Classification of all 1710 moved lines

Every moved line was assigned to exactly one category, computed
programmatically over the diff rather than by eye.

| category | lines | what it is |
|---|---:|---|
| **A — expected text change** | **439** | 409 added lines of per-site diagnosed hints (40 `-- HINT --` headers, 40 `precondition … was NOT verified here.`, 41 `nothing in scope constrains …`, 6 partial-conjunct lines, 2 `reason:` lines, plus their source snippets, carets and blanks) and 30 removed lines of the canned residual paragraph they replace (9 `reason: solver-undecided`, 21 lines of the three-line `note: March reports only definite failures…` block over 7 modules) |
| **B — expected regroup** | **1211** | `--refine-report` bucket lines: 902 added (`unconstrained-subject` 308, `partial-conjunct` 299, `solver-undecided` 295) against 305 removed `solver-undecided` lines, plus the 2 added / 2 removed `refinement obligations (…)` summary lines, which move in exactly one fixture (`stdlib/stats.march`, where 4 skips became violations) |
| **C — intended promotion** | **60** | the four `-- WARNING --` blocks in `stdlib/stats.march` audited in Deliverable 2: 4 headers, 4 `propagates a requirement it doesn't declare`, 4 `requires`, 4 `but … panics`, 3 `help: declare what` + 3 signature + 3 `` `forge fix` can apply this. `` (the fourth, `quantile_default`, carries no `help:` — the gap recorded above), plus the blocks' own snippets, carets and blanks |
| **none** | **0** | — |

439 + 1211 + 60 = 1710.  A shape tally over the added lines returned zero
`OTHER` lines, and `grep -c opaque-application` over the diff is **0**, as
expected: that variant fires nowhere on this corpus.

Only `stdlib/stats.march` gained `-- WARNING --` lines, confirming that
promotion did not fire anywhere else in 298 fixtures.

### Gates the local alcotest suite does not reach

| gate | result |
|---|---|
| `scripts/run-tests.sh` (FULL, not `-q`) | all 11 suites passed — **3177 tests run, 0 FAIL**, 4 `[SKIP]` (3 `cap_sandbox_runtime` linux-only, 1 `adversarial-regressions` `MARCH_SANITIZE`-gated; none z3-related) |
| `./_build/default/test/test_refinecheck.exe -e` | **588 `[OK]`, 0 SKIP, 0 FAIL** in 271s |
| `dune build --root . @types-check --force` | **303 passed, 0 failed** (log 25508 bytes — asserted non-empty; the check is vacuous and zero-byte without `--force`) |
| `dune build --root . @grammar-check --force` | **48 passed, 0 failed** (log 3309 bytes) |
| `scripts/check-docs.sh` | passed (checks A, B, C all ok) |

Both dune rules pin diagnostic TEXT, which this branch rewrites, so they are
the real risk here; neither moved.

**Apparatus note worth recording:** `scripts/run-tests.sh` does **not** run
`test/test_refinecheck.exe`.  Its suite list is
`compiler eval codegen stdlib stdlib_march test_jit lsp utf16 jsonrpc
incremental query_cli`, and the run's own banner lines confirm
`march-refinecheck` is not among the eleven Alcotest runs it launches.  The 588
refinement cases — the ones this whole branch is about — therefore have to be
invoked directly, exactly like `@types-check`/`@grammar-check`.  A green
`run-tests.sh` alone would have said nothing about them.  `.march/cas/vc` was
cleared once before the run (a warm VC cache lets a checker that stopped
checking still "prove").
