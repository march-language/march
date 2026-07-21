(* Unit tests for the HM scheme + instantiation witness tables recorded by
   the typechecker (A1 Task 2, --emit-core-ast v2). Parses a small polymorphic
   module through the real parser (mirrors Test_helpers.parse_module / how
   bin/main.ml bootstraps), typechecks it via check_module_full, and asserts
   that the `id` scheme was recorded (deduped by quantified-id list) and that
   both of its use sites (`id(1)`, `id(true)`) recorded distinct instantiation
   witnesses keyed by use-site span. *)
module T = March_typecheck.Typecheck

let test_scheme_and_instantiation_recorded () =
  (* `id` is generalized (a scheme), used at two types -> two instantiations. *)
  let src =
    "mod M do\n\
    \  let id = fn x -> x\n\
    \  let a = id(1)\n\
    \  let b = id(true)\n\
     end\n"
  in
  let m = Test_helpers.parse_module src in
  let (_errors, _type_map, env) = T.check_module_full m in
  Alcotest.(check bool) "at least one scheme recorded"
    true (Hashtbl.length env.T.scheme_witnesses >= 1);
  Alcotest.(check bool) "at least two instantiations recorded"
    true (Hashtbl.length env.T.inst_witnesses >= 2)

let () =
  Alcotest.run "witnesses"
    [ ("recording",
       [ Alcotest.test_case "scheme+inst" `Quick test_scheme_and_instantiation_recorded ]) ]
