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
  (* stdout ONLY for the two runs: the interpreter also prints unrelated
     diagnostics (e.g. the tail-recursion warning) on stderr, and folding
     those into the comparison would make parity depend on warning text. *)
  let run_out =
    if rc = 0 then begin
      ignore (Sys.command (Printf.sprintf "%s > %s 2>/dev/null" (Filename.quote bin) (Filename.quote log)));
      read log
    end else "" in
  ignore (Sys.command (Printf.sprintf "%s %s > %s 2>/dev/null"
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
ptype Box = Box(Int, String)
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
fn main(cap : Cap(IO)) : Unit do println(int_to_string(bump_copied(Box(1, "two")))) end
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

(* Accept cases.  Each also runs the binary and compares with the
   interpreter (compiled-parity convention).  The TIR shape each one relies
   on was confirmed by hand with MARCH_DUMP_TXT=tir-native-map-inline:
   `reuse` for the tree/accumulator/assume cases, `reuse_hole` for the TRMC
   case under --trmc, and no bare `alloc` in the annotated function. *)
let tree_src = {|mod Main do
needs IO
ptype Tree = Leaf(Int) | Node(Tree, Tree)
@[no_alloc]
fn inc_leaves(t : Tree) : Tree do
  match t do
    Leaf(n) -> Leaf(n + 1)
    Node(l, r) -> Node(inc_leaves(l), inc_leaves(r))
  end
end
fn sum(t : Tree) : Int do
  match t do
    Leaf(n) -> n
    Node(l, r) -> sum(l) + sum(r)
  end
end
fn main(cap : Cap(IO)) : Unit do
  println(int_to_string(sum(inc_leaves(Node(Leaf(1), Leaf(2))))))
end
end|}

let test_accept_fbip_tree () = accepts "fbip tree" tree_src "5\n"

let acc_src = {|mod Main do
needs IO
@[no_alloc]
fn rev_inc(xs : List(Int), acc : List(Int)) : List(Int) do
  match xs do
    Nil -> acc
    Cons(h, t) -> rev_inc(t, Cons(h + 1, acc))
  end
end
fn main(cap : Cap(IO)) : Unit do
  println(int_to_string(List.sum_int(rev_inc([1, 2, 3], Nil))))
end
end|}

let test_accept_accumulator_reuse () = accepts "accumulator" acc_src "9\n"

(* The base case returns the matched `xs` rather than a fresh `Nil`: a nullary
   constructor of a MIXED variant (unlike an all-nullary enum or a niche
   Option) is a real 16-byte heap cell in today's codegen, so building one
   would be a genuine allocation. *)
let trmc_src = {|mod Main do
needs IO
@[no_alloc]
fn inc_all(xs : List(Int)) : List(Int) do
  match xs do
    Nil -> xs
    Cons(h, t) -> Cons(h + 1, inc_all(t))
  end
end
fn main(cap : Cap(IO)) : Unit do
  println(int_to_string(List.sum_int(inc_all([1, 2, 3]))))
end
end|}

let test_accept_trmc_with_flag () = accepts "trmc" ~flags:"--trmc" trmc_src "9\n"

let test_trmc_hint_absent_when_on () =
  let (rc, out) = compile ~flags:"--trmc" trmc_src in
  Alcotest.(check int) "rc" 0 rc;
  Alcotest.(check bool) "no hint" false (contains "TRMC-eligible" out)

let scalar_src = {|mod Main do
needs IO
type Mode = Fast | Slow
ptype P = P(Int, Int)
@[no_alloc]
fn score(m : Mode, p : P) : Int do
  match p do
    P(x, y) -> match m do
      Fast -> x * 2 + y
      Slow -> x + y
    end
  end
end
fn main(cap : Cap(IO)) : Unit do println(int_to_string(score(Fast, P(3, 4)))) end
end|}

let test_accept_scalars_and_nullary_ctors () = accepts "scalars" scalar_src "10\n"

let assume_src = {|mod Main do
needs IO
@[no_alloc(assume)]
fn apply_twice(f : Int -> Int, x : Int) : Int do f(f(x)) end
@[no_alloc]
fn use_it(x : Int) : Int do apply_twice(fn y -> y + 1, x) end
fn main(cap : Cap(IO)) : Unit do println(int_to_string(use_it(1))) end
end|}

let test_accept_assume_and_its_caller () = accepts "assume" assume_src "3\n"

let intbox_src = {|mod Main do
needs IO
@[no_alloc]
fn bump(o : Option(Int)) : Option(Int) do
  match o do
    Some(x) -> Some(x + 1)
    None -> None
  end
end
fn main(cap : Cap(IO)) : Unit do
  match bump(Some(2)) do
    Some(v) -> println(int_to_string(v))
    None -> println("none")
  end
end
end|}

let test_accept_int_option () = accepts "int option" intbox_src "3\n"

(* The Float sibling of [intbox_src]: identical shape, so the only thing that
   can change the verdict is the Float crossing an erased (TVar) payload. *)
let floatbox_src = {|mod Main do
needs IO
@[no_alloc]
fn bump(o : Option(Float)) : Option(Float) do
  match o do
    Some(x) -> Some(x +. 1.0)
    None -> None
  end
end
fn main(cap : Cap(IO)) : Unit do
  match bump(Some(1.5)) do
    Some(v) -> println(float_to_string(v))
    None -> println("none")
  end
end
end|}

let test_reject_float_box () = rejects "float box" floatbox_src "a Float is boxed here"

(* ── Unboxed small scalar aggregates (Repr.Unboxed) ───────────────────────

   The motivating case for the representation: `forward` builds a Vec3 from
   three scalars, so there is no dying cell for FBIP to reuse and no caller
   whose frame it could be promoted into — under the boxed representation it
   is an unconditional march_alloc(40) and the contract cannot hold.  As an
   inline aggregate it is three doubles in registers and the contract does
   hold, transitively through a caller that only reads it back. *)
let unboxed_agg_src = {|mod Main do
needs IO
type Vec3 = Vec3(Float, Float, Float)
@[no_alloc]
fn forward(yaw : Float, pitch : Float) : Vec3 do
  let cp = Math.cos(pitch)
  Vec3(0.0 -. Math.sin(yaw) *. cp, Math.sin(pitch), 0.0 -. Math.cos(yaw) *. cp)
end
@[no_alloc]
fn dot(a : Vec3, b : Vec3) : Float do
  match a do
    Vec3(ax, ay, az) ->
      match b do
        Vec3(bx, b2, bz) -> ax *. bx +. ay *. b2 +. az *. bz
      end
  end
end
@[no_alloc]
fn energy(yaw : Float) : Float do
  let v = forward(yaw, 0.25)
  dot(v, v)
end
fn main(cap : Cap(IO)) : Unit do println(int_to_string(float_round(energy(0.0) *. 1000.0))) end
end|}

let test_accept_unboxed_aggregate () =
  accepts "unboxed aggregate" unboxed_agg_src "1000\n"

(* The RED control, and the exact diagnostic the representation removes.
   MARCH_NO_UNBOX=1 restores the pre-Milestone-3 representation, so the same
   program must fail with the boxed verdict — without this the accept above
   could pass for any reason at all.

   The source carries a distinguishing comment: the content-addressed artifact
   cache keys on source + compiler, and the accept run just compiled the same
   text, so an identical string would be answered from the cache and the
   control would be vacuous. *)
let unboxed_agg_boxed_src =
  "-- RED control: compiled with MARCH_NO_UNBOX=1\n" ^ unboxed_agg_src

let compile_env ~env src =
  let exe = Test_cap_ceiling.compiler_exe in
  let f = Filename.temp_file "noalloc_env" ".march" in
  let oc = open_out f in output_string oc src; close_out oc;
  let bin = Filename.temp_file "noalloc_env" ".bin" in
  let log = Filename.temp_file "noalloc_env" ".log" in
  let rc = Sys.command (Printf.sprintf "%s %s --compile -o %s %s > %s 2>&1"
                          env (Filename.quote exe) (Filename.quote bin)
                          (Filename.quote f) (Filename.quote log)) in
  let ic = open_in log in
  let out = really_input_string ic (in_channel_length ic) in
  close_in ic;
  List.iter (fun p -> try Sys.remove p with _ -> ()) [f; bin; log];
  (rc, out)

let test_reject_unboxed_aggregate_when_boxed () =
  let (rc, out) = compile_env ~env:"MARCH_NO_UNBOX=1" unboxed_agg_boxed_src in
  if rc = 0 then
    Alcotest.failf
      "RED control: with the boxed representation `forward` must fail its \
       contract, but the compile succeeded:\n%s" out;
  if not (contains "constructor `Vec3` is allocated here" out) then
    Alcotest.failf "RED control: missing the boxed verdict in:\n%s" out

let accept_tests = [
  Alcotest.test_case "accept: unboxed scalar aggregate"   `Quick test_accept_unboxed_aggregate;
  Alcotest.test_case "RED control: boxed Vec3 is rejected" `Quick test_reject_unboxed_aggregate_when_boxed;
  Alcotest.test_case "accept: FBIP tree transform"        `Quick test_accept_fbip_tree;
  Alcotest.test_case "accept: accumulator reuses Cons"    `Quick test_accept_accumulator_reuse;
  Alcotest.test_case "accept: TRMC producer with --trmc"  `Quick test_accept_trmc_with_flag;
  Alcotest.test_case "TRMC hint absent when --trmc is on" `Quick test_trmc_hint_absent_when_on;
  Alcotest.test_case "accept: scalars and nullary ctors"  `Quick test_accept_scalars_and_nullary_ctors;
  Alcotest.test_case "accept: assume and its caller"      `Quick test_accept_assume_and_its_caller;
  Alcotest.test_case "accept: Option(Int) reuse"          `Quick test_accept_int_option;
  Alcotest.test_case "reject: boxed Float in Option"      `Quick test_reject_float_box;
]
let tests = tests @ accept_tests

(* ── Task 7: Tagged(_, NoAlloc) / Realtime policies use the same check ─── *)

(* `Tagged(X, T)` is a phantom TYPE with no value constructor, so a
   policy-tagged function is never called; it must still be checked, which
   means the pipeline has to keep it alive past DCE. *)
let policy_reuse_src = {|mod Main do
needs IO
type DSP = DSP
type NoAlloc = NoAlloc
ptype Box = Box(Int, String)
fn bump(_tag : Tagged(DSP, NoAlloc), b : Box) : Box do
  match b do
    Box(x, y) -> Box(x + 1, y)
  end
end
fn main(cap : Cap(IO)) : Unit do println("ok") end
end|}

let test_policy_accepts_reused_ctor () =
  let (rc, out) = compile policy_reuse_src in
  if rc <> 0 then
    Alcotest.failf "NoAlloc policy should accept a reused constructor:\n%s" out

let policy_alloc_src = {|mod Main do
needs IO
type DSP = DSP
type NoAlloc = NoAlloc
ptype Box = Box(Int, String)
fn first(b : Box) : Int do
  match b do
    Box(x, _) -> x
  end
end
fn bump(_tag : Tagged(DSP, NoAlloc), b : Box) : Int do
  match b do
    Box(x, y) ->
      let updated = Box(x + 1, y)
      let old_x = first(b)
      first(updated) + old_x
  end
end
fn main(cap : Cap(IO)) : Unit do println("ok") end
end|}

let test_policy_still_rejects_plain_alloc () =
  rejects "policy alloc" policy_alloc_src
    "`bump` is specialized to a NoAlloc policy but allocates"

let policy_tests = [
  Alcotest.test_case "NoAlloc policy accepts a reused ctor"  `Quick test_policy_accepts_reused_ctor;
  Alcotest.test_case "NoAlloc policy rejects a real alloc"   `Quick test_policy_still_rejects_plain_alloc;
]
let tests = tests @ policy_tests

(* ── Task 9: --report-contracts (the forge fix --contracts input) ─────── *)

(* `bump` reuses its Box in place (default scope); `add` is verified clean but
   has nothing to protect, so it is out of scope unless a glob names it. *)
let report_src = {|mod Main do
needs IO
ptype Box = Box(Int, String)
fn bump(b : Box) : Box do
  match b do
    Box(x, y) -> Box(x + 1, y)
  end
end
fn add(a : Int, b : Int) : Int do a + b end
fn main(cap : Cap(IO)) : Unit do
  match bump(Box(1, "two")) do
    Box(x, _) -> println(int_to_string(x + add(1, 2)))
  end
end
end|}

let insert_lines out =
  List.filter (fun l -> contains "\"kind\":\"insert\"" l)
    (String.split_on_char '\n' out)

(* --report-contracts writes its NDJSON to stdout; compile_with captures both
   streams, which is what we want here. *)
let test_report_contracts_emits_one_insert () =
  let (rc, out) = compile ~flags:"--report-contracts" report_src in
  Alcotest.(check int) "rc 0" 0 rc;
  let lines = insert_lines out in
  Alcotest.(check int) "exactly one in-scope function" 1 (List.length lines);
  let l = List.hd lines in
  Alcotest.(check bool) "names bump" true (contains "`bump`" l);
  Alcotest.(check bool) "inserts the hard form" true (contains "@[no_alloc]" l);
  Alcotest.(check bool) "on the line before the declaration" true
    (contains "\"after_line\":3" l)

let test_report_contracts_glob_widens_scope () =
  let (_, out) = compile ~flags:"--report-contracts --contract-scope add" report_src in
  Alcotest.(check bool) "add is now in scope" true
    (List.exists (fun l -> contains "`add`" l) (insert_lines out))

let test_report_contracts_skips_annotated () =
  let annotated = replace_first report_src ~sub:"fn bump" ~by:"@[no_alloc]\nfn bump" in
  let (_, out) = compile ~flags:"--report-contracts" annotated in
  Alcotest.(check int) "nothing to insert" 0 (List.length (insert_lines out))

let test_report_contracts_skips_allocating () =
  let (_, out) = compile ~flags:"--report-contracts" live_src in
  Alcotest.(check bool) "bump_copied allocates, so no fix" false
    (List.exists (fun l -> contains "`bump_copied`" l) (insert_lines out))

let report_tests = [
  Alcotest.test_case "--report-contracts emits one insert" `Quick test_report_contracts_emits_one_insert;
  Alcotest.test_case "--contract-scope glob widens scope"  `Quick test_report_contracts_glob_widens_scope;
  Alcotest.test_case "already-annotated functions skipped" `Quick test_report_contracts_skips_annotated;
  Alcotest.test_case "allocating functions skipped"        `Quick test_report_contracts_skips_allocating;
]
let tests = tests @ report_tests
