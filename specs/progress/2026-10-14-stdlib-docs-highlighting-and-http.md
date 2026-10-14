# Stdlib API reference: syntax highlighting, prose-as-code, type docs, Http (2026-10-14)

Reported: pages such as `docs/stdlib/Actor.html` had no syntax highlighting, and
`docs/stdlib/Http.html` was mostly empty stubs.

Root causes, all in the `march_doc` generator (separate repo, march-language/march_doc),
except the last:

- **No highlighting.** `Highlight.highlight` only ran on fences tagged with a language,
  and stdlib doc comments use bare fences and indented blocks; the page CSS also had no
  `.tok-*` rules, so even a tagged fence rendered monochrome. Now every untagged or
  indented block is highlighted as March (keywords from `lib/lexer/lexer.mll`, upper-case
  names as types/constructors, `--` comments, `"` strings only: March has no char
  literal), with colours for both themes.
- **Prose rendered as code.** A `doc """` body kept its source indentation, so each
  paragraph after the first began with two spaces and the markdown renderer (2-space
  indented-code rule) turned it into a `<pre>`. Bodies are now dedented to their own
  margin, and indented code blocks are stripped of their common indent. Pages with a
  prose paragraph inside `<pre>` went from 28 modules to 1 (Hamt, a deliberate pseudo-code block).
- **Every type rendered empty.** The language rejects `doc` before a `type` (parser.mly),
  and the generator ignored `--` comments, so a type's comment never reached the page. The
  `--` block directly above a `type`/`ptype`/`interface` is now its description (section
  rulers like `-- ---- X ----` excluded).
- **Http stubs.** 39 of Http's 57 public items had no doc at all. All now documented;
  `encode_query`/`set_query` say plainly that they do not percent-encode (point to
  `Uri.encode_query`). `http` added to the doctest runner's pure-module allowlist: its 23
  examples run and pass.

Also fixed while there: the march_doc test suite no longer compiled against the current
compiler (`Option(TypeRef)` `==` without `Eq`; missing `needs IO.Console/IO.Process`).

Audit totals after regeneration: 616 of 2,814 public items (22%) still have no
description, down from 852 (30%). Remaining backlog:
`specs/todos/2026-10-14-stdlib-doc-coverage-backlog.md`.
