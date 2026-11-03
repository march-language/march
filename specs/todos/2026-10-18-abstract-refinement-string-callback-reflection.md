`[P3]` A String-sorted callback does not reflect `p` inside its declaring definition

Found 2026-10-18 while landing abstract refinements, the leftovers, phase B
(`specs/progress/2026-10-18-abstract-refinements-leftovers-phaseB.md`, test B11).
Inside a combinator over strings, a call through the definer `f : String ->
Bool[p]` does not carry its codomain `f$ret == $abs_p(h)` into the VC, so a
natural-style body never proves its `List(String[p])` return:

```march
mod S do
  fn sfilt(xs : List(String), f : String -> Bool[p]) : List(String[p]) do
    match xs do
    Nil -> Nil
    Cons(h, t) -> if f(h) do Cons(h, sfilt(t, f)) else sfilt(t, f) end
    end
  end
end
```

`--refine-report` files an `opaque-application` skip at the return (z3 answers
`sat`: the query has `f$ret` true and the goal `$abs_p(h)` but nothing linking
them; `Undecided.diagnose` then names `$abs_p` because `known_head` does not know
abstract symbols). The same body over `Int` proves. Cause: `Refine_call`'s
`foreign_var` returns `None` for a `Str`-sorted name (deliberately, to keep a
string from being declared at `Int`), so `reflect_scalar`'s postcondition arm drops
the whole `_ == p(h)` fact. Fix direction: let the codomain fact through when its
only string-sorted subterm is the argument of an abstract symbol (declared at that
argument's sort by `abstract_preamble`), and teach `known_head` the `$abs_` prefix
so a residual skip is not misreported as opaque.

Workaround today: delegate (`List.filter(xs, f)`), which proves at the String sort
(test B11 does exactly that).
