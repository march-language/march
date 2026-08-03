# `forge publish` semver enforcement is inert: its API-surface parser reads a syntax March rejects

Filed 2026-08-03, found sweeping for `-> T` return syntax after the LSP TIR tests
turned out to be written against it.

## Problem

`forge/lib/resolver_api_surface.ml` extracts a package's public API by scanning
each `.march` file line by line and keeping the ones that match:

- `parse_fn_sig` — requires a line starting with **`pub fn `**, and reads the
  return type only when the text after `)` starts with **`->`**.
- `parse_type_decl` — requires a line starting with **`pub type `**.

March has neither construct:

- **There is no `pub` keyword.** Visibility is `fn` (public) / `pfn` (private),
  and `type` is public by default. `pub` is not a token —
  `grep -cE '"pub"|PUB\b' lib/lexer/lexer.mll` returns 0 — and
  `specs/lang/grammar/reject/r09_pub_fn_keyword_rejected.march` is a conformance
  fixture asserting the parser REJECTS `pub fn`.
- **Return types are `: T`, not `-> T`.** `fn f() -> Int do` is a parse error.

Measured over the whole repo:

| pattern | occurrences in `.march` |
|---|---|
| `pub fn ` | **1** (the reject fixture above) |
| `pub type ` | **0** |
| `fn ` in `stdlib/` alone | 2332 |

So `extract_from_directory` returns an empty surface for every real package.

## Consequence

`forge publish` (`forge/lib/cmd_publish.ml:51-66`) diffs the old and new API
surfaces and calls `check_semver_bump` to block an under-bumped release. With
both surfaces empty, `diff` yields no changes, `required_bump []` is Patch, and
the verdict is always `Ok`. **A breaking change can be published under a patch
bump and nothing objects.**

Impact is currently bounded by a second condition: `check_semver_bump` skips
enforcement entirely for `0.x` packages (`if old_v.major = 0 then Ok`). So the
gate is dead code today for pre-1.0 packages regardless — but it will silently
stay dead for the first package that reaches 1.0.0, which is precisely when it
starts mattering.

The unit tests in `forge/test/test_api_surface.ml` pass because their fixtures
are written in the same non-March syntax (`pub fn add(x: Int, y: Int) -> Int`),
so they test the parser against its own invented dialect rather than against the
language. They would keep passing after any fix unless they are rewritten too.

## Fix

Do not hand-roll a line scanner for this. `forge/lib/cmd_cap.ml` already parses
real March with `March_parser.Parser.module_` + `Token_filter`, in the same
codebase, for the same kind of whole-project walk — the API surface should be
read off the AST the same way:

1. Parse each file; walk `DFn` / `DType` / `DAlwaysLinearType`, descending into
   nested `DMod`.
2. Treat `fn` as public and `pfn` as private (there is no `pub`); take the
   return type from the AST rather than from text after `)`.
3. Rewrite `test_api_surface.ml` fixtures in real March. **Add a regression test
   that runs the extractor over an actual stdlib module and asserts the surface
   is non-empty** — the current failure mode is silence, so only a
   non-emptiness assertion catches a recurrence.

A line scanner also cannot see multi-head clauses, default arguments, or
signatures wrapped across lines; the AST walk gets those for free.
