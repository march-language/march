(** `march --topology <json>`: the compiler's half of a topology app
    (distributed-deploys plan, build steps 7 and 3). It reads a forge topology
    digest (.forge/topology.json), refuses any schema version but 1, checks
    that every name the digest binds is declared (step 7) and has the shape
    its binding needs (step 3: a body's arity and environment, a bound
    actor's `init` and handlers, a hook's signature, a role's grant and a
    pool's reach against its written `caps`), generates `main` when the
    entry module has none, and reports each pool's derived caps and
    initiated roles in `--emit-core-ast`'s JSON as a `topology` object.

    The generated `main` itself is exercised by compiling and running
    examples/topology_app (forge/test/test_topology_run.ml) and by
    test/two_node/cluster_ap_local. *)

let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

let write path content =
  let oc = open_out_bin path in
  output_string oc content;
  close_out oc

let read path =
  let ic = open_in_bin path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  s

(** The entry module. [back] is the body of `mod Back` after its `Env` type;
    [extra] goes at the entry's top level (a hand-written `main`, say). *)
let entry_src ?(back = "") ?(extra = "") ?(needs = "") () =
  Printf.sprintf {|mod App do
  import Other
  needs IO
  needs IO.Console
  needs Session.Live
%s
  @[endpoints]
  protocol Checkout do
    role Ledger needs IO.Console
    order: Client -> Ledger : Int
    receipt: Ledger -> Client : Int
  end

  mod Back do
    needs IO.Console
    needs Session.Live
    type Env = { factor : Int }
%s
  end

  mod Front do
    needs IO
    needs Session.Live
    fn start(io : Cap(IO), node : ClusterNode.ClusterHandle) : Int do
      let _ = task_spawn(fn _ -> buy(io, node))
      0
    end
    fn buy(io : Cap(IO), node : ClusterNode.ClusterHandle) : Int do
      match Checkout_Run.initiate_Client(io, node, fn (s, st) ->
          Checkout_Client.recv_Receipt(s, Checkout_Client.send_Order(s, st, 1), fn (_m, st2) ->
            Checkout_Client.close(s, st2))) do
        Ok(_) -> 1
        Err(_) -> 0
      end
    end
  end
%s
end
|} needs back extra

let hook = {|
    fn start(_c : Cap(IO.Console), _node : ClusterNode.ClusterHandle) : Env do { factor: 10 } end
|}

let serve_one = {|
    fn serve_one(env : Env, s : Cap(Session.Live), _c : Cap(IO.Console), st : Checkout_Ledger.Entry) : Checkout_Ledger.Yield do
      Checkout_Ledger.recv_Order(s, st, fn (n, st1) ->
        Checkout_Ledger.close(s, Checkout_Ledger.send_Receipt(s, st1, n * env.factor)))
    end
|}

let actor = {|
    actor Ledger do
      state { factor : Int }
      init(env : Env) { factor: env.factor }
      on Start(_sid : String, _s : Cap(Session.Live), _c : Cap(IO.Console)) do state end
      on Deliver(_sid : String, _s : Cap(Session.Live), _from : Int, _msg : Bytes, _ep : Int) do state end
      on Cancel(_sid : String, _s : Cap(Session.Live), _role : Int, _cause : String, _ep : Int) do state end
    end
|}

(* A sibling module the entry imports; its declarations arrive wrapped in
   DMod, unlike the entry's flat ones. *)
let other_src = {|mod Other do
  fn hello(n : Int) : Int do n + 1 end
end
|}

let digest ?(version = 1) ?(body = {|"App.Back.serve_one"|}) ?(actor = "null")
    ?(back_start = {|"App.Back.start"|}) ?(caps = "null") ?(isolate = "false") () =
  Printf.sprintf {|{
  "version": %d,
  "env": null,
  "sources": ["topology.toml"],
  "roles": [
    { "name": "Checkout.Ledger", "protocol": "Checkout", "role": "Ledger",
      "body": %s, "actor": %s, "capacity": 4, "place": null, "set": false }
  ],
  "pools": [
    { "name": "back", "start": %s, "serves": ["Checkout.Ledger"], "serves_all": false,
      "initiates": null, "caps": %s, "isolate": %s, "public": [],
      "main": null, "replicas": null, "hosts": [] },
    { "name": "front", "start": "App.Front.start", "serves": [], "serves_all": false,
      "initiates": null, "caps": null, "isolate": false, "public": [],
      "main": null, "replicas": null, "hosts": [] }
  ],
  "drain": { "soft_ms": 1000, "hard_ms": 2000 },
  "backend": null
}
|} version body actor back_start caps isolate

(** Run `march <mode> --topology <digest> app.march` in a scratch dir;
    returns (exit code, stdout, stderr). *)
let run ?(mode = "--check") ?(flags = "") ~src ~digest_text () =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf "compiler not found at %s" compiler_exe;
  let dir = Filename.temp_dir "topology_flag_" "" in
  Fun.protect
    ~finally:(fun () -> ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir))))
    (fun () ->
       write (Filename.concat dir "app.march") src;
       write (Filename.concat dir "other.march") other_src;
       let dpath = Filename.concat dir "topology.json" in
       write dpath digest_text;
       let out = Filename.concat dir "stdout.txt" and err = Filename.concat dir "stderr.txt" in
       let cmd =
         (* [mode] last: `--emit-core-ast` takes the file as its own argument. *)
         Printf.sprintf "%s %s --topology %s %s %s > %s 2> %s"
           (Filename.quote compiler_exe) flags (Filename.quote dpath) mode
           (Filename.quote (Filename.concat dir "app.march")) (Filename.quote out) (Filename.quote err)
       in
       let rc = Sys.command cmd in
       (rc, read out, read err))

let contains hay needle =
  let ln = String.length needle and lh = String.length hay in
  let rec at i = i + ln <= lh && (String.sub hay i ln = needle || at (i + 1)) in
  at 0

let expect_ok (rc, _, err) =
  if rc <> 0 then Alcotest.failf "expected exit 0, got %d:\n%s" rc err;
  if contains err "error" then Alcotest.failf "expected no error:\n%s" err

let expect_error (rc, _, err) msg =
  Alcotest.(check int) "exit 1" 1 rc;
  if not (contains err msg) then Alcotest.failf "expected %S in:\n%s" msg err

let ok_src = entry_src ~back:(hook ^ serve_one) ()

let test_function_role_generates_main () =
  expect_ok (run ~src:ok_src ~digest_text:(digest ()) ())

let test_actor_role_generates_main () =
  expect_ok (run ~src:(entry_src ~back:(hook ^ actor) ())
               ~digest_text:(digest ~body:"null" ~actor:{|"App.Back.Ledger"|} ()) ())

let test_derived_caps_and_initiates () =
  let (rc, out, err) = run ~mode:"--emit-core-ast" ~src:ok_src ~digest_text:(digest ()) () in
  if rc <> 0 then Alcotest.failf "expected exit 0, got %d:\n%s" rc err;
  let j = Yojson.Safe.from_string out in
  let open Yojson.Safe.Util in
  let pools = j |> member "topology" |> member "pools" in
  let strs p k = pools |> member p |> member k |> to_list |> List.map to_string in
  Alcotest.(check (list string)) "back reaches only what it was given" [ "IO.Console" ] (strs "back" "caps");
  Alcotest.(check (list string)) "back initiates nothing" [] (strs "back" "initiates");
  Alcotest.(check (list string)) "front initiates Checkout.Client, through a helper"
    [ "Checkout.Client" ] (strs "front" "initiates");
  Alcotest.(check bool) "main was generated" true
    (j |> member "topology" |> member "generated_main" |> to_bool)

let test_emit_without_topology_has_no_object () =
  if not (Sys.file_exists compiler_exe) then Alcotest.failf "compiler not found";
  let dir = Filename.temp_dir "topology_flag_" "" in
  let f = Filename.concat dir "p.march" in
  write f "mod P do\n  fn main() do () end\nend\n";
  let out = Filename.concat dir "out.json" in
  ignore (Sys.command (Printf.sprintf "%s --emit-core-ast %s > %s 2>/dev/null"
                         (Filename.quote compiler_exe) (Filename.quote f) (Filename.quote out)));
  let j = Yojson.Safe.from_string (read out) in
  ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
  Alcotest.(check bool) "no topology key" true (Yojson.Safe.Util.member "topology" j = `Null)

let test_hand_written_main_warns () =
  let (rc, _, err) =
    run ~src:(entry_src ~back:(hook ^ serve_one) ~extra:"  fn main(c : Cap(IO)) do () end" ())
      ~digest_text:(digest ()) ()
  in
  Alcotest.(check int) "exit 0" 0 rc;
  Alcotest.(check bool) "warns about the escape hatch" true (contains err "has its own `main`, so none is generated")

let test_unbound_name_is_rejected () =
  expect_error
    (run ~src:ok_src ~digest_text:(digest ~body:{|"App.Back.serve_two"|} ~back_start:{|"Other.goodbye"|} ()) ())
    "role \"Checkout.Ledger\": body 'App.Back.serve_two' is not a function in the loaded modules";
  expect_error
    (run ~src:ok_src ~digest_text:(digest ~back_start:{|"Other.goodbye"|} ()) ())
    "pool \"back\": start 'Other.goodbye' is not a function in the loaded modules"

let test_wrong_version_is_rejected () =
  expect_error (run ~src:ok_src ~digest_text:(digest ~version:2 ()) ())
    "topology schema version 2, but this build reads version 1"

let test_missing_file_is_rejected () =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf "compiler not found at %s" compiler_exe;
  let dir = Filename.temp_dir "topology_flag_" "" in
  write (Filename.concat dir "app.march") ok_src;
  let rc =
    Sys.command (Printf.sprintf "%s --check --topology %s %s > /dev/null 2>&1"
                   (Filename.quote compiler_exe)
                   (Filename.quote (Filename.concat dir "nope.json"))
                   (Filename.quote (Filename.concat dir "app.march")))
  in
  ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
  Alcotest.(check int) "exit 1" 1 rc

let test_body_arity () =
  let body = {|
    fn serve_one(env : Env, s : Cap(Session.Live), st : Checkout_Ledger.Entry) : Checkout_Ledger.Yield do
      Checkout_Ledger.recv_Order(s, st, fn (n, st1) ->
        Checkout_Ledger.close(s, Checkout_Ledger.send_Receipt(s, st1, n * env.factor)))
    end
|} in
  expect_error (run ~src:(entry_src ~back:(hook ^ body) ()) ~digest_text:(digest ()) ())
    "body 'App.Back.serve_one' takes 3 parameter(s); a body of this role takes 4: the pool's environment, the session, 1 granted cap(s), and the entry state"

let test_body_env_mismatch () =
  let body = {|
    fn serve_one(env : Int, s : Cap(Session.Live), _c : Cap(IO.Console), st : Checkout_Ledger.Entry) : Checkout_Ledger.Yield do
      Checkout_Ledger.recv_Order(s, st, fn (n, st1) ->
        Checkout_Ledger.close(s, Checkout_Ledger.send_Receipt(s, st1, n * env)))
    end
|} in
  expect_error (run ~src:(entry_src ~back:(hook ^ body) ()) ~digest_text:(digest ()) ())
    "body 'App.Back.serve_one' takes its environment as `Int`, but pool \"back\"'s hook returns `App.Back.Env`"

let test_actor_shape () =
  let bad = {|
    actor Ledger do
      state { factor : Int }
      init(n : Int) { factor: n }
      on Start(_sid : String, _s : Cap(Session.Live), _c : Cap(IO.Console)) do state end
      on Cancel(_sid : String, _s : Cap(Session.Live), _role : Int, _cause : String, _ep : Int) do state end
    end
|} in
  let r = run ~src:(entry_src ~back:(hook ^ bad) ()) ~digest_text:(digest ~body:"null" ~actor:{|"App.Back.Ledger"|} ()) () in
  expect_error r "actor 'App.Back.Ledger''s `init` takes `Int`, but pool \"back\"'s hook returns `App.Back.Env`";
  expect_error r "actor 'App.Back.Ledger' has no `on Deliver` handler"

let test_hook_signature () =
  let h = {|
    fn start(n : Int, _node : ClusterNode.ClusterHandle) : Env do { factor: n } end
|} in
  expect_error (run ~src:(entry_src ~back:(h ^ serve_one) ()) ~digest_text:(digest ()) ())
    "hook 'App.Back.start': parameter `n : Int` is not a capability"

let test_grant_beyond_written_caps () =
  expect_error (run ~src:ok_src ~digest_text:(digest ~caps:{|["IO.Clock"]|} ()) ())
    "role \"Checkout.Ledger\" is granted `IO.Console` (`role Ledger needs ...` in protocol Checkout), beyond pool \"back\"'s written caps [IO.Clock]"

let test_hook_cap_beyond_written_caps () =
  expect_error (run ~src:ok_src ~digest_text:(digest ~caps:{|["IO.FileRead"]|} ()) ())
    "hook 'App.Back.start' takes `Cap(IO.Console)`, beyond the pool's written caps [IO.FileRead]"

let test_reach_beyond_written_caps () =
  (* The hook takes only the handle but prints: its REACH is IO.Console,
     which the pool's written caps do not cover. Found after typechecking. *)
  let h = {|
    fn start(_node : ClusterNode.ClusterHandle) : Env do
      println("hi")
      { factor: 1 }
    end
|} in
  let body = {|
    fn serve_one(env : Env, s : Cap(Session.Live), st : Checkout_Ledger.Entry) : Checkout_Ledger.Yield do
      Checkout_Ledger.recv_Order(s, st, fn (n, st1) ->
        Checkout_Ledger.close(s, Checkout_Ledger.send_Receipt(s, st1, n * env.factor)))
    end
|} in
  let src =
    Str.global_replace (Str.regexp_string "    role Ledger needs IO.Console\n") ""
      (entry_src ~back:(h ^ body) ())
  in
  expect_error (run ~src ~digest_text:(digest ~caps:{|["IO.Clock"]|} ()) ())
    "pool \"back\": its hook App.Back.start reaches `IO.Console`, beyond the pool's written caps [IO.Clock]"

let test_foreign_needs_isolation () =
  let src = Str.global_replace (Str.regexp_string "role Ledger needs IO.Console") "role Ledger needs IO.Foreign" ok_src in
  let d = digest () in
  expect_error (run ~flags:"--topology-isolate-foreign" ~src ~digest_text:d ())
    "role \"Checkout.Ledger\" is granted `IO.Foreign`, but pool \"back\" is not isolated";
  (* Not opted in: no such error (the body's shape is then what fails, if anything). *)
  let (_, _, err) = run ~src ~digest_text:d () in
  Alcotest.(check bool) "only with the flag" false (contains err "is not isolated")

let test_unknown_pool_flag () =
  expect_error (run ~flags:"--topology-pools nope" ~src:ok_src ~digest_text:(digest ()) ())
    "--topology-pools: no pool \"nope\" in the topology"

let tests = [
  Alcotest.test_case "a function role: main is generated and typechecks" `Quick test_function_role_generates_main;
  Alcotest.test_case "an actor role: main is generated and typechecks" `Quick test_actor_role_generates_main;
  Alcotest.test_case "--emit-core-ast reports derived caps and initiates" `Quick test_derived_caps_and_initiates;
  Alcotest.test_case "--emit-core-ast without --topology has no topology key" `Quick test_emit_without_topology_has_no_object;
  Alcotest.test_case "a hand-written main warns and is kept" `Quick test_hand_written_main_warns;
  Alcotest.test_case "an unbound body or hook is an error naming it" `Quick test_unbound_name_is_rejected;
  Alcotest.test_case "schema version 2 is refused" `Quick test_wrong_version_is_rejected;
  Alcotest.test_case "a missing digest file is an error" `Quick test_missing_file_is_rejected;
  Alcotest.test_case "a body with the wrong arity" `Quick test_body_arity;
  Alcotest.test_case "a body whose environment is not the hook's" `Quick test_body_env_mismatch;
  Alcotest.test_case "an actor's init and handlers" `Quick test_actor_shape;
  Alcotest.test_case "a hook parameter that is not a cap" `Quick test_hook_signature;
  Alcotest.test_case "a role grant beyond the pool's written caps" `Quick test_grant_beyond_written_caps;
  Alcotest.test_case "a hook cap beyond the pool's written caps" `Quick test_hook_cap_beyond_written_caps;
  Alcotest.test_case "a hook that reaches beyond the written caps" `Quick test_reach_beyond_written_caps;
  Alcotest.test_case "IO.Foreign in a non-isolated pool, when opted in" `Quick test_foreign_needs_isolation;
  Alcotest.test_case "--topology-pools names a pool that exists" `Quick test_unknown_pool_flag;
]
