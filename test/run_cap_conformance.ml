(** Capability refusal conformance: every backend refuses the same way.

    Every [test/cap_conformance/<name>.march] is a program whose first line is
    [-- REFUSE: <kinds>]; the text after the colon is passed as
    [MARCH_TEST_REFUSE] (the ocap phase 1 test hook: a comma-separated list of
    capability kinds the launch refuses, matched exactly). The program is run

    - interpreted: [march <file>];
    - through the ORC JIT: [march --jit <file>];
    - compiled: [march --compile --opt 0], then the binary;
    - as JavaScript: [march --target js --opt 0], then [node] on the output,
      unless the fixture is in [js_unsupported] or [node] is not on PATH;

    and each run's stdout plus [exit <code>] must equal [<name>.expected] byte
    for byte. This is the seed of the conformance suite of
    specs/2026-11-10-object-capability-design.md §15; phase 4 extends it with
    run-time authority, it does not start another.

    Regenerate after an intentional change (from the interpreted run; every
    other backend must still match):
      [UPDATE_CAP_CONFORMANCE=1 ./_build/default/test/run_cap_conformance.exe -e]
    then review [git diff test/cap_conformance/]. *)

let update_mode = Sys.getenv_opt "UPDATE_CAP_CONFORMANCE" = Some "1"

let project_root () =
  if Sys.file_exists "test/cap_conformance" then "."
  else Test_helpers.march_project_root ()

let fixtures_dir () = Filename.concat (project_root ()) "test/cap_conformance"

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let write_file path s =
  let oc = open_out_bin path in
  output_string oc s;
  close_out oc

let rec rm_rf p =
  if Sys.file_exists p then
    if Sys.is_directory p then begin
      Array.iter (fun f -> rm_rf (Filename.concat p f)) (Sys.readdir p);
      Sys.rmdir p
    end else Sys.remove p

let private_home =
  lazy begin
    let d = Filename.temp_dir "march-cap-conformance-home" "" in
    Unix.mkdir (Filename.concat d ".cache") 0o755;
    at_exit (fun () -> try rm_rf d with _ -> ());
    d
  end

(* Fixtures the JS target cannot run yet, each with the gap that stops it. *)
let js_unsupported : (string * string) list = []

let have_node = lazy (Sys.command "command -v node >/dev/null 2>&1" = 0)

(* The [-- REFUSE:] header's value, trimmed. *)
let refuse_of (src : string) : string =
  let first = match String.index_opt src '\n' with
    | Some i -> String.sub src 0 i | None -> src in
  let prefix = "-- REFUSE:" in
  if String.starts_with ~prefix first then
    String.trim (String.sub first (String.length prefix)
                   (String.length first - String.length prefix))
  else failwith "fixture must start with a `-- REFUSE:` line"

let backends = [ "interp"; "jit"; "compiled"; "js" ]

let script ~dir ~name ~refuse =
  let exe = Filename.quote (Test_helpers.find_main_exe ()) in
  let home = Filename.quote (Lazy.force private_home) in
  let f = Filename.quote (name ^ ".march") in
  let js_ok =
    Lazy.force have_node && not (List.mem_assoc name js_unsupported) in
  Printf.sprintf
    "cd %s && export HOME=%s MARCH_TEST_REFUSE=%s; \
     %s %s > interp.out 2>interp.err; echo $? > interp.code; \
     %s --jit %s > jit.out 2>jit.err; echo $? > jit.code; \
     %s --compile --opt 0 %s -o ./prog > build.out 2>&1; \
     if [ -x ./prog ]; then ./prog > compiled.out 2>compiled.err; echo $? > compiled.code; \
     else cp build.out compiled.err; echo > compiled.out; echo -1 > compiled.code; fi; \
     echo > js.out; echo > js.err; echo -2 > js.code; \
     if %b; then \
       %s --target js --opt 0 %s -o ./prog.mjs > js.err 2>&1; \
       if [ -f ./prog.mjs ]; then node ./prog.mjs > js.out 2>>js.err; echo $? > js.code; \
       else echo -1 > js.code; fi; \
     fi; true"
    (Filename.quote dir) home (Filename.quote refuse)
    exe f exe f exe f js_ok exe f

type run = { out : string; err : string; code : int }

let run_all (names : string list) : (string, (string * run) list) Hashtbl.t =
  let results = Hashtbl.create 8 in
  let running = Hashtbl.create 8 in
  List.iter (fun name ->
      let tmp = Filename.temp_dir "march-cap-conformance" "" in
      let src = read_file (Filename.concat (fixtures_dir ()) (name ^ ".march")) in
      write_file (Filename.concat tmp (name ^ ".march")) src;
      let refuse = refuse_of src in
      let pid =
        Unix.create_process "/bin/sh"
          [| "/bin/sh"; "-c"; script ~dir:tmp ~name ~refuse |]
          Unix.stdin Unix.stdout Unix.stderr in
      Hashtbl.replace running pid (name, tmp))
    names;
  while Hashtbl.length running > 0 do
    let (pid, _) = Unix.wait () in
    match Hashtbl.find_opt running pid with
    | None -> ()
    | Some (name, tmp) ->
      Hashtbl.remove running pid;
      let f x = read_file (Filename.concat tmp x) in
      Hashtbl.replace results name
        (List.map (fun b ->
             (b, { out = f (b ^ ".out"); err = f (b ^ ".err");
                   code = int_of_string (String.trim (f (b ^ ".code"))) }))
            backends);
      (try rm_rf tmp with _ -> ())
  done;
  results

let fixtures () =
  Sys.readdir (fixtures_dir ())
  |> Array.to_list
  |> List.filter (fun f -> Filename.check_suffix f ".march")
  |> List.map Filename.remove_extension
  |> List.sort compare

let results = lazy (run_all (fixtures ()))

let rendered r = r.out ^ Printf.sprintf "exit %d\n" r.code

let case name =
  let expected_path = Filename.concat (fixtures_dir ()) (name ^ ".expected") in
  List.map (fun b ->
      Alcotest.test_case (name ^ " " ^ b) `Quick (fun () ->
          let r = List.assoc b (Hashtbl.find (Lazy.force results) name) in
          if b = "js" && r.code = -2 then
            print_endline "  SKIP: node not on PATH or fixture js_unsupported"
          else begin
            let got = rendered r in
            if update_mode && b = "interp" then write_file expected_path got;
            let expected =
              if Sys.file_exists expected_path then read_file expected_path else "" in
            if got <> expected then
              Alcotest.failf "%s (%s): expected\n%s\ngot\n%s\nstderr:\n%s"
                name b expected got r.err
          end))
    backends

let () =
  Alcotest.run "cap_conformance"
    [ ("cap_conformance", List.concat_map case (fixtures ())) ]
