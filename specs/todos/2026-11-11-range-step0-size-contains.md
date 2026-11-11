`[P3]` `Range.size`, `Range.contains` and `Range.is_empty` die with a raw division by zero on a step-0 record (2026-11-11)

`to_list` and `each` now take the range refined as `v.step != 0` and panic with a named message on a zero
step. `size`, `contains` and `is_empty` still take the plain record, fall into the `step <= 0` branch
and divide by `0 - r.step`. The program stops with an unlabelled arithmetic error and the checker gives
no hint at the call site.

Repro:

```march
mod A do
needs IO.Console
fn rt(s : String) : Int do
  match string_to_int(s) do
  Some(n) -> n
  None -> 0
  end
end
fn main(_c : Cap(IO.Console)) do
  let r = {start: 5, stop: rt("0"), step: rt("0")}
  println(to_string(Range.size(r)))
  println(to_string(Range.contains(r, 3)))
end
end
```

Expected: either the same `v.step != 0` precondition and a named panic (`Range.size: step must be non-zero`), or a defined answer.

Actual (interpreted / compiled): interpreted and compiled agree: `Range.size` stops with `division by zero`, `Range.contains` with `modulo by zero`.

Source: `size`, `contains`, `is_empty` in `stdlib/range.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
