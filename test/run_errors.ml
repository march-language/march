(** Golden rendered-diagnostic corpus (diagnostics plan §11, D7).

    Every [test/errors/<slug>_<n>.march] is checked with the real compiler
    ([march --check] and [march --check-json]) and its output compared byte for
    byte against two files beside it:

    - [<name>.expected]: the exit code, the full rendered diagnostics on stderr
      (carets, labels, notes, the [[slug]] suffix, the [march --explain]
      pointer) and every machine fix rendered as a before/after diff of the
      lines it touches;
    - [<name>.json.expected]: the [--check-json] lines, so the machine form
      cannot drift from the human one.

    Nothing else in the tree pins a whole message: the [EXPECT-ERROR] corpora
    and the alcotest assertions pin fragments, so a caret that moves, a label
    that disappears or a fix that changes passes them all. The [.expected] diff
    is the review artifact for any message change.

    A source carrying [-- EXPECT-ERROR: <fragment>] (the programs seeded from
    [specs/lang/*/reject/]) must also contain that fragment in its rendered
    output, so the twin can never silently stop exercising the error it was
    copied for.

    Regenerate after an intentional change:
      [UPDATE_ERRORS=1 ./_build/default/test/run_errors.exe -e]
    then review [git diff test/errors/].

    Each program is checked in a fresh temp directory as [errors/<file>], with
    a private [HOME], so the rendered header carries the same path wherever the
    suite runs and no cache from another worktree can leak in. One compiler
    process per program, so the once-per-run explain pointer is
    deterministic. [MARCH_JOBS] caps the parallel compiler runs (default 8). *)

let update_mode = Sys.getenv_opt "UPDATE_ERRORS" = Some "1"

let project_root () =
  if Sys.file_exists "test/errors" && Sys.is_directory "test/errors" then "."
  else Test_helpers.march_project_root ()

let errors_dir () = Filename.concat (project_root ()) "test/errors"

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

(* One private HOME for the whole run: the stdlib typecheck cache it fills is
   keyed on the compiler and stdlib, so it is shared safely between programs
   and saves re-checking the stdlib per file. *)
let private_home =
  lazy begin
    let d = Filename.temp_dir "march-errors-home" "" in
    Unix.mkdir (Filename.concat d ".cache") 0o755;
    at_exit (fun () -> try rm_rf d with _ -> ());
    d
  end

(* ── Running the compiler, in parallel ─────────────────────────────────

   Each program needs two compiler runs (~0.5 s each); a few hundred programs
   run one at a time would make this the slowest suite in the tree. So every
   program's runs are started up front, [jobs] at a time, as [sh -c] children
   writing into the program's own temp dir; the alcotest cases then only read
   and compare. *)

let jobs =
  match Option.bind (Sys.getenv_opt "MARCH_JOBS") int_of_string_opt with
  | Some n when n > 0 -> n
  | _ -> 8

type result = { code : int; err : string; json : string }

let script ~dir ~rel =
  let exe = Filename.quote (Test_helpers.find_main_exe ()) in
  let home = Filename.quote (Lazy.force private_home) in
  Printf.sprintf
    "cd %s && HOME=%s %s --check %s > check.out 2> check.err; echo $? > check.code; \
     HOME=%s %s --check-json %s > json.out 2> /dev/null; true"
    (Filename.quote dir) home exe (Filename.quote rel) home exe (Filename.quote rel)

let run_all (names : string list) : (string, result) Hashtbl.t =
  let results = Hashtbl.create 64 in
  let pending = Queue.create () in
  List.iter (fun n -> Queue.add n pending) names;
  let running = Hashtbl.create 16 in
  let start name =
    let src = read_file (Filename.concat (errors_dir ()) (name ^ ".march")) in
    let tmp = Filename.temp_dir "march-errors" "" in
    let edir = Filename.concat tmp "errors" in
    Unix.mkdir edir 0o755;
    write_file (Filename.concat edir (name ^ ".march")) src;
    let rel = "errors/" ^ name ^ ".march" in
    let pid =
      Unix.create_process "/bin/sh" [| "/bin/sh"; "-c"; script ~dir:tmp ~rel |]
        Unix.stdin Unix.stdout Unix.stderr in
    Hashtbl.replace running pid (name, tmp)
  in
  let finish pid =
    let (name, tmp) = Hashtbl.find running pid in
    Hashtbl.remove running pid;
    let f x = Filename.concat tmp x in
    let code = int_of_string (String.trim (read_file (f "check.code"))) in
    Hashtbl.replace results name
      { code; err = read_file (f "check.err"); json = read_file (f "json.out") };
    (try rm_rf tmp with _ -> ())
  in
  while not (Queue.is_empty pending) || Hashtbl.length running > 0 do
    while not (Queue.is_empty pending) && Hashtbl.length running < jobs do
      start (Queue.pop pending)
    done;
    let (pid, _) = Unix.wait () in
    if Hashtbl.mem running pid then finish pid
  done;
  results

(* ── Fixes as diffs ────────────────────────────────────────────────────── *)

let lines_of s = String.split_on_char '\n' s

let render_fix ~src (j : Yojson.Safe.t) : string option =
  let open Yojson.Safe.Util in
  match member "fix" j with
  | `Null -> None
  | fix ->
    let lines = Array.of_list (lines_of src) in
    let line n = if n >= 1 && n <= Array.length lines then lines.(n - 1) else "" in
    let buf = Buffer.create 128 in
    let code = member "code" j |> to_string in
    Printf.bprintf buf "fix [%s]:\n" code;
    (match member "kind" fix |> to_string with
     | "insert" ->
       let after = member "after_line" fix |> to_int in
       let text = member "text" fix |> to_string in
       Printf.bprintf buf "@@ after line %d @@\n %s\n" after (line after);
       List.iter (fun l -> Printf.bprintf buf "+%s\n" l) (lines_of text)
     | "delete" ->
       let s = member "start_line" fix |> to_int
       and e = member "end_line" fix |> to_int in
       Printf.bprintf buf "@@ lines %d-%d @@\n" s e;
       for n = s to e do Printf.bprintf buf "-%s\n" (line n) done
     | "replace" ->
       let sl = member "start_line" fix |> to_int
       and sc = member "start_col" fix |> to_int
       and el = member "end_line" fix |> to_int
       and ec = member "end_col" fix |> to_int
       and text = member "text" fix |> to_string in
       let first = line sl and last = line el in
       let clip s n = String.sub s 0 (max 0 (min n (String.length s))) in
       let from s n =
         let n = max 0 (min n (String.length s)) in
         String.sub s n (String.length s - n) in
       let after = clip first sc ^ text ^ from last ec in
       Printf.bprintf buf "@@ lines %d-%d @@\n" sl el;
       for n = sl to el do Printf.bprintf buf "-%s\n" (line n) done;
       List.iter (fun l -> Printf.bprintf buf "+%s\n" l) (lines_of after)
     | k -> Printf.bprintf buf "(unknown fix kind %s)\n" k);
    Some (Buffer.contents buf)

(* ── One corpus program ────────────────────────────────────────────────── *)

let expect_error_fragments src =
  let marker = "-- EXPECT-ERROR:" in
  List.filter_map (fun l ->
      let l = String.trim l in
      let n = String.length marker in
      if String.length l >= n && String.sub l 0 n = marker then
        Some (String.trim (String.sub l n (String.length l - n)))
      else None)
    (lines_of src)

let contains hay needle =
  let hl = String.length hay and nl = String.length needle in
  let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
  nl = 0 || go 0

let render results name =
  let src = read_file (Filename.concat (errors_dir ()) (name ^ ".march")) in
  let r = Hashtbl.find results name in
  let fixes =
    lines_of r.json
    |> List.filter (fun l -> String.trim l <> "")
    |> List.filter_map (fun l ->
        match Yojson.Safe.from_string l with
        | j -> render_fix ~src j
        | exception _ -> None)
  in
  let human =
    Printf.sprintf "exit: %d\n%s%s" r.code r.err
      (if fixes = [] then "" else "\n" ^ String.concat "\n" fixes)
  in
  (src, human, r.json)

let check results name () =
  let (src, human, json) = render (Lazy.force results) name in
  let base = Filename.concat (errors_dir ()) name in
  let exp_h = base ^ ".expected" and exp_j = base ^ ".json.expected" in
  List.iter (fun frag ->
      if not (contains human frag) then
        Alcotest.failf "%s: the rendered output no longer contains its \
                        EXPECT-ERROR fragment %S" name frag)
    (expect_error_fragments src);
  if update_mode then begin
    write_file exp_h human; write_file exp_j json
  end else begin
    let cmp what file actual =
      if not (Sys.file_exists file) then
        Alcotest.failf "%s: %s missing (run with UPDATE_ERRORS=1)" name file
      else
        let expected = read_file file in
        if expected <> actual then
          Alcotest.failf
            "%s: %s differs.\n--- expected (%s)\n%s\n--- actual\n%s\n\
             (regenerate with UPDATE_ERRORS=1 if intended, then review \
             `git diff test/errors/`)"
            name what file expected actual
    in
    cmp "rendered diagnostics" exp_h human;
    cmp "--check-json" exp_j json
  end

let corpus () =
  Sys.readdir (errors_dir ())
  |> Array.to_list
  |> List.filter (fun f -> Filename.check_suffix f ".march")
  |> List.map Filename.remove_extension
  |> List.sort compare

let () =
  let names = corpus () in
  let results = lazy (run_all names) in
  let cases =
    List.map (fun n -> Alcotest.test_case n `Quick (check results n)) names
  in
  Alcotest.run "errors" [ ("golden diagnostics", cases) ]
