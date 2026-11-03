Refinements: soundness fixes from the whole-branch review of two-argument abstract refinements

The single fix pass after a soundness review of phases 1a-4 of
`specs/2026-10-18-abstract-refinements-multi-arg-design.md` (`d053b4bdb`, `eedd5a35f`,
`38635a08f`, `0f99036c3`, `591160909`; notes `specs/progress/2026-10-21-abstract-multiarg-phase{1a,1b,2,3,4}.md`).
Every finding was confirmed by the reviewer with a repro program; each is now a test in
the new group `abstract-multiarg-review` (`test/test_refinecheck.ml`, 17 cases, registered
after `abstract-map`), written first and watched failing on the base build.

## Findings, before / after

The repros are the reviewer's programs, run as `march --check --refine-report
--refine-report-sites` under a private `HOME` (user-code ledger shown).

| # | Repro | Before (`591160909`) | After |
|---|---|---|---|
| C1 | f1v: `consume(ACons(1, 2, ANil), fn (_k, _v) -> false)`, `consume` relying on `p` | 1 proved, 0 violated (the call owes nothing) | violated: "the entry (1, 2) passed to `consume` does not satisfy precondition `false`" |
| C1 ctl | f1d: `fn (k, _v) -> k > k` | violated, "`$s0 > $s0`" | violated, "`k > k`" |
| C2 | f2: `keep : ({x : Int \| true}) -> ({y : Int \| true}) -> {Bool \| _ == (x > 0)}`, body `if keep(k, v) do need_pos(k)` | 3 proved | `need_pos` skipped (`unconstrained-subject`) |
| C2 ctl | f2c: the one-argument codomain | the lambda's postcondition obliged (skip) | unchanged |
| C3 | d1: real `Map.filter(m, fn k -> fn k -> k > 0, …)` into `need_keys` | proved | uninstantiated: "the lambda passed for `p` binds `k` twice" |
| C3 | d2: `filt(a, fn (x, x) -> x > 0)` | proved | uninstantiated, "binds `x` twice" |
| C3 | d3: d1 run (`first_key(Map.filter(…))` is `-5` at run time) | proved | uninstantiated |
| C4 | n1: return `{y \| p(x, y) && y > n}`, call `filtn(a, 0, …)`, caller has `n : {Int \| _ > 1000}` | proved (`n` read as the caller's) | too-weak: "`fn (_k, _v) -> true` does not imply `_ > 100`" |
| C4 ctl | n1b: the caller's parameter is `m` | solver-undecided | too-weak (same as n1) |
| C4 | n3: parameter `{y \| p(x, y) && y > n}`, call `consume(ACons(1, 5, ANil), 100, …)`, caller `n : {Int \| _ == 0}` | proved | violated (`5 > 100` is false) |
| C4 ctl | n3b: the caller's parameter is `m` | solver-undecided (`y > n`) | violated |
| I1 | c1: `Assoc({x : Int \| x < y}, {y : Int \| y > x})` | crash, `Invalid_argument("option is None")` | 2 proved (one relation per slot) |
| I2 | o1: `type Two(k, v) = Two((List(k), List(v)))`, relation projected | `need_pos(t)`, `need_pos(mk())` proved, no warning | both skipped, `refinement_unchecked` warning "…holds the value for `x` inside `(List(k), List(v))`, which is not one entry of the related slots…" |
| minor | f1b: violation text | "precondition `$s0 > $s1`", "e.g. `if $s0 > $s1 do`" | "`k > v`" |
| minor | n4: violation text | "`$s1 > $s0 + 100`" | "`y > x + 100`" |
| minor | h1 (with `filt3[w : Eq]`, which typechecks): input `w` fact through a non-parametric `w` | proved | skipped (solver-undecided) |

## What changed

- **C1** (`lib/refinecheck/refine_check.ml` `instantiate_nary_entry`): a relation whose
  instantiated predicate names none of its slots keeps its original `rel_args`, so it is
  owed on the want side and is the (sound) fact it is on the have side, instead of being
  cut to `[]` and dropped by `normalize_entry`. `entry_implies` records a skip for a want
  relation with no slots instead of answering `true` (unreachable now; defence in
  depth). `normalize_entry`'s zero-slot drop is documented as unreachable; its I1 path
  (one slot) conjoins and was already sound.
- **C2** (`lib/refinecheck/refine_scope.ml` `chain_sig_of_ty`): the n-parameter callback
  signature is built only for shape (i), `{Bool | _ == p(x1, …, xn)}` with `p` a current
  abstract refinement applied to the chain's own binders in order. Shape (ii) falls back
  to the one-parameter signature (no fact). `lib/refinecheck/refine_resolve.ml`
  `postcond_of_declared`: a callback signature of n ≥ 2 parameters called with a
  different number of arguments resolves to no fact, whichever binders the definition
  names (the reviewer's minor; with shape (i) only this was already true because `p(x1,
  …, xn)` names every binder, so it is pinned by the existing `partial_call_no_fact`).
  `lib/refinecheck/refine_audit.ml`: `site_callback_sig` asks `callback_sig_of_ty` under
  the site function's abstract refinements (as the checker does inside the walk), so a
  definer chain stays `Enforced` and a shape (ii) chain codomain is honestly
  `Unenforced` (it was reported enforced while nothing checked it).
- **C3** (`refine_check.ml`): `duplicate_binder` (any name but `_` spelled twice).
  `instantiate_abstract_n` declines a lambda (uncurried, or a curried chain after
  `peel`) that binds a name twice; `inline_bool_body` declines a `let`-bound lambda
  called inside a body that does; `named_predicate_n` gives no contract for a function
  with a doubled parameter; `postcond_of_declared` lends no relational postcondition that
  names a doubled formal. The arity-1 path and named-predicate instantiation could hit
  the same problem through `inline_bool_body` and `named_predicate_n`, both shared, so
  they are fixed there (test "C3 arity 1"). The two backends disagree about which
  binding a doubled name means (interpreter: the first, compiled: the last; measured,
  filed as `specs/todos/2026-10-21-duplicate-binder-interp-compiled-divergence.md`).
- **C4** (`refine_check.ml`): `abstract_flow_n` moves the instantiated return entry to the
  call's actuals with `instantiate_entry ~mode:`Stable ~formals:(sig_of_fn fd).param_names
  ~args` and declines (uninstantiated, naming why) when that fails;
  `abstract_param_entry_n` does the same with `` `Any `` (a demand used once, as
  `check_arg_elements`' ordinary arm does at line ~4067).
- **I1** (`refine_scope.ml` `elem_app`): every slot's binder and sort marker are read
  from a snapshot taken before the loop that empties slots.
- **I2** (`lib/refinecheck/refine_encode.ml`): new table `ctor_field_joint` (per
  constructor field, the type parameters that are direct arguments of the field's own
  type application), registered beside `ctor_field_params` and cleared with it.
  `entry_shaped`'s opaque (vacuous) case now requires every field hiding a related slot
  to be one type application naming all the related slots directly.
- **Minor, `$s` binders** (`refine_check.ml`): `instantiate_entry` substitutes a
  relation's formals in place, keeping the declared binders, when no actual mentions
  one of them (otherwise it still renames to `$s<j>`). `instantiate_nary_entry`'s
  `source_binders`: a relation that is exactly `p($s0, $s1)` over synthetic binders
  (the sugar's expansion) takes the binders of the callable it is instantiated from
  (`fn (k, v) -> k > v` gives `k > v`) when those are distinct plain names.
- **Minor, conjunction** (`abstract_flow_n`): the input entry's slot `j` joins the
  produced entry only when slot `j`'s type variable is one of the gated positive bases
  or passes `parametric_ok` on its own.
- **I3 guard** (`abstract_flow_n`, `abstract_param_entry_n`): an instantiated entry that
  still applies one of the n-ary abstracts (an application `subst_abstract_n` did not
  reach, e.g. inside a nested container slot) declines instead of being read in the
  caller's namespace.

## I3: the arity-1 declines and their n-ary counterparts

| Arity-1 guard | Where | N-ary counterpart |
|---|---|---|
| a registered ONE-parameter container | `abstract_slot_of_ty` | any registered container through `elem_app`, W4 `entry_shaped` (now with I2) |
| one abstract per slot | `abstract_slot_of_ty` | several n-ary abstracts instantiated together (`inst_all`); mixed arities declined in `abstract_flow_n` ("different arities") |
| a base with an SMT sort | `abstract_slot_of_ty` | `elem_app` reads only sorted bases or type variables; a type-variable slot's sort from the demand/call, else `Error j` (declined) |
| `p` only as `p(binder)` under `&&`/`\|\|`/`!` | `abstract_slot_of_ty` (`slot_mentions_only_applied`) | W2 at the declaration (distinct sibling binders); NEW: the post-instantiation `entry_mentions nary` guard on both sides |
| the slot closed over its binder | `abstract_slot_of_ty` (`classify_pred bn [] rest`) | NEW (C4): moved to the actuals by `instantiate_entry`, declined when it cannot move |
| element return proved or assumed | `abstract_flow` | present (`elem_ret_proved \|\| elem_ret_assumed`) |
| parametric gate, P1 for an assumed callee | `abstract_flow` | present, over `positive_bases` |
| no gate and no conjunction for a concrete base | `abstract_flow` | bases filtered to type variables; conjunction only over type-variable slots |
| conjunction through one `Src_elem` source, never for an assumed callee, outside `inst` | `abstract_flow` | present (stricter, slot for slot); NEW: per-slot parametric gate |
| element sort from the demand or concrete base | `abstract_flow` | demand marker, else the call's own type, else declined |
| a tuple component | `abstract_flow ?component` | n-ary answers `None`; the arity-1 rule then finds no one-parameter slot (probe `tup2`: a skip) |
| an unreadable slot is a recorded skip, never a fall-through | `abstract_param_entry` | an entry mentioning the n-ary abstract is instantiated or declined (`Error`, recorded as uninstantiated); a nested one is now caught by the I3 guard (probe `nest2`: was `unreflectable-predicate`, now uninstantiated) |
| unknown element sort declines | `abstract_param_entry` | present (`Error j`) |
| a lambda of exactly one parameter | `instantiate_abstract` | n parameters, uncurried or a peeled curried chain; NEW: no doubled binder |
| reading by `inline_bool_body`, closed over the parameter | `instantiate_abstract` | `classify_pred "$no_binder" ys r <> Unusable` (Closed or Relational over `ys`) |
| inlined preconditions discharged from the domain fact | `instantiate_abstract` | declined (phase 2 ruling: no multi-constant scratch discharge) |
| `let`-bound lambda naming itself (C5) | `instantiate_abstract` | present |
| by name: one parameter, preconditions discharged | `instantiate_abstract` | n parameters, declined when any precondition (phase 2) |
| neither lambda nor name; no definer argument | `instantiate_abstract` | present |

No shared helper was factored out of the arity-1 code; only `duplicate_binder` is new
and shared, and the arity-1 functions are otherwise untouched.

## Tests

Group `abstract-multiarg-review`, 17 cases. RED evidence: the final test file was built
and run against a worktree of the base `591160909` with only `test/test_refinecheck.ml`
replaced: `14 failures! in 0.256s. 17 tests run.` The passing ones there are controls by design (marked "ctl").
RED lines (assertion, Expected → Received):

| # | Case | RED on base |
|---|---|---|
| 0 | C1 f1v: `fn (_k, _v) -> false` at a parameter owes the relation | `consume`: `[violated]` → `[]` |
| 1 | C1 ctl f1d: `fn (k, _v) -> k > k` violated | passes on base (control) |
| 2 | C1 have side: `filt(a, fn (_k, _v) -> false)` lends `false`; `true` lends nothing | `[proved]` → `[(skipped, solver-undecided)]` |
| 3 | C2 f2: a concrete chain codomain gives no fact | `need_pos: nothing proved` `false` → `true` |
| 4 | C2 ctl f2c: a one-argument codomain is obliged at the pass site | passes on base (control) |
| 5 | C2 ctl: a definer chain still proves `filt`'s return | passes on base (control) |
| 6 | C2 audit: shape (ii) codomain unenforced, definer enforced | `shape (ii)`: `["Unenforced"]` → `["Enforced"]` |
| 7 | C3 d2: `fn (x, x) -> x > 0` uninstantiated, "binds `x` twice"; ctl `fn (x, y)` proved | `[uninstantiated]` → `[proved]` |
| 8 | C3 d2': curried `fn k -> fn k -> k > 0` at a negative occurrence | `[uninstantiated]` → `[proved]` |
| 9 | C3 d1: real `Map.filter`, "binds `k` twice"; ctl `fn k -> fn _v -> k > 0` proved | `[uninstantiated]` → `[proved]` |
| 10 | C3 arity 1: `let h = fn (a, a) -> a > 0` inlined, `two(a, a)` by name and as a postcondition; ctl `(a, b)` proved | `let-bound (a, a)`: `[uninstantiated]` → `[proved]` |
| 11 | C4 n1 / n1b (too-weak both), n1c `filtn(a, 200, …)` proved | `n1`: `[too-weak]` → `[proved]` |
| 12 | C4 n3 / n3b (violated both), a satisfying entry proved | `n3`: `[violated]` → `[proved]` |
| 13 | I1 c1: no crash, (1, 2) proved, (2, 1) violated | `[invalid] option is None` |
| 14 | I2 o1: `refinement_unchecked` warning, nothing proved | `warned:` `true` → `false` |
| 15 | minor f1b / n4: `k > v`, `y > x + 100`, no `$s` | `f1b names k > v`: `true` → `false` (base text `$s0 > $s1`) |
| 16 | minor h1: bounded `w` not proved; ctl unbounded `w` all proved | `bounded w: nothing proved` `false` → `true` |

The edited `cb_passthrough` on base: `[uninstantiated]` → `[proved]`.

Edited existing test, deliberately: phase 2's `cb_passthrough` (`abstract-multiarg`) was
"a chain-typed callback parameter passed on is proved". Its callback is shape (ii), a
concrete `{Bool | _ == (y > x)}`, which by the C2 ruling carries no contract, so it now
asserts `[uninstantiated]` and the detail "`kk`, passed for `p`, has no proved …". The
proof it pinned was the unsound direction of C2: nothing obliged the callable passed for
`kk` at `go`'s callers.

## Verification

- `scripts/refine-oracle.sh`, baseline taken at `591160909` before any edit (549
  fixtures, 8726 lines), private `HOME`: `REFINEMENT DIAGNOSTICS IDENTICAL (8726 lines over 549 fixtures)`, after the fixes and again on the final binary. The corpus has no relation whose
  instantiated predicate is constant, no shape (ii) chain, no doubled binder, no
  callee-parameter mention in an n-ary slot and no tuple-hiding opaque container, so
  nothing could move, and nothing did.
- The oracle was shown to go RED: `duplicate_binder` perturbed to decline every
  non-empty list gave `DIAGNOSTICS CHANGED — 1656 differing lines` (e.g.
  `native_actor_call_canonical: skipped (abstract-refinement-uninstantiated): 15`, the
  stdlib's named predicates no longer reflected). The file was restored (`cmp` against
  the saved copy) and rebuilt.
- `--refine-audit`, base binary vs this one, private `HOME`, on every file with a chain
  definer (`r20`, `p43`, `t455`, `t456`, `stdlib/map.march`): identical. (A first
  version without `site_callback_sig` turned each definer's codomain into an
  unenforced site; that is why the audit asks under the site's abstracts.) Shape (ii)
  repro f2: `4 enforced` → `3 enforced, 1 unenforced` (the honest answer).
  `test/refine_audit/*.baseline` (group `audit-baseline`) not regenerated; it passes.
- `scripts/run-tests.sh` (z3 on PATH): `All suites passed.`, exit 0. compiler 1451, eval 289, codegen 719, run_stdlib 896, stdlib_march 80, jit 43, lsp 383 + 5 + 37 + 10 + 8, refinecheck 1498 (1481 + 17), errors 290.
- `scripts/check-docs.sh`: `doc-lint passed` (Check F: `docs/refinement-types.md` regenerated by `scripts/gen-lang-docs.py`).

## Rulings

- Ruling (controller, recorded): the n-parameter chain signature is built ONLY for
  shape (i), a definer of a current abstract refinement; shape (ii) reverts to the
  one-parameter behaviour (no fact). Why: shape (ii) gave the body a fact no pass site
  checked (f2 proved; the base `fa70709af` errors). Cost if wrong: shape (ii) chains
  instantiate nothing until the pass-site obligation in
  `specs/todos/2026-10-21-chain-predicate-contract-pass-site.md` lands.
- Ruling: shape (i) is matched strictly, `p(x1, …, xn)` with exactly the chain's
  binders in order (what W1 requires of a well-formed definer). Why: anything else is
  not a definer and would bring shape (ii)'s hole back. Cost if wrong: none (a
  malformed definer is a W1 error anyway).
- Ruling: a partial call through an n ≥ 2 callback signature gets no fact
  (`postcond_of_declared`), explicitly, rather than "it happens to name every binder".
  Cost if wrong: none observable.
- Ruling: a zero-slot relation keeps its original slots (rather than being conjoined
  into one slot). Why: it is the same predicate over the same entries, and on both sides
  it is then read by the one routine that reads relations. Cost if wrong: none; a
  closed predicate is checked once per entry either way.
- Ruling: duplicate binders are DECLINED, not alpha-renamed. Why: the backends disagree
  on which binding the body sees (interpreter first, compiled last), so no renaming is
  right for both. `_` is exempt (it binds nothing). Cost if wrong: such lambdas
  instantiate nothing; the typechecker should reject them (todo filed).
- Ruling: the duplicate-formal decline also covers `postcond_of_declared`'s relational
  arm, a path outside abstract refinements. Why: it is the same positional
  substitution and `inline_bool_body`'s named-helper row uses its contract; a doubled
  formal there lent `two(y, 1) == (y > 0)`. Cost if wrong: a lost fact for a function
  nobody should write.
- Ruling: C4 substitutes the actuals rather than requiring closedness: `` `Stable `` on
  the return side (as `lend_entry`), `` `Any `` on the parameter side (as
  `check_arg_elements`' ordinary arm). Why: the arity-1 closedness decline would lose
  n1c (`filtn(a, 200, …)` proved). Cost if wrong: an unstable actual on the return
  side declines.
- Ruling (I2): the vacuous opaque case is admitted only where every field hiding a
  related slot is one type application naming all of them directly (`HEntry(k, v)`),
  not "only for `ptype`". Why: it keeps `Map` (`HamtMap(HEntry(k, v))`) entry-shaped,
  rejects o1, and needs no visibility in the checker's tables (`ptype` is not recorded
  there). Cost if wrong: a user type `Box(Pair(k, v))` whose `Pair` stores keys and
  values apart is still admitted; its constructions are phase 0's recorded skip, so only
  an `@[assume]`d or declared value can carry such a relation.
- Ruling: c1's two slots naming each other give two relations (`x < y` and `y > x`),
  not one conjoined relation. Why: that is what `elem_app` builds from a snapshot, and
  each is checked. Cost if wrong: two ledger entries where one would do.
- Ruling: `$s<j>` binders are renamed to source binders only when it is capture-free by
  construction (no actual mentions a relation binder; or the relation is exactly
  `p($s…)` and the callable's binders are distinct plain names). Otherwise the `$s`
  names stay. Cost if wrong: an occasional `$s0` in a message.
- Ruling: the input conjunction is gated per slot (`List.mem b bases ||
  parametric_ok ctx g [b]`). Cost if wrong: a lost conjunction for a slot whose
  variable fails the gate alone.

## Not done

- The shape (ii) pass-site obligation (todo filed).
- Rejecting doubled binders in the typechecker (todo filed).
