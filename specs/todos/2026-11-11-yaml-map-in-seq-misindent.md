`[P2]` Yaml.to_string misindents a map inside a sequence; the round trip loses data (2026-11-11)

A `YMap` inside a `YSeq` is emitted with its first key after `- ` plus the nested pad, and the remaining keys at a different column. `Yaml.parse` reads back only the first key of the first element and drops the rest, returning `Ok`. A top-level sequence also starts with a stray newline.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let v = Yaml.YSeq([Yaml.YMap([("a", Yaml.YInt(1)), ("b", Yaml.YInt(2))]), Yaml.YMap([("c", Yaml.YInt(3))])])
  let out = Yaml.to_string(v)
  println(out)
  println("--")
  println(to_string(Yaml.parse(out)))
end
end
```

Expected: `Ok(YSeq([YMap([("a", YInt(1)), ("b", YInt(2))]), YMap([("c", YInt(3))])]))`

Actual (interpreted / compiled): `Ok(YSeq([YMap([("a", YInt(1))])]))` / same

Source: `value_to_yaml` (YSeq arm) in stdlib/yaml.march.
