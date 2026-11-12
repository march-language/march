`[P2]` Msgpack.encode emits out-of-range values for Bin payloads (2026-11-11)

`Msgpack.bin` and the `Bin` arm of `encode_val` copy the `List(Int)` payload straight into the output. A value outside 0..255 ends up in the encoded byte list, which is then not a byte sequence at all. `decode` accepts it back, so the module's own round trip hides the problem; anything that writes the list to a socket or file truncates or fails later.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let enc = Msgpack.encode(Msgpack.bin([300, -1, 65]))
  println(to_string(enc))
  println(to_string(Msgpack.decode(enc)))
end
end
```

Expected: an error, or each value masked to a byte

Actual (interpreted / compiled): `[196, 3, 300, -1, 65]` then `Ok(Bin([300, -1, 65]))` / same

Source: `encode_val` (Bin arm) and `bin` in stdlib/msgpack.march.
