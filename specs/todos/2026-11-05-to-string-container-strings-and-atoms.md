`[P3]` `to_string` leaves strings unquoted inside lists, options and tuples.

Found 2026-11-05 surveying test failure output (test-failure reports print with `to_string`):

- `to_string(["a", "b"])` is `[a, b]`, `to_string(Some("a"))` is `Some(a)` and
  `to_string(("a", 1))` is `(a, 1)`, on both backends. But a record (`{ s: "a" }`) and a
  user constructor (`W("a")`) quote. The prelude's `Show` impls for List, Option, Result and
  tuples call `show(x)`, and `Show$String.show` is the identity. So a failed
  `assert (xs == ["a, b"])` cannot tell `["a, b"]` from `["a", "b"]`.
- ~~Compiled, `to_string((1, :ok))` prints `(1, 626102635892993007)`.~~ Fixed as of
  2026-11-09 (re-checked on `c3cd49c76`): compiled `to_string((1, :ok))`, `[(2, :err)]` and
  `Some((3, :x))` print the atom. An atom reaching `to_string` through an erased type
  variable (a generic lambda) still prints as its hash, which is
  `2026-10-11-to-string-erased-newtype.md`'s territory.
- Interpreted, a user constructor holding a non-ASCII string escapes it byte by byte
  (`W("\195\169")`); compiled prints `W("é")`.

Quoting strings in containers changes `println` output everywhere, so it is a language-level
decision (and a CHANGELOG `Changed` entry), not a test-runner fix.
