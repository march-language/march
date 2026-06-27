(** March search index — Hoogle-style search for March functions and types.

    Supports three query modes:
    - Name search: fuzzy + substring matching using Levenshtein distance
    - Type signature search: string-based component matching
    - Doc keyword search: full-text keyword search over doc strings

    The index is built from parsed AST declarations and cached as JSON at
    [.march/search-index.json]. *)

module Ast = March_ast.Ast
module TC  = March_typecheck.Typecheck

(* ------------------------------------------------------------------ *)
(* Types                                                               *)
(* ------------------------------------------------------------------ *)

type kind = Fn | Type_ | Constructor

type entry = {
  name        : string;
  module_name : string;
  kind        : kind;
  signature   : string;
  doc         : string option;
  file        : string;
  line        : int;
  params      : (string * string) list;
  return_type : string option;
}

type index = {
  entries      : entry list;
  version      : int;
  generated_at : string;
}

(* ------------------------------------------------------------------ *)
(* Levenshtein distance                                                *)
(* ------------------------------------------------------------------ *)

let levenshtein s t =
  let n = String.length s and m = String.length t in
  if n = 0 then m
  else if m = 0 then n
  else begin
    let d = Array.make_matrix (n + 1) (m + 1) 0 in
    for i = 0 to n do d.(i).(0) <- i done;
    for j = 0 to m do d.(0).(j) <- j done;
    for i = 1 to n do
      for j = 1 to m do
        let cost = if s.[i-1] = t.[j-1] then 0 else 1 in
        d.(i).(j) <-
          min (min (d.(i-1).(j) + 1) (d.(i).(j-1) + 1))
              (d.(i-1).(j-1) + cost)
      done
    done;
    d.(n).(m)
  end

(* ------------------------------------------------------------------ *)
(* AST surface-type pretty printer                                     *)
(* ------------------------------------------------------------------ *)

let rec pp_ast_ty = function
  | Ast.TyCon ({txt; _}, []) -> txt
  | Ast.TyCon ({txt; _}, args) ->
    txt ^ "(" ^ String.concat ", " (List.map pp_ast_ty args) ^ ")"
  | Ast.TyVar {txt; _} -> txt
  | Ast.TyArrow (a, b) ->
    let a_str = match a with
      | Ast.TyArrow _ -> "(" ^ pp_ast_ty a ^ ")"
      | _ -> pp_ast_ty a
    in
    a_str ^ " -> " ^ pp_ast_ty b
  | Ast.TyTuple ts ->
    "(" ^ String.concat ", " (List.map pp_ast_ty ts) ^ ")"
  | Ast.TyRecord fields ->
    "{ " ^
    String.concat ", "
      (List.map (fun ({Ast.txt; _}, t) -> txt ^ ": " ^ pp_ast_ty t) fields)
    ^ " }"
  | Ast.TyLinear (_, t) -> pp_ast_ty t
  | Ast.TyNat n -> string_of_int n
  | Ast.TyNatOp _ -> "_"
  | Ast.TyChan _ -> "Chan"
  | Ast.TyRefine (base, _, _) -> pp_ast_ty base

(* ------------------------------------------------------------------ *)
(* Canonical type printer (clean a/b/c variable names)                *)
(* ------------------------------------------------------------------ *)

(** Create a printer that assigns clean variable names (a, b, c, …) in order
    of first appearance, shared across multiple calls — so all parts of one
    function signature use the same name mapping. *)
let make_ty_printer () : TC.ty -> string =
  let tbl  : (int, string) Hashtbl.t = Hashtbl.create 8 in
  let next = ref 0 in
  let varname id =
    match Hashtbl.find_opt tbl id with
    | Some n -> n
    | None ->
      let n = if !next < 26 then String.make 1 (Char.chr (97 + !next))
              else "t" ^ string_of_int (!next - 25) in
      incr next; Hashtbl.add tbl id n; n
  in
  let rec go ty =
    match TC.repr ty with
    | TC.TVar r ->
      (match !r with
       | TC.Unbound (id, _) -> varname id
       | TC.Link t          -> go t)
    | TC.TCon (name, [])   -> name
    | TC.TCon (name, args) ->
      name ^ "(" ^ String.concat ", " (List.map go args) ^ ")"
    | TC.TArrow (a, b) ->
      let a_str = match TC.repr a with
        | TC.TArrow _ -> "(" ^ go a ^ ")"
        | _           -> go a
      in
      a_str ^ " -> " ^ go b
    | TC.TTuple []  -> "()"
    | TC.TTuple ts  -> "(" ^ String.concat ", " (List.map go ts) ^ ")"
    | TC.TRecord flds ->
      "{ " ^ String.concat ", " (List.map (fun (n, t) -> n ^ ": " ^ go t) flds) ^ " }"
    | TC.TLin (_, t)        -> go t
    | TC.TRefine (base, _,_)-> go base
    | TC.TError             -> "<error>"
    | _                     -> TC.pp_ty ty
  in
  go

let pp_ty_canonical (ty : TC.ty) : string = make_ty_printer () ty

(* ------------------------------------------------------------------ *)
(* Index building from AST declarations                                *)
(* ------------------------------------------------------------------ *)

let extract_fn_params (fn : Ast.fn_def) : (string * string) list =
  match fn.fn_clauses with
  | [] -> []
  | clause :: _ ->
    List.map (function
      | Ast.FPNamed p ->
        (p.param_name.txt,
         match p.param_ty with Some t -> pp_ast_ty t | None -> "_")
      | Ast.FPDefault (p, _) ->
        (p.param_name.txt,
         match p.param_ty with Some t -> pp_ast_ty t | None -> "_")
      | Ast.FPPat (Ast.PatVar n) -> (n.txt, "_")
      | Ast.FPPat _ -> ("_", "_")
    ) clause.fc_params

(** Split a curried arrow type into [n] parameter types + a return type. *)
let rec split_arrows n ty =
  let ty = TC.repr ty in
  if n = 0 then ([], ty)
  else match ty with
  | TC.TArrow (a, b) ->
    let (rest, ret) = split_arrows (n - 1) b in
    (TC.repr a :: rest, ret)
  | _ -> ([], ty)

(** Resolve inferred param types + return type from the type_map.
    Falls back to AST-annotated strings when the span isn't in the map. *)
let rec has_error ty =
  match TC.repr ty with
  | TC.TError         -> true
  | TC.TCon (_, args) -> List.exists has_error args
  | TC.TArrow (a, b)  -> has_error a || has_error b
  | TC.TTuple ts      -> List.exists has_error ts
  | TC.TRecord flds   -> List.exists (fun (_, t) -> has_error t) flds
  | TC.TLin (_, t)    -> has_error t
  | _                 -> false

let resolve_fn_types type_map (fn : Ast.fn_def) (ast_params : (string * string) list) ast_ret =
  match Hashtbl.find_opt type_map fn.fn_name.span with
  | None -> (ast_params, ast_ret)
  | Some fn_ty when has_error fn_ty -> (ast_params, ast_ret)
  | Some fn_ty ->
    let n = List.length ast_params in
    let (param_tys, ret_ty) = split_arrows n fn_ty in
    (* One shared printer so variable names are consistent across params and return. *)
    let pp = make_ty_printer () in
    let params = List.mapi (fun i (name, ast_ty) ->
      let ty = match List.nth_opt param_tys i with
        | Some t -> pp t
        | None   -> ast_ty
      in
      (name, ty)
    ) ast_params in
    let ret = Some (pp ret_ty) in
    (params, ret)

let make_fn_signature ~module_name (fn : Ast.fn_def) (params : (string * string) list) (ret : string option) =
  let prefix = if module_name = "" then "" else module_name ^ "." in
  let param_sig =
    String.concat ", " (List.map (fun (n, t) -> n ^ ": " ^ t) params)
  in
  prefix ^ fn.fn_name.txt ^
  "(" ^ param_sig ^ ")" ^
  (match ret with Some r -> " -> " ^ r | None -> "")

let rec collect_entries ~module_name ~file ~type_map acc (decl : Ast.decl) =
  match decl with
  | Ast.DFn (fn, span) ->
    let ast_params = extract_fn_params fn in
    let ast_ret = Option.map pp_ast_ty fn.fn_ret_ty in
    let (params, ret) = resolve_fn_types type_map fn ast_params ast_ret in
    let signature = make_fn_signature ~module_name fn params ret in
    let entry = {
      name        = fn.fn_name.txt;
      module_name;
      kind        = Fn;
      signature;
      doc         = fn.fn_doc;
      file;
      line        = span.Ast.start_line;
      params;
      return_type = ret;
    } in
    entry :: acc

  | Ast.DTransitions _ -> []
  | Ast.DType (_, name, _, typedef, span)
  | Ast.DAlwaysLinearType (_, name, _, typedef, span) ->
    let prefix = if module_name = "" then "" else module_name ^ "." in
    let type_entry = {
      name        = name.txt;
      module_name;
      kind        = Type_;
      signature   = prefix ^ name.txt;
      doc         = None;
      file;
      line        = span.Ast.start_line;
      params      = [];
      return_type = None;
    } in
    let ctor_entries = match typedef with
      | Ast.TDVariant variants ->
        List.map (fun (v : Ast.variant) ->
          let args_str =
            if v.var_args = [] then ""
            else "(" ^ String.concat ", " (List.map pp_ast_ty v.var_args) ^ ")"
          in
          { name        = v.var_name.txt;
            module_name;
            kind        = Constructor;
            signature   = prefix ^ v.var_name.txt ^ args_str;
            doc         = None;
            file;
            line        = v.var_name.span.Ast.start_line;
            params      = List.mapi (fun i t -> (string_of_int i, pp_ast_ty t)) v.var_args;
            return_type = Some name.txt;
          }
        ) variants
      | _ -> []
    in
    ctor_entries @ (type_entry :: acc)

  | Ast.DMod (mname, _, decls, _) ->
    let sub =
      if module_name = "" then mname.txt
      else module_name ^ "." ^ mname.txt
    in
    List.fold_left (collect_entries ~module_name:sub ~file ~type_map) acc decls

  | _ -> acc

(** Build an index from parsed decl lists, enriched with inferred types
    from an optional typechecker type_map. *)
let build_index (decl_lists : Ast.decl list list) ~(source_files : string list)
    ?(type_map = Hashtbl.create 0) () : index =
  let tm = type_map in
  let entries =
    List.fold_left2
      (fun acc decls file ->
        List.fold_left (collect_entries ~module_name:"" ~file ~type_map:tm) acc decls)
      []
      decl_lists
      source_files
  in
  let now =
    let t  = Unix.gettimeofday () in
    let tm = Unix.gmtime t in
    Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
      (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday
      tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec
  in
  { entries; version = 1; generated_at = now }

(* ------------------------------------------------------------------ *)
(* Stdlib loading (mirrors lsp/lib/analysis.ml)                       *)
(* ------------------------------------------------------------------ *)

let find_stdlib_dir () =
  let exe_dir = Filename.dirname Sys.executable_name in
  let candidates = [
    Filename.concat exe_dir "../stdlib";
    Filename.concat exe_dir "../../stdlib";
    Filename.concat exe_dir "../share/march/stdlib";
    Filename.concat exe_dir "../share/march";
    "stdlib";
  ] in
  List.find_opt Sys.file_exists candidates

let parse_file path =
  let src =
    try
      let ic = open_in path in
      let n  = in_channel_length ic in
      let buf = Bytes.create n in
      really_input ic buf 0 n;
      close_in ic;
      Bytes.to_string buf
    with Sys_error _ -> ""
  in
  if src = "" then []
  else
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
    (try
       let m = March_parser.Parser.module_
           (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
       let m = March_desugar.Desugar.desugar_module m in
       let basename = Filename.basename path in
       if basename = "prelude.march" then
         (match m.Ast.mod_decls with
          | [Ast.DMod (_, _, inner, _)] -> inner
          | decls -> decls)
       else
         [Ast.DMod (m.Ast.mod_name, Ast.Public, m.Ast.mod_decls, Ast.dummy_span)]
     with _ -> [])

(** Load and parse all stdlib .march files. Returns (decl_lists, paths). *)
let load_stdlib () : Ast.decl list list * string list =
  match find_stdlib_dir () with
  | None -> ([], [])
  | Some stdlib_dir ->
    let all_files =
      try
        Sys.readdir stdlib_dir
        |> Array.to_list
        |> List.filter (fun f -> Filename.check_suffix f ".march")
        |> List.sort String.compare
      with Sys_error _ -> []
    in
    let prelude = "prelude.march" in
    let rest = List.filter (fun f -> f <> prelude) all_files in
    let ordered = if List.mem prelude all_files then prelude :: rest else rest in
    let paths = List.map (fun name -> Filename.concat stdlib_dir name) ordered in
    let decls = List.map parse_file paths in
    (decls, paths)

(** Typecheck a flat list of stdlib decls and return the span→type map. *)
let typecheck_decls (all_decls : Ast.decl list) : (Ast.span, TC.ty) Hashtbl.t =
  let synth : Ast.module_ = {
    mod_name  = { txt = "__stdlib__"; span = Ast.dummy_span };
    mod_decls = all_decls;
  } in
  let (_errors, type_map) = TC.check_module synth in
  type_map

(** Build a search index from all stdlib files, with typechecker-inferred types. *)
let build_stdlib_index () : index =
  let (decl_lists, source_files) = load_stdlib () in
  let type_map = typecheck_decls (List.concat decl_lists) in
  build_index decl_lists ~source_files ~type_map ()

(** Build an index from all .march files found in [dirs] (non-recursive). *)
let build_index_from_dirs (dirs : string list) : index =
  let march_files_in dir =
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
  build_index decls ~source_files:paths ()

(** Merge two indices into one. *)
let merge_indices (a : index) (b : index) : index =
  { a with entries = a.entries @ b.entries }

(* ------------------------------------------------------------------ *)
(* Search helpers                                                      *)
(* ------------------------------------------------------------------ *)

let normalize s = String.lowercase_ascii s

let contains_substr haystack needle =
  let hn = String.length haystack and nn = String.length needle in
  if nn = 0 then true
  else if nn > hn then false
  else begin
    let found = ref false in
    let i = ref 0 in
    while !i <= hn - nn && not !found do
      if String.sub haystack !i nn = needle then found := true;
      incr i
    done;
    !found
  end

(* ------------------------------------------------------------------ *)
(* Search functions                                                    *)
(* ------------------------------------------------------------------ *)

(** Search by function/type name.  Uses substring + Levenshtein fuzzy match. *)
let search_name (idx : index) (query : string) : (entry * float) list =
  if String.length query = 0 then
    List.map (fun e -> (e, 1.0)) idx.entries
  else begin
    let ql = normalize query in
    List.filter_map (fun entry ->
      let nl = normalize entry.name in
      if nl = ql then
        Some (entry, 1.0)
      else if contains_substr nl ql then
        Some (entry, 0.8)
      else begin
        let dist = levenshtein ql nl in
        let max_len = max (String.length ql) (String.length nl) in
        let threshold = max 1 (max_len / 3) in
        if dist <= threshold then
          Some (entry, 1.0 -. float_of_int dist /. float_of_int max_len)
        else
          None
      end
    ) idx.entries
    |> List.sort (fun (_, s1) (_, s2) -> compare s2 s1)
  end

(** Search by type signature.  Checks if query type components appear in
    the indexed signature string (v1: component-based string matching). *)
let search_type (idx : index) (type_query : string) : (entry * float) list =
  if String.length type_query = 0 then [] else
  let ql = normalize type_query in
  (* Split on arrows and commas for component matching *)
  let parts =
    String.split_on_char ' ' ql
    |> List.concat_map (String.split_on_char ',')
    |> List.map String.trim
    |> List.filter (fun s -> s <> "" && s <> "->" && s <> "-")
  in
  if parts = [] then [] else
  List.filter_map (fun entry ->
    let sig_l = normalize entry.signature in
    let matched = List.filter (fun p -> contains_substr sig_l p) parts in
    let total = List.length parts in
    let n_matched = List.length matched in
    if n_matched = 0 then None
    else
      let score = float_of_int n_matched /. float_of_int total in
      Some (entry, score)
  ) idx.entries
  |> List.sort (fun (_, s1) (_, s2) -> compare s2 s1)

(** Search by keyword in doc strings. *)
let search_docs (idx : index) (keywords : string) : (entry * float) list =
  if String.length keywords = 0 then [] else
  let ql = normalize keywords in
  let parts =
    String.split_on_char ' ' ql
    |> List.filter (fun s -> s <> "")
  in
  if parts = [] then [] else
  List.filter_map (fun entry ->
    match entry.doc with
    | None -> None
    | Some doc ->
      let doc_l = normalize doc in
      let matched = List.filter (fun p -> contains_substr doc_l p) parts in
      let n_matched = List.length matched in
      if n_matched = 0 then None
      else
        let score = float_of_int n_matched /. float_of_int (List.length parts) in
        Some (entry, score)
  ) idx.entries
  |> List.sort (fun (_, s1) (_, s2) -> compare s2 s1)

(** Combined search: AND-semantics across all specified modes.
    If no mode is specified, returns all entries. *)
let search_combined (idx : index)
    ?(name : string option)
    ?(type_sig : string option)
    ?(doc_query : string option)
    () : (entry * float) list =
  match name, type_sig, doc_query with
  | None, None, None ->
    List.map (fun e -> (e, 1.0)) idx.entries
  | _ ->
    (* Build score maps for each active mode *)
    let make_map results =
      let tbl = Hashtbl.create 64 in
      List.iter (fun (e, s) ->
        let key = (e.module_name, e.name, e.line) in
        Hashtbl.replace tbl key (e, s)
      ) results;
      tbl
    in
    let name_tbl  = Option.map (fun q -> make_map (search_name idx q)) name in
    let type_tbl  = Option.map (fun q -> make_map (search_type idx q)) type_sig in
    let doc_tbl   = Option.map (fun q -> make_map (search_docs idx q)) doc_query in
    List.filter_map (fun entry ->
      let key = (entry.module_name, entry.name, entry.line) in
      let score = ref 0.0 in
      let count = ref 0 in
      let pass  = ref true in
      let check tbl_opt =
        match tbl_opt with
        | None -> ()
        | Some tbl ->
          (match Hashtbl.find_opt tbl key with
           | None -> pass := false
           | Some (_, s) -> score := !score +. s; incr count)
      in
      check name_tbl;
      check type_tbl;
      check doc_tbl;
      if !pass && !count > 0 then
        Some (entry, !score /. float_of_int !count)
      else None
    ) idx.entries
    |> List.sort (fun (_, s1) (_, s2) -> compare s2 s1)

(* ------------------------------------------------------------------ *)
(* JSON serialization                                                  *)
(* ------------------------------------------------------------------ *)

let kind_to_string = function
  | Fn          -> "fn"
  | Type_       -> "type"
  | Constructor -> "constructor"

let kind_of_string = function
  | "type"        -> Type_
  | "constructor" -> Constructor
  | _             -> Fn

let entry_to_json (e : entry) : Yojson.Basic.t =
  `Assoc [
    "name",        `String e.name;
    "module",      `String e.module_name;
    "kind",        `String (kind_to_string e.kind);
    "signature",   `String e.signature;
    "doc",         (match e.doc with None -> `Null | Some s -> `String s);
    "file",        `String e.file;
    "line",        `Int e.line;
    "params",      `List (List.map (fun (n, t) ->
                     `Assoc ["name", `String n; "type", `String t]) e.params);
    "return_type", (match e.return_type with None -> `Null | Some s -> `String s);
  ]

let entry_of_json (j : Yojson.Basic.t) : entry =
  let open Yojson.Basic.Util in
  { name        = j |> member "name"   |> to_string;
    module_name = j |> member "module" |> to_string;
    kind        = j |> member "kind"   |> to_string |> kind_of_string;
    signature   = j |> member "signature" |> to_string;
    doc         = j |> member "doc"    |> to_string_option;
    file        = j |> member "file"   |> to_string;
    line        = j |> member "line"   |> to_int;
    params      = (j |> member "params" |> to_list
                   |> List.map (fun p ->
                       (p |> member "name" |> to_string,
                        p |> member "type" |> to_string)));
    return_type = j |> member "return_type" |> to_string_option;
  }

let index_to_json (idx : index) : string =
  let j : Yojson.Basic.t = `Assoc [
    "version",      `Int idx.version;
    "generated_at", `String idx.generated_at;
    "entries",      `List (List.map entry_to_json idx.entries);
  ] in
  Yojson.Basic.pretty_to_string j

let index_from_json (s : string) : index =
  let open Yojson.Basic.Util in
  let j = Yojson.Basic.from_string s in
  { version      = j |> member "version"      |> to_int;
    generated_at = j |> member "generated_at" |> to_string;
    entries      = j |> member "entries"      |> to_list |> List.map entry_of_json;
  }

(* ------------------------------------------------------------------ *)
(* Output formatting                                                   *)
(* ------------------------------------------------------------------ *)

(** Format an entry as plain text (no color). Used for piped/LLM output. *)
let format_entry (e : entry) : string =
  let loc = Printf.sprintf "%s:%d" e.file e.line in
  let name_part =
    if e.module_name = "" then e.name
    else e.module_name ^ "." ^ e.name
  in
  let headline = Printf.sprintf "%s  %s  %s" name_part e.signature loc in
  match e.doc with
  | None     -> headline
  | Some doc ->
    let first = match String.split_on_char '\n' doc with l :: _ -> l | [] -> "" in
    if first = "" then headline else headline ^ "\n  " ^ first

(** Format results as colored cards for terminal output. *)
let format_results_colored (results : (entry * float) list) : unit =
  if results = [] then
    Printf.printf "\027[2mno results found\027[0m\n"
  else begin
    let cyan  = "\027[36m" in
    let bold  = "\027[1m"  in
    let green = "\027[32m" in
    let dim   = "\027[2m"  in
    let reset = "\027[0m"  in
    let term_width =
      match Sys.getenv_opt "COLUMNS" with
      | Some s -> (try int_of_string s with _ -> 80)
      | None   -> 80
    in
    List.iter (fun (e, _) ->
      let loc = Printf.sprintf "%s:%d" (Filename.basename e.file) e.line in
      let name_visible =
        (if e.module_name = "" then "" else e.module_name ^ ".") ^ e.name
      in
      let name_colored =
        if e.module_name = "" then
          Printf.sprintf "%s%s%s" bold e.name reset
        else
          Printf.sprintf "%s%s%s.%s%s%s" cyan e.module_name reset bold e.name reset
      in
      let gap = max 2 (term_width - String.length name_visible - String.length loc) in
      Printf.printf "%s%s%s%s%s\n"
        name_colored (String.make gap ' ') dim loc reset;
      Printf.printf "  %s%s%s\n" green e.signature reset;
      (match e.doc with
       | None -> ()
       | Some d ->
         let first = match String.split_on_char '\n' d with l :: _ -> l | [] -> "" in
         if first <> "" then Printf.printf "  %s%s%s\n" dim first reset);
      print_newline ()
    ) results
  end

(** Format results as plain text for piped/LLM/tool output. *)
let format_results_plain (results : (entry * float) list) : unit =
  if results = [] then
    print_endline "no results found"
  else
    List.iter (fun (e, _) ->
      print_endline (format_entry e);
      print_newline ()
    ) results
