(** A local hot deploy for the two-node harness (distributed-deploys build
    step 9, test/two_node/protocol_evolve): what `forge deploy hot` does over
    its ssh tunnel, against a reload socket on this machine
    ([Cmd_deploy_hot.run ~tunnel:false], the path `forge test --upgrade-from`
    uses), so a scenario can deploy one node at a time in the order it
    chooses. Not a user-facing tool.

      hcr_deploy keygen <dir>                 writes <dir>/pk (base64), <dir>/sk (hex)
      hcr_deploy deploy <socket> <dir> <so> [<old .schemas.json> <old .hcr_manifest>]
                                              GRANT_CAPS=<cap,...>: the operator's
                                              `--grant-cap`s (authorize a widening)
      hcr_deploy policy <project root> <pool> <.hcr_manifest>
                                              the node policy `forge host init` writes
                                              for <pool> (Host_init.policy_text): its
                                              caps plus its runner's, one per line
      hcr_deploy counters <socket> <key>...   prints key=value from PINS
      hcr_deploy release <dir> <host:port,...> <build> <pool,...> <so> <old .hcr_manifest> [<old .schemas.json>]
                                              a hot release through the control plane
                                              (`forge deploy` on the cluster backend, over
                                              Cluster_deploy): CANARY=<n> CANARY_MS RESTS_MS
                                              TOPOLOGY=<digest file to push> FOLLOW_S
      hcr_deploy certs <dir> <host:port,...> <item>...
                                              a release of certificate items (step 12b) through
                                              the control plane, as `forge cluster cert/revoke
                                              --deliver` sends it, but with the items as given:
                                              cert:<node>:<cert file> or revoke:<token file>,
                                              unchecked (to send what forge would refuse to write)
      hcr_deploy status <host:port,...>       the leader's view of the newest release
      hcr_deploy release-stale <host:port,...> <seq>
                                              send a one-step release with <seq> and no parent,
                                              signed with forge's deploy key ($HOME/.march):
                                              the leader's compare-and-set refuses it once it
                                              holds a newer one; prints the answer
      hcr_deploy probe <dir> <host:port>      the step-12 security review's write attacks on a
                                              control API, each from a plain socket with no
                                              cluster credentials (the release staged is signed
                                              with <dir>'s key); one "<attack>: <answer>" line
                                              each, and "staged_hash: <h>" for the upload that
                                              is allowed (specs/reviews/dd12/api_probe.py)
      hcr_deploy probe-quota <dir> <host:port> <size>
                                              stage two signed releases on one connection, then
                                              put an artifact of <size> bytes under each:
                                              "quota_first: .." and "quota_second: .."
      hcr_deploy probe-stale <dir> <host:port>
                                              STAGE a signed release with seq 1: "stage_stale: .."
      hcr_deploy probe-conns <host:port> <n>  open <n> silent connections: "busy: <k>" (how many
                                              were answered ERR busy), then after IDLE_WAIT_S
                                              (default 5) "idle_closed: <k>" (how many the
                                              server closed)
      hcr_deploy api <host:port> <line>       one request to a control API, answer to stdout
      hcr_deploy reload <socket> <line>       one request to a reload socket, answer to stdout
                                              (lines up to END, or the first line)
      hcr_deploy api-put <host:port> <hash> <file> [<blake3>]
                                              CAS_PUT <file>'s bytes under <hash> through a
                                              control API (with so_blake3:<blake3> when given),
                                              as anyone who reaches the port can; prints the verdict
                                              (the API now answers ERR not_staged unless a
                                              release staged on the connection names <hash>)
      hcr_deploy reload-put <socket> <hash> <file> [<blake3>]
                                              the same CAS_PUT through a reload socket (as a
                                              local user who can open it)
      hcr_deploy digest <file>                the blake3 of <file> (what ACTIVATE7 signs)

    Exit 0 on success; a failed deploy prints why on stderr and exits 1. *)

let read path = In_channel.with_open_bin path In_channel.input_all
let write path s = Out_channel.with_open_bin path (fun oc -> output_string oc s)

let hex_of_bytes b = String.concat "" (List.init (Bytes.length b) (fun i -> Printf.sprintf "%02x" (Char.code (Bytes.get b i))))

let bytes_of_hex h =
  let h = String.trim h in
  Bytes.init (String.length h / 2) (fun i -> Char.chr (int_of_string ("0x" ^ String.sub h (2 * i) 2)))


(* ── the probes: a plain TCP client, no cluster credentials ─────────────── *)

let probe_connect ep =
  match Option.bind (March_forge.Cluster_deploy.endpoint_of_string ep)
          (fun e -> Result.to_option (March_forge.Cluster_deploy.connect e)) with
  | Some c -> Unix.setsockopt_float c.March_forge.Cmd_deploy_hot.fd Unix.SO_RCVTIMEO 15.; c
  | None -> prerr_endline ("hcr_deploy: cannot connect to " ^ ep); exit 1

let probe_send c s = March_forge.Cmd_deploy_hot.send_binary c (Bytes.of_string s) 0 (String.length s)

let probe_line c =
  try March_forge.Cmd_deploy_hot.recv_line c with
  | Failure _ -> "(closed)"
  | Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> "(timeout)"
  | Unix.Unix_error (e, _, _) -> "(" ^ Unix.error_message e ^ ")"

(* Everything the server sends until it closes (or goes quiet), as text. *)
let probe_drain c =
  let b = Buffer.create 256 in
  Buffer.add_buffer b c.March_forge.Cmd_deploy_hot.buf;
  let tmp = Bytes.create 65536 in
  let rec go () =
    match Unix.read c.March_forge.Cmd_deploy_hot.fd tmp 0 65536 with
    | 0 -> ()
    | n -> Buffer.add_subbytes b tmp 0 n; go ()
    | exception Unix.Unix_error _ -> ()
  in
  go (); Buffer.contents b

let contains s sub =
  let n = String.length s and m = String.length sub in
  let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
  go 0

let random_hash () =
  Random.self_init ();
  String.concat "" (List.init 32 (fun _ -> Printf.sprintf "%02x" (Random.int 256)))

let probe_release ~sk ~seq ~topology =
  let open March_forge.Control_release in
  serialize (sign ~sk { seq; parent = no_parent; env = "test"; topology; builds = [];
                        steps = [ { id = 1; pools = [ "*" ]; hosts = All; action = Topology; gate = No_gate; batch = 0 } ];
                        lines = []; drain = None; signature = "" })

let now_ms () = int_of_float (Unix.gettimeofday () *. 1000.)

(* A write the way an attacker sends it: the line and the body at once,
   without waiting for READY or AUTH. The verdict: "OK" when the server took
   it, "refused (<why>)" otherwise. *)
let probe_blind ep line body =
  let c = probe_connect ep in
  probe_send c (line ^ "\n" ^ body);
  Unix.shutdown c.March_forge.Cmd_deploy_hot.fd Unix.SHUTDOWN_SEND;
  let all = probe_drain c in
  March_forge.Cluster_deploy.close c;
  let lines = List.filter (fun l -> l <> "") (String.split_on_char '\n' all) in
  if List.exists (fun l -> l = "OK" || (String.length l > 3 && String.sub l 0 3 = "OK ")) lines then "OK"
  else
    match List.filter (fun l -> String.length l >= 4 && String.sub l 0 4 = "ERR ") lines with
    | l :: _ -> "refused (" ^ l ^ ")"
    | [] -> "refused (no verdict)"

let () =
  match Array.to_list Sys.argv |> List.tl with
  | [ "keygen"; dir ] ->
    let (pk, sk) = March_ed25519.Ed25519.keygen () in
    write (Filename.concat dir "pk") (March_ed25519.Ed25519.pk_to_base64 pk);
    write (Filename.concat dir "sk") (hex_of_bytes sk)
  | "deploy" :: socket :: dir :: so :: rest ->
    let pk = String.trim (read (Filename.concat dir "pk")) in
    let sk = bytes_of_hex (read (Filename.concat dir "sk")) in
    let old_schemas, old_manifest = match rest with [ s; m ] -> (s, m) | _ -> ("", "") in
    (match March_forge.Cmd_deploy_hot.parse_manifest (so ^ ".hcr_manifest") with
     | Error m -> prerr_endline ("hcr_deploy: manifest: " ^ m); exit 1
     | Ok manifest ->
       let r =
         try
           let grant_caps =
             match Sys.getenv_opt "GRANT_CAPS" with
             | Some g -> List.filter (fun c -> c <> "") (String.split_on_char ',' g)
             | None -> []
           in
           March_forge.Cmd_deploy_hot.run ~tunnel:false ~ssh_host:"local" ~remote_socket:socket
             ~signing_pubkey:pk ~sk ~manifest ~so_path:so ~old_schemas_path:old_schemas
             ~new_schemas_path:(so ^ ".schemas.json") ~old_manifest_path:old_manifest ~grant_caps ()
         with Failure m -> Error m | Unix.Unix_error (e, _, _) -> Error (Unix.error_message e)
       in
       (match r with
        | Ok _ -> ()
        | Error m -> prerr_endline ("hcr_deploy: " ^ m); exit 1))
  | [ "policy"; root; pool; manifest_path ] ->
    let fail m = prerr_endline ("hcr_deploy: " ^ m); exit 1 in
    (match March_forge.Reconcile.load_checked ~root None, March_forge.Cmd_deploy_hot.parse_manifest manifest_path with
     | Error m, _ | _, Error m -> fail m
     | Ok t, Ok manifest ->
       (match List.find_opt (fun (p : March_forge.Topology.pool) -> p.pool_name = pool) t.pools with
        | None -> fail ("no pool " ^ pool)
        | Some p ->
          (match March_forge.Host_init.policy_text ~derived:None ~manifest p with
           | Some text -> print_string text
           | None -> fail ("pool " ^ pool ^ " has no written caps: no policy"))))
  | "counters" :: socket :: keys ->
    (match March_forge.Reconcile.query_reload socket with
     | Error m -> prerr_endline ("hcr_deploy: " ^ m); exit 1
     | Ok ri ->
       List.iter (fun k ->
           Printf.printf "%s=%s\n" k
             (match March_forge.Reconcile.pins_counter ri.pins k with Some n -> string_of_int n | None -> "?"))
         keys)
  | "release" :: dir :: eps :: build :: pools :: so :: old_manifest :: rest ->
    let pk = String.trim (read (Filename.concat dir "pk")) in
    let sk = bytes_of_hex (read (Filename.concat dir "sk")) in
    let geti k d = match Sys.getenv_opt k with Some v -> (try int_of_string v with _ -> d) | None -> d in
    let endpoints = List.filter_map March_forge.Cluster_deploy.endpoint_of_string (String.split_on_char ',' eps) in
    (match March_forge.Cmd_deploy_hot.parse_manifest (so ^ ".hcr_manifest") with
     | Error m -> prerr_endline ("hcr_deploy: manifest: " ^ m); exit 1
     | Ok manifest ->
       let topology_body, push_topology =
         match Sys.getenv_opt "TOPOLOGY" with
         | Some f when f <> "" -> (read f, true)
         | _ -> ("{}\n", false)
       in
       let sp = { March_forge.Cluster_deploy.env = "test"; endpoints; sk; pubkey = pk;
                  hot = [ { March_forge.Cluster_deploy.hb_name = build; hb_pools = String.split_on_char ',' pools;
                            hb_manifest = manifest; hb_so = so; hb_old_manifest = old_manifest;
                            hb_old_schemas = (match rest with s :: _ -> s | [] -> "");
                            hb_new_schemas = so ^ ".schemas.json" } ];
                  topology_body; push_topology; canary = geti "CANARY" 0; canary_window_ms = geti "CANARY_MS" 2000;
                  rest_window_ms = geti "REST_MS" 0; work_dir = Filename.concat (Filename.get_temp_dir_name ()) (Printf.sprintf "hcr_release_%d" (Unix.getpid ()));
                  entry_path = ""; grant_caps = []; follow_s = float_of_int (geti "FOLLOW_S" 120) } in
       (match March_forge.Cluster_deploy.run sp with
        | Ok report -> print_string report
        | Error m -> prerr_endline ("hcr_deploy: " ^ m); exit 1))
  | [ "probe"; dir; ep ] ->
    let sk = bytes_of_hex (read (Filename.concat dir "sk")) in
    let say k v = Printf.printf "%s: %s\n%!" k v in
    (* 1. AUDIT_COPY forges an audit line (P2, audit-copy-unauthenticated). *)
    let forged = "{\"ts\":0,\"type\":\"release\",\"leader\":\"ATTACKER\",\"seq\":999999,\"result\":\"ok\",\"why\":\"FORGED BY UNAUTH PEER\"}\n" in
    say "audit_copy" (probe_blind ep (Printf.sprintf "AUDIT_COPY %d" (String.length forged)) forged);
    let c = probe_connect ep in
    probe_send c "AUDIT 0\n";
    let rec lines acc = let l = probe_line c in if l = "END" || l.[0] = '(' then acc else lines (l :: acc) in
    let audit = lines [] in
    March_forge.Cluster_deploy.close c;
    say "audit_forged_present" (string_of_bool (List.exists (fun l -> contains l "FORGED BY UNAUTH PEER") audit));
    (* 2. RELEASE_COPY: a candidate-only verb, even with a signed body. *)
    let rel = probe_release ~sk ~seq:(now_ms ()) ~topology:(random_hash ()) in
    say "release_copy" (probe_blind ep (Printf.sprintf "RELEASE_COPY %d" (String.length rel)) rel);
    (* 3. CAS_PUT under a hash no staged release names (P2, resource exhaustion). *)
    let junk = String.make 300 'Y' in
    say "cas_put_unstaged" (probe_blind ep (Printf.sprintf "CAS_PUT %s %d" (random_hash ()) (String.length junk)) junk);
    (* 4. STAGE an unsigned release. *)
    let unsigned =
      let open March_forge.Control_release in
      serialize { seq = now_ms (); parent = no_parent; env = "test"; topology = random_hash (); builds = [];
                  steps = [ { id = 1; pools = [ "*" ]; hosts = All; action = Topology; gate = No_gate; batch = 0 } ];
                  lines = []; drain = None; signature = String.make 128 '0' } in
    let c = probe_connect ep in
    probe_send c (Printf.sprintf "STAGE %d\n%s" (String.length unsigned) unsigned);
    say "stage_unsigned" (probe_line c);
    March_forge.Cluster_deploy.close c;
    (* 5. A signed release staged: only the hash it names may be put, within the size limit. *)
    let h = random_hash () in
    let staged = probe_release ~sk ~seq:(now_ms ()) ~topology:h in
    let c = probe_connect ep in
    probe_send c (Printf.sprintf "STAGE %d\n%s" (String.length staged) staged);
    say "stage" (probe_line c);
    probe_send c (Printf.sprintf "CAS_PUT %s 10\n" (random_hash ()));
    say "cas_put_other" (probe_line c);
    probe_send c (Printf.sprintf "CAS_PUT %s %d\n" h (64 * 1024 * 1024 + 1));
    say "cas_put_oversize" (probe_line c);
    let body = "STAGED-ARTIFACT-BYTES" in
    probe_send c (Printf.sprintf "CAS_PUT %s %d\n" h (String.length body));
    let ready = probe_line c in
    if ready = "READY" then (probe_send c body; say "cas_put_staged" (probe_line c)) else say "cas_put_staged" ready;
    March_forge.Cluster_deploy.close c;
    say "staged_hash" h;
    (* 6. Oversized bodies are refused before they are read. *)
    let c = probe_connect ep in
    probe_send c "AUDIT_COPY 1048577\n";
    say "audit_copy_oversize" (probe_line c);
    probe_send c "RELEASE 1048577\n";
    say "release_oversize" (probe_line c);
    March_forge.Cluster_deploy.close c
  | [ "probe-quota"; dir; ep; size ] ->
    let sk = bytes_of_hex (read (Filename.concat dir "sk")) in
    let size = int_of_string size in
    let h1 = random_hash () and h2 = random_hash () in
    let c = probe_connect ep in
    List.iter (fun h ->
        let r = probe_release ~sk ~seq:(now_ms ()) ~topology:h in
        probe_send c (Printf.sprintf "STAGE %d\n%s" (String.length r) r);
        ignore (probe_line c))
      [ h1; h2 ];
    List.iter (fun (k, h) ->
        probe_send c (Printf.sprintf "CAS_PUT %s %d\n" h size);
        let ready = probe_line c in
        if ready = "READY" then (probe_send c (String.make size 'Q'); Printf.printf "%s: %s\n%!" k (probe_line c))
        else Printf.printf "%s: %s\n%!" k ready)
      [ ("quota_first", h1); ("quota_second", h2) ];
    March_forge.Cluster_deploy.close c
  | [ "probe-stale"; dir; ep ] ->
    let sk = bytes_of_hex (read (Filename.concat dir "sk")) in
    let r = probe_release ~sk ~seq:1 ~topology:(random_hash ()) in
    let c = probe_connect ep in
    probe_send c (Printf.sprintf "STAGE %d\n%s" (String.length r) r);
    Printf.printf "stage_stale: %s\n%!" (probe_line c);
    March_forge.Cluster_deploy.close c
  | [ "probe-conns"; ep; n ] ->
    let n = int_of_string n in
    let cs = List.init n (fun _ -> let c = probe_connect ep in Unix.sleepf 0.05; c) in
    List.iter (fun c -> Unix.setsockopt_float c.March_forge.Cmd_deploy_hot.fd Unix.SO_RCVTIMEO 0.5) cs;
    let busy = List.filter (fun c -> probe_line c = "ERR busy") cs in
    Printf.printf "busy: %d\n%!" (List.length busy);
    let wait = match Sys.getenv_opt "IDLE_WAIT_S" with Some v -> float_of_string v | None -> 5. in
    Unix.sleepf wait;
    let open_ones = List.filter (fun c -> not (List.memq c busy)) cs in
    let closed = List.filter (fun c -> probe_line c = "(closed)") open_ones in
    Printf.printf "idle_closed: %d of %d\n%!" (List.length closed) (List.length open_ones);
    List.iter March_forge.Cluster_deploy.close cs
  | [ "api"; ep; line ] | [ "reload"; ep; line ] ->
    let read_answer conn =
      (* A list answer ends at END; anything else is one line. *)
      let first = March_forge.Cmd_deploy_hot.recv_line conn in
      print_endline first;
      let listy = List.exists (fun p -> String.length first >= String.length p && String.sub first 0 (String.length p) = p)
          [ "STATUS"; "AUDIT"; "SLOT"; "STATE"; "VERSION"; "EPOCH"; "COUNTERS"; "RESTORED"; "ARTIFACT" ] in
      if listy then begin
        let rec go () = let l = March_forge.Cmd_deploy_hot.recv_line conn in print_endline l; if l <> "END" then go () in
        go ()
      end
    in
    (try
       let conn =
         if Sys.argv.(1) = "api" then
           (match Option.bind (March_forge.Cluster_deploy.endpoint_of_string ep) (fun e -> Result.to_option (March_forge.Cluster_deploy.connect e)) with
            | Some c -> c
            | None -> prerr_endline "hcr_deploy: cannot connect"; exit 1)
         else March_forge.Cmd_deploy_hot.conn_of_fd (March_forge.Cmd_deploy_hot.connect_socket ep)
       in
       March_forge.Cmd_deploy_hot.send_line conn line;
       read_answer conn
     with Failure m -> prerr_endline ("hcr_deploy: " ^ m); exit 1
        | Unix.Unix_error (e, _, _) -> prerr_endline ("hcr_deploy: " ^ Unix.error_message e); exit 1)
  | ("api-put" | "reload-put") as verb :: ep :: hash :: file :: rest ->
    let body = read file in
    let so = match rest with [ d ] -> " so_blake3:" ^ d | _ -> "" in
    (try
       let conn =
         if verb = "reload-put" then
           Some (March_forge.Cmd_deploy_hot.conn_of_fd (March_forge.Cmd_deploy_hot.connect_socket ep))
         else
           Option.bind (March_forge.Cluster_deploy.endpoint_of_string ep)
             (fun e -> Result.to_option (March_forge.Cluster_deploy.connect e))
       in
       match conn with
       | None -> prerr_endline "hcr_deploy: cannot connect"; exit 1
       | Some conn ->
         March_forge.Cmd_deploy_hot.send_line conn
           (Printf.sprintf "CAS_PUT %s %d%s" hash (String.length body) so);
         let ready = March_forge.Cmd_deploy_hot.recv_line conn in
         if ready <> "READY" then print_endline ready
         else begin
           March_forge.Cmd_deploy_hot.send_binary conn (Bytes.of_string body) 0 (String.length body);
           print_endline (March_forge.Cmd_deploy_hot.recv_line conn)
         end
     with Failure m -> prerr_endline ("hcr_deploy: " ^ m); exit 1
        | Unix.Unix_error (e, _, _) -> prerr_endline ("hcr_deploy: " ^ Unix.error_message e); exit 1)
  | [ "digest"; file ] -> print_endline (March_forge.Cmd_deploy_hot.artifact_digest file)
  | "certs" :: dir :: eps :: items ->
    let sk = bytes_of_hex (read (Filename.concat dir "sk")) in
    let endpoints = List.filter_map March_forge.Cluster_deploy.endpoint_of_string (String.split_on_char ',' eps) in
    let certs, revokes =
      List.fold_left (fun (cs, rs) it ->
          match String.split_on_char ':' it with
          | [ "cert"; node; file ] -> (cs @ [ (node, String.trim (read file)) ], rs)
          | [ "revoke"; file ] -> (cs, rs @ [ String.trim (read file) ])
          | _ -> prerr_endline ("hcr_deploy: bad item " ^ it); exit 2)
        ([], []) items
    in
    let follow_s = match Sys.getenv_opt "FOLLOW_S" with Some v -> (try float_of_string v with _ -> 120.) | None -> 120. in
    (match March_forge.Cmd_cluster.deliver ~endpoints ~sk ~env:"test" ~follow_s
             { March_forge.Control_release.certs; revokes } with
     | Ok report -> print_string report
     | Error m -> prerr_endline ("hcr_deploy: " ^ m); exit 1)
  | [ "release-stale"; eps; seq ] ->
    let endpoints = List.filter_map March_forge.Cluster_deploy.endpoint_of_string (String.split_on_char ',' eps) in
    (match March_forge.Cmd_hot_reload.read_sk_raw () with
     | Error m -> prerr_endline ("hcr_deploy: " ^ m); exit 1
     | Ok sk ->
       let open March_forge.Control_release in
       let r = sign ~sk { seq = int_of_string seq; parent = no_parent; env = "local"; topology = String.make 64 '0';
                          builds = []; steps = [ { id = 1; pools = [ "*" ]; hosts = All; action = Topology; gate = No_gate; batch = 0 } ];
                          lines = []; drain = None; signature = "" } in
       (match March_forge.Cluster_deploy.send_release endpoints ~body:(serialize r) with
        | Ok resp | Error resp -> print_endline resp))
  | [ "status"; eps ] ->
    let endpoints = List.filter_map March_forge.Cluster_deploy.endpoint_of_string (String.split_on_char ',' eps) in
    (match March_forge.Cluster_deploy.status endpoints with
     | Ok s -> print_string (March_forge.Cluster_deploy.render_status s)
     | Error m -> prerr_endline ("hcr_deploy: " ^ m); exit 1)
  | _ ->
    prerr_endline "usage: hcr_deploy keygen <dir> | deploy <socket> <dir> <so> [<old schemas> <old manifest>] | counters <socket> <key>...";
    exit 2
