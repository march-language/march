(** forge cluster — operator keys, node certificates and revocations for a
    March cluster in certificate mode (distributed-deploys build step 11a).

    [forge cluster keygen]  the OPERATOR keypair (operator.key / operator.pub)
    [forge cluster cert]    a node keypair and its certificate, signed by the
                            operator key (<node>.key / <node>.cert)
    [forge cluster revoke]  a signed revocation token to hand to a node
                            (ClusterNode.revoke or MARCH_CLUSTER_REVOCATIONS)

    The byte formats are stdlib/node_cert.march's and must stay byte-identical
    to it: a certificate body is the canonical MessagePack array
    ["march-node-cert-v1", node, [roles], [flags], not_after, issuer,
    pubkey_hex, serial] in Msgpack.encode's smallest-form encoding, and the
    signed form is [Bin(body), Bin(signature)], base64. The operator key is
    deliberately NOT forge hot-reload's deploy signing key (plan section 3:
    the deploy keys and the certificate authority are separate). *)

module E = March_ed25519.Ed25519

(* ---------------------------------------------------------------- msgpack *)

(* The subset of stdlib/msgpack.march's encoder the certificate needs, with
   the same header choices (smallest form first). Strings are ASCII here. *)
type mp = Str of string | Int of int | Arr of mp list | Bin of string

let be n v =
  String.init n (fun i -> Char.chr ((v lsr (8 * (n - 1 - i))) land 0xff))

let rec mp_encode (b : Buffer.t) (v : mp) =
  match v with
  | Str s ->
    let n = String.length s in
    if n <= 31 then Buffer.add_char b (Char.chr (0xa0 lor n))
    else if n <= 255 then (Buffer.add_char b '\xd9'; Buffer.add_string b (be 1 n))
    else if n <= 65535 then (Buffer.add_char b '\xda'; Buffer.add_string b (be 2 n))
    else (Buffer.add_char b '\xdb'; Buffer.add_string b (be 4 n));
    Buffer.add_string b s
  | Bin s ->
    let n = String.length s in
    if n <= 255 then (Buffer.add_char b '\xc4'; Buffer.add_string b (be 1 n))
    else if n <= 65535 then (Buffer.add_char b '\xc5'; Buffer.add_string b (be 2 n))
    else (Buffer.add_char b '\xc6'; Buffer.add_string b (be 4 n));
    Buffer.add_string b s
  | Arr xs ->
    let n = List.length xs in
    if n <= 15 then Buffer.add_char b (Char.chr (0x90 lor n))
    else if n <= 65535 then (Buffer.add_char b '\xdc'; Buffer.add_string b (be 2 n))
    else (Buffer.add_char b '\xdd'; Buffer.add_string b (be 4 n));
    List.iter (mp_encode b) xs
  | Int n ->
    if n >= 0 && n <= 127 then Buffer.add_char b (Char.chr n)
    else if n >= -32 && n < 0 then Buffer.add_char b (Char.chr (n land 0xff))
    else if n >= -128 && n <= -33 then (Buffer.add_char b '\xd0'; Buffer.add_string b (be 1 n))
    else if n >= 128 && n <= 255 then (Buffer.add_char b '\xcc'; Buffer.add_string b (be 1 n))
    else if n >= -32768 && n <= -129 then (Buffer.add_char b '\xd1'; Buffer.add_string b (be 2 n))
    else if n >= 256 && n <= 65535 then (Buffer.add_char b '\xcd'; Buffer.add_string b (be 2 n))
    else if n >= -2147483648 && n <= -32769 then (Buffer.add_char b '\xd2'; Buffer.add_string b (be 4 n))
    else if n >= 65536 && n <= 4294967295 then (Buffer.add_char b '\xce'; Buffer.add_string b (be 4 n))
    else if n >= 0 then (Buffer.add_char b '\xcf'; Buffer.add_string b (be 8 n))
    else (Buffer.add_char b '\xd3'; Buffer.add_string b (be 8 n))

let mp (v : mp) : string =
  let b = Buffer.create 128 in mp_encode b v; Buffer.contents b

(* ------------------------------------------------------------------ bytes *)

let to_hex (s : string) : string =
  String.concat "" (List.init (String.length s) (fun i -> Printf.sprintf "%02x" (Char.code s.[i])))

let of_hex (h : string) : (string, string) result =
  let h = String.trim h in
  let n = String.length h in
  if n mod 2 <> 0 then Error "odd-length hex"
  else
    try Ok (String.init (n / 2) (fun i -> Char.chr (int_of_string ("0x" ^ String.sub h (2 * i) 2))))
    with _ -> Error "not hex"

let b64 (s : string) : string = E.pk_to_base64 (Bytes.of_string s)

let random_bytes n =
  let ic = open_in_bin "/dev/urandom" in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () -> really_input_string ic n)

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let write_file ?(perm = 0o644) path contents =
  let oc = open_out_gen [Open_wronly; Open_creat; Open_trunc; Open_binary] perm path in
  Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc contents)

(* A 64-byte secret key from a file holding its hex (what keygen/cert write). *)
let load_secret_key path : (string, string) result =
  match (try Ok (read_file path) with Sys_error e -> Error e) with
  | Error e -> Error (Printf.sprintf "cannot read %s: %s" path e)
  | Ok text ->
    match of_hex text with
    | Error e -> Error (Printf.sprintf "%s: %s" path e)
    | Ok sk when String.length sk = 64 -> Ok sk
    | Ok sk -> Error (Printf.sprintf "%s: expected a 64-byte ed25519 secret key, got %d bytes"
                        path (String.length sk))

let pubkey_of sk = String.sub sk 32 32

let sign sk msg = Bytes.to_string (E.sign (Bytes.of_string msg) (Bytes.of_string sk))

(* ------------------------------------------------------------------- URIs *)

let node_uri ~trust_domain ~pool name =
  Printf.sprintf "spiffe://%s/pool/%s/node/%s" trust_domain pool name

let issuer_uri ~trust_domain operator_pub =
  Printf.sprintf "spiffe://%s/operator/%s" trust_domain (String.sub (to_hex operator_pub) 0 16)

let split_list s =
  String.split_on_char ',' s |> List.map String.trim |> List.filter (fun x -> x <> "")

(* A role is "Proto.Role:offer" or "Proto.Role:initiate". *)
let check_role r =
  match String.rindex_opt r ':' with
  | Some i ->
    let verb = String.sub r (i + 1) (String.length r - i - 1) in
    if verb = "offer" || verb = "initiate" then Ok ()
    else Error (Printf.sprintf "role %S: expected Proto.Role:offer or Proto.Role:initiate" r)
  | None -> Error (Printf.sprintf "role %S: expected Proto.Role:offer or Proto.Role:initiate" r)

(* --------------------------------------------------------------- commands *)

(** [forge cluster keygen]: operator.key (hex secret key, 0600) and
    operator.pub (hex public key) in [out_dir]. Refuses to overwrite a key. *)
let run_keygen ~out_dir ~force () : (string, string) result =
  let key_path = Filename.concat out_dir "operator.key" in
  let pub_path = Filename.concat out_dir "operator.pub" in
  if Sys.file_exists key_path && not force then
    Error (Printf.sprintf "%s exists; pass --force to replace it (every certificate it signed stops verifying)" key_path)
  else begin
    let sk = Bytes.to_string (E.seed_keypair (Bytes.of_string (random_bytes 32))) in
    let pk_hex = to_hex (pubkey_of sk) in
    write_file ~perm:0o600 key_path (to_hex sk ^ "\n");
    write_file pub_path (pk_hex ^ "\n");
    Ok (Printf.sprintf "wrote %s and %s\nMARCH_CLUSTER_OPERATOR_PUBKEY=%s" key_path pub_path pk_hex)
  end

(** The canonical certificate body (see the module comment). *)
let cert_body ~node ~roles ~flags ~not_after ~issuer ~pubkey_hex ~serial =
  mp (Arr [ Str "march-node-cert-v1"; Str node; Arr (List.map (fun r -> Str r) roles);
            Arr (List.map (fun f -> Str f) flags); Int not_after; Str issuer;
            Str pubkey_hex; Str serial ])

(** [forge cluster cert NODE]: a node keypair (NODE.key, unless [node_key]
    names an existing one to renew) and NODE.cert, signed by [operator_key]. *)
let run_cert ~name ~roles ~flags ~days ~seconds ~trust_domain ~pool ~operator_key
    ~node_key ~out_dir () : (string, string) result =
  let roles = split_list roles and flags = split_list flags in
  let bad_role = List.find_map (fun r -> match check_role r with Error e -> Some e | Ok () -> None) roles in
  match bad_role with
  | Some e -> Error e
  | None when name = "" || String.contains name '/' -> Error "the node name must be non-empty and contain no '/'"
  | None ->
    match load_secret_key operator_key with
    | Error e -> Error e
    | Ok op_sk ->
      let node_sk_r = match node_key with
        | Some p -> load_secret_key p
        | None -> Ok (Bytes.to_string (E.seed_keypair (Bytes.of_string (random_bytes 32)))) in
      match node_sk_r with
      | Error e -> Error e
      | Ok node_sk ->
        let lifetime = match seconds with Some s -> s | None -> days * 86400 in
        let not_after = int_of_float (Unix.time ()) + lifetime in
        let node = node_uri ~trust_domain ~pool name in
        let issuer = issuer_uri ~trust_domain (pubkey_of op_sk) in
        let serial = to_hex (random_bytes 16) in
        let body = cert_body ~node ~roles ~flags ~not_after ~issuer
            ~pubkey_hex:(to_hex (pubkey_of node_sk)) ~serial in
        let signed = mp (Arr [ Bin body; Bin (sign op_sk body) ]) in
        let cert_path = Filename.concat out_dir (name ^ ".cert") in
        let key_path = Filename.concat out_dir (name ^ ".key") in
        write_file cert_path (b64 signed ^ "\n");
        if node_key = None then write_file ~perm:0o600 key_path (to_hex node_sk ^ "\n");
        Ok (Printf.sprintf "wrote %s%s\nnode %s\nserial %s\nnot_after %d (unix seconds)"
              cert_path (if node_key = None then " and " ^ key_path else "")
              node serial not_after)

(** [forge cluster revoke]: a signed revocation of one certificate (by
    serial) or of every certificate of a node (by node). Printed, base64. *)
let run_revoke ~serial ~node ~trust_domain ~pool ~operator_key () : (string, string) result =
  let node_uri_s = match node with
    | "" -> ""
    | n when String.length n > 9 && String.sub n 0 9 = "spiffe://" -> n
    | n -> node_uri ~trust_domain ~pool n in
  if serial = "" && node_uri_s = "" then Error "give --serial or --node"
  else
    match load_secret_key operator_key with
    | Error e -> Error e
    | Ok op_sk ->
      let body = mp (Arr [ Str "march-revocation-v1"; Str node_uri_s; Str serial;
                           Int (int_of_float (Unix.time ())) ]) in
      Ok (b64 (mp (Arr [ Bin body; Bin (sign op_sk body) ])))
