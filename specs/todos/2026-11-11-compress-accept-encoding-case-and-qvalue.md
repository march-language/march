`[P2]` Compress.accept_encoding/best_encoding: case-sensitive matching and only three spellings of q=0 (2026-11-11)

Content codings and the `q` parameter name are case-insensitive in HTTP. `accept_encoding` only recognises the exact strings `q=0`, `q=0.0`, `q=0.00`, so `q=0.000`, `Q=0` and `q = 0` leave a rejected encoding in the list. `best_encoding` compares tokens exactly, so `GZIP` or `Br` is never chosen. The result is a response in an encoding the client refused, or no compression at all.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(to_string(Compress.accept_encoding("GZIP, Br")))
  println(to_string(Compress.best_encoding(Compress.accept_encoding("GZIP, Br"))))
  println(to_string(Compress.best_encoding(["Gzip"])))
  println(to_string(Compress.accept_encoding("gzip;Q=0, br")))
  println(to_string(Compress.accept_encoding("gzip;q=0.000, br;q=0., identity; q = 0")))
  println(to_string(Compress.best_encoding(Compress.accept_encoding("gzip;q=0.000, zstd;q=0.000"))))
end
end
```

Expected: `[GZIP, Br]` (or lowercased), `Some(br)`, `Some(gzip)`, `[br]`, `[]`, `None`

Actual (interpreted / compiled): `[GZIP, Br]`, `None`, `None`, `[gzip, br]`, `[gzip, br, identity]`, `Some(zstd)` / same

Source: `accept_encoding` (`is_zero_q`) and `best_encoding` in stdlib/compress.march.
