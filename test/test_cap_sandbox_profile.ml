(* The two SBPL builders must not drift.

   `--cap-sandbox` (bin/main.ml, [cap_sandbox_define]) and `forge cap run`
   (forge/lib/cap_sandbox.ml, [profile_for]) construct the same deny-default
   Seatbelt profile INDEPENDENTLY — one as a -D define compiled into the
   binary, one as a file handed to sandbox-exec.  Both are short and commented
   as mirrors, and bin/main.ml's comment claimed "the two are kept in step by
   test/test_cap_sandbox_profile.ml" — a file that DID NOT EXIST until
   2026-08-08.  This makes the comment true.

   Tracked in specs/todos/2026-08-03-cap-sandbox-remaining.md, in the same
   spirit as [test_cap_attrib_agreement]: two tables/emitters that must agree,
   and the only mechanical check is a test that asks both the same question.

   The comparison is on NORMALIZED CLAUSE SETS, not raw text: forge writes
   one clause per line while the embedded define is a single unbroken string,
   and each side has one legitimate extra —

   - forge adds [(allow file-read* (literal <binary>))], the explicit
     launch-target read (redundant with the baseline's [file-read*], stated
     so a future read-tightening cannot silently make the target unmappable);
     the embedded profile has no path to name, the binary IS the profile.
   - the embedded side may add scoped [(allow file-write* (subpath …))]
     grants from `@[scope]` declarations; the fixture declares none.

   The test drops exactly the forge binary-read clause and then requires SET
   EQUALITY — both directions, so a clause added to one builder and not the
   other fails whichever way the drift runs.  Conditional grants are pinned
   separately in both polarities (FileWrite held means "allow file-write" is
   present in BOTH; Network not held means "allow network" appears in
   NEITHER), since baseline equality alone would pass if both builders
   stopped consulting the capability set entirely.

   macOS-only: SBPL is the Seatbelt backend; on Linux the same capability set
   becomes bubblewrap flags with no embedded profile to extract.  The skip is
   LOUD (a named skip test) rather than a silent pass. *)

let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

let is_macos =
  try
    let ic = Unix.open_process_in "uname -s" in
    let s = input_line ic in
    ignore (Unix.close_process_in ic);
    s = "Darwin"
  with _ -> false

(* Top-level s-expression clauses of an SBPL string, whitespace-normalized.
   SBPL string literals cannot contain parens in either builder's output, so
   depth counting alone is sound here. *)
let clauses_of (s : string) : string list =
  let out = ref [] and buf = Buffer.create 64 and depth = ref 0 in
  String.iter
    (fun c ->
       match c with
       | '(' ->
         incr depth;
         Buffer.add_char buf c
       | ')' ->
         decr depth;
         Buffer.add_char buf c;
         if !depth = 0 then begin
           out := Buffer.contents buf :: !out;
           Buffer.clear buf
         end
       | '\n' | '\t' -> if !depth > 0 then Buffer.add_char buf ' '
       | c -> if !depth > 0 then Buffer.add_char buf c)
    s;
  !out
  |> List.map (fun c ->
      String.concat " "
        (List.filter (fun w -> w <> "") (String.split_on_char ' ' c)))
  |> List.sort_uniq compare

let fixture_src =
  {|
mod SbxDrift do
  needs IO.Console
  needs IO.FileWrite
  fn main() do
    match file_write("/tmp/sbx_drift_out", "d") do
      Ok(_)  -> println("ok")
      Err(_) -> println("e")
    end
  end
end
|}

let embedded_profile () : string =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf "compiler not found at %s" compiler_exe;
  let src = Filename.temp_file "sbx_drift" ".march" in
  let oc = open_out src in
  output_string oc fixture_src;
  close_out oc;
  let bin = Filename.temp_file "sbx_drift" ".bin" in
  let log = Filename.temp_file "sbx_drift" ".log" in
  let rc =
    Sys.command
      (Printf.sprintf "%s --cap-sandbox --compile -o %s %s > %s 2>&1"
         (Filename.quote compiler_exe) (Filename.quote bin)
         (Filename.quote src) (Filename.quote log))
  in
  if rc <> 0 then begin
    let ic = open_in log in
    let out = really_input_string ic (in_channel_length ic) in
    close_in ic;
    Alcotest.failf "--cap-sandbox compile failed (%d):\n%s" rc out
  end;
  let ic =
    Unix.open_process_in
      (Printf.sprintf "strings %s | grep '(version 1)' | head -1"
         (Filename.quote bin))
  in
  let line = try input_line ic with End_of_file -> "" in
  ignore (Unix.close_process_in ic);
  List.iter (fun f -> try Sys.remove f with Sys_error _ -> ()) [ src; bin; log ];
  if line = "" then
    Alcotest.fail
      "no '(version 1)' profile string found in the --cap-sandbox binary — \
       either the embed broke or the extraction did; both are drift-test \
       failures, not skips";
  line

let is_forge_binary_read ~binary clause =
  (* The one clause forge adds that the embedded profile cannot: the explicit
     launch-target read.  Matched on the literal path we passed in, so a NEW
     forge-only clause never hides behind this filter. *)
  clause = Printf.sprintf "(allow file-read* (literal %S))" binary

let test_baselines_agree () =
  if not is_macos then Alcotest.skip ()
  else begin
    let binary = "/tmp/sbx_drift_probe_binary" in
    let forge_profile =
      March_forge.Cap_sandbox.profile_for
        ~caps:[ "IO.Console"; "IO.FileWrite" ] ~binary
    in
    let forge_clauses =
      List.filter
        (fun c -> not (is_forge_binary_read ~binary c))
        (clauses_of forge_profile)
    in
    let embedded_clauses = clauses_of (embedded_profile ()) in
    (* Two empty lists agree too — a broken [clauses_of] must fail here, not
       certify.  10 = version + deny + 8 baseline clauses, the floor either
       builder can emit. *)
    Alcotest.(check bool)
      (Printf.sprintf "clause parse is non-trivial (%d clauses)"
         (List.length embedded_clauses))
      true
      (List.length embedded_clauses >= 10);
    Alcotest.(check (list string))
      "the embedded --cap-sandbox profile and forge's profile_for emit the \
       same clause set for the same capability set"
      forge_clauses embedded_clauses
  end

let test_conditional_grants_agree () =
  if not is_macos then Alcotest.skip ()
  else begin
    let binary = "/tmp/sbx_drift_probe_binary" in
    let forge_clauses =
      clauses_of
        (March_forge.Cap_sandbox.profile_for
           ~caps:[ "IO.Console"; "IO.FileWrite" ] ~binary)
    in
    let embedded_clauses = clauses_of (embedded_profile ()) in
    let has l c = List.mem c l in
    (* Held capability grants in BOTH; unheld in NEITHER.  Without this, both
       builders ignoring the capability set entirely would still pass the
       baseline-equality test above. *)
    Alcotest.(check bool) "file-write* granted by forge" true
      (has forge_clauses "(allow file-write*)");
    Alcotest.(check bool) "file-write* granted by the embedded profile" true
      (has embedded_clauses "(allow file-write*)");
    Alcotest.(check bool) "network* NOT granted by forge" false
      (has forge_clauses "(allow network*)");
    Alcotest.(check bool) "network* NOT granted by the embedded profile" false
      (has embedded_clauses "(allow network*)")
  end

let tests =
  [ Alcotest.test_case "sbpl baselines agree (embedded vs forge)" `Slow
      test_baselines_agree;
    Alcotest.test_case "sbpl conditional grants agree" `Slow
      test_conditional_grants_agree;
  ]
