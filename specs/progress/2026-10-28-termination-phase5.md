Termination checking, phase 5: metric inference

Design: `specs/2026-10-26-termination-checking-design.md` §3.5, §8 phase 5 and §9;
decisions D1-D6. On top of phase 4 (`specs/progress/2026-10-27-termination-phase4.md`).
The rulings of phases 0-4 stand.

A recursive cycle that no certificate covers is searched for a metric. A metric is
proposed only when every phase-2 obligation of the cycle proves with it; nothing is
trusted, and nothing feeds a verdict or the induction hypothesis until the user writes it.
The search runs only under `--refine-infer` (and `forge refine --infer`) or
`--termination-report`.

## What changed

- **`Refine_term.candidates` (§3.5).** For SCC `si`, at most `max_candidates` (8) metric
  candidates, in order:
  1. each `Int` parameter, in parameter order;
  2. `b - i` for an `Int` parameter `i` passed as `i + k` (k a positive literal) at some
     intra-SCC call, and a comparison of `i` with `b` anywhere in the body, where `b` is a
     literal or built (inside the §2.1 fragment) from parameters EVERY intra-SCC call passes
     unchanged: `i < b` / `i >= b` give `b - i`, `i <= b` / `i > b` give `b - i + 1`. Also
     `len(x) - i` for such an `i` and a `List`/`String` parameter `x` passed unchanged,
     with or without a comparison (the `scanner` row);
  3. `len(x)` for a `List` parameter;
  4. 2-tuples of the above, the first component's parameter before the second's.

  Shapes are read from the SCC's first member and instantiated BY POSITION for every
  member; a member lacking the position (or its kind) drops the candidate. Every
  instantiated metric must pass `metric_errors` (the §2.1 fragment). The metric phase 2
  already checked (`pl_metric`: the default or the written one) is dropped, and so is a
  duplicate. The function returns the first 8 and the total.
- **`Refine_term.plan_metrics ?override`.** For an SCC the override answers, the given
  metric of each member is obliged exactly as a written `@[decreases]` would be (the
  edge-filing body is now the local `file_metrics`, shared by both paths, unchanged).
- **`Refine_check.infer_metrics`.** Rounds `k = 0..7`: the `k`-th candidate of every open
  target is planned with `override`, its obligations are discharged in ONE scratch walk
  of the top-level functions holding those SCCs, and `Refine_term.finish` decides each.
  A candidate is accepted only on `metric`: every obligation reached and `Proved`
  (`trusted` is not accepted). The scratch walk is phase 3's, factored out of
  `ih_prepare` as `term_scratch_walk` with no change of behaviour (the IR and refine
  oracles below are identical).
- **`check_module`**, after the phase-2 certificates and before `report_termination`:
  when `Refine_term.infer` is set, every SCC whose certificate is `unproved:<r>` for a
  reason a metric could fix (not `reference`, `non-positive`, `unresolved`,
  `invalid-decreases`) and with a member in user code (or, under `--refine-infer`, one
  `Refine_term.infer_demand` accepts) is searched. Results go to
  `Refine_term.last_inferred` / `last_inferred_exprs`.
- **`Refine_term.suggest_metric`** (phase 4's frame) now answers the inferred metric of a
  one-function, top-level cycle, so the `termination_unproved` text ends with
  `note: try `@[decreases(e)]`.`, which the LSP turns into the "Add `@[decreases(e)]`"
  action.
- **`--termination-report`** sets `Refine_term.infer`. It prints, after the rows, one
  `infer\t<site>\t<name>\t@[decreases(e)]|none\t<k> of <n> candidates checked[; the cap of
  8 was reached]` line per searched unit, and `  inferred: N of M uncertified units`.
- **`--refine-infer` (`Refine_infer.run ?decreases ?applicable_decreases`).** After the
  refinement fixpoint, `infer_decreases`:
  1. runs a real `check_module` of the hypothesis tree with inference on and every SCC
     holding a target unit demanded;
  2. turns the results into `dproposal`s (`d_apply`: `None`, `local`, `written` or
     `apply-by-hand`; a cycle is written whole or not at all) and `dnone`s;
  3. writes every applicable proposal into the tree and checks the module AGAIN with
     inference off. A proposal stands only if that re-check certifies its cycle
     `metric`; one that does not is dropped and its cycle listed as `none`. The re-check's
     user ledger replaces `after` / `after_counts`, so `--refine-infer-apply`'s prediction
     includes any proof the induction hypothesis gains from the new metric.

  The driver prints an `inferred metrics:` block (only when there is something to say),
  JSON v1 gains `decreases` / `decreases_none` arrays (only when non-empty), and
  `--refine-infer-apply` / `-diff` insert `@[decreases(e)] ` before the `fn` / `pfn`
  keyword on the declaration's own line (`Refine_edit.insert_fn_attribute`).
  `--refine-infer-kinds` gains the kind `decreases`; a list without it infers no metric.
- **LSP**: the phase-4 frame now fires from real diagnostics; two new cases.
- **Docs**: `specs/lang/refinement-types.md` "Inferring a metric" (new), the metric
  order paragraph, the inference kinds table, `--refine-infer-kinds`, "Editor repairs";
  `scripts/gen-lang-docs.py` rerun. `docs/tooling.md` (hand-written, not generated):
  `forge refine --infer` now also proposes `@[decreases]`. Flag help in `bin/main.ml`
  and `forge/bin/main.ml`. CHANGELOG `### Added`.
- New todo `specs/todos/2026-10-28-termination-infer-gaps.md`.

## Tests (group `termination-infer`, 20 cases; LSP `termination code actions`, 6)

Every RED-table row of §8 phase 5 is implemented, plus REJECT controls.

RED first: a stub build whose `candidates` returns nothing (`stub-no-phase5`) fails 15 of
the 18 cases then written (the RI-level REJECT case was added later, below). The three
that pass are controls (the stdlib `Json.skip_ws`, the diverging functions, default-off).
First failing line:

```
FAIL up inferred
   Expected: `"100 - n"'
   Received: `"none"'
```

Then each rule under one perturbation (`perturb.py` in the session scratchpad, not
committed: one edit, rebuild, run the group, restore):

| Case | Asserts | Perturbation | First failing line |
|---|---|---|---|
| t2 guarded | `up(n + 1)` with `n >= 100`: `100 - n`, 1 of 1 candidate | `no-guard` | `FAIL up inferred` / `Received: "none"` |
| guard over parameters | `count_to(i + 1, hi)`: `hi - i` | `no-guard` | `FAIL count_to inferred` / `Received: "none"` |
| t8 ack | `(m, n)` | `no-pairs` | `FAIL ack inferred` / `Received: "none"` |
| mutual | `ping`/`pong`: `10 - n`, `10 - k` (one shape, two members) | `no-guard` | `FAIL ping inferred` |
| `chunks` | `chunks/go` (local, class G) through `pop_front`'s post: `len(lst)`; top-level `walk` too | `no-len` | `FAIL chunks/go inferred` / `Received: "none"` |
| `scanner` | `skip_ws(s, i + 1)` with a byte exit: `none`, 1 of 1 candidate, named on its report line | `no-scan` (`(0, 0)` checked); `unchecked` | `Expected: (1, 1) Received: (0, 0)`; `Received: "len(s) - i"` |
| `scanner`, contract | the same over a reader with an assumed contract: `len(s) - i` | `no-scan` | `Received: "none"` |
| `scanner`, stdlib | the real `Json.skip_ws`: `none` | `unchecked` | `FAIL Json.skip_ws inferred` / `Received: "len(s) - i"` |
| `cap` | 10 `Int` parameters, only the last falls: `none`, 8 checked, more generated, "the cap of 8 was reached" | `no-cap` | `FAIL f inferred` / `Received: "p9"` |
| `cap` control | 9 parameters: `p8`, the eighth | `tried-kept` | `Received: "none"` |
| REJECT: diverging | `spin`, `up` (`== 100`), `down`, `grow`, `lex_diverging`: `none` | `unchecked` | `FAIL f inferred` / `Received: "m"` |
| REJECT: not decreasing | `up2(n + 2) - up2(n - 1)`: `100 - n` checked and not proposed | `unchecked`; `no-guard` | `FAIL up2 inferred` / `Received: "100 - n"` |
| `proposal_checked` REJECT | `--refine-infer` on `up2`, `spin`, `up ==`, `down`: no proposal, listed as none | `unchecked+no-confirm` (green under `unchecked` alone: the re-check drops it) | `FAIL up back: no proposal` / `Received: ["up2 @[decreases(100 - n)]"]` |
| `proposal_checked` | `--refine-infer` proposes exactly `up`, `ack`, `ping`+`pong`, `walk`; each written with the driver's edit and re-checked: `cert=metric`, every Termination obligation proved, no warning | `no-pairs`; `no-len` | `FAIL ack: proposals` / `Received: []` |
| local | `chunks/go`'s proposal is `local`, never written | `stub-no-phase5` | `FAIL no proposal for chunks/go` |
| report | `infer … up @[decreases(100 - n)] 1 of 1 candidate checked`, `inferred: 1 of 2 uncertified units` | `tried-kept` | `2 of 2 candidates checked` |
| default off | no flag: nothing searched, with or without the report demand | `default-on` | `FAIL nothing recorded` / `Expected: 0 Received: 1` |
| note | a failing `@[decreases(n)]` on `up`: `note: try `@[decreases(100 - n)]`.`; none without the flag | `no-note`; `default-on` | `FAIL the note`; `FAIL no note without the flag` |
| LSP | the action from the real (cap total) diagnostic, and replacing a failing `@[decreases(n)]`; each applied and re-checked clean; a plain `--check` offers none | — (phase 4's frame test kept) | — |

`unchecked` (accept the first candidate without checking) is the perturbation the brief
names. It turns 10 cases RED, among them both REJECT controls. Against `--refine-infer`
it is caught a second time by the re-check (the RI-level REJECT case stays green); only
`unchecked+no-confirm` turns that one RED.

GREEN: `termination-infer` 20/20 (the IH-prediction case below was added last, RED under
`ledger-prediction`: `Expected (0, 0) Received (2, 0)`); every `termination-*` group; LSP 6/6.

## Measurements

### What inference certifies

Inference was run over the WHOLE standard library as one unit (an entry naming all
135 modules, `--check --refine-infer --refine-infer-stdlib --refine-infer-kinds
decreases`) and over each of the 417 `test/native` files as its own entry
(`--refine-infer-json --refine-infer-kinds decreases`, user code only). A "target" is a
recursive unit whose phase-2 certificate is `unproved:<r>` for a reason a metric could
fix (structural, `diverges`, `reference`, `non-positive`, `unresolved` and
`invalid-decreases` cycles are never searched). Every proposal below passed the scratch
check AND, where it is writable, the real re-check with it written.

| | targets (units) | certified by inference | not inferred | of which: 0 candidates / cap reached |
|---|---|---|---|---|
| stdlib | 315 | **27** (27 SCCs; 18 writable, 9 local `fn`s) | 288 | 153 / 13 |
| test/native | 203 | **78** (78 SCCs; all writable) | 125 | 38 / 8 |

By the §0.5 classifier's class (the classifier emits A-F and `?`; G and H were hand
classes in §0.5 and appear here as `?` or `A`):

| class | stdlib certified / not | test/native certified / not |
|---|---|---|
| B (Int metric, a guard bounds it) | **21** / 51 | **75** / 20 |
| C (no bound on the path) | 0 / 51 | 0 / 79 |
| D (lexicographic) | **2** / 1 | 0 / 0 |
| A (structural by syntax, uncertified) | **2** / 38 | 0 / 7 |
| `?` (no syntactic metric) | **2** / 118 | **3** / 14 |
| E (event loop, on the allow list) | 0 / 18 | 0 / 5 |
| F (through a lambda) | 0 / 11 | — |

By hand, the stdlib `?`/`A`/D proposals are: G (a `len` that falls through a rebuilt or
merged list) `Sort.enforce_invariants`, `Toml.update_last_aot`, `Enum.frequencies/go`;
D (two lengths, lexicographic) `List.sort_by/merge/go`, `Sort.merge_sorted/go`,
`BigInt.add_digits/go`. Class C gets nothing, as it should: a C unit diverges on some
input (or needs a builtin contract), so no metric over its parameters can be proved.
Class H gets nothing either: no candidate reads a step variable.

The stdlib proposals (NOT applied, per the brief):

```
String.decode_go          string.march:566          @[decreases(n - i)]
HttpClient.handle_redirects http_client.march:456   @[decreases(max - count)]
Sort.enforce_invariants   sort.march:468            @[decreases(len(stack))]
Parser.lit_matches        parser.march:86           @[decreases(n - k)]
Parser.repeat_go          parser.march:246          @[decreases(n)]
Parser.line_col_go        parser.march:938          @[decreases(target - i)]
Toml.reposition_go        toml.march:91             @[decreases(j - k)]
Toml.digits_to_int_go     toml.march:404            @[decreases(len - i)]
Toml.update_last_aot      toml.march:843            @[decreases(len(path))]
Xml.reposition_go         xml.march:95              @[decreases(j - k)]
Yaml.reposition_go        yaml.march:92             @[decreases(j - k)]
ConsistentHash.add_replicas consistent_hash.march:63 @[decreases(replicas - i)]
Regex.eclose_from         regex.march:221           @[decreases(m - i + 1)]
Regex.nfa_loop            regex.march:294           @[decreases(slen - pos)]
Regex.eclose_run          regex.march:356           @[decreases(m - st + 1)]
Regex.nfa_find_loop       regex.march:423           @[decreases(slen - pos)]
Gen.filter_attempt        gen.march:474             @[decreases(tries)]
ShellRender.escape_go     shell_render.march:44     @[decreases(stop - i)]
List.sort_by/merge/go     list.march:790            @[decreases(len(l), len(r))]   (local)
Sort.merge_sorted/go      sort.march:113            @[decreases(len(l), len(r))]   (local)
BigInt.add_digits/go      bigint.march:81           @[decreases(len(xs), len(ys))] (local)
Enum.frequencies/go       enum.march:883            @[decreases(len(lst))]         (local)
Decimal.pow10/go          decimal.march:30          @[decreases(e)]                (local)
Hamt.make_branch/go       hamt.march:236            @[decreases(6 - lvl + 1)]      (local)
Map.make_branch/go        map.march:257             @[decreases(6 - lvl + 1)]      (local)
Set.make_branch/go        set.march:206             @[decreases(6 - lvl + 1)]      (local)
HashMap.make_branch/go    hash_map.march:214        @[decreases(6 - lvl + 1)]      (local)
```

Typical test/native proposals: `connect_with_retry @[decreases(attempts_left)]` (10
files), `vault_churn_leak_probe`'s 14 loops `@[decreases(stop - i)]`,
`trmc_computed_arg_nested`'s `@[decreases(b - a)]`, `uuid_v7_dns_parity`'s
`is_lower_hex_or_dash @[decreases(len(s) - i)]` (the scanner candidate).

### Timing

Interleaved, median, private `HOME`, phase-4 exe (`41279fb88`) against the final one,
load 7-10 (other sessions):

| Command | phase 4 | phase 5 | ratio |
|---|---|---|---|
| `--check --refine-report stdlib/list.march` (5 runs) | 1.284 s | 1.260 s | 98.1% |
| `--check --refine-report stdlib/json.march` (5 runs) | 1.240 s | 1.240 s | 100.0% |
| `--check --termination-report` on 5 native files (3 runs each) | 0.643-0.687 s | 0.651-0.699 s | 100.0-104.7% |
| `--check --refine-infer` on the whole stdlib (3 runs) | 18.18 s | 19.22 s | 105.7% |
| `--check --refine-infer`, a native file with nothing to search | 1.276 s | 1.322 s | 103.6% |
| `--check --refine-infer`, native files with targets (3 runs each) | 1.23-2.36 s | 1.90-3.05 s | 130-154% |
| all 417 `test/native` files, `--refine-infer-json`, 3 in parallel | 186 s | 215 s | 116% |

The default `--check` is unchanged (§9's 105%): it never sets `Refine_term.infer`.
The report stays within §9's 150%. `--refine-infer` on a file WITH targets pays two more
module checks (the search and the confirming re-check, about 0.3 s each on a native
file); a file with nothing to search pays none (a graph scan decides).

## Rulings

- **Ruling: the work is on `claude/termination-phase5` in this session's own worktree,
  branched from `claude/termination` at `41279fb88`, not in the brief's worktree.**
  - Why: this session's edit tools refuse to write into another session's worktree,
    and `claude/termination` is checked out there, so git will not check it out twice.
  - Cost if wrong: none to the code; `claude/termination` fast-forwards to this branch
    (`git merge --ff-only claude/termination-phase5` in that worktree).
- **Ruling: a candidate is accepted only on `metric`, never `trusted`.**
  - Why: a `trusted` certificate means an obligation was skipped and an `@[assume]` /
    `@[trusted]` function accepted it. Proposing it would put a metric in the source
    that the checker never proved.
  - Cost if wrong: a metric that is right but only "trusted" is not proposed.
- **Ruling: inference runs only with `Refine_term.infer` set: under `--refine-infer*` or
  `--termination-report`.** Not under a plain `--check`, `--check-json` or the LSP.
  - Why: the brief, and §9's ≤105% for the default path. It also keeps every default
    diagnostic byte-identical (the refine oracle and the error corpus).
  - Cost if wrong: the "Add `@[decreases(e)]`" quick fix appears only on a diagnostic
    produced by an inferring run. A plain `--check-json` diagnostic carries no note.
- **Ruling: the metric phase 2 already checked is not a candidate again.**
  - Why: it already failed (that is why the SCC is a target), so checking it again
    only spends one of the 8. For an annotated SCC this is the written metric, so the
    first `Int` parameter becomes a candidate there.
  - Cost if wrong: none; it was checked with the same obligations.
- **Ruling: candidate shapes come from the SCC's first member and are instantiated by
  parameter POSITION in every member.**
  - Why: §3.3 needs one metric per member of one length, and the parser members of one
    cycle usually share a parameter layout. Position is the only correspondence the
    graph has between two members' parameters.
  - Cost if wrong: a mutual cycle whose members order their parameters differently gets
    no candidate (`0 candidates`), as before.
- **Ruling: `b - i` reads ANY comparison of `i` with `b` in the body, not only the exit
  path's.**
  - Why: finding "the exit path" needs path analysis the graph does not have, and a
    wrong `b` is harmless: its obligations fail. §3.5's "on the exit path" is a filter
    for budget, not soundness.
  - Cost if wrong: budget. 13 stdlib and 8 native targets reach the cap of 8.
- **Ruling: `len(x) - i` is a candidate for a climbing `i` and a `List`/`String` `x`
  passed unchanged, even with no comparison (the `scanner` row).**
  - Why: the RED table's `scanner` row asks for `string_byte_length(s) - i` exactly when
    a builtin contract exists. A byte test is the exit there, so no comparison mentions
    `i`. The candidate is checked like any other; without a contract it fails, and the
    unit is named on its `infer … none` line.
  - Cost if wrong: one candidate of the 8 per scanner-shaped loop.
- **Ruling: the `chunks` row uses a single-list helper (`pop_front`), not `split_at`'s
  tuple.**
  - Why: measured: with `split_at(xs : {List(Int) | len(_) > 0}, …) : (List(Int),
    {List(Int) | len(_) < len(xs)})`, a written `@[decreases(len(lst))]` on the real
    `chunks` shape is refuted. `let (chunk, rest) = …` carries no measure fact for a
    tuple component today (`push_tuple_projs` serves element entries only). Inference
    cannot exceed the checker; the stdlib's `split_at` has no such post anyway. Filed.
  - Cost if wrong: `List.chunks`' own `go` stays uncertified.
- **Ruling: a metric for a local `fn`, or one replacing a written `@[decreases]`, is
  shown but not written.**
  - Why: a local `fn` takes no attribute (phase 4's gap), and overwriting a metric the
    user wrote is the user's call (the editor's quick fix does it one function at a
    time).
  - Cost if wrong: 9 stdlib proposals must be applied by hand once local attributes
    exist.
- **Ruling: `--refine-infer` confirms every writable proposal by a real re-check with
  it written, drops one the re-check does not certify, and takes its prediction from
  that re-check.**
  - Why: the scratch walk is the oracle, but the re-check is what
    `--refine-infer-apply` compares against. It also catches what the scratch walk
    cannot see: a new metric certifies a cycle, so the induction hypothesis can prove
    a skipped return. The IH-free ledger of the refinement fixpoint would then predict
    two skips that the applied program does not have, and the apply would revert
    (`ledger-prediction` perturbation: `Expected (0, 0) Received (2, 0)`).
  - Cost if wrong: two more module checks per `--refine-infer` run that has a target
    (measured above).
- **Ruling: inference does not feed the induction hypothesis or any certificate.**
  - Why: D1. A proposal is not the program; only a written `@[decreases]` is checked
    by the default path.
  - Cost if wrong: none for soundness; a proof waits until the metric is written.
- **Ruling: the note `try @[decreases(e)]` is given only for a cycle of ONE top-level
  function.**
  - Why: the note names one attribute and the action edits one declaration; a mutual
    cycle needs one per member, and a local cannot carry one.
  - Cost if wrong: a mutual cycle's diagnostic offers no metric fix (the
    `--refine-infer` proposals still list each member).
- **Ruling: the JSON `decreases` / `decreases_none` arrays and the `inferred metrics:`
  block appear only when non-empty.**
  - Why: every existing `--refine-infer` consumer and test keeps its output byte for
    byte on a program with no uncertified recursion.
  - Cost if wrong: a consumer must treat a missing array as empty.
- **Ruling: `--refine-infer-kinds` gains the pseudo-kind `decreases`.**
  - Why: the kinds K1-K7 are refinement slots; a metric has none. A list restricts the
    run, so a list without `decreases` infers no metric (`--refine-infer-kinds k1` is
    not slowed down by the new search).
  - Cost if wrong: a script passing a kinds list must add `decreases` to keep metrics.
- **Ruling: `@[decreases]` is written on the `fn` line itself.**
  - Why: phase 4's sweep ruling: no later line moves, so a prediction's spans and every
    other proposal's line stay valid.
  - Cost if wrong: style; `march fmt` may move it.

## Oracles

Both under private `HOME`s, with `_build/default/stdlib` deleted before the baseline and
each check. Baselines were recorded before the first edit, with the phase-4 exe
(`41279fb88`); the checks ran with the final exe (frozen for the IR oracle).

- **`scripts/refine-oracle.sh check`: `REFINEMENT DIAGNOSTICS IDENTICAL (7861 lines over 552
  fixtures)`.** Inference is opt-in, and the oracle runs `--check --refine-report`, which
  never sets `Refine_term.infer`; the corpus has no `@[decreases]` and no `cap total`.
  - Proved able to go red: `oracle-demand-on` (the default path plans every user SCC and
    infers) gave `DIAGNOSTICS CHANGED — 3823 differing lines`, e.g.
    `+native_actor_call_canonical:   by kind: 162 precondition, 49 postcondition, 0
    division, 3 termination`. The search's own effect is invisible to this oracle by
    construction: it runs in a scratch ledger and changes no diagnostic except a note on
    a `termination_unproved`, which the corpus never has. Its evidence is the
    `termination-infer` group.
- **`scripts/ir-oracle.sh check`: `IR IDENTICAL across 497 programs`** (4 skipped, as in
  the baseline). Nothing here reaches codegen.
- The typechecker, parser and lexer are untouched: no types-oracle run, no tree-sitter
  change. `scripts/check-docs.sh`: passed.

## Suites

Full `scripts/run-tests.sh` at load average 8-12: `All suites passed`, 13 suites, 6180
tests. Among them:
- `march-refinecheck`: 1941, including the 20 `termination-infer` cases and every
  phase 0-4 `termination-*` group;
- `march-compiler`: 1453; `march-codegen`: 720; `march-stdlib`: 899;
- `march-lsp`: 394, including the 6 termination code actions;
- `errors`: 300 (no diagnostic text changed).

An earlier direct run of `test_refinecheck.exe` failed one `infer-apply` case with
`Sys_error … _build/default/stdlib/list.march: No such file` — the staged stdlib had been
deleted for the oracle; `scripts/run-tests.sh` restages it, and the case passes.

## Not done

- Everything in `specs/todos/2026-10-28-termination-infer-gaps.md`: tuple-component
  measure facts (`List.chunks`), attributes on local `fn`s (9 stdlib proposals), mixed
  structural-and-Int tuples, descending bounds, a path-sensitive guard search, byte
  contracts and a String `len` mismatch in callee posts.
- The stdlib proposals are reported above, not applied (brief).

## Final review fixes

A fresh final review of the whole branch found two holes and six minors, all confirmed
and fixed here.

### 1 (Critical): builtins that run a user `impl` were trusted

`to_string`, string interpolation (`"${e}"` is parsed as `to_string(e)`) and `println`
run the user's `impl Show` at run time, but their schemes (`to_string : a -> String`)
carry no interface constraint, so `build_graph` resolved them `T_trusted` and added no
edge. A diverging `impl Show` was invisible, the induction hypothesis was granted over
it, and a false return refinement was proved (the review's reproducer: `3 proved, 0
skipped`; on `main`, `1 proved, 2 skipped`; now `1 proved, 2 skipped` again, for the
interpolation, the `to_string` and the `println` spellings alike).

The fix is ONE list, `Refine_term.runtime_dispatch`, merged into `builtin_table`, with
the source of each entry in its comment:

| builtin | interface | dispatch on | where it dispatches |
|---|---|---|---|
| `to_string` (and so `"${e}"`) | Show | arg 0 | `show_dispatch` (eval_builtins.ml); `to_string` -> `show` redirect (lower_expr.ml, mono.ml, cap_passing.ml) |
| `println` | Show | arg 0 | `show_dispatch` (eval_builtins.ml); `Prelude.println` is `print_line(show(x))` |
| `to_json` | JsonTo | arg 0 | `impl_tbl` (eval_builtins.ml); derived impl (lower_expr.ml) |
| `from_json`, `from_json_events` | JsonFrom, JsonFromEvents | every impl (result-typed) | `json_iface_of` (eval.ml), `impl_tbl` (eval_builtins.ml) |
| `own` | Drop | arg 1 | `impl_tbl` (eval_builtins.ml); `Drop$T.drop` closure (lower_expr.ml) |

The builtins whose scheme carries the constraint (`==`, `!=`, `<`, `<=`, `>`, `>=`, `eq`,
`compare`, `show`, `hash`) were already dispatches and are not repeated. Audited as NOT
dispatching: `print` and `html_escape_ctx` (structural repr), the prelude's
`str`/`debug`/`inspect` (ordinary functions over `to_string`), HOF builtins (they call a
function VALUE, already a function-value call).

A single source shared with eval/codegen is not practical: the interpreter's dispatch is
code (`show_dispatch` calls inside builtin closures), not a table. Instead a test keeps
the list honest: `final 1 every interpreter builtin that runs an impl is listed`
installs a probe `impl` of each of the 8 interfaces for a probe type in the
interpreter's `impl_tbl`, calls every interpreter builtin of the typechecker's table
(598) with the probe value in every argument position, and fails on any builtin that
ran an `impl` it is not listed (by scheme or by `runtime_dispatch`) as reaching. It
cannot reach a builtin that dispatches only after a value of another shape (`own`'s
`Pid`, `from_json`'s Json); those two are hand-listed (filed).

Also: a dispatch on a fully known static type (`"${Box(n)}"`, `show(Box(n))`) now
carries its `impl`'s divergence for the report and `cap total` like any call
(`e_dispatch` is now "picked by a value": a type variable or no type). Only a dictionary
dispatch (`show(x)`, `x` of a type variable) keeps the "terminates modulo the `impl`"
rule. Without this, `cap total` could not reject an interpolation of a known type whose
`impl` lives outside the cap.

RED (against the `e91660cdc` implementation, new tests) -> GREEN:

| test | RED line |
|---|---|
| `final 1 interpolation` | `f not certified (got structural)` |
| `final 1 to_string` | `f not certified (got structural)` |
| `final 1 println` | `f not certified (got structural)` |
| `final 1 to_string as a value` (`apply1(to_string, W(xs))`) | `f not certified (got structural)` |
| `final 1 every interpreter builtin …` | `Received: ["println -> Show"; "to_json -> JsonTo"; "to_string -> Show"]` |
| `final cap_total: interpolating a known type whose impl Show diverges` | `Expected ["f"] Received []` |
| `final 1 ==` / `final 1 <` (impl Eq / impl Ord calling `f`) | GREEN before: the scheme constraint already made them dispatches; kept as regression rows |
| controls: `final 1 interpolation control`, `final 1 to_string control`, `final cap_total control` | GREEN before and after |

Certified counts (`--check --termination-report` over every `stdlib/*.march` and
`test/native/*.march` file, 552 entries, `e91660cdc` vs this fix): 501 structural and
263 metric certificates both times, no certificate lost in the stdlib. One new recursive
unit in `test/native`: `set_ops_shared_comparator.march`'s top-level `fn show(s :
Set(Int))`, `cert=unproved:no-int-parameter`. It is a FALSE cycle, not a real one: its
`to_string(Set.to_list(s))` now reaches `List`'s `impl Show`, whose `show(h)` the graph
resolves lexically to the entry file's top-level `show` (a pre-existing resolution
imprecision, fail-closed, filed). Report-only changes: 59 files' `trusted:` lists lose
`to_string` / `to_json` / `from_json`; three `SessionNode` handlers' "may not return"
culprit is now `Option.impl Eq.eq` (a known-type dispatch) instead of
`Msgpack.encode_val`, with the same 50 handler lines and 35 "may diverge" lines. No
generic Show impl pulled a stdlib function into an uncertified cycle.

### 2 (Important): `cap total` let an unmarked member of a marked cycle through

`report_cap_total` ignored a `Marked` culprit in the unit's own SCC. Ruling (the
brief's): under `cap total` every member of a cycle with a `@[diverges]` member must be
marked itself, as Idris's `partial`; outside `cap total` one mark still covers its cycle
for the report and the hypothesis. The error names each unmarked member: "`cyc_a` may
not terminate: it is in a recursive cycle with `cyc_b`, which is marked `@[diverges]`;
under `cap total` every function of that cycle must be marked too."

RED: `final cap_total: an unmarked member …` `Expected ["cyc_a"] Received []`. Controls
(both marked; no cap): no error, before and after. The phase-4 sweep still passes (the
stdlib and test/native have no `cap total` module; the ratchet cases are green).

### Minors

- The `attribute_no_effect` text for a non-recursive `@[decreases]` had a 17-space run
  (a string broken across lines without `\`). RED: the metric group's no-effect case,
  `FAIL no run of spaces in: … so there is no                 recursive call …`. No golden
  pinned it.
- `lsp/lib/code_actions_diag.ml` `attr_region`: a raw newline byte in a char literal is
  now `'\n'`.
- **The `n == 0` -> `n <= 0` repair is no longer a machine fix.** It turned a hang into a
  base-case return, and `forge fix` applies every machine fix. The convention for a
  repair that must not be applied unasked is the one the `try `@[decreases(e)]`` note
  already follows: a note in the message, and an LSP action built from it. The
  diagnostic keeps its note (`the exit `n == 0` misses a negative `n`; `n <= 0` covers
  it.`); the LSP offers "Change `n == 0` to `n <= 0`", not preferred, only when the guard
  is written exactly once in the enclosing function. RED: `FAIL no machine fix on any
  termination diagnostic` (the diagnostic carried `fix: replace … "n <= 0"`). The error
  corpus' `termination_unproved_1` lost its `fix` block (`UPDATE_ERRORS=1`, reviewed).
- The unreachable `diverges_conflicts` scan of impl methods' `@[diverges]` is removed
  (the parser rejects an attribute in an `impl`); a comment says why there is no case.
- `--refine-infer`'s line for a local `fn`'s metric no longer says "apply by hand":
  `(not applied: a local `fn` cannot carry `@[decreases]`; this metric would certify it)`.
- `code_actions_at` deduplicates diagnostics by (range, code, message), both the
  client's context list and its union with the LSP's own. RED: `echoed diagnostic not
  doubled`, `Expected 1 Received 3` (the client echoed the LSP's `;` diagnostic twice
  with a different `source`).

### Rulings

- **Ruling: `own` counts as a `Drop` dispatch although the drop runs later.** — The graph
  already counts a lambda's body as the caller's edges, deferred or not; this is the same
  conservative reading. — Cost if wrong: a caller of `own` whose `Drop` impl is
  uncertified loses its hypothesis.
- **Ruling: a dispatch on a fully known type carries divergence.** — The `impl` is named
  where the call is written; "picked by a value" holds only for a type variable. Needed
  for `cap total` to reject `"${Box(n)}"` with a diverging `impl` outside the cap. —
  Cost if wrong: report wording moves (the `SessionNode` culprits), and a `cap total`
  caller of `x == y` on a type whose `Eq` impl is uncertified (the stdlib's `impl Eq`
  for `List`/`Option` are, today) is an error.
- **Ruling: the dispatch list is checked by an interpreter probe, not shared code.** —
  The interpreter's dispatch is closures, not a table, and the compiled backend's
  redirects are the same names. — Cost if wrong: a builtin that dispatches only on a
  value the probe cannot build is missed; two are hand-listed and filed.
- **Ruling: the `n <= 0` repair is a note plus an LSP action, never a machine fix.** —
  It changes behaviour. — Cost if wrong: one more click in the editor; `forge fix` no
  longer repairs it.

### Oracles and suites

- `scripts/refine-oracle.sh check` against a baseline recorded at `e91660cdc` (same
  `_build`, `_build/default/stdlib` deleted first): `REFINEMENT DIAGNOSTICS IDENTICAL
  (7861 lines over 552 fixtures)`. Expected: its corpus has no interpolation of a type
  whose `Show` impl reaches back, no `cap total` and no `@[decreases]`, and it does not
  run `--termination-report`; the fix's evidence is the RED rows above and the
  reproducer. The oracle's ability to go red was shown in phase 5 (`oracle-demand-on`).
- `scripts/ir-oracle.sh check`: `IR IDENTICAL across 497 programs` (4 skipped, as in the
  baseline). Nothing here reaches codegen.
- `scripts/check-docs.sh`: passed. `scripts/check-tree-sitter.sh`: ok (no grammar change).
- Full `scripts/run-tests.sh` (load average 3-8): `All suites passed`, 13 suites, 6194
  tests: `march-refinecheck` 1954 (13 new cases), `march-lsp` 395 (1 new), `errors`
  300, `march-compiler` 1453, `march-codegen` 720, `march-stdlib` 899.
