(** forge run — run app through the March interpreter (fast for development) *)

let run () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    if proj.Project.project_type = Project.Lib then
      Error "cannot run a library project (use 'forge test' instead)"
    else begin
      let src_dir = Filename.concat proj.Project.root "src" in
      (* Find the entry point: prefer main.march, else first .march file *)
      let all_files =
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
        walk [] src_dir
      in
      if all_files = [] then
        Error (Printf.sprintf "no .march files found in %s" src_dir)
      else begin
        let entry =
          let main = Filename.concat src_dir "main.march" in
          if List.mem main all_files then main
          else List.hd all_files
        in
        (* Build MARCH_LIB_PATH from path deps + src_dir (for intra-src imports) *)
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
        let all_lib_paths = dep_lib_paths @ [src_dir] in
        let lib_path_env =
          Printf.sprintf "MARCH_LIB_PATH=%s" (String.concat ":" all_lib_paths)
        in
        let cmd = Printf.sprintf "%s march %s"
          lib_path_env (Filename.quote entry) in
        let rc = Sys.command cmd in
        if rc = 0 then Ok ()
        else Error (Printf.sprintf "program exited with code %d" rc)
      end
    end
