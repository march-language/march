(** forge build [--release] *)

let find_march_files dir =
  if not (Sys.file_exists dir) then []
  else
    Array.to_list (Sys.readdir dir)
    |> List.filter_map (fun name ->
        if Filename.check_suffix name ".march" then
          Some (Filename.concat dir name)
        else None)

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
    let lib_dir = Filename.concat proj.Project.root "lib" in
    let files   = find_march_files lib_dir in
    if files = [] then
      Error (Printf.sprintf "no .march files found in %s" lib_dir)
    else begin
      let files_str = String.concat " " (List.map Filename.quote files) in
      let output    = Filename.concat build_dir proj.Project.name in
      let opt_flag  = if release then " --opt 2" else "" in
      (* march --compile -o <out> [--opt N] <file> *)
      let cmd = Printf.sprintf "march --compile -o %s%s %s"
          (Filename.quote output) opt_flag files_str in
      let rc = Sys.command cmd in
      if rc = 0 then Ok output
      else Error (Printf.sprintf "march compiler exited with code %d" rc)
    end
