(** forge install / uninstall / archives / update / verify

    forge install bastion              — latest from registry
    forge install bastion@1.2.0        — pinned version from registry
    forge install bastion@latest       — explicit latest
    forge install bastion@../bastion   — local path (dev)
    forge install bastion@https://github.com/march-lang/bastion       — git default branch
    forge install bastion@https://github.com/march-lang/bastion#main  — git branch/tag

    forge uninstall bastion
    forge archives
    forge update [name]
    forge verify [name]
*)

(* ------------------------------------------------------------------ *)
(*  @ref parsing                                                       *)
(* ------------------------------------------------------------------ *)

type ref_spec =
  | Latest
  | Version  of string
  | GitRef   of { url : string; fragment : string option }
  | LocalPath of string

let is_url s =
  let starts prefix =
    String.length s >= String.length prefix &&
    String.sub s 0 (String.length prefix) = prefix
  in
  starts "https://" || starts "http://" || starts "git@" || starts "ssh://"

let is_local_path s =
  let starts prefix =
    String.length s >= String.length prefix &&
    String.sub s 0 (String.length prefix) = prefix
  in
  starts "/" || starts "./" || starts "../"

let parse_git_ref s =
  (* Split on '#' for optional fragment *)
  match String.index_opt s '#' with
  | None -> GitRef { url = s; fragment = None }
  | Some i ->
    let url = String.sub s 0 i in
    let frag = String.sub s (i + 1) (String.length s - i - 1) in
    GitRef { url; fragment = if frag = "" then None else Some frag }

(** Parse "name[@ref]" into (name, ref_spec). *)
let parse_name_ref arg =
  match String.index_opt arg '@' with
  | None ->
    Ok (arg, Latest)
  | Some i ->
    let name = String.sub arg 0 i in
    let ref_ = String.sub arg (i + 1) (String.length arg - i - 1) in
    if name = "" then
      Error (Printf.sprintf "invalid archive argument: '%s' (name is empty)" arg)
    else if ref_ = "" || ref_ = "latest" then
      Ok (name, Latest)
    else if is_url ref_ then
      Ok (name, parse_git_ref ref_)
    else if is_local_path ref_ then
      Ok (name, LocalPath ref_)
    else
      Ok (name, Version ref_)

(* ------------------------------------------------------------------ *)
(*  Helpers                                                            *)
(* ------------------------------------------------------------------ *)

let run_cmd cmd =
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 64 in
  (try while true do Buffer.add_channel buf ic 1 done
   with End_of_file -> ());
  let rc = Unix.close_process_in ic in
  let out = String.trim (Buffer.contents buf) in
  (match rc with Unix.WEXITED n -> (n, out) | _ -> (1, out))

let resolve_commit path =
  let cmd = Printf.sprintf "git -C %s rev-parse HEAD" (Filename.quote path) in
  match run_cmd cmd with
  | (0, sha) when String.length sha >= 7 -> Some sha
  | _ -> None

let tmp_clone_dir () =
  Filename.concat (Filename.get_temp_dir_name ())
    (Printf.sprintf "forge-archive-%d" (Random.int 1_000_000))

(** Read the package name from a forge.toml in a directory.
    Returns Error if forge.toml is absent or has no [archive] section. *)
let read_archive_meta dir =
  let toml_path = Filename.concat dir "forge.toml" in
  if not (Sys.file_exists toml_path) then
    Error (Printf.sprintf "no forge.toml found in %s" dir)
  else begin
    let ic = open_in toml_path in
    let n = in_channel_length ic in
    let buf = Bytes.create n in
    really_input ic buf 0 n;
    close_in ic;
    let doc = Toml.parse (Bytes.to_string buf) in
    (* Accept [package] or [project] *)
    let pkg =
      let p = Toml.get_section doc "package" in
      if p <> [] then p else Toml.get_section doc "project"
    in
    let name = Option.value ~default:"" (Toml.get_string pkg "name") in
    if name = "" then
      Error (Printf.sprintf "forge.toml in %s has no name field" dir)
    else begin
      (* Verify [archive] section exists *)
      let has_archive = List.exists (fun (sec, _) ->
          sec = "archive" ||
          (String.length sec >= 8 && String.sub sec 0 8 = "archive.")
        ) doc.Toml.sections in
      if not has_archive then
        Error (Printf.sprintf "'%s' has no [archive] section — not an archive package" name)
      else
        Ok name
    end
  end

(* ------------------------------------------------------------------ *)
(*  forge install                                                      *)
(* ------------------------------------------------------------------ *)

let install_from_git ~name ~url ~fragment ~force =
  if Archive_store.is_installed name && not force then begin
    let entries = Archive_store.load_registry () in
    match List.assoc_opt name entries with
    | Some e ->
      (match e.Archive_store.source with
       | Archive_store.Git { rev = Some r; _ } ->
         Printf.printf "%s is already installed (rev %s). Use --force to reinstall.\n%!" name r
       | _ ->
         Printf.printf "%s is already installed. Use --force to reinstall.\n%!" name);
      Ok ()
    | None -> Ok ()
  end else begin
    let tmp = tmp_clone_dir () in
    let branch_arg = match fragment with
      | Some b -> Printf.sprintf "--branch %s" (Filename.quote b)
      | None   -> ""
    in
    Printf.printf "Cloning %s%s...\n%!" url
      (match fragment with Some b -> Printf.sprintf " (%s)" b | None -> "");
    let clone_cmd = Printf.sprintf "git clone --depth 1 %s %s %s"
        branch_arg (Filename.quote url) (Filename.quote tmp) in
    let rc = Sys.command clone_cmd in
    if rc <> 0 then
      Error (Printf.sprintf "git clone failed for %s" url)
    else begin
      (* Read archive name from forge.toml (may differ from user-provided name) *)
      let result = match read_archive_meta tmp with
        | Error msg -> Error msg
        | Ok detected_name ->
          let install_name = if name = "" then detected_name else name in
          let rev = resolve_commit tmp in
          let source = Archive_store.Git { url; git_ref = fragment; rev } in
          (match Archive_store.install_from_dir ~name:install_name ~src_dir:tmp ~source with
           | Error msg -> Error msg
           | Ok () ->
             Printf.printf "Installed %s" install_name;
             (match rev with Some r -> Printf.printf " (rev %s)" (String.sub r 0 (min 8 (String.length r))) | None -> ());
             Printf.printf "\n%!";
             (* Print available tasks *)
             let dir = Archive_store.archive_dir install_name in
             let tasks = Archive_store.list_archive_tasks dir in
             if tasks <> [] then begin
               let cmds = List.map fst tasks in
               Printf.printf "Tasks available: %s\n%!" (String.concat ", " cmds)
             end;
             Ok ())
      in
      (* Clean up temp clone *)
      ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmp)));
      result
    end
  end

let install_from_path ~name ~raw_path ~force =
  let abs_path =
    if Filename.is_relative raw_path then
      Filename.concat (Sys.getcwd ()) raw_path
    else raw_path
  in
  (* Normalise (resolve ../ etc.) via pwd -P in a subshell *)
  let (rc, resolved) = run_cmd (Printf.sprintf "cd %s && pwd -P" (Filename.quote abs_path)) in
  let abs_path = if rc = 0 && resolved <> "" then resolved else abs_path in
  if not (Sys.file_exists abs_path) then
    Error (Printf.sprintf "path not found: %s" abs_path)
  else
    match read_archive_meta abs_path with
    | Error msg -> Error msg
    | Ok detected_name ->
      let install_name = if name = "" then detected_name else name in
      if Archive_store.is_installed install_name && not force then begin
        Printf.printf "%s is already installed (path). Use --force to reinstall.\n%!" install_name;
        Ok ()
      end else begin
        (match Archive_store.install_path ~name:install_name ~abs_path with
         | Error msg -> Error msg
         | Ok () ->
           Printf.printf "Installed %s (dev) → %s\n%!" install_name abs_path;
           let tasks = Archive_store.list_archive_tasks abs_path in
           if tasks <> [] then begin
             let cmds = List.map fst tasks in
             Printf.printf "Tasks available: %s\n%!" (String.concat ", " cmds)
           end;
           Ok ())
      end

let run_install arg ~force ~no_verify =
  ignore no_verify;
  match parse_name_ref arg with
  | Error msg -> Error msg
  | Ok (name, ref_spec) ->
    match ref_spec with
    | Latest | Version _ ->
      Printf.eprintf "error: registry not yet available\n%!";
      Printf.eprintf "hint:  install from git: forge install %s@https://...\n%!" name;
      Error "registry not available"
    | GitRef { url; fragment } ->
      install_from_git ~name ~url ~fragment ~force
    | LocalPath raw_path ->
      install_from_path ~name ~raw_path ~force

(* ------------------------------------------------------------------ *)
(*  forge uninstall                                                    *)
(* ------------------------------------------------------------------ *)

let run_uninstall name =
  match Archive_store.uninstall name with
  | Error msg -> Error msg
  | Ok () ->
    Printf.printf "Uninstalled %s.\n%!" name;
    Ok ()

(* ------------------------------------------------------------------ *)
(*  forge archives                                                     *)
(* ------------------------------------------------------------------ *)

let run_list () =
  let entries = Archive_store.load_registry () in
  if entries = [] then
    Printf.printf "No archives installed. Run 'forge install <name>' to install one.\n%!"
  else begin
    (* Column widths *)
    let max_name = List.fold_left (fun acc (n, _) -> max acc (String.length n)) 0 entries in
    List.iter (fun (_, e) ->
        let source_str = match e.Archive_store.source with
          | Archive_store.Registry { version } -> Printf.sprintf "registry  %s" version
          | Archive_store.Git { url; git_ref; rev } ->
            let ref_str = match git_ref with Some r -> r | None -> "default" in
            let rev_str = match rev with
              | Some r -> Printf.sprintf " @%s" (String.sub r 0 (min 8 (String.length r)))
              | None -> ""
            in
            Printf.sprintf "git       %s (%s%s)" url ref_str rev_str
          | Archive_store.Path p ->
            Printf.sprintf "path      %s" p
        in
        (* List available tasks *)
        let archive_root = match e.Archive_store.source with
          | Archive_store.Path p -> p
          | _ -> Archive_store.archive_dir e.Archive_store.name
        in
        let tasks = Archive_store.list_archive_tasks archive_root in
        let task_str = if tasks = [] then ""
          else "  tasks: " ^ String.concat ", " (List.map fst tasks)
        in
        Printf.printf "%-*s  %s%s\n%!" max_name e.Archive_store.name source_str task_str
      ) entries
  end

(* ------------------------------------------------------------------ *)
(*  forge update [name]                                                *)
(* ------------------------------------------------------------------ *)

let update_one name entry =
  match entry.Archive_store.source with
  | Archive_store.Registry _ ->
    Printf.printf "  %s: registry update not yet implemented\n%!" name;
    Ok ()
  | Archive_store.Path _ ->
    Printf.printf "  %s: path archive — nothing to update (re-reads on every invocation)\n%!" name;
    Ok ()
  | Archive_store.Git { url; git_ref; _ } ->
    let tmp = tmp_clone_dir () in
    let branch_arg = match git_ref with
      | Some b -> Printf.sprintf "--branch %s" (Filename.quote b)
      | None   -> ""
    in
    Printf.printf "  %s: fetching latest from %s...\n%!" name url;
    let clone_cmd = Printf.sprintf "git clone --depth 1 %s %s %s"
        branch_arg (Filename.quote url) (Filename.quote tmp) in
    let rc = Sys.command clone_cmd in
    if rc <> 0 then
      Error (Printf.sprintf "failed to fetch %s" name)
    else begin
      let new_rev = resolve_commit tmp in
      let old_rev = match entry.Archive_store.source with
        | Archive_store.Git { rev; _ } -> rev
        | _ -> None
      in
      let changed = match old_rev, new_rev with
        | Some o, Some n -> o <> n
        | _ -> true
      in
      if not changed then begin
        Printf.printf "  %s: already up to date\n%!" name;
        ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmp)));
        Ok ()
      end else begin
        let source = Archive_store.Git { url; git_ref; rev = new_rev } in
        let result = Archive_store.install_from_dir ~name ~src_dir:tmp ~source in
        ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmp)));
        (match result with
         | Ok () ->
           let rev_str = match new_rev with
             | Some r -> String.sub r 0 (min 8 (String.length r))
             | None -> "?"
           in
           Printf.printf "  %s: updated to %s\n%!" name rev_str;
           Ok ()
         | Error msg -> Error msg)
      end
    end

let run_update name_opt =
  let entries = Archive_store.load_registry () in
  let to_update = match name_opt with
    | None   -> entries
    | Some n ->
      (match List.assoc_opt n entries with
       | None   ->
         Printf.eprintf "error: '%s' is not installed\n%!" n;
         []
       | Some e -> [(n, e)])
  in
  if to_update = [] then Ok ()
  else begin
    let results = List.map (fun (n, e) -> update_one n e) to_update in
    let errors = List.filter_map (function Error e -> Some e | Ok _ -> None) results in
    if errors = [] then Ok ()
    else Error (String.concat "\n" errors)
  end

(* ------------------------------------------------------------------ *)
(*  forge verify [name]                                                *)
(* ------------------------------------------------------------------ *)

let verify_one name entry =
  match entry.Archive_store.source with
  | Archive_store.Path p ->
    if Sys.file_exists p then begin
      Printf.printf "  %-20s  ok (path: %s)\n%!" name p;
      Ok ()
    end else begin
      Printf.printf "  %-20s  MISSING (path: %s)\n%!" name p;
      Error (Printf.sprintf "'%s' path no longer exists: %s" name p)
    end
  | _ ->
    let dir = Archive_store.archive_dir name in
    if not (Sys.file_exists dir) then begin
      Printf.printf "  %-20s  MISSING\n%!" name;
      Error (Printf.sprintf "'%s' archive directory missing — reinstall with: forge install %s --force" name name)
    end else begin
      let actual_hash = Resolver_cas_package.store_directory
          ~name ~source:("archive:" ^ name) dir in
      if actual_hash = entry.Archive_store.hash then begin
        Printf.printf "  %-20s  ok\n%!" name;
        Ok ()
      end else begin
        Printf.printf "  %-20s  CORRUPT (hash mismatch)\n%!" name;
        Error (Printf.sprintf
                 "'%s' integrity check failed\n  expected: %s\n  got:      %s\nhint: reinstall with: forge install %s --force"
                 name entry.Archive_store.hash actual_hash name)
      end
    end

let run_verify name_opt =
  let entries = Archive_store.load_registry () in
  let to_check = match name_opt with
    | None   -> entries
    | Some n ->
      (match List.assoc_opt n entries with
       | None   ->
         Printf.eprintf "error: '%s' is not installed\n%!" n;
         []
       | Some e -> [(n, e)])
  in
  if to_check = [] then Ok ()
  else begin
    let results = List.map (fun (n, e) -> verify_one n e) to_check in
    let errors = List.filter_map (function Error e -> Some e | Ok _ -> None) results in
    if errors = [] then Ok ()
    else Error (String.concat "\n" errors)
  end
