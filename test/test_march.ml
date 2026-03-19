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
  let (errors, _type_map) = March_typecheck.Typecheck.check_module m in
  errors

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
  let (_errors, _type_map) = March_typecheck.Typecheck.check_module m in
  March_tir.Lower.lower_module m

let find_fn name (m : March_tir.Tir.tir_module) =
  List.find (fun (f : March_tir.Tir.fn_def) -> f.fn_name = name) m.tm_fns

(** Parse, desugar, typecheck, and lower a March module using the real type_map. *)
let lower_module_typed src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  March_tir.Lower.lower_module ~type_map m

let test_tir_lower_typed_param () =
  (* x has NO explicit annotation — type comes from type_map, not lower_ty.
     Without type_map threading this would produce TVar "_". *)
  let m = lower_module_typed {|mod Test do
    fn identity(x) do x end
  end|} in
  (* The typechecker infers x : 'a (generic), but after lower_module_typed,
     the param should have whatever the typechecker left for that span.
     At minimum it must not crash — and for a concretely-called version the
     type should flow through. Here we just check it does not remain unknown_ty
     by verifying the ty round-trips through pp without crashing. *)
  let f = find_fn "identity" m in
  let p = List.hd f.March_tir.Tir.fn_params in
  let _ = March_tir.Pp.string_of_ty p.March_tir.Tir.v_ty in
  (* The param type must not be TVar "_" (the no-type-map fallback) —
     it should now be TVar with an actual HM id, or TInt if fully resolved. *)
  Alcotest.(check bool) "param not bare unknown" false
    (p.March_tir.Tir.v_ty = March_tir.Tir.TVar "_")

let test_tir_lower_typed_let () =
  (* let y = x with no annotation: y's type should come from type_map
     (the inferred type of x, which is Int here because of the return annotation). *)
  let m = lower_module_typed {|mod Test do
    fn double(x : Int) : Int do
      let y = x
      y
    end
  end|} in
  let f = find_fn "double" m in
  match f.March_tir.Tir.fn_body with
  | March_tir.Tir.ELet (v, _, _) ->
    Alcotest.(check string) "let binding has TInt" "Int"
      (March_tir.Pp.string_of_ty v.March_tir.Tir.v_ty)
  | _ -> Alcotest.fail "expected ELet"

(** Lower with type_map and then monomorphize. *)
let mono_module src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  March_tir.Mono.monomorphize tir

let test_mono_identity () =
  (* identity is polymorphic; called with Int → should produce identity$Int,
     and the generic identity (with TVar params) should NOT appear. *)
  let m = mono_module {|mod Test do
    fn identity(x) do x end
    fn main() : Int do identity(42) end
  end|} in
  let names = List.map (fun f -> f.March_tir.Tir.fn_name) m.March_tir.Tir.tm_fns in
  (* The specialized version must exist *)
  Alcotest.(check bool) "identity$Int present" true
    (List.exists (fun n -> n = "identity$Int") names);
  (* The unspecialized generic version must NOT be present *)
  Alcotest.(check bool) "bare identity absent" false
    (List.mem "identity" names);
  (* No fn should have TVar in its params after mono *)
  List.iter (fun fn ->
    List.iter (fun (v : March_tir.Tir.var) ->
      Alcotest.(check bool)
        (Printf.sprintf "param %s has no TVar" v.March_tir.Tir.v_name)
        false (March_tir.Mono.has_tvar v.March_tir.Tir.v_ty)
    ) fn.March_tir.Tir.fn_params
  ) m.March_tir.Tir.tm_fns

let test_mono_no_tvar_after_mono () =
  (* After mono, no fn_def in the module has TVar in any type *)
  let m = mono_module {|mod Test do
    fn double(x : Int) : Int do x + x end
    fn main() : Int do double(21) end
  end|} in
  let ty_ok t = not (March_tir.Mono.has_tvar t) in
  List.iter (fun fn ->
    Alcotest.(check bool)
      (Printf.sprintf "fn %s ret_ty has no TVar" fn.March_tir.Tir.fn_name)
      true (ty_ok fn.March_tir.Tir.fn_ret_ty);
    List.iter (fun (v : March_tir.Tir.var) ->
      Alcotest.(check bool)
        (Printf.sprintf "fn %s param %s has no TVar" fn.March_tir.Tir.fn_name v.March_tir.Tir.v_name)
        true (ty_ok v.March_tir.Tir.v_ty)
    ) fn.March_tir.Tir.fn_params
  ) m.March_tir.Tir.tm_fns

let test_mono_two_instantiations () =
  (* apply called with Int and Bool at separate call sites → two specializations *)
  let m = mono_module {|mod Test do
    fn apply(f, x) do f(x) end
    fn inc(n : Int) : Int do n + 1 end
    fn main() : Int do
      let a = apply(inc, 1)
      a
    end
  end|} in
  (* main should be present *)
  let main_fn = find_fn "main" m in
  (* main's return type must be concrete Int, not TVar *)
  Alcotest.(check bool) "main ret is Int" true
    (main_fn.March_tir.Tir.fn_ret_ty = March_tir.Tir.TInt);
  (* apply must have been specialized (not present with TVar params) *)
  List.iter (fun fn ->
    List.iter (fun (v : March_tir.Tir.var) ->
      Alcotest.(check bool)
        (Printf.sprintf "fn %s param %s concrete" fn.March_tir.Tir.fn_name v.March_tir.Tir.v_name)
        false (March_tir.Mono.has_tvar v.March_tir.Tir.v_ty)
    ) fn.March_tir.Tir.fn_params
  ) m.March_tir.Tir.tm_fns

let test_mono_pipeline_no_tvar () =
  (* Full pipeline: lower with type_map + monomorphize.
     Verify no TVar remains in a simple typed program. *)
  let m = mono_module {|mod Test do
    fn add(x : Int, y : Int) : Int do x + y end
    fn main() : Int do add(1, 2) end
  end|} in
  let rec check_expr_no_tvar = function
    | March_tir.Tir.EAtom (March_tir.Tir.AVar v) ->
      Alcotest.(check bool)
        (Printf.sprintf "var %s has no TVar" v.March_tir.Tir.v_name)
        false (March_tir.Mono.has_tvar v.March_tir.Tir.v_ty)
    | March_tir.Tir.ELet (v, e1, e2) ->
      Alcotest.(check bool)
        (Printf.sprintf "let %s has no TVar" v.March_tir.Tir.v_name)
        false (March_tir.Mono.has_tvar v.March_tir.Tir.v_ty);
      check_expr_no_tvar e1; check_expr_no_tvar e2
    | March_tir.Tir.ESeq (e1, e2) ->
      check_expr_no_tvar e1; check_expr_no_tvar e2
    | _ -> ()
  in
  List.iter (fun fn -> check_expr_no_tvar fn.March_tir.Tir.fn_body)
    m.March_tir.Tir.tm_fns

let test_mono_subst_ty () =
  let open March_tir.Tir in
  let open March_tir.Mono in
  let s = [("a", TInt); ("b", TBool)] in
  Alcotest.(check string) "subst TVar a → Int" "Int"
    (March_tir.Pp.string_of_ty (subst_ty s (TVar "a")));
  Alcotest.(check string) "subst nested" "List(Int)"
    (March_tir.Pp.string_of_ty (subst_ty s (TCon ("List", [TVar "a"]))));
  Alcotest.(check string) "no TVar left" "Bool"
    (March_tir.Pp.string_of_ty (subst_ty s (TVar "b")))

let test_mono_mangle () =
  let open March_tir.Mono in
  Alcotest.(check string) "no args" "f" (mangle_name "f" []);
  Alcotest.(check string) "one arg" "map$Int" (mangle_name "map" [March_tir.Tir.TInt]);
  Alcotest.(check string) "two args" "map$Int$Bool"
    (mangle_name "map" [March_tir.Tir.TInt; March_tir.Tir.TBool])

let test_mono_has_tvar () =
  let open March_tir.Tir in
  let open March_tir.Mono in
  Alcotest.(check bool) "TInt no tvar"   false (has_tvar TInt);
  Alcotest.(check bool) "TVar has tvar"  true  (has_tvar (TVar "a"));
  Alcotest.(check bool) "nested has tvar" true
    (has_tvar (TCon ("List", [TVar "a"])))

let test_mono_match_ty () =
  let open March_tir.Tir in
  let open March_tir.Mono in
  let s = match_ty (TVar "a") TInt [] in
  Alcotest.(check string) "matched TVar a = Int" "Int"
    (March_tir.Pp.string_of_ty (subst_ty s (TVar "a")));
  let s2 = match_ty (TCon ("List", [TVar "a"])) (TCon ("List", [TBool])) [] in
  Alcotest.(check string) "matched nested TVar a = Bool" "Bool"
    (March_tir.Pp.string_of_ty (subst_ty s2 (TVar "a")))

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
  (* 3 built-in types (Option, Result, List) + 1 user type = 4 *)
  Alcotest.(check int) "type defs include Shape" 4 (List.length m.March_tir.Tir.tm_types)

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
  (* 3 built-in types + 1 user List type = 4 *)
  Alcotest.(check int) "type defs include List" 4 (List.length m.March_tir.Tir.tm_types)

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

(* ── New feature tests ─────────────────────────────────────────────────── *)

(* Num/Ord constraint tests *)
let test_tc_num_int () =
  let ctx = typecheck {|mod Test do
    fn f(x: Int) do x + 1 end
  end|} in
  Alcotest.(check bool) "Int + Int: no errors" false (has_errors ctx)

let test_tc_num_string_error () =
  let ctx = typecheck {|mod Test do
    fn f(x: String) do x + x end
  end|} in
  Alcotest.(check bool) "String + String: Num error" true (has_errors ctx)

let test_tc_ord_string () =
  let ctx = typecheck {|mod Test do
    fn f(a: String, b: String) do a < b end
  end|} in
  Alcotest.(check bool) "String < String: no errors (Ord)" false (has_errors ctx)

let test_tc_ord_int () =
  let ctx = typecheck {|mod Test do
    fn f(a: Int, b: Int) do a > b end
  end|} in
  Alcotest.(check bool) "Int > Int: no errors (Ord)" false (has_errors ctx)

let test_tc_float_ops () =
  let ctx = typecheck {|mod Test do
    fn f(x: Float) do x +. 1.0 end
  end|} in
  Alcotest.(check bool) "Float +. Float: no errors" false (has_errors ctx)

(* Nil/Cons constructor tests *)
let test_tc_nil_ctor () =
  let ctx = typecheck {|mod Test do
    fn empty() do [] end
  end|} in
  Alcotest.(check bool) "Nil: no errors" false (has_errors ctx)

let test_tc_cons_ctor () =
  let ctx = typecheck {|mod Test do
    fn list123() do [1, 2, 3] end
  end|} in
  Alcotest.(check bool) "[1,2,3]: no errors" false (has_errors ctx)

let test_tc_head_builtin () =
  let ctx = typecheck {|mod Test do
    fn first(xs) do head(xs) end
  end|} in
  Alcotest.(check bool) "head builtin: no errors" false (has_errors ctx)

(* eval: head/tail/is_nil *)
let test_eval_head () =
  let env = eval_module {|mod Test do
    fn first(xs) do head(xs) end
  end|} in
  let xs = March_eval.Eval.VCon ("Cons",
    [March_eval.Eval.VInt 1;
     March_eval.Eval.VCon ("Cons",
       [March_eval.Eval.VInt 2; March_eval.Eval.VCon ("Nil", [])])]) in
  let v = call_fn env "first" [xs] in
  Alcotest.(check int) "head([1,2]) = 1" 1
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

let test_eval_tail () =
  let env = eval_module {|mod Test do
    fn rest(xs) do tail(xs) end
  end|} in
  let xs = March_eval.Eval.VCon ("Cons",
    [March_eval.Eval.VInt 1;
     March_eval.Eval.VCon ("Cons",
       [March_eval.Eval.VInt 2; March_eval.Eval.VCon ("Nil", [])])]) in
  let v = call_fn env "rest" [xs] in
  match v with
  | March_eval.Eval.VCon ("Cons", [March_eval.Eval.VInt 2; _]) -> ()
  | _ -> Alcotest.fail "expected Cons(2, ...)"

let test_eval_is_nil () =
  let env = eval_module {|mod Test do
    fn empty(xs) do is_nil(xs) end
  end|} in
  let nil = March_eval.Eval.VCon ("Nil", []) in
  let cons = March_eval.Eval.VCon ("Cons", [March_eval.Eval.VInt 1; nil]) in
  let v_nil = call_fn env "empty" [nil] in
  let v_cons = call_fn env "empty" [cons] in
  Alcotest.(check bool) "is_nil([]) = true" true
    (match v_nil with March_eval.Eval.VBool b -> b | _ -> failwith "expected VBool");
  Alcotest.(check bool) "is_nil([1]) = false" false
    (match v_cons with March_eval.Eval.VBool b -> b | _ -> failwith "expected VBool")

(* Parser: interface/impl/sig/extern/use *)
let test_parse_interface_decl () =
  let src = {|mod Test do
    interface Eq(a) do
      fn eq: a -> a -> Bool
    end
  end|} in
  let m = parse_module src in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DInterface (idef, _)] ->
    Alcotest.(check string) "interface name" "Eq" idef.iface_name.txt;
    Alcotest.(check int) "1 method" 1 (List.length idef.iface_methods)
  | _ -> Alcotest.fail "expected DInterface"

let test_parse_impl_decl () =
  let src = {|mod Test do
    impl Eq(Int) do
      fn eq(x, y) do x == y end
    end
  end|} in
  let m = parse_module src in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DImpl (idef, _)] ->
    Alcotest.(check string) "impl iface" "Eq" idef.impl_iface.txt;
    Alcotest.(check int) "1 method" 1 (List.length idef.impl_methods)
  | _ -> Alcotest.fail "expected DImpl"

let test_parse_sig_decl () =
  let src = {|mod Test do
    sig Collections do
      fn insert: Int -> Int
    end
  end|} in
  let m = parse_module src in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DSig (name, sdef, _)] ->
    Alcotest.(check string) "sig name" "Collections" name.txt;
    Alcotest.(check int) "1 fn" 1 (List.length sdef.sig_fns)
  | _ -> Alcotest.fail "expected DSig"

let test_parse_extern_decl () =
  let src = {|mod Test do
    extern "libc": Cap(LibC) do
      fn malloc(n: Int): Int
    end
  end|} in
  let m = parse_module src in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DExtern (edef, _)] ->
    Alcotest.(check string) "lib name" "libc" edef.ext_lib_name;
    Alcotest.(check int) "1 extern fn" 1 (List.length edef.ext_fns)
  | _ -> Alcotest.fail "expected DExtern"

let test_parse_use_all () =
  let src = {|mod Test do
    use Collections.*
  end|} in
  let m = parse_module src in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DUse (ud, _)] ->
    Alcotest.(check bool) "UseAll" true
      (match ud.use_sel with March_ast.Ast.UseAll -> true | _ -> false)
  | _ -> Alcotest.fail "expected DUse UseAll"

let test_parse_use_names () =
  let src = {|mod Test do
    use Collections.{insert, lookup}
  end|} in
  let m = parse_module src in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DUse (ud, _)] ->
    (match ud.use_sel with
     | March_ast.Ast.UseNames names ->
       Alcotest.(check int) "2 names" 2 (List.length names)
     | _ -> Alcotest.fail "expected UseNames")
  | _ -> Alcotest.fail "expected DUse UseNames"

(* String interpolation *)
let test_parse_string_interp () =
  let lexbuf = Lexing.from_string {|"hi ${name}!"|} in
  let expr = March_parser.Parser.expr_eof March_lexer.Lexer.token lexbuf in
  (* Should desugar to: "hi " ++ to_string(name) ++ "!" *)
  match expr with
  | March_ast.Ast.EApp (March_ast.Ast.EVar cat2, [_; _], _)
    when cat2.txt = "++" -> ()
  | _ -> Alcotest.fail "expected ++ desugaring from string interpolation"

let test_eval_string_interp () =
  let env = eval_module {|mod Test do
    fn greet(name) do "Hello, ${name}!" end
  end|} in
  let v = call_fn env "greet" [March_eval.Eval.VString "World"] in
  Alcotest.(check string) "string interpolation" "Hello, World!"
    (match v with March_eval.Eval.VString s -> s | _ -> failwith "expected VString")

(* mod typecheck: DMod exposes names with prefix *)
let test_tc_mod_typecheck () =
  let ctx = typecheck {|mod Test do
    mod Foo do
      pub fn bar() do 42 end
    end
    fn main() do Foo.bar() end
  end|} in
  Alcotest.(check bool) "pub Foo.bar accessible after mod" false (has_errors ctx)

let test_tc_mod_private () =
  let ctx = typecheck {|mod Test do
    mod Foo do
      fn secret() do 42 end
    end
    fn main() do Foo.secret() end
  end|} in
  Alcotest.(check bool) "private Foo.secret not accessible" true (has_errors ctx)

(* Protocol declaration parsing *)
let test_parse_protocol_decl () =
  let src = {|mod Test do
    protocol Transfer do
      Client -> Server : String
      Server -> Client : Int
    end
  end|} in
  let m = parse_module src in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DProtocol (name, pdef, _)] ->
    Alcotest.(check string) "protocol name" "Transfer" name.March_ast.Ast.txt;
    Alcotest.(check int) "2 steps" 2 (List.length pdef.March_ast.Ast.proto_steps)
  | _ -> Alcotest.fail "expected single DProtocol"

let test_parse_protocol_loop () =
  let src = {|mod Test do
    protocol P do
      loop do
        A -> B : Int
      end
    end
  end|} in
  let m = parse_module src in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DProtocol (_, pdef, _)] ->
    (match pdef.March_ast.Ast.proto_steps with
     | [March_ast.Ast.ProtoLoop [_]] -> ()
     | _ -> Alcotest.fail "expected ProtoLoop with one step")
  | _ -> Alcotest.fail "expected single DProtocol"

(* sig conformance *)
let test_tc_sig_satisfied () =
  let ctx = typecheck {|mod Test do
    sig Foo do
      fn bar : Int -> Int
    end
    mod Foo do
      pub fn bar(x : Int) : Int do x end
    end
  end|} in
  Alcotest.(check bool) "sig satisfied — no errors" false (has_errors ctx)

let test_tc_sig_missing () =
  let ctx = typecheck {|mod Test do
    sig Foo do
      fn bar : Int -> Int
    end
    mod Foo do
      pub fn baz(x : Int) : Int do x end
    end
  end|} in
  Alcotest.(check bool) "sig missing fn — has errors" true (has_errors ctx)

(* impl validation *)
let test_tc_impl_valid () =
  let ctx = typecheck {|mod Test do
    interface Stringify(a) do
      fn to_s : a -> String
    end
    impl Stringify(Int) do
      fn to_s(x : Int) : String do int_to_string(x) end
    end
  end|} in
  Alcotest.(check bool) "valid impl — no errors" false (has_errors ctx)

let test_tc_impl_unknown_iface () =
  let ctx = typecheck {|mod Test do
    impl NoSuchInterface(Int) do
      fn foo(x : Int) : Int do x end
    end
  end|} in
  Alcotest.(check bool) "impl unknown interface — has errors" true (has_errors ctx)

let test_type_map_populated () =
  let src = {|mod Test do
    fn go(x : Int) do x end
  end|} in
  let m = March_desugar.Desugar.desugar_module
    (let lexbuf = Lexing.from_string src in
     March_parser.Parser.module_ March_lexer.Lexer.token lexbuf) in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  Alcotest.(check bool) "type map is non-empty" true
    (Hashtbl.length type_map > 0)

let test_type_map_fn_recorded () =
  let src = {|mod Test do
    fn add(x : Int, y : Int) do x end
  end|} in
  let m = March_desugar.Desugar.desugar_module
    (let lexbuf = Lexing.from_string src in
     March_parser.Parser.module_ March_lexer.Lexer.token lexbuf) in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  Alcotest.(check bool) "type map has many entries" true
    (Hashtbl.length type_map >= 3)

let test_convert_ty_int () =
  let tc = March_typecheck.Typecheck.TCon ("Int", []) in
  let result = March_tir.Lower.convert_ty tc in
  Alcotest.(check string) "Int converts to TInt" "TInt"
    (match result with March_tir.Tir.TInt -> "TInt" | _ -> "other")

let test_convert_ty_arrow () =
  let ti = March_typecheck.Typecheck.TCon ("Int", []) in
  let tc = March_typecheck.Typecheck.TArrow (ti, March_typecheck.Typecheck.TArrow (ti, ti)) in
  let result = March_tir.Lower.convert_ty tc in
  Alcotest.(check string) "curried arrow uncurried" "TFn([TInt;TInt],TInt)"
    (match result with
     | March_tir.Tir.TFn ([March_tir.Tir.TInt; March_tir.Tir.TInt], March_tir.Tir.TInt) ->
       "TFn([TInt;TInt],TInt)"
     | _ -> "other")

(* ── Defunctionalization tests ─────────────────────────────────────────── *)

(** Parse, desugar, typecheck, lower with type_map, monomorphize, defunctionalize. *)
let defun_module src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  March_tir.Defun.defunctionalize tir

let test_defun_free_vars () =
  let m = defun_module {|mod Test do
    fn make_adder(n : Int) : (Int -> Int) do
      fn x -> x + n
    end
  end|} in
  (* After defun, the lifted $lam_apply fn should have n as a param *)
  let lifted = List.filter (fun f ->
    String.length f.March_tir.Tir.fn_name > 6 &&
    String.sub f.March_tir.Tir.fn_name (String.length f.March_tir.Tir.fn_name - 6) 6 = "$apply"
  ) m.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "lifted apply fn exists" true (List.length lifted >= 1);
  (* The apply fn should have 2 params: captured n + original x *)
  let apply_fn = List.hd lifted in
  Alcotest.(check int) "apply fn has 2 params (1 captured + 1 original)" 2
    (List.length apply_fn.March_tir.Tir.fn_params)

let test_defun_closure_struct () =
  let m = defun_module {|mod Test do
    fn main() : Int do
      let add1 = fn x -> x + 1
      add1(41)
    end
  end|} in
  let has_closure = List.exists (function
    | March_tir.Tir.TDClosure _ -> true
    | _ -> false
  ) m.March_tir.Tir.tm_types in
  Alcotest.(check bool) "TDClosure in tm_types" true has_closure

let test_defun_no_letrec_lambda () =
  (* After defun, lambda ELetRecs must be replaced with EAlloc *)
  let m = defun_module {|mod Test do
    fn main() : Int do
      let add1 = fn x -> x + 1
      add1(41)
    end
  end|} in
  let rec has_letrec_lambda = function
    | March_tir.Tir.ELetRec ([fn], March_tir.Tir.EAtom (March_tir.Tir.AVar ref))
      when fn.March_tir.Tir.fn_name = ref.March_tir.Tir.v_name -> true
    | March_tir.Tir.ELet (_, e1, e2) -> has_letrec_lambda e1 || has_letrec_lambda e2
    | March_tir.Tir.ELetRec (fns, body) ->
      List.exists (fun f -> has_letrec_lambda f.March_tir.Tir.fn_body) fns || has_letrec_lambda body
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun b -> has_letrec_lambda b.March_tir.Tir.br_body) brs ||
      (match def with Some e -> has_letrec_lambda e | None -> false)
    | March_tir.Tir.ESeq (a, b) -> has_letrec_lambda a || has_letrec_lambda b
    | _ -> false
  in
  List.iter (fun fn ->
    Alcotest.(check bool)
      (Printf.sprintf "no lambda ELetRec in %s" fn.March_tir.Tir.fn_name)
      false (has_letrec_lambda fn.March_tir.Tir.fn_body)
  ) m.March_tir.Tir.tm_fns

let test_defun_indirect_call_becomes_ecallptr () =
  (* A call through a closure variable should become ECallPtr *)
  let m = defun_module {|mod Test do
    fn apply_fn(f : Int -> Int, x : Int) : Int do f(x) end
    fn main() : Int do
      let add1 = fn x -> x + 1
      apply_fn(add1, 41)
    end
  end|} in
  let apply_fn = List.find (fun f -> f.March_tir.Tir.fn_name = "apply_fn") m.March_tir.Tir.tm_fns in
  let rec has_callptr = function
    | March_tir.Tir.ECallPtr _ -> true
    | March_tir.Tir.ELet (_, e1, e2) -> has_callptr e1 || has_callptr e2
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun b -> has_callptr b.March_tir.Tir.br_body) brs ||
      (match def with Some e -> has_callptr e | None -> false)
    | March_tir.Tir.ESeq (a, b) -> has_callptr a || has_callptr b
    | _ -> false
  in
  Alcotest.(check bool) "apply_fn body has ECallPtr" true (has_callptr apply_fn.March_tir.Tir.fn_body)

let test_defun_zero_capture_closure () =
  let m = defun_module {|mod Test do
    fn main() : Int do
      let add1 = fn x -> x + 1
      add1(41)
    end
  end|} in
  let closures = List.filter_map (function
    | March_tir.Tir.TDClosure (_, fields) -> Some fields
    | _ -> None
  ) m.March_tir.Tir.tm_types in
  Alcotest.(check bool) "at least one closure" true (closures <> []);
  (* zero-capture closure has exactly one field: the fn_ptr (TPtr TUnit) *)
  Alcotest.(check bool) "zero-capture closure has no fields" true
    (List.exists (fun fields -> fields = [March_tir.Tir.TPtr March_tir.Tir.TUnit]) closures)

let test_defun_nested_lambda () =
  (* fn make_adder(n) = fn x -> x + n produces a nested closure.
     After defun, the outer lifted fn should have NO ELetRec-lambda nodes. *)
  let m = defun_module {|mod Test do
    fn make_adder(n : Int) : (Int -> Int) do
      fn x -> x + n
    end
    fn main() : Int do
      let add2 = make_adder(2)
      add2(40)
    end
  end|} in
  let rec has_letrec_lambda = function
    | March_tir.Tir.ELetRec ([fn], March_tir.Tir.EAtom (March_tir.Tir.AVar ref))
      when fn.March_tir.Tir.fn_name = ref.March_tir.Tir.v_name -> true
    | March_tir.Tir.ELet (_, e1, e2) -> has_letrec_lambda e1 || has_letrec_lambda e2
    | March_tir.Tir.ELetRec (fns, body) ->
      List.exists (fun f -> has_letrec_lambda f.March_tir.Tir.fn_body) fns
      || has_letrec_lambda body
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun b -> has_letrec_lambda b.March_tir.Tir.br_body) brs ||
      (match def with Some e -> has_letrec_lambda e | None -> false)
    | March_tir.Tir.ESeq (a, b) -> has_letrec_lambda a || has_letrec_lambda b
    | _ -> false
  in
  (* check ALL fns including lifted ones *)
  List.iter (fun fn ->
    Alcotest.(check bool)
      (Printf.sprintf "no lambda ELetRec in %s after defun" fn.March_tir.Tir.fn_name)
      false (has_letrec_lambda fn.March_tir.Tir.fn_body)
  ) m.March_tir.Tir.tm_fns

let test_defun_pp_type_def () =
  let td = March_tir.Tir.TDClosure ("Clo_foo", [March_tir.Tir.TInt; March_tir.Tir.TBool]) in
  let s = March_tir.Pp.string_of_type_def td in
  (* Should contain closure name and field types *)
  let contains sub str =
    let sub_len = String.length sub and str_len = String.length str in
    let rec loop i = if i > str_len - sub_len then false
      else if String.sub str i sub_len = sub then true
      else loop (i+1)
    in loop 0
  in
  Alcotest.(check bool) "pp TDClosure contains 'Clo_foo'" true (contains "Clo_foo" s);
  Alcotest.(check bool) "pp TDClosure contains 'Int'" true (contains "Int" s)

let test_defun_e2e_no_lambda_letrec () =
  (* Full pipeline: lower → mono → defun produces no lambda ELetRec nodes *)
  let m = defun_module {|mod Test do
    fn apply_twice(f : Int -> Int, x : Int) : Int do f(f(x)) end
    fn main() : Int do
      let add3 = fn x -> x + 3
      apply_twice(add3, 10)
    end
  end|} in
  let rec has_letrec_lambda = function
    | March_tir.Tir.ELetRec ([fn], March_tir.Tir.EAtom (March_tir.Tir.AVar ref))
      when fn.March_tir.Tir.fn_name = ref.March_tir.Tir.v_name -> true
    | March_tir.Tir.ELet (_, e1, e2) -> has_letrec_lambda e1 || has_letrec_lambda e2
    | March_tir.Tir.ELetRec (fns, body) ->
      List.exists (fun f -> has_letrec_lambda f.March_tir.Tir.fn_body) fns
      || has_letrec_lambda body
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun b -> has_letrec_lambda b.March_tir.Tir.br_body) brs ||
      (match def with Some e -> has_letrec_lambda e | None -> false)
    | March_tir.Tir.ESeq (a, b) -> has_letrec_lambda a || has_letrec_lambda b
    | _ -> false
  in
  List.iter (fun fn ->
    Alcotest.(check bool)
      (Printf.sprintf "no lambda ELetRec in %s" fn.March_tir.Tir.fn_name)
      false (has_letrec_lambda fn.March_tir.Tir.fn_body)
  ) m.March_tir.Tir.tm_fns

let test_defun_e2e_closure_types_present () =
  let m = defun_module {|mod Test do
    fn apply_twice(f : Int -> Int, x : Int) : Int do f(f(x)) end
    fn main() : Int do
      let add3 = fn x -> x + 3
      apply_twice(add3, 10)
    end
  end|} in
  let closure_count = List.length (List.filter (function
    | March_tir.Tir.TDClosure _ -> true | _ -> false
  ) m.March_tir.Tir.tm_types) in
  Alcotest.(check bool) "at least one TDClosure in tm_types" true (closure_count >= 1)

let test_defun_e2e_no_hof_unchanged () =
  (* A program with no lambdas/HOF should produce no TDClosure types *)
  let m = defun_module {|mod Test do
    fn double(x : Int) : Int do x + x end
    fn main() : Int do double(21) end
  end|} in
  let closure_count = List.length (List.filter (function
    | March_tir.Tir.TDClosure _ -> true | _ -> false
  ) m.March_tir.Tir.tm_types) in
  Alcotest.(check int) "no TDClosure for non-HOF program" 0 closure_count

let contains sub s =
  let sl = String.length sub and tl = String.length s in
  let rec go i = i <= tl - sl && (String.sub s i sl = sub || go (i + 1))
  in go 0

let test_actor_handler_extra_field () =
  (* Handler returns an extra field not in state → error with note *)
  let ctx = typecheck {|mod Test do
    actor Counter do
      state { value : Int }
      init { value = 0 }
      on Bad() do
        { value = 0, extra = true }
      end
    end
  end|} in
  Alcotest.(check bool) "extra field: has error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  (match List.find_opt (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Error) diags with
  | None -> Alcotest.fail "expected an Error diagnostic"
  | Some d ->
    Alcotest.(check bool) "message mentions handler 'Bad'" true
      (contains "Bad" d.March_errors.Errors.message);
    Alcotest.(check bool) "message mentions actor 'Counter'" true
      (contains "Counter" d.March_errors.Errors.message);
    Alcotest.(check bool) "has at least one note" true
      (d.March_errors.Errors.notes <> []);
    Alcotest.(check bool) "note mentions 'extra'" true
      (List.exists (fun n -> contains "extra" n)
        d.March_errors.Errors.notes))

let test_actor_handler_missing_field () =
  (* Handler omits a state field → error with missing-field note *)
  let ctx = typecheck {|mod Test do
    actor Widget do
      state { value : Int, name : String }
      init { value = 0, name = "x" }
      on Reset() do
        { value = 0 }
      end
    end
  end|} in
  Alcotest.(check bool) "missing field: has error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  (match List.find_opt (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Error) diags with
  | None -> Alcotest.fail "expected an Error diagnostic"
  | Some d ->
    Alcotest.(check bool) "note mentions 'name'" true
      (List.exists (fun n -> contains "name" n)
        d.March_errors.Errors.notes))

let test_actor_handler_correct () =
  (* Correct handler → no errors *)
  let ctx = typecheck {|mod Test do
    actor Counter do
      state { value : Int }
      init { value = 0 }
      on Inc() do
        { value = state.value + 1 }
      end
    end
  end|} in
  Alcotest.(check bool) "correct handler: no errors" false (has_errors ctx)

(* ── Perceus RC tests ────────────────────────────────────────────────── *)

(** Parse, desugar, typecheck, lower, mono, defun, then run perceus. *)
let perceus_module src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  March_tir.Perceus.perceus tir

let test_perceus_no_ops_for_primitives () =
  (* A function using only Int values should have no EIncRC/EDecRC/EFree/EReuse *)
  let m = perceus_module {|mod Test do
    fn double(x : Int) : Int do x + x end
    fn main() : Int do double(21) end
  end|} in
  let rec has_rc_op = function
    | March_tir.Tir.EIncRC _ | March_tir.Tir.EDecRC _
    | March_tir.Tir.EFree _ | March_tir.Tir.EReuse _ -> true
    | March_tir.Tir.ELet (_, e1, e2) -> has_rc_op e1 || has_rc_op e2
    | March_tir.Tir.ESeq (e1, e2) -> has_rc_op e1 || has_rc_op e2
    | March_tir.Tir.ELetRec (fns, body) ->
      List.exists (fun f -> has_rc_op f.March_tir.Tir.fn_body) fns || has_rc_op body
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun b -> has_rc_op b.March_tir.Tir.br_body) brs ||
      (match def with Some e -> has_rc_op e | None -> false)
    | _ -> false
  in
  List.iter (fun fn ->
    Alcotest.(check bool)
      (Printf.sprintf "no RC op in %s (primitives only)" fn.March_tir.Tir.fn_name)
      false (has_rc_op fn.March_tir.Tir.fn_body)
  ) m.March_tir.Tir.tm_fns

let test_perceus_dead_binding_decrc () =
  (* A heap value created but never used should get EDecRC inserted *)
  let m = perceus_module {|mod Test do
    type Box = Box(Int)
    fn make_unused() : Int do
      let b = Box(42)
      0
    end
  end|} in
  let f = List.find (fun fn -> fn.March_tir.Tir.fn_name = "make_unused") m.March_tir.Tir.tm_fns in
  let rec has_decrc = function
    | March_tir.Tir.EDecRC _ -> true
    | March_tir.Tir.ELet (_, e1, e2) -> has_decrc e1 || has_decrc e2
    | March_tir.Tir.ESeq (e1, e2) -> has_decrc e1 || has_decrc e2
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun b -> has_decrc b.March_tir.Tir.br_body) brs ||
      (match def with Some e -> has_decrc e | None -> false)
    | _ -> false
  in
  Alcotest.(check bool) "dead heap binding gets EDecRC" true (has_decrc f.March_tir.Tir.fn_body)

let test_perceus_no_rc_for_last_use () =
  (* Constructing a value and immediately returning it (last use = ownership transfer)
     should have no EDecRC *)
  let m = perceus_module {|mod Test do
    type Box = Box(Int)
    fn wrap(x : Int) : Box do Box(x) end
  end|} in
  let f = List.find (fun fn -> fn.March_tir.Tir.fn_name = "wrap") m.March_tir.Tir.tm_fns in
  let rec has_decrc = function
    | March_tir.Tir.EDecRC _ -> true
    | March_tir.Tir.ELet (_, e1, e2) -> has_decrc e1 || has_decrc e2
    | March_tir.Tir.ESeq (e1, e2) -> has_decrc e1 || has_decrc e2
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun b -> has_decrc b.March_tir.Tir.br_body) brs ||
      (match def with Some e -> has_decrc e | None -> false)
    | _ -> false
  in
  Alcotest.(check bool) "last-use ownership transfer: no EDecRC" false (has_decrc f.March_tir.Tir.fn_body)

let test_perceus_pipeline_no_crash () =
  (* The full pipeline including perceus runs without exception *)
  let m = perceus_module {|mod Test do
    fn double(x : Int) : Int do x + x end
    fn main() : Int do double(21) end
  end|} in
  Alcotest.(check bool) "perceus pipeline produced functions" true
    (List.length m.March_tir.Tir.tm_fns >= 1)

let test_perceus_needs_rc_tcon () =
  (* needs_rc returns true for TCon, false for TInt *)
  Alcotest.(check bool) "TCon needs RC" true
    (March_tir.Perceus.needs_rc (March_tir.Tir.TCon ("List", [])));
  Alcotest.(check bool) "TInt no RC" false
    (March_tir.Perceus.needs_rc March_tir.Tir.TInt)

let test_perceus_preserves_fn_count () =
  (* After perceus, the number of functions is unchanged *)
  let m = perceus_module {|mod Test do
    fn a(x : Int) : Int do x end
    fn b(x : Int) : Int do x end
  end|} in
  Alcotest.(check int) "perceus preserves fn count" 2
    (List.length m.March_tir.Tir.tm_fns)

(* --- multiline tests --- *)

let test_multiline_depth_zero () =
  Alcotest.(check int) "single expression has depth 0"
    0 (March_repl.Multiline.do_end_depth "x + 1")

let test_multiline_depth_open () =
  Alcotest.(check int) "open do block has depth 1"
    1 (March_repl.Multiline.do_end_depth "fn foo() do\n  x + 1")

let test_multiline_depth_closed () =
  Alcotest.(check int) "closed do block has depth 0"
    0 (March_repl.Multiline.do_end_depth "fn foo() do\n  x + 1\nend")

let test_multiline_ends_with_with () =
  Alcotest.(check bool) "match opener ends with with"
    true (March_repl.Multiline.ends_with_with "match x with")

let test_multiline_not_ends_with_with () =
  Alcotest.(check bool) "record update does not trigger with heuristic"
    false (March_repl.Multiline.ends_with_with "let y = { x with foo = 1 }")

let test_multiline_starts_with_pipe () =
  Alcotest.(check bool) "match arm starts with pipe"
    true (March_repl.Multiline.starts_with_pipe "| Some(x) -> x")

let test_multiline_is_complete_simple () =
  Alcotest.(check bool) "simple expression is complete"
    true (March_repl.Multiline.is_complete "x + 1")

let test_multiline_is_complete_open_block () =
  Alcotest.(check bool) "open block is not complete"
    false (March_repl.Multiline.is_complete "fn foo() do\n  x")

(* --- complete tests --- *)

let test_complete_command () =
  let completions = March_repl.Complete.complete ":q" [] in
  Alcotest.(check bool) ":q completes to :quit or :q"
    true (List.mem ":quit" completions || List.mem ":q" completions)

let test_complete_keyword () =
  let completions = March_repl.Complete.complete "fn" [] in
  Alcotest.(check bool) "fn is in keyword completions"
    true (List.mem "fn" completions)

let test_complete_in_scope () =
  let scope = [("double", "Int -> Int"); ("x", "Int")] in
  let completions = March_repl.Complete.complete "do" scope in
  Alcotest.(check bool) "double completes from scope"
    true (List.mem "double" completions)

let test_complete_empty_all () =
  let completions = March_repl.Complete.complete "" [] in
  Alcotest.(check bool) "empty prefix returns at least one keyword"
    true (List.length completions > 0)

(* ------------------------------------------------------------------ *)
(* complete_replace tests                                              *)
(* ------------------------------------------------------------------ *)

let mk_inp buf cur = { March_repl.Input.empty with
  March_repl.Input.buffer = buf;
  March_repl.Input.cursor = cur }

let test_complete_replace_prefix () =
  (* cursor at end of prefix "fo", no right side → replace "fo" with "foo" *)
  let s = mk_inp "fo" 2 in
  let s' = March_repl.Input.complete_replace s "foo" in
  Alcotest.(check string) "buf" "foo" s'.March_repl.Input.buffer;
  Alcotest.(check int)    "cur" 3     s'.March_repl.Input.cursor

let test_complete_replace_midword () =
  (* cursor mid-word: "fo|bar" → replace whole word with "foobar" *)
  let s = mk_inp "fobar" 2 in
  let s' = March_repl.Input.complete_replace s "foobar" in
  Alcotest.(check string) "buf" "foobar" s'.March_repl.Input.buffer;
  Alcotest.(check int)    "cur" 6        s'.March_repl.Input.cursor

let test_complete_replace_with_suffix () =
  (* context: "x = fo|bar + 1" → replace word "fobar" with "foobar", keep rest *)
  let s = mk_inp "x = fobar + 1" 7 in
  let s' = March_repl.Input.complete_replace s "foobar" in
  Alcotest.(check string) "buf" "x = foobar + 1" s'.March_repl.Input.buffer;
  Alcotest.(check int)    "cur" 10               s'.March_repl.Input.cursor

(* ------------------------------------------------------------------ *)
(* list_actors tests                                                   *)
(* ------------------------------------------------------------------ *)

let dummy_actor_def = March_ast.Ast.{
  actor_state    = [];
  actor_init     = ELit (LitInt 0, dummy_span);
  actor_handlers = [];
}

let mk_actor_inst name alive st = March_eval.Eval.{
  ai_name    = name;
  ai_def     = dummy_actor_def;
  ai_env_ref = ref [];
  ai_state   = st;
  ai_alive   = alive;
}

let test_list_actors_empty () =
  Hashtbl.clear March_eval.Eval.actor_registry;
  Alcotest.(check int) "empty registry" 0
    (List.length (March_eval.Eval.list_actors ()))

let test_list_actors_alive () =
  Hashtbl.clear March_eval.Eval.actor_registry;
  Hashtbl.add March_eval.Eval.actor_registry 0
    (mk_actor_inst "Counter" true (March_eval.Eval.VInt 5));
  let actors = March_eval.Eval.list_actors () in
  Alcotest.(check int) "one actor" 1 (List.length actors);
  let a = List.hd actors in
  Alcotest.(check int)    "pid"   0     a.March_eval.Eval.ai_pid;
  Alcotest.(check string) "name"  "Counter" a.March_eval.Eval.ai_name;
  Alcotest.(check bool)   "alive" true  a.March_eval.Eval.ai_alive;
  Alcotest.(check string) "state" "5"   a.March_eval.Eval.ai_state_str

let test_list_actors_sorted () =
  Hashtbl.clear March_eval.Eval.actor_registry;
  Hashtbl.add March_eval.Eval.actor_registry 2
    (mk_actor_inst "A" true (March_eval.Eval.VInt 0));
  Hashtbl.add March_eval.Eval.actor_registry 0
    (mk_actor_inst "B" false (March_eval.Eval.VUnit));
  let actors = March_eval.Eval.list_actors () in
  Alcotest.(check int) "two actors" 2 (List.length actors);
  Alcotest.(check int) "sorted first pid" 0
    (List.nth actors 0).March_eval.Eval.ai_pid;
  Alcotest.(check int) "sorted second pid" 2
    (List.nth actors 1).March_eval.Eval.ai_pid

(* ------------------------------------------------------------------ *)
(* Debugger tests                                                     *)
(* ------------------------------------------------------------------ *)

let test_edbg_ast () =
  let sp = March_ast.Ast.dummy_span in
  let e = March_ast.Ast.EDbg sp in
  Alcotest.(check bool) "EDbg is an expr" true
    (match e with March_ast.Ast.EDbg _ -> true | _ -> false)

let test_lexer_keyword_dbg () =
  let lexbuf = Lexing.from_string "dbg" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "lexes dbg keyword" true
    (match tok with March_parser.Parser.DBG -> true | _ -> false)

let test_parse_dbg () =
  let lexbuf = Lexing.from_string "dbg()" in
  let e = March_parser.Parser.expr_eof March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "parses dbg() as EDbg" true
    (match e with March_ast.Ast.EDbg _ -> true | _ -> false)

let test_desugar_edbg () =
  let sp = March_ast.Ast.dummy_span in
  let e = March_ast.Ast.EDbg sp in
  let e' = March_desugar.Desugar.desugar_expr e in
  Alcotest.(check bool) "EDbg desugar passthrough" true
    (match e' with March_ast.Ast.EDbg _ -> true | _ -> false)

let test_typecheck_edbg () =
  let type_map = Hashtbl.create 4 in
  let env = March_typecheck.Typecheck.base_env
    (March_errors.Errors.create ()) type_map in
  let sp = March_ast.Ast.dummy_span in
  let ty = March_typecheck.Typecheck.infer_expr env (March_ast.Ast.EDbg sp) in
  let pp = March_typecheck.Typecheck.pp_ty (March_typecheck.Typecheck.repr ty) in
  Alcotest.(check string) "EDbg typechecks as Unit" "()" pp

let test_eval_edbg_noop () =
  let v = March_eval.Eval.eval_expr March_eval.Eval.base_env
    (March_ast.Ast.EDbg March_ast.Ast.dummy_span) in
  Alcotest.(check bool) "EDbg evals to VUnit without debug mode" true
    (match v with March_eval.Eval.VUnit -> true | _ -> false)

let test_ring_buffer () =
  let rb = March_eval.Eval.ring_create 3 in
  March_eval.Eval.ring_push rb 10;
  March_eval.Eval.ring_push rb 20;
  March_eval.Eval.ring_push rb 30;
  Alcotest.(check (option int)) "ring get 0 (most recent)" (Some 30)
    (March_eval.Eval.ring_get rb 0);
  Alcotest.(check (option int)) "ring get 2 (oldest)" (Some 10)
    (March_eval.Eval.ring_get rb 2);
  (* overflow: push 40, evicts 10 *)
  March_eval.Eval.ring_push rb 40;
  Alcotest.(check (option int)) "ring get 0 after overflow" (Some 40)
    (March_eval.Eval.ring_get rb 0);
  Alcotest.(check (option int)) "ring get 2 after overflow" (Some 20)
    (March_eval.Eval.ring_get rb 2)

let test_trace_recording () =
  let cap = (match Sys.getenv_opt "MARCH_DEBUG_TRACE_SIZE" with
     | Some s -> (try int_of_string s with _ -> 100000) | None -> 100000) in
  let ctx = {
    March_eval.Eval.dc_trace   = March_eval.Eval.ring_create cap;
    dc_pos     = 0;
    dc_enabled = true;
    dc_depth   = 0;
    dc_on_dbg  = None;
  } in
  March_eval.Eval.debug_ctx := Some ctx;
  let src = "1 + 2" in
  let lexbuf = Lexing.from_string src in
  let e = March_parser.Parser.expr_eof March_lexer.Lexer.token lexbuf in
  let e' = March_desugar.Desugar.desugar_expr e in
  let _v = March_eval.Eval.eval_expr March_eval.Eval.base_env e' in
  let frames_recorded = ctx.March_eval.Eval.dc_trace.March_eval.Eval.rb_size in
  March_eval.Eval.debug_ctx := None;
  Alcotest.(check bool) "trace records frames" true (frames_recorded > 0)

let test_trace_navigation () =
  let ctx = March_debug.Debug.make_debug_ctx ~on_dbg:(fun _ -> ()) in
  March_debug.Debug.install ctx;
  let src = "1 + 2 + 3" in
  let lexbuf = Lexing.from_string src in
  let e = March_parser.Parser.expr_eof March_lexer.Lexer.token lexbuf in
  let e' = March_desugar.Desugar.desugar_expr e in
  ignore (March_eval.Eval.eval_expr March_eval.Eval.base_env e');
  let n = March_debug.Debug.frame_count ctx in
  Alcotest.(check bool) "recorded some frames" true (n > 0);
  let new_pos = March_debug.Trace.back ctx 1 in
  Alcotest.(check int) "back 1 moves cursor" 1 new_pos;
  let new_pos2 = March_debug.Trace.forward ctx 1 in
  Alcotest.(check int) "forward 1 returns to 0" 0 new_pos2;
  March_debug.Debug.uninstall ()

let test_replay () =
  let hit_dbg = ref false in
  let captured_env = ref March_eval.Eval.base_env in
  let ctx = March_debug.Debug.make_debug_ctx ~on_dbg:(fun env ->
    hit_dbg := true;
    captured_env := env
  ) in
  March_debug.Debug.install ctx;
  let src = {|
mod Test do
  fn factorial(n) do
    dbg()
    if n <= 1 then 1
    else n * factorial(n - 1)
  end
  fn main() do
    factorial(3)
  end
end
|} in
  let lexbuf = Lexing.from_string src in
  let m = March_parser.Parser.module_ March_lexer.Lexer.token lexbuf in
  let m' = March_desugar.Desugar.desugar_module m in
  (try March_eval.Eval.run_module m'
   with
   | March_eval.Eval.Eval_error _    -> ()
   | March_eval.Eval.Match_failure _ -> ());
  March_debug.Debug.uninstall ();
  Alcotest.(check bool) "dbg() was hit" true !hit_dbg;
  let frame_count_before = March_debug.Debug.frame_count ctx in
  let new_env = ("n", March_eval.Eval.VInt 5) ::
                (List.remove_assoc "n" !captured_env) in
  March_debug.Debug.install ctx;
  ignore (March_debug.Replay.replay_from ctx new_env);
  March_debug.Debug.uninstall ();
  let frame_count_after = March_debug.Debug.frame_count ctx in
  Alcotest.(check bool) "replay adds new frames" true
    (frame_count_after > frame_count_before)

let test_debug_continue () =
  let hit = ref false in
  let ctx = March_debug.Debug.make_debug_ctx ~on_dbg:(fun _env ->
    hit := true
  ) in
  March_debug.Debug.install ctx;
  let src = {|
mod DebugTest do
  fn main() do
    dbg()
    42
  end
end
|} in
  let lexbuf = Lexing.from_string src in
  let m  = March_parser.Parser.module_ March_lexer.Lexer.token lexbuf in
  let m' = March_desugar.Desugar.desugar_module m in
  (try March_eval.Eval.run_module m'
   with
   | March_eval.Eval.Eval_error _    -> ()
   | March_eval.Eval.Match_failure _ -> ());
  March_debug.Debug.uninstall ();
  Alcotest.(check bool) "dbg() triggered on_dbg callback" true !hit

let test_trace_overflow () =
  let ctx = {
    March_eval.Eval.dc_trace   = March_eval.Eval.ring_create 3;
    dc_pos     = 0;
    dc_enabled = true;
    dc_depth   = 0;
    dc_on_dbg  = None;
  } in
  March_debug.Debug.install ctx;
  let src = "1 + 2 + 3 + 4" in
  let lexbuf = Lexing.from_string src in
  let e = March_parser.Parser.expr_eof March_lexer.Lexer.token lexbuf in
  let e' = March_desugar.Desugar.desugar_expr e in
  ignore (March_eval.Eval.eval_expr March_eval.Eval.base_env e');
  March_debug.Debug.uninstall ();
  Alcotest.(check int) "ring buffer size capped at capacity" 3
    ctx.March_eval.Eval.dc_trace.March_eval.Eval.rb_size

let test_actor_snapshot () =
  Hashtbl.reset March_eval.Eval.actor_registry;
  Hashtbl.reset March_eval.Eval.actor_defs_tbl;
  March_eval.Eval.next_pid := 0;
  let snap = March_eval.Eval.snapshot_actors () in
  Alcotest.(check int) "empty snapshot has 0 instances" 0
    (List.length snap.March_eval.Eval.ass_instances);
  March_eval.Eval.restore_actors snap;
  Alcotest.(check int) "restore_actors leaves registry empty" 0
    (Hashtbl.length March_eval.Eval.actor_registry)

(* ── Docstring tests ──────────────────────────────────────────────────────── *)

let test_doc_parse_fn () =
  let m = parse_module {|mod Test do
    doc "Adds two numbers."
    fn add(a : Int, b : Int) : Int do a + b end
  end|} in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    Alcotest.(check (option string)) "doc string" (Some "Adds two numbers.") def.fn_doc
  | _ -> Alcotest.fail "expected single DFn"

let test_doc_triple_quoted () =
  let m = parse_module {|mod Test do
    doc """
Adds two numbers.
Returns their sum.
"""
    fn add(a : Int, b : Int) : Int do a + b end
  end|} in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    (match def.fn_doc with
     | Some s ->
       Alcotest.(check bool) "multiline content present"
         true (String.length s > 10)
     | None -> Alcotest.fail "expected Some doc")
  | _ -> Alcotest.fail "expected single DFn"

let test_doc_desugar () =
  let m = parse_and_desugar {|mod Test do
    doc "Computes factorial."
    fn factorial(0) do 1 end
    fn factorial(n) do n * factorial(n - 1) end
  end|} in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    Alcotest.(check (option string)) "doc preserved after desugar"
      (Some "Computes factorial.") def.fn_doc
  | _ -> Alcotest.fail "expected single DFn after group_fn_clauses"

let test_doc_eval_registry () =
  Hashtbl.reset March_eval.Eval.doc_registry;
  let _env = eval_module {|mod Test do
    doc "Adds two numbers."
    fn add(a : Int, b : Int) : Int do a + b end
  end|} in
  Alcotest.(check (option string)) "doc registered"
    (Some "Adds two numbers.")
    (March_eval.Eval.lookup_doc "add")

let test_doc_nested_module () =
  Hashtbl.reset March_eval.Eval.doc_registry;
  let _env = eval_module {|mod Test do
    mod Math do
      doc "Adds two numbers."
      pub fn add(a : Int, b : Int) : Int do a + b end
    end
  end|} in
  Alcotest.(check (option string)) "nested doc registered with prefix"
    (Some "Adds two numbers.")
    (March_eval.Eval.lookup_doc "Math.add")

let test_doc_none () =
  Hashtbl.reset March_eval.Eval.doc_registry;
  let _env = eval_module {|mod Test do
    fn undocumented() : Int do 42 end
  end|} in
  Alcotest.(check (option string)) "no doc is None"
    None
    (March_eval.Eval.lookup_doc "undocumented")

(* ── Purity oracle ───────────────────────────────────────────────── *)

let mk_var name ty = { March_tir.Tir.v_name = name; v_ty = ty; v_lin = March_tir.Tir.Unr }
let app op args = March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TInt)), args)
let ilit n = March_tir.Tir.ALit (March_ast.Ast.LitInt n)
let _blit b = March_tir.Tir.ALit (March_ast.Ast.LitBool b)

let test_purity_atom () =
  Alcotest.(check bool) "literal is pure" true
    (March_tir.Purity.is_pure (March_tir.Tir.EAtom (ilit 5)))

let test_purity_arith () =
  Alcotest.(check bool) "int add is pure" true
    (March_tir.Purity.is_pure (app "+" [ilit 1; ilit 2]))

let test_purity_println () =
  Alcotest.(check bool) "println is impure" false
    (March_tir.Purity.is_pure (app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")]))

let test_purity_print () =
  Alcotest.(check bool) "print is impure" false
    (March_tir.Purity.is_pure (app "print" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")]))

let test_purity_send () =
  Alcotest.(check bool) "send is impure" false
    (March_tir.Purity.is_pure (app "send" [March_tir.Tir.ALit (March_ast.Ast.LitString "msg")]))

let test_purity_let_pure () =
  let body = March_tir.Tir.EAtom (ilit 1) in
  let expr = March_tir.Tir.ELet (mk_var "x" March_tir.Tir.TInt, app "+" [ilit 2; ilit 3], body) in
  Alcotest.(check bool) "let with pure rhs is pure" true
    (March_tir.Purity.is_pure expr)

let test_purity_let_impure () =
  let body = March_tir.Tir.EAtom (ilit 1) in
  let expr = March_tir.Tir.ELet (mk_var "x" March_tir.Tir.TInt,
               app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")], body) in
  Alcotest.(check bool) "let with impure rhs is impure" false
    (March_tir.Purity.is_pure expr)

let test_purity_callptr () =
  let f = March_tir.Tir.ALit (March_ast.Ast.LitInt 0) in  (* dummy closure *)
  Alcotest.(check bool) "indirect call is impure" false
    (March_tir.Purity.is_pure (March_tir.Tir.ECallPtr (f, [])))

let test_purity_kill () =
  Alcotest.(check bool) "kill is impure" false
    (March_tir.Purity.is_pure (app "kill" [ilit 0]))

let test_purity_incrc () =
  let v = March_tir.Tir.AVar (mk_var "x" March_tir.Tir.TInt) in
  Alcotest.(check bool) "EIncRC is impure" false
    (March_tir.Purity.is_pure (March_tir.Tir.EIncRC v))

let test_purity_free () =
  let v = March_tir.Tir.AVar (mk_var "x" March_tir.Tir.TInt) in
  Alcotest.(check bool) "EFree is impure" false
    (March_tir.Purity.is_pure (March_tir.Tir.EFree v))

(* ── Constant folding ────────────────────────────────────────────── *)

let mk_fn name body =
  { March_tir.Tir.fn_name = name; fn_params = [];
    fn_ret_ty = March_tir.Tir.TInt; fn_body = body }
let mk_module fns = { March_tir.Tir.tm_name = "test"; tm_fns = fns; tm_types = [] }
let avar name ty = March_tir.Tir.AVar (mk_var name ty)
let flit f = March_tir.Tir.ALit (March_ast.Ast.LitFloat f)
let fapp op args =
  March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TFloat)), args)
let blit b = March_tir.Tir.ALit (March_ast.Ast.LitBool b)
let first_body m = (List.hd m.March_tir.Tir.tm_fns).March_tir.Tir.fn_body

let test_fold_int_add () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "+" [ilit 2; ilit 3])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "2+3=5" "(Tir.EAtom (Tir.ALit (Ast.LitInt 5)))"
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_int_mul () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "*" [ilit 6; ilit 7])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "6*7=42" "(Tir.EAtom (Tir.ALit (Ast.LitInt 42)))"
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_int_div_by_zero () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "/" [ilit 5; ilit 0])] in
  let _ = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "not changed" false !changed

let test_fold_float_add () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (fapp "+." [flit 1.5; flit 2.5])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "1.5+.2.5=4.0" "(Tir.EAtom (Tir.ALit (Ast.LitFloat 4.)))"
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_bool_not () =
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let m = mk_module [mk_fn "f" (bapp "not" [blit true])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "not true = false" "(Tir.EAtom (Tir.ALit (Ast.LitBool false)))"
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_and_shortcircuit_pure () =
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let m = mk_module [mk_fn "f" (bapp "&&" [blit false; blit true])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "false && true = false" "(Tir.EAtom (Tir.ALit (Ast.LitBool false)))"
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_and_shortcircuit_impure () =
  (* false && <AVar> IS folded: AVar is a pure atom (register read in ANF) *)
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let impure = app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")] in
  let print_var = mk_var "p" March_tir.Tir.TBool in
  let body = March_tir.Tir.ELet (print_var, impure,
               bapp "&&" [blit false; March_tir.Tir.AVar print_var]) in
  let m = mk_module [mk_fn "f" body] in
  let _ = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed (AVar is a pure atom)" true !changed

let test_fold_if_true () =
  let changed = ref false in
  let then_e = March_tir.Tir.EAtom (ilit 1) in
  let else_e = March_tir.Tir.EAtom (ilit 2) in
  let body = March_tir.Tir.ECase (blit true,
               [{ March_tir.Tir.br_tag = "True"; br_vars = []; br_body = then_e }],
               Some else_e) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "if true → then" "(Tir.EAtom (Tir.ALit (Ast.LitInt 1)))"
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_if_false () =
  let changed = ref false in
  let then_e = March_tir.Tir.EAtom (ilit 1) in
  let else_e = March_tir.Tir.EAtom (ilit 2) in
  let body = March_tir.Tir.ECase (blit false,
               [{ March_tir.Tir.br_tag = "True"; br_vars = []; br_body = then_e }],
               Some else_e) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "if false → else" "(Tir.EAtom (Tir.ALit (Ast.LitInt 2)))"
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_and_pure_var () =
  (* false && <AVar for pure value> → false (var is pure at atom position) *)
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let x = avar "x" March_tir.Tir.TBool in
  (* let x = true in false && x — x is a pure AVar at atom position *)
  let body = March_tir.Tir.ELet (mk_var "x" March_tir.Tir.TBool,
               March_tir.Tir.EAtom (blit true),
               bapp "&&" [blit false; x]) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed (pure var folded)" true !changed;
  (* The && should be folded; the let may remain *)
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, inner) ->
     (match inner with
      | March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitBool false)) -> ()
      | _ -> Alcotest.failf "expected false, got %s" (March_tir.Tir.show_expr inner))
   | March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitBool false)) -> ()
   | other -> Alcotest.failf "expected false, got %s" (March_tir.Tir.show_expr other))

let test_fold_or_shortcircuit_pure () =
  (* true || <pure rhs> → true *)
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let m = mk_module [mk_fn "f" (bapp "||" [blit true; blit false])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "true || false = true"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit true)))
    (March_tir.Tir.show_expr (first_body m'))

let _ = avar  (* suppress unused warning *)

(* ── Algebraic simplification ────────────────────────────────────── *)

let test_simplify_add_zero () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "+" [x; ilit 0])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x+0=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_mul_one () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "*" [x; ilit 1])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x*1=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_mul_zero_pure () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "*" [x; ilit 0])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x*0=0"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 0)))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_sub_self () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "-" [avar "x" March_tir.Tir.TInt; avar "x" March_tir.Tir.TInt])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x-x=0"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 0)))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_sub_different () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "-" [avar "x" March_tir.Tir.TInt; avar "y" March_tir.Tir.TInt])] in
  let _ = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "not changed" false !changed

let test_simplify_div_one () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "/" [x; ilit 1])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x/1=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_zero_div () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "/" [ilit 0; x])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "0/x=0"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 0)))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_strength_reduce () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "*" [x; ilit 2])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, March_tir.Tir.EApp (f, _), _) ->
     Alcotest.(check string) "strength reduce to add" "+" f.March_tir.Tir.v_name
   | _ -> Alcotest.fail "expected ELet wrapping EApp(+)")

let test_simplify_float_add_zero () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TFloat in
  let fapp' op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TFloat)), args) in
  let m = mk_module [mk_fn "f" (fapp' "+." [x; flit 0.0])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x+.0.0=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_bool_and_true () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TBool in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let m = mk_module [mk_fn "f" (bapp "&&" [x; blit true])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x&&true=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

(* ── Function inlining ───────────────────────────────────────────── *)

let test_inline_pure_small () =
  (* fn double(x) = x + x; fn main() = double(5) → call gets inlined *)
  let changed = ref false in
  let x_param = mk_var "x" March_tir.Tir.TInt in
  let double_body = app "+" [March_tir.Tir.AVar x_param; March_tir.Tir.AVar x_param] in
  let double_fn = { March_tir.Tir.fn_name = "double"; fn_params = [x_param];
                    fn_ret_ty = March_tir.Tir.TInt; fn_body = double_body } in
  let call = March_tir.Tir.EApp (mk_var "double"
               (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [ilit 5]) in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = [];
                  fn_ret_ty = March_tir.Tir.TInt; fn_body = call } in
  let m = mk_module [double_fn; main_fn] in
  let m' = March_tir.Inline.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (* main body should no longer be a bare EApp to "double" *)
  let main_body = (List.find (fun fd -> fd.March_tir.Tir.fn_name = "main") m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  (match main_body with
   | March_tir.Tir.EApp (f, _) when f.March_tir.Tir.v_name = "double" ->
     Alcotest.fail "call was not inlined"
   | _ -> ())

let test_inline_impure_not_inlined () =
  let changed = ref false in
  let x_param = mk_var "x" March_tir.Tir.TInt in
  let bad_body = March_tir.Tir.ESeq (
    app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")],
    March_tir.Tir.EAtom (March_tir.Tir.AVar x_param)) in
  let bad_fn = { March_tir.Tir.fn_name = "bad"; fn_params = [x_param];
                 fn_ret_ty = March_tir.Tir.TInt; fn_body = bad_body } in
  let call = March_tir.Tir.EApp (mk_var "bad"
               (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [ilit 1]) in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = [];
                  fn_ret_ty = March_tir.Tir.TInt; fn_body = call } in
  let m = mk_module [bad_fn; main_fn] in
  let _ = March_tir.Inline.run ~changed m in
  Alcotest.(check bool) "not changed (impure)" false !changed

let test_inline_recursive_not_inlined () =
  let changed = ref false in
  let n_param = mk_var "n" March_tir.Tir.TInt in
  (* self-calling fn — must not inline *)
  let fact_body = March_tir.Tir.EApp (mk_var "fact"
                    (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)),
                    [March_tir.Tir.AVar n_param]) in
  let fact_fn = { March_tir.Tir.fn_name = "fact"; fn_params = [n_param];
                  fn_ret_ty = March_tir.Tir.TInt; fn_body = fact_body } in
  let call = March_tir.Tir.EApp (mk_var "fact"
               (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [ilit 5]) in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = [];
                  fn_ret_ty = March_tir.Tir.TInt; fn_body = call } in
  let m = mk_module [fact_fn; main_fn] in
  let _ = March_tir.Inline.run ~changed m in
  Alcotest.(check bool) "not changed (recursive)" false !changed

let test_inline_mutual_recursion_not_inlined () =
  (* fn f(x) = g(x); fn g(x) = f(x) — mutually recursive, neither should inline *)
  let changed = ref false in
  let x_param = mk_var "x" March_tir.Tir.TInt in
  let g_call = March_tir.Tir.EApp (mk_var "g" (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [March_tir.Tir.AVar x_param]) in
  let f_fn = { March_tir.Tir.fn_name = "f"; fn_params = [x_param]; fn_ret_ty = March_tir.Tir.TInt; fn_body = g_call } in
  let f_call = March_tir.Tir.EApp (mk_var "f" (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [March_tir.Tir.AVar x_param]) in
  let g_fn = { March_tir.Tir.fn_name = "g"; fn_params = [x_param]; fn_ret_ty = March_tir.Tir.TInt; fn_body = f_call } in
  let call_f = March_tir.Tir.EApp (mk_var "f" (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [ilit 1]) in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = []; fn_ret_ty = March_tir.Tir.TInt; fn_body = call_f } in
  let m = mk_module [f_fn; g_fn; main_fn] in
  let _ = March_tir.Inline.run ~changed m in
  Alcotest.(check bool) "not changed (mutually recursive)" false !changed

(* ── Dead code elimination ───────────────────────────────────────── *)

let test_dce_dead_pure_let () =
  (* let x = 5 in 42 → 42, because x is unused and rhs is pure *)
  let changed = ref false in
  let x_var = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x_var, March_tir.Tir.EAtom (ilit 5), March_tir.Tir.EAtom (ilit 42)) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Dce.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "dead let removed" "(Tir.EAtom (Tir.ALit (Ast.LitInt 42)))"
    (March_tir.Tir.show_expr (first_body m'))

let test_dce_impure_let_kept () =
  (* let x = println("hi") in 42 → println("hi"); 42 (rhs is impure, must keep) *)
  let changed = ref false in
  let x_var = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x_var,
               app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")],
               March_tir.Tir.EAtom (ilit 42)) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Dce.run ~changed m in
  (* result should be ESeq, not the original ELet, but the print must be present *)
  (match first_body m' with
   | March_tir.Tir.ESeq _ -> ()  (* impure effect sequenced *)
   | March_tir.Tir.ELet _ -> ()  (* or kept as let — both acceptable *)
   | _ -> Alcotest.fail "impure rhs must be preserved")

let test_dce_used_let_kept () =
  (* let x = 5 in x + 1 → unchanged *)
  let changed = ref false in
  let x_var = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x_var, March_tir.Tir.EAtom (ilit 5),
               app "+" [March_tir.Tir.AVar x_var; ilit 1]) in
  let m = mk_module [mk_fn "f" body] in
  let _ = March_tir.Dce.run ~changed m in
  Alcotest.(check bool) "not changed (used)" false !changed

let test_dce_unreachable_top_fn () =
  (* fn unused() = 99 is not reachable from main → removed *)
  let changed = ref false in
  let unused_fn = { March_tir.Tir.fn_name = "unused"; fn_params = [];
                    fn_ret_ty = March_tir.Tir.TInt;
                    fn_body = March_tir.Tir.EAtom (ilit 99) } in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = [];
                  fn_ret_ty = March_tir.Tir.TInt;
                  fn_body = March_tir.Tir.EAtom (ilit 0) } in
  let m = mk_module [unused_fn; main_fn] in
  let m' = March_tir.Dce.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let fn_names = List.map (fun fd -> fd.March_tir.Tir.fn_name) m'.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "unused removed" false (List.mem "unused" fn_names);
  Alcotest.(check bool) "main kept"      true  (List.mem "main" fn_names)

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
          Alcotest.test_case "actor handler extra field"   `Quick test_actor_handler_extra_field;
          Alcotest.test_case "actor handler missing field" `Quick test_actor_handler_missing_field;
          Alcotest.test_case "actor handler correct"       `Quick test_actor_handler_correct;
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
          Alcotest.test_case "typed param annot"    `Quick test_tir_lower_typed_param;
          Alcotest.test_case "typed let annot"      `Quick test_tir_lower_typed_let;
          Alcotest.test_case "mono subst_ty"        `Quick test_mono_subst_ty;
          Alcotest.test_case "mono mangle_name"     `Quick test_mono_mangle;
          Alcotest.test_case "mono has_tvar"        `Quick test_mono_has_tvar;
          Alcotest.test_case "mono match_ty"        `Quick test_mono_match_ty;
          Alcotest.test_case "mono pipeline"        `Quick test_mono_pipeline_no_tvar;
          Alcotest.test_case "mono identity"         `Quick test_mono_identity;
          Alcotest.test_case "mono no TVar after"    `Quick test_mono_no_tvar_after_mono;
          Alcotest.test_case "mono two instances"    `Quick test_mono_two_instantiations;
          Alcotest.test_case "defun free vars"       `Quick test_defun_free_vars;
          Alcotest.test_case "defun closure struct"  `Quick test_defun_closure_struct;
          Alcotest.test_case "defun no letrec lambda"`Quick test_defun_no_letrec_lambda;
          Alcotest.test_case "defun indirect call"   `Quick test_defun_indirect_call_becomes_ecallptr;
          Alcotest.test_case "defun zero capture"    `Quick test_defun_zero_capture_closure;
          Alcotest.test_case "defun nested lambda"   `Quick test_defun_nested_lambda;
          Alcotest.test_case "defun pp type_def"     `Quick test_defun_pp_type_def;
          Alcotest.test_case "defun e2e no lambda letrec"    `Quick test_defun_e2e_no_lambda_letrec;
          Alcotest.test_case "defun e2e closure types"        `Quick test_defun_e2e_closure_types_present;
          Alcotest.test_case "defun e2e no HOF unchanged"     `Quick test_defun_e2e_no_hof_unchanged;
        ] );
      ( "constraints",
        [
          Alcotest.test_case "Num: Int + Int"       `Quick test_tc_num_int;
          Alcotest.test_case "Num: String + error"  `Quick test_tc_num_string_error;
          Alcotest.test_case "Ord: String <"        `Quick test_tc_ord_string;
          Alcotest.test_case "Ord: Int >"           `Quick test_tc_ord_int;
          Alcotest.test_case "Float +."             `Quick test_tc_float_ops;
        ] );
      ( "list builtins",
        [
          Alcotest.test_case "Nil ctor"             `Quick test_tc_nil_ctor;
          Alcotest.test_case "Cons ctor"            `Quick test_tc_cons_ctor;
          Alcotest.test_case "head builtin"         `Quick test_tc_head_builtin;
          Alcotest.test_case "eval head"            `Quick test_eval_head;
          Alcotest.test_case "eval tail"            `Quick test_eval_tail;
          Alcotest.test_case "eval is_nil"          `Quick test_eval_is_nil;
        ] );
      ( "declarations",
        [
          Alcotest.test_case "interface decl"       `Quick test_parse_interface_decl;
          Alcotest.test_case "impl decl"            `Quick test_parse_impl_decl;
          Alcotest.test_case "sig decl"             `Quick test_parse_sig_decl;
          Alcotest.test_case "extern decl"          `Quick test_parse_extern_decl;
          Alcotest.test_case "use all"              `Quick test_parse_use_all;
          Alcotest.test_case "use names"            `Quick test_parse_use_names;
          Alcotest.test_case "mod typecheck"        `Quick test_tc_mod_typecheck;
          Alcotest.test_case "mod private"          `Quick test_tc_mod_private;
          Alcotest.test_case "protocol decl"        `Quick test_parse_protocol_decl;
          Alcotest.test_case "protocol loop"        `Quick test_parse_protocol_loop;
          Alcotest.test_case "sig satisfied"        `Quick test_tc_sig_satisfied;
          Alcotest.test_case "sig missing fn"       `Quick test_tc_sig_missing;
          Alcotest.test_case "impl valid"           `Quick test_tc_impl_valid;
          Alcotest.test_case "impl unknown iface"   `Quick test_tc_impl_unknown_iface;
        ] );
      ( "string interp",
        [
          Alcotest.test_case "parse interp"         `Quick test_parse_string_interp;
          Alcotest.test_case "eval interp"          `Quick test_eval_string_interp;
        ] );
      ( "type_map", [
          Alcotest.test_case "populated after check" `Quick test_type_map_populated;
          Alcotest.test_case "fn params recorded" `Quick test_type_map_fn_recorded;
        ] );
      ( "convert_ty", [
          Alcotest.test_case "Int" `Quick test_convert_ty_int;
          Alcotest.test_case "arrow uncurried" `Quick test_convert_ty_arrow;
        ] );
      ( "perceus", [
          Alcotest.test_case "no RC ops for primitives"  `Quick test_perceus_no_ops_for_primitives;
          Alcotest.test_case "dead binding gets EDecRC"  `Quick test_perceus_dead_binding_decrc;
          Alcotest.test_case "last use no EDecRC"        `Quick test_perceus_no_rc_for_last_use;
          Alcotest.test_case "pipeline no crash"         `Quick test_perceus_pipeline_no_crash;
          Alcotest.test_case "needs_rc TCon/TInt"        `Quick test_perceus_needs_rc_tcon;
          Alcotest.test_case "preserves fn count"        `Quick test_perceus_preserves_fn_count;
        ] );
      "multiline", [
        Alcotest.test_case "depth zero" `Quick test_multiline_depth_zero;
        Alcotest.test_case "depth open" `Quick test_multiline_depth_open;
        Alcotest.test_case "depth closed" `Quick test_multiline_depth_closed;
        Alcotest.test_case "ends with with" `Quick test_multiline_ends_with_with;
        Alcotest.test_case "not ends with with" `Quick test_multiline_not_ends_with_with;
        Alcotest.test_case "starts with pipe" `Quick test_multiline_starts_with_pipe;
        Alcotest.test_case "is_complete simple" `Quick test_multiline_is_complete_simple;
        Alcotest.test_case "is_complete open block" `Quick test_multiline_is_complete_open_block;
      ];
      "complete", [
        Alcotest.test_case "command" `Quick test_complete_command;
        Alcotest.test_case "keyword" `Quick test_complete_keyword;
        Alcotest.test_case "in scope" `Quick test_complete_in_scope;
        Alcotest.test_case "empty all" `Quick test_complete_empty_all;
      ];
      "complete_replace", [
        Alcotest.test_case "prefix only"    `Quick test_complete_replace_prefix;
        Alcotest.test_case "mid word"       `Quick test_complete_replace_midword;
        Alcotest.test_case "with suffix"    `Quick test_complete_replace_with_suffix;
      ];
      "actors", [
        Alcotest.test_case "empty"  `Quick test_list_actors_empty;
        Alcotest.test_case "alive"  `Quick test_list_actors_alive;
        Alcotest.test_case "sorted" `Quick test_list_actors_sorted;
      ];
      "debugger", [
        Alcotest.test_case "EDbg AST"               `Quick test_edbg_ast;
        Alcotest.test_case "dbg keyword"            `Quick test_lexer_keyword_dbg;
        Alcotest.test_case "parse dbg()"            `Quick test_parse_dbg;
        Alcotest.test_case "desugar EDbg"           `Quick test_desugar_edbg;
        Alcotest.test_case "typecheck EDbg"         `Quick test_typecheck_edbg;
        Alcotest.test_case "eval EDbg no-op"        `Quick test_eval_edbg_noop;
        Alcotest.test_case "ring buffer"            `Quick test_ring_buffer;
        Alcotest.test_case "trace recording"        `Quick test_trace_recording;
        Alcotest.test_case "trace navigation"       `Quick test_trace_navigation;
        Alcotest.test_case "replay"                 `Quick test_replay;
        Alcotest.test_case "debug continue"         `Quick test_debug_continue;
        Alcotest.test_case "trace overflow"         `Quick test_trace_overflow;
        Alcotest.test_case "actor snapshot"         `Quick test_actor_snapshot;
      ];
      "docstrings", [
        Alcotest.test_case "parse fn doc"         `Quick test_doc_parse_fn;
        Alcotest.test_case "triple-quoted doc"    `Quick test_doc_triple_quoted;
        Alcotest.test_case "doc preserved after desugar" `Quick test_doc_desugar;
        Alcotest.test_case "doc registered in eval" `Quick test_doc_eval_registry;
        Alcotest.test_case "doc in nested module" `Quick test_doc_nested_module;
        Alcotest.test_case "no doc is None"       `Quick test_doc_none;
      ];
      ("purity", [
        Alcotest.test_case "atom"         `Quick test_purity_atom;
        Alcotest.test_case "arith"        `Quick test_purity_arith;
        Alcotest.test_case "println"      `Quick test_purity_println;
        Alcotest.test_case "print"        `Quick test_purity_print;
        Alcotest.test_case "send"         `Quick test_purity_send;
        Alcotest.test_case "let_pure"     `Quick test_purity_let_pure;
        Alcotest.test_case "let_impure"   `Quick test_purity_let_impure;
        Alcotest.test_case "callptr"    `Quick test_purity_callptr;
        Alcotest.test_case "kill"       `Quick test_purity_kill;
        Alcotest.test_case "incrc"      `Quick test_purity_incrc;
        Alcotest.test_case "free"       `Quick test_purity_free;
      ]);
      ("fold", [
        Alcotest.test_case "int_add"                 `Quick test_fold_int_add;
        Alcotest.test_case "int_mul"                 `Quick test_fold_int_mul;
        Alcotest.test_case "int_div_by_zero"         `Quick test_fold_int_div_by_zero;
        Alcotest.test_case "float_add"               `Quick test_fold_float_add;
        Alcotest.test_case "bool_not"                `Quick test_fold_bool_not;
        Alcotest.test_case "and_shortcircuit_pure"   `Quick test_fold_and_shortcircuit_pure;
        Alcotest.test_case "and_shortcircuit_impure" `Quick test_fold_and_shortcircuit_impure;
        Alcotest.test_case "if_true"                 `Quick test_fold_if_true;
        Alcotest.test_case "if_false"                `Quick test_fold_if_false;
        Alcotest.test_case "and_pure_var"            `Quick test_fold_and_pure_var;
        Alcotest.test_case "or_shortcircuit_pure"    `Quick test_fold_or_shortcircuit_pure;
      ]);
      ("simplify", [
        Alcotest.test_case "add_zero"          `Quick test_simplify_add_zero;
        Alcotest.test_case "mul_one"           `Quick test_simplify_mul_one;
        Alcotest.test_case "mul_zero_pure"     `Quick test_simplify_mul_zero_pure;
        Alcotest.test_case "sub_self"          `Quick test_simplify_sub_self;
        Alcotest.test_case "sub_different"     `Quick test_simplify_sub_different;
        Alcotest.test_case "div_one"           `Quick test_simplify_div_one;
        Alcotest.test_case "zero_div"          `Quick test_simplify_zero_div;
        Alcotest.test_case "strength_reduce"   `Quick test_simplify_strength_reduce;
        Alcotest.test_case "float_add_zero"    `Quick test_simplify_float_add_zero;
        Alcotest.test_case "bool_and_true"     `Quick test_simplify_bool_and_true;
      ]);
      ("inline", [
        Alcotest.test_case "pure_small"            `Quick test_inline_pure_small;
        Alcotest.test_case "impure_not_inlined"    `Quick test_inline_impure_not_inlined;
        Alcotest.test_case "recursive_not_inlined" `Quick test_inline_recursive_not_inlined;
        Alcotest.test_case "mutual_recursion_not_inlined" `Quick test_inline_mutual_recursion_not_inlined;
      ]);
      ("dce", [
        Alcotest.test_case "dead_pure_let"       `Quick test_dce_dead_pure_let;
        Alcotest.test_case "impure_let_kept"     `Quick test_dce_impure_let_kept;
        Alcotest.test_case "used_let_kept"       `Quick test_dce_used_let_kept;
        Alcotest.test_case "unreachable_top_fn"  `Quick test_dce_unreachable_top_fn;
      ]);
    ]
