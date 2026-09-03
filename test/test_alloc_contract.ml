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
