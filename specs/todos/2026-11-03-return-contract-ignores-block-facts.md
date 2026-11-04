`[P2]` A function's own refined result type does not use facts from earlier lines of its body.

Found while writing `specs/lang/lemmas.md` (2026-11-03). With
`fn twice(n : Int) : Int do n + n end`, every one of these skips (`march --check
--refine-report-sites=all`):

```march
fn grow(n : {Int | _ >= 0}) : {Int | _ >= n} do
  let r = n + n          -- solver-undecided; `n + n` as the last line alone proves
  r
end

fn grow2(n : {Int | _ >= 0}) : {Int | _ >= n} do
  twice_grows(n)         -- a proved lemma {Unit | twice(n) >= n}
  twice(n)               -- unreflectable-subject
end
```

- A `let`-bound result is `solver-undecided`: the binding's equation is not in the
  return-path query.
- A reflected call as the returned expression is `unreflectable-subject`, with or without a
  lemma call before it; the same call as an argument to a refined parameter proves.
- So a lemma's fact reaches later calls' preconditions but not the function's own return
  contract. `specs/lang/lemmas.md` ("What lemmas don't do (yet)") says so; update it when
  this is fixed.
