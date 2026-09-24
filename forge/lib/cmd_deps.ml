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
(*  Version-aware cache layout                                         *)
(* ------------------------------------------------------------------ *)

(** A dep's install directory is [deps/<name>/<coord>], never [deps/<name>].

    The flat layout was keyed by NAME ALONE, so two projects wanting different
    versions of one dep shared one directory. For git deps that merely caused
    thrash (the URL matched, so the checkout was reused at whatever ref it
    happened to be on); for REGISTRY deps it was destructive — install did an
    unconditional `rm -rf` of the destination with no check at all, so
    installing `bastion 0.3.1` silently deleted the `bastion 0.2.0` another
    project was building against.

    [coord] is the dep's resolved identity: the commit SHA for any git dep
    (a tag or branch can move, a commit cannot), and the exact resolved semver
    for a registry dep. Both are already recorded in forge.lock, which is what
    lets a consumer find the directory again without re-resolving. See
    `specs/2026-09-11-forge-offline-and-versioned-dep-cache-design.md` §2. *)
let dep_coord_dir ~name ~coord =
  Filename.concat (Filename.concat (cas_deps_dir ()) name) coord

(** True if [dir] looks like an INSTALLED PACKAGE rather than a container of
    coordinate directories — i.e. the pre-2026-09-12 flat layout. Keyed on
    markers a package root has and a container never does. *)
let looks_like_flat_install dir =
  Sys.file_exists (Filename.concat dir "forge.toml")
  || Sys.file_exists (Filename.concat dir "lib")
  || Sys.file_exists (Filename.concat dir ".git")

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

(** Move a legacy flat install at [deps/<name>] down to
    [deps/<name>/<coord>], preserving a warm cache across the upgrade — the
    alternative is every user re-downloading every dep. A flat install whose
    coordinate cannot be determined is moved aside rather than deleted: it may
    be something a user placed by hand.

    [coord] must identify what the flat directory ACTUALLY holds, not what is
    about to be installed. A git checkout can say ([resolve_commit] reads its
    HEAD), so callers pass [None] and let it. A registry extract cannot — it
    carries no version marker — and labelling it with the version now being
    installed would serve the old tree under the new version's name. So that
    case is moved aside instead, at the cost of one re-download.

    Returns [true] if a migration happened (so the caller can then treat
    [deps/<name>] as a container). *)
let migrate_flat_install ~name ~coord =
  let flat = Filename.concat (cas_deps_dir ()) name in
  if not (Sys.file_exists flat) then false
  else if not (looks_like_flat_install flat) then false
  else begin
    let staging = Printf.sprintf "%s.migrating.%d" flat (Unix.getpid ()) in
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote staging)));
    (* Determine the coordinate BEFORE moving anything: for a git checkout it
       is read out of the checkout itself. *)
    let coord = match coord with
      | Some c -> Some c
      | None -> resolve_commit flat
    in
    match (try Sys.rename flat staging; true with Sys_error _ -> false) with
    | false ->
      Printf.eprintf "warning: %s: could not move legacy cache dir aside\n%!" name;
      false
    | true ->
      Project.mkdir_p flat;
      (match coord with
       | Some c ->
         let target = Filename.concat flat c in
         ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote target)));
         (try Sys.rename staging target with Sys_error _ -> ());
         Printf.printf "  %s: migrated cached copy to %s/%s\n%!" name name c
       | None ->
         let aside = Printf.sprintf "%s.legacy-%.0f" flat (Unix.time ()) in
         (try Sys.rename staging aside with Sys_error _ -> ());
         Printf.printf
           "  %s: cached copy could not be identified; moved aside to %s\n%!"
           name aside);
      true
  end

(* [git_checkout_matches] / [reuse_or_clear_git_dest] lived here until
   2026-09-12. They existed because the CAS keyed an install by dep NAME alone,
   so one directory could hold content from a different source than the
   manifest now asked for; their answer was to compare the remote URL and
   `rm -rf` on a mismatch. Both the problem and that answer are gone: an
   install is keyed by its resolved coordinate ([dep_coord_dir]), so a
   different tag, rev or source is simply a different directory and nothing
   needs clearing. Removed rather than left dead, so nothing reaches for the
   URL-keyed reuse test again. *)

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
module RQ = Registry_query

(* The registry client compile, the metadata fetch and the tarball fetch all
   go through [Registry_query], whose [compile_client] / [fetch] are gated by
   [Net_gate]. This file used to carry private copies of both (and of the JSON
   parsing); two copies of a network path is one more place for an offline
   check to be missing. *)

let download_url = Dep_refetch.download_url

(** Extract a .tar.gz into [dest], stripping the single top-level directory so
    the package's own `lib/` lands directly at [dest]/lib. *)
let extract_tarball ~tarball ~dest = Offline_deps.extract ~tarball ~dest

(** Shared with the online integrity re-fetch; see [Dep_refetch]. *)
let cached_or_download = Dep_refetch.cached_or_download

(** Fetch metadata for each registry dep, version-solve with PubGrub (pinning
    path/git deps as overrides), then download+verify+extract each solved
    registry package into ~/.march/cas/deps/<name>/<version>.  Returns lockfile
    entries for the registry deps (or an error string on the first hard
    failure).

    [reg_deps]     : (name, version_constraint_string) registry deps to solve.
    [override_deps]: (name, Project.dep) path/git/branch deps that must NOT be
                     version-solved — pinned so the solver leaves them alone. *)
let resolve_registry_deps ~reg_deps ~override_deps =
  if reg_deps = [] then Ok []
  else begin
    let base = RQ.registry_base_url () in
    Printf.printf "resolving %d registry dependenc%s from %s...\n%!"
      (List.length reg_deps)
      (if List.length reg_deps = 1 then "y" else "ies") base;
    (* 1. Compile the registry client ONCE (native TLS only works compiled). *)
    Printf.printf "  compiling registry client...\n%!";
    match RQ.compile_client () with
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
            match RQ.available_versions ~binary ~registry:base name with
            | Error e ->
              meta_error := Some (Printf.sprintf "%s: %s" name e)
            | Ok [] ->
              meta_error := Some
                  (Printf.sprintf "%s: no versions found in registry metadata" name)
            | Ok vers ->
              let cs_tbl = Hashtbl.create 8 in
              Hashtbl.replace checksums name cs_tbl;
              List.iter (fun (rv : RQ.reg_version) ->
                  if not rv.RQ.rv_retired then
                    match Resolver_version.parse rv.RQ.rv_version with
                    | Error _ -> ()
                    | Ok v ->
                      Hashtbl.replace cs_tbl rv.RQ.rv_version rv.RQ.rv_checksum;
                      (* Requirements are fetched lazily only if needed; the
                         common case (leaf packages) has none, and the
                         metadata endpoint does not include them.  Register
                         each version with empty deps for now. *)
                      RR.add_version idx
                        { RR.name; version = v; deps = [] }
                ) vers
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
               (* 4. Download (or reuse the cached tarball) + verify + extract
                  each solved registry package. *)
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
                       (* Version-keyed: deps/<name>/<version>. Before this,
                          the destination was deps/<name> and the rm -rf below
                          destroyed whatever OTHER version was cached there. *)
                       ignore (migrate_flat_install ~name ~coord:None);
                       let dest = dep_coord_dir ~name ~coord:vstr in
                       (match cached_or_download ~binary ~base ~name ~vstr ~expected_cs with
                        | Error e -> install_error := Some e
                        | Ok tarball ->
                          (* Fresh extract. Removing [dest] is safe now that
                             it is version-keyed: it can only ever hold a
                             previous extract of THIS same version, never a
                             sibling version another project depends on. *)
                          if Sys.file_exists dest then
                            ignore (Sys.command
                                      (Printf.sprintf "rm -rf %s" (Filename.quote dest)));
                          let rc = extract_tarball ~tarball ~dest in
                          if rc <> 0 then
                            install_error := Some (Printf.sprintf
                                "%s %s: tar extraction failed (exit %d)" name vstr rc)
                          else begin
                            Printf.printf "  %s %s: installed to %s\n%!" name vstr dest;
                            (* Format 2: [hash] is the tree hash, in the
                               same domain as every other dep kind, so one
                               integrity check covers all of them;
                               [checksum] keeps the registry's published
                               tarball digest as provenance — and, since the
                               tarball is now cached under it, the key that
                               lets `forge deps --offline` re-extract it. *)
                            let e = Resolver_lockfile.{
                                name;
                                version = Some vstr;
                                source  = "registry:forge";
                                commit  = None;
                                hash    = content_hash ~name ~source:"registry:forge" dest;
                                checksum = Some ("sha256:" ^ expected_cs) } in
                            entries := e :: !entries
                          end)
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

(** What a refused fetch tells the user: where the cache lives and which
    command, run with network access, fills it. *)
let populate_remedy name =
  Printf.sprintf
    "Cached copies live in %s/; run `forge deps` with network access to populate it."
    (Filename.concat (cas_deps_dir ()) name)

(** Clone a git dep into its COMMIT-keyed directory.

    The commit is only knowable after the clone, so the clone goes to a staging
    directory first, then moves to [deps/<name>/<commit>]. If that directory
    already exists the staging copy is discarded and the cached one reused —
    which is both the cache hit and the reason two projects on different refs
    of one repo no longer fight over one directory.

    Replaces the old [reuse_or_clear_git_dest] flow, whose reuse test was the
    remote URL: the same URL at a different tag was reused as-is, and a
    different URL triggered `rm -rf` of a directory another project might be
    building against.

    [version] is called only on a fresh clone, to decide what goes in the
    lockfile's `version` field (a tag parses as semver; a branch or rev has
    none). *)
let clone_git_dep ~name ~url ~ref_name ~depth1 ~version =
  let source = "git:" ^ url in
  ignore (migrate_flat_install ~name ~coord:None);
  let staging =
    Filename.concat (cas_deps_dir ())
      (Printf.sprintf ".staging-%s-%d" name (Unix.getpid ())) in
  ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote staging)));
  if not (Net_gate.is_offline ()) then
    Printf.printf "  %s: cloning %s @ %s...\n%!" name url ref_name;
  let cmd =
    if depth1 then
      Printf.sprintf "git clone --depth 1 --branch %s %s %s"
        (Filename.quote ref_name) (Filename.quote url) (Filename.quote staging)
    else
      Printf.sprintf "git clone %s %s && git -C %s checkout %s"
        (Filename.quote url) (Filename.quote staging)
        (Filename.quote staging) (Filename.quote ref_name)
  in
  match
    Net_gate.command
      ~what:(Printf.sprintf "clone dependency `%s` from %s @ %s" name url ref_name)
      ~remedy:(populate_remedy name) cmd
  with
  | Error e -> Error e
  | Ok rc ->
  if rc <> 0 then begin
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote staging)));
    Error (Printf.sprintf "failed to clone %s @ %s (exit %d)" url ref_name rc)
  end else begin
    match resolve_commit staging with
    | None ->
      ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote staging)));
      Error (Printf.sprintf "%s: cloned %s but could not resolve its commit" name url)
    | Some commit ->
      let dest = dep_coord_dir ~name ~coord:commit in
      let cached_ok =
        Sys.file_exists dest
        && Resolver_cas_package.hash_directory dest
           = Resolver_cas_package.hash_directory staging in
      if cached_ok then begin
        (* Already cached at this exact commit, and the cached tree matches the
           fresh clone: keep it and throw the clone away, so a concurrent
           reader is never disturbed. *)
        ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote staging)));
        Printf.printf "  %s: already cached at %s\n%!" name commit
      end else if Sys.file_exists dest then begin
        (* Cached at this commit but the tree differs from what the commit
           holds: modified or corrupted. Reusing it here is what used to write
           the TAMPERED tree's hash into forge.lock, laundering the change
           past every later integrity check. Replace it with the clone. *)
        (match Dep_refetch.swap_in ~staging ~dest with
         | Ok () ->
           Printf.printf
             "  %s: cached copy at %s did not match the commit; replaced it \
              with the fresh clone\n%!" name commit
         | Error msg ->
           Printf.eprintf "warning: %s: could not replace the cached copy at %s: %s\n%!"
             name dest msg)
      end else begin
        Project.mkdir_p (Filename.dirname dest);
        (try Sys.rename staging dest
         with Sys_error _ ->
           (* Cross-device or a racing writer: fall back to a copy, then make
              sure staging does not leak. *)
           ignore (Sys.command (Printf.sprintf "cp -R %s %s"
                                  (Filename.quote staging) (Filename.quote dest)));
           ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote staging))));
        Printf.printf "  %s: installed to %s\n%!" name dest
      end;
      Ok Resolver_lockfile.{
          name;
          version = version ();
          source;
          commit = Some commit;
          hash = content_hash ~name ~source dest;
          checksum = None }
  end

(** Express [p] relative to [root] when it can be, so a path dep's recorded
    source is the same on every machine.

    `forge.lock` is committed and shared, but a path dep's `source` was stored
    in whatever spelling the manifest used, so an absolute declaration leaked
    the author's home directory into version control and made two developers
    with identical `forge.toml` files produce different lockfiles — and
    different `manifest_hash`es, since [content_hash] takes the source string.
    Relative declarations were already machine-independent and are returned
    unchanged, so only the absolute ones move, once.

    Falls back to the absolute path when no relative spelling exists (a
    different volume on Windows, or a root that is not a prefix and cannot be
    walked out of). Cosmetic today — nothing reads `source` to LOCATE a dep —
    but the offline-cache design makes the lockfile authoritative for dep
    identity, at which point an absolute path becomes a real failure.
    specs/todos/2026-09-11-lockfile-path-dep-source-is-sometimes-absolute.md *)
let relativize_to_root ~(root : string) (p : string) : string =
  if Filename.is_relative p then p
  else if root = "" || Filename.is_relative root then p
  else begin
    let split path =
      String.split_on_char '/' path |> List.filter (fun c -> c <> "" && c <> ".")
    in
    let rec strip_common a b =
      match a, b with
      | x :: xs, y :: ys when String.equal x y -> strip_common xs ys
      | _ -> (a, b)
    in
    let (root_rest, p_rest) = strip_common (split root) (split p) in
    (* A ".." for each root component left over, then the remainder of [p]. *)
    let ups = List.map (fun _ -> Filename.parent_dir_name) root_rest in
    match ups @ p_rest with
    | [] -> Filename.current_dir_name
    | parts -> String.concat "/" parts
  end

(** Install a dep for the first time.  Returns a (lock_entry, error option). *)
let install_dep ?(project_root = "") name (dep : Project.dep) =
  Project.mkdir_p (cas_deps_dir ());
  match dep with

  | Project.RegistryDep { version } ->
    (* Registry not yet implemented — print a notice and skip *)
    Printf.printf "  %s: registry dep (%s) — registry not yet available, skipping\n%!"
      name version;
    let e = Resolver_lockfile.{ name; version = None;
                                 source = "registry:forge";
                                 commit = None;
                                 hash = Printf.sprintf "pending:%s" name;
                                 checksum = None } in
    Ok e

  | Project.GitTagDep { url; tag } ->
    clone_git_dep ~name ~url ~ref_name:tag ~depth1:true
      ~version:(fun () ->
          match Resolver_version.parse tag with
          | Ok v  -> Some (Resolver_version.to_string v)
          | Error _ ->
            Printf.eprintf
              "warning: tag '%s' for %s is not semver — stored as-is\n%!" tag name;
            Some tag)

  | Project.GitBranchDep { url; branch } ->
    clone_git_dep ~name ~url ~ref_name:branch ~depth1:true ~version:(fun () -> None)

  | Project.GitRevDep { url; rev } ->
    (* A full clone then checkout: --depth 1 cannot take an arbitrary rev
       unless the server advertises it. *)
    clone_git_dep ~name ~url ~ref_name:rev ~depth1:false ~version:(fun () -> None)

  | Project.PathDep path ->
    if Sys.file_exists path then begin
      Printf.printf "  %s: found at %s\n%!" name path;
      (* Record the machine-independent spelling, not the declared one. *)
      let recorded = relativize_to_root ~root:project_root path in
      let hash = content_hash ~name ~source:("path:" ^ recorded) path in
      let e = Resolver_lockfile.{ name; version = None;
                                   source = "path:" ^ recorded;
                                   commit = None;
                                   hash;
                                   checksum = None } in
      Ok e
    end else
      Error (Printf.sprintf "path dep '%s' not found: %s" name path)

(** Update a dep in place (moves branch deps to new HEAD; no-ops for others). *)
let update_dep name (dep : Project.dep) =
  match dep with
  | Project.GitBranchDep _ ->
    (* Moving a branch dep to its new HEAD means landing on a DIFFERENT commit,
       which under the version-aware layout is a different directory. So an
       update is a fresh install: it clones, resolves the new commit, and lands
       at deps/<name>/<new commit>, leaving the old coordinate in place for any
       project still locked to it.
       This used to `git -C deps/<name> fetch && checkout FETCH_HEAD`, mutating
       the one shared checkout in place — the aliasing the coordinate layout
       removes, and which would now not even find a git repository there, since
       deps/<name> is a container of coordinates. *)
    (match install_dep name dep with
     | Ok _ -> Ok ()
     | Error e -> Error e)
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
    let results =
      List.map (fun (name, dep) ->
        (name, dep, install_dep ~project_root name dep)) fresh in
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

(** `forge deps --offline`: the "can I build on a plane?" check (design §3.6).

    Fetches nothing and rewrites nothing. It resolves every declared
    dependency (transitively) from forge.lock to its cache directory,
    re-extracts any registry dep whose tree is gone but whose tarball is
    cached, re-hashes each cached tree against forge.lock, and prints one line
    per dependency. Unlike a build, where a missing dep is a warning, here a
    miss IS the answer: the command exits non-zero if any dependency is
    missing or fails its integrity check. *)
let run_offline proj ~toml_content ~all_deps =
  let root = proj.Project.root in
  let state = Offline_deps.read_state ~project_root:root ~toml_content in
  let needs_lock =
    List.exists (fun (_, d) -> not (Offline_deps.is_path_dep d)) all_deps in
  match
    if needs_lock then Offline_deps.state_error ~project_root:root state else None
  with
  | Some msg -> Error msg
  | None ->
    (match state with
     | Offline_deps.Lockfile { drifted = true; _ } ->
       Printf.eprintf "%s\n%!" Offline_deps.drift_warning
     | _ -> ());
    let restore_errors = ref [] in
    (match state with
     | Offline_deps.Lockfile { entries; format; _ } ->
       List.iter (fun (name, v, r) ->
           match r with
           | Ok dir ->
             Printf.printf "  %s %s: restored from the tarball cache into %s\n%!"
               name v dir
           | Error msg -> restore_errors := msg :: !restore_errors)
         (Offline_deps.restore_registry_trees ~format entries)
     | _ -> ());
    let coords = Project.dep_coords ~project_root:root in
    let closure =
      Cmd_build.collect_transitive_deps ~coords (Hashtbl.create 16) (root, all_deps) in
    let report = Offline_deps.assess ~verify:true ~state closure in
    let missing = ref [] and corrupt = ref [] and ok = ref 0 in
    Printf.printf "offline: checking %d dependenc%s against the local cache\n%!"
      (List.length report) (if List.length report = 1 then "y" else "ies");
    List.iter (fun (name, _dep, status) ->
        match status with
        | Offline_deps.Path_present p ->
          incr ok; Printf.printf "  %s: path dependency at %s\n%!" name p
        | Offline_deps.Path_absent p ->
          missing := name :: !missing;
          Printf.printf "  %s: MISSING — path dependency not found at %s\n%!" name p
        | Offline_deps.Not_locked cached ->
          missing := name :: !missing;
          Printf.printf "  %s: MISSING — no entry in forge.lock%s\n%!" name
            (match cached with
             | [] -> ""
             | vs -> Printf.sprintf " (cached versions %s not used: \
                                     choosing one is version solving)"
                       (String.concat ", " vs))
        | Offline_deps.Missing { coord; label } ->
          missing := name :: !missing;
          Printf.printf "  %s: MISSING — %s is not in the local cache (%s)\n%!"
            name label (Offline_deps.coord_dir ~name ~coord)
        | Offline_deps.Present { dir; label; verdict } ->
          (match verdict with
           | Offline_deps.Verified ->
             incr ok; Printf.printf "  %s: cached (%s), verified\n%!" name label
           | Offline_deps.Unverifiable why ->
             incr ok;
             Printf.printf "  %s: cached (%s), not integrity-checked: %s\n%!"
               name label why
           | Offline_deps.Mismatch { expected; actual } ->
             corrupt :=
               Offline_deps.mismatch_error ~name ~label ~dir ~expected ~actual
               :: !corrupt;
             Printf.printf "  %s: CORRUPT — cached tree does not match forge.lock\n%!"
               name))
      report;
    let problems =
      List.rev !restore_errors
      @ (match List.rev !missing with
          | [] -> []
          | ms ->
            [Printf.sprintf
               "offline: %d dependenc%s not available locally: %s\n  \
                Run `forge deps` with network access to populate the cache."
               (List.length ms) (if List.length ms = 1 then "y is" else "ies are")
               (String.concat ", " ms)])
      @ List.rev !corrupt
    in
    if problems = [] then begin
      Printf.printf "offline: all %d dependencies available\n%!" !ok;
      Ok ()
    end else Error (String.concat "\n" problems)

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
    if not (Net_gate.is_offline ()) && Sys.file_exists lock_path &&
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
    if Net_gate.is_offline () then
      run_offline proj ~toml_content ~all_deps
    else if all_deps = [] then begin
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
         found transitively) accumulate in [reg_acc] instead of installing.
         [results] accumulates across every phase-1 pass, because phase 2 can
         hand back more path/git deps to install (see [drive] below). *)
      let results = ref (bfs_install visited ~reg_acc ~project_root:proj.Project.root all_deps) in
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
      (* The two phases alternate to a JOINT fixpoint.
         [resolve_wave] used to recurse on registry children only:

             List.filter_map (fun (n, d) -> match d with
               | Project.RegistryDep { version } -> Some (n, version)
               | _ -> None)                       (* git/path children dropped *)

         so registry → registry recursed but registry → git/path did not, and a
         registry package's own git dependency was never fetched. Concretely:
         bastion is a registry package declaring `depot = { git = ... }`; depot
         never arrived, and bastion's own Depot.Middleware failed to compile
         with `Module Pool not found`. Now a registry package's non-registry
         children go back through phase 1 (which may in turn surface more
         registry constraints into [reg_acc], hence the alternation).

         The existing invariants are preserved: [visited] and [seen_reg] still
         dedup by dep NAME nearest-wins, so re-entering phase 1 cannot reinstall
         or re-claim an already-seen dep, and that also terminates the
         alternation — every pass strictly grows one of the two visited sets. *)
      let rec resolve_wave pending =
        match dedup pending with
        | [] -> ()
        | wave when !reg_error = None ->
          (match resolve_registry_deps ~reg_deps:wave ~override_deps with
           | Error e -> reg_error := Some e
           | Ok es ->
             reg_entries := !reg_entries @ es;
             (* Split each just-installed registry package's own deps: registry
                children continue the phase-2 fixpoint, everything else is
                handed to phase 1, keyed by the DECLARING package's root so its
                relative PathDeps resolve correctly. *)
             let next_reg = ref [] in
             let next_nonreg = ref [] in
             List.iter (fun e ->
                 (* The version-keyed directory this entry was just
                    extracted to. This read deps/<name> — the pre-2026-09-12
                    flat path, now a container with no forge.toml — so a
                    registry package's own deps were never discovered. *)
                 let dep_dir = match e.Resolver_lockfile.version with
                   | Some v -> dep_coord_dir ~name:e.Resolver_lockfile.name ~coord:v
                   | None -> Filename.concat (cas_deps_dir ()) e.Resolver_lockfile.name in
                 if Sys.file_exists (Filename.concat dep_dir "forge.toml") then
                   match Project.load_from_dir dep_dir with
                   | Ok p ->
                     List.iter (fun (n, d) ->
                         match d with
                         | Project.RegistryDep { version } ->
                           next_reg := (n, version) :: !next_reg
                         | _ ->
                           next_nonreg := (dep_dir, (n, d)) :: !next_nonreg)
                       p.Project.deps
                   | Error _ -> ()
               ) es;
             (* Phase 1 over the non-registry children, grouped by declaring
                root. This may push new constraints into [reg_acc]. *)
             let by_root = Hashtbl.create 4 in
             List.iter (fun (root, dep) ->
                 let existing = try Hashtbl.find by_root root with Not_found -> [] in
                 Hashtbl.replace by_root root (dep :: existing)
               ) !next_nonreg;
             Hashtbl.iter (fun root deps ->
                 results :=
                   !results
                   @ bfs_install visited ~reg_acc ~project_root:root (List.rev deps)
               ) by_root;
             (* Anything phase 1 just surfaced joins this wave's registry
                children for the next pass. *)
             let carried = !reg_acc in
             reg_acc := [];
             resolve_wave (!next_reg @ carried))
        | _ -> ()
      in
      let initial_reg = !reg_acc in
      reg_acc := [];
      resolve_wave initial_reg;
      let git_errors = List.filter_map (fun (_, r) ->
          match r with Error e -> Some e | Ok _ -> None) !results in
      let git_entries = List.filter_map (fun (_, r) ->
          match r with Ok e -> Some e | Error _ -> None) !results in
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
