(** forge run — build then execute *)

let run () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    if proj.Project.project_type = Project.Lib then
      Error "cannot run a library project (use 'forge test' instead)"
    else
      match Cmd_build.build ~release:false with
      | Error msg -> Error msg
      | Ok binary ->
        let rc = Sys.command (Filename.quote binary) in
        if rc = 0 then Ok ()
        else Error (Printf.sprintf "program exited with code %d" rc)
