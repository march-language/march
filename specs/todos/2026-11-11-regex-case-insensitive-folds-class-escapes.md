`[P2]` Regex case_insensitive lowercases the pattern, inverting \D, \W and \S (2026-11-11)

`fold_case` applies `string_to_lowercase` to the whole pattern text. The negated class escapes `\D`, `\W`, `\S` become `\d`, `\w`, `\s`, so a case-insensitive match means the opposite of what was written. The doc string describes it, but the result is simply a wrong match.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let ci = { case_insensitive: true, multiline: false }
  let cs = { case_insensitive: false, multiline: false }
  println("\\D vs \"5\"  sensitive=" ++ to_string(Regex.matches_opts("^\\D$", "5", cs)) ++ " insensitive=" ++ to_string(Regex.matches_opts("^\\D$", "5", ci)))
  println("\\D vs \"a\"  sensitive=" ++ to_string(Regex.matches_opts("^\\D$", "a", cs)) ++ " insensitive=" ++ to_string(Regex.matches_opts("^\\D$", "a", ci)))
  println("\\W vs \"a\"  sensitive=" ++ to_string(Regex.matches_opts("^\\W$", "a", cs)) ++ " insensitive=" ++ to_string(Regex.matches_opts("^\\W$", "a", ci)))
  println("\\S vs \" \"  sensitive=" ++ to_string(Regex.matches_opts("^\\S$", " ", cs)) ++ " insensitive=" ++ to_string(Regex.matches_opts("^\\S$", " ", ci)))
end
end
```

Expected: `insensitive=false`, `insensitive=true`, `insensitive=false`, `insensitive=false`

Actual (interpreted / compiled): `insensitive=true`, `insensitive=false`, `insensitive=true`, `insensitive=true` / same

Source: `fold_case` in stdlib/regex.march.
