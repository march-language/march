(** Secret-safe subprocess runner for forge/tasks/forge_registry.march — the client
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

(** Compile the embedded registry.march source to a temp binary. No secrets
    are involved in compilation, so a plain [Sys.command] shell string is
    fine here (unlike execution, below). Returns the binary's path, or
    [Error] with the compiler's exit code if compilation fails.

    MUST be compiled, not interpreted: the interpreter's `Tls.*` builtins
    (`lib/eval/eval.ml`) are hardcoded stubs for unit-testing the March
    wrapping logic only (`tls_connect` returns a fake handle, `tls_write`
    always reports success without touching a socket, `tls_read` always
    returns `Ok("")`) — real TLS runs exclusively through `runtime/march_tls.c`
    in a compiled binary. Two real compiler/runtime bugs previously made
    compiled TLS unusable against a real remote server and were fixed
    alongside this plan: (1) `runtime/march_tls.c`'s client `SSL_CTX` never
    set `SSL_MODE_AUTO_RETRY`, so `SSL_read` could return early after
    consuming a TLS 1.3 post-handshake record (e.g. a session ticket) before
    any application data arrived; (2) `lib/tir/llvm_builtins.ml` misdeclared
    `tls_write`'s return type as `TUnit` instead of `Result(Int, String)` —
    the C function actually returns a heap-allocated Result pointer, and the
    type mismatch corrupted the compiled backend's handling of it, SIGSEGVing
    deterministically. Both fixed and verified against a real `forgepm.org`
    round-trip before this function was switched from interpreted back to
    compiled. *)
let compile_registry_task tmp_src =
  let out = Filename.temp_file "forge_registry_bin_" "" in
  let march = find_march () in
  let stdlib_env =
    match Archive_store.find_stdlib_dir () with
    | None -> ""
    | Some p -> Printf.sprintf "MARCH_STDLIB=%s " (Filename.quote p)
  in
  let cmd = Printf.sprintf "%s%s --compile -o %s %s"
      stdlib_env (Filename.quote march) (Filename.quote out) (Filename.quote tmp_src) in
  let rc = Sys.command cmd in
  if rc <> 0 then Error rc else Ok out

(** Compile the embedded registry.march client to a fresh temp binary and
    return its path.  Used by `forge deps` to compile the client ONCE and then
    run the `fetch` action many times (metadata + tarball downloads) against
    the same binary, instead of recompiling per URL.  Caller owns the returned
    binary and is responsible for removing it (and the temp source). *)
let compile_client () =
  let tmp_src = write_temp Registry_march_src.content ".march" in
  match compile_registry_task tmp_src with
  | Error rc ->
    (try Sys.remove tmp_src with Sys_error _ -> ());
    Error rc
  | Ok binary ->
    (try Unix.chmod binary 0o755 with Unix.Unix_error _ -> ());
    (try Sys.remove tmp_src with Sys_error _ -> ());
    Ok binary

(** Build the child env array for a `fetch` action of a pre-compiled client
    ([compile_client]).  GETs [url] over native HTTP/TLS and writes the raw
    body to [out].  Returned as a full env array (inherited env + our vars)
    ready for [Unix.create_process_env]; secrets are irrelevant for reads. *)
let fetch_env ~url ~out =
  let stdlib_env =
    match Archive_store.find_stdlib_dir () with
    | None -> []
    | Some p -> [ "MARCH_STDLIB=" ^ p ]
  in
  let base_env =
    [ "FORGE_ACTION=fetch";
      "FORGE_URL=" ^ url;
      "FORGE_OUT=" ^ out ]
    @ stdlib_env
  in
  Array.append (Unix.environment ()) (Array.of_list base_env)

(** Run the embedded registry.march task with FORGE_ACTION=<action> and the
    given env vars. Returns the subprocess's exit code (0/1/2/3/4/5 per
    registry.march's own convention — see this plan's Global Constraints).
    `token` and every value in `extra_env` are passed ONLY via the child's
    environment array, never via argv or a shell string. *)
let run_action ~action ~token ~registry ~pkg_dir ~extra_env =
  let tmp_src = write_temp Registry_march_src.content ".march" in
  match compile_registry_task tmp_src with
  | Error _rc ->
    (try Sys.remove tmp_src with Sys_error _ -> ());
    1 (* client/config-class failure: our own embedded client failed to compile *)
  | Ok binary ->
    (try Unix.chmod binary 0o755 with Unix.Unix_error _ -> ());
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
    (* argv is just [binary] — no secrets, ever. The child inherits our real
       stdin/stdout/stderr fds directly. *)
    let pid =
      Unix.create_process_env binary [| binary |] env
        Unix.stdin Unix.stdout Unix.stderr
    in
    let (_, status) = Unix.waitpid [] pid in
    (try Sys.remove tmp_src with Sys_error _ -> ());
    (try Sys.remove binary with Sys_error _ -> ());
    (match status with
     | Unix.WEXITED n -> n
     | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> 3 (* treat a crashed child as a transport-class failure *))
