# `forge search --type` — structural type-signature matching

Landed 2026-08-02.

**What shipped.** `forge search --type TYPE` no longer treats `TYPE` as a
substring to look for inside the printed signature — it parses `TYPE` as an
actual March type, canonicalizes it, and matches it structurally against each
index entry's `params`/`return_type`: exact arity, each argument type
compared positionally, and type variables canonicalized so `a -> a` and
`x -> x` denote the same query. A malformed query is now a reported CLI
error (`error: could not parse type query: "..."`, exit 1) instead of
silently degrading to "no results" — previously indistinguishable from a
correct query that legitimately matched nothing.

**Grammar addition (Task 1).** Menhir's existing `ty` nonterminal had no
standalone entry point — it was only reachable as a sub-production inside a
full module parse. Added a `ty_eof` start symbol (`lib/parser/parser.mly`)
so `Search.parse_ty_query_string` can parse a bare type expression like
`"List(a) -> a -> Bool"` in isolation, the same way the rest of the compiler
parses a full `.march` file, without constructing a throwaway module/function
wrapper around the query string.

**Canonicalization fix (Task 2).** The AST fallback pretty-printer for types
(`make_ast_ty_printer` / `pp_ast_ty` in `lib/search/search.ml`) is shared by
both index construction (canonicalizing every stdlib/dependency entry's
signature at index-build time) and query parsing (canonicalizing the
user's `--type` string through the *same* variable-renaming table) — this is
what makes `a` in the query denote the same variable as `a` in an indexed
entry regardless of what the original source called its type parameters.
Task 2 fixed a bug in this printer where it did not canonicalize consistently
in all cases, which would have made structural matches silently miss entries
whose source used different type-variable names than the query.

**Structural matcher (Task 3).** `Search.parse_type_query : string ->
(type_query, string) result` in `lib/search/search.ml`, where:

```ocaml
type type_query =
  | QFull of string list * string   (* canonical arg types, canonical return type *)
  | QReturnOnly of string           (* `-> T` form: canonical return type, any arity *)
```

`search_type` dispatches on this: `QFull (args, ret)` requires
`List.length args = List.length entry.params` and a positional canonical-type
match on every argument plus the return type; `QReturnOnly ret` matches the
return type alone, at any arity.

**Return-type-only mode is a deliberate addition beyond the original design
spec.** The original design only called for full-signature structural
matching (`Arg1 -> Arg2 -> Ret`). A leading `->` (e.g. `--type "-> Int"`) was
added as a second query form specifically so "find anything that returns an
Int/Bool/Result(...)" remains expressible without inventing wildcard-argument
syntax — a common Hoogle-style use case that pure exact-arity matching would
otherwise make unreachable except by trying every arity by hand. It is a
distinct constructor (`QReturnOnly`) rather than an empty argument list
because a genuine zero-argument query (`QFull ([], _)`) must match *only*
zero-argument entries, not entries at every arity.

**CLI wiring (Task 4).** `forge/lib/cmd_search.ml`'s `run` now validates a
non-empty `--type` query via `Search.parse_type_query` right after the index
loads (mirroring the file's existing corrupt-index-cache error convention:
`Printf.eprintf "error: %s\n%!" msg; exit 1`) and before dispatching to
`search_combined`, so a malformed query fails loudly instead of falling
through to `search_type`'s internal `Error _ -> []` and reading as a silent
zero-result search.

**Docs updated to match structural semantics.** `.claude/skills/march-lang/
SKILL.md`'s `--type` examples were written for the old substring semantics
and needed correcting, not just rewording:
- `forge search "" --type "List(a), a -> Bool"` no longer parses at all —
  March's `ty` grammar separates curried arguments with `->`, not `,`; the
  comma form was only ever meaningful as a substring pattern. Corrected to
  `forge search "" --type "List(a) -> a -> Bool"`.
- `forge search fold --type "List" --doc "accumulator"` (bare `"List"` as a
  0-argument-fn-returning-`List` query) no longer matches `Iterable.fold` /
  `List.fold_left` (both take 3 args and return a bound type variable, not a
  literal `List`). Corrected to the full structural signature
  `--type "List(a) -> b -> (b -> a -> b) -> b"`, verified to return
  `Iterable.fold` and `List.fold_left`.
- Added an explicit note that matching is exact-arity and order-sensitive,
  with `-> T` documented as the return-type-only form.
- `forge search "" --type "String -> Int"` (1-arg case) was unaffected by
  the semantics change and still returns matches (`UUID.hex_val`,
  `Toml.digits_to_int`, `String.byte_size`, etc.) — left as-is.

**Manual verification, project fixture (`/private/tmp/callers_smoke2/app`,
a two-package `forge.toml` project with a path dependency — `forge search`
only indexes stdlib + declared deps, not loose files in a bare directory):**

```
$ forge search "" --type "String -> Int" --limit 5
UUID.hex_val  UUID.hex_val(c: String) -> Int  .../stdlib/uuid.march:71
... (4 more)
$ echo $?
0

$ forge search "" --type "List( ->"
error: could not parse type query: "List( ->"
$ echo $?
1

$ forge search "" --type="-> Int" --limit 5
Yaml.collect_key_go  Yaml.collect_key_go(s: String, i: Int) -> Int  ...
... (4 more)
$ echo $?
0
```

(`--type="-> Int"` needs the `=` form or cmdliner reads the leading `-` as
its own option and errors `unknown option '->'` — a pre-existing cmdliner
argument-parsing quirk, not something this change introduced or fixed.)

**Out of scope, tracked as follow-ups, not filed as todos in this pass:**
- *Subset matching* — e.g. a query with fewer arguments than an entry
  matching a prefix of its parameter list, or ignoring extra trailing
  arguments. Deliberately not built: exact-arity matching is the
  unambiguous, predictable default, and loosening it needs its own design
  pass on how partial matches should be scored/ranked.
- *Unification-aware matching* — treating two structurally different but
  unifiable type-variable patterns (e.g. matching a query's `a -> a` against
  an entry's `a -> b` under a substitution) as equivalent, the way Hoogle's
  real type search does. The current matcher is pure canonical-string
  equality per position, not full unification; a genuine unification pass
  would let `--type "a -> a"` also surface entries whose real signature is
  more general (`a -> b`) when specialized. Left for a future iteration if
  the exact-match behavior proves too strict in practice.
