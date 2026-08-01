`[P2]` **Refinement predicates are never desugared, so a qualified spelling inside one enforces nothing.**

```march
fn inner(xs : {List(Int) | List.length(_) > 0}) : Int do …   -- enforces NOTHING
fn inner(xs : {List(Int) | len(_) > 0}) : Int do …           -- enforces the contract
```

`Desugar.respan_ty` (`lib/desugar/desugar.ml`) is the only place in desugar that
touches `A.TyRefine`, and it only respans — so inside a predicate `List.length`
stays an `EField` chain rather than the dotted `EVar` the measure alias keys on,
and the obligation is skipped.

**Done 2026-07-30:** this now *warns*, naming both the spelling found and the
bare measure that works, so it is no longer silent. The remedy is independent of
whether the alias is currently withdrawn, and a record-field call (`c.cb(1)`) is
deliberately not reported as a qualified call.

**Still open:** running predicate expressions through the desugarer the way
bodies are, so the qualified spelling means what it reads as. That is a much
larger change with its own regression surface — the warning was the right size
for the *silence*, not a fix for the capability gap.

Known limits of the current warning, both deliberate: a receiver that is itself
a call (`f(x).g(y)`) is not rendered as a path and stays silent, and it warns
once per call rather than once per predicate.
