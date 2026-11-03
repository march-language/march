(** forge query: [march query] for the project.

    {v
    forge query fn NAME [FILE]         a function's body at the last pass that changed it
    forge query origin NAME [FILE]     where an emitted function came from
    forge query callers|callees NAME [FILE]
    forge query repr TYPE [FILE]
    forge query verify [FILE]          the TIR verifier over every stage
    forge query key [FILE]             both cache keys and every input that fed them
    forge query why-miss [FILE]        which key input changed since the last build
    v}

    Every query takes [--json] and [--at PASS] (for [fn]), and [--release] and
    [--target T] to ask about the build [forge build] would run with them.
    Arguments after [--] go to the compiler as they are.

    forge does not parse the query grammar: it passes the query's own
    arguments to [march query] unchanged, so the compiler stays the one place
    that defines it.  What forge adds is what [forge build] adds: the entry
    file (when no [.march] file is named), the project's [MARCH_LIB_PATH], the
    resolved toolchain, and the build's compiler flags ({!Cmd_build.compile_flags}:
    optimisation level, [--target], [--pin-main], hot reload, [[ffi]] sources
    and links, the topology digest, protocol baselines).  The cache queries
    ([key], [why-miss]) therefore describe the same build as [forge build].

    A query changes nothing: no [[ffi.rust]] crate is built (its archive is
    linked only if a previous [forge build] left it), no preprocessor runs, no
    protocol baseline is written, and no toolchain is downloaded. *)

(** Flags the query owns, whose duplicates the compiler would resolve in the
    wrong order (forge's come last): refuse them and name the forge spelling. *)
let check_args (args : string list) : (unit, string) result =
  let is_flag name a = a = name || String.starts_with ~prefix:(name ^ "=") a in
  let clash name hint =
    if List.exists (is_flag name) args then
      Some (Printf.sprintf "forge query: %s is set by %s" name hint)
    else None in
  match clash "--opt" "--release (forge's build default is --opt 0)",
        clash "--target" "forge query --target T" with
  | Some m, _ | None, Some m -> Error m
  | None, None -> Ok ()

let names_a_file args = List.exists (fun a -> Filename.check_suffix a ".march") args

(** The shell command. [flags] is the build's flag string (leading space);
    [entry] is appended only when the query names no [.march] file itself. *)
let command ~lib_path_env ~flags ~(entry : string option) ~(at : string option)
    ~json (args : string list) : string =
  let q = String.concat " " (List.map Filename.quote args) in
  let entry = match entry with
    | Some e when not (names_a_file args) -> " " ^ Filename.quote e
    | _ -> "" in
  let at = match at with Some p -> " --at " ^ Filename.quote p | None -> "" in
  Printf.sprintf "%smarch query %s%s%s%s%s"
    lib_path_env q entry flags at (if json then " --json" else "")

(** The topology digest a previous build wrote, when there is one. *)
let topology_flags ~root =
  let d = Topology.digest_file ~root in
  if Topology.exists ~root && Sys.file_exists d
  then " --topology " ^ Filename.quote d else ""

let run ?(release = false) ?target ?at ?(json = false) (args : string list)
  : (unit, string) result =
  match check_args args with
  | Error _ as e -> e
  | Ok () ->
  let target = Option.map Cmd_build.normalise_target target in
  let plain () =
    (* Not in a project: the named file is compiled on its own. *)
    let flags =
      Cmd_build.compile_flags ~ffi_flags:"" ~release ~dump_phases:false ?target
        ~pin_main:false () in
    Ok (command ~lib_path_env:"" ~flags ~entry:None ~at ~json args) in
  let cmd =
    match Project.load () with
    | Error e -> if names_a_file args then plain () else Error e
    | Ok proj ->
      let root = proj.Project.root in
      let entry =
        if names_a_file args then Ok None
        else match proj.Project.project_type with
          | Project.Lib ->
            Error "this is a library: it has no entry file; name a .march file to query"
          | Project.App | Project.Tool ->
            Result.map Option.some (Project.entry proj)
      in
      match entry with
      | Error _ as e -> e
      | Ok entry ->
      match Cmd_build.deps_preflight
              ~scope:(Cmd_build.build_scope ~release proj) proj with
      | Error _ as e -> e
      | Ok () ->
      let files = Cmd_build.find_march_files (Filename.concat root "lib") in
      let sources = match entry with Some e -> e :: files | None -> files in
      let hcr =
        match proj.Project.project_type, proj.Project.hot_reload with
        | (Project.App | Project.Tool), Some hr ->
          (match hr.hr_module_prefix, hr.hr_public_key with
           | Some prefix, Some public_key -> Some { Cmd_build.prefix; public_key }
           | _ -> None)
        | _ -> None in
      let ffi_flags =
        Cmd_build.ffi_flags_of ~root proj
        ^ topology_flags ~root
        ^ Cmd_build.protocol_flags ~emit:false ~root sources in
      let flags =
        Cmd_build.compile_flags ~ffi_flags ~release ~dump_phases:false ?target ?hcr
          ~pin_main:proj.Project.pin_main () in
      Ok (command ~lib_path_env:(Cmd_build.lib_path_env ~release proj) ~flags ~entry
            ~at ~json args)
  in
  match cmd with
  | Error _ as e -> Result.map (fun _ -> ()) e
  | Ok c ->
    (* The compiler's own exit code is the answer: [verify] exits 1 on a finding. *)
    let rc = Sys.command c in
    if rc = 0 then Ok () else exit rc
