(** Module export registry — maps module names to their exported bindings.
    Populated by loading stdlib .march files and by processing DMod declarations.
    Queried by typecheck, eval, and TIR lower when resolving qualified names. *)

open March_ast.Ast

type export_kind =
  | ExFn
  | ExType of int
  | ExCtor of string * int
  | ExValue

type export_entry = {
  ex_name : string;
  ex_kind : export_kind;
  ex_public : bool;
}

type module_exports = {
  me_name : string;
  me_entries : export_entry list;
}

(* ---- Global state ---- *)

(** The registry: module name → exports. *)
let registry : (string, module_exports) Hashtbl.t = Hashtbl.create 32

(** Modules currently being loaded (circular dependency sentinel). *)
let loading : (string, unit) Hashtbl.t = Hashtbl.create 4

(** Stdlib directory path, set by the compiler entry point. *)
let _stdlib_dir : string option ref = ref None

(* ---- Public API ---- *)

let register name exports =
  Hashtbl.replace registry name exports

let lookup name =
  Hashtbl.find_opt registry name

let is_known_module name =
  Hashtbl.mem registry name || Hashtbl.mem loading name

let set_stdlib_dir dir =
  _stdlib_dir := Some dir

let reset () =
  Hashtbl.clear registry;
  Hashtbl.clear loading;
  _stdlib_dir := None

(* ---- Stdlib file discovery ---- *)

(** Convert CamelCase module name to snake_case .march filename.
    E.g. "HttpClient" → "http_client.march" *)
let module_name_to_filename name =
  let buf = Buffer.create (String.length name + 8) in
  String.iteri (fun i c ->
    if i > 0 && c >= 'A' && c <= 'Z' then begin
      Buffer.add_char buf '_';
      Buffer.add_char buf (Char.lowercase_ascii c)
    end else
      Buffer.add_char buf (Char.lowercase_ascii c)
  ) name;
  Buffer.add_string buf ".march";
  Buffer.contents buf

let find_stdlib_dir () =
  match !_stdlib_dir with
  | Some d -> Some d
  | None ->
    let candidates = [
      "stdlib";
      Filename.concat (Filename.dirname Sys.executable_name) "../stdlib";
      Filename.concat (Filename.dirname Sys.executable_name) "../../stdlib";
      Filename.concat (Filename.dirname Sys.executable_name) "../../../stdlib";
    ] in
    List.find_opt (fun d -> Sys.file_exists d && Sys.is_directory d) candidates

let find_stdlib_file mod_name =
  match find_stdlib_dir () with
  | None -> None
  | Some dir ->
    let fname = module_name_to_filename mod_name in
    let path = Filename.concat dir fname in
    if Sys.file_exists path then Some path else None

(* ---- Extracting exports from parsed declarations ---- *)

(** Extract public exports from a list of declarations (the body of a module). *)
let extract_exports (mod_name : string) (decls : decl list) : module_exports =
  let entries = List.concat_map (fun decl ->
    match decl with
    | DFn (fdef, _) ->
      let vis = fdef.fn_vis in
      [{ ex_name = fdef.fn_name.txt;
         ex_kind = ExFn;
         ex_public = vis = Public }]
    | DLet (vis, bind, _) ->
      let name = match bind.bind_pat with
        | PatVar n -> n.txt
        | _ -> "_"
      in
      [{ ex_name = name; ex_kind = ExValue; ex_public = vis = Public }]
    | DType (vis, tname, tparams, tdef, _) ->
      let arity = List.length tparams in
      let type_entry = { ex_name = tname.txt; ex_kind = ExType arity;
                         ex_public = vis = Public } in
      let ctor_entries = match tdef with
        | TDVariant ctors ->
          List.map (fun (v : variant) ->
            { ex_name = v.var_name.txt;
              ex_kind = ExCtor (tname.txt, List.length v.var_args);
              ex_public = vis = Public }
          ) ctors
        | _ -> []
      in
      type_entry :: ctor_entries
    | _ -> []
  ) decls in
  { me_name = mod_name; me_entries = entries }

(* ---- Loading and parsing ---- *)

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let b = Bytes.create n in
  really_input ic b 0 n;
  close_in ic;
  Bytes.to_string b

let parse_file path src =
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
  try
    Ok (March_parser.Parser.module_
          (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
  with _ -> Error (Printf.sprintf "Failed to parse %s" path)

let ensure_loaded mod_name =
  match Hashtbl.find_opt registry mod_name with
  | Some exports -> Some exports
  | None ->
    if Hashtbl.mem loading mod_name then
      (* Circular dependency — return empty placeholder *)
      Some { me_name = mod_name; me_entries = [] }
    else
      match find_stdlib_file mod_name with
      | None -> None
      | Some path ->
        Hashtbl.add loading mod_name ();
        let result =
          try
            let src = read_file path in
            match parse_file path src with
            | Error _ ->
              Hashtbl.remove loading mod_name;
              None
            | Ok ast ->
              let ast = March_desugar.Desugar.desugar_module ast in
              let exports = extract_exports mod_name ast.mod_decls in
              Hashtbl.remove loading mod_name;
              register mod_name exports;
              Some exports
          with _ ->
            Hashtbl.remove loading mod_name;
            None
        in
        result
