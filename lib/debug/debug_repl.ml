(** March debug REPL session.

    Called by the [on_dbg] callback when [dbg()] is hit.
    Runs an interactive command loop until :continue is entered.

    In simple mode (default): reads from stdin line-by-line, prints to stdout. *)

module Eval  = March_eval.Eval

(** Print the debug prompt. *)
let prompt (ctx : Eval.debug_ctx) =
  if ctx.dc_pos = 0
  then Printf.printf "dbg> %!"
  else Printf.printf "[frame %d] dbg> %!" ctx.dc_pos

(** Parse an optional integer argument from a string like ":back 5" *)
let parse_int_arg (s : string) (default : int) : int =
  let trimmed = String.trim s in
  if trimmed = "" then default
  else (try int_of_string trimmed with _ -> default)

(** Evaluate a March expression string against [env] and print the result. *)
let eval_in_env (env : Eval.env) (tc_env : March_typecheck.Typecheck.env ref)
                (src : string) : unit =
  let lexbuf = Lexing.from_string src in
  (match (try Some (March_parser.Parser.repl_input March_lexer.Lexer.token lexbuf)
          with _ -> Printf.printf "parse error\n%!"; None) with
   | None | Some March_ast.Ast.ReplEOF -> ()
   | Some (March_ast.Ast.ReplDecl _) ->
     Printf.printf "note: declarations not supported in debug REPL\n%!"
   | Some (March_ast.Ast.ReplExpr e) ->
     let e' = March_desugar.Desugar.desugar_expr e in
     let input_ctx = March_errors.Errors.create () in
     let input_tc  = { !tc_env with March_typecheck.Typecheck.errors = input_ctx } in
     let inferred  = March_typecheck.Typecheck.infer_expr input_tc e' in
     let ty_str    = March_typecheck.Typecheck.pp_ty
       (March_typecheck.Typecheck.repr inferred) in
     if March_errors.Errors.has_errors input_ctx then
       Printf.printf "type error\n%!"
     else
       (try
          let v = Eval.eval_expr env e' in
          Printf.printf "= %s : %s\n%!" (Eval.value_to_string v) ty_str
        with
        | Eval.Eval_error msg    -> Printf.printf "runtime error: %s\n%!" msg
        | Eval.Match_failure msg -> Printf.printf "match failure: %s\n%!" msg))

(** Main debug REPL session. Called as the [on_dbg] callback. *)
let run_simple_session (ctx : Eval.debug_ctx) (initial_env : Eval.env) : unit =
  let type_map = Hashtbl.create 32 in
  let tc_env   = ref (March_typecheck.Typecheck.base_env
    (March_errors.Errors.create ()) type_map) in
  let env_ref = ref initial_env in
  let running = ref true in
  Printf.printf "\n[debug] Breakpoint hit at %s\n%!"
    (match Trace.current_frame ctx with
     | None   -> "<unknown>"
     | Some f ->
       let sp = f.tf_span in
       Printf.sprintf "%s:%d:%d"
         sp.March_ast.Ast.file sp.March_ast.Ast.start_line
         sp.March_ast.Ast.start_col);
  Printf.printf "[debug] :help for commands\n%!";
  while !running do
    prompt ctx;
    (match (try Some (input_line stdin) with End_of_file -> None) with
     | None -> running := false
     | Some line ->
       let line = String.trim line in
       (match line with
        | ":continue" | ":c" ->
          running := false
        | ":quit" | ":q" ->
          Printf.printf "[debug] Exiting.\n%!";
          exit 0
        | ":help" | ":h" ->
          List.iter (fun s -> Printf.printf "%s\n" s) [
            "Debug commands:";
            "  :continue :c       — resume execution";
            "  :back [n] :b [n]   — step back n frames (default 1)";
            "  :forward [n] :f [n]— step forward n frames (default 1)";
            "  :step :s           — step forward 1 frame";
            "  :trace [n] :t [n]  — show last n frames (default 10)";
            "  :where :w          — show current position";
            "  :stack :sk         — show call stack";
            "  :env               — show current env bindings";
            "  :let x = expr      — rebind x in current env";
            "  :replay :r         — replay from current frame with modified env";
            "  :quit :q           — exit program";
            "";
            "Any other input is evaluated as a March expression.";
          ]
        | ":where" | ":w" ->
          Printf.printf "%s\n%!" (Trace.show_where ctx)
        | ":stack" | ":sk" ->
          List.iter (fun s -> Printf.printf "%s\n" s)
            (Trace.show_stack ctx)
        | ":env" ->
          let builtin_names = List.map fst Eval.base_env in
          List.iter (fun (k, v) ->
            if not (List.mem k builtin_names) then
              Printf.printf "  %s = %s\n" k (Eval.value_to_string v)
          ) !env_ref
        | ":replay" | ":r" ->
          (match Replay.replay_from ctx !env_ref with
           | None   -> Printf.printf "[replay] Done (exception or no frame).\n%!"
           | Some v -> Printf.printf "[replay] Result: %s\n%!"
                         (Eval.value_to_string v))
        | s when String.length s >= 6 && String.sub s 0 6 = ":back " ->
          let n = parse_int_arg (String.sub s 5 (String.length s - 5)) 1 in
          let pos = Trace.back ctx n in
          Printf.printf "Moved to frame %d.\n%!" pos;
          (match Trace.current_frame ctx with
           | None -> ()
           | Some f -> env_ref := f.tf_env)
        | ":back" | ":b" ->
          let pos = Trace.back ctx 1 in
          Printf.printf "Moved to frame %d.\n%!" pos;
          (match Trace.current_frame ctx with
           | None -> ()
           | Some f -> env_ref := f.tf_env)
        | s when String.length s >= 9 && String.sub s 0 9 = ":forward " ->
          let n = parse_int_arg (String.sub s 8 (String.length s - 8)) 1 in
          let pos = Trace.forward ctx n in
          Printf.printf "Moved to frame %d.\n%!" pos;
          (match Trace.current_frame ctx with
           | None -> ()
           | Some f -> env_ref := f.tf_env)
        | ":forward" | ":f" | ":step" | ":s" ->
          let pos = Trace.forward ctx 1 in
          Printf.printf "Moved to frame %d.\n%!" pos;
          (match Trace.current_frame ctx with
           | None -> ()
           | Some f -> env_ref := f.tf_env)
        | s when String.length s >= 7 && String.sub s 0 7 = ":trace " ->
          let n = parse_int_arg (String.sub s 6 (String.length s - 6)) 10 in
          List.iter (fun s -> Printf.printf "%s\n" s)
            (Trace.show_trace ctx n)
        | ":trace" | ":t" ->
          List.iter (fun s -> Printf.printf "%s\n" s)
            (Trace.show_trace ctx 10)
        | s when String.length s > 5 && String.sub s 0 5 = ":let " ->
          let rest = String.sub s 5 (String.length s - 5) in
          (match String.split_on_char '=' rest with
           | name_part :: expr_parts ->
             let name = String.trim name_part in
             let expr_src = String.trim (String.concat "=" expr_parts) in
             let lexbuf = Lexing.from_string expr_src in
             (try
                let e = March_parser.Parser.expr_eof March_lexer.Lexer.token lexbuf in
                let e' = March_desugar.Desugar.desugar_expr e in
                let v  = Eval.eval_expr !env_ref e' in
                env_ref := Replay.rebind_in_env name v !env_ref;
                Printf.printf "%s rebound to %s\n%!" name (Eval.value_to_string v)
              with _ -> Printf.printf "error evaluating expression\n%!")
           | [] -> Printf.printf "usage: :let x = expr\n%!")
        | "" -> ()
        | src ->
          eval_in_env !env_ref tc_env src))
  done
