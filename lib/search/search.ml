(** March search index — Hoogle-style search for March functions and types.

    Supports three query modes:
    - Name search: fuzzy + substring matching using Levenshtein distance
    - Type signature search: string-based component matching
    - Doc keyword search: full-text keyword search over doc strings

    The index is built from parsed AST declarations and cached as JSON at
    [.march/search-index.json]. *)

module Ast = March_ast.Ast

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
      | Ast.FPPat _ -> ("_", "_")
    ) clause.fc_params

let make_fn_signature ~module_name (fn : Ast.fn_def) (params : (string * string) list) (ret : string option) =
  let prefix = if module_name = "" then "" else module_name ^ "." in
  let param_sig =
    String.concat ", " (List.map (fun (n, t) -> n ^ ": " ^ t) params)
  in
  prefix ^ fn.fn_name.txt ^
  "(" ^ param_sig ^ ")" ^
  (match ret with Some r -> " -> " ^ r | None -> "")

let rec collect_entries ~module_name ~file acc (decl : Ast.decl) =
  match decl with
  | Ast.DFn (fn, span) ->
    let params = extract_fn_params fn in
    let ret = Option.map pp_ast_ty fn.fn_ret_ty in
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

  | Ast.DType (_, name, _, typedef, span) ->
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
    List.fold_left (collect_entries ~module_name:sub ~file) acc decls

  | _ -> acc

(** Build an index from a list of (decls, source_file) pairs. *)
let build_index (decl_lists : Ast.decl list list) ~(source_files : string list) : index =
  let entries =
    List.fold_left2
      (fun acc decls file ->
        List.fold_left (collect_entries ~module_name:"" ~file) acc decls)
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
  let candidates = [
    "stdlib";
    Filename.concat (Filename.dirname Sys.executable_name) "../stdlib";
    Filename.concat (Filename.dirname Sys.executable_name) "../../stdlib";
    Filename.concat (Filename.dirname Sys.executable_name) "../../../stdlib";
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
           March_lexer.Lexer.token lexbuf in
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

(** Build a search index from all stdlib files. *)
let build_stdlib_index () : index =
  let (decl_lists, source_files) = load_stdlib () in
  build_index decl_lists ~source_files

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

(** Format an entry as a human-readable terminal line. *)
let format_entry (e : entry) : string =
  let loc = Printf.sprintf "%s:%d" e.file e.line in
  let padding =
    let sig_len = String.length e.signature in
    let loc_len = String.length loc in
    let width = 72 in
    let gap = width - sig_len - loc_len in
    if gap > 1 then String.make gap ' ' else "  "
  in
  let headline = e.signature ^ padding ^ loc in
  match e.doc with
  | None     -> headline
  | Some doc ->
    (* Wrap doc at 72 chars with 2-space indent *)
    headline ^ "\n  " ^ doc

(** Format results as a colored, aligned table for terminal output. *)
let format_results_pretty (results : (entry * float) list) : unit =
  if results = [] then
    print_endline "no results found"
  else begin
    let cyan  = "\027[36m" in
    let bold  = "\027[1m"  in
    let green = "\027[32m" in
    let dim   = "\027[2m"  in
    let reset = "\027[0m"  in
    let pad s n = s ^ String.make (max 0 (n - String.length s)) ' ' in
    let rows = List.map (fun (e, _) ->
      let loc = Printf.sprintf "%s:%d" e.file e.line in
      (e.module_name, e.name, e.signature, loc, e.doc)
    ) results in
    let w1 = List.fold_left (fun acc (m, _, _, _, _) ->
      max acc (String.length m)) (String.length "Module") rows in
    let w2 = List.fold_left (fun acc (_, n, _, _, _) ->
      max acc (String.length n)) (String.length "Name") rows in
    let w3 = List.fold_left (fun acc (_, _, s, _, _) ->
      max acc (String.length s)) (String.length "Signature") rows in
    Printf.printf "%s  %s  %s  %s\n"
      (pad "Module" w1) (pad "Name" w2) (pad "Signature" w3) "Location";
    Printf.printf "%s  %s  %s  %s\n"
      (String.make w1 '-') (String.make w2 '-')
      (String.make w3 '-') "--------";
    List.iter (fun (modname, name, sig_, loc, doc) ->
      Printf.printf "%s%s%s  %s%s%s  %s%s%s  %s%s%s\n"
        cyan  (pad modname w1) reset
        bold  (pad name   w2) reset
        green (pad sig_   w3) reset
        dim   loc             reset;
      (match doc with
       | None -> ()
       | Some d ->
         let first_line =
           match String.split_on_char '\n' d with l :: _ -> l | [] -> ""
         in
         if first_line <> "" then
           Printf.printf "  %s%s%s\n" dim first_line reset)
    ) rows
  end
