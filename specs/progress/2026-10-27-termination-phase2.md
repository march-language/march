Termination checking, phase 2: metrics, `@[decreases]`, SMT obligations

Design: `specs/2026-10-26-termination-checking-design.md` §2.1, §3.3-§3.6, §6 and §8
phase 2; decisions D1-D6. Branch `claude/termination`, on top of phase 1
(`specs/progress/2026-10-27-termination-phase1.md`).

Report-only, per D2: nothing here feeds the induction hypothesis (phase 3), and a module
with no `@[decreases]` files no termination obligation unless `--termination-report`
asks for one.

## What changed

- **Parser (§2.1).** The bracketed `fn_attr` payload is now
  `separated_nonempty_list(COMMA, expr)`.
  - A single bare identifier keeps today's `name:value` string (`@[no_alloc(warn)]` is
    `no_alloc:warn`).
  - `@[decreases(e, ...)]` keeps its expressions in a new `fn_def` field,
    `fn_attr_args : (string * expr list) list`, and the plain name `decreases` in
    `fn_attrs`.
  - Any other attribute with a non-identifier payload is a parse error naming it
    (`` `@[foo(...)]` takes a single name as its argument ``).
  - The unbracketed `@name(value)` and the `TRANSIENT` rules are unchanged. Menhir still
    reports 7 conflicts. The 30 `fn_def` literals in the tree gained `fn_attr_args = []`
    (or copy it through).
- **`march fmt`** prints the payload back: `@[decreases(m, n)]`, and `@[no_alloc(warn)]`,
  which it used to print as the unparseable `@[no_alloc:warn]` (measured with the phase-1
  exe).
- **`Obligation.Termination`** (a fourth kind) and the reason **`Not_decreasing of
  string`** (slug `not-decreasing`; the payload is the solver's model).
  `--refine-report`'s `by kind:` line (now `Obligation.by_kind_line`) appends
  `, N termination` only when N > 0; `--refine-report-sites` names the kind `termination`.
- **`check_subject Decreases` and `check_call ?kind`.** `note` records the given kind. A
  `Decreases` obligation is proved or skipped, never violated. After the first discharge
  it records `Skipped (Not_decreasing model)` and stops: no `¬G` query, no witness run, no
  diagnosis. `note` emits no diagnostic for it. `@[trusted]` still turns its skip into
  `Trusted`.
- **`Refine_term`, phase 2.**
  - The graph records, per edge, which of the owner clause's parameters are rebound at the
    call (`e_shadowed`, via a new `Param` binding), and every call to a builtin or extern
    (`trusted`).
  - `metric_errors` checks the §2.1 fragment: parameters, Int literals, `+ - *`, `/` by a
    positive literal, and measures applied to parameters.
  - `plan_metrics` handles each demanded SCC: one where a member carries `@[decreases]`, or
    any SCC of user code under `--termination-report`. In the order of §3.5:
    - structural (phase 1's certificate), with no query;
    - `unproved:reference` / `unproved:non-positive`, where no metric can help;
    - the written metrics, when any member has one. An unannotated member takes its first
      `Int` parameter only when the metrics have one component;
    - else the first `Int` parameter of every member.

    It files one obligation per intra-SCC direct or lambda edge.
  - `decreases_site` builds §3.4's synthetic signature. The subject is a dummy `$t`; the
    predicate is `lex(M_g[args], M_f)` over these formals:
    - `$g_p`: a callee parameter whose actual is a bare name or an unreflectable
      expression;
    - `$c_x`: a caller-scope name.

    Plain Int arithmetic (`n - 1`, `n / 2`) is inlined. An argument holding a recursive
    call of the SCC is passed as the fresh name `$opq_p`, an arbitrary value.
  - `finish`: an SCC is `metric` when every obligation was reached and proved, `trusted`
    when each was proved or trusted, else `unproved:not-decreasing`.
- **`Refine_check`.**
  - Before the walk, `check_module` plans (when anything is demanded). It emits
    `invalid_decreases` errors, an `attribute_no_effect` warning for `@[decreases]` on a
    non-recursive function, and fills `term_sites`.
  - `visit`'s `EApp` arm discharges the obligation of a call span in `term_sites` through
    `check_call ~subject:Decreases ~kind:Termination`. It uses the path, scope and `let`
    facts that reach the call.
  - After the walk, `check_module` decides the certificates (`Refine_term.last_certs`, which
    `--termination-report` prints). It emits `termination_unproved` for each annotated
    SCC that is not proved: a warning, or an error when an annotated member sits in a
    `cap verified` decl list.
  - D6: `warn_unknown_attributes` warns (`unknown_attribute`) on any `fn` attribute name
    outside `assume, decreases, measure, no_alloc, no_warn_recursion, trusted,
    trusted_linear, vectorize`, with a did-you-mean within edit distance 2.
- **`--termination-report`** sets `Refine_term.check_all`, so every recursive SCC of user
  code is checked.
  - Its `cert=` column shows phase 2's verdict:
    `structural | metric | trusted | unproved:<reason>`.
  - The certificate line counts `structural, metric, trusted, unproved`.
  - A new `trusted:` line lists the builtin and extern callees.
- **New diagnostic codes**: `invalid_decreases`, `termination_unproved` and
  `unknown_attribute`. Each has an `--explain` page in `specs/lang/errors/` and a
  `test/errors/<slug>_1` twin (seeded, `UPDATE_ERRORS=1`).
- **Docs**:
  - `specs/lang/refinement-types.md` gains "Metrics and `@[decreases]`" and "Attribute
    names are checked";
  - `specs/lang/grammar.md` §8.2 describes the attribute payload;
  - `specs/lang/surface-syntax.md`'s attribute example no longer shows the unimplemented
    `@[deprecated]`;
  - `scripts/gen-lang-docs.py` was rerun;
  - grammar corpus `parse/p44_decreases_attribute.march`, INDEX counts 61/44/17;
  - CHANGELOG `### Added`.
- New todo: `specs/todos/2026-10-27-termination-metric-gaps.md`.

## Tests (group `termination-metric`, 25 cases; phases 0-1's 39 still green)

Every row of the phase 2 RED table is covered, plus a REJECT control for every
certificate rule.

RED first: a stub build in which `plan_metrics` plans nothing (`stub-no-phase2`) fails 19
of the 25. The first failing line:

```
FAIL fib certificate
   Expected: `"metric"'
   Received: `"<none>"'
19 failures! in 0.044s. 65 tests run.
```

The other six cases went RED under the perturbations below: the parser, D6, default-off,
two `invalid_decreases` cases and `attribute_no_effect`. Each perturbation is one edit to
the shipped code (`perturb.py` in the session scratchpad, not committed), a rebuild, a run
of `termination*`, and a restore:

| Case | Asserts | Perturbation | First failing line |
|---|---|---|---|
| t5 `fib` | `metric`; 2 proved | `default-metric` (no default) | `FAIL fib certificate` / `Received: "unproved:no-int-parameter"` |
| t4 `down` | `unproved:not-decreasing`; one skip on `down` with model `n = -1` | `zero-le-component` (drop `0 <=`) | `FAIL down certificate` / `Received: "metric"` |
| t4, unannotated | no `termination_unproved` (D2) | `escalate-all` | `FAIL no warning` / `Expected: 0 Received: 1` |
| t4, annotated | one warning, `` `down(n - 1)` is not shown to decrease `n`: e.g. n = -1 `` | `stub-no-phase2`, `zero-le-component` | `expected one termination_unproved, got 0` |
| `down_le` | `<= 0` exit: `metric` | `stub-no-phase2`, `default-metric` | `Received: "<none>"` |
| t3 ev/od | refined: both `metric`, both edges obliged; unrefined: both unproved | `self-edges-only` (per-edge obligations) | `FAIL both edges obliged` / `Received: []` |
| t8 `ack` | `@[decreases(m, n)]`: `<= 0` exits `metric`, `== 0` exits unproved | `zero-le-component` | `Received: "metric"` (the `== 0` half) |
| lex control | `f(m + 1, n - 1) + f(m - 1, n + 1)` (diverges from `f(2, 2)`): unproved | `lex-equality-guard` (drop `x1 == y1 &&`) | `FAIL f certificate` / `Received: "metric"` |
| t9 / t9b | `bits(n / 2)` `metric`; `bits1`, `same`, `grow` `not-decreasing`, each with a model `n = …` | `stub-no-phase2` | `Received: "<none>"` |
| t2 `up` | `@[decreases(100 - n)]`: `n >= 100` guard `metric`, `== 100` unproved | `zero-le-component` | `Received: "metric"` |
| `len` metric | `@[decreases(len(xs) - i)]` on a scanner: `metric` | `parser-no-exprs` | parse error |
| shadowing | `let n = n + 5` then `f(n - 1)` (diverges): `unproved:shadowed` | `ignore-shadowing` | `Received: "unproved:not-decreasing"` (see the ruling) |
| unreached site | a recursive call in an arm guard: unproved, "the checker did not reach this call" | `unreached-is-proved` | `FAIL q certificate` / `Received: "metric"` |
| nested call | `h(h(n - 1))`: unproved | `opaque-as-zero` | `FAIL h certificate` / `Received: "metric"` |
| parser | p18 parses (2 args); `len(xs) - i` (1 arg); `@[no_alloc(warn)]`, `@[no_alloc(transient)]` unchanged; `@[foo(1 + 2)]` names `foo` | `parser-no-exprs` (decreases treated like any name) | 13 cases fail, e.g. `expected one termination_unproved, got 0` |
| `invalid_decreases` | a local, a `Float`, a bare `List` parameter: one error each, naming its cause | `no-fragment-check` | `FAIL local: one error` / `Expected: 1 Received: 0` |
| lengths differ | `(n, 0)` against `(n)` in one cycle: 2 errors, `unproved:invalid-decreases`, no extra warning | `parser-no-exprs` | fails |
| no effect | `@[decreases]` on a non-recursive `f`: `attribute_no_effect` | `parser-no-exprs` | fails |
| t11c omega | `w` `unproved:non-positive`; `u(t : T, n)` with `T(Int -> Int)`: `metric` | `stub-no-phase2` | `Received: "<none>"` |
| `cap_verified_annotated` | annotated + unproved: an error; unannotated: no diagnostic, no obligation | `demand-all` | `FAIL unannotated: no obligation` / `Expected: 0 Received: 1` |
| `kind_counted` | `by kind: … 0 division, 2 termination`; nothing appended at 0 | `kind-line` | `FAIL with` |
| `cache` | `@[decreases(n)]` `metric` and `@[decreases(n - 2)]` unproved, alternating twice | `zero-le-component` | `Received: "metric"` |
| default off (D2) | `fib` + `down` unannotated, no report flag: 0 obligations, no certificate | `demand-all` (both gates) | `Expected: 0 Received: 1` |
| D6 | `@[decrease(n)]`: one `unknown_attribute` with "did you mean `@[decreases]`?"; `@[trusted]`, `@[no_alloc(warn)]` silent | `no-unknown-attr` | `expected one unknown_attribute, got 0` |
| report | `cert=metric` / `cert=unproved:not-decreasing`, the certificate line, `trusted: 3 builtin or extern callees: ext_tick, int_to_string, string_length` | `stub-no-phase2` | `Received: … "<none>"` |

Two perturbations first came back green. Each was fixed in the tests, not ignored:
- `unreached-is-proved` had no fixture that reached it, so the arm-guard case was added.
- `demand-all` changed one gate of two. The D2 rule lives both in `check_module`'s gate
  and in `plan_metrics`'s `demanded`, so the perturbation now changes both.

GREEN: `termination-metric` 25/25, with a cold and a warm VC cache.

The phase-1 report test's summary string changed with the report's new certificate line
(`certificate: 1 structural, 0 metric, 0 trusted, 1 unproved`).

## Oracles

All four ran under private `HOME`s, with any `_build/default/stdlib` copy deleted before
the baseline and before each check. The baselines were recorded before the first edit,
with the phase-1 exe (`6549fef43`), frozen; the checks ran with the final exe, frozen too
(byte-identical to the committed build).

- **`scripts/refine-oracle.sh check`: `REFINEMENT DIAGNOSTICS IDENTICAL (7861 lines over 552
  fixtures)`.** The corpus has no `@[decreases]`, so no termination obligation was filed,
  and no unknown attribute was warned about.
  - The oracle was proved able to go red. A build that demands every SCC of user code
    (both D2 gates forced open) gave `DIAGNOSTICS CHANGED — 1998 differing lines`, e.g.
    `+native_actor_call_late_reply:   by kind: 0 precondition, 0 postcondition, 0 division,
    1 termination`.
- **`scripts/ir-oracle.sh check`** (`MARCH_ORACLE_EXE`, run from the worktree root): `IR
  IDENTICAL across 497 programs`.
- **`scripts/types-oracle.sh check`** (the parser AST changed): Tier 1 `CORE-AST CHANGED — 61
  fixtures`, Tier 2 `DIAGNOSTICS CHANGED — 6 differing lines`. Every line is explained:
  - **59 fixtures**, all with `derive`, `@[endpoints]` or `@[remote]`: the JSON is equal
    once the `start_col`/`end_col` of `"file":"<none>"` spans are masked. These are
    `Desugar_derive.decl_salt` values, which hash the generated decl structurally, and
    `fn_def` has one more field (ruling below).
  - **`reject_t286`** (2 Tier-1 lines, 4 Tier-2 lines): the same salts, inside the text of
    an `overlapping_impl` message (`<none>:29:232040383` → `<none>:29:270352568`).
  - **`reject_t278`**: its 31 diagnostics are the same multiset after masking the salts.
    They are sorted by span, so new salts reorder two of them on one line.
  - **`reject_t351`** (2 Tier-2 lines): a witness `h = 4` became `h = 3`. This is solver
    nondeterminism, not this change: the phase-1 exe alone, with the VC cache cleared
    before each run, printed `h = 3` on one run and `h = 4` on the next.
- **Timing** (§9, ≤ 105% for default `--check`): `--check --refine-report`, phase-1 exe
  against phase-2 exe, interleaved, 5 timed runs each after a warm-up, median, load 4:
  - `stdlib/list.march`: 1.282 s → 1.205 s (94%);
  - `stdlib/json.march`: 1.302 s → 1.202 s (92%).

  That is within budget. The speed-up is noise: an unannotated module does no new
  solver work, only the attribute walk and the `@[decreases]` scan.

## Rulings

- **Ruling: `@[decreases]` always stores `decreases` plus its expressions, even for one
  identifier (§2.1 keeps `name:value` for a single `EVar`).**
  - Why: the termination pass then reads one field; `decreases:n` would be a second
    spelling to keep in step. The `name:value` rule is kept for every other attribute,
    which is what §2.1 protects (`@[no_alloc(warn)]`).
  - Cost if wrong: none outside the termination pass. `fn_attrs` holds `"decreases"`, never
    `"decreases:n"`.
- **Ruling: only the bracketed payload takes expressions; `@name(value)` keeps
  `LOWER_IDENT`.**
  - Why: the design writes the attribute bracketed, and leaving the other rule alone keeps
    the conflict count at 7 without analysis.
  - Cost if wrong: `@decreases(m, n)` (unbracketed) is a parse error. The bracketed form is
    the documented one.
- **Ruling: adding `fn_attr_args` to `fn_def` changes the derive-site span salts.**
  - Why: `Desugar_derive.decl_salt` hashes the whole generated decl structurally, and a
    record with one more field hashes differently. Seven `test/errors` expectations for
    derived code were regenerated: their synthetic `<none>:29:92686154`-style columns
    moved. They are deterministic run to run (`run_errors.exe` green twice).
    The same salts are all of the types-oracle Tier-1 change.
  - Cost if wrong: none; the columns are opaque salts.
- **Ruling: a termination obligation is discharged in the refinement walk, keyed by the
  call's span, rather than by a separate pass.**
  - Why: `check_call` then supplies, at that call, the path facts, scope facts, `let`
    laundering, the VC cache and the models, exactly as §3.4 asks. The walk's shadow
    discipline applies too.
  - Cost if wrong: a call the walk does not visit (a match-arm guard) is never discharged.
    It counts as unproved (tested).
- **Ruling: the caller's metric must name only parameters still holding their entry
  value at the call (`unproved:shadowed` otherwise).**
  - Why: §3.3's `M_f` is the caller's metric at ENTRY, but the predicate is read in the
    scope of the call. After `let n = n + 5`, `n` is the inner value, so `f(n - 1)` would
    "prove" `n - 1 < n` of the inner `n` while passing the entry `n` plus 4 (the shadowing
    fixture diverges).
  - The walk's own shadowing discipline happens to retire `n`'s facts too: the perturbation
    still gave `unproved:not-decreasing`. Nothing in it is designed for this, and it is not
    relied on.
  - Cost if wrong: harmless rebindings are unproved (gaps todo).
- **Ruling: an argument holding a recursive call of the SCC is an arbitrary value
  (`$opq_p`).**
  - Why: before phase 3 such a call has no contract. An unreflectable actual leaves the
    whole obligation unchecked: `ack(m - 1, ack(m, n - 1))` was skipped
    `unreflectable-subject`. A fresh unconstrained name over-approximates the value, so a
    proof holds of every value it can take.
  - Cost if wrong: none for soundness. `h(h(n - 1))` stays unproved, and `opaque-as-zero`
    turns it RED.
- **Ruling: plain Int arithmetic arguments are inlined into the predicate.**
  - Why: `reflect_scalar` (the actual-argument path) has no `/` arm, while the predicate
    encoder reads `/` and `%` by a literal; `bits(n / 2)` was otherwise
    `unreflectable-subject`. Inlining, rather than a new `reflect_scalar` arm, means no
    other refinement verdict can move.
  - Cost if wrong: none; the inlined term is the argument itself.
- **Ruling: in an annotated cycle, an unannotated member takes its first `Int` parameter
  only when the metrics have one component; otherwise the cycle is
  `unproved:unannotated:<name>`.**
  - Why: §3.3 requires one length per SCC, and a local `fn` cannot carry an attribute.
  - Cost if wrong: a mixed cycle with a lex metric must annotate every top-level member,
    and cannot include a local `fn`.
- **Ruling: metrics of different lengths in one cycle are `invalid_decreases` on every
  annotated member, and suppress `termination_unproved`.**
  - Why: §3.3 names the error, and one error per offending annotation is what the user
    edits.
  - Cost if wrong: two errors for one mistake in a two-member cycle.
- **Ruling: `cap verified` escalates `termination_unproved` only for an annotated
  function.**
  - Why: D2 escalates "the termination obligations a proof relied on", and in phase 2 no
    proof relies on one (there is no IH yet). The only escalation left is §6's "every
    annotated `@[decreases]` that fails".
  - Cost if wrong: an unannotated diverging function in a `cap verified` module is still
    not flagged, as today.
- **Ruling: termination is demanded only by `@[decreases]` or `--termination-report`.**
  §9 also lists a pending refined return in the gate, `@[measure]`, `cap verified` and
  `cap total`.
  - Why:
    - a pending return benefits only from the IH (phase 3);
    - measures are gated structurally (phase 1);
    - `cap total` is phase 4;
    - `cap verified` follows D2.

    Demanding more now would add obligations to unannotated code, which the oracle forbids.
  - Cost if wrong: phase 3 must add the pending-return demand when it adds the IH.
- **Ruling: a refuted termination obligation stops after the first discharge.**
  - Why: §3.4 says it is never `refinement_violated`. The `¬G` query, the witness run and
    the diagnosis exist to word a violation or a skip; a termination skip is worded by the
    termination pass, from the model.
  - Cost if wrong: the ledger has no "definitely never decreases" distinction; both read
    `not-decreasing`.
- **Ruling: `by kind:` appends `, N termination` only when N > 0 (§6 says "a fourth
  kind").**
  - Why: otherwise every `--refine-report` changes by one word, and the oracle must stay
    IDENTICAL for unannotated code.
  - Cost if wrong: a tool parsing the line must accept both shapes.
- **Ruling: the D6 list is the attributes some pass reads; `@[deprecated]` is not on it.**
  - Why: `@[deprecated]` was shown in `surface-syntax.md`, but nothing reads it, which is
    D6's failure mode exactly; the doc example now shows `@[decreases]`. `diverges` is not
    on the list until phase 4 gives it a meaning. Only `fn` attributes are checked:
    protocol and actor attributes already have parse-time checks.
  - Cost if wrong: a user writing `@[deprecated]` is warned that it does nothing, which is
    true.
- **Ruling: `trusted` counts distinct builtin and extern callee NAMES of user units, not
  call sites, and leaves out operators.**
  - Why: §3.6 asks for a count in the report. Names are what a reader can check, and `+`
    would drown the list.
  - Cost if wrong: none; the count is report-only.
- **Ruling: `metric_errors` treats a parameter of unknown type as an `Int`.**
  - Why: an unannotated parameter with no recorded type has no sort to object to, and the
    solver declares it `Int`. A non-Int value there makes the query fail, never prove.
  - Cost if wrong: a confusing `not-decreasing` instead of `invalid_decreases` for an
    untyped, non-Int parameter.

## Suites

The full `scripts/run-tests.sh` ran at load average 4-9 and printed `All suites passed`:
13 suites, 6111 tests. Among them:
- `march-refinecheck`: 1879 tests, including the 64 `termination-*` cases;
- `march-compiler`: 1453;
- `errors`: 299, including the three new twins.

Separately:
- `scripts/check-tree-sitter.sh`: `1668/1672 files parse clean; 4 known failures`
  (unchanged), `ok`, with no `known-failures.txt` entry.
- `specs/lang/grammar/check_grammar.sh`: 61 passed.
- `scripts/check-docs.sh`: passed.

## Not done

- `@[diverges]`, `cap total`, actor handlers and the LSP actions (phase 4); the IH
  (phase 3); inference (phase 5).
- The gaps in `specs/todos/2026-10-27-termination-metric-gaps.md`.
