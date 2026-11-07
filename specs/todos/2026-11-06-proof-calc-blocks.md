`[P2]` `calc` blocks: equational proofs with per-step obligations and diagnostics.

Quick win 2 of `2026-11-06-verification-ladder-roadmap`. Dafny's `calc`.

## Wanted

```march
calc do
  sum_int(reverse(append(xs, ys)))
  == sum_int(append(reverse(ys), reverse(xs)))  by List.reverse_append(xs, ys)
  == sum_int(reverse(ys)) + sum_int(reverse(xs)) by List.sum_int_append(reverse(ys), reverse(xs))
  == sum_int(ys) + sum_int(xs)                   by do List.sum_int_reverse(ys); List.sum_int_reverse(xs) end
end
```

Each step `a op b by hint` is its own obligation (with only its hint's facts, as in
`2026-11-06-proof-assert-by`); the chain's conclusion (first `op`-composed-with-last, for `==`,
`<`, `<=`, `==>`) is then assumed. Allowed operators compose transitively (`==` with `<=` gives
`<=`, and so on); a mixed chain that does not compose is a compile error.

## Why

Long proofs become readable, and a failure says which step does not follow and why, with that
step's counterexample, instead of one large undecided goal. This is where March's
executed-counterexample diagnostics pay most.

## Done when

- Syntax, desugar to a sequence of scoped asserts, per-step `--refine-report-sites` rows
  (`calc step 2`), a failing step's diagnostic naming the step.
- A test with a deliberately wrong middle step reports that step only.
- Docs in `specs/lang/lemmas.md`; tree-sitter grammar.
