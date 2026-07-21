(* Unit tests for Ast_json.resolved_ty_to_json — the internal-ty -> JSON
   encoder used by --emit-core-ast v2. Constructs Typecheck.ty values
   directly and asserts the JSON shape (contract with the march-lean checker). *)
module T = March_typecheck.Typecheck
module J = March_dump.Ast_json

let check name expected actual =
  Alcotest.(check string) name expected actual

let astring_contains hay needle =
  let hl = String.length hay and nl = String.length needle in
  let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
  nl = 0 || go 0

let test_tcon () =
  check "Int" {|{"kind":"TCon","name":"Int","args":[]}|}
    (J.resolved_ty_to_json (T.TCon ("Int", [])))

let test_tcon_args () =
  check "List(Int)"
    {|{"kind":"TCon","name":"List","args":[{"kind":"TCon","name":"Int","args":[]}]}|}
    (J.resolved_ty_to_json (T.TCon ("List", [ T.TCon ("Int", []) ])))

let test_tarrow () =
  check "Int -> Int"
    {|{"kind":"TArrow","from":{"kind":"TCon","name":"Int","args":[]},"to":{"kind":"TCon","name":"Int","args":[]}}|}
    (J.resolved_ty_to_json (T.TArrow (T.TCon ("Int", []), T.TCon ("Int", []))))

let test_tvar_unbound () =
  (* A raw unbound metavariable serializes to its id. *)
  check "tvar 7"
    {|{"kind":"TVar","id":7}|}
    (J.resolved_ty_to_json (T.TVar (ref (T.Unbound (7, 0)))))

let test_tvar_link_deep_repr () =
  (* A Link must be followed by deep-repr, not emitted as a var. *)
  let inner = T.TCon ("Bool", []) in
  check "linked -> Bool"
    {|{"kind":"TCon","name":"Bool","args":[]}|}
    (J.resolved_ty_to_json (T.TVar (ref (T.Link inner))))

let test_trecord_order_preserved () =
  check "record keeps stored order"
    {|{"kind":"TRecord","fields":[{"name":"b","ty":{"kind":"TCon","name":"Int","args":[]}},{"name":"a","ty":{"kind":"TCon","name":"Int","args":[]}}]}|}
    (J.resolved_ty_to_json
       (T.TRecord [ ("b", T.TCon ("Int", [])); ("a", T.TCon ("Int", [])) ]))

let test_tchan_unsupported () =
  check "session -> unsupported"
    {|{"kind":"unsupported","what":"session"}|}
    (J.resolved_ty_to_json (T.TChan (ref T.SEnd)))

let test_constraint_cnum () =
  check "CNum a"
    {|{"kind":"CNum","ty":{"kind":"TVar","id":3}}|}
    (J.constraint_to_json (T.CNum (T.TVar (ref (T.Unbound (3, 0))))))

(* Module_to_json ~types: end-to-end smoke test that the real pipeline
   (parse -> desugar -> check_module_full -> module_to_json on the SAME
   desugared tree, mirroring bin/main.ml's --emit-core-ast branch) produces
   a "resolved_ty" key on emitted expr nodes. Not a golden byte-for-byte
   check (that's Task 5) — just proves the plumbing is wired end to end. *)
let test_module_emits_resolved_ty () =
  let m = Test_helpers.parse_module "mod M do\nlet a = 1\nend\n" in
  let desugared = March_desugar.Desugar.desugar_module m in
  let (_errors, type_map, _env) =
    March_typecheck.Typecheck.check_module_full desugared
  in
  let json = J.module_to_json ~types:type_map desugared in
  Alcotest.(check bool) "module JSON mentions resolved_ty"
    true (astring_contains json "resolved_ty")

let () =
  Alcotest.run "ty_json"
    [ ("encoder",
       [ Alcotest.test_case "tcon" `Quick test_tcon;
         Alcotest.test_case "tcon_args" `Quick test_tcon_args;
         Alcotest.test_case "tarrow" `Quick test_tarrow;
         Alcotest.test_case "tvar_unbound" `Quick test_tvar_unbound;
         Alcotest.test_case "tvar_link_deep_repr" `Quick test_tvar_link_deep_repr;
         Alcotest.test_case "trecord_order" `Quick test_trecord_order_preserved;
         Alcotest.test_case "tchan_unsupported" `Quick test_tchan_unsupported;
         Alcotest.test_case "constraint_cnum" `Quick test_constraint_cnum;
         Alcotest.test_case "module_emits_resolved_ty" `Quick test_module_emits_resolved_ty ]) ]
