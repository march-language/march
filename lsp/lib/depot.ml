(** Depot-library awareness for the March LSP.

    Provides schema extraction from [Depot.Schema.define] calls, query→schema
    resolution for column-name intelligence, and producers for diagnostics /
    completions / go-to-def / hover.  Intentionally library-agnostic: only
    depends on [March_ast.Ast]; helpers that live in [Analysis] are duplicated
    here to keep the dependency graph acyclic. *)

module Ast = March_ast.Ast

(* ------------------------------------------------------------------ *)
(* Types                                                               *)
(* ------------------------------------------------------------------ *)

type depot_field = {
  df_name      : string;
  df_name_span : Ast.span;
  df_type      : string;
}

type schema = {
  ds_table      : string;
  ds_table_span : Ast.span;
  ds_fields     : depot_field list;
  ds_pk         : string;
  ds_def_span   : Ast.span;
  ds_fn         : string option;
}

type col_occ = {
  co_col   : string;
  co_span  : Ast.span;
  co_table : string;
}

(* ------------------------------------------------------------------ *)
(* Local AST walker (mirrors Analysis.iter_expr; avoids circular dep) *)
(* ------------------------------------------------------------------ *)

let rec iter_expr (f : Ast.expr -> unit) (e : Ast.expr) =
  f e;
  match e with
  | Ast.EApp (g, args, _) -> iter_expr f g; List.iter (iter_expr f) args
  | Ast.ECon (_, args, _) | Ast.EAtom (_, args, _) | Ast.ETuple (args, _) ->
    List.iter (iter_expr f) args
  | Ast.ELam (_, body, _) | Ast.ELetFn (_, _, _, body, _) -> iter_expr f body
  | Ast.EBlock (es, _) -> List.iter (iter_expr f) es
  | Ast.ELet (b, _) -> iter_expr f b.Ast.bind_expr
  | Ast.EMatch (subj, brs, _) ->
    iter_expr f subj;
    List.iter (fun (br : Ast.branch) ->
        (match br.branch_guard with Some g -> iter_expr f g | None -> ());
        iter_expr f br.branch_body) brs
  | Ast.ECond (arms, _) ->
    List.iter (fun (c, b) -> iter_expr f c; iter_expr f b) arms
  | Ast.EIf (c, t, el, _) -> iter_expr f c; iter_expr f t; iter_expr f el
  | Ast.EPipe (l, r, _) | Ast.ESend (l, r, _) -> iter_expr f l; iter_expr f r
  | Ast.ERecord (fs, _) -> List.iter (fun (_, e2) -> iter_expr f e2) fs
  | Ast.ERecordUpdate (e2, fs, _) ->
    iter_expr f e2; List.iter (fun (_, e3) -> iter_expr f e3) fs
  | Ast.EField (e2, _, _) | Ast.EAnnot (e2, _, _)
  | Ast.ESpawn (e2, _) | Ast.EAssert (e2, _) | Ast.ESigil (_, e2, _)
  | Ast.EDbg (Some e2, _) -> iter_expr f e2
  | Ast.ELit _ | Ast.EVar _ | Ast.EHole _ | Ast.EResultRef _
  | Ast.EDbg (None, _) -> ()

let rec iter_decl_exprs (f : Ast.expr -> unit) (d : Ast.decl) =
  match d with
  | Ast.DFn (fn, _) ->
    List.iter (fun (cl : Ast.fn_clause) ->
        (match cl.fc_guard with Some g -> iter_expr f g | None -> ());
        iter_expr f cl.fc_body) fn.fn_clauses
  | Ast.DLet (_, b, _) -> iter_expr f b.Ast.bind_expr
  | Ast.DActor (_, _, adef, _) ->
    iter_expr f adef.Ast.actor_init;
    List.iter (fun (h : Ast.actor_handler) -> iter_expr f h.ah_body)
      adef.Ast.actor_handlers
  | Ast.DTest (t, _) -> iter_expr f t.Ast.test_body
  | Ast.DDescribe (_, decls, _) -> List.iter (iter_decl_exprs f) decls
  | Ast.DMod (_, _, decls, _) -> List.iter (iter_decl_exprs f) decls
  | _ -> ()

(* ------------------------------------------------------------------ *)
(* Helpers                                                             *)
(* ------------------------------------------------------------------ *)

(* Flatten a (possibly-qualified) callee expr to a dotted name.
   Handles EVar "Depot.Schema.define" (desugared) and
   EField(EField(EVar "Depot","Schema"),"define") (raw). *)
let rec callee_name (e : Ast.expr) : string option =
  match e with
  | Ast.EVar v -> Some v.Ast.txt
  | Ast.EField (obj, field, _) ->
    (match callee_name obj with
     | Some p -> Some (p ^ "." ^ field.Ast.txt)
     | None   -> Some field.Ast.txt)
  | _ -> None

(* True when [name] ends with [suffix] as a dotted segment. *)
let name_matches ~suffix name =
  name = suffix
  || (String.length name > String.length suffix
      && let cut = String.length name - String.length suffix in
         String.sub name cut (String.length suffix) = suffix
         && name.[cut - 1] = '.')

let string_lit (e : Ast.expr) : (string * Ast.span) option =
  match e with
  | Ast.ELit (Ast.LitString s, sp) -> Some (s, sp)
  | _ -> None

(* Parse the spec.fields record literal into a depot_field list.
   ERecord entries are (Ast.name * Ast.expr) — key is Ast.name, with its own span. *)
let fields_of_spec (spec : Ast.expr) : depot_field list =
  match spec with
  | Ast.ERecord (entries, _) ->
    (match List.find_opt (fun ((k : Ast.name), _) -> k.Ast.txt = "fields") entries with
     | Some (_, Ast.ERecord (fields, _)) ->
       List.filter_map (fun ((col : Ast.name), v) ->
         let ty =
           match v with
           | Ast.ELit (Ast.LitString t, _) -> t
           | Ast.ETuple (Ast.ELit (Ast.LitString t, _) :: _, _) -> t
           | _ -> "?"
         in
         Some { df_name = col.Ast.txt; df_name_span = col.Ast.span; df_type = ty })
         fields
     | _ -> [])
  | _ -> []

(* ------------------------------------------------------------------ *)
(* Schema extraction                                                   *)
(* ------------------------------------------------------------------ *)

let schemas_in (decls : Ast.decl list) : schema list =
  let out = ref [] in
  let cur_fn : string option ref = ref None in
  let visit (e : Ast.expr) =
    match e with
    | Ast.EApp (callee, args, call_sp) ->
      (match callee_name callee with
       | Some n when name_matches ~suffix:"Schema.define" n ->
         (match args with
          | tbl :: spec :: _ ->
            (match string_lit tbl with
             | Some (table, table_span) ->
               let fields = fields_of_spec spec in
               out := { ds_table = table; ds_table_span = table_span;
                        ds_fields = fields; ds_pk = "id";
                        ds_def_span = call_sp; ds_fn = !cur_fn } :: !out
             | None -> ())
          | _ -> ())
       | _ -> ())
    | _ -> ()
  in
  let rec dl (d : Ast.decl) =
    match d with
    | Ast.DFn (fn, _) ->
      List.iter (fun (cl : Ast.fn_clause) ->
        let prev = !cur_fn in
        cur_fn := Some fn.fn_name.Ast.txt;
        iter_expr visit cl.fc_body;
        cur_fn := prev) fn.fn_clauses
    | Ast.DMod (_, _, ds, _) | Ast.DDescribe (_, ds, _) -> List.iter dl ds
    | Ast.DLet (_, b, _) -> iter_expr visit b.Ast.bind_expr
    | _ -> ()
  in
  List.iter dl decls;
  List.rev !out

(* ------------------------------------------------------------------ *)
(* Query → schema resolution                                           *)
(* ------------------------------------------------------------------ *)

let sql_cond_fns =
  ["where_eq"; "where_ne"; "where_gt"; "where_gte"; "where_lt"; "where_lte";
   "where_like"; "where_ilike"; "where_is_null"; "where_is_not_null"]

let order_fns = ["order_asc"; "order_desc"; "order_by"]

let is_cond_fn name =
  List.exists (fun b -> name_matches ~suffix:("Query." ^ b) name) (sql_cond_fns @ order_fns)

let schema_has_column (schemas : schema list) ~table ~col =
  List.exists (fun s ->
    s.ds_table = table
    && List.exists (fun f -> f.df_name = col) s.ds_fields) schemas

(* Walk a query expression back to its source table name. Handles both the
   raw EPipe form and the desugared nested-EApp form. *)
let rec table_of_query (schemas : schema list) (e : Ast.expr) : string option =
  match e with
  | Ast.EPipe (lhs, _, _) -> table_of_query schemas lhs
  | Ast.EApp (callee, args, _) ->
    (match callee_name callee with
     | Some n when name_matches ~suffix:"Query.from_table" n ->
       (match args with t :: _ -> Option.map fst (string_lit t) | _ -> None)
     | Some n when name_matches ~suffix:"Query.from" n ->
       (match args with
        | arg :: _ ->
          (match arg with
           | Ast.EApp (f, _, _) ->
             (match callee_name f with
              | Some fname ->
                let short = match String.rindex_opt fname '.' with
                  | Some i -> String.sub fname (i + 1) (String.length fname - i - 1)
                  | None   -> fname
                in
                (match List.find_opt (fun s -> s.ds_fn = Some short) schemas with
                 | Some s -> Some s.ds_table
                 | None   -> None)
              | None -> None)
           | _ -> None)
        | _ -> None)
     | Some n when is_cond_fn n ->
       (match args with q :: _ -> table_of_query schemas q | _ -> None)
     | _ -> None)
  | _ -> None

(* Build a list of every column-name string literal that appears inside a
   Query.where_*/order_* call, tagged with the resolved table. *)
let column_occurrences (schemas : schema list) (decls : Ast.decl list) : col_occ list =
  let out = ref [] in
  let visit (e : Ast.expr) =
    match e with
    (* Pipe form: from(s) |> where_eq("col", v)
       The where_eq call's args are just ["col"; v]; resolve the table from lhs. *)
    | Ast.EPipe (lhs, (Ast.EApp (callee, args, _) as rhs_app), _) ->
      (match callee_name callee with
       | Some n when is_cond_fn n ->
         (match List.find_map string_lit args with
          | Some (col, sp) ->
            let q = match args with
              | q0 :: _ when string_lit q0 = None -> q0
              | _ -> rhs_app
            in
            let q = if q == rhs_app then lhs else q in
            (match table_of_query schemas q with
             | Some table -> out := { co_col = col; co_span = sp; co_table = table } :: !out
             | None -> ())
          | None -> ())
       | _ -> ())
    (* Desugared form: where_eq(from(s), "col", v) *)
    | Ast.EApp (callee, args, _) ->
      (match callee_name callee with
       | Some n when is_cond_fn n ->
         (match List.find_map string_lit args with
          | Some (col, sp) ->
            let q = match args with
              | q0 :: _ when string_lit q0 = None -> q0
              | _ -> e
            in
            (match table_of_query schemas q with
             | Some table -> out := { co_col = col; co_span = sp; co_table = table } :: !out
             | None -> ())
          | None -> ())
       | _ -> ())
    | _ -> ()
  in
  List.iter (iter_decl_exprs visit) decls;
  List.rev !out

(* ------------------------------------------------------------------ *)
(* Column diagnostics (B1)                                             *)
(* ------------------------------------------------------------------ *)

let levenshtein (a : string) (b : string) : int =
  let la = String.length a and lb = String.length b in
  if la = 0 then lb else if lb = 0 then la
  else begin
    let prev = Array.init (lb + 1) Fun.id in
    let curr = Array.make (lb + 1) 0 in
    for i = 1 to la do
      curr.(0) <- i;
      for j = 1 to lb do
        curr.(j) <-
          if a.[i - 1] = b.[j - 1] then prev.(j - 1)
          else 1 + min prev.(j) (min curr.(j - 1) prev.(j - 1))
      done;
      Array.blit curr 0 prev 0 (lb + 1)
    done;
    prev.(lb)
  end

(* Emit (span, message, code) for each col_occ on a known table whose column
   doesn't exist.  Conservatively silent when the table isn't in schemas. *)
let column_diagnostics (schemas : schema list) (occs : col_occ list)
    : (Ast.span * string * string) list =
  List.filter_map (fun (occ : col_occ) ->
    match List.find_opt (fun s -> s.ds_table = occ.co_table) schemas with
    | None -> None
    | Some schema ->
      if List.exists (fun f -> f.df_name = occ.co_col) schema.ds_fields then None
      else begin
        let suggestion =
          let (best_d, best_n) = List.fold_left (fun (bd, bn) f ->
            let d = levenshtein occ.co_col f.df_name in
            if d < bd then (d, f.df_name) else (bd, bn))
            (max_int, "") schema.ds_fields
          in
          if best_d <= 2 && best_n <> "" then
            Printf.sprintf " (did you mean `%s`?)" best_n
          else ""
        in
        let msg = Printf.sprintf "Unknown column `%s` on table `%s`%s"
          occ.co_col occ.co_table suggestion in
        Some (occ.co_span, msg, "depot/unknown-column")
      end)
    occs

(* ------------------------------------------------------------------ *)
(* Table occurrence index (B4)                                         *)
(* ------------------------------------------------------------------ *)

type table_occ = {
  to_table : string;
  to_span  : Ast.span;
  to_kind  : [ `FromTable | `Migration ];
}

let migration_table_fns =
  ["create_table"; "alter_table"; "drop_table"; "create_index";
   "create_index_simple"; "references"]

let table_occurrences (decls : Ast.decl list) : table_occ list =
  let out = ref [] in
  let visit (e : Ast.expr) =
    match e with
    | Ast.EApp (callee, args, _) ->
      (match callee_name callee with
       | Some n ->
         let is_from_table = name_matches ~suffix:"Query.from_table" n in
         let is_mig = List.exists
           (fun b -> name_matches ~suffix:("Migration." ^ b) n) migration_table_fns in
         if is_from_table || is_mig then
           (match args with
            | tbl :: _ ->
              (match string_lit tbl with
               | Some (table, sp) ->
                 let kind = if is_from_table then `FromTable else `Migration in
                 out := { to_table = table; to_span = sp; to_kind = kind } :: !out
               | None -> ())
            | _ -> ())
       | None -> ())
    | _ -> ()
  in
  List.iter (iter_decl_exprs visit) decls;
  List.rev !out

let table_diagnostics (schemas : schema list) (occs : table_occ list)
    : (Ast.span * string * string) list =
  if schemas = [] then []
  else
    List.filter_map (fun (occ : table_occ) ->
      if List.exists (fun s -> s.ds_table = occ.to_table) schemas then None
      else begin
        let suggestion =
          let (best_d, best_n) = List.fold_left (fun (bd, bn) s ->
            let d = levenshtein occ.to_table s.ds_table in
            if d < bd then (d, s.ds_table) else (bd, bn))
            (max_int, "") schemas
          in
          if best_d <= 2 && best_n <> "" then
            Printf.sprintf " (did you mean `%s`?)" best_n
          else ""
        in
        let msg = Printf.sprintf "Unknown table `%s`%s" occ.to_table suggestion in
        Some (occ.to_span, msg, "depot/unknown-table")
      end)
    occs

(* ------------------------------------------------------------------ *)
(* Migration model (C1)                                                *)
(* ------------------------------------------------------------------ *)

type mig_op =
  | CreateTable of { table : string; cols : (string * string) list; span : Ast.span }
  | AlterTable  of { table : string; adds : (string * string) list;
                     removes : string list; span : Ast.span }
  | CreateIndex of { table : string; cols : string list; span : Ast.span }
  | References  of { table : string; column : string; span : Ast.span }

let migration_ops (decls : Ast.decl list) : mig_op list =
  let out = ref [] in
  let parse_cols spec =
    match spec with
    | Ast.ERecord (entries, _) ->
      List.filter_map (fun ((k : Ast.name), v) ->
        let ty = match v with
          | Ast.ELit (Ast.LitString t, _) -> t
          | Ast.ETuple (Ast.ELit (Ast.LitString t, _) :: _, _) -> t
          | _ -> "?"
        in
        Some (k.Ast.txt, ty)) entries
    | _ -> []
  in
  let visit (e : Ast.expr) =
    match e with
    | Ast.EApp (callee, args, sp) ->
      (match callee_name callee with
       | Some n ->
         if name_matches ~suffix:"Migration.create_table" n then
           (match args with
            | tbl :: spec :: _ ->
              (match string_lit tbl with
               | Some (table, _) ->
                 out := CreateTable { table; cols = parse_cols spec; span = sp } :: !out
               | None -> ())
            | _ -> ())
         else if name_matches ~suffix:"Migration.alter_table" n then
           (match args with
            | tbl :: spec :: _ ->
              (match string_lit tbl with
               | Some (table, _) ->
                 let adds = match spec with
                   | Ast.ERecord (entries, _) ->
                     (match List.find_opt (fun ((k:Ast.name),_) -> k.Ast.txt = "add") entries with
                      | Some (_, add_rec) -> parse_cols add_rec
                      | None -> [])
                   | _ -> []
                 in
                 let removes = match spec with
                   | Ast.ERecord (entries, _) ->
                     (match List.find_opt (fun ((k:Ast.name),_) -> k.Ast.txt = "remove") entries with
                      | Some (_, Ast.ETuple (elts, _)) ->
                        List.filter_map (fun e ->
                          match string_lit e with Some (s, _) -> Some s | None -> None) elts
                      | _ -> [])
                   | _ -> []
                 in
                 out := AlterTable { table; adds; removes; span = sp } :: !out
               | None -> ())
            | _ -> ())
         else if name_matches ~suffix:"Migration.create_index" n
              || name_matches ~suffix:"Migration.create_index_simple" n then
           (match args with
            | tbl :: cols_arg :: _ ->
              (match string_lit tbl with
               | Some (table, _) ->
                 let cols = match cols_arg with
                   | Ast.ETuple (elts, _) ->
                     List.filter_map (fun e ->
                       match string_lit e with Some (s, _) -> Some s | None -> None) elts
                   | _ -> []
                 in
                 out := CreateIndex { table; cols; span = sp } :: !out
               | None -> ())
            | _ -> ())
         else if name_matches ~suffix:"Migration.references" n then
           (match args with
            | tbl :: spec :: _ ->
              (match string_lit tbl with
               | Some (table, _) ->
                 let column = match spec with
                   | Ast.ERecord (entries, _) ->
                     (match List.find_opt (fun ((k:Ast.name),_) -> k.Ast.txt = "column") entries with
                      | Some (_, col_e) ->
                        (match string_lit col_e with Some (c, _) -> c | None -> "")
                      | None -> "")
                   | _ -> ""
                 in
                 out := References { table; column; span = sp } :: !out
               | None -> ())
            | _ -> ())
       | None -> ())
    | _ -> ()
  in
  List.iter (iter_decl_exprs visit) decls;
  List.rev !out

(* ------------------------------------------------------------------ *)
(* Schema-drift diagnostics (C2)                                       *)
(* ------------------------------------------------------------------ *)

let schema_drift_diagnostics (schemas : schema list) (ops : mig_op list)
    (occs : col_occ list) : (Ast.span * string * string) list =
  let diags = ref [] in
  List.iter (fun (s : schema) ->
    let table_ops = List.filter (function
      | CreateTable { table; _ } | AlterTable { table; _ }
      | CreateIndex { table; _ } | References { table; _ } -> table = s.ds_table) ops
    in
    if table_ops = [] then ()
    else begin
      (* Column in a query but not in any migration *)
      List.iter (fun (occ : col_occ) ->
        if occ.co_table = s.ds_table then
          let created_by_mig = List.exists (function
            | CreateTable { table; cols; _ } when table = s.ds_table ->
              List.exists (fun (c, _) -> c = occ.co_col) cols
            | AlterTable { table; adds; _ } when table = s.ds_table ->
              List.exists (fun (c, _) -> c = occ.co_col) adds
            | _ -> false) ops
          in
          if not created_by_mig then
            diags := (occ.co_span,
              Printf.sprintf "Column `%s` on `%s` has no migration creating it"
                occ.co_col s.ds_table,
              "depot/missing-migration") :: !diags)
        occs;
      (* Column in a CreateTable migration but not in the schema *)
      List.iter (function
        | CreateTable { table; cols; span } when table = s.ds_table ->
          List.iter (fun (col, _) ->
            if not (List.exists (fun f -> f.df_name = col) s.ds_fields) then
              diags := (span,
                Printf.sprintf "Migration column `%s` on `%s` not found in schema"
                  col table,
                "depot/schema-drift") :: !diags) cols
        | _ -> ()) ops
    end)
    schemas;
  List.rev !diags

(* ------------------------------------------------------------------ *)
(* FK column diagnostics (C4)                                          *)
(* ------------------------------------------------------------------ *)

let fk_column_diagnostics (schemas : schema list) (ops : mig_op list)
    : (Ast.span * string * string) list =
  if schemas = [] then []
  else
    List.filter_map (function
      | References { table; column; span } when column <> "" ->
        (match List.find_opt (fun s -> s.ds_table = table) schemas with
         | None -> None
         | Some schema ->
           if List.exists (fun f -> f.df_name = column) schema.ds_fields then None
           else
             let suggestion =
               let (best_d, best_n) = List.fold_left (fun (bd, bn) f ->
                 let d = levenshtein column f.df_name in
                 if d < bd then (d, f.df_name) else (bd, bn))
                 (max_int, "") schema.ds_fields
               in
               if best_d <= 2 && best_n <> "" then
                 Printf.sprintf " (did you mean `%s`?)" best_n
               else ""
             in
             Some (span,
               Printf.sprintf "Unknown FK column `%s` on table `%s`%s" column table suggestion,
               "depot/unknown-fk-column"))
      | _ -> None)
    ops

(* ------------------------------------------------------------------ *)
(* SQL injection warning (D1)                                          *)
(* ------------------------------------------------------------------ *)

let sql_injection_diagnostics (decls : Ast.decl list) : (Ast.span * string * string) list =
  let out = ref [] in
  let visit (e : Ast.expr) =
    match e with
    | Ast.EApp (callee, args, _) ->
      (match callee_name callee with
       | Some n when name_matches ~suffix:"Connection.simple_query" n
                  || name_matches ~suffix:"Query.execute" n ->
         (* sql arg is 2nd arg (index 1) for simple_query(conn, sql),
            or 1st arg (index 0) for execute(query). *)
         let sql_arg = match args with
           | _ :: sql :: _ -> Some sql
           | sql :: _      -> Some sql
           | []            -> None
         in
         (match sql_arg with
          | Some (Ast.ELit (Ast.LitString _, _)) -> ()
          | Some arg ->
            let sp = match arg with
              | Ast.ELit (_, sp) | Ast.EVar { Ast.span = sp; _ }
              | Ast.EApp (_, _, sp) | Ast.EPipe (_, _, sp) -> sp
              | _ -> Ast.dummy_span
            in
            out := (sp,
              "Non-parameterized SQL: use exec_prepared with bound parameters",
              "depot/sql-injection") :: !out
          | None -> ())
       | _ -> ())
    | _ -> ()
  in
  List.iter (iter_decl_exprs visit) decls;
  List.rev !out
