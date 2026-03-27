(** Package content-addressed storage.

    Each dependency's source tree is stored as a *canonical archive* in the
    global CAS at:  ~/.march/cas/packages/<sha256-hex>/

    Canonical archive format (Nix-inspired, reproducible):
      1. Walk all source files, excluding .git/, .march/, build artifacts.
      2. Sort entries by path (lexicographic UTF-8 byte order).
      3. For each file:
           <path_length : uint32-le> <path_bytes>
           <content_length : uint32-le> <content_bytes>
      4. Permissions stripped (all treated as regular files).
      5. Timestamps stripped (not included in the canonical form).

    The SHA-256 of the concatenated canonical bytes is the *content hash*.
    Two identical source trees on any machine produce the same hash.
    Hash format: "sha256:<hex>"

    The CAS directory layout:
      ~/.march/cas/packages/
        <sha256-hex>/
          archive    — the canonical archive bytes
          info.toml  — name, version, source URL (informational only)

    Build-time integrity verification:
      On every build, forge re-hashes each dep's CAS entry and checks it
      against the hash recorded in forge.lock.  Mismatch → build aborts.
*)

(* ------------------------------------------------------------------ *)
(*  File collection                                                    *)
(* ------------------------------------------------------------------ *)

(** Directories and filename patterns to skip when building the archive. *)
let skip_dirs  = [".git"; ".march"; "_build"; "node_modules"; ".DS_Store"]
let skip_files = [".DS_Store"; "forge.lock"]

let should_skip name =
  List.mem name skip_dirs || List.mem name skip_files

(** Recursively collect all file paths under [root_dir].
    Returns paths relative to [root_dir], sorted lexicographically. *)
let collect_files root_dir =
  let files = ref [] in
  let rec walk rel_dir abs_dir =
    (try
       let entries = Sys.readdir abs_dir in
       Array.iter (fun name ->
           if not (should_skip name) then begin
             let rel_path = if rel_dir = "" then name
               else rel_dir ^ "/" ^ name in
             let abs_path = Filename.concat abs_dir name in
             if Sys.is_directory abs_path then
               walk rel_path abs_path
             else
               files := rel_path :: !files
           end
         ) entries
     with Sys_error _ -> ())
  in
  walk "" root_dir;
  List.sort String.compare !files

(* ------------------------------------------------------------------ *)
(*  Canonical archive serialization                                    *)
(* ------------------------------------------------------------------ *)

(** Encode a uint32 in little-endian as 4 bytes. *)
let uint32_le n =
  let b = Bytes.create 4 in
  Bytes.set_uint8 b 0 (n land 0xFF);
  Bytes.set_uint8 b 1 ((n lsr 8)  land 0xFF);
  Bytes.set_uint8 b 2 ((n lsr 16) land 0xFF);
  Bytes.set_uint8 b 3 ((n lsr 24) land 0xFF);
  b

(** Read the entire contents of a file. *)
let read_file path =
  let ic = open_in_bin path in
  let n  = in_channel_length ic in
  let buf = Bytes.create n in
  really_input ic buf 0 n;
  close_in ic;
  buf

(** Build the canonical archive bytes for a source directory. *)
let canonical_archive root_dir =
  let files = collect_files root_dir in
  let parts = List.concat_map (fun rel_path ->
      let abs_path = Filename.concat root_dir rel_path in
      let path_bytes    = Bytes.of_string rel_path in
      let content_bytes =
        try read_file abs_path
        with Sys_error _ -> Bytes.empty
      in
      let path_len    = uint32_le (Bytes.length path_bytes) in
      let content_len = uint32_le (Bytes.length content_bytes) in
      [path_len; path_bytes; content_len; content_bytes]
    ) files in
  (* Concatenate all parts *)
  let total = List.fold_left (fun acc b -> acc + Bytes.length b) 0 parts in
  let buf = Bytes.create total in
  let _pos = List.fold_left (fun pos b ->
      Bytes.blit b 0 buf pos (Bytes.length b);
      pos + Bytes.length b
    ) 0 parts in
  buf

(* ------------------------------------------------------------------ *)
(*  Hashing                                                            *)
(* ------------------------------------------------------------------ *)

(** Compute the SHA-256 content hash of a canonical archive.
    Returns a string of the form "sha256:<hex>". *)
let hash_archive (archive : bytes) =
  let digest = Digestif.SHA256.digest_bytes archive in
  "sha256:" ^ Digestif.SHA256.to_hex digest

(** Compute the content hash of a source directory. *)
let hash_directory root_dir =
  let archive = canonical_archive root_dir in
  hash_archive archive

(* ------------------------------------------------------------------ *)
(*  CAS storage                                                        *)
(* ------------------------------------------------------------------ *)

let home_dir () =
  try Sys.getenv "HOME" with Not_found -> ""

let packages_cas_root () =
  Filename.concat (home_dir ())
    (Filename.concat ".march" (Filename.concat "cas" "packages"))

let package_dir cas_root hash =
  (* Strip the "sha256:" prefix *)
  let hex = if String.length hash > 7 && String.sub hash 0 7 = "sha256:"
    then String.sub hash 7 (String.length hash - 7)
    else hash
  in
  Filename.concat cas_root hex

let mkdir_p dir =
  let _ = Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dir)) in ()

(** Store a source directory in the CAS.
    Returns the content hash. If the package is already in the CAS (same
    hash), this is a no-op.  The hash is written to forge.lock. *)
let store_directory ?(name="") ?(source="") root_dir =
  let archive    = canonical_archive root_dir in
  let hash       = hash_archive archive in
  let cas_root   = packages_cas_root () in
  let pkg_dir    = package_dir cas_root hash in
  if not (Sys.file_exists pkg_dir) then begin
    mkdir_p pkg_dir;
    (* Write canonical archive *)
    let archive_path = Filename.concat pkg_dir "archive" in
    let oc = open_out_bin archive_path in
    output_bytes oc archive;
    close_out oc;
    (* Write info.toml *)
    let info_path = Filename.concat pkg_dir "info.toml" in
    let oc = open_out info_path in
    output_string oc (Printf.sprintf
        "name   = %S\nsource = %S\nhash   = %S\n" name source hash);
    close_out oc
  end;
  hash

(** Look up a package by its content hash.
    Returns the path to the canonical archive file, or None if not found. *)
let lookup hash =
  let cas_root = packages_cas_root () in
  let pkg_dir  = package_dir cas_root hash in
  let archive  = Filename.concat pkg_dir "archive" in
  if Sys.file_exists archive then Some archive else None

(** Verify that the CAS entry for [hash] has not been tampered with.
    Re-hashes the stored archive and compares.
    Returns Ok () if intact, Error msg if corrupted. *)
let verify hash =
  match lookup hash with
  | None ->
    Error (Printf.sprintf "package with hash %s not found in CAS" hash)
  | Some archive_path ->
    (try
       let stored = read_file archive_path in
       let actual = hash_archive stored in
       if actual = hash then Ok ()
       else Error (Printf.sprintf
           "integrity check failed for %s\n  expected: %s\n  got:      %s"
           archive_path hash actual)
     with Sys_error e ->
       Error (Printf.sprintf "could not read CAS entry: %s" e))
