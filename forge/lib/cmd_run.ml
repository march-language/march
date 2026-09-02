(** forge run — run a March program through the interpreter (fast for
    development) or, with --compiled, through the LLVM pipeline.

    The entry is either the project's (forge.toml [package] entrypoint, else
    lib/<name>.march) or a single file named on the command line.  Both resolve
    to the same pair — an entry path plus the context it runs in — so only
    [resolve_entry] knows the difference. *)

(** Where a run gets its module search path and native FFI shims. *)
type context = {
  lib_path_env : string;  (** MARCH_LIB_PATH=... prefix, incl. the toolchain PATH *)
  ffi_flags    : string;  (** --ffi-c/--ffi-link flags, each with a leading space *)
}

let empty_context = { lib_path_env = ""; ffi_flags = "" }

(** Install the resolved toolchain if absent (so the PATH prefix
    [Cmd_build.lib_path_env] builds actually points at something), then collect
    the project's search path and FFI shims. *)
let context_of_project proj =
  match Toolchain.ensure_installed () with
  | Error e -> Error e
  | Ok () ->
    match Cmd_build.ffi_flags_full proj with
    | Error msg -> Error msg
    | Ok ffi_flags -> Ok { lib_path_env = Cmd_build.lib_path_env proj; ffi_flags }

(** Resolve what to run and the context to run it in.

    [file] names a single .march file.  It still picks up the surrounding
    project's lib path and FFI shims when there is one, so a scratch file can
    import that project's own modules; with no project it runs bare, the same
    fallback [Cmd_test.run_files] uses for ad-hoc test files.

    Without [file], the project's entry is used and a project is required. *)
let resolve_entry ?file () =
  match file with
  | Some f ->
    if not (Sys.file_exists f) then
      Error (Printf.sprintf "file not found: %s" f)
    else if Sys.is_directory f then
      Error (Printf.sprintf "not a file: %s" f)
    else
      (match Project.load () with
       | Error _   -> Ok (f, empty_context)
       | Ok proj   -> Result.map (fun ctx -> (f, ctx)) (context_of_project proj))
  | None ->
    match Project.load () with
    | Error msg -> Error msg
    | Ok proj ->
      let entry = match proj.Project.entrypoint with
        | Some ep -> Filename.concat proj.Project.root ep
        | None    ->
          Filename.concat proj.Project.root
            (Filename.concat "lib" (proj.Project.name ^ ".march"))
      in
      if not (Sys.file_exists entry) then
        Error (Printf.sprintf "entry point not found: %s" entry)
      else Result.map (fun ctx -> (entry, ctx)) (context_of_project proj)

(** The shell command for an interpreted run.

    Split out of [run] so the FFI flags are pinned by a unit test
    (forge/test/test_forge.ml, "interp_command"): dropping them here is
    invisible to every project without [[ffi]] sources, and fatal — with an
    unhelpful "symbol not found for interpreter FFI" — to every project with
    them.  [ffi_flags] and [dump_flag] already carry their own leading space
    (see [Cmd_build.ffi_flags_of]).

    [args] goes last, behind --args: the compiler collects every remaining
    token there (Arg.Rest_all), so anything emitted after it would be swallowed
    as a program argument.  [args] distinguishes "don't pass --args at all"
    ([None]) from "pass --args with an empty argument list" ([Some []]): the
    project-entry path uses [None] when there are no arguments, keeping its
    command byte-identical to what forge has always run (pinned by
    [test_interp_command_no_ffi_is_unchanged]); the single-named-FILE path
    always passes [Some _], even when empty, so the interpreted program's
    argv is always exactly [ [entry] @ args ] instead of leaking the march
    binary itself as argv[0] when no program arguments are given (`march
    f.march --args` with nothing after --args yields argv = [f.march], per
    test/test_prog_argv.ml's test_args_with_nothing_after_is_script_only).

    Takes a trailing unit: [?args] sits between two required *labeled*
    arguments ([ffi_flags] and [entry]), and OCaml can only erase an optional
    argument to its default when a positional argument follows it in the
    application — a labeled one, no matter how many, never triggers erasure
    (this is "unerasable-optional-argument", warning 16). Without the trailing
    [()], every call that omits [~args] — including the pre-existing
    no-[[ffi]] case — would type as [?args:string list option -> string]
    instead of [string]. *)
let interp_command ~lib_path_env ~dump_flag ~ffi_flags ?(args = None) ~entry () =
  let args_flag =
    match args with
    | None -> ""
    | Some args ->
      let quoted = List.map Filename.quote args in
      " --args" ^ (if quoted = [] then "" else " " ^ String.concat " " quoted)
  in
  Printf.sprintf "%smarch%s%s %s%s"
    lib_path_env dump_flag ffi_flags (Filename.quote entry) args_flag

(** Execute a built artifact with the program's own arguments. *)
let exec_output ~target ~args output =
  let quoted = String.concat " " (List.map Filename.quote args) in
  let sep = if args = [] then "" else " " in
  let cmd = match target with
    | Some ("js" | "javascript") ->
      Printf.sprintf "node %s%s%s" (Filename.quote output) sep quoted
    | _ -> Printf.sprintf "%s%s%s" (Filename.quote output) sep quoted
  in
  let rc = Sys.command cmd in
  if rc = 0 then Ok ()
  else Error (Printf.sprintf "program exited with code %d" rc)

(** [run] branches on [compiled] and [file] together, in one match, so every
    combination is handled in exactly one place and none is reachable-but-
    unhandled:

    - [(true, None)]: a plain compiled PROJECT build.  This is the one
      combination that needs nothing from [resolve_entry] — it hands off
      entirely to [Cmd_build.build], which resolves its own entry and
      re-derives its own context.  Calling [resolve_entry] first would redo
      that work for a result thrown away — re-running any [[ffi.rust]]
      `cargo build` (and re-printing its output) a second time on every
      invocation, including every poll of `forge watch run`, and
      [Sys.file_exists]-checking the entry before [Cmd_build.build]'s own
      preprocessors have had a chance to generate it.
    - [(false, _)]: an interpreted run, project entry or named FILE alike.
    - [(true, Some _)]: a compiled single-FILE run: compile straight to a
      disposable temp output (the CAS caches the real work).

    Splitting this three ways up front — rather than deciding on [compiled]
    first and re-matching on [file] inside — means there is no leftover
    "[compiled] and [file] is somehow [None] after all" arm to fill with a
    placeholder; the impossible case simply isn't expressible. *)
let run ?(dump_phases = false) ?(compiled = false) ?target ?file ?(args = []) () =
  match compiled, file with
  | true, None ->
    (match Cmd_build.build ~release:false ~dump_phases ?target () with
     | Error msg -> Error msg
     | Ok output -> exec_output ~target ~args output)
  | false, _ ->
    (match resolve_entry ?file () with
     | Error msg -> Error msg
     | Ok (entry, ctx) ->
       let dump_flag = if dump_phases then " --dump-phases" else "" in
       let cmd =
         interp_command ~lib_path_env:ctx.lib_path_env ~dump_flag
           ~ffi_flags:ctx.ffi_flags
           ~args:(match file with
                  | Some _ -> Some args
                  | None   -> if args = [] then None else Some args)
           ~entry ()
       in
       let rc = Sys.command cmd in
       if rc = 0 then Ok ()
       else Error (Printf.sprintf "program exited with code %d" rc))
  | true, Some _ ->
    (match resolve_entry ?file () with
     | Error msg -> Error msg
     | Ok (entry, ctx) ->
       (* Single file: compile straight to a temp output.  The CAS caches the
          real work, so the artifact itself is disposable and is removed after
          the run rather than littering the cwd. *)
       let output =
         Filename.temp_file "forge-run-" (Cmd_build.output_ext target) in
       (* temp_file creates the file; the compiler wants to write it itself. *)
       (try Sys.remove output with Sys_error _ -> ());
       Fun.protect
         ~finally:(fun () ->
             try if Sys.file_exists output then Sys.remove output
             with Sys_error _ -> ())
         (fun () ->
            let (rc, _errors, _warnings) =
              Cmd_build.compile_entry ~lib_path_env:ctx.lib_path_env
                ~ffi_flags:ctx.ffi_flags ~output ~release:false ~dump_phases
                ?target entry
            in
            if rc <> 0 then
              Error (Printf.sprintf "march compiler exited with code %d" rc)
            else exec_output ~target ~args output))
