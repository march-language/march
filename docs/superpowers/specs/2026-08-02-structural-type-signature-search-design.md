# Structural type-signature search (`forge search --type`)

Date: 2026-08-02
Status: approved

## Problem

`forge search --type "..."` already exists, but it is not a type search — it is a
substring bag-of-words matcher. [`search_type`](../../../lib/search/search.ml) splits the query on
spaces and commas, then substring-matches each fragment against the entry's
pretty-printed signature string and scores by the fraction of fragments found.

Consequences:

- **No argument order or arity awareness.** `Int -> String` and `String -> Int`
  score identically, and both match a three-argument function that happens to
  mention `Int` and `String`.
- **No type-variable normalization on one of the two printer paths.** A query
  written `List(a) -> b` misses an entry whose signature was printed as
  `List(x) -> y`.
- **Substring bleed.** A query of `Int` matches `Integer`, `Int64`, and
  `List(Int)`.

The result is a query mode that looks Hoogle-shaped but cannot answer the
question Hoogle answers: "what function has *this shape*?"

## Scope

- **Match model**: structural and order-sensitive. Arity must be equal, each
  argument position must match, and the return type must match.
- **Partial matching**: not supported. A query's arity must equal the entry's
  arity exactly. A query naming fewer arguments than the function takes does not
  match at any score. (Name and doc search remain available when arity is
  unknown.)
- **Query parsing**: the query is parsed as a March type annotation using the
  existing menhir parser, then canonicalized through the same printer that
  produced the index entries — so query and entry normalization cannot drift.
- **Scoring**: an exact structural match scores 1.0. Matching is effectively
  binary; no partial credit.
- **Index schema**: unchanged. `entry.params : (string * string) list` and
  `entry.return_type : string option` already carry per-position argument types
  and the return type. No cache-version bump is needed.

## Non-goals

- Subset/partial-arity matching (real Hoogle allows it; explicitly excluded here).
- Unification-based or subtype-aware matching (`List(Int)` will not match a
  query of `List(a)` — canonical string equality only).
- Changing `--type`'s flag name, its `search_combined` integration, or its
  JSON/plain output shape.
- Ranking beyond the binary match (the existing sort handles ordering).

## Design

### Canonicalization symmetry (a prerequisite fix)

Index entries are printed by one of two paths:

- [`make_ty_printer`](../../../lib/search/search.ml) — used when the typechecker resolved the entry's
  type. It assigns clean variable names `a`, `b`, `c`, … in order of first
  appearance, shared across one signature.
- [`pp_ast_ty`](../../../lib/search/search.ml) — the AST fallback, used when a span is absent from
  `type_map`. It prints `Ast.TyVar {txt}` **verbatim**, preserving author-written
  names like `xs` or `acc`.

This asymmetry means AST-fallback entries can never match a normalized query.
Structural matching makes the bug load-bearing, so it is fixed as part of this
work: `pp_ast_ty` gains the same first-appearance renaming, so both paths emit
identical canonical strings for the same type.

This is the one behavior change outside `search_type` itself. It also changes the
`signature` string stored for AST-fallback entries (author var names become
`a`/`b`/`c`), which is a display change users will see in results.

### Matching

`search_type` is rewritten to:

1. Parse the query string as a March type annotation. On parse failure, return a
   structured error rather than a result list.
2. Split the parsed query into `(arg_types, return_type)`.
3. Canonicalize each part through a single shared printer instance, so variable
   identity is consistent across the whole query (the same discipline
   `make_ty_printer` already applies per-signature).
4. For each index entry: match when
   - `List.length query_args = List.length entry.params`, **and**
   - each `query_args[i]` string equals the corresponding `entry.params[i]`
     type string, **and**
   - the canonical query return type equals `entry.return_type`.
5. Matching entries score 1.0.

Entries with no parameters (types, constructors) simply never match a query that
has arguments, and match a zero-argument query only if the return type matches.

### Error handling

An unparseable type query is a user error. `search_type` surfaces it (rather than
raising or silently returning `[]`), and `cmd_search.ml` reports a clear message
naming the offending query and exits non-zero — mirroring how it already handles
a corrupt index (`error: failed to parse search index: ...`).

There is deliberately no fallback to the old substring behavior: silently
degrading to a less precise mode would reintroduce the imprecision this change
exists to remove, and would make scores impossible to interpret.

### Integration

`search_combined` continues to call `search_type` and blend its score with name
and doc scores using the existing averaging logic. Because a structural match is
always 1.0, a combined query like `forge search fold --type "List(a), b, f -> b"`
ranks by the name/doc component, which is the desired behavior.

## Testing

Extend `test/test_search.ml`:

- **Order sensitivity**: a query of `Int -> String` must not match an entry of
  `String -> Int`.
- **Variable normalization**: a query of `List(a) -> b` matches an entry whose
  source type was written `List(x) -> y`.
- **Arity discrimination**: a 2-argument query must not match a 3-argument
  function, even when every query type appears among the function's types.
- **Substring non-matching**: a query of `Int` must not match `Int64`,
  `Integer`, or `List(Int)` — the specific failure mode of the old matcher.
- **AST-fallback symmetry**: an entry printed via the AST fallback path matches a
  normalized query, pinning the `pp_ast_ty` fix. Without this test the
  asymmetry can regress silently, since typechecked entries would still pass
  every other test.
- **Unparseable query**: a malformed type string produces the error path, not a
  crash and not an empty success.
- **Regression**: existing `--type` tests that assert current substring behavior
  must be reviewed — any that encode order-insensitivity or substring bleed are
  asserting the bug and should be updated to the new semantics rather than
  preserved.

## Follow-ups (out of scope)

- Subset matching with an arity-mismatch scoring rule.
- Unification-aware matching (`List(Int)` matching `List(a)`).
