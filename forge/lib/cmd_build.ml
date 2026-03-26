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

let build ~release =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let mode = if release then "release" else "debug" in
    let build_dir =
      Filename.concat proj.Project.root
        (Filename.concat ".march" (Filename.concat "build" mode))
    in
    Project.mkdir_p build_dir;
    let src_dir =
      match proj.Project.project_type with
      | Project.Lib  -> Filename.concat proj.Project.root "lib"
      | Project.App
      | Project.Tool -> Filename.concat proj.Project.root "src"
    in
    let files = find_march_files src_dir in
    if files = [] then
      Error (Printf.sprintf "no .march files found in %s" src_dir)
    else begin
      let output    = Filename.concat build_dir proj.Project.name in
      let opt_flag  = if release then " --opt 2" else "" in
      (* Collect lib directories from path dependencies *)
      let dep_lib_paths = List.filter_map (fun (_, dep) ->
          match dep with
          | Project.PathDep rel_path ->
            let abs_path = if Filename.is_relative rel_path
              then Filename.concat proj.Project.root rel_path
              else rel_path
            in
            let lib_dir = Filename.concat abs_path "lib" in
            if Sys.file_exists lib_dir then Some lib_dir else None
          | Project.GitDep _ -> None
        ) proj.Project.deps in
      (* Also add src_dir itself to MARCH_LIB_PATH so imports within src/ are found *)
      let all_lib_paths = dep_lib_paths @ [src_dir] in
      let lib_path_env = Printf.sprintf "MARCH_LIB_PATH=%s " (String.concat ":" all_lib_paths)
      in
      let cmd =
        match proj.Project.project_type with
        | Project.Lib ->
          (* Type-check all lib sources together (no binary output) *)
          let files_str = String.concat " " (List.map Filename.quote files) in
          Printf.sprintf "%smarch check %s" lib_path_env files_str
        | Project.App | Project.Tool ->
          (* For app/tool: pass the single entry point; the resolver finds other files
             via MARCH_LIB_PATH. Entry point is main.march if present, else first file. *)
          let entry =
            let main = Filename.concat src_dir "main.march" in
            if List.mem main files then main
            else List.hd files
          in
          Printf.sprintf "%smarch --compile -o %s%s %s"
            lib_path_env (Filename.quote output) opt_flag (Filename.quote entry)
      in
      let rc = Sys.command cmd in
      if rc = 0 then Ok output
      else Error (Printf.sprintf "march compiler exited with code %d" rc)
    end
