(** Project model: load and represent forge.toml *)

type project_type = App | Lib | Tool

(** A project dependency.  Every dep form that can appear in any dep section. *)
type dep =
  | RegistryDep  of { version : string }
    (** { registry = "forge", version = "~> 1.0" }
        version is the raw constraint string, validated separately by Resolver_constraint. *)
  | GitTagDep    of { url : string; tag : string }
    (** { git = "...", tag = "v0.2.1" }
        Tag is parsed as semver by the resolver and participates in solving. *)
  | GitBranchDep of { url : string; branch : string }
    (** { git = "...", branch = "main" }
        Floating: locked to HEAD commit; bypasses solver. *)
  | GitRevDep    of { url : string; rev : string }
    (** { git = "...", rev = "abc123" }
        Exact pin: never moves; bypasses solver. *)
  | PathDep      of string
    (** { path = "../vault" }
        Local development dep; bypasses solver; not allowed in published packages. *)

(** A [patch] override: substitute a fork for a package before the solver runs. *)
type patch = {
  patch_name   : string;
  patch_source : dep;  (** always GitBranchDep, GitRevDep, GitTagDep, or PathDep *)
}

(** A task declared in [archive.task.NAME]. *)
type archive_task = {
  task_command : string;  (** e.g. "bastion.new" *)
  task_module  : string;  (** relative path, e.g. "forge/cmd_new.march" *)
}

(** A Rust staticlib crate auto-built by `forge build`.
    Declared under `[ffi.rust]` in forge.toml:
      [ffi.rust]
      crate = "native/my_binding"   # path to the Cargo project (relative to forge.toml)
      lib   = "my_binding"          # optional: [lib] name (default = basename of crate path)
    The built archive is <crate>/target/release/lib<lib>.a. *)
type ffi_rust_crate = {
  frc_path : string;  (** relative path to the Cargo project directory *)
  frc_lib  : string;  (** archive base name (without "lib" prefix and ".a" suffix) *)
}

(** A single server in a named hot-reload environment ([[hot-reload.env]]). *)
type hot_reload_env = {
  hre_name       : string;
  hre_ssh_host   : string;
  hre_socket     : string;
  hre_public_key : string option;
}

type hot_reload_config = {
  hr_socket           : string;             (** Unix socket path on the server *)
  hr_ssh_host         : string;             (** SSH target for tunnel, e.g. "root@1.2.3.4" *)
  hr_public_key       : string option;      (** base64-encoded ed25519 public key *)
  hr_envs             : hot_reload_env list; (** multi-server environments ([[hot-reload.env]]) *)
  hr_health_check_url : string option;      (** Phase 10: HTTP URL polled after each rolling step *)
  hr_strategy         : string;             (** "rolling" (default) | "simultaneous" *)
}

type project = {
  name          : string;
  version       : string;
  project_type  : project_type;
  description   : string;
  author        : string;
  root          : string;
  entrypoint    : string option;
  march_req     : string option;  (** optional `march = "~> X.Y"` toolchain constraint *)
  license       : string option;  (** SPDX license id, e.g. "MIT" *)
  repository    : string option;  (** source repository URL *)
  homepage      : string option;  (** project homepage URL *)
  deps          : (string * dep) list;
  dev_deps      : (string * dep) list;  (** dev + test — don't ship *)
  dev_only_deps : (string * dep) list;  (** dev only — not available in test *)
  test_deps     : (string * dep) list;  (** test only — not available in dev *)
  patches       : patch list;
  archive_tasks : archive_task list;
  archive_deps  : (string * dep) list;
  preprocessors : (string * string) list;
  ffi_sources   : string list;  (** [ffi] sources = [...]: C shim files to compile+link (relative to root) *)
  ffi_link      : string list;  (** [ffi] link = [...]: extra linker flags, e.g. "-lz" *)
  ffi_rust      : ffi_rust_crate option;  (** [ffi.rust]: Rust staticlib crate auto-built by forge build *)
  js_deps       : (string * string) list;  (** [js_deps] name = "version": npm packages for JS target builds *)
  hot_reload    : hot_reload_config option;  (** [hot-reload] section (Phase 4) *)
  contracts_no_alloc : string list;
  (** [contracts] no_alloc = ["Dsp.*", "Audio.mix"]: module/function globs that
      `forge fix --contracts` treats as in scope even without in-place reuse.
      See lib/tir/alloc_contract.ml's generation scope. *)
}

let project_type_of_string = function
  | "app"      -> App
  | "lib"      -> Lib
  | "tool"     -> Tool
  | s          -> failwith (Printf.sprintf "unknown project type '%s'" s)

let project_type_to_string = function
  | App     -> "app"
  | Lib     -> "lib"
  | Tool    -> "tool"

let read_file path =
  let ic = open_in path in
  let n = in_channel_length ic in
  let buf = Bytes.create n in
  really_input ic buf 0 n;
  close_in ic;
  Bytes.to_string buf

(** Search current directory and parents for forge.toml. *)
let find_forge_toml () =
  let rec search dir =
    let candidate = Filename.concat dir "forge.toml" in
    if Sys.file_exists candidate then Some dir
    else
      let parent = Filename.dirname dir in
      if parent = dir then None
      else search parent
  in
  search (Sys.getcwd ())

(** Parse a single dep inline-table into a [dep] value.

    Precedence for git deps:
      - `tag` key → GitTagDep
      - `branch` key → GitBranchDep
      - `rev` key → GitRevDep
      - no qualifier → GitBranchDep with branch="main" (backward-compat) *)
let parse_dep_table tbl =
  let git_url  = Toml.get_string tbl "git" in
  let path     = Toml.get_string tbl "path" in
  let registry = Toml.get_string tbl "registry" in
  let version  = Toml.get_string tbl "version" in
  let tag      = Toml.get_string tbl "tag" in
  let branch   = Toml.get_string tbl "branch" in
  let rev      = Toml.get_string tbl "rev" in
  match registry, git_url, path with
  | Some _, _, _ ->
    let ver = Option.value ~default:"*" version in
    Some (RegistryDep { version = ver })
  | None, None, None when version <> None ->
    (* Table with a `version` key but no `git`/`path`/`registry` qualifier:
       treat as a registry dep (the registry is implicit — one registry per
       forge install, configured via FORGE_REGISTRY / default forgepm.org). *)
    Some (RegistryDep { version = Option.get version })
  | None, Some url, _ ->
    (match tag, branch, rev with
     | Some t, _, _ -> Some (GitTagDep    { url; tag = t })
     | _, Some b, _ -> Some (GitBranchDep { url; branch = b })
     | _, _, Some r -> Some (GitRevDep    { url; rev = r })
     | None, None, None ->
       (* No qualifier: treat as branch dep on "main" for backward compatibility *)
       Some (GitBranchDep { url; branch = "main" }))
  | None, None, Some p ->
    Some (PathDep p)
  | None, None, None ->
    None

(** Parse deps from a [deps] or [dev-deps] section. *)
let parse_deps_section dep_pairs =
  List.filter_map (fun (dep_name, v) ->
      match v with
      | Toml.InlineTable tbl ->
        (match parse_dep_table tbl with
         | Some dep -> Some (dep_name, dep)
         | None     -> None)
      | Toml.Str version ->
        (* Bare-string shorthand `name = "0.2.1"` is a registry dep with that
           version constraint — the most common declaration form. *)
        Some (dep_name, RegistryDep { version })
      | Toml.Array _ -> None
    ) dep_pairs

(** Parse deps from dot-sections like [deps.depot] and [dev-deps.name]. *)
let parse_section_deps prefix doc =
  let plen = String.length prefix in
  List.filter_map (fun (sec_name, pairs) ->
      if String.length sec_name > plen + 1 &&
         String.sub sec_name 0 (plen + 1) = (prefix ^ ".")
      then begin
        let dep_name = String.sub sec_name (plen + 1)
            (String.length sec_name - plen - 1) in
        match parse_dep_table pairs with
        | Some dep -> Some (dep_name, dep)
        | None     -> None
      end else None
    ) doc.Toml.sections

(** Parse [archive.task.NAME] sections into archive_task list. *)
let parse_archive_tasks doc =
  let prefix = "archive.task." in
  let plen = String.length prefix in
  List.filter_map (fun (sec_name, pairs) ->
      if String.length sec_name > plen &&
         String.sub sec_name 0 plen = prefix
      then begin
        let command = Toml.get_string pairs "command" in
        let module_ = Toml.get_string pairs "module" in
        match command, module_ with
        | Some task_command, Some task_module ->
          Some { task_command; task_module }
        | _ -> None
      end else None
    ) doc.Toml.sections

(** Parse [patch.NAME] sections. *)
let parse_patches doc =
  List.filter_map (fun (sec_name, pairs) ->
      let prefix = "patch." in
      let plen = String.length prefix in
      if String.length sec_name > plen &&
         String.sub sec_name 0 plen = prefix
      then begin
        let pkg_name = String.sub sec_name plen (String.length sec_name - plen) in
        match parse_dep_table pairs with
        | Some source -> Some { patch_name = pkg_name; patch_source = source }
        | None        -> None
      end else None
    ) doc.Toml.sections

let load_from root =
  let path = Filename.concat root "forge.toml" in
  let text = read_file path in
  let doc  = Toml.parse text in
  (* Support both [package] and [project] section names *)
  let pkg =
    let p = Toml.get_section doc "package" in
    if p <> [] then p else Toml.get_section doc "project"
  in
  let name        = Option.value ~default:"unknown" (Toml.get_string pkg "name") in
  let version     = Option.value ~default:"0.1.0"  (Toml.get_string pkg "version") in
  let type_str    = Option.value ~default:"app"    (Toml.get_string pkg "type") in
  let description = Option.value ~default:""       (Toml.get_string pkg "description") in
  let author      = Option.value ~default:""       (Toml.get_string pkg "author") in
  let entrypoint  = Toml.get_string pkg "entrypoint" in
  let march_req   = Toml.get_string pkg "march" in
  let license     = Toml.get_string pkg "license" in
  let repository  = Toml.get_string pkg "repository" in
  let homepage    = Toml.get_string pkg "homepage" in
  (* [deps] inline + section forms *)
  let inline_deps   = parse_deps_section (Toml.get_section doc "deps") in
  let section_deps  = parse_section_deps "deps" doc in
  let deps = inline_deps @ section_deps in
  (* [dev-deps] inline + section forms — available in dev + test, don't ship *)
  let inline_devdeps  = parse_deps_section (Toml.get_section doc "dev-deps") in
  let section_devdeps = parse_section_deps "dev-deps" doc in
  let dev_deps = inline_devdeps @ section_devdeps in
  (* [dev-only-deps] inline + section forms — dev only, not available in test *)
  let inline_devonly  = parse_deps_section (Toml.get_section doc "dev-only-deps") in
  let section_devonly = parse_section_deps "dev-only-deps" doc in
  let dev_only_deps = inline_devonly @ section_devonly in
  (* [test-deps] inline + section forms — test only, not available in dev *)
  let inline_testdeps  = parse_deps_section (Toml.get_section doc "test-deps") in
  let section_testdeps = parse_section_deps "test-deps" doc in
  let test_deps = inline_testdeps @ section_testdeps in
  (* [patch.NAME] sections *)
  let patches = parse_patches doc in
  (* [archive.task.NAME] sections *)
  let archive_tasks = parse_archive_tasks doc in
  (* [archive-deps] inline + section forms *)
  let inline_archdeps  = parse_deps_section (Toml.get_section doc "archive-deps") in
  let section_archdeps = parse_section_deps "archive-deps" doc in
  let archive_deps = inline_archdeps @ section_archdeps in
  (* [preprocessors] section: extension → command mappings *)
  let preprocessors =
    List.filter_map (fun (k, v) ->
      match v with
      | Toml.Str cmd -> Some (k, cmd)
      | _ -> None
    ) (Toml.get_section doc "preprocessors")
  in
  (* [ffi] section: C shim sources + extra linker flags for FFI bindings *)
  let ffi_section = Toml.get_section doc "ffi" in
  let ffi_sources = Toml.get_string_list ffi_section "sources" in
  let ffi_link    = Toml.get_string_list ffi_section "link" in
  (* [ffi.rust] section: Rust staticlib crate auto-built by forge build.
     The archive is at <crate>/target/release/lib<lib>.a.
     `lib` defaults to the basename of the crate path if omitted. *)
  let ffi_rust =
    let rust_sec = Toml.get_section doc "ffi.rust" in
    (match Toml.get_string rust_sec "crate" with
     | None -> None
     | Some crate_path ->
       let lib_name = Option.value ~default:(Filename.basename crate_path)
           (Toml.get_string rust_sec "lib") in
       Some { frc_path = crate_path; frc_lib = lib_name })
  in
  (* [js_deps] section: npm package dependencies for --target js builds *)
  let js_deps =
    List.filter_map (fun (k, v) ->
      match v with
      | Toml.Str ver -> Some (k, ver)
      | _ -> None
    ) (Toml.get_section doc "js_deps")
  in
  (* [hot-reload] section: forge deploy hot configuration (Phase 4/7) *)
  let hot_reload =
    let hr = Toml.get_section doc "hot-reload" in
    (* [[hot-reload.env]] entries: multi-server environments (Phase 7) *)
    let hr_envs =
      List.filter_map (fun env_pairs ->
        let ssh_host = Option.value ~default:"" (Toml.get_string env_pairs "ssh_host") in
        if ssh_host = "" then None
        else begin
          let name       = Option.value ~default:"" (Toml.get_string env_pairs "name") in
          let socket     = Option.value ~default:"/tmp/march_hcr.sock"
                             (Toml.get_string env_pairs "socket") in
          let public_key = Toml.get_string env_pairs "public_key" in
          Some { hre_name = name; hre_ssh_host = ssh_host;
                 hre_socket = socket; hre_public_key = public_key }
        end
      ) (Toml.get_all_sections doc "hot-reload.env")
    in
    if hr = [] && hr_envs = [] then None
    else begin
      let socket           = Option.value ~default:"/tmp/march_hcr.sock" (Toml.get_string hr "socket") in
      let ssh_host         = Option.value ~default:""                    (Toml.get_string hr "ssh_host") in
      let public_key       = Toml.get_string hr "public_key" in
      let hr_health_check_url = Toml.get_string hr "health_check_url" in
      let hr_strategy      = Option.value ~default:"rolling"             (Toml.get_string hr "strategy") in
      Some { hr_socket = socket; hr_ssh_host = ssh_host;
             hr_public_key = public_key; hr_envs;
             hr_health_check_url; hr_strategy }
    end
  in
  let contracts_no_alloc =
    Toml.get_string_list (Toml.get_section doc "contracts") "no_alloc" in
  { name; version; project_type = project_type_of_string type_str;
    description; author; root; entrypoint; march_req; license; repository; homepage;
    deps; dev_deps; dev_only_deps; test_deps; patches; archive_tasks; archive_deps;
    preprocessors; ffi_sources; ffi_link; ffi_rust; js_deps; hot_reload;
    contracts_no_alloc }

let load_from_dir dir =
  try Ok (load_from dir)
  with
  | Sys_error msg -> Error msg
  | Failure msg   -> Error msg
  | Toml.Parse_error msg -> Error ("forge.toml parse error: " ^ msg)

let load () =
  match find_forge_toml () with
  | None -> Error "no forge.toml found in current directory or any parent"
  | Some root ->
    (try Ok (load_from root)
     with
     | Sys_error msg -> Error msg
     | Failure msg   -> Error msg
     | Toml.Parse_error msg -> Error ("forge.toml parse error: " ^ msg))

(** Return the lib directory for a git dependency installed in the CAS, or
    [None] if [forge deps] has not been run yet for this dep. *)
let git_dep_lib_path dep_name =
  match Sys.getenv_opt "HOME" with
  | None -> None
  | Some home ->
    let dep_dir =
      Filename.concat home
        (Filename.concat ".march"
           (Filename.concat "cas" (Filename.concat "deps" dep_name)))
    in
    let lib_dir = Filename.concat dep_dir "lib" in
    if Sys.file_exists lib_dir then Some lib_dir
    else if Sys.file_exists dep_dir then Some dep_dir
    else None

(** Resolve the root directory of an already-installed dependency (a path
    dep, or a git dep's clone under the CAS), so its own forge.toml can be
    read to walk transitive dependencies.  [project_root] is the root of the
    project that DECLARED [dep] (needed to resolve a relative PathDep).
    Registry and git deps both live under [~/.march/cas/deps/<name>]. *)
let dep_root_dir ~project_root (dep_name, dep) =
  match dep with
  | PathDep rel_path ->
    Some (if Filename.is_relative rel_path
          then Filename.concat project_root rel_path
          else rel_path)
  | GitTagDep _ | GitBranchDep _ | GitRevDep _ | RegistryDep _ ->
    (match Sys.getenv_opt "HOME" with
     | None -> None
     | Some home ->
       Some (Filename.concat home
               (Filename.concat ".march" (Filename.concat "cas" (Filename.concat "deps" dep_name)))))

(** Create a directory and all its parents. *)
let mkdir_p dir =
  let _ = Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dir)) in
  ()
