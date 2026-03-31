(** March phase dumper.

    Serialises each compiler IR stage to a JSON graph consumable by
    tools/phase-viewer.html.  Each phase is represented as:

      { "phase": "<name>",
        "nodes": [ { "id", "label", "type", "metadata" } … ],
        "edges": [ { "source", "target", "label" } … ] }

    The complete run is written to [march-phases/phases.json] as:

      { "source_file": "<path>", "phases": [ … ] }
*)

open March_ast.Ast

(* ------------------------------------------------------------------ *)
(* Minimal JSON helpers                                                *)
(* ------------------------------------------------------------------ *)

let json_string s =
  let buf = Buffer.create (String.length s + 2) in
  Buffer.add_char buf '"';
  String.iter (function
    | '"'  -> Buffer.add_string buf "\\\""
    | '\\' -> Buffer.add_string buf "\\\\"
    | '\n' -> Buffer.add_string buf "\\n"
    | '\r' -> Buffer.add_string buf "\\r"
    | '\t' -> Buffer.add_string buf "\\t"
    | c when Char.code c < 32 ->
      Buffer.add_string buf (Printf.sprintf "\\u%04x" (Char.code c))
    | c    -> Buffer.add_char buf c
  ) s;
  Buffer.add_char buf '"';
  Buffer.contents buf

let json_obj fields =
  "{" ^ String.concat "," (List.map (fun (k, v) ->
    json_string k ^ ":" ^ v
  ) fields) ^ "}"

let json_list items =
  "[" ^ String.concat "," items ^ "]"

(* ------------------------------------------------------------------ *)
(* Graph types                                                         *)
(* ------------------------------------------------------------------ *)

type node = {
  n_id    : string;
  n_label : string;
  n_type  : string;
  n_meta  : (string * string) list;  (* key → already-encoded JSON value *)
}

type edge = {
  e_src   : string;
  e_dst   : string;
  e_label : string;
}

let node_to_json n =
  json_obj [
    "id",       json_string n.n_id;
    "label",    json_string n.n_label;
    "type",     json_string n.n_type;
    "metadata", json_obj n.n_meta;
  ]

let edge_to_json e =
  json_obj [
    "source", json_string e.e_src;
    "target", json_string e.e_dst;
    "label",  json_string e.e_label;
  ]

let phase_to_json name nodes edges =
  json_obj [
    "phase", json_string name;
    "nodes", json_list (List.map node_to_json nodes);
    "edges", json_list (List.map edge_to_json edges);
  ]

(* ------------------------------------------------------------------ *)
(* Counter for unique IDs within a phase                              *)
(* ------------------------------------------------------------------ *)

let counter = ref 0
let reset_counter () = counter := 0
let new_id prefix = incr counter; Printf.sprintf "%s_%d" prefix !counter

(* ------------------------------------------------------------------ *)
(* Pretty-print helpers                                                *)
(* ------------------------------------------------------------------ *)

let rec ty_to_str = function
  | TyCon (n, [])   -> n.txt
  | TyCon (n, args) -> n.txt ^ "(" ^ String.concat ", " (List.map ty_to_str args) ^ ")"
  | TyVar n         -> "'" ^ n.txt
  | TyArrow (a, b)  -> ty_to_str a ^ " -> " ^ ty_to_str b
  | TyTuple ts      -> "(" ^ String.concat ", " (List.map ty_to_str ts) ^ ")"
  | TyRecord fields -> "{ " ^ String.concat ", " (List.map (fun (n, t) ->
      n.txt ^ ": " ^ ty_to_str t) fields) ^ " }"
  | TyLinear (_, t) -> ty_to_str t
  | TyNat n         -> string_of_int n
  | TyNatOp (_, a, b) -> ty_to_str a ^ " op " ^ ty_to_str b
  | TyChan (r, p)   -> "Chan(" ^ r.txt ^ ", " ^ p.txt ^ ")"

let param_to_str p =
  match p.param_ty with
  | None -> p.param_name.txt
  | Some t -> p.param_name.txt ^ ": " ^ ty_to_str t

let fn_param_to_str = function
  | FPPat pat  ->
    (match pat with
     | PatWild _     -> "_"
     | PatVar n      -> n.txt
     | PatLit (LitInt i, _)    -> string_of_int i
     | PatLit (LitString s, _) -> "\"" ^ String.escaped s ^ "\""
     | PatLit (LitBool b, _)   -> string_of_bool b
     | _             -> "_")
  | FPNamed p  -> param_to_str p
  | FPDefault (p, _) -> param_to_str p ^ " \\\\ _"

(* Collect names of functions directly called inside an expression.
   Only top-level calls are tracked (not recursive descent into every arm)
   to keep the edge set manageable. *)
let rec calls_in_expr acc = function
  | EApp (EVar n, _, _)  -> n.txt :: acc
  | EApp (f, args, _)    ->
    let acc = calls_in_expr acc f in
    List.fold_left calls_in_expr acc args
  | ELet (b, _)          -> calls_in_expr acc b.bind_expr
  | ELetFn (_, _, _, body, _) -> calls_in_expr acc body
  | EBlock (es, _)        -> List.fold_left calls_in_expr acc es
  | EMatch (e, arms, _)  ->
    let acc = calls_in_expr acc e in
    List.fold_left (fun a br -> calls_in_expr a br.branch_body) acc arms
  | EIf (c, t, e, _)     ->
    calls_in_expr (calls_in_expr (calls_in_expr acc c) t) e
  | EPipe (a, b, _)       -> calls_in_expr (calls_in_expr acc a) b
  | ECon (_, args, _)     -> List.fold_left calls_in_expr acc args
  | ETuple (es, _)        -> List.fold_left calls_in_expr acc es
  | ERecord (fs, _)       -> List.fold_left (fun a (_, e) -> calls_in_expr a e) acc fs
  | ERecordUpdate (e, fs, _) ->
    let acc = calls_in_expr acc e in
    List.fold_left (fun a (_, e2) -> calls_in_expr a e2) acc fs
  | EField (e, _, _)      -> calls_in_expr acc e
  | EAnnot (e, _, _)      -> calls_in_expr acc e
  | ECond (arms, _)       ->
    List.fold_left (fun a (c, b) -> calls_in_expr (calls_in_expr a c) b) acc arms
  | ESend (a, b, _)       -> calls_in_expr (calls_in_expr acc a) b
  | ESigil (_, e, _)      -> calls_in_expr acc e
  | _                     -> acc

(* ------------------------------------------------------------------ *)
(* AST phase serialiser                                                *)
(* ------------------------------------------------------------------ *)

(** Produce nodes+edges for the parsed/desugared AST.
    One node per top-level declaration; call edges from fn bodies. *)
let ast_phase (m : module_) phase_name =
  reset_counter ();
  let nodes = ref [] in
  let edges = ref [] in

  (* Module root node *)
  let mod_id = "mod_" ^ m.mod_name.txt in
  nodes := {
    n_id    = mod_id;
    n_label = "mod " ^ m.mod_name.txt;
    n_type  = "module";
    n_meta  = [];
  } :: !nodes;

  let add_edge src dst lbl =
    edges := { e_src = src; e_dst = dst; e_label = lbl } :: !edges
  in

  let rec visit_decls parent decls =
    List.iter (visit_decl parent) decls

  and visit_decl parent = function
    | DFn (fd, _) ->
      let id = "fn_" ^ fd.fn_name.txt in
      let params =
        match fd.fn_clauses with
        | c :: _ -> String.concat ", " (List.map fn_param_to_str c.fc_params)
        | []     -> ""
      in
      let sig_str =
        match fd.fn_ret_ty with
        | None   -> "fn " ^ fd.fn_name.txt ^ "(" ^ params ^ ")"
        | Some t -> "fn " ^ fd.fn_name.txt ^ "(" ^ params ^ "): " ^ ty_to_str t
      in
      let body_calls =
        match fd.fn_clauses with
        | c :: _ -> calls_in_expr [] c.fc_body
        | []     -> []
      in
      nodes := {
        n_id    = id;
        n_label = sig_str;
        n_type  = if fd.fn_vis = Public then "fn_pub" else "fn_priv";
        n_meta  = [
          "arity",  json_string (string_of_int
            (match fd.fn_clauses with c :: _ -> List.length c.fc_params | [] -> 0));
          "clauses", json_string (string_of_int (List.length fd.fn_clauses));
          "calls",  json_list (List.map json_string
            (List.sort_uniq String.compare body_calls));
        ];
      } :: !nodes;
      add_edge parent id "decl";
      (* call edges - best-effort; targets may not exist as IDs *)
      List.iter (fun callee ->
        edges := { e_src = id; e_dst = "fn_" ^ callee ^ "_1"; e_label = "calls" }
          :: !edges
      ) (List.sort_uniq String.compare body_calls)

    | DType (vis, name, _tvars, tdef, _) ->
      let id = "type_" ^ name.txt in
      let detail = match tdef with
        | TDAlias t  -> "alias " ^ ty_to_str t
        | TDVariant vs ->
          String.concat " | " (List.map (fun v ->
            match v.var_args with
            | [] -> v.var_name.txt
            | ts -> v.var_name.txt ^ "(" ^
                    String.concat ", " (List.map ty_to_str ts) ^ ")"
          ) vs)
        | TDRecord fs ->
          "{ " ^ String.concat ", " (List.map (fun f ->
            f.fld_name.txt ^ ": " ^ ty_to_str f.fld_ty
          ) fs) ^ " }"
      in
      nodes := {
        n_id    = id;
        n_label = "type " ^ name.txt;
        n_type  = if vis = Public then "type_pub" else "type_priv";
        n_meta  = ["detail", json_string detail];
      } :: !nodes;
      add_edge parent id "decl"

    | DMod (name, _vis, decls, _) ->
      let id = "mod_" ^ name.txt in
      nodes := {
        n_id    = id;
        n_label = "mod " ^ name.txt;
        n_type  = "module";
        n_meta  = [];
      } :: !nodes;
      add_edge parent id "contains";
      visit_decls id decls

    | DActor (vis, name, _def, _) ->
      let id = "actor_" ^ name.txt in
      nodes := {
        n_id    = id;
        n_label = "actor " ^ name.txt;
        n_type  = if vis = Public then "actor_pub" else "actor_priv";
        n_meta  = [];
      } :: !nodes;
      add_edge parent id "decl"

    | DInterface (idef, _) ->
      let id = "iface_" ^ idef.March_ast.Ast.iface_name.txt in
      nodes := {
        n_id    = id;
        n_label = "interface " ^ idef.March_ast.Ast.iface_name.txt;
        n_type  = "interface";
        n_meta  = [];
      } :: !nodes;
      add_edge parent id "decl"

    | DImpl (iimpl, _) ->
      let id = "impl_" ^ iimpl.March_ast.Ast.impl_iface.txt in
      nodes := {
        n_id    = id;
        n_label = "impl " ^ iimpl.March_ast.Ast.impl_iface.txt;
        n_type  = "impl";
        n_meta  = [];
      } :: !nodes;
      add_edge parent id "decl"

    | DTest (td, _) ->
      let id = new_id "test" in
      nodes := {
        n_id    = id;
        n_label = "test \"" ^ String.escaped td.test_name ^ "\"";
        n_type  = "test";
        n_meta  = [];
      } :: !nodes;
      add_edge parent id "decl"

    | DDescribe (name, _decls, _) ->
      let id = new_id "describe" in
      nodes := {
        n_id    = id;
        n_label = "describe \"" ^ String.escaped name ^ "\"";
        n_type  = "describe";
        n_meta  = [];
      } :: !nodes;
      add_edge parent id "decl"

    | DLet (vis, b, _) ->
      let id = new_id "let" in
      let pat_str = match b.bind_pat with
        | PatVar n -> n.txt | PatWild _ -> "_" | _ -> "pat"
      in
      nodes := {
        n_id    = id;
        n_label = "let " ^ pat_str;
        n_type  = if vis = Public then "let_pub" else "let_priv";
        n_meta  = [];
      } :: !nodes;
      add_edge parent id "decl"

    | _ -> ()  (* DUse, DAlias, DNeeds, etc. — skip *)
  in

  visit_decls mod_id m.mod_decls;
  phase_to_json phase_name (List.rev !nodes) (List.rev !edges)

(* ------------------------------------------------------------------ *)
(* TIR phase serialiser                                                *)
(* ------------------------------------------------------------------ *)

(** Collect names of directly-called functions in a TIR expression. *)
let rec tir_calls_in acc (e : March_tir.Tir.expr) =
  let open March_tir.Tir in
  match e with
  | EApp (v, _)         -> v.v_name :: acc
  | ECallPtr (_, _)     -> acc
  | ELet (_, rhs, body) -> tir_calls_in (tir_calls_in acc rhs) body
  | ELetRec (fns, body) ->
    let acc = tir_calls_in acc body in
    List.fold_left (fun a f -> tir_calls_in a f.fn_body) acc fns
  | ECase (_, brs, def) ->
    let acc = match def with None -> acc | Some e -> tir_calls_in acc e in
    List.fold_left (fun a br -> tir_calls_in a br.br_body) acc brs
  | ESeq (a, b)         -> tir_calls_in (tir_calls_in acc a) b
  | _                   -> acc

let rec tir_ty_str = function
  | March_tir.Tir.TInt     -> "Int"
  | March_tir.Tir.TFloat   -> "Float"
  | March_tir.Tir.TBool    -> "Bool"
  | March_tir.Tir.TString  -> "String"
  | March_tir.Tir.TUnit    -> "Unit"
  | March_tir.Tir.TTuple ts -> "(" ^ String.concat ", " (List.map tir_ty_str ts) ^ ")"
  | March_tir.Tir.TRecord fs ->
    "{ " ^ String.concat ", " (List.map (fun (n, t) -> n ^ ": " ^ tir_ty_str t) fs) ^ " }"
  | March_tir.Tir.TCon (n, []) -> n
  | March_tir.Tir.TCon (n, ts) ->
    n ^ "(" ^ String.concat ", " (List.map tir_ty_str ts) ^ ")"
  | March_tir.Tir.TFn (ps, r) ->
    "fn(" ^ String.concat ", " (List.map tir_ty_str ps) ^ ") -> " ^ tir_ty_str r
  | March_tir.Tir.TPtr t  -> "*" ^ tir_ty_str t
  | March_tir.Tir.TVar n  -> "'" ^ n

(** Count RC operations in a TIR expression (useful for Perceus phase). *)
let rec count_rc_ops (e : March_tir.Tir.expr) =
  let open March_tir.Tir in
  match e with
  | EIncRC _ | EDecRC _ | EAtomicIncRC _ | EAtomicDecRC _ -> 1
  | EFree _  | EReuse _  -> 1
  | ELet (_, rhs, body)  -> count_rc_ops rhs + count_rc_ops body
  | ELetRec (fns, body)  ->
    count_rc_ops body +
    List.fold_left (fun a f -> a + count_rc_ops f.fn_body) 0 fns
  | ECase (_, brs, def)  ->
    (match def with None -> 0 | Some e -> count_rc_ops e) +
    List.fold_left (fun a br -> a + count_rc_ops br.br_body) 0 brs
  | ESeq (a, b)          -> count_rc_ops a + count_rc_ops b
  | _                    -> 0

(** A simple non-cryptographic fingerprint of a string.
    Used only for change detection in the diff viewer. *)
let body_fingerprint s =
  (* djb2-style hash, wrapped to a positive int *)
  let h = ref 5381 in
  String.iter (fun c -> h := (!h lsl 5) + !h + Char.code c) s;
  Printf.sprintf "%08x" (abs !h land 0x7fffffff)

(** Produce a stable, unique ID for a TIR function.
    Uses the function name directly — names are unique within a TIR module
    after monomorphization and are preserved across opt passes. *)
let tir_fn_id fn_name = "fn_" ^ fn_name

(** Produce a stable, unique ID for a TIR type definition. *)
let tir_type_id type_name = "type_" ^ type_name

(** Produce nodes+edges for a TIR module.
    Node IDs are name-based (stable across passes) so the diff viewer can
    track which nodes were added, removed, or modified between adjacent phases. *)
let tir_phase (tm : March_tir.Tir.tir_module) phase_name =
  let nodes = ref [] in
  let edges = ref [] in

  let mod_id = "mod_" ^ tm.March_tir.Tir.tm_name in
  nodes := {
    n_id    = mod_id;
    n_label = "mod " ^ tm.March_tir.Tir.tm_name;
    n_type  = "module";
    n_meta  = [
      "fns",   json_string (string_of_int (List.length tm.March_tir.Tir.tm_fns));
      "types", json_string (string_of_int (List.length tm.March_tir.Tir.tm_types));
    ];
  } :: !nodes;

  (* Type definition nodes — stable IDs based on type name *)
  List.iter (fun td ->
    let open March_tir.Tir in
    let (name, detail, ty) = match td with
      | TDVariant (n, vs) ->
        let detail = String.concat " | " (List.map (fun (c, ts) ->
          match ts with
          | [] -> c
          | _  -> c ^ "(" ^ String.concat ", " (List.map tir_ty_str ts) ^ ")"
        ) vs) in
        (n, detail, "variant")
      | TDRecord (n, fs) ->
        let detail = "{ " ^ String.concat ", " (List.map (fun (f, t) ->
          f ^ ": " ^ tir_ty_str t) fs) ^ " }" in
        (n, detail, "record")
      | TDClosure (n, ts) ->
        (n, "closure(" ^ String.concat ", " (List.map tir_ty_str ts) ^ ")", "closure")
    in
    let id = tir_type_id name in
    nodes := {
      n_id    = id;
      n_label = "type " ^ name;
      n_type  = ty;
      n_meta  = ["detail", json_string detail];
    } :: !nodes;
    edges := { e_src = mod_id; e_dst = id; e_label = "type" } :: !edges
  ) tm.March_tir.Tir.tm_types;

  (* Function nodes — stable IDs based on function name *)
  List.iter (fun (fn : March_tir.Tir.fn_def) ->
    let id = tir_fn_id fn.March_tir.Tir.fn_name in
    let params_str = String.concat ", " (List.map (fun v ->
      v.March_tir.Tir.v_name ^ ": " ^ tir_ty_str v.March_tir.Tir.v_ty
    ) fn.March_tir.Tir.fn_params) in
    let calls = tir_calls_in [] fn.March_tir.Tir.fn_body in
    let calls = List.sort_uniq String.compare calls in
    let rc_ops = count_rc_ops fn.March_tir.Tir.fn_body in
    (* Body fingerprint lets the diff viewer detect when a function's body
       changed between passes even if its signature and call list are the same. *)
    let body_fp = body_fingerprint (March_tir.Tir.show_expr fn.March_tir.Tir.fn_body) in
    nodes := {
      n_id    = id;
      n_label = fn.March_tir.Tir.fn_name ^ "(" ^ params_str ^ ")";
      n_type  = "fn";
      n_meta  = [
        "ret",        json_string (tir_ty_str fn.March_tir.Tir.fn_ret_ty);
        "calls",      json_list (List.map json_string calls);
        "rc_ops",     json_string (string_of_int rc_ops);
        "body_hash",  json_string body_fp;
      ];
    } :: !nodes;
    edges := { e_src = mod_id; e_dst = id; e_label = "fn" } :: !edges;
    (* Call edges — targets now use stable IDs so more edges resolve correctly *)
    List.iter (fun callee ->
      edges := { e_src = id; e_dst = tir_fn_id callee; e_label = "calls" }
        :: !edges
    ) calls
  ) tm.March_tir.Tir.tm_fns;

  phase_to_json phase_name (List.rev !nodes) (List.rev !edges)

(* ------------------------------------------------------------------ *)
(* Write phases.json                                                   *)
(* ------------------------------------------------------------------ *)

let ensure_dir path =
  if not (Sys.file_exists path) then
    Unix.mkdir path 0o755

let write_phases ~source_file phases =
  ensure_dir "march-phases";
  let payload = json_obj [
    "source_file", json_string source_file;
    "phases",      json_list phases;
  ] in
  let path = "march-phases/phases.json" in
  let oc = open_out path in
  output_string oc payload;
  close_out oc;
  Printf.eprintf "wrote %s\n%!" path
