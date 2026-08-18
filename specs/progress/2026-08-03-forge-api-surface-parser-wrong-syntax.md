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

## Fixed 2026-08-18

Rewrote `forge/lib/resolver_api_surface.ml`'s extraction layer exactly as
scoped above:

- `parse_file`/`parse_string` parse with the real
  `March_parser.Parser.module_` + `Token_filter.make March_lexer.Lexer.token`
  (same pattern as `Cmd_cap.parse_file`).
- `extract_decls`/`extract_one` walk `DFn` / `DType` / `DAlwaysLinearType`,
  descending into nested `DMod`. `fn` (`Ast.Public`) is public, `pfn`
  (`Ast.Private`) is not; `type`/`always_linear type` follow their own
  `visibility` field (`ptype` is private).
- Signatures are rendered off the AST via the existing surface-syntax
  printer in `lib/format/format.ml` (`Fmt.fmt_ty`, `Fmt.fmt_fn_param`,
  `Fmt.fmt_lin`, `Fmt.fmt_tys` — `march_format` was already a `march_forge`
  dependency), not re-invented — so `fn add(x : Int, y : Int) : Int` renders
  as `params_raw = "x : Int, y : Int"`, `return_raw = "Int"`. A multi-clause
  function's clauses are joined `"(0) | (1) | (n)"` so every head
  contributes to the diff, not just the first line a scanner would see.
- `extract_from_directory`'s file-parse errors are now reported
  (`Printf.eprintf`) instead of silently dropped, though the function still
  degrades to an empty surface for a file it can't parse rather than
  aborting the whole extraction (matches the prior signature —
  `Resolver_api_surface.extract_from_directory : string -> surface`, no
  `result` — so `forge/lib/cmd_publish.ml` needed no changes at all).
- `forge/test/test_api_surface.ml` fixtures are rewritten in real March
  (`fn`/`pfn`, `: T` returns). Added cases for multi-head clauses, a default
  argument, a signature wrapped across lines, and a nested `mod` — the exact
  shapes a line scanner can't see. Added two non-emptiness regression tests
  (the todo's required check): one runs `extract_from_string` over
  `Registry_march_src.content` — forge's own `forge/tasks/forge_registry.march`,
  embedded into `march_forge` at build time so the test has no runtime
  filesystem dependency — and asserts real names (`request`, `publish_url`,
  `friendly`, …) come back and known-private helpers don't; the other runs
  `extract_from_directory` (the function `cmd_publish.ml` actually calls)
  over a temp dir holding a real excerpt of the same file, exercising the
  file-walk + per-file-parse path too.
- Manual sanity check: `extract_from_directory "stdlib"` now returns 1999
  public fns and 179 public types with real names/signatures (previously:
  0/0, silently). End-to-end: built `forge publish --dry-run --old-source
  <old>` against a two-directory fixture that changes a public fn's arity
  under a `1.0.0 -> 1.0.1` patch bump — now correctly rejected with a
  `SEMVER VIOLATION` (exit 1) naming the changed signature and the required
  `2.0.0`; the same fixture bumped to `2.0.0` passes. Before this fix both
  directories parsed to an empty surface and the patch bump was silently
  accepted.
- `forge/lib/cmd_publish.ml` was **not** touched — its call sites
  (`extract_from_directory`, `diff`, `check_semver_bump`,
  `string_of_change_kind`, `required_bump`, `format_underBumped`,
  `Ok`/`UnderBumped`) all kept their existing names/shapes.

Verification: `dune build --root . @install` (clean) and
`dune build --root . @forge/test/runtest` (all forge suites green, incl. the
rewritten `forge-api-surface`: 25/25).
