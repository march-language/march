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
                "  fn g(i : Int) : Int do if i < 0 do take_n(i) else 0 end end")))
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
        Alcotest.(check bool) "gate off" false (has_refine_error_no_axioms prog)) ]

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
end|})) ]

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
        (* The arm rebinds `x`, so the outer scrutinee's tag says nothing
           about the inner `x`.  Correct code — must stay silent. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod M do\n\
             \  fn unwrap(o : {Option(Int) | is_Some(_)}) : Int do 0 end\n\
             \  fn f(x : Option(Int), y : Option(Int)) : Int do\n\
             \    match y do\n\
             \      Some(x) -> 0\n\
             \      None -> 0\n\
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
      ("guard-path-sensitivity", guard_suite);
      ("tier0-postcond", tier0_suite);
      ("predicate-vocab", vocab_suite);
      ("adt-tags", adt_suite) ]

