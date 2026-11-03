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

(* The program's "beat <pid>" line (an actor main messages every 20 ms). *)
let beat_pid file =
  let s = try read_file file with Sys_error _ -> "" in
  List.find_map (fun l ->
      match String.split_on_char ' ' l with
      | [ "beat"; p ] -> int_of_string_opt p
      | _ -> None) (String.split_on_char '\n' s)
  |> Option.value ~default:(-1)

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

(* This process's boot id, from HELLO: every signed request names it, so a
   captured line cannot be replayed after a restart or against another node. *)
let boot = ref "x"

let sign sk verb ?(not_after = now_ms () + 30_000) ?nonce ?boot_id fields =
  let nonce = match nonce with Some n -> n | None -> fresh_nonce () in
  let boot_id = match boot_id with Some b -> b | None -> !boot in
  let body = String.concat " "
      (Printf.sprintf "nonce:%s" nonce :: Printf.sprintf "boot:%s" boot_id
       :: Printf.sprintf "not_after_ms:%d" not_after :: fields) in
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


(* ── TRACE_START / TRACE_DRAIN / TRACE_STOP (R8) ─────────────────────────
   The program calls the boundary function `tick` every 20 ms from main. *)
let trace_checks sock sk policy beat =
  write_file policy "STATE\nCRASHES_FULL\nTRACE_START\nTRACE_DRAIN\nTRACE_STOP\n";
  let req verb fields = query sock (sign sk verb fields) in
  let err name verb fields code =
    let r = req verb fields in
    check name (error r = Some code) (Yojson.Safe.to_string r) in
  let session r = try data r |> member "session" |> to_int with _ -> -1 in
  let sess id = Printf.sprintf "session:%d" id in
  let stop id = ignore (req "TRACE_STOP" [ sess id ]) in

  (* There is no spelling of TRACE_START without a limit, and the limits are bounded. *)
  err "TRACE_START with no limit: limit_required" "TRACE_START" [ "fn:tick" ] "limit_required";
  err "TRACE_START count:0: limit_out_of_range" "TRACE_START" [ "count:0"; "fn:tick" ] "limit_out_of_range";
  err "TRACE_START count:65537: limit_out_of_range" "TRACE_START" [ "count:65537"; "fn:tick" ] "limit_out_of_range";
  err "TRACE_START count:99999999999: limit_out_of_range" "TRACE_START" [ "count:99999999999"; "fn:tick" ] "limit_out_of_range";
  err "TRACE_START rate:0 per_s:1: limit_out_of_range" "TRACE_START" [ "rate:0"; "per_s:1"; "fn:tick" ] "limit_out_of_range";
  err "TRACE_START rate:5 per_s:0: limit_out_of_range" "TRACE_START" [ "rate:5"; "per_s:0"; "fn:tick" ] "limit_out_of_range";
  err "TRACE_START rate:5 per_s:3601: limit_out_of_range" "TRACE_START" [ "rate:5"; "per_s:3601"; "fn:tick" ] "limit_out_of_range";
  err "TRACE_START rate:100001 per_s:1: limit_out_of_range" "TRACE_START" [ "rate:100001"; "per_s:1"; "fn:tick" ] "limit_out_of_range";
  err "TRACE_START rate without per_s: bad_args" "TRACE_START" [ "rate:5"; "fn:tick" ] "bad_args";
  err "TRACE_START count and rate: bad_args" "TRACE_START" [ "count:5"; "rate:5"; "per_s:1"; "fn:tick" ] "bad_args";
  err "TRACE_START without fn: bad_args" "TRACE_START" [ "count:5" ] "bad_args";
  err "TRACE_START of an unknown function: unknown_function" "TRACE_START" [ "count:5"; "fn:no_such_fn" ] "unknown_function";
  err "TRACE_START of a stdlib function: unknown_function" "TRACE_START" [ "count:5"; "fn:List.map" ] "unknown_function";
  err "TRACE_START with a hostile name: bad_args" "TRACE_START" [ "count:5"; "fn:tick\"x" ] "bad_args";
  err "TRACE_DRAIN of no session: not_found" "TRACE_DRAIN" [ "session:424242" ] "not_found";

  (* A signed start, replayed, is refused and starts nothing. *)
  let line = sign sk "TRACE_START" [ "count:10"; "fn:tick" ] in
  let r = query sock line in
  let id = session r in
  check "TRACE_START count:10: a session, the limit echoed"
    (error r = None && id > 0
     && data r |> member "limit" |> member "kind" = `String "count"
     && data r |> member "limit" |> member "n" = `Int 10
     && data r |> member "ring" = `Int 10)
    (Yojson.Safe.to_string r);
  let r2 = query sock line in
  check "the same TRACE_START again: replay" (error r2 = Some "replay") (Yojson.Safe.to_string r2);

  (* Count(10): exactly ten events, then it stops itself.  Poll until done. *)
  let events = ref [] and last = ref `Null in
  let deadline = Unix.gettimeofday () +. 20. in
  let rec poll () =
    let d = req "TRACE_DRAIN" [ sess id ] in
    last := d;
    (try events := !events @ (data d |> member "events" |> to_list) with _ -> ());
    if (try data d |> member "done" = `Bool true with _ -> false) then ()
    else if Unix.gettimeofday () > deadline then ()
    else (Unix.sleepf 0.1; poll ()) in
  poll ();
  check "Count(10) stopped itself after exactly 10 events"
    (List.length !events = 10
     && data !last |> member "recorded" = `Int 10
     && data !last |> member "why" = `String "count")
    (Yojson.Safe.to_string !last);
  check "events are boundary calls: function name, pid, epoch, time; no arguments"
    (List.for_all (fun e ->
         member "fn" e = `String "tick"
         && (match member "pid" e with `Int _ -> true | _ -> false)
         && (match member "epoch" e with `Int _ -> true | _ -> false)
         && (match member "at_ns" e with `Int _ -> true | _ -> false)
         && List.sort compare (List.map fst (to_assoc e))
            = [ "at_ns"; "epoch"; "fn"; "name_id"; "pid" ]) !events)
    (String.concat " " (List.map Yojson.Safe.to_string !events));
  let times = List.map (fun e -> member "at_ns" e |> to_int) !events in
  check "event times are non-decreasing" (List.sort compare times = times) "";
  Unix.sleepf 0.3;
  let after = req "TRACE_DRAIN" [ sess id ] in
  check "after it stopped: no more events, still 10 recorded"
    (data after |> member "events" |> to_list = [] && data after |> member "recorded" = `Int 10)
    (Yojson.Safe.to_string after);
  let st = req "TRACE_STOP" [ sess id ] in
  check "TRACE_STOP frees it" (error st = None) (Yojson.Safe.to_string st);
  err "TRACE_DRAIN after stop: not_found" "TRACE_DRAIN" [ sess id ] "not_found";
  err "TRACE_STOP twice: not_found" "TRACE_STOP" [ sess id ] "not_found";

  (* Rate(2, 1s): at most 2 events per second; the rest are counted. *)
  let rr = req "TRACE_START" [ "rate:2"; "per_s:1"; "fn:tick" ] in
  let rid = session rr in
  check "TRACE_START rate:2 per_s:1" (error rr = None && rid > 0) (Yojson.Safe.to_string rr);
  Unix.sleepf 2.5;
  let rd = req "TRACE_DRAIN" [ sess rid ] in
  let recorded = try data rd |> member "recorded" |> to_int with _ -> -1 in
  let rate_dropped = try data rd |> member "rate_dropped" |> to_int with _ -> -1 in
  check "Rate(2,1): 2 to 6 events over 2.5 s, the excess counted as rate_dropped, still running"
    (recorded >= 2 && recorded <= 6 && rate_dropped > 20 && data rd |> member "done" = `Bool false)
    (Yojson.Safe.to_string rd);
  stop rid;

  (* At most 4 sessions. *)
  let ids = List.init 4 (fun _ -> session (req "TRACE_START" [ "count:5"; "fn:tick" ])) in
  check "four sessions start" (List.for_all (fun i -> i > 0) ids) (String.concat "," (List.map string_of_int ids));
  err "a fifth session: too_many_sessions" "TRACE_START" [ "count:5"; "fn:tick" ] "too_many_sessions";
  List.iter stop ids;
  let again = req "TRACE_START" [ "count:5"; "fn:tick" ] in
  check "room again after stopping them" (error again = None) (Yojson.Safe.to_string again);
  stop (session again);

  (* ── Actor events.  main sends Beat a message every 20 ms. ─────────────── *)
  let b = Printf.sprintf "pids:%d" beat in
  check "the program printed Beat's pid" (beat > 0) (string_of_int beat);
  err "events without pids: pids_required" "TRACE_START" [ "count:5"; "events:sent" ] "pids_required";
  err "an unknown kind: bad_args" "TRACE_START" [ "count:5"; "events:sent,bogus"; b ] "bad_args";
  err "a repeated kind: bad_args" "TRACE_START" [ "count:5"; "events:sent,sent"; b ] "bad_args";
  err "an upper-case kind: bad_args" "TRACE_START" [ "count:5"; "events:SENT"; b ] "bad_args";
  err "pids without events: bad_args" "TRACE_START" [ "count:5"; "fn:tick"; b ] "bad_args";
  err "nine pids: bad_args" "TRACE_START" [ "count:5"; "events:sent"; "pids:1,2,3,4,5,6,7,8,9" ] "bad_args";
  err "a pid that is not an actor: unknown_pid" "TRACE_START" [ "count:5"; "events:sent"; "pids:999999" ] "unknown_pid";
  err "a malformed pid list: bad_args" "TRACE_START" [ "count:5"; "events:sent"; "pids:1,,2" ] "bad_args";
  err "a negative pid: bad_args" "TRACE_START" [ "count:5"; "events:sent"; "pids:-1" ] "bad_args";
  err "events with limit 0: limit_out_of_range" "TRACE_START" [ "count:0"; "events:sent"; b ] "limit_out_of_range";
  err "events with no limit: limit_required" "TRACE_START" [ "events:sent"; b ] "limit_required";
  err "nothing to watch: bad_args" "TRACE_START" [ "count:5" ] "bad_args";

  (* Count(6) over Sent and Received of Beat: exactly six events, then done. *)
  let sr = req "TRACE_START" [ "count:6"; "events:sent,received"; b ] in
  let srid = session sr in
  check "TRACE_START with events: the kinds and the pid filter echoed"
    (error sr = None && srid > 0
     && data sr |> member "events" = `List [ `String "sent"; `String "received" ]
     && data sr |> member "pids" = `List [ `Int beat ])
    (Yojson.Safe.to_string sr);
  let evs = ref [] and lastd = ref `Null in
  let deadline = Unix.gettimeofday () +. 20. in
  let rec poll2 () =
    let d = req "TRACE_DRAIN" [ sess srid ] in
    lastd := d;
    (try evs := !evs @ (data d |> member "events" |> to_list) with _ -> ());
    if (try data d |> member "done" = `Bool true with _ -> false) then ()
    else if Unix.gettimeofday () > deadline then ()
    else (Unix.sleepf 0.1; poll2 ()) in
  poll2 ();
  check "Count(6) over actor events stopped itself after exactly 6"
    (List.length !evs = 6
     && data !lastd |> member "recorded" = `Int 6
     && data !lastd |> member "why" = `String "count")
    (Yojson.Safe.to_string !lastd);
  let kind e = try member "kind" e |> to_string with _ -> "?" in
  let sents = List.filter (fun e -> kind e = "sent") !evs
  and recvs = List.filter (fun e -> kind e = "received") !evs in
  check "both kinds appear, no others"
    (sents <> [] && recvs <> [] && List.length sents + List.length recvs = 6)
    (String.concat " " (List.map Yojson.Safe.to_string !evs));
  check "an actor event is pids, a tag, a reason slot and times: nothing else"
    (List.for_all (fun e ->
         List.sort compare (List.map fst (to_assoc e))
         = [ "at_ns"; "epoch"; "kind"; "msg_tag"; "peer"; "pid"; "reason" ]) !evs)
    (String.concat " " (List.map Yojson.Safe.to_string !evs));
  check "Sent: from main (-1) to Beat, with a message tag"
    (List.for_all (fun e ->
         member "pid" e = `Int (-1) && member "peer" e = `Int beat
         && (match member "msg_tag" e with `Int _ -> true | _ -> false)) sents)
    (String.concat " " (List.map Yojson.Safe.to_string sents));
  check "Received: by Beat, no peer, the same tag as the Sent"
    (List.for_all (fun e ->
         member "pid" e = `Int beat && member "peer" e = `Null
         && (match sents with s :: _ -> member "msg_tag" e = member "msg_tag" s | [] -> false)) recvs)
    (String.concat " " (List.map Yojson.Safe.to_string recvs));
  stop srid;

  (* Events and boundary calls in one session: calls say what they are. *)
  let mx = req "TRACE_START" [ "count:8"; "events:received"; b; "fn:tick" ] in
  let mxid = session mx in
  check "TRACE_START with calls and events" (error mx = None && mxid > 0) (Yojson.Safe.to_string mx);
  let rec poll3 n =
    let d = req "TRACE_DRAIN" [ sess mxid ] in
    if (try data d |> member "done" = `Bool true with _ -> false) || n = 0 then d
    else (Unix.sleepf 0.1; poll3 (n - 1)) in
  let md = poll3 200 in
  let mevs = try data md |> member "events" |> to_list with _ -> [] in
  check "a mixed session: calls carry kind call and fn, actor events kind received"
    (mevs <> []
     && List.for_all (fun e ->
         match member "kind" e with
         | `String "call" -> member "fn" e = `String "tick"
         | `String "received" -> member "pid" e = `Int beat
         | _ -> false) mevs
     && List.exists (fun e -> member "kind" e = `String "call") mevs
     && List.exists (fun e -> member "kind" e = `String "received") mevs)
    (String.concat " " (List.map Yojson.Safe.to_string mevs));
  stop mxid;

  (* Rate(2, 1s) bounds an event session too, and counts the excess. *)
  let er = req "TRACE_START" [ "rate:2"; "per_s:1"; "events:received"; b ] in
  let erid = session er in
  check "TRACE_START rate with events" (error er = None && erid > 0) (Yojson.Safe.to_string er);
  Unix.sleepf 2.5;
  let ed = req "TRACE_DRAIN" [ sess erid ] in
  let erec = try data ed |> member "recorded" |> to_int with _ -> -1 in
  let erd = try data ed |> member "rate_dropped" |> to_int with _ -> -1 in
  check "Rate(2,1) over Received: 2 to 6 events in 2.5 s, the excess counted, still running"
    (erec >= 2 && erec <= 6 && erd > 20 && data ed |> member "done" = `Bool false)
    (Yojson.Safe.to_string ed);
  stop erid;

  (* A session is a session: four at most, event sessions included. *)
  let eids = List.init 4 (fun _ -> session (req "TRACE_START" [ "count:5"; "events:sent"; b ])) in
  check "four event sessions start" (List.for_all (fun i -> i > 0) eids) (String.concat "," (List.map string_of_int eids));
  err "a fifth: too_many_sessions" "TRACE_START" [ "count:5"; "events:sent"; b ] "too_many_sessions";
  List.iter stop eids

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

  let hello = query sock "HELLO" in
  boot := (try data hello |> member "boot" |> to_string with _ -> "");
  check "HELLO: a 32-hex boot id and signing configured"
    (String.length !boot = 32 && data hello |> member "signing" = `Bool true)
    (Yojson.Safe.to_string hello);
  let hello2 = query sock "HELLO" in
  check "HELLO: the boot id is stable within a process"
    (data hello2 |> member "boot" = `String !boot) (Yojson.Safe.to_string hello2);

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
    (Printf.sprintf "STATE AAAA nonce:%s boot:%s not_after_ms:%d pid:%d" (fresh_nonce ()) !boot (now_ms () + 30_000) pid)
    "bad_signature";
  (* Altering a signed field breaks the signature. *)
  let good = state_req () in
  let tampered =
    String.concat " " (List.map (fun w -> if w = Printf.sprintf "pid:%d" pid then "pid:1" else w)
                         (String.split_on_char ' ' good)) in
  expect_error "a request with its pid changed after signing: bad_signature" tampered "bad_signature";
  expect_error "no policy entry: policy" (state_req ()) "policy";
  (* Signed for another process or node: refused, before the nonce is spent. *)
  expect_error "a request signed for another boot id: wrong_boot"
    (sign sk "STATE" ~boot_id:"00000000000000000000000000000000" [ Printf.sprintf "pid:%d" pid ])
    "wrong_boot";
  expect_error "a request with no boot id: bad_args"
    (let body = Printf.sprintf "nonce:%s not_after_ms:%d pid:%d" (fresh_nonce ()) (now_ms () + 30_000) pid in
     Printf.sprintf "STATE %s %s"
       March_ed25519.Ed25519.(sig_to_base64 (sign_str ("STATE " ^ body) sk)) body)
    "bad_args";

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

  trace_checks sock sk policy (beat_pid prog);

  write_file policy "STATE\n";
  expect_error "CRASHES_FULL once the policy drops it: policy" (sign sk "CRASHES_FULL" []) "policy";
  expect_error "TRACE_START once the policy drops it: policy"
    (sign sk "TRACE_START" [ "count:3"; "fn:tick" ]) "policy";

  let old_verbs j = match member "verb" j with
    | `String ("STATE" | "CRASHES_FULL") -> true | _ -> false in
  let results = audit_lines log |> List.filter old_verbs
                |> List.map (fun j -> member "result" j |> to_string) in
  let expected = [ "bad_signature"; "bad_signature"; "bad_signature"; "policy"; "wrong_boot"; "bad_args";
                   "ok"; "replay"; "expired"; "not_after_too_far"; "bad_nonce"; "bad_args"; "ok"; "ok";
                   "policy" ] in
  check "every attempt is audited, in order" (results = expected) (String.concat "," results);
  let trace_audit = audit_lines log
                    |> List.filter (fun j -> match member "verb" j with
                        | `String s -> String.length s > 6 && String.sub s 0 6 = "TRACE_" | _ -> false) in
  check "trace attempts are audited, with the session in the detail"
    (List.exists (fun j -> match member "detail" j with
         | `String d -> contains d "session=" | _ -> false) trace_audit
     && List.exists (fun j -> member "result" j = `String "limit_required") trace_audit
     && List.exists (fun j -> member "result" j = `String "policy") trace_audit)
    (string_of_int (List.length trace_audit));
  check "actor-event starts are audited with their kinds' presence and pid count; refusals too"
    (List.exists (fun j -> match member "detail" j with
         | `String d -> contains d "session=" && contains d "events=yes pids=1" | _ -> false) trace_audit
     && List.exists (fun j -> member "result" j = `String "pids_required"
                              && (match member "detail" j with
                                  | `String d -> contains d "events=yes pids=0" | _ -> false)) trace_audit
     && List.exists (fun j -> member "result" j = `String "unknown_pid") trace_audit)
    (String.concat "\n" (List.map Yojson.Safe.to_string trace_audit));
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
