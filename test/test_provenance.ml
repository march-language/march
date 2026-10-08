(* Provenance side table + --debug-info (specs/plans/incremental-codegen-cas-
   plan.md §7, A2; specs/progress/2026-10-06-provenance-table-debug-info.md).

   What is pinned here:
   1. completeness: after the full pipeline every top-level fn has an origin;
      user fns carry their source span (including a fn in a nested module,
      whose name was prefixed AFTER lowering created it); mono specialisations,
      lifted lambdas and fused helpers carry a derivation, and lifted lambdas
      carry their host;
   2. the emitter: with [Llvm_toplevel.debug_info] off the module carries no
      metadata at all (the ir-oracle proves byte-identity to the pre-A2
      emitter); with it on, every define carries [!dbg], the compile-unit
      block and [!march.provenance] are present, every call inside a [!dbg]
      function carries a location, and the result passes the LLVM verifier
      both before and after [Llvm_rc_inline.rewrite];
   3. [attach_call_dbg] in isolation, RED-first: a call in a [!dbg] function
      gains the paired location, one outside does not, one that already has
      a location is left alone. *)

open Test_helpers

let src = {|mod Test do
  fn ident(x) do x end

  mod Inner do
    fn twice(n : Int) : Int do n * 2 end
  end

  type IntList = INil | ICons(Int, IntList)

  fn imap(xs : IntList, f : Int -> Int) : IntList do
    match xs do
    INil        -> INil
    ICons(h, t) -> ICons(f(h), imap(t, f))
    end
  end

  fn ifold(xs : IntList, acc : Int, f : Int -> Int -> Int) : Int do
    match xs do
    INil        -> acc
    ICons(h, t) -> ifold(t, f(acc, h), f)
    end
  end

  fn pipeline(xs : IntList) : Int do
    let ys = imap(xs, fn x -> x * 2)
    ifold(ys, 0, fn (a, b) -> a + b)
  end

  fn main() : Int do
    let a = ident(1)
    let _b = ident("s")
    let f = fn y -> y + a
    f(Inner.twice(3)) + pipeline(ICons(1, ICons(2, INil)))
  end
end|}

let starts_with pre s =
  String.length s >= String.length pre && String.sub s 0 (String.length pre) = pre

let contains hay needle =
  let n = String.length needle and h = String.length hay in
  let rec go i = i + n <= h && (String.sub hay i n = needle || go (i + 1)) in
  n = 0 || go 0

(* Lower + the driver's own pass sequence, so the table is exactly what a
   build sees. *)
let pipeline_of src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let iface_methods = March_tir.Lower.get_iface_methods () in
  March_tir.Contract_pipeline.run ~iface_methods ~opt:true tir

let test_every_fn_has_an_origin () =
  let pipe = pipeline_of src in
  let fns = pipe.March_tir.Contract_pipeline.final.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "pipeline emitted functions" true (fns <> []);
  let missing = List.filter_map (fun (fd : March_tir.Tir.fn_def) ->
      if March_tir.Provenance.find fd.fn_name = None then Some fd.fn_name else None) fns in
  Alcotest.(check (list string)) "every final top-level fn has an origin" [] missing;
  (* A synthetic (lifted / fused / cloned) fn names what it came from: a host
     or a derivation.  The RED half: a top-level user fn has neither. *)
  let is_synthetic n = starts_with "$" n || contains n "$apply$" || contains n "$hspec$" in
  let bare = List.filter_map (fun (fd : March_tir.Tir.fn_def) ->
      match March_tir.Provenance.find fd.fn_name with
      | Some { host = None; derived = []; _ } when is_synthetic fd.fn_name -> Some fd.fn_name
      | _ -> None) fns in
  Alcotest.(check (list string)) "every synthetic fn has a host or a derivation" [] bare

let span_line name =
  match March_tir.Provenance.find name with
  | Some { src_span = Some sp; _ } -> Some sp.March_ast.Ast.start_line
  | _ -> None

let test_user_fns_keep_their_span () =
  ignore (pipeline_of src);
  (* The table is complete for the whole module, not just what survived DCE
     and inlining, so these are looked up by name regardless of the final
     tm_fns. *)
  Alcotest.(check (option int)) "ident: line of its declaration" (Some 2) (span_line "ident");
  Alcotest.(check (option int)) "nested-module fn: prefixed name keeps its span"
    (Some 5) (span_line "Inner.twice");
  Alcotest.(check (option int)) "pipeline" (Some 24) (span_line "pipeline");
  Alcotest.(check (option int)) "main" (Some 29) (span_line "main")

let test_derivations () =
  ignore (pipeline_of src);
  let all = March_tir.Provenance.all () in
  let find_by pred = List.filter (fun (n, _) -> pred n) all in
  (* Mono: ident at Int and at String, each derived from the generic. *)
  (match March_tir.Provenance.find "ident$Int" with
   | Some { derived = [March_tir.Provenance.Mono_of ("ident", [March_tir.Tir.TInt])];
            src_span = Some sp; _ } ->
     Alcotest.(check int) "specialisation inherits the generic's span" 2 sp.March_ast.Ast.start_line
   | Some o -> Alcotest.failf "ident$Int: unexpected origin %s" (March_tir.Provenance.render o)
   | None -> Alcotest.fail "ident$Int: no origin");
  Alcotest.(check bool) "ident$String recorded as Mono_of" true
    (match March_tir.Provenance.find "ident$String" with
     | Some { derived = [March_tir.Provenance.Mono_of ("ident", [March_tir.Tir.TString])]; _ } -> true
     | _ -> false);
  (* Defun: every lifted lambda names its lambda and its host. *)
  let applies = find_by (fun n -> contains n "$apply$") in
  Alcotest.(check bool) "at least one lifted lambda" true (applies <> []);
  let user_applies = List.filter (fun (_, (o : March_tir.Provenance.origin)) ->
      match o.host with Some h -> List.mem h ["main"; "pipeline"] | None -> false) applies in
  Alcotest.(check int) "the three user lambdas are hosted by main/pipeline" 3
    (List.length user_applies);
  List.iter (fun (n, (o : March_tir.Provenance.origin)) ->
      (match o.derived with
       | [March_tir.Provenance.Defun_of lam] ->
         Alcotest.(check bool) (n ^ ": Defun_of names a <host>$lam") true (contains lam "$lam")
       | _ -> Alcotest.failf "%s: expected Defun_of, got %s" n (March_tir.Provenance.render o));
      Alcotest.(check bool) (n ^ ": lambda span recorded") true (o.src_span <> None))
    user_applies;
  (* Fusion: the imap/ifold pipeline fuses into a $fused_mf helper that
     names producer and consumer and is hosted by the fn it was rewritten in. *)
  let fused = find_by (fun n -> starts_with "$fused_" n) in
  Alcotest.(check bool) "the map/fold pipeline fused" true (fused <> []);
  List.iter (fun (n, (o : March_tir.Provenance.origin)) ->
      (match o.derived with
       | [March_tir.Provenance.Fusion_of (p, c)] ->
         Alcotest.(check bool) (n ^ ": producer is imap") true (contains p "imap");
         Alcotest.(check bool) (n ^ ": consumer is ifold") true (contains c "ifold")
       | _ -> Alcotest.failf "%s: expected Fusion_of, got %s" n (March_tir.Provenance.render o));
      Alcotest.(check (option string)) (n ^ ": host") (Some "pipeline") o.host) fused

(* ── Emitter ──────────────────────────────────────────────────────────── *)

let with_debug_info on f =
  let saved = !March_tir.Llvm_toplevel.debug_info in
  March_tir.Llvm_toplevel.debug_info := on;
  Fun.protect ~finally:(fun () -> March_tir.Llvm_toplevel.debug_info := saved) f

let emit ~debug_info =
  let pipe = pipeline_of src in
  let ir = with_debug_info debug_info (fun () ->
      March_tir.Llvm_emit.emit_module ~k_table:pipe.March_tir.Contract_pipeline.k_table
        pipe.March_tir.Contract_pipeline.final) in
  (pipe.March_tir.Contract_pipeline.final, ir)

let lines s = String.split_on_char '\n' s

let test_off_emits_no_metadata () =
  let (_, ir) = emit ~debug_info:false in
  Alcotest.(check bool) "no !dbg" false (contains ir "!dbg");
  Alcotest.(check bool) "no compile unit" false (contains ir "!llvm.dbg.cu");
  Alcotest.(check bool) "no provenance node" false (contains ir "!march.provenance")

let verify_text label ir =
  match find_llvm_verifier_tool () with
  | `None -> record_jit_skip ("no LLVM verifier tool — " ^ label ^ " not verified")
  | _ ->
    let path = Filename.temp_file "march_prov" ".ll" in
    let oc = open_out path in output_string oc ir; close_out oc;
    let r = verify_llvm_ir_file path in
    (try Sys.remove path with Sys_error _ -> ());
    (match r with
     | `Ok -> ()
     | `Invalid out -> Alcotest.failf "%s: verifier rejected the IR:\n%s" label out
     | `NoTool -> ())

let test_on_emits_function_level_dbg () =
  let (final, ir) = emit ~debug_info:true in
  Alcotest.(check bool) "compile unit" true (contains ir "!llvm.dbg.cu = !{!0}");
  Alcotest.(check bool) "Debug Info Version flag" true
    (contains ir "!\"Debug Info Version\", i32 3");
  Alcotest.(check bool) "!march.provenance named node" true (contains ir "!march.provenance = !{");
  let defines = List.filter (fun l -> starts_with "define " l) (lines ir) in
  Alcotest.(check bool) "has defines" true (defines <> []);
  (* Every MARCH function's define carries !dbg.  Emitter glue that is not
     a March function (the C `main` entry wrapper, the closure-drop
     registrar) has no DISubprogram and needs none: the verifier's
     call-location rule is about the CALLER's subprogram. *)
  let march_defines = List.filter (fun l ->
      List.exists (fun (fd : March_tir.Tir.fn_def) ->
          contains l ("@" ^ March_tir.Llvm_builtins.mangle_extern fd.fn_name ^ "("))
        final.March_tir.Tir.tm_fns) defines in
  Alcotest.(check bool) "March functions were emitted" true (march_defines <> []);
  let without = List.filter (fun l -> not (contains l " !dbg !")) march_defines in
  Alcotest.(check (list string)) "every March function's define carries !dbg" [] without;
  let with_dbg = List.filter (fun l -> contains l " !dbg !") defines in
  let subprograms = List.filter (fun l -> contains l "!DISubprogram(") (lines ir) in
  Alcotest.(check int) "one DISubprogram per !dbg define"
    (List.length with_dbg) (List.length subprograms);
  (* Every call inside a !dbg function has a location (the verifier rule). *)
  let in_fn = ref false and bare_calls = ref [] in
  List.iter (fun l ->
      if starts_with "define " l then in_fn := contains l " !dbg !"
      else if l = "}" then in_fn := false
      else if !in_fn then begin
        let t = String.trim l in
        let is_call = contains t " call " || starts_with "call " t in
        if is_call && not (contains l ", !dbg !") then bare_calls := l :: !bare_calls
      end) (lines ir);
  Alcotest.(check (list string)) "no call without a location in a !dbg function" []
    (List.rev !bare_calls);
  (* A user fn's DISubprogram points at its March line; a lifted lambda's
     at the lambda's line. *)
  Alcotest.(check bool) "main's subprogram is on line 29" true
    (List.exists (fun l -> contains l "name: \"main\"" && contains l "line: 29") subprograms);
  verify_text "--debug-info IR" ir;
  verify_text "--debug-info IR after inline-RC rewrite" (March_tir.Llvm_rc_inline.rewrite ir)

(* ── attach_call_dbg, RED-first ──────────────────────────────────────── *)

let test_attach_call_dbg () =
  let input = String.concat "\n" [
      "define i64 @f(i64 %x) !dbg !10 {";
      "entry:";
      "  %r = call i64 @g(i64 %x)";
      "  call void @h()";
      "  %t = tail call i64 @g(i64 %r)";
      "  %s = call i64 @g(i64 %r), !dbg !99";
      "  %u = add i64 %r, 1";
      "  ret i64 %u";
      "}";
      "define i64 @g(i64 %x) {";
      "entry:";
      "  %r = call i64 @k(i64 %x)";
      "  ret i64 %r";
      "}";
      "";
    ] in
  let out = March_tir.Llvm_toplevel.attach_call_dbg input in
  let ls = lines out in
  let nth i = List.nth ls i in
  Alcotest.(check string) "define line untouched" "define i64 @f(i64 %x) !dbg !10 {" (nth 0);
  Alcotest.(check string) "call gets the paired location !11"
    "  %r = call i64 @g(i64 %x), !dbg !11" (nth 2);
  Alcotest.(check string) "void call too" "  call void @h(), !dbg !11" (nth 3);
  Alcotest.(check string) "tail call too" "  %t = tail call i64 @g(i64 %r), !dbg !11" (nth 4);
  Alcotest.(check string) "an existing location is kept"
    "  %s = call i64 @g(i64 %r), !dbg !99" (nth 5);
  Alcotest.(check string) "a non-call is untouched" "  %u = add i64 %r, 1" (nth 6);
  Alcotest.(check string) "a call outside a !dbg function is untouched (RED control)"
    "  %r = call i64 @k(i64 %x)" (nth 11);
  Alcotest.(check int) "line count preserved" (List.length (lines input)) (List.length ls)

(* ── End to end: --compile --debug-info links with -g and runs ────────── *)

let test_compiled_with_debug_info_runs () =
  let main_exe = find_main_exe () in
  let tmp = Filename.temp_file "march_prov_e2e" "" in
  Sys.remove tmp; Unix.mkdir tmp 0o755;
  let src_path = Filename.concat tmp "prov_e2e.march" in
  let oc = open_out src_path in
  output_string oc {|mod ProvE2e do
  needs IO.Console
  fn boom(n : Int) : Int do
    if n > 2 do panic("boom at " ++ Int.to_string(n)) else n end
  end
  fn main(_cap_console : Cap(IO.Console)) do
    println("before")
    println(Int.to_string(boom(5)))
  end
end
|};
  close_out oc;
  let bin = Filename.concat tmp "prov_e2e" in
  let (rc, out) = run_capture (Printf.sprintf "cd %s && %s --compile --debug-info -o %s %s </dev/null"
      (Filename.quote tmp) (Filename.quote main_exe) (Filename.quote bin)
      (Filename.quote (Filename.basename src_path))) in
  if rc <> 0 then begin
    rm_rf_temp_dir tmp;
    Alcotest.failf "--compile --debug-info failed (rc %d):\n%s" rc out
  end;
  let (rc, out) = run_capture (Filename.quote bin) in
  rm_rf_temp_dir tmp;
  Alcotest.(check int) "panics with exit 1" 1 rc;
  Alcotest.(check bool) "ran up to the panic" true (contains out "before");
  Alcotest.(check bool) "panic message" true (contains out "boom at 5")

let suites = [
  ("provenance", [
      Alcotest.test_case "every final top-level fn has an origin" `Quick
        test_every_fn_has_an_origin;
      Alcotest.test_case "user fns keep their span through lowering renames" `Quick
        test_user_fns_keep_their_span;
      Alcotest.test_case "mono / defun / fusion derivations and hosts" `Quick
        test_derivations;
      Alcotest.test_case "debug_info off: no metadata in the module" `Quick
        test_off_emits_no_metadata;
      Alcotest.test_case "debug_info on: !dbg per define, provenance, verifier-clean (+inline RC)" `Quick
        test_on_emits_function_level_dbg;
      Alcotest.test_case "attach_call_dbg: paired location on calls (RED-first)" `Quick
        test_attach_call_dbg;
      Alcotest.test_case "--compile --debug-info links with -g and runs" `Slow
        test_compiled_with_debug_info_runs;
    ]);
]
