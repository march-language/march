`[P3]` A curried callback called in two steps inside a body gives no fact

Filed 2026-10-21 by phase 2 of the multi-arg abstract refinements design
(`specs/2026-10-18-abstract-refinements-multi-arg-design.md` §5.6, §8;
`specs/progress/2026-10-21-abstract-multiarg-phase2.md`). Inside a definition that
declares a two-argument `p`, a call through the definer with all its arguments,
`keep(k, v)`, reflects to `keep$ret == $abs_p(k, v)`. A call in two steps does
not:

```march
mod M do
  type Assoc(k, v) = ANil | ACons(k, v, Assoc(k, v))
  fn filt2(a : Assoc(k, v), keep : ({x : k | true}) -> ({y : v | true}) -> {Bool | _ == p(x, y)})
      : Assoc({x : k | true}, {y : v | p(x, y)}) do
    match a do
      ANil -> ANil
      ACons(k, v, t) ->
        let g = keep(k)
        if g(v) do ACons(k, v, filt2(t, keep)) else filt2(t, keep) end
    end
  end
end
```

`keep(k)` is a partial call, so it correctly gets no postcondition (its result is a
function; test `partial_call_no_fact` in group `abstract-multiarg`), and `g(v)` has
no signature, so the `if` gives no `$abs_p(k, v)` fact and the `ACons` tail's
relation obligation is not proved. A combinator written this way (`Map.filter`'s
own style: `pred(k)` then `p(v)`) does not prove its relational return, so its
calls are `abstract-refinement-uninstantiated` ("`filt2`'s own body is not proved
…"). Since the typechecker makes a combinator that calls its callback in two steps
take a CURRIED lambda (`callback_arity_mismatch`), a curried lambda instantiates a
two-argument `p` today only for a parameter's (negative) occurrence.

Fix direction (design §5.6): record the partial application in the `lets` channel
(`g = keep(k)`, retired when `g`, `keep` or `k` is rebound) and reflect `g(v)` as
`$abs_p(k, v)` through it. `keep(k)(v)` is not March syntax (a parse error), so the
`let` form is the only one to cover. `Map.filter` (design phase 4) is `@[assume]`
for this reason and does not need it.
