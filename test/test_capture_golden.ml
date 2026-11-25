(* ocap phase 8a, Task 6 (specs/plans/2026-11-24-ocap-p8a-capture-sets-plan.md):
   the golden `march --dump-captures` corpus.

   Every test/captures/<name>.march is reported and compared with
   <name>.expected.  After an intentional change:
     UPDATE_CAPTURES=1 ./_build/default/test/run_captures.exe -e
   then review `git diff test/captures/`.  CAPTURES_ONLY=a,b limits a run to
   the cases whose name starts with one of the prefixes. *)

let source_dir () : string =
  (* The source tree, so UPDATE_CAPTURES writes where git sees it. *)
  let rec up d n =
    if n = 0 then None
    else if Sys.file_exists (Filename.concat d "test/captures") && Sys.file_exists (Filename.concat d "dune-project")
            && not (Filename.basename (Filename.dirname d) = "_build")
    then Some (Filename.concat d "test/captures")
    else up (Filename.dirname d) (n - 1)
  in
  match up (Sys.getcwd ()) 8 with Some d -> d | None -> Test_capture_oracle.find_dir "captures"

let report (dir : string) (name : string) : string =
  let work = Lazy.force Test_captures.work_dir in
  let scratch = Filename.concat work "golden" in
  if not (Sys.file_exists scratch) then Sys.mkdir scratch 0o755;
  let file = name ^ ".march" in
  Out_channel.with_open_bin (Filename.concat scratch file) (fun oc ->
      output_string oc (Test_capture_oracle.read_file (Filename.concat dir file)));
  let out = Filename.concat scratch (name ^ ".out") in
  let rc =
    Sys.command
      (Printf.sprintf "cd %s && HOME=%s %s --dump-captures %s > %s 2>&1" (Filename.quote scratch)
         (Filename.quote (Filename.concat work "home")) (Filename.quote Test_captures.compiler_exe)
         (Filename.quote file) (Filename.quote out))
  in
  let text = Test_capture_oracle.read_file out in
  if rc <> 0 then Alcotest.failf "%s was rejected (exit %d):\n%s" file rc text;
  text

let test_case (dir : string) (name : string) () =
  let got = report dir name in
  let expected_path = Filename.concat dir (name ^ ".expected") in
  if Sys.getenv_opt "UPDATE_CAPTURES" <> None then
    Out_channel.with_open_bin (Filename.concat (source_dir ()) (name ^ ".expected")) (fun oc -> output_string oc got)
  else if not (Sys.file_exists expected_path) then
    Alcotest.failf "%s.expected is missing; run with UPDATE_CAPTURES=1 and review it" name
  else Alcotest.(check string) name (Test_capture_oracle.read_file expected_path) got

let tests =
  let dir = Test_capture_oracle.find_dir "captures" in
  let only =
    match Sys.getenv_opt "CAPTURES_ONLY" with
    | Some s when s <> "" -> Some (String.split_on_char ',' s)
    | _ -> None
  in
  let names =
    List.filter
      (fun n -> match only with None -> true | Some ps -> List.exists (fun p -> String.starts_with ~prefix:p n) ps)
      (List.map Filename.remove_extension (Test_capture_oracle.march_files dir))
  in
  [ ("capture_golden", List.map (fun n -> Alcotest.test_case n `Quick (test_case dir n)) names) ]
