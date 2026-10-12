# `~H`: a path hole could be a dot segment — FIXED

**Found:** 2026-10-11, while taking the next URL slice of
[`todos/2026-08-06-ctxesc-no-subsidiary-automata.md`](../todos/2026-08-06-ctxesc-no-subsidiary-automata.md)
(after [the scheme fix](2026-10-11-h-sigil-url-scheme-automaton.md)).
**Fixed:** 2026-10-11.

## What was wrong

After the scheme settles, every hole in a URL attribute was one flat `urlmid`
component and got the percent-encoding component escaper. That stops a value
writing `/`, `?`, `#`, `@` or `:`, but it leaves `.` alone (unreserved), so a
value of nothing but dots filled a path segment and became a dot segment:

| Template | Value | Rendered | Browser resolves to |
|---|---|---|---|
| `href="/users/${id}/edit"` | `..` | `/users/../edit` | `/edit` |
| `src="/static/${f}"` | `..` | `/static/..` | `/` |
| `href="/a/.${x}/b"` | `.` | `/a/../b` | `/b` |

That is a client-side path traversal for every attribute that fetches or
navigates (`src`, `action`, `formaction`, `ping`, ...). Percent-encoding
cannot fix it: the URL parser reads `%2e` as `.` when it removes dot segments.

## The fix

- **Positions.** `urlmid` now means the path (or authority). A literal `?`
  moves the walk to `urlquery`, a literal `#` to `urlfragment`, from any URL
  position whose scheme is settled or open. The `#` of a `&#` character
  reference is consumed first so it does not count: without that,
  `href="/a/&#46;${x}/b"` read as a fragment and rendered `/a/../b`.
- **Escaper.** New `url_path` (id 10, `MARCH_ESC_URL_PATH`): the component
  escaper, except that an all-dot value becomes `zSoyz`. Path-class holes
  (`urlmid`, `urlscheme`, `urlschemeholemid`) get it; query and fragment holes
  keep `url_component`, since a dot segment means nothing there and `?q=..` is
  data. `TrustedUrl` covers the new id in both backends.

## Tests

- `test/test_ctxesc.ml` "rendered-output attack corpus":
  - `url path holes cannot traverse`: 10 path shapes (literal neighbours `.`,
    two holes, unquoted, `form action`, after a whole-URL hole, after a `&#46;`)
    × 13 dot-ish payloads (`..`, `.%2e`, `%2E%2E`, `..\admin`, ...) in every
    hole, resolved the way a browser does (references decoded, `\` as `/`, dot
    segments incl. percent spellings removed): the result stays under the
    template's literal prefix. Fails on the pre-fix escaper with
    `/users/../edit resolves to /edit`, and without the `&#` rows.
  - `url positions split path, query, fragment`: which escaper each position gets.
  - `url query and fragment keep dots`: the refusal is confined to the path.
  - `url templates keep their escapers`: updated, path holes now `url_path`.
- `test/test_ctx_escape.c`: the C escaper, including `%2e%2e` (encoded, so not
  a dot segment) and the id table.
- `test/native/h_escape_ctx_builtin`: compiled/interpreted parity for id 10.

Blast radius, measured with `scan_templates.exe` over `stdlib/`, `test/`,
`examples/`, `forge/`, forgepm, conduit, blog_app and test_conduit_app: 0
templates break; 16 holes moved to `url_path`, 4 query holes stay
`url_component`.

## Not done

A template that writes a raw `%` (or `&#37;` / `&percnt;`) right before a path
hole lets the hole finish a `%2e`. Recorded in the todo; the authority
position and CSS `url()` composition are also still open there.
