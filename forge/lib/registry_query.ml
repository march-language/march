(** Registry query helpers — compile the registry client, fetch a package's
    metadata, and parse its available versions.  Extracted so `forge outdated`
    (and, later, a deduplicated `forge deps`) can share one implementation.

    The registry client is a small March program (`tasks/forge_registry.march`)
    compiled to a native binary because native TLS only works compiled; each
    fetch runs that binary with the target URL + output path in its env. *)

type reg_version = { rv_version : string; rv_checksum : string; rv_retired : bool }

(** Registry base URL: [FORGE_REGISTRY] env var, else the public default. *)
let registry_base_url () =
  match Sys.getenv_opt "FORGE_REGISTRY" with
  | Some r when r <> "" -> r
  | _ -> "https://forgepm.org"

let no_trailing_slash s =
  let n = String.length s in
  if n > 0 && s.[n - 1] = '/' then String.sub s 0 (n - 1) else s

let metadata_url ~base name =
  Printf.sprintf "%s/api/v1/packages/%s" (no_trailing_slash base) name

let read_whole path =
  try
    let ic = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
      let n = in_channel_length ic in
      let b = Bytes.create n in
      really_input ic b 0 n;
      Bytes.to_string b)
  with Sys_error _ -> ""

(** Run [prog] with [args]/[env], killing its process group on [timeout]. *)
let run_with_timeout ~timeout ~prog ~args ~env =
  let pid = Unix.fork () in
  if pid = 0 then begin
    (try ignore (Unix.setsid ()) with Unix.Unix_error _ -> ());
    (try Unix.execve prog (Array.of_list (prog :: args)) env
     with _ -> exit 127)
  end;
  let deadline = Unix.gettimeofday () +. timeout in
  let rec wait () =
    match Unix.waitpid [ Unix.WNOHANG ] pid with
    | 0, _ ->
      if Unix.gettimeofday () >= deadline then begin
        (try Unix.kill (- pid) Sys.sigkill with Unix.Unix_error _ -> ());
        (try ignore (Unix.waitpid [] pid) with Unix.Unix_error _ -> ());
        `Timeout
      end else begin
        ignore (Unix.select [] [] [] 0.05);
        wait ()
      end
    | _, Unix.WEXITED n   -> `Exited n
    | _, Unix.WSIGNALED n -> `Signaled n
    | _, Unix.WSTOPPED _  -> wait ()
  in
  (try wait ()
   with Unix.Unix_error (Unix.ECHILD, _, _) -> `Exited 0)

(** Compile the registry client to a temp native binary; returns its path. *)
let compile_client () =
  let tmp_src =
    let t = Filename.temp_file "forge_registry_" ".march" in
    let oc = open_out t in
    output_string oc Registry_march_src.content; close_out oc; t
  in
  let stdlib_pfx =
    match Archive_store.find_stdlib_dir () with
    | None -> ""
    | Some p -> Printf.sprintf "MARCH_STDLIB=%s " (Filename.quote p)
  in
  let march =
    let exe_dir = Filename.dirname Sys.executable_name in
    let sibling = Filename.concat exe_dir "march" in
    if Sys.file_exists sibling then sibling else "march"
  in
  let out = Filename.temp_file "forge_registry_bin_" "" in
  let toolchain_pfx = match Toolchain.path_prefix () with Ok p -> p | Error _ -> "" in
  let cmd = Printf.sprintf "%s%s%s --compile -o %s %s"
      toolchain_pfx stdlib_pfx (Filename.quote march)
      (Filename.quote out) (Filename.quote tmp_src) in
  let env = Unix.environment () in
  let res = run_with_timeout ~timeout:180.0 ~prog:"/bin/sh" ~args:["-c"; cmd] ~env in
  (try Sys.remove tmp_src with Sys_error _ -> ());
  match res with
  | `Exited 0 when Sys.file_exists out ->
    (try Unix.chmod out 0o755 with Unix.Unix_error _ -> ());
    Ok out
  | `Timeout -> Error "registry client compilation timed out"
  | _ -> Error "registry client failed to compile"

(** Fetch [url] to [out] by running the compiled client [binary]. *)
let fetch ~binary ~url ~out =
  let env = Registry_client.fetch_env ~url ~out in
  match run_with_timeout ~timeout:30.0 ~prog:binary ~args:[] ~env with
  | `Exited 0 -> Ok ()
  | `Exited 4 -> Error (Printf.sprintf "registry returned HTTP 4xx for %s" url)
  | `Exited 3 -> Error (Printf.sprintf "transport error fetching %s" url)
  | `Exited n -> Error (Printf.sprintf "fetch of %s failed (exit %d)" url n)
  | `Signaled n -> Error (Printf.sprintf "fetch of %s killed by signal %d" url n)
  | `Timeout -> Error (Printf.sprintf "fetch of %s timed out" url)

(** Extract a top-level string value for [key] from flat registry JSON. *)
let json_str_after body key =
  let needle = Printf.sprintf "\"%s\":" key in
  let nl = String.length needle and bl = String.length body in
  let rec find i =
    if i + nl > bl then None
    else if String.sub body i nl = needle then Some (i + nl)
    else find (i + 1)
  in
  match find 0 with
  | None -> None
  | Some j ->
    let j = ref j in
    while !j < bl && (body.[!j] = ' ' || body.[!j] = '\t') do incr j done;
    if !j >= bl || body.[!j] <> '"' then None
    else begin
      incr j;
      let start = !j in
      while !j < bl && body.[!j] <> '"' do incr j done;
      Some (String.sub body start (!j - start))
    end

(** Parse the `versions` array of package metadata into [reg_version]s. *)
let parse_versions body =
  let marker = "\"versions\":" in
  let ml = String.length marker and bl = String.length body in
  let rec find i =
    if i + ml > bl then None
    else if String.sub body i ml = marker then Some (i + ml)
    else find (i + 1)
  in
  match find 0 with
  | None -> []
  | Some j ->
    let j = ref j in
    while !j < bl && body.[!j] <> '[' do incr j done;
    if !j >= bl then []
    else begin
      incr j;  (* past '[' *)
      let objs = ref [] in
      let depth = ref 0 in
      let obj_start = ref (-1) in
      let stop = ref false in
      while not !stop && !j < bl do
        (match body.[!j] with
         | '{' -> if !depth = 0 then obj_start := !j; incr depth
         | '}' ->
           decr depth;
           if !depth = 0 && !obj_start >= 0 then begin
             objs := String.sub body !obj_start (!j - !obj_start + 1) :: !objs;
             obj_start := -1
           end
         | ']' when !depth = 0 -> stop := true
         | _ -> ());
        incr j
      done;
      List.filter_map (fun obj ->
          match json_str_after obj "version", json_str_after obj "checksum" with
          | Some v, Some c ->
            let retired =
              let m = "\"retired\":" in
              let rec has i =
                if i + String.length m > String.length obj then false
                else if String.sub obj i (String.length m) = m then
                  let rest = String.sub obj (i + String.length m)
                      (String.length obj - i - String.length m) in
                  String.length (String.trim rest) >= 4
                  && String.sub (String.trim rest) 0 4 = "true"
                else has (i + 1)
              in has 0
            in
            Some { rv_version = v; rv_checksum = c; rv_retired = retired }
          | _ -> None
        ) (List.rev !objs)
    end

(** High-level: fetch and parse a package's available versions from [registry]
    using the already-compiled client [binary]. *)
let available_versions ~binary ~registry name =
  let tmp = Filename.temp_file "forge_meta_" ".json" in
  Fun.protect ~finally:(fun () -> try Sys.remove tmp with Sys_error _ -> ())
    (fun () ->
      match fetch ~binary ~url:(metadata_url ~base:registry name) ~out:tmp with
      | Error e -> Error e
      | Ok () -> Ok (parse_versions (read_whole tmp)))
