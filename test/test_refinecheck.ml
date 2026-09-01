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

    (* Until counterexample surfacing, this was "conservatively skipped": the
       solver can refute `n >= 0` for SOME n but not for ALL n, and a raw
       model was not trusted.  The witness validator now EXECUTES the model
       (f(-1) returns -1), so the identity body is a confirmed violation. *)
    gated "unconstrained return with a confirmed witness is rejected" (fun () ->
        Alcotest.(check bool) "error" true
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
       false and reports correct code.  Under counterexample surfacing this
       program DOES error — but via an EXECUTED witness (f(-1, 0) really
       returns 0), never via the conflated definitely-false reading.  The
       witness sentence in the message is what distinguishes the two: the
       misattribution bug produced the bare definite-violation report. *)
    gated "a named return binder colliding with a parameter is not misattributed" (fun () ->
        let text =
          refine_error_text_d
            (post
               "  fn f(v : Int, k : Int) : {v : Int | v > 0} do\n\
               \    if v < 0 do k else 1 end\n\
               \  end") in
        Alcotest.(check bool) "reported via an executed witness" true
          (contains text "but f("));

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
    (* Was "unknown value skipped conservatively" before counterexample
       surfacing: `{ count: x }` with x unconstrained is a confirmed
       violation at x = -1, and the witness validator can execute records. *)
    gated "record postcondition: confirmed witness on an unknown value" (fun () ->
        Alcotest.(check bool) "has error" true (has_refine_error skip_src));
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
        (* `score`'s declared `_ < 0` is TRUE (helper returns -x²-1) but
           unprovable: `helper(x)` is opaque to the definition-side check,
           and the witness battery finds no violating input.  An unproven
           postcondition stays legal at the definition and must NOT travel
           to call sites — believing it at `takepos(score(5))` would let a
           fact nobody proved discharge (or flag) the call. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod Stale do\n\
             \  fn helper(x : Int) : Int do 0 - (x * x) - 1 end\n\
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
        (* `_ < n` is TRUE (blackbox returns n - 1) but not provable from an
           unanalysable body — and the witness battery finds no violating
           input — so the gate clears it and callers learn nothing.  The
           Tier 0 guarantee, inherited. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod M do
  fn blackbox(n : Int) : Int do n - 1 end
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
        (* `x * x + 1 >= 1` is TRUE but unprovable (nonlinear), so the
           postcondition stays unproven without being witness-confirmable —
           the original `{ port: x }` body became a confirmed def-site
           violation once counterexample surfacing landed, which is a
           different property than the propagation gating pinned here. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error
             {|mod T do
  type Cfg = { port : Int }
  fn mk_bad(x : Int) : {v : Cfg | v.port >= 1} do { port: x * x + 1 } end
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

    (* An unguarded call, with a CONTROL.  Without the control this test would
       pass on a z3-less machine for the wrong reason: with no solver EVERY
       obligation falls through to a skip.  The control — the same call under
       a guard that discharges it — can only be [Proved] when a solver
       actually ran and decided, so the pair together says "z3 ran, and on
       the unguarded call it declined".

       Before [Undecided.diagnose] existed this fell all the way through to
       [Solver_undecided]; now it is caught earlier and more precisely: `ys`
       appears in no assumption at all, which is exactly
       [Unconstrained_subject]'s shape.  This is the legitimate reclassification
       Task 1 exists to make — see [Undecided.diagnose]'s unconstrained branch
       for the check, and the "an unconstrained subject is diagnosed" case
       above for its dedicated fixture.  The genuine [Solver_undecided]
       residual (constrained, still undecided) is pinned separately by "a
       constrained-but-undecided subject is not called unconstrained", above.
       Mutation that fails THIS test: return [None] from [Undecided.diagnose]
       unconditionally — the slug reverts to "solver-undecided". *)
    gated "an unguarded call is diagnosed as unconstrained, not solver-undecided" (fun () ->
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
        Alcotest.(check (list string)) "unconstrained-subject" [ "unconstrained-subject" ] rs);

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
        Alcotest.(check (list string)) "alias-withdrawn" [ "alias-withdrawn" ] rs);

    (* Nothing in scope mentions `n` at all, so no assumption constrains it.
       This is the single most common shape in the corpus and used to be
       indistinguishable from a solver that merely ran out of road.
       Mutation that fails this: return `None` from [Undecided.diagnose]'s
       unconstrained branch — the slug reverts to "solver-undecided". *)
    gated "an unconstrained subject is diagnosed, not filed solver-undecided"
      (fun () ->
        let rs =
          skip_reasons
            {|mod UD1 do
  fn take_n(n : {Int | _ > 0}) : Int do n end
  fn go(k : Int) : Int do take_n(k) end
end|}
        in
        Alcotest.(check (list string)) "unconstrained-subject"
          [ "unconstrained-subject" ] rs);

    (* CONTROL for the above: the same call with a fact about `k` in scope is
       NOT unconstrained.  Without this control the test above passes even if
       [diagnose] returns Unconstrained_subject unconditionally, which would
       mislabel every skip in the compiler. *)
    gated "a constrained-but-undecided subject is not called unconstrained"
      (fun () ->
        let rs =
          skip_reasons
            {|mod UD1b do
  fn take_n(n : {Int | _ > 0}) : Int do n end
  fn go(k : Int) : Int do
    if k > -5 do take_n(k) else 0 end
  end
end|}
        in
        Alcotest.(check bool) "not unconstrained" false
          (List.mem "unconstrained-subject" rs))

    (* A third variant, [Nonlinear_goal], was drafted here and cut: the only
       [smt_of] used to build a goal never produces [Smt.Mul] for two
       non-literal operands, so a fixture like `pos(a * b)` never reaches
       [Undecided.diagnose] at all -- it fails earlier as
       [Unreflectable_predicate].  Making it reachable needs [smt_of] itself
       to reflect general multiplication, which is a checker PRECISION change
       out of scope here.  See lib/refinecheck/obligation.ml's [reason] type
       comment for the full account. *)
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
(* A record FIELD as the actual argument of a refined parameter.  `r.count` is
   an ordinary pure read of an immutable record, and a guard on it is the same
   evidence a guard on a plain local is — but the argument side used to reflect
   through [smt_of]'s DEFAULT field resolver, which always answers None, so the
   whole goal came out unreflectable and the obligation was skipped in silence.
   The guard and the goal must meet on ONE symbol for the proof to close, which
   is what these two cases pin: the guarded call verifies, and the UNguarded
   one is still reported (so the first is not passing because field access
   quietly proves everything). *)
let field_actual_suite =
  [ gated "a guarded record field discharges a precondition" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod F1 do\n\
             \  cap verified\n\
             \  type Acct = { rem : Int }\n\
             \  fn takepos(k : {Int | _ >= 0}) : Int do k end\n\
             \  fn go(a : Acct) : Int do\n\
             \    if a.rem >= 0 do takepos(a.rem) else 0 end\n\
             \  end\n\
              end\n"));

    gated "an UNguarded record field is still reported" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod F2 do\n\
             \  cap verified\n\
             \  type Acct = { rem : Int }\n\
             \  fn takepos(k : {Int | _ >= 0}) : Int do k end\n\
             \  fn go(a : Acct) : Int do takepos(a.rem) end\n\
              end\n"));

    (* The guard is about a DIFFERENT field, so it proves nothing about this
       one: field symbols must be per-field, not per-record. *)
    gated "a guard on a sibling field proves nothing" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod F3 do\n\
             \  cap verified\n\
             \  type Acct = { rem : Int, other : Int }\n\
             \  fn takepos(k : {Int | _ >= 0}) : Int do k end\n\
             \  fn go(a : Acct) : Int do\n\
             \    if a.other >= 0 do takepos(a.rem) else 0 end\n\
             \  end\n\
              end\n"));
  ]

(* `match cond do true -> … false -> … end` is the same branch on the same
   Bool as `if cond do … else … end`, so it must establish the same facts. It
   used to establish NONE: the match path-narrowing only ever fired for
   CONSTRUCTOR patterns over a variable scrutinee, so a Bool-literal arm
   contributed nothing and an obligation the `if` spelling discharges was
   reported as solver-undecided. *)
let bool_match_path_suite =
  [ gated "a true-arm learns its Bool scrutinee holds" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod B1 do\n\
             \  cap verified\n\
             \  fn takepos(k : {Int | _ >= 0}) : Int do k end\n\
             \  fn go(n : Int) : Int do\n\
             \    match n >= 0 do\n\
             \      true -> takepos(n)\n\
             \      false -> 0\n\
             \    end\n\
             \  end\n\
              end\n"));

    (* The negation half: reaching `_` means the guard was false. *)
    gated "a wildcard arm after a true-arm learns the negation" (fun () ->
        Alcotest.(check bool) "no error" false
          (has_refine_error
             "mod B2 do\n\
             \  cap verified\n\
             \  fn takeneg(k : {Int | _ < 0}) : Int do k end\n\
             \  fn go(n : Int) : Int do\n\
             \    match n >= 0 do\n\
             \      true -> 0\n\
             \      _ -> takeneg(n)\n\
             \    end\n\
             \  end\n\
              end\n"));

    (* Guard against proving too much: the arm that does NOT establish the
       fact must still be reported. *)
    gated "the false-arm does not inherit the true-arm's fact" (fun () ->
        Alcotest.(check bool) "error" true
          (has_refine_error
             "mod B3 do\n\
             \  cap verified\n\
             \  fn takepos(k : {Int | _ >= 0}) : Int do k end\n\
             \  fn go(n : Int) : Int do\n\
             \    match n >= 0 do\n\
             \      true -> 0\n\
             \      false -> takepos(n)\n\
             \    end\n\
             \  end\n\
              end\n"));
  ]

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

(* ── Postcondition proof for a NON-MATCH ADT body ──────────────────────────
   [check_post_induction] recognised exactly one clause-body shape: a top-level
   `EMatch` on a structural parameter.  A body that is a bare constructor
   application — the simplest case, no induction needed, just one unfolding of
   the measure's definition — fell through and returned false SILENTLY (Tier 2
   is verdict-only).  A deliberately WRONG postcondition on such a body
   therefore reported `0 proved, 0 violated, 0 skipped`: never attempted, not
   merely undecided.

   The REJECT control is what makes this suite worth anything.  An accept-only
   witness cannot tell "the checker proved it" from "the checker still is not
   looking", because both report no error. *)
let post_nonmatch_body_suite =
  let tree_src body post = Printf.sprintf {|
mod PN do
  type Tree = Leaf | Node(Tree, Int, Tree)

  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end

  fn push(t : Tree, x : Int) : {Tree | %s} do %s end
  fn main() : Int do size(push(Leaf, 1)) end
end|} post body
  in
  [ gated "a constructor-literal body has its postcondition ATTEMPTED" (fun () ->
        (* Before: 0 postcondition obligations of any kind — never attempted.

           The counts are EXACT, not `>= 1`.  The fixture has exactly one
           refined-return function, so it must leave exactly one ledger entry —
           and `check_fn_post_verdict` runs TWICE per such function (once from
           the [gate_unverified_posts] pre-pass with `~emit:false`, once from
           the walk).  A `>= 1` assertion cannot see the resulting double-count,
           and in fact did not: it shipped as `2 proved` and was caught in
           review, not here. *)
        March_refinecheck.Obligation.reset ();
        let src = tree_src "Node(t, x, Leaf)" "size(_) == size(t) + 1" in
        Alcotest.(check bool) "no error" false (has_refine_error_d src);
        let proved, violated, _ = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "exactly one postcondition proved, counted once"
          1 proved)
  ; gated "REJECT CONTROL: a FALSE postcondition on the same body is caught"
      (fun () ->
        (* `size(Node(t,x,Leaf))` is `size(t) + 1`, never `size(t) + 2`.
           Without this control the accept case above passes just as well when
           the checker is still not looking at the body at all.  Exact counts
           for the same double-count reason as above. *)
        March_refinecheck.Obligation.reset ();
        let src = tree_src "Node(t, x, Leaf)" "size(_) == size(t) + 2" in
        let _ = has_refine_error_d src in
        let proved, violated, _ = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "proved" 0 proved;
        Alcotest.(check int) "the false postcondition is reported exactly once"
          1 violated)
  ; gated "THIRD OUTCOME: an UNDECIDABLE postcondition stays silent" (fun () ->
        (* Definite-failure-only, on the new path.  `Node(push(t, x), x, Leaf)`
           has a self-recursive call, and the constructor-literal shape supplies
           NO induction hypothesis (there is no matched parameter, so nothing
           can be certified structurally smaller).  The call therefore reflects
           to an unconstrained constant `c`, and the goal reduces to
           `size(c) == size(t)` — neither provable nor refutable.

           That must be a SKIP, not a violation.  This is the gap where a future
           widening of the refutation would first go wrong: refuting a goal
           merely because an opaque constant makes it unprovable would reject
           correct code, which is this subsystem's cardinal sin.  Neither
           counter may move. *)
        March_refinecheck.Obligation.reset ();
        let src = tree_src "Node(push(t, x), x, Leaf)" "size(_) == size(t) + 1" in
        Alcotest.(check bool) "no error" false (has_refine_error_d src);
        let proved, violated, skips = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "proved" 0 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check bool) "recorded as a skip, so it is still countable" true
          (List.exists (fun (_, n) -> n > 0) skips))
  ; gated "the existing match-shaped body still verifies" (fun () ->
        (* Regression guard: widening the accepted shapes must not disturb the
           EMatch path that already worked. *)
        March_refinecheck.Obligation.reset ();
        let src = tree_src
          "match t do Leaf -> Node(Leaf, x, Leaf) | Node(l, y, r) -> Node(Node(l, y, r), x, Leaf) end"
          "size(_) == size(t) + 1"
        in
        Alcotest.(check bool) "no error" false (has_refine_error_d src);
        let proved, violated, skips = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "violated" 0 violated;
        (* The EMatch path deliberately still records NOTHING in the ledger —
           extending the accounting to it would move counts under every existing
           Tier 2 fixture and is a separate change.  Pinned exactly so that if
           someone does extend it, this test fails and forces the decision to be
           made on purpose rather than as a side effect. *)
        Alcotest.(check int) "the EMatch path records no obligation" 0 proved;
        Alcotest.(check int) "…and no skip either" 0
          (List.fold_left (fun a (_, n) -> a + n) 0 skips))
  ]

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
(* ── Division-safety: BOOLEAN path guards ──────────────────────────────────
   [path_proves_nonzero] matched a single atomic comparison and nothing else,
   so ANY `&&`/`||` in a guard — on either side of the `if`, and even a
   disjunction over the divisor itself — defeated it.  The divisor then fell
   through to the unrefined arm and `cap no_panic` reported a division that the
   guard makes unreachable.  That is a FALSE POSITIVE on the most idiomatic
   spelling there is (`if p > 0 && d > 0 do n / d`), and under `cap no_panic` it
   is a hard error, not a hint — which is why this was worth fixing over the
   completeness backlog.

   Found by pointing the checker at forgepm (a real ~9k-line app), whose
   `metrics.march` has exactly the `if prev <= 0 || dt <= 0 do 0 else … / dt`
   shape.

   The polarity is the whole content of the fix, so both directions of BOTH
   connectives are pinned, each with a negative control in [..._unsound] below:
   a fact `A && B` proves the goal if EITHER conjunct does, but a fact `A || B`
   proves it only if BOTH arms do.  Negating swaps which is which (De Morgan).

   NOT gated: decided syntactically, with no VC built at all. *)
let divsafety_boolean_guard_suite =
  let ok name src = Alcotest.(check bool) name false (has_divsafety_error src) in
  let errors name src = Alcotest.(check bool) name true (has_divsafety_error src) in
  [ Alcotest.test_case "conjunctive guard, THEN side: one conjunct proves it"
      `Quick (fun () ->
        ok "no error" {|
mod B1 do
  cap no_panic
  fn f(p : Int, d : Int) : Int do
    if p > 0 && d > 0 do 100 / d else 0 end
  end
end
|})
  ; Alcotest.test_case "disjunctive guard, ELSE side: De Morgan gives a conjunction"
      `Quick (fun () ->
        (* not (p <= 0 || d <= 0)  ==  p > 0 && d > 0  ==>  d != 0.
           This is the forgepm metrics.march shape. *)
        ok "no error" {|
mod B2 do
  cap no_panic
  fn f(p : Int, d : Int) : Int do
    if p <= 0 || d <= 0 do 0 else 100 / d end
  end
end
|})
  ; Alcotest.test_case "disjunction over the divisor ITSELF, else side" `Quick
      (fun () ->
        (* not (d <= 0 || d > 1000)  ==>  d > 0.  Both arms mention `d`, so this
           fails differently from B2 if the recursion drops one arm. *)
        ok "no error" {|
mod B3 do
  cap no_panic
  fn f(d : Int) : Int do
    if d <= 0 || d > 1000 do 0 else 100 / d end
  end
end
|})
  ; Alcotest.test_case "conjunctive guard over a `let`-bound divisor" `Quick
      (fun () ->
        ok "no error" {|
mod B4 do
  cap no_panic
  fn f(total : Int, prev : Int, p : Int) : Int do
    let dt = total - prev
    if p <= 0 || dt <= 0 do 0 else 100 / dt end
  end
end
|})
  ; Alcotest.test_case "`not` around a proving comparison flips polarity" `Quick
      (fun () ->
        ok "no error" {|
mod B5 do
  cap no_panic
  fn f(d : Int) : Int do
    if not(d != 0) do 0 else 100 / d end
  end
end
|})
  ; Alcotest.test_case "nested connectives still reduce" `Quick (fun () ->
        ok "no error" {|
mod B6 do
  cap no_panic
  fn f(p : Int, q : Int, d : Int) : Int do
    if p > 0 && (q > 0 && d != 0) do 100 / d else 0 end
  end
end
|})
  ; (* ── negative controls: the unsound direction must still error ──────── *)
    Alcotest.test_case "DISJUNCTIVE fact whose other arm proves nothing errors"
      `Quick (fun () ->
        (* Fact is `p > 0 || d > 0` — d may well be 0 (take p = 1, d = 0).
           If the `||` arm used OR instead of AND, this would pass. *)
        errors "error" {|
mod B7 do
  cap no_panic
  fn f(p : Int, d : Int) : Int do
    if p > 0 || d > 0 do 100 / d else 0 end
  end
end
|})
  ; Alcotest.test_case
      "negated CONJUNCTION whose other arm proves nothing errors" `Quick
      (fun () ->
        (* Fact is `not (p > 0 && d > 0)` == `p <= 0 || d <= 0` — d may be 0. *)
        errors "error" {|
mod B8 do
  cap no_panic
  fn f(p : Int, d : Int) : Int do
    if p > 0 && d > 0 do 0 else 100 / d end
  end
end
|})
  ; Alcotest.test_case "a conjunction proving nothing about the divisor errors"
      `Quick (fun () ->
        errors "error" {|
mod B9 do
  cap no_panic
  fn f(p : Int, q : Int, d : Int) : Int do
    if p > 0 && q > 0 do 100 / d else 0 end
  end
end
|})
  ]

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
          "still says unconstrained-subject" true
          (contains msg "unconstrained-subject"));
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
          "still says unconstrained-subject" true
          (contains msg "unconstrained-subject");
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
          (contains control "unconstrained-subject");
        Alcotest.(check bool)
          "so the withdrawal is not blamed" false
          (contains witness "alias-withdrawn");
        Alcotest.(check bool)
          "and the honest message stands" true
          (contains witness "unconstrained-subject"));
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
          "stays general" true (contains msg "unconstrained-subject"));
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
          "stays general (unconstrained-subject)" true
          (contains msg "unconstrained-subject"));
    gated "a FREE occurrence under a non-colliding binder still attributes"
      (fun () ->
        (* Companion control to LA7 (the colliding-binder case, just above):
           LA7's `fn n -> n > 0` collides on the laundering name and must NOT
           attribute; this one's `fn q -> n > 0` is a genuine free use of the
           laundered length under a NON-colliding binder, and — unlike the
           `q > n` shape this fixture used before Task 5 — `n > 0` is exactly
           the entailing comparison, so the pair still discriminates the
           free-occurrence walk: a regression that stopped descent at ANY
           binder (colliding or not) would make LA7 wrongly attribute or make
           this one wrongly stay general, and either failure is caught here.
           (The `q > n` shape this fixture used to have never entailed
           anything regardless of shadowing — see the sibling fixture below,
           "a FREE occurrence … entails nothing", which keeps that shape and
           asserts the now-correct undecided outcome instead.) *)
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
    if any_over(zs, fn q -> n > 0) do head(ys) else 0 end
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
    gated "a FREE occurrence under a non-colliding binder entails nothing when it is not the goal"
      (fun () ->
        (* `q > n` inside the lambda IS a genuine free use of the laundered
           length (the free-occurrence walk correctly does not stop at the
           non-colliding `q` binder), so before Task 5 this counted as
           evidence on its own.  It should not have: `q > n` says nothing
           about `n`'s sign — `q` is an arbitrary value from an opaque
           higher-order call, so this guard could never discharge
           `len(ys) > 0` whether or not the alias was withdrawn.  Task 5's
           entailment conjunct correctly reclassifies this as undecided
           (kept general) rather than misattributing it — the free-occurrence
           coverage itself is exercised (and asserted) by the sibling fixture
           above, so this one only needs to pin the entailment half. *)
        let msg =
          refine_error_text_d
            {|mod LA8B do
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
          "no longer misattributed to the withdrawal" false
          (contains msg "alias-withdrawn");
        Alcotest.(check bool)
          "stays general (unconstrained-subject)" true
          (contains msg "unconstrained-subject"));
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
          "stays general" true (contains msg "unconstrained-subject"));
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
          "stays general" true (contains msg "unconstrained-subject"));
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
          "stays general" true (contains msg "unconstrained-subject"));
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
          "still falls back to unconstrained-subject" true
          (contains msg "unconstrained-subject"));
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
          "stays general (unconstrained-subject)" true
          (contains msg "unconstrained-subject"));
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
          (contains msg "solver-undecided"));
    gated "a guard's lambda param colliding with the subject name is not evidence, laundered through a `let`"
      (fun () ->
        (* Same shape as LA11 (a lambda param that merely collides with the
           subject name must not be read as evidence), but the guard is
           laundered through exactly one `let` first, so the collision lives
           in the recorded RHS ([lets]) that [alias_withdrawal_cause]'s
           laundered branch re-checks, rather than in the direct condition
           itself.  Pins the RHS-path half of the same fix LA11 pins on the
           direct path -- until now that half rested on code-reading symmetry
           with no fixture of its own. *)
        let msg =
          refine_error_text_d
            {|mod LA13 do
  cap verified
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn check(f : (List(Int)) -> Bool, zs : List(Int)) : Bool do true end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int), zs : List(Int)) : Int do
    let ok = check(fn ys -> List.length(ys) > 0, zs)
    if ok do head(ys) else 0 end
  end
end|}
        in
        Alcotest.(check bool)
          "stays general (unconstrained-subject)" true
          (contains msg "unconstrained-subject"));
    gated "LA14: a guard that could never discharge is NOT blamed on the withdrawal"
      (fun () ->
        (* `List.length(ys) >= 0` is a tautology over a non-negative measure; it
           proves nothing about the goal `len(ys) > 0`, so this call is skipped
           whether or not the alias was withdrawn.  Blaming the withdrawal sends
           the author to fix a competing `List.length` definition that was never
           the cause — the same nested-`mod List` withdrawal LA1..LA13 already
           use, so this isolates exactly the entailment gap and nothing else. *)
        let msg =
          refine_error_text_d
            {|mod LA14 do
  cap verified
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) >= 0 do head(ys) else 0 end
  end
end|}
        in
        Alcotest.(check bool) "reported at all" true (msg <> "");
        Alcotest.(check bool)
          "does not claim the withdrawal caused this" false
          (contains msg "alias-withdrawn");
        Alcotest.(check bool)
          "stays general (unconstrained-subject)" true
          (contains msg "unconstrained-subject"));
    gated "LA15: CONTROL — a guard that WOULD have discharged is still blamed"
      (fun () ->
        (* The discrimination must be real: `List.length(ys) > 0` is exactly the
           goal, so here the withdrawal genuinely IS why the call is skipped,
           and the message must still say so.  Without this control, LA14
           would pass by disabling the attribution entirely. *)
        let msg =
          refine_error_text_d
            {|mod LA15 do
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
          "still attributes to the withdrawal" true
          (contains msg "alias-withdrawn"));
    gated "LA16: a lambda param reusing a LAUNDERING NAME is not read as that launder"
      (fun () ->
        (* [exists_discharging]'s [is_subject] reads a second name channel —
           [lets], keyed by the laundering name `n` — and that channel needs
           its own shadow discipline, independent of the SUBJECT's (`ys`).
           `fn n -> n > 0` inside `any_pos` binds its OWN `n`; that `n` must
           not be read as `List.length(ys)` just because "n" is a laundering
           key somewhere in the enclosing scope.  Before this fixed, the
           `if n >= 0 && …` conjunct alone should already stay general
           (`>= 0` cannot discharge `> 0`), so if this ever reports
           `alias-withdrawn` at all, it is because the lambda's `n` was
           wrongly read as the laundered length. *)
        let msg =
          refine_error_text_d
            {|mod LA16 do
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
    if n >= 0 && any_pos(zs, fn n -> n > 0) do head(ys) else 0 end
  end
end|}
        in
        Alcotest.(check bool) "reported at all" true (msg <> "");
        Alcotest.(check bool)
          "the shadowed launder is not read as evidence" false
          (contains msg "alias-withdrawn");
        Alcotest.(check bool)
          "stays general (unconstrained-subject)" true
          (contains msg "unconstrained-subject"));
    gated "LA16 CONTROL: a non-colliding param leaves the launder readable"
      (fun () ->
        (* Same shape as LA16, but the lambda binds `q` instead of `n`, so
           nothing shadows the laundering key — the discrimination must be
           real, or LA16 would pass merely because this whole family of
           guards is unreachable by [exists_discharging]. *)
        let msg =
          refine_error_text_d
            {|mod LA16B do
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
    if n >= 0 && any_pos(zs, fn q -> q > 0 && n > 0) do head(ys) else 0 end
  end
end|}
        in
        Alcotest.(check bool) "reported at all" true (msg <> "");
        Alcotest.(check bool)
          "the unshadowed launder still attributes" true
          (contains msg "alias-withdrawn"))
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
           Task 3 will escalate; it must be countable first.
           `z * z + 1 > 0` is TRUE but unprovable — the earlier `do z end`
           body became a witness-CONFIRMED violation (recorded as such) once
           counterexample surfacing landed; the skip accounting pinned here
           needs a contract that stays genuinely undecided. *)
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error_d {|
mod PL3 do
  fn mk(z : Int) : {Int | _ > 0} do z * z + 1 end
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
           obligations, or Task 3 makes cap verified less adoptable.
           `z * z + 1 > 0` is TRUE but unprovable — an incompleteness skip,
           which is exactly the class @[trusted] exists to wave through. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error_d {|
mod PS3 do
  cap verified
  @[trusted]
  fn mk(z : Int) : {Int | _ > 0} do z * z + 1 end
  fn main() : Int do mk(1) end
end|}))

  ; gated "@[trusted] does NOT suppress a witness-confirmed violation" (fun () ->
        (* @[trusted] rescues SKIPS (incompleteness), never a Violated —
           same rule as the pre-existing definite-violation case.  Here the
           interpreter proves the promise false (mk(0) returns 0), so the
           annotation is factually wrong and silence would be a lie. *)
        Alcotest.(check bool) "error" true
          (has_refine_error_d {|
mod PS3b do
  cap verified
  @[trusted]
  fn mk(z : Int) : {Int | _ > 0} do z end
  fn main() : Int do mk(1) end
end|}))

  ; gated "a non-cap-verified module is unaffected" (fun () ->
        (* The strictness boundary pinned here is about cap verified's
           ESCALATION of skips; the body must therefore stay a genuine skip
           (true-but-unprovable), not a witness-confirmable violation. *)
        Alcotest.(check bool) "no error" false
          (has_refine_error_d {|
mod PS4 do
  fn mk(z : Int) : {Int | _ > 0} do z * z + 1 end
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
  [ gated "a qualified spelling in a predicate is now enforced (Task 8 narrow slice)" (fun () ->
        (* PRE-Task-8: silent. The contract parsed, typechecked, and enforced
           NOTHING, because predicates were never desugared so List.length
           stayed an EField chain rather than the dotted EVar the alias keys
           on. Looks like it works; didn't.

           [Desugar.desugar_ty] (see lib/desugar/desugar.ml) now flattens a
           module-path call head found INSIDE a `TyRefine` predicate the same
           way [Desugar.desugar_expr]'s own `EField` arm already flattens an
           ordinary call head — without running the rest of the expression
           desugarer over the predicate.  When the alias is live (no
           competing `List.length` in scope, the case here), that is enough
           for the qualified spelling to mean exactly what `len` means: no
           warning fires, and a genuinely violating call is caught. *)
        March_refinecheck.Obligation.reset ();
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod QP1 do
  fn inner(xs : {List(Int) | List.length(_) > 0}) : Int do 0 end
  fn main() : Int do inner([]) end
end|}));
        let msgs = ctx.March_errors.Errors.diagnostics in
        Alcotest.(check bool) "no qualified-call warning (alias is live)" false
          (List.exists (fun (d : March_errors.Errors.diagnostic) ->
             contains d.March_errors.Errors.message "qualified call") msgs);
        let _, violated, _ = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "the empty list genuinely violates `List.length(_) > 0`" 1 violated)

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

  ; gated "cap verified escalates an inert interface-signature refinement to an error"
      (fun () ->
        (* Decision recorded in
           specs/progress/2026-08-03-cap-verified-interface-signature-decision.md:
           under `cap verified` this is an ERROR, not a warning -- matching
           `check_call`/`check_post`'s own escalation.  [refine_error_text_d]
           filters strictly to [Error] severity (see its doc comment above), so
           asserting through it is NOT vacuous here the way it would be against
           today's plain-warning behaviour -- confirmed by the companion test
           below, which pins that the SAME fixture without `cap verified`
           produces no error, only a warning. *)
        let msg =
          refine_error_text_d
            {|mod T do
  cap verified
  interface Runner(a) do
    fn run : a -> {Int | _ > 0} -> Int
  end
  fn main() : Int do 0 end
end|}
        in
        Alcotest.(check bool) "reported as an error" true (contains msg "enforces nothing"))

  ; gated "without cap verified the same fixture is only a warning, not an error"
      (fun () ->
        (* Companion/control for the test above: proves [refine_error_text_d]
           genuinely distinguishes the two cases here rather than always
           finding SOME error text for unrelated reasons. *)
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod IR5 do
  interface Runner(a) do
    fn run : a -> {Int | _ > 0} -> Int
  end
  fn main() : Int do 0 end
end|}));
        let msgs = ctx.March_errors.Errors.diagnostics in
        Alcotest.(check bool) "no ERROR-severity diagnostic" true
          (not
             (List.exists
                (fun (d : March_errors.Errors.diagnostic) ->
                  d.March_errors.Errors.severity = March_errors.Errors.Error)
                msgs));
        Alcotest.(check bool) "still a WARNING" true
          (List.exists
             (fun (d : March_errors.Errors.diagnostic) ->
               d.March_errors.Errors.severity = March_errors.Errors.Warning
               && contains d.March_errors.Errors.message "enforces nothing")
             msgs))

  ; gated "cap verified does NOT leak strictness into a nested mod lacking its own"
      (fun () ->
        (* Pins non-inheritance: [strict_verified] (and the [~strict] flag
           threaded through [warn_predicate_decls]) is scoped to the decl
           list that declares `cap verified`, exactly like every other
           `cap verified` obligation in this file -- a nested `mod` re-derives
           its own strictness rather than inheriting the enclosing module's.
           This is load-bearing for the whole codebase, not just this test:
           the standard library arrives as sibling `DMod` decls, so a leak
           here would make the entire stdlib strict the moment any one
           top-level module opted into `cap verified`. *)
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod IR6 do
  cap verified
  mod Inner do
    interface Runner(a) do
      fn run : a -> {Int | _ > 0} -> Int
    end
  end
  fn main() : Int do 0 end
end|}));
        let msgs = ctx.March_errors.Errors.diagnostics in
        Alcotest.(check bool) "no ERROR-severity diagnostic (no strictness leak)" true
          (not
             (List.exists
                (fun (d : March_errors.Errors.diagnostic) ->
                  d.March_errors.Errors.severity = March_errors.Errors.Error)
                msgs));
        Alcotest.(check bool) "still a WARNING" true
          (List.exists
             (fun (d : March_errors.Errors.diagnostic) ->
               d.March_errors.Errors.severity = March_errors.Errors.Warning
               && contains d.March_errors.Errors.message "enforces nothing")
             msgs))
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

    (* Count-based pin of the exact `stats.march` repro (Float list, Result
       wrapper), using Obligation.reset/summary directly rather than
       check_ledger, so the obligation ledger's shape is asserted precisely:
       ONE precondition, PROVED, nothing skipped. The `_` arm's own
       arm-order-exclusion fact (`not is_Nil(xs)`, already landed — see
       [arm_exclusion_suite] above) reaches `path_resolve_tester`'s
       is_Nil/is_Cons <-> len(x) translation.

       CORRECTION (final-review pass): this test does NOT reach the
       base-case-linking axiom [build_measure_preamble] adds via
       [measure_base_cases] (the "MA1" name notwithstanding). `len` over the
       built-in `List` routes entirely through `path_resolve_tester`'s own
       hardcoded `is_Nil(xs) <-> len(xs) = 0` translation, never through the
       general axiom — deleting [measure_base_cases]'s emitter entirely still
       leaves this test (and the whole suite) green. See the
       "measure-base-case-axiom" suite below for tests that actually pin the
       axiom itself, using a user `@[measure]` with no `path_resolve_tester`
       special-casing to fall back on. *)
    gated "excluding Nil in a match gives the other arm len(xs) > 0" (fun () ->
        March_refinecheck.Obligation.reset ();
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod MA1 do
  fn mean(xs : {List(Float) | len(_) > 0}) : Float do 0.0 end
  fn mean_safe(xs : List(Float)) : Result(Float, String) do
    match xs do
    Nil -> Err("empty")
    _   -> Ok(mean(xs))
    end
  end
  fn main() : Int do 0 end
end|}));
        Alcotest.(check int) "no diagnostics" 0
          (List.length ctx.March_errors.Errors.diagnostics);
        let proved, violated, skips = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "the mean(xs) call is proved" 1 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "skipped" 0
          (List.fold_left (fun a (_, n) -> a + n) 0 skips));

    (* REJECT CONTROL. No `Nil` arm exists to exclude anything, so `mean`'s
       precondition must stay unproven. This is the discriminating test: it is
       what tells a genuine fact-propagation fix apart from one that
       accidentally proves the precondition unconditionally (laundering the
       goal rather than deriving it from the exclusion). *)
    gated "with no Nil arm, the obligation is still unproven" (fun () ->
        March_refinecheck.Obligation.reset ();
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod MA2 do
  fn mean(xs : {List(Float) | len(_) > 0}) : Float do 0.0 end
  fn always_call(xs : List(Float)) : Result(Float, String) do
    Ok(mean(xs))
  end
  fn main() : Int do 0 end
end|}));
        (* A skip must not produce an ERROR or WARNING.  HINT-severity
           diagnostics are excluded deliberately: the unverified-precondition
           HINT is advisory, does not change the exit code, and is emitted for
           exactly this shape -- counting it here would make the assertion fail
           for a reason that has nothing to do with the skip semantics under
           test (the obligation counts below are the real check). *)
        Alcotest.(check int) "no error/warning diagnostics (skip is silent)" 0
          (List.length
             (List.filter
                (fun (d : March_errors.Errors.diagnostic) ->
                  d.March_errors.Errors.severity <> March_errors.Errors.Hint)
                ctx.March_errors.Errors.diagnostics));
        let proved, violated, skips = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "still NOT proved -- no Nil arm to exclude" 0 proved;
        Alcotest.(check int) "not falsely reported as violated either" 0 violated;
        Alcotest.(check int) "the obligation is skipped" 1
          (List.fold_left (fun a (_, n) -> a + n) 0 skips));
  ]

(* ── Pinning [measure_base_cases]/[build_measure_preamble]'s base-case-linking
   axiom directly ────────────────────────────────────────────────────────────
   The MA1/MA2 tests above exercise `len` over the built-in `List`, which
   never reaches this axiom -- `path_resolve_tester`'s own hardcoded
   `is_Nil(xs) <-> len(xs) = 0` translation gets there first (see the
   corrected MA1 comment). Deleting [measure_base_cases]'s emitter entirely
   leaves MA1/MA2 (and the whole 437/437 suite at the time this was found)
   green, so it needs its own witness: a user `@[measure]` over a user ADT,
   which has no built-in special case to fall back on. *)
(* ── The silent-inert measure warning (2026-08-05) ─────────────────────────
   A `@[measure]` whose value reads a SCALAR constructor field — the shape
   `Array.length` has (`PVec(n,_,_,_) -> n`) — is axiomatised correctly and is
   nonetheless completely inert: [reflect_field] erases every non-datatype
   constructor field to a fresh unconstrained constant, so the measure applied
   to a literal constructor is unknown and neither the predicate nor its
   negation is provable.

   Every symptom of a working measure is present (no error, correct preamble,
   obligations raised), which is why this cost a full investigation to find.
   The warning is the signal that was missing.  See
   specs/todos/2026-08-05-measure-over-scalar-ctor-field.md.

   These cases are NOT [gated]: the warning is computed from the AST at
   preamble-build time and needs no solver, so gating it would disable it
   exactly where a developer without z3 would still benefit. *)
let measure_scalar_field_warn src =
  let ctx = March_errors.Errors.create () in
  March_refinecheck.Refine_check.check_module ctx
    (March_desugar.Desugar.desugar_module (parse src));
  ( List.exists
      (fun (d : March_errors.Errors.diagnostic) ->
        d.March_errors.Errors.severity = March_errors.Errors.Warning
        && contains d.March_errors.Errors.message "reads a constructor field")
      (March_errors.Errors.sorted ctx)
  , March_errors.Errors.has_errors ctx )

let measure_scalar_field_suite =
  [ Alcotest.test_case "a measure reading a scalar ctor field warns" `Quick
      (fun () ->
        (* The real `Array.length` shape, transcribed from stdlib/array.march. *)
        let warned, errored =
          measure_scalar_field_warn {|
mod AW do
  type TrieNode(a) = TrieEmpty | TrieLeaf(List(a))
  type PVec(a) = PVec(Int, Int, TrieNode(a), List(a))
  @[measure]
  fn length(v : PVec(a)) : Int do
    match v do
    PVec(n, _, _, _) -> n
    end
  end
  fn aget(v : PVec(a), idx : {Int | _ >= 0 && _ < length(v)}) : a do aget(v, idx) end
end
|}
        in
        Alcotest.(check bool) "warns" true warned;
        (* A warning, not an error: the measure is sound and its predicates stay
           legal vocabulary, so nothing that compiled before stops compiling. *)
        Alcotest.(check bool) "no error" false errored)

  ; Alcotest.test_case "a structurally recursive measure does NOT warn" `Quick
      (fun () ->
        (* The control.  Without it, a warning that fired on EVERY measure
           would pass the case above — and would bury the real signal under
           noise on every working contract in the tree, `List.nth` included. *)
        let warned, errored =
          measure_scalar_field_warn {|
mod SW do
  type Tree(a) = Leaf | Node(Tree(a), a, Tree(a))
  @[measure]
  fn size(t : Tree(a)) : Int do
    match t do
      Leaf -> 0
      Node(l, x, r) -> 1 + size(l) + size(r)
    end
  end
  fn tget(t : Tree(a), i : {Int | _ >= 0 && _ < size(t)}) : a do tget(t, i) end
end
|}
        in
        Alcotest.(check bool) "no warning" false warned;
        Alcotest.(check bool) "no error" false errored)

  ; Alcotest.test_case "a ctor with a scalar field NOT read does NOT warn" `Quick
      (fun () ->
        (* Sharper control: the constructor HAS an erased `Int` field, but the
           measure's value does not depend on it, so the erasure is harmless
           and the measure proves fine (this is the `probeH` shape, measured as
           `1 proved`).  Warning here would be a false positive. *)
        let warned, _ =
          measure_scalar_field_warn {|
mod NW do
  type T3 = L3 | N3(Int, T3)
  @[measure]
  fn size3(t : T3) : Int do
    match t do
    L3 -> 0
    N3(k, rest) -> 1 + size3(rest)
    end
  end
  fn tget3(t : T3, i : {Int | _ >= 0 && _ < size3(t)}) : Int do tget3(t, i) end
end
|}
        in
        Alcotest.(check bool) "no warning" false warned)

  ; Alcotest.test_case "REGRESSION: a body that MENTIONS an erased field but \
                        does not depend on it does NOT warn" `Quick
      (fun () ->
        (* The first version of this warning asked "does the arm body mention
           an erased field anywhere", and this shape is why that was wrong:
           `0 * n` mentions `n`, but its value is 0 regardless, so the measure
           still evaluates and warning would be a false positive.  It was
           caught by the LOAD-BEARING case in [measure_base_case_axiom_suite],
           which uses this exact fixture for an unrelated reason — pinned here
           too so the connection is explicit rather than incidental.

           The narrowed predicate ("the body IS a bare field read") therefore
           under-covers on purpose: `Node(n, m) -> n + 0` is equally inert and
           draws nothing.  Under-warning is the safe direction. *)
        let warned, _ =
          measure_scalar_field_warn {|
mod ZW do
  type Zt = Zleaf(Int) | Znode(Zt, Zt)
  @[measure]
  fn zsize(t : Zt) : Int do
    match t do
      Zleaf(n) -> 0 * n
      Znode(l, r) -> 1 + zsize(l) + zsize(r)
    end
  end
  fn needs_pos(t : {Zt | zsize(_) > 0}) : Int do 1 end
end
|}
        in
        Alcotest.(check bool) "no warning" false warned)
  ]

let measure_base_case_axiom_suite =
  [ gated "a user measure's nullary-arm exclusion reaches the base-case axiom"
      (fun () ->
        March_refinecheck.Obligation.reset ();
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod Z do
  type Zt = Zleaf(Int) | Znode(Zt, Zt)
  @[measure]
  fn zsize(t : Zt) : Int do
    match t do
      Zleaf(_) -> 0
      Znode(l, r) -> 1 + zsize(l) + zsize(r)
    end
  end
  fn needs_pos(t : {Zt | zsize(_) > 0}) : Int do 1 end
  fn go(t : Zt) : Int do
    match t do
      Zleaf(_) -> 0
      _ -> needs_pos(t)
    end
  end
  fn main() : Int do 0 end
end|}));
        Alcotest.(check int) "no diagnostics" 0
          (List.length ctx.March_errors.Errors.diagnostics);
        let proved, violated, skips = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "the needs_pos(t) call is proved" 1 proved;
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "skipped" 0
          (List.fold_left (fun a (_, n) -> a + n) 0 skips))

  ; gated "REJECT CONTROL: with no Zleaf arm to exclude, the obligation is skipped"
      (fun () ->
        (* Drop the `Zleaf` arm entirely: there is nothing left in the match
           to narrow `t`, so the base-case axiom has no exclusion fact to
           fire against and the call stays unproven. Tells a genuine
           fact-propagation proof apart from one that proves unconditionally. *)
        March_refinecheck.Obligation.reset ();
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod Z2 do
  type Zt = Zleaf(Int) | Znode(Zt, Zt)
  @[measure]
  fn zsize(t : Zt) : Int do
    match t do
      Zleaf(_) -> 0
      Znode(l, r) -> 1 + zsize(l) + zsize(r)
    end
  end
  fn needs_pos(t : {Zt | zsize(_) > 0}) : Int do 1 end
  fn go(t : Zt) : Int do needs_pos(t) end
  fn main() : Int do 0 end
end|}));
        (* A skip must not produce an ERROR or WARNING.  HINT-severity
           diagnostics are excluded deliberately: the unverified-precondition
           HINT is advisory, does not change the exit code, and is emitted for
           exactly this shape -- counting it here would make the assertion fail
           for a reason that has nothing to do with the skip semantics under
           test (the obligation counts below are the real check). *)
        Alcotest.(check int) "no error/warning diagnostics (skip is silent)" 0
          (List.length
             (List.filter
                (fun (d : March_errors.Errors.diagnostic) ->
                  d.March_errors.Errors.severity <> March_errors.Errors.Hint)
                ctx.March_errors.Errors.diagnostics));
        let proved, violated, skips = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "still NOT proved -- no Zleaf arm to exclude" 0 proved;
        Alcotest.(check int) "not falsely reported as violated either" 0 violated;
        Alcotest.(check int) "the obligation is skipped" 1
          (List.fold_left (fun a (_, n) -> a + n) 0 skips))

  ; gated "LOAD-BEARING: a semantically-identical non-ELit base case body loses the axiom"
      (fun () ->
        (* [measure_base_cases]'s collection loop only records a base case
           whose body is a bare [A.ELit] -- `0 * n` is semantically identical
           to `0` for any Int `n`, but it is an [A.EApp] (or similar), not a
           literal, so the emitter does not record it and the base-case axiom
           is never generated for this constructor. This is the decisive pin:
           it fails (proved becomes 1, skipped becomes 0) if the emitter is
           deleted outright, or if its literal-detection is loosened to see
           through arithmetic. *)
        March_refinecheck.Obligation.reset ();
        let ctx = March_errors.Errors.create () in
        March_refinecheck.Refine_check.check_module ctx
          (March_desugar.Desugar.desugar_module (parse {|
mod Z3 do
  type Zt = Zleaf(Int) | Znode(Zt, Zt)
  @[measure]
  fn zsize(t : Zt) : Int do
    match t do
      Zleaf(n) -> 0 * n
      Znode(l, r) -> 1 + zsize(l) + zsize(r)
    end
  end
  fn needs_pos(t : {Zt | zsize(_) > 0}) : Int do 1 end
  fn go(t : Zt) : Int do
    match t do
      Zleaf(_) -> 0
      _ -> needs_pos(t)
    end
  end
  fn main() : Int do 0 end
end|}));
        (* A skip must not produce an ERROR or WARNING.  HINT-severity
           diagnostics are excluded deliberately: the unverified-precondition
           HINT is advisory, does not change the exit code, and is emitted for
           exactly this shape -- counting it here would make the assertion fail
           for a reason that has nothing to do with the skip semantics under
           test (the obligation counts below are the real check). *)
        Alcotest.(check int) "no error/warning diagnostics (skip is silent)" 0
          (List.length
             (List.filter
                (fun (d : March_errors.Errors.diagnostic) ->
                  d.March_errors.Errors.severity <> March_errors.Errors.Hint)
                ctx.March_errors.Errors.diagnostics));
        let proved, violated, skips = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "NOT proved -- base case body is not a bare literal" 0 proved;
        Alcotest.(check int) "not falsely reported as violated either" 0 violated;
        Alcotest.(check int) "the obligation is skipped" 1
          (List.fold_left (fun a (_, n) -> a + n) 0 skips))
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

(* ── Postcondition composition through an unannotated `let`: CLOSED case ───
   `scope_add_binding`'s postcond arm seeds a refined-local scope entry only
   for a scalar- or record-sorted postcondition; a plain multi-constructor ADT
   fell into the catch-all and vanished.  The consumer
   ([load_scope_measure_facts]) already existed and already reads exactly this
   entry — only the producer was missing.

   CLOSED means the postcondition mentions no parameter other than the refined
   value itself (`size(_) > 0`).  The RELATIONAL case (`size(_) == size(t) + 1`)
   needs Task 3 as well and is pinned there, NOT here — do not widen this
   fixture to a relational predicate and expect it to pass. *)
let post_compose_closed_suite =
  let src = {|
mod PC do
  type Tree = Leaf | Node(Tree, Int, Tree)

  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end

  fn grow(t : Tree) : {Tree | size(_) > 0} do
    match t do
      Leaf -> Node(Leaf, 1, Leaf)
      Node(l, y, r) -> Node(Node(l, y, r), 1, Leaf)
    end
  end

  fn needs_nonempty(x : {Tree | size(_) > 0}) : Int do 1 end

  fn go(t : Tree) : Int do
    let r = grow(t)
    needs_nonempty(r)
  end
  fn main() : Int do go(Leaf) end
end|}
  in
  [ gated "a CLOSED measure postcondition composes through an unannotated let"
      (fun () ->
        March_refinecheck.Obligation.reset ();
        Alcotest.(check bool) "no error" false (has_refine_error_d src);
        let _, violated, skips = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "skipped" 0
          (List.fold_left (fun a (_, n) -> a + n) 0 skips))
  ; gated "REJECT CONTROL: rebinding `r` retires the carried fact" (fun () ->
        (* If the fact survived a rebind, the entry is keyed wrongly and an
           outer promise would be attributed to an inner binding — the
           false-positive shape this subsystem has shipped three times. *)
        let src' = {|
mod PC2 do
  type Tree = Leaf | Node(Tree, Int, Tree)

  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end

  fn grow(t : Tree) : {Tree | size(_) > 0} do
    match t do
      Leaf -> Node(Leaf, 1, Leaf)
      Node(l, y, r) -> Node(Node(l, y, r), 1, Leaf)
    end
  end

  fn needs_nonempty(x : {Tree | size(_) > 0}) : Int do 1 end

  fn go(t : Tree) : Int do
    let r = grow(t)
    let r = Leaf
    needs_nonempty(r)
  end
  fn main() : Int do go(Leaf) end
end|}
        in
        March_refinecheck.Obligation.reset ();
        let _ = has_refine_error_d src' in
        let proved, _, skips = March_refinecheck.Obligation.summary () in
        let skipped = List.fold_left (fun a (_, n) -> a + n) 0 skips in
        Alcotest.(check bool) "the rebound `r` does NOT inherit the promise" true
          (skipped >= 1 || proved = 0))
  ]

(* ── Postcondition composition: the RELATIONAL case ────────────────────────
   The motivating repro from the 2026-07-29 todo.  Needs Task 1 (so `push`'s
   own postcondition is proven at its definition), Task 2 (so the `let` seeds a
   measure-marked scope entry) AND this task (so the entry's relational
   predicate can be translated).  Any one alone leaves it skipped. *)
let post_compose_relational_suite =
  let src = {|
mod PR do
  type Tree = Leaf | Node(Tree, Int, Tree)

  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end

  fn push(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1} do
    Node(t, x, Leaf)
  end

  fn needs_bigger(before : Tree, after : {Tree | size(_) > size(before)}) : Int do 0 end

  fn go(t : Tree) : Int do
    let r = push(t, 5)
    needs_bigger(t, r)
  end
  fn main() : Int do go(Leaf) end
end|}
  in
  [ gated "a RELATIONAL measure postcondition composes through a let" (fun () ->
        March_refinecheck.Obligation.reset ();
        Alcotest.(check bool) "no error" false (has_refine_error_d src);
        let _, violated, skips = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "violated" 0 violated;
        Alcotest.(check int) "skipped" 0
          (List.fold_left (fun a (_, n) -> a + n) 0 skips))
  ; gated "REJECT CONTROL: a caller-scope name must not resolve to a FRESH const"
      (fun () ->
        (* If `size(t)` resolved to a fresh unconstrained constant rather than
           the goal side's own term for `t`, the predicate would be trivially
           satisfiable and this FALSE goal would "prove" too.  `push` makes the
           tree bigger, never smaller, so a demand for SMALLER must not pass. *)
        let src' = {|
mod PR2 do
  type Tree = Leaf | Node(Tree, Int, Tree)

  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end

  fn push(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1} do
    Node(t, x, Leaf)
  end

  fn needs_smaller(before : Tree, after : {Tree | size(_) < size(before)}) : Int do 0 end

  fn go(t : Tree) : Int do
    let r = push(t, 5)
    needs_smaller(t, r)
  end
  fn main() : Int do go(Leaf) end
end|}
        in
        March_refinecheck.Obligation.reset ();
        let _ = has_refine_error_d src' in
        let _, violated, skips = March_refinecheck.Obligation.summary () in
        let skipped = List.fold_left (fun a (_, n) -> a + n) 0 skips in
        Alcotest.(check bool) "a FALSE relational goal is never proved" true
          (violated >= 1 || skipped >= 1))
  ; gated "REJECT CONTROL: rebinding the MENTIONED name retires the fact"
      (fun () ->
        (* `r`'s promise mentions `t`.  Rebinding `t` between the `let` and the
           call makes the carried `size(t)` name a value that no longer exists;
           translating it against the NEW `t` would attribute an outer fact to
           an inner binding — the false positive this subsystem has shipped
           three times.  The entry must be RETIRED, i.e. the call must go back
           to being silently skipped. *)
        let src' = {|
mod PR3 do
  type Tree = Leaf | Node(Tree, Int, Tree)

  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end

  fn push(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1} do
    Node(t, x, Leaf)
  end

  fn needs_bigger(before : Tree, after : {Tree | size(_) > size(before)}) : Int do 0 end

  fn go(t : Tree) : Int do
    let r = push(t, 5)
    let t = Leaf
    needs_bigger(t, r)
  end
  fn main() : Int do go(Leaf) end
end|}
        in
        March_refinecheck.Obligation.reset ();
        let _ = has_refine_error_d src' in
        let _, violated, skips = March_refinecheck.Obligation.summary () in
        let skipped = List.fold_left (fun a (_, n) -> a + n) 0 skips in
        Alcotest.(check int) "no violation invented" 0 violated;
        Alcotest.(check bool) "the stale `size(t)` fact does NOT survive" true
          (skipped >= 1))
  ; gated "REJECT CONTROL: a `let` REBINDING a name its own promise mentions"
      (fun () ->
        (* The dangerous shape, and the one the two controls above miss.
           `push2`'s promise mentions `t`; the `let` binds its result to `t`
           as well.  [postcond_of] substituted the ACTUAL, so the predicate's
           `t` is the value BEFORE the binding — but the entry is filed under
           `t`, and the fact loader reads the entry's own name as a spelling
           of the promised value.  The two collide onto one symbol and the
           assumption becomes `size(t) > size(t) + size(u)`, i.e. `0 >
           size(u)`: a CONTRADICTION, which discharges anything at all.  Here
           it would "prove" that an arbitrary `w` is bigger than the tree
           `push2` just grew — a false proof, not merely an over-approximation.
           Base behaviour (273b4ef2) is `1 proved, 1 skipped`. *)
        let src' = {|
mod PR4 do
  type Tree = Leaf | Node(Tree, Int, Tree)

  @[measure]
  fn size(t : Tree) : Int do
    match t do
      Leaf -> 0
      Node(l, _, r) -> 1 + size(l) + size(r)
    end
  end

  fn push2(t : Tree, u : Tree) : {Tree | size(_) > size(t) + size(u)} do
    Node(t, 1, u)
  end

  fn needs_smaller(before : Tree, after : {Tree | size(_) < size(before)}) : Int do 0 end

  fn go(t : Tree, u : Tree, w : Tree) : Int do
    let t = push2(t, u)
    needs_smaller(w, t)
  end
  fn main() : Int do go(Leaf, Leaf, Leaf) end
end|}
        in
        March_refinecheck.Obligation.reset ();
        let _ = has_refine_error_d src' in
        let _, violated, skips = March_refinecheck.Obligation.summary () in
        let skipped = List.fold_left (fun a (_, n) -> a + n) 0 skips in
        Alcotest.(check bool)
          "an IMPOSSIBLE goal is never proved from a self-rebinding promise"
          true (violated >= 1 || skipped >= 1))
  ]

(* ── `List.nth` carries a bounds contract ──────────────────────────────────
   `nth` panics on an out-of-range index and, unlike `head`/`last`/`unwrap`,
   carried no contract at all — so a provably-out-of-range index compiled
   silently.  The contract is cross-parameter (`n` bounded by a measure of
   `xs`), a shape verified working before this task was planned.

   The fixtures restate the stdlib `List.nth` signature inline because this
   harness checks a single parsed string: unlike `bin/main.ml`, it does NOT
   prepend the stdlib, so a bare `List.nth(…)` would resolve to nothing and
   every case here would pass vacuously.  The restated signature is copied
   verbatim from `stdlib/list.march` — Step 5's revert-the-signature mutation
   is what keeps the two in step. *)
let nth_fixture name body =
  Printf.sprintf
    "mod %s do\n\
    \  mod List do\n\
    \    fn nth(xs : List(a), n : {Int | _ >= 0 && _ < len(xs)}) : a do\n\
    \      match xs do\n\
    \      Nil        -> panic(\"List.nth: index out of bounds\")\n\
    \      Cons(h, t) -> if n == 0 do h else nth(t, n - 1) end\n\
    \      end\n\
    \    end\n\
    \  end\n\
     %s\n\
     end\n"
    name body

let stdlib_nth_contract_suite =
  [ gated "an in-range literal index proves" (fun () ->
        March_refinecheck.Obligation.reset ();
        let src =
          nth_fixture "NthOk"
            "  fn go() : Int do List.nth([1, 2, 3], 1) end\n\
            \  fn main() : Int do go() end"
        in
        Alcotest.(check bool) "no error" false (has_refine_error_d src);
        let proved, violated, _ = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "violated" 0 violated;
        (* Silence is NOT the assertion: "no error, 0 violated" holds just as
           well if the contract were absent, if `List.nth` resolved to nothing,
           or if the obligation were never created.  Only the LEDGER can tell
           a proof from a vacuum. *)
        Alcotest.(check bool) "proved" true (proved >= 1))
  ; gated "REJECT CONTROL: a provably out-of-range index is a violation"
      (fun () ->
        March_refinecheck.Obligation.reset ();
        let src =
          nth_fixture "NthBad"
            "  fn go() : Int do List.nth([1, 2, 3], 7) end\n\
            \  fn main() : Int do go() end"
        in
        let _ = has_refine_error_d src in
        let _, violated, _ = March_refinecheck.Obligation.summary () in
        Alcotest.(check bool) "reported" true (violated >= 1))
  ; gated "a negative literal index is a violation" (fun () ->
        March_refinecheck.Obligation.reset ();
        let src =
          nth_fixture "NthNeg"
            "  fn go() : Int do List.nth([1, 2, 3], -1) end\n\
            \  fn main() : Int do go() end"
        in
        let _ = has_refine_error_d src in
        let _, violated, _ = March_refinecheck.Obligation.summary () in
        Alcotest.(check bool) "reported" true (violated >= 1))
  ; gated "an unknown index is SILENT, not reported" (fun () ->
        (* The definite-failure stance: an index the checker cannot bound is
           accepted in silence.  This is the false-positive guard, and it is
           the assertion that matters most in this suite. *)
        March_refinecheck.Obligation.reset ();
        let src =
          nth_fixture "NthUnknown"
            "  fn go(xs : List(Int), i : Int) : Int do List.nth(xs, i) end\n\
            \  fn main() : Int do go([1], 0) end"
        in
        Alcotest.(check bool) "no error" false (has_refine_error_d src);
        let _, violated, skips = March_refinecheck.Obligation.summary () in
        Alcotest.(check int) "violated" 0 violated;
        (* And it must be silent because the obligation was RAISED and then
           SKIPPED — not because no obligation exists.  Without this the case
           stays green if `List.nth`'s contract vanishes entirely, which is the
           precise regression the definite-failure stance exists to prevent. *)
        let skipped = List.fold_left (fun a (_, n) -> a + n) 0 skips in
        Alcotest.(check bool) "skipped" true (skipped >= 1))
  ]

(* ── Per-call-site verdict INDEX ───────────────────────────────────────────
   [Obligation.summary] answers "how many proved" for a whole module; nothing
   answered "what did THIS call site prove", which is what a consumer wanting
   to admit a provably-safe call (rather than banning it by name) needs.

   The span keyed on is the one [Refine_check] itself passes as [~span] to
   [check_call] from its [A.EApp (A.EVar f, args, sp)] case — the CALL
   EXPRESSION's own span, not the callee name's span.  [call_span_of] below
   re-derives it from the AST rather than reading it back off the ledger: a
   test that queried with a span it got from [Obligation.all ()] would pass
   for any keying whatsoever, including one no later pass could reproduce. *)
let call_span_of (src : string) (fname : string) : March_ast.Ast.span =
  let open March_ast.Ast in
  let found = ref None in
  let take sp = if !found = None then found := Some sp in
  let rec ex (e : expr) =
    match e with
    | EApp (EVar n, args, sp) ->
      if n.txt = fname then take sp;
      List.iter ex args
    | EApp (f, args, _) -> ex f; List.iter ex args
    | EBlock (es, _) -> List.iter ex es
    | ECon (_, args, _) | EAtom (_, args, _) | ETuple (args, _) -> List.iter ex args
    | EIf (c, t, f, _) -> ex c; ex t; ex f
    | EAnnot (e, _, _) | EField (e, _, _) | ELam (_, e, _) -> ex e
    | ELet (b, _) -> ex b.bind_expr
    | EMatch (s, brs, _) -> ex s; List.iter (fun b -> ex b.branch_body) brs
    | _ -> ()
  in
  List.iter
    (fun d ->
      match d with
      | DFn (fd, _) -> List.iter (fun c -> ex c.fc_body) fd.fn_clauses
      | _ -> ())
    (parse src).mod_decls;
  match !found with
  | Some sp -> sp
  (* Loud, not silent: the walker above has a catch-all, so a fixture shape it
     does not descend into must fail the test rather than quietly hand back a
     dummy span that the index would legitimately miss. *)
  | None -> Alcotest.failf "no call to `%s` found in fixture" fname

let verdict_query_suite =
  [ gated "a proved call's verdict is queryable by its call span" (fun () ->
        let src =
          "mod VQ do\n\
          \  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end\n\
          \  fn go() : Int do head([1]) end\n\
           end\n"
        in
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error src);
        Alcotest.(check (option string))
          "proved at the call span" (Some "proved")
          (Option.map March_refinecheck.Obligation.verdict_name
             (March_refinecheck.Obligation.verdict_at (call_span_of src "head"))))

  ; gated "REJECT CONTROL: a violated call reports Violated, not just `some verdict`"
      (fun () ->
        let src =
          "mod VQBad do\n\
          \  fn takepos(k : {Int | _ >= 0}) : Int do k end\n\
          \  fn go() : Int do takepos(0 - 5) end\n\
           end\n"
        in
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error src);
        Alcotest.(check (option string))
          "violated at the call span" (Some "violated")
          (Option.map March_refinecheck.Obligation.verdict_name
             (March_refinecheck.Obligation.verdict_at (call_span_of src "takepos"))))

  ; gated "a skipped call reports the skip, never `proved`" (fun () ->
        let src =
          "mod VQSkip do\n\
          \  fn takepos(k : {Int | _ >= 0}) : Int do k end\n\
          \  fn go(n : Int) : Int do takepos(n) end\n\
           end\n"
        in
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error src);
        Alcotest.(check (option string))
          "skipped at the call span" (Some "skipped")
          (Option.map March_refinecheck.Obligation.verdict_name
             (March_refinecheck.Obligation.verdict_at (call_span_of src "takepos"))))

  ; (* A call with no refined parameter raises no obligation at all, so the
       query must answer "nothing known" and NOT be conflated with `proved` —
       a consumer that admits a call on `verdict_at <> None` would otherwise
       admit every unrefined call in the language. *)
    gated "an unrefined call is absent from the index" (fun () ->
        let src =
          "mod VQNone do\n\
          \  fn plain(k : Int) : Int do k end\n\
          \  fn go() : Int do plain(5) end\n\
           end\n"
        in
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error src);
        Alcotest.(check bool) "absent" true
          (March_refinecheck.Obligation.verdict_at (call_span_of src "plain") = None))

  ; (* Lifecycle: the index is per-module state cleared by the same [reset]
       [Refine_check.check_module] already calls at its top.  A verdict that
       outlived its module would let a later module read a `proved` that was
       never established for it — the worst failure this index can have. *)
    Alcotest.test_case "reset clears the index" `Quick (fun () ->
        let src =
          "mod VQReset do\n\
          \  fn takepos(k : {Int | _ >= 0}) : Int do k end\n\
          \  fn go() : Int do takepos(1) end\n\
           end\n"
        in
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error src);
        let sp = call_span_of src "takepos" in
        Alcotest.(check bool) "recorded before reset" true
          (March_refinecheck.Obligation.verdict_at sp <> None);
        March_refinecheck.Obligation.reset ();
        Alcotest.(check bool) "gone after reset" true
          (March_refinecheck.Obligation.verdict_at sp = None))

  ; (* The index must agree with the ledger `--refine-report` prints, entry
       for entry — they are the same records seen two ways, and a divergence
       between them is exactly the drift this mechanism exists to avoid. *)
    gated "every ledger entry is reachable through the index" (fun () ->
        let src =
          "mod VQAgree do\n\
          \  fn takepos(k : {Int | _ >= 0}) : Int do k end\n\
          \  fn nonzero(d : {Int | _ != 0}) : Int do d end\n\
          \  fn go() : Int do takepos(1) + nonzero(2) end\n\
           end\n"
        in
        March_refinecheck.Obligation.reset ();
        ignore (has_refine_error src);
        let all = March_refinecheck.Obligation.all () in
        Alcotest.(check bool) "ledger non-empty" true (all <> []);
        List.iter
          (fun (o : March_refinecheck.Obligation.t) ->
            Alcotest.(check bool) "indexed" true
              (List.exists
                 (fun (o' : March_refinecheck.Obligation.t) -> o' == o)
                 (March_refinecheck.Obligation.obligations_at o.March_refinecheck.Obligation.span)))
          all)
  ]

(* ── `cap no_panic` by proof (Task 3) ──────────────────────────────────────
   Before this task, every name on the panic-surface ban list was rejected
   inside a `cap no_panic` module by a purely syntactic name match, plus a
   transitive fixpoint that blamed every caller up the chain.  For the names
   that carry a REAL refinement contract, the ban is now a question about the
   call's own verdict: `Proved` (and only `Proved`) is silent.

   These fixtures run the production pipeline — typecheck (which still owns the
   syntactic ban for the uncontracted names), then [Refine_check] (which
   populates the per-call-site verdict index), then [Division_safety], then
   [Panic_surface_by_proof] — over the REAL `stdlib/list.march`.  The real
   file, not an inline stand-in: the claim under test is that `List.tail`'s
   SHIPPED contract is what admits a guarded call, and an inline copy would
   keep passing after the shipped contract changed. *)

let load_stdlib_march (name : string) : March_ast.Ast.module_ * string =
  let candidates =
    [ "stdlib/" ^ name; "../../../stdlib/" ^ name; "../../stdlib/" ^ name ]
  in
  match List.find_opt Sys.file_exists candidates with
  | None ->
    Alcotest.failf "cannot find stdlib/%s (searched: %s)" name
      (String.concat ", " candidates)
  | Some path ->
    let src =
      let ic = open_in_bin path in
      let n = in_channel_length ic in
      let buf = Bytes.create n in
      really_input ic buf 0 n;
      close_in ic;
      Bytes.to_string buf
    in
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
    let m =
      March_parser.Parser.module_
        (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
    in
    (March_desugar.Desugar.desugar_module m, path)

(* `list.march` as a sibling `DMod` and `prelude.march` UNWRAPPED into the
   entry module's own decl list — the two shapes bin/main.ml's [load_stdlib]
   actually produces.  The unwrapping is not incidental: it is why prelude's
   `fn tail` is a `DFn` of the `cap no_panic` module under check, which is what
   made the bare spellings resolve for `Refine_check` AND made the syntactic
   fixpoint blame their callers transitively.  A harness that wrapped prelude
   in a `DMod` would exercise neither. *)
let stdlib_list_mod : (March_ast.Ast.decl * string) Lazy.t =
  lazy
    (let m, path = load_stdlib_march "list.march" in
     ( March_ast.Ast.DMod
         ( m.March_ast.Ast.mod_name, March_ast.Ast.Public,
           m.March_ast.Ast.mod_decls, March_ast.Ast.dummy_span ),
       path ))

let stdlib_prelude_decls : (March_ast.Ast.decl list * string) Lazy.t =
  lazy
    (let m, path = load_stdlib_march "prelude.march" in
     (m.March_ast.Ast.mod_decls, path))

(* Same shape as [stdlib_list_mod], for Task 5's `Random.choice_weighted`
   fixtures: the real `stdlib/random.march`, as a sibling `DMod`. Loaded
   alongside `list.march` (its body calls `List.fold_left`/`List.length`) and
   prelude, mirroring bin/main.ml's actual stdlib prepend. *)
let stdlib_random_mod : (March_ast.Ast.decl * string) Lazy.t =
  lazy
    (let m, path = load_stdlib_march "random.march" in
     ( March_ast.Ast.DMod
         ( m.March_ast.Ast.mod_name, March_ast.Ast.Public,
           m.March_ast.Ast.mod_decls, March_ast.Ast.dummy_span ),
       path ))

(* Same shape again, for Task 6's six `Stats` functions: the real
   `stdlib/stats.march`. `Stats` calls `List.fold_left`/`List.length`/
   `List.sort_by`/`List.nth`/`List.map`, so it is loaded alongside
   `list.march` and prelude, same as `Random.choice_weighted` above. *)
let stdlib_stats_mod : (March_ast.Ast.decl * string) Lazy.t =
  lazy
    (let m, path = load_stdlib_march "stats.march" in
     ( March_ast.Ast.DMod
         ( m.March_ast.Ast.mod_name, March_ast.Ast.Public,
           m.March_ast.Ast.mod_decls, March_ast.Ast.dummy_span ),
       path ))

(* Every `cap no_panic` diagnostic [src] produces, from EITHER pass.  Filtered
   on the shared "(declared `cap no_panic`)" phrasing rather than counting all
   errors, so unrelated type noise from checking a lone stdlib file in
   isolation cannot make one of these assertions pass or fail for the wrong
   reason. *)
let no_panic_errors (src : string) : string list =
  let m = March_desugar.Desugar.desugar_module (parse src) in
  let listmod, list_path = Lazy.force stdlib_list_mod in
  let prelude_decls, prelude_path = Lazy.force stdlib_prelude_decls in
  let m =
    { m with
      March_ast.Ast.mod_decls =
        (listmod :: prelude_decls) @ m.March_ast.Ast.mod_decls }
  in
  (* Mirror bin/main.ml: a pipeline that runs [Panic_surface_by_proof] tells the
     typechecker to leave the contracted names alone.  Set here rather than
     globally so the [no-panic-syntactic-fallback] group below can exercise the
     OTHER mode (`march check` / the LSP) in the same process. *)
  (* [Fun.protect]: the flag is process-global and defaults to FALSE for safety.
     An exception escaping any of these passes with a bare reset would leak
     `true` into every later case in this binary — including the
     [no-panic-syntactic-fallback] group below, whose entire subject is that
     default.  That would WEAKEN those assertions rather than fail them, which
     is the worst failure shape a fail-closed default can have. *)
  March_typecheck.Typecheck.proof_based_panic_surface := true;
  let errors =
    Fun.protect
      ~finally:(fun () ->
        March_typecheck.Typecheck.proof_based_panic_surface := false)
      (fun () ->
        let errors, _ = March_typecheck.Typecheck.check_module m in
        March_refinecheck.Refine_check.check_module
          ~stdlib_files:[ list_path; prelude_path ] errors m;
        March_refinecheck.Division_safety.check_module errors m;
        March_refinecheck.Panic_surface_by_proof.check_module errors m;
        errors)
  in
  (* Only diagnostics pointing at the FIXTURE, mirroring bin/main.ml's
     [is_user_file].  Prelude is unwrapped into this module, so its own
     `fn tail`/`head`/`last`/`unwrap`/`expect` are decls under check and report
     against themselves; the compiler never shows those to a user, and counting
     them here would make every count assertion below meaningless.  A
     string-parsed fixture's spans carry the empty filename. *)
  List.filter_map
    (fun (d : March_errors.Errors.diagnostic) ->
      let f = d.March_errors.Errors.span.March_ast.Ast.file in
      if
        d.March_errors.Errors.severity = March_errors.Errors.Error
        && (f = "" || f = "<unknown>")
        && contains d.March_errors.Errors.message "(declared `cap no_panic`)"
      then Some d.March_errors.Errors.message
      else None)
    errors.March_errors.Errors.diagnostics

let has_no_panic_error src = no_panic_errors src <> []
let has_no_panic_error_count src = List.length (no_panic_errors src)

(* ── The suggestion probes must not move the verdict ───────────────────────
   [no_panic_errors] with the `--refine-suggest*` probes interleaved BETWEEN
   [Refine_check] (which populates [Obligation.by_span]) and
   [Panic_surface_by_proof] (which reads it) — the position bin/main.ml's
   `compile` actually ran them in when this was found.

   Each probe [Obligation.reset]s and then refills the ledger AND the
   per-call-site index by re-walking a HYPOTHESIS module: the user's program
   with a speculative contract spliced into one signature.  With the index left
   in that state, [Panic_surface_by_proof] read a hypothesis's verdicts as the
   program's, and `cap no_panic` flipped in BOTH directions on a
   diagnostic-only flag:

     - fail-OPEN: an unguarded `List.tail` compiled clean, because a probe had
       hypothesised `{List(Int) | len(_) > 0}` on the parameter and recorded
       `Proved` at that very span.  A capability that promises no panics,
       silently voided by passing `--refine-suggest-all` (or by `forge refine`,
       which shells out to `--check --refine-suggest-json`).
     - fail-CLOSED: a correctly-guarded call ERRORED, because the last
       hypothesis probed left no `Proved` at that span.

   Both directions are asserted below, and they must stay that way: a fix that
   closed only the fail-open one (say, by making an absent verdict louder) would
   pass a one-sided test while breaking every correct program under the flag.

   Deliberately runs the probes in the OLD, hazardous position rather than the
   fixed one.  bin/main.ml now runs the two consumer passes BEFORE the printers,
   but ordering is an invariant no reader of [by_span] can see; the probes are
   also non-destructive now ([Obligation.with_scratch]), and this harness is
   what pins THAT.  Ordering the harness the safe way would make it pass with
   the real defect still in place.

   The budget is small on purpose: the unsound fixture's polluting candidate is
   the very first one tried, so a large budget only buys solver time. *)
let no_panic_errors_under_suggestion_probes (src : string) : string list =
  let m = March_desugar.Desugar.desugar_module (parse src) in
  let listmod, list_path = Lazy.force stdlib_list_mod in
  let prelude_decls, prelude_path = Lazy.force stdlib_prelude_decls in
  let m =
    { m with
      March_ast.Ast.mod_decls =
        (listmod :: prelude_decls) @ m.March_ast.Ast.mod_decls }
  in
  (* The fixture is parsed from a string, so its spans carry the empty
     filename; the prepended stdlib decls carry real paths.  Same split
     [no_panic_errors] uses to filter diagnostics. *)
  let is_user (sp : March_ast.Ast.span) =
    sp.March_ast.Ast.file = "" || sp.March_ast.Ast.file = "<unknown>"
  in
  March_typecheck.Typecheck.proof_based_panic_surface := true;
  let errors =
    Fun.protect
      ~finally:(fun () ->
        March_typecheck.Typecheck.proof_based_panic_surface := false)
      (fun () ->
        let errors, _ = March_typecheck.Typecheck.check_module m in
        March_refinecheck.Refine_check.check_module
          ~stdlib_files:[ list_path; prelude_path ] errors m;
        March_refinecheck.Division_safety.check_module errors m;
        (* The printer, in its old position.  Results discarded — the subject
           is the side effect on the verdict index, not the advice.

           [Precond_infer] only, matching plain `--refine-suggest-all`, and NOT
           chased with a [Postcond_infer] sweep: a postcondition probe's last
           walk is over a tree whose PRECONDITIONS are unmodified, so it tends
           to refill the index with something close to the truth and mask the
           very corruption under test.  That is not a fix — which sweep runs
           last is a user's choice of flag — but it does neuter the assertion,
           and an earlier draft of this test passed against the unfixed
           compiler for exactly that reason. *)
        ignore
          (March_refinecheck.Precond_infer.suggest_all ~budget:20 ~is_user m
            : March_refinecheck.Precond_infer.t list);
        March_refinecheck.Panic_surface_by_proof.check_module errors m;
        errors)
  in
  List.filter_map
    (fun (d : March_errors.Errors.diagnostic) ->
      let f = d.March_errors.Errors.span.March_ast.Ast.file in
      if
        d.March_errors.Errors.severity = March_errors.Errors.Error
        && (f = "" || f = "<unknown>")
        && contains d.March_errors.Errors.message "(declared `cap no_panic`)"
      then Some d.March_errors.Errors.message
      else None)
    errors.March_errors.Errors.diagnostics

let has_no_panic_error_probed src =
  no_panic_errors_under_suggestion_probes src <> []

(* Same as [no_panic_errors], with `random.march` prepended alongside
   `list.march` and prelude, for Task 5's `Random.choice_weighted` fixtures
   (whose contract is `{List((a, Float)) | len(_) > 0}` — the first name in
   this plan whose refined parameter is a list of TUPLES rather than a plain
   list). *)
let no_panic_errors_with_random (src : string) : string list =
  let m = March_desugar.Desugar.desugar_module (parse src) in
  let listmod, list_path = Lazy.force stdlib_list_mod in
  let randmod, rand_path = Lazy.force stdlib_random_mod in
  let prelude_decls, prelude_path = Lazy.force stdlib_prelude_decls in
  let m =
    { m with
      March_ast.Ast.mod_decls =
        (listmod :: randmod :: prelude_decls) @ m.March_ast.Ast.mod_decls }
  in
  March_typecheck.Typecheck.proof_based_panic_surface := true;
  let errors =
    Fun.protect
      ~finally:(fun () ->
        March_typecheck.Typecheck.proof_based_panic_surface := false)
      (fun () ->
        let errors, _ = March_typecheck.Typecheck.check_module m in
        March_refinecheck.Refine_check.check_module
          ~stdlib_files:[ list_path; rand_path; prelude_path ] errors m;
        March_refinecheck.Division_safety.check_module errors m;
        March_refinecheck.Panic_surface_by_proof.check_module errors m;
        errors)
  in
  List.filter_map
    (fun (d : March_errors.Errors.diagnostic) ->
      let f = d.March_errors.Errors.span.March_ast.Ast.file in
      if
        d.March_errors.Errors.severity = March_errors.Errors.Error
        && (f = "" || f = "<unknown>")
        && contains d.March_errors.Errors.message "(declared `cap no_panic`)"
      then Some d.March_errors.Errors.message
      else None)
    errors.March_errors.Errors.diagnostics

let has_no_panic_error_random src = no_panic_errors_with_random src <> []

(* Same as [no_panic_errors], with `stats.march` prepended alongside
   `list.march` and prelude, for Task 6's six `Stats` fixtures and Task 7's
   three bivariate ones.  Returns ALL diagnostics so callers can look at the
   unverified-precondition HINTS as well as the errors — Task 7's two
   preconditions per function sit on the same call site and produce the same
   error text, so only the hint distinguishes which one went undischarged. *)
let stats_diagnostics (src : string) : March_errors.Errors.diagnostic list =
  let m = March_desugar.Desugar.desugar_module (parse src) in
  let listmod, list_path = Lazy.force stdlib_list_mod in
  let statsmod, stats_path = Lazy.force stdlib_stats_mod in
  let prelude_decls, prelude_path = Lazy.force stdlib_prelude_decls in
  let m =
    { m with
      March_ast.Ast.mod_decls =
        (listmod :: statsmod :: prelude_decls) @ m.March_ast.Ast.mod_decls }
  in
  March_typecheck.Typecheck.proof_based_panic_surface := true;
  let errors =
    Fun.protect
      ~finally:(fun () ->
        March_typecheck.Typecheck.proof_based_panic_surface := false)
      (fun () ->
        let errors, _ = March_typecheck.Typecheck.check_module m in
        March_refinecheck.Refine_check.check_module
          ~stdlib_files:[ list_path; stats_path; prelude_path ] errors m;
        March_refinecheck.Division_safety.check_module errors m;
        March_refinecheck.Panic_surface_by_proof.check_module errors m;
        errors)
  in
  errors.March_errors.Errors.diagnostics

let no_panic_errors_with_stats (src : string) : string list =
  List.filter_map
    (fun (d : March_errors.Errors.diagnostic) ->
      let f = d.March_errors.Errors.span.March_ast.Ast.file in
      if
        d.March_errors.Errors.severity = March_errors.Errors.Error
        && (f = "" || f = "<unknown>")
        && contains d.March_errors.Errors.message "(declared `cap no_panic`)"
      then Some d.March_errors.Errors.message
      else None)
    (stats_diagnostics src)

let has_no_panic_error_stats src = no_panic_errors_with_stats src <> []

(* The unverified-precondition HINTS for a `Stats` fixture — the text of each
   `precondition `P` on `F` was NOT verified here.` note.  Task 7 needs this:
   `covariance`/`correlation`/`linear_regression` each carry TWO preconditions
   at the same call site, so an assertion that merely says "this errors" would
   pass whichever of the two went undischarged.  Asserting on the hint is what
   makes the equal-length test and the short-list test genuinely distinct, and
   is what a mutation of only the relational comparison flips. *)
let unverified_preconditions_stats (src : string) : string list =
  List.filter_map
    (fun (d : March_errors.Errors.diagnostic) ->
      (* Same fixture-only span filter the error path uses: the harness
         prepends the REAL `list.march`/`stats.march`, whose own bodies raise
         their own unverified-precondition hints (`List.nth`, `last`). Counting
         those would make every assertion below pass for the wrong reason. *)
      let f = d.March_errors.Errors.span.March_ast.Ast.file in
      if
        d.March_errors.Errors.severity = March_errors.Errors.Hint
        && (f = "" || f = "<unknown>")
        && contains d.March_errors.Errors.message "was NOT verified here"
      then Some d.March_errors.Errors.message
      else None)
    (stats_diagnostics src)

(* Did [src] leave exactly the precondition spelled [pred] undischarged (and
   not the sibling one)? *)
let only_unverified_is (pred : string) (src : string) : bool =
  let hints = unverified_preconditions_stats src in
  hints <> []
  && List.for_all (fun h -> contains h ("precondition `" ^ pred ^ "`")) hints

(* Fixtures for the probe-interference pair.  Kept next to each other and
   deliberately minimal: the ONLY difference is the parameter's refinement, so
   the pair isolates the verdict rather than any other property of the code. *)
let probe_unguarded_src =
  "mod PSUnguarded do\n\
  \  cap no_panic\n\
  \  fn f(xs : List(Int)) : List(Int) do List.tail(xs) end\n\
   end\n"

(* TWO guarded functions, not one, and that is load-bearing.  The fail-CLOSED
   direction needs the sweep to move ON from the function under assertion:
   [Precond_infer.prune] rebuilds a tree holding only the CURRENT target, so
   after `g`'s probe the index holds nothing at all for `f`'s call site — and
   "no verdict recorded here" is (correctly, fail-closed) an error.  With a
   single-function fixture the last walk is that same function's, the index
   happens to end up right, and the assertion passes against the unfixed
   compiler.  It did; that is why there are two. *)
let probe_guarded_src =
  "mod PSGuarded do\n\
  \  cap no_panic\n\
  \  fn f(xs : {List(Int) | len(_) > 0}) : List(Int) do List.tail(xs) end\n\
  \  fn g(ys : {List(Int) | len(_) > 0}) : List(Int) do List.tail(ys) end\n\
   end\n"

let no_panic_proof_suite =
  [ (* ── Regression: `--refine-suggest*` must not move the verdict ──────────
       See [no_panic_errors_under_suggestion_probes].  Four assertions, not
       two: each fixture is checked WITHOUT the probes as well, so a harness
       that stopped exercising the pipeline at all (or a fixture that stopped
       compiling the way it reads) fails loudly instead of agreeing with
       itself. *)
    gated "cap no_panic: unguarded List.tail errors with AND without probes"
      (fun () ->
        Alcotest.(check bool)
          "errors without probes" true (has_no_panic_error probe_unguarded_src);
        Alcotest.(check bool)
          "errors with --refine-suggest probes interleaved" true
          (has_no_panic_error_probed probe_unguarded_src))

  ; gated "cap no_panic: guarded List.tail is clean with AND without probes"
      (fun () ->
        Alcotest.(check bool)
          "clean without probes" false (has_no_panic_error probe_guarded_src);
        Alcotest.(check bool)
          "clean with --refine-suggest probes interleaved" false
          (has_no_panic_error_probed probe_guarded_src))

  ; (* THE POINT OF THIS TASK.  Inverted from test_compiler.ml's
       [test_cap_no_panic_list_tail_guarded_still_error], which Task 1 pinned
       with the docstring "blunt until Task 3" — the two together document the
       before/after. *)
    gated "cap no_panic: a PROVABLY safe List.tail compiles clean" (fun () ->
        Alcotest.(check bool)
          "no error" false
          (has_no_panic_error
             "mod PT do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Int)) : List(Int) do\n\
             \    if List.length(xs) > 0 do List.tail(xs) else xs end\n\
             \  end\n\
              end\n"))

  ; (* REJECT control: the definite-failure floor must hold. *)
    gated "cap no_panic: an unguarded List.tail still errors after Task 3"
      (fun () ->
        Alcotest.(check bool)
          "error" true
          (has_no_panic_error
             "mod UT do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Int)) : List(Int) do List.tail(xs) end\n\
              end\n"))

  ; (* Fail-closed: not provably safe, not provably unsafe — still an error,
       matching `cap no_panic`'s conservative stance for division.  Getting
       this direction backwards silently reopens every coverage hole Task 1
       closed. *)
    gated "cap no_panic: an UNDECIDABLE List.tail call still errors (fail-closed)"
      (fun () ->
        Alcotest.(check bool)
          "error" true
          (has_no_panic_error
             "mod XT do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Int), flag : Bool) : List(Int) do\n\
             \    if flag do List.tail(xs) else xs end\n\
             \  end\n\
              end\n"))

  ; (* Dropped transitivity: ONE error at the real site, not one per caller.
       Before this task the fixpoint reported three. *)
    gated "cap no_panic: transitive blame is gone for proof-covered names"
      (fun () ->
        let n =
          has_no_panic_error_count
            "mod TB do\n\
            \  cap no_panic\n\
            \  fn helper(xs : List(Int)) : List(Int) do List.tail(xs) end\n\
            \  fn caller1(xs : List(Int)) : List(Int) do helper(xs) end\n\
            \  fn caller2(xs : List(Int)) : List(Int) do helper(xs) end\n\
             end\n"
        in
        Alcotest.(check int) "exactly one error, not three" 1 n)

  ; (* The five BARE prelude spellings, which the qualified fixtures above do
       not exercise at all.  They matter because they reach the checker by a
       different route: prelude is UNWRAPPED into the entry module, so
       `tail(xs)` resolves against a `DFn` sitting in this module's own decl
       list rather than against a `DMod` member.

       Measured while fixing this: bare calls DO resolve — `--refine-report`
       showed `1 proved` for the guarded form — and yet the call was still
       rejected, with a *transitive* message, because that same unwrapping put
       prelude's `fn tail` into the syntactic fixpoint's `local_fns` and its
       body calls `panic`. A proof-based verdict is never consulted on the
       transitive path, so the feature was inert for 5 of its 25 names and the
       unguarded form reported TWICE. Hence the count assertion here, not a
       bool: a bool would have called the double-report a pass. *)
    gated "cap no_panic: a PROVABLY safe BARE prelude tail compiles clean"
      (fun () ->
        Alcotest.(check bool)
          "no error" false
          (has_no_panic_error
             "mod BT do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Int)) : List(Int) do\n\
             \    if List.length(xs) > 0 do tail(xs) else xs end\n\
             \  end\n\
              end\n"))

  ; gated "cap no_panic: an unguarded BARE prelude tail errors exactly ONCE"
      (fun () ->
        Alcotest.(check int)
          "one error, not one direct plus one transitive" 1
          (has_no_panic_error_count
             "mod BTU do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Int)) : List(Int) do tail(xs) end\n\
              end\n"))

  ; (* REGRESSION: `panic` keeps BOTH its syntactic ban and its transitive
       fixpoint.  Same shape as the case above, opposite expectation — three
       errors, because no contract exists or could exist for `panic`. *)
    Alcotest.test_case "cap no_panic: panic keeps its transitive blame" `Quick
      (fun () ->
        let n =
          has_no_panic_error_count
            "mod TP do\n\
            \  cap no_panic\n\
            \  fn helper(x : Int) : Int do panic(\"boom\") end\n\
            \  fn caller1(x : Int) : Int do helper(x) end\n\
            \  fn caller2(x : Int) : Int do helper(x) end\n\
             end\n"
        in
        Alcotest.(check int) "direct site plus two transitive callers" 3 n)

  ; (* ── Task 5: `Random.choice_weighted` (2026-08-05) ───────────────────
       Same shape as the `List.tail` trio above, over the real
       `stdlib/random.march`. The contract is `{List((a, Float)) | len(_) >
       0}` — a tuple-ELEMENT list, the first this plan's proof machinery has
       had to discharge `len` over. A guarded call must be PROVED, not merely
       accepted for some unrelated reason (e.g. a solver-undecided call being
       silently let through) — this is the positive-discharge control that
       distinguishes a working contract from one that checks nothing. *)
    gated
      "cap no_panic: a PROVABLY safe Random.choice_weighted (guarded) compiles clean"
      (fun () ->
        Alcotest.(check bool)
          "no error" false
          (has_no_panic_error_random
             "mod RW1 do\n\
             \  cap no_panic\n\
             \  fn f(rng : Random.Rng, items : List((Int, Float))) : (Int, Random.Rng) do\n\
             \    if List.length(items) > 0 do Random.choice_weighted(rng, items)\n\
             \    else (0, rng) end\n\
             \  end\n\
              end\n"))

  ; (* REJECT control: the definite-failure floor must hold — an unguarded
       call still errors after the contract is wired into the covered set. *)
    gated "cap no_panic: an unguarded Random.choice_weighted still errors"
      (fun () ->
        Alcotest.(check bool)
          "error" true
          (has_no_panic_error_random
             "mod RW2 do\n\
             \  cap no_panic\n\
             \  fn f(rng : Random.Rng, items : List((Int, Float))) : (Int, Random.Rng) do\n\
             \    Random.choice_weighted(rng, items)\n\
             \  end\n\
              end\n"))

  ; (* Fail-closed: an undecidable guard (a Bool flag, not a length check)
       must still error — matching the `List.tail` undecidable case above. *)
    gated
      "cap no_panic: an UNDECIDABLE Random.choice_weighted call still errors (fail-closed)"
      (fun () ->
        Alcotest.(check bool)
          "error" true
          (has_no_panic_error_random
             "mod RW3 do\n\
             \  cap no_panic\n\
             \  fn f(rng : Random.Rng, items : List((Int, Float)), flag : Bool)\n\
             \      : (Int, Random.Rng) do\n\
             \    if flag do Random.choice_weighted(rng, items) else (0, rng) end\n\
             \  end\n\
              end\n"))

  ; (* ── Task 6: `Stats` — six functions needing only the length
       precondition (2026-08-05) ──────────────────────────────────────────
       `percentile`, `quantile`, `quantiles`, `five_number_summary`,
       `variance`, `mode` all panic on `Nil` with their own "empty list"
       message and none carried `{List(Float) | len(_) > 0}` before this
       task (unlike `Stats.mean`/`min_val`/`max_val`, contracted earlier).
       Six REJECT controls below, one per function — each is a call into
       that function's own real body in `stdlib/stats.march`, so each
       exercises its own panic message and precondition wiring, not just a
       shared shape. Only two ACCEPT cases are written (the shared shape is
       proven once), but one of them — `percentile` — is the two-refined-
       parameter case: it must discharge BOTH the `xs` length precondition
       added here AND the pre-existing `p ∈ [0, 100]` precondition
       together, confirming the two coexist. *)
    gated
      "cap no_panic: a PROVABLY safe Stats.percentile (both preconditions guarded) compiles clean"
      (fun () ->
        Alcotest.(check bool)
          "no error" false
          (has_no_panic_error_stats
             "mod SP1 do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Float), p : Float) : Float do\n\
             \    if List.length(xs) > 0 && p >= 0.0 && p <= 100.0 do Stats.percentile(xs, p)\n\
             \    else 0.0 end\n\
             \  end\n\
              end\n"))

  ; gated
      "cap no_panic: a PROVABLY safe Stats.variance (guarded) compiles clean"
      (fun () ->
        Alcotest.(check bool)
          "no error" false
          (has_no_panic_error_stats
             "mod SV1 do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Float)) : Float do\n\
             \    if List.length(xs) > 0 do Stats.variance(xs) else 0.0 end\n\
             \  end\n\
              end\n"))

  ; gated "cap no_panic: an unguarded Stats.percentile still errors"
      (fun () ->
        Alcotest.(check bool)
          "error" true
          (has_no_panic_error_stats
             "mod SPR do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Float), p : Float) : Float do Stats.percentile(xs, p) end\n\
              end\n"))

  ; gated "cap no_panic: an unguarded Stats.quantile still errors"
      (fun () ->
        Alcotest.(check bool)
          "error" true
          (has_no_panic_error_stats
             "mod SQR do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Float), q : Float) : Float do\n\
             \    Stats.quantile(xs, q, Stats.Linear)\n\
             \  end\n\
              end\n"))

  ; gated "cap no_panic: an unguarded Stats.quantiles still errors"
      (fun () ->
        Alcotest.(check bool)
          "error" true
          (has_no_panic_error_stats
             "mod SQSR do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Float), qs : List(Float)) : List(Float) do\n\
             \    Stats.quantiles(xs, qs, Stats.Linear)\n\
             \  end\n\
              end\n"))

  ; gated "cap no_panic: an unguarded Stats.five_number_summary still errors"
      (fun () ->
        Alcotest.(check bool)
          "error" true
          (has_no_panic_error_stats
             "mod SFR do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Float)) : (Float, Float, Float, Float, Float) do\n\
             \    Stats.five_number_summary(xs, Stats.Linear)\n\
             \  end\n\
              end\n"))

  ; gated "cap no_panic: an unguarded Stats.variance still errors"
      (fun () ->
        Alcotest.(check bool)
          "error" true
          (has_no_panic_error_stats
             "mod SVR do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Float)) : Float do Stats.variance(xs) end\n\
              end\n"))

  ; gated "cap no_panic: an unguarded Stats.mode still errors"
      (fun () ->
        Alcotest.(check bool)
          "error" true
          (has_no_panic_error_stats
             "mod SMR do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Float)) : Float do Stats.mode(xs) end\n\
              end\n"))

  ; (* ── Task 7: `Stats` bivariate — the RELATIONAL precondition
       (2026-08-05) ───────────────────────────────────────────────────────
       `covariance`, `correlation` and `linear_regression` each take two
       `List(Float)`s and panic on unequal lengths OR on fewer than 2
       elements. Both are structural, so both are contracted:

         xs : {List(Float) | len(_) >= 2}
         ys : {List(Float) | len(_) == len(xs)}

       `ys`'s predicate references a SIBLING parameter's measure. That is not
       new machinery — it is exactly the shape `List.nth`'s already-shipped
       `n : {Int | _ >= 0 && _ < len(xs)}` uses; the only novelty is `==`
       rather than `<`.

       Two preconditions on one call site means "this errors" alone is a weak
       assertion: it would pass whichever of the two went undischarged. The
       REJECT controls below therefore assert on the unverified-precondition
       HINT, so the equal-length control and the short-list control are
       genuinely distinct tests and a mutation of only the relational
       comparison flips only the former. *)
    gated
      "cap no_panic: a PROVABLY safe Stats.covariance (both preconditions guarded) compiles clean"
      (fun () ->
        Alcotest.(check bool)
          "no error" false
          (has_no_panic_error_stats
             "mod SCV1 do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Float), ys : List(Float)) : Float do\n\
             \    if List.length(xs) >= 2 && List.length(ys) == List.length(xs) do\n\
             \      Stats.covariance(xs, ys)\n\
             \    else 0.0 end\n\
             \  end\n\
              end\n"))

  ; gated
      "cap no_panic: a PROVABLY safe Stats.correlation / Stats.linear_regression compiles clean"
      (fun () ->
        Alcotest.(check bool)
          "no error" false
          (has_no_panic_error_stats
             "mod SCR1 do\n\
             \  cap no_panic\n\
             \  fn a(xs : List(Float), ys : List(Float)) : Float do\n\
             \    if List.length(xs) >= 2 && List.length(ys) == List.length(xs) do\n\
             \      Stats.correlation(xs, ys)\n\
             \    else 0.0 end\n\
             \  end\n\
             \  fn b(xs : List(Float), ys : List(Float)) : (Float, Float) do\n\
             \    if List.length(xs) >= 2 && List.length(ys) == List.length(xs) do\n\
             \      Stats.linear_regression(xs, ys)\n\
             \    else (0.0, 0.0) end\n\
             \  end\n\
              end\n"))

  ; (* REJECT — equal-length violation, one per function. The short-list
       precondition IS guarded here, so the only thing left undischarged is
       the relational one. These are the tests a mutation of the equal-length
       comparison alone must flip. *)
    gated
      "cap no_panic: Stats.covariance with only the length>=2 guard errors on the RELATIONAL precondition"
      (fun () ->
        Alcotest.(check bool)
          "relational precondition unverified" true
          (only_unverified_is "len(_) == len(xs)"
             "mod SCV2 do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Float), ys : List(Float)) : Float do\n\
             \    if List.length(xs) >= 2 do Stats.covariance(xs, ys) else 0.0 end\n\
             \  end\n\
              end\n"))

  ; gated
      "cap no_panic: Stats.correlation with only the length>=2 guard errors on the RELATIONAL precondition"
      (fun () ->
        Alcotest.(check bool)
          "relational precondition unverified" true
          (only_unverified_is "len(_) == len(xs)"
             "mod SCR2 do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Float), ys : List(Float)) : Float do\n\
             \    if List.length(xs) >= 2 do Stats.correlation(xs, ys) else 0.0 end\n\
             \  end\n\
              end\n"))

  ; gated
      "cap no_panic: Stats.linear_regression with only the length>=2 guard errors on the RELATIONAL precondition"
      (fun () ->
        Alcotest.(check bool)
          "relational precondition unverified" true
          (only_unverified_is "len(_) == len(xs)"
             "mod SLR2 do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Float), ys : List(Float)) : (Float, Float) do\n\
             \    if List.length(xs) >= 2 do Stats.linear_regression(xs, ys)\n\
             \    else (0.0, 0.0) end\n\
             \  end\n\
              end\n"))

  ; (* REJECT — short-list violation, one per function. Mirror image: the
       relational guard IS present, so only `len(_) >= 2` is undischarged. *)
    gated
      "cap no_panic: Stats.covariance with only the equal-length guard errors on the SHORT-LIST precondition"
      (fun () ->
        Alcotest.(check bool)
          "short-list precondition unverified" true
          (only_unverified_is "len(_) >= 2"
             "mod SCV3 do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Float), ys : List(Float)) : Float do\n\
             \    if List.length(ys) == List.length(xs) do Stats.covariance(xs, ys)\n\
             \    else 0.0 end\n\
             \  end\n\
              end\n"))

  ; gated
      "cap no_panic: Stats.correlation with only the equal-length guard errors on the SHORT-LIST precondition"
      (fun () ->
        Alcotest.(check bool)
          "short-list precondition unverified" true
          (only_unverified_is "len(_) >= 2"
             "mod SCR3 do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Float), ys : List(Float)) : Float do\n\
             \    if List.length(ys) == List.length(xs) do Stats.correlation(xs, ys)\n\
             \    else 0.0 end\n\
             \  end\n\
              end\n"))

  ; gated
      "cap no_panic: Stats.linear_regression with only the equal-length guard errors on the SHORT-LIST precondition"
      (fun () ->
        Alcotest.(check bool)
          "short-list precondition unverified" true
          (only_unverified_is "len(_) >= 2"
             "mod SLR3 do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Float), ys : List(Float)) : (Float, Float) do\n\
             \    if List.length(ys) == List.length(xs) do\n\
             \      Stats.linear_regression(xs, ys)\n\
             \    else (0.0, 0.0) end\n\
             \  end\n\
              end\n"))

  ; (* Fully unguarded: both preconditions undischarged, and the call errors. *)
    gated "cap no_panic: an unguarded Stats.covariance still errors"
      (fun () ->
        Alcotest.(check bool)
          "error" true
          (has_no_panic_error_stats
             "mod SCV4 do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Float), ys : List(Float)) : Float do\n\
             \    Stats.covariance(xs, ys)\n\
             \  end\n\
              end\n"))
  ]

(* ── The typecheck-only FALLBACK (`march check`, `march caps`, the LSP) ────
   March has three check pipelines and only two run refinecheck.
   [run_check_cmd] (`march check` / `march caps`) is package-level and
   typecheck-only, seeded from a cached stdlib env and deliberately skipping
   the solver; the LSP does not even link march_refinecheck.  With no verdict
   index there is nothing to consult, and `cap no_panic` is a guarantee, so
   "cannot prove" has to mean "reject".

   [Typecheck.proof_based_panic_surface] therefore defaults to FALSE and the
   contracted names stay unconditionally banned — including their transitive
   fixpoint — exactly as before 2026-08-05.  Between the first draft of this
   task and now, that default was the difference between `march check` exiting
   1 and exiting 0 on provably panicky code.

   These cases run the typechecker ALONE with the flag at its default, which is
   what those two pipelines do. *)
let syntactic_no_panic_errors (src : string) : int =
  let m = March_desugar.Desugar.desugar_module (parse src) in
  (* Default, not set: a pipeline that forgets to opt in must get the
     conservative answer, so the absence of an assignment is the assertion. *)
  let errors, _ = March_typecheck.Typecheck.check_module m in
  List.length
    (List.filter
       (fun (d : March_errors.Errors.diagnostic) ->
         d.March_errors.Errors.severity = March_errors.Errors.Error
         && contains d.March_errors.Errors.message "(declared `cap no_panic`)")
       errors.March_errors.Errors.diagnostics)

let syntactic_fallback_suite =
  [ Alcotest.test_case "an unguarded contracted call is still banned" `Quick
      (fun () ->
        Alcotest.(check int) "one error" 1
          (syntactic_no_panic_errors
             "mod SF1 do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Int)) : List(Int) do List.tail(xs) end\n\
              end\n"))

  ; (* Deliberately MORE conservative than the full pipeline, which admits this
       exact fixture. Documented as a divergence in both capability docs; the
       alternative — staying silent — would let genuinely panicky code pass
       `march check`. *)
    Alcotest.test_case "a GUARDED contracted call is also banned (no prover here)"
      `Quick (fun () ->
        Alcotest.(check int) "one error" 1
          (syntactic_no_panic_errors
             "mod SF2 do\n\
             \  cap no_panic\n\
             \  fn f(xs : List(Int)) : List(Int) do\n\
             \    if List.length(xs) > 0 do List.tail(xs) else xs end\n\
             \  end\n\
              end\n"))

  ; Alcotest.test_case "the bare prelude spelling is banned here too" `Quick
      (fun () ->
        Alcotest.(check int) "one error" 1
          (syntactic_no_panic_errors
             "mod SF3 do\n\
             \  cap no_panic\n\
             \  fn f(o : Option(Int)) : Int do unwrap(o) end\n\
              end\n"))

  ; (* And the OLD transitive blame is intact in this mode — three errors, the
       pre-2026-08-05 behaviour, byte-for-byte what `march check` printed
       before this task. *)
    Alcotest.test_case "transitive blame is intact in the fallback" `Quick
      (fun () ->
        Alcotest.(check int) "direct site plus two callers" 3
          (syntactic_no_panic_errors
             "mod SF4 do\n\
             \  cap no_panic\n\
             \  fn helper(xs : List(Int)) : List(Int) do List.tail(xs) end\n\
             \  fn caller1(xs : List(Int)) : List(Int) do helper(xs) end\n\
             \  fn caller2(xs : List(Int)) : List(Int) do helper(xs) end\n\
              end\n"))

  ; (* REJECT control: the fallback must not have become a blanket rejector. *)
    Alcotest.test_case "a safe cap no_panic module is silent in the fallback"
      `Quick (fun () ->
        Alcotest.(check int) "no error" 0
          (syntactic_no_panic_errors
             "mod SF5 do\n\
             \  cap no_panic\n\
             \  fn f(a : Int) : Int do a + 1 end\n\
              end\n"))

  ; (* Task 5: even a length-guarded Random.choice_weighted call is banned in
       this mode — same divergence as List.tail's SF2 case above, since this
       mode never builds a verdict index to consult. *)
    Alcotest.test_case
      "a GUARDED Random.choice_weighted is also banned (no prover here)" `Quick
      (fun () ->
        Alcotest.(check int) "one error" 1
          (syntactic_no_panic_errors
             "mod SF6 do\n\
             \  cap no_panic\n\
             \  fn f(rng : Random.Rng, items : List((Int, Float)))\n\
             \      : (Int, Random.Rng) do\n\
             \    if List.length(items) > 0 do Random.choice_weighted(rng, items)\n\
             \    else (0, rng) end\n\
             \  end\n\
              end\n"))
  ]

(* ── The verdict FILTER, unit-tested directly ──────────────────────────────
   [Obligation.verdict_at] folds EVERY obligation kind at a span down to the
   weakest verdict.  For this consumer that is actively wrong: a call site
   whose precondition is `Proved` but which happens to share a span with an
   unrelated `Division` or a different callee's obligation would fold to the
   weaker verdict, and a provably-safe call would be REJECTED — a false
   positive, this subsystem's cardinal sin.

   So [Panic_surface_by_proof.verdict_for] filters to [Precondition]
   obligations for the callee in question and folds weakest-wins over only
   those.  Constructing the collision through real March source is not
   currently possible (a postcondition keys on a clause span, a division on the
   `/` node's own span), so the filter is exercised where it actually lives, by
   recording obligations at a shared span by hand.  A test that could only
   observe the filter through source would silently stop testing it the day
   those spans stopped colliding. *)
let vf_span : March_ast.Ast.span =
  { March_ast.Ast.file = "filter.march"; start_line = 1; start_col = 1;
    end_line = 1; end_col = 9 }

let record_at ~callee ~kind ~verdict =
  March_refinecheck.Obligation.record
    { March_refinecheck.Obligation.span = vf_span; callee;
      predicate = "len(_) > 0"; verdict; kind }

let vname = Option.map March_refinecheck.Obligation.verdict_name

let verdict_filter_suite =
  [ Alcotest.test_case "a Proved precondition survives an unrelated Division skip"
      `Quick (fun () ->
        March_refinecheck.Obligation.reset ();
        record_at ~callee:"List.tail" ~kind:March_refinecheck.Obligation.Precondition
          ~verdict:March_refinecheck.Obligation.Proved;
        record_at ~callee:"d" ~kind:March_refinecheck.Obligation.Division
          ~verdict:(March_refinecheck.Obligation.Skipped
                      March_refinecheck.Obligation.Solver_undecided);
        (* What bare [verdict_at] would have said — the false positive this
           filter exists to avoid.  Asserted so the test still means something
           if the fold order ever changes. *)
        Alcotest.(check (option string))
          "unfiltered fold is the WEAK verdict" (Some "skipped")
          (vname (March_refinecheck.Obligation.verdict_at vf_span));
        Alcotest.(check (option string))
          "filtered fold is proved" (Some "proved")
          (vname (March_refinecheck.Panic_surface_by_proof.verdict_for vf_span "List.tail")))

  ; Alcotest.test_case "a DIFFERENT callee's skip at the same span does not veto"
      `Quick (fun () ->
        March_refinecheck.Obligation.reset ();
        record_at ~callee:"List.tail" ~kind:March_refinecheck.Obligation.Precondition
          ~verdict:March_refinecheck.Obligation.Proved;
        record_at ~callee:"List.head" ~kind:March_refinecheck.Obligation.Precondition
          ~verdict:(March_refinecheck.Obligation.Skipped
                      March_refinecheck.Obligation.Solver_undecided);
        Alcotest.(check (option string))
          "proved" (Some "proved")
          (vname (March_refinecheck.Panic_surface_by_proof.verdict_for vf_span "List.tail")))

  ; Alcotest.test_case "weakest-wins WITHIN the filtered set" `Quick (fun () ->
        (* One refined parameter proved and another skipped is NOT a proof.
           The fold must stay pessimistic inside the set it does consider. *)
        March_refinecheck.Obligation.reset ();
        record_at ~callee:"List.tail" ~kind:March_refinecheck.Obligation.Precondition
          ~verdict:March_refinecheck.Obligation.Proved;
        record_at ~callee:"List.tail" ~kind:March_refinecheck.Obligation.Precondition
          ~verdict:(March_refinecheck.Obligation.Skipped
                      March_refinecheck.Obligation.Solver_undecided);
        Alcotest.(check (option string))
          "skipped" (Some "skipped")
          (vname (March_refinecheck.Panic_surface_by_proof.verdict_for vf_span "List.tail")))

  ; Alcotest.test_case "no obligation for this callee reads as absent, never proved"
      `Quick (fun () ->
        March_refinecheck.Obligation.reset ();
        record_at ~callee:"List.head" ~kind:March_refinecheck.Obligation.Precondition
          ~verdict:March_refinecheck.Obligation.Proved;
        Alcotest.(check bool) "absent" true
          (March_refinecheck.Panic_surface_by_proof.verdict_for vf_span "List.tail" = None))

  ; (* `@[trusted]` is an UNCHECKED user assertion.  Honouring it inside a
       capability whose entire purpose is to GUARANTEE no panics would hollow
       out the guarantee, so only [Proved] is silent here — even though
       `cap verified` does accept [Trusted]. *)
    Alcotest.test_case "Trusted is not a proof under cap no_panic" `Quick
      (fun () ->
        March_refinecheck.Obligation.reset ();
        record_at ~callee:"List.tail" ~kind:March_refinecheck.Obligation.Precondition
          ~verdict:March_refinecheck.Obligation.Trusted;
        Alcotest.(check (option string))
          "trusted, and therefore not admitted" (Some "trusted")
          (vname (March_refinecheck.Panic_surface_by_proof.verdict_for vf_span "List.tail"));
        Alcotest.(check bool) "not admitted" false
          (March_refinecheck.Panic_surface_by_proof.is_proved vf_span "List.tail"))
  ]

(* =========================================================================
   Witness harness (counterexample surfacing): the two evaluator hooks the
   validation harness in lib/refinecheck/witness.ml stands on.  Not gated:
   no solver is involved — these drive the interpreter directly.

   The guard test proves an effectful builtin is vetoed THROUGH a normal
   apply chain (not just at top level), and the fuel test proves a divergent
   March function is bounded by the reduction budget rather than hanging the
   compiler.  Both restore the global hook state on every path — the other
   suites in this binary run the real pipeline and must never see a stale
   guard. *)

let witness_harness_suite =
  [ Alcotest.test_case "builtin guard blocks a named builtin through apply" `Quick
      (fun () ->
        let m = March_desugar.Desugar.desugar_module (parse
          "mod M do\n  fn shout() : Unit do println(\"hi\") end\nend\n") in
        let env = March_eval.Eval.eval_module_env m in
        let f = List.assoc "shout" env in
        March_eval.Eval_prim.builtin_guard :=
          Some (fun name ->
            if name = "println" then
              raise (March_eval.Eval_prim.Blocked_builtin name));
        let blocked =
          Fun.protect
            ~finally:(fun () -> March_eval.Eval_prim.builtin_guard := None)
            (fun () ->
              try ignore (March_eval.Eval.apply f []); false
              with March_eval.Eval_prim.Blocked_builtin _ -> true)
        in
        Alcotest.(check bool) "println blocked" true blocked)
  ; Alcotest.test_case "fuel bounds a divergent function" `Quick
      (fun () ->
        let m = March_desugar.Desugar.desugar_module (parse
          "mod M do\n  fn spin(n : Int) : Int do spin(n) end\nend\n") in
        let env = March_eval.Eval.eval_module_env m in
        let f = List.assoc "spin" env in
        March_eval.Eval.arm_reduction_budget 10_000;
        let out =
          Fun.protect
            ~finally:(fun () -> March_eval.Eval.set_reduction_counting false)
            (fun () ->
              try ignore (March_eval.Eval.apply f [March_eval.Eval.VInt 0]); false
              with March_eval.Eval.Yield -> true)
        in
        Alcotest.(check bool) "fuel exhausted" true out)
  ]

(* Witness core: model decoding, structural predicate evaluation, and
   source-syntax rendering — the pure stages of lib/refinecheck/witness.ml.
   Also ungated: no solver, no interpreter run. *)

let witness_core_suite =
  let module W = March_refinecheck.Witness in
  let module A = March_ast.Ast in
  let module V = March_eval.Eval_types in
  let dsp = A.dummy_span in
  let nm t = { A.txt = t; A.span = dsp } in
  let evar t = A.EVar (nm t) in
  let eint n = A.ELit (A.LitInt n, dsp) in
  let eapp f args = A.EApp (evar f, args, dsp) in
  let tycon t args = A.TyCon (nm t, args) in
  let t_int = tycon "Int" [] in
  let render v = Option.value ~default:"<none>" (W.render_value v) in
  [ Alcotest.test_case "decode: negative int model value" `Quick (fun () ->
        match W.decode_model ~params:[ ("x", t_int) ] ~model:[ ("x", "(- 3)") ] with
        | Some [ ("x", V.VInt -3) ] -> ()
        | _ -> Alcotest.fail "expected x = -3")
  ; Alcotest.test_case "decode: string from its len fact" `Quick (fun () ->
        match
          W.decode_model ~params:[ ("s", tycon "String" []) ]
            ~model:[ ("len$s", "2"); ("s", "Str!val!0") ]
        with
        | Some [ ("s", V.VString "aa") ] -> ()
        | _ -> Alcotest.fail "expected s = \"aa\"")
  ; Alcotest.test_case "decode: list zero-filled to its len fact" `Quick (fun () ->
        match
          W.decode_model ~params:[ ("xs", tycon "List" [ t_int ]) ]
            ~model:[ ("len$xs", "2") ]
        with
        | Some [ ("xs", v) ] -> Alcotest.(check string) "render" "[0, 0]" (render v)
        | _ -> Alcotest.fail "expected xs decoded")
  ; Alcotest.test_case "decode: absent param zero-fills" `Quick (fun () ->
        match W.decode_model ~params:[ ("b", tycon "Bool" []) ] ~model:[] with
        | Some [ ("b", V.VBool false) ] -> ()
        | _ -> Alcotest.fail "expected b = false")
  ; Alcotest.test_case "eval_pred: _ >= 0 is false at -1" `Quick (fun () ->
        let pred = eapp ">=" [ evar "_"; eint 0 ] in
        let lookup n = if n = "_" then Some (V.VInt (-1)) else None in
        Alcotest.(check (option bool)) "verdict" (Some false)
          (W.eval_pred ~lookup pred))
  ; Alcotest.test_case "eval_pred: unknown application is None, not false" `Quick
      (fun () ->
        let pred = eapp "is_prime" [ evar "_" ] in
        let lookup _ = Some (V.VInt 7) in
        Alcotest.(check (option bool)) "verdict" None (W.eval_pred ~lookup pred))
  ; Alcotest.test_case "render: cons list in source syntax" `Quick (fun () ->
        let v =
          V.VCon ("Cons", [ V.VInt 1; V.VCon ("Cons", [ V.VInt 2; V.VCon ("Nil", []) ]) ])
        in
        Alcotest.(check string) "render" "[1, 2]" (render v))
  ]

(* Witness end-to-end: a Refuted model that survives interpreter validation
   becomes a definite return-contract error carrying the executed failing
   call; every unconfirmable candidate leaves today's behavior untouched.
   Gated: these need the solver to produce the candidate model. *)

let witness_e2e_suite =
  [ gated "return contract: confirmed witness becomes an error" (fun () ->
        let text =
          refine_error_text_d
            (decl "  fn clamp(x : Int) : {Int | _ >= 0} do x - 1 end") in
        Alcotest.(check bool) "violation reported" true
          (contains text "does not satisfy its return type constraint");
        (* EXACT text: shrinking makes the witness canonical, so a flaky
           model, probe order, or shrink order breaks this immediately. *)
        Alcotest.(check bool) "executed minimal witness" true
          (contains text "but clamp(0) returns -1."))
  ; gated "witness shrinks to the smallest admissible input" (fun () ->
        (* 0 is excluded by the param's own refinement; the fixed probe order
           (0, 1, -1, …) then lands on 1 whatever model Z3 returned. *)
        let text =
          refine_error_text_d
            (decl "  fn g(x : {Int | _ != 0}) : {Int | _ >= 10} do x end") in
        Alcotest.(check bool) "minimal witness" true
          (contains text "but g(1) returns 1."))
  ; gated "spurious model is rejected, no witness claim" (fun () ->
        (* `x * x` is unreflectable, so the else-branch's path condition is
           dropped from the VC and the raw model refutes via a branch the
           program can never take.  Validation runs weird(model) -> 1 ->
           predicate holds -> stays silent. *)
        let text =
          refine_error_text_d
            (decl
               "  fn weird(x : Int) : {Int | _ >= 0} do if x * x >= 0 do 1 \
                else x end end") in
        Alcotest.(check bool) "no witness claim" false (contains text "but weird("))
  ; gated "witness inputs must satisfy the param's own refinement" (fun () ->
        (* Any reported witness for f must respect {Int | _ > 0} on x —
           x = 0 would blame an input the contract already excludes. *)
        let text =
          refine_error_text_d
            (decl "  fn fpos(x : {Int | _ > 0}) : {Int | _ >= 5} do x end") in
        Alcotest.(check bool) "never blames the excluded input" false
          (contains text "fpos(0)"))
  ; gated "cap verified: a confirmed violation reports the witness, not cannot-verify" (fun () ->
        (* One error, the strong one: the witness proves the contract is
           WRONG, which supersedes "the checker could not verify it".  The
           design doc's site table originally planned an appended "In fact…"
           sentence on the cannot-verify message; the Violated verdict makes
           that message unreachable here, which is strictly better. *)
        let text =
          refine_error_text_d
            {|mod CV do
  cap verified
  fn clamp(x : Int) : {Int | _ >= 0} do x - 1 end
  fn main() : Int do clamp(5) end
end|} in
        Alcotest.(check bool) "witness error" true
          (contains text "but clamp(0) returns -1.");
        Alcotest.(check bool) "no cannot-verify for this contract" false
          (contains text "cannot verify return type constraint `_ >= 0`"))
  ; gated "precondition cx is validated and minimal" (fun () ->
        (* The inline example is re-derived through the witness pipeline:
           admissible under the caller's own refinement (k < 0), evaluated
           against the violated predicate, shrunk to the smallest weight. *)
        let text =
          refine_error_text_d
            (decl "  fn fk(k : {Int | _ < 0}) : Int do take_n(k) end") in
        Alcotest.(check bool) "violation" true
          (contains text "refinement violation");
        Alcotest.(check bool) "minimal validated example" true
          (contains text "(e.g. k = -1)"))
  ; gated "precondition cx renders an empty list in source syntax" (fun () ->
        (* Today this prints the measure fact `len(ys) = 0`; the concrete
           value `ys = []` is what the user can actually paste. *)
        let text =
          refine_error_text_d
            (decl
               "  fn hd(xs : {List(Int) | len(_) > 0}) : Int do 0 end\n\
               \  fn fy(ys : {List(Int) | len(_) == 0}) : Int do hd(ys) end") in
        Alcotest.(check bool) "violation" true
          (contains text "refinement violation");
        Alcotest.(check bool) "source-syntax value" true
          (contains text "(e.g. ys = [])"))
  ; gated "division: counterexample names the concrete zero divisor" (fun () ->
        (* The witness assignment satisfies the divisor's own refinement
           (_ >= 0 admits 0) and every path fact — a concrete admissible
           input, not just "may be zero". *)
        let errs =
          divsafety_error_texts
            "mod DW do\n\
            \  cap no_panic\n\
            \  fn f(n : Int, d : {Int | _ >= 0}) : Int do n / d end\n\
             end\n"
        in
        Alcotest.(check bool) "concrete divisor witness" true
          (List.exists (fun m -> contains m "(e.g. d = 0)") errs))
  ; gated "unreflectable contract: enumeration finds the witness" (fun () ->
        (* `x * y` never reaches the solver (nonlinear), so no model exists;
           the fixed small-value battery finds an admissible violating input
           and the shrunk result is canonical. *)
        let text =
          refine_error_text_d
            (decl
               "  fn scale(x : {Int | _ > 0}, y : {Int | _ > 0}) : {Int | _ > 100} do x * y end") in
        Alcotest.(check bool) "violation" true
          (contains text "does not satisfy its return type constraint");
        Alcotest.(check bool) "admissible minimal witness" true
          (contains text "but scale(1, 1) returns 1."))
  ; gated "unreflectable contract that HOLDS stays silent" (fun () ->
        (* The battery must not manufacture errors: x*x+1 > 0 for every
           probe, so this stays a skip exactly as before. *)
        let text =
          refine_error_text_d
            (decl "  fn sq(x : Int) : {Int | _ > 0} do x * x + 1 end") in
        Alcotest.(check bool) "no witness claim" false (contains text "but sq("))
  ; gated "divergent execution falls back silently" (fun () ->
        let text =
          refine_error_text_d
            (decl
               "  fn spin(n : Int) : Int do spin(n) end\n\
               \  fn fdiv(x : Int) : {Int | _ >= 0} do spin(x) end") in
        Alcotest.(check bool) "no witness claim" false (contains text "but fdiv("))
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
      ("field-actual", field_actual_suite);
      ("bool-match-path", bool_match_path_suite);
      ("alias-attribution", alias_attribution_suite);
      ("divsafety-hole", divsafety_hole_suite);
      ("divsafety-entailment", divsafety_entailment_suite);
      ("post-nonmatch-body", post_nonmatch_body_suite);
      ("divsafety-boolean-guard", divsafety_boolean_guard_suite);
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
      ("arm-exclusion", arm_exclusion_suite);
      ("measure-base-case-axiom", measure_base_case_axiom_suite);
      ("measure-scalar-field-warn", measure_scalar_field_suite);
      ("post-compose-closed", post_compose_closed_suite);
      ("post-compose-relational", post_compose_relational_suite);
      ("stdlib-nth-contract", stdlib_nth_contract_suite);
      ("verdict-query", verdict_query_suite);
      ("no-panic-by-proof", no_panic_proof_suite);
      ("no-panic-verdict-filter", verdict_filter_suite);
      ("no-panic-syntactic-fallback", syntactic_fallback_suite);
      ("witness-harness", witness_harness_suite);
      ("witness-core", witness_core_suite);
      ("witness-e2e", witness_e2e_suite) ]
