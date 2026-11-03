# Refinement demand chains: C1 (callee post at a return tail) and G1 (relational scalar return)

Closes `specs/progress/2026-10-21-refine-post-through-callee-post-unproved.md` (C1, tail form)
and `specs/progress/2026-10-21-refine-relational-scalar-return-not-lent.md` (G1), rows C1/G1 of
`specs/2026-10-20-refinement-suggest-lite-design.md` §0, and the §3.3 demand chain they block.
Branch `claude/refine-demand-chains`, base `1686cb24d`.

## Causes

**C1.** `check_post` (`lib/refinecheck/refine_post.ml`) reflects a scalar tail through
`smt_of`, which has no call resolver. So a tail `a(x)` was `unreflectable-subject`, even
though the gate (`gate_unverified_posts`) already ran as a fixpoint with a `post_lookup` of
proved contracts. The lookup was read only by the Tier-2 datatype path, by measures of calls
on a list return, and by guards. The scalar tail never consulted it. Not an ordering problem:
the rounds already admit a contract the moment it proves.

**G1.** The relational return *was* instantiated at the actuals (`postcond_of_declared`'s
`Relational` arm), giving `inc$ret1 > n`. The caller name `n` it then mentions reached the
query through `check_call`'s `foreign_var`, which declares the name but does not load the
name's own scope fact (`n >= 0`). The VC was `inc$ret1 > n ∧ ¬(inc$ret1 > 0)`, which is
satisfiable both ways. Nothing was dropped as "not closed".

**Found on the way: a binder capture (unsound, pre-existing).** `postcond_of_declared` (and
the local-`fn` twin `ret_instance`) substituted actuals into a relational return without
first renaming a *named* binder apart. With `fn inc(x : Int) : {r : Int | r > x}` and a
caller variable `r`, `inc(r)` lent `r > r`. Every consumer reads the binder as the returned
value, so that became `inc$ret1 > inc$ret1`, a false assumption. `need_neg(inc(r))` was
**proved** on base. This is the scalar twin of the element path's C4 capture, which
`instantiate_entry` already guards by renaming the binder to `_`.

**Found on the way: undeclared sibling in post scope facts (pre-existing, CI `z3-well-formed`).**
`scope_facts` loaded `k : {Int | _ > x}` with `x` resolved to a bare `Const x` and never
declared when `x` is an unrefined sibling. z3 rejected the query (`unknown constant x`) and
the return was a silent skip. The trigger was the G1 inference fixture's `need_gt` return
probes. It also hid a real violation: `fn f(x : Int, k : {Int | _ > x}) : {Int | _ > 0} do k
end` was a skip on base and is now `violated`.

**Found on the way: inference probes lent unproved returns (pre-existing).**
`Precond_infer.walk_ledger` and the oracle's `prepare` used `collect_all_defs` without the
gate. So in a probe every declared return travelled, proved or not, and
`--refine-infer-apply` failed its own re-check on base: `f(x) = f(x)` with a declared
`{Int | _ > 0}`, exit 3, "predicted 1 skipped, got 2". C1 widened this, because the
probe's own post check would then use its own unproved return.

## Fixes

- `refine_post.ml` `check_post`: when the scalar tail does not reflect and is a direct call,
  `scalar_call` mints `f$ret<N>` at the return's own scalar sort (`?ret_scalar`, from
  `check_fn_post_verdict_core`). It carries `post_lookup`'s contract conjunct by conjunct:
  the same rule `reflect_scalar` uses for an argument. A conjunct that does not reflect (a
  nested call in an instantiated relational contract) is dropped, which loses the proof and
  is never assumed. A contract at another sort is not used.
- `refine_resolve.ml` `binder_apart`: a named binder is renamed to `_` before the actuals
  are substituted, in `postcond_of_declared` and `ret_instance`.
- `refine_call.ml`: `foreign_var` first loads the name's own scope fact
  (`load_scalar_name_fact`, through a forward cell; that loader's table stops cycles).
- `refine_post.ml` `scope_facts ?env`: a non-entry name a scalar or ADT entry's predicate
  mentions is declared at its parameter's scalar sort (`Int` by default). A clash with another producer's sort becomes the recorded
  `sort-conflict` skip.
- `precond_infer.ml` `walk_ledger` and `infer_oracle.ml` `prepare` run
  `gate_unverified_posts` (on a copy) before walking. `walk_ledger` gates the pruned tree;
  `prepare` gates the whole unit, because the pruned tree holds no callees.
- `refine_check.ml` `post_holds_lent` (exported): the oracle's TRUE test for a return is the
  gate's own check, under a lookup of the (gated) unit with the function's own key stripped
  of its return. It replaces `Postcond_infer.post_holds` in `Infer_oracle.return_`/`holds`,
  which ran with no lookup at all.

Recursion: no new gating was needed. `gate_unverified_posts` already clears every pending
return from `defs` until it proves (`{ sg with ret = None }`), so neither a self-call nor a
cycle can see an unproved return. Element returns have their own rounds (`gate_elem_returns`).
Scalar returns needed no rounds of their own, because this gate is already a fixpoint.
Perturbation check: keeping `ret` during the gate turns the recursion, mutual-recursion and
unproved-callee controls RED (`f(x) = f(x)` "proved").

## Tests (`test/test_refinecheck.ml`, group `demand-chains`, 17 cases)

RED on base `1686cb24d` (lib reverted, test file kept), first failing assertion each:

| # | case | base | now |
|---|---|---|---|
| 0 | C1 proved | b `skipped:unreflectable-subject` | proved (+ `need_pos(b(3))`) |
| 1 | C1 two hops, declared c, b, a | b `skipped:unreflectable-subject` | b, c proved |
| 2 | C1 control, weaker callee `_ >= 0` | b `skipped:unreflectable-subject` | `skipped:solver-undecided` |
| 3 | C1 control, unproved callee | (control, same) | `skipped:unreflectable-subject` |
| 4 | C1 reject control, callee `_ < 0` | (control) violated | violated |
| 5 | C1 `@[assume]`d callee | b `skipped:unreflectable-subject` | proved |
| 6 | recursion control (`f(x)`, and `if n == 0 do 1 else f(n - 1)`) | (control) | unchanged: skip / proved+skip |
| 7 | mutual-recursion control | (control) | both `skipped:unreflectable-subject` |
| 8 | G1 proved (inline, `let`, tail) | `skipped:solver-undecided` | proved |
| 9 | G1 controls: `n : Int` skip; `need_neg` violated | `need_neg`: `skipped:solver-undecided` | skip / violated |
| 10 | G1 unreflectable actual `inc(h(n))` (h unrefined; h proved) | (control) | `skipped:solver-undecided` both |
| 11 | G1 two params, crossed `sub(y, x)` | `skipped:solver-undecided` | proved; `sub(a, b)` control undecided |
| 12 | binder capture `{r : Int \| r > x}` with caller `r` | **proved** (unsound) | skip / violated / proved, tail violated |
| 13 | unrefined sibling declared (no malformed query) | `skipped:solver-undecided`, 4 z3 rejections | violated, 0 rejections; refined control proved |
| 14 | infer C1, returns stripped | `[]` proposed | `a`, `b` both `{Int \| _ > 0}` |
| 15 | infer C1 control, self-recursive | (control) | nothing for `f` |
| 16 | infer G1, `_ > x` in the unit's vocabulary | `[]` for `inc` | `inc : {Int \| _ > x}`; control `n : Int` nothing |

Perturbation: with `binder_apart` disabled, case 12 goes RED ("proved"), and the
tail-position case on its own gives "proved" through the CLI. Case 13 is the regression for
the CI `z3-well-formed` failure (`unknown constant x`, 6 queries). No demand-chains case
passed because of a malformed query. Every rejected query came from `need_gt` return probes
in case 16, whose asserted result is `inc`'s proposal.

Updated deliberately: `infer-fixpoint` "C1: the chain …" pinned the gap (b's return not
proposed, a `not-true` rejection at b). It now asserts the chain's result: `a` and `b`
both `{Int | _ > 0}`, and no `not-true` rejection for `b`.

## Inference

`--refine-infer` on C1 with both returns stripped proposes `a : {Int | _ > 0}` (the chain
link, "closes 0") and `b : {Int | _ > 0}` (closes `need_pos(b(3))`), through the §3.3
chain. Two things were missing. The checker's tail rule, and the oracle's TRUE test
(`post_holds`), which never had a contract lookup.

G1 with the annotation stripped still proposes nothing. Its candidates are the demand's `_ >
0` (not TRUE: `x` is unrefined), the unit's house predicates, the body comparisons (none),
and the fixed sign grammar. None of them is `_ > x`. When the unit spells `_ > x` anywhere
(case 16), it is now proposed: it is TRUE, and now USEFUL. A relational candidate family for
return slots (`_ > p`, `_ >= p` per Int parameter) would close the plain G1 shape. It is not
added here; that is a vocabulary change.

## Oracle

`scripts/refine-oracle.sh` under its private HOME. The first baseline, taken before any edit,
cannot be compared: a targetless `dune build --root .` between it and the check restaged
`_build`, which moved 1697 lines of non-refinement stdlib diagnostics (`stdlib_internal`,
`cap_ceiling`, `cap_needs`) and **no** refinement line. The baseline was retaken with
`lib/refinecheck` reverted to `origin/main` in the same `_build` (8742 lines over 551
fixtures). `check` with the fix: **identical**. No corpus fixture has a scalar call tail
under a refined return, a relational scalar return, or a named relational binder, so no
proof moved. That is also why a perturbation of the new code alone (an uncontracted call
tail minted as a fresh constant) left it identical. Red on a perturbation of a verdict:
`check_post` recording `Verified` as a `solver-undecided` skip made `check` exit 1 with
4417 changed lines. Re-checked after the sibling-declaration fix: identical.

## Other checks

- `stdlib/list.march` (`--stdlib-source --refine-report`): user + stdlib `109 proved, 34
  trusted, 37 skipped` before and after (ceiling 42).
- Audit baselines (`test/refine_audit/*.baseline`): not regenerated. The audit classifies
  declarations, and none changed.
- `--refine-infer` on 7 `specs/lang/types/accept/*refine*` files: 12.7 s base, 13.8 s new
  (+9%, from the gates). One prediction changed: `t110_refine_unproven_post_not_propagated`
  went from "user skips 1 -> 1" to "2 -> 2", which matches its real `--refine-report` (2
  skipped). Base under-predicted because it lent `shady`'s unproved return.

## Rulings

- Ruling: a call tail is lent only a contract at the return's own scalar sort — a Bool/Float
  contract under an Int return (or a record one) says nothing about this value — cost if wrong:
  a lost proof, never a false one.
- Ruling: an argument that cannot be reflected (`inc(h(n))`) is declined by dropping that
  conjunct of the instantiated fact, not by refusing the whole call. The obligation is then a
  recorded `solver-undecided` skip. The goal is never replaced by `true`. Cost if wrong:
  none for soundness. A stricter "Stable"-only rule, as the element path uses for stored
  entries, would lose nothing here, because the inline fact is used once at the call.
  Stored (`let`) facts are already retired by mention when a name they carry is rebound;
  the base already pinned that (`let r = inc(n); let n = r + 1; need_pos(r - n)` violated).
- Ruling: a caller name a lent fact mentions brings its scope fact (any `foreign_var` use,
  not only call contracts). Scope facts are hypotheses at this point of the walk, so loading
  more is sound. Cost if wrong: more queries carry more facts (more proofs, and, through the
  definite-failure rule, possibly a definite violation where there was a skip). The oracle
  shows no moved verdict in the corpus.
- Ruling: a named relational binder is renamed to `_` before substitution, in the scalar
  path as in the element path. `_` is never a March variable. Cost if wrong: none found.
  Closed returns are untouched, so their predicate text and VCs are byte-identical.
- Ruling: an undeclared non-entry name in a post scope fact is declared at its parameter's
  declared scalar sort (`check_post`'s `scalar_env`: Bool, Float, else Int). A `String` or
  record sibling can appear in a scalar predicate only under a measure or a field, and the
  scope-fact resolvers drop those, so `Int` is never wrong for a bare one. Cost if wrong:
  a two-sort declaration, which `check_post` turns into a recorded `sort-conflict` skip.
  The Float case (`x : Float, k : {Float | _ > x}`) is pinned in case 13. Its verdict did
  not move: with `x` free the fact decides nothing about `k > 0.0`.
- Ruling: inference probes are gated like a real check (`walk_ledger` over the pruned tree,
  `prepare` over the unit). Cost if wrong: about 9% more probe time on the sample above, and
  probes no longer count on unproved returns, which is the real checker's behaviour.
- Ruling: the `let r = a(x); r` form of C1 is not done (filed:
  `specs/todos/2026-10-24-refine-post-let-bound-call-tail.md`). The post scope holds the
  parameters only, and inlining every `let` would change reasons on existing skips. Cost if
  wrong: that shape stays `solver-undecided`.
