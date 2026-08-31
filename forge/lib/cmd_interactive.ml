(** forge interactive / forge i — launch REPL with project MARCH_LIB_PATH set *)

(** The shell command for the project REPL.  [entry] is [None] when the project
    has no entry module, in which case the REPL starts bare.

    Split out of [run] for the same reason as [Cmd_run.interp_command]: a unit
    test pins that the [[ffi]] flags are present, and that they come AFTER the
    entry file (an older `march` reads argv.(2) as the preload path, so a flag
    in that slot would break it). *)
let repl_command ~lib_path_env ~ffi_flags ~entry =
  match entry with
  | Some e ->
    Printf.sprintf "%s march repl %s%s" lib_path_env (Filename.quote e) ffi_flags
  | None -> Printf.sprintf "%s march%s" lib_path_env ffi_flags

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
    (* Link the same FFI shims as `forge run` / `forge build` (see
       Cmd_run.run).  The REPL preloads the project entry through the
       interpreter, so without --ffi-c the compiler builds no shim .so and any
       extern from a dependency's [[ffi]] sources dies with "symbol not found
       for interpreter FFI".  The flags go AFTER the entry file so an older
       `march` — which reads argv.(2) as the preload file — still behaves
       exactly as before. *)
    match Cmd_build.ffi_flags_full proj with
    | Error msg -> Error msg
    | Ok ffi_flags ->
    let cmd =
      repl_command ~lib_path_env ~ffi_flags
        ~entry:(if Sys.file_exists entry then Some entry else None)
    in
    let rc = Sys.command cmd in
    if rc = 0 then Ok ()
    else Error (Printf.sprintf "march REPL exited with code %d" rc)
