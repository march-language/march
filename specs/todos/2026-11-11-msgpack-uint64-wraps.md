`[P2]` Msgpack.decode silently wraps a uint64 that does not fit March's 63-bit Int (2026-11-11)

A `0xcf` uint64 at or above 2^62 does not fit a 63-bit signed Int. `from_int64` uses wrapping arithmetic, so the decoder returns `Ok` with a different (often negative) number instead of an error. 2^63 decodes to 0. The doc string mentions the wrap, but a decoder that returns a wrong number for valid input cannot be used on untrusted data.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(to_string(Msgpack.decode([207, 255, 255, 255, 255, 255, 255, 255, 255])))
  println(to_string(Msgpack.decode([207, 128, 0, 0, 0, 0, 0, 0, 0])))
  println(to_string(Msgpack.decode([207, 64, 0, 0, 0, 0, 0, 0, 0])))
  println(to_string(Msgpack.decode([207, 127, 255, 255, 255, 255, 255, 255, 255])))
end
end
```

Expected: `Err("uint64 out of range")` or similar

Actual (interpreted / compiled): `Ok(Int(-1))`, `Ok(Int(0))`, `Ok(Int(-4611686018427387904))`, `Ok(Int(-1))` / same

Source: `decode_one` (format 207) and `from_int64` in stdlib/msgpack.march.
