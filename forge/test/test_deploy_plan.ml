(** [Deploy_plan.classify] on fixture pairs (distributed-deploys build step
    10b, item 3; the todo's acceptance): one case per classification
    branch, each an (old, new) pair of manifests, schemas, protocol
    declarations, topologies, derived caps and base-image identities, and
    the six-block rendering. In-process; no toolchain. *)

open March_forge
module P = Deploy_plan

let contains s sub =
  let n = String.length s and k = String.length sub in
  let rec go i = i + k <= n && (String.sub s i k = sub || go (i + 1)) in
  go 0

let expect what text subs =
  List.iter (fun s -> if not (contains text s) then Alcotest.failf "%s: expected %S in:\n%s" what s text) subs

let refuse what text subs =
  List.iter (fun s -> if contains text s then Alcotest.failf "%s: did not expect %S in:\n%s" what s text) subs

(* ── fixtures ──────────────────────────────────────────────────────────── *)

let fm ?(sig_ = "s") ?(caps = []) name impl =
  { Cmd_deploy_hot.fn_name = name; fn_impl_hash = impl; fn_sig_hash = sig_; fn_callers = []; fn_caps = caps;
    fn_has_caps = true }

let abi_arm = "march-hcr-v2;triple=aarch64-unknown-linux-gnu;ptr=8"

let manifest ?(target = "linux/arm64") ?(abi = abi_arm) ?(roles = []) fns =
  { Cmd_deploy_hot.version = 2; cas_hash = "c"; target = Some target; hcr_abi = Some abi; module_prefix = Some "App";
    functions = fns; roles }

(** The base program: two pools' hooks, a role body, an actor, a protocol. *)
let base_fns =
  [ fm "Back.start" "h1"; fm "Front.start" "h2"; fm "Back.serve" "b1"; fm "Back.helper" "x1";
    fm "Counter_dispatch" "d1"; fm "Echo_Msg.fingerprint" "fp1"; fm "Echo_Server.recv_Ask" "r1";
    fm "Echo_Client.send_Ask" "c1" ]

let replace_fn name impl fns = List.map (fun (f : Cmd_deploy_hot.fn_manifest) -> if f.fn_name = name then { f with fn_impl_hash = impl } else f) fns

let schema ?(compat = "full") ?handlers ?migrate_msg_from fields =
  { Schema_diff.compat; invariant = None;
    state_fields = List.map (fun (name, ty) -> { Schema_diff.name; ty }) fields; handlers; migrate_msg_from }

let ctor cname params = { Schema_diff.cname; params }

let topology_text = {|
[roles]
"Echo.Server" = { body = "App.Back.serve", capacity = 8 }

[pool.back]
start = "App.Back.start"
serves = ["Echo.Server"]
hosts = [{ host = "root@b1", labels = ["x"] }]

[pool.front]
start = "App.Front.start"
initiates = ["Echo.Client"]
hosts = ["root@f1"]

[backend]
kind = "ssh"
|}

let topo ?(text = topology_text) () =
  match Topology.of_strings [ ("topology.toml", text) ] with
  | Ok t -> t
  | Error ds -> Alcotest.failf "fixture topology: %s" (String.concat "; " (List.map Topology.render_diag ds))

let replace ~sub ~by s = Str.global_replace (Str.regexp_string sub) by s

let build ?(name = "shared") ?(pools = [ "back"; "front" ]) ?old ?(old_schemas = []) ?(new_schemas = [])
    ?(old_runtime = Some "rt1") ?(new_runtime = Some "rt1") nw =
  { P.b_name = name; b_pools = pools; b_old = old; b_new = nw; b_old_schemas = old_schemas; b_new_schemas = new_schemas;
    b_old_runtime = old_runtime; b_new_runtime = new_runtime }

(** Protocols from March source, through the same parse forge uses. *)
let protos_of_source src : P.proto list =
  match Topology.parse_source ~path:"p.march" src with
  | Ok m -> let idx = Topology.empty_index () in Topology.index_module idx m; P.protos_of_index idx
  | Error e -> Alcotest.failf "fixture protocol does not parse: %s" e

let echo_v1 = {|mod App do
  protocol Echo do
    ask: Client -> Server : Int
    answer: Server -> Client : Int
  end
end
|}

let proto_named name src = List.find (fun (p : P.proto) -> p.p_name = name) (protos_of_source src)

let echo = proto_named "Echo" echo_v1

let derived_v1 = [ ("back", ([ "IO.Console" ], [])); ("front", ([ "IO.Console" ], [ "Echo.Client" ])) ]

let input ?(old_t = Some (topo ())) ?(new_t = topo ()) ?(protocols = [ ("Echo", Some echo, Some echo) ])
    ?(old_derived = Some derived_v1) ?(new_derived = Some derived_v1) ?(grant = []) ?(live = []) ?(compact = false)
    ?compact_after builds =
  { P.i_env = Some "prod"; i_old_topology = old_t; i_new_topology = new_t; i_builds = builds;
    i_protocols = protocols; i_old_derived = old_derived; i_new_derived = new_derived; i_grant_caps = grant;
    i_live = live; i_compact = compact; i_compact_after = compact_after }

let mech (p : P.plan) pool =
  match List.find_opt (fun (pp : P.pool_plan) -> pp.pp_pool = pool) p.pools with
  | Some pp -> pp
  | None -> Alcotest.failf "no pool %s in the plan" pool

let is_restart = function P.Restart _ -> true | _ -> false
let is_blocked = function P.Blocked _ -> true | _ -> false

let check_mech what (pp : P.pool_plan) f =
  if not (f pp.pp_mechanism) then
    Alcotest.failf "%s: pool %s got %s (%s)" what pp.pp_pool (P.mechanism_text pp.pp_mechanism) (String.concat "; " pp.pp_why)

(* ── cases ─────────────────────────────────────────────────────────────── *)

let test_first_deploy () =
  let p = P.classify (input ~old_t:None ~old_derived:None [ build (manifest base_fns) ]) in
  Alcotest.(check bool) "first" true p.first;
  check_mech "back" (mech p "back") is_restart;
  check_mech "front" (mech p "front") is_restart;
  expect "render" (P.render p) [ "nothing has been deployed to this environment yet"; "first deploy";
                                 "nothing is deployed yet: install the base build and start it" ]

let test_nothing_changed () =
  let p = P.classify (input [ build ~old:(manifest base_fns) (manifest base_fns) ]) in
  List.iter (fun pool -> check_mech pool (mech p pool) (fun m -> m = P.Nothing)) [ "back"; "front" ];
  expect "render" (P.render p) [ "1. What changed\n  nothing"; "no capability widens" ]

let test_hot_patch () =
  let nw = manifest (replace_fn "Back.helper" "x2" base_fns @ [ fm "Back.helper2" "y1" ]) in
  let old = manifest (base_fns @ [ fm "Back.gone" "g1" ]) in
  let p = P.classify (input [ build ~old nw ]) in
  check_mech "back" (mech p "back") (fun m -> m = P.Hot);
  check_mech "front" (mech p "front") (fun m -> m = P.Hot);
  expect "render" (P.render p)
    [ "1 function(s) changed, 1 added, 1 removed"; "changed: Back.helper"; "added: Back.helper2";
      "removed: Back.gone"; "pool back (build shared, 1 host): hot patch" ]

let test_signature_change_noted () =
  let nw = manifest (List.map (fun (f : Cmd_deploy_hot.fn_manifest) ->
      if f.fn_name = "Back.helper" then { f with fn_impl_hash = "x2"; fn_sig_hash = "s2" } else f) base_fns) in
  let p = P.classify (input [ build ~old:(manifest base_fns) nw ]) in
  expect "render" (P.render p) [ "signature changed: Back.helper" ]

let test_migration () =
  let old_s = [ ("Counter", schema [ ("n", "Int") ]) ] in
  let new_s = [ ("Counter", schema [ ("n", "Int"); ("hist", "List(Int)") ]) ] in
  let nw = manifest (replace_fn "Counter_dispatch" "d2" base_fns @ [ fm "Back.counter_migrate_state" "m1" ]) in
  let p = P.classify (input [ build ~old:(manifest base_fns) ~old_schemas:old_s ~new_schemas:new_s nw ]) in
  check_mech "back" (mech p "back") (function P.Hot_migrate [ "Counter" ] -> true | _ -> false);
  expect "render" (P.render p) [ "actor Counter: state changed (+hist : List(Int))"; "hot patch + migration";
                                 "Counter: state changed, migrate_state found" ];
  (* no migrate_state under @compat(full): the deploy would be refused *)
  let nw = manifest (replace_fn "Counter_dispatch" "d2" base_fns) in
  let p = P.classify (input [ build ~old:(manifest base_fns) ~old_schemas:old_s ~new_schemas:new_s nw ]) in
  check_mech "blocked" (mech p "back") is_blocked;
  Alcotest.(check bool) "plan is blocked" true (P.blocked p);
  expect "render" (P.render p) [ "BLOCKED"; "@compat(full) violated"; "no counter_migrate_state" ];
  (* @compat(any): no migrate_state needed *)
  let new_s = [ ("Counter", schema ~compat:"any" [ ("n", "Int"); ("hist", "List(Int)") ]) ] in
  let p = P.classify (input [ build ~old:(manifest base_fns) ~old_schemas:old_s ~new_schemas:new_s nw ]) in
  check_mech "compat any" (mech p "back") (fun m -> m = P.Hot)

let test_message_types () =
  let old_h = [ ctor "Add" [ "Int" ]; ctor "Legacy" [ "Int" ] ] and new_h = [ ctor "Add" [ "Int" ] ] in
  let old_s = [ ("Counter", schema ~handlers:old_h [ ("n", "Int") ]) ] in
  let nw = manifest (replace_fn "Counter_dispatch" "d2" base_fns) in
  let run new_s = P.classify (input [ build ~old:(manifest base_fns) ~old_schemas:old_s ~new_schemas:new_s nw ]) in
  let p = run [ ("Counter", schema ~handlers:new_h [ ("n", "Int") ]) ] in
  check_mech "no migrate_msg: hot, with a loss" (mech p "back") (fun m -> m = P.Hot);
  expect "loss" (P.render p) [ "5. What may be lost\n  build shared: actor Counter's message type changed and it has no counter_migrate_msg" ];
  let p = run [ ("Counter", schema ~handlers:new_h ~migrate_msg_from:old_h [ ("n", "Int") ]) ] in
  refuse "migrate_msg converts them" (P.render p) [ "has no counter_migrate_msg" ];
  let p = run [ ("Counter", schema ~handlers:new_h ~migrate_msg_from:[ ctor "Other" [] ] [ ("n", "Int") ]) ] in
  check_mech "wrong old type" (mech p "back") is_blocked;
  expect "render" (P.render p) [ "counter_migrate_msg's old type is not the running version's handlers" ]

let echo_v2_breaking = {|mod App do
  protocol Echo do
    ask: Client -> Server : String
    answer: Server -> Client : Int
  end
end
|}

let test_protocol_drain () =
  let nw = manifest (replace_fn "Echo_Msg.fingerprint" "fp2" (replace_fn "Echo_Server.recv_Ask" "r2" base_fns)) in
  let live = [ { P.l_node = "back-b1"; l_pool = "back"; l_up = true; l_running = 3; l_offers = [ "Echo.Server" ]; l_stack = None } ] in
  let p = P.classify (input ~live ~protocols:[ ("Echo", Some echo, Some (proto_named "Echo" echo_v2_breaking)) ]
                        [ build ~old:(manifest base_fns) nw ]) in
  check_mech "back serves Echo" (mech p "back") (function P.Hot_drain [ "Echo" ] -> true | _ -> false);
  check_mech "front initiates Echo" (mech p "front") (function P.Hot_drain [ "Echo" ] -> true | _ -> false);
  expect "render" (P.render p)
    [ "protocol Echo: fingerprint fp1 -> fp2 (its steps changed (not one added choice branch))";
      "hot patch + protocol drain"; "4. Drains\n  pool back: offers close: Echo.Server; sessions live on the pool's nodes: 3";
      "pool front: offers close: (none: it only initiates)"; "pool back: 3 live session(s) of Echo run to their end" ]

let test_fingerprint_moved_same_declaration () =
  let nw = manifest (replace_fn "Echo_Msg.fingerprint" "fp2" base_fns) in
  let p = P.classify (input [ build ~old:(manifest base_fns) nw ]) in
  check_mech "payload type changed" (mech p "back") (function P.Hot_drain _ -> true | _ -> false);
  expect "render" (P.render p) [ "its wire fingerprint changed (a payload type changed)" ]

let retry_v1 = {|mod App do
  protocol Echo do
    ask: Client -> Server : Int
    choose by Server:
      ok -> Server -> Client : Int
      fail -> Server -> Client : String
    end
  end
end
|}

let retry_v2 = {|mod App do
  protocol Echo do
    ask: Client -> Server : Int
    choose by Server:
      ok -> Server -> Client : Int
      fail -> Server -> Client : String
      retry -> Server -> Client : Int
    end
  end
end
|}

let test_choice_added_monolith_split () =
  let old_p = proto_named "Echo" retry_v1 and new_p = proto_named "Echo" retry_v2 in
  (match P.classify_proto (Some old_p) (Some new_p) with
   | P.Choice_added ca ->
     Alcotest.(check string) "chooser" "Server" ca.ca_by;
     Alcotest.(check (list string)) "receivers" [ "Client" ] ca.ca_receivers;
     Alcotest.(check string) "label" "retry" ca.ca_label
   | _ -> Alcotest.fail "one added branch must classify as Choice_added");
  (* back serves Server (the chooser), front initiates Client (the receiver);
     both are in the shared build: the monolith split (D21). *)
  let nw = manifest (replace_fn "Echo_Msg.fingerprint" "fp2"
                       (replace_fn "Back.serve" "b2" base_fns @ [ fm "Echo_Server.send_Retry" "s1"; fm "Echo_Client.recv_Retry" "q1" ])) in
  let p = P.classify (input ~protocols:[ ("Echo", Some old_p, Some new_p) ] [ build ~old:(manifest base_fns) nw ]) in
  (match p.splits with
   | [ sp ] ->
     Alcotest.(check string) "build" "shared" sp.sp_build;
     Alcotest.(check (list string)) "held back: the chooser's side" [ "Back.serve"; "Echo_Server.send_Retry" ]
       (List.sort compare sp.sp_held)
   | l -> Alcotest.failf "expected one split, got %d" (List.length l));
  expect "render" (P.render p)
    [ "the branch `retry` added to `choose by Server`"; "SPLIT (D21): build shared both chooses and receives Echo's new branch `retry`";
      "deploy one: everything except Server's side of Echo"; "deploy two: Server's side";
      "build step 9's compatibility table" ]

let test_choice_added_order_across_builds () =
  (* front is isolated: its own build receives; back (shared) chooses. No
     split; the receiving pool goes first. *)
  let text = replace ~sub:"[pool.front]\n" ~by:"[pool.front]\nisolate = true\n" topology_text in
  let t = topo ~text () in
  let old_p = proto_named "Echo" retry_v1 and new_p = proto_named "Echo" retry_v2 in
  let shared_new = manifest (replace_fn "Echo_Msg.fingerprint" "fp2" (replace_fn "Back.serve" "b2" base_fns)) in
  let front_new = manifest (replace_fn "Echo_Msg.fingerprint" "fp2" (replace_fn "Echo_Client.send_Ask" "c2" base_fns)) in
  let p = P.classify (input ~old_t:(Some t) ~new_t:t ~protocols:[ ("Echo", Some old_p, Some new_p) ]
                        [ build ~pools:[ "back" ] ~old:(manifest base_fns) shared_new;
                          build ~name:"front" ~pools:[ "front" ] ~old:(manifest base_fns) front_new ]) in
  Alcotest.(check int) "no split" 0 (List.length p.splits);
  Alcotest.(check (list string)) "receivers first" [ "front"; "back" ] (List.map (fun (pp : P.pool_plan) -> pp.pp_pool) p.pools);
  expect "render" (P.render p) [ "3. Order and splits\n  1. pool front"; "pools receiving it (Echo.Client) go before pools choosing it" ]

let unlabelled_v1 = {|mod App do
  protocol Echo do
    Client -> Server : Int
    choose by Server:
      ok -> Server -> Client : Int
    end
    Server -> Client : Int
  end
end
|}

let unlabelled_v2 = {|mod App do
  protocol Echo do
    Client -> Server : Int
    choose by Server:
      ok -> Server -> Client : Int
      more -> Server -> Client : Int
        Server -> Client : Int
    end
    Server -> Client : Int
  end
end
|}

let test_renumbered_wire_tags () =
  let old_p = proto_named "Echo" unlabelled_v1 and new_p = proto_named "Echo" unlabelled_v2 in
  match P.classify_proto (Some old_p) (Some new_p) with
  | P.Choice_added ca ->
    Alcotest.(check (list (pair string string))) "the later unlabelled message moves" [ ("Msg_Server_Client_1", "Msg_Server_Client_2") ]
      ca.ca_renumbered;
    let p = P.classify (input ~protocols:[ ("Echo", Some old_p, Some new_p) ]
                          [ build ~old:(manifest base_fns) (manifest (replace_fn "Echo_Msg.fingerprint" "fp2" base_fns)) ]) in
    expect "render" (P.render p) [ "renumbers unlabelled messages (Msg_Server_Client_1 -> Msg_Server_Client_2)"; "label those steps" ]
  | _ -> Alcotest.fail "expected Choice_added"

let test_protocol_structure () =
  let same = P.classify_proto (Some echo) (Some echo) in
  Alcotest.(check bool) "same" true (same = P.Same);
  Alcotest.(check bool) "added" true (P.classify_proto None (Some echo) = P.Added);
  Alcotest.(check bool) "removed" true (P.classify_proto (Some echo) None = P.Removed);
  (match P.classify_proto (Some echo) (Some (proto_named "Echo" echo_v2_breaking)) with
   | P.Breaking _ -> () | _ -> Alcotest.fail "a payload change is breaking");
  (* the JSON the baseline is kept in round-trips *)
  let back = P.proto_of_json (P.proto_json (proto_named "Echo" retry_v2)) in
  Alcotest.(check bool) "json round trip" true (back = Some (proto_named "Echo" retry_v2));
  (* a branch added inside a loop *)
  let in_loop v = Printf.sprintf "mod App do\n  protocol L do\n    loop do\n      a: A -> B : Int\n      choose by B:\n        x -> B -> A : Int\n%s      end\n    end\n  end\nend\n" v in
  match P.classify_proto (Some (proto_named "L" (in_loop ""))) (Some (proto_named "L" (in_loop "        y -> B -> A : Int\n"))) with
  | P.Choice_added ca -> Alcotest.(check string) "label inside a loop" "y" ca.ca_label
  | _ -> Alcotest.fail "a branch added inside a loop is Choice_added"

let test_hook_changed_restart () =
  let nw = manifest (replace_fn "Back.start" "h9" (replace_fn "Back.helper" "x2" base_fns)) in
  let p = P.classify (input [ build ~old:(manifest base_fns) nw ]) in
  check_mech "back restarts" (mech p "back") is_restart;
  check_mech "front is hot-patched" (mech p "front") (fun m -> m = P.Hot);
  expect "render" (P.render p) [ "hook: App.Back.start (pool back) changed"; "hook App.Back.start changed (hooks run once, at start)" ]

let test_placement () =
  let new_t = topo ~text:(replace ~sub:"capacity = 8" ~by:"capacity = 2" topology_text) () in
  let p = P.classify (input ~new_t [ build ~old:(manifest base_fns) (manifest base_fns) ]) in
  check_mech "capacity only: a push" (mech p "back") (fun m -> m = P.Placement);
  expect "render" (P.render p) [ "placement: Echo.Server: capacity 8 -> 2"; "topology push only" ];
  let new_t = topo ~text:(replace ~sub:{|labels = ["x"]|} ~by:{|labels = ["x", "y"]|} topology_text) () in
  let p = P.classify (input ~new_t [ build ~old:(manifest base_fns) (manifest base_fns) ]) in
  check_mech "labels: restart" (mech p "back") is_restart;
  check_mech "front untouched" (mech p "front") (fun m -> m = P.Nothing)

let test_derived_caps_widening () =
  let new_derived = [ ("back", ([ "IO.Console"; "IO.FileWrite" ], [])); ("front", ([ "IO.Console" ], [ "Echo.Client" ])) ] in
  let b = build ~old:(manifest base_fns) (manifest (replace_fn "Back.helper" "x2" base_fns)) in
  let p = P.classify (input ~new_derived:(Some new_derived) [ b ]) in
  check_mech "ungranted widening" (mech p "back") is_blocked;
  expect "render" (P.render p) [ "back derived caps (D26) widens to IO.FileWrite: needs --grant-cap IO.FileWrite";
                                 "pool back: caps IO.Console, IO.FileWrite  [changed]" ];
  let p = P.classify (input ~new_derived:(Some new_derived) ~grant:[ "IO.FileWrite" ] [ b ]) in
  check_mech "granted" (mech p "back") (fun m -> m = P.Hot);
  expect "render" (P.render p) [ "granted by --grant-cap" ]

let test_role_closure_widening () =
  let role caps = { Cmd_deploy_hot.role_name = "Echo.Server"; role_caps = caps; role_chains = [] } in
  let old = manifest ~roles:[ role [ "IO.Console" ] ] base_fns in
  let nw = manifest ~roles:[ role [ "IO.Console"; "IO.FileWrite" ] ] (replace_fn "Back.helper" "x2" base_fns) in
  let p = P.classify (input [ build ~old nw ]) in
  check_mech "role widened" (mech p "back") is_blocked;
  expect "render" (P.render p) [ "role Echo.Server's closure widens to IO.FileWrite" ]

let test_runtime_identity_restart () =
  let p = P.classify (input [ build ~old:(manifest base_fns) ~new_runtime:(Some "rt2") (manifest base_fns) ]) in
  check_mech "C runtime changed" (mech p "back") is_restart;
  expect "render" (P.render p) [ "base image of build shared: C runtime rt1 -> rt2" ];
  let p = P.classify (input [ build ~old:(manifest base_fns) (manifest ~abi:"march-hcr-v3;triple=aarch64-unknown-linux-gnu;ptr=8" base_fns) ]) in
  check_mech "ABI changed" (mech p "front") is_restart;
  let p = P.classify (input [ build ~old:(manifest base_fns) (manifest ~target:"linux/amd64" base_fns) ]) in
  expect "target" (P.render p) [ "target linux/arm64 -> linux/amd64" ]

let test_compaction () =
  let b = build ~old:(manifest base_fns) (manifest base_fns) in
  let p = P.classify (input ~compact:true [ b ]) in
  check_mech "--compact" (mech p "back") is_restart;
  expect "render" (P.render p) [ "compaction: --compact; the base image is rebuilt from the current version" ];
  let live n = [ { P.l_node = "back-b1"; l_pool = "back"; l_up = true; l_running = 0; l_offers = []; l_stack = Some n } ] in
  let p = P.classify (input ~live:(live 12) ~compact_after:10 [ b ]) in
  check_mech "above compact_after" (mech p "back") is_restart;
  expect "render" (P.render p) [ "a persisted patch stack of 12 entries is above compact_after = 10" ];
  let p = P.classify (input ~live:(live 3) ~compact_after:10 [ b ]) in
  check_mech "below compact_after" (mech p "back") (fun m -> m = P.Nothing)

let test_six_blocks () =
  let p = P.classify (input [ build ~old:(manifest base_fns) (manifest (replace_fn "Back.helper" "x2" base_fns)) ]) in
  let r = P.render p in
  let headers = [ "1. What changed"; "2. Mechanism and why"; "3. Order and splits"; "4. Drains"; "5. What may be lost";
                  "6. Authority and derived values" ] in
  let positions = List.map (fun h ->
      let n = String.length r and k = String.length h in
      let rec find i = if i + k > n then Alcotest.failf "no %S in:\n%s" h r else if String.sub r i k = h then i else find (i + 1) in
      find 0) headers in
  Alcotest.(check bool) "in order" true (List.sort compare positions = positions)

let () =
  Alcotest.run "deploy-plan" [
    ("mechanism", [
        Alcotest.test_case "first deploy: restart everything" `Quick test_first_deploy;
        Alcotest.test_case "no change: nothing" `Quick test_nothing_changed;
        Alcotest.test_case "functions changed/added/removed: hot patch" `Quick test_hot_patch;
        Alcotest.test_case "a signature change is shown" `Quick test_signature_change_noted;
        Alcotest.test_case "state change: migrate_state, @compat, blocked" `Quick test_migration;
        Alcotest.test_case "message types: loss, migrate_msg, wrong old type" `Quick test_message_types;
        Alcotest.test_case "a breaking protocol change: hot patch + drain, live sessions" `Quick test_protocol_drain;
        Alcotest.test_case "fingerprint moved under the same declaration" `Quick test_fingerprint_moved_same_declaration;
        Alcotest.test_case "a changed hook restarts its pool only" `Quick test_hook_changed_restart;
        Alcotest.test_case "placement: push; labels: restart" `Quick test_placement;
        Alcotest.test_case "C runtime, ABI and target changes restart" `Quick test_runtime_identity_restart;
        Alcotest.test_case "compaction: --compact and compact_after" `Quick test_compaction;
      ]);
    ("protocols", [
        Alcotest.test_case "structure: same, added, removed, breaking, JSON, loops" `Quick test_protocol_structure;
        Alcotest.test_case "an added branch in a monolith: the D21 split" `Quick test_choice_added_monolith_split;
        Alcotest.test_case "an added branch across builds: receivers first" `Quick test_choice_added_order_across_builds;
        Alcotest.test_case "renumbered unlabelled messages" `Quick test_renumbered_wire_tags;
      ]);
    ("authority", [
        Alcotest.test_case "derived caps widening needs --grant-cap (D26)" `Quick test_derived_caps_widening;
        Alcotest.test_case "a role closure widening blocks" `Quick test_role_closure_widening;
      ]);
    ("render", [ Alcotest.test_case "the six blocks of 6.8, in order" `Quick test_six_blocks ]);
  ]
