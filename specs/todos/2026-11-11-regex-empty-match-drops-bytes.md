`[P2]` Regex.replace_all and Regex.split drop the input byte after every empty match (2026-11-11)

After an empty match at `s` both loops continue from `s + 1` but never copy the byte at `s` into the output. With a pattern that can match the empty string (`x*`, `\d*`) every unmatched byte of the input disappears. `find_all` uses the same advance and is fine because it only collects matches.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(Regex.replace_all("x*", "-", "abc"))
  println(to_string(Regex.split("x*", "abc")))
  println(Regex.replace_all("\\d*", "#", "a1b"))
  println(to_string(Regex.find_all("x*", "abc")))
end
end
```

Expected: `-a-b-c-` and `[a, b, c]` (or any result that keeps `a`, `b`, `c`)

Actual (interpreted / compiled): `----` and `[, , , ]` / same

Source: `replace_all` and `split` (`go`) in stdlib/regex.march.
