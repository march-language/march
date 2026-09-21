# `[P3]` Refinement: a true postcondition is counted `violated` with no error

Filed 2026-09-21, found while fixing
`specs/progress/2026-09-21-structural-components-trusted-by-name.md`.

```march
fn copy2(xs : List(Int)) : {List(Int) | len(_) == len(xs)} do
  match xs do
  Nil -> Nil
  Cons(h, t) ->
    match t do
    Nil -> Cons(h, Nil)
    Cons(h2, t) -> Cons(h, Cons(h2, copy2(t)))
    end
  end
end
```

The claim is true (two elements consumed, two produced, plus the induction
hypothesis on the inner tail). `--refine-report` counts it `1 violated`, yet
no error is printed and the exit code is 0 — so the ledger and the
diagnostics disagree. Behaves identically on `main` before the name fix.

Likely a tail Tier 2 cannot discharge (it needs two unfoldings of `len`)
recorded as a refutation rather than a skip. Find where the verdict is
recorded; a tail with no confirmed counterexample must be a skip, never a
violation, or `cap verified` and the report both mislead.
