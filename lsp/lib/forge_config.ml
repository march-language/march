(** forge.toml reader for the LSP.
    Locates a forge.toml by walking up from the file being edited, parses its
    [deps] section, and resolves each dependency to an absolute lib/ directory
    — mirroring exactly what [forge build] does via MARCH_LIB_PATH.

    This module is intentionally self-contained: it duplicates the minimal TOML
    parser from [forge/lib/toml.ml] rather than depending on march_forge, which
    would pull in yojson and other unneeded transitive deps. *)

(* ------------------------------------------------------------------ *)
(* Minimal TOML parser (subset sufficient for forge.toml)             *)
(* ------------------------------------------------------------------ *)

type value =
  | Str of string
  | InlineTable of (string * value) list

exception Parse_error of string

let fail msg = raise (Parse_error msg)

let skip_ws s i =
  let n = String.length s in
  let i = ref i in
  while !i < n && (s.[!i] = ' ' || s.[!i] = '\t') do incr i done;
  !i

let parse_quoted_string s i =
  let n = String.length s in
  if i >= n || s.[i] <> '"' then fail "expected '\"'";
  let buf = Buffer.create 16 in
  let pos = ref (i + 1) in
  while !pos < n && s.[!pos] <> '"' do
    (match s.[!pos] with
     | '\\' ->
       incr pos;
       if !pos >= n then fail "unterminated escape sequence";
       (match s.[!pos] with
        | '"'  -> Buffer.add_char buf '"'
        | '\\' -> Buffer.add_char buf '\\'
        | 'n'  -> Buffer.add_char buf '\n'
        | 't'  -> Buffer.add_char buf '\t'
        | 'r'  -> Buffer.add_char buf '\r'
        | c    -> Buffer.add_char buf '\\'; Buffer.add_char buf c);
       incr pos
     | c ->
       Buffer.add_char buf c;
       incr pos)
  done;
  if !pos >= n then fail "unterminated string";
  (Buffer.contents buf, !pos + 1)

let parse_bare_key s i =
  let n = String.length s in
  let start = i in
  let i = ref i in
  while !i < n &&
        (let c = s.[!i] in
         (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
         (c >= '0' && c <= '9') || c = '-' || c = '_') do
    incr i
  done;
  if !i = start then
    fail (Printf.sprintf "expected bare key at position %d" start);
  (String.sub s start (!i - start), !i)

let parse_key s i =
  let i = skip_ws s i in
  let n = String.length s in
  if i >= n then fail "expected key, got end of input";
  if s.[i] = '"' then parse_quoted_string s i
  else parse_bare_key s i

let rec parse_value s i =
  let i = skip_ws s i in
  let n = String.length s in
  if i >= n then fail "expected value, got end of input";
  match s.[i] with
  | '"' ->
    let (v, i') = parse_quoted_string s i in
    (Str v, i')
  | '{' ->
    let (tbl, i') = parse_inline_table s (i + 1) in
    (InlineTable tbl, i')
  | _ ->
    let start = i in
    let i = ref i in
    while !i < n && s.[!i] <> ',' && s.[!i] <> '}' && s.[!i] <> '#' do
      incr i
    done;
    let v = String.trim (String.sub s start (!i - start)) in
    (Str v, !i)

and parse_inline_table s i =
  let n = String.length s in
  let i = ref (skip_ws s i) in
  let pairs = ref [] in
  if !i < n && s.[!i] = '}' then ([], !i + 1)
  else begin
    let stop = ref false in
    while not !stop do
      let (k, i2) = parse_key s !i in
      let i3 = skip_ws s i2 in
      if i3 >= n || s.[i3] <> '=' then
        fail (Printf.sprintf "expected '=' after key '%s'" k);
      let i4 = skip_ws s (i3 + 1) in
      let (v, i5) = parse_value s i4 in
      pairs := (k, v) :: !pairs;
      i := skip_ws s i5;
      if !i >= n then fail "unterminated inline table";
      (match s.[!i] with
       | '}' -> stop := true; incr i
       | ',' -> incr i
       | c   -> fail (Printf.sprintf "expected ',' or '}', got '%c'" c))
    done;
    (List.rev !pairs, !i)
  end

type document = {
  sections : (string * (string * value) list) list;
}

let parse_document text =
  let lines = String.split_on_char '\n' text in
  let sections : (string * (string * value) list) list ref = ref [] in
  let cur_section = ref "" in
  let cur_pairs : (string * value) list ref = ref [] in
  let finish () =
    sections := (!cur_section, List.rev !cur_pairs) :: !sections;
    cur_pairs := []
  in
  List.iter (fun raw ->
    let line = String.trim raw in
    if line = "" || (String.length line > 0 && line.[0] = '#') then
      ()
    else if String.length line >= 3 && line.[0] = '[' then begin
      (match String.index_opt line ']' with
       | None -> ()
       | Some close ->
         finish ();
         let name = String.trim (String.sub line 1 (close - 1)) in
         cur_section := name)
    end else begin
      match String.index_opt line '=' with
      | None -> ()
      | Some eq ->
        let key = String.trim (String.sub line 0 eq) in
        let rest = String.trim (String.sub line (eq + 1) (String.length line - eq - 1)) in
        (try
           let (v, _) = parse_value rest 0 in
           cur_pairs := (key, v) :: !cur_pairs
         with Parse_error _ -> ())
    end
  ) lines;
  finish ();
  { sections = List.rev !sections }

let get_section doc name =
  match List.assoc_opt name doc.sections with
  | None -> []
  | Some pairs -> pairs

let get_string pairs key =
  match List.assoc_opt key pairs with
  | Some (Str s) -> Some s
  | _ -> None

(* ------------------------------------------------------------------ *)
(* Forge project root discovery                                        *)
(* ------------------------------------------------------------------ *)

let read_file path =
  try
    let ic = open_in path in
    let n = in_channel_length ic in
    let buf = Bytes.create n in
    really_input ic buf 0 n;
    close_in ic;
    Some (Bytes.to_string buf)
  with Sys_error _ -> None

(** Walk up from [start_dir] looking for a directory that contains
    [forge.toml].  Returns the directory path (the project root), or [None]
    if none is found before reaching the filesystem root. *)
let find_forge_root start_dir =
  let rec search d =
    let candidate = Filename.concat d "forge.toml" in
    if Sys.file_exists candidate then Some d
    else
      let parent = Filename.dirname d in
      if parent = d then None
      else search parent
  in
  search start_dir

(* ------------------------------------------------------------------ *)
(* Dep resolution — mirrors cmd_build.ml's MARCH_LIB_PATH logic       *)
(* ------------------------------------------------------------------ *)

(** Return the CAS directory where [forge deps] clones git dependencies:
    [~/.march/cas/deps]. *)
let cas_deps_dir () =
  match Sys.getenv_opt "HOME" with
  | None -> None
  | Some home ->
    Some (Filename.concat home
            (Filename.concat ".march" (Filename.concat "cas" "deps")))

(** Given a [forge.toml] project root, return the list of absolute
    library directories contributed by each declared dependency.

    Resolution rules (same as [forge build]):
    - PathDep [path]: [<root>/<path>/lib] if it exists, else [<root>/<path>]
    - GitDep [name]:  [~/.march/cas/deps/<name>/lib] if present

    Directories that don't exist on disk are silently omitted — the
    type-checker will just not find those modules, which is no worse than
    the current behaviour. *)
let dep_lib_paths root =
  let toml_path = Filename.concat root "forge.toml" in
  match read_file toml_path with
  | None -> []
  | Some text ->
    let doc =
      try parse_document text
      with Parse_error _ -> { sections = [] }
    in
    (* Helper: resolve a path string relative to the project root *)
    let resolve_path p =
      if Filename.is_relative p
      then Filename.concat root p
      else p
    in
    (* Helper: pick lib/ subdir if it exists, else the root itself *)
    let best_lib_dir abs_path =
      let lib = Filename.concat abs_path "lib" in
      if Sys.file_exists lib then Some lib
      else if Sys.file_exists abs_path then Some abs_path
      else None
    in
    (* Helper: resolve a git dep by name via the CAS *)
    let git_dep_path dep_name =
      match cas_deps_dir () with
      | None -> None
      | Some cas ->
        let dep_dir = Filename.concat cas dep_name in
        best_lib_dir dep_dir
    in
    (* 1. Inline deps: [deps] section with dep = {path = "..."} or dep = {git = "..."} *)
    let dep_section = get_section doc "deps" in
    let inline_paths = List.filter_map (fun (dep_name, v) ->
        match v with
        | InlineTable tbl ->
          (match get_string tbl "path" with
           | Some p -> best_lib_dir (resolve_path p)
           | None ->
             (match get_string tbl "git" with
              | Some _ -> git_dep_path dep_name
              | None   -> None))
        | Str _ -> None
      ) dep_section
    in
    (* 2. Section deps: [deps.foo] path = "..." or git = "..." *)
    let prefix = "deps." in
    let plen = String.length prefix in
    let section_paths = List.filter_map (fun (sec_name, pairs) ->
        if String.length sec_name > plen &&
           String.sub sec_name 0 plen = prefix
        then
          let dep_name = String.sub sec_name plen (String.length sec_name - plen) in
          (match get_string pairs "path" with
           | Some p -> best_lib_dir (resolve_path p)
           | None ->
             (match get_string pairs "git" with
              | Some _ -> git_dep_path dep_name
              | None   -> None))
        else None
      ) doc.sections
    in
    (* Deduplicate while preserving order *)
    let seen = Hashtbl.create 8 in
    List.filter (fun d ->
        if Hashtbl.mem seen d then false
        else (Hashtbl.add seen d (); true)
      ) (inline_paths @ section_paths)

(** All lib paths for a project root: dependency paths PLUS the project's own
    [lib/], [.forge/generated/], and [config/] — mirroring [lib_path_env] in
    [forge/lib/cmd_build.ml]. *)
let project_lib_paths root =
  let dep_paths = dep_lib_paths root in
  let lib_dir   = Filename.concat root "lib" in
  let gen_dir   = Filename.concat root ".forge/generated" in
  let cfg_dir   = Filename.concat root "config" in
  let extras =
    List.filter_map (fun d -> if Sys.file_exists d then Some d else None)
      [lib_dir; gen_dir; cfg_dir]
  in
  let seen = Hashtbl.create 8 in
  List.filter (fun d ->
      if Hashtbl.mem seen d then false
      else (Hashtbl.add seen d (); true)
    ) (dep_paths @ extras)
