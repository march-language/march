# A local `fn` with a container return (element-flow follow-ups, phase 3)

Landed 2026-10-18. Design: `specs/2026-10-18-element-flow-followups-design.md`, §5 and
phase 3 of §8 (rows l1-l6 of §0.3). Closes item 3 of
`specs/todos/2026-09-18-refine-element-flow-followups.md`. Built on phase 2
(`6fcef2c9d`, which includes leftovers A+B and the self-call induction gate).

## What a user sees

```march
fn go(k : {Int | _ > 0}) : Int do
  fn two(n : {Int | _ > 0}) : List({Int | _ > 0}) do [n, n + 1] end
  sum_pos(two(k))                     -- was unreflectable-subject; proved
end
fn go2(k : Int) : Int do
  fn bad(n : Int) : List({Int | _ > 0}) do [n, 0] end   -- filed NOTHING; now `0` is violated
  first(bad(k))
end
```

A block-level `fn` whose declared return carries an element refinement gets what
`visit_fn` gives a top-level one: every tail is an element obligation, checked in the
walk with the facts in scope at the tail (so `[n, m]` after `let m = n + 1` proves),
and a tail the walk never reached is checked afterwards in the body's env. When every
tail is proved and the entry is closed, the later calls in the block carry the entry
as their container entry. Before, `visit_local_fn` ran entirely under
`with_no_ret_demand`, so a violating local tail was accepted silently, even under
`cap verified` (`reject/t391`).

## Code

- `Refine_check.ret_elem_demand` gains a fifth component, the verdict cell a failing
  tail clears: `last_elem_return_proved` for a top-level function, the local's own
  `bool ref` for a local. `visit`'s in-walk tail check writes to it.
- `elem_return_tails` / `check_leftover_tails`: `visit_fn`'s tail enumeration (phase
  0's z2 rebinding skip, the inner-binder renaming) and its leftover check, factored
  out unchanged and parameterised by the label, the verdict cell and the env. The
  refine oracle is identical, so the refactor moved nothing for top-level functions.
- `visit_local_fn`: on `elem_refinement ret_ty = Some er` it enumerates the tails over
  the local's walk path, arms `ret_elem_demand` with its own cell, walks, runs the
  leftover check in the body's env (local ctx, path, scope, container env), and on a
  proved verdict with a closed entry that does not mention the enclosing function's
  abstract refinements (G3-4) registers the signature it put into `cbenv` in
  `Refine_param.local_elem_ret_proved` (reset with the other per-module tables).
- `declared_elem_return`'s `cbenv` arm: a signature `List.memq` the table lends its
  closed entry. Any other `cbenv` entry still lends nothing, so a local shadowing a
  top-level function never reaches the global (the arm comes before `resolve_key`), and
  a second local of the same spelling is a different signature.
- The induction gate for a recursive local (`local_elem_self`): while a local with a
  container return is walked, a call whose `cbenv` entry IS that signature (physically)
  is a self-call of the local; an unproved element argument there clears the local's
  cell. The enclosing function's self-calls inside the local keep clearing the global
  `last_elem_return_proved` as before.
- The phase 2 scalar hook for a local's scalar return tail: `visit_local_fn`'s
  `check_fn_post_verdict` now runs under `with_tail_demand (!tail_demand_of ~root
  (local_shadow ctx [n]) defs)`. The hook builds its env from the local's own
  parameters (stripped when the local escapes); the local's name, its sibling locals
  and the enclosing function's parameters are in `ctx.locals`, so a tail call to one of
  them is `Na`, never a same-named global (control: a sibling local `uor` returning -5).
  The post engine's PRE-pass over a clause's locals (`Refine_post.check_fn_post_verdict`)
  keeps `no_tail_demand`: its module-level ctx knows none of those locals. That pre-pass
  only decides what the enclosing function's post engine may assume, so it can only
  lose a proof.
- `Refine_audit.classify` (the `Type_arg` arm for `Param`/`Return`/`Let_annot`/`Field`):
  for a `Local_fn` site, `elem_refinement` is asked under NO abstract refinements, not
  the synthesised local `fn_def`'s. The checker reads a local's slots under the
  enclosing function's abstracts, which the site does not carry; asking under none is
  the conservative answer (a concrete slot is Enforced, an abstract one reports
  unenforced). The controller's review note (the base called a local's container return
  Enforced while nothing checked it) is resolved by the check itself: it is enforced
  now, pinned by two tests.

## Where this departs from the design

- **G3-2 is by construction, not save/restore.** The design (§5.2 step 2) saves
  `last_elem_return_proved`, sets it, walks the local and restores it. That would also
  throw away a clear made inside the local by the ENCLOSING function's own self-call
  (`fn outer(xs) … fn helper(t) do let r = outer(t); [1] end …`): the induction gate's
  note would be lost and `outer` could be admitted. The local writes to a separate cell
  instead, and the global is never touched by the local's tails. Test "the enclosing
  function's self-call inside a local still gates it" pins that; the l5 tests pin the
  isolation (perturbation: the local sharing and resetting the global cell turns
  `sum_pos(outer(true, k))` proved in l5 and its order twin).
- **The induction gate applies to a recursive local** (task requirement; the design's
  G3-3 only says no hypothesis). With no self-call hypothesis the gate is conservative
  for locals: a self-call's result carries nothing anyway.
- **Leftover tails are checked in the body's env**, not a parameter-only env (a local's
  "parameters" include everything captured). In practice no tail is left over: the
  ledger-count pin shows each tail recorded once.
- **The scalar hook for local return tails is included** (the design and phase 2 left
  it out); see Code.
- **G3-5 is `entry_is_closed`**, so a relational entry over the local's OWN parameters
  (`fn f(k : Int) : List({Int | _ < k})`) is checked but lends nothing either. Phase 4
  (relational element returns) is what would lend it.

## Tests

Group `elemflow-local-fn` (18 cases). RED on `6fcef2c9d` (every assertion run
non-fatally; only the first failing value per case shown):

| Case | Base | Now |
|---|---|---|
| l1 `sum_pos(two(k))` | (1, 0, 1), tails file nothing | (4, 0, 0), each tail once |
| l2 `[n, 0]` | (0, 0, 0) | (0, 1, 1), `0` violated |
| l2 under `cap verified` | accepted | rejected; l1 accepted (was rejected) |
| l3 `pass(zs) = zs` | (0, 0, 1) | (0, 0, 2): tail skips, caller skips |
| l4 `let m`; `let ys = two(k)` | (1, 0, 1) | (4, 0, 0) |
| l5 `outer`: `[0]` / local `one(k)` | `one(k)` tail skipped, local tail nothing | `one(k)` proved, `sum_pos(outer(true, k))` STILL skipped (and in the order twin); control with `[1]`: proved (was skipped) |
| enclosing self-call inside a local | local tail nothing | local tail proved, `sum_pos(outer(ys))` still skipped |
| escaping local (`let h = one`) | nothing | tail skipped, lends nothing (G3-1) |
| recursive `keep(t)` tail | nothing | tail skipped, lends nothing (G3-3) |
| recursive with unproved self-call arg | nothing | tails proved, call skipped (gate); control `keep(t, n)`: proved |
| local shadowing a proved global `mk` | local tail nothing | local tail skipped, call skipped; converse (proved local, unproved global): proved; second same-named local after a proved one: skipped |
| captured `k` in `List({Int \| _ < k})`, then `let k = 0` | nothing | tail proved, `sum_neg(f(1))` skipped (G3-5) |
| local after `let k = 0` | nothing | `[5]` violated (reads the current `k`) |
| local parameter `k` in its own return | nothing | `[5] < k` skipped |
| inner `let k = 100` before the tail (G3-6) | (0, 0, 0) | (0, 0, 1), rebinding skip |
| scalar hook, `uor(p, 1)` tail | (1, 0, 1) | (2, 0, 0); controls unchanged: `uor(p, 0)` (1, 0, 1), captured `o` (0, 0, 1), sibling local `uor` (2, 0, 1) |
| audit: a local's container return | Enforced | Enforced (a control: now true) |
| audit: its violating tail `Cons(0 - 1, Nil)` | (0, 0, 0) | (0, 1, 0), an error |

One existing pin moved on purpose: `elemflow-scalar-demand` "return position: the
conservative declines" asserted that a block-level `fn`'s return tail is an
unreflectable-subject skip (phase 2's v1 boundary). It is now proved; the assertion
says so.

Perturbations, each turning exactly the named assertions red (all green otherwise):
the local sharing and resetting `last_elem_return_proved` (l5 and its order twin); no
registration in the table (l1, l4, l5's control, the gate control, the converse, l1
under `cap verified`); the self-call gate off (the gate case); the closed-entry guard
off at registration and lookup (G3-5); no escape stripping (G3-1); a fresh `remaining`
for the leftover check, so every tail checks twice (every ledger count); no scalar hook
(the hook case); the hook without `ctx.locals` (the sibling-`uor` control, a false
proof); the z2 rule off for the local (G3-6); lending by "any registered local" instead
of identity (the second same-named local); a `cbenv` entry falling through to the
global (the shadowing case).

Conformance: `accept/t390` (l1, l4, a top-level tail through a lent local, the scalar
hook; under `cap verified`; rejected on `6fcef2c9d` with 6 skips) and `reject/t391`
(l2 under `cap verified`; ACCEPTED on `6fcef2c9d` with 0 obligations). Corpus 464/464.

## Verification

- `test_refinecheck.exe -e`: 1170 tests, one failure on the first run (the phase-2 pin
  above), fixed; the group re-run green.
- `scripts/run-tests.sh -q compiler`: 1348 pass.
- `check_types.sh`: 464/464.
- `refine-oracle.sh check` against a `6fcef2c9d` baseline (detached worktree at the
  same depth, private HOME): identical, 7786 lines over 549 fixtures. No corpus
  fixture or stdlib module has a local `fn` with a container return, so no new
  obligation appears anywhere. Wall time 6:15 vs 5:53 baseline (+6%, under the 10%
  budget; machine load).
- `stdlib/list.march` (`--check --stdlib-source --refine-report`, private HOME, VC cache
  cleared once): report byte-identical to base (21/0/1 user, 63/0/37 user + stdlib).
  Medians 1.13 s vs 1.10 s (+2.7%; run 1 was faster on this branch, 1.26 vs 1.32 s).
  The design's budget is 2%; the difference is noise-level and list.march has no local
  with a container return, so it exercises no new solver work.
- `test/refine_audit` baselines: unchanged (the audit-baseline suite is green).

## Left open

- A structural self-call hypothesis for a recursive local (G3-3).
- Lending a relational entry over the local's own parameters (phase 4).
- The post engine's pre-pass over a clause's locals still runs without the scalar hook.

## Review follow-up: an escaping local's container parameters (second commit)

A review of `f147461e4` (no false proof) noted that the escape rule stripped
only a local's SCALAR parameter refinements: an escaping
`fn mk(ys : List({Int | _ > 0})) : List({Int | _ > 0}) do ys end` (with
`let h = mk`) still proved its tail from `ys`'s element fact and lent the
entry, contradicting "checked under exactly the parameter facts every call
establishes". Sound only because aliased calls are never lent. Now an
escaping local's parameters enter the container env with no entry (their
names still retire any outer entry they shadow), so G3-1 covers element
facts too. This applies to every escaping local with a container parameter,
not only to ones with a container return.

Test: the G3-1 case gains the escaping `mk` (on `f147461e4`: the tail `ys`
proved and `sum_pos(mk(zs))` lent; now both skip) and its non-escaping
control (proved, lent). `elemflow-*` groups 63/63; `scripts/run-tests.sh -q
compiler` 1348 pass; `refine-oracle.sh check` against the same `6fcef2c9d`
baseline (staged stdlib set aside): identical, 7786 lines over 549 fixtures.
