(** forge test — discover and run test files via `march test` *)

let is_test_file name =
  (String.length name > 5 && String.sub name 0 5 = "test_"
   && Filename.check_suffix name ".march")
  || Filename.check_suffix name "_test.march"

let rec find_test_files dir =
  Array.to_list (Sys.readdir dir)
  |> List.concat_map (fun entry ->
    let path = Filename.concat dir entry in
    if Sys.file_exists path && Sys.is_directory path then
      find_test_files path
    else if is_test_file entry then [path]
    else [])

let invoke_march ?(verbose=false) ?(filter="") files =
  let verbose_flag = if verbose then " --verbose" else "" in
  let filter_flag  = if filter = "" then ""
                     else Printf.sprintf " --filter=%s" (Filename.quote filter) in
  let files_str = String.concat " " (List.map Filename.quote files) in
  let cmd = Printf.sprintf "march test%s%s %s" verbose_flag filter_flag files_str in
  let rc = Sys.command cmd in
  if rc = 0 then Ok ()
  else Error (Printf.sprintf "test run failed (exit %d)" rc)

let run ?(verbose=false) ?(filter="") ?(files=[]) () =
  if files <> [] then
    (* User provided explicit files — run only those. *)
    invoke_march ~verbose ~filter files
  else
    match Project.load () with
    | Error msg -> Error msg
    | Ok proj ->
      let test_dir = Filename.concat proj.Project.root "test" in
      if not (Sys.file_exists test_dir) then
        Error (Printf.sprintf "no test/ directory found at %s" test_dir)
      else begin
        (* Recursively discover test_*.march / *_test.march under test/ *)
        let test_files = find_test_files test_dir in
        if test_files = [] then begin
          Printf.printf "no test files found under %s\n%!" test_dir;
          Ok ()
        end else
          invoke_march ~verbose ~filter test_files
      end
