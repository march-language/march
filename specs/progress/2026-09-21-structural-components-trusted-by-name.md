# Structural components were trusted by name: a false postcondition proved

Fixed 2026-09-21. Item 1 of `specs/plans/2026-09-21-refinement-backlog-plan.md`,
item 5 of `specs/todos/2026-09-18-refine-element-flow-followups.md`. The plan
listed it first because it was the one entry that could make a *wrong* proof;
the probe confirmed it did.

## The bug

`Refine_encode.structural_subvars` computes the variables structurally smaller
than a matched parameter, keyed by NAME over the whole body. Its consumers test
a recursive call's argument with `Hashtbl.mem`. A name bound as a component in
one place and rebound to something else in another was therefore trusted at
both:

```march
fn copy(xs : List(Int), ys : List(Int)) : {List(Int) | len(_) == len(xs)} do
  match xs do
  Nil -> Nil
  Cons(h, t) ->
    match ys do
    Nil -> Cons(h, copy(t, ys))
    Cons(_, t) -> Cons(h, copy(t, t))    -- this `t` is ys's tail
    end
  end
end
```

`main` PROVED `len(_) == len(xs)`. At runtime `copy([1], [5, 6, 7])` prints
`len(xs) = 1, len(result) = 3`. The same program with the inner binder renamed
to `u` is correctly left unproved: the spelling alone was the difference.

A proved postcondition becomes a fact at every call site, and `cap verified`
promises that a program which compiles had its contracts proved, so this broke
both.

## Wider than the todo said

Three consumers read the set, and all three had the hole:

- **Tier 2** relational postconditions (`refine_post.ml`) — the false proof
  above.
- The **element-return hypothesis** (`refine_check.ml`) — already patched with
  `Refine_param.ambiguous_names` on 2026-09-18, which drops every name bound
  more than once.
- The **`@[measure]` termination gate** (`refine_encode.ml`) — `main` accepts
  a measure that recurses forever through a rebound name
  (`Cons(_, t) -> let t = xs  1 + bad(t)`) as structurally recursive, which
  hands the solver an inconsistent axiom. I could not turn that into a false
  proof in the shape I tried (a literal subject is refuted without the
  measure), so it is recorded as a real hole without a demonstrated exploit.

## The fix

One place, in `structural_subvars`: a name stays in the set only if EVERY
binder occurrence of it in the body is one of the structural ones, and it is
not also a parameter (the new `?params`). Iterated to a fixpoint, because
dropping a name must also drop the components of any `match` on it, admitted
while it was still trusted.

Why not the element-return hypothesis's flat rule ("bound more than once")?
It throws away sibling arms of one structural match that reuse a spelling —
`One(_, r) -> … | Two(_, r) -> …`, the ordinary shape of a tree measure. The
new rule keeps those, because both bindings are structural. The element-return
site keeps its existing filter on top, so it is no looser than before.

## Tests

`test/test_refinecheck.ml`, group `tier2-component-names`:

| Case | Expected | On the unfixed checker |
|---|---|---|
| true `copy` | proved | proved (control) |
| rebound by an inner `match` | not proved | **proved — FAILS** |
| rebound by a `let` | not proved | not proved (path control) |
| sibling arms reuse `r` | proved | proved (precision control) |
| measure recursing on a rebound name | gate rejects | **accepted — FAILS** |

## Found alongside, not fixed here

A TRUE postcondition over a doubly nested match on the same list
(`Cons(h, t) -> match t do … Cons(h2, t) -> Cons(h, Cons(h2, copy2(t)))`) is
counted `violated` in `--refine-report`, with no error printed and exit 0.
Identical on `main`. Filed as
`specs/todos/2026-09-21-refine-tier2-violated-count-without-error.md`.
