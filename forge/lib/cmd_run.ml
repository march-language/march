(** forge run — run app through the March interpreter (fast for development) *)

(** The shell command for an interpreted `forge run`.

    Split out of [run] so the FFI flags are pinned by a unit test
    (forge/test/test_forge.ml, "interp_command"): dropping them here is
    invisible to every project without [[ffi]] sources, and fatal — with an
    unhelpful "symbol not found for interpreter FFI" — to every project with
    them.  [ffi_flags] and [dump_flag] already carry their own leading space
    (see [Cmd_build.ffi_flags_of]). *)
let interp_command ~lib_path_env ~dump_flag ~ffi_flags ~entry =
  Printf.sprintf "%smarch%s%s %s"
    lib_path_env dump_flag ffi_flags (Filename.quote entry)

let run ?(dump_phases=false) ?(compiled=false) ?target () =
  if compiled then begin
    match Cmd_build.build ~release:false ~dump_phases ?target () with
    | Error msg -> Error msg
    | Ok output ->
      let cmd = match target with
        | Some ("js" | "javascript") -> "node " ^ Filename.quote output
        | _ -> Filename.quote output
      in
      let rc = Sys.command cmd in
      if rc = 0 then Ok ()
      else Error (Printf.sprintf "program exited with code %d" rc)
  end else
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    begin
      let lib_dir    = Filename.concat proj.Project.root "lib" in
      (* Entry point: use forge.toml [package] entrypoint if set, else lib/<name>.march *)
      let entry = match proj.Project.entrypoint with
        | Some ep -> Filename.concat proj.Project.root ep
        | None    -> Filename.concat lib_dir (proj.Project.name ^ ".march")
      in
      if not (Sys.file_exists entry) then
        Error (Printf.sprintf "entry point not found: %s" entry)
      else
      (* Auto-install the resolved toolchain (project .march-version pin, else
         global) if it isn't present, then route `march` to it via a PATH prefix. *)
      match Toolchain.ensure_installed () with
      | Error e -> Error e
      | Ok () ->
        (* Reuse the shared MARCH_LIB_PATH builder so a dependency's lib
           subfolders (e.g. lib/api, lib/wire) are resolved exactly as for
           check/build: Cmd_build.lib_path_env expands every lib root — the
           project's AND its deps' — into all descendant directories, and
           prepends the resolved toolchain to PATH. *)
        let lib_path_env = Cmd_build.lib_path_env proj in
        let dump_flag = if dump_phases then " --dump-phases" else "" in
        (* Link the same FFI shims as `forge build` and interpreted
           `forge test` (see Cmd_test.invoke_march_interp).  Without these,
           the compiler never receives --ffi-c, so setup_interpreter_ffi
           builds no shim .so and every extern call into it dies with
           "symbol not found for interpreter FFI" — making an app with
           [ffi] sources impossible to run interpreted at all. *)
        match Cmd_build.ffi_flags_full proj with
        | Error msg -> Error msg
        | Ok ffi_flags ->
        let cmd = interp_command ~lib_path_env ~dump_flag ~ffi_flags ~entry in
        let rc = Sys.command cmd in
        if rc = 0 then Ok ()
        else Error (Printf.sprintf "program exited with code %d" rc)
    end
