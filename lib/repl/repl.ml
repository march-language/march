(** March REPL v2 — full TUI main loop.
    Dispatches to run_tui (notty two-pane) or run_simple (plain text)
    depending on whether stdin/stdout are a terminal. *)

type debug_hooks = {
  dh_back       : int -> int;
  dh_forward    : int -> int;
  dh_goto       : int -> int;
  dh_where      : unit -> string list;
  dh_stack      : unit -> string list;
  dh_trace      : int -> string list;
  dh_diff       : int -> string list -> string list;
  dh_find       : (March_eval.Eval.env -> bool) -> int option;
  dh_replay     : March_eval.Eval.env -> March_eval.Eval.value option;
  dh_frame_env  : unit -> March_eval.Eval.env option;
  dh_actors     : unit -> string list;
  dh_actor      : int -> int option -> string list;
  dh_save_trace : string -> (unit, string) result;
  dh_load_trace : string -> (unit, string) result;
}

open Notty

type comp_state = CompOff | CompOn of { items: string list; sel: int }

(** Build the input line image with a block cursor at position [cur].
    Uses plain text rendering (no syntax highlight). [cur] and the buffer
    are both byte-based (ASCII), so cursor placement is correct for ASCII
    input; multi-byte UTF-8 characters may show a garbled cursor glyph. *)
let make_input_img s cur =
  let n = String.length s in
  let left  = String.sub s 0 cur in
  let cur_c = if cur < n then String.make 1 s.[cur] else " " in
  let right = if cur < n then String.sub s (cur+1) (n - cur - 1) else "" in
  I.(string A.empty left
     <|> string A.(bg white ++ fg black) cur_c
     <|> string A.empty right)

let history_path () =
  match Sys.getenv_opt "MARCH_HISTORY_FILE" with
  | Some p -> p
  | None   -> Filename.concat (Sys.getenv "HOME") ".march_history"

let history_size () =
  match Sys.getenv_opt "MARCH_HISTORY_SIZE" with
  | Some s -> (try int_of_string s with _ -> 1000)
  | None   -> 1000

(** Build scope panel entries from eval env + typecheck env.
    [baseline_env] is the env after stdlib loading — names present there are hidden. *)
let user_scope eval_env tc_env result_h ~baseline_env =
  let baseline_names = List.map fst baseline_env in
  let seen = Hashtbl.create 16 in
  let scope = List.filter_map (fun (name, v) ->
    if List.mem name baseline_names
    || name = "v"
    || (String.length name > 0 && name.[0] = '_')
    || Hashtbl.mem seen name
    || (match v with March_eval.Eval.VClosure _ | March_eval.Eval.VBuiltin _ -> true | _ -> false)
    then None
    else begin
      Hashtbl.add seen name ();
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
    end
  ) eval_env in
  let result_latest = match Result_vars.get result_h 0 with
    | None       -> None
    | Some entry -> Some (entry.Result_vars.type_str, entry.Result_vars.val_str)
  in
  (scope, result_latest)

(** Load a list of pre-desugared declarations into the eval/typecheck envs silently. *)
let load_decls_into_env env tc_env decls =
  List.fold_left (fun (e, tc) decl ->
    let ctx = March_errors.Errors.create () in
    let tc' = March_typecheck.Typecheck.check_decl { tc with errors = ctx } decl in
    if March_errors.Errors.has_errors ctx then (e, tc)
    else
      let e' = (try March_eval.Eval.eval_decl e decl with _ -> e) in
      (e', { tc' with errors = March_errors.Errors.create () })
  ) (env, tc_env) decls

(** Non-TUI fallback REPL. *)
let run_simple ?(stdlib_decls=[]) ?(debug_hooks=None) ?(initial_env=None) () =
  let is_debug = debug_hooks <> None in
  if is_debug then
    Printf.printf "\n[debug] Breakpoint hit — :continue to resume, :help for commands\n%!"
  else
    Printf.printf "March REPL — :quit to exit, :env to list bindings\n%!";
  let type_map = Hashtbl.create 64 in
  let base_e  = March_eval.Eval.base_env in
  let base_tc = March_typecheck.Typecheck.base_env
    (March_errors.Errors.create ()) type_map in
  let (e0, tc0) = match initial_env with
    | Some e -> (e, base_tc)
    | None   -> load_decls_into_env base_e base_tc stdlib_decls
  in
  let env      = ref e0 in
  let tc_env   = ref tc0 in
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

  (* Show :where immediately on entry. *)
  (match debug_hooks with
   | Some h -> List.iter (fun s -> Printf.printf "%s\n%!" s) (h.dh_where ())
   | None   -> ());

  while !running do
    (try
       let prompt =
         if is_debug then Printf.sprintf "dbg(%d)> " !prompt_num
         else Printf.sprintf "march(%d)> " !prompt_num
       in
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
             | ":quit" | ":q" -> if is_debug then exit 0 else running := false
             | ":continue" | ":c" when is_debug -> running := false
             | ":where" | ":w" when is_debug ->
               (match debug_hooks with
                | Some h -> List.iter (fun s -> Printf.printf "%s\n" s) (h.dh_where ())
                | None -> ())
             | ":stack" | ":sk" when is_debug ->
               (match debug_hooks with
                | Some h -> List.iter (fun s -> Printf.printf "%s\n" s) (h.dh_stack ())
                | None -> ())
             | ":trace" | ":t" when is_debug ->
               (match debug_hooks with
                | Some h -> List.iter (fun s -> Printf.printf "%s\n" s) (h.dh_trace 10)
                | None -> ())
             | ":replay" | ":r" when is_debug ->
               (match debug_hooks with
                | Some h ->
                  (match h.dh_replay !env with
                   | None   -> Printf.printf "[replay] Done (exception or no frame).\n%!"
                   | Some v -> Printf.printf "[replay] Result: %s\n%!"
                                 (March_eval.Eval.value_to_string v))
                | None -> ())
             | ":actors" when is_debug ->
               (match debug_hooks with
                | Some h -> List.iter (fun s -> Printf.printf "%s\n" s) (h.dh_actors ())
                | None -> ())
             | s when is_debug && String.length s >= 7 && String.sub s 0 7 = ":actor " ->
               (match debug_hooks with
                | Some h ->
                  let rest = String.trim (String.sub s 7 (String.length s - 7)) in
                  let (pid, goto_msg) =
                    match String.split_on_char ' ' rest with
                    | [p] -> (int_of_string p, None)
                    | [p; m] -> (int_of_string p, Some (int_of_string m))
                    | _ -> raise (Failure "bad :actor args")
                  in
                  List.iter (fun s -> Printf.printf "%s\n" s) (h.dh_actor pid goto_msg);
                  (match goto_msg with
                   | Some _ -> (match h.dh_frame_env () with Some e -> env := e | None -> ())
                   | None -> ())
                | None -> ())
             | s when is_debug && String.length s >= 6 && String.sub s 0 5 = ":back" ->
               (match debug_hooks with
                | Some h ->
                  let n = (try int_of_string (String.trim (String.sub s 5 (String.length s - 5)))
                           with _ -> 1) in
                  let _pos = h.dh_back n in
                  (match h.dh_frame_env () with Some e -> env := e | None -> ());
                  List.iter (fun s -> Printf.printf "%s\n" s) (h.dh_where ())
                | None -> ())
             | s when is_debug && String.length s >= 8 && String.sub s 0 8 = ":forward" ->
               (match debug_hooks with
                | Some h ->
                  let n = (try int_of_string (String.trim (String.sub s 8 (String.length s - 8)))
                           with _ -> 1) in
                  let _pos = h.dh_forward n in
                  (match h.dh_frame_env () with Some e -> env := e | None -> ());
                  List.iter (fun s -> Printf.printf "%s\n" s) (h.dh_where ())
                | None -> ())
             | ":step" | ":s" when is_debug ->
               (match debug_hooks with
                | Some h ->
                  let _pos = h.dh_forward 1 in
                  (match h.dh_frame_env () with Some e -> env := e | None -> ());
                  List.iter (fun s -> Printf.printf "%s\n" s) (h.dh_where ())
                | None -> ())
             | s when is_debug && String.length s >= 6 && String.sub s 0 6 = ":goto " ->
               (match debug_hooks with
                | Some h ->
                  let n = (try int_of_string (String.trim (String.sub s 6 (String.length s - 6)))
                           with _ -> 0) in
                  let _pos = h.dh_goto n in
                  (match h.dh_frame_env () with Some e -> env := e | None -> ());
                  List.iter (fun s -> Printf.printf "%s\n" s) (h.dh_where ())
                | None -> ())
             | s when is_debug && String.length s >= 7 && String.sub s 0 7 = ":trace " ->
               (match debug_hooks with
                | Some h ->
                  let n = (try int_of_string (String.trim (String.sub s 6 (String.length s - 6)))
                           with _ -> 10) in
                  List.iter (fun s -> Printf.printf "%s\n" s) (h.dh_trace n)
                | None -> ())
             | s when is_debug && String.trim s = ":diff" ->
               (match debug_hooks with
                | Some h ->
                  let baseline = List.map fst e0 in
                  List.iter (fun s -> Printf.printf "%s\n" s) (h.dh_diff 1 baseline)
                | None -> ())
             | s when is_debug && String.length s >= 6 && String.sub s 0 6 = ":diff " ->
               (match debug_hooks with
                | Some h ->
                  let n = (try int_of_string (String.trim (String.sub s 6 (String.length s - 6)))
                           with _ -> 1) in
                  let baseline = List.map fst e0 in
                  List.iter (fun s -> Printf.printf "%s\n" s) (h.dh_diff n baseline)
                | None -> ())
             | s when is_debug && String.length s > 6 && String.sub s 0 6 = ":find " ->
               (match debug_hooks with
                | Some h ->
                  let expr_src = String.trim (String.sub s 6 (String.length s - 6)) in
                  let lexbuf = Lexing.from_string expr_src in
                  (match (try Some (March_parser.Parser.repl_input March_lexer.Lexer.token lexbuf)
                          with _ -> None) with
                   | Some (March_ast.Ast.ReplExpr e) ->
                     let e' = March_desugar.Desugar.desugar_expr e in
                     Printf.printf "Searching...\n%!";
                     let pred frame_env =
                       match March_eval.Eval.eval_expr frame_env e' with
                       | March_eval.Eval.VBool b -> b
                       | _ -> false
                     in
                     (match h.dh_find pred with
                      | None -> Printf.printf "Not found.\n%!"
                      | Some idx ->
                        Printf.printf "Found at frame %d.\n%!" idx;
                        (match h.dh_frame_env () with Some e -> env := e | None -> ());
                        List.iter (fun s -> Printf.printf "%s\n" s) (h.dh_where ()))
                   | _ -> Printf.eprintf "parse error in :find expression\n%!")
                | None -> ())
             | s when is_debug && String.length s > 7 && String.sub s 0 7 = ":watch " ->
               let expr_src = String.trim (String.sub s 7 (String.length s - 7)) in
               Printf.printf "watch: %s (use :watches to list, :unwatch to remove)\n%!" expr_src;
               (* Watches are TUI-only in simple mode — just acknowledge *)
             | s when is_debug && (s = ":watches") ->
               Printf.printf "(watch expressions only available in TUI mode)\n%!"
             | s when is_debug && String.length s > 9 && String.sub s 0 9 = ":unwatch " ->
               Printf.printf "(watch expressions only available in TUI mode)\n%!"
             | s when is_debug && String.length s > 7 && String.sub s 0 7 = ":tsave " ->
               (match debug_hooks with
                | Some h ->
                  let path = String.trim (String.sub s 7 (String.length s - 7)) in
                  (match h.dh_save_trace path with
                   | Ok () -> Printf.printf "Trace saved to %s.\n%!" path
                   | Error msg -> Printf.eprintf "error: %s\n%!" msg)
                | None -> ())
             | s when is_debug && String.length s > 7 && String.sub s 0 7 = ":tload " ->
               (match debug_hooks with
                | Some h ->
                  let path = String.trim (String.sub s 7 (String.length s - 7)) in
                  (match h.dh_load_trace path with
                   | Ok () ->
                     Printf.printf "Trace loaded from %s.\n%!" path;
                     List.iter (fun s -> Printf.printf "%s\n" s) (h.dh_where ())
                   | Error msg -> Printf.eprintf "error: %s\n%!" msg)
                | None -> ())
             | ":env" ->
               let env_baseline = if is_debug then e0 else March_eval.Eval.base_env in
               List.iter (fun (k, _) ->
                 if not (List.mem_assoc k env_baseline) then
                   Printf.printf "  %s\n" k
               ) !env
             | ":help" when is_debug ->
               List.iter (fun s -> Printf.printf "%s\n" s) [
                 "Debug commands:";
                 "  :continue :c        — resume execution";
                 "  :back [n]           — step back n frames (default 1)";
                 "  :forward [n]        — step forward n frames (default 1)";
                 "  :step :s            — step forward 1 frame";
                 "  :goto N             — jump to absolute frame N";
                 "  :trace [n] :t [n]   — show last n trace frames (default 10)";
                 "  :where :w           — show current position";
                 "  :stack :sk          — show call stack";
                 "  :diff [n]           — env diff vs n frames back (default 1)";
                 "  :find <expr>        — find frame where expr is true";
                 "  :replay :r          — replay from current frame with current env";
                 "  :actors             — list actors with message counts";
                 "  :actor <pid> [n]    — show actor message history (jump to msg n)";
                 "  :tsave <path>       — save trace to file";
                 "  :tload <path>       — load trace from file";
                 "  :env                — list bindings";
                 "  :quit :q            — exit program";
                 "";
                 "Any other input is evaluated as a March expression.";
               ]
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
                 (* Intercept h(name) before typecheck — h is a REPL-only doc lookup *)
                 let rec doc_key_of = function
                   | March_ast.Ast.EVar { txt; _ } -> Some txt
                   | March_ast.Ast.ECon ({ txt; _ }, [], _) -> Some txt
                   | March_ast.Ast.EField (inner, { txt = field; _ }, _) ->
                     Option.map (fun prefix -> prefix ^ "." ^ field) (doc_key_of inner)
                   | _ -> None
                 in
                 let handled_as_h = match e with
                   | March_ast.Ast.EApp (March_ast.Ast.EVar { txt = "h"; _ }, [arg], _) ->
                     (match doc_key_of arg with
                      | None ->
                        Printf.printf "h: expected a name or qualified name\n%!"; true
                      | Some key ->
                        let result =
                          match March_eval.Eval.lookup_doc key with
                          | Some s -> s
                          | None   -> Printf.sprintf "No documentation for %s" key
                        in
                        Printf.printf "%s\n%!" result; true)
                   | _ -> false
                 in
                 if not handled_as_h then
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
                      let vs = March_eval.Eval.value_to_string_pretty v in
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
let run_tui ?(stdlib_decls=[]) ?(debug_hooks=None) ?(initial_env=None) () =
  let is_debug = debug_hooks <> None in
  let hist     = History.create ~max_size:(history_size ()) in
  History.load hist (history_path ());
  let type_map = Hashtbl.create 64 in
  let base_e  = March_eval.Eval.base_env in
  let base_tc = March_typecheck.Typecheck.base_env
    (March_errors.Errors.create ()) type_map in
  let (e0, tc0) = match initial_env with
    | Some e -> (e, base_tc)
    | None   -> load_decls_into_env base_e base_tc stdlib_decls
  in
  let env      = ref e0 in
  let tc_env   = ref tc0 in
  let result_h = Result_vars.create () in
  let tui          = Tui.create () in
  let inp          = ref Input.empty in
  let comp         = ref CompOff in
  let hist_lines   = ref [] in
  let prompt_num   = ref 1 in
  let running      = ref true in
  let scroll_offset = ref 0 in
  (* Watch expressions: (display_string * parsed_expr) list *)
  let watch_list   : (string * March_ast.Ast.expr) list ref = ref [] in
  let base_status  =
    if is_debug then "dbg  :continue  :back/:forward  :where  :goto  :diff  :find  :help"
    else "march  :help  Tab  ↑↓: hist  wheel/PgUp: scroll"
  in

  let render_frame () =
    let prompt =
      if is_debug then Printf.sprintf "dbg(%d)> " !prompt_num
      else Printf.sprintf "march(%d)> " !prompt_num
    in
    let input_img = make_input_img !inp.Input.buffer !inp.Input.cursor in
    (* Show accumulated continuation lines above current input *)
    let cont_imgs = List.map (fun line ->
      let pad_str = String.make (String.length prompt) ' ' in
      Notty.I.(Notty.I.string Notty.A.empty pad_str <|> Highlight.highlight line)
    ) (List.rev !inp.Input.multiline_buf) in
    let transcript = !hist_lines @ cont_imgs in
    (* In debug mode use base_e (primitive builtins only) as baseline so user vars
       appear; in normal mode use e0 (base + stdlib) to hide stdlib.
       VClosure/VBuiltin values are filtered separately in user_scope. *)
    let scope_baseline = if is_debug then base_e else e0 in
    let (scope, result_latest) = user_scope !env !tc_env result_h ~baseline_env:scope_baseline in
    let (comp_items, comp_sel) = match !comp with
      | CompOff -> ([], 0)
      | CompOn { items; sel } -> (items, sel)
    in
    let actors = March_eval.Eval.list_actors () in
    (* Scroll indicator at the FRONT so it is visible even on narrow terminals *)
    let status =
      if !scroll_offset > 0
      then Printf.sprintf "[↑%d scrolled  PgDn/wheel↓: return  Shift+drag: select]  %s"
             !scroll_offset base_status
      else base_status
    in
    Tui.render tui Tui.{
      history        = transcript;
      input_line     = input_img;
      prompt;
      scope;
      result_latest;
      status;
      completions    = comp_items;
      completion_sel = comp_sel;
      actors;
      scroll_offset  = !scroll_offset;
    }
  in

  let add_line attr s =
    List.iter (fun line ->
      hist_lines := !hist_lines @ [Notty.I.string attr line]
    ) (String.split_on_char '\n' s)
  in

  (* After any navigation, show :where and update env + watches. *)
  let [@warning "-26"] nav_context h =
    (match h.dh_frame_env () with Some e -> env := e | None -> ());
    let lines = h.dh_where () in
    (match lines with
     | [] -> ()
     | header :: rest ->
       add_line Notty.A.(fg cyan) header;
       List.iter (add_line Notty.A.empty) rest);
    (* Show watch values *)
    List.iter (fun (label, we) ->
      try
        let v = March_eval.Eval.eval_expr !env we in
        add_line Notty.A.(fg magenta)
          (Printf.sprintf "  ◉ %s = %s" label (March_eval.Eval.value_to_string v))
      with _ ->
        add_line Notty.A.(fg magenta) (Printf.sprintf "  ◉ %s = <not in scope>" label)
    ) !watch_list
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
      (* Intercept h(name) before typecheck — h is a REPL-only doc lookup *)
      let rec doc_key_of = function
        | March_ast.Ast.EVar { txt; _ } -> Some txt
        | March_ast.Ast.ECon ({ txt; _ }, [], _) -> Some txt
        | March_ast.Ast.EField (inner, { txt = field; _ }, _) ->
          Option.map (fun prefix -> prefix ^ "." ^ field) (doc_key_of inner)
        | _ -> None
      in
      let handled_as_h = match e with
        | March_ast.Ast.EApp (March_ast.Ast.EVar { txt = "h"; _ }, [arg], _) ->
          (match doc_key_of arg with
           | None ->
             add_line Notty.A.(fg yellow) "h: expected a name or qualified name"; true
           | Some key ->
             let result =
               match March_eval.Eval.lookup_doc key with
               | Some s -> s
               | None   -> Printf.sprintf "No documentation for %s" key
             in
             add_line Notty.A.empty result; true)
        | _ -> false
      in
      if not handled_as_h then
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
           let vs = March_eval.Eval.value_to_string_pretty v in
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

  let dispatch_action action =
    (match action with
     | Input.EOF -> running := false
     | Input.Submit src ->
       comp := CompOff;
       scroll_offset := 0;
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
        | ":quit" | ":q" -> if is_debug then exit 0 else running := false
        | ":continue" | ":c" when is_debug -> running := false
        | ":where" | ":w" when is_debug ->
          (match debug_hooks with
           | Some h ->
             let lines = h.dh_where () in
             (match lines with
              | [] -> ()
              | header :: rest ->
                add_line Notty.A.(fg cyan) header;
                List.iter (add_line Notty.A.empty) rest)
           | None -> ())
        | ":stack" | ":sk" when is_debug ->
          (match debug_hooks with
           | Some h -> List.iter (add_line Notty.A.empty) (h.dh_stack ())
           | None -> ())
        | ":trace" | ":t" when is_debug ->
          (match debug_hooks with
           | Some h -> List.iter (add_line Notty.A.empty) (h.dh_trace 10)
           | None -> ())
        | ":replay" | ":r" when is_debug ->
          (match debug_hooks with
           | Some h ->
             (match h.dh_replay !env with
              | None   -> add_line Notty.A.(fg yellow) "[replay] Done (exception or no frame)."
              | Some v -> add_line Notty.A.(fg green)
                            (Printf.sprintf "[replay] Result: %s"
                               (March_eval.Eval.value_to_string_pretty v)))
           | None -> ())
        | ":actors" when is_debug ->
          (match debug_hooks with
           | Some h -> List.iter (add_line Notty.A.empty) (h.dh_actors ())
           | None -> ())
        | ":watches" when is_debug ->
          if !watch_list = [] then
            add_line Notty.A.(fg yellow) "(no watch expressions)"
          else
            List.iter (fun (label, _) ->
              add_line Notty.A.(fg magenta) (Printf.sprintf "  ◉ %s" label)
            ) !watch_list
        | s when is_debug && String.length s > 7 && String.sub s 0 7 = ":watch " ->
          let expr_src = String.trim (String.sub s 7 (String.length s - 7)) in
          let lexbuf = Lexing.from_string expr_src in
          (match (try Some (March_parser.Parser.repl_input March_lexer.Lexer.token lexbuf)
                  with _ -> None) with
           | Some (March_ast.Ast.ReplExpr e) ->
             let e' = March_desugar.Desugar.desugar_expr e in
             watch_list := !watch_list @ [(expr_src, e')];
             add_line Notty.A.(fg magenta) (Printf.sprintf "Watch added: %s" expr_src)
           | _ -> add_line Notty.A.(fg red) "parse error in watch expression")
        | s when is_debug && String.length s > 9 && String.sub s 0 9 = ":unwatch " ->
          let label = String.trim (String.sub s 9 (String.length s - 9)) in
          let before = List.length !watch_list in
          watch_list := List.filter (fun (l, _) -> l <> label) !watch_list;
          if List.length !watch_list < before then
            add_line Notty.A.(fg magenta) (Printf.sprintf "Removed watch: %s" label)
          else
            add_line Notty.A.(fg yellow) (Printf.sprintf "No watch named: %s" label)
        | s when is_debug && String.length s > 7 && String.sub s 0 7 = ":actor " ->
          (match debug_hooks with
           | Some h ->
             let rest = String.trim (String.sub s 7 (String.length s - 7)) in
             (try
               let parts = List.filter (fun x -> x <> "")
                 (String.split_on_char ' ' rest) in
               let (pid, goto_msg) = match parts with
                 | [p] -> (int_of_string p, None)
                 | [p; m] -> (int_of_string p, Some (int_of_string m))
                 | _ -> raise (Failure "")
               in
               List.iter (add_line Notty.A.empty) (h.dh_actor pid goto_msg);
               (match goto_msg with
                | Some _ -> nav_context h
                | None -> ())
             with _ -> add_line Notty.A.(fg red) "usage: :actor <pid> [msg_n]")
           | None -> ())
        | s when is_debug && String.length s >= 6 && String.sub s 0 5 = ":back" ->
          (match debug_hooks with
           | Some h ->
             let n = (try int_of_string (String.trim (String.sub s 5 (String.length s - 5)))
                      with _ -> 1) in
             let _pos = h.dh_back n in
             nav_context h
           | None -> ())
        | ":step" | ":s" when is_debug ->
          (match debug_hooks with
           | Some h ->
             let _pos = h.dh_forward 1 in
             nav_context h
           | None -> ())
        | s when is_debug && String.length s >= 9 && String.sub s 0 8 = ":forward" ->
          (match debug_hooks with
           | Some h ->
             let n = (try int_of_string (String.trim (String.sub s 8 (String.length s - 8)))
                      with _ -> 1) in
             let _pos = h.dh_forward n in
             nav_context h
           | None -> ())
        | s when is_debug && String.length s >= 6 && String.sub s 0 6 = ":goto " ->
          (match debug_hooks with
           | Some h ->
             let n = (try int_of_string (String.trim (String.sub s 6 (String.length s - 6)))
                      with _ -> 0) in
             let _pos = h.dh_goto n in
             nav_context h
           | None -> ())
        | s when is_debug && String.length s >= 7 && String.sub s 0 7 = ":trace " ->
          (match debug_hooks with
           | Some h ->
             let n = (try int_of_string (String.trim (String.sub s 6 (String.length s - 6)))
                      with _ -> 10) in
             List.iter (add_line Notty.A.empty) (h.dh_trace n)
           | None -> ())
        | s when is_debug && String.trim s = ":diff" ->
          (match debug_hooks with
           | Some h ->
             let baseline = List.map fst e0 in
             List.iter (add_line Notty.A.empty) (h.dh_diff 1 baseline)
           | None -> ())
        | s when is_debug && String.length s >= 6 && String.sub s 0 6 = ":diff " ->
          (match debug_hooks with
           | Some h ->
             let n = (try int_of_string (String.trim (String.sub s 6 (String.length s - 6)))
                      with _ -> 1) in
             let baseline = List.map fst e0 in
             List.iter (add_line Notty.A.empty) (h.dh_diff n baseline)
           | None -> ())
        | s when is_debug && String.length s > 6 && String.sub s 0 6 = ":find " ->
          (match debug_hooks with
           | Some h ->
             let expr_src = String.trim (String.sub s 6 (String.length s - 6)) in
             let lexbuf = Lexing.from_string expr_src in
             (match (try Some (March_parser.Parser.repl_input March_lexer.Lexer.token lexbuf)
                     with _ -> None) with
              | Some (March_ast.Ast.ReplExpr e) ->
                let e' = March_desugar.Desugar.desugar_expr e in
                add_line Notty.A.(fg yellow) "Searching...";
                let pred frame_env =
                  match March_eval.Eval.eval_expr frame_env e' with
                  | March_eval.Eval.VBool b -> b
                  | _ -> false
                in
                (match h.dh_find pred with
                 | None -> add_line Notty.A.(fg yellow) "Not found."
                 | Some idx ->
                   add_line Notty.A.(fg green) (Printf.sprintf "Found at frame %d." idx);
                   nav_context h)
              | _ -> add_line Notty.A.(fg red) "parse error in :find expression")
           | None -> ())
        | s when is_debug && String.length s > 7 && String.sub s 0 7 = ":tsave " ->
          (match debug_hooks with
           | Some h ->
             let path = String.trim (String.sub s 7 (String.length s - 7)) in
             (match h.dh_save_trace path with
              | Ok () ->
                add_line Notty.A.(fg green) (Printf.sprintf "Trace saved to %s." path)
              | Error msg ->
                add_line Notty.A.(fg red) (Printf.sprintf "error: %s" msg))
           | None -> ())
        | s when is_debug && String.length s > 7 && String.sub s 0 7 = ":tload " ->
          (match debug_hooks with
           | Some h ->
             let path = String.trim (String.sub s 7 (String.length s - 7)) in
             (match h.dh_load_trace path with
              | Ok () ->
                add_line Notty.A.(fg green) (Printf.sprintf "Trace loaded from %s." path);
                nav_context h
              | Error msg ->
                add_line Notty.A.(fg red) (Printf.sprintf "error: %s" msg))
           | None -> ())
        | ":env" ->
          (* In debug mode filter by e0 (the breakpoint env) so we only show
             bindings added in this REPL session, not the entire program state.
             The scope panel already shows all program variables. *)
          let env_baseline = if is_debug then e0 else March_eval.Eval.base_env in
          let lines = List.filter_map (fun (k, v) ->
            if List.mem_assoc k env_baseline then None
            else Some (Printf.sprintf "  %s = %s" k
              (March_eval.Eval.value_to_string v))
          ) !env in
          if lines = [] then
            add_line Notty.A.(fg yellow)
              (if is_debug then "(no new bindings in this debug session)"
               else "(no user bindings)")
          else
            List.iter (add_line Notty.A.empty) lines
        | ":clear" -> hist_lines := []
        | ":reset" when not is_debug ->
          let (e', tc') = load_decls_into_env March_eval.Eval.base_env
            (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map)
            stdlib_decls in
          env := e'; tc_env := tc';
          hist_lines := []
        | ":help" ->
          if is_debug then
            List.iter (add_line Notty.A.empty) [
              "Debug commands:";
              "  :continue :c        — resume execution";
              "  :back [n]           — step back n frames (default 1)";
              "  :forward [n]        — step forward n frames (default 1)";
              "  :step :s            — step forward 1 frame";
              "  :goto N             — jump to absolute frame N";
              "  :trace [n] :t [n]   — show last n trace frames (default 10)";
              "  :where :w           — show current position";
              "  :stack :sk          — show call stack";
              "  :diff [n]           — env diff vs n frames back (default 1)";
              "  :find <expr>        — find frame where expr is true";
              "  :replay :r          — replay from current frame with current env";
              "  :watch <expr>       — add watch expression";
              "  :unwatch <expr>     — remove watch expression";
              "  :watches            — list watch expressions";
              "  :actors             — list actors with message counts";
              "  :actor <pid> [n]    — show actor message history (jump to msg n)";
              "  :tsave <path>       — save trace to .mtr file";
              "  :tload <path>       — load trace from .mtr file";
              "  :env                — list bindings";
              "  :quit :q            — exit program";
              "";
              "Any other input is evaluated as a March expression.";
            ]
          else
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
            "      PgUp/PgDn or mouse wheel: scroll history";
            "      Ctrl+A/E: home/end | Ctrl+W: kill word | Ctrl+Y: yank";
            "Copy: Shift+drag to select, then Cmd+C (NOT Ctrl+C) to copy";
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
       let scope = List.map (fun (name, _v) -> (name, "")) !env in
       let items = Complete.complete prefix scope in
       (match items with
       | [] -> ()
       | [single] ->
         inp := Input.complete_replace !inp single;
         render_frame ()
       | multiple ->
         comp := CompOn { items = multiple; sel = 0 };
         render_frame ())
     | Input.HistorySearch -> () (* Phase 2 *)
    )
  in

  (* Show :where immediately on entry so the user knows where they are. *)
  (match debug_hooks with
   | Some h -> nav_context h
   | None   -> ());
  render_frame ();

  while !running do
    (try match Tui.next_event tui with
     | `End -> running := false
     | `Resize _ -> render_frame ()
     | `Scroll `Up ->
       scroll_offset := !scroll_offset + 3;
       render_frame ()
     | `Scroll `Down ->
       scroll_offset := max 0 (!scroll_offset - 3);
       render_frame ()
     | `Key (`Page `Up, _) ->
       let (_, h) = Tui.size tui in
       scroll_offset := !scroll_offset + (h - 2);
       render_frame ()
     | `Key (`Page `Down, _) ->
       let (_, h) = Tui.size tui in
       scroll_offset := max 0 (!scroll_offset - (h - 2));
       render_frame ()
     | `Key key ->
       (match !comp with
        | CompOn { items; sel } ->
          let n = List.length items in
          (match key with
          | (`Tab, _) | (`Arrow `Down, _) ->
            comp := CompOn { items; sel = (sel + 1) mod n };
            render_frame ()
          | (`Arrow `Up, _) ->
            comp := CompOn { items; sel = (sel - 1 + n) mod n };
            render_frame ()
          | (`Enter, _) ->
            (* sel is always in [0, n) by the mod arithmetic in Tab/Up/Down *)
            let chosen = List.nth items sel in
            inp := Input.complete_replace !inp chosen;
            comp := CompOff;
            render_frame ()
          | (`Escape, _) ->
            comp := CompOff;
            render_frame ()
          | _ ->
            comp := CompOff;
            let (inp', action) = Input.handle_key !inp key in
            inp := inp';
            dispatch_action action)
        | CompOff ->
          let (inp', action) = Input.handle_key !inp key in
          inp := inp';
          dispatch_action action)
     with exn ->
       add_line Notty.A.(fg red)
         (Printf.sprintf "internal error: %s" (Printexc.to_string exn));
       render_frame ())
  done;
  History.save hist (history_path ());
  Tui.close tui

let run ?(stdlib_decls = []) ?(debug_hooks = None) ?(initial_env = None) () =
  if Unix.isatty Unix.stdin && Unix.isatty Unix.stdout
  then run_tui ~stdlib_decls ~debug_hooks ~initial_env ()
  else run_simple ~stdlib_decls ~debug_hooks ~initial_env ()
