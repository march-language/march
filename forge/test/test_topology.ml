(** Tests for forge/lib/topology.ml: the topology file (build step 7 of the
    distributed-deploys plan). Everything here is in-process: the fixture
    project is parsed, never typechecked or compiled, so no toolchain is
    needed. The generator goldens live in topology_golden/; regenerate them
    on purpose with [UPDATE_TOPOLOGY_GOLDEN=<dir>] pointing at the source
    directory, then review the diff. *)

open March_forge

(* ------------------------------------------------------------------ fixture *)

let shop_march = {|mod Shop do
  needs IO
  needs Session.Live

  @[endpoints]
  protocol Checkout do
    order: Client -> Ledger : Int
    receipt: Ledger -> Client : Int
  end

  @[endpoints]
  protocol Thumbs do
    Edge -> Render : Int
    Render -> Edge : Int
  end

  @[endpoints]
  protocol Quotes do
    ask: Client -> Server : Int
    reply: Server -> Client : Int
  end

  mod Ledger do
    fn serve_one(env, s, st) do 0 end
  end

  mod Render do
    fn render_one(env, s, st) do 0 end
  end

  mod Edge do
    fn start(c, node) do
      let _ = helper(c)
      1
    end
    pfn helper(c) do
      Checkout_Run.initiate_Client(c, 1, fn s -> s)
    end
  end

  mod Reports do
    fn run(env, s, st) do 0 end
  end

  actor ServerActor do
    state { n : Int }
    init { n: 0 }
  end

  fn main(c : Cap(IO)) do 0 end
end
|}

let base_toml = {|[roles]
"Checkout.Ledger" = { body = "Shop.Ledger.serve_one", capacity = 64 }
"Thumbs.Render"   = { body = "Shop.Render.render_one", capacity = 8, place = { on = "gpu" } }
"Quotes.Server"   = { actor = "Shop.ServerActor" }

[pool.edge]
start  = "Shop.Edge.start"
public = [443]

[pool.ledger]
serves = ["Checkout.Ledger", "Quotes.Server"]
caps   = ["IO.FileWrite"]

[pool.imaging]
serves  = ["Thumbs.Render"]
isolate = true

[drain]
soft_ms = 30000
hard_ms = 120000
|}

let prod_toml = {|[backend]
kind = "ssh"

[pool.edge]
hosts = ["root@web-1"]

[pool.imaging]
hosts = [{ host = "root@render-1", labels = ["gpu"] }, "root@render-2"]

[pool.ledger]
hosts = ["root@db-1"]
|}

let write path content =
  let oc = open_out_bin path in
  output_string oc content;
  close_out oc

let read path =
  let ic = open_in_bin path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  s

(** A scratch project: forge.toml, lib/shop.march, the two topology files. *)
let with_project ?(base = base_toml) ?(prod = prod_toml) f =
  let root = Filename.temp_dir "forge_topology_" "" in
  Fun.protect
    ~finally:(fun () -> ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote root))))
    (fun () ->
       write (Filename.concat root "forge.toml")
         "[package]\nname = \"shop\"\nversion = \"0.1.0\"\ntype = \"app\"\n";
       Sys.mkdir (Filename.concat root "lib") 0o755;
       write (Filename.concat root "lib/shop.march") shop_march;
       write (Filename.concat root "topology.toml") base;
       write (Filename.concat root "topology.prod.toml") prod;
       f root)

let index_of_shop () =
  let idx = Topology.empty_index () in
  let lexbuf = Lexing.from_string shop_march in
  let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  Topology.index_module idx m;
  idx

let load_ok ?env root =
  match Topology.load ~root ?env () with
  | Ok t -> t
  | Error ds -> Alcotest.failf "load failed:\n%s" (String.concat "\n" (List.map Topology.render_diag ds))

let diags_of ?(base = base_toml) ?(prod = prod_toml) ?env () =
  with_project ~base ~prod (fun root ->
      match Topology.load ~root ?env () with
      | Error ds -> List.map Topology.render_diag ds
      | Ok t -> List.map Topology.render_diag (Topology.check ~index:(index_of_shop ()) t))

let errors_of ?base ?prod ?env () =
  with_project ?base ?prod (fun root ->
      match Topology.load ~root ?env () with
      | Error ds -> List.map Topology.render_diag ds
      | Ok t ->
        Topology.check ~index:(index_of_shop ()) t
        |> List.filter (fun (d : Topology.diag) -> d.Topology.severity = Topology.Error)
        |> List.map Topology.render_diag)

let has_line ~needle lines =
  List.exists (fun l ->
      let ln = String.length needle and ll = String.length l in
      let rec at i = i + ln <= ll && (String.sub l i ln = needle || at (i + 1)) in
      at 0)
    lines

let check_has ~what needle lines =
  if not (has_line ~needle lines) then
    Alcotest.failf "%s: expected a line containing %S, got:\n%s" what needle (String.concat "\n" lines)

let check_absent ~what needle lines =
  if has_line ~needle lines then
    Alcotest.failf "%s: did not expect a line containing %S, got:\n%s" what needle (String.concat "\n" lines)

(* ---------------------------------------------------------- parse + merge *)

let test_base_parses () =
  with_project (fun root ->
      let t = load_ok root in
      Alcotest.(check int) "roles" 3 (List.length t.Topology.roles);
      Alcotest.(check (list string)) "pools" [ "edge"; "ledger"; "imaging" ]
        (List.map (fun p -> p.Topology.pool_name) t.Topology.pools);
      let ledger = List.find (fun r -> r.Topology.role_name = "Checkout.Ledger") t.Topology.roles in
      Alcotest.(check (option string)) "body" (Some "Shop.Ledger.serve_one") ledger.Topology.body;
      Alcotest.(check (option int)) "capacity" (Some 64) ledger.Topology.capacity;
      let render = List.find (fun r -> r.Topology.role_name = "Thumbs.Render") t.Topology.roles in
      (match render.Topology.place with
       | Some { Topology.on = Some "gpu"; count = None } -> ()
       | _ -> Alcotest.fail "place = { on = \"gpu\" } expected");
      let quotes = List.find (fun r -> r.Topology.role_name = "Quotes.Server") t.Topology.roles in
      Alcotest.(check (option string)) "actor" (Some "Shop.ServerActor") quotes.Topology.actor;
      let imaging = List.find (fun p -> p.Topology.pool_name = "imaging") t.Topology.pools in
      Alcotest.(check bool) "isolate" true imaging.Topology.isolate;
      Alcotest.(check int) "no hosts in the base" 0 (List.length imaging.Topology.hosts);
      let edge = List.find (fun p -> p.Topology.pool_name = "edge") t.Topology.pools in
      Alcotest.(check (list int)) "public" [ 443 ] edge.Topology.public;
      (match t.Topology.drain with
       | Some { Topology.soft_ms = Some 30000; hard_ms = Some 120000 } -> ()
       | _ -> Alcotest.fail "drain");
      Alcotest.(check (option string)) "no env" None t.Topology.env)

let test_overlay_merges () =
  with_project (fun root ->
      let t = load_ok ~env:"prod" root in
      Alcotest.(check (option string)) "env" (Some "prod") t.Topology.env;
      Alcotest.(check (list string)) "sources" [ "topology.toml"; "topology.prod.toml" ]
        (List.map Filename.basename t.Topology.sources);
      let imaging = List.find (fun p -> p.Topology.pool_name = "imaging") t.Topology.pools in
      Alcotest.(check bool) "base key kept through the merge" true imaging.Topology.isolate;
      Alcotest.(check (list string)) "hosts from the overlay" [ "root@render-1"; "root@render-2" ]
        (List.map (fun h -> h.Topology.host) imaging.Topology.hosts);
      Alcotest.(check (list string)) "labels" [ "gpu" ] (List.hd imaging.Topology.hosts).Topology.labels;
      (match t.Topology.backend with
       | Some { Topology.kind = Some "ssh"; _ } -> ()
       | _ -> Alcotest.fail "backend from the overlay"))

let test_overlay_arrays_replace_tables_merge () =
  (* An array in the overlay replaces; an inline table deep-merges. *)
  let base = base_toml in
  let prod = {|[pool.edge]
public = [8443]

[roles]
"Thumbs.Render" = { place = { count = 1 } }
|} in
  with_project ~base ~prod (fun root ->
      let t = load_ok ~env:"prod" root in
      let edge = List.find (fun p -> p.Topology.pool_name = "edge") t.Topology.pools in
      Alcotest.(check (list int)) "array replaced" [ 8443 ] edge.Topology.public;
      Alcotest.(check (option string)) "sibling key kept" (Some "Shop.Edge.start") edge.Topology.start;
      let render = List.find (fun r -> r.Topology.role_name = "Thumbs.Render") t.Topology.roles in
      Alcotest.(check (option string)) "body kept through the table merge"
        (Some "Shop.Render.render_one") render.Topology.body;
      (match render.Topology.place with
       | Some { Topology.on = Some "gpu"; count = Some 1 } -> ()
       | _ -> Alcotest.fail "place deep-merged: on from the base, count from the overlay"))

let test_missing_overlay_is_an_error () =
  with_project (fun root ->
      match Topology.load ~root ~env:"staging" () with
      | Ok _ -> Alcotest.fail "expected an error"
      | Error ds ->
        check_has ~what:"missing overlay" "no overlay topology.staging.toml for environment 'staging'"
          (List.map Topology.render_diag ds))

(* ------------------------------------------------------------ unknown keys *)

let test_unknown_keys_are_errors_with_lines () =
  let base = {|[roles]
"Checkout.Ledger" = { body = "Shop.Ledger.serve_one", capcity = 64 }
"Thumbs.Render"   = { body = "Shop.Render.render_one", place = { onn = "gpu" } }

[pool.edge]
start  = "Shop.Edge.start"
publik = [443]

[pool.imaging]
serves = ["Thumbs.Render"]
hosts = [{ host = "a", label = ["gpu"] }]

[drain]
soft = 1

[backend]
kind = "ssh"
region = "x"

[nonsense]
x = 1
|} in
  let ds = diags_of ~base () in
  check_has ~what:"role key" "topology.toml:2: unknown key 'capcity' in [roles] \"Checkout.Ledger\"" ds;
  check_has ~what:"place key" "topology.toml:3: unknown key 'onn' in [roles] \"Thumbs.Render\" place" ds;
  check_has ~what:"pool key" "topology.toml:7: unknown key 'publik' in [pool.edge]" ds;
  check_has ~what:"host key" "topology.toml:11: unknown key 'label' in [pool.imaging] hosts" ds;
  check_has ~what:"drain key" "topology.toml:14: unknown key 'soft' in [drain]" ds;
  check_has ~what:"backend key" "topology.toml:18: unknown key 'region' in [backend]" ds;
  check_has ~what:"section" "topology.toml:20: unknown section [nonsense]" ds

let test_overlay_unknown_key_names_the_overlay () =
  let prod = {|[pool.edge]
hosts = ["root@web-1"]
replica = 2
|} in
  let ds = diags_of ~prod ~env:"prod" () in
  check_has ~what:"overlay line" "topology.prod.toml:3: unknown key 'replica' in [pool.edge]" ds

let test_malformed_toml_reports_line () =
  let base = "[roles]\n\"Checkout.Ledger\" = { body = \n" in
  let ds = diags_of ~base () in
  check_has ~what:"parse error" "topology.toml:2:" ds

let test_value_shape_errors () =
  let base = {|[roles]
"Checkout.Ledger" = { body = "Shop.Ledger.serve_one", capacity = "lots" }
"Thumbs.Render" = { body = "Shop.Render.render_one", actor = "Shop.ServerActor" }
"Quotes.Server" = { capacity = 1 }
"BadKey" = { body = "x" }

[pool.edge]
serves = "Checkout.Ledger"
public = [70000]
isolate = "yes"

[drain]
soft_ms = 5000
hard_ms = 1000
|} in
  let ds = diags_of ~base () in
  check_has ~what:"capacity" "topology.toml:2: role \"Checkout.Ledger\": `capacity` must be a positive integer" ds;
  check_has ~what:"body+actor" "topology.toml:3: role \"Thumbs.Render\" binds both `body` and `actor`" ds;
  check_has ~what:"no binding" "topology.toml:4: role \"Quotes.Server\" needs a `body = \"Mod.fn\"` or an `actor = \"Mod.Actor\"` binding" ds;
  check_has ~what:"key shape" "topology.toml:5: role key \"BadKey\" must be \"Protocol.Role\"" ds;
  check_has ~what:"serves string" "topology.toml:8: [pool.edge]: `serves` is an array of \"Protocol.Role\" names, or \"*\"" ds;
  check_has ~what:"port" "topology.toml:9: [pool.edge]: `public` must be an array of ports (1-65535)" ds;
  check_has ~what:"isolate" "topology.toml:10: [pool.edge]: `isolate` must be true or false" ds;
  check_has ~what:"drain order" "topology.toml:12: [drain] `hard_ms` must be at least `soft_ms`" ds

(* ------------------------------------------------------------------- check *)

let test_fixture_checks_clean () =
  let errs = errors_of ~env:"prod" () in
  Alcotest.(check (list string)) "no errors" [] errs;
  let ds = diags_of ~env:"prod" () in
  (* D25: Thumbs has two unlabelled steps; Checkout and Quotes are labelled. *)
  check_has ~what:"D25" "topology.toml:3: warning: protocol 'Thumbs' has 2 unlabelled steps" ds;
  check_absent ~what:"labelled protocol" "protocol 'Checkout' has" ds

let test_unbound_served_role () =
  let base = base_toml ^ "\n[pool.extra]\nserves = [\"Checkout.Client\"]\n" in
  let errs = errors_of ~base () in
  check_has ~what:"unbound" "topology.toml:23: [pool.extra] serves \"Checkout.Client\", which has no binding in [roles]" errs

let test_role_nobody_serves () =
  let base = {|[roles]
"Checkout.Ledger" = { body = "Shop.Ledger.serve_one" }
"Thumbs.Render"   = { body = "Shop.Render.render_one" }

[pool.ledger]
serves = ["Checkout.Ledger"]
|} in
  let errs = errors_of ~base () in
  check_has ~what:"unserved" "topology.toml:3: \"Thumbs.Render\" is bound but no pool serves it" errs

let test_bindings_must_resolve () =
  let base = {|[roles]
"Checkout.Ledger" = { body = "Shop.Ledger.serve_two" }
"Quotes.Server"   = { actor = "Shop.NoSuchActor" }
"Checkout.Cashier" = { body = "Shop.Ledger.serve_one" }
"Nope.Role"       = { body = "Shop.Ledger.serve_one" }

[pool.all]
serves = "*"
start = "Shop.Edge.begin"
initiates = ["Checkout.Nobody"]
|} in
  let errs = errors_of ~base () in
  check_has ~what:"body" "topology.toml:2: \"Checkout.Ledger\": body 'Shop.Ledger.serve_two' is not a function declared in the project" errs;
  check_has ~what:"actor" "topology.toml:3: \"Quotes.Server\": actor 'Shop.NoSuchActor' is not an actor declared in the project" errs;
  check_has ~what:"role" "topology.toml:4: \"Checkout.Cashier\": protocol 'Checkout' has no role 'Cashier' (its roles: Client, Ledger)" errs;
  check_has ~what:"protocol" "topology.toml:5: \"Nope.Role\": no protocol named 'Nope' is declared in the project" errs;
  check_has ~what:"start" "topology.toml:9: [pool.all] start = \"Shop.Edge.begin\" is not a function declared in the project" errs;
  check_has ~what:"initiates" "topology.toml:10: [pool.all] initiates \"Checkout.Nobody\", which is not a role of any declared protocol" errs

let test_serves_star_expands () =
  let base = {|[roles]
"Checkout.Ledger" = { body = "Shop.Ledger.serve_one" }
"Quotes.Server"   = { actor = "Shop.ServerActor" }

[pool.app]
serves = "*"
|} in
  with_project ~base (fun root ->
      let t = load_ok root in
      let app = List.hd t.Topology.pools in
      Alcotest.(check bool) "serves_all" true app.Topology.serves_all;
      Alcotest.(check (list string)) "expanded" [ "Checkout.Ledger"; "Quotes.Server" ] app.Topology.serves;
      Alcotest.(check (list string)) "clean" []
        (List.map Topology.render_diag
           (List.filter (fun (d : Topology.diag) -> d.Topology.severity = Topology.Error)
              (Topology.check ~index:(index_of_shop ()) t))))

let test_place_on_label_must_exist () =
  let prod = {|[pool.edge]
hosts = ["root@web-1"]

[pool.imaging]
hosts = [{ host = "root@render-1", labels = ["cpu"] }, "root@render-2"]

[pool.ledger]
hosts = ["root@db-1"]
|} in
  let errs = errors_of ~prod ~env:"prod" () in
  check_has ~what:"label" "topology.toml:3: \"Thumbs.Render\": place.on = \"gpu\", but no host of [pool.imaging] carries that label" errs;
  (* Without hosts (the base alone) the label check has nothing to check. *)
  Alcotest.(check (list string)) "base alone is clean" [] (errors_of ())

let test_place_count_bounded_by_hosts () =
  let base = {|[roles]
"Checkout.Ledger" = { body = "Shop.Ledger.serve_one", place = { count = 3 } }
"Thumbs.Render"   = { body = "Shop.Render.render_one", place = { on = "gpu", count = 2 } }

[pool.app]
serves = "*"
|} in
  let prod = {|[pool.app]
hosts = [{ host = "a", labels = ["gpu"] }, "b"]
|} in
  let errs = errors_of ~base ~prod ~env:"prod" () in
  check_has ~what:"count" "topology.toml:2: \"Checkout.Ledger\": place.count = 3, but only 2 hosts serve it" errs;
  check_has ~what:"count with on" "topology.toml:3: \"Thumbs.Render\": place.count = 2, but only 1 host carries the label \"gpu\"" errs

let test_isolate_pool_shares_no_role () =
  let base = base_toml ^ "\n[pool.also]\nserves = [\"Thumbs.Render\"]\n" in
  let errs = errors_of ~base () in
  check_has ~what:"isolate" "topology.toml:16: [pool.imaging] is isolated but \"Thumbs.Render\" is also served by [pool.also]" errs

let test_written_initiates_is_an_upper_limit () =
  (* D22: Edge's code reaches Checkout_Run.initiate_Client through a helper;
     a written `initiates` that omits it is an error, one that lists it is fine. *)
  let narrow = base_toml ^ "\n[pool.edge2]\nstart = \"Shop.Edge.start\"\ninitiates = [\"Quotes.Client\"]\n" in
  let errs = errors_of ~base:narrow () in
  check_has ~what:"narrow" "topology.toml:24: [pool.edge2] code initiates \"Checkout.Client\" (in Shop.Edge.helper) but `initiates` does not list it" errs;
  let wide = base_toml ^ "\n[pool.edge2]\nstart = \"Shop.Edge.start\"\ninitiates = [\"Checkout.Client\"]\n" in
  Alcotest.(check (list string)) "listed" [] (errors_of ~base:wide ())

let test_derived_initiates_and_connectivity () =
  with_project (fun root ->
      let t = load_ok ~env:"prod" root in
      let idx = index_of_shop () in
      let edge = List.find (fun p -> p.Topology.pool_name = "edge") t.Topology.pools in
      Alcotest.(check (list (pair string string))) "derived through the helper"
        [ ("Checkout.Client", "Shop.Edge.helper") ] (Topology.derived_initiates idx t edge);
      let edges = Topology.connectivity idx t in
      Alcotest.(check (list (pair string string))) "edge talks to ledger only"
        [ ("edge", "ledger") ] (List.map (fun e -> (e.Topology.e_from, e.Topology.e_to)) edges);
      Alcotest.(check (list string)) "over Checkout" [ "Checkout" ] (List.hd edges).Topology.e_protocols)

let test_main_escape_hatch_warns () =
  let base = base_toml ^ "\n[pool.legacy]\nmain = \"src/legacy_main.march\"\n" in
  let ds = diags_of ~base () in
  check_has ~what:"main" "topology.toml:23: warning: [pool.legacy] main = \"src/legacy_main.march\": a hand-written entry gives up level-0 composition" ds;
  Alcotest.(check (list string)) "not an error" [] (errors_of ~base ())

(* --------------------------------------------------------- digest + export *)

let test_digest_round_trips () =
  with_project (fun root ->
      let t = load_ok ~env:"prod" root in
      let path = Topology.write_digest ~root t in
      Alcotest.(check string) "path" (Filename.concat (Filename.concat root ".forge") "topology.json") path;
      let json = Yojson.Safe.from_file path in
      Alcotest.(check int) "version" 1 (Yojson.Safe.Util.(to_int (member "version" json)));
      (match Topology.read_digest path with
       | Error m -> Alcotest.fail m
       | Ok t' ->
         Alcotest.(check string) "digest(read(digest)) = digest"
           (Yojson.Safe.to_string (Topology.digest_json t))
           (Yojson.Safe.to_string (Topology.digest_json t')));
      (* The export carries the digest fields plus the derived facts, and
         reads back into the same digest. *)
      let ex = Topology.export_json ~index:(index_of_shop ()) t in
      (match Topology.export_of_json ex with
       | Error m -> Alcotest.fail m
       | Ok e ->
         Alcotest.(check string) "export round-trips the digest"
           (Yojson.Safe.to_string (Topology.digest_json t))
           (Yojson.Safe.to_string (Topology.digest_json e.Topology.topo));
         Alcotest.(check int) "one edge" 1 (List.length e.Topology.edges);
         Alcotest.(check int) "default cluster port" 7946 e.Topology.port);
      let module U = Yojson.Safe.Util in
      let derived = U.member "derived" ex in
      Alcotest.(check (list string)) "derived initiates" [ "Checkout.Client" ]
        (List.map U.to_string (U.to_list (U.member "initiates" (U.member "edge" derived))));
      Alcotest.(check bool) "caps derivation is deferred to the compiler"
        true (U.member "caps" (U.member "edge" derived) = `Null))

let test_read_digest_rejects_other_versions () =
  let path = Filename.temp_file "topology" ".json" in
  write path "{\"version\": 2, \"roles\": [], \"pools\": []}";
  (match Topology.read_digest path with
   | Ok _ -> Alcotest.fail "version 2 accepted"
   | Error m -> check_has ~what:"version" "topology schema version 2, but this build reads version 1" [ m ]);
  write path "{\"roles\": []}";
  (match Topology.read_digest path with
   | Ok _ -> Alcotest.fail "missing version accepted"
   | Error m -> check_has ~what:"missing" "missing \"version\" (expected 1)" [ m ]);
  Sys.remove path

let test_unresolved_names_for_the_compiler () =
  with_project (fun root ->
      let t = load_ok root in
      let idx = index_of_shop () in
      Alcotest.(check (list string)) "all bound" [] (Topology.unresolved_names ~index:idx t);
      let t' = { t with Topology.roles =
                          List.map (fun r -> if r.Topology.role_name = "Checkout.Ledger"
                                     then { r with Topology.body = Some "Shop.Ledger.gone" } else r) t.Topology.roles } in
      check_has ~what:"unbound" "role \"Checkout.Ledger\": body 'Shop.Ledger.gone' is not a function in the loaded modules"
        (Topology.unresolved_names ~index:idx t'))

(* ---------------------------------------------------------------- the gate *)

let test_gate () =
  with_project (fun root ->
      let proj = match Project.load_from_dir root with Ok p -> p | Error m -> Alcotest.fail m in
      (match Topology.gate ~proj () with
       | Ok () -> ()
       | Error m -> Alcotest.fail m);
      Alcotest.(check bool) "digest written" true (Sys.file_exists (Topology.digest_file ~root));
      (* A prod overlay applies when named and present; an unknown env name
         falls back to the base rather than failing a build. *)
      (match Topology.gate ~env:"prod" ~proj () with Ok () -> () | Error m -> Alcotest.fail m);
      let d = Topology.read_digest (Topology.digest_file ~root) in
      (match d with
       | Ok t -> Alcotest.(check (option string)) "env applied" (Some "prod") t.Topology.env
       | Error m -> Alcotest.fail m);
      (match Topology.gate ~env:"nowhere" ~proj () with Ok () -> () | Error m -> Alcotest.fail m);
      write (Filename.concat root "topology.toml") (base_toml ^ "\n[pool.x]\nserves = [\"Nope.Nope\"]\n");
      (match Topology.gate ~proj () with
       | Ok () -> Alcotest.fail "expected the gate to fail"
       | Error m -> Alcotest.(check string) "message" "topology check failed (1 error)" m);
      Sys.remove (Filename.concat root "topology.toml");
      (match Topology.gate ~proj () with Ok () -> () | Error m -> Alcotest.failf "no topology should be a no-op: %s" m))

(* -------------------------------------------------------------- generators *)

let golden_dir = "topology_golden"

let check_golden ~name (files : (string * string) list) =
  let actual =
    String.concat "" (List.map (fun (n, c) ->
        Printf.sprintf "# ==> %s <==\n%s%s" n c
          (if c <> "" && c.[String.length c - 1] = '\n' then "" else "\n")) files)
  in
  match Sys.getenv_opt "UPDATE_TOPOLOGY_GOLDEN" with
  | Some dir -> write (Filename.concat dir (name ^ ".expected")) actual
  | None ->
    (* Under `dune build @runtest` the goldens are staged next to the exe
       (the `deps` in forge/test/dune); a direct run of the built exe finds
       them in the source tree instead. *)
    let path =
      let staged = Filename.concat golden_dir (name ^ ".expected") in
      if Sys.file_exists staged then staged
      else
        Filename.concat
          (Filename.concat (Filename.dirname Sys.executable_name) "../../../../forge/test/topology_golden")
          (name ^ ".expected")
    in
    if not (Sys.file_exists path) then Alcotest.failf "no golden %s; run with UPDATE_TOPOLOGY_GOLDEN=<dir>" path;
    let expected = read path in
    if expected <> actual then
      Alcotest.failf "%s differs from %s.\n--- expected\n%s\n--- actual\n%s" name path expected actual

let with_export f =
  with_project (fun root ->
      let t = load_ok ~env:"prod" root in
      match Topology.export_of_json (Topology.export_json ~index:(index_of_shop ()) t) with
      | Error m -> Alcotest.fail m
      | Ok ex -> f ex)

let test_gen_systemd () = with_export (fun ex -> check_golden ~name:"systemd" (Topology.Gen.systemd ~project:"shop" ex))
let test_gen_ufw () = with_export (fun ex -> check_golden ~name:"ufw" (Topology.Gen.ufw ex))
let test_gen_do_firewall () = with_export (fun ex -> check_golden ~name:"do-firewall" (Topology.Gen.do_firewall ex))
let test_gen_compose () = with_export (fun ex -> check_golden ~name:"compose" (Topology.Gen.compose ~project:"shop" ex))

let test_gen_builtin_names () =
  with_export (fun ex ->
      List.iter (fun t ->
          Alcotest.(check bool) t true (Topology.Gen.builtin ~project:"shop" t ex <> None))
        Topology.Gen.builtins;
      Alcotest.(check bool) "unknown" true (Topology.Gen.builtin ~project:"shop" "k8s" ex = None))

let test_gen_external_plugin () =
  (* forge-topology-<target> on PATH is fed the export JSON on stdin. *)
  let dir = Filename.temp_dir "forge_topology_plugin_" "" in
  let exe = Filename.concat dir "forge-topology-echo" in
  let out = Filename.concat dir "seen.json" in
  write exe (Printf.sprintf "#!/bin/sh\ncat > %s\n" (Filename.quote out));
  Unix.chmod exe 0o755;
  let old_path = try Sys.getenv "PATH" with Not_found -> "" in
  Unix.putenv "PATH" (dir ^ ":" ^ old_path);
  Fun.protect
    ~finally:(fun () ->
        Unix.putenv "PATH" old_path;
        ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir))))
    (fun () ->
       (match Cli_ext.external_subcommand ~known:Topology.Gen.builtins ~argv1:"topology-echo"
                ~path_lookup:Topology.Gen.path_lookup with
        | Some p -> Alcotest.(check string) "found on PATH" exe p
        | None -> Alcotest.fail "plugin not found on PATH");
       Alcotest.(check bool) "a built-in name never resolves to a plugin" true
         (Cli_ext.external_subcommand ~known:Topology.Gen.builtins ~argv1:"systemd"
            ~path_lookup:Topology.Gen.path_lookup = None);
       with_project (fun root ->
           let t = load_ok ~env:"prod" root in
           let json = Topology.export_json ~index:(index_of_shop ()) t in
           let rc = Topology.Gen.run_external exe json in
           Alcotest.(check int) "exit code" 0 rc;
           let seen = Yojson.Safe.from_file out in
           Alcotest.(check string) "the plugin saw the export"
             (Yojson.Safe.to_string json) (Yojson.Safe.to_string seen)))

let tests = [
  "topology", [
    Alcotest.test_case "base file parses into roles, pools, drain" `Quick test_base_parses;
    Alcotest.test_case "overlay: hosts and backend merge in" `Quick test_overlay_merges;
    Alcotest.test_case "overlay: arrays replace, inline tables deep-merge" `Quick test_overlay_arrays_replace_tables_merge;
    Alcotest.test_case "a named overlay that does not exist is an error" `Quick test_missing_overlay_is_an_error;
    Alcotest.test_case "unknown keys and sections are errors with file:line" `Quick test_unknown_keys_are_errors_with_lines;
    Alcotest.test_case "an unknown key in the overlay names the overlay" `Quick test_overlay_unknown_key_names_the_overlay;
    Alcotest.test_case "malformed TOML reports its line" `Quick test_malformed_toml_reports_line;
    Alcotest.test_case "value shapes: capacity, body+actor, key format, serves, ports, drain" `Quick test_value_shape_errors;
    Alcotest.test_case "the fixture checks clean, with the D25 warning" `Quick test_fixture_checks_clean;
    Alcotest.test_case "a served role with no [roles] binding" `Quick test_unbound_served_role;
    Alcotest.test_case "a bound role nobody serves" `Quick test_role_nobody_serves;
    Alcotest.test_case "body/actor/start/role/protocol names must resolve" `Quick test_bindings_must_resolve;
    Alcotest.test_case "serves = \"*\" expands to every bound role" `Quick test_serves_star_expands;
    Alcotest.test_case "place.on names a label some host carries" `Quick test_place_on_label_must_exist;
    Alcotest.test_case "place.count is bounded by the (labelled) hosts" `Quick test_place_count_bounded_by_hosts;
    Alcotest.test_case "an isolated pool shares no role" `Quick test_isolate_pool_shares_no_role;
    Alcotest.test_case "a written initiates is an upper limit on the code (D22)" `Quick test_written_initiates_is_an_upper_limit;
    Alcotest.test_case "derived initiates through a helper; connectivity graph" `Quick test_derived_initiates_and_connectivity;
    Alcotest.test_case "the main escape hatch warns" `Quick test_main_escape_hatch_warns;
    Alcotest.test_case "digest and export round-trip" `Quick test_digest_round_trips;
    Alcotest.test_case "read_digest rejects any version but 1" `Quick test_read_digest_rejects_other_versions;
    Alcotest.test_case "unresolved_names (the compiler's --topology check)" `Quick test_unresolved_names_for_the_compiler;
    Alcotest.test_case "the build/run/deploy gate" `Quick test_gate;
    Alcotest.test_case "gen systemd golden" `Quick test_gen_systemd;
    Alcotest.test_case "gen ufw golden" `Quick test_gen_ufw;
    Alcotest.test_case "gen do-firewall golden" `Quick test_gen_do_firewall;
    Alcotest.test_case "gen compose golden" `Quick test_gen_compose;
    Alcotest.test_case "every built-in name resolves; unknown ones do not" `Quick test_gen_builtin_names;
    Alcotest.test_case "forge-topology-<target> plugin on PATH gets the export on stdin" `Quick test_gen_external_plugin;
  ];
]

let () = Alcotest.run "forge-topology" tests
