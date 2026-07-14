(** forge deps — resolve and install project dependencies

    Current implementation handles all dep types:
      - RegistryDep  : placeholder (registry not yet built)
      - GitTagDep    : clones the tag
      - GitBranchDep : clones the branch, locks to a commit SHA
      - GitRevDep    : clones at the exact rev
      - PathDep      : verifies the path exists

    The lockfile (forge.lock) is written after resolution with the
    resolved commit SHAs and placeholder content hashes.
    Drift detection warns when forge.toml changes without re-running
    `forge deps`.
*)

let home_dir () =
  try Sys.getenv "HOME"
  with Not_found -> failwith "HOME not set"

let cas_deps_dir () =
  Filename.concat (home_dir ())
    (Filename.concat ".march" (Filename.concat "cas" "deps"))

(* ------------------------------------------------------------------ *)
(*  Timeout-guarded subprocess runner                                  *)
(* ------------------------------------------------------------------ *)

(** Run [prog] with [args] and [env] as a child in its OWN process group, and
    kill the WHOLE group if it does not finish within [timeout] seconds.

    Why a process group and not a bare [kill pid]: the registry client itself
    shells out to `march`, which shells out to `clang`/the linker, so a naive
    kill of the direct child would orphan those grandchildren and leave them
    running.  The child calls [setsid] to become a new session/group leader
    (its pgid == its pid), so on timeout we [kill (-pid)] — signalling the
    entire group — which reaps the whole tree.

    The child inherits our stdin/stdout/stderr directly, so the client's own
    progress output reaches the terminal.  Returns:
      [`Exited n]    — child exited with code [n]
      [`Signaled n]  — child died on signal [n]
      [`Timeout]     — group was killed after [timeout]s *)
let run_with_timeout ~timeout ~prog ~args ~env =
  let pid = Unix.fork () in
  if pid = 0 then begin
    (* Child: become a session leader so our pid is our process-group id, then
       exec the target.  Any failure here exits with a distinctive code. *)
    (try ignore (Unix.setsid ()) with Unix.Unix_error _ -> ());
    (try Unix.execve prog (Array.of_list (prog :: args)) env
     with _ -> exit 127)
  end;
  (* Parent: poll for completion, killing the group on timeout. *)
  let deadline = Unix.gettimeofday () +. timeout in
  let rec wait () =
    match Unix.waitpid [ Unix.WNOHANG ] pid with
    | 0, _ ->
      if Unix.gettimeofday () >= deadline then begin
        (* Kill the whole group (pgid == child pid via setsid). *)
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

(** Run a shell command and return (exit_code, stdout). *)
let run_cmd cmd =
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 64 in
  (try while true do
       Buffer.add_channel buf ic 1
     done
   with End_of_file -> ());
  let code = Unix.close_process_in ic in
  let out  = String.trim (Buffer.contents buf) in
  (match code with
   | Unix.WEXITED n -> (n, out)
   | _              -> (1, out))

(** Resolve the current HEAD commit SHA of a git repository at [path]. *)
let resolve_commit path =
  let cmd = Printf.sprintf "git -C %s rev-parse HEAD" (Filename.quote path) in
  match run_cmd cmd with
  | (0, sha) when String.length sha >= 7 -> Some sha
  | _ -> None

(** Compute the content hash for a resolved dep directory.
    Uses the CAS canonical archive hash; falls back to a placeholder if
    the directory doesn't exist yet (e.g. registry deps not yet fetched). *)
let content_hash ~name ~source dir =
  if Sys.file_exists dir then
    Resolver_cas_package.store_directory ~name ~source dir
  else
    Printf.sprintf "pending:%s" name

(* ------------------------------------------------------------------ *)
(*  Registry dependency resolution                                     *)
(* ------------------------------------------------------------------ *)

module VC = Resolver_constraint
module RR = Resolver_registry
module PG = Resolver_pubgrub

(** Registry base URL: FORGE_REGISTRY env var, else the public default. *)
let registry_base_url () =
  match Sys.getenv_opt "FORGE_REGISTRY" with
  | Some r when r <> "" -> r
  | _ -> "https://forgepm.org"

(** Strip any trailing '/' so URL joins don't double up. *)
let no_trailing_slash s =
  let n = String.length s in
  if n > 0 && s.[n - 1] = '/' then String.sub s 0 (n - 1) else s

let metadata_url ~base name =
  Printf.sprintf "%s/api/v1/packages/%s" (no_trailing_slash base) name

let release_url ~base name version =
  Printf.sprintf "%s/api/v1/packages/%s/releases/%s"
    (no_trailing_slash base) name version

let download_url ~base name version =
  Printf.sprintf "%s/api/v1/packages/%s/releases/%s/download"
    (no_trailing_slash base) name version

(** Read a whole file into a string (empty on error). *)
let read_whole path =
  try
    let ic = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
      let n = in_channel_length ic in
      let b = Bytes.create n in
      really_input ic b 0 n;
      Bytes.to_string b)
  with Sys_error _ -> ""

(** Fetch [url] to [out] by running the pre-compiled registry client [binary]
    under a timeout, killing the whole process group if it hangs.  Returns
    [Ok ()] on success or [Error msg]. *)
let fetch ~binary ~url ~out =
  let env = Registry_client.fetch_env ~url ~out in
  match run_with_timeout ~timeout:30.0 ~prog:binary ~args:[] ~env with
  | `Exited 0 -> Ok ()
  | `Exited 4 -> Error (Printf.sprintf "registry returned HTTP 4xx for %s" url)
  | `Exited 3 -> Error (Printf.sprintf "transport error fetching %s" url)
  | `Exited n -> Error (Printf.sprintf "fetch of %s failed (exit %d)" url n)
  | `Signaled n -> Error (Printf.sprintf "fetch of %s killed by signal %d" url n)
  | `Timeout -> Error (Printf.sprintf "fetch of %s timed out" url)

(** Extract a top-level string value for [key] from flat registry JSON of the
    form `..."key":"value"...`.  Tolerant of whitespace after the colon. *)
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
    (* skip whitespace, then require an opening quote *)
    let j = ref j in
    while !j < bl && (body.[!j] = ' ' || body.[!j] = '\t') do incr j done;
    if !j >= bl || body.[!j] <> '"' then None
    else begin
      incr j;
      let start = !j in
      while !j < bl && body.[!j] <> '"' do incr j done;
      Some (String.sub body start (!j - start))
    end

(** A parsed registry version summary from the metadata endpoint. *)
type reg_version = { rv_version : string; rv_checksum : string; rv_retired : bool }

(** Split the `versions` array of the metadata JSON into per-object substrings
    and parse each into a [reg_version].  We match on the `"versions":[` marker
    and walk to the matching ']', then split top-level objects by depth. *)
let parse_versions body =
  match json_str_after body "versions" with
  | Some _ -> []  (* "versions" is an array, never a string — fall through below *)
  | None ->
    let marker = "\"versions\":" in
    let ml = String.length marker and bl = String.length body in
    let rec find i =
      if i + ml > bl then None
      else if String.sub body i ml = marker then Some (i + ml)
      else find (i + 1)
    in
    (match find 0 with
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
                 (* retired is a bare boolean, not a string *)
                 let m = "\"retired\":" in
                 let rec has i =
                   if i + String.length m > String.length obj then false
                   else if String.sub obj i (String.length m) = m then
                     let rest = String.sub obj (i + String.length m)
                         (String.length obj - i - String.length m) in
                     String.length rest >= 4 && String.sub (String.trim rest) 0 4 = "true"
                   else has (i + 1)
                 in has 0
               in
               Some { rv_version = v; rv_checksum = c; rv_retired = retired }
             | _ -> None
           ) (List.rev !objs)
       end)

(** Compute the raw sha256 hex of a file's bytes (matching how the registry
    stores a release checksum: [Crypto.sha256(tarball)] over the raw .tar.gz). *)
let sha256_hex_of_file path =
  let content = read_whole path in
  Digestif.SHA256.to_hex (Digestif.SHA256.digest_string content)

(** Extract a .tar.gz into [dest], stripping the single top-level directory so
    the package's own `lib/` lands directly at [dest]/lib. *)
let extract_tarball ~tarball ~dest =
  Project.mkdir_p dest;
  let cmd = Printf.sprintf "tar xzf %s -C %s --strip-components=1"
      (Filename.quote tarball) (Filename.quote dest) in
  Sys.command cmd

(** Fetch metadata for each registry dep, version-solve with PubGrub (pinning
    path/git deps as overrides), then download+verify+extract each solved
    registry package into ~/.march/cas/deps/<name>.  Returns lockfile entries
    for the registry deps (or an error string on the first hard failure).

    [reg_deps]     : (name, version_constraint_string) registry deps to solve.
    [override_deps]: (name, Project.dep) path/git/branch deps that must NOT be
                     version-solved — pinned so the solver leaves them alone. *)
let resolve_registry_deps ~reg_deps ~override_deps =
  if reg_deps = [] then Ok []
  else begin
    let base = registry_base_url () in
    Printf.printf "resolving %d registry dependenc%s from %s...\n%!"
      (List.length reg_deps)
      (if List.length reg_deps = 1 then "y" else "ies") base;
    (* 1. Compile the registry client ONCE (native TLS only works compiled). *)
    Printf.printf "  compiling registry client...\n%!";
    match
      (* compile_client itself shells out to `march`; guard it with a timeout
         and process-group kill so a hung compile can't wedge `forge deps`. *)
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
      let toolchain_pfx =
        match Toolchain.path_prefix () with Ok p -> p | Error _ -> "" in
      let cmd = Printf.sprintf "%s%s%s --compile -o %s %s"
          toolchain_pfx stdlib_pfx (Filename.quote march)
          (Filename.quote out) (Filename.quote tmp_src) in
      let env = Unix.environment () in
      let res = run_with_timeout ~timeout:180.0
          ~prog:"/bin/sh" ~args:["-c"; cmd] ~env in
      (try Sys.remove tmp_src with Sys_error _ -> ());
      (match res with
       | `Exited 0 when Sys.file_exists out ->
         (try Unix.chmod out 0o755 with Unix.Unix_error _ -> ());
         Ok out
       | `Timeout -> Error "registry client compilation timed out"
       | _ -> Error "registry client failed to compile")
    with
    | Error e -> Error e
    | Ok binary ->
      Fun.protect ~finally:(fun () -> try Sys.remove binary with Sys_error _ -> ())
        (fun () ->
      (* 2. Fetch metadata per registry dep; build the resolver index. *)
      let idx = RR.create () in
      (* name → (version_string → checksum_hex) *)
      let checksums : (string, (string, string) Hashtbl.t) Hashtbl.t =
        Hashtbl.create 8 in
      let meta_error = ref None in
      List.iter (fun (name, _constr) ->
          if !meta_error = None && not (Hashtbl.mem checksums name) then begin
            let tmp = Filename.temp_file "forge_meta_" ".json" in
            (match fetch ~binary ~url:(metadata_url ~base name) ~out:tmp with
             | Error e ->
               meta_error := Some (Printf.sprintf "%s: %s" name e)
             | Ok () ->
               let body = read_whole tmp in
               let vers = parse_versions body in
               if vers = [] then
                 meta_error := Some
                     (Printf.sprintf "%s: no versions found in registry metadata" name)
               else begin
                 let cs_tbl = Hashtbl.create 8 in
                 Hashtbl.replace checksums name cs_tbl;
                 List.iter (fun rv ->
                     if not rv.rv_retired then
                       match Resolver_version.parse rv.rv_version with
                       | Error _ -> ()
                       | Ok v ->
                         Hashtbl.replace cs_tbl rv.rv_version rv.rv_checksum;
                         (* Requirements are fetched lazily only if needed; the
                            common case (leaf packages) has none, and the
                            metadata endpoint does not include them.  Register
                            each version with empty deps for now. *)
                         RR.add_version idx
                           { RR.name; version = v; deps = [] }
                   ) vers
               end);
            (try Sys.remove tmp with Sys_error _ -> ())
          end
        ) reg_deps;
      (match !meta_error with
       | Some e -> Error e
       | None ->
         (* 3. Build root constraints + overrides, then solve. *)
         let root_deps_res =
           List.fold_left (fun acc (name, constr) ->
               match acc with
               | Error _ -> acc
               | Ok rds ->
                 (match VC.parse constr with
                  | Ok c -> Ok ((name, c) :: rds)
                  | Error e ->
                    Error (Printf.sprintf "%s: invalid version constraint %S: %s"
                             name constr e))
             ) (Ok []) reg_deps
         in
         (match root_deps_res with
          | Error e -> Error e
          | Ok root_deps ->
            let overrides =
              List.map (fun (name, _dep) -> (name, None)) override_deps in
            (match PG.solve idx ~root_deps ~overrides with
             | Error err -> Error (PG.format_error err)
             | Ok solution ->
               (* 4. Download + verify + extract each solved registry package. *)
               let deps_dir = cas_deps_dir () in
               Project.mkdir_p deps_dir;
               let entries = ref [] in
               let install_error = ref None in
               List.iter (fun (name, v) ->
                   if !install_error = None && Hashtbl.mem checksums name then begin
                     let vstr = Resolver_version.to_string v in
                     let cs_tbl = Hashtbl.find checksums name in
                     match Hashtbl.find_opt cs_tbl vstr with
                     | None ->
                       install_error := Some
                           (Printf.sprintf "%s %s: no checksum in registry metadata"
                              name vstr)
                     | Some expected_cs ->
                       let dest = Filename.concat deps_dir name in
                       let tarball =
                         Filename.temp_file ("forge_" ^ name ^ "_") ".tar.gz" in
                       Printf.printf "  %s %s: downloading...\n%!" name vstr;
                       (match fetch ~binary
                                ~url:(download_url ~base name vstr) ~out:tarball with
                        | Error e -> install_error := Some (Printf.sprintf "%s %s: %s" name vstr e)
                        | Ok () ->
                          let actual_cs = sha256_hex_of_file tarball in
                          if actual_cs <> expected_cs then
                            install_error := Some (Printf.sprintf
                                "%s %s: checksum mismatch\n  expected: %s\n  got:      %s"
                                name vstr expected_cs actual_cs)
                          else begin
                            (* Fresh extract: remove any stale install first. *)
                            if Sys.file_exists dest then
                              ignore (Sys.command
                                        (Printf.sprintf "rm -rf %s" (Filename.quote dest)));
                            let rc = extract_tarball ~tarball ~dest in
                            if rc <> 0 then
                              install_error := Some (Printf.sprintf
                                  "%s %s: tar extraction failed (exit %d)" name vstr rc)
                            else begin
                              Printf.printf "  %s %s: installed to %s\n%!" name vstr dest;
                              let e = Resolver_lockfile.{
                                  name;
                                  version = Some vstr;
                                  source  = "registry:forge";
                                  commit  = None;
                                  hash    = "sha256:" ^ expected_cs } in
                              entries := e :: !entries
                            end
                          end);
                       (try Sys.remove tarball with Sys_error _ -> ())
                   end
                 ) solution;
               (match !install_error with
                | Some e -> Error e
                | None -> Ok (List.rev !entries)))))
        )
  end

(* ------------------------------------------------------------------ *)
(*  Install / update per dep type                                      *)
(* ------------------------------------------------------------------ *)

(** Install a dep for the first time.  Returns a (lock_entry, error option). *)
let install_dep name (dep : Project.dep) =
  let deps_dir = cas_deps_dir () in
  Project.mkdir_p deps_dir;
  let dest = Filename.concat deps_dir name in
  match dep with

  | Project.RegistryDep { version } ->
    (* Registry not yet implemented — print a notice and skip *)
    Printf.printf "  %s: registry dep (%s) — registry not yet available, skipping\n%!"
      name version;
    let e = Resolver_lockfile.{ name; version = None;
                                 source = "registry:forge";
                                 commit = None;
                                 hash = Printf.sprintf "pending:%s" name } in
    Ok e

  | Project.GitTagDep { url; tag } ->
    if Sys.file_exists dest then begin
      Printf.printf "  %s: already installed (tag %s)\n%!" name tag;
      let commit = resolve_commit dest in
      let e = Resolver_lockfile.{ name; version = Some tag;
                                   source = "git:" ^ url;
                                   commit; hash = content_hash ~name ~source:("git:" ^ url) dest } in
      Ok e
    end else begin
      Printf.printf "  %s: cloning %s @ %s...\n%!" name url tag;
      let cmd = Printf.sprintf "git clone --depth 1 --branch %s %s %s"
          (Filename.quote tag) (Filename.quote url) (Filename.quote dest) in
      let rc = Sys.command cmd in
      if rc = 0 then begin
        let commit = resolve_commit dest in
        (* Parse tag as semver version for the lockfile *)
        let ver_str = match Resolver_version.parse tag with
          | Ok v  -> Some (Resolver_version.to_string v)
          | Error _ ->
            Printf.eprintf
              "warning: tag '%s' for %s is not semver — stored as-is\n%!" tag name;
            Some tag
        in
        let e = Resolver_lockfile.{ name; version = ver_str;
                                     source = "git:" ^ url;
                                     commit; hash = content_hash ~name ~source:("git:" ^ url) dest } in
        Ok e
      end else
        Error (Printf.sprintf "failed to clone %s @ %s (exit %d)" url tag rc)
    end

  | Project.GitBranchDep { url; branch } ->
    if Sys.file_exists dest then begin
      Printf.printf "  %s: already installed (branch %s)\n%!" name branch;
      let commit = resolve_commit dest in
      let e = Resolver_lockfile.{ name; version = None;
                                   source = "git:" ^ url;
                                   commit; hash = content_hash ~name ~source:("git:" ^ url) dest } in
      Ok e
    end else begin
      Printf.printf "  %s: cloning %s @ branch %s...\n%!" name url branch;
      let cmd = Printf.sprintf "git clone --depth 1 --branch %s %s %s"
          (Filename.quote branch) (Filename.quote url) (Filename.quote dest) in
      let rc = Sys.command cmd in
      if rc = 0 then begin
        let commit = resolve_commit dest in
        let e = Resolver_lockfile.{ name; version = None;
                                     source = "git:" ^ url;
                                     commit; hash = content_hash ~name ~source:("git:" ^ url) dest } in
        Ok e
      end else
        Error (Printf.sprintf "failed to clone %s (branch %s, exit %d)" url branch rc)
    end

  | Project.GitRevDep { url; rev } ->
    if Sys.file_exists dest then begin
      Printf.printf "  %s: already installed (rev %s)\n%!" name rev;
      let e = Resolver_lockfile.{ name; version = None;
                                   source = "git:" ^ url;
                                   commit = Some rev;
                                   hash = content_hash ~name ~source:("git:" ^ url) dest } in
      Ok e
    end else begin
      Printf.printf "  %s: cloning %s @ %s...\n%!" name url rev;
      (* Can't use --depth 1 with arbitrary rev unless the server supports it.
         Use a full clone then checkout. *)
      let cmd = Printf.sprintf "git clone %s %s && git -C %s checkout %s"
          (Filename.quote url) (Filename.quote dest)
          (Filename.quote dest) (Filename.quote rev) in
      let rc = Sys.command cmd in
      if rc = 0 then begin
        let e = Resolver_lockfile.{ name; version = None;
                                     source = "git:" ^ url;
                                     commit = Some rev;
                                     hash = content_hash ~name ~source:("git:" ^ url) dest } in
        Ok e
      end else
        Error (Printf.sprintf "failed to clone %s @ %s (exit %d)" url rev rc)
    end

  | Project.PathDep path ->
    if Sys.file_exists path then begin
      Printf.printf "  %s: found at %s\n%!" name path;
      let hash = content_hash ~name ~source:("path:" ^ path) path in
      let e = Resolver_lockfile.{ name; version = None;
                                   source = "path:" ^ path;
                                   commit = None;
                                   hash } in
      Ok e
    end else
      Error (Printf.sprintf "path dep '%s' not found: %s" name path)

(** Update a dep in place (moves branch deps to new HEAD; no-ops for others). *)
let update_dep name (dep : Project.dep) =
  match dep with
  | Project.GitBranchDep { url; branch } ->
    let dest = Filename.concat (cas_deps_dir ()) name in
    if Sys.file_exists dest then begin
      Printf.printf "  %s: pulling %s @ %s...\n%!" name url branch;
      let cmd = Printf.sprintf
          "git -C %s fetch --depth 1 origin %s && git -C %s checkout FETCH_HEAD"
          (Filename.quote dest) (Filename.quote branch) (Filename.quote dest) in
      let rc = Sys.command cmd in
      if rc = 0 then Ok ()
      else Error (Printf.sprintf "failed to update %s" name)
    end else begin
      ignore (install_dep name dep);
      Ok ()
    end
  | Project.GitRevDep _ ->
    Printf.printf "  %s: pinned to exact rev — nothing to update\n%!" name;
    Printf.printf "     (change the rev in forge.toml to update)\n%!";
    Ok ()
  | Project.GitTagDep _ ->
    Printf.printf "  %s: pinned to tag — nothing to update\n%!" name;
    Printf.printf "     (change the tag in forge.toml to update)\n%!";
    Ok ()
  | Project.RegistryDep _ ->
    Printf.printf "  %s: registry update not yet implemented\n%!" name;
    Ok ()
  | Project.PathDep _ ->
    Printf.printf "  %s: path dep — nothing to update\n%!" name;
    Ok ()

(** Install a wave of deps, then discover the NEXT wave from each newly
    installed dep's own forge.toml [deps] (recursing into transitive
    dependencies — e.g. installing `bastion` also pulls in `depot` if
    bastion's own forge.toml declares it).  [project_root] is the root of
    the project that declared the current [wave] (needed to resolve a
    PathDep in that wave relative to its OWN declaring project, not the
    top-level one — each recursive call passes the dep's own root down).
    [visited] dedups by name across the whole graph: a name already seen
    (nearest — i.e. more direct — wins) is skipped entirely.

    Registry deps are NOT installed here — they are collected into [reg_acc]
    (a (name, version_constraint) accumulator) so the caller can version-solve
    the whole registry set with PubGrub in one pass.  A registry dep discovered
    transitively (inside an installed git/path dep's forge.toml) still lands in
    [reg_acc], so it participates in the same solve. *)
let rec bfs_install visited ~reg_acc ~project_root wave =
  match wave with
  | [] -> []
  | _ ->
    let fresh = List.filter (fun (name, _) ->
        if Hashtbl.mem visited name then false
        else begin Hashtbl.add visited name (); true end
      ) wave in
    (* Split off registry deps: accumulate their constraints, don't install. *)
    let fresh = List.filter (fun (name, dep) ->
        match dep with
        | Project.RegistryDep { version } ->
          reg_acc := (name, version) :: !reg_acc; false
        | _ -> true
      ) fresh in
    let results = List.map (fun (name, dep) -> (name, dep, install_dep name dep)) fresh in
    let next_wave = List.concat_map (fun (name, dep, result) ->
        match result with
        | Error _ -> []
        | Ok _ ->
          (match Project.dep_root_dir ~project_root (name, dep) with
           | Some dep_dir when Sys.file_exists (Filename.concat dep_dir "forge.toml") ->
             (match Project.load_from_dir dep_dir with
              | Ok dep_proj -> List.map (fun (n, d) -> (n, d, dep_dir)) dep_proj.Project.deps
              | Error _ -> [])
           | _ -> [])
      ) results in
    let this_level = List.map (fun (name, _, result) -> (name, result)) results in
    (* Group the next wave's entries by their (possibly differing) declaring
       root so each recursive call resolves PathDeps against the right root. *)
    let by_root = Hashtbl.create 4 in
    List.iter (fun (n, d, root) ->
        let existing = try Hashtbl.find by_root root with Not_found -> [] in
        Hashtbl.replace by_root root ((n, d) :: existing)
      ) next_wave;
    let nested = Hashtbl.fold (fun root deps acc ->
        acc @ bfs_install visited ~reg_acc ~project_root:root (List.rev deps)
      ) by_root [] in
    this_level @ nested

(* ------------------------------------------------------------------ *)
(*  forge deps                                                         *)
(* ------------------------------------------------------------------ *)

let run () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    (* Drift check: warn if forge.toml changed since last lock *)
    let lock_path = Filename.concat proj.Project.root "forge.lock" in
    let toml_path = Filename.concat proj.Project.root "forge.toml" in
    let toml_content =
      try
        let ic = open_in toml_path in
        let n = in_channel_length ic in
        let buf = Bytes.create n in
        really_input ic buf 0 n;
        close_in ic;
        Bytes.to_string buf
      with Sys_error _ -> ""
    in
    if Sys.file_exists lock_path &&
       Resolver_lockfile.has_drifted lock_path toml_content then
      Printf.printf
        "note: forge.toml has changed since last `forge deps` — updating lockfile\n%!";
    (* Apply [patch] overrides: replace dep sources before installing.
       Patches substitute the declared dep with the patch source. *)
    let patch_names = List.map (fun p -> p.Project.patch_name) proj.Project.patches in
    let effective_deps = List.map (fun (dep_name, dep) ->
        match List.find_opt (fun p -> p.Project.patch_name = dep_name)
                proj.Project.patches with
        | Some p ->
          Printf.printf "  [patch] %s → overriding with patched source\n%!" dep_name;
          (dep_name, p.Project.patch_source)
        | None -> (dep_name, dep)
      ) proj.Project.deps in
    (* Add any patch-only entries (patches for transitive deps not in direct deps) *)
    let extra_patches = List.filter_map (fun p ->
        if List.mem_assoc p.Project.patch_name effective_deps then None
        else Some (p.Project.patch_name, p.Project.patch_source)
      ) proj.Project.patches in
    (* Non-prod deps: dev-deps, dev-only-deps, test-deps.  Patches don't apply
       to these — they're local/dev tooling, not solver-managed prod deps. *)
    let non_prod_deps =
      proj.Project.dev_deps @ proj.Project.dev_only_deps @ proj.Project.test_deps in
    let all_deps = effective_deps @ extra_patches @ non_prod_deps in
    ignore patch_names;
    (* Install all deps *)
    if all_deps = [] then begin
      Printf.printf "no dependencies declared\n%!";
      Resolver_lockfile.write ~toolchain:(Toolchain.resolve_version ())
        lock_path [] ~manifest_hash:
        (Resolver_lockfile.compute_manifest_hash toml_content);
      Ok ()
    end else begin
      Printf.printf "resolving %d dependencies...\n%!" (List.length all_deps);
      let visited = Hashtbl.create 16 in
      let reg_acc = ref [] in
      (* Phase 1: install path/git deps via BFS; registry deps (direct AND any
         found transitively) accumulate in [reg_acc] instead of installing. *)
      let results = bfs_install visited ~reg_acc ~project_root:proj.Project.root all_deps in
      let git_errors = List.filter_map (fun (_, r) ->
          match r with Error e -> Some e | Ok _ -> None) results in
      let git_entries = List.filter_map (fun (_, r) ->
          match r with Ok e -> Some e | Error _ -> None) results in
      (* Overrides: every non-registry (path/git) dep is pre-resolved and must
         not be version-solved by PubGrub. *)
      let override_deps =
        List.filter (fun (_, dep) ->
            match dep with Project.RegistryDep _ -> false | _ -> true)
          all_deps
      in
      (* Phase 2: version-solve + fetch registry deps, with a small fixpoint so
         a registry dep that itself declares registry deps is picked up.  Dedup
         registry names by nearest-wins (first constraint seen). *)
      let reg_entries = ref [] in
      let reg_error = ref None in
      let seen_reg = Hashtbl.create 8 in
      let dedup pairs =
        List.filter (fun (name, _) ->
            if Hashtbl.mem seen_reg name then false
            else begin Hashtbl.add seen_reg name (); true end
          ) (List.rev pairs)
      in
      let rec resolve_wave pending =
        match dedup pending with
        | [] -> ()
        | wave when !reg_error = None ->
          (match resolve_registry_deps ~reg_deps:wave ~override_deps with
           | Error e -> reg_error := Some e
           | Ok es ->
             reg_entries := !reg_entries @ es;
             (* Discover transitive registry deps from the just-installed set. *)
             let next = List.concat_map (fun e ->
                 let dep_dir = Filename.concat (cas_deps_dir ()) e.Resolver_lockfile.name in
                 if Sys.file_exists (Filename.concat dep_dir "forge.toml") then
                   match Project.load_from_dir dep_dir with
                   | Ok p ->
                     List.filter_map (fun (n, d) ->
                         match d with
                         | Project.RegistryDep { version } -> Some (n, version)
                         | _ -> None)
                       p.Project.deps
                   | Error _ -> []
                 else []
               ) es in
             resolve_wave next)
        | _ -> ()
      in
      resolve_wave !reg_acc;
      let errors = git_errors @ (match !reg_error with Some e -> [e] | None -> []) in
      let entries = git_entries @ !reg_entries in
      let mhash = Resolver_lockfile.compute_manifest_hash toml_content in
      Resolver_lockfile.write ~toolchain:(Toolchain.resolve_version ())
        lock_path entries ~manifest_hash:mhash;
      if errors = [] then Ok ()
      else Error (String.concat "\n" errors)
    end

(* ------------------------------------------------------------------ *)
(*  forge deps update [name]                                           *)
(* ------------------------------------------------------------------ *)

let run_update name_opt =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let to_update = match name_opt with
      | None   -> proj.Project.deps
      | Some n ->
        (match List.assoc_opt n proj.Project.deps with
         | None   -> []
         | Some d -> [(n, d)])
    in
    if to_update = [] then begin
      (match name_opt with
       | Some n -> Printf.printf "dependency '%s' not found\n%!" n
       | None   -> Printf.printf "no dependencies to update\n%!");
      Ok ()
    end else begin
      let results = List.map (fun (n, d) -> update_dep n d) to_update in
      let errors  = List.filter_map (function Error e -> Some e | Ok _ -> None) results in
      if errors = [] then Ok ()
      else Error (String.concat "\n" errors)
    end
