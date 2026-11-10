(* Every stdlib function that performs a capability operation checks it first.

   specs/2026-11-10-object-capability-design.md §15: "a test lists every
   public function that reaches one and fails when a new one lacks a check."
   For ocap phase 1 (specs/plans/2026-11-10-ocap-p1-result-plan.md, Task 4):
   a stdlib function (or impl, actor, top-level let) whose source calls a
   builtin that [March_caps.Cap_ops] classifies [Checked] must also call
   [Authority.check], or be listed in [allowlist] with the reason it need not.

   The unit of the check is a declaration's source text, as the parser spans
   it: a nested helper is part of its enclosing function, so a function that
   checks and then calls a local helper that performs the raw call passes.
   Textual on purpose: it reads what a reviewer reads, and it cannot be
   satisfied by a check the typechecker would discard.

   [CAP_COVERAGE_PRINT=1] prints today's offenders in allowlist form. *)

module Ops = March_caps.Cap_ops

(* ((unit, builtin), reason): calls that need no check. The phase-1 tasks
   delete their rows as they add the checks; what remains at the end is
   reasoned. *)
let allowlist : ((string * string) * string) list = [
  (("ClusterConn.listen", "tcp_listen"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("ClusterNode.credentials", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("ClusterNode.config_from_env", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("ClusterNode.actor ClusterNodeActor", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("ClusterNode.actor ClusterNodeActor", "task_spawn"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("ClusterNode.perform", "task_spawn"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("ClusterNode.mirror", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("ClusterNode.dial", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("ClusterNode.read_link", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("ClusterNode.accept_loop", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("ClusterNode.accept_loop", "task_spawn"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("ClusterNode.tick_loop", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("ClusterNode.watch_cert_files", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("ClusterNode.replace_checked", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("ClusterNode.start", "tcp_listen"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("ClusterNode.start", "task_spawn"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Config.global_table", "vault_new"), "Config's own table (\"__march_config__\"), not one a caller names: the stdlib's state, charged to Config's IO.Mut as today");
  (("Config.global_table", "vault_whereis"), "Config's own table (\"__march_config__\"), not one a caller names: the stdlib's state, charged to Config's IO.Mut as today");
  (("HttpServer.configure_runtime", "http_server_plain_listener"), "deferred to ocap phase 2: this open yields a handle (UDP socket, TLS context, HTTP connection or listener) phase 2 re-types; specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md");
  (("HttpServer.listen", "http_server_listen"), "deferred to ocap phase 2: this open yields a handle (UDP socket, TLS context, HTTP connection or listener) phase 2 re-types; specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md");
  (("HttpServer.spawn_n", "http_server_spawn_n"), "deferred to ocap phase 2: this open yields a handle (UDP socket, TLS context, HTTP connection or listener) phase 2 re-types; specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md");
  (("HttpServer.bind_host", "http_server_bind_host"), "deferred to ocap phase 2: this open yields a handle (UDP socket, TLS context, HTTP connection or listener) phase 2 re-types; specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md");
  (("HttpTransport.connect", "tcp_connect"), "deferred to ocap phase 2: this open yields a handle (UDP socket, TLS context, HTTP connection or listener) phase 2 re-types; specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md");
  (("HttpTransport.request_https_with_context", "tcp_connect"), "deferred to ocap phase 2: this open yields a handle (UDP socket, TLS context, HTTP connection or listener) phase 2 re-types; specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md");
  (("HttpTransport.request_plain", "tcp_connect"), "deferred to ocap phase 2: this open yields a handle (UDP socket, TLS context, HTTP connection or listener) phase 2 re-types; specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md");
  (("List.pmap", "task_spawn"), "checked through spawn_allowed() (Authority.check); a refusal computes the same result sequentially");
  (("List.pmap_n", "task_spawn"), "checked through spawn_allowed() (Authority.check); a refusal computes the same result sequentially");
  (("List.pfilter", "task_spawn"), "checked through spawn_allowed() (Authority.check); a refusal computes the same result sequentially");
  (("List.preduce", "task_spawn"), "checked through spawn_allowed() (Authority.check); a refusal computes the same result sequentially");
  (("NetKernel.recv_exact_until", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("NetKernel.now_s", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("NetKernel.handshake_auth", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Parallel.pmap_n", "task_spawn"), "checked through spawn_allowed() (Authority.check); a refusal computes the same result sequentially");
  (("Parallel.preduce_n", "task_spawn"), "checked through spawn_allowed() (Authority.check); a refusal computes the same result sequentially");
  (("SessionNode.start_link", "task_spawn"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("SessionNode.serve_outcome", "task_spawn"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("SessionNode.addrs_from_env", "process_env"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("SessionNode.open_listener", "tcp_listen"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("SessionNode.notify_redialled", "task_spawn"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("SessionNode.cluster_links", "task_spawn"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("SessionNode.actor OfferActor", "task_spawn"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("SessionNode.retire_offer", "task_spawn"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("SessionNode.hosted_trace", "print_stderr"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Tls.client_ctx", "tls_client_ctx"), "deferred to ocap phase 2: this open yields a handle (UDP socket, TLS context, HTTP connection or listener) phase 2 re-types; specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md");
  (("Tls.server_ctx", "tls_server_ctx"), "deferred to ocap phase 2: this open yields a handle (UDP socket, TLS context, HTTP connection or listener) phase 2 re-types; specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md");
  (("Tls.https_get", "tcp_connect"), "deferred to ocap phase 2: this open yields a handle (UDP socket, TLS context, HTTP connection or listener) phase 2 re-types; specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md");
  (("Topology.actor Anchor", "task_spawn"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.place", "process_env"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.place", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.place", "task_spawn"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.reconcile", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.retire", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.topology_source", "process_env"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.write_status", "process_env"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.drain", "process_exit"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.drain", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.drain", "task_spawn"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.drain_wait", "process_exit"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.drain_wait", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.hook", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.hook", "task_spawn"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.watchdog", "process_exit"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.watchdog", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.config_plain_from_env", "unix_time_ms"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.start_failed", "process_exit"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Topology.runs_pool", "process_env"), "cluster plumbing: the authority is checked where the cluster starts (ClusterNode.start / Topology.place, ocap phase 7)");
  (("Udp.open_with", "udp_open"), "deferred to ocap phase 2: this open yields a handle (UDP socket, TLS context, HTTP connection or listener) phase 2 re-types; specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md");
  (("Udp.resolve", "udp_resolve"), "deferred to ocap phase 2: this open yields a handle (UDP socket, TLS context, HTTP connection or listener) phase 2 re-types; specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md");
  (("Udp.connect", "udp_connect"), "deferred to ocap phase 2: this open yields a handle (UDP socket, TLS context, HTTP connection or listener) phase 2 re-types; specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md");
  (("Udp.send_batch", "udp_send_batch"), "deferred to ocap phase 2: this open yields a handle (UDP socket, TLS context, HTTP connection or listener) phase 2 re-types; specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md");
  (("Udp.send_batch_connected", "udp_send_batch"), "deferred to ocap phase 2: this open yields a handle (UDP socket, TLS context, HTTP connection or listener) phase 2 re-types; specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md");
  (("Udp.send_many", "udp_send_many"), "deferred to ocap phase 2: this open yields a handle (UDP socket, TLS context, HTTP connection or listener) phase 2 re-types; specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md");
]

let stdlib_dir () =
  let candidates = [ "stdlib"; "../stdlib"; "../../stdlib"; "../../../stdlib" ] in
  match List.find_opt (fun d -> Sys.file_exists (Filename.concat d "prelude.march"))
          candidates with
  | Some d -> d
  | None -> Filename.concat (Test_helpers.march_project_root ()) "stdlib"

let read_lines path =
  let ic = open_in_bin path in
  let rec go acc = match input_line ic with
    | l -> go (l :: acc)
    | exception End_of_file -> close_in ic; Array.of_list (List.rev acc) in
  go []

(* Every checkable declaration of a parsed file: its dotted name and span. *)
let units_of (m : March_ast.Ast.module_) : (string * March_ast.Ast.span) list =
  let open March_ast.Ast in
  let rec go prefix decls =
    List.concat_map (function
        | DFn (fd, sp) -> [ (prefix ^ fd.fn_name.txt, sp) ]
        | DActor (_, n, _, sp) -> [ (prefix ^ "actor " ^ n.txt, sp) ]
        | DImpl (im, sp) -> [ (prefix ^ "impl " ^ im.impl_iface.txt, sp) ]
        | DLet (_, _, sp) -> [ (prefix ^ "let", sp) ]
        | DMod (n, _, inner, _) -> go (prefix ^ n.txt ^ ".") inner
        | _ -> [])
      decls in
  go (m.mod_name.txt ^ ".") m.mod_decls

(* Whether [text] calls [name] (not a longer name, not a qualified one, not
   the definition `fn name(`). *)
let calls_name (text : string) (name : string) : bool =
  let re = Str.regexp ("\\(^\\|[^a-zA-Z0-9_.]\\)" ^ Str.quote name ^ "[ \t]*(") in
  let is_def pos =
    let before = String.sub text 0 (pos + 1) in
    let t = String.trim before in
    String.ends_with ~suffix:" fn" (" " ^ t) || String.ends_with ~suffix:" pfn" (" " ^ t) in
  let rec from i =
    match Str.search_forward re text i with
    | pos -> if is_def pos then from (pos + 1) else true
    | exception Not_found -> false in
  from 0

(* The declaration's code: its source lines minus `--` comment lines and
   the contents of doc strings (triple-quoted blocks), where a builtin named
   in prose would be a false positive. *)
let code_text (lines : string array) (sp : March_ast.Ast.span) : string =
  let buf = Buffer.create 1024 in
  let in_doc = ref false in
  for i = sp.start_line - 1 to min (Array.length lines - 1) (sp.end_line - 1) do
    let l = lines.(i) in
    let t = String.trim l in
    let triple = (try ignore (Str.search_forward (Str.regexp_string "\"\"\"") l 0); true
                  with Not_found -> false) in
    if !in_doc then (if triple then in_doc := false)
    else if triple then in_doc := true
    else if String.length t >= 2 && String.sub t 0 2 = "--" then ()
    else (Buffer.add_string buf l; Buffer.add_char buf '\n')
  done;
  Buffer.contents buf

let offenders () : (string * string) list =
  let dir = stdlib_dir () in
  let files =
    Sys.readdir dir |> Array.to_list
    |> List.filter (fun f -> Filename.check_suffix f ".march" && f <> "authority.march")
    |> List.sort compare in
  (* A call spelled like a builtin the stdlib shadows (`println` is the
     Prelude's, `random_bytes` Crypto's inside Crypto) reaches the stdlib
     function, which checks. *)
  let shadowed = March_typecheck.Io_ops_gen.shadowed_by_stdlib in
  let checked = List.filter_map (function
      | (n, Ops.Checked _) when not (List.mem n shadowed) -> Some n | _ -> None) Ops.table in
  List.concat_map (fun f ->
      let path = Filename.concat dir f in
      let lines = read_lines path in
      let m =
        let ic = open_in_bin path in
        let lexbuf = Lexing.from_channel ic in
        lexbuf.Lexing.lex_curr_p <- { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
        let m = March_parser.Parse.module_of_lexbuf lexbuf in
        close_in ic; m in
      List.concat_map (fun (u, sp) ->
          let text = code_text lines sp in
          if calls_name text "Authority.check" then []
          else List.filter_map (fun b -> if calls_name text b then Some (u, b) else None)
              checked)
        (units_of m))
    files

let test_every_operation_is_checked () =
  let found = offenders () in
  if Sys.getenv_opt "CAP_COVERAGE_PRINT" = Some "1" then
    List.iter (fun (u, b) -> Printf.printf "  ((%S, %S), \"\");\n" u b) found;
  let unlisted = List.filter (fun p -> not (List.mem_assoc p allowlist)) found in
  Alcotest.(check (list (pair string string)))
    "stdlib functions calling a checked builtin without Authority.check" [] unlisted

let test_allowlist_not_stale () =
  let found = offenders () in
  let stale = List.filter (fun p -> not (List.mem p found)) (List.map fst allowlist) in
  Alcotest.(check (list (pair string string))) "allowlist rows that no longer match" [] stale

(* A fixture function that reads the clock with no check is reported. *)
let test_detects_an_unchecked_call () =
  let lines = [| "  fn now_ms() : Int do"; "    unix_time_ms()"; "  end" |] in
  let sp = { March_ast.Ast.dummy_span with start_line = 1; end_line = 3 } in
  let text = code_text lines sp in
  Alcotest.(check bool) "unix_time_ms is seen" true (calls_name text "unix_time_ms");
  Alcotest.(check bool) "no Authority.check" false (calls_name text "Authority.check");
  Alcotest.(check bool) "System.unix_time_ms is not the raw builtin" false
    (calls_name "System.unix_time_ms()" "unix_time_ms");
  Alcotest.(check bool) "a definition is not a call" false
    (calls_name "  fn random_bytes(n) do\n" "random_bytes");
  Alcotest.(check bool) "a call after a definition is" true
    (calls_name "  pfn f(n) do\n    random_bytes(n)\n" "random_bytes")

let tests =
  [
    Alcotest.test_case "every stdlib capability operation is checked" `Quick
      test_every_operation_is_checked;
    Alcotest.test_case "allowlist is not stale" `Quick test_allowlist_not_stale;
    Alcotest.test_case "detects an unchecked call" `Quick test_detects_an_unchecked_call;
  ]
