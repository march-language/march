`[P2]` DateTime.day_of_week returns a negative number for dates before 1969-12-28 (2026-11-11)

`day_of_week` computes `int_mod(days + 4, 7)`, and `int_mod` truncates toward zero. For any date more than four days before the epoch the result is in -6..-1 instead of 0..6. The doc string notes it; callers indexing a weekday table get a wrong day or an out-of-range index.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(to_string(DateTime.day_of_week(DateTime(Date(1969, 12, 28), Time(0, 0, 0)))))
  println(to_string(DateTime.day_of_week(DateTime(Date(1969, 12, 27), Time(0, 0, 0)))))
  println(to_string(DateTime.day_of_week(DateTime(Date(1969, 12, 25), Time(0, 0, 0)))))
  println(to_string(DateTime.day_of_week(DateTime(Date(1900, 1, 1), Time(0, 0, 0)))))
end
end
```

Expected: `0`, `6`, `4`, `1` (1900-01-01 was a Monday)

Actual (interpreted / compiled): `0`, `-1`, `-3`, `-6` / same

Source: `day_of_week` in stdlib/datetime.march.
