`[done]` A derived `Eq` on a recursive type is reflected, so `==` on it can be used in the logic

Found 2026-11-06 writing `stdlib/session_theory.march` (lemmas phase C).

```march
type T = A | B(Int, T)
derive Eq for T
fn same(x : T, y : T) : Bool do x == y end
@[lemma]
fn refl(x : T) : {Unit | same(x, x)} do () end
```

`same` is "not reflected … == at T dispatches to impl Eq(T).eq, which has termination
certificate unproved:no-structural-arg". The derived `eq` recurses on the fields of both
arguments through a match on the pair, which the termination checker does not see as
structural, so no function that compares a recursive type with `==` can be reflected, and no
lemma can be stated about one.

`Session.Theory` works around it with a hand-written `same`/`same_bs` and the lemma
`same_eq` (`same(a, b) == (a == b)`). Fix: generate the derived `eq` so its recursion is
structural on the first argument (match it, then the second), or certify the derived impl's
termination by construction (it recurses only on sub-fields of both arguments), and treat a
derived `Eq` on a type with no hand-written one as structural equality in the logic.

## Fixed 2026-11-07

The certificate side, not the derivation: `Refine_encode.structural_subvars` now treats a
`match` on a TUPLE scrutinee position by position. When component i of `match (a, b) do …` is
structural for a parameter (the parameter itself, or a component of it), the variables of
position i's constructor sub-pattern are components too. So the derived
`eq(a, b) = match (a, b) do (B(_da0, _da1), B(_db0, _db1)) -> _da0 == _db0 && _da1 == _db1 …`
recurses on `_da1`, a component of `a`, and its termination certificate is structural. No change
to the generated code, and the common user idiom
`match (xs, ys) do (Cons(_, xt), Cons(_, yt)) -> f(xt, yt)` is certified as well. A variable
bound in ANOTHER position is a component of that position's value only: `swp(ys, xt)` under
`(Cons(_, xt), _)` stays unproved (neither position decreases).

The example above, with the type named `Chain`, now reflects `same` and admits `refl`. Named `T`
it still does not: `Crdt.T` declares the same short name at the same arity, the clash of
`2026-11-03-reflect-type-name-clash-with-stdlib`.

`Session.Theory`'s hand-written `same`/`same_bs` and its `same_eq` lemma could now use the
derived `==` directly; left as is (it proves, and changing it moves the lemma manifest).

| Check | Result |
|---|---|
| `reflect-lemma` `derived_eq` cases: `same` reflected and `refl` admitted; `zlen` over `match (xs, ys)` reflected; control `swp(ys, xt)` not reflected | RED (cases 1-2) → GREEN; control green before and after |
| `reflect-lemma` group | 93/93 |

