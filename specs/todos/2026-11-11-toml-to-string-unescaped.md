`[P2]` Toml.to_string does not escape strings, so its output is not TOML (2026-11-11)

`Toml.to_string` wraps a `TStr` in double quotes without escaping `"`, `\` or newlines. The doc string now says the output is for display only, but the module has no other serializer, so a value cannot be written back as TOML. A string containing `"` produces text that `Toml.parse` rejects, and a string containing `\t` comes back as a tab.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let v = Toml.TTable([("k", Toml.TStr("a\"b\\c\nd"))])
  let out = Toml.to_string(v)
  println(out)
  let v2 = Toml.TStr("x\", evil = \"1")
  let d = "k = " ++ Toml.to_string(v2)
  println(d)
  println(to_string(Toml.parse(d)))
  println(to_string(Toml.parse("k = " ++ Toml.to_string(Toml.TStr("a\\tb")))))
end
end
```

Expected: `k = "x\", evil = \"1"` that parses back to the same string

Actual (interpreted / compiled): `k = "x", evil = "1"` then `Err(TomlError("unexpected ',' after value", 1, 7))` / same

Source: `to_string` in stdlib/toml.march.
