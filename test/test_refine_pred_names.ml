(* Predicate names: how a name inside a refinement predicate is printed,
   resolved and warned about (specs/plans/2026-11-06-predicate-names-plan.md).

   Group `pred-names`.  Cases that run the compiler use [Test_refine_unfold]'s
   helpers. *)

module A = March_ast.Ast
module RS = March_refinecheck.Refine_scope
module IV = March_refinecheck.Infer_vocab
module PI = March_refinecheck.Precond_infer
module U = Test_refine_unfold

let test name f = Alcotest.test_case name `Quick f
let gated = U.gated

(* The predicate of a return refinement `{base | src}`, as the parser builds
   it (undesugared, as `pred_str` meets it in a signature). *)
let pred_on ~base src =
  let m =
    Printf.sprintf
      "mod P do\n  fn f(a : Int, b : Int, c : Int, low : Int, high : Int, m : Map(Int, Int)) : {%s | %s} do 0 end\nend\n"
      base src
  in
  match (March_parser.Parse.module_of_lexbuf (Lexing.from_string m)).A.mod_decls with
  | [ A.DFn ({ A.fn_ret_ty = Some (A.TyRefine (_, _, p)); _ }, _) ] -> p
  | _ -> Alcotest.failf "no refinement parsed from %s" src

let pred_of = pred_on ~base:"Int"
let pred_of_bool = pred_on ~base:"Bool"

(* #18: `pred_str` keeps the parentheses a reparse needs. *)
let parens =
  let rows =
    [ ("_ <= a && _ <= b && (_ == a || _ == b)", "_ <= a && _ <= b && (_ == a || _ == b)");
      ("high < low || (_ >= low && _ <= high)", "high < low || _ >= low && _ <= high");
      ("_ == (a + b) * 2", "_ == (a + b) * 2");
      ("_ == a - (b - c)", "_ == a - (b - c)");
      ("_ == a - b - c", "_ == a - b - c");
      ("_ == a * (b / c)", "_ == a * (b / c)");
      ("!(_ > 0 && _ < 9)", "!(_ > 0 && _ < 9)");
      ("_ == -(a + b)", "_ == -(a + b)") ]
  in
  let bool_rows = [ "(_ || a > 0) && b > 0"; "_ == (a == b)"; "_ == (keys(m) == empty)" ] in
  [ test "pred_str prints the parentheses a reparse needs" (fun () ->
        List.iter (fun (src, want) -> Alcotest.(check string) src want (RS.pred_str (pred_of src))) rows);
    test "a Boolean equality of a comparison keeps its parentheses (Map.is_empty)" (fun () ->
        Alcotest.(check string) "is_empty" "_ == (keys(m) == empty)"
          (RS.pred_str (pred_of_bool "_ == (keys(m) == empty)")));
    test "every printed predicate re-parses to the same text" (fun () ->
        let again base s = RS.pred_str (pred_on ~base (RS.pred_str (pred_on ~base s))) in
        List.iter
          (fun s -> Alcotest.(check string) s (RS.pred_str (pred_of s)) (again "Int" s))
          (List.map fst rows @ [ "_ == a - b + c"; "_ == a - (b + c)" ]);
        List.iter (fun s -> Alcotest.(check string) s (RS.pred_str (pred_of_bool s)) (again "Bool" s)) bool_rows;
        List.iter (fun s -> Alcotest.(check string) ("kept: " ^ s) s (RS.pred_str (pred_of_bool s))) bool_rows);
    test "an inference candidate read back from the text keeps its grouping" (fun () ->
        match IV.candidate_of_text (RS.pred_str (pred_of "_ == (a + b) * 2")) with
        | Some c -> Alcotest.(check string) "round trip" "_ == (a + b) * 2" c.PI.c_text
        | None -> Alcotest.fail "not a candidate");
    gated "min_int's report row prints its disjunction in parentheses" (fun () ->
        let dir = Filename.concat (Filename.dirname Sys.executable_name) ".." in
        let out = U.run_in ~dir "--check --stdlib-source --refine-report-sites=all" "stdlib/math.march" in
        let rows = List.filter (fun l -> U.contains l "\tmin_int\t") (U.lines out) in
        if rows = [] then Alcotest.failf "no min_int row:\n%s" out;
        List.iter
          (fun l ->
            if not (U.contains l "_ <= a && _ <= b && (_ == a || _ == b)") then
              Alcotest.failf "min_int row lost its parentheses: %s" l)
          rows) ]

let suite : unit Alcotest.test_case list = parens
