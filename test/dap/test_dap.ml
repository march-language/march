(* End-to-end DAP integration tests: spawn the real `march dap` server, speak the
   Debug Adapter Protocol over stdio with Content-Length framing, and assert
   breakpoint / stepping / variable / output / termination behaviour.

   This is the layer the engine unit tests cannot reach: the worker-thread
   rendezvous, request dispatch, and stdio framing in lib/dap + bin/main.ml. *)

(* The march binary, relative to THIS test exe (.../test/dap/test_dap.exe). *)
let exe = Filename.concat (Filename.dirname Sys.executable_name) "../../bin/main.exe"

(* ── Content-Length framing over the process pipes ────────────────────────── *)

let send oc (json : Yojson.Safe.t) =
  let body = Yojson.Safe.to_string json in
  Printf.fprintf oc "Content-Length: %d\r\n\r\n%s" (String.length body) body;
  flush oc

let read_frame ic : Yojson.Safe.t option =
  let strip_cr s =
    let n = String.length s in
    if n > 0 && s.[n - 1] = '\r' then String.sub s 0 (n - 1) else s
  in
  let rec headers len =
    match input_line ic with
    | exception End_of_file -> len
    | line ->
      let line = strip_cr line in
      if line = "" then len
      else
        let len = match String.split_on_char ':' line with
          | k :: rest when String.lowercase_ascii (String.trim k) = "content-length" ->
            (try int_of_string (String.trim (String.concat ":" rest)) with _ -> len)
          | _ -> len in
        headers len
  in
  let len = headers (-1) in
  if len < 0 then None
  else begin
    let buf = Bytes.create len in
    (try really_input ic buf 0 len;
       Some (Yojson.Safe.from_string (Bytes.to_string buf))
     with _ -> None)
  end

let member k j = match j with `Assoc l -> (try List.assoc k l with Not_found -> `Null) | _ -> `Null
let is_event e j = member "type" j = `String "event" && member "event" j = `String e
let is_cmd c j = member "command" j = `String c

(* Read frames until [pred] matches (returns it) or [max] frames seen. *)
let read_until ic ~max pred : Yojson.Safe.t option =
  let rec loop n =
    if n <= 0 then None
    else match read_frame ic with
      | None -> None
      | Some j -> if pred j then Some j else loop (n - 1)
  in
  loop max

let str_contains hay needle =
  let hl = String.length hay and nl = String.length needle in
  let rec f i = if i + nl > hl then false
                else if String.sub hay i nl = needle then true else f (i + 1) in
  nl = 0 || f 0

(* ── Harness ──────────────────────────────────────────────────────────────── *)

let seq = ref 0
let req oc command args =
  incr seq;
  send oc (`Assoc [
    "seq", `Int !seq; "type", `String "request";
    "command", `String command; "arguments", args ])

let write_program content =
  let path = Filename.temp_file (Printf.sprintf "march_dap_%d_" (Unix.getpid ())) ".march" in
  let oc = open_out path in
  output_string oc content; close_out oc; path

(* Spawn `march dap`, run [k ~ic ~oc ~path], always clean up. A SIGALRM guards
   against a hung server. *)
let with_dap content k =
  Sys.set_signal Sys.sigalrm
    (Sys.Signal_handle (fun _ -> failwith "march dap did not respond (timeout)"));
  ignore (Unix.alarm 30);
  let path = write_program content in
  let (ic, oc, ec) = Unix.open_process_args_full exe [| exe; "dap" |] (Unix.environment ()) in
  let finish () =
    (try req oc "disconnect" (`Assoc []) with _ -> ());
    (try ignore (Unix.close_process_full (ic, oc, ec)) with _ -> ());
    (try Sys.remove path with _ -> ());
    ignore (Unix.alarm 0)
  in
  match k ~ic ~oc ~path with
  | result -> finish (); result
  | exception e -> finish (); raise e

(* initialize + breakpoints + configurationDone + launch, in the canonical order. *)
let boot ~ic ~oc ~path ?(bps = []) ?(stop_on_entry = false) () =
  req oc "initialize" (`Assoc ["adapterID", `String "march"]);
  ignore (read_until ic ~max:10 (is_event "initialized"));
  let bp_objs = List.map (fun l -> `Assoc ["line", `Int l]) bps in
  req oc "setBreakpoints" (`Assoc [
    "source", `Assoc ["path", `String path];
    "breakpoints", `List bp_objs ]);
  let bp_resp = read_until ic ~max:10 (is_cmd "setBreakpoints") in
  req oc "configurationDone" (`Assoc []);
  req oc "launch" (`Assoc ["program", `String path; "stopOnEntry", `Bool stop_on_entry]);
  bp_resp

(* ── Programs ─────────────────────────────────────────────────────────────── *)

let prog_basic = String.concat "\n" [
  "mod Main do";          (* 1 *)
  "  fn main() do";       (* 2 *)
  "    let x = 1";        (* 3 *)
  "    let y = x + 41";   (* 4 <- bp *)
  "    println(y)";       (* 5 *)
  "  end";                (* 6 *)
  "end"; "" ]

let prog_call = String.concat "\n" [
  "mod Main do";              (* 1 *)
  "  fn helper(n) do";        (* 2 *)
  "    let r = n * 2";        (* 3 <- step-in target *)
  "    r";                    (* 4 *)
  "  end";                    (* 5 *)
  "  fn main() do";           (* 6 *)
  "    let a = helper(5)";    (* 7 <- bp *)
  "    println(a)";           (* 8 *)
  "  end";                    (* 9 *)
  "end"; "" ]

let prog_print = String.concat "\n" [
  "mod Main do";                  (* 1 *)
  "  fn main() do";               (* 2 *)
  "    println(\"hello42\")";     (* 3 *)
  "  end";                        (* 4 *)
  "end"; "" ]

let prog_panic = String.concat "\n" [
  "mod Main do";                  (* 1 *)
  "  fn main() do";               (* 2 *)
  "    panic(\"boom\")";          (* 3 *)
  "  end";                        (* 4 *)
  "end"; "" ]

let prog_two_bps = String.concat "\n" [
  "mod Main do";          (* 1 *)
  "  fn main() do";       (* 2 *)
  "    let a = 1";        (* 3 <- bp *)
  "    let b = 2";        (* 4 *)
  "    let c = 3";        (* 5 <- bp *)
  "    println(c)";       (* 6 *)
  "  end";                (* 7 *)
  "end"; "" ]

(* ── Tests ────────────────────────────────────────────────────────────────── *)

let test_breakpoint_stack_vars () =
  with_dap prog_basic (fun ~ic ~oc ~path ->
      let bp = boot ~ic ~oc ~path ~bps:[4] () in
      let bp_ok = match bp with
        | Some j -> (match member "breakpoints" (member "body" j) with
            | `List (b :: _) -> member "verified" b = `Bool true | _ -> false)
        | None -> false in
      let stopped = read_until ic ~max:60 (is_event "stopped") in
      let stopped_bp = match stopped with
        | Some j -> member "reason" (member "body" j) = `String "breakpoint" | None -> false in
      req oc "stackTrace" (`Assoc ["threadId", `Int 1]);
      let st = read_until ic ~max:10 (is_cmd "stackTrace") in
      let line4 = match st with
        | Some j -> (match member "stackFrames" (member "body" j) with
            | `List (f0 :: _) -> member "line" f0 = `Int 4 | _ -> false)
        | None -> false in
      req oc "variables" (`Assoc ["variablesReference", `Int 1]);
      let vars = read_until ic ~max:10 (is_cmd "variables") in
      let has_x = match vars with
        | Some j -> (match member "variables" (member "body" j) with
            | `List vs -> List.exists (fun v ->
                member "name" v = `String "x" && member "value" v = `String "1") vs
            | _ -> false)
        | None -> false in
      req oc "continue" (`Assoc ["threadId", `Int 1]);
      let term = read_until ic ~max:60 (is_event "terminated") <> None in
      Alcotest.(check bool) "breakpoint verified" true bp_ok;
      Alcotest.(check bool) "stopped at breakpoint" true stopped_bp;
      Alcotest.(check bool) "top frame on line 4" true line4;
      Alcotest.(check bool) "local x = 1 visible" true has_x;
      Alcotest.(check bool) "terminates after continue" true term)

let test_step_into () =
  with_dap prog_call (fun ~ic ~oc ~path ->
      ignore (boot ~ic ~oc ~path ~bps:[7] ());
      ignore (read_until ic ~max:60 (is_event "stopped"));
      (* step into helper() — should land on line 3 with a deeper stack *)
      req oc "stepIn" (`Assoc ["threadId", `Int 1]);
      let stepped = read_until ic ~max:60 (is_event "stopped") in
      req oc "stackTrace" (`Assoc ["threadId", `Int 1]);
      let st = read_until ic ~max:10 (is_cmd "stackTrace") in
      let line3, depth2 = match st with
        | Some j -> (match member "stackFrames" (member "body" j) with
            | `List ((f0 :: _) as fs) ->
              (member "line" f0 = `Int 3, List.length fs >= 2)
            | _ -> (false, false))
        | None -> (false, false) in
      req oc "continue" (`Assoc ["threadId", `Int 1]);
      let term = read_until ic ~max:60 (is_event "terminated") <> None in
      Alcotest.(check bool) "step-in produced a stop" true (stepped <> None);
      Alcotest.(check bool) "stepped into helper (line 3)" true line3;
      Alcotest.(check bool) "stack has caller + callee" true depth2;
      Alcotest.(check bool) "terminates after continue" true term)

let test_output_events () =
  with_dap prog_print (fun ~ic ~oc ~path ->
      ignore (boot ~ic ~oc ~path ());
      (* The output event (async pipe drain) and the terminated event can arrive
         in either order — read until both are seen. *)
      let saw_out = ref false and saw_term = ref false in
      let rec loop n =
        if (!saw_out && !saw_term) || n <= 0 then ()
        else match read_frame ic with
          | None -> ()
          | Some j ->
            if is_event "terminated" j then saw_term := true;
            if is_event "output" j &&
               (match member "output" (member "body" j) with
                | `String s -> str_contains s "hello42" | _ -> false)
            then saw_out := true;
            loop (n - 1)
      in
      loop 60;
      Alcotest.(check bool) "program stdout surfaced as an output event" true !saw_out;
      Alcotest.(check bool) "terminates" true !saw_term)

let test_panic_terminates () =
  with_dap prog_panic (fun ~ic ~oc ~path ->
      ignore (boot ~ic ~oc ~path ());
      (* A panic must not hang the adapter: a terminated event still arrives. *)
      let term = read_until ic ~max:60 (is_event "terminated") <> None in
      Alcotest.(check bool) "panicking program still terminates the session" true term)

let test_multiple_breakpoints () =
  with_dap prog_two_bps (fun ~ic ~oc ~path ->
      ignore (boot ~ic ~oc ~path ~bps:[3; 5] ());
      let stop1 = read_until ic ~max:60 (is_event "stopped") in
      req oc "stackTrace" (`Assoc ["threadId", `Int 1]);
      let st1 = read_until ic ~max:10 (is_cmd "stackTrace") in
      let at3 = match st1 with
        | Some j -> (match member "stackFrames" (member "body" j) with
            | `List (f0 :: _) -> member "line" f0 = `Int 3 | _ -> false)
        | None -> false in
      req oc "continue" (`Assoc ["threadId", `Int 1]);
      let stop2 = read_until ic ~max:60 (is_event "stopped") in
      req oc "stackTrace" (`Assoc ["threadId", `Int 1]);
      let st2 = read_until ic ~max:10 (is_cmd "stackTrace") in
      let at5 = match st2 with
        | Some j -> (match member "stackFrames" (member "body" j) with
            | `List (f0 :: _) -> member "line" f0 = `Int 5 | _ -> false)
        | None -> false in
      req oc "continue" (`Assoc ["threadId", `Int 1]);
      let term = read_until ic ~max:60 (is_event "terminated") <> None in
      Alcotest.(check bool) "first stop on line 3"  true (stop1 <> None && at3);
      Alcotest.(check bool) "second stop on line 5" true (stop2 <> None && at5);
      Alcotest.(check bool) "terminates after both" true term)

let () =
  Alcotest.run "dap"
    [ "stdio", [
          Alcotest.test_case "breakpoint/stack/vars/continue" `Quick test_breakpoint_stack_vars;
          Alcotest.test_case "step into a function"           `Quick test_step_into;
          Alcotest.test_case "program output -> output events" `Quick test_output_events;
          Alcotest.test_case "panic still terminates"          `Quick test_panic_terminates;
          Alcotest.test_case "multiple breakpoints"            `Quick test_multiple_breakpoints;
        ] ]
