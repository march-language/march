`[P2]` `assert P by do … end`: a scoped proof hint.

Quick win 1 of `2026-11-06-verification-ladder-roadmap`. Dafny's `assert P by { … }`.

## Now

`assert P` in a body is checked and then assumed for the rest of the walk, and lemma calls add
their theorems to every later obligation in the block. A long proof therefore carries every
helper fact into every later query: slower solving, and facts that make a later proof pass for
the wrong reason.

## Wanted

```march
assert sum_int(append(xs, ys)) == sum_int(xs) + sum_int(ys) by do
  List.sum_int_append(xs, ys)
  List.len_append(xs, ys)
end
```

The block's lemma calls and `let`s are in scope only while proving `P`; afterwards only `P` is
assumed. The block is erased like a lemma body.

## Done when

- Parser, desugar (the block is ghost, erased), and the walk: obligations inside the block see its
  facts; after it, only `P`.
- A test where a later obligation would pass only through a helper fact: with `assert … by` it is
  not proved (the fact did not leak); with a plain lemma call it is.
- `specs/lang/lemmas.md` documents it; tree-sitter grammar extended (CLAUDE.md rule).
