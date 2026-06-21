open March_refine

let smoke_suite =
  [ Alcotest.test_case "library links" `Quick (fun () ->
        Alcotest.(check string) "version" "a0" Smt.version) ]

(* A VC asserting: (d > 0) ==> (d != 0).  We check validity by asserting the
   hypotheses and the NEGATED goal, then check-sat; unsat means valid. *)
let sample_vc : Smt.vc =
  { decls = [ ("d", Smt.SInt) ];
    assumptions = [ Smt.Gt (Smt.Const "d", Smt.IntLit 0) ];
    goal = Smt.Ne (Smt.Const "d", Smt.IntLit 0) }

let smt_suite =
  [ Alcotest.test_case "renders a term" `Quick (fun () ->
        Alcotest.(check string) "ge"
          "(>= _ 0)"
          (Smt.render (Smt.Ge (Smt.Const "_", Smt.IntLit 0))));

    Alcotest.test_case "renders negative int literal" `Quick (fun () ->
        Alcotest.(check string) "neg" "(- 3)" (Smt.render (Smt.IntLit (-3))));

    Alcotest.test_case "assertion_block negates the goal" `Quick (fun () ->
        Alcotest.(check string) "block"
          "(declare-const d Int)\n\
           (assert (> d 0))\n\
           (assert (not (not (= d 0))))\n"
          (Smt.assertion_block sample_vc)) ]

let () =
  Alcotest.run "march-refine"
    [ ("smoke", smoke_suite); ("smt", smt_suite) ]
