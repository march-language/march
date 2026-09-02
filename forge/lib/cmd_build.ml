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
  | Project.GitTagDep _ | Project.GitBranchDep _ | Project.GitRevDep _
  | Project.RegistryDep _ ->
    (* Git and registry deps both install under ~/.march/cas/deps/<name>; use
       that dep's lib/ (or its root as a fallback). *)
    (match Project.git_dep_lib_path dep_name with
     | Some p -> collect_lib_dirs p
     | None  -> [])

(** Walk a project's dependency graph transitively: for every direct dep,
    also pull in ITS OWN prod [deps] (recursively), so e.g. a project
    depending on `bastion`, which itself depends on `depot`, gets `depot`
    on its MARCH_LIB_PATH too.  Each entry carries the root it should be
    resolved relative to (a PathDep is relative to the DECLARING project's
    root, not the top-level one).  Dedup is by dep name, nearest-wins (a
    project's own direct dep shadows the same name pulled in transitively),
    and a [visited] set guards against dependency cycles. *)
let collect_transitive_deps visited (root, deps) =
  (* Walk the dependency graph BREADTH-FIRST by depth, so a SHALLOWER dep
     always shadows a same-named dep reachable only through a deeper path.
     In particular every DIRECT dep of the root is claimed before any
     transitive dep is examined, so the root's own `depot = { path = ... }`
     wins over a sibling's `depot = { git = ... }`.

     The previous DEPTH-FIRST walk descended into the first sibling's own
     deps before visiting later direct siblings: for `deps = [bastion; depot]`
     where bastion depends on depot-via-git, it visited+claimed bastion's git
     `depot` first (which resolves to the empty CAS dir `~/.march/cas/deps/depot`
     and contributes NO lib path), so the root's direct path `depot` was
     dropped as already-visited — leaving depot's lib entirely off
     MARCH_LIB_PATH and every `import Depot` / depot constructor unresolvable.

     [visited] dedups by dep NAME (nearest-depth-wins); ordering of the result
     is depth-major, declared order within a depth, which is deterministic and
     keeps direct deps first on the search path. *)
  let out = ref [] in
  let frontier = ref [ (root, deps) ] in
  while !frontier <> [] do
    let level = !frontier in
    frontier := [];
    (* Pass A: claim every not-yet-seen dep at THIS depth before descending. *)
    let level_entries =
      List.concat_map (fun (root, deps) ->
          List.filter_map (fun (dep_name, dep) ->
              if Hashtbl.mem visited dep_name then None
              else begin
                Hashtbl.add visited dep_name ();
                Some (root, dep_name, dep)
              end)
            deps)
        level
    in
    out := !out @ level_entries;
    (* Pass B: enqueue the next depth from the deps just claimed. *)
    frontier :=
      List.filter_map (fun (root, dep_name, dep) ->
          match Project.dep_root_dir ~project_root:root (dep_name, dep) with
          | Some dep_dir when Sys.file_exists (Filename.concat dep_dir "forge.toml") ->
            (match Project.load_from_dir dep_dir with
             | Ok dep_proj -> Some (dep_dir, dep_proj.Project.deps)
             | Error _ -> None)
          | _ -> None)
        level_entries
  done;
  !out

(** Assemble the MARCH_LIB_PATH environment prefix used for every invocation
    of the [march] compiler.  Contains the project's own lib/, any dep lib
    roots (scoped by environment) — walked transitively — and config/ when
    present.

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
  let visited = Hashtbl.create 16 in
  let transitive_deps = collect_transitive_deps visited (proj.Project.root, scoped_deps) in
  (* A dependency's lib/ may group modules into subfolders exactly like the
     primary package (e.g. lib/api, lib/wire).  The module resolver searches
     each lib path flatly, so expand every dep lib root into the root plus all
     of its descendant directories — mirroring [collect_lib_dirs lib_dir] for
     the primary package below.  Without this, a reorganised dependency's
     internal cross-module imports fail with "Module not found" in consumers. *)
  let dep_lib_paths = List.concat_map
    (fun (root, dep_name, dep) -> dep_to_lib_paths ~root (dep_name, dep))
    transitive_deps in
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

(** Run [cmd] with its stderr captured to a temp file.
    Re-emits the captured content to forge's own stderr (with colour when the
    terminal supports it), then returns [(exit_code, captured_content)]. *)
let run_capturing_stderr cmd =
  let color_env =
    if Unix.isatty Unix.stderr then "MARCH_COLOR=always " else ""
  in
  let tmp = Filename.temp_file "forge_diag" ".tmp" in
  let rc =
    Sys.command (Printf.sprintf "%s%s 2>%s" color_env cmd (Filename.quote tmp))
  in
  let content =
    try
      let ic = open_in tmp in
      let n  = in_channel_length ic in
      let s  = Bytes.create n in
      really_input ic s 0 n;
      close_in ic;
      Bytes.to_string s
    with Sys_error _ -> ""
  in
  output_string stderr content;
  flush stderr;
  (try Sys.remove tmp with Sys_error _ -> ());
  (rc, content)

(** Count ERROR/WARNING diagnostic headers in captured compiler stderr.
    Handles both the rich block format ("-- ERROR --- file") and the simple
    one-liner format ("file:line:col: error: msg"). *)
let count_diagnostics content =
  let strip_ansi s =
    let b = Buffer.create (String.length s) in
    let i = ref 0 and n = String.length s in
    while !i < n do
      if s.[!i] = '\027' && !i + 1 < n && s.[!i + 1] = '[' then begin
        i := !i + 2;
        while !i < n && s.[!i] <> 'm' do incr i done;
        if !i < n then incr i
      end else begin
        Buffer.add_char b s.[!i]; incr i
      end
    done;
    Buffer.contents b
  in
  let has_sub s sub =
    let sl = String.length s and bl = String.length sub in
    let found = ref false and i = ref 0 in
    while not !found && !i + bl <= sl do
      if String.sub s !i bl = sub then found := true;
      incr i
    done;
    !found
  in
  List.fold_left (fun (e, w) raw ->
    let l = strip_ansi raw in
    let n = String.length l in
    if   n >= 8  && String.sub l 0 8  = "-- ERROR"   then (e + 1, w)
    else if n >= 10 && String.sub l 0 10 = "-- WARNING" then (e, w + 1)
    else if has_sub l ": error: "   then (e + 1, w)
    else if has_sub l ": warning: " then (e, w + 1)
    else (e, w)
  ) (0, 0) (String.split_on_char '\n' content)

(** Print the build/check summary line: wall time plus counts when non-zero.
    Example outputs:
      "  0.23s"
      "  3 errors, 1 warning — 0.47s" *)
let print_build_summary ~t0 ~errors ~warnings =
  let elapsed  = Unix.gettimeofday () -. t0 in
  let time_str = Printf.sprintf "%.2fs" elapsed in
  let parts =
    (if errors   > 0 then
       [Printf.sprintf "%d error%s"   errors   (if errors   = 1 then "" else "s")]
     else [])
    @
    (if warnings > 0 then
       [Printf.sprintf "%d warning%s" warnings (if warnings = 1 then "" else "s")]
     else [])
  in
  if parts = [] then
    Printf.printf "  %s\n%!" time_str
  else
    Printf.printf "  %s \xe2\x80\x94 %s\n%!" (String.concat ", " parts) time_str

(** Digest [files]' sorted paths + contents + [lib_path_env], so any edit to
    a checked file or a change to MARCH_LIB_PATH invalidates the cache below.

    Known limitation: this does NOT hash the *contents* of directories on
    MARCH_LIB_PATH, only the env-var string itself.  Editing a local
    `path = "../foo"` dependency's source in place, without touching
    forge.toml/forge.lock (and thus without changing MARCH_LIB_PATH), will
    not invalidate this cache.  Delete `.forge/check-cache/` if that bites. *)
let check_all_cache_key ~lib_path_env files =
  let buf = Buffer.create 4096 in
  List.iter (fun f ->
      Buffer.add_string buf f;
      (try
         let ic = open_in_bin f in
         let n = in_channel_length ic in
         let b = Bytes.create n in
         really_input ic b 0 n;
         close_in ic;
         Buffer.add_bytes buf b
       with Sys_error _ -> ())
    ) (List.sort String.compare files);
  Buffer.add_string buf lib_path_env;
  Digest.to_hex (Digest.string (Buffer.contents buf))

(** Typecheck every file in [files] together in a single [march check]
    subprocess, so the stdlib and any shared imports are parsed and
    typechecked once instead of once per file (previously: one subprocess
    per file, each re-parsing the whole stdlib).  On a fully-clean repeat
    call (no errors, no warnings, nothing changed) short-circuits via
    [cache_dir] instead of invoking [march] at all, so a repeated no-op
    `forge build`/`forge check` doesn't regress relative to the old
    per-file behavior (which benefited from the compiler's own CAS cache).
    Returns [(n_failed, total_errors, total_warnings)]; n_failed is 0 or 1
    since all files are checked as one combined module. *)
let check_all ~lib_path_env ~cache_dir files =
  if files = [] then (0, 0, 0)
  else begin
    let key = check_all_cache_key ~lib_path_env files in
    let marker = Filename.concat cache_dir (key ^ ".clean") in
    if Sys.file_exists marker then (0, 0, 0)
    else begin
      let quoted = String.concat " " (List.map Filename.quote files) in
      let cmd = Printf.sprintf "%smarch check %s" lib_path_env quoted in
      let (rc, content) = run_capturing_stderr cmd in
      let (e, w) = count_diagnostics content in
      if rc = 0 && e = 0 && w = 0 then begin
        (try Project.mkdir_p cache_dir with Sys_error _ -> ());
        (try
           let oc = open_out marker in
           close_out oc
         with Sys_error _ -> ())
      end;
      ((if rc = 0 then 0 else 1), e, w)
    end
  end

(** FFI shim flags from forge.toml [[ffi]]: --ffi-c per source (resolved to an
    absolute path under [root]) and --ffi-link per linker flag. *)
let ffi_flags_of ~root (proj : Project.project) =
  let srcs = List.map (fun s ->
      let p = if Filename.is_relative s then Filename.concat root s else s in
      " --ffi-c " ^ Filename.quote p) proj.Project.ffi_sources in
  let links = List.map (fun l -> " --ffi-link " ^ Filename.quote l) proj.Project.ffi_link in
  String.concat "" (srcs @ links)

(** Full FFI flags for [proj]: the [[ffi]] C sources/links from [ffi_flags_of]
    plus, if [[ffi.rust]] is declared, a `cargo build --release` of the crate and
    a --ffi-link to its staticlib archive.  Shared by [forge build] and
    [forge test] so both link the same native shims.  Returns [Error] if the
    Rust build fails or its archive is missing. *)
let ffi_flags_full ?(target_is_cross=false) (proj : Project.project) : (string, string) result =
  let rust_link_flags_result =
    match proj.Project.ffi_rust with
    | None -> Ok ""
    | Some _ when target_is_cross ->
      (* P1: the Rust crate is built for the host via `cargo build` (no --target),
         so it cannot link into a cross Linux binary. Fail loudly rather than
         silently producing a broken artifact. Cross Rust FFI (cargo-zigbuild)
         is a follow-up. *)
      Error "this project uses [ffi.rust]; cross-compilation of Rust bindings is \
             not yet supported. Build on Linux, or use `forge deploy hot --so`."
    | Some frc ->
      let crate_dir =
        if Filename.is_relative frc.Project.frc_path then
          Filename.concat proj.Project.root frc.Project.frc_path
        else frc.Project.frc_path
      in
      let archive =
        Filename.concat crate_dir
          (Filename.concat "target"
             (Filename.concat "release"
                ("lib" ^ frc.Project.frc_lib ^ ".a")))
      in
      Printf.printf "  [ffi.rust] cargo build --release in %s\n%!" crate_dir;
      let rc = Sys.command
        (Printf.sprintf "cd %s && cargo build --release 2>&1"
           (Filename.quote crate_dir))
      in
      if rc <> 0 then
        Error (Printf.sprintf "ffi.rust: cargo build failed (exit %d)" rc)
      else if not (Sys.file_exists archive) then
        Error (Printf.sprintf "ffi.rust: expected archive not found: %s" archive)
      else begin
        Printf.printf "  [ffi.rust] linked %s\n%!" archive;
        Ok (" --ffi-link " ^ Filename.quote archive)
      end
  in
  match rust_link_flags_result with
  | Error _ as e -> e
  | Ok rust_link_flags ->
    Ok (ffi_flags_of ~root:proj.Project.root proj ^ rust_link_flags)

(** Filename extension for a build's output, by target.  Shared by the project
    build and by the single-file [forge run FILE --compiled] path, which names
    a temp output the same way. *)
let output_ext = function
  | Some ("js" | "javascript") -> ".mjs"
  | Some t when String.length t >= 4 && String.sub t 0 4 = "wasm" -> ".wasm"
  | _ -> ""

(** Compile the entry file to [output]. [target] is passed as --target <t>;
    omitting it compiles to a native binary.
    Returns [(exit_code, n_errors, n_warnings)]. *)
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
  let (rc, content) = run_capturing_stderr cmd in
  let (e, w) = count_diagnostics content in
  (rc, e, w)

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

(** Write package.json and run npm install for [js_deps] declared in forge.toml.
    Called before JS compilation so imported npm packages are available.
    No-op when js_deps is empty. *)
let ensure_js_deps ~root (proj : Project.project) =
  if proj.Project.js_deps = [] then Ok ()
  else begin
    let pkg_path = Filename.concat root "package.json" in
    (* Build the deps JSON object. *)
    let deps_json =
      String.concat ",\n    "
        (List.map (fun (name, ver) ->
           Printf.sprintf {|"%s": "%s"|} name ver
         ) proj.Project.js_deps)
    in
    (* Read existing package.json or start with a minimal skeleton. *)
    let existing =
      if Sys.file_exists pkg_path then
        try let ic = open_in pkg_path in
            let n = in_channel_length ic in
            let s = Bytes.create n in
            really_input ic s 0 n; close_in ic; Bytes.to_string s
        with _ -> ""
      else ""
    in
    (* Only write if the deps section would change.
       Simple heuristic: check if every declared dep appears verbatim in the file. *)
    let needs_write =
      not (List.for_all (fun (name, ver) ->
        let needle = Printf.sprintf {|"%s": "%s"|} name ver in
        let len = String.length existing - String.length needle in
        let found = ref false in
        for i = 0 to len do
          if String.sub existing i (String.length needle) = needle then found := true
        done;
        !found
      ) proj.Project.js_deps)
    in
    if needs_write then begin
      let pkg_name = proj.Project.name in
      let pkg_version = proj.Project.version in
      let json =
        Printf.sprintf {|{
  "name": "%s",
  "version": "%s",
  "type": "module",
  "dependencies": {
    %s
  }
}
|} pkg_name pkg_version deps_json
      in
      (try
        let oc = open_out pkg_path in
        output_string oc json; close_out oc;
        Printf.printf "  [js_deps] wrote package.json\n%!"
       with Sys_error msg ->
         Printf.eprintf "  [js_deps] warning: could not write package.json: %s\n%!" msg)
    end;
    Printf.printf "  [js_deps] npm install...\n%!";
    let rc = Sys.command (Printf.sprintf "cd %s && npm install --silent 2>&1" (Filename.quote root)) in
    if rc = 0 then Ok ()
    else Error (Printf.sprintf "npm install failed (exit %d)" rc)
  end

let build ~release ?(dump_phases=false) ?(frozen=false) ?target () =
  let t0 = Unix.gettimeofday () in
  (* Normalize cross-target aliases to the compiler's canonical form and derive
     a per-target output subdir so a Linux build never clobbers the host binary. *)
  let target = Option.map (fun t ->
    match t with
    | "linux/x86_64" | "linux-x86_64" -> "linux/amd64"
    | "linux/aarch64" | "linux-arm64" -> "linux/arm64"
    | other -> other) target in
  let target_subdir = match target with
    | Some "linux/amd64" -> "linux-amd64"
    | Some "linux/arm64" -> "linux-arm64"
    | _ -> "" in
  match Project.load () with
  | Error msg -> Error msg
  | Ok _ when target_subdir <> ""
              && Sys.command "command -v zig >/dev/null 2>&1" <> 0 ->
    Error (Printf.sprintf
      "cross target %s requires `zig` (used as the C cross-compiler).\n  Install: brew install zig"
      (Option.value ~default:"" target))
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
      let base = Filename.concat proj.Project.root
        (Filename.concat ".march" "build") in
      let base = if target_subdir = "" then base else Filename.concat base target_subdir in
      Filename.concat base mode
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
        let cache_dir = Filename.concat proj.Project.root (Filename.concat ".forge" "check-cache") in
        let (failed, errors, warnings) = check_all ~lib_path_env ~cache_dir files in
        print_build_summary ~t0 ~errors ~warnings;
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
        let cache_dir = Filename.concat proj.Project.root (Filename.concat ".forge" "check-cache") in
        let (orphan_failed, te, tw) = check_all ~lib_path_env ~cache_dir orphan_files in
        if orphan_failed > 0 then begin
          print_build_summary ~t0 ~errors:te ~warnings:tw;
          Error "typecheck failed"
        end else begin
          let output =
            Filename.concat build_dir (proj.Project.name ^ output_ext target) in
          (* FFI shim flags: [[ffi]] C sources/links plus, if declared, a built
             [[ffi.rust]] staticlib archive (shared with [forge test]). *)
          match ffi_flags_full ~target_is_cross:(target_subdir <> "") proj with
          | Error msg -> Error msg
          | Ok ffi_flags ->
          (* Install npm packages declared in [js_deps] before JS compilation. *)
          let npm_result = match target with
            | Some ("js" | "javascript") ->
              ensure_js_deps ~root:proj.Project.root proj
            | _ -> Ok ()
          in
          match npm_result with
          | Error e -> Error e
          | Ok () ->
          let (rc, ce, cw) = compile_entry ~lib_path_env ~ffi_flags ~output ~release ~dump_phases ?target entry_path in
          print_build_summary ~t0 ~errors:(te + ce) ~warnings:(tw + cw);
          if rc = 0 then begin
            do_islands ();
            Ok output
          end
          else Error (Printf.sprintf "march compiler exited with code %d" rc)
        end
    end
