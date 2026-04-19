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
  I.(Highlight.highlight left
     <|> string A.(bg white ++ fg black) cur_c
     <|> Highlight.highlight right)

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
  let baseline_set = Hashtbl.create 64 in
  List.iter (fun (name, _) -> Hashtbl.replace baseline_set name ()) baseline_env;
  let seen = Hashtbl.create 16 in
  let scope = List.filter_map (fun (name, v) ->
    if Hashtbl.mem baseline_set name
    || name = "v"
    || (String.length name > 0 && name.[0] = '_')
    || Hashtbl.mem seen name
    || (match v with March_eval.Eval.VBuiltin (n, _) ->
          let is_rec = String.length n >= 5 && String.sub n 0 5 = "<rec:" in
          not is_rec
        | _ -> false)
    then None
    else begin
      Hashtbl.add seen name ();
      let vs = March_eval.Eval.value_to_string v in
      let ty_str =
        match March_typecheck.Typecheck.StrMap.find_opt name tc_env.March_typecheck.Typecheck.vars with
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

(* Load a list of pre-desugared declarations into the eval/typecheck envs silently. *)
(** Pre-register all DType definitions found inside stdlib DMod declarations.
    Without this pass, circular type dependencies between stdlib modules
    (e.g. http_server.march uses WsSocket from websocket.march, and vice versa)
    cause both modules to fail incremental typecheck and silently drop all their
    runtime bindings from the REPL environment.  By registering every variant
    type and its constructors up-front, each subsequent check_decl call sees a
    complete type environment regardless of module load order. *)
let preregister_stdlib_types tc_env (stdlib_decls : March_ast.Ast.decl list) =
  let open March_ast.Ast in
  let open March_typecheck.Typecheck in
  let rec add_from env decls =
    List.fold_left (fun env d ->
      match d with
      | DMod (_, _, inner, _) -> add_from env inner
      | DType (_, name, params, TDVariant variants, _) ->
        let arity      = List.length params in
        let param_names = List.map (fun (p : name) -> p.txt) params in
        let env1 = { env with types = StrMap.add name.txt arity env.types } in
        List.fold_left (fun e (v : variant) ->
          let ci = { ci_type = name.txt; ci_params = param_names;
                     ci_arg_tys = v.var_args; ci_vis = v.var_vis } in
          { e with ctors = March_typecheck.Typecheck.add_ctor v.var_name.txt ci e.ctors }
        ) env1 variants
      | DType (_, name, params, _, _) ->
        let arity = List.length params in
        { env with types = StrMap.add name.txt arity env.types }
      | _ -> env
    ) env decls
  in
  add_from tc_env stdlib_decls

let load_decls_into_env env tc_env decls =
  List.fold_left (fun (e, tc) decl ->
    let ctx = March_errors.Errors.create () in
    let tc' = March_typecheck.Typecheck.check_decl { tc with errors = ctx } decl in
    (* Always use tc' even when typecheck produces errors: stdlib modules that
       call unregistered C builtins (http_server_listen, ws_recv, etc.) fail
       the check, but tc' still contains the public function types that were
       successfully inferred (e.g. HttpServer.new, HttpServer.plug).  Falling
       back to tc on error would silently drop all of those from the REPL env. *)
    (* Always eval_decl even if typecheck fails: stdlib is known-good, and the
       eval path is purely structural (no type info needed at runtime).  This
       ensures modules with circular type deps (e.g. HttpServer ↔ WebSocket)
       still populate the eval environment and remain callable in the REPL. *)
    let e' = (try March_eval.Eval.eval_decl e decl with _ -> e) in
    (e', { tc' with errors = March_errors.Errors.create () })
  ) (env, tc_env) decls

(** Run only eval_decl for each stdlib module (skip typechecking).
    Used when the typecheck env is loaded from cache. *)
let eval_decls_only env decls =
  List.fold_left (fun e decl ->
    (try March_eval.Eval.eval_decl e decl with _ -> e)
  ) env decls

(** Try to load a cached typecheck env.  Returns Some tc_env on hit. *)
let load_cached_tc_env ~content_hash ~type_map =
  let home = (try Sys.getenv "HOME" with Not_found -> ".") in
  let cache_dir = Filename.concat home ".cache/march" in
  let short_hash = String.sub content_hash 0 16 in
  let cache_path = Filename.concat cache_dir
    ("stdlib_tcenv_" ^ short_hash ^ ".bin") in
  try
    if Sys.file_exists cache_path then begin
      let ic = open_in_bin cache_path in
      let (cached_tc : March_typecheck.Typecheck.env) = Marshal.from_channel ic in
      let (cached_tm : (March_ast.Ast.span * March_typecheck.Typecheck.ty) list) =
        Marshal.from_channel ic in
      close_in ic;
      (* Restore type_map entries into the shared hashtable *)
      List.iter (fun (k, v) -> Hashtbl.replace type_map k v) cached_tm;
      (* Replace errors and type_map with fresh/live ones *)
      Some { cached_tc with
        March_typecheck.Typecheck.errors = March_errors.Errors.create ();
        type_map }
    end else None
  with _ -> None

(** Save the typecheck env to cache. *)
let save_cached_tc_env ~content_hash tc_env =
  let home = (try Sys.getenv "HOME" with Not_found -> ".") in
  let cache_dir = Filename.concat home ".cache/march" in
  let short_hash = String.sub content_hash 0 16 in
  let cache_path = Filename.concat cache_dir
    ("stdlib_tcenv_" ^ short_hash ^ ".bin") in
  (try
    (try Unix.mkdir cache_dir 0o755
     with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
    let oc = open_out_bin cache_path in
    Marshal.to_channel oc tc_env [];
    (* Save type_map as association list (Hashtbl isn't stable across runs) *)
    let tm_list = Hashtbl.fold (fun k v acc -> (k, v) :: acc)
      tc_env.March_typecheck.Typecheck.type_map [] in
    Marshal.to_channel oc tm_list [];
    close_out oc
  with _ -> ())

(** Compute a content hash of stdlib decls using MD5 of their marshalled form.
    Stable within a binary build — changes whenever stdlib source changes. *)
let stdlib_content_hash (stdlib_decls : March_ast.Ast.decl list) : string =
  let bytes = Marshal.to_string stdlib_decls [] in
  Digest.to_hex (Digest.string bytes)

(** Precompile the stdlib to a cached .so via the JIT context.
    Uses a source-level content hash so cache hits skip TIR lowering entirely.
    Non-fatal: any error is silently swallowed so the REPL always starts. *)
let maybe_precompile_stdlib jit_ctx ~stdlib_decls
    ~(type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t) =
  match jit_ctx with
  | None -> ()
  | Some jit ->
    let content_hash = stdlib_content_hash stdlib_decls in
    March_jit.Repl_jit.precompile_stdlib jit
      ~content_hash ~stdlib_decls ~type_map

(** Wrap a REPL expression in a synthetic module for TIR lowering.
    The expression becomes the body of fn main() -> expr.
    Does NOT include stdlib_decls — the JIT uses incremental typecheck
    and passes stdlib_context to lower_module separately. *)
let wrap_expr_as_module
    (e : March_ast.Ast.expr) : March_ast.Ast.module_ =
  let s = March_ast.Ast.dummy_span in
  let main_clause = {
    March_ast.Ast.fc_params = [];
    fc_guard = None;
    fc_body = e;
    fc_span = s;
  } in
  let main_def = {
    March_ast.Ast.fn_name = { txt = "main"; span = s };
    fn_vis = March_ast.Ast.Public;
    fn_doc = None;
    fn_attrs = [];
    fn_ret_ty = None;
    fn_clauses = [main_clause];
  } in
  let main_decl = March_ast.Ast.DFn (main_def, s) in
  { March_ast.Ast.mod_name = { txt = "Repl"; span = s };
    mod_decls = [main_decl] }

(** Wrap a REPL declaration in a synthetic module for TIR lowering. *)
let wrap_decl_as_module
    (d : March_ast.Ast.decl) : March_ast.Ast.module_ =
  let s = March_ast.Ast.dummy_span in
  { March_ast.Ast.mod_name = { txt = "Repl"; span = s };
    mod_decls = [d] }

(** Non-TUI fallback REPL. *)
let run_simple ?(stdlib_decls=[]) ?(debug_hooks=None) ?(initial_env=None) ?(jit_ctx=(None : March_jit.Repl_jit.t option)) ?(preload_file=None) () =
  let use_jit = jit_ctx <> None &&
    Sys.getenv_opt "MARCH_REPL_INTERP" = None in
  let jit_ctx = if use_jit then jit_ctx else None in
  let is_debug = debug_hooks <> None in
  let scroll_mode = Sys.getenv_opt "MARCH_SCROLL_MODE" = Some "1" in
  (* MARCH_SCROLL_SENTINEL overrides the default sentinel so user output that
     happens to contain "__SCROLL_DONE__" cannot corrupt the sentinel counter. *)
  let scroll_sentinel =
    match Sys.getenv_opt "MARCH_SCROLL_SENTINEL" with
    | Some s when s <> "" -> s
    | _ -> "__SCROLL_DONE__"
  in
  if is_debug then
    Printf.printf "\n[debug] Breakpoint hit — :continue to resume, :help for commands\n%!"
  else if not scroll_mode then
    Printf.printf "March REPL — :quit to exit, :env to list bindings\n%!";
  let type_map = Hashtbl.create 64 in
  let base_e  = March_eval.Eval.task_builtins @ March_eval.Eval.base_env in
  let base_tc = March_typecheck.Typecheck.base_env
    (March_errors.Errors.create ()) type_map in
  let t_s0 = Unix.gettimeofday () in
  let content_hash = stdlib_content_hash stdlib_decls in
  let (e0, tc0) = match initial_env with
    | Some e -> (e, base_tc)
    | None   ->
      (match load_cached_tc_env ~content_hash ~type_map with
       | Some cached_tc ->
         let t_s1 = Unix.gettimeofday () in
         Printf.eprintf "[timing] tc_env cache hit: %.3fs\n%!" (t_s1 -. t_s0);
         let e0 = eval_decls_only base_e stdlib_decls in
         let t_s2 = Unix.gettimeofday () in
         Printf.eprintf "[timing] eval_decls: %.3fs\n%!" (t_s2 -. t_s1);
         (e0, cached_tc)
       | None ->
         let tc_pre = preregister_stdlib_types base_tc stdlib_decls in
         let t_s1 = Unix.gettimeofday () in
         Printf.eprintf "[timing] preregister: %.3fs\n%!" (t_s1 -. t_s0);
         let (e0, tc0) = load_decls_into_env base_e tc_pre stdlib_decls in
         let t_s2 = Unix.gettimeofday () in
         Printf.eprintf "[timing] load_decls: %.3fs\n%!" (t_s2 -. t_s1);
         save_cached_tc_env ~content_hash tc0;
         (e0, tc0))
  in
  let t_s3 = Unix.gettimeofday () in
  maybe_precompile_stdlib jit_ctx ~stdlib_decls ~type_map;
  let t_s4 = Unix.gettimeofday () in
  Printf.eprintf "[timing] precompile: %.3fs\n%!" (t_s4 -. t_s3);
  let env         = ref e0 in
  let tc_env      = ref tc0 in
  let result_h    = Result_vars.create () in
  let hist        = History.create ~max_size:(history_size ()) in
  History.load hist (history_path ());
  let prompt_num  = ref 1 in
  let running     = ref true in
  let buf         = Buffer.create 64 in
  let first_line  = ref true in
  let show_type   = ref false in
  let loaded_file : string option ref = ref None in

  let print_diag (d : March_errors.Errors.diagnostic) =
    let src = Buffer.contents buf in
    Printf.eprintf "%s\n\n%!"
      (March_errors.Errors.render_diagnostic ~src d)
  in

  (* Load a file path into env/tc_env, printing any errors to stderr. *)
  let load_decls_list path all_decls =
    List.iter (fun decl ->
      let input_ctx = March_errors.Errors.create () in
      let input_tc  = { !tc_env with errors = input_ctx } in
      let new_tc    = March_typecheck.Typecheck.check_decl input_tc decl in
      if not (March_errors.Errors.has_errors input_ctx) then begin
        (try
          env    := March_eval.Eval.eval_decl !env decl;
          tc_env := { new_tc with errors = March_errors.Errors.create () }
        with exn ->
          Printf.eprintf "runtime error loading %s: %s\n%!" path (Printexc.to_string exn))
      end else
        List.iter print_diag (March_errors.Errors.sorted input_ctx)
    ) all_decls
  in

  let parse_file path =
    match (try
      let ic = open_in path in
      let n  = in_channel_length ic in
      let b  = Bytes.create n in
      really_input ic b 0 n;
      close_in ic;
      Some (Bytes.to_string b)
    with Sys_error msg -> Printf.eprintf "error: cannot open %s: %s\n%!" path msg; None) with
    | None -> None
    | Some file_src ->
      let lexbuf = Lexing.from_string file_src in
      (match (try
        let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
        Some (March_desugar.Desugar.desugar_module m)
      with exn ->
        Printf.eprintf "parse error in %s: %s\n%!" path (Printexc.to_string exn); None) with
      | None -> None
      | Some desugared ->
        let (import_errs, extra_decls) =
          March_resolver.Resolver.resolve_imports ~source_file:path desugared in
        List.iter (fun (_, span, msg) ->
          Printf.eprintf "%s:%d: import error: %s\n%!"
            span.March_ast.Ast.file span.March_ast.Ast.start_line msg
        ) import_errs;
        Some (desugared, extra_decls))
  in

  (* :load — wraps in a DMod so names are qualified (e.g. DbTest.main). *)
  let do_load_file path =
    match parse_file path with
    | None -> ()
    | Some (desugared, extra_decls) ->
      let file_mod =
        March_ast.Ast.DMod (
          desugared.March_ast.Ast.mod_name,
          March_ast.Ast.Public,
          desugared.March_ast.Ast.mod_decls,
          March_ast.Ast.dummy_span)
      in
      load_decls_list path (extra_decls @ [file_mod]);
      Printf.printf "loaded %s\n%!" path;
      loaded_file := Some path
  in

  (* Preload (forge interactive) — processes flat so top-level imports fire,
     opening imported namespaces (Connection, Config, etc.) into REPL scope. *)
  let do_preload_file path =
    match parse_file path with
    | None -> ()
    | Some (desugared, extra_decls) ->
      load_decls_list path (extra_decls @ desugared.March_ast.Ast.mod_decls);
      Printf.printf "loaded %s\n%!" path;
      loaded_file := Some path
  in

  (* Preload a file before entering the loop (e.g. from forge interactive). *)
  Option.iter do_preload_file preload_file;

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
                  (match (try Some (March_parser.Parser.repl_input (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
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
             | ":set +t" ->
               show_type := true;
               Printf.printf "type display: on  (`:set -t` to disable)\n%!"
             | ":set -t" ->
               show_type := false;
               Printf.printf "type display: off\n%!"
             | ":env" ->
               let env_baseline = if is_debug then e0 else March_eval.Eval.base_env in
               List.iter (fun (k, _) ->
                 if not (List.mem_assoc k env_baseline) then
                   Printf.printf "  %s\n" k
               ) !env
             | ":clear" ->
               (* Clear terminal screen and reprint prompt on next iteration *)
               Printf.printf "\027[2J\027[H%!"
             | ":reset" when not is_debug ->
               let base_tc' = March_typecheck.Typecheck.base_env
                 (March_errors.Errors.create ()) type_map in
               let tc_pre' = preregister_stdlib_types base_tc' stdlib_decls in
               let base_e' = March_eval.Eval.task_builtins @ March_eval.Eval.base_env in
               let (e', tc') = load_decls_into_env base_e' tc_pre' stdlib_decls in
               env    := e';
               tc_env := tc';
               Printf.printf "REPL state reset.\n%!"
             | ":help" ->
               if is_debug then
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
               else
               List.iter (fun s -> Printf.printf "%s\n" s) [
                 "Commands:";
                 "  :quit :q            — exit";
                 "  :env                — list bindings in scope";
                 "  :type <expr>        — show inferred type without evaluating";
                 "  :inspect <expr>     — show type and value";
                 "  :doc <name>         — show documentation for a name";
                 "  :load <file>        — load a .march source file";
                 "  :reload             — reload the last :load-ed file";
                 "  :clear              — clear screen";
                 "  :reset              — reset all bindings to stdlib baseline";
                 "  :set +t             — show inferred type after each expression";
                 "  :set -t             — hide inferred type (default)";
                 "  :help               — this message";
                 "";
                 "Aliases: :i = :inspect  :t = :type (outside debug mode)";
               ]
             | src when String.length src > 5 && String.sub src 0 5 = ":load" && not is_debug ->
               let path = String.trim (String.sub src 5 (String.length src - 5)) in
               if path = "" then
                 Printf.eprintf "usage: :load <file>\n%!"
               else
                 do_load_file path
             | ":reload" when not is_debug ->
               (match !loaded_file with
                | None -> Printf.printf "Nothing to reload (use :load <file> first).\n%!"
                | Some path ->
                  (* Reset to stdlib baseline then reload *)
                  let base_tc' = March_typecheck.Typecheck.base_env
                    (March_errors.Errors.create ()) type_map in
                  let tc_pre' = preregister_stdlib_types base_tc' stdlib_decls in
                  let base_e' = March_eval.Eval.task_builtins @ March_eval.Eval.base_env in
                  let (e', tc') = load_decls_into_env base_e' tc_pre' stdlib_decls in
                  env    := e';
                  tc_env := tc';
                  do_load_file path;
                  Printf.printf "reloaded %s\n%!" path)
             | ":reload" when is_debug ->
               Printf.printf "Nothing to reload.\n%!"
             | src when String.length src > 5 && String.sub src 0 5 = ":type" ->
               let expr_src = String.trim (String.sub src 5 (String.length src - 5)) in
               if expr_src = "" then
                 Printf.eprintf "usage: :type <expr>\n%!"
               else begin
                 let lexbuf = Lexing.from_string expr_src in
                 (match (try Some (March_parser.Parser.repl_input (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
                         with _ -> None) with
                 | Some (March_ast.Ast.ReplExpr e) ->
                   let e' = March_desugar.Desugar.desugar_expr e in
                   let input_ctx = March_errors.Errors.create () in
                   let input_tc  = { !tc_env with errors = input_ctx } in
                   let inferred  = March_typecheck.Typecheck.infer_expr input_tc e' in
                   let ty_str    = March_typecheck.Typecheck.pp_ty
                     (March_typecheck.Typecheck.repr inferred) in
                   if March_errors.Errors.has_errors input_ctx then
                     Printf.eprintf "type error\n%!"
                   else
                     Printf.printf "- : %s\n%!" ty_str
                 | _ -> Printf.eprintf "parse error\n%!")
               end
             | src when (let t = String.trim src in
                          (String.length t >= 8 && String.sub t 0 8 = ":inspect")
                          || (String.length t >= 2 && String.sub t 0 2 = ":i"
                              && (String.length t = 2 || t.[2] = ' '))) && not is_debug ->
               (* :inspect expr  /  :i expr — show type and value *)
               let prefix_len =
                 let t = String.trim src in
                 if String.length t >= 8 && String.sub t 0 8 = ":inspect" then 8
                 else 2
               in
               let expr_src = String.trim (String.sub (String.trim src) prefix_len
                 (String.length (String.trim src) - prefix_len)) in
               if expr_src = "" then
                 Printf.eprintf "usage: :inspect <expr>\n%!"
               else begin
                 let lexbuf = Lexing.from_string expr_src in
                 (match (try Some (March_parser.Parser.repl_input (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
                         with _ -> None) with
                 | Some (March_ast.Ast.ReplExpr e) ->
                   let e' = March_desugar.Desugar.desugar_expr e in
                   let input_ctx = March_errors.Errors.create () in
                   let input_tc  = { !tc_env with errors = input_ctx } in
                   let inferred  = March_typecheck.Typecheck.infer_expr input_tc e' in
                   let ty_str    = March_typecheck.Typecheck.pp_ty
                     (March_typecheck.Typecheck.repr inferred) in
                   if March_errors.Errors.has_errors input_ctx then
                     Printf.eprintf "type error\n%!"
                   else begin
                     (March_eval.Eval.clear_march_stack ();
                      try
                        let v   = March_eval.Eval.eval_expr !env e' in
                        let vs  = March_eval.Eval.value_to_string_pretty v in
                        Printf.printf "type  : %s\nvalue : %s\n%!" ty_str vs
                      with
                      | March_eval.Eval.Eval_error msg ->
                        March_eval.Eval.clear_march_stack ();
                        Printf.eprintf "runtime error: %s\n%!" msg
                      | exn ->
                        March_eval.Eval.clear_march_stack ();
                        Printf.eprintf "error: %s\n%!" (Printexc.to_string exn))
                   end
                 | _ -> Printf.eprintf "parse error\n%!")
               end
             | src when String.length src > 4 && String.sub src 0 4 = ":doc" ->
               let name = String.trim (String.sub src 4 (String.length src - 4)) in
               if name = "" then
                 Printf.eprintf "usage: :doc <name>\n%!"
               else begin
                 match March_eval.Eval.lookup_doc name with
                 | Some s -> Printf.printf "%s\n%!" s
                 | None   -> Printf.printf "No documentation found for %s\n%!" name
               end
             | src when String.trim src = "" -> ()
             | src ->
               let lexbuf = Lexing.from_string src in
               (match (try Some (March_parser.Parser.repl_input (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
                       with
                       | March_errors.Errors.ParseError (msg, hint, _) ->
                         let rendered = March_errors.Errors.render_parse_error ~src ?hint ~msg lexbuf in
                         Printf.eprintf "%s\n%!" rendered;
                         None
                       | March_parser.Parser.Error ->
                         let rendered = March_errors.Errors.render_parse_error ~src ~msg:"I got stuck here:" lexbuf in
                         Printf.eprintf "%s\n%!" rendered;
                         None) with
               | None | Some March_ast.Ast.ReplEOF -> ()
               | Some (March_ast.Ast.ReplDecl d) ->
                 let d' = March_desugar.Desugar.desugar_decl d in
                 (* Auto-load user modules on `import Foo` / `import Foo.{bar}` etc.
                    Synthesise a dummy module containing just this declaration, run
                    resolve_imports (which finds Foo in the CWD), then process the
                    resulting DMod stubs before the DUse itself. *)
                 (match d' with
                  | March_ast.Ast.DUse _ | March_ast.Ast.DAlias _ ->
                    (* Search CWD and common subdirectories for .march source files. *)
                    let cwd = Sys.getcwd () in
                    let env_lib_paths =
                      match Sys.getenv_opt "MARCH_LIB_PATH" with
                      | None -> []
                      | Some s -> List.filter (fun d -> d <> "") (String.split_on_char ':' s)
                    in
                    let candidates = [cwd; Filename.concat cwd "src"; Filename.concat cwd "lib"] @ env_lib_paths in
                    let search_dir =
                      let mod_name = match d' with
                        | March_ast.Ast.DUse (ud, _) ->
                          (match ud.March_ast.Ast.use_path with
                           | n :: _ -> Some n.March_ast.Ast.txt | [] -> None)
                        | March_ast.Ast.DAlias (ad, _) ->
                          (match ad.March_ast.Ast.alias_path with
                           | n :: _ -> Some n.March_ast.Ast.txt | [] -> None)
                        | _ -> None
                      in
                      match mod_name with
                      | None -> cwd
                      | Some mname ->
                        let fname = March_resolver.Resolver.module_name_to_filename mname in
                        match List.find_opt (fun d -> Sys.file_exists (Filename.concat d fname)) candidates with
                        | Some d -> d
                        | None   -> cwd
                    in
                    let dummy_src = Filename.concat search_dir "_repl_.march" in
                    let dummy_mod = { March_ast.Ast.mod_name  = { txt = "Repl"; span = March_ast.Ast.dummy_span }
                                    ; mod_decls = [d'] } in
                    let (_, extra_decls) =
                      March_resolver.Resolver.resolve_imports ~source_file:dummy_src dummy_mod in
                    List.iter (fun decl ->
                      let ictx = March_errors.Errors.create () in
                      let itc  = { !tc_env with errors = ictx } in
                      let ntc  = March_typecheck.Typecheck.check_decl itc decl in
                      if not (March_errors.Errors.has_errors ictx) then begin
                        (try
                           env    := March_eval.Eval.eval_decl !env decl;
                           tc_env := { ntc with errors = March_errors.Errors.create () }
                         with _ -> ())
                      end
                    ) extra_decls
                  | _ -> ());
                 let input_ctx = March_errors.Errors.create () in
                 let input_tc  = { !tc_env with errors = input_ctx } in
                 let new_tc    = March_typecheck.Typecheck.check_decl input_tc d' in
                 let tc_ok = not (March_errors.Errors.has_errors input_ctx) in
                 (* In debug mode, skip typecheck gate — the eval env has
                    bindings the typechecker doesn't know about. *)
                 if not is_debug then
                   List.iter print_diag (March_errors.Errors.sorted input_ctx);
                 if tc_ok || is_debug then
                   (try
                      (match jit_ctx with
                      | Some jit when (match d' with March_ast.Ast.DFn _ -> true | _ -> false) ->
                        let bind_name = match d' with
                          | March_ast.Ast.DFn (def, _) -> def.fn_name.txt
                          | _ -> assert false
                        in
                        let m = wrap_decl_as_module d' in
                        March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:true ~bind_name m;
                        if tc_ok then
                          tc_env := { new_tc with errors = March_errors.Errors.create () };
                        Printf.printf "val %s = <fn>\n%!" bind_name
                      | Some jit when (match d' with
                          | March_ast.Ast.DLet (_, b, _) ->
                            (match b.bind_pat with March_ast.Ast.PatVar _ -> true | _ -> false)
                          | _ -> false) ->
                        (* JIT path for simple let bindings: compile value to a global
                           so later expressions can reference the name across module boundaries. *)
                        let bind_name = match d' with
                          | March_ast.Ast.DLet (_, b, _) ->
                            (match b.bind_pat with March_ast.Ast.PatVar n -> n.txt | _ -> assert false)
                          | _ -> assert false
                        in
                        let bind_expr = match d' with
                          | March_ast.Ast.DLet (_, b, _) -> b.bind_expr
                          | _ -> assert false
                        in
                        let m = wrap_expr_as_module bind_expr in
                        (try March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m
                         with Failure _ -> ());
                        (* Always update interpreter env (source of truth for value display) *)
                        env := March_eval.Eval.eval_decl !env d';
                        if tc_ok then
                          tc_env := { new_tc with errors = March_errors.Errors.create () };
                        let vstr = match List.assoc_opt bind_name !env with
                          | Some v -> March_eval.Eval.value_to_string v
                          | None -> "?"
                        in
                        Printf.printf "val %s = %s\n%!" bind_name vstr
                      | _ ->
                        env := March_eval.Eval.eval_decl !env d';
                        if tc_ok then
                          tc_env := { new_tc with errors = March_errors.Errors.create () };
                        (match d' with
                         | March_ast.Ast.DFn (def, _) ->
                           Printf.printf "val %s = <fn>\n%!" def.fn_name.txt
                         | March_ast.Ast.DLet (_, b, _) ->
                           (match b.bind_pat with
                            | March_ast.Ast.PatVar n ->
                              let vstr = match List.assoc_opt n.txt !env with
                                | Some v -> March_eval.Eval.value_to_string v
                                | None -> "?"
                              in
                              Printf.printf "val %s = %s\n%!" n.txt vstr
                            | _ -> Printf.printf "val _ = ...\n%!")
                         | March_ast.Ast.DActor (_, name, _, _) ->
                           Printf.printf "val %s = <actor>\n%!" name.txt
                         | _ -> ()))
                    with
                    | March_eval.Eval.Eval_error msg ->
                      March_eval.Eval.clear_march_stack ();
                      Printf.eprintf "runtime error: %s\n%!" msg
                    | March_eval.Eval.Match_failure msg ->
                      March_eval.Eval.clear_march_stack ();
                      Printf.eprintf "match failure: %s\n%!" msg
                    | Failure msg ->
                      Printf.eprintf "jit error: %s\n%!" msg
                    | exn ->
                      March_eval.Eval.clear_march_stack ();
                      Printf.eprintf "error: %s\n%!" (Printexc.to_string exn))
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
                 let tc_ok = not (March_errors.Errors.has_errors input_ctx) in
                 if not is_debug then
                   List.iter print_diag (March_errors.Errors.sorted input_ctx);
                 if (not tc_ok) && (not is_debug) then
                   Printf.eprintf "note: inferred type was %s\n%!" ty_str
                 else
                   (* Interpreter fallback: used when JIT is unavailable or when
                      JIT compilation fails (e.g. codegen bug for a specific builtin). *)
                   let eval_via_interp () =
                     let v = March_eval.Eval.eval_expr !env e' in
                     let vs = March_eval.Eval.value_to_string_pretty v in
                     Printf.printf "= %s\n%!" vs;
                     if !show_type then
                       Printf.printf "- : %s\n%!" ty_str;
                     Result_vars.push result_h v ty_str;
                     env    := ("v", v)
                              :: (List.remove_assoc "v" !env);
                     if tc_ok then
                       tc_env := { !tc_env with
                         vars = March_typecheck.Typecheck.StrMap.add "v"
                                  (March_typecheck.Typecheck.Mono inferred) !tc_env.vars }
                   in
                   (try
                      (match jit_ctx with
                      | Some jit ->
                        (try
                          let m = wrap_expr_as_module e' in
                          let (_ty, result_str) =
                            March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
                          Printf.printf "= %s\n%!" result_str;
                          if !show_type then
                            Printf.printf "- : %s\n%!" ty_str;
                          if tc_ok then
                            tc_env := { !tc_env with
                              vars = March_typecheck.Typecheck.StrMap.add "v"
                                       (March_typecheck.Typecheck.Mono inferred) !tc_env.vars }
                        with Failure _ ->
                          (* JIT compilation failed — fall back to tree-walking interpreter *)
                          eval_via_interp ())
                      | None ->
                        eval_via_interp ())
                    with
                    | March_eval.Eval.Eval_error msg ->
                      March_eval.Eval.clear_march_stack ();
                      Printf.eprintf "runtime error: %s\n%!" msg
                    | March_eval.Eval.Match_failure msg ->
                      March_eval.Eval.clear_march_stack ();
                      Printf.eprintf "match failure: %s\n%!" msg
                    | Failure msg ->
                      Printf.eprintf "jit error: %s\n%!" msg
                    | exn ->
                      March_eval.Eval.clear_march_stack ();
                      Printf.eprintf "error: %s\n%!" (Printexc.to_string exn))));
          if scroll_mode then Printf.printf "%s\n%!" scroll_sentinel;
          end;
          (* Drain any values that were tap()ed during evaluation. *)
          List.iter (fun v ->
            let vs = March_eval.Eval.value_to_string_pretty v in
            Printf.printf "tap> %s\n%!" vs
          ) (March_eval.Eval.tap_drain ()))
     with
     | March_lexer.Lexer.Lexer_error msg ->
       Buffer.clear buf; first_line := true;
       Printf.eprintf "lexer error: %s\n%!" msg
     | exn ->
       Buffer.clear buf; first_line := true;
       Printf.eprintf "internal error: %s\n%!" (Printexc.to_string exn))
  done;
  History.save hist (history_path ())

(** Full TUI REPL loop using notty two-pane layout. *)
let run_tui ?(stdlib_decls=[]) ?(debug_hooks=None) ?(initial_env=None) ?(jit_ctx=(None : March_jit.Repl_jit.t option)) ?(preload_file=None) () =
  let use_jit = jit_ctx <> None &&
    Sys.getenv_opt "MARCH_REPL_INTERP" = None in
  let jit_ctx = if use_jit then jit_ctx else None in
  let is_debug = debug_hooks <> None in
  let hist     = History.create ~max_size:(history_size ()) in
  History.load hist (history_path ());
  let type_map = Hashtbl.create 64 in
  let base_e  = March_eval.Eval.task_builtins @ March_eval.Eval.base_env in
  let base_tc = March_typecheck.Typecheck.base_env
    (March_errors.Errors.create ()) type_map in
  let content_hash = stdlib_content_hash stdlib_decls in
  let (e0, tc0) = match initial_env with
    | Some e -> (e, base_tc)
    | None   ->
      (match load_cached_tc_env ~content_hash ~type_map with
       | Some cached_tc ->
         let e0 = eval_decls_only base_e stdlib_decls in
         (e0, cached_tc)
       | None ->
         let tc_pre = preregister_stdlib_types base_tc stdlib_decls in
         let (e0, tc0) = load_decls_into_env base_e tc_pre stdlib_decls in
         save_cached_tc_env ~content_hash tc0;
         (e0, tc0))
  in
  maybe_precompile_stdlib jit_ctx ~stdlib_decls ~type_map;
  let env      = ref e0 in
  let tc_env   = ref tc0 in
  let result_h = Result_vars.create () in
  let loaded_file  = ref (None : string option) in
  let tui          = Tui.create () in
  let inp          = ref Input.empty in
  let comp         = ref CompOff in
  let hist_lines   = ref [] in
  let prompt_num   = ref 1 in
  let running      = ref true in
  let scroll_offset = ref 0 in
  (* Watch expressions: (display_string * parsed_expr) list *)
  let watch_list   : (string * March_ast.Ast.expr) list ref = ref [] in
  (* Auto-type display: when true, print inferred type after each expression. *)
  let show_type    = ref false in
  (* scope_baseline: stdlib + preloaded names to hide from the right pane.
     Mutable so that preload can update it after loading project code. *)
  let scope_baseline = ref (if is_debug then base_e else e0) in
  (* Cached right-pane data — recomputed only after Submit/env changes,
     never on plain Redraw keystrokes.  This avoids O(|env|²) work per key. *)
  let cached_scope   = ref ([] : Tui.scope_entry list) in
  let cached_result  = ref (None : (string * string) option) in
  let cached_actors  = ref ([] : March_eval.Eval.actor_info list) in
  let refresh_scope () =
    let (sc, res) = user_scope !env !tc_env result_h ~baseline_env:!scope_baseline in
    cached_scope  := sc;
    cached_result := res;
    cached_actors := March_eval.Eval.list_actors ()
  in
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
    let scope         = !cached_scope in
    let result_latest = !cached_result in
    let (comp_items, comp_sel) = match !comp with
      | CompOff -> ([], 0)
      | CompOn { items; sel } -> (items, sel)
    in
    let actors = !cached_actors in
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

  let tui_load_decls_list path all_decls =
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
    ) all_decls;
    ignore path
  in

  let tui_parse_file path =
    match (try
      let ic = open_in path in
      let n  = in_channel_length ic in
      let b  = Bytes.create n in
      really_input ic b 0 n;
      close_in ic;
      Some (Bytes.to_string b)
    with Sys_error msg ->
      add_line Notty.A.(fg red) (Printf.sprintf "cannot open: %s" msg); None) with
    | None -> None
    | Some file_src ->
      let lexbuf = Lexing.from_string file_src in
      (match (try
        let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
        Some (March_desugar.Desugar.desugar_module m)
      with _ -> add_line Notty.A.(fg red) "parse error in file"; None) with
      | None -> None
      | Some desugared ->
        let (_, extra_decls) =
          March_resolver.Resolver.resolve_imports ~source_file:path desugared in
        Some (desugared, extra_decls))
  in

  (* :load — wraps in DMod so names are qualified (e.g. DbTest.main). *)
  let do_load_file path =
    match tui_parse_file path with
    | None -> ()
    | Some (desugared, extra_decls) ->
      let file_mod =
        March_ast.Ast.DMod (
          desugared.March_ast.Ast.mod_name,
          March_ast.Ast.Public,
          desugared.March_ast.Ast.mod_decls,
          March_ast.Ast.dummy_span)
      in
      tui_load_decls_list path (extra_decls @ [file_mod]);
      add_line Notty.A.(fg green) (Printf.sprintf "loaded %s" path);
      loaded_file := Some path
  in

  (* Preload (forge interactive) — flat so top-level imports open namespaces. *)
  let do_preload_file path =
    match tui_parse_file path with
    | None -> ()
    | Some (desugared, extra_decls) ->
      tui_load_decls_list path (extra_decls @ desugared.March_ast.Ast.mod_decls);
      add_line Notty.A.(fg green) (Printf.sprintf "loaded %s" path);
      loaded_file := Some path
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

  (* Redirect stdout to a pipe during [f ()], add captured lines to transcript.
     Notty already dup'd its terminal fd at create time, so redirecting fd 1
     here does not interfere with rendering. *)
  let capture_stdout f =
    flush stdout;
    let (pipe_r, pipe_w) = Unix.pipe () in
    let saved_fd = Unix.dup Unix.stdout in
    Unix.dup2 pipe_w Unix.stdout;
    Unix.close pipe_w;
    let result = (try Ok (f ()) with exn -> Error exn) in
    flush stdout;
    Unix.dup2 saved_fd Unix.stdout;
    Unix.close saved_fd;
    let buf = Buffer.create 256 in
    let tmp = Bytes.create 4096 in
    (try while true do
      let n = Unix.read pipe_r tmp 0 (Bytes.length tmp) in
      if n = 0 then raise Exit
      else Buffer.add_subbytes buf tmp 0 n
    done with Exit -> ());
    Unix.close pipe_r;
    let captured = Buffer.contents buf in
    List.iter (fun line -> if line <> "" then add_line Notty.A.empty line)
      (String.split_on_char '\n' captured);
    match result with
    | Ok v    -> v
    | Error e -> raise e
  in

  let process_src src =
    let lexbuf = Lexing.from_string src in
    (match (try Some (March_parser.Parser.repl_input (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
            with
            | March_errors.Errors.ParseError (msg, hint, _) ->
              let rendered = March_errors.Errors.render_parse_error ~src ?hint ~msg lexbuf in
              List.iter (add_line Notty.A.(fg red)) (String.split_on_char '\n' rendered);
              None
            | March_parser.Parser.Error ->
              let rendered = March_errors.Errors.render_parse_error ~src ~msg:"I got stuck here:" lexbuf in
              List.iter (add_line Notty.A.(fg red)) (String.split_on_char '\n' rendered);
              None) with
    | None | Some March_ast.Ast.ReplEOF -> ()
    | Some (March_ast.Ast.ReplDecl d) ->
      let d' = March_desugar.Desugar.desugar_decl d in
      (* Auto-load user modules on `import Foo` typed directly in the REPL. *)
      (match d' with
       | March_ast.Ast.DUse _ | March_ast.Ast.DAlias _ ->
         let cwd = Sys.getcwd () in
         let env_lib_paths =
           match Sys.getenv_opt "MARCH_LIB_PATH" with
           | None -> []
           | Some s -> List.filter (fun d -> d <> "") (String.split_on_char ':' s)
         in
         let candidates = [cwd; Filename.concat cwd "src"; Filename.concat cwd "lib"] @ env_lib_paths in
         let search_dir =
           let mod_name = match d' with
             | March_ast.Ast.DUse (ud, _) ->
               (match ud.March_ast.Ast.use_path with
                | n :: _ -> Some n.March_ast.Ast.txt | [] -> None)
             | March_ast.Ast.DAlias (ad, _) ->
               (match ad.March_ast.Ast.alias_path with
                | n :: _ -> Some n.March_ast.Ast.txt | [] -> None)
             | _ -> None
           in
           match mod_name with
           | None -> cwd
           | Some mname ->
             let fname = March_resolver.Resolver.module_name_to_filename mname in
             match List.find_opt (fun d -> Sys.file_exists (Filename.concat d fname)) candidates with
             | Some d -> d | None -> cwd
         in
         let dummy_src = Filename.concat search_dir "_repl_.march" in
         let dummy_mod = { March_ast.Ast.mod_name = { txt = "Repl"; span = March_ast.Ast.dummy_span }
                         ; mod_decls = [d'] } in
         let (_, extra_decls) =
           March_resolver.Resolver.resolve_imports ~source_file:dummy_src dummy_mod in
         List.iter (fun decl ->
           let ictx = March_errors.Errors.create () in
           let itc  = { !tc_env with errors = ictx } in
           let ntc  = March_typecheck.Typecheck.check_decl itc decl in
           if not (March_errors.Errors.has_errors ictx) then
             (try env    := March_eval.Eval.eval_decl !env decl;
                  tc_env := { ntc with errors = March_errors.Errors.create () }
              with _ -> ())
         ) extra_decls
       | _ -> ());
      let input_ctx = March_errors.Errors.create () in
      let input_tc  = { !tc_env with errors = input_ctx } in
      let new_tc    = March_typecheck.Typecheck.check_decl input_tc d' in
      let tc_ok = not (March_errors.Errors.has_errors input_ctx) in
      if not is_debug then
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
      if tc_ok || is_debug then
        (try
           (match jit_ctx with
           | Some jit when (match d' with March_ast.Ast.DFn _ -> true | _ -> false) ->
             let bind_name = match d' with
               | March_ast.Ast.DFn (def, _) -> def.fn_name.txt
               | _ -> assert false
             in
             let m = wrap_decl_as_module d' in
             (try March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:true ~bind_name m
              with Failure _ -> ());
             if tc_ok then
               tc_env := { new_tc with errors = March_errors.Errors.create () };
             add_line Notty.A.empty (Printf.sprintf "val %s = <fn>" bind_name)
           | Some jit when (match d' with
               | March_ast.Ast.DLet (_, b, _) ->
                 (match b.bind_pat with March_ast.Ast.PatVar _ -> true | _ -> false)
               | _ -> false) ->
             (* JIT path for simple let bindings: compile value to a global. *)
             let bind_name = match d' with
               | March_ast.Ast.DLet (_, b, _) ->
                 (match b.bind_pat with March_ast.Ast.PatVar n -> n.txt | _ -> assert false)
               | _ -> assert false
             in
             let bind_expr = match d' with
               | March_ast.Ast.DLet (_, b, _) -> b.bind_expr
               | _ -> assert false
             in
             let m = wrap_expr_as_module bind_expr in
             (try March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m
              with Failure _ -> ());
             env := capture_stdout (fun () -> March_eval.Eval.eval_decl !env d');
             if tc_ok then
               tc_env := { new_tc with errors = March_errors.Errors.create () };
             let vstr = match List.assoc_opt bind_name !env with
               | Some v -> March_eval.Eval.value_to_string v
               | None -> "?"
             in
             add_line Notty.A.empty (Printf.sprintf "val %s = %s" bind_name vstr)
           | _ ->
             env := capture_stdout (fun () -> March_eval.Eval.eval_decl !env d');
             if tc_ok then
               tc_env := { new_tc with errors = March_errors.Errors.create () };
             let out = match d' with
               | March_ast.Ast.DFn (def, _) ->
                 Printf.sprintf "val %s = <fn>" def.fn_name.txt
               | March_ast.Ast.DLet (_, b, _) ->
                 (match b.bind_pat with
                  | March_ast.Ast.PatVar n ->
                    let vstr = match List.assoc_opt n.txt !env with
                      | Some v -> March_eval.Eval.value_to_string v
                      | None -> "?"
                    in
                    Printf.sprintf "val %s = %s" n.txt vstr
                  | _ -> "val _ = ...")
               | March_ast.Ast.DActor (_, name, _, _) ->
                 Printf.sprintf "val %s = <actor>" name.txt
               | _ -> ""
             in
             if out <> "" then add_line Notty.A.empty out)
         with
         | March_eval.Eval.Eval_error msg ->
           March_eval.Eval.clear_march_stack ();
           add_line Notty.A.(fg red) (Printf.sprintf "runtime error: %s" msg)
         | March_eval.Eval.Match_failure msg ->
           March_eval.Eval.clear_march_stack ();
           add_line Notty.A.(fg red) (Printf.sprintf "match failure: %s" msg)
         | Failure msg ->
           add_line Notty.A.(fg red) (Printf.sprintf "jit error: %s" msg)
         | exn ->
           add_line Notty.A.(fg red) (Printf.sprintf "error: %s" (Printexc.to_string exn)))
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
      let tc_ok = not (March_errors.Errors.has_errors input_ctx) in
      if not is_debug then
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
      if (not tc_ok) && (not is_debug) then
        add_line Notty.A.empty (Printf.sprintf "note: inferred type was %s" ty_str)
      else
        (try
           (match jit_ctx with
           | Some jit ->
             let m = wrap_expr_as_module e' in
             let (_ty, result_str) =
               March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
             add_line Notty.A.(fg green) (Printf.sprintf "= %s" result_str);
             if !show_type then
               add_line Notty.A.(fg cyan) (Printf.sprintf "- : %s" ty_str);
             if tc_ok then
               tc_env := { !tc_env with
                 vars = March_typecheck.Typecheck.StrMap.add "v"
                          (March_typecheck.Typecheck.Mono inferred) !tc_env.vars }
           | None ->
             let v = capture_stdout (fun () -> March_eval.Eval.eval_expr !env e') in
             let vs = March_eval.Eval.value_to_string_pretty v in
             add_line Notty.A.(fg green) (Printf.sprintf "= %s" vs);
             if !show_type then
               add_line Notty.A.(fg cyan) (Printf.sprintf "- : %s" ty_str);
             Result_vars.push result_h v ty_str;
             env    := ("v", v) :: (List.remove_assoc "v" !env);
             if tc_ok then
               tc_env := { !tc_env with
                 vars = March_typecheck.Typecheck.StrMap.add "v"
                          (March_typecheck.Typecheck.Mono inferred) !tc_env.vars })
         with
         | March_eval.Eval.Eval_error msg ->
           March_eval.Eval.clear_march_stack ();
           add_line Notty.A.(fg red) (Printf.sprintf "runtime error: %s" msg)
         | March_eval.Eval.Match_failure msg ->
           March_eval.Eval.clear_march_stack ();
           add_line Notty.A.(fg red) (Printf.sprintf "match failure: %s" msg)
         | Failure msg ->
           add_line Notty.A.(fg red) (Printf.sprintf "jit error: %s" msg)
         | exn ->
           add_line Notty.A.(fg red) (Printf.sprintf "error: %s" (Printexc.to_string exn))))
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
          (match (try Some (March_parser.Parser.repl_input (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
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
             (match (try Some (March_parser.Parser.repl_input (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
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
        | ":set +t" ->
          show_type := true;
          add_line Notty.A.(fg green) "type display: on  (`:set -t` to disable)"
        | ":set -t" ->
          show_type := false;
          add_line Notty.A.(fg green) "type display: off"
        | ":clear" -> hist_lines := []
        | ":reset" when not is_debug ->
          let base_tc' = March_typecheck.Typecheck.base_env
            (March_errors.Errors.create ()) type_map in
          let tc_pre' = preregister_stdlib_types base_tc' stdlib_decls in
          let base_e' = March_eval.Eval.task_builtins @ March_eval.Eval.base_env in
          let (e', tc') = load_decls_into_env base_e' tc_pre' stdlib_decls in
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
            "  :quit :q            — exit";
            "  :env                — list bindings in scope";
            "  :type <expr>        — show inferred type without evaluating";
            "  :inspect <expr>     — show type and value  (alias: :i)";
            "  :doc <name>         — show documentation for a name";
            "  :load <file>        — load a .march source file";
            "  :reload             — reload the last :load-ed file";
            "  :clear              — clear transcript (keeps bindings)";
            "  :reset              — reset all bindings to stdlib baseline";
            "  :set +t             — show inferred type after each expression";
            "  :set -t             — hide inferred type (default)";
            "  :help               — this message";
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
            (match (try Some (March_parser.Parser.repl_input (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
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
            do_load_file path
        | ":reload" ->
          (match !loaded_file with
           | None ->
             add_line Notty.A.(fg yellow) "Nothing to reload."
           | Some path ->
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
                 let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
                 Some (March_desugar.Desugar.desugar_module m)
               with _ -> add_line Notty.A.(fg red) "parse error in file"; None) with
               | None -> ()
               | Some desugared ->
                 let (_, extra_decls) =
                   March_resolver.Resolver.resolve_imports ~source_file:path desugared in
                 let file_mod =
                   March_ast.Ast.DMod (
                     desugared.March_ast.Ast.mod_name,
                     March_ast.Ast.Public,
                     desugared.March_ast.Ast.mod_decls,
                     March_ast.Ast.dummy_span)
                 in
                 let all_decls = extra_decls @ [file_mod] in
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
                 ) all_decls;
                 add_line Notty.A.(fg green) (Printf.sprintf "reloaded %s" path))))
        | src when (let t = String.trim src in
                      (String.length t >= 8 && String.sub t 0 8 = ":inspect")
                      || (String.length t >= 2 && String.sub t 0 2 = ":i"
                          && (String.length t = 2 || t.[2] = ' '))) && not is_debug ->
          (* :inspect expr  /  :i expr — show type and value *)
          let prefix_len =
            let t = String.trim src in
            if String.length t >= 8 && String.sub t 0 8 = ":inspect" then 8
            else 2
          in
          let expr_src = String.trim (String.sub (String.trim src) prefix_len
            (String.length (String.trim src) - prefix_len)) in
          if expr_src = "" then
            add_line Notty.A.(fg red) "usage: :inspect <expr>"
          else begin
            let lexbuf = Lexing.from_string expr_src in
            (match (try Some (March_parser.Parser.repl_input (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
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
              else begin
                (try
                   let v   = March_eval.Eval.eval_expr !env e' in
                   let vs  = March_eval.Eval.value_to_string_pretty v in
                   add_line Notty.A.(fg cyan) (Printf.sprintf "type  : %s" ty_str);
                   add_line Notty.A.empty     (Printf.sprintf "value : %s" vs)
                 with
                 | March_eval.Eval.Eval_error msg ->
                   March_eval.Eval.clear_march_stack ();
                   add_line Notty.A.(fg red) (Printf.sprintf "runtime error: %s" msg)
                 | exn ->
                   March_eval.Eval.clear_march_stack ();
                   add_line Notty.A.(fg red) (Printf.sprintf "error: %s" (Printexc.to_string exn)))
              end
            | _ -> add_line Notty.A.(fg red) "parse error")
          end
        | src when String.length src > 4 && String.sub src 0 4 = ":doc" ->
          let name = String.trim (String.sub src 4 (String.length src - 4)) in
          if name = "" then
            add_line Notty.A.(fg red) "usage: :doc <name>"
          else begin
            match March_eval.Eval.lookup_doc name with
            | Some s -> add_line Notty.A.empty s
            | None   ->
              add_line Notty.A.(fg yellow)
                (Printf.sprintf "No documentation found for %s" name)
          end
        | src when String.length src > 5 && String.sub src 0 5 = ":save" ->
          let path = String.trim (String.sub src 5 (String.length src - 5)) in
          if path = "" then
            add_line Notty.A.(fg red) "usage: :save <file>"
          else
            add_line Notty.A.(fg yellow)
              (Printf.sprintf ":save %s — session tracking not yet implemented" path)
        | src when String.trim src = "" -> ()
        | src -> process_src src);
       (* Drain any values that were tap()ed during evaluation. *)
       List.iter (fun v ->
         let vs = March_eval.Eval.value_to_string_pretty v in
         add_line Notty.A.(fg (rgb_888 ~r:255 ~g:165 ~b:0))
           (Printf.sprintf "tap> %s" vs)
       ) (March_eval.Eval.tap_drain ());
       refresh_scope ();
       render_frame ()
     | Input.HistoryPrev ->
       (match History.prev hist with
        | None -> ()
        | Some entry ->
          let (buf, mbuf) = match List.rev (String.split_on_char '\n' entry) with
            | [] -> ("", [])
            | last :: rest -> (last, rest)
          in
          inp := { !inp with Input.buffer = buf;
                             Input.cursor = String.length buf;
                             Input.multiline_buf = mbuf };
          render_frame ())
     | Input.HistoryNext ->
       let entry = match History.next hist with None -> "" | Some e -> e in
       let (buf, mbuf) = match List.rev (String.split_on_char '\n' entry) with
         | [] -> ("", [])
         | last :: rest -> (last, rest)
       in
       inp := { !inp with Input.buffer = buf;
                          Input.cursor = String.length buf;
                          Input.multiline_buf = mbuf };
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

  (* Preload a file before entering the loop (e.g. from forge interactive).
     After preloading, update the baseline so preloaded names are hidden
     from the scope panel — only user-typed bindings should appear. *)
  Option.iter do_preload_file preload_file;
  if preload_file <> None then scope_baseline := !env;

  (* Show :where immediately on entry so the user knows where they are. *)
  (match debug_hooks with
   | Some h -> nav_context h
   | None   -> ());
  refresh_scope ();
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

let run ?(stdlib_decls = []) ?(debug_hooks = None) ?(initial_env = None) ?(jit_ctx : March_jit.Repl_jit.t option = None) ?(preload_file = None) () =
  if Unix.isatty Unix.stdin && Unix.isatty Unix.stdout
  then run_tui ~stdlib_decls ~debug_hooks ~initial_env ~jit_ctx ~preload_file ()
  else run_simple ~stdlib_decls ~debug_hooks ~initial_env ~jit_ctx ~preload_file ()
