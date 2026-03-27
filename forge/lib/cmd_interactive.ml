(** forge interactive / forge i — launch REPL with project MARCH_LIB_PATH set *)

let run () =
  match Project.load () with
  | Error _msg ->
    (* Outside a project: just launch the REPL bare *)
    let rc = Sys.command "march" in
    if rc = 0 then Ok ()
    else Error (Printf.sprintf "march REPL exited with code %d" rc)
  | Ok proj ->
    let lib_dir    = Filename.concat proj.Project.root "lib" in
    let config_dir = Filename.concat proj.Project.root "config" in
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
    let all_lib_paths =
      dep_lib_paths @ [lib_dir]
      @ (if Sys.file_exists config_dir then [config_dir] else [])
    in
    let lib_path_env =
      Printf.sprintf "MARCH_LIB_PATH=%s MARCH_REPL_INTERP=1"
        (String.concat ":" all_lib_paths)
    in
    let entry = Filename.concat lib_dir (proj.Project.name ^ ".march") in
    let cmd =
      if Sys.file_exists entry
      then Printf.sprintf "%s march repl %s" lib_path_env (Filename.quote entry)
      else Printf.sprintf "%s march" lib_path_env
    in
    let rc = Sys.command cmd in
    if rc = 0 then Ok ()
    else Error (Printf.sprintf "march REPL exited with code %d" rc)
