(** March REPL v2 — full TUI main loop.
    Dispatches to run_tui (notty two-pane) or run_simple (plain text)
    depending on whether stdin/stdout are a terminal. *)

let history_path () =
  match Sys.getenv_opt "MARCH_HISTORY_FILE" with
  | Some p -> p
  | None   -> Filename.concat (Sys.getenv "HOME") ".march_history"

let history_size () =
  match Sys.getenv_opt "MARCH_HISTORY_SIZE" with
  | Some s -> (try int_of_string s with _ -> 1000)
  | None   -> 1000

(** Build scope panel entries from eval env + typecheck env. *)
let user_scope eval_env tc_env result_h =
  let builtin_names = List.map fst March_eval.Eval.base_env in
  let scope = List.filter_map (fun (name, v) ->
    if List.mem name builtin_names
    || name = "v"
    || (String.length name > 0 && name.[0] = '_')
    then None
    else
      let vs = March_eval.Eval.value_to_string v in
      let ty_str =
        match List.assoc_opt name tc_env.March_typecheck.Typecheck.vars with
        | None -> "?"
        | Some scheme ->
          let ty = March_typecheck.Typecheck.instantiate
            tc_env.March_typecheck.Typecheck.level tc_env scheme in
          March_typecheck.Typecheck.pp_ty (March_typecheck.Typecheck.repr ty)
      in
      Some Tui.{ name; type_str = ty_str; val_str = vs }
  ) eval_env in
  let result_latest = match Result_vars.get result_h 0 with
    | None       -> None
    | Some entry -> Some (entry.Result_vars.type_str, entry.Result_vars.val_str)
  in
  (scope, result_latest)

(** Non-TUI fallback REPL. *)
let run_simple () =
  Printf.printf "March REPL — :quit to exit, :env to list bindings\n%!";
  let env      = ref March_eval.Eval.base_env in
  let type_map = Hashtbl.create 64 in
  let tc_env   = ref (March_typecheck.Typecheck.base_env
    (March_errors.Errors.create ()) type_map) in
  let result_h = Result_vars.create () in
  let hist     = History.create ~max_size:(history_size ()) in
  History.load hist (history_path ());
  let prompt_num = ref 1 in
  let running    = ref true in
  let buf        = Buffer.create 64 in
  let first_line = ref true in

  let print_diag (d : March_errors.Errors.diagnostic) =
    let sev = match d.severity with
      | March_errors.Errors.Error   -> "error"
      | March_errors.Errors.Warning -> "warning"
      | March_errors.Errors.Hint    -> "hint"
    in
    Printf.eprintf "%s: %s\n%!" sev d.message;
    List.iter (fun note -> Printf.eprintf "note: %s\n%!" note) d.notes
  in

  while !running do
    (try
       let prompt = Printf.sprintf "march(%d)> " !prompt_num in
       let cont   = String.make (String.length prompt) ' ' in
       Printf.printf "%s%!" (if !first_line then prompt else cont);
       first_line := false;
       (match (try Some (input_line stdin) with End_of_file -> None) with
        | None ->
          let s = Buffer.contents buf in
          if s = "" then running := false
          else begin
            Buffer.clear buf;
            first_line := true;
            incr prompt_num
          end
        | Some line ->
          if Buffer.length buf > 0 then Buffer.add_char buf '\n';
          Buffer.add_string buf line;
          let contents = Buffer.contents buf in
          if Multiline.is_complete contents && String.trim line <> "" then begin
            let src = contents in
            Buffer.clear buf;
            first_line := true;
            incr prompt_num;
            History.add hist src;
            (match String.trim src with
             | ":quit" | ":q" -> running := false
             | ":env" ->
               List.iter (fun (k, _) ->
                 if not (List.mem_assoc k March_eval.Eval.base_env) then
                   Printf.printf "  %s\n" k
               ) !env
             | src when String.trim src = "" -> ()
             | src ->
               let lexbuf = Lexing.from_string src in
               (match (try Some (March_parser.Parser.repl_input March_lexer.Lexer.token lexbuf)
                       with March_parser.Parser.Error ->
                         let pos = Lexing.lexeme_start_p lexbuf in
                         Printf.eprintf "parse error at col %d\n%!"
                           (pos.Lexing.pos_cnum - pos.Lexing.pos_bol);
                         None) with
               | None | Some March_ast.Ast.ReplEOF -> ()
               | Some (March_ast.Ast.ReplDecl d) ->
                 let d' = March_desugar.Desugar.desugar_decl d in
                 let input_ctx = March_errors.Errors.create () in
                 let input_tc  = { !tc_env with errors = input_ctx } in
                 let new_tc    = March_typecheck.Typecheck.check_decl input_tc d' in
                 List.iter print_diag (March_errors.Errors.sorted input_ctx);
                 if not (March_errors.Errors.has_errors input_ctx) then
                   (try
                      env := March_eval.Eval.eval_decl !env d';
                      tc_env := { new_tc with errors = March_errors.Errors.create () };
                      (match d' with
                       | March_ast.Ast.DFn (def, _) ->
                         Printf.printf "val %s = <fn>\n%!" def.fn_name.txt
                       | March_ast.Ast.DLet (b, _) ->
                         (match b.bind_pat with
                          | March_ast.Ast.PatVar n ->
                            let v = List.assoc n.txt !env in
                            Printf.printf "val %s = %s\n%!" n.txt
                              (March_eval.Eval.value_to_string v)
                          | _ -> Printf.printf "val _ = ...\n%!")
                       | March_ast.Ast.DActor (name, _, _) ->
                         Printf.printf "val %s = <actor>\n%!" name.txt
                       | _ -> ())
                    with
                    | March_eval.Eval.Eval_error msg ->
                      Printf.eprintf "runtime error: %s\n%!" msg
                    | March_eval.Eval.Match_failure msg ->
                      Printf.eprintf "match failure: %s\n%!" msg)
               | Some (March_ast.Ast.ReplExpr e) ->
                 let e' = March_desugar.Desugar.desugar_expr e in
                 let input_ctx = March_errors.Errors.create () in
                 let input_tc  = { !tc_env with errors = input_ctx } in
                 let inferred  = March_typecheck.Typecheck.infer_expr input_tc e' in
                 let ty_str    = March_typecheck.Typecheck.pp_ty
                   (March_typecheck.Typecheck.repr inferred) in
                 List.iter print_diag (March_errors.Errors.sorted input_ctx);
                 if March_errors.Errors.has_errors input_ctx then
                   Printf.eprintf "note: inferred type was %s\n%!" ty_str
                 else
                   (try
                      let v = March_eval.Eval.eval_expr !env e' in
                      let vs = March_eval.Eval.value_to_string v in
                      Printf.printf "= %s\n%!" vs;
                      Result_vars.push result_h v ty_str;
                      env    := ("v", v)
                               :: (List.remove_assoc "v" !env);
                      tc_env := { !tc_env with
                        vars = ("v", March_typecheck.Typecheck.Mono inferred)
                               :: (List.remove_assoc "v" !tc_env.vars) }
                    with
                    | March_eval.Eval.Eval_error msg ->
                      Printf.eprintf "runtime error: %s\n%!" msg
                    | March_eval.Eval.Match_failure msg ->
                      Printf.eprintf "match failure: %s\n%!" msg)))
          end)
     with
     | March_lexer.Lexer.Lexer_error msg -> Printf.eprintf "lexer error: %s\n%!" msg
     | exn -> Printf.eprintf "internal error: %s\n%!" (Printexc.to_string exn))
  done;
  History.save hist (history_path ())

(** Full TUI REPL loop using notty two-pane layout. *)
let run_tui () =
  let hist     = History.create ~max_size:(history_size ()) in
  History.load hist (history_path ());
  let env      = ref March_eval.Eval.base_env in
  let type_map = Hashtbl.create 64 in
  let tc_env   = ref (March_typecheck.Typecheck.base_env
    (March_errors.Errors.create ()) type_map) in
  let result_h = Result_vars.create () in
  let tui       = Tui.create () in
  let inp       = ref Input.empty in
  let hist_lines = ref [] in
  let prompt_num = ref 1 in
  let running    = ref true in
  let status     = "March REPL  :help  Tab: complete  Up/Down: history" in

  let render_frame () =
    let prompt = Printf.sprintf "march(%d)> " !prompt_num in
    let input_img = Highlight.highlight !inp.Input.buffer in
    (* Show accumulated continuation lines above current input *)
    let cont_imgs = List.map (fun line ->
      let pad_str = String.make (String.length prompt) ' ' in
      Notty.I.(Notty.I.string Notty.A.empty pad_str <|> Highlight.highlight line)
    ) (List.rev !inp.Input.multiline_buf) in
    let transcript = !hist_lines @ cont_imgs in
    let (scope, result_latest) = user_scope !env !tc_env result_h in
    Tui.render tui Tui.{
      history       = transcript;
      input_line    = input_img;
      prompt;
      scope;
      result_latest;
      status;
      completions    = [];      (* stub — wired in Task 4 *)
      completion_sel = 0;       (* stub *)
      actors         = [];      (* stub — wired in Task 4 *)
    }
  in

  let add_line attr s =
    hist_lines := !hist_lines @ [Notty.I.string attr s]
  in

  let process_src src =
    let lexbuf = Lexing.from_string src in
    (match (try Some (March_parser.Parser.repl_input March_lexer.Lexer.token lexbuf)
            with March_parser.Parser.Error ->
              let pos = Lexing.lexeme_start_p lexbuf in
              add_line Notty.A.(fg red)
                (Printf.sprintf "parse error at col %d"
                   (pos.Lexing.pos_cnum - pos.Lexing.pos_bol));
              None) with
    | None | Some March_ast.Ast.ReplEOF -> ()
    | Some (March_ast.Ast.ReplDecl d) ->
      let d' = March_desugar.Desugar.desugar_decl d in
      let input_ctx = March_errors.Errors.create () in
      let input_tc  = { !tc_env with errors = input_ctx } in
      let new_tc    = March_typecheck.Typecheck.check_decl input_tc d' in
      List.iter (fun (diag : March_errors.Errors.diagnostic) ->
        let (label, attr) = match diag.severity with
          | March_errors.Errors.Error   -> ("error",   Notty.A.(fg red))
          | March_errors.Errors.Warning -> ("warning", Notty.A.(fg yellow))
          | March_errors.Errors.Hint    -> ("hint",    Notty.A.(fg blue))
        in
        add_line attr (Printf.sprintf "%s: %s" label diag.message);
        List.iter (fun note ->
          add_line Notty.A.empty (Printf.sprintf "note: %s" note)) diag.notes
      ) (March_errors.Errors.sorted input_ctx);
      if not (March_errors.Errors.has_errors input_ctx) then
        (try
           env := March_eval.Eval.eval_decl !env d';
           tc_env := { new_tc with errors = March_errors.Errors.create () };
           let out = match d' with
             | March_ast.Ast.DFn (def, _) ->
               Printf.sprintf "val %s = <fn>" def.fn_name.txt
             | March_ast.Ast.DLet (b, _) ->
               (match b.bind_pat with
                | March_ast.Ast.PatVar n ->
                  let v = List.assoc n.txt !env in
                  Printf.sprintf "val %s = %s" n.txt (March_eval.Eval.value_to_string v)
                | _ -> "val _ = ...")
             | March_ast.Ast.DActor (name, _, _) ->
               Printf.sprintf "val %s = <actor>" name.txt
             | _ -> ""
           in
           if out <> "" then add_line Notty.A.empty out
         with
         | March_eval.Eval.Eval_error msg ->
           add_line Notty.A.(fg red) (Printf.sprintf "runtime error: %s" msg)
         | March_eval.Eval.Match_failure msg ->
           add_line Notty.A.(fg red) (Printf.sprintf "match failure: %s" msg))
    | Some (March_ast.Ast.ReplExpr e) ->
      let e' = March_desugar.Desugar.desugar_expr e in
      let input_ctx = March_errors.Errors.create () in
      let input_tc  = { !tc_env with errors = input_ctx } in
      let inferred  = March_typecheck.Typecheck.infer_expr input_tc e' in
      let ty_str    = March_typecheck.Typecheck.pp_ty
        (March_typecheck.Typecheck.repr inferred) in
      List.iter (fun (diag : March_errors.Errors.diagnostic) ->
        let (label, attr) = match diag.severity with
          | March_errors.Errors.Error   -> ("error",   Notty.A.(fg red))
          | March_errors.Errors.Warning -> ("warning", Notty.A.(fg yellow))
          | March_errors.Errors.Hint    -> ("hint",    Notty.A.(fg blue))
        in
        add_line attr (Printf.sprintf "%s: %s" label diag.message);
        List.iter (fun note ->
          add_line Notty.A.empty (Printf.sprintf "note: %s" note)) diag.notes
      ) (March_errors.Errors.sorted input_ctx);
      if March_errors.Errors.has_errors input_ctx then
        add_line Notty.A.empty (Printf.sprintf "note: inferred type was %s" ty_str)
      else
        (try
           let v = March_eval.Eval.eval_expr !env e' in
           let vs = March_eval.Eval.value_to_string v in
           add_line Notty.A.(fg green) (Printf.sprintf "= %s" vs);
           Result_vars.push result_h v ty_str;
           env    := ("v", v) :: (List.remove_assoc "v" !env);
           tc_env := { !tc_env with
             vars = ("v", March_typecheck.Typecheck.Mono inferred)
                    :: (List.remove_assoc "v" !tc_env.vars) }
         with
         | March_eval.Eval.Eval_error msg ->
           add_line Notty.A.(fg red) (Printf.sprintf "runtime error: %s" msg)
         | March_eval.Eval.Match_failure msg ->
           add_line Notty.A.(fg red) (Printf.sprintf "match failure: %s" msg)))
  in

  render_frame ();

  while !running do
    (match Tui.next_event tui with
     | `End -> running := false
     | `Resize _ -> render_frame ()
     | `Key key ->
       let (inp', action) = Input.handle_key !inp key in
       inp := inp';
       (match action with
        | Input.EOF -> running := false
        | Input.Submit src ->
          (* Add submitted input to transcript *)
          let prompt = Printf.sprintf "march(%d)> " !prompt_num in
          let src_lines = String.split_on_char '\n' src in
          List.iteri (fun i line ->
            let pfx =
              if i = 0 then Notty.I.string Notty.A.(st bold ++ fg blue) prompt
              else Notty.I.string Notty.A.empty (String.make (String.length prompt) ' ')
            in
            hist_lines := !hist_lines @ [Notty.I.(pfx <|> Highlight.highlight line)]
          ) src_lines;
          History.add hist src;
          History.reset_pos hist;
          incr prompt_num;
          inp := Input.empty;
          (* Dispatch to command handler or process_src *)
          (match String.trim src with
           | ":quit" | ":q" -> running := false
           | ":env" ->
             let lines = List.filter_map (fun (k, v) ->
               if List.mem_assoc k March_eval.Eval.base_env then None
               else Some (Printf.sprintf "  %s = %s" k
                 (March_eval.Eval.value_to_string v))
             ) !env in
             List.iter (add_line Notty.A.empty) lines
           | ":clear" -> hist_lines := []
           | ":reset" ->
             env := March_eval.Eval.base_env;
             tc_env := March_typecheck.Typecheck.base_env
               (March_errors.Errors.create ()) type_map;
             hist_lines := []
           | ":help" ->
             List.iter (add_line Notty.A.empty) [
               "Commands:";
               "  :quit :q        — exit";
               "  :env            — list bindings";
               "  :type <expr>    — show type without evaluating";
               "  :clear          — clear transcript (keeps bindings)";
               "  :reset          — reset all bindings";
               "  :load <file>    — load a .march file";
               "  :help           — this message";
               "";
               "Keys: Tab: complete | Up/Down: history";
               "      Ctrl+A/E: home/end | Ctrl+W: kill word | Ctrl+Y: yank";
               "Magic: v = last result";
             ]
           | src when String.length src > 5 && String.sub src 0 5 = ":type" ->
             let expr_src = String.trim (String.sub src 5 (String.length src - 5)) in
             if expr_src = "" then
               add_line Notty.A.(fg red) "usage: :type <expr>"
             else begin
               let lexbuf = Lexing.from_string expr_src in
               (match (try Some (March_parser.Parser.repl_input March_lexer.Lexer.token lexbuf)
                       with _ -> None) with
               | Some (March_ast.Ast.ReplExpr e) ->
                 let e' = March_desugar.Desugar.desugar_expr e in
                 let input_ctx = March_errors.Errors.create () in
                 let input_tc  = { !tc_env with errors = input_ctx } in
                 let inferred  = March_typecheck.Typecheck.infer_expr input_tc e' in
                 let ty_str    = March_typecheck.Typecheck.pp_ty
                   (March_typecheck.Typecheck.repr inferred) in
                 if March_errors.Errors.has_errors input_ctx then
                   add_line Notty.A.(fg red) "type error"
                 else
                   add_line Notty.A.(fg cyan) (Printf.sprintf "- : %s" ty_str)
               | _ -> add_line Notty.A.(fg red) "parse error")
             end
           | src when String.length src > 5 && String.sub src 0 5 = ":load" ->
             let path = String.trim (String.sub src 5 (String.length src - 5)) in
             if path = "" then
               add_line Notty.A.(fg red) "usage: :load <file>"
             else
               (match (try
                 let ic = open_in path in
                 let n  = in_channel_length ic in
                 let b  = Bytes.create n in
                 really_input ic b 0 n;
                 close_in ic;
                 Some (Bytes.to_string b)
               with Sys_error msg -> add_line Notty.A.(fg red)
                 (Printf.sprintf "cannot open: %s" msg); None) with
               | None -> ()
               | Some file_src ->
                 let lexbuf = Lexing.from_string file_src in
                 (match (try
                   let m = March_parser.Parser.module_ March_lexer.Lexer.token lexbuf in
                   Some (March_desugar.Desugar.desugar_module m)
                 with _ -> add_line Notty.A.(fg red) "parse error in file"; None) with
                 | None -> ()
                 | Some desugared ->
                   List.iter (fun decl ->
                     let input_ctx = March_errors.Errors.create () in
                     let input_tc  = { !tc_env with errors = input_ctx } in
                     let new_tc    = March_typecheck.Typecheck.check_decl input_tc decl in
                     if not (March_errors.Errors.has_errors input_ctx) then begin
                       (try
                         env := March_eval.Eval.eval_decl !env decl;
                         tc_env := { new_tc with errors = March_errors.Errors.create () }
                       with _ -> ())
                     end else
                       List.iter (fun (d : March_errors.Errors.diagnostic) ->
                         add_line Notty.A.(fg red)
                           (Printf.sprintf "error: %s" d.message)
                       ) (March_errors.Errors.sorted input_ctx)
                   ) desugared.March_ast.Ast.mod_decls;
                   add_line Notty.A.(fg green) (Printf.sprintf "loaded %s" path)))
           | src when String.length src > 5 && String.sub src 0 5 = ":save" ->
             let path = String.trim (String.sub src 5 (String.length src - 5)) in
             if path = "" then
               add_line Notty.A.(fg red) "usage: :save <file>"
             else
               add_line Notty.A.(fg yellow)
                 (Printf.sprintf ":save %s — session tracking not yet implemented" path)
           | src when String.trim src = "" -> ()
           | src -> process_src src);
          render_frame ()
        | Input.HistoryPrev ->
          (match History.prev hist with
           | None -> ()
           | Some entry ->
             inp := { !inp with Input.buffer = entry;
                                Input.cursor = String.length entry };
             render_frame ())
        | Input.HistoryNext ->
          let entry = match History.next hist with None -> "" | Some e -> e in
          inp := { !inp with Input.buffer = entry;
                             Input.cursor = String.length entry };
          render_frame ()
        | Input.Redraw | Input.Noop -> render_frame ()
        | Input.Complete ->
          let b = !inp.Input.buffer and c = !inp.Input.cursor in
          let i = ref c in
          while !i > 0 && b.[!i - 1] <> ' ' do decr i done;
          let prefix = String.sub b !i (c - !i) in
          let scope = List.filter_map (fun (name, v) ->
            if List.mem_assoc name March_eval.Eval.base_env then None
            else Some (name, March_eval.Eval.value_to_string v)
          ) !env in
          let completions = Complete.complete prefix scope in
          (match completions with
           | [] -> ()
           | [single] ->
             let suffix = String.sub single (String.length prefix)
               (String.length single - String.length prefix) in
             inp := Input.insert_at !inp suffix;
             render_frame ()
           | multiple ->
             add_line Notty.A.empty (String.concat "  " multiple);
             render_frame ())
        | Input.HistorySearch -> () (* Phase 2 *)
       ))
  done;
  History.save hist (history_path ());
  Tui.close tui

let run () =
  if Unix.isatty Unix.stdin && Unix.isatty Unix.stdout
  then run_tui ()
  else run_simple ()
