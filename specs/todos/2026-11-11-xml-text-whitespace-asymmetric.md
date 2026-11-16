`[P3]` Xml.parse strips leading whitespace of a text run but keeps trailing whitespace (2026-11-11)

A text run loses its leading whitespace and keeps its trailing whitespace. Neither a trimming nor a preserving reading explains that, and mixed content such as `x <b>y</b> z` loses the space before `z`. The doc string describes the behaviour, so this is a design question: trim both sides or neither.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(to_string(Xml.parse("<a>  hi  <b/>  there  </a>")))
  println(to_string(Xml.parse("<a>x <b>y</b> z</a>")))
end
end
```

Expected: `Text("  hi  ")` (preserve) or `Text("hi")` (trim)

Actual (interpreted / compiled): `Text("hi  ")` / same

Source: text-run scanning in `xml_loop` in stdlib/xml.march.
