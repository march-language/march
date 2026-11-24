(** forge clean [--cas|--all] — remove build artifacts *)

let rm_rf path =
  let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote path)) in
  ()

(** Remove the dependency-grants files forge writes under [.forge/]
    ([dep-grants-<digest>], content-addressed, never deleted by a build so
    that commands running at once cannot remove each other's) and any
    [dep-grants.*.tmp] a crash left between writing and renaming.  The next
    command that runs march writes the one it needs again.  Every mode of
    [forge clean] does this. *)
let sweep_dep_grants (proj : Project.project) =
  let dir = Filename.concat proj.Project.root ".forge" in
  match Sys.readdir dir with
  | exception Sys_error _ -> ()
  | names ->
    Array.iter (fun n ->
        if String.starts_with ~prefix:"dep-grants-" n
        || (String.starts_with ~prefix:"dep-grants." n && Filename.check_suffix n ".tmp")
        then (try Sys.remove (Filename.concat dir n) with Sys_error _ -> ()))
      names

let run ~cas ~all =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    sweep_dep_grants proj;
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
