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

let tests =
  [ ( "cap_runtime_slot",
      [ Alcotest.test_case "save/push/enter/restore around cap_check_raw" `Quick test_slot;
        Alcotest.test_case "cap_grant_text reads MARCH_GRANT, trimmed" `Quick test_grant_text;
        Alcotest.test_case "push/restore leaves nothing live" `Quick test_no_leak ] ) ]
