`[P2]` Yaml.to_string emits a string containing a newline unquoted, corrupting the document (2026-11-11)

`needs_quoting` does not look for `\n`, so a string with a newline and no other special character is written raw across two lines. `Yaml.parse` then reads the second line as a new key, or merges it with the next key. `yaml_str_escape` already knows how to write `\n`; it is just never reached.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let v = Yaml.YMap([("k", Yaml.YStr("line1\nline2")), ("z", Yaml.YInt(1))])
  let out = Yaml.to_string(v)
  println(out)
  println("--")
  println(to_string(Yaml.parse(out)))
  let v2 = Yaml.YMap([("k", Yaml.YStr("a\nb: 2"))])
  println(to_string(Yaml.parse(Yaml.to_string(v2))))
  let v3 = Yaml.YMap([("k", Yaml.YStr("a\nb"))])
  println(to_string(Yaml.parse(Yaml.to_string(v3))))
end
end
```

Expected: `k: "a\nb"` and `Ok(YMap([("k", YStr("a\nb"))]))`

Actual (interpreted / compiled): `Ok(YMap([("k", YStr("a")), ("b", YNull)]))` / same

Source: `needs_quoting` in stdlib/yaml.march.
