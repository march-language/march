(** `march --topology <json>`: the compiler's half of build step 7 of the
    distributed-deploys plan. It reads a forge topology digest
    (.forge/topology.json), refuses any schema version but 1, and checks that
    every name the digest binds is declared in the loaded modules. Nothing
    else happens yet: the generated `main` (step 3), role grants (step 4)
    and the derived caps are later steps, so with a valid digest `--check`
    behaves exactly as without the flag. *)

let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

let write path content =
  let oc = open_out_bin path in
  output_string oc content;
  close_out oc

let entry_src = {|mod App do
  import Other
  needs IO
  needs Session.Live

  @[endpoints]
  protocol Checkout do
    order: Client -> Ledger : Int
    receipt: Ledger -> Client : Int
  end

  mod Ledger do
    fn serve_one(_env : Int, _s : Int, _st : Int) : Int do 0 end
  end

  actor ServerActor do
    state { n : Int }
    init { n: 0 }
  end

  fn start(c : Int) : Int do Other.hello(c) end

  fn main(c : Cap(IO)) do
    let _ = Other.hello(1)
    ()
  end
end
|}

(* A sibling module the entry imports; the resolver loads it from the
   entry's directory and its declarations arrive wrapped in DMod, unlike the
   entry's flat ones. *)
let other_src = {|mod Other do
  fn hello(n : Int) : Int do n + 1 end
end
|}

let digest ~version ~body ~actor ~start =
  Printf.sprintf {|{
  "version": %d,
  "env": null,
  "sources": ["topology.toml"],
  "roles": [
    { "name": "Checkout.Ledger", "protocol": "Checkout", "role": "Ledger",
      "body": %s, "actor": %s, "capacity": null, "place": null, "set": false }
  ],
  "pools": [
    { "name": "app", "start": %s, "serves": ["Checkout.Ledger"], "serves_all": true,
      "initiates": null, "caps": null, "isolate": false, "public": [],
      "main": null, "replicas": null, "hosts": [] }
  ],
  "drain": null,
  "backend": null
}
|} version body actor start

let json_str s = Printf.sprintf "%S" s

(** Run `march --check --topology <digest> app.march` in a scratch dir;
    returns (exit code, stderr). *)
let run ~digest_text =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf "compiler not found at %s" compiler_exe;
  let dir = Filename.temp_dir "topology_flag_" "" in
  Fun.protect
    ~finally:(fun () -> ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir))))
    (fun () ->
       write (Filename.concat dir "app.march") entry_src;
       write (Filename.concat dir "other.march") other_src;
       let dpath = Filename.concat dir "topology.json" in
       write dpath digest_text;
       let err = Filename.concat dir "stderr.txt" in
       let cmd =
         Printf.sprintf "%s --check --topology %s %s > /dev/null 2> %s"
           (Filename.quote compiler_exe) (Filename.quote dpath)
           (Filename.quote (Filename.concat dir "app.march")) (Filename.quote err)
       in
       let rc = Sys.command cmd in
       let ic = open_in_bin err in
       let text = really_input_string ic (in_channel_length ic) in
       close_in ic;
       (rc, text))

let contains hay needle =
  let ln = String.length needle and lh = String.length hay in
  let rec at i = i + ln <= lh && (String.sub hay i ln = needle || at (i + 1)) in
  at 0

let test_valid_digest_is_accepted () =
  let rc, err =
    run ~digest_text:(digest ~version:1 ~body:(json_str "App.Ledger.serve_one") ~actor:"null"
                        ~start:(json_str "Other.hello"))
  in
  if rc <> 0 then Alcotest.failf "expected exit 0, got %d:\n%s" rc err;
  Alcotest.(check bool) "no topology diagnostics" false (contains err "topology")

let test_actor_binding_resolves () =
  let rc, err =
    run ~digest_text:(digest ~version:1 ~body:"null" ~actor:(json_str "App.ServerActor")
                        ~start:(json_str "App.start"))
  in
  if rc <> 0 then Alcotest.failf "expected exit 0, got %d:\n%s" rc err

let test_unbound_name_is_rejected () =
  let rc, err =
    run ~digest_text:(digest ~version:1 ~body:(json_str "App.Ledger.serve_two") ~actor:"null"
                        ~start:(json_str "Other.goodbye"))
  in
  Alcotest.(check int) "exit 1" 1 rc;
  Alcotest.(check bool) "names the body" true
    (contains err "role \"Checkout.Ledger\": body 'App.Ledger.serve_two' is not a function in the loaded modules");
  Alcotest.(check bool) "names the hook" true
    (contains err "pool \"app\": start 'Other.goodbye' is not a function in the loaded modules")

let test_wrong_version_is_rejected () =
  let rc, err =
    run ~digest_text:(digest ~version:2 ~body:(json_str "App.Ledger.serve_one") ~actor:"null" ~start:"null")
  in
  Alcotest.(check int) "exit 1" 1 rc;
  Alcotest.(check bool) "says which version" true
    (contains err "topology schema version 2, but this build reads version 1")

let test_missing_file_is_rejected () =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf "compiler not found at %s" compiler_exe;
  let dir = Filename.temp_dir "topology_flag_" "" in
  write (Filename.concat dir "app.march") entry_src;
  let rc =
    Sys.command (Printf.sprintf "%s --check --topology %s %s > /dev/null 2>&1"
                   (Filename.quote compiler_exe)
                   (Filename.quote (Filename.concat dir "nope.json"))
                   (Filename.quote (Filename.concat dir "app.march")))
  in
  ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
  Alcotest.(check int) "exit 1" 1 rc

let tests = [
  Alcotest.test_case "a valid digest changes nothing" `Quick test_valid_digest_is_accepted;
  Alcotest.test_case "an actor binding resolves" `Quick test_actor_binding_resolves;
  Alcotest.test_case "an unbound body or hook is an error naming it" `Quick test_unbound_name_is_rejected;
  Alcotest.test_case "schema version 2 is refused" `Quick test_wrong_version_is_rejected;
  Alcotest.test_case "a missing digest file is an error" `Quick test_missing_file_is_rejected;
]
