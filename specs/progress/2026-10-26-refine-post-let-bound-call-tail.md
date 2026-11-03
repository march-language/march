# A return that is a `let`-bound call is proved from the callee's return (C1's let form)

Landed 2026-10-26. Closes `specs/todos/2026-10-24-refine-post-let-bound-call-tail.md`
(deleted; this note replaces it).
Branch `claude/refine-call-lambda-gaps`.

```march
fn a(x : {Int | _ > 0}) : {Int | _ > 0} do x + 1 end
fn b(x : {Int | _ > 0}) : {Int | _ > 0} do
  let r = a(x)
  r
end
```

Before: `b` `skipped:solver-undecided`. Now: proved.

## Root cause

`check_fn_post_verdict_core` (`lib/refinecheck/refine_post.ml`) builds each tail's VC from
the parameters' scope facts and the path conditions. `tails_bound` records the names a
`let` binds on the way to the tail (to retire path facts about them), but not what they
are bound to. So the tail `r` reflected as a fresh unconstrained constant. The bare tail
`a(x)` already proved through `check_post`'s `scalar_call` (2026-10-24 demand chains).

## Fix (`lib/refinecheck/refine_post.ml` only)

- `tails_let_calls`: per tail, in `tails_bound`'s order, the block `let`s of a plain name
  to a direct call (`let r = f(args)`) still in force at the tail. A binding is retired when
  its name or any name its call mentions is bound again before the tail (a later `let`, a
  local `fn`, a `match` arm's pattern, a `let?`/`let*` pattern; over-approximate
  `expr_mentions`). A call that mentions its own name (`let x = inc(x)`) is never recorded.
- `check_fn_post_verdict_core` zips them with the tails and moves each binding by the
  tail's own clash renaming (`rename_free_checked`, `inner_name`), so a binding named like
  a parameter and a call over an inner binding that shadows one mean what they mean in the
  renamed tail. An incomplete renaming drops the binding.
- `check_post ?let_calls`: `var_const` (shadowed after `resolve_measure_app`) reads such a
  name as a fresh `f$let<N>` carrying `post_lookup f args`, conjunct by conjunct, at the
  contract's scalar sort, exactly as `scalar_call` reads a bare call tail. Memoised per
  name, so the tail, a path condition and a chained `let`'s argument share one constant. No
  contract, or a non-scalar one: the plain constant, as before.

Gating is the bare tail's: `post_lookup` answers only proved or `@[assume]`d contracts, and
`gate_unverified_posts` admits one only once proved (`ret = None` while pending), so neither
a self-call nor a cycle sees its own return.

## Tests (group `gap-let-call-tail`, 8 cases)

RED on base (`bc1fef6f1`, lib reverted, tests kept): cases 0, 1, 2, 7 fail.

| # | case | base | now |
|---|---|---|---|
| 0 | `let r = a(x); r`; and `r + 1` | b `skipped:solver-undecided` | proved, proved |
| 1 | `let r1 = a(x); let r2 = a(r1); r2` | `skipped:solver-undecided` | proved |
| 2 | `@[assume]`d callee | `skipped:solver-undecided` | proved |
| 3 | control: unproved callee | (control) | `skipped:solver-undecided` |
| 4 | control: `let r = f(x); r` in `f` | (control) | `skipped:solver-undecided` |
| 5 | control: mutual recursion through lets | (control) | both `skipped:solver-undecided` |
| 6 | `r - 1` against `> 0`: skip; callee `_ < 0`: violated | (control) | skip / violated |
| 7 | name capture (7 rows) | `param r < 0, let r = a(x)`: `skipped:solver-undecided` | see below |

Case 7: `let x = 0 - 5; let r = inc(x)` not proved; `let r = inc(x); let x = 0 - 5`
undecided (retired); `let x = -50; let r = inc(x); let x = 100; if x > 0 do r …` not
proved; `let r = a(x); let r = 0 - 1` not proved; `let x = inc(x)` not violated; a
parameter `r < 0` with `let r = a(x)` proved (renamed apart); a parameter `r > 0` with
`let r = u(x)`, `u` unproved: `violated` (b(1, 0) returns 0, the interpreter's witness);
a `match` arm rebinding the call's argument retires the binding (`skipped`, `proved`).

Perturbations: retirement disabled → "`let x = -50; … let x = 100; if x > 0 do r`" goes
RED (proved); the rhs clash renaming disabled → "`let x = 0 - 5; let r = inc(x)`" goes RED
(proved).

## Oracle

`scripts/refine-oracle.sh`, private HOME, baseline from this tree before any edit (8750
lines over 552 fixtures): **identical** after this fix. No corpus fixture returns a
`let`-bound call under a refined scalar return.

## Rulings

- Ruling: only a plain-name `let` of a direct call is read — a tuple pattern or a nested
  call in the RHS is an unconstrained name as before — cost if wrong: a lost proof.
- Ruling: retirement is over-approximate (any later binder of the name or of a name the
  call mentions, including in a `match` pattern), as `path_shadow` is — cost if wrong: a
  lost proof, never a reading of the wrong binding.
- Ruling: the binding is moved by the tail's own clash renaming, not checked separately —
  a call over a shadowing local then names `x$in`, the same unconstrained inner constant
  the path uses — cost if wrong: none found; the perturbation shows the unrenamed reading
  proves a false return.
- Ruling: a contract is lent at its own scalar sort only (Int/Bool/Float) — cost if wrong:
  a lost proof.
