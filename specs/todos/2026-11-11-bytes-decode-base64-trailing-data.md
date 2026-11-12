`[P2]` `Bytes.decode_base64` ignores everything after the first padded group (2026-11-11)

`decode_base64_go` returns as soon as it sees a group ending in `=`, without checking that it is the last
group. Concatenated or corrupted input is accepted and silently truncated, including bytes that are not
in the Base64 alphabet. The doc string now states that decoding stops at the first padded group.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(to_string(Result.map(Bytes.decode_base64("TQ==TWFu"), Bytes.to_string)))
  println(to_string(Result.map(Bytes.decode_base64("TQ==!!!!"), Bytes.to_string)))
end
end
```

Expected: `Err(...)` for both (padding is only valid in the final group).

Actual (interpreted / compiled): interpreted and compiled agree: `Ok(M)` and `Ok(M)`.

Source: `decode_base64_go` in `stdlib/bytes.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
