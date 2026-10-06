(* Drives a running compiled program's observe socket and checks the signed
   debug verbs (R4 of specs/plans/2026-09-28-observe-recon-shell-plan.md).

     observe_debug_check keygen <pk-file> <sk-file>
     observe_debug_check signed <socket> <program-output> <sk-file> <policy-file> <audit-log>
     observe_debug_check nokey  <socket> <program-output>

   [keygen] writes a fresh deploy keypair (the public half in base64, for
   --signing-pubkey).  [signed] runs every acceptance case of the plan against
   test/native/observe_debug.march built with that key; [nokey] checks that a
   build without a key refuses.  One "ok: ..." / "FAIL: ..." line per check,
   diffed against a golden. *)

open Yojson.Safe.Util

let query sock line =
  let fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
      Unix.setsockopt_float fd Unix.SO_RCVTIMEO 15.;
      Unix.connect fd (Unix.ADDR_UNIX sock);
      let req = line ^ "\n" in
      ignore (Unix.write_substring fd req 0 (String.length req));
      let buf = Buffer.create 4096 and chunk = Bytes.create 65536 in
      let rec loop () =
        match Unix.read fd chunk 0 (Bytes.length chunk) with
        | 0 -> ()
        | n -> Buffer.add_subbytes buf chunk 0 n; loop ()
      in
      loop ();
      Yojson.Safe.from_string (String.trim (Buffer.contents buf)))

let failures = ref 0
let check name ok detail =
  if ok then Printf.printf "ok: %s\n%!" name
  else begin incr failures; Printf.printf "FAIL: %s (%s)\n%!" name detail end

let error j = member "error" j |> to_string_option
let data j = member "data" j

let contains s sub =
  let n = String.length s and m = String.length sub in
  let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
  go 0

let read_file f =
  let ic = open_in_bin f in
  Fun.protect ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let write_file f s =
  let oc = open_out_bin f in
  output_string oc s;
  close_out oc

(* The program's "counter <pid>" line, once it has printed "ready". *)
let wait_ready file =
  let deadline = Unix.gettimeofday () +. 60. in
  let rec go () =
    let s = try read_file file with Sys_error _ -> "" in
    if contains s "ready\n" then
      List.find_map (fun l ->
          match String.split_on_char ' ' l with
          | [ "counter"; p ] -> int_of_string_opt p
          | _ -> None) (String.split_on_char '\n' s)
      |> Option.value ~default:(-1)
    else if Unix.gettimeofday () > deadline then (prerr_endline ("never ready:\n" ^ s); exit 1)
    else (Unix.sleepf 0.05; go ())
  in
  go ()

let now_ms () = int_of_float (Unix.gettimeofday () *. 1000.)

let nonce_counter = ref 0
let fresh_nonce () =
  incr nonce_counter;
  Printf.sprintf "%016x%016x" (now_ms ()) !nonce_counter

let sign sk verb ?(not_after = now_ms () + 30_000) ?nonce fields =
  let nonce = match nonce with Some n -> n | None -> fresh_nonce () in
  let body = String.concat " "
      (Printf.sprintf "nonce:%s" nonce :: Printf.sprintf "not_after_ms:%d" not_after :: fields) in
  let s = March_ed25519.Ed25519.(sig_to_base64 (sign_str (verb ^ " " ^ body) sk)) in
  Printf.sprintf "%s %s %s" verb s body

let keygen pk_file sk_file =
  let pk, sk = March_ed25519.Ed25519.keygen () in
  write_file pk_file (March_ed25519.Ed25519.pk_to_base64 pk);
  write_file sk_file (Bytes.to_string sk)

let audit_lines log =
  (try read_file log with Sys_error _ -> "")
  |> String.split_on_char '\n'
  |> List.filter (fun l -> l <> "")
  |> List.map Yojson.Safe.from_string
  |> List.filter (fun j -> member "type" j = `String "debug")

let signed sock prog sk_file policy log =
  let sk = Bytes.of_string (read_file sk_file) in
  let pid = wait_ready prog in
  let state_req ?not_after ?nonce () =
    sign sk "STATE" ?not_after ?nonce [ Printf.sprintf "pid:%d" pid ] in
  let expect_error name line code =
    let r = query sock line in
    check name (error r = Some code)
      (Printf.sprintf "error %s" (Option.value ~default:"none" (error r)))
  in

  let help = query sock "HELP" in
  let tiers = data help |> member "verbs" |> to_list
              |> List.filter_map (fun v ->
                  if member "name" v = `String "STATE" then to_string_option (member "tier" v) else None) in
  check "HELP lists STATE in the debug tier" (tiers = [ "debug" ]) (String.concat "," tiers);

  write_file policy "";
  (* A signature by a different key. *)
  let _, other = March_ed25519.Ed25519.keygen () in
  expect_error "a request signed by another key: bad_signature"
    (sign other "STATE" [ Printf.sprintf "pid:%d" pid ]) "bad_signature";
  expect_error "a garbage signature: bad_signature"
    (Printf.sprintf "STATE AAAA nonce:%s not_after_ms:%d pid:%d" (fresh_nonce ()) (now_ms () + 30_000) pid)
    "bad_signature";
  (* Altering a signed field breaks the signature. *)
  let good = state_req () in
  let tampered =
    String.concat " " (List.map (fun w -> if w = Printf.sprintf "pid:%d" pid then "pid:1" else w)
                         (String.split_on_char ' ' good)) in
  expect_error "a request with its pid changed after signing: bad_signature" tampered "bad_signature";
  expect_error "no policy entry: policy" (state_req ()) "policy";

  write_file policy "# debug verbs this node allows\nSTATE\nCRASHES_FULL\n";
  let line = state_req () in
  let r = query sock line in
  check "a valid STATE: the actor's rendered state"
    (error r = None && data r |> member "state" = `String "{ n: 5, tags: [x] }")
    (Yojson.Safe.to_string r);
  expect_error "the same request again: replay" line "replay";
  expect_error "an expired request: expired" (state_req ~not_after:(now_ms () - 1000) ()) "expired";
  expect_error "a request valid for 2 minutes: not_after_too_far"
    (state_req ~not_after:(now_ms () + 120_000) ()) "not_after_too_far";
  expect_error "a short nonce: bad_nonce" (state_req ~nonce:"abc" ()) "bad_nonce";
  expect_error "an unknown argument: bad_args"
    (sign sk "STATE" [ Printf.sprintf "pid:%d" pid; "colour:red" ]) "bad_args";
  let dead = query sock (sign sk "STATE" [ "pid:999999" ]) in
  check "STATE of a pid that is not running: dead"
    (data dead |> member "error" = `String "dead") (Yojson.Safe.to_string dead);

  let full = query sock (sign sk "CRASHES_FULL" []) in
  let msgs = try data full |> member "crashes" |> to_list
                 |> List.map (fun c -> member "message" c |> to_string)
    with _ -> [] in
  check "CRASHES_FULL carries the crash message"
    (List.exists (fun m -> contains m "debug-crash-message-plugh") msgs) (Yojson.Safe.to_string full);
  let plain = query sock "CRASHES" in
  check "CRASHES (observe tier) still does not"
    (not (contains (Yojson.Safe.to_string plain) "plugh")) "message leaked";

  write_file policy "STATE\n";
  expect_error "CRASHES_FULL once the policy drops it: policy" (sign sk "CRASHES_FULL" []) "policy";

  let results = audit_lines log |> List.map (fun j -> member "result" j |> to_string) in
  let expected = [ "bad_signature"; "bad_signature"; "bad_signature"; "policy"; "ok"; "replay";
                   "expired"; "not_after_too_far"; "bad_nonce"; "bad_args"; "ok"; "ok"; "policy" ] in
  check "every attempt is audited, in order" (results = expected) (String.concat "," results);
  let signers = audit_lines log |> List.map (fun j -> member "signer" j |> to_string) in
  check "audit lines name the node's key"
    (List.for_all (fun s -> String.length s = 64) signers) (String.concat "," signers);
  if !failures > 0 then exit 1

let nokey sock prog =
  let pid = wait_ready prog in
  let _, sk = March_ed25519.Ed25519.keygen () in
  let r = query sock (sign sk "STATE" [ Printf.sprintf "pid:%d" pid ]) in
  check "a build without a key: signing_not_configured"
    (error r = Some "signing_not_configured") (Yojson.Safe.to_string r);
  if !failures > 0 then exit 1

let () =
  match Array.to_list Sys.argv |> List.tl with
  | [ "keygen"; pk; sk ] -> keygen pk sk
  | [ "signed"; sock; prog; sk; policy; log ] -> signed sock prog sk policy log
  | [ "nokey"; sock; prog ] -> nokey sock prog
  | _ -> prerr_endline "usage: observe_debug_check keygen|signed|nokey ..."; exit 2
