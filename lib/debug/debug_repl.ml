(** March debug REPL session.

    Called by the [on_dbg] callback when [dbg()] is hit.
    Launches the normal March REPL (TUI or simple, depending on terminal)
    with the breakpoint env pre-loaded and debug navigation commands added. *)

module Eval = March_eval.Eval

(** Build the [debug_hooks] record wiring Trace/Replay functions into the REPL. *)
let make_hooks (ctx : Eval.debug_ctx) : March_repl.Repl.debug_hooks =
  { March_repl.Repl.
    dh_back       = (fun n -> Trace.back ctx n);
    dh_forward    = (fun n -> Trace.forward ctx n);
    dh_goto       = (fun n -> Trace.goto ctx n);
    dh_where      = (fun () -> Trace.show_where ctx);
    dh_stack      = (fun () -> Trace.show_stack ctx);
    dh_trace      = (fun n  -> Trace.show_trace ctx n);
    dh_diff       = (fun n baseline -> Trace.diff_frames ctx n baseline);
    dh_find       = (fun pred -> Trace.find_frame ctx pred);
    dh_replay     = (fun env -> Replay.replay_from ctx env);
    dh_frame_env  = (fun () ->
      match Trace.current_frame ctx with
      | None   -> None
      | Some f -> Some f.Eval.tf_env);
    dh_actors     = (fun () -> Trace.actors_summary ctx);
    dh_actor      = (fun pid goto_msg -> Trace.actor_history ctx pid goto_msg);
    dh_save_trace = (fun path -> Trace.save_trace ctx path);
    dh_load_trace = (fun path -> Trace.load_trace ctx path);
  }

(** Main debug REPL entry point. Called as the [on_dbg] callback. *)
let run_session (ctx : Eval.debug_ctx) (initial_env : Eval.env) : unit =
  let location =
    match Trace.current_frame ctx with
    | None   -> "<unknown>"
    | Some f ->
      let sp = f.Eval.tf_span in
      Printf.sprintf "%s:%d:%d"
        sp.March_ast.Ast.file sp.March_ast.Ast.start_line
        sp.March_ast.Ast.start_col
  in
  Printf.eprintf "\n[debug] Breakpoint hit at %s\n%!" location;
  let hooks = make_hooks ctx in
  March_repl.Repl.run
    ~debug_hooks:(Some hooks)
    ~initial_env:(Some initial_env)
    ()
