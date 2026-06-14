(** forge version [<patch|minor|major>|<X.Y.Z>] [--tag]

    No arg: print the current version. A bump kind or an explicit semver:
    rewrite `[package].version` in forge.toml. With --tag: require a clean tree,
    commit the bump, and create an annotated git tag `vX.Y.Z`. *)

let git_tree_clean root =
  Sys.command (Printf.sprintf "git -C %s diff --quiet && git -C %s diff --cached --quiet"
                 (Filename.quote root) (Filename.quote root)) = 0

let resolve_new ~cur ~spec =
  match Versioning.kind_of_string spec with
  | Some k ->
    (match Resolver_version.parse cur with
     | Ok v -> Ok (Resolver_version.to_string (Versioning.bump k v))
     | Error e -> Error (Printf.sprintf "current version %S is not semver: %s" cur e))
  | None ->
    (match Resolver_version.parse spec with
     | Ok v -> Ok (Resolver_version.to_string v)
     | Error _ -> Error (Printf.sprintf "expected patch|minor|major or X.Y.Z, got %S" spec))

let run ?(spec = "") ?(tag = false) () =
  match Project.load () with
  | Error e -> Error e
  | Ok proj ->
    let root = proj.Project.root and cur = proj.Project.version in
    if spec = "" then (Printf.printf "%s\n" cur; Ok ())
    else
      Result.bind (resolve_new ~cur ~spec) (fun new_v ->
        if tag && not (git_tree_clean root) then
          Error "working tree is dirty; commit or stash changes before `forge version --tag`"
        else begin
          let toml_path = Filename.concat root "forge.toml" in
          let updated =
            Versioning.rewrite_version_line ~toml:(Project.read_file toml_path) ~new_version:new_v
          in
          let oc = open_out toml_path in
          Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc updated);
          Printf.printf "%s -> %s\n" cur new_v;
          if not tag then Ok ()
          else
            let rc =
              Sys.command (Printf.sprintf
                "git -C %s add forge.toml && git -C %s commit -q -m %s && git -C %s tag -a %s -m %s"
                (Filename.quote root) (Filename.quote root) (Filename.quote ("v" ^ new_v))
                (Filename.quote root) (Filename.quote ("v" ^ new_v)) (Filename.quote ("v" ^ new_v)))
            in
            if rc = 0 then (Printf.printf "committed + tagged v%s\n" new_v; Ok ())
            else Error (Printf.sprintf "git commit/tag failed (does tag v%s already exist?)" new_v)
        end)
