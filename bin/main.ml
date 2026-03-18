(** March compiler entry point. *)

let dump_tir       = ref false
let emit_llvm      = ref false
let do_compile     = ref false
let output_file    = ref ""
let debug_mode     = ref false
let debug_tui_mode = ref false

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
    with March_parser.Parser.Error ->
      let pos = Lexing.lexeme_start_p lexbuf in
      Printf.eprintf "%s:%d:%d: parse error\n"
        pos.Lexing.pos_fname
        pos.Lexing.pos_lnum
        (pos.Lexing.pos_cnum - pos.Lexing.pos_bol);
      exit 1
  in
  (* Desugar *)
  let desugared = March_desugar.Desugar.desugar_module module_ast in
  (* Typecheck *)
  let (errors, type_map) = March_typecheck.Typecheck.check_module desugared in
  (* Print diagnostics sorted by position *)
  let diags = March_errors.Errors.sorted errors in
  List.iter (fun (d : March_errors.Errors.diagnostic) ->
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
    ) diags;
  if March_errors.Errors.has_errors errors then exit 1
  else if !dump_tir || !emit_llvm || !do_compile then begin
    let tir = March_tir.Lower.lower_module ~type_map desugared in
    let tir = March_tir.Mono.monomorphize tir in
    let tir = March_tir.Defun.defunctionalize tir in
    let tir = March_tir.Perceus.perceus tir in
    let tir = March_tir.Escape.escape_analysis tir in
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
      let ir = March_tir.Llvm_emit.emit_module tir in
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
        let cmd = Printf.sprintf "clang %s %s -o %s" runtime ll_file out_bin in
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
          March_debug.Debug_repl.run_simple_session
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
    ("--debug",     Arg.Set debug_mode,     " Enable time-travel debugger (simple mode)");
    ("--debug-tui", Arg.Set debug_tui_mode, " Enable time-travel debugger (TUI mode)");
  ] in
  Arg.parse specs (fun f -> files := f :: !files) "Usage: march [options] [file.march]";
  match !files with
  | []  -> March_repl.Repl.run ()
  | [f] -> compile f
  | _   -> Printf.eprintf "Usage: march [options] [file.march]\n"; exit 1
