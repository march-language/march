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
