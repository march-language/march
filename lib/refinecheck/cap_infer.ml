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
  ("tcp_local_port",        "IO.NetListen");
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
      | A.DNeeds (caps, _) -> List.map (fun (p, _) -> cap_path_of_names p) caps
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

(* ── Call graph, for "how did we get here from `main`" ───────────────────── *)

(** Direct callees of an expression: the names in `f(...)` position. Indirect
    calls (a function value in a variable, an interface method) are not edges we
    can resolve syntactically, so they are skipped — the chain is a witness, not
    a proof, and a missing edge costs at most the chain, never a wrong one. *)
let direct_callees (e : A.expr) : string list =
  let acc = ref [] in
  (* A qualified call `M.f` is one [EVar] whose text carries the module prefix,
     while graph nodes are keyed by the simple name a definition declares. Left
     unnormalised the edge never matches, and the chain breaks precisely at a
     module boundary — the case most worth explaining, since threading `needs`
     across modules is the part people get wrong. Normalising can conflate two
     modules' same-named functions; that is the acknowledged cost of a
     syntactic witness (see [build_call_graph]). *)
  let simple_name (s : string) =
    match String.rindex_opt s '.' with
    | None -> s
    | Some i -> String.sub s (i + 1) (String.length s - i - 1)
  in
  let rec go (e : A.expr) =
    (match e with
     | A.EApp (A.EVar fn, _, _) -> acc := simple_name fn.A.txt :: !acc
     | _ -> ());
    match e with
    | A.EApp (callee, args, _) -> go callee; List.iter go args
    | A.ECon (_, args, _) | A.ETuple (args, _) | A.EAtom (_, args, _) ->
      List.iter go args
    | A.ERecord (fields, _) -> List.iter (fun (_, e) -> go e) fields
    | A.ERecordUpdate (r, fields, _) -> go r; List.iter (fun (_, e) -> go e) fields
    | A.EBlock (es, _) -> List.iter go es
    | A.ELet (b, _) -> go b.A.bind_expr
    | A.ELetQ (_, e1, e2, _) -> go e1; go e2
    | A.ELetFn (_, _, _, body, _) -> go body
    | A.EMatch (scrut, arms, _) ->
      go scrut; List.iter (fun (br : A.branch) -> go br.A.branch_body) arms
    | A.EIf (c, t, f, _) -> go c; go t; go f
    | A.ECond (arms, _) -> List.iter (fun (c, b) -> go c; go b) arms
    | A.ELam (_, body, _) -> go body
    | A.EPipe (a, b, _) | A.ESend (a, b, _) -> go a; go b
    | A.EField (e, _, _) | A.EAnnot (e, _, _) | A.ESpawn (e, _)
    | A.ESigil (_, e, _) | A.EAssert (e, _) -> go e
    | A.EDbg (e_opt, _) -> Option.iter go e_opt
    | A.EVar _ | A.ELit _ | A.EHole _ | A.EResultRef _ -> ()
  in
  go e;
  List.rev !acc

(** Flat call graph over every function in the compilation unit, keyed by SIMPLE
    name — the same key [iter_cap_calls] reports and the same one a qualified
    call `M.f` resolves to at its definition. Two modules that both define `f`
    therefore share a node; the cost of that collision is a chain that may name
    the wrong sibling, never a chain where none exists, which is why this is
    reported as "reached from" rather than as a proof. *)
let build_call_graph (decls : A.decl list) : (string, string list) Hashtbl.t =
  let g : (string, string list) Hashtbl.t = Hashtbl.create 64 in
  let add name callees =
    let prev = try Hashtbl.find g name with Not_found -> [] in
    Hashtbl.replace g name (prev @ callees)
  in
  let rec walk ds =
    List.iter
      (function
        | A.DFn (fd, _) ->
          List.iter
            (fun (c : A.fn_clause) ->
              add fd.A.fn_name.A.txt (direct_callees c.A.fc_body))
            fd.A.fn_clauses
        | A.DLet (_, b, _) -> add "" (direct_callees b.A.bind_expr)
        | A.DMod (_, _, inner, _) -> walk inner
        | _ -> ())
      ds
  in
  walk decls;
  g

(** Shortest call path [entry → … → target], or None when the target is not
    reachable from the entry (a library with no `main`, or a function only
    reached indirectly). Breadth-first, so the reported chain is the shortest
    one; the visited set makes recursion terminate. *)
let call_path (g : (string, string list) Hashtbl.t) ~(entry : string)
    ~(target : string) : string list option =
  if entry = target then Some [ entry ]
  else begin
    let visited : (string, unit) Hashtbl.t = Hashtbl.create 64 in
    let result = ref None in
    let rec bfs (frontier : (string * string list) list) =
      match frontier with
      | [] -> ()
      | _ when !result <> None -> ()
      | _ ->
        let next =
          List.concat_map
            (fun (node, path) ->
              if !result <> None then []
              else
                let callees = try Hashtbl.find g node with Not_found -> [] in
                List.filter_map
                  (fun c ->
                    if Hashtbl.mem visited c then None
                    else begin
                      Hashtbl.replace visited c ();
                      let path' = path @ [ c ] in
                      if c = target then (result := Some path'; None)
                      else Some (c, path')
                    end)
                  callees)
            frontier
        in
        bfs next
    in
    Hashtbl.replace visited entry ();
    bfs [ (entry, [ entry ]) ];
    !result
  end

(* ── Per-module check ────────────────────────────────────────────────────── *)

(** Walk [decls] belonging to module [mod_name], emitting a hint for every
    capability-requiring call not covered by the module's [needs].  One hint
    per missing capability per module (deduplication suppresses repeated hints
    for the same cap when multiple call sites are present).
    Recurses into [DMod] children with their own [DNeeds] scope. *)
let rec check_decls ?(graph : (string, string list) Hashtbl.t option)
    (mod_name : string) (errctx : Err.ctx) (decls : A.decl list) : unit =
  let needs = declared_needs decls in
  let hinted : (string, unit) Hashtbl.t = Hashtbl.create 4 in
  (* The chain that forced this capability. A capability is a property of the
     whole path, not of the one call that happens to need it: the reader has to
     thread `needs` through every function between `main` and here, and until
     now the diagnostic named only the far end. Omitted rather than guessed when
     there is no `main` (a library) or no syntactic path (the call is reached
     only through a function value). *)
  let chain_note (enclosing : string) : string =
    match graph with
    | None -> ""
    | Some g ->
      (match call_path g ~entry:"main" ~target:enclosing with
       | None | Some [ _ ] -> ""
       | Some path ->
         Printf.sprintf "\nreached from `main`: %s" (String.concat " → " path))
  in
  let emit_if_missing enclosing call_name call_span =
    match cap_of_call call_name with
    | None -> ()
    | Some cap ->
      if need_covers cap needs then ()
      else if Hashtbl.mem hinted cap then ()
      else begin
        Hashtbl.replace hinted cap ();
        Err.hint errctx ~span:call_span
          (Printf.sprintf
             "call to `%s` requires `needs %s` — add `needs %s` to module `%s`%s"
             call_name cap cap mod_name (chain_note enclosing))
      end
  in
  List.iter
    (function
      | A.DFn (fd, _) ->
        List.iter
          (fun (clause : A.fn_clause) ->
            iter_cap_calls (emit_if_missing fd.A.fn_name.A.txt) clause.A.fc_body)
          fd.A.fn_clauses
      | A.DLet (_vis, b, _) ->
        iter_cap_calls (emit_if_missing "") b.A.bind_expr
      | A.DMod (inner_name, _, inner_decls, _) ->
        check_decls ?graph inner_name.A.txt errctx inner_decls
      | _ -> ())
    decls

let check_module (errctx : Err.ctx) (m : A.module_) : unit =
  (* Built once over the whole unit, then shared by every nested module's walk:
     a chain from `main` routinely crosses module boundaries, so a per-module
     graph would report "no path" for exactly the cases worth explaining. *)
  let graph = build_call_graph m.A.mod_decls in
  check_decls ~graph m.A.mod_name.A.txt errctx m.A.mod_decls
