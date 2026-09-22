(** Resolving, restoring and verifying dependencies with no network access.

    Shared by the offline preflight of every compile-shaped command
    ([Cmd_build.offline_preflight]: build, check, run, test, bench) and by
    `forge deps --offline` ([Cmd_deps.run_offline]). Nothing here fetches:
    the only inputs are forge.toml, forge.lock and what is already under
    [~/.march/cas/]. `specs/2026-09-11-forge-offline-and-versioned-dep-cache-design.md`
    §3 is the contract and §4 the integrity rules. *)

module LF = Resolver_lockfile

let deps_root () =
  let home = try Sys.getenv "HOME" with Not_found -> "" in
  Filename.concat home
    (Filename.concat ".march" (Filename.concat "cas" "deps"))

let coord_dir ~name ~coord =
  Filename.concat (Filename.concat (deps_root ()) name) coord

let is_path_dep = function Project.PathDep _ -> true | _ -> false

(* ------------------------------------------------------------------ *)
(*  Lockfile state (§3.3)                                              *)
(* ------------------------------------------------------------------ *)

type lock_state =
  | No_lockfile
  | Not_a_lockfile
  (** Parses, but has zero [[package]] entries AND no manifest hash — the
      shape of a file holding forge.toml dependency syntax. [read] returns
      [Ok] for it, so without this case such a project silently resolves to
      "no dependencies" (3 of 13 real lockfiles on the machine the design
      was checked on). *)
  | Lockfile of { entries : LF.entry list; drifted : bool; format : int }

let lock_path ~project_root = Filename.concat project_root "forge.lock"

let read_state ~project_root ~toml_content =
  let path = lock_path ~project_root in
  if not (Sys.file_exists path) then No_lockfile
  else
    match LF.read path with
    | Error _ -> Not_a_lockfile
    | Ok ([], None) -> Not_a_lockfile
    | Ok (entries, _) ->
      Lockfile { entries;
                 (* The same check `--frozen` uses; only the message differs. *)
                 drifted = LF.has_drifted path toml_content;
                 format = LF.read_format_version path }

(** The single message for an unusable lockfile, or [None] when it is usable.
    One message for the whole project, never one per dependency. *)
let state_error ~project_root = function
  | Lockfile _ -> None
  | No_lockfile ->
    Some (Printf.sprintf
            "offline: no forge.lock in %s, so no git or registry dependency \
             has a recorded version to look up in the cache.\n  \
             Continuing with path dependencies only. Run `forge deps` with \
             network access to create it."
            project_root)
  | Not_a_lockfile ->
    Some (Printf.sprintf
            "offline: %s is not a lockfile: it has no [[package]] entries and \
             no [manifest_hash] (it looks like forge.toml dependency syntax).\n  \
             Offline mode cannot resolve git or registry dependencies from it; \
             continuing with path dependencies only. Run `forge deps` with \
             network access to regenerate it."
            (lock_path ~project_root))

let drift_warning =
  "warning: offline: forge.toml has changed since `forge deps` last wrote \
   forge.lock. Offline mode cannot re-resolve, so it is using the versions the \
   lockfile recorded, which may be stale."

(* ------------------------------------------------------------------ *)
(*  Integrity (§4)                                                     *)
(* ------------------------------------------------------------------ *)

type verdict =
  | Verified
  | Mismatch of { expected : string; actual : string }
  | Unverifiable of string   (** why no check was possible *)

(** Re-hash a cached tree and compare it to forge.lock's [hash]. Since lockfile
    format 2 that field is the canonical-archive tree hash for every dep kind,
    so one check covers git and registry deps alike. Two cases cannot be
    checked and say so instead of passing silently: a [pending:] hash (the dep
    was never installed when the lockfile was written) and a registry entry
    in a format-1 lockfile, whose [hash] is the tarball checksum, a different
    domain from a tree hash. *)
let verify_tree ~format (e : LF.entry) dir =
  let h = e.LF.hash in
  if h = "" || (String.length h >= 8 && String.sub h 0 8 = "pending:") then
    Unverifiable "no recorded hash"
  else if format < 2 && e.LF.source = "registry:forge" then
    Unverifiable "format-1 lockfile records a tarball checksum, not a tree hash"
  else
    let actual = Resolver_cas_package.hash_directory dir in
    if actual = h then Verified else Mismatch { expected = h; actual }

let mismatch_error ~name ~label ~dir ~expected ~actual =
  Printf.sprintf
    "dependency `%s` (%s) failed its integrity check:\n  \
     cached tree: %s\n  \
     expected (forge.lock): %s\n  \
     actual:                %s\n  \
     The cached copy has been modified or corrupted. Delete %s and run \
     `forge deps` with network access to reinstall it."
    name label dir expected actual dir

(* ------------------------------------------------------------------ *)
(*  Restoring registry trees from the tarball cache (§2.4)             *)
(* ------------------------------------------------------------------ *)

let extract ~tarball ~dest =
  ignore (Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dest)));
  Sys.command
    (Printf.sprintf "tar xzf %s -C %s --strip-components=1"
       (Filename.quote tarball) (Filename.quote dest))

let rm_rf p = ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote p)))

(** For every registry entry of the lockfile whose tree is absent but whose
    published tarball is in [Tarball_cache], re-extract it — no network. The
    extract is staged, checked against the lockfile's tree hash where one is
    checkable, and only then renamed into place, so a failed restore never
    leaves a half-written coordinate directory that a build would pick up.

    Returns [(name, version, outcome)] for each entry it acted on; entries
    whose tree is present, or which have no cached tarball, are not listed. *)
let restore_registry_trees ~format (entries : LF.entry list) =
  List.filter_map (fun (e : LF.entry) ->
      match e.LF.source, e.LF.version, e.LF.checksum with
      | "registry:forge", Some v, Some cs ->
        let dest = coord_dir ~name:e.LF.name ~coord:v in
        if Sys.file_exists dest then None
        else begin
          match Tarball_cache.lookup cs with
          | Tarball_cache.Miss -> None
          | Tarball_cache.Corrupt { path; actual } ->
            Some (e.LF.name, v,
                  Error (Tarball_cache.corrupt_warning
                           ~label:(e.LF.name ^ " " ^ v) ~path
                           ~expected:cs ~actual))
          | Tarball_cache.Hit tarball ->
            let staging = Printf.sprintf "%s.restoring-%d" dest (Unix.getpid ()) in
            rm_rf staging;
            if extract ~tarball ~dest:staging <> 0 then begin
              rm_rf staging;
              Some (e.LF.name, v, Error (Printf.sprintf
                "%s %s: could not extract cached tarball %s" e.LF.name v tarball))
            end else
              match verify_tree ~format e staging with
              | Mismatch { expected; actual } ->
                rm_rf staging;
                Some (e.LF.name, v, Error (Printf.sprintf
                  "%s %s: the cached tarball extracts to tree hash %s, but \
                   forge.lock records %s; not restored"
                  e.LF.name v actual expected))
              | Verified | Unverifiable _ ->
                (try Sys.rename staging dest; Some (e.LF.name, v, Ok dest)
                 with Sys_error msg ->
                   rm_rf staging;
                   Some (e.LF.name, v, Error msg))
        end
      | _ -> None)
    entries

(* ------------------------------------------------------------------ *)
(*  Per-dependency assessment                                          *)
(* ------------------------------------------------------------------ *)

type status =
  | Path_present of string
  | Path_absent of string
  | Not_locked of string list
  (** git/registry dep with no lockfile coordinate; the list is the versions
      that happen to be cached anyway, which offline mode must NOT pick from *)
  | Missing of { coord : string; label : string }
  | Present of { dir : string; label : string; verdict : verdict }

(** Human label for a lockfile entry: its source and coordinate. *)
let entry_label (e : LF.entry) =
  let coord = match e.LF.commit, e.LF.version with
    | Some c, _ -> String.sub c 0 (min 7 (String.length c))
    | None, Some v -> v
    | None, None -> "?"
  in
  Printf.sprintf "%s @ %s" e.LF.source coord

let cached_versions name =
  let container = Filename.concat (deps_root ()) name in
  match Sys.readdir container with
  | exception Sys_error _ -> []
  | a ->
    Array.to_list a
    |> List.filter (fun n ->
        n <> "" && n.[0] <> '.'
        && Sys.is_directory (Filename.concat container n))
    |> List.sort compare

(** Classify each dependency of [closure] — the transitive (root, name, dep)
    walk the caller computed with the lockfile's coordinates. [verify] turns
    the tree re-hash on. *)
let assess ~verify ~state closure =
  let entries, format = match state with
    | Lockfile { entries; format; _ } -> entries, format
    | No_lockfile | Not_a_lockfile -> [], 2
  in
  List.map (fun (root, name, dep) ->
      let status =
        match dep with
        | Project.PathDep p ->
          let abs = if Filename.is_relative p then Filename.concat root p else p in
          if Sys.file_exists abs then Path_present abs else Path_absent abs
        | _ ->
          match List.find_opt (fun (e : LF.entry) -> e.LF.name = name) entries with
          | None -> Not_locked (cached_versions name)
          | Some e ->
            let coord = match e.LF.commit with
              | Some c -> Some c
              | None ->
                if e.LF.source = "registry:forge" then e.LF.version else None
            in
            (match coord with
             | None | Some "" -> Not_locked (cached_versions name)
             | Some c ->
               let dir = coord_dir ~name ~coord:c in
               let label = entry_label e in
               if not (Sys.file_exists dir) then Missing { coord = c; label }
               else
                 Present { dir; label;
                           verdict = if verify then verify_tree ~format e dir
                             else Unverifiable "not checked" })
      in
      (name, dep, status))
    closure

let module_guess name =
  String.capitalize_ascii
    (String.concat "" (List.map String.capitalize_ascii
                         (String.split_on_char '_' name)))

(** The warning for a dependency that will be left off MARCH_LIB_PATH. It
    predicts the downstream `Unknown module` error, because that error is what
    the user actually sees and it says nothing about why. *)
let skip_warning name = function
  | Missing { coord; label } ->
    Some (Printf.sprintf
      "warning: offline: dependency `%s` (%s) is not in the local cache — \
       skipping it.\n         \
       If the build fails with \"Unknown module %s\", this is why.\n         \
       Cached copies live in %s/ (this one would be %s); run `forge deps` \
       with network access to populate it."
      name label (module_guess name)
      (Filename.concat (deps_root ()) name) coord)
  | Not_locked cached ->
    let also = match cached with
      | [] -> ""
      | vs -> Printf.sprintf
                " Cached version%s %s %s not used: choosing one is version \
                 solving, which needs forge.lock."
                (if List.length vs = 1 then "" else "s")
                (String.concat ", " vs)
                (if List.length vs = 1 then "is" else "are")
    in
    Some (Printf.sprintf
      "warning: offline: dependency `%s` has no entry in forge.lock, so \
       offline mode cannot resolve it — skipping it.%s\n         \
       If the build fails with \"Unknown module %s\", this is why. Run \
       `forge deps` with network access to lock it."
      name also (module_guess name))
  | Path_absent p ->
    Some (Printf.sprintf "warning: path dependency `%s` not found at %s" name p)
  | Path_present _ | Present _ -> None
