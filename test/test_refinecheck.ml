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

(* The text of every ERROR the refinement pass reports on [src], concatenated.
   DESUGARED, for the same reason [has_refine_error_d] is: a qualified guard
   like `List.length(ys)` is an `EField` chain until desugar flattens it, so a
   fixture checked without desugaring exercises a different program than the
   compiler does — and an assertion about the message would then pass or fail
   for reasons unrelated to what it claims to test.

   A boolean cannot distinguish "reported for the right reason" from "reported
   for a different one", which is exactly what the attribution of a skip is
   about; only the text can. *)
let refine_error_text_d src =
  let ctx = March_errors.Errors.create () in
  March_refinecheck.Refine_check.check_module ctx
    (March_desugar.Desugar.desugar_module (parse src));
  String.concat "\n"
    (List.filter_map
       (fun (d : March_errors.Errors.diagnostic) ->
         if d.March_errors.Errors.severity = March_errors.Errors.Error then
           Some d.March_errors.Errors.message
         else None)
       ctx.March_errors.Errors.diagnostics)

(* Substring search — [String.contains] is over CHARACTERS, and there is no
   substring predicate in the OCaml stdlib. *)
let contains (hay : string) (needle : string) : bool =
  let n = String.length needle and h = String.length hay in
  let rec at i = i + n <= h && (String.sub hay i n = needle || at (i + 1)) in
  n = 0 || at 0

(* True iff the refinement pass reports at least one WARNING on [src].
   [has_refine_error] only sees Errors, so vocabulary diagnostics need this. *)
let has_refine_warning src =
  let ctx = March_errors.Errors.create () in
  March_refinecheck.Refine_check.check_module ctx (parse src);
  List.exists
    (fun (d : March_errors.Errors.diagnostic) ->
      d.March_errors.Errors.severity = March_errors.Errors.Warning)
    ctx.March_errors.Errors.diagnostics

(* Hints emitted by the refinement pass, as (message) list. *)
let refine_hints src =
  let ctx = March_errors.Errors.create () in
  March_refinecheck.Refine_check.check_module ctx (parse src);
  List.filter_map
    (fun (d : March_errors.Errors.diagnostic) ->
      if d.March_errors.Errors.severity = March_errors.Errors.Hint
      then Some d.March_errors.Errors.message else None)
    ctx.March_errors.Errors.diagnostics

(* Most of this suite needs a solver, so a z3-less machine cannot run it.  What
   it must NOT do is report those cases as PASSING.  [gated] used to print a
   "[skip]" line and then return unit, which alcotest scores as `[OK]`: on a
   machine without z3 the entire gated corpus went green and the exit code said
   nothing at all — a developer could "run the refinement tests" and learn
   precisely zero.  [Alcotest.skip] raises instead, so those cases are reported
   as `[SKIP]` and counted as skipped in the summary line.

   RESIDUAL HAZARD, stated plainly because it cannot be removed from here:
   alcotest still EXITS 0 when every test skipped, so a green exit code is not
   by itself evidence that anything was verified.  Read the summary line — it
   distinguishes "N tests run" from "N skipped".  CI installs z3 (see
   .github/actions/march-setup/action.yml), so on CI nothing here is skipped;
   this is a developer-local hazard.  Cases that do NOT need a solver are
   deliberately built with a plain [Alcotest.test_case] rather than [gated] —
   see [cap_verified_suite], [reason_suite] and [divsafety_hole_suite] — since
   gating a test whose subject is fail-closed behaviour would disable it
   exactly when verification is unavailable. *)
let gated name f =
  Alcotest.test_case name `Quick (fun () ->
      if z3_available () then f () else Alcotest.skip ())

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
             (decl "  fn fwd(m : {Int | _ >= 0}) : Int do take_n(m) end")));

    (* The message used to open with a bare "argument", which on a call with
       several arguments does not say which one — and the predicate's binder is
       usually the anonymous `_`, so nothing else in the message identified it
       either. It now names the parameter and the callee. *)
    gated "violation names the offending parameter and callee" (fun () ->
        let text =
          refine_error_text_d (decl "  fn main() : Int do nonzero(0) end") in
        Alcotest.(check bool) "names the parameter" true
          (contains text "argument `d`");
        Alcotest.(check bool) "names the callee" true
          (contains text "of `nonzero`");
        Alcotest.(check bool) "still quotes the predicate" true
          (contains text "_ != 0"));

    (* A definite violation whose model has a free variable should still carry
       the solver's counterexample — the parameter naming must not displace it. *)
    gated "violation keeps the solver counterexample" (fun () ->
        let text =
          refine_error_text_d
            (decl "  fn f(k : {Int | _ < 0}) : Int do take_n(k) end") in
        Alcotest.(check bool) "reports a violation" true
          (contains text "refinement violation");
        Alcotest.(check bool) "includes a counterexample" true
          (contains text "e.g. k = "));

    (* An undecidable obligation stays non-fatal, but silence is
       indistinguishable from "checked and fine". One hint per module says so
       and names the escalation. *)
    gated "an unverified contract is announced once" (fun () ->
        let hints =
          refine_hints (decl "  fn f(k : Int) : Int do take_n(k) end") in
        Alcotest.(check bool) "a hint is emitted" true
          (List.exists (fun h -> contains h "was NOT verified here") hints);
        Alcotest.(check bool) "it points at `cap verified`" true
          (List.exists (fun h -> contains h "cap verified") hints));

    (* Advice repeated per call site would be worse than silence. *)
    gated "the unverified hint is emitted at most once per module" (fun () ->
        let hints =
          refine_hints
            (decl
               "  fn f(k : Int) : Int do take_n(k) end\n\
               \  fn g(k : Int) : Int do take_n(k) end\n\
               \  fn h(k : Int) : Int do take_n(k) end") in
        Alcotest.(check int) "exactly one unverified hint" 1
          (List.length
             (List.filter (fun h -> contains h "was NOT verified here") hints)));

    (* The hint is about the checker giving up. Code it can discharge must stay
       completely silent, or every clean project grows advisory noise. *)
    gated "a fully proved module emits no unverified hint" (fun () ->
        let hints = refine_hints (decl "  fn main() : Int do take_n(5) end") in
        Alcotest.(check int) "no unverified hints on proved code" 0
          (List.length
             (List.filter (fun h -> contains h "was NOT verified here") hints))) ]

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
  (* Asserts the LEDGER, not silence.  Silence is what a SKIP looks like too, so
     `check bool "no error" false` here passed with the alias deleted — the very
     confusion the obligation ledger exists to end.  `1 proved, 0 skipped` is a
     claim only a working alias can satisfy.
     Mutation that fails this: make [measure_alias] return [None] always
     (lib/refinecheck/refine_check.ml) — proved drops 1→0, skipped 0→1. *)
  [ gated "a List.length guard discharges a len obligation" (fun () ->
        let src =
          {|
mod L1 do
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) > 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}
        in
        March_refinecheck.Obligation.reset ();
        Alcotest.(check bool) "no error" false (has_refine_error_d src);
        let proved, violated, skips = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "proved" 1 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "skipped" 0
          (List.fold_left (fun a (_, n) -> a + n) 0 skips));

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
       shape needs bin/main.ml's real driver.  It is kept because the property
       it asserts (silence) is the one that must hold, not because it is a
       witness.  The WITNESS that discriminates the walk start is
       `specs/lang/types/accept/t126_entry_module_shadows_list_length.march`
       (and `t127…string_byte_size` for the other alias): it declares `length`
       in an `extern` block — a decl form `strip_entry_self_qual` does not
       rewrite, so the call site really does reach refinecheck spelled
       `List.length` — and with the walk start reverted to `go false` the
       corpus rejects it with a FALSE `len(ys) = 0`.  Note `fn length` as
       written below could NOT be that witness even through the real driver:
       desugar strips `List.length` to bare `length` whenever the entry module
       declares `length` as a `fn` or a `let`. *)
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

    (* `Shim` is not declared in this unit, so the glob's contents cannot be
       resolved — the unresolvable case, which still withdraws. *)
    gated "a glob `import X` of an UNRESOLVABLE X withdraws the alias" (fun () ->
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

    (* ── The glob pair: LOOK, don't assume ─────────────────────────────────
       A glob used to withdraw unconditionally.  Because bin/main.ml prepends
       the whole stdlib and this gate is unit-global, the single `import
       Process` in `stdlib/system.march` therefore withdrew the alias for
       EVERY March program — the feature was inert in production, and no
       ACCEPT witness could see it (a skip exits 0 exactly like a proof).

       These two fixtures are the same program, differing ONLY in whether the
       glob's target actually carries a competing `List.length`.  The second
       is the one that discriminates the fix (it FAILS pre-fix, silently); the
       first is the one that guards the soundness boundary — trading a dead
       feature for a false positive would show up here. *)
    gated "a glob whose target DOES define List.length withdraws the alias" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod QGComp do
  mod Shim do
    mod List do
      fn length(xs : List(Int)) : Int do 0 end
    end
  end
  import Shim
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) == 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}));

    gated "a glob whose target has NO List keeps the alias" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error_d
             {|
mod QGClean do
  mod Shim do
    fn helper(x : Int) : Int do x end
  end
  import Shim
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) == 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}));

    (* An `alias … as List` inside the glob's target is a competitor too. *)
    gated "a glob whose target aliases something to `List` withdraws the alias"
      (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod QGAlias do
  mod Other do
    fn length(xs : List(Int)) : Int do 0 end
  end
  mod Shim do
    alias Other as List
  end
  import Shim
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) == 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}));

    (* ── The UseSingle pair: LOOK, don't assume (Task 9, 2026-07-31) ───────
       `use X.List` (UseSingle) used to withdraw purely syntactically on its
       last path segment, while the two glob forms already RESOLVED their
       target and checked it.  Measured cost (MARCH_LIB_PATH fixture, ledger
       report): one nested `use Extras.Deep.List` in a dependency — whose
       target has NO `length` member at all, so it cannot make `List.length`
       denote anything non-stdlib at ANY call site — flipped the entry's
       obligation from `1 proved` to `1 skipped (alias-withdrawn)`.

       The narrowed arm resolves the use's target (from EVERY module scope of
       the unit, ALL matches) and withdraws only when some match provides a
       member named `length` — where "provides" is fail-closed over the
       target's own use-forms — or when nothing resolves.  Soundness does not
       rest on resolver semantics: rebinding `List` to a module that provably
       provides nothing named `length` cannot make `List.length` denote a
       non-stdlib function anywhere.  A target that provides it via a DIRECT
       member decl is a `mod List` with that member, which the member gate
       withdraws independently — so the cases this arm alone must keep are
       the re-export and unresolvable shapes below. *)
    gated "`use X.List` whose target provably lacks `length` keeps the alias"
      (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error_d
             {|
mod QUKeep do
  mod Shim do
    mod List do
      fn size(xs : List(Int)) : Int do 0 end
    end
  end
  use Shim.List
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) == 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}));

    (* The member gate is silent here — a `use Helpers.{length}` inside the
       target is not a member DECL — so this fixture discriminates the
       provides-walk itself: drop its UseNames arm and the alias is wrongly
       kept, and this correct program is reported. *)
    gated "`use X.List` whose target re-exports a `length` withdraws the alias"
      (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod QUReex do
  mod Helpers do
    fn length(xs : List(Int)) : Int do 99 end
  end
  mod Shim do
    mod List do
      use Helpers.{length}
    end
  end
  use Shim.List
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) == 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}));

    gated "`use X.List` with an UNRESOLVABLE target withdraws the alias"
      (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod QUUnres do
  use Ghost.List
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) == 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}));

    gated "`use X.List` whose target holds an unenumerable glob withdraws the alias"
      (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod QUGlob do
  mod Shim do
    mod List do
      import Unknowable
    end
  end
  use Shim.List
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) == 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}));

    (* Two modules answer to the path `Shim.List` — a top-level one that lacks
       `length` and a nested one that re-exports it.  Which one the `use`
       semantically binds is exactly the question this pass cannot answer, so
       resolution must consider ALL matches from EVERY scope and withdraw if
       ANY provides: a first-match-from-root implementation keeps the alias
       here and reports this correct program. *)
    gated "`use X.List` withdraws when ANY same-path module provides `length`"
      (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod QUDup do
  mod Helpers do
    fn length(xs : List(Int)) : Int do 99 end
  end
  mod Shim do
    mod List do
      fn size(xs : List(Int)) : Int do 0 end
    end
  end
  mod Outer do
    mod Shim do
      mod List do
        use Helpers.{length}
      end
    end
  end
  use Shim.List
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

    (* ── A stdlib `import` must not withdraw the alias ────────────────────
       The REBINDING half of this gate treats a glob `import X` as "could
       carry a nested module named List", and — unlike the DEFINITION half,
       which has always ignored stdlib spans — applied that to the standard
       library's own sources.  One import added inside stdlib therefore
       withdrew `List.length` -> `len` for every program compiled with it.

       Not hypothetical: #112 added `import Process` to stdlib/system.march
       to dedupe System.ProcessResult, and every `{List(a) | len(_) > 0}`
       contract stopped being enforced.  Nothing failed except
       specs/lang/types/reject/t117, which exists to notice exactly this — a
       withdrawn alias is silent by construction, since refinement checking
       only speaks when a predicate can NEVER hold.  So the contradictory
       guard here must still FIRE for the test to mean anything. *)
    (let src =
       {|
mod SysLike do
  import Process
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) == 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}
     in
     let file = "/opt/march/share/march/system.march" in
     gated "a glob import in a STDLIB file does not withdraw the alias" (fun () ->
         Alcotest.(check bool) "violation still reported" true
           (has_refine_error_from ~stdlib_files:[ file ] ~file src)));

    (* Control: the same glob import in the PROGRAM's own file still
       withdraws it — a user's `import X` genuinely can put another module
       under the bare name `List`, and suppressing is the safe direction. *)
    (let src =
       {|
mod UserMod do
  import Process
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) == 0 do head(ys) else 0 end
  end
  fn main() : Int do go([1]) end
end|}
     in
     gated "...while the same import in USER code still withdraws it" (fun () ->
         Alcotest.(check bool) "no error" false
           (has_refine_error_from
              ~stdlib_files:[ "/opt/march/share/march/list.march" ]
              ~file:"/home/u/proj/main.march" src)));

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
  (* Ledger, not silence — see the note on [length_alias_suite]'s first case.
     Mutation that fails this: make [measure_alias] return [None] always;
     proved drops 1→0 and the obligation reappears as a skip. *)
  [ gated "a String.byte_size guard discharges a String len obligation" (fun () ->
        let src =
          {|
mod S1 do
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if String.byte_size(t) > 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}
        in
        March_refinecheck.Obligation.reset ();
        Alcotest.(check bool) "no error" false (has_refine_error_d src);
        let proved, violated, skips = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "proved" 1 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "skipped" 0
          (List.fold_left (fun a (_, n) -> a + n) 0 skips));

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

    (* Same shape, same honesty note, as the list-side entry-module case — the
       discriminating witness for this half is
       `specs/lang/types/accept/t127_entry_module_shadows_string_byte_size.march`. *)
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

    (* The glob pair, string side — the two gates are one parameterised
       function, so both spellings are pinned symmetrically.  See the list
       side for why the second case is the one that discriminates the fix. *)
    gated "a glob whose target DOES define String.byte_size withdraws the alias"
      (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod QSGComp do
  mod Shim do
    mod String do
      fn byte_size(s : String) : Int do 0 end
    end
  end
  import Shim
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if String.byte_size(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}));

    gated "a glob whose target has NO String keeps the alias" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error_d
             {|
mod QSGClean do
  mod Shim do
    fn helper(x : Int) : Int do x end
  end
  import Shim
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if String.byte_size(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}));

    (* The UseSingle narrowing, string side — the gate is one parameterised
       function, so the `use X.String` arm is pinned symmetrically with the
       list side's QUKeep. *)
    gated "`use X.String` whose target provably lacks `byte_size` keeps the alias"
      (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error_d
             {|
mod QSUKeep do
  mod Shim do
    mod String do
      fn size(s : String) : Int do 0 end
    end
  end
  use Shim.String
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if String.byte_size(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}));

    (* And the bare-builtin gate, which shares the same glob resolution: a
       glob takes `string_byte_length` only if its target declares one. *)
    gated "a glob whose target DEFINES string_byte_length withdraws the bare alias"
      (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d
             {|
mod QBGComp do
  mod Shim do
    fn string_byte_length(s : String) : Int do 99 end
  end
  import Shim
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if string_byte_length(t) == 0 do slug(t) else 0 end
  end
  fn main() : Int do go("a") end
end|}));

    gated "a glob whose target lacks string_byte_length keeps the bare alias" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error_d
             {|
mod QBGClean do
  mod Shim do
    fn helper(x : Int) : Int do x end
  end
  import Shim
  fn slug(s : {String | len(_) > 0}) : Int do 1 end
  fn go(t : String) : Int do
    if string_byte_length(t) == 0 do slug(t) else 0 end
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

(* ── Reason CLASSIFICATION ─────────────────────────────────────────────────
   [obligation_suite] above counts skips; these pin WHICH reason each skip is
   filed under.  A count cannot tell the difference, and the difference is the
   whole reason several of these constructors exist: [Unreflectable_subject]
   was split out of [Unreflectable_predicate] precisely so a record-typed
   SUBJECT that failed to reflect is not reported as an unreflectable
   PREDICATE — a user with a perfectly ordinary predicate would otherwise be
   told to rewrite it and sent after the wrong thing.  Nothing checked that
   split ever fired, so the two could have been silently re-conflated (or
   swapped) with the suite still green.

   Gating: only the [Solver_undecided] case reaches the solver.  The other
   three are decided at reflection / sort-gate time, BEFORE [Refine.discharge],
   so gating them would disable them on a z3-less machine for no reason — and
   worse, [Solver_undecided] is the fallthrough every obligation lands in when
   there is no solver, so an ungated reason test would pass by accident there.
   Verified empirically with z3 off PATH. *)
let skip_reasons src =
  March_refinecheck.Obligation.reset ();
  ignore (has_refine_error_d src);
  List.filter_map
    (fun (o : March_refinecheck.Obligation.t) ->
      match o.March_refinecheck.Obligation.verdict with
      | March_refinecheck.Obligation.Skipped r ->
        Some (March_refinecheck.Obligation.reason_name r)
      | _ -> None)
    (March_refinecheck.Obligation.all ())

let reason_suite =
  [ (* A RECORD subject whose actual cannot be reflected: `mk()` is a call, so
       [record_self] finds no term for it and no goal is built at all.  The
       predicate `v.port >= 1` is entirely reflectable — which is the point:
       blaming it would be a lie.
       Mutation that fails this: in refine_check.ml, change the `\`Skip` arm of
       the reason match to [Unreflectable_predicate] (i.e. undo the split). *)
    Alcotest.test_case "an unreflectable SUBJECT is not blamed on the predicate"
      `Quick (fun () ->
        let rs =
          skip_reasons
            {|mod RS1 do
  type Config = { port : Int }
  fn mk() : Config do { port: 1 } end
  fn serve(c : {v : Config | v.port >= 1}) : Int do c.port end
  fn f() : Int do serve(mk()) end
end|}
        in
        Alcotest.(check (list string)) "unreflectable-subject"
          [ "unreflectable-subject" ] rs);

    (* Reflection SUCCEEDS here — `_ > "a"` builds a term — but it compares the
       `$Str`-sorted subject with an Int-sorted side, which [wellsorted]
       rejects before any VC is sent.  Sending it would put an `(error …)` line
       on the shared `z3 -in` channel.
       Mutation that fails this: make [sort_conflict] return [false] always,
       or make [wellsorted] return [true] always — the obligation then reaches
       the solver and is filed [solver-undecided] instead. *)
    Alcotest.test_case "a Str/Int sort clash is filed as sort-conflict" `Quick
      (fun () ->
        let rs =
          skip_reasons
            {|mod RS2 do
  fn f(s : {String | _ > "a"}) : Int do 1 end
  fn go(t : String) : Int do f(t) end
end|}
        in
        Alcotest.(check (list string)) "sort-conflict" [ "sort-conflict" ] rs);

    (* `_ > 0` on a Float subject: [fp_rewrite] declines (only one side is
       float-sorted), so the term still mentions a float outside an `fp.*`
       comparison and [float_wellsorted] abandons the VC.
       Mutation that fails this: make [float_wellsorted] return [true] always —
       the goal is emitted, the solver runs, and the reason becomes
       [solver-undecided]. *)
    Alcotest.test_case "a Float/Int comparison is filed as float-sort-gate" `Quick
      (fun () ->
        let rs =
          skip_reasons
            {|mod RS3 do
  fn f(x : {Float | _ > 0}) : Float do x end
  fn go(y : Float) : Float do f(y) end
end|}
        in
        Alcotest.(check (list string)) "float-sort-gate" [ "float-sort-gate" ] rs);

    (* The genuine solver outcome, with a CONTROL.  Without the control this
       test would pass on a z3-less machine for the wrong reason: with no
       solver EVERY obligation falls through to [Solver_undecided].  The
       control — the same call under a guard that discharges it — can only be
       [Proved] when a solver actually ran and decided, so the pair together
       says "z3 ran, and on the unguarded call it declined".
       Mutation that fails this: replace the final `| _ -> note (Skipped
       Solver_undecided)` arm with any other reason. *)
    gated "a genuinely undecided obligation is filed as solver-undecided" (fun () ->
        let control =
          {|mod RS4b do
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) > 0 do head(ys) else 0 end
  end
end|}
        in
        Alcotest.(check (list string)) "the control is decided, not skipped" []
          (skip_reasons control);
        let rs =
          skip_reasons
            {|mod RS4 do
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do head(ys) end
end|}
        in
        Alcotest.(check (list string)) "solver-undecided" [ "solver-undecided" ] rs);

    (* [Alias_withdrawn] is checked in [alias_attribution_suite] through the
       `cap verified` MESSAGE text, which is the user-facing surface.  It is
       also re-attributed in the LEDGER (see [note] in refine_check.ml), and
       `--refine-report` prints the ledger, so a ledger that disagreed with the
       diagnostic would be a second thing to be confused by.  Pin the ledger
       side directly, including that it is not left as [solver-undecided].
       Mutation that fails this: move the re-attribution in [note] to after
       [Obligation.record], so only the message is re-attributed. *)
    gated "a withdrawn alias is re-attributed in the LEDGER, not just the message"
      (fun () ->
        let rs =
          skip_reasons
            {|mod RS5 do
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) > 0 do head(ys) else 0 end
  end
end|}
        in
        Alcotest.(check (list string)) "alias-withdrawn" [ "alias-withdrawn" ] rs)
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

(* NOTE ON GATING (same reasoning as [divsafety_hole_suite] below): five of these
   six cases never reach the solver, so gating them on z3 would DISABLE the
   fail-closed tests exactly on the machine where verification is unavailable —
   the one place fail-closed behaviour matters most.  `is_prime` fails at
   REFLECTION ([smt_of] returns None) and the escalation happens in that `None`
   arm, before [Refine.discharge] is ever called; the two scoping cases and the
   message case ride the same arm.
   The one genuine exception is "a PROVED obligation stays silent": with no
   solver every obligation falls through to [Solver_undecided], which under
   `cap verified` escalates to an error, so that case asserts silence that only
   a real solver can produce.  It stays [gated].
   Verified empirically by running this group with z3 removed from PATH:
     env PATH=/usr/bin:/bin ./_build/default/test/test_refinecheck.exe \
       test cap-verified -e *)
let cap_verified_suite =
  [ Alcotest.test_case "cap verified: an unreflectable predicate is an ERROR" `Quick
      (fun () ->
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
    Alcotest.test_case "WITHOUT cap verified the same skip stays silent" `Quick
      (fun () ->
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
    Alcotest.test_case "cap verified does NOT reach into a nested ordinary module"
      `Quick (fun () ->
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
    Alcotest.test_case "a nested cap verified module opts in without leaking to siblings"
      `Quick (fun () ->
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
    Alcotest.test_case
      "the cap verified error names the predicate, the callee and the reason" `Quick
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

(* ── Division-safety: discharge before rejecting ───────────────────────────
   Closing the unreflectable-refinement hole (above) over-corrected: the new
   arm rejected predicates that DO entail `d != 0` and that z3 decides
   instantly, because [division_safety]'s own [smt_of] refused non-literal
   multiplication.  It also fell back to a syntactic path check that ignored
   NEGATED path conditions, while the reflectable arm beside it handled them.
   These pin both fixes — and, critically, the control that neither fix
   reopens the hole.

   GATING: the first case genuinely needs z3 (nothing syntactic decides
   `v * v > 0`), so it is [gated].  The other two must NOT be: the control has
   to fail closed precisely when there is no solver, and the negated-guard case
   is decided by [path_proves_nonzero] with no VC built at all. *)
let divsafety_entailment_suite =
  [ gated "a non-linear refinement that entails d != 0 is accepted" (fun () ->
        (* v*v > 0  <=>  v != 0 over the integers. Z3 decides this instantly;
           only division_safety's own linear smt_of refused it. *)
        Alcotest.(check bool) "no error" false
          (has_divsafety_error {|
mod D1 do
  cap no_panic
  fn scale(d : {v : Int | v * v > 0}) : Int do 10 / d end
end|}))
  ; Alcotest.test_case "an unreflectable refinement that proves NOTHING still errors" `Quick
      (fun () ->
        (* The control. Widening must not reopen the hole PR #105 closed. *)
        Alcotest.(check bool) "error" true
          (has_divsafety_error {|
mod D2 do
  cap no_panic
  fn f(n : Int, d : {Int | is_prime(_)}) : Int do n / d end
end|}))
  ; Alcotest.test_case "a negated path condition discharges too" `Quick (fun () ->
      (* The `Some assumption` branch reflects negated path conditions via
         smt_of; the None arm's `path_proves_nonzero` fallback dropped the
         else-branch. The guard alone makes this division unreachable with
         zero. *)
      Alcotest.(check bool) "no error" false
        (has_divsafety_error {|
mod D3 do
  cap no_panic
  fn f(d : {v : Int | v * v > 0}) : Int do
    if d == 0 do 0 else 10 / d end
  end
end|}))
  ]

(* ── Division-safety: a rebound name retires the fact about it ─────────────
   Every channel this pass reads keys on a bare variable NAME — a path
   condition (`d != 0`), a refined parameter (`d : {Int | …}`), a `let` value
   (`let d = …`) — so none of them survives that name being rebound.  The walk
   did not retire ANY of them, and the negated-path fix above doubled the reach
   of that omission: each program below passed `--check` with exit 0 and then
   panicked at run time with "division by zero".

   The `then`-side witness was already broken before that fix; it is the same
   one-line discipline, so it is closed here too rather than left as a known
   hole in a capability that promises the division cannot panic.

   NOT gated: every case is decided before any VC is built (the guard fact is
   retired, so the divisor reaches the unrefined branch and errors), and the
   whole point is fail-closed behaviour — gating would disable these exactly
   where verification is unavailable. *)
let divsafety_shadowing_suite =
  let errors name src = Alcotest.(check bool) name true (has_divsafety_error src) in
  [ Alcotest.test_case "a `let` rebinding the guarded name retires the guard (else side)"
      `Quick (fun () ->
        errors "error" {|
mod S1 do
  cap no_panic
  fn f(d : Int) : Int do
    if d == 0 do 0 else
      let d = 0
      10 / d
    end
  end
end|})
  ; Alcotest.test_case "a `let` rebinding the guarded name retires the guard (then side)"
      `Quick (fun () ->
        (* Pre-existing, not a regression of the negated-path fix — the same
           discipline closes it, so leaving it open would mean `cap no_panic`
           still accepts a literal division by zero. *)
        errors "error" {|
mod S2 do
  cap no_panic
  fn f(d : Int) : Int do
    if d != 0 do
      let d = 0
      10 / d
    else 0 end
  end
end|})
  ; Alcotest.test_case "a lambda parameter shadowing the guarded name retires the guard"
      `Quick (fun () ->
        errors "error" {|
mod S3 do
  cap no_panic
  fn ap(g : (Int) -> Int) : Int do g(0) end
  fn f(d : Int) : Int do
    if d == 0 do 0 else ap(fn d -> 10 / d) end
  end
end|})
  ; Alcotest.test_case "a match binder shadowing the guarded name retires the guard"
      `Quick (fun () ->
        errors "error" {|
mod S4 do
  cap no_panic
  fn f(d : Int, o : Option(Int)) : Int do
    if d == 0 do 0 else
      match o do
        Some(d) -> 10 / d
        None -> 0
      end
    end
  end
end|})
  ; Alcotest.test_case "a lambda parameter shadowing a REFINED parameter retires it"
      `Quick (fun () ->
        (* The parameter channel has the identical hole as the path channel:
           the refinement is about the outer `d`, not the lambda's. *)
        errors "error" {|
mod S5 do
  cap no_panic
  fn ap(g : (Int) -> Int) : Int do g(0) end
  fn f(d : {Int | _ != 0}) : Int do ap(fn d -> 10 / d) end
end|})
  ; Alcotest.test_case "a `let` rebinding a REFINED parameter to zero is caught"
      `Quick (fun () ->
        errors "error" {|
mod S6 do
  cap no_panic
  fn f(d : {Int | _ != 0}) : Int do
    let d = 0
    10 / d
  end
end|})
  ; Alcotest.test_case "an ordinary `let` divisor is still accepted" `Quick (fun () ->
      (* The control: retirement must not swallow the `let` value channel it
         replaces.  `let d = 5` retires the OUTER `d` and records 5 in its
         place, so this stays silent. *)
      Alcotest.(check bool) "no error" false
        (has_divsafety_error {|
mod S7 do
  cap no_panic
  fn f(d : Int) : Int do
    let d = 5
    10 / d
  end
end|}))
  ; Alcotest.test_case "a guard on an unshadowed name still discharges" `Quick (fun () ->
      (* The other control: retirement is per-NAME, so an unrelated binder
         must not retire the guard. *)
      Alcotest.(check bool) "no error" false
        (has_divsafety_error {|
mod S8 do
  cap no_panic
  fn f(d : Int) : Int do
    if d == 0 do 0 else
      let k = 3
      k / d
    end
  end
end|}))
  ]

(* ── Decl-walk coverage ────────────────────────────────────────────────────
   Both obligation-raising walks used to descend only into [DFn] and [DMod] and
   end in `| _ -> ()`, so a capability directive said nothing about code living
   in any other decl form: an `impl` method, a top-level `let`, an actor
   handler, a `test` body.  `cap no_panic` accepted a division by zero that
   crashed at runtime.  These pin the widened walk; the fourth is the control
   that the widening does not make ORDINARY modules noisier. *)
let walk_coverage_suite =
  [ Alcotest.test_case "cap no_panic sees a division inside an impl body" `Quick (fun () ->
      Alcotest.(check bool) "error" true
        (has_divsafety_error {|
mod NP do
  cap no_panic
  type Box = Box(Int)
  interface Runner(a) do
    fn run : a -> Int
  end
  impl Runner(Box) do
    fn run(b) do
      match b do
      Box(n) -> 100 / n
      end
    end
  end
end|}))
  ; Alcotest.test_case "cap no_panic sees a division in a top-level let" `Quick (fun () ->
      Alcotest.(check bool) "error" true
        (has_divsafety_error {|
mod NP2 do
  cap no_panic
  fn zero() : Int do 0 end
  let boom = 100 / zero()
end|}))
    (* NOTE ON THE CONTRACT USED HERE.  The obvious fixture — an impl body
       calling `List.head(xs)` — cannot work: a string fixture prepends no
       standard library, so `List.head` resolves to nothing, carries no
       contract, and raises no obligation no matter how wide the walk is.  It
       would pass before AND after the fix.  The obligation has to come from a
       contract the fixture itself declares, hence module-level `weird`, whose
       `is_prime` predicate is outside the checkable fragment and therefore
       SKIPS — which `cap verified` must escalate to an error. *)
  ; gated "cap verified sees an obligation inside an impl body" (fun () ->
      Alcotest.(check bool) "error" true
        (has_refine_error_d {|
mod CV do
  cap verified
  type Box = Box(Int)
  fn weird(k : {Int | is_prime(_)}) : Int do k end
  interface Runner(a) do
    fn run : a -> Int
  end
  impl Runner(Box) do
    fn run(b) do
      match b do
      Box(n) -> weird(n)
      end
    end
  end
end|}))
  ; gated "an ordinary module is unaffected by the wider walk" (fun () ->
      (* The control. Widening the walk must not make a NON-capability module
         report anything it did not report before: the same skip, without the
         `cap verified` directive, stays silent. *)
      Alcotest.(check bool) "no error" false
        (has_refine_error_d {|
mod Plain do
  type Box = Box(Int)
  fn weird(k : {Int | is_prime(_)}) : Int do k end
  interface Runner(a) do
    fn run : a -> Int
  end
  impl Runner(Box) do
    fn run(b) do
      match b do
      Box(n) -> weird(n)
      end
    end
  end
end|}))

    (* ── Assume-without-check: a contract nothing enforces ────────────────
       Widening the walk made both passes ASSUME an impl method's parameter
       refinements, while [collect_all_defs] still registered only `fn`s — so
       no caller was obliged to establish them.  `--check` exited 0 on the
       program below and it divided by zero at run time.  The predicate must
       either bind the CALLER (when the method name unambiguously denotes this
       contract) or bind NOBODY (when it does not) — never only the body. *)
  ; gated "an impl method's contract obliges its callers" (fun () ->
      Alcotest.(check bool) "error" true
        (has_refine_error_d {|
mod HIC do
  type Box = Box(Int)
  interface Runner(a) do fn run : a -> Int -> Int end
  impl Runner(Box) do
    fn run(b, k : {Int | k != 0}) : Int do
      match b do Box(m) -> m / k end
    end
  end
  fn main() do println(int_to_string(run(Box(4), 0))) end
end|}))
  ; gated "the same call satisfying the impl contract stays silent" (fun () ->
      (* Negative control for the case above: registering impl contracts must
         not reject a call that DOES satisfy them. *)
      Alcotest.(check bool) "no error" false
        (has_refine_error_d {|
mod HICOK do
  type Box = Box(Int)
  interface Runner(a) do fn run : a -> Int -> Int end
  impl Runner(Box) do
    fn run(b, k : {Int | k != 0}) : Int do
      match b do Box(m) -> m / k end
    end
  end
  fn main() do println(int_to_string(run(Box(4), 2))) end
end|}))
  ; Alcotest.test_case
      "an AMBIGUOUS impl method's refinement is assumed by nobody" `Quick (fun () ->
      (* Two impls define `run`, so a call resolved by NAME cannot tell their
         contracts apart and neither is adopted — which must NOT leave the
         bodies free to assume them.  Fail closed: the divisor refinement is
         stripped and `m / k` must prove itself some other way, so
         `cap no_panic` reports it.  Without the strip this exits silently
         while nothing anywhere enforces `k != 0`. *)
      Alcotest.(check bool) "error" true
        (has_divsafety_error {|
mod AMB do
  cap no_panic
  type Box = Box(Int)
  type Cup = Cup(Int)
  interface Runner(a) do fn run : a -> Int -> Int end
  impl Runner(Box) do
    fn run(b, k : {Int | k != 0}) : Int do match b do Box(m) -> m / k end end
  end
  impl Runner(Cup) do
    fn run(c, k : {Int | k != 0}) : Int do match c do Cup(m) -> m / k end end
  end
end|}))
  ; Alcotest.test_case
      "an UNAMBIGUOUS impl method's refinement still discharges its division"
      `Quick (fun () ->
      (* Negative control for the strip: when the contract IS adopted (one impl,
         no `fn` of that name), the divisor refinement is enforced at call sites
         and may therefore be assumed in the body.  Without this, the case above
         could be satisfied by stripping unconditionally. *)
      Alcotest.(check bool) "no error" false
        (has_divsafety_error {|
mod UNAMB do
  cap no_panic
  type Box = Box(Int)
  interface Runner(a) do fn run : a -> Int -> Int end
  impl Runner(Box) do
    fn run(b, k : {Int | k != 0}) : Int do match b do Box(m) -> m / k end end
  end
end|}))

    (* ── Self-module-qualified callee inside an impl body ─────────────────
       `strip_entry_self_qual` had its own `| d -> d` wildcard, so `M.g(...)`
       written inside an `impl` method of the entry module `M` survived
       unstripped and resolved to nothing — silently raising no obligation,
       while the identical call in a sibling `fn` was reported. *)
  ; gated "a self-module-qualified call inside an impl body is checked" (fun () ->
      Alcotest.(check bool) "error" true
        (has_refine_error_d {|
mod OuterB do
  fn g(k : {Int | k > 0}) : Int do k end
  type Box = Box(Int)
  interface I(a) do fn run : a -> Int end
  impl I(Box) do
    fn run(_b) : Int do OuterB.g(0 - 9) end
  end
end|}))

    (* ── One case per descended declaration form ──────────────────────────
       Exhaustiveness over [A.decl] protects against a 25th CONSTRUCTOR; it
       protects nothing against someone deleting an arm's body or "correcting"
       [DDescribe] to recurse through [visit_decls].  Each case below pairs a
       firing program with the same program minus `cap no_panic`, so a test can
       only pass if the arm both walks the body AND respects the capability
       scope. *)
  ; Alcotest.test_case "cap no_panic sees a division in a describe block" `Quick (fun () ->
      (* THE case for the deliberate departure from the brief: a `describe`
         block carries no `cap` directive of its own, so recursing through
         [visit_decls]/[check_decls] would re-derive the flag from the inner
         decl list and silently disable checking inside every describe. *)
      Alcotest.(check bool) "error" true
        (has_divsafety_error {|
mod DSC do
  cap no_panic
  fn zero() : Int do 0 end
  describe "arith" do
    test "divides" do
      let d = zero()
      println(int_to_string(100 / d))
    end
  end
end|}))
  ; Alcotest.test_case "a describe block in an ordinary module stays silent" `Quick (fun () ->
      Alcotest.(check bool) "no error" false
        (has_divsafety_error {|
mod DSC2 do
  fn zero() : Int do 0 end
  describe "arith" do
    test "divides" do
      let d = zero()
      println(int_to_string(100 / d))
    end
  end
end|}))
  ; Alcotest.test_case "cap no_panic sees a division in a test body" `Quick (fun () ->
      Alcotest.(check bool) "error" true
        (has_divsafety_error {|
mod TST do
  cap no_panic
  fn zero() : Int do 0 end
  test "divides" do
    let d = zero()
    println(int_to_string(100 / d))
  end
end|}))
  ; Alcotest.test_case "cap no_panic sees a division in setup and setup_all" `Quick (fun () ->
      Alcotest.(check int) "both reported" 2
        (List.length
           (divsafety_error_texts {|
mod STP do
  cap no_panic
  fn zero() : Int do 0 end
  setup do
    println(int_to_string(100 / zero()))
  end
  setup_all do
    println(int_to_string(200 / zero()))
  end
end|})))
  ; Alcotest.test_case "cap no_panic sees a division in an actor handler and init" `Quick
      (fun () ->
      Alcotest.(check int) "both reported" 2
        (List.length
           (divsafety_error_texts {|
mod ACT do
  cap no_panic
  fn zero() : Int do 0 end
  actor Counter do
    state { value : Int }
    init { value: 100 / zero() }

    on Bump(d : Int) do
      { state with value: 200 / d }
    end
  end
end|})))
  ; Alcotest.test_case "an actor in an ordinary module stays silent" `Quick (fun () ->
      Alcotest.(check bool) "no error" false
        (has_divsafety_error {|
mod ACT2 do
  fn zero() : Int do 0 end
  actor Counter do
    state { value : Int }
    init { value: 100 / zero() }

    on Bump(d : Int) do
      { state with value: 200 / d }
    end
  end
end|}))
  ; Alcotest.test_case "cap no_panic sees a division in an interface default body"
      `Quick (fun () ->
      Alcotest.(check bool) "error" true
        (has_divsafety_error {|
mod IFD do
  cap no_panic
  fn zero() : Int do 0 end
  interface Runner(a) do
    fn run : a -> Int do
      100 / zero()
    end
  end
end|}))
  ; Alcotest.test_case "cap no_panic sees a division in every app hook" `Quick (fun () ->
      Alcotest.(check int) "all three reported" 3
        (List.length
           (divsafety_error_texts {|
mod APP do
  cap no_panic
  fn zero() : Int do 0 end
  app Main do
    on_start do
      200 / zero()
    end
    on_stop do
      300 / zero()
    end
    100 / zero()
  end
end|})))
  ]

(* ── A withdrawn measure alias must explain itself ──────────────────────────
   The `List.length` / `String.byte_size` / `string_byte_length` gates are
   unit-global and syntactic BY DESIGN: they resolve doubt by withdrawing the
   alias, which under the default stance costs only a missed proof.  Under
   `cap verified` a missed proof is a hard ERROR, and the error used to read
   "solver-undecided: the solver proved neither the predicate nor its
   negation" — pointing at z3 and at the predicate when the cause was a
   name-shadowing decision taken elsewhere in the unit, possibly in a
   `MARCH_LIB_PATH` dependency the author never opened.  Every remedy that text
   offered ("guard the call", "rewrite the predicate") was one the author had
   already applied.

   These tests pin the ATTRIBUTION, not the suppression: the gates still
   withdraw exactly as before (see [length_alias_suite] / [string_alias_suite]),
   and the last two cases are the ones that matter most — they are what stops
   the fix from relabelling every undischarged obligation as an alias problem. *)
let alias_attribution_suite =
  [ gated "a nested `mod List do fn length` names itself in the cap verified error"
      (fun () ->
        (* Reachable only as `Ver3.Internal.List.length`, and it does NOT win at
           runtime — but the gate is syntactic, so the alias goes anyway. *)
        let msg =
          refine_error_text_d
            {|mod Ver3 do
  cap verified
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) > 0 do head(ys) else 0 end
  end
end|}
        in
        Alcotest.(check bool) "reported at all" true (msg <> "");
        Alcotest.(check bool)
          "does not blame the solver" false
          (contains msg "solver-undecided");
        Alcotest.(check bool)
          "names the withdrawn spelling" true
          (contains msg "List.length"));
    gated "an unrelated Int local named string_byte_length names itself"
      (fun () ->
        let msg =
          refine_error_text_d
            {|mod Ver4 do
  cap verified
  fn first(s : {String | len(_) > 0}) : Int do 0 end
  fn go(t : String) : Int do
    if string_byte_length(t) > 0 do first(t) else 0 end
  end
  fn unrelated(n : Int) : Int do
    let string_byte_length = n + 1
    string_byte_length
  end
end|}
        in
        Alcotest.(check bool) "reported at all" true (msg <> "");
        Alcotest.(check bool)
          "does not blame the solver" false
          (contains msg "solver-undecided");
        Alcotest.(check bool)
          "names the withdrawn spelling" true
          (contains msg "string_byte_length"));
    (* ── THE CONTROLS ─────────────────────────────────────────────────────
       A skip with no withdrawn alias behind it, and a skip in a module that
       DOES have a withdrawn alias but at a call the alias could not have
       helped, must both keep the general message.  Without these, "never says
       solver-undecided" would pass trivially. *)
    gated "a genuinely undecided obligation still says solver-undecided"
      (fun () ->
        let msg =
          refine_error_text_d
            {|mod CtlA do
  cap verified
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do head(ys) end
end|}
        in
        Alcotest.(check bool) "reported at all" true (msg <> "");
        Alcotest.(check bool)
          "still says solver-undecided" true
          (contains msg "solver-undecided"));
    gated "a withdrawn alias is not blamed for an UNGUARDED call"
      (fun () ->
        (* Same competing `mod List` as the first case, so the alias IS
           withdrawn — but this call site never mentions the spelling, so the
           withdrawal cannot be what stopped the proof and must not be named. *)
        let msg =
          refine_error_text_d
            {|mod CtlB do
  cap verified
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do head(ys) end
end|}
        in
        Alcotest.(check bool) "reported at all" true (msg <> "");
        Alcotest.(check bool)
          "still says solver-undecided" true
          (contains msg "solver-undecided");
        Alcotest.(check bool)
          "does not name the alias" false
          (contains msg "alias-withdrawn"));
    (* ── RELEVANCE, not merely presence ───────────────────────────────────
       The controls above only vary "is there a guard at all", and an earlier
       version of this attribution passed them while still blaming a withdrawal
       that was provably not the cause.  Each case below pairs a witness with a
       CONTROL that deletes only the competing binding: if the control is still
       undischarged, the withdrawal cannot have been what stopped the proof,
       and naming it would send the author to rename something irrelevant. *)
    gated "a guard on a DIFFERENT variable is not this obligation's guard"
      (fun () ->
        let prog competing =
          Printf.sprintf
            {|mod WA do
  cap verified
%s
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int), zs : List(Int)) : Int do
    if List.length(zs) > 0 do head(ys) else 0 end
  end
end|}
            competing
        in
        let competing =
          {|  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end|}
        in
        let control = refine_error_text_d (prog "") in
        let witness = refine_error_text_d (prog competing) in
        (* The control proves causal irrelevance: with the alias fully active
           the call is undischarged all the same. *)
        Alcotest.(check bool)
          "control is undischarged too" true
          (contains control "solver-undecided");
        Alcotest.(check bool)
          "so the withdrawal is not blamed" false
          (contains witness "alias-withdrawn");
        Alcotest.(check bool)
          "and the honest message stands" true
          (contains witness "solver-undecided"));
    gated "a withdrawn LIST alias is not blamed for a STRING obligation"
      (fun () ->
        (* All three spellings route to the single measure name `len`, so
           mentioning `len` in the predicate cannot distinguish a list length
           from a string byte length.  The String aliases were never withdrawn
           here; nothing about `List.length` is relevant. *)
        let msg =
          refine_error_text_d
            {|mod WB do
  cap verified
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn first(s : {String | len(_) > 0}) : Int do 0 end
  fn go(t : String, zs : List(Int)) : Int do
    if List.length(zs) > 0 do first(t) else 0 end
  end
end|}
        in
        Alcotest.(check bool) "reported at all" true (msg <> "");
        Alcotest.(check bool)
          "does not name the list alias" false (contains msg "alias-withdrawn");
        Alcotest.(check bool)
          "stays general" true (contains msg "solver-undecided"));
    gated "a NEGATED guard is not read as a guard that proved nothing"
      (fun () ->
        (* `if List.length(ys) > 0 do 0 else head(ys) end` — the guard does not
           fail to prove the predicate, it DISPROVES it.  The control shows the
           genuine bug underneath; the witness must not dress that up as a
           story about a nested module. *)
        let prog competing =
          Printf.sprintf
            {|mod WC do
  cap verified
%s
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) > 0 do 0 else head(ys) end
  end
end|}
            competing
        in
        let control =
          refine_error_text_d (prog "")
        in
        let witness =
          refine_error_text_d
            (prog
               {|  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end|})
        in
        Alcotest.(check bool)
          "the control finds a real violation" true
          (contains control "refinement violation");
        Alcotest.(check bool)
          "so the withdrawal is not blamed" false
          (contains witness "alias-withdrawn"));
    (* ── A guard LAUNDERED through one `let` ──────────────────────────────
       `let n = List.length(ys)` then `if n > 0` is the same author intent as
       guarding directly, and the same withdrawal stopped the same proof — so
       it earns the same attribution.  ONE level only, and every control below
       is a way the laundered walk could attribute WRONGLY rather than merely
       vaguely: through a rebinding of the laundering name, through a rebinding
       of the collection itself, through a different collection, or through a
       second hop. *)
    gated "a guard laundered through one `let` is attributed to the withdrawal"
      (fun () ->
        let msg =
          refine_error_text_d
            {|mod LA1 do
  cap verified
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    let n = List.length(ys)
    if n > 0 do head(ys) else 0 end
  end
end|}
        in
        Alcotest.(check bool) "reported at all" true (msg <> "");
        Alcotest.(check bool)
          "does not blame the solver" false
          (contains msg "solver-undecided");
        Alcotest.(check bool)
          "names the withdrawn spelling" true
          (contains msg "List.length"));
    gated "a lambda param COLLIDING with the laundering name is not evidence"
      (fun () ->
        (* Review probe PE (2026-07-31): the guard's `n` is the lambda's own
           parameter — the guard never uses the laundered length at all, so
           blaming the withdrawal is a WRONG attribution, not a vague one.
           The discard-only [expr_mentions] counted the param as a mention;
           the accepting position must use the free-occurrence check. *)
        let msg =
          refine_error_text_d
            {|mod LA7 do
  cap verified
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn any_pos(xs : List(Int), f : (Int) -> Bool) : Bool do true end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int), zs : List(Int)) : Int do
    let n = List.length(ys)
    if any_pos(zs, fn n -> n > 0) do head(ys) else 0 end
  end
end|}
        in
        Alcotest.(check bool) "reported at all" true (msg <> "");
        Alcotest.(check bool)
          "stays general (solver-undecided)" true
          (contains msg "solver-undecided"));
    gated "a FREE occurrence under a non-colliding binder still attributes"
      (fun () ->
        (* The companion pin: `q > n` inside the lambda is a genuine free use
           of the laundered length, so the attribution must still fire — the
           free-occurrence fix must not over-retire. *)
        let msg =
          refine_error_text_d
            {|mod LA8 do
  cap verified
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn any_over(xs : List(Int), f : (Int) -> Bool) : Bool do true end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int), zs : List(Int)) : Int do
    let n = List.length(ys)
    if any_over(zs, fn q -> q > n) do head(ys) else 0 end
  end
end|}
        in
        Alcotest.(check bool) "reported at all" true (msg <> "");
        Alcotest.(check bool)
          "does not blame the solver" false
          (contains msg "solver-undecided");
        Alcotest.(check bool)
          "names the withdrawn spelling" true
          (contains msg "List.length"));
    gated "a laundered guard on a DIFFERENT collection is not this guard"
      (fun () ->
        (* The laundered analogue of the WA control: the walk must consult
           [expr_applies_to_free] with the ORIGINAL argument (`zs`), never the
           let-bound name — `n` guards `zs`, and the obligation is about
           `ys`. *)
        let msg =
          refine_error_text_d
            {|mod LA2 do
  cap verified
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int), zs : List(Int)) : Int do
    let n = List.length(zs)
    if n > 0 do head(ys) else 0 end
  end
end|}
        in
        Alcotest.(check bool) "reported at all" true (msg <> "");
        Alcotest.(check bool)
          "the withdrawal is not blamed" false (contains msg "alias-withdrawn");
        Alcotest.(check bool)
          "stays general" true (contains msg "solver-undecided"));
    gated "a REBOUND laundering name is not the launder"
      (fun () ->
        (* `let n = 5` between the laundering `let` and the guard: the guard's
           `n` is the literal, not the length.  The fact must retire exactly
           as a path fact would (see [path_shadow]) — surviving it would
           attribute an unrelated comparison to the withdrawal. *)
        let msg =
          refine_error_text_d
            {|mod LA3 do
  cap verified
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    let n = List.length(ys)
    let n = 5
    if n > 0 do head(ys) else 0 end
  end
end|}
        in
        Alcotest.(check bool) "reported at all" true (msg <> "");
        Alcotest.(check bool)
          "the withdrawal is not blamed" false (contains msg "alias-withdrawn");
        Alcotest.(check bool)
          "stays general" true (contains msg "solver-undecided"));
    gated "a REBOUND collection retires the laundered fact"
      (fun () ->
        (* The collection itself rebinds between the `let` and the call: `n`
           measures the OUTER `ys`, the obligation is about the new one.  The
           laundered fact's RHS mentions the rebound name, so it must retire —
           the same both-channels discipline every binding construct already
           applies to [scope] and [path]. *)
        let msg =
          refine_error_text_d
            {|mod LA4 do
  cap verified
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int), zs : List(Int)) : Int do
    let n = List.length(ys)
    let ys = zs
    if n > 0 do head(ys) else 0 end
  end
end|}
        in
        Alcotest.(check bool) "reported at all" true (msg <> "");
        Alcotest.(check bool)
          "the withdrawal is not blamed" false (contains msg "alias-withdrawn");
        Alcotest.(check bool)
          "stays general" true (contains msg "solver-undecided"));
    gated "a NEGATED laundered guard is not read as a guard that proved nothing"
      (fun () ->
        (* The laundered analogue of WC: in the else-branch the guard
           DISPROVES the predicate; the existing polarity gate must apply to
           the laundered walk exactly as to the direct one. *)
        let msg =
          refine_error_text_d
            {|mod LA6 do
  cap verified
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    let n = List.length(ys)
    if n > 0 do 0 else head(ys) end
  end
end|}
        in
        Alcotest.(check bool) "reported at all" true (msg <> "");
        Alcotest.(check bool)
          "the withdrawal is not blamed" false (contains msg "alias-withdrawn"));
    (* Suppression itself is untouched: with nothing competing, the same guarded
       call still PROVES and reports nothing at all. *)
    gated "the guarded call still proves when no alias was withdrawn" (fun () ->
        Alcotest.(check string)
          "silent" ""
          (refine_error_text_d
             {|mod Ok1 do
  cap verified
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) > 0 do head(ys) else 0 end
  end
end|}));
    gated "a guard laundered through a TWO-let chain is attributed to the withdrawal"
      (fun () ->
        let msg =
          refine_error_text_d
            {|mod LA9 do
  cap verified
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    let a = List.length(ys)
    let n = a
    if n > 0 do head(ys) else 0 end
  end
end|}
        in
        Alcotest.(check bool) "reported at all" true (msg <> "");
        Alcotest.(check bool)
          "does not blame the solver" false
          (contains msg "solver-undecided");
        Alcotest.(check bool)
          "names the withdrawn spelling" true
          (contains msg "List.length"));
    gated "a chain that rebinds to something ELSE stays general" (fun () ->
        let msg =
          refine_error_text_d
            {|mod LA10 do
  cap verified
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    let a = List.length(ys)
    let n = 5
    if n > 0 do head(ys) else 0 end
  end
end|}
        in
        Alcotest.(check bool)
          "still falls back to solver-undecided" true
          (contains msg "solver-undecided"));
    gated "a guard's lambda param colliding with the subject name is not evidence"
      (fun () ->
        (* Mirror-image of probe PE (2026-07-31), on the DIRECT path instead of
           the laundered one. The guard's `ys` here is the lambda's own
           parameter — it never applies List.length to the OUTER ys that
           `head`'s argument names. *)
        let msg =
          refine_error_text_d
            {|mod LA11 do
  cap verified
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn check(f : (List(Int)) -> Bool, zs : List(Int)) : Bool do true end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int), zs : List(Int)) : Int do
    if check(fn ys -> List.length(ys) > 0, zs) do head(ys) else 0 end
  end
end|}
        in
        Alcotest.(check bool)
          "stays general (solver-undecided)" true
          (contains msg "solver-undecided"));
    gated "a FREE occurrence of the subject under a non-colliding binder still attributes"
      (fun () ->
        (* Companion control: a genuine free use of the withdrawn spelling
           applied to the real subject, merely sitting inside an unrelated
           lambda, must still attribute -- the fix must not over-retire. *)
        let msg =
          refine_error_text_d
            {|mod LA12 do
  cap verified
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn check(f : (List(Int)) -> Bool, zs : List(Int)) : Bool do true end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int), zs : List(Int)) : Int do
    if check(fn q -> List.length(ys) > 0, zs) do head(ys) else 0 end
  end
end|}
        in
        Alcotest.(check bool) "reported at all" true (msg <> "");
        Alcotest.(check bool)
          "does not blame the solver" false
          (contains msg "solver-undecided"))
  ]

(* ── Composing a LIST contract across a call boundary ───────────────────────
   A refined list parameter's own promise must hold inside its own body, so a
   function requiring a non-empty list can pass that very list on.  The `Int`
   shape composed all along (via [reflect_scalar]'s scope lookup); the list
   shape was SKIPPED, which produces no diagnostic and so looked fine. *)
let compose_suite =
  [ gated "a list contract composes into a call in its own body" (fun () ->
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod LC do
  fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn outer(ys : {List(Int) | len(_) > 0}) : Int do inner(ys) end
  fn main() : Int do outer([1]) end
end|});
        let proved, violated, skips = March_refinecheck.Obligation.summary () in
        (* proved must be 2 -- BOTH the outer([1]) call from main AND the
           inner(ys) call inside outer's body.  If the fix is wired to the wrong
           function (scope_facts, which check_call never consults), this stays
           "1 proved, 1 skipped" -- the exact silent-non-fix this test exists
           to catch. Do not weaken this to "no error"; a skip also produces no
           error, and that is precisely the bug. *)
        Alcotest.(check int) "proved" 2 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "skipped" 0
          (List.fold_left (fun a (_, n) -> a + n) 0 skips))

  ; gated "a WEAKER caller contract does not discharge a stronger callee" (fun () ->
        (* The false-positive control that matters most: the caller promises
           only len >= 0, true of every list, which proves nothing about
           len > 0. If this reports a violation, the loaded fact is stronger
           than the promise. If it PROVES, the fact is being read as the
           callee's own predicate rather than the caller's. Either way the
           assumption is wrong. It must be SKIPPED. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod LW do
  fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn outer(ys : {List(Int) | len(_) >= 0}) : Int do inner(ys) end
  fn main() : Int do outer([1]) end
end|});
        let proved, violated, _ = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "not proved by the weak fact" 1 proved;
        Alcotest.(check int) "violated" 0 violated)

  ; gated "the PARAMETER-NAME spelling of the caller's contract composes too"
      (fun () ->
        (* The third spelling of the refined value: not `_`, not a declared
           binder, but the parameter's OWN name.  All three denote the same
           list, so all three must compose identically.  Until 2026-07-29 the
           assumption side's guard accepted only `_` and the declared binder,
           so this stayed "1 proved, 1 skipped" while the other two spellings
           proved both calls — and a skip emits no diagnostic, so renaming a
           binder to the parameter's name silently unwired composition.  This
           is the third time this exact spelling class has shipped broken in
           this file; the GOAL side was fixed for it on 2026-07-27. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod LP do
  fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn outer(ys : {List(Int) | len(ys) > 0}) : Int do inner(ys) end
  fn main() : Int do outer([1]) end
end|});
        let proved, violated, skips = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "proved" 2 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "skipped" 0
          (List.fold_left (fun a (_, n) -> a + n) 0 skips))

  ; gated "a WEAKER contract in the parameter-name spelling still does not compose"
      (fun () ->
        (* The false-positive control for the case above, and the one that
           proves the widening did not overshoot: the same third spelling, but
           the caller promises only `len(ys) >= 0`, true of every list.  It
           entails nothing about `len > 0`, so the inner call must still be
           SKIPPED — 1 proved, main's `outer([1])` alone.  A proof here would
           mean the loaded fact is not the caller's actual promise. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod LPW do
  fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn outer(ys : {List(Int) | len(ys) >= 0}) : Int do inner(ys) end
  fn main() : Int do outer([1]) end
end|});
        let proved, violated, skips = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "not proved by the weak fact" 1 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "still skipped" 1
          (List.fold_left (fun a (_, n) -> a + n) 0 skips))

  ; gated "rebinding the name retires the list fact" (fun () ->
        (* THE CARDINAL-SIN TEST. `ys` inside the body is a different list after
           the let; the caller's promise says nothing about it. If the outer
           fact survives the rebind, a correct program is reported as
           violating. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error_d {|
mod LS do
  fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn outer(ys : {List(Int) | len(_) > 0}) : Int do
    let ys = List.tail(ys)
    inner(ys)
  end
  fn main() : Int do outer([1, 2]) end
end|}))

  ; gated "a match binder shadowing the name retires the fact" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d {|
mod LM do
  fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn outer(ys : {List(Int) | len(_) > 0}, o : Option(List(Int))) : Int do
    match o do
      Some(ys) -> inner(ys)
      None     -> 0
    end
  end
  fn main() : Int do outer([1], None) end
end|}))
  ]

(* ── Composing a USER ADT `@[measure]` contract across a call boundary ──────
   `len` on a variable reflects to a plain uninterpreted Int constant; an
   AXIOMATISED measure (declared `@[measure]`) reflects the SUBJECT itself into
   an `Smt.SData` datatype term and needs the quantified-axiom preamble attached
   to the VC.  So the list case composing is not by itself evidence that this
   one does — these pin it directly. *)
let compose_adt_suite =
  [ gated "a user ADT measure contract composes" (fun () ->
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod TA do
  type Tree = Leaf | Node(Tree, Int, Tree)
  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> size(l) + 1 + size(r)
    end
  end
  fn inner(t : {Tree | size(_) > 0}) : Int do 1 end
  fn outer(u : {Tree | size(_) > 0}) : Int do inner(u) end
  fn main() : Int do outer(Node(Leaf, 5, Leaf)) end
end|});
        let proved, violated, _ = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "proved" 2 proved;
        Alcotest.(check int) "violated" 0 violated)

  ; gated "an ADT measure in the PARAMETER-NAME spelling composes too" (fun () ->
        (* The axiom-measure equivalent of the list case: the assumption side's
           spelling guard is SHARED between the two measure classes, so the same
           2026-07-29 omission skipped this too.  Pinned separately because an
           axiomatised measure travels a different reflection path (an
           `Smt.SData` datatype term plus the quantified-axiom preamble), so the
           list case passing is not evidence that this one does. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod TP do
  type Tree = Leaf | Node(Tree, Int, Tree)
  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> size(l) + 1 + size(r)
    end
  end
  fn inner(t : {Tree | size(_) > 0}) : Int do 1 end
  fn outer(u : {Tree | size(u) > 0}) : Int do inner(u) end
  fn main() : Int do outer(Node(Leaf, 5, Leaf)) end
end|});
        let proved, violated, skips = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "proved" 2 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "skipped" 0
          (List.fold_left (fun a (_, n) -> a + n) 0 skips))

  ; gated "a WEAKER ADT contract in the parameter-name spelling still skips"
      (fun () ->
        (* Direction control for the case above: `size(u) >= 0` is true of every
           tree and must not discharge `size(_) > 0`. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod TPW do
  type Tree = Leaf | Node(Tree, Int, Tree)
  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> size(l) + 1 + size(r)
    end
  end
  fn inner(t : {Tree | size(_) > 0}) : Int do 1 end
  fn outer(u : {Tree | size(u) >= 0}) : Int do inner(u) end
  fn main() : Int do outer(Node(Leaf, 5, Leaf)) end
end|});
        let proved, violated, skips = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "not proved by the weak fact" 1 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "still skipped" 1
          (List.fold_left (fun a (_, n) -> a + n) 0 skips))

  ; gated "a user ADT fact is retired on rebind, not proved falsely" (fun () ->
        (* THE CARDINAL-SIN TEST.  `let u = Leaf` makes the call genuinely
           violating: `u` inside the body is a different tree, and the caller's
           promise says nothing about it.  If the outer fact survives the rebind,
           this VC comes back PROVED — a wrong proof, silently, which is worse
           than a false positive because nothing surfaces at all.

           What it asserts is therefore `proved = 1` (main's `outer(...)` alone),
           NOT that the violation is reported.  A plain `has_refine_error` is
           false for BOTH a correct skip and a leaked false proof and so cannot
           tell them apart; the count can.

           Reporting the violation is out of reach for a reason that has nothing
           to do with measures or ADTs: this pass does not propagate a LOCAL
           `let`'s value into a later goal for ANY type.  The `Int` analogue
           (`fn outer(u : {Int | _ > 0}) do let u = 0  inner(u) end`) and the
           `List` analogue (`let ys = []`) are both likewise 1 proved / 1
           skipped.  Local-value propagation is separate work; retiring the fact
           is the property under test here, and a skip is its correct outcome. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod TS do
  type Tree = Leaf | Node(Tree, Int, Tree)
  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> size(l) + 1 + size(r)
    end
  end
  fn inner(t : {Tree | size(_) > 0}) : Int do 1 end
  fn outer(u : {Tree | size(_) > 0}) : Int do
    let u = Leaf
    inner(u)
  end
  fn main() : Int do outer(Node(Leaf, 5, Leaf)) end
end|});
        let proved, violated, _ = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "the retired fact proves nothing" 1 proved;
        Alcotest.(check int) "violated" 0 violated)

  ; gated "a WEAKER caller ADT contract does not discharge a stronger callee"
      (fun () ->
        (* The false-positive control: the caller promises only `size(_) >= 0`,
           true of every tree, which proves nothing about `size(_) > 0`.  A
           violation here would mean the loaded fact is stronger than the
           promise; a proof would mean the fact is being read as the callee's own
           predicate.  It must be SKIPPED — 1 proved, main's call alone. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod TW do
  type Tree = Leaf | Node(Tree, Int, Tree)
  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> size(l) + 1 + size(r)
    end
  end
  fn inner(t : {Tree | size(_) > 0}) : Int do 1 end
  fn outer(u : {Tree | size(_) >= 0}) : Int do inner(u) end
  fn main() : Int do outer(Node(Leaf, 5, Leaf)) end
end|});
        let proved, violated, _ = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "not proved by the weak fact" 1 proved;
        Alcotest.(check int) "violated" 0 violated)

  ; gated "an ADT measure contract on the subject itself is now enforced"
      (fun () ->
        (* The direct, composition-free shape this task had to fix first: until
           the self spellings reflected the ACTUAL, `{Tree | size(_) > 0}`
           enforced nothing — BOTH of these were skipped.  An accept-only
           witness cannot tell a working contract from one that checks nothing,
           so both directions are pinned. *)
        let prog arg =
          Printf.sprintf {|
mod TD do
  type Tree = Leaf | Node(Tree, Int, Tree)
  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> size(l) + 1 + size(r)
    end
  end
  fn inner(t : {Tree | size(_) > 0}) : Int do 1 end
  fn main() : Int do inner(%s) end
end|} arg
        in
        Alcotest.(check bool) "Node is accepted" false
          (has_refine_error_d (prog "Node(Leaf, 5, Leaf)"));
        Alcotest.(check bool) "Leaf is rejected" true
          (has_refine_error_d (prog "Leaf")))
  ]

(* ── Composing a CONSTRUCTOR-TAG contract across a call boundary ────────────
   The tester analogue of [compose_suite]/[compose_adt_suite].  A refined ADT
   parameter whose contract is a MEASURE composed into its own body once
   [load_scope_measure_facts] existed; the identically-shaped TAG contract
   (`{Option(Int) | is_Some(_)}`) did not, because [reflect_dt]'s `EVar` arm
   declares a fresh UNCONSTRAINED datatype constant for a bare caller-scope
   name and nothing consulted the scope channel for the tag the caller's own
   signature already promises.  The result was "1 proved, 1 skipped" — and a
   skip emits no diagnostic, so it read as success.

   Every case below asserts the obligation COUNTS.  A skip and a proof both
   compile clean; only the counts tell them apart. *)
let compose_tag_suite =
  let summary () = March_refinecheck.Obligation.summary () in
  let skip_count skips = List.fold_left (fun a (_, n) -> a + n) 0 skips in
  [ gated "a constructor-tag contract composes into a call in its own body"
      (fun () ->
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod TC do
  fn inner(o : {Option(Int) | is_Some(_)}) : Int do 0 end
  fn outer(p : {Option(Int) | is_Some(_)}) : Int do inner(p) end
  fn main() : Int do outer(Some(1)) end
end|});
        let proved, violated, skips = summary () in
        (* 2 = main's `outer(Some(1))` AND `inner(p)` inside outer's body. *)
        Alcotest.(check int) "proved" 2 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "skipped" 0 (skip_count skips))

  ; gated "the NAMED-BINDER spelling of a tag contract composes too" (fun () ->
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod TCB do
  fn inner(o : {Option(Int) | is_Some(_)}) : Int do 0 end
  fn outer(p : {v : Option(Int) | is_Some(v)}) : Int do inner(p) end
  fn main() : Int do outer(Some(1)) end
end|});
        let proved, violated, skips = summary () in
        Alcotest.(check int) "proved" 2 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "skipped" 0 (skip_count skips))

  ; gated "the PARAMETER-NAME spelling of a tag contract composes too" (fun () ->
        (* The third spelling of the refined value: not `_`, not a declared
           binder, but the parameter's OWN name.  All three denote the same
           value and must compose identically.  This spelling class has shipped
           broken three separate times in refine_check.ml — twice on the measure
           assumption side, once on the goal side — and each time the symptom
           was silence, not a failure. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod TCP do
  fn inner(o : {Option(Int) | is_Some(_)}) : Int do 0 end
  fn outer(p : {Option(Int) | is_Some(p)}) : Int do inner(p) end
  fn main() : Int do outer(Some(1)) end
end|});
        let proved, violated, skips = summary () in
        Alcotest.(check int) "proved" 2 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "skipped" 0 (skip_count skips))

  ; gated "a DIFFERENT constructor in the caller's contract does not compose"
      (fun () ->
        (* The direction control.  The caller promises `is_None(_)`; the callee
           wants `is_Some(_)`.  Assuming the caller's own promise verbatim WOULD
           be sound and would make this a reported violation (the two testers
           are exclusive on `Option`), but the loader deliberately fires only
           when the caller already promises the GOAL's constructor: that is the
           narrowest claim that discharges the goal, and a missed report costs
           nothing while a wrong fact is the failure this subsystem exists to
           prevent.  So: 1 proved (main's call alone), 1 skipped — and in
           particular NOT falsely proved. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod TCN do
  fn inner(o : {Option(Int) | is_Some(_)}) : Int do 0 end
  fn outer(p : {Option(Int) | is_None(_)}) : Int do inner(p) end
  fn main() : Int do outer(None) end
end|});
        let proved, violated, skips = summary () in
        Alcotest.(check int) "not proved by the other tag" 1 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "still skipped" 1 (skip_count skips))

  ; gated "rebinding the name retires the tag fact" (fun () ->
        (* THE CARDINAL-SIN TEST.  After `let p = None` the name denotes a
           different value and the caller's promise says nothing about it.  If
           the outer fact survived the rebind this would come back 2 proved —
           a WRONG proof, of a call that genuinely violates `inner`'s
           precondition, with nothing surfaced at all.

           The assertion is `proved = 1`, not "the violation is reported":
           reporting it would need the local `let`'s VALUE propagated into a
           later goal, which this pass does not do for ANY type (the Int and
           List analogues are likewise 1 proved / 1 skipped — see the
           corresponding note in [compose_adt_suite]).  Retiring the fact is
           the property under test; a skip is its correct outcome. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod TCS do
  fn inner(o : {Option(Int) | is_Some(_)}) : Int do 0 end
  fn outer(p : {Option(Int) | is_Some(_)}) : Int do
    let p = None
    inner(p)
  end
  fn main() : Int do outer(Some(1)) end
end|});
        let proved, violated, skips = summary () in
        Alcotest.(check int) "the retired fact proves nothing" 1 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "skipped" 1 (skip_count skips))

  ; gated "a match binder shadowing the name retires the tag fact" (fun () ->
        (* Same property through the other binding construct: the arm's `p`
           is the payload of `q`, not the refined parameter. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod TCM do
  fn inner(o : {Option(Int) | is_Some(_)}) : Int do 0 end
  fn outer(p : {Option(Int) | is_Some(_)}, q : Option(Option(Int))) : Int do
    match q do
      Some(p) -> inner(p)
      None    -> 0
    end
  end
  fn main() : Int do outer(Some(1), None) end
end|});
        let proved, violated, skips = summary () in
        Alcotest.(check int) "the shadowed fact proves nothing" 1 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "skipped" 1 (skip_count skips))
  ]

(* ── A refined `let` annotation is CHECKED against its bound expression ──────

   Before this suite, [scope_add_binding]'s annotated arm admitted a `let`'s
   refinement into scope UNCONDITIONALLY — `A.PatVar n, Some r -> (n.A.txt, r)
   :: sc` — so an annotation was a promise the author made and the checker
   believed.  `let ys : {List(Int) | len(_) > 0} = []` was not merely unproven,
   it was PROVED, and the downstream call rode a manufactured fact.  Under
   `cap verified`, whose whole premise is "if it compiles, it is proved", that
   is a hole punched through the premise by ordinary non-adversarial code.

   Every case below asserts obligation COUNTS rather than the presence of a
   diagnostic, and records the count it measured BEFORE the fix.  That is not
   ceremony: [has_refine_error_d] is true for a `cap verified` escalation of a
   *skip* exactly as much as for a real violation, so `check bool … true` can
   pass for precisely the wrong reason — and `check bool … false` cannot tell
   "correctly skipped now" from "still falsely proved".  Both mistakes were
   present in this suite's first draft and were caught only by measuring. *)
let let_annotation_suite =
  let summary () = March_refinecheck.Obligation.summary () in
  let skip_count skips = List.fold_left (fun a (_, n) -> a + n) 0 skips in
  [ gated "a false let annotation is REPORTED, not trusted" (fun () ->
        (* PRE-FIX: 1 proved, 0 violated, 0 skipped — the `inner(ys)` call
           falsely proved off the trusted annotation, `--check` exit 0. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod LA1 do
  fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn outer() : Int do
    let ys : {List(Int) | len(_) > 0} = []
    inner(ys)
  end
  fn main() : Int do outer() end
end|});
        let _, violated, _ = summary () in
        Alcotest.(check int) "the false annotation is violated" 1 violated)

  ; gated "a false let annotation at the LET-NAME spelling" (fun () ->
        (* The same bug with the predicate spelled using the bound name rather
           than `_`.  PRE-FIX: 1 proved, 0 violated — also falsely proved.
           This is the spelling the synthesis is most likely to drop, because
           it is the one that must resolve through [param_names]. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod LA1b do
  fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn outer() : Int do
    let ys : {List(Int) | len(ys) > 0} = []
    inner(ys)
  end
  fn main() : Int do outer() end
end|});
        let _, violated, _ = summary () in
        Alcotest.(check int) "violated" 1 violated)

  ; gated "a false let annotation at the DECLARED-BINDER spelling" (fun () ->
        (* Third spelling: `{v : T | pred(v)}`.  PRE-FIX: 1 proved, 0 violated.
           All three spellings denote the same value and must behave
           identically; this exact spelling class has shipped broken three
           separate times elsewhere in refine_check.ml, each time silently. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod LA1c do
  fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn outer() : Int do
    let ys : {v : List(Int) | len(v) > 0} = []
    inner(ys)
  end
  fn main() : Int do outer() end
end|});
        let _, violated, _ = summary () in
        Alcotest.(check int) "violated" 1 violated)

  ; gated "a false let annotation at Int, not just List" (fun () ->
        (* PRE-FIX: 1 proved, 0 violated — falsely proved, exit 0.
           Deliberately written at `_ > 0`.  Do NOT write this at
           `{Int | n > 0}` over `let n`: that spelling measures 0 proved,
           0 violated, 1 skipped and ALREADY exits 1 today via the
           cap-verified skip escalation, so asserting an error on it would
           pass before the fix existed and prove nothing. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod LA4 do
  fn inner(n : {Int | _ > 0}) : Int do 0 end
  fn outer() : Int do
    let m : {Int | _ > 0} = 0 - 5
    inner(m)
  end
  fn main() : Int do outer() end
end|});
        let _, violated, _ = summary () in
        Alcotest.(check int) "violated" 1 violated)

  ; gated "a TRUE let annotation proves, and still composes" (fun () ->
        (* The false-positive control AND the interaction check with the
           composition work landed in PR #121/#126.  PRE-FIX: 1 proved (the
           trusted call alone).  POST-FIX must be 2 — the annotation
           obligation proving on its own merits, AND the checked fact still
           composing into `inner(ys)`.  Asserting `proved >= 1` here would be
           vacuous; exactly 2 is the assertion with teeth. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod LA2 do
  fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn outer() : Int do
    let ys : {List(Int) | len(_) > 0} = [1]
    inner(ys)
  end
  fn main() : Int do outer() end
end|});
        let proved, violated, skips = summary () in
        Alcotest.(check int) "both obligations prove" 2 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "skipped" 0 (skip_count skips))

  ; gated "an unreflectable RHS is SKIPPED, never reported" (fun () ->
        (* THE CARDINAL-SIN CONTROL.  "Cannot prove" must not become "reports
           a violation": this task adds a new obligation-raising site, so an
           inverted definite-failure stance would turn every undecidable
           annotation into a false positive.  PRE-FIX this measures 1 proved
           (falsely).  POST-FIX: 0 proved, 0 violated, and TWO skips — nothing
           manufactured, nothing reported.  A bare "no error" assertion cannot
           separate those two states, which is why this asserts counts.

           Two skips, not one, and the second is the point: the annotation
           itself is undecidable here, so it grants no fact, so `inner(ys)` —
           which used to be Proved off that ungranted premise — is now
           undischarged too.  A proof standing on an unverified assumption is
           precisely what this change removes. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod LA3 do
  fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(zs : List(Int)) : Int do
    let ys : {List(Int) | len(_) > 0} = zs
    inner(ys)
  end
  fn main() : Int do go([1]) end
end|});
        let proved, violated, skips = summary () in
        Alcotest.(check int) "never reported" 0 violated;
        Alcotest.(check int) "nothing manufactured" 0 proved;
        Alcotest.(check int) "both obligations skipped" 2 (skip_count skips))

  ; gated "the named-Int annotation, previously unresolved, is now caught" (fun () ->
        (* A SECOND, SEPARATE gap that this change CLOSES as a side effect.
           PRE-FIX `{Int | n > 0}` over `let n` resolved against nothing and
           was merely skipped (0 proved, 0 violated, 1 skipped) — the sole
           spelling that was not even trusted, just inert.  Routing the check
           through [param_names] = [the let name] makes `n` denote the bound
           value, so `0 - 5` is now seen and the annotation is REPORTED.
           That is a genuine violation, not a false positive: the annotation
           claims `n > 0` of the value -5.
           The trailing skip is the downstream `inner(n)`, which no longer
           rides the unproven annotation. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod LA6 do
  fn inner(n : {Int | _ > 0}) : Int do 0 end
  fn outer() : Int do
    let n : {Int | n > 0} = 0 - 5
    inner(n)
  end
  fn main() : Int do outer() end
end|});
        let proved, violated, _ = summary () in
        Alcotest.(check int) "no false proof" 0 proved;
        Alcotest.(check int) "the false annotation is now caught" 1 violated)
  ]

let postcond_ledger_suite =
  let summary () = March_refinecheck.Obligation.summary () in
  let skip_count skips = List.fold_left (fun a (_, n) -> a + n) 0 skips in
  [ gated "a PROVED postcondition is recorded" (fun () ->
        (* PRE-FIX: 0 proved, 0 violated, 0 skipped — check_post records
           nothing at all, so a function whose entire contract is its return
           type is invisible to --refine-report. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod PL1 do
  fn mk() : {Int | _ > 0} do 100 end
  fn main() : Int do mk() end
end|});
        let proved, violated, _ = summary () in
        Alcotest.(check int) "the postcondition proves" 1 proved;
        Alcotest.(check int) "violated" 0 violated)

  ; gated "a VIOLATED postcondition is recorded" (fun () ->
        (* PRE-FIX: 0 proved, 0 violated, 0 skipped, but exit 1 — the error
           IS emitted, it just never reaches the ledger. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod PL2 do
  fn mk() : {Int | _ > 0} do 0 - 5 end
  fn main() : Int do mk() end
end|});
        let _, violated, _ = summary () in
        Alcotest.(check int) "violated" 1 violated)

  ; gated "an UNDECIDABLE postcondition is recorded as skipped" (fun () ->
        (* PRE-FIX: 0 proved, 0 violated, 0 skipped, exit 0. This is the case
           Task 3 will escalate; it must be countable first. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod PL3 do
  fn mk(z : Int) : {Int | _ > 0} do z end
  fn main() : Int do mk(1) end
end|});
        let proved, violated, skips = summary () in
        Alcotest.(check int) "proved" 0 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "skipped" 1 (skip_count skips))

  ; gated "a postcondition is recorded ONCE, not twice" (fun () ->
        (* THE DOUBLE-COUNT GUARD. check_fn_post_verdict runs twice per
           refined-return function: once from gate_unverified_posts with
           ~emit:false (the propagation gate pre-pass) and once from
           check_fn_post during the walk with emit=true. Recording in
           check_post unconditionally counts every postcondition twice.
           Without this case that bug ships and only shows up as inflated
           --refine-report totals nobody cross-checks. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod PL4 do
  fn mk() : {Int | _ > 0} do 100 end
  fn main() : Int do mk() end
end|});
        let proved, _, _ = summary () in
        Alcotest.(check int) "exactly one record" 1 proved)

  ; gated "a precondition and a postcondition are both counted" (fun () ->
        (* Interaction: the two paths are independent and must not clobber
           one another. 2 = mk's return refinement + take_pos's precondition. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod PL5 do
  fn take_pos(n : {Int | _ > 0}) : Int do n end
  fn mk() : {Int | _ > 0} do 100 end
  fn main() : Int do take_pos(mk()) end
end|});
        let proved, violated, _ = summary () in
        Alcotest.(check int) "both counted" 2 proved;
        Alcotest.(check int) "violated" 0 violated)
  ]

(* ── `@[trusted]` (Task 2) ──────────────────────────────────────────────────
   A per-function escape hatch from `cap verified`'s escalation: an obligation
   the checker cannot discharge inside a `@[trusted]` function is accepted as
   an ASSERTION, recorded as its own [Trusted] verdict, rather than forcing the
   author to drop `cap verified` for the whole module.  Deliberately loud (see
   [Obligation.Trusted]) and deliberately narrow: it must never suppress a
   [Violated] and must never leak to a sibling function. *)
let trusted_suite =
  let summary_full () = March_refinecheck.Obligation.all () in
  let count_trusted () =
    List.length (List.filter (fun (o : March_refinecheck.Obligation.t) ->
      o.verdict = March_refinecheck.Obligation.Trusted) (summary_full ()))
  in
  [ gated "@[trusted] suppresses a cap-verified skip" (fun () ->
        (* PRE-FIX: exit 1 — the skip is escalated and there is no way out
           short of dropping cap verified for the whole module. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error_d {|
mod TR1 do
  cap verified
  fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  @[trusted]
  fn go(zs : List(Int)) : Int do inner(zs) end
  fn main() : Int do go([1]) end
end|}))

  ; gated "a trusted obligation is NOT counted as proved" (fun () ->
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod TR2 do
  cap verified
  fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  @[trusted]
  fn go(zs : List(Int)) : Int do inner(zs) end
  fn main() : Int do go([1]) end
end|});
        let proved, _, _ = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "not laundered into proved" 0 proved;
        Alcotest.(check int) "counted as trusted" 1 (count_trusted ()))

  ; gated "@[trusted] does NOT suppress a definite violation" (fun () ->
        (* The load-bearing limit. A predicate that can never hold is a bug in
           the annotation; waving it through would make @[trusted] a way to
           ship known-false contracts. *)
        Alcotest.(check bool) "still errors" true
          (has_refine_error_d {|
mod TR3 do
  cap verified
  fn inner(n : {Int | _ > 0}) : Int do n end
  @[trusted]
  fn go() : Int do inner(0 - 5) end
  fn main() : Int do go() end
end|}))

  ; gated "@[trusted] is scoped to its own function" (fun () ->
        (* A sibling function in the same cap verified module must still be
           strict — otherwise one annotation silently disarms the module. *)
        Alcotest.(check bool) "sibling still errors" true
          (has_refine_error_d {|
mod TR4 do
  cap verified
  fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  @[trusted]
  fn ok(zs : List(Int)) : Int do inner(zs) end
  fn not_ok(ws : List(Int)) : Int do inner(ws) end
  fn main() : Int do ok([1]) + not_ok([1]) end
end|}))

  ; (* Step 5: an attribute that silently does nothing is exactly the failure
       mode this subsystem keeps producing (Tasks 4/5). No solver needed —
       this fires before any obligation is even checked — so unlike the four
       cases above this one is NOT gated on z3. *)
    Alcotest.test_case "@[trusted] without cap verified warns that it does nothing"
      `Quick (fun () ->
        Alcotest.(check bool) "warns" true
          (has_refine_warning {|
mod TR5 do
  fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  @[trusted]
  fn go(zs : List(Int)) : Int do inner(zs) end
  fn main() : Int do go([1]) end
end|}))
  ]

let postcond_strict_suite =
  [ gated "cap verified escalates an undischarged postcondition" (fun () ->
        (* PRE-FIX: exit 0 — silently permitted. This is the last place a fact
           is granted without obliging anyone. *)
        Alcotest.(check bool) "errors" true
          (has_refine_error_d {|
mod PS1 do
  cap verified
  fn mk(z : Int) : {Int | _ > 0} do z end
  fn main() : Int do mk(1) end
end|}))

  ; gated "a PROVED postcondition under cap verified stays silent" (fun () ->
        (* The false-positive control. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error_d {|
mod PS2 do
  cap verified
  fn mk() : {Int | _ > 0} do 100 end
  fn main() : Int do mk() end
end|}))

  ; gated "@[trusted] rescues an undischarged postcondition" (fun () ->
        (* Arc A's payoff: the escape hatch has to reach the newly-strict
           obligations, or Task 3 makes cap verified less adoptable. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error_d {|
mod PS3 do
  cap verified
  @[trusted]
  fn mk(z : Int) : {Int | _ > 0} do z end
  fn main() : Int do mk(1) end
end|}))

  ; gated "a non-cap-verified module is unaffected" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error_d {|
mod PS4 do
  fn mk(z : Int) : {Int | _ > 0} do z end
  fn main() : Int do mk(1) end
end|}))
  ]

(* Task 4: a QUALIFIED spelling inside a predicate (`List.length(_)`) parses
   and typechecks, but predicates are never desugared, so `List.length` stays
   an `EField` chain rather than the dotted `EVar` the measure alias keys on
   — the contract enforces NOTHING, silently.  This suite pins a WARNING
   (not an error — the module still compiles) naming both the qualified
   spelling found and the bare spelling that would actually work. *)
let qualified_pred_suite =
  [ gated "a qualified spelling in a predicate warns" (fun () ->
        (* PRE-FIX: silent. The contract parses, typechecks, and enforces
           NOTHING, because predicates are never desugared so List.length
           stays an EField chain rather than the dotted EVar the alias keys
           on. Looks like it works; doesn't. *)
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod QP1 do
  fn inner(xs : {List(Int) | List.length(_) > 0}) : Int do 0 end
  fn main() : Int do inner([1]) end
end|}));
        let msgs = ctx.March_errors.Errors.diagnostics in
        (* Pin the SUGGESTION, not just the spelling. `contains m "len"` would
           be vacuous here — "len" is a substring of "List.length", so that
           conjunct is implied by the first and the test would stay green if
           the remedy said `length`, or said nothing at all. Match the whole
           remedy clause instead. *)
        Alcotest.(check bool) "warns about the qualified spelling" true
          (List.exists (fun (d : March_errors.Errors.diagnostic) ->
             let m = d.March_errors.Errors.message in
             contains m "List.length"
             && contains m "Use the bare spelling `len` instead") msgs))

  ; gated "the bare spelling does NOT warn" (fun () ->
        (* The false-positive control: the supported spelling must stay quiet. *)
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod QP2 do
  fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn main() : Int do inner([1]) end
end|}));
        Alcotest.(check int) "no diagnostics" 0
          (List.length (ctx.March_errors.Errors.diagnostics)))

  ; gated "a WITHDRAWN alias still suggests `len`, not the last segment" (fun () ->
        (* A competing `List.length` withdraws the alias, so `measure_alias`
           returns None. Deriving the suggestion from the last dotted segment
           there yields `length` — NOT predicate vocabulary, so following the
           advice just swaps this warning for the unknown-name one and the
           contract still enforces nothing. The remedy must not depend on
           whether the alias is currently withdrawn. *)
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod QP3 do
  mod List do
    fn length(xs : List(Int)) : Int do 0 end
  end
  fn inner(xs : {List(Int) | List.length(_) > 0}) : Int do 0 end
  fn main() : Int do inner([1]) end
end|}));
        let msgs = ctx.March_errors.Errors.diagnostics in
        let qualified_warnings =
          List.filter
            (fun (d : March_errors.Errors.diagnostic) ->
              contains d.March_errors.Errors.message "qualified call")
            msgs
        in
        Alcotest.(check bool) "still suggests `len`" true
          (List.exists
             (fun (d : March_errors.Errors.diagnostic) ->
               contains d.March_errors.Errors.message
                 "Use the bare spelling `len` instead")
             qualified_warnings);
        Alcotest.(check bool) "never suggests `length`" false
          (List.exists
             (fun (d : March_errors.Errors.diagnostic) ->
               contains d.March_errors.Errors.message
                 "Use the bare spelling `length` instead")
             qualified_warnings))

  ; gated "a record FIELD call is not reported as a qualified call" (fun () ->
        (* `c.cb(1)` is a field call on a value, not a qualified call on a
           module. It enforces nothing either way (`smt_of` has no arm for an
           applied field access), but calling it "qualified" and offering the
           field name as a "bare spelling" is wrong on both counts — a false
           explanation costs more than silence. `qualified_name` therefore
           mirrors desugar's `flatten_module_path`, which bottoms out at an
           uppercase `ECon` and never at a bare `EVar`. *)
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod QP4 do
  type Cfg = { port : Int, cb : (Int) -> Int }
  fn ok(c : {Cfg | c.cb(1) > 0}) : Int do c.port end
  fn main() : Int do 0 end
end|}));
        Alcotest.(check int) "no qualified-call warning" 0
          (List.length
             (List.filter
                (fun (d : March_errors.Errors.diagnostic) ->
                  contains d.March_errors.Errors.message "qualified call")
                ctx.March_errors.Errors.diagnostics)))
  ]

let iface_refine_suite =
  [ gated "a refinement in an interface signature is diagnosed" (fun () ->
        (* PRE-FIX: silent. It obliges no call site AND assumes nothing, so it
           is a missing check rather than an unsound one -- but it silently
           does nothing, which is the failure mode this area keeps producing.
           The supported spelling is a refinement on the corresponding impl
           method's OWN SIGNATURE -- stated that way, not as "the impl
           parameter", because the two positions are enforced under different
           conditions: a return refinement there is always checked, while a
           parameter one is enforced only when the method name is unambiguous
           (adoptable_impl_methods). *)
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod IR1 do
  interface Runner(a) do
    fn run : a -> {Int | _ > 0} -> Int
  end
  fn main() : Int do 0 end
end|}));
        let msgs = ctx.March_errors.Errors.diagnostics in
        Alcotest.(check bool) "diagnosed" true
          (List.exists (fun (d : March_errors.Errors.diagnostic) ->
             contains d.March_errors.Errors.message "impl") msgs);
        (* `contains m "impl"` alone is weak — "impl" is a substring of plenty
           of unrelated prose, so it would stay green if the remedy drifted to
           something useless. Pin the two clauses that make the advice
           ACTIONABLE, and the naming of the method. *)
        Alcotest.(check bool) "names the method" true
          (List.exists (fun (d : March_errors.Errors.diagnostic) ->
             contains d.March_errors.Errors.message "`run`") msgs);
        Alcotest.(check bool) "remedy names the impl method's own signature" true
          (List.exists (fun (d : March_errors.Errors.diagnostic) ->
             contains d.March_errors.Errors.message
               "Write the refinement on the corresponding `impl` method's own signature")
            msgs);
        (* The parameter half of the remedy is CONDITIONAL — an impl parameter
           refinement is only enforced when [adoptable_impl_methods] adopts the
           name. Stating it unconditionally would send an author with an
           ambiguous method name from one silent no-op to another, so the
           caveat is part of the contract this test pins. *)
        Alcotest.(check bool) "remedy states the adoption caveat" true
          (List.exists (fun (d : March_errors.Errors.diagnostic) ->
             contains d.March_errors.Errors.message "when the method name is unambiguous")
            msgs))

  ; gated "a RETURN-position interface refinement is diagnosed too" (fun () ->
        (* The return position is as inert as a parameter, and the remedy must
           still be right for it — which is why the message covers the return
           type explicitly rather than naming only the impl PARAMETER
           spelling. *)
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod IR3 do
  interface Sizer(a) do
    fn size : a -> {Int | _ >= 0}
  end
  fn main() : Int do 0 end
end|}));
        let msgs = ctx.March_errors.Errors.diagnostics in
        Alcotest.(check bool) "diagnosed" true
          (List.exists (fun (d : March_errors.Errors.diagnostic) ->
             contains d.March_errors.Errors.message "`size`") msgs);
        Alcotest.(check bool) "remedy covers the return position" true
          (List.exists (fun (d : March_errors.Errors.diagnostic) ->
             contains d.March_errors.Errors.message "return type is always checked") msgs))

  ; gated "a refinement on an `impl` method is NOT reported as inert" (fun () ->
        (* False-positive control, and the sharper half of the pair: the walk
           must fire on a genuine `interface` method SIGNATURE only. An `impl`
           method's parameter refinement is the very spelling the warning
           recommends — warning on it too would be self-contradictory advice.
           `bump` is adoptable here (one impl defines it, no top-level `fn`
           owns the name), so the contract really is enforced -- confirmed
           end-to-end by `specs/lang/types/accept/t137`, whose sibling probe
           `bump(Box(1), 0 - 5)` is a refinement ERROR. *)
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod IR4 do
  interface Bumper(a) do
    fn bump : a -> Int -> Int
  end
  type Box = Box(Int)
  impl Bumper(Box) do
    fn bump(_b : Box, n : {Int | _ > 0}) : Int do n end
  end
  fn main() : Int do 0 end
end|}));
        Alcotest.(check int) "no inert-signature warning" 0
          (List.length
             (List.filter
                (fun (d : March_errors.Errors.diagnostic) ->
                  contains d.March_errors.Errors.message "enforces nothing: an interface")
                ctx.March_errors.Errors.diagnostics)))

  ; gated "an unrefined interface signature stays quiet" (fun () ->
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod IR2 do
  interface Runner(a) do
    fn run : a -> Int -> Int
  end
  fn main() : Int do 0 end
end|}));
        Alcotest.(check int) "no diagnostics" 0
          (List.length (ctx.March_errors.Errors.diagnostics)))
  ]

(* ── `sig` / `extern` signature refinements ────────────────────────────────
   The same silent-no-op shape as `iface_refine_suite`, in the two other decl
   forms that carry a `ty` the checker never reads.  Both were probed silent
   before the fix: `--check` on either fixture exited 0 with ZERO diagnostics.

   These assert over `ctx.diagnostics` directly rather than through
   `refine_error_text_d`, which filters to `Error` severity and would therefore
   be green on both sides of a fix that ships a WARNING — pinning nothing. *)
let sig_extern_refine_suite =
  [ gated "a refinement in a `sig` signature is diagnosed" (fun () ->
        (* PRE-FIX: silent. `sig_fns`' types were never walked. *)
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod SR1 do
  sig Store do
    fn put : Int -> {Int | _ > 0}
  end
  fn main() : Int do 0 end
end|}));
        let msgs = ctx.March_errors.Errors.diagnostics in
        Alcotest.(check bool) "names the signature function" true
          (List.exists (fun (d : March_errors.Errors.diagnostic) ->
             contains d.March_errors.Errors.message "`put`") msgs);
        (* Naming the enclosing `sig` too: a module may declare several, and
           "`put` enforces nothing" is not locatable without it. *)
        Alcotest.(check bool) "names the enclosing sig" true
          (List.exists (fun (d : March_errors.Errors.diagnostic) ->
             contains d.March_errors.Errors.message "`sig Store`") msgs);
        (* The remedy must be the sig-specific one, NOT the interface message's
           "put it on the `impl` method" — there is no impl here and that
           advice would be actively wrong. *)
        Alcotest.(check bool) "remedy names the module's own `fn` definition" true
          (List.exists (fun (d : March_errors.Errors.diagnostic) ->
             contains d.March_errors.Errors.message
               "Write the refinement on the module's own `fn` definition") msgs);
        Alcotest.(check bool) "does not give the interface remedy" false
          (List.exists (fun (d : March_errors.Errors.diagnostic) ->
             contains d.March_errors.Errors.message
               "corresponding `impl` method's own signature") msgs))

  ; gated "a refinement in an `extern` signature is diagnosed" (fun () ->
        (* The plan's fixture for this case did not compile: it wrote
           `Cap(IO.FileSystem)` with no `needs`, which `--check` rejects with
           two hard errors before refinecheck is reached.  Corrected to
           `needs IO.Foreign` + `Cap(IO.Foreign)`, matching
           `specs/lang/types/accept/t139`. *)
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod SR2 do
  needs IO.Foreign

  extern "c" : Cap(IO.Foreign) do
    fn take(n : {Int | _ > 0}) : Int = "take"
  end
  fn main() : Int do 0 end
end|}));
        let msgs = ctx.March_errors.Errors.diagnostics in
        Alcotest.(check bool) "names the extern function" true
          (List.exists (fun (d : March_errors.Errors.diagnostic) ->
             contains d.March_errors.Errors.message "`take`") msgs);
        (* The extern reason is NOT the sig reason. A foreign return refinement
           is unverifiable in principle, not merely unwalked, so the message
           must say the callee is not March code — advice that told the author
           to move the predicate somewhere it would be "checked" is wrong for
           the return position. *)
        Alcotest.(check bool) "states the callee is not March code" true
          (List.exists (fun (d : March_errors.Errors.diagnostic) ->
             contains d.March_errors.Errors.message "the callee is not March code") msgs);
        Alcotest.(check bool) "remedy names a March wrapper" true
          (List.exists (fun (d : March_errors.Errors.diagnostic) ->
             contains d.March_errors.Errors.message "Wrap the extern in a March `fn`") msgs))

  ; gated "a RETURN-position `extern` refinement is diagnosed too" (fun () ->
        (* `ef_ret_ty` is a separate field from `ef_params`; a detector that
           only walked the parameters would be green on the case above and
           silent here. *)
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod SR4 do
  needs IO.Foreign

  extern "c" : Cap(IO.Foreign) do
    fn count(s : String) : {Int | _ >= 0} = "strlen"
  end
  fn main() : Int do 0 end
end|}));
        Alcotest.(check bool) "diagnosed" true
          (List.exists (fun (d : March_errors.Errors.diagnostic) ->
             contains d.March_errors.Errors.message "`count`")
            ctx.March_errors.Errors.diagnostics))

  ; gated "an UNREFINED sig signature stays quiet" (fun () ->
        (* The false-positive control: it must be the REFINEMENT that fires,
           not the mere presence of a `sig`. Green on both sides of the fix. *)
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod SR3 do
  sig Store do
    fn put : Int -> Int
  end
  fn main() : Int do 0 end
end|}));
        Alcotest.(check int) "no diagnostics" 0
          (List.length ctx.March_errors.Errors.diagnostics))

  ; gated "an UNREFINED extern signature stays quiet" (fun () ->
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod SR5 do
  needs IO.Foreign

  extern "c" : Cap(IO.Foreign) do
    fn count(s : String) : Int = "strlen"
  end
  fn main() : Int do 0 end
end|}));
        Alcotest.(check int) "no diagnostics" 0
          (List.length ctx.March_errors.Errors.diagnostics))
  ]

(* ── `use` competes with an impl method for its name ───────────────────────
   [adoptable_impl_methods] counted only the decls it could SEE defining a
   name — sibling `fn`s and other `impl`s — so a `use Other.{run}` beside
   `impl Runner(Box) do fn run` left `run` looking unambiguous and its contract
   was adopted.  A call the import resolves elsewhere was then checked against
   a predicate it never touches: the false positive this subsystem must never
   have.

   EVERY case here asserts obligation COUNTS, not the presence or absence of a
   diagnostic, because withdrawal is SILENT and so is a satisfied contract.  A
   withdrawn method registers no signature at all, so the call site raises no
   obligation and the ledger is EMPTY — that zero is the whole assertion, and
   `has_refine_error_d` returning false cannot distinguish it from a proof. *)
let total_obligations () =
  List.length (March_refinecheck.Obligation.all ())

let use_adoption_suite =
  [ gated "a `use`-imported name of the same spelling withdraws adoption" (fun () ->
        (* The `use` binds a bare `run` in exactly the scope the impl method is
           callable from, so `run(Box(4), 0)` may not denote this contract. No
           obligation may be raised for it. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod UAD do
  use Other.{run}
  type Box = Box(Int)
  interface Runner(a) do fn run : a -> Int -> Int end
  impl Runner(Box) do
    fn run(b, k : {Int | k != 0}) : Int do
      match b do Box(m) -> m / k end
    end
  end
  fn main() do println(int_to_string(run(Box(4), 0))) end
end|});
        Alcotest.(check int) "no obligation raised at all" 0 (total_obligations ()))

  ; gated "the SAME program without the `use` still adopts the contract" (fun () ->
        (* The non-vacuity anchor for every zero above. Identical source minus
           one line: the contract IS adopted, the call IS obliged, and the
           violation IS found. Without this, the tests above could pass because
           the fixture never produced an obligation in the first place. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod UADC do
  type Box = Box(Int)
  interface Runner(a) do fn run : a -> Int -> Int end
  impl Runner(Box) do
    fn run(b, k : {Int | k != 0}) : Int do
      match b do Box(m) -> m / k end
    end
  end
  fn main() do println(int_to_string(run(Box(4), 0))) end
end|});
        Alcotest.(check int) "one obligation" 1 (total_obligations ());
        let _, violated, _ = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "violated" 1 violated)

  ; gated "a `use` naming SOMETHING ELSE does not withdraw adoption" (fun () ->
        (* The over-shoot control. Failing closed on an enumerated selector must
           mean "this name is imported", not "some import exists". If this drops
           to 0 the rule has become `any DUse withdraws everything`, which would
           make the withdrawal tests above pass for the wrong reason. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod UADN do
  use Other.{helper}
  type Box = Box(Int)
  interface Runner(a) do fn run : a -> Int -> Int end
  impl Runner(Box) do
    fn run(b, k : {Int | k != 0}) : Int do
      match b do Box(m) -> m / k end
    end
  end
  fn main() do println(int_to_string(run(Box(4), 0))) end
end|});
        Alcotest.(check int) "still obliged" 1 (total_obligations ()))

  ; gated "a glob `use` withdraws adoption — the import set is unknowable here"
      (fun () ->
        (* `use Other.*` names a module this pass cannot see, so whether it
           binds `run` is undecidable at this point. Fail CLOSED: withdraw. The
           cost is silence; the alternative is a false positive. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod UADG do
  use Other.*
  type Box = Box(Int)
  interface Runner(a) do fn run : a -> Int -> Int end
  impl Runner(Box) do
    fn run(b, k : {Int | k != 0}) : Int do
      match b do Box(m) -> m / k end
    end
  end
  fn main() do println(int_to_string(run(Box(4), 0))) end
end|});
        Alcotest.(check int) "no obligation raised at all" 0 (total_obligations ()))

  ; gated "a bare `import Other` withdraws adoption too" (fun () ->
        (* `import Mod` with no selector parses to the SAME UseAll as
           `use Mod.*` (parser.mly, import_path_tail's empty alternative) — the
           Elixir-style spelling is the one real programs use, and reading only
           `use ... .*` would leave it open. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod UADI do
  import Other
  type Box = Box(Int)
  interface Runner(a) do fn run : a -> Int -> Int end
  impl Runner(Box) do
    fn run(b, k : {Int | k != 0}) : Int do
      match b do Box(m) -> m / k end
    end
  end
  fn main() do println(int_to_string(run(Box(4), 0))) end
end|});
        Alcotest.(check int) "no obligation raised at all" 0 (total_obligations ()))

  ; gated "a selector-less `use Other` keeps adoption" (fun () ->
        (* `use Other` (UseSingle) binds the MODULE, not any bare name, so it
           competes with nothing. Second over-shoot control, and the one that
           pins the UseSingle arm specifically: deleting it would make this 0. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod UADS do
  use Other
  type Box = Box(Int)
  interface Runner(a) do fn run : a -> Int -> Int end
  impl Runner(Box) do
    fn run(b, k : {Int | k != 0}) : Int do
      match b do Box(m) -> m / k end
    end
  end
  fn main() do println(int_to_string(run(Box(4), 0))) end
end|});
        Alcotest.(check int) "still obliged" 1 (total_obligations ()))

    (* Not [gated]: this half needs no solver, and gating a fail-closed test
       would disable it exactly on the machines where verification is
       unavailable. *)
  ; Alcotest.test_case
      "a `use`-withdrawn impl method may not ASSUME its own refinement" `Quick
      (fun () ->
        (* Withdrawal must be symmetric. If the contract binds no caller, the
           BODY may not treat it as a fact either — otherwise `m / k` is
           discharged by a predicate nothing enforces, which is the
           assume-without-check hole that made an earlier widening unsound.
           [Division_safety] consults [adoptable_impl_methods] directly, so this
           also pins that the two passes did not drift apart. *)
        Alcotest.(check bool) "error" true
          (has_divsafety_error {|
mod UADD do
  cap no_panic
  use Other.{run}
  type Box = Box(Int)
  interface Runner(a) do fn run : a -> Int -> Int end
  impl Runner(Box) do
    fn run(b, k : {Int | k != 0}) : Int do match b do Box(m) -> m / k end end
  end
end|}))

  ; Alcotest.test_case
      "without the `use` the same division is still discharged" `Quick (fun () ->
        (* Negative control for the strip: an adopted contract IS enforced at
           call sites, so its body may assume it. Without this the case above
           could be satisfied by stripping unconditionally. *)
        Alcotest.(check bool) "no error" false
          (has_divsafety_error {|
mod UADDC do
  cap no_panic
  type Box = Box(Int)
  interface Runner(a) do fn run : a -> Int -> Int end
  impl Runner(Box) do
    fn run(b, k : {Int | k != 0}) : Int do match b do Box(m) -> m / k end end
  end
end|}))
  ]

(* ── A nested `use` must not be shadowed by an enclosing contract ──────────
   [resolve_call]'s step 1 (lexical enclosing-module lookup) used to run
   BEFORE step 3 (`use`-imported names), so a call inside a module that
   `use`-imports a name was checked against an ENCLOSING module's
   same-named function — a contract the call never actually dispatches to
   at runtime.  That is a false positive on correct code, the one failure
   this subsystem must never have.

   The fix must not introduce the mirror-image bug: an ENCLOSING module's
   `use` must not be allowed to beat an INNER module's own definition — see
   case 3.  `ctx.uses` inherits into nested modules while declaration-list
   competition does not, so the fix has to be scope-aware: at each level of
   the modpath walk, consult that level's own `use`s before falling
   outward.

   EVERY case asserts obligation COUNTS via [total_obligations] /
   [Obligation.summary], not the presence of a diagnostic — modeled on
   [use_adoption_suite] above, since a correctly-resolved call and a
   silently-skipped one are both quiet. *)
(* ── A caller's own refinement must survive mentioning another name ────────

   Filed as "`len` facts don't propagate", which measurement refuted: `len` is
   incidental. Four shapes distinguish the real defect —

     A  `{Int | _ < n}` forwarded to a callee with the same contract   was: skipped
     B  `{List(Int) | len(_) > 0}` forwarded likewise                  was: PROVED
     C  `{Int | _ < len(xs)}` forwarded likewise                       was: skipped
     D  A's fact arriving as a PATH GUARD instead                      was: PROVED

   B proves, so measure composition works. D proves, so the solver, the
   cross-parameter goal reflection and the VC machinery all work. A and C differ
   from D only in the CHANNEL the fact arrives through: `reflect_scalar`'s
   assumption-side resolver mapped every non-binder name to None, so ONE foreign
   name discarded the whole predicate and the VC carried nothing but its negated
   goal.

   Every case asserts the LEDGER, never silence — a skip and a proof are
   indistinguishable from outside, which is the confusion the ledger exists to
   end. B and D are kept as regression guards precisely because they already
   passed: a fix that broke them would otherwise look like a win. *)
let ledger_of src =
  March_refinecheck.Obligation.reset ();
  let err = has_refine_error_d src in
  let proved, violated, skips = March_refinecheck.Obligation.summary () in
  (err, proved, violated, List.fold_left (fun a (_, n) -> a + n) 0 skips)

let check_ledger label ~proved ~skipped src =
  let (err, p, v, s) = ledger_of src in
  Alcotest.(check bool) (label ^ ": no error") false err;
  Alcotest.(check int) (label ^ ": proved") proved p;
  Alcotest.(check int) (label ^ ": violated") 0 v;
  Alcotest.(check int) (label ^ ": skipped") skipped s

let caller_promise_suite =
  [ gated "A: a cross-parameter scalar contract composes" (fun () ->
        check_ledger "A" ~proved:1 ~skipped:0 {|
mod CPA do
  fn at(n : Int, i : {Int | _ < n}) : Int do i end
  fn pick(n : Int, i : {Int | _ < n}) : Int do at(n, i) end
end|});

    gated "C: a cross-parameter MEASURE contract composes" (fun () ->
        check_ledger "C" ~proved:1 ~skipped:0 {|
mod CPC do
  fn at(xs : List(Int), i : {Int | _ < len(xs)}) : Int do i end
  fn pick(xs : List(Int), i : {Int | _ < len(xs)}) : Int do at(xs, i) end
end|});

    gated "B: a self-measure contract still composes (regression)" (fun () ->
        check_ledger "B" ~proved:1 ~skipped:0 {|
mod CPB do
  fn need(ys : {List(Int) | len(_) > 0}) : Int do 1 end
  fn fwd(ys : {List(Int) | len(_) > 0}) : Int do need(ys) end
end|});

    gated "D: the same fact via a path guard still composes (regression)" (fun () ->
        check_ledger "D" ~proved:1 ~skipped:0 {|
mod CPD do
  fn at(n : Int, i : {Int | _ < n}) : Int do i end
  fn go(n : Int, i : Int) : Int do
    if i < n do at(n, i) else 0 end
  end
end|});

    (* REJECT WITNESS. A caller that promises NOTHING about `i` must still be
       skipped. If this starts proving, the fix is laundering the goal rather
       than carrying a fact — the failure mode that makes a contract look
       enforced while checking nothing. *)
    gated "REJECT: an unpromised caller is still not proved" (fun () ->
        check_ledger "unpromised" ~proved:0 ~skipped:1 {|
mod CPR do
  fn at(n : Int, i : {Int | _ < n}) : Int do i end
  fn bad(n : Int, i : Int) : Int do at(n, i) end
end|});

    (* REJECT WITNESS. The name the promise mentions is REBOUND before the call,
       so the outer fact says nothing about the value actually passed.
       Attributing an outer fact to an inner binding is the cardinal false
       positive this subsystem keeps re-introducing. *)
    gated "REJECT: a shadowed name does not borrow the outer fact" (fun () ->
        check_ledger "shadowed" ~proved:0 ~skipped:1 {|
mod CPS do
  fn at(n : Int, i : {Int | _ < n}) : Int do i end
  fn bad(n : Int, i : {Int | _ < n}) : Int do
    let n = 0
    at(n, i)
  end
end|});
  ]

(* ── An earlier arm's failure narrows the later arms ───────────────────────
   The safe-wrapper idiom — match the empty case, return Err, do the real work
   in the other arm — is what every standard library is full of, and until this
   it carried permanent unprovable debt: the `_` arm could not see that `Nil`
   had been excluded, so a `len > 0` precondition in it never discharged. It
   also produced actively WRONG advice, because `forge refine` could discharge
   that debt by proposing `{List(a) | len(_) > 0}` — forbidding the exact input
   the function exists to accept.

   Two pieces, and neither works alone: reaching a later arm pushes
   `not is_Ctor(s)` for each earlier arm whose failure is decided purely by the
   tag, and a tag test on a LIST translates onto the same `len$x` symbol the
   goal uses (`is_Nil(xs) <-> len(xs) = 0`).

   The REJECT witnesses below are the load-bearing half. An earlier arm can fail
   with its tag still matching — via a guard, or a refutable sub-pattern — and
   concluding anything from those would be unsound. *)
let arm_exclusion_suite =
  [ gated "the `_` arm knows the empty case was excluded" (fun () ->
        check_ledger "safe-wrapper" ~proved:1 ~skipped:0 {|
mod AE1 do
  fn mean_of(xs : {List(Int) | len(_) > 0}) : Int do 1 end
  fn mean_safe(xs : List(Int)) : Result(Int, String) do
    match xs do
      Nil -> Err("empty")
      _   -> Ok(mean_of(xs))
    end
  end
end|});

    gated "a Cons arm knows the list is non-empty" (fun () ->
        check_ledger "cons-arm" ~proved:1 ~skipped:0 {|
mod AE2 do
  fn mean_of(xs : {List(Int) | len(_) > 0}) : Int do 1 end
  fn go(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(_, _) -> mean_of(xs)
    end
  end
end|});

    (* REJECT WITNESS. The earlier arm carries a GUARD, so reaching the later arm
       does not mean the tag differed — the guard may simply have been false with
       `Nil` matching. Concluding `len > 0` here would be unsound. *)
    gated "REJECT: a guarded earlier arm excludes nothing" (fun () ->
        check_ledger "guarded" ~proved:0 ~skipped:1 {|
mod AE3 do
  fn mean_of(xs : {List(Int) | len(_) > 0}) : Int do 1 end
  fn go(xs : List(Int), flag : Bool) : Int do
    match xs do
      Nil when flag -> 0
      _ -> mean_of(xs)
    end
  end
end|});

    (* REJECT WITNESS. The earlier arm's sub-pattern is refutable, so it can fail
       with the tag still matching: `Cons(0, _)` does not match `Cons(1, [])`,
       which is nonetheless a Cons. *)
    gated "REJECT: a refutable sub-pattern excludes nothing" (fun () ->
        check_ledger "refutable" ~proved:0 ~skipped:1 {|
mod AE4 do
  fn tail_of(xs : {List(Int) | len(_) > 0}) : Int do 1 end
  fn go(xs : List(Int)) : Int do
    match xs do
      Cons(0, _) -> 0
      _ -> tail_of(xs)
    end
  end
end|});

    (* REJECT WITNESS. The arm REBINDS the scrutinee's name, so the narrowing
       would be recorded against a different value entirely. *)
    gated "REJECT: an arm rebinding the scrutinee excludes nothing" (fun () ->
        check_ledger "rebound" ~proved:0 ~skipped:1 {|
mod AE5 do
  fn mean_of(xs : {List(Int) | len(_) > 0}) : Int do 1 end
  fn go(ys : List(Int)) : Int do
    match ys do
      Nil -> 0
      ys -> mean_of(ys)
    end
  end
end|});
  ]

let resolve_precedence_suite =
  [ gated "a nested `use` beats an enclosing contract of the same name (the fix)"
      (fun () ->
        (* `Inner.go`'s `run(7, 0)` dispatches to `Other.run` (unrefined) at
           runtime, per the `MARCH_LIB_PATH` ground-truth fixture. Pre-fix,
           step 1 resolved it to the ENCLOSING `run` (`k != 0`) instead and
           raised+violated an obligation against a contract this call never
           touches. Post-fix: no obligation at all. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod RPN1 do
  mod Other do fn run(a : Int, k : Int) : Int do a / k end end
  fn run(a : Int, k : {Int | k != 0}) : Int do a / k end
  mod Inner do
    use Other.{run}
    fn go() : Int do run(7, 0) end
  end
end|});
        Alcotest.(check int) "no obligation raised against the enclosing contract"
          0 (total_obligations ()))

  ; gated "CONTROL: with no `use`, the enclosing contract still applies" (fun () ->
        (* Must NOT regress: absent any shadowing import, the nearest
           enclosing definition is still the right resolution, and a
           violating call is still caught. Green on both sides of the fix. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod RPN2 do
  fn run(a : Int, k : {Int | k != 0}) : Int do a / k end
  mod Inner do
    fn go() : Int do run(7, 0) end
  end
end|});
        Alcotest.(check int) "one obligation" 1 (total_obligations ());
        let _, violated, _ = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "violated" 1 violated)

  ; gated "CONTROL: an outer module's `use` must not beat an inner module's own def"
      (fun () ->
        (* The mirror-image direction the naive "move step 3 first" fix would
           have broken. The OUTER (top-level) scope imports `run` via `use`;
           `Inner` defines its OWN refined `run`. `Inner.go`'s call must
           still resolve to Inner's own definition — declaration-list
           competition (nearest enclosing def) already got this right before
           the fix (defs are consulted across every prefix before uses), so
           this must stay green on both sides. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod RPN3 do
  mod Other do fn run(a : Int, k : Int) : Int do a / k end end
  use Other.{run}
  mod Inner do
    fn run(a : Int, k : {Int | k != 0}) : Int do a / k end
    fn go() : Int do run(7, 0) end
  end
end|});
        Alcotest.(check int) "one obligation" 1 (total_obligations ());
        let _, violated, _ = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "violated" 1 violated)

  ; gated "CONTROL: a selector-less `use Other` binds the module, not the bare name"
      (fun () ->
        (* `use Other` (no `.{...}` selector) parses to `UseSingle`, which
           binds the module name itself, not any bare function name — so it
           competes with nothing and the enclosing contract still applies.
           Green on both sides; pins the `UseSingle` arm specifically. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod RPN4 do
  mod Other do fn run(a : Int, k : Int) : Int do a / k end end
  fn run(a : Int, k : {Int | k != 0}) : Int do a / k end
  mod Inner do
    use Other
    fn go() : Int do run(7, 0) end
  end
end|});
        Alcotest.(check int) "one obligation" 1 (total_obligations ());
        let _, violated, _ = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "violated" 1 violated)
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
      ("obligation-reasons", reason_suite);
      ("cap-verified", cap_verified_suite);
      ("alias-attribution", alias_attribution_suite);
      ("divsafety-hole", divsafety_hole_suite);
      ("divsafety-entailment", divsafety_entailment_suite);
      ("divsafety-shadowing", divsafety_shadowing_suite);
      ("walk-coverage", walk_coverage_suite);
      ("compose", compose_suite);
      ("compose-adt", compose_adt_suite);
      ("compose-tag", compose_tag_suite);
      ("let-annotation", let_annotation_suite);
      ("postcond-ledger", postcond_ledger_suite);
      ("trusted", trusted_suite);
      ("postcond-strict", postcond_strict_suite);
      ("qualified-predicate", qualified_pred_suite);
      ("interface-signature-refinement", iface_refine_suite);
      ("sig-extern-refinement", sig_extern_refine_suite);
      ("use-impl-adoption", use_adoption_suite);
      ("resolve-precedence", resolve_precedence_suite);
      ("caller-promise", caller_promise_suite);
      ("arm-exclusion", arm_exclusion_suite) ]
