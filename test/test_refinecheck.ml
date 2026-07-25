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

(* Same, but DESUGARED first — required for qualified calls (`M.f(x)`), which the
   parser produces as `EField` and desugar flattens to a single dotted `EVar`,
   exactly as the compiler feeds refine_check in production. *)
let has_refine_error_d src =
  let ctx = March_errors.Errors.create () in
  March_refinecheck.Refine_check.check_module ctx (March_desugar.Desugar.desugar_module (parse src));
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
                "  fn f(n : Int) : {Int | _ >= 0} do if n < 0 do n else 0 end end"))) ]

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
       scalar reflection declares every variable SInt, so reflecting it anyway
       would build a constructor application with mismatched argument sorts —
       and Z3 answers a malformed VC with an error that DESYNCS the long-lived
       `z3 -in` channel, silently disabling refinement checking for the rest of
       the compilation.  So the record must be skipped instead. *)
    gated "record precondition: non-Int field bound to a variable is skipped" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error {|mod M do
  type Config = { port : Int, name : String }
  fn serve(c : {v : Config | v.port >= 1}) : Int do c.port end
  fn f(n : String) : Int do serve({ port: 0, name: n }) end
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
       every later verdict by one.  The record must be skipped instead. *)
    gated "record precondition: a concrete list element is a nested sort mismatch" (fun () ->
        Alcotest.(check bool) "no error" false
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
end|})) ]

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

    gated "relational postcondition is NOT propagated (Tier 1 boundary)" (fun () ->
        (* `_ < n` mentions the parameter `n`, so pred_is_closed rejects it and
           the call site learns nothing.  Silence here is correct, not a bug. *)
        Alcotest.(check bool) "no error" false
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
      ("adt-tags", adt_suite) ]

