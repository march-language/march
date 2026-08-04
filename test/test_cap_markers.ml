(* Capability marker emission (design §4.3, mechanism C).

   A marker global must exist for each capability the emitted module actually
   references, and must NOT exist for capabilities it does not use.  Markers
   are recorded at mangle_extern resolution time — the declare preamble lists
   every builtin unconditionally and must never produce markers (that would
   re-create the app-invariance trap, design §3). *)

(* Exe-relative, for the same reason as test_cap_strip.ml: a CWD-relative
   path returns 127 under dune's test runner. *)
let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

let emit_ir src_text =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf "compiler not found at %s" compiler_exe;
  let src = Filename.temp_file "cap_marker" ".march" in
  let oc = open_out src in
  output_string oc src_text;
  close_out oc;
  (* --emit-llvm ignores -o: it writes <input-basename>.ll next to the input
     (bin/main.ml:2616, `let ll_file = basename ^ ".ll"`). *)
  let ll = Filename.remove_extension src ^ ".ll" in
  let rc =
    Sys.command
      (Printf.sprintf "%s --emit-llvm %s > /dev/null 2>&1"
         (Filename.quote compiler_exe) (Filename.quote src))
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

(* The hardest routing case: a builtin passed DIRECTLY as a first-class value,
   never syntactically applied in the caller.  Codegen builds a
   closure + $clo_wrap trampoline for it (fixed upstream in 57376dce, which
   also fixed a SIGBUS here) — the marker must still be recorded, or a program
   can perform a capability the audit never reports.  This is the routing that
   defeated the call-site scanning approach entirely (design §3). *)
let direct_pass_src =
  {|
mod MarkerDirectPassApp do
  needs IO.FileRead

  fn apply1(f : (String) -> a, p : String) : a do
    f(p)
  end

  fn main() : () do
    match apply1(file_read, "/etc/hosts") do
      Ok(_)  -> println("ok")
      Err(_) -> println("err")
    end
  end
end
|}

let test_marker_for_directly_passed_builtin () =
  let ir = emit_ir direct_pass_src in
  Alcotest.(check bool)
    "IO.FileRead marker emitted for a builtin passed as a bare value" true
    (contains ir "@__march_cap_IO_FileRead")

let tests =
  [
    Alcotest.test_case "marker emitted for used capability" `Slow
      test_marker_present_for_used_cap;
    Alcotest.test_case "marker for directly-passed builtin value" `Slow
      test_marker_for_directly_passed_builtin;
    Alcotest.test_case "no marker for unused capability" `Slow
      test_marker_absent_for_unused_cap;
  ]

(* ── Per-module attribution (lib/tir/cap_attrib.ml) ──────────────────────
   The flat marker says the binary reads files; @__march_capfrom_ says WHOSE
   code does the reading.  Each case below is a route by which attribution
   was measured to go wrong, or would go wrong under the obvious
   implementation. *)

let attrib_inlined_src =
  {|
mod AttribApp do
  mod Dep do
    needs IO.FileRead
    fn slurp(p : String) : String do
      match file_read(p) do
        Ok(s)  -> s
        Err(_) -> ""
      end
    end
  end
  fn main() : () do
    println(Dep.slurp("/etc/hosts"))
  end
end
|}

let test_attributed_to_dep_not_app_despite_inlining () =
  (* The load-bearing case.  [Dep.slurp] is small enough that the inliner
     folds it into main and no trace of [Dep] survives to the emitted IR —
     measured.  Attributing at codegen time would therefore credit the
     dependency's file read to the application: a clean bill for the
     dependency and a false one for the app, which is the wrong direction for
     every decision this feature exists to support.  Attribution is taken
     pre-inline precisely so this says Dep. *)
  let ir = emit_ir attrib_inlined_src in
  Alcotest.(check bool) "IO.FileRead attributed to Dep" true
    (contains ir "@__march_capfrom_IO_FileRead__Dep");
  Alcotest.(check bool) "IO.FileRead NOT attributed to the app" false
    (contains ir "@__march_capfrom_IO_FileRead__AttribApp")

let attrib_stdlib_wrapper_src =
  {|
mod WrapApp do
  mod Dep do
    needs IO.FileRead
    fn slurp(p : String) : String do
      match File.read(p) do
        Ok(s)  -> s
        Err(_) -> ""
      end
    end
  end
  fn main() : () do
    println(Dep.slurp("/etc/hosts"))
  end
end
|}

let test_stdlib_wrapper_is_seen_through () =
  (* Before the transparent-module walk this reported [File] — and since most
     dependencies reach IO through a stdlib wrapper, every capability in a
     real program landed on a handful of stdlib modules.  A report that names
     the same owner regardless of which dependency is responsible answers
     nobody's question, so stdlib is walked through to the caller. *)
  let ir = emit_ir attrib_stdlib_wrapper_src in
  Alcotest.(check bool) "attributed to the calling module" true
    (contains ir "@__march_capfrom_IO_FileRead__Dep");
  Alcotest.(check bool) "NOT attributed to the stdlib wrapper" false
    (contains ir "@__march_capfrom_IO_FileRead__File")

let attrib_unused_feature_src =
  {|
mod PartialApp do
  mod Dep do
    needs IO.FileRead
    fn add(a : Int, b : Int) : Int do
      a + b
    end
    fn slurp(p : String) : String do
      match file_read(p) do
        Ok(s)  -> s
        Err(_) -> ""
      end
    end
  end
  fn main() : () do
    println(Int.to_string(Dep.add(2, 3)))
  end
end
|}

let test_unused_feature_contributes_nothing () =
  (* Using one function of a module must not import the capabilities of the
     functions you did not call — neither the flat marker nor an owner row.
     Attribution runs after reachability pruning so that stays true. *)
  let ir = emit_ir attrib_unused_feature_src in
  Alcotest.(check bool) "no IO.FileRead marker at all" false
    (contains ir "@__march_cap_IO_FileRead");
  Alcotest.(check bool) "no IO.FileRead owner row either" false
    (contains ir "@__march_capfrom_IO_FileRead")

let test_attribution_prefix_cannot_be_read_as_a_flat_marker () =
  (* forge's Cap_binary matches the "__march_cap_" prefix and takes the whole
     remainder as the capability path.  An attribution marker spelled
     @__march_cap_IO_FileRead__Dep would decode as a bogus capability named
     "IO_FileRead__Dep", so the two prefixes must diverge before that point. *)
  let ir = emit_ir attrib_inlined_src in
  Alcotest.(check bool) "attribution markers do not start with __march_cap_"
    false
    (contains ir "@__march_cap_IO_FileRead__")

let tests =
  tests
  @ [
      Alcotest.test_case "attributed to the dep despite inlining" `Slow
        test_attributed_to_dep_not_app_despite_inlining;
      Alcotest.test_case "stdlib wrapper is seen through" `Slow
        test_stdlib_wrapper_is_seen_through;
      Alcotest.test_case "unused feature contributes no owner row" `Slow
        test_unused_feature_contributes_nothing;
      Alcotest.test_case "attribution prefix is not a flat-marker prefix" `Slow
        test_attribution_prefix_cannot_be_read_as_a_flat_marker;
    ]

let test_builtin_passed_as_a_value_is_attributed () =
  (* [direct_pass_src] hands file_read to apply1 as a VALUE; defun only later
     synthesizes the wrapper that calls it, so an EApp-only walk saw nothing
     and the capability was emitted with no owner at all — the module handing
     out the authority escaped attribution entirely.  Measured before the
     atom scan was added.  Charging it to the module that passes the value is
     the right answer: that module is the one granting the capability. *)
  let ir = emit_ir direct_pass_src in
  Alcotest.(check bool) "flat marker reports the capability" true
    (contains ir "@__march_cap_IO_FileRead");
  Alcotest.(check bool) "and it now has an owner" true
    (contains ir "@__march_capfrom_IO_FileRead__")

let tests =
  tests
  @ [
      Alcotest.test_case "builtin passed as a value is attributed" `Slow
        test_builtin_passed_as_a_value_is_attributed;
    ]
