`[P3]` DateTime.parse accepts and discards anything after the seconds field (2026-11-11)

After the seconds digits `parse` stops looking at the input. Garbage is accepted, and so is a fractional second or a UTC offset, which is then silently dropped: `2024-01-15 10:30:45+05:00` is returned as 10:30:45 UTC. A suffix after a date-only string is correctly rejected, so the two forms disagree.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(to_string(DateTime.parse("2024-01-15 10:30:45xyz")))
  println(to_string(DateTime.parse("2024-01-15 10:30:45.999+05:00")))
  println(to_string(DateTime.parse("2024-01-15xyz")))
end
end
```

Expected: `Err(...)` for all three inputs

Actual (interpreted / compiled): `Ok(DateTime(Date(2024, 1, 15), Time(10, 30, 45)))` twice, then `Err(expected ' ' or end after date)` / same

Source: `parse` in stdlib/datetime.march.
