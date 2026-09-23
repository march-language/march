(** forge check

    Typecheck every .march file under lib/ via [march --check], plus the
    entry point for app/tool projects.  Emits no binary and skips island
    WASM generation.  Returns a non-zero exit status if any file fails.

    This is the fast feedback command for editor / pre-commit use: it
    catches orphan modules that have bit-rotted without paying for codegen
    or linking.  [forge build] also runs the same checks, but additionally
    produces the binary and island sidecars. *)

let check ?(_quiet = false) () =
  let t0 = Unix.gettimeofday () in
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let lib_dir = Filename.concat proj.Project.root "lib" in
    let files   = Cmd_build.find_march_files lib_dir in
    let entry =
      match proj.Project.project_type with
      | Project.Lib -> None
      | Project.App | Project.Tool -> Some (Project.entry proj)
    in
    if files = [] && not (match entry with Some (Ok _) -> true | _ -> false) then
      Error (Printf.sprintf "no .march files found in %s" lib_dir)
    else begin
      match Cmd_build.offline_preflight
              ~scope:(Cmd_build.build_scope ~release:false proj) proj with
      | Error e -> Error e
      | Ok () ->
      let lib_path_env = Cmd_build.lib_path_env proj in
      (* For app/tool: include the entry even if it lives outside lib/.
         For lib: files already covers everything. *)
      match (match entry with Some (Error e) -> Error e | _ -> Ok ()) with
      | Error e -> Error e
      | Ok () ->
      let all_files =
        match entry with
        | None | Some (Error _) -> files
        | Some (Ok entry_path) ->
          (* Avoid duplicate-checking the entry if it already lives under lib/. *)
          let entry_abs = try Unix.realpath entry_path with _ -> entry_path in
          let already_included = List.exists (fun f ->
            let a = try Unix.realpath f with _ -> f in
            a = entry_abs
          ) files in
          if already_included then files else entry_path :: files
      in
      let cache_dir = Filename.concat proj.Project.root (Filename.concat ".forge" "check-cache") in
      let (failed, errors, warnings) = Cmd_build.check_all ~lib_path_env ~cache_dir all_files in
      Cmd_build.print_build_summary ~t0 ~errors ~warnings;
      if failed > 0 then
        Error "typecheck failed"
      else
        Ok (Printf.sprintf "checked %d file(s) in %s" (List.length all_files) lib_dir)
    end
