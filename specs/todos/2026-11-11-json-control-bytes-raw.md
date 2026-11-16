`[P2]` Json.to_string writes control bytes below 0x20 raw, producing invalid JSON (2026-11-11)

`Json.to_string` escapes only `"`, `\`, `\n`, `\r`, `\t`, `\b`, `\f`. Every other byte below 0x20 is copied through, which RFC 8259 forbids, so strict parsers reject the output. `Json.parse` is lenient and reads the raw bytes back, so the module's own round trip hides it.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let s = "a" ++ char_from_int(1) ++ "b" ++ char_from_int(31) ++ "c"
  let out = Json.to_string(Json.Str(s))
  println(to_string(Bytes.to_list(Bytes.from_string(out))))
  println(to_string(Json.parse(out)))
  println(to_string(Json.parse(Json.to_string(Json.Str("tab\there")))))
end
end
```

Expected: bytes `[34, 97, 92, 117, 48, 48, 48, 49, ...]` (`"a\u0001b\u001fc"`)

Actual (interpreted / compiled): `[34, 97, 1, 98, 31, 99, 34]` / same

Source: `escape_of` in stdlib/json.march.
