(* @[no_alloc] allocation contracts — lib/tir/alloc_contract.ml.
   Design: specs/2026-09-03-allocation-contracts-design.md. *)
open Test_helpers
module AC = March_tir.Alloc_contract

let attrs_of src fn =
  let m = parse_and_desugar src in
  let rec find = function
    | [] -> None
    | March_ast.Ast.DFn (d, _) :: _
      when d.March_ast.Ast.fn_name.March_ast.Ast.txt = fn ->
      Some d.March_ast.Ast.fn_attrs
    | March_ast.Ast.DMod (_, _, inner, _) :: rest ->
      (match find inner with Some a -> Some a | None -> find rest)
    | _ :: rest -> find rest
  in
  find m.March_ast.Ast.mod_decls

let test_attr_forms_parse () =
  let src = {|mod T do
  @[no_alloc]
  fn a(x : Int) : Int do x end
  @[no_alloc(warn)]
  fn b(x : Int) : Int do x end
  @[no_alloc(assume)]
  fn c(x : Int) : Int do x end
end|} in
  Alcotest.(check (option (list string))) "hard" (Some ["no_alloc"]) (attrs_of src "a");
  Alcotest.(check (option (list string))) "warn" (Some ["no_alloc:warn"]) (attrs_of src "b");
  Alcotest.(check (option (list string))) "assume" (Some ["no_alloc:assume"]) (attrs_of src "c")

let test_form_of_attrs () =
  Alcotest.(check bool) "hard" true (AC.form_of_attrs ["no_alloc"] = Some AC.Hard);
  Alcotest.(check bool) "warn" true
    (AC.form_of_attrs ["vectorize"; "no_alloc:warn"] = Some AC.Warn);
  Alcotest.(check bool) "assume" true (AC.form_of_attrs ["no_alloc:assume"] = Some AC.Assume);
  Alcotest.(check bool) "none" true (AC.form_of_attrs ["vectorize"] = None)

let test_collect_qualifies_nested () =
  let m = parse_and_desugar {|mod T do
  mod Inner do
    @[no_alloc]
    fn helper(x : Int) : Int do x end
  end
  fn plain(x : Int) : Int do x end
end|} in
  let ds = AC.collect m in
  let find n = List.find_opt (fun d -> d.AC.d_name = n) ds in
  (match find "Inner.helper" with
   | Some d ->
     Alcotest.(check bool) "helper is Hard" true (d.AC.d_form = Some AC.Hard);
     Alcotest.(check int) "name span line" 4 d.AC.d_name_span.March_ast.Ast.start_line
   | None -> Alcotest.fail "Inner.helper not collected");
  (match find "plain" with
   | Some d -> Alcotest.(check bool) "plain has no form" true (d.AC.d_form = None)
   | None -> Alcotest.fail "plain not collected")

let msg_contains needle = function
  | Some m -> contains needle m
  | None -> false

let test_bad_payload_is_parse_error () =
  let msg = parse_error_msg {|mod T do
  @[no_alloc(strict)]
  fn a(x : Int) : Int do x end
end|} in
  Alcotest.(check bool) "mentions no_alloc" true (msg_contains "no_alloc" msg)

let test_no_alloc_on_actor_is_parse_error () =
  let msg = parse_error_msg {|mod T do
  @[no_alloc]
  actor Counter do
    state { value : Int }
    init { value: 0 }
    on Inc(n : Int) do { state with value: state.value + n } end
  end
end|} in
  Alcotest.(check bool) "mentions actors" true (msg_contains "actor" msg)

let tests = [
  Alcotest.test_case "attribute forms parse"          `Quick test_attr_forms_parse;
  Alcotest.test_case "form_of_attrs"                  `Quick test_form_of_attrs;
  Alcotest.test_case "collect qualifies nested names" `Quick test_collect_qualifies_nested;
  Alcotest.test_case "bad payload is a parse error"   `Quick test_bad_payload_is_parse_error;
  Alcotest.test_case "no_alloc on actor is rejected"  `Quick test_no_alloc_on_actor_is_parse_error;
]

(* ── Task 5: classifier + transitive set on hand-built TIR ─────────────── *)
module T = March_tir.Tir
let v n ty = { T.v_name = n; v_ty = ty; v_lin = T.Unr }
let fn name body = { T.fn_name = name; fn_params = []; fn_ret_ty = T.TInt;
                     fn_body = body; fn_kind = T.FnNormal }
let modl fns = { T.tm_name = "M"; tm_fns = fns;
                 tm_types = [T.TDVariant ("Box", [("Box", [T.TInt])])];
                 tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] }
let call f = T.EApp (v f T.TInt, [])
let lit n = T.ALit (March_ast.Ast.LitInt n)
let decl ?form n = { AC.d_name = n; d_form = form;
                     d_name_span = March_ast.Ast.dummy_span;
                     d_decl_span = March_ast.Ast.dummy_span }

let test_builtin_table_total_and_conservative () =
  Alcotest.(check bool) "+ does not allocate" false (AC.builtin_allocates "+");
  Alcotest.(check bool) "++ allocates" true (AC.builtin_allocates "++");
  Alcotest.(check bool) "int_to_string allocates" true (AC.builtin_allocates "int_to_string");
  Alcotest.(check bool) "specialized name is stripped" false (AC.builtin_allocates "+$Int");
  Alcotest.(check bool) "unknown name allocates" true
    (AC.builtin_allocates "totally_unknown_builtin");
  List.iter (fun c -> ignore (AC.builtin_allocates (March_tir.Builtin_name.to_string c)))
    March_tir.Builtin_name.all

let test_fixpoint_transitive () =
  let m = modl [ fn "g" (T.EAlloc (T.TCon ("Box", []), [lit 1]));
                 fn "f" (call "g");
                 fn "h" (T.EAtom (lit 0)) ] in
  let set = AC.allocating_fns ~decls:[] m in
  Alcotest.(check bool) "g direct" true (Hashtbl.mem set "g");
  (match Hashtbl.find_opt set "f" with
   | Some (AC.Callee ("g", AC.Ctor "Box")) -> ()
   | _ -> Alcotest.fail "f should be Callee(g, Ctor Box)");
  Alcotest.(check bool) "h clean" false (Hashtbl.mem set "h")

let test_assume_removes_and_unseeds () =
  let m = modl [ fn "wrap" (T.ECallPtr (T.AVar (v "cb" (T.TPtr T.TUnit)), []));
                 fn "user" (call "wrap") ] in
  let set = AC.allocating_fns ~decls:[decl ~form:AC.Assume "wrap"] m in
  Alcotest.(check bool) "assume is clean" false (Hashtbl.mem set "wrap");
  Alcotest.(check bool) "caller of assume is clean" false (Hashtbl.mem set "user");
  let set2 = AC.allocating_fns ~decls:[] m in
  (match Hashtbl.find_opt set2 "wrap" with
   | Some (AC.UnknownClosure "cb") -> ()
   | _ -> Alcotest.fail "ECallPtr without assume must fail")

let test_reuse_and_stack_pass_float_box_fails () =
  let x = v "x" T.TInt in
  let reuse = T.EReuse (T.AVar (v "o" (T.TCon ("Box", []))), T.TCon ("Box", []), [T.AVar x]) in
  let stack = T.EStackAlloc (T.TCon ("Box", []), [T.AVar x]) in
  let m = modl [ fn "r" reuse; fn "s" stack ] in
  let set = AC.allocating_fns ~decls:[] m in
  Alcotest.(check bool) "reuse clean" false (Hashtbl.mem set "r");
  Alcotest.(check bool) "stack clean" false (Hashtbl.mem set "s");
  (* A Float stored into an erased (TVar) payload is boxed even under reuse. *)
  let m2 = { (modl [ fn "fb" (T.EReuse (T.AVar (v "o" (T.TCon ("Some", []))),
                                        T.TCon ("Some", []),
                                        [T.AVar (v "f" T.TFloat)])) ])
             with T.tm_types = [T.TDVariant ("Option", [("None", []); ("Some", [T.TVar "a"])])] } in
  (match Hashtbl.find_opt (AC.allocating_fns ~decls:[] m2) "fb" with
   | Some AC.FloatBox -> ()
   | _ -> Alcotest.fail "Float into TVar payload must be FloatBox")

let test_spec_clone_resolves_to_decl () =
  let m = modl [ fn "wrap$Int" (T.ECallPtr (T.AVar (v "cb" (T.TPtr T.TUnit)), [])) ] in
  let set = AC.allocating_fns ~decls:[decl ~form:AC.Assume "wrap"] m in
  Alcotest.(check bool) "clone inherits assume" false (Hashtbl.mem set "wrap$Int")

let tests = tests @ [
  Alcotest.test_case "builtin table total and conservative" `Quick test_builtin_table_total_and_conservative;
  Alcotest.test_case "fixpoint is transitive"                `Quick test_fixpoint_transitive;
  Alcotest.test_case "assume removes and unseeds"            `Quick test_assume_removes_and_unseeds;
  Alcotest.test_case "reuse/stack pass, float box fails"     `Quick test_reuse_and_stack_pass_float_box_fails;
  Alcotest.test_case "spec clone resolves to decl"           `Quick test_spec_clone_resolves_to_decl;
]

(* ── Task 6: end-to-end through `march --compile` ─────────────────────── *)
let compile ?(flags = "") src = Test_cap_ceiling.compile_with ~flags src

(* Keeps the binary, runs it, and also runs the interpreter: compiled parity. *)
let compile_and_run ?(flags = "") src =
  let exe = Test_cap_ceiling.compiler_exe in
  let f = Filename.temp_file "noalloc" ".march" in
  let oc = open_out f in
  output_string oc src;
  close_out oc;
  let bin = Filename.temp_file "noalloc" ".bin" in
  let log = Filename.temp_file "noalloc" ".log" in
  let read p =
    let ic = open_in p in
    let s = really_input_string ic (in_channel_length ic) in
    close_in ic; s
  in
  let rc = Sys.command (Printf.sprintf "%s %s --compile -o %s %s > %s 2>&1"
                          (Filename.quote exe) flags (Filename.quote bin)
                          (Filename.quote f) (Filename.quote log)) in
  let compile_out = read log in
  let run_out =
    if rc = 0 then begin
      ignore (Sys.command (Printf.sprintf "%s > %s 2>&1" (Filename.quote bin) (Filename.quote log)));
      read log
    end else "" in
  ignore (Sys.command (Printf.sprintf "%s %s > %s 2>&1"
                         (Filename.quote exe) (Filename.quote f) (Filename.quote log)));
  let interp_out = read log in
  List.iter (fun p -> try Sys.remove p with _ -> ()) [f; bin; log];
  (rc, compile_out, run_out, interp_out)

let accepts name ?(flags = "") src expected_stdout =
  let (rc, out, run_out, interp_out) = compile_and_run ~flags src in
  if rc <> 0 then Alcotest.failf "%s: expected accept, got rc=%d:\n%s" name rc out;
  Alcotest.(check string) (name ^ ": compiled output") expected_stdout run_out;
  Alcotest.(check string) (name ^ ": interpreter parity") expected_stdout interp_out;
  Alcotest.(check bool) (name ^ ": no contract diagnostic") false (contains "no_alloc" out)

let rejects name ?(flags = "") src needle =
  let (rc, out) = compile ~flags src in
  if rc = 0 then Alcotest.failf "%s: expected reject, compiled fine" name;
  if not (contains needle out) then Alcotest.failf "%s: missing %S in:\n%s" name needle out

let live_src = {|mod Main do
needs IO
ptype Box = Box(Int, Int)
fn first(b : Box) : Int do
  match b do
    Box(x, _) -> x
  end
end
@[no_alloc]
fn bump_copied(b : Box) : Int do
  match b do
    Box(x, y) ->
      let updated = Box(x + 1, y)
      let old_x = first(b)
      first(updated) + old_x
  end
end
fn main(cap : Cap(IO)) : Unit do println(int_to_string(bump_copied(Box(1, 2)))) end
end|}

let test_reject_live_scrutinee () =
  rejects "live scrutinee" live_src "`bump_copied` is marked @[no_alloc] but allocates";
  rejects "names ctor" live_src "constructor `Box` is allocated here"

(* The callee must survive inlining or the allocation is honestly DIRECT, not
   transitive (the inliner folds a one-liner into its caller); a recursive
   callee is not inlined.  The callee's FIRST allocation in evaluation order
   is the one named. *)
let trans_src = {|mod Main do
needs IO
fn format_row(xs : List(String)) : String do
  match xs do
    Nil -> ""
    Cons(h, t) -> h ++ format_row(t)
  end
end
@[no_alloc]
fn render(xs : List(String)) : String do format_row(xs) end
fn main(cap : Cap(IO)) : Unit do println(render(["a", "b"])) end
end|}

let test_reject_transitive_names_callee () =
  rejects "transitive" trans_src
    "`render` calls `format_row`, which allocates (in `format_row`: string concatenation)"

let concat_src = {|mod Main do
needs IO
@[no_alloc]
fn greet(s : String) : String do "hi " ++ s end
fn main(cap : Cap(IO)) : Unit do println(greet("x")) end
end|}

let test_reject_string_concat () = rejects "concat" concat_src "string concatenation"

let callptr_src = {|mod Main do
needs IO
@[no_alloc]
fn process(f : Int -> Int, x : Int) : Int do f(x) end
fn main(cap : Cap(IO)) : Unit do println(int_to_string(process(fn y -> y, 1))) end
end|}

let test_reject_callptr_without_assume () =
  rejects "callptr" callptr_src
    "`process` is marked @[no_alloc] but calls through an unknown closure";
  rejects "callptr hint" callptr_src "mark `process` @[no_alloc(assume)]"

let replace_first s ~sub ~by =
  let n = String.length s and k = String.length sub in
  let rec go i = if i + k > n then s
    else if String.sub s i k = sub then String.sub s 0 i ^ by ^ String.sub s (i + k) (n - i - k)
    else go (i + 1) in
  go 0

let warn_src = replace_first live_src ~sub:"@[no_alloc]" ~by:"@[no_alloc(warn)]"

let test_warn_form_exit_zero () =
  let (rc, out) = compile warn_src in
  Alcotest.(check int) "rc 0" 0 rc;
  Alcotest.(check bool) "warning printed" true
    (contains "-- WARNING --" out && contains "is marked @[no_alloc] but allocates" out)

let test_no_opt_downgrades () =
  let (rc, out) = compile ~flags:"--no-opt" live_src in
  Alcotest.(check int) "rc 0 under --no-opt" 0 rc;
  Alcotest.(check bool) "names the flag" true
    (contains "(TIR optimisation was skipped by --no-opt; the normal build may pass.)" out)

let test_opt_level_does_not_change_verdict () =
  let (rc0, _) = compile ~flags:"--opt 0" live_src in
  let (rc2, _) = compile ~flags:"--opt 2" live_src in
  Alcotest.(check bool) "both reject" true (rc0 <> 0 && rc2 <> 0)

let test_interpreter_ignores_attribute () =
  let (_, _, _, interp_out) = compile_and_run live_src in
  Alcotest.(check string) "interpreted runs" "3\n" interp_out

let test_check_ignores_attribute () =
  let exe = Test_cap_ceiling.compiler_exe in
  let f = Filename.temp_file "noalloc" ".march" in
  let oc = open_out f in output_string oc live_src; close_out oc;
  let log = Filename.temp_file "noalloc" ".log" in
  let rc = Sys.command (Printf.sprintf "%s --check %s > %s 2>&1"
                          (Filename.quote exe) (Filename.quote f) (Filename.quote log)) in
  let ic = open_in log in
  let out = really_input_string ic (in_channel_length ic) in
  close_in ic;
  List.iter (fun p -> try Sys.remove p with _ -> ()) [f; log];
  Alcotest.(check int) "--check rc" 0 rc;
  Alcotest.(check bool) "silent" false (contains "no_alloc" out)

let e2e_tests = [
  Alcotest.test_case "reject: live scrutinee ctor"          `Quick test_reject_live_scrutinee;
  Alcotest.test_case "reject: transitive names callee"      `Quick test_reject_transitive_names_callee;
  Alcotest.test_case "reject: string concatenation"         `Quick test_reject_string_concat;
  Alcotest.test_case "reject: ECallPtr without assume"      `Quick test_reject_callptr_without_assume;
  Alcotest.test_case "warn form exits 0"                    `Quick test_warn_form_exit_zero;
  Alcotest.test_case "--no-opt downgrades to a warning"     `Quick test_no_opt_downgrades;
  Alcotest.test_case "--opt N does not change the verdict"  `Quick test_opt_level_does_not_change_verdict;
  Alcotest.test_case "interpreter ignores the attribute"    `Quick test_interpreter_ignores_attribute;
  Alcotest.test_case "--check ignores the attribute"        `Quick test_check_ignores_attribute;
]
let tests = tests @ e2e_tests
