# `[P4]` `--refine-infer` probes `_.step != 0` on `Int` slots

Filed 2026-10-29 from the second inference evaluation
(`specs/progress/2026-10-29-refine-infer-evaluation-2.md`).

The refinement `{v : IntRange | v.step != 0}` on `Range.to_list`/`Range.new` (#1030) enters
the candidate vocabulary as `_.step != 0`. Inference then offers it to slots of any sort:
`Int` returns, `Int` element returns and `Int` fold-accumulator parameters. Every such
candidate is probed and rejected `not-true`, so each one costs a probe and can never be
proposed.

## Minimal repro

```march
mod Repro do
  fn total(xs : List(Int)) : Int do
    List.fold_left(xs, 0, fn (acc, x) -> acc + x)
  end

  fn main() : Int do
    let r = Range.new(1, 6)
    total(Range.to_list(r))
  end
end
```

`march --check --refine-infer-json repro.march` lists
`main return _.step != 0 not-true` among its rejections.

## Measured

On `test/native` (418 files) there were 79 such probes in 33 files: 42 on returns, 12 on
element returns and 25 on lambda parameters. That is 0.7% of all probes. A candidate whose
field projection does not exist on the slot's type should be filtered out before it is probed.
