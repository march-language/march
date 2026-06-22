(** forge build [--release]

    Build behavior depends on [forge.toml]'s [package.type]:

    - [app]: compile the entry point to a native binary.  Every other .march
      file under lib/ is additionally typechecked via [march --check] so
      orphan modules cannot silently rot.

    - [lib]: typecheck every .march file under lib/ via [march --check].
      No binary is produced — a library has no single entry, and consumers
      may import any module.

    - [tool]: same as [app].

    In all cases [build_islands] then walks @island modules and emits their
    WASM sidecars. *)

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
    else begin
      (* Sort entries: raw Sys.readdir order is filesystem-dependent, which
         would make file discovery order nondeterministic across machines. *)
      let entries = Sys.readdir d in
      Array.sort compare entries;
      Array.fold_left (fun acc name ->
          let path = Filename.concat d name in
          if Sys.is_directory path then walk acc path
          else if Filename.check_suffix name ".march" && not (is_test_file name)
          then path :: acc
          else acc)
        acc entries
    end
  in
  walk [] dir

(** Collect [dir] plus every nested subdirectory under it.

    The module resolver searches each lib path FLATLY (it does not recurse
    into subdirectories when resolving an [import]).  To let projects group
    their lib/ modules into subfolders without rewriting every import, we
    expand a lib root into the root plus all of its descendant directories
    so each one becomes an independent entry on MARCH_LIB_PATH.

    Entries are sorted so MARCH_LIB_PATH order is deterministic across
    machines (raw [Sys.readdir] order is filesystem-dependent). *)
let collect_lib_dirs dir =
  let rec walk acc d =
    if not (Sys.file_exists d && Sys.is_directory d) then acc
    else begin
      let acc = d :: acc in
      let entries = Sys.readdir d in
      Array.sort compare entries;
      Array.fold_left (fun acc name ->
          let path = Filename.concat d name in
          if Sys.is_directory path then walk acc path else acc)
        acc entries
    end
  in
  List.rev (walk [] dir)

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
let build_islands ~lib_path_env ~islands_dir ~release lib_dir =
  let islands = find_island_modules lib_dir in
  if islands = [] then (0, 0)
  else begin
    Project.mkdir_p islands_dir;
    let total   = List.length islands in
    let built   = ref 0 in
    let opt_flag = if release then " --opt 2" else " --opt 0" in
    List.iter (fun (name, src) ->
      let out = Filename.concat islands_dir (name ^ ".wasm") in
      let cmd =
        Printf.sprintf "%smarch --compile --target wasm32-unknown-unknown%s -o %s %s"
          lib_path_env opt_flag (Filename.quote out) (Filename.quote src)
      in
      Printf.printf "  [island] %s -> %s\n%!" name (Filename.basename out);
      let rc = Sys.command cmd in
      if rc = 0 then incr built
      else Printf.eprintf "  [island] error compiling %s (exit %d)\n%!" src rc
    ) islands;
    (!built, total)
  end

(** Expand a single dep entry into the lib paths it contributes to MARCH_LIB_PATH.
    PathDeps are resolved relative to [root]; git deps use the CAS install path. *)
let dep_to_lib_paths ~root (dep_name, dep) =
  match dep with
  | Project.PathDep rel_path ->
    let abs_path = if Filename.is_relative rel_path
      then Filename.concat root rel_path
      else rel_path
    in
    let d = Filename.concat abs_path "lib" in
    if Sys.file_exists d then collect_lib_dirs d
    else if Sys.file_exists abs_path then collect_lib_dirs abs_path
    else []
  | Project.GitTagDep _ | Project.GitBranchDep _ | Project.GitRevDep _ ->
    (match Project.git_dep_lib_path dep_name with
     | Some p -> collect_lib_dirs p
     | None  -> [])
  | _ -> []

(** Assemble the MARCH_LIB_PATH environment prefix used for every invocation
    of the [march] compiler.  Contains the project's own lib/, any dep lib
    roots (scoped by environment), and config/ when present.

    [release=true]  → only prod [deps] are on the path (ships to users).
    [release=false] → [deps] + [dev-deps] + [dev-only-deps] are included. *)
let lib_path_env ?(release=false) proj =
  let lib_dir    = Filename.concat proj.Project.root "lib" in
  let config_dir = Filename.concat proj.Project.root "config" in
  (* Collect deps for the current build scope. *)
  let scoped_deps =
    if release then proj.Project.deps
    else proj.Project.deps @ proj.Project.dev_deps @ proj.Project.dev_only_deps
  in
  (* A dependency's lib/ may group modules into subfolders exactly like the
     primary package (e.g. lib/api, lib/wire).  The module resolver searches
     each lib path flatly, so expand every dep lib root into the root plus all
     of its descendant directories — mirroring [collect_lib_dirs lib_dir] for
     the primary package below.  Without this, a reorganised dependency's
     internal cross-module imports fail with "Module not found" in consumers. *)
  let dep_lib_paths = List.concat_map
    (dep_to_lib_paths ~root:proj.Project.root) scoped_deps in
  let gen_dir = Filename.concat proj.Project.root ".forge/generated" in
  let all_lib_paths =
    dep_lib_paths @ collect_lib_dirs lib_dir
    @ (if Sys.file_exists gen_dir then [gen_dir] else [])
    @ (if Sys.file_exists config_dir then [config_dir] else [])
  in
  (* Put the resolved toolchain (project .march-version pin, else global) first
     on PATH so the bare `march` in the commands below uses the pinned version.
     Quote each path so a metachar in a project/dep path can't inject shell. *)
  let toolchain_pfx = match Toolchain.path_prefix () with Ok p -> p | Error _ -> "" in
  let quoted = String.concat ":" (List.map Filename.quote all_lib_paths) in
  Printf.sprintf "%sMARCH_LIB_PATH=%s " toolchain_pfx quoted

(** Typecheck [file] via [march --check].
    Returns [true] on clean exit, [false] on any compiler error.
    The compiler itself prints diagnostics to stderr — we don't intercept. *)
let check_file ~lib_path_env file =
  let cmd =
    Printf.sprintf "%smarch --check %s"
      lib_path_env (Filename.quote file)
  in
  Sys.command cmd = 0

(** Typecheck every .march file in [files] individually.
    Returns the number of files that failed (0 means clean). *)
let check_all ~lib_path_env files =
  List.fold_left (fun failed f ->
    if check_file ~lib_path_env f then failed else failed + 1
  ) 0 files

(** FFI shim flags from forge.toml [[ffi]]: --ffi-c per source (resolved to an
    absolute path under [root]) and --ffi-link per linker flag. *)
let ffi_flags_of ~root (proj : Project.project) =
  let srcs = List.map (fun s ->
      let p = if Filename.is_relative s then Filename.concat root s else s in
      " --ffi-c " ^ Filename.quote p) proj.Project.ffi_sources in
  let links = List.map (fun l -> " --ffi-link " ^ Filename.quote l) proj.Project.ffi_link in
  String.concat "" (srcs @ links)

(** Compile the entry file to [output]. [target] is passed as --target <t>;
    omitting it compiles to a native binary. *)
let compile_entry ~lib_path_env ~ffi_flags ~output ~release ~dump_phases ?target entry =
  let opt_flag    = if release then " --opt 2" else " --opt 0" in
  let dump_flag   = if dump_phases then " --dump-phases" else "" in
  let target_flag = match target with Some t -> " --target " ^ t | None -> "" in
  (* Optional List.pmap sequential-fallback cutoff, passed through to the
     compiler.  Sourced from MARCH_PMAP_THRESHOLD so the value can flow
     without a forge.toml schema change. *)
  let pmap_flag =
    match Sys.getenv_opt "MARCH_PMAP_THRESHOLD" with
    | Some v when v <> "" -> " --pmap-threshold=" ^ v
    | _ -> ""
  in
  let cmd =
    Printf.sprintf "%smarch --compile -o %s%s%s%s%s%s %s"
      lib_path_env (Filename.quote output) opt_flag pmap_flag target_flag dump_flag ffi_flags (Filename.quote entry)
  in
  Sys.command cmd

(** Find files matching a given extension under [dir], recursively. *)
let find_files_with_ext ext dir =
  let rec walk acc d =
    if not (Sys.file_exists d) then acc
    else
      Array.fold_left (fun acc name ->
          let path = Filename.concat d name in
          if Sys.is_directory path then walk acc path
          else if Filename.check_suffix name ext
          then path :: acc
          else acc)
        acc (Sys.readdir d)
  in
  walk [] dir

(** Run preprocessors declared in forge.toml.
    For each [preprocessors] entry (extension → command), find matching files
    under [src_dir], run the command, and write output to [gen_dir].
    Returns the number of files processed. *)
let run_preprocessors ~proj ~src_dir ~gen_dir =
  if proj.Project.preprocessors = [] then 0
  else begin
    Project.mkdir_p gen_dir;
    let count = ref 0 in
    List.iter (fun (ext, command) ->
      let files = find_files_with_ext ext src_dir in
      List.iter (fun input_path ->
        let root_prefix = proj.Project.root ^ "/" in
        let rlen = String.length root_prefix in
        let rel =
          if String.length input_path >= rlen &&
             String.sub input_path 0 rlen = root_prefix
          then String.sub input_path rlen (String.length input_path - rlen)
          else input_path
        in
        let base = Filename.chop_suffix rel ext in
        let output_march = Filename.concat gen_dir (base ^ ".march") in
        let output_spans = Filename.concat gen_dir (base ^ ".march.spans") in
        let output_dir = Filename.dirname output_march in
        Project.mkdir_p output_dir;
        let input_mtime =
          try (Unix.stat input_path).Unix.st_mtime with _ -> 0.0
        in
        let output_mtime =
          try (Unix.stat output_march).Unix.st_mtime with _ -> 0.0
        in
        if input_mtime > output_mtime then begin
          let cmd = Printf.sprintf "%s %s %s %s"
            command
            (Filename.quote input_path)
            (Filename.quote output_march)
            (Filename.quote output_spans)
          in
          let rc = Sys.command cmd in
          if rc = 0 then begin
            Printf.printf "  [preprocess] %s\n%!" rel;
            incr count
          end else
            Printf.eprintf "  [preprocess] error processing %s (exit %d)\n%!" rel rc
        end
      ) files
    ) proj.Project.preprocessors;
    !count
  end

let build ~release ?(dump_phases=false) ?(frozen=false) ?target () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    (* --frozen: a lockfile out of date with forge.toml is an error, not a
       silent re-resolve (CI reproducibility). *)
    let lock = Filename.concat proj.Project.root "forge.lock" in
    let drifted =
      Sys.file_exists lock
      && Resolver_lockfile.has_drifted lock
           (Project.read_file (Filename.concat proj.Project.root "forge.toml"))
    in
    if Cmd_licenses.frozen_error ~drifted ~frozen then
      Error "forge.lock is out of date with forge.toml; --frozen forbids re-resolving — run `forge deps`"
    else
    (* Enforce an optional `march = "~> X.Y"` constraint in forge.toml against
       the resolved toolchain — before any download. *)
    match
      match proj.Project.march_req, Toolchain.resolve_version () with
      | Some req, Some resolved -> Toolchain.check_constraint ~resolved ~req
      | Some req, None ->
        Printf.eprintf
          "warning: forge.toml requires march %s, but no toolchain is pinned or \
           active; cannot verify it (using `march` on PATH)\n%!" req;
        Ok ()
      | None, _ -> Ok ()
    with
    | Error e -> Error e
    | Ok () ->
    (* Auto-install the pinned/global toolchain if it isn't present yet. *)
    match Toolchain.ensure_installed () with
    | Error e -> Error e
    | Ok () ->
    (* Option B: warn (never override) if forge.lock recorded a different
       toolchain than the one resolved for this build. *)
    (let lock = Filename.concat proj.Project.root "forge.lock" in
     match Toolchain.toolchain_drift
             ~locked:(Resolver_lockfile.read_toolchain lock)
             ~resolved:(Toolchain.resolve_version ()) with
     | Some w -> Printf.eprintf "%s\n%!" w
     | None   -> ());
    let mode = if release then "release" else "debug" in
    let build_dir =
      Filename.concat proj.Project.root
        (Filename.concat ".march" (Filename.concat "build" mode))
    in
    Project.mkdir_p build_dir;
    let lib_dir = Filename.concat proj.Project.root "lib" in
    let src_dir = Filename.concat proj.Project.root "src" in
    (* Run preprocessors on src/ and lib/ *)
    let gen_dir = Filename.concat proj.Project.root ".forge/generated" in
    let _pp_count = run_preprocessors ~proj ~src_dir ~gen_dir in
    let _pp_count2 = run_preprocessors ~proj ~src_dir:lib_dir ~gen_dir in
    let gen_files =
      if Sys.file_exists gen_dir then find_march_files gen_dir else []
    in
    let files = find_march_files lib_dir @ gen_files in
    if files = [] then
      Error (Printf.sprintf "no .march files found in %s" lib_dir)
    else begin
      let lib_path_env = lib_path_env ~release proj in
      let entry_path = match proj.Project.entrypoint with
        | Some ep -> Filename.concat proj.Project.root ep
        | None    -> Filename.concat lib_dir (proj.Project.name ^ ".march")
      in
      let do_islands () =
        let islands_dir = Filename.concat proj.Project.root "islands" in
        let (built, total) = build_islands ~lib_path_env ~islands_dir ~release lib_dir in
        if total > 0 then
          Printf.printf "Islands: %d/%d compiled to %s\n%!" built total islands_dir
      in
      match proj.Project.project_type with
      | Project.Lib ->
        let failed = check_all ~lib_path_env files in
        if failed > 0 then
          Error "typecheck failed"
        else begin
          do_islands ();
          Ok (Printf.sprintf "checked %d file(s) in %s" (List.length files) lib_dir)
        end
      | Project.App | Project.Tool ->
        (* Check every lib/ file individually before compilation so that orphan
           modules (not imported by the entry) don't silently rot.  This runs
           before compile_entry so failures report "typecheck failed" rather
           than a linker or runtime error. *)
        let orphan_files =
          let abs_entry = try Unix.realpath entry_path with _ -> entry_path in
          List.filter (fun f ->
            let abs_f = try Unix.realpath f with _ -> f in
            abs_f <> abs_entry
          ) files
        in
        let orphan_failed = check_all ~lib_path_env orphan_files in
        if orphan_failed > 0 then
          Error "typecheck failed"
        else begin
          let output_ext = match target with
            | Some ("js" | "javascript") -> ".mjs"
            | Some t when String.length t >= 4 && String.sub t 0 4 = "wasm" -> ".wasm"
            | _ -> ""
          in
          let output = Filename.concat build_dir (proj.Project.name ^ output_ext) in
          let ffi_flags = ffi_flags_of ~root:proj.Project.root proj in
          let rc = compile_entry ~lib_path_env ~ffi_flags ~output ~release ~dump_phases ?target entry_path in
          if rc = 0 then begin
            do_islands ();
            Ok output
          end
          else Error (Printf.sprintf "march compiler exited with code %d" rc)
        end
    end
