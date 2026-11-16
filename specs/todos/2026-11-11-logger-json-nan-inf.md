`[P2]` Logger.format_json writes NaN and infinite floats as bare `nan`/`inf`, and control bytes raw (2026-11-11)

`value_to_json` prints an `LFloat` with `float_to_string`, which gives `nan`, `inf` and `-inf`. None of those is a JSON token, so the whole log line is rejected by JSON parsers, including `Json.parse`. `json_escape` also leaves control bytes other than `\n`, `\r`, `\t` unescaped (the repro prints a raw byte 1 inside the `msg` string).

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let nan = math_sqrt(-1.0)
  let inf = float_infinity()
  let e = Logger.LogEntry(Logger.Info, "m", 0, "", [Logger.LogField("x", Logger.f(nan)), Logger.LogField("y", Logger.f(inf)), Logger.LogField("z", Logger.f(0.0 -. inf))])
  let out = Logger.format_json(e)
  println(out)
  println(to_string(Json.parse(out)))
  let e3 = Logger.LogEntry(Logger.Info, "ctl" ++ char_from_int(1), 0, "", [])
  println(to_string(Bytes.to_list(Bytes.from_string(Logger.format_json(e3)))))
end
end
```

Expected: `"x":null` (or a quoted string) and a line that `Json.parse` accepts

Actual (interpreted / compiled): `{"ts":0,"level":"info","msg":"m","attributes":{"x":nan,"y":inf,"z":-inf}}` then `Err(expected 'null' but found 'a')` / same

Source: `value_to_json` and `json_escape` in stdlib/logger.march.
