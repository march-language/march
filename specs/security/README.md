# Contextual escaping tables

This directory holds the **source of truth** for `~H`'s contextual auto-escaping:
which escaper applies to an interpolation, and which interpolations cannot be
made safe at all.

The design follows Samuel, Palmer, Summa & Grayson, *Compile-time Security
Analysis and Optimization of Sensitive String Producers* (Temper Systems),
arXiv:2605.16561v1. The implementation plan is
`specs/plans/2026-08-05-contextual-autoescaping.md`.

**This file and `html-contexts.tbl` are meant to be edited by someone reasoning
about HTML parsing and injection, not about OCaml.** A dune rule embeds the
`.tbl` into the compiler on every build, so the two cannot drift; see
"Regenerating".

## Why a table

The same table specifies two things that must never disagree:

- **what the escaper does** — which encoding an interpolation gets, and
- **what the compiler proves** — which contexts a template walks through, so an
  interpolation in an unsafe position becomes a compile error.

Writing them separately is how contextual escapers usually rot.

## The model

A template is a sequence of *fixed* chunks (literal source text) and *holes*
(`${...}` interpolations). Walking the fixed chunks through an automaton yields
a **context** at each hole; the context alone decides the escaper.

The load-bearing property, from the paper: **a hole is a single transition whose
successor context depends only on the predecessor context, never on the
interpolated value.** The escaper is chosen precisely so an interpolated value
cannot move the parser out of its context. That is why the whole walk can be
constant-folded at compile time — for `~H` there is no in-template control flow,
so there are no join points and no fixed point to compute.

If you add a row whose successor depends on what was interpolated, you have
broken that property and the compile-time analysis becomes unsound.

## Context tuple

Four fields, exactly as the paper describes:

| Field | Values |
|---|---|
| `state` | `pcdata` `rcdata` `tagname` `closetagname` `beforeattrname` `afterattrname` `beforeattrvalue` `attrvalue` `comment` |
| `element` | `normal` `script` `style` `textarea` `title` |
| `attr` | `normal` `url` `urlmid` `style` `stylevalue` `cssurl` `script` `jsstring` `jscomment` `jsregex` `jstemplate` `srcset` `htmldoc` |
| `delim` | `none` `single` `double` `unquoted` `doublesubst` |

`element` tracks which element's content we are inside, because `<script>` and
`<style>` bodies are not HTML. `attr` is set when an attribute name is read, and
selects the subsidiary language for its value (`href` → URL, `style` → CSS,
`on*` → JS). `delim` tracks how an attribute value is quoted.

### JS positions

`script` is JS at an **expression** position; `jsstring` is JS inside a
quote-delimited **string literal**. The distinction is load-bearing in the same
way `url` / `urlmid` is, and getting it wrong was a real vulnerability: the JS
string escaper only makes a value unable to END a string literal, so at an
expression position — where the template opened no literal at all — it escapes
delimiters that are not delimiting anything and lets `alert(document.cookie)`
through as code. See `specs/progress/2026-08-20-h-sigil-js-and-url-attr-xss.md`.

Inside a `<script>` body the `delim` field is free (there is no HTML attribute
around it) and carries the open literal's quote, so `'` closes only a `'` string.
Inside an `on*` attribute `delim` is taken by the HTML delimiter, and none is
needed: a raw `"` ends a double-quoted ATTRIBUTE, so the only JS string a
double-quoted handler can hold is a single-quoted one, and vice versa.

`jscomment`, `jsregex` and `jstemplate` exist to keep ONE invariant:

> the walk must never land at `jsstring` when the hole is really in expression
> position.

That is the dangerous direction — it is the bug above, reached by a different
route. Each of those three constructs can hide a stray quote (`// don't`,
`/'/`, `` `it's` ``) that would otherwise leave the quote count off by one and
hand the NEXT hole the string escaper while it sat in open code. All three
reject a hole outright: a comment hides the value until it stops being a
comment, a regex literal ends at an unescaped `/` that no escaper here escapes,
and a template literal reads `${` as a substitution — arbitrary code — and a
backtick as its terminator, neither of which the JS string escaper touches.

`jsregex` is entered by ANY `/` in expression position, because the table cannot
tell a regex literal from division without a JS parser. That bias is
deliberate: misreading division as a regex costs a compile error, while
misreading a regex as division costs a quote desynchronisation, which is the
unsafe direction.

`srcset` and `htmldoc` are not positions but refusals; see "What is rejected".

`urlmid` is `url` after at least one literal character of the value has been
seen. The distinction is load-bearing: a hole at the *start* of a URL attribute
**is** the whole URL and needs a scheme allowlist (`href="${u}"` must not accept
`javascript:`), while a hole after literal text is a *component* and needs
percent-encoding (`href="/search?q=${q}"`). Rather than add a fifth context
field, the table demotes `url` → `urlmid` on the first literal character.

### `doublesubst` — the substitution mechanism

`delim = doublesubst` means *"this attribute value was unquoted and we inserted a
`"` ourselves."* It is the paper's epsilon-transition-with-substitution
(§4.6): rather than trying to escape a value safely into an unquoted attribute —
where a single space ends the attribute and a new one begins — the automaton
**adds the quote**, and remembers to close it when the value ends.

`<div class=${x}>` therefore emits `<div class="` … `">`.

## `.tbl` file format

Line-oriented. `#` begins a comment; blank lines are ignored. Three sections,
introduced by `[tags]`, `[attrs]` and `[transitions]`.

### `[transitions]`

Five `|`-separated fields:

```
from-context | pattern | substitution | successor-context | diagnostic
```

**Contexts** are `state,element,attr,delim`. In `from-context`, `*` matches any
value of that field. In `successor-context`, `=` means "unchanged from the
matched source context".

**Patterns** — a fixed, closed vocabulary. There is deliberately **no regex
engine**: implementing and cross-validating one in both OCaml and March is
disproportionate, and HTML does not need it. Adding a pattern form is a format
version bump, not a rewrite.

| Pattern | Meaning |
|---|---|
| `lit:"<"` | matches this literal string at the current position |
| `ilit:"</script"` | as `lit`, case-insensitively — HTML tag names are case-insensitive, so `</SCRIPT>` must not slip past |
| `cls:[a-z]` | matches exactly one character in the class |
| `cls+:[a-z]` | matches one or more characters in the class (greedy) |
| `name` | matches an attribute name (`cls+:[a-zA-Z0-9-_:]`) **and classifies it** via `[attrs]`, setting the successor's `attr` field |
| `tag` | matches an element name **and classifies it** via `[tags]`, setting the successor's `element` field |
| `until:"-->"` | consumes everything up to and including this literal |
| `any` | matches exactly one character — the catch-all, tried last |
| `interp` | matches a hole rather than source text |

Character classes support ranges (`a-z`), literal members, and `\\]` / `\\\\`
escapes. They are **not** regex classes: no negation, no metacharacters.

**Substitution** — a **quoted** string emitted on this transition regardless of
the interpolated value, or empty. This is how `doublesubst` inserts its quotes,
so the common value is `"\""`. The quotes are required: a bare `"` would open a
literal that the field splitter never closes, swallowing the rest of the row.

**Diagnostic** — if present, this transition is a **compile error** and the text
is the message. Used for holes no escaper can make safe.

Rows are tried **in file order**; the first row whose source context and pattern
both match wins. Put specific rows above `any`.

### `[tags]` and `[attrs]`

```
tag-name-pattern  | element class
attr-name-pattern | attr class
```

The pattern is a literal name or a `prefix*` glob; the class is one of the
`element` / `attr` values. Matching is case-insensitive (HTML names are). **First
match wins**, so put `on*` above any broader rule and keep the `*` catch-all
last. These sections are what the `tag` and `name` patterns consult.

## Escaper selection

The escaper for a hole is implied by its **successor** context, not named in the
row — one less thing to get out of sync:

| Successor context | Escaper |
|---|---|
| `pcdata`, `rcdata` in `textarea`/`title` | HTML entity-encode |
| `attrvalue` with `attr = normal` | HTML entity-encode, plus backtick |
| `attrvalue` with `attr = url` (start of value) | URL scheme allowlist |
| `attrvalue` with `attr = urlmid` | percent-encode |
| `attrvalue` with `attr = style`, or `rcdata` in `style` | CSS **declaration** escape |
| `attrvalue` with `attr = stylevalue` | CSS **value** escape |
| `attr = cssurl`, or `rcdata` in `style` inside `url(` | CSS **url** escape |
| `attrvalue` with `attr = jsstring`, or `rcdata` in `script` inside a string literal | JS **string** escape |
| `attrvalue` with `attr = script`, or `rcdata` in `script` at expression position | JS **expression** escape |

## What is rejected

Some holes get no escaper at all, because none would be honest. These are
compile errors carrying the reason:

| Position | Why no escaper works |
|---|---|
| element name, attribute name | nothing to escape — `onerror` has no special character |
| inside an HTML comment | comment-ending sequences vary between parsers |
| inside a JS comment | the value is dead text until a newline or `*/` moves it into live code |
| inside a JS regex literal | an unescaped `/` ends the literal and everything after it is code |
| inside a JS template literal | a backtick ends it and `${` opens a substitution — arbitrary code |
| JS expression position in a **single-quoted** `on*` attribute | the JS-expression escaper's own `'` delimiters would end the attribute; use a double-quoted attribute |
| `srcset` | the value is a comma-separated candidate LIST, so a whole-URL scheme check validates only the first entry. Interpolate a single URL into `src` instead |
| `srcdoc` | the browser HTML-DECODES the attribute and parses the result as a whole DOCUMENT, so the entity escaping that makes every other attribute safe is undone before the markup is read, and `&lt;img onerror=…&gt;` fires |

`srcdoc` is arguably a third instance of the subsidiary-automata divergence —
HTML nested inside an HTML attribute is exactly the codec case the paper
describes. Rejecting is the honest answer until that exists.

## Escaper implementations

The escapers live in `runtime/march_ctx_escape.c` and are unit-tested standalone
by `test/test_ctx_escape.c` (no runtime, no allocator — the core works on plain
buffers, two-pass: measure, then write).

Two notes on what they refuse, since both are deliberately stricter than they
might first appear:

- **JS expression** does not escape a value into safety — there is no encoding
  that makes an arbitrary string safe as bare JS *code*. It stops the value
  being code: it supplies the quotes the template did not and renders the value
  as a JS **string literal**, so a payload lands as inert data and honest input
  survives as text. Both quote characters are escaped numerically, so the only
  raw quotes in its output are its own two delimiters — which is what lets one
  escaper serve a `<script>` body and a double-quoted `on*` attribute. A value
  that must reach JS as CODE goes through `Html.trust_js`, which bypasses
  escaping; that is the explicit opt-in, and it is why this position is escaped
  rather than rejected.
- **JS string** escapes both quote characters numerically too, for the same
  reason: a JS string can live inside an HTML attribute, and a backslash-escaped
  quote still contains the quote byte, which HTML has never heard of.
- **Whole-URL** is an allowlist (`http` `https` `mailto` `tel` `ftp`, plus any
  relative reference), not a `javascript:` denylist. Browsers strip leading
  whitespace and C0 control bytes before parsing a URL and ignore them *inside*
  a scheme, so `  javascript:` and `java\tscript:` both defeat a naive prefix
  check; the scheme is therefore extracted by skipping those bytes rather than
  by comparing a prefix. Anything not on the list becomes
  `about:invalid#zSoyz`.
- **CSS** is an allowlist too — anything outside `[A-Za-z0-9-_#%., ]` becomes a
  `\XX ` hex escape. That means interpolating a whole declaration
  (`style="${'color: red'}"`) will not work: the colon is escaped. This is
  intended. CSS has too many routes to a URL or an expression for a denylist to
  be credible, and a hole should be a *value*, not a declaration.

`cssurl` is the one place three languages nest at once. A hole inside
`url(...)` must be safe as a URL (so the scheme allowlist applies), as a CSS
url-token (so it must not close the paren or the quoting), and — when the CSS
sits in a `style` attribute — as an HTML attribute value. Neither the CSS nor
the URL escaper alone works: CSS escaping mangles the slashes and breaks a
perfectly good `url(/img/logo.png)`, while URL escaping leaves `)` free to close
the construct and start writing CSS. The `css_url` escaper runs the scheme
allowlist and then percent-encodes only what is structural in CSS or HTML —
percent-encoding being the right tool because the URL layer decodes it *after*
CSS and HTML have parsed.

This is the nearest thing here to the paper's subsidiary automata. It is still a
flat context rather than a nested automaton with codecs; see
`specs/todos/2026-08-06-ctxesc-no-subsidiary-automata.md` for what that would
buy and why it was not needed for this case.

**The `MARCH_ESC_*` ids in `march_ctx_escape.h` must match `Context.escaper_id`
in `lib/ctxesc/context.ml`.** That pairing is the one cross-language contract
the generated-table drift check does not cover, so `test_ctx_escape.c` asserts
it explicitly. A mismatch would silently apply the wrong escaper.

## Regenerating

Nothing to do. `lib/ctxesc/table_data.ml` embeds the `.tbl` verbatim and is
generated by a dune rule in `lib/ctxesc/dune` on every build, so drift is
structurally impossible and no freshness check is needed. Do not edit the
generated file. (An `emit_tables.exe` and a March-side `stdlib/ctx_table.march`
were planned and never built — neither exists. `stdlib/html.march` does carry a
hand-written second copy of the `[attrs]` classifications for the deprecated
`Html.tag`, kept honest by a conformance test in `test/test_ctxesc.ml` rather
than by generation.)

## Known limitations

- No regex; see the pattern table above.
- Attribute classification is by name only. An attribute whose safety depends on
  the element it is on (`<meta http-equiv>` vs elsewhere) is not modelled. `data`
  is classified as a URL everywhere, though only `<object data>` is one.
- Only the subsidiary languages HTML strictly requires are covered: URL, CSS and
  JS. There is no SQL or shell table yet.
- The JS position tracker is not a JS parser. It reads any `/` in expression
  position as the start of a regex literal, so a template that uses `/` as
  DIVISION before a hole gets a compile error rather than an escaper. The bias
  is towards the error on purpose — see "JS positions".
- A hole at a JS expression position is rendered as a string, not as the value's
  own JS type: `<script>var n = ${count}</script>` yields `'42'`, not `42`.
  That is deliberate (a number is a program fragment, and admitting program
  fragments is the vulnerability), but it is a silent change of meaning rather
  than a loud one. Making it loud needs the typechecker to know the `Trusted*`
  types so it can reject an untrusted value here and point at `Html.trust_js`;
  see `specs/todos/2026-08-06-ctxesc-no-subsidiary-automata.md`.
- `srcset` is rejected rather than escaped. A per-candidate URL escaper would be
  a new escaper, not a table edit; rejecting is the conservative placeholder.
