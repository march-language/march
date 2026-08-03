(* Capability marker emission (design §4.3, mechanism C).

   A marker global must exist for each capability the emitted module actually
   references, and must NOT exist for capabilities it does not use.  Markers
   are recorded at mangle_extern resolution time — the declare preamble lists
   every builtin unconditionally and must never produce markers (that would
   re-create the app-invariance trap, design §3). *)

let emit_ir src_text =
  let src = Filename.temp_file "cap_marker" ".march" in
  let oc = open_out src in
  output_string oc src_text;
  close_out oc;
  (* --emit-llvm ignores -o: it writes <input-basename>.ll next to the input
     (bin/main.ml:2616, `let ll_file = basename ^ ".ll"`). *)
  let ll = Filename.remove_extension src ^ ".ll" in
  let rc =
    Sys.command
      (Printf.sprintf "./_build/default/bin/main.exe --emit-llvm %s > /dev/null 2>&1"
         (Filename.quote src))
  in
  if rc <> 0 then Alcotest.failf "emit-llvm failed (rc=%d)" rc;
  let ic = open_in ll in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  Sys.remove src;
  Sys.remove ll;
  s

let contains haystack needle =
  let nl = String.length needle and hl = String.length haystack in
  let rec go i = i + nl <= hl && (String.sub haystack i nl = needle || go (i + 1)) in
  nl = 0 || go 0

let file_src =
  {|
mod MarkerFileApp do
  needs IO.FileRead
  fn main() : () do
    match file_read("/etc/hosts") do
      Ok(_) -> println("ok")
      Err(_) -> println("err")
    end
  end
end
|}

let pure_src =
  {|
mod MarkerPureApp do
  fn main() : () do
    println("hi")
  end
end
|}

let test_marker_present_for_used_cap () =
  let ir = emit_ir file_src in
  Alcotest.(check bool) "IO.FileRead marker emitted" true
    (contains ir "@__march_cap_IO_FileRead");
  Alcotest.(check bool) "markers are pinned via llvm.used" true
    (contains ir "@llvm.used")

let test_marker_absent_for_unused_cap () =
  let ir = emit_ir pure_src in
  (* println means IO.Console IS used — that marker must appear; the point is
     that FileRead must NOT, even though the preamble declares it. *)
  Alcotest.(check bool) "IO.Console marker emitted for println" true
    (contains ir "@__march_cap_IO_Console");
  Alcotest.(check bool) "no IO.FileRead marker for a pure program" false
    (contains ir "@__march_cap_IO_FileRead")

let tests =
  [
    Alcotest.test_case "marker emitted for used capability" `Slow
      test_marker_present_for_used_cap;
    Alcotest.test_case "no marker for unused capability" `Slow
      test_marker_absent_for_unused_cap;
  ]
