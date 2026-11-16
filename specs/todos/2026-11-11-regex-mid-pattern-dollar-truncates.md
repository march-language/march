`[P2]` Regex: a `$` in the middle of a pattern silently discards the rest of the pattern (2026-11-11)

`parse_items` stops at the first `$` and treats it as the end anchor. Everything after it is ignored, including text that is not a valid pattern. `a$b` behaves as `a$`, and `^\d+$garbage(` validates `42`. A pattern assembled from pieces can lose its tail without any error.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(to_string(Regex.matches("a$b", "a")))
  println(to_string(Regex.matches("a$b", "a$b")))
  println(to_string(Regex.find("a$bcd", "xa")))
  println(to_string(Regex.matches("^\\d+$garbage(", "42")))
end
end
```

Expected: `false` for both (or a compile error for the second)

Actual (interpreted / compiled): `true`, `false`, `Some(a)`, `true` / same

Source: `parse_items` in stdlib/regex.march.
