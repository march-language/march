(** Archive store — manages ~/.march/archives/

    Layout:
      ~/.march/archives/
        registry.toml           -- manifest of all installed archives
        <name>/                 -- extracted archive (forge.toml + forge/)
          forge.toml
          forge/
            *.march
        dev/                    -- symlinks for path (dev) archives
          <name> -> /abs/path

    Path (dev) archives bypass CAS; git and registry archives are stored
    in the CAS and symlinked here.
*)

(* ------------------------------------------------------------------ *)
(*  Types                                                              *)
(* ------------------------------------------------------------------ *)

type source =
  | Registry of { version : string }
  | Git      of { url : string; git_ref : string option; rev : string option }
  | Path     of string  (** absolute path; not CAS-backed *)

type entry = {
  name         : string;
  source       : source;
  hash         : string;       (** "sha256:..." or "path:<abs>" for dev *)
  installed_at : string;
}

(* ------------------------------------------------------------------ *)
(*  Directories                                                        *)
(* ------------------------------------------------------------------ *)

let home_dir () =
  try Sys.getenv "HOME"
  with Not_found -> failwith "HOME not set"

let archives_dir () =
  Filename.concat (home_dir ()) (Filename.concat ".march" "archives")

let archive_dir name =
  Filename.concat (archives_dir ()) name

let dev_dir () =
  Filename.concat (archives_dir ()) "dev"

let registry_path () =
  Filename.concat (archives_dir ()) "registry.toml"

let ensure_archives_dir () =
  Project.mkdir_p (archives_dir ())

(* ------------------------------------------------------------------ *)
(*  Registry read / write                                              *)
(* ------------------------------------------------------------------ *)

(** Parse a source from registry.toml fields. *)
let source_of_toml pairs =
  let get k = Toml.get_string pairs k in
  match get "source" with
  | Some "registry" ->
    let version = Option.value ~default:"*" (get "version") in
    Some (Registry { version })
  | Some "git" ->
    (match get "url" with
     | None -> None
     | Some url ->
       let git_ref = get "ref" in
       let rev     = get "rev" in
       Some (Git { url; git_ref; rev }))
  | Some "path" ->
    (match get "path" with
     | None -> None
     | Some p -> Some (Path p))
  | _ -> None

(** Load all entries from registry.toml.  Returns [] if the file doesn't exist. *)
let load_registry () : (string * entry) list =
  let path = registry_path () in
  if not (Sys.file_exists path) then []
  else
    let ic = open_in path in
    let n = in_channel_length ic in
    let buf = Bytes.create n in
    really_input ic buf 0 n;
    close_in ic;
    let doc = Toml.parse (Bytes.to_string buf) in
    List.filter_map (fun (sec_name, pairs) ->
        (* Skip reserved section names *)
        if sec_name = "" || String.contains sec_name '.' then None
        else begin
          match source_of_toml pairs with
          | None -> None
          | Some src ->
            let hash         = Option.value ~default:"" (Toml.get_string pairs "hash") in
            let installed_at = Option.value ~default:"" (Toml.get_string pairs "installed_at") in
            let entry = { name = sec_name; source = src; hash; installed_at } in
            Some (sec_name, entry)
        end
      ) doc.Toml.sections

(** Serialise a single entry to TOML key-value lines. *)
let entry_to_toml e =
  let buf = Buffer.create 64 in
  let add k v = Buffer.add_string buf (Printf.sprintf "%s = %S\n" k v) in
  (match e.source with
   | Registry { version } ->
     add "source" "registry";
     add "version" version
   | Git { url; git_ref; rev } ->
     add "source" "git";
     add "url" url;
     (match git_ref with Some r -> add "ref" r | None -> ());
     (match rev with Some r -> add "rev" r | None -> ())
   | Path p ->
     add "source" "path";
     add "path" p);
  add "hash" e.hash;
  add "installed_at" e.installed_at;
  Buffer.contents buf

(** Write all entries to registry.toml (full rewrite). *)
let save_registry (entries : (string * entry) list) =
  ensure_archives_dir ();
  let path = registry_path () in
  let oc = open_out path in
  output_string oc "# forge archive registry\n";
  output_string oc "# written by 'forge install'\n\n";
  List.iter (fun (name, e) ->
      output_string oc (Printf.sprintf "[%s]\n" name);
      output_string oc (entry_to_toml e);
      output_string oc "\n"
    ) entries;
  close_out oc

(* ------------------------------------------------------------------ *)
(*  Install / uninstall                                                *)
(* ------------------------------------------------------------------ *)

let is_installed name =
  let entries = load_registry () in
  List.mem_assoc name entries

(** Copy forge.toml + forge/ from src_dir to ~/.march/archives/<name>/.
    Also stores in CAS for integrity.  Returns the content hash. *)
let extract_archive ~name ~src_dir =
  let dest = archive_dir name in
  Project.mkdir_p dest;
  (* Copy forge.toml *)
  let src_toml = Filename.concat src_dir "forge.toml" in
  let dst_toml = Filename.concat dest "forge.toml" in
  let rc1 = Sys.command (Printf.sprintf "cp %s %s"
                           (Filename.quote src_toml) (Filename.quote dst_toml)) in
  (* Copy forge/ directory *)
  let src_forge = Filename.concat src_dir "forge" in
  let dst_forge = Filename.concat dest "forge" in
  let rc2 =
    if Sys.file_exists src_forge then
      Sys.command (Printf.sprintf "cp -r %s %s"
                     (Filename.quote src_forge) (Filename.quote dst_forge))
    else 0
  in
  if rc1 <> 0 || rc2 <> 0 then
    Error (Printf.sprintf "failed to extract archive for '%s'" name)
  else begin
    let hash = Resolver_cas_package.store_directory ~name ~source:("archive:" ^ name) dest in
    Ok hash
  end

let timestamp () =
  let t = Unix.gettimeofday () in
  let tm = Unix.gmtime t in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday
    tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec

(** Install an archive from an already-fetched source directory. *)
let install_from_dir ~name ~src_dir ~source =
  let entries = load_registry () in
  (* Compute hash and copy files *)
  match extract_archive ~name ~src_dir with
  | Error msg -> Error msg
  | Ok hash ->
    let entry = { name; source; hash; installed_at = timestamp () } in
    let entries' = List.filter (fun (n, _) -> n <> name) entries in
    save_registry ((name, entry) :: entries');
    Ok ()

(** Install a path (dev) archive — records it without copying files. *)
let install_path ~name ~abs_path =
  let entries = load_registry () in
  let hash = Printf.sprintf "path:%s" abs_path in
  let entry = { name; source = Path abs_path; hash; installed_at = timestamp () } in
  let entries' = List.filter (fun (n, _) -> n <> name) entries in
  save_registry ((name, entry) :: entries');
  Ok ()

(** Remove an installed archive. *)
let uninstall name =
  let entries = load_registry () in
  if not (List.mem_assoc name entries) then
    Error (Printf.sprintf "'%s' is not installed" name)
  else begin
    (* Remove the archive directory (not path archives — those are external) *)
    let entry = List.assoc name entries in
    (match entry.source with
     | Path _ -> ()  (* don't delete external path *)
     | _ ->
       let dir = archive_dir name in
       if Sys.file_exists dir then
         ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir))));
    let entries' = List.filter (fun (n, _) -> n <> name) entries in
    save_registry entries';
    Ok ()
  end

(* ------------------------------------------------------------------ *)
(*  Task discovery                                                     *)
(* ------------------------------------------------------------------ *)

(** Load task declarations from a forge.toml that has [archive.task.*] sections. *)
let read_tasks_from_toml toml_path =
  if not (Sys.file_exists toml_path) then []
  else
    let ic = open_in toml_path in
    let n = in_channel_length ic in
    let buf = Bytes.create n in
    really_input ic buf 0 n;
    close_in ic;
    let doc = Toml.parse (Bytes.to_string buf) in
    let prefix = "archive.task." in
    let plen = String.length prefix in
    List.filter_map (fun (sec_name, pairs) ->
        if String.length sec_name > plen &&
           String.sub sec_name 0 plen = prefix
        then begin
          let command = Toml.get_string pairs "command" in
          let module_ = Toml.get_string pairs "module" in
          match command, module_ with
          | Some cmd, Some m -> Some (cmd, m)
          | _ -> None
        end else None
      ) doc.Toml.sections

(** Lib paths to add to MARCH_LIB_PATH for tasks running from an archive root.
    Includes lib/ (for sibling module imports like Forge.Scaffold) and forge/
    at the root level (for CAS-extracted archives). *)
let lib_paths_for_root archive_root =
  let lib_dir   = Filename.concat archive_root "lib" in
  let forge_dir = Filename.concat archive_root "forge" in
  List.filter Sys.file_exists [lib_dir; forge_dir]

(** Given a command like "bastion.new", return (task_file, lib_paths) or None.
    Checks project-local deps first, then global archives. *)
let find_task command =
  (* Extract namespace = first dotted segment *)
  match String.index_opt command '.' with
  | None -> None
  | Some dot ->
    let ns = String.sub command 0 dot in
    (* 1. Check project-local deps *)
    let local_result =
      match Project.find_forge_toml () with
      | None -> None
      | Some project_root ->
        let dep_dir = Filename.concat project_root (Filename.concat "deps" ns) in
        let dep_toml = Filename.concat dep_dir "forge.toml" in
        if Sys.file_exists dep_toml then begin
          let tasks = read_tasks_from_toml dep_toml in
          match List.assoc_opt command tasks with
          | None -> None
          | Some rel_module ->
            let full_path = Filename.concat dep_dir rel_module in
            if Sys.file_exists full_path then
              Some (full_path, lib_paths_for_root dep_dir)
            else None
        end else None
    in
    (match local_result with
     | Some _ -> local_result
     | None ->
       (* 2. Check global archive *)
       let entries = load_registry () in
       (match List.assoc_opt ns entries with
        | None -> None
        | Some entry ->
          let archive_root = match entry.source with
            | Path p -> p
            | _ -> archive_dir ns
          in
          let toml_path = Filename.concat archive_root "forge.toml" in
          let tasks = read_tasks_from_toml toml_path in
          match List.assoc_opt command tasks with
          | None -> None
          | Some rel_module ->
            let full_path = Filename.concat archive_root rel_module in
            if Sys.file_exists full_path then
              Some (full_path, lib_paths_for_root archive_root)
            else None))

(** Return all (command, module_path) pairs for an archive directory. *)
let list_archive_tasks archive_root =
  let toml_path = Filename.concat archive_root "forge.toml" in
  let tasks = read_tasks_from_toml toml_path in
  List.filter_map (fun (cmd, rel_m) ->
      let full = Filename.concat archive_root rel_m in
      if Sys.file_exists full then Some (cmd, full) else None
    ) tasks

(** Resolve the stdlib directory using the same strategy as the compiler:
    1. MARCH_STDLIB env var  2. exe-relative paths  3. CWD fallback *)
let find_stdlib_dir () =
  match Sys.getenv_opt "MARCH_STDLIB" with
  | Some p when Sys.file_exists p -> Some p
  | _ ->
    let exe_dir = Filename.dirname Sys.executable_name in
    let candidates = [
      Filename.concat exe_dir "../stdlib";
      Filename.concat exe_dir "../../stdlib";
      Filename.concat exe_dir "../share/march/stdlib";
      Filename.concat exe_dir "../share/march";
      "stdlib";
    ] in
    List.find_opt Sys.file_exists candidates

(** Run a task module file with the given arguments.
    FORGE_TASK_ARGS carries newline-separated args; MARCH_LIB_PATH lets tasks
    import sibling modules; MARCH_STDLIB tells tasks where the stdlib lives. *)
let run_task task_file lib_paths args =
  let args_env = String.concat "\n" args in
  let lib_path_env = match lib_paths with
    | [] -> ""
    | ps -> Printf.sprintf "MARCH_LIB_PATH=%s " (Filename.quote (String.concat ":" ps))
  in
  let stdlib_env = match find_stdlib_dir () with
    | None -> ""
    | Some p -> Printf.sprintf "MARCH_STDLIB=%s " (Filename.quote p)
  in
  let cmd = Printf.sprintf "%s%sFORGE_TASK_ARGS=%s march %s"
      lib_path_env stdlib_env (Filename.quote args_env) (Filename.quote task_file) in
  Sys.command cmd
