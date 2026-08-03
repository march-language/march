# Structural Type-Signature Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `forge search --type`'s substring bag-of-words matcher with real structural matching — equal arity, per-position argument types, and return type, over canonically-renamed type variables.

**Architecture:** Add a `ty_eof` start symbol to the existing menhir grammar so a type query can be parsed by March's real type parser. Fix an existing canonicalization asymmetry so both index-entry printer paths emit identical strings. Rewrite `search_type` to compare parsed+canonicalized query parts against the per-position type strings the index already stores.

**Tech Stack:** OCaml, menhir, dune, Alcotest (`test/test_search.ml`).

## Global Constraints

- Match model: structural and order-sensitive. Arity equal, each argument position equal, return type equal — all as canonical strings.
- No partial/subset arity matching. A query's arity must equal the entry's arity.
- No fallback to substring matching. An unparseable query is a reported error, never a silent degradation.
- Exact structural match scores `1.0`. Matching is binary.
- Index schema unchanged (`entry.params`, `entry.return_type` already suffice). **No cache-version bump.**
- `--type` keeps its flag name, its `search_combined` integration, and its JSON/plain output shape.
- **Return-type-only mode:** a query whose first non-space characters are `->` matches on return type alone, at any arity. This preserves the existing useful `--type "-> Int"` capability that strict parsing would otherwise reject. It is the one intentional addition to the approved spec.

---

## File Structure

- **Modify `lib/parser/parser.mly`**: add a `ty_eof` start symbol over the existing `ty` nonterminal (Task 1).
- **Modify `lib/search/search.ml`**: canonicalize `pp_ast_ty`'s type variables (Task 2); rewrite `search_type` and add a query-parse error type (Task 3).
- **Modify `forge/lib/cmd_search.ml`**: surface a query-parse error and exit non-zero (Task 4).
- **Modify `test/test_search.ml`**: update the three existing `--type` tests to the new semantics, add structural tests (Tasks 2-4).
- **Modify `CHANGELOG.md`**, add `specs/progress/` entry (Task 4).

---

## Task 1: Add a `ty_eof` start symbol to the grammar

**Files:**
- Modify: `lib/parser/parser.mly:248-251` (start symbol declarations), plus a new rule near `ty:` (`lib/parser/parser.mly:968`)

**Interfaces:**
- Produces: `March_parser.Parser.ty_eof : (Lexing.lexbuf -> token) -> Lexing.lexbuf -> March_ast.Ast.ty` — parses a standalone type annotation. Used by Task 3.

- [ ] **Step 1: Write the failing test**

Add to `test/test_search.ml` (near the other type-search tests):

```ocaml
let parse_ty_str (s : string) : March_ast.Ast.ty =
  let lexbuf = Lexing.from_string s in
  March_parser.Parser.ty_eof
    (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf

let test_parse_ty_eof_arrow () =
  match parse_ty_str "List(a) -> Int" with
  | March_ast.Ast.TyArrow (_, _) -> ()
  | _ -> Alcotest.fail "expected TyArrow for `List(a) -> Int`"
```

Register it in the existing `Alcotest.run` group list (add to the `"type search"` group if one exists, otherwise add a `"type parsing"` group following the file's existing group pattern).

- [ ] **Step 2: Run test to verify it fails**

Run: `dune build test/test_search.exe --root . 2>&1 | tail -20`
Expected: FAIL — `Unbound value "March_parser.Parser.ty_eof"`.

- [ ] **Step 3: Add the start symbol declaration**

In `lib/parser/parser.mly`, alongside the existing `%start` lines (248-251):

```
%start <March_ast.Ast.ty> ty_eof
```

- [ ] **Step 4: Add the rule**

In `lib/parser/parser.mly`, immediately before the existing `ty:` rule (line 968):

```
ty_eof:
  | t = ty EOF { t }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `dune build test/test_search.exe --root . && ./_build/default/test/test_search.exe test`
Expected: PASS. Menhir must report no new conflicts — check the build output for `Warning: N states have shift/reduce conflicts` and confirm the count did not increase versus a build of the base commit. If it did increase, stop and report: a grammar conflict is a blocker, not something to work around.

- [ ] **Step 6: Run the full suite**

Build the four alcotest drivers and run each directly and synchronously (do NOT background `scripts/run-tests.sh`):

```bash
dune build test/run_compiler.exe test/run_eval.exe test/run_codegen.exe test/run_stdlib.exe --root .
./_build/default/test/run_compiler.exe -e
./_build/default/test/run_eval.exe -e
./_build/default/test/run_codegen.exe -e
./_build/default/test/run_stdlib.exe -q
```

Expected: all passing. A grammar change touches every parse in the project, so `run_compiler` passing is the load-bearing check here.

- [ ] **Step 7: Commit**

```bash
git add lib/parser/parser.mly test/test_search.ml
git commit -m "parser: add ty_eof start symbol for standalone type annotations"
```

---

## Task 2: Canonicalize `pp_ast_ty` type variables

**Files:**
- Modify: `lib/search/search.ml:100-122` (`pp_ast_ty`)
- Modify: `test/test_search.ml`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `pp_ast_ty` emits `a`/`b`/`c`-renamed type variables in order of first appearance, matching `make_ty_printer`'s existing convention, so both printer paths produce identical canonical strings.

- [ ] **Step 1: Write the failing test**

```ocaml
let test_pp_ast_ty_canonicalizes_vars () =
  (* `xs` and `acc` must print as `a` and `b`, matching make_ty_printer. *)
  let ty = parse_ty_str "List(xs) -> acc" in
  Alcotest.(check string) "author var names normalized"
    "List(a) -> b" (Search.pp_ast_ty ty)
```

If `pp_ast_ty` is not currently exposed outside `search.ml`, expose it (there is no `.mli` for this library — verify with `ls lib/search/`; if an `.mli` exists, add the signature there).

- [ ] **Step 2: Run test to verify it fails**

Run: `dune build test/test_search.exe --root . && ./_build/default/test/test_search.exe test`
Expected: FAIL — received `List(xs) -> acc`, expected `List(a) -> b`.

- [ ] **Step 3: Implement**

Restructure `pp_ast_ty` so it takes a per-call renaming table, mirroring `make_ty_printer`'s design (a closure holding a `(string, string) Hashtbl.t` and a counter, assigning `a`, `b`, `c`, … on first sight of each distinct variable name). Keep a `pp_ast_ty : Ast.ty -> string` wrapper that creates a fresh table per call, so existing single-type call sites are unchanged.

Important: one signature must share a single table across its parts. Check every existing `pp_ast_ty` call site (`grep -n "pp_ast_ty" lib/search/search.ml`) — where several types belong to the same signature (e.g. `extract_fn_params`'s params plus its return type, around `search.ml:220` and `search.ml:288`), they must share one table, or `a` in an argument and `a` in the return type will denote different variables.

- [ ] **Step 4: Run test to verify it passes**

Run: `dune build test/test_search.exe --root . && ./_build/default/test/test_search.exe test`
Expected: PASS.

- [ ] **Step 5: Run the full suite**

Same four-binary invocation as Task 1 Step 6.
Expected: all passing. Note that this change alters the `signature` string stored for AST-fallback entries — if any existing test asserts an author-written variable name in a signature, it is asserting the old asymmetry and should be updated to the canonical name.

- [ ] **Step 6: Commit**

```bash
git add lib/search/search.ml test/test_search.ml
git commit -m "search: canonicalize type variables in the AST fallback printer"
```

---

## Task 3: Rewrite `search_type` with structural matching

**Files:**
- Modify: `lib/search/search.ml:515-536` (`search_type`)
- Modify: `test/test_search.ml`

**Interfaces:**
- Consumes: `March_parser.Parser.ty_eof` (Task 1), canonical `pp_ast_ty` (Task 2).
- Produces: `Search.search_type : index -> string -> (entry * float) list` (unchanged signature, new semantics), plus:

```ocaml
type type_query =
  | QFull of string list * string   (** canonical arg types, canonical return type *)
  | QReturnOnly of string           (** `-> T` form: canonical return type, any arity *)

val parse_type_query : string -> (type_query, string) result
```

Task 4 consumes the `Error` case.

- [ ] **Step 1: Write the failing tests**

```ocaml
let test_type_search_order_sensitive () =
  let idx = sample_index () in
  (* An entry of `String -> Int` must NOT match a query of `Int -> String`. *)
  let results = Search.search_type idx "Int -> String" in
  let names = List.map (fun (e, _) -> e.Search.name) results in
  Alcotest.(check bool) "length (String -> Int) not matched by reversed query"
    false (List.mem "length" names)

let test_type_search_arity_discriminates () =
  let idx = sample_index () in
  (* A 1-arg query must not match a 2-arg entry, even if the types appear. *)
  let results = Search.search_type idx "String -> Int" in
  List.iter (fun (e, _) ->
      Alcotest.(check int) ("arity 1 for " ^ e.Search.name)
        1 (List.length e.Search.params))
    results

let test_type_search_no_substring_bleed () =
  let idx = sample_index () in
  (* `Int` must not match `Int64` / `Integer` / `List(Int)`. *)
  let results = Search.search_type idx "Int -> Int" in
  List.iter (fun (e, _) ->
      Alcotest.(check bool) ("exact param type for " ^ e.Search.name)
        true (List.for_all (fun (_, t) -> t = "Int") e.Search.params))
    results

let test_type_search_unparseable_is_error () =
  match Search.parse_type_query "List( ->" with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "expected a parse error for a malformed type query"

let test_type_search_zero_arg_not_return_only () =
  (* A zero-argument query is QFull ([], _), NOT QReturnOnly — it must match
     only zero-argument entries, unlike the `-> T` form. *)
  match Search.parse_type_query "Int" with
  | Ok (Search.QFull ([], _)) -> ()
  | Ok (Search.QReturnOnly _) ->
    Alcotest.fail "bare `Int` must not be treated as a return-only query"
  | Ok _ -> Alcotest.fail "expected QFull ([], _) for a bare type"
  | Error m -> Alcotest.fail ("unexpected parse error: " ^ m)

let test_type_search_return_only_mode () =
  let idx = sample_index () in
  (* Leading `->` = return-type-only query, matches at any arity. *)
  let results = Search.search_type idx "-> Int" in
  let names = List.map (fun (e, _) -> e.Search.name) results in
  Alcotest.(check bool) "length (-> Int) found" true (List.mem "length" names)
```

Update `sample_index ()` if it lacks entries with the shapes these tests need (a `String -> Int` single-arg entry, and at least one multi-arg entry) — read its current contents first and add entries rather than rewriting existing ones, so other tests keep passing.

Also update the two existing substring-semantics tests: `test_type_search_return_type` is superseded by `test_type_search_return_only_mode` (delete the old one), and `test_type_search_param_type` (query `"String"`) now asserts substring behavior that no longer exists — rewrite it as a full structural query (e.g. `"String -> List(String)"`) matching the entry it was checking for, or delete it if `test_type_search_no_substring_bleed` already covers the intent. `test_type_search_empty_query` (empty query returns 0) stays as-is.

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune build test/test_search.exe --root . && ./_build/default/test/test_search.exe test`
Expected: FAIL — `Search.parse_type_query` unbound, and the order/arity/bleed tests failing against the substring matcher.

- [ ] **Step 3: Implement `parse_type_query`**

```ocaml
type type_query =
  | QFull of string list * string   (** canonical arg types, canonical return type *)
  | QReturnOnly of string           (** `-> T` form: canonical return type, any arity *)

(** Parse a type query, canonicalizing every part through one shared
    variable-renaming table so `a` denotes the same variable everywhere in the
    query.

    A query beginning with `->` is a return-type-only query, matched at any
    arity. This is a distinct constructor rather than an empty argument list,
    because a zero-argument query also has no arguments and must NOT match at
    any arity. *)
let parse_type_query (q : string) : (type_query, string) result =
  ...
```

Implementation notes:
- Detect the return-type-only form by trimming leading whitespace and testing for a `->` prefix; parse the remainder as a type and return `Ok (QReturnOnly canonical_return)`.
- Otherwise parse the whole query with `Parser.ty_eof` over `Token_filter.make Lexer.token` (mirroring `parse_file`'s lexbuf setup at `search.ml:307`), then flatten the resulting `Ast.TyArrow` spine into `(args, return)`. Note the grammar is right-associative (`ty: t = ty_nat_add ARROW u = ty`), so a curried `A -> B -> C` flattens to `args=[A;B]`, `return=C`.
- Catch parser/lexer exceptions and return `Error` with a message naming the query.
- Canonicalize every part through one shared renaming table (the Task 2 mechanism).

- [ ] **Step 4: Implement structural `search_type`**

Replace the body of `search_type`:
- Empty query → `[]` (preserves existing behavior, keeps `test_type_search_empty_query` passing).
- `parse_type_query` returning `Error _` → `[]` here (the CLI reports the error separately in Task 4; `search_type`'s list-returning signature is relied on by `search_combined` and must not change).
- Return-type-only mode → match entries whose `return_type` equals the canonical query return type, any arity, score `1.0`.
- Full mode → match when `List.length args = List.length entry.params`, each `args[i]` equals the corresponding `entry.params[i]` type string, and the canonical return type equals `entry.return_type`. Score `1.0`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `dune build test/test_search.exe --root . && ./_build/default/test/test_search.exe test`
Expected: PASS for all new tests and the retained/updated existing ones.

- [ ] **Step 6: Run the full suite**

Same four-binary invocation as Task 1 Step 6. Expected: all passing.

- [ ] **Step 7: Commit**

```bash
git add lib/search/search.ml test/test_search.ml
git commit -m "search: structural type-signature matching for --type"
```

---

## Task 4: CLI error surfacing, docs, changelog

**Files:**
- Modify: `forge/lib/cmd_search.ml` (the `run` function's type-query handling)
- Modify: `CHANGELOG.md`
- Create: `specs/progress/2026-08-02-structural-type-signature-search.md`
- Modify: `.claude/skills/march-lang/SKILL.md` (the type-search examples)

**Interfaces:**
- Consumes: `Search.parse_type_query` (Task 3).

- [ ] **Step 1: Surface a parse error in the CLI**

In `forge/lib/cmd_search.ml`'s `run`, before dispatching a type query, validate it:

```ocaml
    (match type_q with
     | Some q ->
       (match Search.parse_type_query q with
        | Error msg ->
          Printf.eprintf "error: %s\n%!" msg;
          exit 1
        | Ok _ -> ())
     | None -> ());
```

Place it after the index is loaded and before `search_combined` is called, matching the file's existing `Printf.eprintf "error: %s\n%!" msg; exit 1` convention for a corrupt index.

- [ ] **Step 2: Verify manually**

```bash
dune build forge/bin/main.exe --root .
```

Then, from a directory with a `forge.toml`, confirm all three behaviors and paste the output into the report:
- A valid structural query returns results.
- `--type "List( ->"` prints `error: ...` and exits non-zero (check `echo $?`).
- `--type "-> Int"` still returns return-type matches.

- [ ] **Step 3: Update the march-lang skill's type-search examples**

`.claude/skills/march-lang/SKILL.md` documents `--type` with examples that assume substring semantics (`forge search "" --type "String -> Int"`, `forge search "" --type "List(a), a -> Bool"`). Verify each documented example still returns what the doc implies under structural matching; fix any that no longer do, and add a line noting that matching is exact-arity and order-sensitive, with `-> T` as the return-type-only form.

- [ ] **Step 4: Add the CHANGELOG entry**

Under `## [Unreleased]` → `### Changed`:

```
- `forge search --type` now performs structural type matching (exact arity, per-position argument types, canonical type variables) instead of substring matching. A leading `->` queries by return type alone. Malformed type queries are now reported as errors rather than silently returning loose matches.
```

- [ ] **Step 5: Add the progress entry**

Create `specs/progress/2026-08-02-structural-type-signature-search.md` following the conventions in `specs/progress/README.md` (read it first). Cover: what changed, the `ty_eof` grammar addition, the `pp_ast_ty` canonicalization fix, the return-type-only mode as a deliberate addition beyond the original spec, and the out-of-scope follow-ups (subset matching, unification-aware matching).

- [ ] **Step 6: Run the full suite**

Same four-binary invocation as Task 1 Step 6, plus `dune build forge/test/test_forge.exe --root . && ./_build/default/forge/test/test_forge.exe`.
Expected: all passing.

- [ ] **Step 7: Run doc lint**

```bash
scripts/check-docs.sh
```
Expected: `doc-lint passed`.

- [ ] **Step 8: Commit**

```bash
git add forge/lib/cmd_search.ml CHANGELOG.md specs/progress/2026-08-02-structural-type-signature-search.md .claude/skills/march-lang/SKILL.md
git commit -m "forge: report malformed type queries; document structural --type"
```
