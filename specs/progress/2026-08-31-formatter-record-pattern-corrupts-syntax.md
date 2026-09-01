# Formatter corrupted non-shorthand record patterns

`--fmt` (and the LSP formatting request, which shares `March_format.Format`)
turned `{ left: l, right: r }` into `{ left = l, right = r }`. That's
record-*construction* syntax; record *patterns* require `field: binder`, so
the reformatted file no longer parsed at all — every formatter pass on a
function whose parameter destructured a record with a renamed binder broke
the file it was supposed to prettify.

## Root cause

`lib/format/format.ml`, `fmt_pat`'s `PatRecord` case, printed each
non-shorthand field with `Printf.sprintf "%s = %s" n.txt ps` — reusing the
separator from the `ERecord` (record-literal) printer instead of the pattern
separator. The shorthand branch (binder name equals field name, e.g.
`{ x, y }`) was unaffected, since it never reaches the `sprintf` call.

## Fix

`lib/format/format.ml:252`: `"%s = %s"` → `"%s: %s"`.

Added a regression case (`test_record_pattern`) to `test/test_fmt.ml`,
alongside the existing `test_record_literal`, using a renamed binder
(`{ left: l, right: r }`) so it actually exercises the non-shorthand branch.
Verified the oracle goes RED without the fix (`check_parses` fails: "formatted
source does not parse") and GREEN with it, via `test/test_fmt.exe`.

## Evidence

- `./_build/default/test/test_fmt.exe -e` — 33/33, including the new case.
- `scripts/run-tests.sh -q` — all suites pass.
