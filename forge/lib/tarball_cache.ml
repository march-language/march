(** Content-addressed cache of registry tarballs:
    [~/.march/cas/tarballs/<sha256-hex>.tar.gz].

    Before this, a downloaded registry `.tar.gz` went to a temp file, was
    extracted, and was deleted, so the extracted tree was the only copy and the
    lockfile's [checksum] described bytes that no longer existed anywhere
    (`specs/2026-09-11-forge-offline-and-versioned-dep-cache-design.md` §0.2,
    §2.4). Keeping the verified bytes makes three things possible:
    - re-extracting a registry dep with no network after its tree is deleted
      ([Offline_deps.restore_registry_trees]);
    - skipping the download when the same version is installed again;
    - re-verifying against the registry's PUBLISHED digest at any later time.

    {2 Contract}
    - The key is the sha256 of the raw tarball bytes — the registry's published
      checksum, which is what was verified at download time. A file is only
      ever written under the key its own bytes hash to ([store] checks).
    - Writes are atomic: bytes go to a temp file IN THE CACHE DIRECTORY, then
      [Sys.rename] (same filesystem) puts them in place, so a reader never sees
      a partial file and a crash leaves at worst a stray temp file.
    - Every read re-hashes. An entry whose bytes do not match its name is
      reported as [Corrupt], removed so the next online install re-downloads
      it, and never handed to a caller. *)

let cache_dir () =
  let home = try Sys.getenv "HOME" with Not_found -> "" in
  Filename.concat home
    (Filename.concat ".march" (Filename.concat "cas" "tarballs"))

(** Normalise a checksum to 64 lowercase hex digits, accepting an optional
    ["sha256:"] prefix (the lockfile spelling). [None] for anything else, so a
    malformed value can never name a path outside the cache. *)
let hex_of_checksum cs =
  let cs = String.trim cs in
  let cs =
    if String.length cs > 7 && String.sub cs 0 7 = "sha256:"
    then String.sub cs 7 (String.length cs - 7) else cs
  in
  let cs = String.lowercase_ascii cs in
  let is_hex c = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') in
  if String.length cs = 64 && String.for_all is_hex cs then Some cs else None

let path_of_hex hex = Filename.concat (cache_dir ()) (hex ^ ".tar.gz")

(** sha256 hex of a file's bytes, streamed. *)
let sha256_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
      let buf = Bytes.create 65536 in
      let rec loop ctx =
        let n = input ic buf 0 (Bytes.length buf) in
        if n = 0 then ctx
        else loop (Digestif.SHA256.feed_bytes ctx buf ~off:0 ~len:n)
      in
      Digestif.SHA256.to_hex
        (Digestif.SHA256.get (loop Digestif.SHA256.empty)))

type lookup =
  | Hit of string                                  (** verified path *)
  | Miss
  | Corrupt of { path : string; actual : string }  (** removed; not usable *)

(** Find the tarball whose sha256 is [checksum], verifying its bytes. *)
let lookup checksum =
  match hex_of_checksum checksum with
  | None -> Miss
  | Some hex ->
    let path = path_of_hex hex in
    if not (Sys.file_exists path) then Miss
    else
      match (try Some (sha256_file path) with Sys_error _ -> None) with
      | Some actual when actual = hex -> Hit path
      | other ->
        let actual = Option.value ~default:"<unreadable>" other in
        (try Sys.remove path with Sys_error _ -> ());
        Corrupt { path; actual }

let corrupt_warning ~label ~path ~expected ~actual =
  Printf.sprintf
    "warning: %s: cached tarball %s is corrupt (expected sha256 %s, got %s); \
     discarded it"
    label path expected actual

(** Copy [src] into the cache under [checksum], atomically. Refuses (and
    writes nothing) when [src]'s bytes do not hash to [checksum]. Returns the
    cached path. Storing an entry that is already present and intact is a
    no-op. *)
let store ~checksum ~src =
  match hex_of_checksum checksum with
  | None -> Error (Printf.sprintf "not a sha256 checksum: %S" checksum)
  | Some hex ->
    let actual = sha256_file src in
    if actual <> hex then
      Error (Printf.sprintf
               "refusing to cache %s: sha256 is %s, expected %s" src actual hex)
    else begin
      match lookup hex with
      | Hit p -> Ok p
      | Miss | Corrupt _ ->
        let dir = cache_dir () in
        ignore (Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dir)));
        let final = path_of_hex hex in
        let tmp = Filename.concat dir
            (Printf.sprintf ".tmp-%s-%d-%d" hex (Unix.getpid ())
               (Random.bits ())) in
        (try
           let ic = open_in_bin src in
           Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
               let oc = open_out_bin tmp in
               Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
                   let buf = Bytes.create 65536 in
                   let rec loop () =
                     let n = input ic buf 0 (Bytes.length buf) in
                     if n > 0 then (output oc buf 0 n; loop ())
                   in
                   loop ()));
           Sys.rename tmp final;
           Ok final
         with Sys_error e ->
           (try Sys.remove tmp with Sys_error _ -> ());
           Error (Printf.sprintf "could not cache tarball: %s" e))
    end
