(** Project model: load and represent forge.toml *)

type project_type = App | Lib | Tool

type dep =
  | GitDep of { url : string; rev : string }
  | PathDep of string

type project = {
  name         : string;
  version      : string;
  project_type : project_type;
  description  : string;
  author       : string;
  root         : string;
  deps         : (string * dep) list;
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

let load_from root =
  let path = Filename.concat root "forge.toml" in
  let text = read_file path in
  let doc  = Toml.parse text in
  let pkg  = Toml.get_section doc "package" in
  let name        = Option.value ~default:"unknown" (Toml.get_string pkg "name") in
  let version     = Option.value ~default:"0.1.0"  (Toml.get_string pkg "version") in
  let type_str    = Option.value ~default:"app"    (Toml.get_string pkg "type") in
  let description = Option.value ~default:""       (Toml.get_string pkg "description") in
  let author      = Option.value ~default:""       (Toml.get_string pkg "author") in
  (* Parse deps declared as inline tables in [deps]: depot = {path="../depot"} *)
  let dep_pairs   = Toml.get_section doc "deps" in
  let inline_deps = List.filter_map (fun (dep_name, v) ->
      match v with
      | Toml.InlineTable tbl ->
        let git_url = Toml.get_string tbl "git" in
        let path    = Toml.get_string tbl "path" in
        (match git_url, path with
         | Some u, _ ->
           let rev = Option.value ~default:"main" (Toml.get_string tbl "rev") in
           Some (dep_name, GitDep { url = u; rev })
         | _, Some p ->
           Some (dep_name, PathDep p)
         | None, None -> None)
      | Toml.Str _ -> None
    ) dep_pairs
  in
  (* Also parse deps declared as sections: [deps.depot] path = "../depot" *)
  let section_deps = List.filter_map (fun (sec_name, pairs) ->
      let prefix = "deps." in
      let plen = String.length prefix in
      if String.length sec_name > plen &&
         String.sub sec_name 0 plen = prefix
      then begin
        let dep_name = String.sub sec_name plen (String.length sec_name - plen) in
        let git_url = Toml.get_string pairs "git" in
        let path    = Toml.get_string pairs "path" in
        match git_url, path with
        | Some u, _ ->
          let rev = Option.value ~default:"main" (Toml.get_string pairs "rev") in
          Some (dep_name, GitDep { url = u; rev })
        | _, Some p ->
          Some (dep_name, PathDep p)
        | None, None -> None
      end else None
    ) doc.Toml.sections
  in
  let deps = inline_deps @ section_deps in
  { name; version; project_type = project_type_of_string type_str;
    description; author; root; deps }

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
