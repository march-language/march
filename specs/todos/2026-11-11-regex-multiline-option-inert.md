`[P3]` Regex: the `multiline` option is accepted and ignored (2026-11-11)

`RegexOpts.multiline` is a public record field that no code reads. `^` and `$` always anchor to the whole string. The comment and doc string call it reserved; either implement line anchors or remove the field so callers do not rely on it.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let ml = { case_insensitive: false, multiline: true }
  println(to_string(Regex.matches_opts("^b", "a\nb", ml)))
  println(to_string(Regex.matches_opts("a$", "a\nb", ml)))
  println(to_string(Regex.matches_opts("^b", "a\nb", Regex.default_opts())))
end
end
```

Expected: `true`, `true`, `false`

Actual (interpreted / compiled): `false`, `false`, `false` / same

Source: `RegexOpts`, `matches_opts` in stdlib/regex.march.
