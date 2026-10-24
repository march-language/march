# `[P2]` `--refine-infer` proposes preconditions that only make the demanding branch unreachable

Filed 2026-10-21 from the inference-lite evaluation
(`specs/progress/2026-10-21-refinement-suggest-lite-evaluation.md`).

```march
pfn set_n(j : Int, n : Int, v) do
  if j >= n do v
  else set_n(j + 37, n, Array.set(v, j, 0 - j)) end   -- Array.set: 0 <= j < length
end
```

The only proposal the 416-file `test/native` corpus accepts is `n : {Int | _ <= j}`
(`array_trie_drop_leak_probe.march`). It "closes" the `Array.set` site because the `else`
branch becomes dead, not because the index is in bounds. It is admissible (closes one, opens
none) and satisfiable, but it is not a contract anyone wants. The same file also produced
`pop_n(j : {Int | _ == 0})`, which is now refused for caller violations.

Fix direction: a precondition candidate whose closed sites are closed only because the site's
path condition becomes unsatisfiable (hypothesis ∧ path ⊢ false at the site) should be rejected
(`reason: "vacuous-branch"`). That needs one solver query per closed site, asking whether the
site's own path condition is consistent with the hypothesis.

## Resolution (2026-10-23)

Fixed in `lib/refinecheck/infer_oracle.ml` (`vacuous_closes`, `accept_genuine`) and
`lib/refinecheck/precond_infer.ml` (`unreachable_sites`).

**The probe.** For each site a precondition candidate closes inside the target's body,
`unreachable_sites` puts a call to `__refine_reach_never__(x : {Int | _ < 0 && _ > 0})`
just before the site's expression, with an Int parameter as subject (the slot's
parameter when it is Int, else the first one), and walks the oracle's pruned tree
(the target and its callers) with the real checker. `check_call` translates every
path condition at that point into the query, plus the scope facts of the names the
conditions mention, so the demand is proved exactly when path and hypothesis are
inconsistent: the site is dead. This is the same "demand `false`" trick as
`satisfiable`. No obligation-ledger plumbing was needed.

**Rulings.**
- A close is *vacuous* when the site is reachable without the hypothesis and dead with
  it. A site already dead without the hypothesis counts as before.
- A precondition must be admissible on its genuine closes: at least one, and at least
  as many as its new skips. Otherwise it is `Reject ("vacuous-branch", "closes `<callee>`
  at file:line:col only by making its branch unreachable")`. Cost if wrong: the only
  candidates lost are those whose every proved site is dead (or whose live closes do
  not pay for their new skips), which is the `set_n` class this todo targets.
- Once admissible, a proposal keeps and is ranked on all its closes. So in
  `let a = need_pos(n)` / `if n > 0 do a else need_pos(n + 5) end`, `_ > 0` (proves
  `need_pos(n)`, kills the `else`) still beats `_ >= 0`. If wrong, a candidate that
  kills more branches could out-rank a weaker one that kills fewer, but only when it
  also genuinely closes at least as much as its new skips.
- The vacuity check runs before the `caller-violation` refusal. A refusal tells the
  author to fix a caller, which is the wrong advice for a non-contract. On the
  fixture, `pop_n`'s `j : _ == 0` (refused before) is now rejected as `vacuous-branch`.
- Not instrumented, and so reported reachable (the pre-fix behaviour, never a false
  rejection): a site in a clause guard, a site whose innermost covering expression is a
  `let` form, a site inside a form the instrumenter does not descend (`cond`, records),
  a function with no Int parameter, and caller sites.
- `--refine-suggest` (the older per-function `Precond_infer.infer_fn`) is not changed.

**Cost.** One extra walk per candidate that would otherwise be accepted or refused
(all its closed sites at once), plus one walk per slot without the hypothesis, cached
in `ctx.reach0` across the slot's candidates. These are not counted as probes.

**Reporting.** `rejected[].reason = "vacuous-branch"` in JSON v1 (the closed set in
design §4.2 now lists it). The text report prints only this kind of rejection, as
`  <fn>: rejected (vacuous-branch) <slot> : <pred>` and then the detail line.

**Tests** (`test/test_refinecheck.ml`, group `infer-vacuous`, plus one `infer-cli`
case). RED before the fix: the set_n shape was accepted (`[("set_n", "{Int | _ <= j}")]`),
and the CLI case on `test/native/array_trie_drop_leak_probe.march` printed
`1 proposed`. The controls (unguarded `need_pos(n)`, guarded demand, both-branch
demand, genuine plus vacuous close) passed before and after. A direct probe test pins
`unreachable_sites` (else-site dead under `n > 0`, genuine site live, both live
without the hypothesis).

**Evaluation over `test/native` (416 files)**, `eval.py`-style: per file, cold `--check`
and cold `--check --refine-infer-json`, each in a fresh cwd and `HOME`, 4 files in
parallel, not interleaved:
- before: 1 accepted (`set_n` `n : {Int | _ <= j}`), 6 refused. Infer ÷ check: median
  1.38×, p90 1.69×, aggregate 1.49×.
- after: the corpus re-run was stopped unfinished (the sweep was dropped from scope
  and CI runs the suites), so there is no after timing. On the one file that had an
  accepted proposal, `array_trie_drop_leak_probe.march`, the after run accepts nothing
  (`0 proposed, 0 refused; 318 probes`). It rejects four candidates as
  `vacuous-branch`: `set_n` `n : _ <= j`, `pop_n` `j : _ == 0` (refused for
  caller-violation before), and `set_legs` / `string_legs` `k : _ == i`.
