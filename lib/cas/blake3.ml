(** BLAKE3 hashing for March content-addressed versioning.

    Wraps libblake3 via C stubs.
    Output: 64-character lowercase hex string (32-byte digest). *)

external hash_bytes : bytes -> string = "march_blake3_hash"

(** [hash b] returns the BLAKE3 digest of [b] as a 64-char hex string. *)
let hash (b : bytes) : string = hash_bytes b

(** Convenience: hash a string directly. *)
let hash_string (s : string) : string = hash (Bytes.of_string s)

(** Combine multiple byte sequences and hash the concatenation. *)
let hash_concat (parts : bytes list) : string =
  let total = List.fold_left (fun acc b -> acc + Bytes.length b) 0 parts in
  let buf   = Bytes.create total in
  let _     = List.fold_left (fun off b ->
    let len = Bytes.length b in
    Bytes.blit b 0 buf off len;
    off + len) 0 parts in
  hash buf
