# `[P2]` `--refine-infer` proposes preconditions that only make the demanding branch unreachable

Filed 2026-10-21 from the inference-lite evaluation
(`specs/progress/2026-10-21-refinement-suggest-lite-evaluation.md`).

```march
pfn set_n(j : Int, n : Int, v) do
  if j >= n do v
  else set_n(j + 37, n, Array.set(v, j, 0 - j)) end   -- Array.set: 0 <= j < length
end
```

The only proposal the 416-file `test/native` corpus accepts is `n : {Int | _ <= j}`
(`array_trie_drop_leak_probe.march`). It "closes" the `Array.set` site because the `else`
branch becomes dead, not because the index is in bounds. It is admissible (closes one, opens
none) and satisfiable, but it is not a contract anyone wants. The same file also produced
`pop_n(j : {Int | _ == 0})`, which is now refused for caller violations.

Fix direction: a precondition candidate whose closed sites are closed only because the site's
path condition becomes unsatisfiable (hypothesis ∧ path ⊢ false at the site) should be rejected
(`reason: "vacuous-branch"`). That needs one solver query per closed site, asking whether the
site's own path condition is consistent with the hypothesis.
