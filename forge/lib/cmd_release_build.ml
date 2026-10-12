(** forge release build [--target T] [--profile P] [--tar]

    R9 of specs/plans/2026-09-28-observe-recon-shell-plan.md (design section
    7.2).  Builds the project and lays out a self-contained release directory
    [.march/release/<app>-<version>-<target>/]:

    {v
    bin/<app>                 the launcher (Release_launcher: POSIX sh)
    lib/<app>                 the binary (the HCR baseline when [hot-reload] is set)
    lib/<app>.hcr_manifest    from a --compile-so build of the same source (hot-reload only)
    lib/<app>.schemas.json    the same build's actor schemas (hot-reload, when it has any)
    lib/patches/              reserved for the host's patch stack
    etc/topology.json         the exported topology (when the project has one)
    etc/policy                MARCH_DEPLOY_POLICY
    etc/debug_policy          MARCH_DEBUG_POLICY
    etc/shell_policy          MARCH_SHELL_POLICY
    etc/pubkey                the [hot-reload] public key (when set)
    etc/env                   MARCH_* defaults the launcher applies
    RELEASE                   key=value: name, version, target, cas_hash, ...
    v}

    The policy files and extra [etc/env] lines come from [release/etc/] in the
    project when it has them; otherwise the policies are empty (nothing
    allowed). *)

let ( let* ) = Result.bind

let write_file path content =
  Project.mkdir_p (Filename.dirname path);
  Out_channel.with_open_bin path (fun oc -> output_string oc content)

let sh fmt = Printf.ksprintf Sys.command fmt

let capture cmd =
  match Unix.open_process_in cmd with
  | exception _ -> ""
  | ic ->
    let s = try In_channel.input_all ic with _ -> "" in
    ignore (Unix.close_process_in ic);
    String.trim s

(** The directory-name label of a build target: [linux-amd64],
    [darwin-arm64]; the host's own when no cross target is given. *)
let target_label (target : string option) : string =
  match Option.map Cmd_build.normalise_target target with
  | Some "linux/amd64" -> "linux-amd64"
  | Some "linux/arm64" -> "linux-arm64"
  | Some t -> String.map (fun c -> if c = '/' then '-' else c) t
  | None ->
    let os = String.lowercase_ascii (capture "uname -s") in
    let arch = match String.lowercase_ascii (capture "uname -m") with
      | "x86_64" -> "amd64" | "aarch64" -> "arm64" | a -> a in
    (if os = "" then "unknown" else os) ^ "-" ^ (if arch = "" then "unknown" else arch)

(** Seconds the launcher gives a SIGTERM before SIGKILL: the topology's soft
    drain deadline, else its hard one, else 30. *)
let stop_grace_secs (drain : Topology.drain option) : int =
  let secs ms = max 1 ((ms + 999) / 1000) in
  match drain with
  | Some { Topology.soft_ms = Some ms; _ } -> secs ms
  | Some { Topology.hard_ms = Some ms; _ } -> secs ms
  | _ -> 30

let iso8601_now () =
  let t = Unix.gmtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (t.Unix.tm_year + 1900) (t.Unix.tm_mon + 1) t.Unix.tm_mday
    t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec

let env_file ~grace ~extra =
  String.concat "\n" ([
      "# Defaults the launcher applies to names the environment does not set.";
      "# NAME=VALUE, one per line; no expansion except @ROOT@ (the release directory).";
      "MARCH_DEPLOY_POLICY=@ROOT@/etc/policy";
      "MARCH_DEBUG_POLICY=@ROOT@/etc/debug_policy";
      "MARCH_SHELL_POLICY=@ROOT@/etc/shell_policy";
      Printf.sprintf "MARCH_STOP_GRACE=%d" grace;
    ] @ (if extra = "" then [] else [ String.trim extra ]))
  ^ "\n"

let release_file ~(proj : Project.project) ~target ~profile ~cas_hash ~hot ~compiler =
  String.concat "\n" [
    "name=" ^ proj.Project.name;
    "version=" ^ proj.Project.version;
    "target=" ^ target;
    "profile=" ^ profile;
    "cas_hash=" ^ cas_hash;
    "hot_reload=" ^ (if hot then "true" else "false");
    "compiler=" ^ compiler;
    "built_at=" ^ iso8601_now ();
  ] ^ "\n"

(** The exported topology JSON, when the project has a topology.toml. *)
let topology_json ~(proj : Project.project) : (string option * Topology.drain option, string) result =
  let root = proj.Project.root in
  if not (Topology.exists ~root) then Ok (None, None)
  else
    match Topology.load ~root () with
    | Error ds ->
      Error ("topology check failed:\n" ^ String.concat "\n" (List.map Topology.render_diag ds))
    | Ok t ->
      let index = Topology.index_project ~root in
      let ds = Topology.check ~index t in
      if Topology.has_errors ds then
        Error ("topology check failed:\n" ^ String.concat "\n" (List.map Topology.render_diag ds))
      else
        let compiler = Result.to_option (Topology_run.compiler_derived proj) in
        Ok (Some (Yojson.Safe.pretty_to_string (Topology.export_json ?compiler ~index t)), t.Topology.drain)

let read_opt path = if Sys.file_exists path then Some (Project.read_file path) else None

(** [build ()] returns the release directory and, with [~tar], the tarball. *)
let build ?target ?(profile = "release") ?(tar = false) () : (string * string option, string) result =
  let* release =
    match profile with
    | "release" -> Ok true
    | "debug" -> Ok false
    | p -> Error (Printf.sprintf "release build: unknown profile %S (release or debug)" p)
  in
  let* proj = Project.load () in
  let app = proj.Project.name in
  let* () =
    if proj.Project.project_type = Project.Lib then
      Error "release build: a library has no binary to release (type = \"app\" or \"tool\")"
    else if not (Release_launcher.valid_app_name app) then
      Error (Printf.sprintf "release build: package name %S is not usable as a file name (letters, digits, - _ .)" app)
    else Ok ()
  in
  let target = Option.map Cmd_build.normalise_target target in
  let label = target_label target in
  let root = proj.Project.root in
  let* topo_json, drain = topology_json ~proj in
  let* binary = Cmd_build.build ~release ?target () in
  let hot =
    match proj.Project.hot_reload with
    | Some { Project.hr_module_prefix = Some _; hr_public_key = Some _; _ } -> true
    | _ -> false
  in
  (* The baseline's manifest and actor schemas come from a --compile-so build
     of the same source: the baseline binary itself does not write them. *)
  let* sidecars =
    if not hot then Ok None
    else begin
      let out = Filename.concat (Filename.concat (Filename.concat root ".march") "release-tmp")
          (app ^ "-" ^ label) in
      Project.mkdir_p (Filename.dirname out);
      let* so, manifest = Cmd_deploy_hot.build_so_for ~target ~proj ~output:out in
      let schemas = so ^ ".schemas.json" in
      let* m = Cmd_deploy_hot.parse_manifest manifest in
      Ok (Some (manifest, (if Sys.file_exists schemas then Some schemas else None), m.Cmd_deploy_hot.cas_hash))
    end
  in
  let name = Printf.sprintf "%s-%s-%s" app proj.Project.version label in
  let dir = Filename.concat (Filename.concat (Filename.concat root ".march") "release") name in
  if Filename.basename dir <> name then Error "release build: bad release directory name"
  else begin
    ignore (sh "rm -rf %s" (Filename.quote dir));
    let p rel = Filename.concat dir rel in
    List.iter (fun d -> Project.mkdir_p (p d)) [ "bin"; "lib/patches"; "etc" ];
    let copy ~mode src dst =
      if sh "cp %s %s && chmod %s %s" (Filename.quote src) (Filename.quote dst) mode (Filename.quote dst) <> 0
      then Error (Printf.sprintf "release build: cannot copy %s" src)
      else Ok ()
    in
    let* () = copy ~mode:"755" binary (p ("lib/" ^ app)) in
    let cas_hash =
      match sidecars with
      | Some (manifest, schemas, h) ->
        ignore (copy ~mode:"644" manifest (p ("lib/" ^ app ^ ".hcr_manifest")));
        Option.iter (fun s -> ignore (copy ~mode:"644" s (p ("lib/" ^ app ^ ".schemas.json")))) schemas;
        h
      | None -> "-"
    in
    write_file (p ("bin/" ^ app)) (Release_launcher.script ~app);
    Unix.chmod (p ("bin/" ^ app)) 0o755;
    let src_etc f = read_opt (Filename.concat (Filename.concat (Filename.concat root "release") "etc") f) in
    List.iter (fun f -> write_file (p ("etc/" ^ f)) (Option.value (src_etc f) ~default:""))
      [ "policy"; "debug_policy"; "shell_policy" ];
    Option.iter (write_file (p "etc/topology.json")) topo_json;
    (match proj.Project.hot_reload with
     | Some { Project.hr_public_key = Some k; _ } -> write_file (p "etc/pubkey") (k ^ "\n")
     | _ -> ());
    write_file (p "etc/env")
      (env_file ~grace:(stop_grace_secs drain) ~extra:(Option.value (src_etc "env") ~default:""));
    let compiler =
      match String.split_on_char '\n' (capture "march --version 2>/dev/null") with
      | l :: _ when l <> "" -> l
      | _ -> "unknown"
    in
    write_file (p "RELEASE")
      (release_file ~proj ~target:label ~profile ~cas_hash ~hot ~compiler);
    if not tar then Ok (dir, None)
    else begin
      let tarball = dir ^ ".tar.gz" in
      if sh "tar -C %s -czf %s %s" (Filename.quote (Filename.dirname dir))
          (Filename.quote tarball) (Filename.quote name) <> 0
      then Error "release build: tar failed"
      else Ok (dir, Some tarball)
    end
  end
