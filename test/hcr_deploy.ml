(** A local hot deploy for the two-node harness (distributed-deploys build
    step 9, test/two_node/protocol_evolve): what `forge deploy hot` does over
    its ssh tunnel, against a reload socket on this machine
    ([Cmd_deploy_hot.run ~tunnel:false], the path `forge test --upgrade-from`
    uses), so a scenario can deploy one node at a time in the order it
    chooses. Not a user-facing tool.

      hcr_deploy keygen <dir>                 writes <dir>/pk (base64), <dir>/sk (hex)
      hcr_deploy deploy <socket> <dir> <so> [<old .schemas.json> <old .hcr_manifest>]
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
      hcr_deploy api <host:port> <line>       one request to a control API, answer to stdout
      hcr_deploy reload <socket> <line>       one request to a reload socket, answer to stdout
                                              (lines up to END, or the first line)

    Exit 0 on success; a failed deploy prints why on stderr and exits 1. *)

let read path = In_channel.with_open_bin path In_channel.input_all
let write path s = Out_channel.with_open_bin path (fun oc -> output_string oc s)

let hex_of_bytes b = String.concat "" (List.init (Bytes.length b) (fun i -> Printf.sprintf "%02x" (Char.code (Bytes.get b i))))

let bytes_of_hex h =
  let h = String.trim h in
  Bytes.init (String.length h / 2) (fun i -> Char.chr (int_of_string ("0x" ^ String.sub h (2 * i) 2)))

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
           March_forge.Cmd_deploy_hot.run ~tunnel:false ~ssh_host:"local" ~remote_socket:socket
             ~signing_pubkey:pk ~sk ~manifest ~so_path:so ~old_schemas_path:old_schemas
             ~new_schemas_path:(so ^ ".schemas.json") ~old_manifest_path:old_manifest ()
         with Failure m -> Error m | Unix.Unix_error (e, _, _) -> Error (Unix.error_message e)
       in
       (match r with
        | Ok _ -> ()
        | Error m -> prerr_endline ("hcr_deploy: " ^ m); exit 1))
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
  | [ "api"; ep; line ] | [ "reload"; ep; line ] ->
    let read_answer conn =
      (* A list answer ends at END; anything else is one line. *)
      let first = March_forge.Cmd_deploy_hot.recv_line conn in
      print_endline first;
      let listy = List.exists (fun p -> String.length first >= String.length p && String.sub first 0 (String.length p) = p)
          [ "STATUS"; "SLOT"; "STATE"; "VERSION"; "EPOCH"; "COUNTERS"; "RESTORED"; "ARTIFACT" ] in
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
  | [ "status"; eps ] ->
    let endpoints = List.filter_map March_forge.Cluster_deploy.endpoint_of_string (String.split_on_char ',' eps) in
    (match March_forge.Cluster_deploy.status endpoints with
     | Ok s -> print_string (March_forge.Cluster_deploy.render_status s)
     | Error m -> prerr_endline ("hcr_deploy: " ^ m); exit 1)
  | _ ->
    prerr_endline "usage: hcr_deploy keygen <dir> | deploy <socket> <dir> <so> [<old schemas> <old manifest>] | counters <socket> <key>...";
    exit 2
