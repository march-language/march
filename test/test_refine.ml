open March_refine

(* Orphan-probe mode (see lifecycle_suite): when re-exec'd with this env var,
   spawn a solver, report the z3 pid, and exit WITHOUT closing it — simulating
   a parent that dies with no cleanup.  Must run before Alcotest.run. *)
let () =
  if Sys.getenv_opt "MARCH_Z3_ORPHAN_PROBE" = Some "1" then begin
    (match Solver.create () with
     | None -> print_string "none\n"
     | Some t -> Printf.printf "%d\n" t.Solver.pid);
    exit 0
  end

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

(* A VC whose preamble z3 rejects (unknown sort), used to prove that ONE bad VC
   does not take the shared solver channel down with it.  Before the fix, z3's
   `(error …)` line was read in place of the verdict, Solver.check raised, and
   Refine killed + respawned the solver twice before marking z3 unavailable for
   the WHOLE REST OF THE RUN — every later VC silently unchecked. *)
let bad_preamble = "(declare-const bogus NoSuchSort)"

let resync_suite =
  [ with_solver "a z3 error yields Unknown, not a wrong verdict" (fun s ->
        (* The verdict after an error is computed against an incomplete state,
           so it must never be trusted: under definite-failure a bogus `sat`
           would be reported as a violation — a false positive. *)
        match Solver.check ~preamble:bad_preamble s sample_vc with
        | Solver.Unknown -> ()
        | Solver.Unsat -> Alcotest.fail "expected unknown, got unsat"
        | Solver.Sat _ -> Alcotest.fail "expected unknown, got sat");

    with_solver "the channel resyncs: a later VC still checks correctly" (fun s ->
        ignore (Solver.check ~preamble:bad_preamble s sample_vc);
        (* Same solver, next VC.  If the channel were desynchronized this reads
           a stale line; if the solver were dead this raises. *)
        match Solver.check s sample_vc with
        | Solver.Unsat -> ()
        | Solver.Sat _ -> Alcotest.fail "desynced: expected unsat, got sat"
        | Solver.Unknown -> Alcotest.fail "desynced: expected unsat, got unknown");

    with_solver "a bad VC does not disable checking for later ones (Refine)" (fun s ->
        ignore s;
        (* Drive the full Refine path, which is where the shutdown happened. *)
        let root = Filename.get_temp_dir_name () in
        (match Refine.discharge ~root ~preamble:bad_preamble sample_vc with
         | Refine.Unverified -> ()
         | Refine.Verified -> Alcotest.fail "expected unverified, got verified"
         | Refine.Refuted _ -> Alcotest.fail "expected unverified, got refuted");
        let later = Refine.discharge ~root sample_vc in
        (* Reap the shared solver this test spawned, so the lifecycle suite's
           child count isn't polluted by it. *)
        Refine.shutdown ();
        match later with
        | Refine.Verified -> ()
        | _ -> Alcotest.fail "later VC was silently left unchecked") ]

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

let refine_suite =
  let root =
    Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "march_refine_disc_%d" (Unix.getpid ()))
  in
  [ Alcotest.test_case "cached unsat returns Verified without a solver" `Quick
      (fun () ->
        (* Pre-seed the cache so discharge never needs z3 — keeps this case
           green in CI.  A subsequent lookup must report Verified. *)
        let vc : Smt.vc =
          { decls = [ ("d", Smt.SInt) ];
            assumptions = [ Smt.Gt (Smt.Const "d", Smt.IntLit 0) ];
            goal = Smt.Ne (Smt.Const "d", Smt.IntLit 0) }
        in
        Vc_cache.store ~root (Vc_cache.key_of_vc vc) Solver.Unsat;
        match Refine.discharge ~root vc with
        | Refine.Verified -> ()
        | Refine.Refuted _ -> Alcotest.fail "expected Verified, got Refuted"
        | Refine.Unverified -> Alcotest.fail "expected Verified, got Unverified");

    Alcotest.test_case "cached sat returns Refuted with model" `Quick (fun () ->
        let vc : Smt.vc =
          { decls = [ ("d", Smt.SInt) ]; assumptions = []; goal =
            Smt.Ne (Smt.Const "d", Smt.IntLit 0) }
        in
        Vc_cache.store ~root (Vc_cache.key_of_vc vc)
          (Solver.Sat [ ("d", "0") ]);
        match Refine.discharge ~root vc with
        | Refine.Refuted model ->
            Alcotest.(check (option string)) "d=0" (Some "0")
              (List.assoc_opt "d" model)
        | _ -> Alcotest.fail "expected Refuted") ]

(* ── Solver-process lifecycle (regression: 2026-07 z3 orphan leak) ────────
   Every compile/check run used to leave one immortal z3: the shared solver
   was never closed, and the child inherited the write end of its own stdin
   pipe (no cloexec), so it never saw EOF after the parent died. *)

(* Pids of z3 processes whose parent is THIS test binary. *)
let z3_children () : int list =
  let ic =
    Unix.open_process_in
      (Printf.sprintf "pgrep -P %d -x z3" (Unix.getpid ()))
  in
  let rec loop acc =
    match input_line ic with
    | line -> loop (int_of_string (String.trim line) :: acc)
    | exception End_of_file -> acc
  in
  let pids = loop [] in
  ignore (Unix.close_process_in ic);
  pids

let mkdtemp prefix =
  let d = Filename.temp_file prefix "" in
  Sys.remove d;
  Unix.mkdir d 0o700;
  d

let lifecycle_suite =
  [ Alcotest.test_case "shared solver: 1 child while solving, 0 after shutdown"
      `Quick (fun () ->
        match Solver.create () with
        | None -> Printf.printf "\n[skip] solver lifecycle: no z3 on PATH\n"
        | Some probe ->
            Solver.close probe;
            let root = mkdtemp "march_refine_leak" in
            (* Distinct VCs (d > n ==> d != 0) so each one misses the disk
               cache and actually exercises the shared solver. *)
            List.iter
              (fun n ->
                let vc : Smt.vc =
                  { decls = [ ("d", Smt.SInt) ];
                    assumptions = [ Smt.Gt (Smt.Const "d", Smt.IntLit n) ];
                    goal = Smt.Ne (Smt.Const "d", Smt.IntLit 0) }
                in
                match Refine.discharge ~root vc with
                | Refine.Verified -> ()
                | _ -> Alcotest.fail "expected Verified")
              [ 1; 2; 3 ];
            Alcotest.(check int) "one z3 child while shared solver is live" 1
              (List.length (z3_children ()));
            Refine.shutdown ();
            Alcotest.(check int) "no z3 children after shutdown" 0
              (List.length (z3_children ())));

    Alcotest.test_case "z3 dies when parent exits without closing it" `Quick
      (fun () ->
        (* Re-exec this binary in orphan-probe mode: it spawns a solver,
           prints the z3 pid, and exits with NO cleanup.  With cloexec pipes
           the orphaned z3 must see EOF on stdin and exit promptly; before
           the fix it inherited its own stdin write end and lived forever. *)
        let out_r, out_w = Unix.pipe ~cloexec:true () in
        let self = Sys.executable_name in
        let env =
          Array.append (Unix.environment ()) [| "MARCH_Z3_ORPHAN_PROBE=1" |]
        in
        let child =
          Unix.create_process_env self [| self |] env Unix.stdin out_w
            Unix.stderr
        in
        Unix.close out_w;
        let ic = Unix.in_channel_of_descr out_r in
        let line = try input_line ic with End_of_file -> "none" in
        ignore (Unix.waitpid [] child);
        close_in ic;
        match int_of_string_opt (String.trim line) with
        | None -> Printf.printf "\n[skip] orphan probe: no z3 on PATH\n"
        | Some z3_pid ->
            let alive pid =
              try
                Unix.kill pid 0;
                true
              with Unix.Unix_error (Unix.ESRCH, _, _) -> false
            in
            let deadline = Unix.gettimeofday () +. 5.0 in
            let rec wait_dead () =
              if not (alive z3_pid) then true
              else if Unix.gettimeofday () > deadline then false
              else begin
                ignore (Unix.select [] [] [] 0.05);
                wait_dead ()
              end
            in
            let died = wait_dead () in
            if not died then (try Unix.kill z3_pid Sys.sigkill with _ -> ());
            Alcotest.(check bool) "orphaned z3 exits on parent death" true died)
  ]

let () =
  Alcotest.run "march-refine"
    [ ("smoke", smoke_suite);
      ("smt", smt_suite);
      ("model", model_suite);
      ("solver", solver_suite);
      ("solver-resync", resync_suite);
      ("cache", cache_suite);
      ("refine", refine_suite);
      ("lifecycle", lifecycle_suite) ]
