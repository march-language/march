`[P3]` ShellRender.string/raw: the `n more chars` count disagrees with the cut on the JS target; string_grapheme_count means codepoints natively (2026-11-11)

`ShellRender.string` and `raw` cut after `limit` codepoints and report `string_grapheme_count(s) - limit` as the remainder. On the JS target `string_grapheme_count` segments real grapheme clusters, so for text with combining marks, flags or CRLF the remainder is wrong (it can undercount, and for `limit` above the grapheme count it would go negative). In the interpreter and the compiled runtime the same builtin counts codepoints, so the numbers agree there but the builtin does not do what its name says, and the three backends print different text for the same program.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let e = "é"
  let s = e ++ e ++ e ++ e
  println("codepoints/bytes=" ++ to_string(string_byte_length(s)) ++ " graphemes=" ++ to_string(string_grapheme_count(s)))
  println(ShellRender.raw(s, 2))
  println(ShellRender.string(s, 2))
  let flags = "🇫🇷🇩🇪🇯🇵"
  println("flags graphemes=" ++ to_string(string_grapheme_count(flags)))
  println(ShellRender.raw(flags, 2))
  let crlf = "a\r\nb\r\nc"
  println("crlf graphemes=" ++ to_string(string_grapheme_count(crlf)))
  println(ShellRender.string(crlf, 2))
end
end
```

Build the third run with `march --target js -o out/x.mjs FILE && node out/x.mjs`.

Expected: the same output on every backend, with a remainder that matches what was cut

Actual (interpreted / compiled): `é… 6 more chars` (interpreted and compiled); `é… 2 more chars` under `--target js` with node

Source: `string`, `raw` in stdlib/shell_render.march; `march_string_grapheme_count` in runtime/march_runtime.c; `string_grapheme_count` in lib/eval/eval_builtins.ml.
