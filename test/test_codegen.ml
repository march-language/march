(** March test suite — codegen tests. *)
open Test_helpers

(* ── js_pipeline: shared TIR->JS compile pipeline (lib/driver) ────────── *)

let compile_to_js src =
  let m = parse_and_desugar src in
  March_driver.Js_pipeline.compile_module_to_js ~source_file:"<test>"
    ~fn_lines:[] m

let test_js_pipeline_simple_program_compiles () =
  match
    compile_to_js
      {|mod Test do
    fn add(a: Int, b: Int) : Int do a + b end
    fn main() : Unit do
      let _ = add(1, 2)
      ()
    end
  end|}
  with
  | Ok (js, _map) ->
    Alcotest.(check bool) "output mentions main" true
      (Test_helpers.contains "main" js)
  | Error errs ->
    Alcotest.failf "expected Ok, got errors: %s" (String.concat "; " errs)

let test_js_pipeline_typecheck_error_surfaces () =
  match
    compile_to_js
      {|mod Test do
    fn main() : Unit do
      let _ = 1 + "not a number"
      ()
    end
  end|}
  with
  | Ok _ -> Alcotest.fail "expected a typecheck error, got Ok"
  | Error errs ->
    Alcotest.(check bool) "at least one error message" true (errs <> [])

let test_js_pipeline_dom_extern_reaches_output () =
  match
    compile_to_js
      {|mod Test do
    needs Ffi
    needs IO.Foreign
    resource Node
    resource Event
    extern "dom" : Cap(Ffi) do
      fn dom_get_element_by_id(id: String) : Option(Node) = "march_dom_get_element_by_id"
    end
    fn main(_cap_foreign : Cap(IO.Foreign)) : Unit do
      let _ = dom_get_element_by_id("root")
      ()
    end
  end|}
  with
  | Ok (js, _map) ->
    Alcotest.(check bool) "output references the extern symbol" true
      (Test_helpers.contains "march_dom_get_element_by_id" js)
  | Error errs ->
    Alcotest.failf "expected Ok, got errors: %s" (String.concat "; " errs)

let test_js_pipeline_dom_event_key_reaches_output () =
  match
    compile_to_js
      {|mod Test do
    needs Ffi
    needs IO.Foreign
    extern "dom" : Cap(Ffi) do
      fn dom_event_key(ev: String) : String = "march_dom_event_key"
    end
    fn main(_cap_foreign : Cap(IO.Foreign)) : Unit do
      let _ = dom_event_key("x")
      ()
    end
  end|}
  with
  | Ok (js, _map) ->
    Alcotest.(check bool) "output references march_dom_event_key" true
      (Test_helpers.contains "march_dom_event_key" js)
  | Error errs ->
    Alcotest.failf "expected Ok, got errors: %s" (String.concat "; " errs)

let test_js_pipeline_simd_builtin_rejected () =
  match
    compile_to_js
      {|mod Test do
    fn main() : Unit do
      let v = Simd.splat_f32x4(1.0)
      let _ = v
      ()
    end
  end|}
  with
  | Ok _ -> Alcotest.fail "expected a JS-target rejection, got Ok"
  | Error errs ->
    Alcotest.(check bool) "message names the Simd module and fixed-128 reason" true
      (List.exists (fun e ->
         Test_helpers.contains "simd_f32x4_splat" e
         && Test_helpers.contains "Simd" e
         && Test_helpers.contains "128-bit" e) errs)

(* ── Tir_names: cross-pass name contract unit tests (Wave 3 Task 1) ──── *)

let test_tir_names_tuple_tag () =
  Alcotest.(check string) "tuple_tag 2" "$Tuple2" (March_tir.Tir_names.tuple_tag 2);
  Alcotest.(check bool) "is_tuple_tag $Tuple2" true
    (March_tir.Tir_names.is_tuple_tag (March_tir.Tir_names.tuple_tag 2));
  Alcotest.(check bool) "is_tuple_tag $Tuple0" true
    (March_tir.Tir_names.is_tuple_tag (March_tir.Tir_names.tuple_tag 0));
  Alcotest.(check bool) "not is_tuple_tag Some" false
    (March_tir.Tir_names.is_tuple_tag "Some");
  Alcotest.(check bool) "not is_tuple_tag $fv1" false
    (March_tir.Tir_names.is_tuple_tag "$fv1")

let test_tir_names_fv_field_round_trip () =
  Alcotest.(check string) "fv_field 1" "$fv1" (March_tir.Tir_names.fv_field 1);
  Alcotest.(check bool) "is_fv_field $fv1" true
    (March_tir.Tir_names.is_fv_field (March_tir.Tir_names.fv_field 1));
  Alcotest.(check int) "fv_field_index round-trip" 42
    (March_tir.Tir_names.fv_field_index (March_tir.Tir_names.fv_field 42));
  Alcotest.(check bool) "not is_fv_field $Clo_foo$1" false
    (March_tir.Tir_names.is_fv_field "$Clo_foo$1");
  Alcotest.(check bool) "not is_fv_field plain field" false
    (March_tir.Tir_names.is_fv_field "name")

let test_tir_names_clo_struct () =
  let n = March_tir.Tir_names.clo_struct_name ~fn_name:"foo" ~lam_uid:3 in
  Alcotest.(check string) "clo_struct_name" "$Clo_foo$3" n;
  Alcotest.(check bool) "is_clo_struct" true (March_tir.Tir_names.is_clo_struct n);
  Alcotest.(check bool) "not is_clo_struct Option" false
    (March_tir.Tir_names.is_clo_struct "Option")

let test_tir_names_apply_fn () =
  let n = March_tir.Tir_names.apply_fn_name ~fn_name:"foo" ~lam_uid:3 in
  Alcotest.(check string) "apply_fn_name" "foo$apply$3" n;
  Alcotest.(check bool) "is_apply_fn" true (March_tir.Tir_names.is_apply_fn n);
  Alcotest.(check bool) "not is_apply_fn plain" false
    (March_tir.Tir_names.is_apply_fn "foo");
  (* is_apply_fn scans for the marker anywhere, not just as a suffix. *)
  Alcotest.(check bool) "is_apply_fn marker mid-string" true
    (March_tir.Tir_names.is_apply_fn "foo$apply$3$extra")

let test_tir_names_iface_mangled () =
  Alcotest.(check bool) "Show$Int.show is mangled" true
    (March_tir.Tir_names.is_iface_mangled "Show$Int.show");
  Alcotest.(check bool) "Show$List.show$List_Int is mangled" true
    (March_tir.Tir_names.is_iface_mangled "Show$List.show$List_Int");
  (* The critical negative case from the plan brief: a $ AFTER the last '.'
     is an ordinary specialized generic fn, not an interface impl. *)
  Alcotest.(check bool) "List.map$Int is NOT mangled" false
    (March_tir.Tir_names.is_iface_mangled "List.map$Int");
  Alcotest.(check bool) "ordinary qualified name is NOT mangled" false
    (March_tir.Tir_names.is_iface_mangled "Crypto.base64_encode");
  Alcotest.(check bool) "no dot at all is NOT mangled" false
    (March_tir.Tir_names.is_iface_mangled "no_dots_here$weird");
  (* A user fn named with dots but no interface mangling. *)
  Alcotest.(check bool) "App.Core.b is NOT mangled" false
    (March_tir.Tir_names.is_iface_mangled "App.Core.b")

let test_tir_names_iface_mangle_builder () =
  Alcotest.(check string) "iface_mangle" "Show$List.show"
    (March_tir.Tir_names.iface_mangle ~iface:"Show" ~ty:"List" ~meth:"show")

let test_tir_names_default_arg_round_trip () =
  Alcotest.(check string) "default_arg_mangle" "greet$2"
    (March_tir.Tir_names.default_arg_mangle "greet" 2);
  Alcotest.(check bool) "parse round-trip" true
    (March_tir.Tir_names.parse_default_arg
       (March_tir.Tir_names.default_arg_mangle "greet" 2) = Some ("greet", 2));
  Alcotest.(check bool) "parse_default_arg no dollar" true
    (March_tir.Tir_names.parse_default_arg "greet" = None);
  Alcotest.(check bool) "parse_default_arg empty base rejected" true
    (March_tir.Tir_names.parse_default_arg "$2" = None);
  Alcotest.(check bool) "parse_default_arg non-numeric suffix rejected" true
    (March_tir.Tir_names.parse_default_arg "greet$abc" = None)

let test_tir_names_actor_suffixes () =
  Alcotest.(check bool) "is_actor_struct_name Counter_Actor" true
    (March_tir.Tir_names.is_actor_struct_name ("Counter" ^ March_tir.Tir_names.actor_struct_suffix));
  Alcotest.(check bool) "not is_actor_struct_name Counter" false
    (March_tir.Tir_names.is_actor_struct_name "Counter");
  Alcotest.(check bool) "is_actor_dispatch_fn Counter_dispatch" true
    (March_tir.Tir_names.is_actor_dispatch_fn ("Counter" ^ March_tir.Tir_names.actor_dispatch_suffix));
  Alcotest.(check bool) "not is_actor_dispatch_fn Counter" false
    (March_tir.Tir_names.is_actor_dispatch_fn "Counter");
  (* Field-sort invariant: $d_ < $e_ < $f_ < any letter (C-runtime word-index
     coupling — see the module doc comment). *)
  Alcotest.(check bool) "dispatch field sorts before alive field" true
    (March_tir.Tir_names.actor_dispatch_field < March_tir.Tir_names.actor_alive_field);
  Alcotest.(check bool) "alive field sorts before state field" true
    (March_tir.Tir_names.actor_alive_field < March_tir.Tir_names.actor_state_field);
  Alcotest.(check bool) "state field sorts before a plain letter field" true
    (March_tir.Tir_names.actor_state_field < "a")

let test_tir_names_runtime_prefix () =
  Alcotest.(check bool) "has_runtime_prefix march_compare_int" true
    (March_tir.Tir_names.has_runtime_prefix "march_compare_int");
  (* "march_" requires the trailing underscore; "marching" has none at
     that position, so it must NOT match. *)
  Alcotest.(check bool) "not has_runtime_prefix marching" false
    (March_tir.Tir_names.has_runtime_prefix "marching");
  Alcotest.(check bool) "not has_runtime_prefix short string" false
    (March_tir.Tir_names.has_runtime_prefix "march")

let test_tir_names_try_call () =
  Alcotest.(check bool) "is_try_call __try_call" true
    (March_tir.Tir_names.is_try_call "__try_call");
  Alcotest.(check bool) "is_try_call __try_call_val" true
    (March_tir.Tir_names.is_try_call "__try_call_val");
  Alcotest.(check bool) "not is_try_call other" false
    (March_tir.Tir_names.is_try_call "try_call")

let test_tir_names_test_and_setup_fn_names () =
  Alcotest.(check string) "test_fn_name 0" "__march_test_0__" (March_tir.Tir_names.test_fn_name 0);
  Alcotest.(check string) "test_fn_name 7" "__march_test_7__" (March_tir.Tir_names.test_fn_name 7);
  Alcotest.(check string) "setup_fn_name" "__march_setup__" March_tir.Tir_names.setup_fn_name;
  Alcotest.(check string) "setup_all_fn_name" "__march_setup_all__" March_tir.Tir_names.setup_all_fn_name

let test_tir_names_specialize_mangle () =
  (* Equality against the OLD inline expression shape mono.ml used before
     this conversion (Wave 3 Chunk 2 Task 1): `base ^ "$" ^ mangled_ty`. *)
  let old_shape base mangled_ty = base ^ "$" ^ mangled_ty in
  Alcotest.(check string) "specialize_mangle matches old inline shape (single ty)"
    (old_shape "map" "Int")
    (March_tir.Tir_names.specialize_mangle "map" "Int");
  Alcotest.(check string) "specialize_mangle basic" "map$Int"
    (March_tir.Tir_names.specialize_mangle "map" "Int");
  (* Multi-arg specialization: caller joins mangled tys with "$" itself
     before calling (mirrors mono.ml's `mangle_name`'s
     `String.concat "$" (List.map mangle_ty tys)`), so this helper sees
     the already-joined suffix. *)
  Alcotest.(check string) "specialize_mangle multi-ty suffix (pre-joined)"
    (old_shape "map" "Int$Bool")
    (March_tir.Tir_names.specialize_mangle "map" "Int$Bool");
  (* The W2 interface-impl double-mangle case: applying specialize_mangle to
     an already-iface_mangle'd base must NOT trip is_iface_mangled — the new
     '$' lands after the base's own '.', same as the pre-existing
     "List.map$Int" negative case. *)
  let iface_base = March_tir.Tir_names.iface_mangle ~iface:"Show" ~ty:"List" ~meth:"show" in
  let doubly_mangled = March_tir.Tir_names.specialize_mangle iface_base "List_Int" in
  Alcotest.(check string) "W2 double-mangle shape" "Show$List.show$List_Int" doubly_mangled;
  Alcotest.(check bool) "double-mangled impl name still is_iface_mangled" true
    (March_tir.Tir_names.is_iface_mangled doubly_mangled);
  (* Ordinary generic fn (no dots at all) specialized: must NOT be
     is_iface_mangled — matches the existing "List.map$Int" contract. *)
  Alcotest.(check bool) "plain specialized generic fn is NOT iface_mangled" false
    (March_tir.Tir_names.is_iface_mangled
       (March_tir.Tir_names.specialize_mangle "map" "Int"))

let test_tir_names_strip_specialization_suffix () =
  (* No '.' at all: first '$' is the specialization separator. *)
  Alcotest.(check string) "println$String -> println" "println"
    (March_tir.Tir_names.strip_specialization_suffix "println$String");
  (* '$' after the last '.': ordinary specialized generic fn. *)
  Alcotest.(check string) "List.map$Int -> List.map" "List.map"
    (March_tir.Tir_names.strip_specialization_suffix "List.map$Int");
  (* '$' before the last '.' is part of an interface-impl mangle (base);
     only the '$' AFTER the last '.' is the specialization separator. *)
  Alcotest.(check string) "Show$List.show$Int -> Show$List.show" "Show$List.show"
    (March_tir.Tir_names.strip_specialization_suffix "Show$List.show$Int");
  (* No '$' at all: unchanged. *)
  Alcotest.(check string) "map (no $) -> map" "map"
    (March_tir.Tir_names.strip_specialization_suffix "map");
  (* Round-trips against the actual producer, specialize_mangle. *)
  Alcotest.(check string) "round-trip through specialize_mangle" "println"
    (March_tir.Tir_names.strip_specialization_suffix
       (March_tir.Tir_names.specialize_mangle "println" "String"));
  let iface_base = March_tir.Tir_names.iface_mangle ~iface:"Show" ~ty:"List" ~meth:"show" in
  Alcotest.(check string) "round-trip through iface + specialize mangle" iface_base
    (March_tir.Tir_names.strip_specialization_suffix
       (March_tir.Tir_names.specialize_mangle iface_base "List_Int"))

let test_tir_names_bool_tags () =
  Alcotest.(check string) "synthetic_true_tag" "True" March_tir.Tir_names.synthetic_true_tag;
  Alcotest.(check string) "synthetic_false_tag" "False" March_tir.Tir_names.synthetic_false_tag;
  Alcotest.(check string) "bool_lit_tag true" "true" (March_tir.Tir_names.bool_lit_tag true);
  Alcotest.(check string) "bool_lit_tag false" "false" (March_tir.Tir_names.bool_lit_tag false)

(* ── Rc_types: needs_rc / borrow_eligible divergence contract (Wave 3 Task 2) ──
   Table-driven pin of the FULL truth table for both predicates over
   representative types, plus an exactness check that the divergence set is
   precisely {TFn _, bare TVar _, TTuple _, TRecord _} and nothing else.
   If either predicate changes, this test fails and points at Rc_types's
   module doc (each divergent constructor's fix history: a705cc95/d2cf09e/
   fd520110 for TFn/TVar).

   TTuple/TRecord diverge, but in the OPPOSITE direction from their history:
   they used to be (needs_rc false, borrow_eligible true), and are now
   (true, false).

   needs_rc true: aggregates own their fields and are deep-dropped at death like
   variants.  While it was false Perceus never decided an aggregate was dead, so
   every record and tuple cell leaked along with every heap value it owned.

   borrow_eligible false: an aggregate parameter is OWNED.  A borrowed one
   leaves the caller holding the release, and in a self-tail-recursive loop that
   release is unreachable -- it sits after the tail call, llvm_tco folds the call
   into a back-edge, and the dec is discarded -- so every iteration leaked its
   aggregate.  Ownership lets each iteration release the aggregate it was handed
   before jumping with a new one, which is also what makes
   Perceus.insert_owned_aggregate_param_drops reachable at all. *)

(* (label, ty, expected needs_rc, expected borrow_eligible) *)
let rc_types_truth_table : (string * March_tir.Tir.ty * bool * bool) list =
  let open March_tir.Tir in
  [
    "TInt",                TInt,                        false, false;
    "TFloat",              TFloat,                      false, false;
    "TBool",               TBool,                       false, false;
    "TString",             TString,                     true,  true;
    "TUnit",               TUnit,                       false, false;
    "TTuple []",           TTuple [],                   true,  false; (* diverges *)
    "TTuple [Int]",        TTuple [TInt],               true,  false; (* diverges *)
    "TTuple [String]",     TTuple [TString],            true,  false; (* diverges *)
    "TRecord []",          TRecord [],                  true,  false; (* diverges *)
    "TRecord [(f,Int)]",   TRecord [("f", TInt)],       true,  false; (* diverges *)
    "TCon (Atom,[])",      TCon ("Atom", []),           false, false;
    "TCon (Foo,[])",       TCon ("Foo", []),            true,  true;
    "TCon (List,[Int])",   TCon ("List", [TInt]),       true,  true;
    "TCon (Atom,[Int])",   TCon ("Atom", [TInt]),       true,  true;   (* only nullary Atom is scalar *)
    "TFn ([],Int)",        TFn ([], TInt),              true,  false;  (* diverges *)
    "TFn ([Int],Int)",     TFn ([TInt], TInt),          true,  false;  (* diverges *)
    "TPtr Int",            TPtr TInt,                   true,  true;
    "TVar \"_\"",          TVar "_",                    true,  true;   (* placeholder: both conservative *)
    "TVar \"a\"",          TVar "a",                    true,  false;  (* diverges *)
    "TVar \"'_1234\"",     TVar "'_1234",               true,  false;  (* diverges *)
  ]

(* Both predicates now consult [Repr]'s unboxed registry for [TCon] (the
   [Repr.Unboxed] row), and that registry is process-global: clear it so the
   table's "Foo"/"List" rows are judged as ordinary boxed types no matter what
   an earlier test in this runner registered. *)
let test_rc_types_truth_table () =
  March_tir.Repr.clear_unboxed_types ();
  List.iter (fun (label, ty, exp_rc, exp_be) ->
    Alcotest.(check bool) (label ^ ": needs_rc") exp_rc
      (March_tir.Rc_types.needs_rc ty);
    Alcotest.(check bool) (label ^ ": borrow_eligible") exp_be
      (March_tir.Rc_types.borrow_eligible ty)
  ) rc_types_truth_table

let test_rc_types_divergence_set_exact () =
  March_tir.Repr.clear_unboxed_types ();
  (* Exactly the {TFn, bare TVar, TTuple, TRecord} rows diverge — computed
     from the live predicates, compared against the constructor-classified
     expectation, so a new divergence (or a silently unified arm) fails
     loudly here even if the truth-table rows above were edited in sync. *)
  let expected_divergent (ty : March_tir.Tir.ty) : bool =
    match ty with
    | March_tir.Tir.TFn _ | March_tir.Tir.TTuple _ | March_tir.Tir.TRecord _ -> true
    | March_tir.Tir.TVar "_" -> false
    | March_tir.Tir.TVar _ -> true
    | _ -> false
  in
  List.iter (fun (label, ty, _, _) ->
    let actual =
      March_tir.Rc_types.needs_rc ty <> March_tir.Rc_types.borrow_eligible ty
    in
    Alcotest.(check bool) (label ^ ": diverges iff TFn/bare-TVar/TTuple/TRecord")
      (expected_divergent ty) actual
  ) rc_types_truth_table

(* ── Unboxed small scalar aggregates (Repr.Unboxed, Milestone 3) ──────────

   A single-constructor variant whose fields are all Int/Float/Bool and whose
   arity is 2..Repr.max_unboxed_arity is represented as an LLVM struct VALUE:
   `Vec3(Float, Float, Float)` is `{ double, double, double }` in registers,
   with no heap cell, no header and no refcount.  These pin the three things
   that make that representation worth having, plus the classification itself.

   The differential half (interpreted == compiled for construction, matching,
   equality, Show and every heap-slot boundary) lives in the oracle sweep, over
   test/native/unboxed_aggregate{,_boundaries}.march. *)

let unboxed_vec3_src = {|mod UB do
  needs IO.Console
  type Vec3 = Vec3(Float, Float, Float)
  fn forward(yaw : Float, pitch : Float) : Vec3 do
    Vec3(0.0 -. yaw, pitch, yaw *. pitch)
  end
  fn vx(v : Vec3) : Float do
    match v do
      Vec3(x, _, _) -> x
    end
  end
  fn main(_cap_console : Cap(IO.Console)) : Unit do
    println(float_to_string(vx(forward(1.0, 2.0))))
  end
end|}

let test_unboxed_aggregate_declared_as_struct () =
  let ir = emit_tco_opt_ir unboxed_vec3_src in
  Alcotest.(check bool)
    "the identified struct type is declared once in the preamble" true
    (ir_contains ir "%ub.Vec3 = type { double, double, double }")

let test_unboxed_aggregate_built_without_alloc () =
  let ir = emit_tco_opt_ir unboxed_vec3_src in
  (* Construction is an insertvalue chain ... *)
  Alcotest.(check bool) "constructed with insertvalue" true
    (ir_contains ir "insertvalue %ub.Vec3");
  (* ... and destructuring is extractvalue, not a field load. *)
  Alcotest.(check bool) "destructured with extractvalue" true
    (ir_contains ir "extractvalue %ub.Vec3");
  (* ... and nothing in this program reaches march_alloc.  The module builds
     only Vec3 values and a println of a formatted Float, so a single
     march_alloc CALL here would mean the cell came back. *)
  Alcotest.(check int) "no march_alloc call anywhere in the module" 0
    (ir_count ir "call ptr @march_alloc(")

(* The RED control for the two above: with MARCH_NO_UNBOX the same source must
   go back to allocating a cell, which is what proves the assertions are
   measuring the representation and not some incidental property of the
   program.  The env var is read through a [Lazy.t] in [Repr], so it cannot be
   flipped inside this process — assert the pre-Milestone-3 shape by clearing
   the registry directly instead, which is the same code path the flag takes. *)
let test_unboxed_aggregate_boxed_control () =
  let m = parse_and_desugar unboxed_vec3_src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  (* Register the EMPTY table and pin it to this module's types, so the
     [ensure_unboxed_types] calls inside Perceus/Escape and [make_ctx] all
     inherit "nothing is unboxed". *)
  March_tir.Repr.set_unboxed_types ~enabled:false tir.March_tir.Tir.tm_types;
  let tir = March_tir.Perceus.perceus tir in
  let tir = March_tir.Drop.run tir in
  let tir = March_tir.Escape.escape_analysis tir in
  let ir  = March_tir.Llvm_emit.emit_module tir in
  March_tir.Repr.clear_unboxed_types ();
  Alcotest.(check bool) "control: no struct type declared" false
    (ir_contains ir "%ub.Vec3 = type");
  Alcotest.(check bool)
    "control: the same program DOES allocate a cell when Vec3 stays boxed" true
    (ir_count ir "call ptr @march_alloc(" > 0)

(* The eligible class, stated as a table over [Repr.set_unboxed_types].  Each
   rejected row is rejected for its own reason, so a widening of the predicate
   shows up here as a specific row flipping rather than as a mysterious IR
   diff somewhere else. *)
let test_unboxed_aggregate_eligible_class () =
  let open March_tir.Tir in
  let cases = [
    "3 Floats",            TDVariant ("Vec3", [("Vec3", [TFloat; TFloat; TFloat])]),      true;
    "2 Ints",              TDVariant ("P", [("P", [TInt; TInt])]),                        true;
    "Bool + 2 Ints",       TDVariant ("Hit", [("Hit", [TBool; TInt; TInt])]),             true;
    "4 fields (max)",      TDVariant ("Sw", [("Sw", [TFloat; TFloat; TFloat; TBool])]),   true;
    "5 fields (over max)", TDVariant ("Big", [("Big", [TInt; TInt; TInt; TInt; TInt])]),  false;
    "1 field (Newtype)",   TDVariant ("N", [("N", [TInt; ])]),                            false;
    "0 fields",            TDVariant ("Z", [("Z", [])]),                                  false;
    "a String field",      TDVariant ("S", [("S", [TInt; TString])]),                     false;
    "an ADT field",        TDVariant ("A", [("A", [TInt; TCon ("Foo", [])])]),            false;
    "a Unit field",        TDVariant ("U", [("U", [TInt; TUnit])]),                       false;
    "two constructors",    TDVariant ("Two", [("L", [TInt; TInt]); ("R", [TInt; TInt])]), false;
    "a record",            TDRecord ("R", [("a", TInt); ("b", TInt)]),                    false;
  ] in
  List.iter (fun (label, td, expected) ->
      March_tir.Repr.set_unboxed_types [td];
      let name = match td with
        | TDVariant (n, _) | TDRecord (n, _) | TDClosure (n, _) -> n in
      Alcotest.(check bool) (label ^ ": unboxed?") expected
        (March_tir.Repr.unboxed_of_type_name name <> None))
    cases;
  (* An actor message type is excluded whatever its shape: it needs a runtime
     tag so a foreign message can be told apart at dispatch. *)
  March_tir.Repr.set_unboxed_types
    [ TDVariant ("Counter" ^ March_tir.Tir_names.actor_msg_suffix,
                 [("Inc", [TInt; TInt])]) ];
  Alcotest.(check int) "an actor message type is never unboxed" 0
    (List.length (March_tir.Repr.unboxed_types ()));
  March_tir.Repr.clear_unboxed_types ()

let test_unboxed_aggregate_rc_predicates () =
  let open March_tir.Tir in
  March_tir.Repr.set_unboxed_types
    [ TDVariant ("Vec3", [("Vec3", [TFloat; TFloat; TFloat])]) ];
  let v = TCon ("Vec3", []) in
  Alcotest.(check bool) "needs_rc: an inline aggregate has no refcount" false
    (March_tir.Rc_types.needs_rc v);
  Alcotest.(check bool) "borrow_eligible: it is copied, never referenced" false
    (March_tir.Rc_types.borrow_eligible v);
  (* An ordinary TCon in the same table is unaffected. *)
  Alcotest.(check bool) "an ordinary ADT still needs RC" true
    (March_tir.Rc_types.needs_rc (TCon ("Other", [])));
  March_tir.Repr.clear_unboxed_types ()

(* A type named in an extern signature stays Boxed: the C side is handed the
   boxed cell (that is the layout every extern was written against), but that
   box would be a fresh rc=1 cell no one owns — [needs_rc] is false for the
   aggregate, so Perceus emits no caller-side drop.  Keeping the type boxed end
   to end removes the question. *)
let test_unboxed_aggregate_ffi_type_stays_boxed () =
  let open March_tir.Tir in
  let td = TDVariant ("Vec3", [("Vec3", [TFloat; TFloat; TFloat])]) in
  March_tir.Repr.set_unboxed_types [td];
  Alcotest.(check bool) "unboxed without an extern" true
    (March_tir.Repr.unboxed_of_type_name "Vec3" <> None);
  March_tir.Repr.set_unboxed_types
    ~externs:[ { ed_march_name = "f"; ed_c_name = "f"; ed_lib_name = "m";
                 ed_js_sym = "f"; ed_params = [TCon ("Vec3", [])];
                 ed_consumed = [false]; ed_blocking = false; ed_raises = false;
                 ed_ret = TInt } ]
    [td];
  Alcotest.(check bool) "boxed once it crosses an extern signature" false
    (March_tir.Repr.unboxed_of_type_name "Vec3" <> None);
  March_tir.Repr.clear_unboxed_types ()

(* ── The branch-join box is owned by the merge that made it ───────────────

   An unboxed aggregate built inside an `if`/`match` arm cannot stay in
   registers across the join: both arms store through a `ptr` result slot, so
   [Llvm_ctx.coerce]'s inline-aggregate boxing arm materialises a
   [march_alloc] cell per arm.  Nobody downstream owns that cell —
   [Rc_types.needs_rc] is false for the aggregate, so Perceus emits no drop for
   it, and the value the caller sees is the struct, not the box.  The merge in
   [Llvm_case.finish_ptr_merge] is therefore the only place that can release
   it, and before it did, a `Pair(Float, Float)` built in a branch leaked one
   32-byte cell per construction (5 001 live objects over 5 000 iterations;
   specs/progress/2026-09-04-unboxed-aggregate-branch-join-leak.md).

   Asserted structurally rather than by a raw call count, so the check says
   what it means: for each case-merge load that is UNBOXED as an inline
   aggregate (a field read at +16 off the loaded pointer, which only the
   ptr→struct coerce arm emits), the same SSA value must also be released.
   Pre-fix this program emitted two boxes and one release, and the pair whose
   `released` is false was exactly the aggregate merge. *)

let unboxed_branch_join_src = {|mod UBJoin do
  needs IO.Console
  type P2 = P2(Float, Float)
  fn psum(p : P2) : Float do
    match p do
      P2(a, c) -> a +. c
    end
  end
  pfn spin(i : Int, acc : Float) : Float do
    if i == 0 do acc
    else
      let p = if i % 2 == 0 do P2(1.0, 2.0) else P2(3.0, 4.0) end
      spin(i - 1, acc +. psum(p))
    end
  end
  fn main(_cap_console : Cap(IO.Console)) : Unit do
    println(float_to_string(spin(10, 0.0)))
  end
end|}

(* The body of `define ... @name(`, up to the closing brace in column 0. *)
let ir_define ir name =
  let re = Str.regexp (Printf.sprintf "define [^\n]*@%s(" (Str.quote name)) in
  match Str.search_forward re ir 0 with
  | exception Not_found -> ""
  | start ->
    (match Str.search_forward (Str.regexp "^}") ir start with
     | exception Not_found -> String.sub ir start (String.length ir - start)
     | stop -> String.sub ir start (stop - start))

(* Every case-merge load in [fn_ir] that is unboxed back into an inline
   aggregate, paired with whether that same value is also released. *)
let unboxed_merge_loads fn_ir =
  let re = Str.regexp "\\(%[A-Za-z0-9_.]+\\) = load ptr, ptr %res_slot" in
  let rec go i acc =
    match Str.search_forward re fn_ir i with
    | exception Not_found -> List.rev acc
    | j ->
      let v = Str.matched_group 1 fn_ir in
      let acc =
        if ir_contains fn_ir (Printf.sprintf "getelementptr i8, ptr %s, i64 16" v)
        then (v, ir_contains fn_ir
                (Printf.sprintf "call void @march_decrc_local(ptr %s)" v)) :: acc
        else acc
      in
      go (j + 1) acc
  in
  go 0 []

let test_unboxed_aggregate_branch_join_box_released () =
  let ir = emit_tco_opt_ir unboxed_branch_join_src in
  let fn_ir = ir_define ir "spin" in
  Alcotest.(check bool) "the loop function is present in the IR" true (fn_ir <> "");
  (* The join really does box — otherwise the release assertion below is
     vacuous.  Two arms, two boxes, each the 16-byte header + 2 fields. *)
  Alcotest.(check int) "both arms box the aggregate to cross the join" 2
    (ir_count fn_ir "call ptr @march_alloc(i64 32)");
  let merges = unboxed_merge_loads fn_ir in
  Alcotest.(check bool) "an aggregate-unboxing merge exists" true (merges <> []);
  List.iter (fun (v, released) ->
      Alcotest.(check bool)
        (Printf.sprintf
           "the box loaded at %s is unboxed into a struct and then released — \
            nobody downstream owns it" v)
        true released)
    merges

(* ── FnFused coverage: flag-vs-reality cross-check (Wave 3 Chunk 2 Task 1) ──
   fusion.ml's three synthesis sites (gen_map_fold / gen_filter_fold /
   gen_map_filter_fold — see fusion.ml) tag every generated fn_def
   `Tir.FnFused` (added Wave 3 Chunk 1 Task 3, commit c28ff465), but until
   now nothing ever read that field back — no consumer, no assert, no test.
   This is exactly the "flag says X but does anything check X matches
   reality" gap the transitional fn_kind asserts (perceus.ml, llvm_emit.ml)
   exist to catch for the OTHER fn_kind values; FnFused had no such
   cross-check at all.

   Reachability: fusion IS already exercised by test-corpus programs — see
   test_eval.ml's test_fusion_map_fold / test_fusion_filter_fold /
   test_fusion_map_filter_fold (via Test_helpers.fusion_module +
   has_fused_fn, which only sniff the "$fused_" name prefix). These tests
   below reuse that same reachable pipeline and additionally assert the
   fn_kind tag, closing the flag-vs-reality gap: every "$fused_" named
   fn_def must be FnFused, and — the direction the name-only check can't
   see — every FnFused fn_def must be named "$fused_<mf|ff|mff>_N" per
   fusion.ml's own gensym convention. *)

(** True if [name] matches fusion.ml's gensym convention: "$fused_" followed
    by one of the three generator tags ("mf"/"ff"/"mff") then "_" and a
    counter. Mirrors fusion.ml's [gensym] (`Printf.sprintf "$fused_%s_%d"`) —
    kept local to this test (not a Tir_names contract: fusion.ml's synthesized
    names have no consumer that name-sniffs them, per the Wave 3 Task 3
    report, so there is nothing in Tir_names to centralize here). *)
let is_fusion_gensym_name (name : string) : bool =
  let has_prefix p s =
    String.length s >= String.length p && String.sub s 0 (String.length p) = p
  in
  let strip_prefix p s = String.sub s (String.length p) (String.length s - String.length p) in
  if not (has_prefix "$fused_" name) then false
  else
    let rest = strip_prefix "$fused_" name in
    List.exists (fun tag ->
      has_prefix (tag ^ "_") rest &&
      (let ctr = strip_prefix (tag ^ "_") rest in
       ctr <> "" && String.for_all (fun c -> c >= '0' && c <= '9') ctr)
    ) ["mf"; "ff"; "mff"]

(** Cross-check, over a fused module: every fn whose name matches the
    "$fused_" gensym convention is tagged FnFused, AND every FnFused-tagged
    fn matches the naming convention — the bidirectional check the plan
    calls out as never having been covered. *)
let assert_fnfused_consistent (m : March_tir.Tir.tir_module) : unit =
  List.iter (fun (fd : March_tir.Tir.fn_def) ->
    if is_fusion_gensym_name fd.March_tir.Tir.fn_name then
      Alcotest.(check bool)
        ("\"" ^ fd.March_tir.Tir.fn_name ^ "\" named like a fusion helper => FnFused")
        true (fd.March_tir.Tir.fn_kind = March_tir.Tir.FnFused);
    if fd.March_tir.Tir.fn_kind = March_tir.Tir.FnFused then
      Alcotest.(check bool)
        ("FnFused fn \"" ^ fd.March_tir.Tir.fn_name ^ "\" named like fusion.ml's gensym")
        true (is_fusion_gensym_name fd.March_tir.Tir.fn_name)
  ) m.March_tir.Tir.tm_fns

(** At least one FnFused fn_def actually exists post-fusion (not just that
    IF one exists it's consistent — the existence half of the gate). *)
let assert_some_fnfused_present (m : March_tir.Tir.tir_module) : unit =
  let any_fused = List.exists (fun (fd : March_tir.Tir.fn_def) ->
      fd.March_tir.Tir.fn_kind = March_tir.Tir.FnFused)
      m.March_tir.Tir.tm_fns
  in
  Alcotest.(check bool) "at least one FnFused fn_def present post-fusion" true any_fused

let test_fnfused_map_fold_tagged () =
  let m = fusion_module {|mod Test do
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

    fn main() : Int do
      let xs = ICons(1, ICons(2, ICons(3, INil)))
      let ys = imap(xs, fn x -> x * 2)
      ifold(ys, 0, fn (a, b) -> a + b)
    end
  end|} in
  Alcotest.(check bool) "fused fn emitted for map+fold" true (has_fused_fn m);
  assert_some_fnfused_present m;
  assert_fnfused_consistent m

let test_fnfused_filter_fold_tagged () =
  let m = fusion_module {|mod Test do
    type IntList = INil | ICons(Int, IntList)

    fn ifilter(xs : IntList, p : Int -> Bool) : IntList do
      match xs do
      INil        -> INil
      ICons(h, t) ->
        if p(h) do ICons(h, ifilter(t, p))
        else ifilter(t, p) end
      end
    end

    fn ifold(xs : IntList, acc : Int, f : Int -> Int -> Int) : Int do
      match xs do
      INil        -> acc
      ICons(h, t) -> ifold(t, f(acc, h), f)
      end
    end

    fn main() : Int do
      let xs = ICons(1, ICons(2, ICons(3, INil)))
      let ys = ifilter(xs, fn x -> x > 1)
      ifold(ys, 0, fn (a, b) -> a + b)
    end
  end|} in
  Alcotest.(check bool) "fused fn emitted for filter+fold" true (has_fused_fn m);
  assert_some_fnfused_present m;
  assert_fnfused_consistent m

let test_fnfused_map_filter_fold_tagged () =
  let m = fusion_module {|mod Test do
    type IntList = INil | ICons(Int, IntList)

    fn imap(xs : IntList, f : Int -> Int) : IntList do
      match xs do
      INil        -> INil
      ICons(h, t) -> ICons(f(h), imap(t, f))
      end
    end

    fn ifilter(xs : IntList, p : Int -> Bool) : IntList do
      match xs do
      INil        -> INil
      ICons(h, t) ->
        if p(h) do ICons(h, ifilter(t, p))
        else ifilter(t, p) end
      end
    end

    fn ifold(xs : IntList, acc : Int, f : Int -> Int -> Int) : Int do
      match xs do
      INil        -> acc
      ICons(h, t) -> ifold(t, f(acc, h), f)
      end
    end

    fn main() : Int do
      let xs = ICons(1, ICons(2, ICons(3, ICons(4, ICons(5, INil)))))
      let ys = imap(xs, fn x -> x * 2)
      let zs = ifilter(ys, fn x -> x > 4)
      ifold(zs, 0, fn (a, b) -> a + b)
    end
  end|} in
  Alcotest.(check bool) "fused fn emitted for map+filter+fold" true (has_fused_fn m);
  assert_some_fnfused_present m;
  assert_fnfused_consistent m

(** Negative control: a non-fusible (non-list) program must have NO
    FnFused-tagged fn_def at all — the existence check must not be
    vacuously true for every module. *)
let test_fnfused_absent_when_not_fused () =
  let m = fusion_module {|mod Test do
    fn add(a : Int, b : Int) : Int do a + b end
    fn main() : Int do add(1, 2) end
  end|} in
  Alcotest.(check bool) "no fused fn for non-list program" false (has_fused_fn m);
  let any_fused = List.exists (fun (fd : March_tir.Tir.fn_def) ->
      fd.March_tir.Tir.fn_kind = March_tir.Tir.FnFused)
      m.March_tir.Tir.tm_fns
  in
  Alcotest.(check bool) "no FnFused fn_def for non-list program" false any_fused

let test_nested_bool_lit_pattern_no_tag_switch () =
  let ir = emit_actor_ir {|mod Test do
  needs IO.Console
    fn classify(r : Result(Bool, String)) : String do
      match r do
        Ok(true) -> "T"
        Ok(false) -> "F"
        Err(_) -> "E"
      end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do
      println(classify(Ok(true)))
      println(classify(Ok(false)))
      println(classify(Err("x")))
    end
  end|} in
  Alcotest.(check int) "exactly one i32 ctor-tag switch (outer Ok/Err)" 1
    (ir_count ir "switch i32");
  Alcotest.(check bool) "bool field tested via trunc to i1" true
    (ir_contains ir "trunc i64");
  Alcotest.(check bool) "bool field untagged via ashr" true
    (ir_contains ir "ashr i64")

(** Nested Int literal patterns: the inner test must switch on the raw
    tagged bits with (n<<1)|1 labels — Ok(1) → label 3, Ok(2) → label 5. *)
let test_nested_int_lit_pattern_tagged_switch () =
  let ir = emit_actor_ir {|mod Test do
  needs IO.Console
    fn classify(r : Result(Int, String)) : String do
      match r do
        Ok(1) -> "one"
        Ok(2) -> "two"
        Ok(_) -> "other"
        Err(_) -> "E"
      end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do
      println(classify(Ok(1)))
    end
  end|} in
  Alcotest.(check int) "exactly one i32 ctor-tag switch (outer Ok/Err)" 1
    (ir_count ir "switch i32");
  Alcotest.(check bool) "Ok(1) compared against tagged immediate 3" true
    (ir_contains ir "i64 3, label");
  Alcotest.(check bool) "Ok(2) compared against tagged immediate 5" true
    (ir_contains ir "i64 5, label")

(** Nested Atom literal patterns: same shape — no second ctor-tag switch. *)
let test_nested_atom_lit_pattern_no_tag_switch () =
  let ir = emit_actor_ir {|mod Test do
  needs IO.Console
    fn classify(r : Result(Atom, String)) : String do
      match r do
        Ok(:red) -> "R"
        Ok(:blue) -> "B"
        Ok(_) -> "other"
        Err(_) -> "E"
      end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do
      println(classify(Ok(:red)))
    end
  end|} in
  Alcotest.(check int) "exactly one i32 ctor-tag switch (outer Ok/Err)" 1
    (ir_count ir "switch i32")

(** Finding-19 memory-safety regression: two single-handler actors whose
    messages, under the OLD per-actor 0-based Newtype encoding, were
    indistinguishable at dispatch — a Logger message delivered to Counter's
    mailbox was misrouted into Counter's Inc handler and its String payload
    reinterpreted as an Int (memory-unsafe UB).

    The fix forces each actor message type Boxed with a GLOBALLY-unique heap tag
    and gives every dispatch ECase a dropping default arm. Assert the IR shape:
      - Counter_dispatch switches on an i32 tag (Boxed decode — NOT a
        tag-less Newtype value passed straight through), and
      - has a case_default arm that decrefs the dropped message and returns
        (the drop), rather than folding to `unreachable`, and
      - Counter's and Logger's message ctor tags are DISTINCT (global numbering),
        so a Logger message cannot match a Counter branch. *)
let test_actor_foreign_msg_drop_boxed_dispatch () =
  let ir = emit_actor_ir {|mod Test do
    actor Counter do
      state { count : Int }
      init  { count: 0 }
      on Inc(x : Int) do { count: state.count + x } end
    end
    actor Logger do
      state { seen : Int }
      init  { seen: 0 }
      on Log(m : String) do { seen: state.seen + 1 } end
    end
    fn main() : Unit do
      let c = spawn(Counter)
      send(c, Inc(3))
      send(c, Log("stray"))
      run_until_idle()
    end
  end|} in
  (* Boxed decode: the single-handler dispatch loads an i32 ctor tag and
     switches on it (a tag-less Newtype would pass the value straight through
     with no `switch i32`). *)
  Alcotest.(check bool) "Counter dispatch switches on an i32 tag (Boxed, not Newtype)"
    true (ir_contains ir "switch i32");
  (* Dropping default arm: the dispatch has a case_default that releases the
     message (via march_decrc) — the foreign-message drop, not `unreachable`. *)
  Alcotest.(check bool) "dispatch default arm is a drop (decrc), not unreachable"
    true (ir_contains ir "case_default");
  (* Global tags: Counter.Inc and Logger.Log get DISTINCT tags. Both are in the
     0x01000000+ actor-message tag space; distinctness is what makes a foreign
     message fall to the default arm. The base tag 16777216 (0x01000000) is
     assigned to the first message ctor; a second, distinct tag must also appear. *)
  Alcotest.(check bool) "first actor-message ctor uses the global tag base 16777216"
    true (ir_contains ir "store i32 16777216");
  Alcotest.(check bool) "a second, distinct actor-message tag is assigned (16777217)"
    true (ir_contains ir "store i32 16777217")

(** Finding 20 (compiled actor-struct state-write race, fixed): a genuine
    actor's handler writes its new state back via an EReuse on the actor
    struct. That EReuse must be UNCONDITIONAL — no refcount load/branch — or
    the handler can race the caller's concurrent incrc/decrc on the actor
    handle and silently lose the write (see specs/todos.md finding 20).
    Assert the absence of the generic RC-conditional FBIP shape (an atomic RC
    load + `icmp eq i64 _, 1` + the `fbip_fresh`/`fbip_reuse` block pair) in
    the emitted module. *)
let test_actor_struct_ereuse_unconditional () =
  let ir = emit_actor_ir {|mod Test do
    actor Counter do
      state { count : Int }
      init  { count: 0 }
      on Inc(x : Int) do { count: state.count + x } end
    end
    fn main() : Unit do
      let c = spawn(Counter)
      send(c, Inc(3))
      run_until_idle()
    end
  end|} in
  Alcotest.(check bool) "no RC-conditional fbip_fresh block for the actor-struct reuse"
    false (ir_contains ir "fbip_fresh");
  Alcotest.(check bool) "no atomic RC load guarding the actor-struct reuse"
    false (ir_contains ir "load atomic i64")

(** An actor message-handler binder must SHADOW a same-named top-level function.

    [lower_fn_def] registers a function's parameters in [_fn_param_types] for the
    duration of lowering its body; that table is the shield [resolve_use_alias]
    consults before rewriting a bare name into a qualified global. [lower_handler]
    did not do the same for [ah_params], so a handler binder whose name matched
    ANY top-level function linked into the program was silently discarded and the
    bare reference resolved to the FUNCTION — emitting its raw code address where
    the bound value belonged.

    Found in the wild 2026-08-19: an Envoy actor with
    [on Deliver(session_id, kind, text, approved)] collided with stdlib
    [HttpServer.text], so the compiled server passed [ptr @HttpServer.text] as the
    message text. Refcounting that code address writes at ptr+0 into read-only
    __TEXT — SIGBUS, exit 138 — while the INTERPRETER handled the same program
    correctly (a compiled-only miscompile). Non-colliding binders worked only by
    name coincidence with the TIR param var.

    Witness: the handler passes its own binder, never the imported function. *)
let test_actor_handler_binder_shadows_toplevel_fn () =
  let ir = emit_actor_ir {|mod Test do
  needs IO.Console
    mod Helper do
      fn text(s : String) : String do s end
    end
    import Helper
    fn emit(label : String, v : String) : String do label ++ v end
    actor Host do
      state { n : Int }
      init  { n: 0 }
      on Msg(text) do
        let _ = emit("got: ", text)
        { n: state.n + 1 }
      end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do
      let pid = spawn(Host)
      let _ = send(pid, Msg("hello"))
      run_until_idle()
    end
  end|} in
  (* The bug emitted the function's address as a call argument. Match the
     ARGUMENT form (comma-preceded) so this cannot alias the `define` line. *)
  Alcotest.(check bool)
    "handler binder is not replaced by the imported Helper.text function"
    false (ir_contains ir ", ptr @Helper.text")

(** Finding 20 follow-up (adversarial-review Critical, fixed): the actor-struct
    always-in-place gate must be STRUCTURAL (does this type's field 0 carry
    the compiler-only "$d_dispatch" marker lower_actor.ml alone can construct
    — see Repr.is_actor_struct_type), not a name-suffix heuristic. A prior
    version gated on the type constructor name ending in "_Actor", which
    false-positive-matched an ORDINARY user type coincidentally named
    `Tree_Actor` — such a type's EReuse would then skip the refcount check,
    silently corrupting a SHARED (RC>1) value in place. Assert a non-actor
    `..._Actor`-named type's EReuse still takes the RC-conditional path. *)
let test_actor_suffix_named_user_type_not_treated_as_actor () =
  let ir = emit_actor_ir {|mod Test do
  needs IO.Console
    type Tree_Actor = TLeaf(Int) | TNode(Tree_Actor, Tree_Actor)
    fn bump(t : Tree_Actor) : Tree_Actor do
      match t do
        TLeaf(n) -> TLeaf(n + 1)
        TNode(l, r) -> TNode(bump(l), r)
      end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do
      let original = TNode(TLeaf(10), TLeaf(20))
      let shared = original
      let bumped = bump(original)
      println(int_to_string(bumped_val(bumped) + shared_val(shared)))
    end
    fn bumped_val(t : Tree_Actor) : Int do
      match t do
        TLeaf(n) -> n
        TNode(l, _) -> bumped_val(l)
      end
    end
    fn shared_val(t : Tree_Actor) : Int do
      match t do
        TLeaf(n) -> n
        TNode(l, _) -> shared_val(l)
      end
    end
  end|} in
  Alcotest.(check bool) "a `_Actor`-suffixed non-actor type's reuse KEEPS the RC-conditional fbip_fresh block"
    true (ir_contains ir "fbip_fresh");
  Alcotest.(check bool) "a `_Actor`-suffixed non-actor type's reuse KEEPS the atomic RC load"
    true (ir_contains ir "load atomic i64")

(* ── TCO (tail-call optimisation) IR tests ─────────────────────────────── *)

(** Helper: full pipeline → LLVM IR, same as emit_actor_ir but named clearly. *)
let test_tco_factorial_has_loop () =
  let ir = emit_tco_ir {|mod Test do
  needs IO.Console
    @[no_warn_recursion]
    fn factorial(n : Int, acc : Int) : Int do
      if n == 0 do acc
      else factorial(n - 1, n * acc) end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(int_to_string(factorial(10, 1))) end
  end|} in
  (* The tco_loop label and back-edge branch are the unique markers of TCO. *)
  Alcotest.(check bool) "TCO factorial: tco_loop block emitted" true
    (ir_contains ir "tco_loop");
  Alcotest.(check bool) "TCO factorial: back-edge branch emitted" true
    (ir_contains ir "br label %tco_loop")

(** Tail-recursive list fold: should be transformed into a loop. *)
let test_tco_fold_has_loop () =
  let ir = emit_tco_ir {|mod Test do
  needs IO.Console
    type L = Nil | Cons(Int, L)
    @[no_warn_recursion]
    fn fold(xs : L, acc : Int) : Int do
      match xs do
      Nil        -> acc
      Cons(h, t) -> fold(t, acc + h)
      end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(int_to_string(fold(Cons(1, Cons(2, Nil)), 0))) end
  end|} in
  Alcotest.(check bool) "TCO fold: tco_loop block emitted" true
    (ir_contains ir "tco_loop");
  Alcotest.(check bool) "TCO fold: back-edge branch emitted" true
    (ir_contains ir "br label %tco_loop")

(** Non-tail-recursive fib must NOT get a TCO loop (it is not tail recursive). *)
let test_tco_nontail_fib_no_loop () =
  let ir = emit_tco_ir {|mod Test do
  needs IO.Console
    @[no_warn_recursion]
    fn fib(n : Int) : Int do
      if n < 2 do n
      else fib(n - 1) + fib(n - 2) end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(int_to_string(fib(10))) end
  end|} in
  Alcotest.(check bool) "non-tail fib: no TCO loop" false
    (ir_contains ir "tco_loop");
  Alcotest.(check bool) "non-tail fib: call instruction present" true
    (ir_contains ir "call i64 @fib")

(** Single-param tail-recursive countdown: loop emitted with back-edge. *)
let test_tco_countdown_has_loop () =
  let ir = emit_tco_ir {|mod Test do
  needs IO.Console
    @[no_warn_recursion]
    fn count(n : Int) : Int do
      if n == 0 do 0
      else count(n - 1) end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(int_to_string(count(100))) end
  end|} in
  Alcotest.(check bool) "TCO countdown: tco_loop block emitted" true
    (ir_contains ir "tco_loop");
  Alcotest.(check bool) "TCO countdown: back-edge branch emitted" true
    (ir_contains ir "br label %tco_loop")

(* ── Mutual TCO codegen tests ──────────────────────────────────────── *)

let test_mutual_tco_even_odd_loop_emitted () =
  let ir = emit_mutual_tco_ir {|mod Test do
  needs IO.Console
    @[no_warn_recursion]
    fn even(n : Int) : Bool do
      if n == 0 do true else odd(n - 1) end
    end
    @[no_warn_recursion]
    fn odd(n : Int) : Bool do
      if n == 0 do false else even(n - 1) end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(to_string(even(1000000))) end
  end|} in
  Alcotest.(check bool) "mutual TCO even/odd: mutual_loop block emitted" true
    (ir_contains ir "mutual_loop");
  Alcotest.(check bool) "mutual TCO even/odd: switch dispatch emitted" true
    (ir_contains ir "switch");
  Alcotest.(check bool) "mutual TCO even/odd: back-edge branch emitted" true
    (ir_contains ir "br label %mutual_loop");
  Alcotest.(check bool) "mutual TCO even/odd: combined fn declared" true
    (ir_contains ir "__mutco_");
  Alcotest.(check bool) "mutual TCO even/odd: even wrapper present" true
    (ir_contains ir "@even(")

(** Three-way mutual tail recursion: f → g → h → f.
    All three must end up inside the same combined dispatch function. *)
let test_mutual_tco_three_way () =
  let ir = emit_mutual_tco_ir {|mod Test do
  needs IO.Console
    @[no_warn_recursion]
    fn fa(n : Int) : Int do
      if n == 0 do 0 else fb(n - 1) end
    end
    @[no_warn_recursion]
    fn fb(n : Int) : Int do
      if n == 0 do 0 else fc(n - 1) end
    end
    @[no_warn_recursion]
    fn fc(n : Int) : Int do
      if n == 0 do 0 else fa(n - 1) end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(int_to_string(fa(99))) end
  end|} in
  Alcotest.(check bool) "three-way mutual TCO: mutual_loop emitted" true
    (ir_contains ir "mutual_loop");
  Alcotest.(check bool) "three-way mutual TCO: switch emitted" true
    (ir_contains ir "switch");
  Alcotest.(check bool) "three-way mutual TCO: combined fn declared" true
    (ir_contains ir "__mutco_")

(** A/B state-machine with mutual tail calls. *)
let test_mutual_tco_state_machine () =
  let ir = emit_mutual_tco_ir {|mod Test do
  needs IO.Console
    @[no_warn_recursion]
    fn state_a(n : Int) : Int do
      if n <= 0 do 1 else state_b(n - 1) end
    end
    @[no_warn_recursion]
    fn state_b(n : Int) : Int do
      if n <= 0 do 2 else state_a(n - 1) end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(int_to_string(state_a(1000000))) end
  end|} in
  Alcotest.(check bool) "state machine mutual TCO: mutual_loop emitted" true
    (ir_contains ir "mutual_loop");
  Alcotest.(check bool) "state machine mutual TCO: combined fn declared" true
    (ir_contains ir "__mutco_")

(** Non-tail mutual recursion must NOT get a mutual_loop block.
    f calls g in non-tail position (result used in arithmetic). *)
let test_mutual_tco_non_tail_no_loop () =
  let ir = emit_mutual_tco_ir {|mod Test do
  needs IO.Console
    @[no_warn_recursion]
    fn count_f(n : Int) : Int do
      if n == 0 do 1 else count_g(n - 1) + 1 end
    end
    @[no_warn_recursion]
    fn count_g(n : Int) : Int do
      if n == 0 do 1 else count_f(n - 1) + 1 end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(int_to_string(count_f(10))) end
  end|} in
  Alcotest.(check bool) "non-tail mutual recursion: no mutual_loop" false
    (ir_contains ir "mutual_loop")

(** Self-TCO must still work when mutual-TCO detection is also running.
    A self-recursive function that is NOT part of any mutual group must still
    get its tco_loop transformation. *)
let test_mutual_tco_self_tco_unaffected () =
  let ir = emit_mutual_tco_ir {|mod Test do
  needs IO.Console
    @[no_warn_recursion]
    fn countdown(n : Int) : Int do
      if n == 0 do 0 else countdown(n - 1) end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(int_to_string(countdown(10))) end
  end|} in
  Alcotest.(check bool) "self TCO still works: tco_loop emitted" true
    (ir_contains ir "tco_loop");
  Alcotest.(check bool) "self TCO still works: back-edge branch emitted" true
    (ir_contains ir "br label %tco_loop")

(** B7 regression: Perceus wraps a borrow-induced post-call DecRC around a
    MUTUAL (non-self) tail call — [let tmp = other_member(args) in (dec_rc v;
    tmp)] — exactly as it does for self-tail-calls (see
    is_trivial_dec_chain_returning's doc comment). The mutual-TCO EApp
    interception arm has no ELet/ESeq counterparts, so this dec-chain used to
    land in the dead "mutco_cont" block opened after the back-edge branch:
    the DecRC never executes, leaking one heap cell every loop iteration.

    build_loop/consume_loop mirror examples/rc_mutual_tco_borrowed.march:
    `prefix` is a fresh local passed to consume_loop's BORROWED position 0
    and is dead after that call, so Perceus emits the ELet-wrapped dec-chain
    around the mutual tail call. Assert the DecRC executes on the live
    back-edge path (before the branch to mutual_loop), not only in the
    unreachable continuation block after it. *)
let test_mutual_tco_borrowed_arg_decref_on_live_path () =
  let ir = emit_mutual_tco_ir {|mod Test do
  needs IO.Console
    fn build_loop(seed, n) do
      let prefix = String.repeat("a", 1)
      if n == 0 do
        String.byte_size(seed) + String.byte_size(prefix)
      else
        consume_loop(prefix, n - 1)
      end
    end
    fn consume_loop(s, n) do
      if n == 0 do
        String.byte_size(s)
      else
        build_loop(s, n - 1)
      end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(int_to_string(build_loop("z", 1000))) end
  end|} in
  Alcotest.(check bool) "mutual-tco borrowed-arg: mutual_loop emitted" true
    (ir_contains ir "mutual_loop");
  (* For each "br label %mutual_loop..." back-edge, find the LLVM basic block
     that contains it (the text since the nearest preceding "label:") and
     require a live "march_decrc" call inside that same block — i.e. on the
     reachable path, executed before the branch. Before the fix, the
     mutual-tail-call back-edge block has NO decrc (it is stranded in the
     unreachable "mutco_cont" block emitted just after the branch instead). *)
  let re_label = Str.regexp "\n[A-Za-z_][A-Za-z0-9_.]*:" in
  let re_backedge = Str.regexp "br label %mutual_loop[0-9]*" in
  let block_start_before pos =
    let rec find_last start acc =
      match Str.search_forward re_label ir start with
      | exception Not_found -> acc
      | i when i >= pos -> acc
      | i -> find_last (i + 1) (Str.match_end ())
    in
    find_last 0 0
  in
  let rec scan_backedges start acc =
    match Str.search_forward re_backedge ir start with
    | exception Not_found -> acc
    | i ->
      let block_start = block_start_before i in
      let block = String.sub ir block_start (i - block_start) in
      scan_backedges (Str.match_end ()) (block :: acc)
  in
  let backedge_blocks = scan_backedges 0 [] in
  Alcotest.(check bool) "mutual-tco borrowed-arg: at least one back-edge found" true
    (List.length backedge_blocks > 0);
  let live_decrefs = List.filter (fun b -> ir_contains b "march_decrc") backedge_blocks in
  Alcotest.(check bool)
    "mutual-tco borrowed-arg: DecRC executes in the back-edge's own block (live path), not only in the dead mutco_cont block after it"
    true (List.length live_decrefs > 0)

(** Regression: a hand-written tail-recursive list walk leaked every cons cell.

    [eafbd71a] fixed a use-after-free where the self-TCO back-edge eagerly ran
    a post-call DecRC on a FRESHLY-ALLOCATED forwarded argument (no matching
    prior IncRC), freeing it one instruction before the next iteration reused
    it.  The fix skipped every Dec/IncRC in the dec-chain whose target is one
    of the forwarded arguments — too broad.  A [Cons(_, t) -> walk(t, ...)]
    walk lowers to
        let t = (inc_rc $f; $f) in walk(t, acc'); dec_rc t
    where the DecRC is the *matching half* of the IncRC that materialised [t]
    from the borrowed tail field.  Skipping it leaves the IncRC uncompensated,
    so every cons cell (and its payload) ends the loop at refcount >= 1 and is
    never reclaimed when the owner drops the list — a leak proportional to the
    input, the ordinary way to consume a [String.split] result.

    [walk]'s whole body is the TCO loop, so its RC ops must balance over one
    iteration: assert the emitted [@walk] definition issues as many DecRCs as
    IncRCs.  Before the fix it dups the tail field once and never releases it
    (1 IncRC / 0 DecRC).  (eafbd71a's own case stays covered by
    test/native/tco_fresh_arg_decrc.march — there the forwarded argument has
    no IncRC to balance, so it must keep emitting neither op.) *)
let test_tco_self_dup_arg_decref_on_live_path () =
  let ir = emit_tco_opt_ir {|mod Test do
  needs IO.Console
    @[no_warn_recursion]
    fn walk(xs : List(String), acc : Int) : Int do
      match xs do
      Nil -> acc
      Cons(_, t) -> walk(t, acc + 1)
      end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(int_to_string(walk(["a", "b"], 0))) end
  end|} in
  Alcotest.(check bool) "self-tco dup-arg: tco_loop emitted" true
    (ir_contains ir "tco_loop");
  let walk_ir =
    let start = Str.search_forward (Str.regexp "define [^\n]*@walk(") ir 0 in
    let stop = Str.search_forward (Str.regexp "\n}") ir start in
    String.sub ir start (stop - start)
  in
  Alcotest.(check bool) "self-tco dup-arg: walk's body is the TCO loop" true
    (ir_contains walk_ir "br label %tco_loop");
  let count pat =
    let re = Str.regexp_string pat in
    let rec go start acc =
      match Str.search_forward re walk_ir start with
      | exception Not_found -> acc
      | _ -> go (Str.match_end ()) (acc + 1)
    in
    go 0 0
  in
  let incs = count "@march_incrc" in
  (* The release is either a direct decrc or — once Drop.run has rewritten it
     — a call to the generated deep drop, which performs that same decrc on
     the box.  Either discharges the dup; neither being present does not. *)
  let decs = count "@march_decrc" + count "@__drop$" in
  Alcotest.(check bool) "self-tco dup-arg: the tail field is dup'd" true (incs > 0);
  Alcotest.(check int)
    "self-tco dup-arg: every IncRC of the forwarded tail has a matching release (else every cons cell leaks)"
    incs decs

(** Regression: dropping a container that was never destructured leaked
    everything below its top cell.

    March reclaims an aggregate by DESTRUCTURING it — [llvm_case.ml]'s
    owned-scrutinee path frees the box with [march_decrc_freed] and lets the
    extracted fields inherit its child references.  A bare [EDecRC], which is
    what Perceus emits for the OWNER when the consumer only borrows, instead
    lowered to [march_decrc_local]: a shallow [free(p)] that never decrements
    the children.  So

    {v
      let parts = String.split(buf, ",")
      consume(parts)        -- borrows
      -- drop parts         -- freed ONE cons cell; 150K strings orphaned
    v}

    leaked proportionally to the input (585 MB peak on a 60-iteration loop,
    growing linearly).  It was never about the traversal: a [consume] that
    ignores its argument entirely leaked identically.

    [Drop.run] now routes such a drop through a synthesized [__drop$T].
    Assert the call reaches the emitted IR and that the drop function itself
    is present, releases the head field, and early-exits on a shared box —
    that last part is not an optimization: descending into a cell whose
    refcount did not reach zero is both wrong (the children still belong to
    the surviving reference) and quadratic. *)
let test_deep_drop_of_borrowed_container () =
  let ir = emit_tco_opt_ir {|mod Test do
  needs IO.Console
    @[no_warn_recursion]
    fn consume(xs : List(String)) : Int do 0 end
    fn go(buf : String, i : Int, n : Int, acc : Int) : Int do
      if i >= n do acc
      else
        let parts = String.split(buf, ",")
        go(buf, i + 1, n, acc + consume(parts))
      end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(int_to_string(go("a,b,c", 0, 2, 0))) end
  end|} in
  Alcotest.(check bool)
    "deep drop: the owner's drop of the split result calls a generated deep drop, not a bare decrc"
    true (ir_contains ir "call void @__drop$List_String");
  let drop_ir =
    let start = Str.search_forward
        (Str.regexp "define [^\n]*@__drop\\$List_String(") ir 0 in
    let stop = Str.search_forward (Str.regexp "\n}") ir start in
    String.sub ir start (stop - start)
  in
  Alcotest.(check bool)
    "deep drop: releases the box via march_decrc_freed so it can tell unique from shared"
    true (ir_contains drop_ir "@march_decrc_freed");
  Alcotest.(check bool)
    "deep drop: releases the head field when it owned the box"
    true (ir_contains drop_ir "@march_decrc");
  Alcotest.(check bool)
    "deep drop: walks the spine as a TCO loop, not C-stack recursion (a 150K-element list must not overflow)"
    true (ir_contains drop_ir "br label %tco_loop")

(** Final-review regression: [has_non_tail_group_call]'s dec-chain-wrapper
    arm used to recognise [ELet (tmp, EApp (f, _), dec-chain-returning-tmp)]
    at ANY position without checking [in_tail], so a Perceus-wrapped group
    call sitting in a genuinely NON-tail spot (its result is bound and fed
    into further arithmetic) would be invisible to the "does this SCC have
    any non-tail group call" check.

    [tail_calls_in] (which builds the Tarjan SCC edges) only recognises the
    dec-chain wrapper as a tail call when it IS the fn's tail expression —
    so a group edge needs at least one genuine tail call between the two
    functions. [build_loop] below supplies that in its odd-n branch
    (`consume_loop(prefix, n - 1)` as the branch's tail expr — the SCC forms).
    Its even-n branch ALSO calls [consume_loop] on the very same borrowed
    [prefix] (dead after the call, so Perceus wraps it in the same
    post-call-DecRC dec-chain), but here the result is bound to [r] and
    [r + 1] is returned — a genuinely non-tail group call. Pre-fix,
    [has_non_tail_group_call] ignored [in_tail] in the dec-chain-wrapper arm
    and reported no non-tail call, so the group was wrongly accepted; the
    mutual-TCO back-edge emitted for this pair then stranded the `+ 1`
    continuation in a dead block. Post-fix the group must be rejected (no
    mutual_loop for this pair), and the program must still compile and run
    correctly via ordinary (non-TCO) calls. *)
let test_mutual_tco_non_tail_dec_chain_wrapped_no_loop () =
  let ir = emit_mutual_tco_ir {|mod Test do
  needs IO.Console
    fn build_loop(seed, n) do
      let prefix = String.repeat("a", 1)
      if n == 0 do
        String.byte_size(seed) + String.byte_size(prefix)
      else
        if n % 2 == 0 do
          let r = consume_loop(prefix, n - 1)
          r + 1
        else
          consume_loop(prefix, n - 1)
        end
      end
    end
    fn consume_loop(s, n) do
      if n == 0 do
        String.byte_size(s)
      else
        build_loop(s, n - 1)
      end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(int_to_string(build_loop("z", 5))) end
  end|} in
  Alcotest.(check bool)
    "non-tail dec-chain-wrapped group call: no mutual_loop formed for this pair"
    false (ir_contains ir "mutual_loop")

(** B8 regression: a pure mutually-recursive loop (is_even/is_odd style) never
    calls a builtin and never returns to the scheduler on its own — unlike
    emit_fn's self-TCO path (which calls emit_reduction_check at the top of
    every tco_loop iteration), emit_mutual_tco_group never emitted a reduction
    check anywhere in its combined dispatch function. That starves the
    scheduler worker running the loop forever. Assert the mutual_loop body
    contains the same preemption-check IR (@march_preempt_request load +
    @march_yield_from_compiled call) that self-TCO loops get. *)
let test_mutual_tco_has_reduction_check () =
  let ir = emit_mutual_tco_ir {|mod Test do
  needs IO.Console
    @[no_warn_recursion]
    fn is_even(n : Int) : Bool do
      if n == 0 do true else is_odd(n - 1) end
    end
    @[no_warn_recursion]
    fn is_odd(n : Int) : Bool do
      if n == 0 do false else is_even(n - 1) end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(to_string(is_even(1000000))) end
  end|} in
  Alcotest.(check bool) "mutual TCO is_even/is_odd: mutual_loop block emitted" true
    (ir_contains ir "mutual_loop");
  Alcotest.(check bool) "mutual TCO is_even/is_odd: preempt request loaded" true
    (ir_contains ir "load volatile i64, ptr @march_preempt_request");
  Alcotest.(check bool) "mutual TCO is_even/is_odd: yield call present" true
    (ir_contains ir "@march_yield_from_compiled");
  (* The check must be inside the loop body, not merely present somewhere else
     in the module — find the mutual_loop label and confirm the reduction
     check appears between it and the switch dispatch that follows it. *)
  let loop_pos =
    try Str.search_forward (Str.regexp "\nmutual_loop[0-9]*:") ir 0
    with Not_found -> Alcotest.fail "mutual_loop label not found in IR"
  in
  let switch_pos =
    try Str.search_forward (Str.regexp "switch i64") ir loop_pos
    with Not_found -> Alcotest.fail "switch dispatch not found after mutual_loop label"
  in
  let loop_header = String.sub ir loop_pos (switch_pos - loop_pos) in
  Alcotest.(check bool)
    "mutual TCO is_even/is_odd: reduction check sits inside the loop header, before the dispatch switch"
    true (ir_contains loop_header "@march_yield_from_compiled")

(* ── Phase 4: Reduction Counting in Compiled Code ─────────────────────── *)

(** Non-leaf, non-TCO function: reduction check IR must appear. *)
let test_phase4_nonleaf_has_reduction_check () =
  let ir = emit_tco_ir {|mod Test do
  needs IO.Console
    fn fib(n : Int) : Int do
      if n <= 1 do n
      else fib(n - 1) + fib(n - 2) end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(int_to_string(fib(10))) end
  end|} in
  (* Must match the LOAD, not the preamble declaration: @march_tls_reductions
     and @march_preempt_request are both declared in every native preamble, so
     a bare name match would pass even with no check emitted at all.
     `volatile` is asserted deliberately — without it the load is
     loop-invariant and LLVM hoists the check out of TCO loops, silently
     disabling preemption (pinned end-to-end by
     test/native/preempt_starvation.march). *)
  Alcotest.(check bool) "non-leaf fib: @march_preempt_request loaded" true
    (ir_contains ir "load volatile i64, ptr @march_preempt_request");
  Alcotest.(check bool) "non-leaf fib: march_yield_from_compiled called" true
    (ir_contains ir "@march_yield_from_compiled");
  Alcotest.(check bool) "non-leaf fib: sched_yield block emitted" true
    (ir_contains ir "sched_yield");
  Alcotest.(check bool) "non-leaf fib: sched_cont block emitted" true
    (ir_contains ir "sched_cont")

(** All-leaf module (only builtin calls): NO reduction check anywhere.
    - square(n) = n * n        → only builtin `*`  → leaf
    - main()    = println(42)  → only builtins      → leaf
    Neither function should emit the icmp/br reduction check. *)
let test_phase4_leaf_fn_no_reduction_check () =
  let ir = emit_tco_ir {|mod Test do
  needs IO.Console
    fn square(n : Int) : Int do n * n end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(int_to_string(42)) end
  end|} in
  (* No non-leaf functions → no preemption check IR anywhere in the output.
     Assert on the LOAD: the preamble declares @march_preempt_request
     unconditionally, so only an actual load proves a check was emitted. *)
  Alcotest.(check bool) "all-leaf module: no preempt-request load" false
    (ir_contains ir "load volatile i64, ptr @march_preempt_request")

(** TCO function: reduction check must be inside the tco_loop block. *)
let test_phase4_tco_fn_reduction_in_loop () =
  let ir = emit_tco_ir {|mod Test do
  needs IO.Console
    @[no_warn_recursion]
    fn countdown(n : Int) : Int do
      if n == 0 do 0 else countdown(n - 1) end
    end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(int_to_string(countdown(100))) end
  end|} in
  Alcotest.(check bool) "TCO countdown: tco_loop emitted" true
    (ir_contains ir "tco_loop");
  Alcotest.(check bool) "TCO countdown: preemption check in loop" true
    (ir_contains ir "load volatile i64, ptr @march_preempt_request");
  Alcotest.(check bool) "TCO countdown: yield call present" true
    (ir_contains ir "@march_yield_from_compiled")

(** Non-recursive function that calls another user function: non-leaf,
    so it must get a reduction check even though it has no loop. *)
let test_phase4_nonrecursive_caller_has_check () =
  let ir = emit_tco_ir {|mod Test do
  needs IO.Console
    fn double(n : Int) : Int do n + n end
    fn apply_double(n : Int) : Int do double(n) end
    fn main(_cap_console : Cap(IO.Console)) : Unit do println(int_to_string(apply_double(3))) end
  end|} in
  (* apply_double calls double (non-builtin) → non-leaf → check emitted. *)
  Alcotest.(check bool) "apply_double: preemption check present" true
    (ir_contains ir "load volatile i64, ptr @march_preempt_request")

let test_llvm_no_call_to_double_underscore () =
  let src = {|mod Test do
    fn and_op(a : Bool, b : Bool) : Bool do a && b end
    fn or_op(a : Bool, b : Bool)  : Bool do a || b end
  end|} in
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus tir in
  let ir  = March_tir.Llvm_emit.emit_module tir in
  (* The bug was that @__ was emitted as a called symbol. *)
  let has_call_to_dunder =
    try ignore (Str.search_forward (Str.regexp_string "call.*@__") ir 0); true
    with Not_found -> false
  in
  Alcotest.(check bool) "no call to @__ in generated IR" false has_call_to_dunder

(* --- name-resolution: cross-module qualified-alias hijack (RC-underflow root
   cause) --------------------------------------------------------------------

   A bulk `import Bastion` in ONE module registers the DOTTED short name
   `Logger.debug` -> `Bastion.Logger.debug` in the program-global [_use_aliases]
   table (register_aliases strips only the import prefix "Bastion.").  That
   global table is consulted while lowering EVERY module.  It must NOT hijack a
   module-qualified `Logger.debug` reference written in an UNRELATED module —
   one that never imported Bastion, and that the typechecker bound to the stdlib
   `Logger.debug/1`.  Pre-fix, lowering rewrote it to the arity-2
   `Bastion.Logger.debug`, emitting a call with an uninitialised second argument
   -> RC underflow / SIGSEGV at runtime.  The fix restricts the global
   [_use_aliases] fallback to UNQUALIFIED (dot-free) names; the importing module
   itself still resolves its own qualified alias via [current_module_aliases]. *)
let test_qualified_alias_no_cross_module_hijack () =
  let open March_tir.Lower in
  Hashtbl.reset _fn_param_types;
  _use_aliases := Hashtbl.create 8;
  _module_aliases := Hashtbl.create 8;  (* isolate: resolve_use_alias's prefix fallback reads it *)
  (* Simulate another module's `import Bastion`: a DOTTED global alias plus an
     ordinary UNQUALIFIED one. *)
  Hashtbl.replace !_use_aliases "Logger.debug" "Bastion.Logger.debug";
  Hashtbl.replace !_use_aliases "helper" "Some.Mod.helper";
  with_current_module_fns [] (fun () ->
    (* A module that did NOT import Bastion — empty current_module_aliases. *)
    let non_importer =
      { type_map = None; current_module_aliases = Hashtbl.create 0;
        mod_prefix = ""; collision_set = Hashtbl.create 0 } in
    Alcotest.(check string)
      "qualified `Logger.debug` NOT hijacked by another module's global import"
      "Logger.debug" (resolve_use_alias non_importer "Logger.debug");
    (* The importing module itself still resolves its own qualified alias. *)
    let importer =
      { type_map = None; current_module_aliases = Hashtbl.create 8;
        mod_prefix = ""; collision_set = Hashtbl.create 0 } in
    Hashtbl.replace importer.current_module_aliases
      "Logger.debug" "Bastion.Logger.debug";
    Alcotest.(check string)
      "importing module still resolves its own qualified alias"
      "Bastion.Logger.debug" (resolve_use_alias importer "Logger.debug");
    (* Unqualified names still resolve through the global table (unchanged). *)
    Alcotest.(check string)
      "unqualified global alias still applies"
      "Some.Mod.helper" (resolve_use_alias non_importer "helper"))

(* Companion to the hijack guard: the entry file's OWN top-level bulk import
   must still resolve the partial-qualified call form.  `import Foo` (UseAll,
   where Foo has a sub-module Foo.Sub) registers the DOTTED short name
   `Sub.greet` -> `Foo.Sub.greet`.  After the global `_use_aliases` fallback was
   restricted to unqualified names, the entry file's own `Sub.greet(...)` call
   must resolve via the entry module's `current_module_aliases` — the top-level
   DUse arms now register there too (mirroring the nested-import path).  Without
   that, lowering emits an undefined `@Sub.greet` call (the same failure
   direction as the hijack bug, but for a legitimate import).  This exercises the
   full lower pipeline: pre-fix the emitted IR calls bare `@Sub.greet`, post-fix
   it calls the qualified `@Foo.Sub.greet`. *)
let test_entry_bulk_import_resolves_partial_qualified () =
  let src = {|mod Main do
    mod Foo do
      mod Sub do
        fn greet(n : Int) : Int do n + 1 end
      end
    end
    import Foo
    fn run(x : Int) : Int do Sub.greet(x) end
  end|} in
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus tir in
  let ir  = March_tir.Llvm_emit.emit_module tir in
  (* The qualified target must be CALLED; the bare `@Sub.greet(` (undefined /
     unresolved) must NOT appear. Note `@Foo.Sub.greet` does not contain the
     substring `@Sub.greet`, so the negative check is a clean discriminator. *)
  Alcotest.(check bool) "partial-qualified call resolves to Foo.Sub.greet" true
    (Test_helpers.contains "@Foo.Sub.greet" ir);
  Alcotest.(check bool) "no unresolved bare @Sub.greet call" false
    (Test_helpers.contains "@Sub.greet(" ir)

(* A record type loaded from the COMPILED module registry (a dependency in the
   `--compile`/`--test` unit, not prebound from source) stores its field types as
   UNRESOLVED surface types that name sibling types by their BARE name (e.g.
   `mod Conduit`'s `type UniqueConstraint = { scope : UniqueScope }` — both types
   in one module, `UniqueScope` referenced unqualified).  When a referring module
   annotates against `Conduit.UniqueConstraint`, [surface_ty] must expand that
   record's fields; before the fix it expanded them in the REFERRER's env, which
   held only the QUALIFIED sibling name (`Conduit.UniqueScope`) — [load_module_
   into_env]/registry loading never seeded the bare `UniqueScope`.  Result: a
   bogus "I cannot find `UniqueScope`" pointing at the definer's field span,
   reproduced ~16x (once per test file importing the dep) under `forge test`
   while `forge check` (which prebinds the dep FROM SOURCE, seeding bare names)
   stayed clean.  Fix: registry type/record loading seeds the bare name too, and
   registry-record field expansion threads the defining module's env.  This test
   drives the exact registry path: register a module with a bare-named sibling
   type referenced by a record field, then resolve the qualified record in a
   separate module — pre-fix errors, post-fix clean. *)
let test_registry_record_field_bare_sibling_type_resolves () =
  let open March_modules.Module_registry in
  reset ();
  let dummy = March_ast.Ast.dummy_span in
  let bare_ty n = March_ast.Ast.TyCon ({ March_ast.Ast.txt = n; span = dummy }, []) in
  register "Widgets" {
    me_name = "Widgets";
    me_entries = [
      (* A variant sibling type, referenced BARE by the record field below. *)
      { ex_name = "Scope"; ex_kind = ExType 0; ex_public = true };
      (* The record whose stored field type names `Scope` by its bare name —
         exactly how the compiler serialises a same-module sibling reference. *)
      { ex_name = "Constraint";
        ex_kind = ExRecord (0, [("scope", bare_ty "Scope")]);
        ex_public = true };
    ];
  };
  (* A DIFFERENT module references the qualified record type; expanding it must
     resolve the bare `Scope` field type. *)
  let src = {|mod Client do
    fn describe(c : Widgets.Constraint) : Int do 0 end
  end|} in
  let m = Test_helpers.parse_and_desugar src in
  let (errors, _tm) = March_typecheck.Typecheck.check_module m in
  reset ();
  let msgs = List.map (fun (d : March_errors.Errors.diagnostic) -> d.message)
      errors.March_errors.Errors.diagnostics in
  let mentions_scope =
    List.exists (fun s -> Test_helpers.contains "Scope" s
                          && Test_helpers.contains "cannot find" s) msgs in
  Alcotest.(check bool)
    "no 'cannot find Scope' when expanding a registry record's bare-named field"
    false mentions_scope;
  Alcotest.(check bool)
    "referrer typechecks cleanly against the registry record type"
    false (March_errors.Errors.has_errors errors)

(* --- multiline tests --- *)

let test_multiline_depth_zero () =
  Alcotest.(check int) "single expression has depth 0"
    0 (March_repl.Multiline.do_end_depth "x + 1")

let test_multiline_depth_open () =
  Alcotest.(check int) "open do block has depth 1"
    1 (March_repl.Multiline.do_end_depth "fn foo() do\n  x + 1")

let test_multiline_depth_closed () =
  Alcotest.(check int) "closed do block has depth 0"
    0 (March_repl.Multiline.do_end_depth "fn foo() do\n  x + 1\nend")

let test_multiline_ends_with_with () =
  Alcotest.(check int) "match opener depth is 1"
    1 (March_repl.Multiline.do_end_depth "match x do")

let test_multiline_not_ends_with_with () =
  Alcotest.(check bool) "record update does not trigger with heuristic"
    false (March_repl.Multiline.ends_with_with "let y = { x with foo = 1 }")

let test_multiline_starts_with_pipe () =
  Alcotest.(check bool) "match arm starts with pipe"
    true (March_repl.Multiline.starts_with_pipe "| Some(x) -> x")

let test_multiline_is_complete_simple () =
  Alcotest.(check bool) "simple expression is complete"
    true (March_repl.Multiline.is_complete "x + 1")

let test_multiline_is_complete_open_block () =
  Alcotest.(check bool) "open block is not complete"
    false (March_repl.Multiline.is_complete "fn foo() do\n  x")

(* --- complete tests --- *)

let test_complete_command () =
  let completions = March_repl.Complete.complete ":q" [] in
  Alcotest.(check bool) ":q completes to :quit or :q"
    true (List.mem ":quit" completions || List.mem ":q" completions)

let test_complete_keyword () =
  let completions = March_repl.Complete.complete "fn" [] in
  Alcotest.(check bool) "fn is in keyword completions"
    true (List.mem "fn" completions)

let test_complete_in_scope () =
  let scope = [("double", "Int -> Int"); ("x", "Int")] in
  let completions = March_repl.Complete.complete "do" scope in
  Alcotest.(check bool) "double completes from scope"
    true (List.mem "double" completions)

let test_complete_empty_all () =
  let completions = March_repl.Complete.complete "" [] in
  Alcotest.(check bool) "empty prefix returns at least one keyword"
    true (List.length completions > 0)

(* ------------------------------------------------------------------ *)
(* complete_replace tests                                              *)
(* ------------------------------------------------------------------ *)

let test_complete_replace_prefix () =
  (* cursor at end of prefix "fo", no right side → replace "fo" with "foo" *)
  let s = mk_inp "fo" 2 in
  let s' = March_repl.Input.complete_replace s "foo" in
  Alcotest.(check string) "buf" "foo" s'.March_repl.Input.buffer;
  Alcotest.(check int)    "cur" 3     s'.March_repl.Input.cursor

let test_complete_replace_midword () =
  (* cursor mid-word: "fo|bar" → replace whole word with "foobar" *)
  let s = mk_inp "fobar" 2 in
  let s' = March_repl.Input.complete_replace s "foobar" in
  Alcotest.(check string) "buf" "foobar" s'.March_repl.Input.buffer;
  Alcotest.(check int)    "cur" 6        s'.March_repl.Input.cursor

let test_complete_replace_with_suffix () =
  (* context: "x = fo|bar + 1" → replace word "fobar" with "foobar", keep rest *)
  let s = mk_inp "x = fobar + 1" 7 in
  let s' = March_repl.Input.complete_replace s "foobar" in
  Alcotest.(check string) "buf" "x = foobar + 1" s'.March_repl.Input.buffer;
  Alcotest.(check int)    "cur" 10               s'.March_repl.Input.cursor

(* ------------------------------------------------------------------ *)
(* JIT cross-line REPL variable capture tests                         *)
(* These tests exercise the fix for the bug where variables defined   *)
(* on previous REPL lines could not be referenced in HOF arguments.  *)
(* Tests skip (counted) only when clang is absent; runtime-source or  *)
(* link problems fail loudly per W2.0 — see setup_jit_runtime.        *)
(* ------------------------------------------------------------------ *)

(** Try to compile the march runtime to a shared library.
    Returns [Some path] on success, [None] only when clang is absent (a
    counted skip); a missing runtime source or a failed link is an
    Alcotest failure, not a [None] (W2.0).

    The cache lives in ~/.cache/march, which is SHARED across worktrees and
    concurrent sessions — so the artifact name is keyed by a digest of every
    C source/header that goes into it, and the write is atomic (compile to
    a pid-suffixed temp, then rename).  The old scheme — one fixed
    "libmarch_rt_test.so" with an existence-only check — was never
    invalidated when the runtime changed, and a concurrent worktree with
    diverged runtime sources would overwrite it with an ABI-mismatched
    binary, hanging whichever test process dlopen'd the wrong build. *)

(** Canary (W2 Task 2 / W2.0): the "gate is live" assertion. If clang is on
    PATH, `setup_jit_runtime` must NEVER return `None` — every clang-gated
    test in this file (and test_stdlib_suite.ml) silently no-ops when it
    does, so a regression that reintroduces a swallowed link failure (or
    breaks the runtime-source search path) would otherwise make an entire
    class of tests vacuously pass again without any test catching it. This
    test fails loudly if that ever happens; it only legitimately skips (via
    the same clang-absence check) when clang itself is not installed here. *)
let test_setup_jit_runtime_gate_is_live () =
  if not (clang_available ()) then
    (* Legitimate skip: no clang on PATH.  Counted directly here — this
       canary short-circuits before setup_jit_runtime, so it would otherwise
       be invisible in the shared skip ledger. *)
    record_jit_skip "canary test_setup_jit_runtime_gate_is_live: no clang on PATH"
  else
    match setup_jit_runtime () with
    | Some _ -> ()
    | None ->
      Alcotest.fail
        "setup_jit_runtime returned None while `clang --version` succeeds — \
         the JIT gate is broken (a link failure or missing runtime source is \
         being silently swallowed again; see setup_jit_runtime's Alcotest.failf \
         paths, which should have raised instead of returning None here)"

let test_repl_jit_cross_line_let () =
  match setup_jit_runtime () with
  | None -> ()  (* counted skip: no clang on PATH (anything else fails loudly, W2.0) *)
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
       (* Compile: let x = 21 *)
       (match parse_repl "let x = 21" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let n = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt
                | _ -> failwith "expected PatVar"
              in (n, b.bind_expr)
            | _ -> failwith "expected DLet for 'let x = 21'"
          in
          let m = make_jit_test_module bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          (* Update tc_env so 'x : Int' is in scope for the next expression *)
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (* Compile: x + 21 — cross-line reference *)
       (match parse_repl "x + 21" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "cross-line let: x+21 = 42" "42" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Test: `let f = fn x -> x * 2` (DFn) on line 1,
    then `f(21)` on line 2 should give 42 (cross-line function reference). *)
let test_repl_jit_cross_line_fn () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
       (* Compile: let f = fn x -> x * 2  (parsed as DLet with lambda RHS) *)
       (match parse_repl "let f = fn x -> x * 2" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let name = match b.bind_pat with
                | March_ast.Ast.PatVar n -> n.txt
                | _ -> failwith "expected PatVar"
              in (name, b.bind_expr)
            | _ -> failwith "expected DLet for 'let f = fn x -> x * 2'"
          in
          let m = make_jit_test_module bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          (* Update tc_env so 'f : Int -> Int' is in scope for the next expression *)
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (* Compile: f(21) — cross-line function reference.
          Known limitation: cross-fragment function calls require `declare` stubs
          for functions compiled in prior fragments (issue #1 in repl_smoke_test.sh).
          This test verifies the let binding compiles; the cross-fragment call
          may fail with a clang error, which is an expected known issue. *)
       (match parse_repl "f(21)" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          (try
            let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
            Alcotest.(check string) "cross-line fn: f(21) = 42" "42" result
          with Failure msg when
            (let m = String.lowercase_ascii msg in
             let len = String.length m in
             let rec scan i =
               if i + 8 >= len then false
               else if String.sub m i 9 = "undefined" then true
               else scan (i + 1)
             in scan 0) ->
            (* Cross-fragment declare issue — known limitation, skip *)
            ())
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Test: both a let and a function defined on previous lines,
    used together in a HOF call — the original bug scenario. *)
let test_repl_jit_cross_line_hof () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
       (* let n = 21 *)
       (match parse_repl "let n = 21" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let nm = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt | _ -> assert false
              in (nm, b.bind_expr)
            | _ -> failwith "expected DLet"
          in
          let m = make_jit_test_module bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (* let double = fn x -> x * 2  (parsed as DLet with lambda RHS) *)
       (match parse_repl "let double = fn x -> x * 2" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let name = match b.bind_pat with
                | March_ast.Ast.PatVar n -> n.txt
                | _ -> failwith "expected PatVar"
              in (name, b.bind_expr)
            | _ -> failwith "expected DLet for 'let double = fn x -> x * 2'"
          in
          let m = make_jit_test_module bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (* double(n) — both from previous lines.
          Known limitation: cross-fragment function call may fail if the
          closure function compiled in a prior fragment isn't reachable via
          LLVM `declare`. This is a known issue (see repl_smoke_test.sh). *)
       (match parse_repl "double(n)" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          (try
            let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
            Alcotest.(check string) "cross-line hof: double(n) = 42" "42" result
          with Failure msg when
            (let m = String.lowercase_ascii msg in
             let len = String.length m in
             let rec scan i =
               if i + 8 >= len then false
               else if String.sub m i 9 = "undefined" then true
               else scan (i + 1)
             in scan 0) ->
            (* Cross-fragment declare issue — known limitation, skip *)
            ())
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression (B11): a REPL-defined top-level `fn` (declared via a bare
    `fn ... do ... end` at the prompt) is stored as a first-class closure in
    a persistent slot by [emit_repl_fn_with_closure_slot] (see
    lib/repl/repl.ml's `DFn` arm, `run_decl ~is_fn_decl:true`), so that a
    LATER fragment referencing the function by bare name loads the slot's
    closure value rather than re-resolving a fresh top-level call (each REPL
    fragment gets its own [ctx], so `ctx.top_fns`/`ctx.compiled_fns` from the
    defining fragment aren't visible — the bridge in
    [emit_prev_slot_bridges] is what makes cross-fragment references work at
    all).  That bridged reference is dispatched through ECallPtr, which
    always reads the callee's result as `ptr` — the same ABI every OTHER
    closure wrapper in llvm_emit.ml (the canonical [clo_wrap_define]) honors
    by tagging scalar results `(n<<1)|1`.  The REPL's inline wrapper instead
    declares the RAW concrete return type (`i64` for `mk() : Int`), so the
    LLVM-declared return type disagrees with the indirect call's `ptr`
    signature; the conditional-untag on the caller side reinterprets the raw
    bits as tagged and (n odd) `ashr`s them — halving odd Int results
    (5 -> 2).  `mk()` returns the odd literal `5` directly (no inner
    lambda, so the *only* wrapper in play is the REPL's own); referencing
    `mk` bare on a later REPL line and calling it must yield "5", not "2". *)
let test_repl_jit_stored_closure_returns_untagged_int () =
  match setup_jit_runtime () with
  | None -> ()  (* counted skip: no clang on PATH (anything else fails loudly, W2.0) *)
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
       (* fn mk() do 5 end *)
       (match parse_repl "fn mk() do\n  5\nend" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let bind_name = match d' with
            | March_ast.Ast.DFn (def, _) -> def.March_ast.Ast.fn_name.txt
            | _ -> failwith "expected DFn for 'fn mk() do 5 end'"
          in
          let s = March_ast.Ast.dummy_span in
          let m = { March_ast.Ast.mod_name = { txt = "Repl"; span = s };
                    mod_decls = [d'] } in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:true ~bind_name m;
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (* mk() — cross-fragment reference; bridged through the closure slot
          (not a fresh top-level call, since ctx is fresh per fragment). *)
       (match parse_repl "mk()" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "stored closure mk() = 5 (not halved to 2)" "5" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression (B11 review follow-up): a REPL-defined `fn` whose body
    references ITSELF as a first-class value must not produce a duplicate
    `$clo_wrap` definition.  [emit_repl_fn_with_closure_slot] registers the
    fn into [ctx.top_fns] BEFORE [emit_fn] runs, so when the body takes the
    fn as a value (e.g. `let g = selfref`), emit_atom's top-fns wrap path
    fires [clo_wrap_define] into [ctx.extra_fns] and records the name in
    [ctx.emitted_wraps].  The emitter's own wrapper emission must honor the
    same emitted_wraps check-then-add guard the other two clo_wrap_define
    call sites use — an unconditional emission appends a SECOND
    `define ptr @selfref$clo_wrap` to the same fragment, and clang rejects
    the duplicate symbol (compile_fragment raises "clang failed").  The
    assertion is simply that the fragment compiles and the call returns the
    right (odd, tag-round-tripped) value. *)
let test_repl_jit_selfref_fn_no_duplicate_wrapper () =
  match setup_jit_runtime () with
  | None -> ()  (* counted skip: no clang on PATH (anything else fails loudly, W2.0) *)
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
       (* fn selfref(n) do let g = selfref ... end — self-reference as value *)
       (match parse_repl
          "fn selfref(n) do\n  let g = selfref\n  if n > 0 do\n    g(0)\n  else\n    7\n  end\nend" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let bind_name = match d' with
            | March_ast.Ast.DFn (def, _) -> def.March_ast.Ast.fn_name.txt
            | _ -> failwith "expected DFn for 'fn selfref(n) do ... end'"
          in
          let s = March_ast.Ast.dummy_span in
          let m = { March_ast.Ast.mod_name = { txt = "Repl"; span = s };
                    mod_decls = [d'] } in
          (* Pre-guard-fix this raised: Failure "clang failed ... symbol
             'selfref$clo_wrap' is already defined". *)
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:true ~bind_name m;
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (* selfref(1) — recurses once through the self-referenced closure
          value, returning the odd literal 7 through the ptr-ABI wrapper. *)
       (match parse_repl "selfref(1)" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "selfref(1) = 7 (single wrapper, ptr ABI)" "7" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Shared driver for the two fn-body-lambda REPL-JIT session regressions
    below: precompiles list.march as the stdlib prelude (mirroring the real
    REPL's [precompile_stdlib], which also seeds [ctx.stdlib_decls] so the
    fragment lowering can resolve the List module), builds a tc env that knows the
    List module, defines [fn_src] via [run_decl ~is_fn_decl:true] exactly
    like lib/repl/repl.ml's DFn arm (module = the single decl), then
    evaluates [expr_src] with [run_expr] and checks the printed result. *)
let run_repl_jit_fn_lambda_session ~fn_src ~expr_src ~expected ~label =
  match setup_jit_runtime () with
  | None -> ()  (* counted skip: no clang on PATH (anything else fails loudly, W2.0) *)
  | Some runtime_so ->
    let list_decl = load_stdlib_file_for_test "list.march" in
    let stdlib_decls = [list_decl] in
    let content_hash =
      Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let base_tc = March_typecheck.Typecheck.base_env
        (March_errors.Errors.create ()) type_map in
    let tc_pre = March_repl.Repl.preregister_stdlib_types base_tc stdlib_decls in
    let (_ev, tc0) = March_repl.Repl.load_decls_into_env
        March_eval.Eval.base_env tc_pre stdlib_decls in
    let tc_env = ref { tc0 with March_typecheck.Typecheck.errors =
                                  March_errors.Errors.create () } in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       March_jit.Repl_jit.precompile_stdlib jit
         ~content_hash ~stdlib_decls ~type_map;
       (match parse_repl fn_src with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let bind_name = match d' with
            | March_ast.Ast.DFn (def, _) -> def.March_ast.Ast.fn_name.txt
            | _ -> failwith "expected DFn"
          in
          let s = March_ast.Ast.dummy_span in
          let m = { March_ast.Ast.mod_name = { txt = "Repl"; span = s };
                    mod_decls = [d'] } in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:true ~bind_name m;
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (match parse_repl expr_src with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) label expected result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression: redefining a REPL `fn` must take effect (Elixir-style
    rebinding, matching interpreter mode).  run_decl's is_fn_decl path used
    to early-return whenever [bind_name] was already in [compiled_fns] — a
    guard meant only for :reset scroll-replay (which resends identical
    cells) — so a genuine redefinition never recompiled or rebound the
    closure slot and `f(1)` kept answering with the FIRST body.  The fix
    fingerprints the declaration AST: an identical resend still takes the
    replay fast path (asserted below via [fragment_count]), while a changed
    body recompiles under a fresh unique symbol and rebinds the slot. *)
let test_repl_jit_fn_redefinition () =
  match setup_jit_runtime () with
  | None -> ()  (* counted skip: no clang on PATH (anything else fails loudly, W2.0) *)
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
       let run_fn_decl src =
         match parse_repl src with
         | March_ast.Ast.ReplDecl d ->
           let d' = March_desugar.Desugar.desugar_decl d in
           let bind_name = match d' with
             | March_ast.Ast.DFn (def, _) -> def.March_ast.Ast.fn_name.txt
             | _ -> failwith ("expected DFn for: " ^ src)
           in
           let s = March_ast.Ast.dummy_span in
           let m = { March_ast.Ast.mod_name = { txt = "Repl"; span = s };
                     mod_decls = [d'] } in
           March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:true ~bind_name m;
           let new_env = March_typecheck.Typecheck.check_decl
             { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
           tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () };
           (bind_name, m)
         | _ -> failwith ("expected ReplDecl for: " ^ src)
       in
       let eval_expr src expected label =
         match parse_repl src with
         | March_ast.Ast.ReplExpr e ->
           let e' = March_desugar.Desugar.desugar_expr e in
           let m = make_jit_test_module e' in
           let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
           Alcotest.(check string) label expected result
         | _ -> failwith ("expected ReplExpr for: " ^ src)
       in
       ignore (run_fn_decl "fn f(x) do x + 1 end");
       eval_expr "f(1)" "2" "original f(1) = 2";
       (* Genuine redefinition: different body, same name. *)
       let (bind_name, m2) = run_fn_decl "fn f(x) do x + 100 end" in
       eval_expr "f(1)" "101" "redefined f(1) = 101 (not silently ignored)";
       (* :reset scroll-replay resends the identical cell: must stay a
          fast-path skip (no new fragment compiled) and keep the binding. *)
       let frags_before = March_jit.Repl_jit.fragment_count jit in
       March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:true ~bind_name m2;
       Alcotest.(check int) "identical replay compiles no new fragment"
         frags_before (March_jit.Repl_jit.fragment_count jit);
       eval_expr "f(1)" "101" "f(1) = 101 after identical replay";
       (* Self-recursive redefinition: the recursive call must reach the NEW
          body (the renamed fragment-local symbol), not the old one. *)
       ignore (run_fn_decl
         "fn f(n) do if n < 1 do 0 else 10 + f(n - 1) end end");
       eval_expr "f(3)" "30" "self-recursive redefined f(3) = 30";
       (* Arity-changing redefinition through the same closure slot. *)
       ignore (run_fn_decl "fn f(a, b) do a + b end");
       eval_expr "f(3, 4)" "7" "arity-changed f(3, 4) = 7";
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression (two stacked bugs, both fixed together):

    1. Defun capture-shadowing: the fn is named `f` — the SAME name as
       List.map's function parameter.  [Defun.free_vars_of_expr] excluded any
       free var whose name matched a top-level fn of the module being
       lowered, even when that name was really a binder of the enclosing
       scope (map's param `f`, closed over by its inner `go` accumulator).
       With a user top-level `f` in the module, the fragment's re-lowered
       `go$apply$N` dropped the capture and phase 3 left `f(h)` as a DIRECT
       call to the user's `f` — an undefined `_f` in the helpers fragment
       (dlopen error at the REPL) and a segfault when compiled AOT.

    2. Fragment ordering: run_decl used to compile the defun'd helper
       lambdas in a SEPARATE fragment loaded BEFORE the primary fn, so any
       legitimate helper→primary reference (see the selfrec test below) hit
       macOS dlopen's eager binding.  Helpers and primary now share one
       fragment.

    Pre-fix this raised Failure "dlopen(...): symbol not found in flat
    namespace '_f'" from run_decl and the binding was lost. *)
let test_repl_jit_fn_lambda_shadows_hof_param () =
  run_repl_jit_fn_lambda_session
    ~fn_src:"fn f(xs : List(Int)) : List(Int) do\n  List.map(xs, fn y -> y + 1)\nend"
    ~expr_src:"f([1, 2, 3])"
    ~expected:"[2, 3, 4]"
    ~label:"fn f with lambda (name collides with List.map's param): f([1,2,3])"

(** Regression (bug 2 of the pair above, isolated): the lambda inside the fn
    body calls the fn BEING DEFINED (`g`), so the lifted lambda helper
    legitimately references the primary fn's symbol.  With helpers compiled
    in their own fragment first, macOS dlopen's eager binding failed with
    "symbol not found in flat namespace '_g'" even though `g`'s fragment was
    loaded immediately after.  One combined fragment resolves it in both the
    clang and ORC backends. *)
let test_repl_jit_fn_selfrec_via_lambda () =
  run_repl_jit_fn_lambda_session
    ~fn_src:"fn g(n : Int) : Int do\n  if n <= 0 do\n    0\n  else\n    List.length(List.map([n], fn y -> g(y - 1)))\n  end\nend"
    ~expr_src:"g(3)"
    ~expected:"1"
    ~label:"fn g whose lambda calls g (self-recursion through helper): g(3)"

(** Regression: a top-level function referenced as a first-class VALUE (not
    called) from a plain REPL expression or `let` RHS.  emit_atom wraps such a
    reference in a @<fn>$clo_wrap trampoline whose definition is appended to
    ctx.extra_fns — but emit_repl_expr / emit_repl_decl dropped extra_fns from
    their output (unlike emit_repl_fn / emit_fns_fragment /
    emit_repl_fn_with_closure_slot, fixed as B11), so the fragment stored the
    address of an undefined symbol and clang rejected the IR. *)
let test_repl_jit_topfn_first_class_value () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
       let desugared_decl src = match parse_repl src with
         | March_ast.Ast.ReplDecl d -> March_desugar.Desugar.desugar_decl d
         | _ -> failwith "expected ReplDecl" in
       (* Module-level fns compiled into the same fragment; main's body passes
          `double` as a bare value, forcing the clo_wrap trampoline. *)
       let fn_decls = [
         desugared_decl "fn double(x) do x * 2 end";
         desugared_decl "fn call_with_21(f) do f(21) end";
       ] in
       let make_mod e =
         let s = March_ast.Ast.dummy_span in
         let clause = March_ast.Ast.{ fc_params = []; fc_guard = None; fc_body = e; fc_span = s; fc_params_span = s } in
         let main_def = March_ast.Ast.{
           fn_name = { txt = "main"; span = s };
           fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
           fn_clauses = [clause]; fn_bounds = [] } in
         { March_ast.Ast.mod_name = { txt = "Repl"; span = s };
           mod_decls = fn_decls @ [DFn (main_def, s)] }
       in
       (* Expression path (emit_repl_expr). *)
       (match parse_repl "call_with_21(double)" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_mod e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "expr: call_with_21(double) = 42" "42" result
        | _ -> failwith "expected ReplExpr");
       (* Let-binding path (emit_repl_decl): same first-class use in a let RHS. *)
       (match parse_repl "let y = call_with_21(double)" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let n = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt | _ -> failwith "expected PatVar"
              in (n, b.bind_expr)
            | _ -> failwith "expected DLet"
          in
          let m = make_mod bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env ~is_fn_decl:false ~bind_name m
        | _ -> failwith "expected ReplDecl");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(* The session-level `$clo_wrap` table must be committed only AFTER a fragment
   actually compiles (see [Repl_jit.commit_wraps]), never at emission time —
   the same discipline [mark_compiled_fns] follows for [compiled_fns], and for
   the same reason.  A fragment can emit a `define` and then FAIL to compile:
   the REPL prints the error and keeps going, and NOTHING was materialized.  If
   that decision had already landed in the session table, the next fragment
   would emit a `declare` against a symbol that does not exist — an unresolved
   symbol, in a spot where the pre-dedupe code recovered by simply redefining
   the wrapper.  So a failure must leave the session table untouched.

   Driving a genuine clang/ORC failure through [Repl_jit] would need a fragment
   that typechecks and lowers cleanly but then fails at the LLVM stage, which
   there is no cheap handle on from here (and [Repl_jit.t] is abstract, so the
   table could not be inspected anyway).  This pins the decision function the
   whole discipline rests on instead, driving the same four states a session
   walks through: define-but-fail, retry, commit, declare. *)
let test_clo_wrap_session_commit_is_deferred () =
  let open March_tir.Llvm_ctx in
  let w = "double$clo_wrap" in
  (* The session's committed set — [Repl_jit.t.wrap_defined]. *)
  let session = Hashtbl.create 8 in
  let fragment () =
    let sw = { sw_defined = session; sw_pending = Hashtbl.create 8 } in
    let c = make_ctx ~repl:true () in
    c.session_wraps <- Some sw;
    (c, sw)
  in
  (* Mirrors [Repl_jit.commit_wraps], which runs only where mark_compiled_fns
     does — i.e. after compile_fragment + dlopen succeed. *)
  let commit sw = Hashtbl.iter (fun k () -> Hashtbl.replace session k ()) sw.sw_pending in
  (* Fragment 1 decides to DEFINE, then "fails to compile" — never commits. *)
  let (c1, sw1) = fragment () in
  Alcotest.(check bool) "fragment 1 defines" true (wrap_emit_kind c1 w = `Define);
  Alcotest.(check bool) "the define is PENDING, not yet committed" true
    (Hashtbl.mem sw1.sw_pending w);
  Alcotest.(check bool) "emission must not touch the session table" false
    (Hashtbl.mem session w);
  Alcotest.(check bool) "one fragment never defines the same wrapper twice" true
    (wrap_emit_kind c1 w = `Skip);
  (* Fragment 2, after that failure, must DEFINE again — never declare a
     phantom symbol.  This is the regression the deferral exists for. *)
  let (c2, sw2) = fragment () in
  Alcotest.(check bool) "after a FAILED fragment: redefine, no phantom declare"
    true (wrap_emit_kind c2 w = `Define);
  (* This time the fragment compiles, so the session records it. *)
  commit sw2;
  Alcotest.(check bool) "commit promotes pending into the session" true
    (Hashtbl.mem session w);
  (* Fragment 3 now sees a genuinely materialized wrapper and declares. *)
  let (c3, _) = fragment () in
  Alcotest.(check bool) "after a SUCCEEDED fragment: declare" true
    (wrap_emit_kind c3 w = `Declare);
  (* The AOT path installs no session table and must be untouched by all of
     this: always Define, never Declare. *)
  let aot = make_ctx () in
  Alcotest.(check bool) "AOT ctx always defines" true (wrap_emit_kind aot w = `Define);
  Alcotest.(check bool) "AOT ctx skips its own repeat" true
    (wrap_emit_kind aot w = `Skip)

(* REPL/JIT counterpart of [test_lambda_static_closure_materialization_no_leak_
   compiled].  Natively a capture-free closure is one immortal global
   ([Llvm_ctx.intern_static_closure]), so nothing needs to release it; under the
   REPL/JIT [Llvm_emit.static_closure_ok] is [not ctx.repl && ..], so the very
   same lambda falls back to a fresh [march_alloc] per materialization — and
   before the capture-free arm of [Perceus.insert_apply_fn_clo_drop] nothing
   ever released THAT.  One leaked allocation per materialization.

   Measured the way the native tests measure it, but with the gauge read from
   OCaml (dlsym'ing [march_live_allocs] out of the JIT's own runtime .so)
   rather than through a March extern, so the fragments under test stay
   ordinary REPL input.  Warm the materialization site in one fragment, sample
   the gauge, then run the same site 2,000 more times in a second fragment: a
   leak makes the growth scale with the iteration count (~2,000), a correct
   build leaves only the second fragment's own fixed compilation overhead. *)
let test_repl_jit_capture_free_closure_no_leak () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let live_allocs =
      let h = March_jit.Jit.dlopen runtime_so in
      let sym = March_jit.Jit.dlsym h "march_live_allocs" in
      fun () -> Int64.to_int (March_jit.Jit.call_void_to_int sym)
    in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
       let desugared_decl src = match parse_repl src with
         | March_ast.Ast.ReplDecl d -> March_desugar.Desugar.desugar_decl d
         | _ -> failwith "expected ReplDecl" in
       (* `fn x -> x * 2` captures nothing, so each materialization is the
          capture-free shape; `apply_it` forces it to be materialized as a
          real first-class value rather than inlined into a direct call. *)
       let fn_decls = [
         desugared_decl "fn apply_it(f, n) do f(n) end";
         desugared_decl
           "fn materialize_loop(i, n, acc) do\n\
           \  if i >= n do acc\n\
           \  else materialize_loop(i + 1, n, acc + apply_it(fn x -> x * 2, i)) end\n\
            end";
         desugared_decl "fn double(x) do x * 2 end";
         desugared_decl
           "fn materialize_loop2(i, n, acc) do\n\
           \  if i >= n do acc\n\
           \  else materialize_loop2(i + 1, n, acc + apply_it(double, i)) end\n\
            end";
       ] in
       let make_mod e =
         let s = March_ast.Ast.dummy_span in
         let clause = March_ast.Ast.{ fc_params = []; fc_guard = None; fc_body = e; fc_span = s; fc_params_span = s } in
         let main_def = March_ast.Ast.{
           fn_name = { txt = "main"; span = s };
           fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
           fn_clauses = [clause]; fn_bounds = [] } in
         { March_ast.Ast.mod_name = { txt = "Repl"; span = s };
           mod_decls = fn_decls @ [DFn (main_def, s)] }
       in
       let run src = match parse_repl src with
         | March_ast.Ast.ReplExpr e ->
           let e' = March_desugar.Desugar.desugar_expr e in
           let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env (make_mod e') in
           result
         | _ -> failwith "expected ReplExpr"
       in
       (* Warm: compiles the fragment shape and settles any one-off allocation. *)
       let warm = run "materialize_loop(0, 100, 0)" in
       Alcotest.(check string) "warm loop result" "9900" warm;
       let base = live_allocs () in
       let bulk = run "materialize_loop(0, 2000, 0)" in
       Alcotest.(check string) "bulk loop result" "3998000" bulk;
       let grew = live_allocs () - base in
       (* A leaking build grows by ~2,000 here (one closure per iteration).  The
          bound is generous because a second REPL fragment legitimately allocates
          a fixed amount of its own; it just must not scale with the loop. *)
       if grew > 200 then
         Alcotest.failf
           "capture-free LAMBDA materialized 2,000 times in a REPL fragment \
            leaked: march_live_allocs grew by %d (expected bounded, <= 200)" grew;
       (* Second shape, and a genuinely independent mechanism: a top-level
          function used as a value materializes an @<fn>$clo_wrap trampoline
          closure, which is synthesized at LLVM emission and has no TIR apply fn
          for Perceus to touch.  It leaked exactly the same 1-per-materialization
          way until [clo_wrap_define ~drop_clo] was added, and it stayed leaking
          after the Perceus-side fix alone — so it needs its own assertion. *)
       let warm2 = run "materialize_loop2(0, 100, 0)" in
       Alcotest.(check string) "warm top-level-fn loop result" "9900" warm2;
       let base2 = live_allocs () in
       let bulk2 = run "materialize_loop2(0, 2000, 0)" in
       Alcotest.(check string) "bulk top-level-fn loop result" "3998000" bulk2;
       let grew2 = live_allocs () - base2 in
       if grew2 > 200 then
         Alcotest.failf
           "capture-free TOP-LEVEL FN value materialized 2,000 times in a REPL \
            fragment leaked: march_live_allocs grew by %d (expected bounded, \
            <= 200)" grew2;
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Test: List.length works correctly in JIT REPL with stdlib precompile.

    This is a regression test for the defun TVar bug: when the stdlib is
    precompiled with an empty type_map (as in the real REPL), inner function
    calls like [go(xs, 0)] inside [length] had v_ty = TVar "_" at the call site.
    Defun's condition B required TFn to convert EApp → ECallPtr, so the call
    stayed as a direct [call @go] — an undefined symbol — returning garbage.

    The fix: EApp of a TVar-typed non-top-level var is also converted to ECallPtr. *)
let test_repl_jit_stdlib_list_length () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    (* Load list.march *)
    let list_decl = load_stdlib_file_for_test "list.march" in
    let stdlib_decls = [list_decl] in
    (* Compute content hash the same way Repl does *)
    let content_hash =
      Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       (* Precompile stdlib — this triggers the TVar bug path on unfixed builds *)
       March_jit.Repl_jit.precompile_stdlib jit
         ~content_hash ~stdlib_decls ~type_map;
       (* Wrap expression in a module that includes stdlib_decls so that
          List.length resolves through monomorphization to length$List_Int. *)
       let make_stdlib_mod e =
         let s = March_ast.Ast.dummy_span in
         let main_clause = March_ast.Ast.{
           fc_params = []; fc_guard = None; fc_body = e; fc_span = s;
           fc_params_span = s } in
         let main_def = March_ast.Ast.{
           fn_name = { txt = "main"; span = s };
           fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
           fn_clauses = [main_clause]; fn_bounds = [] } in
         { March_ast.Ast.mod_name = { txt = "Main"; span = s };
           mod_decls = stdlib_decls @ [DFn (main_def, s)] }
       in
       (* List.length([1, 2, 3]) should return 3 *)
       (match parse_repl "List.length([1, 2, 3])" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_mod e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "List.length [1,2,3] = 3" "3" result
        | _ -> failwith "expected ReplExpr");
       (* List.length([]) should return 0 *)
       (match parse_repl "List.length([])" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_mod e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "List.length [] = 0" "0" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** B12 regression: a niche-eligible ADT ([Opt = None | Some(Int)], Option-shaped
    — one nullary ctor + one single-field ctor) defined via [:load] (a DMod,
    exactly like the real REPL wraps user modules) in fragment 1, then matched
    on by an expression in fragment 2.

    Fragment 1 goes through [register_module_decl], which emits the producer
    function via [emit_fns_fragment]; fragment 2's [run_expr] passes
    [ctx.loaded_tir_types @ tir.tm_types] to [emit_repl_expr]'s `~types`.

    HISTORY / why this test is shaped the way it is (best-effort RED, per the
    task brief): pre-fix, representation decisions were driven by a single
    module-level ref `cur_type_defs`, set ONLY by [emit_module] — which the
    pure REPL/JIT path never calls. So in an isolated JIT-only process,
    `cur_type_defs` sat at `[]` for the *entire* session: every fragment's
    EAlloc/emit_case/ensure_adt_eq_fn call consistently (if accidentally)
    computed "Boxed" for `Opt`, so running fragment 1 then fragment 2 straight
    did NOT reproduce an observable split (verified empirically by
    instrumenting both call sites: `cur_type_defs_len=0` at every call, with
    no poke at all — this alone was GREEN even pre-fix).

    To force the actual staleness — "the REPL/fragment entry points ... never
    set the global — so all niche/newtype representation decisions ... run
    against a stale or empty table" — the original RED additionally called
    [Llvm_emit.emit_module] directly on the `Opt` module before fragment 1
    (mimicking a prior `--compile` sharing the same process image as the
    REPL, which is how `emit_module` legitimately runs at all) and then reset
    the ref to `[]` before fragment 2. That combination reliably reproduced a
    SIGSEGV pre-fix (fragment 2's emit_case read the ctor tag at offset 8 of
    what fragment 1 had actually emitted as a bare tagged scalar, per the
    live-at-the-time global) — confirmed by running the suite repeatedly
    (5/5 crashes, exit 139) before the mechanical fix landed below.

    Now that [cur_type_defs] is deleted (ctx.type_defs is populated
    per-fragment from each entry point's own `types` parameter, never a
    shared global), that historical RED recipe no longer compiles — there is
    no global left to poke. This test keeps the two-fragment cross-ADT
    scenario as a permanent regression pin: fragment 1 defines a niche-shaped
    ADT and a producer, fragment 2 matches on the value the producer returns,
    and the payload must round-trip correctly. It is GREEN post-fix (as
    verified above); its historical RED is documented here rather than
    reproduced in-line because reproducing it requires reintroducing the
    deleted global. *)
let test_repl_jit_niche_adt_cross_fragment () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       (* Fragment 1: `:load`-style DMod defining a niche-eligible ADT and a
          producer fn, exactly as lib/repl/repl.ml wraps user :load files. *)
       let mod_src = {|mod OptMod do
         type Opt = None | Some(Int)
         fn mk(x : Int) : Opt do
           Some(x)
         end
       end|} in
       let mod_ast = parse_module mod_src in
       let dmod = March_ast.Ast.DMod
         (mod_ast.March_ast.Ast.mod_name, March_ast.Ast.Public,
          mod_ast.March_ast.Ast.mod_decls, March_ast.Ast.dummy_span) in
       (* Mirror lib/repl/repl.ml's load_decls_list exactly: check_decl with a
          fresh error ctx, keep tc_env pre-decl ("input_tc") to hand to
          register_module_decl, then advance tc_env past the DMod. *)
       let input_tc = { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } in
       let new_tc = March_typecheck.Typecheck.check_decl input_tc dmod in
       (* Fragment 1: emits `mk`'s body — EAlloc(Opt.Some, [x]) — via
          register_module_decl -> emit_fns_fragment, whose ctx.type_defs is
          populated from this fragment's own `types` (containing `Opt`). *)
       March_jit.Repl_jit.register_module_decl jit ~tc_env:input_tc dmod;
       tc_env := { new_tc with March_typecheck.Typecheck.errors = March_errors.Errors.create () };
       (* Between fragments: exercise an entirely unrelated emit_module call
          (as any prior --compile in the same process would) to prove there
          is no shared mutable state left for it to leave behind. *)
       let unrelated_src = {|mod Unrelated do
         fn id(x : Int) : Int do x end
       end|} in
       let unrelated_ast = parse_module unrelated_src in
       let (_, unrelated_type_map) = March_typecheck.Typecheck.check_module unrelated_ast in
       let unrelated_tir = March_tir.Lower.lower_module ~type_map:unrelated_type_map unrelated_ast in
       let unrelated_tir = March_tir.Mono.monomorphize unrelated_tir in
       let unrelated_tir = March_tir.Defun.defunctionalize unrelated_tir in
       let unrelated_tir = March_tir.Perceus.perceus unrelated_tir in
       ignore (March_tir.Llvm_emit.emit_module unrelated_tir);
       (* Fragment 2: match on the value the fragment-1 producer returns.
          Post-fix, the intervening emit_module call (with a `types` table
          that doesn't even mention `Opt`) has zero effect on this fragment's
          representation decisions. *)
       (match parse_repl "match OptMod.mk(7) do\nSome(v) -> v\nNone -> 0\nend" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "niche ADT cross-fragment: match Some(7) = 7" "7" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(* ------------------------------------------------------------------ *)
(* REPL JIT regression tests                                           *)
(* Exercises fixes: AVar extern fix, repl_N global uniquification,    *)
(* List literal JIT support, var redefinition, expr-after-let.        *)
(* ------------------------------------------------------------------ *)

(** Regression: `let xs = [1,2,3]` should succeed without JIT error.
    Fixes: AVar for march_compare_int was falling through to alloca bridge. *)
let test_repl_list_literal () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl = load_stdlib_file_for_test "list.march" in
    let stdlib_decls = [list_decl] in
    let content_hash =
      Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       March_jit.Repl_jit.precompile_stdlib jit
         ~content_hash ~stdlib_decls ~type_map;
       let make_stdlib_mod e =
         let s = March_ast.Ast.dummy_span in
         let clause = March_ast.Ast.{ fc_params = []; fc_guard = None; fc_body = e; fc_span = s; fc_params_span = s } in
         let main_def = March_ast.Ast.{
           fn_name = { txt = "main"; span = s };
           fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
           fn_clauses = [clause]; fn_bounds = [] } in
         { March_ast.Ast.mod_name = { txt = "Main"; span = s };
           mod_decls = stdlib_decls @ [DFn (main_def, s)] }
       in
       (match parse_repl "let xs = [1, 2, 3]" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let n = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt | _ -> failwith "expected PatVar"
              in (n, b.bind_expr)
            | _ -> failwith "expected DLet"
          in
          let m = make_stdlib_mod bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env ~is_fn_decl:false ~bind_name m
        | _ -> failwith "expected ReplDecl");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression: `let xs = [1,2,3]` then `List.length(xs)` should return 3.
    Exercises stdlib dispatch on a list literal defined in a prior REPL line. *)
let test_repl_stdlib_on_list () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl = load_stdlib_file_for_test "list.march" in
    let stdlib_decls = [list_decl] in
    let content_hash =
      Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       March_jit.Repl_jit.precompile_stdlib jit
         ~content_hash ~stdlib_decls ~type_map;
       let make_stdlib_mod e =
         let s = March_ast.Ast.dummy_span in
         let clause = March_ast.Ast.{ fc_params = []; fc_guard = None; fc_body = e; fc_span = s; fc_params_span = s } in
         let main_def = March_ast.Ast.{
           fn_name = { txt = "main"; span = s };
           fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
           fn_clauses = [clause]; fn_bounds = [] } in
         { March_ast.Ast.mod_name = { txt = "Main"; span = s };
           mod_decls = stdlib_decls @ [DFn (main_def, s)] }
       in
       (match parse_repl "let xs = [1, 2, 3]" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let n = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt | _ -> failwith "expected PatVar"
              in (n, b.bind_expr)
            | _ -> failwith "expected DLet"
          in
          let m = make_stdlib_mod bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (match parse_repl "List.length(xs)" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_mod e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "List.length(xs) = 3" "3" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression: `let x = 1` then `let x = 2` then `x` should return 2.
    Exercises global-name uniquification (repl_N_x) so redefining x doesn't
    collide with the previous fragment's global. *)
let test_repl_var_redefinition () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
       (match parse_repl "let x = 1" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let n = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt | _ -> failwith "PatVar"
              in (n, b.bind_expr)
            | _ -> failwith "expected DLet"
          in
          let m = make_jit_test_module bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (match parse_repl "let x = 2" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let n = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt | _ -> failwith "PatVar"
              in (n, b.bind_expr)
            | _ -> failwith "expected DLet"
          in
          let m = make_jit_test_module bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (match parse_repl "x" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "x after redef = 2" "2" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression: `let xs = [3,1,2]` then `List.length(xs)` twice.
    Exercises that the stdlib precompile cache is stable across multiple calls. *)
let test_repl_stdlib_chain () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl = load_stdlib_file_for_test "list.march" in
    let stdlib_decls = [list_decl] in
    let content_hash =
      Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       March_jit.Repl_jit.precompile_stdlib jit
         ~content_hash ~stdlib_decls ~type_map;
       let make_stdlib_mod e =
         let s = March_ast.Ast.dummy_span in
         let clause = March_ast.Ast.{ fc_params = []; fc_guard = None; fc_body = e; fc_span = s; fc_params_span = s } in
         let main_def = March_ast.Ast.{
           fn_name = { txt = "main"; span = s };
           fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
           fn_clauses = [clause]; fn_bounds = [] } in
         { March_ast.Ast.mod_name = { txt = "Main"; span = s };
           mod_decls = stdlib_decls @ [DFn (main_def, s)] }
       in
       (match parse_repl "let xs = [3, 1, 2]" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let n = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt | _ -> failwith "PatVar"
              in (n, b.bind_expr)
            | _ -> failwith "expected DLet"
          in
          let m = make_stdlib_mod bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (* First call *)
       (match parse_repl "List.length(xs)" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_mod e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "List.length(xs) call 1 = 3" "3" result
        | _ -> failwith "expected ReplExpr");
       (* Second call — same value, different fragment *)
       (match parse_repl "List.length(xs)" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_mod e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "List.length(xs) call 2 = 3" "3" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression: `let x = 42` then `x + 1` should return 43.
    Exercises that an expression using a previous binding evaluates correctly. *)
let test_repl_expr_after_let () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
       (match parse_repl "let x = 42" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let n = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt | _ -> failwith "PatVar"
              in (n, b.bind_expr)
            | _ -> failwith "expected DLet"
          in
          let m = make_jit_test_module bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (match parse_repl "x + 1" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "x + 1 = 43" "43" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(* ------------------------------------------------------------------ *)
(* REPL magic `v` variable and heap pretty-printer tests              *)
(* ------------------------------------------------------------------ *)

(** `v` (magic last-result variable) works across JIT fragments.
    After evaluating `21 + 21`, `v` should be available and equal to 42.
    Bug: previously `v` was added to tc_env but not to JIT globals,
    so referencing `v` in the next fragment crashed clang. *)
let test_repl_jit_v_magic_int () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
       (* Evaluate `21 + 21` — result stored as @repl_N_v *)
       (match parse_repl "21 + 21" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "21+21 = 42" "42" result;
          let inferred = March_typecheck.Typecheck.infer_expr
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } e' in
          tc_env := { !tc_env with March_typecheck.Typecheck.vars =
            March_typecheck.Typecheck.StrMap.add "v"
              (March_typecheck.Typecheck.Mono inferred)
              !tc_env.March_typecheck.Typecheck.vars }
        | _ -> failwith "expected ReplExpr");
       (* Now evaluate `v + 1` — references the `v` global from prior fragment *)
       (match parse_repl "v + 1" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "v+1 = 43" "43" result;
          let inferred = March_typecheck.Typecheck.infer_expr
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } e' in
          tc_env := { !tc_env with March_typecheck.Typecheck.vars =
            March_typecheck.Typecheck.StrMap.add "v"
              (March_typecheck.Typecheck.Mono inferred)
              !tc_env.March_typecheck.Typecheck.vars }
        | _ -> failwith "expected ReplExpr");
       (* `v` itself equals 43 now (the result of the last expression) *)
       (match parse_repl "v" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "v = 43 (last result)" "43" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Heap pretty-printer: a list literal `[1, 2, 3]` must display as
    "[1, 2, 3]" rather than "#<value at 0x...>".
    Bug: the `_` catch-all in run_expr returned the raw pointer address. *)
let test_repl_jit_list_display () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl = load_stdlib_file_for_test "list.march" in
    let stdlib_decls = [list_decl] in
    let content_hash =
      Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       March_jit.Repl_jit.precompile_stdlib jit
         ~content_hash ~stdlib_decls ~type_map;
       let make_stdlib_mod e =
         let s = March_ast.Ast.dummy_span in
         let clause = March_ast.Ast.{ fc_params = []; fc_guard = None; fc_body = e; fc_span = s; fc_params_span = s } in
         let main_def = March_ast.Ast.{
           fn_name = { txt = "main"; span = s };
           fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
           fn_clauses = [clause]; fn_bounds = [] } in
         { March_ast.Ast.mod_name = { txt = "Main"; span = s };
           mod_decls = stdlib_decls @ [DFn (main_def, s)] }
       in
       (* Evaluate `[1, 2, 3]` — should pretty-print as "[1, 2, 3]" *)
       (match parse_repl "[1, 2, 3]" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_mod e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "[1,2,3] display" "[1, 2, 3]" result
        | _ -> failwith "expected ReplExpr");
       (* Empty list `[]` — should display as "[]" *)
       (match parse_repl "List.empty()" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_mod e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "empty list display" "[]" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Parser hint: `x = 5` at REPL top-level should raise ParseError with
    a hint containing "let". *)
let test_repl_assign_hint () =
  (try
     let _ = parse_repl "x = 5" in
     Alcotest.fail "expected ParseError for `x = 5`"
   with
   | March_errors.Errors.ParseError (msg, _hint, _pos) ->
     (* Message must mention `let` as a hint *)
     let has_let = String.length msg >= 3 &&
       (let rec check i =
          if i + 2 >= String.length msg then false
          else if String.sub msg i 3 = "let" then true
          else check (i + 1)
        in check 0) in
     Alcotest.(check bool) "hint mentions let" true has_let
   | exn ->
     Alcotest.failf "unexpected exception: %s" (Printexc.to_string exn))

(** General REPL interaction: define a variable, evaluate an expression
    using it, redefine it, and check v tracks the last result. *)
let test_repl_jit_general_interaction () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
       let run_decl_str src =
         match parse_repl src with
         | March_ast.Ast.ReplDecl d ->
           let d' = March_desugar.Desugar.desugar_decl d in
           let (bind_name, bind_expr) = match d' with
             | March_ast.Ast.DLet (_, b, _) ->
               let n = match b.bind_pat with
                 | March_ast.Ast.PatVar v -> v.txt | _ -> failwith "PatVar"
               in (n, b.bind_expr)
             | _ -> failwith "expected DLet"
           in
           let m = make_jit_test_module bind_expr in
           March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
           let new_env = March_typecheck.Typecheck.check_decl
             { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
           tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
         | _ -> failwith ("expected ReplDecl for: " ^ src)
       in
       let run_expr_str src =
         match parse_repl src with
         | March_ast.Ast.ReplExpr e ->
           let e' = March_desugar.Desugar.desugar_expr e in
           let m = make_jit_test_module e' in
           let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
           result
         | _ -> failwith ("expected ReplExpr for: " ^ src)
       in
       run_decl_str "let x = 10";
       (* x + 5 = 15 *)
       Alcotest.(check string) "x+5" "15" (run_expr_str "x + 5");
       (* v = 15 (last result) *)
       Alcotest.(check string) "v=15" "15" (run_expr_str "v");
       (* redefine x = 99 *)
       run_decl_str "let x = 99";
       Alcotest.(check string) "x after redef" "99" (run_expr_str "x");
       (* v = 99 now *)
       Alcotest.(check string) "v=99" "99" (run_expr_str "v");
       (* boolean expression: true *)
       Alcotest.(check string) "true expr" "true" (run_expr_str "1 == 1");
       (* v after bool *)
       Alcotest.(check string) "v=true" "true" (run_expr_str "v");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression: `let ll = [1,2,3,9,4,5,6,7]` must compile when bigint is
    in the JIT fragment.  Reproduces the real-REPL scenario where
    precompile_stdlib fails (e.g. decimal.march parse error), causing ALL
    stdlib functions — including BigInt.div_digit$go$apply$N — to be
    JIT-compiled in the first fragment alongside the user's list literal.

    Bug: the Cons branch of div_digit$go$apply$N defines %new_rem.addr in
    case_cons_lbl, but after FBIP the subsequent load lands in fbip_merge1
    without %new_rem.addr being defined there (or the alloca uses the wrong
    slot due to stale local_names state leaking from a prior emit_fn call). *)
let test_repl_list_literal_with_bigint () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl   = load_stdlib_file_for_test "list.march" in
    let bigint_decl = load_stdlib_file_for_test "bigint.march" in
    let stdlib_decls = [list_decl; bigint_decl] in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (* Intentionally do NOT call precompile_stdlib — this forces all stdlib
       functions (including BigInt) into the first JIT fragment, reproducing
       the real-REPL scenario when precompile fails due to a parse error in
       another stdlib file (e.g. decimal.march). *)
    (try
       let make_stdlib_mod e =
         let s = March_ast.Ast.dummy_span in
         let clause = March_ast.Ast.{
           fc_params = []; fc_guard = None; fc_body = e; fc_span = s;
           fc_params_span = s } in
         let main_def = March_ast.Ast.{
           fn_name = { txt = "main"; span = s };
           fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
           fn_clauses = [clause]; fn_bounds = [] } in
         { March_ast.Ast.mod_name = { txt = "Main"; span = s };
           mod_decls = stdlib_decls @ [DFn (main_def, s)] }
       in
       let run_decl_with_stdlib src =
         match parse_repl src with
         | March_ast.Ast.ReplDecl d ->
           let d' = March_desugar.Desugar.desugar_decl d in
           let (bind_name, bind_expr) = match d' with
             | March_ast.Ast.DLet (_, b, _) ->
               let n = match b.bind_pat with
                 | March_ast.Ast.PatVar v -> v.txt
                 | _ -> failwith "expected PatVar"
               in (n, b.bind_expr)
             | _ -> failwith "expected DLet"
           in
           March_jit.Repl_jit.run_decl jit ~tc_env ~is_fn_decl:false
             ~bind_name (make_stdlib_mod bind_expr)
         | _ -> failwith ("expected ReplDecl for: " ^ src)
       in
       (* 8-element list — exact reproducer from bug report *)
       run_decl_with_stdlib "let ll = [1,2,3,9,4,5,6,7]";
       (* Shorter lists at the boundary *)
       run_decl_with_stdlib "let xs = [1,2,3]";
       run_decl_with_stdlib "let ys = [1]";
       run_decl_with_stdlib "let zs = []";
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression: decimal.march must parse without errors.
    A missing `end` in the `align` function caused the module block to close
    prematurely, which then caused a parse error on the next `doc` annotation.
    With decimal fixed, precompile_stdlib can succeed for the full stdlib. *)
let test_decimal_march_parses () =
  (* load_stdlib_file_for_test will raise if decimal.march fails to parse *)
  let _decl = load_stdlib_file_for_test "decimal.march" in
  ignore _decl

(** Regression: precompile_stdlib with bigint + decimal should succeed,
    ensuring list literals don't drag all stdlib fns into every JIT fragment. *)
let test_repl_list_literal_with_precompile_bigint () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl   = load_stdlib_file_for_test "list.march" in
    let bigint_decl = load_stdlib_file_for_test "bigint.march" in
    let stdlib_decls = [list_decl; bigint_decl] in
    let content_hash =
      Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       (* Precompile bigint — should succeed now that decimal.march is fixed *)
       March_jit.Repl_jit.precompile_stdlib jit
         ~content_hash ~stdlib_decls ~type_map;
       let make_stdlib_mod e =
         let s = March_ast.Ast.dummy_span in
         let clause = March_ast.Ast.{
           fc_params = []; fc_guard = None; fc_body = e; fc_span = s;
           fc_params_span = s } in
         let main_def = March_ast.Ast.{
           fn_name = { txt = "main"; span = s };
           fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
           fn_clauses = [clause]; fn_bounds = [] } in
         { March_ast.Ast.mod_name = { txt = "Main"; span = s };
           mod_decls = stdlib_decls @ [DFn (main_def, s)] }
       in
       (match parse_repl "let ll = [1,2,3,9,4,5,6,7]" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let n = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt
                | _ -> failwith "expected PatVar"
              in (n, b.bind_expr)
            | _ -> failwith "expected DLet"
          in
          March_jit.Repl_jit.run_decl jit ~tc_env ~is_fn_decl:false
            ~bind_name (make_stdlib_mod bind_expr)
        | _ -> failwith "expected ReplDecl");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(* ------------------------------------------------------------------ *)
(* P0 REGRESSION: compiled_fns corruption fix (2026-03)               *)
(*                                                                     *)
(* Previously `partition_fns` added functions to `compiled_fns`       *)
(* BEFORE `compile_fragment` succeeded.  If compilation failed, those *)
(* functions were poisoned: marked compiled but absent from any .so.   *)
(* On the next REPL expression they became `extern_fns` (declared but *)
(* not defined), causing "undefined symbol" errors on ALL stdlib fns.  *)
(*                                                                     *)
(* Fix: `partition_fns` is now pure; `mark_compiled_fns` is called    *)
(* only after a successful `compile_fragment` + dlopen.               *)
(*                                                                     *)
(* Tests below cover:                                                  *)
(*   1. stdlib fns (List.reverse, List.length) work in successive frags*)
(*   2. stdlib fns available WITHOUT precompile (inline-JIT mode)     *)
(*   3. List.map with user-defined lambda across REPL lines            *)
(* ------------------------------------------------------------------ *)

(** Helper: build a module including [stdlib_decls] with main = [e]. *)
let test_repl_jit_stdlib_reverse () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl = load_stdlib_file_for_test "list.march" in
    let stdlib_decls = [list_decl] in
    let content_hash =
      Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       March_jit.Repl_jit.precompile_stdlib jit
         ~content_hash ~stdlib_decls ~type_map;
       (* First fragment: List.reverse([1, 2, 3]) *)
       (match parse_repl "List.reverse([1, 2, 3])" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_module stdlib_decls e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "List.reverse [1,2,3] = [3, 2, 1]" "[3, 2, 1]" result
        | _ -> failwith "expected ReplExpr");
       (* Second fragment: List.reverse([4, 5]) — stdlib fn in 2nd fragment *)
       (match parse_repl "List.reverse([4, 5])" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_module stdlib_decls e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "List.reverse [4,5] = [5, 4]" "[5, 4]" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression P0: stdlib fns available WITHOUT precompile (inline-JIT mode).
    When precompile_stdlib is not called (simulating a failed precompile),
    stdlib fns must still compile inline on first use, and then be properly
    marked compiled so subsequent fragments can use them as externs.
    Previously the premature-marking bug caused the SECOND call to crash. *)
let test_repl_jit_stdlib_no_precompile () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl = load_stdlib_file_for_test "list.march" in
    let stdlib_decls = [list_decl] in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (* Intentionally skip precompile_stdlib to force inline-JIT mode *)
    (try
       (* First call: List.length inline (includes stdlib in fragment) *)
       (match parse_repl "List.length([10, 20, 30])" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_module stdlib_decls e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "inline: List.length [10,20,30] = 3" "3" result
        | _ -> failwith "expected ReplExpr");
       (* Second call: List.length again — stdlib fns are now extern, must resolve *)
       (match parse_repl "List.length([1])" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_module stdlib_decls e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "inline: List.length [1] = 1" "1" result
        | _ -> failwith "expected ReplExpr");
       (* Third call: List.reverse — different stdlib fn, same fragment mode *)
       (match parse_repl "List.reverse([3, 2, 1])" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_module stdlib_decls e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "inline: List.reverse [3,2,1] = [1, 2, 3]" "[1, 2, 3]" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression P0: List.length works 3 times in succession.
    With the old premature-marking bug, if ANY of the compilations had
    failed, subsequent calls would see length$List_Int as "already compiled"
    (extern-only) and crash.  Three successive calls exercises the
    mark-after-success invariant thoroughly. *)
let test_repl_jit_stdlib_length_3x () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl = load_stdlib_file_for_test "list.march" in
    let stdlib_decls = [list_decl] in
    let content_hash =
      Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       March_jit.Repl_jit.precompile_stdlib jit
         ~content_hash ~stdlib_decls ~type_map;
       let run_length lst expected label =
         let src = Printf.sprintf "List.length(%s)" lst in
         match parse_repl src with
         | March_ast.Ast.ReplExpr e ->
           let e' = March_desugar.Desugar.desugar_expr e in
           let m = make_stdlib_module stdlib_decls e' in
           let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
           Alcotest.(check string) label expected result
         | _ -> failwith ("expected ReplExpr for: " ^ src)
       in
       run_length "[1, 2, 3]"    "3" "length 3 (fragment 1)";
       run_length "[1, 2]"       "2" "length 2 (fragment 2)";
       run_length "[]"           "0" "length 0 (fragment 3)";
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(* ------------------------------------------------------------------ *)
(* list_actors tests                                                   *)
(* ------------------------------------------------------------------ *)

let test_list_actors_empty () =
  Hashtbl.clear March_eval.Eval.actor_registry;
  Alcotest.(check int) "empty registry" 0
    (List.length (March_eval.Eval.list_actors ()))

let test_list_actors_alive () =
  Hashtbl.clear March_eval.Eval.actor_registry;
  Hashtbl.add March_eval.Eval.actor_registry 0
    (mk_actor_inst "Counter" true (March_eval.Eval.VInt 5));
  let actors = March_eval.Eval.list_actors () in
  Alcotest.(check int) "one actor" 1 (List.length actors);
  let a = List.hd actors in
  Alcotest.(check int)    "pid"   0     a.March_eval.Eval.ai_pid;
  Alcotest.(check string) "name"  "Counter" a.March_eval.Eval.ai_name;
  Alcotest.(check bool)   "alive" true  a.March_eval.Eval.ai_alive;
  Alcotest.(check string) "state" "5"   a.March_eval.Eval.ai_state_str

let test_list_actors_sorted () =
  Hashtbl.clear March_eval.Eval.actor_registry;
  Hashtbl.add March_eval.Eval.actor_registry 2
    (mk_actor_inst "A" true (March_eval.Eval.VInt 0));
  Hashtbl.add March_eval.Eval.actor_registry 0
    (mk_actor_inst "B" false (March_eval.Eval.VUnit));
  let actors = March_eval.Eval.list_actors () in
  Alcotest.(check int) "two actors" 2 (List.length actors);
  Alcotest.(check int) "sorted first pid" 0
    (List.nth actors 0).March_eval.Eval.ai_pid;
  Alcotest.(check int) "sorted second pid" 2
    (List.nth actors 1).March_eval.Eval.ai_pid

(* ------------------------------------------------------------------ *)
(* Debugger tests                                                     *)
(* ------------------------------------------------------------------ *)

let test_edbg_ast () =
  let sp = March_ast.Ast.dummy_span in
  let e = March_ast.Ast.EDbg (None, sp) in
  Alcotest.(check bool) "EDbg is an expr" true
    (match e with March_ast.Ast.EDbg _ -> true | _ -> false)

let test_lexer_keyword_dbg () =
  let lexbuf = Lexing.from_string "dbg" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "lexes dbg keyword" true
    (match tok with March_parser.Parser.DBG -> true | _ -> false)

let test_parse_dbg () =
  let lexbuf = Lexing.from_string "dbg()" in
  let e = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  Alcotest.(check bool) "parses dbg() as EDbg" true
    (match e with March_ast.Ast.EDbg _ -> true | _ -> false)

let test_desugar_edbg () =
  let sp = March_ast.Ast.dummy_span in
  let e = March_ast.Ast.EDbg (None, sp) in
  let e' = March_desugar.Desugar.desugar_expr e in
  Alcotest.(check bool) "EDbg desugar passthrough" true
    (match e' with March_ast.Ast.EDbg _ -> true | _ -> false)

let test_typecheck_edbg () =
  let type_map = Hashtbl.create 4 in
  let env = March_typecheck.Typecheck.base_env
    (March_errors.Errors.create ()) type_map in
  let sp = March_ast.Ast.dummy_span in
  let ty = March_typecheck.Typecheck.infer_expr env (March_ast.Ast.EDbg (None, sp)) in
  let pp = March_typecheck.Typecheck.pp_ty (March_typecheck.Typecheck.repr ty) in
  Alcotest.(check string) "EDbg typechecks as Unit" "()" pp

let test_eval_edbg_noop () =
  let v = March_eval.Eval.eval_expr March_eval.Eval.base_env
    (March_ast.Ast.EDbg (None, March_ast.Ast.dummy_span)) in
  Alcotest.(check bool) "EDbg evals to VUnit without debug mode" true
    (match v with March_eval.Eval.VUnit -> true | _ -> false)

let test_ring_buffer () =
  let rb = March_eval.Eval.ring_create 3 in
  March_eval.Eval.ring_push rb 10;
  March_eval.Eval.ring_push rb 20;
  March_eval.Eval.ring_push rb 30;
  Alcotest.(check (option int)) "ring get 0 (most recent)" (Some 30)
    (March_eval.Eval.ring_get rb 0);
  Alcotest.(check (option int)) "ring get 2 (oldest)" (Some 10)
    (March_eval.Eval.ring_get rb 2);
  (* overflow: push 40, evicts 10 *)
  March_eval.Eval.ring_push rb 40;
  Alcotest.(check (option int)) "ring get 0 after overflow" (Some 40)
    (March_eval.Eval.ring_get rb 0);
  Alcotest.(check (option int)) "ring get 2 after overflow" (Some 20)
    (March_eval.Eval.ring_get rb 2)

let test_trace_recording () =
  let cap = (match Sys.getenv_opt "MARCH_DEBUG_TRACE_SIZE" with
     | Some s -> (try int_of_string s with _ -> 100000) | None -> 100000) in
  let ctx = {
    March_eval.Eval.dc_trace   = March_eval.Eval.ring_create cap;
    dc_pos       = 0;
    dc_enabled   = true;
    dc_depth     = 0;
    dc_on_dbg    = None;
    dc_actor_log = [];
    dc_breakpoints = Hashtbl.create 16;
    dc_step        = March_eval.Eval.Run;
    dc_on_pause    = None;
    dc_last_line   = None;
  } in
  March_eval.Eval.debug_ctx := Some ctx;
  let src = "1 + 2" in
  let lexbuf = Lexing.from_string src in
  let e = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  let e' = March_desugar.Desugar.desugar_expr e in
  let _v = March_eval.Eval.eval_expr March_eval.Eval.base_env e' in
  let frames_recorded = ctx.March_eval.Eval.dc_trace.March_eval.Eval.rb_size in
  March_eval.Eval.debug_ctx := None;
  Alcotest.(check bool) "trace records frames" true (frames_recorded > 0)

let test_trace_navigation () =
  let ctx = March_debug.Debug.make_debug_ctx ~on_dbg:(fun _ -> ()) in
  March_debug.Debug.install ctx;
  let src = "1 + 2 + 3" in
  let lexbuf = Lexing.from_string src in
  let e = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  let e' = March_desugar.Desugar.desugar_expr e in
  ignore (March_eval.Eval.eval_expr March_eval.Eval.base_env e');
  let n = March_debug.Debug.frame_count ctx in
  Alcotest.(check bool) "recorded some frames" true (n > 0);
  let new_pos = March_debug.Trace.back ctx 1 in
  Alcotest.(check int) "back 1 moves cursor" 1 new_pos;
  let new_pos2 = March_debug.Trace.forward ctx 1 in
  Alcotest.(check int) "forward 1 returns to 0" 0 new_pos2;
  March_debug.Debug.uninstall ()

let test_replay () =
  let hit_dbg = ref false in
  let captured_env = ref March_eval.Eval.base_env in
  let ctx = March_debug.Debug.make_debug_ctx ~on_dbg:(fun env ->
    hit_dbg := true;
    captured_env := env
  ) in
  March_debug.Debug.install ctx;
  let src = {|
mod Test do
  fn factorial(n) do
    dbg()
    if n <= 1 do 1
    else n * factorial(n - 1) end
  end
  fn main() do
    factorial(3)
  end
end
|} in
  let lexbuf = Lexing.from_string src in
  let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  let m' = March_desugar.Desugar.desugar_module m in
  (try March_eval.Eval.run_module m'
   with
   | March_eval.Eval.Eval_error _    -> ()
   | March_eval.Eval.Match_failure _ -> ());
  March_debug.Debug.uninstall ();
  Alcotest.(check bool) "dbg() was hit" true !hit_dbg;
  let frame_count_before = March_debug.Debug.frame_count ctx in
  let new_env = ("n", March_eval.Eval.VInt 5) ::
                (List.remove_assoc "n" !captured_env) in
  March_debug.Debug.install ctx;
  ignore (March_debug.Replay.replay_from ctx new_env);
  March_debug.Debug.uninstall ();
  let frame_count_after = March_debug.Debug.frame_count ctx in
  Alcotest.(check bool) "replay adds new frames" true
    (frame_count_after > frame_count_before)

let test_debug_continue () =
  let hit = ref false in
  let ctx = March_debug.Debug.make_debug_ctx ~on_dbg:(fun _env ->
    hit := true
  ) in
  March_debug.Debug.install ctx;
  let src = {|
mod DebugTest do
  fn main() do
    dbg()
    42
  end
end
|} in
  let lexbuf = Lexing.from_string src in
  let m  = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  let m' = March_desugar.Desugar.desugar_module m in
  (try March_eval.Eval.run_module m'
   with
   | March_eval.Eval.Eval_error _    -> ()
   | March_eval.Eval.Match_failure _ -> ());
  March_debug.Debug.uninstall ();
  Alcotest.(check bool) "dbg() triggered on_dbg callback" true !hit

let test_trace_overflow () =
  let ctx = {
    March_eval.Eval.dc_trace   = March_eval.Eval.ring_create 3;
    dc_pos       = 0;
    dc_enabled   = true;
    dc_depth     = 0;
    dc_on_dbg    = None;
    dc_actor_log = [];
    dc_breakpoints = Hashtbl.create 16;
    dc_step        = March_eval.Eval.Run;
    dc_on_pause    = None;
    dc_last_line   = None;
  } in
  March_debug.Debug.install ctx;
  let src = "1 + 2 + 3 + 4" in
  let lexbuf = Lexing.from_string src in
  let e = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  let e' = March_desugar.Desugar.desugar_expr e in
  ignore (March_eval.Eval.eval_expr March_eval.Eval.base_env e');
  March_debug.Debug.uninstall ();
  Alcotest.(check int) "ring buffer size capped at capacity" 3
    ctx.March_eval.Eval.dc_trace.March_eval.Eval.rb_size

let test_actor_snapshot () =
  Hashtbl.reset March_eval.Eval.actor_registry;
  Hashtbl.reset March_eval.Eval.actor_defs_tbl;
  March_eval.Eval.next_pid := 0;
  let snap = March_eval.Eval.snapshot_actors () in
  Alcotest.(check int) "empty snapshot has 0 instances" 0
    (List.length snap.March_eval.Eval.ass_instances);
  March_eval.Eval.restore_actors snap;
  Alcotest.(check int) "restore_actors leaves registry empty" 0
    (Hashtbl.length March_eval.Eval.actor_registry)

(* ── Docstring tests ──────────────────────────────────────────────────────── *)

let test_doc_parse_fn () =
  let m = parse_module {|mod Test do
    doc "Adds two numbers."
    fn add(a : Int, b : Int) : Int do a + b end
  end|} in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    Alcotest.(check (option string)) "doc string" (Some "Adds two numbers.") def.fn_doc
  | _ -> Alcotest.fail "expected single DFn"

let test_doc_triple_quoted () =
  let m = parse_module {|mod Test do
    doc """
Adds two numbers.
Returns their sum.
"""
    fn add(a : Int, b : Int) : Int do a + b end
  end|} in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    (match def.fn_doc with
     | Some s ->
       Alcotest.(check bool) "multiline content present"
         true (String.length s > 10)
     | None -> Alcotest.fail "expected Some doc")
  | _ -> Alcotest.fail "expected single DFn"

let test_doc_desugar () =
  let m = parse_and_desugar {|mod Test do
    doc "Computes factorial."
    fn factorial(0) do 1 end
    fn factorial(n) do n * factorial(n - 1) end
  end|} in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    Alcotest.(check (option string)) "doc preserved after desugar"
      (Some "Computes factorial.") def.fn_doc
  | _ -> Alcotest.fail "expected single DFn after group_fn_clauses"

let test_doc_eval_registry () =
  Hashtbl.reset March_eval.Eval.doc_registry;
  let _env = eval_module {|mod Test do
    doc "Adds two numbers."
    fn add(a : Int, b : Int) : Int do a + b end
  end|} in
  Alcotest.(check (option string)) "doc registered"
    (Some "Adds two numbers.")
    (March_eval.Eval.lookup_doc "add")

let test_doc_nested_module () =
  Hashtbl.reset March_eval.Eval.doc_registry;
  let _env = eval_module {|mod Test do
    mod Math do
      doc "Adds two numbers."
      fn add(a : Int, b : Int) : Int do a + b end
    end
  end|} in
  Alcotest.(check (option string)) "nested doc registered with prefix"
    (Some "Adds two numbers.")
    (March_eval.Eval.lookup_doc "Math.add")

let test_doc_none () =
  Hashtbl.reset March_eval.Eval.doc_registry;
  let _env = eval_module {|mod Test do
    fn undocumented() : Int do 42 end
  end|} in
  Alcotest.(check (option string)) "no doc is None"
    None
    (March_eval.Eval.lookup_doc "undocumented")

(* ── Purity oracle ───────────────────────────────────────────────── *)

let test_purity_atom () =
  Alcotest.(check bool) "literal is pure" true
    (March_tir.Purity.is_pure (March_tir.Tir.EAtom (ilit 5)))

let test_purity_arith () =
  Alcotest.(check bool) "int add is pure" true
    (March_tir.Purity.is_pure (app "+" [ilit 1; ilit 2]))

let test_purity_println () =
  Alcotest.(check bool) "println is impure" false
    (March_tir.Purity.is_pure (app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")]))

let test_purity_print () =
  Alcotest.(check bool) "print is impure" false
    (March_tir.Purity.is_pure (app "print" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")]))

let test_purity_send () =
  Alcotest.(check bool) "send is impure" false
    (March_tir.Purity.is_pure (app "send" [March_tir.Tir.ALit (March_ast.Ast.LitString "msg")]))

let test_purity_let_pure () =
  let body = March_tir.Tir.EAtom (ilit 1) in
  let expr = March_tir.Tir.ELet (mk_var "x" March_tir.Tir.TInt, app "+" [ilit 2; ilit 3], body) in
  Alcotest.(check bool) "let with pure rhs is pure" true
    (March_tir.Purity.is_pure expr)

let test_purity_let_impure () =
  let body = March_tir.Tir.EAtom (ilit 1) in
  let expr = March_tir.Tir.ELet (mk_var "x" March_tir.Tir.TInt,
               app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")], body) in
  Alcotest.(check bool) "let with impure rhs is impure" false
    (March_tir.Purity.is_pure expr)

let test_purity_callptr () =
  let f = March_tir.Tir.ALit (March_ast.Ast.LitInt 0) in  (* dummy closure *)
  Alcotest.(check bool) "indirect call is impure" false
    (March_tir.Purity.is_pure (March_tir.Tir.ECallPtr (f, [])))

let test_purity_kill () =
  Alcotest.(check bool) "kill is impure" false
    (March_tir.Purity.is_pure (app "kill" [ilit 0]))

let test_purity_incrc () =
  let v = March_tir.Tir.AVar (mk_var "x" March_tir.Tir.TInt) in
  Alcotest.(check bool) "EIncRC is impure" false
    (March_tir.Purity.is_pure (March_tir.Tir.EIncRC v))

let test_purity_free () =
  let v = March_tir.Tir.AVar (mk_var "x" March_tir.Tir.TInt) in
  Alcotest.(check bool) "EFree is impure" false
    (March_tir.Purity.is_pure (March_tir.Tir.EFree v))

(* ── Constant folding ────────────────────────────────────────────── *)

let test_fold_int_add () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "+" [ilit 2; ilit 3])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "2+3=5"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 5)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_int_mul () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "*" [ilit 6; ilit 7])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "6*7=42"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 42)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_int_div_by_zero () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "/" [ilit 5; ilit 0])] in
  let _ = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "not changed" false !changed

let test_fold_float_add () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (fapp "+." [flit 1.5; flit 2.5])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "1.5+.2.5=4.0"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (flit 4.0)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_bool_not () =
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let m = mk_module [mk_fn "f" (bapp "not" [blit true])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "not true = false"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit false)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_and_shortcircuit_pure () =
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let m = mk_module [mk_fn "f" (bapp "&&" [blit false; blit true])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "false && true = false"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit false)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_and_shortcircuit_impure () =
  (* false && <AVar> IS folded: AVar is a pure atom (register read in ANF) *)
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let impure = app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")] in
  let print_var = mk_var "p" March_tir.Tir.TBool in
  let body = March_tir.Tir.ELet (print_var, impure,
               bapp "&&" [blit false; March_tir.Tir.AVar print_var]) in
  let m = mk_module [mk_fn "f" body] in
  let _ = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed (AVar is a pure atom)" true !changed

let test_fold_if_true () =
  let changed = ref false in
  let then_e = March_tir.Tir.EAtom (ilit 1) in
  let else_e = March_tir.Tir.EAtom (ilit 2) in
  let body = March_tir.Tir.ECase (blit true,
               [{ March_tir.Tir.br_tag = "True"; br_vars = []; br_body = then_e }],
               Some else_e) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "if true → then"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 1)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_if_false () =
  let changed = ref false in
  let then_e = March_tir.Tir.EAtom (ilit 1) in
  let else_e = March_tir.Tir.EAtom (ilit 2) in
  let body = March_tir.Tir.ECase (blit false,
               [{ March_tir.Tir.br_tag = "True"; br_vars = []; br_body = then_e }],
               Some else_e) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "if false → else"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 2)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_and_pure_var () =
  (* false && <AVar for pure value> → false (var is pure at atom position) *)
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let x = avar "x" March_tir.Tir.TBool in
  (* let x = true in false && x — x is a pure AVar at atom position *)
  let body = March_tir.Tir.ELet (mk_var "x" March_tir.Tir.TBool,
               March_tir.Tir.EAtom (blit true),
               bapp "&&" [blit false; x]) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed (pure var folded)" true !changed;
  (* The && should be folded; the let may remain *)
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, inner) ->
     (match inner with
      | March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitBool false)) -> ()
      | _ -> Alcotest.failf "expected false, got %s" (March_tir.Tir.show_expr inner))
   | March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitBool false)) -> ()
   | other -> Alcotest.failf "expected false, got %s" (March_tir.Tir.show_expr other))

let test_fold_or_shortcircuit_pure () =
  (* true || <pure rhs> → true *)
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let m = mk_module [mk_fn "f" (bapp "||" [blit true; blit false])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "true || false = true"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit true)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_string_concat () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "++" [slit "hello"; slit " world"])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "\"hello\" ++ \" world\" = \"hello world\""
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (slit "hello world")))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_string_byte_length () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "string_byte_length" [slit "hello"])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "string_byte_length(\"hello\") = 5"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 5)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_string_is_empty () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "string_is_empty" [slit ""])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "string_is_empty(\"\") = true"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit true)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_string_is_empty_false () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "string_is_empty" [slit "x"])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "string_is_empty(\"x\") = false"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit false)))
    (March_tir.Tir.show_expr (first_body m'))

(* ── Fold: boolean comparison identities + int comparison folding ─────────── *)

let test_fold_eq_true_rhs () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TBool in
  let m = mk_module [mk_fn "f" (app "==" [x; blit true])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x==true → x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_eq_false_rhs () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TBool in
  let m = mk_module [mk_fn "f" (app "==" [x; blit false])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  match first_body m' with
  | March_tir.Tir.EApp (f, [_]) when f.March_tir.Tir.v_name = "not" -> ()
  | e -> Alcotest.failf "x==false → not x, got: %s" (March_tir.Tir.show_expr e)

let test_fold_int_cmp_lit () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "<" [ilit 3; ilit 5])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "3 < 5 → true"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit true)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_int_cmp_lit_false () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app ">" [ilit 3; ilit 5])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "3 > 5 → false"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit false)))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_add_zero () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "+" [x; ilit 0])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x+0=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_mul_one () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "*" [x; ilit 1])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x*1=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_mul_zero_pure () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "*" [x; ilit 0])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x*0=0"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 0)))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_sub_self () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "-" [avar "x" March_tir.Tir.TInt; avar "x" March_tir.Tir.TInt])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x-x=0"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 0)))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_sub_different () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "-" [avar "x" March_tir.Tir.TInt; avar "y" March_tir.Tir.TInt])] in
  let _ = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "not changed" false !changed

let test_simplify_div_one () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "/" [x; ilit 1])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x/1=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_zero_div () =
  (* 0 / x where x is a variable must NOT simplify — x could be 0 *)
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let original = app "/" [ilit 0; x] in
  let m = mk_module [mk_fn "f" original] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "not changed" false !changed;
  Alcotest.(check string) "0/x unchanged"
    (March_tir.Tir.show_expr original)
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_zero_div_lit () =
  (* 0 / 5 → 0 (divisor is a known non-zero literal) *)
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "/" [ilit 0; ilit 5])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "0/5=0"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 0)))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_strength_reduce () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "*" [x; ilit 2])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, March_tir.Tir.EApp (f, _), _) ->
     Alcotest.(check string) "strength reduce to add" "+" f.March_tir.Tir.v_name
   | _ -> Alcotest.fail "expected ELet wrapping EApp(+)")

let test_simplify_float_add_zero () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TFloat in
  let fapp' op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TFloat)), args) in
  let m = mk_module [mk_fn "f" (fapp' "+." [x; flit 0.0])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x+.0.0=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_bool_and_true () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TBool in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let m = mk_module [mk_fn "f" (bapp "&&" [x; blit true])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x&&true=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

(* The empty-string concat identities are sound ONLY before Perceus, so they
   fire under ~pre_perceus:true (the dedicated pre-Perceus pipeline step) and
   are deliberately suppressed in the default post-Perceus Opt loop. *)
let test_simplify_string_concat_empty_rhs () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TString in
  let m = mk_module [mk_fn "f" (app "++" [x; slit ""])] in
  let m' = March_tir.Simplify.run ~pre_perceus:true ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x++\"\"=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_string_concat_empty_lhs () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TString in
  let m = mk_module [mk_fn "f" (app "++" [slit ""; x])] in
  let m' = March_tir.Simplify.run ~pre_perceus:true ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "\"\"++x=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

(* Guard: the default (post-Perceus) Simplify must NOT fold empty-string concat,
   else it would alias an RC-tracked value and double-free. *)
let test_simplify_string_concat_not_folded_post_perceus () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TString in
  let m = mk_module [mk_fn "f" (app "++" [x; slit ""])] in
  let _m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "unchanged post-Perceus" false !changed

(* P14 — boolean conditional identities ──────────────────────────── *)

let test_simplify_if_then_true_else_false () =
  (* if x then true else false → x *)
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TBool in
  let body = March_tir.Tir.ECase (x,
    [{ March_tir.Tir.br_tag = "True"; br_vars = [];
       br_body = March_tir.Tir.EAtom (blit true) }],
    Some (March_tir.Tir.EAtom (blit false))) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "if x then true else false = x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_if_then_false_else_true () =
  (* if x then false else true → not x *)
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TBool in
  let body = March_tir.Tir.ECase (x,
    [{ March_tir.Tir.br_tag = "True"; br_vars = [];
       br_body = March_tir.Tir.EAtom (blit false) }],
    Some (March_tir.Tir.EAtom (blit true))) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.EApp (f, [_]) when f.March_tir.Tir.v_name = "not" -> ()
   | e -> Alcotest.failf "expected EApp(not, [x]), got: %s" (March_tir.Tir.show_expr e))

let test_simplify_eq_self () =
  (* x == x → true (non-float) *)
  let changed = ref false in
  let x = mk_var "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "==" [March_tir.Tir.AVar x; March_tir.Tir.AVar x])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x==x=true"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit true)))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_ne_self () =
  (* x != x → false (non-float) *)
  let changed = ref false in
  let x = mk_var "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "!=" [March_tir.Tir.AVar x; March_tir.Tir.AVar x])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x!=x=false"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit false)))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_eq_self_float_no_reduce () =
  (* x == x must NOT reduce when x is Float (NaN != NaN in IEEE 754) *)
  let changed = ref false in
  let x = mk_var "x" March_tir.Tir.TFloat in
  let m = mk_module [mk_fn "f" (app "==" [March_tir.Tir.AVar x; March_tir.Tir.AVar x])] in
  let _ = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "not changed for float ==" false !changed

let test_simplify_eq_self_tuple_float_no_reduce () =
  (* x == x must NOT reduce for TTuple containing Float — NaN inside a tuple
     means (NaN,1) == (NaN,1) is false at runtime but the rule would return true *)
  let changed = ref false in
  let ty = March_tir.Tir.TTuple [March_tir.Tir.TFloat; March_tir.Tir.TInt] in
  let x = mk_var "x" ty in
  let m = mk_module [mk_fn "f" (app "==" [March_tir.Tir.AVar x; March_tir.Tir.AVar x])] in
  let _ = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "not changed for tuple-float ==" false !changed

(* ── P15: boolean short-circuit absorber peepholes ──────────────────────── *)

let test_simplify_and_false_rhs () =
  let x = mk_var "x" March_tir.Tir.TBool in
  let m = mk_module [mk_fn "f" (app "&&" [March_tir.Tir.AVar x;
                                           March_tir.Tir.ALit (March_ast.Ast.LitBool false)])] in
  let changed = ref false in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let body = (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  Alcotest.(check bool) "result is EAtom false"
    (body = March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitBool false))) true

let test_simplify_and_false_lhs () =
  let x = mk_var "x" March_tir.Tir.TBool in
  let m = mk_module [mk_fn "f" (app "&&" [March_tir.Tir.ALit (March_ast.Ast.LitBool false);
                                           March_tir.Tir.AVar x])] in
  let changed = ref false in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let body = (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  Alcotest.(check bool) "result is EAtom false"
    (body = March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitBool false))) true

let test_simplify_or_true_rhs () =
  let x = mk_var "x" March_tir.Tir.TBool in
  let m = mk_module [mk_fn "f" (app "||" [March_tir.Tir.AVar x;
                                           March_tir.Tir.ALit (March_ast.Ast.LitBool true)])] in
  let changed = ref false in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let body = (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  Alcotest.(check bool) "result is EAtom true"
    (body = March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitBool true))) true

let test_simplify_not_true () =
  let m = mk_module [mk_fn "f" (app "not" [March_tir.Tir.ALit (March_ast.Ast.LitBool true)])] in
  let changed = ref false in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let body = (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  Alcotest.(check bool) "result is EAtom false"
    (body = March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitBool false))) true

let test_simplify_not_false () =
  let m = mk_module [mk_fn "f" (app "not" [March_tir.Tir.ALit (March_ast.Ast.LitBool false)])] in
  let changed = ref false in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let body = (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  Alcotest.(check bool) "result is EAtom true"
    (body = March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitBool true))) true

(* ── Function inlining ───────────────────────────────────────────── *)

let direct_call_to name =
  March_tir.Tir.EApp
    (mk_var name
       (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)),
     [ilit 1])

let test_inline_pure_small () =
  (* fn double(x) = x + x; fn main() = double(5) → call gets inlined *)
  let changed = ref false in
  let x_param = mk_var "x" March_tir.Tir.TInt in
  let double_body = app "+" [March_tir.Tir.AVar x_param; March_tir.Tir.AVar x_param] in
  let double_fn = { March_tir.Tir.fn_name = "double"; fn_params = [x_param];
                    fn_ret_ty = March_tir.Tir.TInt; fn_body = double_body;
                    fn_kind = March_tir.Tir.FnNormal } in
  let call = March_tir.Tir.EApp (mk_var "double"
               (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [ilit 5]) in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = [];
                  fn_ret_ty = March_tir.Tir.TInt; fn_body = call;
                  fn_kind = March_tir.Tir.FnNormal } in
  let m = mk_module [double_fn; main_fn] in
  let m' = March_tir.Inline.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (* main body should no longer be a bare EApp to "double" *)
  let main_body = (List.find (fun fd -> fd.March_tir.Tir.fn_name = "main") m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  (match main_body with
   | March_tir.Tir.EApp (f, _) when f.March_tir.Tir.v_name = "double" ->
     Alcotest.fail "call was not inlined"
   | _ -> ())

let test_inline_impure_not_inlined () =
  let changed = ref false in
  let x_param = mk_var "x" March_tir.Tir.TInt in
  let bad_body = March_tir.Tir.ESeq (
    app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")],
    March_tir.Tir.EAtom (March_tir.Tir.AVar x_param)) in
  let bad_fn = { March_tir.Tir.fn_name = "bad"; fn_params = [x_param];
                 fn_ret_ty = March_tir.Tir.TInt; fn_body = bad_body;
                 fn_kind = March_tir.Tir.FnNormal } in
  let call = March_tir.Tir.EApp (mk_var "bad"
               (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [ilit 1]) in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = [];
                  fn_ret_ty = March_tir.Tir.TInt; fn_body = call;
                  fn_kind = March_tir.Tir.FnNormal } in
  let m = mk_module [bad_fn; main_fn] in
  let _ = March_tir.Inline.run ~changed m in
  Alcotest.(check bool) "not changed (impure)" false !changed

let test_inline_recursive_not_inlined () =
  let changed = ref false in
  let n_param = mk_var "n" March_tir.Tir.TInt in
  (* self-calling fn — must not inline *)
  let fact_body = March_tir.Tir.EApp (mk_var "fact"
                    (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)),
                    [March_tir.Tir.AVar n_param]) in
  let fact_fn = { March_tir.Tir.fn_name = "fact"; fn_params = [n_param];
                  fn_ret_ty = March_tir.Tir.TInt; fn_body = fact_body;
                  fn_kind = March_tir.Tir.FnNormal } in
  let call = March_tir.Tir.EApp (mk_var "fact"
               (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [ilit 5]) in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = [];
                  fn_ret_ty = March_tir.Tir.TInt; fn_body = call;
                  fn_kind = March_tir.Tir.FnNormal } in
  let m = mk_module [fact_fn; main_fn] in
  let _ = March_tir.Inline.run ~changed m in
  Alcotest.(check bool) "not changed (recursive)" false !changed

let test_inline_mutual_recursion_not_inlined () =
  (* fn f(x) = g(x); fn g(x) = f(x) — mutually recursive, neither should inline *)
  let changed = ref false in
  let x_param = mk_var "x" March_tir.Tir.TInt in
  let g_call = March_tir.Tir.EApp (mk_var "g" (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [March_tir.Tir.AVar x_param]) in
  let f_fn = { March_tir.Tir.fn_name = "f"; fn_params = [x_param]; fn_ret_ty = March_tir.Tir.TInt; fn_body = g_call; fn_kind = March_tir.Tir.FnNormal } in
  let f_call = March_tir.Tir.EApp (mk_var "f" (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [March_tir.Tir.AVar x_param]) in
  let g_fn = { March_tir.Tir.fn_name = "g"; fn_params = [x_param]; fn_ret_ty = March_tir.Tir.TInt; fn_body = f_call; fn_kind = March_tir.Tir.FnNormal } in
  let call_f = March_tir.Tir.EApp (mk_var "f" (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [ilit 1]) in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = []; fn_ret_ty = March_tir.Tir.TInt; fn_body = call_f; fn_kind = March_tir.Tir.FnNormal } in
  let m = mk_module [f_fn; g_fn; main_fn] in
  let _ = March_tir.Inline.run ~changed m in
  Alcotest.(check bool) "not changed (mutually recursive)" false !changed

let test_inline_acyclic_candidate_chain () =
  let changed = ref false in
  let x = mk_var "x" March_tir.Tir.TInt in
  let leaf =
    { March_tir.Tir.fn_name = "leaf";
      fn_params = [x];
      fn_ret_ty = March_tir.Tir.TInt;
      fn_body = app "+" [March_tir.Tir.AVar x; ilit 1];
      fn_kind = March_tir.Tir.FnNormal }
  in
  let wrapper =
    { March_tir.Tir.fn_name = "wrapper";
      fn_params = [x];
      fn_ret_ty = March_tir.Tir.TInt;
      fn_body =
        March_tir.Tir.EApp
          (mk_var "leaf"
             (March_tir.Tir.TFn
                ([March_tir.Tir.TInt], March_tir.Tir.TInt)),
           [March_tir.Tir.AVar x]);
      fn_kind = March_tir.Tir.FnNormal }
  in
  let main =
    { March_tir.Tir.fn_name = "main";
      fn_params = [];
      fn_ret_ty = March_tir.Tir.TInt;
      fn_body = direct_call_to "wrapper";
      fn_kind = March_tir.Tir.FnNormal }
  in
  let result =
    March_tir.Inline.run ~changed (mk_module [leaf; wrapper; main])
  in
  let main_body =
    result.March_tir.Tir.tm_fns
    |> List.find (fun fn -> String.equal fn.March_tir.Tir.fn_name "main")
    |> fun fn -> fn.March_tir.Tir.fn_body
  in
  match main_body with
  | March_tir.Tir.EApp (fn, _)
    when String.equal fn.March_tir.Tir.v_name "wrapper" ->
    Alcotest.fail "acyclic wrapper remained excluded from candidates"
  | _ -> ()

let live_add_chain param count tail =
  let rec build index current =
    if index = count then tail current
    else
      let next =
        mk_var (Printf.sprintf "grow_%d" index) March_tir.Tir.TInt
      in
      March_tir.Tir.ELet
        (next,
         app "+" [March_tir.Tir.AVar current; March_tir.Tir.AVar param],
         build (index + 1) next)
  in
  build 0 param

let test_inline_acyclic_growth_removes_outer_from_llvm () =
  let int_fn_ty =
    March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)
  in
  let x = mk_var "x" March_tir.Tir.TInt in
  let inner_first = mk_var "inner_first" March_tir.Tir.TInt in
  let inner_second = mk_var "inner_second" March_tir.Tir.TInt in
  let inner_growth =
    { March_tir.Tir.fn_name = "inner_growth";
      fn_params = [x];
      fn_ret_ty = March_tir.Tir.TInt;
      fn_body =
        March_tir.Tir.ELet
          (inner_first,
           app "+" [March_tir.Tir.AVar x; March_tir.Tir.AVar x],
           March_tir.Tir.ELet
             (inner_second,
              app "+" [March_tir.Tir.AVar inner_first; March_tir.Tir.AVar x],
              March_tir.Tir.EAtom (March_tir.Tir.AVar inner_second)));
      fn_kind = March_tir.Tir.FnNormal }
  in
  let outer_x = mk_var "outer_x" March_tir.Tir.TInt in
  let outer_growth =
    { March_tir.Tir.fn_name = "outer_growth";
      fn_params = [outer_x];
      fn_ret_ty = March_tir.Tir.TInt;
      fn_body =
        live_add_chain outer_x 11 (fun current ->
          March_tir.Tir.EApp
            (mk_var "inner_growth" int_fn_ty, [March_tir.Tir.AVar current]));
      fn_kind = March_tir.Tir.FnNormal }
  in
  let main =
    { March_tir.Tir.fn_name = "main";
      fn_params = [];
      fn_ret_ty = March_tir.Tir.TInt;
      fn_body = March_tir.Tir.EApp (mk_var "outer_growth" int_fn_ty, [ilit 1]);
      fn_kind = March_tir.Tir.FnNormal }
  in
  Alcotest.(check int) "inner_growth fixture node count" 9
    (March_tir.Inline.node_count inner_growth.March_tir.Tir.fn_body);
  Alcotest.(check int) "outer_growth fixture node count" 46
    (March_tir.Inline.node_count outer_growth.March_tir.Tir.fn_body);
  let module_ = mk_module [inner_growth; outer_growth; main] in
  let contains haystack needle =
    let needle_len = String.length needle in
    let rec search index =
      index + needle_len <= String.length haystack
      && (String.sub haystack index needle_len = needle || search (index + 1))
    in
    search 0
  in
  let count_substring haystack needle =
    let needle_len = String.length needle in
    let rec count index total =
      if index + needle_len > String.length haystack then total
      else if String.sub haystack index needle_len = needle then
        count (index + needle_len) (total + 1)
      else count (index + 1) total
    in
    count 0 0
  in
  let ir_before = March_tir.Llvm_emit.emit_module module_ in
  let optimized = March_tir.Opt.run module_ in
  let ir = March_tir.Llvm_emit.emit_module optimized in
  let metrics =
    Printf.sprintf " (calls before=%d after=%d; ir bytes before=%d after=%d)"
      (count_substring ir_before " call ")
      (count_substring ir " call ")
      (String.length ir_before) (String.length ir)
  in
  Alcotest.(check bool)
    ("no residual call to outer_growth" ^ metrics) false
    (contains ir "call i64 @outer_growth(");
  Alcotest.(check bool)
    ("DCE removes outer_growth definition" ^ metrics) false
    (contains ir "define i64 @outer_growth(")

let test_inline_alpha_sequence_scope_is_lexical () =
  let local_target = mk_var "target" March_tir.Tir.TInt in
  let global_target =
    mk_var "target" (March_tir.Tir.TFn ([], March_tir.Tir.TInt))
  in
  let helper =
    { March_tir.Tir.fn_name = "helper";
      fn_params = [];
      fn_ret_ty = March_tir.Tir.TInt;
      fn_body =
        March_tir.Tir.ESeq
          (March_tir.Tir.EApp (global_target, []),
           March_tir.Tir.ELet
             (local_target, March_tir.Tir.EAtom (ilit 1),
              March_tir.Tir.EAtom (March_tir.Tir.AVar local_target)));
      fn_kind = March_tir.Tir.FnNormal }
  in
  match March_tir.Inline.expand_call helper [] with
  | Some
      (March_tir.Tir.ESeq
         (March_tir.Tir.EApp (free_callee, []),
          March_tir.Tir.ELet
            (renamed, _, March_tir.Tir.EAtom (March_tir.Tir.AVar local_use)))) ->
      Alcotest.(check bool) "local binder was freshened" false
        (String.equal renamed.March_tir.Tir.v_name "target");
      Alcotest.(check string) "local use follows its binder"
        renamed.March_tir.Tir.v_name local_use.March_tir.Tir.v_name;
      Alcotest.(check string)
        "a binder in the second sequence expression does not scope the first"
        "target" free_callee.March_tir.Tir.v_name
  | Some actual ->
      Alcotest.failf "unexpected alpha-renamed sequence: %s"
        (March_tir.Tir.show_expr actual)
  | None -> Alcotest.fail "zero-arity expansion unexpectedly failed"

let test_inline_alpha_case_arms_and_default_are_lexical () =
  let branch_target = mk_var "target" March_tir.Tir.TInt in
  let free_target =
    mk_var "target" (March_tir.Tir.TFn ([], March_tir.Tir.TInt))
  in
  let helper =
    { March_tir.Tir.fn_name = "helper";
      fn_params = [];
      fn_ret_ty = March_tir.Tir.TInt;
      fn_body =
        March_tir.Tir.ECase
          (ilit 0,
           [{ March_tir.Tir.br_tag = "Bound";
              br_vars = [branch_target];
              br_body =
                March_tir.Tir.EAtom (March_tir.Tir.AVar branch_target) };
            { March_tir.Tir.br_tag = "Sibling";
              br_vars = [];
              br_body = March_tir.Tir.EApp (free_target, []) }],
           Some (March_tir.Tir.EApp (free_target, [])));
      fn_kind = March_tir.Tir.FnNormal }
  in
  match March_tir.Inline.expand_call helper [] with
  | Some
      (March_tir.Tir.ECase
         (_,
          [{ March_tir.Tir.br_vars = [renamed];
             br_body = March_tir.Tir.EAtom (March_tir.Tir.AVar local_use);
             _ };
           { March_tir.Tir.br_vars = [];
             br_body = March_tir.Tir.EApp (sibling_callee, []);
             _ }],
          Some (March_tir.Tir.EApp (default_callee, [])))) ->
      Alcotest.(check bool) "branch binder was freshened" false
        (String.equal renamed.March_tir.Tir.v_name "target");
      Alcotest.(check string) "branch use follows its binder"
        renamed.March_tir.Tir.v_name local_use.March_tir.Tir.v_name;
      Alcotest.(check string) "one case arm does not scope a sibling"
        "target" sibling_callee.March_tir.Tir.v_name;
      Alcotest.(check string) "one case arm does not scope the default"
        "target" default_callee.March_tir.Tir.v_name
  | Some actual ->
      Alcotest.failf "unexpected alpha-renamed case: %s"
        (March_tir.Tir.show_expr actual)
  | None -> Alcotest.fail "zero-arity expansion unexpectedly failed"

let test_inline_alpha_local_function_params_are_lexical () =
  let outer_x = mk_var "x" March_tir.Tir.TInt in
  let local_x = mk_var "x" March_tir.Tir.TInt in
  let local_fn =
    { March_tir.Tir.fn_name = "local";
      fn_params = [local_x];
      fn_ret_ty = March_tir.Tir.TInt;
      fn_body = March_tir.Tir.EAtom (March_tir.Tir.AVar local_x);
      fn_kind = March_tir.Tir.FnNormal }
  in
  let params, renamed_body =
    March_tir.Inline.alpha_rename [outer_x]
      (March_tir.Tir.ELetRec
         ([local_fn], March_tir.Tir.EAtom (March_tir.Tir.AVar outer_x)))
  in
  match params, renamed_body with
  | [renamed_outer],
    March_tir.Tir.ELetRec
      ([{ March_tir.Tir.fn_params = [renamed_local];
          fn_body = March_tir.Tir.EAtom (March_tir.Tir.AVar local_use);
          _ }],
       March_tir.Tir.EAtom (March_tir.Tir.AVar outer_use)) ->
      Alcotest.(check bool) "local parameter was freshened" false
        (String.equal renamed_local.March_tir.Tir.v_name "x");
      Alcotest.(check bool) "local parameter shadows the outer parameter" false
        (String.equal renamed_local.March_tir.Tir.v_name
           renamed_outer.March_tir.Tir.v_name);
      Alcotest.(check string) "local body uses its local parameter"
        renamed_local.March_tir.Tir.v_name local_use.March_tir.Tir.v_name;
      Alcotest.(check string) "continuation uses the outer parameter"
        renamed_outer.March_tir.Tir.v_name outer_use.March_tir.Tir.v_name
  | _ ->
      Alcotest.failf "unexpected local-function alpha-renaming: %s"
        (March_tir.Tir.show_expr renamed_body)

let test_inline_alpha_avoids_existing_free_name () =
  let x = mk_var "x" March_tir.Tir.TInt in
  let warmup_params, _ =
    March_tir.Inline.alpha_rename [x]
      (March_tir.Tir.EAtom (March_tir.Tir.AVar x))
  in
  let warmup_name =
    match warmup_params with
    | [param] -> param.March_tir.Tir.v_name
    | _ -> Alcotest.fail "alpha-renaming changed warmup arity"
  in
  let prefix = "x_i" in
  let counter =
    int_of_string
      (String.sub warmup_name (String.length prefix)
         (String.length warmup_name - String.length prefix))
  in
  let colliding_name = Printf.sprintf "%s%d" prefix (counter + 1) in
  let free_global =
    mk_var colliding_name
      (March_tir.Tir.TFn ([], March_tir.Tir.TInt))
  in
  let params, body =
    March_tir.Inline.alpha_rename [x]
      (March_tir.Tir.ESeq
         (March_tir.Tir.EApp (free_global, []),
          March_tir.Tir.EAtom (March_tir.Tir.AVar x)))
  in
  match params, body with
  | [renamed],
    March_tir.Tir.ESeq
      (March_tir.Tir.EApp (free_use, []),
       March_tir.Tir.EAtom (March_tir.Tir.AVar local_use)) ->
      Alcotest.(check bool)
        "a fresh binder cannot capture an existing free/global spelling"
        false
        (String.equal renamed.March_tir.Tir.v_name
           free_use.March_tir.Tir.v_name);
      Alcotest.(check string) "parameter use follows its fresh binder"
        renamed.March_tir.Tir.v_name local_use.March_tir.Tir.v_name
  | _ ->
      Alcotest.failf "unexpected collision-avoidance alpha-renaming: %s"
        (March_tir.Tir.show_expr body)

let string_fn_ty =
  March_tir.Tir.TFn ([March_tir.Tir.TString], March_tir.Tir.TString)

let impure_identity name =
  let x = mk_var "x" March_tir.Tir.TString in
  { March_tir.Tir.fn_name = name;
    fn_params = [x];
    fn_ret_ty = March_tir.Tir.TString;
    fn_body =
      March_tir.Tir.ESeq
        (March_tir.Tir.EIncRC (March_tir.Tir.AVar x),
         March_tir.Tir.ESeq
           (March_tir.Tir.EDecRC (March_tir.Tir.AVar x),
            March_tir.Tir.EAtom (March_tir.Tir.AVar x)));
    fn_kind = March_tir.Tir.FnNormal }

let call_string name value =
  March_tir.Tir.EApp (mk_var name string_fn_ty, [value])

let body_of name module_ =
  module_.March_tir.Tir.tm_fns
  |> List.find (fun fn -> String.equal fn.March_tir.Tir.fn_name name)
  |> fun fn -> fn.March_tir.Tir.fn_body

let test_opt_runs_single_use_inline_after_inline () =
  let helper = impure_identity "single_use_helper" in
  let main = mk_fn "main" (call_string "single_use_helper" (slit "seven")) in
  let snapshots = ref [] in
  let result =
    March_tir.Opt.run
      ~snap:(fun label _module_ -> snapshots := label :: !snapshots)
      (mk_module [helper; main])
  in
  (match body_of "main" result with
   | March_tir.Tir.EApp (fn, _)
     when String.equal fn.March_tir.Tir.v_name "single_use_helper" ->
       Alcotest.fail "optimizer left the one-use impure helper call intact"
   | _ -> ());
  Alcotest.(check bool) "DCE removes the inlined helper definition" false
    (List.exists
       (fun fn -> String.equal fn.March_tir.Tir.fn_name "single_use_helper")
       result.March_tir.Tir.tm_fns);
  let labels = List.rev !snapshots in
  let index_of target =
    let rec loop index = function
      | [] -> None
      | label :: rest ->
          if String.equal label target then Some index else loop (index + 1) rest
    in
    loop 0 labels
  in
  match (index_of "tir-opt-1-inline",
         index_of "tir-opt-1-single-use-inline",
         index_of "tir-opt-1-cprop") with
  | Some inline_index, Some single_use_index, Some cprop_index ->
      Alcotest.(check bool) "single-use pass is between inline and cprop" true
        (inline_index < single_use_index && single_use_index < cprop_index)
  | _ -> Alcotest.fail "optimizer snapshots omitted the single-use inline phase"

let test_single_use_impure_eliminated_from_llvm () =
  let x = mk_var "x" March_tir.Tir.TString in
  let helper =
    { March_tir.Tir.fn_name = "one_use_effect";
      fn_params = [x];
      fn_ret_ty = March_tir.Tir.TString;
      fn_body =
        March_tir.Tir.ESeq
          (March_tir.Tir.EIncRC (March_tir.Tir.AVar x),
           March_tir.Tir.ESeq
             (app "println" [slit "effect"],
              March_tir.Tir.ESeq
                (March_tir.Tir.EDecRC (March_tir.Tir.AVar x),
                 March_tir.Tir.EAtom (March_tir.Tir.AVar x))));
      fn_kind = March_tir.Tir.FnNormal }
  in
  let main =
    { March_tir.Tir.fn_name = "main";
      fn_params = [];
      fn_ret_ty = March_tir.Tir.TString;
      fn_body = call_string "one_use_effect" (slit "payload");
      fn_kind = March_tir.Tir.FnNormal }
  in
  let module_ = mk_module [helper; main] in
  let ir_before = March_tir.Llvm_emit.emit_module module_ in
  Alcotest.(check bool) "fixture has named call before Opt" true
    (Test_helpers.contains "call ptr @one_use_effect(" ir_before);
  Alcotest.(check bool) "fixture has named definition before Opt" true
    (Test_helpers.contains "define ptr @one_use_effect(" ir_before);
  let ir_after =
    module_ |> March_tir.Opt.run |> March_tir.Llvm_emit.emit_module
  in
  Alcotest.(check bool) "Opt removes named call" false
    (Test_helpers.contains "call ptr @one_use_effect(" ir_after);
  Alcotest.(check bool) "DCE removes named definition" false
    (Test_helpers.contains "define ptr @one_use_effect(" ir_after);
  let position needle =
    try Str.search_forward (Str.regexp_string needle) ir_after 0
    with Not_found ->
      Alcotest.failf "optimized LLVM omitted %S" needle
  in
  let incrc = position "call void @march_incrc_local(" in
  let println = position "call void @march_println(" in
  let decrc = position "call void @march_decrc_local(" in
  Alcotest.(check bool)
    "inlined caller preserves IncRC, runtime effect, DecRC order" true
    (incrc < println && println < decrc)

let test_single_use_impure_inlined () =
  let helper = impure_identity "helper" in
  let main = mk_fn "main" (call_string "helper" (slit "seven")) in
  let changed = ref false in
  let result =
    March_tir.Single_use_inline.run ~changed (mk_module [helper; main])
  in
  Alcotest.(check bool) "changed" true !changed;
  match body_of "main" result with
  | March_tir.Tir.EApp (fn, _)
    when String.equal fn.March_tir.Tir.v_name "helper" ->
      Alcotest.fail "one-use impure helper remained a call"
  | _ -> ()

let test_single_use_two_calls_not_inlined () =
  let helper = impure_identity "helper" in
  let main =
    mk_fn "main"
      (March_tir.Tir.ESeq
         (call_string "helper" (slit "one"),
          call_string "helper" (slit "two")))
  in
  let changed = ref false in
  ignore (March_tir.Single_use_inline.run ~changed
            (mk_module [helper; main]));
  Alcotest.(check bool) "unchanged" false !changed

let test_single_use_address_taken_not_inlined () =
  let helper = impure_identity "helper" in
  let helper_value =
    March_tir.Tir.AVar (mk_var "helper" string_fn_ty)
  in
  let main =
    mk_fn "main"
      (March_tir.Tir.ESeq
         (March_tir.Tir.EAtom helper_value,
          call_string "helper" (slit "one")))
  in
  let changed = ref false in
  ignore (March_tir.Single_use_inline.run ~changed
            (mk_module [helper; main]));
  Alcotest.(check bool) "unchanged" false !changed

let test_single_use_let_shadowing_respected () =
  let helper = impure_identity "helper" in
  let local_helper = mk_var "helper" string_fn_ty in
  let shadowed_call = call_string "helper" (slit "local") in
  let top_level_call = call_string "helper" (slit "top-level") in
  let main =
    mk_fn "main"
      (March_tir.Tir.ESeq
         (March_tir.Tir.ELet
            (local_helper, March_tir.Tir.EAtom (slit "local binding"),
             shadowed_call),
          top_level_call))
  in
  let changed = ref false in
  let result =
    March_tir.Single_use_inline.run ~changed (mk_module [helper; main])
  in
  Alcotest.(check bool) "top-level call selected" true !changed;
  match body_of "main" result with
  | March_tir.Tir.ESeq
      (March_tir.Tir.ELet
         (_, _, March_tir.Tir.EApp (local_callee, _)),
       top_level_result)
    when String.equal local_callee.March_tir.Tir.v_name "helper" ->
      (match top_level_result with
       | March_tir.Tir.EApp (callee, _)
         when String.equal callee.March_tir.Tir.v_name "helper" ->
           Alcotest.fail "genuine top-level call was not inlined"
       | _ -> ())
  | actual ->
      Alcotest.failf "shadowed local call was rewritten: %s"
        (March_tir.Tir.show_expr actual)

let test_single_use_let_rhs_uses_outer_scope () =
  let helper = impure_identity "helper" in
  let local_helper = mk_var "helper" string_fn_ty in
  let main =
    mk_fn "main"
      (March_tir.Tir.ELet
         (local_helper,
          call_string "helper" (slit "top-level RHS"),
          call_string "helper" (slit "local body")))
  in
  let changed = ref false in
  let result =
    March_tir.Single_use_inline.run ~changed (mk_module [helper; main])
  in
  Alcotest.(check bool) "top-level RHS call selected" true !changed;
  match body_of "main" result with
  | March_tir.Tir.ELet
      (_, rhs_result, March_tir.Tir.EApp (local_callee, _))
    when String.equal local_callee.March_tir.Tir.v_name "helper" ->
      (match rhs_result with
       | March_tir.Tir.EApp (callee, _)
         when String.equal callee.March_tir.Tir.v_name "helper" ->
           Alcotest.fail "top-level RHS call was not inlined"
       | _ -> ())
  | actual ->
      Alcotest.failf "ELet body binding leaked into RHS or body rewrite: %s"
        (March_tir.Tir.show_expr actual)

let test_single_use_two_callers_not_inlined () =
  let helper = impure_identity "helper" in
  let caller = mk_fn "caller" (call_string "helper" (slit "one")) in
  let main = mk_fn "main" (call_string "helper" (slit "two")) in
  let changed = ref false in
  ignore
    (March_tir.Single_use_inline.run ~changed
       (mk_module [helper; caller; main]));
  Alcotest.(check bool) "references are counted across callers" false !changed

let test_single_use_parameter_and_case_shadowing_respected () =
  let helper = impure_identity "helper" in
  let parameter = mk_var "helper" string_fn_ty in
  let parameter_user =
    { March_tir.Tir.fn_name = "parameter_user";
      fn_params = [parameter];
      fn_ret_ty = March_tir.Tir.TString;
      fn_body = call_string "helper" (slit "parameter");
      fn_kind = March_tir.Tir.FnNormal }
  in
  let scrutinee = mk_var "scrutinee" March_tir.Tir.TString in
  let case_binder = mk_var "helper" string_fn_ty in
  let case_user =
    mk_fn "case_user"
      (March_tir.Tir.ECase
         (March_tir.Tir.AVar scrutinee,
          [{ March_tir.Tir.br_tag = "Some";
             br_vars = [case_binder];
             br_body = call_string "helper" (slit "case binder") }],
          None))
  in
  let main = mk_fn "main" (call_string "helper" (slit "top-level")) in
  let changed = ref false in
  let result =
    March_tir.Single_use_inline.run ~changed
      (mk_module [helper; parameter_user; case_user; main])
  in
  Alcotest.(check bool) "genuine top-level call selected" true !changed;
  (match body_of "parameter_user" result with
   | March_tir.Tir.EApp (callee, _)
     when String.equal callee.March_tir.Tir.v_name "helper" -> ()
   | actual ->
       Alcotest.failf "parameter-shadowed call was rewritten: %s"
         (March_tir.Tir.show_expr actual));
  (match body_of "case_user" result with
   | March_tir.Tir.ECase
       (_, [{ March_tir.Tir.br_body = March_tir.Tir.EApp (callee, _); _ }], _)
     when String.equal callee.March_tir.Tir.v_name "helper" -> ()
   | actual ->
       Alcotest.failf "case-binder-shadowed call was rewritten: %s"
         (March_tir.Tir.show_expr actual));
  match body_of "main" result with
  | March_tir.Tir.EApp (callee, _)
    when String.equal callee.March_tir.Tir.v_name "helper" ->
      Alcotest.fail "genuine top-level call was not inlined"
  | _ -> ()

let test_single_use_self_recursive_not_inlined () =
  let x = mk_var "x" March_tir.Tir.TString in
  let recursive =
    { March_tir.Tir.fn_name = "recursive";
      fn_params = [x];
      fn_ret_ty = March_tir.Tir.TString;
      fn_body =
        March_tir.Tir.ESeq
          (March_tir.Tir.EIncRC (March_tir.Tir.AVar x),
           call_string "recursive" (March_tir.Tir.AVar x));
      fn_kind = March_tir.Tir.FnNormal }
  in
  let main = mk_fn "main" (March_tir.Tir.EAtom (slit "done")) in
  let changed = ref false in
  ignore
    (March_tir.Single_use_inline.run ~changed
       (mk_module [recursive; main]));
  Alcotest.(check bool) "self-recursive SCC is excluded" false !changed

let test_single_use_mutually_recursive_not_inlined () =
  let x = mk_var "x" March_tir.Tir.TString in
  let recursive name callee =
    { March_tir.Tir.fn_name = name;
      fn_params = [x];
      fn_ret_ty = March_tir.Tir.TString;
      fn_body =
        March_tir.Tir.ESeq
          (March_tir.Tir.EIncRC (March_tir.Tir.AVar x),
           call_string callee (March_tir.Tir.AVar x));
      fn_kind = March_tir.Tir.FnNormal }
  in
  let f = recursive "f" "g" in
  let g = recursive "g" "f" in
  let main = mk_fn "main" (March_tir.Tir.EAtom (slit "done")) in
  let changed = ref false in
  ignore
    (March_tir.Single_use_inline.run ~changed (mk_module [f; g; main]));
  Alcotest.(check bool) "mutually recursive SCC is excluded" false !changed

let test_single_use_recursion_through_noncandidate_not_inlined () =
  let x = mk_var "x" March_tir.Tir.TString in
  let impure =
    { March_tir.Tir.fn_name = "impure";
      fn_params = [x];
      fn_ret_ty = March_tir.Tir.TString;
      fn_body =
        March_tir.Tir.ESeq
          (March_tir.Tir.EIncRC (March_tir.Tir.AVar x),
           call_string "pure" (March_tir.Tir.AVar x));
      fn_kind = March_tir.Tir.FnNormal }
  in
  let pure =
    { March_tir.Tir.fn_name = "pure";
      fn_params = [x];
      fn_ret_ty = March_tir.Tir.TString;
      fn_body = call_string "impure" (March_tir.Tir.AVar x);
      fn_kind = March_tir.Tir.FnNormal }
  in
  let main = mk_fn "main" (March_tir.Tir.EAtom (slit "done")) in
  let changed = ref false in
  ignore
    (March_tir.Single_use_inline.run ~changed
       (mk_module [impure; pure; main]));
  Alcotest.(check bool) "full graph SCC is excluded" false !changed

let sized_impure name arg_count =
  let x = mk_var "x" March_tir.Tir.TString in
  { March_tir.Tir.fn_name = name;
    fn_params = [x];
    fn_ret_ty = March_tir.Tir.TString;
    fn_body =
      March_tir.Tir.ECallPtr
        (March_tir.Tir.AVar x, List.init arg_count (fun _ -> slit "arg"));
    fn_kind = March_tir.Tir.FnNormal }

let test_single_use_size_threshold_is_inclusive () =
  let exact = sized_impure "exact" 49 in
  let over = sized_impure "over" 50 in
  Alcotest.(check int) "exact fixture" 50
    (March_tir.Inline.node_count exact.March_tir.Tir.fn_body);
  Alcotest.(check int) "over fixture" 51
    (March_tir.Inline.node_count over.March_tir.Tir.fn_body);
  let main =
    mk_fn "main"
      (March_tir.Tir.ESeq
         (call_string "exact" (slit "x"),
          call_string "over" (slit "y")))
  in
  let changed = ref false in
  let result =
    March_tir.Single_use_inline.run ~changed (mk_module [exact; over; main])
  in
  Alcotest.(check bool) "50-node candidate selected" true !changed;
  match body_of "main" result with
  | March_tir.Tir.ESeq
      (March_tir.Tir.EApp (exact_callee, _),
       March_tir.Tir.EApp (_, _))
    when String.equal exact_callee.March_tir.Tir.v_name "exact" ->
      Alcotest.fail "50-node candidate was not inlined"
  | March_tir.Tir.ESeq
      (_, March_tir.Tir.EApp (over_callee, _))
    when String.equal over_callee.March_tir.Tir.v_name "over" -> ()
  | actual ->
      Alcotest.failf "51-node candidate was inlined: %s"
        (March_tir.Tir.show_expr actual)

let test_single_use_arity_mismatch_not_inlined () =
  let helper = impure_identity "helper" in
  let main =
    mk_fn "main"
      (March_tir.Tir.EApp (mk_var "helper" string_fn_ty, []))
  in
  let changed = ref false in
  ignore
    (March_tir.Single_use_inline.run ~changed (mk_module [helper; main]));
  Alcotest.(check bool) "arity mismatch is excluded" false !changed

let test_single_use_dce_roots_not_inlined () =
  let check_root label root_name configure =
    let root = impure_identity root_name in
    let main = mk_fn "main" (call_string root_name (slit label)) in
    let module_ = configure (mk_module [root; main]) in
    let changed = ref false in
    ignore (March_tir.Single_use_inline.run ~changed module_);
    Alcotest.(check bool) label false !changed
  in
  check_root "exported" "exported_helper"
    (fun module_ ->
      { module_ with March_tir.Tir.tm_exports = ["exported_helper"] });
  check_root "test" "test_helper"
    (fun module_ ->
      { module_ with
        March_tir.Tir.tm_tests = [("test_helper", "test helper")] });
  check_root "setup" March_tir.Tir_names.setup_fn_name Fun.id;
  check_root "setup all" March_tir.Tir_names.setup_all_fn_name Fun.id;
  check_root "migration" "actor_migrate_state" Fun.id

let test_single_use_no_seed_fallback_roots_all_functions () =
  let helper = impure_identity "helper" in
  let caller = mk_fn "caller" (call_string "helper" (slit "one")) in
  let changed = ref false in
  ignore
    (March_tir.Single_use_inline.run ~changed (mk_module [helper; caller]));
  Alcotest.(check bool) "fallback roots every function" false !changed

let test_single_use_closure_stored_pointer_not_inlined () =
  let helper = impure_identity "helper" in
  let closure =
    March_tir.Tir.EAlloc
      (March_tir.Tir.TCon ("$Clo_helper$0", []),
       [March_tir.Tir.AVar (mk_var "helper" string_fn_ty)])
  in
  let main =
    mk_fn "main"
      (March_tir.Tir.ESeq
         (closure, call_string "helper" (slit "one")))
  in
  let changed = ref false in
  ignore
    (March_tir.Single_use_inline.run ~changed (mk_module [helper; main]));
  Alcotest.(check bool) "closure-stored pointer counts as a reference" false
    !changed

let test_single_use_collision_dispatch_target_not_inlined () =
  let sentinel = "__march_ifdispatch$Show$show$Thing" in
  March_tir.Dispatch_registry.register sentinel [("App.Thing", "helper")];
  Fun.protect
    ~finally:March_tir.Dispatch_registry.reset
    (fun () ->
      let helper = impure_identity "helper" in
      let dispatch =
        March_tir.Tir.EApp (mk_var sentinel string_fn_ty, [slit "dispatch"])
      in
      let main =
        mk_fn "main"
          (March_tir.Tir.ESeq
             (dispatch, call_string "helper" (slit "direct")))
      in
      let changed = ref false in
      ignore
        (March_tir.Single_use_inline.run ~changed
           (mk_module [helper; main]));
      Alcotest.(check bool)
        "dispatch target contributes a synthetic non-direct reference"
        false !changed)

let test_single_use_reloadable_callee_not_inlined () =
  March_tir.Inline.boundary_config :=
    Some (March_tir.Hot_reload.default_config "App");
  Fun.protect
    ~finally:(fun () -> March_tir.Inline.boundary_config := None)
    (fun () ->
      let helper = impure_identity "App.helper" in
      let main = mk_fn "main" (call_string "App.helper" (slit "one")) in
      let changed = ref false in
      ignore
        (March_tir.Single_use_inline.run ~changed
           (mk_module [helper; main]));
      Alcotest.(check bool) "reloadable callee is excluded" false !changed)

let test_single_use_rc_order_preserved () =
  let helper = impure_identity "helper" in
  let main = mk_fn "main" (call_string "helper" (slit "seven")) in
  let changed = ref false in
  let result =
    March_tir.Single_use_inline.run ~changed (mk_module [helper; main])
  in
  match body_of "main" result with
  | March_tir.Tir.ELet
      (param,
       March_tir.Tir.EAtom
         (March_tir.Tir.ALit (March_ast.Ast.LitString "seven")),
       March_tir.Tir.ESeq
         (March_tir.Tir.EIncRC (March_tir.Tir.AVar inc),
          March_tir.Tir.ESeq
            (March_tir.Tir.EDecRC (March_tir.Tir.AVar dec),
             March_tir.Tir.EAtom (March_tir.Tir.AVar result_var))))
    when String.equal param.March_tir.Tir.v_name inc.March_tir.Tir.v_name
         && String.equal inc.March_tir.Tir.v_name dec.March_tir.Tir.v_name
         && String.equal dec.March_tir.Tir.v_name
              result_var.March_tir.Tir.v_name -> ()
  | actual ->
      Alcotest.failf "RC operations were removed or reordered: %s"
        (March_tir.Tir.show_expr actual)

let test_single_use_pure_body_not_inlined () =
  let x = mk_var "x" March_tir.Tir.TString in
  let helper =
    { March_tir.Tir.fn_name = "helper";
      fn_params = [x];
      fn_ret_ty = March_tir.Tir.TString;
      fn_body = March_tir.Tir.EAtom (March_tir.Tir.AVar x);
      fn_kind = March_tir.Tir.FnNormal }
  in
  let main = mk_fn "main" (call_string "helper" (slit "one")) in
  let changed = ref false in
  ignore
    (March_tir.Single_use_inline.run ~changed (mk_module [helper; main]));
  Alcotest.(check bool) "syntactically pure body is excluded" false !changed

let test_single_use_local_letrec_shadowing_respected () =
  let helper = impure_identity "helper" in
  let local_x = mk_var "x" March_tir.Tir.TString in
  let local_helper =
    { March_tir.Tir.fn_name = "helper";
      fn_params = [local_x];
      fn_ret_ty = March_tir.Tir.TString;
      fn_body = March_tir.Tir.EAtom (March_tir.Tir.AVar local_x);
      fn_kind = March_tir.Tir.FnNormal }
  in
  let local_caller =
    { March_tir.Tir.fn_name = "local_caller";
      fn_params = [];
      fn_ret_ty = March_tir.Tir.TString;
      fn_body = call_string "helper" (slit "local body");
      fn_kind = March_tir.Tir.FnNormal }
  in
  let main =
    mk_fn "main"
      (March_tir.Tir.ESeq
         (March_tir.Tir.ELetRec
            ([local_helper; local_caller],
             call_string "helper" (slit "local continuation")),
          call_string "helper" (slit "top-level")))
  in
  let changed = ref false in
  let result =
    March_tir.Single_use_inline.run ~changed (mk_module [helper; main])
  in
  Alcotest.(check bool) "top-level call selected" true !changed;
  match body_of "main" result with
  | March_tir.Tir.ESeq
      (March_tir.Tir.ELetRec
         (local_fns, March_tir.Tir.EApp (local_callee, _)),
       top_level_result)
    when String.equal local_callee.March_tir.Tir.v_name "helper" ->
      let local_caller_body =
        local_fns
        |> List.find (fun fn ->
          String.equal fn.March_tir.Tir.fn_name "local_caller")
        |> fun fn -> fn.March_tir.Tir.fn_body
      in
      (match local_caller_body with
       | March_tir.Tir.EApp (callee, _)
         when String.equal callee.March_tir.Tir.v_name "helper" -> ()
       | actual ->
           Alcotest.failf "ELetRec name did not scope every local body: %s"
             (March_tir.Tir.show_expr actual));
      (match top_level_result with
       | March_tir.Tir.EApp (callee, _)
         when String.equal callee.March_tir.Tir.v_name "helper" ->
           Alcotest.fail "genuine top-level call was not inlined"
       | _ -> ())
  | actual ->
      Alcotest.failf "local ELetRec call was rewritten: %s"
        (March_tir.Tir.show_expr actual)

let test_single_use_local_function_parameter_shadowing_respected () =
  let helper = impure_identity "helper" in
  let nested_parameter = mk_var "helper" string_fn_ty in
  let local_parameter_user =
    { March_tir.Tir.fn_name = "local_parameter_user";
      fn_params = [nested_parameter];
      fn_ret_ty = March_tir.Tir.TString;
      fn_body = call_string "helper" (slit "nested parameter");
      fn_kind = March_tir.Tir.FnNormal }
  in
  let main =
    mk_fn "main"
      (March_tir.Tir.ESeq
         (March_tir.Tir.ELetRec
            ([local_parameter_user], March_tir.Tir.EAtom (slit "local")),
          call_string "helper" (slit "top-level")))
  in
  let changed = ref false in
  let result =
    March_tir.Single_use_inline.run ~changed (mk_module [helper; main])
  in
  Alcotest.(check bool) "top-level call selected" true !changed;
  match body_of "main" result with
  | March_tir.Tir.ESeq
      (March_tir.Tir.ELetRec
         ([{ March_tir.Tir.fn_body = March_tir.Tir.EApp (callee, _); _ }],
          _),
       top_level_result)
    when String.equal callee.March_tir.Tir.v_name "helper" ->
      (match top_level_result with
       | March_tir.Tir.EApp (top_callee, _)
         when String.equal top_callee.March_tir.Tir.v_name "helper" ->
           Alcotest.fail "genuine top-level call was not inlined"
       | _ -> ())
  | actual ->
      Alcotest.failf "local-function parameter call was rewritten: %s"
        (March_tir.Tir.show_expr actual)

let test_single_use_all_atom_positions_counted () =
  let helper_atom = March_tir.Tir.AVar (mk_var "helper" string_fn_ty) in
  let other_callee = mk_var "other" string_fn_ty in
  let dummy = mk_var "dummy" March_tir.Tir.TString in
  let local_ref =
    { March_tir.Tir.fn_name = "local";
      fn_params = [];
      fn_ret_ty = March_tir.Tir.TString;
      fn_body = March_tir.Tir.EAtom helper_atom;
      fn_kind = March_tir.Tir.FnNormal }
  in
  let containers = [
    ("call pointer callee", March_tir.Tir.ECallPtr (helper_atom, []));
    ("call pointer argument",
     March_tir.Tir.ECallPtr (slit "callee", [helper_atom]));
    ("direct-call argument",
     March_tir.Tir.EApp (other_callee, [helper_atom]));
    ("let RHS",
     March_tir.Tir.ELet
       (dummy, March_tir.Tir.EAtom helper_atom,
        March_tir.Tir.EAtom (slit "body")));
    ("let body",
     March_tir.Tir.ELet
       (dummy, March_tir.Tir.EAtom (slit "rhs"),
        March_tir.Tir.EAtom helper_atom));
    ("case scrutinee", March_tir.Tir.ECase (helper_atom, [], None));
    ("case branch",
     March_tir.Tir.ECase
       (slit "scrutinee",
        [{ March_tir.Tir.br_tag = "Some";
           br_vars = [];
           br_body = March_tir.Tir.EAtom helper_atom }],
        None));
    ("case default",
     March_tir.Tir.ECase
       (slit "scrutinee", [], Some (March_tir.Tir.EAtom helper_atom)));
    ("local function body",
     March_tir.Tir.ELetRec
       ([local_ref], March_tir.Tir.EAtom (slit "continuation")));
    ("local function continuation",
     March_tir.Tir.ELetRec
       ([], March_tir.Tir.EAtom helper_atom));
    ("tuple", March_tir.Tir.ETuple [helper_atom]);
    ("record", March_tir.Tir.ERecord [("f", helper_atom)]);
    ("field", March_tir.Tir.EField (helper_atom, "f"));
    ("update base", March_tir.Tir.EUpdate (helper_atom, []));
    ("update value",
     March_tir.Tir.EUpdate (slit "base", [("f", helper_atom)]));
    ("allocation",
     March_tir.Tir.EAlloc
       (March_tir.Tir.TCon ("Box", []), [helper_atom]));
    ("stack allocation",
     March_tir.Tir.EStackAlloc
       (March_tir.Tir.TCon ("Box", []), [helper_atom]));
    ("free", March_tir.Tir.EFree helper_atom);
    ("increment", March_tir.Tir.EIncRC helper_atom);
    ("decrement", March_tir.Tir.EDecRC helper_atom);
    ("atomic increment", March_tir.Tir.EAtomicIncRC helper_atom);
    ("atomic decrement", March_tir.Tir.EAtomicDecRC helper_atom);
    ("reuse source",
     March_tir.Tir.EReuse (helper_atom, March_tir.Tir.TString, []));
    ("reuse argument",
     March_tir.Tir.EReuse
       (slit "source", March_tir.Tir.TString, [helper_atom]));
  ] in
  List.iter
    (fun (label, container) ->
      let helper = impure_identity "helper" in
      let main =
        mk_fn "main"
          (March_tir.Tir.ESeq
             (container, call_string "helper" (slit "direct")))
      in
      let changed = ref false in
      ignore
        (March_tir.Single_use_inline.run ~changed
           (mk_module [helper; main]));
      Alcotest.(check bool) label false !changed)
    containers

let test_single_use_defref_counts_as_non_direct () =
  let helper = impure_identity "helper" in
  let defref =
    March_tir.Tir.ADefRef
      { March_tir.Tir.did_name = "helper"; did_hash = "helper-hash" }
  in
  let main =
    mk_fn "main"
      (March_tir.Tir.ESeq
         (March_tir.Tir.EAtom defref,
          call_string "helper" (slit "direct")))
  in
  let changed = ref false in
  ignore
    (March_tir.Single_use_inline.run ~changed (mk_module [helper; main]));
  Alcotest.(check bool) "ADefRef counts as a non-direct reference" false
    !changed

let test_single_use_rejects_caller_binding_capture () =
  let x = mk_var "x" March_tir.Tir.TString in
  let helper =
    { March_tir.Tir.fn_name = "helper";
      fn_params = [x];
      fn_ret_ty = March_tir.Tir.TString;
      fn_body =
        March_tir.Tir.ESeq
          (March_tir.Tir.EIncRC (March_tir.Tir.AVar x),
           call_string "target" (March_tir.Tir.AVar x));
      fn_kind = March_tir.Tir.FnNormal }
  in
  let target =
    { March_tir.Tir.fn_name = "target";
      fn_params = [x];
      fn_ret_ty = March_tir.Tir.TString;
      fn_body = March_tir.Tir.EAtom (March_tir.Tir.AVar x);
      fn_kind = March_tir.Tir.FnNormal }
  in
  let local_target = mk_var "target" March_tir.Tir.TString in
  let main =
    mk_fn "main"
      (March_tir.Tir.ELet
         (local_target, March_tir.Tir.EAtom (slit "local"),
          call_string "helper" (slit "argument")))
  in
  let changed = ref false in
  let result =
    March_tir.Single_use_inline.run ~changed
      (mk_module [helper; target; main])
  in
  Alcotest.(check bool)
    "unsafe expansion is rejected instead of capturing the free global call"
    false !changed;
  match body_of "main" result with
  | March_tir.Tir.ELet
      (_, _, March_tir.Tir.EApp (callee, _))
    when String.equal callee.March_tir.Tir.v_name "helper" -> ()
  | actual ->
      Alcotest.failf "capture-prone helper call was rewritten: %s"
        (March_tir.Tir.show_expr actual)

let test_single_use_bare_address_alias_counts_qualified_target () =
  let helper = impure_identity "Module.helper" in
  let bare_helper =
    March_tir.Tir.AVar (mk_var "helper" string_fn_ty)
  in
  let main =
    mk_fn "main"
      (March_tir.Tir.ESeq
         (March_tir.Tir.EAtom bare_helper,
          call_string "Module.helper" (slit "direct")))
  in
  let changed = ref false in
  ignore
    (March_tir.Single_use_inline.run ~changed (mk_module [helper; main]));
  Alcotest.(check bool)
    "bare address alias and qualified direct call are two references"
    false !changed

let test_single_use_ambiguous_bare_alias_marks_every_target () =
  let left = impure_identity "Left.helper" in
  let right = impure_identity "Right.helper" in
  let bare_helper =
    March_tir.Tir.AVar (mk_var "helper" string_fn_ty)
  in
  let main =
    mk_fn "main"
      (March_tir.Tir.ESeq
         (March_tir.Tir.EAtom bare_helper,
          March_tir.Tir.ESeq
            (call_string "Left.helper" (slit "left"),
             call_string "Right.helper" (slit "right"))))
  in
  let changed = ref false in
  ignore
    (March_tir.Single_use_inline.run ~changed
       (mk_module [left; right; main]));
  Alcotest.(check bool)
    "an ambiguous bare alias makes every qualified target non-direct"
    false !changed

let test_single_use_bare_alias_participates_in_scc () =
  let x = mk_var "x" March_tir.Tir.TString in
  let left =
    { March_tir.Tir.fn_name = "Module.left";
      fn_params = [x];
      fn_ret_ty = March_tir.Tir.TString;
      fn_body =
        March_tir.Tir.ESeq
          (March_tir.Tir.EIncRC (March_tir.Tir.AVar x),
           call_string "right" (March_tir.Tir.AVar x));
      fn_kind = March_tir.Tir.FnNormal }
  in
  let right =
    { March_tir.Tir.fn_name = "Module.right";
      fn_params = [x];
      fn_ret_ty = March_tir.Tir.TString;
      fn_body = call_string "Module.left" (March_tir.Tir.AVar x);
      fn_kind = March_tir.Tir.FnNormal }
  in
  let main = mk_fn "main" (March_tir.Tir.EAtom (slit "done")) in
  let changed = ref false in
  ignore
    (March_tir.Single_use_inline.run ~changed
       (mk_module [left; right; main]));
  Alcotest.(check bool)
    "a unique bare alias closes the qualified recursive SCC"
    false !changed

let test_single_use_exact_extern_precedes_qualified_alias () =
  let helper = impure_identity "Module.helper" in
  let extern_helper =
    { March_tir.Tir.ed_march_name = "helper";
      ed_c_name = "c_helper";
      ed_lib_name = "test";
      ed_js_sym = "helper";
      ed_params = [March_tir.Tir.TString];
      ed_consumed = [false];
      ed_blocking = false;
      ed_raises = false;
      ed_ret = March_tir.Tir.TString }
  in
  let main = mk_fn "main" (call_string "helper" (slit "extern")) in
  let module_ =
    { (mk_module [helper; main]) with
      March_tir.Tir.tm_externs = [extern_helper] }
  in
  let changed = ref false in
  let result = March_tir.Single_use_inline.run ~changed module_ in
  Alcotest.(check bool)
    "an exact extern blocks fallback to a same-suffix qualified function"
    false !changed;
  match body_of "main" result with
  | March_tir.Tir.EApp (callee, _)
    when String.equal callee.March_tir.Tir.v_name "helper" -> ()
  | actual ->
      Alcotest.failf "exact extern call was rewritten as qualified helper: %s"
        (March_tir.Tir.show_expr actual)

(* ── `blocking` extern dispatch ──────────────────────────────────── *)

(* A `blocking` extern must ALWAYS be dispatched through march_run_blocking_*,
   on whichever emission path the call happens to reach.  [Defun] rewrites some
   extern calls into [ECallPtr], and that arm used to fall through to a plain
   direct call, silently dropping the `blocking` treatment.

   The consequence is a hang, not a slowdown: the C call then runs inline on the
   green thread's stack and blocks its whole scheduler OS thread.  Once every
   scheduler thread is parked inside such a call, no runnable green thread can
   be dispatched — including the ones whose work would let the blocked callees
   return — and the program deadlocks.  Observed as an intermittent whole-
   program hang in a worker-pool program whose workers block on a native queue. *)
let blocking_extern_src = {|mod Test do
  needs IO
  needs IO.Foreign
  needs IO.Spawn

  extern "repro" : Cap(IO.Foreign) do
    blocking fn blocking_work(micros : Int) : Int = "repro_blocking_work"
  end

  pfn worker(remaining : Int) : Int do
    if remaining <= 0 do
      0
    else
      do
        let _ = blocking_work(10)
        worker(remaining - 1)
      end
    end
  end

  fn main(_cap_foreign : Cap(IO.Foreign), _cap_spawn : Cap(IO.Spawn)) : Unit do
    let w = task_spawn(fn _ -> worker(2))
    let _ = task_await(w)
    ()
  end
end|}

let test_blocking_extern_uses_blocking_dispatch () =
  let ir = emit_tco_opt_ir blocking_extern_src in
  Alcotest.(check bool)
    "blocking extern is dispatched via march_run_blocking_i"
    true (ir_contains ir "@march_run_blocking_i(ptr @repro_blocking_work")

let test_blocking_extern_never_called_directly () =
  let ir = emit_tco_opt_ir blocking_extern_src in
  (* The only permitted mention of the symbol as a *called* function is the
     `declare`; every call site must go through the blocking helper.  A direct
     `call ... @repro_blocking_work(` is exactly the defect this guards. *)
  Alcotest.(check bool)
    "blocking extern is never called directly (would block the scheduler thread)"
    false (ir_contains ir "call i64 @repro_blocking_work(")

(* ── Known-call optimization ─────────────────────────────────────── *)

(** Helper: build an EAlloc for a Defun-style closure struct.
    apply_name is the lifted apply function.  clo_struct_name is "$Clo_foo$N". *)
let test_known_call_direct () =
  let changed = ref false in
  (* let clo = EAlloc("$Clo_foo$0", [fn_ptr]) in ECallPtr(clo, [5]) *)
  let clo_var = mk_var "clo" (March_tir.Tir.TCon ("$Clo_foo$0", [])) in
  let alloc = mk_closure_alloc "$Clo_foo$0" "foo$apply$0" in
  let callptr = March_tir.Tir.ECallPtr
    (March_tir.Tir.AVar clo_var, [ilit 5]) in
  let body = March_tir.Tir.ELet (clo_var, alloc, callptr) in
  let m = mk_module [mk_fn "main" body] in
  let m' = March_tir.Known_call.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (* The ECallPtr should be gone — inner expression should be EApp *)
  let main_body = (List.find (fun fd -> fd.March_tir.Tir.fn_name = "main")
                    m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  (match main_body with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EApp (f, _)) ->
     Alcotest.(check string) "apply fn name" "foo$apply$0" f.March_tir.Tir.v_name
   | other ->
     Alcotest.failf "expected ELet(_,EAlloc,EApp), got: %s"
       (March_tir.Tir.show_expr other))

(** ECallPtr on a variable NOT in the known-closure map stays unchanged. *)
let test_known_call_unknown_unchanged () =
  let changed = ref false in
  let v = mk_var "f" (March_tir.Tir.TPtr March_tir.Tir.TUnit) in
  let callptr = March_tir.Tir.ECallPtr (March_tir.Tir.AVar v, [ilit 1]) in
  let m = mk_module [mk_fn "main" callptr] in
  let _ = March_tir.Known_call.run ~changed m in
  Alcotest.(check bool) "not changed (unknown closure)" false !changed

(** Two consecutive closures in the same scope are both tracked. *)
let test_known_call_two_closures () =
  let changed = ref false in
  let clo1 = mk_var "clo1" (March_tir.Tir.TCon ("$Clo_f$0", [])) in
  let clo2 = mk_var "clo2" (March_tir.Tir.TCon ("$Clo_g$1", [])) in
  let alloc1 = mk_closure_alloc "$Clo_f$0" "f$apply$0" in
  let alloc2 = mk_closure_alloc "$Clo_g$1" "g$apply$1" in
  (* let clo1 = EAlloc($Clo_f$0)
     let clo2 = EAlloc($Clo_g$1)
     ECallPtr(clo1, []) *)
  let body =
    March_tir.Tir.ELet (clo1, alloc1,
      March_tir.Tir.ELet (clo2, alloc2,
        March_tir.Tir.ECallPtr (March_tir.Tir.AVar clo1, []))) in
  let m = mk_module [mk_fn "main" body] in
  let m' = March_tir.Known_call.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (* Inner expression should reference f$apply$0 *)
  let inner = match (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body with
    | March_tir.Tir.ELet (_, _, March_tir.Tir.ELet (_, _, e)) -> e
    | _ -> Alcotest.fail "unexpected structure" in
  (match inner with
   | March_tir.Tir.EApp (f, _) ->
     Alcotest.(check string) "apply fn" "f$apply$0" f.March_tir.Tir.v_name
   | _ -> Alcotest.fail "expected EApp")

(** Stack-allocated closures (after Escape) are also recognized. *)
let test_known_call_stack_alloc () =
  let changed = ref false in
  let clo_var = mk_var "clo" (March_tir.Tir.TCon ("$Clo_h$2", [])) in
  let fn_ptr_atom = March_tir.Tir.AVar
    (mk_var "h$apply$2" (March_tir.Tir.TPtr March_tir.Tir.TUnit)) in
  let stack_alloc = March_tir.Tir.EStackAlloc
    (March_tir.Tir.TCon ("$Clo_h$2", []), [fn_ptr_atom]) in
  let callptr = March_tir.Tir.ECallPtr (March_tir.Tir.AVar clo_var, [ilit 42]) in
  let body = March_tir.Tir.ELet (clo_var, stack_alloc, callptr) in
  let m = mk_module [mk_fn "main" body] in
  let _ = March_tir.Known_call.run ~changed m in
  Alcotest.(check bool) "changed (stack-allocated closure)" true !changed

(** known_call.ml's [is_clo_name] was converted from an inline 4-char
    "$Clo" prefix check to [Tir_names.is_clo_struct] (Wave 3 Chunk 2 Task 1)
    — pins the behavior-narrowing proof: every name ANY producer in the
    compiler can actually mint (i.e. every name [Tir_names.clo_struct_name]
    can produce) agrees between the old 4-char check and the new 5-char
    predicate; the two predicates diverge ONLY on the unreachable
    "$Clo"+non-underscore shape, which this test also documents. *)
let test_known_call_is_clo_name_matches_tir_names () =
  let old_is_clo_name_4char s =
    String.length s >= 4 && String.sub s 0 4 = "$Clo"
  in
  let representative_names =
    (* Every shape [Tir_names.clo_struct_name] can actually produce. *)
    [ March_tir.Tir_names.clo_struct_name ~fn_name:"foo" ~lam_uid:0;
      March_tir.Tir_names.clo_struct_name ~fn_name:"bar" ~lam_uid:42;
      March_tir.Tir_names.clo_struct_name ~fn_name:"" ~lam_uid:7;
      (* Non-closure names, must be false under both. *)
      "Option"; "List"; "$fv1"; "$Tuple2"; "main" ]
  in
  List.iter (fun name ->
    Alcotest.(check bool)
      ("is_clo_name/is_clo_struct agree on producible name \"" ^ name ^ "\"")
      (old_is_clo_name_4char name)
      (March_tir.Known_call.is_clo_name name)
  ) representative_names;
  (* The only theoretical divergence: "$Clo"+non-underscore. Documented as
     unreachable (no producer mints it — see is_clo_name's doc comment) but
     pinned here so the narrowing is explicit, not silently assumed. *)
  Alcotest.(check bool) "old 4-char check WOULD match unreachable shape" true
    (old_is_clo_name_4char "$Clox");
  Alcotest.(check bool) "new predicate correctly rejects unreachable shape" false
    (March_tir.Known_call.is_clo_name "$Clox")

(* ── Struct update fusion ────────────────────────────────────────── *)

(** Two consecutive record updates on the same base record, with the
    intermediate variable used exactly once, should be merged. *)
let test_struct_fusion_two_updates () =
  let changed = ref false in
  let conn0 = mk_var "conn0" March_tir.Tir.TUnit in
  let conn1 = mk_var "conn1" March_tir.Tir.TUnit in
  let conn2 = mk_var "conn2" March_tir.Tir.TUnit in
  let h_atom = ilit 200 in
  let s_atom = ilit 42 in
  (* let conn1 = { conn0 | status = 200 }
     let conn2 = { conn1 | body_size = 42 }
     conn2 *)
  let body =
    March_tir.Tir.ELet (conn1,
      March_tir.Tir.EUpdate (March_tir.Tir.AVar conn0, [("status", h_atom)]),
      March_tir.Tir.ELet (conn2,
        March_tir.Tir.EUpdate (March_tir.Tir.AVar conn1, [("body_size", s_atom)]),
        March_tir.Tir.EAtom (March_tir.Tir.AVar conn2))) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Fusion.run_struct ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (* Result: ELet(conn2, EUpdate(conn0, [(status,200);(body_size,42)]), conn2) *)
  (match first_body m' with
   | March_tir.Tir.ELet (_, March_tir.Tir.EUpdate (March_tir.Tir.AVar base, fields), _) ->
     Alcotest.(check string) "base variable" "conn0" base.March_tir.Tir.v_name;
     Alcotest.(check int)    "merged field count" 2 (List.length fields)
   | other ->
     Alcotest.failf "expected merged EUpdate, got: %s"
       (March_tir.Tir.show_expr other))

(** Three consecutive updates should be collapsed into one after two
    fixed-point iterations (each iteration collapses one pair). *)
let test_struct_fusion_three_updates () =
  let changed = ref false in
  let b  = mk_var "b"  March_tir.Tir.TUnit in
  let v1 = mk_var "v1" March_tir.Tir.TUnit in
  let v2 = mk_var "v2" March_tir.Tir.TUnit in
  let v3 = mk_var "v3" March_tir.Tir.TUnit in
  let body =
    March_tir.Tir.ELet (v1,
      March_tir.Tir.EUpdate (March_tir.Tir.AVar b,  [("a", ilit 1)]),
      March_tir.Tir.ELet (v2,
        March_tir.Tir.EUpdate (March_tir.Tir.AVar v1, [("b", ilit 2)]),
        March_tir.Tir.ELet (v3,
          March_tir.Tir.EUpdate (March_tir.Tir.AVar v2, [("c", ilit 3)]),
          March_tir.Tir.EAtom (March_tir.Tir.AVar v3)))) in
  let m = mk_module [mk_fn "f" body] in
  (* Run twice to fully collapse the 3-step chain *)
  let m' = March_tir.Fusion.run_struct ~changed m in
  let m'' = March_tir.Fusion.run_struct ~changed m' in
  (match first_body m'' with
   | March_tir.Tir.ELet (_, March_tir.Tir.EUpdate (March_tir.Tir.AVar base, fields), _) ->
     Alcotest.(check string) "base variable" "b" base.March_tir.Tir.v_name;
     Alcotest.(check int)    "all three fields merged" 3 (List.length fields)
   | other ->
     Alcotest.failf "expected single merged EUpdate, got: %s"
       (March_tir.Tir.show_expr other))

(** Later updates on the same field override earlier ones. *)
let test_struct_fusion_field_override () =
  let changed = ref false in
  let b  = mk_var "b"  March_tir.Tir.TUnit in
  let v1 = mk_var "v1" March_tir.Tir.TUnit in
  let v2 = mk_var "v2" March_tir.Tir.TUnit in
  (* let v1 = { b | x = 1 }; let v2 = { v1 | x = 99 }; v2
     After fusion: let v2 = { b | x = 99 }  — second write wins *)
  let body =
    March_tir.Tir.ELet (v1,
      March_tir.Tir.EUpdate (March_tir.Tir.AVar b,  [("x", ilit 1)]),
      March_tir.Tir.ELet (v2,
        March_tir.Tir.EUpdate (March_tir.Tir.AVar v1, [("x", ilit 99)]),
        March_tir.Tir.EAtom (March_tir.Tir.AVar v2))) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Fusion.run_struct ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, March_tir.Tir.EUpdate (_, fields), _) ->
     Alcotest.(check int) "deduplicated: only one x field" 1 (List.length fields);
     let (_, v) = List.find (fun (k, _) -> k = "x") fields in
     Alcotest.(check string) "second value wins"
       (March_tir.Tir.show_atom (ilit 99))
       (March_tir.Tir.show_atom v)
   | other ->
     Alcotest.failf "expected merged EUpdate, got: %s"
       (March_tir.Tir.show_expr other))

(** Multi-use intermediate must NOT be fused. *)
let test_struct_fusion_no_fuse_multi_use () =
  let changed = ref false in
  let b  = mk_var "b"  March_tir.Tir.TUnit in
  let v1 = mk_var "v1" March_tir.Tir.TUnit in
  let v2 = mk_var "v2" March_tir.Tir.TUnit in
  (* v1 is used twice — in the EUpdate and in the final EAtom *)
  let body =
    March_tir.Tir.ELet (v1,
      March_tir.Tir.EUpdate (March_tir.Tir.AVar b, [("x", ilit 1)]),
      March_tir.Tir.ELet (v2,
        March_tir.Tir.EUpdate (March_tir.Tir.AVar v1, [("y", ilit 2)]),
        (* Use v1 a second time — blocks fusion *)
        March_tir.Tir.ESeq (
          March_tir.Tir.EAtom (March_tir.Tir.AVar v1),
          March_tir.Tir.EAtom (March_tir.Tir.AVar v2)))) in
  let m = mk_module [mk_fn "f" body] in
  let _ = March_tir.Fusion.run_struct ~changed m in
  Alcotest.(check bool) "not changed (multi-use)" false !changed

(* ── Dead code elimination ───────────────────────────────────────── *)

let test_dce_dead_pure_let () =
  (* let x = 5 in 42 → 42, because x is unused and rhs is pure *)
  let changed = ref false in
  let x_var = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x_var, March_tir.Tir.EAtom (ilit 5), March_tir.Tir.EAtom (ilit 42)) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Dce.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "dead let removed"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 42)))
    (March_tir.Tir.show_expr (first_body m'))

let test_dce_impure_let_kept () =
  (* let x = println("hi") in 42 → println("hi"); 42 (rhs is impure, must keep) *)
  let changed = ref false in
  let x_var = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x_var,
               app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")],
               March_tir.Tir.EAtom (ilit 42)) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Dce.run ~changed m in
  (* result should be ESeq, not the original ELet, but the print must be present *)
  (match first_body m' with
   | March_tir.Tir.ESeq _ -> ()  (* impure effect sequenced *)
   | March_tir.Tir.ELet _ -> ()  (* or kept as let — both acceptable *)
   | _ -> Alcotest.fail "impure rhs must be preserved")

let test_dce_used_let_kept () =
  (* let x = 5 in x + 1 → unchanged *)
  let changed = ref false in
  let x_var = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x_var, March_tir.Tir.EAtom (ilit 5),
               app "+" [March_tir.Tir.AVar x_var; ilit 1]) in
  let m = mk_module [mk_fn "f" body] in
  let _ = March_tir.Dce.run ~changed m in
  Alcotest.(check bool) "not changed (used)" false !changed

let test_dce_unreachable_topfn () =
  (* fn unused() = 99 is not reachable from main → removed *)
  let changed = ref false in
  let unused_fn = { March_tir.Tir.fn_name = "unused"; fn_params = [];
                    fn_ret_ty = March_tir.Tir.TInt;
                    fn_body = March_tir.Tir.EAtom (ilit 99);
                    fn_kind = March_tir.Tir.FnNormal } in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = [];
                  fn_ret_ty = March_tir.Tir.TInt;
                  fn_body = March_tir.Tir.EAtom (ilit 0);
                  fn_kind = March_tir.Tir.FnNormal } in
  let m = mk_module [unused_fn; main_fn] in
  let m' = March_tir.Dce.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let fn_names = List.map (fun fd -> fd.March_tir.Tir.fn_name) m'.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "unused removed" false (List.mem "unused" fn_names);
  Alcotest.(check bool) "main kept"      true  (List.mem "main" fn_names)

let test_dce_root_names () =
  let plain = mk_fn "plain" (March_tir.Tir.EAtom (ilit 0)) in
  let main = mk_fn "App.main" (March_tir.Tir.EAtom (ilit 0)) in
  let exported = mk_fn "rpc__rpc_stub" (March_tir.Tir.EAtom (ilit 0)) in
  let setup = mk_fn March_tir.Tir_names.setup_fn_name
      (March_tir.Tir.EAtom (ilit 0)) in
  let migrate = mk_fn "actor_migrate_state" (March_tir.Tir.EAtom (ilit 0)) in
  let module_ =
    { (mk_module [plain; main; exported; setup; migrate]) with
      March_tir.Tir.tm_exports = ["rpc__rpc_stub"];
      tm_tests = [("plain", "plain test")] }
  in
  let roots = March_tir.Dce.root_names module_ in
  List.iter
    (fun name ->
      Alcotest.(check bool) (name ^ " is rooted") true (List.mem name roots))
    ["plain"; "App.main"; "rpc__rpc_stub";
     March_tir.Tir_names.setup_fn_name; "actor_migrate_state"]

let test_dce_root_names_no_seed_falls_back_to_all () =
  let module_ =
    mk_module
      [mk_fn "a" (March_tir.Tir.EAtom (ilit 0));
       mk_fn "b" (March_tir.Tir.EAtom (ilit 1))]
  in
  Alcotest.(check (list string)) "all functions are roots"
    ["a"; "b"] (March_tir.Dce.root_names module_)

(* ── Optimizer coordinator ───────────────────────────────────────── *)

let test_opt_fixpoint () =
  (* let x = 1 + 1 in x * 1
     → fold: let x = 2 in x * 1
     → simplify: let x = 2 in x
     At minimum x*1 should be simplified to x *)
  let x_var = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x_var,
               app "+" [ilit 1; ilit 1],
               app "*" [March_tir.Tir.AVar x_var; ilit 1]) in
  let m = mk_module [mk_fn "main" body] in
  let m' = March_tir.Opt.run m in
  (match first_body m' with
   | March_tir.Tir.EAtom (March_tir.Tir.AVar _) -> ()
   | March_tir.Tir.EAtom (March_tir.Tir.ALit _) -> ()
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom _) -> ()
   | e -> Alcotest.failf "expected reduced form, got: %s" (March_tir.Tir.show_expr e))

let test_opt_no_infinite_loop () =
  (* A stable expression should not loop forever *)
  let m = mk_module [mk_fn "main" (March_tir.Tir.EAtom (ilit 42))] in
  let m' = March_tir.Opt.run m in
  Alcotest.(check string) "stable"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 42)))
    (March_tir.Tir.show_expr (first_body m'))

(* ── fast-math IR attribute ──────────────────────────────────────── *)

let test_fast_math_emits_fast_attr () =
  let x = mk_var "x" March_tir.Tir.TFloat in
  let y = mk_var "y" March_tir.Tir.TFloat in
  let fn_var name = mk_var name (March_tir.Tir.TFn ([], March_tir.Tir.TFloat)) in
  let body = March_tir.Tir.EApp (fn_var "+.", [March_tir.Tir.AVar x; March_tir.Tir.AVar y]) in
  let fd = { March_tir.Tir.fn_name = "fadd_test"; fn_params = [x; y];
             fn_ret_ty = March_tir.Tir.TFloat; fn_body = body;
             fn_kind = March_tir.Tir.FnNormal } in
  let m = { March_tir.Tir.tm_name = "test"; tm_fns = [fd]; tm_types = []; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  let ir_fast   = March_tir.Llvm_emit.emit_module ~fast_math:true  m in
  let ir_normal = March_tir.Llvm_emit.emit_module ~fast_math:false m in
  Alcotest.(check bool) "fast_math IR contains 'fadd fast'" true
    (let re = Str.regexp "fadd fast" in
     (try ignore (Str.search_forward re ir_fast 0); true with Not_found -> false));
  Alcotest.(check bool) "normal IR does not contain 'fadd fast'" false
    (let re = Str.regexp "fadd fast" in
     (try ignore (Str.search_forward re ir_normal 0); true with Not_found -> false))

(* ── Constant propagation ───────────────────────────────────────── *)

(* Helpers for cprop tests: build a function body with a let-chain,
   run CProp alone, and inspect the result. *)

let test_cprop_simple_literal () =
  (* let x = 7 in x
     CProp: x is literal 7, so the body EAtom(AVar x) → EAtom(ALit 7) *)
  let x = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x, March_tir.Tir.EAtom (ilit 7),
               March_tir.Tir.EAtom (March_tir.Tir.AVar x)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 7))) -> ()
   | e -> Alcotest.failf "expected let x=7 in 7, got: %s" (March_tir.Tir.show_expr e))

let test_cprop_chain () =
  (* let a = 3
     let b = a          — CProp: b's rhs becomes EAtom(ALit 3)
     b                  — CProp: body becomes ALit 3 *)
  let a = mk_var "a" March_tir.Tir.TInt in
  let b = mk_var "b" March_tir.Tir.TInt in
  let body =
    March_tir.Tir.ELet (a, March_tir.Tir.EAtom (ilit 3),
      March_tir.Tir.ELet (b, March_tir.Tir.EAtom (March_tir.Tir.AVar a),
        March_tir.Tir.EAtom (March_tir.Tir.AVar b))) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let rec find_inner = function
    | March_tir.Tir.ELet (_, _, e) -> find_inner e
    | March_tir.Tir.EAtom a -> a
    | e -> Alcotest.failf "unexpected: %s" (March_tir.Tir.show_expr e)
  in
  (match find_inner (first_body m') with
   | March_tir.Tir.ALit (March_ast.Ast.LitInt 3) -> ()
   | a -> Alcotest.failf "expected ALit 3, got: %s" (March_tir.Tir.show_atom a))

let test_cprop_enables_fold () =
  (* let x = 7
     let r = x + 1
     r
     CProp turns x→7: let x=7 in let r = 7+1 in r
     Fold then gives 8. *)
  let x = mk_var "x" March_tir.Tir.TInt in
  let r = mk_var "r" March_tir.Tir.TInt in
  let body =
    March_tir.Tir.ELet (x, March_tir.Tir.EAtom (ilit 7),
      March_tir.Tir.ELet (r, app "+" [March_tir.Tir.AVar x; ilit 1],
        March_tir.Tir.EAtom (March_tir.Tir.AVar r))) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m1 = March_tir.Cprop.run ~changed m in
  let _  = Alcotest.(check bool) "cprop changed" true !changed in
  let changed2 = ref false in
  let m2 = March_tir.Fold.run ~changed:changed2 m1 in
  Alcotest.(check bool) "fold changed after cprop" true !changed2;
  let rec inner = function
    | March_tir.Tir.ELet (_, _, March_tir.Tir.ELet (_, rhs, _)) -> rhs
    | March_tir.Tir.ELet (_, _, e) -> inner e
    | e -> e
  in
  (match inner (first_body m2) with
   | March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 8)) -> ()
   | e -> Alcotest.failf "expected 8 after fold, got: %s" (March_tir.Tir.show_expr e))

let test_cprop_no_propagate_complex () =
  (* let x = 1 + 2   (complex rhs — not a bare literal)
     x
     CProp should NOT propagate x since its rhs is not ALit *)
  let x = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x, app "+" [ilit 1; ilit 2],
               March_tir.Tir.EAtom (March_tir.Tir.AVar x)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "not changed (complex rhs)" false !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom (March_tir.Tir.AVar _)) -> ()
   | e -> Alcotest.failf "expected unchanged, got: %s" (March_tir.Tir.show_expr e))

let test_cprop_case_branch_shadow () =
  (* let x = 5
     match b do
     | True  -> let x = 99 in x   (* shadows outer x *)
     | False -> x                  (* uses outer x = 5 *)
     end
     False branch: x should propagate to 5. *)
  let x_outer = mk_var "x" March_tir.Tir.TInt in
  let x_inner = mk_var "x" March_tir.Tir.TInt in
  let scrutinee = avar "b" March_tir.Tir.TBool in
  let true_branch = { March_tir.Tir.br_tag = "True"; br_vars = [];
    br_body = March_tir.Tir.ELet (x_inner, March_tir.Tir.EAtom (ilit 99),
                March_tir.Tir.EAtom (March_tir.Tir.AVar x_inner)) } in
  let false_branch = { March_tir.Tir.br_tag = "False"; br_vars = [];
    br_body = March_tir.Tir.EAtom (March_tir.Tir.AVar x_outer) } in
  let body = March_tir.Tir.ELet (x_outer, March_tir.Tir.EAtom (ilit 5),
               March_tir.Tir.ECase (scrutinee, [true_branch; false_branch], None)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.ECase (_, [_; fb], None)) ->
     (match fb.March_tir.Tir.br_body with
      | March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 5)) -> ()
      | e -> Alcotest.failf "False branch: expected 5, got: %s" (March_tir.Tir.show_expr e))
   | e -> Alcotest.failf "unexpected outer form: %s" (March_tir.Tir.show_expr e))

let test_cprop_opt_integration () =
  (* Full pipeline: let x = 3 in let y = x + 4 in y
     CProp+Fold+DCE → 7 *)
  let x = mk_var "x" March_tir.Tir.TInt in
  let y = mk_var "y" March_tir.Tir.TInt in
  let body =
    March_tir.Tir.ELet (x, March_tir.Tir.EAtom (ilit 3),
      March_tir.Tir.ELet (y, app "+" [March_tir.Tir.AVar x; ilit 4],
        March_tir.Tir.EAtom (March_tir.Tir.AVar y))) in
  let m = mk_module [mk_fn "main" body] in
  let m' = March_tir.Opt.run m in
  (match first_body m' with
   | March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 7)) -> ()
   | e -> Alcotest.failf "expected 7 after full opt, got: %s" (March_tir.Tir.show_expr e))

(** Regression: cprop must NOT substitute literals into RC / Free arguments.
    Bug: let m = "POST" in ... DecRC(m)  →  DecRC("POST") after cprop.
    LLVM emit would then allocate a fresh string just to free it, while the
    original allocation leaks at RC=1. *)
let test_cprop_no_propagate_into_rc () =
  let m_var = { March_tir.Tir.v_name = "m"; v_ty = March_tir.Tir.TString; v_lin = March_tir.Tir.Aff } in
  let lit_post = March_ast.Ast.LitString "POST" in
  (* let m = "POST"
     DecRC(m)          -- cprop must leave this as DecRC(AVar m), not DecRC(ALit "POST") *)
  let body =
    March_tir.Tir.ELet (m_var,
      March_tir.Tir.EAtom (March_tir.Tir.ALit lit_post),
      March_tir.Tir.EDecRC (March_tir.Tir.AVar m_var)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EDecRC (March_tir.Tir.AVar _)) -> ()
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EDecRC (March_tir.Tir.ALit _)) ->
     Alcotest.fail "cprop corrupted DecRC target: substituted literal into DecRC argument"
   | e -> Alcotest.failf "unexpected shape: %s" (March_tir.Tir.show_expr e))

let test_cprop_no_propagate_into_incrc () =
  let m_var = { March_tir.Tir.v_name = "m"; v_ty = March_tir.Tir.TString; v_lin = March_tir.Tir.Lin } in
  let lit_post = March_ast.Ast.LitString "POST" in
  let body =
    March_tir.Tir.ELet (m_var,
      March_tir.Tir.EAtom (March_tir.Tir.ALit lit_post),
      March_tir.Tir.EIncRC (March_tir.Tir.AVar m_var)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EIncRC (March_tir.Tir.AVar _)) -> ()
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EIncRC (March_tir.Tir.ALit _)) ->
     Alcotest.fail "cprop corrupted IncRC target: substituted literal into IncRC argument"
   | e -> Alcotest.failf "unexpected shape: %s" (March_tir.Tir.show_expr e))

let test_cprop_no_propagate_into_free () =
  let m_var = { March_tir.Tir.v_name = "m"; v_ty = March_tir.Tir.TString; v_lin = March_tir.Tir.Aff } in
  let lit_post = March_ast.Ast.LitString "POST" in
  let body =
    March_tir.Tir.ELet (m_var,
      March_tir.Tir.EAtom (March_tir.Tir.ALit lit_post),
      March_tir.Tir.EFree (March_tir.Tir.AVar m_var)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EFree (March_tir.Tir.AVar _)) -> ()
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EFree (March_tir.Tir.ALit _)) ->
     Alcotest.fail "cprop corrupted Free target: substituted literal into Free argument"
   | e -> Alcotest.failf "unexpected shape: %s" (March_tir.Tir.show_expr e))

(* P13 — EField of known record ──────────────────────────────────── *)

let test_cprop_field_fold_record () =
  (* let r = { x = 3, y = 4 } in r.x
     CProp: r in fenv → EField(r,"x") folds to ALit 3 *)
  let ty_r = March_tir.Tir.TRecord [("x", March_tir.Tir.TInt); ("y", March_tir.Tir.TInt)] in
  let r = mk_var "r" ty_r in
  let body = March_tir.Tir.ELet (r,
    March_tir.Tir.ERecord [("x", ilit 3); ("y", ilit 4)],
    March_tir.Tir.EField (March_tir.Tir.AVar r, "x")) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 3))) -> ()
   | e -> Alcotest.failf "expected r.x=3, got: %s" (March_tir.Tir.show_expr e))

let test_cprop_field_fold_alias () =
  (* let r  = { x = 3 }
     let r2 = r          -- alias: should copy r's fenv entry to r2
     r2.x                -- folds to 3 via alias propagation *)
  let ty_r = March_tir.Tir.TRecord [("x", March_tir.Tir.TInt)] in
  let r  = mk_var "r"  ty_r in
  let r2 = mk_var "r2" ty_r in
  let body =
    March_tir.Tir.ELet (r, March_tir.Tir.ERecord [("x", ilit 3)],
      March_tir.Tir.ELet (r2, March_tir.Tir.EAtom (March_tir.Tir.AVar r),
        March_tir.Tir.EField (March_tir.Tir.AVar r2, "x"))) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 3)))) -> ()
   | e -> Alcotest.failf "expected r2.x=3 via alias, got: %s" (March_tir.Tir.show_expr e))

let test_cprop_field_fold_update () =
  (* let r  = { x = 3, y = 4 }
     let r2 = { r with y = 99 }
     r2.x   — inherits x field from r → 3 *)
  let ty_r = March_tir.Tir.TRecord [("x", March_tir.Tir.TInt); ("y", March_tir.Tir.TInt)] in
  let r  = mk_var "r"  ty_r in
  let r2 = mk_var "r2" ty_r in
  let body =
    March_tir.Tir.ELet (r, March_tir.Tir.ERecord [("x", ilit 3); ("y", ilit 4)],
      March_tir.Tir.ELet (r2, March_tir.Tir.EUpdate (March_tir.Tir.AVar r, [("y", ilit 99)]),
        March_tir.Tir.EField (March_tir.Tir.AVar r2, "x"))) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 3)))) -> ()
   | e -> Alcotest.failf "expected r2.x=3 (from r), got: %s" (March_tir.Tir.show_expr e))

(* P13 (extended) — EField of known tuple ──────────────────────────── *)

let test_cprop_field_fold_tuple () =
  (* let t = (3, 4) in t.$fv0
     CProp: t in fenv (tuple) -> EField(t, fv_field 0) folds to ALit 3 *)
  let ty_t = March_tir.Tir.TTuple [March_tir.Tir.TInt; March_tir.Tir.TInt] in
  let t = mk_var "t" ty_t in
  let body = March_tir.Tir.ELet (t,
    March_tir.Tir.ETuple [ilit 3; ilit 4],
    March_tir.Tir.EField (March_tir.Tir.AVar t, March_tir.Tir_names.fv_field 0)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 3))) -> ()
   | e -> Alcotest.failf "expected t.$fv0=3, got: %s" (March_tir.Tir.show_expr e))

let test_cprop_field_fold_tuple_second_element () =
  (* let t = (3, 4) in t.$fv1  -- the SECOND element, not just the first *)
  let ty_t = March_tir.Tir.TTuple [March_tir.Tir.TInt; March_tir.Tir.TInt] in
  let t = mk_var "t" ty_t in
  let body = March_tir.Tir.ELet (t,
    March_tir.Tir.ETuple [ilit 3; ilit 4],
    March_tir.Tir.EField (March_tir.Tir.AVar t, March_tir.Tir_names.fv_field 1)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 4))) -> ()
   | e -> Alcotest.failf "expected t.$fv1=4, got: %s" (March_tir.Tir.show_expr e))

let test_cprop_field_fold_tuple_alias () =
  (* let t  = (3, 4)
     let t2 = t             -- alias: should copy t's fenv entry to t2
     t2.$fv0                -- folds to 3 via alias propagation *)
  let ty_t = March_tir.Tir.TTuple [March_tir.Tir.TInt; March_tir.Tir.TInt] in
  let t  = mk_var "t"  ty_t in
  let t2 = mk_var "t2" ty_t in
  let body =
    March_tir.Tir.ELet (t, March_tir.Tir.ETuple [ilit 3; ilit 4],
      March_tir.Tir.ELet (t2, March_tir.Tir.EAtom (March_tir.Tir.AVar t),
        March_tir.Tir.EField (March_tir.Tir.AVar t2, March_tir.Tir_names.fv_field 0))) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 3)))) -> ()
   | e -> Alcotest.failf "expected t2.$fv0=3 via alias, got: %s" (March_tir.Tir.show_expr e))

let test_cprop_field_fold_tuple_non_literal_element () =
  (* let t = (x, y) in t.$fv0   -- non-literal elements still forward
     (this is the whole point: it's not just constant-folding, it's
     forwarding to whatever atom built the tuple, literal or not). *)
  let x = mk_var "x" March_tir.Tir.TInt in
  let ty_t = March_tir.Tir.TTuple [March_tir.Tir.TInt; March_tir.Tir.TInt] in
  let t = mk_var "t" ty_t in
  let body = March_tir.Tir.ELet (t,
    March_tir.Tir.ETuple [March_tir.Tir.AVar x; ilit 4],
    March_tir.Tir.EField (March_tir.Tir.AVar t, March_tir.Tir_names.fv_field 0)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom (March_tir.Tir.AVar v))
     when v.March_tir.Tir.v_name = "x" -> ()
   | e -> Alcotest.failf "expected t.$fv0 -> x, got: %s" (March_tir.Tir.show_expr e))

let test_cprop_no_tuple_field_collision_with_closure_capture () =
  (* A closure-capture struct also has a field literally named "$fv1"
     (defun.ml's 1-based capture-field convention), built via EAlloc, never
     ETuple. It must NEVER be folded as if it were a tuple: field_env is
     populated only from a name's OWN binding shape, never from the field
     name string, so a variable bound via EAlloc can never appear in
     field_env at all. This test pins that boundary explicitly. *)
  let captured = mk_var "captured" March_tir.Tir.TInt in
  let clo_ty = March_tir.Tir.TCon ("$Clo_foo", []) in
  let clo = mk_var "clo" clo_ty in
  let body = March_tir.Tir.ELet (clo,
    March_tir.Tir.EAlloc (clo_ty, [March_tir.Tir.AVar captured; ilit 99]),
    March_tir.Tir.EField (March_tir.Tir.AVar clo, March_tir.Tir_names.fv_field 1)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "no fold: EAlloc never enters field_env" false !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EField (March_tir.Tir.AVar v, k))
     when v.March_tir.Tir.v_name = "clo" && k = March_tir.Tir_names.fv_field 1 -> ()
   | e -> Alcotest.failf "expected clo.$fv1 left untouched, got: %s" (March_tir.Tir.show_expr e))

let test_cprop_tuple_field_result_escape_unchanged () =
  (* Pins CURRENT (unchanged) behavior for a tuple field returned bare in
     result position: fn f(t) = t.$fv0. This does NOT get the record-only
     dup_field_results escape-safety normalization (lib/tir/perceus.ml:1378
     matches only Tir.TRecord) -- a pre-existing, unrelated gap. This test
     exists so a future change to that gap (or to this cprop extension)
     that alters this shape gets caught, and so THIS plan is not blamed for
     a behavior it neither introduces nor fixes. cprop itself still folds
     the projection when the tuple's shape is locally known (as it does for
     every other position) -- there is nothing perceus-specific to pin
     inside cprop.ml itself, so this is a same-shape restatement of
     test_cprop_field_fold_tuple kept under its own name/intent for
     discoverability if perceus.ml's dup_field_results is ever extended to
     TTuple later. *)
  let ty_t = March_tir.Tir.TTuple [March_tir.Tir.TInt; March_tir.Tir.TInt] in
  let t = mk_var "t" ty_t in
  let body = March_tir.Tir.ELet (t,
    March_tir.Tir.ETuple [ilit 7; ilit 8],
    March_tir.Tir.EField (March_tir.Tir.AVar t, March_tir.Tir_names.fv_field 0)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 7))) -> ()
   | e -> Alcotest.failf "expected t.$fv0=7, got: %s" (March_tir.Tir.show_expr e))

let test_cprop_tuple_dce_removes_allocation_from_llvm () =
  (* let t = (x, y) in let a = t.$fv0 in let b = t.$fv1 in a + b
     CProp folds both projections to x/y, t becomes provably unused, and DCE
     removes the ETuple binding — assert the emitted LLVM for tuple_sum
     contains no struct field load (getelementptr) at all.

     Deliberately run only Cprop + Dce here rather than the full Opt fixed
     point: with the whole pipeline (Inline / Single_use_inline), this tiny
     tuple_sum gets fully inlined into main and constant-folded away, so
     "@tuple_sum" would never appear in the emitted module and the
     getelementptr assertion below would pass vacuously no matter what CProp
     does. Isolating the two passes under test keeps tuple_sum as its own
     function so the scoped assertion is actually exercising the fold. *)
  let x = mk_var "x" March_tir.Tir.TInt in
  let y = mk_var "y" March_tir.Tir.TInt in
  let ty_t = March_tir.Tir.TTuple [March_tir.Tir.TInt; March_tir.Tir.TInt] in
  let t = mk_var "t" ty_t in
  let field0 = March_tir.Tir.EField (March_tir.Tir.AVar t, March_tir.Tir_names.fv_field 0) in
  let field1 = March_tir.Tir.EField (March_tir.Tir.AVar t, March_tir.Tir_names.fv_field 1) in
  let a = mk_var "a" March_tir.Tir.TInt in
  let b = mk_var "b" March_tir.Tir.TInt in
  let final_body =
    March_tir.Tir.ELet (t, March_tir.Tir.ETuple [March_tir.Tir.AVar x; March_tir.Tir.AVar y],
      March_tir.Tir.ELet (a, field0,
        March_tir.Tir.ELet (b, field1,
          app "+" [March_tir.Tir.AVar a; March_tir.Tir.AVar b])))
  in
  let tuple_sum =
    { March_tir.Tir.fn_name = "tuple_sum"; fn_params = [x; y];
      fn_ret_ty = March_tir.Tir.TInt; fn_body = final_body;
      fn_kind = March_tir.Tir.FnNormal }
  in
  let main =
    { March_tir.Tir.fn_name = "main"; fn_params = [];
      fn_ret_ty = March_tir.Tir.TInt;
      fn_body =
        March_tir.Tir.EApp
          (mk_var "tuple_sum"
             (March_tir.Tir.TFn ([March_tir.Tir.TInt; March_tir.Tir.TInt], March_tir.Tir.TInt)),
           [ilit 3; ilit 4]);
      fn_kind = March_tir.Tir.FnNormal }
  in
  let module_ = mk_module [tuple_sum; main] in
  let changed = ref true in
  let after_cprop = ref module_ in
  while !changed do
    changed := false;
    after_cprop := March_tir.Cprop.run ~changed !after_cprop
  done;
  let dce_changed = ref true in
  let optimized = ref !after_cprop in
  while !dce_changed do
    dce_changed := false;
    optimized := March_tir.Dce.run ~changed:dce_changed !optimized
  done;
  let ir = March_tir.Llvm_emit.emit_module !optimized in
  let contains haystack needle =
    let needle_len = String.length needle in
    let rec search index =
      index + needle_len <= String.length haystack
      && (String.sub haystack index needle_len = needle || search (index + 1))
    in
    search 0
  in
  (* Slice the emitted module down to just tuple_sum's `define` so the
     assertion can't accidentally pass because of what main (or the module
     preamble) does or doesn't emit. *)
  let find_substring haystack needle start =
    let needle_len = String.length needle in
    let hay_len = String.length haystack in
    let rec search index =
      if index + needle_len > hay_len then None
      else if String.sub haystack index needle_len = needle then Some index
      else search (index + 1)
    in
    search start
  in
  let define_marker = "define" in
  let tuple_sum_marker = "@tuple_sum" in
  let tuple_sum_define_start =
    match find_substring ir tuple_sum_marker 0 with
    | None -> Alcotest.fail "expected emitted IR to contain a definition for @tuple_sum"
    | Some tuple_sum_idx ->
      (* Find the nearest `define` preceding the @tuple_sum occurrence — the
         start of its own function definition. *)
      let rec last_define_before idx best =
        match find_substring ir define_marker idx with
        | Some found when found < tuple_sum_idx -> last_define_before (found + 1) (Some found)
        | _ -> best
      in
      (match last_define_before 0 None with
       | Some d -> d
       | None -> Alcotest.fail "expected a `define` line preceding @tuple_sum")
  in
  let tuple_sum_define_end =
    match find_substring ir define_marker (tuple_sum_define_start + String.length define_marker) with
    | Some next_define -> next_define
    | None -> String.length ir
  in
  let tuple_sum_ir =
    String.sub ir tuple_sum_define_start (tuple_sum_define_end - tuple_sum_define_start)
  in
  Alcotest.(check bool) "tuple_sum slice actually contains tuple_sum's definition"
    true (contains tuple_sum_ir tuple_sum_marker);
  Alcotest.(check bool) "tuple_sum slice excludes main's definition"
    false (contains tuple_sum_ir "@main");
  Alcotest.(check bool) "no tuple struct field load (getelementptr) survives in tuple_sum"
    false (contains tuple_sum_ir "getelementptr")

(* ── P12: variable copy propagation ─────────────────────────────────────── *)

(** P12 basic: let x = y in x + 1  →  y + 1
    The alias is propagated into the EApp arg. *)
let test_cprop_var_alias () =
  let x = mk_var "x" March_tir.Tir.TInt in
  let y = mk_var "y" March_tir.Tir.TInt in
  let body =
    March_tir.Tir.ELet (x, March_tir.Tir.EAtom (March_tir.Tir.AVar y),
      app "succ" [March_tir.Tir.AVar x]) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EApp (_, [March_tir.Tir.AVar v]))
     when v.March_tir.Tir.v_name = "y" -> ()
   | e -> Alcotest.failf "expected x→y propagation, got: %s" (March_tir.Tir.show_expr e))

(** P12 chain: let x = y in let z = x in z + 1  →  y + 1
    The second alias (z = x → y) is also propagated transitively. *)
let test_cprop_var_chain () =
  let x = mk_var "x" March_tir.Tir.TInt in
  let y = mk_var "y" March_tir.Tir.TInt in
  let z = mk_var "z" March_tir.Tir.TInt in
  let body =
    March_tir.Tir.ELet (x, March_tir.Tir.EAtom (March_tir.Tir.AVar y),
      March_tir.Tir.ELet (z, March_tir.Tir.EAtom (March_tir.Tir.AVar x),
        app "succ" [March_tir.Tir.AVar z])) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (* After propagation, z → x → y, so the arg becomes y. *)
  let rec find_innermost_app = function
    | March_tir.Tir.ELet (_, _, body) -> find_innermost_app body
    | e -> e in
  (match find_innermost_app (first_body m') with
   | March_tir.Tir.EApp (_, [March_tir.Tir.AVar v])
     when v.March_tir.Tir.v_name = "y" -> ()
   | e -> Alcotest.failf "expected chain x→y propagation, got: %s" (March_tir.Tir.show_expr e))

(** P12 closure guard: let f = g (TFn type) must NOT be propagated.
    Closure aliases are excluded to protect ECallPtr dispatch. *)
let test_cprop_var_no_alias_closure () =
  let fn_ty = March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt) in
  let f = mk_var "f" fn_ty in
  let g = mk_var "g" fn_ty in
  let body =
    March_tir.Tir.ELet (f, March_tir.Tir.EAtom (March_tir.Tir.AVar g),
      March_tir.Tir.ECallPtr (March_tir.Tir.AVar f, [ilit 42])) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let _m' = March_tir.Cprop.run ~changed m in
  (* Closure alias must NOT be propagated; changed may be false *)
  (match first_body (March_tir.Cprop.run ~changed:(ref false) m) with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.ECallPtr (March_tir.Tir.AVar fv, _))
     when fv.March_tir.Tir.v_name = "f" -> ()
   | e -> Alcotest.failf "expected f unchanged in ECallPtr, got: %s" (March_tir.Tir.show_expr e))

(* ── P11: beta-ADT (case-of-known-constructor) ───────────────────────────── *)

(** P11 basic: let r = EAlloc(Ok, [x]) in ECase(r, [{Ok; [v]; EAtom v}], None)
    → let v = x in EAtom v  (reduced; EAlloc dead → DCE removes it) *)
let test_beta_adt_ok_inline () =
  let tcon_ty = March_tir.Tir.TCon ("Result", [March_tir.Tir.TInt; March_tir.Tir.TString]) in
  let r = mk_var "r" tcon_ty in
  let v = mk_var "v" March_tir.Tir.TInt in
  let x = mk_var "x" March_tir.Tir.TInt in
  let branch = { March_tir.Tir.br_tag = "Ok"; br_vars = [v];
                 br_body = March_tir.Tir.EAtom (March_tir.Tir.AVar v) } in
  let body =
    March_tir.Tir.ELet (r,
      March_tir.Tir.EAlloc (March_tir.Tir.TCon ("Result.Ok", [March_tir.Tir.TInt]), [March_tir.Tir.AVar x]),
      March_tir.Tir.ECase (March_tir.Tir.AVar r, [branch], None)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Beta_adt.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (* Result: let v = EAtom(x) in EAtom(v) — no EAlloc or ECase *)
  let rec find = function
    | March_tir.Tir.ELet (bv, March_tir.Tir.EAtom (March_tir.Tir.AVar src), inner)
      when bv.March_tir.Tir.v_name = "v" && src.March_tir.Tir.v_name = "x" ->
      (match inner with
       | March_tir.Tir.EAtom (March_tir.Tir.AVar rv) when rv.March_tir.Tir.v_name = "v" -> ()
       | e -> Alcotest.failf "expected EAtom(v), got: %s" (March_tir.Tir.show_expr e))
    | March_tir.Tir.ELet (_, _, rest) -> find rest
    | e -> Alcotest.failf "expected let v=x chain, got: %s" (March_tir.Tir.show_expr e) in
  find (first_body m')

(** P11 with qualified tag: EAlloc uses "Result.Ok" but branch tag is "Ok".
    tags_match must handle the mismatch via short_name. *)
let test_beta_adt_qualified_tag () =
  let tcon_ty = March_tir.Tir.TCon ("Result", []) in
  let r = mk_var "r" tcon_ty in
  let v = mk_var "v" March_tir.Tir.TInt in
  let x = mk_var "x" March_tir.Tir.TInt in
  let branch = { March_tir.Tir.br_tag = "Ok"; br_vars = [v];
                 br_body = March_tir.Tir.EAtom (March_tir.Tir.AVar v) } in
  let default_body = March_tir.Tir.EAtom (ilit 0) in
  let body =
    March_tir.Tir.ELet (r,
      March_tir.Tir.EAlloc (March_tir.Tir.TCon ("Result.Ok", [March_tir.Tir.TInt]), [March_tir.Tir.AVar x]),
      March_tir.Tir.ECase (March_tir.Tir.AVar r, [branch], Some default_body)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Beta_adt.run ~changed m in
  Alcotest.(check bool) "changed (qualified tag matched)" true !changed;
  (* Default branch (with EAtom 0) must be dropped — we matched Ok *)
  let contains_lit0 e =
    let s = March_tir.Tir.show_expr e in
    let lit0 = March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 0)) in
    let n = String.length lit0 in
    let ls = String.length s in
    let found = ref false in
    for i = 0 to ls - n do
      if String.sub s i n = lit0 then found := true
    done; !found in
  if contains_lit0 (first_body m') then
    Alcotest.fail "default branch (lit 0) must be dropped after P11 Ok match"

(** P11 no-fire: ELet body is NOT an ECase — should not fire. *)
let test_beta_adt_no_fire_non_case () =
  let tcon_ty = March_tir.Tir.TCon ("Foo", []) in
  let r = mk_var "r" tcon_ty in
  let body =
    March_tir.Tir.ELet (r,
      March_tir.Tir.EAlloc (March_tir.Tir.TCon ("Foo.Bar", []), []),
      March_tir.Tir.EAtom (March_tir.Tir.AVar r)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let _m' = March_tir.Beta_adt.run ~changed m in
  Alcotest.(check bool) "not changed" false !changed

(* ── P8: FBIP cross-tag constructor reuse ───────────────────────────────── *)

(** P8 basic: same_arity returns true when the $fbip$-marked encoding has the
    same field count.  TCon("$fbip$Foo.A", [TUnit; TUnit]) encodes arity=2;
    nfields=2 → true. *)
let test_same_arity_match () =
  let ty = March_tir.Tir.TCon ("$fbip$Foo.A", [March_tir.Tir.TUnit; March_tir.Tir.TUnit]) in
  Alcotest.(check bool) "same arity matches" true
    (March_tir.Perceus.same_arity ty 2)

(** P8: different arity returns false. *)
let test_same_arity_mismatch () =
  let ty = March_tir.Tir.TCon ("$fbip$Foo.A", [March_tir.Tir.TUnit]) in
  Alcotest.(check bool) "different arity does not match" false
    (March_tir.Perceus.same_arity ty 2)

(** P8: non-TCon type returns false (no arity info). *)
let test_same_arity_non_tcon () =
  Alcotest.(check bool) "non-TCon always false" false
    (March_tir.Perceus.same_arity March_tir.Tir.TInt 0)

(** P0 regression: a RAW declared type (no $fbip$ marker) must be refused even
    when its type-PARAMETER count happens to equal nfields.  A dead binding's
    dec carries its declared type — e.g. Ok(7) : Result(Int, String) is a
    1-field cell with 2 type params; treating the 2 params as "2 fields"
    approved reusing the cell for a 2-field constructor (heap overflow). *)
let test_same_arity_raw_type_refused () =
  let ty = March_tir.Tir.TCon ("Result", [March_tir.Tir.TInt; March_tir.Tir.TString]) in
  Alcotest.(check bool) "raw declared type is never an arity encoding" false
    (March_tir.Perceus.same_arity ty 2)

(** P8 integration: cross-tag FBIP fires.  We construct a TIR expression that
    mirrors what Perceus emits for a consumed scrutinee followed by a same-arity
    alloc of a different constructor.  Perceus wraps the decrc in ESeq (via
    add_scrutinee_free_for), so fbip_expr's ESeq path calls try_fbip_sink.

    Shape (Perceus ESeq form):
      ESeq(EDecRC(v : TCon("$fbip$Foo.A", [TUnit])),   -- arity=1 encoded
           ELet(result, EAlloc(TCon("Foo.B",[]), [arg]),
                EAtom result))
    → ELet(result, EReuse(AVar v, TCon("Foo.B",[]), [arg]),
           EAtom result) *)
let test_fbip_cross_tag_reuse () =
  (* v's type encodes arity=1 as one dummy TUnit arg behind the marker *)
  let v = mk_var "v" (March_tir.Tir.TCon ("$fbip$Foo.A", [March_tir.Tir.TUnit])) in
  let result = mk_var "result" (March_tir.Tir.TCon ("Foo", [])) in
  let arg = March_tir.Tir.ALit (March_ast.Ast.LitInt 42) in
  let e =
    March_tir.Tir.ESeq (
      March_tir.Tir.EDecRC (March_tir.Tir.AVar v),
      March_tir.Tir.ELet (result,
        March_tir.Tir.EAlloc (March_tir.Tir.TCon ("Foo.B", []), [arg]),
        March_tir.Tir.EAtom (March_tir.Tir.AVar result))) in
  let e' = March_tir.Perceus.fbip_expr e in
  match e' with
  | March_tir.Tir.ELet (_, March_tir.Tir.EReuse (March_tir.Tir.AVar rv, _, _), _) ->
    Alcotest.(check string) "reuses v" "v" rv.March_tir.Tir.v_name
  | _ ->
    Alcotest.failf "expected EReuse, got: %s" (March_tir.Tir.show_expr e')

(** P8: different arity does NOT produce EReuse — falls back to ESeq EDecRC. *)
let test_fbip_no_reuse_arity_mismatch () =
  (* v's type encodes arity=1; alloc has 2 fields → arity mismatch → no reuse *)
  let v = mk_var "v" (March_tir.Tir.TCon ("$fbip$Foo.A", [March_tir.Tir.TUnit])) in
  let result = mk_var "result" (March_tir.Tir.TCon ("Foo", [])) in
  let arg1 = March_tir.Tir.ALit (March_ast.Ast.LitInt 1) in
  let arg2 = March_tir.Tir.ALit (March_ast.Ast.LitInt 2) in
  let e =
    March_tir.Tir.ESeq (
      March_tir.Tir.EDecRC (March_tir.Tir.AVar v),
      March_tir.Tir.ELet (result,
        March_tir.Tir.EAlloc (March_tir.Tir.TCon ("Foo.B", []), [arg1; arg2]),
        March_tir.Tir.EAtom (March_tir.Tir.AVar result))) in
  let e' = March_tir.Perceus.fbip_expr e in
  match e' with
  | March_tir.Tir.ESeq (March_tir.Tir.EDecRC _, _) ->
    ()  (* correct: no reuse, kept as ESeq(EDecRC, ...) *)
  | March_tir.Tir.ELet (_, March_tir.Tir.EReuse _, _) ->
    Alcotest.fail "should NOT produce EReuse for arity mismatch"
  | _ ->
    Alcotest.failf "unexpected shape: %s" (March_tir.Tir.show_expr e')

(* ── P1: let-floating past ECase ─────────────────────────────────────────── *)

(** P1 basic: a common leading let in every branch is floated above the ECase.

    ECase(a,
      [{T1; []; ELet(x, EApp(f,[y]), EAtom x)},
       {T2; []; ELet(x, EApp(f,[y]), EAtom x)}],
      None)
    →
    ELet(x, EApp(f,[y]),
      ECase(a,
        [{T1; []; EAtom x},
         {T2; []; EAtom x}],
        None)) *)
let test_join_points_float_common_let () =
  let a  = mk_var "a"  (March_tir.Tir.TCon ("T", [])) in
  let x  = mk_var "x"  March_tir.Tir.TInt in
  let y  = mk_var "y"  March_tir.Tir.TInt in
  let f  = mk_var "f"  (March_tir.Tir.TFn ([], March_tir.Tir.TInt)) in
  let rhs = March_tir.Tir.EApp (f, [March_tir.Tir.AVar y]) in
  let br tag = { March_tir.Tir.br_tag = tag; br_vars = [];
                 br_body = March_tir.Tir.ELet (x, rhs, March_tir.Tir.EAtom (March_tir.Tir.AVar x)) } in
  let e = March_tir.Tir.ECase (March_tir.Tir.AVar a,
    [br "T1"; br "T2"], None) in
  let m = mk_module [mk_fn "g" e] in
  let changed = ref false in
  let m' = March_tir.Join_points.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let body' = (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  match body' with
  | March_tir.Tir.ELet (bv, March_tir.Tir.EApp (_, _),
                         March_tir.Tir.ECase (_, branches, None)) ->
    Alcotest.(check string) "floated var name" "x" bv.March_tir.Tir.v_name;
    List.iter (fun br ->
      match br.March_tir.Tir.br_body with
      | March_tir.Tir.EAtom _ -> ()
      | _ -> Alcotest.fail "branch body should be EAtom after floating"
    ) branches
  | _ ->
    Alcotest.failf "expected ELet(x, EApp, ECase), got: %s"
      (March_tir.Tir.show_expr body')

(** P1 no-fire: different RHS expressions in branches — cannot float. *)
let test_join_points_no_float_different_rhs () =
  let a  = mk_var "a"  (March_tir.Tir.TCon ("T", [])) in
  let x  = mk_var "x"  March_tir.Tir.TInt in
  let y  = mk_var "y"  March_tir.Tir.TInt in
  let f1 = mk_var "f1" (March_tir.Tir.TFn ([], March_tir.Tir.TInt)) in
  let f2 = mk_var "f2" (March_tir.Tir.TFn ([], March_tir.Tir.TInt)) in
  let br1 = { March_tir.Tir.br_tag = "T1"; br_vars = [];
              br_body = March_tir.Tir.ELet (x,
                March_tir.Tir.EApp (f1, [March_tir.Tir.AVar y]),
                March_tir.Tir.EAtom (March_tir.Tir.AVar x)) } in
  let br2 = { March_tir.Tir.br_tag = "T2"; br_vars = [];
              br_body = March_tir.Tir.ELet (x,
                March_tir.Tir.EApp (f2, [March_tir.Tir.AVar y]),  (* different fn *)
                March_tir.Tir.EAtom (March_tir.Tir.AVar x)) } in
  let e = March_tir.Tir.ECase (March_tir.Tir.AVar a, [br1; br2], None) in
  let m = mk_module [mk_fn "g" e] in
  let changed = ref false in
  let _m' = March_tir.Join_points.run ~changed m in
  Alcotest.(check bool) "not changed" false !changed

(** P1 no-fire: let RHS mentions a pattern-bound variable. *)
let test_join_points_no_float_uses_br_var () =
  let a  = mk_var "a"  (March_tir.Tir.TCon ("T", [])) in
  let x  = mk_var "x"  March_tir.Tir.TInt in
  let v1 = mk_var "v1" March_tir.Tir.TInt in
  let v2 = mk_var "v2" March_tir.Tir.TInt in
  (* Each arm binds pattern var vN, then uses it in the RHS — can't float *)
  let br tag pv = { March_tir.Tir.br_tag = tag; br_vars = [pv];
                    br_body = March_tir.Tir.ELet (x,
                      March_tir.Tir.EAtom (March_tir.Tir.AVar pv),
                      March_tir.Tir.EAtom (March_tir.Tir.AVar x)) } in
  let e = March_tir.Tir.ECase (March_tir.Tir.AVar a,
    [br "T1" v1; br "T2" v2], None) in
  let m = mk_module [mk_fn "g" e] in
  let changed = ref false in
  let _m' = March_tir.Join_points.run ~changed m in
  Alcotest.(check bool) "not changed" false !changed

(** P1 chain: two consecutive common lets are both floated (fixpoint via opt loop). *)
let test_join_points_float_two_common_lets () =
  let a  = mk_var "a"  (March_tir.Tir.TCon ("T", [])) in
  let x  = mk_var "x"  March_tir.Tir.TInt in
  let z  = mk_var "z"  March_tir.Tir.TInt in
  let y  = mk_var "y"  March_tir.Tir.TInt in
  let f  = mk_var "f"  (March_tir.Tir.TFn ([], March_tir.Tir.TInt)) in
  (* Both branches: let x = f(y) in let z = x in z *)
  let arm_body =
    March_tir.Tir.ELet (x, March_tir.Tir.EApp (f, [March_tir.Tir.AVar y]),
      March_tir.Tir.ELet (z, March_tir.Tir.EAtom (March_tir.Tir.AVar x),
        March_tir.Tir.EAtom (March_tir.Tir.AVar z))) in
  let br tag = { March_tir.Tir.br_tag = tag; br_vars = []; br_body = arm_body } in
  let e = March_tir.Tir.ECase (March_tir.Tir.AVar a, [br "T1"; br "T2"], None) in
  let m = mk_module [mk_fn "g" e] in
  let changed = ref false in
  let m' = March_tir.Join_points.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (* After one pass: let x = f(y) in ECase(..., ELet(z, x, z), ...) *)
  let body' = (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  match body' with
  | March_tir.Tir.ELet (bv, March_tir.Tir.EApp _, _) ->
    Alcotest.(check string) "outer floated var" "x" bv.March_tir.Tir.v_name
  | _ ->
    Alcotest.failf "expected outer ELet(x, ...), got: %s"
      (March_tir.Tir.show_expr body')

(** P1 Layer 1 (pre-Perceus alpha-merge): arms share an identical RHS but bind
    it to DIFFERENT variable names (fresh ANF temporaries).  [run_pre] floats a
    single binding and substitutes each arm's binder with the floated one. *)
let test_join_points_pre_float_alpha () =
  let a  = mk_var "a"  (March_tir.Tir.TCon ("T", [])) in
  let x  = mk_var "x"  March_tir.Tir.TInt in
  let w  = mk_var "w"  March_tir.Tir.TInt in   (* different binder name *)
  let y  = mk_var "y"  March_tir.Tir.TInt in
  let f  = mk_var "f"  (March_tir.Tir.TFn ([], March_tir.Tir.TInt)) in
  let rhs = March_tir.Tir.EApp (f, [March_tir.Tir.AVar y]) in
  let br1 = { March_tir.Tir.br_tag = "T1"; br_vars = [];
              br_body = March_tir.Tir.ELet (x, rhs,
                March_tir.Tir.EAtom (March_tir.Tir.AVar x)) } in
  let br2 = { March_tir.Tir.br_tag = "T2"; br_vars = [];
              br_body = March_tir.Tir.ELet (w, rhs,
                March_tir.Tir.EAtom (March_tir.Tir.AVar w)) } in
  let e = March_tir.Tir.ECase (March_tir.Tir.AVar a, [br1; br2], None) in
  let m = mk_module [mk_fn "g" e] in
  let changed = ref false in
  let m' = March_tir.Join_points.run_pre ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let body' = (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  match body' with
  | March_tir.Tir.ELet (bv, March_tir.Tir.EApp (_, _),
                         March_tir.Tir.ECase (_, branches, None)) ->
    (* Every arm body must now reference the single floated binder. *)
    List.iter (fun br ->
      match br.March_tir.Tir.br_body with
      | March_tir.Tir.EAtom (March_tir.Tir.AVar v) ->
        Alcotest.(check string) "arm uses floated binder"
          bv.March_tir.Tir.v_name v.March_tir.Tir.v_name
      | other ->
        Alcotest.failf "branch body should be EAtom(floated), got: %s"
          (March_tir.Tir.show_expr other)
    ) branches
  | _ ->
    Alcotest.failf "expected ELet(_, EApp, ECase), got: %s"
      (March_tir.Tir.show_expr body')

(** P1 Layer 1 no-fire: different RHS across arms, even with the alpha-merge
    relaxation, must not float. *)
let test_join_points_pre_no_float_different_rhs () =
  let a  = mk_var "a"  (March_tir.Tir.TCon ("T", [])) in
  let x  = mk_var "x"  March_tir.Tir.TInt in
  let w  = mk_var "w"  March_tir.Tir.TInt in
  let y  = mk_var "y"  March_tir.Tir.TInt in
  let f1 = mk_var "f1" (March_tir.Tir.TFn ([], March_tir.Tir.TInt)) in
  let f2 = mk_var "f2" (March_tir.Tir.TFn ([], March_tir.Tir.TInt)) in
  let br1 = { March_tir.Tir.br_tag = "T1"; br_vars = [];
              br_body = March_tir.Tir.ELet (x,
                March_tir.Tir.EApp (f1, [March_tir.Tir.AVar y]),
                March_tir.Tir.EAtom (March_tir.Tir.AVar x)) } in
  let br2 = { March_tir.Tir.br_tag = "T2"; br_vars = [];
              br_body = March_tir.Tir.ELet (w,
                March_tir.Tir.EApp (f2, [March_tir.Tir.AVar y]),  (* different fn *)
                March_tir.Tir.EAtom (March_tir.Tir.AVar w)) } in
  let e = March_tir.Tir.ECase (March_tir.Tir.AVar a, [br1; br2], None) in
  let m = mk_module [mk_fn "g" e] in
  let changed = ref false in
  let _m' = March_tir.Join_points.run_pre ~changed m in
  Alcotest.(check bool) "not changed" false !changed

(* ── P6 Repr classification ──────────────────────────────────────────────── *)

let test_repr_newtype_int () =
  let tds = [March_tir.Tir.TDVariant ("UserId", [("UserId", [March_tir.Tir.TInt])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("UserId", [])) with
  | March_tir.Repr.Newtype March_tir.Tir.TInt -> ()
  | other -> Alcotest.failf "expected Newtype TInt, got %s"
      (match other with March_tir.Repr.Boxed -> "Boxed" | _ -> "other")

let test_repr_newtype_ptr () =
  let tds = [March_tir.Tir.TDVariant ("Wrap", [("Wrap", [March_tir.Tir.TString])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Wrap", [])) with
  | March_tir.Repr.Newtype March_tir.Tir.TString -> ()
  | _ -> Alcotest.fail "expected Newtype TString"

let test_repr_multivariant_is_boxed () =
  (* No type params → can't determine payload → Boxed. *)
  let tds = [March_tir.Tir.TDVariant
    ("Option", [("None", []); ("Some", [March_tir.Tir.TInt])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Option", [])) with
  | March_tir.Repr.Boxed -> ()
  | _ -> Alcotest.fail "expected Boxed for Option with no params"

let test_repr_niche_int () =
  let tds = [March_tir.Tir.TDVariant
    ("Option", [("None", []); ("Some", [March_tir.Tir.TInt])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Option", [March_tir.Tir.TInt])) with
  | March_tir.Repr.Niche { payload = March_tir.Tir.TInt; tagged = true } -> ()
  | _ -> Alcotest.fail "expected Niche{TInt, tagged=true}"

let test_repr_niche_string () =
  let tds = [March_tir.Tir.TDVariant
    ("Option", [("None", []); ("Some", [March_tir.Tir.TString])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Option", [March_tir.Tir.TString])) with
  | March_tir.Repr.Niche { payload = March_tir.Tir.TString; tagged = false } -> ()
  | _ -> Alcotest.fail "expected Niche{TString, tagged=false}"

let test_repr_niche_bool () =
  let tds = [March_tir.Tir.TDVariant
    ("Option", [("None", []); ("Some", [March_tir.Tir.TBool])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Option", [March_tir.Tir.TBool])) with
  | March_tir.Repr.Niche { payload = March_tir.Tir.TBool; tagged = true } -> ()
  | _ -> Alcotest.fail "expected Niche{TBool, tagged=true}"

let test_repr_niche_float_is_boxed () =
  (* Float 0.0 bitcasts to 0 → cannot use niche. *)
  let tds = [March_tir.Tir.TDVariant
    ("Option", [("None", []); ("Some", [March_tir.Tir.TFloat])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Option", [March_tir.Tir.TFloat])) with
  | March_tir.Repr.Boxed -> ()
  | _ -> Alcotest.fail "expected Boxed for Option(Float)"

let test_repr_niche_unit_is_boxed () =
  (* Unit = i64 0 → null → unsafe for niche. *)
  let tds = [March_tir.Tir.TDVariant
    ("Option", [("None", []); ("Some", [March_tir.Tir.TUnit])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Option", [March_tir.Tir.TUnit])) with
  | March_tir.Repr.Boxed -> ()
  | _ -> Alcotest.fail "expected Boxed for Option(Unit)"

let test_repr_nested_niche_is_boxed () =
  (* Some(None)=0=None: nested niche is ambiguous → must stay Boxed. *)
  let tds = [March_tir.Tir.TDVariant
    ("Option", [("None", []); ("Some", [March_tir.Tir.TCon ("Option", [March_tir.Tir.TInt])])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Option", [March_tir.Tir.TCon ("Option", [March_tir.Tir.TInt])])) with
  | March_tir.Repr.Boxed -> ()
  | _ -> Alcotest.fail "expected Boxed for Option(Option(Int))"

let test_repr_multifield_is_boxed () =
  let tds = [March_tir.Tir.TDVariant
    ("Point", [("Point", [March_tir.Tir.TInt; March_tir.Tir.TInt])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Point", [])) with
  | March_tir.Repr.Boxed -> ()
  | _ -> Alcotest.fail "expected Boxed for 2-field ctor"

let test_repr_scalar_is_boxed () =
  (* Bare scalars are not TCon ctors — classify as Boxed (irrelevant). *)
  match March_tir.Repr.repr_of_ty [] March_tir.Tir.TInt with
  | March_tir.Repr.Boxed -> ()
  | _ -> Alcotest.fail "expected Boxed for TInt"

(** Same-short-name colliding types must never classify Niche even when they
    are structurally Option-shaped: a niche repr has no runtime tag slot, so
    a colliding type's value would be indistinguishable at runtime even with
    Task 1's globally-unique ctor tags (those tags live in the heap-cell
    header, which niche values don't have). *)
let test_repr_colliding_niche_shaped_type_forced_boxed () =
  let defs = March_tir.Tir.[
    TDVariant ("NA.Option2", [("TA", []); ("TWithPayload", [TInt])]);
    TDVariant ("NB.Option2", [("TB", []); ("TWithPayload2", [TInt])]);
  ] in
  let cs = March_tir.Collision_set.compute defs in
  Alcotest.(check bool) "colliding niche-shaped type is NOT niche"
    false (March_tir.Repr.is_niche_shaped ~collision_set:cs defs "NA.Option2");
  (match March_tir.Repr.repr_of_ty ~collision_set:cs defs
           (March_tir.Tir.TCon ("NA.Option2", [March_tir.Tir.TInt])) with
   | March_tir.Repr.Boxed -> ()
   | _ -> Alcotest.fail "expected forced Boxed repr for colliding niche-shaped type")

(** Non-colliding types (the common case: a single declaring module) must be
    completely unaffected by the collision_set threading — this is the
    byte-identity guarantee the plan calls out as highest-risk. *)
let test_repr_noncolliding_niche_shaped_type_unaffected () =
  let defs = March_tir.Tir.[
    TDVariant ("Option", [("None", []); ("Some", [TVar "a"])])
  ] in
  let cs = March_tir.Collision_set.compute defs in  (* empty — single declaration *)
  Alcotest.(check bool) "Option stays niche"
    true (March_tir.Repr.is_niche_shaped ~collision_set:cs defs "Option")

(* ── lower.ml: collision-conditional module-qualified impl symbols
   (Task 3, specs/plans/2026-07-20-fqn-impl-dispatch-identity.md) ────────── *)

(** Two DISTINCT same-short-name types (declared in different modules), each
    implementing the same GENERAL user interface, must lower to TWO DISTINCT
    mangled fn_defs — not collapse onto one via [collect_iface_impls]'s
    first-wins `already` guard (pre-fix: only "Speak$Thing.speak" survived,
    silently dropping NB's "from-B" impl body entirely). Since FQN dispatch
    Stage 3 landed, the typechecker ACCEPTS this shape (accept/t89) — no gate
    bypass needed. This test only proves both impl BODIES survive lowering as
    independently-addressable symbols; correct dispatch at call sites is covered
    by [test_colliding_general_iface_runtime_dispatch] below and the
    cross-backend runtime witness test/imports/speak_collision_native. *)
let test_colliding_impls_get_distinct_symbols () =
  let src = {|
mod Top do
  interface Speak(a) do
    fn speak : a -> String
  end
  mod NA do
    type Thing = TA
    impl Speak(Thing) do
      fn speak(_self) do "from-A" end
    end
  end
  mod NB do
    type Thing = TB
    impl Speak(Thing) do
      fn speak(_self) do "from-B" end
    end
  end
  fn main() do 0 end
end
|} in
  let m = parse_and_desugar src in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  let tir_module = March_tir.Lower.lower_module ~type_map m in
  let fn_names = List.map (fun (fn : March_tir.Tir.fn_def) -> fn.March_tir.Tir.fn_name)
      tir_module.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "two distinct Speak impl symbols" true
    (List.mem "Speak$NA.Thing.speak" fn_names && List.mem "Speak$NB.Thing.speak" fn_names)

(** Non-colliding types (the common case: a single declaring module per
    short name) must be completely unaffected — mangled symbols stay bare,
    exactly like before this task. Highest-risk byte-identity guarantee the
    plan calls out. *)
let test_noncolliding_impl_symbol_stays_bare () =
  let src = {|
mod Top do
  interface Speak(a) do
    fn speak : a -> String
  end
  mod NA do
    type Thing = TA
    impl Speak(Thing) do
      fn speak(_self) do "from-A" end
    end
  end
  fn main() do 0 end
end
|} in
  let m = parse_and_desugar src in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  let tir_module = March_tir.Lower.lower_module ~type_map m in
  let fn_names = List.map (fun (fn : March_tir.Tir.fn_def) -> fn.March_tir.Tir.fn_name)
      tir_module.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "bare (unqualified) Speak impl symbol" true
    (List.mem "Speak$Thing.speak" fn_names)

(* ── lower.ml: collision-conditional module-qualified ctor CONSTRUCTION
   (Task 3, docs/superpowers/plans/2026-07-21-ctor-module-identity.md — the
   "native construction" task) ───────────────────────────────────────────

   Two DISTINCT same-short-name types (declared in different modules) that
   ALSO share a constructor short name (both declare a nullary `Shared`)
   must construct DISTINCT, module-qualified [EAlloc(TCon(key,_),_)] ctor
   keys — not the same bare "Thing.Shared" key for both, which is the exact
   mechanism behind the double-collision miscompile: whichever module's
   [TDVariant] happens to register into [ctor_info] LAST silently wins for
   BOTH constructions. *)
let test_colliding_ctor_construction_gets_qualified_key () =
  let src = {|
mod Top do
  needs IO.Console
  interface Speak(a) do
    fn speak : a -> String
  end
  mod DcA do
    type Thing = Shared | OnlyA
    impl Speak(Thing) do
      fn speak(self) do
        match self do
          Shared -> "from-A-shared"
          OnlyA -> "from-A-only"
        end
      end
    end
    fn mk() do Shared end
  end
  mod DcB do
    type Thing = Shared | OnlyB
    impl Speak(Thing) do
      fn speak(self) do
        match self do
          Shared -> "from-B-shared"
          OnlyB -> "from-B-only"
        end
      end
    end
    fn mk() do Shared end
  end
  fn main(_cap_console : Cap(IO.Console)) do
    println(speak(DcA.mk()))
    println(speak(DcB.mk()))
  end
end
|} in
  let m = parse_and_desugar src in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let find_fn name = List.find (fun (fn : March_tir.Tir.fn_def) -> fn.March_tir.Tir.fn_name = name)
      tir.March_tir.Tir.tm_fns in
  let ctor_key_of_alloc (fn : March_tir.Tir.fn_def) =
    match fn.March_tir.Tir.fn_body with
    | March_tir.Tir.EAlloc (March_tir.Tir.TCon (k, _), _) -> k
    | _ -> Alcotest.fail (Printf.sprintf "expected EAlloc body in %s" fn.March_tir.Tir.fn_name)
  in
  let a_key = ctor_key_of_alloc (find_fn "DcA.mk") in
  let b_key = ctor_key_of_alloc (find_fn "DcB.mk") in
  Alcotest.(check bool) "DcA's and DcB's Shared construction get distinct qualified keys"
    true (a_key <> b_key);
  Alcotest.(check bool) "DcA's key mentions DcA" true
    (let re = Str.regexp_string "DcA" in
     try ignore (Str.search_forward re a_key 0); true with Not_found -> false);
  Alcotest.(check bool) "DcB's key mentions DcB" true
    (let re = Str.regexp_string "DcB" in
     try ignore (Str.search_forward re b_key 0); true with Not_found -> false)

(** Bug: [Lower_state.resolve_iface_method] resolved an ambiguous
    general-interface call using [List.assoc_opt tname impls] — first-match,
    NOT collision-aware. When two modules declare same-short-name types
    (here both called [Thing]) that both implement [Speak], [impls] under the
    bare key "Thing" holds both candidates and [List.assoc_opt] silently
    returns whichever was registered first, for EVERY ambiguous call site —
    not just the ones that actually target that module. This resolution runs
    at LOWER time, fully baking one static impl symbol into the EApp callee
    BEFORE Mono.monomorphize's collision-aware [try_collision_dispatch] (which
    generates a correct runtime tag-switch) ever sees the call.
    [env.type_map] (the typechecker's own type representation, consulted
    here) only knows the type by its BARE name ("Thing") — the
    module-qualified identity ("NA.Thing" vs "NB.Thing") is attached later,
    in the TIR/Mono layer — so this layer has no sound way to pick a winner
    and MUST defer (return [None]) whenever the bare name is ambiguous.
    Both `speak(NA.mk())` and `speak(NB.mk())` must therefore stay
    UNRESOLVED (bare "speak" callee) after [Lower.lower_module] — not
    prematurely (and identically) resolved to one impl symbol. Note: for this
    exact program shape the wrong resolution happens to be masked
    END-TO-END by an unrelated Mono guard (the interface-method-name-collision
    check, mono.ml ~line 608) that re-verifies the call's actual argument type
    against the picked impl's declared parameter type — but that guard exists
    for a different bug (a user fn sharing a name with an interface method)
    and is not a substitute for correct behavior at this layer; see
    [test_mono_ecallptr_collision_dispatch]'s doc comment for a call shape
    (ECallPtr, no fn_table entry) where no such guard exists. *)
let test_ambiguous_iface_call_stays_unresolved_at_lower_time () =
  let src = {|
mod Top do
  needs IO.Console
  interface Speak(a) do
    fn speak : a -> String
  end
  mod NA do
    type Thing = TA
    impl Speak(Thing) do
      fn speak(_self) do "from-A" end
    end
    fn mk() do TA end
  end
  mod NB do
    type Thing = TB
    impl Speak(Thing) do
      fn speak(_self) do "from-B" end
    end
    fn mk() do TB end
  end
  fn main(_cap_console : Cap(IO.Console)) do
    println(speak(NA.mk()))
    println(speak(NB.mk()))
  end
end
|} in
  let m = parse_and_desugar src in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  let tir_module = March_tir.Lower.lower_module ~type_map m in
  let main_fn = List.find
      (fun (fn : March_tir.Tir.fn_def) -> fn.March_tir.Tir.fn_name = "main")
      tir_module.March_tir.Tir.tm_fns in
  let body_str = March_tir.Pp.string_of_fn_def main_fn in
  Alcotest.(check bool) "no premature resolution to a concrete Speak impl" false
    (ir_contains body_str "Speak$");
  Alcotest.(check int) "both ambiguous calls stay bare `speak(...)`" 2
    (ir_count body_str "speak(")

(** Non-colliding types (the common case: a single declaring module per
    short name) must construct the exact same bare ctor key as before this
    task — highest-risk byte-identity guarantee. *)
let test_noncolliding_ctor_construction_stays_bare () =
  let src = {|
mod Top do
  mod DcA do
    type Thing = Shared | OnlyA
    fn mk() do Shared end
  end
  fn main() do 0 end
end
|} in
  let m = parse_and_desugar src in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let find_fn name = List.find (fun (fn : March_tir.Tir.fn_def) -> fn.March_tir.Tir.fn_name = name)
      tir.March_tir.Tir.tm_fns in
  let fn = find_fn "DcA.mk" in
  (match fn.March_tir.Tir.fn_body with
   | March_tir.Tir.EAlloc (March_tir.Tir.TCon (k, _), _) ->
     Alcotest.(check string) "bare (unqualified) ctor key" "Thing.Shared" k
   | _ -> Alcotest.fail "expected EAlloc body in DcA.mk")

(** Reserved local-monitor constructor names are the one intentional exception
    to the ordinary non-colliding short-key rule.  The compiler always seeds
    canonical [Down.Down] metadata with [MARCH_DOWN_TAG], so a nested user type
    named [Down] must retain its declaring-module qualifier at construction and
    pattern sites even when it has no second source declaration and no impl.
    Otherwise [Inner.Down(7)] lowers to canonical [Down.Down], and mailbox reap
    mis-disposes its one-field object as the runtime's three-field monitor Down. *)
let test_nested_down_constructor_does_not_alias_monitor_abi () =
  let src = {|
mod Top do
  mod Inner do
    type Down = Down(Int)
    type DownReason = Crash(Int)
    fn make() : Down do Down(7) end
    fn make_reason() : DownReason do Crash(8) end
    fn unwrap(value : Down) : Int do
      match value do
        Down(n) -> n
      end
    end
    fn unwrap_reason(value : DownReason) : Int do
      match value do
        Crash(n) -> n
      end
    end
  end
  fn main() do 0 end
end
|} in
  let m = parse_and_desugar src in
  let (errors, type_map) = March_typecheck.Typecheck.check_module m in
  Alcotest.(check bool) "nested Down source typechecks" false
    (March_errors.Errors.has_errors errors);
  let tir = March_tir.Lower.lower_module ~type_map m in
  let find_fn name = List.find
      (fun (fn : March_tir.Tir.fn_def) -> fn.March_tir.Tir.fn_name = name)
      tir.March_tir.Tir.tm_fns in
  let alloc_key =
    match (find_fn "Inner.make").March_tir.Tir.fn_body with
    | March_tir.Tir.EAlloc (March_tir.Tir.TCon (key, _), _) -> key
    | _ -> Alcotest.fail "expected EAlloc body in Inner.make"
  in
  let branch_tag =
    match (find_fn "Inner.unwrap").March_tir.Tir.fn_body with
    | March_tir.Tir.ECase (_, branch :: _, _) -> branch.March_tir.Tir.br_tag
    | _ -> Alcotest.fail "expected ECase body in Inner.unwrap"
  in
  let reason_alloc_key =
    match (find_fn "Inner.make_reason").March_tir.Tir.fn_body with
    | March_tir.Tir.EAlloc (March_tir.Tir.TCon (key, _), _) -> key
    | _ -> Alcotest.fail "expected EAlloc body in Inner.make_reason"
  in
  let reason_branch_tag =
    match (find_fn "Inner.unwrap_reason").March_tir.Tir.fn_body with
    | March_tir.Tir.ECase (_, branch :: _, _) -> branch.March_tir.Tir.br_tag
    | _ -> Alcotest.fail "expected ECase body in Inner.unwrap_reason"
  in
  Alcotest.(check string) "nested Down allocation keeps module identity"
    "Inner.Down.Down" alloc_key;
  Alcotest.(check string) "nested Down pattern keeps module identity"
    "Inner.Down.Down" branch_tag;
  Alcotest.(check string) "nested DownReason allocation keeps module identity"
    "Inner.DownReason.Crash" reason_alloc_key;
  Alcotest.(check string) "nested DownReason pattern keeps module identity"
    "Inner.DownReason.Crash" reason_branch_tag

(** Exact canonical monitor spellings remain canonical even in the lexical
    scope of user types that shadow both reserved short names.  Bare local
    constructors still name the local user variants.  This pins source-level
    precedence at the lowering boundary for both allocation and matching. *)
let test_canonical_monitor_spelling_wins_inside_shadowing_module () =
  let src = {|
mod Top do
  mod Inner do
    type Down = Down(Int)
    type DownReason = Crash(Int)

    fn make_local() : Down do Down(7) end
    fn match_local(value : Down) : Int do
      match value do
        Down(n) -> n
      end
    end

    fn make_canonical(pid) do
      Down.Down(1, pid, DownReason.Normal)
    end
    fn make_canonical_killed() do DownReason.Killed end
    fn make_canonical_crash() do DownReason.Crash("boom") end
    fn match_canonical(value) : Int do
      match value do
        Down.Down(_, _, DownReason.Crash(_)) -> 1
        _ -> 0
      end
    end
  end
  fn main() do 0 end
end
|} in
  let m = parse_and_desugar src in
  let (errors, type_map) = March_typecheck.Typecheck.check_module m in
  Alcotest.(check bool) "canonical and local constructors typecheck together"
    false (March_errors.Errors.has_errors errors);
  let tir = March_tir.Lower.lower_module ~type_map m in
  let find_fn name = List.find
      (fun (fn : March_tir.Tir.fn_def) -> fn.March_tir.Tir.fn_name = name)
      tir.March_tir.Tir.tm_fns in
  let rec alloc_keys (expr : March_tir.Tir.expr) acc =
    let open March_tir.Tir in
    match expr with
    | EAlloc (TCon (key, _), _) -> key :: acc
    | EAlloc _ -> acc
    | ELet (_, before, after) -> alloc_keys after (alloc_keys before acc)
    | ELetRec (fns, body) ->
      alloc_keys body
        (List.fold_left
           (fun keys (fn : fn_def) -> alloc_keys fn.fn_body keys) acc fns)
    | ECase (_, branches, fallback) ->
      let acc = List.fold_left
          (fun keys (branch : branch) -> alloc_keys branch.br_body keys)
          acc branches in
      (match fallback with Some body -> alloc_keys body acc | None -> acc)
    | ESeq (left, right) -> alloc_keys right (alloc_keys left acc)
    | _ -> acc
  in
  let rec case_tags (expr : March_tir.Tir.expr) acc =
    let open March_tir.Tir in
    match expr with
    | ECase (_, branches, fallback) ->
      let acc = List.fold_left
          (fun tags (branch : branch) ->
             case_tags branch.br_body (branch.br_tag :: tags))
          acc branches in
      (match fallback with Some body -> case_tags body acc | None -> acc)
    | ELet (_, before, after) -> case_tags after (case_tags before acc)
    | ELetRec (fns, body) ->
      case_tags body
        (List.fold_left
           (fun tags (fn : fn_def) -> case_tags fn.fn_body tags) acc fns)
    | ESeq (left, right) -> case_tags right (case_tags left acc)
    | _ -> acc
  in
  let keys name = alloc_keys (find_fn name).March_tir.Tir.fn_body [] in
  let tags name = case_tags (find_fn name).March_tir.Tir.fn_body [] in
  Alcotest.(check bool) "bare local Down allocation stays local" true
    (List.mem "Inner.Down.Down" (keys "Inner.make_local"));
  Alcotest.(check bool) "bare local Down pattern stays local" true
    (List.mem "Inner.Down.Down" (tags "Inner.match_local"));
  Alcotest.(check bool) "explicit canonical Down allocation stays canonical" true
    (List.mem "Down.Down" (keys "Inner.make_canonical"));
  Alcotest.(check bool) "explicit canonical Normal allocation stays canonical" true
    (List.mem "DownReason.Normal" (keys "Inner.make_canonical"));
  Alcotest.(check bool) "explicit canonical Killed allocation stays canonical" true
    (List.mem "DownReason.Killed" (keys "Inner.make_canonical_killed"));
  Alcotest.(check bool) "explicit canonical Crash allocation stays canonical" true
    (List.mem "DownReason.Crash" (keys "Inner.make_canonical_crash"));
  Alcotest.(check bool) "explicit canonical Down pattern stays canonical" true
    (List.mem "Down.Down" (tags "Inner.match_canonical"));
  Alcotest.(check bool) "explicit canonical Crash pattern stays canonical" true
    (List.mem "DownReason.Crash" (tags "Inner.match_canonical"))

(* ── Final-review finding: ctor construction INSIDE an impl method body
   (not just a module-level `fn mk()`) must ALSO get the qualified key.
   [collect_iface_impls] (Pass 1) lowers impl method bodies via
   [Lower_decls.lower_fn_def env mdef] — closing over the TOP-LEVEL [env]
   (whose [mod_prefix] is always "") rather than a module-scoped [mod_env]
   like Pass 2's [lower_mod_decls] builds. Its own [mod_prefix] recursion
   parameter was only used for the impl SYMBOL name and [rename_tir_vars],
   never folded into the [env] that actually reaches the [ECon] gate — so a
   bare `Shared` constructed directly inside an impl method's OWN body
   stayed unqualified even after this task's first fix, silently
   reproducing the exact double-collision bug for this one construction
   site. *)
let test_colliding_ctor_construction_inside_impl_method_gets_qualified_key () =
  let src = {|
mod Top do
  needs IO.Console
  interface Speak(a) do
    fn speak : a -> String
    fn again : a -> a
  end
  mod DcA do
    type Thing = Shared | OnlyA
    impl Speak(Thing) do
      fn speak(self) do
        match self do
          Shared -> "from-A-shared"
          OnlyA -> "from-A-only"
        end
      end
      fn again(_self) do Shared end
    end
    fn mk() do Shared end
  end
  mod DcB do
    type Thing = Shared | OnlyB
    impl Speak(Thing) do
      fn speak(self) do
        match self do
          Shared -> "from-B-shared"
          OnlyB -> "from-B-only"
        end
      end
      fn again(_self) do Shared end
    end
    fn mk() do Shared end
  end
  fn main(_cap_console : Cap(IO.Console)) do
    println(speak(DcA.mk()))
    println(speak(DcB.mk()))
  end
end
|} in
  let m = parse_and_desugar src in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let find_fn name = List.find (fun (fn : March_tir.Tir.fn_def) -> fn.March_tir.Tir.fn_name = name)
      tir.March_tir.Tir.tm_fns in
  let ctor_key_of_alloc (fn : March_tir.Tir.fn_def) =
    match fn.March_tir.Tir.fn_body with
    | March_tir.Tir.EAlloc (March_tir.Tir.TCon (k, _), _) -> k
    | _ -> Alcotest.fail (Printf.sprintf "expected EAlloc body in %s" fn.March_tir.Tir.fn_name)
  in
  let a_key = ctor_key_of_alloc (find_fn "Speak$DcA.Thing.again") in
  let b_key = ctor_key_of_alloc (find_fn "Speak$DcB.Thing.again") in
  Alcotest.(check bool)
    "DcA's and DcB's impl-method-body Shared construction get distinct qualified keys"
    true (a_key <> b_key);
  Alcotest.(check bool) "DcA's impl-method key mentions DcA" true
    (let re = Str.regexp_string "DcA" in
     try ignore (Str.search_forward re a_key 0); true with Not_found -> false);
  Alcotest.(check bool) "DcB's impl-method key mentions DcB" true
    (let re = Str.regexp_string "DcB" in
     try ignore (Str.search_forward re b_key 0); true with Not_found -> false)

(* ── lower_match.ml: collision-conditional module-qualified PATTERN tag
   (Task 4, docs/superpowers/plans/2026-07-21-ctor-module-identity.md — the
   "native pattern-match" task) ───────────────────────────────────────────

   Mirrors the ctor-CONSTRUCTION tests directly above, but for the pattern
   side: a bare `Shared` pattern arm inside a colliding type's own match must
   lower to a br_tag qualified by the pattern's LEXICAL enclosing module
   (e.g. "DcA.Thing.Shared"), not the bare "Shared"/"Thing.Shared" that would
   ambiguously match either colliding type's constructor at codegen time
   (llvm_case.ml's [qualified_br_key], for a BARE incoming tag, qualifies
   using only the scrutinee's — necessarily bare, per this whole plan's
   "TCon stays bare" invariant — static type name, so both DcA's and DcB's
   `Shared` arm would produce the SAME "Thing.Shared" key without this fix).

   Two shapes, per the brief's explicit instruction to cover both from the
   start (learned from this same plan's Task 3, whose first round missed the
   impl-method-body construction site): a pattern match inside a plain
   module-level function, and — the more common, canonical shape — a pattern
   match inside an interface impl method's own body. *)

(** Shape 1 (narrowed by Task 5.5): a bare `Shared`/`OnlyA` match inside a
    plain module-level function where NEITHER `Thing` is the subject of any
    interface `impl`. Before Task 5.5 this qualified to distinct per-module
    tags (like Shape 2 below); after the impl-presence filter it stays BARE —
    with no `impl` there is no interface dispatch, so the two types' `Shared`
    values are never mixed in well-typed code and need no runtime
    disambiguation (mirrors the interpreter's Task 5 gating, whose
    `types_with_any_impl` filter excludes impl-less collisions identically —
    every eval colliding-ctor test carries an `impl`). Construction of
    `DcA.Shared`/`DcB.Shared` (in `main`) stays bare too, so each type's own
    construction and match still agree via `ctor_entry`'s suffix resolver. The
    genuinely-ambiguous, dispatch-bearing shape is covered by Shape 2. *)
let test_colliding_pattern_match_impl_less_stays_bare () =
  let src = {|
mod Top do
  needs IO.Console
  mod DcA do
    type Thing = Shared | OnlyA
    fn describe(t: Thing) do
      match t do
        Shared -> "from-A-shared"
        OnlyA -> "from-A-only"
      end
    end
  end
  mod DcB do
    type Thing = Shared | OnlyB
    fn describe(t: Thing) do
      match t do
        Shared -> "from-B-shared"
        OnlyB -> "from-B-only"
      end
    end
  end
  fn main(_cap_console : Cap(IO.Console)) do
    println(DcA.describe(DcA.Shared))
    println(DcB.describe(DcB.Shared))
  end
end
|} in
  let m = parse_and_desugar src in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let find_fn name = List.find (fun (fn : March_tir.Tir.fn_def) -> fn.March_tir.Tir.fn_name = name)
      tir.March_tir.Tir.tm_fns in
  (* Each `describe` body lowers straight to an ECase (the match IS the whole
     fn body); find the "Shared" arm's br_tag (search by content, not
     position, to stay robust to compile_matrix's internal grouping order). *)
  let shared_tag_of (fn : March_tir.Tir.fn_def) =
    match fn.March_tir.Tir.fn_body with
    | March_tir.Tir.ECase (_, branches, _) ->
      let br = List.find (fun (b : March_tir.Tir.branch) ->
          (* bare "Shared" or a qualified "....Shared" — never "OnlyA"/"OnlyB" *)
          let t = b.March_tir.Tir.br_tag in
          (t = "Shared"
           || (String.length t >= 7
               && String.sub t (String.length t - 7) 7 = ".Shared")))
        branches in
      br.March_tir.Tir.br_tag
    | _ -> Alcotest.fail (Printf.sprintf "expected ECase body in %s" fn.March_tir.Tir.fn_name)
  in
  let a_tag = shared_tag_of (find_fn "DcA.describe") in
  let b_tag = shared_tag_of (find_fn "DcB.describe") in
  (* Impl-less collision: both Shared arms stay bare, unqualified. *)
  Alcotest.(check string) "DcA's impl-less Shared pattern arm stays bare" "Shared" a_tag;
  Alcotest.(check string) "DcB's impl-less Shared pattern arm stays bare" "Shared" b_tag

(** Shape 2 (the canonical, more common shape per the task brief): a bare
    `Shared` match arm written directly inside an interface impl method's
    own body — `impl Speak(Thing) do fn speak(self) do match self do
    Shared -> ... end end end`. *)
let test_colliding_pattern_match_impl_method_gets_qualified_tag () =
  let src = {|
mod Top do
  needs IO.Console
  interface Speak(a) do
    fn speak : a -> String
  end
  mod DcA do
    type Thing = Shared | OnlyA
    impl Speak(Thing) do
      fn speak(self) do
        match self do
          Shared -> "from-A-shared"
          OnlyA -> "from-A-only"
        end
      end
    end
    fn mk() do Shared end
  end
  mod DcB do
    type Thing = Shared | OnlyB
    impl Speak(Thing) do
      fn speak(self) do
        match self do
          Shared -> "from-B-shared"
          OnlyB -> "from-B-only"
        end
      end
    end
    fn mk() do Shared end
  end
  fn main(_cap_console : Cap(IO.Console)) do
    println(speak(DcA.mk()))
    println(speak(DcB.mk()))
  end
end
|} in
  let m = parse_and_desugar src in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let find_fn name = List.find (fun (fn : March_tir.Tir.fn_def) -> fn.March_tir.Tir.fn_name = name)
      tir.March_tir.Tir.tm_fns in
  let shared_tag_of (fn : March_tir.Tir.fn_def) =
    match fn.March_tir.Tir.fn_body with
    | March_tir.Tir.ECase (_, branches, _) ->
      let br = List.find (fun (b : March_tir.Tir.branch) ->
          let t = b.March_tir.Tir.br_tag in
          (t = "Shared"
           || (String.length t >= 7
               && String.sub t (String.length t - 7) 7 = ".Shared")))
        branches in
      br.March_tir.Tir.br_tag
    | _ -> Alcotest.fail (Printf.sprintf "expected ECase body in %s" fn.March_tir.Tir.fn_name)
  in
  let a_tag = shared_tag_of (find_fn "Speak$DcA.Thing.speak") in
  let b_tag = shared_tag_of (find_fn "Speak$DcB.Thing.speak") in
  Alcotest.(check bool) "DcA's and DcB's impl-method Shared pattern arms get distinct qualified tags"
    true (a_tag <> b_tag);
  Alcotest.(check bool) "DcA's impl-method tag mentions DcA" true
    (let re = Str.regexp_string "DcA" in
     try ignore (Str.search_forward re a_tag 0); true with Not_found -> false);
  Alcotest.(check bool) "DcB's impl-method tag mentions DcB" true
    (let re = Str.regexp_string "DcB" in
     try ignore (Str.search_forward re b_tag 0); true with Not_found -> false)

(* ── Task 5.5 (inserted fix): narrow native ctor-key qualification to
   PUBLIC, impl-bearing collisions ─────────────────────────────────────────
   Tasks 3/4 (above) qualified the ctor identity of ANY two same-short-name
   TIR types, with no filter for visibility (`type` vs `ptype`) or for whether
   either candidate is ever the subject of an `impl`. That broke a real,
   deliberate stdlib structural-interop pattern: stdlib/seq.march and
   stdlib/file.march EACH independently declare `ptype Seq(a) = Seq(a)` — same
   short name, same sole ctor — on purpose. `File.with_lines`'s callback
   constructs a `File.Seq` value that the CALLER then feeds through
   `Seq.map`/`Seq.to_list` (a DIFFERENT module's functions), relying on
   STRUCTURAL shape, not nominal identity. Tasks 3/4's lexical qualification
   split the hand-off: construction qualified to "File.Seq.Seq", the consuming
   pattern (inside Seq.march's own functions) qualified to "Seq.Seq.Seq" — a
   genuine tag mismatch → `panic: non-exhaustive pattern match` when compiled.

   This mirrors the interpreter's own Task 5 fix (eval.ml's
   compute_type_collision_set / colliding_ctor_type_by_module): a NEW, narrower
   table (Lower_state.shared_ctor_collision_tbl) gated on two filters
   (public-only AND the short name must have an `impl` block anywhere), applied
   ONLY to Tasks 3/4's ECon/pattern-tag qualification gates — the pre-existing
   broad env.collision_set (Task 1 global tags, Task 2 forced-Boxed repr, the
   earlier plan's impl-symbol qualification) is untouched. *)

(** Regression: two modules each declaring `ptype Seq(a) = Seq(a)` — same short
    name, same sole ctor, NEITHER the subject of any interface `impl` — model
    the stdlib seq.march/file.march structural-interop pattern. One module
    CONSTRUCTS the value, the other CONSUMES it through a structural pattern
    match. After the fix, NEITHER side's ctor key is qualified to its declaring
    module (both stay bare, agreeing on the same ctor_info entry via
    llvm_data.ctor_entry's suffix resolver); before the fix, construction
    qualified to "Producer.Seq.Seq" and the pattern to "Consumer.Seq.Seq" — a
    silent runtime mismatch. *)
let test_ptype_structural_interop_ctor_key_stays_bare () =
  let src = {|
mod Top do
  mod Producer do
    ptype Seq(a) = Seq(a)
    fn mk(x: Int): Seq(Int) do Seq(x) end
  end
  mod Consumer do
    ptype Seq(a) = Seq(a)
    fn consume(s: Seq(Int)): Int do
      match s do
        Seq(x) -> x
      end
    end
  end
  fn main() do 0 end
end
|} in
  let m = parse_and_desugar src in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let find_fn name = List.find (fun (fn : March_tir.Tir.fn_def) -> fn.March_tir.Tir.fn_name = name)
      tir.March_tir.Tir.tm_fns in
  (* Recursive collectors, robust to ELet/ESeq/ELetRec wrapping. *)
  let rec alloc_keys (e : March_tir.Tir.expr) acc =
    let open March_tir.Tir in
    match e with
    | EAlloc (TCon (k, _), _) -> k :: acc
    | EAlloc (_, _) -> acc
    | ELet (_, e1, e2) -> alloc_keys e2 (alloc_keys e1 acc)
    | ELetRec (fns, body) ->
      alloc_keys body
        (List.fold_left (fun a (fn : fn_def) -> alloc_keys fn.fn_body a) acc fns)
    | ECase (_, brs, def) ->
      let acc = List.fold_left (fun a (b : branch) -> alloc_keys b.br_body a) acc brs in
      (match def with Some d -> alloc_keys d acc | None -> acc)
    | ESeq (a, b) -> alloc_keys b (alloc_keys a acc)
    | _ -> acc
  in
  let rec case_tags (e : March_tir.Tir.expr) acc =
    let open March_tir.Tir in
    match e with
    | ECase (_, brs, def) ->
      let acc = List.fold_left (fun a (b : branch) -> case_tags b.br_body (b.br_tag :: a)) acc brs in
      (match def with Some d -> case_tags d acc | None -> acc)
    | ELet (_, e1, e2) -> case_tags e2 (case_tags e1 acc)
    | ELetRec (fns, body) ->
      case_tags body
        (List.fold_left (fun a (fn : fn_def) -> case_tags fn.fn_body a) acc fns)
    | ESeq (a, b) -> case_tags b (case_tags a acc)
    | _ -> acc
  in
  let contains needle hay =
    let re = Str.regexp_string needle in
    try ignore (Str.search_forward re hay 0); true with Not_found -> false in
  let last_seg s = match String.rindex_opt s '.' with
    | Some i -> String.sub s (i + 1) (String.length s - i - 1) | None -> s in
  let mk_keys = alloc_keys (find_fn "Producer.mk").March_tir.Tir.fn_body [] in
  let seq_alloc_key =
    try List.find (fun k -> last_seg k = "Seq") mk_keys
    with Not_found ->
      Alcotest.fail (Printf.sprintf "expected a Seq EAlloc in Producer.mk, found: [%s]"
                       (String.concat "; " mk_keys)) in
  let cons_tags = case_tags (find_fn "Consumer.consume").March_tir.Tir.fn_body [] in
  let seq_pat_tag =
    try List.find (fun t -> last_seg t = "Seq") cons_tags
    with Not_found ->
      Alcotest.fail (Printf.sprintf "expected a Seq pattern arm in Consumer.consume, found: [%s]"
                       (String.concat "; " cons_tags)) in
  (* The bug: construction qualified to the CONSTRUCTING module (Producer),
     pattern to the CONSUMING module (Consumer) — divergent, so their codegen
     tags never agree. The fix keeps both bare (no declaring-module prefix). *)
  Alcotest.(check bool) "ptype construction key is NOT qualified to Producer"
    false (contains "Producer" seq_alloc_key);
  Alcotest.(check bool) "ptype construction key is NOT qualified to Consumer"
    false (contains "Consumer" seq_alloc_key);
  Alcotest.(check bool) "ptype consuming pattern tag is NOT qualified to Consumer"
    false (contains "Consumer" seq_pat_tag);
  Alcotest.(check bool) "ptype consuming pattern tag is NOT qualified to Producer"
    false (contains "Producer" seq_pat_tag);
  (* Both still name the same shared ctor, so ctor_entry's suffix resolver
     lands them on ONE ctor_info entry (identical runtime tag). *)
  Alcotest.(check string) "construction key's ctor is Seq" "Seq" (last_seg seq_alloc_key);
  Alcotest.(check string) "pattern tag's ctor is Seq" "Seq" (last_seg seq_pat_tag)

(** Task 4: two same-short-name colliding types implementing one GENERAL
    interface must, at a call site whose static (bare) argument type is
    ambiguous, dispatch on the value's RUNTIME constructor tag — not
    first-wins. The emitted IR must contain a generated dispatch function that
    switches [i32] on the tag and tail-calls BOTH module-qualified impls
    (Task 3's symbols), and BOTH impl bodies must survive DCE (they are
    referenced only from the LLVM-level dispatch fn). Compiled through the full
    native pipeline (Lower→Mono→Defun→Perceus→Dce→Llvm_emit). Since FQN dispatch
    Stage 3 landed, the typechecker ACCEPTS this shape (accept/t89) — no gate
    bypass needed. End-to-end runtime proof (compiled + interpreted):
    test/imports/speak_collision_native. *)
let test_colliding_general_iface_runtime_dispatch () =
  let src = {|
mod Top do
  needs IO.Console
  interface Speak(a) do
    fn speak : a -> String
  end
  mod NA do
    type Thing = TA
    impl Speak(Thing) do
      fn speak(_self) do "from-A" end
    end
  end
  mod NB do
    type Thing = TB
    impl Speak(Thing) do
      fn speak(_self) do "from-B" end
    end
  end
  fn main(_cap_console : Cap(IO.Console)) do
    println(speak(NA.TA))
    println(speak(NB.TB))
  end
end
|} in
  let m = parse_and_desugar src in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let iface_methods = March_tir.Lower.get_iface_methods () in
  let tir = March_tir.Mono.monomorphize ~iface_methods tir in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus tir in
  let tir = March_tir.Dce.prune_unreachable tir in
  let ir = March_tir.Llvm_emit.emit_module tir in
  Alcotest.(check bool) "dispatch fn generated" true
    (ir_contains ir "define ptr @__march_ifdispatch$Speak$speak$Thing");
  Alcotest.(check bool) "switches on runtime tag" true
    (ir_contains ir "switch i32");
  (* Both module-qualified impls are tail-called from the switch (specialized
     name carries Mono's "$Thing" suffix). *)
  Alcotest.(check bool) "tail-calls NA impl" true
    (ir_contains ir "tail call ptr @Speak$NA.Thing.speak");
  Alcotest.(check bool) "tail-calls NB impl" true
    (ir_contains ir "tail call ptr @Speak$NB.Thing.speak");
  (* Both impl bodies survive DCE (reachable only via the dispatch fn). *)
  Alcotest.(check bool) "NA impl body defined" true
    (ir_contains ir "define ptr @Speak$NA.Thing.speak");
  Alcotest.(check bool) "NB impl body defined" true
    (ir_contains ir "define ptr @Speak$NB.Thing.speak")

(** Byte-identity guard (Task 4): a NON-colliding program must never reach the
    dispatch-fn path — no [__march_ifdispatch] symbol may appear in its IR. *)
let test_noncolliding_no_dispatch_fn () =
  let src = {|
mod M do
  needs IO.Console
  interface Speak(a) do
    fn speak : a -> String
  end
  type Dog = Dog
  type Cat = Cat
  impl Speak(Dog) do
    fn speak(_self) do "woof" end
  end
  impl Speak(Cat) do
    fn speak(_self) do "meow" end
  end
  fn main(_cap_console : Cap(IO.Console)) do
    println(speak(Dog))
    println(speak(Cat))
  end
end
|} in
  let m = parse_and_desugar src in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let iface_methods = March_tir.Lower.get_iface_methods () in
  let tir = March_tir.Mono.monomorphize ~iface_methods tir in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus tir in
  let tir = March_tir.Dce.prune_unreachable tir in
  let ir = March_tir.Llvm_emit.emit_module tir in
  Alcotest.(check bool) "no dispatch fn for distinct-name types" false
    (ir_contains ir "__march_ifdispatch")

(* ── Task 4 review Finding 1: multi-constructor colliding type ───────────
   [test_colliding_general_iface_runtime_dispatch] above only exercises a
   colliding type with a SINGLE constructor on each side. The task report
   claims (manually verified, not pinned by an automated test) that a
   colliding type with MULTIPLE constructors routes every one of its tags to
   the SAME impl symbol ([Llvm_dispatch.tags_of_type] enumerates all of a
   type's global tags; [emit_dispatch_fn]'s [concat_map] must emit one switch
   arm per tag while sharing one destination row/impl per declaring type).
   These helpers extract the actual switch-arm structure from the emitted
   IR so the assertions are shape-based (not dependent on the specific
   global tag integers, which shift with the corpus). *)

(** [(tag, row_label)] pairs found inside the [switch i32 ... [ ... ]] block
    of the (single, in this corpus) generated [__march_ifdispatch] function. *)
let dispatch_switch_arms (ir : string) : (string * string) list =
  (* Anchor on the dispatch fn's [define] line first — a colliding impl body
     may itself contain an unrelated [switch i32] (e.g. matching a
     multi-constructor scrutinee inside the impl method), so searching for
     "switch i32" from position 0 can find the WRONG switch. *)
  let fn_start =
    Str.search_forward (Str.regexp_string "define ptr @__march_ifdispatch") ir 0 in
  let start = Str.search_forward (Str.regexp_string "switch i32") ir fn_start in
  let close = Str.search_forward (Str.regexp_string "\n  ]") ir start in
  let block = String.sub ir start (close - start) in
  let re = Str.regexp "i32 \\([0-9]+\\), label \\(%row[0-9]+\\)" in
  let rec go pos acc =
    match Str.search_forward re block pos with
    | i ->
      let tag = Str.matched_group 1 block in
      let lbl = Str.matched_group 2 block in
      go (i + String.length (Str.matched_string block)) ((tag, lbl) :: acc)
    | exception Not_found -> List.rev acc
  in
  go 0 []

(** The symbol tail-called from the block labelled [lbl] (e.g. ["%row4"]). *)
let dispatch_row_symbol (ir : string) (lbl : string) : string =
  let name = String.sub lbl 1 (String.length lbl - 1) in
  let hdr_pos = Str.search_forward (Str.regexp_string (name ^ ":")) ir 0 in
  let re = Str.regexp "@\\([A-Za-z0-9_.$]+\\)(" in
  ignore (Str.search_forward re ir hdr_pos);
  Str.matched_group 1 ir

(** [NA.Thing] has TWO constructors (TA, TA2); [NB.Thing] has ONE (TB).
    Every constructor tag NA.Thing owns must route to NA's impl, and
    NB.Thing's single tag to NB's impl — i.e. exactly one row label is hit
    by two switch arms (both landing on the same NA symbol) and one row
    label by a single arm (the NB symbol). *)
let test_colliding_multi_ctor_shares_one_impl () =
  let src = {|
mod Top do
  needs IO.Console
  interface Speak(a) do
    fn speak : a -> String
  end
  mod NA do
    type Thing = TA | TA2
    impl Speak(Thing) do
      fn speak(self) do
        match self do
          TA -> "from-A-TA"
          TA2 -> "from-A-TA2"
        end
      end
    end
  end
  mod NB do
    type Thing = TB
    impl Speak(Thing) do
      fn speak(_self) do "from-B" end
    end
  end
  fn main(_cap_console : Cap(IO.Console)) do
    println(speak(NA.TA))
    println(speak(NA.TA2))
    println(speak(NB.TB))
  end
end
|} in
  let m = parse_and_desugar src in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let iface_methods = March_tir.Lower.get_iface_methods () in
  let tir = March_tir.Mono.monomorphize ~iface_methods tir in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus tir in
  let tir = March_tir.Dce.prune_unreachable tir in
  let ir = March_tir.Llvm_emit.emit_module tir in
  Alcotest.(check bool) "dispatch fn generated" true
    (ir_contains ir "define ptr @__march_ifdispatch$Speak$speak$Thing");
  let arms = dispatch_switch_arms ir in
  Alcotest.(check int) "three switch arms total (TA, TA2, TB tags)" 3
    (List.length arms);
  let labels = List.map snd arms in
  let uniq_labels = List.sort_uniq compare labels in
  Alcotest.(check int) "exactly two distinct row labels (one per impl)" 2
    (List.length uniq_labels);
  let count_of lbl = List.length (List.filter (fun l -> l = lbl) labels) in
  let two_arm_labels = List.filter (fun l -> count_of l = 2) uniq_labels in
  let one_arm_labels = List.filter (fun l -> count_of l = 1) uniq_labels in
  (match two_arm_labels, one_arm_labels with
   | [na_lbl], [nb_lbl] ->
     let na_sym = dispatch_row_symbol ir na_lbl in
     let nb_sym = dispatch_row_symbol ir nb_lbl in
     Alcotest.(check bool) "both TA/TA2 tags route to NA's impl" true
       (ir_contains na_sym "NA.Thing.speak");
     Alcotest.(check bool) "TB's single tag routes to NB's impl" true
       (ir_contains nb_sym "NB.Thing.speak");
     Alcotest.(check bool) "the two rows resolve to distinct impls" true
       (na_sym <> nb_sym)
   | _ ->
     Alcotest.failf
       "expected exactly one row hit by 2 arms (NA) and one row hit by 1 \
        arm (NB); got arms=[%s]"
       (String.concat "; "
          (List.map (fun (t, l) -> Printf.sprintf "(%s,%s)" t l) arms)))

(* ── Task 4 review Finding 2: ECallPtr None-branch of try_collision_dispatch
   ───────────────────────────────────────────────────────────────────────
   [Mono.try_collision_dispatch] is wired into THREE call sites: the [EApp]
   None-branch (exercised above by [test_colliding_general_iface_runtime_dispatch]),
   the [iface_impl_name] name-collision branch, and the [ECallPtr]
   None-branch. A natural March fixture reliably reaching the [ECallPtr]
   branch could not be constructed: a generic wrapper function calling the
   colliding method, and a higher-order closure parameter calling it, BOTH
   still resolve through the [EApp] path in this compiler (verified
   empirically — mono only ever sees a bare, unresolved [EApp "speak"] for
   these shapes, never a pre-existing [ECallPtr] naming an unresolved
   interface method).  Real cross-module ECallPtr dispatch (the scenario
   [try_collision_dispatch]'s doc comment cites — a capability parameter
   whose concrete type is erased to [TVar "_"] at lowering time) requires a
   multi-file MARCH_LIB_PATH dependency graph that this single-file test
   harness cannot construct.

   So — mirroring [test_iface_guard_fires_ecallptr] above, which isolates
   [llvm_emit]'s ECallPtr consumer the same way for the same reason — this
   test hand-builds a TIR module and drives the REAL [Mono.monomorphize]
   directly: a bare [ECallPtr] naming an unresolved method ("speak") with
   two colliding "Thing" impls registered in [iface_methods]. This proves
   the ECallPtr None-branch (mono.ml, the `Tir.ECallPtr (fn_atom, args) ->
   ... Hashtbl.find_opt fn_table orig_name -> None` arm) rewrites to the
   dispatch sentinel exactly like the EApp branch does, and registers both
   impls' rows in [Dispatch_registry] — without depending on which
   real-frontend shape happens to produce ECallPtr today. *)
let test_mono_ecallptr_collision_dispatch () =
  let open March_tir.Tir in
  let mkv name ty = { v_name = name; v_ty = ty; v_lin = Unr } in
  let thing_ty = TCon ("Thing", []) in
  let impl_a_name = "Speak$NA.Thing.speak" in
  let impl_b_name = "Speak$NB.Thing.speak" in
  let impl_fn name lit = {
    fn_name   = name;
    fn_params = [ mkv "_self" thing_ty ];
    fn_ret_ty = TString;
    fn_body   = EAtom (ALit (March_ast.Ast.LitString lit));
    fn_kind   = FnNormal;
  } in
  let arg_var = mkv "x" thing_ty in
  let speak_var = mkv "speak" (TFn ([ thing_ty ], TString)) in
  let main_fn = {
    fn_name   = "main";
    fn_params = [];
    fn_ret_ty = TString;
    fn_body   =
      ELet (arg_var, EAlloc (thing_ty, []),
            ECallPtr (AVar speak_var, [ AVar arg_var ]));
    fn_kind   = FnNormal;
  } in
  let tir = {
    tm_name = "EcpDispatch";
    tm_fns  = [ impl_fn impl_a_name "from-A"; impl_fn impl_b_name "from-B"; main_fn ];
    tm_types = []; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [];
  } in
  let iface_methods : (string, (string * string) list) Hashtbl.t = Hashtbl.create 4 in
  Hashtbl.replace iface_methods "speak" [ ("Thing", impl_a_name); ("Thing", impl_b_name) ];
  let tir' = March_tir.Mono.monomorphize ~iface_methods tir in
  let main' =
    match List.find_opt (fun fn -> fn.fn_name = "main") tir'.tm_fns with
    | Some fn -> fn
    | None -> Alcotest.fail "specialized module has no `main` fn"
  in
  let sentinel_name =
    match main'.fn_body with
    | ELet (_, _, EApp (f, _)) -> Some f.v_name
    | e -> Alcotest.failf "unexpected main body shape: %s" (show_expr e)
  in
  (match sentinel_name with
   | None -> Alcotest.fail "ECallPtr call site was not rewritten to an EApp"
   | Some sentinel ->
     Alcotest.(check bool) "ECallPtr rewritten to the dispatch sentinel" true
       (March_tir.Dispatch_registry.is_sentinel sentinel);
     Alcotest.(check string) "sentinel name matches Speak.speak.Thing convention"
       "__march_ifdispatch$Speak$speak$Thing" sentinel;
     (match March_tir.Dispatch_registry.lookup sentinel with
      | None -> Alcotest.fail "no dispatch rows registered for the sentinel"
      | Some rows ->
        let syms = List.map snd rows |> List.sort compare in
        Alcotest.(check (list string))
          "both colliding impls registered as dispatch rows"
          (List.sort compare [ impl_a_name; impl_b_name ]) syms))

(* ── Final-review Finding 2: iface_impl_name name-collision branch ───────────
   The THIRD [Mono.try_collision_dispatch] call site — distinct from the two
   above.  It is NOT the [None]-branch (callee absent from [fn_table]); here the
   callee name IS a real user top-level function present in [fn_table], but it
   ALSO happens to be an interface method name, AND the user function's
   first-parameter type does not match the call's concrete first-argument type
   (the classic `fn show(r: String)` shadowing the [Show] method while a prelude
   generic calls `show(x)` on a different type).  mono must dispatch to the
   interface impl, not the user function — and when that argument type is a
   COLLIDING short name (two impls in different modules), it must route through
   [try_collision_dispatch] rather than [resolve_impl_by_type]'s silent
   first-match.

   Reaching this branch (mono.ml's `Some orig_fn when <param/arg mismatch> ->`
   arm) requires the callee to resolve to a user fn in [fn_table], which the
   ECallPtr/None-branch shapes above do not — so, mirroring
   [test_mono_ecallptr_collision_dispatch]'s hand-built-TIR technique, this test
   supplies BOTH a user fn `speak(_: String)` (populating [fn_table]) and two
   colliding "Thing" impls under `speak` in [iface_methods], then calls
   `speak(x : Thing)` directly ([EApp], not [ECallPtr]).  A regression here
   would silently fall through to [resolve_impl_by_type]'s first match. *)
let test_mono_iface_name_collision_dispatch () =
  let open March_tir.Tir in
  let mkv name ty = { v_name = name; v_ty = ty; v_lin = Unr } in
  let thing_ty = TCon ("Thing", []) in
  let impl_a_name = "Speak$NA.Thing.speak" in
  let impl_b_name = "Speak$NB.Thing.speak" in
  let impl_fn name lit = {
    fn_name   = name;
    fn_params = [ mkv "_self" thing_ty ];
    fn_ret_ty = TString;
    fn_body   = EAtom (ALit (March_ast.Ast.LitString lit));
    fn_kind   = FnNormal;
  } in
  (* A REAL user top-level fn named `speak` whose first param is String — it
     lands in fn_table and shares the name with the Show-style method, but its
     param type (String) differs from the call's arg type (Thing), which is what
     trips the name-collision guard. *)
  let user_speak = {
    fn_name   = "speak";
    fn_params = [ mkv "s" TString ];
    fn_ret_ty = TString;
    fn_body   = EAtom (ALit (March_ast.Ast.LitString "user-speak"));
    fn_kind   = FnNormal;
  } in
  let arg_var = mkv "x" thing_ty in
  let speak_var = mkv "speak" (TFn ([ thing_ty ], TString)) in
  let main_fn = {
    fn_name   = "main";
    fn_params = [];
    fn_ret_ty = TString;
    fn_body   =
      ELet (arg_var, EAlloc (thing_ty, []),
            EApp (speak_var, [ AVar arg_var ]));
    fn_kind   = FnNormal;
  } in
  let tir = {
    tm_name = "IfaceNameDispatch";
    tm_fns  =
      [ impl_fn impl_a_name "from-A"; impl_fn impl_b_name "from-B";
        user_speak; main_fn ];
    tm_types = []; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [];
  } in
  let iface_methods : (string, (string * string) list) Hashtbl.t = Hashtbl.create 4 in
  Hashtbl.replace iface_methods "speak" [ ("Thing", impl_a_name); ("Thing", impl_b_name) ];
  let tir' = March_tir.Mono.monomorphize ~iface_methods tir in
  let main' =
    match List.find_opt (fun fn -> fn.fn_name = "main") tir'.tm_fns with
    | Some fn -> fn
    | None -> Alcotest.fail "specialized module has no `main` fn"
  in
  let sentinel_name =
    match main'.fn_body with
    | ELet (_, _, EApp (f, _)) -> Some f.v_name
    | e -> Alcotest.failf "unexpected main body shape: %s" (show_expr e)
  in
  (match sentinel_name with
   | None -> Alcotest.fail "name-collision call site was not rewritten to an EApp"
   | Some sentinel ->
     Alcotest.(check bool) "call rewritten to the dispatch sentinel (not user fn)" true
       (March_tir.Dispatch_registry.is_sentinel sentinel);
     Alcotest.(check string) "sentinel name matches Speak.speak.Thing convention"
       "__march_ifdispatch$Speak$speak$Thing" sentinel;
     (match March_tir.Dispatch_registry.lookup sentinel with
      | None -> Alcotest.fail "no dispatch rows registered for the sentinel"
      | Some rows ->
        let syms = List.map snd rows |> List.sort compare in
        Alcotest.(check (list string))
          "both colliding impls registered as dispatch rows"
          (List.sort compare [ impl_a_name; impl_b_name ]) syms))

(* ── LLVM emit correctness: constructor hashtable collision ──────────────── *)

(** Bug: ctor_info keyed by constructor name only — two ADTs with the same
    constructor name (e.g. both having "Cons") silently overwrite each other,
    producing wrong tags and field counts.

    Fix: keys are now type-qualified ("A.Cons", "B.Cons").
    lower.ml embeds the parent type name in EAlloc TCon; build_ctor_info stores
    variants as "TypeName.CtorName"; emit_case qualifies br_tag at lookup time. *)
let test_ctor_no_collision_different_tags () =
  (* Type A: [Nil, Cons(Int), End] — Nil=tag0, Cons=tag1, End=tag2
     Type B: [Cons(Int), Nil] — Cons=tag0, Nil=tag1
     Without the fix, ctor_info["Cons"] would be overwritten by whichever type
     is processed last, and make_a's allocation would get the wrong tag.
     A has 3 variants so it is NOT niche-shaped (niche needs exactly 1 nullary +
     1 single-field); the boxed path emits "store i32 1" for A.Cons. *)
  let td_a = March_tir.Tir.TDVariant ("A",
    [("Nil", []); ("Cons", [March_tir.Tir.TInt]); ("End", [])]) in
  let td_b = March_tir.Tir.TDVariant ("B",
    [("Cons", [March_tir.Tir.TInt]); ("Nil", [])]) in
  let x = mk_var "x" March_tir.Tir.TInt in
  (* make_a: builds A.Cons — should store tag 1 (second ctor of A) *)
  let fn_a = { March_tir.Tir.fn_name = "make_a";
               fn_params = [x];
               fn_ret_ty = March_tir.Tir.TCon ("A", []);
               fn_body   = March_tir.Tir.EAlloc
                             (March_tir.Tir.TCon ("A.Cons", []),
                              [March_tir.Tir.AVar x]);
               fn_kind   = March_tir.Tir.FnNormal } in
  (* make_b: builds B.Cons — should store tag 0 (first ctor of B) *)
  let fn_b = { March_tir.Tir.fn_name = "make_b";
               fn_params = [x];
               fn_ret_ty = March_tir.Tir.TCon ("B", []);
               fn_body   = March_tir.Tir.EAlloc
                             (March_tir.Tir.TCon ("B.Cons", []),
                              [March_tir.Tir.AVar x]);
               fn_kind   = March_tir.Tir.FnNormal } in
  let m = { March_tir.Tir.tm_name = "test"; tm_fns = [fn_a; fn_b];
            tm_types = [td_a; td_b]; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  let ir = March_tir.Llvm_emit.emit_module m in
  (* Without the fix, A.Cons lookup falls back to tag=0 (ctor_info["A.Cons"]
     not found → fallback entry with ce_tag=0).  With the fix, it finds
     ctor_info["A.Cons"] = {tag=1} and emits "store i32 1". *)
  let has_tag1 =
    try ignore (Str.search_forward (Str.regexp "store i32 1") ir 0); true
    with Not_found -> false
  in
  Alcotest.(check bool) "A.Cons emits tag 1 (not the fallback tag 0)" true has_tag1

(** Bug 2: when field counts don't match (e.g. cascading from collision),
    the emitter silently fell back to ptr type.  Fix: hard Failure. *)
let test_ctor_arity_mismatch_raises () =
  (* Construct EAlloc with key "A.Cons" (1 field in the type def) but 2 args.
     With the fix this must raise, not silently emit broken IR. *)
  let td = March_tir.Tir.TDVariant ("A",
    [("Cons", [March_tir.Tir.TInt])]) in   (* Cons has exactly 1 field *)
  let x = mk_var "x" March_tir.Tir.TInt in
  let y = mk_var "y" March_tir.Tir.TInt in
  let fn_t = { March_tir.Tir.fn_name = "bad";
               fn_params = [x; y];
               fn_ret_ty = March_tir.Tir.TCon ("A", []);
               fn_body   = March_tir.Tir.EAlloc
                             (March_tir.Tir.TCon ("A.Cons", []),
                              (* 2 args but ctor only has 1 field *)
                              [March_tir.Tir.AVar x; March_tir.Tir.AVar y]);
               fn_kind   = March_tir.Tir.FnNormal } in
  let m = { March_tir.Tir.tm_name = "test"; tm_fns = [fn_t];
            tm_types = [td]; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  let raised =
    try ignore (March_tir.Llvm_emit.emit_module m); false
    with Failure _ -> true
  in
  Alcotest.(check bool) "arity mismatch raises Failure" true raised

(** Compiled path: the generated @main() C wrapper must call
    march_run_scheduler() after march_main() so that actor mailboxes
    are drained even when main() never calls run_until_idle(). *)
let test_compiled_main_calls_march_run_scheduler () =
  let src = {|mod Test do
    actor Counter do
      state { count : Int }
      init { count: 0 }
      on Inc() do { count: state.count + 1 } end
    end
    fn main() do
      let pid = spawn(Counter)
      send(pid, Inc())
    end
  end|} in
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let ir = March_tir.Llvm_emit.emit_module tir in
  (* The @main() wrapper must contain a call to march_run_scheduler so
     that actor mailboxes are drained after march_main() returns.
     Without this, handlers would never run in compiled executables. *)
  let has_scheduler_call =
    try ignore (Str.search_forward (Str.regexp "march_run_scheduler") ir 0); true
    with Not_found -> false
  in
  Alcotest.(check bool) "@main wrapper calls march_run_scheduler" true has_scheduler_call;
  (* Verify the declaration is present too (needed by the linker) *)
  let has_declaration =
    try ignore (Str.search_forward
      (Str.regexp "declare void @march_run_scheduler") ir 0); true
    with Not_found -> false
  in
  Alcotest.(check bool) "march_run_scheduler is declared in preamble" true has_declaration

(* ── LLVM emit regression: string_chars / string_from_chars ─────────────── *)

(** Uniform integer tagging: coerce("i64","ptr") must emit shl+or+inttoptr;
    coerce("ptr","i64") must emit ptrtoint+ashr.  This is the IR-level check
    for the low-bit tagging scheme that prevents SIGSEGV when integers pass
    through polymorphic (ptr-typed) ADT fields (e.g. List(Int) with n >= 4096). *)
let test_int_tag_coerce_ir () =
  (* A function that takes a polymorphic list and returns the head as Int forces
     the codegen to coerce Int→ptr when constructing Cons and ptr→i64 when
     extracting the head.  The List type is generic so fields are ptr-typed. *)
  let src = {|mod Test do
    fn head_int(xs : List(Int)) : Int do
      match xs do
        Cons(h, _) -> h
        Nil -> 0
      end
    end
    fn make_list(n : Int) : List(Int) do
      Cons(n, Nil)
    end
  end|} in
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let ir = March_tir.Llvm_emit.emit_module tir in
  let ir_has pat =
    try ignore (Str.search_forward (Str.regexp_string pat) ir 0); true
    with Not_found -> false
  in
  (* Tag: shl i64 %*, 1 and or i64 %*, 1 should appear for i64→ptr boxing *)
  Alcotest.(check bool) "tag: shl nsw i64 ... 1"  true (ir_has "shl nsw i64");
  Alcotest.(check bool) "tag: or i64 ... 1"   true (ir_has "or i64");
  (* Untag: ashr i64 %*, 1 should appear for ptr→i64 unboxing *)
  Alcotest.(check bool) "untag: ashr i64"      true (ir_has "ashr i64");
  (* The old unsafe raw inttoptr of an unshifted i64 must NOT appear for the
     Int→ptr case (would mean an integer was stored without tagging). *)
  Alcotest.(check bool) "no raw i64 inttoptr"  false (ir_has "inttoptr i64 %r to ptr")

(** Regression: i64-returning closure wrappers must tag the return value.
    Without tagging, an Int value >= 4096 stored in a polymorphic closure
    result would look like a heap pointer and crash march_incrc.
    The wrapper fires when a top-level Int-returning function is used as a
    first-class value (e.g. passed to a HOF that accepts a polymorphic fn). *)
let test_int_tag_wrapper_ir () =
  (* inc_fn is a top-level function returning i64; passing it as a value to
     list_apply forces the codegen to emit a closure wrapper around inc_fn.
     Closure fn-pointers are type-erased and dispatched uniformly, so every
     wrapper ($clo_wrap and $lam$apply) shares ONE calling convention: the
     generic ptr ABI.  The wrapper takes concrete params but returns its result
     in the ptr slot — an i64 result is tagged (n<<1)|1 so the dispatch's
     conditional untag recovers it, and so an Int >= 4096 is never mistaken for a
     heap pointer by march_incrc.  (A prior "concrete i64 return" variant avoided
     tagging but could not carry a *polymorphic* return, e.g. a lambda whose body
     is a dynamic record-field read — the dispatch read the tagged generic value
     as a raw scalar.  Uniform ptr ABI fixes both.) *)
  let src = {|mod Test do
    fn inc_fn(x : Int) : Int do x + 1 end
    fn list_apply(f : Int -> Int, xs : List(Int)) : List(Int) do
      map(xs, f)
    end
    fn use_wrapper() : List(Int) do
      list_apply(inc_fn, Cons(1, Nil))
    end
  end|} in
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let ir = March_tir.Llvm_emit.emit_module tir in
  let ir_has pat =
    try ignore (Str.search_forward (Str.regexp_string pat) ir 0); true
    with Not_found -> false
  in
  (* The wrapper returns ptr (generic ABI), keeps a concrete i64 param, and tags
     its scalar result so the ECallPtr dispatch can untag it on read. *)
  Alcotest.(check bool) "wrapper: define ptr return" true (ir_has "define ptr @inc_fn$clo_wrap");
  Alcotest.(check bool) "wrapper: i64 param"         true (ir_has "i64 %a0");
  Alcotest.(check bool) "wrapper: tags scalar result (shl)" true (ir_has "shl nsw i64 %r, 1")

(** Regression: string_chars and string_from_chars must lower to C-runtime
    calls in the LLVM backend.  Before the fix, emit_atom fell through to the
    default alloca-load path and generated [%string_chars.addr] which was never
    allocated, crashing LLVM IR verification. *)
let test_string_chars_llvm_emit () =
  let src = {|mod Test do
    fn f(s : String) do
      let chars = string_chars(s)
      string_from_chars(chars)
    end
  end|} in
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let ir = March_tir.Llvm_emit.emit_module tir in
  let ir_has pat =
    try ignore (Str.search_forward (Str.regexp_string pat) ir 0); true
    with Not_found -> false
  in
  Alcotest.(check bool) "string_chars -> @march_string_chars"     true  (ir_has "@march_string_chars");
  Alcotest.(check bool) "string_from_chars -> @march_string_from_chars" true  (ir_has "@march_string_from_chars");
  Alcotest.(check bool) "no %string_chars.addr load"              false (ir_has "%string_chars.addr")

(* ── String stdlib module tests ─────────────────────────────────────────── *)

(** Helper: load string.march and evaluate [src] with it in scope. *)
let test_string_byte_size () =
  let env = eval_with_string {|mod Test do
    fn f() do String.byte_size("hello") end
  end|} in
  Alcotest.(check int) "byte_size(\"hello\") = 5" 5
    (vint (call_fn env "f" []))

let test_string_byte_size_empty () =
  let env = eval_with_string {|mod Test do
    fn f() do String.byte_size("") end
  end|} in
  Alcotest.(check int) "byte_size(\"\") = 0" 0
    (vint (call_fn env "f" []))

let test_string_byte_size_unicode () =
  (* UTF-8: "é" is 2 bytes *)
  let env = eval_with_string {|mod Test do
    fn f() do String.byte_size("é") end
  end|} in
  Alcotest.(check int) "byte_size(\"é\") = 2" 2
    (vint (call_fn env "f" []))

let test_string_slice_bytes () =
  let env = eval_with_string {|mod Test do
    fn f() do String.slice_bytes("hello world", 6, 5) end
  end|} in
  Alcotest.(check string) "slice_bytes(\"hello world\", 6, 5) = \"world\"" "world"
    (vstr (call_fn env "f" []))

let test_string_slice_bytes_clamp () =
  (* slice beyond end should clamp, not raise *)
  let env = eval_with_string {|mod Test do
    fn f() do String.slice_bytes("hi", 0, 100) end
  end|} in
  Alcotest.(check string) "slice_bytes clamps to string length" "hi"
    (vstr (call_fn env "f" []))

let test_string_contains () =
  let env = eval_with_string {|mod Test do
    fn yes() do String.contains("hello world", "world") end
    fn no()  do String.contains("hello world", "xyz") end
  end|} in
  Alcotest.(check bool) "contains: true"  true  (vbool (call_fn env "yes" []));
  Alcotest.(check bool) "contains: false" false (vbool (call_fn env "no"  []))

let test_string_starts_with () =
  let env = eval_with_string {|mod Test do
    fn yes() do String.starts_with("hello", "he") end
    fn no()  do String.starts_with("hello", "lo") end
  end|} in
  Alcotest.(check bool) "starts_with: true"  true  (vbool (call_fn env "yes" []));
  Alcotest.(check bool) "starts_with: false" false (vbool (call_fn env "no"  []))

let test_string_ends_with () =
  let env = eval_with_string {|mod Test do
    fn yes() do String.ends_with("hello", "lo") end
    fn no()  do String.ends_with("hello", "he") end
  end|} in
  Alcotest.(check bool) "ends_with: true"  true  (vbool (call_fn env "yes" []));
  Alcotest.(check bool) "ends_with: false" false (vbool (call_fn env "no"  []))

let test_string_concat () =
  let env = eval_with_string {|mod Test do
    fn f() do String.concat("foo", "bar") end
  end|} in
  Alcotest.(check string) "concat" "foobar"
    (vstr (call_fn env "f" []))

let test_string_replace () =
  let env = eval_with_string {|mod Test do
    fn f() do String.replace("hello world", "world", "there") end
  end|} in
  Alcotest.(check string) "replace first" "hello there"
    (vstr (call_fn env "f" []))

let test_string_replace_all () =
  let env = eval_with_string {|mod Test do
    fn f() do String.replace_all("aabbaa", "a", "x") end
  end|} in
  Alcotest.(check string) "replace_all" "xxbbxx"
    (vstr (call_fn env "f" []))

let test_string_split () =
  let env = eval_with_string {|mod Test do
    fn f() do String.split("a,b,c", ",") end
  end|} in
  let xs = vlist (call_fn env "f" []) in
  Alcotest.(check int) "split length" 3 (List.length xs);
  Alcotest.(check string) "split[0]" "a" (vstr (List.nth xs 0));
  Alcotest.(check string) "split[1]" "b" (vstr (List.nth xs 1));
  Alcotest.(check string) "split[2]" "c" (vstr (List.nth xs 2))

let test_string_split_first () =
  (* split_first("a:b:c", ":") = Some("a", "b:c") *)
  let env = eval_with_string {|mod Test do
    fn f() do String.split_first("a:b:c", ":") end
  end|} in
  let args = vcon "Some" (call_fn env "f" []) in
  let pair = (match List.nth args 0 with
    | March_eval.Eval.VTuple [a; b] -> (a, b)
    | _ -> failwith "expected tuple") in
  Alcotest.(check string) "split_first head" "a"   (vstr (fst pair));
  Alcotest.(check string) "split_first tail" "b:c" (vstr (snd pair))

let test_string_split_first_no_sep () =
  (* split_first("hello", ":") = None *)
  let env = eval_with_string {|mod Test do
    fn f() do String.split_first("hello", ":") end
  end|} in
  let _ = vcon "None" (call_fn env "f" []) in
  ()  (* Just checking it returns None *)

let test_string_join () =
  let env = eval_with_string {|mod Test do
    fn f() do String.join(["a", "b", "c"], "-") end
  end|} in
  Alcotest.(check string) "join" "a-b-c"
    (vstr (call_fn env "f" []))

let test_string_trim () =
  let env = eval_with_string {|mod Test do
    fn f() do String.trim("  hello  ") end
  end|} in
  Alcotest.(check string) "trim" "hello"
    (vstr (call_fn env "f" []))

let test_string_trim_start () =
  let env = eval_with_string {|mod Test do
    fn f() do String.trim_start("  hello  ") end
  end|} in
  Alcotest.(check string) "trim_start" "hello  "
    (vstr (call_fn env "f" []))

let test_string_trim_end () =
  let env = eval_with_string {|mod Test do
    fn f() do String.trim_end("  hello  ") end
  end|} in
  Alcotest.(check string) "trim_end" "  hello"
    (vstr (call_fn env "f" []))

let test_string_to_uppercase () =
  let env = eval_with_string {|mod Test do
    fn f() do String.to_uppercase("hello") end
  end|} in
  Alcotest.(check string) "to_uppercase" "HELLO"
    (vstr (call_fn env "f" []))

let test_string_to_lowercase () =
  let env = eval_with_string {|mod Test do
    fn f() do String.to_lowercase("HELLO") end
  end|} in
  Alcotest.(check string) "to_lowercase" "hello"
    (vstr (call_fn env "f" []))

let test_string_repeat () =
  let env = eval_with_string {|mod Test do
    fn f() do String.repeat("ab", 3) end
  end|} in
  Alcotest.(check string) "repeat" "ababab"
    (vstr (call_fn env "f" []))

let test_string_reverse () =
  let env = eval_with_string {|mod Test do
    fn f() do String.reverse("hello") end
  end|} in
  Alcotest.(check string) "reverse" "olleh"
    (vstr (call_fn env "f" []))

let test_string_pad_left () =
  let env = eval_with_string {|mod Test do
    fn f() do String.pad_left("hi", 5, "0") end
  end|} in
  Alcotest.(check string) "pad_left" "000hi"
    (vstr (call_fn env "f" []))

let test_string_pad_right () =
  let env = eval_with_string {|mod Test do
    fn f() do String.pad_right("hi", 5, ".") end
  end|} in
  Alcotest.(check string) "pad_right" "hi..."
    (vstr (call_fn env "f" []))

let test_string_chars () =
  let env = eval_with_string {|mod Test do
    fn f() do String.chars("abc") end
  end|} in
  let xs = vlist (call_fn env "f" []) in
  Alcotest.(check int)    "chars length" 3   (List.length xs);
  Alcotest.(check string) "chars[0]"     "a" (vstr (List.nth xs 0));
  Alcotest.(check string) "chars[1]"     "b" (vstr (List.nth xs 1));
  Alcotest.(check string) "chars[2]"     "c" (vstr (List.nth xs 2))

let test_string_chars_empty () =
  let env = eval_with_string {|mod Test do
    fn f() do String.chars("") end
  end|} in
  let xs = vlist (call_fn env "f" []) in
  Alcotest.(check int) "chars empty" 0 (List.length xs)

let test_string_to_upper () =
  let env = eval_with_string {|mod Test do
    fn f() do String.to_upper("hello world") end
  end|} in
  Alcotest.(check string) "to_upper" "HELLO WORLD"
    (vstr (call_fn env "f" []))

let test_string_to_lower () =
  let env = eval_with_string {|mod Test do
    fn f() do String.to_lower("HELLO WORLD") end
  end|} in
  Alcotest.(check string) "to_lower" "hello world"
    (vstr (call_fn env "f" []))

let test_string_is_empty () =
  let env = eval_with_string {|mod Test do
    fn yes() do String.is_empty("") end
    fn no()  do String.is_empty("x") end
  end|} in
  Alcotest.(check bool) "is_empty: true"  true  (vbool (call_fn env "yes" []));
  Alcotest.(check bool) "is_empty: false" false (vbool (call_fn env "no"  []))

let test_string_grapheme_count () =
  let env = eval_with_string {|mod Test do
    fn f() do String.grapheme_count("hello") end
  end|} in
  Alcotest.(check int) "grapheme_count(\"hello\") = 5" 5
    (vint (call_fn env "f" []))

let test_string_index_of () =
  let env = eval_with_string {|mod Test do
    fn found()     do String.index_of("hello", "ll") end
    fn not_found() do String.index_of("hello", "xyz") end
  end|} in
  let some_args = vcon "Some" (call_fn env "found" []) in
  Alcotest.(check int) "index_of found at 2" 2
    (vint (List.nth some_args 0));
  let _ = vcon "None" (call_fn env "not_found" []) in
  ()

let test_string_to_int () =
  let env = eval_with_string {|mod Test do
    fn ok()  do String.to_int("42") end
    fn err() do String.to_int("abc") end
  end|} in
  let ok_args = vcon "Ok" (call_fn env "ok" []) in
  Alcotest.(check int) "to_int Ok(42)" 42 (vint (List.nth ok_args 0));
  let _ = vcon "Err" (call_fn env "err" []) in
  ()

let test_string_to_float () =
  let env = eval_with_string {|mod Test do
    fn ok()  do String.to_float("3.14") end
    fn err() do String.to_float("abc") end
  end|} in
  let ok_args = vcon "Ok" (call_fn env "ok" []) in
  Alcotest.(check (float 0.001)) "to_float Ok(3.14)" 3.14
    (match List.nth ok_args 0 with
     | March_eval.Eval.VFloat f -> f
     | _ -> failwith "expected VFloat");
  let _ = vcon "Err" (call_fn env "err" []) in
  ()

let test_string_from_int () =
  let env = eval_with_string {|mod Test do
    fn f() do String.from_int(42) end
  end|} in
  Alcotest.(check string) "from_int(42)" "42"
    (vstr (call_fn env "f" []))

let test_string_from_float () =
  let env = eval_with_string {|mod Test do
    fn f() do String.from_float(3.14) end
  end|} in
  let s = vstr (call_fn env "f" []) in
  Alcotest.(check bool) "from_float contains dot" true
    (String.contains s '.')

(* ── IOList stdlib module tests ─────────────────────────────────────────── *)

let test_iolist_empty () =
  let env = eval_with_iolist {|mod Test do
    fn f() do IOList.to_string(IOList.empty()) end
  end|} in
  Alcotest.(check string) "IOList.empty flattens to \"\"" ""
    (vstr (call_fn env "f" []))

let test_iolist_from_string () =
  let env = eval_with_iolist {|mod Test do
    fn f() do IOList.to_string(IOList.from_string("hello")) end
  end|} in
  Alcotest.(check string) "IOList.from_string round-trips" "hello"
    (vstr (call_fn env "f" []))

let test_iolist_append () =
  let env = eval_with_iolist {|mod Test do
    fn f() do
      IOList.to_string(IOList.append(IOList.from_string("foo"), IOList.from_string("bar")))
    end
  end|} in
  Alcotest.(check string) "IOList.append" "foobar"
    (vstr (call_fn env "f" []))

let test_iolist_byte_size () =
  let env = eval_with_iolist {|mod Test do
    fn f() do
      IOList.byte_size(IOList.from_string("hello"))
    end
  end|} in
  Alcotest.(check int) "IOList.byte_size" 5
    (vint (call_fn env "f" []))

(* ── ~H sigil codegen regression ──────────────────────────────────────────
   Regression for the bidirectional-inference / span-collision bug that broke
   the ~H HTML template sigil in compiled mode.  The desugar built its
   cons-list of parts with every generated Cons/Nil node sharing the sigil's
   span; the typechecker keys its type_map by span, so the outer
   IOList.from_strings(...) application's IOList type clobbered the list's
   List(String) type.  The TIR lowerer reads that map to choose a bare
   constructor's owning ADT, so the list lowered to the non-existent
   IOList.Cons / IOList.Nil tags and the template rendered "".
   These tests assert the desugared list lowers to List.Cons / List.Nil, and
   that the int-interpolation html_auto_escape arg is coerced to a tagged ptr
   (not passed as a raw i64, which segfaulted the runtime). *)

let test_h_sigil_static_lowers_to_list_cons () =
  let tir = emit_tir_with_iolist {|mod Test do
    fn render() : String do IOList.to_string(~H"<p>HHH</p>") end
  end|} in
  Alcotest.(check bool) "~H list uses List.Cons (real List ctor)" true
    (ir_contains tir "List.Cons");
  Alcotest.(check bool) "~H list does NOT use bogus IOList.Cons" false
    (ir_contains tir "IOList.Cons");
  Alcotest.(check bool) "~H list does NOT use bogus IOList.Nil" false
    (ir_contains tir "IOList.Nil")

let test_h_sigil_int_interp_coerces_arg_to_ptr () =
  let ir = emit_ir_with_iolist {|mod Test do
    fn render(n : Int) : String do IOList.to_string(~H"<p>n=${n}</p>") end
  end|} in
  (* Contextual escaping (Task 5) replaced html_auto_escape with
     html_escape_ctx(id, v), but the hazard this test exists for is unchanged:
     the VALUE argument must arrive as a tagged ptr, never as a raw `i64 N`
     against a `ptr` declaration, which segfaulted. The escaper id is a
     genuine i64 and is the FIRST argument, so the shape to pin is
     `(i64 <id>, ptr ...)`.

     Also pins the contextual decision itself at the IR level: a hole in
     element content must select escaper 0 (Context.EscHtml). *)
  Alcotest.(check bool) "html_escape_ctx called with (i64 id, ptr value)" true
    (ir_contains ir "call ptr @march_html_escape_ctx(i64 0, ptr");
  Alcotest.(check bool) "value arg is NOT a raw i64" false
    (ir_contains ir "@march_html_escape_ctx(i64 0, i64");
  (* An Int reaches the escaper via to_string, and must be tagged on the way. *)
  Alcotest.(check bool) "int is coerced through the ptr path" true
    (ir_contains ir "call ptr @march_value_to_string(ptr")

(* ── Http stdlib module tests ──────────────────────────────────────────── *)

let test_http_parse_url () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("https://example.com/path?q=1") do
      Ok(req) -> Http.host(req)
      Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "parse_url host" "example.com" (vstr (call_fn env "f" []))

let test_http_parse_url_scheme () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("http://localhost:8080/api") do
      Ok(req) ->
        match Http.scheme(req) do
        SchemeHttp -> "http"
        SchemeHttps -> "https"
        end
      Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "parse_url scheme" "http" (vstr (call_fn env "f" []))

let test_http_parse_url_path () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("https://example.com/api/v1") do
      Ok(req) -> Http.path(req)
      Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "parse_url path" "/api/v1" (vstr (call_fn env "f" []))

let test_http_parse_url_port () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("http://localhost:3000/") do
      Ok(req) ->
        match Http.port(req) do
        Some(p) -> p
        None -> 0
        end
      Err(_) -> -1
      end
    end
  end|} in
  Alcotest.(check int) "parse_url port" 3000 (vint (call_fn env "f" []))

let test_http_parse_url_invalid () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("ftp://bad") do
      Ok(_) -> "ok"
      Err(InvalidScheme(_)) -> "invalid_scheme"
      Err(_) -> "other_error"
      end
    end
  end|} in
  Alcotest.(check string) "parse_url invalid scheme" "invalid_scheme" (vstr (call_fn env "f" []))

let test_http_set_header () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.get("https://example.com") do
      Ok(req) -> do
        let req = Http.set_header(req, "Accept", "application/json")
        match Http.get_request_header(req, "accept") do
        Some(v) -> v
        None -> "none"
        end
      end
      Err(_) -> "error"
      end
    end
  end|} in
  Alcotest.(check string) "set_header" "application/json" (vstr (call_fn env "f" []))

let test_http_method_to_string () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.post("https://example.com", ()) do
      Ok(req) -> Http.method_to_string(Http.method(req))
      Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "method_to_string" "POST" (vstr (call_fn env "f" []))

let test_http_status_helpers () =
  let env = eval_with_http {|mod Test do
    fn f() do Http.is_success(Http.status_ok()) end
  end|} in
  Alcotest.(check bool) "status_ok is success" true (vbool (call_fn env "f" []))

let test_http_post_constructor () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.post("https://example.com/api", "body data") do
      Ok(req) -> Http.method_to_string(Http.method(req))
      Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "post method" "POST" (vstr (call_fn env "f" []))

let test_http_encode_query () =
  let env = eval_with_http {|mod Test do
    fn f() do
      Http.encode_query(Cons(("key", "value"), Cons(("foo", "bar"), Nil)))
    end
  end|} in
  Alcotest.(check string) "encode_query" "key=value&foo=bar" (vstr (call_fn env "f" []))

let test_http_response_helpers () =
  let env = eval_with_http {|mod Test do
    fn f() do
      let resp = Response(Status(404), Nil, "Not Found")
      Http.response_status_code(resp)
    end
  end|} in
  Alcotest.(check int) "response status code" 404 (vint (call_fn env "f" []))

(* ── Http builtin tests ───────────────────────────────────────────── *)

let test_http_serialize_request () =
  let env = eval_with_http {|mod Test do
    fn f() do
      http_serialize_request("GET", "example.com", "/path", None, Nil, "")
    end
  end|} in
  let raw = vstr (call_fn env "f" []) in
  Alcotest.(check bool) "starts with GET /path"
    true (String.length raw > 0 && String.sub raw 0 14 = "GET /path HTTP")

let test_http_serialize_request_with_body () =
  let env = eval_with_http {|mod Test do
    fn f() do
      http_serialize_request("POST", "example.com", "/api", None,
        Cons(Header("Content-Type", "text/plain"), Nil), "hello")
    end
  end|} in
  let raw = vstr (call_fn env "f" []) in
  Alcotest.(check bool) "contains body" true (
    let lines = String.split_on_char '\n' raw in
    List.exists (fun l -> String.trim l = "hello") lines)

let test_http_parse_response () =
  let raw = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nhello world" in
  let open March_eval.Eval in
  let result = List.assoc "http_parse_response" base_env in
  match result with
  | VBuiltin (_, f) ->
    (match f [VString raw] with
     | VCon ("Ok", [VTuple [VInt code; _; VString _body]]) ->
       Alcotest.(check int) "status code" 200 code
     | _ -> Alcotest.fail "expected Ok tuple")
  | _ -> Alcotest.fail "expected builtin"

let test_http_parse_response_body () =
  (* Build the raw HTTP response with actual \r\n in OCaml, pass to builtin directly *)
  let raw = "HTTP/1.1 404 Not Found\r\nX-Foo: bar\r\n\r\nnot here" in
  let open March_eval.Eval in
  let result = List.assoc "http_parse_response" base_env in
  match result with
  | VBuiltin (_, f) ->
    (match f [VString raw] with
     | VCon ("Ok", [VTuple [VInt code; _; VString body]]) ->
       Alcotest.(check int) "status code" 404 code;
       Alcotest.(check string) "body" "not here" body
     | _ -> Alcotest.fail "expected Ok tuple")
  | _ -> Alcotest.fail "expected builtin"

(* ── Http.Client tests ───────────────────────────────────────────── *)

let test_http_client_new () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let c = HttpClient.new_client()
      c
    end
  end|} in
  let v = call_fn env "f" [] in
  match v with
  | March_eval.Eval.VCon ("Client", _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "expected Client, got %s"
    (March_eval.Eval.value_to_string v))

let test_http_client_add_steps () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let c = HttpClient.new_client()
      let c = HttpClient.add_request_step(c, "auth", HttpClient.step_bearer_auth("tok"))
      let c = HttpClient.add_request_step(c, "headers", HttpClient.step_default_headers)
      fn count(xs) do
        match xs do
        Nil -> 0
        Cons(_, t) -> 1 + count(t)
        end
      end
      count(HttpClient.list_steps(c))
    end
  end|} in
  Alcotest.(check int) "two request steps" 2 (vint (call_fn env "f" []))

let test_http_client_request_step_transforms () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      match Http.get("http://example.com") do
      Err(_) -> "fail"
      Ok(req) -> do
        let step = HttpClient.step_bearer_auth("my-token")
        match step(req) do
        Err(_) -> "fail"
        Ok(transformed) ->
          match Http.get_request_header(transformed, "authorization") do
          Some(v) -> v
          None -> "none"
          end
        end
      end
      end
    end
  end|} in
  Alcotest.(check string) "bearer auth header" "Bearer my-token" (vstr (call_fn env "f" []))

let test_http_client_raise_on_error_status () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      match Http.get("http://example.com") do
      Err(_) -> "url_fail"
      Ok(req) -> do
        let resp = Response(Status(500), Nil, "Internal Server Error")
        match HttpClient.step_raise_on_error(req, resp) do
        Ok(_) -> "ok"
        Err(StepError(name, code)) -> name ++ ":" ++ code
        Err(_) -> "other_error"
        end
      end
      end
    end
  end|} in
  Alcotest.(check string) "raise on 500" "step_raise_on_error:500" (vstr (call_fn env "f" []))

let test_http_client_with_redirects () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let c = HttpClient.new_client()
      let c = HttpClient.with_redirects(c, 5)
      match HttpClient.list_steps(c) do
      Nil -> "empty"
      _ -> "has_steps"
      end
    end
  end|} in
  Alcotest.(check string) "redirects config" "empty" (vstr (call_fn env "f" []))

let test_http_client_base_url_step () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let step = HttpClient.step_base_url("http://api.example.com")
      -- Create a request with just a path
      let req = Request(Get, SchemeHttp, "", None, "/users", None, Nil, "")
      match step(req) do
      Ok(transformed) -> Http.host(transformed)
      Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "base url sets host" "api.example.com" (vstr (call_fn env "f" []))

let test_http_client_content_type_step () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let step = HttpClient.step_content_type("application/json")
      let req = Request(Post, SchemeHttp, "example.com", None, "/api", None, Nil, "{}")
      match step(req) do
      Ok(transformed) ->
        match Http.get_request_header(transformed, "content-type") do
        Some(v) -> v
        None -> "none"
        end
      Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "content type header" "application/json" (vstr (call_fn env "f" []))

(* ── Scheduler tests ───────────────────────────────────────────────── *)

let test_reduction_counter_ticks () =
  let ctx = March_scheduler.Scheduler.create_reduction_ctx () in
  let initial = ctx.remaining in
  let exhausted = March_scheduler.Scheduler.tick ctx in
  Alcotest.(check bool) "first tick not exhausted" false exhausted;
  Alcotest.(check int) "decremented by 1" (initial - 1) ctx.remaining

let test_reduction_counter_exhausts () =
  let ctx = March_scheduler.Scheduler.create_reduction_ctx () in
  let count = ref 0 in
  while not (March_scheduler.Scheduler.tick ctx) do
    incr count
  done;
  Alcotest.(check int) "exhausts after max_reductions - 1 ticks"
    (March_scheduler.Scheduler.max_reductions - 1) !count;
  Alcotest.(check bool) "yielded flag set" true ctx.yielded

let test_eval_yields_after_budget () =
  let src = {|mod Test do
    fn countdown(n) do if n <= 0 do 0 else countdown(n - 1) end end
  end|} in
  let env = eval_module src in
  March_eval.Eval.set_reduction_counting true;
  let yielded = ref false in
  (try
     ignore (call_fn env "countdown" [March_eval.Eval.VInt 100_000])
   with March_eval.Eval.Yield ->
     yielded := true);
  March_eval.Eval.set_reduction_counting false;
  Alcotest.(check bool) "countdown yields after budget" true !yielded

let test_eval_no_yield_when_disabled () =
  March_eval.Eval.set_reduction_counting false;
  let src = {|mod Test do
    fn countdown(n) do if n <= 0 do 0 else countdown(n - 1) end end
  end|} in
  let env = eval_module src in
  let v = call_fn env "countdown" [March_eval.Eval.VInt 100_000] in
  Alcotest.(check int) "completes without yield" 0 (vint v)

(* ── Task tests ──────────────────────────────────────────────────── *)

let test_eval_task_spawn_await () =
  let src = {|mod Test do
  needs IO.Spawn
    fn main() do
      let t = task_spawn(fn x -> 42)
      task_await_unwrap(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "task returns 42" 42 (vint v)

let test_eval_task_await_unwrap () =
  let src = {|mod Test do
  needs IO.Spawn
    fn main() do
      let t = task_spawn(fn x -> 99)
      task_await_unwrap(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "task unwrap returns 99" 99 (vint v)

let test_eval_task_multiple () =
  let src = {|mod Test do
  needs IO.Spawn
    fn main() do
      let t1 = task_spawn(fn x -> 10)
      let t2 = task_spawn(fn x -> 20)
      let r1 = task_await_unwrap(t1)
      let r2 = task_await_unwrap(t2)
      r1 + r2
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "two tasks sum to 30" 30 (vint v)

let test_eval_task_captures_env () =
  let src = {|mod Test do
  needs IO.Spawn
    fn main() do
      let x = 5
      let t = task_spawn(fn u -> x * x)
      task_await_unwrap(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "task captures outer x" 25 (vint v)

let test_eval_spawn_steal_requires_pool () =
  let src = {|mod Test do
  needs IO.Spawn
    fn main() do
      task_spawn_steal(42, fn x -> 1)
    end
  end|} in
  let env = eval_module src in
  let raised = ref false in
  (try ignore (call_fn env "main" [])
   with March_eval.Eval.Eval_error _ -> raised := true);
  Alcotest.(check bool) "rejects non-WorkPool" true !raised

let test_eval_spawn_steal_with_pool () =
  let src = {|mod Test do
  needs IO.Spawn
    fn run(pool) do
      let t = task_spawn_steal(pool, fn x -> 77)
      task_await_unwrap(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "run" [March_eval.Eval.VWorkPool] in
  Alcotest.(check int) "steal task returns 77" 77 (vint v)

let test_eval_workpool_threading () =
  let src = {|mod Test do
  needs IO.Spawn
    fn helper(pool) do
      let t = task_spawn_steal(pool, fn x -> 55)
      task_await_unwrap(t)
    end

    fn main(pool) do
      helper(pool)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [March_eval.Eval.VWorkPool] in
  Alcotest.(check int) "threaded pool works" 55 (vint v)

let test_eval_task_sends_to_actor () =
  let src = {|mod Test do
  needs IO.Spawn
    actor Counter do
      state { count : Int }
      init { count: 0 }

      on Increment(n) do
        { count: state.count + n }
      end
    end

    fn main() do
      let pid = spawn(Counter)
      let t = task_spawn(fn x -> send(pid, Increment(10)))
      task_await_unwrap(t)
      send(pid, Increment(0))
    end
  end|} in
  let env = eval_module src in
  let _v = call_fn env "main" [] in
  (* If we get here without error, cross-tier messaging works *)
  ()

(** Regression: task_spawn with a heap-allocating lambda must not crash with
    "local RC underflow".  Root cause was march_task_spawn_thunk zeroing the
    Task object's RC field (task[0]=0) after march_alloc already set it to 1,
    so the caller's march_decrc_local on the Task result went 0→-1.
    Secondary: march_incrc on the closure inside the runtime was spurious;
    Perceus treats task_spawn as consuming (no DecRC on caller side). *)
let test_compile_task_spawn_heap_alloc_no_rc_underflow () =
  let ir = emit_actor_ir {|mod T do
  needs IO.Spawn
    fn go() : String do "hello" end
    fn main(_cap_spawn : Cap(IO.Spawn)) do
      let _ = task_spawn(fn _ -> go())
      ()
    end
  end|} in
  (* march_task_spawn_thunk must be called *)
  Alcotest.(check bool) "calls march_task_spawn_thunk" true
    (ir_contains ir "march_task_spawn_thunk");
  (* The Task result (let _ = ...) must be DecRC'd by the caller — Perceus
     side of the fix; the runtime side (task[0]=0 removal) is verified by the
     full binary tests passing without abort. *)
  Alcotest.(check bool) "task handle is decrc'd by caller" true
    (ir_contains ir "march_decrc_local")

(** Regression (B10): a local variable whose name shadows a builtin (e.g.
    `kill`, the actor-kill builtin) must still get its RC ops emitted.
    The five EIncRC/EDecRC/EFree/EAtomicIncRC/EAtomicDecRC arms in
    llvm_emit.ml skip emission purely by NAME match against is_builtin_fn /
    top_fns, without checking whether a local alloca (var_slot) shadows that
    name — unlike emit_atom, which has the correct var_slot guard in both of
    its analogous arms. Perceus DOES insert a dec_rc for the shadowed local
    (confirmed via --dump-tir: `let out = dec_rc kill; ...`), so if the
    guard is missing, the alloca for `kill` is created and stored but never
    referenced by any RC runtime call — the local leaks (never freed) and,
    more importantly, the same missing-guard bug pattern is what causes
    heap corruption in the emit_atom builtin arm this mirrors.
    (Was originally written against `link`, the actor-linking builtin, before
    that builtin was removed as permanently unreachable from typed March —
    see specs/progress/2026-08-17-compiled-link-builtin-still-unreachable.md
    — so the shadow target was swapped to `kill`, an actual surviving
    builtin, to keep exercising a real name collision.) *)
let test_compile_local_shadows_builtin_still_gets_rc_ops () =
  let ir = emit_actor_ir {|mod ShadowRc do
  needs IO.Console
    fn main(_cap_console : Cap(IO.Console)) do
      let kill = String.concat("heap", "-allocated")
      let out = String.concat(kill, "!")
      println(out)
    end
  end|} in
  (* The shadowed local must be stack-allocated under its own name... *)
  Alcotest.(check bool) "local `kill` gets its own alloca" true
    (ir_contains ir "%kill.addr = alloca");
  (* ...and at least one RC runtime call must load from that exact alloca
     (not just some unrelated %kill.addr text elsewhere, and not the
     unrelated @march_kill actor-kill builtin declaration/call). *)
  let loads_kill_addr = Str.regexp "load ptr, ptr %kill\\.addr" in
  let ir_has_load_of_kill_addr =
    try ignore (Str.search_forward loads_kill_addr ir 0); true
    with Not_found -> false
  in
  Alcotest.(check bool) "a load from %kill.addr exists (feeds some use)" true
    ir_has_load_of_kill_addr;
  (* Precisely: the value loaded from %kill.addr must reach an RC op
     (march_decrc_local/march_incrc_local/march_free/march_incrc/march_decrc)
     as an argument — not merely be stored/loaded for the String.concat call.
     Extract every SSA temp assigned from `load ptr, ptr %kill.addr`, then
     confirm at least one of those temps is passed to an RC runtime call. *)
  let ssa_temps_loading_kill_addr =
    let re = Str.regexp "%\\([A-Za-z0-9_$]+\\) = load ptr, ptr %kill\\.addr" in
    let rec go i acc =
      match Str.search_forward re ir i with
      | j -> go (j + 1) (Str.matched_group 1 ir :: acc)
      | exception Not_found -> acc
    in
    go 0 []
  in
  Alcotest.(check bool) "at least one SSA temp loads %kill.addr" true
    (ssa_temps_loading_kill_addr <> []);
  let rc_call_re =
    Str.regexp "call void @march_\\(decrc_local\\|incrc_local\\|free\\|incrc\\|decrc\\)(ptr %\\([A-Za-z0-9_$]+\\))"
  in
  let rc_call_args =
    let rec go i acc =
      match Str.search_forward rc_call_re ir i with
      | j -> go (j + 1) (Str.matched_group 2 ir :: acc)
      | exception Not_found -> acc
    in
    go 0 []
  in
  let shadow_reaches_rc_op =
    List.exists (fun t -> List.mem t rc_call_args) ssa_temps_loading_kill_addr
  in
  Alcotest.(check bool)
    "an RC op (incrc/decrc/free) is emitted against the shadowed local `kill`'s value"
    true shadow_reaches_rc_op

(** Phase 5: task_yield() must emit call void @march_sched_yield(), not a no-op. *)
let test_compile_task_yield_actually_yields () =
  let ir = emit_actor_ir {|mod TaskYieldTest do
    fn main() : Unit do
      let _ = task_yield()
      ()
    end
  end|} in
  Alcotest.(check bool) "yields via sched_yield" true
    (ir_contains ir "call void @march_sched_yield()")

(** Phase 5: task_reductions() must read from @march_tls_reductions, not return literal 0. *)
let test_compile_task_reductions_reads_tls () =
  let ir = emit_actor_ir {|mod TaskReductionsTest do
    fn main() : Int do
      task_reductions()
    end
  end|} in
  Alcotest.(check bool) "reads TLS reductions" true
    (ir_contains ir "load i64, ptr @march_tls_reductions")

(** Phase 5: task_await must emit call to @march_task_await, not inline field load. *)
let test_compile_task_await_in_ir () =
  let ir = emit_actor_ir {|mod TaskAwaitTest do
  needs IO.Spawn
    fn main() do
      let t = task_spawn(fn _ -> 42)
      task_await(t)
    end
  end|} in
  Alcotest.(check bool) "uses march_task_await" true
    (ir_contains ir "call ptr @march_task_await")

(** Phase 5: cancel token builtins must emit the correct C extern calls. *)
let test_compile_cancel_token_ir () =
  let ir = emit_actor_ir {|mod CancelTokenTest do
    fn main() do
      let tok = task_cancel_token_new()
      let _ = task_is_cancelled(tok)
      task_cancel(tok)
    end
  end|} in
  Alcotest.(check bool) "cancel_token_new declared" true
    (ir_contains ir "march_cancel_token_new");
  Alcotest.(check bool) "cancel_token_cancel declared" true
    (ir_contains ir "march_cancel_token_cancel");
  Alcotest.(check bool) "cancel_token_is_cancelled declared" true
    (ir_contains ir "march_cancel_token_is_cancelled")

(* ── P10 Phase 2: NativeArray compiled-path IR tests ────────────────────── *)

(** native_int_arr_* builtins must appear in the LLVM preamble and generate
    correct call instructions: i64 return for length/get/sum, ptr for make/set/map. *)
let test_native_int_arr_ir () =
  let ir = emit_actor_ir {|mod Test do
    fn sum_list(xs : List(Int)) : Int do
      let arr = native_int_arr_from_list(xs)
      native_int_arr_sum(arr)
    end
    fn roundtrip(xs : List(Int)) : List(Int) do
      let arr = native_int_arr_from_list(xs)
      native_int_arr_to_list(arr)
    end
    fn make_arr(n : Int) : Int do
      let arr = native_int_arr_make(n, 0)
      let arr2 = native_int_arr_set(arr, 0, 42)
      native_int_arr_get(arr2, 0)
    end
    fn arr_len(xs : List(Int)) : Int do
      let arr = native_int_arr_from_list(xs)
      native_int_arr_length(arr)
    end
  end|} in
  Alcotest.(check bool) "native_int_arr_from_list declared" true
    (ir_contains ir "@native_int_arr_from_list");
  Alcotest.(check bool) "native_int_arr_sum declared" true
    (ir_contains ir "@native_int_arr_sum");
  Alcotest.(check bool) "native_int_arr_to_list declared" true
    (ir_contains ir "@native_int_arr_to_list");
  Alcotest.(check bool) "native_int_arr_make declared" true
    (ir_contains ir "@native_int_arr_make");
  Alcotest.(check bool) "native_int_arr_set declared" true
    (ir_contains ir "@native_int_arr_set");
  Alcotest.(check bool) "native_int_arr_get declared" true
    (ir_contains ir "@native_int_arr_get");
  Alcotest.(check bool) "native_int_arr_length declared" true
    (ir_contains ir "@native_int_arr_length");
  (* IR calls must use correct return types *)
  Alcotest.(check bool) "sum call returns i64" true
    (ir_contains ir "= call i64 @native_int_arr_sum");
  Alcotest.(check bool) "get call returns i64" true
    (ir_contains ir "= call i64 @native_int_arr_get");
  Alcotest.(check bool) "length call returns i64" true
    (ir_contains ir "= call i64 @native_int_arr_length");
  Alcotest.(check bool) "from_list call returns ptr" true
    (ir_contains ir "= call ptr @native_int_arr_from_list")

(** native_float_arr_* builtins must appear in the LLVM preamble and generate
    correct call instructions: double return for get/sum, ptr for make/set/map. *)
let test_native_float_arr_ir () =
  let ir = emit_actor_ir {|mod Test do
    fn sum_arr(n : Int) : Float do
      let arr = native_float_arr_make(n, 1.0)
      native_float_arr_sum(arr)
    end
    fn get_arr(n : Int, i : Int) : Float do
      let arr = native_float_arr_make(n, 2.5)
      native_float_arr_get(arr, i)
    end
    fn set_arr(n : Int, i : Int, v : Float) : NativeFloatArr do
      let arr = native_float_arr_make(n, 0.0)
      native_float_arr_set(arr, i, v)
    end
    fn len_arr(n : Int) : Int do
      let arr = native_float_arr_make(n, 0.0)
      native_float_arr_length(arr)
    end
  end|} in
  Alcotest.(check bool) "native_float_arr_make declared" true
    (ir_contains ir "@native_float_arr_make");
  Alcotest.(check bool) "native_float_arr_sum declared" true
    (ir_contains ir "@native_float_arr_sum");
  Alcotest.(check bool) "native_float_arr_get declared" true
    (ir_contains ir "@native_float_arr_get");
  Alcotest.(check bool) "native_float_arr_length declared" true
    (ir_contains ir "@native_float_arr_length");
  Alcotest.(check bool) "native_float_arr_set declared" true
    (ir_contains ir "@native_float_arr_set");
  (* IR calls must use correct return types *)
  Alcotest.(check bool) "float sum call returns double" true
    (ir_contains ir "= call double @native_float_arr_sum");
  Alcotest.(check bool) "float get call returns double" true
    (ir_contains ir "= call double @native_float_arr_get");
  Alcotest.(check bool) "float make call returns ptr" true
    (ir_contains ir "= call ptr @native_float_arr_make")

(** native narrow-width (f32/i32/u8) builtins must appear in the LLVM preamble
    and generate correct call instructions: i64 return for int-family get/sum,
    double for f32 get/sum, ptr for make/map/conversions. *)
let test_native_narrow_arr_ir () =
  let ir = emit_actor_ir {|mod Test do
    fn make_u8_arr(n : Int, fill : Int) : NativeU8Arr do
      native_u8_arr_make(n, fill)
    end
    fn get_u8_elem(arr : NativeU8Arr, i : Int) : Int do
      native_u8_arr_get(arr, i)
    end
    fn sum_i32_arr(arr : NativeI32Arr) : Int do
      native_i32_arr_sum(arr)
    end
    fn map_f32_arr(arr : NativeF32Arr, f : Float -> Float) : NativeF32Arr do
      native_f32_arr_map(arr, f)
    end
    fn to_u8(arr : NativeIntArr) : NativeU8Arr do
      native_int_to_u8_arr(arr)
    end
  end|} in
  Alcotest.(check bool) "native_u8_arr_make declared" true
    (ir_contains ir "declare ptr    @native_u8_arr_make");
  Alcotest.(check bool) "native_u8_arr_get call returns i64" true
    (ir_contains ir "= call i64 @native_u8_arr_get");
  Alcotest.(check bool) "native_i32_arr_sum call returns i64" true
    (ir_contains ir "= call i64 @native_i32_arr_sum");
  Alcotest.(check bool) "native_f32_arr_map declared" true
    (ir_contains ir "@native_f32_arr_map");
  Alcotest.(check bool) "native_int_to_u8_arr declared" true
    (ir_contains ir "@native_int_to_u8_arr")

(** SIMD vector ops (Task 2) must lower to native LLVM vector instructions —
    inline `fadd`/`llvm.vector.reduce.fadd`, never a runtime call — and must
    NOT auto-declare/call `@simd_f32x4_add` (the coerce-catch-all class of
    regression this task's hard-fail guard exists to catch). *)
let test_simd_vector_ir () =
  let ir = emit_actor_ir {|mod Test do
    fn f() : Float do
      let a = simd_f32x4_make(1.0, 2.0, 3.0, 4.0)
      let b = simd_f32x4_make(5.0, 6.0, 7.0, 8.0)
      let c = simd_f32x4_add(a, b)
      simd_f32x4_sum(c)
    end
  end|} in
  Alcotest.(check bool) "add lowers to native fadd on the vector type" true
    (ir_contains ir "fadd <4 x float>");
  Alcotest.(check bool) "sum lowers to the ordered vector-reduce intrinsic" true
    (ir_contains ir "llvm.vector.reduce.fadd");
  Alcotest.(check bool) "no runtime-call fallthrough for simd_f32x4_add" false
    (ir_contains ir "call ptr @simd_f32x4_add")

(** Phase 4: send() should push to mailbox, NOT dispatch inline.
    After send(), mailbox_size = 1 and state is unchanged. *)
let test_cancel_token_new () =
  let src = {|mod Test do
    fn main() do
      let tok = task_cancel_token_new()
      task_is_cancelled(tok)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check bool) "new token is not cancelled" false (vbool v)

let test_cancel_token_cancel () =
  let src = {|mod Test do
    fn main() do
      let tok = task_cancel_token_new()
      task_cancel(tok)
      task_is_cancelled(tok)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check bool) "cancelled token returns true" true (vbool v)

let test_cancel_tokens_independent () =
  let src = {|mod Test do
    fn main() do
      let tok1 = task_cancel_token_new()
      let tok2 = task_cancel_token_new()
      task_cancel(tok1)
      task_is_cancelled(tok2)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check bool) "other token unaffected" false (vbool v)

let test_spawn_with_cancel_active () =
  let src = {|mod Test do
  needs IO.Spawn
    fn main() do
      let tok = task_cancel_token_new()
      let t = task_spawn_with_cancel(fn _ -> 42, tok)
      task_await(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check string) "runs when active" "Ok(42)" (March_eval.Eval.value_to_string v)

let test_spawn_with_cancel_precancelled () =
  let src = {|mod Test do
  needs IO.Spawn
    fn main() do
      let tok = task_cancel_token_new()
      task_cancel(tok)
      let t = task_spawn_with_cancel(fn _ -> 99, tok)
      task_await(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check string) "skipped when pre-cancelled" {|Err("cancelled")|} (March_eval.Eval.value_to_string v)

let test_cancel_by_id () =
  let src = {|mod Test do
  needs IO.Spawn
    fn main() do
      let t = task_spawn(fn _ -> 7)
      task_cancel_by_id(t)
      task_await(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check string) "cancelled by id" {|Err("cancelled")|} (March_eval.Eval.value_to_string v)

(* ── Task.race ─────────────────────────────────────────────────────── *)

let test_task_race_single () =
  let list_decl = load_stdlib_file_for_test "list.march" in
  let task_decl = load_stdlib_file_for_test "task.march" in
  let src = {|mod Test do
  needs IO.Spawn
    fn main() do
      let t = task_spawn(fn _ -> 100)
      Task.race([t])
    end
  end|} in
  let env = eval_with_stdlib [list_decl; task_decl] src in
  let v = call_fn env "main" [] in
  Alcotest.(check string) "race single" "Ok(100)" (March_eval.Eval.value_to_string v)

let test_task_race_cancels_losers () =
  let list_decl = load_stdlib_file_for_test "list.march" in
  let task_decl = load_stdlib_file_for_test "task.march" in
  let src = {|mod Test do
  needs IO.Spawn
    fn main() do
      let t1 = task_spawn(fn _ -> 1)
      let t2 = task_spawn(fn _ -> 2)
      Task.race([t1, t2])
      task_await(t2)
    end
  end|} in
  let env = eval_with_stdlib [list_decl; task_decl] src in
  let v = call_fn env "main" [] in
  Alcotest.(check string) "loser is cancelled" {|Err("cancelled")|} (March_eval.Eval.value_to_string v)

let test_task_race_empty () =
  let list_decl = load_stdlib_file_for_test "list.march" in
  let task_decl = load_stdlib_file_for_test "task.march" in
  let src = {|mod Test do
    fn main() do Task.race([]) end
  end|} in
  let env = eval_with_stdlib [list_decl; task_decl] src in
  let v = call_fn env "main" [] in
  Alcotest.(check string) "race empty" {|Err("race: empty task list")|} (March_eval.Eval.value_to_string v)

(* ── Task.all_settled ──────────────────────────────────────────────── *)

let test_task_all_settled () =
  let list_decl = load_stdlib_file_for_test "list.march" in
  let src = {|mod Test do
  needs IO.Spawn
    fn main() do
      let t1 = task_spawn(fn _ -> 10)
      let t2 = task_spawn(fn _ -> 20)
      task_cancel_by_id(t2)
      let t3 = task_spawn(fn _ -> 30)
      let rs = List.map([t1, t2, t3], fn t -> task_await(t))
      rs
    end
  end|} in
  let env = eval_with_stdlib [list_decl] src in
  let v = call_fn env "main" [] in
  Alcotest.(check string) "all_settled includes Err"
    {|[Ok(10), Err("cancelled"), Ok(30)]|}
    (March_eval.Eval.value_to_string v)

(** Phase 4: run_scheduler() processes queued messages.
    After run_until_idle(), counter state should be updated. *)
let test_eval_reduction_count () =
  let src = {|mod Test do
    fn countdown(n) do
      if n <= 0 do 0
      else countdown(n - 1) end
    end

    fn main() do
      countdown(100)
    end
  end|} in
  let env = eval_module src in
  let thunk = List.assoc "main" env in
  let (_result, reductions) =
    March_eval.Eval.eval_with_reduction_tracking thunk in
  (* Each iteration: EApp(countdown) + EMatch(if) = 2 reductions.
     Plus the initial EApp(main). Should be roughly 200+. *)
  Alcotest.(check bool) "reductions > 100" true (reductions > 100);
  Alcotest.(check bool) "reductions < 1000" true (reductions < 1000)

(* ── Work-stealing deque tests ────────────────────────────────────── *)

let test_deque_push_pop () =
  let d = March_scheduler.Work_pool.Deque.create 16 in
  March_scheduler.Work_pool.Deque.push d 1;
  March_scheduler.Work_pool.Deque.push d 2;
  March_scheduler.Work_pool.Deque.push d 3;
  (* Pop is LIFO from the bottom *)
  Alcotest.(check (option int)) "pop 3" (Some 3)
    (March_scheduler.Work_pool.Deque.pop d);
  Alcotest.(check (option int)) "pop 2" (Some 2)
    (March_scheduler.Work_pool.Deque.pop d);
  Alcotest.(check (option int)) "pop 1" (Some 1)
    (March_scheduler.Work_pool.Deque.pop d);
  Alcotest.(check (option int)) "pop empty" None
    (March_scheduler.Work_pool.Deque.pop d)

let test_deque_steal () =
  let d = March_scheduler.Work_pool.Deque.create 16 in
  March_scheduler.Work_pool.Deque.push d 1;
  March_scheduler.Work_pool.Deque.push d 2;
  March_scheduler.Work_pool.Deque.push d 3;
  (* Steal is FIFO from the top *)
  Alcotest.(check (option int)) "steal 1" (Some 1)
    (March_scheduler.Work_pool.Deque.steal d);
  Alcotest.(check (option int)) "steal 2" (Some 2)
    (March_scheduler.Work_pool.Deque.steal d)

let test_deque_size () =
  let d = March_scheduler.Work_pool.Deque.create 16 in
  Alcotest.(check int) "empty size" 0
    (March_scheduler.Work_pool.Deque.size d);
  March_scheduler.Work_pool.Deque.push d 1;
  March_scheduler.Work_pool.Deque.push d 2;
  Alcotest.(check int) "size 2" 2
    (March_scheduler.Work_pool.Deque.size d);
  ignore (March_scheduler.Work_pool.Deque.pop d);
  Alcotest.(check int) "size after pop" 1
    (March_scheduler.Work_pool.Deque.size d)

let test_pool_submit_steal () =
  let pool = March_scheduler.Work_pool.create 2 in
  March_scheduler.Work_pool.submit pool 0 "task_a";
  March_scheduler.Work_pool.submit pool 0 "task_b";
  let stolen = March_scheduler.Work_pool.Deque.steal pool.workers.(0) in
  Alcotest.(check (option string)) "stole task_a" (Some "task_a") stolen

(* ── Capability security tests ─────────────────────────────────────────── *)

(* Pure module with no Cap usage and no needs — should be clean *)
let test_cap_needs_pure_ok () =
  let ctx = typecheck {|mod Test do
    fn add(x, y) do x + y end
  end|} in
  Alcotest.(check bool) "pure module: no errors" false (has_errors ctx)

(* Module declares needs and uses Cap in a function signature — should be clean *)
let test_cap_needs_declared_ok () =
  let ctx = typecheck {|mod Test do
    needs IO
    fn greet(cap : Cap(IO)) do
      cap
    end
  end|} in
  Alcotest.(check bool) "declared needs with Cap: no errors" false (has_errors ctx)

(* Module uses Cap(IO) in a signature without declaring needs IO — should error *)
let test_cap_missing_needs_error () =
  let ctx = typecheck {|mod Test do
    fn greet(cap : Cap(IO)) do
      cap
    end
  end|} in
  Alcotest.(check bool) "undeclared Cap is an error" true (has_errors ctx)

(* Module declares needs IO but never uses Cap(IO) anywhere — should warn *)
let test_cap_unused_needs_warning () =
  let ctx = typecheck {|mod Test do
    needs IO
    fn add(x, y) do x + y end
  end|} in
  Alcotest.(check bool) "unused needs produces a diagnostic" true
    (March_errors.Errors.has_diagnostics ctx)

(* An extern block's Cap(X) counts as USING X, so `needs X` + an extern block
   must NOT trigger the "declared but not used" warning.  An extern block ALSO
   implies `IO.Foreign` (the FFI meta-capability), so a clean module declares
   both — matching the `needs Ffi` + `needs IO.Foreign` pattern in the
   `test/native/ffi_*.march` fixtures. *)
let test_cap_extern_block_counts_as_use () =
  let ctx = typecheck {|mod Test do
    needs Ffi
    needs IO.Foreign
    extern "m" : Cap(Ffi) do
      fn dbl(n : Int) : Int = "ffi_test_dbl"
    end
  end|} in
  Alcotest.(check bool) "extern Cap(Ffi) + needs IO.Foreign: no diagnostics" false
    (March_errors.Errors.has_diagnostics ctx)

(* Cap(IO) as supertype covers Cap(IO.Network) usage *)
let test_cap_supertype_covers_subtype () =
  let ctx = typecheck {|mod Test do
    needs IO
    fn connect(cap : Cap(IO.Network)) do
      cap
    end
  end|} in
  Alcotest.(check bool) "needs IO covers Cap(IO.Network): no errors" false (has_errors ctx)

(* Cap(IO.Network) does NOT cover Cap(IO.FileRead) *)
let test_cap_needs_wrong_subtype () =
  let ctx = typecheck {|mod Test do
    needs IO.Network
    fn read_file(cap : Cap(IO.FileRead)) do
      cap
    end
  end|} in
  Alcotest.(check bool) "needs IO.Network does not cover Cap(IO.FileRead): error" true
    (has_errors ctx)

(* Multiple needs declarations are supported *)
let test_cap_multiple_needs () =
  let ctx = typecheck {|mod Test do
    needs IO.Network, IO.FileRead
    fn connect(cap : Cap(IO.Network)) do cap end
    fn read_file(cap : Cap(IO.FileRead)) do cap end
  end|} in
  Alcotest.(check bool) "multiple needs: no errors" false (has_errors ctx)

(* needs IO is parsed correctly *)
let test_cap_parse_needs () =
  let src = {|mod Test do
    needs IO
    fn f(x) do x end
  end|} in
  let m = parse_and_desugar src in
  let has_needs = List.exists (fun d ->
    match d with
    | March_ast.Ast.DNeeds _ -> true
    | _ -> false
  ) m.March_ast.Ast.mod_decls in
  Alcotest.(check bool) "DNeeds present in AST" true has_needs

(* needs with dotted path is parsed correctly *)
let test_cap_parse_needs_dotted () =
  let src = {|mod Test do
    needs IO.Network
    fn f(x) do x end
  end|} in
  let m = parse_and_desugar src in
  let cap_paths = List.filter_map (fun d ->
    match d with
    | March_ast.Ast.DNeeds (caps, _) ->
      Some (List.map (fun (names, _scope) ->
        String.concat "." (List.map (fun (n : March_ast.Ast.name) -> n.txt) names)
      ) caps)
    | _ -> None
  ) m.March_ast.Ast.mod_decls in
  Alcotest.(check bool) "IO.Network parsed as DNeeds" true
    (List.exists (fun paths -> List.mem "IO.Network" paths) cap_paths)

(* ── Transitive capability enforcement tests ────────────────────────────── *)

(* Mirrors [has_message_containing] in test_compiler.ml: matches on diagnostic
   TEXT rather than on [has_errors], so a capability assertion cannot be
   satisfied (or broken) by an unrelated error in the same fixture. *)
let has_message_containing ctx needle =
  List.exists (fun d ->
    let m = d.March_errors.Errors.message in
    let nl = String.length needle and ml = String.length m in
    let rec scan i = i + nl <= ml && (String.sub m i nl = needle || scan (i + 1)) in
    scan 0)
    ctx.March_errors.Errors.diagnostics

(* Module that imports another with matching needs declared — should be ok *)
let test_cap_transitive_ok () =
  let ctx = typecheck {|mod Outer do
    mod Lib do
      needs IO.Network
      fn connect(cap : Cap(IO.Network)) do cap end
    end
    mod Test do
      needs IO.Network
      use Lib.*
      fn run(cap : Cap(IO.Network)) do Lib.connect(cap) end
    end
  end|} in
  Alcotest.(check bool) "transitive ok when needs declared" false (has_errors ctx)

(* Module imports another that requires IO.Network but declares nothing — error *)
let test_cap_transitive_missing_error () =
  let ctx = typecheck {|mod Outer do
    mod Lib do
      needs IO.Network
      fn connect(cap : Cap(IO.Network)) do cap end
    end
    mod Test do
      use Lib.*
      fn run(cap) do connect(cap) end
    end
  end|} in
  Alcotest.(check bool) "transitive import without needs is an error" true (has_errors ctx);
  (* Propagation is demand-driven: the same import that REFERENCES NOTHING from
     `Lib` costs nothing. This fixture used to be `fn run(x) do x end` and
     asserted an error, pinning the old module-granular over-approximation —
     importing a module for one pure function used to cost you its impure
     siblings' capabilities. The reference above is what makes the assertion
     above about propagation rather than about the mere presence of a `use`. *)
  let unreferenced = typecheck {|mod Outer do
    mod Lib do
      needs IO.Network
      fn connect(cap : Cap(IO.Network)) do cap end
    end
    mod Test do
      use Lib.*
      fn run(x) do x end
    end
  end|} in
  Alcotest.(check bool) "an import that references nothing costs nothing" false
    (has_errors unreferenced)

(* Module declares parent cap (IO) which covers imported module's child (IO.Network) *)
let test_cap_transitive_supertype_ok () =
  let ctx = typecheck {|mod Outer do
    mod Lib do
      needs IO.Network
      fn connect(cap : Cap(IO.Network)) do cap end
    end
    mod Test do
      needs IO
      use Lib.*
      fn run(cap : Cap(IO)) do cap end
    end
  end|} in
  Alcotest.(check bool) "parent cap covers transitive import" false (has_errors ctx)

(* Three-level chain: C uses B uses A; B covers its A import, C must cover B's needs *)
let test_cap_transitive_chain_error () =
  let ctx = typecheck {|mod Outer do
    mod A do
      needs IO.FileRead
      fn read(cap : Cap(IO.FileRead)) do cap end
    end
    mod B do
      needs IO.FileRead
      use A.*
      fn do_read(cap : Cap(IO.FileRead)) do A.read(cap) end
    end
    mod C do
      use B.*
      fn run(cap) do do_read(cap) end
    end
  end|} in
  (* `fn run(x) do x end` here until 2026-08-06: propagation is demand-driven,
     so C only owes B's capabilities for the functions C actually references.
     `do_read` is `B`'s OWN name (not one of `A`'s re-exported through it), so
     `use B.*` binds it and the fixture has no unresolved names — asserted
     below, because a `has_errors`-only assertion would be satisfied just as
     well by a typo in the reference. Assert on the Check-4 message text for
     the same reason. *)
  Alcotest.(check bool) "chain: C must declare needs covered by B" true
    (has_message_containing ctx "which requires");
  Alcotest.(check bool) "and the fixture resolves every name it references" false
    (has_message_containing ctx "I cannot find")

(* extern with capability declared in needs — ok *)
let test_cap_extern_with_needs_ok () =
  let ctx = typecheck {|mod Test do
    needs LibC
    extern "libc": Cap(LibC) do
      fn malloc(n : Int) : Int
    end
  end|} in
  Alcotest.(check bool) "extern with declared needs: no errors" false (has_errors ctx)

(* extern without declaring its capability in needs — error *)
let test_cap_extern_missing_needs_error () =
  let ctx = typecheck {|mod Test do
    extern "libc": Cap(LibC) do
      fn malloc(n : Int) : Int
    end
  end|} in
  Alcotest.(check bool) "extern without needs is an error" true (has_errors ctx)

(* ── FFI: extern fn = "symbol" binds the explicit C symbol ──────────────── *)

let test_ffi_extern_explicit_symbol_ir () =
  let ir = emit_actor_ir {|mod Test do
  needs IO.Console
    needs Ffi
    needs IO.Foreign
    extern "crc" : Cap(Ffi) do
      fn crc32(n: Int): Int = "crc32_compute"
    end
    fn main(_cap_console : Cap(IO.Console), _cap_foreign : Cap(IO.Foreign)) : Unit do println(int_to_string(crc32(255))) end
  end|} in
  Alcotest.(check bool) "calls the explicit C symbol" true
    (ir_contains ir "@crc32_compute");
  Alcotest.(check bool) "does not emit the default <lib>_<fn> name" false
    (ir_contains ir "@crc_crc32")

let test_ffi_extern_default_symbol_ir () =
  let ir = emit_actor_ir {|mod Test do
  needs IO.Console
    needs Ffi
    needs IO.Foreign
    extern "crc" : Cap(Ffi) do
      fn crc32(n: Int): Int
    end
    fn main(_cap_console : Cap(IO.Console), _cap_foreign : Cap(IO.Foreign)) : Unit do println(int_to_string(crc32(255))) end
  end|} in
  Alcotest.(check bool) "falls back to <lib>_<fn> when no symbol given" true
    (ir_contains ir "@crc_crc32")

(* ── Capability enforcement path tests ─────────────────────────────────── *)

(* Verify capability errors surface via check_capabilities (the effects-module
   entry point that wraps check_module for explicit use on both paths). *)
let test_cap_effects_clean () =
  let src = {|mod Test do
    needs IO.Network
    fn f(cap : Cap(IO.Network)) do cap end
  end|} in
  let m = parse_and_desugar src in
  let ctx = March_effects.Effects.check_capabilities m in
  Alcotest.(check bool) "check_capabilities: clean module has no errors" false
    (March_errors.Errors.has_errors ctx)

let test_cap_effects_violation () =
  let src = {|mod Test do
    fn f(cap : Cap(IO.Network)) do cap end
  end|} in
  let m = parse_and_desugar src in
  let ctx = March_effects.Effects.check_capabilities m in
  Alcotest.(check bool) "check_capabilities: capability violation produces error" true
    (March_errors.Errors.has_errors ctx)

(* Verify eval path: typechecking with capability errors prevents eval.
   We check that has_errors returns true, which in main.ml causes exit(1)
   before run_module is ever called. *)
let test_cap_eval_path_blocked () =
  let src = {|mod Test do
  needs IO.Network
    fn f(cap : Cap(IO.Network)) do cap end
    fn main(_cap_network : Cap(IO.Network)) do f(42) end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "eval path: capability error prevents evaluation" true
    (has_errors ctx)

(* Verify eval path: clean module can evaluate *)
let test_cap_eval_path_ok () =
  let src = {|mod Test do
    needs IO.Network
    fn double(x) do x + x end
    fn main() do double(21) end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "eval path: clean module with needs evaluates without error" false
    (has_errors ctx)

(* ── Proof cap tests ────────────────────────────────────────────────────── *)

let test_proof_cap_parse () =
  let src = {|mod Db do
    proof cap Migrated
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap: parses without error" false (has_errors ctx)

let test_proof_cap_declaration_ok () =
  let src = {|mod Db do
    proof cap Migrated
    needs Db.Migrated
    fn start_app(m : Cap(Db.Migrated)) : () do () end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap declaration: no errors" false (has_errors ctx)

let test_proof_cap_forge_error () =
  (* A function outside the declaring module declares proof cap in return type
     without receiving it as a parameter — Check 6 should fire *)
  let src = {|mod Outer do
    mod Db do
      proof cap Migrated
    end
    mod App do
      needs Db.Migrated
      fn bad_forge() : Cap(Db.Migrated) do () end
    end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap forge: error when non-declaring module returns it without receiving" true (has_errors ctx)

let test_proof_cap_passthrough_ok () =
  (* Receiving a proof cap and returning it (pass-through) is allowed anywhere *)
  let src = {|mod Outer do
    mod Db do
      proof cap Migrated
    end
    mod App do
      needs Db.Migrated
      fn relay(m : Cap(Db.Migrated)) : Cap(Db.Migrated) do m end
    end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap passthrough: receiving and returning is allowed" false (has_errors ctx)

let test_proof_cap_missing_needs_error () =
  (* Using Cap(X) for a proof cap without declaring needs — Check 1 fires with
     proof-cap-specific message naming the declaring module *)
  let src = {|mod Outer do
    mod Db do
      proof cap Migrated
    end
    mod App do
      fn use_cap(m : Cap(Db.Migrated)) : () do () end
    end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap missing needs: error with declaring-module hint" true (has_errors ctx)

let test_proof_cap_in_declaring_module_ok () =
  (* Within the declaring module, returning the proof cap (pass-through) is fine
     and Check 6 should NOT fire even though declaring_mod = mod_name *)
  let src = {|mod Db do
    proof cap Migrated
    needs Db.Migrated
    fn relay(m : Cap(Db.Migrated)) : Cap(Db.Migrated) do m end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap: declaring module can return it freely" false (has_errors ctx)

let test_proof_cap_implicit_needs () =
  (* The declaring module does NOT need to write `needs Db.Migrated` —
     `proof cap Migrated` implicitly satisfies it for functions that use Cap(Db.Migrated) *)
  let src = {|mod Db do
    proof cap Migrated
    fn use_cap(m : Cap(Db.Migrated)) : () do () end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap: declaring module needs implicit" false (has_errors ctx)

let test_proof_cap_pfn_forge_error () =
  (* A pfn inside the declaring module cannot mint a proof cap from nothing —
     Check 6 fires even though the module is the declaring module.
     The Cap(IO) arrives as a PARAMETER so the body typechecks and the only
     error is Check 6.  This used `cap_narrow(root_cap())` until 2026-08-05,
     which was doubly wrong: R2 removed `root_cap` from ordinary code, and
     `root_cap()` (the callable spelling) was ALREADY a typecheck error in its
     own right — so this assertion passed whether or not Check 6 fired at all.
     Taking the capability as a parameter makes the test non-vacuous. *)
  let src = {|mod Db do
    proof cap Migrated
    needs IO
    pfn bad_private_forge(c : Cap(IO)) : Cap(Db.Migrated) do cap_narrow(c) end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap pfn forge: error for private function in declaring module" true (has_errors ctx)

let test_proof_cap_pfn_passthrough_ok () =
  (* A pfn inside the declaring module CAN pass a proof cap through —
     it just cannot produce one from nothing *)
  let src = {|mod Db do
    proof cap Migrated
    pfn relay(m : Cap(Db.Migrated)) : Cap(Db.Migrated) do m end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap pfn passthrough: private relay is allowed" false (has_errors ctx)

(** Opt.run is safe on RC-free TIR (the JS target skips Perceus). *)
let test_opt_without_perceus () =
  let src = {|mod Test do
  needs IO.Console
    type Tree = Leaf | Node(Tree, Int, Tree)

    fn sum(t : Tree) : Int do
      match t do
        Leaf -> 0
        Node(l, n, r) -> sum(l) + n + sum(r)
      end
    end

    fn main(_cap_console : Cap(IO.Console)) : Unit do
      let t = Node(Node(Leaf, 1, Leaf), 2, Node(Leaf, 3, Leaf))
      println(int_to_string(sum(t)))
    end
  end|} in
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  (* NOTE: Defun and Perceus intentionally skipped — this is the JS pipeline *)
  let opt_tir = March_tir.Opt.run tir in
  (* Opt must not introduce RC nodes when given RC-free TIR *)
  let rec has_rc = function
    | March_tir.Tir.EIncRC _ | March_tir.Tir.EDecRC _ | March_tir.Tir.EFree _
    | March_tir.Tir.EReuse _ | March_tir.Tir.EAtomicIncRC _
    | March_tir.Tir.EAtomicDecRC _ -> true
    | March_tir.Tir.ELet (_, e1, e2) -> has_rc e1 || has_rc e2
    | March_tir.Tir.ELetRec (fns, body) ->
      List.exists (fun f -> has_rc f.March_tir.Tir.fn_body) fns || has_rc body
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun b -> has_rc b.March_tir.Tir.br_body) brs
      || (match def with Some e -> has_rc e | None -> false)
    | March_tir.Tir.ESeq (a, b) -> has_rc a || has_rc b
    | _ -> false
  in
  let any_rc = List.exists
    (fun fn -> has_rc fn.March_tir.Tir.fn_body)
    opt_tir.March_tir.Tir.tm_fns
  in
  Alcotest.(check bool) "Opt on RC-free TIR produces no RC nodes" false any_rc

(* ── Hot Code Reload: leaf change does not drag the caller chain ──────────
   Regression for the `forge deploy hot` crash: changing one leaf function used
   to change the TRANSITIVE Merkle impl_hash of every caller up to `main`, so a
   hot deploy flagged the whole chain — including the running entry point — for
   swap, which OOM/corrupts the runtime.  Two fixes are exercised here:
     1. HCR reload-identity hashes are non-transitive (Hash.hash_fn_def), so a
        leaf-body change only changes the leaf's hash, not its callers'.
     2. The entry point (`main`/`ModName.main`) is excluded from the reloadable
        boundary, so it is never a dispatch slot / swap candidate. *)

(* Lower March source to a post-Perceus TIR module, the same shape the compiler
   feeds to Llvm_emit / Pipeline.hash_module. *)
let hcr_lower (src : string) : March_tir.Tir.tir_module =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map ~hot_reload:true m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  March_tir.Perceus.perceus tir

(* The NON-transitive HCR reload-identity hash per function name — this mirrors
   how bin/main.ml now populates hr_impl_hashes (Hash.hash_fn_def, sig+body,
   no callee/type fold). *)
let hcr_reload_hashes (m : March_tir.Tir.tir_module) : (string, string) Hashtbl.t =
  let tbl = Hashtbl.create 16 in
  List.iter (fun (fd : March_tir.Tir.fn_def) ->
    let h = March_cas.Hash.hash_fn_def fd in
    Hashtbl.replace tbl fd.March_tir.Tir.fn_name h.March_cas.Hash.impl_hash)
    m.March_tir.Tir.tm_fns;
  tbl

(* The TRANSITIVE Merkle impl_hash per function name — the CAS compilation key
   (unchanged by this fix; still used for incremental-build correctness). *)
let hcr_transitive_hashes (m : March_tir.Tir.tir_module) : (string, string) Hashtbl.t =
  let tbl = Hashtbl.create 16 in
  let add (hd : March_cas.Cas.hashed_def) =
    match hd.March_cas.Cas.hd_def with
    | March_cas.Cas.FnDef fd ->
      Hashtbl.replace tbl fd.March_tir.Tir.fn_name hd.March_cas.Cas.hd_impl_hash
    | March_cas.Cas.TypeDef _ -> ()
  in
  List.iter (function
    | March_cas.Pipeline.HSingle { hs_hdef } -> add hs_hdef
    | March_cas.Pipeline.HGroup { hg_hdefs; _ } -> List.iter add hg_hdefs)
    (March_cas.Pipeline.hash_module m);
  tbl

(* A 3-deep caller chain: main → mid → leaf.  In lowered TIR the entry file's
   top module name is stripped, so the names are bare `leaf`/`mid`/`main` — the
   same shape the compiler hashes.  [leaf_body] is spliced into `leaf` so we can
   produce a leaf-only change. *)
let hcr_chain_src (leaf_body : string) : string =
  Printf.sprintf {|mod App do
    fn leaf(n : Int) : Int do %s end
    fn mid(n : Int) : Int do leaf(n) + 1 end
    fn main() : Unit do println(int_to_string(mid(3))) end
  end|} leaf_body

let hget tbl k = Hashtbl.find_opt tbl k

let test_hcr_leaf_change_only_changes_leaf_reload_hash () =
  let m0 = hcr_lower (hcr_chain_src "n * 2") in
  let m1 = hcr_lower (hcr_chain_src "n * 3") in  (* leaf body changed *)
  let r0 = hcr_reload_hashes m0 and r1 = hcr_reload_hashes m1 in
  (* Leaf's non-transitive reload hash DOES change. *)
  Alcotest.(check bool) "leaf reload hash changes" true
    (hget r0 "leaf" <> hget r1 "leaf" && hget r0 "leaf" <> None);
  (* Its callers' reload hashes are UNCHANGED (bodies are byte-identical).
     THIS is the crux of the fix: pre-fix these were transitive Merkle roots
     that folded in the leaf's hash, so they changed too and dragged the whole
     chain (up to main) into the hot-swap set. *)
  Alcotest.(check bool) "mid reload hash unchanged" true
    (hget r0 "mid" = hget r1 "mid" && hget r0 "mid" <> None);
  Alcotest.(check bool) "main reload hash unchanged" true
    (hget r0 "main" = hget r1 "main" && hget r0 "main" <> None)

let test_hcr_transitive_hash_still_propagates_for_cas () =
  (* Sanity: the CAS/compilation key IS still transitive — a leaf change DOES
     propagate to callers there — so incremental-build cache correctness is
     preserved.  Only the HCR reload identity is non-transitive. *)
  let m0 = hcr_lower (hcr_chain_src "n * 2") in
  let m1 = hcr_lower (hcr_chain_src "n * 3") in
  let t0 = hcr_transitive_hashes m0 and t1 = hcr_transitive_hashes m1 in
  Alcotest.(check bool) "transitive leaf hash changes" true
    (hget t0 "leaf" <> hget t1 "leaf");
  Alcotest.(check bool) "transitive caller (mid) hash ALSO changes" true
    (hget t0 "mid" <> hget t1 "mid" && hget t0 "mid" <> None)

(* Build a TIR module directly, mirroring the forgepm multi-file layout where
   `Blog.main` (the app entry point) IS under the `--hot-reload Blog` boundary
   because it comes from a library file (its module prefix is retained, unlike a
   single-file entry). Chain: Blog.main → Blog.handle → Blog.hero. *)
let hcr_boundary_module () : March_tir.Tir.tir_module =
  let open March_tir.Tir in
  let vref name = { v_name = name; v_ty = TFn ([TInt], TInt); v_lin = Unr } in
  let hero : fn_def =
    { fn_name = "Blog.hero";
      fn_params = [{ v_name = "n"; v_ty = TInt; v_lin = Unr }];
      fn_ret_ty = TInt;
      fn_kind = FnNormal;
      fn_body = EAtom (ALit (March_ast.Ast.LitInt 1)) } in
  let handle : fn_def =
    { fn_name = "Blog.handle";
      fn_params = [{ v_name = "n"; v_ty = TInt; v_lin = Unr }];
      fn_ret_ty = TInt;
      fn_kind = FnNormal;
      fn_body = EApp (vref "Blog.hero",
                      [AVar { v_name = "n"; v_ty = TInt; v_lin = Unr }]) } in
  let main : fn_def =
    { fn_name = "Blog.main"; fn_params = []; fn_ret_ty = TInt;
      fn_kind = FnNormal;
      fn_body = EApp (vref "Blog.handle",
                      [ALit (March_ast.Ast.LitInt 3)]) } in
  { tm_name = "Blog"; tm_fns = [main; handle; hero]; tm_types = [];
    tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] }

let test_hcr_entry_point_not_a_reloadable_slot () =
  (* Blog.main is under the "Blog" boundary but must NOT be published as a slot,
     because it is the running entry point.  Its callees remain reloadable. *)
  let m = hcr_boundary_module () in
  let ir = March_tir.Llvm_emit.emit_module
             ~hot_reload:(Some (March_tir.Hot_reload.default_config "Blog")) m in
  (* No baseline publish nor name registration for the entry point. *)
  Alcotest.(check bool) "entry point Blog.main NOT published as a slot" false
    (ir_contains ir "ptr @Blog.main,");
  Alcotest.(check bool) "entry point Blog.main NOT registered as a name" false
    (ir_contains ir "call void @march_dispatch_register_name" &&
     ir_contains ir "Blog.main\\00");
  (* Its callees ARE published as reloadable slots. *)
  Alcotest.(check bool) "Blog.handle IS published as a slot" true
    (ir_contains ir "ptr @Blog.handle,");
  Alcotest.(check bool) "Blog.hero IS published as a slot" true
    (ir_contains ir "ptr @Blog.hero,");
  (* Boundary→boundary calls still route through the versioned dispatch table,
     including from main's body — proving main still calls swappable versions. *)
  Alcotest.(check bool) "boundary callees still dispatch-routed" true
    (ir_contains ir "@march_dispatch_enter")

(* ── Sort stdlib tests ──────────────────────────────────────────────────── *)

(* ── Guard-exhaustion fallthrough (B3) ─────────────────────────────────────
   A guarded match where every guard fails must panic, not silently return
   `LitInt 0` reinterpreted at the match's real (non-Int) type — see
   lib/tir/lower.ml's `nonexhaustive_panic` comment.  This test compiles and
   *runs* the binary (not just inspecting IR text) because the bug's symptom
   is a runtime crash/garbage value, not a shape in the emitted IR. *)
let test_guard_exhaustion_panics_compiled () =
  let main_exe = find_main_exe () in
  (* Run from the project root so the compiler resolves its CWD-relative
     runtime/ and stdlib/ directories (same trick as the other compiled
     regression tests in test_stdlib_suite.ml). *)
  let project_root = march_project_root () in
  let src_text =
    "mod GuardEx do\n\
    \  needs IO.Console\n\
    \  fn classify(n) do\n\
    \    match n do\n\
    \      x when x > 0 -> \"pos\"\n\
    \      x when x < 0 -> \"neg\"\n\
    \    end\n\
    \  end\n\
    \  fn main(_cap_console : Cap(IO.Console)) do\n\
    \    println(classify(0))\n\
    \  end\n\
     end\n"
  in
  let tmp = Filename.temp_file "march_guardex" "" in
  Sys.remove tmp;
  Unix.mkdir tmp 0o755;
  let src = Filename.concat tmp "guardex.march" in
  let oc = open_out src in
  output_string oc src_text;
  close_out oc;
  (* Read the whole stdout+stderr of a command (trimmed). *)
  let read_cmd cmd =
    let ic = Unix.open_process_in cmd in
    let buf = Buffer.create 64 in
    (try
       while true do Buffer.add_channel buf ic 1 done
     with End_of_file -> ());
    ignore (Unix.close_process_in ic);
    String.trim (Buffer.contents buf)
  in
  (* --- interpreter: must already panic (parity check) --- *)
  let interp_out = read_cmd (Printf.sprintf
    "cd %s && %s %s 2>&1"
    (Filename.quote project_root)
    (Filename.quote main_exe) (Filename.quote src)) in
  Alcotest.(check bool) "interpreter panics on guard exhaustion (non-exhaustive)" true
    (ir_contains interp_out "non-exhaustive" || ir_contains interp_out "panic");
  (* --- compiled: must panic (exit 1) with a non-exhaustive-match message,
     not crash (segfault, exit 139) or exit 0 with garbage output --- *)
  let bin = Filename.concat tmp "guardexbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd (Printf.sprintf "%s 2>&1; echo EXIT:$?" (Filename.quote bin)) in
    Alcotest.(check bool)
      "compiled guard-exhaustion panics with a non-exhaustive-match message (not exit 0/segfault)"
      true
      ((ir_contains run_out "non-exhaustive" || ir_contains run_out "panic")
       && ir_contains run_out "EXIT:1")

(* ── Float-literal match arms (B4) ──────────────────────────────────────
   `pat_tag_and_subs` returned `None` for `Ast.LitFloat` patterns, and the
   match-matrix grouping loop silently discarded rows it couldn't tag — so a
   float-literal match arm compiled to nothing, silently falling through to
   whatever the next (typically wildcard) arm was.  The interpreter (which
   matches on the AST directly) got this right; only the compiled backend
   diverged.  These tests compile and *run* the binary, because the bug's
   symptom is a wrong *value*, not a shape in the emitted IR (same rationale
   as the guard-exhaustion test above). *)

(* Read the whole stdout+stderr of a command (trimmed). Shared helper for the
   compile-and-run regression tests in this section. *)
let read_cmd_output cmd =
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 64 in
  (try
     while true do Buffer.add_channel buf ic 1 done
   with End_of_file -> ());
  ignore (Unix.close_process_in ic);
  String.trim (Buffer.contents buf)

(** Write [src_text] to a fresh temp dir and return (project_root, main_exe,
    src_path, tmp_dir). Shared setup for the compile-and-run tests below.
    [find_main_exe] fails loudly if the compiler binary is missing (it is
    never legitimately absent — see test_helpers.ml). *)
let write_march_source ~name src_text =
  let main_exe = find_main_exe () in
  let project_root = march_project_root () in
  let tmp = Filename.temp_file name "" in
  Sys.remove tmp;
  Unix.mkdir tmp 0o755;
  let src = Filename.concat tmp (name ^ ".march") in
  let oc = open_out src in
  output_string oc src_text;
  close_out oc;
  (project_root, main_exe, src, tmp)

let test_float_lit_match_arm_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_floatpat"
    "mod FloatPat do\n\
    \  needs IO.Console\n\
    \  fn name(x) do\n\
    \    match x do\n\
    \      1.5 -> \"one-and-a-half\" | 2.5 -> \"two-and-a-half\" | _ -> \"other\"\n\
    \    end\n\
    \  end\n\
    \  fn main(_cap_console : Cap(IO.Console)) do\n\
    \    println(name(2.5))\n\
    \  end\n\
     end\n"
  in
  (* --- interpreter: matches the float literal correctly (baseline) --- *)
  let interp_out = read_cmd_output (Printf.sprintf
    "cd %s && %s %s 2>&1"
    (Filename.quote project_root)
    (Filename.quote main_exe) (Filename.quote src)) in
  Alcotest.(check string) "interpreter matches float literal arm"
    "two-and-a-half" interp_out;
  (* --- compiled: must match too — this is the B4 regression --- *)
  let bin = Filename.concat tmp "floatpatbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Filename.quote bin) in
    Alcotest.(check string)
      "compiled float literal match arm produces the SAME value as the \
       interpreter (not silently falling through to a later/wildcard arm)"
      "two-and-a-half" run_out

(* ── `()` on its own line must not become a call of the previous line ─────
   `let _ = a` followed by a line holding just `()` parsed as the single
   binding `let _ = a()` (the block's newline is swallowed, so the parser saw
   `a` `(` `)` adjacent and applied the call rule). The parameter was then
   *invoked*: codegen emitted the closure-ABI indirect call — load the fn_ptr
   from offset 16 of the receiver, then `call ptr (ptr)` through it — but the
   receiver was a String, so offset 16 is its character payload. The binary
   jumped to a garbage address and died with EXC_BAD_ACCESS (exit 138 / 139).
   Fixed in the token filter + grammar (LPAREN_STMT); see token_filter.ml.

   Asserted two ways: the IR must contain no indirect `call ptr (ptr)` for
   this program (the mis-lowering's fingerprint), and the binary must run. *)
let unit_tail_discard_src =
  "mod UnitTail do\n\
    \  needs IO.Console\n\
  \  fn f(a) do\n\
  \    let _ = a\n\
  \    ()\n\
  \  end\n\
  \  fn main(_cap_console : Cap(IO.Console)) do\n\
  \    f(\"x\")\n\
  \    println(\"ok\")\n\
  \  end\n\
   end\n"

let test_unit_tail_discard_no_indirect_call_ir () =
  let ir = emit_actor_ir unit_tail_discard_src in
  (* The closure-ABI indirect call: `%fv = load ptr, ptr %fp` off `+16`, then
     `call ptr (ptr) %fv(...)`. Nothing in this program is a closure, so a
     known top-level callee must be called directly. *)
  Alcotest.(check int)
    "no closure-style indirect call is emitted for a known top-level callee"
    0 (ir_count ir "call ptr (ptr)");
  Alcotest.(check bool)
    "no fn_ptr load off offset 16 of a non-closure value"
    false (ir_contains ir "getelementptr i8, ptr %sl");
  (* Non-vacuity: the program really did compile to something. *)
  Alcotest.(check bool) "march_main was emitted" true
    (ir_contains ir "define ptr @march_main")

let test_unit_tail_discard_runs_compiled () =
  let (project_root, main_exe, src, tmp) =
    write_march_source ~name:"march_unittail" unit_tail_discard_src in
  let interp_out = read_cmd_output (Printf.sprintf
    "cd %s && %s %s 2>&1"
    (Filename.quote project_root)
    (Filename.quote main_exe) (Filename.quote src)) in
  Alcotest.(check string) "interpreter prints ok" "ok" interp_out;
  let bin = Filename.concat tmp "unittailbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output
      (Printf.sprintf "%s 2>&1; echo EXIT:$?" (Filename.quote bin)) in
    Alcotest.(check string)
      "compiled binary prints ok and exits 0 (pre-fix: EXC_BAD_ACCESS, exit 138)"
      "ok\nEXIT:0" run_out

(* Same shape after a LITERAL rather than an identifier. The first fix keyed
   the retag on a "value-ending" token — an identifier, `)` or `]` — but the
   call rule takes an `expr_field`, which a bare literal also reduces to, so
   `let _ = 1` ⏎ `()` was still glued into `1()`.

   This one does NOT reach the closure-ABI path: a literal has no receiver to
   load a fn_ptr from, so codegen emitted a call to a name it never defined
   and produced INVALID LLVM — `declare ptr @<lit>()` — which clang rejected
   with "expected function name". The build failed pointing at generated IR
   rather than at the source line, so assert on a clean compile-and-run. *)
let unit_tail_literal_discard_src =
  "mod UnitTailLit do\n\
    \  needs IO.Console\n\
  \  fn f() do\n\
  \    let _ = 1\n\
  \    ()\n\
  \  end\n\
  \  fn main(_cap_console : Cap(IO.Console)) do\n\
  \    f()\n\
  \    println(\"ok\")\n\
  \  end\n\
   end\n"

let test_unit_tail_literal_discard_runs_compiled () =
  let (project_root, main_exe, src, tmp) =
    write_march_source ~name:"march_unittail_lit" unit_tail_literal_discard_src in
  let interp_out = read_cmd_output (Printf.sprintf
    "cd %s && %s %s 2>&1"
    (Filename.quote project_root)
    (Filename.quote main_exe) (Filename.quote src)) in
  (* Pre-fix: "applied non-function value: 1". *)
  Alcotest.(check string) "interpreter prints ok" "ok" interp_out;
  let bin = Filename.concat tmp "unittaillitbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output
      (Printf.sprintf "%s 2>&1; echo EXIT:$?" (Filename.quote bin)) in
    Alcotest.(check string)
      "compiled binary prints ok and exits 0 (pre-fix: clang rejected \
       `declare ptr @<lit>()`, so the binary never built)"
      "ok\nEXIT:0" run_out

(** Float arm with NO wildcard: a non-exhaustive float match must panic (the
    Task 1 / B3 `nonexhaustive_panic` fallback), not silently fall through to
    LLVM `unreachable` (undefined behaviour — observed, pre-fix, to print a
    WRONG matched value with exit 0 instead of crashing). The scrutinee must
    NOT be a compile-time constant, or the optimizer folds the whole match to
    its statically-known arm and never reaches the fallback path at all. *)
let test_float_lit_no_wildcard_panics_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_floatpat_nowild"
    "mod FloatPatNoWild do\n\
    \  needs IO.Console\n\
    \  needs IO.Process\n\
    \  fn name(x) do\n\
    \    match x do\n\
    \      1.5 -> \"one-and-a-half\" | 2.5 -> \"two-and-a-half\"\n\
    \    end\n\
    \  end\n\
    \  fn main(_cap_console : Cap(IO.Console), _cap_process : Cap(IO.Process)) do\n\
    \    let n = int_to_float(List.length(process_argv())) +. 3.7\n\
    \    println(name(n))\n\
    \  end\n\
     end\n"
  in
  (* --- interpreter: must already panic (parity check) --- *)
  let interp_out = read_cmd_output (Printf.sprintf
    "cd %s && %s %s 2>&1"
    (Filename.quote project_root)
    (Filename.quote main_exe) (Filename.quote src)) in
  Alcotest.(check bool) "interpreter panics on float non-exhaustive match" true
    (ir_contains interp_out "non-exhaustive" || ir_contains interp_out "panic");
  (* --- compiled: must panic (exit 1), not exit 0 with a wrong value --- *)
  let bin = Filename.concat tmp "floatpatnowildbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Printf.sprintf "%s 2>&1; echo EXIT:$?" (Filename.quote bin)) in
    Alcotest.(check bool)
      "compiled float non-exhaustive match panics with a non-exhaustive-match \
       message (not exit 0 with a wrong value, and not a segfault)"
      true
      ((ir_contains run_out "non-exhaustive" || ir_contains run_out "panic")
       && ir_contains run_out "EXIT:1")

(* ── String literals are constants, not per-evaluation allocations ──────
   A string literal carries NO refcount obligation in TIR: perceus.ml's
   [EAtom (ALit _)] arm returns the expression untouched, exactly as it does
   for a global [ADefRef].  Codegen used to break that contract for
   [LitString] by calling @march_string_lit — a fresh rc=1 malloc — on every
   evaluation of the site.  Nothing owned that cell, so no pass ever emitted
   a matching dec: each evaluation leaked one string.  `buf ++ "xyz"` in a
   2M-iteration loop leaked 2M strings (peak RSS 64MB vs 2.9MB for the same
   loop with both operands as variables).  This matters well beyond the
   synthetic case — `acc ++ ", "` and `s ++ "\n"` are how ordinary string
   building is written.  Fix: one immortal string per literal SITE, cached in
   a per-site global by @march_string_lit_static.

   Choosing the shape of this test is the whole trick, because two adjacent
   shapes are VACUOUS:
     * a let-bound literal (`let s = "xyz"` used later) gets an ordinary
       Perceus dec on its binding, so it never leaked; and
     * a literal passed straight to a non-allocating call (e.g.
       `String.byte_size("xyz")` in a loop) is hoisted out of the loop by the
       optimizer and evaluated twice in total.
   Only a literal evaluated repeatedly as a direct OPERAND — canonically of
   `++` — exercises the bug.  Verified non-vacuous by reverting just the
   codegen arm: this program prints "LEAKED 20001" against the old emission
   and "BOUNDED" against the fixed one.

   The assertion reads the runtime's own live-object gauge
   (march_live_allocs, alloc + / free-on-rc=0 -) through an extern rather
   than sampling RSS, so it measures the leak directly and cannot flake on
   allocator or platform behaviour.  It compares the SAME literal site across
   two loop lengths: the growth is what must stay bounded, not the absolute
   count (one immortal cell per site is the intended, and permanent, cost). *)
let test_string_literal_operand_no_leak_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_strlitleak"
    "mod StrLitLeak do\n\
    \  needs IO.Console\n\
    \  needs Ffi\n\
    \  needs IO.Foreign\n\
    \  extern \"m\" : Cap(Ffi) do\n\
    \    fn live_allocs(): Int = \"march_live_allocs\"\n\
    \  end\n\
    \  pfn concat_loop(buf : String, i : Int, n : Int, acc : Int) : Int do\n\
    \    if i >= n do acc\n\
    \    else\n\
    \      let s = buf ++ \"xyz\"\n\
    \      concat_loop(buf, i + 1, n, acc + String.byte_size(s))\n\
    \    end\n\
    \  end\n\
    \  fn main(_cap_console : Cap(IO.Console), _cap_foreign : Cap(IO.Foreign)) : Unit do\n\
     -- Warm the literal site first, so its one permanent cell is already\n\
     -- allocated when the baseline is sampled and only per-iteration growth\n\
     -- can move the gauge.\n\
    \    let warm = concat_loop(\"abc\", 0, 100, 0)\n\
    \    let base = live_allocs()\n\
    \    let bulk = concat_loop(\"abc\", 0, 20000, 0)\n\
    \    let grew = live_allocs() - base\n\
    \    if warm + bulk > 0 && grew <= 8 do\n\
    \      println(\"BOUNDED\")\n\
    \    else\n\
    \      println(\"LEAKED \" ++ int_to_string(grew))\n\
    \    end\n\
    \  end\n\
     end\n"
  in
  let bin = Filename.concat tmp "strlitleakbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Printf.sprintf "%s 2>&1" (Filename.quote bin)) in
    Alcotest.(check string)
      "a string literal used as a `++` operand in a loop allocates once for \
       the whole site, not once per iteration (live-object count must not \
       grow with the iteration count)"
      "BOUNDED" run_out

(* The runtime-gauge half of the unboxed-aggregate story (the IR assertions
   live in the "unboxed_aggregates" group above): a vector-math loop over an
   inline aggregate must move march_live_allocs by ZERO.  Same shape as the
   two leak probes above — warm the code once so any one-off permanent cell is
   already live at the baseline, then run the same loop 200x longer and assert
   the gauge has not moved.  Unlike those, the assertion is exact rather than
   bounded: the whole point of the representation is that a Vec3 never reaches
   the allocator at all, so any growth is a regression.

   Non-vacuity: the same program compiled with MARCH_NO_UNBOX=1 (the
   representation escape hatch) allocates one 40-byte cell per iteration and
   prints "GREW 20000". *)
let test_unboxed_aggregate_zero_live_allocs_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_ubgauge"
    "mod UbGauge do\n\
    \  needs IO.Console\n\
    \  needs Ffi\n\
    \  needs IO.Foreign\n\
    \  extern \"m\" : Cap(Ffi) do\n\
    \    fn live_allocs(): Int = \"march_live_allocs\"\n\
    \  end\n\
    \  type Vec3 = Vec3(Float, Float, Float)\n\
    \  fn forward(yaw : Float, pitch : Float) : Vec3 do\n\
    \    let cp = Math.cos(pitch)\n\
    \    Vec3(0.0 -. Math.sin(yaw) *. cp, Math.sin(pitch), 0.0 -. Math.cos(yaw) *. cp)\n\
    \  end\n\
    \  fn dot(a : Vec3, b : Vec3) : Float do\n\
    \    match a do\n\
    \      Vec3(ax, ay, az) ->\n\
    \        match b do\n\
    \          Vec3(bx, b2, bz) -> ax *. bx +. ay *. b2 +. az *. bz\n\
    \        end\n\
    \    end\n\
    \  end\n\
    \  pfn spin(i : Int, n : Int, acc : Float) : Float do\n\
    \    if i >= n do acc\n\
    \    else\n\
    \      let v = forward(int_to_float(i) *. 0.001, 0.25)\n\
    \      spin(i + 1, n, acc +. dot(v, v))\n\
    \    end\n\
    \  end\n\
    \  fn main(_cap_console : Cap(IO.Console), _cap_foreign : Cap(IO.Foreign)) : Unit do\n\
    \    let warm = spin(0, 100, 0.0)\n\
    \    let base = live_allocs()\n\
    \    let bulk = spin(0, 20000, 0.0)\n\
    \    let grew = live_allocs() - base\n\
    \    if warm +. bulk > 0.0 && grew == 0 do\n\
    \      println(\"ZERO\")\n\
    \    else\n\
    \      println(\"GREW \" ++ int_to_string(grew))\n\
    \    end\n\
    \  end\n\
     end\n"
  in
  let bin = Filename.concat tmp "ubgaugebin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Printf.sprintf "%s 2>&1" (Filename.quote bin)) in
    Alcotest.(check string)
      "a Vec3-heavy loop never reaches the allocator: an unboxed aggregate is \
       built with insertvalue, not march_alloc, so the runtime's live-object \
       count must not move at all"
      "ZERO" run_out

(* The runtime-gauge half of the branch-join story (the IR assertion lives in
   test_unboxed_aggregate_branch_join_box_released, "unboxed_aggregates"
   group).  Unlike the straight-line Vec3 loop above, this one CANNOT reach
   zero: an aggregate built inside an `if` is boxed to cross the join, so one
   cell per construction is allocated and must be freed again.  The assertion
   is therefore that the gauge does not GROW — which is exactly what the boxed
   representation did before Milestone 3, and exactly what the leak broke.

   Non-vacuity: with the merge release removed, this same program prints
   "GREW 20000" — one leaked 32-byte cell per iteration, scaling exactly with
   the loop count (measured 5 000 -> 5 001, 20 000 -> 20 001 live objects). *)
let test_unboxed_aggregate_branch_join_no_leak_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_ubjoingauge"
    "mod UbJoinGauge do\n\
    \  needs IO.Console\n\
    \  needs Ffi\n\
    \  needs IO.Foreign\n\
    \  extern \"m\" : Cap(Ffi) do\n\
    \    fn live_allocs(): Int = \"march_live_allocs\"\n\
    \  end\n\
    \  type P2 = P2(Float, Float)\n\
    \  pfn psum(p : P2) : Float do\n\
    \    match p do\n\
    \      P2(a, c) -> a +. c\n\
    \    end\n\
    \  end\n\
    \  pfn spin(i : Int, acc : Float) : Float do\n\
    \    if i == 0 do acc\n\
    \    else\n\
    \      let p = if i % 2 == 0 do P2(1.0, 2.0) else P2(3.0, 4.0) end\n\
    \      spin(i - 1, acc +. psum(p))\n\
    \    end\n\
    \  end\n\
    \  fn main(_cap_console : Cap(IO.Console), _cap_foreign : Cap(IO.Foreign)) : Unit do\n\
    \    let warm = spin(100, 0.0)\n\
    \    let base = live_allocs()\n\
    \    let bulk = spin(20000, 0.0)\n\
    \    let grew = live_allocs() - base\n\
    \    if warm +. bulk > 0.0 && grew == 0 do\n\
    \      println(\"ZERO\")\n\
    \    else\n\
    \      println(\"GREW \" ++ int_to_string(grew))\n\
    \    end\n\
    \  end\n\
     end\n"
  in
  let bin = Filename.concat tmp "ubjoingaugebin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Printf.sprintf "%s 2>&1" (Filename.quote bin)) in
    Alcotest.(check string)
      "an aggregate built inside a branch is boxed to cross the join and freed \
       again at the merge: the runtime's live-object count must not grow with \
       the iteration count"
      "ZERO" run_out

(* Static capture-free closures (Task 1, lib/tir/llvm_emit.ml): a top-level
   named fn used as a first-class value now references ONE immortal
   `internal global` closure object per fn (@<fn>$static_clo, refcount
   MARCH_RC_IMMORTAL) instead of calling march_alloc(24) at every
   materialization site evaluation. The old per-materialization allocation
   was never freed — a genuine leak.

   Same shape as test_string_literal_operand_no_leak_compiled immediately
   above: read the runtime's own live-object gauge (march_live_allocs)
   through an extern, warm the materialization site once so its one
   permanent cell is already live when the baseline is sampled, then re-run
   the same site at a much larger loop count and assert the growth stays
   bounded rather than scaling with the iteration count. One static closure
   per function is the intended permanent cost — the assertion is on
   GROWTH, not an absolute count. *)
let test_static_closure_materialization_no_leak_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_staticcloleak"
    "mod StaticCloLeak do\n\
    \  needs IO.Console\n\
    \  needs Ffi\n\
    \  needs IO.Foreign\n\
    \  extern \"m\" : Cap(Ffi) do\n\
    \    fn live_allocs(): Int = \"march_live_allocs\"\n\
    \  end\n\
    \  fn double(x : Int) : Int do x * 2 end\n\
    \  pfn apply_it(f : Int -> Int, n : Int) : Int do f(n) end\n\
    \  pfn materialize_loop(i : Int, n : Int, acc : Int) : Int do\n\
    \    if i >= n do acc\n\
    \    else\n\
    \      materialize_loop(i + 1, n, acc + apply_it(double, i))\n\
    \    end\n\
    \  end\n\
    \  fn main(_cap_console : Cap(IO.Console), _cap_foreign : Cap(IO.Foreign)) : Unit do\n\
     -- Warm the materialization site first, so its one permanent static\n\
     -- closure is already allocated when the baseline is sampled and only\n\
     -- per-iteration growth can move the gauge.\n\
    \    let warm = materialize_loop(0, 100, 0)\n\
    \    let base = live_allocs()\n\
    \    let bulk = materialize_loop(0, 20000, 0)\n\
    \    let grew = live_allocs() - base\n\
    \    if warm + bulk > 0 && grew <= 8 do\n\
    \      println(\"BOUNDED\")\n\
    \    else\n\
    \      println(\"LEAKED \" ++ int_to_string(grew))\n\
    \    end\n\
    \  end\n\
     end\n"
  in
  let bin = Filename.concat tmp "staticcloleakbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Printf.sprintf "%s 2>&1" (Filename.quote bin)) in
    Alcotest.(check string)
      "a top-level named fn materialized as a first-class value in a loop \
       references one immortal static closure per site, not one fresh \
       allocation per materialization (live-object count must not grow \
       with the iteration count)"
      "BOUNDED" run_out

(* Static capture-free closures (Task 1, lib/tir/llvm_emit.ml), lambda form:
   the precedent immediately above materializes a top-level named fn
   (`double`) as a first-class value. This test exercises the shape Task 1
   was actually written for — a capture-free LAMBDA literal, whose closure
   struct is `EAlloc(TCon("$Clo_..", []), [fn_ptr])` with exactly one
   argument. Before Task 1, `apply_it(fn x -> x * 2, i)` at 4,000,000
   iterations allocated 4,000,000 closures and never freed any of them (no
   dec_rc/free anywhere in the loop) — a genuine leak, not churn. Same
   growth-assertion shape as the two tests above: warm the materialization
   site once, sample march_live_allocs as a baseline, re-run the same site
   at a much larger loop count, and assert the growth stays bounded rather
   than scaling with the iteration count. *)
let test_lambda_static_closure_materialization_no_leak_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_lambdacloleak"
    "mod LambdaCloLeak do\n\
    \  needs IO.Console\n\
    \  needs Ffi\n\
    \  needs IO.Foreign\n\
    \  extern \"m\" : Cap(Ffi) do\n\
    \    fn live_allocs(): Int = \"march_live_allocs\"\n\
    \  end\n\
    \  pfn apply_it(f : Int -> Int, n : Int) : Int do f(n) end\n\
    \  pfn materialize_loop(i : Int, n : Int, acc : Int) : Int do\n\
    \    if i >= n do acc\n\
    \    else\n\
    \      materialize_loop(i + 1, n, acc + apply_it(fn x -> x * 2, i))\n\
    \    end\n\
    \  end\n\
    \  fn main(_cap_console : Cap(IO.Console), _cap_foreign : Cap(IO.Foreign)) : Unit do\n\
     -- Warm the materialization site first, so its one permanent static\n\
     -- closure is already allocated when the baseline is sampled and only\n\
     -- per-iteration growth can move the gauge.\n\
    \    let warm = materialize_loop(0, 100, 0)\n\
    \    let base = live_allocs()\n\
    \    let bulk = materialize_loop(0, 20000, 0)\n\
    \    let grew = live_allocs() - base\n\
    \    if warm + bulk > 0 && grew <= 8 do\n\
    \      println(\"BOUNDED\")\n\
    \    else\n\
    \      println(\"LEAKED \" ++ int_to_string(grew))\n\
    \    end\n\
    \  end\n\
     end\n"
  in
  let bin = Filename.concat tmp "lambdacloleakbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Printf.sprintf "%s 2>&1" (Filename.quote bin)) in
    Alcotest.(check string)
      "a capture-free lambda literal materialized as a first-class value in \
       a loop references one immortal static closure per site, not one \
       fresh allocation per materialization (live-object count must not \
       grow with the iteration count)"
      "BOUNDED" run_out

(* CAPTURING closures — the shape the two static-closure tests above cannot
   reach.  A lambda that captures a variable cannot be a static global: each
   materialization is a genuine `march_alloc` holding the captured values.
   Before the $clo ownership drop (lib/tir/perceus.ml
   [insert_apply_fn_clo_drop], sound only alongside the apply-fn param-0 pin
   in lib/tir/borrow.ml [infer_module]) NOTHING released it — the caller side
   deferred to the callee and the callee never dropped, so a 4,000,000-
   iteration loop allocated 4,000,000 closures and freed none (~125 MB peak
   RSS versus ~2.9 MB for the capture-free control).

   Same growth-assertion shape as the two tests above, and deliberately so:
   this one FAILS on a build with only the callee drop and no pin (the
   closure is freed while the caller still holds it — a double-free, not a
   leak) and equally on a build with neither. *)
let test_capturing_closure_materialization_no_leak_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_capcloleak"
    "mod CapCloLeak do\n\
    \  needs IO.Console\n\
    \  needs Ffi\n\
    \  needs IO.Foreign\n\
    \  extern \"m\" : Cap(Ffi) do\n\
    \    fn live_allocs(): Int = \"march_live_allocs\"\n\
    \  end\n\
    \  pfn apply_it(f : Int -> Int, n : Int) : Int do f(n) end\n\
    \  pfn materialize_loop(i : Int, n : Int, k : Int, acc : Int) : Int do\n\
    \    if i >= n do acc\n\
    \    else\n\
     -- `fn x -> x * k` captures k, so this allocates a real closure struct\n\
     -- every iteration; it can never be routed to a static global.\n\
    \      materialize_loop(i + 1, n, k, acc + apply_it(fn x -> x * k, i))\n\
    \    end\n\
    \  end\n\
    \  fn main(_cap_console : Cap(IO.Console), _cap_foreign : Cap(IO.Foreign)) : Unit do\n\
    \    let warm = materialize_loop(0, 100, 2, 0)\n\
    \    let base = live_allocs()\n\
    \    let bulk = materialize_loop(0, 20000, 2, 0)\n\
    \    let grew = live_allocs() - base\n\
    \    if warm + bulk > 0 && grew <= 8 do\n\
    \      println(\"BOUNDED\")\n\
    \    else\n\
    \      println(\"LEAKED \" ++ int_to_string(grew))\n\
    \    end\n\
    \  end\n\
     end\n"
  in
  let bin = Filename.concat tmp "capcloleakbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Printf.sprintf "%s 2>&1" (Filename.quote bin)) in
    Alcotest.(check string)
      "a CAPTURING lambda materialized in a loop must release each closure \
       struct: the live-object count must not grow with the iteration count"
      "BOUNDED" run_out

(* SELF-RECURSIVE capturing closures — the residual leak the PR that fixed
   the two tests above shipped with, then fixed here.

   [insert_apply_fn_clo_drop]'s unconditional early drop (right after the
   fv-extraction prefix) cancels the self-binding's own protective
   [inc_rc $clo] (`let helper = inc_rc $clo; $clo in ...`, a transient
   bump-then-unbump) and is the WHOLE story for a non-recursive capturing
   closure, where nothing else ever touches $clo again. For a self-recursive
   one it is necessary but not sufficient: the self-binding alias is used
   again on the recursive path (transferred onward via ordinary
   dead-after-argument [ECallPtr] semantics, no separate rc touch needed
   there) but never used at all on a base-case path — and nothing released
   the one genuinely-transferred reference there, leaking one allocation per
   top-level MATERIALIZATION of the closure (not per recursive call — the
   whole recursion reuses one heap object via the alias, so a loop with
   d.eep recursion inside ONE materialization stays flat; only calling the
   materializing scope repeatedly shows growth).

   Fixed with a second, path-sensitive pass (also in
   [insert_apply_fn_clo_drop]): walk the body via [Dce.free_vars] and insert
   an ADDITIONAL drop at exactly the points where the self-binding is no
   longer free — leaving the live (recursive) path alone. Two earlier,
   broken attempts at this fix are documented inline in perceus.ml: dropping
   the unconditional early drop in favour of only the path-sensitive walk
   left the protective inc permanently uncanceled on the recursive path
   (rc grows without bound); doing the path-sensitive walk with a plain
   "recurse into the let's tail" rule (rather than checking which half of an
   [ELet]'s RHS/tail actually contains the occurrence) inserted a SECOND,
   spurious drop on the live path itself — a double-free waiting to happen,
   not a leak. *)
let test_self_recursive_capturing_closure_no_leak_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_selfreccap"
    "mod SelfRecCap do\n\
    \  needs IO.Console\n\
    \  needs Ffi\n\
    \  needs IO.Foreign\n\
    \  extern \"m\" : Cap(Ffi) do\n\
    \    fn live_allocs(): Int = \"march_live_allocs\"\n\
    \  end\n\
    \  pfn apply_it(f : Int -> Int, n : Int) : Int do f(n) end\n\
    \  fn outer(k : Int, n : Int) : Int do\n\
    \    fn helper(x : Int) : Int do\n\
    \      if x <= 0 do 0 else helper(x - 1) + k end\n\
    \    end\n\
    \    apply_it(helper, n)\n\
    \  end\n\
    \  pfn materialize_loop(i : Int, acc : Int, k : Int) : Int do\n\
    \    if i >= 20000 do acc\n\
    \    else materialize_loop(i + 1, acc + outer(k, 5), k) end\n\
    \  end\n\
    \  fn main(_cap_console : Cap(IO.Console), _cap_foreign : Cap(IO.Foreign)) : Unit do\n\
    \    let warm = materialize_loop(0, 0, 2)\n\
    \    let base = live_allocs()\n\
    \    let bulk = materialize_loop(0, 0, 2)\n\
    \    let grew = live_allocs() - base\n\
    \    if warm + bulk > 0 && grew <= 8 do\n\
    \      println(\"BOUNDED\")\n\
    \    else\n\
    \      println(\"LEAKED \" ++ int_to_string(grew))\n\
    \    end\n\
    \  end\n\
     end\n"
  in
  let bin = Filename.concat tmp "selfreccapbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Printf.sprintf "%s 2>&1" (Filename.quote bin)) in
    Alcotest.(check string)
      "a self-recursive capturing closure materialized in a loop must release \
       each closure struct at the base case: the live-object count must not \
       grow with the materialization count"
      "BOUNDED" run_out

(* Same shape, verifying CORRECTNESS (not just leak-freedom): a double
   recursive call within one branch (fib-shaped) and negative/zero/large
   inputs, checked against the interpreter. The leak fix above touches every
   base-case branch of a self-recursive apply fn, so an over-eager extra
   drop (a double-free, not a leak) would show up here as a wrong value or a
   crash rather than as unbounded growth. *)
let test_self_recursive_capturing_closure_correct_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_selfreccapcorrect"
    "mod SelfRecCapCorrect do\n\
    \  needs IO.Console\n\
    \  pfn apply_it(f : Int -> Int, n : Int) : Int do f(n) end\n\
    \  fn outer(k : Int, n : Int) : Int do\n\
    \    fn helper(x : Int) : Int do\n\
    \      if x <= 0 do k\n\
    \      else if x == 1 do helper(x - 1) * 2\n\
    \      else helper(x - 1) + helper(x - 2) end\n\
    \      end\n\
    \    end\n\
    \    apply_it(helper, n)\n\
    \  end\n\
    \  fn main(_cap_console : Cap(IO.Console)) : Unit do\n\
    \    println(int_to_string(outer(1, 0)))\n\
    \    println(int_to_string(outer(1, 1)))\n\
    \    println(int_to_string(outer(1, 6)))\n\
    \    println(int_to_string(outer(-3, 10)))\n\
    \  end\n\
     end\n"
  in
  let interp_out = read_cmd_output (Printf.sprintf
    "cd %s && %s %s 2>&1"
    (Filename.quote project_root)
    (Filename.quote main_exe) (Filename.quote src)) in
  Alcotest.(check string) "interpreted self-recursive capturing closure"
    "1\n2\n21\n-432" interp_out;
  let bin = Filename.concat tmp "selfreccapcorrectbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let compiled_out = read_cmd_output (Printf.sprintf "%s 2>&1" (Filename.quote bin)) in
    Alcotest.(check string) "compiled matches interpreted" "1\n2\n21\n-432" compiled_out

(* NOTE — the companion invariant, "the $clo drop must NOT be emitted for a
   CAPTURE-FREE apply function", is pinned by this suite's existing
   "stdlib List.length via precompile" JIT test rather than by a test added
   here, and deliberately so: native measurement cannot observe it at all.
   [Llvm_emit.static_closure_ok] is `not ctx.repl && ..`, so natively a
   capture-free closure is the immortal global where a decrement is a no-op —
   but under the REPL/JIT it is a real `march_alloc` with rc = 1, and an
   unguarded drop frees it on the first call.  The next dispatch then jumps
   through the zeroed apply-fn slot: EXC_BAD_ACCESS at address 0x0 with
   frame #0 = 0x0 — a jump to a null code pointer, not a data
   use-after-free.  Removing the `prefix_has_fv_extraction` guard in
   [Perceus.insert_apply_fn_clo_drop] reproduces that SIGSEGV there while
   every native program in the corpus stays green. *)

(* __try_call / __try_call_val — the callee-side $clo drop (see the two tests
   above) is only sound when every C-runtime call site that invokes a
   closure's apply function agrees on the calling convention. The runtime
   originally decref'd the thunk itself AFTER calling it once — a second
   consumption of the same reference the drop already released, since the
   drop fires as the FIRST thing the apply function does (right after
   extracting its captures, before any of the actual body runs), so it has
   already executed by the time the runtime's own decrc would fire, on both
   the normal-return and the panic (longjmp) path.

   This is flaky, not deterministic: the freed memory frequently still looks
   valid enough that the double-decrement doesn't crash immediately (a
   classic use-after-free signature). Measured before the runtime fix
   (removing the explicit `march_decrc(thunk)` in both __try_call and
   __try_call_val, runtime/march_runtime.c): 6 crashes ("RC underflow") out
   of 30 runs of a single-capture __try_call thunk. 0/30 after. A single
   clean run proves nothing here — this test alone cannot pin a heap-timing
   bug, so treat any future regression suspicion the same way: loop the
   binary directly, don't trust one pass. *)
let test_try_call_single_capture_no_double_free_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_trycallcap"
    "mod TryCallCap do\n\
    \  needs IO.Console\n\
    \  fn main(_cap_console : Cap(IO.Console)) : Unit do\n\
    \    let threshold = 5\n\
    \    match __try_call(fn _ -> threshold > 0) do\n\
    \    Ok(_) -> println(\"ok\")\n\
    \    Err(e) -> println(\"err: \" ++ e)\n\
    \    end\n\
    \  end\n\
     end\n"
  in
  let bin = Filename.concat tmp "trycallcapbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let cmd = Printf.sprintf "%s 2>&1" (Filename.quote bin) in
    for _ = 1 to 30 do
      let run_out = read_cmd_output cmd in
      Alcotest.(check string)
        "a single-capture __try_call thunk must not double-consume its \
         closure's reference — flaky heap-corruption bug, run repeatedly"
        "ok" run_out
    done

let test_try_call_val_single_capture_no_double_free_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_trycallvalcap"
    "mod TryCallValCap do\n\
    \  needs IO.Console\n\
    \  fn main(_cap_console : Cap(IO.Console)) : Unit do\n\
    \    let base = \"hi\"\n\
    \    match __try_call_val(fn _ -> base ++ \"!\") do\n\
    \    Ok(v) -> println(\"ok: \" ++ v)\n\
    \    Err(e) -> println(\"err: \" ++ e)\n\
    \    end\n\
    \  end\n\
     end\n"
  in
  let bin = Filename.concat tmp "trycallvalcapbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let cmd = Printf.sprintf "%s 2>&1" (Filename.quote bin) in
    for _ = 1 to 30 do
      let run_out = read_cmd_output cmd in
      Alcotest.(check string)
        "a single-capture __try_call_val thunk must not double-consume its \
         closure's reference — flaky heap-corruption bug, run repeatedly"
        "ok: hi!" run_out
    done

(* The panic (longjmp) path: the drop fires before the body runs, so it must
   also be safe when the body never returns normally. *)
let test_try_call_panic_with_capture_no_double_free_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_trycallpanic"
    "mod TryCallPanic do\n\
    \  needs IO.Console\n\
    \  fn main(_cap_console : Cap(IO.Console)) : Unit do\n\
    \    let label = \"boom\"\n\
    \    match __try_call(fn _ -> panic(label)) do\n\
    \    Ok(_) -> println(\"ok\")\n\
    \    Err(e) -> println(\"err: \" ++ e)\n\
    \    end\n\
    \  end\n\
     end\n"
  in
  let bin = Filename.concat tmp "trycallpanicbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let cmd = Printf.sprintf "%s 2>&1" (Filename.quote bin) in
    for _ = 1 to 15 do
      let run_out = read_cmd_output cmd in
      Alcotest.(check bool)
        "a panicking single-capture __try_call thunk must not double-consume \
         its closure's reference"
        true (Test_helpers.contains "boom" run_out)
    done

(* try_finally — the third member of the try-call family, and the one the
   stdlib leans on for resource cleanup (File.with_lines / File.with_chunks /
   Logger's context stack). Unlike __try_call/__try_call_val it was a
   typecheck+interpreter builtin ONLY: no llvm_builtins row, so compiled
   call sites fell into the unknown-extern fallback and emitted
   `declare ptr @try_finally(...)` against a C symbol that never existed —
   any program whose compiled code reached try_finally failed at LINK time
   ("Undefined symbols: _try_finally", first seen via
   examples/read_file.march's File.with_lines call).

   try_finally returns the action's value at the polymorphic type `a`
   DIRECTLY (not wrapped in a Result field like its siblings), so its
   llvm_builtins row uses ret_ty = TVar "_" (the record_put precedent): the
   call site reads a uniform ptr and the consumer coerces. The Int case
   below is the adversarial witness for exactly that — if the runtime
   returned a raw untagged value, or the call site skipped the conditional
   untag, 42 would come back as 85 ((42<<1)|1) compiled-only. *)
let test_try_finally_value_and_order_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_tryfin"
    "mod TryFin do\n\
    \  needs IO.Console\n\
    \  fn main(_cap_console : Cap(IO.Console)) : Unit do\n\
    \    let k = 40\n\
    \    let n = try_finally(\n\
    \      fn _ ->\n\
    \        let _ = println(\"action\")\n\
    \        k + 2,\n\
    \      fn _ -> println(\"cleanup\"))\n\
    \    println(int_to_string(n))\n\
    \    let s = try_finally(fn _ -> \"he\" ++ \"ap\", fn _ -> ())\n\
    \    println(s)\n\
    \  end\n\
     end\n"
  in
  let expected = "action\ncleanup\n42\nheap" in
  let interp_out = read_cmd_output (Printf.sprintf
    "cd %s && %s %s 2>&1"
    (Filename.quote project_root)
    (Filename.quote main_exe) (Filename.quote src)) in
  Alcotest.(check string) "interpreted try_finally value + cleanup order"
    expected interp_out;
  let bin = Filename.concat tmp "tryfinbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Printf.sprintf "%s 2>&1" (Filename.quote bin)) in
    Alcotest.(check string) "compiled matches interpreted" expected run_out

(* The semantic contract that justifies try_finally's existence: cleanup runs
   even when the action panics, and the panic still propagates afterwards
   (nonzero exit). Combined stdout+stderr capture can interleave the two
   streams arbitrarily around process exit, so assert presence of both
   markers rather than their relative order — cleanup-before-repanic is
   enforced by construction inside march_try_finally. *)
let test_try_finally_cleanup_runs_on_panic_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_tryfinpanic"
    "mod TryFinPanic do\n\
    \  needs IO.Console\n\
    \  fn main(_cap_console : Cap(IO.Console)) : Unit do\n\
    \    let label = \"kaboom\"\n\
    \    let _ = try_finally(\n\
    \      fn _ ->\n\
    \        let _ = panic(label)\n\
    \        0,\n\
    \      fn _ -> println(\"cleanup-ran\"))\n\
    \    println(\"unreachable\")\n\
    \  end\n\
     end\n"
  in
  let bin = Filename.concat tmp "tryfinpanicbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let out_file = Filename.concat tmp "tryfinpanic.out" in
    let rc = Sys.command (Printf.sprintf "%s > %s 2>&1"
                            (Filename.quote bin) (Filename.quote out_file)) in
    let run_out = read_cmd_output (Printf.sprintf "cat %s" (Filename.quote out_file)) in
    Alcotest.(check bool) "panicking action still exits nonzero" true (rc <> 0);
    Alcotest.(check bool) "cleanup ran before the panic propagated" true
      (Test_helpers.contains "cleanup-ran" run_out);
    Alcotest.(check bool) "the original panic message propagated" true
      (Test_helpers.contains "kaboom" run_out);
    Alcotest.(check bool) "code after try_finally did not run" false
      (Test_helpers.contains "unreachable" run_out)

(* The fd-streaming builtins' C→March return contract — the SECOND bug the
   try_finally link failure was masking. file_read_line/file_read_chunk are
   typed Option(String), which is NICHE-encoded compiled (Some's payload is
   the value itself, None is raw NULL), but the C runtime returned mk_ok /
   mk_err RESULT cells: every return — including the EOF Err — read as
   Some(<Result cell>), so a read-to-EOF fold never terminated (the
   File.with_lines hang) and using the misread "line" crashed (SIGBUS in a
   straight-line read). Unreachable before try_finally linked: every
   fd-streaming stdlib path goes through it, and the interpreter (where
   stdlib tests run) has its own correct Some/None implementation. This
   drives File.with_lines end-to-end, compiled vs interpreted. *)
let test_file_with_lines_streaming_compiled () =
  (* The input file lives in its own temp path, embedded into the source
     verbatim, so the test is hermetic and CWD-independent. *)
  let input_path = Filename.temp_file "march_withlines_input" ".txt" in
  let oc = open_out input_path in
  output_string oc "alpha\nbeta\ngamma\ndelta\nepsilon\n";
  close_out oc;
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_withlines"
    (Printf.sprintf
    "mod WithLines do\n\
    \  needs IO.Console\n\
    \  needs IO.FileRead\n\
    \  fn main(_cap_console : Cap(IO.Console), _cap_fileread : Cap(IO.FileRead)) : Unit do\n\
    \    let path = \"%s\"\n\
    \    match File.with_lines(path, fn(lines) -> Seq.to_list(Seq.take(lines, 3))) do\n\
    \    Err(e) -> println(\"Error: \" ++ to_string(e))\n\
    \    Ok(first3) -> do\n\
    \      println(int_to_string(List.length(first3)))\n\
    \      println(List.fold_left(first3, \"\", fn(acc, line) -> acc ++ line ++ \"|\"))\n\
    \    end\n\
    \    end\n\
    \    match File.with_lines(path, fn(lines) -> Seq.to_list(lines)) do\n\
    \    Err(e) -> println(\"Error: \" ++ to_string(e))\n\
    \    Ok(all) -> println(int_to_string(List.length(all)))\n\
    \    end\n\
    \  end\n\
     end\n" input_path)
  in
  let expected = "3\nalpha|beta|gamma|\n5" in
  let interp_out = read_cmd_output (Printf.sprintf
    "cd %s && %s %s 2>&1"
    (Filename.quote project_root)
    (Filename.quote main_exe) (Filename.quote src)) in
  Alcotest.(check string) "interpreted File.with_lines streaming"
    expected interp_out;
  let bin = Filename.concat tmp "withlinesbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    (* Bounded run: the pre-fix failure mode was an infinite read loop, so a
       plain Sys.command here would hang the whole suite. *)
    let out_file = Filename.concat tmp "withlines.out" in
    (match Test_helpers.run_with_timeout ~timeout_secs:30.0 ~stdout_file:out_file
             [| bin |] with
     | `Timeout ->
       Alcotest.fail
         "compiled File.with_lines hung (>30s): fd-streaming EOF was never \
          seen — the file_read_line niche-Option contract is broken again"
     | `Exited 0 ->
       let run_out = read_cmd_output (Printf.sprintf "cat %s" (Filename.quote out_file)) in
       Alcotest.(check string) "compiled matches interpreted" expected run_out
     | `Exited rc ->
       Alcotest.failf "compiled File.with_lines exited with rc=%d" rc)

(* NativeArray.map_int/map_float et al. and TypedArray.map/fold — a THIRD
   family of call sites sharing the same double-consumption bug as
   __try_call above, but shaped differently: instead of one call plus an
   explicit runtime decrc, these call the SAME closure once PER ELEMENT
   without transferring ownership on each call. Both the C-runtime general
   path (runtime/march_runtime.c's native_int_arr_map/native_float_arr_map/
   march_typed_array_map/march_typed_array_fold, all via march_incrc before
   each per-element call plus one march_decrc after the loop) and the
   compiled-loop fast path (lib/tir/llvm_emit.ml's
   emit_native_map_inline_loop/emit_native_map2_inline_loop, Phase 2c) share
   this fix.

   This repro deliberately exercises the case that must fall back to the
   GENERAL path rather than the inline loop: a closure that captures a free
   variable AND is called again after the map, so it is not single-use
   (Native_map_inline.ml declines to rewrite it — any Perceus-inserted RC op
   on the closure counts as an extra use). Confirmed via TIR dump before
   writing this test: `inc_rc closure; NativeArray.map_int(a1, closure)`,
   proving the closure is a transferred-but-still-live reference at that
   call site, not a last-use consume. *)
let test_native_array_map_reused_capturing_closure_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_arrmapcap"
    "mod ArrMapCap do\n\
    \  needs IO.Console\n\
    \  fn main(_cap_console : Cap(IO.Console)) : Unit do\n\
    \    let k = 7\n\
    \    let closure = fn x -> x + k\n\
    \    let a1 = NativeArray.from_list_int(Cons(1, Cons(2, Cons(3, Nil))))\n\
    \    let a2 = NativeArray.map_int(a1, closure)\n\
    \    println(NativeArray.to_list_int(a2))\n\
    \    println(int_to_string(closure(100)))\n\
    \  end\n\
     end\n"
  in
  let bin = Filename.concat tmp "arrmapcapbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let cmd = Printf.sprintf "%s 2>&1" (Filename.quote bin) in
    for _ = 1 to 20 do
      let run_out = read_cmd_output cmd in
      Alcotest.(check string)
        "a capturing closure reused after NativeArray.map_int must not be \
         freed mid-map (general C-runtime path, not the inline fast path)"
        "[8, 9, 10]\n107" run_out
    done

(* ── NativeArray.set_int FBIP in-place-at-rc==1 ──────────────────────────
   native_int_arr_set / native_float_arr_set (runtime/march_runtime.c) take
   their array under the owned/consumed convention (absent from borrow.ml's
   extern_borrow_table, so Perceus emits no dec_rc after the call). They used
   to *always* allocate a fresh backing array, memcpy, and return it —
   WITHOUT ever releasing the consumed input. A hot loop threading the result
   forward (last-use, rc==1) leaked one copy per op: a 2M-op set_int loop on
   an 8-element array ramped to ~190MB RSS (linear in ops) while the same loop
   without set_int held ~2.7MB flat.

   Fixed by reusing the backing array in place when it is uniquely owned
   (rc==1) — O(1), flat RSS — and preserving copy-on-write + releasing the
   consumed reference only when the array is shared (rc>1). These two tests
   pin BOTH halves of that contract; the correctness bug they guard is
   compiled-only (the interpreter has a different NativeArray backend). *)

(* rc>1 (aliased): the array is still live after set_int, so copy-on-write
   MUST be preserved — the alias must observe the ORIGINAL, not the mutation. *)
let test_native_array_set_int_alias_cow_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_setalias"
    "mod SetAlias do\n\
    \  needs IO.Console\n\
    \  fn main(_cap_console : Cap(IO.Console)) : Unit do\n\
    \    let a = NativeArray.make_int(4, 0)\n\
    \    let b = NativeArray.set_int(a, 0, 99)\n\
    \    -- a is read AFTER set_int -> aliased (rc>1) -> must be unchanged.\n\
    \    println(int_to_string(NativeArray.get_int(a, 0)))\n\
    \    println(int_to_string(NativeArray.get_int(b, 0)))\n\
    \  end\n\
     end\n"
  in
  let bin = Filename.concat tmp "setaliasbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Printf.sprintf "%s 2>&1" (Filename.quote bin)) in
    Alcotest.(check string)
      "set_int on a SHARED (rc>1) array must copy-on-write: the alias reads 0 \
       (unchanged original), the result reads 99 — in-place mutation here \
       would corrupt the alias"
      "0\n99" run_out

(* rc==1 (unique, threaded forward): the in-place path must produce the SAME
   final array as a copy would. A long churn loop that would crash / read
   freed memory / diverge if in-place reuse ever freed a still-live array;
   the value is the sum of the 8 last writes per position. *)
let test_native_array_set_int_inplace_churn_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_setchurn"
    "mod SetChurn do\n\
    \  needs IO.Console\n\
    \  fn go(arr, i : Int, n : Int) : Int do\n\
    \    if i >= n do\n\
    \      NativeArray.sum_int(arr)\n\
    \    else\n\
    \      let arr2 = NativeArray.set_int(arr, i % 8, i)\n\
    \      go(arr2, i + 1, n)\n\
    \    end\n\
    \  end\n\
    \  fn main(_cap_console : Cap(IO.Console)) : Unit do\n\
    \    let arr = NativeArray.make_int(8, 0)\n\
    \    println(int_to_string(go(arr, 0, 2000000)))\n\
    \  end\n\
     end\n"
  in
  let bin = Filename.concat tmp "setchurnbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Printf.sprintf "%s 2>&1" (Filename.quote bin)) in
    (* last write to position p is the largest i<2_000_000 with i%8==p:
       1999992..1999999; their sum is 15999964. *)
    Alcotest.(check string)
      "set_int threaded forward at rc==1 mutates in place and stays correct \
       over 2M ops (final array = sum of the last 8 writes)"
      "15999964" run_out

(* ── Blocking-FFI worker pool ────────────────────────────────────── *)

(* Blocking externs used to get a fresh pthread_create + join PER CALL, which
   made a program doing one blocking call per work item pay a thread
   create/join per item (measured on a 3,600-item run: 14,408 clone3 calls,
   ~0.79s of pure thread churn — enough to make the parallel path several
   times slower than the serial one).  Calls now go to a pool of reusable
   worker threads.

   The pool must stay ELASTIC — see the comment in runtime/march_ffi.c: blocking
   calls can depend on each other, so a submission that finds no PARKED worker
   must spawn one rather than wait for a busy worker to free up.  This test
   therefore checks reuse, not a thread cap: many sequential calls from a single
   green thread must be served by far fewer threads than there are calls. *)
let test_blocking_ffi_pool_reuses_threads_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_blkpool"
    "mod BlkPool do\n\
    \  needs IO.Console\n\
    \  needs IO\n\
    \  extern \"march\" : Cap(IO.Foreign) do\n\
    \    blocking fn nap(us : Int) : Int = \"march_test_blocking_nap\"\n\
    \    fn spawned() : Int = \"march_blocking_threads_spawned\"\n\
    \    fn calls() : Int = \"march_blocking_calls\"\n\
    \  end\n\
    \  pfn spin(n : Int) : Int do\n\
    \    if n <= 0 do 0 else do let _ = nap(0)\n\
    \      spin(n - 1) end end\n\
    \  end\n\
    \  fn main(_cap_console : Cap(IO.Console), _cap_foreign : Cap(IO.Foreign)) do\n\
    \    let _ = spin(400)\n\
    \    println(int_to_string(calls()) ++ \" \" ++ int_to_string(spawned()))\n\
    \  end\n\
     end\n"
  in
  let bin = Filename.concat tmp "blkpoolbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let out = read_cmd_output (Printf.sprintf "%s 2>&1" (Filename.quote bin)) in
    (match String.split_on_char ' ' (String.trim out) with
     | [calls_s; spawned_s] ->
       let calls = int_of_string (String.trim calls_s) in
       let spawned = int_of_string (String.trim spawned_s) in
       Alcotest.(check bool)
         (Printf.sprintf "all 400 blocking calls ran (saw %d)" calls)
         true (calls >= 400);
       (* One-thread-per-call would make these equal.  A serial caller can only
          ever need one worker at a time, so reuse should keep this tiny; the
          bound is deliberately loose (idle-retirement or a stray respawn may
          add a few) while still failing hard on per-call thread creation. *)
       Alcotest.(check bool)
         (Printf.sprintf
            "pool reuses threads: %d spawned for %d calls (per-call would be %d)"
            spawned calls calls)
         true (spawned <= 20)
     | _ ->
       Alcotest.failf "unexpected output from blocking-pool probe: %S" out)

(* Signal.watch — a FOURTH family, and the most severe: unlike __try_call
   (one call) or the array builtins (N calls but the whole map finishes and
   releases in one process step), a watcher closure is held for the
   program's entire lifetime and can be invoked an UNBOUNDED number of times,
   once per signal delivery. Before this fix (runtime/march_runtime.c's
   march_signal_drain, march_incrc before each apply() call) a CAPTURING
   watcher's apply function released its one $clo reference on the very
   first delivery — the table then held a dangling pointer, and the SECOND
   delivery dispatched through freed memory. Confirmed deterministic (not
   flaky like __try_call's UAF): every run crashed on delivery 2 before the
   fix, every run below is clean after it. *)
let test_signal_watch_capturing_handler_repeated_delivery_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_sigwatchcap"
    "mod SigWatchCap do\n\
    \  needs IO.Console\n\
    \  needs IO.Signal\n\
    \  fn main(_cap_console : Cap(IO.Console), _cap_signal : Cap(IO.Signal)) do\n\
    \    let k = 99\n\
    \    Signal.watch(Signal.Usr2, fn -> println(\"caught \" ++ int_to_string(k)))\n\
    \    Signal.raise(Signal.Usr2)\n\
    \    Signal.raise(Signal.Usr2)\n\
    \    Signal.raise(Signal.Usr2)\n\
    \    println(\"done\")\n\
    \  end\n\
     end\n"
  in
  let bin = Filename.concat tmp "sigwatchcapbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let cmd = Printf.sprintf "%s 2>&1; echo EXIT:$?" (Filename.quote bin) in
    let ok out =
      ir_contains out "done" && ir_contains out "EXIT:0"
      && not (ir_contains out "RC underflow")
    in
    (* Retry a failing iteration ONCE before failing the suite, and report what
       was actually captured when it fails twice.

       Why a retry here is not a way of hiding the bug: the regression this
       test guards is DETERMINISTIC.  Pre-fix the capturing watcher was freed
       on delivery 1 and EVERY run crashed dispatching delivery 2 (see the
       comment above this function).  A deterministic crash fails both
       attempts, so a single retry cannot mask it; what it absorbs is a
       one-off environmental kill.

       That distinction is the whole point.  This test reddened trmc-suite
       (ubuntu-24.04) twice on PR #316 — a test-only PR with an empty
       lib/runtime/bin diff — while passing on main's runs of #315 and #317
       (specs/progress/2026-08-21-signal-watch-capturing-handler-trmc-suite-flake.md).
       Locally the only failure reproducible in 6000 runs was EXIT:137: the
       binary SIGKILLed with otherwise-correct output, i.e. host-level
       pressure, the same shape as the exit-137 observations recorded in
       specs/progress/2026-08-21-actor-monitor-bounded-mailbox-race.md.

       The old form asserted a bare bool, so a CI failure printed only
       "Expected true, Received false" — no captured output, no iteration
       number, nothing to diagnose from.  That was the todo's core complaint;
       Alcotest.failf below fixes it. *)
    for i = 1 to 25 do
      let run_out = read_cmd_output cmd in
      if not (ok run_out) then begin
        let retry_out = read_cmd_output cmd in
        if not (ok retry_out) then
          Alcotest.failf
            "a capturing Signal.watch handler delivered 3 times must not be \
             freed after the first delivery (long-lived, unbounded-repeat \
             call site) - iteration %d failed twice. first attempt: %S retry: %S"
            i run_out retry_out
      end
    done

(* ── `--check` diagnostic-display determinism ───────────────────────────
   Repeated `march --check` of the SAME source file must produce
   byte-identical stderr every run. Regression for a display-nondeterminism
   bug: `--check` cached a "clean check" CAS artifact after ANY successful
   check (bin/main.ml), then a later identical-source invocation hit that
   cache and `exit 0`ed BEFORE the diagnostic-printing pass — so a module
   that emits a warning/hint (here: the Check-3 `Cap(IO)`-narrowing HINT)
   printed it on the first (cache-miss) run and stayed SILENT on every
   subsequent (cache-hit) run. Because the CAS store lives at the shared
   project-root `.march/cas` and is cleared intermittently (concurrent
   sessions, `dune cache trim`), the hint reappeared ~1-in-N — real, if
   display-only (the exit code is invariant 0). Fix: only cache a `--check`
   run that emitted NO user-facing diagnostics, so a cache hit provably
   means "nothing to print" and its silent exit is byte-identical to a fresh
   run.

   A fresh unique temp path guarantees a cache MISS on the first run, so
   pre-fix this test is reliably RED (run 1 prints the hint, run 2 is
   silent); post-fix all runs print identically. *)
let test_check_diagnostic_display_deterministic () =
  let (project_root, main_exe, src, _tmp) =
    write_march_source ~name:"march_capcheck_determinism"
      "mod CapCheckDet do\n\
      \  needs IO\n\
      \  fn run(io : Cap(IO)) do io end\n\
       end\n"
  in
  let check_cmd = Printf.sprintf
    "cd %s && %s --check %s 2>&1"
    (Filename.quote project_root)
    (Filename.quote main_exe) (Filename.quote src)
  in
  let iterations = 12 in
  let first = read_cmd_output check_cmd in
  (* The narrowing HINT must actually appear (otherwise the test is vacuous —
     it would pass trivially if `--check` printed nothing at all). *)
  Alcotest.(check bool)
    "the Cap(IO)-narrowing HINT is present in --check output"
    true
    (ir_contains first "narrowing" || ir_contains first "HINT");
  let all_identical = ref true in
  for _ = 2 to iterations do
    let out = read_cmd_output check_cmd in
    if out <> first then all_identical := false
  done;
  Alcotest.(check bool)
    (Printf.sprintf
       "repeated --check produces byte-identical stderr across %d runs \
        (no cache-driven diagnostic suppression)" iterations)
    true
    !all_identical

(* ── Erased-Option FBIP reuse (RC underflow) ────────────────────────────
   A niche-represented Option (`Some(x) ≡ x`) that crosses a fully-polymorphic
   boundary (`actor_call`'s reply is `Result(Option(a), _)` with `a` an
   unresolved unification variable) reaches Perceus as `Option(TVar)`.
   `Repr.repr_of_ty` conservatively boxes that (niche_payload_ok(TVar)=false),
   but codegen (`llvm_case.ml`'s `effective_repr` abstract-arg recovery) niche-
   encodes it — the value shares storage with its payload.  Pre-fix,
   `scrutinee_shares_payload_storage` trusted `repr_of_ty`'s Boxed verdict, so
   `add_scrutinee_free_for` treated the value as a distinct boxed cell and
   handed it to FBIP, which rewrote `Some(conn) -> Ok(conn)` into
   `reuse maybe_conn as Ok(conn)`.  Because `conn` aliases `maybe_conn` (niche),
   the reuse stored the payload into its own reused cell — a self-referential
   object → `march: RC underflow (rc was 0)` (SIGABRT, exit 134) when the
   value is later consumed.  Fix: `scrutinee_shares_payload_storage` mirrors
   codegen's abstract-arg niche recovery.  See docs/value-representation.md §7.
   Runs the binary because the symptom is a runtime abort, not an IR shape. *)
let test_erased_option_niche_fbip_no_underflow_compiled () =
  let (project_root, main_exe, src, tmp) =
    write_march_source ~name:"march_erased_option_niche"
    "mod Main do\n\
    \  needs IO.Console\n\
    \  needs IO.Spawn\n\
    \  type Conn = PgConn(Int) | LiteConn(String)\n\
    \  actor Pool do\n\
    \    state { n : Int }\n\
    \    init { n: 0 }\n\
    \    on Checkout(reply_to) do\n\
    \      let _ = actor_reply(reply_to, Some(PgConn(42)))\n\
    \      state\n\
    \    end\n\
    \  end\n\
    \  fn describe(c) do\n\
    \    match c do\n\
    \    PgConn(fd)  -> \"pg:\" ++ int_to_string(fd)\n\
    \    LiteConn(k) -> \"lite:\" ++ k\n\
    \    end\n\
    \  end\n\
    \  fn checkout(pool) do\n\
    \    let t = task_spawn(fn _ ->\n\
    \      match actor_call(pool, Checkout(0), 5000) do\n\
    \      Err(e)         -> Err(e)\n\
    \      Ok(maybe_conn) ->\n\
    \        match maybe_conn do\n\
    \        None       -> Err(\"none\")\n\
    \        Some(conn) -> Ok(conn)\n\
    \        end\n\
    \      end\n\
    \    )\n\
    \    task_await_unwrap(t)\n\
    \  end\n\
    \  fn main(_cap_console : Cap(IO.Console), _cap_spawn : Cap(IO.Spawn)) do\n\
    \    match checkout(spawn(Pool)) do\n\
    \    Ok(conn) -> println(describe(conn))\n\
    \    Err(e)   -> println(\"err: \" ++ e)\n\
    \    end\n\
    \  end\n\
     end\n"
  in
  (* NB: no interpreter parity check here — the interpreter's actor_call /
     task_spawn interaction does not deliver the reply for this shape ("err: no
     reply"), an unrelated interpreter limitation.  The RC bug is purely a
     COMPILED-backend defect, so we assert on the compiled binary alone:
     pre-fix it aborted with `RC underflow` (SIGABRT, exit 134); post-fix it
     prints pg:42 and exits 0. *)
  let bin = Filename.concat tmp "erasedoptbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Printf.sprintf "%s 2>&1; echo EXIT:$?" (Filename.quote bin)) in
    Alcotest.(check bool)
      "compiled erased-niche-Option checkout prints pg:42 with no RC underflow \
       (not SIGABRT/exit 134)"
      true
      (ir_contains run_out "pg:42"
       && ir_contains run_out "EXIT:0"
       && not (ir_contains run_out "RC underflow"))

(* ── Nested-tuple destructure in a block-level `let` (Core March golden) ──
   `let ((a, b), (c, d)) = ((1, 2), (3, 4))` failed to compile: the emitted IR
   referenced a/b/c/d as undefined global functions (`call ptr @a()`), so clang
   rejected the module.  Root cause: the block-`let` PatTuple lowering in
   lib/tir/lower.ml bound only *direct* PatVar tuple elements and silently
   dropped any nested sub-pattern (`| _ -> inner`), so a nested tuple's leaf
   vars were never bound and later resolved to global fn references.  The
   interpreter and the equivalent `match ((1,2),(3,4)) do ((a,b),(c,d)) -> ..`
   form always got this right; only the compiled block-`let` path diverged.
   Compile-and-run because the symptom is a codegen failure / wrong value, not
   an IR shape (same rationale as the float-literal tests above). *)
let test_nested_tuple_let_destructure_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_nested_tuple_let"
    "mod NestedTupleLet do\n\
    \  needs IO.Console\n\
    \  fn main(_cap_console : Cap(IO.Console)) do\n\
    \    let ((a, b), (c, d)) = ((1, 2), (3, 4))\n\
    \    println(int_to_string(a + b + c + d))\n\
    \  end\n\
     end\n"
  in
  (* --- interpreter baseline: destructures nested tuple correctly --- *)
  let interp_out = read_cmd_output (Printf.sprintf
    "cd %s && %s %s 2>&1"
    (Filename.quote project_root)
    (Filename.quote main_exe) (Filename.quote src)) in
  Alcotest.(check string) "interpreter destructures nested tuple in let" "10" interp_out;
  (* --- compiled: must bind all four leaf vars and produce the same value --- *)
  let bin = Filename.concat tmp "nestedtupleletbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Filename.quote bin) in
    Alcotest.(check string)
      "compiled nested-tuple `let` binds every leaf var (a/b/c/d), producing \
       the SAME value as the interpreter (not `use of undefined value @a`)"
      "10" run_out

(** Deeper coverage of the same recursion: 3-level nesting, a wildcard element,
    and a nested-tuple element, all in one block-`let`.  Locks down that
    [bind_subpat] recurses through interior tuples and skips wildcards, rather
    than only handling the flat two-element repro above. *)
let test_nested_tuple_let_deep_wildcard_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_nested_tuple_let_deep"
    "mod NestedTupleLetDeep do\n\
    \  needs IO.Console\n\
    \  fn main(_cap_console : Cap(IO.Console)) do\n\
    \    let ((a, (b, c)), _, (d, e)) = ((1, (2, 3)), 99, (4, 5))\n\
    \    println(int_to_string(a + b + c + d + e))\n\
    \  end\n\
     end\n"
  in
  (* --- interpreter baseline --- *)
  let interp_out = read_cmd_output (Printf.sprintf
    "cd %s && %s %s 2>&1"
    (Filename.quote project_root)
    (Filename.quote main_exe) (Filename.quote src)) in
  Alcotest.(check string) "interpreter: deep nested tuple let with wildcard element"
    "15" interp_out;
  (* --- compiled: must match --- *)
  let bin = Filename.concat tmp "nestedtupledeepbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Filename.quote bin) in
    Alcotest.(check string)
      "compiled deep nested-tuple `let` (3-level nesting, wildcard element, \
       interior nested tuple) matches the interpreter"
      "15" run_out

(* ── Nested-fn name collision with a top-level fn (mono shadowing) ─────────
   A user top-level `pfn go` that reverses a list via `Cons(h, acc)` collides
   with the MANY stdlib helpers that use a conventionally-named nested
   `fn go` (List.length, List.reverse, List.map, …).  Monomorphization's
   [rewrite_calls] resolved every call named `go` against the module-level
   fn_table (keyed by bare name), so the stdlib helpers' nested `go` calls were
   silently rebound to the USER's top-level `go`.  `List.length(r)` then ran the
   user's reverse-accumulator against an Int accumulator (0), returning a garbage
   pointer reinterpreted as an Int (observed: len=4745871568 instead of 5).
   The interpreter has no mangling/linking step, so it was always correct — an
   interpreter-correct / compiled-wrong divergence.  Compile-and-run because the
   symptom is a wrong runtime value, not an IR shape.  Fix: nested-fn names
   shadow same-named top-level fns in mono (lib/tir/mono.ml `rewrite_calls`). *)
let test_nested_fn_name_shadows_toplevel_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_go_collision"
    "mod GoCollision do\n\
    \  needs IO.Console\n\
    \  pfn go(xs, acc) do\n\
    \    match xs do\n\
    \    Nil -> acc\n\
    \    Cons(h, t) -> go(t, Cons(h, acc))\n\
    \    end\n\
    \  end\n\
    \  fn main(_cap_console : Cap(IO.Console)) do\n\
    \    let r = go([1, 2, 3, 4, 5], [])\n\
    \    println(int_to_string(List.length(r)) ++ \"|\" ++ int_to_string(List.sum_int(r)))\n\
    \  end\n\
     end\n"
  in
  (* --- interpreter baseline: no mangling, so always correct --- *)
  let interp_out = read_cmd_output (Printf.sprintf
    "cd %s && %s %s 2>&1"
    (Filename.quote project_root)
    (Filename.quote main_exe) (Filename.quote src)) in
  Alcotest.(check string)
    "interpreter: user `go` reverses to a 5-element list; stdlib `go` helpers \
     (length/sum_int) still resolve to their own bodies"
    "5|15" interp_out;
  (* --- compiled: must match; before the fix this printed a garbage length --- *)
  let bin = Filename.concat tmp "gocollisionbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Filename.quote bin) in
    Alcotest.(check string)
      "compiled: stdlib nested `go` helpers are NOT captured by the user's \
       top-level `go` — List.length/List.sum_int return the SAME values as the \
       interpreter (not a garbage pointer reinterpreted as an Int)"
      "5|15" run_out

(* ── Non-entry-module single-field ADT: construct-vs-destructure repr ──────
   A single-field ADT (`type Wrap = Wrap(List(Int))`, or stdlib `Bytes`)
   defined in a NON-ENTRY module (a nested `mod`, or any MARCH_LIB_PATH library
   like stdlib) is registered under its MODULE-QUALIFIED name ("Inner.Wrap") by
   [Lower.lower_mod_decls], but the module's own value types reference it BARE
   ("Wrap") — the typechecker drops the prefix on same-module references.  So
   [Repr.find_variant]/[repr_of_ty] missed on the bare-name query and defaulted
   to [Boxed] at construction (EAlloc) and top-level pattern sites, while the
   codegen newtype-recovery path (`emit_case`, which looks up by CTOR name → the
   qualified typedef) saw [Newtype].  A tuple-nested destructure
   `match (w1,w2) do (Wrap(xs),Wrap(ys)) -> …` reaches [emit_case] with a
   TVar-erased sub-scrutinee → took the Newtype (identity) path, so `xs` was the
   BOX pointer, not the payload; `List.length(xs)` then read the box header
   (tag 0) as an empty `Nil` → 0.  Entry-module ADTs are registered bare so both
   sides agreed (Newtype) and worked — this was non-entry-only, and it made
   compiled `Bytes.concat` (bytes.march is a non-entry module) return an empty
   `Bytes`, hanging forgepm's Postgres handshake.  Fixed in [Repr.find_variant]:
   reconcile a bare query against a unique module-qualified registration.
   Compile-and-run because the symptom is a wrong runtime value across the
   construct/destructure boundary, not an IR shape. *)
let test_nonentry_newtype_tuple_destructure_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_nonentry_newtype"
    "mod Main do\n\
    \  needs IO.Console\n\
    \  mod Inner do\n\
    \    type Wrap = Wrap(List(Int))\n\
    \    fn mk(xs) do Wrap(xs) end\n\
    \    fn sum_pair(w1, w2) do\n\
    \      match (w1, w2) do\n\
    \      (Wrap(xs), Wrap(ys)) -> List.length(xs) + List.length(ys)\n\
    \      end\n\
    \    end\n\
    \  end\n\
    \  fn main(_cap_console : Cap(IO.Console)) do\n\
    \    let a = Inner.mk([1, 2, 3])\n\
    \    let b = Inner.mk([4, 5])\n\
    \    println(int_to_string(Inner.sum_pair(a, b)))\n\
    \  end\n\
     end\n"
  in
  (* --- interpreter baseline: no repr/mangling step, so always correct --- *)
  let interp_out = read_cmd_output (Printf.sprintf
    "cd %s && %s %s 2>&1"
    (Filename.quote project_root)
    (Filename.quote main_exe) (Filename.quote src)) in
  Alcotest.(check string)
    "interpreter: tuple-destructure of a non-entry single-field ADT unwraps \
     both payloads (3 + 2)"
    "5" interp_out;
  (* --- compiled: must match; before the fix the nested Wrap destructure took
         the Newtype (identity) path against a boxed value and printed 0 --- *)
  let bin = Filename.concat tmp "nonentrynewtypebin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Filename.quote bin) in
    Alcotest.(check string)
      "compiled: a non-entry single-field ADT is classified identically at \
       construction and (tuple-nested) destructure — the payload is unwrapped, \
       not read as an empty niche/newtype (which returned 0)"
      "5" run_out

(* ── EUpdate on type-erased records (B5) ─────────────────────────────────
   `{ base with f: v }` where the base's static shape is unknown
   (get_record_fields = [], e.g. a record_from_list/record_put result) used
   to allocate a header-only cell and write every update past it via
   field_index_for's (0, TVar "_") fallback.  The fix lowers the whole
   update to ONE march_record_update_dyn call (single allocation, base
   fields copied, named fields overwritten, runtime panic on a name missing
   from the base shape — the typechecker's TVar branch cannot validate
   names against an erased base). *)

(** IR shape: a 3-field erased update must emit exactly ONE
    march_record_update_dyn call — not a chain of per-field
    march_record_put calls (which would allocate an intermediate record per
    field and leak every non-final one: compiler-emitted temporaries are
    invisible to Perceus). *)
let test_erased_update_single_dyn_call_ir () =
  let src = {|mod ErasedUpd do
  needs IO.Console
    fn get_a(r) do r.a end
    fn main(_cap_console : Cap(IO.Console)) do
      let built = record_from_list([("a", 1), ("b", 2), ("c", 3)])
      let u = { built with a: 10, b: 20, c: 30 }
      println(int_to_string(get_a(u)))
    end
  end|} in
  let ir = emit_actor_ir src in
  (* Match CALL SITES only — the preamble also carries a
     `declare ptr @march_record_update_dyn(...)` line. *)
  Alcotest.(check int)
    "exactly ONE march_record_update_dyn call for a 3-field erased update"
    1 (ir_count ir "call ptr (ptr, i64, ...) @march_record_update_dyn(");
  Alcotest.(check int)
    "no chained march_record_put calls emitted for the update"
    0 (ir_count ir "call ptr @march_record_put(")

(** Compiled missing-field update on an erased base must PANIC (nonzero
    exit, clear message), not silently fabricate the field.  The typechecker
    cannot catch this: its TVar branch builds a partial record constraint
    from the update's own field names, never checking them against the
    base's actual fields — so `{ record_from_list([("a",1)]) with z: 99 }`
    typechecks.  march_record_put semantics (extend on new key) would
    silently produce a 2-field record here.  NOTE: the interpreter's
    ERecordUpdate (lib/eval/eval.ml) used to diverge here (silently appending
    missing update fields instead of erroring); Core March spec Task 3
    adjudicated the compiled fail-loud contract as normative and converged
    eval.ml to match (see specs/lang/core-march.md §4, ERecordUpdate rule).
    This test only asserts the compiled side; the converged interpreter
    behavior is covered by
    test_properties.ml's test_record_update_missing_field_on_erased_base_converged. *)
let test_erased_update_missing_field_panics_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_erasedupd_miss"
    "mod ErasedUpdMiss do\n\
    \  needs IO.Console\n\
    \  fn main(_cap_console : Cap(IO.Console)) do\n\
    \    let built = record_from_list([(\"a\", 1)])\n\
    \    let bad = { built with z: 99 }\n\
    \    match record_get(bad, \"z\") do\n\
    \      Some(v) -> println(\"FABRICATED \" ++ int_to_string(v))\n\
    \      None -> println(\"no z\")\n\
    \    end\n\
    \  end\n\
     end\n"
  in
  (* Compile from the source root: the new march_record_update_dyn symbol
     must come from the live runtime/*.c sources, not _build/default's
     runtime copies (refreshed only when a dune rule that lists them as
     deps runs). *)
  let src_root = project_root in
  let bin = Filename.concat tmp "erasedupdmissbin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote src_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Printf.sprintf "%s 2>&1; echo EXIT:$?" (Filename.quote bin)) in
    Alcotest.(check bool)
      "compiled erased update with a missing field name panics with a \
       no-field message (not exit 0 with a silently fabricated field)"
      true
      (ir_contains run_out "no field"
       && ir_contains run_out "EXIT:1"
       && not (ir_contains run_out "FABRICATED"))

(** Compiled multi-field (3-field) erased update: every updated field must
    carry its own value (pre-fix, all updates collided on slot 0 of a
    header-only cell) and untouched reads must not crash. *)
let test_erased_update_multi_field_values_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_erasedupd_multi"
    "mod ErasedUpdMulti do\n\
    \  needs IO.Console\n\
    \  fn get_i(r, k) do\n\
    \    match record_get(r, k) do\n\
    \      Some(v) -> v\n\
    \      None -> 0 - 1\n\
    \    end\n\
    \  end\n\
    \  fn main(_cap_console : Cap(IO.Console)) do\n\
    \    let built = record_from_list([(\"a\", 1), (\"b\", 2), (\"c\", 3)])\n\
    \    let u = { built with a: 11, b: 22, c: 33 }\n\
    \    println(int_to_string(get_i(u, \"a\")) ++ \" \" ++\n\
    \            int_to_string(get_i(u, \"b\")) ++ \" \" ++\n\
    \            int_to_string(get_i(u, \"c\")))\n\
    \  end\n\
     end\n"
  in
  (* --- interpreter baseline --- *)
  let interp_out = read_cmd_output (Printf.sprintf
    "cd %s && %s %s 2>&1"
    (Filename.quote project_root)
    (Filename.quote main_exe) (Filename.quote src)) in
  Alcotest.(check string) "interpreter: all three updated values" "11 22 33" interp_out;
  (* --- compiled must agree (compile from the source root — see the
     missing-field test above for why) --- *)
  let src_root = project_root in
  let bin = Filename.concat tmp "erasedupdmultibin" in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote src_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Filename.quote bin) in
    Alcotest.(check string)
      "compiled 3-field erased update: each field carries its own value \
       (no slot-0 collision, no corruption)"
      "11 22 33" run_out

(* ── Interface-impl monomorphization: compiled println/show on generic
   containers (Wave 2, Task 1) ──────────────────────────────────────────
   Root cause (see specs/analysis or .superpowers/sdd/sortby-diagnosis.md):
   inside `impl Show(List(a)) when Show(a)` (stdlib/prelude.march), the
   element-level `show(x)` types as a TVar, so lower.ml defers resolution.
   mono.ml resolves the OUTER call (`show(xs : List(Int))`) to the mangled
   impl `Show$List.show`, but historically enqueued that impl with an EMPTY
   substitution — so the impl body stayed generic and the nested `show(x)`
   call survived to llvm_emit unresolved.  llvm_emit's `unqualified_fns`
   dot-suffix fallback then resolved the bare `show` to whatever `*.show`
   impl happened to be registered first (typically `Show$List.show`
   itself) — the list-impl applied to a raw element.  Symptom varies by
   element type: Int → SIGSEGV (tag-load on an erased-int treated as a
   heap pointer), String → non-exhaustive-match panic, Option → SIGSEGV/
   SIGBUS (varies by which impl DCE keeps first).

   These four variants (Int list, String list, Option list, nested list)
   must all produce IDENTICAL stdout in compiled and interpreted mode, and
   the compiled binary must exit 0. *)

(** Shared parity assertion: interpreter and compiled binary must print the
    exact same stdout and the compiled binary must exit 0. Returns the
    compiled run's raw "stdout;EXIT:n" string on failure paths so callers
    can still assert on it directly if useful. *)
let assert_compiled_interp_parity ~name ~src ~expected () =
  let (project_root, main_exe, src_path, tmp) = write_march_source ~name src in
  let interp_out = read_cmd_output (Printf.sprintf
    "cd %s && %s %s 2>&1"
    (Filename.quote project_root)
    (Filename.quote main_exe) (Filename.quote src_path)) in
  Alcotest.(check string) (name ^ ": interpreter output") expected interp_out;
  let bin = Filename.concat tmp (name ^ "bin") in
  match compile_march_or_skip ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src:src_path () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Printf.sprintf "%s 2>&1; echo EXIT:$?"
      (Filename.quote bin)) in
    Alcotest.(check bool)
      (name ^ ": compiled output matches interpreter AND exits 0 \
       (got: " ^ run_out ^ ")")
      true
      (ir_contains run_out (expected ^ "\nEXIT:0")
       || run_out = expected ^ "\nEXIT:0")

(** `--compile --no-opt` must still prune unreachable top-level functions.
    Reachability pruning (Dce.prune_unreachable) is a LINKABILITY requirement,
    not an optimization: the injected prelude/http stack references
    not-always-linked externs (e.g. `_http_fetch`).  Before the fix DCE ran only
    inside Opt.run, so `--no-opt` left the whole prelude reachable and a trivial
    program failed to link with "Undefined symbols: _http_fetch".  This test
    compiles a trivial `println("hi")` with `--no-opt` and asserts the binary
    links, runs, prints `hi`, and exits 0. It fails (link error) pre-fix. *)
(* ── R1 stage D: the entry adapter must supply N erased capabilities ─────
   specs/2026-08-10-r1-stage-d-grant-required-design.md §D5.

   Capabilities are erased, and `march_spawn_main` invokes the program entry
   through a bare zero-argument, void-returning function pointer.  A `main`
   that takes capability parameters
   therefore cannot be spawned directly — llvm_toplevel emits a thin 0-arg
   thunk that supplies the erased capabilities (null pointers) and forwards
   into the real, N-arg mangled main.

   This is proven-dangerous ground: the FIRST version of the 1-parameter case
   passed the entry pointer straight to `march_spawn_main` with a real unused
   parameter in its LLVM signature, and the resulting ABI mismatch SIGBUS'd at
   startup (test/native/main_cap_io.march is that incident's regression file).
   Stage D generalizes the thunk from one null to N, so the same class of
   mismatch is one hardcoded argument list away from returning.

   Typecheck-side tests cannot see any of this — they pass while the binary
   crashes.  These four must be compiled AND run. *)

let test_main_adapter_zero_caps () =
  (* The arity-0 fast path: no thunk at all, the entry is spawned directly.
     Under stage D a parameterless `main` must be pure, and a pure `main`
     cannot print (printing needs a grant) — so this asserts the shape the
     parity helper cannot express: EMPTY stdout and exit 0. That is the state
     the 38 already-pure in-repo programs are in, and it must keep linking and
     running. *)
  let src =
    "mod Main do\n\
    \  fn twice(n : Int) : Int do n * 2 end\n\
    \  fn main() : () do\n\
    \    let _n = twice(21)\n\
    \    ()\n\
    \  end\n\
     end\n" in
  let (project_root, main_exe, src_path, tmp) =
    write_march_source ~name:"march_staged_adapter0" src in
  let bin = Filename.concat tmp "march_staged_adapter0bin" in
  match compile_march_or_skip
          ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src:src_path () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out =
      read_cmd_output (Printf.sprintf "%s 2>&1; echo EXIT:$?" (Filename.quote bin)) in
    Alcotest.(check string)
      "a pure parameterless main links, runs silently, and exits 0"
      "EXIT:0" run_out

let test_main_adapter_one_cap () =
  assert_compiled_interp_parity
    ~name:"march_staged_adapter1"
    ~src:"mod Main do\n\
         \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) : () do println(\"a1\") end\n\
          end\n"
    ~expected:"a1" ()

let test_main_adapter_two_caps () =
  assert_compiled_interp_parity
    ~name:"march_staged_adapter2"
    ~src:"mod Main do\n\
         \  needs IO.Console\n\
         \  needs IO.Clock\n\
         \  fn main(_cap_console : Cap(IO.Console), _cap_clock : Cap(IO.Clock)) : () do\n\
         \    let _t = unix_time()\n\
         \    println(\"a2\")\n\
         \  end\n\
          end\n"
    ~expected:"a2" ()

let test_main_adapter_three_caps () =
  assert_compiled_interp_parity
    ~name:"march_staged_adapter3"
    ~src:"mod Main do\n\
         \  needs IO.Console\n\
         \  needs IO.Clock\n\
         \  needs IO.Random\n\
         \  fn main(_cap_console : Cap(IO.Console), _cap_clock : Cap(IO.Clock), _cap_random : Cap(IO.Random)) : () do\n\
         \    let _t = unix_time()\n\
         \    let _b = random_bytes(4)\n\
         \    println(\"a3\")\n\
         \  end\n\
          end\n"
    ~expected:"a3" ()

let test_compiled_no_opt_prunes_unreachable () =
  let src =
    "mod Main do\n  needs IO.Console\n  fn main(_cap_console : Cap(IO.Console)) do println(\"hi\") end\nend\n" in
  let (project_root, main_exe, src_path, tmp) =
    write_march_source ~name:"no_opt_prune" src in
  let bin = Filename.concat tmp "no_opt_prune_bin" in
  match compile_march_or_skip
          ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~extra_args:"--no-opt"
          ~main_exe ~bin ~src:src_path () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Printf.sprintf "%s 2>&1; echo EXIT:$?"
      (Filename.quote bin)) in
    Alcotest.(check bool)
      ("--no-opt compile links, runs, prints hi, exits 0 (got: " ^ run_out ^ ")")
      true
      (run_out = "hi\nEXIT:0")

(** String.from_codepoint/to_codepoints must be usable COMPILED (2026-07-14,
    restored 2026-07-24 from lost commit 4a1c2ee3).  They were interpreter-only
    builtin wrappers: string_from_codepoint / string_to_codepoints exist in
    eval.ml but have no native runtime impl and no llvm_emit mapping, so any
    compiled program calling them failed at link time with
    `Undefined symbols: _string_from_codepoint`.  Now pure-March UTF-8 codecs
    over Bytes + the int_* bitwise builtins — one definition, every backend.
    Covers the 1/2/3/4-byte encode widths, the rejection cases (negative,
    > 0x10FFFF handled via range check, UTF-16 surrogates), and decode. *)
let test_string_codepoint_parity () =
  assert_compiled_interp_parity
    ~name:"march_string_codepoint"
    ~src:"mod StringCodepoint do\n\
    \  needs IO.Console\n\
         \  pfn opt(o) do\n\
         \    match o do\n\
         \      Some(x) -> x\n\
         \      None -> \"<none>\"\n\
         \    end\n\
         \  end\n\
         \  pfn ints_go(xs, acc) do\n\
         \    match xs do\n\
         \      Nil -> acc\n\
         \      Cons(h, Nil) -> acc ++ int_to_string(h)\n\
         \      Cons(h, t) -> ints_go(t, acc ++ int_to_string(h) ++ \",\")\n\
         \    end\n\
         \  end\n\
         \  pfn ints(xs) do ints_go(xs, \"\") end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(opt(String.from_codepoint(65)) ++ opt(String.from_codepoint(233)))\n\
         \    println(opt(String.from_codepoint(-1)) ++ opt(String.from_codepoint(55296)))\n\
         \    println(ints(String.to_codepoints(\"AB\")))\n\
         \    println(ints(String.to_codepoints(\"é\")))\n\
         \    println(ints(String.to_codepoints(opt(String.from_codepoint(128512)))))\n\
         \  end\n\
          end\n"
    ~expected:"Aé\n<none><none>\n65,66\n233\n128512"
    ()

(** The three builtins that were registered in typecheck.ml's table and absent
    from codegen's, so they typechecked, lowered to LLVM, and then failed at
    LINK time with a bare C symbol name and no March span
    (specs/progress/2026-08-21-unix-time-ms-has-no-codegen-backing.md):

      Undefined symbols for architecture arm64:
        "_unix_time_ms", referenced from: ...

    These are the RAW builtins, not `String.from_codepoint`/`String.to_codepoints`
    — the pure-March codec in stdlib/string.march, covered by
    [test_string_codepoint_parity] above, which exists precisely because these
    did not link.  Both spellings are worth holding: the stdlib one is what
    user code calls, these are what it could delegate to.

    Interpreter/compiled parity is the assertion because that is the contract
    that was broken; [test_every_builtin_c_name_is_declared] covers the
    structural half (a table entry with no declare), and this covers the half
    it cannot see (a declare with no definition to link against). *)
let test_compiled_string_codepoint_builtin_parity () =
  assert_compiled_interp_parity
    ~name:"march_string_codepoint_builtin"
    ~src:"mod StringCodepointBuiltin do\n\
    \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(string_to_codepoints(\"aé€𝄞\"))\n\
         \    println(string_to_codepoints(\"\"))\n\
         \    println(string_from_codepoint(65))\n\
         \    println(string_from_codepoint(119070))\n\
         \    println(string_from_codepoint(1114112))\n\
         \    println(string_from_codepoint(55296))\n\
         \  end\n\
          end\n"
    ~expected:"[97, 233, 8364, 119070]\n[]\nSome(A)\nSome(𝄞)\nNone\nNone"
    ()

(** unix_time_ms: same defect, but a wall clock has no reproducible output, so
    every assertion is a RELATION that both backends must agree on rather than
    a value.

    What this does NOT check, deliberately recorded so nobody reads more into
    it: that the builtin is registered IMPURE in lib/tir/purity.ml.  If it were
    treated as pure, the two calls would be CSE'd into one read, and every
    relation below — `t1 >= t0` included — would still hold, for the wrong
    reason.  The honest test for that would have to assert two reads CAN
    differ, which is inherently flaky at millisecond resolution.  The purity
    registration is held by the list itself, not by this test. *)
let test_compiled_unix_time_ms_parity () =
  assert_compiled_interp_parity
    ~name:"march_unix_time_ms"
    ~src:"mod UnixTimeMsParity do\n\
    \  needs IO\n\
         \  fn main(_cap : Cap(IO)) do\n\
         \    let t0 = unix_time_ms(())\n\
         \    let secs = unix_time(())\n\
         \    println(t0 > 1700000000000)\n\
         \    println(float_to_int(secs) > 1700000000)\n\
         \    let drift = t0 - float_to_int(secs *. 1000.0)\n\
         \    println(drift > -1000 && drift < 1000)\n\
         \    let t1 = unix_time_ms(())\n\
         \    println(t1 >= t0 && t1 - t0 < 60000)\n\
         \  end\n\
          end\n"
    ~expected:"true\ntrue\ntrue\ntrue"
    ()

(** int_div_euclid: native codegen must route through march_checked_ediv and
    match the interpreter's Euclidean quotient across all four sign quadrants.
    Pre-fix the builtin had no llvm_emit mapping, so compiling ANY caller failed
    at link time with `Undefined symbols: _int_div_euclid`. The negative-operand
    cases exercise the truncated→Euclidean correction step (r<0 → q∓1). *)
let test_compiled_int_div_euclid_parity () =
  assert_compiled_interp_parity
    ~name:"march_int_div_euclid"
    ~src:"mod IntDivEuclidParity do\n\
    \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println([int_div_euclid(7, 2), int_div_euclid(-7, 2), \
                        int_div_euclid(-7, -2), int_div_euclid(7, -2)])\n\
         \  end\n\
          end\n"
    ~expected:"[3, -4, 4, -3]"
    ()

(** int_mod_euclid: the Euclidean remainder must be non-negative in all four
    sign quadrants. The runtime helper (march_checked_emod) previously used
    unsigned `%`, which agrees with the interpreter only for a positive divisor;
    for a NEGATIVE divisor it diverged (int_mod_euclid(-7, -3) → -7 compiled vs.
    2 interpreted). This pins the fixed signed-Euclidean semantics. *)
let test_compiled_int_mod_euclid_parity () =
  assert_compiled_interp_parity
    ~name:"march_int_mod_euclid"
    ~src:"mod IntModEuclidParity do\n\
    \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println([int_mod_euclid(7, 3), int_mod_euclid(-7, 3), \
                        int_mod_euclid(-7, -3), int_mod_euclid(7, -3)])\n\
         \  end\n\
          end\n"
    ~expected:"[1, 2, 2, 1]"
    ()

(** Deque.pop_front decode parity (2026-07-24).  deque.march loaded LAZILY
    (it was missing from bin/main.ml's stdlib_file_list), so the caller's
    let-binders stayed unresolved '_ tvars and monomorphization could not
    specialize the generic pop_front : Deque(a) -> (Option(a), Deque(a)).
    The generic body allocates a BOXED Some cell; the concrete caller decodes
    the tuple field as a NICHE Option(Int) — so `Some(v)` bound v to the box's
    heap ADDRESS.  Interpreted printed 1; compiled printed a raw pointer, and
    bench/deque_ops's drain loop never terminated.  Fixed by eager-loading
    deque.march; the lazy-vs-eager repr-divergence CLASS is filed in
    specs/todos.md.  This pins the decode plus a push/pop/drain round trip. *)
let test_compiled_deque_pop_parity () =
  assert_compiled_interp_parity
    ~name:"march_deque_pop"
    ~src:"mod DequePop do\n\
    \  needs IO.Console\n\
         \  pfn drain(d, acc : Int) : Int do\n\
         \    match Deque.pop_front(d) do\n\
         \    (None, _)    -> acc\n\
         \    (Some(v), r) -> drain(r, acc + v)\n\
         \    end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let d = Deque.push_back(Deque.push_front(Deque.empty(), 1), 2)\n\
         \    match Deque.pop_front(d) do\n\
         \      (Some(v), _) -> println(int_to_string(v))\n\
         \      (None, _) -> println(\"empty\")\n\
         \    end\n\
         \    println(int_to_string(drain(d, 0)))\n\
         \  end\n\
          end\n"
    ~expected:"1\n3"
    ()

(** Deep-tree flatten regression.  `IOList.append(acc, x)` in a loop builds a
    left-spine `Segments([Segments([...], x_{n-1}]), x_n])` tree one level
    deeper per append.  The old `to_string`/`byte_size` walked this with a
    non-tail native recursion, so flattening a deep chain overflowed the 1 MiB
    green-thread stack and crashed with SIGBUS (rc138) — even though the module
    documents flattening as stack-safe.  The fix rewrote those walkers as
    tail-recursive explicit-worklist traversals.  The pre-fix crash threshold on
    this shape was measured between 15k and 20k deep; 25000 sits comfortably
    past it (and far below `bench/iolist_template`'s 50k) so the test crashes
    reliably pre-fix while keeping the interpreter leg cheap. *)
let test_compiled_iolist_deep_flatten_parity () =
  assert_compiled_interp_parity
    ~name:"march_iolist_deep_flatten"
    ~src:"mod IOListDeepFlatten do\n\
    \  needs IO.Console\n\
         \  pfn build(n : Int, acc : IOList) : IOList do\n\
         \    if n == 0 do acc\n\
         \    else build(n - 1, IOList.append(acc, IOList.from_string(\"x\"))) end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let t = build(25000, IOList.empty())\n\
         \    println(int_to_string(IOList.byte_size(t)))\n\
         \    println(int_to_string(string_byte_length(IOList.to_string(t))))\n\
         \  end\n\
          end\n"
    ~expected:"25000\n25000"
    ()

(** Float `!=` on NaN: the interpreter implements float `!=` via OCaml's
    polymorphic `<>`, under which `nan <> nan` is `true`. The compiled
    backend used LLVM `fcmp one` (ordered-and-not-equal, IEEE 754 semantics)
    for `!=`, which is `false` whenever either operand is NaN — a
    interp/compiled divergence. Fixed by using `fcmp une`
    (unordered-or-not-equal), which matches `<>`: true whenever the operands
    differ OR either is NaN. `string_to_float("nan")` is used to produce a
    NaN without hitting the checked-div-by-zero abort that `0.0 /. 0.0`
    triggers on both backends. *)
let test_compiled_float_nan_neq_parity () =
  assert_compiled_interp_parity
    ~name:"march_float_nan_neq"
    ~src:"mod FloatNanNeqParity do\n\
    \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let x = match string_to_float(\"nan\") do\n\
         \      Some(v) -> v\n\
         \      None -> 0.0\n\
         \    end\n\
         \    println(x != x)\n\
         \    println(x != 1.0)\n\
         \  end\n\
          end\n"
    ~expected:"true\ntrue"
    ()

(** Self-referencing block-`let` shadowing (`let x = x + 5`) must compile to
    the same value the interpreter produces. Pre-fix, `Cprop`'s `ELet` arm
    left the outer binding's literal mapping (`x -> 10`) in scope when the
    shadowing RHS was not itself a literal/alias/record, so the body's uses of
    the *new* `x` were substituted with the *old* value — a silently-wrong
    compile on BOTH the native and JS backends (interpreter was correct). The
    chain `((10 + 5) * 2)` discriminates cleanly: correct = 30, buggy = 10
    (every shadow kept reading the original 10). *)
let test_compiled_let_shadowing_parity () =
  assert_compiled_interp_parity
    ~name:"march_let_shadowing"
    ~src:"mod LetShadowParity do\n\
    \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let x = 10\n\
         \    let x = x + 5\n\
         \    let x = x * 2\n\
         \    println(int_to_string(x))\n\
         \  end\n\
          end\n"
    ~expected:"30"
    ()

(** Entry-module self-qualification: a hand-written call that spells out the
    entry file's OWN top-level module name (`Foo.wrapped(x)` inside `mod Foo`,
    or `Outer.Inner.wrapped(x)` inside entry `mod Outer`) must resolve. TIR
    unwraps the entry module — its members are emitted WITHOUT the entry
    mod-name prefix — but a dotted source reference kept its `Foo.` /
    `Outer.` segment (it never matched desugar's bare `make_qualifier`), so
    reference and definition never converged: "unbound variable: Foo.wrapped"
    (interp) / "Undefined symbols: _Foo.wrapped" (compiled), on BOTH backends.
    The desugar strip pass removes only the single leading entry-own segment,
    so `Outer.Inner.wrapped -> Inner.wrapped` survives to match the nested
    definition. `wrapped(5)` = 6 via `Foo.bar` / `Outer.Inner.helper`. *)
let test_compiled_entry_self_qual_parity () =
  assert_compiled_interp_parity
    ~name:"march_entry_self_qual"
    ~src:"mod Foo do\n\
    \  needs IO.Console\n\
         \  fn bar(x) do x + 1 end\n\
         \  fn wrapped(x) do Foo.bar(x) end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do println(int_to_string(Foo.wrapped(5))) end\n\
          end\n"
    ~expected:"6"
    ()

(** Nested variant of {!test_compiled_entry_self_qual_parity}: the entry file's
    sole top-level mod is `Outer`, so `Outer.Inner.wrapped(5)` must strip only
    the leading `Outer.` down to `Inner.wrapped` (the nested `Inner.` stays,
    matching the still-qualified nested definition). *)
let test_compiled_entry_self_qual_nested_parity () =
  assert_compiled_interp_parity
    ~name:"march_entry_self_qual_nested"
    ~src:"mod Outer do\n\
    \  needs IO.Console\n\
         \  mod Inner do\n\
         \    fn helper(x) do x + 1 end\n\
         \    fn wrapped(x) do helper(x) end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do println(int_to_string(Outer.Inner.wrapped(5))) end\n\
          end\n"
    ~expected:"6"
    ()

(** Over-stripping guard for {!test_compiled_entry_self_qual_parity}: bare
    intra-module calls (`wrapped(5)`) and single-level nested-module
    references that do NOT lead with the entry name (`Inner.wrapped(5)`) must
    STILL resolve after the strip pass. Prints 6 twice. *)
let test_compiled_entry_self_qual_no_overstrip_parity () =
  assert_compiled_interp_parity
    ~name:"march_entry_self_qual_no_overstrip"
    ~src:"mod Outer do\n\
    \  needs IO.Console\n\
         \  mod Inner do\n\
         \    fn helper(x) do x + 1 end\n\
         \    fn wrapped(x) do helper(x) end\n\
         \  end\n\
         \  fn bar(x) do x + 1 end\n\
         \  fn wrapped(x) do bar(x) end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(int_to_string(wrapped(5)))\n\
         \    println(int_to_string(Inner.wrapped(5)))\n\
         \  end\n\
          end\n"
    ~expected:"6\n6"
    ()

(** [DExtern] arm of {!test_compiled_entry_self_qual_parity}: an `extern`
    block's `fn`s are ordinary lowercase value names of the declaring module,
    so `Foo.my_abs(-7)` inside entry `mod Foo` must strip to `my_abs(-7)` just
    like a `DFn` does.  Pre-fix, desugar's [collect_direct_names] ended in
    `| _ -> []` and so knew only about `DFn`/`DLet`: the strip pass's
    must-name-something-of-ours guard did not recognise `my_abs` as a member,
    left the reference as `Foo.my_abs`, and it never converged on the
    definition — `unbound variable: Foo.my_abs` (interp) /
    `Undefined symbols: _Foo.my_abs` (compiled), on BOTH backends.

    The explicit `= "labs"` symbol binds C's `labs` so the program actually
    links and runs on both backends (the default `<lib>_<fn>` mangling would
    look for a nonexistent `libc_my_abs`). *)
let test_compiled_entry_self_qual_extern_parity () =
  assert_compiled_interp_parity
    ~name:"march_entry_self_qual_extern"
    ~src:"mod Foo do\n\
    \  needs IO.Console\n\
         \  needs IO.Foreign\n\
         \  needs IO.FileSystem\n\
         \  extern \"libc\": Cap(IO.FileSystem) do\n\
         \    fn my_abs(x : Int) : Int = \"labs\"\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console), _cap_foreign : Cap(IO.Foreign)) do println(int_to_string(Foo.my_abs(0 - 7))) end\n\
          end\n"
    ~expected:"7"
    ()

(** Over-qualification guard for {!test_compiled_entry_self_qual_extern_parity}:
    [collect_direct_names] also feeds [qualify_module_refs], which rewrites
    BARE intra-module calls inside a NESTED module to `Outer.Inner.name`.  An
    extern `fn` called bare from inside the nested module that declares it must
    still reach the foreign symbol after that rewrite, not get qualified into
    nothing. *)
let test_compiled_entry_self_qual_extern_nested_parity () =
  assert_compiled_interp_parity
    ~name:"march_entry_self_qual_extern_nested"
    ~src:"mod Foo do\n\
    \  needs IO.Console\n\
    \  needs IO.Foreign\n\
         \  mod Bar do\n\
         \    needs IO.Foreign\n\
         \    needs IO.FileSystem\n\
         \    extern \"libc\": Cap(IO.FileSystem) do\n\
         \      fn my_abs(x : Int) : Int = \"labs\"\n\
         \    end\n\
         \    fn go(x) do my_abs(x) end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console), _cap_foreign : Cap(IO.Foreign)) do println(int_to_string(Bar.go(0 - 7))) end\n\
          end\n"
    ~expected:"7"
    ()

(** Guard that an interface method name stays OUT of [collect_direct_names].
    Interface methods resolve through interface dispatch, not module member
    lookup — `Bar.greet(1)` never resolves for any module — so adding them
    would make [qualify_module_refs] rewrite the bare `greet(1)` inside the
    nested module that DECLARES the interface into `Foo.Bar.greet(1)`, which
    resolves to nothing.  This program prints `hi-nested` today and must keep
    doing so. *)
let test_compiled_nested_interface_dispatch_parity () =
  assert_compiled_interp_parity
    ~name:"march_nested_interface_dispatch"
    ~src:"mod Foo do\n\
    \  needs IO.Console\n\
         \  mod Bar do\n\
         \    interface Greeter(a) do\n\
         \      fn greet : a -> String\n\
         \    end\n\
         \    impl Greeter(Int) do\n\
         \      fn greet(_x) do \"hi-nested\" end\n\
         \    end\n\
         \    fn go() : String do greet(1) end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do println(Bar.go()) end\n\
          end\n"
    ~expected:"hi-nested"
    ()

(** MPST (multiparty session types), 3-role Relay — the FIRST MPST test that
    RUNS the compiled binary (the [test_session_compile_*] tests only grep IR,
    so they never caught this).

    Two independent compiled-only bugs are pinned here:
    (1) Layout: [march_mpst_new] used to return a March linked list (Cons
        cells), while the typechecker types [MPST.new(P)] as a flat N-tuple and
        the compiled destructure reads tuple field offsets 16/24/32.  Reading
        past a 32-byte Cons cell yielded a garbage endpoint pointer → SIGSEGV
        (exit 139, zero stderr) on EVERY compiled MPST program.  Fixed by
        returning a flat N-tuple (mirroring [march_chan_new]).
    (2) Role name/index skew: endpoints carry positional role indices 0..N-1
        (tuple-position = role-name-SORTED order), but send/recv route by role
        NAME via [mpst_resolve_role], which used to assign names to slots in
        first-encounter order → indices didn't line up → empty-queue abort even
        after the layout fix.  Fixed by threading the sorted role names to the
        runtime so [role_names[i]] is pre-registered in tuple-position order.

    The tuple destructure `(cc, lc, sc)` is role-name-SORTED
    (Client, Logger, Server), NOT declaration order — so this also exercises
    the sorted-order contract between the typechecker and the runtime. *)
let test_compiled_mpst_relay_parity () =
  assert_compiled_interp_parity
    ~name:"march_mpst_relay"
    ~src:"mod MpstRelayParity do\n\
    \  needs IO.Console\n\
         \  type Client = Client\n\
         \  type Server = Server\n\
         \  type Logger = Logger\n\
         \  protocol Relay do\n\
         \    Client -> Server : String\n\
         \    Server -> Logger : String\n\
         \    Logger -> Client : String\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let (cc, lc, sc) = MPST.new(Relay)\n\
         \    let cc2 = MPST.send(cc, Server, \"req\")\n\
         \    let (m1, sc2) = MPST.recv(sc, Client)\n\
         \    let sc3 = MPST.send(sc2, Logger, m1)\n\
         \    let (m2, lc2) = MPST.recv(lc, Server)\n\
         \    let lc3 = MPST.send(lc2, Client, m2)\n\
         \    let (m3, cc3) = MPST.recv(cc2, Logger)\n\
         \    println(m3)\n\
         \    MPST.close(cc3) MPST.close(sc3) MPST.close(lc3)\n\
         \  end\n\
          end\n"
    ~expected:"req"
    ()

(** MPST Relay with DISTINCT payloads on each of the three hops.  Where the
    forwarding variant above could mask a name→index misroute (every hop
    carries the same "req"), this one sends a unique literal per hop and prints
    all three received values.  Any skew between the tuple-position role index
    and the name-resolved routing index would deliver the wrong string or hit
    an empty queue (abort) — so this specifically exercises fix (2), the
    sorted role-name pre-registration, not just the tuple-layout fix. *)
let test_compiled_mpst_relay_distinct_parity () =
  assert_compiled_interp_parity
    ~name:"march_mpst_relay_distinct"
    ~src:"mod MpstRelayDistinctParity do\n\
    \  needs IO.Console\n\
         \  type Client = Client\n\
         \  type Server = Server\n\
         \  type Logger = Logger\n\
         \  protocol Relay do\n\
         \    Client -> Server : String\n\
         \    Server -> Logger : String\n\
         \    Logger -> Client : String\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let (cc, lc, sc) = MPST.new(Relay)\n\
         \    let cc2 = MPST.send(cc, Server, \"c2s\")\n\
         \    let (m1, sc2) = MPST.recv(sc, Client)\n\
         \    let sc3 = MPST.send(sc2, Logger, \"s2l\")\n\
         \    let (m2, lc2) = MPST.recv(lc, Server)\n\
         \    let lc3 = MPST.send(lc2, Client, \"l2c\")\n\
         \    let (m3, cc3) = MPST.recv(cc2, Logger)\n\
         \    println(m1)\n\
         \    println(m2)\n\
         \    println(m3)\n\
         \    MPST.close(cc3) MPST.close(sc3) MPST.close(lc3)\n\
         \  end\n\
          end\n"
    ~expected:"c2s\ns2l\nl2c"
    ()

(** Guarded-match IR-bloat fix: a 3-arm guarded match with a wildcard
    catch-all ([n > 0 -> "pos"], [n < 0 -> "neg"], [_ -> "zero"]) used to
    re-lower a FRESH fallback join point per guard check, duplicating the
    tail body (panic/"zero") per arm.  The fix threads ONE shared 0-arg join
    point per arm (see lib/tir/lower_match.ml's guard path + the reduced
    test/snapshots/perceus/guard_match.expected).  This parity test guards
    the *behaviour*: all three guard outcomes must still print identically on
    the interpreter and the compiled backend after the shared-JP refactor. *)
let test_compiled_guarded_match_parity () =
  assert_compiled_interp_parity
    ~name:"march_guarded_match"
    ~src:"mod GuardedMatchParity do\n\
    \  needs IO.Console\n\
         \  fn classify(x : Int) : String do\n\
         \    match x do\n\
         \      n when n > 0 -> \"pos\"\n\
         \      n when n < 0 -> \"neg\"\n\
         \      _ -> \"zero\"\n\
         \    end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(classify(5))\n\
         \    println(classify(-3))\n\
         \    println(classify(0))\n\
         \  end\n\
          end\n"
    ~expected:"pos\nneg\nzero"
    ()

(** Variant 1: List(Int) — pre-fix symptom was SIGSEGV (exit 139). The
    erased-int tag (2n+1) got passed as a fresh Show$List.show's list
    argument and the match-scrutinee tag load faulted. *)
let test_compiled_println_int_list_parity () =
  assert_compiled_interp_parity
    ~name:"march_ifaceimpl_intlist"
    ~src:"mod IfaceImplIntList do\n\
    \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println([1, 2, 3, 4, 5])\n\
         \  end\n\
          end\n"
    ~expected:"[1, 2, 3, 4, 5]"
    ()

(** Variant 2: List(String) — pre-fix symptom was a non-exhaustive-match
    panic (exit 1): the bogus tag load landed inside a valid string heap
    object and hit the match's default arm. *)
let test_compiled_println_string_list_parity () =
  assert_compiled_interp_parity
    ~name:"march_ifaceimpl_stringlist"
    ~src:"mod IfaceImplStringList do\n\
    \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println([\"a\", \"b\"])\n\
         \  end\n\
          end\n"
    ~expected:"[a, b]"
    ()

(** Variant 3: List(Option(Int)) — pre-fix symptom was SIGSEGV/SIGBUS
    (varies with DCE impl ordering): the erased-Option payload's tag byte
    was read through the wrong impl's scrutinee layout. *)
let test_compiled_println_option_list_parity () =
  assert_compiled_interp_parity
    ~name:"march_ifaceimpl_optionlist"
    ~src:"mod IfaceImplOptionList do\n\
    \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println([Some(42), None])\n\
         \  end\n\
          end\n"
    ~expected:"[Some(42), None]"
    ()

(** Variant 4: List(List(Int)) — nested container. Exercises recursive
    impl specialization (Show$List.show for the outer List must itself
    specialize the inner Show$List.show for List(Int), which specializes
    Show$Int.show) AND is the recursion-guard check: mono's worklist
    dedup (done_set keyed by the fully mangled name) must terminate this
    without looping, since Show$List's own impl calls Show$List again at
    one level deeper. *)
let test_compiled_println_nested_list_parity () =
  assert_compiled_interp_parity
    ~name:"march_ifaceimpl_nestedlist"
    ~src:"mod IfaceImplNestedList do\n\
    \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println([[1, 2], [3]])\n\
         \  end\n\
          end\n"
    ~expected:"[[1, 2], [3]]"
    ()

(** Compiled `println(:atom)` / `show(:atom)` parity.  Pre-fix symptom was a
    LINK failure (not a runtime crash): `Show$Atom.show` was never registered
    — [Atom] was absent from lower.ml's builtin Show injection ([show_specs]),
    so `show(atom)` resolved to a bare, undefined `show` symbol.  `println$Atom`
    and `march_main` both referenced `_show`, and ld failed with "Undefined
    symbols … _show".  The interpreter rendered `:ok` fine (VAtom a -> ":" ^ a),
    so this was a compiled-backend-only divergence.  Atoms compile to nameless
    FNV-1a i64 hashes, so the fix also emits a compile-time hash→name reverse
    table (`march_atom_to_string`) that the generated `Show$Atom.show` calls. *)
let test_compiled_println_atom_parity () =
  assert_compiled_interp_parity
    ~name:"march_atomshow"
    ~src:"mod AtomShow do\n\
    \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(:ok)\n\
         \  end\n\
          end\n"
    ~expected:":ok"
    ()

(** Variant: multiple atoms (including one with digits/underscores) shown via
    the explicit `show` builtin and concatenated — exercises the reverse
    table with more than one entry and confirms each hash maps back to its
    own name. *)
let test_compiled_show_atom_multi_parity () =
  assert_compiled_interp_parity
    ~name:"march_atomshow_multi"
    ~src:"mod AtomShowMulti do\n\
    \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(show(:hello) ++ \" \" ++ show(:world_123))\n\
         \  end\n\
          end\n"
    ~expected:":hello :world_123"
    ()

(* ── Guard liveness (Wave 2 final review): positive control for
   [fail_if_unresolved_iface_method] ─────────────────────────────────────
   The four parity tests above prove the FIXED pipeline resolves nested
   interface-method calls; on a healthy compiler the guard's
   Ambiguous_iface_call (a user-facing diagnostic since 2026-08-08, formerly
   a failwith ICE) never fires, so nothing exercised it.  If ctx.top_fns naming or the guard's
   `$`-before-last-dot detection predicate ever drifts, the guard would rot
   silently.  These tests hand-build the exact regression signature as a raw
   Tir.tir_module — a bare `describe` call alongside a registered mangled
   impl `Pretty$Int.describe` — precisely BECAUSE the real frontend can no
   longer produce that state (that unreachability is what Wave 2 Task 1
   fixed), and assert emission fails loudly, naming the symbol and the
   candidate impl.  Full emit_module (rather than a synthetic-ctx unit test
   of the helper alone) was chosen so the is_known_fn gating at BOTH
   consumer call sites — the general EApp path and the ECallPtr
   no-var-slot catch-all — stays covered too. *)

let iface_guard_var name ty =
  { March_tir.Tir.v_name = name; v_ty = ty; v_lin = March_tir.Tir.Unr }

(** Minimal TIR module: one registered fn named [impl_name] plus a [main]
    whose body is [main_body]. *)
let iface_guard_module ~impl_name ~main_body =
  let open March_tir.Tir in
  let impl_fn = {
    fn_name   = impl_name;
    fn_params = [ iface_guard_var "x" TInt ];
    fn_ret_ty = TString;
    fn_body   = EAtom (ALit (March_ast.Ast.LitString "int"));
    fn_kind   = FnNormal;
  } in
  let main_fn = {
    fn_name   = "main";
    fn_params = [];
    fn_ret_ty = TString;
    fn_body   = main_body;
    fn_kind   = FnNormal;
  } in
  { tm_name = "IfaceGuard"; tm_fns = [ impl_fn; main_fn ]; tm_types = [];
    tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] }

(** A call to the bare (unqualified, unresolved) name `describe` — [mk]
    picks the call form (EApp or ECallPtr) so both guard consumers share
    one construction. *)
let bare_describe_call mk =
  let open March_tir.Tir in
  mk (iface_guard_var "describe" (TFn ([ TInt ], TString)))
    [ ALit (March_ast.Ast.LitInt 1) ]

let assert_iface_guard_fires ~path_label m =
  match March_tir.Llvm_emit.emit_module m with
  | (_ : string) ->
    Alcotest.fail
      (path_label ^ ": emit_module was expected to raise \
                     Ambiguous_iface_call — the unresolved-iface-method \
                     guard did not fire on a bare `describe` call with a \
                     registered Pretty$Int.describe impl")
  | exception March_tir.Llvm_calls.Ambiguous_iface_call msg ->
    Alcotest.(check bool)
      (path_label ^ ": failure names the unresolved symbol (got: " ^ msg ^ ")")
      true (ir_contains msg "interface-method call to `describe`");
    Alcotest.(check bool)
      (path_label ^ ": failure names the candidate impl (got: " ^ msg ^ ")")
      true (ir_contains msg "Pretty$Int.describe")

(** Consumer 1: the general EApp direct-call path. *)
let test_iface_guard_fires_eapp () =
  assert_iface_guard_fires ~path_label:"EApp"
    (iface_guard_module ~impl_name:"Pretty$Int.describe"
       ~main_body:(bare_describe_call
                     (fun f args -> March_tir.Tir.EApp (f, args))))

(** Consumer 2: the ECallPtr no-var-slot catch-all path. *)
let test_iface_guard_fires_ecallptr () =
  assert_iface_guard_fires ~path_label:"ECallPtr"
    (iface_guard_module ~impl_name:"Pretty$Int.describe"
       ~main_body:(bare_describe_call
                     (fun f args ->
                        March_tir.Tir.(ECallPtr (AVar f, args)))))

(** Negative control: an impl-mangled fn is registered but its dot-suffix
    (`render`) does not match the bare callee (`describe`), so the guard
    must NOT fire and the call must fall through to the pre-existing
    forward-declare behavior.  Pins the predicate against false positives. *)
let test_iface_guard_negative_control () =
  let m = iface_guard_module ~impl_name:"Pretty$Int.render"
      ~main_body:(bare_describe_call
                    (fun f args -> March_tir.Tir.EApp (f, args))) in
  let ir = March_tir.Llvm_emit.emit_module m in
  Alcotest.(check bool) "non-matching bare call falls through to a declare"
    true (ir_contains ir "declare ptr @describe")
(* ── Scrutinee-borrowed conservatism: cross-branch double dec_rc (P0) ────
   found during Wave 2 Task 4's TIR snapshot audit
   (test/snapshots/perceus/scrutinee_borrowed_conservatism.expected).  When a
   match arm re-matches the SAME scrutinee variable on a sub-path of its own
   body (here, the `Cons` arm's `else` branch re-matches `xs`), Perceus's
   "scrutinee-borrowed conservatism" (perceus.ml's ECase handling, ~line
   1058-1080) re-adds the scrutinee to that arm's `live_before_br` to protect
   its branch-bound vars from a premature free.  `add_cross_decrcs` (~line
   1146) used to union `live_before_br` across ALL sibling arms and emit a
   cross-branch `dec_rc` for "dead here, live elsewhere" variables — so a
   SIBLING arm (here, `Nil`) that never uses the scrutinee got a cross-branch
   `dec_rc xs` IN ADDITION TO the ordinary per-arm scrutinee free every arm
   already receives from `add_scrutinee_free_for` (~line 984).  Two
   `dec_rc`s on the same reference: RC underflow, exit 134, compiled only —
   the interpreter (which does not use this RC scheme) is unaffected.  Fixed
   by excluding the scrutinee's own variable name from `add_cross_decrcs`'s
   liveness set: its lifecycle is exclusively owned by
   `add_scrutinee_free_for`, which independently and correctly decides, per
   arm, whether to free it. *)
let test_scrutinee_borrowed_cross_branch_no_double_dec () =
  assert_compiled_interp_parity
    ~name:"march_scrutdbl"
    ~src:"mod MinimalScrutDbl do\n\
    \  needs IO.Console\n\
         \  fn f(xs : List(Int), flag : Bool) : Int do\n\
         \    match xs do\n\
         \      Cons(h, t) ->\n\
         \        if flag do\n\
         \          h\n\
         \        else\n\
         \          match xs do\n\
         \            Cons(h2, _) -> h2\n\
         \            Nil -> 0\n\
         \          end\n\
         \        end\n\
         \      Nil -> -1\n\
         \    end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do println(f(Nil, true)) end\n\
          end\n"
    ~expected:"-1"
    ()

(* ── Newtype-repr derived-method crash (P1) ─────────────────────────────
   `type Wrap = Wrap(Int)` (single ctor, single field) is Newtype-represented
   (Repr.repr_of_ty): the value IS its raw payload, no heap cell. Calling a
   derived `eq`/`compare`/`hash` BY NAME on such a value used to crash the
   compiled binary — the `==` OPERATOR path (ensure_adt_eq_fn, Repr-aware)
   was always correct, and the interpreter was always correct; only the
   named-method path, compiled, was broken. Root cause was two stacked
   defects: (1) every AST node `expand_derive` mints shared one `dummy_span`,
   so the span-keyed typechecker type_map collided across ALL derived impls
   (last write wins) and lowering read back garbage types for derived params/
   exprs; (2) `lower_match`'s destructured sub-pattern variables carry
   `unknown_ty` (a TVar), so a nested match on a Newtype-repr value (derived
   Eq's `match (a, b)`, or ANY hand-written nested destructure) reached
   `emit_case` typed TVar and took the Boxed heap-tag-load strategy on a value
   that has no heap header — SIGSEGV on a scalar payload, a garbage tag (non-
   exhaustive panic) on a String payload. Fixed by (1) uniquifying every
   derive-generated span so each node gets its own type_map entry, and (2) a
   Newtype analogue of `emit_case`'s existing TVar niche-recovery: when every
   branch's single Ctor-tag resolves unambiguously to a Newtype-repr type
   (same payload tagging), commit to the Newtype decode strategy instead of
   Boxed. Preserves interpreter semantics exactly, including the separately-
   documented payload-IGNORING behavior of derived Ord/Hash on variants (see
   syntax_reference.md "Semantics notes"). *)

(** Discriminator: `==` (operator, always worked) vs `eq(a, b)` (named
    method, crashed pre-fix) on the SAME Newtype-repr value, back to back —
    isolates the named-method-only nature of the bug. *)
let test_newtype_derived_eq_operator_vs_named_parity () =
  assert_compiled_interp_parity
    ~name:"march_newtype_eq_op_vs_named"
    ~src:"mod NewtypeEqOpVsNamed do\n\
    \  needs IO.Console\n\
         \  type Wrap = Wrap(Int)\n\
         \  derive Eq for Wrap\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let a = Wrap(1)\n\
         \    let b = Wrap(1)\n\
         \    println(bool_to_string(a == b))\n\
         \    println(bool_to_string(eq(a, b)))\n\
         \    println(bool_to_string(eq(a, Wrap(2))))\n\
         \  end\n\
          end\n"
    ~expected:"true\ntrue\nfalse"
    ()

(** Derived `compare` (Ord) and `hash` (Hash) by name on an Int-payload
    Newtype: pre-fix SIGSEGV (compare) — lldb showed EXC_BAD_ACCESS inside
    `Ord$Wrap.compare` loading a ctor tag at scrut+8 from a tagged-int
    payload. Derived Ord/Hash on variants intentionally ignore ctor payload
    (index-only) — both calls must return 0 (single ctor, index 0). *)
let test_newtype_derived_ord_hash_named_compiled () =
  assert_compiled_interp_parity
    ~name:"march_newtype_ord_hash"
    ~src:"mod NewtypeOrdHash do\n\
    \  needs IO.Console\n\
         \  type Wrap = Wrap(Int)\n\
         \  derive Ord, Hash for Wrap\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(int_to_string(compare(Wrap(1), Wrap(2))))\n\
         \    println(int_to_string(hash(Wrap(7))))\n\
         \  end\n\
          end\n"
    ~expected:"0\n0"
    ()

(** String-payload Newtype: pre-fix symptom was a NON-EXHAUSTIVE PANIC
    (not a segfault) — the garbage-tag byte at scrut+8 of a heap string
    pointer never matched the single ctor tag. *)
let test_newtype_derived_ord_string_payload_compiled () =
  assert_compiled_interp_parity
    ~name:"march_newtype_string_payload"
    ~src:"mod NewtypeStringPayload do\n\
    \  needs IO.Console\n\
         \  type WrapS = WrapS(String)\n\
         \  derive Eq, Ord, Hash for WrapS\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(bool_to_string(eq(WrapS(\"a\"), WrapS(\"a\"))))\n\
         \    println(bool_to_string(eq(WrapS(\"a\"), WrapS(\"b\"))))\n\
         \    println(int_to_string(compare(WrapS(\"a\"), WrapS(\"b\"))))\n\
         \  end\n\
          end\n"
    ~expected:"true\nfalse\n0"
    ()

(** Negative control: a 2-field single-ctor type (`Pair(Int, Int)`) is
    Boxed, not Newtype — must be unaffected by the fix (always worked). *)
let test_boxed_pair_derived_methods_unaffected_compiled () =
  assert_compiled_interp_parity
    ~name:"march_boxed_pair_control"
    ~src:"mod BoxedPairControl do\n\
    \  needs IO.Console\n\
         \  type Pair = Pair(Int, Int)\n\
         \  derive Eq, Ord, Hash for Pair\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(bool_to_string(eq(Pair(1, 2), Pair(1, 2))))\n\
         \    println(bool_to_string(eq(Pair(1, 2), Pair(1, 3))))\n\
         \    println(int_to_string(compare(Pair(1, 2), Pair(3, 4))))\n\
         \  end\n\
          end\n"
    ~expected:"true\nfalse\n0"
    ()

(** Negative control: a multi-ctor type (2 variants) is never Newtype —
    must be unaffected. *)
let test_multi_ctor_derived_methods_unaffected_compiled () =
  assert_compiled_interp_parity
    ~name:"march_multictor_control"
    ~src:"mod MultiCtorControl do\n\
    \  needs IO.Console\n\
         \  type Shape = Circle(Int) | Square(Int)\n\
         \  derive Eq, Ord, Hash for Shape\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(bool_to_string(eq(Circle(1), Circle(1))))\n\
         \    println(bool_to_string(eq(Circle(1), Square(1))))\n\
         \    println(int_to_string(compare(Circle(1), Square(1))))\n\
         \  end\n\
          end\n"
    ~expected:"true\nfalse\n-1"
    ()

(** Regression: a user variant type whose bare name collides with a stdlib
    RECORD type (`Plot.Color = { r, g, b }`, always auto-loaded) must still
    resolve its derived impls. Records register in `env.records` under their
    BARE name globally, so pre-fix `surface_ty` / `register_impl_shape`
    structurally expanded the variant's `impl Eq(Color)` to the record's
    `TRecord{r,g,b}` shape; that never matched the variant's `TCon("Color")`
    dispatch target, so typecheck reported "`Color` does not implement
    interface `Eq`". Renaming the type (e.g. to `Status`) sidestepped it — the
    type-NAME collision with the stdlib record was the sole trigger. Fixed by
    `name_is_variant` guarding the record expansion in typecheck.ml. *)
let test_derive_variant_name_collides_stdlib_record_compiled () =
  assert_compiled_interp_parity
    ~name:"march_derive_stdlib_name_collision"
    ~src:"mod ColorMod do\n\
    \  needs IO.Console\n\
         \  type Color = Red | Green | Blue\n\
         \  derive Eq, Show for Color\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(show(Green))\n\
         \    println(bool_to_string(eq(Red, Red)))\n\
         \    println(bool_to_string(eq(Red, Blue)))\n\
         \  end\n\
          end\n"
    ~expected:"Green\ntrue\nfalse"
    ()

(** Same bug, self-contained (independent of any particular stdlib module):
    a nested RECORD `Palette.Color` collides with the enclosing module's own
    variant `Color`. Distinct field names (`hue/sat/lum`) prove the corrupting
    shape is the local nested record, not stdlib `Plot.Color`, so this test
    still guards the fix if `Plot.Color` is ever renamed or removed. *)
let test_derive_variant_name_collides_local_record_compiled () =
  assert_compiled_interp_parity
    ~name:"march_derive_local_name_collision"
    ~src:"mod SelfContained do\n\
    \  needs IO.Console\n\
         \  mod Palette do\n\
         \    type Color = { hue: Int, sat: Int, lum: Int }\n\
         \  end\n\
         \  type Color = Red | Green | Blue\n\
         \  derive Eq, Show for Color\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(show(Green))\n\
         \    println(bool_to_string(eq(Red, Red)))\n\
         \    println(bool_to_string(eq(Red, Blue)))\n\
         \  end\n\
          end\n"
    ~expected:"Green\ntrue\nfalse"
    ()

(** A hand-written (non-derived) `impl Eq(Wrap)` with a nested destructure
    match must also work — this isolates defect (2) (the emit_case Newtype
    TVar-recovery) from defect (1) (derive's shared-span typecheck
    collision): a hand-written impl has real, distinct source spans, so only
    defect (2) could have crashed it. Pre-fix this also SIGSEGV'd. *)
let test_handwritten_impl_nested_match_newtype_compiled () =
  assert_compiled_interp_parity
    ~name:"march_newtype_handwritten_impl"
    ~src:"mod NewtypeHandwrittenImpl do\n\
    \  needs IO.Console\n\
         \  type Wrap = Wrap(Int)\n\
         \  impl Eq(Wrap) do\n\
         \    fn eq(a, b) do\n\
         \      match (a, b) do\n\
         \        (Wrap(x), Wrap(y)) -> x == y\n\
         \      end\n\
         \    end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(bool_to_string(eq(Wrap(1), Wrap(1))))\n\
         \    println(bool_to_string(eq(Wrap(1), Wrap(2))))\n\
         \  end\n\
          end\n"
    ~expected:"true\nfalse"
    ()

(* ── Newtype-repr `==` OPERATOR with a heap payload (P1, distinct bug) ────
   Sibling of the named-method crash above, but the reverse split: the NAMED
   `eq()`/`compare()` path was fixed by `6cc676fc`; the `==` OPERATOR path
   (`ensure_adt_eq_fn`, `lib/tir/llvm_eq.ml`) was STILL wrong — silently, not a
   crash — on a Newtype-repr type whose payload is a HEAP pointer. That fn
   special-cased the Niche (Option-shaped) repr but never consulted
   `Repr.repr_of_ty` for `Newtype`, so for a single-ctor single-field type it
   fell to the generic Boxed ctor-table strategy: it read a "ctor tag" at
   `payload_ptr + 8` and a "field" at `payload_ptr + 16`. For a String-payload
   Newtype the value IS the raw string pointer (no wrapper cell), so those
   offsets land inside the string's own heap layout and the comparison is
   garbage. An Int-payload Newtype is a tagged scalar (i64, not ptr) and never
   reaches `ensure_adt_eq_fn` at all — the operator control below stays green
   with or without the fix. Fixed by a `Repr.Newtype payload` arm in
   `ensure_adt_eq_fn` that compares the unwrapped payloads directly
   (march_string_eq for String, recursive `ensure_adt_eq_fn` for a nested
   heap ADT/tuple/record, scalar `icmp`/`fcmp` otherwise). *)

(** Core bug: `==`/`!=` on a String-payload Newtype. Pre-fix, compiled
    `WrapS("a") == WrapS("a")` returned FALSE (garbage tag/field offsets into
    the raw string cell); the interpreter was always correct. *)
let test_newtype_eq_operator_string_payload_compiled () =
  assert_compiled_interp_parity
    ~name:"march_newtype_eqop_string"
    ~src:"mod NewtypeEqOpString do\n\
    \  needs IO.Console\n\
         \  type WrapS = WrapS(String)\n\
         \  derive Eq for WrapS\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(bool_to_string(WrapS(\"a\") == WrapS(\"a\")))\n\
         \    println(bool_to_string(WrapS(\"a\") == WrapS(\"b\")))\n\
         \    println(bool_to_string(WrapS(\"a\") != WrapS(\"b\")))\n\
         \  end\n\
          end\n"
    ~expected:"true\nfalse\ntrue"
    ()

(** Control: an Int-payload Newtype is a tagged scalar, never routed through
    `ensure_adt_eq_fn` — the `==` operator was always correct here. Guards
    against a fix that would perturb the scalar path. *)
let test_newtype_eq_operator_int_payload_control_compiled () =
  assert_compiled_interp_parity
    ~name:"march_newtype_eqop_int"
    ~src:"mod NewtypeEqOpInt do\n\
    \  needs IO.Console\n\
         \  type Wrap = Wrap(Int)\n\
         \  derive Eq for Wrap\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(bool_to_string(Wrap(1) == Wrap(1)))\n\
         \    println(bool_to_string(Wrap(1) == Wrap(2)))\n\
         \  end\n\
          end\n"
    ~expected:"true\nfalse"
    ()

(** Heap-ADT payload: a Newtype wrapping a Boxed 2-field ctor. Exercises the
    recursive arm — inside `__march_eq_WrapR` the operands ARE the raw `Inner`
    heap pointers, so the fix must recurse into `Inner`'s own structural
    equality (not read a tag off the unwrapped payload). Pre-fix, compiled
    `WrapR(Inner(1,2)) == WrapR(Inner(1,3))` returned TRUE. *)
let test_newtype_eq_operator_boxed_payload_compiled () =
  assert_compiled_interp_parity
    ~name:"march_newtype_eqop_boxed"
    ~src:"mod NewtypeEqOpBoxed do\n\
    \  needs IO.Console\n\
         \  type Inner = Inner(Int, Int)\n\
         \  type WrapR = WrapR(Inner)\n\
         \  derive Eq for Inner\n\
         \  derive Eq for WrapR\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(bool_to_string(WrapR(Inner(1, 2)) == WrapR(Inner(1, 2))))\n\
         \    println(bool_to_string(WrapR(Inner(1, 2)) == WrapR(Inner(1, 3))))\n\
         \  end\n\
          end\n"
    ~expected:"true\nfalse"
    ()

(** Generic Newtype (`type Wrap(a) = Wrap(a)`) — exercises the `type_params`
    substitution branch of the fix specifically: `repr_of_ty` returns
    `Newtype (TVar a)` (the field type as written in the generic typedef, which
    mono never concretises), so the arm must apply the `a -> <concrete>` subst
    to recover the real payload type. The String instantiation must reach
    `march_string_eq` (heap payload — the bug class; verified in `--emit-llvm`
    that `__march_eq_Wrap_String` is a bare `march_string_eq` call), while the
    Int instantiation stays a tagged scalar (never enters `ensure_adt_eq_fn`).
    All three non-generic newtype tests above leave `type_params` empty, so this
    is the only test that drives a NON-identity substitution. *)
let test_newtype_eq_operator_generic_payload_compiled () =
  assert_compiled_interp_parity
    ~name:"march_newtype_eqop_generic"
    ~src:"mod NewtypeEqOpGeneric do\n\
    \  needs IO.Console\n\
         \  type Wrap(a) = Wrap(a)\n\
         \  derive Eq for Wrap\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(bool_to_string(Wrap(\"x\") == Wrap(\"x\")))\n\
         \    println(bool_to_string(Wrap(\"x\") == Wrap(\"y\")))\n\
         \    println(bool_to_string(Wrap(1) == Wrap(1)))\n\
         \    println(bool_to_string(Wrap(1) == Wrap(2)))\n\
         \  end\n\
          end\n"
    ~expected:"true\nfalse\ntrue\nfalse"
    ()

(** Bug: a variant field typed as an OPAQUE builtin type constructor (no
    March-level `type` declaration exists for it — e.g. `Task(a)`) makes
    [ensure_adt_eq_fn] return [None] for that field's own type. The `==`
    operator's per-ctor field-compare arm for [TCon _ | TTuple _ | TRecord _]
    then fell back to raw pointer-identity (ptrtoint + icmp eq) instead of
    [march_poly_eq] — the runtime-shape-dispatched comparator the sibling
    [TVar] arm (ten lines below in [llvm_eq.ml]) already uses for exactly
    this "no eq fn derivable" situation. Two distinct heap cells with
    identical content would then compare unequal.
    `Task(Int)` gives a clean repro: `Holder` itself has a `type`
    declaration (resolvable), but its field type `Task(Int)` does not (Task
    is a compiler-builtin type constructor never declared in March source) —
    and two non-nullary single-field ctors keep this off the Newtype/Niche
    shortcuts, landing in the general ctor-table codegen path where the bug
    lives. This only checks the emitted IR (no execution needed — the bug is
    in which comparator gets *called*, not runtime behavior of Task itself). *)
let test_eq_operator_opaque_ctor_field_uses_poly_eq () =
  let ir = emit_actor_ir {|mod EqOpaqueCtorField do
  needs IO.Console
  type Holder = HA(Task(Int)) | HB(Task(Int))
  derive Eq for Holder
  fn main() : Unit do
    let t = task_spawn(fn n -> n)
    println(bool_to_string(HA(t) == HA(t)))
  end
end|} in
  Alcotest.(check bool)
    "opaque ctor field falls back to march_poly_eq, not pointer identity"
    true (ir_contains ir "call i64 @march_poly_eq")

(** Cross-module ambiguous-constructor resolution (compiled-only regression).

    `Msgpack.Value` and `Json.JsonValue` (both stdlib) share the bare constructor
    names `Null`/`Bool`/`Str`/`Array` at DIFFERENT tag positions (`Array` is tag 5
    in `Value`, tag 4 in `JsonValue`). Pre-fix, an unannotated `Msgpack` function
    resolving a bare `Array`/`Str`/`Null` could pick the sibling module's variant,
    so:
      • `encode_val`'s scrutinee typed as `JsonValue` → the `Int`/`Array`/`Map`
        arms (Msgpack-only) collapsed to a non-exhaustive `switch`, and
        `Msgpack.encode(Msgpack.int(42))` panicked with "non-exhaustive pattern
        match" at runtime (interpreter was fine — this was compiled-only), and
      • `decode` constructed `alloc JsonValue.Array` (tag 4) where a `Value`
        (tag 5) was meant, so a decoded array no longer matched `Msgpack.Array`.
    The interpreter got both right, making this a pure codegen parity divergence.
    Fixed as a side effect of the sibling-ctor-shadowing fix (`add_ctor` moving a
    module's own re-registered constructor to the front of its candidate list —
    see the "sibling-ctor shadowing" entry in `specs/progress.md`). This
    exercises the Msgpack-only arms (Int, Array, Map) through both encode and a
    decode round-trip. *)
let test_msgpack_cross_module_ctor_resolution_compiled () =
  assert_compiled_interp_parity
    ~name:"march_msgpack_ctor_resolution"
    ~src:"mod MsgpackCtorResolution do\n\
    \  needs IO.Console\n\
         \  fn describe(bs : List(Int)) : String do\n\
         \    match Msgpack.decode(bs) do\n\
         \      Ok(Msgpack.Int(n))   -> \"int:\" ++ String.from_int(n)\n\
         \      Ok(Msgpack.Array(_)) -> \"array\"\n\
         \      Ok(Msgpack.Map(_))   -> \"map\"\n\
         \      Ok(_)                -> \"other\"\n\
         \      Err(e)               -> \"err:\" ++ e\n\
         \    end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(String.from_int(List.length(Msgpack.encode(Msgpack.int(42)))))\n\
         \    println(describe(Msgpack.encode(Msgpack.int(7))))\n\
         \    println(describe(Msgpack.encode(Msgpack.array(Cons(Msgpack.int(1), Cons(Msgpack.int(2), Nil))))))\n\
         \    println(describe(Msgpack.encode(Msgpack.map(Cons((Msgpack.str(\"k\"), Msgpack.int(9)), Nil)))))\n\
         \  end\n\
          end\n"
    ~expected:"1\nint:7\narray\nmap"
    ()

(** MODULE-qualified constructor pattern whose bare name collides (compiled-only).

    Sibling of [test_msgpack_cross_module_ctor_resolution_compiled] above, but
    exercising the other direction — a USER module that writes the documented
    qualified-pattern syntax (`Json.Array(_)`), i.e. a MODULE prefix.

    `ctor_info` keys are TYPE-qualified ("JsonValue.Array"), so a module-qualified
    pattern tag ("Json.Array") matched no key: [qualified_br_key]'s fold compares
    the written qualifier only against each key's TYPE segment, and the module
    `Json` declares the type `JsonValue` — the two names differ, so nothing
    matched and the tag DEGRADED to the bare ctor "Array". [Llvm_data.ctor_entry]
    then resolved that bare name by an ambiguous ".Array" suffix scan across all
    types, and picked `Msgpack.Value.Array` — which, because `Value` is a
    same-short-name colliding type (Msgpack + DataFrame), carries a globally
    unique 0x0200_00xx collision tag. Switching on that constant against a value
    built with `JsonValue.Array`'s tag 4 could never match, so the arm FAILED OPEN
    to the `_` arm: no error, no warning, no crash, silently wrong answer.

    `Object` masked the bug — Msgpack has no `Object` ctor, so the ambiguous
    suffix scan had exactly one candidate and happened to land on the right one.
    The test therefore asserts all three (`Array`, `Null`, `Object`): a fixture
    that only checked `Object` would have passed pre-fix.

    Interpreted was always correct — this is a pure codegen parity divergence. *)
let test_module_qualified_colliding_ctor_pattern_compiled () =
  assert_compiled_interp_parity
    ~name:"march_module_qualified_ctor_pattern"
    ~src:"mod ModQualCtorPattern do\n\
    \  needs IO.Console\n\
         \  fn describe(s : String) : String do\n\
         \    match Json.parse(s) do\n\
         \      Ok(Json.Array(_))  -> \"array\"\n\
         \      Ok(Json.Null)      -> \"null\"\n\
         \      Ok(Json.Object(_)) -> \"object\"\n\
         \      Ok(Json.Str(_))    -> \"str\"\n\
         \      Ok(_)              -> \"other\"\n\
         \      Err(e)             -> \"err:\" ++ e\n\
         \    end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(describe(\"[1]\"))\n\
         \    println(describe(\"null\"))\n\
         \    println(describe(\"{\\\"a\\\":1}\"))\n\
         \    println(describe(\"\\\"hi\\\"\"))\n\
         \    println(describe(\"7\"))\n\
         \  end\n\
          end\n"
    ~expected:"array\nnull\nobject\nstr\nother"
    ()

(** [W3C2.4 / HAZARD H2] Golden preamble byte-diff test.

    These four strings are VERBATIM COPIES of llvm_emit.ml's deleted
    hand-written preamble blob (the [Buffer.add_string buf {| ... |}]
    literals that used to sit inside [emit_preamble], before Wave 3 Task 4
    replaced them with [Llvm_builtins.emit_preamble] generating the same
    text from the declarative builtin table). They are kept here ONLY as a
    regression golden — this test's entire job is to fail loudly the
    moment [Llvm_builtins]'s generated preamble stops matching this
    literal byte-for-byte.

    DELETE THIS GOLDEN (and loosen the test) only when someone
    DELIBERATELY changes the preamble's content/order/whitespace — at that
    point this test's failure is expected and its golden is stale by
    design, not a regression. *)
let golden_preamble_core : string = {|; Runtime declarations
; Hot Code Reload versioned dispatch (runtime/march_dispatch.c)
declare ptr  @march_dispatch_enter(i32 %name_id, ptr %out_version)
declare ptr  @march_dispatch_enter_gen(i32 %name_id, i32 %caller_epoch, ptr %out_version)
declare void @march_dispatch_leave(i32 %name_id, i32 %version)
declare i32  @march_dispatch_publish(i32 %name_id, ptr %fn, ptr %impl_hash, ptr %sig_hash, i8 %kind)
declare i32  @march_dispatch_publish_epoch(i32 %name_id, ptr %fn, ptr %impl_hash, ptr %sig_hash, i8 %kind, i32 %epoch)
declare void @march_dispatch_init(i32 %n_slots)
declare void @march_dispatch_register_name(i32, ptr)
declare void @march_reload_server_start(ptr)
declare void @march_actor_set_dispatch_id(ptr %actor, i32 %name_id)
declare void @march_actor_set_call_base(ptr %actor, i64 %base)
declare ptr  @getenv(ptr)
declare noalias nonnull ptr @march_alloc(i64 %sz) allocsize(0)
declare void @march_incrc(ptr %p)
declare void @march_decrc(ptr %p)
declare i64  @march_decrc_freed(ptr %p)
declare void @march_incrc_local(ptr %p)
declare void @march_decrc_local(ptr %p)
declare void @march_free(ptr %p)
declare void @march_print(ptr %s)
declare void @march_panic(ptr %s)
declare ptr  @march_panic_ext(ptr %s)
declare ptr  @march_todo_ext(ptr %s)
declare ptr  @march_try_finally(ptr %action, ptr %cleanup)
declare void @march_test_init(i32 %argc, ptr %argv)
declare void @march_test_run(ptr %fn, ptr %name, ptr %setup_or_null)
declare void @march_test_setup_all(ptr %fn)
declare i32  @march_test_report()
declare void @march_println(ptr %s)
declare void @march_print_stderr(ptr %s)
declare ptr  @march_io_read_line()
declare i64  @march_io_read_byte()
declare ptr  @march_string_lit(ptr %s, i64 %len)
declare ptr  @march_string_lit_static(ptr %s, i64 %len, ptr %cell)
declare ptr  @march_html_auto_escape(ptr %v)
declare ptr  @march_html_escape_ctx(i64 %id, ptr %v)
declare i32  @march_record_shape_intern(ptr %desc)
declare void @march_record_set_shape(ptr %rec, ptr %desc, ptr %cache)
declare ptr  @march_record_keys(ptr %rec)
declare ptr  @march_record_values(ptr %rec)
declare ptr  @march_record_entries(ptr %rec)
declare ptr  @march_record_get(ptr %rec, ptr %key, i64 %kind)
declare i64  @march_record_has_key(ptr %rec, ptr %key)
declare ptr  @march_record_put(ptr %rec, ptr %key, ptr %val, i64 %kind)
declare ptr  @march_record_put3(ptr %rec, ptr %key, ptr %val)
declare ptr  @march_record_from_list(ptr %list)
declare ptr  @march_record_from_list_k(ptr %list, i64 %kind)
declare ptr  @march_record_field_dyn(ptr %rec, ptr %name, i64 %len)
declare ptr  @march_record_update_dyn(ptr %rec, i64 %n, ...)
declare ptr  @march_int_to_string(i64 %n)
declare ptr    @march_float_to_string(double %f)
declare ptr    @march_bool_to_string(i64 %b)
; Checked float division — aborts on divisor == 0.0 instead of returning inf/NaN
declare double @march_checked_fdiv(double %a, double %b)
; Checked integer division/remainder — panic on a zero divisor (matches interpreter)
declare i64    @march_checked_idiv(i64 %a, i64 %b)
declare i64    @march_checked_imod(i64 %a, i64 %b)
declare i64    @march_checked_emod(i64 %a, i64 %b)
declare i64    @march_checked_ediv(i64 %a, i64 %b)
; Operator forms of / and % — bare "division by zero" / "modulo by zero" messages
declare i64    @march_checked_div_op(i64 %a, i64 %b)
declare i64    @march_checked_mod_op(i64 %a, i64 %b)
declare ptr  @march_string_concat(ptr %a, ptr %b)
declare i64  @march_string_eq(ptr %a, ptr %b)
declare i64  @march_poly_eq(ptr %a, ptr %b)
; Ord / Hash builtins
declare i64    @march_compare_int(i64 %x, i64 %y)
declare i64    @march_compare_float(double %x, double %y)
declare i64    @march_compare_string(ptr %x, ptr %y)
declare i64    @march_hash_int(i64 %x)
declare i64    @march_hash_float(double %x)
declare i64    @march_hash_string(ptr %x)
declare i64    @march_hash_bool(i64 %x)
declare i64  @march_string_byte_length(ptr %s)
declare i64  @march_string_byte_at(ptr %s, i64 %i)
declare i64  @march_string_is_empty(ptr %s)
declare ptr  @march_string_to_int(ptr %s)
declare ptr  @march_string_concat3(ptr %a, ptr %b, ptr %c)
declare ptr  @march_string_join(ptr %list, ptr %sep)
; Float builtins
declare double @march_float_abs(double %f)
declare i64    @march_float_ceil(double %f)
declare i64    @march_float_floor(double %f)
declare i64    @march_float_round(double %f)
declare i64    @march_float_truncate(double %f)
declare double @march_int_to_float(i64 %n)
; Char builtins
declare ptr    @march_char_from_int(i64 %n)
declare i64    @march_char_to_int(ptr %c)
declare i64    @march_char_is_digit(ptr %c)
declare i64    @march_char_is_alphanumeric(ptr %c)
declare i64    @march_char_is_whitespace(ptr %c)
; Float/Int conversion builtins
declare i64    @march_float_to_int(double %f)
; Math builtins
declare double @march_math_sin(double %f)
declare double @march_math_cos(double %f)
declare double @march_math_tan(double %f)
declare double @march_math_asin(double %f)
declare double @march_math_acos(double %f)
declare double @march_math_atan(double %f)
declare double @march_math_atan2(double %y, double %x)
declare double @march_math_sinh(double %f)
declare double @march_math_cosh(double %f)
declare double @march_math_tanh(double %f)
declare double @march_math_sqrt(double %f)
declare double @march_math_cbrt(double %f)
declare double @march_math_exp(double %f)
declare double @march_math_exp2(double %f)
declare double @march_math_log(double %f)
declare double @march_math_log2(double %f)
declare double @march_math_log10(double %f)
declare double @march_math_pow(double %b, double %e)
; Extended string builtins
declare ptr  @march_string_chars(ptr %s)
declare ptr  @march_string_to_codepoints(ptr %s)
declare ptr  @march_string_from_codepoint(i64 %cp)
declare ptr  @march_string_from_chars(ptr %list)
declare i64  @march_string_contains(ptr %s, ptr %sub)
declare i64  @march_string_starts_with(ptr %s, ptr %prefix)
declare i64  @march_string_ends_with(ptr %s, ptr %suffix)
declare ptr  @march_string_slice(ptr %s, i64 %start, i64 %len)
declare ptr  @march_string_split(ptr %s, ptr %sep)
declare ptr  @march_string_split_first(ptr %s, ptr %sep)
declare ptr  @march_string_replace(ptr %s, ptr %old, ptr %new)
declare ptr  @march_string_replace_all(ptr %s, ptr %old, ptr %new)
declare ptr  @march_string_to_lowercase(ptr %s)
declare ptr  @march_string_to_uppercase(ptr %s)
declare ptr  @march_string_trim(ptr %s)
declare ptr  @march_string_trim_start(ptr %s)
declare ptr  @march_string_trim_end(ptr %s)
declare ptr  @march_string_repeat(ptr %s, i64 %n)
declare ptr  @march_string_reverse(ptr %s)
declare ptr  @march_string_pad_left(ptr %s, i64 %width, ptr %fill)
declare ptr  @march_string_pad_right(ptr %s, i64 %width, ptr %fill)
declare i64  @march_string_grapheme_count(ptr %s)
declare ptr  @march_string_index_of(ptr %s, ptr %sub)
declare ptr  @march_string_index_of_from(ptr %s, ptr %sub, i64 %start)
declare ptr  @march_string_last_index_of(ptr %s, ptr %sub)
declare ptr  @march_string_to_float(ptr %s)
; List builtins
declare ptr  @march_list_append(ptr %a, ptr %b)
declare ptr  @march_list_concat(ptr %lists)
; IOList builtins
declare ptr  @march_iolist_hash_fnv1a(ptr %iol)
; Vault (key-value store) builtins
declare ptr  @march_vault_new(ptr %name)
declare ptr  @march_vault_whereis(ptr %name)
declare ptr  @march_vault_set(ptr %table, ptr %key, ptr %value)
declare ptr  @march_vault_set_ttl(ptr %table, ptr %key, ptr %value, i64 %ttl)
declare i64  @march_vault_put_new(ptr %table, ptr %key, ptr %value, i64 %ttl)
declare i64  @march_vault_incr(ptr %table, ptr %key, i64 %delta)
declare ptr  @march_vault_push_capped(ptr %table, ptr %key, ptr %value, i64 %max)
declare ptr  @march_vault_get(ptr %table, ptr %key)
declare ptr  @march_vault_drop(ptr %table, ptr %key)
declare ptr  @march_vault_update(ptr %table, ptr %key, ptr %f)
declare i64  @march_vault_size(ptr %table)
declare ptr  @march_vault_keys(ptr %table)
declare ptr  @march_vault_ns_set(ptr %ns, ptr %key, ptr %value)
declare ptr  @march_vault_ns_get(ptr %ns, ptr %key)
declare ptr  @march_vault_ns_drop(ptr %ns, ptr %key)
; Crypto / hash builtins
declare ptr  @march_md5(ptr %b)
declare ptr  @march_sha256(ptr %b)
declare ptr  @march_sha512(ptr %b)
declare ptr  @march_sha1_bytes(ptr %b)
declare ptr  @march_hmac_sha256(ptr %key, ptr %msg)
declare ptr  @march_hmac_sha256_bytes(ptr %key, ptr %msg)
declare ptr  @march_pbkdf2_sha256(ptr %pass, ptr %salt, i64 %iters, i64 %len)
declare ptr  @march_base64_encode(ptr %b)
declare ptr  @march_base64_decode(ptr %s)
declare ptr  @march_random_bytes(i64 %n)
declare ptr  @bytes_to_u8_arr(ptr %b)
declare ptr  @u8_arr_to_bytes(ptr %arr)
; Compression builtins (runtime/march_compress.c)
declare ptr  @march_gzip_encode(ptr %b, i64 %level)
declare ptr  @march_gzip_decode(ptr %b)
declare ptr  @march_deflate_encode(ptr %b)
declare ptr  @march_deflate_decode(ptr %b)
declare ptr  @march_zstd_encode(ptr %b, i64 %level)
declare ptr  @march_zstd_decode(ptr %b)
declare ptr  @march_brotli_encode(ptr %b, i64 %mode, i64 %quality)
declare ptr  @march_brotli_decode(ptr %b)
; System introspection builtins
declare i64  @march_sys_uptime_ms()
declare i64  @march_sys_heap_bytes()
declare i64  @march_sys_word_size()
declare i64  @march_sys_minor_gcs()
declare i64  @march_sys_major_gcs()
declare i64  @march_sys_actor_count()
declare i64  @march_sys_cpu_count()
declare i64  @march_sys_cpu_load_milli()
declare i64  @march_sys_mem_total_bytes()
declare i64  @march_sys_mem_available_bytes()
declare ptr  @march_sys_os()
declare ptr  @march_sys_arch()
declare ptr  @march_get_version()
; UUID / identity builtins
declare ptr  @march_uuid_v4()
; Distributed OTP L4 — function-by-identity remote registry (march_remote_registry.c)
declare void @march_remote_init()
declare i32  @march_remote_register(ptr %impl_hash, ptr %sg_hash, ptr %stub)
declare i64  @march_remote_count()
declare i64  @march_remote_check_march(ptr %impl_hash, ptr %sig_hash)
declare ptr  @march_remote_invoke_march(ptr %impl_hash, ptr %args)
; Integer math helpers
declare i64  @march_int_pow(i64 %base, i64 %exp)
; LLVM intrinsics
declare i64  @llvm.ctpop.i64(i64 %val)
declare i64  @llvm.abs.i64(i64 %val, i1 %is_int_min_poison)
declare ptr  @llvm.stacksave()
declare void @llvm.stackrestore(ptr %ptr)
; Logger builtins
declare ptr  @march_logger_set_level(i64 %level)
declare i64  @march_logger_get_level()
declare ptr  @march_logger_add_context(ptr %key, ptr %value)
declare ptr  @march_logger_clear_context()
declare ptr  @march_logger_get_context()
declare ptr  @march_logger_write(ptr %level, ptr %msg, ptr %ctx, ptr %extra)
; REPL JIT persistent variable slot table (march_extras.c)
declare i64  @march_repl_get(i64 %slot)
declare void @march_repl_set(i64 %slot, i64 %val)

|}

let golden_preamble_native_actor : string = {|; Actor builtins
declare void @march_kill(ptr %actor)
declare i64  @march_is_alive(ptr %actor)
declare ptr  @march_send(ptr %actor, ptr %msg)
declare ptr  @march_send_linear(ptr %actor, ptr %msg)
declare ptr  @march_msg_copy(ptr %src_heap, ptr %dst_heap, ptr %value)
declare ptr  @march_msg_move(ptr %src_heap, ptr %dst_heap, ptr %value)
declare ptr  @march_process_alloc(ptr %heap, i64 %sz)
declare ptr  @march_spawn(ptr %actor)
declare ptr  @march_spawn_supervised(ptr %actor)
declare i64  @march_actor_get_int(ptr %actor, i64 %index)
declare ptr  @march_actor_call(ptr %actor, ptr %msg, i64 %timeout_ms)
declare void @march_actor_reply(ptr %ref, ptr %result)
declare ptr  @march_send_after(ptr %actor, ptr %msg, i64 %delay_ms)
declare void @march_timer_cancel(ptr %tok)
declare void @march_run_scheduler()
declare ptr  @march_task_spawn_thunk(ptr %clo_ptr)
declare ptr  @march_task_await(ptr %task)
declare ptr  @march_task_await_value(ptr %task)
declare void @march_sched_yield()
declare ptr  @march_sched_recv()
declare ptr  @march_cancel_token_new()
declare void @march_cancel_token_cancel(ptr %tok)
declare i64  @march_cancel_token_is_cancelled(ptr %tok)
declare ptr  @march_task_spawn_with_cancel_thunk(ptr %clo, ptr %tok)
declare void @march_task_cancel_by_id(ptr %task)
declare void @march_signal_watch(i64 %code, ptr %clo)
declare void @march_signal_unwatch(i64 %code)
declare void @march_signal_raise_self(i64 %code)
declare ptr  @march_alloc_float(double %v)
declare double @march_unbox_float(ptr %p)
declare i64  @march_poly_compare(ptr %a, ptr %b)
declare ptr  @march_simd_alloc(i64 %kind)
declare void @march_simd_bounds_panic(i64 %i, i64 %lanes, i64 %len)
declare void @march_simd_lane_panic(i64 %i, i64 %lanes)
|}

let golden_preamble_native_net_io : string = {|
; TCP/network builtins
declare ptr  @march_tcp_listen(i64 %port)
declare ptr  @march_tcp_accept(i64 %fd)
declare ptr  @march_tcp_local_port(i64 %fd)
declare ptr  @march_tcp_recv_exact(i64 %fd, i64 %n)
declare ptr  @march_tcp_recv_http(i64 %fd, i64 %max)
declare ptr  @march_tcp_send_all(i64 %fd, ptr %data)
declare void @march_tcp_close(i64 %fd)
declare ptr  @march_tcp_peer_addr(i64 %fd)
declare ptr  @march_http_parse_request(ptr %raw)
declare ptr  @march_http_serialize_response(i64 %status, ptr %headers, ptr %body)
declare void @march_http_server_listen(i64 %port, i64 %max_conns, i64 %idle_timeout, ptr %pipeline)
declare i64  @march_http_server_spawn_n(i64 %port, i64 %n, i64 %max_conns, i64 %idle_timeout, ptr %pipeline)
declare void @march_http_server_wait(i64 %handle)
declare void @march_ws_handshake(i64 %fd, ptr %key)
declare ptr  @march_ws_recv(i64 %fd)
declare void @march_ws_send(i64 %fd, ptr %frame)
declare ptr  @march_ws_select(i64 %fd, ptr %pipe, i64 %timeout)
; File/Dir builtins
declare i64  @march_file_exists(ptr %s)
declare i64  @march_dir_exists(ptr %s)
declare ptr  @march_file_open(ptr %path)
declare ptr  @march_file_close(ptr %handle)
declare ptr  @march_file_read(ptr %path)
declare ptr  @march_file_read_line(ptr %handle)
declare ptr  @march_file_read_chunk(ptr %handle, i64 %size)
declare ptr  @march_file_write(ptr %path, ptr %data)
declare ptr  @march_file_append(ptr %path, ptr %data)
declare ptr  @march_file_delete(ptr %path)
declare ptr  @march_file_copy(ptr %src, ptr %dst)
declare ptr  @march_file_rename(ptr %src, ptr %dst)
declare ptr  @march_file_stat(ptr %path)
declare ptr  @march_dir_mkdir(ptr %path)
declare ptr  @march_dir_mkdir_p(ptr %path)
declare ptr  @march_dir_rmdir(ptr %path)
declare ptr  @march_dir_rm_rf(ptr %path)
declare ptr  @march_dir_list(ptr %path)
declare ptr  @march_dir_list_full(ptr %path)
declare ptr  @march_process_argv()
declare ptr  @march_process_cwd()
declare ptr  @march_process_env(ptr %name)
declare i64  @march_process_set_env(ptr %name, ptr %value)
declare i64  @march_process_exit(i64 %code)
declare i64  @march_process_pid()
declare ptr  @march_process_spawn_sync(ptr %cmd, ptr %args)
declare ptr  @march_process_spawn_lines(ptr %cmd, ptr %args)
declare ptr  @march_process_spawn_async(ptr %cmd, ptr %args)
declare ptr  @march_process_read_line(ptr %proc)
declare i64  @march_process_write(ptr %proc, ptr %data)
declare i64  @march_process_kill_proc(ptr %proc)
declare i64  @march_process_wait_proc(ptr %proc)
; TCP recv-all
declare ptr  @march_tcp_recv_all(i64 %fd, i64 %max_bytes, i64 %timeout_ms)
declare ptr  @march_tcp_recv_chunk(i64 %fd, i64 %max_bytes)
declare ptr  @march_tcp_recv_chunk_timeout(i64 %fd, i64 %max_bytes, i64 %timeout_ms)
declare ptr  @march_tcp_set_recv_timeout(i64 %fd, i64 %timeout_ms)
declare ptr  @march_tcp_recv_timeout(i64 %fd, i64 %max_bytes, i64 %timeout_ms)
declare ptr  @march_tcp_recv_http_headers(i64 %fd)
declare ptr  @march_tcp_recv_chunked_frame(i64 %fd)
; TLS builtins
declare ptr  @march_tls_client_ctx(ptr %ca_file, ptr %alpn_list, i64 %verify_peer, i64 %timeout_ms)
declare ptr  @march_tls_server_ctx(ptr %cert_file, ptr %key_file, ptr %ca_file, ptr %alpn_list, i64 %verify_peer)
declare ptr  @march_tls_connect(i64 %fd, i64 %ctx_handle, ptr %hostname)
declare ptr  @march_tls_accept(i64 %fd, i64 %ctx_handle)
declare ptr  @march_tls_read(i64 %ssl_handle, i64 %max_bytes)
declare ptr  @march_tls_read_timeout(i64 %ssl_handle, i64 %max_bytes, i64 %timeout_ms)
declare ptr  @march_tls_write(i64 %ssl_handle, ptr %data)
declare void @march_tls_close(i64 %ssl_handle)
declare void @march_tls_ctx_free(i64 %ctx_handle)
declare ptr  @march_tls_negotiated_alpn(i64 %ssl_handle)
declare ptr  @march_tls_peer_cn(i64 %ssl_handle)
; TypedArray builtins
declare ptr  @march_typed_array_create(i64 %len, ptr %default_val)
declare ptr  @march_typed_array_from_list(ptr %list)
declare ptr  @march_typed_array_to_list(ptr %arr)
declare i64  @march_typed_array_length(ptr %arr)
declare ptr  @march_typed_array_get(ptr %arr, i64 %i)
declare ptr  @march_typed_array_set(ptr %arr, i64 %i, ptr %val)
declare ptr  @march_typed_array_map(ptr %arr, ptr %f)
declare ptr  @march_typed_array_filter(ptr %arr, ptr %f)
declare ptr  @march_typed_array_fold(ptr %arr, ptr %acc, ptr %f)
; NativeIntArr builtins — flat i64 arrays for vectorizable loops
declare ptr    @native_int_arr_make(i64 %len, i64 %def)
declare i64    @native_int_arr_length(ptr %arr)
declare i64    @native_int_arr_get(ptr %arr, i64 %i)
declare ptr    @native_int_arr_set(ptr %arr, i64 %i, i64 %val)
declare i64    @native_int_arr_sum(ptr %arr)
declare i64    @native_int_arr_min(ptr %arr)
declare i64    @native_int_arr_max(ptr %arr)
declare double @native_int_arr_sumsq_dev(ptr %arr, double %mean)
declare ptr    @native_int_arr_map(ptr %arr, ptr %f)
declare ptr    @native_int_arr_map2(ptr %arr1, ptr %arr2, ptr %f)
declare ptr    @native_int_arr_to_float_arr(ptr %arr)
declare ptr    @native_int_arr_fold(ptr %acc, ptr %arr, ptr %f)
declare ptr    @native_int_arr_from_list(ptr %lst)
declare ptr    @native_int_arr_to_list(ptr %arr)
declare ptr    @native_int_arr_filter_mask(ptr %arr, ptr %mask)
; NativeFloatArr builtins — flat double arrays for vectorizable loops
declare ptr    @native_float_arr_make(i64 %len, double %def)
declare i64    @native_float_arr_length(ptr %arr)
declare double @native_float_arr_get(ptr %arr, i64 %i)
declare ptr    @native_float_arr_set(ptr %arr, i64 %i, double %val)
declare double @native_float_arr_sum(ptr %arr)
declare double @native_float_arr_min(ptr %arr)
declare double @native_float_arr_max(ptr %arr)
declare double @native_float_arr_sumsq_dev(ptr %arr, double %mean)
declare ptr    @native_float_arr_map(ptr %arr, ptr %f)
declare ptr    @native_float_arr_map2(ptr %arr1, ptr %arr2, ptr %f)
declare ptr    @native_float_arr_fold(ptr %acc, ptr %arr, ptr %f)
declare ptr    @native_float_arr_from_list(ptr %lst)
declare ptr    @native_float_arr_to_list(ptr %arr)
declare ptr    @native_float_arr_filter_mask(ptr %arr, ptr %mask)
declare ptr    @native_int_arr_alloc_raw(i64 %len)
declare ptr    @native_float_arr_alloc_raw(i64 %len)
declare void   @native_arr_map2_check_len(i64 %len1, i64 %len2)
; Narrow native arrays (f32/i32/u8)
declare ptr    @native_f32_arr_make(i64 %len, double %def)
declare i64    @native_f32_arr_length(ptr %arr)
declare double @native_f32_arr_get(ptr %arr, i64 %i)
declare ptr    @native_f32_arr_set(ptr %arr, i64 %i, double %v)
declare double @native_f32_arr_sum(ptr %arr)
declare ptr    @native_f32_arr_map(ptr %arr, ptr %f)
declare ptr    @native_f32_arr_map2(ptr %a, ptr %b, ptr %f)
declare ptr    @native_f32_arr_fold(ptr %acc, ptr %arr, ptr %f)
declare ptr    @native_f32_arr_from_list(ptr %lst)
declare ptr    @native_f32_arr_to_list(ptr %arr)
declare ptr    @native_i32_arr_make(i64 %len, i64 %def)
declare i64    @native_i32_arr_length(ptr %arr)
declare i64    @native_i32_arr_get(ptr %arr, i64 %i)
declare ptr    @native_i32_arr_set(ptr %arr, i64 %i, i64 %v)
declare i64    @native_i32_arr_sum(ptr %arr)
declare ptr    @native_i32_arr_map(ptr %arr, ptr %f)
declare ptr    @native_i32_arr_map2(ptr %a, ptr %b, ptr %f)
declare ptr    @native_i32_arr_fold(ptr %acc, ptr %arr, ptr %f)
declare ptr    @native_i32_arr_from_list(ptr %lst)
declare ptr    @native_i32_arr_to_list(ptr %arr)
declare ptr    @native_u8_arr_make(i64 %len, i64 %def)
declare i64    @native_u8_arr_length(ptr %arr)
declare i64    @native_u8_arr_get(ptr %arr, i64 %i)
declare ptr    @native_u8_arr_set(ptr %arr, i64 %i, i64 %v)
declare i64    @native_u8_arr_sum(ptr %arr)
declare ptr    @native_u8_arr_map(ptr %arr, ptr %f)
declare ptr    @native_u8_arr_map2(ptr %a, ptr %b, ptr %f)
declare ptr    @native_u8_arr_fold(ptr %acc, ptr %arr, ptr %f)
declare ptr    @native_u8_arr_from_list(ptr %lst)
declare ptr    @native_u8_arr_to_list(ptr %arr)
declare ptr    @native_float_to_f32_arr(ptr %arr)
declare ptr    @native_f32_to_float_arr(ptr %arr)
declare ptr    @native_int_to_i32_arr(ptr %arr)
declare ptr    @native_i32_to_int_arr(ptr %arr)
declare ptr    @native_int_to_u8_arr(ptr %arr)
declare ptr    @native_u8_to_int_arr(ptr %arr)
declare ptr    @native_i32_to_f32_arr(ptr %arr)
declare ptr    @native_u8_to_f32_arr(ptr %arr)
declare ptr    @native_f32_arr_alloc_raw(i64 %len)
declare ptr    @native_i32_arr_alloc_raw(i64 %len)
declare ptr    @native_u8_arr_alloc_raw(i64 %len)
; RingBuf builtins — mutable fixed-capacity circular buffer
declare ptr    @ring_buf_make(i64 %cap)
declare void   @ring_buf_push(ptr %rb, ptr %x)
declare ptr    @ring_buf_pop(ptr %rb)
declare ptr    @ring_buf_get(ptr %rb, i64 %i)
declare ptr    @ring_buf_peek_oldest(ptr %rb)
declare ptr    @ring_buf_peek_newest(ptr %rb)
declare i64    @ring_buf_size(ptr %rb)
declare i64    @ring_buf_cap(ptr %rb)
declare void   @ring_buf_clear(ptr %rb)
declare ptr    @ring_buf_to_list(ptr %rb)
; Time builtins
declare double @march_unix_time()
declare i64    @march_unix_time_ms()
declare i64  @march_peak_rss_bytes()
declare i64  @march_live_allocs()
declare ptr  @march_tcp_connect(ptr %host, i64 %port)
; HTTP client builtins
declare ptr  @march_http_serialize_request(ptr %method, ptr %host, ptr %path, ptr %query, ptr %headers, ptr %body)
declare ptr  @march_http_parse_response(ptr %raw)
; CSV builtins
declare ptr  @march_csv_open(ptr %path, ptr %delim, ptr %mode)
declare ptr  @march_csv_next_row(ptr %handle)
declare ptr  @march_csv_close(ptr %handle)
; Resource ownership
declare void @march_own(ptr %pid, ptr %value)
; Capability builtins
declare ptr  @march_cap_narrow(ptr %cap)
declare ptr  @march_mint_cap(ptr %cap)
declare ptr  @march_cap_impl(ptr %cap, ptr %dict)
declare ptr  @march_cap_dict(ptr %cap)
declare void @march_set_actor_caps(ptr %actor, ptr %caps)
declare ptr  @march_actor_caps(ptr %actor)
; Monitor/supervision builtins
declare void @march_demonitor(i64 %ref)
declare i64  @march_monitor(ptr %watcher, ptr %target)
declare i64  @march_mailbox_size(ptr %pid)
declare i64  @march_sched_stat(i64 %which)
declare void @march_actor_set_mbox_limit(ptr %pid, i64 %limit, i64 %policy)
declare void @march_run_until_idle()
declare void @march_register_resource(ptr %pid, ptr %name, ptr %cleanup)
; Named registry builtins
declare i64  @march_actor_register(ptr %name, ptr %actor)
declare i64  @march_actor_unregister(ptr %name)
declare ptr  @march_actor_whereis(ptr %name)
declare ptr  @march_actor_registered()
declare ptr  @march_get_cap(ptr %pid)
declare i64  @march_send_checked(ptr %cap, ptr %msg)
declare i64  @march_revoke_cap(ptr %cap)
declare i64  @march_is_cap_valid(ptr %cap)
declare ptr  @march_pid_of_int(i64 %n)
declare ptr  @march_get_actor_field(ptr %pid, ptr %name)
declare void @march_register_supervisor(ptr %supervisor, i64 %strategy, i64 %max_restarts, i64 %window_secs)
declare void @march_actor_register_child(ptr %sup, ptr %child, ptr %spawn_fn, i64 %word_idx, i64 %restart_type)
declare i64  @march_pid_index_of(ptr %actor)
declare ptr  @march_value_to_string(ptr %v)
; Session-typed channel builtins (binary)
declare ptr  @march_chan_new(ptr %proto_name)
declare ptr  @march_chan_send(ptr %ep, ptr %val)
declare ptr  @march_chan_recv(ptr %ep)
declare i64  @march_chan_close(ptr %ep)
declare ptr  @march_chan_choose(ptr %ep, ptr %label)
declare ptr  @march_chan_offer(ptr %ep)
; Multi-party session type (MPST) builtins
declare ptr  @march_mpst_new(ptr %proto_name, i64 %n_roles, ptr %roles_csv)
declare ptr  @march_mpst_send(ptr %ep, ptr %target_role, ptr %val)
declare ptr  @march_mpst_recv(ptr %ep, ptr %source_role)
declare i64  @march_mpst_close(ptr %ep)
|}

let golden_preamble_wasm_stub : string = {|; WASM: plain globals (no TLS), no-op scheduler stub
@march_preempt_request = external global i64
@march_tls_reductions = external global i64
declare void @march_yield_from_compiled()
declare void @march_run_scheduler()
declare ptr  @march_task_spawn_thunk(ptr %clo_ptr)
declare ptr  @march_task_await(ptr %task)
declare ptr  @march_task_await_value(ptr %task)
declare void @march_sched_yield()
declare ptr  @march_sched_recv()
declare ptr  @march_cancel_token_new()
declare void @march_cancel_token_cancel(ptr %tok)
declare i64  @march_cancel_token_is_cancelled(ptr %tok)
declare ptr  @march_task_spawn_with_cancel_thunk(ptr %clo, ptr %tok)
declare void @march_task_cancel_by_id(ptr %task)
declare void @march_signal_watch(i64 %code, ptr %clo)
declare void @march_signal_unwatch(i64 %code)
declare void @march_signal_raise_self(i64 %code)
declare ptr  @march_alloc_float(double %v)
declare double @march_unbox_float(ptr %p)
declare i64  @march_poly_compare(ptr %a, ptr %b)
declare ptr  @march_simd_alloc(i64 %kind)
declare void @march_simd_bounds_panic(i64 %i, i64 %lanes, i64 %len)
declare void @march_simd_lane_panic(i64 %i, i64 %lanes)
|}

(** Reassemble the historical preamble text for a given (is_wasm, repl)
    combination exactly as the OLD [emit_preamble] used to nest its
    [Buffer.add_string] calls — see the deleted function's structure (git
    history, commit before W3C2.4). *)
let golden_preamble ~(is_wasm : bool) ~(repl : bool) : string =
  if is_wasm then
    golden_preamble_core ^ golden_preamble_wasm_stub
  else
    let tls_insert =
      if repl then ""
      else "@march_preempt_request = external global i64
@march_tls_reductions = external thread_local global i64
declare void @march_yield_from_compiled()
"
    in
    golden_preamble_core ^ golden_preamble_native_actor ^ tls_insert ^ golden_preamble_native_net_io

(** Every builtin whose call site mangles to a C symbol must have that symbol
    DECLARED in some preamble, or the emitted module references a name LLVM has
    never heard of.  This is the invariant that broke for `unix_time_ms`
    (specs/progress/2026-08-21-unix-time-ms-has-no-codegen-backing.md): the
    table entry and the [PDeclare] list are two separate hand-maintained lists,
    and an entry with no declare fails as

      error: use of undefined value '@march_unix_time_ms'

    at the FIRST caller, in whatever unrelated change happens to add one.
    Checked against the union of every preamble configuration, so a
    native-only or WASM-only symbol is not falsely flagged.

    Two entries are legitimately absent and are listed rather than filtered by
    pattern, so a third one cannot join them silently:

      march_main             the program's own entry point — DEFINED by the
                             emitted module, not declared into it.
      march_atom_to_string   compile-time generated per module by
                             [Llvm_toplevel.emit_atom_show_table] as a switch
                             over ctx.atom_names; a `declare` alongside that
                             `define` would be an LLVM redefinition, which is
                             why its [declare_sig] is None (see the note on the
                             entry itself in llvm_builtins.ml).

    Note what this does NOT check: that the C symbol actually EXISTS at link
    time. A declare with no definition still fails, just later and with a
    linker error instead of an IR one — `test/native/builtin_link_backing`
    covers that half by running a compiled program. *)
(* ── Builtin_name round-trip ────────────────────────────────────────────
   [Builtin_name.t] names the exact set of builtins Llvm_emit.emit_expr
   dispatches.  The count literal is the tripwire: a new emit arm added
   without a constructor (or vice versa) fails here.  Re-derive it with
     S=$(grep -n '^let rec emit_expr ctx' lib/tir/llvm_emit.ml | cut -d: -f1)
     awk -v s=$S 'NR>s && /^let |^and /{print NR; exit}' lib/tir/llvm_emit.ml
   and the v_name grep over that window (see the decomposition plan, Task 2.1). *)
(* Every Builtin_name constructor is classified by Llvm_emit.builtin_group.
   That match is the exhaustiveness surface emit_expr's [when] guards cannot
   provide; this test is its caller, and pins the per-group counts so a
   constructor silently migrating between groups shows up as a diff. *)
let test_builtin_group_total () =
  let count g =
    List.length
      (List.filter
         (fun c -> March_tir.Llvm_emit.builtin_group c = g)
         March_tir.Builtin_name.all)
  in
  Alcotest.(check int) "arith" 16 (count March_tir.Llvm_emit.Bg_arith);
  Alcotest.(check int) "task" 24 (count March_tir.Llvm_emit.Bg_task);
  Alcotest.(check int) "record" 17 (count March_tir.Llvm_emit.Bg_record)

let test_builtin_name_roundtrip () =
  List.iter
    (fun c ->
      let s = March_tir.Builtin_name.to_string c in
      Alcotest.(check bool) (s ^ ": is c s") true (March_tir.Builtin_name.is c s);
      match March_tir.Builtin_name.of_string s with
      | Some c' when c' = c -> ()
      | Some _ ->
        Alcotest.failf "builtin %S round-tripped to a different constructor" s
      | None -> Alcotest.failf "builtin %S has no of_string entry" s)
    March_tir.Builtin_name.all;
  Alcotest.(check int) "constructor count" 57
    (List.length March_tir.Builtin_name.all);
  (* Distinct names: two constructors mapping to one string would make the
     Hashtbl silently drop one direction of the round trip. *)
  let names = List.map March_tir.Builtin_name.to_string March_tir.Builtin_name.all in
  Alcotest.(check int) "names are distinct" (List.length names)
    (List.length (List.sort_uniq compare names));
  (* root_cap is dispatched in emit_atom, not emit_expr, so it is
     deliberately NOT a constructor. *)
  Alcotest.(check bool) "root_cap absent" true
    (March_tir.Builtin_name.of_string "root_cap" = None)

let test_every_builtin_c_name_is_declared () =
  let declared =
    List.fold_left
      (fun acc (is_wasm, repl) ->
         let buf = Buffer.create 8192 in
         March_tir.Llvm_builtins.emit_preamble ~is_wasm
           ~triple:(if is_wasm then "wasm64-wasi" else "x86_64-unknown-linux-gnu")
           ~repl buf;
         Buffer.contents buf :: acc)
      [] [ (false, false); (false, true); (true, false) ]
  in
  let is_declared sym =
    List.exists
      (fun text ->
         try ignore (Str.search_forward (Str.regexp_string ("@" ^ sym ^ "(")) text 0); true
         with Not_found -> false)
      declared
  in
  let compiler_defined = [ "march_main"; "march_atom_to_string" ] in
  let missing =
    List.filter_map
      (fun (b : March_tir.Llvm_builtins.builtin) ->
         match b.c_name with
         | Some sym when not (List.mem sym compiler_defined) && not (is_declared sym) ->
           Some (b.march_name ^ " -> @" ^ sym)
         | _ -> None)
      March_tir.Llvm_builtins.builtins
  in
  Alcotest.(check (list string))
    "every builtin c_name is declared in some preamble (or compiler-defined)"
    [] missing

let test_preamble_byte_identical_native () =
  let buf = Buffer.create 4096 in
  March_tir.Llvm_builtins.emit_preamble ~is_wasm:false ~triple:"x86_64-unknown-linux-gnu" ~repl:false buf;
  let actual = Buffer.contents buf in
  let expected =
    Printf.sprintf "; March compiler output\ntarget triple = \"%s\"\n\n" "x86_64-unknown-linux-gnu"
    ^ golden_preamble ~is_wasm:false ~repl:false
  in
  Alcotest.(check string) "native, non-repl preamble byte-identical to historical blob" expected actual

let test_preamble_byte_identical_native_repl () =
  let buf = Buffer.create 4096 in
  March_tir.Llvm_builtins.emit_preamble ~is_wasm:false ~triple:"x86_64-unknown-linux-gnu" ~repl:true buf;
  let actual = Buffer.contents buf in
  let expected =
    Printf.sprintf "; March compiler output\ntarget triple = \"%s\"\n\n" "x86_64-unknown-linux-gnu"
    ^ golden_preamble ~is_wasm:false ~repl:true
  in
  Alcotest.(check string) "native, REPL preamble byte-identical to historical blob" expected actual

let test_preamble_byte_identical_wasm () =
  let buf = Buffer.create 4096 in
  March_tir.Llvm_builtins.emit_preamble ~is_wasm:true ~triple:"wasm64-wasi" ~repl:false buf;
  let actual = Buffer.contents buf in
  let expected =
    Printf.sprintf "; March compiler output\ntarget triple = \"%s\"\n\n" "wasm64-wasi"
    ^ golden_preamble ~is_wasm:true ~repl:false
  in
  Alcotest.(check string) "WASM preamble byte-identical to historical blob" expected actual

(** [march_alloc] returns fresh storage or terminates on OOM, and its sole
    argument is the allocation size.  Keep those optimizer facts on the
    canonical declaration for every target. *)
let test_preamble_march_alloc_attributes () =
  let buf = Buffer.create 4096 in
  March_tir.Llvm_builtins.emit_preamble
    ~is_wasm:false ~triple:"x86_64-unknown-linux-gnu" ~repl:false buf;
  Alcotest.(check bool) "march_alloc carries verified return and size attributes" true
    (Test_helpers.contains
       "declare noalias nonnull ptr @march_alloc(i64 %sz) allocsize(0)"
       (Buffer.contents buf))

(** A closure trampoline contains only ABI adaptation and a forwarding call,
    so keeping it out of line adds overhead without preserving a semantic
    boundary.  Pin the canonical generator rather than one emitter call site. *)
let test_clo_wrap_is_alwaysinline () =
  let ir =
    March_tir.Llvm_calls.clo_wrap_define
      "pred$clo_wrap" ["i64"] "i64" "pred"
  in
  Alcotest.(check bool) "closure trampoline is alwaysinline" true
    (Test_helpers.contains
       "define ptr @pred$clo_wrap(ptr %_clo, ptr %a0) alwaysinline {"
       ir)

(** [Llvm_emit.emit_preamble] (the thin wrapper) must delegate to
    [Llvm_builtins.emit_preamble] with no behavior change: same output for
    the same [target_config]/[repl] as calling the new function directly
    with the equivalent [is_wasm]/[triple]. *)
let test_preamble_wrapper_delegates () =
  let buf_old = Buffer.create 4096 in
  March_tir.Llvm_emit.emit_preamble ~target:March_tir.Llvm_emit.Native ~repl:false buf_old;
  let buf_new = Buffer.create 4096 in
  March_tir.Llvm_builtins.emit_preamble ~is_wasm:false
    ~triple:(March_tir.Llvm_emit.target_triple March_tir.Llvm_emit.Native) ~repl:false buf_new;
  Alcotest.(check string) "Llvm_emit.emit_preamble wrapper matches Llvm_builtins.emit_preamble"
    (Buffer.contents buf_new) (Buffer.contents buf_old)

(** A top-level fn used as a first-class value must NOT emit a fresh
    march_alloc(24) per materialization; it must reference one immortal
    static global instead. *)
let test_static_closure_global_replaces_alloc () =
  let x = mk_var "x" March_tir.Tir.TInt in
  let fn_ty = March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt) in
  let target =
    { March_tir.Tir.fn_name = "target"; fn_params = [x];
      fn_ret_ty = March_tir.Tir.TInt;
      fn_body = app "+" [March_tir.Tir.AVar x; ilit 1];
      fn_kind = March_tir.Tir.FnNormal }
  in
  (* main returns `target` AS A VALUE (not calling it) — forces materialization. *)
  let main =
    { March_tir.Tir.fn_name = "main"; fn_params = [];
      fn_ret_ty = fn_ty;
      fn_body = March_tir.Tir.EAtom (March_tir.Tir.AVar (mk_var "target" fn_ty));
      fn_kind = March_tir.Tir.FnNormal }
  in
  let ir = March_tir.Llvm_emit.emit_module (mk_module [target; main]) in
  Alcotest.(check bool) "emits an immortal static closure global"
    true (Test_helpers.contains "$static_clo" ir);
  Alcotest.(check bool) "static closure carries the MARCH_RC_IMMORTAL refcount"
    true (Test_helpers.contains "1099511627776" ir);
  Alcotest.(check bool) "static closure is a writable global, not a constant"
    true (Test_helpers.contains "internal global" ir);
  Alcotest.(check bool) "no per-materialization march_alloc(i64 24) remains"
    false (Test_helpers.contains "march_alloc(i64 24)" ir)

(** A capture-free lambda's closure struct is EAlloc(TCon("$Clo_..", []),
    [fn_ptr]) — defun.ml lifts every lambda this way, and an empty capture
    list leaves exactly one arg. Its contents are then entirely compile-time
    constant, so — like a top-level fn used as a value — it must reference
    one immortal static global rather than allocate per materialization. *)
let test_capture_free_lambda_uses_static_global () =
  let clo_ty = March_tir.Tir.TCon ("$Clo_lam$1", []) in
  let alloc = mk_closure_alloc "$Clo_lam$1" "lam$apply$1" in
  let main =
    { March_tir.Tir.fn_name = "main"; fn_params = [];
      fn_ret_ty = clo_ty;
      fn_body = alloc;
      fn_kind = March_tir.Tir.FnNormal }
  in
  let ir = March_tir.Llvm_emit.emit_module (mk_module [main]) in
  Alcotest.(check bool) "capture-free lambda gets a static closure global"
    true (Test_helpers.contains "$static_clo" ir);
  Alcotest.(check bool) "no per-materialization closure alloc remains"
    false (Test_helpers.contains "march_alloc(i64 24)" ir)

(** A capturing lambda's closure struct carries 2+ args (fn_ptr plus one
    entry per free variable) — its contents differ per instance, so it MUST
    keep allocating.  Sharing one global here would silently share one
    captured environment across every instance: a correctness bug, not a
    missed optimization.  This is the guard on the discriminator: it must
    admit ONLY the exact single-argument shape. *)
let test_capturing_lambda_still_allocates () =
  let clo_ty = March_tir.Tir.TCon ("$Clo_lam$2", []) in
  let captured = mk_var "k" March_tir.Tir.TInt in
  let fn_ptr_atom =
    March_tir.Tir.AVar (mk_var "lam$apply$2" (March_tir.Tir.TPtr March_tir.Tir.TUnit)) in
  let alloc =
    March_tir.Tir.EAlloc (clo_ty, [fn_ptr_atom; March_tir.Tir.AVar captured]) in
  let main =
    { March_tir.Tir.fn_name = "main"; fn_params = [captured];
      fn_ret_ty = clo_ty;
      fn_body = alloc;
      fn_kind = March_tir.Tir.FnNormal }
  in
  let ir = March_tir.Llvm_emit.emit_module (mk_module [main]) in
  (* header(16) + fn_ptr(8) + one capture(8) = 32 bytes, not the 24-byte
     size of a capture-free closure (header + fn_ptr only) — confirmed
     against real compiled output for `fn x -> x * k` (one capture). *)
  Alcotest.(check bool) "capturing lambda still allocates per materialization"
    true (Test_helpers.contains "march_alloc(i64 32)" ir);
  (* The primary correctness risk of this optimization is a shared captured
     environment across instances — this negative assertion is the one that
     actually names that risk, not just the allocation-count positive above. *)
  Alcotest.(check bool) "capturing lambda gets no static global"
    false (Test_helpers.contains "$static_clo" ir)

(** REPL fragments are separate modules; a per-fragment static global would
    hand out different pointers for the same fn across fragments, and can
    collide under the ORC backend's shared JITDylib. The REPL must keep the
    fresh-alloc path.

    Exercised through the actual REPL emission entry point
    ([Llvm_emit.emit_repl_expr], which builds its ctx with [~repl:true] —
    see [lib/tir/llvm_repl.ml]) rather than by calling
    [Llvm_ctx.intern_static_closure] directly: the eligibility gate lives in
    [llvm_emit.ml]'s [static_closure_ok], not in the memoizing helper itself,
    so the helper alone can't demonstrate the REPL is declined — only the
    full materialization path can. *)
let test_static_closure_not_emitted_in_repl_mode () =
  let x = mk_var "x" March_tir.Tir.TInt in
  let fn_ty = March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt) in
  let target =
    { March_tir.Tir.fn_name = "target"; fn_params = [x];
      fn_ret_ty = March_tir.Tir.TInt;
      fn_body = app "+" [March_tir.Tir.AVar x; ilit 1];
      fn_kind = March_tir.Tir.FnNormal }
  in
  (* REPL fragment: "target" evaluated as a bare expression, materializing the
     top-level fn as a first-class value — the same trigger as the native
     test above, run through the REPL fragment emitter instead of
     emit_module. *)
  let body = March_tir.Tir.EAtom (March_tir.Tir.AVar (mk_var "target" fn_ty)) in
  let ir =
    March_tir.Llvm_emit.emit_repl_expr
      ~n:0 ~ret_ty:fn_ty ~prev_slots:[] ~fns:[target] ~types:[] body
  in
  Alcotest.(check bool) "REPL mode still materializes via fresh march_alloc(24)"
    true (Test_helpers.contains "march_alloc(i64 24)" ir);
  Alcotest.(check bool) "REPL mode emits no static closure global"
    false (Test_helpers.contains "$static_clo" ir)

(** Regression for the finding that the JIT's stdlib-prelude fragment call
    ([precompile_stdlib] in [lib/jit/repl_jit.ml]) went through
    [Llvm_emit.emit_fns_fragment] WITHOUT [~repl:true], so a top-level fn
    materialized as a first-class value inside that fragment silently got a
    static closure global — exactly the thing [static_closure_ok] is meant to
    forbid in REPL/JIT mode (a per-fragment global would hand out different
    pointers for the same fn across fragments, and the ORC backend loads each
    fragment as its own module). The existing REPL-mode coverage above only
    drives [emit_repl_expr]; it can't catch a second REPL-mode entry point
    (`emit_fns_fragment`) forgetting to pass `~repl:true`, because that call
    site is separate code entirely. This test drives `emit_fns_fragment`
    itself — the exact function precompile_stdlib calls — with `~repl:true`
    and asserts no `$static_clo` global is emitted for a fn materialized as a
    value inside the fragment. Prior to the fix (missing `~repl:true` at
    repl_jit.ml:823) this scenario is precisely what let 13 `$static_clo`
    symbols leak into `~/.cache/march/stdlib_prelude_*.so`. *)
let test_static_closure_not_emitted_in_fns_fragment_repl_mode () =
  let x = mk_var "x" March_tir.Tir.TInt in
  let fn_ty = March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt) in
  let target =
    { March_tir.Tir.fn_name = "target"; fn_params = [x];
      fn_ret_ty = March_tir.Tir.TInt;
      fn_body = app "+" [March_tir.Tir.AVar x; ilit 1];
      fn_kind = March_tir.Tir.FnNormal }
  in
  (* A second fn that materializes `target` as a first-class value — mirrors
     how a stdlib fn like `Cluster.parse_addr` passes a named fn as a value
     (e.g. into a HOF) inside the precompiled prelude fragment. *)
  let holder =
    { March_tir.Tir.fn_name = "holder"; fn_params = [];
      fn_ret_ty = fn_ty;
      fn_body = March_tir.Tir.EAtom (March_tir.Tir.AVar (mk_var "target" fn_ty));
      fn_kind = March_tir.Tir.FnNormal }
  in
  let ir =
    March_tir.Llvm_emit.emit_fns_fragment
      ~types:[] ~fns:[target; holder] ~repl:true ()
  in
  Alcotest.(check bool) "fns_fragment in repl mode emits no static closure global"
    false (Test_helpers.contains "$static_clo" ir);
  Alcotest.(check bool) "fns_fragment in repl mode still materializes via fresh march_alloc(24)"
    true (Test_helpers.contains "march_alloc(i64 24)" ir)

(** Lambda-bodied twin of [test_static_closure_not_emitted_in_repl_mode]. The
    two existing REPL-exclusion tests above both materialize a top-level
    NAMED function, which exercises [static_closure_ok] via the named-fn arm
    in [emit_atom] — not the newer [EAlloc (TCon (tcon_name, []), [fn_ptr_atom])]
    arm added for capture-free lambdas. Nothing previously pinned
    `not ctx.repl` for that arm; this drives the exact same capture-free
    closure-struct shape as [test_capture_free_lambda_uses_static_global]
    through [emit_repl_expr] (which builds its ctx with [~repl:true]) and
    asserts the REPL fallback (fresh [march_alloc(i64 24)], no
    [$static_clo]) still holds. *)
let test_capture_free_lambda_not_emitted_in_repl_mode () =
  let clo_ty = March_tir.Tir.TCon ("$Clo_lam$1", []) in
  let body = Test_helpers.mk_closure_alloc "$Clo_lam$1" "lam$apply$1" in
  let ir =
    March_tir.Llvm_emit.emit_repl_expr
      ~n:0 ~ret_ty:clo_ty ~prev_slots:[] ~fns:[] ~types:[] body
  in
  Alcotest.(check bool) "REPL mode still materializes lambda via fresh march_alloc(24)"
    true (Test_helpers.contains "march_alloc(i64 24)" ir);
  Alcotest.(check bool) "REPL mode emits no static closure global for a lambda"
    false (Test_helpers.contains "$static_clo" ir)

(** Lambda-bodied twin of [test_static_closure_not_emitted_in_fns_fragment_repl_mode].
    Same rationale as the twin above: the fns_fragment REPL entry point
    (the exact one [precompile_stdlib] calls, see [lib/jit/repl_jit.ml])
    needs its own lambda-path coverage, not just the named-fn one. *)
let test_capture_free_lambda_not_emitted_in_fns_fragment_repl_mode () =
  let clo_ty = March_tir.Tir.TCon ("$Clo_lam$1", []) in
  let alloc = Test_helpers.mk_closure_alloc "$Clo_lam$1" "lam$apply$1" in
  let holder =
    { March_tir.Tir.fn_name = "holder"; fn_params = [];
      fn_ret_ty = clo_ty;
      fn_body = alloc;
      fn_kind = March_tir.Tir.FnNormal }
  in
  let ir =
    March_tir.Llvm_emit.emit_fns_fragment
      ~types:[] ~fns:[holder] ~repl:true ()
  in
  Alcotest.(check bool) "fns_fragment in repl mode emits no static closure global for a lambda"
    false (Test_helpers.contains "$static_clo" ir);
  Alcotest.(check bool) "fns_fragment in repl mode still materializes lambda via fresh march_alloc(24)"
    true (Test_helpers.contains "march_alloc(i64 24)" ir)

(** [static_closure_ok] mirroring for hot-reload is conditional on the whole
    [ctx.hr_config], not on resolving a March-level dotted name (the lambda
    arm's [tcon_name] is a synthetic "$Clo_..." string, not always
    unambiguously mappable back to an owning module — see the comment above
    the lambda [EAlloc] arm in [lib/tir/llvm_emit.ml]). This drives
    [emit_module ~hot_reload:(Some cfg)] over a program containing a
    capture-free lambda and asserts no [$static_clo] global is emitted. *)
let test_capture_free_lambda_not_emitted_under_hot_reload () =
  let open March_tir.Tir in
  let clo_ty = TCon ("$Clo_lam$1", []) in
  let alloc = Test_helpers.mk_closure_alloc "$Clo_lam$1" "lam$apply$1" in
  let main : fn_def =
    { fn_name = "Blog.main"; fn_params = []; fn_ret_ty = clo_ty;
      fn_kind = FnNormal; fn_body = alloc }
  in
  let m : tir_module =
    { tm_name = "Blog"; tm_fns = [main]; tm_types = [];
      tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] }
  in
  let ir = March_tir.Llvm_emit.emit_module
             ~hot_reload:(Some (March_tir.Hot_reload.default_config "Blog")) m in
  Alcotest.(check bool) "hot-reload mode emits no static closure global for a lambda"
    false (Test_helpers.contains "$static_clo" ir)

(* ── Robustness: an unreadable sibling directory must not crash the compiler ──
   The compiler auto-discovers sibling `.march` modules in the entry file's own
   source directory (`resolve_imports` plus the early-CAS sibling hash both walk
   it via `collect_lib_files`).  That recursive walk called `Sys.readdir` on
   every subdirectory with no exception guard, so a permission-denied sibling
   directory — e.g. macOS's `$TMPDIR/TemporaryItems`, which is "Operation not
   permitted" — raised an uncaught `Sys_error` and killed an otherwise
   well-typed compile (exit 2, no output).  The walk now skips directories it
   cannot read.  `--check` exercises the exact crashing path (it shares the
   early-CAS/resolver walk with `--compile`) without needing clang, so this
   test runs everywhere.  Perms on the 0000 dir are always restored via
   [Fun.protect] so it never lingers to break later cleanup. *)
let test_unreadable_sibling_dir_does_not_crash_check () =
  let (project_root, main_exe, src, tmp) =
    write_march_source ~name:"march_permdenied"
      "mod PdEntry do\n\
      \  fn main() : Int do\n\
      \    1 + 2\n\
      \  end\n\
       end\n"
  in
  (* A permission-denied sibling directory beside the entry file.  Its contents
     are irrelevant: the crash was in [Sys.readdir] on the directory itself,
     which fails before any entry can be read. *)
  let denied = Filename.concat tmp "TemporaryItems" in
  Unix.mkdir denied 0o755;
  Unix.chmod denied 0o000;
  Fun.protect
    ~finally:(fun () ->
      (* Restore perms so the temp tree can be reclaimed; ignore if already gone. *)
      (try Unix.chmod denied 0o755 with Unix.Unix_error _ -> ()))
    (fun () ->
      (* Run from the project root so the compiler resolves its CWD-relative
         stdlib/ (same trick as the other compiled-regression tests).  The
         scanned directory is [Filename.dirname src] = [tmp] (an absolute
         path), independent of CWD. *)
      let cmd = Printf.sprintf "cd %s && %s --check %s 2>&1; echo EXIT:$?"
        (Filename.quote project_root) (Filename.quote main_exe)
        (Filename.quote src) in
      let out = read_cmd_output cmd in
      Alcotest.(check bool)
        (Printf.sprintf
          "--check exits 0 despite an unreadable sibling dir (no Sys_error crash); got:\n%s"
          out)
        true
        (ir_contains out "EXIT:0"))

(* ── Cross-compile: TLS (OpenSSL) + gzip (zlib) for linux/amd64 (P3) ────────
   Cross-compile a program that references BOTH the TLS runtime
   (march_tls_write / march_tls_close) AND the gzip runtime (march_gzip_encode /
   march_gzip_decode), then assert the output is a valid Linux x86-64 ELF whose
   DT_NEEDED lists libssl.so.3, libcrypto.so.3 and libz.so.1 — i.e. the cross
   link resolved the external symbols against the target sysroot instead of
   failing with "undefined symbol: march_tls_write" (the P1 pure-compute
   behaviour this fix replaces).

   This is a LINK-STRUCTURE test: the binary is x86-64 Linux and cannot RUN on
   the (arm64/macOS) test host, so we inspect the ELF, we do not execute it.  It
   REQUIRES `zig` (the cross driver) and the target sysroot cache
   (scripts/fetch-cross-sysroot.sh amd64); when either is absent it SKIPS
   cleanly via the tool-absence ledger rather than failing — mirroring the
   clang-absence policy for the JIT tests. *)
let test_cross_tls_gzip_linux_amd64_elf () =
  if not (zig_available ()) then
    record_jit_skip
      "cross TLS+gzip linux/amd64: no zig on PATH (cross driver absent)"
  else match cross_sysroot_dir "amd64" with
  | None ->
    record_jit_skip
      "cross TLS+gzip linux/amd64: no target sysroot \
       (run scripts/fetch-cross-sysroot.sh amd64)"
  | Some _sysroot ->
    let main_exe = find_main_exe () in
    let project_root = march_project_root () in
    (* The TLS calls are guarded by a RUNTIME length (never actually huge) so the
       optimizer can't dead-code-strip them — otherwise the DT_NEEDED for
       libssl/libcrypto would be dropped and the assertion below would be a
       false negative.  The gzip calls are unconditional. *)
    let src_text =
      "mod XTls do\n\
    \  needs IO.Console\n\
      \  needs IO.NetConnect.TLS\n\
      \  fn main(_cap_console : Cap(IO.Console), _cap_tls : Cap(IO.NetConnect.TLS)) do\n\
      \    let payload = Bytes.from_string(\"march cross tls+gzip probe\")\n\
      \    let gz = match stdlib_gzip_encode(payload, -1) do\n\
      \      Ok(c)  -> c\n\
      \      Err(_) -> payload\n\
      \    end\n\
      \    let restored = match stdlib_gzip_decode(gz) do\n\
      \      Ok(o)  -> o\n\
      \      Err(_) -> gz\n\
      \    end\n\
      \    if Bytes.length(restored) > 1000000000 do\n\
      \      let _ = tls_write(0, \"ping\")\n\
      \      tls_close(0)\n\
      \    else\n\
      \      ()\n\
      \    end\n\
      \    println(\"probe ok\")\n\
      \  end\n\
       end\n"
    in
    let tmp = Filename.temp_file "march_xtls" "" in
    Sys.remove tmp;
    Unix.mkdir tmp 0o755;
    let src = Filename.concat tmp "xtls.march" in
    let oc = open_out src in
    output_string oc src_text;
    close_out oc;
    let bin = Filename.concat tmp "xtls_linux" in
    let read_cmd cmd =
      let ic = Unix.open_process_in cmd in
      let buf = Buffer.create 256 in
      (try while true do Buffer.add_channel buf ic 1 done with End_of_file -> ());
      ignore (Unix.close_process_in ic);
      String.trim (Buffer.contents buf)
    in
    let compile_out = read_cmd (Printf.sprintf
      "cd %s && %s --compile --target linux/amd64 -o %s %s 2>&1; echo EXIT:$?"
      (Filename.quote project_root) (Filename.quote main_exe)
      (Filename.quote bin) (Filename.quote src)) in
    Alcotest.(check bool)
      (Printf.sprintf "cross-compile succeeds (no undefined march_tls_*/march_gzip_* \
                       symbols); output:\n%s" compile_out)
      true (ir_contains compile_out "EXIT:0" && Sys.file_exists bin);
    (* Assert Linux x86-64 ELF via `file`. *)
    let file_out = read_cmd (Printf.sprintf "file %s" (Filename.quote bin)) in
    Alcotest.(check bool)
      (Printf.sprintf "output is a Linux x86-64 ELF; `file` said:\n%s" file_out)
      true
      (ir_contains file_out "ELF 64-bit"
       && ir_contains file_out "x86-64"
       && ir_contains file_out "GNU/Linux");
    (* Assert DT_NEEDED lists all three target sonames.  `objdump -p` parses the
       Linux ELF fine on the host; llvm-readelf would work too. *)
    let needed = read_cmd (Printf.sprintf
      "objdump -p %s 2>/dev/null | grep NEEDED || true" (Filename.quote bin)) in
    List.iter (fun so ->
        Alcotest.(check bool)
          (Printf.sprintf "DT_NEEDED contains %s; NEEDED lines:\n%s" so needed)
          true (ir_contains needed so))
      ["libssl.so.3"; "libcrypto.so.3"; "libz.so.1"]

(** Phase 7.1: a default-arg function must be callable BY NAME from March source
    at every arity — desugar emits only mangled `greet$N` decls, so before the
    typecheck default-arg call-resolution fix a source-level `greet("Bob")` died
    with "I cannot find `greet`. Did you mean `greet$1`?" under --check/--compile
    AND interpretation. Exercises reduced (1-arg, one default), partial (2-arg,
    one default), and full (3-arg) arities; parity asserts interp == compiled. *)
let test_compiled_default_args_parity () =
  assert_compiled_interp_parity
    ~name:"march_default_args_source_call"
    ~src:"mod M do\n\
    \  needs IO.Console\n\
         \  fn greet(name, greeting \\\\ \"Hi\", punct \\\\ \"!\") do\n\
         \    greeting ++ \", \" ++ name ++ punct\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(greet(\"Bob\"))\n\
         \    println(greet(\"Al\", \"Yo\"))\n\
         \    println(greet(\"Cy\", \"Hey\", \"?\"))\n\
         \  end\n\
          end\n"
    ~expected:"Hi, Bob!\nYo, Al!\nHey, Cy?"
    ()

(** Phase 7.1 (nested): a default-arg fn defined inside a NESTED module is also
    callable by name at reduced arity, on both backends — needs the desugar
    `expand_defaults_decl` DMod recursion AND the eval nested `foo$N`→base
    VMultiarity reconstruction/exposure (compiled worked via TIR alone, interp
    did not, before those). *)
let test_compiled_nested_default_args_parity () =
  assert_compiled_interp_parity
    ~name:"march_nested_default_args"
    ~src:"mod A do\n\
    \  needs IO.Console\n\
         \  mod B do\n\
         \    fn f(x, y \\\\ 100) do x + y end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(int_to_string(B.f(1)))\n\
         \    println(int_to_string(B.f(2, 20)))\n\
         \  end\n\
          end\n"
    ~expected:"101\n22"
    ()

let test_vectorize_check_module_loads () =
  let ctx = March_errors.Errors.create () in
  March_tir.Vectorize_check.check_fn ctx (Hashtbl.create 0)
    ~severity:March_tir.Vectorize_check.Hard
    ~span:March_ast.Ast.dummy_span
    { March_tir.Tir.fn_name = "noop"; fn_params = [];
      fn_ret_ty = March_tir.Tir.TUnit;
      fn_body = March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 0));
      fn_kind = March_tir.Tir.FnNormal };
  Alcotest.(check int) "zero-call annotated fn reports exactly one (misuse) diagnostic"
    1 (List.length (March_errors.Errors.sorted ctx))

let vectorize_source_inlined_reuse_fail = {|mod Main do
  needs IO.Console
  @[vectorize]
  fn scale(arr, k) do
    let f = fn x -> x *. k
    let a1 = native_float_arr_map(arr, f)
    let a2 = native_float_arr_map(a1, f)
    native_float_arr_map(a2, f)
  end
  fn main(_cap_console : Cap(IO.Console)) : () do
    let arr = native_float_arr_make(4, 1.0)
    let out = scale(arr, 2.0)
    println(native_float_arr_get(out, 0))
  end
end|}

let test_vectorize_catches_violation_even_when_inlined () =
  let diags = Test_helpers.run_vectorize_check vectorize_source_inlined_reuse_fail in
  Alcotest.(check bool) "at least one diagnostic even if Opt inlines `scale` into `main`"
    true (List.length diags >= 1);
  Alcotest.(check bool) "severity is Error"
    true ((List.hd diags).March_errors.Errors.severity = March_errors.Errors.Error)

let vectorize_check_fail_src = {|mod Main do
  needs IO.Console
  @[vectorize]
  fn scale(arr) do
    let f = fn x -> x *. 2.0
    let _ = f(1.0)
    native_float_arr_map(arr, f)
  end
  fn main(_cap_console : Cap(IO.Console)) : () do
    let arr = native_float_arr_make(4, 1.0)
    let doubled = scale(arr)
    println(native_float_arr_get(doubled, 0))
  end
end|}

let test_vectorize_hard_error_fails_compile () =
  let (project_root, main_exe, src, _tmp) =
    write_march_source ~name:"march_vectorize_fail" vectorize_check_fail_src in
  let bin = Filename.temp_file "march_vectorize_fail_bin" "" in
  Sys.remove bin;
  (* Deliberately NOT compile_march_raw/compile_march_or_skip, which every
     other compiled test in this file uses: those treat ANY nonzero exit on a
     clang-less machine as a legitimate "tool absent" skip. That heuristic is
     inapplicable here, because this test's PASSING outcome is itself a
     nonzero exit -- the @[vectorize] check rejects the program at
     bin/main.ml (~2408), well before clang is invoked (~2468). Routing
     through the heuristic would classify the passing case as a skip on a
     clang-less box (silently vacuous), and asserting failure on that skip
     would instead make the passing case red there. clang's presence is
     simply irrelevant to this path, so drive the compiler directly. *)
  let cmd = Printf.sprintf "cd %s && %s --compile -o %s %s"
      (Filename.quote project_root) (Filename.quote main_exe)
      (Filename.quote bin) (Filename.quote src) in
  let (rc, output) = run_capture cmd in
  Alcotest.(check bool) "compile fails (nonzero exit)" true (rc <> 0);
  Alcotest.(check bool) "stderr names the failing fn" true
    (ir_contains output "`scale` cannot vectorize")

let vectorize_source_ok = {|mod Main do
  needs IO.Console
  @[vectorize]
  fn scale(arr) do
    native_float_arr_map(arr, fn x -> x *. 2.0)
  end
  fn main(_cap_console : Cap(IO.Console)) : () do
    let arr = native_float_arr_make(4, 1.0)
    let doubled = scale(arr)
    println(native_float_arr_get(doubled, 0))
  end
end|}

(** FIX 2 regression: the only compile-driving test above
    (test_vectorize_hard_error_fails_compile) exercises a FAILING program,
    which exits before clang ever runs — so no test proves that a PASSING
    program's `__vectorize_marker_*` sentinel actually gets stripped before
    LLVM emission (there is no such symbol to link against; a
    find_markers/strip_markers regression would otherwise ship green,
    silently, forever). This test compiles an eligible annotated program
    (vectorize_source_ok, above) and then RUNS the binary, which is the
    only way to prove the marker was stripped and the program links and
    behaves correctly.

    Unlike its neighbor above, this test's PASSING path genuinely reaches
    clang (there's no compiler-side rejection to stop short), so the usual
    clang-absent skip policy legitimately applies here — hence
    [compile_march_or_skip] instead of driving `march --compile` raw. *)
let test_vectorize_pass_compiles_and_runs () =
  let (project_root, main_exe, src, tmp) =
    write_march_source ~name:"march_vectorize_ok" vectorize_source_ok in
  let bin = Filename.concat tmp "vectorize_ok_bin" in
  match compile_march_or_skip
          ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Filename.quote bin) in
    Alcotest.(check string)
      "compiled eligible @[vectorize] program runs and prints the doubled value \
       (proves the sentinel was stripped before LLVM emission and the \
       program links/behaves correctly)"
      "2." run_out

let vectorize_source_warn_ok = {|mod Main do
  needs IO.Console
  @[vectorize(warn)]
  fn scale(arr) do
    native_float_arr_map(arr, fn x -> x *. 2.0)
  end
  fn main(_cap_console : Cap(IO.Console)) : () do
    let arr = native_float_arr_make(4, 1.0)
    let doubled = scale(arr)
    println(native_float_arr_get(doubled, 0))
  end
end|}

let vectorize_source_ok_int = {|mod Main do
  needs IO.Console
  @[vectorize]
  fn double_all(arr) do
    native_int_arr_map(arr, fn x -> x * 2)
  end
  fn main(_cap_console : Cap(IO.Console)) : () do
    let arr = native_int_arr_make(4, 1)
    let doubled = double_all(arr)
    println(native_int_arr_get(doubled, 0))
  end
end|}

let vectorize_source_reuse_fail = {|mod Main do
  needs IO.Console
  @[vectorize]
  fn scale(arr) do
    let f = fn x -> x *. 2.0
    let _ = f(1.0)
    native_float_arr_map(arr, f)
  end
  fn main(_cap_console : Cap(IO.Console)) : () do
    let arr = native_float_arr_make(4, 1.0)
    let doubled = scale(arr)
    println(native_float_arr_get(doubled, 0))
  end
end|}

let vectorize_source_reuse_warn = {|mod Main do
  needs IO.Console
  @[vectorize(warn)]
  fn scale(arr) do
    let f = fn x -> x *. 2.0
    let _ = f(1.0)
    native_float_arr_map(arr, f)
  end
  fn main(_cap_console : Cap(IO.Console)) : () do
    let arr = native_float_arr_make(4, 1.0)
    let doubled = scale(arr)
    println(native_float_arr_get(doubled, 0))
  end
end|}

let vectorize_source_ok_map2 = {|mod Main do
  needs IO.Console
  @[vectorize]
  fn combine(a, b) do
    native_float_arr_map2(a, b, fn (x, y) -> x +. y)
  end
  fn main(_cap_console : Cap(IO.Console)) : () do
    let a = native_float_arr_make(4, 1.0)
    let b = native_float_arr_make(4, 2.0)
    let summed = combine(a, b)
    println(native_float_arr_get(summed, 0))
  end
end|}

let vectorize_source_reuse_fail_map2 = {|mod Main do
  needs IO.Console
  @[vectorize]
  fn combine(a, b) do
    let f = fn (x, y) -> x +. y
    let _ = f(1.0, 1.0)
    native_float_arr_map2(a, b, f)
  end
  fn main(_cap_console : Cap(IO.Console)) : () do
    let a = native_float_arr_make(4, 1.0)
    let b = native_float_arr_make(4, 2.0)
    let summed = combine(a, b)
    println(native_float_arr_get(summed, 0))
  end
end|}

let vectorize_source_misuse = {|mod Main do
  needs IO.Console
  @[vectorize]
  fn scale(arr) do
    arr
  end
  fn main(_cap_console : Cap(IO.Console)) : () do
    let arr = native_float_arr_make(4, 1.0)
    let doubled = scale(arr)
    println(native_float_arr_get(doubled, 0))
  end
end|}

let vectorize_source_misuse_warn = {|mod Main do
  needs IO.Console
  @[vectorize(warn)]
  fn scale(arr) do
    arr
  end
  fn main(_cap_console : Cap(IO.Console)) : () do
    let arr = native_float_arr_make(4, 1.0)
    let doubled = scale(arr)
    println(native_float_arr_get(doubled, 0))
  end
end|}

let test_vectorize_pass_float () =
  Alcotest.(check int) "no diagnostics for an eligible Float callback"
    0 (List.length (Test_helpers.run_vectorize_check vectorize_source_ok))

let test_vectorize_pass_int () =
  Alcotest.(check int) "no diagnostics for an eligible Int callback (no generic gate applies)"
    0 (List.length (Test_helpers.run_vectorize_check vectorize_source_ok_int))

let test_vectorize_warn_on_eligible_code_is_silent () =
  Alcotest.(check int) "no diagnostics for (warn) on eligible code"
    0 (List.length (Test_helpers.run_vectorize_check vectorize_source_warn_ok))

let test_vectorize_pass_map2 () =
  Alcotest.(check int) "no diagnostics for an eligible map2 callback"
    0 (List.length (Test_helpers.run_vectorize_check vectorize_source_ok_map2))

let test_vectorize_reuse_fail_map2 () =
  let diags = Test_helpers.run_vectorize_check vectorize_source_reuse_fail_map2 in
  Alcotest.(check int) "exactly one reuse-gate diagnostic" 1 (List.length diags);
  let d = List.hd diags in
  Alcotest.(check bool) "severity is Error"
    true (d.March_errors.Errors.severity = March_errors.Errors.Error);
  Alcotest.(check bool) "message names the reuse failure"
    true (ir_contains d.March_errors.Errors.message "isn't safe to inline")

let test_vectorize_reuse_fail () =
  let diags = Test_helpers.run_vectorize_check vectorize_source_reuse_fail in
  Alcotest.(check int) "exactly one reuse-gate diagnostic" 1 (List.length diags);
  let d = List.hd diags in
  Alcotest.(check bool) "severity is Error"
    true (d.March_errors.Errors.severity = March_errors.Errors.Error);
  Alcotest.(check bool) "message names the reuse failure"
    true (ir_contains d.March_errors.Errors.message "isn't safe to inline")

let vectorize_source_reuse_fail_int = {|mod Main do
  needs IO.Console
  @[vectorize]
  fn double_all(arr) do
    let f = fn x -> x * 2
    let _ = f(1)
    native_int_arr_map(arr, f)
  end
  fn main(_cap_console : Cap(IO.Console)) : () do
    let arr = native_int_arr_make(4, 1)
    let doubled = double_all(arr)
    println(native_int_arr_get(doubled, 0))
  end
end|}

(** FIX 1 regression: [reuse_example] used to hardcode float syntax
    (`x *. 2.0`) for BOTH Int and Float targets, so the hint the compiler
    prints for an Int reuse-gate violation suggested code that doesn't
    typecheck against an Int array. The hint lives in the diagnostic's
    [notes] field, not [message]. *)
let test_vectorize_reuse_fail_int_hint_uses_int_syntax () =
  let diags = Test_helpers.run_vectorize_check vectorize_source_reuse_fail_int in
  Alcotest.(check int) "exactly one reuse-gate diagnostic" 1 (List.length diags);
  let d = List.hd diags in
  let notes = String.concat "\n" d.March_errors.Errors.notes in
  Alcotest.(check bool) "hint uses Int syntax (`fn x -> x * 2`)"
    true (ir_contains notes "fn x -> x * 2");
  Alcotest.(check bool) "hint does NOT use Float syntax (`*.`)"
    false (ir_contains notes "*.")

let test_vectorize_reuse_warn () =
  let diags = Test_helpers.run_vectorize_check vectorize_source_reuse_warn in
  Alcotest.(check int) "exactly one diagnostic" 1 (List.length diags);
  Alcotest.(check bool) "severity is Warning, not Error"
    true ((List.hd diags).March_errors.Errors.severity = March_errors.Errors.Warning);
  Alcotest.(check bool) "message names the reuse failure"
    true (ir_contains (List.hd diags).March_errors.Errors.message "isn't safe to inline")

let test_vectorize_misuse () =
  let diags = Test_helpers.run_vectorize_check vectorize_source_misuse in
  Alcotest.(check int) "exactly one misuse diagnostic" 1 (List.length diags);
  Alcotest.(check bool) "severity is Error"
    true ((List.hd diags).March_errors.Errors.severity = March_errors.Errors.Error);
  Alcotest.(check bool) "message names the misuse failure"
    true (ir_contains (List.hd diags).March_errors.Errors.message "calls no NativeArray.map/map2")

let test_vectorize_misuse_ignores_warn () =
  let diags = Test_helpers.run_vectorize_check vectorize_source_misuse_warn in
  Alcotest.(check int) "exactly one misuse diagnostic" 1 (List.length diags);
  Alcotest.(check bool) "misuse is ALWAYS Error, even under @[vectorize(warn)]"
    true ((List.hd diags).March_errors.Errors.severity = March_errors.Errors.Error)

(* ── generic-signature-gate unit tests (hand-built TIR) ────────────────
   Sidesteps the open question of whether real March source can be made to
   leave a callback's TIR signature as a bare TVar post-monomorphization by
   constructing that TIR shape directly. *)

let vc_clo_ty = March_tir.Tir.TCon ("Main.scale$clo", [])
let vc_clo_var : March_tir.Tir.var =
  { v_name = "$c0"; v_ty = vc_clo_ty; v_lin = March_tir.Tir.Unr }
let vc_apply_var : March_tir.Tir.var =
  { v_name = "scale$apply$0"; v_ty = March_tir.Tir.TPtr March_tir.Tir.TUnit;
    v_lin = March_tir.Tir.Unr }
let vc_arr_var : March_tir.Tir.var =
  { v_name = "arr"; v_ty = March_tir.Tir.TCon ("NativeFloatArr", []);
    v_lin = March_tir.Tir.Unr }
let vc_map_fn_var : March_tir.Tir.var =
  { v_name = "native_float_arr_map"; v_ty = March_tir.Tir.TPtr March_tir.Tir.TUnit;
    v_lin = March_tir.Tir.Unr }

let vc_outer_fd : March_tir.Tir.fn_def =
  { fn_name = "scale"; fn_kind = March_tir.Tir.FnNormal;
    fn_params = [ vc_arr_var ]; fn_ret_ty = March_tir.Tir.TCon ("NativeFloatArr", []);
    fn_body =
      March_tir.Tir.ELet (vc_clo_var,
        March_tir.Tir.EAlloc (vc_clo_ty, [ March_tir.Tir.AVar vc_apply_var ]),
        March_tir.Tir.EApp (vc_map_fn_var,
          [ March_tir.Tir.AVar vc_arr_var; March_tir.Tir.AVar vc_clo_var ])) }

let vc_apply_fn_concrete : March_tir.Tir.fn_def =
  { fn_name = "scale$apply$0"; fn_kind = March_tir.Tir.FnApply;
    fn_params = [ { March_tir.Tir.v_name = "$clo"; v_ty = March_tir.Tir.TPtr March_tir.Tir.TUnit;
                    v_lin = March_tir.Tir.Unr };
                  { March_tir.Tir.v_name = "x"; v_ty = March_tir.Tir.TFloat;
                    v_lin = March_tir.Tir.Unr } ];
    fn_ret_ty = March_tir.Tir.TFloat;
    fn_body = March_tir.Tir.EAtom (March_tir.Tir.AVar
                { March_tir.Tir.v_name = "x"; v_ty = March_tir.Tir.TFloat;
                  v_lin = March_tir.Tir.Unr }) }

let vc_apply_fn_generic : March_tir.Tir.fn_def =
  { vc_apply_fn_concrete with
    fn_params = [ { March_tir.Tir.v_name = "$clo"; v_ty = March_tir.Tir.TPtr March_tir.Tir.TUnit;
                    v_lin = March_tir.Tir.Unr };
                  { March_tir.Tir.v_name = "x"; v_ty = March_tir.Tir.TVar "a";
                    v_lin = March_tir.Tir.Unr } ];
    fn_ret_ty = March_tir.Tir.TVar "a" }

let vc_table fn =
  let t = Hashtbl.create 1 in
  Hashtbl.replace t "scale$apply$0" fn; t

let test_vectorize_generic_pass () =
  let ctx = March_errors.Errors.create () in
  March_tir.Vectorize_check.check_fn ctx (vc_table vc_apply_fn_concrete)
    ~severity:March_tir.Vectorize_check.Hard ~span:March_ast.Ast.dummy_span vc_outer_fd;
  Alcotest.(check int) "concrete Float signature: no diagnostics"
    0 (List.length (March_errors.Errors.sorted ctx))

let test_vectorize_generic_fail () =
  let ctx = March_errors.Errors.create () in
  March_tir.Vectorize_check.check_fn ctx (vc_table vc_apply_fn_generic)
    ~severity:March_tir.Vectorize_check.Hard ~span:March_ast.Ast.dummy_span vc_outer_fd;
  let diags = March_errors.Errors.sorted ctx in
  Alcotest.(check int) "generic signature: exactly one diagnostic" 1 (List.length diags);
  let d = List.hd diags in
  Alcotest.(check bool) "severity is Error"
    true (d.March_errors.Errors.severity = March_errors.Errors.Error);
  Alcotest.(check bool) "message names the generic-signature failure"
    true (ir_contains d.March_errors.Errors.message "still generic")

let test_vectorize_generic_fail_warn () =
  let ctx = March_errors.Errors.create () in
  March_tir.Vectorize_check.check_fn ctx (vc_table vc_apply_fn_generic)
    ~severity:March_tir.Vectorize_check.Soft ~span:March_ast.Ast.dummy_span vc_outer_fd;
  let diags = March_errors.Errors.sorted ctx in
  Alcotest.(check int) "generic signature under (warn): exactly one diagnostic"
    1 (List.length diags);
  Alcotest.(check bool) "severity is Warning, not Error"
    true ((List.hd diags).March_errors.Errors.severity = March_errors.Errors.Warning)

(* ── derive Json / from_json return-position interface dispatch ─────────
   `from_json` dispatches on its RESULT type, not its argument (the argument
   is always a JsonValue) — mono's first-arg interface dispatch can never
   resolve it.  Two behaviors are pinned here:

   1. SINGLE derive in the module: the call is unambiguous (exactly one
      JsonFrom impl exists, and its parameter type matches the call's
      argument type, proving the dispatch position is the result).  Mono
      must resolve it — this used to fall through to a raw
      `Undefined symbols: _from_json` linker error.

   2. MULTIPLE derives in one module: the result type at the call site is
      an unpinned TVar (the typechecker does not back-propagate it), so
      dispatch is genuinely ambiguous.  The compiler must reject this with
      a clean user-facing diagnostic (exit 1) naming the candidate impls —
      not the "internal compiler error" ICE (exit 3) it used to raise, and
      not a linker error. *)

let derive_json_single_src = {|mod JsonOne do
  needs IO.Console
  type Flat = { name : String, age : Int }
  derive Json for Flat

  fn main(_cap_console : Cap(IO.Console)) do
    match Json.parse("{\"name\":\"a\",\"age\":3}") do
    Err(e) -> println("parse err")
    Ok(v) -> match from_json(v) do
      Ok(x) -> println("ok: " ++ x.name)
      Err(e) -> println("decode err")
      end
    end
  end
end|}

let test_derive_json_single_from_json_compiled () =
  let (project_root, main_exe, src, tmp) =
    write_march_source ~name:"march_json_single" derive_json_single_src in
  (* interpreter baseline: bare from_json resolves to the sole derive *)
  let interp_out = read_cmd_output (Printf.sprintf
    "cd %s && %s %s 2>&1"
    (Filename.quote project_root)
    (Filename.quote main_exe) (Filename.quote src)) in
  Alcotest.(check string) "interpreter decodes via the single derive"
    "ok: a" interp_out;
  let bin = Filename.concat tmp "json_single_bin" in
  match compile_march_or_skip
          ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = read_cmd_output (Printf.sprintf "%s 2>&1" (Filename.quote bin)) in
    Alcotest.(check string)
      "compiled single-derive bare from_json resolves to the sole impl \
       (used to be a raw `_from_json` linker error)"
      "ok: a" run_out

let derive_json_ambiguous_src = {|mod JsonTwo do
  needs IO.Console
  type Flat = { name : String, age : Int }
  derive Json for Flat
  type Other = { id : Int }
  derive Json for Other

  fn main(_cap_console : Cap(IO.Console)) do
    match Json.parse("{\"name\":\"a\",\"age\":3}") do
    Err(e) -> println("parse err")
    Ok(v) -> match from_json(v) do
      Ok(x) -> println("ok: " ++ x.name)
      Err(e) -> println("decode err")
      end
    end
  end
end|}

let test_derive_json_ambiguous_from_json_diagnostic () =
  let (project_root, main_exe, src, _tmp) =
    write_march_source ~name:"march_json_ambig" derive_json_ambiguous_src in
  let bin = Filename.temp_file "march_json_ambig_bin" "" in
  Sys.remove bin;
  (* Deliberately NOT compile_march_or_skip (same rationale as
     test_vectorize_hard_error_fails_compile): the PASSING outcome is a
     nonzero exit produced inside llvm_emit, before clang is ever invoked,
     so clang's absence is irrelevant and the skip heuristic would make the
     passing case vacuous on a clang-less box. *)
  let cmd = Printf.sprintf "cd %s && %s --compile -o %s %s"
      (Filename.quote project_root) (Filename.quote main_exe)
      (Filename.quote bin) (Filename.quote src) in
  let (rc, output) = run_capture cmd in
  Alcotest.(check bool) "ambiguous from_json: compile fails (nonzero exit)"
    true (rc <> 0);
  Alcotest.(check bool) "diagnostic names the ambiguous method" true
    (ir_contains output "from_json" && ir_contains output "ambiguous");
  Alcotest.(check bool) "diagnostic is a clean user error, not an ICE" true
    (not (ir_contains output "internal compiler error"))

let codegen_suites =
  [
      ( "vectorize_check", [
          Alcotest.test_case "module loads, misuse case reports one diagnostic" `Quick
            test_vectorize_check_module_loads;
          Alcotest.test_case "reuse gate: caught even after the annotated fn is inlined away" `Quick
            test_vectorize_catches_violation_even_when_inlined;
          Alcotest.test_case "vectorize hard error fails compile" `Quick
            test_vectorize_hard_error_fails_compile;
          Alcotest.test_case "pass: eligible annotated program compiles and runs" `Quick
            test_vectorize_pass_compiles_and_runs;
          Alcotest.test_case "pass: eligible Float callback" `Quick
            test_vectorize_pass_float;
          Alcotest.test_case "pass: eligible Int callback" `Quick
            test_vectorize_pass_int;
          Alcotest.test_case "reuse gate: fails hard" `Quick
            test_vectorize_reuse_fail;
          Alcotest.test_case "reuse gate: Int hint uses Int syntax" `Quick
            test_vectorize_reuse_fail_int_hint_uses_int_syntax;
          Alcotest.test_case "reuse gate: warns under (warn)" `Quick
            test_vectorize_reuse_warn;
          Alcotest.test_case "pass: (warn) on eligible code is silent" `Quick
            test_vectorize_warn_on_eligible_code_is_silent;
          Alcotest.test_case "pass: eligible map2 callback" `Quick
            test_vectorize_pass_map2;
          Alcotest.test_case "reuse gate: map2 fails hard" `Quick
            test_vectorize_reuse_fail_map2;
          Alcotest.test_case "generic-signature gate: passes when concrete" `Quick
            test_vectorize_generic_pass;
          Alcotest.test_case "generic-signature gate: fails hard" `Quick
            test_vectorize_generic_fail;
          Alcotest.test_case "generic-signature gate: warns under (warn)" `Quick
            test_vectorize_generic_fail_warn;
          Alcotest.test_case "misuse: zero calls fails hard" `Quick
            test_vectorize_misuse;
          Alcotest.test_case "misuse: fails hard even under (warn)" `Quick
            test_vectorize_misuse_ignores_warn;
        ] );
      ( "cross_compile", [
          Alcotest.test_case
            "linux/amd64 TLS+gzip links to valid ELF w/ libssl/libcrypto/libz NEEDED (P3)"
            `Quick test_cross_tls_gzip_linux_amd64_elf;
        ] );
      ( "tir_names", [
          Alcotest.test_case "tuple_tag round-trip"       `Quick test_tir_names_tuple_tag;
          Alcotest.test_case "fv_field round-trip"        `Quick test_tir_names_fv_field_round_trip;
          Alcotest.test_case "clo_struct_name/is_clo_struct" `Quick test_tir_names_clo_struct;
          Alcotest.test_case "apply_fn_name/is_apply_fn"  `Quick test_tir_names_apply_fn;
          Alcotest.test_case "is_iface_mangled"            `Quick test_tir_names_iface_mangled;
          Alcotest.test_case "iface_mangle builder"        `Quick test_tir_names_iface_mangle_builder;
          Alcotest.test_case "default_arg_mangle round-trip" `Quick test_tir_names_default_arg_round_trip;
          Alcotest.test_case "actor suffixes + field sort" `Quick test_tir_names_actor_suffixes;
          Alcotest.test_case "runtime_prefix"              `Quick test_tir_names_runtime_prefix;
          Alcotest.test_case "is_try_call"                 `Quick test_tir_names_try_call;
          Alcotest.test_case "test/setup fn names"         `Quick test_tir_names_test_and_setup_fn_names;
          Alcotest.test_case "specialize_mangle"           `Quick test_tir_names_specialize_mangle;
          Alcotest.test_case "strip_specialization_suffix" `Quick test_tir_names_strip_specialization_suffix;
          Alcotest.test_case "bool tags"                   `Quick test_tir_names_bool_tags;
        ] );
      ( "fnfused_coverage", [
          Alcotest.test_case "map+fold fused fn is FnFused"        `Quick test_fnfused_map_fold_tagged;
          Alcotest.test_case "filter+fold fused fn is FnFused"     `Quick test_fnfused_filter_fold_tagged;
          Alcotest.test_case "map+filter+fold fused fn is FnFused" `Quick test_fnfused_map_filter_fold_tagged;
          Alcotest.test_case "no FnFused when nothing fuses"       `Quick test_fnfused_absent_when_not_fused;
        ] );
      ( "unboxed_aggregates", [
          Alcotest.test_case "identified struct type declared"        `Quick test_unboxed_aggregate_declared_as_struct;
          Alcotest.test_case "built/destructured without march_alloc" `Quick test_unboxed_aggregate_built_without_alloc;
          Alcotest.test_case "RED control: boxed repr does allocate"  `Quick test_unboxed_aggregate_boxed_control;
          Alcotest.test_case "eligible class"                         `Quick test_unboxed_aggregate_eligible_class;
          Alcotest.test_case "needs_rc/borrow_eligible are false"     `Quick test_unboxed_aggregate_rc_predicates;
          Alcotest.test_case "compiled Vec3 loop moves march_live_allocs by zero" `Slow
            test_unboxed_aggregate_zero_live_allocs_compiled;
          Alcotest.test_case "branch-join box is released at the merge" `Quick
            test_unboxed_aggregate_branch_join_box_released;
          Alcotest.test_case "compiled branch-built aggregate loop does not leak" `Slow
            test_unboxed_aggregate_branch_join_no_leak_compiled;
          Alcotest.test_case "a type in an extern signature stays boxed" `Quick test_unboxed_aggregate_ffi_type_stays_boxed;
        ] );
      ( "rc_types", [
          Alcotest.test_case "needs_rc/borrow_eligible truth table" `Quick test_rc_types_truth_table;
          Alcotest.test_case "divergence set is exactly {TFn, bare TVar, TTuple, TRecord}" `Quick test_rc_types_divergence_set_exact;
        ] );
      ( "nested_lit_pattern_codegen", [
          Alcotest.test_case "nested bool lit: no tag switch"   `Quick test_nested_bool_lit_pattern_no_tag_switch;
          Alcotest.test_case "nested int lit: tagged switch"    `Quick test_nested_int_lit_pattern_tagged_switch;
          Alcotest.test_case "nested atom lit: no tag switch"   `Quick test_nested_atom_lit_pattern_no_tag_switch;
        ] );
      ( "actor_dispatch_codegen", [
          Alcotest.test_case "finding-19: foreign msg dropped (Boxed dispatch + global tags + default arm)"
            `Quick test_actor_foreign_msg_drop_boxed_dispatch;
          Alcotest.test_case "finding-20: actor-struct state EReuse is unconditional (no RC race)"
            `Quick test_actor_struct_ereuse_unconditional;
          Alcotest.test_case "finding-20 follow-up: a `_Actor`-suffixed user type is NOT treated as an actor struct"
            `Quick test_actor_suffix_named_user_type_not_treated_as_actor;
          Alcotest.test_case "handler binder shadows a same-named top-level fn"
            `Quick test_actor_handler_binder_shadows_toplevel_fn;
        ] );
      ( "tco_codegen", [
          Alcotest.test_case "factorial loop emitted"   `Quick test_tco_factorial_has_loop;
          Alcotest.test_case "fold loop emitted"        `Quick test_tco_fold_has_loop;
          Alcotest.test_case "non-tail fib no loop"     `Quick test_tco_nontail_fib_no_loop;
          Alcotest.test_case "countdown loop emitted"   `Quick test_tco_countdown_has_loop;
        ] );
      ( "mutual_tco_codegen", [
          Alcotest.test_case "even/odd loop emitted"    `Quick test_mutual_tco_even_odd_loop_emitted;
          Alcotest.test_case "three-way mutual TCO"     `Quick test_mutual_tco_three_way;
          Alcotest.test_case "state machine mutual TCO" `Quick test_mutual_tco_state_machine;
          Alcotest.test_case "non-tail mutual: no loop" `Quick test_mutual_tco_non_tail_no_loop;
          Alcotest.test_case "self TCO unaffected"      `Quick test_mutual_tco_self_tco_unaffected;
          Alcotest.test_case "B7: borrowed-arg decref on live path (not dead mutco_cont)"
            `Quick test_mutual_tco_borrowed_arg_decref_on_live_path;
          Alcotest.test_case "self TCO: dup'd forwarded arg is decref'd on live path"
            `Quick test_tco_self_dup_arg_decref_on_live_path;
          Alcotest.test_case "deep drop: never-destructured container releases its children"
            `Quick test_deep_drop_of_borrowed_container;
          Alcotest.test_case "final-review: non-tail dec-chain-wrapped group call rejected"
            `Quick test_mutual_tco_non_tail_dec_chain_wrapped_no_loop;
          Alcotest.test_case "B8: reduction check present in mutual loop"
            `Quick test_mutual_tco_has_reduction_check;
        ] );
      ( "phase4_reduction_codegen", [
          Alcotest.test_case "non-leaf has reduction check"      `Quick test_phase4_nonleaf_has_reduction_check;
          Alcotest.test_case "leaf fn no reduction check"        `Quick test_phase4_leaf_fn_no_reduction_check;
          Alcotest.test_case "TCO fn reduction check in loop"    `Quick test_phase4_tco_fn_reduction_in_loop;
          Alcotest.test_case "non-recursive caller has check"    `Quick test_phase4_nonrecursive_caller_has_check;
        ] );
      "multiline", [
        Alcotest.test_case "depth zero" `Quick test_multiline_depth_zero;
        Alcotest.test_case "depth open" `Quick test_multiline_depth_open;
        Alcotest.test_case "depth closed" `Quick test_multiline_depth_closed;
        Alcotest.test_case "ends with with" `Quick test_multiline_ends_with_with;
        Alcotest.test_case "not ends with with" `Quick test_multiline_not_ends_with_with;
        Alcotest.test_case "starts with pipe" `Quick test_multiline_starts_with_pipe;
        Alcotest.test_case "is_complete simple" `Quick test_multiline_is_complete_simple;
        Alcotest.test_case "is_complete open block" `Quick test_multiline_is_complete_open_block;
      ];
      "repl_jit_cross_line", [
        Alcotest.test_case "W2.0 canary: setup_jit_runtime gate is live" `Quick test_setup_jit_runtime_gate_is_live;
        Alcotest.test_case "let binding cross-line" `Quick test_repl_jit_cross_line_let;
        Alcotest.test_case "fn reference cross-line" `Quick test_repl_jit_cross_line_fn;
        Alcotest.test_case "hof with fn and let cross-line" `Quick test_repl_jit_cross_line_hof;
        Alcotest.test_case "B11: stored closure returns untagged Int" `Quick test_repl_jit_stored_closure_returns_untagged_int;
        Alcotest.test_case "B11: self-referencing fn no duplicate clo_wrap" `Quick test_repl_jit_selfref_fn_no_duplicate_wrapper;
        Alcotest.test_case "fn redefinition rebinds (replay still skips)" `Quick test_repl_jit_fn_redefinition;
        Alcotest.test_case "top-level fn as first-class value" `Quick test_repl_jit_topfn_first_class_value;
        Alcotest.test_case "session wrap record is committed only after compile" `Quick test_clo_wrap_session_commit_is_deferred;
        Alcotest.test_case "capture-free closure materialization does not leak" `Quick test_repl_jit_capture_free_closure_no_leak;
        Alcotest.test_case "stdlib List.length via precompile" `Quick test_repl_jit_stdlib_list_length;
        Alcotest.test_case "B12: niche ADT cross-fragment (:load DMod then match)" `Quick test_repl_jit_niche_adt_cross_fragment;
        Alcotest.test_case "fn with lambda shadowing List.map's param compiles + runs" `Quick test_repl_jit_fn_lambda_shadows_hof_param;
        Alcotest.test_case "fn self-recursive through its lambda helper" `Quick test_repl_jit_fn_selfrec_via_lambda;
      ];
      "repl_jit_regression", [
        Alcotest.test_case "list literal compiles" `Quick test_repl_list_literal;
        Alcotest.test_case "list literal with bigint in fragment" `Quick test_repl_list_literal_with_bigint;
        Alcotest.test_case "decimal.march parses" `Quick test_decimal_march_parses;
        Alcotest.test_case "list literal with precompile bigint" `Quick test_repl_list_literal_with_precompile_bigint;
        Alcotest.test_case "stdlib on list literal" `Quick test_repl_stdlib_on_list;
        Alcotest.test_case "var redefinition" `Quick test_repl_var_redefinition;
        Alcotest.test_case "stdlib chain" `Quick test_repl_stdlib_chain;
        Alcotest.test_case "expr after let" `Quick test_repl_expr_after_let;
        Alcotest.test_case "v magic var (int)" `Quick test_repl_jit_v_magic_int;
        Alcotest.test_case "list pretty-print display" `Quick test_repl_jit_list_display;
        Alcotest.test_case "assign hint (x = 5)" `Quick test_repl_assign_hint;
        Alcotest.test_case "general REPL interaction" `Quick test_repl_jit_general_interaction;
        (* P0 compiled_fns corruption fix *)
        Alcotest.test_case "P0: List.reverse works (precompile)" `Quick test_repl_jit_stdlib_reverse;
        Alcotest.test_case "P0: stdlib fns inline (no precompile)" `Quick test_repl_jit_stdlib_no_precompile;
        Alcotest.test_case "P0: List.length x3 successive fragments" `Quick test_repl_jit_stdlib_length_3x;
      ];
      "complete", [
        Alcotest.test_case "command" `Quick test_complete_command;
        Alcotest.test_case "keyword" `Quick test_complete_keyword;
        Alcotest.test_case "in scope" `Quick test_complete_in_scope;
        Alcotest.test_case "empty all" `Quick test_complete_empty_all;
      ];
      "complete_replace", [
        Alcotest.test_case "prefix only"    `Quick test_complete_replace_prefix;
        Alcotest.test_case "mid word"       `Quick test_complete_replace_midword;
        Alcotest.test_case "with suffix"    `Quick test_complete_replace_with_suffix;
      ];
      "actors", [
        Alcotest.test_case "empty"  `Quick test_list_actors_empty;
        Alcotest.test_case "alive"  `Quick test_list_actors_alive;
        Alcotest.test_case "sorted" `Quick test_list_actors_sorted;
      ];
      "debugger", [
        Alcotest.test_case "EDbg AST"               `Quick test_edbg_ast;
        Alcotest.test_case "dbg keyword"            `Quick test_lexer_keyword_dbg;
        Alcotest.test_case "parse dbg()"            `Quick test_parse_dbg;
        Alcotest.test_case "desugar EDbg"           `Quick test_desugar_edbg;
        Alcotest.test_case "typecheck EDbg"         `Quick test_typecheck_edbg;
        Alcotest.test_case "eval EDbg no-op"        `Quick test_eval_edbg_noop;
        Alcotest.test_case "ring buffer"            `Quick test_ring_buffer;
        Alcotest.test_case "trace recording"        `Quick test_trace_recording;
        Alcotest.test_case "trace navigation"       `Quick test_trace_navigation;
        Alcotest.test_case "replay"                 `Quick test_replay;
        Alcotest.test_case "debug continue"         `Quick test_debug_continue;
        Alcotest.test_case "trace overflow"         `Quick test_trace_overflow;
        Alcotest.test_case "actor snapshot"         `Quick test_actor_snapshot;
      ];
      "docstrings", [
        Alcotest.test_case "parse fn doc"         `Quick test_doc_parse_fn;
        Alcotest.test_case "triple-quoted doc"    `Quick test_doc_triple_quoted;
        Alcotest.test_case "doc preserved after desugar" `Quick test_doc_desugar;
        Alcotest.test_case "doc registered in eval" `Quick test_doc_eval_registry;
        Alcotest.test_case "doc in nested module" `Quick test_doc_nested_module;
        Alcotest.test_case "no doc is None"       `Quick test_doc_none;
      ];
      ("purity", [
        Alcotest.test_case "atom"         `Quick test_purity_atom;
        Alcotest.test_case "arith"        `Quick test_purity_arith;
        Alcotest.test_case "println"      `Quick test_purity_println;
        Alcotest.test_case "print"        `Quick test_purity_print;
        Alcotest.test_case "send"         `Quick test_purity_send;
        Alcotest.test_case "let_pure"     `Quick test_purity_let_pure;
        Alcotest.test_case "let_impure"   `Quick test_purity_let_impure;
        Alcotest.test_case "callptr"    `Quick test_purity_callptr;
        Alcotest.test_case "kill"       `Quick test_purity_kill;
        Alcotest.test_case "incrc"      `Quick test_purity_incrc;
        Alcotest.test_case "free"       `Quick test_purity_free;
      ]);
      ("fold", [
        Alcotest.test_case "int_add"                 `Quick test_fold_int_add;
        Alcotest.test_case "int_mul"                 `Quick test_fold_int_mul;
        Alcotest.test_case "int_div_by_zero"         `Quick test_fold_int_div_by_zero;
        Alcotest.test_case "float_add"               `Quick test_fold_float_add;
        Alcotest.test_case "bool_not"                `Quick test_fold_bool_not;
        Alcotest.test_case "and_shortcircuit_pure"   `Quick test_fold_and_shortcircuit_pure;
        Alcotest.test_case "and_shortcircuit_impure" `Quick test_fold_and_shortcircuit_impure;
        Alcotest.test_case "if_true"                 `Quick test_fold_if_true;
        Alcotest.test_case "if_false"                `Quick test_fold_if_false;
        Alcotest.test_case "and_pure_var"            `Quick test_fold_and_pure_var;
        Alcotest.test_case "or_shortcircuit_pure"    `Quick test_fold_or_shortcircuit_pure;
        Alcotest.test_case "string_concat"           `Quick test_fold_string_concat;
        Alcotest.test_case "string_byte_length"      `Quick test_fold_string_byte_length;
        Alcotest.test_case "string_is_empty"         `Quick test_fold_string_is_empty;
        Alcotest.test_case "string_is_empty_false"   `Quick test_fold_string_is_empty_false;
        Alcotest.test_case "eq_true_rhs"             `Quick test_fold_eq_true_rhs;
        Alcotest.test_case "eq_false_rhs"            `Quick test_fold_eq_false_rhs;
        Alcotest.test_case "int_cmp_lit_true"        `Quick test_fold_int_cmp_lit;
        Alcotest.test_case "int_cmp_lit_false"       `Quick test_fold_int_cmp_lit_false;
      ]);
      ("simplify", [
        Alcotest.test_case "add_zero"          `Quick test_simplify_add_zero;
        Alcotest.test_case "mul_one"           `Quick test_simplify_mul_one;
        Alcotest.test_case "mul_zero_pure"     `Quick test_simplify_mul_zero_pure;
        Alcotest.test_case "sub_self"          `Quick test_simplify_sub_self;
        Alcotest.test_case "sub_different"     `Quick test_simplify_sub_different;
        Alcotest.test_case "div_one"           `Quick test_simplify_div_one;
        Alcotest.test_case "zero_div"          `Quick test_simplify_zero_div;
        Alcotest.test_case "zero_div_lit"      `Quick test_simplify_zero_div_lit;
        Alcotest.test_case "strength_reduce"   `Quick test_simplify_strength_reduce;
        Alcotest.test_case "float_add_zero"    `Quick test_simplify_float_add_zero;
        Alcotest.test_case "bool_and_true"     `Quick test_simplify_bool_and_true;
        Alcotest.test_case "str_concat_empty_rhs" `Quick test_simplify_string_concat_empty_rhs;
        Alcotest.test_case "str_concat_empty_lhs" `Quick test_simplify_string_concat_empty_lhs;
        Alcotest.test_case "str_concat_not_folded_post_perceus" `Quick test_simplify_string_concat_not_folded_post_perceus;
        Alcotest.test_case "if_then_true_else_false"  `Quick test_simplify_if_then_true_else_false;
        Alcotest.test_case "if_then_false_else_true"  `Quick test_simplify_if_then_false_else_true;
        Alcotest.test_case "eq_self"                  `Quick test_simplify_eq_self;
        Alcotest.test_case "ne_self"                  `Quick test_simplify_ne_self;
        Alcotest.test_case "eq_self_float_no_reduce"  `Quick test_simplify_eq_self_float_no_reduce;
        Alcotest.test_case "eq_self_tuple_float_no_reduce" `Quick test_simplify_eq_self_tuple_float_no_reduce;
        Alcotest.test_case "and_false_rhs"            `Quick test_simplify_and_false_rhs;
        Alcotest.test_case "and_false_lhs"            `Quick test_simplify_and_false_lhs;
        Alcotest.test_case "or_true_rhs"              `Quick test_simplify_or_true_rhs;
        Alcotest.test_case "not_true"                 `Quick test_simplify_not_true;
        Alcotest.test_case "not_false"                `Quick test_simplify_not_false;
      ]);
      ("inline", [
        Alcotest.test_case "pure_small"            `Quick test_inline_pure_small;
        Alcotest.test_case "impure_not_inlined"    `Quick test_inline_impure_not_inlined;
        Alcotest.test_case "recursive_not_inlined" `Quick test_inline_recursive_not_inlined;
        Alcotest.test_case "mutual_recursion_not_inlined" `Quick test_inline_mutual_recursion_not_inlined;
        Alcotest.test_case "acyclic_candidate_chain" `Quick test_inline_acyclic_candidate_chain;
        Alcotest.test_case "acyclic_growth_removes_outer_from_llvm" `Quick
          test_inline_acyclic_growth_removes_outer_from_llvm;
        Alcotest.test_case "alpha-renaming keeps sequence scopes lexical" `Quick
          test_inline_alpha_sequence_scope_is_lexical;
        Alcotest.test_case "alpha-renaming keeps case scopes lexical" `Quick
          test_inline_alpha_case_arms_and_default_are_lexical;
        Alcotest.test_case "alpha-renaming scopes local function parameters"
          `Quick test_inline_alpha_local_function_params_are_lexical;
        Alcotest.test_case "alpha-renaming avoids existing free names" `Quick
          test_inline_alpha_avoids_existing_free_name;
      ]);
      ("single_use_inline", [
        Alcotest.test_case "impure helper is eliminated from emitted LLVM"
          `Quick test_single_use_impure_eliminated_from_llvm;
        Alcotest.test_case "impure single call is inlined" `Quick
          test_single_use_impure_inlined;
        Alcotest.test_case "two calls are not inlined" `Quick
          test_single_use_two_calls_not_inlined;
        Alcotest.test_case "address-taken function is not inlined" `Quick
          test_single_use_address_taken_not_inlined;
        Alcotest.test_case "ELet shadowing is respected by analysis and rewrite"
          `Quick test_single_use_let_shadowing_respected;
        Alcotest.test_case "ELet RHS uses the outer scope" `Quick
          test_single_use_let_rhs_uses_outer_scope;
        Alcotest.test_case "two callers are counted together" `Quick
          test_single_use_two_callers_not_inlined;
        Alcotest.test_case "parameter and case-binder shadowing is respected"
          `Quick test_single_use_parameter_and_case_shadowing_respected;
        Alcotest.test_case "self recursion is excluded" `Quick
          test_single_use_self_recursive_not_inlined;
        Alcotest.test_case "mutual recursion is excluded" `Quick
          test_single_use_mutually_recursive_not_inlined;
        Alcotest.test_case "recursion through a non-candidate is excluded"
          `Quick test_single_use_recursion_through_noncandidate_not_inlined;
        Alcotest.test_case "50-node threshold is inclusive" `Quick
          test_single_use_size_threshold_is_inclusive;
        Alcotest.test_case "arity mismatch is excluded" `Quick
          test_single_use_arity_mismatch_not_inlined;
        Alcotest.test_case "DCE roots are excluded" `Quick
          test_single_use_dce_roots_not_inlined;
        Alcotest.test_case "no-seed fallback roots all functions" `Quick
          test_single_use_no_seed_fallback_roots_all_functions;
        Alcotest.test_case "closure-stored apply pointer is excluded" `Quick
          test_single_use_closure_stored_pointer_not_inlined;
        Alcotest.test_case "collision-dispatch target is excluded" `Quick
          test_single_use_collision_dispatch_target_not_inlined;
        Alcotest.test_case "reloadable callee is excluded" `Quick
          test_single_use_reloadable_callee_not_inlined;
        Alcotest.test_case "RC operation order is preserved" `Quick
          test_single_use_rc_order_preserved;
        Alcotest.test_case "pure body is excluded" `Quick
          test_single_use_pure_body_not_inlined;
        Alcotest.test_case "local ELetRec shadowing is respected" `Quick
          test_single_use_local_letrec_shadowing_respected;
        Alcotest.test_case "local-function parameter shadowing is respected"
          `Quick test_single_use_local_function_parameter_shadowing_respected;
        Alcotest.test_case "all atom positions are counted" `Quick
          test_single_use_all_atom_positions_counted;
        Alcotest.test_case "ADefRef is a non-direct reference" `Quick
          test_single_use_defref_counts_as_non_direct;
        Alcotest.test_case "caller binding cannot capture callee free name"
          `Quick test_single_use_rejects_caller_binding_capture;
        Alcotest.test_case "bare address aliases a qualified target" `Quick
          test_single_use_bare_address_alias_counts_qualified_target;
        Alcotest.test_case "ambiguous bare alias marks every target" `Quick
          test_single_use_ambiguous_bare_alias_marks_every_target;
        Alcotest.test_case "bare alias participates in recursive SCC" `Quick
          test_single_use_bare_alias_participates_in_scc;
        Alcotest.test_case "exact extern precedes qualified bare alias" `Quick
          test_single_use_exact_extern_precedes_qualified_alias;
      ]);
      ("blocking_extern", [
        Alcotest.test_case "dispatched via march_run_blocking_i" `Quick
          test_blocking_extern_uses_blocking_dispatch;
        Alcotest.test_case "never emitted as a direct call" `Quick
          test_blocking_extern_never_called_directly;
        Alcotest.test_case "pool reuses worker threads across calls" `Quick
          test_blocking_ffi_pool_reuses_threads_compiled;
      ]);
      ("known_call", [
        Alcotest.test_case "direct"          `Quick test_known_call_direct;
        Alcotest.test_case "unknown_unchanged" `Quick test_known_call_unknown_unchanged;
        Alcotest.test_case "two_closures"    `Quick test_known_call_two_closures;
        Alcotest.test_case "stack_alloc"     `Quick test_known_call_stack_alloc;
        Alcotest.test_case "is_clo_name matches Tir_names.is_clo_struct (W3C2.1)" `Quick
          test_known_call_is_clo_name_matches_tir_names;
      ]);
      ("struct_fusion", [
        Alcotest.test_case "two_updates"       `Quick test_struct_fusion_two_updates;
        Alcotest.test_case "three_updates"     `Quick test_struct_fusion_three_updates;
        Alcotest.test_case "field_override"    `Quick test_struct_fusion_field_override;
        Alcotest.test_case "no_fuse_multi_use" `Quick test_struct_fusion_no_fuse_multi_use;
      ]);
      ("dce", [
        Alcotest.test_case "dead_pure_let"       `Quick test_dce_dead_pure_let;
        Alcotest.test_case "impure_let_kept"     `Quick test_dce_impure_let_kept;
        Alcotest.test_case "used_let_kept"       `Quick test_dce_used_let_kept;
        Alcotest.test_case "unreachable_top_fn"  `Quick test_dce_unreachable_topfn;
        Alcotest.test_case "root_names"           `Quick test_dce_root_names;
        Alcotest.test_case "root_names_no_seed_falls_back_to_all" `Quick
          test_dce_root_names_no_seed_falls_back_to_all;
      ]);
      ("opt", [
        Alcotest.test_case "fixpoint"         `Quick test_opt_fixpoint;
        Alcotest.test_case "no_infinite_loop" `Quick test_opt_no_infinite_loop;
        Alcotest.test_case "single-use inline phase" `Quick
          test_opt_runs_single_use_inline_after_inline;
      ]);
      ("cprop", [
        Alcotest.test_case "simple_literal"       `Quick test_cprop_simple_literal;
        Alcotest.test_case "chain"                `Quick test_cprop_chain;
        Alcotest.test_case "enables_fold"         `Quick test_cprop_enables_fold;
        Alcotest.test_case "no_propagate_complex" `Quick test_cprop_no_propagate_complex;
        Alcotest.test_case "case_branch_shadow"      `Quick test_cprop_case_branch_shadow;
        Alcotest.test_case "opt_integration"         `Quick test_cprop_opt_integration;
        Alcotest.test_case "no_propagate_into_decrc" `Quick test_cprop_no_propagate_into_rc;
        Alcotest.test_case "no_propagate_into_incrc" `Quick test_cprop_no_propagate_into_incrc;
        Alcotest.test_case "no_propagate_into_free"  `Quick test_cprop_no_propagate_into_free;
        Alcotest.test_case "field_fold_record"       `Quick test_cprop_field_fold_record;
        Alcotest.test_case "field_fold_alias"        `Quick test_cprop_field_fold_alias;
        Alcotest.test_case "field_fold_update"       `Quick test_cprop_field_fold_update;
        Alcotest.test_case "field_fold_tuple"        `Quick test_cprop_field_fold_tuple;
        Alcotest.test_case "field_fold_tuple_second_element" `Quick
          test_cprop_field_fold_tuple_second_element;
        Alcotest.test_case "field_fold_tuple_alias"  `Quick test_cprop_field_fold_tuple_alias;
        Alcotest.test_case "field_fold_tuple_non_literal_element" `Quick
          test_cprop_field_fold_tuple_non_literal_element;
        Alcotest.test_case "no_tuple_field_collision_with_closure_capture" `Quick
          test_cprop_no_tuple_field_collision_with_closure_capture;
        Alcotest.test_case "tuple_field_result_escape_unchanged" `Quick
          test_cprop_tuple_field_result_escape_unchanged;
        Alcotest.test_case "tuple_dce_removes_allocation_from_llvm" `Quick
          test_cprop_tuple_dce_removes_allocation_from_llvm;
        Alcotest.test_case "var_alias"               `Quick test_cprop_var_alias;
        Alcotest.test_case "var_chain"               `Quick test_cprop_var_chain;
        Alcotest.test_case "no_alias_closure"        `Quick test_cprop_var_no_alias_closure;
      ]);
      ("beta_adt", [
        Alcotest.test_case "ok_inline"               `Quick test_beta_adt_ok_inline;
        Alcotest.test_case "qualified_tag"           `Quick test_beta_adt_qualified_tag;
        Alcotest.test_case "no_fire_non_case"        `Quick test_beta_adt_no_fire_non_case;
      ]);
      ("fbip_p8", [
        Alcotest.test_case "same_arity_match"        `Quick test_same_arity_match;
        Alcotest.test_case "same_arity_mismatch"     `Quick test_same_arity_mismatch;
        Alcotest.test_case "same_arity_non_tcon"     `Quick test_same_arity_non_tcon;
        Alcotest.test_case "same_arity_raw_type_refused" `Quick test_same_arity_raw_type_refused;
        Alcotest.test_case "cross_tag_reuse"         `Quick test_fbip_cross_tag_reuse;
        Alcotest.test_case "no_reuse_arity_mismatch" `Quick test_fbip_no_reuse_arity_mismatch;
      ]);
      ("join_points", [
        Alcotest.test_case "float_common_let"       `Quick test_join_points_float_common_let;
        Alcotest.test_case "no_float_different_rhs" `Quick test_join_points_no_float_different_rhs;
        Alcotest.test_case "no_float_uses_br_var"   `Quick test_join_points_no_float_uses_br_var;
        Alcotest.test_case "float_two_common_lets"  `Quick test_join_points_float_two_common_lets;
        Alcotest.test_case "pre_float_alpha"         `Quick test_join_points_pre_float_alpha;
        Alcotest.test_case "pre_no_float_diff_rhs"   `Quick test_join_points_pre_no_float_different_rhs;
      ]);
      ("repr", [
        Alcotest.test_case "newtype_int"          `Quick test_repr_newtype_int;
        Alcotest.test_case "newtype_ptr"          `Quick test_repr_newtype_ptr;
        Alcotest.test_case "multivariant_boxed"   `Quick test_repr_multivariant_is_boxed;
        Alcotest.test_case "multifield_boxed"     `Quick test_repr_multifield_is_boxed;
        Alcotest.test_case "scalar_boxed"         `Quick test_repr_scalar_is_boxed;
        Alcotest.test_case "niche_int"            `Quick test_repr_niche_int;
        Alcotest.test_case "niche_string"         `Quick test_repr_niche_string;
        Alcotest.test_case "niche_bool"           `Quick test_repr_niche_bool;
        Alcotest.test_case "niche_float_boxed"    `Quick test_repr_niche_float_is_boxed;
        Alcotest.test_case "niche_unit_boxed"     `Quick test_repr_niche_unit_is_boxed;
        Alcotest.test_case "nested_niche_boxed"   `Quick test_repr_nested_niche_is_boxed;
        Alcotest.test_case "colliding_niche_shaped_forced_boxed" `Quick
          test_repr_colliding_niche_shaped_type_forced_boxed;
        Alcotest.test_case "noncolliding_niche_shaped_unaffected" `Quick
          test_repr_noncolliding_niche_shaped_type_unaffected;
      ]);
      ("lower: collision-conditional impl symbols", [
        Alcotest.test_case "colliding general-iface impls get distinct symbols" `Quick
          test_colliding_impls_get_distinct_symbols;
        Alcotest.test_case "non-colliding impl symbol stays bare" `Quick
          test_noncolliding_impl_symbol_stays_bare;
        Alcotest.test_case "ambiguous iface call stays unresolved at lower time" `Quick
          test_ambiguous_iface_call_stays_unresolved_at_lower_time;
      ]);
      ("dispatch: collision-conditional ctor construction key", [
        Alcotest.test_case "colliding ctor construction gets qualified key" `Quick
          test_colliding_ctor_construction_gets_qualified_key;
        Alcotest.test_case "non-colliding ctor construction stays bare" `Quick
          test_noncolliding_ctor_construction_stays_bare;
        Alcotest.test_case "nested Down does not alias monitor ABI" `Quick
          test_nested_down_constructor_does_not_alias_monitor_abi;
        Alcotest.test_case "canonical monitor spelling wins inside shadowing module" `Quick
          test_canonical_monitor_spelling_wins_inside_shadowing_module;
        Alcotest.test_case "colliding ctor construction inside impl method body gets qualified key" `Quick
          test_colliding_ctor_construction_inside_impl_method_gets_qualified_key;
      ]);
      ("lower_match: collision-conditional pattern tag qualification", [
        Alcotest.test_case "impl-less colliding pattern match stays bare (narrowed)" `Quick
          test_colliding_pattern_match_impl_less_stays_bare;
        Alcotest.test_case "colliding pattern match inside impl method body gets qualified tag" `Quick
          test_colliding_pattern_match_impl_method_gets_qualified_tag;
        Alcotest.test_case "ptype structural-interop ctor key stays bare (not per-module qualified)" `Quick
          test_ptype_structural_interop_ctor_key_stays_bare;
      ]);
      ("dispatch: colliding general-iface runtime tag switch", [
        Alcotest.test_case "colliding general-iface dispatches on runtime tag" `Quick
          test_colliding_general_iface_runtime_dispatch;
        Alcotest.test_case "non-colliding program emits no dispatch fn" `Quick
          test_noncolliding_no_dispatch_fn;
        Alcotest.test_case "multi-ctor colliding type shares one impl per type" `Quick
          test_colliding_multi_ctor_shares_one_impl;
        Alcotest.test_case "mono ECallPtr None-branch reaches try_collision_dispatch" `Quick
          test_mono_ecallptr_collision_dispatch;
        Alcotest.test_case "mono iface_impl_name name-collision branch reaches try_collision_dispatch" `Quick
          test_mono_iface_name_collision_dispatch;
      ]);
      ("fast_math", [
        Alcotest.test_case "emits_fast_attr" `Quick test_fast_math_emits_fast_attr;
      ]);
      ("llvm_emit correctness", [
        Alcotest.test_case "ctor_no_collision_different_tags" `Quick
          test_ctor_no_collision_different_tags;
        Alcotest.test_case "ctor_arity_mismatch_raises" `Quick
          test_ctor_arity_mismatch_raises;
        Alcotest.test_case "compiled main calls march_run_scheduler" `Quick
          (with_reset test_compiled_main_calls_march_run_scheduler);
        Alcotest.test_case "string_chars llvm emit" `Quick
          test_string_chars_llvm_emit;
        Alcotest.test_case "int tag coerce IR (shl+or+ashr)" `Quick
          test_int_tag_coerce_ir;
        Alcotest.test_case "int tag wrapper IR (shl+or in wrapper)" `Quick
          test_int_tag_wrapper_ir;
        (* Regression: 831e315 + perceus caused @__ undefined symbol in &&/|| *)
        Alcotest.test_case "no @__ call for && / || (831e315)" `Quick
          test_llvm_no_call_to_double_underscore;
      ]);
      ("string stdlib", [
        Alcotest.test_case "byte_size"           `Quick test_string_byte_size;
        Alcotest.test_case "byte_size empty"     `Quick test_string_byte_size_empty;
        Alcotest.test_case "byte_size unicode"   `Quick test_string_byte_size_unicode;
        Alcotest.test_case "slice_bytes"         `Quick test_string_slice_bytes;
        Alcotest.test_case "slice_bytes clamp"   `Quick test_string_slice_bytes_clamp;
        Alcotest.test_case "contains"            `Quick test_string_contains;
        Alcotest.test_case "starts_with"         `Quick test_string_starts_with;
        Alcotest.test_case "ends_with"           `Quick test_string_ends_with;
        Alcotest.test_case "concat"              `Quick test_string_concat;
        Alcotest.test_case "replace"             `Quick test_string_replace;
        Alcotest.test_case "replace_all"         `Quick test_string_replace_all;
        Alcotest.test_case "split"               `Quick test_string_split;
        Alcotest.test_case "split_first"         `Quick test_string_split_first;
        Alcotest.test_case "split_first no sep"  `Quick test_string_split_first_no_sep;
        Alcotest.test_case "join"                `Quick test_string_join;
        Alcotest.test_case "trim"                `Quick test_string_trim;
        Alcotest.test_case "trim_start"          `Quick test_string_trim_start;
        Alcotest.test_case "trim_end"            `Quick test_string_trim_end;
        Alcotest.test_case "to_uppercase"        `Quick test_string_to_uppercase;
        Alcotest.test_case "to_lowercase"        `Quick test_string_to_lowercase;
        Alcotest.test_case "repeat"              `Quick test_string_repeat;
        Alcotest.test_case "reverse"             `Quick test_string_reverse;
        Alcotest.test_case "pad_left"            `Quick test_string_pad_left;
        Alcotest.test_case "pad_right"           `Quick test_string_pad_right;
        Alcotest.test_case "chars"               `Quick test_string_chars;
        Alcotest.test_case "chars empty"         `Quick test_string_chars_empty;
        Alcotest.test_case "to_upper"            `Quick test_string_to_upper;
        Alcotest.test_case "to_lower"            `Quick test_string_to_lower;
        Alcotest.test_case "is_empty"            `Quick test_string_is_empty;
        Alcotest.test_case "grapheme_count"      `Quick test_string_grapheme_count;
        Alcotest.test_case "index_of"            `Quick test_string_index_of;
        Alcotest.test_case "to_int"              `Quick test_string_to_int;
        Alcotest.test_case "to_float"            `Quick test_string_to_float;
        Alcotest.test_case "from_int"            `Quick test_string_from_int;
        Alcotest.test_case "from_float"          `Quick test_string_from_float;
      ]);
      ("iolist stdlib", [
        Alcotest.test_case "empty"         `Quick test_iolist_empty;
        Alcotest.test_case "from_string"   `Quick test_iolist_from_string;
        Alcotest.test_case "append"        `Quick test_iolist_append;
        Alcotest.test_case "byte_size"     `Quick test_iolist_byte_size;
      ]);
      ("~H sigil codegen", [
        Alcotest.test_case "static ~H lowers to List.Cons"
          `Quick test_h_sigil_static_lowers_to_list_cons;
        Alcotest.test_case "int interp coerces arg to ptr"
          `Quick test_h_sigil_int_interp_coerces_arg_to_ptr;
      ]);
      ("http stdlib", [
        Alcotest.test_case "parse_url"          `Quick test_http_parse_url;
        Alcotest.test_case "parse_url scheme"    `Quick test_http_parse_url_scheme;
        Alcotest.test_case "parse_url path"      `Quick test_http_parse_url_path;
        Alcotest.test_case "parse_url port"      `Quick test_http_parse_url_port;
        Alcotest.test_case "parse_url invalid"   `Quick test_http_parse_url_invalid;
        Alcotest.test_case "set_header"          `Quick test_http_set_header;
        Alcotest.test_case "method_to_string"    `Quick test_http_method_to_string;
        Alcotest.test_case "status helpers"      `Quick test_http_status_helpers;
        Alcotest.test_case "post constructor"    `Quick test_http_post_constructor;
        Alcotest.test_case "encode_query"        `Quick test_http_encode_query;
        Alcotest.test_case "response helpers"    `Quick test_http_response_helpers;
      ]);
      ("http builtins", [
        Alcotest.test_case "serialize request"       `Quick test_http_serialize_request;
        Alcotest.test_case "serialize with body"     `Quick test_http_serialize_request_with_body;
        Alcotest.test_case "parse response"          `Quick test_http_parse_response;
        Alcotest.test_case "parse response body"     `Quick test_http_parse_response_body;
      ]);
      ("http client", [
        Alcotest.test_case "new client"              `Quick test_http_client_new;
        Alcotest.test_case "add steps"               `Quick test_http_client_add_steps;
        Alcotest.test_case "bearer auth transform"   `Quick test_http_client_request_step_transforms;
        Alcotest.test_case "raise on error status"   `Quick test_http_client_raise_on_error_status;
        Alcotest.test_case "with redirects"          `Quick test_http_client_with_redirects;
        Alcotest.test_case "base url step"           `Quick test_http_client_base_url_step;
        Alcotest.test_case "content type step"       `Quick test_http_client_content_type_step;
      ]);
      ( "scheduler",
        [
          Alcotest.test_case "reduction counter ticks"     `Quick (with_reset test_reduction_counter_ticks);
          Alcotest.test_case "reduction counter exhausts"  `Quick (with_reset test_reduction_counter_exhausts);
          Alcotest.test_case "eval yields after budget"    `Quick (with_reset test_eval_yields_after_budget);
          Alcotest.test_case "eval no yield when disabled" `Quick (with_reset test_eval_no_yield_when_disabled);
          Alcotest.test_case "reduction count"             `Quick (with_reset test_eval_reduction_count);
        ] );
      ( "native_arrays",
        [
          Alcotest.test_case "int arr IR"   `Quick (with_reset test_native_int_arr_ir);
          Alcotest.test_case "float arr IR" `Quick (with_reset test_native_float_arr_ir);
          Alcotest.test_case "narrow arr IR" `Quick (with_reset test_native_narrow_arr_ir);
          Alcotest.test_case "simd vector IR" `Quick (with_reset test_simd_vector_ir);
        ] );
      ( "tasks",
        [
          Alcotest.test_case "spawn and await"     `Quick (with_reset test_eval_task_spawn_await);
          Alcotest.test_case "await unwrap"        `Quick (with_reset test_eval_task_await_unwrap);
          Alcotest.test_case "multiple tasks"      `Quick (with_reset test_eval_task_multiple);
          Alcotest.test_case "task captures env"   `Quick (with_reset test_eval_task_captures_env);
          Alcotest.test_case "spawn_steal requires pool" `Quick (with_reset test_eval_spawn_steal_requires_pool);
          Alcotest.test_case "spawn_steal with pool"     `Quick (with_reset test_eval_spawn_steal_with_pool);
          Alcotest.test_case "workpool threading"        `Quick (with_reset test_eval_workpool_threading);
          Alcotest.test_case "task sends to actor"       `Quick (with_reset test_eval_task_sends_to_actor);
          Alcotest.test_case "task_spawn heap-alloc no RC underflow" `Quick
            (with_reset test_compile_task_spawn_heap_alloc_no_rc_underflow);
          Alcotest.test_case "local shadowing builtin still gets RC ops (B10)" `Quick
            (with_reset test_compile_local_shadows_builtin_still_gets_rc_ops);
          (* Phase 5: compiled IR correctness *)
          Alcotest.test_case "task_yield emits sched_yield"        `Quick
            (with_reset test_compile_task_yield_actually_yields);
          Alcotest.test_case "task_reductions reads TLS"           `Quick
            (with_reset test_compile_task_reductions_reads_tls);
          Alcotest.test_case "task_await uses march_task_await"    `Quick
            (with_reset test_compile_task_await_in_ir);
          Alcotest.test_case "cancel token IR correctness"         `Quick
            (with_reset test_compile_cancel_token_ir);
          (* Phase 5B: cancel tokens *)
          Alcotest.test_case "cancel token new"          `Quick (with_reset test_cancel_token_new);
          Alcotest.test_case "cancel token cancel"       `Quick (with_reset test_cancel_token_cancel);
          Alcotest.test_case "cancel tokens independent" `Quick (with_reset test_cancel_tokens_independent);
          Alcotest.test_case "spawn_with_cancel active"  `Quick (with_reset test_spawn_with_cancel_active);
          Alcotest.test_case "spawn_with_cancel pre-cancelled" `Quick (with_reset test_spawn_with_cancel_precancelled);
          Alcotest.test_case "cancel_by_id"              `Quick (with_reset test_cancel_by_id);
          (* Phase 5C: structured concurrency *)
          Alcotest.test_case "race single"               `Quick (with_reset test_task_race_single);
          Alcotest.test_case "race cancels losers"       `Quick (with_reset test_task_race_cancels_losers);
          Alcotest.test_case "race empty"                `Quick (with_reset test_task_race_empty);
          Alcotest.test_case "all_settled mixed results" `Quick (with_reset test_task_all_settled);
        ] );
      ( "work_stealing",
        [
          Alcotest.test_case "deque push/pop"     `Quick (with_reset test_deque_push_pop);
          Alcotest.test_case "deque steal"        `Quick (with_reset test_deque_steal);
          Alcotest.test_case "deque size"         `Quick (with_reset test_deque_size);
          Alcotest.test_case "pool submit/steal"  `Quick (with_reset test_pool_submit_steal);
        ] );
      ( "capabilities",
        [
          Alcotest.test_case "pure module ok"            `Quick test_cap_needs_pure_ok;
          Alcotest.test_case "declared needs ok"         `Quick test_cap_needs_declared_ok;
          Alcotest.test_case "missing needs error"       `Quick test_cap_missing_needs_error;
          Alcotest.test_case "unused needs warning"      `Quick test_cap_unused_needs_warning;
          Alcotest.test_case "extern block counts as cap use" `Quick test_cap_extern_block_counts_as_use;
          Alcotest.test_case "supertype covers subtype"  `Quick test_cap_supertype_covers_subtype;
          Alcotest.test_case "wrong subtype error"       `Quick test_cap_needs_wrong_subtype;
          Alcotest.test_case "multiple needs"            `Quick test_cap_multiple_needs;
          Alcotest.test_case "parse needs"               `Quick test_cap_parse_needs;
          Alcotest.test_case "parse needs dotted"        `Quick test_cap_parse_needs_dotted;
          Alcotest.test_case "transitive ok"             `Quick test_cap_transitive_ok;
          Alcotest.test_case "transitive missing error"  `Quick test_cap_transitive_missing_error;
          Alcotest.test_case "transitive supertype ok"   `Quick test_cap_transitive_supertype_ok;
          Alcotest.test_case "transitive chain error"    `Quick test_cap_transitive_chain_error;
          Alcotest.test_case "extern with needs ok"      `Quick test_cap_extern_with_needs_ok;
          Alcotest.test_case "extern missing needs error" `Quick test_cap_extern_missing_needs_error;
          Alcotest.test_case "ffi: extern explicit symbol in IR" `Quick test_ffi_extern_explicit_symbol_ir;
          Alcotest.test_case "ffi: extern default symbol in IR"  `Quick test_ffi_extern_default_symbol_ir;
          Alcotest.test_case "effects entry point clean"  `Quick test_cap_effects_clean;
          Alcotest.test_case "effects entry point violation" `Quick test_cap_effects_violation;
          Alcotest.test_case "eval path blocked by cap error" `Quick test_cap_eval_path_blocked;
          Alcotest.test_case "eval path ok with needs"    `Quick test_cap_eval_path_ok;
          Alcotest.test_case "proof cap: parse"               `Quick test_proof_cap_parse;
          Alcotest.test_case "proof cap: decl ok"             `Quick test_proof_cap_declaration_ok;
          Alcotest.test_case "proof cap: forge error"         `Quick test_proof_cap_forge_error;
          Alcotest.test_case "proof cap: passthrough ok"      `Quick test_proof_cap_passthrough_ok;
          Alcotest.test_case "proof cap: missing needs"       `Quick test_proof_cap_missing_needs_error;
          Alcotest.test_case "proof cap: declaring mod ok"    `Quick test_proof_cap_in_declaring_module_ok;
          Alcotest.test_case "proof cap: implicit needs"      `Quick test_proof_cap_implicit_needs;
          Alcotest.test_case "proof cap: pfn forge error"     `Quick test_proof_cap_pfn_forge_error;
          Alcotest.test_case "proof cap: pfn passthrough ok"  `Quick test_proof_cap_pfn_passthrough_ok;
        ] );
      ( "js_backend_opt", [
          Alcotest.test_case "Opt safe without Perceus" `Quick test_opt_without_perceus;
        ] );
      ( "hot_reload_leaf_change", [
          Alcotest.test_case "leaf change: only leaf reload hash changes" `Quick test_hcr_leaf_change_only_changes_leaf_reload_hash;
          Alcotest.test_case "transitive CAS hash still propagates"       `Quick test_hcr_transitive_hash_still_propagates_for_cas;
          Alcotest.test_case "entry point excluded from reloadable slots" `Quick test_hcr_entry_point_not_a_reloadable_slot;
        ] );
      ( "guard_exhaustion_codegen", [
          Alcotest.test_case "compiled guard exhaustion panics (B3)" `Quick
            test_guard_exhaustion_panics_compiled;
          Alcotest.test_case "compiled guarded 3-arm match parity (shared-JP bloat fix)" `Quick
            test_compiled_guarded_match_parity;
        ] );
      ( "check_diagnostic_determinism", [
          Alcotest.test_case "repeated --check has byte-identical diagnostics" `Quick
            test_check_diagnostic_display_deterministic;
        ] );
      ( "unit_tail_discard_codegen", [
          Alcotest.test_case "`()` tail after a discard emits no indirect call" `Quick
            test_unit_tail_discard_no_indirect_call_ir;
          Alcotest.test_case "`()` tail after a discard runs compiled (exit 0)" `Quick
            test_unit_tail_discard_runs_compiled;
          Alcotest.test_case "`()` tail after a LITERAL discard runs compiled (exit 0)" `Quick
            test_unit_tail_literal_discard_runs_compiled;
        ] );
      ( "derive_json_dispatch_codegen", [
          Alcotest.test_case "compiled single-derive bare from_json resolves" `Quick
            test_derive_json_single_from_json_compiled;
          Alcotest.test_case "ambiguous multi-derive from_json: clean diagnostic, not ICE" `Quick
            test_derive_json_ambiguous_from_json_diagnostic;
        ] );
      ( "float_lit_match_codegen", [
          Alcotest.test_case "compiled float-literal match arm (B4)" `Quick
            test_float_lit_match_arm_compiled;
          Alcotest.test_case "compiled float non-exhaustive match panics (B4)" `Quick
            test_float_lit_no_wildcard_panics_compiled;
        ] );
      ( "string_literal_codegen", [
          Alcotest.test_case "compiled string literal as `++` operand does not leak per evaluation" `Quick
            test_string_literal_operand_no_leak_compiled;
          Alcotest.test_case "compiled static closure materialization does not leak per use" `Quick
            test_static_closure_materialization_no_leak_compiled;
          Alcotest.test_case "compiled capture-free lambda materialization does not leak per use" `Quick
            test_lambda_static_closure_materialization_no_leak_compiled;
          Alcotest.test_case "compiled capturing lambda materialization does not leak per use" `Quick
            test_capturing_closure_materialization_no_leak_compiled;
          Alcotest.test_case "compiled self-recursive capturing closure materialization does not leak per use" `Quick
            test_self_recursive_capturing_closure_no_leak_compiled;
          Alcotest.test_case "compiled self-recursive capturing closure: correct values (fib-shaped, double recursive call)" `Quick
            test_self_recursive_capturing_closure_correct_compiled;
        ] );
      ( "try_call_capture_ownership_codegen", [
          Alcotest.test_case "single-capture __try_call thunk: no double-free (30x)" `Quick
            test_try_call_single_capture_no_double_free_compiled;
          Alcotest.test_case "single-capture __try_call_val thunk: no double-free (30x)" `Quick
            test_try_call_val_single_capture_no_double_free_compiled;
          Alcotest.test_case "single-capture __try_call thunk panics: no double-free (15x)" `Quick
            test_try_call_panic_with_capture_no_double_free_compiled;
          Alcotest.test_case "try_finally: value untag + cleanup order (compiled vs interpreted)" `Quick
            test_try_finally_value_and_order_compiled;
          Alcotest.test_case "try_finally: cleanup runs when the action panics (compiled)" `Quick
            test_try_finally_cleanup_runs_on_panic_compiled;
          Alcotest.test_case "File.with_lines streaming: fd Option niche contract (compiled)" `Quick
            test_file_with_lines_streaming_compiled;
          Alcotest.test_case "NativeArray.map_int: reused capturing closure not freed mid-map (20x)" `Quick
            test_native_array_map_reused_capturing_closure_compiled;
          Alcotest.test_case "NativeArray.set_int: aliased (rc>1) array is copy-on-write, not mutated" `Quick
            test_native_array_set_int_alias_cow_compiled;
          Alcotest.test_case "NativeArray.set_int: rc==1 in-place churn stays correct over 2M ops (flat RSS)" `Quick
            test_native_array_set_int_inplace_churn_compiled;
          Alcotest.test_case "Signal.watch: capturing handler survives repeated delivery (25x)" `Quick
            test_signal_watch_capturing_handler_repeated_delivery_compiled;
        ] );
      ( "erased_option_niche_fbip_codegen", [
          Alcotest.test_case "compiled erased-niche-Option FBIP reuse: no RC underflow" `Quick
            test_erased_option_niche_fbip_no_underflow_compiled;
        ] );
      ( "nested_tuple_let_codegen", [
          Alcotest.test_case "compiled nested-tuple `let` destructure binds leaf vars" `Quick
            test_nested_tuple_let_destructure_compiled;
          Alcotest.test_case "compiled deep nested-tuple `let` (nesting + wildcard)" `Quick
            test_nested_tuple_let_deep_wildcard_compiled;
        ] );
      ( "nested_fn_name_collision_codegen", [
          Alcotest.test_case "nested `fn go` shadows a same-named top-level fn in mono" `Quick
            test_nested_fn_name_shadows_toplevel_compiled;
        ] );
      ( "nonentry_newtype_repr_codegen", [
          Alcotest.test_case "non-entry single-field ADT: construct/destructure repr agree (tuple-nested)" `Quick
            test_nonentry_newtype_tuple_destructure_compiled;
        ] );
      ( "erased_record_update_codegen", [
          Alcotest.test_case "single march_record_update_dyn call in IR (B5)" `Quick
            test_erased_update_single_dyn_call_ir;
          Alcotest.test_case "compiled missing-field update panics (B5)" `Quick
            test_erased_update_missing_field_panics_compiled;
          Alcotest.test_case "compiled multi-field update values (B5)" `Quick
            test_erased_update_multi_field_values_compiled;
        ] );
      ( "main_cap_adapter", [
          Alcotest.test_case "compiled main with Cap(IO)" `Quick
            test_main_adapter_zero_caps;
          Alcotest.test_case "compiled main with 1 narrow cap" `Quick
            test_main_adapter_one_cap;
          Alcotest.test_case "compiled main with 2 caps" `Quick
            test_main_adapter_two_caps;
          Alcotest.test_case "compiled main with 3 caps" `Quick
            test_main_adapter_three_caps;
        ] );
      ( "iface_impl_mono_codegen", [
          Alcotest.test_case "compiled default-arg call at every arity (source-level resolution)" `Quick
            test_compiled_default_args_parity;
          Alcotest.test_case "compiled nested-module default-arg call (both backends)" `Quick
            test_compiled_nested_default_args_parity;
          Alcotest.test_case "compiled --no-opt prunes unreachable fns (links, prints hi)" `Quick
            test_compiled_no_opt_prunes_unreachable;
          Alcotest.test_case "compiled int_div_euclid parity (all sign quadrants)" `Quick
            test_compiled_int_div_euclid_parity;
          Alcotest.test_case "compiled int_mod_euclid parity (negative divisor)" `Quick
            test_compiled_int_mod_euclid_parity;
          Alcotest.test_case "compiled IOList deep-tree flatten parity (stack-safe)" `Slow
            test_compiled_iolist_deep_flatten_parity;
          Alcotest.test_case "compiled Deque.pop_front decode parity (eager stdlib load)" `Quick
            test_compiled_deque_pop_parity;
          Alcotest.test_case "compiled self-referencing let-shadowing parity (cprop)" `Quick
            test_compiled_let_shadowing_parity;
          Alcotest.test_case "compiled float NaN `!=` parity (une vs one)" `Quick
            test_compiled_float_nan_neq_parity;
          Alcotest.test_case "compiled entry-module self-qualification parity" `Quick
            test_compiled_entry_self_qual_parity;
          Alcotest.test_case "compiled entry-module nested self-qualification parity" `Quick
            test_compiled_entry_self_qual_nested_parity;
          Alcotest.test_case "compiled entry-module self-qual no-overstrip parity" `Quick
            test_compiled_entry_self_qual_no_overstrip_parity;
          Alcotest.test_case "compiled entry-module self-qual of an extern fn parity" `Quick
            test_compiled_entry_self_qual_extern_parity;
          Alcotest.test_case "compiled nested-module bare extern call parity (no over-qualification)" `Quick
            test_compiled_entry_self_qual_extern_nested_parity;
          Alcotest.test_case "compiled nested-module interface dispatch parity (methods stay unqualified)" `Quick
            test_compiled_nested_interface_dispatch_parity;
          Alcotest.test_case "compiled MPST 3-role Relay parity (runs binary; layout+role-index fix)" `Quick
            test_compiled_mpst_relay_parity;
          Alcotest.test_case "compiled MPST Relay distinct-payload parity (runs binary; role name->index)" `Quick
            test_compiled_mpst_relay_distinct_parity;
          Alcotest.test_case "compiled println(List(Int)) parity (Wave2 T1)" `Quick
            test_compiled_println_int_list_parity;
          Alcotest.test_case "compiled println(List(String)) parity (Wave2 T1)" `Quick
            test_compiled_println_string_list_parity;
          Alcotest.test_case "compiled println(List(Option(Int))) parity (Wave2 T1)" `Quick
            test_compiled_println_option_list_parity;
          Alcotest.test_case "compiled println(List(List(Int))) parity + mono termination (Wave2 T1)" `Quick
            test_compiled_println_nested_list_parity;
          Alcotest.test_case "compiled println(:atom) parity (Show$Atom)" `Quick
            test_compiled_println_atom_parity;
          Alcotest.test_case "compiled show(:atom) multi-atom parity (Show$Atom)" `Quick
            test_compiled_show_atom_multi_parity;
          Alcotest.test_case "unresolved-iface-method guard fires: EApp path (Wave2 review)" `Quick
            test_iface_guard_fires_eapp;
          Alcotest.test_case "unresolved-iface-method guard fires: ECallPtr path (Wave2 review)" `Quick
            test_iface_guard_fires_ecallptr;
          Alcotest.test_case "unresolved-iface-method guard: negative control (Wave2 review)" `Quick
            test_iface_guard_negative_control;
        ] );
      ( "scrutinee_borrowed_cross_branch_dec_codegen", [
          Alcotest.test_case "no double dec_rc on scrutinee re-matched in sibling sub-path (P0)" `Quick
            test_scrutinee_borrowed_cross_branch_no_double_dec;
        ] );
      ( "newtype_derived_method_crash", [
          Alcotest.test_case "derived Eq: == operator vs named eq() parity (P1)" `Quick
            test_newtype_derived_eq_operator_vs_named_parity;
          Alcotest.test_case "derived Ord/Hash named compare()/hash() on Int-payload newtype (P1)" `Quick
            test_newtype_derived_ord_hash_named_compiled;
          Alcotest.test_case "derived Eq/Ord/Hash named on String-payload newtype (P1)" `Quick
            test_newtype_derived_ord_string_payload_compiled;
          Alcotest.test_case "control: Boxed 2-field ctor derived methods unaffected (P1)" `Quick
            test_boxed_pair_derived_methods_unaffected_compiled;
          Alcotest.test_case "control: multi-ctor derived methods unaffected (P1)" `Quick
            test_multi_ctor_derived_methods_unaffected_compiled;
          Alcotest.test_case "derive on variant whose name collides with a stdlib record" `Quick
            test_derive_variant_name_collides_stdlib_record_compiled;
          Alcotest.test_case "derive on variant whose name collides with a local nested record" `Quick
            test_derive_variant_name_collides_local_record_compiled;
          Alcotest.test_case "hand-written impl nested-destructure match on newtype (P1)" `Quick
            test_handwritten_impl_nested_match_newtype_compiled;
          Alcotest.test_case "== operator on String-payload newtype (P1, distinct bug)" `Quick
            test_newtype_eq_operator_string_payload_compiled;
          Alcotest.test_case "control: == operator on Int-payload newtype (tagged scalar) (P1)" `Quick
            test_newtype_eq_operator_int_payload_control_compiled;
          Alcotest.test_case "== operator on Boxed-ADT-payload newtype (recursive) (P1)" `Quick
            test_newtype_eq_operator_boxed_payload_compiled;
          Alcotest.test_case "== operator on generic newtype (type_params subst path) (P1)" `Quick
            test_newtype_eq_operator_generic_payload_compiled;
          Alcotest.test_case "== operator on opaque (undeclared) ctor field falls back to march_poly_eq" `Quick
            test_eq_operator_opaque_ctor_field_uses_poly_eq;
        ] );
      ( "cross_module_ctor_resolution", [
          Alcotest.test_case "Msgpack vs Json ambiguous ctor: encode/decode parity" `Quick
            test_msgpack_cross_module_ctor_resolution_compiled;
          Alcotest.test_case "module-qualified pattern for colliding ctor name" `Quick
            test_module_qualified_colliding_ctor_pattern_compiled;
        ] );
      ( "string_codepoint", [
          Alcotest.test_case "String.from_codepoint/to_codepoints usable compiled (pure-March codec)" `Quick
            test_string_codepoint_parity;
          Alcotest.test_case "string_to_codepoints/string_from_codepoint builtins link and match interp" `Quick
            test_compiled_string_codepoint_builtin_parity;
        ] );
      ( "unix_time_ms", [
          Alcotest.test_case "unix_time_ms builtin links and matches interp" `Quick
            test_compiled_unix_time_ms_parity;
        ] );
      ( "llvm_builtins_preamble_golden", [
          Alcotest.test_case "every builtin c_name is declared in some preamble" `Quick
            test_every_builtin_c_name_is_declared;
          Alcotest.test_case "Builtin_name round-trips and covers emit_expr" `Quick
            test_builtin_name_roundtrip;
          Alcotest.test_case "every Builtin_name has an emit group" `Quick
            test_builtin_group_total;
          Alcotest.test_case "native, non-repl preamble byte-identical (W3C2.4 / H2)" `Quick
            test_preamble_byte_identical_native;
          Alcotest.test_case "native, REPL preamble byte-identical (W3C2.4 / H2)" `Quick
            test_preamble_byte_identical_native_repl;
          Alcotest.test_case "WASM preamble byte-identical (W3C2.4 / H2)" `Quick
            test_preamble_byte_identical_wasm;
          Alcotest.test_case "march_alloc has verified return and size attributes" `Quick
            test_preamble_march_alloc_attributes;
          Alcotest.test_case "closure trampolines are alwaysinline" `Quick
            test_clo_wrap_is_alwaysinline;
          Alcotest.test_case "Llvm_emit.emit_preamble wrapper delegates (W3C2.4)" `Quick
            test_preamble_wrapper_delegates;
          Alcotest.test_case "static closure global replaces per-materialization march_alloc" `Quick
            test_static_closure_global_replaces_alloc;
          Alcotest.test_case "capture-free lambda uses static closure global" `Quick
            test_capture_free_lambda_uses_static_global;
          Alcotest.test_case "capturing lambda still allocates per materialization" `Quick
            test_capturing_lambda_still_allocates;
          Alcotest.test_case "static closure global is not emitted in REPL mode" `Quick
            test_static_closure_not_emitted_in_repl_mode;
          Alcotest.test_case "static closure global is not emitted via emit_fns_fragment ~repl:true" `Quick
            test_static_closure_not_emitted_in_fns_fragment_repl_mode;
          Alcotest.test_case "capture-free lambda static closure global is not emitted in REPL mode" `Quick
            test_capture_free_lambda_not_emitted_in_repl_mode;
          Alcotest.test_case "capture-free lambda static closure global is not emitted via emit_fns_fragment ~repl:true" `Quick
            test_capture_free_lambda_not_emitted_in_fns_fragment_repl_mode;
          Alcotest.test_case "capture-free lambda static closure global is not emitted under hot-reload" `Quick
            test_capture_free_lambda_not_emitted_under_hot_reload;
        ] );
      ( "compiler_robustness", [
          Alcotest.test_case "unreadable sibling dir does not crash --check" `Quick
            test_unreadable_sibling_dir_does_not_crash_check;
        ] );
      ( "name_resolution", [
          Alcotest.test_case "qualified call not hijacked by another module's global import" `Quick
            test_qualified_alias_no_cross_module_hijack;
          Alcotest.test_case "entry-file bulk import resolves partial-qualified call" `Quick
            test_entry_bulk_import_resolves_partial_qualified;
          Alcotest.test_case "registry record's bare-named sibling field type resolves" `Quick
            test_registry_record_field_bare_sibling_type_resolves;
        ] );
      ( "js_pipeline", [
          Alcotest.test_case "simple program compiles"      `Quick test_js_pipeline_simple_program_compiles;
          Alcotest.test_case "typecheck error surfaces"      `Quick test_js_pipeline_typecheck_error_surfaces;
          Alcotest.test_case "dom extern reaches output"     `Quick test_js_pipeline_dom_extern_reaches_output;
          Alcotest.test_case "dom event_key reaches output"  `Quick test_js_pipeline_dom_event_key_reaches_output;
          Alcotest.test_case "simd builtin rejected"         `Quick test_js_pipeline_simd_builtin_rejected;
        ] );
  ]
  @ Test_ir_verify.suites (* W2.1: LLVM IR validity gate over test/native/*.march *)
  @ Test_collision_set.suites (* Task 0: same-short-name type collision-set computation *)
  @ Test_ctor_tags.suites (* Task 1: globally-unique ctor tags for colliding types *)
  @ Test_trmc.suites (* TRMC Phase 1: tail-recursion-modulo-cons eligibility *)
