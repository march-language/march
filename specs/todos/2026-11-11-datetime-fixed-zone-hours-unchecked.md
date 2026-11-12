`[P3]` DateTime.fixed_zone_hours builds zones outside the +/-14 h range that fixed_zone rejects (2026-11-11)

`fixed_zone` carries a refinement and a runtime check for -50400..50400 seconds. `fixed_zone_hours` builds the `Tz` constructor directly, so any hour count is accepted and an invalid zone such as `+1000:00` can be created. `fixed_zone_hm` has the same shape for its hours argument.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(to_string(DateTime.fixed_zone_hours(15)))
  println(to_string(DateTime.fixed_zone_hours(-99)))
  println(to_string(DateTime.fixed_zone_hours(1000)))
end
end
```

Expected: a refinement error or panic, as `fixed_zone("x", 54000)` gives

Actual (interpreted / compiled): `Tz("+15:00", 54000)`, `Tz("-99:00", -356400)`, `Tz("+1000:00", 3600000)` / same

Source: `fixed_zone_hours` in stdlib/datetime.march.
