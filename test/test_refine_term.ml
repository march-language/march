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
        Alcotest.(check bool) "summary" true (has "certificate: 1 structural, 0 metric, 0 trusted, 1 unproved"));
  ]

(* ── Phase 2: metrics, `@[decreases]`, SMT obligations (group
   `termination-metric`) ────────────────────────────────────────────────

   Each fixture is desugared and typechecked, then checked by
   [Refine_check.check_module] exactly as the driver does; the verdicts are
   read back as the certificate [Refine_term.last_certs] holds for a unit,
   the [Termination] ledger entries, and the diagnostics.  [~all] is
   `--termination-report`'s demand-everything mode; without it only an
   `@[decreases]` SCC is checked (decision D2).  These need z3. *)

module Ob = March_refinecheck.Obligation
module E = March_errors.Errors

let z3_available () =
  match March_refine.Solver.create () with
  | None -> false
  | Some s ->
    March_refine.Solver.close s;
    true

let zcase name f = Alcotest.test_case name `Quick (fun () -> if z3_available () then f () else Alcotest.skip ())

type run = {
  certs : (string * string) list;  (** unit name -> phase-2 certificate *)
  terms : Ob.t list;  (** the Termination obligations *)
  diags : E.diagnostic list;
}

let run ?(all = false) src : run =
  let d = desugar src in
  let _errs, type_map = March_typecheck.Typecheck.check_module d in
  let ctx = E.create () in
  Ob.reset ();
  RT.check_all := all;
  Fun.protect
    ~finally:(fun () -> RT.check_all := false)
    (fun () -> March_refinecheck.Refine_check.check_module ~type_map ctx d);
  let t = RT.analyze ~type_map ~file_mod:d.March_ast.Ast.mod_name.March_ast.Ast.txt d.March_ast.Ast.mod_decls in
  let certs =
    Array.to_list t.RT.graph.RT.units
    |> List.filter_map (fun (u : RT.unit_) ->
           Option.map (fun c -> (u.RT.u_name, c)) (Hashtbl.find_opt RT.last_certs u.RT.u_span))
  in
  { certs; terms = List.filter (fun (o : Ob.t) -> o.Ob.kind = Ob.Termination) (Ob.all ());
    diags = ctx.E.diagnostics }

let mcert r name = Option.value ~default:"<none>" (List.assoc_opt name r.certs)

let check_mcert r name want = Alcotest.(check string) (name ^ " certificate") want (mcert r name)

let diags_with code r = List.filter (fun (d : E.diagnostic) -> d.E.code = code) r.diags

let n_with code r = List.length (diags_with code r)

let verdicts r = List.map (fun (o : Ob.t) -> Ob.verdict_name o.Ob.verdict) r.terms

let fib = t5

let down_le = {|
  fn down_le(n : Int) : Int do if n <= 0 do 0 else down_le(n - 1) end end
|}

let down_ann = {|
  @[decreases(n)]
  fn down(n : Int) : Int do if n == 0 do 0 else down(n - 1) end end
|}

let evod_refined = {|
  fn ev(n : {Int | _ >= 0}) : Bool do if n == 0 do true else od(n - 1) end end
  fn od(n : {Int | _ >= 0}) : Bool do if n == 0 do false else ev(n - 1) end end
|}

let ack_le = {|
  @[decreases(m, n)]
  fn ack(m : Int, n : Int) : Int do
    if m <= 0 do n + 1
    else if n <= 0 do ack(m - 1, 1)
    else ack(m - 1, ack(m, n - 1)) end end
  end
|}

let ack_eq = {|
  @[decreases(m, n)]
  fn ack(m : Int, n : Int) : Int do
    if m == 0 do n + 1
    else if n == 0 do ack(m - 1, 1)
    else ack(m - 1, ack(m, n - 1)) end end
  end
|}

(* `f(2, 2) -> f(3, 1) -> f(2, 2)`: diverges.  The second component falls at
   the first edge only while the first RISES, which is no lexicographic
   decrease; the REJECT control of the lex formula's `x1 == y1` guard. *)
let lex_diverging = {|
  @[decreases(m, n)]
  fn f(m : Int, n : Int) : Int do
    if m <= 0 || n <= 0 do 0 else f(m + 1, n - 1) + f(m - 1, n + 1) end
  end
|}

(* A recursive call in a match-arm guard: the refinement walk never visits
   a guard, so the obligation is never discharged.  A site that is never
   reached is unproved, never proved by default. *)
let guard_call = {|
  @[decreases(n)]
  fn q(n : Int) : Int do
    match n do
      k when k > 0 && q(k - 1) > 0 -> 1
      _ -> 0
    end
  end
|}

let up_ge = {|
  @[decreases(100 - n)]
  fn up(n : Int) : Int do if n >= 100 do 0 else up(n + 1) end end
|}

let up_eq = {|
  @[decreases(100 - n)]
  fn up(n : Int) : Int do if n == 100 do 0 else up(n + 1) end end
|}

(* A recursion whose metric parameter is rebound before the call: the call
   passes the entry `n` plus 4, so `f` never stops, though `n - 1 < n` holds
   of the INNER `n`.  The REJECT control of the shadowing rule. *)
let shadowed = {|
  @[decreases(n)]
  fn f(n : Int) : Int do
    if n <= 0 do 0
    else
      let n = n + 5
      f(n - 1)
    end
  end
|}

(* The nested call's result is the argument at the decreasing position: an
   arbitrary value, so nothing is proved (the REJECT control of the opaque
   nested-call argument). *)
let nested_arg = {|
  @[decreases(n)]
  fn h(n : Int) : Int do if n <= 0 do 0 else h(h(n - 1)) end end
|}

let positive_metric = {|
  type T = T(Int -> Int)
  fn u(t : T, n : Int) : Int do
    if n <= 0 do 0
    else
      match t do
        T(g) -> g(n) + u(t, n - 1)
      end
    end
  end
|}

let verified_annotated = {|
  cap verified
  @[decreases(n)]
  fn down(n : Int) : Int do if n == 0 do 0 else down(n - 1) end end
|}

let verified_unannotated = {|
  cap verified
  fn down(n : Int) : Int do if n == 0 do 0 else down(n - 1) end end
|}

let invalid_local = {|
  @[decreases(k)]
  fn f(n : Int) : Int do
    let k = n
    if n <= 0 do 0 else f(n - 1) end
  end
|}

let invalid_float = {|
  @[decreases(x)]
  fn f(x : Float, n : Int) : Int do if n <= 0 do 0 else f(x, n - 1) end end
|}

let invalid_adt = {|
  @[decreases(xs)]
  fn f(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(_, t) -> 1 + f(t)
    end
  end
|}

let len_metric = {|
  @[decreases(len(xs) - i)]
  fn scan(xs : List(Int), i : {Int | _ >= 0}, acc : Int) : Int do
    if i >= List.length(xs) do acc else scan(xs, i + 1, acc + 1) end
  end
|}

let lengths_differ = {|
  @[decreases(n, 0)]
  fn ev(n : Int) : Bool do if n <= 0 do true else od(n - 1) end end
  @[decreases(n)]
  fn od(n : Int) : Bool do if n <= 0 do false else ev(n - 1) end end
|}

let non_recursive = {|
  @[decreases(n)]
  fn f(n : Int) : Int do n + 1 end
|}

let typo = {|
  @[decrease(n)]
  fn f(n : Int) : Int do if n <= 0 do 0 else f(n - 1) end end
  @[trusted]
  @[no_alloc(warn)]
  fn g(n : Int) : Int do n end
|}

let cache_src metric = Printf.sprintf {|
  @[decreases(%s)]
  fn d(n : Int) : Int do if n <= 0 do 0 else d(n - 1) end end
|} metric

let parse_attrs src =
  match (parse (m src)).March_ast.Ast.mod_decls with
  | [ March_ast.Ast.DMod (_, _, [ March_ast.Ast.DFn (fd, _) ], _) ] | [ March_ast.Ast.DFn (fd, _) ] ->
    (fd.March_ast.Ast.fn_attrs, List.map (fun (n, es) -> (n, List.length es)) fd.March_ast.Ast.fn_attr_args)
  | _ -> ([ "<shape>" ], [])

let parse_error src =
  match parse (m src) with
  | _ -> "<parsed>"
  | exception E.ParseError (msg, _, _) -> msg

let metric_suite =
  [ zcase "t5 fib: certified by the default metric `n`, 2 termination obligations proved" (fun () ->
        let r = run ~all:true (m fib) in
        check_mcert r "fib" "metric";
        Alcotest.(check (list string)) "two proved" [ "proved"; "proved" ] (verdicts r));
    zcase "t4 down: unproved, the ledger skip names the model n = -1" (fun () ->
        let r = run ~all:true (m t4) in
        check_mcert r "down" "unproved:not-decreasing";
        match r.terms with
        | [ o ] ->
          Alcotest.(check string) "callee" "down" o.Ob.callee;
          (match o.Ob.verdict with
           | Ob.Skipped (Ob.Not_decreasing cx) ->
             Alcotest.(check bool) ("model " ^ cx) true (contains cx "n = -1")
           | v -> Alcotest.failf "expected a not-decreasing skip, got %s" (Ob.verdict_name v))
        | os -> Alcotest.failf "expected one termination obligation, got %d" (List.length os));
    zcase "t4 down, unannotated: no termination_unproved (D2)" (fun () ->
        let r = run ~all:true (m t4) in
        Alcotest.(check int) "no warning" 0 (n_with E.Code.termination_unproved r));
    zcase "t4 down, annotated: termination_unproved warning with the witness" (fun () ->
        let r = run (m down_ann) in
        match diags_with E.Code.termination_unproved r with
        | [ d ] ->
          Alcotest.(check bool) "a warning" true (d.E.severity = E.Warning);
          Alcotest.(check bool) d.E.message true
            (contains d.E.message "`down(n - 1)` is not shown to decrease `n`: e.g. n = -1")
        | ds -> Alcotest.failf "expected one termination_unproved, got %d" (List.length ds));
    zcase "down_le: a `<= 0` exit is certified" (fun () ->
        check_mcert (run ~all:true (m down_le)) "down_le" "metric");
    zcase "t3 ev/od: refined `{Int | _ >= 0}` certified as one SCC; unrefined unproved" (fun () ->
        let r = run ~all:true (m evod_refined) in
        check_mcert r "ev" "metric";
        check_mcert r "od" "metric";
        Alcotest.(check (list string)) "both edges obliged" [ "proved"; "proved" ] (verdicts r);
        let r = run ~all:true (m t3) in
        check_mcert r "ev" "unproved:not-decreasing";
        check_mcert r "od" "unproved:not-decreasing");
    zcase "t8 ack: `@[decreases(m, n)]` with `<= 0` exits certified; with `== 0` exits unproved" (fun () ->
        check_mcert (run (m ack_le)) "ack" "metric";
        check_mcert (run (m ack_eq)) "ack" "unproved:not-decreasing");
    zcase "lex: a later component falling while an earlier one rises is no decrease" (fun () ->
        check_mcert (run (m lex_diverging)) "f" "unproved:not-decreasing");
    zcase "t9 / t9b: bits certified; bits1, same, grow refuted" (fun () ->
        check_mcert (run ~all:true (m t9)) "bits" "metric";
        let r = run ~all:true (m t9b) in
        List.iter (fun n -> check_mcert r n "unproved:not-decreasing") [ "bits1"; "same"; "grow" ];
        List.iter
          (fun (o : Ob.t) ->
            match o.Ob.verdict with
            | Ob.Skipped (Ob.Not_decreasing cx) ->
              Alcotest.(check bool) (o.Ob.callee ^ " refuted with a model: " ^ cx) true (contains cx "n = ")
            | v -> Alcotest.failf "%s: expected not-decreasing, got %s" o.Ob.callee (Ob.verdict_name v))
          r.terms);
    zcase "t2 up: `@[decreases(100 - n)]` certified with guard `n >= 100`, unproved with `== 100`" (fun () ->
        check_mcert (run (m up_ge)) "up" "metric";
        check_mcert (run (m up_eq)) "up" "unproved:not-decreasing");
    zcase "a `len` metric over a list and an index" (fun () ->
        check_mcert (run (m len_metric)) "scan" "metric");
    zcase "shadowing: a metric parameter rebound before the call is not trusted" (fun () ->
        let r = run (m shadowed) in
        check_mcert r "f" "unproved:shadowed";
        Alcotest.(check int) "warned" 1 (n_with E.Code.termination_unproved r));
    zcase "a call the walk never reaches (a match-arm guard) is unproved" (fun () ->
        let r = run (m guard_call) in
        check_mcert r "q" "unproved:not-decreasing";
        match diags_with E.Code.termination_unproved r with
        | [ d ] ->
          Alcotest.(check bool) d.E.message true (contains d.E.message "the checker did not reach this call")
        | ds -> Alcotest.failf "expected one termination_unproved, got %d" (List.length ds));
    zcase "a nested recursive call's result is an arbitrary value" (fun () ->
        check_mcert (run (m nested_arg)) "h" "unproved:not-decreasing");
    case "parser: p18 parses, `@[no_alloc(warn)]` unchanged, `@[foo(1 + 2)]` names `foo`" (fun () ->
        Alcotest.(check (pair (list string) (list (pair string int))))
          "decreases(m, n)" ([ "decreases" ], [ ("decreases", 2) ])
          (parse_attrs "@[decreases(m, n)]\nfn ack(m : Int, n : Int) : Int do 0 end");
        Alcotest.(check (pair (list string) (list (pair string int))))
          "decreases(len(xs) - i)" ([ "decreases" ], [ ("decreases", 1) ])
          (parse_attrs "@[decreases(len(xs) - i)]\nfn s(xs : List(Int), i : Int) : Int do 0 end");
        Alcotest.(check (pair (list string) (list (pair string int))))
          "no_alloc(warn)" ([ "no_alloc:warn" ], [])
          (parse_attrs "@[no_alloc(warn)]\nfn f(n : Int) : Int do n end");
        Alcotest.(check (pair (list string) (list (pair string int))))
          "no_alloc(transient)" ([ "no_alloc:transient" ], [])
          (parse_attrs "@[no_alloc(transient)]\nfn f(n : Int) : Int do n end");
        let msg = parse_error "@[foo(1 + 2)]\nfn f(n : Int) : Int do n end" in
        Alcotest.(check bool) ("names foo: " ^ msg) true (contains msg "`@[foo(...)]`"));
    zcase "invalid_decreases: a local, a Float, a bare ADT parameter, one error each" (fun () ->
        List.iter
          (fun (label, src, frag) ->
            let ds = diags_with E.Code.invalid_decreases (run (m src)) in
            Alcotest.(check int) (label ^ ": one error") 1 (List.length ds);
            Alcotest.(check bool) (label ^ ": " ^ (List.hd ds).E.message) true
              (contains (List.hd ds).E.message frag))
          [ ("local", invalid_local, "`k` is not a parameter of `f`");
            ("float", invalid_float, "`x` is a Float");
            ("adt", invalid_adt, "`xs` is a `List`, not an Int") ]);
    zcase "invalid_decreases: metrics of different lengths in one cycle" (fun () ->
        let r = run (m lengths_differ) in
        Alcotest.(check int) "one per annotated member" 2 (n_with E.Code.invalid_decreases r);
        check_mcert r "ev" "unproved:invalid-decreases";
        Alcotest.(check int) "no termination_unproved on top" 0 (n_with E.Code.termination_unproved r));
    zcase "`@[decreases]` on a non-recursive function has no effect" (fun () ->
        Alcotest.(check int) "attribute_no_effect" 1 (n_with E.Code.attribute_no_effect (run (m non_recursive))));
    zcase "t11c omega: `w` unproved; a positive `T(Int -> Int)` does not block a metric" (fun () ->
        check_cert "w" omega "unproved:non-positive";
        check_mcert (run ~all:true (m positive_metric)) "u" "metric");
    zcase "cap_verified_annotated: annotated + unproved is an error; unannotated is silent" (fun () ->
        let r = run (m verified_annotated) in
        (match diags_with E.Code.termination_unproved r with
         | [ d ] -> Alcotest.(check bool) "an error" true (d.E.severity = E.Error)
         | ds -> Alcotest.failf "expected one termination_unproved, got %d" (List.length ds));
        let r = run (m verified_unannotated) in
        Alcotest.(check int) "unannotated: nothing" 0 (n_with E.Code.termination_unproved r);
        Alcotest.(check int) "unannotated: no obligation" 0 (List.length r.terms));
    zcase "kind_counted: `by kind:` prints the termination count, and only when there is one" (fun () ->
        let r = run ~all:true (m fib) in
        Alcotest.(check string) "with" "  by kind: 0 precondition, 0 postcondition, 0 division, 2 termination"
          (Ob.by_kind_line r.terms);
        Alcotest.(check string) "without" "  by kind: 0 precondition, 0 postcondition, 0 division"
          (Ob.by_kind_line []));
    zcase "cache: `@[decreases(n)]` and `@[decreases(n - 2)]` keep independent verdicts" (fun () ->
        for _ = 1 to 2 do
          check_mcert (run (m (cache_src "n"))) "d" "metric";
          check_mcert (run (m (cache_src "n - 2"))) "d" "unproved:not-decreasing"
        done);
    zcase "default off (D2): an unannotated module files no termination obligation" (fun () ->
        let r = run (m (fib ^ t4)) in
        Alcotest.(check int) "no obligation" 0 (List.length r.terms);
        Alcotest.(check (list (pair string string))) "no certificate" [] r.certs);
    zcase "D6: an unknown attribute warns with a did-you-mean; known ones do not" (fun () ->
        match diags_with E.Code.unknown_attribute (run (m typo)) with
        | [ d ] -> Alcotest.(check bool) d.E.message true (contains d.E.message "did you mean `@[decreases]`?")
        | ds -> Alcotest.failf "expected one unknown_attribute, got %d" (List.length ds));
    zcase "report: metric certificates and the trusted builtin callees" (fun () ->
        let src =
          m
            ("extern \"rt\" : Cap(Ffi) do\n    fn ext_tick(n : Int) : Int = \"ffi_tick\"\n  end\n"
           ^ "  fn ticks(n : Int) : Int do if n <= 0 do 0 else ext_tick(n) + string_length(int_to_string(n)) + ticks(n - 1) end end\n"
           ^ fib ^ t4)
        in
        ignore (run ~all:true src);
        let d = desugar src in
        let t = RT.analyze ~file_mod:d.March_ast.Ast.mod_name.March_ast.Ast.txt d.March_ast.Ast.mod_decls in
        let lines = RT.report_lines t in
        let has s = List.exists (fun l -> contains l s) lines in
        Alcotest.(check bool) "fib metric" true (has "\tfib\ttop\tscc=1\tcert=metric");
        Alcotest.(check bool) "down unproved" true (has "\tdown\ttop\tscc=1\tcert=unproved:not-decreasing");
        Alcotest.(check bool) ("summary: " ^ String.concat " | " lines) true
          (has "certificate: 0 structural, 2 metric, 0 trusted, 1 unproved");
        Alcotest.(check bool) ("trusted: " ^ String.concat " | " lines) true
          (has "trusted: 3 builtin or extern callees: ext_tick, int_to_string, string_length"));
  ]

(* Phase 3 ([ih_suite], group `termination-ih`): the induction hypothesis,
   granted only behind a termination certificate (decision D1, §4.2).  Every
   row asserts (kind, callee) -> verdict triples from the obligation ledger,
   never an exit code.  The payoff rows (r1-r4, the widened element and local
   hypotheses) were skips on the phase-2 compiler; the soundness rows (c1-c3,
   pre_fails, scc_atomic, diverges_in_scc) must stay unproved, and each goes
   RED under the perturbation named in the progress note. *)

(* Every ledger verdict for obligations of [kind] whose callee is [callee]. *)
let ledger ?(all = false) src : Ob.t list =
  ignore (run ~all src);
  Ob.all ()

let vs kind callee (obs : Ob.t list) =
  List.filter_map
    (fun (o : Ob.t) ->
      if o.Ob.kind = kind && o.Ob.callee = callee then Some (Ob.verdict_name o.Ob.verdict) else None)
    obs

let post = Ob.Postcondition

let pre = Ob.Precondition

let check_all_proved label kind callee obs =
  let v = vs kind callee obs in
  Alcotest.(check bool) (label ^ ": has obligations") true (v <> []);
  Alcotest.(check (list string)) label (List.map (fun _ -> "proved") v) v

(* Not proved, and never violated: the skip of today.  A postcondition is
   recorded per tail, so a base tail (`0`) may prove; some tail must skip. *)
let check_skip label kind callee obs =
  let v = vs kind callee obs in
  Alcotest.(check bool) (label ^ ": has obligations") true (v <> []);
  Alcotest.(check bool) (label ^ ": some tail skipped, none violated; got " ^ String.concat "," v) true
    (List.mem "skipped" v && not (List.mem "violated" v))

let not_all_proved label kind callee obs =
  let v = vs kind callee obs in
  Alcotest.(check bool) (label ^ ": has obligations") true (v <> []);
  Alcotest.(check bool) (label ^ ": not every tail proved; got " ^ String.concat "," v) false
    (List.for_all (( = ) "proved") v)

let r1 = {|
  fn sum_to(n : {Int | _ >= 0}) : {Int | _ >= 0} do
    if n == 0 do 0 else
      let r = sum_to(n - 1)
      n + r
    end
  end
  fn need_nn(x : {Int | _ >= 0}) : Int do x end
  fn caller(k : {Int | _ >= 0}) : Int do need_nn(sum_to(k)) end
|}

let r2 = {|
  fn sum_to(n : {Int | _ >= 0}) : {Int | _ >= 0} do
    if n == 0 do 0 else n + sum_to(n - 1) end
  end
  fn need_nn(x : {Int | _ >= 0}) : Int do x end
  fn caller(k : {Int | _ >= 0}) : Int do need_nn(sum_to(k)) end
|}

let r3 = {|
  fn sum_to(n : {Int | _ >= 0}) : {Int | _ >= n} do
    if n == 0 do 0 else
      let r = sum_to(n - 1)
      n + r
    end
  end
  fn need_ge(x : {Int | _ >= 10}) : Int do x end
  fn caller() : Int do need_ge(sum_to(10)) end
|}

let r4 = {|
  fn len2(xs : List(Int)) : {Int | _ >= 0} do
    match xs do
      Nil -> 0
      Cons(_, t) -> 1 + len2(t)
    end
  end
  fn need_nn(x : {Int | _ >= 0}) : Int do x end
  fn caller(xs : List(Int)) : Int do need_nn(len2(xs)) end
|}

let c1 = {|
  fn loopy(x : Int) : {Int | _ < 0} do loopy(x) end
  fn need_pos(x : {Int | _ > 0}) : Int do x end
  fn caller(k : Int) : Int do need_pos(loopy(k)) end
|}

(* c1's nested twin: rule (b) must not reflect an uncertified call either. *)
let c1_nested = {|
  fn loopy(x : Int) : {Int | _ < 0} do 0 + loopy(x) end
  fn need_pos(x : {Int | _ > 0}) : Int do x end
  fn caller(k : Int) : Int do need_pos(loopy(k)) end
|}

let c2 = {|
  fn down(n : Int) : {Int | _ == 0} do if n == 0 do 0 else down(n - 1) end end
  fn need_nn(x : {Int | _ >= 0}) : Int do x end
  fn caller() : Int do need_nn(down(0 - 1) - 1) end
|}

let c3 = {|
  fn loopy(x : Int) : {Int | _ > 0 && _ < 0} do loopy(x) end
  fn need_neg(x : {Int | _ < 0}) : Int do x end
  fn caller(k : Int) : Int do need_neg(loopy(k)) end
|}

let pre_fails = {|
  fn f(n : {Int | _ >= 0}) : {Int | _ >= 0} do
    if n == 0 do 0 else
      let r = f(n - 2)
      r + 1
    end
  end
|}

(* Rule (a)'s precondition half on its own: `f(n - 1, k - 1)` DECREASES
   (`n`, the default metric), but breaks `k`'s precondition at k = 1, and
   `f(1, 1)` really returns 0.  The hypothesis there would "prove" `_ > 0`. *)
let pre_fails_k = {|
  fn f(n : {Int | _ >= 0}, k : {Int | _ > 0}) : {Int | _ > 0} do
    if n == 0 do k else
      let r = f(n - 1, k - 1)
      r
    end
  end
  fn need_pos(x : {Int | _ > 0}) : Int do x end
  fn caller() : Int do need_pos(f(1, 1)) end
|}

(* `od`'s contract is false (`od(0) = 1`), and under `od`'s hypothesis `ev`'s
   would prove: admitting `ev` alone would lend `ev(1) >= 0` to the caller,
   and `ev(1) = -1`. *)
let atomic_false = {|
  fn ev(n : {Int | _ >= 0}) : {Int | _ >= 0} do if n == 0 do 0 else 0 - od(n - 1) end end
  fn od(n : {Int | _ >= 0}) : {Int | _ < 0} do if n == 0 do 1 else ev(n - 1) + 1 end end
  fn need_nn(x : {Int | _ >= 0}) : Int do x end
  fn caller() : Int do need_nn(ev(1)) end
|}

let atomic_true = {|
  fn ev(n : {Int | _ >= 0}) : {Int | _ >= 0} do if n == 0 do 0 else od(n - 1) end end
  fn od(n : {Int | _ >= 0}) : {Int | _ > 0} do if n == 0 do 1 else ev(n - 1) + 1 end end
|}

let elem_widened = {|
  @[decreases(n)]
  fn replicate(x : {Int | _ > 0}, n : {Int | _ >= 0}) : List({Int | _ > 0}) do
    if n == 0 do Nil else Cons(x, replicate(x, n - 1)) end
  end
  fn keep(xs : List({Int | _ > 0})) : List({Int | _ > 0}) do
    match xs do
      Nil -> Nil
      Cons(h, t) -> Cons(h, keep(t))
    end
  end
|}

(* The same shape whose metric does NOT decrease: `x` is the default metric
   and is passed unchanged, so no certificate and no hypothesis. *)
let elem_unwidened = {|
  fn replicate(x : {Int | _ > 0}, n : {Int | _ >= 0}) : List({Int | _ > 0}) do
    if n == 0 do Nil else Cons(x, replicate(x, n - 1)) end
  end
|}

let local_src next = Printf.sprintf {|
  fn need_nn(k : {Int | _ >= 0}) : Int do k end
  fn last_hit(n : {Int | _ >= 0}, pred : Int -> Bool) : Option({Int | _ >= 0}) do
    fn go(i : {Int | _ >= 0}) : Option({Int | _ >= 0}) do
      if i == 0 do None else if pred(i) do Some(i) else %s end end
    end
    go(n)
  end
  fn user(n : {Int | _ >= 0}) : Int do
    match last_hit(n, fn y -> y > 3) do
      Some(i) -> need_nn(i)
      None -> 0
    end
  end
|} next

let diverges_in_scc = {|
  fn spin(n : Int) : Int do spin(n) end
  fn f(n : {Int | _ >= 0}) : {Int | _ >= 0} do
    if n == 0 do 0 else
      let s = spin(n)
      let r = f(n - 1)
      r + 1
    end
  end
|}

(* Tier 2 (a datatype return, `len(_) == n`): the self-call `rep(n - 1)` is
   not structural; the certified metric `n` widens [ih_arg].  `rep_bad`'s
   `n` is unbounded (`rep_bad(-1)` diverges): no certificate, no hypothesis. *)
let tier2_widened = {|
  fn rep(n : {Int | _ >= 0}) : {List(Int) | len(_) == n} do
    if n == 0 do Nil else Cons(0, rep(n - 1)) end
  end
  fn rep_bad(n : Int) : {List(Int) | len(_) == n} do
    if n == 0 do Nil else Cons(0, rep_bad(n - 1)) end
  end
|}

let ih_suite =
  [ zcase "r2 / §4.3: nested `n + sum_to(n - 1)` proves, and so does its caller" (fun () ->
        let obs = ledger (m r2) in
        check_all_proved "sum_to post" post "sum_to" obs;
        check_all_proved "sum_to pre" pre "sum_to" obs;
        check_all_proved "need_nn" pre "need_nn" obs);
    zcase "r1 / r3: the let form, `_ >= 0` and `_ >= n` with `need_ge(sum_to(10))`" (fun () ->
        let obs = ledger (m r1) in
        check_all_proved "r1 sum_to" post "sum_to" obs;
        check_all_proved "r1 need_nn" pre "need_nn" obs;
        let obs = ledger (m r3) in
        check_all_proved "r3 sum_to" post "sum_to" obs;
        check_all_proved "r3 need_ge" pre "need_ge" obs);
    zcase "r4: structural `1 + len2(t)` (rule (b)) and its caller" (fun () ->
        let obs = ledger (m r4) in
        check_all_proved "len2" post "len2" obs;
        check_all_proved "need_nn" pre "need_nn" obs);
    zcase "c1 / c2 / c3: diverging functions get no hypothesis, nothing proved or violated" (fun () ->
        List.iter
          (fun (label, src, fn_, callee) ->
            let obs = ledger (m src) in
            check_skip (label ^ " post") post fn_ obs;
            check_skip (label ^ " caller") pre callee obs)
          [ ("c1", c1, "loopy", "need_pos"); ("c1 nested", c1_nested, "loopy", "need_pos");
            ("c2", c2, "down", "need_nn"); ("c3", c3, "loopy", "need_neg") ]);
    zcase "pre_fails: `f(n - 2)` breaks its precondition at n = 1, so no hypothesis" (fun () ->
        let obs = ledger (m pre_fails) in
        check_skip "f post" post "f" obs;
        (* The call decreases, so only the precondition withholds the IH. *)
        let obs = ledger (m pre_fails_k) in
        not_all_proved "f(n, k) post" post "f" obs;
        Alcotest.(check bool) "need_pos(f(1, 1)) not proved" false
          (List.mem "proved" (vs pre "need_pos" obs)));
    zcase "scc_atomic: one false member sinks both; both true admits both" (fun () ->
        let obs = ledger (m atomic_false) in
        not_all_proved "ev" post "ev" obs;
        not_all_proved "od" post "od" obs;
        check_skip "caller need_nn(ev(1))" pre "need_nn" obs;
        let obs = ledger (m atomic_true) in
        check_all_proved "ev" post "ev" obs;
        check_all_proved "od" post "od" obs);
    zcase "elem_widened: `Cons(x, replicate(x, n - 1))` proves; a structural one still does" (fun () ->
        let obs = ledger (m elem_widened) in
        check_all_proved "return of replicate" pre "return of replicate" obs;
        check_all_proved "return of keep" pre "return of keep" obs;
        let obs = ledger (m elem_unwidened) in
        Alcotest.(check bool) "uncertified: not all proved" false
          (List.for_all (( = ) "proved") (vs pre "return of replicate" obs)));
    zcase "local_widened: a local `go(i - 1)` proves; an ascending `go(i + 1)` still skips" (fun () ->
        let obs = ledger (m (local_src "go(i - 1)")) in
        check_all_proved "return of go" pre "return of go" obs;
        check_all_proved "need_nn" pre "need_nn" obs;
        let obs = ledger (m (local_src "go(i + 1)")) in
        Alcotest.(check bool) "ascending: return of go skips" true
          (List.mem "skipped" (vs pre "return of go" obs));
        Alcotest.(check bool) "ascending: need_nn not proved" false
          (List.mem "proved" (vs pre "need_nn" obs)));
    zcase "tier2_widened: `Cons(0, rep(n - 1))` proves `len(_) == n`; unbounded `n` still skips" (fun () ->
        let obs = ledger (m tier2_widened) in
        check_all_proved "rep" post "rep" obs;
        check_skip "rep_bad" post "rep_bad" obs);
    zcase "diverges_in_scc: calling an uncertified recursive function withholds the hypothesis" (fun () ->
        let obs = ledger (m diverges_in_scc) in
        check_skip "f post" post "f" obs);
    zcase "the IH files no termination obligation in the ledger (D2: report-only)" (fun () ->
        let r = run (m r2) in
        Alcotest.(check int) "no termination obligation" 0 (List.length r.terms));
  ]
