(** Secret-safe subprocess runner for forge/tasks/registry.march — the client
    that speaks forgepm's publish/retire HTTP API (see
    forgepm/specs/forge-publish-client.md). The API token must never appear
    in a shell command string or the child process's argv (both are visible
    via `ps` to any local user) — only in the child's environment block, via
    Unix.create_process_env's explicit env parameter. The child inherits our
    own stdin/stdout/stderr file descriptors directly (no pipes), so
    registry.march's own println output reaches the terminal as-is and there
    is no risk of the classic two-pipe read deadlock a naive pipe-capture
    implementation could hit. *)

let write_temp content suffix =
  let tmp = Filename.temp_file "forge_registry_" suffix in
  let oc = open_out tmp in
  output_string oc content;
  close_out oc;
  tmp

let find_march () =
  let exe_dir = Filename.dirname Sys.executable_name in
  let sibling = Filename.concat exe_dir "march" in
  if Sys.file_exists sibling then sibling else "march"

(** HTTPS-by-default gate (Global Constraints / spec §8). Called before any
    network action. `insecure` is true when the caller passed --insecure or
    set FORGE_INSECURE=1. *)
let validate_registry_url ~registry ~insecure =
  match String.length registry >= 7 && String.sub registry 0 7 = "http://" with
  | true when not insecure ->
    Error (Printf.sprintf
      "refusing to use insecure registry %s without --insecure (or FORGE_INSECURE=1)"
      registry)
  | _ ->
    if String.length registry >= 8 && String.sub registry 0 8 = "https://" then Ok ()
    else if String.length registry >= 7 && String.sub registry 0 7 = "http://" then Ok () (* insecure=true, already allowed above *)
    else Error (Printf.sprintf "registry URL must start with http:// or https://: %s" registry)

(** Run the embedded registry.march task with FORGE_ACTION=<action> and the
    given env vars. Returns the subprocess's exit code (0/1/2/3/4/5 per
    registry.march's own convention — see this plan's Global Constraints).
    `token` and every value in `extra_env` are passed ONLY via the child's
    environment array, never via argv or a shell string. *)
let run_action ~action ~token ~registry ~pkg_dir ~extra_env =
  let tmp = write_temp Registry_march_src.content ".march" in
  let march = find_march () in
  let stdlib_env =
    match Archive_store.find_stdlib_dir () with
    | None -> []
    | Some p -> [ "MARCH_STDLIB=" ^ p ]
  in
  let base_env =
    [ "FORGE_ACTION=" ^ action;
      "FORGE_TOKEN=" ^ token;
      "FORGE_REGISTRY=" ^ registry;
      "FORGE_PKG_DIR=" ^ pkg_dir ]
    @ List.map (fun (k, v) -> k ^ "=" ^ v) extra_env
    @ stdlib_env
  in
  let env = Array.append (Unix.environment ()) (Array.of_list base_env) in
  (* argv is just [march_binary; tmp_file_path] — no secrets, ever. The child
     inherits our real stdin/stdout/stderr fds directly. *)
  let pid =
    Unix.create_process_env march [| march; tmp |] env
      Unix.stdin Unix.stdout Unix.stderr
  in
  let (_, status) = Unix.waitpid [] pid in
  (try Sys.remove tmp with Sys_error _ -> ());
  match status with
  | Unix.WEXITED n -> n
  | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> 3 (* treat a crashed child as a transport-class failure *)
