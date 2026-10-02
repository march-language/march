(* Drives a running compiled program's observe socket and checks the R1
   snapshot verbs (specs/plans/2026-09-28-observe-recon-shell-plan.md).

     observe_snapshot_check tree  <socket> <program-output>
     observe_snapshot_check types <socket> <program-output>

   Waits for the program to print "ready", then queries and prints one
   deterministic line per check ("ok: ..." or "FAIL: ..."), which the dune
   rule diffs against a golden.  [tree] is test/native/observe_snapshot.march;
   [types] is test/native/observe_types_hr.march (built --hot-reload). *)

open Yojson.Safe.Util

let secret = "xyzzy"   (* inside the fixture's panic message; must never appear *)

let query sock line =
  let fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
      (* A hung verb fails the rule instead of hanging it. *)
      Unix.setsockopt_float fd Unix.SO_RCVTIMEO 10.;
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
      String.trim (Buffer.contents buf))

let failures = ref 0
let check name ok detail =
  if ok then Printf.printf "ok: %s\n" name
  else begin incr failures; Printf.printf "FAIL: %s (%s)\n" name detail end

(* Every raw reply goes through here, so the crash text is checked on all. *)
let leaked = ref []
let get sock line =
  let raw = query sock line in
  let contains s sub =
    let n = String.length s and m = String.length sub in
    let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
    go 0
  in
  if contains raw secret then leaked := line :: !leaked;
  Yojson.Safe.from_string raw

let data j = member "data" j
let error j = member "error" j |> to_string_option

let wait_ready file =
  let deadline = Unix.gettimeofday () +. 60. in
  let rec go () =
    let ready =
      try
        let ic = open_in file in
        let s = Fun.protect ~finally:(fun () -> close_in ic)
            (fun () -> really_input_string ic (in_channel_length ic)) in
        String.length s >= 5 && (String.sub s 0 5 = "ready")
      with Sys_error _ -> false
    in
    if ready then ()
    else if Unix.gettimeofday () > deadline then (print_endline "FAIL: never ready"; exit 0)
    else (Unix.sleepf 0.05; go ())
  in
  go ()

(* The fixture prints "ready" after a fixed sleep; under load the crash, the
   restart or the burst may not have landed yet.  Wait (up to 20 s) for the
   state every check below assumes: 20 live actors, 500 queued on "hot", and
   exactly one dead pid. *)
let settled sock =
  let rows () = data (get sock "ACTORS pid 10000") |> member "actors" |> to_list in
  let ok () =
    try
      let rs = rows () in
      let pids = List.map (fun r -> member "pid" r |> to_int) rs in
      let hi = List.fold_left max 0 pids in
      let hot = List.exists (fun r ->
          (member "names" r |> to_list |> List.map to_string) = ["hot"]
          && member "user_mbox" r |> to_int = 500) rs in
      List.length rs = 20 && hot && hi + 1 - List.length pids = 1
    with _ -> false
  in
  let deadline = Unix.gettimeofday () +. 20. in
  let rec go () =
    if ok () then ()
    else if Unix.gettimeofday () > deadline then print_endline "FAIL: never settled"
    else (Unix.sleepf 0.1; go ())
  in
  go ()

let tree sock =
  settled sock;
  (* ACTORS: the burst target sorts first by mailbox depth. *)
  let a = data (get sock "ACTORS mbox 1") in
  let rows = member "actors" a |> to_list in
  let top = List.hd rows in
  check "ACTORS mbox 1 names the actor with the burst"
    (List.length rows = 1
     && (member "names" top |> to_list |> List.map to_string) = ["hot"]
     && member "user_mbox" top |> to_int = 500
     && member "parent" top = `Null)
    (Yojson.Safe.to_string top);
  check "ACTORS total counts every live actor (3x(1+4) + 5)"
    (member "total" a |> to_int = 20) (Yojson.Safe.to_string (member "total" a));

  (* TREE: three supervisors of four, and the five bare actors. *)
  let t = data (get sock "TREE") in
  let roots = member "roots" t |> to_list in
  let kids r = member "children" r |> to_list in
  check "TREE has 3 roots with 4 children each"
    (List.length roots = 3 && List.for_all (fun r -> List.length (kids r) = 4) roots)
    (Yojson.Safe.to_string t);
  check "TREE lists 5 unsupervised actors"
    (List.length (member "unsupervised" t |> to_list) = 5) (Yojson.Safe.to_string t);
  check "TREE is not truncated" (member "truncated" t = `Bool false) "";

  (* The crashed child: the one pid missing from the live range. *)
  let all = data (get sock "ACTORS pid 10000") in
  let pids = member "actors" all |> to_list |> List.map (fun r -> member "pid" r |> to_int) in
  let hi = List.fold_left max 0 pids in
  let gaps = List.filter (fun p -> not (List.mem p pids)) (List.init (hi + 1) Fun.id) in
  check "exactly one dead pid in the live range" (List.length gaps = 1)
    (String.concat "," (List.map string_of_int gaps));
  (match gaps with
   | [dead] ->
     let d = data (get sock (Printf.sprintf "ACTOR %d" dead)) in
     check "ACTOR <dead child> reports kind Crash"
       (member "alive" d = `Bool false
        && member "terminal" d |> member "kind" |> to_string = "Crash")
       (Yojson.Safe.to_string d);
     check "ACTOR <dead child> carries no message field"
       (member "terminal" d |> keys = ["kind"]) (Yojson.Safe.to_string d)
   | _ -> ());

  (* NAMES, and the supervisor through ACTOR. *)
  let n = data (get sock "NAMES") |> member "names" |> to_list in
  let named = List.map (fun e -> (member "name" e |> to_string, member "pid" e |> to_int)) n in
  check "NAMES lists hot and sup_one, sorted"
    (List.map fst named = ["hot"; "sup_one"]) (Yojson.Safe.to_string (`List n));
  (match List.assoc_opt "sup_one" named with
   | Some sp ->
     let s = data (get sock (Printf.sprintf "ACTOR %d" sp)) in
     let sup = member "supervisor" s in
     check "ACTOR <supervisor> reports config and the one restart"
       (member "alive" s = `Bool true
        && member "strategy" sup |> to_string = "one_for_one"
        && member "max_restarts" sup |> to_int = 5
        && member "window_secs" sup |> to_int = 60
        && member "restarts_held" sup |> to_int = 1
        && List.length (member "children" s |> to_list) = 4)
       (Yojson.Safe.to_string s);
     let in_tree = List.exists (fun r -> member "pid" r |> to_int = sp) roots in
     check "the named supervisor is a TREE root" in_tree ""
   | None -> check "sup_one is registered" false "");

  (* SCHED, MEM, EPOCHS, SNAPSHOT. *)
  let sc = data (get sock "SCHED") in
  check "SCHED has one thread row per scheduler"
    (List.length (member "threads" sc |> to_list) = (member "schedulers" sc |> to_int)
     && member "schedulers" sc |> to_int >= 1)
    (Yojson.Safe.to_string sc);
  let m = data (get sock "MEM") in
  check "MEM reports rss, live objects and the queued burst"
    (member "rss_bytes" m |> to_int > 0
     && member "live_objects" m |> to_int > 0
     && member "queued_messages" m |> to_int >= 500
     && member "actors" m |> to_int = 20)
    (Yojson.Safe.to_string m);
  let e = data (get sock "EPOCHS") in
  check "EPOCHS reports the current epoch"
    (member "current" e |> to_int >= 1 && member "counters" e <> `Null)
    (Yojson.Safe.to_string e);
  let s = data (get sock "SNAPSHOT") in
  check "SNAPSHOT carries all six sections"
    (List.sort compare (keys s)
     = ["actors"; "epochs"; "mem"; "names"; "sched"; "tree"])
    (String.concat "," (keys s));
  check "SNAPSHOT sections come from one walk"
    (member "actors" s |> member "total" |> to_int
     = (member "mem" s |> member "actors" |> to_int))
    "";
  let s2 = data (get sock "SNAPSHOT mem,names") in
  check "SNAPSHOT mem,names carries just those"
    (List.sort compare (keys s2) = ["mem"; "names"]) (String.concat "," (keys s2));

  (* Arguments. *)
  List.iter (fun (req, want) ->
      let got = error (get sock req) in
      check (Printf.sprintf "%s -> %s" req want) (got = Some want)
        (Option.value got ~default:"(data)"))
    [ "ACTORS bogus", "bad_args"; "ACTORS 10001", "bad_args";
      "ACTORS mbox 5 extra", "bad_args"; "ACTORS 5 7", "bad_args"; "ACTORS mbox pid", "bad_args"; "ACTOR", "bad_args"; "ACTOR -1", "bad_args";
      "ACTOR 99999999", "not_found"; "TREE x", "bad_args";
      "SNAPSHOT bogus", "bad_args" ];
  let h = data (get sock "HELP") |> member "verbs" |> to_list
          |> List.map (fun v -> member "name" v |> to_string) in
  check "HELP lists every verb"
    (h = ["HELP"; "PING"; "SNAPSHOT"; "ACTORS"; "ACTOR"; "TREE"; "NAMES";
          "SCHED"; "MEM"; "EPOCHS"])
    (String.concat "," h)

let types sock =
  let a = data (get sock "ACTORS pid 10") |> member "actors" |> to_list in
  check "ACTORS names the actor type under --hot-reload"
    (List.length a = 2
     && List.for_all (fun r -> member "type" r = `String "Counter") a)
    (Yojson.Safe.to_string (`List a));
  let e = data (get sock "EPOCHS") |> member "slots" |> to_list in
  check "EPOCHS lists the dispatch slot"
    (List.exists (fun s -> member "name" s = `String "Counter_dispatch") e)
    (Yojson.Safe.to_string (`List e))

(* R2 counters: test/native/observe_counters.march. *)
let counters sock =
  let by_name () =
    data (get sock "ACTORS pid 10000") |> member "actors" |> to_list
    |> List.filter_map (fun r ->
        match member "names" r |> to_list with
        | [ `String n ] -> Some (n, r)
        | _ -> None)
  in
  let int k r = member k r |> to_int in
  let deadline = Unix.gettimeofday () +. 20. in
  let rec wait () =
    let rows = by_name () in
    let ok =
      match List.assoc_opt "pong" rows, List.assoc_opt "caller" rows with
      | Some p, Some c -> int "msgs_in" p = 200 && int "held" c = 150
      | _ -> false
    in
    if ok then rows
    else if Unix.gettimeofday () > deadline then (print_endline "FAIL: never settled"; rows)
    else (Unix.sleepf 0.1; wait ())
  in
  let rows = wait () in
  let row n = List.assoc n rows in
  let show r = Yojson.Safe.to_string r in
  let pong = row "pong" and ping = row "ping" and caller = row "caller" in
  check "pong received 200 and sent 200"
    (int "msgs_in" pong = 200 && int "msgs_out" pong = 200) (show pong);
  check "ping sent 200 and received 201 (the kick)"
    (int "msgs_in" ping = 201 && int "msgs_out" ping = 200) (show ping);
  check "each side of the pair was dispatched"
    (int "slices" pong >= 1 && int "slices" ping >= 1) "";
  check "idle_ms is reported once an actor has run"
    (match member "idle_ms" pong with `Int n -> n >= 0 | _ -> false) (show pong);
  check "a caller blocked in Actor.call shows the 150 it holds, none queued"
    (int "held" caller = 150 && int "mbox" caller = 0) (show caller);
  check "the call's request counts as a send" (int "msgs_out" caller = 1) (show caller);
  let top = data (get sock "ACTORS mbox 1") |> member "actors" |> to_list in
  check "ACTORS mbox ranks the held work first"
    (match top with [ r ] -> member "names" r = `List [ `String "caller" ] | _ -> false)
    (show (`List top));
  let m = data (get sock "MEM") in
  check "MEM counts held messages as queued"
    (member "queued_messages" m |> to_int >= 150) (show m)

let () =
  match Sys.argv with
  | [| _; mode; sock; ready |] ->
    wait_ready ready;
    (match mode with
     | "tree" -> tree sock
     | "types" -> types sock
     | "counters" -> counters sock
     | _ -> prerr_endline "mode: tree | types | counters"; exit 2);
    check "no reply carries the crash message" (!leaked = [])
      (String.concat "; " !leaked);
    (* The golden diff reports a failure; exit 0 so it is shown. *)
    ignore !failures
  | _ -> prerr_endline "usage: observe_snapshot_check tree|types|counters <socket> <ready-file>"; exit 2
