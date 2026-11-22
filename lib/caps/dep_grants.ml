(* Dependency grants (ocap phase 6): the grants file and package membership.
   See dep_grants.mli for the file format and the contract; the plan is
   specs/plans/2026-11-22-ocap-p6-grants-plan.md (decisions 3, 4, 5, 12). *)

open March_ast

type grant = {
  g_pkg : string;
  g_root : string;
  g_manifest : string;
  g_line : int;
  g_text : string;
  g_entries : (Ast.name list * string option) list;
  g_scoped : bool;
}

let env_var = "MARCH_DEP_GRANTS"

(* ── Scope text ─────────────────────────────────────────────────────────── *)

let wrapper_module = "G__"

let parse_scope_text (text : string) :
    ((Ast.name list * string option) list, string) result =
  let t = String.trim text in
  if t = "()" then Ok []
  else if t = "" then Error "the grant is empty; write `()` to grant nothing"
  else if String.contains t '\n' || String.contains t '\r' then
    Error "the grant spans more than one line"
  else
    let src = Printf.sprintf "mod %s do needs %s end" wrapper_module t in
    let bad () =
      Error (Printf.sprintf "`%s` is not a list of capabilities in `needs` syntax" t)
    in
    match March_parser.Parse.module_ ~filename:"<grant>" src with
    | Error (d :: _) ->
      (* The parser's first line, unless it is only a lead-in to a caret
         snippet ("I got stuck here:"), which means nothing out of context. *)
      let first = String.trim (List.hd (String.split_on_char '\n' d.March_errors.Errors.message)) in
      if first = "" || first.[String.length first - 1] = ':' then bad ()
      else
        Error
          (Printf.sprintf "`%s` is not a list of capabilities in `needs` syntax: %s" t first)
    | Error [] -> bad ()
    | Ok { Ast.mod_name; mod_decls = [ Ast.DNeeds (entries, _) ] }
      when mod_name.Ast.txt = wrapper_module ->
      Ok entries
    | Ok _ -> bad ()

(* ── The file ───────────────────────────────────────────────────────────── *)

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
      really_input_string ic (in_channel_length ic))

let is_space c = c = ' ' || c = '\t' || c = '\n' || c = '\r'

(* One non-comment line of the grants file into a grant. *)
let parse_line (line : string) : (grant, string) result =
  let ( let* ) = Result.bind in
  let* () =
    if String.contains line '\r' then Error "a field contains a carriage return"
    else Ok ()
  in
  let* pkg, root, man, text =
    match String.split_on_char '\t' line with
    | [ a; b; c; d ] -> Ok (a, b, c, d)
    | fs when List.length fs < 4 ->
      Error
        (Printf.sprintf
           "expected four tab-separated fields (package, library root, \
            manifest:line, grant), found %d"
           (List.length fs))
    | _ ->
      Error
        "a field contains a tab: expected exactly four tab-separated fields \
         (package, library root, manifest:line, grant)"
  in
  let* () =
    if pkg = "" then Error "the package name is empty"
    else if String.exists is_space pkg then
      Error (Printf.sprintf "the package name `%s` contains white space" pkg)
    else Ok ()
  in
  let* root =
    if root = "" || root.[0] <> '/' then
      Error
        (Printf.sprintf
           "the library root `%s` of `%s` is not an absolute path" root pkg)
    else
      match Unix.realpath root with
      | r when Sys.file_exists r && Sys.is_directory r -> Ok r
      | _ ->
        Error
          (Printf.sprintf "the library root `%s` of `%s` is not a directory" root
             pkg)
      | exception Unix.Unix_error _ ->
        Error
          (Printf.sprintf "the library root `%s` of `%s` does not exist" root pkg)
  in
  let* manifest, mline =
    let bad () =
      Error
        (Printf.sprintf
           "`%s` is not `<manifest>:<line>` (the forge.toml entry that grants \
            `%s`)"
           man pkg)
    in
    match String.rindex_opt man ':' with
    | None -> bad ()
    | Some i ->
      let m = String.sub man 0 i
      and n = String.sub man (i + 1) (String.length man - i - 1) in
      if m = "" || n = "" || not (String.for_all (fun c -> c >= '0' && c <= '9') n)
      then bad ()
      else (
        match int_of_string_opt n with
        | Some k when k >= 1 -> Ok (m, k)
        | _ -> bad ())
  in
  let* entries =
    Result.map_error
      (fun msg -> Printf.sprintf "the grant to `%s`: %s" pkg msg)
      (parse_scope_text text)
  in
  let canonical, scoped = Cap_request.request_of_entries entries in
  Ok
    {
      g_pkg = pkg;
      g_root = root;
      g_manifest = manifest;
      g_line = mline;
      g_text = (if entries = [] then "()" else canonical);
      g_entries = entries;
      g_scoped = scoped;
    }

let parse_file (path : string) : (grant list, string * int option) result =
  match read_file path with
  | exception Sys_error msg ->
    Error (Printf.sprintf "cannot read it (%s)" msg, None)
  | contents ->
    let lines = String.split_on_char '\n' contents in
    let rec go lineno acc = function
      | [] -> Ok (List.rev acc)
      | line :: rest ->
        if String.trim line = "" || line.[0] = '#' then go (lineno + 1) acc rest
        else (
          match parse_line line with
          | Error msg -> Error (msg, Some lineno)
          | Ok g -> (
            match
              List.find_opt
                (fun (o : grant) -> o.g_pkg = g.g_pkg || o.g_root = g.g_root)
                acc
            with
            | Some o when o.g_pkg = g.g_pkg ->
              Error
                (Printf.sprintf "the package `%s` is listed more than once" g.g_pkg,
                 Some lineno)
            | Some o ->
              Error
                ( Printf.sprintf
                    "`%s` and `%s` have the same library root `%s`" o.g_pkg
                    g.g_pkg g.g_root,
                  Some lineno )
            | None -> go (lineno + 1) (g :: acc) rest))
    in
    go 1 [] lines

let load ?flag () : (grant list, string * int option) result =
  let source =
    match flag with
    | Some f -> Some f
    | None -> (
      match Sys.getenv_opt env_var with
      | Some "" | None -> None
      | Some f -> Some f)
  in
  match source with
  | None -> Ok []
  | Some path -> parse_file path

(* ── The active set ─────────────────────────────────────────────────────── *)

let active_grants : grant list ref = ref []
let active_digest : string option ref = ref None
let membership : (string, grant option) Hashtbl.t = Hashtbl.create 64
let proven : (string, unit) Hashtbl.t = Hashtbl.create 64

let digest_of (gs : grant list) : string option =
  match gs with
  | [] -> None
  | _ ->
    let b = Buffer.create 256 in
    List.iter
      (fun g ->
         Buffer.add_string b
           (Printf.sprintf "%s\t%s\t%s:%d\t%s\n" g.g_pkg g.g_root g.g_manifest
              g.g_line g.g_text))
      gs;
    Some (Digest.to_hex (Digest.string (Buffer.contents b)))

let set_active (gs : grant list) =
  active_grants := gs;
  active_digest := digest_of gs;
  Hashtbl.reset membership;
  Hashtbl.reset proven

let active () = !active_grants
let digest () = !active_digest

(* [root] contains [path] (both real paths, no trailing slash except "/"). *)
let contains ~root path =
  path = root
  ||
  let pre = if root = "/" then "/" else root ^ "/" in
  String.length path > String.length pre
  && String.sub path 0 (String.length pre) = pre

let package_of_file (file : string) : grant option =
  match !active_grants with
  | [] -> None
  | gs -> (
    match Hashtbl.find_opt membership file with
    | Some r -> r
    | None ->
      let r =
        match Unix.realpath file with
        | exception Unix.Unix_error _ -> None
        | real ->
          List.fold_left
            (fun best g ->
               if contains ~root:g.g_root real then
                 match best with
                 | Some b when String.length b.g_root >= String.length g.g_root ->
                   best
                 | _ -> Some g
               else best)
            None gs
      in
      Hashtbl.replace membership file r;
      r)
