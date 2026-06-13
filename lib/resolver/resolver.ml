(** March cross-file import resolver — shared between the compiler entry
    point (bin/main.ml), the REPL (lib/repl/repl.ml), and the LSP
    (lsp/lib/analysis.ml).

    This is the single source of truth for module resolution.  It resolves
    explicit [import]/[alias] declarations by filename convention AND
    auto-discovers every .march file reachable through the library search
    path, indexing modules by their DECLARED name — so a module like
    [Bastion.Channel] living in [channel.march] resolves the same way for
    `forge check`, the REPL, and editor diagnostics. *)

(** Convert a single CamelCase segment to snake_case.
    E.g. "HttpClient" → "http_client", "Router" → "router" *)
let camel_to_snake name =
  let buf = Buffer.create (String.length name + 4) in
  String.iteri (fun i c ->
    if i > 0 && c >= 'A' && c <= 'Z' then begin
      Buffer.add_char buf '_';
      Buffer.add_char buf (Char.lowercase_ascii c)
    end else
      Buffer.add_char buf (Char.lowercase_ascii c)
  ) name;
  Buffer.contents buf

(** Convert a possibly-dotted module name to a relative file path.
    Single segment: "HttpClient" → "http_client.march"
    Dotted:         "MyApp.Router" → "my_app/router.march"
                    "MyApp.Templates.Layout" → "my_app/templates/layout.march" *)
let module_name_to_filename name =
  let parts = String.split_on_char '.' name in
  let snake_parts = List.map camel_to_snake parts in
  String.concat Filename.dir_sep snake_parts ^ ".march"

(** Stdlib module names — used only to SUPPRESS "module not found" errors
    for imports that resolve from the bundled stdlib.  A user file with the
    same conventional filename always wins (it is found first), so listing
    a name here never shadows user code. *)
let stdlib_module_names =
  [ "List"; "Map"; "Set"; "Array"; "Queue"; "String"; "Option"; "Result"
  ; "Math"; "Enum"; "BigInt"; "Decimal"; "DateTime"; "Duration"; "Bytes"; "Json"
  ; "Regex"; "Csv"; "File"; "Dir"; "Path"; "Http"; "HttpClient"
  ; "HttpServer"; "HttpTransport"; "WebSocket"; "Process"; "Logger"
  ; "Flow"; "Actor"; "Sort"; "Hamt"; "Seq"; "Iterable"; "IOList"
  ; "Random"; "Stats"; "Plot"; "Prelude"; "DataFrame"; "Test"
  ; "Vault"; "URI"
  ; "Depot"; "Depot.Gate"
  ; "Config"; "Crypto"; "Env"; "Channel"; "PubSub"
  ; "ChannelServer"; "ChannelSocket"; "Presence"; "Tls"; "Uuid"
  ; "DepotForm"; "DepotGate"; "DepotSchema"; "DepotRepo"
  ; "DepotQuery"; "DepotMigration"; "DepotTest"
  ; "Tuple"; "Char"; "OrderedMap"; "SortedSet"; "Range" ]

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

let read_file path =
  let ic = open_in_bin path in
  let n  = in_channel_length ic in
  let b  = Bytes.create n in
  really_input ic b 0 n;
  close_in ic;
  Bytes.to_string b

(** Parse a .march source file.  Returns [Ok module_ast] or [Error msg].
    Applies a span-remap sidecar when one exists (template-lowered files). *)
let parse_march_file path src =
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
  try
    let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
    let m = match March_ast.Span_remap.load_sidecar path with
      | Some tbl -> March_ast.Span_remap.remap_module tbl m
      | None -> m
    in
    Ok m
  with
  | March_errors.Errors.ParseError (msg, _hint, pos) ->
    let open Lexing in
    Error (Printf.sprintf "%s:%d: parse error: %s" path pos.pos_lnum msg)
  | March_parser.Parser.Error ->
    let pos = Lexing.lexeme_start_p lexbuf in
    let open Lexing in
    Error (Printf.sprintf "%s:%d: parse error" path pos.pos_lnum)

(** Recursively collect all .march files under [dir].
    Entries are sorted so discovery order is deterministic — raw
    [Sys.readdir] order is unspecified and filesystem-dependent, which
    would make whole-program module discovery vary across machines. *)
let collect_lib_files dir =
  let rec walk acc d =
    if not (Sys.file_exists d && Sys.is_directory d) then acc
    else begin
      let entries = Sys.readdir d in
      Array.sort compare entries;
      Array.fold_left (fun acc name ->
          let p = Filename.concat d name in
          (* A dangling symlink makes [Sys.is_directory] (which stats through
             the link) raise [Sys_error]; skip any entry we can't stat rather
             than aborting the whole compile. *)
          match Sys.is_directory p with
          | true -> walk acc p
          | false -> if Filename.check_suffix p ".march" then p :: acc else acc
          | exception (Sys_error _ | Unix.Unix_error _) -> acc)
        acc entries
    end
  in
  walk [] dir

(** Resolve cross-file imports and auto-discover project library files.

    Step 1 resolves explicit [import]/[alias] declarations from the entry
    module (by filename convention).  Step 2 auto-discovers all .march
    files in the library search path so that qualified cross-module calls
    (e.g. MyApp.Router.dispatch) and modules whose declared name does not
    match their filename (mod Bastion.Channel in channel.march) work
    without explicit [use] declarations — required for multi-file projects.

    The search path is [source_dir :: extra_lib_paths @ MARCH_LIB_PATH].
    [extra_lib_paths] lets callers (e.g. the LSP) inject paths derived from
    forge.toml without requiring the env var to be set.

    Returns (errors, extra_dmods_to_prepend, user_files) where [user_files]
    is every file loaded as user code (entry + imports + discovered libs) —
    callers use it to decide which typecheck diagnostics are fatal. *)
let resolve_imports ?(extra_lib_paths = []) ?(auto_discover = true)
    ~source_file (m : March_ast.Ast.module_) =
  let source_dir = Filename.dirname source_file in
  let env_lib_paths =
    match Sys.getenv_opt "MARCH_LIB_PATH" with
    | None -> []
    | Some s -> List.filter (fun d -> d <> "") (String.split_on_char ':' s)
  in
  let all_lib_paths = extra_lib_paths @ env_lib_paths in
  let search_path = source_dir :: all_lib_paths in
  let resolved : (string, March_ast.Ast.decl list) Hashtbl.t = Hashtbl.create 8 in
  (* Track loaded file paths so the same file is never parsed twice *)
  let loaded_paths : (string, unit) Hashtbl.t = Hashtbl.create 8 in
  (* [loaded_paths] is keyed by CANONICAL (realpath) paths for dedup, but
     diagnostic spans carry the path string the file was PARSED under
     (pos_fname = the possibly-relative path used to open it).  Callers do
     exact membership checks of span files against [user_files], so record
     BOTH forms — returning only the canonical form silently un-fixed the
     imported-module error filter (regression fixture:
     test/imports/entry_imports_ill_typed.march). *)
  let user_files = ref [] in
  let note_user_file path canon =
    user_files :=
      path :: (if canon = path then [] else [canon]) @ !user_files
  in
  let in_progress : (string, unit) Hashtbl.t = Hashtbl.create 4 in
  let errors : (string * March_ast.Ast.span * string) list ref = ref [] in
  let dummy_span = March_ast.Ast.dummy_span in
  (* Pre-mark the entry file so auto-discovery never re-loads it.
     Canonicalise the path so that relative and absolute references to the
     same file are treated as identical (prevents the file being loaded a
     second time when it also appears in the lib path as an absolute path). *)
  let canonical_source =
    (try Unix.realpath source_file with Unix.Unix_error _ -> source_file) in
  Hashtbl.add loaded_paths canonical_source ();
  note_user_file source_file canonical_source;

  let find_file mod_name =
    let fname = module_name_to_filename mod_name in
    List.find_map (fun dir ->
        let p = Filename.concat dir fname in
        if Sys.file_exists p then Some p else None
      ) search_path
  in

  let rec load mod_name ~from_span =
    if Hashtbl.mem resolved mod_name then
      (* Already emitted at some point — never re-emit (would duplicate decls) *)
      []
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
          let canon_fp =
            (try Unix.realpath file_path with Unix.Unix_error _ -> file_path) in
          if Hashtbl.mem loaded_paths canon_fp then
            (* Already loaded (entry file or earlier import) — avoid duplication *)
            []
          else begin
            Hashtbl.add loaded_paths canon_fp ();
            note_user_file file_path canon_fp;
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
                (* Mark resolved BEFORE recursing so cycles don't duplicate. *)
                Hashtbl.add resolved mod_name [];
                let transitive = load_refs ast.March_ast.Ast.mod_decls in
                let self_dmod =
                  March_ast.Ast.DMod (ast.March_ast.Ast.mod_name,
                                      March_ast.Ast.Public,
                                      ast.March_ast.Ast.mod_decls,
                                      dummy_span)
                in
                (* Emit transitive imports as top-level siblings, NOT nested.
                   Nesting would cause TIR to prefix their fn names with this
                   module's name (e.g. `Runner.foo` → `Processes.Runner.foo`),
                   which breaks qualified cross-module calls at link time. *)
                transitive @ [self_dmod]
          end
      in
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

  (* Step 1: resolve explicit imports (DUse/DAlias) from the entry file *)
  let explicit_decls = load_refs m.March_ast.Ast.mod_decls in
  (* Mark all explicitly-loaded modules (and their nested transitive deps) as
     already-emitted.  This prevents them from being re-embedded as transitive
     deps inside auto-discovered DMods in step 2.  Without this, every
     submodule that does `import App` would embed the entire App DMod
     inside itself, causing O(N²) typecheck cost. *)
  let rec mark_emitted_decls = function
    | [] -> ()
    | March_ast.Ast.DMod ({March_ast.Ast.txt = mn; _}, _, inner, _) :: rest ->
      Hashtbl.replace resolved mn [];
      mark_emitted_decls inner;
      mark_emitted_decls rest
    | _ :: rest -> mark_emitted_decls rest
  in
  mark_emitted_decls explicit_decls;

  (* Step 2: auto-discover all .march files in the library search path.
     Load any that were not already pulled in via explicit imports.
     Two-phase: parse all files first to learn their module names, then sort
     by module-name depth (more dot-segments = deeper namespace = fewer
     dependents = load first) so dependencies are in env before their users. *)
  let dot_count s =
    String.fold_left (fun n c -> if c = '.' then n + 1 else n) 0 s
  in
  let auto_decls =
    if not auto_discover then []
    else
    List.concat_map (fun lib_dir ->
        let files = collect_lib_files lib_dir in
        (* Phase 1: parse + desugar all un-loaded files to learn their mod names *)
        let parsed = List.filter_map (fun file_path ->
            let canon_fp =
              (try Unix.realpath file_path with Unix.Unix_error _ -> file_path) in
            if Hashtbl.mem loaded_paths canon_fp then None
            else
              let src = try read_file file_path with Sys_error _ -> "" in
              if src = "" then None
              else
                match parse_march_file file_path src with
                | Error msg ->
                  Printf.eprintf "[lib] %s\n%!" msg; None
                | Ok ast ->
                  Some (canon_fp, file_path, March_desugar.Desugar.desugar_module ast)
          ) files in
        (* Sort: more dot-segments in mod name → load first (namespace leaves).
           Alphabetical tiebreak keeps things deterministic. *)
        let sorted = List.sort (fun (_, _, a) (_, _, b) ->
            let mn ast = ast.March_ast.Ast.mod_name.March_ast.Ast.txt in
            let da = dot_count (mn a) and db = dot_count (mn b) in
            if db <> da then compare db da
            else compare (mn a) (mn b)
          ) parsed in
        (* Phase 2: build DMods in sorted order.  Emit transitive imports as
           top-level siblings (not nested) to avoid name-mangling collisions.
           [canon_fp] keys the dedup; [orig_path] is the string the file was
           parsed under (= what its spans carry), recorded for user_files. *)
        List.concat_map (fun (canon_fp, orig_path, ast) ->
            if Hashtbl.mem loaded_paths canon_fp then []
            else begin
              Hashtbl.add loaded_paths canon_fp ();
              note_user_file orig_path canon_fp;
              let mn = ast.March_ast.Ast.mod_name.March_ast.Ast.txt in
              if Hashtbl.mem resolved mn then []
              else begin
                (* Mark emitted BEFORE load_refs so recursive imports don't
                   re-emit this module inside their own transitive set. *)
                Hashtbl.add resolved mn [];
                let transitive = load_refs ast.March_ast.Ast.mod_decls in
                let self_dmod =
                  March_ast.Ast.DMod (ast.March_ast.Ast.mod_name,
                                      March_ast.Ast.Public,
                                      ast.March_ast.Ast.mod_decls,
                                      dummy_span)
                in
                transitive @ [self_dmod]
              end
            end
          ) sorted
      ) all_lib_paths
  in

  (* Every file loaded here is USER code (the entry file plus modules from
     the source dir / lib path).  Callers use this list to decide which
     typecheck diagnostics are fatal: errors in any of these files must
     abort, while stdlib-internal errors are tolerated (some stdlib modules
     are WIP).  Membership is exact, so [user_files] carries BOTH the
     parse-time path string of each file (what its spans record) and its
     canonical realpath — and is robust against stdlib files whose cached
     spans point at a different install location. *)
  (!errors, explicit_decls @ auto_decls,
   List.sort_uniq String.compare !user_files)
