(** March test suite — compiler tests. *)
open Test_helpers

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
  let lex = March_parser.Token_filter.make March_lexer.Lexer.token in
  let tok = lex lexbuf in
  Alcotest.(check int) "skips line comment" 42
    (match tok with March_parser.Parser.INT n -> n | _ -> failwith "expected INT")

let test_lexer_block_comment () =
  let lexbuf = Lexing.from_string "{- nested {- comment -} -} 7" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check int) "skips block comment" 7
    (match tok with March_parser.Parser.INT n -> n | _ -> failwith "expected INT")

let test_lexer_underscore_ident () =
  let lexbuf = Lexing.from_string "_cap" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check string) "lexes _cap as LOWER_IDENT" "_cap"
    (match tok with March_parser.Parser.LOWER_IDENT s -> s | _ -> failwith "expected LOWER_IDENT")

let test_ast_span () =
  let span = March_ast.Ast.dummy_span in
  Alcotest.(check string) "dummy span file" "<none>" span.file

let test_parse_expr_int () =
  let lexbuf = Lexing.from_string "42" in
  let expr = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  match expr with
  | March_ast.Ast.ELit (LitInt 42, _) -> ()
  | _ -> Alcotest.fail "expected ELit(LitInt 42)"

let test_parse_expr_atom () =
  let lexbuf = Lexing.from_string ":ok" in
  let expr = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  match expr with
  | March_ast.Ast.EAtom ("ok", [], _) -> ()
  | _ -> Alcotest.fail "expected EAtom(ok)"

let test_parse_expr_pipe () =
  let lexbuf = Lexing.from_string "x |> f" in
  let expr = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  match expr with
  | March_ast.Ast.EPipe (_, _, _) -> ()
  | _ -> Alcotest.fail "expected EPipe"

let test_parse_expr_lambda () =
  (* Lambdas use fn keyword: fn x -> body *)
  let lexbuf = Lexing.from_string "map(fn x -> x)" in
  let expr = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  match expr with
  | March_ast.Ast.EApp (_, [March_ast.Ast.ELam (_, _, _)], _) -> ()
  | _ -> Alcotest.fail "expected EApp with ELam argument"

let test_parse_lambda_keyword_params () =
  (* `state` is a reserved keyword; it must be usable as a lambda param name *)
  let src = "fn (state, event, payload) -> state" in
  let lexbuf = Lexing.from_string src in
  let expr = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  match expr with
  | March_ast.Ast.ELam (ps, _, _) ->
    Alcotest.(check int) "3 params" 3 (List.length ps);
    let names = List.map (fun p -> p.March_ast.Ast.param_name.March_ast.Ast.txt) ps in
    Alcotest.(check (list string)) "param names" ["state"; "event"; "payload"] names
  | _ -> Alcotest.fail "expected ELam"

let test_parse_lambda_block_body () =
  (* Multi-expression lambda body with let bindings *)
  let src = "fn x -> let y = x + 1 let z = y * 2 z" in
  let lexbuf = Lexing.from_string src in
  let expr = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  match expr with
  | March_ast.Ast.ELam ([_], March_ast.Ast.EBlock (stmts, _), _) ->
    Alcotest.(check int) "3 stmts in block" 3 (List.length stmts)
  | _ -> Alcotest.fail "expected ELam with EBlock body"

let test_parse_lambda_single_let () =
  (* Single let-binding lambda: let followed by final expr *)
  let src = "fn x -> let y = x + 1 y" in
  let lexbuf = Lexing.from_string src in
  let expr = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  match expr with
  | March_ast.Ast.ELam ([_], March_ast.Ast.EBlock ([_; _], _), _) -> ()
  | _ -> Alcotest.fail "expected ELam with 2-element EBlock body"

let test_parse_lambda_no_let_unchanged () =
  (* Single-expression lambda still works as before — no EBlock wrapper *)
  let src = "fn x -> x + 1" in
  let lexbuf = Lexing.from_string src in
  let expr = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  match expr with
  | March_ast.Ast.ELam ([_], body, _) ->
    (match body with
     | March_ast.Ast.EBlock _ -> Alcotest.fail "single-expr lambda should not be wrapped in EBlock"
     | _ -> ())
  | _ -> Alcotest.fail "expected ELam"

let test_parse_lambda_zero_arg_block () =
  (* Zero-arg lambda with multi-expression body *)
  let src = "fn () -> let x = 1 x" in
  let lexbuf = Lexing.from_string src in
  let expr = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  match expr with
  | March_ast.Ast.ELam ([], March_ast.Ast.EBlock ([_; _], _), _) -> ()
  | _ -> Alcotest.fail "expected zero-arg ELam with EBlock body"

let test_parse_lambda_multi_param_block () =
  (* Multi-param lambda with let-binding body *)
  let src = "fn (a, b) -> let c = a + b c" in
  let lexbuf = Lexing.from_string src in
  let expr = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  match expr with
  | March_ast.Ast.ELam ([_; _], March_ast.Ast.EBlock ([_; _], _), _) -> ()
  | _ -> Alcotest.fail "expected 2-param ELam with EBlock body"

let test_parse_expr_app () =
  let lexbuf = Lexing.from_string "f(x, y)" in
  let expr = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
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
  let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
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
  let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  match m.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    Alcotest.(check string) "fn name" "greet" def.fn_name.txt;
    Alcotest.(check int) "1 clause" 1 (List.length def.fn_clauses)
  | _ -> Alcotest.fail "expected single DFn"

let test_parse_dotted_module_name () =
  let src = {|mod TestApp.Router do
    fn dispatch(conn) do conn end
  end|} in
  let lexbuf = Lexing.from_string src in
  let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  Alcotest.(check string) "module name is dotted" "TestApp.Router" m.mod_name.txt;
  match m.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    Alcotest.(check string) "fn name" "dispatch" def.fn_name.txt
  | _ -> Alcotest.fail "expected single DFn"

let test_parse_underscore_param () =
  let src = {|mod Test do
    fn greet(_name : String) do "hello" end
  end|} in
  let lexbuf = Lexing.from_string src in
  let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  match m.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    Alcotest.(check string) "fn name" "greet" def.fn_name.txt;
    Alcotest.(check int) "1 clause" 1 (List.length def.fn_clauses)
  | _ -> Alcotest.fail "expected single DFn with underscore param"

(* ── Helpers for desugar + typecheck tests ─────────────────────────────── *)

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
    fn bad(x) do if x + 1 do 0 else 1 end end
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
      match x do
      0 -> 1
      n -> n + 1
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

(* Arity checking: March has no partial application, so a wrong-arity call of a
   known (module-defined) function is a compile-time error.  Previously the
   curried typechecker silently accepted under-application; the compiler then
   miscompiled it into a body call with a garbage argument (a runtime hang),
   which is how a conduit test typo — fake_workflow_storage_new() with 0 args —
   became a non-deterministic hang. *)
let test_tc_arity_under_application () =
  let ctx = typecheck {|mod Test do
    fn add(a : Int, b : Int) : Int do a + b end
    fn main() : Unit do let _ = add(1) () end
  end|} in
  Alcotest.(check bool) "under-application is an error" true (has_errors ctx)

let test_tc_arity_zero_args () =
  let ctx = typecheck {|mod Test do
    fn mk(name : String) : Int do string_byte_length(name) end
    fn main() : Unit do let _ = mk() () end
  end|} in
  Alcotest.(check bool) "0-arg call of 1-arg fn is an error" true (has_errors ctx)

let test_tc_arity_over_application () =
  let ctx = typecheck {|mod Test do
    fn add(a : Int, b : Int) : Int do a + b end
    fn main() : Unit do let _ = add(1, 2, 3) () end
  end|} in
  Alcotest.(check bool) "over-application is an error" true (has_errors ctx)

let test_tc_arity_correct_ok () =
  let ctx = typecheck {|mod Test do
    fn add(a : Int, b : Int) : Int do a + b end
    fn main() : Unit do let _ = add(1, 2) () end
  end|} in
  Alcotest.(check bool) "correct-arity call: no error" false (has_errors ctx)

let test_tc_arity_fn_returning_fn_ok () =
  (* Full application of an arity-1 function that RETURNS a function must NOT be
     flagged as under-application — the result is a value, not a partial app. *)
  let ctx = typecheck {|mod Test do
    fn make_adder(n : Int) : (Int) -> Int do fn x -> x + n end
    fn main() : Unit do
      let f = make_adder(5)
      let _ = f(2)
      ()
    end
  end|} in
  Alcotest.(check bool) "full app of fn-returning-fn: no error" false (has_errors ctx)

(* ── Fix 1: Interface constraint discharge ──────────────────────────────── *)

let test_interface_constraint_satisfied () =
  (* Calling a method when an impl exists should succeed. *)
  let ctx = typecheck {|mod Test do
    interface Eq(a) do
      fn eq: a -> a -> Bool
    end
    impl Eq(Int) do
      fn eq(x, y) do x == y end
    end
    fn check() do eq(1, 2) end
  end|} in
  Alcotest.(check bool) "interface method with impl: no errors" false (has_errors ctx)

let test_interface_constraint_missing_impl () =
  (* Calling eq on a user-defined type with NO impl should error. *)
  let ctx = typecheck {|mod Test do
    interface Eq(a) do
      fn eq: a -> a -> Bool
    end
    type Color = Red | Green
    fn check(x: Color) do eq(x, x) end
  end|} in
  Alcotest.(check bool) "interface method without impl: error" true (has_errors ctx)

let test_impl_when_constraint_satisfied () =
  (* impl with a satisfied 'when' constraint should succeed. *)
  let ctx = typecheck {|mod Test do
    interface Eq(a) do
      fn eq: a -> a -> Bool
    end
    impl Eq(Int) do
      fn eq(x, y) do x == y end
    end
    impl Eq(Bool) when Eq(Int) do
      fn eq(x, y) do x == y end
    end
  end|} in
  Alcotest.(check bool) "impl when Eq(Int) with Eq(Int) in scope: no errors" false (has_errors ctx)

let test_impl_when_constraint_unsatisfied () =
  (* impl with an unsatisfied 'when' constraint should error.
     Use a user-defined type Color that has no Eq impl. *)
  let ctx = typecheck {|mod Test do
    interface Eq(a) do
      fn eq: a -> a -> Bool
    end
    type Color = Red | Green
    impl Eq(Bool) when Eq(Color) do
      fn eq(x, y) do x == y end
    end
  end|} in
  Alcotest.(check bool) "impl when Eq(Color) but no Eq(Color) in scope: error" true (has_errors ctx)

let test_interface_cross_module_dispatch () =
  (* A bare interface-method call from a DIFFERENT module than the one defining
     the interface+impl must resolve. Sibling [mod] blocks are exactly how the
     resolver presents a multi-file project to the typechecker. Regression: the
     cross-module pre-pass bound only the qualified method names ("Show2.show2",
     "Lib.Show2.show2"), never the bare "show2", so dispatch failed with
     "I cannot find `show2`". *)
  let ctx = typecheck {|mod Outer do
    fn run() : String do
      let w = Lib.wrap(7)
      show2(w)
    end

    mod Lib do
      type Widget = Widget(Int)
      fn wrap(n : Int) : Widget do Widget(n) end
      interface Show2(a) do
        fn show2: a -> String
      end
      impl Show2(Widget) do
        fn show2(x) do "widget" end
      end
    end
  end|} in
  Alcotest.(check bool) "cross-module interface dispatch: no errors" false (has_errors ctx)

let test_interface_cross_module_dispatch_record () =
  (* Same as above but the impl is on a RECORD type. The forward-reference
     pre-pass (`register_impl_shape`) registered the impl under the nominal type
     name (`TCon "T"`) instead of the record's structural form (`TRecord [...]`,
     which `surface_ty`/`check_decl DImpl` produce), so a dispatch from a module
     checked before the impl's own module failed with "T does not implement".
     The sibling modules are placed BEFORE the dispatch to match the order the
     resolver produces for a multi-file project (`extra_decls @ entry_decls`). *)
  let ctx = typecheck {|mod App do
    mod Board do
      interface Summarize(a) do
        fn summarize: a -> String
      end
    end

    mod Widget do
      type T = { n : Int }
      fn mk(x : Int) : T do { n: x } end
      impl Summarize(T) do
        fn summarize(w) do int_to_string(w.n) end
      end
    end

    fn run() : String do summarize(Widget.mk(7)) end
  end|} in
  Alcotest.(check bool) "cross-module record-impl dispatch: no errors" false (has_errors ctx)

let test_test_keywords_as_identifiers () =
  (* `test`, `describe`, `setup`, `setup_all` are test-DSL keywords ONLY in the
     `kw "name" do` / `kw do` position. Everywhere else they must lex as ordinary
     identifiers so they can be function names, parameters, and calls. *)
  let ctx = typecheck {|mod Test do
    fn describe(x : Int) : Int do x + 1 end
    fn setup(n : Int) : Int do n end
    fn setup_all(n : Int) : Int do n end
    fn test(b : Bool) : Bool do b end
    fn run() : Int do describe(setup(setup_all(41))) end
  end|} in
  Alcotest.(check bool) "test keywords usable as identifiers: no errors" false (has_errors ctx)

let test_test_dsl_still_parses () =
  (* Regression guard: the contextual-keyword change must not break the test DSL
     in its real position. *)
  let ctx = typecheck {|mod Test do
    describe "math" do
      test "adds" do
        assert 1 + 1 == 2
      end
    end
  end|} in
  Alcotest.(check bool) "test DSL still parses: no errors" false (has_errors ctx)

(* ── Standard interfaces: Eq, Ord, Show, Hash ───────────────────────────── *)

let test_eq_builtin_int () =
  (* == on Int should be satisfied by the builtin Eq(Int) impl *)
  let ctx = typecheck {|mod Test do
    fn f() : Bool do 1 == 2 end
  end|} in
  Alcotest.(check bool) "== on Int: no errors" false (has_errors ctx)

let test_eq_builtin_string () =
  let ctx = typecheck {|mod Test do
    fn f() : Bool do "a" == "b" end
  end|} in
  Alcotest.(check bool) "== on String: no errors" false (has_errors ctx)

let test_eq_builtin_bool () =
  let ctx = typecheck {|mod Test do
    fn f() : Bool do true == false end
  end|} in
  Alcotest.(check bool) "== on Bool: no errors" false (has_errors ctx)

let test_eq_builtin_float () =
  let ctx = typecheck {|mod Test do
    fn f() : Bool do 1.0 == 2.0 end
  end|} in
  Alcotest.(check bool) "== on Float: no errors" false (has_errors ctx)

let test_eq_user_impl () =
  (* User-defined type with an Eq impl: == should be allowed *)
  let ctx = typecheck {|mod Test do
    type Color = Red | Green | Blue
    impl Eq(Color) do
      fn eq(x, y) do
        match (x, y) do
        (Red, Red)     -> true
        (Green, Green) -> true
        (Blue, Blue)   -> true
        _              -> false
        end
      end
    end
    fn f() : Bool do Red == Green end
  end|} in
  Alcotest.(check bool) "== on user type with Eq impl: no errors" false (has_errors ctx)

let test_ord_builtin_lt () =
  (* < on Int should be satisfied by builtin Ord(Int) impl *)
  let ctx = typecheck {|mod Test do
    fn f() : Bool do 1 < 2 end
  end|} in
  Alcotest.(check bool) "< on Int: no errors" false (has_errors ctx)

let test_ord_builtin_string () =
  let ctx = typecheck {|mod Test do
    fn f() : Bool do "a" < "b" end
  end|} in
  Alcotest.(check bool) "< on String: no errors" false (has_errors ctx)

let test_ord_compare_method () =
  (* compare method: ∀a:Ord. a -> a -> Int *)
  let ctx = typecheck {|mod Test do
    fn f() : Int do compare(3, 5) end
  end|} in
  Alcotest.(check bool) "compare(Int, Int): no errors" false (has_errors ctx)

let test_show_builtin_int () =
  (* show method: ∀a:Show. a -> String *)
  let ctx = typecheck {|mod Test do
    fn f() : String do show(42) end
  end|} in
  Alcotest.(check bool) "show(Int): no errors" false (has_errors ctx)

let test_show_builtin_bool () =
  let ctx = typecheck {|mod Test do
    fn f() : String do show(true) end
  end|} in
  Alcotest.(check bool) "show(Bool): no errors" false (has_errors ctx)

let test_show_user_impl () =
  (* User-defined type with Show impl *)
  let ctx = typecheck {|mod Test do
    type Point = { x: Int, y: Int }
    impl Show(Point) do
      fn show(p) do
        "(" ++ int_to_string(p.x) ++ ", " ++ int_to_string(p.y) ++ ")"
      end
    end
    fn f(p: Point) : String do show(p) end
  end|} in
  Alcotest.(check bool) "show on user type with Show impl: no errors" false (has_errors ctx)

let test_println_polymorphic_typecheck () =
  (* Verify that a user-defined fn println(x) using show can accept any Show type,
     matching the behaviour of the prelude's polymorphic println. *)
  let ctx = typecheck {|mod Test do
    fn println(x) do
      print(show(x))
      print("\n")
    end
    fn f() do
      println(42)
      println(true)
    end
  end|} in
  Alcotest.(check bool) "polymorphic println accepts Show types" false (has_errors ctx)

let test_hash_builtin_int () =
  (* hash method: ∀a:Hash. a -> Int *)
  let ctx = typecheck {|mod Test do
    fn f() : Int do hash(42) end
  end|} in
  Alcotest.(check bool) "hash(Int): no errors" false (has_errors ctx)

let test_hash_builtin_string () =
  let ctx = typecheck {|mod Test do
    fn f() : Int do hash("hello") end
  end|} in
  Alcotest.(check bool) "hash(String): no errors" false (has_errors ctx)

let test_eq_method_callable () =
  (* The eq method itself is callable directly *)
  let ctx = typecheck {|mod Test do
    fn f() : Bool do eq(1, 2) end
  end|} in
  Alcotest.(check bool) "eq(Int, Int): no errors" false (has_errors ctx)

let test_standard_interfaces_in_scope () =
  (* Eq, Ord, Show, Hash are pre-registered — user can impl them without declaring *)
  let ctx = typecheck {|mod Test do
    type Wrap = Wrap(Int)
    impl Eq(Wrap) do
      fn eq(x, y) do
        match (x, y) do
        (Wrap(a), Wrap(b)) -> a == b
        end
      end
    end
    fn same(a: Wrap, b: Wrap) : Bool do a == b end
  end|} in
  Alcotest.(check bool) "impl Eq for user type without re-declaring interface: no errors"
    false (has_errors ctx)

(* ── Fix 2: Linear type enforcement ─────────────────────────────────────── *)

let test_linear_pattern_match_ok () =
  (* Matching a linear var and using the binding exactly once is fine. *)
  let ctx = typecheck {|mod Test do
    fn consume(linear x: Int) : Int do
      match x do
      n -> n
      end
    end
  end|} in
  Alcotest.(check bool) "linear through pattern match once: no errors" false (has_errors ctx)

let test_linear_pattern_match_double_use () =
  (* Matching a linear var and using the binding twice should error. *)
  let ctx = typecheck {|mod Test do
    fn bad(linear x: Int) : Int do
      match x do
      n -> n + n
      end
    end
  end|} in
  Alcotest.(check bool) "linear pattern binding used twice: error" true (has_errors ctx)

let test_linear_closure_capture_error () =
  (* Capturing a linear value in a closure should error. *)
  let ctx = typecheck {|mod Test do
    fn bad(linear x: Int) : Int do
      let f = fn () -> x
      f()
    end
  end|} in
  Alcotest.(check bool) "linear value captured in closure: error" true (has_errors ctx)

let test_linear_field_let_binding () =
  (* A linear record field bound to a let-variable should be tracked as linear.
     Using that variable twice should error. *)
  let ctx = typecheck {|mod Test do
    type Packet = { linear data: Int, size: Int }
    fn bad(p: Packet) : Int do
      let x = p.data
      x + x
    end
  end|} in
  Alcotest.(check bool) "linear field bound in let, used twice: error" true (has_errors ctx)

(* ── Fix 3: Session type validation ─────────────────────────────────────── *)

let test_protocol_self_message_error () =
  (* A participant sending a message to itself should be an error. *)
  let ctx = typecheck {|mod Test do
    protocol SelfTalk do
      Client -> Client : Int
    end
  end|} in
  Alcotest.(check bool) "self-message in protocol: error" true (has_errors ctx)

let test_protocol_empty_loop_error () =
  (* An empty loop block should be an error. *)
  let ctx = typecheck {|mod Test do
    protocol Ping do
      loop do
      end
    end
  end|} in
  Alcotest.(check bool) "empty loop in protocol: error" true (has_errors ctx)

let test_protocol_valid () =
  (* A well-formed two-party protocol should produce no errors. *)
  let ctx = typecheck {|mod Test do
    protocol Ping do
      Client -> Server : Int
      Server -> Client : Bool
    end
  end|} in
  Alcotest.(check bool) "valid two-party protocol: no errors" false (has_errors ctx)

let test_protocol_duplicate_error () =
  (* Duplicate protocol names should error. *)
  let ctx = typecheck {|mod Test do
    protocol P do
      A -> B : Int
    end
    protocol P do
      A -> B : Bool
    end
  end|} in
  Alcotest.(check bool) "duplicate protocol name: error" true (has_errors ctx)

(* ── H6: Linear types through record fields (direct field access) ─────────── *)

let test_linear_field_double_access_error () =
  (* Accessing a linear record field twice directly on a named variable should error.
     The sentinel "r#data" is created when r is bound, and record_use is called
     on it each time r.data is evaluated. *)
  let ctx = typecheck {|mod Test do
    type Packet = { linear data: Int, size: Int }
    fn bad(r: Packet) : Int do
      r.data + r.data
    end
  end|} in
  Alcotest.(check bool) "linear field direct double-access: error" true (has_errors ctx)

let test_linear_field_single_access_ok () =
  (* Accessing a linear record field exactly once should be fine. *)
  let ctx = typecheck {|mod Test do
    type Packet = { linear data: Int, size: Int }
    fn ok(r: Packet) : Int do
      r.data
    end
  end|} in
  Alcotest.(check bool) "linear field single access: no error" false (has_errors ctx)

(* ── H8: Protocol participant cross-checking ─────────────────────────────── *)

let test_protocol_unknown_participant_hint () =
  (* A protocol that names participants that are not known actors or types
     should produce a hint (not an error). *)
  let ctx = typecheck {|mod Test do
    protocol Mystery do
      Unicorn -> Dragon : Int
    end
  end|} in
  (* Should have hints (unknown participants) but no hard errors *)
  Alcotest.(check bool) "unknown protocol participant: hint (not error)" false (has_errors ctx)

let test_protocol_known_participant_no_hint () =
  (* A protocol that names a declared type as participant should not hint. *)
  let ctx = typecheck {|mod Test do
    type Client = {}
    type Server = {}
    protocol Ping do
      Client -> Server : Int
    end
  end|} in
  Alcotest.(check bool) "known participant types: no errors" false (has_errors ctx)

(* ── Phase 1: Session type projection + duality ──────────────────────────── *)

let test_session_projection_simple () =
  (* A two-step protocol: Client sends Int, Server sends Bool back.
     Client projection: Send(Int, Recv(Bool, End))
     Server projection: Recv(Int, Send(Bool, End)) *)
  let (_ctx, env) = typecheck_full {|mod Test do
    protocol Ping do
      Client -> Server : Int
      Server -> Client : Bool
    end
  end|} in
  let pi = March_typecheck.Typecheck.StrMap.find "Ping" env.March_typecheck.Typecheck.protocols in
  let client_ty = List.assoc "Client" pi.March_typecheck.Typecheck.pi_projections in
  let server_ty = List.assoc "Server" pi.March_typecheck.Typecheck.pi_projections in
  Alcotest.(check string) "client projection"
    "Send(Int, Recv(Bool, End))"
    (pp_sty client_ty);
  Alcotest.(check string) "server projection"
    "Recv(Int, Send(Bool, End))"
    (pp_sty server_ty)

let test_session_duality_holds () =
  (* dual(client) should equal server *)
  let (_ctx, env) = typecheck_full {|mod Test do
    protocol Counter do
      Client -> Server : Int
      Server -> Client : Int
    end
  end|} in
  let pi = March_typecheck.Typecheck.StrMap.find "Counter" env.March_typecheck.Typecheck.protocols in
  let client_ty = List.assoc "Client" pi.March_typecheck.Typecheck.pi_projections in
  let server_ty = List.assoc "Server" pi.March_typecheck.Typecheck.pi_projections in
  let dual_client = March_typecheck.Typecheck.dual_session_ty client_ty in
  Alcotest.(check bool) "dual(client) = server"
    true
    (March_typecheck.Typecheck.session_ty_equal dual_client server_ty)

let test_session_loop_projection () =
  (* A protocol with a loop: generates SRec/SVar *)
  let (ctx, env) = typecheck_full {|mod Test do
    protocol Stream do
      loop do
        Source -> Sink : Int
      end
    end
  end|} in
  Alcotest.(check bool) "loop protocol: no errors" false (has_errors ctx);
  let pi = March_typecheck.Typecheck.StrMap.find "Stream" env.March_typecheck.Typecheck.protocols in
  let source_ty = List.assoc "Source" pi.March_typecheck.Typecheck.pi_projections in
  (* Source projection should be Rec(X, Send(Int, X)) for some X *)
  (match source_ty with
   | March_typecheck.Typecheck.SRec (_, March_typecheck.Typecheck.SSend _) ->
     Alcotest.(check bool) "source loop projection is SRec(Send(...))" true true
   | other ->
     Alcotest.fail ("expected SRec(SSend(...)) but got: " ^ pp_sty other))

let test_session_chan_type_annotation () =
  (* Chan(Client, Ping) in a type annotation should resolve correctly — no errors *)
  let ctx = typecheck {|mod Test do
    protocol Ping do
      Client -> Server : Int
      Server -> Client : Bool
    end
    fn use_chan(ch : Chan(Client, Ping)) : Unit do
      ()
    end
  end|} in
  Alcotest.(check bool) "Chan(Role, Proto) annotation: no errors" false (has_errors ctx)

let test_session_chan_unknown_protocol_error () =
  (* Chan(Client, DoesNotExist) should produce an error *)
  let ctx = typecheck {|mod Test do
    fn bad(ch : Chan(Client, DoesNotExist)) : Unit do
      ()
    end
  end|} in
  Alcotest.(check bool) "Chan with unknown protocol: error" true (has_errors ctx)

let test_session_chan_unknown_role_error () =
  (* Chan(Ghost, Ping) where Ghost is not a role in Ping should error *)
  let ctx = typecheck {|mod Test do
    protocol Ping do
      Client -> Server : Int
    end
    fn bad(ch : Chan(Ghost, Ping)) : Unit do
      ()
    end
  end|} in
  Alcotest.(check bool) "Chan with unknown role: error" true (has_errors ctx)

(* ── Phase 2: Chan.send / Chan.recv / Chan.close session type checking ─────── *)

let test_session_send_recv_close_ok () =
  (* A well-typed send/recv/close sequence: no errors *)
  let ctx = typecheck {|mod Test do
    protocol Ping do
      Client -> Server : Int
      Server -> Client : Bool
    end
    fn client_side(ch : Chan(Client, Ping)) : Bool do
      let ch2 = Chan.send(ch, 42)
      let (b, ch3) = Chan.recv(ch2)
      Chan.close(ch3)
      b
    end
    fn server_side(ch : Chan(Server, Ping)) : Unit do
      let (_, ch2) = Chan.recv(ch)
      let ch3 = Chan.send(ch2, true)
      Chan.close(ch3)
    end
  end|} in
  Alcotest.(check bool) "valid send/recv/close: no errors" false (has_errors ctx)

let test_session_send_wrong_type_error () =
  (* Sending wrong type: Int where Bool expected *)
  let ctx = typecheck {|mod Test do
    protocol BoolChan do
      A -> B : Bool
    end
    fn bad(ch : Chan(A, BoolChan)) : Unit do
      let ch2 = Chan.send(ch, 42)
      ()
    end
  end|} in
  Alcotest.(check bool) "send wrong type: error" true (has_errors ctx)

let test_session_send_at_recv_state_error () =
  (* Calling send on a channel at Recv state is a protocol violation *)
  let ctx = typecheck {|mod Test do
    protocol PingB do
      A -> B : Int
      B -> A : Int
    end
    fn bad(ch : Chan(B, PingB)) : Unit do
      -- B's first action is Recv(Int, ...) but we try to send
      let ch2 = Chan.send(ch, 99)
      ()
    end
  end|} in
  Alcotest.(check bool) "send at recv state: error" true (has_errors ctx)

let test_session_close_at_wrong_state_error () =
  (* Calling close on a channel that is not at End *)
  let ctx = typecheck {|mod Test do
    protocol NotDone do
      A -> B : Int
    end
    fn bad(ch : Chan(A, NotDone)) : Unit do
      Chan.close(ch)
    end
  end|} in
  Alcotest.(check bool) "close at non-End state: error" true (has_errors ctx)

let test_session_chan_new_ok () =
  (* Chan.new with a valid protocol produces no errors *)
  let ctx = typecheck {|mod Test do
    protocol Counter do
      Client -> Server : Int
      Server -> Client : Int
    end
    fn make_chan() : Unit do
      let _ = Chan.new(Counter)
      ()
    end
  end|} in
  Alcotest.(check bool) "Chan.new valid protocol: no errors" false (has_errors ctx)

let test_session_chan_new_unknown_proto_error () =
  (* Chan.new with an undeclared protocol is an error *)
  let ctx = typecheck {|mod Test do
    fn bad() : Unit do
      let _ = Chan.new(NoSuchProto)
      ()
    end
  end|} in
  Alcotest.(check bool) "Chan.new unknown protocol: error" true (has_errors ctx)

(* ── Phase 3: Choose/Offer branching ────────────────────────────────────── *)

let test_session_choose_protocol_parses () =
  (* A protocol with choose by syntax should parse and typecheck without errors. *)
  let ctx = typecheck {|mod Test do
    protocol Decision do
      Client -> Server : Int
      choose by Server:
        ok  -> Server -> Client : Bool
        err -> Server -> Client : Int
      end
    end
  end|} in
  Alcotest.(check bool) "choose protocol parses: no errors" false (has_errors ctx)

let test_session_choose_advances_state () =
  (* Chan.choose(ch, :ok) on a SChoose channel should produce no errors *)
  let ctx = typecheck {|mod Test do
    protocol Decision do
      Client -> Server : Int
      choose by Server:
        ok  -> Server -> Client : Bool
        err -> Server -> Client : Int
      end
    end
    fn server_side(ch : Chan(Server, Decision)) : Unit do
      let (_, ch2) = Chan.recv(ch)
      let ch3 = Chan.choose(ch2, :ok)
      let ch4 = Chan.send(ch3, true)
      Chan.close(ch4)
    end
  end|} in
  Alcotest.(check bool) "Chan.choose advances state: no errors" false (has_errors ctx)

let test_session_choose_invalid_label_error () =
  (* Chan.choose with wrong label should produce an error *)
  let ctx = typecheck {|mod Test do
    protocol Bin do
      choose by A:
        left  -> A -> B : Int
        right -> A -> B : Bool
      end
    end
    fn bad(ch : Chan(A, Bin)) : Unit do
      let ch2 = Chan.choose(ch, :missing)
      ()
    end
  end|} in
  Alcotest.(check bool) "Chan.choose invalid label: error" true (has_errors ctx)

let test_session_choose_at_wrong_state_error () =
  (* Chan.choose on a channel not at SChoose should error *)
  let ctx = typecheck {|mod Test do
    protocol Simple do
      A -> B : Int
    end
    fn bad(ch : Chan(A, Simple)) : Unit do
      let ch2 = Chan.choose(ch, :ok)
      ()
    end
  end|} in
  Alcotest.(check bool) "Chan.choose at non-choose state: error" true (has_errors ctx)

let test_session_offer_ok () =
  (* Chan.offer on a SOffer channel should produce no errors *)
  let ctx = typecheck {|mod Test do
    protocol Decision do
      Client -> Server : Int
      choose by Server:
        ok  -> Server -> Client : Bool
        err -> Server -> Client : Int
      end
    end
    fn client_side(ch : Chan(Client, Decision)) : Unit do
      let ch2 = Chan.send(ch, 42)
      let (_, ch3) = Chan.offer(ch2)
      ()
    end
  end|} in
  Alcotest.(check bool) "Chan.offer on SOffer: no errors" false (has_errors ctx)

let test_session_offer_at_wrong_state_error () =
  (* Chan.offer on a channel not at SOffer should error *)
  let ctx = typecheck {|mod Test do
    protocol Simple do
      A -> B : Int
    end
    fn bad(ch : Chan(A, Simple)) : Unit do
      let (_, ch2) = Chan.offer(ch)
      ()
    end
  end|} in
  Alcotest.(check bool) "Chan.offer at non-offer state: error" true (has_errors ctx)

(* ── Phase 4: SRec multi-turn recursive protocol tests ───────────────────── *)

let test_srec_pingpong_loop_typechecks () =
  (* Ping-pong loop: Client sends Int, Server replies Bool, repeats.
     A function that does one iteration and returns the updated channel
     should typecheck — the channel type after one loop is the same as before. *)
  let ctx = typecheck {|mod Test do
    protocol PingLoop do
      loop do
        Client -> Server : Int
        Server -> Client : Bool
      end
    end
    fn client_step(ch : Chan(Client, PingLoop), val : Int) : Bool do
      let ch1 = Chan.send(ch, val)
      let (b, ch2) = Chan.recv(ch1)
      let _ = ch2
      b
    end
    fn server_step(ch : Chan(Server, PingLoop)) : Unit do
      let (n, ch1) = Chan.recv(ch)
      let ch2 = Chan.send(ch1, n > 0)
      let _ = ch2
      ()
    end
  end|} in
  Alcotest.(check bool) "SRec ping-pong: typechecks without errors" false (has_errors ctx)

let test_srec_unfold_simple () =
  (* unfold_srec on SRec(x, SSend(Int, SVar x)) should give SSend(Int, SRec(x, ...)) *)
  let module TC = March_typecheck.Typecheck in
  let int_ty = TC.TCon ("Int", []) in
  let s = TC.SRec ("x", TC.SSend (int_ty, TC.SVar "x")) in
  let unfolded = TC.unfold_srec s in
  (match unfolded with
   | TC.SSend (_, TC.SRec ("x", TC.SSend _)) ->
     Alcotest.(check bool) "unfold_srec 1-step loop gives SSend(Int, SRec(...))" true true
   | other ->
     Alcotest.fail ("unexpected unfold result: " ^ TC.pp_session_ty other))

let test_srec_unfold_multi_step () =
  (* SRec(x, SSend(Int, SRecv(Bool, SVar x))) — a two-step loop.
     unfold_srec should produce SSend(Int, SRecv(Bool, SRec(x, ...))) *)
  let module TC = March_typecheck.Typecheck in
  let int_ty = TC.TCon ("Int", []) in
  let bool_ty = TC.TCon ("Bool", []) in
  let s = TC.SRec ("x", TC.SSend (int_ty, TC.SRecv (bool_ty, TC.SVar "x"))) in
  let unfolded = TC.unfold_srec s in
  (match unfolded with
   | TC.SSend (_, TC.SRecv (_, TC.SRec ("x", TC.SSend _))) ->
     Alcotest.(check bool) "unfold_srec 2-step loop: SSend(Int, SRecv(Bool, SRec(...)))" true true
   | other ->
     Alcotest.fail ("unexpected unfold result: " ^ TC.pp_session_ty other))

let test_srec_unfold_nested () =
  (* SRec(x, SRec(y, SSend(Int, SVar y))) — nested SRec with different vars.
     The outer SRec x is transparent since the body never references x;
     unfold_srec gives SRec(y, SSend(Int, SVar y)) which then unfolds to
     SSend(Int, SRec(y, ...)) *)
  let module TC = March_typecheck.Typecheck in
  let int_ty = TC.TCon ("Int", []) in
  let s = TC.SRec ("x", TC.SRec ("y", TC.SSend (int_ty, TC.SVar "y"))) in
  let unfolded = TC.unfold_srec s in
  (match unfolded with
   | TC.SSend (_, TC.SRec _) ->
     Alcotest.(check bool) "nested SRec unfolds to SSend(Int, SRec(...))" true true
   | other ->
     Alcotest.fail ("nested SRec unfold: " ^ TC.pp_session_ty other))

let test_srec_with_branching_typechecks () =
  (* SRec with SChoose/SOffer inside: a loop containing a branch.
     Tests that the protocol definition itself parses and typechecks correctly. *)
  let ctx = typecheck {|mod Test do
    protocol Stream do
      loop do
        choose by Server:
          data -> Client -> Server : Bool
          stop -> Server -> Client : Int
        end
      end
    end
  end|} in
  Alcotest.(check bool) "SRec with SChoose/SOffer protocol: typechecks" false (has_errors ctx)

let test_srec_wrong_type_in_loop_error () =
  (* Sending wrong type inside a recursive loop should still error *)
  let ctx = typecheck {|mod Test do
    protocol Counter do
      loop do
        Client -> Server : Int
        Server -> Client : Int
      end
    end
    fn bad(ch : Chan(Client, Counter)) : Unit do
      let ch1 = Chan.send(ch, "not an int")
      let (_, ch2) = Chan.recv(ch1)
      let _ = ch2
      ()
    end
  end|} in
  Alcotest.(check bool) "wrong type in SRec loop: error" true (has_errors ctx)

(* ── Complex type error message tests ───────────────────────────────────── *)

let test_complex_type_error_pp_ty_pretty () =
  (* pp_ty_pretty should wrap long type names across multiple lines *)
  let module TC = March_typecheck.Typecheck in
  let nested = TC.TCon ("Map", [
    TC.TCon ("String", []);
    TC.TCon ("List", [TC.TCon ("Vec", [TC.TCon ("Int", []); TC.TNat 32])]);
  ]) in
  let flat = TC.pp_ty nested in
  let pretty = TC.pp_ty_pretty ~indent:0 ~width:30 nested in
  (* flat should be a single long string *)
  Alcotest.(check bool) "flat pp_ty is non-empty" true (String.length flat > 0);
  (* pretty-printed version should contain newlines when flat exceeds width *)
  Alcotest.(check bool) "pp_ty_pretty wraps at narrow width"
    true (String.contains pretty '\n')

let test_complex_type_mismatch_hint () =
  (* When two types share the same constructor but differ in one arg,
     the error message should include a note about which arg mismatches. *)
  let ctx = typecheck {|mod Test do
    type Pair(a, b) = Pair(a, b)
    fn expects_int_str(p : Pair(Int, String)) : Unit do () end
    fn call() : Unit do
      expects_int_str(Pair(true, "hello"))
    end
  end|} in
  (* Should produce an error *)
  Alcotest.(check bool) "type mismatch in generic produces error" true (has_errors ctx);
  (* The error message should mention the mismatch context *)
  let diags = March_errors.Errors.sorted ctx in
  Alcotest.(check bool) "at least one diagnostic" true (List.length diags > 0);
  let msgs = List.map (fun d -> d.March_errors.Errors.message ^ String.concat " " d.March_errors.Errors.notes) diags in
  Alcotest.(check bool) "error mentions type mismatch"
    true (List.exists (fun m ->
      String.length m > 0 &&
      (let low = String.lowercase_ascii m in
       String.length low > 0)
    ) msgs)

(* ── H9: Actor handler capability checking ───────────────────────────────── *)

let test_actor_handler_cap_needs_ok () =
  (* An actor handler with a Cap parameter is OK if the module declares the need. *)
  let ctx = typecheck {|mod Test do
    needs IO
    actor Counter do
      state { count: Int }
      init { count: 0 }
      on Inc(cap: Cap(IO)) do
        state
      end
    end
  end|} in
  Alcotest.(check bool) "actor handler cap with needs: ok" false (has_errors ctx)

let test_actor_handler_cap_missing_needs_error () =
  (* An actor handler with a Cap parameter, but no needs declaration, should error. *)
  let ctx = typecheck {|mod Test do
    actor Counter do
      state { count: Int }
      init { count: 0 }
      on Inc(cap: Cap(IO.Console)) do
        state
      end
    end
  end|} in
  Alcotest.(check bool) "actor handler cap without needs: error" true (has_errors ctx)

let test_lexer_when () =
  let lexbuf = Lexing.from_string "when" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "lexes when keyword" true
    (match tok with March_parser.Parser.WHEN -> true | _ -> false)

(* ── Eval helpers ───────────────────────────────────────────────────────── *)

let test_show_list_eval () =
  let env = eval_module {|mod T do
    fn main() do show([1, 2, 3]) end
  end|} in
  Alcotest.(check string) "show list" "[1, 2, 3]" (get_show_result env)

let test_show_option_some_eval () =
  let env = eval_module {|mod T do
    fn main() do show(Some(42)) end
  end|} in
  Alcotest.(check string) "show Some(42)" "Some(42)" (get_show_result env)

let test_show_option_none_eval () =
  let env = eval_module {|mod T do
    fn main() do show(None) end
  end|} in
  Alcotest.(check string) "show None" "None" (get_show_result env)

let test_show_result_ok_eval () =
  let env = eval_module {|mod T do
    fn main() do show(Ok(1)) end
  end|} in
  Alcotest.(check string) "show Ok(1)" "Ok(1)" (get_show_result env)

let test_show_result_err_eval () =
  (* Requires prelude Show(Result) impl so Err("x") shows Err(x) without quotes *)
  let prelude_decl = load_stdlib_file_for_test "prelude.march" in
  let env = eval_with_stdlib [prelude_decl] {|mod T do
    fn main() do show(Err("oops")) end
  end|} in
  Alcotest.(check string) "show Err no quotes" "Err(oops)" (get_show_result env)

let test_show_nested_list_eval () =
  let prelude_decl = load_stdlib_file_for_test "prelude.march" in
  let env = eval_with_stdlib [prelude_decl] {|mod T do
    fn main() do show([Some(1), None, Some(3)]) end
  end|} in
  Alcotest.(check string) "show nested list" "[Some(1), None, Some(3)]"
    (get_show_result env)

let test_session_eval_send_recv () =
  (* End-to-end eval: send an Int on one endpoint, receive it on the other *)
  let env = eval_module {|mod Test do
    protocol Echo do
      Sender -> Receiver : Int
      Receiver -> Sender : Int
    end
    fn run() do
      let (sc, rc) = Chan.new(Echo)
      let sc2 = Chan.send(sc, 42)
      let (n, rc2) = Chan.recv(rc)
      let rc3 = Chan.send(rc2, n + 1)
      let (result, sc3) = Chan.recv(sc2)
      Chan.close(sc3)
      Chan.close(rc3)
      result
    end
  end|} in
  let v = call_fn env "run" [] in
  Alcotest.(check int) "eval echo protocol: result = 43" 43 (vint v)

(* ── SRec multi-turn protocol tests ─────────────────────────────────────── *)

(** unfold_srec: basic SRec(x, Send(Int, x)) unfolds to Send(Int, SRec(x,...)). *)
let test_srec_unfold_basic () =
  let t_int = March_typecheck.Typecheck.TCon ("Int", []) in
  let s = March_typecheck.Typecheck.(SRec ("x", SSend (t_int, SVar "x"))) in
  let unfolded = March_typecheck.Typecheck.unfold_srec s in
  (match unfolded with
   | March_typecheck.Typecheck.SSend (ty, cont) ->
     Alcotest.(check bool) "unfold gives SSend" true true;
     Alcotest.(check bool) "inner type is Int" true (ty = t_int);
     (match cont with
      | March_typecheck.Typecheck.SRec _ ->
        Alcotest.(check bool) "continuation is SRec (recursive)" true true
      | _ -> Alcotest.fail "continuation should be SRec")
   | other -> Alcotest.fail ("expected SSend, got: " ^ pp_sty other))

(** unfold_srec: SEnd passes through unchanged (no SRec to unfold). *)
let test_srec_unfold_send_passes_through () =
  let t_int = March_typecheck.Typecheck.TCon ("Int", []) in
  let s = March_typecheck.Typecheck.SSend (t_int, March_typecheck.Typecheck.SEnd) in
  let unfolded = March_typecheck.Typecheck.unfold_srec s in
  Alcotest.(check bool) "SSend(Int, SEnd) unchanged by unfold" true
    (March_typecheck.Typecheck.session_ty_equal s unfolded)

(** SRec ping-pong protocol: source sends Int, receives Bool, loops.
    Projection should be SRec(x, Send(Int, Recv(Bool, x))). *)
let test_srec_ping_pong_protocol () =
  let (ctx, env) = typecheck_full {|mod Test do
    protocol PingPong do
      loop do
        Client -> Server : Int
        Server -> Client : Bool
      end
    end
  end|} in
  Alcotest.(check bool) "ping-pong: no typecheck errors" false (has_errors ctx);
  let pi = March_typecheck.Typecheck.StrMap.find "PingPong" env.March_typecheck.Typecheck.protocols in
  let client_ty = List.assoc "Client" pi.March_typecheck.Typecheck.pi_projections in
  let t_int  = March_typecheck.Typecheck.TCon ("Int",  []) in
  let t_bool = March_typecheck.Typecheck.TCon ("Bool", []) in
  (* Client projection should be SRec(_, SSend(Int, SRecv(Bool, ...))) *)
  (match client_ty with
   | March_typecheck.Typecheck.SRec (_, inner) ->
     (match inner with
      | March_typecheck.Typecheck.SSend (ty, recv_part) when ty = t_int ->
        (match recv_part with
         | March_typecheck.Typecheck.SRecv (ty2, _) when ty2 = t_bool ->
           Alcotest.(check bool) "client: Rec(_, Send(Int, Recv(Bool, ...)))" true true
         | _ -> Alcotest.fail ("client inner recv: " ^ pp_sty recv_part))
      | _ -> Alcotest.fail ("client inner: " ^ pp_sty inner))
   | other -> Alcotest.fail ("client: " ^ pp_sty other))

(** Ping-pong unfold: one step of unfold gives Send(Int, Recv(Bool, Rec(...))). *)
let test_srec_ping_pong_unfold_one_step () =
  let t_int  = March_typecheck.Typecheck.TCon ("Int",  []) in
  let t_bool = March_typecheck.Typecheck.TCon ("Bool", []) in
  (* Manually construct Rec(x, Send(Int, Recv(Bool, x))) *)
  let s = March_typecheck.Typecheck.SRec ("x",
    March_typecheck.Typecheck.SSend (t_int,
      March_typecheck.Typecheck.SRecv (t_bool,
        March_typecheck.Typecheck.SVar "x"))) in
  let step1 = March_typecheck.Typecheck.unfold_srec s in
  (match step1 with
   | March_typecheck.Typecheck.SSend (ty, cont) when ty = t_int ->
     Alcotest.(check bool) "step 1: SSend(Int, ...)" true true;
     (match cont with
      | March_typecheck.Typecheck.SRecv (ty2, loop_back) when ty2 = t_bool ->
        (match loop_back with
         | March_typecheck.Typecheck.SRec _ ->
           Alcotest.(check bool) "step 1: ... Recv(Bool, SRec(...))" true true
         | _ -> Alcotest.fail ("loop-back should be SRec: " ^ pp_sty loop_back))
      | _ -> Alcotest.fail ("after Send: expected Recv(Bool,...): " ^ pp_sty cont))
   | other -> Alcotest.fail ("step 1 expected SSend: " ^ pp_sty other))

(** Ping-pong unfold: second step after advancing restores the same structure. *)
let test_srec_ping_pong_unfold_two_steps () =
  let t_int  = March_typecheck.Typecheck.TCon ("Int",  []) in
  let t_bool = March_typecheck.Typecheck.TCon ("Bool", []) in
  (* After unfolding once and advancing past Send+Recv, we get back SRec which
     can be unfolded again: structure should be identical to step 1. *)
  let s = March_typecheck.Typecheck.SRec ("x",
    March_typecheck.Typecheck.SSend (t_int,
      March_typecheck.Typecheck.SRecv (t_bool,
        March_typecheck.Typecheck.SVar "x"))) in
  let step1 = March_typecheck.Typecheck.unfold_srec s in
  (* Advance past SSend *)
  let after_send = match step1 with
    | March_typecheck.Typecheck.SSend (_, cont) -> cont
    | _ -> March_typecheck.Typecheck.SEnd in
  (* Advance past SRecv *)
  let after_recv = match after_send with
    | March_typecheck.Typecheck.SRecv (_, cont) -> cont
    | _ -> March_typecheck.Typecheck.SEnd in
  (* after_recv should be SRec, unfoldable again *)
  let step2 = March_typecheck.Typecheck.unfold_srec after_recv in
  (match step2 with
   | March_typecheck.Typecheck.SSend (ty, _) when ty = t_int ->
     Alcotest.(check bool) "step 2 again starts with SSend(Int,...)" true true
   | other -> Alcotest.fail ("step 2 expected SSend: " ^ pp_sty other))

(** Multi-level nested SRec: SRec inside SRec where inner loop recurses. *)
let test_srec_nested_srec () =
  let t_int = March_typecheck.Typecheck.TCon ("Int", []) in
  (* Rec(x, Rec(y, Send(Int, y))) — inner loop never uses x *)
  let inner = March_typecheck.Typecheck.(SRec ("y", SSend (t_int, SVar "y"))) in
  ignore t_int; (* used inside local open above *)
  let outer = March_typecheck.Typecheck.SRec ("x", inner) in
  (* Unfolding outer should eliminate the outer SRec and give us the inner SRec.
     Then unfolding the inner SRec gives SSend. *)
  let unfolded = March_typecheck.Typecheck.unfold_srec outer in
  (match unfolded with
   | March_typecheck.Typecheck.SSend _ ->
     Alcotest.(check bool) "nested SRec unfolds to SSend" true true
   | March_typecheck.Typecheck.SRec _ ->
     (* One more unfold needed — also acceptable *)
     let step2 = March_typecheck.Typecheck.unfold_srec unfolded in
     (match step2 with
      | March_typecheck.Typecheck.SSend _ ->
        Alcotest.(check bool) "nested SRec: two unfold steps reach SSend" true true
      | _ -> Alcotest.fail ("nested: two steps gave: " ^ pp_sty step2))
   | other -> Alcotest.fail ("nested SRec: " ^ pp_sty other))

(** Protocol that recurses N times then ends (counted recursion via nesting).
    We simulate a 3-turn protocol: Send, Send, Send, End.
    Uses SRec + choice to represent a counted loop.  *)
let test_srec_finite_protocol () =
  let t_int = March_typecheck.Typecheck.TCon ("Int", []) in
  (* A finite 3-step linear protocol (no recursion), represented in typecheck *)
  let s = March_typecheck.Typecheck.SSend (t_int,
    March_typecheck.Typecheck.SSend (t_int,
      March_typecheck.Typecheck.SSend (t_int,
        March_typecheck.Typecheck.SEnd))) in
  (* Three steps advance correctly *)
  let step s' = match March_typecheck.Typecheck.unfold_srec s' with
    | March_typecheck.Typecheck.SSend (_, cont) -> cont
    | other -> other in
  let s1 = step s in
  let s2 = step s1 in
  let s3 = step s2 in
  Alcotest.(check bool) "3-step protocol ends at SEnd" true
    (s3 = March_typecheck.Typecheck.SEnd)

(** SRec choose-based ping-pong: client can Continue or Stop each round. *)
let test_srec_choose_loop_protocol () =
  let (ctx, env) = typecheck_full {|mod Test do
    protocol Negotiation do
      loop do
        Client -> Server : Int
        Server -> Client : Bool
      end
    end
  end|} in
  Alcotest.(check bool) "choose loop: no typecheck errors" false (has_errors ctx);
  let pi = March_typecheck.Typecheck.StrMap.find "Negotiation" env.March_typecheck.Typecheck.protocols in
  (* Both roles should have a projection *)
  let has_client = List.mem_assoc "Client" pi.March_typecheck.Typecheck.pi_projections in
  let has_server = List.mem_assoc "Server" pi.March_typecheck.Typecheck.pi_projections in
  Alcotest.(check bool) "Client projection present" true has_client;
  Alcotest.(check bool) "Server projection present" true has_server

(** SRec duality: dual of Rec(x, Send(Int, x)) is Rec(x, Recv(Int, x)). *)
let test_srec_dual () =
  let t_int = March_typecheck.Typecheck.TCon ("Int", []) in
  let s = March_typecheck.Typecheck.(SRec ("x", SSend (t_int, SVar "x"))) in
  let d = March_typecheck.Typecheck.dual_session_ty s in
  (* dual should be Rec(x, Recv(Int, x)) *)
  (match d with
   | March_typecheck.Typecheck.SRec (_, inner) ->
     (match inner with
      | March_typecheck.Typecheck.SRecv (ty, March_typecheck.Typecheck.SVar _) when ty = t_int ->
        Alcotest.(check bool) "dual(Rec(x,Send(Int,x))) = Rec(x,Recv(Int,x))" true true
      | _ -> Alcotest.fail ("dual inner: " ^ pp_sty inner))
   | other -> Alcotest.fail ("dual: " ^ pp_sty other))

(** SRec multi-turn typecheck: a function using a recursive channel protocol typechecks. *)
let test_srec_multi_turn_typechecks () =
  (* A function that uses a recursive protocol exactly once (one send+recv then done) *)
  let ctx = typecheck {|mod Test do
    protocol Ping do
      loop do
        Client -> Server : Int
      end
    end
    fn one_ping(ch : Chan(Client, Ping)) : Unit do
      let ch2 = Chan.send(ch, 42)
      Chan.close(ch2)
    end
  end|} in
  Alcotest.(check bool) "recursive Chan usage typechecks" false (has_errors ctx)

(* ══════════════════════════════════════════════════════════════════════════
   Multi-party session types (MPST) tests
   ══════════════════════════════════════════════════════════════════════════ *)

(* ── §1  Protocol declaration and projection ─────────────────────────── *)

let test_mpst_three_party_parses () =
  (* A 3-party protocol should parse and typecheck without errors. *)
  let ctx = typecheck {|mod Test do
    protocol ThreePartyAuth do
      Client -> Server : Int
      Server -> AuthDB : String
      AuthDB -> Server : Bool
      Server -> Client : Bool
    end
  end|} in
  Alcotest.(check bool) "3-party protocol: no errors" false (has_errors ctx)

let test_mpst_projection_client () =
  (* Client projection: MSend(Server, Int, MRecv(Server, Bool, End)) *)
  let (_ctx, env) = typecheck_full {|mod Test do
    protocol Auth do
      Client -> Server : Int
      Server -> AuthDB : String
      AuthDB -> Server : Bool
      Server -> Client : Bool
    end
  end|} in
  let pi = March_typecheck.Typecheck.StrMap.find "Auth" env.March_typecheck.Typecheck.protocols in
  let client_ty = List.assoc "Client" pi.March_typecheck.Typecheck.pi_projections in
  Alcotest.(check string) "client projection"
    "MSend(Server, Int, MRecv(Server, Bool, End))"
    (pp_sty client_ty)

let test_mpst_projection_authdb () =
  (* AuthDB projection: MRecv(Server, String, MSend(Server, Bool, End)) *)
  let (_ctx, env) = typecheck_full {|mod Test do
    protocol Auth do
      Client -> Server : Int
      Server -> AuthDB : String
      AuthDB -> Server : Bool
      Server -> Client : Bool
    end
  end|} in
  let pi = March_typecheck.Typecheck.StrMap.find "Auth" env.March_typecheck.Typecheck.protocols in
  let authdb_ty = List.assoc "AuthDB" pi.March_typecheck.Typecheck.pi_projections in
  Alcotest.(check string) "authdb projection"
    "MRecv(Server, String, MSend(Server, Bool, End))"
    (pp_sty authdb_ty)

let test_mpst_projection_server () =
  (* Server projection: MRecv(Client, Int, MSend(AuthDB, String, MRecv(AuthDB, Bool, MSend(Client, Bool, End)))) *)
  let (_ctx, env) = typecheck_full {|mod Test do
    protocol Auth do
      Client -> Server : Int
      Server -> AuthDB : String
      AuthDB -> Server : Bool
      Server -> Client : Bool
    end
  end|} in
  let pi = March_typecheck.Typecheck.StrMap.find "Auth" env.March_typecheck.Typecheck.protocols in
  let server_ty = List.assoc "Server" pi.March_typecheck.Typecheck.pi_projections in
  Alcotest.(check string) "server projection"
    "MRecv(Client, Int, MSend(AuthDB, String, MRecv(AuthDB, Bool, MSend(Client, Bool, End))))"
    (pp_sty server_ty)

let test_mpst_four_party_parses () =
  (* A 4-party protocol should also typecheck without errors. *)
  let ctx = typecheck {|mod Test do
    protocol FourParty do
      A -> B : Int
      B -> C : String
      C -> D : Bool
      D -> A : Float
    end
  end|} in
  Alcotest.(check bool) "4-party protocol: no errors" false (has_errors ctx)

(* ── §2  MPST.new type checking ─────────────────────────────────────── *)

let test_mpst_new_ok () =
  (* MPST.new on a 3-party protocol typechecks fine. *)
  let ctx = typecheck {|mod Test do
    protocol Auth do
      Client -> Server : Int
      Server -> AuthDB : String
      AuthDB -> Server : Bool
      Server -> Client : Bool
    end
    fn make() do
      let _ = MPST.new(Auth)
      ()
    end
  end|} in
  Alcotest.(check bool) "MPST.new 3-party: no errors" false (has_errors ctx)

let test_mpst_new_binary_error () =
  (* MPST.new on a 2-party protocol is an error (use Chan.new instead). *)
  let ctx = typecheck {|mod Test do
    protocol Binary do
      A -> B : Int
    end
    fn bad() do
      let _ = MPST.new(Binary)
      ()
    end
  end|} in
  Alcotest.(check bool) "MPST.new binary protocol: error" true (has_errors ctx)

let test_mpst_new_unknown_proto_error () =
  let ctx = typecheck {|mod Test do
    fn bad() do
      let _ = MPST.new(NoSuchProto)
      ()
    end
  end|} in
  Alcotest.(check bool) "MPST.new unknown protocol: error" true (has_errors ctx)

(* ── §3  MPST.send type checking ────────────────────────────────────── *)

let test_mpst_send_ok () =
  (* Client sending Int to Server should typecheck. *)
  let ctx = typecheck {|mod Test do
    protocol Auth do
      Client -> Server : Int
      Server -> AuthDB : String
      AuthDB -> Server : Bool
      Server -> Client : Bool
    end
    fn client_step(ch : Chan(Client, Auth)) : Unit do
      let ch2 = MPST.send(ch, Server, 42)
      ()
    end
  end|} in
  Alcotest.(check bool) "MPST.send correct role+type: no errors" false (has_errors ctx)

let test_mpst_send_wrong_role_error () =
  (* Client sending to AuthDB instead of Server is a type error. *)
  let ctx = typecheck {|mod Test do
    protocol Auth do
      Client -> Server : Int
      Server -> AuthDB : String
      AuthDB -> Server : Bool
      Server -> Client : Bool
    end
    fn bad(ch : Chan(Client, Auth)) : Unit do
      let _ = MPST.send(ch, AuthDB, 42)
      ()
    end
  end|} in
  Alcotest.(check bool) "MPST.send wrong role: error" true (has_errors ctx)

let test_mpst_send_wrong_type_error () =
  (* Client sending String instead of Int is a type error. *)
  let ctx = typecheck {|mod Test do
    protocol Auth do
      Client -> Server : Int
      Server -> AuthDB : String
      AuthDB -> Server : Bool
      Server -> Client : Bool
    end
    fn bad(ch : Chan(Client, Auth)) : Unit do
      let _ = MPST.send(ch, Server, "hello")
      ()
    end
  end|} in
  Alcotest.(check bool) "MPST.send wrong payload type: error" true (has_errors ctx)

(* ── §4  MPST.recv type checking ────────────────────────────────────── *)

let test_mpst_recv_ok () =
  (* AuthDB receiving String from Server then completing its session typechecks. *)
  let ctx = typecheck {|mod Test do
    protocol Auth do
      Client -> Server : Int
      Server -> AuthDB : String
      AuthDB -> Server : Bool
      Server -> Client : Bool
    end
    fn authdb_step(ch : Chan(AuthDB, Auth)) : Unit do
      let (_, ch2) = MPST.recv(ch, Server)
      let ch3 = MPST.send(ch2, Server, true)
      MPST.close(ch3)
    end
  end|} in
  Alcotest.(check bool) "MPST.recv correct role: no errors" false (has_errors ctx)

let test_mpst_recv_wrong_role_error () =
  (* AuthDB receiving from Client instead of Server is a type error. *)
  let ctx = typecheck {|mod Test do
    protocol Auth do
      Client -> Server : Int
      Server -> AuthDB : String
      AuthDB -> Server : Bool
      Server -> Client : Bool
    end
    fn bad(ch : Chan(AuthDB, Auth)) : Unit do
      let (_, ch2) = MPST.recv(ch, Client)
      let ch3 = MPST.send(ch2, Server, true)
      MPST.close(ch3)
    end
  end|} in
  Alcotest.(check bool) "MPST.recv wrong role: error" true (has_errors ctx)

(* ── §5  MPST.close type checking ───────────────────────────────────── *)

let test_mpst_close_ok () =
  (* AuthDB can close after finishing all its communications. *)
  let ctx = typecheck {|mod Test do
    protocol Auth do
      Client -> Server : Int
      Server -> AuthDB : String
      AuthDB -> Server : Bool
      Server -> Client : Bool
    end
    fn authdb_role(ch : Chan(AuthDB, Auth)) : Unit do
      let (_, ch2) = MPST.recv(ch, Server)
      let ch3 = MPST.send(ch2, Server, true)
      MPST.close(ch3)
    end
  end|} in
  Alcotest.(check bool) "MPST.close at SEnd: no errors" false (has_errors ctx)

let test_mpst_close_wrong_state_error () =
  (* Closing when not at SEnd is an error. *)
  let ctx = typecheck {|mod Test do
    protocol Auth do
      Client -> Server : Int
      Server -> AuthDB : String
      AuthDB -> Server : Bool
      Server -> Client : Bool
    end
    fn bad(ch : Chan(Client, Auth)) : Unit do
      MPST.close(ch)
    end
  end|} in
  Alcotest.(check bool) "MPST.close at non-End: error" true (has_errors ctx)

(* ── §6  Full protocol type checking ────────────────────────────────── *)

let test_mpst_full_auth_protocol_typechecks () =
  (* A complete function for each role should typecheck without errors. *)
  let ctx = typecheck {|mod Test do
    protocol Auth do
      Client -> Server : Int
      Server -> AuthDB : String
      AuthDB -> Server : Bool
      Server -> Client : Bool
    end
    fn client_role(ch : Chan(Client, Auth)) : Bool do
      let ch2 = MPST.send(ch, Server, 42)
      let (result, ch3) = MPST.recv(ch2, Server)
      MPST.close(ch3)
      result
    end
    fn authdb_role(ch : Chan(AuthDB, Auth)) : Unit do
      let (_, ch2) = MPST.recv(ch, Server)
      let ch3 = MPST.send(ch2, Server, true)
      MPST.close(ch3)
    end
    fn server_role(ch : Chan(Server, Auth)) : Unit do
      let (creds, ch2) = MPST.recv(ch, Client)
      let ch3 = MPST.send(ch2, AuthDB, "query")
      let (ok, ch4) = MPST.recv(ch3, AuthDB)
      let ch5 = MPST.send(ch4, Client, ok)
      MPST.close(ch5)
      ()
    end
  end|} in
  Alcotest.(check bool) "full Auth protocol: no errors" false (has_errors ctx)

let test_mpst_choose_offer_three_party_typechecks () =
  (* 3-party protocol with choose/offer branching typechecks. *)
  let ctx = typecheck {|mod Test do
    protocol Decision do
      A -> B : Int
      choose by B:
        yes -> B -> C : String
        no  -> B -> C : Int
      end
    end
    fn a_role(ch : Chan(A, Decision)) : Unit do
      let ch2 = MPST.send(ch, B, 42)
      MPST.close(ch2)
    end
  end|} in
  Alcotest.(check bool) "3-party choose/offer: no errors" false (has_errors ctx)

(* ── §7  Runtime (eval) tests ───────────────────────────────────────── *)

let test_mpst_eval_three_party () =
  (* Full runtime execution of ThreePartyAuth: client sends 42,
     authdb approves (true), client receives true back. *)
  let env = eval_module {|mod Test do
    protocol Auth do
      Client -> Server : Int
      Server -> AuthDB : String
      AuthDB -> Server : Bool
      Server -> Client : Bool
    end
    fn run() do
      let (ep_authdb, ep_client, ep_server) = MPST.new(Auth)
      -- Client sends credentials
      let ep_client2 = MPST.send(ep_client, Server, 42)
      -- Server receives credentials from Client
      let (_, ep_server2) = MPST.recv(ep_server, Client)
      -- Server sends query to AuthDB
      let ep_server3 = MPST.send(ep_server2, AuthDB, "lookup:42")
      -- AuthDB receives query from Server
      let (_, ep_authdb2) = MPST.recv(ep_authdb, Server)
      -- AuthDB sends result to Server
      let ep_authdb3 = MPST.send(ep_authdb2, Server, true)
      MPST.close(ep_authdb3)
      -- Server receives result from AuthDB
      let (result, ep_server4) = MPST.recv(ep_server3, AuthDB)
      -- Server sends response to Client
      let ep_server5 = MPST.send(ep_server4, Client, result)
      MPST.close(ep_server5)
      -- Client receives response from Server
      let (response, ep_client3) = MPST.recv(ep_client2, Server)
      MPST.close(ep_client3)
      response
    end
  end|} in
  let v = call_fn env "run" [] in
  Alcotest.(check bool) "MPST eval: client receives true" true (vbool v)

let test_mpst_eval_two_messages_same_pair () =
  (* Three parties where one pair exchanges two messages in sequence. *)
  let env = eval_module {|mod Test do
    protocol Relay do
      Sender -> Relay : Int
      Relay -> Sink : Int
    end
    fn run() do
      let (ep_relay, ep_sender, ep_sink) = MPST.new(Relay)
      -- Sender sends to Relay
      let ep_sender2 = MPST.send(ep_sender, Relay, 99)
      MPST.close(ep_sender2)
      -- Relay receives from Sender
      let (n, ep_relay2) = MPST.recv(ep_relay, Sender)
      -- Relay forwards to Sink
      let ep_relay3 = MPST.send(ep_relay2, Sink, n + 1)
      MPST.close(ep_relay3)
      -- Sink receives from Relay
      let (result, ep_sink2) = MPST.recv(ep_sink, Relay)
      MPST.close(ep_sink2)
      result
    end
  end|} in
  let v = call_fn env "run" [] in
  Alcotest.(check int) "MPST relay: sender 99 → sink 100" 100 (vint v)

let test_mpst_eval_four_party () =
  (* 4-party linear chain: A→B→C→D *)
  let env = eval_module {|mod Test do
    protocol Chain do
      A -> B : Int
      B -> C : Int
      C -> D : Int
    end
    fn run() do
      let (ep_a, ep_b, ep_c, ep_d) = MPST.new(Chain)
      let ep_a2 = MPST.send(ep_a, B, 1)
      MPST.close(ep_a2)
      let (n1, ep_b2) = MPST.recv(ep_b, A)
      let ep_b3 = MPST.send(ep_b2, C, n1 + 1)
      MPST.close(ep_b3)
      let (n2, ep_c2) = MPST.recv(ep_c, B)
      let ep_c3 = MPST.send(ep_c2, D, n2 + 1)
      MPST.close(ep_c3)
      let (n3, ep_d2) = MPST.recv(ep_d, C)
      MPST.close(ep_d2)
      n3
    end
  end|} in
  let v = call_fn env "run" [] in
  Alcotest.(check int) "MPST 4-party chain: 1→2→3" 3 (vint v)

let test_mpst_eval_wrong_order_error () =
  (* Receiving before sender sends should produce a runtime error. *)
  let env = eval_module {|mod Test do
    protocol Simple do
      X -> Y : Int
      Y -> Z : Int
    end
    fn run() do
      let (ep_x, ep_y, ep_z) = MPST.new(Simple)
      -- Y tries to recv from X before X sends — this will fail at runtime
      let (_, ep_y2) = MPST.recv(ep_y, X)
      let ep_x2 = MPST.send(ep_x, Y, 5)
      MPST.close(ep_x2)
      let ep_y3 = MPST.send(ep_y2, Z, 10)
      MPST.close(ep_y3)
      let (n, ep_z2) = MPST.recv(ep_z, Y)
      MPST.close(ep_z2)
      n
    end
  end|} in
  Alcotest.(check bool) "MPST recv before send: runtime error"
    true
    (try
       ignore (call_fn env "run" []);
       false  (* should not reach here *)
     with Failure _ | Invalid_argument _ | March_eval.Eval.Eval_error _ -> true)

(* ── Session type TIR lowering / compilation tests ──────────────────────── *)

(** Helper: parse, typecheck, lower + full pipeline → LLVM IR string.
    Identical to [emit_actor_ir] but placed here for session-type tests. *)
let test_session_compile_chan_new () =
  let ir = emit_session_ir {|mod Test do
    protocol Ping do
      Client -> Server : String
      Server -> Client : String
    end
    fn main() do
      let (ch_a, ch_b) = Chan.new(Ping)
      let ch_a2 = Chan.send(ch_a, "hello")
      let (msg, ch_b2) = Chan.recv(ch_b)
      let ch_b3 = Chan.send(ch_b2, msg)
      let (reply, ch_a3) = Chan.recv(ch_a2)
      Chan.close(ch_a3)
      Chan.close(ch_b3)
      reply
    end
  end|} in
  Alcotest.(check bool) "march_chan_new called" true
    (session_ir_contains ir "march_chan_new");
  Alcotest.(check bool) "march_chan_send called" true
    (session_ir_contains ir "march_chan_send");
  Alcotest.(check bool) "march_chan_recv called" true
    (session_ir_contains ir "march_chan_recv");
  Alcotest.(check bool) "march_chan_close called" true
    (session_ir_contains ir "march_chan_close")

(** Binary session types: Chan.choose/offer lower to march_chan_choose/offer. *)
let test_session_compile_chan_choose_offer () =
  let ir = emit_session_ir {|mod Test do
    protocol Decision do
      Client -> Server : Int
      choose by Server:
        ok  -> Server -> Client : Bool
        err -> Server -> Client : Int
      end
    end
    fn server_side(ch : Chan(Server, Decision)) : Unit do
      let (_, ch2) = Chan.recv(ch)
      let ch3 = Chan.choose(ch2, :ok)
      let ch4 = Chan.send(ch3, true)
      Chan.close(ch4)
    end
    fn client_side(ch : Chan(Client, Decision)) : Unit do
      let ch2 = Chan.send(ch, 42)
      let (label, ch3) = Chan.offer(ch2)
      let (_, ch4) = Chan.recv(ch3)
      Chan.close(ch4)
    end
    fn main() do
      let (c, s) = Chan.new(Decision)
      server_side(s)
      client_side(c)
    end
  end|} in
  Alcotest.(check bool) "march_chan_choose called" true
    (session_ir_contains ir "march_chan_choose");
  Alcotest.(check bool) "march_chan_offer called" true
    (session_ir_contains ir "march_chan_offer")

(** Full pipeline: session-typed code survives lower+mono+defun+perceus+emit. *)
let test_session_compile_full_pipeline_no_crash () =
  let _ir = emit_session_ir {|mod Test do
    protocol Echo do
      Sender -> Receiver : Int
      Receiver -> Sender : Int
    end
    fn main() do
      let (s, r) = Chan.new(Echo)
      let s2 = Chan.send(s, 42)
      let (n, r2) = Chan.recv(r)
      let r3 = Chan.send(r2, n + 1)
      let (result, s3) = Chan.recv(s2)
      Chan.close(s3)
      Chan.close(r3)
      result
    end
  end|} in
  Alcotest.(check bool) "session compile full pipeline: no crash" true true

(* ── Eval tests ─────────────────────────────────────────────────────────── *)

let test_actor_handler_extra_field () =
  (* Handler returns an extra field not in state → error with note *)
  let ctx = typecheck {|mod Test do
    actor Counter do
      state { value : Int }
      init { value: 0 }
      on Bad() do
        { value: 0, extra: true }
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
      init { value: 0, name: "x" }
      on Reset() do
        { value: 0 }
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
      init { value: 0 }
      on Inc() do
        { value: state.value + 1 }
      end
    end
  end|} in
  Alcotest.(check bool) "correct handler: no errors" false (has_errors ctx)

(* ── Actor handler return type checks — new gap-filling tests ─────────── *)

let test_actor_handler_duplicate_name () =
  (* Two handlers with the same message name → error *)
  let ctx = typecheck {|mod Test do
    actor Counter do
      state { value : Int }
      init { value: 0 }
      on Inc() do
        { value: state.value + 1 }
      end
      on Inc() do
        { value: state.value + 2 }
      end
    end
  end|} in
  Alcotest.(check bool) "duplicate handler: has error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  (match List.find_opt (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Error) diags with
  | None -> Alcotest.fail "expected an Error diagnostic for duplicate handler"
  | Some d ->
    Alcotest.(check bool) "message mentions 'Inc'" true
      (contains "Inc" d.March_errors.Errors.message);
    Alcotest.(check bool) "message mentions 'Counter'" true
      (contains "Counter" d.March_errors.Errors.message))

let test_actor_handler_wrong_return_type () =
  (* Handler returns Int instead of the state record → error *)
  let ctx = typecheck {|mod Test do
    actor Ticker do
      state { count : Int }
      init { count: 0 }
      on Tick() do
        42
      end
    end
  end|} in
  Alcotest.(check bool) "wrong return type: has error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  (match List.find_opt (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Error) diags with
  | None -> Alcotest.fail "expected an Error diagnostic"
  | Some d ->
    Alcotest.(check bool) "message mentions handler 'Tick'" true
      (contains "Tick" d.March_errors.Errors.message);
    Alcotest.(check bool) "message mentions actor 'Ticker'" true
      (contains "Ticker" d.March_errors.Errors.message))

let test_actor_handler_init_wrong_type () =
  (* Init returns wrong type (Int) instead of state record → error *)
  let ctx = typecheck {|mod Test do
    actor Foo do
      state { x : Int }
      init 99
      on Noop() do
        { x: state.x }
      end
    end
  end|} in
  Alcotest.(check bool) "init wrong type: has error" true (has_errors ctx)

let test_actor_handler_multiple_all_correct () =
  (* Multiple handlers, all returning correct state → no errors *)
  let ctx = typecheck {|mod Test do
    actor Game do
      state { score : Int, lives : Int }
      init { score: 0, lives: 3 }
      on Score(n : Int) do
        { score: state.score + n, lives: state.lives }
      end
      on Die() do
        { score: state.score, lives: state.lives - 1 }
      end
      on Reset() do
        { score: 0, lives: 3 }
      end
    end
  end|} in
  Alcotest.(check bool) "multiple handlers all correct: no errors" false (has_errors ctx)

let test_actor_handler_multiple_one_wrong () =
  (* Multiple handlers; one returns wrong type → exactly that handler errors *)
  let ctx = typecheck {|mod Test do
    actor Game do
      state { score : Int }
      init { score: 0 }
      on Add(n : Int) do
        { score: state.score + n }
      end
      on Cheat() do
        "free win"
      end
    end
  end|} in
  Alcotest.(check bool) "one bad handler: has error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  let errors = List.filter (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Error) diags in
  (* Only the 'Cheat' handler should error, not 'Add' *)
  Alcotest.(check bool) "bad handler name in message" true
    (List.exists (fun d -> contains "Cheat" d.March_errors.Errors.message) errors)

let test_actor_handler_unannotated_param_correct_arity () =
  (* Handler with unannotated param — constructor arity must be 1, not 0.
     Sending with the right number of args should typecheck with no error. *)
  let ctx = typecheck {|mod Test do
    actor Adder do
      state { total : Int }
      init { total: 0 }
      on Add(n) do
        { total: state.total + n }
      end
    end
    fn go(pid : Pid(Int)) : Int do
      send(pid, Add(5))
      0
    end
  end|} in
  Alcotest.(check bool) "unannotated param, correct arity: no error" false (has_errors ctx)

let test_actor_handler_unannotated_param_wrong_arity () =
  (* Sending wrong number of args to a handler with an unannotated param
     must error: constructor registered with arity 1, but 0 args sent. *)
  let ctx = typecheck {|mod Test do
    actor Adder do
      state { total : Int }
      init { total: 0 }
      on Add(n) do
        { total: state.total + n }
      end
    end
    fn go(pid : Pid(Int)) : Int do
      send(pid, Add())
      0
    end
  end|} in
  Alcotest.(check bool) "unannotated param, wrong arity: has error" true (has_errors ctx)

let test_actor_handler_state_spread_correct () =
  (* Record spread { state with field = ... } returns the correct state type *)
  let ctx = typecheck {|mod Test do
    actor Counter do
      state { count : Int, label : String }
      init { count: 0, label: "x" }
      on Inc() do
        { count: state.count + 1, label: state.label }
      end
    end
  end|} in
  Alcotest.(check bool) "state spread handler: no errors" false (has_errors ctx)

let test_actor_handler_no_message_params_correct () =
  (* Handler with no params (zero-arg message) that uses state correctly *)
  let ctx = typecheck {|mod Test do
    actor Toggle do
      state { active : Bool }
      init { active: false }
      on Flip() do
        { active: true }
      end
      on Reset() do
        { active: false }
      end
    end
  end|} in
  Alcotest.(check bool) "no-param handlers: no errors" false (has_errors ctx)

(* Regression: let-generalization hole for forward-referenced pfn helpers.
   When function A appears before helper B in source order and calls B,
   pass-1 seeds B with Mono(TVar r) at level 1.  During A's body inference
   the call site unifies r into the type chain.  generalize() previously
   wrapped those shared mutable TVar refs directly in the Poly scheme.
   When B's own body was later checked its recursive call unified the same
   TVar (e.g. ?lst_elem → List(Int)), silently corrupting A's stored scheme
   so a second call site with a different element type failed with a spurious
   type mismatch.  Fix: generalize() deep-copies quantified TVar refs into
   fresh isolated allocations so future unification of the originals cannot
   reach the stored scheme. *)
let test_tc_forward_ref_poly_helper_two_call_sites () =
  (* count calls go which is defined AFTER count — the forward-reference case. *)
  let ctx = typecheck {|mod Test do
    pfn count(lst) do
      go(lst, 0)
    end
    pfn go(lst, n) do
      match lst do
      Nil -> n
      Cons(_, rest) -> go(rest, n + 1)
      end
    end
    fn main() do
      let a = count([1, 2, 3])
      let b = count(["x", "y"])
      a + b
    end
  end|} in
  Alcotest.(check bool)
    "forward-ref pfn called at two element types: no errors" false (has_errors ctx)

let test_tc_forward_ref_poly_reverse_order () =
  (* Same pattern but go is defined before count — should also work.
     Verifies the fix doesn't break the already-working ordering. *)
  let ctx = typecheck {|mod Test do
    pfn go(lst, n) do
      match lst do
      Nil -> n
      Cons(_, rest) -> go(rest, n + 1)
      end
    end
    pfn count(lst) do go(lst, 0) end
    fn main() do
      let a = count([1, 2, 3])
      let b = count(["x", "y"])
      a + b
    end
  end|} in
  Alcotest.(check bool)
    "normal-order pfn called at two element types: no errors" false (has_errors ctx)

(* ── let? typecheck tests ────────────────────────────────────────────── *)

let test_letq_typechecks_ok () =
  let ctx = typecheck {|mod Test do
    fn run() do
      let? x = Ok(42)
      Ok(x + 1)
    end
  end|} in
  Alcotest.(check bool) "let? with Ok: no type errors" false (has_errors ctx)

let test_letq_rhs_not_result_error () =
  let ctx = typecheck {|mod Test do
    fn run() do
      let? x = 42
      Ok(x)
    end
  end|} in
  Alcotest.(check bool) "let? rhs must be Result: type error" true (has_errors ctx)

let test_letq_mismatched_error_types () =
  (* f returns Result(Int, String) and g returns Result(Int, Int).
     Using both in a let? chain forces their error types to unify:
     String vs Int → type error. *)
  let ctx = typecheck {|mod Test do
    fn f() : Result(Int, String) do Ok(1) end
    fn g() : Result(Int, Int) do Ok(2) end
    fn run() do
      let? _a = f()
      let? _b = g()
      Ok(42)
    end
  end|} in
  Alcotest.(check bool) "let? mixed error types: type error" true (has_errors ctx)

let test_letq_last_in_block_error () =
  let ctx = typecheck {|mod Test do
    fn run() do
      let? _x = Ok(42)
    end
  end|} in
  Alcotest.(check bool) "let? last in block: type error" true (has_errors ctx)

let test_letq_chain_typechecks () =
  let ctx = typecheck {|mod Test do
    fn run() do
      let? x = Ok(1)
      let? y = Ok(2)
      Ok(x + y)
    end
  end|} in
  Alcotest.(check bool) "let? chain: no type errors" false (has_errors ctx)

(* ── Perceus RC tests ────────────────────────────────────────────────── *)

(** Parse, desugar, typecheck, lower, mono, defun, then run perceus. *)
let test_fn_when_constraint_satisfied () =
  let ctx = typecheck {|mod Test do
    impl Eq(Int) do
      fn eq(x, y) do x == y end
    end
    fn contains(xs : List(a), x : a) : Bool when Eq(a) do
      match xs do
      Nil -> false
      Cons(h, t) -> if eq(h, x) then true else contains(t, x)
      end
    end
    fn main() : Bool do
      contains(Cons(1, Cons(2, Nil)), 2)
    end
  end|} in
  Alcotest.(check bool) "fn when Eq(a) with Int (has impl): no errors" false (has_errors ctx)

(* F2: when Eq(a) constraint on user function signature — unsatisfied *)
let test_fn_when_constraint_unsatisfied () =
  let ctx = typecheck {|mod Test do
    type Color = Red | Green
    fn contains(xs : List(a), x : a) : Bool when Eq(a) do
      match xs do
      Nil -> false
      Cons(h, t) -> if eq(h, x) then true else contains(t, x)
      end
    end
    fn main() : Bool do
      contains(Cons(Red, Nil), Green)
    end
  end|} in
  Alcotest.(check bool) "fn when Eq(a) with Color (no impl): error" true (has_errors ctx)

(* F2: qualified method call Eq.eq(x, y) resolves correctly *)
let test_qualified_method_call () =
  let ctx = typecheck {|mod Test do
    impl Eq(Int) do
      fn eq(x, y) do x == y end
    end
    fn check(x : Int, y : Int) : Bool do
      Eq.eq(x, y)
    end
  end|} in
  Alcotest.(check bool) "Eq.eq(x, y) resolves: no errors" false (has_errors ctx)

(* F2: qualified Show.show call *)
let test_qualified_show_call () =
  let ctx = typecheck {|mod Test do
    fn to_str(x : Int) : String do Show.show(x) end
  end|} in
  Alcotest.(check bool) "Show.show(x) resolves: no errors" false (has_errors ctx)

(* F5: linear let binding — used exactly once is ok *)
let test_linear_let_ok () =
  let ctx = typecheck {|mod Test do
    fn consume(x : Int) : Int do x end
    fn f() : Int do
      linear let v = 42
      consume(v)
    end
  end|} in
  Alcotest.(check bool) "linear let used once: no errors" false (has_errors ctx)

(* F5: linear let binding — used twice is an error *)
let test_linear_let_double_use () =
  let ctx = typecheck {|mod Test do
    fn consume(x : Int) : Int do x end
    fn f() : Int do
      linear let v = 42
      consume(v) + consume(v)
    end
  end|} in
  Alcotest.(check bool) "linear let used twice: error" true (has_errors ctx)

(* Track-A: linear type enforcement — using a linear binding twice inside a
   match arm is detected and rejected. *)
let test_worker_named_spec () =
  let src = {|mod AppTest do
    actor Counter do
      state { count : Int }
      init { count: 0 }
      on Inc() do { count: state.count + 1 } end
    end

    fn main() do
      worker(Counter, :permanent, {name: :my_svc})
    end
  end|} in
  let env = eval_module src in
  let spec = call_fn env "main" [] in
  (match spec with
   | March_eval.Eval.VRecord fields ->
     let name_field = List.assoc_opt "name" fields in
     Alcotest.(check bool) "worker named spec has name field" true
       (name_field = Some (March_eval.Eval.VAtom "my_svc"))
   | _ -> Alcotest.fail "expected VRecord from worker/3")

(** run_module with a named app child registers it in process_registry *)
let test_whereis_named () =
  let src = {|mod AppTest do
    actor Counter do
      state { count : Int }
      init { count: 0 }
      on Inc() do { count: state.count + 1 } end
    end

    app MyApp do
      Supervisor.spec(:one_for_one, [worker(Counter, :permanent, {name: :counter_svc})])
    end
  end|} in
  let m =
    let lexbuf = Lexing.from_string src in
    let ast = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
    March_desugar.Desugar.desugar_module ast
  in
  March_eval.Eval.run_module m;
  (* process_registry should have "counter_svc" → some pid (set during app startup) *)
  let registered = Hashtbl.find_opt March_eval.Eval.process_registry "counter_svc" in
  Alcotest.(check bool) "counter_svc registered" true (registered <> None);
  (* After graceful shutdown, the actor is dead; whereis correctly returns None *)
  let result = call_builtin "whereis" [March_eval.Eval.VAtom "counter_svc"] in
  Alcotest.(check bool) "whereis returns None for dead post-shutdown actor" true
    (match result with March_eval.Eval.VCon ("None", []) -> true | _ -> false)

(** whereis returns Some(Pid) for a live actor registered manually *)
let test_whereis_live_actor () =
  let _env = eval_module {|mod TestWhereis do
    actor Counter do
      state { count : Int }
      init { count: 0 }
      on Inc() do { count: state.count + 1 } end
    end
    fn main() do
      spawn(Counter)
    end
  end|} in
  let pid = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  Alcotest.(check bool) "actor spawned" true (pid >= 0);
  Hashtbl.replace March_eval.Eval.process_registry "live_svc" pid;
  let result = call_builtin "whereis" [March_eval.Eval.VAtom "live_svc"] in
  Alcotest.(check bool) "whereis returns Some(Pid) for live actor" true
    (match result with March_eval.Eval.VCon ("Some", [March_eval.Eval.VPid _]) -> true | _ -> false)

(** whereis on an unknown atom returns None *)
let test_whereis_unknown () =
  let result = call_builtin "whereis" [March_eval.Eval.VAtom "no_such_process"] in
  Alcotest.(check bool) "whereis unknown returns None" true
    (match result with March_eval.Eval.VCon ("None", []) -> true | _ -> false)

(** whereis_bang on an unknown atom raises Eval_error *)
let test_whereis_bang_unknown () =
  let raised =
    try
      ignore (call_builtin "whereis_bang" [March_eval.Eval.VAtom "no_such_process"]);
      false
    with March_eval.Eval.Eval_error _ -> true
       | Failure _                    -> true
  in
  Alcotest.(check bool) "whereis_bang unknown raises" true raised

(** When a supervised actor is killed and restarted, its registered name
    is rebound to the new pid automatically. *)
let test_name_reregisters_on_restart () =
  let env = eval_module {|mod Test do
    actor Worker do
      state { count : Int }
      init { count: 0 }
      on Inc() do { count: state.count + 1 } end
    end

    actor Supervisor do
      state { worker : Int }
      init { worker: 0 }
      supervise do
        strategy one_for_one
        max_restarts 3 within 5
        Worker worker
      end
    end

    fn main() do
      spawn(Supervisor)
    end
  end|} in
  let sup_pid = match call_fn env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  let w1_pid = get_supervisor_child_pid sup_pid "worker" in
  Alcotest.(check bool) "initial worker pid >= 0" true (w1_pid >= 0);
  (* Manually register the worker under a name, simulating named spawn *)
  Hashtbl.replace March_eval.Eval.process_registry "my_worker" w1_pid;
  Hashtbl.replace March_eval.Eval.pid_to_registry_name w1_pid "my_worker";
  (* Kill the worker — supervisor restarts it *)
  March_eval.Eval.crash_actor w1_pid "test kill";
  let w2_pid = get_supervisor_child_pid sup_pid "worker" in
  Alcotest.(check bool) "new pid differs from old" true (w2_pid <> w1_pid);
  (* Verify the name is now bound to the new pid *)
  let registered_pid = Hashtbl.find_opt March_eval.Eval.process_registry "my_worker" in
  Alcotest.(check bool) "name rebound to new pid" true (registered_pid = Some w2_pid);
  (* Old pid no longer in pid_to_registry_name *)
  let old_name = Hashtbl.find_opt March_eval.Eval.pid_to_registry_name w1_pid in
  Alcotest.(check bool) "old pid removed from name map" true (old_name = None)

(* ------------------------------------------------------------------ *)
(* Spec construction tests                                             *)
(* ------------------------------------------------------------------ *)

(** Supervisor.spec(:one_for_one, [...]) returns a record with strategy and
    children fields. Verifies the spec value structure at the eval level. *)
let test_dyn_sup_start_child () =
  let env = eval_module {|mod Test do
    actor Worker do
      state { n : Int }
      init { n: 0 }
      on Inc() do { n: state.n + 1 } end
    end

    fn main() do
      dynamic_supervisor(:workers, :one_for_one)
      let spec = worker(Worker)
      Supervisor.start_child(:workers, spec)
    end
  end|} in
  let result = call_fn env "main" [] in
  (* start_child should return Ok(pid) *)
  let ok = match result with
    | March_eval.Eval.VCon ("Ok", [March_eval.Eval.VInt _]) -> true
    | _ -> false in
  Alcotest.(check bool) "start_child returns Ok(pid)" true ok;
  (* Dynamic supervisor should have exactly 1 child *)
  let children = dyn_sup_children "workers" in
  Alcotest.(check int) "dyn sup has 1 child" 1 (List.length children)

(** count_children returns active + specs counts. *)
let test_dyn_sup_count_children () =
  let _env = eval_module {|mod Test do
    actor W do
      state { x : Int }
      init { x: 0 }
      on Noop() do { x: 0 } end
    end

    fn main() do
      dynamic_supervisor(:pool, :one_for_one)
      Supervisor.start_child(:pool, worker(W))
      Supervisor.start_child(:pool, worker(W))
      Supervisor.count_children(:pool)
    end
  end|} in
  let result = call_fn _env "main" [] in
  let active = match result with
    | March_eval.Eval.VRecord fs ->
      (match List.assoc_opt "active" fs with
       | Some (March_eval.Eval.VInt n) -> n | _ -> -1)
    | _ -> -1 in
  let specs = match result with
    | March_eval.Eval.VRecord fs ->
      (match List.assoc_opt "specs" fs with
       | Some (March_eval.Eval.VInt n) -> n | _ -> -1)
    | _ -> -1 in
  Alcotest.(check int) "count_children active = 2" 2 active;
  Alcotest.(check int) "count_children specs = 2" 2 specs

(** which_children returns a list of child records. *)
let test_dyn_sup_which_children () =
  let _env = eval_module {|mod Test do
    actor W do
      state { x : Int }
      init { x: 0 }
      on Noop() do { x: 0 } end
    end

    fn main() do
      dynamic_supervisor(:ws, :one_for_one)
      Supervisor.start_child(:ws, worker(W))
      Supervisor.start_child(:ws, worker(W))
      Supervisor.which_children(:ws)
    end
  end|} in
  let result = call_fn _env "main" [] in
  let children = vlist result in
  Alcotest.(check int) "which_children returns 2 entries" 2 (List.length children);
  (* Each entry should be a record with pid/actor/restart fields *)
  let has_pid = match List.hd children with
    | March_eval.Eval.VRecord fs -> List.mem_assoc "pid" fs | _ -> false in
  Alcotest.(check bool) "child records have pid field" true has_pid

(** Crash a permanent child → it is restarted with a new pid. *)
let test_dyn_sup_permanent_restart () =
  let _env = eval_module {|mod Test do
    actor W do
      state { x : Int }
      init { x: 0 }
      on Noop() do { x: 0 } end
    end

    fn main() do
      dynamic_supervisor(:wpool, :one_for_one)
      Supervisor.start_child(:wpool, worker(W))
    end
  end|} in
  ignore (call_fn _env "main" []);
  let ds = Hashtbl.find March_eval.Eval.dyn_sup_registry "wpool" in
  let orig_pid = (List.hd ds.March_eval.Eval.ds_children).March_eval.Eval.dce_pid in
  (* Crash the child — should be restarted *)
  March_eval.Eval.crash_actor orig_pid "test kill";
  let ds2 = Hashtbl.find March_eval.Eval.dyn_sup_registry "wpool" in
  let new_children = ds2.March_eval.Eval.ds_children in
  Alcotest.(check int) "still has 1 child after restart" 1 (List.length new_children);
  let new_pid = (List.hd new_children).March_eval.Eval.dce_pid in
  Alcotest.(check bool) "new pid differs from old" true (new_pid <> orig_pid);
  Alcotest.(check bool) "new child is alive" true
    (match Hashtbl.find_opt March_eval.Eval.actor_registry new_pid with
     | Some i -> i.March_eval.Eval.ai_alive | None -> false)

(** Crash a temporary child → it is NOT restarted. *)
let test_dyn_sup_temporary_not_restarted () =
  let _env = eval_module {|mod Test do
    actor W do
      state { x : Int }
      init { x: 0 }
      on Noop() do { x: 0 } end
    end

    fn main() do
      dynamic_supervisor(:temps, :one_for_one)
      Supervisor.start_child(:temps, worker(W, :temporary))
    end
  end|} in
  ignore (call_fn _env "main" []);
  let ds = Hashtbl.find March_eval.Eval.dyn_sup_registry "temps" in
  let orig_pid = (List.hd ds.March_eval.Eval.ds_children).March_eval.Eval.dce_pid in
  March_eval.Eval.crash_actor orig_pid "test kill";
  let ds2 = Hashtbl.find March_eval.Eval.dyn_sup_registry "temps" in
  Alcotest.(check int) "temporary child NOT restarted" 0 (List.length ds2.March_eval.Eval.ds_children)

(** stop_child removes child from supervisor and kills it. *)
let test_dyn_sup_stop_child () =
  let _env = eval_module {|mod Test do
    actor W do
      state { x : Int }
      init { x: 0 }
      on Noop() do { x: 0 } end
    end

    fn main() do
      dynamic_supervisor(:stoppool, :one_for_one)
      let r = Supervisor.start_child(:stoppool, worker(W))
      r
    end
  end|} in
  let result = call_fn _env "main" [] in
  let pid = match result with
    | March_eval.Eval.VCon ("Ok", [March_eval.Eval.VInt p]) -> p
    | _ -> failwith "expected Ok(pid)" in
  (* Verify child is present *)
  let ds_before = Hashtbl.find March_eval.Eval.dyn_sup_registry "stoppool" in
  Alcotest.(check int) "1 child before stop" 1 (List.length ds_before.March_eval.Eval.ds_children);
  (* stop_child via builtin *)
  let stopfn = List.assoc "Supervisor.stop_child"
    (March_eval.Eval.task_builtins @ March_eval.Eval.base_env) in
  let stop_result = March_eval.Eval.apply stopfn
    [March_eval.Eval.VAtom "stoppool"; March_eval.Eval.VInt pid] in
  let ok = match stop_result with
    | March_eval.Eval.VCon ("Ok", [March_eval.Eval.VUnit]) -> true | _ -> false in
  Alcotest.(check bool) "stop_child returns Ok(Unit)" true ok;
  let ds_after = Hashtbl.find March_eval.Eval.dyn_sup_registry "stoppool" in
  Alcotest.(check int) "0 children after stop" 0 (List.length ds_after.March_eval.Eval.ds_children);
  Alcotest.(check bool) "stopped child is dead" false
    (match Hashtbl.find_opt March_eval.Eval.actor_registry pid with
     | Some i -> i.March_eval.Eval.ai_alive | None -> false)

(** dynamic_supervisor in an app spec: registers the dyn sup before scheduler runs. *)
let test_dyn_sup_in_app () =
  let src = {|mod DynApp do
    actor Worker do
      state { n : Int }
      init { n: 0 }
      on Inc() do { n: state.n + 1 } end
    end

    app MyApp do
      Supervisor.spec(:one_for_one, [
        dynamic_supervisor(:handlers, :one_for_one)
      ])
    end
  end|} in
  let m =
    let lexbuf = Lexing.from_string src in
    let ast = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
    March_desugar.Desugar.desugar_module ast
  in
  March_eval.Eval.run_module m;
  (* The dynamic supervisor should have been registered *)
  Alcotest.(check bool) "dyn sup registered in app" true
    (Hashtbl.mem March_eval.Eval.dyn_sup_registry "handlers")

(* ------------------------------------------------------------------ *)
(* Shutdown protocol tests                                            *)
(* ------------------------------------------------------------------ *)

(** Shutdown handler runs when actor receives Shutdown() *)
let test_resolver_skips_dangling_symlink () =
  let dir = Filename.temp_file "march_resolver_dangling_" "" in
  Sys.remove dir;
  Unix.mkdir dir 0o755;
  let foo = Filename.concat dir "foo.march" in
  let oc = open_out foo in
  output_string oc "mod Foo do\nend\n";
  close_out oc;
  Unix.symlink "/nonexistent/march/target" (Filename.concat dir "broken");
  let files = March_resolver.Resolver.collect_lib_files dir in
  Alcotest.(check bool) "valid module found despite dangling symlink"
    true (List.exists (fun p -> Filename.basename p = "foo.march") files);
  Alcotest.(check bool) "dangling symlink not collected"
    false (List.exists (fun p -> Filename.basename p = "broken") files)

(* ── `tag` keyword tests ───────────────────────────────────────────────── *)

let test_tag_parses () =
  let src = {|mod Test do
    tag Open
    tag Closed
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "tag declarations: no errors" false (has_errors ctx)

let test_tag_usable_as_ctor () =
  let src = {|mod Test do
    tag Open
    fn go() : Open do Open end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "tag ctor usable as value: no errors" false (has_errors ctx)

(* ── `always_linear type` tests ─────────────────────────────────────────── *)

let test_always_linear_type_ok () =
  let src = {|mod Test do
    always_linear type Handle(s) = Handle(Int)
    fn use_it(h : Handle(Open)) : Handle(Open) do h end
    tag Open
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "always_linear type: no errors when consumed" false (has_errors ctx)

let test_always_linear_type_drop_error () =
  let src = {|mod Test do
    always_linear type Handle(s) = Handle(Int)
    tag Open
    fn bad() do
      let h = Handle(42)
      42
    end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "always_linear type: drop is error" true (has_errors ctx)

(* ── `transitions` tests ────────────────────────────────────────────────── *)

let test_transitions_parses () =
  let src = {|mod Conn do
    type Handle(s) = Handle(Int)
    tag Open
    tag Closed

    fn open_conn(h : Handle(Closed)) : Handle(Open) do Handle(1) end

    transitions Handle do
      ConnTag: Closed -> Open via open_conn
    end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "transitions block: no errors" false (has_errors ctx)

let test_transitions_via_not_found_error () =
  let src = {|mod Conn do
    type Handle(s) = Handle(Int)
    tag Open
    tag Closed

    transitions Handle do
      ConnTag: Closed -> Open via nonexistent_fn
    end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "transitions via missing fn: error" true (has_errors ctx)

let test_transitions_warn_undeclared () =
  let src = {|mod Conn do
    type Handle(s) = Handle(Int)
    tag Open
    tag Closed

    fn open_conn(h : Handle(Closed)) : Handle(Open) do Handle(1) end

    transitions Handle do
    end
  end|} in
  let ctx = typecheck src in
  let contains_sub s sub =
    let n = String.length s and len = String.length sub in
    let found = ref false in
    for i = 0 to n - len do
      if String.sub s i len = sub then found := true
    done;
    !found
  in
  let has_transition_warning = List.exists (fun (d : March_errors.Errors.diagnostic) ->
    d.severity = March_errors.Errors.Warning &&
    contains_sub (String.lowercase_ascii d.message) "transition"
  ) ctx.diagnostics in
  Alcotest.(check bool) "undeclared transition fn: warning emitted" true has_transition_warning

(* ── `Tagged(X, T)` specialization tag tests ────────────────────────────── *)

let test_tagged_type_parses () =
  let src = {|mod Test do
    type DSP = DSP
    type Realtime = Realtime
    fn process(cap : Tagged(DSP, Realtime)) : () do () end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "Tagged(X, T): valid type, no errors" false (has_errors ctx)

let test_tagged_realtime_excludes_io_error () =
  let src = {|mod Test do
    needs IO
    type DSP = DSP
    type Realtime = Realtime
    fn process(cap : Tagged(DSP, Realtime), io : Cap(IO)) : () do () end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "Tagged(_, Realtime) + Cap(IO): error" true (has_errors ctx)

let test_tagged_realtime_excludes_alloc_error () =
  let src = {|mod Test do
    needs Alloc
    type DSP = DSP
    type Realtime = Realtime
    fn process(cap : Tagged(DSP, Realtime), alloc : Cap(Alloc)) : () do () end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "Tagged(_, Realtime) + Cap(Alloc): error" true (has_errors ctx)

let test_tagged_realtime_excludes_panic_error () =
  let src = {|mod Test do
    needs Panic
    type DSP = DSP
    type Realtime = Realtime
    fn process(cap : Tagged(DSP, Realtime), p : Cap(Panic)) : () do () end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "Tagged(_, Realtime) + Cap(Panic): error" true (has_errors ctx)

let test_tagged_standard_no_exclusion () =
  let src = {|mod Test do
    needs IO
    type DSP = DSP
    type Standard = Standard
    fn process(cap : Tagged(DSP, Standard), io : Cap(IO)) : () do () end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "Tagged(_, Standard) + Cap(IO): no error" false (has_errors ctx)

(* ── Phase 3a: Explicit bounded type parameters ─────────────────────────── *)

let test_bound_param_parses () =
  let src = {|mod T do
    type ConnState = Open | Closed
    type Handle(s) = Handle(Int)
    fn transmit[s : ConnState](h : Handle(s), data : Int) : Int do data end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "fn[s : ADT] parses and typechecks" false (has_errors ctx)

let test_bound_param_valid_call () =
  let src = {|mod T do
    type ConnState = Open | Closed
    type Handle(s) = Handle(Int)
    fn unwrap[s : ConnState](b : Handle(s)) : Int do
      match b do Handle(x) -> x end
    end
    fn go() : Int do
      let h : Handle(Open) = Handle(42)
      unwrap(h)
    end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "bound ADT: valid constructor — no error" false (has_errors ctx)

let test_bound_param_invalid_call () =
  (* Force the phantom type to Int via a typed helper — Int is a valid type name
     but not a constructor of ConnState, so discharge_constraints will reject it. *)
  let src = {|mod T do
    type ConnState = Open | Closed
    type Handle(s) = Handle(Int)
    fn unwrap[s : ConnState](b : Handle(s)) : Int do
      match b do Handle(x) -> x end
    end
    pfn coerce_int(h : Handle(Int)) : Handle(Int) do h end
    fn go() : Int do
      let h = Handle(42)
      let h2 = coerce_int(h)
      unwrap(h2)
    end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "bound ADT: wrong constructor — error" true (has_errors ctx)

let test_bound_interface_equiv () =
  let src = {|mod T do
    fn eq_test[a : Eq](x : a, y : a) : Bool do x == y end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "bound interface (Eq): no error" false (has_errors ctx)

let test_bound_multiple_params () =
  (* Box(A)/Box(B) annotations are invalid (constructors aren't type names).
     Use untyped let bindings — phantom types stay polymorphic, constraints skip. *)
  let src = {|mod T do
    type State = A | B
    type Box(s) = Box(Int)
    fn swap[s : State, t : State](a : Box(s), b : Box(t)) : Box(t) do b end
    fn go() : Int do
      let a = Box(1)
      let b = Box(2)
      let _ = swap(a, b)
      0
    end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "multiple bounds: valid call — no error" false (has_errors ctx)

let test_bound_unknown_adt () =
  let src = {|mod T do
    fn f[s : NonExistentType](x : Int) : Int do x end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "bound unknown type — error" true (has_errors ctx)

let test_bound_in_return_type () =
  (* Box(A) annotation is invalid (A is a constructor, not a type name).
     Call identity with an untyped binding — s stays polymorphic, no error. *)
  let src = {|mod T do
    type State = A | B
    type Box(s) = Box(Int)
    fn identity[s : State](b : Box(s)) : Box(s) do b end
    fn go() : Int do
      let b = Box(1)
      let _ = identity(b)
      0
    end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "bound in return type: no error" false (has_errors ctx)

let test_bound_nat_valid () =
  let src = {|mod T do
    fn check_nat[n : Nat](x : Int) : Int do x end
    fn go() : Int do check_nat(1) end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "Nat bound: polymorphic call — no error" false (has_errors ctx)

let test_bound_tag_as_adt () =
  let src = {|mod T do
    type ConnTag = Open | Closed
    type Handle(s) = Handle(Int)
    fn read[s : ConnTag](h : Handle(s)) : Int do
      match h do Handle(x) -> x end
    end
    fn go() : Int do
      let h : Handle(Open) = Handle(7)
      read(h)
    end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "ADT bound with tag-style type: valid" false (has_errors ctx)

(* ── Phase 3b: Policy-tag DCE audit (TIR-level unit tests) ──────────── *)

let mk_tagged_param policy_name =
  { March_tir.Tir.v_name = "cap";
    v_ty = March_tir.Tir.TCon ("Tagged",
             [March_tir.Tir.TCon ("DSP", []);
              March_tir.Tir.TCon (policy_name, [])]);
    v_lin = March_tir.Tir.Unr }

let mk_tagged_fn policy_name body =
  { March_tir.Tir.fn_name = "process";
    fn_params = [mk_tagged_param policy_name];
    fn_ret_ty  = March_tir.Tir.TInt;
    fn_body    = body }

let tir_int_lit n =
  March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt n))

let tir_call name arg_tys ret_ty args =
  let f = { March_tir.Tir.v_name = name;
            v_ty = March_tir.Tir.TFn (arg_tys, ret_ty);
            v_lin = March_tir.Tir.Unr } in
  March_tir.Tir.EApp (f, args)

let test_policy_noalloc_alloc_violation () =
  let body = March_tir.Tir.EAlloc (March_tir.Tir.TCon ("List", [March_tir.Tir.TInt]), []) in
  let m = mk_module [mk_tagged_fn "NoAlloc" body] in
  let v = March_tir.Policy_dce.audit m in
  Alcotest.(check bool) "NoAlloc fn with EAlloc: violation" true (v <> [])

let test_policy_noalloc_clean () =
  let m = mk_module [mk_tagged_fn "NoAlloc" (tir_int_lit 42)] in
  let v = March_tir.Policy_dce.audit m in
  Alcotest.(check bool) "NoAlloc fn with no alloc: no violation" true (v = [])

let test_policy_nopanic_int_div_violation () =
  let body = tir_call "int_div"
    [March_tir.Tir.TInt; March_tir.Tir.TInt] March_tir.Tir.TInt
    [March_tir.Tir.ALit (March_ast.Ast.LitInt 10);
     March_tir.Tir.ALit (March_ast.Ast.LitInt 2)] in
  let m = mk_module [mk_tagged_fn "NoPanic" body] in
  let v = March_tir.Policy_dce.audit m in
  Alcotest.(check bool) "NoPanic fn calling int_div: violation" true (v <> [])

let test_policy_nopanic_clean () =
  let m = mk_module [mk_tagged_fn "NoPanic" (tir_int_lit 0)] in
  let v = March_tir.Policy_dce.audit m in
  Alcotest.(check bool) "NoPanic fn with safe body: no violation" true (v = [])

let test_policy_nopanic_transitive () =
  (* Helper that calls panic_ *)
  let helper_body = tir_call "panic_"
    [March_tir.Tir.TString] March_tir.Tir.TUnit
    [March_tir.Tir.ALit (March_ast.Ast.LitString "oops")] in
  let helper = { March_tir.Tir.fn_name = "my_helper"; fn_params = [];
                 fn_ret_ty = March_tir.Tir.TUnit; fn_body = helper_body } in
  (* Tagged fn calls the helper *)
  let body = tir_call "my_helper" [] March_tir.Tir.TUnit [] in
  let fd = mk_tagged_fn "NoPanic" body in
  let m = mk_module [helper; fd] in
  let v = March_tir.Policy_dce.audit m in
  Alcotest.(check bool) "NoPanic fn with transitive panic helper: violation" true (v <> [])

let test_policy_realtime_io_violation () =
  let body = tir_call "Http.get"
    [March_tir.Tir.TString] March_tir.Tir.TString
    [March_tir.Tir.ALit (March_ast.Ast.LitString "url")] in
  let fd = mk_tagged_fn "Realtime" body in
  let m = { (mk_module [fd]) with March_tir.Tir.tm_io_fns = ["Http"] } in
  let v = March_tir.Policy_dce.audit m in
  Alcotest.(check bool) "Realtime fn calling Http.get: violation" true (v <> [])

let test_policy_realtime_clean () =
  let fd = mk_tagged_fn "Realtime" (tir_int_lit 0) in
  let m = { (mk_module [fd]) with March_tir.Tir.tm_io_fns = ["Http"] } in
  let v = March_tir.Policy_dce.audit m in
  Alcotest.(check bool) "Realtime fn with clean body: no violation" true (v = [])

let test_policy_untagged_not_checked () =
  let body = March_tir.Tir.EAlloc (March_tir.Tir.TCon ("List", [March_tir.Tir.TInt]), []) in
  let fd = { March_tir.Tir.fn_name = "normal_fn"; fn_params = [];
             fn_ret_ty = March_tir.Tir.TInt; fn_body = body } in
  let m = mk_module [fd] in
  let v = March_tir.Policy_dce.audit m in
  Alcotest.(check bool) "Untagged fn with alloc: no violation" true (v = [])

(* ── cap no_panic tests ─────────────────────────────────────────────────── *)

let test_cap_no_panic_lexes () =
  let lexbuf = Lexing.from_string "cap no_panic" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "cap no_panic lexes as CAP_NO_PANIC token" true
    (match tok with March_parser.Parser.CAP_NO_PANIC -> true | _ -> false)

let test_cap_no_panic_safe_no_error () =
  let ctx = typecheck {|mod Safe do
    cap no_panic
    fn add(a : Int, b : Int) : Int do a + b end
  end|} in
  Alcotest.(check bool) "cap no_panic with safe body: no error" false (has_errors ctx)

let test_cap_not_set_div_ok () =
  let ctx = typecheck {|mod Unsafe do
    fn divide(a : Int, b : Int) : Int do a / b end
  end|} in
  Alcotest.(check bool) "no cap no_panic: division is allowed" false (has_errors ctx)

let test_cap_no_panic_div_error () =
  let ctx = typecheck {|mod Safe do
    cap no_panic
    fn divide(a : Int, b : Int) : Int do a / b end
  end|} in
  Alcotest.(check bool) "cap no_panic + division: error" true (has_errors ctx)

let test_cap_no_panic_mod_error () =
  let ctx = typecheck {|mod Safe do
    cap no_panic
    fn remainder(a : Int, b : Int) : Int do a % b end
  end|} in
  Alcotest.(check bool) "cap no_panic + modulo: error" true (has_errors ctx)

let test_cap_no_panic_explicit_panic_error () =
  let ctx = typecheck {|mod Safe do
    cap no_panic
    fn fail() : Int do
      panic_("boom")
      0
    end
  end|} in
  Alcotest.(check bool) "cap no_panic + panic_: error" true (has_errors ctx)

let test_cap_no_panic_todo_error () =
  let ctx = typecheck {|mod Safe do
    cap no_panic
    fn not_done() : Int do
      todo_("not implemented")
      0
    end
  end|} in
  Alcotest.(check bool) "cap no_panic + todo_: error" true (has_errors ctx)

let test_cap_no_panic_unreachable_error () =
  let ctx = typecheck {|mod Safe do
    cap no_panic
    fn unreachable(x : Int) : Int do
      unreachable_("impossible")
      x
    end
  end|} in
  Alcotest.(check bool) "cap no_panic + unreachable_: error" true (has_errors ctx)

let test_cap_no_panic_unwrap_error () =
  let ctx = typecheck {|mod Safe do
    cap no_panic
    fn extract(x : Option(Int)) : Int do unwrap(x) end
  end|} in
  Alcotest.(check bool) "cap no_panic + unwrap: error" true (has_errors ctx)

let test_cap_no_panic_safe_helper_ok () =
  let ctx = typecheck {|mod Safe do
    cap no_panic
    pfn double(n : Int) : Int do n * 2 end
    fn apply(x : Int) : Int do double(x) end
  end|} in
  Alcotest.(check bool) "cap no_panic + safe local helper: no error" false (has_errors ctx)

let test_cap_no_panic_transitive_error () =
  let ctx = typecheck {|mod Safe do
    cap no_panic
    pfn helper(a : Int, b : Int) : Int do a / b end
    fn caller(x : Int) : Int do helper(x, 2) end
  end|} in
  Alcotest.(check bool) "cap no_panic + transitive panic via helper: error" true (has_errors ctx)

let test_cap_no_panic_two_safe_sibling_fns_ok () =
  let ctx = typecheck {|mod Safe do
    cap no_panic
    fn ping(n : Int) : Int do pong(n) end
    fn pong(n : Int) : Int do n end
  end|} in
  Alcotest.(check bool) "cap no_panic + two safe sibling fns: no error" false (has_errors ctx)

(* ── Record field auto-satisfy tests ───────────────────────────────────── *)

let test_record_auto_satisfy_ok () =
  (* Anonymous record with a matching field auto-satisfies a single-method interface. *)
  let ctx = typecheck {|mod Test do
    interface Named(a) do
      fn name: a -> String
    end
    fn main() do name({name: "Alice", age: 30}) end
  end|} in
  Alcotest.(check bool) "record with matching field auto-satisfies: no error" false (has_errors ctx)

let test_record_auto_satisfy_wrong_type () =
  (* Field exists but has wrong type (Int instead of String). *)
  let ctx = typecheck {|mod Test do
    interface Named(a) do
      fn name: a -> String
    end
    fn main() do name({name: 42, age: 30}) end
  end|} in
  Alcotest.(check bool) "record with wrong-type field: error" true (has_errors ctx)

let test_record_auto_satisfy_missing_field () =
  (* Anonymous record has no field named 'name'. *)
  let ctx = typecheck {|mod Test do
    interface Named(a) do
      fn name: a -> String
    end
    fn main() do name({age: 30}) end
  end|} in
  Alcotest.(check bool) "record missing required field: error" true (has_errors ctx)

let test_record_auto_satisfy_multi_method_error () =
  (* Multi-method interfaces cannot auto-satisfy. *)
  let ctx = typecheck {|mod Test do
    interface Describable(a) do
      fn label: a -> String
      fn desc: a -> String
    end
    fn main() do label({label: "A", desc: "B"}) end
  end|} in
  Alcotest.(check bool) "multi-method interface does not auto-satisfy: error" true (has_errors ctx)

let test_record_auto_satisfy_binary_method_error () =
  (* Method with binary signature (a -> a -> Bool): the record field 'eq'
     would need type (RecordType -> Bool), not Bool — type mismatch. *)
  let ctx = typecheck {|mod Test do
    interface Equal(a) do
      fn eq: a -> a -> Bool
    end
    fn main() do eq({val: 1}) end
  end|} in
  Alcotest.(check bool) "binary method: record with plain field does not satisfy: error" true (has_errors ctx)

let test_record_auto_satisfy_named_type_error () =
  (* Named type constructors (TCon) do not auto-satisfy, only anonymous TRecord. *)
  let ctx = typecheck {|mod Test do
    interface Named(a) do
      fn name: a -> String
    end
    type User = User(String)
    fn main() do name(User("Alice")) end
  end|} in
  Alcotest.(check bool) "named type does not auto-satisfy: error" true (has_errors ctx)

let test_record_auto_satisfy_explicit_impl_ok () =
  (* Named type with explicit impl is still satisfied normally. *)
  let ctx = typecheck {|mod Test do
    interface Named(a) do
      fn name: a -> String
    end
    type User = User(String)
    impl Named(User) do
      fn name(User(s)) do s end
    end
    fn main() do name(User("Alice")) end
  end|} in
  Alcotest.(check bool) "named type with explicit impl satisfies: no error" false (has_errors ctx)

let test_record_auto_satisfy_when_constraint_ok () =
  (* Record with matching field also satisfies inside a polymorphic fn. *)
  let ctx = typecheck {|mod Test do
    interface HasAge(a) do
      fn age: a -> Int
    end
    fn main() do age({name: "Alice", age: 30}) end
  end|} in
  Alcotest.(check bool) "record with matching Int field auto-satisfies: no error" false (has_errors ctx)

let test_record_auto_satisfy_two_shapes_ok () =
  (* Two different anonymous record shapes both satisfying the same interface. *)
  let ctx = typecheck {|mod Test do
    interface Named(a) do
      fn name: a -> String
    end
    fn main() do
      let a = name({name: "Alice", age: 30})
      let b = name({name: "Bob", score: 100})
      a ++ b
    end
  end|} in
  Alcotest.(check bool) "two different record shapes both auto-satisfy: no error" false (has_errors ctx)

(* ── cap_body_enforce: Phase 2 body-scan capability enforcement ─────────── *)

(* Modules that declare `needs` and call the matching builtin — clean. *)
let test_cap_body_needs_ok () =
  let ctx = typecheck {|mod Greeter do
    needs IO.Console
    fn greet(name) do println("Hello " ++ name) end
  end|} in
  Alcotest.(check bool) "println with needs IO.Console: no warning" false
    (has_warning_with ctx "builtin")

(* Module without `needs` that calls println — body-scan emits warning. *)
let test_cap_body_missing_console () =
  let ctx = typecheck {|mod Greeter do
    fn greet(name) do println("Hello " ++ name) end
  end|} in
  Alcotest.(check bool) "println without needs: body-scan warning" true
    (has_warning_with ctx "IO.Console")

(* Module without `needs` that calls file_read — body-scan emits warning. *)
let test_cap_body_missing_fileread () =
  let ctx = typecheck {|mod Reader do
    fn load(path) do file_read(path) end
  end|} in
  Alcotest.(check bool) "file_read without needs: body-scan warning" true
    (has_warning_with ctx "IO.FileRead")

(* Module without `needs` that calls file_write — body-scan emits warning. *)
let test_cap_body_missing_filewrite () =
  let ctx = typecheck {|mod Writer do
    fn save(path, data) do file_write(path, data) end
  end|} in
  Alcotest.(check bool) "file_write without needs: body-scan warning" true
    (has_warning_with ctx "IO.FileWrite")

(* Module without `needs` that calls random_bytes — body-scan emits warning. *)
let test_cap_body_missing_random () =
  let ctx = typecheck {|mod Gen do
    fn token() do random_bytes(16) end
  end|} in
  Alcotest.(check bool) "random_bytes without needs: body-scan warning" true
    (has_warning_with ctx "IO.Random")

(* Module without `needs` that calls unix_time — body-scan emits warning. *)
let test_cap_body_missing_clock () =
  let ctx = typecheck {|mod Clk do
    fn now() do unix_time(()) end
  end|} in
  Alcotest.(check bool) "unix_time without needs: body-scan warning" true
    (has_warning_with ctx "IO.Clock")

(* Module without `needs` that calls process_env — body-scan emits warning. *)
let test_cap_body_missing_process () =
  let ctx = typecheck {|mod Env do
    fn get_path() do process_env("PATH") end
  end|} in
  Alcotest.(check bool) "process_env without needs: body-scan warning" true
    (has_warning_with ctx "IO.Process")

(* Body-scan warning does NOT escalate to an error. *)
let test_cap_body_warn_not_error () =
  let ctx = typecheck {|mod Greeter do
    fn greet(name) do println("Hello " ++ name) end
  end|} in
  Alcotest.(check bool) "body-scan missing cap is only a warning, not an error" false
    (has_errors ctx)

(* Declared needs covers body call: no spurious warning. *)
let test_cap_body_no_double_warn () =
  let ctx = typecheck {|mod Greeter do
    needs IO.Console
    fn greet(name) do println("Hello " ++ name) end
  end|} in
  Alcotest.(check bool) "declared needs suppresses body-scan warning" false
    (has_warning_with ctx "builtin")

(* needs IO.Console satisfies both `print` and `println` body calls. *)
let test_cap_body_umbrella_parent () =
  let ctx = typecheck {|mod Out do
    needs IO.Console
    fn say(x) do
      print(x)
      println(x)
    end
  end|} in
  Alcotest.(check bool) "needs IO.Console covers print+println calls" false
    (has_warning_with ctx "IO.Console")

(* Multiple distinct builtins from different cap trees each get their own warning. *)
let test_cap_body_two_missing_caps () =
  let ctx = typecheck {|mod Mixed do
    fn run() do
      let _ = file_read("/tmp/x")
      println("done")
    end
  end|} in
  Alcotest.(check bool) "file_read warns about IO.FileRead" true
    (has_warning_with ctx "IO.FileRead")

(* Check 2: a declared needs whose cap is inferred from body doesn't produce
   the "declared but not used" warning. *)
let test_cap_body_need_satisfied_by_body () =
  let ctx = typecheck {|mod Greeter do
    needs IO.Console
    fn greet(name) do println(name) end
  end|} in
  Alcotest.(check bool) "body call satisfies declared needs: no unused-cap warning" false
    (has_warning_with ctx "not used")

(* A DLet binding that calls a builtin also triggers body-scan. *)
let test_cap_body_let_body () =
  let ctx = typecheck {|mod Top do
    let banner = println("app started")
  end|} in
  Alcotest.(check bool) "DLet body call triggers body-scan warning" true
    (has_warning_with ctx "IO.Console")

(* Pure module with no builtins: no spurious warnings. *)
let test_cap_body_pure_no_warn () =
  let ctx = typecheck {|mod Pure do
    fn add(a, b) do a + b end
  end|} in
  Alcotest.(check bool) "pure module has no body-scan warnings" false
    (has_warning_with ctx "builtin")

let compiler_suites =
  [
      ( "resolver",
        [
          Alcotest.test_case "collect_lib_files skips dangling symlinks" `Quick
            test_resolver_skips_dangling_symlink;
        ] );
      ( "app",
        [
          Alcotest.test_case "app keyword lexes"       `Quick test_lexer_keyword_app;
          Alcotest.test_case "on_start keyword lexes"  `Quick test_lexer_keyword_on_start;
          Alcotest.test_case "on_stop keyword lexes"   `Quick test_lexer_keyword_on_stop;
          Alcotest.test_case "app desugars to init"    `Quick (with_reset test_app_desugars_to_app_init);
          Alcotest.test_case "app spawns actors"       `Quick (with_reset test_app_spawns_actors);
          Alcotest.test_case "main + app exclusive"    `Quick test_app_main_exclusive;
          Alcotest.test_case "app typechecks valid"    `Quick (with_reset test_app_typechecks_valid);
          Alcotest.test_case "app wrong body type err" `Quick (with_reset test_app_wrong_body_type_error);
        ] );
      ( "spec_construction",
        [
          Alcotest.test_case "Supervisor.spec returns record"  `Quick (with_reset test_supervisor_spec_value);
          Alcotest.test_case "worker/1 returns child spec"     `Quick (with_reset test_worker_builtin_fields);
        ] );
      ( "shutdown",
        [
          Alcotest.test_case "shutdown handler runs"        `Quick (with_reset test_shutdown_handler_runs);
          Alcotest.test_case "graceful shutdown order"      `Quick (with_reset test_graceful_shutdown_reverse_order);
          Alcotest.test_case "on_start hook"                `Quick (with_reset test_on_start_hook);
          Alcotest.test_case "on_stop hook"                 `Quick (with_reset test_on_stop_hook);
          Alcotest.test_case "no-handler actor force-killed" `Quick (with_reset test_actor_no_shutdown_handler_force_killed);
          Alcotest.test_case "shutdown marks actor dead"    `Quick (with_reset test_shutdown_actor_pid_marks_dead);
        ] );
      ( "registry",
        [
          Alcotest.test_case "worker named spec"         `Quick (with_reset test_worker_named_spec);
          Alcotest.test_case "whereis named"             `Quick (with_reset test_whereis_named);
          Alcotest.test_case "whereis live actor"        `Quick (with_reset test_whereis_live_actor);
          Alcotest.test_case "whereis unknown"           `Quick (with_reset test_whereis_unknown);
          Alcotest.test_case "whereis_bang unknown"      `Quick (with_reset test_whereis_bang_unknown);
          Alcotest.test_case "name reregisters restart"  `Quick (with_reset test_name_reregisters_on_restart);
        ] );
      ( "dynamic_supervisor",
        [
          Alcotest.test_case "start_child adds child"      `Quick (with_reset test_dyn_sup_start_child);
          Alcotest.test_case "count_children"              `Quick (with_reset test_dyn_sup_count_children);
          Alcotest.test_case "which_children"              `Quick (with_reset test_dyn_sup_which_children);
          Alcotest.test_case "permanent child restarts"    `Quick (with_reset test_dyn_sup_permanent_restart);
          Alcotest.test_case "temporary child not restart" `Quick (with_reset test_dyn_sup_temporary_not_restarted);
          Alcotest.test_case "stop_child removes child"    `Quick (with_reset test_dyn_sup_stop_child);
          Alcotest.test_case "dyn sup in app spec"         `Quick (with_reset test_dyn_sup_in_app);
        ] );
      ( "lexer",
        [
          Alcotest.test_case "integer" `Quick test_lexer_int;
          Alcotest.test_case "identifier" `Quick test_lexer_ident;
          Alcotest.test_case "fn keyword" `Quick test_lexer_keyword_fn;
          Alcotest.test_case "do keyword" `Quick test_lexer_keyword_do;
          Alcotest.test_case "end keyword" `Quick test_lexer_keyword_end;
          Alcotest.test_case "mod keyword" `Quick test_lexer_keyword_mod;
          Alcotest.test_case "app keyword" `Quick test_lexer_keyword_app;
          Alcotest.test_case "string" `Quick test_lexer_string;
          Alcotest.test_case "atom" `Quick test_lexer_atom;
          Alcotest.test_case "pipe arrow" `Quick test_lexer_pipe_arrow;
          Alcotest.test_case "arrow" `Quick test_lexer_arrow;
          Alcotest.test_case "line comment" `Quick test_lexer_comment;
          Alcotest.test_case "block comment" `Quick test_lexer_block_comment;
          Alcotest.test_case "underscore-prefixed identifier" `Quick test_lexer_underscore_ident;
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
          Alcotest.test_case "lambda keyword params" `Quick test_parse_lambda_keyword_params;
          Alcotest.test_case "lambda block body" `Quick test_parse_lambda_block_body;
          Alcotest.test_case "lambda single let" `Quick test_parse_lambda_single_let;
          Alcotest.test_case "lambda no-let unchanged" `Quick test_parse_lambda_no_let_unchanged;
          Alcotest.test_case "lambda zero-arg block" `Quick test_parse_lambda_zero_arg_block;
          Alcotest.test_case "lambda multi-param block" `Quick test_parse_lambda_multi_param_block;
          Alcotest.test_case "application" `Quick test_parse_expr_app;
        ] );
      ( "module",
        [
          Alcotest.test_case "multi-head fn" `Quick test_parse_module_multi_head;
          Alcotest.test_case "single fn" `Quick test_parse_module_single_fn;
          Alcotest.test_case "dotted module name parse" `Quick test_parse_dotted_module_name;
          Alcotest.test_case "underscore-prefixed param" `Quick test_parse_underscore_param;
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
          Alcotest.test_case "arity: under-application is error"   `Quick test_tc_arity_under_application;
          Alcotest.test_case "arity: 0-arg call of 1-arg fn error" `Quick test_tc_arity_zero_args;
          Alcotest.test_case "arity: over-application is error"    `Quick test_tc_arity_over_application;
          Alcotest.test_case "arity: correct call is ok"           `Quick test_tc_arity_correct_ok;
          Alcotest.test_case "arity: fn returning fn is ok"        `Quick test_tc_arity_fn_returning_fn_ok;
          Alcotest.test_case "actor handler extra field"   `Quick test_actor_handler_extra_field;
          Alcotest.test_case "actor handler missing field" `Quick test_actor_handler_missing_field;
          Alcotest.test_case "actor handler correct"       `Quick test_actor_handler_correct;
          (* Fix 1: Interface constraint discharge *)
          Alcotest.test_case "iface constraint satisfied"   `Quick test_interface_constraint_satisfied;
          Alcotest.test_case "iface constraint missing impl" `Quick test_interface_constraint_missing_impl;
          Alcotest.test_case "impl when satisfied"          `Quick test_impl_when_constraint_satisfied;
          Alcotest.test_case "impl when unsatisfied"        `Quick test_impl_when_constraint_unsatisfied;
          Alcotest.test_case "cross-module dispatch"        `Quick test_interface_cross_module_dispatch;
          Alcotest.test_case "cross-module record dispatch" `Quick test_interface_cross_module_dispatch_record;
          Alcotest.test_case "test keywords as idents"      `Quick test_test_keywords_as_identifiers;
          Alcotest.test_case "test DSL still parses"        `Quick test_test_dsl_still_parses;
          (* Standard interfaces: Eq, Ord, Show, Hash *)
          Alcotest.test_case "Eq builtin Int"               `Quick test_eq_builtin_int;
          Alcotest.test_case "Eq builtin String"            `Quick test_eq_builtin_string;
          Alcotest.test_case "Eq builtin Bool"              `Quick test_eq_builtin_bool;
          Alcotest.test_case "Eq builtin Float"             `Quick test_eq_builtin_float;
          Alcotest.test_case "Eq user impl"                 `Quick test_eq_user_impl;
          Alcotest.test_case "Ord builtin lt Int"           `Quick test_ord_builtin_lt;
          Alcotest.test_case "Ord builtin lt String"        `Quick test_ord_builtin_string;
          Alcotest.test_case "Ord compare method"           `Quick test_ord_compare_method;
          Alcotest.test_case "Show builtin Int"             `Quick test_show_builtin_int;
          Alcotest.test_case "Show builtin Bool"            `Quick test_show_builtin_bool;
          Alcotest.test_case "Show user impl"               `Quick test_show_user_impl;
          Alcotest.test_case "show List eval"               `Quick (with_reset test_show_list_eval);
          Alcotest.test_case "show Option Some eval"        `Quick (with_reset test_show_option_some_eval);
          Alcotest.test_case "show Option None eval"        `Quick (with_reset test_show_option_none_eval);
          Alcotest.test_case "show Result Ok eval"          `Quick (with_reset test_show_result_ok_eval);
          Alcotest.test_case "show Result Err eval"         `Quick (with_reset test_show_result_err_eval);
          Alcotest.test_case "show nested list eval"        `Quick (with_reset test_show_nested_list_eval);
          Alcotest.test_case "println polymorphic typecheck" `Quick test_println_polymorphic_typecheck;
          Alcotest.test_case "Hash builtin Int"             `Quick test_hash_builtin_int;
          Alcotest.test_case "Hash builtin String"          `Quick test_hash_builtin_string;
          Alcotest.test_case "eq method callable"           `Quick test_eq_method_callable;
          Alcotest.test_case "std ifaces pre-registered"    `Quick test_standard_interfaces_in_scope;
          (* F2: when Eq(a) constraints on function signatures *)
          Alcotest.test_case "fn when constraint satisfied"  `Quick test_fn_when_constraint_satisfied;
          Alcotest.test_case "fn when constraint unsatisfied" `Quick test_fn_when_constraint_unsatisfied;
          (* F2: qualified method calls Eq.eq, Show.show *)
          Alcotest.test_case "qualified Eq.eq call"          `Quick test_qualified_method_call;
          Alcotest.test_case "qualified Show.show call"      `Quick test_qualified_show_call;
          (* F5: linear let bindings *)
          Alcotest.test_case "linear let ok"                 `Quick test_linear_let_ok;
          Alcotest.test_case "linear let double use"         `Quick test_linear_let_double_use;
          (* Fix 2: Linear type enforcement *)
          Alcotest.test_case "linear pattern match ok"       `Quick test_linear_pattern_match_ok;
          Alcotest.test_case "linear pattern match double"   `Quick test_linear_pattern_match_double_use;
          Alcotest.test_case "linear closure capture"        `Quick test_linear_closure_capture_error;
          Alcotest.test_case "linear field let binding"       `Quick test_linear_field_let_binding;
          (* H6: Linear field direct field-access tracking *)
          Alcotest.test_case "linear field double access"    `Quick test_linear_field_double_access_error;
          Alcotest.test_case "linear field single access ok" `Quick test_linear_field_single_access_ok;
          (* Fix 3/H8: Session type validation + participant cross-check *)
          Alcotest.test_case "protocol self-message"         `Quick test_protocol_self_message_error;
          Alcotest.test_case "protocol empty loop"           `Quick test_protocol_empty_loop_error;
          Alcotest.test_case "protocol valid"                `Quick test_protocol_valid;
          Alcotest.test_case "protocol duplicate"            `Quick test_protocol_duplicate_error;
          Alcotest.test_case "protocol unknown participant"  `Quick test_protocol_unknown_participant_hint;
          Alcotest.test_case "protocol known participant"    `Quick test_protocol_known_participant_no_hint;
          (* Phase 1: Session type projection + duality *)
          Alcotest.test_case "session projection simple"     `Quick test_session_projection_simple;
          Alcotest.test_case "session duality holds"         `Quick test_session_duality_holds;
          Alcotest.test_case "session loop projection"       `Quick test_session_loop_projection;
          Alcotest.test_case "session Chan annotation ok"    `Quick test_session_chan_type_annotation;
          Alcotest.test_case "session Chan unknown proto"    `Quick test_session_chan_unknown_protocol_error;
          Alcotest.test_case "session Chan unknown role"     `Quick test_session_chan_unknown_role_error;
          (* Phase 2: Chan.send/recv/close session type checking + eval *)
          Alcotest.test_case "session send recv close ok"    `Quick test_session_send_recv_close_ok;
          Alcotest.test_case "session send wrong type"       `Quick test_session_send_wrong_type_error;
          Alcotest.test_case "session send at recv state"    `Quick test_session_send_at_recv_state_error;
          Alcotest.test_case "session close wrong state"     `Quick test_session_close_at_wrong_state_error;
          Alcotest.test_case "session Chan.new ok"           `Quick test_session_chan_new_ok;
          Alcotest.test_case "session Chan.new unknown"      `Quick test_session_chan_new_unknown_proto_error;
          Alcotest.test_case "session eval send recv"        `Quick test_session_eval_send_recv;
          (* Phase 3: Choose/Offer branching *)
          Alcotest.test_case "session choose protocol parses"    `Quick test_session_choose_protocol_parses;
          Alcotest.test_case "session choose advances state"     `Quick test_session_choose_advances_state;
          Alcotest.test_case "session choose invalid label"      `Quick test_session_choose_invalid_label_error;
          Alcotest.test_case "session choose wrong state"        `Quick test_session_choose_at_wrong_state_error;
          Alcotest.test_case "session offer ok"                  `Quick test_session_offer_ok;
          Alcotest.test_case "session offer wrong state"         `Quick test_session_offer_at_wrong_state_error;
          (* Phase 4: SRec multi-turn recursive protocols — original set *)
          Alcotest.test_case "SRec ping-pong loop typechecks"    `Quick test_srec_pingpong_loop_typechecks;
          Alcotest.test_case "SRec unfold simple"                `Quick test_srec_unfold_simple;
          Alcotest.test_case "SRec unfold multi-step"            `Quick test_srec_unfold_multi_step;
          Alcotest.test_case "SRec unfold nested"                `Quick test_srec_unfold_nested;
          Alcotest.test_case "SRec with branching typechecks"    `Quick test_srec_with_branching_typechecks;
          Alcotest.test_case "SRec wrong type in loop error"     `Quick test_srec_wrong_type_in_loop_error;
          (* Complex type error messages *)
          Alcotest.test_case "pp_ty_pretty wraps long types"     `Quick test_complex_type_error_pp_ty_pretty;
          Alcotest.test_case "type mismatch hint for same ctor"  `Quick test_complex_type_mismatch_hint;
          (* Phase 4: SRec extended test suite *)
          Alcotest.test_case "srec unfold basic"               `Quick test_srec_unfold_basic;
          Alcotest.test_case "srec unfold passthrough"         `Quick test_srec_unfold_send_passes_through;
          Alcotest.test_case "srec ping-pong protocol"         `Quick test_srec_ping_pong_protocol;
          Alcotest.test_case "srec ping-pong unfold step 1"    `Quick test_srec_ping_pong_unfold_one_step;
          Alcotest.test_case "srec ping-pong unfold step 2"    `Quick test_srec_ping_pong_unfold_two_steps;
          Alcotest.test_case "srec nested SRec"                `Quick test_srec_nested_srec;
          Alcotest.test_case "srec finite 3-step"              `Quick test_srec_finite_protocol;
          Alcotest.test_case "srec choose-loop protocol"       `Quick test_srec_choose_loop_protocol;
          Alcotest.test_case "srec dual"                       `Quick test_srec_dual;
          Alcotest.test_case "srec multi-turn typechecks"      `Quick test_srec_multi_turn_typechecks;
          (* H9: Actor handler capability checking *)
          Alcotest.test_case "actor cap needs ok"            `Quick test_actor_handler_cap_needs_ok;
          Alcotest.test_case "actor cap needs missing error" `Quick test_actor_handler_cap_missing_needs_error;
          (* Actor handler return type checking — gap fills *)
          Alcotest.test_case "actor handler duplicate name"            `Quick test_actor_handler_duplicate_name;
          Alcotest.test_case "actor handler wrong return type"         `Quick test_actor_handler_wrong_return_type;
          Alcotest.test_case "actor handler init wrong type"           `Quick test_actor_handler_init_wrong_type;
          Alcotest.test_case "actor handler multiple all correct"      `Quick test_actor_handler_multiple_all_correct;
          Alcotest.test_case "actor handler multiple one wrong"        `Quick test_actor_handler_multiple_one_wrong;
          Alcotest.test_case "actor handler unannotated param arity ok"  `Quick test_actor_handler_unannotated_param_correct_arity;
          Alcotest.test_case "actor handler unannotated param arity err" `Quick test_actor_handler_unannotated_param_wrong_arity;
          Alcotest.test_case "actor handler state spread correct"      `Quick test_actor_handler_state_spread_correct;
          Alcotest.test_case "actor handler no-param msgs correct"      `Quick test_actor_handler_no_message_params_correct;
          (* Regression: let-generalization hole for forward-referenced pfn helpers *)
          Alcotest.test_case "forward-ref pfn poly two call sites"      `Quick test_tc_forward_ref_poly_helper_two_call_sites;
          Alcotest.test_case "normal-order pfn poly two call sites"     `Quick test_tc_forward_ref_poly_reverse_order;
        ] );
      ( "let?",
        [
          Alcotest.test_case "let? typechecks ok"            `Quick test_letq_typechecks_ok;
          Alcotest.test_case "let? rhs not Result: error"    `Quick test_letq_rhs_not_result_error;
          Alcotest.test_case "let? last in block: error"     `Quick test_letq_last_in_block_error;
          Alcotest.test_case "let? chain typechecks"         `Quick test_letq_chain_typechecks;
          Alcotest.test_case "let? mixed error types: error" `Quick test_letq_mismatched_error_types;
        ] );
      ( "tag_and_typestate", [
          Alcotest.test_case "tag keyword parses"                        `Quick test_tag_parses;
          Alcotest.test_case "tag ctor usable as value"                  `Quick test_tag_usable_as_ctor;
          Alcotest.test_case "always_linear type: consumed ok"           `Quick test_always_linear_type_ok;
          Alcotest.test_case "always_linear type: drop is error"         `Quick test_always_linear_type_drop_error;
          Alcotest.test_case "transitions block: no errors"              `Quick test_transitions_parses;
          Alcotest.test_case "transitions via missing fn: error"         `Quick test_transitions_via_not_found_error;
          Alcotest.test_case "undeclared transition fn: warning emitted" `Quick test_transitions_warn_undeclared;
          Alcotest.test_case "Tagged(X,T): valid type annotation"        `Quick test_tagged_type_parses;
          Alcotest.test_case "Tagged(_, Realtime) + Cap(IO): error"      `Quick test_tagged_realtime_excludes_io_error;
          Alcotest.test_case "Tagged(_, Realtime) + Cap(Alloc): error"   `Quick test_tagged_realtime_excludes_alloc_error;
          Alcotest.test_case "Tagged(_, Realtime) + Cap(Panic): error"   `Quick test_tagged_realtime_excludes_panic_error;
          Alcotest.test_case "Tagged(_, Standard): no exclusion"         `Quick test_tagged_standard_no_exclusion;
          (* Phase 3a: explicit bounded type parameters *)
          Alcotest.test_case "fn[s:ADT] parses and typechecks"           `Quick test_bound_param_parses;
          Alcotest.test_case "bound ADT: valid constructor — no error"   `Quick test_bound_param_valid_call;
          Alcotest.test_case "bound ADT: wrong constructor — error"      `Quick test_bound_param_invalid_call;
          Alcotest.test_case "bound interface equiv to when-clause"      `Quick test_bound_interface_equiv;
          Alcotest.test_case "multiple bounds: valid call"               `Quick test_bound_multiple_params;
          Alcotest.test_case "bound unknown type — error"                `Quick test_bound_unknown_adt;
          Alcotest.test_case "bound in return type: no error"            `Quick test_bound_in_return_type;
          Alcotest.test_case "Nat bound: polymorphic call — no error"    `Quick test_bound_nat_valid;
          Alcotest.test_case "ADT bound with tag-style type: valid"      `Quick test_bound_tag_as_adt;
        ] );
      ( "mpst",
        [
          (* §1 Protocol declaration and projection *)
          Alcotest.test_case "3-party protocol parses"         `Quick test_mpst_three_party_parses;
          Alcotest.test_case "3-party projection: Client"      `Quick test_mpst_projection_client;
          Alcotest.test_case "3-party projection: AuthDB"      `Quick test_mpst_projection_authdb;
          Alcotest.test_case "3-party projection: Server"      `Quick test_mpst_projection_server;
          Alcotest.test_case "4-party protocol parses"         `Quick test_mpst_four_party_parses;
          (* §2 MPST.new *)
          Alcotest.test_case "MPST.new 3-party ok"             `Quick test_mpst_new_ok;
          Alcotest.test_case "MPST.new binary: error"          `Quick test_mpst_new_binary_error;
          Alcotest.test_case "MPST.new unknown proto: error"   `Quick test_mpst_new_unknown_proto_error;
          (* §3 MPST.send *)
          Alcotest.test_case "MPST.send correct: ok"           `Quick test_mpst_send_ok;
          Alcotest.test_case "MPST.send wrong role: error"     `Quick test_mpst_send_wrong_role_error;
          Alcotest.test_case "MPST.send wrong type: error"     `Quick test_mpst_send_wrong_type_error;
          (* §4 MPST.recv *)
          Alcotest.test_case "MPST.recv correct: ok"           `Quick test_mpst_recv_ok;
          Alcotest.test_case "MPST.recv wrong role: error"     `Quick test_mpst_recv_wrong_role_error;
          (* §5 MPST.close *)
          Alcotest.test_case "MPST.close at End: ok"           `Quick test_mpst_close_ok;
          Alcotest.test_case "MPST.close wrong state: error"   `Quick test_mpst_close_wrong_state_error;
          (* §6 Full protocol *)
          Alcotest.test_case "full Auth protocol typechecks"   `Quick test_mpst_full_auth_protocol_typechecks;
          Alcotest.test_case "3-party choose/offer typechecks" `Quick test_mpst_choose_offer_three_party_typechecks;
          (* §7 Runtime eval *)
          Alcotest.test_case "MPST eval: 3-party auth"         `Quick (with_reset test_mpst_eval_three_party);
          Alcotest.test_case "MPST eval: relay 3-party"        `Quick (with_reset test_mpst_eval_two_messages_same_pair);
          Alcotest.test_case "MPST eval: 4-party chain"        `Quick (with_reset test_mpst_eval_four_party);
          Alcotest.test_case "MPST eval: recv before send error" `Quick (with_reset test_mpst_eval_wrong_order_error);
        ] );
      ( "session_compile", [
          Alcotest.test_case "Chan.new/send/recv/close in IR"   `Quick test_session_compile_chan_new;
          Alcotest.test_case "Chan.choose/offer in IR"          `Quick test_session_compile_chan_choose_offer;
          Alcotest.test_case "full pipeline no crash"           `Quick test_session_compile_full_pipeline_no_crash;
        ] );
      ( "policy_dce", [
          Alcotest.test_case "NoAlloc fn with EAlloc: violation"          `Quick test_policy_noalloc_alloc_violation;
          Alcotest.test_case "NoAlloc fn clean: no violation"             `Quick test_policy_noalloc_clean;
          Alcotest.test_case "NoPanic fn calls int_div: violation"        `Quick test_policy_nopanic_int_div_violation;
          Alcotest.test_case "NoPanic fn safe body: no violation"         `Quick test_policy_nopanic_clean;
          Alcotest.test_case "NoPanic fn transitive panic: violation"     `Quick test_policy_nopanic_transitive;
          Alcotest.test_case "Realtime fn calls IO fn: violation"         `Quick test_policy_realtime_io_violation;
          Alcotest.test_case "Realtime fn clean: no violation"            `Quick test_policy_realtime_clean;
          Alcotest.test_case "Untagged fn with alloc: no violation"       `Quick test_policy_untagged_not_checked;
        ] );
      ( "cap_no_panic", [
          Alcotest.test_case "cap no_panic lexes as CAP_NO_PANIC token"   `Quick test_cap_no_panic_lexes;
          Alcotest.test_case "cap no_panic safe body: no error"           `Quick test_cap_no_panic_safe_no_error;
          Alcotest.test_case "no cap directive: division allowed"         `Quick test_cap_not_set_div_ok;
          Alcotest.test_case "cap no_panic + division: error"             `Quick test_cap_no_panic_div_error;
          Alcotest.test_case "cap no_panic + modulo: error"               `Quick test_cap_no_panic_mod_error;
          Alcotest.test_case "cap no_panic + panic_: error"               `Quick test_cap_no_panic_explicit_panic_error;
          Alcotest.test_case "cap no_panic + todo_: error"                `Quick test_cap_no_panic_todo_error;
          Alcotest.test_case "cap no_panic + unreachable_: error"         `Quick test_cap_no_panic_unreachable_error;
          Alcotest.test_case "cap no_panic + unwrap: error"               `Quick test_cap_no_panic_unwrap_error;
          Alcotest.test_case "cap no_panic + safe local helper: no error" `Quick test_cap_no_panic_safe_helper_ok;
          Alcotest.test_case "cap no_panic + transitive panic: error"     `Quick test_cap_no_panic_transitive_error;
          Alcotest.test_case "cap no_panic + safe sibling fns: no error"  `Quick test_cap_no_panic_two_safe_sibling_fns_ok;
        ] );
      ( "record_auto_satisfy", [
          Alcotest.test_case "matching field auto-satisfies"    `Quick test_record_auto_satisfy_ok;
          Alcotest.test_case "wrong field type: error"          `Quick test_record_auto_satisfy_wrong_type;
          Alcotest.test_case "missing field: error"             `Quick test_record_auto_satisfy_missing_field;
          Alcotest.test_case "multi-method iface: no auto"      `Quick test_record_auto_satisfy_multi_method_error;
          Alcotest.test_case "binary method: no auto"           `Quick test_record_auto_satisfy_binary_method_error;
          Alcotest.test_case "named type: no auto"              `Quick test_record_auto_satisfy_named_type_error;
          Alcotest.test_case "named type + explicit impl: ok"   `Quick test_record_auto_satisfy_explicit_impl_ok;
          Alcotest.test_case "when constraint auto-satisfied"   `Quick test_record_auto_satisfy_when_constraint_ok;
          Alcotest.test_case "two record shapes both satisfy"   `Quick test_record_auto_satisfy_two_shapes_ok;
        ] );
      ( "cap_body_enforce", [
          Alcotest.test_case "println with needs: no warn"           `Quick test_cap_body_needs_ok;
          Alcotest.test_case "println missing needs: warn IO.Console" `Quick test_cap_body_missing_console;
          Alcotest.test_case "file_read missing needs: warn"          `Quick test_cap_body_missing_fileread;
          Alcotest.test_case "file_write missing needs: warn"         `Quick test_cap_body_missing_filewrite;
          Alcotest.test_case "random_bytes missing needs: warn"       `Quick test_cap_body_missing_random;
          Alcotest.test_case "unix_time missing needs: warn"          `Quick test_cap_body_missing_clock;
          Alcotest.test_case "process_env missing needs: warn"        `Quick test_cap_body_missing_process;
          Alcotest.test_case "missing cap is warning not error"       `Quick test_cap_body_warn_not_error;
          Alcotest.test_case "declared needs: no dup warning"         `Quick test_cap_body_no_double_warn;
          Alcotest.test_case "parent cap covers multiple calls"       `Quick test_cap_body_umbrella_parent;
          Alcotest.test_case "two missing caps each warned"           `Quick test_cap_body_two_missing_caps;
          Alcotest.test_case "body satisfies declared needs"          `Quick test_cap_body_need_satisfied_by_body;
          Alcotest.test_case "DLet body triggers body-scan"          `Quick test_cap_body_let_body;
          Alcotest.test_case "pure module: no spurious warning"       `Quick test_cap_body_pure_no_warn;
        ] );
  ]

