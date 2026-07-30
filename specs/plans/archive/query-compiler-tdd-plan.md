# Query-Based / Demand-Driven Compiler Architecture for March — TDD Implementation Plan

**Status:** Design proposal
**Priority:** P4 (Long-Term / Research), deferred post-v1
**Related:** `specs/todos.md` P4 item; `specs/design.md` §"Query-based/demand-driven compiler architecture"

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Core Abstractions](#2-core-abstractions)
3. [Query Catalog](#3-query-catalog)
4. [TDD Phases](#4-tdd-phases)
5. [Test Infrastructure](#5-test-infrastructure)
6. [Migration Strategy](#6-migration-strategy)
7. [OCaml Implementation Patterns](#7-ocaml-implementation-patterns)
8. [Risks and Mitigations](#8-risks-and-mitigations)
9. [Success Criteria](#9-success-criteria)

---

## 1. Architecture Overview

### What Is a Query-Based Compiler?

A query-based (demand-driven) compiler replaces a linear "pipeline of passes" with a **database of memoized computations** where each result is computed on demand and cached until its inputs change. The authoritative references are:

- **`rustc` + Salsa** ([github.com/salsa-rs/salsa](https://github.com/salsa-rs/salsa)) — rustc migrated to query-based architecture around 2017–2019. Each compilation step (parsing, name resolution, type checking, MIR construction, codegen) is a query. The key insight: queries form a DAG; when a source file changes, only the queries that transitively depend on that file are re-run. The rest are served from cache.
- **Roslyn (C#/VB)** — Microsoft's second-generation compiler as a platform. Every "green node" in the syntax tree is immutable; a change produces a new tree that shares structure with the old one. Higher-level analyses layer on top via lazy computation.
- **GHC's planned "GHC-as-a-library" / Shake-based build** — GHC has moved toward modularity using `Rules` (the Shake build system abstraction). The `ghcide` / HLS project builds an IDE layer using a demand-driven analysis loop that re-runs type checking only for the changed module and its dependents.

The key properties all three share:

1. **Inputs are versioned.** Every input (source file contents, environment variables, CLI flags) carries a "revision" or "generation" counter.
2. **Derived results are memoized.** Once computed, `parse("foo.march")` returns the same AST until `source_text("foo.march")` changes.
3. **Dependency tracking is automatic.** When query A calls query B, the framework records "A depends on B". If B's inputs change, A is automatically invalidated.
4. **Fine-grained invalidation.** A function's type doesn't change because we edited a comment in the same file — only the string that feeds the relevant parse needs to be re-processed.

### Why March Needs It

March's current pipeline is linear (`parse → desugar → typecheck → eval/TIR → ...`). This is simple and correct but has costs:

1. **Full recompilation on any change.** Edit a doc comment → re-parse, re-desugar, re-typecheck, re-lower everything. For a project with a large stdlib (the current stdlib already has ~4894 lines across 22 modules), this adds up fast.

2. **REPL incremental evaluation is hard-coded.** `lib/jit/repl_jit.ml` hand-implements the "only re-compile new functions" logic via the `compiled_fns` hashtable and `partition_fns` / `mark_compiled_fns`. This works but is bespoke and fragile (the `compiled_fns` corruption bug fixed in 2026-03 is a symptom). A query-based compiler gives this for free.

3. **LSP server re-runs the full pipeline per keystroke.** The current LSP server (`march-lsp`) likely runs a full parse+typecheck on every document change. A query-based architecture would re-parse only the changed range, re-typecheck only the changed module and its dependents, and serve hover/goto-def from cached typed ASTs.

4. **CAS already content-addresses definitions.** `lib/cas/` computes BLAKE3 hashes of TIR definitions and caches compiled artifacts. Query-based architecture extends this idea upward through the entire pipeline — not just at the TIR/codegen boundary but all the way from source text to tokens to AST to types to TIR.

5. **Sig hashes are designed for incremental compilation.** `specs/design.md` notes that `sig Name do ... end` blocks get their own hash separate from the impl hash, so downstream code depends on the sig hash — internal refactors don't invalidate downstream caches. This is exactly the "input/derived" boundary that a query system needs.

### How It Differs From the Current Linear Pipeline

| Property | Current Pipeline | Query-Based |
|----------|-----------------|-------------|
| Execution order | Fixed: parse → desugar → typecheck → TIR → … | Demand-driven: compute what is asked, pull in dependencies |
| Re-computation on change | All passes re-run from the changed file | Only queries transitively depending on changed input |
| Memoization | Only at TIR/CAS boundary | Every query result memoized |
| Granularity | Per-module/file | Per-function, per-expression, configurable |
| REPL incremental | Hand-coded in `repl_jit.ml` | Automatic consequence of memoization |
| LSP re-analysis | Full pipeline per change | Re-run only invalidated queries |
| Parallel compilation | None | Queries with no shared dependencies can run in parallel |

---

## 2. Core Abstractions

### 2.1 Two Kinds of Queries

**Input queries** represent external inputs that the compiler cannot compute — they are set by the driver and invalidated when the outside world changes:
- Source file text
- Compiler flags
- Environment variables
- File modification times

**Derived queries** compute results from other queries:
- `tokens_of_file(path)` ← reads `source_text(path)`
- `ast_of_file(path)` ← reads `tokens_of_file(path)`
- `type_of_expr(span)` ← reads `typed_module(file)`, which reads `ast_of_file`
- `llvm_ir_of_fn(fn_name)` ← reads `tir_of_fn(fn_name)`, which reads `type_of_module`

The framework guarantees: if all inputs transitively reachable from a derived query are unchanged (same value), the cached result is returned without re-running the query function.

### 2.2 The Database

The database is a mutable store that holds:
1. **Input table**: `query_key → (revision, value)` — the latest revision at which this input was set, and its current value.
2. **Derived cache**: `query_key → (computed_at_revision, dependencies, value)` — the revision at which the result was last computed, the set of query keys it depended on, and the cached value.
3. **Current revision**: a global monotonic counter. Bumped every time any input changes.

Pseudocode:
```
type revision = int

type 'a entry =
  | Input   { rev: revision; value: 'a }
  | Derived { computed_rev: revision; deps: key list; value: 'a }

type db = {
  mutable current_rev: revision;
  tables: (key, entry) Hashtbl.t;
}
```

### 2.3 Dependency Tracking

When a derived query runs, it pushes itself onto a "currently executing" stack and records every query it reads. After it finishes, those reads become its dependency set.

```
let query_stack: key Stack.t = Stack.create ()

let read db key =
  (* Record this as a dependency of the currently executing query *)
  (match Stack.top_opt query_stack with
   | Some parent -> record_dep db parent key
   | None -> ());
  get_or_compute db key
```

This is the core insight from Salsa. No manual wiring of dependencies — they fall out automatically from ordinary function calls.

### 2.4 Salsa-Style Revision Counting

Invalidation uses revision numbers, not dirty bits:
- Global revision counter starts at 0.
- Each time an input changes, global revision is incremented and the input's revision is updated.
- A derived query is valid if: `computed_rev >= max(dep.revision for dep in dependencies)`.
- On re-execution, after computing the new value: if `new_value = old_value` (structurally equal), the query's revision is NOT bumped. This is the **early-return optimization** — if a function's signature didn't change even though its body did, queries depending only on the signature are not invalidated.

### 2.5 OCaml Mapping

OCaml has no proc macros, so we cannot derive `#[query]` attributes like Salsa does in Rust. The equivalent OCaml pattern:

**Option A: Explicit query registration with functors.**
Each query is a module that implements a `Query` signature:
```ocaml
module type QUERY = sig
  type input
  type output
  val name : string
  val compute : db -> input -> output
end
```

**Option B: First-class query values with GADTs.**
```ocaml
type 'a query =
  | SourceText   : string -> string query
  | TokensOf     : string -> token list query
  | AstOf        : string -> Ast.module_ query
  | TypedModule  : string -> typed_module query
  | TirOf        : string -> tir_module query
  | LlvmIrOf     : string -> string query
```

**Option C: Effect handlers for dependency tracking (OCaml 5 native).**
Using effects to intercept every `query_read` call and record it automatically:
```ocaml
effect Read : 'a query -> 'a

let with_tracking f =
  match f () with
  | result -> (result, [])
  | effect (Read q) k ->
    let deps = ref [] in
    let v = get_or_compute q in
    deps := q_key q :: !deps;
    continue k v
```

**Recommendation for March: Option B (GADTs) + Option C (effects for auto-tracking).**
- GADTs give type-safe query dispatch.
- OCaml 5 effects give automatic dependency tracking without instrumenting every call site.
- Functors give composability and testability.

The key data structure will be an `(int, Obj.t) Hashtbl.t` (or a typed heterogeneous map built with first-class modules) keyed by a hash of the query name + serialized input.

---

## 3. Query Catalog

Each query is specified as: **Name** · **Signature** · **Replaces** · **Dependencies** · **Granularity** · **Test case**.

---

### Q1: `source_text`

**Signature:** `source_text : path -> string`
**Type:** Input query
**Replaces:** `read_file` in `bin/main.ml` (lines 164–170)
**Dependencies:** None (external input)
**Granularity:** Per file

**Description:** Returns the raw source text of a file. Setting this is how the driver notifies the compiler that a file has changed. In batch mode, set once per file. In LSP mode, updated on every `textDocument/didChange` notification.

**Test case:**
```ocaml
(* test: source_text returns file contents *)
let db = Db.create () in
Db.set_input db (Q.source_text "hello.march") "fn main() do println(\"hi\") end\n";
assert (Db.query db (Q.source_text "hello.march") = "fn main() do println(\"hi\") end\n")

(* test: changing source_text bumps global revision *)
let rev0 = Db.current_revision db in
Db.set_input db (Q.source_text "hello.march") "fn main() do println(\"bye\") end\n";
assert (Db.current_revision db > rev0)
```

---

### Q2: `tokens_of`

**Signature:** `tokens_of : path -> (token * span) list`
**Type:** Derived query
**Replaces:** `March_lexer.Lexer.token` called inline in `compile`
**Dependencies:** `source_text(path)`
**Granularity:** Per file

**Description:** Lexes the source text into a token stream with spans. Cached — re-runs only when `source_text` changes.

**Test case:**
```ocaml
(* test: tokens_of parses identifiers *)
Db.set_input db (Q.source_text "t.march") "let x = 42";
let toks = Db.query db (Q.tokens_of "t.march") in
assert (List.mem (Token.Let, span_of "let") toks);
assert (List.mem (Token.Int 42, span_of "42") toks)

(* test: tokens_of is cached after first call *)
let _ = Db.query db (Q.tokens_of "t.march") in
let stats0 = Db.query_stats db (Q.tokens_of "t.march") in
let _ = Db.query db (Q.tokens_of "t.march") in
let stats1 = Db.query_stats db (Q.tokens_of "t.march") in
assert (stats1.cache_hits = stats0.cache_hits + 1)

(* test: tokens_of re-runs after source change *)
Db.set_input db (Q.source_text "t.march") "let y = 99";
let toks2 = Db.query db (Q.tokens_of "t.march") in
assert (List.mem (Token.Int 99, _) toks2);
assert (not (List.mem (Token.Int 42, _) toks2))
```

---

### Q3: `parsed_module`

**Signature:** `parsed_module : path -> Ast.module_ result`
**Type:** Derived query
**Replaces:** `March_parser.Parser.module_` in `compile` (lines 275–286 of `bin/main.ml`)
**Dependencies:** `tokens_of(path)` (or equivalently `source_text(path)` — can depend directly on source if we re-lex inside the parser query)
**Granularity:** Per file

**Description:** Parses the token stream into a raw AST. Returns `Ok ast` or `Err diagnostics`. Carries recovery errors from `Parse_errors` module.

**Test case:**
```ocaml
(* test: parsed_module returns Ok for valid input *)
Db.set_input db (Q.source_text "f.march") "fn add(a, b) do a + b end\n";
(match Db.query db (Q.parsed_module "f.march") with
 | Ok m -> assert (List.length m.Ast.mod_decls = 1)
 | Err _ -> failwith "unexpected parse error")

(* test: parsed_module returns parse errors for invalid input *)
Db.set_input db (Q.source_text "bad.march") "fn (do end\n";
(match Db.query db (Q.parsed_module "bad.march") with
 | Ok _ -> failwith "should have failed"
 | Err diags -> assert (List.length diags > 0))

(* test: parse result is stable across two reads (no global state mutation) *)
Db.set_input db (Q.source_text "s.march") "type Color = Red | Green | Blue\n";
let r1 = Db.query db (Q.parsed_module "s.march") in
let r2 = Db.query db (Q.parsed_module "s.march") in
assert (r1 == r2)  (* physical equality — same cached object *)
```

---

### Q4: `desugared_module`

**Signature:** `desugared_module : path -> Ast.module_ result`
**Type:** Derived query
**Replaces:** `March_desugar.Desugar.desugar_module` in `compile` (line 299)
**Dependencies:** `parsed_module(path)`
**Granularity:** Per file

**Description:** Runs the desugar pass (multi-head fn → single EMatch, pipe desugar, string interp expansion) over the parsed module.

**Test case:**
```ocaml
(* test: multi-head fn desugars to single EMatch *)
Db.set_input db (Q.source_text "fib.march") {|
  fn fib(0) do 0 end
  fn fib(1) do 1 end
  fn fib(n) do fib(n-1) + fib(n-2) end
|};
(match Db.query db (Q.desugared_module "fib.march") with
 | Ok m ->
   (* Should be a single DFn with one clause containing an EMatch *)
   let fn_decls = List.filter is_fn m.mod_decls in
   assert (List.length fn_decls = 1);
   let fib = List.hd fn_decls in
   assert (has_single_clause_with_ematch fib)
 | Err _ -> failwith "desugar failed")

(* test: pipe |> desugars to function application *)
Db.set_input db (Q.source_text "pipe.march") "fn f(x) do x |> add(1) end\n";
(match Db.query db (Q.desugared_module "pipe.march") with
 | Ok m -> assert (contains_eapp_not_epipe m)
 | Err _ -> failwith "desugar failed")
```

---

### Q5: `stdlib_decls`

**Signature:** `stdlib_decls : unit -> Ast.decl list`
**Type:** Derived query (with `stdlib_path` as input)
**Replaces:** `load_stdlib ()` in `compile` (line 301)
**Dependencies:** `source_text` for each stdlib file, `desugared_module` for each
**Granularity:** Per stdlib file (individual files can change independently)

**Description:** Returns the desugared declarations for the entire stdlib, in load order. Cached — the stdlib doesn't change during normal compilation so this is computed once and reused. In development, changing a stdlib file invalidates only the affected module and its dependents.

**Test case:**
```ocaml
(* test: stdlib_decls includes List module *)
let decls = Db.query db (Q.stdlib_decls ()) in
let list_mod = List.find_opt (function
  | Ast.DMod (n, _, _, _) -> n = "List"
  | _ -> false) decls in
assert (Option.is_some list_mod)

(* test: stdlib_decls are cached (second call is free) *)
let _  = Db.query db (Q.stdlib_decls ()) in
let s0 = (Db.query_stats db (Q.stdlib_decls ())).compute_count in
let _  = Db.query db (Q.stdlib_decls ()) in
let s1 = (Db.query_stats db (Q.stdlib_decls ())).compute_count in
assert (s1 = s0)  (* no re-computation *)
```

---

### Q6: `name_resolution`

**Signature:** `name_resolution : path -> name_map result`
**Type:** Derived query
**Replaces:** Parts of `check_module` that handle `DUse`, `DAlias`, module scope building
**Dependencies:** `desugared_module(path)`, `desugared_module` of all imported modules
**Granularity:** Per module

**Description:** Builds the name-resolution map: what does each identifier in this module refer to? Handles `use A.B.*`, `alias Long as Short`, qualified names. Separates from type inference so LSP can do rename/goto-def without running full type checking.

**Note:** This is a new query that doesn't have a direct 1:1 counterpart in the current code — name resolution is currently interleaved with type checking in `typecheck.ml`. Extracting it is the key architectural win that enables LSP features without full typechecking.

**Test case:**
```ocaml
(* test: use import resolves names *)
Db.set_input db (Q.source_text "u.march") {|
  use List.*
  fn main() do map(fn x -> x + 1, [1, 2, 3]) end
|};
let nm = Db.query db (Q.name_resolution "u.march") |> unwrap in
assert (NameMap.lookup nm "map" = Some "List.map")

(* test: alias resolves names *)
Db.set_input db (Q.source_text "al.march") {|
  alias List as L
  fn main() do L.map(fn x -> x, []) end
|};
let nm = Db.query db (Q.name_resolution "al.march") |> unwrap in
assert (NameMap.lookup nm "L" = Some "List")
```

---

### Q7: `module_graph`

**Signature:** `module_graph : string list -> dep_graph`
**Type:** Derived query
**Replaces:** `March_cas.Scc.compute_sccs` (but at module level, not TIR function level)
**Dependencies:** `desugared_module` for each path
**Granularity:** Whole project

**Description:** Builds the module dependency graph (which modules import which). Used to determine compilation order and for incremental invalidation. Returns topological order + SCC groups for mutually recursive modules.

**Test case:**
```ocaml
(* test: module_graph detects import order *)
(* Given: A imports B, B has no imports *)
Db.set_input db (Q.source_text "a.march") "use B.*\nfn f() do g() end";
Db.set_input db (Q.source_text "b.march") "fn g() do 42 end";
let g = Db.query db (Q.module_graph ["a.march"; "b.march"]) in
assert (DepGraph.order g = ["b.march"; "a.march"])

(* test: module_graph detects mutual recursion as SCC *)
(* A calls B, B calls A → same SCC *)
Db.set_input db (Q.source_text "x.march") "use Y.*\nfn fx() do fy() end";
Db.set_input db (Q.source_text "y.march") "use X.*\nfn fy() do fx() end";
let g = Db.query db (Q.module_graph ["x.march"; "y.march"]) in
assert (DepGraph.is_scc g ["x.march"; "y.march"])
```

---

### Q8: `typed_module`

**Signature:** `typed_module : path -> (Ast.module_ * type_map) result`
**Type:** Derived query — the most important one
**Replaces:** `March_typecheck.Typecheck.check_module` (lines 311 of `bin/main.ml`)
**Dependencies:** `desugared_module(path)`, `stdlib_decls()`, `typed_module` for imported modules (their signature hashes, not full typed modules)
**Granularity:** Per module

**Description:** Runs bidirectional HM type inference over the desugared module. Returns the typed module plus the `type_map` mapping spans to types. This is the big query — the one where most incremental wins come from.

The key insight for granularity: typed_module could be further split into:
- `typed_module_signatures`: the public interface of the module (function types, type aliases, exported names). Downstream modules only depend on this.
- `typed_module_bodies`: full body type checking. Only needed for codegen or error reporting.

This corresponds to the existing `sig` hash / impl hash split in `specs/design.md`.

**Test case:**
```ocaml
(* test: typed_module infers type of simple function *)
Db.set_input db (Q.source_text "t.march") "fn add(a : Int, b : Int) : Int do a + b end\n";
(match Db.query db (Q.typed_module "t.march") with
 | Ok (_, type_map) ->
   (* Find the span of `a + b` and check it has type Int *)
   let expr_span = find_span_of_expr "a + b" in
   assert (TypeMap.lookup type_map expr_span = Some (TCon ("Int", [])))
 | Err diags -> failwith (show_diags diags))

(* test: changing a function body does NOT invalidate downstream module's sig query *)
(* Setup: module A exports `fn f : Int -> Int`; module B imports f *)
Db.set_input db (Q.source_text "a.march") "pub fn f(x : Int) : Int do x + 1 end\n";
Db.set_input db (Q.source_text "b.march") "use A.*\nfn g(x : Int) do f(x) end\n";
let _  = Db.query db (Q.typed_module "b.march") in
let s0 = (Db.query_stats db (Q.typed_module "b.march")).compute_count in
(* Change A's body but NOT its signature *)
Db.set_input db (Q.source_text "a.march") "pub fn f(x : Int) : Int do x + 2 end\n";
let _  = Db.query db (Q.typed_module "b.march") in
let s1 = (Db.query_stats db (Q.typed_module "b.march")).compute_count in
assert (s1 = s0)  (* B was NOT re-checked because A's sig hash didn't change *)

(* test: linear type error is reported *)
Db.set_input db (Q.source_text "lin.march") {|
  fn bad(x : linear Int) do
    let _ = x
    let _ = x  -- use linear value twice
    ()
  end
|};
(match Db.query db (Q.typed_module "lin.march") with
 | Err diags ->
   assert (List.exists (fun d -> String.is_substring "linear" d.message) diags)
 | Ok _ -> failwith "should have reported linearity error")
```

---

### Q9: `type_at_position`

**Signature:** `type_at_position : (path * line * col) -> ty option`
**Type:** Derived query
**Replaces:** LSP hover handler in `march-lsp`
**Dependencies:** `typed_module(path)`
**Granularity:** Per position

**Description:** Given a file + position, returns the type of the expression at that position by looking up the span in `type_map`. This is what powers LSP hover.

**Test case:**
```ocaml
(* test: type_at_position finds Int literal type *)
Db.set_input db (Q.source_text "pos.march") "fn main() do\n  let x = 42\n  x\nend\n";
let ty = Db.query db (Q.type_at_position ("pos.march", 2, 11)) in
assert (ty = Some (TCon ("Int", [])))

(* test: type_at_position returns None for whitespace *)
let ty = Db.query db (Q.type_at_position ("pos.march", 1, 0)) in
assert (ty = None)
```

---

### Q10: `definitions_at`

**Signature:** `definitions_at : (path * line * col) -> (path * span) list`
**Type:** Derived query
**Replaces:** LSP goto-definition handler
**Dependencies:** `name_resolution(path)`, `typed_module(path)`
**Granularity:** Per position

**Test case:**
```ocaml
(* test: definitions_at resolves to definition site of a function *)
Db.set_input db (Q.source_text "def.march") "fn f() do 1 end\nfn g() do f() end\n";
let defs = Db.query db (Q.definitions_at ("def.march", 2, 12)) in
(* cursor on `f` in `f()` on line 2 should resolve to line 1 *)
assert (List.exists (fun (_, sp) -> sp.start_line = 1) defs)
```

---

### Q11: `references_to`

**Signature:** `references_to : (path * span) -> (path * span) list`
**Type:** Derived query
**Replaces:** LSP find-references handler
**Dependencies:** `name_resolution` for all files in project
**Granularity:** Per definition site

---

### Q12: `tir_of_module`

**Signature:** `tir_of_module : path -> Tir.tir_module result`
**Type:** Derived query
**Replaces:** `March_tir.Lower.lower_module` in `compile` (line 345)
**Dependencies:** `typed_module(path)`
**Granularity:** Per module

**Description:** Lowers the typed AST to TIR (ANF form). The `type_map` from `typed_module` is threaded through as it is today in `lower_module ~type_map`.

**Test case:**
```ocaml
(* test: tir_of_module produces ANF for function application *)
Db.set_input db (Q.source_text "anf.march") "fn f(x : Int) do x + 1 end\n";
(match Db.query db (Q.tir_of_module "anf.march") with
 | Ok tir ->
   (* ANF: every subexpression is named; no nested applications *)
   assert (all_fns_in_anf tir)
 | Err _ -> failwith "lowering failed")
```

---

### Q13: `monomorphized_module`

**Signature:** `monomorphized_module : path -> Tir.tir_module result`
**Type:** Derived query
**Replaces:** `March_tir.Mono.monomorphize` (line 346)
**Dependencies:** `tir_of_module(path)`, `tir_of_module` for all transitively imported modules (for monomorphization seeds)
**Granularity:** Per module (but note: mono is whole-program today — see Phase 5 for the granularity challenge)

**Test case:**
```ocaml
(* test: monomorphization specializes polymorphic map to Int → Int *)
Db.set_input db (Q.source_text "mono.march") {|
  fn id(x) do x end
  fn main() do id(42) end
|};
(match Db.query db (Q.monomorphized_module "mono.march") with
 | Ok tir ->
   (* id_Int should exist; generic id should be removed *)
   assert (List.exists (fun f -> f.fn_name = "id_Int") tir.tm_fns);
   assert (not (List.exists (fun f -> f.fn_name = "id") tir.tm_fns))
 | Err _ -> failwith "mono failed")
```

---

### Q14: `defunctionalized_module`

**Signature:** `defunctionalized_module : path -> Tir.tir_module result`
**Type:** Derived query
**Replaces:** `March_tir.Defun.defunctionalize` (line 347)
**Dependencies:** `monomorphized_module(path)`
**Granularity:** Per module

**Test case:**
```ocaml
(* test: defunctionalization removes TFn types *)
Db.set_input db (Q.source_text "hof.march") {|
  fn apply(f, x) do f(x) end
  fn main() do apply(fn x -> x + 1, 5) end
|};
(match Db.query db (Q.defunctionalized_module "hof.march") with
 | Ok tir ->
   (* No TFn in the output — all functions are either direct calls or tagged union dispatch *)
   assert (not (contains_tfn tir))
 | Err _ -> failwith "defun failed")
```

---

### Q15: `perceus_module`

**Signature:** `perceus_module : path -> Tir.tir_module result`
**Type:** Derived query
**Replaces:** `March_tir.Perceus.perceus` (line 348)
**Dependencies:** `defunctionalized_module(path)`
**Granularity:** Per module

**Test case:**
```ocaml
(* test: Perceus inserts RC decrements for dead values *)
Db.set_input db (Q.source_text "rc.march") "fn f(xs : List(Int)) do 42 end\n";
(match Db.query db (Q.perceus_module "rc.march") with
 | Ok tir ->
   (* xs is dropped at function entry — should have a decref *)
   let f = find_fn tir "f" in
   assert (contains_rc_drop f)
 | Err _ -> failwith "perceus failed")
```

---

### Q16: `optimized_module`

**Signature:** `optimized_module : path -> Tir.tir_module result`
**Type:** Derived query
**Replaces:** `March_tir.Opt.run` (line 350)
**Dependencies:** `perceus_module(path)`, escape analysis as sub-query
**Granularity:** Per module

**Sub-queries (derived from optimized_module):**
- `escape_analyzed_module`: runs `March_tir.Escape.escape_analysis`
- `inlined_module`: runs `March_tir.Inline`
- `dce_module`: dead code elimination

---

### Q17: `llvm_ir_of_module`

**Signature:** `llvm_ir_of_module : path -> string result`
**Type:** Derived query
**Replaces:** `March_tir.Llvm_emit.emit_module` (line 379)
**Dependencies:** `optimized_module(path)`
**Granularity:** Per module (could go finer: per function)

**Test case:**
```ocaml
(* test: llvm_ir_of_module emits define for main *)
Db.set_input db (Q.source_text "main.march") "fn main() do println(42) end\n";
(match Db.query db (Q.llvm_ir_of_module "main.march") with
 | Ok ir ->
   assert (String.is_substring "define" ir);
   assert (String.is_substring "main" ir)
 | Err _ -> failwith "emit failed")
```

---

### Q18: `compiled_artifact`

**Signature:** `compiled_artifact : path -> artifact_path result`
**Type:** Derived query
**Replaces:** The `clang` invocation + CAS cache check in `compile` (lines 367–413 of `bin/main.ml`)
**Dependencies:** `llvm_ir_of_module(path)`, `compiled_artifact` for runtime
**Granularity:** Per module

**Description:** This query integrates directly with the existing CAS layer (`lib/cas/`). The CAS `compilation_hash` becomes the query cache key. A hit in the CAS means this query returns immediately without running clang. The query framework's memoization and the CAS layer become unified.

**Test case:**
```ocaml
(* test: compiled_artifact is cached by CAS on second call *)
Db.set_input db (Q.source_text "c.march") "fn main() do 0 end\n";
let _path1 = Db.query db (Q.compiled_artifact "c.march") |> unwrap in
(* Mutate body but not signature — CAS key should match *)
Db.set_input db (Q.source_text "c.march") "fn main() do 1 end\n";
let path2 = Db.query db (Q.compiled_artifact "c.march") |> unwrap in
(* Different output, but if sig hash is same, the CAS may or may not cache — depends on granularity *)
assert (Sys.file_exists path2)
```

---

### Q19: `sig_hash_of_module`

**Signature:** `sig_hash_of_module : path -> string`
**Type:** Derived query
**Replaces:** Conceptually: the `hd_sig_hash` computed in `lib/cas/hash.ml`
**Dependencies:** `typed_module_signatures(path)`
**Granularity:** Per module

**Description:** Returns the BLAKE3 hash of the module's public interface (exported types, function signatures). Used as the dependency key that downstream modules track. If `sig_hash_of_module "a.march"` returns the same value as before, modules importing `a.march` do NOT need re-typechecking even if `a.march`'s implementation changed.

This is the query that encodes the existing `sig Name do ... end` hash design.

---

### Q20: `completion_items`

**Signature:** `completion_items : (path * line * col) -> completion list`
**Type:** Derived query
**Replaces:** LSP completion handler
**Dependencies:** `name_resolution(path)`, `typed_module(path)` (for type-directed completion)

---

### Q21: `inlay_hints`

**Signature:** `inlay_hints : (path * range) -> hint list`
**Type:** Derived query
**Replaces:** LSP inlay hints handler
**Dependencies:** `typed_module(path)`

---

### Q22: `diagnostics`

**Signature:** `diagnostics : path -> diagnostic list`
**Type:** Derived query
**Replaces:** The diagnostic collection/rendering in `compile`
**Dependencies:** `parsed_module(path)`, `typed_module(path)`

**Description:** Collects all diagnostics for a file. The LSP server subscribes to this query for each open document and sends `textDocument/publishDiagnostics` when it changes.

---

### Query Dependency Graph (Summary)

```
source_text(path) ──────────────────────────────────────────────┐
        │                                                        │
   tokens_of(path) ──► parsed_module(path) ──► desugared_module(path)
                                                      │
              stdlib_decls() ◄────────────────────────┤
                                                      │
                                          name_resolution(path)
                                                      │
                                           typed_module(path)
                                          /     │      \
                              type_at_pos  definitions  sig_hash
                                                │
                                        tir_of_module(path)
                                                │
                                    monomorphized_module(path)
                                                │
                                    defunctionalized_module(path)
                                                │
                                     perceus_module(path)
                                                │
                                    escape_analyzed_module(path)
                                                │
                                     optimized_module(path)
                                                │
                                    llvm_ir_of_module(path)
                                                │
                                    compiled_artifact(path)
```

---

## 4. TDD Phases

Each phase follows Red → Green → Refactor. Migration notes explain how to run the old and new pipelines in parallel.

---

### Phase 1: Foundation — Query Database, Memoization, Invalidation

**Estimated complexity:** Medium (2–3 weeks)
**Goal:** A working query database that can store, retrieve, and invalidate typed values.

#### Queries introduced
- `source_text` (input query)
- Generic database operations: `set_input`, `query`, `current_revision`, `query_stats`

#### Red phase — write these tests first

```ocaml
(* test/test_query_db.ml *)

(* 1. Input query round-trip *)
let test_input_roundtrip () =
  let db = Db.create () in
  Db.set_input db (Q.source_text "a.march") "hello";
  Alcotest.(check string) "source text" "hello"
    (Db.query db (Q.source_text "a.march"))

(* 2. Setting input bumps revision *)
let test_revision_bumps () =
  let db = Db.create () in
  let r0 = Db.current_revision db in
  Db.set_input db (Q.source_text "a.march") "x";
  let r1 = Db.current_revision db in
  Alcotest.(check bool) "revision increased" true (r1 > r0)

(* 3. Derived query caching *)
let test_derived_caching () =
  let db = Db.create () in
  let call_count = ref 0 in
  let q_double = Q.derived "double" (fun db () ->
    incr call_count;
    let s = Db.query db (Q.source_text "a.march") in
    String.length s * 2
  ) in
  Db.set_input db (Q.source_text "a.march") "hello";
  let v1 = Db.query db q_double in
  let v2 = Db.query db q_double in
  Alcotest.(check int) "same value" v1 v2;
  Alcotest.(check int) "only computed once" 1 !call_count

(* 4. Derived query invalidation *)
let test_invalidation () =
  let db = Db.create () in
  let call_count = ref 0 in
  let q_len = Q.derived "len" (fun db () ->
    incr call_count;
    String.length (Db.query db (Q.source_text "a.march"))
  ) in
  Db.set_input db (Q.source_text "a.march") "hi";
  let v1 = Db.query db q_len in
  Db.set_input db (Q.source_text "a.march") "hello";
  let v2 = Db.query db q_len in
  Alcotest.(check int) "recomputed" 2 !call_count;
  Alcotest.(check int) "correct new value" 5 v2;
  ignore v1

(* 5. Early-return optimization: if recomputed value is equal, don't propagate *)
let test_early_return () =
  let db = Db.create () in
  let downstream_calls = ref 0 in
  let q_length_mod_2 = Q.derived "len_mod_2" (fun db () ->
    (String.length (Db.query db (Q.source_text "a.march"))) mod 2
  ) in
  let q_downstream = Q.derived "downstream" (fun db () ->
    incr downstream_calls;
    Db.query db q_length_mod_2 + 100
  ) in
  Db.set_input db (Q.source_text "a.march") "hi";    (* len=2, mod2=0 *)
  let _ = Db.query db q_downstream in
  Db.set_input db (Q.source_text "a.march") "ok";    (* len=2, mod2=0 — same! *)
  let _ = Db.query db q_downstream in
  Alcotest.(check int) "downstream not recomputed" 1 !downstream_calls

(* 6. Dependency cycles → error (not stack overflow) *)
let test_cycle_detection () =
  let db = Db.create () in
  let q_a = Q.derived "a" (fun db () -> Db.query db (Q.by_name "b") + 1) in
  let q_b = Q.derived "b" (fun db () -> Db.query db (Q.by_name "a") + 1) in
  Q.register db q_a; Q.register db q_b;
  try
    let _ = Db.query db q_a in
    Alcotest.fail "should detect cycle"
  with Db.Cycle_error _ -> ()
```

#### Green phase
Implement `lib/query/db.ml`:
- `type t` — the database record
- `type 'a query_key` — typed query key (use GADTs or first-class modules)
- `set_input : t -> 'a query -> 'a -> unit`
- `query : t -> 'a query -> 'a`
- `current_revision : t -> int`
- `query_stats : t -> 'a query -> { compute_count: int; cache_hits: int }`

Start with the simplest possible implementation: a pair of hashtables, one for inputs and one for derived results. No effects-based dependency tracking yet — use explicit `depends_on` calls.

#### Refactor phase
Once tests pass, switch from explicit `depends_on` to effect-based auto-tracking using OCaml 5 effects. All tests should still pass; no test changes needed.

#### Migration
Phase 1 is pure infrastructure — no migration needed. The old pipeline continues to run unmodified. New tests are additive.

---

### Phase 2: Lexing + Parsing Queries

**Estimated complexity:** Low (3–5 days)
**Goal:** `source_text`, `tokens_of`, `parsed_module`, `desugared_module` queries working.

#### Queries introduced
- `source_text`
- `tokens_of`
- `parsed_module`
- `desugared_module`

#### Red phase

```ocaml
(* test/test_query_parse.ml *)

let make_db () =
  let db = Db.create () in
  Query_register.register_parse_queries db;
  db

(* Q2: tokens_of *)
let test_tokens_of_basic () =
  let db = make_db () in
  Db.set_input db (Q.source_text "t.march") "let x = 42\n";
  let toks = Db.query db (Q.tokens_of "t.march") in
  assert (token_contains toks Token.Let);
  assert (token_contains toks (Token.Ident "x"));
  assert (token_contains toks (Token.Int 42))

let test_tokens_of_cached () =
  let db = make_db () in
  Db.set_input db (Q.source_text "t.march") "let x = 1\n";
  ignore (Db.query db (Q.tokens_of "t.march"));
  let s0 = Db.query_stats db (Q.tokens_of "t.march") in
  ignore (Db.query db (Q.tokens_of "t.march"));
  let s1 = Db.query_stats db (Q.tokens_of "t.march") in
  Alcotest.(check int) "cached" (s0.compute_count) s1.compute_count

let test_tokens_of_invalidated () =
  let db = make_db () in
  Db.set_input db (Q.source_text "t.march") "let x = 1\n";
  ignore (Db.query db (Q.tokens_of "t.march"));
  Db.set_input db (Q.source_text "t.march") "let y = 2\n";
  let toks = Db.query db (Q.tokens_of "t.march") in
  assert (token_contains toks (Token.Ident "y"))

(* Q3: parsed_module *)
let test_parse_fn_decl () =
  let db = make_db () in
  Db.set_input db (Q.source_text "f.march") "fn add(a, b) do a + b end\n";
  match Db.query db (Q.parsed_module "f.march") with
  | Ok m ->
    Alcotest.(check int) "one decl" 1 (List.length m.Ast.mod_decls)
  | Err diags -> Alcotest.failf "parse error: %s" (show_diags diags)

let test_parse_error_recovery () =
  let db = make_db () in
  Db.set_input db (Q.source_text "bad.march") "fn (broken end\n";
  match Db.query db (Q.parsed_module "bad.march") with
  | Err diags -> Alcotest.(check bool) "has errors" true (diags <> [])
  | Ok _ -> Alcotest.fail "should fail"

(* Q4: desugared_module *)
let test_desugar_multihead () =
  let db = make_db () in
  Db.set_input db (Q.source_text "fib.march") {|
fn fib(0) do 0 end
fn fib(1) do 1 end
fn fib(n) do fib(n-1) + fib(n-2) end
|};
  match Db.query db (Q.desugared_module "fib.march") with
  | Ok m ->
    let fn_decls = List.filter is_dfn m.Ast.mod_decls in
    Alcotest.(check int) "single fn" 1 (List.length fn_decls)
  | Err _ -> Alcotest.fail "desugar failed"
```

#### Green phase
Create `lib/query/parse_queries.ml`:
```ocaml
let register_parse_queries db =
  Query.register db (Q.tokens_of_impl (fun db path ->
    let src = Db.query db (Q.source_text path) in
    lex_string ~filename:path src));
  Query.register db (Q.parsed_module_impl (fun db path ->
    let src = Db.query db (Q.source_text path) in
    parse_string ~filename:path src));
  Query.register db (Q.desugared_module_impl (fun db path ->
    match Db.query db (Q.parsed_module path) with
    | Error e -> Error e
    | Ok m -> Ok (Desugar.desugar_module m)))
```

The key: these are thin wrappers around the existing `March_lexer`, `March_parser`, `March_desugar` modules. No changes to those modules. The query layer is purely additive.

#### Migration
The driver (`bin/main.ml`) still calls the old pipeline. Add a `--use-query-db` flag that routes through the new query-based path for parsing. Both paths should produce identical output (verified by snapshot tests).

---

### Phase 3: Name Resolution + Module Graph Queries

**Estimated complexity:** High (1–2 weeks)
**Goal:** `name_resolution` and `module_graph` queries. This requires extracting name-resolution logic from `typecheck.ml`.

#### Queries introduced
- `name_resolution`
- `module_graph`
- `stdlib_decls`

#### Red phase

```ocaml
(* test/test_query_names.ml *)

let test_use_import () =
  let db = make_db () in
  Db.set_input db (Q.source_text "u.march") "use List.*\nfn f() do map(fn x -> x, []) end\n";
  let nm = Db.query db (Q.name_resolution "u.march") |> Result.get_ok in
  Alcotest.(check (option string)) "map resolves"
    (Some "List.map") (NameMap.lookup nm "map")

let test_alias_resolution () =
  let db = make_db () in
  Db.set_input db (Q.source_text "al.march") "alias List as L\nfn f() do L.map end\n";
  let nm = Db.query db (Q.name_resolution "al.march") |> Result.get_ok in
  Alcotest.(check (option string)) "L resolves to List"
    (Some "List") (NameMap.lookup nm "L")

let test_module_graph_order () =
  let db = make_db () in
  Db.set_input db (Q.source_text "b.march") "fn g() do 1 end\n";
  Db.set_input db (Q.source_text "a.march") "use B\nfn f() do B.g() end\n";
  let g = Db.query db (Q.module_graph ["a.march"; "b.march"]) in
  let order = DepGraph.topo_order g in
  let b_idx = List.index_of "b.march" order in
  let a_idx = List.index_of "a.march" order in
  Alcotest.(check bool) "b before a" true (b_idx < a_idx)
```

#### Green phase
Extract `check_use_decls` and `check_alias_decls` logic from `typecheck.ml` into a new `lib/names/name_resolution.ml`. Wire it as a query. The typecheck pass can still call the name resolver directly (as a function call) while the query layer wraps it.

**Critical:** Keep the existing typecheck.ml intact and passing all tests. The name resolution extraction is strictly additive — typecheck.ml can call `Name_resolution.resolve_module` directly.

#### Migration
Once `name_resolution` query works, the LSP server can use it for goto-def and rename without running full type checking. This is a pure win — new capability, old path unchanged.

---

### Phase 4: Type Inference Queries — The Big One

**Estimated complexity:** Very high (3–6 weeks)
**Goal:** `typed_module`, `sig_hash_of_module`, `type_at_position` queries. The sig/impl hash split for incremental cross-module checking.

#### Queries introduced
- `typed_module`
- `typed_module_signatures` (public interface only)
- `sig_hash_of_module`
- `type_at_position`
- `diagnostics` (type errors as a query)

#### Red phase

The key incremental correctness test — this is the one that makes the whole architecture worth it:

```ocaml
(* test/test_query_typecheck.ml *)

(* THE CRITICAL INCREMENTAL TEST *)
(* If A's body changes but signature doesn't, B should NOT be re-typechecked *)
let test_sig_stability () =
  let db = make_db () in
  (* Module A: exports fn f : Int -> Int *)
  Db.set_input db (Q.source_text "a.march")
    "pub fn f(x : Int) : Int do x + 1 end\n";
  (* Module B: imports and uses f *)
  Db.set_input db (Q.source_text "b.march")
    "use A.*\npub fn g(x : Int) : Int do f(x) * 2 end\n";

  (* First pass: typecheck both *)
  let _ = Db.query db (Q.typed_module "b.march") in
  let b_checks_0 = (Db.query_stats db (Q.typed_module "b.march")).compute_count in

  (* Change A's implementation — body only, not the signature *)
  Db.set_input db (Q.source_text "a.march")
    "pub fn f(x : Int) : Int do x + 42 end\n";

  (* A's sig_hash should be the same *)
  let sig0 = Db.query db (Q.sig_hash_of_module "a.march") in
  Db.set_input db (Q.source_text "a.march")
    "pub fn f(x : Int) : Int do x + 999 end\n";
  let sig1 = Db.query db (Q.sig_hash_of_module "a.march") in
  Alcotest.(check string) "sig unchanged" sig0 sig1;

  (* B should NOT be re-typechecked (sig_hash unchanged → B's input unchanged) *)
  let _ = Db.query db (Q.typed_module "b.march") in
  let b_checks_1 = (Db.query_stats db (Q.typed_module "b.march")).compute_count in
  Alcotest.(check int) "B not re-typechecked" b_checks_0 b_checks_1

(* Changing A's signature SHOULD re-typecheck B *)
let test_sig_change_propagates () =
  let db = make_db () in
  Db.set_input db (Q.source_text "a.march")
    "pub fn f(x : Int) : Int do x + 1 end\n";
  Db.set_input db (Q.source_text "b.march")
    "use A.*\npub fn g(x : Int) : Int do f(x) end\n";

  let _ = Db.query db (Q.typed_module "b.march") in
  let b_checks_0 = (Db.query_stats db (Q.typed_module "b.march")).compute_count in

  (* Change A's signature: f now takes String *)
  Db.set_input db (Q.source_text "a.march")
    "pub fn f(x : String) : Int do String.length(x) end\n";

  (* B must be re-typechecked and should now have a type error *)
  let _ = Db.query db (Q.typed_module "b.march") in
  let b_checks_1 = (Db.query_stats db (Q.typed_module "b.march")).compute_count in
  Alcotest.(check bool) "B re-typechecked" true (b_checks_1 > b_checks_0)

(* Type at position *)
let test_type_at_position () =
  let db = make_db () in
  Db.set_input db (Q.source_text "pos.march")
    "fn main() do\n  let x : Int = 42\n  x\nend\n";
  let ty = Db.query db (Q.type_at_position ("pos.march", 2, 18)) in
  (* Line 2, col 18 is the `42` literal — should have type Int *)
  Alcotest.(check (option string)) "Int" (Some "Int")
    (Option.map pp_ty ty)
```

#### Green phase
This is the most complex phase. Strategy:

1. Factor `check_module` in `typecheck.ml` into:
   - `compute_signatures : env -> decl list -> signature_map` — only looks at type annotations and return types, does not do full body checking
   - `check_bodies : env -> signature_map -> decl list -> (diagnostic list * type_map)` — full inference

2. `typed_module_signatures` query calls `compute_signatures`.
3. `sig_hash_of_module` query computes BLAKE3 of the serialized signature map.
4. `typed_module` query:
   a. Queries `sig_hash_of_module` for each imported module.
   b. If all sig hashes are unchanged from last run, return cached `typed_module`.
   c. Otherwise, re-run `check_bodies`.

The existing `check_module` becomes a composition: `compute_signatures` then `check_bodies`. All current tests continue to pass.

#### Refactor phase
Once the sig/impl split works, look for opportunities to make `typed_module` per-definition granular. For very large modules, this would enable checking only the changed function's body.

#### Migration
Add `--typecheck-query` flag. The `march-lsp` server switches to query-based typechecking first (biggest payoff) while the batch compiler continues using the old path.

---

### Phase 5: TIR Lowering Queries

**Estimated complexity:** Medium (1–2 weeks)
**Goal:** `tir_of_module`, `monomorphized_module` queries.

#### Queries introduced
- `tir_of_module`
- `monomorphized_module`
- `defunctionalized_module`

#### The Monomorphization Challenge

The current `March_tir.Mono.monomorphize` is whole-program: it starts from `main`, follows all call edges, and specializes polymorphic functions. This is fundamentally a whole-program pass. For a query-based architecture, there are two options:

**Option A: Keep whole-program mono as a single query.** `monomorphized_module` takes the set of all modules as input. This works and is correct; it doesn't get per-module incrementality for mono, but that's fine — mono needs to know all instantiations.

**Option B: Per-SCC mono.** Hash each SCC's monomorphization inputs (the set of type-specialized calls). If an SCC's callers haven't changed their instantiation patterns, the SCC's mono output is unchanged.

**Recommendation: Option A for now (simpler), Option B post-v1.**

#### Red phase

```ocaml
(* test/test_query_tir.ml *)

let test_tir_is_anf () =
  let db = make_db () in
  Db.set_input db (Q.source_text "anf.march") "fn f(x : Int) do x + 1 end\n";
  match Db.query db (Q.tir_of_module "anf.march") with
  | Ok tir ->
    List.iter (fun fn -> assert_is_anf fn) tir.tm_fns
  | Err _ -> Alcotest.fail "lowering failed"

let test_mono_specializes () =
  let db = make_db () in
  Db.set_input db (Q.source_text "poly.march") {|
fn id(x) do x end
fn main() do
  let a = id(42)
  let b = id("hello")
  (a, b)
end
|};
  match Db.query db (Q.monomorphized_module "poly.march") with
  | Ok tir ->
    assert (has_fn tir "id_Int");
    assert (has_fn tir "id_String");
    assert (not (has_fn tir "id"))  (* generic version removed *)
  | Err _ -> Alcotest.fail "mono failed"

let test_tir_cached_after_parse_fix () =
  (* Change a comment in source → tokens change → parsed_module recomputes →
     BUT if AST is structurally identical, TIR should NOT recompute *)
  let db = make_db () in
  Db.set_input db (Q.source_text "cmt.march") "-- hello\nfn f() do 1 end\n";
  let _ = Db.query db (Q.tir_of_module "cmt.march") in
  let s0 = (Db.query_stats db (Q.tir_of_module "cmt.march")).compute_count in
  (* Change only the comment *)
  Db.set_input db (Q.source_text "cmt.march") "-- world\nfn f() do 1 end\n";
  let _ = Db.query db (Q.tir_of_module "cmt.march") in
  let s1 = (Db.query_stats db (Q.tir_of_module "cmt.march")).compute_count in
  (* AST is structurally the same → early-return optimization → TIR not recomputed *)
  Alcotest.(check int) "TIR not recomputed for comment change" s0 s1
```

The last test is the early-return optimization in action: if `parsed_module` returns the same AST value (via structural equality), `tir_of_module` gets a cache hit without re-running.

#### Migration
Once `tir_of_module` query passes tests, the `--compile` path in `bin/main.ml` can optionally route through it with `--use-query-tir`. Keep old path as default.

---

### Phase 6: Optimization Queries

**Estimated complexity:** Low–Medium (1 week)
**Goal:** Wrap the existing optimization passes as queries.

#### Queries introduced
- `escape_analyzed_module`
- `perceus_module`
- `inlined_module`
- `dce_module`
- `optimized_module` (fixed-point composition of the above)

These are straightforward wrappers. The interesting new test is:

```ocaml
(* test: perceus result cached across unchanged IR change *)
let test_perceus_cache () =
  let db = make_db () in
  Db.set_input db (Q.source_text "p.march") "fn f(xs : List(Int)) do 42 end\n";
  let _ = Db.query db (Q.perceus_module "p.march") in
  let s0 = (Db.query_stats db (Q.perceus_module "p.march")).compute_count in
  (* Change source in a way that doesn't affect the TIR for f *)
  Db.set_input db (Q.source_text "p.march") "-- comment\nfn f(xs : List(Int)) do 42 end\n";
  let _ = Db.query db (Q.perceus_module "p.march") in
  let s1 = (Db.query_stats db (Q.perceus_module "p.march")).compute_count in
  Alcotest.(check int) "perceus not rerun" s0 s1
```

---

### Phase 7: Codegen Queries

**Estimated complexity:** Low (3–5 days)
**Goal:** `llvm_ir_of_module` and `compiled_artifact` queries. The CAS integration.

#### Queries introduced
- `llvm_ir_of_module`
- `compiled_artifact`
- `cas_lookup` / `cas_store` (primitive queries wrapping `lib/cas/`)

#### CAS Integration

The existing `lib/cas/cas.ml` becomes the storage layer for `compiled_artifact`. The query's cache key is exactly `Cas.compilation_hash`. This unifies two separate caching mechanisms (the query database's derived cache and the CAS) into one:

```ocaml
let compiled_artifact_impl db path =
  match Db.query db (Q.llvm_ir_of_module path) with
  | Error e -> Error e
  | Ok ir ->
    let cas = Db.query db (Q.cas_store ()) in
    let ir_hash = Blake3.hash_string ir in
    let flags = Db.query db (Q.compiler_flags ()) in
    let ch = Cas.compilation_hash ir_hash ~target:"native" ~flags in
    match Cas.lookup_artifact cas ch with
    | Some path -> Ok path
    | None ->
      let path = compile_via_clang ir in
      Cas.store_artifact cas ch path;
      Ok path
```

This means: a CAS hit for a given IR hash bypasses clang entirely, just as today. But now it's expressed as a query — the query framework handles invalidation automatically.

#### Red phase

```ocaml
let test_llvm_emits_define () =
  let db = make_db () in
  Db.set_input db (Q.source_text "emit.march") "fn main() do 42 end\n";
  match Db.query db (Q.llvm_ir_of_module "emit.march") with
  | Ok ir ->
    Alcotest.(check bool) "has define" true
      (String.is_substring "define" ir)
  | Err _ -> Alcotest.fail "emit failed"

let test_cas_cache_hit_skips_clang () =
  let db = make_db () in
  let clang_calls = ref 0 in
  Db.set_option db `clang_invoke_counter clang_calls;
  Db.set_input db (Q.source_text "c.march") "fn main() do 0 end\n";
  let _ = Db.query db (Q.compiled_artifact "c.march") in
  let c0 = !clang_calls in
  (* Second call should be a CAS hit — no clang *)
  let _ = Db.query db (Q.compiled_artifact "c.march") in
  let c1 = !clang_calls in
  Alcotest.(check int) "clang not called twice" c0 c1
```

---

### Phase 8: REPL Integration

**Estimated complexity:** Medium (1–2 weeks)
**Goal:** The REPL incremental evaluation becomes a consequence of the query system rather than hand-coded logic in `repl_jit.ml`.

#### Queries introduced
- `repl_session_state` (input query: the accumulated REPL declarations)
- `repl_module_for_expr` (derived query: constructs a module for a given expression given the current session)
- `repl_compiled_fragment` (derived query: replaces `partition_fns` / `compile_fragment` logic)

#### Current REPL JIT architecture

`lib/jit/repl_jit.ml` maintains:
- `ctx.compiled_fns`: which functions are already compiled into loaded .so files
- `partition_fns`: classifies new vs. already-compiled functions
- `mark_compiled_fns`: records success

This is query-based thinking implemented manually. The migration:
- `repl_session_state` replaces the accumulated `env` and `type_map` state
- `compiled_fns` hashtable becomes the query database's derived cache
- `partition_fns` logic becomes: "query `repl_compiled_fragment` for each expression; the query system knows which functions are new because their query keys don't exist in the cache yet"

**Key correctness property** (the bug that was fixed in 2026-03, now expressed as a test):

```ocaml
(* test: failed compilation does NOT corrupt the compiled set *)
let test_repl_failed_compile_no_corruption () =
  let db = make_repl_db () in
  Db.set_input db (Q.repl_session "s") (ReSession.empty);

  (* Eval a valid expression first *)
  let s1 = ReSession.add_expr (ReSession.empty) "let x = 42" in
  Db.set_input db (Q.repl_session "s") s1;
  let _ok = Db.query db (Q.repl_fragment "s") |> Result.get_ok in

  (* Now try an invalid expression *)
  let s2 = ReSession.add_expr s1 "let y = @@@invalid@@@" in
  Db.set_input db (Q.repl_session "s") s2;
  (match Db.query db (Q.repl_fragment "s") with
   | Error _ -> ()  (* expected *)
   | Ok _ -> Alcotest.fail "should fail");

  (* Now try a valid expression — x should still be accessible *)
  let s3 = ReSession.add_expr s1 "x + 1" in
  Db.set_input db (Q.repl_session "s") s3;
  match Db.query db (Q.repl_fragment "s") with
  | Ok result -> Alcotest.(check int) "x still accessible" 43 result
  | Error e -> Alcotest.failf "x corrupted: %s" e
```

This test precisely captures the 2026-03 bug: after a failed compilation, the next valid expression must still see all previously compiled functions. The query system provides this automatically because the failed compilation never updates any cached entry.

---

### Phase 9: LSP Integration

**Estimated complexity:** Medium (1–2 weeks)
**Goal:** `march-lsp` switches to query-based analysis for all handlers.

#### Queries introduced
- `type_at_position` (Q9 above — now fully implemented)
- `definitions_at` (Q10)
- `references_to` (Q11)
- `completion_items` (Q20)
- `inlay_hints` (Q21)
- `diagnostics` (Q22)
- `signature_help_at`
- `code_actions_at`

#### The LSP event loop

```ocaml
(* Current: re-run full pipeline on every change *)
let handle_did_change uri text =
  let diags = run_full_pipeline text in
  publish_diagnostics uri diags

(* Query-based: only invalidate what changed *)
let handle_did_change uri text =
  Db.set_input db (Q.source_text (uri_to_path uri)) text;
  (* diagnostics query is now stale; it will be recomputed lazily
     when the LSP server next requests it *)
  let diags = Db.query db (Q.diagnostics (uri_to_path uri)) in
  publish_diagnostics uri diags
```

The full pipeline (parse → desugar → typecheck) is re-run only if `source_text` changed. If the user's cursor moved without changing the file, `hover` requests are served from the cached `typed_module`.

#### Red phase

```ocaml
(* test: diagnostics query updates after file change *)
let test_diagnostics_reactive () =
  let db = make_lsp_db () in
  Db.set_input db (Q.source_text "l.march") "fn f(x : Int) do x + \"oops\" end\n";
  let diags0 = Db.query db (Q.diagnostics "l.march") in
  Alcotest.(check bool) "has type error" true (diags0 <> []);

  (* Fix the error *)
  Db.set_input db (Q.source_text "l.march") "fn f(x : Int) do x + 1 end\n";
  let diags1 = Db.query db (Q.diagnostics "l.march") in
  Alcotest.(check (list unit)) "no errors" [] (List.map (fun _ -> ()) diags1)

(* test: hover is cached between keystrokes on unchanged file *)
let test_hover_cached () =
  let db = make_lsp_db () in
  Db.set_input db (Q.source_text "h.march") "fn main() do\n  let x : Int = 42\n  x\nend\n";
  let h0 = Db.query db (Q.type_at_position ("h.march", 2, 18)) in
  let s0 = (Db.query_stats db (Q.type_at_position ("h.march", 2, 18))).compute_count in
  let h1 = Db.query db (Q.type_at_position ("h.march", 2, 18)) in
  let s1 = (Db.query_stats db (Q.type_at_position ("h.march", 2, 18))).compute_count in
  Alcotest.(check int) "hover cached" s0 s1;
  assert (h0 = h1)
```

---

### Phase 10: CAS Integration (Unified Caching)

**Estimated complexity:** Medium (1–2 weeks)
**Goal:** The query database's persistent cache is backed by the CAS. Query results are content-addressed.

#### The Big Unification

Today there are two separate caching layers:
1. Query database (in-memory, per-session)
2. CAS (on-disk, persistent across sessions)

Phase 10 unifies them: the query database is backed by the CAS for derived queries whose results are serializable. After a build, the query database is serialized to the CAS. Next build starts by loading the CAS into the database — most queries are pre-warmed.

The key insight: a query result is valid across sessions if and only if its input hashes are the same. This is exactly what the CAS already tracks.

```ocaml
(* Query database serialization format *)
type persistent_entry = {
  pe_query_hash : string;   (* hash of (query_name, serialized_input) *)
  pe_dep_hashes : string list;  (* hashes of each dependency's persistent_entry *)
  pe_value_hash : string;   (* hash of the serialized result value *)
  pe_value_path : string;   (* CAS path to the serialized result *)
}
```

**Test:**
```ocaml
(* test: warm start loads typed_module from CAS — no re-parsing *)
let test_warm_start () =
  (* Session 1: full build *)
  let db1 = make_db () in
  Db.set_input db1 (Q.source_text "ws.march") "fn main() do 42 end\n";
  let _ = Db.query db1 (Q.typed_module "ws.march") in
  Db.persist_to_cas db1;

  (* Session 2: start fresh, load from CAS *)
  let db2 = Db.create () in
  Db.load_from_cas db2;
  Db.set_input db2 (Q.source_text "ws.march") "fn main() do 42 end\n";  (* same text *)
  let s0 = (Db.query_stats db2 (Q.typed_module "ws.march")).compute_count in
  let _ = Db.query db2 (Q.typed_module "ws.march") in
  let s1 = (Db.query_stats db2 (Q.typed_module "ws.march")).compute_count in
  Alcotest.(check int) "no re-typecheck after warm start" s0 s1
```

---

## 5. Test Infrastructure

### 5.1 Test Harness Setup

New test suite: `test/test_query.ml` (will start as one file, split by phase).

```ocaml
(* test/test_query.ml structure *)
let () = Alcotest.run "march query" [
  "db",          Test_query_db.tests;       (* Phase 1 *)
  "parse",       Test_query_parse.tests;    (* Phase 2 *)
  "names",       Test_query_names.tests;    (* Phase 3 *)
  "typecheck",   Test_query_typecheck.tests; (* Phase 4 *)
  "tir",         Test_query_tir.tests;      (* Phase 5 *)
  "opt",         Test_query_opt.tests;      (* Phase 6 *)
  "codegen",     Test_query_codegen.tests;  (* Phase 7 *)
  "repl",        Test_query_repl.tests;     (* Phase 8 *)
  "lsp",         Test_query_lsp.tests;      (* Phase 9 *)
  "cas",         Test_query_cas.tests;      (* Phase 10 *)
]
```

### 5.2 Property-Based Testing for Query Determinism

Every derived query must be deterministic: calling it twice with the same inputs returns equal values. This is a QCheck2 property:

```ocaml
(* QCheck2 property: all queries are deterministic *)
let prop_query_deterministic (query_name : string) (input_text : string) =
  let db = make_test_db () in
  Db.set_input db (Q.source_text "test.march") input_text;
  let q = Query_registry.find_by_name query_name in
  let v1 = Db.query db q in
  let v2 = Db.query db q in
  v1 = v2

(* For all queries in the catalog, this should hold *)
let () = QCheck2.(Test.make ~count:100
  Gen.(pair (oneofl Query_registry.all_names) (small_string ~gen:printable))
  (fun (qname, src) -> prop_query_deterministic qname src))
```

### 5.3 Snapshot Testing for Query Results

Key query outputs (AST shape, type maps, TIR structures) are snapshot-tested:

```ocaml
(* Snapshot: desugared_module for multi-head fib *)
let test_fib_desugar_snapshot () =
  let db = make_db () in
  Db.set_input db (Q.source_text "fib.march") test_fib_source;
  let m = Db.query db (Q.desugared_module "fib.march") |> Result.get_ok in
  Snapshot.assert_matches "desugar_fib" (Ast.show_module m)
```

Snapshots live in `test/snapshots/query/`. Update with `MARCH_UPDATE_SNAPSHOTS=1 dune runtest`.

### 5.4 Incremental Correctness Tests

These tests verify that after an edit, only the expected queries re-run:

```ocaml
type query_execution_log = {
  mutable executed: (string * string) list;  (* (query_name, input_key) pairs *)
}

let with_execution_log db f =
  let log = { executed = [] } in
  Db.set_execution_hook db (fun qname key ->
    log.executed <- (qname, key) :: log.executed);
  let result = f () in
  (result, List.rev log.executed)

(* Test: editing a comment only re-runs parse, nothing else *)
let test_comment_edit_minimal_recompute () =
  let db = make_db () in
  Db.set_input db (Q.source_text "c.march") "fn f() do 1 end\n";
  let _ = Db.query db (Q.typed_module "c.march") in  (* prime the cache *)

  let (_, executed) = with_execution_log db (fun () ->
    Db.set_input db (Q.source_text "c.march") "-- comment\nfn f() do 1 end\n";
    Db.query db (Q.typed_module "c.march")
  ) in
  (* tokens_of and parsed_module re-run, but typed_module should NOT
     (because AST is structurally equal → early-return) *)
  assert (List.mem ("tokens_of", "c.march") executed);
  assert (List.mem ("parsed_module", "c.march") executed);
  assert (not (List.mem ("typed_module", "c.march") executed))
```

### 5.5 Performance Regression Tests

```ocaml
(* Benchmark: incremental re-typecheck of stdlib after changing one file *)
let bench_incremental_stdlib () =
  let db = make_db () in
  setup_all_stdlib db;
  let _ = Db.query db (Q.typed_module "user.march") in  (* warm cache *)

  let t0 = Unix.gettimeofday () in
  (* Simulate editing a single stdlib function body (not its signature) *)
  let list_src = Db.query db (Q.source_text "stdlib/list.march") in
  let patched = patch_fn_body list_src "map" "-- different impl\n" in
  Db.set_input db (Q.source_text "stdlib/list.march") patched;
  let _ = Db.query db (Q.typed_module "user.march") in
  let t1 = Unix.gettimeofday () in

  let t_full0 = Unix.gettimeofday () in
  let db2 = make_db () in
  setup_all_stdlib db2;
  let _ = Db.query db2 (Q.typed_module "user.march") in
  let t_full1 = Unix.gettimeofday () in

  let incremental_ms = (t1 -. t0) *. 1000. in
  let full_ms = (t_full1 -. t_full0) *. 1000. in
  Printf.printf "Incremental: %.1fms, Full: %.1fms, Speedup: %.1fx\n"
    incremental_ms full_ms (full_ms /. incremental_ms);
  (* Target: incremental should be < 10% of full recompile *)
  assert (incremental_ms < full_ms *. 0.1)
```

---

## 6. Migration Strategy

### 6.1 Parallel Execution with Feature Flags

Every phase adds a flag to `bin/main.ml` and the LSP server:

```
--query-parse      Phase 2: use query-based parse
--query-names      Phase 3: use query-based name resolution
--query-typecheck  Phase 4: use query-based type checking
--query-tir        Phase 5: use query-based TIR lowering
--query-codegen    Phase 7: use query-based codegen
--query-all        All of the above
```

During migration, both paths are tested:
```bash
# Run existing tests against old path
dune runtest

# Run same tests against query path
MARCH_QUERY_FLAGS=--query-all dune runtest
```

If outputs differ, the query path has a bug. The test suite is the oracle.

### 6.2 Dual-Mode Execution for Validation

A special `--validate-query` flag runs both pipelines and diffs the output:

```ocaml
(* bin/main.ml *)
if !validate_query_mode then begin
  let old_result = run_old_pipeline filename in
  let new_result = run_query_pipeline filename in
  if old_result <> new_result then begin
    Printf.eprintf "QUERY VALIDATION FAILURE for %s:\n" filename;
    Printf.eprintf "Old: %s\n" (show old_result);
    Printf.eprintf "New: %s\n" (show new_result);
    exit 2
  end
end
```

Run this on the entire test suite and all example programs before removing the old path.

### 6.3 Phase-by-Phase Rollback Plan

Each phase is implemented on a feature branch. If a phase introduces regressions:
- The branch is reverted.
- The feature flag ensures users on `main` are unaffected.
- The old path stays in place until the query path passes all tests.

Phases 1–3 (infrastructure + parsing) are low risk — easy to revert.
Phase 4 (type checking) is the highest risk — keep old path active for at least one release cycle.
Phases 5–7 (TIR + codegen) are medium risk.
Phases 8–10 build on Phase 4 and follow the same caution.

### 6.4 Maintaining the REPL JIT During Migration

The `lib/jit/repl_jit.ml` module continues to work unchanged during Phases 1–7. Phase 8 introduces the query-based REPL. The migration:

1. Create `lib/jit/repl_jit_query.ml` implementing the query-based REPL.
2. `lib/repl/repl.ml` gets a `~use_query_jit` flag.
3. Both paths are tested: `test_jit.ml` runs both.
4. Once `repl_jit_query.ml` passes all REPL JIT regression tests (including the 8 currently failing `repl_jit_regression` tests), the old `repl_jit.ml` is deprecated.

---

## 7. OCaml Implementation Patterns

### 7.1 The Query Key Type

Using a GADT for type-safe query keys:

```ocaml
(* lib/query/query.ml *)

type 'a query =
  (* Input queries *)
  | SourceText    : string -> string query
  | CompilerFlags : unit   -> string list query
  (* Derived queries *)
  | TokensOf      : string -> (Token.t * Ast.span) list query
  | ParsedModule  : string -> Ast.module_ result query
  | DesugaredModule : string -> Ast.module_ result query
  | StdlibDecls   : unit   -> Ast.decl list query
  | NameResolution : string -> name_map result query
  | TypedModule   : string -> (Ast.module_ * type_map) result query
  | SigHashOf     : string -> string query
  | TirOf         : string -> Tir.tir_module result query
  | MonoOf        : string -> Tir.tir_module result query
  | DefunOf       : string -> Tir.tir_module result query
  | PerceusOf     : string -> Tir.tir_module result query
  | EscapeOf      : string -> Tir.tir_module result query
  | OptOf         : string -> Tir.tir_module result query
  | LlvmIrOf      : string -> string result query
  | CompiledArtifact : string -> artifact_path result query
  | TypeAtPos     : (string * int * int) -> ty option query
  | DefsAt        : (string * int * int) -> (string * Ast.span) list query
  | Diagnostics   : string -> diagnostic list query
```

Query key serialization for the hashtable:
```ocaml
let key_of_query : type a. a query -> string = function
  | SourceText path      -> "src:" ^ path
  | TokensOf path        -> "tok:" ^ path
  | ParsedModule path    -> "par:" ^ path
  | DesugaredModule path -> "dsg:" ^ path
  | TypedModule path     -> "typ:" ^ path
  | TirOf path           -> "tir:" ^ path
  | LlvmIrOf path        -> "llv:" ^ path
  | TypeAtPos (p,l,c)    -> Printf.sprintf "tpos:%s:%d:%d" p l c
  | Diagnostics path     -> "diag:" ^ path
  (* ... *)
```

### 7.2 The Database Type

```ocaml
(* lib/query/db.ml *)

module IntMap = Map.Make(Int)

type entry =
  | EInput   of { rev: int; value: Obj.t }
  | EDerived of { computed_rev: int;
                  value: Obj.t;
                  dep_keys: string list;
                  execution_count: int }

type t = {
  mutable current_rev : int;
  entries : (string, entry) Hashtbl.t;
  (* Dependency tracking *)
  mutable exec_stack  : string list;  (* stack of currently-executing query keys *)
  dep_log             : (string, string list) Hashtbl.t;  (* key → [deps] *)
  (* Observability *)
  mutable exec_hook   : (string -> unit) option;
}

let create () = {
  current_rev = 0;
  entries     = Hashtbl.create 256;
  exec_stack  = [];
  dep_log     = Hashtbl.create 256;
  exec_hook   = None;
}
```

### 7.3 Effect-Based Dependency Tracking (OCaml 5)

```ocaml
(* lib/query/tracking.ml — requires OCaml 5 effects *)

type _ Effect.t +=
  | RecordDep : string -> unit Effect.t

(** Execute [f] and collect all query keys it reads via RecordDep. *)
let with_dep_tracking key f =
  let deps = ref [] in
  let result =
    Effect.Deep.match_with f ()
    { Effect.Deep.
      retc = (fun x -> x);
      exnc = (fun e -> raise e);
      effc = fun (type a) (eff : a Effect.t) ->
        match eff with
        | RecordDep dep_key ->
          Some (fun (k : (a, _) Effect.Deep.continuation) ->
            deps := dep_key :: !deps;
            Effect.Deep.continue k ())
        | _ -> None }
  in
  (result, List.rev !deps)

(** Call this inside a query to declare a dependency. *)
let record_dep key =
  Effect.perform (RecordDep key)
```

### 7.4 The Core Query Execution Engine

```ocaml
let rec query : type a. t -> a Query.query -> a = fun db q ->
  let key = Query.key_of_query q in
  Option.iter (fun hook -> hook key) db.exec_hook;
  (* Push onto execution stack for dep tracking *)
  db.exec_stack <- key :: db.exec_stack;
  let result =
    match Hashtbl.find_opt db.entries key with
    | Some (EInput { value; _ }) ->
      (* Record this as a dep of the caller *)
      record_dep_of_caller db key;
      Obj.obj value
    | Some (EDerived { computed_rev; value; dep_keys; execution_count }) ->
      (* Is the cache still valid? *)
      if still_valid db computed_rev dep_keys then begin
        record_dep_of_caller db key;
        Obj.obj value
      end else begin
        (* Re-compute *)
        recompute db q key execution_count
      end
    | None ->
      (* Never computed *)
      recompute db q key 0
  in
  db.exec_stack <- List.tl db.exec_stack;
  result

and recompute : type a. t -> a Query.query -> string -> int -> a = fun db q key prev_count ->
  let compute_fn = Query_registry.find q in
  let (new_value, deps) = with_dep_tracking key (fun () -> compute_fn db q) in
  (* Early-return: if new value equals old, don't bump revision *)
  let new_rev =
    match Hashtbl.find_opt db.entries key with
    | Some (EDerived { value = old_value; _ }) when Obj.obj old_value = new_value ->
      db.current_rev  (* unchanged — keep old revision, don't propagate *)
    | _ ->
      db.current_rev
  in
  Hashtbl.replace db.entries key
    (EDerived { computed_rev = new_rev;
                value = Obj.repr new_value;
                dep_keys = deps;
                execution_count = prev_count + 1 });
  new_value
```

### 7.5 Functor-Based Query Composition

For testability, each "subsystem" of queries is a functor over the database type:

```ocaml
(* lib/query/parse_system.ml *)
module Make (Db : DB_SIG) = struct
  let tokens_of db path =
    Db.depends_on db (Q.SourceText path);
    let src = Db.query db (Q.SourceText path) in
    March_lexer.Lexer.lex_string ~filename:path src

  let parsed_module db path =
    Db.depends_on db (Q.TokensOf path);
    let src = Db.query db (Q.SourceText path) in
    match March_parser.Parser.parse_string ~filename:path src with
    | Ok m -> Ok m
    | Error e -> Error [e]

  let register db =
    Db.register db Q.TokensOf (tokens_of db);
    Db.register db Q.ParsedModule (parsed_module db)
end
```

This allows unit testing query subsystems with a mock database.

---

## 8. Risks and Mitigations

### 8.1 Performance Overhead of Query Tracking

**Risk:** Every function call through the query layer has overhead: hashtable lookup, stack push/pop, dep recording. For a small project (single file), this could make batch compilation slower than the current direct pipeline.

**Mitigation:**
- For batch compilation of a single file with no incremental state, bypass the query system and call functions directly (the old path). The query system only activates when incremental compilation is needed.
- Measure overhead in Phase 1 using the benchmark suite (`bench/`).
- Target: query overhead < 5ms per compilation on a 1000-line file.

### 8.2 Memory Usage for Memoized Results

**Risk:** The database retains all computed ASTs, type maps, and TIR in memory. For large codebases, this could be gigabytes.

**Mitigation:**
- Implement LRU eviction for derived query results. Keep only the `N` most recently accessed entries in memory; others are evicted and re-computed on demand.
- For the CAS-backed Phase 10 approach, evicted entries can be reloaded from disk without re-running the computation.
- For the LSP server, only keep entries for open documents in memory; evict closed documents.

### 8.3 Complexity Budget

**Risk:** The query infrastructure adds significant complexity (new abstraction layer, GADT-heavy code, effect handlers) that makes the compiler harder to understand and modify.

**Mitigation:**
- The query database is isolated in `lib/query/`. All existing code in `lib/typecheck/`, `lib/tir/`, etc. continues to work as plain functions. The query layer is a thin wrapper.
- Maintain the existing pipeline in `bin/main.ml` (behind a flag) until the query path is stable. New contributors can ignore the query system initially.
- Write a `docs/query-architecture.md` explaining the design; include in the language reference.

### 8.4 Incremental Slower Than Batch for Small Projects

**Risk:** For a 100-line single-file program, the overhead of the query system (hashtable lookups, dep tracking, stack manipulation) makes compilation slower than the direct pipeline.

**Mitigation:**
- Always use the direct pipeline for single-file programs where no incremental state exists. The query system is opt-in.
- The LSP server is the primary beneficiary. Batch compilation should always use the direct path for single-file programs.
- For the REPL, the incremental benefit appears after the first expression; subsequent expressions are much faster.

### 8.5 The Monomorphization Whole-Program Problem

**Risk:** Monomorphization (`March_tir.Mono`) is inherently whole-program. Wrapping it as a per-module query doesn't give fine-grained incrementality.

**Mitigation:**
- Accept this limitation in Phase 5. `monomorphized_module` takes the full project graph as input and is a single whole-program query.
- Post-v1: explore per-SCC mono (Option B from Phase 5). The key insight: an SCC's monomorphization inputs are the set of type-specialized call sites pointing INTO it. If those don't change, the SCC's mono output is cached.

### 8.6 Typecheck Side Effects (Global State in typecheck.ml)

**Risk:** `typecheck.ml` uses several global mutable counters (`_counter`, `_tvar_names`, `_tvar_ctr`). A query-based typecheck needs to be pure/deterministic, but these counters will produce different IDs on each run.

**Mitigation:**
- Thread the counter state through the type checker as a record rather than using global refs.
- This is a prerequisite for Phase 4. The refactoring can be done incrementally inside typecheck.ml while all existing tests continue to pass.
- The type_map produces spans as keys (not tvar IDs), so this is safe.

---

## 9. Success Criteria

### Phase 1 (Foundation)
- [ ] Query database passes all 6 unit tests described in §4.1
- [ ] Early-return optimization test passes
- [ ] Cycle detection test passes
- [ ] No regressions in existing 1061 tests
- [ ] Benchmark: `Db.query` overhead < 1µs per lookup (cached case)

### Phase 2 (Parse Queries)
- [ ] `tokens_of`, `parsed_module`, `desugared_module` queries pass all tests
- [ ] Editing a comment in a file triggers re-parse but NOT re-typecheck (via early-return)
- [ ] Old pipeline and new pipeline produce identical output for all 846 `test_march` cases (verified by `--validate-query`)

### Phase 3 (Name Resolution)
- [ ] `name_resolution` and `module_graph` queries pass all tests
- [ ] LSP goto-def and rename use query-based name resolution
- [ ] 84 LSP tests still pass

### Phase 4 (Type Inference)
- [ ] `typed_module` with sig/impl split passes all tests
- [ ] Incremental correctness test: changing A's body without changing its sig does NOT re-typecheck B
- [ ] All 846 `test_march` type error tests produce identical diagnostics via query path
- [ ] Performance target: after warming the cache, re-typechecking a module that imports stdlib (but stdlib is unchanged) takes < 50ms

### Phase 5–7 (TIR + Codegen)
- [ ] `tir_of_module`, `monomorphized_module`, `llvm_ir_of_module` queries pass all tests
- [ ] CAS integration: second compilation of an unchanged file produces 0 clang invocations
- [ ] Oracle tests: `march --query-all` and `march` produce identical binaries for all programs in `examples/`

### Phase 8 (REPL)
- [ ] All 8 currently failing `repl_jit_regression` tests pass via query-based REPL path
- [ ] Failed-compilation-no-corruption test passes
- [ ] REPL query system is the default (old `repl_jit.ml` deprecated but not deleted)

### Phase 9 (LSP)
- [ ] All 84 LSP tests pass via query-based LSP
- [ ] Measured: hover response time < 20ms on a warm cache (vs. > 100ms full pipeline)
- [ ] Measured: diagnostics update < 100ms after a keystroke on a 500-line file

### Phase 10 (CAS Integration)
- [ ] Warm start test passes: second session loads results from CAS with 0 re-typechecks
- [ ] `deciduous sync` equivalent for query persistence works

### Overall Success Metrics

| Metric | Target |
|--------|--------|
| Incremental re-compile after 1-line change in 1000-line project | < 10% of full recompile time |
| LSP hover latency (warm cache) | < 20ms |
| LSP diagnostics update (1 changed file) | < 100ms |
| Memory overhead of query database for stdlib | < 50MB |
| Query lookup overhead (cache hit) | < 1µs |
| Full batch compile overhead vs. direct pipeline | < 5ms total |
| Test suite still passes | 1061/1061 |

---

## Appendix A: File Layout for Query Infrastructure

```
lib/
├── query/
│   ├── dune
│   ├── query.ml       -- GADT query type, key_of_query
│   ├── db.ml          -- database type, set_input, query
│   ├── tracking.ml    -- OCaml 5 effect-based dep tracking
│   ├── registry.ml    -- global query registry
│   ├── parse_system.ml   -- tokens_of, parsed_module, desugared_module
│   ├── name_system.ml    -- name_resolution, module_graph, stdlib_decls
│   ├── type_system.ml    -- typed_module, sig_hash, type_at_position
│   ├── tir_system.ml     -- tir_of, mono, defun, perceus, escape, opt
│   ├── codegen_system.ml -- llvm_ir_of, compiled_artifact
│   ├── repl_system.ml    -- repl_session, repl_fragment
│   └── lsp_system.ml     -- diagnostics, completion, hover, etc.
├── query_persist/
│   ├── dune
│   ├── persist.ml     -- serialize/deserialize query entries to CAS
│   └── warm_start.ml  -- load CAS into db at session start
test/
├── test_query_db.ml
├── test_query_parse.ml
├── test_query_names.ml
├── test_query_typecheck.ml
├── test_query_tir.ml
├── test_query_repl.ml
└── test_query_lsp.ml
```

## Appendix B: Reading List

For implementers picking this up:

1. **Salsa tutorial**: https://salsa-rs.github.io/salsa/ — the Rust version is the best existing documentation of this pattern.
2. **"Incremental Computation with Names"** (Hammer et al.) — theoretical foundations for memoized computation.
3. **`rustc` dev guide — "Queries: demand-driven compilation"** — practical documentation of how rustc uses this pattern.
4. **Roslyn architecture white paper** — the .NET implementation with lazy syntax trees.
5. **OCaml 5 effects tutorial** — for the dependency tracking mechanism: https://v2.ocaml.org/manual/effects.html

## Appendix C: Example — What a Changed-Comment Edit Looks Like End-to-End

Given the source:
```
-- old comment
fn f(x : Int) do x + 1 end
```

Changed to:
```
-- new comment
fn f(x : Int) do x + 1 end
```

Query execution trace (✓ = cache hit, ✗ = re-run):
```
source_text("t.march")    ✗  (input changed)
tokens_of("t.march")      ✗  (source_text changed → re-lex)
parsed_module("t.march")  ✗  (tokens changed → re-parse)
desugared_module("t.march")  ✗  (parsed_module changed → re-desugar)
  → but: AST is structurally equal (comment stripped by lexer)
  → early-return: desugared_module.revision unchanged
typed_module("t.march")   ✓  (desugared_module revision unchanged → cache hit)
tir_of("t.march")         ✓  (typed_module unchanged)
optimized("t.march")      ✓  (tir unchanged)
llvm_ir_of("t.march")     ✓  (tir unchanged)
compiled_artifact("t.march")  ✓  (CAS hit)
```

Total work: re-lex + re-parse + early-return check. Everything from `typed_module` onward is served from cache. In practice this means the incremental cost of a comment edit is microseconds, not seconds.
