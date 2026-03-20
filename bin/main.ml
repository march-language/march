(** March compiler entry point. *)

(* ------------------------------------------------------------------ *)
(* Stdlib loader                                                       *)
(* ------------------------------------------------------------------ *)

(** Locate the stdlib directory.  Try paths relative to the source root
    (for development) and relative to the installed executable. *)
let find_stdlib_dir () =
  let candidates = [
    "stdlib";
    Filename.concat (Filename.dirname Sys.executable_name) "../stdlib";
    Filename.concat (Filename.dirname Sys.executable_name) "../../stdlib";
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
       let m = March_parser.Parser.module_ March_lexer.Lexer.token lexbuf in
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
  let runtime_c = match List.find_opt Sys.file_exists candidates with
    | Some p -> p
    | None -> failwith "march: cannot find runtime/march_runtime.c"
  in
  let runtime_dir = Filename.dirname runtime_c in
  (* Recompile if .so is missing or older than .c *)
  let needs_compile =
    not (Sys.file_exists so_path) ||
    (Unix.stat runtime_c).st_mtime > (Unix.stat so_path).st_mtime
  in
  if needs_compile then begin
    (* Note: -lpthread not needed on macOS (pthreads are in libSystem). *)
    let http_c = Filename.concat runtime_dir "march_http.c" in
    let extra_files =
      if Sys.file_exists http_c then
        let sha1_c = Filename.concat runtime_dir "sha1.c" in
        let base64_c = Filename.concat runtime_dir "base64.c" in
        Printf.sprintf " %s %s %s" http_c sha1_c base64_c
      else ""
    in
    let cmd = Printf.sprintf
      "clang -shared -O2 -fPIC -I%s %s%s -o %s 2>&1"
      runtime_dir runtime_c extra_files so_path in
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

(* ------------------------------------------------------------------ *)
(* File compiler                                                       *)
(* ------------------------------------------------------------------ *)

let compile filename =
  let src =
    try
      let ic = open_in filename in
      let n = in_channel_length ic in
      let buf = Bytes.create n in
      really_input ic buf 0 n;
      close_in ic;
      Bytes.to_string buf
    with Sys_error msg ->
      Printf.eprintf "march: %s\n" msg;
      exit 1
  in
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
  (* Parse *)
  let module_ast =
    try March_parser.Parser.module_ March_lexer.Lexer.token lexbuf
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
  (* Desugar *)
  let desugared = March_desugar.Desugar.desugar_module module_ast in
  (* Inject stdlib declarations before user declarations *)
  let stdlib_decls = load_stdlib () in
  let desugared =
    { desugared with
      March_ast.Ast.mod_decls = stdlib_decls @ desugared.March_ast.Ast.mod_decls }
  in
  (* Typecheck *)
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
        Printf.printf "%s:%d:%d: %s: %s\n"
          d.span.March_ast.Ast.file
          d.span.March_ast.Ast.start_line
          d.span.March_ast.Ast.start_col
          sev
          d.message;
        List.iter (fun note ->
            Printf.printf "note: %s\n" note
          ) d.notes
      end
    ) diags;
  let compile_mode = !dump_tir || !emit_llvm || !do_compile in
  let has_user_errors = List.exists (fun (d : March_errors.Errors.diagnostic) ->
      d.severity = March_errors.Errors.Error && is_user_file d
    ) diags in
  (* In compile mode, abort on user-file errors only.  Stdlib errors
     (e.g. http_client) are tolerated since those modules are WIP. *)
  if has_user_errors then exit 1
  else if compile_mode then begin
    let tir = March_tir.Lower.lower_module ~type_map desugared in
    let tir = March_tir.Mono.monomorphize tir in
    let tir = March_tir.Defun.defunctionalize tir in
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
      let ir = March_tir.Llvm_emit.emit_module ~fast_math:!fast_math tir in
      let oc = open_out ll_file in
      output_string oc ir;
      close_out oc;
      if !do_compile then begin
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
        let out_bin =
          if !output_file <> "" then !output_file
          else basename
        in
        let opt_flag =
          if !opt_level >= 0 && !opt_level <= 3
          then Printf.sprintf " -O%d" !opt_level
          else ""
        in
        let runtime_dir = Filename.dirname runtime in
        let http_c = Filename.concat runtime_dir "march_http.c" in
        let extra_c_files =
          if Sys.file_exists http_c then
            let sha1_c = Filename.concat runtime_dir "sha1.c" in
            let base64_c = Filename.concat runtime_dir "base64.c" in
            Printf.sprintf " %s %s %s" http_c sha1_c base64_c
          else ""
        in
        let cmd = Printf.sprintf "clang%s %s%s %s -o %s"
          opt_flag runtime extra_c_files ll_file out_bin in
        let rc = Sys.command cmd in
        if rc <> 0 then begin
          Printf.eprintf "march: clang failed (exit %d)\n" rc; exit 1
        end else
          Printf.printf "compiled %s\n" out_bin
      end else
        Printf.printf "wrote %s\n" ll_file
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

let () =
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
