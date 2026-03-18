(** March test suite — basic smoke tests. *)

let test_lexer_int () =
  let lexbuf = Lexing.from_string "42" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check int) "lexes integer" 42
    (match tok with March_parser.Parser.INT n -> n | _ -> failwith "expected INT")

let test_lexer_ident () =
  let lexbuf = Lexing.from_string "hello" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check string) "lexes identifier" "hello"
    (match tok with March_parser.Parser.LOWER_IDENT s -> s | _ -> failwith "expected LOWER_IDENT")

let test_lexer_keyword_fn () =
  let lexbuf = Lexing.from_string "fn" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "lexes fn keyword" true
    (match tok with March_parser.Parser.FN -> true | _ -> false)

let test_lexer_keyword_do () =
  let lexbuf = Lexing.from_string "do" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "lexes do keyword" true
    (match tok with March_parser.Parser.DO -> true | _ -> false)

let test_lexer_keyword_end () =
  let lexbuf = Lexing.from_string "end" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "lexes end keyword" true
    (match tok with March_parser.Parser.END -> true | _ -> false)

let test_lexer_keyword_mod () =
  let lexbuf = Lexing.from_string "mod" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "lexes mod keyword" true
    (match tok with March_parser.Parser.MOD -> true | _ -> false)

let test_lexer_string () =
  let lexbuf = Lexing.from_string {|"hello world"|} in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check string) "lexes string" "hello world"
    (match tok with March_parser.Parser.STRING s -> s | _ -> failwith "expected STRING")

let test_lexer_atom () =
  let lexbuf = Lexing.from_string ":ok" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check string) "lexes atom" "ok"
    (match tok with March_parser.Parser.ATOM s -> s | _ -> failwith "expected ATOM")

let test_lexer_pipe_arrow () =
  let lexbuf = Lexing.from_string "|>" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "lexes pipe arrow" true
    (match tok with March_parser.Parser.PIPE_ARROW -> true | _ -> false)

let test_lexer_arrow () =
  let lexbuf = Lexing.from_string "->" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "lexes arrow" true
    (match tok with March_parser.Parser.ARROW -> true | _ -> false)

let test_lexer_comment () =
  let lexbuf = Lexing.from_string "-- this is a comment\n42" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check int) "skips line comment" 42
    (match tok with March_parser.Parser.INT n -> n | _ -> failwith "expected INT")

let test_lexer_block_comment () =
  let lexbuf = Lexing.from_string "{- nested {- comment -} -} 7" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check int) "skips block comment" 7
    (match tok with March_parser.Parser.INT n -> n | _ -> failwith "expected INT")

let test_ast_span () =
  let span = March_ast.Ast.dummy_span in
  Alcotest.(check string) "dummy span file" "<none>" span.file

let test_parse_expr_int () =
  let lexbuf = Lexing.from_string "42" in
  let expr = March_parser.Parser.expr_eof March_lexer.Lexer.token lexbuf in
  match expr with
  | March_ast.Ast.ELit (LitInt 42, _) -> ()
  | _ -> Alcotest.fail "expected ELit(LitInt 42)"

let test_parse_expr_atom () =
  let lexbuf = Lexing.from_string ":ok" in
  let expr = March_parser.Parser.expr_eof March_lexer.Lexer.token lexbuf in
  match expr with
  | March_ast.Ast.EAtom ("ok", [], _) -> ()
  | _ -> Alcotest.fail "expected EAtom(ok)"

let test_parse_expr_pipe () =
  let lexbuf = Lexing.from_string "x |> f" in
  let expr = March_parser.Parser.expr_eof March_lexer.Lexer.token lexbuf in
  match expr with
  | March_ast.Ast.EPipe (_, _, _) -> ()
  | _ -> Alcotest.fail "expected EPipe"

let test_parse_expr_lambda () =
  (* Lambdas use fn keyword: fn x -> body *)
  let lexbuf = Lexing.from_string "map(fn x -> x)" in
  let expr = March_parser.Parser.expr_eof March_lexer.Lexer.token lexbuf in
  match expr with
  | March_ast.Ast.EApp (_, [March_ast.Ast.ELam (_, _, _)], _) -> ()
  | _ -> Alcotest.fail "expected EApp with ELam argument"

let test_parse_expr_app () =
  let lexbuf = Lexing.from_string "f(x, y)" in
  let expr = March_parser.Parser.expr_eof March_lexer.Lexer.token lexbuf in
  match expr with
  | March_ast.Ast.EApp (_, [_; _], _) -> ()
  | _ -> Alcotest.fail "expected EApp with 2 args"

let test_parse_module_multi_head () =
  let src = {|mod Test do
    fn fib(0) do 0 end
    fn fib(1) do 1 end
    fn fib(n) do n end
  end|} in
  let lexbuf = Lexing.from_string src in
  let m = March_parser.Parser.module_ March_lexer.Lexer.token lexbuf in
  (* Three fn fib clauses should be grouped into one DFn with 3 clauses *)
  match m.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    Alcotest.(check string) "fn name" "fib" def.fn_name.txt;
    Alcotest.(check int) "3 clauses" 3 (List.length def.fn_clauses)
  | _ -> Alcotest.fail "expected single DFn with grouped clauses"

let test_parse_module_single_fn () =
  let src = {|mod Test do
    fn greet(name) do name end
  end|} in
  let lexbuf = Lexing.from_string src in
  let m = March_parser.Parser.module_ March_lexer.Lexer.token lexbuf in
  match m.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    Alcotest.(check string) "fn name" "greet" def.fn_name.txt;
    Alcotest.(check int) "1 clause" 1 (List.length def.fn_clauses)
  | _ -> Alcotest.fail "expected single DFn"

(* ── Helpers for desugar + typecheck tests ─────────────────────────────── *)

let parse_module src =
  let lexbuf = Lexing.from_string src in
  March_parser.Parser.module_ March_lexer.Lexer.token lexbuf

let parse_and_desugar src =
  March_desugar.Desugar.desugar_module (parse_module src)

let typecheck src =
  let m = parse_and_desugar src in
  March_typecheck.Typecheck.check_module m

let has_errors ctx = March_errors.Errors.has_errors ctx

(* ── Desugaring tests ───────────────────────────────────────────────────── *)

let test_desugar_pipe () =
  (* x |> f  becomes  f(x) *)
  let src = {|mod Test do
    fn go(x) do x |> negate end
  end|} in
  let m = parse_and_desugar src in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    (match def.fn_clauses with
     | [clause] ->
       (match clause.fc_body with
        | March_ast.Ast.EApp (March_ast.Ast.EVar negate, [_], _) ->
          Alcotest.(check string) "pipe becomes application" "negate" negate.txt
        | _ -> Alcotest.fail "expected EApp after pipe desugar")
     | _ -> Alcotest.fail "expected single clause")
  | _ -> Alcotest.fail "expected single DFn"

let test_desugar_multihead () =
  (* Multi-head fn desugars to single clause with match *)
  let src = {|mod Test do
    fn fib(0) do 0 end
    fn fib(1) do 1 end
    fn fib(n) do n end
  end|} in
  let m = parse_and_desugar src in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    Alcotest.(check int) "desugared to single clause" 1
      (List.length def.fn_clauses);
    (match def.fn_clauses with
     | [clause] ->
       (match clause.fc_body with
        | March_ast.Ast.EMatch (_, branches, _) ->
          Alcotest.(check int) "3 branches" 3 (List.length branches)
        | _ -> Alcotest.fail "expected EMatch in desugared body")
     | _ -> Alcotest.fail "expected one clause after desugaring")
  | _ -> Alcotest.fail "expected single DFn"

let test_desugar_trivial_fn () =
  (* Single named-param clause with no guard → no match inserted *)
  let src = {|mod Test do
    fn add(x, y) do x end
  end|} in
  let m = parse_and_desugar src in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    (match def.fn_clauses with
     | [clause] ->
       (match clause.fc_body with
        | March_ast.Ast.EMatch _ ->
          Alcotest.fail "trivial fn should not be wrapped in a match"
        | _ -> ())
     | _ -> Alcotest.fail "expected single clause")
  | _ -> Alcotest.fail "expected single DFn"

(* ── Type checker tests ─────────────────────────────────────────────────── *)

let test_tc_literal () =
  let ctx = typecheck {|mod Test do
    let x = 42
  end|} in
  Alcotest.(check bool) "Int literal: no errors" false (has_errors ctx)

let test_tc_fn_identity () =
  let ctx = typecheck {|mod Test do
    fn identity(x) do x end
  end|} in
  Alcotest.(check bool) "identity: no errors" false (has_errors ctx)

let test_tc_fn_add () =
  let ctx = typecheck {|mod Test do
    fn add(x, y) do x + y end
  end|} in
  Alcotest.(check bool) "add: no errors" false (has_errors ctx)

let test_tc_if_bad_cond () =
  (* Condition must be Bool — using Int + 1 should produce an error.
     if/then/else needs no `end`; only fn do…end and match…end do. *)
  let ctx = typecheck {|mod Test do
    fn bad(x) do if x + 1 then 0 else 1 end
  end|} in
  Alcotest.(check bool) "non-Bool condition is an error" true (has_errors ctx)

let test_tc_annotated_fn () =
  let ctx = typecheck {|mod Test do
    fn double(x) : Int do x + x end
  end|} in
  Alcotest.(check bool) "annotated return: no errors" false (has_errors ctx)

let test_tc_match () =
  let ctx = typecheck {|mod Test do
    fn f(x) do
      match x with
      | 0 -> 1
      | n -> n + 1
      end
    end
  end|} in
  Alcotest.(check bool) "match branches: no errors" false (has_errors ctx)

let test_tc_undefined_var () =
  let ctx = typecheck {|mod Test do
    fn f(x) do y end
  end|} in
  Alcotest.(check bool) "undefined var is an error" true (has_errors ctx)

let test_tc_hole () =
  (* Typed holes produce Hint diagnostics, not errors *)
  let ctx = typecheck {|mod Test do
    fn f(x) do ? end
  end|} in
  Alcotest.(check bool) "hole is not an error" false (has_errors ctx)

let test_lexer_when () =
  let lexbuf = Lexing.from_string "when" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "lexes when keyword" true
    (match tok with March_parser.Parser.WHEN -> true | _ -> false)

(* ── Eval helpers ───────────────────────────────────────────────────────── *)

let eval_module src =
  let m = parse_and_desugar src in
  March_eval.Eval.eval_module_env m

let call_fn env name args =
  let fn_val = List.assoc name env in
  March_eval.Eval.apply fn_val args

(* ── Eval tests ─────────────────────────────────────────────────────────── *)

let test_eval_literal () =
  let env = eval_module {|mod Test do
    fn answer() do 42 end
  end|} in
  let v = call_fn env "answer" [] in
  Alcotest.(check int) "literal 42" 42
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

let test_eval_arithmetic () =
  let env = eval_module {|mod Test do
    fn add(x, y) do x + y end
  end|} in
  let v = call_fn env "add"
      [March_eval.Eval.VInt 3; March_eval.Eval.VInt 4] in
  Alcotest.(check int) "3 + 4 = 7" 7
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

let test_eval_recursion () =
  let env = eval_module {|mod Test do
    fn fib(0) do 0 end
    fn fib(1) do 1 end
    fn fib(n) do fib(n - 1) + fib(n - 2) end
  end|} in
  let v = call_fn env "fib" [March_eval.Eval.VInt 7] in
  Alcotest.(check int) "fib(7) = 13" 13
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

let test_eval_if () =
  let env = eval_module {|mod Test do
    fn abs(x) do if x < 0 then negate(x) else x end
  end|} in
  let v = call_fn env "abs" [March_eval.Eval.VInt (-5)] in
  Alcotest.(check int) "abs(-5) = 5" 5
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

let test_eval_match_adt () =
  let env = eval_module {|mod Test do
    type Shape = Circle(Int) | Square(Int)
    fn area(s) do
      match s with
      | Circle(r) -> r * r
      | Square(side) -> side * side
      end
    end
  end|} in
  let circle = March_eval.Eval.VCon ("Circle", [March_eval.Eval.VInt 3]) in
  let v = call_fn env "area" [circle] in
  Alcotest.(check int) "area(Circle(3)) = 9" 9
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

let test_eval_tuple () =
  let env = eval_module {|mod Test do
    fn swap(x, y) do (y, x) end
  end|} in
  let v = call_fn env "swap"
      [March_eval.Eval.VInt 1; March_eval.Eval.VInt 2] in
  match v with
  | March_eval.Eval.VTuple [March_eval.Eval.VInt 2; March_eval.Eval.VInt 1] -> ()
  | _ -> Alcotest.fail "expected VTuple [2; 1]"

let test_eval_let_binding () =
  let env = eval_module {|mod Test do
    fn double(x) do
      let y = x + x
      y
    end
  end|} in
  let v = call_fn env "double" [March_eval.Eval.VInt 5] in
  Alcotest.(check int) "double(5) = 10" 10
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

let test_eval_closure () =
  let env = eval_module {|mod Test do
    fn make_adder(n) do fn x -> x + n end
  end|} in
  let adder = call_fn env "make_adder" [March_eval.Eval.VInt 10] in
  let v = March_eval.Eval.apply adder [March_eval.Eval.VInt 5] in
  Alcotest.(check int) "make_adder(10)(5) = 15" 15
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

(* ── Parser gap tests ───────────────────────────────────────────────────── *)

let test_parse_unary_minus () =
  (* -x  parses as  negate(x) *)
  let lexbuf = Lexing.from_string "-x" in
  let expr = March_parser.Parser.expr_eof March_lexer.Lexer.token lexbuf in
  match expr with
  | March_ast.Ast.EApp (March_ast.Ast.EVar n, [_], _) ->
    Alcotest.(check string) "unary minus becomes negate" "negate" n.txt
  | _ -> Alcotest.fail "expected EApp(negate, [x])"

let test_parse_negative_lit_pattern () =
  (* match n with | -1 -> ... should produce PatLit(LitInt(-1)) *)
  let src = {|mod T do
    fn f(n) do
      match n with
      | -1 -> true
      | _  -> false
      end
    end
  end|} in
  let m = parse_and_desugar src in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    let clause = List.hd def.fn_clauses in
    (match clause.fc_body with
     | March_ast.Ast.EMatch (_, branches, _) ->
       (match branches with
        | br :: _ ->
          (match br.branch_pat with
           | March_ast.Ast.PatLit (March_ast.Ast.LitInt (-1), _) -> ()
           | _ -> Alcotest.fail "expected PatLit(LitInt(-1))")
        | [] -> Alcotest.fail "no branches")
     | _ -> Alcotest.fail "expected EMatch")
  | _ -> Alcotest.fail "expected single DFn"

let test_parse_list_literal () =
  (* [1, 2, 3]  →  Cons(1, Cons(2, Cons(3, Nil))) *)
  let lexbuf = Lexing.from_string "[1, 2, 3]" in
  let expr = March_parser.Parser.expr_eof March_lexer.Lexer.token lexbuf in
  match expr with
  | March_ast.Ast.ECon (n, [_; _], _) when n.txt = "Cons" -> ()
  | _ -> Alcotest.fail "expected Cons(1, Cons(...))"

let test_lexer_percent () =
  let lexbuf = Lexing.from_string "%" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "lexes %" true
    (match tok with March_parser.Parser.PERCENT -> true | _ -> false)

let test_eval_modulo () =
  let env = eval_module {|mod Test do
    fn rem(a, b) do a % b end
  end|} in
  let v = call_fn env "rem" [March_eval.Eval.VInt 17; March_eval.Eval.VInt 5] in
  Alcotest.(check int) "17 % 5 = 2" 2
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

let test_eval_multi_stmt_match_arm () =
  (* Multi-statement match arm body — sequences two lets and returns result *)
  let env = eval_module {|mod Test do
    fn classify(n) do
      match n with
      | 0 ->
        let tag = 0
        tag
      | _ ->
        let tag = 1
        tag
      end
    end
  end|} in
  let v0 = call_fn env "classify" [March_eval.Eval.VInt 0] in
  let v1 = call_fn env "classify" [March_eval.Eval.VInt 7] in
  Alcotest.(check int) "classify(0) = 0" 0
    (match v0 with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt");
  Alcotest.(check int) "classify(7) = 1" 1
    (match v1 with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

let test_eval_unary_minus () =
  let env = eval_module {|mod Test do
    fn neg(x) do -x end
  end|} in
  let v = call_fn env "neg" [March_eval.Eval.VInt 5] in
  Alcotest.(check int) "-5" (-5)
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

let test_eval_list_literal () =
  (* [1, 2] should produce Cons(1, Cons(2, Nil)) at runtime *)
  let env = eval_module {|mod Test do
    fn make_list() do [1, 2, 3] end
  end|} in
  let v = call_fn env "make_list" [] in
  match v with
  | March_eval.Eval.VCon ("Cons", [March_eval.Eval.VInt 1; _]) -> ()
  | _ -> Alcotest.fail "expected Cons(1, ...)"

let test_eval_negative_pattern () =
  let env = eval_module {|mod Test do
    fn sign(n) do
      match n with
      | 0  -> 0
      | -1 -> -1
      | _  -> 1
      end
    end
  end|} in
  let v = call_fn env "sign" [March_eval.Eval.VInt (-1)] in
  Alcotest.(check int) "sign(-1) = -1" (-1)
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

let test_value_to_string () =
  Alcotest.(check string) "int"    "42"          (March_eval.Eval.value_to_string (March_eval.Eval.VInt 42));
  Alcotest.(check string) "string" "\"hello\""   (March_eval.Eval.value_to_string (March_eval.Eval.VString "hello"));
  Alcotest.(check string) "tuple"  "(1, 2)"      (March_eval.Eval.value_to_string
                                                    (March_eval.Eval.VTuple [March_eval.Eval.VInt 1; March_eval.Eval.VInt 2]));
  Alcotest.(check string) "con"    "Some(42)"    (March_eval.Eval.value_to_string
                                                    (March_eval.Eval.VCon ("Some", [March_eval.Eval.VInt 42])));
  Alcotest.(check string) "nil"    "[]"          (March_eval.Eval.value_to_string
                                                    (March_eval.Eval.VCon ("Nil", [])));
  Alcotest.(check string) "list"   "[1, 2]"      (March_eval.Eval.value_to_string
                                                    (March_eval.Eval.VCon ("Cons",
                                                      [March_eval.Eval.VInt 1;
                                                       March_eval.Eval.VCon ("Cons",
                                                         [March_eval.Eval.VInt 2;
                                                          March_eval.Eval.VCon ("Nil", [])])])))

(** Parse, desugar, and lower a March module to TIR. *)
let lower_module src =
  let m = parse_and_desugar src in
  March_tir.Lower.lower_module m

let find_fn name (m : March_tir.Tir.tir_module) =
  List.find (fun (f : March_tir.Tir.fn_def) -> f.fn_name = name) m.tm_fns

let test_tir_lower_literal () =
  let m = lower_module {|mod Test do
    fn answer() : Int do 42 end
  end|} in
  let f = find_fn "answer" m in
  match f.fn_body with
  | March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 42)) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "expected EAtom(42), got: %s"
           (March_tir.Pp.string_of_expr f.fn_body))

let test_tir_lower_let () =
  let m = lower_module {|mod Test do
    fn double(x : Int) : Int do
      let y = x
      y
    end
  end|} in
  let f = find_fn "double" m in
  match f.fn_body with
  | March_tir.Tir.ELet (_, _, _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "expected ELet, got: %s"
           (March_tir.Pp.string_of_expr f.fn_body))

let test_tir_lower_if () =
  let m = lower_module {|mod Test do
    fn pick(b : Bool) : Int do if b then 1 else 0 end
  end|} in
  let f = find_fn "pick" m in
  let rec has_case = function
    | March_tir.Tir.ECase _ -> true
    | March_tir.Tir.ELet (_, _, body) -> has_case body
    | _ -> false
  in
  Alcotest.(check bool) "if→case" true (has_case f.fn_body)

let test_tir_anf_nested_call () =
  (* f(g(x)) should produce an ELet for the inner g(x) call *)
  let m = lower_module {|mod Test do
    fn g(x : Int) : Int do x end
    fn f(x : Int) : Int do x end
    fn main() : Int do f(g(1)) end
  end|} in
  let f = find_fn "main" m in
  let has_let = function
    | March_tir.Tir.ELet (_, _, _) -> true
    | _ -> false
  in
  Alcotest.(check bool) "nested call needs ELet" true (has_let f.fn_body)

let test_tir_lower_constructor () =
  let m = lower_module {|mod Test do
    type Shape = Circle(Int) | Square(Int)
    fn make() do Circle(42) end
  end|} in
  let f = find_fn "make" m in
  let rec has_alloc = function
    | March_tir.Tir.EAlloc _ -> true
    | March_tir.Tir.ELet (_, e1, e2) -> has_alloc e1 || has_alloc e2
    | _ -> false
  in
  Alcotest.(check bool) "constructor→EAlloc" true (has_alloc f.fn_body)

let test_tir_lower_lambda () =
  let m = lower_module {|mod Test do
    fn make_adder(n : Int) do fn x -> x end
  end|} in
  let f = find_fn "make_adder" m in
  let rec has_letrec = function
    | March_tir.Tir.ELetRec _ -> true
    | March_tir.Tir.ELet (_, _, body) -> has_letrec body
    | _ -> false
  in
  Alcotest.(check bool) "lambda→ELetRec" true (has_letrec f.fn_body)

let test_tir_lower_match () =
  let m = lower_module {|mod Test do
    type Shape = Circle(Int) | Square(Int)
    fn area(s) do
      match s with
      | Circle(r) -> r
      | Square(side) -> side
      end
    end
  end|} in
  let f = find_fn "area" m in
  let rec has_case = function
    | March_tir.Tir.ECase _ -> true
    | March_tir.Tir.ELet (_, _, body) -> has_case body
    | _ -> false
  in
  Alcotest.(check bool) "match→ECase" true (has_case f.fn_body)

let test_tir_lower_record () =
  let m = lower_module {|mod Test do
    fn make() do { x = 1, y = 2 } end
  end|} in
  let f = find_fn "make" m in
  match f.fn_body with
  | March_tir.Tir.ERecord _ -> ()
  | _ -> Alcotest.fail (Printf.sprintf "expected ERecord, got: %s"
           (March_tir.Pp.string_of_expr f.fn_body))

let test_tir_lower_seq () =
  let m = lower_module {|mod Test do
    fn f() do
      println("hi")
      42
    end
  end|} in
  let f = find_fn "f" m in
  let rec has_seq = function
    | March_tir.Tir.ESeq _ -> true
    | March_tir.Tir.ELet (_, _, body) -> has_seq body
    | _ -> false
  in
  Alcotest.(check bool) "block→ESeq" true (has_seq f.fn_body)

let test_tir_lower_module () =
  let m = lower_module {|mod Test do
    fn add(x : Int, y : Int) : Int do x + y end
    fn main() do add(1, 2) end
  end|} in
  Alcotest.(check int) "2 functions" 2 (List.length m.March_tir.Tir.tm_fns);
  Alcotest.(check string) "first fn name" "add" (List.hd m.tm_fns).fn_name

let test_tir_lower_type_def () =
  let m = lower_module {|mod Test do
    type Shape = Circle(Int) | Square(Int)
    fn main() do 0 end
  end|} in
  Alcotest.(check int) "1 type def" 1 (List.length m.March_tir.Tir.tm_types)

let test_tir_lower_fn_params () =
  let m = lower_module {|mod Test do
    fn add(x : Int, y : Int) : Int do x + y end
  end|} in
  let f = find_fn "add" m in
  Alcotest.(check int) "2 params" 2 (List.length f.March_tir.Tir.fn_params);
  Alcotest.(check string) "ret type" "Int"
    (March_tir.Pp.string_of_ty f.fn_ret_ty)

let test_tir_anf_invariant () =
  (* Verify the core ANF property: all EApp arguments are atoms *)
  let m = lower_module {|mod Test do
    fn f(x : Int) : Int do x + x end
  end|} in
  let f = find_fn "f" m in
  let rec check_anf = function
    | March_tir.Tir.EApp (_, args) ->
      List.for_all (function
        | March_tir.Tir.AVar _ | March_tir.Tir.ALit _ -> true
      ) args
    | March_tir.Tir.ELet (_, e1, e2) -> check_anf e1 && check_anf e2
    | March_tir.Tir.ESeq (e1, e2) -> check_anf e1 && check_anf e2
    | March_tir.Tir.ECase (_, brs, def) ->
      List.for_all (fun (br : March_tir.Tir.branch) -> check_anf br.br_body) brs &&
      (match def with Some e -> check_anf e | None -> true)
    | _ -> true
  in
  Alcotest.(check bool) "ANF invariant: all call args are atoms" true (check_anf f.fn_body)

let test_tir_lower_patvar_default () =
  (* PatVar in default arm should bind the scrutinee *)
  let m = lower_module {|mod Test do
    fn describe(n) do
      match n with
      | 0 -> 0
      | other -> other
      end
    end
  end|} in
  let f = find_fn "describe" m in
  (* The default arm should have an ELet binding "other" *)
  let rec find_case = function
    | March_tir.Tir.ECase (_, _, Some def) -> def
    | March_tir.Tir.ELet (_, _, body) -> find_case body
    | e -> e
  in
  match find_case f.fn_body with
  | March_tir.Tir.ELet (v, _, _) ->
    Alcotest.(check string) "PatVar binds scrutinee" "other" v.v_name
  | _ -> Alcotest.fail "expected ELet in default arm for PatVar"

let test_tir_lower_ty_int () =
  let ast_ty = March_ast.Ast.TyCon ({ txt = "Int"; span = March_ast.Ast.dummy_span }, []) in
  let tir_ty = March_tir.Lower.lower_ty ast_ty in
  Alcotest.(check string) "Int → TInt" "Int" (March_tir.Pp.string_of_ty tir_ty)

let test_tir_lower_ty_tuple () =
  let open March_ast.Ast in
  let ast_ty = TyTuple [
    TyCon ({ txt = "Int"; span = dummy_span }, []);
    TyCon ({ txt = "Bool"; span = dummy_span }, [])
  ] in
  let tir_ty = March_tir.Lower.lower_ty ast_ty in
  Alcotest.(check string) "tuple" "(Int, Bool)" (March_tir.Pp.string_of_ty tir_ty)

let test_tir_lower_polymorphic () =
  (* Polymorphic functions should lower without crashing *)
  let m = lower_module {|mod Test do
    fn identity(x) do x end
    fn apply(f, x) do f(x) end
    fn compose(f, g, x) do f(g(x)) end
  end|} in
  Alcotest.(check int) "3 functions" 3 (List.length m.March_tir.Tir.tm_fns)

let test_tir_lower_recursive () =
  let m = lower_module {|mod Test do
    fn fib(0) do 0 end
    fn fib(1) do 1 end
    fn fib(n) do fib(n - 1) + fib(n - 2) end
  end|} in
  let f = find_fn "fib" m in
  (* Should have an ECase from the desugared multi-head *)
  let rec has_case = function
    | March_tir.Tir.ECase _ -> true
    | March_tir.Tir.ELet (_, _, body) -> has_case body
    | _ -> false
  in
  Alcotest.(check bool) "recursive fn lowers" true (has_case f.fn_body)

let test_tir_lower_list_ops () =
  let m = lower_module {|mod Test do
    type List = Cons(Int, List) | Nil

    fn map(f, xs) do
      match xs with
      | Nil -> Nil()
      | Cons(h, t) -> Cons(f(h), map(f, t))
      end
    end

    fn length(xs) do
      match xs with
      | Nil -> 0
      | Cons(h, t) -> 1 + length(t)
      end
    end
  end|} in
  Alcotest.(check int) "2 functions" 2 (List.length m.March_tir.Tir.tm_fns);
  Alcotest.(check int) "1 type def" 1 (List.length m.March_tir.Tir.tm_types)

let test_tir_lower_closures_and_hof () =
  let m = lower_module {|mod Test do
    fn make_adder(n : Int) do
      fn x -> x + n
    end

    fn twice(f, x) do f(f(x)) end

    fn main() : Int do
      let add5 = make_adder(5)
      twice(add5, 10)
    end
  end|} in
  Alcotest.(check int) "3 functions" 3 (List.length m.March_tir.Tir.tm_fns)

let test_tir_pp_atom () =
  let open March_tir.Tir in
  let open March_tir.Pp in
  let v = { v_name = "x"; v_ty = TInt; v_lin = Unr } in
  let a = AVar v in
  Alcotest.(check string) "atom var" "x" (string_of_atom a)

let test_tir_pp_lit () =
  let open March_tir.Pp in
  let a = March_tir.Tir.ALit (March_ast.Ast.LitInt 42) in
  Alcotest.(check string) "atom lit" "42" (string_of_atom a)

let () =
  Alcotest.run "march"
    [
      ( "lexer",
        [
          Alcotest.test_case "integer" `Quick test_lexer_int;
          Alcotest.test_case "identifier" `Quick test_lexer_ident;
          Alcotest.test_case "fn keyword" `Quick test_lexer_keyword_fn;
          Alcotest.test_case "do keyword" `Quick test_lexer_keyword_do;
          Alcotest.test_case "end keyword" `Quick test_lexer_keyword_end;
          Alcotest.test_case "mod keyword" `Quick test_lexer_keyword_mod;
          Alcotest.test_case "string" `Quick test_lexer_string;
          Alcotest.test_case "atom" `Quick test_lexer_atom;
          Alcotest.test_case "pipe arrow" `Quick test_lexer_pipe_arrow;
          Alcotest.test_case "arrow" `Quick test_lexer_arrow;
          Alcotest.test_case "line comment" `Quick test_lexer_comment;
          Alcotest.test_case "block comment" `Quick test_lexer_block_comment;
        ] );
      ( "ast",
        [
          Alcotest.test_case "dummy span" `Quick test_ast_span;
        ] );
      ( "parser",
        [
          Alcotest.test_case "integer expr" `Quick test_parse_expr_int;
          Alcotest.test_case "atom expr" `Quick test_parse_expr_atom;
          Alcotest.test_case "pipe expr" `Quick test_parse_expr_pipe;
          Alcotest.test_case "lambda expr" `Quick test_parse_expr_lambda;
          Alcotest.test_case "application" `Quick test_parse_expr_app;
        ] );
      ( "module",
        [
          Alcotest.test_case "multi-head fn" `Quick test_parse_module_multi_head;
          Alcotest.test_case "single fn" `Quick test_parse_module_single_fn;
        ] );
      ( "keywords",
        [
          Alcotest.test_case "when" `Quick test_lexer_when;
        ] );
      ( "desugar",
        [
          Alcotest.test_case "pipe desugar"        `Quick test_desugar_pipe;
          Alcotest.test_case "multi-head desugar"  `Quick test_desugar_multihead;
          Alcotest.test_case "trivial fn no match" `Quick test_desugar_trivial_fn;
        ] );
      ( "typecheck",
        [
          Alcotest.test_case "Int literal"         `Quick test_tc_literal;
          Alcotest.test_case "identity fn"         `Quick test_tc_fn_identity;
          Alcotest.test_case "add fn"              `Quick test_tc_fn_add;
          Alcotest.test_case "bad if condition"    `Quick test_tc_if_bad_cond;
          Alcotest.test_case "annotated return"    `Quick test_tc_annotated_fn;
          Alcotest.test_case "match expression"    `Quick test_tc_match;
          Alcotest.test_case "undefined variable"  `Quick test_tc_undefined_var;
          Alcotest.test_case "typed hole"          `Quick test_tc_hole;
        ] );
      ( "eval",
        [
          Alcotest.test_case "literal"             `Quick test_eval_literal;
          Alcotest.test_case "arithmetic"          `Quick test_eval_arithmetic;
          Alcotest.test_case "recursion"           `Quick test_eval_recursion;
          Alcotest.test_case "if expression"       `Quick test_eval_if;
          Alcotest.test_case "match ADT"           `Quick test_eval_match_adt;
          Alcotest.test_case "tuple"               `Quick test_eval_tuple;
          Alcotest.test_case "let binding"         `Quick test_eval_let_binding;
          Alcotest.test_case "closure"             `Quick test_eval_closure;
          Alcotest.test_case "unary minus"         `Quick test_eval_unary_minus;
          Alcotest.test_case "list literal"        `Quick test_eval_list_literal;
          Alcotest.test_case "negative pattern"    `Quick test_eval_negative_pattern;
          Alcotest.test_case "value_to_string"     `Quick test_value_to_string;
        ] );
      ( "parser gaps",
        [
          Alcotest.test_case "unary minus"         `Quick test_parse_unary_minus;
          Alcotest.test_case "negative lit pattern"`Quick test_parse_negative_lit_pattern;
          Alcotest.test_case "list literal"        `Quick test_parse_list_literal;
          Alcotest.test_case "percent token"       `Quick test_lexer_percent;
          Alcotest.test_case "modulo operator"     `Quick test_eval_modulo;
          Alcotest.test_case "multi-stmt match arm"`Quick test_eval_multi_stmt_match_arm;
        ] );
      ( "tir",
        [
          Alcotest.test_case "lower literal"       `Quick test_tir_lower_literal;
          Alcotest.test_case "lower let"            `Quick test_tir_lower_let;
          Alcotest.test_case "lower if→case"        `Quick test_tir_lower_if;
          Alcotest.test_case "ANF nested call"      `Quick test_tir_anf_nested_call;
          Alcotest.test_case "lower constructor"    `Quick test_tir_lower_constructor;
          Alcotest.test_case "lower lambda"         `Quick test_tir_lower_lambda;
          Alcotest.test_case "lower match"          `Quick test_tir_lower_match;
          Alcotest.test_case "lower record"         `Quick test_tir_lower_record;
          Alcotest.test_case "lower seq"            `Quick test_tir_lower_seq;
          Alcotest.test_case "lower module"         `Quick test_tir_lower_module;
          Alcotest.test_case "lower type def"       `Quick test_tir_lower_type_def;
          Alcotest.test_case "lower fn params"      `Quick test_tir_lower_fn_params;
          Alcotest.test_case "ANF invariant"        `Quick test_tir_anf_invariant;
          Alcotest.test_case "PatVar default arm"   `Quick test_tir_lower_patvar_default;
          Alcotest.test_case "lower polymorphic"   `Quick test_tir_lower_polymorphic;
          Alcotest.test_case "lower recursive"     `Quick test_tir_lower_recursive;
          Alcotest.test_case "lower list ops"      `Quick test_tir_lower_list_ops;
          Alcotest.test_case "lower closures/HOF"  `Quick test_tir_lower_closures_and_hof;
          Alcotest.test_case "lower ty Int"        `Quick test_tir_lower_ty_int;
          Alcotest.test_case "lower ty tuple"      `Quick test_tir_lower_ty_tuple;
          Alcotest.test_case "pp atom var"         `Quick test_tir_pp_atom;
          Alcotest.test_case "pp atom lit"          `Quick test_tir_pp_lit;
        ] );
    ]
