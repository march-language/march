(** ML-KEM-768 (FIPS 203) and ML-DSA-65 (FIPS 204) via C stubs over the
    vendored mlkem-native / mldsa-native (runtime/pqc.c), the same code the
    compiled runtime links (runtime/march_pqc.c).

    Every function is deterministic: randomness is an argument. Each returns
    [None] on a wrong-length argument or a key the library rejects; the
    interpreter maps that to EMPTY Bytes, matching the runtime. *)

external mlkem768_keypair_c : string -> string option = "caml_pqc_mlkem768_keypair"
external mlkem768_encaps_c  : string -> string -> string option = "caml_pqc_mlkem768_encaps"
external mlkem768_decaps_c  : string -> string -> string option = "caml_pqc_mlkem768_decaps"
external mldsa65_keypair_c  : string -> string option = "caml_pqc_mldsa65_keypair"
external mldsa65_sign_c     : string -> string -> string -> string option = "caml_pqc_mldsa65_sign"
external mldsa65_verify_c   : string -> string -> string -> bool = "caml_pqc_mldsa65_verify"

(** [mlkem768_keypair seed] — 64-byte seed (d || z) to the 2400-byte
    decapsulation key, which embeds the 1184-byte encapsulation key at 1152. *)
let mlkem768_keypair seed = mlkem768_keypair_c seed

(** [mlkem768_encaps pk coins] — ciphertext (1088) || shared secret (32). *)
let mlkem768_encaps pk coins = mlkem768_encaps_c pk coins

(** [mlkem768_decaps sk ct] — the 32-byte shared secret. *)
let mlkem768_decaps sk ct = mlkem768_decaps_c sk ct

(** [mldsa65_keypair seed] — 32-byte seed to sk (4032) || pk (1952). *)
let mldsa65_keypair seed = mldsa65_keypair_c seed

(** [mldsa65_sign sk msg rnd] — 3309-byte pure-ML-DSA signature, empty context. *)
let mldsa65_sign sk msg rnd = mldsa65_sign_c sk msg rnd

(** [mldsa65_verify pk msg sig] *)
let mldsa65_verify pk msg sg = mldsa65_verify_c pk msg sg
