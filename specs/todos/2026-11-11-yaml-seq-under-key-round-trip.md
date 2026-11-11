`[P2]` Yaml round trip loses a sequence nested under a key (and the keys after it) (2026-11-11)

`Yaml.to_string` emits a sequence under a map key at the key's own indentation. That is legal YAML, but `Yaml.parse` does not read it: the key gets `YNull` and every later key of the map is dropped silently, with `Ok`. Either the serializer should indent the items or the parser should accept the compact form.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let v = Yaml.YMap([("k", Yaml.YSeq([Yaml.YInt(1), Yaml.YInt(2)])), ("z", Yaml.YInt(3))])
  let out = Yaml.to_string(v)
  println(out)
  println("--")
  println(to_string(Yaml.parse(out)))
  let v2 = Yaml.YMap([("o", Yaml.YMap([("k", Yaml.YSeq([Yaml.YInt(1), Yaml.YInt(2)]))]))])
  let out2 = Yaml.to_string(v2)
  println(out2)
  println("--")
  println(to_string(Yaml.parse(out2)))
end
end
```

Expected: `Ok(YMap([("k", YSeq([YInt(1), YInt(2)])), ("z", YInt(3))]))`

Actual (interpreted / compiled): `Ok(YMap([("k", YNull)]))` / same

Source: `value_to_yaml` (YMap arm, `YSeq(_)` case) and `parse_block_map` in stdlib/yaml.march.
