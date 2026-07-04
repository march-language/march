(* Capability inference hints for the March compiler.
   A post-typecheck pass that walks function and let-binding bodies, finds calls
   to capability-requiring builtins, and emits Err.hint diagnostics at the exact
   call site when the enclosing module lacks the corresponding [needs] declaration.

   This is a *soft* pass — the typechecker's own body-scan (Phase 2) already
   emits Err.warning for missing needs; this pass adds Err.hint annotations that
   point directly at the call site rather than at the [needs] insertion point,
   giving a second, finer-grained anchor.

   Capability hierarchy: a declared `needs IO` covers all IO.* children; a
   declared `needs IO.Network` covers IO.NetConnect, IO.NetListen, etc.  We
   implement the same subsumption rule as the typechecker's [cap_subsumes].

   Supported capabilities (mirrors builtin_cap_table in typecheck.ml):
     IO.Console, IO.FileRead, IO.FileWrite, IO.FileSystem, IO.NetConnect,
     IO.Network, IO.NetListen, IO.Process, IO.Clock, IO.Random,
     IO.Spawn, IO.Mut, IO.NetConnect.TLS, IO.Foreign, IO.Foreign.Blocking *)

module A = March_ast.Ast
module Err = March_errors.Errors

(* ── Capability hierarchy ────────────────────────────────────────────────── *)

(** Hierarchy + subsumption now live in [March_caps.Cap_lattice] (Phase5C-A.1)
    — shared with the typechecker's body-scan pass, which previously carried
    a verbatim duplicate of this table. *)
let cap_subsumes = March_caps.Cap_lattice.cap_subsumes

(* ── Builtin → capability table ──────────────────────────────────────────── *)

(** Mirrors [builtin_cap_table] in typecheck.ml.  Keep in sync when new
    capabilities are added. *)
let cap_table : (string * string) list = [
  (* IO.Console *)
  ("println",               "IO.Console");
  ("print",                 "IO.Console");
  (* IO.FileRead *)
  ("file_exists",           "IO.FileRead");
  ("file_read",             "IO.FileRead");
  ("file_open",             "IO.FileRead");
  ("file_read_line",        "IO.FileRead");
  ("file_read_chunk",       "IO.FileRead");
  ("file_stat",             "IO.FileRead");
  ("dir_exists",            "IO.FileRead");
  ("dir_list",              "IO.FileRead");
  ("csv_open",              "IO.FileRead");
  ("csv_next_row",          "IO.FileRead");
  (* IO.FileWrite *)
  ("file_write",            "IO.FileWrite");
  ("file_append",           "IO.FileWrite");
  ("file_delete",           "IO.FileWrite");
  ("file_rename",           "IO.FileWrite");
  ("dir_mkdir",             "IO.FileWrite");
  ("dir_mkdir_p",           "IO.FileWrite");
  ("dir_rmdir",             "IO.FileWrite");
  ("dir_rm_rf",             "IO.FileWrite");
  (* IO.FileSystem — needs both read+write *)
  ("file_copy",             "IO.FileSystem");
  (* IO.NetConnect *)
  ("tcp_connect",           "IO.NetConnect");
  ("tcp_send_all",          "IO.NetConnect");
  ("tcp_recv_all",          "IO.NetConnect");
  ("tcp_recv_exact",        "IO.NetConnect");
  ("tcp_recv_http",         "IO.NetConnect");
  ("tcp_recv_http_headers", "IO.NetConnect");
  ("tcp_recv_chunk",        "IO.NetConnect");
  ("tcp_recv_chunked_frame","IO.NetConnect");
  ("ws_recv",               "IO.NetConnect");
  ("ws_send",               "IO.NetConnect");
  ("ws_select",             "IO.NetConnect");
  (* IO.Network *)
  ("dns_resolve",           "IO.Network");
  (* IO.NetListen *)
  ("tcp_listen",            "IO.NetListen");
  ("tcp_accept",            "IO.NetListen");
  ("http_server_listen",    "IO.NetListen");
  ("http_server_spawn_n",   "IO.NetListen");
  ("http_server_wait",      "IO.NetListen");
  (* IO.Process *)
  ("process_env",           "IO.Process");
  ("process_set_env",       "IO.Process");
  ("process_cwd",           "IO.Process");
  ("process_argv",          "IO.Process");
  ("process_pid",           "IO.Process");
  ("process_exit",          "IO.Process");
  ("process_spawn_sync",    "IO.Process");
  ("process_spawn_lines",   "IO.Process");
  ("process_spawn_async",   "IO.Process");
  ("process_read_line",     "IO.Process");
  ("process_write",         "IO.Process");
  ("process_kill_proc",     "IO.Process");
  ("process_wait_proc",     "IO.Process");
  (* IO.Clock *)
  ("unix_time",             "IO.Clock");
  ("unix_time_ms",          "IO.Clock");
  ("uuid_v7",               "IO.Clock");
  (* IO.Random *)
  ("random_bytes",          "IO.Random");
  ("stdlib_random_bytes",   "IO.Random");
  ("uuid_v4",               "IO.Random");
  (* IO.Spawn *)
  ("task_spawn",            "IO.Spawn");
  ("task_spawn_link",       "IO.Spawn");
  ("task_spawn_steal",      "IO.Spawn");
  ("task_spawn_with_cancel","IO.Spawn");
  ("get_work_pool",         "IO.Spawn");
  (* IO.Mut — shared mutable state via Vault *)
  ("vault_new",             "IO.Mut");
  ("vault_set",             "IO.Mut");
  ("vault_set_ttl",         "IO.Mut");
  ("vault_get",             "IO.Mut");
  ("vault_drop",            "IO.Mut");
  ("vault_update",          "IO.Mut");
  ("vault_put_new",         "IO.Mut");
  ("vault_incr",            "IO.Mut");
  ("vault_push_capped",     "IO.Mut");
  ("vault_ns_set",          "IO.Mut");
  ("vault_ns_get",          "IO.Mut");
  ("vault_ns_drop",         "IO.Mut");
  ("vault_keys",            "IO.Mut");
  ("vault_whereis",         "IO.Mut");
  ("vault_size",            "IO.Mut");
  (* IO.NetConnect.TLS *)
  ("tls_client_ctx",        "IO.NetConnect.TLS");
  ("tls_server_ctx",        "IO.NetConnect.TLS");
  ("tls_connect",           "IO.NetConnect.TLS");
  ("tls_accept",            "IO.NetConnect.TLS");
  ("tls_read",              "IO.NetConnect.TLS");
  ("tls_write",             "IO.NetConnect.TLS");
  ("tls_negotiated_alpn",   "IO.NetConnect.TLS");
  ("tls_peer_cn",           "IO.NetConnect.TLS");
]

let cap_of_call name = List.assoc_opt name cap_table

(* ── Declared needs collection ───────────────────────────────────────────── *)

(** [cap_path_of_names names] joins an AST name-list to a dot-joined string. *)
let cap_path_of_names names =
  String.concat "." (List.map (fun (n : A.name) -> n.txt) names)

(** Collect the set of declared capability paths from a decl list. *)
let declared_needs (decls : A.decl list) : string list =
  List.concat_map
    (function
      | A.DNeeds (caps, _) -> List.map cap_path_of_names caps
      | _ -> [])
    decls

(** [need_covers cap needs] — true when any element of [needs] subsumes [cap]. *)
let need_covers cap needs =
  List.exists (fun need -> cap_subsumes need cap) needs

(* ── Call-site walker ────────────────────────────────────────────────────── *)

(** [iter_cap_calls f e] calls [f call_name call_span] for every direct
    function call in [e] to a capability-requiring builtin.
    Walks the full expression tree; conservatively ignores higher-order calls
    (EApp where the callee is not EVar). *)
let rec iter_cap_calls (f : string -> A.span -> unit) (e : A.expr) : unit =
  let go = iter_cap_calls f in
  match e with
  | A.EApp (A.EVar fn_name, args, _) ->
    (match cap_of_call fn_name.A.txt with
     | Some _ -> f fn_name.A.txt fn_name.A.span
     | None   -> ());
    List.iter go args
  | A.EApp (callee, args, _) ->
    go callee; List.iter go args
  | A.ECon (_, args, _) | A.ETuple (args, _) | A.EAtom (_, args, _) ->
    List.iter go args
  | A.ERecord (fields, _) ->
    List.iter (fun (_, e) -> go e) fields
  | A.ERecordUpdate (r, fields, _) ->
    go r; List.iter (fun (_, e) -> go e) fields
  | A.EBlock (es, _) -> List.iter go es
  | A.ELet (b, _) -> go b.A.bind_expr
  | A.EMatch (scrut, arms, _) ->
    go scrut;
    List.iter
      (fun (arm : A.branch) ->
        Option.iter go arm.A.branch_guard;
        go arm.A.branch_body)
      arms
  | A.EIf (cond, t, e_else, _) -> go cond; go t; go e_else
  | A.ECond (arms, _) -> List.iter (fun (c, b) -> go c; go b) arms
  | A.EField (inner, _, _) -> go inner
  | A.EPipe (a, b, _) -> go a; go b
  | A.EAnnot (inner, _, _) -> go inner
  | A.ELam (_, body, _) -> go body
  | A.ELetFn (_, _, _, body, _) -> go body
  | A.ELetQ (_, rhs, body, _) -> go rhs; go body
  | A.EAssert (inner, _) -> go inner
  | A.ESend (cap, msg, _) -> go cap; go msg
  | A.ESpawn (inner, _) -> go inner
  | A.EDbg (e_opt, _) -> Option.iter go e_opt
  | A.ESigil (_, inner, _) -> go inner
  | A.EVar _ | A.ELit _ | A.EHole _ | A.EResultRef _ -> ()

(* ── Per-module check ────────────────────────────────────────────────────── *)

(** Walk [decls] belonging to module [mod_name], emitting a hint for every
    capability-requiring call not covered by the module's [needs].  One hint
    per missing capability per module (deduplication suppresses repeated hints
    for the same cap when multiple call sites are present).
    Recurses into [DMod] children with their own [DNeeds] scope. *)
let rec check_decls (mod_name : string) (errctx : Err.ctx) (decls : A.decl list) : unit =
  let needs = declared_needs decls in
  let hinted : (string, unit) Hashtbl.t = Hashtbl.create 4 in
  let emit_if_missing call_name call_span =
    match cap_of_call call_name with
    | None -> ()
    | Some cap ->
      if need_covers cap needs then ()
      else if Hashtbl.mem hinted cap then ()
      else begin
        Hashtbl.replace hinted cap ();
        Err.hint errctx ~span:call_span
          (Printf.sprintf
             "call to `%s` requires `needs %s` — add `needs %s` to module `%s`"
             call_name cap cap mod_name)
      end
  in
  List.iter
    (function
      | A.DFn (fd, _) ->
        List.iter
          (fun (clause : A.fn_clause) ->
            iter_cap_calls emit_if_missing clause.A.fc_body)
          fd.A.fn_clauses
      | A.DLet (_vis, b, _) ->
        iter_cap_calls emit_if_missing b.A.bind_expr
      | A.DMod (inner_name, _, inner_decls, _) ->
        check_decls inner_name.A.txt errctx inner_decls
      | _ -> ())
    decls

let check_module (errctx : Err.ctx) (m : A.module_) : unit =
  check_decls m.A.mod_name.A.txt errctx m.A.mod_decls
