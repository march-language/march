(** forge format [--check] — delegate to march fmt *)

let rec collect_march_files dir =
  if not (Sys.file_exists dir) then []
  else
    Array.to_list (Sys.readdir dir)
    |> List.concat_map (fun name ->
        let path = Filename.concat dir name in
        if Sys.is_directory path then
          collect_march_files path
        else if Filename.check_suffix name ".march" then
          [path]
        else [])

let run ~check =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let dirs = [
      Filename.concat proj.Project.root "lib";
      Filename.concat proj.Project.root "test";
    ] in
    let files = List.concat_map collect_march_files dirs in
    if files = [] then begin
      Printf.printf "no .march files found\n%!";
      Ok ()
    end else begin
      let check_flag = if check then " --check" else "" in
      let files_str  = String.concat " " (List.map Filename.quote files) in
      let cmd = Printf.sprintf "march fmt%s %s" check_flag files_str in
      let rc  = Sys.command cmd in
      if rc = 0 then Ok ()
      else Error (Printf.sprintf "march fmt exited with code %d" rc)
    end
