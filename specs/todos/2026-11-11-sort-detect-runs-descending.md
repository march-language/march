`[P3]` `Sort.timsort_by` does not detect descending runs (2026-11-11)

`detect_runs` only extends a run while `cmp(prev)(h)` holds, so a strictly descending input splits into
one-element runs that are each padded to 16 by insertion. The result is correct; the cost is the lost
O(n) best case on reversed input. The doc string of `detect_runs` now states this. Performance only.

Repro:

```march
mod A do
needs IO.Console
needs IO.Clock
fn main(_c : Cap(IO.Console), _k : Cap(IO.Clock)) do
  let t0 = unix_time(())
  let ys = Sort.timsort_by(List.reverse(List.range(0, 20000)), fn a -> fn b -> a <= b)
  println(to_string(List.length(ys)) ++ " sorted in " ++ to_string(unix_time(()) -. t0) ++ " s")
end
end
```

Expected: a reversed list costs about the same as an ascending one (one run, one reversal).

Actual (interpreted / compiled): descending 20000 elements takes about 12x the ascending time compiled (0.0052 s against 0.0004 s) and 2.6x interpreted (0.44 s against 0.17 s).

Source: `detect_runs` (`scan_run`) in `stdlib/sort.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
