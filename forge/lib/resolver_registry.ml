(** Local registry index — maps package names to available versions and their deps.

    The registry index is stored as a TOML file at:
      ~/.march/registry/forge/index.toml

    Format:
    ────────────────────────────────────────────────────────────────────
    [[package]]
    name    = "json"
    version = "1.4.7"

    [[package.dep]]
    name       = "core"
    constraint = "~> 1.0"

    [[package]]
    name    = "json"
    version = "1.5.0"

    [[package.dep]]
    name       = "core"
    constraint = "~> 1.0"
    ────────────────────────────────────────────────────────────────────

    In Phase 2 the registry is purely local (populated by `forge publish` and
    `forge deps` from a registry manifest file).  Network transport is Phase 6.
*)

module V  = Resolver_version
module VC = Resolver_constraint

(** A single version of a package as known to the registry. *)
type package_version = {
  name        : string;
  version     : V.t;
  deps        : (string * VC.t) list;  (** name → constraint *)
}

(** The in-memory registry index. *)
type t = {
  packages : (string, package_version list) Hashtbl.t;
}

let create () = { packages = Hashtbl.create 16 }

(** Add a package version to the index. *)
let add_version idx pv =
  let existing = try Hashtbl.find idx.packages pv.name with Not_found -> [] in
  Hashtbl.replace idx.packages pv.name (pv :: existing)

(** Return all known versions for a package, sorted descending (newest first). *)
let versions_of idx name =
  match Hashtbl.find_opt idx.packages name with
  | None   -> []
  | Some vs ->
    List.sort (fun a b -> V.compare b.version a.version) vs

(** Return the deps of a specific version. *)
let deps_of idx name version =
  match Hashtbl.find_opt idx.packages name with
  | None    -> None
  | Some vs ->
    match List.find_opt (fun pv -> V.equal pv.version version) vs with
    | None    -> None
    | Some pv -> Some pv.deps

(* ------------------------------------------------------------------ *)
(*  Index file loading                                                 *)
(* ------------------------------------------------------------------ *)

let home_dir () =
  try Sys.getenv "HOME" with Not_found -> ""

let default_index_path () =
  Filename.concat (home_dir ())
    (Filename.concat ".march"
       (Filename.concat "registry"
          (Filename.concat "forge" "index.toml")))

(** Parse a registry index TOML file into an index.

    The format uses `[[package]]` arrays (same structure as forge.lock).
    Each [[package]] block can be followed by [[package.dep]] blocks.

    We use a simple line-by-line parser since we control the format. *)
let load_from_string content =
  let idx = create () in
  let lines = String.split_on_char '\n' content in
  let cur_name    = ref "" in
  let cur_version = ref None in
  let cur_deps    = ref [] in
  let in_pkg      = ref false in
  let in_dep      = ref false in
  let dep_name    = ref "" in
  let dep_constr  = ref "" in
  let flush_dep () =
    if !dep_name <> "" && !dep_constr <> "" then begin
      cur_deps := (!dep_name, !dep_constr) :: !cur_deps;
      dep_name := "";
      dep_constr := ""
    end
  in
  let flush_package () =
    flush_dep ();
    if !cur_name <> "" then begin
      match !cur_version with
      | None -> ()
      | Some ver_str ->
        (match V.parse ver_str with
         | Error _ -> ()
         | Ok v ->
           let parsed_deps = List.filter_map (fun (dn, dc) ->
               match VC.parse dc with
               | Ok c  -> Some (dn, c)
               | Error _ -> None
             ) (List.rev !cur_deps) in
           add_version idx {
             name    = !cur_name;
             version = v;
             deps    = parsed_deps;
           })
    end;
    cur_name    := "";
    cur_version := None;
    cur_deps    := [];
    in_pkg      := false;
    in_dep      := false
  in
  let unquote s =
    let s = String.trim s in
    let n = String.length s in
    if n >= 2 && s.[0] = '"' && s.[n-1] = '"' then
      String.sub s 1 (n - 2)
    else s
  in
  let parse_kv line =
    match String.index_opt line '=' with
    | None -> ()
    | Some eq ->
      let key   = String.trim (String.sub line 0 eq) in
      let value = unquote (String.sub line (eq+1) (String.length line - eq - 1)) in
      if !in_dep then begin
        (match key with
         | "name"       -> dep_name   := value
         | "constraint" -> dep_constr := value
         | _ -> ())
      end else if !in_pkg then begin
        (match key with
         | "name"    -> cur_name    := value
         | "version" -> cur_version := Some value
         | _ -> ())
      end
  in
  List.iter (fun raw ->
      let line = String.trim raw in
      if line = "" || (String.length line > 0 && line.[0] = '#') then ()
      else if line = "[[package.dep]]" then begin
        flush_dep ();
        in_dep := true
      end else if line = "[[package]]" then begin
        flush_package ();
        in_pkg := true;
        in_dep := false
      end else if String.length line > 0 && line.[0] = '[' then begin
        flush_package ()
      end else
        parse_kv line
    ) lines;
  flush_package ();
  idx

let load_from_file path =
  if not (Sys.file_exists path) then
    (* Empty index if the file doesn't exist yet *)
    Ok (create ())
  else
    try
      let ic = open_in path in
      let n = in_channel_length ic in
      let buf = Bytes.create n in
      really_input ic buf 0 n;
      close_in ic;
      Ok (load_from_string (Bytes.to_string buf))
    with Sys_error e -> Error e

let load () = load_from_file (default_index_path ())

(* ------------------------------------------------------------------ *)
(*  Serialization (for `forge publish` and tests)                     *)
(* ------------------------------------------------------------------ *)

let save_to_file idx path =
  let all_versions =
    Hashtbl.fold (fun _ vs acc -> vs @ acc) idx.packages []
    |> List.sort (fun a b ->
        let c = String.compare a.name b.name in
        if c <> 0 then c else V.compare a.version b.version)
  in
  let oc = open_out path in
  output_string oc "# Forge registry index — auto-generated\n";
  List.iter (fun pv ->
      output_char oc '\n';
      output_string oc "[[package]]\n";
      output_string oc (Printf.sprintf "name    = %S\n" pv.name);
      output_string oc (Printf.sprintf "version = %S\n" (V.to_string pv.version));
      List.iter (fun (dn, dc) ->
          output_char oc '\n';
          output_string oc "[[package.dep]]\n";
          output_string oc (Printf.sprintf "name       = %S\n" dn);
          output_string oc (Printf.sprintf "constraint = %S\n" (VC.to_string dc))
        ) pv.deps
    ) all_versions;
  close_out oc
