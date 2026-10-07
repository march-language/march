(* --rc-trace site ids on the MARCH_TRACE_GC runtime trace, and the report
   that folds the trace into per-object histories
   (specs/plans/incremental-codegen-cas-plan.md §8, A3;
   specs/progress/2026-10-06-rc-trace-site-ids.md).

   Three layers, each with its own non-vacuity:
   - the text rewrite itself (Llvm_rc_trace.rewrite) on a synthetic module,
     so a change to the bracketing or the table shape fails here, not in a
     dune diff three suites away;
   - the driver: the switch OFF leaves --emit-llvm output free of any site
     machinery (scripts/ir-oracle.sh proves byte-identity over the corpus;
     this is the one-program smoke), ON adds it;
   - the whole loop on a program that leaks ON PURPOSE
     (test/native/rc_trace_leak_site.march): compile with --rc-trace, run
     under MARCH_TRACE_GC=1, fold with scripts/gc-trace-report.py, and the
     report must name the leaking function and nothing else. *)

open Test_helpers

let contains hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i = i + m <= n && (String.sub hay i m = needle || go (i + 1)) in
  m = 0 || go 0

let count hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i acc =
    if i + m > n then acc
    else if String.sub hay i m = needle then go (i + m) (acc + 1)
    else go (i + 1) acc
  in
  if m = 0 then 0 else go 0 0

(* ── the rewrite ──────────────────────────────────────────────────────── *)

let synthetic_ir = {|declare void @march_incrc(ptr %p)
declare ptr @march_string_concat(ptr, ptr)
declare void @march_set_atom_namer(ptr)
define internal void @march_atom_namer_register() {
entry:
  call void @march_set_atom_namer(ptr null)
  ret void
}
@llvm.global_ctors = appending global [1 x { i32, ptr, ptr }] [{ i32, ptr, ptr } { i32 65535, ptr @march_atom_namer_register, ptr null }]
define ptr @Main.f(ptr %a, ptr %b) {
entry:
  call void @march_incrc(ptr %a)
  %s = call ptr @march_string_concat(ptr %a, ptr %b)
  %n = add i64 1, 2
  ret ptr %s
}
define ptr @"Main.g$1"(ptr %a) {
entry:
  call void @march_incrc(ptr %a)
  ret ptr %a
}
|}

let test_rewrite_brackets_runtime_calls () =
  let out = March_tir.Llvm_rc_trace.rewrite synthetic_ir in
  (* Every runtime call in a compiled function is bracketed: set before,
     clear after.  The atom-namer registration function counts too (it is a
     define in the module); the declares do not. *)
  Alcotest.(check int) "four sites registered: namer register, f's two calls, g's one"
    1 (count out "call void @march_rc_sites_register(ptr @__march_rc_site_names, i32 4)");
  Alcotest.(check int) "four clears" 4 (count out "call void @march_rc_site_set(i32 -1)");
  Alcotest.(check bool) "site 1 precedes f's incrc" true
    (contains out "  call void @march_rc_site_set(i32 1)\n  call void @march_incrc(ptr %a)\n  call void @march_rc_site_set(i32 -1)");
  Alcotest.(check bool) "site 2 precedes f's concat (a call with a result)" true
    (contains out "  call void @march_rc_site_set(i32 2)\n  %s = call ptr @march_string_concat(ptr %a, ptr %b)\n  call void @march_rc_site_set(i32 -1)");
  (* The table names <fn>#<ordinal>:<callee>, ordinals per function. *)
  Alcotest.(check bool) "f#0 names the incrc" true (contains out {|c"Main.f#0:march_incrc\00"|});
  Alcotest.(check bool) "f#1 names the concat" true (contains out {|c"Main.f#1:march_string_concat\00"|});
  Alcotest.(check bool) "quoted symbol unquoted, ordinal restarts" true
    (contains out {|c"Main.g$1#0:march_incrc\00"|});
  Alcotest.(check bool) "namer register is site 0" true
    (contains out {|@__march_rc_site_0 = private unnamed_addr constant [49 x i8] c"march_atom_namer_register#0:march_set_atom_namer\00"|});
  (* The module already had a constructor table: extended, not duplicated. *)
  Alcotest.(check int) "one global_ctors" 1 (count out "@llvm.global_ctors = ");
  Alcotest.(check bool) "two entries, ours first" true
    (contains out "@llvm.global_ctors = appending global [2 x { i32, ptr, ptr }] [{ i32, ptr, ptr } { i32 65535, ptr @__march_rc_sites_register, ptr null }, { i32, ptr, ptr } { i32 65535, ptr @march_atom_namer_register, ptr null }]");
  (* The arithmetic line and the declares are untouched. *)
  Alcotest.(check bool) "non-runtime instruction kept" true (contains out "  %n = add i64 1, 2\n  ret ptr %s");
  Alcotest.(check int) "declares not bracketed" 1 (count out "declare void @march_incrc(ptr %p)\n")

let test_rewrite_no_runtime_calls_is_identity () =
  let ir = "define i64 @Main.k(i64 %x) {\nentry:\n  %y = add i64 %x, 1\n  ret i64 %y\n}\n" in
  Alcotest.(check string) "returned unchanged" ir (March_tir.Llvm_rc_trace.rewrite ir)

let test_rewrite_fresh_ctor_table_when_none () =
  let ir = "declare void @march_incrc(ptr)\ndefine void @Main.h(ptr %a) {\nentry:\n  call void @march_incrc(ptr %a)\n  ret void\n}\n" in
  let out = March_tir.Llvm_rc_trace.rewrite ir in
  Alcotest.(check bool) "a constructor table is created" true
    (contains out "@llvm.global_ctors = appending global [1 x { i32, ptr, ptr }] [{ i32, ptr, ptr } { i32 65535, ptr @__march_rc_sites_register, ptr null }]")

(* ── the driver switch ────────────────────────────────────────────────── *)

let small_src =
  "mod Rt do\n\
  \  needs IO.Console\n\
  \  pfn greet(n : Int) : String do \"n=\" ++ int_to_string(n) end\n\
  \  fn main(_cap : Cap(IO.Console)) : Unit do println(greet(3)) end\n\
   end\n"

let emit_llvm ~env src =
  let main_exe = find_main_exe () in
  let project_root = march_project_root () in
  let tmp = Filename.temp_file "march_rctrace_emit" "" in
  Sys.remove tmp; Unix.mkdir tmp 0o755;
  let path = Filename.concat tmp "rt.march" in
  let oc = open_out path in output_string oc src; close_out oc;
  let (rc, out) = run_capture (Printf.sprintf "cd %s && %s %s --emit-llvm %s"
      (Filename.quote project_root) env (Filename.quote main_exe) (Filename.quote path)) in
  if rc <> 0 then Alcotest.failf "--emit-llvm failed (rc=%d):\n%s" rc out;
  read_file_contents (Filename.concat tmp "rt.ll")

let test_switch_off_emits_no_site_machinery () =
  let ir = emit_llvm ~env:"" small_src in
  Alcotest.(check int) "no site stores" 0 (count ir "march_rc_site_set");
  Alcotest.(check int) "no site table" 0 (count ir "__march_rc_site");
  Alcotest.(check bool) "but the program does refcount" true (contains ir "march_decrc")

let test_switch_on_emits_sites_and_table () =
  let ir = emit_llvm ~env:"MARCH_RC_TRACE=1" small_src in
  Alcotest.(check bool) "site stores present" true (count ir "call void @march_rc_site_set(i32 " > 2);
  (* greet is inlined into main at this size, so the site that names the
     concatenation is main's; the callee half of the label is what matters. *)
  Alcotest.(check bool) "a site names the concat it precedes" true
    (contains ir ":march_string_concat\\00\"");
  Alcotest.(check bool) "the table starts at id 0" true (contains ir "@__march_rc_site_0 = ");
  Alcotest.(check bool) "the table is registered from a constructor" true
    (contains ir "ptr @__march_rc_sites_register, ptr null");
  (* The inline refcount twins still run after this pass: the bracketed
     refcount calls are the twins, which take the out-of-line branch while
     tracing is on, so the stored site reaches the runtime. *)
  Alcotest.(check bool) "inline twins still applied after the site pass" true
    (contains ir "@__march_rc_decrc(" || contains ir "@__march_rc_decrc_local(")

(* ── the whole loop ───────────────────────────────────────────────────── *)

let report_of ~project_root ~main_exe ~src ~tmp =
  rc_trace_report ~project_root ~main_exe ~src ~tmp

let test_report_names_the_leaking_site () =
  let main_exe = find_main_exe () in
  let project_root = march_project_root () in
  let fixture = Filename.concat project_root "test/native/rc_trace_leak_site.march" in
  let tmp = Filename.temp_file "march_rctrace_leak" "" in
  Sys.remove tmp; Unix.mkdir tmp 0o755;
  if Sys.command "command -v clang >/dev/null 2>&1" <> 0 then () (* tool-absence skip, as compile_march_or_skip *)
  else begin
    let out = report_of ~project_root ~main_exe ~src:fixture ~tmp in
    (* --top 20 and three live objects: the live section is the whole of the
       object listing, so the counts below are over [out] itself. *)
    let live_section = out in
    Alcotest.(check bool) ("the traced run printed its deltas:\n" ^ out) true
      (contains out "sum: 716" && contains out "delta:");
    Alcotest.(check bool) ("exactly three live objects, the leaked strings:\n" ^ out) true
      (contains out "live at end: 3");
    Alcotest.(check int) ("three LIVE entries:\n" ^ out) 3 (count live_section "\nLIVE ");
    Alcotest.(check int) ("every leaked string was allocated by leak_loop's concat:\n" ^ out) 3
      (count live_section "allocated at leak_loop#");
    Alcotest.(check int) ("and retained by leak_loop's march_incrc call:\n" ^ out) 3
      (count live_section "    inc_ref  rc=2    leak_loop#");
    Alcotest.(check bool) ("the retaining site names march_incrc:\n" ^ out) true
      (contains live_section ":march_incrc\n");
    Alcotest.(check bool) ("balanced_loop is not blamed for any live object:\n" ^ out) false
      (contains live_section "LIVE 0x" && contains live_section "allocated at balanced_loop#");
    Alcotest.(check bool) ("literal cells are immortal, not leaks:\n" ^ out) true
      (contains out "immortal: 4");
    Alcotest.(check bool) ("no inconsistent history:\n" ^ out) true
      (contains out "inconsistent: 0");
    Alcotest.(check bool) ("the report's exit status flags the leak:\n" ^ out) true
      (contains out "report (rc=1;")
  end

(* The other direction: a program that churns strings and leaks nothing must
   report zero live objects, with the string allocations (traced since this
   work) balanced against their frees.  Without this, "names the leaking
   site" could pass on a report that calls everything live. *)
let clean_src =
  "mod Clean do\n\
  \  needs IO.Console\n\
  \  pfn churn(n : Int, acc : Int) : Int do\n\
  \    if n <= 0 do acc else\n\
  \      let s = \"item-\" ++ int_to_string(n)\n\
  \      churn(n - 1, acc + String.byte_size(s))\n\
  \    end\n\
  \  end\n\
  \  fn main(_cap : Cap(IO.Console)) : Unit do\n\
  \    println(\"total: \" ++ int_to_string(churn(200, 0)))\n\
  \  end\n\
   end\n"

let test_report_clean_program_has_no_live_objects () =
  let main_exe = find_main_exe () in
  let project_root = march_project_root () in
  let tmp = Filename.temp_file "march_rctrace_clean" "" in
  Sys.remove tmp; Unix.mkdir tmp 0o755;
  let src = Filename.concat tmp "clean.march" in
  let oc = open_out src in output_string oc clean_src; close_out oc;
  if Sys.command "command -v clang >/dev/null 2>&1" <> 0 then ()
  else begin
    let out = report_of ~project_root ~main_exe ~src ~tmp in
    Alcotest.(check bool) ("ran:\n" ^ out) true (contains out "total: ");
    Alcotest.(check bool) ("strings were traced at all (allocs attributed to churn):\n" ^ out) true
      (contains out "churn#" && contains out ":march_string_concat");
    Alcotest.(check bool) ("nothing live:\n" ^ out) true (contains out "live at end: 0");
    Alcotest.(check bool) ("exit 0:\n" ^ out) true (contains out "report (rc=0;")
  end

let suites = [
  ( "rc_trace", [
      Alcotest.test_case "rewrite brackets every runtime call and merges the ctor table" `Quick
        test_rewrite_brackets_runtime_calls;
      Alcotest.test_case "rewrite is the identity without runtime calls" `Quick
        test_rewrite_no_runtime_calls_is_identity;
      Alcotest.test_case "rewrite creates the ctor table when none exists" `Quick
        test_rewrite_fresh_ctor_table_when_none;
      Alcotest.test_case "switch off: --emit-llvm has no site machinery" `Quick
        test_switch_off_emits_no_site_machinery;
      Alcotest.test_case "switch on: sites, table, twins still inlined" `Quick
        test_switch_on_emits_sites_and_table;
      Alcotest.test_case "report names the leaking site (deliberate leak fixture)" `Slow
        test_report_names_the_leaking_site;
      Alcotest.test_case "report shows zero live objects for a clean program" `Slow
        test_report_clean_program_has_no_live_objects;
    ] );
]
