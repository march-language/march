(** Globally-unique constructor tags for same-short-name colliding types.

    Task 1 of the FQN impl-dispatch-identity plan: a colliding type's
    constructors (per [Collision_set.is_colliding], computed by Task 0) must
    get a globally-unique [ce_tag] from a dedicated counter, distinct from
    both the per-type 0-based scheme non-colliding types keep AND the
    actor-message global-tag counter (0x0100_0000+) — so a later runtime tag
    switch (Task 4/5) can tell same-short-name types apart by tag alone. See
    specs/plans/2026-07-20-fqn-impl-dispatch-identity.md. *)

open March_tir

let mk_variant name ctors = Tir.TDVariant (name, ctors)

let test_colliding_types_get_global_tags () =
  let defs = [
    mk_variant "NA.Thing" [("TA", [])];
    mk_variant "NB.Thing" [("TB", [])];
    mk_variant "Solo.Other" [("O", [])];   (* non-colliding control *)
  ] in
  let m : Tir.tir_module =
    { tm_name = "test"; tm_types = defs; tm_fns = []; tm_externs = [];
      tm_exports = []; tm_tests = []; tm_io_fns = [] }
  in
  let ctx = Llvm_ctx.make_ctx ~type_defs:defs () in
  Llvm_toplevel.build_ctor_info ctx m;
  let tag_of key = (Hashtbl.find ctx.Llvm_ctx.ctor_info key).Llvm_ctx.ce_tag in
  Alcotest.(check bool) "NA.Thing.TA tag is global-range" true
    (tag_of "NA.Thing.TA" >= 0x0200_0000);
  Alcotest.(check bool) "NB.Thing.TB tag is global-range" true
    (tag_of "NB.Thing.TB" >= 0x0200_0000);
  Alcotest.(check bool) "NA/NB tags distinct" true
    (tag_of "NA.Thing.TA" <> tag_of "NB.Thing.TB");
  Alcotest.(check int) "non-colliding type keeps per-type tag 0" 0
    (tag_of "Solo.Other.O")

let test_noncolliding_program_byte_identical_tags () =
  (* A program with zero collisions must keep the exact pre-Task-1 per-type
     0-based tag assignment — collision-conditional, always. *)
  let defs = [
    mk_variant "List" [("Nil", []); ("Cons", [Tir.TVar "a"; Tir.TCon ("List", [Tir.TVar "a"])])];
    mk_variant "Other.Foo" [("F", [])];
  ] in
  let m : Tir.tir_module =
    { tm_name = "test"; tm_types = defs; tm_fns = []; tm_externs = [];
      tm_exports = []; tm_tests = []; tm_io_fns = [] }
  in
  let ctx = Llvm_ctx.make_ctx ~type_defs:defs () in
  Llvm_toplevel.build_ctor_info ctx m;
  let tag_of key = (Hashtbl.find ctx.Llvm_ctx.ctor_info key).Llvm_ctx.ce_tag in
  Alcotest.(check int) "List.Nil keeps tag 0" 0 (tag_of "List.Nil");
  Alcotest.(check int) "List.Cons keeps tag 1" 1 (tag_of "List.Cons");
  Alcotest.(check int) "Other.Foo.F keeps tag 0" 0 (tag_of "Other.Foo.F")

let suites = [
  ( "ctor_tags", [
      Alcotest.test_case "colliding types get distinct global tags" `Quick
        test_colliding_types_get_global_tags;
      Alcotest.test_case "non-colliding program keeps per-type tags" `Quick
        test_noncolliding_program_byte_identical_tags;
    ] );
]
