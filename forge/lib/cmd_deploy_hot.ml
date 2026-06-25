(** forge deploy hot — CAS-native, ed25519-signed hot code replacement.

    Flow:
      1. Load forge.toml + [hot-reload] config
      2. Build with --compile-so  → <output>.so + <output>.so.hcr_manifest
      3. Open SSH tunnel to the server's Unix socket
      4. VERSIONS — detect crash-restart drift
      5. ABI_QUERY — get current (id, name, impl_hash, sig_hash) per slot
      6. Read manifest — new (name → impl_hash, sig_hash)
      7. Set-diff — find names where new impl_hash ≠ current impl_hash
      8. CAS_CHECK + CAS_PUT the .so artifact  (if any function changed)
      9. Sign + ACTIVATE each changed function
     10. Report
*)

open Unix

(* ─── Manifest parsing ───────────────────────────────────────────────────── *)

type fn_manifest = {
  fn_name      : string;
  fn_impl_hash : string;
  fn_sig_hash  : string;
}

type manifest = {
  cas_hash  : string;
  functions : fn_manifest list;
}

let parse_manifest path : (manifest, string) result =
  try
    let ic = open_in path in
    let cas_hash = ref "" in
    let fns = ref [] in
    (try while true do
       let line = String.trim (input_line ic) in
       if String.length line = 0 || line.[0] = '#' then begin
         (* # cas_hash <hex> *)
         if String.length line > 10 && String.sub line 0 10 = "# cas_hash" then
           cas_hash := String.trim (String.sub line 10 (String.length line - 10))
       end else begin
         match String.split_on_char ' ' line with
         | [name; impl_h; sig_h] ->
           fns := { fn_name = name; fn_impl_hash = impl_h; fn_sig_hash = sig_h } :: !fns
         | [name; impl_h] ->
           fns := { fn_name = name; fn_impl_hash = impl_h; fn_sig_hash = "" } :: !fns
         | _ -> ()  (* skip malformed lines *)
       end
     done with End_of_file -> ());
    close_in ic;
    if !cas_hash = "" then Error (path ^ ": missing # cas_hash line")
    else Ok { cas_hash = !cas_hash; functions = List.rev !fns }
  with Sys_error m -> Error m

(* ─── Socket I/O ─────────────────────────────────────────────────────────── *)

type conn = {
  fd  : file_descr;
  buf : Buffer.t;
}

let conn_of_fd fd = { fd; buf = Buffer.create 256 }

let send_line conn s =
  let msg = s ^ "\n" in
  let rec loop off remaining =
    if remaining > 0 then
      let n = write conn.fd (Bytes.of_string msg) off remaining in
      loop (off + n) (remaining - n)
  in
  loop 0 (String.length msg)

let recv_line conn =
  let rec loop () =
    match Buffer.contents conn.buf |> String.split_on_char '\n' with
    | line :: rest when String.length line > 0 ->
      let rest_str = String.concat "\n" rest in
      Buffer.clear conn.buf;
      Buffer.add_string conn.buf rest_str;
      line
    | _ ->
      let tmp = Bytes.create 4096 in
      let n = read conn.fd tmp 0 4096 in
      if n = 0 then failwith "connection closed";
      Buffer.add_subbytes conn.buf tmp 0 n;
      loop ()
  in
  loop ()

let send_binary conn data offset len =
  let rec loop off remaining =
    if remaining > 0 then begin
      let n = write conn.fd data off remaining in
      loop (off + n) (remaining - n)
    end
  in
  loop offset len

(* ─── SHA-256 via digestif for CAS hash of the .so ─────────────────────── *)

let sha256_file path =
  let ic = open_in_bin path in
  let ctx = Digestif.SHA256.empty in
  let buf = Bytes.create 65536 in
  let ctx = ref ctx in
  (try while true do
     let n = input ic buf 0 65536 in
     if n = 0 then raise Exit;
     ctx := Digestif.SHA256.feed_bytes !ctx (Bytes.sub buf 0 n)
   done with Exit | End_of_file -> ());
  close_in ic;
  Digestif.SHA256.get !ctx |> Digestif.SHA256.to_hex

(* ─── SSH tunnel ─────────────────────────────────────────────────────────── *)

let open_tunnel ~ssh_host ~remote_socket ~local_socket =
  let pid = Unix.create_process "ssh"
    [| "ssh"; "-N"; "-o"; "StrictHostKeyChecking=no"; "-o"; "ExitOnForwardFailure=yes";
       "-L"; Printf.sprintf "%s:%s" local_socket remote_socket;
       ssh_host |]
    Unix.stdin Unix.stdout Unix.stderr
  in
  (* Wait for the tunnel socket to appear (up to 5 seconds). *)
  let ready = ref false in
  for i = 1 to 50 do
    if not !ready then begin
      Unix.sleepf 0.1;
      if Sys.file_exists local_socket then ready := true
      else if i = 50 then
        Printf.eprintf "forge deploy hot: warning: tunnel socket not appearing after 5s\n%!"
    end
  done;
  (pid, local_socket)

let close_tunnel pid local_socket =
  (try Unix.kill pid Sys.sigterm with Unix_error _ -> ());
  (try Unix.waitpid [] pid |> ignore with Unix_error _ -> ());
  (try Sys.remove local_socket with Sys_error _ -> ())

let connect_socket path =
  let fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  let addr = Unix.ADDR_UNIX path in
  Unix.connect fd addr;
  fd

(* ─── Protocol helpers ───────────────────────────────────────────────────── *)

(** Parse ABI_QUERY response lines.
    Each line: SLOT <id> <name> <impl_hash> <sig_hash> *)
type slot = {
  slot_id        : int;
  slot_name      : string;
  slot_impl_hash : string;
  slot_sig_hash  : string;
}

let parse_abi_query conn =
  let slots = ref [] in
  let rec loop () =
    let line = recv_line conn in
    if line = "END" then List.rev !slots
    else begin
      (match String.split_on_char ' ' line with
       | ["SLOT"; id_s; name; impl_h; sig_h] ->
         (match int_of_string_opt id_s with
          | Some id ->
            slots := { slot_id = id; slot_name = name;
                       slot_impl_hash = impl_h; slot_sig_hash = sig_h } :: !slots
          | None -> ())
       | _ -> ());
      loop ()
    end
  in
  loop ()

(** Parse VERSIONS response. Returns list of (name, baseline, current_or_none). *)
type version_entry = {
  ve_name     : string;
  ve_baseline : string;
  ve_current  : string option;  (* Some h when hot ≠ baseline *)
}

let parse_versions conn =
  let entries = ref [] in
  let rec loop () =
    let line = recv_line conn in
    if line = "END" then List.rev !entries
    else begin
      (match String.split_on_char ' ' line with
       | ["VERSION"; name; "baseline"; h] ->
         entries := { ve_name = name; ve_baseline = h; ve_current = None } :: !entries
       | ["VERSION"; name; "hot"; h] ->
         (* Update the last entry with the hot hash *)
         entries := (match !entries with
           | e :: rest when e.ve_name = name -> { e with ve_current = Some h } :: rest
           | _ -> !entries)
       | _ -> ());
      loop ()
    end
  in
  loop ()

(* ─── CAS operations ─────────────────────────────────────────────────────── *)

let cas_check conn hash =
  send_line conn (Printf.sprintf "CAS_CHECK %s" hash);
  let resp = recv_line conn in
  resp = "PRESENT"

let cas_put conn hash path =
  let size = (Unix.stat path).Unix.st_size in
  send_line conn (Printf.sprintf "CAS_PUT %s %d" hash size);
  let resp = recv_line conn in
  if resp <> "READY" then
    failwith (Printf.sprintf "CAS_PUT: server not ready: %s" resp);
  (* Stream the file *)
  let ic = open_in_bin path in
  let buf = Bytes.create 65536 in
  (try while true do
     let n = input ic buf 0 65536 in
     if n = 0 then raise Exit;
     send_binary conn buf 0 n
   done with Exit | End_of_file -> ());
  close_in ic;
  let final = recv_line conn in
  if not (String.length final >= 2 && String.sub final 0 2 = "OK") then
    failwith (Printf.sprintf "CAS_PUT failed: %s" final)

(* ─── Main deploy flow ───────────────────────────────────────────────────── *)

(* Check if a symbol is exported from a shared library (for migrate_state presence check). *)
let so_exports_symbol (so_path : string) (sym : string) : bool =
  let cmd = Printf.sprintf "nm -D %s 2>/dev/null | grep -q ' T %s$'" so_path sym in
  Sys.command cmd = 0

let run ~ssh_host ~remote_socket ~signing_pubkey ~sk ~manifest ~so_path
    ?(old_schemas_path="") ?(new_schemas_path="") () =
  let local_socket = Printf.sprintf "/tmp/march_deploy_%d.sock" (Unix.getpid ()) in

  (* 1. SSH tunnel *)
  Printf.printf "Connecting to %s via SSH...\n%!" ssh_host;
  let (tunnel_pid, _) = open_tunnel ~ssh_host ~remote_socket ~local_socket in

  let result =
    (try
      let fd = connect_socket local_socket in
      let conn = conn_of_fd fd in

      (* 2. VERSIONS — drift check *)
      send_line conn "VERSIONS";
      let versions = parse_versions conn in
      let drifted = List.filter (fun ve -> ve.ve_current <> None) versions in
      if drifted <> [] then begin
        Printf.printf "WARNING: crash-restart drift detected in %d function(s):\n" (List.length drifted);
        List.iter (fun ve ->
          Printf.printf "  %s: baseline=%s, running=%s\n"
            ve.ve_name ve.ve_baseline (Option.value ~default:"?" ve.ve_current)
        ) drifted
      end;

      (* 3. ABI_QUERY — current slot state *)
      send_line conn "ABI_QUERY";
      let slots = parse_abi_query conn in
      let slot_map = Hashtbl.create 16 in
      List.iter (fun s -> Hashtbl.replace slot_map s.slot_name s) slots;

      (* 4. Set-diff: functions where new impl_hash ≠ current *)
      let to_activate = List.filter (fun fm ->
        match Hashtbl.find_opt slot_map fm.fn_name with
        | None -> false  (* not registered on server yet — skip *)
        | Some slot -> slot.slot_impl_hash <> fm.fn_impl_hash
      ) manifest.functions in

      if to_activate = [] then begin
        Printf.printf "No changes detected — server is already up to date.\n%!";
        Unix.close fd;
        Ok 0
      end else begin
        Printf.printf "Deploying %d changed function(s)...\n%!" (List.length to_activate);

        (* 5. sig_hash safety gate: new sig_hash must match old sig_hash (no ABI breaks).
           Exception: actor dispatch functions whose state schema changed AND whose actor
           exports a __migrate_<Actor> symbol are allowed to have a different sig_hash —
           the state migration path handles the ABI change safely. *)
        let dispatch_suffix = "_dispatch" in
        let has_migrate_exemption (fn_name : string) : bool =
          (* fn_name pattern: "Module.ActorName_dispatch" or "ActorName_dispatch" *)
          let base = match String.rindex_opt fn_name '.' with
            | Some i -> String.sub fn_name (i+1) (String.length fn_name - i - 1)
            | None   -> fn_name
          in
          let dlen = String.length dispatch_suffix in
          if String.length base > dlen &&
             String.sub base (String.length base - dlen) dlen = dispatch_suffix
          then begin
            let actor_name = String.sub base 0 (String.length base - dlen) in
            so_exports_symbol so_path ("__migrate_" ^ actor_name)
          end else false
        in
        let abi_violations = List.filter (fun fm ->
          match Hashtbl.find_opt slot_map fm.fn_name with
          | None -> false
          | Some slot ->
            slot.slot_sig_hash <> "" && fm.fn_sig_hash <> "" &&
            slot.slot_sig_hash <> fm.fn_sig_hash &&
            not (has_migrate_exemption fm.fn_name)
        ) to_activate in
        if abi_violations <> [] then begin
          Printf.eprintf "error: ABI mismatch — sig_hash changed for:\n";
          List.iter (fun fm ->
            let old_sig = (Hashtbl.find slot_map fm.fn_name).slot_sig_hash in
            Printf.eprintf "  %s: old=%s new=%s\n" fm.fn_name old_sig fm.fn_sig_hash
          ) abi_violations;
          Unix.close fd;
          Error "ABI mismatch — refusing to deploy"
        end else begin
          (* 6. CAS_PUT the .so if not already present *)
          let cas_hash = manifest.cas_hash in
          if not (cas_check conn cas_hash) then begin
            Printf.printf "Uploading artifact %s...\n%!" so_path;
            cas_put conn cas_hash so_path;
            Printf.printf "Artifact uploaded.\n%!"
          end else
            Printf.printf "Artifact already on server (cache hit).\n%!";

          (* Phase 5: load actor state schemas for compat checking and migrate_required flag *)
          let old_schemas =
            if old_schemas_path <> "" then Schema_diff.parse_schemas_file old_schemas_path
            else []
          in
          let new_schemas =
            if new_schemas_path <> "" then Schema_diff.parse_schemas_file new_schemas_path
            else []
          in
          let actor_diffs = Schema_diff.diff_schemas old_schemas new_schemas in

          (* Abort if any actor has a compat violation and no migrate_state is present *)
          let compat_errors = List.filter_map (fun d ->
              let compat = match List.assoc_opt d.Schema_diff.actor new_schemas with
                | Some s -> s.Schema_diff.compat | None -> "full" in
              match Schema_diff.check_compat compat d.Schema_diff.changes with
              | Ok () -> None
              | Error msg ->
                let actor_mangled = String.map (fun c -> if c = '.' then '_' else c)
                    d.Schema_diff.actor in
                let migrate_sym = "__migrate_" ^ actor_mangled in
                if so_exports_symbol so_path migrate_sym then None
                else Some (d.Schema_diff.actor, msg)
            ) actor_diffs
          in
          if compat_errors <> [] then begin
            List.iter (fun (actor, msg) ->
              Printf.eprintf "forge deploy hot: actor %s — %s\n" actor msg
            ) compat_errors;
            Printf.eprintf "Provide a migrate_state function or add @compat annotation.\n";
            Unix.close fd;
            raise (Failure "compat violation — deploy aborted")
          end;

          (* 7. Sign + ACTIVATE each changed function *)
          let _ = signing_pubkey in  (* public key already embedded in server binary *)
          let activated = ref 0 in
          let failed = ref 0 in
          List.iter (fun fm ->
            (* Phase 5: determine migrate_required for actor dispatch functions *)
            let dispatch_suffix = "_dispatch" in
            let dlen = String.length dispatch_suffix in
            let flen = String.length fm.fn_name in
            let migrate_required =
              if flen > dlen && String.sub fm.fn_name (flen - dlen) dlen = dispatch_suffix
              then
                let actor_name = String.sub fm.fn_name 0 (flen - dlen) in
                match List.find_opt (fun d -> d.Schema_diff.actor = actor_name) actor_diffs with
                | None -> 0
                | Some d ->
                  let compat = match List.assoc_opt actor_name new_schemas with
                    | Some s -> s.Schema_diff.compat | None -> "full" in
                  (match Schema_diff.check_compat compat d.Schema_diff.changes with
                  | Ok () ->
                    if Schema_diff.requires_migration d.Schema_diff.changes then 1 else 0
                  | Error _ -> 1)
              else 0
            in
            let msg = Printf.sprintf "%s %s %s" fm.fn_name fm.fn_impl_hash cas_hash in
            let sig_bytes = March_ed25519.Ed25519.sign_str msg sk in
            let sig_b64 = March_ed25519.Ed25519.sig_to_base64 sig_bytes in
            let cmd = Printf.sprintf "ACTIVATE %s %s %s %s %d"
              fm.fn_name fm.fn_impl_hash cas_hash sig_b64 migrate_required in
            send_line conn cmd;
            let resp = recv_line conn in
            if String.length resp >= 2 && String.sub resp 0 2 = "OK" then begin
              Printf.printf "  activated: %s\n%!" fm.fn_name;
              incr activated
            end else begin
              Printf.eprintf "  FAILED %s: %s\n%!" fm.fn_name resp;
              incr failed
            end
          ) to_activate;

          Unix.close fd;

          if !failed = 0 then begin
            Printf.printf "Deploy complete: %d function(s) activated.\n%!" !activated;
            Ok !activated
          end else
            Error (Printf.sprintf "%d function(s) failed to activate" !failed)
        end
      end
    with
    | Failure m -> Error m
    | Unix_error (e, fn, _) ->
      Error (Printf.sprintf "%s: %s" fn (Unix.error_message e)))
  in
  close_tunnel tunnel_pid local_socket;
  result

(* ─── Build step ─────────────────────────────────────────────────────────── *)

let build_so ~proj ~output : (string * string, string) result =
  let so_path = output ^ ".so" in
  let manifest_path = output ^ ".so.hcr_manifest" in
  let lib_env = Cmd_build.lib_path_env proj in
  let ffi_flags = Cmd_build.ffi_flags_of ~root:proj.Project.root proj in
  let entry = match proj.Project.entrypoint with
    | Some e -> Filename.concat proj.Project.root e
    | None ->
      let src = Filename.concat proj.Project.root "src" in
      Filename.concat src (proj.Project.name ^ ".march")
  in
  let cmd = Printf.sprintf
    "%smarch --compile --compile-so -o %s%s %s"
    lib_env (Filename.quote so_path) ffi_flags (Filename.quote entry)
  in
  let rc = Sys.command cmd in
  if rc <> 0 then Error (Printf.sprintf "build failed (exit %d)" rc)
  else if not (Sys.file_exists manifest_path) then
    Error (Printf.sprintf "no manifest at %s — rebuild with a hot-reload enabled compiler" manifest_path)
  else
    Ok (so_path, manifest_path)

(* ─── Entry point ────────────────────────────────────────────────────────── *)

(** [deploy ~so ~output ()] deploys a hot-reload artifact.
    When [so] is non-empty, it is used as the pre-built .so (the build step is
    skipped).  This allows cross-compiled artifacts (e.g. built in Docker for
    a remote Linux host) to be deployed without a local rebuild. *)
let deploy ?(output="") ?(so="") () : (unit, string) result =
  (* Load project *)
  match Project.load () with
  | Error m -> Error m
  | Ok proj ->
    match proj.Project.hot_reload with
    | None -> Error "no [hot-reload] section in forge.toml — add ssh_host, socket, public_key"
    | Some hr ->
      if hr.Project.hr_ssh_host = "" then
        Error "[hot-reload] ssh_host is required"
      else begin
        (* Load signing secret key *)
        match Cmd_hot_reload.read_sk_raw () with
        | Error m -> Error m
        | Ok sk ->
          let (so_path, manifest_path) =
            if so <> "" then
              (* Pre-built artifact supplied: manifest is <so>.hcr_manifest *)
              (so, so ^ ".hcr_manifest")
            else begin
              let out = if output <> "" then output
                else Filename.concat (Filename.concat proj.Project.root ".march")
                       (proj.Project.name ^ "_hot") in
              (out ^ ".so", out ^ ".so.hcr_manifest")
            end
          in
          let result =
            if so <> "" then begin
              (* Skip build — use pre-built .so *)
              if not (Sys.file_exists so_path) then
                Error (Printf.sprintf "pre-built .so not found: %s" so_path)
              else if not (Sys.file_exists manifest_path) then
                Error (Printf.sprintf "manifest not found: %s" manifest_path)
              else
                Ok (so_path, manifest_path)
            end else begin
              Printf.printf "Building hot-reload .so for %s...\n%!" proj.Project.name;
              build_so ~proj ~output:(if output <> "" then output
                else Filename.concat (Filename.concat proj.Project.root ".march")
                       (proj.Project.name ^ "_hot"))
            end
          in
          match result with
          | Error m -> Error m
          | Ok (so_path2, manifest_path2) ->
            (* Parse manifest *)
            match parse_manifest manifest_path2 with
            | Error m -> Error m
            | Ok manifest ->
              let signing_pubkey = Option.value ~default:"" hr.Project.hr_public_key in
              (* Phase 5: compute schema paths for compat checking.
                 new_schemas = <so>.schemas.json; old_schemas = last deployed schemas file.
                 After a successful deploy, write new schemas as the "prev" baseline. *)
              let new_schemas_path = so_path2 ^ ".schemas.json" in
              let prev_schemas_path = Filename.concat
                  (Filename.concat proj.Project.root ".march")
                  (proj.Project.name ^ "_hot.so.schemas.json.prev") in
              let result2 =
                run
                  ~ssh_host:hr.Project.hr_ssh_host
                  ~remote_socket:hr.Project.hr_socket
                  ~signing_pubkey
                  ~sk
                  ~manifest
                  ~so_path:so_path2
                  ~old_schemas_path:prev_schemas_path
                  ~new_schemas_path
                  ()
              in
              (* After successful deploy, save new schemas as the baseline for next time *)
              (match result2 with
              | Ok _ when Sys.file_exists new_schemas_path ->
                (try
                  let ic = open_in new_schemas_path in
                  let content = In_channel.input_all ic in
                  close_in ic;
                  (* Ensure the .march directory exists before writing *)
                  let march_dir = Filename.dirname prev_schemas_path in
                  (if not (Sys.file_exists march_dir) then
                    try Unix.mkdir march_dir 0o755 with Unix_error _ -> ());
                  let oc = open_out prev_schemas_path in
                  output_string oc content;
                  close_out oc
                with Sys_error _ -> ())
              | _ -> ());
              result2 |> Result.map ignore
      end
