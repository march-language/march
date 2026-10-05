(** Releases for the in-cluster control plane (distributed-deploys build step
    12a; design section 4 of specs/plans/2026-09-28-dd-step12-control-plane-design.md).

    A release is one signed document: what to deploy, in what order, with
    which gates, and the operator-signed request lines a node relays to its
    own reload server for each step. forge writes and signs it here, where the
    deploy key lives (D37: the control plane holds no keys); the leader stores
    it and orders the steps, and each node verifies every line itself.

    The text form is [stdlib/control.march]'s ([Control.signed_text],
    [Control.serialize], [Control.parse]): [signed_text] here is the same bytes,
    so a release forge signs verifies on the leader and parses back.

    {1 Where the signed lines come from}

    A hot step's lines are exactly what [forge deploy hot] would send one node
    (BEGIN_BATCH, one ACTIVATE per changed function, COMMIT_BATCH), and they are
    produced by the same code, [Cmd_deploy_hot.run], against a recorder: a
    fake reload server ([record_hot]) that answers the queries from the
    manifest forge last deployed and writes down the signed lines instead of
    applying them. Every gate, capability check and migration decision
    [forge deploy hot] makes is therefore made here, before anything is sent.
    A topology step's line is the signed TOPOLOGY verb; its body travels as an
    artifact under the topology's digest.

    {1 Certificate and revocation items (step 12b)}

    A release may also carry operator-signed node certificates
    ([cert <node> <text>]) and revocations ([revoke <token>]), delivered by a
    [do:certs] step: each node takes the certificate for itself through
    [ClusterNode.replace_cert] and every revocation through
    [ClusterNode.revoke]. Issuance stays offline with the operator (D39:
    [forge cluster cert] signs them; the control plane holds no issuer key),
    and the node checks both signatures, the deploy key's over the release
    and the operator's over the item (D37). Items live beside the release
    ([items]), not in [t], and [signed_text_with] places them where
    [Control.signed_text] does: after the signed lines, before the drain. *)

let ( let* ) = Result.bind

(* ── The model ─────────────────────────────────────────────────────────── *)

type hosts = Canary of int | Rest | All

type action = Activate of string | Topology | Drain | Certs

type gate = No_gate | Healthy of int  (** the window, in ms *)

type step = { id : int; pools : string list; hosts : hosts; action : action; gate : gate; batch : int }

type build = { name : string; base : string; manifest : string }

type drain = { epoch : int; soft_ms : int; hard_ms : int }

type t = {
  seq : int;
  parent : string;                (** the parent's digest, or ["none"] *)
  env : string;
  topology : string;              (** blake3 of the topology digest text *)
  builds : build list;
  steps : step list;
  lines : (int * string) list;    (** (step, signed request line) *)
  drain : drain option;
  signature : string;             (** hex; "" until signed *)
}

let no_parent = "none"

let show_duration ms =
  if ms > 0 && ms mod 1000 = 0 then Printf.sprintf "%ds" (ms / 1000) else Printf.sprintf "%dms" ms

let show_hosts = function
  | Canary n -> Printf.sprintf "canary(%d)" n
  | Rest -> "rest"
  | All -> "all"

let show_action = function
  | Activate b -> Printf.sprintf "activate(%s)" b
  | Topology -> "topology"
  | Drain -> "drain"
  | Certs -> "certs"

let show_gate = function
  | No_gate -> "none"
  | Healthy ms -> Printf.sprintf "healthy(%s)" (show_duration ms)

let show_step s =
  let base =
    Printf.sprintf "step %d pools:%s hosts:%s do:%s gate:%s" s.id (String.concat "," s.pools) (show_hosts s.hosts)
      (show_action s.action) (show_gate s.gate)
  in
  if s.batch > 0 then base ^ Printf.sprintf " batch:%d" s.batch else base

(** A release's certificate items: (node, certificate text form) pairs and
    revocation tokens (see the module comment). *)
type items = { certs : (string * string) list; revokes : string list }

let no_items = { certs = []; revokes = [] }

(** The text the signature covers, byte for byte [Control.signed_text]. *)
let signed_text_with (items : items) (r : t) : string =
  let head =
    [ "release v1"; Printf.sprintf "seq %d" r.seq; "parent " ^ r.parent; "env " ^ r.env; "topology " ^ r.topology ]
  in
  let builds = List.map (fun b -> Printf.sprintf "build %s base:%s manifest:%s" b.name b.base b.manifest) r.builds in
  let steps = List.map show_step r.steps in
  let lines = List.map (fun (step, text) -> Printf.sprintf "line %d %s" step text) r.lines in
  let certs = List.map (fun (node, text) -> Printf.sprintf "cert %s %s" node text) items.certs in
  let revokes = List.map (fun tok -> "revoke " ^ tok) items.revokes in
  let drain =
    match r.drain with
    | Some d -> [ Printf.sprintf "drain epoch<=%d soft:%d hard:%d" d.epoch d.soft_ms d.hard_ms ]
    | None -> []
  in
  String.concat "\n" (head @ builds @ steps @ lines @ certs @ revokes @ drain) ^ "\n"

let signed_text (r : t) : string = signed_text_with no_items r

let serialize_with (items : items) (r : t) : string =
  signed_text_with items r ^ "sig " ^ (if r.signature = "" then "-" else r.signature) ^ "\n"

let serialize (r : t) : string = serialize_with no_items r

(** The release's content address, [Control.digest]: sha256 (hex) of the signed text. *)
let digest_with (items : items) (r : t) : string = Digestif.SHA256.(to_hex (digest_string (signed_text_with items r)))

let digest (r : t) : string = digest_with no_items r

let hex_of_bytes b = String.concat "" (List.init (Bytes.length b) (fun i -> Printf.sprintf "%02x" (Char.code (Bytes.get b i))))

let sign_with ~(sk : bytes) (items : items) (r : t) : t =
  { r with signature = hex_of_bytes (March_ed25519.Ed25519.sign_str (signed_text_with items r) sk) }

let sign ~(sk : bytes) (r : t) : t = sign_with ~sk no_items r

(* ── The signed lines of a hot step (the recorder) ─────────────────────── *)

(** A fake reload server on [path]: answers what [Cmd_deploy_hot.run] asks
    (identity, versions, slots, epoch, the CAS) from [old] (the manifest of
    what runs) and [manifest] (the patch), and records the signed lines it is
    sent to [record] instead of applying them. It serves one connection and
    exits. Runs in the forked child. *)
let serve_recorder ~listener ~(old : Cmd_deploy_hot.manifest) ~(manifest : Cmd_deploy_hot.manifest) ~(key_hex : string)
    ~(seq : int) ~record : unit =
  let dbg m = if Sys.getenv_opt "FORGE_DEBUG_RECORDER" <> None then (prerr_endline ("recorder: " ^ m)) in
  dbg "waiting";
  let fd, _ = Unix.accept listener in
  dbg "accepted";
  let conn = Cmd_deploy_hot.conn_of_fd fd in
  let out = open_out_bin record in
  let reply s = Cmd_deploy_hot.send_line conn s in
  let staged = ref 0 in
  let rec loop () =
    match Cmd_deploy_hot.recv_line conn with
    | exception Failure _ -> ()
    | line ->
      dbg line;
      let words = String.split_on_char ' ' line in
      (match words with
       | [ "PING" ] -> reply "PONG"
       | [ "RELEASE_HEAD" ] -> reply (Printf.sprintf "HEAD %d -" (seq - 1))
       | [ "HCR_INFO" ] ->
         reply (Printf.sprintf "HCR_INFO target:%s abi:%s prefix:%s key:%s"
                  (Option.value ~default:"native" manifest.target)
                  (Option.value ~default:"-" manifest.hcr_abi)
                  (Option.value ~default:"" manifest.module_prefix) key_hex)
       | [ "VERSIONS" ] ->
         List.iter (fun (f : Cmd_deploy_hot.fn_manifest) ->
             reply (Printf.sprintf "VERSION %s baseline %s" f.fn_name f.fn_impl_hash))
           old.functions;
         reply "END"
       | [ "ABI_QUERY" ] ->
         List.iteri (fun i (f : Cmd_deploy_hot.fn_manifest) ->
             reply (Printf.sprintf "SLOT %d %s %s %s" (i + 1) f.fn_name f.fn_impl_hash
                      (if f.fn_sig_hash = "" then "(none)" else f.fn_sig_hash)))
           old.functions;
         reply "END"
       | [ "GET_EPOCH" ] -> reply "EPOCH 1"
       | "CAS_CHECK" :: _ -> reply "PRESENT"   (* the hash, and the bytes' digest *)
       | [ "BEGIN_BATCH" ] -> staged := 0; output_string out "BEGIN_BATCH\n"; flush out; reply "OK"
       | [ "COMMIT_BATCH" ] ->
         output_string out "COMMIT_BATCH\n"; flush out;
         reply (Printf.sprintf "OK %d" !staged)
       | [ "ROLLBACK_BATCH" ] -> output_string out "ROLLBACK_BATCH\n"; flush out; reply "OK"
       | "SEQ" :: _ | "ACTIVATE3" :: _ | "ACTIVATE4" :: _ | "ACTIVATE5" :: _ | "ACTIVATE6" :: _
       | "ACTIVATE7" :: _ ->
         incr staged;
         output_string out (line ^ "\n"); flush out;
         reply "OK recorded"
       | _ -> reply "ERR unknown_command");
      loop ()
  in
  (try loop () with _ -> ());
  close_out out;
  (try Unix.close fd with _ -> ())

(** The signed lines that hot-deploy [manifest] (built at [so_path]) over what
    [old_manifest_path] says runs: BEGIN_BATCH, one ACTIVATE per changed
    function (each wrapped in the release [seq]), COMMIT_BATCH. Everything
    [forge deploy hot] would check on a node it checks here, from the
    baseline manifest; an error names what it refused. *)
let record_hot ~(dir : string) ~(seq : int) ~(sk : bytes) ~(pubkey : string) ~(old_manifest_path : string)
    ~(manifest : Cmd_deploy_hot.manifest) ~(so_path : string) ?(old_schemas_path = "") ?(new_schemas_path = "")
    ?(entry_path = "") ?(grant_caps = []) () : (string list, string) result =
  let* old =
    if old_manifest_path <> "" && Sys.file_exists old_manifest_path then Cmd_deploy_hot.parse_manifest old_manifest_path
    else Error "there is no record of what the nodes run (no baseline manifest): the first deploy of a build goes through the process backend"
  in
  (try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let sock = Filename.concat dir "recorder.sock" and record = Filename.concat dir "recorded.txt" in
  (try Sys.remove sock with Sys_error _ -> ());
  (try Sys.remove record with Sys_error _ -> ());
  let listener = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  Unix.bind listener (Unix.ADDR_UNIX sock);
  Unix.listen listener 1;
  (* The key the recorder reports is the deploy key's public half as hex. *)
  let key_hex =
    match March_ed25519.Ed25519.pk_of_base64 pubkey with
    | Some pk -> hex_of_bytes pk
    | None -> ""
  in
  flush_all ();
  match Unix.fork () with
  | 0 ->
    (try serve_recorder ~listener ~old ~manifest ~key_hex ~seq ~record with _ -> ());
    Unix._exit 0
  | pid ->
    Unix.close listener;
    Cmd_deploy_hot.release_seq := Some seq;
    let r =
      try
        Cmd_deploy_hot.run ~tunnel:false ~ssh_host:"release" ~remote_socket:sock ~signing_pubkey:pubkey ~sk ~manifest
          ~so_path ~old_schemas_path ~new_schemas_path ~entry_path ~old_manifest_path ~provided_epoch:1 ~grant_caps ()
      with Failure m -> Error m | Unix.Unix_error (e, _, _) -> Error (Unix.error_message e)
    in
    ignore (Unix.waitpid [] pid);
    (try Sys.remove sock with Sys_error _ -> ());
    (match r with
     | Error m -> Error m
     | Ok 0 -> Error "nothing to activate: the patch changes no function the nodes run"
     | Ok _ ->
       let lines =
         String.split_on_char '\n' (In_channel.with_open_bin record In_channel.input_all)
         |> List.filter (fun l -> l <> "")
       in
       if List.mem "ROLLBACK_BATCH" lines then Error "the deploy rolled its own batch back"
       else Ok lines)

(** The signed TOPOLOGY line for [body], as the release's [seq]: the verb, its
    signature over the body's blake3, and the release wrapper. The body is not
    in the line: the release names it by digest and a node reads it from its
    CAS. Returns (line, digest). *)
let topology_line ~(seq : int) ~(sk : bytes) ~(body : string) : string * string =
  let (cmd, digest) = Cmd_deploy_hot.topology_command ~sk ~body in
  (Cmd_deploy_hot.wrap_release ~seq ~id:(Lazy.force Cmd_deploy_hot.release_id) ~sk cmd, digest)

(** The release [seq] for [now_ms] and the newest seq [head] anyone holds:
    one more than the head, and never behind the clock, so releases from one
    operator only grow. *)
let next_seq ~(now_ms : int) ~(head : int) : int = max now_ms (head + 1)
