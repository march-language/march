(** Span remapping from .march.spans sidecar files.

    When a .march file is generated from a .march.html template, the lowering
    pass writes a .march.spans sidecar that maps generated line numbers back to
    original file positions. This module loads that sidecar and rewrites AST
    spans so error messages point to the original template. *)

type entry = {
  gen_line  : int;
  orig_file : string;
  orig_line : int;
  orig_col  : int;
}

type t = entry array

let parse text : t =
  let lines = String.split_on_char '\n' text in
  let entries = List.filter_map (fun line ->
    let line = String.trim line in
    if line = "" then None
    else
      match String.split_on_char '\t' line with
      | [gl; file; ol; oc] ->
        (try Some {
          gen_line  = int_of_string gl;
          orig_file = file;
          orig_line = int_of_string ol;
          orig_col  = int_of_string oc;
        } with Failure _ -> None)
      | _ -> None
  ) lines in
  let arr = Array.of_list entries in
  Array.sort (fun a b -> compare a.gen_line b.gen_line) arr;
  arr

let find_entry (tbl : t) line : entry option =
  let n = Array.length tbl in
  if n = 0 then None
  else
    let lo = ref 0 in
    let hi = ref (n - 1) in
    let result = ref (-1) in
    while !lo <= !hi do
      let mid = !lo + (!hi - !lo) / 2 in
      if tbl.(mid).gen_line <= line then begin
        result := mid;
        lo := mid + 1
      end else
        hi := mid - 1
    done;
    if !result >= 0 then Some tbl.(!result)
    else None

let remap_span (tbl : t) (sp : Ast.span) : Ast.span =
  if Array.length tbl = 0 then sp
  else
    match find_entry tbl sp.start_line with
    | None -> sp
    | Some entry ->
      let line_offset = sp.start_line - entry.gen_line in
      { file = entry.orig_file;
        start_line = entry.orig_line + line_offset;
        start_col = if line_offset = 0 then entry.orig_col + sp.start_col - 1 else sp.start_col;
        end_line = entry.orig_line + (sp.end_line - entry.gen_line);
        end_col = sp.end_col;
      }

let remap_name tbl (n : Ast.name) : Ast.name =
  { n with span = remap_span tbl n.span }

let rec remap_pattern tbl = function
  | Ast.PatWild sp -> Ast.PatWild (remap_span tbl sp)
  | Ast.PatVar n -> Ast.PatVar (remap_name tbl n)
  | Ast.PatCon (n, pats) -> Ast.PatCon (remap_name tbl n, List.map (remap_pattern tbl) pats)
  | Ast.PatAtom (s, pats, sp) -> Ast.PatAtom (s, List.map (remap_pattern tbl) pats, remap_span tbl sp)
  | Ast.PatTuple (pats, sp) -> Ast.PatTuple (List.map (remap_pattern tbl) pats, remap_span tbl sp)
  | Ast.PatLit (lit, sp) -> Ast.PatLit (lit, remap_span tbl sp)
  | Ast.PatRecord (fields, sp) ->
    Ast.PatRecord (List.map (fun (n, p) -> (remap_name tbl n, remap_pattern tbl p)) fields, remap_span tbl sp)
  | Ast.PatAs (p, n, sp) -> Ast.PatAs (remap_pattern tbl p, remap_name tbl n, remap_span tbl sp)

let rec remap_expr tbl = function
  | Ast.ELit (lit, sp) -> Ast.ELit (lit, remap_span tbl sp)
  | Ast.EVar n -> Ast.EVar (remap_name tbl n)
  | Ast.EApp (f, args, sp) ->
    Ast.EApp (remap_expr tbl f, List.map (remap_expr tbl) args, remap_span tbl sp)
  | Ast.ECon (n, args, sp) ->
    Ast.ECon (remap_name tbl n, List.map (remap_expr tbl) args, remap_span tbl sp)
  | Ast.ELam (params, body, sp) ->
    Ast.ELam (List.map (remap_param tbl) params, remap_expr tbl body, remap_span tbl sp)
  | Ast.EBlock (exprs, sp) ->
    Ast.EBlock (List.map (remap_expr tbl) exprs, remap_span tbl sp)
  | Ast.ELet (b, sp) ->
    Ast.ELet (remap_binding tbl b, remap_span tbl sp)
  | Ast.EMatch (e, branches, sp) ->
    Ast.EMatch (remap_expr tbl e, List.map (remap_branch tbl) branches, remap_span tbl sp)
  | Ast.ETuple (exprs, sp) ->
    Ast.ETuple (List.map (remap_expr tbl) exprs, remap_span tbl sp)
  | Ast.ERecord (fields, sp) ->
    Ast.ERecord (List.map (fun (n, e) -> (remap_name tbl n, remap_expr tbl e)) fields, remap_span tbl sp)
  | Ast.ERecordUpdate (e, fields, sp) ->
    Ast.ERecordUpdate (remap_expr tbl e, List.map (fun (n, e) -> (remap_name tbl n, remap_expr tbl e)) fields, remap_span tbl sp)
  | Ast.EField (e, n, sp) ->
    Ast.EField (remap_expr tbl e, remap_name tbl n, remap_span tbl sp)
  | Ast.EIf (c, t, f, sp) ->
    Ast.EIf (remap_expr tbl c, remap_expr tbl t, remap_expr tbl f, remap_span tbl sp)
  | Ast.ECond (arms, sp) ->
    Ast.ECond (List.map (fun (c, b) -> (remap_expr tbl c, remap_expr tbl b)) arms, remap_span tbl sp)
  | Ast.EPipe (l, r, sp) ->
    Ast.EPipe (remap_expr tbl l, remap_expr tbl r, remap_span tbl sp)
  | Ast.EAnnot (e, ty, sp) ->
    Ast.EAnnot (remap_expr tbl e, ty, remap_span tbl sp)
  | Ast.EHole (n, sp) ->
    Ast.EHole (Option.map (remap_name tbl) n, remap_span tbl sp)
  | Ast.EAtom (s, args, sp) ->
    Ast.EAtom (s, List.map (remap_expr tbl) args, remap_span tbl sp)
  | Ast.ESend (e1, e2, sp) ->
    Ast.ESend (remap_expr tbl e1, remap_expr tbl e2, remap_span tbl sp)
  | Ast.ESpawn (e, sp) ->
    Ast.ESpawn (remap_expr tbl e, remap_span tbl sp)
  | Ast.EResultRef _ as e -> e
  | Ast.EDbg (e, sp) ->
    Ast.EDbg (Option.map (remap_expr tbl) e, remap_span tbl sp)
  | Ast.ELetFn (n, params, ret, body, sp) ->
    Ast.ELetFn (remap_name tbl n, List.map (remap_param tbl) params, ret, remap_expr tbl body, remap_span tbl sp)
  | Ast.EAssert (e, sp) ->
    Ast.EAssert (remap_expr tbl e, remap_span tbl sp)
  | Ast.ESigil (c, e, sp) ->
    Ast.ESigil (c, remap_expr tbl e, remap_span tbl sp)

and remap_param tbl (p : Ast.param) : Ast.param =
  { p with param_name = remap_name tbl p.param_name }

and remap_binding tbl (b : Ast.binding) : Ast.binding =
  { b with
    bind_pat = remap_pattern tbl b.bind_pat;
    bind_expr = remap_expr tbl b.bind_expr;
  }

and remap_branch tbl (br : Ast.branch) : Ast.branch =
  { branch_pat = remap_pattern tbl br.branch_pat;
    branch_guard = Option.map (remap_expr tbl) br.branch_guard;
    branch_body = remap_expr tbl br.branch_body;
  }

let rec remap_fn_clause tbl (fc : Ast.fn_clause) : Ast.fn_clause =
  { fc_params = List.map (remap_fn_param tbl) fc.fc_params;
    fc_guard = Option.map (remap_expr tbl) fc.fc_guard;
    fc_body = remap_expr tbl fc.fc_body;
    fc_span = remap_span tbl fc.fc_span;
  }

and remap_fn_param tbl = function
  | Ast.FPPat p -> Ast.FPPat (remap_pattern tbl p)
  | Ast.FPNamed p -> Ast.FPNamed (remap_param tbl p)
  | Ast.FPDefault (p, e) -> Ast.FPDefault (remap_param tbl p, remap_expr tbl e)

let rec remap_decl tbl = function
  | Ast.DFn (fd, sp) ->
    Ast.DFn ({ fd with
      fn_name = remap_name tbl fd.fn_name;
      fn_clauses = List.map (remap_fn_clause tbl) fd.fn_clauses;
    }, remap_span tbl sp)
  | Ast.DLet (vis, b, sp) ->
    Ast.DLet (vis, remap_binding tbl b, remap_span tbl sp)
  | Ast.DType (vis, n, params, td, sp) ->
    Ast.DType (vis, remap_name tbl n, List.map (remap_name tbl) params, td, remap_span tbl sp)
  | Ast.DMod (n, vis, decls, sp) ->
    Ast.DMod (remap_name tbl n, vis, List.map (remap_decl tbl) decls, remap_span tbl sp)
  | Ast.DSig (n, sd, sp) ->
    Ast.DSig (remap_name tbl n, sd, remap_span tbl sp)
  | Ast.DInterface (idef, sp) ->
    Ast.DInterface (idef, remap_span tbl sp)
  | Ast.DImpl (idef, sp) ->
    Ast.DImpl (idef, remap_span tbl sp)
  | Ast.DExtern (edef, sp) ->
    Ast.DExtern (edef, remap_span tbl sp)
  | Ast.DUse (u, sp) ->
    Ast.DUse (u, remap_span tbl sp)
  | Ast.DAlias (a, sp) ->
    Ast.DAlias (a, remap_span tbl sp)
  | Ast.DNeeds (paths, sp) ->
    Ast.DNeeds (paths, remap_span tbl sp)
  | Ast.DApp (app, sp) ->
    Ast.DApp ({
      app_name = remap_name tbl app.app_name;
      app_body = remap_expr tbl app.app_body;
      app_on_start = Option.map (remap_expr tbl) app.app_on_start;
      app_on_stop = Option.map (remap_expr tbl) app.app_on_stop;
    }, remap_span tbl sp)
  | Ast.DDeriving (n, ifaces, sp) ->
    Ast.DDeriving (remap_name tbl n, List.map (remap_name tbl) ifaces, remap_span tbl sp)
  | Ast.DTest (td, sp) ->
    Ast.DTest ({ td with test_body = remap_expr tbl td.test_body }, remap_span tbl sp)
  | Ast.DDescribe (name, decls, sp) ->
    Ast.DDescribe (name, List.map (remap_decl tbl) decls, remap_span tbl sp)
  | Ast.DSetup (e, sp) ->
    Ast.DSetup (remap_expr tbl e, remap_span tbl sp)
  | Ast.DSetupAll (e, sp) ->
    Ast.DSetupAll (remap_expr tbl e, remap_span tbl sp)
  | Ast.DActor (vis, n, adef, sp) ->
    Ast.DActor (vis, remap_name tbl n, adef, remap_span tbl sp)
  | Ast.DProtocol (n, pdef, sp) ->
    Ast.DProtocol (remap_name tbl n, pdef, remap_span tbl sp)

let remap_module tbl (m : Ast.module_) : Ast.module_ =
  if Array.length tbl = 0 then m
  else
    { m with mod_decls = List.map (remap_decl tbl) m.mod_decls }

let load_sidecar march_path =
  let spans_path = march_path ^ ".spans" in
  if Sys.file_exists spans_path then begin
    try
      let ic = open_in spans_path in
      let n = in_channel_length ic in
      let s = Bytes.create n in
      really_input ic s 0 n;
      close_in ic;
      Some (parse (Bytes.to_string s))
    with _ -> None
  end else None
