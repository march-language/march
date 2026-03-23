(** forge interactive / forge i — launch REPL with project lib in load path *)

let run () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let lib_dir = Filename.concat proj.Project.root "lib" in
    let cmd =
      if Sys.file_exists lib_dir then
        Printf.sprintf "march --repl --load-path %s" (Filename.quote lib_dir)
      else
        "march --repl"
    in
    let rc = Sys.command cmd in
    if rc = 0 then Ok ()
    else Error (Printf.sprintf "march REPL exited with code %d" rc)
