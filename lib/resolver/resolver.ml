(** March cross-file import resolver — shared between the compiler
    entry point (bin/main.ml) and the REPL (lib/repl/repl.ml). *)

(** Convert a CamelCase module name to a snake_case .march filename.
    E.g. "HttpClient" → "http_client.march", "Message" → "message.march" *)
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

(** Stdlib module names — always resolved from the bundled stdlib, never
    from the user's source tree. *)
let stdlib_module_names =
  [ "List"; "Map"; "Set"; "Array"; "Queue"; "String"; "Option"; "Result"
  ; "Math"; "Enum"; "BigInt"; "Decimal"; "DateTime"; "Bytes"; "Json"
  ; "Regex"; "Csv"; "File"; "Dir"; "Path"; "Http"; "HttpClient"
  ; "HttpServer"; "HttpTransport"; "WebSocket"; "Process"; "Logger"
  ; "Flow"; "Actor"; "Sort"; "Hamt"; "Seq"; "Iterable"; "IOList"
  ; "Random"; "Stats"; "Plot"; "Prelude"; "DataFrame" ]

(** Collect [(mod_name, span)] for each DUse/DAlias in [decls],
    recursing into nested DMod blocks so that imports written inside
    `mod Foo do import Bar ... end` are also resolved. *)
let rec import_refs decls =
  List.concat_map (function
    | March_ast.Ast.DUse (ud, sp) ->
      (match ud.March_ast.Ast.use_path with
       | n :: _ -> [(n.March_ast.Ast.txt, sp)]
       | [] -> [])
    | March_ast.Ast.DAlias (ad, sp) ->
      (match ad.March_ast.Ast.alias_path with
       | n :: _ -> [(n.March_ast.Ast.txt, sp)]
       | [] -> [])
    | March_ast.Ast.DMod (_, _, inner_decls, _) ->
      import_refs inner_decls
    | _ -> []
  ) decls

(** Parse a .march source file.  Returns [Ok module_ast] or [Error msg]. *)
let parse_march_file path src =
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
  try Ok (March_parser.Parser.module_ March_lexer.Lexer.token lexbuf)
  with
  | March_errors.Errors.ParseError (msg, _hint, pos) ->
    let open Lexing in
    Error (Printf.sprintf "%s:%d: parse error: %s" path pos.pos_lnum msg)
  | March_parser.Parser.Error ->
    let pos = Lexing.lexeme_start_p lexbuf in
    let open Lexing in
    Error (Printf.sprintf "%s:%d: parse error" path pos.pos_lnum)

let read_file path =
  let ic = open_in_bin path in
  let n  = in_channel_length ic in
  let b  = Bytes.create n in
  really_input ic b 0 n;
  close_in ic;
  Bytes.to_string b

(** Resolve cross-file imports.
    Scans [m.mod_decls] for DUse/DAlias that name user modules (not stdlib),
    finds their .march files, parses and desugars them, detects cycles.
    Returns (errors, extra_dmods_to_prepend).

    [extra_lib_paths] are prepended to the search path before [MARCH_LIB_PATH].
    This lets callers (e.g. the LSP) inject paths derived from forge.toml deps
    without requiring the env var to be set. *)
let resolve_imports ?(extra_lib_paths=[]) ~source_file (m : March_ast.Ast.module_) =
  let source_dir = Filename.dirname source_file in
  let env_lib_paths =
    match Sys.getenv_opt "MARCH_LIB_PATH" with
    | None -> []
    | Some s -> List.filter (fun d -> d <> "") (String.split_on_char ':' s)
  in
  let search_path = source_dir :: (extra_lib_paths @ env_lib_paths) in
  let resolved : (string, March_ast.Ast.decl list) Hashtbl.t = Hashtbl.create 8 in
  let in_progress : (string, unit) Hashtbl.t = Hashtbl.create 4 in
  let errors : (string * March_ast.Ast.span * string) list ref = ref [] in
  let dummy_span = March_ast.Ast.dummy_span in

  let find_file mod_name =
    let fname = module_name_to_filename mod_name in
    List.find_map (fun dir ->
        let p = Filename.concat dir fname in
        if Sys.file_exists p then Some p else None
      ) search_path
  in

  let rec load mod_name ~from_span =
    if Hashtbl.mem resolved mod_name then
      Hashtbl.find resolved mod_name
    else if Hashtbl.mem in_progress mod_name then begin
      errors := (mod_name, from_span,
        Printf.sprintf
          "Circular import: module `%s` imports itself (directly or transitively)"
          mod_name) :: !errors;
      []
    end else begin
      Hashtbl.add in_progress mod_name ();
      let result =
        match find_file mod_name with
        | None ->
          if not (List.mem mod_name stdlib_module_names) then
            errors := (mod_name, from_span,
              Printf.sprintf
                "Module `%s` not found (looked for `%s` in the source directory)"
                mod_name (module_name_to_filename mod_name)) :: !errors;
          []
        | Some file_path ->
          let src =
            try read_file file_path
            with Sys_error msg ->
              errors := (mod_name, from_span,
                Printf.sprintf "Cannot read `%s`: %s" file_path msg) :: !errors;
              ""
          in
          if src = "" then []
          else
            match parse_march_file file_path src with
            | Error msg ->
              errors := (mod_name, from_span, msg) :: !errors; []
            | Ok ast ->
              let ast = March_desugar.Desugar.desugar_module ast in
              let transitive = load_refs ast.March_ast.Ast.mod_decls in
              let all_decls = transitive @ ast.March_ast.Ast.mod_decls in
              [ March_ast.Ast.DMod (ast.March_ast.Ast.mod_name,
                                    March_ast.Ast.Public,
                                    all_decls,
                                    dummy_span) ]
      in
      Hashtbl.add resolved mod_name result;
      Hashtbl.remove in_progress mod_name;
      result
    end

  and load_refs decls =
    let refs = import_refs decls in
    let seen : (string, unit) Hashtbl.t = Hashtbl.create 4 in
    List.concat_map (fun (mod_name, span) ->
        if Hashtbl.mem seen mod_name
           || List.mem mod_name stdlib_module_names
        then []
        else begin
          Hashtbl.add seen mod_name ();
          load mod_name ~from_span:span
        end
      ) refs
  in
  let extra_decls = load_refs m.March_ast.Ast.mod_decls in
  (!errors, extra_decls)
