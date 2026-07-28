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
let has_refine_error ?root src =
  let ctx = March_errors.Errors.create () in
  March_refinecheck.Refine_check.check_module ?root ctx (parse src);
  March_errors.Errors.has_errors ctx

let with_temp_root prefix f =
  let root = Filename.temp_dir prefix "" in
  let rec remove_tree path =
    if Sys.is_directory path then begin
      Sys.readdir path
      |> Array.iter (fun name -> remove_tree (Filename.concat path name));
      Unix.rmdir path
    end
    else Sys.remove path
  in
  Fun.protect ~finally:(fun () -> remove_tree root) (fun () -> f root)

(* Same, but DESUGARED first — required for qualified calls (`M.f(x)`), which the
   parser produces as `EField` and desugar flattens to a single dotted `EVar`,
   exactly as the compiler feeds refine_check in production. *)
let has_refine_error_d src =
  let ctx = March_errors.Errors.create () in
  March_refinecheck.Refine_check.check_module ctx (March_desugar.Desugar.desugar_module (parse src));
  March_errors.Errors.has_errors ctx

(* Same as [has_refine_error_d], but parsed AS IF it came from [file] and
   checked with [stdlib_files] declared as the standard library's own sources.
   Both are needed to exercise the ENABLING branch of the `List.length` measure
   alias: the alias is allowed only when a `List.length` in scope came from a
   file the caller identified as stdlib, and no string-parsed fixture (whose
   span file is "") can ever reach that branch. *)
let has_refine_error_from ?(stdlib_files = []) ~file src =
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <- { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = file };
  let m =
    March_parser.Parser.module_
      (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
  in
  let ctx = March_errors.Errors.create () in
  March_refinecheck.Refine_check.check_module ~stdlib_files ctx
    (March_desugar.Desugar.desugar_module m);
  March_errors.Errors.has_errors ctx

(* Number of ERRORS the refinement pass reports on [src].  A plain boolean
   cannot tell "both violations found" from "one found, one silently lost",
   which is exactly the failure mode the co-occurrence guards below pin. *)
let refine_error_count src =
  let ctx = March_errors.Errors.create () in
  March_refinecheck.Refine_check.check_module ctx (parse src);
  List.length
    (List.filter
       (fun (d : March_errors.Errors.diagnostic) ->
         d.March_errors.Errors.severity = March_errors.Errors.Error)
       ctx.March_errors.Errors.diagnostics)

(* True iff the refinement pass reports at least one WARNING on [src].
   [has_refine_error] only sees Errors, so vocabulary diagnostics need this. *)
let has_refine_warning src =
  let ctx = March_errors.Errors.create () in
  March_refinecheck.Refine_check.check_module ctx (parse src);
  List.exists
    (fun (d : March_errors.Errors.diagnostic) ->
      d.March_errors.Errors.severity = March_errors.Errors.Warning)
    ctx.March_errors.Errors.diagnostics

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

(* Path sensitivity: a guard establishes facts that discharge a precondition. *)
let path_suite =
  [ gated "scalar guard `if i >= 0` lets take_n(i) verify" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (decl
                "  fn g(i : Int) : Int do if i >= 0 do take_n(i) else 0 end end")));

    gated "else-branch negates the guard (i < 0 else => i >= 0)" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (decl
                "  fn g(i : Int) : Int do if i < 0 do 0 else take_n(i) end end")));

    gated "full bounds guard lets at(xs, i) verify" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (bounds
                "  fn g(xs : List(Int), i : Int) : Int do\n\
                \    if i >= 0 && i < len(xs) do at(xs, i) else 0 end\n\
                \  end")));

    gated "partial guard (no upper bound) is conservatively skipped" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (bounds
                "  fn g(xs : List(Int), i : Int) : Int do\n\
                \    if i >= 0 do at(xs, i) else 0 end\n\
                \  end")));

    gated "guard contradicting the precondition is rejected" (fun () ->
        (* inside `i < 0`, calling take_n (needs `_ >= 0`) can never hold *)
        Alcotest.(check bool) "error" true
          (has_refine_error
             (decl
                "  fn g(i : Int) : Int do if i < 0 do take_n(i) else 0 end end")));

    gated "a `let` rebinding the guarded name retires the guard fact" (fun () ->
        (* `i` inside the branch is a fresh 5, not the guarded outer `i`; the
           call is correct code and must not be flagged. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (decl
                "  fn g(i : Int) : Int do\n\
                \    if i < 0 do\n\
                \      let i = 5\n\
                \      take_n(i)\n\
                \    else 0 end\n\
                \  end")))
  ]

(* Postconditions: a function's return value must satisfy its return refinement. *)
let post src = Printf.sprintf "mod M do\n%s\nend\n" src

let post_suite =
  [ gated "returning a violating literal is rejected" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (post "  fn f() : {Int | _ >= 0} do -1 end")));

    gated "returning a valid literal passes" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error (post "  fn f() : {Int | _ >= 0} do 5 end")));

    gated "`_ > 0` return of 0 is rejected" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error (post "  fn f() : {Int | _ > 0} do 0 end")));

    gated "returning a refined param satisfies the postcondition" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (post "  fn f(n : {Int | _ >= 0}) : {Int | _ >= 0} do n end")));

    gated "unconstrained return is conservatively skipped" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error (post "  fn f(n : Int) : {Int | _ >= 0} do n end")));

    gated "guarded branches each satisfy the postcondition" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (post
                "  fn f(n : Int) : {Int | _ >= 0} do if n >= 0 do n else 0 end end")));

    gated "a branch that definitely violates is rejected" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (post
                "  fn f(n : Int) : {Int | _ >= 0} do if n < 0 do n else 0 end end")));

    (* ── The return binder is a CALLEE-side name, not a body name ────────────
       `check_post` translated the path conditions with the SAME resolver as the
       return predicate, in which the binder denotes the RETURN value.  A path
       condition was collected from the function BODY, so every name in it is a
       body name; when a parameter happens to share the binder's spelling the
       fact was re-pointed at the returned expression — the same caller/callee
       conflation already fixed for `check_call`'s path conditions.

       Here the guard `v < 0` is about the PARAMETER `v`; misread as the return
       value it becomes `k < 0`, which makes `v > 0` (i.e. `k > 0`) definitely
       false and reports correct code.  The right answer is SILENCE: `k` is
       unconstrained, so the postcondition is neither proven nor refuted. *)
    gated "a named return binder colliding with a parameter is not misattributed" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (post
                "  fn f(v : Int, k : Int) : {v : Int | v > 0} do\n\
                \    if v < 0 do k else 1 end\n\
                \  end")));

    (* Control: the SAME collision, with a tail that definitely violates.  Had
       the fix worked by simply dropping the path conditions (or the binder),
       this would go silent too. *)
    gated "the same collision still reports a definitely violating tail" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (post
                "  fn f(v : Int, k : Int) : {v : Int | v > 0} do\n\
                \    if v < 0 do 0 else 1 end\n\
                \  end")));

    (* Control: a named binder with NO collision still denotes the return value
       in the PREDICATE — the fix must change only the path context. *)
    gated "a named return binder still denotes the return value" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (post "  fn f() : {v : Int | v >= 0} do 0 - 1 end")));

    (* …and a guard on the colliding parameter must still discharge the
       postcondition when the tail IS that parameter, which is the case the
       body-namespace reading gets right and the binder reading only got right
       by accident. *)
    gated "a guard on the colliding parameter still discharges" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (post
                "  fn f(v : Int) : {v : Int | v > 0} do\n\
                \    if v > 0 do v else 1 end\n\
                \  end"))) ]

(* P1c: `assert(p)` acts as an assume — it extends the path context. *)
let assume_suite =
  [ gated "assert establishes a fact for a later call" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (decl
                "  fn g(i : Int) : Int do\n\
                \    assert(i >= 0)\n\
                \    take_n(i)\n\
                \  end")));

    gated "a contradicting assert makes the later call definitely violate" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (decl
                "  fn g(i : Int) : Int do\n\
                \    assert(i < 0)\n\
                \    take_n(i)\n\
                \  end"))) ]

(* P1a: a bare name defined (with a refinement) in two modules is ambiguous, so a
   bare call to it is conservatively skipped — never checked against the wrong
   predicate. *)
let collision_suite =
  [ gated "ambiguous bare call across modules is skipped (no false positive)" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod Root do\n\
             \  mod A do fn foo(n : {Int | _ >= 100}) : Int do n end end\n\
             \  mod B do\n\
             \    fn foo(n : {Int | _ >= 0}) : Int do n end\n\
             \    fn use_it() : Int do foo(5) end\n\
             \  end\n\
              end\n")) ]

(* P1b: a user `@[measure]` function can appear in predicates; guarded bounds
   over user-defined structure verify via path sensitivity. *)
let measure_prog body =
  Printf.sprintf
    "mod M do\n\
    \  @[measure]\n\
    \  fn size(t : Tree(a)) : Int do\n\
    \    match t do\n\
    \      Leaf -> 0\n\
    \      Node(l, x, r) -> 1 + size(l) + size(r)\n\
    \    end\n\
    \  end\n\
    \  fn get(t : Tree(a), i : {Int | _ >= 0 && _ < size(t)}) : a do get(t, i) end\n\
     %s\n\
     end\n"
    body

let measure_suite =
  [ gated "guarded bounds over a user measure verifies" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (measure_prog
                "  fn use_it(t : Tree(Int), i : Int) : Int do\n\
                \    if i >= 0 && i < size(t) do get(t, i) else 0 end\n\
                \  end")));

    gated "a guard contradicting the measure bound is rejected" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (measure_prog
                "  fn bad(t : Tree(Int), i : Int) : Int do\n\
                \    if i >= size(t) do get(t, i) else 0 end\n\
                \  end")));

    gated "unguarded measure bound is conservatively skipped" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (measure_prog
                "  fn ung(t : Tree(Int), i : Int) : Int do get(t, i) end")));

    (* Non-negativity inference: `size` is syntactically non-negative, so it can
       never satisfy a `_ < 0` postcondition — a definite violation.  Without the
       inference this would be skipped (size symbolic, unconstrained). *)
    gated "non-negative measure cannot satisfy a `_ < 0` postcondition" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (measure_prog
                "  fn f(t : Tree(Int)) : {Int | _ < 0} do size(t) end")));

    gated "non-negative measure DOES satisfy a `_ >= 0` postcondition" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (measure_prog
                "  fn f(t : Tree(Int)) : {Int | _ >= 0} do size(t) end"))) ]

(* M-a: with the ADT declared, `size` is AXIOMATISED — the solver computes
   measure values structurally from the recursion equations. *)
let axiom_prog body =
  Printf.sprintf
    "mod M do\n\
    \  type Tree(a) = Leaf | Node(Tree(a), a, Tree(a))\n\
    \  @[measure]\n\
    \  fn size(t : Tree(a)) : Int do\n\
    \    match t do\n\
    \      Leaf -> 0\n\
    \      Node(l, x, r) -> 1 + size(l) + size(r)\n\
    \    end\n\
    \  end\n\
    \  fn get(t : Tree(a), i : {Int | _ >= 0 && _ < size(t)}) : a do get(t, i) end\n\
     %s\n\
     end\n"
    body

let axiom_suite =
  [ gated "axioms compute size(Node(Leaf,x,Leaf))=1: index 5 is out of bounds" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (axiom_prog "  fn f(x : Int) : Int do get(Node(Leaf, x, Leaf), 5) end")));

    gated "axioms compute size=1: index 0 is in bounds" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (axiom_prog "  fn f(x : Int) : Int do get(Node(Leaf, x, Leaf), 0) end")));

    gated "axioms compute size(Node(Node(Leaf,x,Leaf),y,Leaf))=2: index 2 out of bounds" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (axiom_prog
                "  fn f(x : Int, y : Int) : Int do get(Node(Node(Leaf, x, Leaf), y, Leaf), 2) end"))) ]

(* M-b: the @[measure] soundness gate.  A measure that is not total, terminating
   and pure is a HARD compile error (the gate is z3-independent — purely
   syntactic — so these run ungated). *)
let case name expect src =
  Alcotest.test_case name `Quick (fun () ->
      Alcotest.(check bool) "gate" expect (has_refine_error src))

let gate_suite =
  [ case "effectful measure (calls panic) is rejected" true
      "mod M do\n\
      \  type Nat = Zero | Succ(Nat)\n\
      \  @[measure]\n\
      \  fn sz(n : Nat) : Int do\n\
      \    match n do\n\
      \      Zero -> panic(\"no\")\n\
      \      Succ(m) -> 1 + sz(m)\n\
      \    end\n\
      \  end\n\
       end\n";

    case "non-exhaustive measure is rejected" true
      "mod M do\n\
      \  type Color = Red | Green | Blue\n\
      \  @[measure]\n\
      \  fn rank(c : Color) : Int do\n\
      \    match c do\n\
      \      Red -> 0\n\
      \      Green -> 1\n\
      \    end\n\
      \  end\n\
       end\n";

    case "non-structural recursion is rejected" true
      "mod M do\n\
      \  type Nat = Zero | Succ(Nat)\n\
      \  @[measure]\n\
      \  fn bad(n : Nat) : Int do\n\
      \    match n do\n\
      \      Zero -> 0\n\
      \      Succ(m) -> 1 + bad(n)\n\
      \    end\n\
      \  end\n\
       end\n";

    case "a total, terminating, pure measure passes the gate" false
      "mod M do\n\
      \  type Nat = Zero | Succ(Nat)\n\
      \  @[measure]\n\
      \  fn sz(n : Nat) : Int do\n\
      \    match n do\n\
      \      Zero -> 0\n\
      \      Succ(m) -> 1 + sz(m)\n\
      \    end\n\
      \  end\n\
       end\n" ]

(* M-b: the built-in List(a) is axiomatised, so a user `length` measure computes
   list lengths structurally — `length([10,20]) = 2`. *)
let list_prog body =
  Printf.sprintf
    "mod M do\n\
    \  @[measure]\n\
    \  fn length(xs : List(a)) : Int do\n\
    \    match xs do\n\
    \      Nil -> 0\n\
    \      Cons(h, t) -> 1 + length(t)\n\
    \    end\n\
    \  end\n\
    \  fn nth(xs : List(a), i : {Int | _ >= 0 && _ < length(xs)}) : a do nth(xs, i) end\n\
     %s\n\
     end\n"
    body

let list_axiom_suite =
  [ gated "list axioms compute length([10,20])=2: index 5 is out of bounds" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error (list_prog "  fn f() : Int do nth([10, 20], 5) end")));

    gated "list axioms compute length([10,20])=2: index 1 is in bounds" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error (list_prog "  fn f() : Int do nth([10, 20], 1) end"))) ]

(* M-c: cross-measure calls + mutual recursion over mutually-recursive datatypes.
   `tsize`/`fsize` are defined over `RTree`/`RForest` (each references the other),
   call each other on structural substructures, and are axiomatised together in a
   single declare-datatypes — so `tsize(RNode(5, FEmpty)) = 1` is computed. *)
let mutual_prog body =
  Printf.sprintf
    "mod M do\n\
    \  type RTree = RNode(Int, RForest)\n\
    \  type RForest = FEmpty | FCons(RTree, RForest)\n\
    \  @[measure]\n\
    \  fn tsize(t : RTree) : Int do\n\
    \    match t do\n\
    \      RNode(x, f) -> 1 + fsize(f)\n\
    \    end\n\
    \  end\n\
    \  @[measure]\n\
    \  fn fsize(f : RForest) : Int do\n\
    \    match f do\n\
    \      FEmpty -> 0\n\
    \      FCons(t, rest) -> tsize(t) + fsize(rest)\n\
    \    end\n\
    \  end\n\
    \  fn tget(t : RTree, i : {Int | _ >= 0 && _ < tsize(t)}) : Int do tget(t, i) end\n\
     %s\n\
     end\n"
    body

let mutual_suite =
  [ gated "mutually-recursive measures compute tsize(RNode(5,FEmpty))=1: index 1 out of bounds" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error (mutual_prog "  fn f() : Int do tget(RNode(5, FEmpty), 1) end")));

    gated "mutually-recursive measures: index 0 is in bounds" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error (mutual_prog "  fn f() : Int do tget(RNode(5, FEmpty), 0) end")));

    gated "deeper structure: tsize(RNode(_,FCons(RNode(_,FEmpty),FEmpty)))=2, index 2 out of bounds" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (mutual_prog
                "  fn f() : Int do tget(RNode(7, FCons(RNode(8, FEmpty), FEmpty)), 2) end"))) ]

(* Flag-gating: with --no-measure-axioms, measures are purely symbolic, so a
   violation that is only detectable from the measure's recursion equations
   (a concrete-structure bound) is conservatively skipped instead of caught. *)
let has_refine_error_no_axioms src =
  let ctx = March_errors.Errors.create () in
  March_refinecheck.Refine_check.check_module ~measure_axioms:false ctx (parse src);
  March_errors.Errors.has_errors ctx

let flag_suite =
  [ gated "axioms ON (default): concrete-structure out-of-bounds is caught" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (axiom_prog "  fn f(x : Int) : Int do get(Node(Leaf, x, Leaf), 5) end")));

    gated "--no-measure-axioms: the same violation is skipped (symbolic measure)" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_no_axioms
             (axiom_prog "  fn f(x : Int) : Int do get(Node(Leaf, x, Leaf), 5) end")));

    Alcotest.test_case "--no-measure-axioms disables the soundness gate" `Quick (fun () ->
        (* a non-exhaustive measure is a hard error with axioms on, skipped with them off *)
        let prog =
          "mod M do\n\
          \  type Color = Red | Green | Blue\n\
          \  @[measure]\n\
          \  fn rank(c : Color) : Int do\n\
          \    match c do\n\
          \      Red -> 0\n\
          \      Green -> 1\n\
          \    end\n\
          \  end\n\
           end\n"
        in
        Alcotest.(check bool) "gate on" true (has_refine_error prog);
        Alcotest.(check bool) "gate off" false (has_refine_error_no_axioms prog));

    (* Constructor-tag refinements are NOT measure axioms: the flag documents
       itself as an escape hatch from measure cost only, so tag checking (and
       the vocabulary warning that depends on the ADT registry) must behave
       identically with it off. *)
    gated "--no-measure-axioms still checks constructor tags" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error_no_axioms
             "mod M do\n\
             \  fn unwrap(o : {Option(Int) | is_Some(_)}) : Int do 0 end\n\
             \  fn main() : Int do unwrap(None) end\n\
              end\n"));

    Alcotest.test_case "--no-measure-axioms does not call `is_Some` unknown vocabulary"
      `Quick (fun () ->
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ~measure_axioms:false ctx
          (parse
             "mod M do\n\
             \  fn f(o : {Option(Int) | is_Some(_)}) : Int do 1 end\n\
             \  fn main() : Int do f(Some(1)) end\n\
              end\n");
        Alcotest.(check bool) "no warning" false
          (List.exists
             (fun (d : March_errors.Errors.diagnostic) ->
               d.March_errors.Errors.severity = March_errors.Errors.Warning)
             ctx.March_errors.Errors.diagnostics)) ]

(* Use/alias-aware call resolution: a call name resolves the way the typechecker
   resolves it (lexical module scope + alias + use), not by fragile string
   matching.  This both CATCHES violations the old skip-on-collision missed and
   stays free of false positives via correct shadowing. *)
let resolution_suite =
  [ gated "sibling call on a name collision is now resolved + checked (violation caught)" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error_d {|mod Root do
  mod A do fn foo(n : {Int | _ >= 100}) : Int do n end end
  mod B do
    fn foo(n : {Int | _ >= 0}) : Int do n end
    fn use_it() : Int do foo(-5) end
  end
end|}));

    gated "sibling resolves to the LOCAL definition, not the colliding one (no false positive)" (fun () ->
        (* foo(5) in Root.B must check `_ >= 0` (Root.B.foo), not `_ >= 100` (Root.A.foo) *)
        Alcotest.(check bool) "no error" false
          (has_refine_error_d {|mod Root do
  mod A do fn foo(n : {Int | _ >= 100}) : Int do n end end
  mod B do
    fn foo(n : {Int | _ >= 0}) : Int do n end
    fn use_it() : Int do foo(5) end
  end
end|}));

    gated "alias-qualified call is resolved + checked" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error_d {|mod Root do
  mod Lib do
    mod Inner do fn take_pos(n : {Int | _ >= 0}) : Int do n end end
  end
  mod App do
    alias Lib.Inner as I
    fn use_it() : Int do I.take_pos(-1) end
  end
end|}));

    gated "use-imported call is resolved + checked" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error_d {|mod Root do
  mod Lib do fn take_pos(n : {Int | _ >= 0}) : Int do n end end
  mod App do
    use Lib.{take_pos}
    fn use_it() : Int do take_pos(-1) end
  end
end|}));

    gated "a non-refined sibling shadows an outer refined function (no false positive)" (fun () ->
        (* helper(-5) resolves to Root.Inner.helper (non-refined), NOT Root.helper *)
        Alcotest.(check bool) "no error" false
          (has_refine_error_d {|mod Root do
  fn helper(n : {Int | _ >= 0}) : Int do n end
  mod Inner do
    fn helper(n : Int) : Int do n end
    fn use_it() : Int do helper(-5) end
  end
end|})) ]

(* Gap #1 spike: EField in smt_of + TDRecord as 1-ctor SMT datatype.
   Proves { v : State | v.count >= 0 } discharges on { count = 1 }, rejects
   { count = -1 }, and conservatively skips { count = x } (unknown). *)
let record_suite =
  let ok_src = {|mod M do
  type State = { count : Int }
  fn ok_migrate() : {v : State | v.count >= 0} do
    { count: 1 }
  end
end|} in
  let bad_src = {|mod M do
  type State = { count : Int }
  fn bad_migrate() : {v : State | v.count >= 0} do
    { count: -1 }
  end
end|} in
  let skip_src = {|mod M do
  type State = { count : Int }
  fn unknown_migrate(x : Int) : {v : State | v.count >= 0} do
    { count: x }
  end
end|} in
  let meas_ok_src = {|mod M do
  @[measure]
  pfn mlength(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(_, t) -> 1 + mlength(t)
    end
  end
  type State = { count : Int, history : List(Int) }
  fn good2() : {v : State | mlength(v.history) == v.count} do
    { count: 0, history: Nil }
  end
end|} in
  let meas_bad_src = {|mod M do
  @[measure]
  pfn mlength(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(_, t) -> 1 + mlength(t)
    end
  end
  type State = { count : Int, history : List(Int) }
  fn bad2() : {v : State | mlength(v.history) == v.count} do
    { count: 1, history: Nil }
  end
end|} in
  let len_ok_src = {|mod M do
  type State = { count : Int, history : List(Int) }
  fn good3() : {v : State | len(v.history) == v.count} do
    { count: 0, history: Nil }
  end
end|} in
  let len_bad_src = {|mod M do
  type State = { count : Int, history : List(Int) }
  fn bad3() : {v : State | len(v.history) == v.count} do
    { count: 1, history: Nil }
  end
end|} in
  [ gated "record postcondition: literal satisfies" (fun () ->
        Alcotest.(check bool) "no error" false (has_refine_error ok_src));
    gated "record postcondition: literal violates" (fun () ->
        Alcotest.(check bool) "has error" true (has_refine_error bad_src));
    gated "record postcondition: unknown value skipped conservatively" (fun () ->
        Alcotest.(check bool) "no error" false (has_refine_error skip_src));
    gated "measure over field: user @[measure] mlength holds for Nil/0" (fun () ->
        Alcotest.(check bool) "no error" false (has_refine_error meas_ok_src));
    gated "measure over field: user @[measure] mlength violated by Nil/1" (fun () ->
        Alcotest.(check bool) "has error" true (has_refine_error meas_bad_src));
    gated "measure over field: builtin len holds for Nil/0" (fun () ->
        Alcotest.(check bool) "no error" false (has_refine_error len_ok_src));
    gated "measure over field: builtin len violated by Nil/1" (fun () ->
        Alcotest.(check bool) "has error" true (has_refine_error len_bad_src));

    (* B1: record-typed parameter refinements as preconditions *)
    gated "record precondition: carried invariant verifies" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error {|mod M do
  type State = { count : Int }
  fn keep(old : {s : State | s.count >= 0}) : {v : State | v.count >= 0} do
    { count: old.count }
  end
end|}));
    gated "record precondition: violating migration refuted" (fun () ->
        Alcotest.(check bool) "has error" true
          (has_refine_error {|mod M do
  type State = { count : Int }
  fn drop(old : {s : State | s.count >= 0}) : {v : State | v.count >= 0} do
    { count: old.count - 1 }
  end
end|}));

    (* B3: end-to-end migration shape — param + return + measure *)
    gated "migration shape: count=0/history=Nil sound" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error {|mod M do
  type State = { count : Int, history : List(Int) }
  fn migrate(old : {s : State | s.count >= 0}) : {v : State | v.count >= 0 && len(v.history) == v.count} do
    { count: 0, history: Nil }
  end
end|}));
    gated "migration shape: count=old/history=Nil unsound" (fun () ->
        Alcotest.(check bool) "has error" true
          (has_refine_error {|mod M do
  type State = { count : Int, history : List(Int) }
  fn migrate(old : {s : State | s.count >= 0}) : {v : State | v.count >= 0 && len(v.history) == v.count} do
    { count: old.count, history: Nil }
  end
end|}));

    (* ── Call-site (precondition) side. ─────────────────────────────────────
       Four of these six assert SILENCE: an unreflectable record, an
       unreflectable field value, and a forwarded refinement that is merely
       unproven must all be SKIPPED under the definite-failure stance. *)
    gated "record precondition: literal argument violates" (fun () ->
        Alcotest.(check bool) "has error" true
          (has_refine_error {|mod M do
  type Config = { port : Int }
  fn serve(c : {v : Config | v.port >= 1}) : Int do c.port end
  fn main() : Int do serve({ port: 0 }) end
end|}));

    gated "record precondition: literal argument satisfies" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error {|mod M do
  type Config = { port : Int }
  fn serve(c : {v : Config | v.port >= 1}) : Int do c.port end
  fn main() : Int do serve({ port: 8080 }) end
end|}));

    gated "record precondition: unknown record is skipped" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error {|mod M do
  type Config = { port : Int }
  fn serve(c : {v : Config | v.port >= 1}) : Int do c.port end
  fn f(c : Config) : Int do serve(c) end
end|}));

    gated "record precondition: unknown FIELD value is skipped" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error {|mod M do
  type Config = { port : Int }
  fn serve(c : {v : Config | v.port >= 1}) : Int do c.port end
  fn f(p : Int) : Int do serve({ port: p }) end
end|}));

    gated "record precondition: a refined record param forwards" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error {|mod M do
  type Config = { port : Int }
  fn serve(c : {v : Config | v.port >= 1}) : Int do c.port end
  fn fwd(c : {v : Config | v.port >= 1}) : Int do serve(c) end
end|}));

    gated "record precondition: multi-field predicate on the wrong field" (fun () ->
        Alcotest.(check bool) "has error" true
          (has_refine_error {|mod M do
  type Config = { port : Int, retries : Int }
  fn serve(c : {v : Config | v.port >= 1 && v.retries >= 0}) : Int do c.port end
  fn main() : Int do serve({ port: 8080, retries: -1 }) end
end|}));

    (* Forwarding: the discriminating pair.  A WEAKER refinement neither
       establishes nor contradicts the callee's, so it must be silent; a
       CONTRADICTORY one is a definite failure and must be reported.  The
       second is what proves field facts actually travel through a variable. *)
    gated "record precondition: forwarding a WEAKER refinement is not proven" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error {|mod M do
  type Config = { port : Int }
  fn serve(c : {v : Config | v.port >= 1}) : Int do c.port end
  fn fwd(c : {v : Config | v.port >= 0}) : Int do serve(c) end
end|}));

    gated "record precondition: forwarding a CONTRADICTORY refinement is caught" (fun () ->
        Alcotest.(check bool) "has error" true
          (has_refine_error {|mod M do
  type Config = { port : Int }
  fn serve(c : {v : Config | v.port >= 1}) : Int do c.port end
  fn fwd(c : {v : Config | v.port <= 0}) : Int do serve(c) end
end|}));

    (* A record sort and a measure/ADT sort in ONE verification condition: the
       two preambles must dedup, since a Z3 error maps the VC to Unknown and
       would silently skip the check rather than merely adding noise. *)
    gated "record precondition: record + measure sorts coexist in one VC" (fun () ->
        Alcotest.(check bool) "has error" true
          (has_refine_error {|mod M do
  @[measure]
  pfn mlength(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(_, t) -> 1 + mlength(t)
    end
  end
  type State = { count : Int, history : List(Int) }
  fn take(s : {v : State | mlength(v.history) == v.count}) : Int do s.count end
  fn main() : Int do take({ count: 1, history: Nil }) end
end|}));

    (* A record field whose declared type is NOT Int, bound to a variable.  The
       scalar reflection declares every variable SInt, so reflecting the
       variable's own term there would build a constructor application with
       mismatched argument sorts — and Z3 answers a malformed VC with an error
       that DESYNCS the long-lived `z3 -in` channel, silently disabling
       refinement checking for the rest of the compilation.

       The record is no longer skipped for it: the ill-sorted field is replaced
       by a FRESH constant at the field's DECLARED sort, carrying no
       assumptions, so the VC is well-sorted and the checkable `port` field
       survives.  `port: 0` against `v.port >= 1` is therefore now reported —
       a violation that used to be lost to a sibling field. *)
    gated "record precondition: an unreflectable sibling field no longer hides `port`" (fun () ->
        Alcotest.(check bool) "has error" true
          (has_refine_error {|mod M do
  type Config = { port : Int, name : String }
  fn serve(c : {v : Config | v.port >= 1}) : Int do c.port end
  fn f(n : String) : Int do serve({ port: 0, name: n }) end
end|}));

    (* The other direction, and the one that matters for soundness: a
       SATISFYING `port` alongside the same unreflectable field must stay
       silent, i.e. the opaque stand-in must not make anything provable. *)
    gated "record precondition: a satisfying `port` beside an opaque field passes" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error {|mod M do
  type Config = { port : Int, name : String }
  fn serve(c : {v : Config | v.port >= 1}) : Int do c.port end
  fn f(n : String) : Int do serve({ port: 8080, name: n }) end
end|}));

    (* Nothing may be concluded ABOUT the opaque field.  Here the predicate is
       entirely about the unreflectable list field and its true value (`len` of
       `Cons(1, Nil)` is 1) does NOT satisfy `== 5` — a real violation, which we
       must nevertheless stay SILENT about, because the stand-in constant is
       unconstrained and proves nothing in either direction.  If this ever
       reports, the substitution has started concluding things about a value it
       cannot see. *)
    gated "record precondition: a predicate about the opaque field is skipped" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error {|mod M do
  type State = { count : Int, history : List(Int) }
  fn take(s : {v : State | len(v.history) == v.count}) : Int do s.count end
  fn f() : Int do take({ count: 5, history: Cons(1, Nil) }) end
end|}));

    (* …and the same predicate whose value the opaque field DOES satisfy is
       equally silent — the stand-in is symmetric, not a one-way ratchet. *)
    gated "record precondition: an opaque field cannot discharge either" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error {|mod M do
  type State = { count : Int, history : List(Int) }
  fn take(s : {v : State | len(v.history) == v.count}) : Int do s.count end
  fn f() : Int do take({ count: 1, history: Cons(1, Nil) }) end
end|}));

    (* The opaque stand-in is a CALL-SITE-only device.  [check_post] switches to
       "a SAT model is a definite violation" whenever a concrete record is in
       scope, and under that rule a model that assigned an unconstrained field a
       bad value would be reported as a counterexample even though the real
       field holds a perfectly good value — a false positive.  So the return
       side keeps the conservative skip, and this pins it. *)
    gated "record postcondition: an unreflectable field still skips the whole record" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error {|mod M do
  type State = { count : Int, history : List(Int) }
  fn mk() : {v : State | v.count >= 0} do
    { count: -1, history: Cons(1, Nil) }
  end
end|}));

    (* The channel-survival half: an unrelated Int violation AFTER such a record
       call must still be reported.  If the record VC poisoned the solver this
       goes silent — the failure mode is silence, so only this shape catches it. *)
    gated "record precondition: a skipped record does not poison the solver" (fun () ->
        Alcotest.(check bool) "has error" true
          (has_refine_error {|mod M do
  type Config = { port : Int, name : String }
  fn serve(c : {v : Config | v.port >= 1}) : Int do c.port end
  fn take_n(n : {Int | _ >= 0}) : Int do n end
  fn first(n : String) : Int do serve({ port: 8080, name: n }) end
  fn second() : Int do take_n(-3) end
end|}));

    (* A NESTED sort mismatch: `Cons(1, Nil)` sits well at an `M_List` field,
       but `Cons`'s own head field is `Elem` (the built-in `List` is generic, so
       its element sort is opaque) and the scalar reflection puts the integer
       `1` there.  A top-level-only fit check passes this and builds
       `(Cons 1 Nil)`, which z3 rejects with a MULTI-LINE `(error …)` — the
       exact shape that used to leave a continuation line in the pipe and shift
       every later verdict by one.  `(Cons 1 Nil)` is therefore still never
       built; the field is replaced by a fresh `M_List` constant instead, which
       is well-sorted, and `port: 0` is now caught rather than lost. *)
    gated "record precondition: a concrete list element becomes an opaque stand-in" (fun () ->
        Alcotest.(check bool) "has error" true
          (has_refine_error {|mod M do
  type Config = { port : Int, history : List(Int) }
  fn serve(c : {v : Config | v.port >= 1}) : Int do c.port end
  fn f() : Int do serve({ port: 0, history: Cons(1, Nil) }) end
end|}));

    (* Channel survival across ALL FOUR refinable subjects in one module, with
       the record's unreflectable list field first and a plain Int violation
       LAST.  A verdict shifted by one desynchronised read turns the two
       CORRECT calls in between into reported violations, so this pins the
       no-false-positive property and the report-still-arrives property at
       once. *)
    gated "record + string + ADT + Int in one module: only the Int call is reported" (fun () ->
        Alcotest.(check int) "exactly one violation" 1
          (refine_error_count {|mod M do
  type Config = { port : Int, history : List(Int) }
  fn serve(c : {v : Config | v.port >= 1}) : Int do c.port end
  fn nonempty(s : {String | len(_) > 0}) : Int do 1 end
  fn unwrap(o : {Option(Int) | is_Some(_)}) : Int do 0 end
  fn takepos(n : {Int | _ >= 0}) : Int do n end
  fn main() : Int do
    let a = serve({ port: 8080, history: Cons(1, Nil) })
    let b = nonempty("hello")
    let c = unwrap(Some(7))
    let d = takepos(-3)
    a + b + c + d
  end
end|}));

    gated "sequential modules may redefine a qualified record shape" (fun () ->
        with_temp_root "march_refine_redefine_" (fun root ->
          Alcotest.(check bool) "first shape has no error" false
            (has_refine_error ~root {|mod M do
  type State = { count : Int }
  fn valid() : {v : State | v.count >= 0} do { count: 0 } end
end|});
          Alcotest.(check bool)
            "second incompatible shape still reports violation" true
            (has_refine_error ~root {|mod M do
  type State = { count : Int, history : List(Int) }
  fn invalid() : {v : State | len(v.history) == v.count} do
    { count: 1, history: Nil }
  end
end|}))) ]

(* ── Record FIELD facts in the path context ────────────────────────────────
   A guard on a record field (`if c.port >= 1`) lands in the path context like
   any other condition, but until the path translation grew a record field
   resolver `c.port` translated to None and the fact was silently dropped.

   Only the CONTRADICTION direction is observable through this API: under the
   definite-failure stance a fact that merely *discharges* a precondition turns
   an error into silence, and silence is also what a skipped call produces.  So
   the RED cases below are the ones where a guard makes a call a DEFINITE
   failure, and they are paired with silence assertions covering the satisfying
   guard and the unguarded (still skipped) shape.

   The four shadowing cases assert SILENCE.  A path fact is recorded against a
   NAME; when an inner scope rebinds that name the fact is about the OUTER
   value, and attributing it to the inner binding is a false positive — the one
   failure this subsystem must never have.  Each is written so the inner call is
   still REFLECTABLE (the binder is re-established as a record), because a
   shadowing test whose inner call is skipped for an unrelated reason would pass
   no matter what the shadowing code did. *)
let record_path_suite =
  let prog body =
    Printf.sprintf
      {|mod M do
  type Config = { port : Int }
  fn serve(c : {v : Config | v.port >= 1}) : Int do c.port end
  fn mk() : Result(Config, String) do Ok({ port: 1 }) end
%s
end|}
      body
  in
  [ gated "a satisfying field guard leaves the call silent" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (prog
                "  fn f(c : Config) : Int do\n\
                \    if c.port >= 1 do serve(c) else 0 end\n\
                \  end")));

    gated "a field guard contradicting the precondition is caught" (fun () ->
        Alcotest.(check bool) "has error" true
          (has_refine_error
             (prog
                "  fn f(c : Config) : Int do\n\
                \    if c.port <= 0 do serve(c) else 0 end\n\
                \  end")));

    gated "the else-branch negates a field guard" (fun () ->
        Alcotest.(check bool) "has error" true
          (has_refine_error
             (prog
                "  fn f(c : Config) : Int do\n\
                \    if c.port >= 1 do 0 else serve(c) end\n\
                \  end")));

    (* The guard narrows a refinement that on its own is merely WEAKER (and so
       correctly silent — see the record-postconditions group) into a definite
       failure.  This is the case that proves the guard's fact and the carried
       record refinement land on the SAME SMT constant. *)
    gated "a field guard narrows a weaker record refinement into a failure" (fun () ->
        Alcotest.(check bool) "has error" true
          (has_refine_error
             (prog
                "  fn f(c : {v : Config | v.port >= 0}) : Int do\n\
                \    if c.port == 0 do serve(c) else 0 end\n\
                \  end")));

    gated "an unguarded unrefined record argument is still skipped" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error (prog "  fn f(c : Config) : Int do serve(c) end")));

    (* ── Shadow discipline ──────────────────────────────────────────────────
       The guard is CONTRADICTORY, so a fact that survived the rebinding would
       be reported as a violation of correct code. *)
    gated "an inner `let` rebinding the record retires the field fact" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (prog
                "  fn f(c : Config, d : Config) : Int do\n\
                \    if c.port <= 0 do\n\
                \      let c = d\n\
                \      serve(c)\n\
                \    else 0 end\n\
                \  end")));

    gated "a lambda parameter rebinding the record retires the field fact" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (prog
                "  fn f(c : Config, d : Config) : Int do\n\
                \    if c.port <= 0 do\n\
                \      let g = fn (c : Config) -> serve(c)\n\
                \      g(d)\n\
                \    else 0 end\n\
                \  end")));

    (* `let?` is the one rebinding this group cannot make DISCRIMINATING: its
       binder can carry no type annotation (`let? x : T = …` is a dedicated
       parse error) and March has no annotated-expression form, so the payload's
       record type is never declared anywhere [recenv] can see it.  The inner
       `c` is therefore not a known record, the call is skipped for that reason,
       and this case would stay silent even if `let?` retired nothing.  It is
       kept as a safety assertion — `visit`'s `ELetQ` arm does call both
       [path_shadow] and [recenv_shadow], and this pins that it stays silent —
       but it does NOT prove the retirement the way the other three do. *)
    gated "a `let?` binder rebinding the record stays silent" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (prog
                "  fn f(c : Config) : Result(Int, String) do\n\
                \    if c.port <= 0 do\n\
                \      let? c = mk()\n\
                \      Ok(serve(c))\n\
                \    else Ok(0) end\n\
                \  end")));

    gated "a match binder rebinding the record retires the field fact" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (prog
                "  fn f(c : Config, d : Config) : Int do\n\
                \    if c.port <= 0 do\n\
                \      match d do\n\
                \        c -> serve(c)\n\
                \      end\n\
                \    else 0 end\n\
                \  end")));

    (* The same four rebindings, but with the guard SATISFYING the callee's
       precondition: the outer fact must not travel in this direction either,
       so these stay silent for the right reason (no fact, not a masked one).
       Paired with the contradictory versions above they pin that the retirement
       is unconditional rather than direction-dependent. *)
    gated "a rebinding retires a SATISFYING field fact too" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (prog
                "  fn f(c : Config, d : Config) : Int do\n\
                \    if c.port >= 1 do\n\
                \      let c = d\n\
                \      serve(c)\n\
                \    else 0 end\n\
                \  end")));

    (* Channel survival: a record path fact in the same module as an unrelated
       Int violation.  A malformed VC (a symbol declared at two sorts, say) is
       answered with an `(error …)` that desynchronises the shared `z3 -in`
       channel and silently disables checking for the rest of the compilation —
       so the failure mode is SILENCE, and only this shape catches it. *)
    gated "a record field guard does not poison the solver channel" (fun () ->
        Alcotest.(check int) "exactly one violation" 1
          (refine_error_count
             (prog
                "  fn take_n(n : {Int | _ >= 0}) : Int do n end\n\
                \  fn f(c : Config) : Int do\n\
                \    if c.port >= 1 do serve(c) else 0 end\n\
                \  end\n\
                \  fn g() : Int do take_n(-3) end"))) ]

(* Guard path sensitivity for EMatch arms: `when` guards establish facts
   that discharge call-site VCs and postconditions. *)
let guard_suite =
  [ gated "match `when n >= 0` lets take_n(n) verify" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (decl
                "  fn g(n : Int) : Int do\n\
                \    match n do\n\
                \      n when n >= 0 -> take_n(n)\n\
                \      _ -> 0\n\
                \    end\n\
                \  end")));

    gated "match `when n < 0` contradicts take_n precondition: error" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (decl
                "  fn g(n : Int) : Int do\n\
                \    match n do\n\
                \      n when n < 0 -> take_n(n)\n\
                \      _ -> 0\n\
                \    end\n\
                \  end")));

    gated "match `when n >= 0` discharges `_ >= 0` postcondition" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (post
                "  fn clamp_pos(n : Int) : {Int | _ >= 0} do\n\
                \    match n do\n\
                \      n when n >= 0 -> n\n\
                \      _ -> 0\n\
                \    end\n\
                \  end")));

    gated "arm without guard returning literal -1 still violates postcondition" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (post
                "  fn wrong(n : Int) : {Int | _ > 0} do\n\
                \    match n do\n\
                \      n when n > 0 -> n\n\
                \      _ -> 0 - 1\n\
                \    end\n\
                \  end"))) ]

(* ── Tier 0: postcondition propagation ─────────────────────────────────────
   A callee's declared return refinement becomes a fact at its call sites. *)
let t0 body =
  Printf.sprintf
    "mod M do\n\
    \  fn neg() : {Int | _ < 0} do 0 - 1 end\n\
    \  fn nonneg() : {Int | _ >= 0} do 1 end\n\
    \  fn takepos(n : {Int | _ >= 0}) : Int do n end\n\
     %s\n\
     end\n"
    body

let tier0_suite =
  [ gated "recording a return refinement changes nothing on a compatible call" (fun () ->
        (* Task 1 records the signature but does not yet consume it.  Both of
           these must stay silent, before AND after the change. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error (t0 "  fn f() : Int do let c = nonneg()\n    takepos(c) end")));

    gated "a non-refined function is still resolvable (no regression)" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error (t0 "  fn plain() : Int do 7 end\n  fn f() : Int do takepos(plain()) end")));

    gated "let-bound postcondition `_ < 0` contradicts `_ >= 0`" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error (t0 "  fn f() : Int do let c = neg()\n    takepos(c) end")));

    gated "let-bound compatible postcondition passes" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error (t0 "  fn f() : Int do let c = nonneg()\n    takepos(c) end")));

    gated "explicit annotation still wins over the inferred postcondition" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (t0 "  fn f() : Int do let c : {Int | _ < 0} = neg()\n    takepos(c) end")));

    gated "inline call arg `takepos(neg())` is rejected" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error (t0 "  fn f() : Int do takepos(neg()) end")));

    gated "inline call arg with compatible postcondition passes" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error (t0 "  fn f() : Int do takepos(nonneg()) end")));

    gated "inline call to a non-refined function is skipped" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (t0 "  fn plain() : Int do 0 - 9 end\n  fn f() : Int do takepos(plain()) end")));

    gated "inline call arg binder used twice must reflect to one constant" (fun () ->
        (* `four`'s predicate `n > 3 && n < 5` forces n == 4, contradicting
           `notfour`'s postcondition `_ != 4`.  If the two occurrences of `n`
           reflect the inline argument `notfour()` to two DIFFERENT fresh
           SMT constants, the contradiction is lost and this wrongly passes
           (see the let-bound control just below, which must still fail). *)
        Alcotest.(check bool) "error" true
          (has_refine_error
             (post
                "  fn notfour() : {Int | _ != 4} do 5 end\n\
                \  fn four(n : {Int | n > 3 && n < 5}) : Int do n end\n\
                \  fn f() : Int do four(notfour()) end")));

    gated "let-bound control for the binder-reuse case still fails" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (post
                "  fn notfour() : {Int | _ != 4} do 5 end\n\
                \  fn four(n : {Int | n > 3 && n < 5}) : Int do n end\n\
                \  fn f() : Int do\n\
                \    let c = notfour()\n\
                \    four(c)\n\
                \  end")));

    gated "postcondition resolves through a qualified cross-module call" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error_d
             "mod Root do\n\
              mod Lib do\n\
             \  fn neg() : {Int | _ < 0} do 0 - 1 end\n\
              end\n\
              mod App do\n\
             \  fn takepos(n : {Int | _ >= 0}) : Int do n end\n\
             \  fn f() : Int do let c = Lib.neg()\n    takepos(c) end\n\
              end\n\
              end\n"));

    (* Tier 1 superseded this: `_ < n` mentions the parameter `n`, and the call
       `below(0)` instantiates it as `_ < 0`, which contradicts `_ >= 0`.  Until
       relational postconditions propagated, this case asserted SILENCE and was
       the marker for the Tier 0/Tier 1 boundary. *)
    gated "relational postcondition IS propagated after substitution" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (t0 "  fn below(n : Int) : {Int | _ < n} do n - 1 end\n\
                 \  fn f() : Int do let c = below(0)\n    takepos(c) end")));

    gated "postcondition reaches a call inside an if-branch" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (t0 "  fn f(k : Int) : Int do\n\
                 \    let c = neg()\n\
                 \    if k > 0 do takepos(c) else 0 end\n\
                 \  end")));

    gated "shadowed local definition wins over an enclosing refined one" (fun () ->
        (* App.neg has no refinement and must shadow Lib.neg, so nothing is
           learned and the call is skipped. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             "mod Root do\n\
              mod Lib do\n\
             \  fn neg() : {Int | _ < 0} do 0 - 1 end\n\
              end\n\
              mod App do\n\
             \  fn neg() : Int do 5 end\n\
             \  fn takepos(n : {Int | _ >= 0}) : Int do n end\n\
             \  fn f() : Int do let c = neg()\n    takepos(c) end\n\
              end\n\
              end\n"));

    gated "an UNVERIFIED postcondition does not propagate (no false positive)" (fun () ->
        (* `score`'s declared `_ < 0` is stale: `helper(x)` is opaque, so the
           definition side can neither prove nor refute it.  An unproven
           postcondition stays legal at the definition and must NOT travel to
           call sites — believing it here would flag the CORRECT call
           `takepos(score(5))` (score(5) = 6, which satisfies `_ >= 0`). *)
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod Stale do\n\
             \  fn helper(x : Int) : Int do x + 1 end\n\
             \  fn score(x : Int) : {Int | _ < 0} do helper(x) end\n\
             \  fn takepos(n : {Int | _ >= 0}) : Int do n end\n\
             \  fn main() : Int do takepos(score(5)) end\n\
              end\n"));

    gated "a VERIFIED postcondition still propagates (headline feature)" (fun () ->
        (* `0 - 1` is reflectable and verifies against `_ < 0`, so the fact is
           true and may be assumed at the call site. *)
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod Ok do\n\
             \  fn neg() : {Int | _ < 0} do 0 - 1 end\n\
             \  fn takepos(n : {Int | _ >= 0}) : Int do n end\n\
             \  fn f() : Int do takepos(neg()) end\n\
              end\n"));

    gated "a lambda parameter shadows a refined outer local" (fun () ->
        (* The inner `c` is the lambda's own unrefined parameter; the outer
           refined `c` must not leak into its body. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod Shadow do\n\
             \  fn neg() : {Int | _ < 0} do 0 - 1 end\n\
             \  fn takepos(n : {Int | _ >= 0}) : Int do n end\n\
             \  fn f() : Int do\n\
             \    let c = neg()\n\
             \    let g = fn c -> takepos(c)\n\
             \    g(5)\n\
             \  end\n\
              end\n"));

    gated "a match pattern binder shadows a refined outer local" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod ShadowMatch do\n\
             \  fn neg() : {Int | _ < 0} do 0 - 1 end\n\
             \  fn takepos(n : {Int | _ >= 0}) : Int do n end\n\
             \  fn f(o : Option(Int)) : Int do\n\
             \    let c = neg()\n\
             \    match o do\n\
             \      Some(c) -> takepos(c)\n\
             \      None -> 0\n\
             \    end\n\
             \  end\n\
              end\n"));

    gated "an unrefined let shadows a refined outer local" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod ShadowLet do\n\
             \  fn neg() : {Int | _ < 0} do 0 - 1 end\n\
             \  fn takepos(n : {Int | _ >= 0}) : Int do n end\n\
             \  fn f() : Int do\n\
             \    let c = neg()\n\
             \    let c = 5\n\
             \    takepos(c)\n\
             \  end\n\
              end\n"));

    gated "a let? binder shadows a refined outer local" (fun () ->
        (* `let? c = ok5()` rebinds `c` to the Ok payload (5) before the
           continuation runs; the outer refined `c` (from `neg()`) must not
           leak into `takepos(c)`. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod LetQ do\n\
             \  fn neg() : {Int | _ < 0} do 0 - 1 end\n\
             \  fn ok5() : Result(Int, String) do Ok(5) end\n\
             \  fn takepos(n : {Int | _ >= 0}) : Int do n end\n\
             \  fn f() : Result(Int, String) do\n\
             \    let c = neg()\n\
             \    let? c = ok5()\n\
             \    Ok(takepos(c))\n\
             \  end\n\
              end\n")) ]

(* ── String refinements ──────────────────────────────────────────────────── *)
let str_decl body =
  Printf.sprintf
    "mod M do\n\
    \  fn nonempty(s : {String | len(_) > 0}) : Int do 1 end\n\
    \  fn short(s : {String | len(_) <= 3}) : Int do 2 end\n\
     %s\n\
     end\n"
    body

let string_suite =
  [ gated "nonempty(\"\") is rejected" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error (str_decl "  fn main() : Int do nonempty(\"\") end")));

    gated "nonempty(\"abc\") passes" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error (str_decl "  fn main() : Int do nonempty(\"abc\") end")));

    gated "short(\"abcd\") is rejected (length 4 > 3)" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error (str_decl "  fn main() : Int do short(\"abcd\") end")));

    gated "an unknown String variable is skipped" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error (str_decl "  fn f(s : String) : Int do nonempty(s) end")));

    gated "a String-refined local propagates" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (str_decl "  fn f(s : {String | len(_) > 0}) : Int do nonempty(s) end")));

    gated "list `len` still works (no overload regression)" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod M do\n\
             \  fn at(xs : List(Int), i : {Int | _ >= 0 && _ < len(xs)}) : Int do i end\n\
             \  fn main() : Int do at([1, 2], 5) end\n\
              end\n"));

    (* Regression: an early draft resolved `len` with a `match` dangling inside
       an `if ... then`, which silently swallowed the rest of the `else if`
       chain.  OCaml accepted it and every string test still passed, but ALL
       non-string variable resolution had quietly stopped working.  This is the
       cheapest predicate that pins the non-string path. *)
    gated "an Int `_ == 0` contract still rejects a violating literal" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod M do\n\
             \  fn iszero(n : {Int | _ == 0}) : Int do n end\n\
             \  fn main() : Int do iszero(5) end\n\
              end\n"));

    (* Regression: the string encoding once declared a bare `len` function, which
       collided with any program variable of that name.  z3 answered the
       malformed query with an error line, and because the solver is ONE
       long-lived process whose driver reads exactly one verdict per query, that
       desynchronised the channel and silently swallowed every later diagnostic
       in the compilation.  Both violations here must be reported.

       The guard `len > 0` puts an Int constant named `len` into the very same
       VC as the string preamble, which is what makes the two symbols collide.
       The second expected error is the canary: it comes from a LATER, perfectly
       well-formed VC, so losing it proves the channel was corrupted rather than
       just this one query being wrong. *)
    gated "a variable named `len` does not collide with the string encoding" (fun () ->
        Alcotest.(check int) "two errors" 2
          (refine_error_count
             "mod M do\n\
             \  fn nonempty(s : {String | len(_) > 0}) : Int do 1 end\n\
             \  fn iszero(n : {Int | _ == 0}) : Int do n end\n\
             \  fn f(len : Int) : Int do\n\
             \    if len > 0 do nonempty(\"\") else 0 end\n\
             \  end\n\
             \  fn main() : Int do iszero(5) end\n\
              end\n"));

    (* Regression: a caller variable reflected as an Int must never be compared
       against a string constant.  z3 rejects the mixed-sort term outright, with
       the same channel-corrupting consequence. *)
    gated "a mixed-sort guard does not corrupt the check it guards" (fun () ->
        (* `u` is neither the binder nor a parameter of the callee, so it is
           reflected as an Int while `"a"` reflects into the string sort.  The
           resulting `(= u $str…)` is ill-sorted and must be DROPPED from the
           assumptions; sending it makes z3 reject the query and the violation
           in the very same VC is lost. *)
        Alcotest.(check int) "one error" 1
          (refine_error_count
             "mod M do\n\
             \  fn nonempty(s : {String | len(_) > 0}) : Int do 1 end\n\
             \  fn g(u : String) : Int do\n\
             \    if u == \"a\" do nonempty(\"\") else 0 end\n\
             \  end\n\
              end\n"));

    gated "a `_ != \"\"` contract rejects the empty literal" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod M do\n\
             \  fn f(s : {String | _ != \"\"}) : Int do 1 end\n\
             \  fn main() : Int do f(\"\") end\n\
              end\n"));

    gated "a `_ != \"\"` contract accepts a non-empty literal" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn f(s : {String | _ != \"\"}) : Int do 1 end\n\
             \  fn main() : Int do f(\"x\") end\n\
              end\n"));

    gated "an `s == \"\"` guard does not manufacture a length fact" (fun () ->
        (* Distinctness from the empty literal does NOT establish a length —
           there is no injectivity axiom.  Silence here is correct. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn nonempty(s : {String | len(_) > 0}) : Int do 1 end\n\
             \  fn f(s : String) : Int do\n\
             \    if s == \"\" do 0 else nonempty(s) end\n\
             \  end\n\
              end\n")) ]

(* ── Shared predicate-vocabulary foundation ────────────────────────────────
   Task 1 is pure plumbing: it adds the registry without wiring it to
   anything, so these must pass both before AND after. *)
let vocab_suite =
  [ gated "an unrecognized predicate name still compiles (no error)" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn f(n : {Int | totally_bogus_fn(_) > 0}) : Int do n end\n\
             \  fn main() : Int do f(3) end\n\
              end\n"));

    gated "ordinary Int predicates are unaffected" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod M do\n\
             \  fn take_n(n : {Int | _ >= 0}) : Int do n end\n\
             \  fn main() : Int do take_n(-3) end\n\
              end\n"));

    gated "every operator smt_of handles is known vocabulary" (fun () ->
        (* If smt_of gains an operator, add it to predicate_operators too, or
           a predicate using it will draw a spurious "no effect" warning. *)
        List.iter
          (fun op ->
            Alcotest.(check bool)
              (Printf.sprintf "%s is known" op) true
              (March_refinecheck.Refine_check.known_predicate_fn op))
          [ "+"; "-"; "*"; "negate"; "not"; "&&"; "||"
          ; "=="; "!="; "<"; "<="; ">"; ">=" ]);

    gated "an unrecognized predicate name warns" (fun () ->
        Alcotest.(check bool) "warning" true
          (has_refine_warning
             "mod M do\n\
             \  fn f(n : {Int | totally_bogus_fn(_) > 0}) : Int do n end\n\
             \  fn main() : Int do f(3) end\n\
              end\n"));

    gated "a recognized predicate does not warn" (fun () ->
        Alcotest.(check bool) "no warning" false
          (has_refine_warning
             "mod M do\n\
             \  fn f(n : {Int | _ >= 0 && _ < 10}) : Int do n end\n\
             \  fn main() : Int do f(3) end\n\
              end\n"));

    gated "a `len` predicate does not warn" (fun () ->
        Alcotest.(check bool) "no warning" false
          (has_refine_warning
             "mod M do\n\
             \  fn at(xs : List(Int), i : {Int | _ >= 0 && _ < len(xs)}) : Int do i end\n\
             \  fn main() : Int do at([1, 2], 0) end\n\
              end\n"));

    gated "a user @[measure] predicate does not warn" (fun () ->
        Alcotest.(check bool) "no warning" false
          (has_refine_warning
             "mod M do\n\
             \  type Tree = Leaf | Node(Tree, Tree)\n\
             \  @[measure]\n\
             \  fn size(t : Tree) : Int do\n\
             \    match t do\n\
             \      Leaf -> 0\n\
             \      Node(l, r) -> 1 + size(l) + size(r)\n\
             \    end\n\
             \  end\n\
             \  fn get(t : Tree, i : {Int | _ >= 0 && _ < size(t)}) : Int do i end\n\
             \  fn main() : Int do get(Leaf, 0) end\n\
              end\n"));

    gated "an unrecognized predicate is still not an error" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn f(n : {Int | totally_bogus_fn(_) > 0}) : Int do n end\n\
             \  fn main() : Int do f(3) end\n\
              end\n")) ]

(* ── ADT constructor tags ────────────────────────────────────────────────── *)
let adt_suite =
  [ gated "`is_Some` is recognized vocabulary (no warning)" (fun () ->
        Alcotest.(check bool) "no warning" false
          (has_refine_warning
             "mod M do\n\
             \  fn f(o : {Option(Int) | is_Some(_)}) : Int do 1 end\n\
             \  fn main() : Int do f(Some(1)) end\n\
              end\n"));

    gated "a misspelled lowercase `is_some` still warns" (fun () ->
        Alcotest.(check bool) "warning" true
          (has_refine_warning
             "mod M do\n\
             \  fn f(o : {Option(Int) | is_some(_)}) : Int do 1 end\n\
             \  fn main() : Int do f(Some(1)) end\n\
              end\n"));

    gated "unwrap(None) is rejected" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod M do\n\
             \  fn unwrap(o : {Option(Int) | is_Some(_)}) : Int do 0 end\n\
             \  fn main() : Int do unwrap(None) end\n\
              end\n"));

    gated "unwrap(Some(1)) passes" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn unwrap(o : {Option(Int) | is_Some(_)}) : Int do 0 end\n\
             \  fn main() : Int do unwrap(Some(1)) end\n\
              end\n"));

    gated "an unknown Option variable is skipped" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn unwrap(o : {Option(Int) | is_Some(_)}) : Int do 0 end\n\
             \  fn f(x : Option(Int)) : Int do unwrap(x) end\n\
              end\n"));

    gated "a user ADT tester works" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod M do\n\
             \  type Shape = Circle(Int) | Square(Int)\n\
             \  fn area(s : {Shape | is_Circle(_)}) : Int do 0 end\n\
             \  fn main() : Int do area(Square(2)) end\n\
              end\n"));

    gated "unwrap(o) inside a `None ->` arm is rejected" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod M do\n\
             \  fn unwrap(o : {Option(Int) | is_Some(_)}) : Int do 0 end\n\
             \  fn f(x : Option(Int)) : Int do\n\
             \    match x do\n\
             \      None -> unwrap(x)\n\
             \      Some(v) -> v\n\
             \    end\n\
             \  end\n\
              end\n"));

    gated "unwrap(o) inside a `Some(_) ->` arm passes" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn unwrap(o : {Option(Int) | is_Some(_)}) : Int do 0 end\n\
             \  fn f(x : Option(Int)) : Int do\n\
             \    match x do\n\
             \      Some(v) -> unwrap(x)\n\
             \      None -> 0\n\
             \    end\n\
             \  end\n\
              end\n"));

    gated "narrowing does not leak past a rebinding pattern binder" (fun () ->
        (* The INNER arm rebinds `x`, so the outer scrutinee's `None` tag says
           nothing about the inner `x` — which is a `Some` payload here.
           Correct code; the call must not be flagged.  (The call is what makes
           this a real test: an arm body of `0` exercises nothing.) *)
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn unwrap(o : {Option(Int) | is_Some(_)}) : Int do 0 end\n\
             \  fn f(x : Option(Int), y : Option(Int)) : Int do\n\
             \    match x do\n\
             \      None ->\n\
             \        match y do\n\
             \          Some(x) -> unwrap(x)\n\
             \          None -> 0\n\
             \        end\n\
             \      Some(v) -> v\n\
             \    end\n\
             \  end\n\
              end\n"));

    (* ── Path facts must not survive a rebinding of the name they mention ── *)
    gated "a `let` rebinding the scrutinee retires the narrowing" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn unwrap(o : {Option(Int) | is_Some(_)}) : Int do 0 end\n\
             \  fn f(x : Option(Int)) : Int do\n\
             \    match x do\n\
             \      None ->\n\
             \        let x = Some(1)\n\
             \        unwrap(x)\n\
             \      Some(v) -> v\n\
             \    end\n\
             \  end\n\
              end\n"));

    gated "a lambda param rebinding the scrutinee retires the narrowing" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn unwrap(o : {Option(Int) | is_Some(_)}) : Int do 0 end\n\
             \  fn apply(g : (Option(Int)) -> Int) : Int do 0 end\n\
             \  fn f(x : Option(Int)) : Int do\n\
             \    match x do\n\
             \      None -> apply(fn x -> unwrap(x))\n\
             \      Some(v) -> v\n\
             \    end\n\
             \  end\n\
              end\n"));

    gated "a `let?` rebinding the scrutinee retires the narrowing" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn unwrap(o : {Option(Int) | is_Some(_)}) : Int do 0 end\n\
             \  fn mk() : Result(Option(Int), String) do Ok(Some(1)) end\n\
             \  fn f(x : Option(Int)) : Result(Int, String) do\n\
             \    match x do\n\
             \      None ->\n\
             \        let? x = mk()\n\
             \        Ok(unwrap(x))\n\
             \      Some(v) -> Ok(v)\n\
             \    end\n\
             \  end\n\
              end\n"));

    gated "a user ADT `let` rebinding the scrutinee retires the narrowing" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  type Shape = Circle(Int) | Square(Int)\n\
             \  fn area(sh : {Shape | is_Circle(_)}) : Int do 0 end\n\
             \  fn f(s : Shape) : Int do\n\
             \    match s do\n\
             \      Square(n) ->\n\
             \        let s = Circle(1)\n\
             \        area(s)\n\
             \      Circle(n) -> 0\n\
             \    end\n\
             \  end\n\
              end\n"));

    (* A path condition lives in the CALLER's namespace; it must not be
       re-pointed at the callee's actuals just because the caller happens to
       use the same variable name as the callee's refinement binder. *)
    gated "a caller variable sharing the callee's binder name is not confused"
      (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn unwrap(o : {Option(Int) | is_Some(o)}) : Int do 0 end\n\
             \  fn f(o : Option(Int), y : Option(Int)) : Int do\n\
             \    match o do\n\
             \      None -> unwrap(y)\n\
             \      Some(v) -> v\n\
             \    end\n\
             \  end\n\
              end\n"));

    gated "a complex scrutinee expression is skipped" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn unwrap(o : {Option(Int) | is_Some(_)}) : Int do 0 end\n\
             \  fn mk() : Option(Int) do None end\n\
             \  fn f() : Int do\n\
             \    match mk() do\n\
             \      None -> 0\n\
             \      Some(v) -> v\n\
             \    end\n\
             \  end\n\
              end\n")) ]

(* ── Tier 1: relational postconditions ──────────────────────────────────────
   Direct unit tests for the predicate classifier.  These need no solver, so
   they are NOT gated: they exercise pure AST analysis. *)

module RC = March_refinecheck.Refine_check

(* Parse `fn g(<params>) : {Int | <pred>} do 0 end` and hand back the
   refinement's (binder, predicate) so the classifier can be probed directly. *)
let ret_refinement_of (fn_src : string) : string * March_ast.Ast.expr =
  let m = parse (Printf.sprintf "mod M do\n  %s\nend\n" fn_src) in
  let rec find (ds : March_ast.Ast.decl list) =
    match ds with
    | March_ast.Ast.DFn (fd, _) :: _ -> (
      match fd.March_ast.Ast.fn_ret_ty with
      | Some (March_ast.Ast.TyRefine (_, binder, pred)) ->
        ((match binder with Some b -> b.March_ast.Ast.txt | None -> "_"), pred)
      | _ -> Alcotest.fail "function has no return refinement")
    | _ :: rest -> find rest
    | [] -> Alcotest.fail "no function declaration found"
  in
  find m.March_ast.Ast.mod_decls

let classify fn_src params =
  let binder, pred = ret_refinement_of fn_src in
  RC.classify_pred binder params pred

let scope_str = function
  | RC.Closed -> "Closed"
  | RC.Relational ps -> "Relational[" ^ String.concat ";" (List.sort compare ps) ^ "]"
  | RC.Unusable -> "Unusable"

let check_scope name expected actual =
  Alcotest.(check string) name expected (scope_str actual)

let classifier_suite =
  [ Alcotest.test_case "a closed predicate mentions no parameter" `Quick (fun () ->
        check_scope "closed" "Closed"
          (classify "fn g(n : Int) : {Int | _ >= 0} do 0 end" [ "n" ]));

    Alcotest.test_case "a predicate mentioning one parameter is relational" `Quick
      (fun () ->
        check_scope "relational" "Relational[n]"
          (classify "fn g(n : Int) : {Int | _ < n} do 0 end" [ "n" ]));

    Alcotest.test_case "a predicate mentioning two parameters lists both" `Quick
      (fun () ->
        check_scope "relational" "Relational[m;n]"
          (classify "fn g(n : Int, m : Int) : {Int | _ < n + m} do 0 end" [ "n"; "m" ]));

    Alcotest.test_case "a measure applied to a parameter is relational in that parameter"
      `Quick (fun () ->
        (* `len` is the application HEAD — a function name, not a value — so it
           must not itself register as a free name. *)
        check_scope "relational" "Relational[xs]"
          (classify "fn g(xs : List(Int)) : {Int | _ < len(xs)} do 0 end" [ "xs" ]));

    Alcotest.test_case "a predicate mentioning an unknown name is unusable" `Quick
      (fun () ->
        check_scope "unusable" "Unusable"
          (classify "fn g(n : Int) : {Int | _ < q} do 0 end" [ "n" ]));

    (* A field projection is classified by its RECEIVER — the value reference —
       with the field name treated as a selector.  This test previously pinned
       the opposite (`Unusable`, via the conservative catch-all), which meant
       NO record postcondition could ever reach a call site: every one of them
       mentions a field, so `fn mk() : {v : Cfg | v.port >= 1}` was proven at
       its definition and then silently discarded.  [subst_params] has the
       mirror-image arm, so a relational one is rewritten wholly into the
       caller's namespace rather than left half-translated. *)
    Alcotest.test_case "a field projection on a parameter is relational in it" `Quick
      (fun () ->
        check_scope "relational" "Relational[r]"
          (classify "fn g(r : Cfg) : {Int | _ < r.port} do 0 end" [ "r" ]));

    Alcotest.test_case "a field projection on the binder is closed" `Quick (fun () ->
        check_scope "closed" "Closed"
          (classify "fn g(n : Int) : {v : Cfg | v.port >= 1} do { port: 1 } end" [ "n" ]));

    (* The catch-all still rejects genuinely untraversed syntax, and a field
       projection on an UNKNOWN receiver is still unusable — the receiver's own
       classification is what decides. *)
    Alcotest.test_case "a field projection on an unknown name is unusable" `Quick
      (fun () ->
        check_scope "unusable" "Unusable"
          (classify "fn g(n : Int) : {Int | _ < q.port} do 0 end" [ "n" ]))
  ]

(* Integration tests for propagating a relational postcondition to call sites.
   NOTE: `use` and `opaque` are reserved words in March, so the caller here is
   named `usit` and the unanalysable callee `blackbox`. *)
let tier1_suite =
  [ gated "relational postcondition propagates through an inline call" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             {|mod M do
  fn below(n : Int) : {Int | _ < n} do n - 1 end
  fn takepos(k : {Int | _ >= 0}) : Int do k end
  fn usit() : Int do takepos(below(0)) end
end|}));

    gated "relational postcondition propagates through a let" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             {|mod M do
  fn below(n : Int) : {Int | _ < n} do n - 1 end
  fn takepos(k : {Int | _ >= 0}) : Int do k end
  fn usit() : Int do
    let c = below(0)
    takepos(c)
  end
end|}));

    gated "a satisfiable instantiation stays silent" (fun () ->
        (* below(10) < 10 does not contradict >= 0 — it might be 5. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod M do
  fn below(n : Int) : {Int | _ < n} do n - 1 end
  fn takepos(k : {Int | _ >= 0}) : Int do k end
  fn usit() : Int do takepos(below(10)) end
end|}));

    gated "an unknown actual stays silent" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod M do
  fn below(n : Int) : {Int | _ < n} do n - 1 end
  fn takepos(k : {Int | _ >= 0}) : Int do k end
  fn usit(q : Int) : Int do takepos(below(q)) end
end|}));

    gated "simultaneous substitution: an actual naming another formal" (fun () ->
        (* f(m, 1) must instantiate `_ < n + m` as `_ < m + 1`, NOT `_ < 1 + 1`.
           With m unknown the result is unprovable either way, so silence here
           is the correct outcome — this pins that we do not CRASH or invent a
           fact from a sequential rewrite. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod M do
  fn f(n : Int, m : Int) : {Int | _ < n + m} do n + m - 1 end
  fn takepos(k : {Int | _ >= 0}) : Int do k end
  fn usit(m : Int) : Int do takepos(f(m, 1)) end
end|}));

    gated "an unverified relational postcondition does not propagate" (fun () ->
        (* `_ < n` is not provable from an unanalysable body, so the gate clears
           it and callers learn nothing.  The Tier 0 guarantee, inherited. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod M do
  fn blackbox(n : Int) : Int do n end
  fn shady(n : Int) : {Int | _ < n} do blackbox(n) end
  fn takepos(k : {Int | _ >= 0}) : Int do k end
  fn usit() : Int do takepos(shady(0)) end
end|}));

    (* A callee formal `n` whose name equals a CALLER variable that is not the
       actual passed for it.  Substitution must use the actual (`hi`), giving
       `_ < hi` with `hi` unconstrained.  Reading the caller's own `n` instead
       would give `_ < n` with `n <= 0`, contradicting `_ >= 0` and flagging
       correct code — the caller/callee conflation that has produced false
       positives in this subsystem before. *)
    gated "a caller variable sharing a callee formal's name is not conflated"
      (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod M do
  fn below(n : Int) : {Int | _ < n} do n - 1 end
  fn takepos(k : {Int | _ >= 0}) : Int do k end
  fn usit(n : {Int | _ <= 0}, hi : Int) : Int do takepos(below(hi)) end
end|}));

    (* The predicate mentions only the THIRD formal.  These two cases differ
       solely in which actual sits at index 2, so together they pin that the
       formal->actual map is positional: taking the first actual would flag the
       silent case, and ignoring position entirely would miss the loud one. *)
    gated "substitution picks the actual positionally (satisfiable)" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod M do
  fn pick(a : Int, b : Int, hi : Int, c : Int) : {Int | _ < hi} do hi - 1 end
  fn takepos(k : {Int | _ >= 0}) : Int do k end
  fn usit() : Int do takepos(pick(0, 0, 50, 0)) end
end|}));

    gated "substitution picks the actual positionally (violating)" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             {|mod M do
  fn pick(a : Int, b : Int, hi : Int, c : Int) : {Int | _ < hi} do hi - 1 end
  fn takepos(k : {Int | _ >= 0}) : Int do k end
  fn usit() : Int do takepos(pick(50, 50, 0, 50)) end
end|}));

    (* `len` is an application HEAD — a measure, not a value — so it must not be
       rewritten even when a formal shares its name.  Substituting the head would
       turn `len(xs)` into `40(xs)`. *)
    gated "a formal sharing a measure's name does not rewrite the measure"
      (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod M do
  fn odd(len : Int, xs : List(Int)) : {Int | _ < len(xs) + len} do len - 1 end
  fn takepos(k : {Int | _ >= 0}) : Int do k end
  fn usit(ys : List(Int)) : Int do takepos(odd(40, ys)) end
end|}));

    (* postcond_of is consulted for `countdown` from inside `countdown`'s own
       body: confirms neither the gate nor the substitution loops forever. *)
    gated "a recursive relational postcondition terminates" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod M do
  fn countdown(n : {Int | _ >= 0}) : {Int | _ <= n} do
    if n == 0 do 0 else countdown(n - 1) end
  end
  fn takepos(k : {Int | _ >= 0}) : Int do k end
  fn usit(m : {Int | _ >= 0}) : Int do takepos(countdown(m)) end
end|})) ]

(* ── Higher-order refinement checking ──────────────────────────────────────
   Two call shapes [resolve_call] cannot see because it only resolves NAMED
   callees: a call made THROUGH a refined function-typed parameter, and a
   call through a LOCAL ALIAS of a named function.  Most of these cases
   assert SILENCE — the whole risk in this file is a shadowed name leaking an
   outer fact into an inner binding, and only a silence-asserting test can
   catch that. *)
let hof_suite =
  [ gated "a call through a refined callback type is checked" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod M do\n\
             \  fn ap(f : ({Int | _ >= 0}) -> Int) : Int do f(-3) end\n\
              end\n"));

    gated "a valid call through a refined callback type passes" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn ap(f : ({Int | _ >= 0}) -> Int) : Int do f(1) end\n\
              end\n"));

    gated "an unknown argument through a callback type is skipped" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn ap(f : ({Int | _ >= 0}) -> Int, k : Int) : Int do f(k) end\n\
              end\n"));

    gated "an UNREFINED callback type checks nothing" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn ap(f : (Int) -> Int) : Int do f(-3) end\n\
              end\n"));

    gated "a shadowing let retires the callback fact" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn other(n : Int) : Int do n end\n\
             \  fn ap(f : ({Int | _ >= 0}) -> Int) : Int do\n\
             \    let f = other\n\
             \    f(-3)\n\
             \  end\n\
              end\n"));

    gated "a shadowing lambda param retires the callback fact" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn ap(f : ({Int | _ >= 0}) -> Int) : Int do\n\
             \    let h = fn f -> 0\n\
             \    h(1)\n\
             \  end\n\
              end\n"));

    (* ── Task 2: local function aliases ── *)
    gated "a call through a local alias is checked" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod M do\n\
             \  fn takepos(k : {Int | _ >= 0}) : Int do k end\n\
             \  fn probe() : Int do\n\
             \    let g = takepos\n\
             \    g(-3)\n\
             \  end\n\
              end\n"));

    gated "a valid call through a local alias passes" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn takepos(k : {Int | _ >= 0}) : Int do k end\n\
             \  fn probe() : Int do\n\
             \    let g = takepos\n\
             \    g(5)\n\
             \  end\n\
              end\n"));

    gated "an alias to an unrefined function checks nothing" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn plain(k : Int) : Int do k end\n\
             \  fn probe() : Int do\n\
             \    let g = plain\n\
             \    g(-3)\n\
             \  end\n\
              end\n"));

    gated "a rebound alias no longer resolves to the original" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn takepos(k : {Int | _ >= 0}) : Int do k end\n\
             \  fn plain(k : Int) : Int do k end\n\
             \  fn probe() : Int do\n\
             \    let g = takepos\n\
             \    let g = plain\n\
             \    g(-3)\n\
             \  end\n\
              end\n")) ]

(* ── Tier 2: structural induction over recursive functions ─────────────────
   A relational postcondition on a RECURSIVE function (`insert` grows a tree by
   exactly one node) cannot be discharged by Z3 alone — it needs the induction
   hypothesis.  The IH is sound to assume ONLY at a recursive call whose
   argument is structurally smaller than the matched parameter; assuming it
   anywhere else is circular, and — because a propagated postcondition is ADDED
   to the assumption set a call-site VC proves `¬goal` against — an unsound IH
   manufactures FALSE POSITIVES on correct code rather than merely failing.
   Hence three of the four cases below assert SILENCE.

   Note also that under the definite-failure stance, exit-0 at a definition is
   ambiguous between "proved" and "skipped".  The distinguishing observation is
   PROPAGATION: only a proven postcondition survives [gate_unverified_posts] and
   reaches a call site.  That is what the first test measures. *)

(* `insert` adds exactly one node.  `needs_empty` demands `size < 1`, and the
   proven postcondition says the result has size(Leaf) + 1 == 1 — a definite
   violation, but ONLY if the postcondition was actually proven. *)
let tier2_src =
  {|mod P do
  type Tree = Leaf | Node(Tree, Int, Tree)
  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end
  fn insert(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1} do
    match t do
      Leaf -> Node(Leaf, x, Leaf)
      Node(l, v, r) -> Node(insert(l, x), v, r)
    end
  end
  fn needs_empty(t : {Tree | size(t) < 1}) : Int do 0 end
  fn probe() : Int do needs_empty(insert(Leaf, 5)) end
end|}

(* The same definition with no call site: proving a postcondition must never
   make the definition itself report. *)
let tier2_defn_only =
  {|mod P do
  type Tree = Leaf | Node(Tree, Int, Tree)
  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end
  fn insert(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1} do
    match t do
      Leaf -> Node(Leaf, x, Leaf)
      Node(l, v, r) -> Node(insert(l, x), v, r)
    end
  end
end|}

(* SOUNDNESS GATE.  The recursive call passes the WHOLE matched parameter, not a
   component of it, so no induction hypothesis may be assumed.  With an unsound
   IH the Node arm would discharge trivially (assume the goal, prove the goal),
   the postcondition would propagate, and `needs_empty(bad(Leaf, 5))` would be
   reported — a false positive.  This test asserts that does not happen. *)
let tier2_nonstructural =
  {|mod P do
  type Tree = Leaf | Node(Tree, Int, Tree)
  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end
  fn bad(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1} do
    match t do
      Leaf -> Node(Leaf, x, Leaf)
      Node(l, v, r) -> bad(t, x)
    end
  end
  fn needs_empty(t : {Tree | size(t) < 1}) : Int do 0 end
  fn probe() : Int do needs_empty(bad(Leaf, 5)) end
end|}

(* A FALSE relational postcondition.  The IH makes the Node arm go through, but
   the BASE case is `1 == 0 + 2`, which fails — so the postcondition is not
   proven and must not travel.  The definition side stays silent (definite
   failure reports only what can never hold, and this is checked with
   diagnostics suppressed), and the call site learns nothing. *)
let tier2_false_post =
  {|mod P do
  type Tree = Leaf | Node(Tree, Int, Tree)
  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end
  fn ins2(t : Tree, x : Int) : {Tree | size(_) == size(t) + 2} do
    match t do
      Leaf -> Node(Leaf, x, Leaf)
      Node(l, v, r) -> Node(ins2(l, x), v, r)
    end
  end
  fn needs_empty(t : {Tree | size(t) < 1}) : Int do 0 end
  fn probe() : Int do needs_empty(ins2(Leaf, 5)) end
end|}

let tier2_suite =
  [ (* The postcondition is now PROVEN, so it propagates: needs_empty demands
       size < 1 while insert guarantees size == size(Leaf)+1 == 1. *)
    gated "a proven relational postcondition propagates" (fun () ->
        Alcotest.(check bool) "error" true (has_refine_error tier2_src));

    (* `--no-measure-axioms` empties [measure_preamble], and with it
       [measure_preamble_sorts] — which [check_post_induction] requires to
       contain both the return and matched-parameter ADT sorts before it will
       build a VC (a VC naming an undeclared sort makes z3 emit an `(error …)`
       and desynchronise the shared solver channel).  So the flag disables
       Tier 2, exactly as it disables the measure reasoning it is an escape
       hatch from.  Same fixture as the test above, which reports WITH axioms. *)
    gated "--no-measure-axioms disables Tier 2 induction" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_no_axioms tier2_src));

    (* Definition-side must stay clean — proving it must not flag it. *)
    gated "the recursive definition itself reports nothing" (fun () ->
        Alcotest.(check bool) "no error" false (has_refine_error tier2_defn_only));

    (* Soundness gate: a recursive call on a NON-smaller argument must not get
       the IH, or the checker could prove anything. *)
    gated "a non-structural recursive call gets no induction hypothesis" (fun () ->
        Alcotest.(check bool) "no error" false (has_refine_error tier2_nonstructural));

    (* A FALSE relational postcondition must remain unproven and must not
       propagate — the definition side stays silent (definite-failure), and the
       call site learns nothing. *)
    gated "a false relational postcondition does not propagate" (fun () ->
        Alcotest.(check bool) "no error" false (has_refine_error tier2_false_post));

    (* ── Task 2: other shapes ───────────────────────────────────────────── *)

    (* A user @[measure] over the BUILT-IN List ADT, not a user type.  Nothing
       about the induction is tree-specific. *)
    gated "a measure over List propagates" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             {|mod P do
  @[measure]
  fn llen(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(_, t) -> 1 + llen(t)
    end
  end
  fn push(xs : List(Int), x : Int) : {List(Int) | llen(_) == llen(xs) + 1} do
    match xs do
      Nil -> Cons(x, Nil)
      Cons(h, t) -> Cons(h, push(t, x))
    end
  end
  fn needs_empty(ys : {List(Int) | llen(ys) < 1}) : Int do 0 end
  fn probe() : Int do needs_empty(push(Nil, 5)) end
end|}));

    (* FRONTIER, pinned deliberately: the BUILT-IN `len` is not an axiomatised
       measure ([is_axiom_measure] covers only user `@[measure]`s), so it has no
       recursion equations for the induction to reduce through and the
       postcondition stays unproven.  Silence, not a wrong answer.  Declaring a
       user measure over the same list (above) is the workaround. *)
    gated "the built-in `len` does not yet carry Tier 2 induction" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod P do
  fn push(xs : List(Int), x : Int) : {List(Int) | len(_) == len(xs) + 1} do
    match xs do
      Nil -> Cons(x, Nil)
      Cons(h, t) -> Cons(h, push(t, x))
    end
  end
  fn needs_empty(ys : {List(Int) | len(ys) < 1}) : Int do 0 end
  fn probe() : Int do needs_empty(push(Nil, 5)) end
end|}));

    (* The recursion descends into the SECOND recursive component.  The
       structural set is computed from the pattern, not from a position. *)
    gated "recursion on the second component propagates" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             {|mod P do
  type Tree = Leaf | Node(Tree, Int, Tree)
  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end
  fn insr(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1} do
    match t do
      Leaf -> Node(Leaf, x, Leaf)
      Node(l, v, r) -> Node(l, v, insr(r, x))
    end
  end
  fn needs_empty(t : {Tree | size(t) < 1}) : Int do 0 end
  fn probe() : Int do needs_empty(insr(Leaf, 5)) end
end|}));

    (* MUTUAL recursion is NOT supported: the IH is minted only for a call to
       the function's OWN name, so `f`'s call to `g` reflects to nothing and
       neither postcondition is proven.  Asserted as silence and documented in
       specs/lang/refinement-types.md rather than made to work. *)
    gated "mutual recursion gets no induction hypothesis (silent)" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod P do
  type T = A | B(T)
  @[measure]
  fn sz(t : T) : Int do
    match t do
      A -> 0
      B(x) -> 1 + sz(x)
    end
  end
  fn f(t : T) : {T | sz(_) == sz(t) + 1} do
    match t do
      A -> B(A)
      B(x) -> B(g(x))
    end
  end
  fn g(t : T) : {T | sz(_) == sz(t) + 1} do
    match t do
      A -> B(A)
      B(x) -> B(f(x))
    end
  end
  fn needs_empty(t : {T | sz(t) < 1}) : Int do 0 end
  fn probe() : Int do needs_empty(f(A)) end
end|}));

    (* A CLOSED (non-relational) INT postcondition on a recursive function goes
       down the pre-existing Tier 0 path, which Tier 2 does not touch:
       [return_refine_ext] still claims an Int return, so [check_post_induction]
       is never consulted.  The behaviour is unchanged — and it is SILENCE,
       because the recursive tail `countdown(n - 1)` is not reflectable, so the
       postcondition is not proven and does not propagate.  Pinned so a future
       widening of Tier 2 onto Int returns cannot change it unnoticed. *)
    gated "a closed Int postcondition on a recursive function is unaffected"
      (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod M do
  fn countdown(n : Int) : {Int | _ >= 0} do
    if n <= 0 do 0 else countdown(n - 1) end
  end
  fn needsneg(k : {Int | _ < 0}) : Int do k end
  fn probe() : Int do needsneg(countdown(5)) end
end|}));

    (* A CLOSED postcondition over an ADT return, by contrast, IS newly proven
       by the induction (the base case gives size >= 1 outright, the step needs
       only the measure's non-negativity), and so propagates. *)
    gated "a closed ADT postcondition on a recursive function propagates"
      (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             {|mod P do
  type Tree = Leaf | Node(Tree, Int, Tree)
  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end
  fn ins(t : Tree, x : Int) : {Tree | size(_) >= 1} do
    match t do
      Leaf -> Node(Leaf, x, Leaf)
      Node(l, v, r) -> Node(ins(l, x), v, r)
    end
  end
  fn needs_empty(t : {Tree | size(t) < 1}) : Int do 0 end
  fn probe() : Int do needs_empty(ins(Leaf, 5)) end
end|}));

    (* A recursive function with NO postcondition is untouched. *)
    gated "a recursive function without a postcondition is unaffected" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod P do
  type Tree = Leaf | Node(Tree, Int, Tree)
  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end
  fn ins(t : Tree, x : Int) : Tree do
    match t do
      Leaf -> Node(Leaf, x, Leaf)
      Node(l, v, r) -> Node(ins(l, x), v, r)
    end
  end
  fn needs_empty(t : {Tree | size(t) < 1}) : Int do 0 end
  fn probe() : Int do needs_empty(ins(Leaf, 5)) end
end|}));

    (* ── Task 2: adversarial silence.  Every program below is CORRECT at
       runtime, so any diagnostic is a false positive. ──────────────────── *)

    (* An accumulator that GROWS across the recursive call.  The induction is on
       `t` alone, so the IH is universally quantified over `acc`; the structural
       gate must look at the MATCHED parameter's position, not at every
       argument, or this correct function would go unproven and (worse) a looser
       gate would be needed to rescue it. *)
    gated "a growing accumulator does not disturb the induction" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod P do
  type Tree = Leaf | Node(Tree, Int, Tree)
  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end
  fn addall(t : Tree, acc : Int) : {Tree | size(_) == size(t) + 1} do
    match t do
      Leaf -> Node(Leaf, acc, Leaf)
      Node(l, v, r) -> Node(addall(l, acc + 1), v, r)
    end
  end
  fn needs_pos(t : {Tree | size(t) >= 1}) : Int do 0 end
  fn probe() : Int do needs_pos(addall(Leaf, 0)) end
end|}));

    (* The recursive call is hidden inside a lambda / behind a nested match.
       Neither is reflectable, so both stay unproven — silence, not a report. *)
    gated "a recursive call inside a lambda or nested match stays silent"
      (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod P do
  type Tree = Leaf | Node(Tree, Int, Tree)
  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end
  fn walk(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1} do
    match t do
      Leaf -> Node(Leaf, x, Leaf)
      Node(l, v, r) ->
        let f = fn z -> walk(z, x)
        Node(f(l), v, r)
    end
  end
  fn nest(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1} do
    match t do
      Leaf -> Node(Leaf, x, Leaf)
      Node(l, v, r) ->
        match r do
          Leaf -> Node(nest(l, x), v, Leaf)
          Node(a, b, c) -> Node(nest(l, x), v, r)
        end
    end
  end
  fn needs_pos(t : {Tree | size(t) >= 1}) : Int do 0 end
  fn probe() : Int do needs_pos(walk(Leaf, 1)) + needs_pos(nest(Leaf, 1)) end
end|}));

    (* A TRUE postcondition the IH alone cannot discharge: the inner match's
       pattern equation is not built, so the arm returns unknown.  Unproven is
       fine; reporting it would not be. *)
    gated "a true but unprovable postcondition stays silent" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod P do
  type Tree = Leaf | Node(Tree, Int, Tree)
  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end
  fn norm(t : Tree) : {Tree | size(_) == size(t)} do
    match t do
      Leaf -> Leaf
      Node(l, v, r) ->
        match l do
          Leaf -> Node(Leaf, v, norm(r))
          Node(a, b, c) -> Node(norm(l), v, norm(r))
        end
    end
  end
  fn needs_empty(t : {Tree | size(t) < 1}) : Int do 0 end
  fn probe() : Int do needs_empty(norm(Leaf)) end
end|}));

    (* Tier 2 alongside records, strings, ADT testers, callbacks and Tier 1
       relational propagation, every line correct. *)
    gated "Tier 2 composes with records, strings, ADTs and callbacks" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod P do
  type Tree = Leaf | Node(Tree, Int, Tree)
  type Cfg = { port : Int, name : String }
  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end
  fn insert(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1} do
    match t do
      Leaf -> Node(Leaf, x, Leaf)
      Node(l, v, r) -> Node(insert(l, x), v, r)
    end
  end
  fn below(hi : Int) : {Int | _ < hi} do hi - 1 end
  fn takelt(k : {Int | _ < 100}) : Int do k end
  fn takepos(n : {Int | _ >= 0}) : Int do n end
  fn cfg_ok(c : {Cfg | c.port >= 1}) : Int do c.port end
  fn nonempty(s : {String | len(s) > 0}) : Int do string_length(s) end
  fn unwrap(o : {Option(Int) | is_Some(o)}) : Int do
    match o do
      Some(v) -> v
      None -> 0
    end
  end
  fn apply_cb(f : ({Int | _ >= 0}) -> Int) : Int do f(7) end
  fn needs_pos(t : {Tree | size(t) >= 1}) : Int do 0 end
  fn main2() : Int do
    let a = needs_pos(insert(Leaf, 5))
    let b = takelt(below(100))
    let c = takepos(3)
    let d = cfg_ok({ port: 8080, name: "svc" })
    let e = nonempty("hello")
    let g = unwrap(Some(9))
    let h = apply_cb(fn z -> z)
    a + b + c + d + e + g + h
  end
end|})) ]

(* ── A1: callee resolution obeys the shadow discipline ─────────────────────
   [resolve_call] matches a call's function name against the GLOBAL definition
   table.  That table is a fact channel exactly like [scope]/[path]/[recenv]/
   [cbenv] — "the name `f` denotes this contract" — so every binding construct
   must retire a name it rebinds here too.  A local binder that happens to
   reuse a refined global's name otherwise gets its calls checked against a
   contract that never runs: a FALSE POSITIVE.

   Each case below asserts SILENCE.  Each is paired with a CONTROL that
   renames the local away from the collision, so the global really is called
   and the violation really is reported — without the control a test could
   pass by the checker having gone blind. *)
let shadow_src body =
  Printf.sprintf "mod S do\n  fn takepos(k : {Int | _ >= 0}) : Int do k end\n%s\nend\n" body

let shadow_suite =
  [ gated "a `let`-bound local shadows a refined global" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (shadow_src
                "  fn probe() : Int do\n\
                \    let takepos = fn n -> n\n\
                \    takepos(-3)\n\
                \  end")));

    gated "control: `let` renamed away still reports" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (shadow_src
                "  fn probe() : Int do\n\
                \    let other = fn n -> n\n\
                \    takepos(-3)\n\
                \  end")));

    gated "a `let?` binder shadows a refined global" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (shadow_src
                "  fn srcf() : Result((Int) -> Int, String) do Ok(fn n -> n) end\n\
                \  fn probe() : Result(Int, String) do\n\
                \    let? takepos = srcf()\n\
                \    Ok(takepos(-3))\n\
                \  end")));

    gated "control: `let?` renamed away still reports" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (shadow_src
                "  fn srcf() : Result((Int) -> Int, String) do Ok(fn n -> n) end\n\
                \  fn probe() : Result(Int, String) do\n\
                \    let? other = srcf()\n\
                \    Ok(takepos(-3))\n\
                \  end")));

    gated "a lambda parameter shadows a refined global" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (shadow_src
                "  fn probe() : Int do\n\
                \    let f = fn takepos -> takepos(-3)\n\
                \    f(fn n -> n)\n\
                \  end")));

    gated "control: lambda parameter renamed away still reports" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (shadow_src
                "  fn probe() : Int do\n\
                \    let f = fn other -> takepos(-3)\n\
                \    f(0)\n\
                \  end")));

    gated "a local-`fn` parameter shadows a refined global" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (shadow_src
                "  fn probe() : Int do\n\
                \    fn inner(takepos : (Int) -> Int) : Int do takepos(-3) end\n\
                \    inner(fn n -> n)\n\
                \  end")));

    gated "control: local-`fn` parameter renamed away still reports" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (shadow_src
                "  fn probe() : Int do\n\
                \    fn inner(other : (Int) -> Int) : Int do takepos(-3) end\n\
                \    inner(fn n -> n)\n\
                \  end")));

    (* The local `fn`'s own NAME, not its parameters: a block-level `fn` is a
       SIBLING statement, so the name must be retired for what follows it. *)
    gated "a local-`fn` name shadows a refined global" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (shadow_src
                "  fn probe() : Int do\n\
                \    fn takepos(n : Int) : Int do n end\n\
                \    takepos(-3)\n\
                \  end")));

    gated "a `match` arm binder shadows a refined global" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (shadow_src
                "  fn probe(o : Option((Int) -> Int)) : Int do\n\
                \    match o do\n\
                \      Some(takepos) -> takepos(-3)\n\
                \      None -> 0\n\
                \    end\n\
                \  end")));

    gated "control: `match` binder renamed away still reports" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (shadow_src
                "  fn probe(o : Option((Int) -> Int)) : Int do\n\
                \    match o do\n\
                \      Some(other) -> takepos(-3)\n\
                \      None -> 0\n\
                \    end\n\
                \  end")));

    gated "a function parameter shadows a refined global" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (shadow_src "  fn probe(takepos : (Int) -> Int) : Int do takepos(-3) end")));

    gated "control: function parameter renamed away still reports" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (shadow_src "  fn probe(other : (Int) -> Int) : Int do takepos(-3) end")))
  ]

(* ── B1: `size(_)` and `size(v)` are the SAME predicate ────────────────────
   The anonymous binder is the DOCUMENTED idiom (`{Int | _ >= 0}` is the form
   the reference teaches), so a gap that only affects `_` matters more than
   ordinary incompleteness: the natural spelling silently checks nothing while
   the named one works.

   In MEASURE-APPLICATION position `_` used to be emitted verbatim as an SMT
   symbol — and `_` is a RESERVED SMT-LIB token, so z3 answered `(error …)`
   and the predicate was never decided.  Every case below is asserted as a
   PAIR: the two spellings must agree, whatever the verdict is. *)
let b1_src body =
  Printf.sprintf
    "mod B do\n\
    \  type Tree = Leaf | Node(Tree, Int, Tree)\n\
    \  @[measure]\n\
    \  fn size(t : Tree) : Int do\n\
    \    match t do\n\
    \      Leaf -> 0\n\
    \      Node(l, _, r) -> 1 + size(l) + size(r)\n\
    \    end\n\
    \  end\n\
     %s\n\
     end\n"
    body

(* [both] runs the same program in both spellings and asserts one verdict. *)
let b1_pair name ~expect anon named =
  gated name (fun () ->
      Alcotest.(check bool) "anonymous `_`" expect (has_refine_error (b1_src anon));
      Alcotest.(check bool) "named binder" expect (has_refine_error (b1_src named)))

let b1_suite =
  [ (* A violating call: `size` is a measure, hence always >= 0, so `size < 0`
       can never hold.  Both spellings must report it. *)
    b1_pair "violating measure call: both spellings report" ~expect:true
      "  fn need(t : {Tree | size(_) < 0}) : Int do 0 end\n\
      \  fn probe() : Int do need(Leaf) end"
      "  fn need(t : {v : Tree | size(v) < 0}) : Int do 0 end\n\
      \  fn probe() : Int do need(Leaf) end";

    (* A satisfiable call: `size >= 0` always holds — silence, both ways. *)
    b1_pair "satisfiable measure call: both spellings stay silent" ~expect:false
      "  fn need(t : {Tree | size(_) >= 0}) : Int do 0 end\n\
      \  fn probe() : Int do need(Node(Leaf, 1, Leaf)) end"
      "  fn need(t : {v : Tree | size(v) >= 0}) : Int do 0 end\n\
      \  fn probe() : Int do need(Node(Leaf, 1, Leaf)) end";

    (* An UNKNOWN argument settles nothing in either direction: the definite
       failure stance skips it.  This is the negative-space guard — the fix
       must not start guessing about opaque values. *)
    b1_pair "unknown argument: both spellings stay silent" ~expect:false
      "  fn need(t : {Tree | size(_) > 3}) : Int do 0 end\n\
      \  fn probe(u : Tree) : Int do need(u) end"
      "  fn need(t : {v : Tree | size(v) > 3}) : Int do 0 end\n\
      \  fn probe(u : Tree) : Int do need(u) end";

    (* `len` over a list — the measure path with no axioms. *)
    b1_pair "list `len` measure: both spellings stay silent" ~expect:false
      "  fn needl(xs : {List(Int) | len(_) >= 0}) : Int do 0 end\n\
      \  fn probe() : Int do needl([1, 2]) end"
      "  fn needl(xs : {v : List(Int) | len(v) >= 0}) : Int do 0 end\n\
      \  fn probe() : Int do needl([1, 2]) end";

    b1_pair "list `len` on an opaque list: both spellings stay silent" ~expect:false
      "  fn needl(xs : {List(Int) | len(_) >= 3}) : Int do 0 end\n\
      \  fn probe(ys : List(Int)) : Int do needl(ys) end"
      "  fn needl(xs : {v : List(Int) | len(v) >= 3}) : Int do 0 end\n\
      \  fn probe(ys : List(Int)) : Int do needl(ys) end"
  ]

(* ── B2: a record-returning postcondition reaches the call site ────────────
   Int, String and variant-ADT postconditions all propagated; only the record
   shape was dropped, so `needLow(mk())` was silently skipped while the
   identically-shaped Int version was caught.  Two things had to change: the
   predicate classifier had to stop reading a field projection as unusable
   syntax, and [record_self] had to learn the call shape.

   The gate is NOT bypassed: [gate_unverified_posts] still clears [ret] on
   every postcondition the definition side did not PROVE, so an unproven one
   must stay put — that is the first negative test below.  The remaining ones
   assert that the newly-propagated fact is retired by each binding form, each
   with a control confirming it would otherwise have been reported. *)
let b2_cfg body =
  Printf.sprintf
    "mod T do\n\
    \  type Cfg = { port : Int }\n\
    \  fn mk() : {v : Cfg | v.port >= 1} do { port: 8080 } end\n\
    \  fn needLow(c : {v : Cfg | v.port <= 0}) : Int do 0 end\n\
     %s\n\
     end\n"
    body

let b2_suite =
  [ gated "a record postcondition propagates through a direct call" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error (b2_cfg "  fn probe() : Int do needLow(mk()) end")));

    gated "a record postcondition propagates through a `let`" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (b2_cfg
                "  fn probe() : Int do\n\
                \    let c = mk()\n\
                \    needLow(c)\n\
                \  end")));

    (* THE GATE.  `mk_bad`'s body cannot establish `v.port >= 1` (x is
       unknown), so the postcondition is never proven and must not travel.
       Bypassing the gate here would turn a legal program into an error. *)
    gated "an UNPROVEN record postcondition does not propagate" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod T do
  type Cfg = { port : Int }
  fn mk_bad(x : Int) : {v : Cfg | v.port >= 1} do { port: x } end
  fn needLow(c : {v : Cfg | v.port <= 0}) : Int do 0 end
  fn probe(y : Int) : Int do needLow(mk_bad(y)) end
end|}));

    gated "a record postcondition that SATISFIES the precondition is silent" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod T do
  type Cfg = { port : Int }
  fn mk() : {v : Cfg | v.port >= 1} do { port: 8080 } end
  fn needHigh(c : {v : Cfg | v.port >= 1}) : Int do 0 end
  fn probe() : Int do needHigh(mk()) end
end|}));

    gated "an opaque record in the newly-checked position stays silent" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod T do
  type Cfg = { port : Int }
  fn needHigh(c : {v : Cfg | v.port >= 1}) : Int do 0 end
  fn probe(d : Cfg) : Int do needHigh(d) end
end|}));

    (* Retirement, one per binding form.  In each, the inner `c` is a
       DIFFERENT, unknown record; carrying mk()'s postcondition onto it would
       be a false positive.  The paired control renames the inner binder to
       `e`, so the fact survives and the violation IS reported — without it
       these could pass by the checker having gone blind. *)
    gated "a re-`let` retires the propagated record fact" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (b2_cfg
                "  fn probe(d : Cfg) : Int do\n\
                \    let c = mk()\n\
                \    let c = d\n\
                \    needLow(c)\n\
                \  end")));

    gated "a lambda parameter retires the propagated record fact" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (b2_cfg
                "  fn probe(d : Cfg) : Int do\n\
                \    let c = mk()\n\
                \    let f = fn c -> needLow(c)\n\
                \    f(d)\n\
                \  end")));

    gated "control: lambda parameter renamed away still reports" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (b2_cfg
                "  fn probe(d : Cfg) : Int do\n\
                \    let c = mk()\n\
                \    let f = fn e -> needLow(c)\n\
                \    f(d)\n\
                \  end")));

    gated "a `match` binder retires the propagated record fact" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (b2_cfg
                "  fn probe(o : Option(Cfg)) : Int do\n\
                \    let c = mk()\n\
                \    match o do\n\
                \      Some(c) -> needLow(c)\n\
                \      None -> 0\n\
                \    end\n\
                \  end")));

    gated "control: `match` binder renamed away still reports" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (b2_cfg
                "  fn probe(o : Option(Cfg)) : Int do\n\
                \    let c = mk()\n\
                \    match o do\n\
                \      Some(e) -> needLow(c)\n\
                \      None -> 0\n\
                \    end\n\
                \  end")));

    gated "a local-`fn` parameter retires the propagated record fact" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (b2_cfg
                "  fn probe(d : Cfg) : Int do\n\
                \    let c = mk()\n\
                \    fn inner(c : Cfg) : Int do needLow(c) end\n\
                \    inner(d)\n\
                \  end")));

    gated "control: local-`fn` parameter renamed away still reports" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (b2_cfg
                "  fn probe(d : Cfg) : Int do\n\
                \    let c = mk()\n\
                \    fn inner(e : Cfg) : Int do needLow(c) end\n\
                \    inner(d)\n\
                \  end")));

    gated "a `let?` binder retires the propagated record fact" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             (b2_cfg
                "  fn src() : Result(Cfg, String) do Err(\"x\") end\n\
                \  fn probe() : Result(Int, String) do\n\
                \    let c = mk()\n\
                \    let? c = src()\n\
                \    Ok(needLow(c))\n\
                \  end")));

    gated "control: `let?` binder renamed away still reports" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             (b2_cfg
                "  fn src() : Result(Cfg, String) do Err(\"x\") end\n\
                \  fn probe() : Result(Int, String) do\n\
                \    let c = mk()\n\
                \    let? e = src()\n\
                \    Ok(needLow(c))\n\
                \  end")));

    (* A RELATIONAL record postcondition over an opaque actual proves nothing
       about the caller's value, so it must not decide the call either way. *)
    gated "a relational record postcondition on an opaque actual is silent" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod T do
  type Cfg = { port : Int }
  fn bump(c : Cfg) : {v : Cfg | v.port >= c.port} do c end
  fn needLow(c : {v : Cfg | v.port <= 0}) : Int do 0 end
  fn probe(d : Cfg) : Int do needLow(bump(d)) end
end|}));

    (* Records + variant ADTs + strings + a relational postcondition, all
       correct: the combination must stay entirely silent. *)
    gated "records + ADTs + strings + relational postcondition: all silent" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod T do
  type Cfg = { port : Int, name : String }
  type Tag = Live | Dead
  fn bump(c : Cfg) : {v : Cfg | v.port >= c.port} do c end
  fn needHigh(c : {v : Cfg | v.port >= 1}) : Int do 0 end
  fn nonempty(s : {String | len(_) >= 1}) : Int do 0 end
  fn live(t : {v : Tag | is_Live(v)}) : Int do 0 end
  fn probe(base : Cfg) : Int do
    let b = bump(base)
    needHigh(b) + nonempty("hello") + live(Live)
  end
end|}))
  ]

(* ── Bool refinements ──────────────────────────────────────────────────────
   `{Bool | _ == true}` used to parse, type-check and check NOTHING.  These pin
   both halves of the contract: a definite violation reports, and everything
   the checker cannot settle (an unknown Bool) stays silent. *)
let bool_suite =
  [ gated "a Bool precondition rejects the wrong literal" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod M do\n\
             \  fn needTrue(b : {Bool | _ == true}) : Int do 1 end\n\
             \  fn v() : Int do needTrue(false) end\n\
              end\n"));

    gated "a Bool precondition accepts the right literal" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn needTrue(b : {Bool | _ == true}) : Int do 1 end\n\
             \  fn v() : Int do needTrue(true) end\n\
              end\n"));

    gated "an unknown Bool is skipped" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn needTrue(b : {Bool | _ == true}) : Int do 1 end\n\
             \  fn v(k : Bool) : Int do needTrue(k) end\n\
              end\n"));

    gated "a Bool postcondition propagates" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod M do\n\
             \  fn always_false() : {Bool | _ == false} do false end\n\
             \  fn needTrue(b : {Bool | _ == true}) : Int do 1 end\n\
             \  fn v() : Int do needTrue(always_false()) end\n\
              end\n"))
  ]

(* ── Float refinements ─────────────────────────────────────────────────────
   Discharged through Z3's BIT-PRECISE FloatingPoint theory (`Float64`,
   `fp.geq`, `fp.eq`), never through `Real`.  Over reals trichotomy makes
   `¬(x >= 0) ∧ ¬(x <= 0)` unsatisfiable, so a reals encoding would conclude
   "this can never hold" and report a violation on correct code; over floats it
   is satisfiable, witnessed by NaN.  The NaN case below pins that. *)
let float_suite =
  [ gated "a Float precondition rejects a violating literal" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod M do\n\
             \  fn sqrtish(x : {Float | _ >= 0.0}) : Float do x end\n\
             \  fn v() : Float do sqrtish(0.0 -. 1.0) end\n\
              end\n"));

    gated "a Float precondition accepts a satisfying literal" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn sqrtish(x : {Float | _ >= 0.0}) : Float do x end\n\
             \  fn v() : Float do sqrtish(4.0) end\n\
              end\n"));

    gated "an unknown Float is skipped" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn sqrtish(x : {Float | _ >= 0.0}) : Float do x end\n\
             \  fn v(k : Float) : Float do sqrtish(k) end\n\
              end\n"));

    gated "a non-zero Float divisor contract rejects 0.0" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod M do\n\
             \  fn nonzero(d : {Float | _ != 0.0}) : Float do d end\n\
             \  fn v() : Float do nonzero(0.0) end\n\
              end\n"));

    gated "float arithmetic in a predicate is skipped, not guessed" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn f(x : {Float | _ +. 1.0 > 0.0}) : Float do x end\n\
             \  fn v() : Float do f(0.0 -. 100.0) end\n\
              end\n"))
  ]

(* ── Measure aliases: `List.length` IS the `len` measure ───────────────────
   These use [has_refine_error_d] (desugared) because a qualified call is an
   `EField` chain until desugar flattens it to a dotted `EVar` — which is what
   the compiler feeds refine_check in production.

   The load-bearing case is the CONTRADICTORY guard.  The "guard discharges"
   case was already silent before the alias existed — because the obligation
   was SKIPPED, which from outside is indistinguishable from proved.  Only a
   guard that must FIRE proves the two symbols actually meet. *)
let length_alias_suite =
  [ gated "a List.length guard discharges a len obligation" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod L1 do
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) > 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}));

    gated "a contradictory List.length guard IS a violation" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error_d
             {|
mod L2 do
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) == 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}));

    gated "an unguarded unknown list stays silent" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod L3 do
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do head(ys) end
  fn main() : Int do go([1]) end
end|}));

    (* The alias keys on a SPELLING, and a program may define its own
       `List.length` — which wins at runtime.  Here it is constantly 99, so the
       `== 0` branch is DEAD and `head` is never called; the program cannot
       violate anything.  Aliasing regardless made the checker report a
       violation on correct code — a wrong fact in the assumption set makes
       `discharge(¬goal)` succeed.  Silence here is the whole point, so it is
       load-bearing that the contradictory-guard case above still FIRES: that
       pair is what separates "the gate works" from "the gate killed the
       feature". *)
    gated "a user-defined List.length is NOT aliased" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod Q do
  mod List do
    fn length(xs : List(Int)) : Int do 99 end
  end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) == 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}));

    (* ── The same competing definition in every OTHER declaration form ─────
       The gate above once matched `A.DFn` alone and ended its walk in a
       wildcard, so the three shapes below were invisible: the alias stayed on,
       the dead `== 0` branch was treated as reachable, and correct code was
       reported.  That is a false positive, the one error this pass must never
       make.  Each of these is the `mod Q` case reworded — silence is required,
       and it is the CONTRADICTORY-guard case above (which must still fire)
       that proves the fix suppressed a wrong fact rather than the feature. *)
    gated "a user-defined List.length as a module-level `let` is NOT aliased" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod QLet do
  mod List do
    let length = fn xs -> 99
  end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) == 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}));

    gated "an extern-declared List.length is NOT aliased" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod QExt do
  mod List do
    needs Ffi
    extern "c" : Cap(Ffi) do
      fn length(xs: List(Int)) : Int = "march_qext_length"
    end
  end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) == 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}));

    (* The ENTRY module's own declarations are top-level, not a `DMod` — and
       bin/main.ml strips the stdlib's `DMod List` whenever the entry module
       shadows it — so `mod List do fn length` defines `List.length` with
       nothing nested for the walk to see.  The gate now starts its walk with
       `in_mod = true` when the enclosing module's own name matches.

       HONESTY NOTE: unlike its four neighbours, this case passes against the
       PRE-fix gate too, so it does not by itself discriminate the hole — a
       string-parsed fixture has no stdlib prepended, and the discriminating
       shape needs bin/main.ml's prepend-and-strip.  It is kept because the
       property it asserts (silence) is the one that must hold, not because it
       is a witness. *)
    gated "an entry module named List defining `length` is NOT aliased" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod List do
  fn length(xs : List(Int)) : Int do 99 end
  mod Inner do
    fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
    fn go(ys : List(Int)) : Int do
      if List.length(ys) == 0 do head(ys) else 0 end
    end
  end
  fn main() : Int do Inner.go([1]) end
end|}));

    (* Rebinding the bare segment `List` withdraws the alias too, whichever
       selector form does it — `use X.List` was handled, the three below were
       not. *)
    gated "`import X.{List}` withdraws the alias" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod QIN do
  import Shim.{List}
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) == 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}));

    gated "a glob `import X` withdraws the alias" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod QGlob do
  import Shim
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) == 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}));

    (* ── The ENABLING branch ───────────────────────────────────────────────
       Every case above reaches its verdict WITHOUT a `List.length` definition
       in scope at all, i.e. via the gate's "no defs -> allow" path.  None of
       them can tell whether the gate's stdlib-identity test works, which is
       how a revision that never recognised an installed stdlib (`share/march`
       rather than `stdlib/`) passed the whole suite while the feature was dead
       in the shipped compiler.

       These two are the same program with a real `mod List do fn length`
       present, differing ONLY in whether the caller declares that file to be
       the standard library.  Together they pin both directions of the
       identity test. *)
    (let src =
       {|
mod S do
  mod List do
    fn length(xs : List(Int)) : Int do 0 end
  end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) == 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}
     in
     let file = "/opt/march/share/march/list.march" in
     gated "the alias APPLIES to a List.length the caller calls stdlib" (fun () ->
         (* Note the directory is `share/march`, an installed layout with no
            path segment named `stdlib` — identity comes from the caller, not
            from the shape of the path. *)
         Alcotest.(check bool) "error" true
           (has_refine_error_from ~stdlib_files:[ file ] ~file src)));

    (let src =
       {|
mod S do
  mod List do
    fn length(xs : List(Int)) : Int do 0 end
  end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) == 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}
     in
     gated "…and NOT to the same List.length from any other file" (fun () ->
         Alcotest.(check bool) "no error" false
           (has_refine_error_from ~stdlib_files:[ "/opt/march/share/march/list.march" ]
              ~file:"/home/u/proj/stdlib/list.march" src)))
  ]

(* ── Measure aliases, string side: BYTE length only ────────────────────────
   `len` over a String reflects to `($strlen t)`, whose meaning is pinned in
   BYTES by the string-literal axiom (which uses OCaml `String.length`).  So
   only byte-valued spellings may be aliased to it.

   As on the list side, the load-bearing case is the CONTRADICTORY guard: the
   "guard discharges" case was already silent before the alias existed, because
   the obligation was SKIPPED, which from outside is indistinguishable from
   proved.  Desugared throughout — `String.byte_size(t)` is an `EField` chain
   until desugar flattens it to a dotted `EVar`. *)
let string_alias_suite =
  [ gated "a String.byte_size guard discharges a String len obligation" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod S1 do
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if String.byte_size(t) > 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}));

    gated "a contradictory String.byte_size guard IS a violation" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error_d
             {|
mod S2 do
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if String.byte_size(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}));

    (* The builtin `String.byte_size` forwards to, in its own right. *)
    gated "a contradictory string_byte_length guard IS a violation" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error_d
             {|
mod S2b do
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if string_byte_length(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}));

    (* `string_length` is NOT aliased.  It happens to be byte length today —
       llvm_builtins lowers it to the same `march_string_byte_length` C symbol
       — so this is an abstention on an ambiguous NAME, not a claim that the
       two differ.  Silence is what the abstention looks like from outside; if
       the abstention is ever revisited, revisit this test with it. *)
    gated "string_length is not aliased to the byte measure" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod S3 do
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if string_length(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}));

    (* Codepoint counts must never reach `$strlen`: "é" is 1 codepoint and 2
       bytes, so aliasing one would assert a falsehood about the other. *)
    gated "String.codepoint_count is not aliased to the byte measure" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod S4 do
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if String.codepoint_count(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}));

    (* ── The shadowing gate, both directions ───────────────────────────────
       A program may define its own `mod String do fn byte_size`, which wins at
       runtime.  Here it is constantly 99, so the `== 0` branch is DEAD and
       `slug` is never called: the program cannot violate anything, and a
       report would be a false positive on correct code. *)
    gated "a user-defined String.byte_size is NOT aliased" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod QS do
  mod String do
    fn byte_size(s : String) : Int do 99 end
  end
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if String.byte_size(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}));

    (* The same competing definition in the other declaration forms — the
       `A.DFn`-only hole, string side.  See the list-side comment. *)
    gated "a user-defined String.byte_size as a module-level `let` is NOT aliased"
      (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod QSLet do
  mod String do
    let byte_size = fn s -> 99
  end
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if String.byte_size(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}));

    gated "an extern-declared String.byte_size is NOT aliased" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod QSExt do
  mod String do
    needs Ffi
    extern "c" : Cap(Ffi) do
      fn byte_size(s: String) : Int = "march_qsext_byte_size"
    end
  end
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if String.byte_size(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}));

    (* Same shape, same honesty note, as the list-side entry-module case. *)
    gated "an entry module named String defining `byte_size` is NOT aliased" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod String do
  fn byte_size(s : String) : Int do 99 end
  mod Inner do
    fn slug(s : {String | len(_) > 0}) : Int do 1 end
    fn go(t : String) : Int do
      if String.byte_size(t) == 0 do slug(t) else 0 end
    end
  end
  fn main() : Int do Inner.go("a") end
end|}));

    gated "`import X.{String}` withdraws the alias" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod QSIN do
  import Shim.{String}
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if String.byte_size(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}));

    (* The ENABLING branch.  Every case above reaches its verdict with NO
       `String.byte_size` definition in scope, i.e. via the gate's "no defs ->
       allow" path — none of them can tell whether the stdlib-identity test
       works, which is exactly how a dead feature can pass a whole suite.
       These two are the same program, differing ONLY in whether the caller
       declares that file to be the standard library. *)
    (let src =
       {|
mod SG do
  mod String do
    fn byte_size(s : String) : Int do 0 end
  end
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if String.byte_size(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}
     in
     let file = "/opt/march/share/march/string.march" in
     gated "the alias APPLIES to a String.byte_size the caller calls stdlib" (fun () ->
         Alcotest.(check bool) "error" true
           (has_refine_error_from ~stdlib_files:[ file ] ~file src)));

    (let src =
       {|
mod SG do
  mod String do
    fn byte_size(s : String) : Int do 0 end
  end
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if String.byte_size(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}
     in
     gated "…and NOT to the same String.byte_size from any other file" (fun () ->
         Alcotest.(check bool) "no error" false
           (has_refine_error_from ~stdlib_files:[ "/opt/march/share/march/string.march" ]
              ~file:"/home/u/proj/vendor/string.march" src)));

    (* The bare builtin has no stdlib definition to identify, so ANY definition
       of the name takes it.  Constantly 99 again: the `== 0` branch is dead. *)
    gated "a user-defined string_byte_length withdraws the bare alias" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod QB do
  fn string_byte_length(s : String) : Int do 99 end
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if string_byte_length(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}));

    (* ── Expression-level shadowing ────────────────────────────────────────
       A `let` binder shadows the builtin just as a declaration does, and the
       first cut of the gate scanned declaration forms only.  The body here
       evaluates to 99, so the `== 0` branch is DEAD, `slug` is never called,
       and the program cannot violate anything — reporting one was a
       demonstrated FALSE POSITIVE on correct code.

       Load-bearing as a PAIR with case 2 above, which uses the genuine builtin
       and must still FIRE: together they separate "the gate sees local
       binders" from "the gate suppressed the feature into silence". *)
    gated "a let-bound string_byte_length withdraws the bare alias" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod RS do
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    let string_byte_length = fn s -> 99
    if string_byte_length(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}));

    (* Same hole, reached through a PARAMETER rather than a `let`. *)
    gated "a parameter named string_byte_length withdraws the bare alias" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod RSP do
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String, string_byte_length : (String) -> Int) : Int do
    if string_byte_length(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a", fn s -> 99) end
end|}));

    (* A lambda parameter, i.e. a binder found only by descending INTO an
       expression — the case a declaration-form scan cannot reach at all. *)
    gated "a lambda parameter named string_byte_length withdraws the bare alias"
      (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod RSL do
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    let f = fn string_byte_length -> 99
    if string_byte_length(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}));

    (* ── Declaration forms that BIND without being descended into ──────────
       A module-level `let` is never visited by [visit_decls] — yet it binds the
       name for every sibling `fn` body, which is exactly where obligations are
       raised.  Reasoning from "the checker never descends into a DLet" is what
       hid this; the gate's invariant is now "can this construct put the name in
       scope for a checked body", not "is this construct visited". *)
    gated "a module-level let string_byte_length withdraws the bare alias" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod DL do
  let string_byte_length = fn s -> 99
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if string_byte_length(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}));

    (* An `extern` block declares its functions under their bare names — the
       same class of hole, reached through a different decl form. *)
    gated "an extern fn named string_byte_length withdraws the bare alias" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod DX do
  needs LibC
  extern "libc": Cap(LibC) do
    fn string_byte_length(s: String): Int
  end
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if string_byte_length(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}))
  ]

(* ── Obligation ledger ────────────────────────────────────────────────────
   The checker reports a violation only when a predicate can NEVER hold, so
   silence covers three very different outcomes.  These pin that every
   precondition obligation leaves a COUNTABLE record: a proved one, a violated
   one, and one the checker could not reflect into SMT at all — the last is the
   case that used to be indistinguishable from a passing contract. *)
let obligation_suite =
  [ gated "a proved precondition is recorded as Proved" (fun () ->
        March_refinecheck.Obligation.reset ();
        ignore
          (has_refine_error
             "mod O1 do\n\
             \  fn takepos(k : {Int | _ >= 0}) : Int do k end\n\
             \  fn main() : Int do takepos(5) end\n\
              end\n");
        let proved, violated, _ = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "proved" 1 proved;
        Alcotest.(check int) "violated" 0 violated);

    gated "a violated precondition is recorded as Violated" (fun () ->
        March_refinecheck.Obligation.reset ();
        ignore
          (has_refine_error
             "mod O2 do\n\
             \  fn takepos(k : {Int | _ >= 0}) : Int do k end\n\
             \  fn main() : Int do takepos(0 - 5) end\n\
              end\n");
        let _, violated, _ = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "violated" 1 violated);

    gated "an unreflectable predicate is recorded as a SKIP, not silence" (fun () ->
        March_refinecheck.Obligation.reset ();
        ignore
          (has_refine_error
             "mod O3 do\n\
             \  fn weird(k : {Int | is_prime(_)}) : Int do k end\n\
             \  fn main() : Int do weird(5) end\n\
              end\n");
        let proved, violated, skips = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "not proved" 0 proved;
        Alcotest.(check int) "not violated" 0 violated;
        Alcotest.(check int) "one skip recorded" 1
          (List.fold_left (fun a (_, n) -> a + n) 0 skips))
  ]

(* ── `cap verified`: an obligation the checker SKIPS becomes an error ─────
   The default stance reports only definite failures; `cap verified` inverts
   that for the module that asks for it.  The load-bearing test is the third
   one: if strict mode ever fires for a module that did not opt in, the default
   stance is broken for every existing program. *)
let refine_error_texts src =
  let ctx = March_errors.Errors.create () in
  March_refinecheck.Refine_check.check_module ctx (parse src);
  List.filter_map
    (fun (d : March_errors.Errors.diagnostic) ->
      if d.March_errors.Errors.severity = March_errors.Errors.Error then
        Some d.March_errors.Errors.message
      else None)
    ctx.March_errors.Errors.diagnostics

let cap_verified_suite =
  [ gated "cap verified: an unreflectable predicate is an ERROR" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod V1 do\n\
             \  cap verified\n\
             \  fn weird(k : {Int | is_prime(_)}) : Int do k end\n\
             \  fn main() : Int do weird(5) end\n\
              end\n"));

    gated "cap verified: a PROVED obligation stays silent" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod V2 do\n\
             \  cap verified\n\
             \  fn takepos(k : {Int | _ >= 0}) : Int do k end\n\
             \  fn main() : Int do takepos(5) end\n\
              end\n"));

    (* THE test.  Same skip, no `cap verified` — must stay silent. *)
    gated "WITHOUT cap verified the same skip stays silent" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod V3 do\n\
             \  fn weird(k : {Int | is_prime(_)}) : Int do k end\n\
             \  fn main() : Int do weird(5) end\n\
              end\n"));

    (* Scoping, outward: a nested ordinary module inside a `cap verified` one
       does NOT inherit strictness.  In production bin/main.ml prepends the
       whole standard library as sibling `DMod`s of the entry module's decls,
       so inheritance would make every stdlib module strict. *)
    gated "cap verified does NOT reach into a nested ordinary module" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod V4 do\n\
             \  cap verified\n\
             \  mod Inner do\n\
             \    fn weird(k : {Int | is_prime(_)}) : Int do k end\n\
             \    fn go() : Int do weird(5) end\n\
             \  end\n\
             \  fn main() : Int do 0 end\n\
              end\n"));

    (* Scoping, inward: a nested module may opt in on its own, and doing so
       must not leave strict mode on for its siblings. *)
    gated "a nested cap verified module opts in without leaking to siblings" (fun () ->
        let errs =
          refine_error_texts
            "mod V5 do\n\
            \  mod Inner do\n\
            \    cap verified\n\
            \    fn weird(k : {Int | is_prime(_)}) : Int do k end\n\
            \    fn go() : Int do weird(5) end\n\
            \  end\n\
            \  fn odd(k : {Int | is_prime(_)}) : Int do k end\n\
            \  fn main() : Int do odd(5) end\n\
             end\n"
        in
        Alcotest.(check int) "exactly the nested call errors" 1 (List.length errs));

    (* The message must name the obligation and say why it could not be
       discharged — the whole point is legibility. *)
    gated "the cap verified error names the predicate, the callee and the reason"
      (fun () ->
        let errs =
          refine_error_texts
            "mod V6 do\n\
            \  cap verified\n\
            \  fn weird(k : {Int | is_prime(_)}) : Int do k end\n\
            \  fn main() : Int do weird(5) end\n\
             end\n"
        in
        Alcotest.(check int) "one error" 1 (List.length errs);
        let msg = List.hd errs in
        let has sub =
          let n = String.length sub and m = String.length msg in
          let rec go i = i + n <= m && (String.sub msg i n = sub || go (i + 1)) in
          go 0
        in
        Alcotest.(check bool) "names cap verified" true (has "cap verified");
        Alcotest.(check bool) "names the predicate" true (has "is_prime");
        Alcotest.(check bool) "names the callee" true (has "weird");
        Alcotest.(check bool) "names the reason" true (has "unreflectable-predicate"))
  ]

(* ── Division-safety reflection hole (Task 8) ──────────────────────────────
   NOTE: [has_refine_error] runs [Refine_check], which does NOT run the
   `cap no_panic` division checker — that is a separate pass wired in
   bin/main.ml.  These tests must call [Division_safety] directly, on the
   DESUGARED module, exactly as the driver does. *)
let divsafety_error_texts src =
  let ctx = March_errors.Errors.create () in
  March_refinecheck.Division_safety.check_module ctx
    (March_desugar.Desugar.desugar_module (parse src));
  List.filter_map
    (fun (d : March_errors.Errors.diagnostic) ->
      if d.March_errors.Errors.severity = March_errors.Errors.Error then
        Some d.March_errors.Errors.message
      else None)
    ctx.March_errors.Errors.diagnostics

let has_divsafety_error src = divsafety_error_texts src <> []

(* NOTE ON GATING: none of these cases reaches the solver, so they must NOT be
   [gated] on z3 — a [gated] hole test would silently SKIP on a z3-less machine,
   i.e. the test whose whole point is fail-closed behaviour when verification is
   unavailable would be disabled exactly when verification is unavailable.
   Case by case: `is_prime` fails at REFLECTION ([smt_of] returns None) before
   Z3 is consulted; `_ > 0` is discharged by [syntactic_nonzero], which matches
   the `_` binder directly; a bare `Int` divisor errors in the unrefined branch
   with no VC built; and every path-condition discharge goes through
   [path_proves_nonzero], which is purely syntactic.  Verified empirically by
   running this group with z3 removed from PATH. *)
let divsafety_hole_suite =
  [ Alcotest.test_case
      "cap no_panic: an unreflectable divisor refinement is an ERROR" `Quick
      (fun () ->
        (* Before the fix this PASSED: `is_prime` does not reflect, so [smt_of]
           returned None and division_safety treated that as proof.  Writing a
           meaningless refinement was more permissive than writing none. *)
        Alcotest.(check bool) "error" true
          (has_divsafety_error
             "mod D1 do\n\
             \  cap no_panic\n\
             \  fn f(n : Int, d : {Int | is_prime(_)}) : Int do n / d end\n\
              end\n"))
  ; Alcotest.test_case "cap no_panic: a genuine proof still passes" `Quick
      (fun () ->
        Alcotest.(check bool) "no error" false
          (has_divsafety_error
             "mod D2 do\n\
             \  cap no_panic\n\
             \  fn f(n : Int, d : {Int | _ > 0}) : Int do n / d end\n\
              end\n"))
  ; Alcotest.test_case "cap no_panic: a bare Int divisor still errors" `Quick
      (fun () ->
        Alcotest.(check bool) "error" true
          (has_divsafety_error
             "mod D3 do\n\
             \  cap no_panic\n\
             \  fn f(n : Int, d : Int) : Int do n / d end\n\
              end\n"))
  ; Alcotest.test_case
      "cap no_panic: unreflectable-refinement error explains itself" `Quick
      (fun () ->
        let errs =
          divsafety_error_texts
            "mod D4 do\n\
            \  cap no_panic\n\
            \  fn f(n : Int, d : {Int | is_prime(_)}) : Int do n / d end\n\
             end\n"
        in
        Alcotest.(check int) "one error" 1 (List.length errs);
        let msg = List.hd errs in
        let has sub =
          let n = String.length sub and m = String.length msg in
          let rec go i = i + n <= m && (String.sub msg i n = sub || go (i + 1)) in
          go 0
        in
        Alcotest.(check bool) "names the divisor" true (has "`d`");
        Alcotest.(check bool) "names the cap" true (has "cap no_panic");
        Alcotest.(check bool) "names the reason" true
          (has "outside the checkable fragment"))
  ; Alcotest.test_case
      "cap no_panic: a CLAUSE guard proving d != 0 is silent (unrefined branch)"
      `Quick (fun () ->
        (* CAUTION — this case does NOT exercise the `None`-arm path guard, even
           though it looks like it should.  Desugaring rewrites a guarded clause
           into a match, so the refined parameter is no longer visible to
           [clause_refined_params] and [check_var_divisor] takes the UNREFINED
           branch, which has always consulted [path_proves_nonzero].  Proof: the
           same module with a NON-proving clause guard (`when n > 0`) reports
           "no refinement proves `d != 0`" — the unrefined message, not the
           unreflectable-fragment one.  Kept as a regression pin on the
           desugared-guard path; the `None` arm is pinned by D6/D7 below. *)
        Alcotest.(check bool) "no error" false
          (has_divsafety_error
             "mod D5 do\n\
             \  cap no_panic\n\
             \  fn f(n : Int, d : {Int | is_prime(_)}) : Int when d != 0 do n / d end\n\
              end\n"))
  ; Alcotest.test_case
      "cap no_panic: a BODY-LEVEL guard discharges an unreflectable refinement"
      `Quick (fun () ->
        (* THIS is the case that exercises the [path_proves_nonzero] call in the
           new `None` arm: a body-level `if` leaves the parameter list intact, so
           [check_var_divisor] takes the REFINED branch, `is_prime` fails to
           reflect, and only the path condition can discharge the obligation.
           Deleting that call from division_safety.ml makes this test fail (and
           only this one) — verified. *)
        Alcotest.(check bool) "no error" false
          (has_divsafety_error
             "mod D6 do\n\
             \  cap no_panic\n\
             \  fn f(n : Int, d : {Int | is_prime(_)}) : Int do\n\
             \    if d != 0 do n / d else 0 end\n\
             \  end\n\
              end\n"))
  ; Alcotest.test_case
      "cap no_panic: a body-level guard that does NOT prove d != 0 still errors"
      `Quick (fun () ->
        (* Negative control for D6: the path guard must actually prove the goal.
           Without this, D6 alone could be satisfied by a path guard that
           discharges unconditionally. *)
        Alcotest.(check bool) "error" true
          (has_divsafety_error
             "mod D7 do\n\
             \  cap no_panic\n\
             \  fn f(n : Int, d : {Int | is_prime(_)}) : Int do\n\
             \    if n > 0 do n / d else 0 end\n\
             \  end\n\
              end\n"))
  ]

let () =
  Alcotest.run "march-refinecheck"
    [ ("refinecheck", suite);
      ("bounds-a2", a2_suite);
      ("path-sensitivity", path_suite);
      ("postconditions", post_suite);
      ("assume-p1c", assume_suite);
      ("collision-p1a", collision_suite);
      ("measures-p1b", measure_suite);
      ("axioms-ma", axiom_suite);
      ("gate-mb", gate_suite);
      ("list-axioms-mb", list_axiom_suite);
      ("mutual-mc", mutual_suite);
      ("flag-gating", flag_suite);
      ("resolution", resolution_suite);
      ("record-postconditions", record_suite);
      ("record-path-facts", record_path_suite);
      ("guard-path-sensitivity", guard_suite);
      ("tier0-postcond", tier0_suite);
      ("string-refinements", string_suite);
      ("predicate-vocab", vocab_suite);
      ("adt-tags", adt_suite);
      ("pred-classifier", classifier_suite);
      ("tier1-relational", tier1_suite);
      ("higher-order", hof_suite);
      ("tier2-induction", tier2_suite);
      ("callee-shadowing", shadow_suite);
      ("anon-binder-measures", b1_suite);
      ("record-postcond-propagation", b2_suite);
      ("bool-refinements", bool_suite);
      ("float-refinements", float_suite);
      ("length-alias", length_alias_suite);
      ("string-alias", string_alias_suite);
      ("obligations", obligation_suite);
      ("cap-verified", cap_verified_suite);
      ("divsafety-hole", divsafety_hole_suite) ]
