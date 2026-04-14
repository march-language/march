(** March compiler entry point. *)

(* ------------------------------------------------------------------ *)
(* Stdlib loader                                                       *)
(* ------------------------------------------------------------------ *)

(** Resolve an executable name to an absolute path.
    If the name already contains a slash it is used as-is (after resolving
    relative to CWD).  Otherwise PATH is searched.  Falls back to the raw
    name if nothing is found. *)
let resolve_exe_path name =
  if String.contains name '/' then
    (* relative or absolute path — resolve against CWD *)
    if String.length name > 0 && name.[0] = '/' then name
    else Filename.concat (Sys.getcwd ()) name
  else begin
    let path_dirs =
      match Sys.getenv_opt "PATH" with
      | None   -> ["/usr/local/bin"; "/usr/bin"; "/bin"]
      | Some p -> String.split_on_char ':' p
    in
    match List.find_opt (fun d ->
        let p = Filename.concat d name in
        Sys.file_exists p && not (Sys.is_directory p)
      ) path_dirs with
    | Some d -> Filename.concat d name
    | None   -> name
  end

(** Locate the stdlib directory.
    Resolution order:
    1. MARCH_STDLIB environment variable (explicit override)
    2. Paths relative to the resolved march executable:
       - bin/../stdlib          (source-tree / opam switch layout)
       - bin/../../stdlib       (nested build layout)
       - bin/../share/march/stdlib  (installed share layout)
    3. "stdlib" relative to CWD (works when running from the March repo root) *)
let find_stdlib_dir () =
  match Sys.getenv_opt "MARCH_STDLIB" with
  | Some p when Sys.file_exists p -> Some p
  | _ ->
    let exe_path = resolve_exe_path Sys.executable_name in
    let exe_dir  = Filename.dirname exe_path in
    let candidates = [
      (* Exe-relative candidates — work regardless of CWD *)
      Filename.concat exe_dir "../stdlib";
      Filename.concat exe_dir "../../stdlib";
      (* Installed share layout: bin/../share/march/stdlib or bin/../share/march *)
      Filename.concat exe_dir "../share/march/stdlib";
      Filename.concat exe_dir "../share/march";
      (* CWD-relative fallback — works when invoked from the March repo root *)
      "stdlib";
    ] in
    List.find_opt Sys.file_exists candidates

(** Parse a stdlib source file and return its top-level declarations.
    Each stdlib file is a single [mod Name do ... end] wrapper.
    - For "prelude.march": the inner declarations are returned directly,
      so they land in the user module's top-level scope.
    - For all other files: the whole [DMod] is returned, so the module
      is accessible as e.g. [Option.is_some]. *)
let load_stdlib_file path =
  let src =
    try
      let ic = open_in path in
      let n = in_channel_length ic in
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
       let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
       let m = March_desugar.Desugar.desugar_module m in
       let basename = Filename.basename path in
       if basename = "prelude.march" then
         (* Unwrap the outer mod so prelude functions are in global scope *)
         (match m.March_ast.Ast.mod_decls with
          | [March_ast.Ast.DMod (_, _, inner_decls, _)] -> inner_decls
          | decls -> decls)
       else
         (* Wrap in a DMod so names are accessible as Module.name *)
         [March_ast.Ast.DMod (m.March_ast.Ast.mod_name,
                              March_ast.Ast.Public,
                              m.March_ast.Ast.mod_decls,
                              March_ast.Ast.dummy_span)]
     with
     | March_parser.Parser.Error ->
       let pos = Lexing.lexeme_start_p lexbuf in
       Printf.eprintf "[stdlib] parse error in %s at line %d col %d\n%!"
         path pos.Lexing.pos_lnum (pos.Lexing.pos_cnum - pos.Lexing.pos_bol);
       []
     | exn ->
       Printf.eprintf "[stdlib] error in %s: %s\n%!" path (Printexc.to_string exn); [])

(** The ordered list of stdlib file names. *)
let stdlib_file_list = [
  "prelude.march";
  "option.march";
  "result.march";
  "list.march";
  "hamt.march";
  "map.march";
  "math.march";
  "string.march";
  "iolist.march";
  "html.march";
  "sigil.march";
  "http.march";
  "http_transport.march";
  "http_client.march";
  "seq.march";
  "path.march";
  "file.march";
  "dir.march";
  "sort.march";
  "csv.march";
  "websocket.march";
  "http_server.march";
  "iterable.march";
  "set.march";
  "array.march";
  "bigint.march";
  "decimal.march";
  "duration.march";
  "bytes.march";
  "process.march";
  "io.march";
  "system.march";
  "logger.march";
  "actor.march";
  "flow.march";
  "json.march";
  "regex.march";
  "datetime.march";
  "queue.march";
  "enum.march";
  "random.march";
  "stats.march";
  "plot.march";
  "dataframe.march";
  "tls.march";
  "uuid.march";
  "vault.march";
  "channel.march";
  "pubsub.march";
  "channel_server.march";
  "channel_socket.march";
  "presence.march";
  "env.march";
  "config.march";
  "test.march";
  "tuple.march";
  "char.march";
  "ordered_map.march";
  "sorted_set.march";
  "range.march";
  "crypto.march";
  "base64.march";
  "native_array.march";
  "task.march";
  "uri.march";
  "forge_nb.march";
]

(** Read all stdlib source files and compute a hash of their contents.
    Returns (stdlib_dir, source_hash, file_paths). *)
let stdlib_source_hash () =
  match find_stdlib_dir () with
  | None -> None
  | Some stdlib_dir ->
    let paths = List.map (Filename.concat stdlib_dir) stdlib_file_list in
    let buf = Buffer.create (256 * 1024) in
    List.iter (fun path ->
      try
        let ic = open_in path in
        let n = in_channel_length ic in
        let bytes = Bytes.create n in
        really_input ic bytes 0 n;
        close_in ic;
        Buffer.add_bytes buf bytes
      with Sys_error _ -> ()
    ) paths;
    let hash = Digest.to_hex (Digest.string (Buffer.contents buf)) in
    Some (stdlib_dir, hash, paths)

(** Load all stdlib modules and return their declarations, to be
    prepended to the user module before evaluation.
    Uses a content-hash-keyed cache of parsed+desugared ASTs. *)
let load_stdlib () =
  match stdlib_source_hash () with
  | None -> []
  | Some (stdlib_dir, source_hash, _) ->
    let home = (try Sys.getenv "HOME" with Not_found -> ".") in
    let cache_dir = Filename.concat home ".cache/march" in
    let short_hash = String.sub source_hash 0 16 in
    let cache_path = Filename.concat cache_dir
      ("stdlib_ast_" ^ short_hash ^ ".bin") in
    (* Cache hit: unmarshal parsed ASTs *)
    match (try
      if Sys.file_exists cache_path then begin
        let ic = open_in_bin cache_path in
        let data : March_ast.Ast.decl list = Marshal.from_channel ic in
        close_in ic;
        Some data
      end else None
    with _ -> None) with
    | Some decls -> decls
    | None ->
      (* Cache miss: parse all files, then cache *)
      let decls = List.concat_map (fun name ->
          load_stdlib_file (Filename.concat stdlib_dir name)
        ) stdlib_file_list in
      (try
        (try Unix.mkdir cache_dir 0o755
         with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
        let oc = open_out_bin cache_path in
        Marshal.to_channel oc decls [];
        close_out oc
      with _ -> ());
      decls

(** Pre-compile the C runtime to a shared library.
    Cached at ~/.cache/march/libmarch_runtime.so.
    Returns the path to the .so. *)
let ensure_runtime_so () =
  let home = Sys.getenv "HOME" in
  let dot_cache = Filename.concat home ".cache" in
  let cache_dir = Filename.concat dot_cache "march" in
  (* Create parent directories recursively *)
  List.iter (fun d ->
    try Unix.mkdir d 0o755
    with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  ) [dot_cache; cache_dir];
  let so_path = Filename.concat cache_dir "libmarch_runtime.so" in
  (* Find runtime source *)
  let candidates = [
    "runtime/march_runtime.c";
    Filename.concat (Filename.dirname Sys.executable_name) "../runtime/march_runtime.c";
    Filename.concat (Filename.dirname Sys.executable_name) "../../runtime/march_runtime.c";
  ] in
  let runtime_c_opt = List.find_opt Sys.file_exists candidates in
  let so_exists = Sys.file_exists so_path in
  (* If the .so is already cached and we can't find the source, just use the cache. *)
  let runtime_c = match runtime_c_opt with
    | Some p -> p
    | None ->
      if so_exists then ""  (* use cached .so as-is *)
      else failwith "march: cannot find runtime/march_runtime.c"
  in
  let runtime_dir = if runtime_c = "" then "" else Filename.dirname runtime_c in
  (* Recompile if .so is missing or source is newer than the cached .so *)
  let needs_compile =
    not so_exists ||
    (runtime_c <> "" && (Unix.stat runtime_c).st_mtime > (Unix.stat so_path).st_mtime)
  in
  if needs_compile then begin
    (* Note: -lpthread not needed on macOS (pthreads are in libSystem). *)
    let http_c = Filename.concat runtime_dir "march_http.c" in
    let extras_c = Filename.concat runtime_dir "march_extras.c" in
    let opt_file f = if Sys.file_exists f then Printf.sprintf " %s" f else "" in
    let extra_files =
      if Sys.file_exists http_c then
        let sha1_c    = Filename.concat runtime_dir "sha1.c" in
        let base64_c  = Filename.concat runtime_dir "base64.c" in
        let simd_c    = Filename.concat runtime_dir "march_http_parse_simd.c" in
        let sched_c   = Filename.concat runtime_dir "march_scheduler.c" in
        let resp_c    = Filename.concat runtime_dir "march_http_response.c" in
        let io_c      = Filename.concat runtime_dir "march_http_io.c" in
        let evloop_c  = Filename.concat runtime_dir "march_http_evloop.c" in
        let tls_c     = Filename.concat runtime_dir "march_tls.c" in
        Printf.sprintf " %s %s %s%s%s%s%s%s%s%s" http_c sha1_c base64_c
          (opt_file simd_c) (opt_file sched_c) (opt_file resp_c)
          (opt_file io_c) (opt_file evloop_c) (opt_file tls_c) (opt_file extras_c)
      else (opt_file extras_c)
    in
    (* OpenSSL flags: needed when march_tls.c is included. *)
    let tls_c = Filename.concat runtime_dir "march_tls.c" in
    let openssl_flags =
      if not (Sys.file_exists tls_c) then ""
      else
        let dirs = [
          "/opt/homebrew/opt/openssl@3";
          "/opt/homebrew/opt/openssl";
          "/usr/local/opt/openssl@3";
          "/usr/local/opt/openssl";
          "/usr/include/openssl";
        ] in
        let found = List.fold_left (fun acc d ->
          match acc with
          | Some _ -> acc
          | None ->
            let hdr = Filename.concat d "include/openssl/ssl.h" in
            if Sys.file_exists hdr then Some d else None
        ) None dirs in
        match found with
        | Some d ->
          Printf.sprintf " -I%s/include -L%s/lib -lssl -lcrypto" d d
        | None ->
          (* Try pkg-config *)
          if Sys.command "pkg-config --exists openssl 2>/dev/null" = 0 then
            " -lssl -lcrypto"
          else ""
    in
    let evloop_flag =
      let evloop_c = Filename.concat runtime_dir "march_http_evloop.c" in
      if Sys.file_exists evloop_c then " -DMARCH_HTTP_USE_EVLOOP" else ""
    in
    let cmd = Printf.sprintf
      "clang -shared -O2 -fPIC -msse4.2 -Wno-unused-command-line-argument%s -I%s %s%s%s -o %s 2>&1"
      evloop_flag runtime_dir runtime_c extra_files openssl_flags so_path in
    let rc = Sys.command cmd in
    if rc <> 0 then
      failwith (Printf.sprintf "march: failed to compile runtime .so (clang exit %d)" rc)
  end;
  so_path

let dump_tir       = ref false
let dump_phases    = ref false
let emit_llvm      = ref false
let do_compile     = ref false
let do_test        = ref false   (* --test: compile test blocks into a test-runner binary *)
let output_file    = ref ""
let debug_mode     = ref false
let debug_tui_mode = ref false
let opt_enabled    = ref true
let fast_math      = ref false
let opt_level      = ref (-1)   (* -1 = not set; 0..3 = explicit clang -ON *)
let do_fmt         = ref false   (* --fmt: format source before compiling *)
let target_str     = ref "native"  (* --target: native | wasm64-wasi | wasm32-wasi | wasm32-unknown-unknown *)

(** Parse --target string into Llvm_emit.target_config. *)
let parse_target s =
  match String.lowercase_ascii s with
  | "native" -> March_tir.Llvm_emit.Native
  | "wasm64-wasi" | "wasm64" -> March_tir.Llvm_emit.Wasm64Wasi
  | "wasm32-wasi" | "wasm32" -> March_tir.Llvm_emit.Wasm32Wasi
  | "wasm32-unknown-unknown" | "wasm-browser" | "browser" -> March_tir.Llvm_emit.Wasm32Unknown
  | other ->
    Printf.eprintf "march: unknown target '%s'\n  Valid targets: native, wasm64-wasi, wasm32-wasi, wasm32-unknown-unknown\n" other;
    exit 1

(* ------------------------------------------------------------------ *)
(* Formatter helpers                                                   *)
(* ------------------------------------------------------------------ *)

(** Read a file's contents, returning the string. *)
let read_file path =
  let ic = open_in path in
  let n  = in_channel_length ic in
  let buf = Bytes.create n in
  really_input ic buf 0 n;
  close_in ic;
  Bytes.to_string buf

(** Write [contents] to [path] atomically (via a temp file). *)
let write_file path contents =
  let tmp = path ^ ".fmt.tmp" in
  let oc = open_out tmp in
  output_string oc contents;
  close_out oc;
  Sys.rename tmp path

(* ------------------------------------------------------------------ *)
(* Cross-file import resolver (delegated to march_resolver library)  *)
(* ------------------------------------------------------------------ *)

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

(** Stdlib module names — always resolved from the bundled stdlib, never
    from the user's source tree. *)
let stdlib_module_names =
  [ "List"; "Map"; "Set"; "Array"; "Queue"; "String"; "Option"; "Result"
  ; "Math"; "Enum"; "BigInt"; "Decimal"; "DateTime"; "Duration"; "Bytes"; "Json"
  ; "Regex"; "Csv"; "File"; "Dir"; "Path"; "Http"; "HttpClient"
  ; "HttpServer"; "HttpTransport"; "WebSocket"; "Process"; "Logger"
  ; "Flow"; "Actor"; "Sort"; "Hamt"; "Seq"; "Iterable"; "IOList"
  ; "Random"; "Stats"; "Plot"; "Prelude"; "DataFrame"; "Test"
  ; "Vault"; "URI"
  ; "Depot"; "Depot.Gate" ]

(** Collect [(mod_name, span)] for each DUse/DAlias in [decls]. *)
let import_refs decls =
  List.filter_map (function
    | March_ast.Ast.DUse (ud, sp) ->
      (match ud.March_ast.Ast.use_path with
       | n :: _ -> Some (n.March_ast.Ast.txt, sp)
       | [] -> None)
    | March_ast.Ast.DAlias (ad, sp) ->
      (match ad.March_ast.Ast.alias_path with
       | n :: _ -> Some (n.March_ast.Ast.txt, sp)
       | [] -> None)
    | _ -> None
  ) decls

(** Parse a .march source file.  Returns [Ok module_ast] or [Error msg]. *)
let parse_march_file path src =
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
  try Ok (March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
  with
  | March_errors.Errors.ParseError (msg, _hint, pos) ->
    let open Lexing in
    Error (Printf.sprintf "%s:%d: parse error: %s" path pos.pos_lnum msg)
  | March_parser.Parser.Error ->
    let pos = Lexing.lexeme_start_p lexbuf in
    let open Lexing in
    Error (Printf.sprintf "%s:%d: parse error" path pos.pos_lnum)

(** Resolve cross-file imports and auto-discover project library files.
    Scans [m.mod_decls] for DUse/DAlias that name user modules (not stdlib),
    finds their .march files, parses and desugars them, detects cycles.
    Also auto-discovers all .march files in MARCH_LIB_PATH directories so that
    qualified cross-module calls (e.g. MyApp.Router.dispatch) work without
    explicit [use] declarations — required for multi-file projects.
    Returns (errors, extra_dmods_to_prepend). *)
let resolve_imports ~source_file (m : March_ast.Ast.module_) =
  let source_dir = Filename.dirname source_file in
  let extra_lib_paths =
    match Sys.getenv_opt "MARCH_LIB_PATH" with
    | None -> []
    | Some s -> List.filter (fun d -> d <> "") (String.split_on_char ':' s)
  in
  let search_path = source_dir :: extra_lib_paths in
  let resolved : (string, March_ast.Ast.decl list) Hashtbl.t = Hashtbl.create 8 in
  (* Track loaded file paths so the same file is never parsed twice *)
  let loaded_paths : (string, unit) Hashtbl.t = Hashtbl.create 8 in
  let in_progress : (string, unit) Hashtbl.t = Hashtbl.create 4 in
  let errors : (string * March_ast.Ast.span * string) list ref = ref [] in
  let dummy_span = March_ast.Ast.dummy_span in
  (* Pre-mark the entry file so auto-discovery never re-loads it *)
  Hashtbl.add loaded_paths source_file ();

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
          if Hashtbl.mem loaded_paths file_path then
            (* Already loaded via auto-discovery; return empty to avoid duplication *)
            []
          else begin
            Hashtbl.add loaded_paths file_path ();
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
          end
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

  (* Step 1: resolve explicit imports (DUse/DAlias) from the entry file *)
  let explicit_decls = load_refs m.March_ast.Ast.mod_decls in
  (* Mark all explicitly-loaded modules (and their nested transitive deps) as
     already-emitted.  This prevents them from being re-embedded as transitive
     deps inside auto-discovered DMods in step 2.  Without this, every conduit
     submodule that does `import Conduit` would embed the entire Conduit DMod
     (~80 declarations) inside itself, causing O(N²) typecheck cost. *)
  let rec mark_emitted_decls = function
    | [] -> ()
    | March_ast.Ast.DMod ({March_ast.Ast.txt = mn; _}, _, inner, _) :: rest ->
      Hashtbl.replace resolved mn [];
      mark_emitted_decls inner;
      mark_emitted_decls rest
    | _ :: rest -> mark_emitted_decls rest
  in
  mark_emitted_decls explicit_decls;

  (* Step 2: auto-discover all .march files in MARCH_LIB_PATH directories.
     Load any that were not already pulled in via explicit imports.
     Two-phase: parse all files first to learn their module names, then sort
     by module-name depth (more dot-segments = deeper namespace = fewer
     dependents = load first) so dependencies are in env before their users. *)
  let collect_lib_files dir =
    let rec walk acc d =
      if not (Sys.file_exists d && Sys.is_directory d) then acc
      else
        Array.fold_left (fun acc name ->
            let p = Filename.concat d name in
            if Sys.is_directory p then walk acc p
            else if Filename.check_suffix p ".march" then p :: acc
            else acc)
          acc (Sys.readdir d)
    in
    walk [] dir
  in
  let dot_count s =
    String.fold_left (fun n c -> if c = '.' then n + 1 else n) 0 s
  in
  let auto_decls =
    List.concat_map (fun lib_dir ->
        let files = collect_lib_files lib_dir in
        (* Phase 1: parse + desugar all un-loaded files to learn their mod names *)
        let parsed = List.filter_map (fun file_path ->
            if Hashtbl.mem loaded_paths file_path then None
            else
              let src = try read_file file_path with Sys_error _ -> "" in
              if src = "" then None
              else
                match parse_march_file file_path src with
                | Error msg ->
                  Printf.eprintf "[lib] %s\n%!" msg; None
                | Ok ast ->
                  Some (file_path, March_desugar.Desugar.desugar_module ast)
          ) files in
        (* Sort: more dot-segments in mod name → load first (namespace leaves).
           Alphabetical tiebreak keeps things deterministic. *)
        let sorted = List.sort (fun (_, a) (_, b) ->
            let mn ast = ast.March_ast.Ast.mod_name.March_ast.Ast.txt in
            let da = dot_count (mn a) and db = dot_count (mn b) in
            if db <> da then compare db da
            else compare (mn a) (mn b)
          ) parsed in
        (* Phase 2: build DMods in sorted order *)
        List.filter_map (fun (file_path, ast) ->
            if Hashtbl.mem loaded_paths file_path then None
            else begin
              Hashtbl.add loaded_paths file_path ();
              let transitive = load_refs ast.March_ast.Ast.mod_decls in
              let all_decls = transitive @ ast.March_ast.Ast.mod_decls in
              (* Cache under mod_name so explicit `use` won't reload this file *)
              let mn = ast.March_ast.Ast.mod_name.March_ast.Ast.txt in
              if not (Hashtbl.mem resolved mn) then
                Hashtbl.add resolved mn [];
              Some (March_ast.Ast.DMod (ast.March_ast.Ast.mod_name,
                                        March_ast.Ast.Public,
                                        all_decls,
                                        dummy_span))
            end
          ) sorted
      ) extra_lib_paths
  in

  (!errors, explicit_decls @ auto_decls)

(** Format [filename] in-place.  Returns true if the file was changed. *)
let fmt_file filename =
  let src = read_file filename in
  let formatted =
    try March_format.Format.format_source ~filename src
    with
    | March_errors.Errors.ParseError (msg, hint, _) ->
      Printf.eprintf "%s\n"
        (March_errors.Errors.render_parse_error ~src ~filename ?hint ~msg
           (Lexing.from_string src));
      exit 1
    | March_parser.Parser.Error ->
      let lexbuf = Lexing.from_string src in
      lexbuf.Lexing.lex_curr_p <-
        { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
      Printf.eprintf "%s\n"
        (March_errors.Errors.render_parse_error ~src ~filename
           ~msg:"Parse error (cannot format)" lexbuf);
      exit 1
  in
  formatted <> src, formatted

(** Collect all .march files under a directory recursively. *)
let rec march_files_in dir =
  let entries = Sys.readdir dir in
  Array.fold_left (fun acc entry ->
    let path = Filename.concat dir entry in
    if Sys.is_directory path then
      acc @ march_files_in path
    else if Filename.check_suffix path ".march" then
      acc @ [path]
    else
      acc
  ) [] entries

(** Run the test subcommand and exit.
    Discovers test files, parses/typechecks them, and runs all test blocks.
    Usage: march test [--verbose|-v] [--filter=pattern] [file...] *)
let run_test_cmd args =
  let verbose  = ref false in
  let filter   = ref "" in
  let coverage = ref false in
  let targets  = ref [] in
  List.iter (fun a ->
    if a = "--verbose" || a = "-v" then verbose := true
    else if a = "--coverage" then coverage := true
    else if String.length a > 9 && String.sub a 0 9 = "--filter=" then
      filter := String.sub a 9 (String.length a - 9)
    else
      targets := a :: !targets
  ) args;
  let targets = List.rev !targets in
  (* If no explicit files given, auto-discover test/test_*.march and test/*_test.march *)
  let files =
    if targets <> [] then targets
    else begin
      let test_dir = "test" in
      if not (Sys.file_exists test_dir) then []
      else
        let entries = Array.to_list (Sys.readdir test_dir) in
        List.filter_map (fun name ->
          if (String.length name > 6 && String.sub name 0 5 = "test_"
              && Filename.check_suffix name ".march")
          || Filename.check_suffix name "_test.march"
          then Some (Filename.concat test_dir name)
          else None
        ) entries
    end
  in
  if files = [] then begin
    Printf.eprintf "march test: no test files found\n";
    Printf.eprintf "  Put test files in test/ named test_*.march or *_test.march\n";
    exit 0
  end;
  let total_files = List.length files in
  let total_tests = ref 0 in
  let total_failed = ref 0 in
  let failed_files = ref [] in
  (* In quiet mode (non-verbose), collect failures across files for end-of-run reporting. *)
  let all_file_failures : (string * (string * string) list) list ref = ref [] in
  List.iter (fun filename ->
    let src =
      try read_file filename
      with Sys_error msg ->
        Printf.eprintf "march test: %s\n" msg; exit 1
    in
    if !verbose then Printf.printf "%s\n%!" filename;
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
    let module_ast =
      try March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
      with
      | March_errors.Errors.ParseError (msg, hint, _) ->
        Printf.eprintf "\n%s\n"
          (March_errors.Errors.render_parse_error ~src ~filename ?hint ~msg lexbuf);
        exit 1
      | March_parser.Parser.Error ->
        Printf.eprintf "\n%s\n"
          (March_errors.Errors.render_parse_error ~src ~filename ~msg:"Parse error:" lexbuf);
        exit 1
    in
    let parse_errs = March_parser.Parse_errors.take_parse_errors () in
    if parse_errs <> [] then begin
      List.iter (fun (msg, _hint, pos) ->
        let open Lexing in
        Printf.eprintf "%s:%d:%d: error: %s\n"
          filename pos.pos_lnum (pos.pos_cnum - pos.pos_bol) msg
      ) parse_errs;
      exit 1
    end;
    let desugar_errors = March_errors.Errors.create () in
    let desugared = March_desugar.Desugar.desugar_module ~errors:desugar_errors module_ast in
    if March_errors.Errors.has_errors desugar_errors then begin
      List.iter (fun (d : March_errors.Errors.diagnostic) ->
          Printf.eprintf "%s:%d:%d: error: %s\n"
            d.span.March_ast.Ast.file d.span.March_ast.Ast.start_line
            d.span.March_ast.Ast.start_col d.message
        ) (March_errors.Errors.sorted desugar_errors);
      exit 1
    end;
    let (resolve_errors, extra_decls) = resolve_imports ~source_file:filename desugared in
    if resolve_errors <> [] then begin
      List.iter (fun (_mod_name, span, msg) ->
          Printf.eprintf "%s:%d:%d: error: %s\n"
            span.March_ast.Ast.file span.March_ast.Ast.start_line
            span.March_ast.Ast.start_col msg
        ) resolve_errors;
      exit 1
    end;
    let desugared =
      { desugared with
        March_ast.Ast.mod_decls = extra_decls @ desugared.March_ast.Ast.mod_decls }
    in
    let stdlib_decls = load_stdlib () in
    let desugared =
      { desugared with
        March_ast.Ast.mod_decls = stdlib_decls @ desugared.March_ast.Ast.mod_decls }
    in
    let (errors, _type_map) = March_typecheck.Typecheck.check_module desugared in
    let diags = March_errors.Errors.sorted errors in
    let is_user_file (d : March_errors.Errors.diagnostic) =
      d.span.March_ast.Ast.file = filename
    in
    let has_user_errors = List.exists (fun (d : March_errors.Errors.diagnostic) ->
        d.severity = March_errors.Errors.Error && is_user_file d
      ) diags in
    if has_user_errors then begin
      List.iter (fun (d : March_errors.Errors.diagnostic) ->
        if is_user_file d && d.severity = March_errors.Errors.Error then
          Printf.eprintf "%s\n\n"
            (March_errors.Errors.render_diagnostic ~src ~filename d)
      ) diags;
      exit 1
    end;
    (* Enable coverage tracking for this file's test run. *)
    if !coverage then begin
      March_coverage.Coverage.reset ();
      March_coverage.Coverage.coverage_enabled := true
    end;
    (* Check whether the test source opts into IO capture via @capture_io. *)
    let capture_io =
      let pat = "@capture_io" in
      let n = String.length src and p = String.length pat in
      let rec check i =
        if i + p > n then false
        else if String.sub src i p = pat then true
        else check (i + 1)
      in check 0
    in
    let (n_tests, n_failed, file_failures) =
      if !verbose then
        March_eval.Eval.run_tests ~verbose:true ~filter:!filter ~capture_io desugared
      else
        March_eval.Eval.run_tests ~dot_stream:true ~filter:!filter ~capture_io desugared
    in
    if !coverage then begin
      March_coverage.Coverage.coverage_enabled := false;
      March_coverage.Coverage.report_summary ~target_file:filename desugared ()
    end;
    total_tests  := !total_tests + n_tests;
    total_failed := !total_failed + n_failed;
    if n_failed > 0 then begin
      failed_files := filename :: !failed_files;
      if not !verbose then
        all_file_failures := (filename, file_failures) :: !all_file_failures
    end;
    (* Run doctests extracted from fn_doc fields *)
    let parse_expr src =
      let lexbuf = Lexing.from_string src in
      try March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
      with
      | March_errors.Errors.ParseError (msg, _, _) ->
        failwith ("doctest parse error: " ^ msg)
      | March_parser.Parser.Error ->
        failwith ("doctest parse error in: " ^ src)
    in
    let (dt_total, dt_failed, dt_failures) =
      if !verbose then
        March_eval.Eval.run_doctests ~verbose:true ~filter:!filter ~parse_expr desugared
      else
        March_eval.Eval.run_doctests ~quiet:true ~filter:!filter ~parse_expr desugared
    in
    total_tests  := !total_tests + dt_total;
    total_failed := !total_failed + dt_failed;
    if dt_failed > 0 then begin
      if not (List.mem filename !failed_files) then
        failed_files := filename :: !failed_files;
      if not !verbose then
        all_file_failures := (filename, dt_failures) :: !all_file_failures
    end
  ) files;
  (* End the dot line after all files *)
  if not !verbose then Printf.printf "\n%!";
  (* Print collected failure details grouped by file. *)
  if not !verbose && !all_file_failures <> [] then begin
    List.iter (fun (filename, failures) ->
      Printf.printf "%s\n" filename;
      List.iter (fun (name, msg) ->
        Printf.printf "  FAIL: \"%s\"\n    %s\n\n" name
          (String.concat "\n    " (String.split_on_char '\n' msg))
      ) failures
    ) (List.rev !all_file_failures)
  end;
  let n_failed_files = List.length !failed_files in
  if n_failed_files = 0 then
    Printf.printf "=== %d file%s, %d test%s passed ===\n%!"
      total_files (if total_files = 1 then "" else "s")
      !total_tests (if !total_tests = 1 then "" else "s")
  else
    Printf.printf "=== %d/%d file%s, %d/%d test%s failed ===\n%!"
      n_failed_files total_files (if total_files = 1 then "" else "s")
      !total_failed !total_tests (if !total_tests = 1 then "" else "s");
  if !total_failed > 0 then exit 1
  else exit 0

(** Run the fmt subcommand and exit. *)
let run_fmt args =
  (* Parse flags and collect targets *)
  let check_mode = ref false in
  let stdin_mode = ref false in
  let targets    = ref [] in
  List.iter (fun a ->
    if a = "--check" then check_mode := true
    else if a = "--stdin" then stdin_mode := true
    else targets := a :: !targets
  ) args;
  (* --stdin: read from stdin, format, write to stdout *)
  if !stdin_mode then begin
    let buf = Buffer.create 4096 in
    (try while true do Buffer.add_char buf (input_char stdin) done
     with End_of_file -> ());
    let src = Buffer.contents buf in
    let filename = match !targets with f :: _ -> f | [] -> "<stdin>" in
    let formatted =
      try March_format.Format.format_source ~filename src
      with _ -> src
    in
    print_string formatted;
    exit 0
  end;
  let targets = List.rev !targets in
  let files = List.concat_map (fun target ->
    if target = "." || (Sys.file_exists target && Sys.is_directory target) then
      march_files_in target
    else
      [target]
  ) targets in
  if files = [] then begin
    Printf.eprintf "march fmt: no files specified\n"; exit 1
  end;
  let any_changed = ref false in
  List.iter (fun f ->
    let changed, formatted = fmt_file f in
    if !check_mode then begin
      if changed then begin
        Printf.eprintf "%s: not formatted\n" f;
        any_changed := true
      end
    end else begin
      if changed then begin
        write_file f formatted;
        Printf.printf "formatted %s\n%!" f
      end
    end
  ) files;
  if !check_mode && !any_changed then exit 1
  else exit 0

(* ------------------------------------------------------------------ *)
(* File compiler                                                       *)
(* ------------------------------------------------------------------ *)

let compile filename =
  let src =
    try read_file filename
    with Sys_error msg ->
      Printf.eprintf "march: %s\n" msg;
      exit 1
  in
  (* --fmt: format the source file before compiling *)
  if !do_fmt then begin
    let changed, formatted = fmt_file filename in
    if changed then begin
      write_file filename formatted;
      Printf.eprintf "formatted %s\n%!" filename
    end
  end;
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
  (* Parse *)
  let module_ast =
    try March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
    with
    | March_errors.Errors.ParseError (msg, hint, _) ->
      Printf.eprintf "%s\n"
        (March_errors.Errors.render_parse_error ~src ~filename ?hint ~msg lexbuf);
      exit 1
    | March_parser.Parser.Error ->
      Printf.eprintf "%s\n"
        (March_errors.Errors.render_parse_error ~src ~filename ~msg:"I got stuck here:" lexbuf);
      exit 1
  in
  (* Display any declaration-level parse errors collected during recovery *)
  let parse_errs = March_parser.Parse_errors.take_parse_errors () in
  let has_parse_errors = parse_errs <> [] in
  List.iter (fun (msg, hint, pos) ->
      let open Lexing in
      Printf.eprintf "%s:%d:%d: error: %s\n"
        filename pos.pos_lnum (pos.pos_cnum - pos.pos_bol) msg;
      (match hint with
       | None -> ()
       | Some h -> Printf.eprintf "hint: %s\n" h)
    ) parse_errs;
  (* Desugar *)
  let desugar_errors = March_errors.Errors.create () in
  let desugared = March_desugar.Desugar.desugar_module ~errors:desugar_errors module_ast in
  List.iter (fun (d : March_errors.Errors.diagnostic) ->
      Printf.eprintf "%s:%d:%d: error: %s\n"
        d.span.March_ast.Ast.file d.span.March_ast.Ast.start_line
        d.span.March_ast.Ast.start_col d.message
    ) (March_errors.Errors.sorted desugar_errors);
  let has_desugar_errors = March_errors.Errors.has_errors desugar_errors in
  (* Capture user AST before stdlib injection — used by -dump-phases *)
  let user_ast = desugared in
  (* Resolve cross-file imports: find imported .march files, parse and inject *)
  let (resolve_errors, extra_decls) = resolve_imports ~source_file:filename desugared in
  List.iter (fun (_mod_name, span, msg) ->
      Printf.eprintf "%s:%d:%d: error: %s\n"
        span.March_ast.Ast.file span.March_ast.Ast.start_line
        span.March_ast.Ast.start_col msg
    ) resolve_errors;
  let has_resolve_errors = resolve_errors <> [] in
  let desugared =
    { desugared with
      March_ast.Ast.mod_decls = extra_decls @ desugared.March_ast.Ast.mod_decls }
  in
  (* Inject stdlib declarations before user declarations.
     If MARCH_LIB_PATH provided a module that also ships in the stdlib, defer
     to the external version: strip the stdlib copy so the external one is
     the sole definition. *)
  let stdlib_decls = load_stdlib () in
  let extern_mod_names =
    List.filter_map (function
      | March_ast.Ast.DMod (nm, _vis, _decls, _sp) ->
        Some nm.March_ast.Ast.txt
      | _ -> None
    ) extra_decls
  in
  let stdlib_decls =
    if extern_mod_names = [] then stdlib_decls
    else List.filter (function
      | March_ast.Ast.DMod (nm, _vis, _decls, _sp) ->
        not (List.mem nm.March_ast.Ast.txt extern_mod_names)
      | _ -> true
    ) stdlib_decls
  in
  let desugared =
    { desugared with
      March_ast.Ast.mod_decls = stdlib_decls @ desugared.March_ast.Ast.mod_decls }
  in
  (* Typecheck + capability enforcement (applies to both eval and compile paths).
     Capability enforcement is embedded in check_module via check_module_needs:
       - transitive needs propagation across module imports
       - extern block capability gating
     See also: March_effects.Effects.check_capabilities *)
  let (errors, type_map) = March_typecheck.Typecheck.check_module desugared in
  (* Print diagnostics sorted by position, filtering stdlib-internal errors *)
  let diags = March_errors.Errors.sorted errors in
  let is_user_file (d : March_errors.Errors.diagnostic) =
    d.span.March_ast.Ast.file = filename ||
    d.span.March_ast.Ast.file = "" ||
    d.span.March_ast.Ast.file = "<unknown>"
  in
  List.iter (fun (d : March_errors.Errors.diagnostic) ->
      if is_user_file d then
        Printf.eprintf "%s\n\n"
          (March_errors.Errors.render_diagnostic ~src ~filename d)
    ) diags;
  let compile_mode = !dump_tir || !emit_llvm || !do_compile || !dump_phases in
  let has_user_errors = List.exists (fun (d : March_errors.Errors.diagnostic) ->
      d.severity = March_errors.Errors.Error && is_user_file d
    ) diags in
  (* In compile mode, abort on user-file errors only.  Stdlib errors
     (e.g. http_client) are tolerated since those modules are WIP. *)
  if has_user_errors || has_parse_errors || has_resolve_errors || has_desugar_errors then exit 1
  else if compile_mode then begin
    (* -dump-phases: collect per-stage JSON graphs *)
    let phases = ref [] in
    let snap_tir label tir =
      if !dump_phases then
        phases := March_dump.Dump.tir_phase tir label :: !phases
    in
    (* Phase 1: AST after parse+desugar — user file only (no stdlib). *)
    (if !dump_phases then
       phases := March_dump.Dump.ast_phase user_ast "parse" :: !phases);
    let tir = March_tir.Lower.lower_module ~type_map ~test_mode:!do_test desugared in
    snap_tir "tir-lower" tir;
    (* Capture the interface-dispatch table before it is cleared by lower_module.
       Passed to monomorphize so it can resolve interface calls in functions
       that were polymorphic during lowering but now have concrete types. *)
    let iface_methods = March_tir.Lower.get_iface_methods () in
    (* For WASM island targets, mark render/update/init as exported.
       Set exports BEFORE monomorphization so the functions get mono'd. *)
    let tir = match parse_target !target_str with
      | March_tir.Llvm_emit.Wasm32Unknown ->
        let island_suffixes = ["render"; "update"; "init"] in
        let exports = List.filter_map (fun (fn : March_tir.Tir.fn_def) ->
          let n = fn.March_tir.Tir.fn_name in
          if List.exists (fun suffix ->
            n = suffix ||
            (String.length n > String.length suffix + 1 &&
             String.sub n (String.length n - String.length suffix - 1)
               (String.length suffix + 1) = ("." ^ suffix))
          ) island_suffixes
          then Some n else None
        ) tir.March_tir.Tir.tm_fns in
        { tir with March_tir.Tir.tm_exports = exports }
      | _ -> tir
    in
    let tir = March_tir.Mono.monomorphize ~iface_methods tir in
    snap_tir "tir-mono" tir;
    (* After mono, update tm_exports to use monomorphized names *)
    let tir =
      if tir.March_tir.Tir.tm_exports <> [] then begin
        let island_suffixes = ["render"; "update"; "init"] in
        let matches_suffix name suffix =
          let base = match String.index_opt name '$' with
            | Some i -> String.sub name 0 i
            | None -> name
          in
          base = suffix ||
          (String.length base > String.length suffix + 1 &&
           String.sub base (String.length base - String.length suffix - 1)
             (String.length suffix + 1) = ("." ^ suffix))
        in
        let exports = List.filter_map (fun (fn : March_tir.Tir.fn_def) ->
          let n = fn.March_tir.Tir.fn_name in
          if List.exists (matches_suffix n) island_suffixes
          then Some n else None
        ) tir.March_tir.Tir.tm_fns in
        { tir with March_tir.Tir.tm_exports = exports }
      end else tir
    in
    let tir = if !opt_enabled then March_tir.Fusion.run ~changed:(ref false) tir else tir in
    snap_tir "tir-fusion" tir;
    let tir = March_tir.Defun.defunctionalize tir in
    snap_tir "tir-defun" tir;
    (* Known-call pass: run before Perceus so apply functions are still pure
       and eligible for inlining in the subsequent Opt fixed-point loop.
       Also included in the Opt coordinator for cases revealed after Perceus. *)
    let tir = if !opt_enabled
              then March_tir.Known_call.run ~changed:(ref false) tir
              else tir in
    snap_tir "tir-known-call" tir;
    let tir = March_tir.Perceus.perceus tir in
    snap_tir "tir-perceus" tir;
    let tir = March_tir.Escape.escape_analysis tir in
    snap_tir "tir-escape" tir;
    (* Run optimizer with per-pass snapshots (Phase 3 instrumentation).
       When dump_phases is on, each individual opt pass is captured separately
       (tir-opt-1-inline, tir-opt-1-cprop, …) so the viewer shows every step.
       When opt is disabled, fall through to a single tir-opt snapshot. *)
    let tir =
      if !opt_enabled then
        March_tir.Opt.run
          ~snap:(fun label m ->
            if !dump_phases then
              phases := March_dump.Dump.tir_phase m label :: !phases)
          tir
      else tir
    in
    (* When opt is disabled there are no per-pass snaps; still emit one overall. *)
    if not !opt_enabled then snap_tir "tir-opt" tir;
    (* Write all collected phases to march-phases/phases.json *)
    (if !dump_phases then
       March_dump.Dump.write_phases ~source_file:filename (List.rev !phases));
    if !dump_tir then begin
      List.iter (fun td ->
          Printf.printf "%s\n\n" (March_tir.Pp.string_of_type_def td)
        ) tir.tm_types;
      List.iter (fun fn ->
          Printf.printf "%s\n\n" (March_tir.Pp.string_of_fn_def fn)
        ) tir.tm_fns
    end else begin
      let target = parse_target !target_str in
      let basename = Filename.remove_extension filename in
      let ll_file  = basename ^ ".ll" in
      if !do_compile then begin
        let is_wasm = March_tir.Llvm_emit.is_wasm_target target in
        let out_bin =
          if !output_file <> "" then !output_file
          else if is_wasm then basename ^ ".wasm"
          else basename
        in
        (* CAS: check for a cached binary before running clang *)
        let target_label = match target with
          | March_tir.Llvm_emit.Native -> "native"
          | March_tir.Llvm_emit.Wasm64Wasi -> "wasm64-wasi"
          | March_tir.Llvm_emit.Wasm32Wasi -> "wasm32-wasi"
          | March_tir.Llvm_emit.Wasm32Unknown -> "wasm32-unknown-unknown"
        in
        let store = March_cas.Cas.create ~project_root:(Sys.getcwd ()) in
        let h_sccs = March_cas.Pipeline.hash_module tir in
        let mod_hash = String.concat "" (List.map March_cas.Pipeline.scc_impl_hash h_sccs) in
        let effective_opt = if !opt_level >= 0 && !opt_level <= 3 then !opt_level else 2 in
        let cas_flags = [if !opt_enabled then Printf.sprintf "O%d" effective_opt else "no-opt"] in
        let ch = March_cas.Cas.compilation_hash mod_hash ~target:target_label ~flags:cas_flags in
        (match March_cas.Cas.lookup_artifact store ch with
        | Some cached_bin ->
          let _ = Sys.command (Printf.sprintf "cp %s %s" cached_bin out_bin) in
          Printf.eprintf "compiled %s (cached)\n" out_bin
        | None ->
          (* Cache miss: emit LLVM IR, call clang, then cache the binary *)
          let ir = March_tir.Llvm_emit.emit_module ~fast_math:!fast_math ~target tir in
          let oc = open_out ll_file in
          output_string oc ir;
          close_out oc;
          if is_wasm then begin
            (* ── WASM compilation path ──────────────────────────────────── *)
            let wasm_runtime_candidates = [
              "runtime/march_runtime_wasm.c";
              Filename.concat (Filename.dirname Sys.executable_name) "../runtime/march_runtime_wasm.c";
              Filename.concat (Filename.dirname Sys.executable_name) "../../runtime/march_runtime_wasm.c";
            ] in
            let wasm_runtime = match List.find_opt Sys.file_exists wasm_runtime_candidates with
              | Some p -> p
              | None ->
                (* Fall back to main runtime with -DMARCH_WASM *)
                let candidates = [
                  "runtime/march_runtime.c";
                  Filename.concat (Filename.dirname Sys.executable_name) "../runtime/march_runtime.c";
                  Filename.concat (Filename.dirname Sys.executable_name) "../../runtime/march_runtime.c";
                ] in
                (match List.find_opt Sys.file_exists candidates with
                 | Some p -> p
                 | None ->
                   Printf.eprintf "march: cannot find runtime for WASM target\n"; exit 1)
            in
            let triple = March_tir.Llvm_emit.target_triple target in
            let opt_flag = Printf.sprintf " -O%d" effective_opt in
            (* Locate wasi-sdk for WASI targets, or use system clang for wasm32-unknown-unknown *)
            let clang, sysroot_flag = match target with
              | March_tir.Llvm_emit.Wasm64Wasi | March_tir.Llvm_emit.Wasm32Wasi ->
                let wasi_sdk = match Sys.getenv_opt "WASI_SDK_PATH" with
                  | Some p -> p
                  | None ->
                    if Sys.file_exists "/opt/wasi-sdk" then "/opt/wasi-sdk"
                    else begin
                      Printf.eprintf "march: wasi-sdk not found. Set WASI_SDK_PATH or install to /opt/wasi-sdk\n";
                      exit 1
                    end
                in
                (Filename.concat wasi_sdk "bin/clang",
                 Printf.sprintf " --sysroot=%s/share/wasi-sysroot" wasi_sdk)
              | _ ->
                (* wasm32-unknown-unknown: need a clang with WASM backend.
                   Apple clang doesn't include it, so try wasi-sdk or homebrew LLVM. *)
                let wasm_clang =
                  let wasi_candidates = [
                    (match Sys.getenv_opt "WASI_SDK_PATH" with Some p -> Some (Filename.concat p "bin/clang") | None -> None);
                    (if Sys.file_exists "/opt/wasi-sdk/bin/clang" then Some "/opt/wasi-sdk/bin/clang" else None);
                    (if Sys.file_exists "/opt/homebrew/opt/llvm/bin/clang" then Some "/opt/homebrew/opt/llvm/bin/clang" else None);
                    (if Sys.file_exists "/usr/local/opt/llvm/bin/clang" then Some "/usr/local/opt/llvm/bin/clang" else None);
                  ] in
                  match List.find_map Fun.id wasi_candidates with
                  | Some p -> p
                  | None ->
                    Printf.eprintf "march: No clang with WASM backend found.\n";
                    Printf.eprintf "  Install wasi-sdk (brew install wasi-sdk) or LLVM (brew install llvm)\n";
                    exit 1
                in
                (wasm_clang, " -nostdlib -Wl,--no-entry -Wl,--export-dynamic")
            in
            let cmd = Printf.sprintf
              "%s --target=%s%s%s -DMARCH_WASM -Wno-unused-command-line-argument %s %s -o %s"
              clang triple sysroot_flag opt_flag wasm_runtime ll_file out_bin in
            let rc = Sys.command cmd in
            if rc <> 0 then begin
              Printf.eprintf "march: WASM compilation failed (exit %d)\n  cmd: %s\n" rc cmd; exit 1
            end else begin
              March_cas.Cas.store_artifact store ch out_bin;
              Printf.eprintf "compiled %s (%s)\n" out_bin target_label
            end
          end else begin
            (* ── Native compilation path ────────────────────────────────── *)
            let candidates = [
              "runtime/march_runtime.c";
              Filename.concat (Filename.dirname Sys.executable_name) "../runtime/march_runtime.c";
              Filename.concat (Filename.dirname Sys.executable_name) "../../runtime/march_runtime.c";
            ] in
            let runtime = match List.find_opt Sys.file_exists candidates with
              | Some p -> p
              | None ->
                Printf.eprintf "march: cannot find runtime/march_runtime.c\n"; exit 1
            in
            let opt_flag = Printf.sprintf " -O%d" effective_opt in
            let runtime_dir = Filename.dirname runtime in
            let http_c = Filename.concat runtime_dir "march_http.c" in
            let extras_c2 = Filename.concat runtime_dir "march_extras.c" in
            let opt_file2 f = if Sys.file_exists f then Printf.sprintf " %s" f else "" in
            let extra_c_files =
              if Sys.file_exists http_c then
                let sha1_c    = Filename.concat runtime_dir "sha1.c" in
                let base64_c  = Filename.concat runtime_dir "base64.c" in
                let simd_c    = Filename.concat runtime_dir "march_http_parse_simd.c" in
                let sched_c   = Filename.concat runtime_dir "march_scheduler.c" in
                let resp_c    = Filename.concat runtime_dir "march_http_response.c" in
                let io_c      = Filename.concat runtime_dir "march_http_io.c" in
                let evloop_c  = Filename.concat runtime_dir "march_http_evloop.c" in
                let tls_c2    = Filename.concat runtime_dir "march_tls.c" in
                Printf.sprintf " %s %s %s%s%s%s%s%s%s%s" http_c sha1_c base64_c
                  (opt_file2 simd_c) (opt_file2 sched_c) (opt_file2 resp_c)
                  (opt_file2 io_c) (opt_file2 evloop_c)
                  (opt_file2 tls_c2) (opt_file2 extras_c2)
              else (opt_file2 extras_c2)
            in
            (* OpenSSL flags for TLS *)
            let tls_c2 = Filename.concat runtime_dir "march_tls.c" in
            let openssl_flags2 =
              if not (Sys.file_exists tls_c2) then ""
              else
                let dirs = [
                  "/opt/homebrew/opt/openssl@3";
                  "/opt/homebrew/opt/openssl";
                  "/usr/local/opt/openssl@3";
                  "/usr/local/opt/openssl";
                ] in
                let found = List.fold_left (fun acc d ->
                  match acc with
                  | Some _ -> acc
                  | None ->
                    let hdr = Filename.concat d "include/openssl/ssl.h" in
                    if Sys.file_exists hdr then Some d else None
                ) None dirs in
                match found with
                | Some d ->
                  Printf.sprintf " -I%s/include -L%s/lib -lssl -lcrypto" d d
                | None ->
                  if Sys.command "pkg-config --exists openssl 2>/dev/null" = 0
                  then " -lssl -lcrypto" else ""
            in
            let evloop_flag =
              let evloop_c = Filename.concat runtime_dir "march_http_evloop.c" in
              if Sys.file_exists evloop_c then " -DMARCH_HTTP_USE_EVLOOP" else ""
            in
            let math_flag = if Sys.unix then " -lm" else "" in
            let cmd = Printf.sprintf
              "clang%s -msse4.2 -Wno-unused-command-line-argument%s %s%s%s %s -o %s%s"
              opt_flag evloop_flag runtime extra_c_files openssl_flags2 ll_file out_bin math_flag in
            let rc = Sys.command cmd in
            if rc <> 0 then begin
              Printf.eprintf "march: clang failed (exit %d)\n" rc; exit 1
            end else begin
              March_cas.Cas.store_artifact store ch out_bin;
              Printf.eprintf "compiled %s\n" out_bin
            end
          end)
      end else begin
        (* --emit-llvm only: write IR and exit *)
        let ir = March_tir.Llvm_emit.emit_module ~fast_math:!fast_math ~target tir in
        let oc = open_out ll_file in
        output_string oc ir;
        close_out oc;
        Printf.eprintf "wrote %s\n" ll_file
      end
    end
  end
  else begin
    (* Set up the on-demand module loader so qualified access like Map.get()
       can trigger loading a stdlib module even if it wasn't explicitly imported.
       This is mostly a fallback — load_stdlib() already loads common modules,
       but this covers modules not in the hardcoded list or REPL scenarios. *)
    March_eval.Eval.module_loader := Some (fun mod_name ->
      match March_modules.Module_registry.find_stdlib_file mod_name with
      | None -> ()
      | Some path ->
        let decls = load_stdlib_file path in
        March_eval.Eval.eval_stdlib_decls decls
    );
    (if !debug_mode || !debug_tui_mode then begin
      let ctx = March_debug.Debug.make_debug_ctx
        ~on_dbg:(fun env ->
          March_debug.Debug_repl.run_session
            (Option.get !March_eval.Eval.debug_ctx) env)
      in
      March_debug.Debug.install ctx;
      Printf.eprintf "[debug] Trace recording enabled (buffer: %d frames)\n%!"
        ctx.March_eval.Eval.dc_trace.March_eval.Eval.rb_cap
    end);
    (try March_eval.Eval.run_module desugared
     with
     | March_eval.Eval.Eval_error msg ->
       Printf.eprintf "%s: runtime error: %s\n" filename msg; exit 1
     | March_eval.Eval.Match_failure msg ->
       Printf.eprintf "%s: match failure: %s\n" filename msg; exit 1
     | Unix.Unix_error (Unix.EINTR, syscall, _) ->
       (* SIGINT interrupted a blocking syscall (accept/select/recv) —
          print nothing if shutdown was requested, otherwise show the call *)
       if not !March_eval.Eval.shutdown_requested then
         Printf.eprintf "%s: interrupted syscall: %s\n" filename syscall;
       exit 0);
    March_debug.Debug.uninstall ()
  end

(** Type-check multiple .march files together.
    Parses each file, collects all their declarations, and type-checks the
    combined module.  Exits 0 on success, 1 if any errors are found.
    Used by [forge build] for library projects. *)
let run_check_cmd files =
  if files = [] then begin
    Printf.eprintf "march check: no files specified\n"; exit 1
  end;
  let stdlib_decls = load_stdlib () in
  (* Parse and desugar each file; collect all declarations *)
  let all_decls = List.concat_map (fun filename ->
    let src =
      try read_file filename
      with Sys_error msg ->
        Printf.eprintf "march: %s\n" msg; exit 1
    in
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
    let module_ast =
      try March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
      with
      | March_errors.Errors.ParseError (msg, hint, _) ->
        Printf.eprintf "%s\n"
          (March_errors.Errors.render_parse_error ~src ~filename ?hint ~msg lexbuf);
        exit 1
      | March_parser.Parser.Error ->
        Printf.eprintf "%s\n"
          (March_errors.Errors.render_parse_error ~src ~filename
             ~msg:"I got stuck here:" lexbuf);
        exit 1
    in
    let desugared = March_desugar.Desugar.desugar_module module_ast in
    let (_resolve_errors, extra_decls) = resolve_imports ~source_file:filename desugared in
    let desugared =
      { desugared with
        March_ast.Ast.mod_decls = extra_decls @ desugared.March_ast.Ast.mod_decls }
    in
    (* Wrap each user file in a DMod so its names are accessible as Module.name,
       mirroring what load_stdlib_file does for stdlib modules. *)
    [March_ast.Ast.DMod (desugared.March_ast.Ast.mod_name,
                         March_ast.Ast.Public,
                         desugared.March_ast.Ast.mod_decls,
                         March_ast.Ast.dummy_span)]
  ) files in
  (* Build a synthetic combined module and type-check it *)
  let dummy_span = March_ast.Ast.{
    file = ""; start_line = 0; start_col = 0; end_line = 0; end_col = 0
  } in
  let combined = {
    March_ast.Ast.mod_name = { March_ast.Ast.txt = "LibCheck"; span = dummy_span };
    March_ast.Ast.mod_decls = stdlib_decls @ all_decls;
  } in
  let (errors, _type_map) = March_typecheck.Typecheck.check_module combined in
  let diags = March_errors.Errors.sorted errors in
  let lib_files = List.sort_uniq String.compare files in
  let is_user_file (d : March_errors.Errors.diagnostic) =
    List.mem d.span.March_ast.Ast.file lib_files ||
    d.span.March_ast.Ast.file = "" ||
    d.span.March_ast.Ast.file = "<unknown>"
  in
  let user_errors = List.filter (fun d ->
    is_user_file d &&
    d.March_errors.Errors.severity = March_errors.Errors.Error
  ) diags in
  List.iter (fun (d : March_errors.Errors.diagnostic) ->
    Printf.eprintf "%s:%d:%d: error: %s\n"
      d.span.March_ast.Ast.file
      d.span.March_ast.Ast.start_line
      d.span.March_ast.Ast.start_col
      d.message
  ) user_errors;
  if user_errors <> [] then exit 1
  else exit 0

(* ── Phase 10: GC trace analyser ────────────────────────────────────── *)
(*
 * Reads a gc.jsonl file produced by MARCH_TRACE_GC=1 and reports:
 *   - leaked objects   (alloc'd but never freed at program end)
 *   - double frees     (free event for an already-freed address)
 *   - negative RCs     (dec_ref whose post-decrement RC < 0)
 *)
let analyze_gc_trace path =
  let ic = try open_in path
           with Sys_error _ ->
             Printf.eprintf "march analyze-trace: cannot open '%s'\n" path;
             exit 1
  in
  (* Minimal JSON field scanner — pure OCaml, no external deps.
     Handles "key":"string_val" and "key":number_val forms. *)
  let str_find haystack needle from =
    let hl = String.length haystack and nl = String.length needle in
    let r = ref (-1) and i = ref from in
    while !i <= hl - nl && !r < 0 do
      if String.sub haystack !i nl = needle then r := !i else incr i
    done; !r
  in
  let get_field json key =
    let ps = "\"" ^ key ^ "\":\"" in
    let pn = "\"" ^ key ^ "\":" in
    let i  = str_find json ps 0 in
    if i >= 0 then
      let s = i + String.length ps in
      (match String.index_from_opt json s '"' with
       | Some e -> Some (String.sub json s (e - s))
       | None   -> None)
    else
      let j = str_find json pn 0 in
      if j >= 0 then
        let s = j + String.length pn in
        let e = ref s in
        while !e < String.length json &&
              (let c = json.[!e] in (c >= '0' && c <= '9') || c = '-') do
          incr e
        done;
        if !e > s then Some (String.sub json s (!e - s)) else None
      else None
  in
  let live  : (string, int * int) Hashtbl.t = Hashtbl.create 4096 in
  let freed : (string, bool)      Hashtbl.t = Hashtbl.create 1024 in
  let n_alloc = ref 0 and n_free = ref 0 and n_inc = ref 0 and n_dec = ref 0 in
  let n_double = ref 0 and n_neg = ref 0 and lno = ref 0 in
  (try while true do
    let line = String.trim (input_line ic) in
    incr lno;
    if line <> "" then begin
      let ev   = Option.value ~default:"" (get_field line "event") in
      let addr = Option.value ~default:"" (get_field line "addr")  in
      let rc   = Option.fold  ~none:0 ~some:int_of_string (get_field line "rc") in
      match ev with
      | "alloc" ->
        incr n_alloc;
        Hashtbl.replace live addr (rc, !lno);
        Hashtbl.remove freed addr
      | "free" ->
        incr n_free;
        if Hashtbl.mem freed addr then incr n_double
        else begin Hashtbl.remove live addr; Hashtbl.replace freed addr true end
      | "inc_ref" ->
        incr n_inc;
        (match Hashtbl.find_opt live addr with
         | Some (_, eno) -> Hashtbl.replace live addr (rc, eno)
         | None -> ())
      | "dec_ref" ->
        incr n_dec;
        (match Hashtbl.find_opt live addr with
         | Some (_, eno) ->
           if rc < 0 then incr n_neg;
           Hashtbl.replace live addr (rc, eno)
         | None -> ())
      | _ -> ()
    end
  done with End_of_file -> ());
  close_in ic;
  let n_leaked = Hashtbl.length live in
  Printf.printf "March GC Trace Analysis: %s\n" path;
  Printf.printf "  events        : alloc=%d  free=%d  inc_ref=%d  dec_ref=%d\n"
    !n_alloc !n_free !n_inc !n_dec;
  Printf.printf "  leaked objects: %d\n" n_leaked;
  Printf.printf "  double frees  : %d\n" !n_double;
  Printf.printf "  negative RCs  : %d\n" !n_neg;
  let ok = n_leaked = 0 && !n_double = 0 && !n_neg = 0 in
  if ok then print_string "  result: OK\n"
  else begin
    if n_leaked > 0 then begin
      Printf.eprintf "error: %d leaked object(s)\n" n_leaked;
      let shown = ref 0 in
      Hashtbl.iter (fun addr (rc, eno) ->
        if !shown < 10 then begin
          Printf.eprintf "  leak: addr=%-18s rc=%-3d (alloc at event #%d)\n" addr rc eno;
          incr shown
        end
      ) live;
      if n_leaked > 10 then
        Printf.eprintf "  … and %d more\n" (n_leaked - 10)
    end;
    if !n_double > 0 then
      Printf.eprintf "error: %d double-free(s)\n" !n_double;
    if !n_neg   > 0 then
      Printf.eprintf "error: %d negative reference count(s)\n" !n_neg
  end;
  exit (if ok then 0 else 1)

let () =
  (* Handle subcommands before Arg.parse *)
  let argv = Sys.argv in
  if Array.length argv >= 2 && argv.(1) = "fmt" then begin
    let rest = Array.to_list (Array.sub argv 2 (Array.length argv - 2)) in
    run_fmt rest
  end;
  if Array.length argv >= 2 && argv.(1) = "check" then begin
    let rest = Array.to_list (Array.sub argv 2 (Array.length argv - 2)) in
    run_check_cmd rest
  end;
  if Array.length argv >= 2 && argv.(1) = "test" then begin
    let rest = Array.to_list (Array.sub argv 2 (Array.length argv - 2)) in
    run_test_cmd rest
  end;
  (* Phase 10: GC trace validator — see analyze_gc_trace below. *)
  if Array.length argv >= 2 && argv.(1) = "analyze-trace" then begin
    let path = if Array.length argv >= 3 then argv.(2) else "trace/gc/gc.jsonl" in
    analyze_gc_trace path
  end;
  if Array.length argv >= 2 && argv.(1) = "warm-cache" then begin
    let t0 = Unix.gettimeofday () in
    (* 1. Parse + desugar stdlib (populates AST cache) *)
    let stdlib_decls = load_stdlib () in
    let t1 = Unix.gettimeofday () in
    Printf.printf "stdlib AST:      %.3fs\n%!" (t1 -. t0);
    (* 2. Typecheck stdlib (populates TC env cache) *)
    let type_map = Hashtbl.create 64 in
    let base_tc = March_typecheck.Typecheck.base_env
      (March_errors.Errors.create ()) type_map in
    let tc_pre = March_repl.Repl.preregister_stdlib_types base_tc stdlib_decls in
    let content_hash = March_repl.Repl.stdlib_content_hash stdlib_decls in
    (match March_repl.Repl.load_cached_tc_env ~content_hash ~type_map with
     | Some _ ->
       let t2 = Unix.gettimeofday () in
       Printf.printf "tc_env:          %.3fs (cached)\n%!" (t2 -. t1)
     | None ->
       let (_e0, tc0) = March_repl.Repl.load_decls_into_env
         March_eval.Eval.base_env tc_pre stdlib_decls in
       March_repl.Repl.save_cached_tc_env ~content_hash tc0;
       let t2 = Unix.gettimeofday () in
       Printf.printf "tc_env:          %.3fs (built + cached)\n%!" (t2 -. t1));
    (* 3. Compile C runtime .so *)
    let t3 = Unix.gettimeofday () in
    let runtime_so = ensure_runtime_so () in
    let t4 = Unix.gettimeofday () in
    Printf.printf "runtime .so:     %.3fs\n%!" (t4 -. t3);
    (* 4. Precompile stdlib .so *)
    let jit_ctx = March_jit.Repl_jit.create ~runtime_so () in
    March_repl.Repl.maybe_precompile_stdlib (Some jit_ctx) ~stdlib_decls ~type_map;
    March_jit.Repl_jit.cleanup jit_ctx;
    let t5 = Unix.gettimeofday () in
    Printf.printf "stdlib .so:      %.3fs\n%!" (t5 -. t4);
    Printf.printf "total:           %.3fs\n%!" (t5 -. t0);
    exit 0
  end;
  if Array.length argv >= 2 && argv.(1) = "repl" then begin
    let preload_file = if Array.length argv >= 3 then Some argv.(2) else None in
    let runtime_so = ensure_runtime_so () in
    let jit_ctx = March_jit.Repl_jit.create ~runtime_so () in
    Fun.protect
      ~finally:(fun () -> March_jit.Repl_jit.cleanup jit_ctx)
      (fun () ->
        March_repl.Repl.run ~stdlib_decls:(load_stdlib ())
          ~jit_ctx:(Some jit_ctx) ~preload_file ());
    exit 0
  end;
  let files = ref [] in
  let specs = [
    ("--dump-tir",     Arg.Set dump_tir,     " Print TIR instead of evaluating");
    ("--dump-phases",  Arg.Set dump_phases,  " Serialize each IR stage to march-phases/phases.json");
    ("--emit-llvm",  Arg.Set emit_llvm,   " Emit LLVM IR to <file>.ll");
    ("--compile",    Arg.Set do_compile,  " Compile to native binary via clang");
    ("--test",       Arg.Set do_test,     " Compile test blocks into a standalone test-runner binary (use with --compile)");
    ("--target",     Arg.Set_string target_str,  "<target>  Compilation target: native, wasm64-wasi, wasm32-wasi, wasm32-unknown-unknown");
    ("-o",           Arg.Set_string output_file, "<file>  Output binary name (with --compile)");
    ("--no-opt",    Arg.Clear opt_enabled,  " Skip TIR optimization passes");
    ("--fast-math",  Arg.Set fast_math,  " Emit 'fast' on all FP LLVM instructions");
    ("--opt",        Arg.Set_int opt_level, "<N>  Optimization level passed to clang (0-3)");
    ("--debug",     Arg.Set debug_mode,     " Enable time-travel debugger (simple mode)");
    ("--debug-tui", Arg.Set debug_tui_mode, " Enable time-travel debugger (TUI mode)");
    ("--fmt",       Arg.Set do_fmt,         " Format source file in-place before compiling");
  ] in
  Arg.parse specs (fun f -> files := f :: !files) "Usage: march [options] [file.march]";
  match !files with
  | []  ->
    let runtime_so = ensure_runtime_so () in
    let jit_ctx = March_jit.Repl_jit.create ~runtime_so () in
    Fun.protect
      ~finally:(fun () -> March_jit.Repl_jit.cleanup jit_ctx)
      (fun () ->
        March_repl.Repl.run ~stdlib_decls:(load_stdlib ()) ~jit_ctx:(Some jit_ctx) ())
  | [f] -> compile f
  | _   -> Printf.eprintf "Usage: march [options] [file.march]\n"; exit 1
