(** forge publish — validate and publish a package to the registry.

    Workflow:
      1. Load the project (forge.toml).
      2. If --old-source is supplied, extract the old and new API surfaces
         and check the semver bump.  Print a SEMVER VIOLATION error and
         exit 1 if the declared version bump is too small.
      3. Otherwise, print a success notice.  Actual network push to a
         registry server is Phase 6 work.

    --old-source PATH   Path to a directory containing the previous
                        version's source tree (must have forge.toml).
    --dry-run           Validate only; do not submit to registry.
*)

let run ~old_source_dir ~dry_run () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let name    = proj.Project.name in
    let version = proj.Project.version in
    Printf.printf "publishing %s %s...\n%!" name version;

    (* Semver check: only when a previous source tree is given *)
    let semver_ok =
      match old_source_dir with
      | None ->
        Printf.printf
          "note: no --old-source supplied; skipping semver enforcement\n%!";
        true
      | Some old_dir ->
        if not (Sys.file_exists old_dir) then begin
          Printf.eprintf
            "error: --old-source directory not found: %s\n%!" old_dir;
          false
        end else begin
          let old_version =
            match Project.load_from_dir old_dir with
            | Ok p    -> p.Project.version
            | Error _ -> "0.0.0"
          in
          let old_surf = Resolver_api_surface.extract_from_directory old_dir in
          let new_surf = Resolver_api_surface.extract_from_directory proj.Project.root in
          let changes  = Resolver_api_surface.diff ~old_:old_surf ~new_:new_surf in
          (match Resolver_api_surface.check_semver_bump
                   ~old_version ~new_version:version ~changes with
           | Resolver_api_surface.Ok ->
             if changes = [] then
               Printf.printf "API surface: no changes (PATCH)\n%!"
             else
               Printf.printf "API surface: %s changes — bump is correct\n%!"
                 (Resolver_api_surface.string_of_change_kind
                    (Resolver_api_surface.required_bump changes));
             true
           | Resolver_api_surface.UnderBumped { required; declared; breaking } ->
             Printf.eprintf "%s\n%!"
               (Resolver_api_surface.format_underBumped
                  name old_version version required declared breaking);
             false)
        end
    in
    if not semver_ok then
      Error "semver violation — see above"
    else if dry_run then begin
      Printf.printf
        "dry-run: package validated, not submitted to registry\n%!";
      Ok ()
    end else begin
      (* Actual registry push is Phase 6 work (registry server not yet built) *)
      Printf.printf
        "note: registry push not yet implemented — package validated locally\n%!";
      Printf.printf "ok: %s %s is ready to publish\n%!" name version;
      Ok ()
    end
