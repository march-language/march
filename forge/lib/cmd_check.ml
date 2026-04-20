(** forge check

    Typecheck every .march file under lib/ via [march --check], plus the
    entry point for app/tool projects.  Emits no binary and skips island
    WASM generation.  Returns a non-zero exit status if any file fails.

    This is the fast feedback command for editor / pre-commit use: it
    catches orphan modules that have bit-rotted without paying for codegen
    or linking.  [forge build] also runs the same checks, but additionally
    produces the binary and island sidecars. *)

let check ?(_quiet = false) () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let lib_dir = Filename.concat proj.Project.root "lib" in
    let files   = Cmd_build.find_march_files lib_dir in
    if files = [] then
      Error (Printf.sprintf "no .march files found in %s" lib_dir)
    else begin
      let lib_path_env = Cmd_build.lib_path_env proj in
      (* For app/tool: include the entry even if it lives outside lib/.
         For lib: files already covers everything. *)
      let all_files =
        match proj.Project.project_type with
        | Project.Lib -> files
        | Project.App | Project.Tool ->
          let entry_path = match proj.Project.entrypoint with
            | Some ep -> Filename.concat proj.Project.root ep
            | None    -> Filename.concat lib_dir (proj.Project.name ^ ".march")
          in
          (* Avoid duplicate-checking the entry if it already lives under lib/. *)
          let entry_abs = try Unix.realpath entry_path with _ -> entry_path in
          let already_included = List.exists (fun f ->
            let a = try Unix.realpath f with _ -> f in
            a = entry_abs
          ) files in
          if already_included then files else entry_path :: files
      in
      (* One march --check call auto-discovers all MARCH_LIB_PATH files, so
         a single invocation typechecks everything in O(N) instead of O(N²). *)
      let ok = match all_files with
        | [] -> true
        | first :: _ -> Cmd_build.check_file ~lib_path_env first
      in
      if not ok then
        Error "typecheck failed"
      else
        Ok (Printf.sprintf "checked %d file(s) in %s" (List.length all_files) lib_dir)
    end
