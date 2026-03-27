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
    (* Install all deps *)
    if proj.Project.deps = [] then begin
      Printf.printf "no dependencies declared\n%!";
      Resolver_lockfile.write lock_path [] ~manifest_hash:
        (Resolver_lockfile.compute_manifest_hash toml_content);
      Ok ()
    end else begin
      Printf.printf "resolving %d dependencies...\n%!" (List.length proj.Project.deps);
      let results = List.map (fun (n, d) -> (n, install_dep n d)) proj.Project.deps in
      let errors  = List.filter_map (fun (_, r) ->
          match r with Error e -> Some e | Ok _ -> None) results in
      let entries = List.filter_map (fun (_, r) ->
          match r with Ok e -> Some e | Error _ -> None) results in
      let mhash = Resolver_lockfile.compute_manifest_hash toml_content in
      Resolver_lockfile.write lock_path entries ~manifest_hash:mhash;
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
