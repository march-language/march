`[P3]` A constructor passed as a call argument fails to reflect when one of its fields mentions an unreflected `Int`.

Found proving `Set`'s insert (2026-11-08). In

```march
let bm = bitmap_set(0, s1)
wrap_slots(SBranch(bm, Cons(n1, Cons(n2, Nil))), acc)
```

`wrap_slots`'s contract `sentry_elts(_) == sentry_elts(nd)` is relational in
`nd`, so the argument `SBranch(bm, ..)` must reflect, and a field that is a
`let` of an unreflected call (or the call itself, `SBranch(bitmap_set(0, s1),
..)`, or `s1 + s2` over such lets) makes the whole argument fail: the postcondition
is solver-undecided. The same field as a parameter proves, and the same
constructor as a direct return tail proves (an `Int` payload the reflection
cannot place is an unconstrained `Int` there). `stdlib/set.march` works around
it with `wrap_pair`, which takes the bitmap as a parameter.

Fix: when reflecting a call argument at a datatype sort, give an `Int` field
that does not reflect a fresh unconstrained constant, as `reflect_at` does for
a tail (`Refine_post`, the `Smt.SInt` arm). Done when the inline form above
proves and `wrap_pair` can go.
