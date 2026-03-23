(** forge interactive / forge i — launch REPL *)

let run () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok _proj ->
    (* march launches the REPL when invoked with no file arguments *)
    let rc = Sys.command "march" in
    if rc = 0 then Ok ()
    else Error (Printf.sprintf "march REPL exited with code %d" rc)
