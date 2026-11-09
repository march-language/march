`[P1]` Two stdlib security bugs from the 2026-10-20 doc sweep — DONE (2026-11-09).

Found by `specs/progress/2026-10-18-stdlib-doc-coverage.md`; first item of the
road-to-1.0 Phase 5 burn-down (`specs/plans/2026-09-28-road-to-1.0.md`).

## 1. `ClusterAuth.verify` compared HMAC proofs with `==`

`stdlib/cluster_auth.march` `verify` did `prove(secret, nonce) == proof`. String equality
exits at the first differing byte, so response time leaks how many leading bytes of a forged
shared-secret proof were right.

Fix: `Crypto.secure_compare(prove(secret, nonce), proof)`. A constant-time compare already
existed (`stdlib/crypto.march`, used by `Crypto.verify_password`), so no new helper was
added: it walks both strings to the end of the longer one, accumulating a difference count,
and checks the lengths separately, never returning early. No `secure`/`constant_time`
builtin exists in the typechecker or runtime.

Tests (`test/stdlib/test_cluster_auth.march`): equal-length proofs that differ only in the
first or only in the last byte, a correct proof with bytes appended, a truncated proof and
an empty proof are all rejected; the existing accept/reject cases still hold. These pass
before the fix as well: constant time is a property of running time, not of the answer,
and is not unit-testable. The tests pin that the switch kept the answers right.

## 2. `DataFrame.to_html` escaped only the first special character (XSS)

`stdlib/dataframe.march` private `html_esc` nested `string_replace`, which replaces only the
first occurrence, so `<b>x</b><script>` rendered with every `<` after the first left raw.

Fix: `string_replace_all` for each pass, `&` first, and `'` → `&#39;` added (matching
`Html.escape` and `Plot`'s `svg_escape`). The `to_html` doc's "do not feed it untrusted text"
caveat is replaced by a statement of what is escaped.

Tests (`test/stdlib/test_dataframe.march`, "to_html escaping"): a header and a cell with
several `<`, `>`, `&`, `"` and `'` render with no raw `<script`/`</script` and with exactly the
expected entities; an already-escaped `&lt;&lt;` renders as `&amp;lt;&amp;lt;`. Both failed
before the fix.

Sibling sweep: no other stdlib escaper uses `string_replace`/`String.replace` (`Html.escape`,
`Html.escape_attr`, `Plot.svg_escape`, the XML and JSON escapers all replace every match or
scan char by char). `String.replace` itself is the only other caller and is documented as
first-match.
