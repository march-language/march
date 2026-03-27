(** Project model: load and represent forge.toml *)

type project_type = App | Lib | Tool

(** A project dependency.  Every dep form that can appear in [deps] or [dev-deps]. *)
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

type project = {
  name         : string;
  version      : string;
  project_type : project_type;
  description  : string;
  author       : string;
  root         : string;
  deps         : (string * dep) list;
  dev_deps     : (string * dep) list;
  patches      : patch list;
}

let project_type_of_string = function
  | "app"  -> App
  | "lib"  -> Lib
  | "tool" -> Tool
  | s      -> failwith (Printf.sprintf "unknown project type '%s'" s)

let project_type_to_string = function
  | App  -> "app"
  | Lib  -> "lib"
  | Tool -> "tool"

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
      | Toml.Str _ -> None
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
  (* [deps] inline + section forms *)
  let inline_deps   = parse_deps_section (Toml.get_section doc "deps") in
  let section_deps  = parse_section_deps "deps" doc in
  let deps = inline_deps @ section_deps in
  (* [dev-deps] inline + section forms *)
  let inline_devdeps  = parse_deps_section (Toml.get_section doc "dev-deps") in
  let section_devdeps = parse_section_deps "dev-deps" doc in
  let dev_deps = inline_devdeps @ section_devdeps in
  (* [patch.NAME] sections *)
  let patches = parse_patches doc in
  { name; version; project_type = project_type_of_string type_str;
    description; author; root; deps; dev_deps; patches }

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

(** Create a directory and all its parents. *)
let mkdir_p dir =
  let _ = Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dir)) in
  ()
