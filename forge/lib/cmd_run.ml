(** forge run — run app through the March interpreter (fast for development) *)

let run ?(dump_phases=false) ?(compiled=false) () =
  if compiled then begin
    match Cmd_build.build ~release:false ~dump_phases () with
    | Error msg -> Error msg
    | Ok binary ->
      let rc = Sys.command (Filename.quote binary) in
      if rc = 0 then Ok ()
      else Error (Printf.sprintf "program exited with code %d" rc)
  end else
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    begin
      let lib_dir    = Filename.concat proj.Project.root "lib" in
      let config_dir = Filename.concat proj.Project.root "config" in
      (* Entry point: use forge.toml [package] entrypoint if set, else lib/<name>.march *)
      let entry = match proj.Project.entrypoint with
        | Some ep -> Filename.concat proj.Project.root ep
        | None    -> Filename.concat lib_dir (proj.Project.name ^ ".march")
      in
      if not (Sys.file_exists entry) then
        Error (Printf.sprintf "entry point not found: %s" entry)
      else begin
        (* Build MARCH_LIB_PATH: dep lib dirs + lib/ + config/ (if present) *)
        let dep_lib_paths = List.filter_map (fun (dep_name, dep) ->
            match dep with
            | Project.PathDep rel_path ->
              let abs_path = if Filename.is_relative rel_path
                then Filename.concat proj.Project.root rel_path
                else rel_path
              in
              let d = Filename.concat abs_path "lib" in
              if Sys.file_exists d then Some d
              else if Sys.file_exists abs_path then Some abs_path
              else None
            | Project.GitTagDep _ | Project.GitBranchDep _ | Project.GitRevDep _ ->
              Project.git_dep_lib_path dep_name
            | _ -> None
          ) proj.Project.deps in
        let extra_dirs =
          dep_lib_paths @ [lib_dir]
          @ (if Sys.file_exists config_dir then [config_dir] else [])
        in
        let lib_path_env =
          Printf.sprintf "MARCH_LIB_PATH=%s" (String.concat ":" extra_dirs)
        in
        let dump_flag = if dump_phases then " --dump-phases" else "" in
        let cmd = Printf.sprintf "%s march%s %s"
          lib_path_env dump_flag (Filename.quote entry) in
        let rc = Sys.command cmd in
        if rc = 0 then Ok ()
        else Error (Printf.sprintf "program exited with code %d" rc)
      end
    end
