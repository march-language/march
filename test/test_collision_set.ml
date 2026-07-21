(** Collision-set computation test suite.

    Collision_set.compute (lib/tir/collision_set.ml) is the shared input to
    Stage 3's three consumers (global ctor tags, forced-Boxed repr,
    dispatch-function codegen / mono routing) — see
    specs/plans/2026-07-20-fqn-impl-dispatch-identity.md. *)

open March_tir

let mk_variant name ctors = Tir.TDVariant (name, ctors)

let test_no_collision () =
  let defs = [ mk_variant "NA.Thing" [("TA", [])]; mk_variant "Other.Foo" [("F", [])] ] in
  let cs = Collision_set.compute defs in
  Alcotest.(check bool) "Thing not colliding" false (Collision_set.is_colliding cs "Thing");
  Alcotest.(check bool) "Thing not colliding (qualified)" false
    (Collision_set.is_colliding cs "NA.Thing")

let test_two_module_collision () =
  let defs = [ mk_variant "NA.Thing" [("TA", [])]; mk_variant "NB.Thing" [("TB", [])] ] in
  let cs = Collision_set.compute defs in
  Alcotest.(check bool) "Thing colliding" true (Collision_set.is_colliding cs "Thing");
  Alcotest.(check bool) "NA.Thing colliding via short name" true
    (Collision_set.is_colliding cs "NA.Thing");
  (match Hashtbl.find_opt cs "Thing" with
   | Some names -> Alcotest.(check (list string)) "both declarers"
       ["NA.Thing"; "NB.Thing"] (List.sort compare names)
   | None -> Alcotest.fail "expected Thing in collision set")

let test_bare_toplevel_type_not_colliding () =
  (* Entry-module types are bare (no prefix) — a bare "Thing" appearing once
     alongside an unrelated qualified "NA.Thing" is NOT the same short name
     colliding with itself; this only matters once two declarations produce
     the same short name, which a single bare entry never does alone. *)
  let defs = [ mk_variant "Thing" [("T", [])] ] in
  let cs = Collision_set.compute defs in
  Alcotest.(check bool) "single bare Thing not colliding" false
    (Collision_set.is_colliding cs "Thing")

let suites = [
  ( "collision_set", [
      Alcotest.test_case "no collision"                `Quick test_no_collision;
      Alcotest.test_case "two-module collision"         `Quick test_two_module_collision;
      Alcotest.test_case "bare toplevel not colliding"  `Quick test_bare_toplevel_type_not_colliding;
    ] );
]
