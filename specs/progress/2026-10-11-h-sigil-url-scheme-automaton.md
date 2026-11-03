# `~H`: a hole could choose a URL's scheme through a literal `:` — FIXED

**Found:** 2026-10-11, while scoping the URL slice of
[`todos/2026-08-06-ctxesc-no-subsidiary-automata.md`](../todos/2026-08-06-ctxesc-no-subsidiary-automata.md).
**Fixed:** 2026-10-11.

That todo recorded the flat URL model as "not known to be exploitable" and
warned that the argument came from the cases examined. Writing an attack string
for the unexamined case found it.

## What was wrong

A URL attribute had two positions. A hole at the very start got the whole-URL
escaper (a scheme allowlist); the first literal character moved the value to
`urlmid`, where holes are percent-encoded components. The allowlist checks the
scheme of one value, so text after that value could still extend it:

| Template | Values | Rendered before |
|---|---|---|
| `href="${s}://${r}"` | `s = "javascript"`, `r = "\nalert(1)//"` | `javascript://%0Aalert%281%29%2F%2F` (runs `alert(1)`) |
| `href="${a}script:alert(1)"` | `a = "java"` | `javascript:alert(1)` |
| `href="java${b}:alert(1)"` | `b = "script"` | `javascript:alert(1)` |

`javascript` has no colon, so the allowlist reads it as a relative reference;
the template's own `:` then makes it the scheme. Percent-encoding in the rest
of the URL does not help: a `javascript:` URL is percent-decoded before it runs.
Reproduced through `march` on the interpreter before the fix.

## The fix

A scheme sub-automaton in the `attr` field (`specs/security/html-contexts.tbl`,
"URL scheme tracking"): `url` → `urlscheme` (literal scheme-shaped text only) /
`urlschemehole` (a whole-URL hole wrote into the open scheme) /
`urlschemeholemid` (a hole wrote into it and more text followed) → `urlmid`
(settled). In the two hole positions a literal `:`, `&#` or `&colon;` is a
compile error. `&` and `;` keep the scheme open because they spell character
references, and tab/CR/LF keep it open because the URL parser deletes them.
Unquoted URL values get the same rows (`beforeattrvalue,*,url,*`).

Two mechanism changes were needed:

- `Automaton.consume_literal` now honours a diagnostic on a LITERAL row. The
  README always said a diagnostic makes a transition a compile error, but until
  now only `interp` rows carried one and the literal walk ignored the field.
- The desugar no longer adds a second "does not end in a well-formed state"
  error after a literal chunk is rejected.

Escapers are unchanged except for one case: a hole after nothing but leading
whitespace (`href=" ${u}"`) is now the start of the URL (the URL parser strips
the space) and gets the scheme allowlist instead of the component escaper.

Blast radius, measured with `scan_templates.exe` over `stdlib/`, `test/`,
`examples/`, `forge/`, forgepm, conduit, blog_app and test_conduit_app: 0
templates break.

## Tests

`test/test_ctxesc.ml`, "rendered-output attack corpus":

- `url scheme exploits do not compile`: 15 exploit shapes (including the
  three above, unquoted values, tab, `&#58;`, `&#x3a;`, `&colon;`, `&Tab;`, an
  entity in the literal head, two holes, `src`) must be rejected.
- `url templates keep their escapers`: 18 legitimate shapes compile and get the
  same escapers as before.
- `url corpus renders no dangerous scheme`: 9 legitimate shapes × 15 payloads
  in every hole, decoded as a browser would (references, leading C0, tab/LF
  deletion): no `javascript:` / `vbscript:` / `data:` comes out.

- `scheme colon rejection names the scheme`: the rejection message explains
  itself.

Against the pre-fix table the exploit test fails (printing the executable
`javascript://%0Aalert%281%29%2F%2F` rendering), the message test fails, and
the escaper test fails only on the deliberate leading-space change.

## Not done

Authority/path/query/fragment are still one flat `urlmid`, and CSS `url()` has
the same composition shape (not executable in current browsers). Both are
recorded in the open todo.
