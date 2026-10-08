(** forge cluster — operator keys, node certificates and revocations for a
    March cluster in certificate mode (distributed-deploys build step 11a).

    [forge cluster keygen]  the OPERATOR keypair (operator.key / operator.pub)
    [forge cluster cert]    a node keypair and its certificate, signed by the
                            operator key (<node>.key / <node>.cert)
    [forge cluster revoke]  a signed revocation token to hand to a node
                            (ClusterNode.revoke or MARCH_CLUSTER_REVOCATIONS)

    With [--deliver HOST:PORT,...], [cert] and [revoke] also hand what they
    signed to a running cluster's control plane (distributed-deploys step
    12b): a release carrying the certificate or revocation as an item,
    signed by the deploy key and sent to the control API the way
    [forge deploy] sends its releases ({!deliver}). Issuance stays here, with
    the operator (D39); each node checks the release's signature and the
    item's own operator signature before it takes the certificate
    ([ClusterNode.replace_cert], live, keeping the node's key) or the
    revocation ([ClusterNode.revoke], which gossips it on).

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

let control_roles ~roles ~agent ~candidate =
  if not (agent || candidate) then roles
  else
    let add roles role = if List.mem role roles then roles else roles @ [role] in
    let roles = add (split_list roles) "Ctl.Agent:initiate" in
    let roles = if candidate then add roles "Ctl.Control:offer" else roles in
    String.concat "," roles

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
    ~node_key ~out_dir ?(deliver : (string -> (string, string) result) option) () : (string, string) result =
  let roles = split_list roles and flags = split_list flags in
  let bad_role = List.find_map (fun r -> match check_role r with Error e -> Some e | Ok () -> None) roles in
  match bad_role with
  | Some e -> Error e
  | None when name = "" || String.contains name '/' -> Error "the node name must be non-empty and contain no '/'"
  | None when Option.is_some deliver && node_key = None ->
    Error "--deliver renews a running node's certificate for the key it already holds: pass --node-key <node>.key \
           (the control plane never carries a secret key)"
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
        (* "<issued, unix ms>-<random hex>": the issue time orders a node's
           certificates (NodeCert.supersedes), so a node refuses one issued
           before the certificate it holds, a replayed superseded one. *)
        let serial = Printf.sprintf "%d-%s" (int_of_float (Unix.gettimeofday () *. 1000.)) (to_hex (random_bytes 16)) in
        let body = cert_body ~node ~roles ~flags ~not_after ~issuer
            ~pubkey_hex:(to_hex (pubkey_of node_sk)) ~serial in
        let signed = mp (Arr [ Bin body; Bin (sign op_sk body) ]) in
        let cert_path = Filename.concat out_dir (name ^ ".cert") in
        let key_path = Filename.concat out_dir (name ^ ".key") in
        write_file cert_path (b64 signed ^ "\n");
        if node_key = None then write_file ~perm:0o600 key_path (to_hex node_sk ^ "\n");
        let wrote = Printf.sprintf "wrote %s%s\nnode %s\nserial %s\nnot_after %d (unix seconds)"
            cert_path (if node_key = None then " and " ^ key_path else "")
            node serial not_after in
        match deliver with
        | None -> Ok wrote
        | Some f ->
          print_endline wrote;
          f (b64 signed)

(** [forge cluster revoke]: a signed revocation of one certificate (by
    serial) or of every certificate of a node (by node). Printed, base64. *)
let run_revoke ~serial ~node ~trust_domain ~pool ~operator_key ?(deliver : (string -> (string, string) result) option) ()
  : (string, string) result =
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
      let token = b64 (mp (Arr [ Bin body; Bin (sign op_sk body) ])) in
      match deliver with
      | None -> Ok token
      | Some f -> print_endline token; f token

(* ------------------------------------------------- delivery (step 12b) *)

let ( let* ) = Result.bind

(** The deploy signing key: [path] holding it as hex (128 digits) or base64,
    else forge's own ([forge hot-reload keygen]). *)
let load_deploy_key (path : string option) : (bytes, string) result =
  match path with
  | None -> Cmd_hot_reload.read_sk_raw ()
  | Some p ->
    match (try Ok (String.trim (read_file p)) with Sys_error e -> Error e) with
    | Error e -> Error (Printf.sprintf "cannot read the deploy key %s: %s" p e)
    | Ok text ->
      match of_hex text with
      | Ok sk when String.length sk = 64 -> Ok (Bytes.of_string sk)
      | _ ->
        match Cmd_hot_reload.b64_decode_raw text with
        | Some b when Bytes.length b >= 64 -> Ok (Bytes.sub b 0 64)
        | _ -> Error (Printf.sprintf "%s: expected a 64-byte ed25519 deploy key, as hex or base64" p)

(** The release carrying [items] after [head]: one [do:certs] step over every
    pool. Its [topology] is ["-"]: it changes no topology, and the executor
    reads the field only for a topology step. *)
let cert_release ~(sk : bytes) ~(env : string) ~(head : Cluster_deploy.status) (items : Control_release.items)
  : Control_release.t =
  let open Control_release in
  let seq = next_seq ~now_ms:(int_of_float (Unix.gettimeofday () *. 1000.)) ~head:head.Cluster_deploy.head_seq in
  sign_with ~sk items
    { seq; parent = (if head.Cluster_deploy.head_digest = "-" then no_parent else head.Cluster_deploy.head_digest);
      env; topology = "-"; builds = [];
      steps = [ { id = 1; pools = [ "*" ]; hosts = All; action = Certs; gate = No_gate; batch = 0 } ];
      lines = []; drain = None; signature = "" }

(** Deliver [items] through the control plane at [endpoints]: the leader's
    status, a release over its head, RELEASE, then follow it until every node
    reports the certificates and revocations it carries (or it halts: a node
    refused an item, and STATUS says which and why). Refused while the head
    release is still rolling out, which the new one would supersede. Nothing
    here checks a certificate against its target node: [run_cert] writes them
    consistent, and the node checks every item itself. *)
let deliver ~(endpoints : Cluster_deploy.endpoint list) ~(sk : bytes) ~(env : string) ?(follow_s = 120.)
    (items : Control_release.items) : (string, string) result =
  if endpoints = [] then Error "--deliver needs the control API of at least one control candidate (host:port,...)"
  else
    let* head = Cluster_deploy.status endpoints in
    if head.Cluster_deploy.state = "running" || head.Cluster_deploy.state = "behind" then
      Error (Printf.sprintf "release %d is still rolling out (%s); deliver once it completes or halts, \
                             since a new release supersedes it" head.Cluster_deploy.head_seq head.Cluster_deploy.decision)
    else begin
      let known = List.map (fun n -> n.Cluster_deploy.n_name) head.Cluster_deploy.nodes in
      List.iter (fun (node, _) ->
          if not (List.mem node known) then
            Printf.printf "warning: %s does not report to the control plane; this release will not reach it\n%!" node)
        items.Control_release.certs;
      let r = cert_release ~sk ~env ~head items in
      let body = Control_release.serialize_with items r in
      (match Sys.getenv_opt "FORGE_RELEASE_OUT" with
       | Some f when f <> "" -> write_file f body
       | _ -> ());
      let* resp = Cluster_deploy.send_release endpoints ~body in
      Printf.printf "release accepted: %s\n%!" resp;
      Cluster_deploy.follow endpoints ~seq:r.Control_release.seq ~timeout_s:follow_s
    end

(** [--deliver] for [forge cluster cert] and [revoke]: the endpoints, the
    deploy key, the environment. *)
type delivery = { d_endpoints : string; d_deploy_key : string option; d_env : string }

let endpoints_of (s : string) : (Cluster_deploy.endpoint list, string) result =
  let ws = split_list s in
  let eps = List.filter_map Cluster_deploy.endpoint_of_string ws in
  if List.length eps <> List.length ws || eps = [] then
    Error (Printf.sprintf "--deliver %S: expected host:port[,host:port...] (a control candidate's control API)" s)
  else Ok eps

let deliver_items (d : delivery) (items : Control_release.items) : (string, string) result =
  let* endpoints = endpoints_of d.d_endpoints in
  let* sk = load_deploy_key d.d_deploy_key in
  deliver ~endpoints ~sk ~env:d.d_env items
