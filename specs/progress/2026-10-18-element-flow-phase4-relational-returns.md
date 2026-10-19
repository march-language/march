# Relational element returns as call-site facts (element-flow follow-ups, phase 4)

Landed 2026-10-18. Design: `specs/2026-10-18-element-flow-followups-design.md`, §2 and
phase 4 of §8 (rows r1-r6 of §0.4), decision D2. Closes item 4 of
`specs/progress/2026-09-18-refine-element-flow-followups.md` (moved from `specs/todos/`
with this phase: all six items are closed). Built on `72c1eb52a` (phases 0-3 and the
abstract-refinement leftovers A-C).

## What a user sees

```march
fn below(n : Int) : List({Int | _ < n}) do [n - 1, n - 2] end

fn go(k : {Int | _ <= 10}, n : Int) : Int do
  sum_small(below(10))        -- was unreflectable-subject; proved
  let ys = below(k)
  sum_small(ys)               -- proved (k <= 10)
  sum_lt5(below(10))          -- violated (D2): _ < 10 does not imply _ < 5
  sum_small(below(n))         -- skipped: nothing constrains n
  need_lt(below(n), n)        -- proved for any n
end

fn clamp(xs : List(Int), n : Int) : List({Int | _ <= n}) do
  match xs do
    Nil -> Nil
    Cons(h, t) -> if h <= n do Cons(h, clamp(t, n)) else Cons(n, clamp(t, n)) end
  end                         -- both self-call tails proved (were skipped)
end
```

A proved container return whose element refinement names a parameter is a fact at a
call once the call's actuals replace the parameters, the element mirror of
`postcond_of`'s `Relational` arm. Before, `entry_is_closed` kept every such entry from
being a fact anywhere, so every call was an `unreflectable-subject` skip (an error under
`cap verified`).

## Code

- `Refine_check.lend_entry ~formals ~args`: `instantiate_entry ~mode:`Stable` (phase 0's
  machinery: binder renamed to `_`, simultaneous substitution) per top-level slot; a slot
  that cannot move is `None`, and an entry with no surviving slot is `None` so the caller's
  other routes still run. `entry_movable` (every predicate `Closed` or `Relational` over the
  formals) and `uniform_formals` (the first clause's parameter names, only when every
  clause spells them alike).
- `declared_elem_return ?args`: with the actuals, a relational entry of a proved global
  (`elem_ret_proved`, abstract-name guard first, `uniform_formals`, arity = formals) or of a
  registered local (`local_elem_ret_proved`, formals = its own `param_names`) is lent through
  `lend_entry`. Without actuals (a function passed as a value: `demand_flow`'s `Src_cod`
  arm, `check_pass_site_elements`' named arm) closed entries only, as before. A closed
  entry takes exactly the old path.
- `container_entry_of_expr`'s hypothesis arm: a closed hypothesis is the entry as before; a
  relational one is lent at the self-call's actuals, and one whose actuals do not move falls
  through to the parametric rule and the declared return. `elem_ret_hyp` gains a fifth
  component, the formals (`Refine_param`). `visit_fn` builds a hypothesis when every entry
  is closed or movable over `uniform_formals` (it required closed).
- `tuple_self_hyp` and `declared_tuple_return ~args` (leftovers phase C): each relational
  component lent the same way; both call sites (`check_elements`' `$tuple_proj` arm,
  `check_ret_elems`) pass the call's actuals. The `$tuple_proj` record in `lets` is re-read
  at use and retires by mention, so `let (lo, hi) = split(k); let k = 5` drops it.
- `visit_local_fn`: a proved local registers an entry closed **or movable over its own
  parameters** (phase 3: closed only). A captured name is `Unusable` over them, so G3-5
  holds unchanged.
- The `let` walker: an entry naming the bound name itself (`let k = g(k)`) is not stored.
- `Refine_call.check_call` under `~goal_scope_facts`: the names an ACTUAL's own scope fact
  mentions (`$elem : {_ < k}`) load their scope facts the way the goal's names do (so
  `k <= 10` discharges `sum_small(below(k))`), and a name there that no user assumption
  constrains blocks the definite-failure shortcut exactly as phase 0's goal names do.

## The verdict rule (D2 reconciled with phase 0)

D2: an instantiated relational return that fails to imply a call's demand is a
**violation**, through the existing element-subtyping arm (`Element_domain`), the verdict
a variable holding the same entry gets. Phase 0: a goal naming a caller variable that no
fact constrains is not a definite failure. Implemented rule:

- the subtyping arm's definite failure (a solver model refuting the implication) is taken
  only when every caller name in the **demand and the subject's fact** is the subject, a
  parameter of the elem signature, or constrained by a user assumption (a loaded scope fact
  or a translated path condition, phase 0's `constrained_names`);
- otherwise the `¬G` discharge decides: a violation only if no value of the free names
  satisfies the demand, else a skip.

So `sum_lt5(below(10))` (no caller name) and `let ys = below(k)` with `k : {Int | _ <= 100}`
into `_ < 5` (constrained) are violations; `sum_small(below(n))` with `n : Int` is a skip
(n = 5 works, n = 100 does not; design row r5 said violation, the task asked for the skip);
`need_ge(below(n), n)` against `List({Int | _ >= n})` is a violation for every `n`.

The rule applies to every subject fact on that arm, not only lent ones, because a
`let`-stored lent entry and a parameter's own relational entry are indistinguishable there.
So a parameter entry naming an unrefined parameter (`fn f(n : Int, xs : List({Int | _ < n}))`
calling `sum_small(xs)`) is now a skip rather than a violation. That is the conservative
direction (a lost rejection, never a proof); no test or corpus fixture had pinned it, and
the refine oracle is identical. It is pinned now (the r5 case). A reviewer who prefers
the old violation for a function's own PARAMETERS (they are universally quantified, so a
refuting model is a real input) would need phase 0's goal-side rule changed the same way;
this phase keeps the two sides consistent instead.

## Where this departs from the design

- **The r5 verdict** (above): a skip, not a violation, per the task's reconciliation.
- **Two binder-capture holes, one pre-existing**, found probing phase 4's soundness and fixed
  in the same places, because phase 4 made them reachable from calls:
  - a `match` arm binder spelled like a name its slot mentions (`Cons(n, _)` over
    `List({Int | _ < n})`) took the slot as a fact about the NEW `n` (`n < n`), so
    `need_neg(n)` was a **false proof** on the base for a parameter's entry, and with this
    phase also for `match below(k) do Cons(k, _)`. Such a slot (scalar, nested container or
    `Self` entry) now gives no fact;
  - the `let` walker's parametric scalar arm (`let n = hd(xs)`) lacked
    `scope_add_binding`'s self-rebinding guard: also a **false proof** on the base for a
    parameter's entry, and reachable through `hd(nbelow(n))` now.
  `reject/t402` pins the first under `cap verified` (accepted on the base); CHANGELOG
  `### Fixed` names both.
- **`uniform_formals`** is belt-and-braces: desugar collapses a multi-head `fn` into one
  clause before the checker runs, so no test can make two spellings reach it.
- **Stable only, decision 7 kept.** A call actual with a proved postcondition
  (`below(inc(k))`) is not substituted; pinned (with `` `Any `` it reads as a false
  violation, see perturbations).

## Tests

`test/test_refinecheck.ml`, group `elemflow-relational-return` (15 cases, ledger triples,
never exit codes). Run on `72c1eb52a` with this test file (every assertion made non-fatal
to record each value):

| Case | Base | Now |
|---|---|---|
| r1 `sum_small(below(10))` | (2, 0, 1) | (3, 0, 0) |
| r2 `sum_lt5(below(10))`; VC pin `below(10)` + `below(50)` | (2, 0, 1); (2, 0, 2) | (2, 1, 0) and an error; (3, 1, 0) |
| r4 `let ys = below(k)`, inline, `below(k + 1)`, `k <= 100` into `_ < 5`, guard `if k <= 10` | (2, 0, 1) each | (3, 0, 0) / (3, 0, 0) / (3, 0, 0) / (2, 1, 0) / (3, 0, 0) |
| r5 `below(n)` unrefined; `need_ge(below(n), n)`; `need_lt(below(n), n)` | (2, 0, 1) each | (2, 0, 1) **guard**; (2, 1, 0); (3, 0, 0) |
| a parameter's entry naming an unrefined parameter, `sum_small(xs)` | (2, 1, 0) | (2, 0, 1), the documented verdict change |
| caller `let n = 3`: `sum_small` / `sum_lt5`; `mk(b, a)` / `mk(a, b)` | (2, 0, 1) / (2, 0, 1); (3, 0, 1) / (3, 0, 1) | (3, 0, 0) / (2, 1, 0); (4, 0, 0) / (3, 1, 0) |
| named binder `below2(x)` | (3, 0, 1) | (4, 0, 0) |
| unstable `below(f(x))`; `below(inc(k))` | (2, 0, 1); (3, 0, 1) | same (guards) |
| stale: `let k = 5`, `let n = 0` + `need_lt(r, n)`, a `match` binder `k`; control | (2, 0, 1) each | guards unchanged; control (3, 0, 0) |
| unproved `bad(10)` | (3, 1, 1) | same (guard) |
| r6 `clamp` | (4, 0, 3) | (7, 0, 0) |
| `cl1` (`clamp(t, n + 1)`), `cl2` (swapped actuals) | (4, 0, 3) | same (guards) |
| tuple `split(10)`: `sum_small(lo)` / `sum_lt5(lo)`; stale `let k = 5`; tail `split(n)`; `sp` hypothesis; `sp1` (`n + 1`) | (4, 0, 1) / (4, 0, 1); (4, 0, 1); (4, 0, 2); (4, 0, 5); (4, 0, 5) | (5, 0, 0) / (4, 1, 0); guard; (6, 0, 0); (9, 0, 0); guard |
| local `bl(k)`; `bl(10)` into `_ < 5`; stale; captured `j` | (3, 0, 1) each | (4, 0, 0); (3, 1, 0); guard; guard |
| binder capture: param `Cons(n, _)`; `below(k)` `Cons(k, _)` (inline, `let`); control `h - k` | **(3, 0, 0) false proof**; (2, 0, 1); (2, 0, 1) | (2, 0, 1); guards; (3, 0, 0) |
| `let n = hd(xs)` param; `hd(nbelow(n))`; control `h` | **(4, 0, 0) false proof**; (5, 0, 1); (5, 0, 1) | (3, 0, 1); guard; (6, 0, 0) |
| `let k = below(k)`; `apply1(below, 10)` (a value) | (2, 0, 1) each | same (guards) |
| `cap verified`: r1 / r2 | rejected / rejected | accepted / rejected |

**Perturbations** (each one source change, the `elemflow-*` groups re-run, 79 cases; no
other group moved under any of them):

| Change | Reddens |
|---|---|
| no global relational lending | r1, r2, r4, r5 (two), the substitution, named-binder, stale control, r6, both binder-capture controls, `cap verified` r1 |
| global lending RAW (no substitution) | as above, plus `let n = 3; sum_lt5(below(10))` **proved** (the namespace pin) and `mk(b, a)` violated |
| `` `Stable `` → `` `Any `` | `below(inc(k))` (becomes a false violation) |
| hypothesis closed-only | r6, `sp` |
| hypothesis RAW | `cl1`, `cl2` (both turn (7, 0, 0)) |
| tuple declared return closed-only | the four `split` cases, `sp`'s caller |
| tuple hypothesis RAW | `sp1` (turns (9, 0, 0)) |
| local registration closed-only; local lending RAW | `bl(k)`, `bl(10)` |
| no subject-fact loading in `check_call` | the `k`-bounded r4 cases, `mk`, `below2`, local `bl(k)` |
| no subject-fact free-name rule | r5 `below(n)` (turns a violation) |
| no `match` binder guard | the three `Cons(n/k, _)` cases |
| no `let` scalar self-mention guard | both `hd` cases |
| no `let` container self-mention guard | nothing (stated in the test: the new `k` is a list, so no verdict depends on it; defence in depth) |

Conformance: `accept/t400_refine_relational_element_return` (r1, r4, both-sides, `clamp`,
tuple, local; `cap verified`, 16 proved; rejected on the base with 9 skips),
`reject/t401_refine_relational_element_return_violated` (r2; accepted on the base) and
`reject/t402_refine_element_binder_captures_slot_name` (the pre-existing false proof;
accepted on the base). `check_types.sh`: 469/469 (198 accept, 271 reject).

## Verification

- `test_refinecheck.exe -e`, private HOME, `.march/cas/vc` cleared once: 1212 tests, all
  pass, 0 `[SKIP]` (522 s).
- `scripts/run-tests.sh -q compiler`: 1348 pass.
- `scripts/refine-oracle.sh` baseline on `72c1eb52a` (detached worktree at the same depth,
  `_build/default/stdlib` deleted in both), check on this change: **identical**, 7786 lines
  over 549 fixtures. Blind to this change as phase 0's oracle was: no corpus fixture or
  stdlib module declares a relational element return (and `conduit`/`depot` have no
  element-refined slot at all, grepped). The evidence is the test group and the corpus.
- `stdlib/list.march` ratchet (`--check --stdlib-source --refine-report`, private HOME,
  VC cleared once, base and branch interleaved, load ~9-10): both 77 proved, 37 skipped
  (ceiling 37); user slice 35/0/1 on both. Medians of runs 2-4: base 1.23 s, branch 1.24 s
  (+0.8%, budget 5%).
- `test/refine_audit` baselines: unchanged (the `audit-baseline` group passes).

## Left open

- A function passed as a value lends only a closed entry (no actuals to substitute).
- A local `fn`'s tuple return still lends nothing, and a recursive local still has no
  self-call hypothesis (G3-3).

## Review follow-up: a definite violation needs a fully seen path (second commit)

An independent review of `8e5c15c48` (no false proof) found a CORRECT program reported as
a definite violation:

```march
fn small(k : Int) : Bool do k < 5 end
fn r1(k : {Int | _ <= 100}) : Int do
  if small(k) do need_lt5(below(k)) else 0 end   -- "violated (e.g. k = 6)"
end
```

also through `let ys = below(k)`, a literal arm `match k do 3 -> …`, and (already on
`72c1eb52a`) a parameter's own entry, `fn f(k : {Int | _ <= 100}, ys : List({Int | _ < k}))`
with `if small(k) do need_lt5(ys)`. The element-subtyping arm took a solver model as a
definite counterexample once every caller name was "constrained" (here by `k <= 100`),
but the query did not contain the untranslated guard, so `k = 6` was a state the program
never reaches. The scalar twin `n5(k)` never takes that shortcut and was a skip.

**Rule now.** On the definite-failure shortcut (`Element_domain`, and the two callback
subjects), when the goal or the subject's fact names a caller variable, the path to the
call must be fully seen: no path condition that failed to translate exactly (dropped, or
stood up as a call constant), and no opaque marker. Otherwise the `¬G` discharge decides
(a violation only if no state satisfies the demand), else a skip, which is how the scalar
path decides. A goal and fact naming no caller variable (`sum_lt5(below(10))`, phase 0's
literal demands, the callback-domain pass sites) are decided by the contracts alone, as
before.

**The opaque marker** (`Refine_scope.opaque_path_marker`): a path entry that reads as
`true` to every consumer and that `check_call` detects (`path_is_opaque`). The walk pushes
it for a `match` arm whose reachability it does not record: a pattern other than a
variable, wildcard, Bool or Int literal, all-irrefutable tuple, or a registered
constructor with irrefutable fields over an unshadowed variable scrutinee; or an arm after
an earlier one whose failure is not recorded (anything but an unguarded Bool/Int literal or
a tag-only constructor arm over a variable scrutinee). Also every `match do` (cond) arm
after the first, whose earlier conditions' negations were never pushed. `tails_bound`
pushes it for every `match` arm but an irrefutable first one and every later cond arm, for
the checks that read its paths (lambda tails, leftover return tails).

**Int literal arms are now facts:** inside `3 ->` the path holds `subj == 3`, and past an
unguarded `3 ->`, `subj != 3` (the Bool-literal arms' rule). So `match k do 3 ->
need_lt5(below(k))` proves rather than skips, and `match k do 5 -> 0  _ ->
need_lt4(below(k))` with `k <= 5` proves.

Tests (group `elemflow-relational-return`, new case "a path the query does not fully see
is never a definite violation"; each RED was `(2, 1, 0)` on `8e5c15c48`):

| Shape | `8e5c15c48` | Now |
|---|---|---|
| `if small(k)`: `need_lt5(below(k))`; via `let ys` | (2, 1, 0) | (2, 0, 1) |
| `match k do 3 -> need_lt5(below(k))` | (2, 1, 0) | (3, 0, 0) |
| parameter entry under `if small(k)` (p6_param); under `Some(3) ->` | (2, 1, 0) | (2, 0, 1) |
| `match k do 5 -> 0 _ -> need_lt4(below(k))`, `k <= 5` | (2, 1, 0) | (3, 0, 0) |
| `match (k, 0) do (5, _) -> 0 _ -> …` (unrecorded earlier arm) | (2, 1, 0) | (2, 0, 1) |
| `match do k >= 5 -> 0  true -> need_lt5(below(k))` | (2, 1, 0) | (2, 0, 1) |
| controls: `if k < 10` (translated, still admits 9), no guard, closed `below(10)` under `if small(k)`: violated; `if k < 5`: proved | same | same |
| a lambda tail under `(5, _) -> [0]` (guard: a refuted lambda source is a demand-flow skip by design) | (2, 0, 1) | (2, 0, 1) |

Perturbations (the `elemflow*` groups, 80 cases): no path rule reddens every skip row
above; no untranslated-condition tracking reddens the three `if small(k)` rows; no match
marker reddens the `Some(3)` and `(5, _)` rows; no Int-literal fact reddens `3 ->`; no
Int-literal exclusion reddens `5 -> 0 _ ->`; no cond marker reddens the cond row. Removing
`tails_bound`'s marker reddens nothing: through `demand_flow` a refuted lambda tail is
already a skip, and no test reaches a leftover return tail with a match path; it is kept
as defence in depth.

Verification: `test_refinecheck.exe -e` (stdlib re-staged with `dune build --root .
@stdlib/default` and compared, `.march/cas/vc` cleared once): 1213 tests, all pass, 0
skipped. `scripts/run-tests.sh -q compiler`: 1348 pass. `check_types.sh`: 469/469.
`refine-oracle.sh check` against the same `72c1eb52a` baseline (staged stdlib set aside to
match the baseline's environment): identical, 7786 lines over 549 fixtures, so neither the
new Int-literal facts nor the marker moved any corpus or stdlib line.

## Second review follow-up: let-bound locals in a guard (third commit)

A re-review of `fece9d212` (no false proof, ~40 Int-literal attack shapes) found one more
false violation:

```march
fn c1(k : {Int | _ <= 100}) : Int do
  let ok = k < 5
  if ok do need_lt5(below(k)) else 0 end      -- "violated (e.g. ok = true, k = 6)"
end
```

and its parameter-entry twin. The guard `ok` translated exactly, so the path counted as
fully seen, but nothing tied `ok` to `k < 5`.

**Fix, two parts.**

1. **A Bool local bound to a comparison or connective is read as it.** `check_call` rewrites
   a path condition's `ok` to `k < 5` through `lets` (the laundering channel, which already
   records `ok -> k < 5` and retires it when `ok` or anything it mentions is rebound). A
   self-mentioning entry (`let k = k < 5`) is not used. This is a new exact fact for every
   check, so the scalar twin `let ok = k < 5; if ok do n5(k)`, a skip before, is now proved.
2. **Opaque names** (`Refine_scope.opaque_name_marker`, a path entry reading `true` that
   carries one name). The walk tags a local whose value the query does not pin down: a
   `let` binder unless its RHS is a literal, an admitted equality, an `if` of admitted
   arms, or a comparison/connective (each not mentioning its own binder or a tagged name);
   every name whose defining fact (a path equality, a `lets` entry, a scope fact) a
   rebinding retires by mention; a `match` arm's binders unless the scrutinee is an
   untagged variable; a lambda's and a local `fn`'s parameters and a `let?`/`let*` binder
   (`rebind_opaque`). `check_call` then takes no model as a definite counterexample when
   a path condition (after part 1) or the demand/subject fact names a tagged name. Tags
   are never retired, so a later rebinding only loses violations.

Tests (same group, new case "a let-bound Bool guard is read through its definition, or is
opaque"; `fece9d212` value first): c1 (2, 1, 0) → (3, 0, 0); the parameter twin (2, 1, 0)
→ (3, 0, 0); the scalar twin (2, 0, 1) → (3, 0, 0); `let k = 7` after `let ok` (2, 1, 0) →
(2, 0, 1) (the old fact neither proves nor gives a definite verdict); `let ok = small(k)`,
`let ok = if k < 5 do true else false end`, `need_lt(below(k), m)` with `m = two100(k)`
(post `_ > 0`, really 200), `Some(j)` out of `let o = Some(k)`, `(j, _)` out of `let t =
(k, 0)`, `Some(b)` out of `let o = Some(k < 5)`: each a false violation → a skip.
Control: `let ok = k < 10; if ok do need_lt5(below(k))` is a **definite violation** (the
definition is recorded, so `k = 9` is a real counterexample); unchanged.

Perturbations (each reddens the case; first failing assertion shown by alcotest): no
`lets` read-through (c1); every `let` binder treated as pinned (`small(k)`); no tagging of
names a rebinding unties (`let k = 7`); no match-binder tags (the tuple case, the only
shape where no tester on the scrutinee catches it); no path-name check (c1's rebinding
case); no demand-name check (`m = two100(k)`). Not observable: the lambda / local `fn` /
`let?` tags (`rebind_opaque`); no test reaches a definite element violation whose demand
or path names such a binder with a constraining fact, so they are defence in depth.

Verification: `elemflow*` groups 81 pass; `test_refinecheck.exe -e` (stdlib re-staged and
compared, VC cleared once) 1214 pass, 0 skipped; `scripts/run-tests.sh -q compiler` 1348
pass; `check_types.sh` 469/469; `refine-oracle.sh check` against the `72c1eb52a` baseline
(staged stdlib set aside to match it): identical, 7786 lines over 549 fixtures.
