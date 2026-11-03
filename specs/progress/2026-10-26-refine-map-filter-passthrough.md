# A two-argument definer passed through to `Map.filter` proves its return

Landed 2026-10-26. Closes `specs/todos/2026-10-25-refine-map-filter-two-arg-passthrough.md`
(deleted; this note replaces it). Branch `claude/refine-call-lambda-gaps`.

```march
fn need_posmap(_m : Map(String, {Int | _ > 0})) : Int do 0 end
fn mfilt(m : Map(k, v), keep : k -> v -> Bool[p], cmp : k -> k -> Bool) : Map(k[p], v[p]) do
  Map.filter(m, keep, cmp)
end
fn go(m : Map(String, Int)) : Int do need_posmap(mfilt(m, fn _k -> fn v -> v > 0, Map.str_cmp)) end
```

Before: 2 skipped, both `abstract-refinement-uninstantiated`. Now: both proved.

## Root cause

Neither suspect in the todo. The detail at `return of mfilt` was "`Map.filter`'s element
return applies `p` where it is not instantiated". The two abstract refinements share the
spelling `p`: `keep`'s reading (`named_predicate_n` over its chain signature, the definer
case review C2 kept) is mfilt's own `p($cb_arg, $cb_arg2)`. `instantiate_nary_entry`
substituted `Map.filter`'s `p` by it correctly, but the guard after it (`entry_mentions
nary produced`, review I3: an application the substitution did not reach) found `p` in the
result and could not tell mfilt's `p` from `Map.filter`'s. Renaming mfilt's abstract to `q`
proved on base, which is why the user-`Assoc` pass-throughs written with distinct names
did.

The same confusion has a second form: with several callee abstracts, `inst` substitutes
them one after another, so a reading that brings in a caller abstract spelled like a LATER
callee abstract is rewritten again (`cross` below: `filt2(a, g, f)` with `p := g's p`,
`q := f's q`).

## Fix (`lib/refinecheck/refine_check.ml` only)

- `instantiate_nary_entry` renames the caller's own abstract applications
  (`current_abstracts`) in every reading to `$own$<name>` (`to_own`) before substituting, so
  the callee's substitution and the guard see only the callee's names.
- `abstract_flow_n` and `abstract_param_entry_n` restore them (`of_own_entry`) right after
  the guard, before the entry is moved to the call's actuals.

Soundness is the definer argument: inside `mfilt`, `p` is uninterpreted (`$abs_p`) and is
instantiated at each call of `mfilt` from the callable passed, so `Map.filter(m, keep, …)`
returning `Map(k[p], v[p])` with mfilt's `p` is exactly the claim. `Map.filter`'s entry
fact stays assumed (P1-gated) as before.

## Tests (group `gap-map-passthrough`, 4 cases)

RED on base (`bc1fef6f1`, lib reverted): cases 0 and 3.

| # | case | base | now |
|---|---|---|---|
| 0 | `mfilt` return; `need_posmap(mfilt(m, fn _k -> fn v -> v > 0, …))`; spelled `q` | return `[uninstantiated]` | proved, proved, proved |
| 1 | control: `Map.filter(m, other, cmp)` with `other : … Bool[q]`; a constant-true lambda | (control) | not proved |
| 2 | control: `mfilt` returns `m` | (control) | not proved |
| 3 | two abstracts crossed: `cross` / `cross2` over an `@[assume]`d `filt2`; control `wrong` passes `f` for `p` | `cross` `[uninstantiated]` | proved / proved / not proved |

Edited existing test, deliberately: `infer-vocab-oct` "K6 over Map(k, v) … not proposed"
pinned this gap; it now asserts the proposal `mfilt : k -> v -> Bool[p] / Map(k[p], v[p])`.

## Oracle

`scripts/refine-oracle.sh`, private HOME. Baseline taken in this tree before any edit, after
a full `dune build --root .` (8750 lines over 552 fixtures). `check` after gap 1 alone and
again with all three gaps: **identical** both times. No corpus fixture passes a definer
through to a same-named callee abstract, a capturing two-argument lambda, or returns a
`let`-bound call under a refined scalar return, so no proof could move. Red on a
perturbation of a verdict (`check_post` recording `Verified` as a `solver-undecided` skip):
`check` reported 4423 changed lines; restored and rebuilt afterwards.

`stdlib/list.march` (`--stdlib-source --refine-report`): user + stdlib `109 proved, 34
trusted, 37 skipped` on base and with the branch (ceiling 42). Audit baselines
(`test/refine_audit/*.baseline`) not regenerated: no declaration changed class.

## Rulings

- Ruling: a caller abstract is kept apart by renaming, not by refusing a same-named callee
  abstract — the substitution is then the same one a distinct name gets, which proved on
  base — cost if wrong: none found; the `other` and `wrong` controls do not prove.
- Ruling: the restore runs after the I3 guard and before `instantiate_entry` — the guard
  must see only callee names, and `instantiate_entry` treats an application head as a
  function name either way — cost if wrong: a caller abstract read as uninstantiated, a
  lost proof.
