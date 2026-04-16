(** forge test — discover and compile+run test files via the compile pipeline.

    `forge test` compiles lib/ + test/ together using `march --compile --test`,
    producing a standalone test-runner binary that uses the same CAS as
    `forge build`.  The test binary accepts --verbose / -v and --filter=PATTERN
    at runtime.

    Fallback: when MARCH_TEST_INTERPRETER=1 is set in the environment, the old
    interpreter path (`march test`) is used instead. *)

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

(** Expand any directories in [paths] to their test files; keep plain files as-is. *)
let expand_paths paths =
  List.concat_map (fun p ->
    if Sys.file_exists p && Sys.is_directory p then find_test_files p
    else [p]
  ) paths

let find_test_dir () =
  let test_dir_of_root root = Filename.concat root "test" in
  match Project.load () with
  | Ok proj -> Some (test_dir_of_root proj.Project.root)
  | Error _ ->
    let cwd_test = Filename.concat (Sys.getcwd ()) "test" in
    if Sys.file_exists cwd_test && Sys.is_directory cwd_test then Some cwd_test
    else None

(** Compile and run test files using the compile pipeline (march --compile --test).
    [entry] is the single test entrypoint file (the one with test blocks).
    [lib_path_env] is the MARCH_LIB_PATH prefix (same as forge build).
    [seed] forwards to property tests via MARCH_PROP_SEED env var. *)
let invoke_compiled ?(verbose=false) ?(filter="") ?(seed="") ?(skip_properties=false) ~lib_path_env ~output test_entry =
  let verbose_flag = if verbose then " --verbose" else "" in
  let filter_flag  = if filter = "" then ""
                     else Printf.sprintf " --filter=%s" (Filename.quote filter) in
  let seed_env = if seed = "" then ""
                 else Printf.sprintf "MARCH_PROP_SEED=%s " (Filename.quote seed) in
  let skip_env = if skip_properties then "MARCH_SKIP_PROPERTIES=1 " else "" in
  (* Build: compile test entry with --compile --test *)
  let build_cmd =
    Printf.sprintf "%smarch --compile --test -o %s %s"
      lib_path_env (Filename.quote output) (Filename.quote test_entry)
  in
  let build_rc = Sys.command build_cmd in
  if build_rc <> 0 then
    Error (Printf.sprintf "test compilation failed (exit %d)" build_rc)
  else begin
    (* Run the compiled test binary *)
    let run_cmd = Printf.sprintf "%s%s%s%s%s" skip_env seed_env (Filename.quote output) verbose_flag filter_flag in
    let run_rc = Sys.command run_cmd in
    if run_rc = 0 then Ok ()
    else Error (Printf.sprintf "tests failed (exit %d)" run_rc)
  end

(** Interpreter fallback: invoke `march test` directly.
    Used when MARCH_TEST_INTERPRETER=1. *)
let invoke_march_interp ?(verbose=false) ?(filter="") ?(coverage=false) ?(seed="") ?(skip_properties=false) ~lib_path_env files =
  let verbose_flag  = if verbose  then " --verbose"  else "" in
  let coverage_flag = if coverage then " --coverage" else "" in
  let filter_flag   = if filter = "" then ""
                      else Printf.sprintf " --filter=%s" (Filename.quote filter) in
  let seed_flag     = if seed = "" then ""
                      else Printf.sprintf " --seed=%s" (Filename.quote seed) in
  let skip_flag     = if skip_properties then " --skip-properties" else "" in
  let files_str = String.concat " " (List.map Filename.quote files) in
  let cmd = Printf.sprintf "%smarch test%s%s%s%s%s %s"
      lib_path_env verbose_flag coverage_flag filter_flag seed_flag skip_flag files_str in
  let rc = Sys.command cmd in
  if rc = 0 then Ok ()
  else Error (Printf.sprintf "test run failed (exit %d)" rc)

(** Build the MARCH_LIB_PATH prefix string and test output path for a project. *)
let project_env proj =
  let lib_dir    = Filename.concat proj.Project.root "lib" in
  let config_dir = Filename.concat proj.Project.root "config" in
  let dep_lib_paths = List.filter_map (fun (_, dep) ->
      match dep with
      | Project.PathDep rel_path ->
        let abs = if Filename.is_relative rel_path
          then Filename.concat proj.Project.root rel_path else rel_path in
        let d = Filename.concat abs "lib" in
        if Sys.file_exists d then Some d else None
      | _ -> None
    ) proj.Project.deps in
  let all_lib_paths =
    dep_lib_paths @ [lib_dir]
    @ (if Sys.file_exists config_dir then [config_dir] else [])
  in
  let lib_path_env =
    Printf.sprintf "MARCH_LIB_PATH=%s " (String.concat ":" all_lib_paths) in
  (* Test binary goes in .march/build/test/ — same CAS root as forge build. *)
  let test_build_dir =
    Filename.concat proj.Project.root
      (Filename.concat ".march" (Filename.concat "build" "test"))
  in
  Project.mkdir_p test_build_dir;
  let output = Filename.concat test_build_dir (proj.Project.name ^ "_test") in
  (lib_path_env, output)

(** Run forge test for a given list of test files (after directory expansion). *)
let run_files ?(verbose=false) ?(filter="") ?(coverage=false) ?(seed="") ?(skip_properties=false) test_files =
  (* coverage is only supported on the interpreter path *)
  let use_interp = coverage || Sys.getenv_opt "MARCH_TEST_INTERPRETER" = Some "1" in
  match Project.load () with
  | Error _ ->
    (* No project: fall back to interpreter for ad-hoc files. *)
    invoke_march_interp ~verbose ~filter ~coverage ~seed ~skip_properties ~lib_path_env:"" test_files
  | Ok proj ->
    let (lib_path_env, output) = project_env proj in
    if use_interp then
      invoke_march_interp ~verbose ~filter ~coverage ~seed ~skip_properties ~lib_path_env test_files
    else begin
      (* Compiled path: we need a single entry point.  When multiple test files
         are present, use the first one as entry — MARCH_LIB_PATH includes the
         test dir so all test files are resolved as imports.
         For multi-file test suites, the convention is that test files live in
         test/ and the compiler auto-discovers them via MARCH_LIB_PATH. *)
      let test_dir = Filename.concat proj.Project.root "test" in
      let lib_path_with_test =
        if Sys.file_exists test_dir
        then Printf.sprintf "MARCH_LIB_PATH=%s:%s "
               test_dir
               (match Sys.getenv_opt "MARCH_LIB_PATH" with
                | Some s -> s
                | None ->
                  let lib_dir = Filename.concat proj.Project.root "lib" in
                  lib_dir)
        else lib_path_env
      in
      (* Use first test file as entry; MARCH_LIB_PATH provides the rest. *)
      let entry = List.hd test_files in
      invoke_compiled ~verbose ~filter ~seed ~skip_properties ~lib_path_env:lib_path_with_test ~output entry
    end

let run ?(verbose=false) ?(filter="") ?(coverage=false) ?(seed="") ?(skip_properties=false) ?(files=[]) () =
  if files <> [] then begin
    let expanded = expand_paths files in
    if expanded = [] then begin
      Printf.printf "no test files found\n%!";
      Ok ()
    end else
      run_files ~verbose ~filter ~coverage ~seed ~skip_properties expanded
  end else
    match find_test_dir () with
    | None ->
      Error "no test/ directory found (no forge.toml and no ./test/ directory)"
    | Some test_dir ->
      if not (Sys.file_exists test_dir) then
        Error (Printf.sprintf "no test/ directory found at %s" test_dir)
      else begin
        let test_files = find_test_files test_dir in
        if test_files = [] then begin
          Printf.printf "no test files found under %s\n%!" test_dir;
          Ok ()
        end else
          run_files ~verbose ~filter ~coverage ~seed test_files
      end
