(** A local hot deploy for the two-node harness (distributed-deploys build
    step 9, test/two_node/protocol_evolve): what `forge deploy hot` does over
    its ssh tunnel, against a reload socket on this machine
    ([Cmd_deploy_hot.run ~tunnel:false], the path `forge test --upgrade-from`
    uses), so a scenario can deploy one node at a time in the order it
    chooses. Not a user-facing tool.

      hcr_deploy keygen <dir>                 writes <dir>/pk (base64), <dir>/sk (hex)
      hcr_deploy deploy <socket> <dir> <so> [<old .schemas.json> <old .hcr_manifest>]
      hcr_deploy counters <socket> <key>...   prints key=value from PINS

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
  | _ ->
    prerr_endline "usage: hcr_deploy keygen <dir> | deploy <socket> <dir> <so> [<old schemas> <old manifest>] | counters <socket> <key>...";
    exit 2
