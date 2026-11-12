`[P2]` Yaml.to_string leaves Yes/True/No/NULL unquoted, so strings come back as booleans or null (2026-11-11)

`needs_quoting` compares against lowercase spellings only (`true`, `false`, `null`, `yes`, `no`, `on`, `off`). `Yaml.parse` recognises other capitalisations (`Yes`, `True`, `No`, `FALSE`, `NULL`, `Null`), so a `YStr` with one of those values changes type on a round trip.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  fn rt(s) do
    let v = Yaml.YMap([("k", Yaml.YStr(s))])
    let out = Yaml.to_string(v)
    println(out ++ "  =>  " ++ to_string(Yaml.parse(out)))
  end
  rt("Yes")
  rt("True")
  rt("No")
  rt("NULL")
  rt("On")
  rt("yes")
  rt("Null")
  rt("FALSE")
  rt("Off")
end
end
```

Expected: `k: "Yes"` and `Ok(YMap([("k", YStr("Yes"))]))`

Actual (interpreted / compiled): `k: Yes  =>  Ok(YMap([("k", YBool(true))]))` / same

Source: `needs_quoting` in stdlib/yaml.march.
