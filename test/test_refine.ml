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

let model_suite =
  [ Alcotest.test_case "parses define-fun ints" `Quick (fun () ->
        let s =
          "(\n\
          \  (define-fun d () Int 0)\n\
          \  (define-fun i () Int 10)\n\
           )"
        in
        let m = Model.of_string s in
        Alcotest.(check (option string)) "d" (Some "0") (List.assoc_opt "d" m);
        Alcotest.(check (option string)) "i" (Some "10") (List.assoc_opt "i" m));

    Alcotest.test_case "parses negative and bool values" `Quick (fun () ->
        let s =
          "(model\n\
          \  (define-fun n () Int (- 3))\n\
          \  (define-fun b () Bool true)\n\
           )"
        in
        let m = Model.of_string s in
        Alcotest.(check (option string)) "n" (Some "(- 3)") (List.assoc_opt "n" m);
        Alcotest.(check (option string)) "b" (Some "true") (List.assoc_opt "b" m)) ]

(* Solver tests require a real z3 on PATH.  When absent (e.g. CI), they print a
   skip notice and pass — matching the spec's graceful-degradation design. *)
let with_solver name f =
  Alcotest.test_case name `Quick (fun () ->
      match Solver.create () with
      | None -> Printf.printf "\n[skip] %s: no z3 on PATH\n" name
      | Some s -> Fun.protect ~finally:(fun () -> Solver.close s) (fun () -> f s))

let solver_suite =
  [ with_solver "valid VC is unsat (verified)" (fun s ->
        let vc : Smt.vc =
          { decls = [ ("d", Smt.SInt) ];
            assumptions = [ Smt.Gt (Smt.Const "d", Smt.IntLit 0) ];
            goal = Smt.Ne (Smt.Const "d", Smt.IntLit 0) }
        in
        match Solver.check s vc with
        | Solver.Unsat -> ()
        | Solver.Sat _ -> Alcotest.fail "expected unsat, got sat"
        | Solver.Unknown -> Alcotest.fail "expected unsat, got unknown");

    with_solver "invalid VC is sat with d=0 counterexample" (fun s ->
        let vc : Smt.vc =
          { decls = [ ("d", Smt.SInt) ];
            assumptions = [];
            goal = Smt.Ne (Smt.Const "d", Smt.IntLit 0) }
        in
        match Solver.check s vc with
        | Solver.Sat model ->
            Alcotest.(check (option string)) "d=0" (Some "0")
              (List.assoc_opt "d" model)
        | Solver.Unsat -> Alcotest.fail "expected sat, got unsat"
        | Solver.Unknown -> Alcotest.fail "expected sat, got unknown");

    with_solver "two checks on one process are independent" (fun s ->
        let valid : Smt.vc =
          { decls = [ ("x", Smt.SInt) ];
            assumptions = [ Smt.Ge (Smt.Const "x", Smt.IntLit 1) ];
            goal = Smt.Gt (Smt.Const "x", Smt.IntLit 0) }
        in
        let invalid : Smt.vc =
          { decls = [ ("x", Smt.SInt) ]; assumptions = []; goal =
            Smt.Gt (Smt.Const "x", Smt.IntLit 0) }
        in
        (match Solver.check s valid with
         | Solver.Unsat -> ()
         | _ -> Alcotest.fail "valid VC should be unsat");
        (match Solver.check s invalid with
         | Solver.Sat _ -> ()
         | _ -> Alcotest.fail "invalid VC should be sat (push/pop leaked?)")) ]

let cache_suite =
  (* Unique temp root per process to avoid concurrent-session collisions. *)
  let root =
    Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "march_refine_cache_%d" (Unix.getpid ()))
  in
  let vc : Smt.vc =
    { decls = [ ("d", Smt.SInt) ]; assumptions = []; goal =
      Smt.Ne (Smt.Const "d", Smt.IntLit 0) }
  in
  [ Alcotest.test_case "key is stable for equal VCs" `Quick (fun () ->
        Alcotest.(check string) "key" (Vc_cache.key_of_vc vc)
          (Vc_cache.key_of_vc vc));

    Alcotest.test_case "miss then store then hit (unsat)" `Quick (fun () ->
        let key = Vc_cache.key_of_vc vc in
        Alcotest.(check bool) "initial miss" true
          (Vc_cache.lookup ~root key = None);
        Vc_cache.store ~root key Solver.Unsat;
        Alcotest.(check bool) "hit unsat" true
          (Vc_cache.lookup ~root key = Some Solver.Unsat));

    Alcotest.test_case "round-trips a sat model" `Quick (fun () ->
        let key = "ff" ^ String.make 62 'a' in
        let r = Solver.Sat [ ("d", "0"); ("i", "10") ] in
        Vc_cache.store ~root key r;
        Alcotest.(check bool) "hit sat" true
          (Vc_cache.lookup ~root key = Some r)) ]

let () =
  Alcotest.run "march-refine"
    [ ("smoke", smoke_suite);
      ("smt", smt_suite);
      ("model", model_suite);
      ("solver", solver_suite);
      ("cache", cache_suite) ]
