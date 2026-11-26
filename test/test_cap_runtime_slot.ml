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
  fn main() needs IO.Console do
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
  fn main() needs IO.Console do
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
                  Cons(Authority.CapEntry("IO.FileRead", Authority.Paths(Cons("/srv/", Nil))), Nil)))
      let r = cap_check_raw("IO.FileRead", "/srv/x")
      cap_restore(old)
      spin(n - 1 + r - 1)
    end
  end
  fn main() needs IO.Console do
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
                Cons(Authority.CapEntry("IO.FileRead", Authority.Paths(Cons("/srv/", Nil))), Nil)))
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
  fn main() needs IO.Console do
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

(* A caught panic must leave the authority it puts back alive.  [boom] never
   restores what its push returned, so the compiler drops that value right
   after the push.  When the value was the reference to the outer authority
   (before the saved stack), an unwind that "adopted" it, taking no reference
   of its own, freed the outer authority while it was in force, and [under]'s
   cap_restore released it again: "RC underflow" (a use-after-free under
   ASan).  Now the value is a token and the runtime's saved stack holds the
   reference, so the drop is a no-op; this keeps guarding the same outcome.
   History: specs/progress/2026-11-24-ocap-cap-unwind-mark-leak.md. *)
let unwind_adopt_src = {|mod CapUnwindAdopt do
  needs IO.Console
  fn layer(name : String) do
    Authority.Layer(ByFnNeeds(name), "IO.FileRead(\"/srv/\")",
      Cons(Authority.CapEntry("IO.FileRead", Authority.Paths(Cons("/srv/", Nil))), Nil))
  end
  fn boom(n : Int) : Int do
    let _old = cap_push(layer("inner"))
    panic("boom " ++ int_to_string(n))
  end
  fn catch_one(act : Bool -> Int) : Int do
    match __try_call_val(act) do
    Ok(_) -> 0
    Err(_) -> 1
    end
  end
  fn bare(act : Bool -> Int, n : Int, acc : Int) : Int do
    if n == 0 do acc else bare(act, n - 1, acc + catch_one(act)) end
  end
  fn under(act : Bool -> Int, n : Int, acc : Int) : Int do
    if n == 0 do acc
    else
      let old = cap_push(layer("outer"))
      let c = catch_one(act)
      let depth = List.length(cap_layers())
      cap_restore(old)
      under(act, n - 1, acc + c + depth - 1)
    end
  end
  fn main() needs IO.Console do
    let act = fn _ -> boom(1)
    let caught = bare(act, 200, 0) + under(act, 200, 0)
    println("caught " ++ int_to_string(caught))
    println("layers " ++ int_to_string(List.length(cap_layers())))
  end
end
|}

let test_unwind_keeps_mark () =
  (* Not interpreted: the interpreter puts an authority back when a framed
     call or a captured value returns (eval.ml's Fun.protect), not at the
     catch, so [boom]'s raw cap_push stays in force there after [bare]'s
     catches and the printlns are refused.  Only stdlib-internal code can
     push without a frame. *)
  check_all ~skip:[ "interp" ] ~name:"unwind_adopt" ~src:unwind_adopt_src
    [ ("", "caught 400\nlayers 0\n") ]

(* What a caught panic abandons, the catcher releases: the saved authority
   of every frame the panic left without restoring (one frame, two nested
   frames, a frame entered a second time) is held by the runtime, not by the
   abandoned code, so march_cap_unwind can release exactly those.  Before,
   each such frame's saved value kept one reference to the authority below
   it, and that authority (its cell and its layer) was never freed.

   A panic leaks other things by itself (its message, the closure), so
   each shape is measured twice: caught under the launch authority, whose
   slot value is not counted, and caught under a pushed, refcounted one that
   is restored after every catch.  The two must leave the same number of
   objects behind, and no more than one per catch (the message).  Compiled
   and JIT: the other two have no live_allocs. *)
let unwind_exact_src = {|mod CapUnwindExact do
  needs IO.Console
  fn layer(name : String) do
    Authority.Layer(ByFnNeeds(name), "IO.FileRead(\"/srv/\")",
      Cons(Authority.CapEntry("IO.FileRead", Authority.Paths(Cons("/srv/", Nil))), Nil))
  end
  -- Not known to panic where it is called, so the caller's restore stays.
  fn thrower(n : Int) : Int do
    if n >= 0 do panic("boom " ++ int_to_string(n)) else n end
  end
  fn one(n : Int) : Int do
    let old = cap_push(layer("inner"))
    let r = thrower(n)
    cap_restore(old)
    r
  end
  fn two(n : Int) : Int do
    let old = cap_push(layer("middle"))
    let r = one(n)
    cap_restore(old)
    r
  end
  fn again(n : Int) : Int do
    let old = Authority.enter_fn(layer("again"))
    let old2 = Authority.enter_fn(layer("again"))
    let r = thrower(n)
    cap_restore(old2)
    cap_restore(old)
    r
  end
  fn catch_one(act : Bool -> Int) : Int do
    match __try_call_val(act) do
    Ok(_) -> 0
    Err(_) -> 1
    end
  end
  fn bare(act : Bool -> Int, n : Int, acc : Int) : Int do
    if n == 0 do acc else bare(act, n - 1, acc + catch_one(act)) end
  end
  fn under(act : Bool -> Int, n : Int, acc : Int) : Int do
    if n == 0 do acc
    else
      let old = cap_push(layer("outer"))
      let c = catch_one(act)
      cap_restore(old)
      under(act, n - 1, acc + c)
    end
  end
  fn measure(name : String, act : Bool -> Int) : Int do
    let warm = bare(act, 5, 0) + under(act, 5, 0)
    let a = live_allocs()
    let x = bare(act, 100, 0)
    let b = live_allocs()
    let y = under(act, 100, 0)
    let c = live_allocs()
    println(name ++ ": " ++ (if c - b <= b - a && b - a <= 100 do "exact" else
      "under a frame leaves " ++ int_to_string(c - b) ++ ", bare " ++ int_to_string(b - a) end))
    warm + x + y
  end
  fn main() needs IO.Console do
    let n = measure("one frame", fn _ -> one(1))
      + measure("two frames", fn _ -> two(1))
      + measure("entered twice", fn _ -> again(1))
    println("caught " ++ int_to_string(n))
    println("layers " ++ int_to_string(List.length(cap_layers())))
  end
end
|}

let test_unwind_exact () =
  check_all ~skip:[ "js"; "interp" ] ~name:"unwind_exact" ~src:unwind_exact_src
    [ ("", "one frame: exact\ntwo frames: exact\nentered twice: exact\ncaught 630\nlayers 0\n") ]

(* Task 10b: cap_enter of the authority already in force changes nothing
   and touches no count (natively it returns a tagged word that cap_restore
   treats as "nothing to undo").  Pinned in every runtime: the launch
   authority entered under itself, a frame's authority under that frame, a
   different authority inside a same-authority entry and the same one again
   inside that, and the frame's authority entered from outside it.  Each
   number is the length of the layers in force at that point. *)
let enter_same_src = {|mod CapEnterSame do
  needs IO.Console
  fn n() : Int do
    List.length(cap_layers())
  end
  fn show(xs : List(Int)) : String do
    match xs do
    Nil -> ""
    Cons(x, Nil) -> int_to_string(x)
    Cons(x, rest) -> int_to_string(x) ++ " " ++ show(rest)
    end
  end
  fn main() needs IO.Console do
    let s0 = cap_save()
    let e0 = cap_enter(s0)
    let a = n()
    cap_restore(e0)
    let b = n()
    let old = cap_push(Authority.Layer(ByFnNeeds("f"), "IO.Console", Nil))
    let inner = cap_save()
    let e1 = cap_enter(inner)
    let c = n()
    let e2 = cap_enter(s0)
    let d = n()
    let e3 = cap_enter(s0)
    let d2 = n()
    cap_restore(e3)
    let d3 = n()
    cap_restore(e2)
    let e = n()
    cap_restore(e1)
    let f = n()
    cap_restore(old)
    let g = n()
    let e4 = cap_enter(inner)
    let h = n()
    let r = cap_check_raw("IO.Console", "")
    cap_restore(e4)
    let i = n()
    println(show([a, b, c, d, d2, d3, e, f, g, h, i]))
    println("raw " ++ int_to_string(r) ++ " then " ++ int_to_string(cap_check_raw("IO.Console", "")))
  end
end
|}

let test_enter_same () =
  check_all ~name:"enter_same" ~src:enter_same_src
    [ ("", "0 0 1 0 0 0 1 1 0 1 0\nraw 1 then 0\n") ]

(* The Task 10b fast paths leave nothing live (compiled and JIT): a
   same-authority cap_enter/cap_restore, nested inside different ones; a
   compiled frame entered from the launch authority (its pushed cell is
   cached, immortal) and from inside another frame (allocated, as before);
   a captured function value called under the authority it was made under;
   and a panic caught inside a frame (the catch puts the authority back). *)
let fast_leak_src = {|mod CapFastLeak do
  needs IO.Console
  needs IO.FileRead
  fn outer(x : Int) : Int needs IO.Console, IO.FileRead("/srv/") do
    inner(x) + 1
  end
  fn inner(x : Int) : Int needs IO.Console, IO.FileRead("/srv/a/") do
    x + 1
  end
  fn boom(x : Int) : Int needs IO.Console, IO.FileRead("/srv/") do
    if x >= 0 do panic("boom") else x end
  end
  fn compose(f : Int -> Int, g : Int -> Int) : Int -> Int do
    fn x -> g(f(x))
  end
  fn spin(n : Int, h : Int -> Int) : () do
    if n == 0 do ()
    else
      let s0 = cap_save()
      let old = cap_push(Authority.Layer(ByFnNeeds("f"), "IO.Console", Nil))
      let mid = cap_save()
      let e1 = cap_enter(mid)
      let e2 = cap_enter(s0)
      let e3 = cap_enter(mid)
      cap_restore(e3)
      cap_restore(e2)
      cap_restore(e1)
      cap_restore(old)
      let a = outer(n)
      let b = inner(a)
      let c = h(b)
      let d = match __try_call_val(fn _ -> boom(c)) do
        Ok(v) -> v
        Err(_) -> 0
      end
      spin(n - 1 + d, h)
    end
  end
  fn main() needs IO.Console do
    let h = compose(fn x -> x + 1, fn x -> x * 2)
    spin(10, h)
    let before = live_allocs()
    spin(1000, h)
    let after = live_allocs()
    println(if after - before <= 0 do "flat" else "leak " ++ int_to_string(after - before) end)
  end
end
|}

let test_fast_paths_no_leak () =
  check_all ~skip:[ "js" ] ~name:"fast_paths_no_leak" ~src:fast_leak_src [ ("", "flat\n") ]

(* ocap phase 4, Task 6: actors and tasks spawned under a frame hold their
   own reference to the authority they were spawned under (the actor meta's
   [auth], a supervisor slot's [first_auth], a task proc's slot), and every
   one is released when the actor, slot or task dies.  10,000 spawn/exit
   cycles under a frame (an actor spawned and killed, a task spawned and
   awaited, and every tenth cycle a supervisor with one child, spawned and
   killed), compiled with [--rc-trace] and run with [MARCH_TRACE_GC=1].
   [cycle] is entered from inside [run]'s frame, not from the launch
   authority: entering from launch reuses a cached immortal cell (Task 10b),
   which would leave nothing mortal for the spawned actors to hold.

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
   the bound is 16.  Measured: 1 per run, constant in the cycle count, not
   traced to its holder (that it is a lazily reclaimed meta is a guess; see
   specs/todos/2026-11-16-gc-trace-report-multithread-file-order.md).
   Dropping the meta's release (march_runtime.c,
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
  fn cycle(i : Int) : Int needs IO.FileRead("/srv/data/"), IO.Spawn do
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
  fn run(n : Int) : Int needs IO.FileRead("/srv/"), IO.Spawn do
    spin(0, n, 0)
  end
  fn main() do
    let k = run(10000)
    run_until_idle()
    println(int_to_string(k))
  end
end
|}

(* (events at authority sites on non-immortal addresses, those addresses
   that do not balance). *)
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
  let touched : (string, int) Hashtbl.t = Hashtbl.create 4096 in
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
           if is_cap (int "site") then
             Hashtbl.replace touched addr
               (1 + Option.value ~default:0 (Hashtbl.find_opt touched addr));
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
    (fun addr events (n, bad) ->
       if Hashtbl.mem immortal addr then (n, bad)
       else
         let b = Option.value ~default:0 (Hashtbl.find_opt bal addr) in
         (n + events, if b <> 0 then (addr, b) :: bad else bad))
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
      (* Events, not distinct addresses: how many addresses 10,000 cells
         occupy is up to the allocator's reuse (1,776 on macOS; under 1,000
         with glibc). *)
      Alcotest.(check bool) "the trace saw the authority's cells" true (n > 10000);
      if List.length bad > 16 then
        Alcotest.failf "%d authority-touched addresses (%d events) still hold a \
                        reference (e.g. %s)" (List.length bad) n
          (String.concat ", "
             (List.map (fun (a, b) -> Printf.sprintf "%s:%+d" a b)
                (List.filteri (fun i _ -> i < 5) bad))))

(* A caught panic leaves the handle uses it abandoned (handle_enter with no
   handle_leave).  The catch sites that put the authority back also unwind
   the green thread's stack of entered boxes to their mark.  Without it the
   box's in-flight count never reaches zero, so close_listener sets CLOSED
   but the release waits for a leave that cannot come, and the port stays
   bound until the box is dropped: the second listen on it fails.
   The interpreter keeps no in-flight count and the JS target has no
   sockets. *)
let handle_unwind_src = {|mod HandleUnwind do
  needs IO.Console
  needs IO.NetListen
  fn strand(l : Listener) : Bool do
    let _ = handle_enter(l, 5)
    panic("boom")
  end
  fn again(port : Int) : String do
    match Socket.listen(port) do
    Ok(Ok(l2)) ->
      let _ = Socket.close_listener(l2)
      "released"
    _ -> "still bound"
    end
  end
  fn main() needs IO.Console, IO.NetListen do
    match Socket.listen(0) do
    Ok(Ok(l)) ->
      let port = match Socket.local_port(l) do
        Ok(p) -> p
        Err(_) -> 0
      end
      let _ = __try_call(fn _ -> strand(l))
      let _ = try_finally(fn _ -> __try_call(fn _ -> strand(l)), fn _ -> ())
      let _ = Socket.close_listener(l)
      println("after a caught panic inside a use: " ++ again(port))
    _ -> println("listen failed")
    end
  end
end
|}

let test_handle_unwind () =
  check_all ~skip:[ "js"; "interp" ] ~name:"handle_unwind" ~src:handle_unwind_src
    [ ("", "after a caught panic inside a use: released\n") ]

let tests =
  [ ( "cap_runtime_slot",
      [ Alcotest.test_case "save/push/enter/restore around cap_check_raw" `Quick test_slot;
        Alcotest.test_case "cap_grant_text reads MARCH_GRANT, trimmed" `Quick test_grant_text;
        Alcotest.test_case "push/restore leaves nothing live" `Quick test_no_leak;
        Alcotest.test_case "compiled code dropping the last CapAuthRef releases it" `Quick
          test_compiled_drop;
        Alcotest.test_case "a caught panic keeps the authority it restores alive" `Quick
          test_unwind_keeps_mark;
        Alcotest.test_case "a caught panic releases what the abandoned frames saved" `Quick
          test_unwind_exact;
        Alcotest.test_case "a caught panic leaves the handle uses it abandoned" `Quick
          test_handle_unwind;
        Alcotest.test_case "cap_enter of the authority in force changes nothing" `Quick
          test_enter_same;
        Alcotest.test_case "the Task 10b fast paths leave nothing live" `Quick
          test_fast_paths_no_leak;
        Alcotest.test_case "10,000 spawn/exit cycles under a frame release every authority"
          `Quick test_spawn_cycles_no_leak ] ) ]
