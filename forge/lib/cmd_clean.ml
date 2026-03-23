(** forge clean [--cas|--all] — remove build artifacts *)

let rm_rf path =
  let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote path)) in
  ()

let run ~cas ~all =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let march_dir = Filename.concat proj.Project.root ".march" in
    if all then begin
      if Sys.file_exists march_dir then rm_rf march_dir;
      Printf.printf "cleaned %s\n%!" march_dir;
      Ok ()
    end else if cas then begin
      let build_dir = Filename.concat march_dir "build" in
      let cas_dir   = Filename.concat march_dir "cas" in
      if Sys.file_exists build_dir then rm_rf build_dir;
      if Sys.file_exists cas_dir   then rm_rf cas_dir;
      Printf.printf "cleaned build/ and cas/\n%!";
      Ok ()
    end else begin
      let build_dir = Filename.concat march_dir "build" in
      if Sys.file_exists build_dir then rm_rf build_dir;
      Printf.printf "cleaned build/\n%!";
      Ok ()
    end
