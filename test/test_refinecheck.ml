(* Integration tests for the A1b refinement-check pass (lib/refinecheck).
   Parses small programs and asserts which calls are rejected.  Gated on z3:
   without a solver the pass returns Unverified (no error), so these skip. *)

let parse src =
  let lexbuf = Lexing.from_string src in
  March_parser.Parser.module_
    (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf

let z3_available () =
  match March_refine.Solver.create () with
  | None -> false
  | Some s -> March_refine.Solver.close s; true

(* True iff the refinement pass reports at least one error on [src]. *)
let has_refine_error src =
  let ctx = March_errors.Errors.create () in
  March_refinecheck.Refine_check.check_module ctx (parse src);
  March_errors.Errors.has_errors ctx

let gated name f =
  Alcotest.test_case name `Quick (fun () ->
      if z3_available () then f ()
      else Printf.printf "\n[skip] %s: no z3 on PATH\n" name)

let decl n =
  Printf.sprintf
    "mod M do\n\
    \  fn take_n(n : {Int | _ >= 0}) : Int do n end\n\
    \  fn nonzero(d : {Int | _ != 0}) : Int do d end\n\
     %s\n\
     end\n"
    n

let suite =
  [ gated "violating literal `take_n(-3)` is rejected" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error (decl "  fn main() : Int do take_n(-3) end")));

    gated "violating literal `nonzero(0)` is rejected" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error (decl "  fn main() : Int do nonzero(0) end")));

    gated "valid literals pass" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error (decl "  fn main() : Int do take_n(5) + nonzero(3) end")));

    gated "unconstrained variable is conservatively skipped" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error (decl "  fn f(k : Int) : Int do take_n(k) end")));

    gated "refined-local propagation passes" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (decl "  fn fwd(m : {Int | _ >= 0}) : Int do take_n(m) end"))) ]

(* A2: the `len` measure + cross-argument bounds.  `at` indexes a list with a
   bounds-refined index; we check calls against list literals (statically sized). *)
let bounds prog =
  Printf.sprintf
    "mod M do\n\
    \  fn at(xs : List(Int), i : {Int | _ >= 0 && _ < len(xs)}) : Int do i end\n\
     %s\n\
     end\n"
    prog

let a2_suite =
  [ gated "out-of-bounds index on a literal list is rejected" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error (bounds "  fn main() : Int do at([10, 20, 30], 5) end")));

    gated "in-bounds index passes" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error (bounds "  fn main() : Int do at([10, 20, 30], 1) end")));

    gated "boundary index 0 passes" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error (bounds "  fn main() : Int do at([10, 20, 30], 0) end")));

    gated "index == length is rejected (off-by-one)" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error (bounds "  fn main() : Int do at([10, 20, 30], 3) end")));

    gated "negative index is rejected" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error (bounds "  fn main() : Int do at([10, 20, 30], -1) end")));

    gated "unknown-length list arg is conservatively skipped" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (bounds "  fn f(ys : List(Int)) : Int do at(ys, 5) end"))) ]

let () =
  Alcotest.run "march-refinecheck"
    [ ("refinecheck", suite); ("bounds-a2", a2_suite) ]
