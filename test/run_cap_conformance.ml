(** Run-time authority conformance: every runtime refuses the same way.

    Every [test/cap_conformance/<name>.march] is a program that may open with
    header lines, each on its own line at the top:
    - [-- GRANT: <scopes>]: exported as [MARCH_GRANT] (the launch grant).
      [-- GRANT:] with nothing after it exports the empty string, which every
      runtime reads as unset. Without the header [MARCH_GRANT] is unset.
    - [-- EXIT-ONLY]: compare only the exit status and the first line of
      stderr (a launch error), and require stdout to be empty.
    A fixture without headers runs under its own request (`main`'s needs ∪
    its Cap params, else the module's needs line). The program is run

    - interpreted: [march <file>];
    - through the ORC JIT: [march --jit <file>];
    - compiled: [march --compile --opt 0], then the binary;
    - as JavaScript: [march --target js --opt 0], then [node] on the output,
      unless the fixture is in [js_unsupported] or [node] is not on PATH;
    - in the REPL: [march repl --grant G <file>], which loads the file's
      declarations except `main`, with the lines of `main`'s body typed at
      the prompt,
      unless the fixture is in [repl_unsupported]. The REPL has no `main`, and
      its own request is the full authority (design §21), so it is launched
      with the authority the program's launch holds: G is the header's grant,
      else `main`'s request when that carries a scope (the launch layer is
      then the same), else none. Its prompts and echoes (`val x = ...`,
      `= v`, `loaded <file>`) are not program output and are dropped.
      The REPL reports a failed prompt line on stderr and still exits 0, so
      a REPL run also fails when its stderr reports an error (unless the
      fixture is [-- EXIT-ONLY]).

    Each run's stdout plus [exit <code>] (with [-- EXIT-ONLY]: stderr's first
    line plus [exit <code>]) must equal [<name>.expected] byte for byte. This
    is the conformance suite of specs/2026-11-10-object-capability-design.md
    §15 and §18 ("every enforcement test on every backend").

    Regenerate after an intentional change (from the interpreted run; every
    other runtime must still match):
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
let js_unsupported : (string * string) list = [
  (* With the console refused the verdict can only be the exit code, and the
     JS target has neither `process_exit` nor stdin (`io_read_line`,
     `io_read_byte`): pre-existing gaps. Authority.check itself is covered
     on JS by the refuse_* fixtures. *)
  ("console_read_byte", "verdict needs `process_exit`, and `io_read_byte`; the JS target has neither");
  ("console_refused", "verdict needs `process_exit`, and `io_read_line`; the JS target has neither");
  ("process_allowed", "the JS target has no `process_set_env` or `process_spawn_sync`");
  ("process_refused", "the JS target has no `process_exit`");
  ("spawn_mut_signal_refused", "the JS target has no `signal_watch` or `pmap_threshold`");
  ("file_refused", "the JS target has no `dir_list` or `dir_mkdir_p`");
  ("file_allowed", "the JS target has no `file_exists`");
  ("tls_https_get_refused", "the JS target has no TLS (`tls_client_ctx`)");
  ("listen_refused", "the JS target has no HTTP server (`http_server_listen`) or UDP (`udp_resolve`)");
  ("resolve_port_scoped", "the JS target has no UDP (`udp_resolve`)");
  ("capture_stored_in_record_list_vault", "the JS target has no tables (`vault_new`, `vault_get`)");
  ("spawn_mut_allowed", "the JS target has no tasks");
  ("actor_under_frame_restricted", "the JS target has no tasks");
  ("actor_restart_keeps_authority", "the JS target has no tasks");
  ("task_inherits_capture", "the JS target has no tasks");
  ("restrict_named_fn_value_inside", "the JS target has no `file_read`");
  ("restrict_actor_restricted_for_life", "the JS target has no tasks");
  ("restrict_task_inherits", "the JS target has no tasks");
]

(* Fixtures the REPL mode does not run, each with the reason. *)
let repl_unsupported : (string * string) list = [
  ("actor_under_frame_restricted", "actors: the REPL mode runs the fixtures that use no actors");
  ("actor_restart_keeps_authority", "actors: the REPL mode runs the fixtures that use no actors");
  ("restrict_actor_restricted_for_life", "actors: the REPL mode runs the fixtures that use no actors");
  ("grant_wider_launch_error",
   "the REPL requests the full authority (design §21), so no grant is wider than its request");
]

let have_node = lazy (Sys.command "command -v node >/dev/null 2>&1" = 0)

(* The fixture's leading header lines, as (KEY, value) with the value
   trimmed ("" for a header with no `:`, such as [-- EXIT-ONLY]). A header
   is [-- KEY] or [-- KEY: value] with KEY made of A-Z and `-`. *)
let headers (src : string) : (string * string) list =
  let is_key k = k <> "" && String.for_all (fun c -> (c >= 'A' && c <= 'Z') || c = '-') k in
  let rec scan acc = function
    | line :: rest when String.starts_with ~prefix:"-- " line ->
      let body = String.sub line 3 (String.length line - 3) in
      let key, value =
        match String.index_opt body ':' with
        | Some i -> (String.sub body 0 i,
                     String.trim (String.sub body (i + 1) (String.length body - i - 1)))
        | None -> (String.trim body, "") in
      if is_key key then scan ((key, value) :: acc) rest else List.rev acc
    | _ -> List.rev acc
  in
  scan [] (String.split_on_char '\n' src)

(* The lines of `main`'s body: from the line after `  fn main(` up to the
   first line that is exactly `  end`. *)
let main_body (src : string) : string list =
  let rec skip = function
    | l :: rest -> if String.starts_with ~prefix:"  fn main(" l then take [] rest else skip rest
    | [] -> failwith "fixture has no `  fn main(` line"
  and take acc = function
    | "  end" :: _ -> List.rev acc
    | l :: rest -> take (l :: acc) rest
    | [] -> failwith "fixture's `main` has no closing `  end` line"
  in
  skip (String.split_on_char '\n' src)

(* The fixture without its `main` (the `  fn main(` line through the first
   `  end` line), blank lines in its place so spans keep their lines: the file
   the REPL mode preloads.  `main` is never called there (its body is typed
   at the prompt), and the REPL typechecks a preloaded declaration on its
   own, which can report errors (e.g. no `Eq` for a `Result` compared with
   `==`) that the prompt lines, typed one at a time, do not. *)
let without_main (src : string) : string =
  let rec go acc in_main = function
    | [] -> List.rev acc
    | l :: rest when not in_main && String.starts_with ~prefix:"  fn main(" l -> go ("" :: acc) true rest
    | "  end" :: rest when in_main -> go ("" :: acc) false rest
    | _ :: rest when in_main -> go ("" :: acc) true rest
    | l :: rest -> go (l :: acc) false rest
  in
  String.concat "\n" (go [] false (String.split_on_char '\n' src))

(* The grant the REPL mode launches with (see the header comment). *)
let repl_grant (src : string) (grant : string option) : string option =
  match grant with
  | Some g when g <> "" -> Some g
  | _ ->
    let m = March_parser.Parse.module_of_lexbuf (Lexing.from_string src) in
    (match March_ast.Cap_request.launch_request m with
     | text, true -> Some text
     | _, false -> None)

let modes = [ "interp"; "jit"; "compiled"; "js"; "repl" ]

let script ~dir ~name ~grant ~repl_grant =
  let exe = Filename.quote (Test_helpers.find_main_exe ()) in
  let home = Filename.quote (Lazy.force private_home) in
  let f = Filename.quote (name ^ ".march") in
  let js_ok =
    Lazy.force have_node && not (List.mem_assoc name js_unsupported) in
  let repl_ok = not (List.mem_assoc name repl_unsupported) in
  let grant_env = match grant with
    | None -> "unset MARCH_GRANT;"
    | Some g -> Printf.sprintf "export MARCH_GRANT=%s;" (Filename.quote g) in
  let repl_grant_arg = match repl_grant with
    | None -> ""
    | Some g -> "--grant " ^ Filename.quote g in
  Printf.sprintf
    "cd %s && export HOME=%s; %s \
     %s %s > interp.out 2>interp.err; echo $? > interp.code; \
     %s --jit %s > jit.out 2>jit.err; echo $? > jit.code; \
     %s --compile --opt 0 %s -o ./prog > build.out 2>&1; \
     if [ -x ./prog ]; then ./prog > compiled.out 2>compiled.err; echo $? > compiled.code; \
     else cp build.out compiled.err; echo > compiled.out; echo -1 > compiled.code; fi; \
     echo > js.out; echo > js.err; echo -2 > js.code; \
     if %b; then \
       %s --target js --opt 0 %s -o ./prog.mjs > js.build 2>&1; \
       if [ -f ./prog.mjs ]; then node ./prog.mjs > js.out 2>js.err; echo $? > js.code; \
       else cp js.build js.err; echo -1 > js.code; fi; \
     fi; \
     echo > repl.out; echo > repl.err; echo -2 > repl.code; \
     if %b; then \
       (unset MARCH_GRANT; MARCH_REPL_INTERP=1 %s repl %s repl/%s < repl.in > repl.out 2>repl.err; \
        echo $? > repl.code); \
     fi; true"
    (Filename.quote dir) home grant_env
    exe f exe f exe f js_ok exe f
    repl_ok exe repl_grant_arg f

type run = { out : string; err : string; code : int }

(* The REPL's stdout without its prompts (`march(N)> `, and the blank
   continuation prompt of the same width after it) and echoes. *)
let repl_program_output (raw : string) : string =
  let b = Buffer.create (String.length raw) in
  let n = String.length raw in
  let rec prompt_at i =
    (* Some (length of the prompt) when [raw] has `march(<digits>)> ` at [i]. *)
    if i + 6 <= n && String.sub raw i 6 = "march(" then begin
      let j = ref (i + 6) in
      while !j < n && raw.[!j] >= '0' && raw.[!j] <= '9' do incr j done;
      if !j > i + 6 && !j + 3 <= n && String.sub raw !j 3 = ")> " then Some (!j + 3 - i)
      else None
    end else None
  and go i =
    if i < n then
      match prompt_at i with
      | Some len ->
        let k = ref (i + len) in
        let blank = String.make len ' ' in
        while !k + len <= n && String.sub raw !k len = blank do k := !k + len done;
        go !k
      | None -> Buffer.add_char b raw.[i]; go (i + 1)
  in
  go 0;
  let echo l =
    String.starts_with ~prefix:"March REPL" l || String.starts_with ~prefix:"loaded " l
    || String.starts_with ~prefix:"val " l || String.starts_with ~prefix:"= " l in
  String.split_on_char '\n' (Buffer.contents b)
  |> List.filter (fun l -> l <> "" && not (echo l))
  |> List.map (fun l -> l ^ "\n")
  |> String.concat ""

(* A line of REPL stderr that reports a failed prompt line: an evaluation
   error, a JIT error, or the header of a rendered diagnostic
   (`-- NAMING ------`, `-- TYPE MISMATCH ---`). *)
let repl_error_line (l : string) : bool =
  let starts p = String.starts_with ~prefix:p l in
  starts "runtime error:" || starts "match failure:" || starts "error:"
  || starts "jit error:" || starts "internal error"
  || (starts "-- " && String.length l > 4
      && String.for_all (fun c -> (c >= 'A' && c <= 'Z') || c = ' ' || c = '-')
           (String.sub l 3 (String.length l - 3)))

let not_timing l = not (String.starts_with ~prefix:"[timing]" l)

let run_all (names : string list) : (string, (string * run) list) Hashtbl.t =
  (* One REPL first, so the fixtures' REPLs share its cached stdlib
     environment instead of all building it at once. *)
  ignore (Sys.command (Printf.sprintf
    "HOME=%s MARCH_REPL_INTERP=1 %s repl < /dev/null > /dev/null 2>&1"
    (Filename.quote (Lazy.force private_home))
    (Filename.quote (Test_helpers.find_main_exe ()))));
  let results = Hashtbl.create 8 in
  let running = Hashtbl.create 8 in
  (* At most [Test_helpers.test_jobs ()] fixtures at once. Each fixture runs
     five runtimes, one of them a clang compile; starting all 37 together
     starved CI's 4-core `compiler` runner (also running run_compiler) until
     GitHub lost contact with it. *)
  let jobs = Test_helpers.test_jobs () in
  let start name =
    let tmp = Filename.temp_dir "march-cap-conformance" "" in
    let src = read_file (Filename.concat (fixtures_dir ()) (name ^ ".march")) in
    write_file (Filename.concat tmp (name ^ ".march")) src;
    let hs = headers src in
    let grant = List.assoc_opt "GRANT" hs in
    let repl_grant =
      if List.mem_assoc name repl_unsupported then None else repl_grant src grant in
    if not (List.mem_assoc name repl_unsupported) then
      (write_file (Filename.concat tmp "repl.in")
         (String.concat "" (List.map (fun l -> l ^ "\n") (main_body src)));
       Unix.mkdir (Filename.concat tmp "repl") 0o755;
       write_file (Filename.concat tmp (Filename.concat "repl" (name ^ ".march")))
         (without_main src));
    let pid =
      Unix.create_process "/bin/sh"
        [| "/bin/sh"; "-c"; script ~dir:tmp ~name ~grant ~repl_grant |]
        Unix.stdin Unix.stdout Unix.stderr in
    Hashtbl.replace running pid (name, tmp)
  in
  let reap () =
    let (pid, _) = Unix.wait () in
    match Hashtbl.find_opt running pid with
    | None -> ()
    | Some (name, tmp) ->
      Hashtbl.remove running pid;
      let f x = read_file (Filename.concat tmp x) in
      Hashtbl.replace results name
        (List.map (fun m ->
             let out = f (m ^ ".out") and err = f (m ^ ".err") in
             let out, err =
               if m = "repl" then
                 (repl_program_output out,
                  String.concat "\n" (List.filter not_timing (String.split_on_char '\n' err)))
               else (out, err) in
             (m, { out; err; code = int_of_string (String.trim (f (m ^ ".code"))) }))
            modes);
      (try rm_rf tmp with _ -> ())
  in
  List.iter (fun name ->
      while Hashtbl.length running >= jobs do reap () done;
      start name)
    names;
  while Hashtbl.length running > 0 do reap () done;
  results

let fixtures () =
  Sys.readdir (fixtures_dir ())
  |> Array.to_list
  |> List.filter (fun f -> Filename.check_suffix f ".march")
  |> List.map Filename.remove_extension
  |> List.sort compare

let results = lazy (run_all (fixtures ()))

let first_line s =
  match String.index_opt s '\n' with Some i -> String.sub s 0 i | None -> s

let rendered ~exit_only r =
  (if exit_only then first_line r.err ^ "\n" else r.out)
  ^ Printf.sprintf "exit %d\n" r.code

let case name =
  let expected_path = Filename.concat (fixtures_dir ()) (name ^ ".expected") in
  let exit_only =
    List.mem_assoc "EXIT-ONLY"
      (headers (read_file (Filename.concat (fixtures_dir ()) (name ^ ".march")))) in
  List.map (fun m ->
      Alcotest.test_case (name ^ " " ^ m) `Quick (fun () ->
          let r = List.assoc m (Hashtbl.find (Lazy.force results) name) in
          if m = "js" && r.code = -2 then
            print_endline "  SKIP: node not on PATH or fixture js_unsupported"
          else if m = "repl" && r.code = -2 then
            print_endline "  SKIP: fixture repl_unsupported"
          else begin
            let got = rendered ~exit_only r in
            if update_mode && m = "interp" then write_file expected_path got;
            let expected =
              if Sys.file_exists expected_path then read_file expected_path else "" in
            if got <> expected then
              Alcotest.failf "%s (%s): expected\n%s\ngot\n%s\nstderr:\n%s"
                name m expected got r.err;
            (* A launch error stops the program before any of its code runs,
               module-level `let`s included, so an [-- EXIT-ONLY] run
               prints nothing on stdout. *)
            if exit_only && r.out <> "" then
              Alcotest.failf "%s (%s): a launch error, but the program printed:\n%s"
                name m r.out;
            (* The REPL reports a failed prompt line on stderr and goes on
               to exit 0 at end of input, so where the expected stdout is
               empty (or a line was silently dropped) stdout alone would
               pass whatever happened.  A REPL run passes only if its stderr
               holds no error.  [-- EXIT-ONLY] fixtures read stderr. *)
            if m = "repl" && not exit_only then
              match List.find_opt repl_error_line (String.split_on_char '\n' r.err) with
              | Some l ->
                Alcotest.failf "%s (repl): the REPL reported an error: %s\nstderr:\n%s"
                  name l r.err
              | None -> ()
          end))
    modes

let () =
  Alcotest.run "cap_conformance"
    [ ("cap_conformance", List.concat_map case (fixtures ())) ]
