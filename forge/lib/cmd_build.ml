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
      let files_str = String.concat " " (List.map Filename.quote files) in
      let output    = Filename.concat build_dir proj.Project.name in
      let opt_flag  = if release then " --opt 2" else "" in
      let cmd =
        match proj.Project.project_type with
        | Project.Lib ->
          (* Type-check all lib sources together (no binary output) *)
          Printf.sprintf "march check %s" files_str
        | Project.App | Project.Tool ->
          (* Compile to native binary *)
          Printf.sprintf "march --compile -o %s%s %s"
            (Filename.quote output) opt_flag files_str
      in
      let rc = Sys.command cmd in
      if rc = 0 then Ok output
      else Error (Printf.sprintf "march compiler exited with code %d" rc)
    end
