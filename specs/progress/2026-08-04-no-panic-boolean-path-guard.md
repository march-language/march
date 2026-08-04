`[P1]` **`cap no_panic` rejected a division that a boolean guard makes safe.**

```march
fn f(p : Int, d : Int) : Int do
  if p > 0 && d > 0 do 100 / d else 0 end     -- ERROR: "no refinement proves `d ≠ 0`"
end
```

A **false positive**, on the most idiomatic safe spelling there is — and under
`cap no_panic` a hard error, not a hint. Rejecting correct code is this
subsystem's cardinal sin, so this outranked the completeness backlog.

**How it was found.** By pointing the checker at
[forgepm](https://github.com/march-language/forgepm) — a real ~9k-line
application, 603 `.march` files, with *zero* refinement usage — and trying to
adopt `cap no_panic` on its metrics module. That module's CPU-utilization
function is exactly:

```march
if prev_total <= 0 || dt <= 0 do
  (total - idle) * 100 / total
else
  let busy = dt - di
  if busy < 0 do 0 else busy * 100 / dt end     -- rejected: `dt` "may be by zero"
end
```

`¬(prev_total ≤ 0 ∨ dt ≤ 0)` gives `dt > 0`, so the division is safe. The
`/ total` on the line above it — guarded by a plain `if total <= 0` — was
accepted, which is what made the shape of the gap legible.

**Root cause.** `path_proves_nonzero` (`lib/refinecheck/division_safety.ml`)
matched a single atomic comparison and nothing else. Any `&&`/`||` anywhere in
the guard fell through to `| _ -> false`, the divisor reached the unrefined arm,
and the pass reported a division the guard makes unreachable.

Isolated with a nine-case A/B before any code changed. What worked: a guard
`d > 0` / `d != 0` / `d <= 0`-else on a parameter, the same on a `let`-bound
expression, and a `{Int | _ > 0}` divisor. What failed: **every** guard
containing a connective — including `if d <= 0 || d > 1000 do 0 else … / d`,
a disjunction over the divisor *itself*. So this was never about `let`
bindings or about which variable the guard mentions; it was purely the boolean
structure.

Notably the z3 path could not rescue any of these, for two independent reasons:
a bare-`Int` divisor never reaches a VC at all (the unrefined arm errors
directly), and in the refined arm `consts_declared` drops any path condition
mentioning an *unrefined* parameter — which `p > 0 && d > 0` does.

**Fix.** `path_proves_nonzero` now recurses through `&&`, `||` and `not`,
carrying the polarity. The rule, which is the entire content of the change:

- a **conjunctive** fact is proved by **either** side;
- a **disjunctive** fact is proved only if **both** sides prove it
  independently, since either arm may be the one that holds.

De Morgan decides which is which — conjunctive exactly when
`(op = "&&") <> negated` — and both arms inherit the same negation flag, so
polarity threads through unchanged and only the combinator flips. Anything that
is neither a connective nor a recognised comparison still answers `false`, so
the fallback stays fail-closed.

Getting the two combinators backwards would be **unsound**, not merely
incomplete, so each direction carries a negative control. Confirmed
load-bearing by mutation: inverting the rule to `(op = "&&") = negated` fails
`B7` (a `p > 0 || d > 0` guard, where `d` may well be zero) alongside the five
permissive cases. `B8`/`B9` survive that particular mutation — they are pinned
by construction rather than by this mutant, and are kept because they fix the
other polarity in place against future edits.

+9 tests (`divsafety-boolean-guard`, ungated — every case is decided
syntactically with no VC built, and the whole point is fail-closed behaviour on
a machine with no solver). All 13 `cap no_panic` corpus witnesses unchanged,
accept and reject alike.

The forgepm metrics function now checks clean under `cap no_panic`, and the
unguarded control (`(total - idle) * 100 / total` with no enclosing guard) still
errors.
