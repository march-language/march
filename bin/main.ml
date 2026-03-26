(** March compiler entry point. *)

(* ------------------------------------------------------------------ *)
(* Stdlib loader                                                       *)
(* ------------------------------------------------------------------ *)

(** Locate the stdlib directory.  Try paths relative to the source root
    (for development) and relative to the installed executable. *)
let find_stdlib_dir () =
  (* Allow override via environment variable *)
  let env_override =
    match Sys.getenv_opt "MARCH_STDLIB" with
    | Some p when Sys.file_exists p -> Some p
    | _ -> None
  in
  match env_override with
  | Some p -> Some p
  | None ->
    let exe_dir = Filename.dirname Sys.executable_name in
    let candidates = [
      "stdlib";
      (* Installed share layout: bin/../share/march/stdlib *)
      Filename.concat exe_dir "../share/march/stdlib";
      (* Source-tree layouts for development *)
      Filename.concat exe_dir "../stdlib";
      Filename.concat exe_dir "../../stdlib";
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

(** Load all stdlib modules and return their declarations, to be
    prepended to the user module before evaluation. *)
let load_stdlib () =
  match find_stdlib_dir () with
  | None -> []
  | Some stdlib_dir ->
    (* Load order: prelude first so its globals (reverse, panic, etc.) are
       available to subsequent modules, then the module libraries. *)
    let files = [
      "prelude.march";
      "option.march";
      "result.march";
      "list.march";
      "hamt.march";
      "map.march";
      "math.march";
      "string.march";
      "iolist.march";
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
      "bytes.march";
      "process.march";
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
      "channel.march";
      "pubsub.march";
      "channel_server.march";
      "channel_socket.march";
      "presence.march";
    ] in
    List.concat_map (fun name ->
        load_stdlib_file (Filename.concat stdlib_dir name)
      ) files

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
    let extra_files =
      if Sys.file_exists http_c then
        let sha1_c    = Filename.concat runtime_dir "sha1.c" in
        let base64_c  = Filename.concat runtime_dir "base64.c" in
        let simd_c    = Filename.concat runtime_dir "march_http_parse_simd.c" in
        let sched_c   = Filename.concat runtime_dir "march_scheduler.c" in
        let resp_c    = Filename.concat runtime_dir "march_http_response.c" in
        let io_c      = Filename.concat runtime_dir "march_http_io.c" in
        let evloop_c  = Filename.concat runtime_dir "march_http_evloop.c" in
        let opt_file f = if Sys.file_exists f then Printf.sprintf " %s" f else "" in
        Printf.sprintf " %s %s %s%s%s%s%s%s" http_c sha1_c base64_c
          (opt_file simd_c) (opt_file sched_c) (opt_file resp_c)
          (opt_file io_c) (opt_file evloop_c)
      else ""
    in
    let evloop_flag =
      let evloop_c = Filename.concat runtime_dir "march_http_evloop.c" in
      if Sys.file_exists evloop_c then " -DMARCH_HTTP_USE_EVLOOP" else ""
    in
    let cmd = Printf.sprintf
      "clang -shared -O2 -fPIC -msse4.2 -Wno-unused-command-line-argument%s -I%s %s%s -o %s 2>&1"
      evloop_flag runtime_dir runtime_c extra_files so_path in
    let rc = Sys.command cmd in
    if rc <> 0 then
      failwith (Printf.sprintf "march: failed to compile runtime .so (clang exit %d)" rc)
  end;
  so_path

let dump_tir       = ref false
let emit_llvm      = ref false
let do_compile     = ref false
let output_file    = ref ""
let debug_mode     = ref false
let debug_tui_mode = ref false
let opt_enabled    = ref true
let fast_math      = ref false
let opt_level      = ref (-1)   (* -1 = not set; 0..3 = explicit clang -ON *)
let do_fmt         = ref false   (* --fmt: format source before compiling *)

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

(** Convert a CamelCase module name to a snake_case file name.
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

(** Resolve cross-file imports.
    Scans [m.mod_decls] for DUse/DAlias that name user modules (not stdlib),
    finds their .march files, parses and desugars them, detects cycles.
    Returns (errors, extra_dmods_to_prepend). *)
let resolve_imports ~source_file (m : March_ast.Ast.module_) =
  let source_dir = Filename.dirname source_file in
  let search_path = [source_dir] in
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
    let desugared = March_desugar.Desugar.desugar_module module_ast in
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
          Printf.eprintf "%s:%d:%d: error: %s\n"
            d.span.March_ast.Ast.file d.span.March_ast.Ast.start_line
            d.span.March_ast.Ast.start_col d.message
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
  (* Parse --check flag and collect targets *)
  let check_mode = ref false in
  let targets    = ref [] in
  List.iter (fun a ->
    if a = "--check" then check_mode := true
    else targets := a :: !targets
  ) args;
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
  let desugared = March_desugar.Desugar.desugar_module module_ast in
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
  (* Inject stdlib declarations before user declarations *)
  let stdlib_decls = load_stdlib () in
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
      if is_user_file d then begin
        let sev = match d.severity with
          | March_errors.Errors.Error   -> "error"
          | March_errors.Errors.Warning -> "warning"
          | March_errors.Errors.Hint    -> "hint"
        in
        Printf.eprintf "%s:%d:%d: %s: %s\n"
          d.span.March_ast.Ast.file
          d.span.March_ast.Ast.start_line
          d.span.March_ast.Ast.start_col
          sev
          d.message;
        List.iter (fun note ->
            Printf.eprintf "note: %s\n" note
          ) d.notes
      end
    ) diags;
  let compile_mode = !dump_tir || !emit_llvm || !do_compile in
  let has_user_errors = List.exists (fun (d : March_errors.Errors.diagnostic) ->
      d.severity = March_errors.Errors.Error && is_user_file d
    ) diags in
  (* In compile mode, abort on user-file errors only.  Stdlib errors
     (e.g. http_client) are tolerated since those modules are WIP. *)
  if has_user_errors || has_parse_errors || has_resolve_errors then exit 1
  else if compile_mode then begin
    let tir = March_tir.Lower.lower_module ~type_map desugared in
    let tir = March_tir.Mono.monomorphize tir in
    let tir = if !opt_enabled then March_tir.Fusion.run ~changed:(ref false) tir else tir in
    let tir = March_tir.Defun.defunctionalize tir in
    (* Known-call pass: run before Perceus so apply functions are still pure
       and eligible for inlining in the subsequent Opt fixed-point loop.
       Also included in the Opt coordinator for cases revealed after Perceus. *)
    let tir = if !opt_enabled
              then March_tir.Known_call.run ~changed:(ref false) tir
              else tir in
    let tir = March_tir.Perceus.perceus tir in
    let tir = March_tir.Escape.escape_analysis tir in
    let tir = if !opt_enabled then March_tir.Opt.run tir else tir in
    if !dump_tir then begin
      List.iter (fun td ->
          Printf.printf "%s\n\n" (March_tir.Pp.string_of_type_def td)
        ) tir.tm_types;
      List.iter (fun fn ->
          Printf.printf "%s\n\n" (March_tir.Pp.string_of_fn_def fn)
        ) tir.tm_fns
    end else begin
      let basename = Filename.remove_extension filename in
      let ll_file  = basename ^ ".ll" in
      if !do_compile then begin
        let out_bin =
          if !output_file <> "" then !output_file
          else basename
        in
        (* CAS: check for a cached binary before running clang *)
        let store = March_cas.Cas.create ~project_root:(Sys.getcwd ()) in
        let h_sccs = March_cas.Pipeline.hash_module tir in
        let mod_hash = String.concat "" (List.map March_cas.Pipeline.scc_impl_hash h_sccs) in
        let effective_opt = if !opt_level >= 0 && !opt_level <= 3 then !opt_level else 2 in
        let cas_flags = [if !opt_enabled then Printf.sprintf "O%d" effective_opt else "no-opt"] in
        let ch = March_cas.Cas.compilation_hash mod_hash ~target:"native" ~flags:cas_flags in
        (match March_cas.Cas.lookup_artifact store ch with
        | Some cached_bin ->
          let _ = Sys.command (Printf.sprintf "cp %s %s" cached_bin out_bin) in
          Printf.eprintf "compiled %s (cached)\n" out_bin
        | None ->
          (* Cache miss: emit LLVM IR, call clang, then cache the binary *)
          let ir = March_tir.Llvm_emit.emit_module ~fast_math:!fast_math tir in
          let oc = open_out ll_file in
          output_string oc ir;
          close_out oc;
          (* Locate the runtime: try cwd-relative first (development), then
             relative to the executable (installed). *)
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
          let extra_c_files =
            if Sys.file_exists http_c then
              let sha1_c    = Filename.concat runtime_dir "sha1.c" in
              let base64_c  = Filename.concat runtime_dir "base64.c" in
              let simd_c    = Filename.concat runtime_dir "march_http_parse_simd.c" in
              let sched_c   = Filename.concat runtime_dir "march_scheduler.c" in
              let resp_c    = Filename.concat runtime_dir "march_http_response.c" in
              let io_c      = Filename.concat runtime_dir "march_http_io.c" in
              let evloop_c  = Filename.concat runtime_dir "march_http_evloop.c" in
              let opt_file f = if Sys.file_exists f then Printf.sprintf " %s" f else "" in
              Printf.sprintf " %s %s %s%s%s%s%s%s" http_c sha1_c base64_c
                (opt_file simd_c) (opt_file sched_c) (opt_file resp_c)
                (opt_file io_c) (opt_file evloop_c)
            else ""
          in
          let evloop_flag =
            let evloop_c = Filename.concat runtime_dir "march_http_evloop.c" in
            if Sys.file_exists evloop_c then " -DMARCH_HTTP_USE_EVLOOP" else ""
          in
          let cmd = Printf.sprintf
            "clang%s -msse4.2 -Wno-unused-command-line-argument%s %s%s %s -o %s"
            opt_flag evloop_flag runtime extra_c_files ll_file out_bin in
          let rc = Sys.command cmd in
          if rc <> 0 then begin
            Printf.eprintf "march: clang failed (exit %d)\n" rc; exit 1
          end else begin
            March_cas.Cas.store_artifact store ch out_bin;
            Printf.eprintf "compiled %s\n" out_bin
          end)
      end else begin
        (* --emit-llvm only: write IR and exit *)
        let ir = March_tir.Llvm_emit.emit_module ~fast_math:!fast_math tir in
        let oc = open_out ll_file in
        output_string oc ir;
        close_out oc;
        Printf.eprintf "wrote %s\n" ll_file
      end
    end
  end
  else begin
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
       Printf.eprintf "%s: match failure: %s\n" filename msg; exit 1);
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
  let files = ref [] in
  let specs = [
    ("--dump-tir",   Arg.Set dump_tir,    " Print TIR instead of evaluating");
    ("--emit-llvm",  Arg.Set emit_llvm,   " Emit LLVM IR to <file>.ll");
    ("--compile",    Arg.Set do_compile,  " Compile to native binary via clang");
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
