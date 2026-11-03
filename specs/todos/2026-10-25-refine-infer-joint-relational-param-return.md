# `[P4]` `--refine-infer`: a relation kept from parameter to return (`bump`) is not proposed

Filed 2026-10-25 from `specs/progress/2026-10-25-refine-infer-vocab.md` (item 3).

```march
fn bump(a : Assoc(Int, Int)) : Assoc(Int, Int) do
  match a do
    ANil -> ANil
    ACons(k, v, t) -> ACons(k, v + 1, bump(t))
  end
end
fn go(a : Assoc({x : Int | true}, {y : Int | y > x})) : Int do need_arel(bump(a)) end
```

The checker proves `bump : Assoc({x : Int | true}, {y : Int | y > x}) -> (same)` (test
"a recursive map keeping the relation is proved by the self-call hypothesis"). Inference
proposes relations one root at a time, from a demand: the return alone is not TRUE without
the parameter's relation, and the parameter alone closes nothing in `bump`'s body.

Needs a joint candidate (parameter and return together, one atomic probe):
- TRUE: the element-return gate under the parameter hypothesis;
- caller impact: the precondition rule (no new caller violation);
- USEFUL: a caller site closes;
- applied as two edits, like K6's "callback / return" pair.
