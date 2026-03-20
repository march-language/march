(** Compute sig_hash and impl_hash for TIR definitions. *)

open March_tir.Tir

type hashed_fn = {
  sig_hash  : string;   (** BLAKE3 hex of signature only *)
  impl_hash : string;   (** BLAKE3 hex of full impl (sig + body) *)
}

(** Hash a function definition.
    - sig_hash:  BLAKE3(canonical signature bytes)
    - impl_hash: BLAKE3(sig_hash_bytes ++ canonical impl bytes)
      The impl hash covers the full definition so that a body change
      always produces a new impl_hash while leaving sig_hash stable. *)
let hash_fn_def (fd : fn_def) : hashed_fn =
  let sig_bytes  = Serialize.serialize_fn_sig fd in
  let impl_bytes = Serialize.serialize_fn_def fd in
  let sig_hash   = Blake3.hash sig_bytes in
  (* impl_hash = BLAKE3(sig_hash_bytes ++ full impl bytes) *)
  let impl_hash  = Blake3.hash_concat [Bytes.of_string sig_hash; impl_bytes] in
  { sig_hash; impl_hash }
