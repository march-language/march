`[P2]` Compiled Csv ignores `:simple` mode and always parses RFC 4180 quotes (2026-11-22)

`march_csv_open` (runtime/march_runtime.c) discards its `mode` argument (`(void)mode_ptr;`
"we always use rfc4180 for now") and opens every handle in RFC 4180 mode. The interpreter's
`csv_open_impl` (lib/eval/eval_net.ml) honours `:simple`, which treats `"` as an ordinary
character. A quoted field in a `:simple` file therefore splits differently by backend.

Found while fixing specs/progress/2026-11-11-csv-open-error-shape-compiled.md.

Repro (`q.csv` contains the single line `a,"b,c",d`):

```march
mod SimpleMode do
  needs IO.Console
  needs IO.FileRead
  fn main(_c : Cap(IO.Console), _f : Cap(IO.FileRead)) do
    println(to_string(Csv.read_all("q.csv", ",", :simple)))
  end
end
```

Expected (both backends, the documented `:simple` behaviour): four fields, `a`, `"b`, `c"`, `d`,
which prints as `Ok(Ok([[a, "b, c", d]]))`.

Actual (interpreted / compiled): as expected / `Ok(Ok([[a, b,c, d]]))` (three fields, quotes
stripped).

Fix sketch: pass `mode` through to `fh_open`'s rfc4180 flag (`:simple` -> 0); the row parser
`csv_parse_row_fields` already takes the flag.
