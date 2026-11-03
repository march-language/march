# `len(Cons(h, t)) == len(t) + 1` outside the induction checker (L2)

Landed 2026-10-26 on `claude/refine-length-facts`. No todo tracked it; the source is row 12 of
the 2026-10-24 stdlib refinement audit, which is also the only skip inside
`stdlib/list.march` in the CI ratchet measurement: `list.march:224:38 partial-conjunct nth`
(`_ >= 0` established, `_ < len(xs)` not, for `nth(t, n - 1)`).

```march
need_ne(Cons(x, t))          -- was solver-undecided; now proved
let ys = Cons(x, t)
need_ne(ys)                  -- was unconstrained-subject; now proved
fn nth(xs : List(a), n : {Int | _ >= 0 && _ < len(xs)}) : a do
  match xs do
  Nil        -> panic("List.nth: index out of bounds")
  Cons(h, t) -> if n == 0 do h else nth(t, n - 1) end   -- was partial-conjunct; now proved
  end
end
```

## Root cause

`len` is not axiomatised over the built-in `List` (no quantified recursion axiom), so a list
term is either a concrete literal (`list_len`), a name's memoized `len$x` constant, or a call
carrying a proved `len` postcondition. Three places had no rule for a constructor whose tail
is not a literal:

1. the goal-side `resolve_measure` (`Refine_call.check_call`): `Cons(x, t)` as an actual fell
   to the binder-spelling fallback, a fresh unconstrained constant;
2. `Refine_scope.scope_add_binding`: `let ys = Cons(x, t)` filed nothing (L1 covered only
   chains ending in `Nil`);
3. the `match` walk (`Refine_check.visit`, `EMatch`): a `Cons(h, t)` arm on a variable pushed
   only the tag `is_Cons(xs)`, which `path_resolve_tester` translates to `len(xs) > 0`, with
   nothing tying `len(t)` to `len(xs)`.

## Fix

1. `Refine_call`: `cons_len_term` unfolds a Cons chain to `len(tail) + k`, where the tail is a
   caller name (its scope facts loaded first, like a bare-name actual), `Nil`, or a call with
   a proved `len` post (`set_of_call`). `resolve_measure`'s list-`len` branch uses it for a
   `Cons` actual; an unreflectable tail keeps the old fallback.
2. `Refine_scope.list_len_pred`: a chain ending in a variable `t` gives `len(_) == len(t) + k`.
   The entry takes `self_mentioning`'s guard (`let t = Cons(x, t)` is declined), and
   `scope_shadow` retires it when `t` is later rebound (its predicate mentions `t`).
3. `Refine_check.visit`, beside the tag narrowing: in an arm `Cons(_, …)` on a bare variable
   `xs` the arm does not rebind, push `len(xs) == len(t) + k` (or `== k` when the pattern ends
   in `Nil`; nothing for a wildcard tail) as a path fact. Gated on `Cons` being the built-in
   `List`'s constructor and on no user `@[measure] len`. `path_shadow` retires it when `xs` or
   `t` is rebound inside the arm.

All three are the measure's own defining equations, so they hold for every list.

## Tests (`gap-cons-len`, 10 cases)

RED on the base (received):

- `need_ne(Cons(x, t))`, `need_ne(Cons(x, Cons(x, t)))`: `solver-undecided` ×2, expected proved.
- tail composition `ok(x, t : {len == 1}) = need_len2(Cons(x, t))`: `solver-undecided`,
  expected proved (`bad` with `len == 2` expected violated; `unk` not proved).
- `let ys = Cons(x, t); need_ne(ys)`: `unconstrained-subject`, expected proved.
- name capture: `need_succ(t : List(Int), ys : {len(_) == len(t) + 1})` called as
  `need_succ(t, Cons(x, t))` and `need_succ(Nil, Cons(x, t))` with `t : {len == 1}`:
  `solver-undecided` ×2, expected proved then violated.
- `mynth(t, n - 1)` under `Cons(h, t)` (the `List.nth` copy): `partial-conjunct`, expected proved.

Controls that held before and after: `need_len2(Cons(1, Cons(2, Nil)))` proved and
`need_ne(Nil)` violated; self-rebinding `let t = Cons(x, t); need_len2(t)` not proved; a tail
rebound after the `let` (`let t = [1, 2, 3]`) gives neither a proof nor a violation;
`mynth(xs, n - 1)` proves, `mynth(t, n)` does not; a tail binder rebound inside the arm
(`let t = [1]`) retires the equation.

GREEN: all 10 (and `gap-let-literal-len` still 7/7).

## Ratchet

`--check --stdlib-source --refine-report stdlib/list.march`: before `109 proved, 34 trusted,
37 skipped` (user code `35 proved, 1 skipped`, the `nth` line); after `110 proved, 34 trusted,
36 skipped` (user code `36 proved, 0 skipped`). The CI ceiling (42) is a maximum and the
step does not require lowering it, so `ci.yml` is unchanged; lowering it to 36 is a separate
one-line follow-up for whoever lands the merge train.

## Oracle

`scripts/refine-oracle.sh check` against the pre-L1 baseline (552 fixtures): DIAGNOSTICS
CHANGED, every change the same one. In all 552 fixtures one `skipped (partial-conjunct)`
becomes a proof (`user + stdlib`: +1 proved, -1 skipped), the stdlib's own
`list.march:224 nth(t, n - 1)`, which every program checks because the driver prepends the
stdlib. In `stdlib_list` that line is user code, so its `user code` slice moves too and the
three-line site diagnostic disappears. No new violation, no new skip, nothing else moved.

## Rulings

- Ruling: the arm equation is a PATH fact, not a scope entry — the tag narrowing it sits
  beside is a path fact, and `path_shadow` already retires facts mentioning a rebound binder
  — cost if wrong: none for soundness; a consumer that drops a measure-bearing path fact
  loses the proof.
- Ruling: a wildcard tail (`Cons(_, _)`) gives no equation — there is no name to state it
  over, and the tag already gives `len(xs) > 0` — cost if wrong: a lost proof.
- Ruling: CI ceiling left at 42 — the gap's test does not require it, and the instructions
  say to change it only then — cost if wrong: the ratchet stays 6 looser than measured until
  someone lowers it.
