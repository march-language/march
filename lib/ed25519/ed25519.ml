(** Ed25519 digital signatures via TweetNaCl C stubs.

    Public key: 32 bytes.  Secret key: 64 bytes (seed || public key).
    Signatures: 64 bytes (detached). *)

external keygen_c    : unit   -> bytes * bytes = "caml_ed25519_keygen"
external sign_c      : bytes -> bytes -> bytes  = "caml_ed25519_sign"
external verify_c    : bytes -> bytes -> bytes -> bool = "caml_ed25519_verify"

(** Generate a fresh keypair.  Returns [(public_key, secret_key)].
    Reads 32 random bytes from /dev/urandom.  Raises Failure on error. *)
let keygen () : bytes * bytes = keygen_c ()

(** [sign msg sk] — produce a 64-byte detached signature over [msg].
    [sk] must be the 64-byte secret key from [keygen].
    Raises Failure on invalid input. *)
let sign (msg : bytes) (sk : bytes) : bytes = sign_c msg sk

(** [verify msg sig pk] — return [true] if [sig] is a valid ed25519 signature
    over [msg] under public key [pk]. *)
let verify (msg : bytes) (signature : bytes) (pk : bytes) : bool =
  verify_c msg signature pk

(** [sign_str s sk] — sign a string [s], returning a 64-byte signature. *)
let sign_str (s : string) (sk : bytes) : bytes =
  sign (Bytes.of_string s) sk

(** [pk_to_base64 pk] — URL-safe base64 encoding of a 32-byte public key. *)
let pk_to_base64 (pk : bytes) : string =
  let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" in
  let n = Bytes.length pk in
  let out = Buffer.create (((n + 2) / 3) * 4) in
  let i = ref 0 in
  while !i < n do
    let b0 = Char.code (Bytes.get pk !i) in
    let b1 = if !i+1 < n then Char.code (Bytes.get pk (!i+1)) else 0 in
    let b2 = if !i+2 < n then Char.code (Bytes.get pk (!i+2)) else 0 in
    Buffer.add_char out chars.[b0 lsr 2];
    Buffer.add_char out chars.[((b0 land 3) lsl 4) lor (b1 lsr 4)];
    Buffer.add_char out (if !i+1 < n then chars.[((b1 land 15) lsl 2) lor (b2 lsr 6)] else '=');
    Buffer.add_char out (if !i+2 < n then chars.[b2 land 63] else '=');
    i := !i + 3
  done;
  Buffer.contents out

(** [pk_of_base64 s] — decode base64 → 32-byte public key, or [None] on error. *)
let pk_of_base64 (s : string) : bytes option =
  let tbl = Array.make 256 (-1) in
  String.iteri (fun i _c ->
    if i < 26 then tbl.(Char.code 'A' + i) <- i
    else if i < 52 then tbl.(Char.code 'a' + (i-26)) <- i
    else if i < 62 then tbl.(Char.code '0' + (i-52)) <- i
    else if i = 62 then tbl.(Char.code '+') <- 62
    else tbl.(Char.code '/') <- 63
  ) "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  (* strip padding *)
  let s = String.map (fun c -> if c = '=' then 'A' else c) s in
  let n = String.length s in
  if n mod 4 <> 0 then None
  else begin
    let out_n = n / 4 * 3 in
    let buf = Bytes.create out_n in
    let ok = ref true in
    for j = 0 to (n/4) - 1 do
      let v i =
        let x = tbl.(Char.code s.[j*4+i]) in
        if x < 0 then ok := false;
        x
      in
      let b0 = v 0 and b1 = v 1 and b2 = v 2 and b3 = v 3 in
      Bytes.set buf (j*3)   (Char.chr ((b0 lsl 2) lor (b1 lsr 4)));
      Bytes.set buf (j*3+1) (Char.chr (((b1 land 15) lsl 4) lor (b2 lsr 2)));
      Bytes.set buf (j*3+2) (Char.chr (((b2 land 3) lsl 6) lor b3))
    done;
    if not !ok then None
    else begin
      (* trim trailing bytes from padding *)
      let trail = String.fold_right (fun c n -> if c = '=' then n+1 else n) s 0 in
      let real_n = out_n - (if trail > 0 then 3 - (3 - trail mod 3) mod 3 else 0) in
      if real_n <> 32 then None
      else Some (Bytes.sub buf 0 32)
    end
  end

(** [sig_to_base64 sig] — base64-encode a 64-byte signature. *)
let sig_to_base64 = pk_to_base64

(** [pk_to_hex pk] — hex-encode a 32-byte public key (64 hex chars). *)
let pk_to_hex (pk : bytes) : string =
  let b = Buffer.create 64 in
  Bytes.iter (fun c -> Buffer.add_string b (Printf.sprintf "%02x" (Char.code c))) pk;
  Buffer.contents b
