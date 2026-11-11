`[P3]` Logger.format_text and format_logfmt print atom field values with two colons (2026-11-11)

`value_to_string_lit` renders `LAtom(a)` as `":" ++ to_string(a)`, and `to_string` of an atom already includes the leading colon. Atom fields come out as `::ok`. `format_json` uses `to_string(a)` alone and prints `":ok"`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let e = Logger.LogEntry(Logger.Info, "m", 0, "", [Logger.LogField("status", Logger.a(:ok))])
  println(Logger.format_text(e))
  println(Logger.format_logfmt(e))
  println(Logger.format_json(e))
  println(to_string(:ok))
end
end
```

Expected: `[INFO] m {status=:ok}`

Actual (interpreted / compiled): `[INFO] m {status=::ok}` / same

Source: `value_to_string_lit` in stdlib/logger.march.
