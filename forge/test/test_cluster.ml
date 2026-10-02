(** Tests for forge/lib/cmd_cluster.ml: the operator/node certificate tooling
    (distributed-deploys build step 11a). The certificate bytes forge writes
    must be byte-identical to stdlib/node_cert.march's canonical encoding, so
    the vector below is pinned in BOTH suites (test/stdlib/test_node_cert.march
    asserts the same hex); a drift in either encoder reddens one of them. *)

open March_forge

let seed b = String.make 32 (Char.chr b)
let op_sk = Bytes.to_string (March_ed25519.Ed25519.seed_keypair (Bytes.of_string (seed 1)))
let node_sk = Bytes.to_string (March_ed25519.Ed25519.seed_keypair (Bytes.of_string (seed 2)))

let test_pinned_vector () =
  Alcotest.(check string) "operator pubkey" "8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c" (Cmd_cluster.to_hex (Cmd_cluster.pubkey_of op_sk));
  Alcotest.(check string) "node pubkey" "8139770ea87d175f56a35466c34c7ecccb8d8a91b4ee37a25df60f5b8fc9b394" (Cmd_cluster.to_hex (Cmd_cluster.pubkey_of node_sk));
  let body = Cmd_cluster.cert_body ~node:"spiffe://example.org/pool/web/node/node-a"
      ~roles:["Checkout.Ledger:offer"] ~flags:["raw_send"] ~not_after:2000000000
      ~issuer:(Cmd_cluster.issuer_uri ~trust_domain:"example.org" (Cmd_cluster.pubkey_of op_sk))
      ~pubkey_hex:(Cmd_cluster.to_hex (Cmd_cluster.pubkey_of node_sk))
      ~serial:"00112233445566778899aabbccddeeff" in
  Alcotest.(check string) "canonical body" "98b26d617263682d6e6f64652d636572742d7631d9297370696666653a2f2f6578616d706c652e6f72672f706f6f6c2f7765622f6e6f64652f6e6f64652d6191b5436865636b6f75742e4c65646765723a6f6666657291a87261775f73656e64ce77359400d92e7370696666653a2f2f6578616d706c652e6f72672f6f70657261746f722f38613838653364643734303966313935d94038313339373730656138376431373566353661333534363663333463376563636362386438613931623465653337613235646636306635623866633962333934d9203030313132323333343435353636373738383939616162626363646465656666" (Cmd_cluster.to_hex body);
  Alcotest.(check string) "signature" "e8604e7d6a3c3cfbce93a90d76491d8ff87d49df9c7dd7e5cc0526f41733cb0a79450f0f9ff3caf7e9ddb4c2fa27bd71a3a7bfff8a24ac7a69827b9db3aec507" (Cmd_cluster.to_hex (Cmd_cluster.sign op_sk body))

let test_msgpack_forms () =
  let h v = Cmd_cluster.to_hex (Cmd_cluster.mp v) in
  Alcotest.(check string) "fixint" "7f" (h (Cmd_cluster.Int 127));
  Alcotest.(check string) "uint8" "cc80" (h (Cmd_cluster.Int 128));
  Alcotest.(check string) "uint32" "ce77359400" (h (Cmd_cluster.Int 2000000000));
  Alcotest.(check string) "neg fixint" "ff" (h (Cmd_cluster.Int (-1)));
  Alcotest.(check string) "fixstr" "a3616263" (h (Cmd_cluster.Str "abc"));
  Alcotest.(check string) "str8" ("d920" ^ Cmd_cluster.to_hex (String.make 32 'f'))
    (h (Cmd_cluster.Str (String.make 32 'f')));
  Alcotest.(check string) "bin8" "c4020102" (h (Cmd_cluster.Bin "\x01\x02"));
  Alcotest.(check string) "fixarray" "920102" (h (Cmd_cluster.Arr [Cmd_cluster.Int 1; Cmd_cluster.Int 2]))

let with_tmpdir f =
  let d = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "forge-cluster-%d-%d" (Unix.getpid ()) (Random.bits ())) in
  Unix.mkdir d 0o700;
  Fun.protect ~finally:(fun () -> ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote d)))) (fun () -> f d)

let test_keygen_cert_revoke () =
  with_tmpdir (fun d ->
    (match Cmd_cluster.run_keygen ~out_dir:d ~force:false () with
     | Ok _ -> () | Error e -> Alcotest.fail e);
    (match Cmd_cluster.run_keygen ~out_dir:d ~force:false () with
     | Ok _ -> Alcotest.fail "keygen overwrote an existing operator.key"
     | Error _ -> ());
    let key_perm = (Unix.stat (Filename.concat d "operator.key")).Unix.st_perm in
    Alcotest.(check int) "operator.key is 0600" 0o600 key_perm;
    let ok = Filename.concat d "operator.key" in
    (match Cmd_cluster.run_cert ~name:"node-a" ~roles:"Checkout.Ledger:offer" ~flags:"raw_send"
             ~days:30 ~seconds:None ~trust_domain:"example.org" ~pool:"web" ~operator_key:ok
             ~node_key:None ~out_dir:d () with
     | Ok _ -> () | Error e -> Alcotest.fail e);
    Alcotest.(check bool) "node-a.cert written" true (Sys.file_exists (Filename.concat d "node-a.cert"));
    Alcotest.(check bool) "node-a.key written" true (Sys.file_exists (Filename.concat d "node-a.key"));
    (match Cmd_cluster.run_cert ~name:"node-b" ~roles:"Checkout.Ledger" ~flags:"" ~days:1
             ~seconds:None ~trust_domain:"t" ~pool:"p" ~operator_key:ok ~node_key:None ~out_dir:d () with
     | Ok _ -> Alcotest.fail "a role without :offer/:initiate was accepted"
     | Error _ -> ());
    (match Cmd_cluster.run_revoke ~serial:"" ~node:"" ~trust_domain:"t" ~pool:"p" ~operator_key:ok () with
     | Ok _ -> Alcotest.fail "revoke with neither --serial nor --node succeeded"
     | Error _ -> ());
    match Cmd_cluster.run_revoke ~serial:"abc" ~node:"" ~trust_domain:"t" ~pool:"p" ~operator_key:ok () with
    | Ok tok -> Alcotest.(check bool) "token is base64 text" true (String.length tok > 0)
    | Error e -> Alcotest.fail e)

(* ── step 12b: certificate items in a release ──────────────────────────── *)

(* The same release text is pinned in test/stdlib/test_control.march
   ("the item lines are forge's, byte for byte"): forge signs exactly what
   Control.signed_text reads back. *)
let pinned_items_text =
  "release v1\nseq 7\nparent none\nenv prod\ntopology -\nstep 1 pools:* hosts:all do:certs gate:none\n\
   cert node-a Q0VSVA==\nrevoke UkVWMQ==\nrevoke UkVWMg==\n"

let items_release () =
  let open Control_release in
  ({ seq = 7; parent = no_parent; env = "prod"; topology = "-"; builds = [];
     steps = [ { id = 1; pools = [ "*" ]; hosts = All; action = Certs; gate = No_gate; batch = 0 } ];
     lines = []; drain = None; signature = "" },
   { certs = [ ("node-a", "Q0VSVA==") ]; revokes = [ "UkVWMQ=="; "UkVWMg==" ] })

let test_release_items () =
  let r, items = items_release () in
  Alcotest.(check string) "signed text" pinned_items_text (Control_release.signed_text_with items r);
  Alcotest.(check string) "no items: the 12a text" (Control_release.signed_text r)
    (Control_release.signed_text_with Control_release.no_items r);
  let sk = Bytes.of_string node_sk in
  let signed = Control_release.sign_with ~sk items r in
  Alcotest.(check bool) "the signature covers the items" true
    (March_ed25519.Ed25519.verify (Bytes.of_string pinned_items_text)
       (Bytes.of_string (Result.get_ok (Cmd_cluster.of_hex signed.Control_release.signature)))
       (Bytes.of_string (Cmd_cluster.pubkey_of node_sk)));
  let other = Control_release.sign_with ~sk { items with Control_release.revokes = [] } r in
  Alcotest.(check bool) "other items, another signature" true (other.Control_release.signature <> signed.Control_release.signature);
  let doc = Control_release.serialize_with items signed in
  Alcotest.(check bool) "the document ends with its sig line" true
    (String.ends_with ~suffix:("sig " ^ signed.Control_release.signature ^ "\n") doc)

let test_deliver_flags () =
  with_tmpdir (fun d ->
    let ok = Filename.concat d "operator.key" in
    ignore (Cmd_cluster.run_keygen ~out_dir:d ~force:false ());
    let delivered = ref [] in
    let deliver cert = delivered := cert :: !delivered; Ok "delivered" in
    (match Cmd_cluster.run_cert ~name:"node-a" ~roles:"" ~flags:"" ~days:1 ~seconds:None ~trust_domain:"t"
             ~pool:"p" ~operator_key:ok ~node_key:None ~out_dir:d ~deliver () with
     | Ok _ -> Alcotest.fail "--deliver without --node-key was accepted (it would need the node's new secret key)"
     | Error e -> Alcotest.(check bool) "says why" true (String.length e > 0));
    Alcotest.(check int) "nothing delivered" 0 (List.length !delivered);
    ignore (Cmd_cluster.run_cert ~name:"node-a" ~roles:"" ~flags:"" ~days:1 ~seconds:None ~trust_domain:"t"
              ~pool:"p" ~operator_key:ok ~node_key:None ~out_dir:d ());
    let key = Filename.concat d "node-a.key" in
    (match Cmd_cluster.run_cert ~name:"node-a" ~roles:"" ~flags:"" ~days:2 ~seconds:None ~trust_domain:"t"
             ~pool:"p" ~operator_key:ok ~node_key:(Some key) ~out_dir:d ~deliver () with
     | Ok m -> Alcotest.(check string) "the delivery's answer" "delivered" m
     | Error e -> Alcotest.fail e);
    Alcotest.(check (list string)) "the certificate written is the one delivered"
      [ String.trim (Cmd_cluster.read_file (Filename.concat d "node-a.cert")) ] !delivered;
    (match Cmd_cluster.run_revoke ~serial:"abc" ~node:"" ~trust_domain:"t" ~pool:"p" ~operator_key:ok
             ~deliver:(fun tok -> Ok ("revoked " ^ tok)) () with
     | Ok m -> Alcotest.(check bool) "the token is delivered" true (String.length m > 8 && String.sub m 0 8 = "revoked ")
     | Error e -> Alcotest.fail e);
    (* the deploy key, as hex or as forge's base64 *)
    let hex = Filename.concat d "dk.hex" and b64 = Filename.concat d "dk.b64" in
    Cmd_cluster.write_file hex (Cmd_cluster.to_hex node_sk ^ "\n");
    Cmd_cluster.write_file b64 (Cmd_cluster.b64 node_sk ^ "\n");
    List.iter (fun p ->
        match Cmd_cluster.load_deploy_key (Some p) with
        | Ok k -> Alcotest.(check string) p (Cmd_cluster.to_hex node_sk) (Cmd_cluster.to_hex (Bytes.to_string k))
        | Error e -> Alcotest.fail e)
      [ hex; b64 ];
    (match Cmd_cluster.endpoints_of "127.0.0.1:7947,host:x" with
     | Ok _ -> Alcotest.fail "a bad endpoint was accepted"
     | Error _ -> ());
    match Cmd_cluster.endpoints_of "127.0.0.1:7947, h2:8000" with
    | Ok eps -> Alcotest.(check int) "two endpoints" 2 (List.length eps)
    | Error e -> Alcotest.fail e)

let () =
  Alcotest.run "forge cluster"
    [ ("certificates",
       [ Alcotest.test_case "pinned vector matches stdlib/node_cert.march" `Quick test_pinned_vector;
         Alcotest.test_case "msgpack smallest forms" `Quick test_msgpack_forms;
         Alcotest.test_case "keygen / cert / revoke" `Quick test_keygen_cert_revoke ]);
      ("delivery (step 12b)",
       [ Alcotest.test_case "certificate items in a release" `Quick test_release_items;
         Alcotest.test_case "--deliver: the node key, what is delivered, the deploy key" `Quick test_deliver_flags ]) ]
