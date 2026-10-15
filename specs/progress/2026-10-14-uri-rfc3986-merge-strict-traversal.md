# Uri: merge_strict traversal off-by-one, merge leading `/`, parse relative refs (2026-10-14)

Found when `stdlib/uri.march`'s doc examples became checked doctests (the
`feat/doc-examples-check` conversion, which documented the then-current behaviour). Three
bugs, fixed together because they share the dot-segment resolver and the doc examples:

1. **`Uri.merge_strict` (security).** The traversal guard is meant to return `Err` when a
   relative reference's `..` segments climb above the root. Both `merge` and
   `merge_strict` resolved dot segments over `string_split(merged, "/")`, and for an
   absolute merged path (`/a/b/../../../etc/passwd`) that list starts with an empty
   string, the marker for the leading `/`. The resolver pushed it like a real segment, so
   the first surplus `..` popped it: one `..` was absorbed before the stack counted as
   empty (against `/a/b/c`, three `..` returned `Ok`, four were needed for `Err`), and
   `string_join` of the remaining segments had lost the leading `/` (`etc/passwd`).
2. **`Uri.merge` over-traversal** dropped the leading `/` for the same reason, so
   `to_string` glued the path onto the host (`https://example.comx`).
3. **`Uri.parse`** read any scheme-less string not starting with `/` as `host/path`
   (`../d` gave host `..`, path `/d`) and had no notion of a network-path reference
   (`//other.com/x` became one long path). It also took the text before the first `://`
   as the scheme even when that `://` sat in a query.

Fix (RFC 3986 §5.2, §4.2):

- One private `remove_dot_segments(path) : (String, Bool)` implements §5.2.4 on segment
  lists: an absolute path's leading empty string is treated as the root marker, not a
  poppable segment; a `..` with nothing to pop sets `escaped` and is dropped (as the RFC
  says); a trailing `.`/`..` leaves a trailing `/`. `merge_paths` implements §5.2.3
  (base with authority and empty path merges as `/` + rpath). `resolve_reference`
  implements §5.2.2 and is shared: `merge` returns its target, `merge_strict` returns
  `Err` if `escaped`. Dot segments are now also removed for absolute-path, network-path
  and absolute references, so `/../etc/passwd` is rejected by `merge_strict` too. A
  fragment-only/empty reference keeps the base query (the old code had a no-op `new_q`
  that always dropped it, contrary to its own doc).
- `parse`: a scheme is accepted only if it contains no `/`, `?`, `#`; without one, only a
  leading `//` introduces an authority, otherwise the whole pre-`?`/`#` text is the path.
  `to_string` writes `//host` for a scheme-less reference with a host, so network-path
  references round-trip. The only in-tree caller (`forge/tasks/forge_registry.march`)
  parses absolute URLs, which are unchanged.

Docs: the `parse`, `merge` and `merge_strict` examples are back to using `Uri.parse` on
relative references and describe the RFC behaviour; the off-by-one note is gone. Each
merge example is self-contained (no shared `let base`), because `march test`'s doctest
runner chains a `let` only onto the next example, unlike `check-stdlib-doctests.py`.

Tests: new `test/stdlib/test_uri.march` (registered in `test/test_stdlib_march.ml`, which
now loads `uri.march`): parse of relative/network-path references, the traversal guard
(three/four `..`, exactly-to-root, climb-then-descend, absolute-path, root and empty
base paths), the leading-`/` regression, and the RFC 3986 §5.4.1 normal and §5.4.2
abnormal resolution examples. Against the old `uri.march` 27 of its cases fail; with the
fix all pass. `check-stdlib-doctests.py --check stdlib/uri.march`: 28 run, 0 failed.

Not changed: `URI` still has no `Eq` impl (the tests compare a field rendering), and the
URI type still cannot distinguish an empty query/fragment from an absent one, so §5.2.2's
"defined" checks are approximated by "non-empty".
