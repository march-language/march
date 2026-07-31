`[P3]` **Should `cap verified` escalate an inert `interface`-signature refinement to an error?**

Unexamined, and no test covers the combination either before or after the
2026-07-30 work. Today a `cap verified` module containing

```march
interface Runner(a) do
  fn run : a -> {Int | _ > 0} -> Int
end
```

exits 0 with a warning.

**For leaving it:** `cap verified`'s escalation machinery
(`check_call`/`check_post`'s `note`) fires on *undischarged obligations*, and an
inert interface signature raises no obligation at all — there is nothing in the
ledger to escalate. This would be new machinery, not a flipped flag.

**Against:** the mode's whole promise is "if it compiles, it is proved", and a
contract that provably enforces nothing sits awkwardly under that promise.

Filed rather than decided, so the next person does not have to re-derive the
tradeoff. Related: `2026-07-31-refine-sig-and-extern-signature-refinements-inert.md`
raises the same question for `sig`/`extern`.
