`[P3]` Compress.*.encode_stream/decode_stream map over chunks instead of streaming (2026-11-11)

`encode_stream` and `decode_stream` are `Seq.map` over the one-shot codec. Each input chunk becomes an independent gzip or zstd member, and `decode_stream` cannot decode a single compressed stream that arrives split at arbitrary byte boundaries, which is the normal shape of network or file input. The doc strings say so; the names promise more than the functions do.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let whole = Bytes.from_string("hello hello hello hello hello hello hello hello")
  match Compress.Gzip.encode(whole) do
  Err(_) -> println("encode failed")
  Ok(z) ->
    let bs = Bytes.to_list(z)
    let n = List.length(bs)
    let a = Bytes.from_list(List.take(bs, n / 2))
    let b = Bytes.from_list(List.drop(bs, n / 2))
    let out = Seq.to_list(Compress.Gzip.decode_stream(Seq.from_list([a, b])))
    println("one gzip stream split in two chunks -> " ++ to_string(out))
    let enc = Seq.to_list(Compress.Gzip.encode_stream(Seq.from_list([Bytes.from_string("aaa"), Bytes.from_string("bbb")])))
    println("encode_stream of 2 chunks -> " ++ to_string(List.length(enc)) ++ " results")
    println(to_string(enc))
  end
end
end
```

Expected: the original bytes, decoded across the chunk boundary

Actual (interpreted / compiled): `[Err(InvalidInput("gzip_decode: unexpected end of compressed data")), Err(InvalidInput("gzip_decode: inflate failed (invalid data)"))]` / same with `inflate failed`

Source: `Gzip.encode_stream`, `Gzip.decode_stream`, `Zstd.encode_stream`, `Zstd.decode_stream` in stdlib/compress.march.
