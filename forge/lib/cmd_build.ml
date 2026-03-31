(** forge build [--release] *)

let find_march_files dir =
  let rec walk acc d =
    if not (Sys.file_exists d) then acc
    else
      Array.fold_left (fun acc name ->
          let path = Filename.concat d name in
          if Sys.is_directory path then walk acc path
          else if Filename.check_suffix name ".march" then path :: acc
          else acc)
        acc (Sys.readdir d)
  in
  walk [] dir

let build ~release ?(dump_phases=false) () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let mode = if release then "release" else "debug" in
    let build_dir =
      Filename.concat proj.Project.root
        (Filename.concat ".march" (Filename.concat "build" mode))
    in
    Project.mkdir_p build_dir;
    let lib_dir    = Filename.concat proj.Project.root "lib" in
    let config_dir = Filename.concat proj.Project.root "config" in
    let files = find_march_files lib_dir in
    if files = [] then
      Error (Printf.sprintf "no .march files found in %s" lib_dir)
    else begin
      let output    = Filename.concat build_dir proj.Project.name in
      let opt_flag  = if release then " --opt 2" else "" in
      let dump_flag = if dump_phases then " --dump-phases" else "" in
      (* Collect lib directories from path dependencies *)
      let dep_lib_paths = List.filter_map (fun (_, dep) ->
          match dep with
          | Project.PathDep rel_path ->
            let abs_path = if Filename.is_relative rel_path
              then Filename.concat proj.Project.root rel_path
              else rel_path
            in
            let d = Filename.concat abs_path "lib" in
            if Sys.file_exists d then Some d else None
          | _ -> None
        ) proj.Project.deps in
      (* MARCH_LIB_PATH: dep libs + lib/ + config/ (if present) *)
      let all_lib_paths =
        dep_lib_paths @ [lib_dir]
        @ (if Sys.file_exists config_dir then [config_dir] else [])
      in
      let lib_path_env = Printf.sprintf "MARCH_LIB_PATH=%s " (String.concat ":" all_lib_paths)
      in
      let entry = match proj.Project.entrypoint with
        | Some ep -> Filename.concat proj.Project.root ep
        | None    -> Filename.concat lib_dir (proj.Project.name ^ ".march")
      in
      let cmd =
        Printf.sprintf "%smarch --compile -o %s%s%s %s"
          lib_path_env (Filename.quote output) opt_flag dump_flag (Filename.quote entry)
      in
      let rc = Sys.command cmd in
      if rc = 0 then Ok output
      else Error (Printf.sprintf "march compiler exited with code %d" rc)
    end
