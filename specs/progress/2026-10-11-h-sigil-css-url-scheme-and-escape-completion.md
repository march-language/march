# `~H`: CSS `url()` scheme composition, and a hole finishing an escape — FIXED

**Decided:** 2026-10-11, by the repo owner, on two items left open in
[`todos/2026-08-06-ctxesc-no-subsidiary-automata.md`](../todos/2026-08-06-ctxesc-no-subsidiary-automata.md)
by [the scheme fix](2026-10-11-h-sigil-url-scheme-automaton.md) and
[the path fix](2026-10-11-h-sigil-url-path-dot-segments.md):

1. CSS `url(${s}:x)` becomes a compile error, the same rule as `href`.
2. A literal `%` (or `&#37;`) right before a URL path hole is rejected.

**Fixed:** 2026-10-11. Table-only change (`specs/security/html-contexts.tbl`,
plus the new `attr` names in `lib/ctxesc/context.ml` and their escaper mapping
in `lib/ctxesc/automaton.ml`). No escaper changed, so the C runtime, the
interpreter and the parity tests are untouched.

## What was wrong

Each escaper judges ONE value. Both items are compositions the escaper cannot
see: the template writes part of a construct and the hole writes the rest.

| Template | Value | Rendered | Browser reads |
|---|---|---|---|
| `href="/users/.%${x}/edit"` | `2e` | `/users/.%2e/edit` | `/edit` |
| `href="/users/.&#37;${x}/edit"` | `2e` | same, after the HTML decode | `/edit` |
| `href="/users/.&#${x}/edit"` | `46` | `/users/.&#46/edit` | `/edit` |
| `href="javascript&#${x}alert(1)"` | `58` | `javascript&#58alert(1)` | `javascript:alert(1)` |
| `style="background:url(${s}:x)"` | `javascript` | `url(javascript:x)` | scheme `javascript` |
| `<style>…url("javascript\${x}x")` | `00003a` | the CSS escape for `:` | scheme `javascript` |

The fourth row is new: it was found while closing item 2, it is executable,
and it is the reason the reference rows reject a hole after ANY reference
while the scheme is open. The HTML parser decodes a numeric reference without
its `;`, so the hole only has to supply the digits.

## The fix

- **URL path.** `urlpct` (after `%` or `&percnt;`), `urlpct1` (after `%` and
  one hex digit) and `urlref` (after a numeric reference, finished or not)
  reject a hole. The table cannot decode a reference, so it rejects the hole
  after any of them, not only one that spells `%`. A literal `%` in any
  open-scheme position also goes to `urlpct`: `%` cannot be part of a scheme,
  so it settles it.
- **URL scheme.** `urlschemeref` is `urlscheme` after a reference (`&`); a
  hole there is rejected. `&percnt;` right after a scheme hole is rejected
  outright, as `&#` and `&colon;` already were.
- **CSS `url()`.** `cssurl` is now only the start of the url(); `cssurlscheme`
  (literal scheme-shaped text), `cssurlhole` (a hole wrote into the open scheme:
  `:`, `&` and `\` rejected), `cssurlref` (a reference or CSS escape a hole
  could finish: hole rejected) and `cssurlmid` (settled). Generated identically
  for the `style` attribute and the `<style>` body; only the exit on `)`
  differs. All five give a hole the same `css_url` escaper as before.

## Tests

`test/test_ctxesc.ml`, "rendered-output attack corpus":

- `url escape-completion exploits do not compile`: 16 shapes. **All 16
  compiled on the base** (each failure message names the rendered URL and the
  path or scheme it resolves to).
- `css url scheme exploits do not compile`: 15 shapes, attribute and body.
  **All 15 compiled on the base.**
- `url complete escapes keep compiling` and `css url templates keep
  compiling`: what must not break (complete escapes, `%` in a query,
  `&quot;`-quoted url(), `@import url(...)`, two url()s in one body ...).
- `css url corpus renders no dangerous scheme`: 9 honest shapes × 16 payloads
  in every hole.
- Two existing cases moved: `/a/&#46;${x}/b` (a hole right after a
  reference) is now a compile error, so "numeric reference is not a fragment"
  writes a byte between them and the traversal corpus uses `/a/%2e${x}/b`
  instead.

Blast radius, measured with `scan_templates.exe` over `stdlib/`, `test/`,
`examples/`, `forge/`, forgepm, conduit, blog_app and test_conduit_app: output
identical to the base table's (240 templates, 413 holes, 0 would break, no
escaper changed).

## Not done

- `css_url` keeps `&`, `#` and `;`, and a `style` attribute decodes references,
  so ONE hole of `javascript&#58;x` still renders a `javascript:` url() there.
  Not executable in any current browser; the fix is an escaper design choice.
  Recorded in the todo.
- The URL authority position is still flat (todo).
