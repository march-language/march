(* ocap phase 4, Task 1 (specs/plans/2026-11-15-ocap-p4-runtime-plan.md): the
   per-green-thread authority slot, the launch global and the fast path, in
   every runtime.

   Each fixture is a stdlib-spanned program (`--stdlib-source`: the slot
   builtins are stdlib-only) run by the real compiler binary

   - interpreted: [march --stdlib-source f];
   - through the ORC JIT: [march --jit --stdlib-source f];
   - compiled: [march --compile --opt 0 --stdlib-source f], then the binary;
   - as JavaScript ([--target js]) under node, when node is on PATH;

   under one private HOME and a fresh cwd per fixture, and every run's stdout
   must equal the fixture's expected text.

   The slot fixture pins the fast path's contract: [cap_check_raw] answers 0
   while the launch is empty and no frame is in force, 1 while one is, and 0
   again once the slot is restored (the "ever pushed" flag only stops the
   fast path from skipping the slot read; it decides nothing by itself). *)

let have_node = lazy (Sys.command "command -v node >/dev/null 2>&1" = 0)

let rec rm_rf p =
  if Sys.file_exists p then
    if Sys.is_directory p then begin
      Array.iter (fun f -> rm_rf (Filename.concat p f)) (Sys.readdir p);
      Sys.rmdir p
    end else Sys.remove p

let private_home =
  lazy begin
    let d = Filename.temp_dir "march-cap-slot-home" "" in
    Unix.mkdir (Filename.concat d ".cache") 0o755;
    at_exit (fun () -> try rm_rf d with _ -> ());
    d
  end

let write_file path s =
  let oc = open_out_bin path in
  output_string oc s;
  close_out oc

let read_all ic =
  let b = Buffer.create 256 in
  (try
     while true do Buffer.add_channel b ic 1 done
   with End_of_file -> ());
  Buffer.contents b

(* Run [cmd] in [dir] under the private HOME with [env] exported; stdout and
   the exit status.  stderr goes to a file whose text is appended to the
   output on a non-zero exit, so a failure says why. *)
let sh ~dir ?(env = "") cmd =
  let full =
    Printf.sprintf "cd %s && export HOME=%s; %s %s 2>stderr.txt"
      (Filename.quote dir) (Filename.quote (Lazy.force private_home)) env cmd in
  let ic = Unix.open_process_in full in
  let out = read_all ic in
  let code = match Unix.close_process_in ic with
    | Unix.WEXITED c -> c | _ -> -1 in
  if code = 0 then out
  else
    let err =
      try
        let ic = open_in_bin (Filename.concat dir "stderr.txt") in
        let s = really_input_string ic (in_channel_length ic) in
        close_in ic; s
      with _ -> "" in
    Printf.sprintf "%s<exit %d>\n%s" out code err

let modes = [ "interp"; "jit"; "compiled"; "js" ]

(* [mode]'s stdout for [src] (built once per mode, run under each [envs]). *)
let run_mode ~src ~envs mode : string list =
  let exe = Filename.quote (Test_helpers.find_main_exe ()) in
  let dir = Filename.temp_dir "march-cap-slot" "" in
  Fun.protect ~finally:(fun () -> try rm_rf dir with _ -> ()) (fun () ->
      write_file (Filename.concat dir "slot.march") src;
      match mode with
      | "interp" ->
        List.map (fun env -> sh ~dir ~env (exe ^ " --stdlib-source slot.march")) envs
      | "jit" ->
        List.map (fun env -> sh ~dir ~env (exe ^ " --jit --stdlib-source slot.march")) envs
      | "compiled" ->
        let b = sh ~dir (exe ^ " --compile --opt 0 --stdlib-source slot.march -o ./prog") in
        if not (Sys.file_exists (Filename.concat dir "prog")) then List.map (fun _ -> b) envs
        else List.map (fun env -> sh ~dir ~env "./prog") envs
      | _ ->
        let b = sh ~dir (exe ^ " --target js --opt 0 --stdlib-source slot.march -o ./prog.mjs") in
        if not (Sys.file_exists (Filename.concat dir "prog.mjs")) then List.map (fun _ -> b) envs
        else List.map (fun env -> sh ~dir ~env "node ./prog.mjs") envs)

let check_all ?(skip = []) ~name ~src (cases : (string * string) list) =
  List.iter (fun mode ->
      if List.mem mode skip || (mode = "js" && not (Lazy.force have_node)) then ()
      else
        let outs = run_mode ~src ~envs:(List.map fst cases) mode in
        List.iter2 (fun (env, expected) got ->
            Alcotest.(check string)
              (Printf.sprintf "%s %s [%s]" name mode env) expected got)
          cases outs)
    modes

(* Save, push, enter and restore around three [cap_check_raw] reads. *)
let slot_src = {|mod CapSlotFixture do
  needs IO.Console
  fn raw() : Int do
    cap_check_raw("IO.Console", "")
  end
  fn main(_c : Cap(IO.Console)) do
    let before = raw()
    let s0 = cap_save()
    let old = cap_push(Authority.Layer(ByFnNeeds("f"), "IO.Console", Nil))
    let inner = cap_save()
    let layers = List.length(cap_layers())
    cap_restore(old)
    let o2 = cap_enter(inner)
    let during = raw()
    cap_restore(o2)
    cap_restore(s0)
    let after = raw()
    println(int_to_string(before))
    println(int_to_string(during))
    println(int_to_string(after))
    println("layers " ++ int_to_string(layers))
    println("empty " ++ int_to_string(List.length(cap_layers())))
  end
end
|}

let test_slot () =
  check_all ~name:"slot" ~src:slot_src
    [ ("", "0\n1\n0\nlayers 1\nempty 0\n") ]

let grant_src = {|mod CapGrantFixture do
  needs IO.Console
  fn main(_c : Cap(IO.Console)) do
    println("\"" ++ cap_grant_text() ++ "\"")
  end
end
|}

let test_grant_text () =
  check_all ~name:"grant_text" ~src:grant_src
    [ ("unset MARCH_GRANT;", "\"\"\n");
      ("export MARCH_GRANT='   ';", "\"\"\n");
      ("export MARCH_GRANT=' IO.Console ';", "\"IO.Console\"\n") ]

(* A frame entered and left many times leaves no live object behind
   (compiled and JIT; the interpreter's live_allocs answers 0 throughout, and
   the JS target has no live_allocs). *)
let leak_src = {|mod CapSlotLeak do
  needs IO.Console
  fn spin(n : Int) : () do
    if n == 0 do ()
    else
      let old = cap_push(Authority.Layer(ByFnNeeds("f"), "IO.FileRead(\"/srv/\")",
                  Cons(Authority.Scope("IO.FileRead", Authority.Paths(Cons("/srv/", Nil))), Nil)))
      let r = cap_check_raw("IO.FileRead", "/srv/x")
      cap_restore(old)
      spin(n - 1 + r - 1)
    end
  end
  fn main(_c : Cap(IO.Console)) do
    spin(10)
    let before = live_allocs()
    spin(1000)
    let after = live_allocs()
    println(if after - before <= 0 do "flat" else "leak " ++ int_to_string(after - before) end)
  end
end
|}

let test_no_leak () =
  check_all ~skip:[ "js" ] ~name:"no_leak" ~src:leak_src [ ("", "flat\n") ]

(* Compiled code holds the LAST reference to a CapAuthRef and drops it: a
   saved ref outlives the frame it was taken in (the slot was restored
   under it), then goes out of scope, both bare and captured by a closure
   that is never called (Task 4's capture shape).  The drop must release the
   whole layer list, not just its top cell. *)
let drop_src = {|mod CapSlotDrop do
  needs IO.Console
  fn hold(n : Int) : Int do
    let old = cap_push(Authority.Layer(ByFnNeeds("f"), "IO.FileRead(\"/srv/\")",
                Cons(Authority.Scope("IO.FileRead", Authority.Paths(Cons("/srv/", Nil))), Nil)))
    let r = cap_save()
    cap_restore(old)
    n + 1
  end
  fn capture(n : Int) : Int do
    let old = cap_push(Authority.Layer(ByFnNeeds("g"), "IO.Console", Nil))
    let r = cap_save()
    cap_restore(old)
    let f = fn _ -> cap_enter(r)
    n + 1
  end
  fn spin(n : Int) : () do
    if n == 0 do ()
    else
      let a = hold(n)
      let b = capture(a)
      spin(b - 3)
    end
  end
  fn main(_c : Cap(IO.Console)) do
    spin(10)
    let before = live_allocs()
    spin(1000)
    let after = live_allocs()
    println(if after - before <= 0 do "flat" else "leak " ++ int_to_string(after - before) end)
  end
end
|}

let test_compiled_drop () =
  check_all ~skip:[ "js" ] ~name:"compiled_drop" ~src:drop_src [ ("", "flat\n") ]

(* ocap phase 4, Task 6: actors and tasks spawned under a frame hold their
   own reference to the authority they were spawned under (the actor meta's
   [auth], a supervisor slot's [first_auth], a task proc's slot), and every
   one is released when the actor, slot or task dies.  10,000 spawn/exit
   cycles under a frame (an actor spawned and killed, a task spawned and
   awaited, and every tenth cycle a supervisor with one child, spawned and
   killed), compiled with [--rc-trace] and run with [MARCH_TRACE_GC=1].

   The verdict is computed from the trace per ADDRESS, not by
   scripts/gc-trace-report.py's per-object fold: every scheduler thread
   writes its own event buffer, so the file is not in event order and the
   fold, which replays it in file order, reports phantom live objects
   whenever a reused address's free lands after its next allocation (the
   report says "allocated before tracing").  Per address, allocs + increments
   - decrements - frees is the final count of whatever lives there, in any
   order.  Every non-immortal address an authority site touched
   ([march_cap_*]) must balance; a handful may still be held by the last
   killed actors when main returns (their metas are reclaimed lazily), so
   the bound is 16.  Dropping the meta's release (march_runtime.c,
   meta_free) unbalances about 20,000. *)
let spawn_leak_src = {|mod CapSpawnLeak do
  needs IO.Console
  needs IO.FileRead
  needs IO.Spawn
  actor W do
    state { n : Int }
    init  { n: 0 }
    on Ping() do
      { n: state.n + 1 }
    end
  end
  actor Boss do
    state { child : Int }
    init  { child: 0 }
    supervise do
      strategy one_for_one
      max_restarts 10 within 60
      W child
    end
  end
  fn cycle(i : Int) : Int needs IO.FileRead("/srv/"), IO.Spawn do
    let w = spawn(W)
    send(w, Ping())
    kill(w)
    if i % 10 == 0 do
      let b = spawn(Boss)
      kill(b)
    else ()
    end
    match Task.async(fn () -> i + 1) do
    Ok(t) ->
      match Task.await(t) do
      Ok(n) -> n
      Err(_) -> 0
      end
    Err(_) -> 0
    end
  end
  fn spin(i : Int, n : Int, acc : Int) : Int do
    if i == n do acc else spin(i + 1, n, acc + cycle(i) - i) end
  end
  fn main() do
    let k = spin(0, 10000, 0)
    run_until_idle()
    println(int_to_string(k))
  end
end
|}

(* (authority-touched non-immortal addresses, those that do not balance). *)
let unbalanced_cap_addresses (trace_dir : string) : int * (string * int) list =
  let sites =
    match Yojson.Safe.from_file (Filename.concat trace_dir "sites.json") with
    | `List l -> Array.of_list (List.map (function `String s -> s | _ -> "") l)
    | _ -> [||] in
  let is_cap sid =
    sid >= 0 && sid < Array.length sites
    && (let s = sites.(sid) in
        let p = ":march_cap_" in
        let n = String.length s and m = String.length p in
        let rec at i = i + m <= n && (String.sub s i m = p || at (i + 1)) in
        at 0) in
  let bal : (string, int) Hashtbl.t = Hashtbl.create 4096 in
  let touched : (string, unit) Hashtbl.t = Hashtbl.create 4096 in
  let immortal : (string, unit) Hashtbl.t = Hashtbl.create 64 in
  let ic = open_in_bin (Filename.concat trace_dir "gc.jsonl") in
  (try
     while true do
       let line = input_line ic in
       if String.trim line <> "" then
         match Yojson.Safe.from_string line with
         | `Assoc kv ->
           let str k = match List.assoc_opt k kv with Some (`String s) -> s | _ -> "" in
           let int k = match List.assoc_opt k kv with Some (`Int i) -> i | _ -> -1 in
           let addr = str "addr" in
           if is_cap (int "site") then Hashtbl.replace touched addr ();
           let d = match str "event" with
             | "alloc" | "inc_ref" -> 1
             | "dec_ref" | "free" -> -1
             | "immortal" -> Hashtbl.replace immortal addr (); 0
             | _ -> 0 in
           Hashtbl.replace bal addr (d + Option.value ~default:0 (Hashtbl.find_opt bal addr))
         | _ -> ()
     done
   with End_of_file -> ());
  close_in ic;
  Hashtbl.fold
    (fun addr () (n, bad) ->
       if Hashtbl.mem immortal addr then (n, bad)
       else
         let b = Option.value ~default:0 (Hashtbl.find_opt bal addr) in
         (n + 1, if b <> 0 then (addr, b) :: bad else bad))
    touched (0, [])

let test_spawn_cycles_no_leak () =
  let exe = Filename.quote (Test_helpers.find_main_exe ()) in
  let dir = Filename.temp_dir "march-cap-spawn-leak" "" in
  Fun.protect ~finally:(fun () -> try rm_rf dir with _ -> ()) (fun () ->
      write_file (Filename.concat dir "leak.march") spawn_leak_src;
      let b = sh ~dir (exe ^ " --compile --opt 0 --rc-trace leak.march -o ./prog") in
      if not (Sys.file_exists (Filename.concat dir "prog")) then
        Alcotest.failf "build failed:\n%s" b;
      Alcotest.(check string) "the program ran" "10000\n"
        (sh ~dir ~env:"export MARCH_TRACE_GC=1;" "./prog");
      let n, bad = unbalanced_cap_addresses (Filename.concat dir "trace/gc") in
      Alcotest.(check bool) "the trace saw the authority's cells" true (n > 1000);
      if List.length bad > 16 then
        Alcotest.failf "%d of %d authority-touched addresses still hold a reference \
                        (e.g. %s)" (List.length bad) n
          (String.concat ", "
             (List.map (fun (a, b) -> Printf.sprintf "%s:%+d" a b)
                (List.filteri (fun i _ -> i < 5) bad))))

let tests =
  [ ( "cap_runtime_slot",
      [ Alcotest.test_case "save/push/enter/restore around cap_check_raw" `Quick test_slot;
        Alcotest.test_case "cap_grant_text reads MARCH_GRANT, trimmed" `Quick test_grant_text;
        Alcotest.test_case "push/restore leaves nothing live" `Quick test_no_leak;
        Alcotest.test_case "compiled code dropping the last CapAuthRef releases it" `Quick
          test_compiled_drop;
        Alcotest.test_case "10,000 spawn/exit cycles under a frame release every authority"
          `Quick test_spawn_cycles_no_leak ] ) ]
