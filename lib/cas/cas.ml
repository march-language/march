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

(* Artifacts live under artifacts-v2/ and hold the compiled binary ITSELF.
   v1 (`artifacts/`) stored a POINTER — the text of whatever path the compiler
   happened to write the binary to — which made the "cache" an index of file
   paths rather than a content-addressed store. Nothing owned the pointed-to
   file, so overwriting it silently poisoned every later hit for the original
   key:

     march --compile a.march -o /tmp/x     # store: key(a) -> "/tmp/x"  (AAA)
     march --compile b.march -o /tmp/x     # store: key(b) -> "/tmp/x"  (BBB)
     march --compile a.march -o /tmp/y     # hit key(a) -> copies /tmp/x = BBB

   i.e. compiling a program returned a DIFFERENT program's binary, reported as
   "(cached)", with no error. Found while building the bench gate: three
   benches produced an unrelated program's output because an earlier
   verification loop had reused one -o path for several sources.

   The directory is versioned rather than reused so stale v1 pointer files are
   never read as binaries (that would copy a text file to the output path and
   produce a non-executable "binary"). Old `artifacts/` trees are inert and can
   simply be deleted. *)
let artifact_path root ch =
  let prefix = String.sub ch 0 2 in
  let rest   = String.sub ch 2 (String.length ch - 2) in
  root ^ "/artifacts-v2/" ^ prefix ^ "/" ^ rest

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

(* Identity of the compiler that produced an artifact.  The compilation_hash
   must change whenever the compiler itself changes — otherwise a rebuilt
   compiler (e.g. a codegen bugfix) silently serves a stale binary that was
   cached under the same source+target+flags key.  We mix in a BLAKE3 of the
   running executable's contents; computed once per process (Lazy) since the
   executable does not change underneath a live process.  Falls back to the
   executable path + mtime if the bytes can't be read. *)
let compiler_identity : string Lazy.t = lazy (
  let exe = Sys.executable_name in
  match
    (try
       let ic = open_in_bin exe in
       Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
         let n = in_channel_length ic in
         let b = Bytes.create n in
         really_input ic b 0 n;
         Some (Blake3.hash_string (Bytes.unsafe_to_string b)))
     with _ -> None)
  with
  | Some h -> h
  | None ->
    let mtime = try string_of_float (Unix.stat exe).Unix.st_mtime with _ -> "0" in
    Blake3.hash_string (exe ^ "\x00" ^ mtime))

(* Identity of the C runtime that gets compiled and linked into output
   binaries.  The runtime sources are NOT part of the compiler executable,
   so compiler_identity does not cover them: editing runtime/march_extras.c
   would still serve the stale binary cached under the same key.  Digest
   every .c/.h file (sorted name + contents) in the runtime directory. *)
let runtime_identity_of_dir (dir : string) : string =
  let files =
    try
      Sys.readdir dir
      |> Array.to_list
      |> List.filter (fun f ->
           Filename.check_suffix f ".c" || Filename.check_suffix f ".h")
      |> List.sort String.compare
    with Sys_error _ -> []
  in
  let buf = Buffer.create (1 lsl 16) in
  List.iter (fun f ->
    Buffer.add_string buf f;
    Buffer.add_char buf '\x00';
    (match read_file (Filename.concat dir f) with
     | Some data -> Buffer.add_string buf data
     | None -> ());
    Buffer.add_char buf '\x00'
  ) files;
  Blake3.hash_string (Buffer.contents buf)

(* Which runtime directory this process compiles against.
   ────────────────────────────────────────────────────────
   The digest MUST cover the directory whose sources are ACTUALLY handed to
   clang, which only the compiler driver knows.  This used to be resolved here
   with an independent, cwd-FIRST candidate list while bin/main.ml resolved the
   sources it compiles exe-relative-first ("independent of CWD").  The two
   disagree exactly when cwd is the repo root and the exe is dune's
   _build/default/bin/main.exe: the key digested the edited ./runtime/*.c while
   the compile used the (not necessarily refreshed) _build/default/runtime/*.c.
   Editing a runtime source then produced `compiled <out> (cached)` with none of
   the new code in the binary — and compiler_identity does not save us, since
   the march executable's bytes do not change when only runtime C changes.

   So the driver registers its resolved directory via [set_runtime_dir] and
   that is the single source of truth.  The fallback below (for callers that
   never register one — unit tests, library embeddings) now mirrors
   bin/main.ml's find_runtime_file order: exe-relative first, cwd last, and a
   candidate only counts if it actually holds march_runtime.c. *)
let runtime_dir_override : string option ref = ref None

(* Memoized like compiler_identity — the runtime sources do not change
   underneath a live process — but keyed on the resolved directory, so a
   [set_runtime_dir] to a different directory recomputes instead of returning
   the previous directory's digest. *)
let runtime_identity_memo : (string * string) option ref = ref None

let resolve_runtime_dir () : string option =
  match !runtime_dir_override with
  | Some _ as d -> d
  | None ->
    let exe_dir = Filename.dirname Sys.executable_name in
    let candidates = [
      Filename.concat exe_dir "../runtime";
      Filename.concat exe_dir "../../runtime";
      Filename.concat exe_dir "../../../runtime";
      "runtime";
    ] in
    List.find_opt
      (fun d -> Sys.file_exists (Filename.concat d "march_runtime.c"))
      candidates

(* Registering (or re-registering) a directory also drops the memo, so the
   digest is re-read from disk rather than answered from a previous
   registration's snapshot. *)
let set_runtime_dir (dir : string) : unit =
  runtime_dir_override := Some dir;
  runtime_identity_memo := None

(* Drop a registration and go back to the fallback search (tests). *)
let clear_runtime_dir () : unit =
  runtime_dir_override := None;
  runtime_identity_memo := None

(* Falls back to "" if no runtime dir is found (e.g. unit tests) — the hash
   then simply carries no runtime component. *)
let runtime_identity () : string =
  let dir = match resolve_runtime_dir () with Some d -> d | None -> "" in
  match !runtime_identity_memo with
  | Some (d, h) when String.equal d dir -> h
  | _ ->
    let h = if dir = "" then "" else runtime_identity_of_dir dir in
    runtime_identity_memo := Some (dir, h);
    h

let compilation_hash (impl_hash : string) ~(target : string) ~(flags : string list) : string =
  let parts =
    [impl_hash; target; Lazy.force compiler_identity; runtime_identity ()]
    @ flags
  in
  Blake3.hash_string (String.concat "\x00" parts)

(* Copy [src] to [dest] preserving the executable bit, replacing [dest] if it
   exists.  Returns false on any failure so callers can treat it as a cache
   miss rather than reporting a success they did not achieve. *)
let copy_file_exec ~(src : string) ~(dest : string) : bool =
  try
    mkdir_p (Filename.dirname dest);
    match read_file src with
    | None -> false
    | Some data ->
      (* Write via a temp file in the destination directory and rename, so a
         concurrent reader never observes a half-written binary and a crash
         mid-copy cannot leave a truncated artifact in the cache. *)
      let tmp = dest ^ ".tmp." ^ string_of_int (Unix.getpid ()) in
      write_file tmp data;
      (try Unix.chmod tmp 0o755 with Unix.Unix_error _ -> ());
      Sys.rename tmp dest;
      true
  with Sys_error _ | Unix.Unix_error _ -> false

(* Store the compiled binary IN the cache (by content), not a pointer to it.
   See [artifact_path] for why a pointer is unsound. A failed copy simply
   leaves no entry — a future compile misses and rebuilds, which is correct. *)
let store_artifact (t : t) (ch : string) (path : string) : unit =
  let blob = artifact_path t.local_root ch in
  if copy_file_exec ~src:path ~dest:blob then
    Hashtbl.replace t.artifacts ch blob

(* Copy a cached artifact to [dest], returning false if the artifact file is
   gone or the copy fails — callers must treat that as a cache miss and
   recompile, instead of reporting "(cached)" with no output written.
   [src] is now always a blob inside the cache, so it can never alias [dest];
   the same-file guard is kept as a cheap defence for any caller that passes a
   path of its own. *)
let copy_artifact ~(src : string) ~(dest : string) : bool =
  if not (Sys.file_exists src) then false
  else
    let same_file =
      try
        let a = Unix.stat src and b = Unix.stat dest in
        a.Unix.st_dev = b.Unix.st_dev && a.Unix.st_ino = b.Unix.st_ino
      with Unix.Unix_error _ -> false
    in
    same_file || copy_file_exec ~src ~dest

let lookup_artifact (t : t) (ch : string) : string option =
  let blob = artifact_path t.local_root ch in
  if Sys.file_exists blob then begin
    (* Keep the memo in step with the on-disk truth. *)
    Hashtbl.replace t.artifacts ch blob;
    Some blob
  end else begin
    (* A memo entry whose blob has been removed (gc, manual rm) is stale. *)
    Hashtbl.remove t.artifacts ch;
    None
  end

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
  (* Walk artifacts-v2/ (the content-addressed binaries; see artifact_path) *)
  let art_root = t.local_root ^ "/artifacts-v2" in
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
