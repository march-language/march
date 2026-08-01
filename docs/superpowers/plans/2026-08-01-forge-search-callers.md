# forge search --callers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `forge search --callers NAME`, a reverse-reference search that resolves who calls a function, uses a constructor, or references a type — reusing the existing `forge search` index and the typechecker's own name resolution (not a textual/grep heuristic).

**Architecture:** The typechecker (`lib/typecheck/typecheck.ml`) already resolves every `EVar` call, `ECon` constructor use, and qualified `TyCon` type reference against `env` while typechecking. We add a small accumulator (`env.refs`) that records `(callee, caller, kind, file, line)` at the exact points where that resolution already succeeds, plus a `current_decl` tracker so each reference knows its enclosing function. `lib/search/search.ml`'s existing index (built by the same typecheck pass that already produces `type_map`) gains a `references` table keyed by callee. `forge/lib/cmd_search.ml` exposes it via `--callers`.

**Tech Stack:** OCaml, dune, Alcotest (`test/test_search.ml`), Yojson for the on-disk index cache.

## Global Constraints

- Precision: resolution-based only. A reference is recorded ONLY when it resolves to a real declaration through the typechecker's own lookup — never a bare textual/name-only match.
- Reference kinds tracked in this plan: function/value calls (Task 2), constructor uses (Task 3), and **qualified** type-annotation references only (Task 4) — see the accepted gaps below.
- Index integration: extends the existing `Search.index` / `.march/search-index.json` cache and the existing `forge search` command. No new cache file, no new subcommand.
- Traversal depth: direct references only. No `--depth N` / transitive closure.
- Corpus: same as today's `forge search` (stdlib + project deps via `Project.load ()`).
- **Accepted gaps (do not attempt to fix in this plan — call out clearly if discovered again):**
  - Special-cased call forms that pattern-match a whole `EApp` before the generic `EVar` arm runs (`Chan.new`, `Chan.send`, `Chan.recv`, `Chan.close`, `Chan.choose`, `Chan.offer`, `MPST.new`, `MPST.send`, `MPST.recv`, `MPST.close`, `cap_narrow`, `mint_cap` — `lib/typecheck/typecheck.ml:4797-5290`) never reach the generic `EVar`/`ECon` hooks and will not appear as references. These are compiler builtins, not user-declared callees.
  - Constructor resolution by expected type (`lib/typecheck/typecheck.ml:5961`, the `Ast.ECon (name, args, sp), exp_ty when ...` arm used to disambiguate same-named constructors from context) is a second, separate resolution path from the one this plan instruments (`typecheck.ml:5420`). Constructor calls resolved only through that path won't be recorded as references in this plan.
  - Bare (unqualified) type-annotation references are not tracked — only explicitly-qualified `Mod.TypeName` annotations are. Unlike functions and constructors, the typechecker doesn't currently expose which module a bare type name resolved from a same-module vs. builtin binding, so recording it in v1 would risk misattributing the caller's own module for a cross-module bare reference.

---

## File Structure

- **Modify `lib/typecheck/typecheck.ml`**: add `ref_record` type + `env.refs`/`env.current_decl` fields (Task 1); hook the generic `EVar` call-resolution arm and `check_fn` (Task 2); hook the `ECon` constructor-resolution arm (Task 3); hook `surface_ty`'s qualified `TyCon` case (Task 4); add `check_module_with_refs` next to `check_module` (Task 2).
- **Modify `lib/search/search.ml`**: add `references` field to `index`, populate it from `TC.check_module_with_refs`, extend JSON (de)serialization, add `?callers` to `search_combined`, add reference-result formatters (Task 5).
- **Modify `forge/lib/cmd_search.ml`**: add `--callers` flag and wire it through (Task 6).
- **Modify `test/dune`**: add `march_typecheck march_parser march_lexer march_desugar march_ast` to the `test_search` stanza's `libraries` so tests can drive the typecheck pipeline directly (Task 2).
- **Modify `test/test_search.ml`**: add reference-tracking tests for each kind, the ambiguous-ctor regression, the cache round-trip, and an end-to-end `--callers`-style query test (Tasks 2, 3, 4, 5, 7).

---

## Task 1: `ref_record` type + `env` scaffolding

**Files:**
- Modify: `lib/typecheck/typecheck.ml:487-488` (just before `type env = {`)
- Modify: `lib/typecheck/typecheck.ml:707-709` (`make_env`)

**Interfaces:**
- Produces: `type ref_record = { callee : string; caller : string; ref_kind : [ \`Call | \`Ctor | \`TypeRef ]; ref_file : string; ref_line : int }`, and two new `env` fields: `refs : ref_record list ref` and `current_decl : string ref`.

This task only adds inert scaffolding (an unused-until-later accumulator) — there is no new observable behavior to unit test, so the "test" is confirming the compiler still builds and the existing suite is unaffected.

- [ ] **Step 1: Add the `ref_record` type immediately before `type env = {` (line 488)**

```ocaml
(** A resolved reference recorded during typechecking: [callee] used a
    declaration that [caller] (both fully-qualified "Mod.name") owns, at
    [ref_file]:[ref_line]. Populated only where resolution already succeeds —
    never a textual guess. *)
type ref_record = {
  callee   : string;
  caller   : string;
  ref_kind : [ `Call | `Ctor | `TypeRef ];
  ref_file : string;
  ref_line : int;
}
```

- [ ] **Step 2: Add the two fields to `type env = { ... }`, right after `type_map : (Ast.span, ty) Hashtbl.t;` (line 498)**

```ocaml
  refs : ref_record list ref;
  (** Resolved call/ctor/type references accumulated during checking, for
      `forge search --callers`. Shared (mutable) across all env copies
      derived from the same root, same as [import_tracker]. *)
  current_decl : string ref;
  (** Fully-qualified name ("Mod.fn") of the top-level fn/impl-method whose
      body is currently being checked. Set by [check_fn]; read wherever a
      [ref_record] is recorded so it knows its caller. Empty string before
      the first fn is entered. *)
```

- [ ] **Step 3: Initialize both fields in `make_env` (line 707-709), alongside `pending_constraints = ref []`**

```ocaml
let make_env errors type_map = {
  vars = StrMap.empty; types = StrMap.empty; ctors = StrMap.empty; records = StrMap.empty;
  level = 0; lin = [];
  errors; pending_constraints = ref []; type_map;
  refs = ref []; current_decl = ref "";
  scheme_witnesses = Hashtbl.create 64;
  inst_witnesses = Hashtbl.create 256;
  interfaces = StrMap.empty; sigs = [];
  mod_needs = []; module_caps = []; protocols = StrMap.empty; impls = StrMap.empty;
  import_tracker = ref [];
  import_idx = make_import_index ();
  local_fns = StrMap.empty;
  fn_arities = StrMap.empty;
  plain_let_names = StringSet.empty;
```

(Keep every other existing field/line in `make_env` exactly as-is — only the one new line is inserted.)

- [ ] **Step 4: Build and run the existing suite to confirm no regression**

Run: `dune build lib/typecheck/typecheck.ml`
Expected: builds clean (a record literal missing a field is a hard OCaml compile error, so a clean build already proves both fields are wired into every `env` construction site).

Run: `scripts/run-tests.sh -q`
Expected: same pass count as before this change (no behavior changed yet).

- [ ] **Step 5: Commit**

```bash
git add lib/typecheck/typecheck.ml
git commit -m "typecheck: add ref_record accumulator scaffolding to env"
```

---

## Task 2: Call-reference recording (`EVar`) + `check_module_with_refs`

**Files:**
- Modify: `lib/typecheck/typecheck.ml:4697-4704` (generic `EVar` arm in `infer_expr`)
- Modify: `lib/typecheck/typecheck.ml:6690` (`check_fn`, to set `current_decl`)
- Modify: `lib/typecheck/typecheck.ml:11122-11125` (add `check_module_with_refs` next to `check_module`)
- Modify: `test/dune` (`test_search` stanza libraries)
- Modify: `test/test_search.ml` (new test)

**Interfaces:**
- Consumes: `ref_record`, `env.refs`, `env.current_decl`, `env.local_fns : unit StrMap.t` (already exists — "function names defined by the module currently being checked"), `env.current_module : string` (already exists), `lookup_var`, `resolve_qualified_var` (all Task 1 / pre-existing).
- Produces: `TC.check_module_with_refs : ?errors:Err.ctx -> Ast.module_ -> Err.ctx * (Ast.span, TC.ty) Hashtbl.t * TC.ref_record list`, used by Task 5.

- [ ] **Step 1: Write the failing test in `test/test_search.ml`**

First add the extra libraries `test_search` needs (edit `test/dune`, the `test_search` stanza at line 590-592):

```
 (name test_search)
 (modules test_search)
 (libraries march_search march_typecheck march_parser march_lexer march_desugar march_ast alcotest unix))
```

Then add this test to `test/test_search.ml` (near the top, after the Levenshtein tests, before `sample_index`):

```ocaml
(* ------------------------------------------------------------------ *)
(* Reference tracking (forge search --callers)                        *)
(* ------------------------------------------------------------------ *)

module TC = March_typecheck.Typecheck

(** Parse + desugar a source string into decls wrapped in a DMod, mirroring
    [Search.parse_file]'s handling of a real .march file. *)
let decls_of_source ~(file : string) (mod_name : string) (src : string) : Ast.decl list =
  let module Ast = March_ast.Ast in
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <- { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = file };
  let m = March_parser.Parser.module_
      (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  let m = March_desugar.Desugar.desugar_module m in
  ignore mod_name;
  [Ast.DMod (m.Ast.mod_name, Ast.Public, m.Ast.mod_decls, Ast.dummy_span)]

let check_refs (files : (string * string * string) list) : TC.ref_record list =
  (* [files] is (file, mod_name, src) list. *)
  let module Ast = March_ast.Ast in
  let all_decls = List.concat_map (fun (file, mod_name, src) ->
      decls_of_source ~file mod_name src) files in
  let synth : Ast.module_ =
    { mod_name = { txt = "__test__"; span = Ast.dummy_span }; mod_decls = all_decls } in
  let (_errors, _type_map, refs) = TC.check_module_with_refs synth in
  refs

let test_call_ref_same_module () =
  let refs = check_refs [
    ("a.march", "A", "mod A do\n  fn helper() do 1 end\n  fn main() do helper() end\nend\n");
  ] in
  let calls = List.filter (fun (r : TC.ref_record) -> r.ref_kind = `Call) refs in
  Alcotest.(check bool) "helper call recorded" true
    (List.exists (fun (r : TC.ref_record) ->
         r.callee = "A.helper" && r.caller = "A.main") calls)

let test_call_ref_cross_module () =
  let refs = check_refs [
    ("b.march", "B", "mod B do\n  fn util() do 1 end\nend\n");
    ("a.march", "A", "mod A do\n  fn main() do B.util() end\nend\n");
  ] in
  let calls = List.filter (fun (r : TC.ref_record) -> r.ref_kind = `Call) refs in
  Alcotest.(check bool) "cross-module B.util call recorded" true
    (List.exists (fun (r : TC.ref_record) ->
         r.callee = "B.util" && r.caller = "A.main") calls)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dune build @test/test_search.exe 2>&1 | tail -40` (expect a compile error: `check_module_with_refs`/`ref_record`/`ref_kind` unbound, since Task 2's implementation doesn't exist yet).
Expected: FAIL — build error referencing the missing `check_module_with_refs`/`ref_record`.

- [ ] **Step 3: Hook `check_fn` to set `current_decl` (line 6690)**

```ocaml
let check_fn env (def : Ast.fn_def) fn_span : scheme =
  env.current_decl := env.current_module ^ "." ^ def.fn_name.txt;
  let env'    = enter_level env in
```

(One line inserted before the existing `let env' = enter_level env in`; nothing else in `check_fn` changes. `env.current_decl` is a shared `ref`, so this is visible to every nested `infer_expr` call for the rest of this function body, including impl-method bodies — `check_fn` is also the entry point `DImpl` uses at `typecheck.ml:9841`.)

- [ ] **Step 4: Hook the generic `EVar` arm to record calls (lines 4697-4704)**

```ocaml
    (* ── Variables ────────────────────────────────────────────────── *)
    | Ast.EVar name ->
      record_use name.txt name.span env;
      (match lookup_var name.txt env with
       | Some sch ->
         (if StrMap.mem name.txt env.local_fns then
            env.refs := { callee = env.current_module ^ "." ^ name.txt;
                          caller = !(env.current_decl);
                          ref_kind = `Call;
                          ref_file = name.span.Ast.file;
                          ref_line = name.span.Ast.start_line } :: !(env.refs));
         instantiate ~use_span:name.span env.level env sch
       | None     ->
         (* Try qualified module resolution: "Mod.func" *)
         match resolve_qualified_var name.txt env with
         | _, Some sch ->
           env.refs := { callee = name.txt;
                         caller = !(env.current_decl);
                         ref_kind = `Call;
                         ref_file = name.span.Ast.file;
                         ref_line = name.span.Ast.start_line } :: !(env.refs);
           instantiate ~use_span:name.span env.level env sch
         | _ when is_confirmed_private_qualified name.txt env ->
           (* A confirmed privacy violation (`Mod.priv_fn`) must be reported
```

(Everything from `| _ when is_confirmed_private_qualified ...` onward is unchanged existing code — only the two `if`/insertion blocks above are new. Note: `env.local_fns` guards the bare-name case so only genuine top-level function calls are recorded, not references to local `let`-bound values, which also live in `env.vars`.)

- [ ] **Step 5: Add `check_module_with_refs` next to `check_module` (line 11122-11125)**

```ocaml
let check_module ?errors (m : Ast.module_) : Err.ctx * (Ast.span, ty) Hashtbl.t =
  let (errs, type_map, _env) = check_module_core ?errors m in
  (errs, type_map)

(** Like [check_module], but also returns every resolved call/ctor/type
    reference recorded during checking — used by [forge search --callers].
    Order is call-order, most-recent-first is reversed back to source order. *)
let check_module_with_refs ?errors (m : Ast.module_)
    : Err.ctx * (Ast.span, ty) Hashtbl.t * ref_record list =
  let (errs, type_map, final_env) = check_module_core ?errors m in
  (errs, type_map, List.rev !(final_env.refs))
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `dune build @test/test_search.exe && ./_build/default/test/test_search.exe test 'reference'` (or `dune exec test/test_search.exe -- test`)
Expected: PASS for `test_call_ref_same_module` and `test_call_ref_cross_module`. If you haven't registered the two tests in the Alcotest runner list at the bottom of `test/test_search.ml` yet, add them there now (follow the existing `"levenshtein", [...]` group pattern — add a `"references", [ Alcotest.test_case "same-module call" \`Quick test_call_ref_same_module; Alcotest.test_case "cross-module call" \`Quick test_call_ref_cross_module; ]` group) and re-run.

- [ ] **Step 7: Run the full suite to confirm no regressions**

Run: `scripts/run-tests.sh -q`
Expected: all passing, count unchanged except the new test_search cases.

- [ ] **Step 8: Commit**

```bash
git add lib/typecheck/typecheck.ml test/dune test/test_search.ml
git commit -m "typecheck: record resolved call references for forge search --callers"
```

---

## Task 3: Constructor-reference recording (`ECon`)

**Files:**
- Modify: `lib/typecheck/typecheck.ml:5420-5429` (`ECon` arm in `infer_expr`)
- Modify: `test/test_search.ml`

**Interfaces:**
- Consumes: `ctor_info.ci_module : string` (already exists, doc'd as "declaring module of this constructor's parent type").
- Produces: additional `ref_record`s with `ref_kind = \`Ctor`.

- [ ] **Step 1: Write the failing test**

```ocaml
let test_ctor_ref_recorded () =
  let refs = check_refs [
    ("a.march", "A",
     "mod A do\n  type Box = Empty | Full(Int)\n  fn main() do Full(1) end\nend\n");
  ] in
  let ctors = List.filter (fun (r : TC.ref_record) -> r.ref_kind = `Ctor) refs in
  Alcotest.(check bool) "Full ctor use recorded" true
    (List.exists (fun (r : TC.ref_record) ->
         r.callee = "A.Full" && r.caller = "A.main") ctors)
```

Add it to `test/test_search.ml` next to the Task 2 tests and to the `"references"` Alcotest group.

- [ ] **Step 2: Run test to verify it fails**

Run: `dune build @test/test_search.exe && dune exec test/test_search.exe -- test`
Expected: FAIL — `test_ctor_ref_recorded` reports no `A.Full`/`A.main` entry (nothing records ctor uses yet).

- [ ] **Step 3: Hook the `ECon` arm (line 5420-5429)**

```ocaml
    (* ── Constructor application ──────────────────────────────────── *)
    | Ast.ECon (name, args, sp) ->
      (let ci_opt = match lookup_ctor_same_module name.txt env with
         | Some _ as r -> r
         | None ->
         match lookup_ctor name.txt env with
         | Some _ as r -> r
         | None ->
           (* Try qualified module resolution: "Mod.Ctor" *)
           let _, resolved = resolve_qualified_ctor name.txt env in
           resolved
       in
       (match ci_opt with
        | Some ci ->
          env.refs := { callee = ci.ci_module ^ "." ^
                          (if String.contains name.txt '.'
                           then (let i = String.rindex name.txt '.' in
                                 String.sub name.txt (i + 1) (String.length name.txt - i - 1))
                           else name.txt);
                        caller = !(env.current_decl);
                        ref_kind = `Ctor;
                        ref_file = sp.Ast.file;
                        ref_line = sp.Ast.start_line } :: !(env.refs)
        | None -> ());
       match ci_opt with
       | None ->
         let candidates = suggest_ctors name.txt env in
```

(The added block sits between the existing `let ci_opt = ... in` and the existing `match ci_opt with | None -> ...` — it re-matches `ci_opt` once purely to record the reference, then falls through to the original `match ci_opt with` unchanged. `name.txt` may already be `"Mod.Ctor"` for an explicitly-qualified constructor use, so the bare ctor name is extracted after the last `.` before re-qualifying with `ci.ci_module`, keeping the callee format consistent with Task 2's `"Mod.name"`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `dune build @test/test_search.exe && dune exec test/test_search.exe -- test`
Expected: PASS.

- [ ] **Step 5: Run the full suite**

Run: `scripts/run-tests.sh -q`
Expected: all passing.

- [ ] **Step 6: Commit**

```bash
git add lib/typecheck/typecheck.ml test/test_search.ml
git commit -m "typecheck: record resolved constructor references for forge search --callers"
```

---

## Task 4: Qualified type-reference recording (`TyCon`)

**Files:**
- Modify: `lib/typecheck/typecheck.ml:3048-3052` (`surface_ty`'s `Ast.TyCon` case)
- Modify: `test/test_search.ml`

**Interfaces:**
- Produces: additional `ref_record`s with `ref_kind = \`TypeRef`, for explicitly-qualified `Mod.TypeName` annotations only (see Global Constraints — bare type references are an accepted gap).

- [ ] **Step 1: Read the exact current `Ast.TyCon` case before editing**

Run: `sed -n '3040,3070p' lib/typecheck/typecheck.ml` and confirm the match arm shape and the span available (the surrounding `surface_ty` signature is `surface_ty env ~tvars (s : Ast.ty) : ty`, matching `Ast.TyCon (name, args)` — note `Ast.TyCon` carries a `name : Ast.name` with a `.span`, per `lib/ast/ast.ml`'s `TyCon of name * ty list`). If the arm shape has drifted from what's captured in this plan's Task-writing investigation, adapt the insertion point accordingly — the anchor is "wherever `Ast.TyCon (name, args)` is matched and resolves to a type", not the exact line number.

- [ ] **Step 2: Write the failing test**

```ocaml
let test_typeref_qualified_recorded () =
  let refs = check_refs [
    ("b.march", "B", "mod B do\n  type Widget = Widget(Int)\nend\n");
    ("a.march", "A", "mod A do\n  fn make(w: B.Widget) do w end\nend\n");
  ] in
  let tyrefs = List.filter (fun (r : TC.ref_record) -> r.ref_kind = `TypeRef) refs in
  Alcotest.(check bool) "B.Widget annotation recorded" true
    (List.exists (fun (r : TC.ref_record) ->
         r.callee = "B.Widget" && r.caller = "A.make") tyrefs)
```

Add to `test/test_search.ml`'s `"references"` group.

- [ ] **Step 3: Run test to verify it fails**

Run: `dune build @test/test_search.exe && dune exec test/test_search.exe -- test`
Expected: FAIL — no `TypeRef` entries exist yet.

- [ ] **Step 4: Hook the qualified `Ast.TyCon` case in `surface_ty`**

```ocaml
  | Ast.TyCon (name, args) ->
    (if String.contains name.Ast.txt '.' then
       env.refs := { callee = name.Ast.txt;
                     caller = !(env.current_decl);
                     ref_kind = `TypeRef;
                     ref_file = name.Ast.span.Ast.file;
                     ref_line = name.Ast.span.Ast.start_line } :: !(env.refs));
    (* ... existing resolution body unchanged below ... *)
```

Insert the `if`-block as the first line of the existing `Ast.TyCon (name, args) -> ...` arm body, leaving every subsequent line of that arm exactly as it already is. Only qualified names (containing `.`) are recorded, per the Global Constraints gap.

- [ ] **Step 5: Run test to verify it passes**

Run: `dune build @test/test_search.exe && dune exec test/test_search.exe -- test`
Expected: PASS.

- [ ] **Step 6: Run the full suite**

Run: `scripts/run-tests.sh -q`
Expected: all passing.

- [ ] **Step 7: Commit**

```bash
git add lib/typecheck/typecheck.ml test/test_search.ml
git commit -m "typecheck: record qualified type-annotation references for forge search --callers"
```

---

## Task 5: Extend `Search.index` with a `references` table

**Files:**
- Modify: `lib/search/search.ml` (`index` type, `build_stdlib_index`, `build_index_from_dirs`, `merge_indices`, JSON (de)serialization, `search_combined`, new formatters)
- Modify: `test/test_search.ml`

**Interfaces:**
- Consumes: `TC.check_module_with_refs`, `TC.ref_record` (Task 2/3/4).
- Produces: `index.references : (string, (string * string * int * string) list) Hashtbl.t` (callee qualified name -> `(caller, file, line, kind_string)` list); `Search.search_combined`'s new `?callers:string` param returning `(string * string * int * string) list`; `Search.format_references_plain`/`format_references_colored`.

- [ ] **Step 1: Write the failing test**

```ocaml
let test_index_references_roundtrip () =
  let refs : Search.ref_entry list = [
    { Search.callee = "A.helper"; caller = "A.main"; kind = "call"; file = "a.march"; line = 3 };
  ] in
  let idx = Search.{ (sample_index ()) with references = Search.references_of_list refs } in
  let json = Search.index_to_json idx in
  let idx2 = Search.index_from_json json in
  let looked_up = Search.callers_of idx2 "A.helper" in
  Alcotest.(check int) "one caller round-tripped" 1 (List.length looked_up)
```

Add to `test/test_search.ml`, registered in the Alcotest runner.

- [ ] **Step 2: Run test to verify it fails**

Run: `dune build @test/test_search.exe && dune exec test/test_search.exe -- test`
Expected: FAIL — `Search.ref_entry`/`references_of_list`/`callers_of` unbound.

- [ ] **Step 3: Add the `ref_entry` type and `index.references` field**

In `lib/search/search.ml`, near the existing `type entry = { ... }` (line ~21-30):

```ocaml
type ref_entry = {
  callee : string;   (* qualified name of the referenced declaration *)
  caller : string;   (* qualified name of the enclosing declaration *)
  kind   : string;   (* "call" | "ctor" | "type" *)
  file   : string;
  line   : int;
}
```

In `type index = { ... }` (line ~33-36), add:

```ocaml
type index = {
  entries      : entry list;
  references   : (string, ref_entry list) Hashtbl.t;
  version      : int;
  generated_at : string;
}
```

- [ ] **Step 4: Add helpers to build/query the references table**

Immediately after the `type index` block:

```ocaml
let ref_kind_to_string = function
  | `Call    -> "call"
  | `Ctor    -> "ctor"
  | `TypeRef -> "type"

(** Group a flat list of ref_entry into the callee-keyed table [index.references] expects. *)
let references_of_list (refs : ref_entry list) : (string, ref_entry list) Hashtbl.t =
  let tbl : (string, ref_entry list) Hashtbl.t = Hashtbl.create 64 in
  List.iter (fun (r : ref_entry) ->
      let existing = Option.value ~default:[] (Hashtbl.find_opt tbl r.callee) in
      Hashtbl.replace tbl r.callee (r :: existing)
    ) refs;
  tbl

let callers_of (idx : index) (callee : string) : ref_entry list =
  Option.value ~default:[] (Hashtbl.find_opt idx.references callee)
```

- [ ] **Step 5: Wire `TC.ref_record list` into index construction**

Modify `typecheck_decls` (line 357-362) to also return refs, and thread them through `build_stdlib_index`/`build_index_from_dirs`:

```ocaml
let typecheck_decls (all_decls : Ast.decl list)
    : (Ast.span, TC.ty) Hashtbl.t * ref_entry list =
  let synth : Ast.module_ = {
    mod_name  = { txt = "__stdlib__"; span = Ast.dummy_span };
    mod_decls = all_decls;
  } in
  let (_errors, type_map, tc_refs) = TC.check_module_with_refs synth in
  let refs = List.map (fun (r : TC.ref_record) ->
      { callee = r.callee; caller = r.caller;
        kind = ref_kind_to_string r.ref_kind;
        file = r.ref_file; line = r.ref_line }
    ) tc_refs in
  (type_map, refs)

(** Build a search index from all stdlib files, with typechecker-inferred types. *)
let build_stdlib_index () : index =
  let (decl_lists, source_files) = load_stdlib () in
  let (type_map, refs) = typecheck_decls (List.concat decl_lists) in
  let idx = build_index decl_lists ~source_files ~type_map () in
  { idx with references = references_of_list refs }
```

`build_index_from_dirs` (line 370-381) doesn't currently call `typecheck_decls` at all (it calls `build_index decls ~source_files:paths ()` with no `type_map`, so params/return types come out unresolved for project-dependency-only builds — this is pre-existing behavior, not something this task changes). Update it to also typecheck and attach references, matching `build_stdlib_index`'s new shape:

```ocaml
let build_index_from_dirs (dirs : string list) : index =
  let march_files_in dir = (* unchanged *)
    try
      Sys.readdir dir
      |> Array.to_list
      |> List.filter (fun f -> Filename.check_suffix f ".march")
      |> List.sort String.compare
      |> List.map (Filename.concat dir)
    with Sys_error _ -> []
  in
  let paths = List.concat_map march_files_in dirs in
  let decls = List.map parse_file paths in
  let (type_map, refs) = typecheck_decls (List.concat decls) in
  let idx = build_index decls ~source_files:paths ~type_map () in
  { idx with references = references_of_list refs }
```

Update `merge_indices` (line ~383-385) to merge references too:

```ocaml
let merge_indices (a : index) (b : index) : index =
  let merged = Hashtbl.copy a.references in
  Hashtbl.iter (fun k v ->
      let existing = Option.value ~default:[] (Hashtbl.find_opt merged k) in
      Hashtbl.replace merged k (v @ existing)
    ) b.references;
  { a with entries = a.entries @ b.entries; references = merged }
```

- [ ] **Step 6: Extend JSON (de)serialization (lines 576-596)**

```ocaml
let ref_entry_to_json (r : ref_entry) : Yojson.Basic.t =
  `Assoc [
    "caller", `String r.caller;
    "file",   `String r.file;
    "line",   `Int r.line;
    "kind",   `String r.kind;
  ]

let ref_entry_of_json (callee : string) (j : Yojson.Basic.t) : ref_entry =
  let open Yojson.Basic.Util in
  { callee;
    caller = j |> member "caller" |> to_string;
    file   = j |> member "file"   |> to_string;
    line   = j |> member "line"   |> to_int;
    kind   = j |> member "kind"   |> to_string;
  }

let index_to_json (idx : index) : string =
  let refs_json : Yojson.Basic.t =
    `Assoc (Hashtbl.fold (fun callee entries acc ->
        (callee, `List (List.map ref_entry_to_json entries)) :: acc
      ) idx.references [])
  in
  let j : Yojson.Basic.t = `Assoc [
    "version",      `Int idx.version;
    "generated_at", `String idx.generated_at;
    "entries",      `List (List.map entry_to_json idx.entries);
    "references",   refs_json;
  ] in
  Yojson.Basic.pretty_to_string j

let index_from_json (s : string) : index =
  let open Yojson.Basic.Util in
  let j = Yojson.Basic.from_string s in
  let references =
    match j |> member "references" with
    | `Null -> Hashtbl.create 0  (* old cache predating this field *)
    | refs_json ->
      let tbl = Hashtbl.create 64 in
      (match refs_json with
       | `Assoc kvs ->
         List.iter (fun (callee, entries_json) ->
             let entries = entries_json |> to_list |> List.map (ref_entry_of_json callee) in
             Hashtbl.replace tbl callee entries
           ) kvs
       | _ -> ());
      tbl
  in
  { version      = j |> member "version"      |> to_int;
    generated_at = j |> member "generated_at" |> to_string;
    entries      = j |> member "entries"      |> to_list |> List.map entry_of_json;
    references;
  }
```

Bump the cache version constant used when constructing a fresh index (find the `version = 1` — or similar — literal near `build_index`'s index construction and bump it by one) so a stale on-disk cache from before this change is distinguishable; `--rebuild` (already wired in `cmd_search.ml`) remains the manual way to force a fresh build either way.

- [ ] **Step 7: Add `?callers` to `search_combined` and reference formatters**

```ocaml
(** Resolve [query] (bare or qualified) to every matching entry's qualified
    name, then return their combined caller list. Bare names may match
    entries in more than one module; all matches are merged rather than
    treated as an error, consistent with [search_name]'s existing UX. *)
let search_callers (idx : index) (query : string) : ref_entry list =
  let qualified_of (e : entry) =
    if e.module_name = "" then e.name else e.module_name ^ "." ^ e.name
  in
  let candidates =
    if String.contains query '.' then [query]
    else
      idx.entries
      |> List.filter (fun e -> e.name = query)
      |> List.map qualified_of
  in
  List.concat_map (callers_of idx) candidates

let format_ref_entry (r : ref_entry) : string =
  Printf.sprintf "%s  %s:%d  (%s)" r.caller r.file r.line r.kind

let format_references_plain (refs : ref_entry list) : unit =
  if refs = [] then print_endline "no references found"
  else List.iter (fun r -> print_endline (format_ref_entry r)) refs

let format_references_colored (refs : ref_entry list) : unit =
  if refs = [] then Printf.printf "\027[2mno references found\027[0m\n"
  else begin
    let bold = "\027[1m" and dim = "\027[2m" and reset = "\027[0m" in
    List.iter (fun r ->
        Printf.printf "%s%s%s  %s%s:%d%s  %s(%s)%s\n"
          bold r.caller reset dim r.file r.line reset dim r.kind reset
      ) refs
  end
```

(`search_combined` itself is left untouched — `--callers` is a distinct query mode from name/type/doc search, so `cmd_search.ml` will call `search_callers` directly rather than folding it into `search_combined`'s scoring pipeline, which returns a different result shape.)

- [ ] **Step 8: Run test to verify it passes**

Run: `dune build @test/test_search.exe && dune exec test/test_search.exe -- test`
Expected: PASS for `test_index_references_roundtrip`.

- [ ] **Step 9: Run the full suite**

Run: `scripts/run-tests.sh -q`
Expected: all passing.

- [ ] **Step 10: Commit**

```bash
git add lib/search/search.ml test/test_search.ml
git commit -m "search: add references table to the search index (call/ctor/type)"
```

---

## Task 6: `forge search --callers` CLI flag

**Files:**
- Modify: `forge/lib/cmd_search.ml`
- Modify: whichever file parses `forge search`'s CLI args and dispatches to `Cmd_search.run` (find it with `forge search --type` as the anchor: `grep -rn -- '--type' forge/bin forge/lib` before editing, since this plan's investigation didn't trace the arg-parser file directly — follow the exact pattern already used for `--type`/`--doc`).

**Interfaces:**
- Consumes: `Search.search_callers`, `Search.format_references_plain`, `Search.format_references_colored` (Task 5).

- [ ] **Step 1: Locate the CLI arg definition for `--type`/`--doc`**

Run: `grep -rn -- '"--type"\|"--doc"' forge/ | grep -v _build`
Read the matched file's arg-parsing block in full before editing, so the new `--callers` flag follows the exact same option-definition pattern (flag name, help text, how it's threaded into `Cmd_search.run`'s labeled arguments).

- [ ] **Step 2: Add `~callers` to `Cmd_search.run`'s signature (`forge/lib/cmd_search.ml:127`)**

```ocaml
let run ~query ~type_sig ~doc_query ~callers ~limit ~as_json ~plain ~rebuild () =
```

- [ ] **Step 3: Branch on `callers` before the existing search dispatch**

Replace the body from `match load_or_build_index ...` (line 138) onward:

```ocaml
  match load_or_build_index ~verbose:false ~root all_deps with
  | Error msg -> Printf.eprintf "error: %s\n%!" msg; exit 1
  | Ok idx ->
    if String.length callers > 0 then begin
      let refs = Search.search_callers idx callers in
      if as_json then begin
        let j : Yojson.Basic.t = `List (List.map (fun (r : Search.ref_entry) ->
            `Assoc [ "caller", `String r.Search.caller; "file", `String r.Search.file;
                     "line", `Int r.Search.line; "kind", `String r.Search.kind ]
          ) refs) in
        print_string (Yojson.Basic.pretty_to_string j); print_newline ()
      end else if plain || not (Unix.isatty Unix.stdout) then
        Search.format_references_plain refs
      else
        Search.format_references_colored refs
    end else begin
      let name_q     = if String.length query    > 0 then Some query    else None in
      let type_q     = if String.length type_sig > 0 then Some type_sig else None in
      let doc_q      = if String.length doc_query > 0 then Some doc_query else None in
      let results =
        if name_q = None && type_q = None && doc_q = None then
          (Printf.printf "index contains %d entries (stdlib + deps)\n%!"
             (List.length idx.Search.entries);
           [])
        else
          Search.search_combined idx ?name:name_q ?type_sig:type_q ?doc_query:doc_q ()
      in
      print_results ~as_json ~plain ~limit results
    end
```

- [ ] **Step 4: Update the caller of `Cmd_search.run` to pass `~callers`**

In the file found in Step 1, add a `--callers` string-arg definition (default `""`, same shape as `--type`) and pass it through as `~callers` in the call to `Cmd_search.run`.

- [ ] **Step 5: Build and smoke-test manually**

Run: `dune build forge/bin/main.exe`
Expected: builds clean.

Run (from a directory with a `forge.toml`, or any march project):
```bash
cd /tmp && mkdir -p callers_smoke && cd callers_smoke && \
  echo 'mod A do
  fn helper() do 1 end
  fn main() do helper() end
end' > a.march && \
  /Users/80197052/code/march/_build/default/forge/bin/main.exe search --callers helper --rebuild
```
Expected: prints one reference line for `A.main` at `a.march:3` (adjust the exact `forge` invocation to match whatever `forge/bin/main.exe`'s actual entry point/command name is, discovered in Step 1 — this is a manual smoke check, not the automated test, which is Task 7).

- [ ] **Step 6: Commit**

```bash
git add forge/lib/cmd_search.ml
git commit -m "forge: add --callers flag to forge search"
```

(Also `git add` whichever CLI arg-parser file was modified in Step 4 — its exact path is discovered in Step 1.)

---

## Task 7: End-to-end tests + ambiguous-ctor regression + docs/changelog

**Files:**
- Modify: `test/test_search.ml`
- Modify: `specs/todos/` / `specs/progress/` (per CLAUDE.md: move the filed todo to progress)
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: everything from Tasks 1-6.

- [ ] **Step 1: Write the ambiguous-ctor regression test**

This directly guards the class of bug on record in project memory (`project_ambiguous_ctor_current_module.md` — stdlib ADTs sharing a bare ctor name at different tags miscompiled because `lookup_ctor` didn't prefer the current module; the fix made `lookup_ctor` module-aware). This test proves reference-tracking inherits that same current-module preference rather than reintroducing the bug at the reference layer.

```ocaml
let test_ambiguous_ctor_ref_prefers_current_module () =
  let refs = check_refs [
    ("x.march", "X", "mod X do\n  type Status = Active | Done\nend\n");
    ("y.march", "Y",
     "mod Y do\n  type Status = Active | Done\n  fn main() do Active end\nend\n");
  ] in
  let ctors = List.filter (fun (r : TC.ref_record) -> r.ref_kind = `Ctor) refs in
  Alcotest.(check bool) "Y.main's Active resolves to Y.Active, not X.Active" true
    (List.exists (fun (r : TC.ref_record) ->
         r.callee = "Y.Active" && r.caller = "Y.main") ctors);
  Alcotest.(check bool) "no false X.Active reference from Y.main" false
    (List.exists (fun (r : TC.ref_record) ->
         r.callee = "X.Active" && r.caller = "Y.main") ctors)
```

- [ ] **Step 2: Write the "no references" (empty result) test**

```ocaml
let test_no_references_is_empty_not_error () =
  let refs = check_refs [
    ("a.march", "A", "mod A do\n  fn unused() do 1 end\n  fn main() do 2 end\nend\n");
  ] in
  let tbl = Search.references_of_list
      (List.map (fun (r : TC.ref_record) ->
           { Search.callee = r.callee; caller = r.caller;
             kind = Search.ref_kind_to_string r.ref_kind;
             file = r.ref_file; line = r.ref_line })
          refs) in
  Alcotest.(check int) "unused fn has zero recorded callers" 0
    (List.length (Search.callers_of { (sample_index ()) with Search.references = tbl } "A.unused"))
```

- [ ] **Step 3: Register all new tests in the Alcotest runner and run them**

Add every `test_*` function written in Tasks 2-4 and 7 to a `"references"` test group at the bottom of `test/test_search.ml`, following the file's existing `Alcotest.run "search" [ "levenshtein", [...]; ...; "references", [...] ]` structure.

Run: `dune build @test/test_search.exe && dune exec test/test_search.exe -- test`
Expected: PASS for all reference tests, including the two new ones in this task.

- [ ] **Step 4: Run the full project suite**

Run: `scripts/run-tests.sh` (full, not `-q` — this is the pre-merge full run per CLAUDE.md)
Expected: all passing, no regressions elsewhere.

- [ ] **Step 5: Update specs/todos and specs/progress**

Check whether a todo file already covers this (search `specs/todos/` for "reverse" or "callers" or "search"); if one exists, `git mv` it to `specs/progress/` with today's date. If none exists (this feature was designed fresh in this session, not from a pre-filed todo), create `specs/progress/2026-08-01-forge-search-callers-reverse-reference-search.md` directly, briefly describing what shipped (per the `specs/progress/README.md` convention — read that file's format before writing, since this plan doesn't reproduce its exact template).

- [ ] **Step 6: Update CHANGELOG.md**

Add under `## [Unreleased]` → `### Added`:

```
- `forge search --callers NAME`: reverse-reference search — find every resolved call, constructor use, or qualified type reference to a declaration, using the typechecker's own name resolution (not textual matching).
```

- [ ] **Step 7: Final commit**

```bash
git add test/test_search.ml specs/progress/ CHANGELOG.md
git commit -m "search: add --callers regression tests, changelog, and progress entry"
```

(If a `specs/todos/` file was moved via `git mv` in Step 5, that rename is already staged by the `git mv` itself — include it in this same commit rather than a separate one.)
