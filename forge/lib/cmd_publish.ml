(** forge publish — validate and publish a package to the registry.

    Workflow:
      1. Load the project (forge.toml).
      2. If --old-source is supplied, extract the old and new API surfaces
         and check the semver bump.  Print a SEMVER VIOLATION error and
         exit 1 if the declared version bump is too small.
      3. Otherwise, print a success notice.
      4. Unless --dry-run, package + submit to the registry via the embedded
         registry.march client (Registry_client.run_action).

    --old-source PATH   Path to a directory containing the previous
                        version's source tree (must have forge.toml).
    --dry-run           Validate only; do not submit to registry.
    --registry URL      Registry base URL (default: FORGE_REGISTRY env var,
                        or https://forgepm.org if unset).
    --insecure          Allow a http:// registry (local dev only).
*)

let run ~old_source_dir ~dry_run ~registry ~insecure () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let name    = proj.Project.name in
    let version = proj.Project.version in
    Printf.printf "publishing %s %s...\n%!" name version;
    (* Publishing hygiene: nudge (non-fatal) when no license is declared. *)
    (match proj.Project.license with
     | Some l when String.trim l <> "" -> ()
     | _ -> Printf.eprintf
              "warning: no `license` field in forge.toml; consider adding one (e.g. license = \"MIT\")\n%!");

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
          let old_surf, old_failed =
            Resolver_api_surface.extract_from_directory_checked old_dir in
          let new_surf, new_failed =
            Resolver_api_surface.extract_from_directory_checked proj.Project.root in
          let failed = old_failed @ new_failed in
          let changes  = Resolver_api_surface.diff ~old_:old_surf ~new_:new_surf in
          if failed <> [] then begin
            (* An unparseable file makes the surface incomplete, and a missing
               public item is indistinguishable from a deleted one — so a
               "no breaking changes" verdict here would be unsound rather than
               merely approximate. Refuse to certify the bump instead of
               waving the release through on a partial surface. *)
            Printf.eprintf
              "error: cannot verify the semver bump: %d source file(s) failed to \
               parse, so the API surface is incomplete and a removed public item \
               would be indistinguishable from one that was never seen:\n%!"
              (List.length failed);
            List.iter (fun (path, msg) ->
                Printf.eprintf "  %s: %s\n%!" path msg) failed;
            false
          end else
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
      let registry_url =
        match registry with
        | Some r -> r
        | None ->
          (match Sys.getenv_opt "FORGE_REGISTRY" with
           | Some r -> r
           | None -> "https://forgepm.org")
      in
      match Registry_client.validate_registry_url ~registry:registry_url ~insecure with
      | Error msg -> Error msg
      | Ok () ->
        let token = match Sys.getenv_opt "FORGE_TOKEN" with Some t -> t | None -> "" in
        if token = "" then
          Error "FORGE_TOKEN is required (an API key with the 'publish' permission) — set it in your environment, never pass it as a flag"
        else begin
          let rc =
            Registry_client.run_action ~action:"publish" ~token
              ~registry:registry_url ~pkg_dir:proj.Project.root ~extra_env:[]
          in
          if rc = 0 then Ok ()
          else Error (Printf.sprintf "publish failed (exit %d) — see output above" rc)
        end
    end
