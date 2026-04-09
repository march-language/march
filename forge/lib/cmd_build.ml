(** forge build [--release] *)

(** Returns true for files that match test-file naming conventions.
    forge build (production binary) must never include these even if they
    somehow end up under lib/. *)
let is_test_file name =
  (String.length name > 5 && String.sub name 0 5 = "test_"
   && Filename.check_suffix name ".march")
  || Filename.check_suffix name "_test.march"

let find_march_files dir =
  let rec walk acc d =
    if not (Sys.file_exists d) then acc
    else
      Array.fold_left (fun acc name ->
          let path = Filename.concat d name in
          if Sys.is_directory path then walk acc path
          else if Filename.check_suffix name ".march" && not (is_test_file name)
          then path :: acc
          else acc)
        acc (Sys.readdir d)
  in
  walk [] dir

(** Read the full contents of a file, returning empty string on error. *)
let read_file path =
  try
    let ic = open_in path in
    let n  = in_channel_length ic in
    let s  = Bytes.create n in
    really_input ic s 0 n;
    close_in ic;
    Bytes.to_string s
  with _ -> ""

(** Return true if any line in [text] is exactly "@island" (trimmed). *)
let has_island_annotation text =
  let lines = String.split_on_char '\n' text in
  List.exists (fun line ->
    let t = String.trim line in
    t = "@island"
  ) lines

(** Extract the module name from the first "mod Name do" line that follows
    an "@island" annotation in [text].  Returns None if not found. *)
let extract_island_module_name text =
  let lines = Array.of_list (String.split_on_char '\n' text) in
  let n = Array.length lines in
  let i = ref 0 in
  let result = ref None in
  while !i < n && !result = None do
    if String.trim lines.(!i) = "@island" then begin
      (* Scan forward past blank/comment lines for the mod declaration *)
      let j = ref (!i + 1) in
      while !j < n && !result = None do
        let t = String.trim lines.(!j) in
        if String.length t > 4 && String.sub t 0 4 = "mod " then begin
          (* "mod Name do" or "mod Name" — extract the name token *)
          let rest = String.sub t 4 (String.length t - 4) in
          let name = match String.index_opt rest ' ' with
            | Some k -> String.sub rest 0 k
            | None   -> String.trim rest
          in
          if String.length name > 0 then result := Some name
        end else if t = "" || (String.length t >= 2 && String.sub t 0 2 = "--") then
          ()  (* skip blank lines and comments *)
        else
          j := n;  (* non-blank, non-comment, non-mod: stop scanning *)
        incr j
      done
    end;
    incr i
  done;
  !result

(** Discover all @island modules under [lib_dir].
    Returns a list of (module_name, source_path) pairs. *)
let find_island_modules lib_dir =
  let files = find_march_files lib_dir in
  List.filter_map (fun path ->
    let text = read_file path in
    if has_island_annotation text then
      match extract_island_module_name text with
      | Some name -> Some (name, path)
      | None      -> None
    else None
  ) files

(** Compile all discovered @island modules to WASM.
    Output goes to [islands_dir]/<Name>.wasm.
    Returns (compiled_count, total_count). *)
let build_islands ~lib_path_env ~islands_dir lib_dir =
  let islands = find_island_modules lib_dir in
  if islands = [] then (0, 0)
  else begin
    Project.mkdir_p islands_dir;
    let total   = List.length islands in
    let built   = ref 0 in
    List.iter (fun (name, src) ->
      let out = Filename.concat islands_dir (name ^ ".wasm") in
      let cmd =
        Printf.sprintf "%smarch --compile --target wasm32-unknown-unknown -o %s %s"
          lib_path_env (Filename.quote out) (Filename.quote src)
      in
      Printf.printf "  [island] %s -> %s\n%!" name (Filename.basename out);
      let rc = Sys.command cmd in
      if rc = 0 then incr built
      else Printf.eprintf "  [island] error compiling %s (exit %d)\n%!" src rc
    ) islands;
    (!built, total)
  end

let build ~release ?(dump_phases=false) () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let mode = if release then "release" else "debug" in
    let build_dir =
      Filename.concat proj.Project.root
        (Filename.concat ".march" (Filename.concat "build" mode))
    in
    Project.mkdir_p build_dir;
    let lib_dir    = Filename.concat proj.Project.root "lib" in
    let config_dir = Filename.concat proj.Project.root "config" in
    let files = find_march_files lib_dir in
    if files = [] then
      Error (Printf.sprintf "no .march files found in %s" lib_dir)
    else begin
      let output    = Filename.concat build_dir proj.Project.name in
      let opt_flag  = if release then " --opt 2" else "" in
      let dump_flag = if dump_phases then " --dump-phases" else "" in
      (* Collect lib directories from path dependencies *)
      let dep_lib_paths = List.filter_map (fun (dep_name, dep) ->
          match dep with
          | Project.PathDep rel_path ->
            let abs_path = if Filename.is_relative rel_path
              then Filename.concat proj.Project.root rel_path
              else rel_path
            in
            let d = Filename.concat abs_path "lib" in
            if Sys.file_exists d then Some d
            else if Sys.file_exists abs_path then Some abs_path
            else None
          | Project.GitTagDep _ | Project.GitBranchDep _ | Project.GitRevDep _ ->
            Project.git_dep_lib_path dep_name
          | _ -> None
        ) proj.Project.deps in
      (* MARCH_LIB_PATH: dep libs + lib/ + config/ (if present) *)
      let all_lib_paths =
        dep_lib_paths @ [lib_dir]
        @ (if Sys.file_exists config_dir then [config_dir] else [])
      in
      let lib_path_env = Printf.sprintf "MARCH_LIB_PATH=%s " (String.concat ":" all_lib_paths)
      in
      let entry = match proj.Project.entrypoint with
        | Some ep -> Filename.concat proj.Project.root ep
        | None    -> Filename.concat lib_dir (proj.Project.name ^ ".march")
      in
      let cmd =
        Printf.sprintf "%smarch --compile -o %s%s%s %s"
          lib_path_env (Filename.quote output) opt_flag dump_flag (Filename.quote entry)
      in
      let rc = Sys.command cmd in
      if rc = 0 then begin
        (* Compile any @island modules to WASM alongside the native binary *)
        let islands_dir = Filename.concat proj.Project.root "islands" in
        let (built, total) = build_islands ~lib_path_env ~islands_dir lib_dir in
        if total > 0 then
          Printf.printf "Islands: %d/%d compiled to %s\n%!" built total islands_dir;
        Ok output
      end
      else Error (Printf.sprintf "march compiler exited with code %d" rc)
    end
