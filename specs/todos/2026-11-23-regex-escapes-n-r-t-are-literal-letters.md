`[P2]` Regex: `\n`, `\r` and `\t` outside a character class match the letters n, r and t (2026-11-23)

`parse_atom` (stdlib/regex.march, line 626) maps `\d \D \w \W \s \S` and turns every other
escaped byte into a literal of that byte, so `\n` is the letter `n`. `parse_class_body` does map
the three control escapes, so `[\n]` works and `\n` does not.

Repro (interpreted and compiled print the same):

```march
mod Rx do
  needs IO.Console
  fn main() do
    println(to_string(Regex.matches("a\\nb", "a\nb")))
    println(to_string(Regex.matches("a\\nb", "anb")))
    println(to_string(Regex.matches("[\\n]", "\n")))
  end
end
```

Actual: `false`, `true`, `true`. Expected: `true`, `false`, `true`.

Fix: add the `n`, `r`, `t` cases to `parse_atom`, matching `parse_class_body`. Patterns that
relied on `\n` meaning the letter `n` change; none exist in this repository (Regex has no callers
outside its tests).

Related, same function: a `^` that is not at the start of the pattern is a literal (`a^b` matches
the text `a^b`), while a `$` that is not at the end is treated as an anchor and discards the rest
(2026-11-11-regex-mid-pattern-dollar-truncates.md). Settle both anchors with one rule.

Found 2026-11-23 while reading the Regex todos for
specs/plans/2026-11-23-pre-1.0-bug-first-plan.md (unit U14); confirmed by running the repro on
a build of `4744a0830`.
