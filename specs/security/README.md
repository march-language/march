# Contextual escaping tables

This directory holds the **source of truth** for `~H`'s contextual auto-escaping:
which escaper applies to an interpolation, and which interpolations cannot be
made safe at all.

The design follows Samuel, Palmer, Summa & Grayson, *Compile-time Security
Analysis and Optimization of Sensitive String Producers* (Temper Systems),
arXiv:2605.16561v1. The implementation plan is
`specs/plans/2026-08-05-contextual-autoescaping.md`.

**This file and `html-contexts.tbl` are meant to be edited by someone reasoning
about HTML parsing and injection, not about OCaml.** A build step generates the
compiler's table from the `.tbl`; a CI check fails if the generated copy drifts.

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
| `attr` | `normal` `url` `urlmid` `style` `stylevalue` `script` |
| `delim` | `none` `single` `double` `unquoted` `doublesubst` |

`element` tracks which element's content we are inside, because `<script>` and
`<style>` bodies are not HTML. `attr` is set when an attribute name is read, and
selects the subsidiary language for its value (`href` → URL, `style` → CSS,
`on*` → JS). `delim` tracks how an attribute value is quoted.

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
| `attrvalue` with `attr = script`, or `rcdata` in `script` | JS string escape |

## Escaper implementations

The escapers live in `runtime/march_ctx_escape.c` and are unit-tested standalone
by `test/test_ctx_escape.c` (no runtime, no allocator — the core works on plain
buffers, two-pass: measure, then write).

Two notes on what they refuse, since both are deliberately stricter than they
might first appear:

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

**The `MARCH_ESC_*` ids in `march_ctx_escape.h` must match `Context.escaper_id`
in `lib/ctxesc/context.ml`.** That pairing is the one cross-language contract
the generated-table drift check does not cover, so `test_ctx_escape.c` asserts
it explicitly. A mismatch would silently apply the wrong escaper.

## Regenerating

The `.tbl` is the source of truth. After editing it:

```bash
dune build --root . lib/ctxesc/emit_tables.exe
./_build/default/lib/ctxesc/emit_tables.exe
```

That rewrites `lib/ctxesc/table_data.ml` and `stdlib/ctx_table.march`. Both are
generated — do not edit them. A CI freshness check regenerates into a temporary
prefix and fails on any difference, so a forgotten regeneration cannot merge.

## Known limitations

- No regex; see the pattern table above.
- Attribute classification is by name only. An attribute whose safety depends on
  the element it is on (`<meta http-equiv>` vs elsewhere) is not modelled.
- Only the subsidiary languages HTML strictly requires are covered: URL, CSS and
  JS-string. There is no SQL or shell table yet.
