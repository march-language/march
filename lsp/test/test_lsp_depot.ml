(** March LSP tests: depot-aware analysis (Phase A) and capability tooling (Phase 3f)

    Moved verbatim out of [test_lsp.ml]; see [Test_lsp_harness]. *)

open Test_lsp_harness

(* ------------------------------------------------------------------ *)
(* Depot-aware LSP: Phase A — foundation                              *)
(* ------------------------------------------------------------------ *)

module Depot = March_lsp_lib.Depot

let test_depot_schema_extract () =
  let src = {|mod M do
  fn user_schema() do
    Depot.Schema.define("users", { fields: { name: "String", age: ("Int", { default: 0 }) } })
  end
end|} in
  let a = analyse src in
  match Depot.schemas_in a.An.depot_source_decls with
  | [s] ->
    Alcotest.(check string) "table" "users" s.Depot.ds_table;
    let cols = List.map (fun (f : Depot.depot_field) -> f.Depot.df_name) s.Depot.ds_fields in
    Alcotest.(check (list string)) "columns" ["name"; "age"] cols
  | other -> Alcotest.failf "expected exactly one schema, got %d" (List.length other)

let test_query_schema_resolution () =
  (* Use from_table (simpler resolution path) *)
  let src = {|mod M do
  fn s() do
    Depot.Schema.define("users", { fields: { name: "String", age: ("Int", { default: 0 }) } })
  end
  fn q() do
    Depot.Query.from_table("users") |> Depot.Query.where_eq("age", "18")
  end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "age in users schema" true
    (Depot.schema_has_column a.An.depot_schemas ~table:"users" ~col:"age");
  Alcotest.(check bool) "col_occ for 'age' present (pipe + from_table)" true
    (List.exists (fun (o : Depot.col_occ) -> o.Depot.co_col = "age" && o.Depot.co_table = "users")
       a.An.depot_col_occs)

let test_query_schema_resolution_from_fn () =
  (* Use from(schema_fn()) path - resolves schema by fn name *)
  let src = {|mod M do
  fn user_schema() do
    Depot.Schema.define("users", { fields: { email: "String", age: ("Int", { default: 0 }) } })
  end
  fn q() do
    Depot.Query.from(user_schema()) |> Depot.Query.where_eq("email", "x")
  end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "col_occ for 'email' via from(fn())" true
    (List.exists (fun (o : Depot.col_occ) -> o.Depot.co_col = "email" && o.Depot.co_table = "users")
       a.An.depot_col_occs)

let test_depot_schemas_field () =
  let src = {|mod M do
  fn user_schema() do
    Depot.Schema.define("users", { fields: { name: "String" } })
  end
end|} in
  let a = analyse src in
  Alcotest.(check int) "one schema on the analysis record" 1 (List.length a.An.depot_schemas)

let test_depot_column_completion () =
  let src = {|mod M do
  fn s() do Depot.Schema.define("users", { fields: { name: "String", age: ("Int", { default: 0 }) } }) end
  fn q() do
    Depot.Query.from_table("users") |> Depot.Query.where_eq("ag", "18")
  end
end|} in
  let a = analyse src in
  (* verify col_occs and schemas first *)
  Alcotest.(check bool) "depot_col_occs non-empty" true (a.An.depot_col_occs <> []);
  Alcotest.(check bool) "depot_schemas non-empty" true (a.An.depot_schemas <> []);
  (* find cursor inside "ag" — position of the 'a' in "ag" *)
  let (line, col) = pos_of src "\"ag\"" in
  let items = An.completions_at a ~line ~character:(col + 1) in
  let labels = List.map (fun (i : Lsp.Types.CompletionItem.t) -> i.label) items in
  Alcotest.(check bool) "age in column completions" true (List.mem "age" labels);
  Alcotest.(check bool) "name in column completions" true (List.mem "name" labels)

let test_depot_column_completion_no_dilution () =
  (* When inside a column-arg string, ONLY column names should be returned *)
  let src = {|mod M do
  fn s() do Depot.Schema.define("users", { fields: { email: "String" } }) end
  fn q() do
    Depot.Query.from_table("users") |> Depot.Query.where_eq("em", "x")
  end
end|} in
  let a = analyse src in
  let (line, col) = pos_of src "\"em\"" in
  let items = An.completions_at a ~line ~character:(col + 1) in
  let labels = List.map (fun (i : Lsp.Types.CompletionItem.t) -> i.label) items in
  Alcotest.(check bool) "email in column completions" true (List.mem "email" labels);
  (* Generic keywords should NOT appear when inside column string *)
  Alcotest.(check bool) "no 'fn' keyword when inside column string" false (List.mem "fn" labels)

let test_depot_unknown_column () =
  let src = {|mod M do
  fn s() do Depot.Schema.define("users", { fields: { age: ("Int", { default: 0 }) } }) end
  fn q() do Depot.Query.from_table("users") |> Depot.Query.where_eq("ag", "18") end
end|} in
  let a = analyse src in
  let has = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.code with
    | Some (`String "depot/unknown-column") -> true | _ -> false) a.An.diagnostics in
  Alcotest.(check bool) "typo'd column flagged" true has

let test_depot_known_column_not_flagged () =
  let src = {|mod M do
  fn s() do Depot.Schema.define("users", { fields: { age: ("Int", { default: 0 }) } }) end
  fn q() do Depot.Query.from_table("users") |> Depot.Query.where_eq("age", "18") end
end|} in
  let a = analyse src in
  let has = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.code with
    | Some (`String "depot/unknown-column") -> true | _ -> false) a.An.diagnostics in
  Alcotest.(check bool) "known column not flagged" false has

let test_depot_unresolved_schema_not_flagged () =
  (* No schema in scope: conservative — do not flag *)
  let src = {|mod M do
  fn q() do Depot.Query.from_table("users") |> Depot.Query.where_eq("bogus", "x") end
end|} in
  let a = analyse src in
  let has = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.code with
    | Some (`String "depot/unknown-column") -> true | _ -> false) a.An.diagnostics in
  Alcotest.(check bool) "unresolvable table not flagged" false has

let test_imported_decls_retained () =
  let src = {|mod App do
  fn user_schema() do
    Depot.Schema.define("users", { fields: { name: "String", age: ("Int", { default: 0 }) } })
  end
  fn list_users() do
    Depot.Query.from(user_schema())
  end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "analysis exposes decls for the Depot pass" true
    (List.length a.An.depot_source_decls > 0)

let test_depot_table_completion () =
  let src = {|mod M do
  fn s() do Depot.Schema.define("users", { fields: { name: "String" } }) end
  fn q() do Depot.Query.from_table("us") end
end|} in
  let a = analyse src in
  let (line, col) = pos_of src {|"us"|} in
  let items = An.completions_at a ~line ~character:(col + 1) in
  let labels = List.map (fun (i : Lsp.Types.CompletionItem.t) -> i.label) items in
  Alcotest.(check bool) "users in table completions" true (List.mem "users" labels)

let test_depot_unknown_table () =
  let src = {|mod M do
  fn s() do Depot.Schema.define("users", { fields: { name: "String" } }) end
  fn q() do Depot.Query.from_table("bogus") end
end|} in
  let a = analyse src in
  let has = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.code with
    | Some (`String "depot/unknown-table") -> true | _ -> false) a.An.diagnostics in
  Alcotest.(check bool) "unknown table flagged" true has

let test_depot_migration_ops () =
  let src = {|mod M do
  fn m1() do
    Depot.Migration.create_table("users", { name: "String", age: "Int" })
  end
  fn m2() do
    Depot.Migration.alter_table("users", { add: { score: "Float" }, remove: ["old_col"] })
  end
end|} in
  let a = analyse src in
  let ops = Depot.migration_ops a.An.depot_source_decls in
  Alcotest.(check bool) "at least one CreateTable" true
    (List.exists (function Depot.CreateTable { table; _ } -> table = "users" | _ -> false) ops);
  Alcotest.(check bool) "at least one AlterTable" true
    (List.exists (function Depot.AlterTable { table; _ } -> table = "users" | _ -> false) ops)

let test_depot_schema_drift () =
  let src = {|mod M do
  fn s() do
    Depot.Schema.define("users", { fields: { name: "String" } })
  end
  fn mig() do
    Depot.Migration.create_table("users", { name: "String", age: "Int" })
  end
  fn q() do
    Depot.Query.from_table("users") |> Depot.Query.where_eq("name", "Alice")
  end
end|} in
  let a = analyse src in
  let has_drift = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.code with
    | Some (`String "depot/schema-drift") -> true | _ -> false) a.An.diagnostics in
  Alcotest.(check bool) "age in migration but not in schema => depot/schema-drift" true has_drift

let test_depot_no_drift_when_aligned () =
  let src = {|mod M do
  fn s() do
    Depot.Schema.define("users", { fields: { name: "String", age: "Int" } })
  end
  fn mig() do
    Depot.Migration.create_table("users", { name: "String", age: "Int" })
  end
  fn q() do
    Depot.Query.from_table("users") |> Depot.Query.where_eq("name", "Alice")
  end
end|} in
  let a = analyse src in
  let has_drift = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.code with
    | Some (`String "depot/schema-drift")
    | Some (`String "depot/missing-migration") -> true | _ -> false) a.An.diagnostics in
  Alcotest.(check bool) "aligned schema+migration not flagged" false has_drift

let test_depot_fk_column_valid () =
  let src = {|mod M do
  fn s() do
    Depot.Schema.define("posts", { fields: { post_id: "Int", title: "String" } })
  end
  fn mig() do
    Depot.Migration.references("posts", { column: "post_id" })
  end
end|} in
  let a = analyse src in
  let has_fk_err = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.code with
    | Some (`String "depot/unknown-fk-column") -> true | _ -> false) a.An.diagnostics in
  Alcotest.(check bool) "valid FK column not flagged" false has_fk_err

let test_depot_fk_column_invalid () =
  let src = {|mod M do
  fn s() do
    Depot.Schema.define("posts", { fields: { post_id: "Int" } })
  end
  fn mig() do
    Depot.Migration.references("posts", { column: "bogus_id" })
  end
end|} in
  let a = analyse src in
  let has_fk_err = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.code with
    | Some (`String "depot/unknown-fk-column") -> true | _ -> false) a.An.diagnostics in
  Alcotest.(check bool) "invalid FK column flagged" true has_fk_err

let test_depot_col_hover () =
  let src = {|mod M do
  fn s() do Depot.Schema.define("users", { fields: { age: ("Int", { default: 0 }) } }) end
  fn q() do Depot.Query.from_table("users") |> Depot.Query.where_eq("age", "18") end
end|} in
  let a = analyse src in
  let (line, col) = pos_of src "\"age\"" in
  let ty = An.type_at a ~line ~character:(col + 1) in
  Alcotest.(check (option string)) "hover on column string shows Depot field type"
    (Some "Int") ty

let test_depot_col_def () =
  let src = {|mod M do
  fn s() do Depot.Schema.define("users", { fields: { age: ("Int", { default: 0 }) } }) end
  fn q() do Depot.Query.from_table("users") |> Depot.Query.where_eq("age", "18") end
end|} in
  let a = analyse src in
  let (line, col) = pos_of src "\"age\"" in
  let loc = An.definition_at a ~line ~character:(col + 1) in
  Alcotest.(check bool) "def on column string finds schema field" true (loc <> None)

(* ------------------------------------------------------------------ *)
(* Capability tooling (Phase 3f)                                       *)
(* ------------------------------------------------------------------ *)

let test_proof_cap_defs_registered () =
  (* Sanity check: proof_cap_defs contains the declared cap name, and the
     def_map and use_map are populated even when the typechecker adds errors. *)
  let src = {|mod M do
  proof cap Foo
end|} in
  let a = analyse src in
  Alcotest.(check int) "no parse errors" 0 (List.length a.An.diagnostics);
  Alcotest.(check bool) "proof_cap_defs has Foo" true (Hashtbl.mem a.An.proof_cap_defs "Foo");
  Alcotest.(check bool) "def_map has Foo" true (Hashtbl.mem a.An.def_map "Foo")

let test_proof_cap_goto_def () =
  (* proof cap Foo declares "Foo"; fn f(c: Cap(Foo)) uses it.
     Go-to-def on the Cap(Foo) annotation should resolve to the declaration. *)
  let src = {|mod M do
  proof cap Foo
  fn f(c : Cap(Foo)) : Int do 1 end
end|} in
  let a = analyse src in
  (* pos_of lands on the first char of "Foo)" in the type annotation *)
  let (line, col) = pos_of src "Foo)" in
  let loc = An.definition_at a ~line ~character:col in
  Alcotest.(check bool) "Cap(Foo) annotation resolves to proof cap declaration" true (loc <> None)

let test_proof_cap_find_refs () =
  (* proof cap Bar declared once; two functions carry Cap(Bar) params.
     find-references at the declaration span should find both uses. *)
  let src = {|mod M do
  proof cap Bar
  fn f(c : Cap(Bar)) : Int do 1 end
  fn g(c : Cap(Bar)) : Int do 2 end
end|} in
  let a = analyse src in
  let (line, col) = pos_of src "proof cap Bar" in
  let col = col + 10 in  (* skip "proof cap " to land on 'B' of Bar *)
  let refs = An.references_at a ~include_declaration:false ~line ~character:col in
  Alcotest.(check bool) "two Cap(Bar) uses found" true (List.length refs >= 2)

let test_cap_inlay_hints () =
  (* A module with `needs IO.Console` should emit a ⬡ IO.Console hint
     at println() call sites when perf_annotations is on. *)
  let src = {|mod M do
  needs IO.Console
  fn greet() do
    println("hello")
  end
end|} in
  let a = analyse src in
  let range = Lsp.Types.Range.create
      ~start:(Lsp.Types.Position.create ~line:0 ~character:0)
      ~end_:(Lsp.Types.Position.create ~line:10 ~character:0)
  in
  let hints = An.inlay_hints_for ~perf_annotations:true a range in
  let has_cap_hint = List.exists (fun (h : Lsp.Types.InlayHint.t) ->
      match h.label with
      | `String s -> contains_sub s "IO.Console"
      | _ -> false) hints in
  Alcotest.(check bool) "IO.Console hint emitted for println in needs module" true has_cap_hint

