(* Tests for [Kind], the per-type table (specs/2026-09-10-type-kinds-design.md).

   The truth table and divergence-set cases are the ones that used to live in
   test_codegen.ml's "rc_types" group, retargeted at the table; the fixture
   list is copied verbatim so a reviewer can diff the two. *)

open March_tir

let empty_cs () : (string, string list) Hashtbl.t = Hashtbl.create 0

(* ── needs_rc / borrowable truth table (moved from test_codegen.ml) ────

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

(* (label, ty, expected needs_rc, expected borrowable) *)
let rc_truth_table : (string * Tir.ty * bool * bool) list =
  let open Tir in
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

let test_truth_table () =
  List.iter (fun (label, ty, exp_rc, exp_bo) ->
      let k = Kind.of_ty Kind.empty ty in
      Alcotest.(check bool) (label ^ ": needs_rc") exp_rc k.Kind.needs_rc;
      Alcotest.(check bool) (label ^ ": borrowable") exp_bo k.Kind.borrowable)
    rc_truth_table

let test_divergence_set_exact () =
  (* Exactly the {TFn, bare TVar, TTuple, TRecord} rows diverge — computed
     from the live table, compared against the constructor-classified
     expectation, so a new divergence (or a silently unified arm) fails
     loudly here even if the truth-table rows above were edited in sync. *)
  let expected_divergent (ty : Tir.ty) : bool =
    match ty with
    | Tir.TFn _ | Tir.TTuple _ | Tir.TRecord _ -> true
    | Tir.TVar "_" -> false
    | Tir.TVar _ -> true
    | _ -> false
  in
  List.iter (fun (label, ty, _, _) ->
      let k = Kind.of_ty Kind.empty ty in
      Alcotest.(check bool) (label ^ ": diverges iff TFn/bare-TVar/TTuple/TRecord")
        (expected_divergent ty) (k.Kind.needs_rc <> k.Kind.borrowable))
    rc_truth_table

(* ── Representation classification ───────────────────────────────────── *)

let fixture_defs : Tir.type_def list =
  let open Tir in
  [
    TDVariant ("Color",   [ ("Red", []); ("Green", []); ("Blue", []) ]);
    TDVariant ("Option",  [ ("None", []); ("Some", [TVar "a"]) ]);
    TDVariant ("Wrap",    [ ("Wrap", [TInt]) ]);                       (* newtype *)
    TDVariant ("FWrap",   [ ("FWrap", [TFloat]) ]);                    (* Float newtype: Boxed *)
    TDVariant ("Vec3",    [ ("Vec3", [TFloat; TFloat; TFloat]) ]);     (* unboxed *)
    TDVariant ("Pair",    [ ("Pair", [TInt; TString]) ]);              (* not unboxed: String *)
    TDVariant ("Tree",    [ ("Leaf", [TInt]); ("Node", [TCon ("Tree", []); TCon ("Tree", [])]) ]);
    TDVariant ("Counter" ^ Tir_names.actor_msg_suffix, [ ("Inc", [TInt; TInt]) ]);
    TDRecord  ("Rec",     [ ("f", TFn ([TInt], TInt)); ("n", TInt) ]);
    TDVariant ("Deep",    [ ("Deep", [TCon ("Tree", [])]); ("DeepF", [TCon ("FWrap", [])]) ]);
    (* mutually recursive pair *)
    TDVariant ("A",       [ ("A", [TCon ("B", [])]); ("ANil", []) ]);
    TDVariant ("B",       [ ("B", [TCon ("A", [])]) ]);
  ]

let table ?(unboxing = true) ?(externs = []) ?collision_set defs =
  let collision_set = match collision_set with
    | Some cs -> cs
    | None -> Collision_set.compute defs in
  Kind.build ~externs ~unboxing ~collision_set defs

let repr_pp = Alcotest.testable
    (fun fmt r -> Format.pp_print_string fmt
        (match r with
         | Kind.Boxed -> "Boxed"
         | Kind.Newtype _ -> "Newtype"
         | Kind.Niche { tagged; _ } -> if tagged then "Niche(tagged)" else "Niche"
         | Kind.Unboxed _ -> "Unboxed"))
    (fun a b -> match a, b with
       | Kind.Boxed, Kind.Boxed -> true
       | Kind.Newtype x, Kind.Newtype y -> x = y
       | Kind.Niche a, Kind.Niche b -> a.payload = b.payload && a.tagged = b.tagged
       | Kind.Unboxed a, Kind.Unboxed b -> a.ctor = b.ctor && a.fields = b.fields
       | _ -> false)

let test_repr_classification () =
  let open Tir in
  let t = table fixture_defs in
  let r ty = (Kind.of_ty t ty).Kind.repr in
  Alcotest.check repr_pp "all-nullary enum is Boxed" Kind.Boxed (r (TCon ("Color", [])));
  Alcotest.check repr_pp "Option(Int) is a tagged niche"
    (Kind.Niche { payload = TInt; tagged = true }) (r (TCon ("Option", [TInt])));
  Alcotest.check repr_pp "Option(String) is an untagged niche"
    (Kind.Niche { payload = TString; tagged = false }) (r (TCon ("Option", [TString])));
  Alcotest.check repr_pp "Option(Float) stays Boxed (0.0 is raw 0)"
    Kind.Boxed (r (TCon ("Option", [TFloat])));
  Alcotest.check repr_pp "Option(Option(Int)) stays Boxed (nested niche)"
    Kind.Boxed (r (TCon ("Option", [TCon ("Option", [TInt])])));
  Alcotest.check repr_pp "Option with no params is Boxed (cannot classify)"
    Kind.Boxed (r (TCon ("Option", [])));
  Alcotest.check repr_pp "Int newtype" (Kind.Newtype TInt) (r (TCon ("Wrap", [])));
  Alcotest.check repr_pp "Float newtype stays Boxed" Kind.Boxed (r (TCon ("FWrap", [])));
  Alcotest.check repr_pp "Vec3 is Unboxed"
    (Kind.Unboxed { ctor = "Vec3"; fields = [TFloat; TFloat; TFloat] }) (r (TCon ("Vec3", [])));
  Alcotest.check repr_pp "String-carrying single ctor is not unboxed"
    Kind.Boxed (r (TCon ("Pair", [])));
  Alcotest.check repr_pp "actor message type is forced Boxed"
    Kind.Boxed (r (TCon ("Counter" ^ Tir_names.actor_msg_suffix, [])));
  (* non-TCon types are Boxed by definition of the field *)
  Alcotest.check repr_pp "TInt repr is Boxed placeholder" Kind.Boxed (r TInt)

let test_forced_boxed_by_collision () =
  let open Tir in
  let defs = [ TDVariant ("M1.Vec3", [ ("Vec3", [TFloat; TFloat; TFloat]) ]);
               TDVariant ("M2.Vec3", [ ("Vec3", [TInt; TInt]) ]) ] in
  let t = table defs in
  Alcotest.check repr_pp "colliding short name M1.Vec3 is Boxed"
    Kind.Boxed (Kind.of_ty t (TCon ("M1.Vec3", []))).Kind.repr;
  Alcotest.check repr_pp "colliding short name M2.Vec3 is Boxed"
    Kind.Boxed (Kind.of_ty t (TCon ("M2.Vec3", []))).Kind.repr;
  Alcotest.(check int) "nothing unboxed" 0 (List.length (Kind.unboxed_types t))

let test_extern_crossing_stays_boxed () =
  let open Tir in
  let td = TDVariant ("Vec3", [ ("Vec3", [TFloat; TFloat; TFloat]) ]) in
  let t0 = table [td] in
  Alcotest.(check bool) "unboxed without an extern" true
    (Kind.unboxed_of_type_name t0 "Vec3" <> None);
  let ed = { ed_march_name = "f"; ed_c_name = "f"; ed_lib_name = "m";
             ed_js_sym = "f"; ed_params = [TCon ("Vec3", [])];
             ed_consumed = [false]; ed_blocking = false; ed_raises = false;
             ed_ret = TInt } in
  let t1 = table ~externs:[ed] [td] in
  Alcotest.(check bool) "boxed once it crosses an extern signature" false
    (Kind.unboxed_of_type_name t1 "Vec3" <> None)

let test_unboxing_off () =
  let open Tir in
  let td = TDVariant ("Vec3", [ ("Vec3", [TFloat; TFloat; TFloat]) ]) in
  let t = table ~unboxing:false [td] in
  Alcotest.check repr_pp "unboxing:false → Boxed" Kind.Boxed
    (Kind.of_ty t (TCon ("Vec3", []))).Kind.repr;
  Alcotest.(check string) "and llvm_ty is ptr" "ptr" (Kind.of_ty t (TCon ("Vec3", []))).Kind.llvm_ty

let test_unboxed_eligible_class () =
  let open Tir in
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
      let t = table [td] in
      let name = match td with
        | TDVariant (n, _) | TDRecord (n, _) | TDClosure (n, _) -> n in
      Alcotest.(check bool) (label ^ ": unboxed?") expected
        (Kind.unboxed_of_type_name t name <> None))
    cases

let test_llvm_ty_spelling () =
  let open Tir in
  let t = table fixture_defs in
  let l ty = (Kind.of_ty t ty).Kind.llvm_ty in
  Alcotest.(check string) "Int" "i64" (l TInt);
  Alcotest.(check string) "Float" "double" (l TFloat);
  Alcotest.(check string) "Bool" "i64" (l TBool);
  Alcotest.(check string) "Unit" "i64" (l TUnit);
  Alcotest.(check string) "Atom" "i64" (l (TCon ("Atom", [])));
  Alcotest.(check string) "String" "ptr" (l TString);
  Alcotest.(check string) "boxed TCon" "ptr" (l (TCon ("Color", [])));
  Alcotest.(check string) "Vec3 struct" "%ub.Vec3" (l (TCon ("Vec3", [])));
  Alcotest.(check string) "tuple" "ptr" (l (TTuple [TInt]));
  Alcotest.(check string) "record" "ptr" (l (TRecord []));
  Alcotest.(check string) "fn" "ptr" (l (TFn ([], TInt)));
  Alcotest.(check string) "TVar" "ptr" (l (TVar "a"));
  Alcotest.(check string) "SIMD vector is ptr at rest" "ptr" (l (TCon ("F32x4", [])))

(* ── Deep crossing facts ─────────────────────────────────────────────── *)

let test_crossing_facts () =
  let open Tir in
  let t = table fixture_defs in
  let cf ty = (Kind.of_ty t ty).Kind.closure_free
  and ff ty = (Kind.of_ty t ty).Kind.float_free in
  Alcotest.(check bool) "Int is closure_free" true (cf TInt);
  Alcotest.(check bool) "Int is float_free" true (ff TInt);
  Alcotest.(check bool) "Float is not float_free" false (ff TFloat);
  Alcotest.(check bool) "fn is not closure_free" false (cf (TFn ([], TInt)));
  Alcotest.(check bool) "record with a fn field is not closure_free" false (cf (TCon ("Rec", [])));
  Alcotest.(check bool) "record with a fn field is float_free" true (ff (TCon ("Rec", [])));
  Alcotest.(check bool) "recursive Tree terminates and is closure_free" true (cf (TCon ("Tree", [])));
  Alcotest.(check bool) "recursive Tree is float_free" true (ff (TCon ("Tree", [])));
  Alcotest.(check bool) "Float two levels down is found" false (ff (TCon ("Deep", [])));
  Alcotest.(check bool) "mutually recursive A/B terminates" true (cf (TCon ("A", [])));
  Alcotest.(check bool) "Option(Int) is closure_free" true (cf (TCon ("Option", [TInt])));
  Alcotest.(check bool) "Option(fn) is not closure_free" false (cf (TCon ("Option", [TFn ([], TInt)])));
  Alcotest.(check bool) "Vec3 is not float_free" false (ff (TCon ("Vec3", [])));
  Alcotest.(check bool) "closure struct is not closure_free" false
    (cf (TCon (Tir_names.clo_struct_prefix ^ "f_1", [])))

(* ── Determinism: the property Phase 3 exists to restore ─────────────── *)

let test_build_is_deterministic () =
  let open Tir in
  let t1 = table fixture_defs and t2 = table fixture_defs in
  List.iter (fun ty ->
      let a = Kind.of_ty t1 ty and b = Kind.of_ty t2 ty in
      Alcotest.(check bool) ("same kind for " ^ Tir.show_ty ty) true (a = b))
    [ TInt; TFloat; TCon ("Option", [TInt]); TCon ("Vec3", []); TCon ("Tree", []);
      TTuple [TInt; TString]; TRecord [("x", TFloat)]; TFn ([TInt], TInt) ]

let test_tables_do_not_leak_between_modules () =
  let open Tir in
  let m1 = table [ TDVariant ("Vec3", [ ("Vec3", [TFloat; TFloat; TFloat]) ]) ] in
  let m2 = table [ TDVariant ("Other", [ ("Other", [TInt; TInt]) ]) ] in
  Alcotest.(check bool) "m1 unboxes Vec3" true (Kind.unboxed_of_type_name m1 "Vec3" <> None);
  Alcotest.(check bool) "m2 does not see Vec3" false (Kind.unboxed_of_type_name m2 "Vec3" <> None);
  Alcotest.(check bool) "m1 does not see Other" false (Kind.unboxed_of_type_name m1 "Other" <> None);
  (* An unboxing:false table built in between does not latch anything. *)
  let _repl = table ~unboxing:false [ TDVariant ("Vec3", [ ("Vec3", [TFloat; TFloat; TFloat]) ]) ] in
  let m3 = table [ TDVariant ("Vec3", [ ("Vec3", [TFloat; TFloat; TFloat]) ]) ] in
  Alcotest.(check bool) "a later table still unboxes after a REPL-style one" true
    (Kind.unboxed_of_type_name m3 "Vec3" <> None)

let test_rebind_keeps_decision () =
  let open Tir in
  let t0 = table [ TDVariant ("Vec3", [ ("Vec3", [TFloat; TFloat; TFloat]) ]) ] in
  (* a type added after the decision stays Boxed; Vec3's decision survives *)
  let later = TDVariant ("Late", [ ("Late", [TInt; TInt]) ]) in
  let t1 = Kind.rebind t0 (later :: Kind.type_defs t0) in
  Alcotest.(check bool) "Vec3 still unboxed after rebind" true
    (Kind.unboxed_of_type_name t1 "Vec3" <> None);
  Alcotest.(check bool) "Late (added after the decision) is not unboxed" false
    (Kind.unboxed_of_type_name t1 "Late" <> None);
  Alcotest.(check bool) "but Late's shape IS visible to find_variant" true
    (Kind.find_variant t1 "Late" <> None)

let suites = [
  ( "kind", [
      Alcotest.test_case "needs_rc/borrowable truth table"        `Quick test_truth_table;
      Alcotest.test_case "divergence set is exactly {TFn, bare TVar, TTuple, TRecord}" `Quick test_divergence_set_exact;
      Alcotest.test_case "repr classification"                    `Quick test_repr_classification;
      Alcotest.test_case "colliding short names are forced Boxed" `Quick test_forced_boxed_by_collision;
      Alcotest.test_case "extern-crossing type stays Boxed"       `Quick test_extern_crossing_stays_boxed;
      Alcotest.test_case "unboxing:false classifies Boxed"        `Quick test_unboxing_off;
      Alcotest.test_case "unboxed eligible class"                 `Quick test_unboxed_eligible_class;
      Alcotest.test_case "llvm_ty spelling"                       `Quick test_llvm_ty_spelling;
      Alcotest.test_case "deep crossing facts"                    `Quick test_crossing_facts;
      Alcotest.test_case "build is deterministic"                 `Quick test_build_is_deterministic;
      Alcotest.test_case "tables do not leak between modules"     `Quick test_tables_do_not_leak_between_modules;
      Alcotest.test_case "rebind keeps the unboxed decision"      `Quick test_rebind_keeps_decision;
    ] );
]
