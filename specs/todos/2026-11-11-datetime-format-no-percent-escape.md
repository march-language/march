`[P3]` DateTime.format has no `%%` escape, so a literal `%Y` cannot be written (2026-11-11)

`format` is six `string_replace_all` passes. `%%` is not collapsed to `%`, and it does not protect the following letter, so there is no way to emit the literal text `%Y`, `%m`, `%d`, `%H`, `%M` or `%S`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(DateTime.format(DateTime(Date(2024, 1, 5), Time(9, 5, 0)), "100%% on %Y"))
  println(DateTime.format(DateTime(Date(2024, 1, 5), Time(9, 5, 0)), "%%Y %%d"))
end
end
```

Expected: `100% on 2024` and `%Y %d`

Actual (interpreted / compiled): `100%% on 2024` and `%2024 %05` / same

Source: `format` in stdlib/datetime.march.
