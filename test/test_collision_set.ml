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

(* ── Finding 1 (final review): DActor arm of collect_type_names ──────────────
   [Lower.collect_type_names] is the PRE-Pass-1 AST walker that must produce the
   same set of type NAMES Pass 2 eventually puts into [tm_types], so the EARLY
   collision set (driving impl-symbol qualification) agrees with the LATE
   [Collision_set.compute tm_types] (driving global tags / forced Boxed).  Pass
   2 emits actor-generated types (<Name>_Msg/_Actor/_State) BARE — un-prefixed
   by the enclosing module.  Before the fix, [collect_type_names] walked
   DType/DMod but NOT DActor, so it missed those bare names: an actor
   type-name colliding with a user type in another module (bare [Widget_Msg]
   from [actor Widget] vs qualified [B.Widget_Msg]) was seen by the late set
   but NOT the early set — the exact silent-miscompile divergence the plan
   exists to eliminate, reached via an actor trigger. *)
let test_collect_type_names_includes_actor_types () =
  let m = Test_helpers.parse_and_desugar {|
    mod Test do
      mod A do
        actor Widget do
          state { n : Int }
          init { n: 0 }
          on Ping() do
            state
          end
        end
      end
      mod B do
        type Widget_Msg = Custom(Int)
      end
    end
  |} in
  let names =
    March_tir.Lower.collect_type_names ~prefix:"" [] m.March_ast.Ast.mod_decls
    |> List.map Collision_set.type_def_name
  in
  (* The actor's three BARE generated type names are present, un-prefixed by
     the enclosing "A." module. *)
  List.iter (fun expected ->
      Alcotest.(check bool) (Printf.sprintf "%s in collected names" expected) true
        (List.mem expected names))
    ["Widget_Msg"; "Widget_Actor"; "Widget_State"];
  (* And the qualified user type in module B is present. *)
  Alcotest.(check bool) "B.Widget_Msg in collected names" true
    (List.mem "B.Widget_Msg" names);
  (* So the bare actor type + the qualified user type collide on short name
     Widget_Msg — the parity the fix restores between the early and late sets. *)
  let cs =
    Collision_set.compute
      (March_tir.Lower.collect_type_names ~prefix:"" [] m.March_ast.Ast.mod_decls)
  in
  Alcotest.(check bool) "actor Widget_Msg collides with user B.Widget_Msg" true
    (Collision_set.is_colliding cs "Widget_Msg");
  (* A non-colliding actor-only name is still absent from the collision set. *)
  Alcotest.(check bool) "Widget_Actor (single declarer) not colliding" false
    (Collision_set.is_colliding cs "Widget_Actor")

let suites = [
  ( "collision_set", [
      Alcotest.test_case "no collision"                `Quick test_no_collision;
      Alcotest.test_case "two-module collision"         `Quick test_two_module_collision;
      Alcotest.test_case "bare toplevel not colliding"  `Quick test_bare_toplevel_type_not_colliding;
      Alcotest.test_case "collect_type_names includes actor types" `Quick
        test_collect_type_names_includes_actor_types;
    ] );
]
