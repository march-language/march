Refinements: two-argument abstract refinements, long form (multi-arg design phase 2)

Phase 2 of `specs/2026-10-18-abstract-refinements-multi-arg-design.md` (§3, §4, §5,
§1.4 W1-W5, §9 "Phase 2"). Phases 1a (`d053b4bdb`) and 1b (`eedd5a35f`) built the
entry record and gave relations a meaning
(`specs/progress/2026-10-21-abstract-multiarg-phase1a.md`, `…-phase1b.md`). This phase
lets a callback of two arguments define an abstract refinement `p` of two, and lets a
return or parameter relate two sibling slots through it. Long form only: no parser
change (the sugar is phase 3).

## Before / after

```march
type Assoc(k, v) = ANil | ACons(k, v, Assoc(k, v))
fn filt(a : Assoc(k, v), keep : ({x : k | true}) -> ({y : v | true}) -> {Bool | _ == p(x, y)})
    : Assoc({x : k | true}, {y : v | p(x, y)}) do
  match a do
    ANil -> ANil
    ACons(k, v, t) -> if keep(k, v) do ACons(k, v, filt(t, keep)) else filt(t, keep) end
  end
end
```

| Row | Program | Before (`eedd5a35f`) | After |
|---|---|---|---|
| s1 | the definer above | two "`p` is not a measure" warnings | `p` abstract, arity 2, no warning |
| s5 | `… -> ({y : v \| true}) -> {Bool \| _ == p(y)}` | accepted, inert | error: "`p` is applied to 1 of the callback's 2 arguments; write `p(x, y)`" |
| a1 | `filt`'s return | no obligation (the slots were not read) | proved |
| a1-bad | `bad(a, keep) : <filt's return> do a end` | no obligation | not proved (skip) |
| a2 | `need_pos(filt(a, fn (_k, v) -> v > 0))` | skip, `parametric-source-unproved` | proved |
| rel | `need_arel(filt(a, fn (k, v) -> v > k))` | skip, same | proved |
| m4/m6 | `fn (_k, v) -> v >= 0` / `fn (k, v) -> v > k` into `need_pos` | skip, same | skip, `abstract-refinement-too-weak` |
| m5 | `fn (k, v) -> k > 0 && v > k` into `need_pos` | skip, same | proved (projection) |
| m7 | `fn (_k, v) -> v > now` | skip, same | skip, `abstract-refinement-uninstantiated` |
| a3 | `keep(k)(v)` in a body | parse error | unchanged (checked: "`f(...)(...)` is not a chained call") |
| a4 | `cap verified`, `count(a, fn (k, v) -> v > k)` | accepted, 0 obligations | accepted, 0 obligations (no definer obligation) |

## What changed

- `lib/refinecheck/refine_abstract.ml` (§5.1):
  - `applications_n`: applications of any arity, arguments classified as before.
    `applications` is unchanged; its arity-1 entries are exactly `applications_n`'s.
  - `occurrence` gains `occ_args`, `occ_scope`, `occ_slot` and `occ_cont`. The old
    fields keep their arity-1 meaning. For an n-ary definer, `occ_arg` and
    `occ_binder` are the joined argument and chain-binder lists, so the role summary
    prints `D=` for a well-formed definer.
  - `walk_ty` walks a callback chain. A definer in the final codomain of `D1 -> … ->
    Dn -> C` records the chain's (binder, base) list. A slot occurrence records its
    application's slots (binder, base), its own index and the constructor. Two
    exclusions keep everything else as it was. An n-ary application under a chain of
    one domain (a tuple domain, s4) is no occurrence at all. An operator head (`==`,
    `&&`) is never an n-ary candidate.
  - `check_nary`: W1 to W5 as hard errors `abstract_refinement_misuse`, each naming its
    fix. It runs for any name `is_nary` holds of (an application of several arguments,
    or a definer under a chain of several domains). Every other name takes the
    unchanged arity-1 rules.
    - W1: the definer applies `p` to every chain binder, once each, in order (D3).
    - W5: one arity.
    - W2: a single slot gets the long-form fix. Otherwise the arguments must be distinct
      sibling binders, at scalar slots.
    - W3: one base per position.
    - W4: `entry_shaped`, passed in from `Refine_check`, since this module sits below
      `Refine_encode`.
  - The unused-definer warning has an n-ary wording. `arity_of` and `positive_bases`
    are new. `subst_abstract_n` is the n-ary β-substitution.
- `lib/refinecheck/refine_encode.ml`, `refine_scope.ml`, `refine_call.ml`,
  `refine_post.ml` (§3a):
  - The `$abs_p` arm of `smt_of_r_marked` is n-ary. `abs_apps` returns argument lists.
    `abstract_preamble` declares one signature per symbol, at its arguments' sorts.
  - `abs_sort_conflict` refuses, as `sort_conflict`, a query applying one symbol at two
    sort tuples. This is checked at both discharge sites.
  - The `[ _ ]` arms of `mentions_str`, `wellsorted` and `formula_wellsorted`, and of
    `resolve_sorts_exact`'s `infer`, take any arity.
  - At arity 1 every query text is byte-identical: same preamble string, same terms.
- `lib/refinecheck/refine_scope.ml` (§5.2, §5.3):
  - `abstract_tyvar_slot` sees n-ary applications.
  - `abstract_rel_binders` and `elem_app` admit a type-variable slot whose binder an
    n-ary current-abstract application in a sibling slot names (`{x : k | true}`).
    This applies inside the declaring definition only. The slot is emptied once the
    relation is read if its own fact is literally `true`.
  - `chain_sig_of_ty`: a chain `D1 -> … -> Dn -> {Bool | _ == e}` (n ≥ 2) is an
    n-parameter callback signature `[$cb_arg; $cb_arg2; …]`. Each domain binder is
    renamed in `e` and in later domains' refinements. Every other chain keeps the
    one-parameter signature. `declared_elem_return`'s marker test is now "first
    parameter is `$cb_arg`".
- `lib/refinecheck/refine_check.ml` (§4):
  - `instantiate_abstract_n` handles:
    - an uncurried lambda of n parameters;
    - a curried chain of one-parameter lambdas whose intermediate bodies are the next
      lambda;
    - a `let`-bound lambda (with the C5 self-name decline);
    - a name with a proved `{Bool | _ == e}` return over n parameters (a function, or a
      chain-typed callback through `chain_sig_of_ty`).

    The body is read by `inline_bool_body` over the parameter list and must mention
    nothing else.
  - `named_predicate_n`'s `reflected` accepts an n-ary current abstract.
  - `abstract_flow_n` (§4.2) does the following:
    - reads the callee's return entry with the callee's abstracts uninterpreted
      (`abstract_entry_of_ty`, i.e. through `elem_app` as inside the definition);
    - gates on `elem_ret_proved` and on P1/P2 for the type-variable positive bases;
    - instantiates and β-substitutes, cuts each relation down to the slots it still
      names, and normalises (I1);
    - takes each type-variable slot's sort from the demand, else from the call's own
      type (`elem_markers_of_expr`), and declines when the sort is unknown;
    - conjoins the input entry's SLOT facts (see the rulings);
    - decides `entry_implies ~have:produced ~want` in a scratch ledger: all proved
      gives `Proved`, any violated gives `Too_weak` (naming the callable as written
      and the first unimplied predicate), anything else gives `Undecided`.

    The caller records one `record_abstract_verdict` per demanded call.
    `abstract_flow_any` tries it before the untouched arity-1 `abstract_flow`, at all
    four call sites. A tuple component (`~component`) is arity-1 only.
  - `abstract_param_entry_n` (§4.3): a parameter relating sibling slots through an
    n-ary `p` obliges the argument against the instantiated relation. The sorts come
    from the argument's type. `check_arg_elements` tries it before the arity-1
    `abstract_param_entry`.
  - §5.5: unchanged and pinned. A chain parameter's codomain is an arrow, so
    `check_pass_sites` owes nothing (a4 under `cap verified`).

## Tests

New group `abstract-multiarg` in `test/test_refinecheck.ml`, 33 cases, registered after
`relational-elements`. The final test file was run against a worktree of the base
`eedd5a35f`, with only the test file replaced: `31 failures! … 33 tests run.` The two
that pass there are controls by design: "the well-formed definer has no misuse error"
and "cap verified: a too-weak demand is an error" (base: an error for another reason).
The RED lines below are from that run (assertion, Expected → Received):

| # | Case | RED on base |
|---|---|---|
| 0 | s1 roles, no unknown-predicate warning | roles `[("p", ["+"; "D="])]` → `[]` |
| 1 | W1 (s5): `p(y)` under two binders | `arity:` `true` → `false` |
| 2 | W1: `p(y, x)` (order) | `order:` `true` → `false` |
| 3 | W2: single slot `Assoc(k, {v \| p(_)})` | `single slot:` `true` → `false` |
| 4 | W2: `p(y, y)` | `siblings:` `true` → `false` |
| 5 | W3: `({x : Int \| true})` vs slot `k` | `sorts:` `true` → `false` |
| 6 | W4: `Two(k, v) = K(k) \| V(v)` | `shape:` `true` → `false` |
| 7 | W5: arity 2 and arity 1 definers | `arity:` `true` → `false` |
| 8 | control: well-formed, no misuse | passes on base |
| 9 | a1: `filt`'s return proved | `return of filt: has obligations` `true` → `false` |
| 10 | a1-bad: not proved | `return of bad: has obligations` `true` → `false` |
| 11 | `partial_call_no_fact` (`let g = keep(k)` then `g(v)`) | `return of filt2: has obligations` `true` → `false` |
| 12 | a2 | `[("proved", "")]` → `[("skipped", "parametric-source-unproved")]` |
| 13 | `curried_lambda` (negative occurrence) | `proved` `true` → `false` |
| 14 | `curried_lambda` through `filt2`: uninstantiated, names the unproved body | `[uninstantiated]` → `[parametric-source-unproved]` |
| 15 | `key_projection` | `[proved]` → `[parametric-source-unproved]` |
| 16 | `rel_demand` | `[proved]` → `[parametric-source-unproved]` |
| 17 | `projection_fresh_k` (m5) | `[proved]` → `[parametric-source-unproved]` |
| 18 | `projection_too_weak` (m6) | `[too-weak]` → `[parametric-source-unproved]` |
| 19 | `too_weak` (m4), the detail names the lambda | `[too-weak]` → `[parametric-source-unproved]` |
| 20 | `capture` (m7) | `[uninstantiated]` → `[parametric-source-unproved]` |
| 21 | `opaque` | `[uninstantiated]` → `[parametric-source-unproved]` |
| 22 | `wrong_arity_lambda` | `[uninstantiated]` → `[parametric-source-unproved]` |
| 23 | `named2`: proved, plus the unproved-return control uninstantiated | `[proved; uninstantiated]` → `[parametric-source-unproved; …]` |
| 24 | `cb_passthrough` | `[proved]` → `[parametric-source-unproved]` |
| 25 | `let_lambda`: proved, plus rebinding retires it | `[proved; uninstantiated]` → `[parametric-source-unproved; …]` |
| 26 | `conjunction` | `[proved]` → `[parametric-source-unproved]` |
| 27 | `conjunction` control (unrefined input) | `[too-weak]` → `[parametric-source-unproved]` |
| 28 | `conjunction_drops_input_rel` (+ slot-fact control) | `[too-weak]` → `[parametric-source-unproved]` |
| 29 | `negative_occurrence`: proved / violated / skipped / uninstantiated | `proved:` `true` → `false` |
| 30 | `cache`: `v > k` vs `v >= k`, both orders | `[proved; too-weak]` → `[parametric-source-unproved; …]` |
| 31 | a4 / `cap verified`: no definer obligation, a proved demand no error | `[]` → `["…cannot verify element refinement `_ > 0` on `need_pos` (parametric-source-unproved…"]` |
| 32 | `cap verified`: a too-weak demand is an error | passes on base (control) |

`conjunction_drops_input_rel` is the brief's test. The input is `a : Assoc({x : Int |
true}, {y : Int | y > x && y > 0})` through `filt(a, fn (_k, v) -> v < 100)`. Into
`need_arel` it must be too-weak: the input's relation is not carried. Into `need_band`
(`_ > 0 && _ < 100`) it must be proved: the input's slot fact `y > 0` is carried.

`arity1_unchanged` is no separate test. It is the existing groups passing unmodified:
`abstract-refinements`, `abstract-pass-sites`, `abstract-phase2`, `abstract-phase3`,
`abstract-leftovers-a` to `-e`, `abstract-sugar` and `relational-elements`. No existing
test was edited. The AR-phase-4 test "a curried Bool[p] proves nothing and violates
nothing" (`abstract-sugar`) still passes unmodified, because it asserts only the
(proved, violated) pair, which is still (0, 0). Its program now carries a W1 hard
error, though, as D3 intends: `Int -> Int -> Bool[p]` is the shorthand applying `p`
to the last of two arguments. Phase 3 rewrites that test, as §9 says.

Conformance:
- `specs/lang/types/accept/t455_two_argument_abstract_refinement.march`: a1, a2, rel,
  m5, a negative occurrence and a4, under `cap verified`.
- `reject/t456_two_argument_abstract_too_weak.march`: m4 under `cap verified`, with
  `-- EXPECT-ERROR: abstract-refinement-too-weak: `fn (_k, v) -> v >= 0` does not imply
  `_ > 0``.

On the base compiler, t455 has two `cannot verify` errors (`parametric-source-unproved`)
and t456's error is the parametric-source one. After the change, t455 has none and t456
has the expected text. `specs/lang/types/INDEX.md` has the new rows and counts (492 =
206 + 286). `specs/lang/types/check_types.sh`: `492 passed, 0 failed`.

## Verification

- `scripts/refine-oracle.sh`: the baseline was taken at `eedd5a35f` before any edit
  (549 fixtures, 8726 lines, the same as phase 1b's). After the change:
  `REFINEMENT DIAGNOSTICS IDENTICAL (8726 lines over 549 fixtures)`. The corpus has no
  two-argument abstract refinement, no chain ending in `{Bool | _ == e}` and no curried
  `Bool[p]` shorthand, so nothing could move, and nothing did. That includes no new
  W1 error anywhere in `stdlib` or `test/native`.
- The oracle was shown to go RED. The perturbation made `abs_sort_conflict` refuse
  every query with an abstract symbol (`ds <> [] || …`). The result was
  `DIAGNOSTICS CHANGED — 2341 differing lines`: for example,
  `native_actor_call_canonical: skipped (abstract-refinement-uninstantiated): 26` is
  new, because the stdlib combinators' own returns no longer prove. The file was
  restored from a saved copy and rebuilt, and the oracle ran again: IDENTICAL.
- Refine audit baselines (`test/refine_audit/*.baseline`, group `audit-baseline`): not
  regenerated, and they still pass. `--refine-audit` on t455: `16 enforced, 0 inert
  (warned), 0 unenforced`.
- `scripts/run-tests.sh refinecheck` (z3 on PATH): `Test Successful … 1449 tests run.`
  That is 1416 + 33.
- Full `scripts/run-tests.sh`: `All suites passed.`, exit 0. refinecheck: `1449 tests run`;
  compiler: `1451 tests run`.
- Budget (§10): cold `--check --stdlib-source --refine-report stdlib/list.march` with
  artifacts and the VC cache cleared and a fresh `HOME` every run, 5 interleaved A/B
  runs against a base worktree of `eedd5a35f`.
  - Base: 2.688, 1.912, 1.894, 1.890, 1.903 s (median 1.903).
  - This phase: 1.874, 1.856, 1.874, 1.872, 1.892 s (median 1.874).
  - That is 98.5% of base, within the 110% budget.
  - Load average: 6.1 at the start, 5.9 at the end.
  - The report is byte-identical (`user + stdlib`: 105 proved, 33 trusted, 37 skipped).
- `scripts/check-docs.sh`: `doc-lint passed` (Check C: types 492 = 206 + 286; Check F:
  the generated chapters match).

## Rulings

- Ruling: the arity-n call-site rule is a separate path. `abstract_flow_n`,
  `abstract_param_entry_n` and `instantiate_abstract_n` are tried first and answer
  `None` unless the callee has an abstract refinement of arity ≥ 2. The arity-1
  `abstract_flow` / `abstract_param_entry` / `instantiate_abstract` are not edited.
  Why: arity-1 verdicts, details, ledger lines and query texts are then unchanged by
  construction, which the oracle and the unmodified AR groups confirm. Cost if wrong:
  about 350 lines of parallel logic to merge later.
- Ruling: an n-ary application in a definer position under a chain of one domain (a
  tuple domain, s4) is no occurrence at all, and an operator head (`==`, `&&`, any
  non-identifier) is never an n-ary candidate. Why: s4 is "unchanged" in §0, and an
  abstract refinement is an identifier. Without the operator rule the role summary
  under `is_known = fun _ -> false` listed `==`. Cost if wrong: none (those were never
  abstract).
- Ruling: W2's single-slot fix text is the long form (`write `Assoc({x : k | true}, {y
  : v | p(x, y)})``), not the spec's `Map(k[p], v[p])`. Why: in phase 2 that sugar is
  itself two single-slot occurrences, i.e. the W2 error. Cost if wrong: phase 3
  rewords the fix.
- Ruling: W1 also fires when a chain domain has no binder (the shorthand `Int -> Int ->
  Bool[p]`). Its fix then says "name every argument of the callback …". Why: D3; the
  definer cannot apply `p` to an unnamed argument. Cost if wrong: this is exactly the
  AR-phase-4 curried shape, now an error until phase 3's sugar names it.
- Ruling: `curried_lambda` cannot be "proved" through a positive return in phase 2. The
  typechecker gives a curried lambda only to a callee that calls its callback in two
  steps (`callback_arity_mismatch`, probed), and such a body does not prove its return
  (§5.6). The curried instantiation arm is tested through a negative occurrence
  (proved and violated). Through `filt2` it is uninstantiated, naming "`filt2`'s own
  body is not proved". Cost if wrong: none for soundness; the §5.6 todo is the way to
  the positive case.
- Ruling: a lambda whose body relies on a callee precondition (an inlined helper with
  refined parameters) declines for an n-ary `p` (`uninstantiated`, naming the
  precondition). Why: arity 1 discharges each precondition from the definer's domain
  fact over ONE fresh value; doing that over several needs a multi-constant scratch
  query that nothing here needs yet. Cost if wrong: lost proofs for such lambdas.
- Ruling: the conjunction (§4.2 step 4) needs one argument `i` such that every
  type-variable slot `j` of the return has exactly the source `Src_elem (i, [(C, j)])`,
  with the same container and slot for slot. That is stricter than the spec's "the
  same single `Src_elem (j, [(C, _)])`". It conjoins the input's SLOT facts only (the
  brief; phase 1b's ruling). Why: a slot-permuting callee (`Assoc(k, v) -> Assoc(v,
  k)`) would otherwise put key facts on values. The input's relations are not the
  result's entries' relations. Cost if wrong: a lost conjunction for a slot-permuting
  callee.
- Ruling: a type-variable slot's sort comes from the demand (its slot, else a demand
  relation over it), else from the call expression's own type. A slot whose sort is
  still unknown and whose fact is needed makes the call `uninstantiated` ("the element
  type of slot j … is not known here"). That is a decline, never an Int default. Why:
  §2.4 step 1, and AR phase 2's q09b. Cost if wrong: a skip where a sort was knowable.
- Ruling: the verdict is `Proved` only when every obligation `entry_implies` recorded in
  the scratch ledger is proved. Any violated one gives `Too_weak`, naming the callable
  and that obligation's predicate (`` `fn (_k, v) -> v >= 0` does not imply `_ > 0` ``).
  Anything else gives `Undecided`. A declined conjunction appends "; `a`'s own element
  facts are not carried through `g`" (decision 10). Cost if wrong: detail text.
- Ruling: a sort conflict between two applications of one abstract symbol is refused at
  the two discharge sites (`abs_sort_conflict`, the `sort_conflict` skip), not inside
  `abstract_preamble`. Why: the preamble returns text and cannot refuse. Cost if wrong:
  none (unreachable from a W3-clean signature).
- Ruling: the chain signature (§5.3) is built for any chain whose final codomain is
  `{Bool | _ == e}` (both §5.3 shapes have that form). A call with fewer arguments gets
  no fact, because `postcond_of` finds no actual for a parameter `e` names. A chain
  whose `e` names only its first parameter would give a partial call `keep(k)` the
  fact, but the result is a function, so typing keeps it from reaching any Bool or Int
  position. Not guarded; there is no observable case to test. Cost if wrong: a fact
  about a function value.
- Ruling: a negative occurrence that cannot be instantiated records its skip under the
  declared relation's predicate (`p(x, y)`), not `p(_)`. Cost if wrong: ledger text.
- Ruling: inside the declaring definition, a type-variable slot whose binder a
  sibling's n-ary current-abstract application names (`{x : k | true}`) is a slot of
  the relation (§5.2). It is emptied after reading when its own fact is literally
  `true`, so the `ECon` arm owes no `true` obligation for it. Cost if wrong: none.

## Not done

- The sugar (`k -> v -> Bool[p]`, `Map(k[p], v[p])`): phase 3. Today each is a W1 or W2
  error, and the docs say so.
- A curried two-step call inside a body (§5.6): filed as
  `specs/todos/2026-10-21-abstract-curried-two-step-call-no-fact.md`.
- A tuple-component (`~component`) return with an n-ary `p`: the arity-n path answers
  `None` there. That shape is not in the design's scope.
- `Map.filter`: phase 4.
