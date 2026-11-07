`[P2]` A derived `Eq` on a recursive type is not reflected, so `==` on it can't be used in the logic

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
