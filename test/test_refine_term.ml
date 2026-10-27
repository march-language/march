(* Termination checking (specs/2026-10-26-termination-checking-design.md).

   Phase 0 ([report_suite], group `termination-report`): the §3.2 call graph
   (direct, lambda and reference edges) and the COUNT classifier, read only by
   `--termination-report`.  Every row is the design's §0.1 table; each asserts
   the (shape, class) pair, never an exit code.

   None of these needs z3: phase 0 and the structural certificate are
   syntactic.  They parse and desugar exactly as the driver does, so a call
   inside a nested module carries its qualified spelling. *)

module RT = March_refinecheck.Refine_term

let parse src =
  let lexbuf = Lexing.from_string src in
  March_parser.Parse.module_of_lexbuf lexbuf

let desugar src = March_desugar.Desugar.desugar_module (parse src)

let analyze src =
  let m = desugar src in
  RT.analyze ~file_mod:m.March_ast.Ast.mod_name.March_ast.Ast.txt m.March_ast.Ast.mod_decls

let row_of t name = List.find_opt (fun (r : RT.row) -> r.RT.r_name = name) (RT.rows t)

let contains (hay : string) (needle : string) : bool =
  let n = String.length needle and h = String.length hay in
  let rec go i = i + n <= h && (String.sub hay i n = needle || go (i + 1)) in
  go 0

let m body = "mod M do\n" ^ body ^ "\nend\n"

(* (shape, class, mutual) of [name], or a sentinel the assertion prints. *)
let shape_class src name =
  match row_of (analyze (m src)) name with
  | Some r -> (r.RT.r_shape, r.RT.r_class, r.RT.r_mutual)
  | None -> ("<no row>", "", false)

let check_row name src ~shape ~cls ?(mutual = false) () =
  Alcotest.(check (triple string string bool))
    (name ^ " (shape, class, mutual)") (shape, cls, mutual) (shape_class src name)

let no_row src name =
  Alcotest.(check bool) (name ^ " has no row") true (row_of (analyze (m src)) name = None)

let case name f = Alcotest.test_case name `Quick f

let t1 = {|
  fn spin(n : Int) : Int do spin(n) end
|}

let t2 = {|
  fn up(n : Int) : Int do if n == 100 do 0 else up(n + 1) end end
|}

let t3 = {|
  fn ev(n : Int) : Bool do if n == 0 do true else od(n - 1) end end
  fn od(n : Int) : Bool do if n == 0 do false else ev(n - 1) end end
|}

let t4 = {|
  fn down(n : Int) : Int do if n == 0 do 0 else down(n - 1) end end
|}

let t5 = {|
  fn fib(n : Int) : Int do if n < 2 do n else fib(n - 1) + fib(n - 2) end end
|}

let t7 = {|
  fn len2(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(_, t) -> 1 + len2(t)
    end
  end
|}

let t8 = {|
  fn ack(m : Int, n : Int) : Int do
    if m == 0 do n + 1
    else if n == 0 do ack(m - 1, 1)
    else ack(m - 1, ack(m, n - 1)) end end
  end
|}

let t9 = {|
  fn bits(n : Int) : Int do if n <= 0 do 0 else 1 + bits(n / 2) end end
|}

let t9b = {|
  fn bits1(n : Int) : Int do if n <= 0 do 0 else 1 + bits1(n / 1) end end
  fn same(n : Int) : Int do if n <= 0 do 0 else 1 + same(n - 0) end end
  fn grow(n : Int) : Int do if n <= 0 do 0 else 1 + grow(n - (0 - 1)) end end
|}

let t10b = {|
  fn h(i : Int) : Int do
    fn go3(i : Int) : Int do 1 + go3(i + 1) end
    go3(i)
  end
|}

let t11 = {|
  fn apply2(g : Int -> Int, x : Int) : Int do g(x) end
  fn h(x : Int) : Int do apply2(h, x) end
|}

let t11b = {|
  fn viafold(n : Int) : Int do List.fold_left([n], 0, fn (acc, x) -> acc + viafold(x)) end
|}

(* Prelude's `length` uses a local `fn go`; a user's own top-level `go` must
   not pick up its call (typecheck_tailcall.ml's scoping note).  Without the
   scope, `length -> go(top) -> length` is a forged two-member SCC. *)
let shadowing = {|
  fn length(xs : List(Int)) : Int do
    fn go(ys : List(Int), acc : Int) : Int do
      match ys do
        Nil -> acc
        Cons(_, t) -> go(t, acc + 1)
      end
    end
    go(xs, 0)
  end
  fn go(n : Int) : Int do length(Cons(n, Nil)) end
|}

let nested = {|
  mod Inner do
    fn boom(n : Int) : Int do if n <= 0 do 0 else 1 + boom(n - 1) end end
  end
|}

(* The driver prepends the stdlib with BARE intra-module calls inside its
   [DMod]s (List's own `fold_left(t, ..)`).  Parsed, not desugared, to keep
   the call bare, as it reaches the checker.  A top-level-first lookup tied
   `L.fold_left` to the entry's own `fold_left` (a forged SCC). *)
let lexical = {|
  mod L do
    fn fold_left(xs : List(Int), acc : Int) : Int do
      match xs do
        Nil -> acc
        Cons(h, t) -> fold_left(t, acc + h)
      end
    end
  end
  fn fold_left(d : List(Int), acc : Int) : Int do L.fold_left(d, acc) end
|}

let analyze_raw src =
  let m = parse src in
  RT.analyze ~file_mod:m.March_ast.Ast.mod_name.March_ast.Ast.txt m.March_ast.Ast.mod_decls

(* The stack pass's own verdict on [src]: its warnings, by message. *)
let tail_warnings src =
  let d = desugar (m src) in
  let errs, _ = March_typecheck.Typecheck.check_module d in
  List.filter_map
    (fun (x : March_errors.Errors.diagnostic) ->
      if x.March_errors.Errors.code = March_errors.Errors.Code.non_tail_recursion
      then Some x.March_errors.Errors.message else None)
    errs.March_errors.Errors.diagnostics

let report_suite =
  [ case "t1 spin: the argument is the parameter, no metric" (fun () ->
        check_row "spin" t1 ~shape:"none" ~cls:"?" ());
    case "t2 up: ascending, `== 100` bounds nothing" (fun () ->
        check_row "up" t2 ~shape:"int-asc" ~cls:"C" ());
    case "t3 ev/od: descending, mutual, `== 0` bounds nothing" (fun () ->
        check_row "ev" t3 ~shape:"int-dec" ~cls:"C" ~mutual:true ();
        check_row "od" t3 ~shape:"int-dec" ~cls:"C" ~mutual:true ());
    case "t4 down: descending, unbounded" (fun () ->
        check_row "down" t4 ~shape:"int-dec" ~cls:"C" ());
    case "t5 fib: descending, `n < 2` bounds it" (fun () ->
        check_row "fib" t5 ~shape:"int-dec" ~cls:"B" ());
    case "t7 len2: structural" (fun () ->
        check_row "len2" t7 ~shape:"structural" ~cls:"A" ());
    case "t8 ack: lexicographic only" (fun () ->
        check_row "ack" t8 ~shape:"lex" ~cls:"D" ());
    case "t9 bits: `n / 2` with `n <= 0` exit" (fun () ->
        check_row "bits" t9 ~shape:"int-dec" ~cls:"B" ());
    case "t9b: `n / 1`, `n - 0`, `n - (0 - 1)` are no metric" (fun () ->
        check_row "bits1" t9b ~shape:"none" ~cls:"?" ();
        check_row "same" t9b ~shape:"none" ~cls:"?" ();
        check_row "grow" t9b ~shape:"none" ~cls:"?" ());
    case "t9b: grow is `none` though the stack pass calls it structural (§3.1)" (fun () ->
        check_row "grow" t9b ~shape:"none" ~cls:"?" ();
        let ws = tail_warnings t9b in
        Alcotest.(check bool) "stack pass: grow is \"structurally recursive\"" true
          (List.exists
             (fun w ->
               contains w "`grow`"
               && contains w "structurally recursive")
             ws));
    case "t10b: a local fn in a non-recursive fn is a unit" (fun () ->
        check_row "h/go3" t10b ~shape:"int-asc" ~cls:"C" ();
        no_row t10b "h");
    case "t11: a function passing itself is a reference edge" (fun () ->
        check_row "h" t11 ~shape:"ref" ~cls:"F" ();
        no_row t11 "apply2");
    case "t11b: recursion inside a lambda is a lambda edge" (fun () ->
        check_row "viafold" t11b ~shape:"lambda" ~cls:"F" ());
    case "shadowing: a local `go` forges no edge to a top-level `go`" (fun () ->
        check_row "length/go" shadowing ~shape:"structural" ~cls:"A" ();
        no_row shadowing "length";
        no_row shadowing "go");
    case "nested mod: a recursive fn one `mod` deeper is found" (fun () ->
        check_row "Inner.boom" nested ~shape:"int-dec" ~cls:"B" ());
    case "nested mod: a bare call inside a module resolves to that module first" (fun () ->
        let t = analyze_raw (m lexical) in
        (match row_of t "L.fold_left" with
         | Some r ->
           Alcotest.(check (pair string int)) "L.fold_left (shape, scc size)" ("structural", 1)
             (r.RT.r_shape, r.RT.r_scc)
         | None ->
           Alcotest.fail
             ("L.fold_left has no row; rows: "
             ^ String.concat ";" (List.map (fun (r : RT.row) -> r.RT.r_name) (RT.rows t))));
        Alcotest.(check bool) "top-level fold_left has no row" true (row_of t "fold_left" = None));
    case "report: one line per recursive unit, plus a class summary" (fun () ->
        let lines = RT.report_lines (analyze (m (t1 ^ t7)) ) in
        let has s = List.exists (fun l -> contains l s) lines in
        Alcotest.(check bool) "header" true (has "termination report: 2 recursive units");
        Alcotest.(check bool) "spin row" true (has "term\t?\tnone\t");
        Alcotest.(check bool) "len2 row" true (has "term\tA\tstructural\t");
        Alcotest.(check bool) "summary" true (has "by class: ?=1 A=1"));
  ]

(* ── Phase 1 (group `termination-structural`) ─────────────────────────────

   The structural certificate of §3.3 and strict positivity (§3.6).  Each
   certificate rule has a REJECT control: a program the rule alone keeps
   from being certified.  Fixtures are typechecked first, exactly as the
   driver does, so a merged multi-head function's [__argN] has its type in
   the [type_map] and a function value's static type is known. *)

let analyze_typed src =
  let d = desugar src in
  let _errs, type_map = March_typecheck.Typecheck.check_module d in
  RT.analyze ~type_map ~file_mod:d.March_ast.Ast.mod_name.March_ast.Ast.txt
    d.March_ast.Ast.mod_decls

let cert_of src name =
  match row_of (analyze_typed (m src)) name with
  | Some r -> r.RT.r_cert
  | None -> "<no row>"

let check_cert name src want =
  Alcotest.(check string) (name ^ " certificate") want (cert_of src name)

let nil_not_smaller = {|
  fn f(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(_, t) -> 1 + f(Nil)
    end
  end
|}

(* A genuine divergence that trust-by-name would certify: position 0 receives
   `t`, which here is ys's tail (bound by the inner match), and the sizes
   cycle (|xs|, |ys|) -> (|ys| - 1, |xs| + 1) -> (|xs|, |ys|).  `copy([1],
   [1, 2])` never returns.  `t` is ALSO xs's component (outer match), so a
   by-name set without [structural_subvars]' fixpoint trusts it. *)
let copy_shadow = {|
  fn copy(xs : List(Int), ys : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(h, t) ->
        match ys do
          Nil -> h
          Cons(_, t) -> 1 + copy(t, Cons(0, xs))
        end
    end
  end
|}

let mutual_nat = {|
  type Nat = Z | S(Nat)
  fn even(n : Nat) : Bool do
    match n do
      Z -> true
      S(m) -> odd(m)
    end
  end
  fn odd(n : Nat) : Bool do
    match n do
      Z -> false
      S(m) -> even(m)
    end
  end
|}

(* The multi-head spelling: desugar merges the heads into one clause whose
   parameter is an unannotated [__arg0]; its ADT comes from the type_map. *)
let mutual_nat_heads = {|
  type Nat = Z | S(Nat)
  fn even(Z) do true end
  fn even(S(m)) do odd(m) end
  fn odd(Z) do false end
  fn odd(S(m)) do even(m) end
|}

(* Members matching on types of DIFFERENT families: a tree through a
   `List(Tree)` of children (the stdlib's `Map.node_fold` shape).  `Tree`
   mentions `List`, but `List`'s definition never mentions `Tree`, so they are
   not one mutually-defined family.  This terminates, but the phase-1 rule asks
   for one type family across the SCC (§3.3), so it stays unproved: the
   conservative direction. *)
let mutual_two_adts = {|
  type Tree = Node(Int, List(Tree))
  fn tsize(t : Tree) : Int do
    match t do
      Node(_, cs) -> 1 + csize(cs)
    end
  end
  fn csize(cs : List(Tree)) : Int do
    match cs do
      Nil -> 0
      Cons(t, rest) -> tsize(t) + csize(rest)
    end
  end
|}

(* One mutually-defined family (each type mentions the other): certified.
   The measure group `mutual-mc` relies on exactly this shape. *)
let mutual_family = {|
  type RTree = RNode(Int, RForest)
  type RForest = FEmpty | FCons(RTree, RForest)
  fn tsize(t : RTree) : Int do
    match t do
      RNode(_, f) -> 1 + fsize(f)
    end
  end
  fn fsize(f : RForest) : Int do
    match f do
      FEmpty -> 0
      FCons(t, rest) -> tsize(t) + fsize(rest)
    end
  end
|}

(* A mutual SCC whose edge passes a NULLARY constructor, never a component. *)
let mutual_nullary = {|
  type Nat = Z | S(Nat)
  fn pa(n : Nat) : Int do
    match n do
      Z -> pb(Z)
      S(m) -> pa(m)
    end
  end
  fn pb(n : Nat) : Int do
    match n do
      Z -> pa(Z)
      S(m) -> pb(m)
    end
  end
|}

(* Lambda edge, diverging: walk([1]) -> apply1([1], λ) -> walk([1]) -> …  Without
   lambda edges `walk` has no recursion at all, so it would be "terminating". *)
let lambda_diverges = {|
  fn apply1(x : List(Int), f : List(Int) -> Int) : Int do f(x) end
  fn walk(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(_, t) ->
        let k = fn y -> walk(y)
        apply1(xs, k)
    end
  end
|}

(* The control: the same lambda edge on a component is checked like any other. *)
let lambda_structural = {|
  fn apply1(x : List(Int), f : List(Int) -> Int) : Int do f(x) end
  fn walk(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(_, t) ->
        let k = fn y -> walk(t)
        apply1(t, k)
    end
  end
|}

(* t11c: no syntactic recursion anywhere, yet `omega()` never returns. *)
let omega = {|
  type Fix = Fix(Fix -> Int)
  fn w(f : Fix) : Int do
    match f do
      Fix(g) -> g(f)
    end
  end
  fn omega() : Int do w(Fix(w)) end
|}

let positive = {|
  type T = T(Int -> Int)
  fn u(t : T) : Int do
    match t do
      T(g) -> g(1)
    end
  end
|}

(* Non-positivity through a mutual pair of types and through a generic type's
   negative parameter: the same omega, one indirection away. *)
let nonpos_mutual = {|
  type A = MkA(B -> Int)
  type B = MkB(A)
  fn w2(b : B) : Int do
    match b do
      MkB(a) ->
        match a do
          MkA(g) -> g(b)
        end
    end
  end
|}

let nonpos_generic = {|
  type Box(a) = Box(a -> Int)
  type F = F(Box(F))
  fn w3(f : F) : Int do
    match f do
      F(bx) ->
        match bx do
          Box(g) -> g(f)
        end
    end
  end
|}

(* A structural SCC that also calls a function value of a non-positive type
   is not certified: positivity is part of the certificate. *)
let structural_nonpos = {|
  type Fix = Fix(Fix -> Int)
  fn r(xs : List(Fix)) : Int do
    match xs do
      Nil -> 0
      Cons(h, t) ->
        match h do
          Fix(g) -> g(h) + r(t)
        end
    end
  end
|}

let nonpos_names src =
  let d = desugar (m src) in
  RT.nonpositive_types d.March_ast.Ast.mod_decls |> List.sort compare

(* c4 (§0.3): a mutual measure cycle `ma(Z) -> mb(Z) -> ma(Z) + 1`.  The
   `@[measure]` gate looked at self-calls only (F5). *)
let c4 = {|
  type Nat = Z | S(Nat)
  @[measure]
  fn ma(n : Nat) : Int do
    match n do
      Z -> mb(Z)
      S(k) -> 1 + ma(k)
    end
  end
  @[measure]
  @[no_warn_recursion]
  fn mb(n : Nat) : Int do
    match n do
      Z -> ma(Z) + 1
      S(k) -> mb(k)
    end
  end
|}

let c4_control = {|
  type Nat = Z | S(Nat)
  @[measure]
  fn ma(n : Nat) : Int do
    match n do
      Z -> 0
      S(k) -> 1 + mb(k)
    end
  end
  @[measure]
  fn mb(n : Nat) : Int do
    match n do
      Z -> 0
      S(k) -> 1 + ma(k)
    end
  end
|}

(* c5 = the gate's m1/m3 row: a measure recursing on its own parameter. *)
let c5 = {|
  type Nat = Z | S(Nat)
  @[measure]
  fn bad(n : Nat) : Int do
    match n do
      Z -> 0
      S(k) -> 1 + bad(n)
    end
  end
|}

let measure_errors src =
  let ctx = March_errors.Errors.create () in
  March_refinecheck.Refine_check.check_module ctx (desugar (m src));
  List.filter_map
    (fun (d : March_errors.Errors.diagnostic) ->
      if d.March_errors.Errors.severity = March_errors.Errors.Error
         && d.March_errors.Errors.code = March_errors.Errors.Code.invalid_measure
      then Some d.March_errors.Errors.message
      else None)
    ctx.March_errors.Errors.diagnostics
  |> List.sort compare

let structural_suite =
  [ case "t7 len2: certified structural" (fun () -> check_cert "len2" t7 "structural");
    case "nil_not_smaller: f(Nil) is not a component" (fun () ->
        check_cert "f" nil_not_smaller "unproved:no-structural-arg";
        (* The stack pass accepts it (F2: a nullary constructor is
           "structurally minimal"); termination must not. *)
        Alcotest.(check bool) "stack pass: a warning, not an error" true
          (List.exists (fun w -> contains w "`f`") (tail_warnings nil_not_smaller)));
    case "copy_shadow: a component name rebound by an inner match is not trusted" (fun () ->
        check_cert "copy" copy_shadow "unproved:no-structural-arg");
    case "mutual_nat: even/odd on Nat certified as one SCC" (fun () ->
        check_cert "even" mutual_nat "structural";
        check_cert "odd" mutual_nat "structural");
    case "mutual_nat: the multi-head spelling (unannotated __arg0)" (fun () ->
        check_cert "even" mutual_nat_heads "structural";
        check_cert "odd" mutual_nat_heads "structural");
    case "mutual_two_adts: members matching types of different families are not certified" (fun () ->
        check_cert "tsize" mutual_two_adts "unproved:not-same-family";
        check_cert "csize" mutual_two_adts "unproved:not-same-family");
    case "mutual_family: one mutually-defined family (RTree/RForest) is certified" (fun () ->
        check_cert "tsize" mutual_family "structural";
        check_cert "fsize" mutual_family "structural");
    case "mutual_nullary: an edge passing a nullary constructor is not certified" (fun () ->
        check_cert "pa" mutual_nullary "unproved:no-structural-arg");
    case "t11: a reference edge is not certified" (fun () ->
        check_cert "h" t11 "unproved:reference");
    case "t11b: a lambda edge with an unrelated argument is not certified" (fun () ->
        check_cert "viafold" t11b "unproved:no-structural-arg");
    case "lambda edge: a diverging recursion through a callback is not certified" (fun () ->
        check_cert "walk" lambda_diverges "unproved:no-structural-arg");
    case "lambda edge: on a component it is certified (control)" (fun () ->
        check_cert "walk" lambda_structural "structural");
    case "t9b: grow is not certified, though the stack pass calls it structural" (fun () ->
        check_cert "grow" t9b "unproved:no-structural-arg");
    case "t1 spin / t4 down: no structural certificate for Int recursion" (fun () ->
        check_cert "spin" t1 "unproved:no-structural-arg";
        check_cert "down" t4 "unproved:no-structural-arg");
    case "t11c omega: `w` calls a value of the non-positive `Fix`" (fun () ->
        Alcotest.(check (list string)) "non-positive types" [ "Fix" ] (nonpos_names omega);
        check_cert "w" omega "unproved:non-positive");
    case "positivity control: `T(Int -> Int)` is positive and blocks nothing" (fun () ->
        Alcotest.(check (list string)) "non-positive types" [] (nonpos_names positive);
        Alcotest.(check bool) "u has no row" true (row_of (analyze_typed (m positive)) "u" = None));
    case "non-positive through a mutual pair of types" (fun () ->
        Alcotest.(check (list string)) "non-positive types" [ "A"; "B" ] (nonpos_names nonpos_mutual);
        check_cert "w2" nonpos_mutual "unproved:non-positive");
    case "non-positive through a generic type's negative parameter" (fun () ->
        Alcotest.(check (list string)) "non-positive types" [ "F" ] (nonpos_names nonpos_generic);
        check_cert "w3" nonpos_generic "unproved:non-positive");
    case "a structural SCC calling a non-positive function value is not certified" (fun () ->
        check_cert "r" structural_nonpos "unproved:non-positive");
    case "c4: a mutual measure cycle is invalid_measure" (fun () ->
        let errs = measure_errors c4 in
        Alcotest.(check int) "two invalid_measure errors" 2 (List.length errs);
        Alcotest.(check bool) "ma named, structural wording" true
          (List.exists (fun e -> contains e "`ma`" && contains e "is not structurally recursive") errs);
        Alcotest.(check bool) "mb named, structural wording" true
          (List.exists (fun e -> contains e "`mb`" && contains e "is not structurally recursive") errs));
    case "c4 control: a structural mutual measure pair passes the gate" (fun () ->
        Alcotest.(check (list string)) "no invalid_measure" [] (measure_errors c4_control));
    case "c5: a measure recursing on its own parameter is unchanged" (fun () ->
        Alcotest.(check (list string)) "one error, today's wording"
          [ "@[measure] `bad` is not structurally recursive (every recursive call must be on a \
             component of the matched parameter)" ]
          (measure_errors c5));
    case "report: the certificate column and its summary" (fun () ->
        let lines = RT.report_lines (analyze_typed (m (t1 ^ t7))) in
        let has s = List.exists (fun l -> contains l s) lines in
        Alcotest.(check bool) "spin unproved" true (has "\tspin\ttop\tscc=1\tcert=unproved:no-structural-arg");
        Alcotest.(check bool) "len2 certified" true (has "\tlen2\ttop\tscc=1\tcert=structural");
        Alcotest.(check bool) "summary" true (has "certificate: 1 structural, 1 unproved"));
  ]
