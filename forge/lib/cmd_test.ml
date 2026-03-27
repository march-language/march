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

let rec find_lib_files dir =
  Array.to_list (Sys.readdir dir)
  |> List.concat_map (fun entry ->
    let path = Filename.concat dir entry in
    if Sys.file_exists path && Sys.is_directory path then
      find_lib_files path
    else if Filename.check_suffix entry ".march" then [path]
    else [])

(** Find lib .march files for library projects.
    For [type = "lib"] projects, returns all .march files under lib/ so they
    are loaded before the test files (making the library's module available). *)
let find_lib_sources () =
  match Project.load () with
  | Error _ -> []
  | Ok proj ->
    if proj.Project.project_type <> Project.Lib then []
    else
      let lib_dir = Filename.concat proj.Project.root "lib" in
      if Sys.file_exists lib_dir && Sys.is_directory lib_dir then
        find_lib_files lib_dir
      else []

let invoke_march ?(verbose=false) ?(filter="") ?(coverage=false) files =
  let verbose_flag  = if verbose  then " --verbose"  else "" in
  let coverage_flag = if coverage then " --coverage" else "" in
  let filter_flag   = if filter = "" then ""
                      else Printf.sprintf " --filter=%s" (Filename.quote filter) in
  (* Prepend lib source files for library projects so the lib module is in scope. *)
  let lib_files = find_lib_sources () in
  let all_files = lib_files @ files in
  let files_str = String.concat " " (List.map Filename.quote all_files) in
  (* Set MARCH_LIB_PATH so test files can resolve `use LibModule` imports
     from the lib/ directory without needing manual env setup. *)
  (match Project.load () with
   | Ok proj when proj.Project.project_type = Project.Lib ->
     let lib_dir = Filename.concat proj.Project.root "lib" in
     let path = match Sys.getenv_opt "MARCH_LIB_PATH" with
       | Some s -> lib_dir ^ ":" ^ s | None -> lib_dir in
     Unix.putenv "MARCH_LIB_PATH" path
   | _ -> ());
  let cmd = Printf.sprintf "march test%s%s%s %s" verbose_flag coverage_flag filter_flag files_str in
  let rc = Sys.command cmd in
  if rc = 0 then Ok ()
  else Error (Printf.sprintf "test run failed (exit %d)" rc)

(** Expand any directories in [paths] to their test files; keep plain files as-is. *)
let expand_paths paths =
  List.concat_map (fun p ->
    if Sys.file_exists p && Sys.is_directory p then find_test_files p
    else [p]
  ) paths

let find_test_dir () =
  (* Try forge.toml root first, then fall back to ./test/ in cwd. *)
  let test_dir_of_root root = Filename.concat root "test" in
  match Project.load () with
  | Ok proj -> Some (test_dir_of_root proj.Project.root)
  | Error _ ->
    let cwd_test = Filename.concat (Sys.getcwd ()) "test" in
    if Sys.file_exists cwd_test && Sys.is_directory cwd_test then Some cwd_test
    else None

let run ?(verbose=false) ?(filter="") ?(coverage=false) ?(files=[]) () =
  if files <> [] then begin
    (* User provided explicit files/directories — expand dirs, then run. *)
    let expanded = expand_paths files in
    if expanded = [] then begin
      Printf.printf "no test files found\n%!";
      Ok ()
    end else
      invoke_march ~verbose ~filter ~coverage expanded
  end else
    match find_test_dir () with
    | None ->
      Error "no test/ directory found (no forge.toml and no ./test/ directory)"
    | Some test_dir ->
      if not (Sys.file_exists test_dir) then
        Error (Printf.sprintf "no test/ directory found at %s" test_dir)
      else begin
        (* Recursively discover test_*.march / *_test.march under test/ *)
        let test_files = find_test_files test_dir in
        if test_files = [] then begin
          Printf.printf "no test files found under %s\n%!" test_dir;
          Ok ()
        end else
          invoke_march ~verbose ~filter ~coverage test_files
      end
