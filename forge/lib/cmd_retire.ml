(** forge retire — retire a published version of the current package.

    forge retire <VERSION> [--reason TEXT] [--registry URL] [--insecure]

    Runs from a package directory (reads ./forge.toml to determine the
    package name). See forgepm/specs/forge-publish-client.md §2.2 for the
    registry contract this drives. *)

let run ~version ~reason ~registry ~insecure () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    if version = "" then
      Error "a version to retire is required"
    else begin
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
          Error "FORGE_TOKEN is required (an API key with the 'retire' permission) — set it in your environment, never pass it as a flag"
        else begin
          Printf.printf "retiring %s %s...\n%!" proj.Project.name version;
          let rc =
            Registry_client.run_action ~action:"retire" ~token
              ~registry:registry_url ~pkg_dir:proj.Project.root
              ~extra_env:[ ("FORGE_VERSION", version); ("FORGE_REASON", reason) ]
          in
          if rc = 0 then Ok ()
          else Error (Printf.sprintf "retire failed (exit %d) — see output above" rc)
        end
    end
