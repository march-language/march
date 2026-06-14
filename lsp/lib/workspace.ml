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

let rec walk_dir acc dir =
  match Sys.readdir dir with
  | exception _ -> acc
  | entries ->
    Array.fold_left (fun acc name ->
        if skip_dir name then acc
        else
          let path = Filename.concat dir name in
          if (try Sys.is_directory path with _ -> false) then walk_dir acc path
          else if Filename.check_suffix name ".march" then path :: acc
          else acc)
      acc entries

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
