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
  check "SNAPSHOT carries all seven sections"
    (List.sort compare (keys s)
     = ["actors"; "crashes"; "epochs"; "mem"; "names"; "sched"; "tree"])
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
      "SNAPSHOT bogus", "bad_args"; "TOP stack", "bad_args";
      "TOP stack 5 100", "bad_args"; "TOP stack 0", "bad_args" ];
  (* TOP rows carry the supervision columns (the ranked list is the point of
     Recon.top / forge top). *)
  let top req = data (get sock req) |> member "top" |> to_list in
  let rows_by_pid = List.map (fun r -> (member "pid" r |> to_int, r)) (top "TOP mbox 100") in
  check "TOP mbox 100 returns all 20 actors, the burst first"
    (List.length rows_by_pid = 20
     && (match top "TOP mbox 1" with
         | [ r ] -> member "names" r = `List [ `String "hot" ] && member "value" r |> to_int = 500
                    && member "link" r = `String "none" && member "parent" r = `Null
                    && member "supervisor" r = `Null
         | _ -> false))
    "";
  let sups = List.filter (fun (_, r) -> member "supervisor" r <> `Null) rows_by_pid in
  check "TOP marks exactly the 3 supervisors, each one_for_one 5 within 60 with 4 children"
    (List.length sups = 3
     && List.for_all (fun (_, r) ->
         let sj = member "supervisor" r in
         member "strategy" sj = `String "one_for_one" && member "max_restarts" sj |> to_int = 5
         && member "window_secs" sj |> to_int = 60 && member "children" r |> to_int = 4) sups)
    "";
  let supervised = List.filter (fun (_, r) -> member "link" r = `String "supervised") rows_by_pid in
  check "TOP: 12 supervised children, each naming one of the supervisors as parent"
    (List.length supervised = 12
     && List.for_all (fun (_, r) ->
         List.mem_assoc (member "parent" r |> to_int) sups && member "supervisor" r = `Null) supervised)
    "";
  check "TOP: the crashed slot shows on its supervisor as 1 restart held and 1 child crash"
    (List.exists (fun (_, r) ->
         member "child_crashes" r |> to_int = 1
         && member "supervisor" r |> member "restarts_held" |> to_int = 1) sups)
    "";
  let ranked = top "TOP stack 20" in
  let keyed = List.map (fun r -> (- (member "value" r |> to_int), member "pid" r |> to_int)) ranked in
  check "TOP stack: every actor has a committed stack, and rows are by value then pid"
    (List.length ranked = 20
     && List.for_all (fun r -> member "stack_bytes" r |> to_int > 0
                               && member "stack_bytes" r = member "value" r) ranked
     && keyed = List.sort compare keyed)
    "";
  let zero_ties = List.map (fun r -> member "pid" r |> to_int) (top "TOP crashes 20") in
  check "TOP crashes: ties (all but the supervisor of the crashed slot) are in pid order"
    (match zero_ties with
     | _ :: rest -> rest = List.sort compare rest
     | [] -> false)
    (String.concat "," (List.map string_of_int zero_ties));
  let h = data (get sock "HELP") |> member "verbs" |> to_list
          |> List.map (fun v -> member "name" v |> to_string) in
  check "HELP lists every verb"
    (h = ["HELP"; "PING"; "SNAPSHOT"; "ACTORS"; "ACTOR"; "TREE"; "NAMES";
          "SCHED"; "MEM"; "EPOCHS"; "CRASHES"; "TOP"; "STATE"; "CRASHES_FULL"])
    (String.concat "," h)

let types sock =
  let a = data (get sock "ACTORS pid 10") |> member "actors" |> to_list in
  let type_of r = member "type" r in
  let count t = List.length (List.filter (fun r -> type_of r = `String t) a) in
  check "ACTORS names the actor type under --hot-reload"
    (List.length a = 5 && count "Counter" = 3 && count "Sup" = 1 && count "Deep" = 1)
    (Yojson.Safe.to_string (`List a));
  let e = data (get sock "EPOCHS") |> member "slots" |> to_list in
  check "EPOCHS lists the dispatch slot"
    (List.exists (fun s -> member "name" s = `String "Counter_dispatch") e)
    (Yojson.Safe.to_string (`List e));
  (* TOP: the supervisor's type name, and stack as the size ranking. *)
  let top req = data (get sock req) |> member "top" |> to_list in
  let rows = top "TOP mbox 10" in
  let sup = List.find (fun r -> member "type" r = `String "Sup") rows in
  let child = List.find (fun r -> member "link" r = `String "supervised") rows in
  check "TOP names a supervised child's supervisor by pid and type"
    (member "parent" child = member "pid" sup && member "parent_type" child = `String "Sup"
     && member "type" child = `String "Counter")
    (Yojson.Safe.to_string child);
  check "TOP gives the supervisor's policy: rest_for_one, 3 within 30, 1 child"
    (let sj = member "supervisor" sup in
     member "strategy" sj = `String "rest_for_one" && member "max_restarts" sj |> to_int = 3
     && member "window_secs" sj |> to_int = 30 && member "restarts_held" sj |> to_int = 0
     && member "children" sup |> to_int = 1)
    (Yojson.Safe.to_string sup);
  check "TOP leaves parent_type null for an unsupervised actor"
    (List.exists (fun r -> member "link" r = `String "none" && member "parent_type" r = `Null) rows) "";
  (match top "TOP stack 2" with
   | first :: second :: _ ->
     check "TOP stack ranks the deep-recursion actor first, over the 64 KiB floor"
       (member "type" first = `String "Deep" && member "stack_bytes" first |> to_int >= 65536
        && (member "stack_bytes" second |> to_int) < (member "stack_bytes" first |> to_int))
       (Yojson.Safe.to_string (`List [ first; second ]))
   | _ -> check "TOP stack returns two rows" false "")

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

(* R2 utilisation: test/native/observe_sched.march at 4 schedulers.  The
   idle query runs right after "ready" (3 s of idle follow); the busy one
   after the program prints "busy" (4 s of 4 spinners follow). *)
let sched sock ready_file =
  let util req =
    let d = data (get sock req) in
    (member "utilisation" d |> to_number, d)
  in
  let (idle, d) = util "SCHED 300" in
  check "SCHED reports 4 schedulers" (member "schedulers" d |> to_int = 4) "";
  check "an idle node is under 5% busy" (idle < 0.05)
    (Printf.sprintf "%.3f" idle);
  let deadline = Unix.gettimeofday () +. 20. in
  let rec wait_busy () =
    let s = try In_channel.with_open_bin ready_file In_channel.input_all with Sys_error _ -> "" in
    let has_busy = List.mem "busy" (String.split_on_char '\n' s) in
    if has_busy then ()
    else if Unix.gettimeofday () > deadline then print_endline "FAIL: never busy"
    else (Unix.sleepf 0.05; wait_busy ())
  in
  wait_busy ();
  Unix.sleepf 0.3;
  let (busy, d) = util "SCHED 1000" in
  check "4 spinners on 4 schedulers are over 90% busy" (busy > 0.90)
    (Printf.sprintf "%.3f %s" busy (Yojson.Safe.to_string (member "threads" d)));
  (* last_run_ms comes from a clock the preemption daemon ticks every 1 ms:
     an actor that is running right now must not look idle.  (It once came
     from a per-scheduler clock refreshed every 1024 dispatches, which left
     the busiest actors reading seconds idle, nearly every reading of every
     actor over 50 ms.)  A correct reading can still go over once in a while
     for a real reason: four spinners on a 3-core macOS runner time-share the
     CPU, and a scheduler thread descheduled mid-slice takes its actor's next
     dispatch with it (one CI run read 101 ms in one of 20 readings).  So: ten
     samples, and fail only on a CONSISTENT stale value, an actor over 50 ms
     in half or more of its samples, or more than a quarter of all readings
     over.  Measured 2026-10-04, 30 runs each, macOS under 14 `yes` on 14
     cores and linux/arm64 on 4 CPUs under 4 `yes`: correct runs peaked at 6
     of 40 readings over, while the stale clock reintroduced (dispatch
     stamping the 1024-dispatch scheduler clock, or a coarse clock ticked
     every 100 ms) never read fewer than 21 of 40 over.  Rows are keyed by
     pid: ACTORS ranks by status, so row order can change between samples. *)
  let nsamples = 10 in
  let samples = List.init nsamples (fun _ ->
      Unix.sleepf 0.1;
      data (get sock "ACTORS status 4") |> member "actors" |> to_list
      |> List.map (fun r ->
          (member "pid" r |> to_int,
           match member "idle_ms" r with `Int n -> n | _ -> max_int))) in
  let readings = List.concat samples in
  let over (_, n) = n >= 50 in
  let pids = List.sort_uniq compare (List.map fst readings) in
  let stale_pid p =
    List.length (List.filter (fun r -> fst r = p && over r) readings) * 2
    >= List.length (List.filter (fun r -> fst r = p) readings) in
  let shown = String.concat " " (List.map (fun xs ->
      String.concat "," (List.map (fun (_, n) -> string_of_int n) xs)) samples) in
  (* stderr, so a passing run's readings still reach the CI log. *)
  prerr_endline ("observe_sched idle_ms samples: " ^ shown);
  check "running actors read under 50 ms idle (10 samples)"
    (List.for_all (fun xs -> List.length xs = 4) samples
     && List.length pids = 4
     && not (List.exists stale_pid pids)
     && List.length (List.filter over readings) * 4 <= List.length readings)
    shown;
  let s = data (get sock "SNAPSHOT sched") |> member "sched" in
  check "SNAPSHOT's sched section is lifetime-only (no window)"
    (member "window_ms" s = `Null && member "utilisation" s = `Null
     && (match member "lifetime_utilisation" s with `Float _ -> true | _ -> false))
    (Yojson.Safe.to_string s);
  check "SCHED rejects a window over 5000 ms"
    (error (get sock "SCHED 5001") = Some "bad_args") ""

(* R2 crash ring and TOP: test/native/observe_crashes.march. *)
let crashes sock =
  let c = data (get sock "CRASHES 10") in
  let es = member "crashes" c |> to_list in
  check "CRASHES lists the 3 crashes" (member "total" c |> to_int = 3 && List.length es = 3)
    (Yojson.Safe.to_string c);
  check "restart numbers 3, 2, 1 (newest first)"
    (List.map (fun e -> member "restart" e |> to_int) es = [3; 2; 1]) (Yojson.Safe.to_string c);
  check "every entry is kind crash under one supervisor"
    (List.for_all (fun e -> member "kind" e = `String "crash") es
     && List.length (List.sort_uniq compare (List.map (fun e -> member "supervisor" e) es)) = 1)
    (Yojson.Safe.to_string c);
  check "an entry carries no message field"
    (List.for_all (fun e -> not (List.mem "message" (keys e))) es) "";
  let boss = List.hd es |> member "supervisor" |> to_int in
  let names = data (get sock "NAMES") |> member "names" |> to_list in
  check "the entries' supervisor is boss"
    (List.exists (fun e -> member "name" e = `String "boss" && member "pid" e |> to_int = boss) names) "";
  let a = data (get sock (Printf.sprintf "ACTOR %d" boss)) |> member "actor" in
  check "boss's row counts its children's 3 crashes"
    (member "child_crashes" a |> to_int = 3 && member "crashes" a |> to_int = 0)
    (Yojson.Safe.to_string a);
  let top req = data (get sock req) |> member "top" |> to_list in
  let first_name t = match t with r :: _ -> member "names" r | [] -> `Null in
  check "TOP crashes ranks the crash-looping supervisor first"
    (first_name (top "TOP crashes 1") = `List [ `String "boss" ]) "";
  check "TOP msgs_in over a window ranks the self-sending actor first"
    (first_name (top "TOP msgs_in 1 300") = `List [ `String "loop" ]) "";
  List.iter (fun (req, want) ->
      let got = error (get sock req) in
      check (Printf.sprintf "%s -> %s" req want) (got = Some want)
        (Option.value got ~default:"(data)"))
    [ "TOP", "bad_args"; "TOP bogus 3", "bad_args"; "TOP mbox", "bad_args";
      "TOP mbox 3 500", "bad_args"; "TOP msgs_in 3 10001", "bad_args";
      "CRASHES 0", "bad_args"; "CRASHES 257", "bad_args" ];
  let s = data (get sock "SNAPSHOT crashes") in
  check "SNAPSHOT has a crashes section"
    (member "crashes" s |> member "total" |> to_int = 3) "";
  (* spawned_by: maker spawned two leaves. *)
  let maker = List.find (fun e -> member "name" e = `String "maker") names |> member "pid" |> to_int in
  let m = data (get sock (Printf.sprintf "ACTOR %d" maker)) in
  check "ACTOR maker lists the two actors it spawned"
    (List.length (member "spawned" m |> to_list) = 2) (Yojson.Safe.to_string m);
  let t = data (get sock "TREE") in
  let roots = member "roots" t |> to_list in
  let node = List.find_opt (fun r -> member "pid" r |> to_int = maker) roots in
  check "TREE nests them under maker, linked as spawned"
    (match node with
     | Some r ->
       let kids = member "children" r |> to_list in
       List.length kids = 2 && List.for_all (fun k -> member "link" k = `String "spawned") kids
     | None -> false)
    (Yojson.Safe.to_string t);
  check "loop (spawned by main) stays unsupervised"
    (List.exists (fun p -> p = `Int (List.find (fun e -> member "name" e = `String "loop") names |> member "pid" |> to_int))
       (member "unsupervised" t |> to_list)) "";
  (* TOP's supervision columns over the same tree. *)
  let all = top "TOP mbox 100" in
  let row_of name =
    List.find (fun r -> member "names" r = `List [ `String name ]) all in
  let boss_row = row_of "boss" in
  check "TOP: boss is a one_for_one supervisor, 3 restarts held of 10 in 60 s, 3 child crashes"
    (let sj = member "supervisor" boss_row in
     member "strategy" sj = `String "one_for_one" && member "max_restarts" sj |> to_int = 10
     && member "window_secs" sj |> to_int = 60 && member "restarts_held" sj |> to_int = 3
     && member "child_crashes" boss_row |> to_int = 3 && member "children" boss_row |> to_int = 1
     && member "link" boss_row = `String "none")
    (Yojson.Safe.to_string boss_row);
  let boss_pid = member "pid" boss_row in
  check "TOP: boss's current child is supervised by it and is not a supervisor"
    (List.exists (fun r ->
         member "link" r = `String "supervised" && member "parent" r = boss_pid
         && member "supervisor" r = `Null) all) "";
  let twigs = List.filter (fun r -> member "link" r = `String "spawned") all in
  check "TOP: maker's two twigs are linked spawned, with spawned_by maker and no supervisor"
    (List.length twigs = 2
     && List.for_all (fun r -> member "spawned_by" r = `Int maker && member "parent" r = `Null) twigs)
    (Yojson.Safe.to_string (`List twigs));
  check "TOP: loop, spawned by main, has link none"
    (member "link" (row_of "loop") = `String "none") ""

let () =
  match Sys.argv with
  | [| _; mode; sock; ready |] ->
    wait_ready ready;
    (match mode with
     | "tree" -> tree sock
     | "types" -> types sock
     | "counters" -> counters sock
     | "sched" -> sched sock ready
     | "crashes" -> crashes sock
     | _ -> prerr_endline "mode: tree | types | counters | sched | crashes"; exit 2);
    check "no reply carries the crash message" (!leaked = [])
      (String.concat "; " !leaked);
    (* The golden diff reports a failure; exit 0 so it is shown. *)
    ignore !failures
  | _ -> prerr_endline "usage: observe_snapshot_check tree|types|counters|sched|crashes <socket> <ready-file>"; exit 2
