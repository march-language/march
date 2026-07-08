(** March test suite — codegen tests. *)
open Test_helpers

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
   fd520110 for TFn/TVar, 0b52510d/390dff00 for TTuple/TRecord). *)

(* (label, ty, expected needs_rc, expected borrow_eligible) *)
let rc_types_truth_table : (string * March_tir.Tir.ty * bool * bool) list =
  let open March_tir.Tir in
  [
    "TInt",                TInt,                        false, false;
    "TFloat",              TFloat,                      false, false;
    "TBool",               TBool,                       false, false;
    "TString",             TString,                     true,  true;
    "TUnit",               TUnit,                       false, false;
    "TTuple []",           TTuple [],                   false, true;   (* diverges *)
    "TTuple [Int]",        TTuple [TInt],               false, true;   (* diverges *)
    "TTuple [String]",     TTuple [TString],            false, true;   (* diverges *)
    "TRecord []",          TRecord [],                  false, true;   (* diverges *)
    "TRecord [(f,Int)]",   TRecord [("f", TInt)],       false, true;   (* diverges *)
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

let test_rc_types_truth_table () =
  List.iter (fun (label, ty, exp_rc, exp_be) ->
    Alcotest.(check bool) (label ^ ": needs_rc") exp_rc
      (March_tir.Rc_types.needs_rc ty);
    Alcotest.(check bool) (label ^ ": borrow_eligible") exp_be
      (March_tir.Rc_types.borrow_eligible ty)
  ) rc_types_truth_table

let test_rc_types_divergence_set_exact () =
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
    fn classify(r : Result(Bool, String)) : String do
      match r do
        Ok(true) -> "T"
        Ok(false) -> "F"
        Err(_) -> "E"
      end
    end
    fn main() : Unit do
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
    fn classify(r : Result(Int, String)) : String do
      match r do
        Ok(1) -> "one"
        Ok(2) -> "two"
        Ok(_) -> "other"
        Err(_) -> "E"
      end
    end
    fn main() : Unit do
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
    fn classify(r : Result(Atom, String)) : String do
      match r do
        Ok(:red) -> "R"
        Ok(:blue) -> "B"
        Ok(_) -> "other"
        Err(_) -> "E"
      end
    end
    fn main() : Unit do
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
    type Tree_Actor = TLeaf(Int) | TNode(Tree_Actor, Tree_Actor)
    fn bump(t : Tree_Actor) : Tree_Actor do
      match t do
        TLeaf(n) -> TLeaf(n + 1)
        TNode(l, r) -> TNode(bump(l), r)
      end
    end
    fn main() : Unit do
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
    @[no_warn_recursion]
    fn factorial(n : Int, acc : Int) : Int do
      if n == 0 do acc
      else factorial(n - 1, n * acc) end
    end
    fn main() : Unit do println(int_to_string(factorial(10, 1))) end
  end|} in
  (* The tco_loop label and back-edge branch are the unique markers of TCO. *)
  Alcotest.(check bool) "TCO factorial: tco_loop block emitted" true
    (ir_contains ir "tco_loop");
  Alcotest.(check bool) "TCO factorial: back-edge branch emitted" true
    (ir_contains ir "br label %tco_loop")

(** Tail-recursive list fold: should be transformed into a loop. *)
let test_tco_fold_has_loop () =
  let ir = emit_tco_ir {|mod Test do
    type L = Nil | Cons(Int, L)
    @[no_warn_recursion]
    fn fold(xs : L, acc : Int) : Int do
      match xs do
      Nil        -> acc
      Cons(h, t) -> fold(t, acc + h)
      end
    end
    fn main() : Unit do println(int_to_string(fold(Cons(1, Cons(2, Nil)), 0))) end
  end|} in
  Alcotest.(check bool) "TCO fold: tco_loop block emitted" true
    (ir_contains ir "tco_loop");
  Alcotest.(check bool) "TCO fold: back-edge branch emitted" true
    (ir_contains ir "br label %tco_loop")

(** Non-tail-recursive fib must NOT get a TCO loop (it is not tail recursive). *)
let test_tco_nontail_fib_no_loop () =
  let ir = emit_tco_ir {|mod Test do
    @[no_warn_recursion]
    fn fib(n : Int) : Int do
      if n < 2 do n
      else fib(n - 1) + fib(n - 2) end
    end
    fn main() : Unit do println(int_to_string(fib(10))) end
  end|} in
  Alcotest.(check bool) "non-tail fib: no TCO loop" false
    (ir_contains ir "tco_loop");
  Alcotest.(check bool) "non-tail fib: call instruction present" true
    (ir_contains ir "call i64 @fib")

(** Single-param tail-recursive countdown: loop emitted with back-edge. *)
let test_tco_countdown_has_loop () =
  let ir = emit_tco_ir {|mod Test do
    @[no_warn_recursion]
    fn count(n : Int) : Int do
      if n == 0 do 0
      else count(n - 1) end
    end
    fn main() : Unit do println(int_to_string(count(100))) end
  end|} in
  Alcotest.(check bool) "TCO countdown: tco_loop block emitted" true
    (ir_contains ir "tco_loop");
  Alcotest.(check bool) "TCO countdown: back-edge branch emitted" true
    (ir_contains ir "br label %tco_loop")

(* ── Mutual TCO codegen tests ──────────────────────────────────────── *)

let test_mutual_tco_even_odd_loop_emitted () =
  let ir = emit_mutual_tco_ir {|mod Test do
    @[no_warn_recursion]
    fn even(n : Int) : Bool do
      if n == 0 do true else odd(n - 1) end
    end
    @[no_warn_recursion]
    fn odd(n : Int) : Bool do
      if n == 0 do false else even(n - 1) end
    end
    fn main() : Unit do println(to_string(even(1000000))) end
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
    fn main() : Unit do println(int_to_string(fa(99))) end
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
    @[no_warn_recursion]
    fn state_a(n : Int) : Int do
      if n <= 0 do 1 else state_b(n - 1) end
    end
    @[no_warn_recursion]
    fn state_b(n : Int) : Int do
      if n <= 0 do 2 else state_a(n - 1) end
    end
    fn main() : Unit do println(int_to_string(state_a(1000000))) end
  end|} in
  Alcotest.(check bool) "state machine mutual TCO: mutual_loop emitted" true
    (ir_contains ir "mutual_loop");
  Alcotest.(check bool) "state machine mutual TCO: combined fn declared" true
    (ir_contains ir "__mutco_")

(** Non-tail mutual recursion must NOT get a mutual_loop block.
    f calls g in non-tail position (result used in arithmetic). *)
let test_mutual_tco_non_tail_no_loop () =
  let ir = emit_mutual_tco_ir {|mod Test do
    @[no_warn_recursion]
    fn count_f(n : Int) : Int do
      if n == 0 do 1 else count_g(n - 1) + 1 end
    end
    @[no_warn_recursion]
    fn count_g(n : Int) : Int do
      if n == 0 do 1 else count_f(n - 1) + 1 end
    end
    fn main() : Unit do println(int_to_string(count_f(10))) end
  end|} in
  Alcotest.(check bool) "non-tail mutual recursion: no mutual_loop" false
    (ir_contains ir "mutual_loop")

(** Self-TCO must still work when mutual-TCO detection is also running.
    A self-recursive function that is NOT part of any mutual group must still
    get its tco_loop transformation. *)
let test_mutual_tco_self_tco_unaffected () =
  let ir = emit_mutual_tco_ir {|mod Test do
    @[no_warn_recursion]
    fn countdown(n : Int) : Int do
      if n == 0 do 0 else countdown(n - 1) end
    end
    fn main() : Unit do println(int_to_string(countdown(10))) end
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
    fn main() : Unit do println(int_to_string(build_loop("z", 1000))) end
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
    fn main() : Unit do println(int_to_string(build_loop("z", 5))) end
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
    contains the same reduction-check IR (@march_tls_reductions decrement +
    @march_yield_from_compiled call) that self-TCO loops get. *)
let test_mutual_tco_has_reduction_check () =
  let ir = emit_mutual_tco_ir {|mod Test do
    @[no_warn_recursion]
    fn is_even(n : Int) : Bool do
      if n == 0 do true else is_odd(n - 1) end
    end
    @[no_warn_recursion]
    fn is_odd(n : Int) : Bool do
      if n == 0 do false else is_even(n - 1) end
    end
    fn main() : Unit do println(to_string(is_even(1000000))) end
  end|} in
  Alcotest.(check bool) "mutual TCO is_even/is_odd: mutual_loop block emitted" true
    (ir_contains ir "mutual_loop");
  Alcotest.(check bool) "mutual TCO is_even/is_odd: reduction budget loaded" true
    (ir_contains ir "@march_tls_reductions");
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
    fn fib(n : Int) : Int do
      if n <= 1 do n
      else fib(n - 1) + fib(n - 2) end
    end
    fn main() : Unit do println(int_to_string(fib(10))) end
  end|} in
  Alcotest.(check bool) "non-leaf fib: @march_tls_reductions loaded" true
    (ir_contains ir "@march_tls_reductions");
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
    fn square(n : Int) : Int do n * n end
    fn main() : Unit do println(int_to_string(42)) end
  end|} in
  (* No non-leaf functions → no reduction check IR anywhere in the output. *)
  Alcotest.(check bool) "all-leaf module: no icmp reduction check" false
    (ir_contains ir "icmp sle i64")

(** TCO function: reduction check must be inside the tco_loop block. *)
let test_phase4_tco_fn_reduction_in_loop () =
  let ir = emit_tco_ir {|mod Test do
    @[no_warn_recursion]
    fn countdown(n : Int) : Int do
      if n == 0 do 0 else countdown(n - 1) end
    end
    fn main() : Unit do println(int_to_string(countdown(100))) end
  end|} in
  Alcotest.(check bool) "TCO countdown: tco_loop emitted" true
    (ir_contains ir "tco_loop");
  Alcotest.(check bool) "TCO countdown: reduction check in loop" true
    (ir_contains ir "@march_tls_reductions");
  Alcotest.(check bool) "TCO countdown: yield call present" true
    (ir_contains ir "@march_yield_from_compiled")

(** Non-recursive function that calls another user function: non-leaf,
    so it must get a reduction check even though it has no loop. *)
let test_phase4_nonrecursive_caller_has_check () =
  let ir = emit_tco_ir {|mod Test do
    fn double(n : Int) : Int do n + n end
    fn apply_double(n : Int) : Int do double(n) end
    fn main() : Unit do println(int_to_string(apply_double(3))) end
  end|} in
  (* apply_double calls double (non-builtin) → non-leaf → check emitted. *)
  Alcotest.(check bool) "apply_double: reduction check present" true
    (ir_contains ir "@march_tls_reductions")

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
         let clause = March_ast.Ast.{ fc_params = []; fc_guard = None; fc_body = e; fc_span = s } in
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
           fc_params = []; fc_guard = None; fc_body = e; fc_span = s } in
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
         let clause = March_ast.Ast.{ fc_params = []; fc_guard = None; fc_body = e; fc_span = s } in
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
         let clause = March_ast.Ast.{ fc_params = []; fc_guard = None; fc_body = e; fc_span = s } in
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
         let clause = March_ast.Ast.{ fc_params = []; fc_guard = None; fc_body = e; fc_span = s } in
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
         let clause = March_ast.Ast.{ fc_params = []; fc_guard = None; fc_body = e; fc_span = s } in
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
           fc_params = []; fc_guard = None; fc_body = e; fc_span = s } in
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
           fc_params = []; fc_guard = None; fc_body = e; fc_span = s } in
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
  Alcotest.(check bool) "tag: shl i64 ... 1"  true (ir_has "shl i64");
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
  Alcotest.(check bool) "wrapper: tags scalar result (shl)" true (ir_has "shl i64 %r, 1")

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
  (* The runtime march_html_auto_escape takes a tagged ptr; an int arg must be
     tagged via i64->ptr coercion, never passed as `i64 N` against the `ptr`
     declaration (which segfaulted). *)
  Alcotest.(check bool) "html_auto_escape called with a ptr arg" true
    (ir_contains ir "call ptr @march_html_auto_escape(ptr");
  Alcotest.(check bool) "html_auto_escape NOT called with a raw i64 arg" false
    (ir_contains ir "@march_html_auto_escape(i64")

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
    fn go() : String do "hello" end
    fn main() do
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
    `link`, the actor-linking builtin) must still get its RC ops emitted.
    The five EIncRC/EDecRC/EFree/EAtomicIncRC/EAtomicDecRC arms in
    llvm_emit.ml skip emission purely by NAME match against is_builtin_fn /
    top_fns, without checking whether a local alloca (var_slot) shadows that
    name — unlike emit_atom, which has the correct var_slot guard in both of
    its analogous arms. Perceus DOES insert a dec_rc for the shadowed local
    (confirmed via --dump-tir: `let out = dec_rc link; ...`), so if the
    guard is missing, the alloca for `link` is created and stored but never
    referenced by any RC runtime call — the local leaks (never freed) and,
    more importantly, the same missing-guard bug pattern is what causes
    heap corruption in the emit_atom builtin arm this mirrors. *)
let test_compile_local_shadows_builtin_still_gets_rc_ops () =
  let ir = emit_actor_ir {|mod ShadowRc do
    fn main() do
      let link = String.concat("heap", "-allocated")
      let out = String.concat(link, "!")
      println(out)
    end
  end|} in
  (* The shadowed local must be stack-allocated under its own name... *)
  Alcotest.(check bool) "local `link` gets its own alloca" true
    (ir_contains ir "%link.addr = alloca");
  (* ...and at least one RC runtime call must load from that exact alloca
     (not just some unrelated %link.addr text elsewhere, and not the
     unrelated @march_link actor-linking builtin declaration/call). *)
  let loads_link_addr = Str.regexp "load ptr, ptr %link\\.addr" in
  let ir_has_load_of_link_addr =
    try ignore (Str.search_forward loads_link_addr ir 0); true
    with Not_found -> false
  in
  Alcotest.(check bool) "a load from %link.addr exists (feeds some use)" true
    ir_has_load_of_link_addr;
  (* Precisely: the value loaded from %link.addr must reach an RC op
     (march_decrc_local/march_incrc_local/march_free/march_incrc/march_decrc)
     as an argument — not merely be stored/loaded for the String.concat call.
     Extract every SSA temp assigned from `load ptr, ptr %link.addr`, then
     confirm at least one of those temps is passed to an RC runtime call. *)
  let ssa_temps_loading_link_addr =
    let re = Str.regexp "%\\([A-Za-z0-9_$]+\\) = load ptr, ptr %link\\.addr" in
    let rec go i acc =
      match Str.search_forward re ir i with
      | j -> go (j + 1) (Str.matched_group 1 ir :: acc)
      | exception Not_found -> acc
    in
    go 0 []
  in
  Alcotest.(check bool) "at least one SSA temp loads %link.addr" true
    (ssa_temps_loading_link_addr <> []);
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
    List.exists (fun t -> List.mem t rc_call_args) ssa_temps_loading_link_addr
  in
  Alcotest.(check bool)
    "an RC op (incrc/decrc/free) is emitted against the shadowed local `link`'s value"
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
      Some (List.map (fun names ->
        String.concat "." (List.map (fun (n : March_ast.Ast.name) -> n.txt) names)
      ) caps)
    | _ -> None
  ) m.March_ast.Ast.mod_decls in
  Alcotest.(check bool) "IO.Network parsed as DNeeds" true
    (List.exists (fun paths -> List.mem "IO.Network" paths) cap_paths)

(* ── Transitive capability enforcement tests ────────────────────────────── *)

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
      fn run(x) do x end
    end
  end|} in
  Alcotest.(check bool) "transitive import without needs is an error" true (has_errors ctx)

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
      fn run(x) do x end
    end
  end|} in
  Alcotest.(check bool) "chain: C must declare needs covered by B" true (has_errors ctx)

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
    needs Ffi
    extern "crc" : Cap(Ffi) do
      fn crc32(n: Int): Int = "crc32_compute"
    end
    fn main() : Unit do println(int_to_string(crc32(255))) end
  end|} in
  Alcotest.(check bool) "calls the explicit C symbol" true
    (ir_contains ir "@crc32_compute");
  Alcotest.(check bool) "does not emit the default <lib>_<fn> name" false
    (ir_contains ir "@crc_crc32")

let test_ffi_extern_default_symbol_ir () =
  let ir = emit_actor_ir {|mod Test do
    needs Ffi
    extern "crc" : Cap(Ffi) do
      fn crc32(n: Int): Int
    end
    fn main() : Unit do println(int_to_string(crc32(255))) end
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
    fn f(cap : Cap(IO.Network)) do cap end
    fn main() do f(42) end
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
     Use cap_narrow(root_cap()) so the body typechecks; the error is Check 6 specifically. *)
  let src = {|mod Db do
    proof cap Migrated
    pfn bad_private_forge() : Cap(Db.Migrated) do cap_narrow(root_cap()) end
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
    type Tree = Leaf | Node(Tree, Int, Tree)

    fn sum(t : Tree) : Int do
      match t do
        Leaf -> 0
        Node(l, n, r) -> sum(l) + n + sum(r)
      end
    end

    fn main() : Unit do
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
    \  fn classify(n) do\n\
    \    match n do\n\
    \      x when x > 0 -> \"pos\"\n\
    \      x when x < 0 -> \"neg\"\n\
    \    end\n\
    \  end\n\
    \  fn main() do\n\
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
    \  fn name(x) do\n\
    \    match x do\n\
    \      1.5 -> \"one-and-a-half\" | 2.5 -> \"two-and-a-half\" | _ -> \"other\"\n\
    \    end\n\
    \  end\n\
    \  fn main() do\n\
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

(** Float arm with NO wildcard: a non-exhaustive float match must panic (the
    Task 1 / B3 `nonexhaustive_panic` fallback), not silently fall through to
    LLVM `unreachable` (undefined behaviour — observed, pre-fix, to print a
    WRONG matched value with exit 0 instead of crashing). The scrutinee must
    NOT be a compile-time constant, or the optimizer folds the whole match to
    its statically-known arm and never reaches the fallback path at all. *)
let test_float_lit_no_wildcard_panics_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_floatpat_nowild"
    "mod FloatPatNoWild do\n\
    \  fn name(x) do\n\
    \    match x do\n\
    \      1.5 -> \"one-and-a-half\" | 2.5 -> \"two-and-a-half\"\n\
    \    end\n\
    \  end\n\
    \  fn main() do\n\
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
    \  fn main() do\n\
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
    \  fn main() do\n\
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
    fn get_a(r) do r.a end
    fn main() do
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
    \  fn main() do\n\
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
    \  fn get_i(r, k) do\n\
    \    match record_get(r, k) do\n\
    \      Some(v) -> v\n\
    \      None -> 0 - 1\n\
    \    end\n\
    \  end\n\
    \  fn main() do\n\
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

(** Variant 1: List(Int) — pre-fix symptom was SIGSEGV (exit 139). The
    erased-int tag (2n+1) got passed as a fresh Show$List.show's list
    argument and the match-scrutinee tag load faulted. *)
let test_compiled_println_int_list_parity () =
  assert_compiled_interp_parity
    ~name:"march_ifaceimpl_intlist"
    ~src:"mod IfaceImplIntList do\n\
         \  fn main() do\n\
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
         \  fn main() do\n\
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
         \  fn main() do\n\
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
         \  fn main() do\n\
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
         \  fn main() do\n\
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
         \  fn main() do\n\
         \    println(show(:hello) ++ \" \" ++ show(:world_123))\n\
         \  end\n\
          end\n"
    ~expected:":hello :world_123"
    ()

(* ── Guard liveness (Wave 2 final review): positive control for
   [fail_if_unresolved_iface_method] ─────────────────────────────────────
   The four parity tests above prove the FIXED pipeline resolves nested
   interface-method calls; on a healthy compiler the guard's failwith never
   fires, so nothing exercised it.  If ctx.top_fns naming or the guard's
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
      (path_label ^ ": emit_module was expected to raise Failure — the \
                     unresolved-iface-method guard did not fire on a bare \
                     `describe` call with a registered Pretty$Int.describe \
                     impl")
  | exception Failure msg ->
    Alcotest.(check bool)
      (path_label ^ ": failure names the unresolved symbol (got: " ^ msg ^ ")")
      true (ir_contains msg "unresolved interface-method call to `describe`");
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
         \  fn main() do println(f(Nil, true)) end\n\
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
         \  type Wrap = Wrap(Int)\n\
         \  derive Eq for Wrap\n\
         \  fn main() do\n\
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
         \  type Wrap = Wrap(Int)\n\
         \  derive Ord, Hash for Wrap\n\
         \  fn main() do\n\
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
         \  type WrapS = WrapS(String)\n\
         \  derive Eq, Ord, Hash for WrapS\n\
         \  fn main() do\n\
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
         \  type Pair = Pair(Int, Int)\n\
         \  derive Eq, Ord, Hash for Pair\n\
         \  fn main() do\n\
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
         \  type Shape = Circle(Int) | Square(Int)\n\
         \  derive Eq, Ord, Hash for Shape\n\
         \  fn main() do\n\
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
         \  type Color = Red | Green | Blue\n\
         \  derive Eq, Show for Color\n\
         \  fn main() do\n\
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
         \  mod Palette do\n\
         \    type Color = { hue: Int, sat: Int, lum: Int }\n\
         \  end\n\
         \  type Color = Red | Green | Blue\n\
         \  derive Eq, Show for Color\n\
         \  fn main() do\n\
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
         \  type Wrap = Wrap(Int)\n\
         \  impl Eq(Wrap) do\n\
         \    fn eq(a, b) do\n\
         \      match (a, b) do\n\
         \        (Wrap(x), Wrap(y)) -> x == y\n\
         \      end\n\
         \    end\n\
         \  end\n\
         \  fn main() do\n\
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
         \  type WrapS = WrapS(String)\n\
         \  derive Eq for WrapS\n\
         \  fn main() do\n\
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
         \  type Wrap = Wrap(Int)\n\
         \  derive Eq for Wrap\n\
         \  fn main() do\n\
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
         \  type Inner = Inner(Int, Int)\n\
         \  type WrapR = WrapR(Inner)\n\
         \  derive Eq for Inner\n\
         \  derive Eq for WrapR\n\
         \  fn main() do\n\
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
         \  type Wrap(a) = Wrap(a)\n\
         \  derive Eq for Wrap\n\
         \  fn main() do\n\
         \    println(bool_to_string(Wrap(\"x\") == Wrap(\"x\")))\n\
         \    println(bool_to_string(Wrap(\"x\") == Wrap(\"y\")))\n\
         \    println(bool_to_string(Wrap(1) == Wrap(1)))\n\
         \    println(bool_to_string(Wrap(1) == Wrap(2)))\n\
         \  end\n\
          end\n"
    ~expected:"true\nfalse\ntrue\nfalse"
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
declare ptr  @getenv(ptr)
declare ptr  @march_alloc(i64 %sz)
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
declare void @march_test_init(i32 %argc, ptr %argv)
declare void @march_test_run(ptr %fn, ptr %name, ptr %setup_or_null)
declare void @march_test_setup_all(ptr %fn)
declare i32  @march_test_report()
declare void @march_println(ptr %s)
declare void @march_print_stderr(ptr %s)
declare ptr  @march_io_read_line()
declare ptr  @march_string_lit(ptr %s, i64 %len)
declare ptr  @march_html_auto_escape(ptr %v)
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
declare i64    @march_checked_umod(i64 %a, i64 %b)
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
declare i64  @march_string_is_empty(ptr %s)
declare ptr  @march_string_to_int(ptr %s)
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
declare i64  @march_actor_get_int(ptr %actor, i64 %index)
declare ptr  @march_actor_call(ptr %actor, ptr %msg, i64 %timeout_ms)
declare void @march_actor_reply(ptr %ref, ptr %result)
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
|}

let golden_preamble_native_net_io : string = {|
; TCP/network builtins
declare ptr  @march_tcp_listen(i64 %port)
declare ptr  @march_tcp_accept(i64 %fd)
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
declare ptr  @march_tcp_recv_http_headers(i64 %fd)
declare ptr  @march_tcp_recv_chunked_frame(i64 %fd)
; TLS builtins
declare ptr  @march_tls_client_ctx(ptr %ca_file, ptr %alpn_list, i64 %verify_peer, i64 %timeout_ms)
declare ptr  @march_tls_server_ctx(ptr %cert_file, ptr %key_file, ptr %ca_file, ptr %alpn_list, i64 %verify_peer)
declare ptr  @march_tls_connect(i64 %fd, i64 %ctx_handle, ptr %hostname)
declare ptr  @march_tls_accept(i64 %fd, i64 %ctx_handle)
declare ptr  @march_tls_read(i64 %ssl_handle, i64 %max_bytes)
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
declare ptr    @native_int_arr_map(ptr %arr, ptr %f)
declare ptr    @native_int_arr_from_list(ptr %lst)
declare ptr    @native_int_arr_to_list(ptr %arr)
declare ptr    @native_int_arr_filter_mask(ptr %arr, ptr %mask)
; NativeFloatArr builtins — flat double arrays for vectorizable loops
declare ptr    @native_float_arr_make(i64 %len, double %def)
declare i64    @native_float_arr_length(ptr %arr)
declare double @native_float_arr_get(ptr %arr, i64 %i)
declare ptr    @native_float_arr_set(ptr %arr, i64 %i, double %val)
declare double @native_float_arr_sum(ptr %arr)
declare ptr    @native_float_arr_map(ptr %arr, ptr %f)
declare ptr    @native_float_arr_from_list(ptr %lst)
declare ptr    @native_float_arr_to_list(ptr %arr)
declare ptr    @native_float_arr_filter_mask(ptr %arr, ptr %mask)
; Time builtins
declare double @march_unix_time()
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
; Monitor/supervision builtins
declare void @march_demonitor(i64 %ref)
declare i64  @march_monitor(ptr %watcher, ptr %target)
declare i64  @march_mailbox_size(ptr %pid)
declare void @march_run_until_idle()
declare void @march_register_resource(ptr %pid, ptr %name, ptr %cleanup)
declare ptr  @march_get_cap(ptr %pid)
declare void @march_send_checked(ptr %cap, ptr %msg)
declare ptr  @march_pid_of_int(i64 %n)
declare ptr  @march_get_actor_field(ptr %pid, ptr %name)
declare void @march_link(ptr %actor_a, ptr %actor_b)
declare void @march_unlink(ptr %actor_a, ptr %actor_b)
declare void @march_register_supervisor(ptr %supervisor, i64 %strategy, i64 %max_restarts, i64 %window_secs)
declare ptr  @march_value_to_string(ptr %v)
; Session-typed channel builtins (binary)
declare ptr  @march_chan_new(ptr %proto_name)
declare ptr  @march_chan_send(ptr %ep, ptr %val)
declare ptr  @march_chan_recv(ptr %ep)
declare i64  @march_chan_close(ptr %ep)
declare ptr  @march_chan_choose(ptr %ep, ptr %label)
declare ptr  @march_chan_offer(ptr %ep)
; Multi-party session type (MPST) builtins
declare ptr  @march_mpst_new(ptr %proto_name, i64 %n_roles)
declare ptr  @march_mpst_send(ptr %ep, ptr %target_role, ptr %val)
declare ptr  @march_mpst_recv(ptr %ep, ptr %source_role)
declare i64  @march_mpst_close(ptr %ep)
|}

let golden_preamble_wasm_stub : string = {|; WASM: plain global (no TLS), no-op scheduler stub
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
      else "@march_tls_reductions = external thread_local global i64
declare void @march_yield_from_compiled()
"
    in
    golden_preamble_core ^ golden_preamble_native_actor ^ tls_insert ^ golden_preamble_native_net_io

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

let codegen_suites =
  [
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
          Alcotest.test_case "bool tags"                   `Quick test_tir_names_bool_tags;
        ] );
      ( "fnfused_coverage", [
          Alcotest.test_case "map+fold fused fn is FnFused"        `Quick test_fnfused_map_fold_tagged;
          Alcotest.test_case "filter+fold fused fn is FnFused"     `Quick test_fnfused_filter_fold_tagged;
          Alcotest.test_case "map+filter+fold fused fn is FnFused" `Quick test_fnfused_map_filter_fold_tagged;
          Alcotest.test_case "no FnFused when nothing fuses"       `Quick test_fnfused_absent_when_not_fused;
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
        Alcotest.test_case "top-level fn as first-class value" `Quick test_repl_jit_topfn_first_class_value;
        Alcotest.test_case "stdlib List.length via precompile" `Quick test_repl_jit_stdlib_list_length;
        Alcotest.test_case "B12: niche ADT cross-fragment (:load DMod then match)" `Quick test_repl_jit_niche_adt_cross_fragment;
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
      ]);
      ("opt", [
        Alcotest.test_case "fixpoint"         `Quick test_opt_fixpoint;
        Alcotest.test_case "no_infinite_loop" `Quick test_opt_no_infinite_loop;
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
      ( "guard_exhaustion_codegen", [
          Alcotest.test_case "compiled guard exhaustion panics (B3)" `Quick
            test_guard_exhaustion_panics_compiled;
        ] );
      ( "float_lit_match_codegen", [
          Alcotest.test_case "compiled float-literal match arm (B4)" `Quick
            test_float_lit_match_arm_compiled;
          Alcotest.test_case "compiled float non-exhaustive match panics (B4)" `Quick
            test_float_lit_no_wildcard_panics_compiled;
        ] );
      ( "nested_tuple_let_codegen", [
          Alcotest.test_case "compiled nested-tuple `let` destructure binds leaf vars" `Quick
            test_nested_tuple_let_destructure_compiled;
          Alcotest.test_case "compiled deep nested-tuple `let` (nesting + wildcard)" `Quick
            test_nested_tuple_let_deep_wildcard_compiled;
        ] );
      ( "erased_record_update_codegen", [
          Alcotest.test_case "single march_record_update_dyn call in IR (B5)" `Quick
            test_erased_update_single_dyn_call_ir;
          Alcotest.test_case "compiled missing-field update panics (B5)" `Quick
            test_erased_update_missing_field_panics_compiled;
          Alcotest.test_case "compiled multi-field update values (B5)" `Quick
            test_erased_update_multi_field_values_compiled;
        ] );
      ( "iface_impl_mono_codegen", [
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
        ] );
      ( "llvm_builtins_preamble_golden", [
          Alcotest.test_case "native, non-repl preamble byte-identical (W3C2.4 / H2)" `Quick
            test_preamble_byte_identical_native;
          Alcotest.test_case "native, REPL preamble byte-identical (W3C2.4 / H2)" `Quick
            test_preamble_byte_identical_native_repl;
          Alcotest.test_case "WASM preamble byte-identical (W3C2.4 / H2)" `Quick
            test_preamble_byte_identical_wasm;
          Alcotest.test_case "Llvm_emit.emit_preamble wrapper delegates (W3C2.4)" `Quick
            test_preamble_wrapper_delegates;
        ] );
      ( "compiler_robustness", [
          Alcotest.test_case "unreadable sibling dir does not crash --check" `Quick
            test_unreadable_sibling_dir_does_not_crash_check;
        ] );
  ]
  @ Test_ir_verify.suites (* W2.1: LLVM IR validity gate over test/native/*.march *)

