(** forge compile <file.march> — compile a single file and dump all compiler phases *)

let mkdir_p dir =
  let parts = String.split_on_char '/' dir in
  let rec loop acc = function
    | [] -> ()
    | part :: rest ->
      let path = if acc = "" then part else acc ^ "/" ^ part in
      (if path <> "" && not (Sys.file_exists path) then
         (try Unix.mkdir path 0o755
          with Unix.Unix_error (Unix.EEXIST, _, _) -> ()));
      loop path rest
  in
  loop "" parts

let run ~file () =
  if not (Sys.file_exists file) then
    Error (Printf.sprintf "file not found: %s" file)
  else if not (Filename.check_suffix file ".march") then
    Error (Printf.sprintf "expected a .march file, got: %s" file)
  else begin
    let out_dir = ".forge/compile" in
    mkdir_p out_dir;
    let base = Filename.basename file in
    let name = Filename.chop_suffix base ".march" in
    let output = Filename.concat out_dir name in
    let cmd =
      Printf.sprintf "march --dump-phases --compile -o %s %s"
        (Filename.quote output) (Filename.quote file)
    in
    let rc = Sys.command cmd in
    if rc = 0 then begin
      Printf.printf "compiled:  %s\n" output;
      Printf.printf "phases:    trace/phases/phases.json\n";
      Printf.printf "           march-phases/phases.json  (legacy alias)\n";
      Printf.printf "tip: run 'forge phases' to view phases in the browser\n%!";
      Ok ()
    end else
      Error (Printf.sprintf "march compiler exited with code %d" rc)
  end
