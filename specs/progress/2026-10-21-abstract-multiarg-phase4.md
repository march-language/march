Refinements: `Map.filter` carries an assumed two-argument entry fact (multi-arg design phase 4)

Phase 4, the last phase of `specs/2026-10-18-abstract-refinements-multi-arg-design.md` (§1.2,
§4.2 step 2, §7, §9 "Phase 4"; user decision D1: `@[assume]` with a runtime property witness).
Phases 1a-3 (`d053b4bdb`, `eedd5a35f`, `38635a08f`, `0f99036c3`) built the relational entry,
the long-form two-argument `p` and the sugar. This phase gives `@[assume]` a meaning on an
element return and puts it on `Map.filter`.

## Before / after (the design's §0 rows, measured)

`need_vals : Map(String, {Int | _ > 0})`, `need_ivals : Map(Int, {Int | _ > 0})`,
`need_keys : Map({Int | _ > 0}, String)`, `need_rel : Map({x : Int | true}, {y : Int | y > x})`.

| Row | Program | Before (`0f99036c3`) | After |
|---|---|---|---|
| m1 | `need_vals(Map.filter(m, fn _k -> fn v -> v > 0, Map.str_cmp))` | skip, `parametric-source-unproved` | proved |
| m2 | `need_keys(Map.filter(m, fn k -> fn _v -> k > 0, Map.int_cmp))` | skip, same | proved |
| m3 | `need_rel(Map.filter(m, fn k -> fn v -> v > k, Map.int_cmp))` | skip, same | proved |
| m4 | `… fn _k -> fn v -> v >= 0 …` into `need_vals` | skip, same | skip, `abstract-refinement-too-weak` ("`fn _k -> fn v -> v >= 0` does not imply `_ > 0`") |
| m5 | `… fn k -> fn v -> k > 0 && v > k …` into `need_ivals` | skip, same | proved (projection) |
| m6 | `… fn k -> fn v -> v > k …` into `need_ivals` | skip, same | skip, too-weak |
| m7 | `… fn _k -> fn v -> v > now …` | skip, same | skip, `abstract-refinement-uninstantiated` |
| m8 | `let m2 = Map.filter(…)` then `need_vals(m2)` | skip, `unreflectable-subject` | proved |
| m9 | `need_vals(m)`, `m` refined | proved | proved (unchanged) |
| m10 | `need_vals(Map.insert(m, "b", 5, …))` | skip, `parametric-source-unproved` | unchanged (filed) |
| m12 | `cap verified`, `Map.size(Map.filter(m, fn k -> fn v -> v > k, …))` | accepted, 0 obligations | accepted, 0 obligations |

## What changed

- `lib/refinecheck/refine_param.ml`:
  - `elem_ret_assumed`, a table beside `elem_ret_proved` (reset with it);
  - `p1_ok`: P1 alone (`generic_in_inferred`, no bound on the variables), the gate for an
    assumed callee.
- `lib/refinecheck/refine_check.ml`:
  - `gate_elem_returns`: an `@[assume]` function with an element return (`has_elem_return`,
    read under its own abstract refinements, so slots, rels and abstract applications all
    count) goes into `elem_ret_assumed` and is no longer a proof candidate.
  - `visit_fn`: for such a function (`assumed_elem_return`), one `Trusted` postcondition per
    entry is recorded at the function name (predicate `entry_pred_str`: the entry's slot facts
    and relations joined, e.g. `p($s0, $s1)`), and the clause's element demand is `None`, so no
    tail is walked for it. The `@[assume] has no effect` warning no longer fires for an assumed
    function whose only refinement is an element return.
  - Consumers:
    - `declared_elem_return`: a new arm for an assumed key, closed entries free of the callee's
      abstracts only (no relational lend).
    - `abstract_flow` (arity 1) and `abstract_flow_n` (arity n): the gate accepts
      `elem_ret_proved || elem_ret_assumed`. For an assumed (not proved) callee the parametric
      gate is `p1_ok` instead of `parametric_ok`, and the conjunction with the input's entry
      (§4.2 step 4) is declined. For arity n the existing "`m`'s own element facts are not
      carried through `Map.filter`" note then names the input.
- `stdlib/map.march` `Map.filter`:
  `@[assume] fn filter(m : Map(k, v), pred : k -> v -> Bool[p], cmp : k -> k -> Bool) : {Map(k[p],
  v[p]) | subset(keys(_), keys(m))}`. The container predicate is kept. The `doc` paragraph now
  adds that the checker also assumes every entry satisfies `pred`. The body is unchanged.
- No other stdlib function is affected. No `@[assume]` function in `stdlib/` or `test/native`
  had an element return before (checked by listing every assumed return type), so no proof
  candidate was removed from `gate_elem_returns`.

## Tests

New group `abstract-map` in `test/test_refinecheck.ml`, 19 cases, registered after
`abstract-multiarg-sugar`. Each case typechecks and refine-checks a user module beside the
REAL `stdlib/list.march`, `stdlib/map.march` and the prelude (the leftovers-d harness shape),
so P1 reads a real `type_map`. RED: the final test file was built and run in a worktree of the
base `0f99036c3` (base compiler, base stdlib): `14 failures! in 0.355s. 19 tests run.` The five
passing there are controls or unchanged rows by design (m9, m10, m12, and controls 16 and 18).

| # | Case | RED on base (Expected → Received) |
|---|---|---|
| 0 | m1 | `[proved]` → `[(skipped, parametric-source-unproved)]` |
| 1 | m2 | same |
| 2 | m3 | same |
| 3 | m4, detail names the lambda and `_ > 0` | `[too-weak]` → `[parametric-source-unproved]` |
| 4 | m5 | `[proved]` → `[parametric-source-unproved]` |
| 5 | m6 | `[too-weak]` → `[parametric-source-unproved]` |
| 6 | m7 | `[uninstantiated]` → `[parametric-source-unproved]` |
| 7 | m8 | `[proved]` → `[(skipped, unreflectable-subject)]` |
| 8 | m9 (the subtyping obligation is labelled `m`) | passes on base (unchanged row) |
| 9 | m10 control: `Map.insert` carries nothing | passes on base (out of scope, pinned) |
| 10 | a refined input through `fn _k -> fn v -> v < 100` into `need_band`: too-weak, detail "`m`'s own element facts are not carried through `Map.filter`" | `[too-weak]` → `[parametric-source-unproved]` |
| 11 | m12, plus the `cluster_node` shape `fn _a -> fn until -> until > now`: under `cap verified`, no error, 0 user obligations | passes on base (pin) |
| 12 | `cap verified`: m3 leaves nothing unverified | `[]` → one "cannot verify element refinement `true` on `need_rel` (parametric-source-unproved…)" |
| 13 | `cap verified` control: m6 is an `abstract-refinement-too-weak` error | `true` → `false` (base: the parametric-source error) |
| 14 | `assumed_counted`: Map.filter's postconditions are exactly `[(trusted, subset(keys(_), keys(m))); (trusted, p($s0, $s1))]`, and no `return of filter` obligation in `map.march` | `[…two…]` → `[(trusted, subset(keys(_), keys(m)))]` |
| 15 | an assumed callee failing P1 (unannotated `m`) is uninstantiated, "is not known to be parametric" | detail: base says "`afilt`'s own body is not proved …" |
| 16 | control: same signature, no `@[assume]`, body `m`: uninstantiated, "own body is not proved" | passes on base (control) |
| 17 | `@[assume] fn pos_map() : Map(String, {Int | _ > 0})`: `pos_map()` into `need_vals` proved, user ledger (1 proved, 1 trusted), no "has no effect" warning | `[proved]` → `[]` |
| 18 | control: the same without `@[assume]` is recorded and not proved | passes on base (control) |

Every accept row has a skip or error control: m4/m6/m7, case 10, case 13, 15, 16 and 18.

**Runtime witness.** `test/stdlib/test_map.march`, describe "assumed keys contracts (runtime
witnesses)": "every entry Map.filter keeps satisfies pred (the assumed entry fact)". Over
`Gen.tuple2(Gen.list(Gen.tuple2(Gen.int(-20, 20), Gen.int(-20, 20))), Gen.int(-10, 10))` it
builds `Map.from_list(pairs, int_cmp)`, filters with `fn k -> fn v -> v > k + t` and checks every
entry of `Map.to_list` satisfies `v > k + t` (a helper `above`; a `match` with a tuple arm inside
the `List.all` lambda was a parse error). The existing filter tests (the unit test and the
`keys, map_values, filter and merge` property) are unchanged. Perturbation: `if p(v)` inverted to
`if !p(v)` in `stdlib/map.march`, restaged, `march test test/stdlib/test_map.march`:

```
FAIL: "filter filter keeps entries matching predicate"  (left: 1, right: 2)
FAIL: "assumed keys contracts (runtime witnesses) every entry Map.filter keeps satisfies pred (the assumed entry fact)"
  error: panic: property failed after 2 run(s)
  counterexample: ([(0, 0)], 0)
  shrunk 3 step(s) from: ([(18, 2)], 5)
FAIL: "doctest Map.filter (1)"
=== 1/1 file, 3/2427 tests failed ===
```

Restored from a saved copy (`grep -c 'if !p(v)'` = 0), restaged: `=== 1 file, 2427 tests passed ===`.

## Verification

- **Refine oracle.** Baseline at `0f99036c3` before any edit, from a base worktree: 549 fixtures,
  8726 lines. After: `DIAGNOSTICS CHANGED — 2200 differing lines`. Every one of the 1100 pairs
  is accounted for by one rule: every fixture that loads the stdlib gets `+1 trusted` in its
  `user + stdlib` summary and `+1 postcondition` in its `by kind` line (Map.filter's trusted
  entry), and `stdlib_map`'s own `user code` line goes from 12 to 13 trusted. A script applied
  that bump to every `-` line and matched it against the `+` lines; nothing was left over. No
  proved, violated or skip count moved anywhere, including `stdlib_cluster_node` (its
  `Map.filter(st.dialing, fn _a -> fn until -> until > now, …)` has no demand, so it files no
  obligation). The oracle going RED is shown by this run itself.
- **Refine audit baselines** (`test/refine_audit/*.baseline`, group `audit-baseline`) regenerated
  with `UPDATE_SNAPSHOTS=1`. Reason: Map.filter's new signature. Every `user + stdlib` line goes
  from 175 to 180 enforced (550 lines; the holes baseline's one line from 175 to 180 enforced with
  its 1 unenforced unchanged), and `stdlib_map`'s user code from 12 to 17 enforced. The 5 sites
  are the expanded signature's refinements: the definer's two domains and its `{Bool | _ ==
  p($x2, $x)}` codomain, and the return's two slots. All are Enforced; no Inert or Unenforced
  line appeared, and the unenforced ceiling is untouched.
- **Full sweep**, base `0f99036c3` vs branch, each under its own private `HOME`, `--check
  --refine-report --refine-report-sites`:
  - `stdlib` and `test/native`: covered by the oracle above.
  - `test/stdlib` (115 files), conduit `lib` (45 files, `MARCH_LIB_PATH` = conduit/lib) and
    depot `lib` (32 files, `MARCH_LIB_PATH` = conduit/lib:depot/lib): 77 ecosystem files.
  - Diff: 1536 lines, 384 pairs, all of them the same `+1 trusted` / `+1 postcondition` bump.
    No skip turned into a violation and no verdict changed.
  - Conduit: every one of its 45 files reports module-resolution errors (`Pool`, `Message`, `Db`,
    `Connection` not found) and a `cap_ceiling` error (`Conduit.Dashboard` uses `IO.NetListen`),
    identically on base and branch. They are unrelated and pre-existing, and the refine report
    still prints for each. Neither conduit nor depot calls `Map.filter`.
- **Budget (§10).** Cold `--check --stdlib-source --refine-report`, with
  `.march/cas/{artifacts-v2,vc}` cleared and a fresh `HOME` every run, 5 interleaved A/B runs,
  base = the `0f99036c3` worktree.
  - `stdlib/map.march`: base median 1.368 s, branch 1.374 s, 100.4%.
  - `stdlib/list.march`: base median 1.317 s, branch 1.313 s, 99.7%.
  - Load average was 4.07 before and 3.95 after. Both are within the 110% budget.
- `scripts/check-docs.sh`: `doc-lint passed`.
- Targetless `dune build --root .`: exit 0 (stdlib restaged).
- Full `scripts/run-tests.sh` (z3 on PATH): `All suites passed.`, exit 0. refinecheck `1481 tests
  run` (1462 + 19); compiler 1451 (the stdlib ratchet), eval 289, codegen 719, run_stdlib 896,
  stdlib_march 80, jit 43, lsp 383 + 5 + 37 + 10 + 8, errors 290.

## Rulings

- Ruling: the audit counts the assumed entry's sites as Enforced, not as a new "trusted" bucket.
  Why: the audit has no trusted bucket (Enforced / Inert_warned / Unenforced). The existing
  precedent is an `@[assume]`d scalar return, which it classifies Enforced ("counted under
  `trusted`, and never a hole"). The trusted count lives in the ledger (`--refine-report`).
  Cost if wrong: adding a bucket changes the audit's output format and the CI ratchet's parser.
- Ruling: one `trusted` postcondition per ENTRY, recorded at the function name with the entry's
  slot facts and relations as its predicate (`p($s0, $s1)` for Map.filter). This is on top of the
  existing trusted line for the container-level predicate, so Map.filter has two. Cost if wrong:
  ledger text.
- Ruling: an assumed callee is never conjoined with its input's entry (§4.2 step 4), at either
  arity. Why: the conjunction claims the result's elements are the input's, which is the body's
  parametricity (P2). The assumed contract states only the produced entry. For `Map` it never
  applied anyway (F4). Cost if wrong: a lost proof for a future assumed generic `List`
  combinator.
- Ruling: `declared_elem_return` lends an assumed entry only when it is closed. It does not lend
  one relational over the parameters (the `relational ~formals` path a proved entry takes).
  Why: the brief says closed, non-abstract entries; a relational lend reads the contract at the
  actuals, a claim no proof backs. Cost if wrong: a lost fact for an assumed `{List({Int | _ <=
  n})}`-style return.
- Ruling: `declared_tuple_return` and the structural self-call hypothesis do not read
  `elem_ret_assumed`. Why: they are not named consumers in §7.2, and the hypothesis exists to
  prove a body that is not walked here. Cost if wrong: a lost fact for an assumed tuple return
  (none exist).
- Ruling: the arity-1 `abstract_flow` takes the assumed gate too, not only `abstract_flow_n`.
  Why: §7.2 says "abstract applications", whatever the arity. No arity-1 `@[assume]` combinator
  exists, so nothing moves today (oracle). Cost if wrong: none observable.
- Ruling: `@[assume]` on a function whose only refinement is an element return no longer warns
  "has no effect". Why: it now assumes the entry. Cost if wrong: none.
- Ruling: the reference's "Only four combinators" is now a list of thirteen (the item had grown
  since the design was written). `Map.filter` was added to it rather than the count being bumped
  to five. No `(k, v) -> Bool` spelling remained in `specs/lang/refinement-types.md`. The one in
  the closed todo is corrected in that file's closing note. Cost if wrong: wording.

## Bookkeeping

- `specs/todos/2026-09-20-abstract-refinements-multi-arg-callbacks.md` was moved (`git mv`) to
  `specs/progress/`, with a closing note. The fold sibling had already dropped its `fold_left`
  bullet, and only `Map.filter` remained.
- Filed (§8, phase 4):
  - `specs/todos/2026-10-21-map-element-flow-through-combinators.md` (m10/m11);
  - `…-hashmap-filter-two-argument-abstract.md`;
  - `…-ordered-map-filter-two-argument-abstract.md`;
  - `…-tuple-elements-list-of-pairs-abstract.md`.
- `specs/todos/2026-10-21-abstract-curried-two-step-call-no-fact.md`: one sentence updated (a
  curried lambda now also instantiates an assumed return).
- Docs: `specs/lang/refinement-types.md` was edited and regenerated with
  `scripts/gen-lang-docs.py`:
  - a "`Map.filter` carries it, assumed" paragraph;
  - the combinator list;
  - the Set-Refinements `Map` paragraph;
  - "`Map.filter` does not carry it yet" is replaced by a bullet on `Map`'s other functions.

  The generated stdlib API HTML is bot-owned and was not regenerated.
