# LSP Feature Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add five new LSP features to march-lsp: doc-string hover, find references, rename symbol, signature help, and code actions (make-linear, pattern exhaustion quickfix).

**Architecture:** All analysis logic lives in `lsp/lib/analysis.ml` (new fields on `Analysis.t`, new query functions); protocol wiring lives in `lsp/lib/server.ml` (new capability declarations and request handlers); all features are covered by unit tests in `lsp/test/test_lsp.ml` that call analysis functions directly without a running server.

**Tech Stack:** OCaml 5.3, Dune, Alcotest (tests), Linol/Linol-lwt (LSP protocol), March compiler internals (march_ast, march_typecheck, march_errors, march_desugar, march_parser, march_lexer).

---

## File Map

| File | Role | Change type |
|------|------|-------------|
| `lsp/lib/analysis.ml` | Analysis pipeline + query layer | Modify — new fields, collection passes, query functions |
| `lsp/lib/server.ml` | LSP protocol handler | Modify — new capabilities + request handlers |
| `lsp/test/test_lsp.ml` | Unit test suite | Modify — new test sections appended |

No new files needed. All five features touch only these three files.

---

## Build & Test Command

```bash
dune runtest lsp/
```

Expected output when all tests pass: every test name followed by `OK`.

---

## Task 1 — Doc Strings on Hover: analysis layer

**Files:**
- Modify: `lsp/lib/analysis.ml`
- Test: `lsp/test/test_lsp.ml`

### Background

`Ast.fn_def.fn_doc : string option` holds the optional doc string for each
function (set by `doc "..." fn foo ...`). The analysis layer currently ignores
it. We need to collect it into a lookup table so hover can display it.

Only `fn_def` carries a doc field today. `DType`, `DLet`, and `DInterface` do
not, so doc lookup is function-name-only for now.

### Step-by-step

- [ ] **1.1 Write the failing tests**

Append to `lsp/test/test_lsp.ml`:

```ocaml
(* ------------------------------------------------------------------ *)
(* 10. Doc strings                                                     *)
(* ------------------------------------------------------------------ *)

let test_doc_for_documented_fn () =
  let src = {|
mod M do
  doc "Adds two integers together."
  fn add(x: Int, y: Int): Int do
    x + y
  end

  fn main() do
    add(1, 2)
  end
end
|} in
  let a = analyse src in
  (* doc_for "add" returns the doc string *)
  Alcotest.(check (option string))
    "doc for add"
    (Some "Adds two integers together.")
    (An.doc_for a "add")

let test_doc_for_undocumented_fn () =
  let src = {|
mod M do
  fn no_doc(x: Int): Int do x end
end
|} in
  let a = analyse src in
  Alcotest.(check (option string))
    "no doc returns None"
    None
    (An.doc_for a "no_doc")

let test_doc_for_unknown_name () =
  let src = {|mod M do fn f() do 1 end end|} in
  let a = analyse src in
  Alcotest.(check (option string))
    "unknown name returns None"
    None
    (An.doc_for a "does_not_exist")

let test_doc_name_at_cursor () =
  let src = {|
mod M do
  doc "Multiply."
  fn mul(a: Int, b: Int): Int do a * b end

  fn main() do
    mul(2, 3)
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "mul(2" in
  (* hovering on the call site "mul" should resolve the doc string *)
  Alcotest.(check (option string))
    "doc at call site"
    (Some "Multiply.")
    (An.doc_name_at a ~line ~character:col)

let test_doc_triple_quoted () =
  let src = {|
mod M do
  doc """
  Multi-line doc.
  Second line.
  """
  fn greet() do "hi" end
end
|} in
  let a = analyse src in
  Alcotest.(check bool)
    "triple-quoted doc non-empty"
    true
    (match An.doc_for a "greet" with
     | Some s -> String.length s > 0
     | None   -> false)
```

Also add to the `let () = Alcotest.run` block at the bottom of the file:

```ocaml
    "doc strings", [
      "documented fn",    `Quick, test_doc_for_documented_fn;
      "undocumented fn",  `Quick, test_doc_for_undocumented_fn;
      "unknown name",     `Quick, test_doc_for_unknown_name;
      "at call-site cursor", `Quick, test_doc_name_at_cursor;
      "triple-quoted",    `Quick, test_doc_triple_quoted;
    ];
```

- [ ] **1.2 Run tests — verify they fail**

```bash
dune runtest lsp/
```

Expected: compilation error — `An.doc_for` and `An.doc_name_at` are undefined.

- [ ] **1.3 Add `doc_map` field to `Analysis.t`**

In `lsp/lib/analysis.ml`, add to the `type t` record (after the `actors` field):

```ocaml
  doc_map     : (string, string) Hashtbl.t;
  (** Function name → doc string (from [fn_doc] field). *)
```

- [ ] **1.4 Populate `doc_map` in `collect_decl`**

In `collect_decl`, extend the `Ast.DFn` branch (currently lines 145–149):

```ocaml
  | Ast.DFn (fn, _) ->
    add_def fn.fn_name.txt fn.fn_name.span;
    (match fn.fn_doc with
     | Some doc -> Hashtbl.replace doc_map fn.fn_name.txt doc
     | None -> ());
    List.iter (fun (cl : Ast.fn_clause) ->
        collect_expr ~def_map ~use_map cl.fc_body
      ) fn.fn_clauses
```

The `doc_map` parameter must be threaded through `collect_decl` (add
`~doc_map` analogously to `~def_map`).

Update the `collect_decl` signature:

```ocaml
let rec collect_decl ~def_map ~use_map ~doc_map ~actors_tbl ?(prefix = "") (decl : Ast.decl) =
```

Update every recursive call inside `collect_decl` (the `DMod` branch) to also
pass `~doc_map`.

- [ ] **1.5 Add query functions `doc_for` and `doc_name_at`**

At the end of the query-helpers section of `analysis.ml`:

```ocaml
let doc_for (a : t) (name : string) : string option =
  Hashtbl.find_opt a.doc_map name

(** Return the doc string for the function whose name the cursor sits on,
    by resolving the name via [use_map] and then looking up [doc_map]. *)
let doc_name_at (a : t) ~line ~character : string option =
  let name_opt =
    Hashtbl.fold (fun sp name found ->
        match found with
        | Some _ -> found
        | None   ->
          if Pos.span_contains sp ~line ~character then Some name
          else None
      ) a.use_map None
  in
  (* also check def_map in case cursor is on the definition itself *)
  let name_opt =
    match name_opt with
    | Some _ -> name_opt
    | None ->
      Hashtbl.fold (fun name sp found ->
          match found with
          | Some _ -> found
          | None   ->
            if Pos.span_contains sp ~line ~character then Some name
            else None
        ) a.def_map None
  in
  match name_opt with
  | None -> None
  | Some name -> doc_for a name
```

- [ ] **1.6 Wire `doc_map` into the `analyse` function**

In the `analyse` function, create the table and pass it:

```ocaml
    let doc_map     = Hashtbl.create 16 in
    (* ... existing def_map / use_map / actors_tbl creation ... *)
    List.iter (collect_decl ~def_map ~use_map ~doc_map ~actors_tbl) user_decls;
```

And include `doc_map` in the returned record:

```ocaml
    { src; filename; type_map; def_map; use_map; doc_map;
      vars = ...; ... }
```

Also initialise `doc_map = Hashtbl.create 0` in `make_empty_with`.

- [ ] **1.7 Run tests — verify they pass**

```bash
dune runtest lsp/
```

Expected: all 5 doc-string tests pass, zero regressions.

- [ ] **1.8 Commit**

```bash
git add lsp/lib/analysis.ml lsp/test/test_lsp.ml
git commit -m "feat(lsp): collect fn doc strings into doc_map, add doc_for/doc_name_at queries"
```

---

## Task 2 — Doc Strings on Hover: server wiring

**Files:**
- Modify: `lsp/lib/server.ml`

- [ ] **2.1 Write the failing test**

This is a server-integration concern; the analysis tests from Task 1 already
cover correctness. Add one integration-style test that verifies the hover
response includes both type and doc:

```ocaml
let test_hover_includes_doc () =
  let src = {|
mod M do
  doc "Returns the integer unchanged."
  fn identity(x: Int): Int do x end

  fn main() do
    identity(42)
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "identity(42" in
  (* type_at should return Some "Int -> Int" or similar *)
  let ty = An.type_at a ~line ~character:col in
  let doc = An.doc_name_at a ~line ~character:col in
  Alcotest.(check bool) "type present"  true (ty  <> None);
  Alcotest.(check bool) "doc present"   true (doc <> None)
```

Add to the `"doc strings"` Alcotest section:

```ocaml
      "hover has both type and doc", `Quick, test_hover_includes_doc;
```

- [ ] **2.2 Run test — verify it fails** (`doc_name_at` exists after Task 1, but confirm both fields are present)

```bash
dune runtest lsp/
```

- [ ] **2.3 Update `on_req_hover` in `server.ml`**

Extend the hover handler to append a doc section when available. Replace
the existing `ty_hover` computation (lines ~188–203) with:

```ocaml
    method on_req_hover ~notify_back:_ ~id:_ ~uri ~pos ~workDoneToken:_ _doc =
      let open Lsp.Types in
      let (line, character) = Pos.lsp_pos_to_pair pos in
      let result =
        match get_analysis uri with
        | None -> None
        | Some a ->
          let ty_hover =
            Analysis.type_at a ~line ~character
            |> Option.map (fun ty_str ->
                let doc_section =
                  match Analysis.doc_name_at a ~line ~character with
                  | None     -> ""
                  | Some doc -> Printf.sprintf "\n\n---\n%s" doc
                in
                let value =
                  Printf.sprintf "```march\n%s\n```%s" ty_str doc_section
                in
                let md = MarkupContent.create
                  ~kind:MarkupKind.Markdown ~value in
                Hover.create ~contents:(`MarkupContent md) ())
          in
          (match ty_hover with
           | Some _ -> ty_hover
           | None ->
             Analysis.actor_info_at a ~line ~character
             |> Option.map (fun info ->
                 let md = MarkupContent.create
                   ~kind:MarkupKind.Markdown ~value:info in
                 Hover.create ~contents:(`MarkupContent md) ()))
      in
      Lwt.return result
```

- [ ] **2.4 Run tests**

```bash
dune runtest lsp/
```

- [ ] **2.5 Commit**

```bash
git add lsp/lib/server.ml lsp/test/test_lsp.ml
git commit -m "feat(lsp): show doc strings in hover responses"
```

---

## Task 3 — Find References: analysis layer

**Files:**
- Modify: `lsp/lib/analysis.ml`
- Test: `lsp/test/test_lsp.ml`

### Background

`use_map : (Ast.span, string) Hashtbl.t` maps each use-site span to the
variable name. To answer "all references to X", we need the inverse: name → all
spans. We build `refs_map` as the inverted index during `analyse`.

### Step-by-step

- [ ] **3.1 Write the failing tests**

```ocaml
(* ------------------------------------------------------------------ *)
(* 11. Find references                                                 *)
(* ------------------------------------------------------------------ *)

let test_references_empty_for_literal () =
  let src = {|mod M do fn f() do 42 end end|} in
  let a = analyse src in
  let (line, col) = pos_of src "42" in
  Alcotest.(check int)
    "no refs for literal"
    0
    (List.length (An.references_at a ~include_declaration:false ~line ~character:col))

let test_references_finds_uses () =
  let src = {|
mod M do
  fn double(n: Int): Int do n + n end
  fn main() do
    double(1)
    double(2)
  end
end
|} in
  let a = analyse src in
  (* Position cursor on one of the call sites *)
  let (line, col) = pos_of src "double(1" in
  let refs = An.references_at a ~include_declaration:false ~line ~character:col in
  (* There are two call-site uses of "double" *)
  Alcotest.(check bool)
    "at least 2 use refs"
    true
    (List.length refs >= 2)

let test_references_include_declaration () =
  let src = {|
mod M do
  fn sq(n: Int): Int do n * n end
  fn main() do sq(3) end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "sq(3" in
  let with_decl    = An.references_at a ~include_declaration:true  ~line ~character:col in
  let without_decl = An.references_at a ~include_declaration:false ~line ~character:col in
  Alcotest.(check bool)
    "include_declaration adds one entry"
    true
    (List.length with_decl = List.length without_decl + 1)

let test_references_local_variable () =
  let src = {|
mod M do
  fn f() do
    let x = 10
    x + x
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "x + x" in
  let refs = An.references_at a ~include_declaration:false ~line ~character:col in
  (* two uses of x in the expression *)
  Alcotest.(check bool) "two uses of x" true (List.length refs >= 2)

let test_references_no_cross_contamination () =
  (* Two different names — refs for one should not contain the other *)
  let src = {|
mod M do
  fn a() do 1 end
  fn b() do 2 end
  fn main() do a() end
end
|} in
  let a_an = analyse src in
  let (line, col) = pos_of src "a()" in
  let refs = An.references_at a_an ~include_declaration:false ~line ~character:col in
  let all_same_name =
    List.for_all (fun (loc : Lsp.Types.Location.t) ->
        (* Very rough check: the range is non-zero length *)
        loc.range.start.character < loc.range.end_.character
      ) refs
  in
  Alcotest.(check bool) "all refs are real ranges" true all_same_name
```

Add to the `Alcotest.run` call:

```ocaml
    "find references", [
      "literal has no refs",       `Quick, test_references_empty_for_literal;
      "finds multiple uses",        `Quick, test_references_finds_uses;
      "include_declaration flag",   `Quick, test_references_include_declaration;
      "local variable",             `Quick, test_references_local_variable;
      "no cross-contamination",     `Quick, test_references_no_cross_contamination;
    ];
```

- [ ] **3.2 Run tests — verify they fail** (compilation error: `An.references_at` undefined)

- [ ] **3.3 Add `refs_map` field to `Analysis.t`**

```ocaml
  refs_map    : (string, Ast.span list) Hashtbl.t;
  (** Inverted index: variable name → all use-site spans. *)
```

- [ ] **3.4 Build `refs_map` in `analyse` by inverting `use_map`**

After the `List.iter (collect_decl ...)` call:

```ocaml
    let refs_map = Hashtbl.create 64 in
    Hashtbl.iter (fun sp name ->
        let existing =
          match Hashtbl.find_opt refs_map name with
          | Some lst -> lst
          | None     -> []
        in
        Hashtbl.replace refs_map name (sp :: existing)
      ) use_map;
```

Include `refs_map` in the returned record and in `make_empty_with`
(`refs_map = Hashtbl.create 0`).

- [ ] **3.5 Add `references_at` query function**

```ocaml
let references_at (a : t) ~include_declaration ~line ~character
    : Lsp.Types.Location.t list =
  (* Resolve which name the cursor is on — check use_map first, then def_map *)
  let name_opt =
    let from_use =
      Hashtbl.fold (fun sp name found ->
          match found with
          | Some _ -> found
          | None   ->
            if Pos.span_contains sp ~line ~character then Some name
            else None
        ) a.use_map None
    in
    match from_use with
    | Some _ -> from_use
    | None ->
      Hashtbl.fold (fun name sp found ->
          match found with
          | Some _ -> found
          | None   ->
            if Pos.span_contains sp ~line ~character then Some name
            else None
        ) a.def_map None
  in
  match name_opt with
  | None -> []
  | Some name ->
    let use_spans =
      match Hashtbl.find_opt a.refs_map name with
      | Some spans -> spans
      | None       -> []
    in
    let all_spans =
      if include_declaration then
        match Hashtbl.find_opt a.def_map name with
        | Some def_sp -> def_sp :: use_spans
        | None        -> use_spans
      else
        use_spans
    in
    List.filter_map (fun (sp : Ast.span) ->
        if sp = Ast.dummy_span then None
        else
          let path =
            if sp.Ast.file = "" || sp.Ast.file = "<unknown>" then a.filename
            else sp.Ast.file
          in
          let uri   = Lsp.Types.DocumentUri.of_path path in
          let range = Pos.span_to_lsp_range sp in
          Some (Lsp.Types.Location.create ~uri ~range)
      ) all_spans
```

- [ ] **3.6 Run tests — verify they pass**

```bash
dune runtest lsp/
```

- [ ] **3.7 Commit**

```bash
git add lsp/lib/analysis.ml lsp/test/test_lsp.ml
git commit -m "feat(lsp): add refs_map and references_at for find-references"
```

---

## Task 4 — Find References: server wiring

**Files:**
- Modify: `lsp/lib/server.ml`

- [ ] **4.1 Declare the capability via `config_modify_capabilities`**

> **linol note:** The linol base class does **not** expose virtual hooks for
> `textDocument/references`, `textDocument/rename`, or
> `textDocument/signatureHelp`. All three must be wired via
> `on_unknown_request` (JSON dispatch) and their capabilities injected inside
> the existing `config_modify_capabilities` override.

Extend the `config_modify_capabilities` method (already present for
semantic tokens) to also set `referencesProvider`:

```ocaml
    method config_modify_capabilities caps =
      let open Lsp.Types in
      (* ... existing semantic-tokens legend setup ... *)
      { caps with
        ServerCapabilities.semanticTokensProvider =
          Some (`SemanticTokensOptions sem_tokens);
        ServerCapabilities.referencesProvider =
          Some (`Bool true) }
```

- [ ] **4.2 Dispatch `textDocument/references` via `on_unknown_request`**

Inside the existing `on_unknown_request` handler, add a branch before the
final `else Lwt.fail_with …`:

```ocaml
      end else if meth = "textDocument/references" then begin
        (* Parse params: { textDocument: { uri }, position: { line, character },
                           context: { includeDeclaration } } *)
        let uri_opt, pos_opt, include_decl =
          match params with
          | Some (`Assoc fields) ->
            let uri_opt =
              match List.assoc_opt "textDocument" fields with
              | Some (`Assoc td) ->
                (match List.assoc_opt "uri" td with
                 | Some (`String u) ->
                   let path =
                     if String.length u >= 7 && String.sub u 0 7 = "file://"
                     then String.sub u 7 (String.length u - 7) else u
                   in
                   Some (Lsp.Types.DocumentUri.of_path path)
                 | _ -> None)
              | _ -> None
            in
            let pos_opt =
              match List.assoc_opt "position" fields with
              | Some (`Assoc p) ->
                let line = match List.assoc_opt "line" p with
                  | Some (`Int n) -> n | _ -> 0 in
                let character = match List.assoc_opt "character" p with
                  | Some (`Int n) -> n | _ -> 0 in
                Some (line, character)
              | _ -> None
            in
            let include_decl =
              match List.assoc_opt "context" fields with
              | Some (`Assoc ctx) ->
                (match List.assoc_opt "includeDeclaration" ctx with
                 | Some (`Bool b) -> b | _ -> false)
              | _ -> false
            in
            (uri_opt, pos_opt, include_decl)
          | _ -> (None, None, false)
        in
        let locs =
          match uri_opt, pos_opt with
          | Some uri, Some (line, character) ->
            (match get_analysis uri with
             | None   -> []
             | Some a ->
               Analysis.references_at a ~include_declaration:include_decl
                 ~line ~character)
          | _ -> []
        in
        let json_locs = List.map (fun (loc : Lsp.Types.Location.t) ->
            `Assoc [
              ("uri",   `String (Lsp.Types.DocumentUri.to_string loc.uri));
              ("range", `Assoc [
                ("start", `Assoc [
                  ("line",      `Int loc.range.start.line);
                  ("character", `Int loc.range.start.character)]);
                ("end",   `Assoc [
                  ("line",      `Int loc.range.end_.line);
                  ("character", `Int loc.range.end_.character)])])
            ]
          ) locs in
        Lwt.return (`List json_locs)

- [ ] **4.3 Run tests and build**

```bash
dune build && dune runtest lsp/
```

- [ ] **4.4 Commit**

```bash
git add lsp/lib/server.ml
git commit -m "feat(lsp): wire textDocument/references handler"
```

---

## Task 5 — Rename Symbol: analysis layer + server

**Files:**
- Modify: `lsp/lib/analysis.ml`
- Modify: `lsp/lib/server.ml`
- Test: `lsp/test/test_lsp.ml`

### Background

Rename re-uses `refs_map` (all uses) and `def_map` (the definition site) to
produce a `WorkspaceEdit` replacing every occurrence of the old name with the
new one. Since analysis is per-file, rename is scoped to the open document.

### Step-by-step

- [ ] **5.1 Write the failing tests**

```ocaml
(* ------------------------------------------------------------------ *)
(* 12. Rename symbol                                                   *)
(* ------------------------------------------------------------------ *)

let test_rename_no_edits_for_literal () =
  let src = {|mod M do fn f() do 99 end end|} in
  let a = analyse src in
  let (line, col) = pos_of src "99" in
  let edits = An.rename_at a ~line ~character:col ~new_name:"foo" in
  Alcotest.(check int) "no edits for literal" 0 (List.length edits)

let test_rename_produces_edits_for_def_and_uses () =
  let src = {|
mod M do
  fn calc(n: Int): Int do n + 1 end
  fn main() do
    calc(10)
    calc(20)
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "calc(10" in
  let edits = An.rename_at a ~line ~character:col ~new_name:"compute" in
  (* definition + 2 call sites = 3 edits minimum *)
  Alcotest.(check bool)
    "at least 3 edits"
    true
    (List.length edits >= 3)

let test_rename_new_name_in_edits () =
  let src = {|
mod M do
  fn old_name(x: Int): Int do x end
  fn main() do old_name(5) end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "old_name(5" in
  let edits = An.rename_at a ~line ~character:col ~new_name:"new_name" in
  let all_new_name =
    List.for_all (fun (e : Lsp.Types.TextEdit.t) ->
        e.newText = "new_name"
      ) edits
  in
  Alcotest.(check bool) "all edits contain new_name" true all_new_name

let test_rename_does_not_rename_other_names () =
  let src = {|
mod M do
  fn alpha() do 1 end
  fn beta()  do 2 end
  fn main()  do alpha() end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "alpha()" in
  let edits = An.rename_at a ~line ~character:col ~new_name:"gamma" in
  (* None of the edits should span a range that covers "beta" *)
  let no_beta =
    List.for_all (fun (e : Lsp.Types.TextEdit.t) ->
        e.newText <> "beta"
      ) edits
  in
  Alcotest.(check bool) "beta untouched" true no_beta
```

Add to `Alcotest.run`:

```ocaml
    "rename symbol", [
      "literal produces no edits",    `Quick, test_rename_no_edits_for_literal;
      "def + uses all renamed",        `Quick, test_rename_produces_edits_for_def_and_uses;
      "new name appears in all edits", `Quick, test_rename_new_name_in_edits;
      "other names untouched",         `Quick, test_rename_does_not_rename_other_names;
    ];
```

- [ ] **5.2 Run tests — verify compilation fails** (`An.rename_at` undefined)

- [ ] **5.3 Add `rename_at` query function to `analysis.ml`**

```ocaml
(** Return a flat list of [TextEdit.t] replacing every occurrence of the
    symbol at the cursor with [new_name], including its definition site. *)
let rename_at (a : t) ~line ~character ~new_name
    : Lsp.Types.TextEdit.t list =
  let locs =
    references_at a ~include_declaration:true ~line ~character
  in
  List.map (fun (loc : Lsp.Types.Location.t) ->
      Lsp.Types.TextEdit.create ~range:loc.range ~newText:new_name
    ) locs
```

- [ ] **5.4 Run tests — verify they pass**

```bash
dune runtest lsp/
```

- [ ] **5.5 Add rename capability and handler to `server.ml`**

Add `renameProvider` to `config_modify_capabilities` (same method as
references — add it to the capability record alongside `referencesProvider`):

```ocaml
        ServerCapabilities.renameProvider =
          Some (`Bool true);
```

Dispatch `textDocument/rename` via `on_unknown_request`, as a new branch
alongside references:

```ocaml
      end else if meth = "textDocument/rename" then begin
        let uri_opt, pos_opt, new_name =
          match params with
          | Some (`Assoc fields) ->
            let uri_opt =
              match List.assoc_opt "textDocument" fields with
              | Some (`Assoc td) ->
                (match List.assoc_opt "uri" td with
                 | Some (`String u) ->
                   let path = if String.length u >= 7 &&
                                  String.sub u 0 7 = "file://"
                               then String.sub u 7 (String.length u - 7) else u
                   in Some (Lsp.Types.DocumentUri.of_path path)
                 | _ -> None)
              | _ -> None
            in
            let pos_opt =
              match List.assoc_opt "position" fields with
              | Some (`Assoc p) ->
                let line = match List.assoc_opt "line" p with
                  | Some (`Int n) -> n | _ -> 0 in
                let ch = match List.assoc_opt "character" p with
                  | Some (`Int n) -> n | _ -> 0 in
                Some (line, ch)
              | _ -> None
            in
            let new_name = match List.assoc_opt "newName" fields with
              | Some (`String s) -> s | _ -> ""
            in
            (uri_opt, pos_opt, new_name)
          | _ -> (None, None, "")
        in
        let edit_json =
          match uri_opt, pos_opt with
          | Some uri, Some (line, character) when new_name <> "" ->
            (match get_analysis uri with
             | None   -> `Null
             | Some a ->
               let edits = Analysis.rename_at a ~line ~character ~new_name in
               if edits = [] then `Null
               else
                 (* WorkspaceEdit: { changes: { uri: [TextEdit] } } *)
                 let uri_str = Lsp.Types.DocumentUri.to_string uri in
                 let json_edits = List.map (fun (e : Lsp.Types.TextEdit.t) ->
                     `Assoc [
                       ("newText", `String e.newText);
                       ("range", `Assoc [
                         ("start", `Assoc [
                           ("line",      `Int e.range.start.line);
                           ("character", `Int e.range.start.character)]);
                         ("end",   `Assoc [
                           ("line",      `Int e.range.end_.line);
                           ("character", `Int e.range.end_.character)])])
                     ]) edits in
                 `Assoc [("changes", `Assoc [(uri_str, `List json_edits)])])
          | _ -> `Null
        in
        Lwt.return edit_json

- [ ] **5.6 Build and test**

```bash
dune build && dune runtest lsp/
```

- [ ] **5.7 Commit**

```bash
git add lsp/lib/analysis.ml lsp/lib/server.ml lsp/test/test_lsp.ml
git commit -m "feat(lsp): add rename_at query and textDocument/rename handler"
```

---

## Task 6 — Signature Help: analysis layer

**Files:**
- Modify: `lsp/lib/analysis.ml`
- Test: `lsp/test/test_lsp.ml`

### Background

When the cursor is inside the argument list of a function call — e.g. `foo(a,
|cursor|, c)` — signature help shows the function's parameter types and
highlights the active parameter.

**Collecting call sites:** During `collect_expr`, when we encounter `EApp`,
record the call's span, the function name (when the callee is a simple
`EVar`), and the number of arguments. This gives us a list of `call_site`
records.

**Determining active parameter:** Count how many argument-separator commas
appear in the source text between the opening `(` and the cursor position.
We do this from the raw source string + span info.

**Resolving parameter types:** Look up the function name in `vars` to get its
`scheme`, then walk the `TArrow` chain to extract parameter type strings.

### Step-by-step

- [ ] **6.1 Write the failing tests**

```ocaml
(* ------------------------------------------------------------------ *)
(* 13. Signature help                                                  *)
(* ------------------------------------------------------------------ *)

let test_sig_help_none_outside_call () =
  let src = {|mod M do fn f() do 42 end end|} in
  let a = analyse src in
  Alcotest.(check bool)
    "no sig help outside call"
    true
    (An.signature_help_at a ~line:2 ~character:5 = None)

let test_sig_help_single_param () =
  let src = {|
mod M do
  fn negate(n: Int): Int do 0 - n end
  fn main() do negate(10) end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "negate(10" in
  (* cursor is just inside the opening paren *)
  let sh = An.signature_help_at a ~line ~character:(col + 7) in
  Alcotest.(check bool) "sig help present" true (sh <> None);
  match sh with
  | None -> ()
  | Some (label, params, active_param) ->
    Alcotest.(check bool) "label non-empty"   true (String.length label > 0);
    Alcotest.(check int)  "one param"         1    (List.length params);
    Alcotest.(check int)  "first param active" 0   active_param

let test_sig_help_active_param_index () =
  let src = {|
mod M do
  fn add3(a: Int, b: Int, c: Int): Int do a + b + c end
  fn main() do add3(1, 2, 3) end
end
|} in
  let a = analyse src in
  (* Cursor at '3' — third argument: find ", 3)" which is unique in the source.
     pos_of returns (line, col_of_comma); col+2 is the '3'. *)
  let (line, comma_col) = pos_of src ", 3)" in
  (match An.signature_help_at a ~line ~character:(comma_col + 2) with
   | None -> Alcotest.fail "expected signature help"
   | Some (_, _, active) ->
     Alcotest.(check int) "third param active (index 2)" 2 active)

let test_sig_help_param_labels () =
  let src = {|
mod M do
  fn div(numerator: Int, denominator: Int): Int do
    numerator / denominator
  end
  fn main() do div(10, 2) end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "div(10" in
  (match An.signature_help_at a ~line ~character:(col + 4) with
   | None -> Alcotest.fail "expected sig help"
   | Some (_, params, _) ->
     Alcotest.(check int) "two params" 2 (List.length params);
     (* param labels should contain the type strings *)
     List.iter (fun p ->
         Alcotest.(check bool)
           "param label non-empty"
           true
           (String.length p > 0)
       ) params)

let test_sig_help_not_a_known_function () =
  (* Calling via a variable — we can't resolve the type from vars *)
  let src = {|
mod M do
  fn main() do
    let f = fn x -> x + 1
    f(5)
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "f(5" in
  (* Should return None or a valid sig — either is acceptable, just not crash *)
  let _ = An.signature_help_at a ~line ~character:(col + 2) in
  Alcotest.(check bool) "no crash" true true
```

Add to `Alcotest.run`:

```ocaml
    "signature help", [
      "none outside call",       `Quick, test_sig_help_none_outside_call;
      "single param",            `Quick, test_sig_help_single_param;
      "active param index",      `Quick, test_sig_help_active_param_index;
      "param labels",            `Quick, test_sig_help_param_labels;
      "non-resolvable callee",   `Quick, test_sig_help_not_a_known_function;
    ];
```

- [ ] **6.2 Run — verify compilation failure** (`An.signature_help_at` undefined)

- [ ] **6.3 Add `call_site` type and `call_sites` field to `Analysis.t`**

Add a helper type just before `type t`:

```ocaml
(** A call-site collected from the AST for signature-help queries. *)
type call_site = {
  cs_fn_name  : string option;  (** Name of the callee if it's a plain identifier *)
  cs_span     : Ast.span;       (** Span of the full EApp expression *)
  cs_args     : Ast.expr list;  (** Argument expressions *)
}
```

Add to `type t`:

```ocaml
  call_sites  : call_site list;
  (** All call sites collected for signature-help queries. *)
```

- [ ] **6.4 Collect call sites in `collect_expr`**

Add a mutable accumulator list `call_sites_acc` (a `call_site list ref`) to
the `analyse` function. Pass it into `collect_expr` via a new `~calls`
parameter (analogous to `~def_map`). Update the `collect_expr` signature:

```ocaml
let rec collect_expr ~def_map ~use_map ~calls (expr : Ast.expr) = ...
```

Every recursive call to `collect_expr` inside `collect_expr` must also pass
`~calls`. Likewise, `collect_decl` already calls `collect_expr`; add `~calls`
to every `collect_expr` call site inside `collect_decl`. Update
`collect_decl`'s signature to accept `~calls` and thread it through.

In the `EApp` branch:

```ocaml
  | Ast.EApp (f, args, sp) ->
    let fn_name = match f with
      | Ast.EVar n -> Some n.txt
      | _          -> None
    in
    calls := { cs_fn_name = fn_name; cs_span = sp; cs_args = args } :: !calls;
    collect_expr ~def_map ~use_map ~calls f;
    List.iter (collect_expr ~def_map ~use_map ~calls) args
```

In `analyse`, after `collect_decl` calls:

```ocaml
    let call_sites = !call_sites_acc in
```

Include `call_sites` in the returned record and in `make_empty_with`
(`call_sites = []`).

- [ ] **6.5 Add `signature_help_at` query function**

```ocaml
(** Walk [TArrow] chain to collect stringified parameter types.
    Returns [(param_types, return_type)]. *)
let rec unwrap_arrows (ty : Tc.ty) : string list * string =
  match ty with
  | Tc.TArrow (param, rest) ->
    let (more, ret) = unwrap_arrows rest in
    (Tc.pp_ty param :: more, ret)
  | _                       -> ([], Tc.pp_ty ty)

(** Count the number of top-level commas in [src] between positions
    [from_ofs] (exclusive) and [to_ofs] (exclusive).
    "Top-level" means not inside nested parens/brackets/braces. *)
let count_commas_between src from_ofs to_ofs =
  let depth = ref 0 in
  let count = ref 0 in
  for i = from_ofs to to_ofs - 1 do
    match src.[i] with
    | '(' | '[' | '{' -> incr depth
    | ')' | ']' | '}' -> if !depth > 0 then decr depth
    | ',' when !depth = 0 -> incr count
    | _ -> ()
  done;
  !count

(** Convert 0-indexed (line, character) to a byte offset in [src]. *)
let offset_of_pos src line character =
  let n = String.length src in
  let cur_line = ref 0 in
  let i = ref 0 in
  while !i < n && !cur_line < line do
    if src.[!i] = '\n' then incr cur_line;
    incr i
  done;
  !i + character

(** Return [(signature_label, param_labels, active_param_index)] for the
    innermost call expression that contains the cursor, or [None]. *)
let signature_help_at (a : t) ~line ~character
    : (string * string list * int) option =
  (* Find the smallest call_site span that contains the cursor position *)
  let containing =
    List.fold_left (fun best cs ->
        if Pos.span_contains cs.cs_span ~line ~character then
          match best with
          | None      -> Some cs
          | Some prev ->
            if Pos.span_smaller cs.cs_span prev.cs_span
            then Some cs else best
        else best
      ) None a.call_sites
  in
  match containing with
  | None -> None
  | Some cs ->
    (* Resolve the callee's type from vars *)
    let scheme_opt =
      match cs.cs_fn_name with
      | None      -> None
      | Some name -> List.assoc_opt name a.vars
    in
    let ty_opt = match scheme_opt with
      | Some (Tc.Mono ty)         -> Some ty
      | Some (Tc.Poly (_, _, ty)) -> Some ty
      | None                      -> None
    in
    (match ty_opt with
     | None -> None
     | Some ty ->
       let (params, _ret) = unwrap_arrows ty in
       if params = [] then None
       else begin
         (* Determine active param by counting commas before cursor *)
         let open_paren_ofs =
           offset_of_pos a.src
             (cs.cs_span.Ast.start_line - 1)
             cs.cs_span.Ast.start_col
         in
         (* Skip to the opening '(' — search forward from the call span start *)
         let paren_ofs = ref open_paren_ofs in
         let src_len = String.length a.src in
         while !paren_ofs < src_len && a.src.[!paren_ofs] <> '(' do
           incr paren_ofs
         done;
         let cursor_ofs = offset_of_pos a.src line character in
         let active =
           if !paren_ofs >= src_len then 0
           else
             min
               (count_commas_between a.src (!paren_ofs + 1) cursor_ofs)
               (List.length params - 1)
         in
         let label =
           match cs.cs_fn_name with
           | Some n -> Printf.sprintf "%s(%s)" n (String.concat ", " params)
           | None   -> Printf.sprintf "(%s)" (String.concat ", " params)
         in
         Some (label, params, active)
       end)
```

- [ ] **6.6 Run tests — verify they pass**

```bash
dune runtest lsp/
```

- [ ] **6.7 Commit**

```bash
git add lsp/lib/analysis.ml lsp/test/test_lsp.ml
git commit -m "feat(lsp): collect call_sites, add signature_help_at query"
```

---

## Task 7 — Signature Help: server wiring

**Files:**
- Modify: `lsp/lib/server.ml`

> **linol note:** The linol base class does **not** expose a virtual hook for
> `textDocument/signatureHelp`. Like references and rename, it must be wired
> via `on_unknown_request` (JSON dispatch) with the capability injected in
> `config_modify_capabilities`.

- [ ] **7.1 Declare the capability in `config_modify_capabilities`**

Extend the existing `config_modify_capabilities` override (the same method
used for semantic tokens, references, and rename) to also advertise
`signatureHelpProvider`:

```ocaml
    method config_modify_capabilities caps =
      let open Lsp.Types in
      (* ... existing semantic-tokens legend and referencesProvider setup ... *)
      { caps with
        ServerCapabilities.semanticTokensProvider =
          Some (`SemanticTokensOptions sem_tokens);
        ServerCapabilities.referencesProvider =
          Some (`Bool true);
        ServerCapabilities.renameProvider =
          Some (`Bool true);
        ServerCapabilities.signatureHelpProvider =
          Some (SignatureHelpOptions.create
                  ~triggerCharacters:["("; ","]
                  ()) }
```

- [ ] **7.2 Dispatch `textDocument/signatureHelp` via `on_unknown_request`**

Inside the existing `on_unknown_request` handler, add a branch alongside
references and rename:

```ocaml
      end else if meth = "textDocument/signatureHelp" then begin
        (* Parse params: { textDocument: { uri }, position: { line, character } } *)
        let uri_opt, pos_opt =
          match params with
          | Some (`Assoc fields) ->
            let uri_opt =
              match List.assoc_opt "textDocument" fields with
              | Some (`Assoc td) ->
                (match List.assoc_opt "uri" td with
                 | Some (`String u) ->
                   let path =
                     if String.length u >= 7 && String.sub u 0 7 = "file://"
                     then String.sub u 7 (String.length u - 7) else u
                   in
                   Some (Lsp.Types.DocumentUri.of_path path)
                 | _ -> None)
              | _ -> None
            in
            let pos_opt =
              match List.assoc_opt "position" fields with
              | Some (`Assoc p) ->
                let line = match List.assoc_opt "line" p with
                  | Some (`Int n) -> n | _ -> 0 in
                let character = match List.assoc_opt "character" p with
                  | Some (`Int n) -> n | _ -> 0 in
                Some (line, character)
              | _ -> None
            in
            (uri_opt, pos_opt)
          | _ -> (None, None)
        in
        let result =
          match uri_opt, pos_opt with
          | Some uri, Some (line, character) ->
            (match get_analysis uri with
             | None   -> `Null
             | Some a ->
               (match Analysis.signature_help_at a ~line ~character with
                | None -> `Null
                | Some (label, params, active_param) ->
                  let param_infos = List.map (fun p ->
                      `Assoc [("label", `String p)]
                    ) params in
                  `Assoc [
                    ("signatures", `List [
                      `Assoc [
                        ("label",      `String label);
                        ("parameters", `List param_infos)]]);
                    ("activeSignature",  `Int 0);
                    ("activeParameter",  `Int active_param)
                  ]))
          | _ -> `Null
        in
        Lwt.return result
```

- [ ] **7.3 Build and test**

```bash
dune build && dune runtest lsp/
```

- [ ] **7.4 Commit**

```bash
git add lsp/lib/server.ml
git commit -m "feat(lsp): wire textDocument/signatureHelp handler"
```

---

## Task 8 — Code Action: Make Linear

**Files:**
- Modify: `lsp/lib/analysis.ml`
- Modify: `lsp/lib/server.ml`
- Test: `lsp/test/test_lsp.ml`

### Background

`build_consumption_map` in `analysis.ml` already computes which linear/affine
bindings are used and how many times. We now expose that data so `code_actions_for`
can offer a "make linear" quick-fix for non-linear `let` bindings that are used
exactly once.

A "make linear" edit inserts `linear ` immediately before the bound pattern
name in source. We find the source offset by using the binding pattern's span
from `def_map`.

### Step-by-step

- [ ] **8.1 Write the failing tests**

```ocaml
(* ------------------------------------------------------------------ *)
(* 14. Code actions: make-linear                                       *)
(* ------------------------------------------------------------------ *)

let test_make_linear_offered_for_single_use () =
  let src = {|
mod M do
  fn f() do
    let x = 42
    x + 1
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "let x" in
  let acts = An.code_actions_at a ~line ~character:col in
  let has_make_linear =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        match ca.title with
        | t -> String.length t > 0 &&
               (let low = String.lowercase_ascii t in
                let n = String.length low in
                let sub = "linear" in
                let sn = String.length sub in
                let found = ref false in
                for i = 0 to n - sn do
                  if String.sub low i sn = sub then found := true
                done;
                !found)
      ) acts
  in
  Alcotest.(check bool) "make-linear offered" true has_make_linear

let test_make_linear_not_offered_for_multi_use () =
  let src = {|
mod M do
  fn f() do
    let x = 10
    x + x
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "let x" in
  let acts = An.code_actions_at a ~line ~character:col in
  (* x is used twice — can't make it linear *)
  let has_make_linear =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        match ca.title with
        | t ->
          let low = String.lowercase_ascii t in
          let n = String.length low and sn = 6 in
          let found = ref false in
          for i = 0 to n - sn do
            if String.sub low i sn = "linear" then found := true
          done;
          !found
      ) acts
  in
  Alcotest.(check bool) "no make-linear for multi-use" false has_make_linear

let test_make_linear_edit_inserts_keyword () =
  let src = {|
mod M do
  fn f() do
    let value = 5
    value * 2
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "let value" in
  let acts = An.code_actions_at a ~line ~character:col in
  let linear_act = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      match ca.title with
      | t ->
        let low = String.lowercase_ascii t in
        let n = String.length low and sn = 6 in
        let found = ref false in
        for i = 0 to n - sn do
          if String.sub low i sn = "linear" then found := true
        done;
        !found
    ) acts
  in
  match linear_act with
  | None -> Alcotest.fail "expected make-linear action"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected workspace edit"
     | Some edit ->
       let has_edit =
         match edit.changes with
         | None -> false
         | Some m ->
           List.exists (fun (_, edits) ->
               List.exists (fun (e : Lsp.Types.TextEdit.t) ->
                   let t = e.newText in
                   let n = String.length t and sn = 7 in
                   let found = ref false in
                   for i = 0 to n - sn do
                     if String.sub t i sn = "linear " then found := true
                   done;
                   !found
                 ) edits
             ) m
       in
       Alcotest.(check bool) "edit inserts 'linear '" true has_edit)
```

Add to `Alcotest.run`:

```ocaml
    "code actions: make-linear", [
      "offered for single-use binding",  `Quick, test_make_linear_offered_for_single_use;
      "not offered for multi-use",        `Quick, test_make_linear_not_offered_for_multi_use;
      "edit inserts 'linear ' keyword",   `Quick, test_make_linear_edit_inserts_keyword;
    ];
```

- [ ] **8.2 Run — verify compilation fails** (`An.code_actions_at` undefined)

- [ ] **8.3 Expose consumption map in `Analysis.t`**

Add to `type t`:

```ocaml
  consumption   : consumption list;
  (** Linear/affine binding consumption records — used for make-linear actions. *)
```

In `analyse`, after the `collect_decl` calls, build it using the already-existing function:

```ocaml
    let consumption = build_consumption_map type_map user_decls in
```

Include `consumption` in the returned record and in `make_empty_with` (`consumption = []`).

- [ ] **8.4 Add `code_actions_at` query function to `analysis.ml`**

```ocaml
(** Find the byte offset range of name [name] in [src] starting from [hint_ofs].
    Returns the byte offset of the first character of the name. *)
let find_name_ofs src name hint_ofs =
  let sn  = String.length name in
  let len = String.length src in
  let rec go i =
    if i + sn > len then None
    else if String.sub src i sn = name then Some i
    else go (i + 1)
  in
  go hint_ofs

(** Generate code actions relevant to the cursor position [line, character].
    Currently produces:
    - "Make `x` linear" for single-use non-linear let bindings at cursor. *)
let code_actions_at (a : t) ~line ~character
    : Lsp.Types.CodeAction.t list =
  let open Lsp.Types in
  (* Find all single-use consumption records whose definition span contains cursor *)
  List.filter_map (fun (c : consumption) ->
      let span = c.con_def in
      if not (Pos.span_contains span ~line ~character) then None
      else if List.length c.con_uses <> 1 then None
      else begin
        (* Build a TextEdit that inserts "linear " before the name *)
        let name = c.con_name in
        let hint_ofs =
          offset_of_pos a.src (span.Ast.start_line - 1) span.Ast.start_col
        in
        match find_name_ofs a.src name hint_ofs with
        | None -> None
        | Some name_ofs ->
          (* Convert name_ofs back to (line, col) in the source *)
          let insert_line = ref 0 and insert_col = ref 0 in
          let cur_line = ref 0 and cur_col = ref 0 in
          String.iteri (fun i _ch ->
              if i = name_ofs then begin
                insert_line := !cur_line;
                insert_col  := !cur_col
              end;
              if a.src.[i] = '\n' then begin
                incr cur_line;
                cur_col := 0
              end else
                incr cur_col
            ) a.src;
          let range =
            Range.create
              ~start:(Position.create ~line:!insert_line ~character:!insert_col)
              ~end_:(Position.create  ~line:!insert_line ~character:!insert_col)
          in
          let edit = TextEdit.create ~range ~newText:"linear " in
          (* WorkspaceEdit.create ~changes expects (DocumentUri.t * TextEdit.t list) list *)
          let uri  = DocumentUri.of_path a.filename in
          let we   = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
          let action = CodeAction.create
                         ~title:(Printf.sprintf "Make `%s` linear" name)
                         ~kind:CodeActionKind.RefactorRewrite
                         ~edit:we
                         () in
          Some action
      end
    ) a.consumption
```

- [ ] **8.5 Run tests — verify they pass**

```bash
dune runtest lsp/
```

- [ ] **8.6 Replace stub `code_actions_for` in `server.ml`**

Replace the existing stub at the top of `server.ml`:

```ocaml
let code_actions_for (a : Analysis.t) uri range :
    Lsp.Types.CodeAction.t list =
  let open Lsp.Types in
  let mid_line = (range.Range.start.line + range.Range.end_.line) / 2 in
  let mid_char = range.Range.start.character in
  ignore uri;
  Analysis.code_actions_at a ~line:mid_line ~character:mid_char
```

- [ ] **8.7 Build and test**

```bash
dune build && dune runtest lsp/
```

- [ ] **8.8 Commit**

```bash
git add lsp/lib/analysis.ml lsp/lib/server.ml lsp/test/test_lsp.ml
git commit -m "feat(lsp): code action 'make linear' for single-use bindings"
```

---

## Task 9 — Code Action: Pattern Match Exhaustion Quickfix

**Files:**
- Modify: `lsp/lib/analysis.ml`
- Modify: `lsp/lib/server.ml`
- Test: `lsp/test/test_lsp.ml`

### Background

The March type-checker already emits a `Warning` for non-exhaustive matches
with message `"Non-exhaustive pattern match — missing case: <pattern>"`. We
surface this as a code action that inserts the missing arm into the source.

**Finding the match `end`:** The warning's span covers the whole `match …
end` expression. The `end` keyword sits just before the span's end position.
We find it by scanning backwards from the span's last character in the raw
source.

**Generating the arm:** Extract the pattern string from the message after the
`": "` prefix. Produce the edit:

```
| <pattern> ->\n    ?\n
```

inserted on a new line immediately before the `end` that closes the match.

### Step-by-step

- [ ] **9.1 Add `match_site` type and field to `Analysis.t`**

Add before `type t`:

```ocaml
(** A non-exhaustive match site extracted from diagnostics. *)
type match_site = {
  ms_span         : Ast.span;  (** Span of the whole match expression *)
  ms_missing_case : string;    (** Pattern example from the warning message *)
}
```

Add to `type t`:

```ocaml
  match_sites : match_site list;
  (** Non-exhaustive match warnings, structured for quickfix consumption. *)
```

- [ ] **9.2 Write the failing tests**

```ocaml
(* ------------------------------------------------------------------ *)
(* 15. Code actions: pattern exhaustion quickfix                       *)
(* ------------------------------------------------------------------ *)

let test_exhaustion_quickfix_absent_for_exhaustive_match () =
  let src = {|
mod M do
  type Color = Red | Green | Blue

  fn describe(c: Color): String do
    match c with
    | Red   -> "red"
    | Green -> "green"
    | Blue  -> "blue"
    end
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "match c" in
  let acts = An.code_actions_at a ~line ~character:col in
  let has_exhaustion =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        let low = String.lowercase_ascii ca.title in
        let n = String.length low and sn = 7 in
        let found = ref false in
        for i = 0 to n - sn do
          if String.sub low i sn = "missing" then found := true
        done;
        !found
      ) acts
  in
  Alcotest.(check bool) "no exhaustion fix for complete match" false has_exhaustion

let test_exhaustion_quickfix_offered_for_incomplete_match () =
  let src = {|
mod M do
  type Shape = Circle | Square | Triangle

  fn area(s: Shape): Int do
    match s with
    | Circle -> 1
    | Square -> 2
    end
  end
end
|} in
  let a = analyse src in
  (* There should be a non-exhaustive warning diagnostic *)
  let has_warning =
    List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
        match d.severity with
        | Some Lsp.Types.DiagnosticSeverity.Warning -> true
        | _ -> false
      ) a.diagnostics
  in
  Alcotest.(check bool) "warning present" true has_warning;
  let (line, col) = pos_of src "match s" in
  let acts = An.code_actions_at a ~line ~character:col in
  let has_quickfix =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        ca.kind = Some Lsp.Types.CodeActionKind.QuickFix
      ) acts
  in
  Alcotest.(check bool) "quickfix offered" true has_quickfix

let test_exhaustion_quickfix_edit_contains_missing_arm () =
  let src = {|
mod M do
  type Dir = North | South | East | West

  fn label(d: Dir): String do
    match d with
    | North -> "N"
    | South -> "S"
    | East  -> "E"
    end
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "match d" in
  let acts = An.code_actions_at a ~line ~character:col in
  let qf = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      ca.kind = Some Lsp.Types.CodeActionKind.QuickFix
    ) acts in
  match qf with
  | None -> Alcotest.fail "expected quickfix"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected edit"
     | Some edit ->
       let found_west =
         match edit.changes with
         | None -> false
         | Some m ->
           List.exists (fun (_, edits) ->
               List.exists (fun (e : Lsp.Types.TextEdit.t) ->
                   let low = String.lowercase_ascii e.newText in
                   let n = String.length low and sn = 4 in
                   let f = ref false in
                   for i = 0 to n - sn do
                     if String.sub low i sn = "west" then f := true
                   done;
                   !f
                 ) edits
             ) m
       in
       Alcotest.(check bool) "edit mentions West" true found_west)

let test_exhaustion_quickfix_edit_inserts_before_end () =
  let src = {|
mod M do
  type Bit = Zero | One

  fn flip(b: Bit): Bit do
    match b with
    | Zero -> One
    end
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "match b" in
  let acts = An.code_actions_at a ~line ~character:col in
  let qf = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      ca.kind = Some Lsp.Types.CodeActionKind.QuickFix) acts in
  match qf with
  | None -> Alcotest.fail "expected quickfix"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected edit"
     | Some edit ->
       (* The inserted text should look like a match arm: "| ... ->" *)
       let has_arm =
         match edit.changes with
         | None -> false
         | Some m ->
           List.exists (fun (_, edits) ->
               List.exists (fun (e : Lsp.Types.TextEdit.t) ->
                   String.contains e.newText '|'
                 ) edits
             ) m
       in
       Alcotest.(check bool) "edit is a match arm" true has_arm)
```

Add to `Alcotest.run`:

```ocaml
    "code actions: exhaustion quickfix", [
      "absent for exhaustive match",    `Quick, test_exhaustion_quickfix_absent_for_exhaustive_match;
      "offered for incomplete match",   `Quick, test_exhaustion_quickfix_offered_for_incomplete_match;
      "edit contains missing arm",      `Quick, test_exhaustion_quickfix_edit_contains_missing_arm;
      "edit inserts before end",        `Quick, test_exhaustion_quickfix_edit_inserts_before_end;
    ];
```

- [ ] **9.3 Run — verify compilation fails** (new field `match_sites` missing from construction)

- [ ] **9.4 Collect `match_sites` in `analyse`**

The `check_module_full` run already produces exhaustiveness warnings. We
extract them from `errors` after typechecking. Add after the `let (errors, …)`
line:

```ocaml
    let match_sites =
      let prefix = "Non-exhaustive pattern match — missing case: " in
      let plen   = String.length prefix in
      List.filter_map (fun (d : March_errors.Errors.diagnostic) ->
          if d.severity = March_errors.Errors.Warning &&
             String.length d.message >= plen &&
             String.sub d.message 0 plen = prefix
          then
            let ms_missing_case =
              String.sub d.message plen (String.length d.message - plen)
            in
            (* Only surface warnings from the user file *)
            if d.span.Ast.file = filename || d.span.Ast.file = "" ||
               d.span.Ast.file = "<unknown>"
            then Some { ms_span = d.span; ms_missing_case }
            else None
          else None
        ) (March_errors.Errors.sorted errors)
    in
```

Include `match_sites` in the returned record and `make_empty_with` (`match_sites = []`).

- [ ] **9.5 Add helper: find `end` offset preceding a span**

```ocaml
(** Find the byte offset of the [end] keyword immediately before the end of
    [span] in [src].  Scans backwards to locate it. Returns [None] if not found. *)
let find_end_before_span src (span : Ast.span) =
  (* Convert the span's end position to a byte offset *)
  let end_ofs = offset_of_pos src (span.Ast.end_line - 1) span.Ast.end_col in
  (* Scan backwards from end_ofs for "end" surrounded by whitespace/boundary *)
  let sn = 3 in
  let rec go i =
    if i < sn then None
    else
      let candidate = String.sub src (i - sn) sn in
      if candidate = "end" then begin
        (* Confirm it's a word boundary *)
        let before_ok =
          i - sn = 0 ||
          (let c = src.[i - sn - 1] in c = ' ' || c = '\n' || c = '\t')
        in
        let after_ok =
          i >= String.length src ||
          (let c = src.[i] in c = ' ' || c = '\n' || c = '\t' || c = '\r')
        in
        if before_ok && after_ok then Some (i - sn)
        else go (i - 1)
      end else
        go (i - 1)
  in
  go (min end_ofs (String.length src))
```

- [ ] **9.6 Rewrite `code_actions_at` to include both action kinds**

Replace the entire `code_actions_at` function written in Task 8.4 with this
version that accumulates both action lists and concatenates them:

```ocaml
(** Generate code actions relevant to the cursor position [line, character].
    Produces:
    - "Make `x` linear" for single-use non-linear let bindings at cursor.
    - "Add missing case: P" quickfix for non-exhaustive matches at cursor. *)
let code_actions_at (a : t) ~line ~character
    : Lsp.Types.CodeAction.t list =
  let open Lsp.Types in
  (* ---- Make-linear actions ---- *)
  let make_linear_actions =
    List.filter_map (fun (c : consumption) ->
        let span = c.con_def in
        if not (Pos.span_contains span ~line ~character) then None
        else if List.length c.con_uses <> 1 then None
        else begin
          let name = c.con_name in
          let hint_ofs =
            offset_of_pos a.src (span.Ast.start_line - 1) span.Ast.start_col
          in
          match find_name_ofs a.src name hint_ofs with
          | None -> None
          | Some name_ofs ->
            let insert_line = ref 0 and insert_col = ref 0 in
            let cur_line = ref 0 and cur_col = ref 0 in
            String.iteri (fun i _ch ->
                if i = name_ofs then begin
                  insert_line := !cur_line;
                  insert_col  := !cur_col
                end;
                if a.src.[i] = '\n' then begin incr cur_line; cur_col := 0 end
                else incr cur_col
              ) a.src;
            let range =
              Range.create
                ~start:(Position.create ~line:!insert_line ~character:!insert_col)
                ~end_:(Position.create  ~line:!insert_line ~character:!insert_col)
            in
            let edit = TextEdit.create ~range ~newText:"linear " in
            (* WorkspaceEdit.create ~changes expects (DocumentUri.t * TextEdit.t list) list *)
            let uri  = DocumentUri.of_path a.filename in
            let we   = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
            let action = CodeAction.create
                           ~title:(Printf.sprintf "Make `%s` linear" name)
                           ~kind:CodeActionKind.RefactorRewrite
                           ~edit:we
                           () in
            Some action
        end
      ) a.consumption
  in
  (* ---- Exhaustion quickfix actions ---- *)
  let exhaustion_actions =
    List.filter_map (fun (ms : match_site) ->
        if not (Pos.span_contains ms.ms_span ~line ~character) then None
        else begin
          match find_end_before_span a.src ms.ms_span with
          | None -> None
          | Some end_ofs ->
            let e_line = ref 0 and e_col = ref 0 in
            let cl = ref 0 and cc = ref 0 in
            String.iteri (fun i _ch ->
                if i = end_ofs then begin
                  e_line := !cl;
                  e_col  := !cc
                end;
                if a.src.[i] = '\n' then begin incr cl; cc := 0 end
                else incr cc
              ) a.src;
            let insert_pos = Position.create ~line:!e_line ~character:!e_col in
            let range      = Range.create ~start:insert_pos ~end_:insert_pos in
            let arm_text   = Printf.sprintf "| %s ->\n    ?\n" ms.ms_missing_case in
            let edit       = TextEdit.create ~range ~newText:arm_text in
            (* WorkspaceEdit.create ~changes expects (DocumentUri.t * TextEdit.t list) list *)
            let uri    = DocumentUri.of_path a.filename in
            let we     = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
            let action = CodeAction.create
                           ~title:(Printf.sprintf "Add missing case: %s" ms.ms_missing_case)
                           ~kind:CodeActionKind.QuickFix
                           ~edit:we
                           () in
            Some action
        end
      ) a.match_sites
  in
  make_linear_actions @ exhaustion_actions
```

> **Note:** This replaces the Task 8.4 implementation entirely. Remove the old
> `code_actions_at` body and insert this version in its place.

- [ ] **9.7 Run tests — verify they pass**

```bash
dune runtest lsp/
```

- [ ] **9.8 Update `code_actions_for` in `server.ml` to pass the full range mid-point**

The existing replacement from Task 8 already routes to `Analysis.code_actions_at`.
Verify the mid-point cursor calculation is correct for match spans (which can
be multi-line). If a match expression is at lines 5–15 and the action is
requested for the whole range, the mid-point might not land inside. Fix:

```ocaml
let code_actions_for (a : Analysis.t) uri range :
    Lsp.Types.CodeAction.t list =
  ignore uri;
  let open Lsp.Types in
  (* Try the start of the requested range first, then the midpoint *)
  let line1 = range.Range.start.line in
  let char1 = range.Range.start.character in
  let acts1 = Analysis.code_actions_at a ~line:line1 ~character:char1 in
  let line2 = (range.Range.start.line + range.Range.end_.line) / 2 in
  let char2 = range.Range.start.character in
  let acts2 = Analysis.code_actions_at a ~line:line2 ~character:char2 in
  (* Deduplicate by title *)
  let seen = Hashtbl.create 8 in
  List.filter (fun (ca : CodeAction.t) ->
      if Hashtbl.mem seen ca.title then false
      else (Hashtbl.add seen ca.title (); true)
    ) (acts1 @ acts2)
```

- [ ] **9.9 Build and test**

```bash
dune build && dune runtest lsp/
```

- [ ] **9.10 Commit**

```bash
git add lsp/lib/analysis.ml lsp/lib/server.ml lsp/test/test_lsp.ml
git commit -m "feat(lsp): code action quickfix for non-exhaustive pattern matches"
```

---

## Task 10 — Final integration smoke test and cleanup

- [ ] **10.1 Run full test suite**

```bash
dune runtest
```

Expected: all tests pass, no regressions in the main compiler test suite.

- [ ] **10.2 Verify `dune build` is clean (no warnings in LSP lib)**

```bash
dune build 2>&1 | grep -i warning | grep -v "_build"
```

Expected: no new warnings.

- [ ] **10.3 Final commit (if any stray changes remain)**

```bash
git add lsp/lib/analysis.ml lsp/lib/server.ml lsp/test/test_lsp.ml
git commit -m "chore(lsp): tidy up after feature implementation"
```

---

## Edge Cases & Gotchas

| Feature | Edge case | How it's handled |
|---------|-----------|-----------------|
| Doc strings | Triple-quoted strings with embedded newlines | `fn_doc` stores the raw content; callers display as-is in markdown |
| Doc strings | Doc on interface method (no `fn_doc`) | `doc_map` will simply have no entry; hover shows type only |
| Find refs | Cursor on the definition, not a use | `doc_name_at` / `references_at` fall back to `def_map` lookup |
| Find refs | Name used in stdlib | `use_map` only contains user-file spans; stdlib uses are excluded by the existing file-filter in `collect_decl` |
| Rename | New name is a keyword | The LSP client is responsible for validation; the server generates the edit unconditionally |
| Sig help | Lambda passed as argument | `cs_fn_name = None`; `signature_help_at` returns `None` gracefully |
| Sig help | Curried application (`f a b`) | Desugared to nested `EApp` nodes; inner call is matched first (smallest span) |
| Sig help | Zero-argument function `f()` | `unwrap_arrows` returns `([], ret)` → returns `None` |
| Make-linear | Pattern binding with tuple `let (a, b) = …` | `build_consumption_map` tracks each name separately; each gets its own action |
| Make-linear | Already-linear binding | `build_consumption_map` skips non-linear bindings; no duplicate actions |
| Exhaustion QF | Match with guards (undecidable coverage) | `check_exhaustiveness` skips guarded matches; no warning → no action |
| Exhaustion QF | `end` keyword appears in a string inside the match | `find_end_before_span` scans raw source; could be confused. Accept this limitation for now; a robust parser-based approach is a future improvement |
| All | Parse error in document | `make_empty_with` sets empty tables/lists; all queries return nothing gracefully |

## Reference: Key Types

```ocaml
(* March ast *)
Ast.fn_def.fn_doc  : string option
Ast.fn_def.fn_name : Ast.name  (* .txt = string, .span = Ast.span *)
Ast.fn_clause.fc_params : Ast.fn_param list
Ast.param.param_name : Ast.name
Ast.param.param_ty   : Ast.ty option

(* Typecheck *)
Tc.ty  = TCon | TVar | TArrow of ty * ty | TTuple | TRecord | TLin | ...
Tc.scheme = Mono of ty | Poly of int list * constraint_ list * ty
Tc.pp_ty : ty -> string

(* Errors *)
Err.diagnostic.severity : Error | Warning | Hint
Err.diagnostic.span     : Ast.span
Err.diagnostic.message  : string

(* Position (0-indexed lines, 0-indexed cols) *)
Pos.span_contains sp ~line ~character : bool
Pos.span_to_lsp_range sp : Lsp.Types.Range.t
Pos.span_smaller inner outer : bool
```

---

## March-Specific LSP Features

These features go beyond the five tasks above and are specific to March's language model. They are planned at the same architectural level but not yet tasked for implementation. Work them in priority order.

---

### P1 — High Value

---

#### Feature A — Actor/Supervision Topology Visualization

**What:** A custom LSP notification that sends actor hierarchy data to the editor. Shows which actors spawn which, supervision trees, link/monitor relationships. Editors that support custom LSP extensions (Zed, Neovim, VS Code with extension) can render this as a sidebar or inline code lens.

**Why:** March's actor system with supervisors, links, and monitors is hard to reason about from code alone. A topology view is a killer feature that no mainstream language server offers.

**Protocol:**
- Option A: Custom `march/actorTopology` notification. Server computes the graph on `textDocument/didOpen` / `textDocument/didChange` and pushes it to the client. Client extension renders it.
- Option B: `textDocument/codeLens` — annotate each `actor` declaration with spawn count and supervision depth, e.g., `[spawned by: Supervisor | depth: 2 | links: 3]`. No custom client needed.
- **Recommended:** Ship Option B first (zero client work), then add Option A as a richer extension.

**Implementation sketch:**
1. Walk the desugared AST for `actor` declarations, `spawn` / `spawn_link` / `spawn_monitor` calls, and `supervise` blocks.
2. Build an adjacency map: `actor_name → { spawns: name list; supervised_by: name option; links: name list }`.
3. For code lens: compute depth (BFS from root supervisor) and attach to each actor's declaration span.
4. For custom notification: serialize adjacency map to JSON and push via `$/march/actorTopology`.

**New analysis fields:**
```ocaml
type actor_info = {
  ai_name       : string;
  ai_span       : Ast.span;
  ai_spawns     : string list;
  ai_supervised : string option;
  ai_links      : string list;
}

(* in Analysis.t *)
actor_map : actor_info String.Map.t;
```

**Test scaffolding:**
```ocaml
(* Test: supervisor spawns two workers *)
let src = {|
mod M do
  actor Supervisor do ... end
  actor Worker do ... end
  fn main() do
    spawn_link Worker
    spawn_link Worker
  end
end
|} in
let a = analyse src in
let info = An.actor_info a "Supervisor" in
Alcotest.(check int) "spawns 2 workers" 2 (List.length info.ai_spawns)
```

**Complexity:** Medium. AST walk is straightforward; the tricky part is resolving `spawn` call targets when they're stored in variables. Start with direct `spawn(ActorName, ...)` forms and handle indirect spawns in a follow-up.

---

#### Feature B — Linear Type Consumption Tracking

**What:** Show where linear/affine values are consumed, warn about unconsumed values inline, highlight the consumption point. In practice: inlay hints saying `consumed ↑` at the call site, and diagnostics for paths where a linear value escapes unconsumed.

**Why:** Linear types are March's core differentiator. Without IDE support, users must mentally track consumption — error messages alone aren't enough.

**Protocol:**
- `textDocument/inlayHints` — `consumed here` annotation at each consumption span.
- `textDocument/diagnostic` (supplemental) — `linear value 'x' not consumed on this path` for missing consumptions.
- Optional `textDocument/codeLens` on the binding site: `consumed 1×` or `⚠ unconsumed`.

**Implementation sketch:**
1. The typechecker already tracks linear bindings in `lin_entry` (or equivalent). After type-checking a function body, enumerate all linear binding spans and their single consumption span.
2. Build `lin_consumption_map : span -> span` (binding span → consumption span).
3. For inlay hints: at the consumption span, emit `↑ linear 'x' consumed`.
4. For diagnostics: any linear binding without a recorded consumption site emits a warning diagnostic.

**New analysis fields:**
```ocaml
type lin_consumption = {
  lc_binding   : Ast.span;   (* where the linear value was bound *)
  lc_consumed  : Ast.span option;  (* where it was consumed; None = leak *)
  lc_name      : string;
}

(* in Analysis.t *)
lin_map : lin_consumption list;
```

**New query functions:**
```ocaml
val linear_consumptions : t -> lin_consumption list
(** All linear bindings in the last-analysed document. *)

val inlay_hints_for_linear : t -> Lsp.Types.InlayHint.t list
(** Convert lin_map to LSP InlayHint records. *)
```

**Test scaffolding:**
```ocaml
(* Test: linear value consumed once — one consumption record, no leak *)
let src = {|
mod M do
  fn use_linear(x: lin Int): Int do consume(x) end
end
|} in
let a = analyse src in
let lins = An.linear_consumptions a in
Alcotest.(check int) "one linear binding" 1 (List.length lins);
Alcotest.(check bool) "consumed" true (Option.is_some (List.hd lins).lc_consumed)
```

**Complexity:** Medium. Requires threading consumption-span recording through the typechecker's linear checking pass. The hard part is multi-branch paths (if/match) where a linear value must be consumed on every branch — the per-branch analysis is already done by the typechecker; we just need to surface the spans.

---

#### Feature C — Session Type Protocol State Tracking

**What:** Show the current protocol state at each point in a session-typed channel interaction inline. After `Chan.send(ch, msg)`, an inlay hint shows that the channel's protocol advanced from `!Int.?String.end` to `?String.end`. Hovering a channel variable shows its remaining protocol.

**Why:** Session types are expressive but opaque — the protocol lives in the type signature, not in the code. Inline state tracking makes session types actually usable in practice.

**Protocol:**
- `textDocument/inlayHints` — after each channel operation, emit the residual protocol type.
- `textDocument/hover` (extend existing) — hover on a channel variable shows current protocol type, not just the raw session type.

**Implementation sketch:**
1. During type inference, when the typechecker processes a channel operation (send/receive/close), record the pre- and post-operation session types alongside the AST span.
2. Store as `session_state_map : Ast.span -> { before: Tc.ty; after: Tc.ty }`.
3. For inlay hints: at the end of each channel-op span, emit the `after` type formatted with `Tc.pp_ty`.
4. For hover: look up the channel variable name in `session_state_map` for the innermost span; show the current `before` type.

**New analysis fields:**
```ocaml
type session_state = {
  ss_before : Tc.ty;
  ss_after  : Tc.ty;
  ss_op     : string;   (* "send" | "recv" | "close" *)
}

(* in Analysis.t *)
session_map : session_state Ast.Span.Map.t;
```

**Test scaffolding:**
```ocaml
(* Test: after a send, protocol advances *)
let src = {|
mod M do
  fn proto(ch: Chan(!Int.end)): Unit do
    Chan.send(ch, 42)
  end
end
|} in
let a = analyse src in
(* Find the send span, check that after-state is `end` *)
let states = An.session_states_at a ~line ~character in
Alcotest.(check string) "after send, protocol is end"
  "end" (Tc.pp_ty (List.hd states).ss_after)
```

**Complexity:** High. Requires threading span-annotated session type state through the typechecker. Session type unfolding (unfold a recursive session type at each step) must be recorded rather than discarded. This is the highest-complexity feature in this plan — implement after the typechecker is stable.

---

#### Feature D — Interface Impl Navigation

**What:** Go-to-definition on an interface method call jumps to the specific impl for that concrete type. E.g., clicking `==` on a `Color` value jumps to `impl Eq for Color`, not to the `Eq` interface declaration.

**Why:** With mono-time dispatch, the compiler knows exactly which impl applies — exposing that to the user makes code navigation much more precise.

**Protocol:**
- Extend `textDocument/definition` — when the resolved name is an interface method and there's a concrete type at the call site, return the impl declaration span instead of (or in addition to) the interface declaration span.
- `textDocument/implementation` — list all impls for an interface method across the workspace.

**Implementation sketch:**
1. After type-checking, the `impl_tbl` maps `(interface_name, type_name) → impl_decl`. Impl declarations must have their source spans recorded (add `impl_span : Ast.span` to the impl table entry).
2. In `definition_at`: if the target resolves to an interface method name and the enclosing expression has a concrete inferred type, look up `impl_tbl[(interface, concrete_type)]` and return its span.
3. In `implementation_at`: given an interface method name, return all `impl_tbl` entries for that method name.

**New analysis fields:**
```ocaml
(* Extend existing impl_tbl entry *)
type impl_entry = {
  ie_interface : string;
  ie_type      : string;
  ie_span      : Ast.span;   (* declaration span of the impl block *)
  ie_methods   : (string * Ast.span) list;  (* method name → method span *)
}

(* in Analysis.t *)
impl_map : impl_entry list;
```

**New query functions:**
```ocaml
val impl_for : t -> interface:string -> ty:string -> impl_entry option
val impls_of_method : t -> method_name:string -> impl_entry list
```

**Test scaffolding:**
```ocaml
(* Test: definition on `==` for Color jumps to Color's Eq impl *)
let src = {|
mod M do
  type Color = Red | Green | Blue
  impl Eq for Color do
    fn eq(a: Color, b: Color): Bool do a == b end
  end
  fn main() do Red == Blue end
end
|} in
let a = analyse src in
let (line, col) = pos_of src "Red == Blue" |> advance_to "==" in
let defs = An.definition_at a ~line ~character:col in
(* Should point into the impl block, not the Eq interface *)
Alcotest.(check bool) "points to impl" true
  (List.exists (fun d -> span_contains_text d "impl Eq for Color") defs)
```

**Complexity:** Low-Medium. The impl resolution logic already exists in the typechecker; the main work is (a) recording impl declaration spans during the typecheck pass and (b) wiring the `definition_at` lookup to prefer the concrete impl span when a concrete type is known.

---

#### Feature E — Pipe Chain Type Flow

**What:** Show the type at each step of a `|>` pipeline as inlay hints. E.g.:

```
data |> filter(pred) |> map(f) |> take(5)
     ^ List(Int)     ^ List(Int) ^ List(String) ^ List(String)
```

**Why:** March is pipe-heavy (like Elixir). Seeing types flow through the chain makes it easy to spot mismatches without reading deeply nested type error messages.

**Protocol:**
- `textDocument/inlayHints` — after each `|>` operator, emit a `: Type` inlay hint.

**Implementation sketch:**
1. The desugarer transforms `a |> f |> g` into nested `EApp` nodes. The typechecker annotates each `EApp` with its result type (in the `type_map`).
2. Walk the `type_map` for spans that correspond to `EApp` nodes produced by pipe desugaring. The desugarer should tag these nodes (e.g., with a boolean `from_pipe : bool` on `EApp`) or we can identify them by checking whether the span of the outer `EApp` immediately follows a `|>` token.
3. Emit a `: T` inlay hint after the `|>` token at the start of each pipe step.

**New query function:**
```ocaml
val pipe_type_hints : t -> Lsp.Types.InlayHint.t list
(** All pipe-step type annotations as LSP inlay hints. *)
```

**Test scaffolding:**
```ocaml
(* Test: pipeline of two steps produces two inlay hints *)
let src = {|
mod M do
  fn main() do
    [1, 2, 3] |> List.map(fn x -> x + 1) |> List.length
  end
end
|} in
let a = analyse src in
let hints = An.pipe_type_hints a in
(* One hint after each |> = 2 hints *)
Alcotest.(check int) "two pipe hints" 2 (List.length hints);
(* Second hint should be Int (result of List.length) *)
let last_hint = List.nth hints 1 in
Alcotest.(check string) "last pipe type is Int" "Int"
  (match last_hint.Lsp.Types.InlayHint.label with
   | `String s -> s | _ -> "?")
```

**Note on desugarer tagging:** The cleanest implementation adds a `pipe_steps : Ast.span list` field to `Analysis.t` during the desugar pass, recording the span of each expression produced by a `|>`. This avoids any heuristic span-matching in `analysis.ml`.

**Complexity:** Low-Medium. The type information is already in `type_map`; the main challenge is correctly identifying which `EApp` spans came from pipe desugaring. Tagging in the desugarer is ~5 lines.

---

### P2 — Nice to Have

---

#### Feature F — Semantic Tokens

**What:** Rich compiler-driven syntax highlighting that supersedes Tree-sitter regex patterns. Distinguishes linear variables, actor names, constructor names, interface names, and type variables from ordinary identifiers.

**Protocol:** `textDocument/semanticTokens/full` — returns a flat encoded array of `(line, startChar, length, tokenType, tokenModifiers)` tuples.

**Implementation sketch:**
1. Define a token legend matching Lsp.Types.SemanticTokensLegend: token types include `variable`, `function`, `type`, `interface`, `enumMember` (constructors), `macro` (actors), plus custom `linearVariable` if client supports it.
2. Walk the `type_map` and `def_map` to classify each use-site span by its kind.
3. Encode into the LSP-required delta-encoded integer array.
4. Register the capability in `server.ml` and add a handler for `textDocument/semanticTokens/full`.

**Test scaffolding:**
```ocaml
(* Test: 'add' classified as function token, 'Int' as type token *)
let a = analyse src in
let tokens = An.semantic_tokens a in
let add_tok = List.find (fun t -> t.st_text = "add") tokens in
Alcotest.(check string) "add is function" "function" add_tok.st_type
```

**Complexity:** Medium. The LSP encoding format (delta encoding) is fiddly; use the `lsp` library's helpers. The classification logic is straightforward given `def_map` and `type_map`.

---

#### Feature G — Code Lens

**What:** Show contextual metadata above declarations:
- Functions: test count (if any test references this function by name)
- Types: count of interface impls for this type
- Actors: count of message handlers, supervision depth
- `derive(...)`: which traits are auto-derived

**Protocol:** `textDocument/codeLens` — returns a list of `CodeLens` (range + command + optional data).

**Implementation sketch:**
1. For test counts: scan `def_map` for functions whose names start with `test_` and that call a given function; group by called function name.
2. For impl counts: use `impl_map` from Feature D; for each type declaration, count entries.
3. For actor stats: use `actor_map` from Feature A.
4. Emit each code lens with a `march.showRefs` command that the editor can invoke.

**Test scaffolding:**
```ocaml
let lenses = An.code_lenses a in
let type_lens = List.find (fun l -> l.cl_label = "2 impls") lenses in
Alcotest.(check bool) "Color has 2 impl lenses" true (Option.is_some type_lens)
```

**Complexity:** Low. Most data is already collected by Features A and D; this is primarily a rendering pass.

---

#### Feature H — Call Hierarchy

**What:** Show incoming and outgoing calls for any function. Essential for understanding actor message flows and tracing data through pipelines.

**Protocol:**
- `textDocument/prepareCallHierarchy` — resolve the item at cursor.
- `callHierarchy/incomingCalls` — who calls this function.
- `callHierarchy/outgoingCalls` — what this function calls.

**Implementation sketch:**
1. Build `call_graph : string -> string list` (callee → callers) by walking the `use_map` for function-name uses that appear inside another function body. The enclosing function can be determined by checking which `fn_def` span contains the use span.
2. `prepare_call_hierarchy_at` resolves the name at cursor to a function definition (via `def_map`), returns a `CallHierarchyItem`.
3. `incoming_calls` looks up `call_graph[name]` → caller function items.
4. `outgoing_calls` walks the function body spans in `use_map` to find callees.

**New analysis field:**
```ocaml
(* in Analysis.t *)
call_graph : (string * string list) list;  (* fn_name -> list of callee names *)
enclosing_fn : Ast.span -> string option;  (* span -> enclosing function name *)
```

**Test scaffolding:**
```ocaml
(* Test: main calls add twice — outgoing calls for main includes add *)
let calls = An.outgoing_calls a "main" in
Alcotest.(check bool) "main calls add" true (List.mem "add" calls)
```

**Complexity:** Medium. The call graph traversal requires mapping use-site spans to their enclosing function, which means sorting `fn_def` spans and doing a containment check — O(n log n) on first build, then O(1) per lookup with a span tree.

---

#### Feature I — Workspace Symbols

**What:** Fuzzy-find any symbol (function, type, constructor, interface, actor) across all open/indexed March files in the workspace.

**Protocol:** `workspace/symbol` — given a query string, return matching `SymbolInformation` records.

**Implementation sketch:**
1. Maintain a workspace-level index (`WorkspaceIndex.t`) that aggregates `def_map` entries from all analysed files. Update on `textDocument/didChange`.
2. On `workspace/symbol` request, run a simple substring or trigram match against all indexed symbol names.
3. Return `SymbolInformation` with kind mapped from March's declaration kind (`DFn → Function`, `DType → Class`, `DInterface → Interface`, etc.).

**New module:** `lsp/lib/workspace_index.ml` (the only feature that warrants a new file, since it manages cross-file state).

**Test scaffolding:**
```ocaml
(* Test: query "add" returns the add function from the indexed file *)
let idx = WorkspaceIndex.empty |> WorkspaceIndex.add_file "test.march" a in
let results = WorkspaceIndex.query idx "add" in
Alcotest.(check bool) "found add" true
  (List.exists (fun r -> r.wi_name = "add") results)
```

**Complexity:** Low. Substring matching is fast enough for typical workspace sizes. Trigram indexing can be added later if needed.

---

### P3 — Future

---

#### Feature J — Debug Adapter Protocol

**What:** Step-through debugging for the March interpreter, with actor-aware features: step into an actor's message handler, inspect mailbox state, visualize actor lifecycle.

**Protocol:** DAP (Debug Adapter Protocol) — a separate TCP server from the LSP server, launched alongside the interpreter. Implements `initialize`, `launch`, `setBreakpoints`, `continue`, `next`, `stepIn`, `stackTrace`, `variables`, `evaluate`.

**Implementation sketch:**
1. Add a `--dap` flag to `bin/main.ml` that starts a DAP server on a port instead of running the interpreter directly.
2. Instrument `eval.ml` with a hook table: before each `eval_expr` call, check if the current span has a breakpoint set; if so, pause and notify the DAP client.
3. For actor debugging: extend the hook to also pause on actor message receipt and expose the mailbox queue as a DAP `variable` scope.

**Complexity:** Very High. DAP is a separate protocol (JSON-RPC over stdin/stdout or TCP). Actor debugging requires the evaluator to be re-entrant (pause mid-execution) — incompatible with the current recursive tree-walk evaluator. This feature requires either a trampoline-style evaluator or cooperative coroutines via OCaml 5's effects. Defer until after the compiler is code-generating.

---

#### Feature K — Type Hierarchy

**What:** Show subtype/supertype relationships for interfaces. E.g., if `Ord` extends `Eq`, navigate up/down the hierarchy. Show all types that implement a given interface.

**Protocol:**
- `typeHierarchy/supertypes` — interfaces that a given interface extends.
- `typeHierarchy/subtypes` — types/interfaces that extend a given interface.
- `textDocument/prepareTypeHierarchy` — resolve the item at cursor.

**Implementation sketch:**
1. Build `interface_hierarchy : string -> string list` (interface → list of super-interfaces it extends) during the typecheck pass.
2. Build `interface_impls : string -> string list` (interface → list of concrete types that implement it) from `impl_tbl`.
3. Wire into LSP handlers.

**Complexity:** Medium. The data is already present in the typechecker; the implementation is mostly wiring into LSP protocol types. Depends on Feature D (impl navigation) being done first.

---

### Implementation Order

| Priority | Feature | Depends on | Estimated effort |
|----------|---------|-----------|-----------------|
| P1 | D — Interface Impl Nav | `impl_tbl` spans | 1–2 days |
| P1 | E — Pipe Chain Types | Desugarer tagging | 1–2 days |
| P1 | B — Linear Consumption | `lin_entry` threading | 2–3 days |
| P1 | A — Actor Topology | AST walk | 2–3 days |
| P1 | C — Session Types | Typechecker threading | 4–6 days |
| P2 | I — Workspace Symbols | None | 1 day |
| P2 | G — Code Lens | A, D | 1 day |
| P2 | F — Semantic Tokens | `type_map`, `def_map` | 2 days |
| P2 | H — Call Hierarchy | `use_map` | 2 days |
| P3 | K — Type Hierarchy | D, typechecker | 2–3 days |
| P3 | J — Debug Adapter | Evaluator rewrite | weeks |
