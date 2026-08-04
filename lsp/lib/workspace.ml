(** Workspace symbol index: a cheap, parse-only (no typecheck) index of the
    top-level symbols across a project's .march files, for workspace/symbol
    ("go to symbol in project"). *)

module Lsp = Linol_lsp.Lsp
module Ast = March_ast.Ast

type ws_symbol = {
  wsy_name : string;
  wsy_kind : Lsp.Types.SymbolKind.t;
  wsy_file : string;
  wsy_span : Ast.span;
}

(* Parse + desugar a single source; errors yield [None] (no symbols). *)
let parse_source ~filename ~src : Ast.decl list option =
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
  try
    let m =
      March_parser.Parser.module_
        (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
    in
    let m = March_desugar.Desugar.desugar_module m in
    Some m.Ast.mod_decls
  with _ -> None

let symbols_of_decls ~filename (decls : Ast.decl list) : ws_symbol list =
  let open Lsp.Types in
  let acc = ref [] in
  let add (n : Ast.name) kind =
    acc := { wsy_name = n.Ast.txt; wsy_kind = kind;
             wsy_file = filename; wsy_span = n.Ast.span } :: !acc
  in
  let rec go (d : Ast.decl) =
    match d with
    | Ast.DFn (fn, _) -> add fn.Ast.fn_name SymbolKind.Function
    | Ast.DType (_, name, _, td, _) ->
      add name SymbolKind.Class;
      (match td with
       | Ast.TDVariant vs ->
         List.iter (fun (v : Ast.variant) -> add v.Ast.var_name SymbolKind.EnumMember) vs
       | Ast.TDRecord fs ->
         List.iter (fun (f : Ast.field) -> add f.Ast.fld_name SymbolKind.Field) fs
       | Ast.TDAlias _ -> ())
    | Ast.DActor (_, name, _, _) -> add name SymbolKind.Class
    | Ast.DInterface (idef, _) ->
      add idef.Ast.iface_name SymbolKind.Interface;
      List.iter (fun (m : Ast.method_decl) -> add m.Ast.md_name SymbolKind.Method)
        idef.Ast.iface_methods
    | Ast.DMod (name, _, ds, _) -> add name SymbolKind.Module; List.iter go ds
    | _ -> ()
  in
  List.iter go decls;
  List.rev !acc

let symbols_of_source ~filename ~src : ws_symbol list =
  match parse_source ~filename ~src with
  | None -> []
  | Some decls -> symbols_of_decls ~filename decls

let index_sources (files : (string * string) list) : ws_symbol list =
  List.concat_map (fun (f, src) -> symbols_of_source ~filename:f ~src) files

(* ------------------------------------------------------------------ *)
(* Use-site indexing (for cross-file references)                       *)
(* ------------------------------------------------------------------ *)

type ws_use = { wsu_name : string; wsu_file : string; wsu_span : Ast.span }

let uses_of_decls ~filename (decls : Ast.decl list) : ws_use list =
  let acc = ref [] in
  let add (n : Ast.name) =
    acc := { wsu_name = n.Ast.txt; wsu_file = filename; wsu_span = n.Ast.span } :: !acc
  in
  let rec we (e : Ast.expr) =
    match e with
    | Ast.EVar n -> add n
    | Ast.ECon (n, args, _) -> add n; List.iter we args
    | Ast.EApp (f, args, _) -> we f; List.iter we args
    | Ast.ELet (b, _) -> we b.Ast.bind_expr
    | Ast.ELetFn (_, _, _, body, _) -> we body
    | Ast.ELam (_, body, _) -> we body
    | Ast.EMatch (s, brs, _) ->
      we s;
      List.iter (fun (br : Ast.branch) ->
          wp br.Ast.branch_pat;
          Option.iter we br.Ast.branch_guard;
          we br.Ast.branch_body) brs
    | Ast.EBlock (es, _) -> List.iter we es
    | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) -> List.iter we es
    | Ast.ERecord (fs, _) -> List.iter (fun (_, e) -> we e) fs
    | Ast.ERecordUpdate (e, fs, _) -> we e; List.iter (fun (_, e2) -> we e2) fs
    | Ast.EField (base, field, _) -> add field; we base
    | Ast.EAnnot (e, _, _) | Ast.EDbg (Some e, _) | Ast.ESpawn (e, _) -> we e
    | Ast.EIf (c, a, b, _) -> we c; we a; we b
    | Ast.ECond (arms, _) -> List.iter (fun (c, b) -> we c; we b) arms
    | Ast.EPipe (a, b, _) | Ast.ESend (a, b, _) -> we a; we b
    | Ast.EAssert (e, _) -> we e
    | Ast.ESigil (_, c, _) -> we c
    | Ast.ELetQ (_, r, c, _) -> we r; we c
    | Ast.ELit _ | Ast.EHole _ | Ast.EDbg (None, _) | Ast.EResultRef _ -> ()
  and wp (p : Ast.pattern) =
    match p with
    | Ast.PatCon (n, ps) -> add n; List.iter wp ps
    | Ast.PatAs (p, _, _) -> wp p
    | Ast.PatTuple (ps, _) | Ast.PatAtom (_, ps, _) -> List.iter wp ps
    | Ast.PatRecord (fs, _) -> List.iter (fun (_, p) -> wp p) fs
    | Ast.PatOr (ps, _) -> List.iter wp ps
    | Ast.PatVar _ | Ast.PatWild _ | Ast.PatLit _ -> ()
  in
  let rec wd (d : Ast.decl) =
    match d with
    | Ast.DFn (fn, _) ->
      List.iter (fun (cl : Ast.fn_clause) ->
          Option.iter we cl.Ast.fc_guard; we cl.Ast.fc_body) fn.Ast.fn_clauses
    | Ast.DLet (_, b, _) -> we b.Ast.bind_expr
    | Ast.DActor (_, _, adef, _) ->
      we adef.Ast.actor_init;
      List.iter (fun (h : Ast.actor_handler) -> we h.Ast.ah_body) adef.Ast.actor_handlers
    | Ast.DMod (_, _, ds, _) -> List.iter wd ds
    | Ast.DImpl (impl, _) ->
      List.iter (fun (_, (fn : Ast.fn_def)) ->
          List.iter (fun (cl : Ast.fn_clause) -> we cl.Ast.fc_body) fn.Ast.fn_clauses)
        impl.Ast.impl_methods
    | Ast.DApp (app, _) ->
      we app.Ast.app_body;
      Option.iter we app.Ast.app_on_start;
      Option.iter we app.Ast.app_on_stop
    | Ast.DTest (t, _) -> we t.Ast.test_body
    | Ast.DSetup (b, _) | Ast.DSetupAll (b, _) -> we b
    | _ -> ()
  in
  List.iter wd decls;
  List.rev !acc

let uses_of_source ~filename ~src : ws_use list =
  match parse_source ~filename ~src with
  | None -> []
  | Some decls -> uses_of_decls ~filename decls

type ws_index = { wsi_defs : ws_symbol list; wsi_uses : ws_use list }

let index_full (files : (string * string) list) : ws_index =
  { wsi_defs = index_sources files;
    wsi_uses = List.concat_map (fun (f, src) -> uses_of_source ~filename:f ~src) files }

(* All def + use occurrences of [name] across the project (name-based). *)
let references_across (idx : ws_index) (name : string) : (string * Ast.span) list =
  let defs =
    List.filter_map (fun (s : ws_symbol) ->
        if s.wsy_name = name then Some (s.wsy_file, s.wsy_span) else None)
      idx.wsi_defs
  in
  let uses =
    List.filter_map (fun (u : ws_use) ->
        if u.wsu_name = name then Some (u.wsu_file, u.wsu_span) else None)
      idx.wsi_uses
  in
  defs @ uses

(* Case-insensitive subsequence match (the common fuzzy "Ctrl-T" behaviour). *)
let matches (query : string) (name : string) : bool =
  let q = String.lowercase_ascii query and name = String.lowercase_ascii name in
  let nl = String.length name and ql = String.length q in
  let ni = ref 0 and qi = ref 0 in
  while !ni < nl && !qi < ql do
    if name.[!ni] = q.[!qi] then incr qi;
    incr ni
  done;
  !qi = ql

let query_symbols (index : ws_symbol list) (q : string) : ws_symbol list =
  if q = "" then index else List.filter (fun s -> matches q s.wsy_name) index

(* ------------------------------------------------------------------ *)
(* On-disk project discovery                                           *)
(* ------------------------------------------------------------------ *)

let skip_dir name =
  match name with
  | "_build" | "_build_wt" | ".git" | ".claude" | "node_modules" | "_opam" -> true
  | _ -> false

(* Bounds on the workspace walk.

   [project_root] falls back to the open DOCUMENT'S DIRECTORY when no
   `forge.toml` is found above it, and to the process cwd when there is no
   document — so a file opened at `/`, in a home directory, or anywhere else
   large makes this walk the whole tree. Unbounded, that is not slow but
   effectively infinite: `textDocument/references` and `workspace/symbol` never
   return, and the client cannot tell a hang from a server that is thinking.
   Observed while auditing the LSP against a real project.

   A cap turns that into partial results, which is the right failure: symbol
   search that misses a distant file is useful, and a request that never answers
   is not. The depth bound catches deep trees, the file bound catches wide ones,
   and either one alone leaves the other case open. *)
let max_walk_files = 5000
let max_walk_depth = 16

(* Reported once per walk that truncates. A silently partial index would make
   "symbol not found" indistinguishable from "symbol not indexed" — the same
   ambiguity the obligation ledger exists to prevent in the checker. stderr is
   where an LSP server's diagnostics go; there is no protocol channel for
   "your workspace is bigger than I will read". *)
let warn_truncated ~root ~count =
  Printf.eprintf
    "march-lsp: workspace index stopped at %d files under %s (limit %d). \
     Symbol search and find-references will be incomplete. Open the project \
     root (the directory containing forge.toml) to index it properly.\n%!"
    count root max_walk_files

let walk_dir acc root =
  let count = ref (List.length acc) in
  let truncated = ref false in
  let rec go acc dir depth =
    if !count >= max_walk_files || depth > max_walk_depth then begin
      if !count >= max_walk_files then truncated := true;
      acc
    end
    else
      match Sys.readdir dir with
      | exception _ -> acc
      | entries ->
        Array.fold_left (fun acc name ->
            if !count >= max_walk_files then begin truncated := true; acc end
            else if skip_dir name then acc
            else
              let path = Filename.concat dir name in
              if (try Sys.is_directory path with _ -> false) then
                go acc path (depth + 1)
              else if Filename.check_suffix name ".march" then begin
                incr count; path :: acc
              end
              else acc)
          acc entries
  in
  let result = go acc root 0 in
  if !truncated then warn_truncated ~root ~count:!count;
  result

let read_file path =
  try
    let ic = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
      let n = in_channel_length ic in
      let b = Bytes.create n in
      really_input ic b 0 n;
      Some (Bytes.to_string b))
  with _ -> None

let discover_sources ~root : (string * string) list =
  walk_dir [] root
  |> List.filter_map (fun p ->
         match read_file p with Some s -> Some (p, s) | None -> None)

let index_project ~root : ws_symbol list =
  index_sources (discover_sources ~root)

let index_project_full ~root : ws_index =
  index_full (discover_sources ~root)
