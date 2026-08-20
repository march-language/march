# `~H` has no subsidiary automata — nested languages are handled coarsely

**Filed:** 2026-08-06
**Priority:** ~~P3 — a correctness/usability defect, not a known vulnerability~~
**Re-rated 2026-08-20: the JS half of this divergence WAS a vulnerability.**
See `specs/progress/2026-08-20-h-sigil-js-and-url-attr-xss.md`.

## Status

- **CSS `url()` — DONE.** `cssurl` / `EscCssUrl` landed; the two symptoms in
  "The cost, measured" below no longer reproduce.
- **JS — DONE, and it was exploitable.** Fixed 2026-08-20. A hole in a
  `<script>` body or an `on*` handler got the JS *string* escaper regardless of
  whether it sat inside a string literal, so `<script>var x = ${p}</script>`
  rendered `alert(document.cookie)` as executable code. The table now tracks JS
  string literals, comments, regex literals and template literals, and
  expression position has its own escaper.
- **URL — still flat**, and still not known to be exploitable; see below.

## What this file got wrong, which is the part worth keeping

The technical analysis was right. The **risk assessment** was not, and the way
it was wrong is reusable:

> the P3 rating reasoned through URL and CSS only, and concluded "not currently
> reachable" / "not exploitable as it stands". It never analysed JS — the one
> nested language where the same divergence *was* exploitable.

The flattening was a deliberate, documented trade-off, and the trade-off is
still defensible for URL. The defect was scoping the risk to the two languages
that had been looked at and rating the whole divergence from them. A divergence
from a security design is only as safe as its **worst** instance, and the
instance nobody examined is not evidence of safety.

It also left the deciding question open, and then did not come back to it:

> "The full paper design ... is only worth it if a nested language appears whose
> *position* matters in ways the flat model cannot express. The `url(` case does
> not need it."

JS was that language. Position was the entire difference between "inside a
string literal, where escaping the delimiters is exactly right" and "in open
code, where there are no delimiters and escaping them accomplishes nothing".

## What the paper does

> "Subsidiary automata handle processing of nested content languages. Upon
> encountering `<a href=`, the HTML automaton spins up a URL parsing automaton
> and mediates its input via an HTML attribute codec."

The codec "decodes content as seen by the HTML automaton and re-encodes any
modifications made by the URL automaton", and the subsidiary relationship is
tracked alongside the context value.

## What we do instead

The nested language is flattened into the `attr` field of the 4-tuple, and the
escaper does that language's work in one shot. There is no separate automaton
object and no codec. The JS fix went further than the earlier ones — it uses
`attr` for the JS position AND `delim` for the open string literal's quote — but
it is still a flat encoding of a sub-automaton, not a nested one.

| Nested language | Sub-positions | Escapers |
|---|---|---|
| URL | `url` → `urlmid` | `EscUrlWhole`, `EscUrlComponent` |
| CSS | `style` → `stylevalue` → `cssurl` | `EscCssDecl`, `EscCssValue`, `EscCssUrl` |
| JS | `script` ⇄ `jsstring`, plus `jscomment` / `jsregex` / `jstemplate` | `EscJsExpr`, `EscJsString` |

## What is left

**URL.** A real URL automaton would track scheme / authority / path / query /
fragment; we have two positions. The codec's absence is still not exploitable,
because the attribute escaper escapes `&` after the URL check, so an entity
cannot be decoded a second time:

```
href="${'javascript&#58;alert(1)'}"  ->  href="javascript&amp;#58;alert(1)"
```

Note that this reasoning is exactly the shape that failed for JS: it argues from
the cases examined. It is recorded here as an argument, not as a clearance.

**A real nested automaton with codecs** is still not built, and the JS fix shows
the flat model can be pushed further than expected before it breaks. The
question to revisit is no longer "is the flat model expressive enough" — it is
whether the flat model's failure mode is acceptable, and the answer for JS was
that we could not tell until someone wrote an attack string and looked at the
output. See the "coverage class" note in the progress file.

## Do not "fix" this by widening the CSS allowlist

Adding `/` to the CSS-safe character set would repair a broken-URL symptom and
reintroduce a hole: `/` is how a CSS comment (`/*`) starts. The escaper's
allowlist is deliberate — see `specs/security/README.md`.
