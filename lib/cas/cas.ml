(** Content-Addressed Store for March.

    Two layers:
    - Project-local: <project_root>/.march/cas/
    - Global (read-through cache): ~/.march/cas/

    Objects are keyed by their impl_hash (64-char hex).
    Compiled artifacts are keyed by compilation_hash = BLAKE3(impl_hash ++ target ++ flags).
*)

open March_tir.Tir

(* ── Types ──────────────────────────────────────────────────────────────── *)

type def_id = March_tir.Tir.def_id = {
  did_name : string;     (** human-readable, for errors/display *)
  did_hash : string;     (** 64-char hex impl_hash *)
}

type def_kind =
  | FnDef   of fn_def
  | TypeDef of type_def

type hashed_def = {
  hd_sig_hash  : string;   (** sig_hash  hex *)
  hd_impl_hash : string;   (** impl_hash hex *)
  hd_def       : def_kind;
}

(* ── Store internals ────────────────────────────────────────────────────── *)

type t = {
  local_root  : string;         (** <project_root>/.march/cas *)
  global_root : string option;  (** ~/.march/cas if $HOME is set *)
  (* In-memory index: name → def_id (persisted to index.bin on update) *)
  mutable index : (string, def_id) Hashtbl.t;
  (* In-memory artifact map: compilation_hash → artifact_path *)
  mutable artifacts : (string, string) Hashtbl.t;
}

(* ── Filesystem helpers ─────────────────────────────────────────────────── *)

let mkdir_p path =
  let parts = String.split_on_char '/' path in
  let _ = List.fold_left (fun acc part ->
    if part = "" then acc
    else begin
      let p = if acc = "" then "/" ^ part else acc ^ "/" ^ part in
      (try Unix.mkdir p 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
      p
    end) "" parts in
  ()

let object_path root hash =
  (* git-style: first 2 hex chars as directory prefix *)
  let prefix = String.sub hash 0 2 in
  let rest   = String.sub hash 2 (String.length hash - 2) in
  root ^ "/objects/" ^ prefix ^ "/" ^ rest

let artifact_path root ch =
  let prefix = String.sub ch 0 2 in
  let rest   = String.sub ch 2 (String.length ch - 2) in
  root ^ "/artifacts/" ^ prefix ^ "/" ^ rest

(* ── Serialization helpers for stored objects ───────────────────────────── *)

(* We store the hashed_def as: sig_hash (64B) + impl_hash (64B) + kind_tag (1B) + payload *)

let write_file path data =
  let dir = Filename.dirname path in
  mkdir_p dir;
  let oc = open_out_bin path in
  output_string oc data;
  close_out oc

let read_file path =
  try
    let ic  = open_in_bin path in
    let len = in_channel_length ic in
    let s   = Bytes.create len in
    really_input ic s 0 len;
    close_in ic;
    Some (Bytes.to_string s)
  with Sys_error _ -> None

let encode_hashed_def (hd : hashed_def) : string =
  (* Simple encoding: sig_hash + "\n" + impl_hash + "\n" + marshalled def *)
  let kind_bytes = Marshal.to_string hd.hd_def [] in
  hd.hd_sig_hash ^ "\n" ^ hd.hd_impl_hash ^ "\n" ^ kind_bytes

let decode_hashed_def (s : string) : hashed_def option =
  match String.split_on_char '\n' s with
  | sig_hash :: impl_hash :: rest ->
    let kind_bytes = String.concat "\n" rest in
    (try
      let def : def_kind = Marshal.from_string kind_bytes 0 in
      Some { hd_sig_hash = sig_hash; hd_impl_hash = impl_hash; hd_def = def }
    with _ -> None)
  | _ -> None

(* ── Public API ─────────────────────────────────────────────────────────── *)

let create ~project_root =
  let local_root = project_root ^ "/.march/cas" in
  mkdir_p (local_root ^ "/objects");
  mkdir_p (local_root ^ "/artifacts");
  let global_root =
    match Sys.getenv_opt "HOME" with
    | Some h ->
      let g = h ^ "/.march/cas" in
      (try mkdir_p (g ^ "/objects"); mkdir_p (g ^ "/artifacts"); Some g
       with _ -> None)
    | None -> None
  in
  { local_root; global_root; index = Hashtbl.create 64; artifacts = Hashtbl.create 64 }

let store_def (t : t) (hd : hashed_def) : unit =
  let path = object_path t.local_root hd.hd_impl_hash in
  write_file path (encode_hashed_def hd)

let lookup_def (t : t) (impl_hash : string) : hashed_def option =
  (* 1. project-local *)
  let local = object_path t.local_root impl_hash in
  match read_file local with
  | Some data -> decode_hashed_def data
  | None ->
    (* 2. global *)
    match t.global_root with
    | None -> None
    | Some gr ->
      let global = object_path gr impl_hash in
      match read_file global with
      | None      -> None
      | Some data ->
        (* Warm local cache *)
        write_file local data;
        decode_hashed_def data

let compilation_hash (impl_hash : string) ~(target : string) ~(flags : string list) : string =
  let parts = [impl_hash; target] @ flags in
  Blake3.hash_string (String.concat "\x00" parts)

let store_artifact (t : t) (ch : string) (path : string) : unit =
  Hashtbl.replace t.artifacts ch path;
  (* Also write a pointer file so the store is persistent across processes *)
  let ptr = artifact_path t.local_root ch in
  write_file ptr path

let lookup_artifact (t : t) (ch : string) : string option =
  match Hashtbl.find_opt t.artifacts ch with
  | Some p -> Some p
  | None ->
    let ptr = artifact_path t.local_root ch in
    read_file ptr

let lookup_name (t : t) (name : string) : def_id option =
  Hashtbl.find_opt t.index name

let update_index (t : t) (entries : (string * def_id) list) : unit =
  List.iter (fun (name, did) -> Hashtbl.replace t.index name did) entries

let gc (t : t) ~(keep_defs : string list) ~(keep_artifacts : string list) : int =
  let removed = ref 0 in
  let keep_set = Hashtbl.create (List.length keep_defs) in
  List.iter (fun h -> Hashtbl.replace keep_set h ()) keep_defs;
  (* Walk objects/ directory and remove any file whose name is not in keep_set *)
  let obj_root = t.local_root ^ "/objects" in
  (try
    let prefixes = Sys.readdir obj_root in
    Array.iter (fun prefix ->
      let dir = obj_root ^ "/" ^ prefix in
      (try
        let files = Sys.readdir dir in
        Array.iter (fun file ->
          let hash = prefix ^ file in
          if not (Hashtbl.mem keep_set hash) then begin
            (try Sys.remove (dir ^ "/" ^ file) with Sys_error _ -> ());
            incr removed
          end) files
      with Sys_error _ -> ())) prefixes
  with Sys_error _ -> ());
  (* Walk artifacts/ directory *)
  let art_root = t.local_root ^ "/artifacts" in
  let keep_art_set = Hashtbl.create (List.length keep_artifacts) in
  List.iter (fun h -> Hashtbl.replace keep_art_set h ()) keep_artifacts;
  (try
    let prefixes = Sys.readdir art_root in
    Array.iter (fun prefix ->
      let dir = art_root ^ "/" ^ prefix in
      (try
        let files = Sys.readdir dir in
        Array.iter (fun file ->
          let hash = prefix ^ file in
          if not (Hashtbl.mem keep_art_set hash) then begin
            (try Sys.remove (dir ^ "/" ^ file) with Sys_error _ -> ());
            incr removed
          end) files
      with Sys_error _ -> ())) prefixes
  with Sys_error _ -> ());
  !removed
