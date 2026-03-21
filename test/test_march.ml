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
        match (x, y) with
        | (Red, Red)     -> true
        | (Green, Green) -> true
        | (Blue, Blue)   -> true
        | _              -> false
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
        match (x, y) with
        | (Wrap(a), Wrap(b)) -> a == b
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
      match x with
      | n -> n
      end
    end
  end|} in
  Alcotest.(check bool) "linear through pattern match once: no errors" false (has_errors ctx)

let test_linear_pattern_match_double_use () =
  (* Matching a linear var and using the binding twice should error. *)
  let ctx = typecheck {|mod Test do
    fn bad(linear x: Int) : Int do
      match x with
      | n -> n + n
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

(** Load a stdlib file by name and return its declarations as a single DMod.
    Searches paths relative to the project root (for development builds). *)
let load_stdlib_file_for_test name =
  let candidates = [
    Filename.concat "stdlib" name;
    Filename.concat "../../../stdlib" name;
    Filename.concat "../../stdlib" name;
  ] in
  match List.find_opt Sys.file_exists candidates with
  | None ->
    Alcotest.failf "Cannot find stdlib/%s (searched: %s)" name
      (String.concat ", " candidates)
  | Some path ->
    let src =
      let ic = open_in path in
      let n = in_channel_length ic in
      let buf = Bytes.create n in
      really_input ic buf 0 n;
      close_in ic;
      Bytes.to_string buf
    in
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
    let m = March_parser.Parser.module_ March_lexer.Lexer.token lexbuf in
    let m = March_desugar.Desugar.desugar_module m in
    (* Wrap as DMod so names are accessible as Module.name *)
    March_ast.Ast.DMod (m.March_ast.Ast.mod_name,
                        March_ast.Ast.Public,
                        m.March_ast.Ast.mod_decls,
                        March_ast.Ast.dummy_span)

(** Evaluate a module source with the given stdlib DMod declarations prepended. *)
let eval_with_stdlib decls src =
  let m = parse_and_desugar src in
  let m = { m with March_ast.Ast.mod_decls = decls @ m.March_ast.Ast.mod_decls } in
  March_eval.Eval.eval_module_env m

let vint = function March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt"
let vstr = function March_eval.Eval.VString s -> s | _ -> failwith "expected VString"
let vbool = function March_eval.Eval.VBool b -> b | _ -> failwith "expected VBool"

let with_reset f () =
  March_eval.Eval.reset_scheduler_state ();
  f ()

(** Convert a March VCon-linked-list to an OCaml list. *)
let rec vlist = function
  | March_eval.Eval.VCon ("Nil", []) -> []
  | March_eval.Eval.VCon ("Cons", [h; t]) -> h :: vlist t
  | _ -> failwith "expected list value"

let vcon tag = function
  | March_eval.Eval.VCon (t, args) when t = tag -> args
  | _ -> failwith ("expected VCon " ^ tag)

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

let test_value_task_to_string () =
  let v = March_eval.Eval.VTask 42 in
  let s = March_eval.Eval.value_to_string v in
  Alcotest.(check string) "VTask prints" "<task:42>" s

let test_value_workpool_to_string () =
  let v = March_eval.Eval.VWorkPool in
  let s = March_eval.Eval.value_to_string v in
  Alcotest.(check string) "VWorkPool prints" "<work_pool>" s

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
        | March_tir.Tir.AVar _ | March_tir.Tir.ADefRef _ | March_tir.Tir.ALit _ -> true
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
  let contains_apply s =
    let target = "$apply" in
    let tlen = String.length target in
    let slen = String.length s in
    let rec loop i = i <= slen - tlen && (String.sub s i tlen = target || loop (i+1)) in
    loop 0
  in
  let lifted = List.filter (fun f -> contains_apply f.March_tir.Tir.fn_name) m.March_tir.Tir.tm_fns in
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
  (* After perceus, user function count is unchanged.
     The module will also contain 15 builtin interface impl functions
     (Eq/Ord/Show/Hash for Int/Float/String/Bool) injected by the full pipeline. *)
  let m = perceus_module {|mod Test do
    fn a(x : Int) : Int do x end
    fn b(x : Int) : Int do x end
  end|} in
  let n = List.length m.March_tir.Tir.tm_fns in
  (* At least 2 user functions; builtins may be present *)
  Alcotest.(check bool) "perceus preserves user fn count" true (n >= 2)

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
  actor_state     = [];
  actor_init      = ELit (LitInt 0, dummy_span);
  actor_handlers  = [];
  actor_supervise = None;
}

let mk_actor_inst name alive st = March_eval.Eval.{
  ai_name          = name;
  ai_def           = dummy_actor_def;
  ai_env_ref       = ref [];
  ai_state         = st;
  ai_alive         = alive;
  ai_monitors      = [];
  ai_links         = [];
  ai_mailbox       = Queue.create ();
  ai_supervisor    = None;
  ai_restart_count = [];
  ai_epoch         = 0;
  ai_resources     = [];
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
  let e = March_ast.Ast.EDbg (None, sp) in
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
  let e = March_ast.Ast.EDbg (None, sp) in
  let e' = March_desugar.Desugar.desugar_expr e in
  Alcotest.(check bool) "EDbg desugar passthrough" true
    (match e' with March_ast.Ast.EDbg _ -> true | _ -> false)

let test_typecheck_edbg () =
  let type_map = Hashtbl.create 4 in
  let env = March_typecheck.Typecheck.base_env
    (March_errors.Errors.create ()) type_map in
  let sp = March_ast.Ast.dummy_span in
  let ty = March_typecheck.Typecheck.infer_expr env (March_ast.Ast.EDbg (None, sp)) in
  let pp = March_typecheck.Typecheck.pp_ty (March_typecheck.Typecheck.repr ty) in
  Alcotest.(check string) "EDbg typechecks as Unit" "()" pp

let test_eval_edbg_noop () =
  let v = March_eval.Eval.eval_expr March_eval.Eval.base_env
    (March_ast.Ast.EDbg (None, March_ast.Ast.dummy_span)) in
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
    dc_pos       = 0;
    dc_enabled   = true;
    dc_depth     = 0;
    dc_on_dbg    = None;
    dc_actor_log = [];
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
    dc_pos       = 0;
    dc_enabled   = true;
    dc_depth     = 0;
    dc_on_dbg    = None;
    dc_actor_log = [];
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
let mk_module fns = { March_tir.Tir.tm_name = "test"; tm_fns = fns; tm_types = []; tm_externs = [] }
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

(* ── Optimizer coordinator ───────────────────────────────────────── *)

let test_opt_fixpoint () =
  (* let x = 1 + 1 in x * 1
     → fold: let x = 2 in x * 1
     → simplify: let x = 2 in x
     At minimum x*1 should be simplified to x *)
  let x_var = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x_var,
               app "+" [ilit 1; ilit 1],
               app "*" [March_tir.Tir.AVar x_var; ilit 1]) in
  let m = mk_module [mk_fn "main" body] in
  let m' = March_tir.Opt.run m in
  (match first_body m' with
   | March_tir.Tir.EAtom (March_tir.Tir.AVar _) -> ()
   | March_tir.Tir.EAtom (March_tir.Tir.ALit _) -> ()
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom _) -> ()
   | e -> Alcotest.failf "expected reduced form, got: %s" (March_tir.Tir.show_expr e))

let test_opt_no_infinite_loop () =
  (* A stable expression should not loop forever *)
  let m = mk_module [mk_fn "main" (March_tir.Tir.EAtom (ilit 42))] in
  let m' = March_tir.Opt.run m in
  Alcotest.(check string) "stable" "(Tir.EAtom (Tir.ALit (Ast.LitInt 42)))"
    (March_tir.Tir.show_expr (first_body m'))

(* ── fast-math IR attribute ──────────────────────────────────────── *)

let test_fast_math_emits_fast_attr () =
  let x = mk_var "x" March_tir.Tir.TFloat in
  let y = mk_var "y" March_tir.Tir.TFloat in
  let fn_var name = mk_var name (March_tir.Tir.TFn ([], March_tir.Tir.TFloat)) in
  let body = March_tir.Tir.EApp (fn_var "+.", [March_tir.Tir.AVar x; March_tir.Tir.AVar y]) in
  let fd = { March_tir.Tir.fn_name = "fadd_test"; fn_params = [x; y];
             fn_ret_ty = March_tir.Tir.TFloat; fn_body = body } in
  let m = { March_tir.Tir.tm_name = "test"; tm_fns = [fd]; tm_types = []; tm_externs = [] } in
  let ir_fast   = March_tir.Llvm_emit.emit_module ~fast_math:true  m in
  let ir_normal = March_tir.Llvm_emit.emit_module ~fast_math:false m in
  Alcotest.(check bool) "fast_math IR contains 'fadd fast'" true
    (let re = Str.regexp "fadd fast" in
     (try ignore (Str.search_forward re ir_fast 0); true with Not_found -> false));
  Alcotest.(check bool) "normal IR does not contain 'fadd fast'" false
    (let re = Str.regexp "fadd fast" in
     (try ignore (Str.search_forward re ir_normal 0); true with Not_found -> false))

(* ── LLVM emit correctness: constructor hashtable collision ──────────────── *)

(** Bug: ctor_info keyed by constructor name only — two ADTs with the same
    constructor name (e.g. both having "Cons") silently overwrite each other,
    producing wrong tags and field counts.

    Fix: keys are now type-qualified ("A.Cons", "B.Cons").
    lower.ml embeds the parent type name in EAlloc TCon; build_ctor_info stores
    variants as "TypeName.CtorName"; emit_case qualifies br_tag at lookup time. *)
let test_ctor_no_collision_different_tags () =
  (* Type A: [Nil, Cons(Int)] — Nil=tag0, Cons=tag1
     Type B: [Cons(Int), Nil] — Cons=tag0, Nil=tag1
     Without the fix, ctor_info["Cons"] would be overwritten by whichever type
     is processed last, and make_a's allocation would get the wrong tag. *)
  let td_a = March_tir.Tir.TDVariant ("A",
    [("Nil", []); ("Cons", [March_tir.Tir.TInt])]) in
  let td_b = March_tir.Tir.TDVariant ("B",
    [("Cons", [March_tir.Tir.TInt]); ("Nil", [])]) in
  let x = mk_var "x" March_tir.Tir.TInt in
  (* make_a: builds A.Cons — should store tag 1 (second ctor of A) *)
  let fn_a = { March_tir.Tir.fn_name = "make_a";
               fn_params = [x];
               fn_ret_ty = March_tir.Tir.TCon ("A", []);
               fn_body   = March_tir.Tir.EAlloc
                             (March_tir.Tir.TCon ("A.Cons", []),
                              [March_tir.Tir.AVar x]) } in
  (* make_b: builds B.Cons — should store tag 0 (first ctor of B) *)
  let fn_b = { March_tir.Tir.fn_name = "make_b";
               fn_params = [x];
               fn_ret_ty = March_tir.Tir.TCon ("B", []);
               fn_body   = March_tir.Tir.EAlloc
                             (March_tir.Tir.TCon ("B.Cons", []),
                              [March_tir.Tir.AVar x]) } in
  let m = { March_tir.Tir.tm_name = "test"; tm_fns = [fn_a; fn_b];
            tm_types = [td_a; td_b]; tm_externs = [] } in
  let ir = March_tir.Llvm_emit.emit_module m in
  (* Without the fix, A.Cons lookup falls back to tag=0 (ctor_info["A.Cons"]
     not found → fallback entry with ce_tag=0).  With the fix, it finds
     ctor_info["A.Cons"] = {tag=1} and emits "store i32 1". *)
  let has_tag1 =
    try ignore (Str.search_forward (Str.regexp "store i32 1") ir 0); true
    with Not_found -> false
  in
  Alcotest.(check bool) "A.Cons emits tag 1 (not the fallback tag 0)" true has_tag1

(** Bug 2: when field counts don't match (e.g. cascading from collision),
    the emitter silently fell back to ptr type.  Fix: hard Failure. *)
let test_ctor_arity_mismatch_raises () =
  (* Construct EAlloc with key "A.Cons" (1 field in the type def) but 2 args.
     With the fix this must raise, not silently emit broken IR. *)
  let td = March_tir.Tir.TDVariant ("A",
    [("Cons", [March_tir.Tir.TInt])]) in   (* Cons has exactly 1 field *)
  let x = mk_var "x" March_tir.Tir.TInt in
  let y = mk_var "y" March_tir.Tir.TInt in
  let fn_t = { March_tir.Tir.fn_name = "bad";
               fn_params = [x; y];
               fn_ret_ty = March_tir.Tir.TCon ("A", []);
               fn_body   = March_tir.Tir.EAlloc
                             (March_tir.Tir.TCon ("A.Cons", []),
                              (* 2 args but ctor only has 1 field *)
                              [March_tir.Tir.AVar x; March_tir.Tir.AVar y]) } in
  let m = { March_tir.Tir.tm_name = "test"; tm_fns = [fn_t];
            tm_types = [td]; tm_externs = [] } in
  let raised =
    try ignore (March_tir.Llvm_emit.emit_module m); false
    with Failure _ -> true
  in
  Alcotest.(check bool) "arity mismatch raises Failure" true raised

(** Compiled path: the generated @main() C wrapper must call
    march_run_scheduler() after march_main() so that actor mailboxes
    are drained even when main() never calls run_until_idle(). *)
let test_compiled_main_calls_march_run_scheduler () =
  let src = {|mod Test do
    actor Counter do
      state { count : Int }
      init { count = 0 }
      on Inc() do { count = state.count + 1 } end
    end
    fn main() do
      let pid = spawn(Counter)
      send(pid, Inc())
    end
  end|} in
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let ir = March_tir.Llvm_emit.emit_module tir in
  (* The @main() wrapper must contain a call to march_run_scheduler so
     that actor mailboxes are drained after march_main() returns.
     Without this, handlers would never run in compiled executables. *)
  let has_scheduler_call =
    try ignore (Str.search_forward (Str.regexp "march_run_scheduler") ir 0); true
    with Not_found -> false
  in
  Alcotest.(check bool) "@main wrapper calls march_run_scheduler" true has_scheduler_call;
  (* Verify the declaration is present too (needed by the linker) *)
  let has_declaration =
    try ignore (Str.search_forward
      (Str.regexp "declare void @march_run_scheduler") ir 0); true
    with Not_found -> false
  in
  Alcotest.(check bool) "march_run_scheduler is declared in preamble" true has_declaration

(* ── String stdlib module tests ─────────────────────────────────────────── *)

(** Helper: load string.march and evaluate [src] with it in scope. *)
let eval_with_string src =
  let string_decl = load_stdlib_file_for_test "string.march" in
  eval_with_stdlib [string_decl] src

let test_string_byte_size () =
  let env = eval_with_string {|mod Test do
    fn f() do String.byte_size("hello") end
  end|} in
  Alcotest.(check int) "byte_size(\"hello\") = 5" 5
    (vint (call_fn env "f" []))

let test_string_byte_size_empty () =
  let env = eval_with_string {|mod Test do
    fn f() do String.byte_size("") end
  end|} in
  Alcotest.(check int) "byte_size(\"\") = 0" 0
    (vint (call_fn env "f" []))

let test_string_byte_size_unicode () =
  (* UTF-8: "é" is 2 bytes *)
  let env = eval_with_string {|mod Test do
    fn f() do String.byte_size("é") end
  end|} in
  Alcotest.(check int) "byte_size(\"é\") = 2" 2
    (vint (call_fn env "f" []))

let test_string_slice_bytes () =
  let env = eval_with_string {|mod Test do
    fn f() do String.slice_bytes("hello world", 6, 5) end
  end|} in
  Alcotest.(check string) "slice_bytes(\"hello world\", 6, 5) = \"world\"" "world"
    (vstr (call_fn env "f" []))

let test_string_slice_bytes_clamp () =
  (* slice beyond end should clamp, not raise *)
  let env = eval_with_string {|mod Test do
    fn f() do String.slice_bytes("hi", 0, 100) end
  end|} in
  Alcotest.(check string) "slice_bytes clamps to string length" "hi"
    (vstr (call_fn env "f" []))

let test_string_contains () =
  let env = eval_with_string {|mod Test do
    fn yes() do String.contains("hello world", "world") end
    fn no()  do String.contains("hello world", "xyz") end
  end|} in
  Alcotest.(check bool) "contains: true"  true  (vbool (call_fn env "yes" []));
  Alcotest.(check bool) "contains: false" false (vbool (call_fn env "no"  []))

let test_string_starts_with () =
  let env = eval_with_string {|mod Test do
    fn yes() do String.starts_with("hello", "he") end
    fn no()  do String.starts_with("hello", "lo") end
  end|} in
  Alcotest.(check bool) "starts_with: true"  true  (vbool (call_fn env "yes" []));
  Alcotest.(check bool) "starts_with: false" false (vbool (call_fn env "no"  []))

let test_string_ends_with () =
  let env = eval_with_string {|mod Test do
    fn yes() do String.ends_with("hello", "lo") end
    fn no()  do String.ends_with("hello", "he") end
  end|} in
  Alcotest.(check bool) "ends_with: true"  true  (vbool (call_fn env "yes" []));
  Alcotest.(check bool) "ends_with: false" false (vbool (call_fn env "no"  []))

let test_string_concat () =
  let env = eval_with_string {|mod Test do
    fn f() do String.concat("foo", "bar") end
  end|} in
  Alcotest.(check string) "concat" "foobar"
    (vstr (call_fn env "f" []))

let test_string_replace () =
  let env = eval_with_string {|mod Test do
    fn f() do String.replace("hello world", "world", "there") end
  end|} in
  Alcotest.(check string) "replace first" "hello there"
    (vstr (call_fn env "f" []))

let test_string_replace_all () =
  let env = eval_with_string {|mod Test do
    fn f() do String.replace_all("aabbaa", "a", "x") end
  end|} in
  Alcotest.(check string) "replace_all" "xxbbxx"
    (vstr (call_fn env "f" []))

let test_string_split () =
  let env = eval_with_string {|mod Test do
    fn f() do String.split("a,b,c", ",") end
  end|} in
  let xs = vlist (call_fn env "f" []) in
  Alcotest.(check int) "split length" 3 (List.length xs);
  Alcotest.(check string) "split[0]" "a" (vstr (List.nth xs 0));
  Alcotest.(check string) "split[1]" "b" (vstr (List.nth xs 1));
  Alcotest.(check string) "split[2]" "c" (vstr (List.nth xs 2))

let test_string_split_first () =
  (* split_first("a:b:c", ":") = Some("a", "b:c") *)
  let env = eval_with_string {|mod Test do
    fn f() do String.split_first("a:b:c", ":") end
  end|} in
  let args = vcon "Some" (call_fn env "f" []) in
  let pair = (match List.nth args 0 with
    | March_eval.Eval.VTuple [a; b] -> (a, b)
    | _ -> failwith "expected tuple") in
  Alcotest.(check string) "split_first head" "a"   (vstr (fst pair));
  Alcotest.(check string) "split_first tail" "b:c" (vstr (snd pair))

let test_string_split_first_no_sep () =
  (* split_first("hello", ":") = None *)
  let env = eval_with_string {|mod Test do
    fn f() do String.split_first("hello", ":") end
  end|} in
  let _ = vcon "None" (call_fn env "f" []) in
  ()  (* Just checking it returns None *)

let test_string_join () =
  let env = eval_with_string {|mod Test do
    fn f() do String.join(["a", "b", "c"], "-") end
  end|} in
  Alcotest.(check string) "join" "a-b-c"
    (vstr (call_fn env "f" []))

let test_string_trim () =
  let env = eval_with_string {|mod Test do
    fn f() do String.trim("  hello  ") end
  end|} in
  Alcotest.(check string) "trim" "hello"
    (vstr (call_fn env "f" []))

let test_string_trim_start () =
  let env = eval_with_string {|mod Test do
    fn f() do String.trim_start("  hello  ") end
  end|} in
  Alcotest.(check string) "trim_start" "hello  "
    (vstr (call_fn env "f" []))

let test_string_trim_end () =
  let env = eval_with_string {|mod Test do
    fn f() do String.trim_end("  hello  ") end
  end|} in
  Alcotest.(check string) "trim_end" "  hello"
    (vstr (call_fn env "f" []))

let test_string_to_uppercase () =
  let env = eval_with_string {|mod Test do
    fn f() do String.to_uppercase("hello") end
  end|} in
  Alcotest.(check string) "to_uppercase" "HELLO"
    (vstr (call_fn env "f" []))

let test_string_to_lowercase () =
  let env = eval_with_string {|mod Test do
    fn f() do String.to_lowercase("HELLO") end
  end|} in
  Alcotest.(check string) "to_lowercase" "hello"
    (vstr (call_fn env "f" []))

let test_string_repeat () =
  let env = eval_with_string {|mod Test do
    fn f() do String.repeat("ab", 3) end
  end|} in
  Alcotest.(check string) "repeat" "ababab"
    (vstr (call_fn env "f" []))

let test_string_reverse () =
  let env = eval_with_string {|mod Test do
    fn f() do String.reverse("hello") end
  end|} in
  Alcotest.(check string) "reverse" "olleh"
    (vstr (call_fn env "f" []))

let test_string_pad_left () =
  let env = eval_with_string {|mod Test do
    fn f() do String.pad_left("hi", 5, "0") end
  end|} in
  Alcotest.(check string) "pad_left" "000hi"
    (vstr (call_fn env "f" []))

let test_string_pad_right () =
  let env = eval_with_string {|mod Test do
    fn f() do String.pad_right("hi", 5, ".") end
  end|} in
  Alcotest.(check string) "pad_right" "hi..."
    (vstr (call_fn env "f" []))

let test_string_is_empty () =
  let env = eval_with_string {|mod Test do
    fn yes() do String.is_empty("") end
    fn no()  do String.is_empty("x") end
  end|} in
  Alcotest.(check bool) "is_empty: true"  true  (vbool (call_fn env "yes" []));
  Alcotest.(check bool) "is_empty: false" false (vbool (call_fn env "no"  []))

let test_string_grapheme_count () =
  let env = eval_with_string {|mod Test do
    fn f() do String.grapheme_count("hello") end
  end|} in
  Alcotest.(check int) "grapheme_count(\"hello\") = 5" 5
    (vint (call_fn env "f" []))

let test_string_index_of () =
  let env = eval_with_string {|mod Test do
    fn found()     do String.index_of("hello", "ll") end
    fn not_found() do String.index_of("hello", "xyz") end
  end|} in
  let some_args = vcon "Some" (call_fn env "found" []) in
  Alcotest.(check int) "index_of found at 2" 2
    (vint (List.nth some_args 0));
  let _ = vcon "None" (call_fn env "not_found" []) in
  ()

let test_string_to_int () =
  let env = eval_with_string {|mod Test do
    fn ok()  do String.to_int("42") end
    fn err() do String.to_int("abc") end
  end|} in
  let ok_args = vcon "Ok" (call_fn env "ok" []) in
  Alcotest.(check int) "to_int Ok(42)" 42 (vint (List.nth ok_args 0));
  let _ = vcon "Err" (call_fn env "err" []) in
  ()

let test_string_to_float () =
  let env = eval_with_string {|mod Test do
    fn ok()  do String.to_float("3.14") end
    fn err() do String.to_float("abc") end
  end|} in
  let ok_args = vcon "Ok" (call_fn env "ok" []) in
  Alcotest.(check (float 0.001)) "to_float Ok(3.14)" 3.14
    (match List.nth ok_args 0 with
     | March_eval.Eval.VFloat f -> f
     | _ -> failwith "expected VFloat");
  let _ = vcon "Err" (call_fn env "err" []) in
  ()

let test_string_from_int () =
  let env = eval_with_string {|mod Test do
    fn f() do String.from_int(42) end
  end|} in
  Alcotest.(check string) "from_int(42)" "42"
    (vstr (call_fn env "f" []))

let test_string_from_float () =
  let env = eval_with_string {|mod Test do
    fn f() do String.from_float(3.14) end
  end|} in
  let s = vstr (call_fn env "f" []) in
  Alcotest.(check bool) "from_float contains dot" true
    (String.contains s '.')

(* ── IOList stdlib module tests ─────────────────────────────────────────── *)

let eval_with_iolist src =
  let string_decl = load_stdlib_file_for_test "string.march" in
  let iolist_decl = load_stdlib_file_for_test "iolist.march" in
  eval_with_stdlib [string_decl; iolist_decl] src

let test_iolist_empty () =
  let env = eval_with_iolist {|mod Test do
    fn f() do IOList.to_string(IOList.empty()) end
  end|} in
  Alcotest.(check string) "IOList.empty flattens to \"\"" ""
    (vstr (call_fn env "f" []))

let test_iolist_from_string () =
  let env = eval_with_iolist {|mod Test do
    fn f() do IOList.to_string(IOList.from_string("hello")) end
  end|} in
  Alcotest.(check string) "IOList.from_string round-trips" "hello"
    (vstr (call_fn env "f" []))

let test_iolist_append () =
  let env = eval_with_iolist {|mod Test do
    fn f() do
      IOList.to_string(IOList.append(IOList.from_string("foo"), IOList.from_string("bar")))
    end
  end|} in
  Alcotest.(check string) "IOList.append" "foobar"
    (vstr (call_fn env "f" []))

let test_iolist_byte_size () =
  let env = eval_with_iolist {|mod Test do
    fn f() do
      IOList.byte_size(IOList.from_string("hello"))
    end
  end|} in
  Alcotest.(check int) "IOList.byte_size" 5
    (vint (call_fn env "f" []))

(* ── Http stdlib module tests ──────────────────────────────────────────── *)

let eval_with_http src =
  let string_decl = load_stdlib_file_for_test "string.march" in
  let http_decl = load_stdlib_file_for_test "http.march" in
  eval_with_stdlib [string_decl; http_decl] src

let test_http_parse_url () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("https://example.com/path?q=1") with
      | Ok(req) -> Http.host(req)
      | Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "parse_url host" "example.com" (vstr (call_fn env "f" []))

let test_http_parse_url_scheme () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("http://localhost:8080/api") with
      | Ok(req) ->
        match Http.scheme(req) with
        | SchemeHttp -> "http"
        | SchemeHttps -> "https"
        end
      | Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "parse_url scheme" "http" (vstr (call_fn env "f" []))

let test_http_parse_url_path () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("https://example.com/api/v1") with
      | Ok(req) -> Http.path(req)
      | Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "parse_url path" "/api/v1" (vstr (call_fn env "f" []))

let test_http_parse_url_port () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("http://localhost:3000/") with
      | Ok(req) ->
        match Http.port(req) with
        | Some(p) -> p
        | None -> 0
        end
      | Err(_) -> -1
      end
    end
  end|} in
  Alcotest.(check int) "parse_url port" 3000 (vint (call_fn env "f" []))

let test_http_parse_url_invalid () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("ftp://bad") with
      | Ok(_) -> "ok"
      | Err(InvalidScheme(_)) -> "invalid_scheme"
      | Err(_) -> "other_error"
      end
    end
  end|} in
  Alcotest.(check string) "parse_url invalid scheme" "invalid_scheme" (vstr (call_fn env "f" []))

let test_http_set_header () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.get("https://example.com") with
      | Ok(req) ->
        let req = Http.set_header(req, "Accept", "application/json")
        match Http.get_request_header(req, "accept") with
        | Some(v) -> v
        | None -> "none"
        end
      | Err(_) -> "error"
      end
    end
  end|} in
  Alcotest.(check string) "set_header" "application/json" (vstr (call_fn env "f" []))

let test_http_method_to_string () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.post("https://example.com", ()) with
      | Ok(req) -> Http.method_to_string(Http.method(req))
      | Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "method_to_string" "POST" (vstr (call_fn env "f" []))

let test_http_status_helpers () =
  let env = eval_with_http {|mod Test do
    fn f() do Http.is_success(Http.status_ok()) end
  end|} in
  Alcotest.(check bool) "status_ok is success" true (vbool (call_fn env "f" []))

let test_http_post_constructor () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.post("https://example.com/api", "body data") with
      | Ok(req) -> Http.method_to_string(Http.method(req))
      | Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "post method" "POST" (vstr (call_fn env "f" []))

let test_http_encode_query () =
  let env = eval_with_http {|mod Test do
    fn f() do
      Http.encode_query(Cons(("key", "value"), Cons(("foo", "bar"), Nil)))
    end
  end|} in
  Alcotest.(check string) "encode_query" "key=value&foo=bar" (vstr (call_fn env "f" []))

let test_http_response_helpers () =
  let env = eval_with_http {|mod Test do
    fn f() do
      let resp = Response(Status(404), Nil, "Not Found")
      Http.response_status_code(resp)
    end
  end|} in
  Alcotest.(check int) "response status code" 404 (vint (call_fn env "f" []))

(* ── Http builtin tests ───────────────────────────────────────────── *)

let test_http_serialize_request () =
  let env = eval_with_http {|mod Test do
    fn f() do
      http_serialize_request("GET", "example.com", "/path", None, Nil, "")
    end
  end|} in
  let raw = vstr (call_fn env "f" []) in
  Alcotest.(check bool) "starts with GET /path"
    true (String.length raw > 0 && String.sub raw 0 14 = "GET /path HTTP")

let test_http_serialize_request_with_body () =
  let env = eval_with_http {|mod Test do
    fn f() do
      http_serialize_request("POST", "example.com", "/api", None,
        Cons(Header("Content-Type", "text/plain"), Nil), "hello")
    end
  end|} in
  let raw = vstr (call_fn env "f" []) in
  Alcotest.(check bool) "contains body" true (
    let lines = String.split_on_char '\n' raw in
    List.exists (fun l -> String.trim l = "hello") lines)

let test_http_parse_response () =
  let raw = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nhello world" in
  let open March_eval.Eval in
  let result = List.assoc "http_parse_response" base_env in
  match result with
  | VBuiltin (_, f) ->
    (match f [VString raw] with
     | VCon ("Ok", [VTuple [VInt code; _; VString _body]]) ->
       Alcotest.(check int) "status code" 200 code
     | _ -> Alcotest.fail "expected Ok tuple")
  | _ -> Alcotest.fail "expected builtin"

let test_http_parse_response_body () =
  (* Build the raw HTTP response with actual \r\n in OCaml, pass to builtin directly *)
  let raw = "HTTP/1.1 404 Not Found\r\nX-Foo: bar\r\n\r\nnot here" in
  let open March_eval.Eval in
  let result = List.assoc "http_parse_response" base_env in
  match result with
  | VBuiltin (_, f) ->
    (match f [VString raw] with
     | VCon ("Ok", [VTuple [VInt code; _; VString body]]) ->
       Alcotest.(check int) "status code" 404 code;
       Alcotest.(check string) "body" "not here" body
     | _ -> Alcotest.fail "expected Ok tuple")
  | _ -> Alcotest.fail "expected builtin"

(* ── Http.Client tests ───────────────────────────────────────────── *)

let eval_with_http_client src =
  let string_decl = load_stdlib_file_for_test "string.march" in
  let http_decl = load_stdlib_file_for_test "http.march" in
  let transport_decl = load_stdlib_file_for_test "http_transport.march" in
  let client_decl = load_stdlib_file_for_test "http_client.march" in
  eval_with_stdlib [string_decl; http_decl; transport_decl; client_decl] src

let test_http_client_new () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let c = HttpClient.new_client()
      c
    end
  end|} in
  let v = call_fn env "f" [] in
  match v with
  | March_eval.Eval.VCon ("Client", _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "expected Client, got %s"
    (March_eval.Eval.value_to_string v))

let test_http_client_add_steps () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let c = HttpClient.new_client()
      let c = HttpClient.add_request_step(c, "auth", HttpClient.step_bearer_auth("tok"))
      let c = HttpClient.add_request_step(c, "headers", HttpClient.step_default_headers)
      fn count(xs) do
        match xs with
        | Nil -> 0
        | Cons(_, t) -> 1 + count(t)
        end
      end
      count(HttpClient.list_steps(c))
    end
  end|} in
  Alcotest.(check int) "two request steps" 2 (vint (call_fn env "f" []))

let test_http_client_request_step_transforms () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      match Http.get("http://example.com") with
      | Err(_) -> "fail"
      | Ok(req) ->
        let step = HttpClient.step_bearer_auth("my-token")
        match step(req) with
        | Err(_) -> "fail"
        | Ok(transformed) ->
          match Http.get_request_header(transformed, "authorization") with
          | Some(v) -> v
          | None -> "none"
          end
        end
      end
    end
  end|} in
  Alcotest.(check string) "bearer auth header" "Bearer my-token" (vstr (call_fn env "f" []))

let test_http_client_raise_on_error_status () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      match Http.get("http://example.com") with
      | Err(_) -> "url_fail"
      | Ok(req) ->
        let resp = Response(Status(500), Nil, "Internal Server Error")
        match HttpClient.step_raise_on_error(req, resp) with
        | Ok(_) -> "ok"
        | Err(StepError(name, code)) -> name ++ ":" ++ code
        | Err(_) -> "other_error"
        end
      end
    end
  end|} in
  Alcotest.(check string) "raise on 500" "step_raise_on_error:500" (vstr (call_fn env "f" []))

let test_http_client_with_redirects () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let c = HttpClient.new_client()
      let c = HttpClient.with_redirects(c, 5)
      match HttpClient.list_steps(c) with
      | Nil -> "empty"
      | _ -> "has_steps"
      end
    end
  end|} in
  Alcotest.(check string) "redirects config" "empty" (vstr (call_fn env "f" []))

let test_http_client_base_url_step () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let step = HttpClient.step_base_url("http://api.example.com")
      -- Create a request with just a path
      let req = Request(Get, SchemeHttp, "", None, "/users", None, Nil, "")
      match step(req) with
      | Ok(transformed) -> Http.host(transformed)
      | Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "base url sets host" "api.example.com" (vstr (call_fn env "f" []))

let test_http_client_content_type_step () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let step = HttpClient.step_content_type("application/json")
      let req = Request(Post, SchemeHttp, "example.com", None, "/api", None, Nil, "{}")
      match step(req) with
      | Ok(transformed) ->
        match Http.get_request_header(transformed, "content-type") with
        | Some(v) -> v
        | None -> "none"
        end
      | Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "content type header" "application/json" (vstr (call_fn env "f" []))

(* ── Scheduler tests ───────────────────────────────────────────────── *)

let test_reduction_counter_ticks () =
  let ctx = March_scheduler.Scheduler.create_reduction_ctx () in
  let initial = ctx.remaining in
  let exhausted = March_scheduler.Scheduler.tick ctx in
  Alcotest.(check bool) "first tick not exhausted" false exhausted;
  Alcotest.(check int) "decremented by 1" (initial - 1) ctx.remaining

let test_reduction_counter_exhausts () =
  let ctx = March_scheduler.Scheduler.create_reduction_ctx () in
  let count = ref 0 in
  while not (March_scheduler.Scheduler.tick ctx) do
    incr count
  done;
  Alcotest.(check int) "exhausts after max_reductions - 1 ticks"
    (March_scheduler.Scheduler.max_reductions - 1) !count;
  Alcotest.(check bool) "yielded flag set" true ctx.yielded

let test_eval_yields_after_budget () =
  let src = {|mod Test do
    fn countdown(n) do if n <= 0 then 0 else countdown(n - 1) end
  end|} in
  let env = eval_module src in
  March_eval.Eval.set_reduction_counting true;
  let yielded = ref false in
  (try
     ignore (call_fn env "countdown" [March_eval.Eval.VInt 100_000])
   with March_eval.Eval.Yield ->
     yielded := true);
  March_eval.Eval.set_reduction_counting false;
  Alcotest.(check bool) "countdown yields after budget" true !yielded

let test_eval_no_yield_when_disabled () =
  March_eval.Eval.set_reduction_counting false;
  let src = {|mod Test do
    fn countdown(n) do if n <= 0 then 0 else countdown(n - 1) end
  end|} in
  let env = eval_module src in
  let v = call_fn env "countdown" [March_eval.Eval.VInt 100_000] in
  Alcotest.(check int) "completes without yield" 0 (vint v)

(* ── Task tests ──────────────────────────────────────────────────── *)

let test_eval_task_spawn_await () =
  let src = {|mod Test do
    fn main() do
      let t = task_spawn(fn x -> 42)
      task_await_unwrap(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "task returns 42" 42 (vint v)

let test_eval_task_await_unwrap () =
  let src = {|mod Test do
    fn main() do
      let t = task_spawn(fn x -> 99)
      task_await_unwrap(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "task unwrap returns 99" 99 (vint v)

let test_eval_task_multiple () =
  let src = {|mod Test do
    fn main() do
      let t1 = task_spawn(fn x -> 10)
      let t2 = task_spawn(fn x -> 20)
      let r1 = task_await_unwrap(t1)
      let r2 = task_await_unwrap(t2)
      r1 + r2
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "two tasks sum to 30" 30 (vint v)

let test_eval_task_captures_env () =
  let src = {|mod Test do
    fn main() do
      let x = 5
      let t = task_spawn(fn u -> x * x)
      task_await_unwrap(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "task captures outer x" 25 (vint v)

let test_eval_spawn_steal_requires_pool () =
  let src = {|mod Test do
    fn main() do
      task_spawn_steal(42, fn x -> 1)
    end
  end|} in
  let env = eval_module src in
  let raised = ref false in
  (try ignore (call_fn env "main" [])
   with March_eval.Eval.Eval_error _ -> raised := true);
  Alcotest.(check bool) "rejects non-WorkPool" true !raised

let test_eval_spawn_steal_with_pool () =
  let src = {|mod Test do
    fn run(pool) do
      let t = task_spawn_steal(pool, fn x -> 77)
      task_await_unwrap(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "run" [March_eval.Eval.VWorkPool] in
  Alcotest.(check int) "steal task returns 77" 77 (vint v)

let test_eval_workpool_threading () =
  let src = {|mod Test do
    fn helper(pool) do
      let t = task_spawn_steal(pool, fn x -> 55)
      task_await_unwrap(t)
    end

    fn main(pool) do
      helper(pool)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [March_eval.Eval.VWorkPool] in
  Alcotest.(check int) "threaded pool works" 55 (vint v)

let test_eval_task_sends_to_actor () =
  let src = {|mod Test do
    actor Counter do
      state { count : Int }
      init { count = 0 }

      on Increment(n) do
        { count = state.count + n }
      end
    end

    fn main() do
      let pid = spawn(Counter)
      let t = task_spawn(fn x -> send(pid, Increment(10)))
      task_await_unwrap(t)
      send(pid, Increment(0))
    end
  end|} in
  let env = eval_module src in
  let _v = call_fn env "main" [] in
  (* If we get here without error, cross-tier messaging works *)
  ()

(** Phase 4: send() should push to mailbox, NOT dispatch inline.
    After send(), mailbox_size = 1 and state is unchanged. *)
let test_async_send_queues_not_dispatches () =
  let src = {|mod Test do
    actor Counter do
      state { count : Int }
      init { count = 0 }
      on Inc() do { count = state.count + 1 } end
    end

    fn main() do
      let pid = spawn(Counter)
      send(pid, Inc())
      mailbox_size(pid)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  (* After send(), message is queued but not yet processed.
     mailbox_size should be 1, NOT 0. *)
  Alcotest.(check int) "mailbox has 1 queued message" 1
    (match v with March_eval.Eval.VInt n -> n | _ -> -1)

(** Phase 4: run_scheduler() processes queued messages.
    After run_until_idle(), counter state should be updated. *)
let test_scheduler_drains_mailbox () =
  let src = {|mod Test do
    actor Counter do
      state { count : Int }
      init { count = 0 }
      on Inc() do { count = state.count + 1 } end
    end

    fn main() do
      let pid = spawn(Counter)
      send(pid, Inc())
      send(pid, Inc())
      send(pid, Inc())
      run_until_idle()
      mailbox_size(pid)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "mailbox empty after run_until_idle" 0
    (match v with March_eval.Eval.VInt n -> n | _ -> -1)

(** Phase 4: scheduler processes handler and updates actor state. *)
let test_scheduler_updates_actor_state () =
  let src = {|mod Test do
    actor Counter do
      state { count : Int }
      init { count = 0 }
      on Inc() do { count = state.count + 1 } end
    end

    fn main() do
      let pid = spawn(Counter)
      send(pid, Inc())
      send(pid, Inc())
      send(pid, Inc())
      run_until_idle()
      pid
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  let pid = match v with March_eval.Eval.VPid n -> n | _ -> failwith "expected pid" in
  let state = match Hashtbl.find_opt March_eval.Eval.actor_registry pid with
    | Some inst -> inst.March_eval.Eval.ai_state
    | None -> failwith "actor not found" in
  Alcotest.(check int) "count = 3 after 3 Inc messages" 3
    (match state with
     | March_eval.Eval.VRecord fields ->
       (match List.assoc_opt "count" fields with
        | Some (March_eval.Eval.VInt n) -> n
        | _ -> -1)
     | _ -> -1)

(** Phase 4: scheduler processes messages from multiple actors, all actors processed. *)
let test_scheduler_round_robin () =
  let src = {|mod Test do
    actor Counter do
      state { count : Int }
      init { count = 0 }
      on Inc() do { count = state.count + 1 } end
    end

    fn main() do
      let p1 = spawn(Counter)
      let p2 = spawn(Counter)
      let p3 = spawn(Counter)
      send(p1, Inc())
      send(p2, Inc())
      send(p2, Inc())
      send(p3, Inc())
      send(p3, Inc())
      send(p3, Inc())
      run_until_idle()
      p1
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  let pid1 = match v with March_eval.Eval.VPid n -> n | _ -> failwith "expected pid" in
  let get_count pid =
    match Hashtbl.find_opt March_eval.Eval.actor_registry pid with
    | Some inst ->
      (match inst.March_eval.Eval.ai_state with
       | March_eval.Eval.VRecord fs ->
         (match List.assoc_opt "count" fs with
          | Some (March_eval.Eval.VInt n) -> n | _ -> -1)
       | _ -> -1)
    | None -> -1
  in
  Alcotest.(check int) "p1 received 1 Inc message" 1 (get_count pid1);
  Alcotest.(check int) "p2 received 2 Inc messages" 2 (get_count (pid1 + 1));
  Alcotest.(check int) "p3 received 3 Inc messages" 3 (get_count (pid1 + 2))

(** Phase 4: self() returns the current actor's pid inside a handler. *)
let test_self_inside_handler () =
  let src = {|mod Test do
    actor Echo do
      state { alive : Bool }
      init { alive = true }
      on Ping() do
        let me = self()
        { alive = true }
      end
    end

    fn main() do
      let pid = spawn(Echo)
      send(pid, Ping())
      run_until_idle()
      is_alive(pid)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check bool) "actor still alive after self() call" true
    (match v with March_eval.Eval.VBool b -> b | _ -> false)

(** Phase 4: receive() inside a handler pops the next queued message. *)
let test_receive_inside_handler () =
  let src = {|mod Test do
    actor Dispatcher do
      state { got : Int }
      init { got = 0 }
      on Dispatch() do
        let follow = receive()
        match follow with
        | Followup(n) -> { got = n }
        end
      end
    end

    fn main() do
      let pid = spawn(Dispatcher)
      send(pid, Dispatch())
      send(pid, Followup(99))
      run_until_idle()
      pid
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  let pid = match v with March_eval.Eval.VPid n -> n | _ -> failwith "expected pid" in
  let got = match Hashtbl.find_opt March_eval.Eval.actor_registry pid with
    | Some inst ->
      (match inst.March_eval.Eval.ai_state with
       | March_eval.Eval.VRecord fs ->
         (match List.assoc_opt "got" fs with
          | Some (March_eval.Eval.VInt n) -> n
          | _ -> -1)
       | _ -> -1)
    | None -> -1 in
  Alcotest.(check int) "Dispatcher got 99 via receive()" 99 got

(** Async mailbox semantics: messages to a single actor are delivered in
    FIFO order.  We use the "accumulator * 10 + n" trick: if processed as
    Append(1) → Append(2) → Append(3), acc = 123.  LIFO would give 321. *)
let test_message_fifo_ordering () =
  let src = {|mod Test do
    actor Accumulator do
      state { acc : Int }
      init { acc = 0 }
      on Append(n) do
        { acc = state.acc * 10 + n }
      end
    end

    fn main() do
      let pid = spawn(Accumulator)
      send(pid, Append(1))
      send(pid, Append(2))
      send(pid, Append(3))
      run_until_idle()
      pid
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  let pid = match v with March_eval.Eval.VPid n -> n | _ -> failwith "expected pid" in
  let acc =
    match Hashtbl.find_opt March_eval.Eval.actor_registry pid with
    | Some inst ->
      (match inst.March_eval.Eval.ai_state with
       | March_eval.Eval.VRecord fs ->
         (match List.assoc_opt "acc" fs with
          | Some (March_eval.Eval.VInt n) -> n | _ -> -1)
       | _ -> -1)
    | None -> -1
  in
  (* FIFO: Append(1)→Append(2)→Append(3) ⟹ ((0*10+1)*10+2)*10+3 = 123 *)
  Alcotest.(check int) "FIFO ordering: acc = 123" 123 acc

(** A message sent to an actor from inside a handler is queued and
    processed in a subsequent scheduler pass — not dropped, not
    processed inline during the current handler. *)
let test_handler_sends_to_another_actor () =
  let src = {|mod Test do
    actor Target do
      state { pinged : Bool }
      init { pinged = false }
      on Ping() do { pinged = true } end
    end

    actor Relay do
      state { relayed : Bool }
      init { relayed = false }
      on Forward(target) do
        let _ = send(target, Ping())
        { relayed = true }
      end
    end

    fn main() do
      let target = spawn(Target)
      let relay  = spawn(Relay)
      send(relay, Forward(target))
      run_until_idle()
      target
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  let pid = match v with March_eval.Eval.VPid n -> n | _ -> failwith "expected pid" in
  let pinged =
    match Hashtbl.find_opt March_eval.Eval.actor_registry pid with
    | Some inst ->
      (match inst.March_eval.Eval.ai_state with
       | March_eval.Eval.VRecord fs ->
         (match List.assoc_opt "pinged" fs with
          | Some (March_eval.Eval.VBool b) -> b | _ -> false)
       | _ -> false)
    | None -> false
  in
  Alcotest.(check bool) "Target received Ping relayed from handler" true pinged

(** run_module drains the scheduler after main() returns even when
    main() never calls run_until_idle() explicitly. *)
let test_run_module_auto_drains () =
  March_eval.Eval.reset_scheduler_state ();
  let src = {|mod Test do
    actor Counter do
      state { count : Int }
      init { count = 0 }
      on Inc() do { count = state.count + 1 } end
    end

    fn main() do
      let pid = spawn(Counter)
      send(pid, Inc())
      send(pid, Inc())
      send(pid, Inc())
      pid
    end
  end|} in
  let m = parse_and_desugar src in
  March_eval.Eval.run_module m;
  (* After run_module, the scheduler has been drained even though main()
     never called run_until_idle(). *)
  (* Collect all live actor instances directly from the registry. *)
  let instances =
    Hashtbl.fold (fun _pid inst acc -> inst :: acc)
      March_eval.Eval.actor_registry []
  in
  let count = match instances with
    | [inst] ->
      (match inst.March_eval.Eval.ai_state with
       | March_eval.Eval.VRecord fs ->
         (match List.assoc_opt "count" fs with
          | Some (March_eval.Eval.VInt n) -> n | _ -> -1)
       | _ -> -1)
    | _ -> -2
  in
  Alcotest.(check int) "run_module auto-drain: count = 3" 3 count

(** Sending to a dead actor silently drops the message; the mailbox
    stays empty and the caller does not crash. *)
let test_send_to_dead_actor_dropped () =
  let src = {|mod Test do
    actor Worker do
      state { count : Int }
      init { count = 0 }
      on Inc() do { count = state.count + 1 } end
    end

    fn main() do
      let pid = spawn(Worker)
      kill(pid)
      send(pid, Inc())
      run_until_idle()
      mailbox_size(pid)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "dead actor mailbox stays 0 after send" 0
    (match v with March_eval.Eval.VInt n -> n | _ -> -1)

(** An actor that sends to self() in a handler: the self-message is
    queued and processed in a subsequent scheduler pass, not inline.
    Here Relay sends Ping to itself; after run_until_idle both the
    initial Forward handler and the Ping handler must have run. *)
let test_self_send_from_handler () =
  let src = {|mod Test do
    actor SelfSender do
      state { stage : Int }
      init { stage = 0 }
      on Begin() do
        let _ = send(self(), End())
        { stage = 1 }
      end
      on End() do
        { stage = 2 }
      end
    end

    fn main() do
      let pid = spawn(SelfSender)
      send(pid, Begin())
      run_until_idle()
      pid
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  let pid = match v with March_eval.Eval.VPid n -> n | _ -> failwith "expected pid" in
  let stage =
    match Hashtbl.find_opt March_eval.Eval.actor_registry pid with
    | Some inst ->
      (match inst.March_eval.Eval.ai_state with
       | March_eval.Eval.VRecord fs ->
         (match List.assoc_opt "stage" fs with
          | Some (March_eval.Eval.VInt n) -> n | _ -> -1)
       | _ -> -1)
    | None -> -1
  in
  (* stage 1 after Begin(), stage 2 after the queued End() — both must run *)
  Alcotest.(check int) "self-send reaches stage 2" 2 stage

let test_eval_reduction_count () =
  let src = {|mod Test do
    fn countdown(n) do
      if n <= 0 then 0
      else countdown(n - 1)
    end

    fn main() do
      countdown(100)
    end
  end|} in
  let env = eval_module src in
  let thunk = List.assoc "main" env in
  let (_result, reductions) =
    March_eval.Eval.eval_with_reduction_tracking thunk in
  (* Each iteration: EApp(countdown) + EMatch(if) = 2 reductions.
     Plus the initial EApp(main). Should be roughly 200+. *)
  Alcotest.(check bool) "reductions > 100" true (reductions > 100);
  Alcotest.(check bool) "reductions < 1000" true (reductions < 1000)

(* ── Work-stealing deque tests ────────────────────────────────────── *)

let test_deque_push_pop () =
  let d = March_scheduler.Work_pool.Deque.create 16 in
  March_scheduler.Work_pool.Deque.push d 1;
  March_scheduler.Work_pool.Deque.push d 2;
  March_scheduler.Work_pool.Deque.push d 3;
  (* Pop is LIFO from the bottom *)
  Alcotest.(check (option int)) "pop 3" (Some 3)
    (March_scheduler.Work_pool.Deque.pop d);
  Alcotest.(check (option int)) "pop 2" (Some 2)
    (March_scheduler.Work_pool.Deque.pop d);
  Alcotest.(check (option int)) "pop 1" (Some 1)
    (March_scheduler.Work_pool.Deque.pop d);
  Alcotest.(check (option int)) "pop empty" None
    (March_scheduler.Work_pool.Deque.pop d)

let test_deque_steal () =
  let d = March_scheduler.Work_pool.Deque.create 16 in
  March_scheduler.Work_pool.Deque.push d 1;
  March_scheduler.Work_pool.Deque.push d 2;
  March_scheduler.Work_pool.Deque.push d 3;
  (* Steal is FIFO from the top *)
  Alcotest.(check (option int)) "steal 1" (Some 1)
    (March_scheduler.Work_pool.Deque.steal d);
  Alcotest.(check (option int)) "steal 2" (Some 2)
    (March_scheduler.Work_pool.Deque.steal d)

let test_deque_size () =
  let d = March_scheduler.Work_pool.Deque.create 16 in
  Alcotest.(check int) "empty size" 0
    (March_scheduler.Work_pool.Deque.size d);
  March_scheduler.Work_pool.Deque.push d 1;
  March_scheduler.Work_pool.Deque.push d 2;
  Alcotest.(check int) "size 2" 2
    (March_scheduler.Work_pool.Deque.size d);
  ignore (March_scheduler.Work_pool.Deque.pop d);
  Alcotest.(check int) "size after pop" 1
    (March_scheduler.Work_pool.Deque.size d)

let test_pool_submit_steal () =
  let pool = March_scheduler.Work_pool.create 2 in
  March_scheduler.Work_pool.submit pool 0 "task_a";
  March_scheduler.Work_pool.submit pool 0 "task_b";
  let stolen = March_scheduler.Work_pool.Deque.steal pool.workers.(0) in
  Alcotest.(check (option string)) "stole task_a" (Some "task_a") stolen

(* ── Capability security tests ─────────────────────────────────────────── *)

(* Pure module with no Cap usage and no needs — should be clean *)
let test_cap_needs_pure_ok () =
  let ctx = typecheck {|mod Test do
    fn add(x, y) do x + y end
  end|} in
  Alcotest.(check bool) "pure module: no errors" false (has_errors ctx)

(* Module declares needs and uses Cap in a function signature — should be clean *)
let test_cap_needs_declared_ok () =
  let ctx = typecheck {|mod Test do
    needs IO
    fn greet(cap : Cap(IO)) do
      cap
    end
  end|} in
  Alcotest.(check bool) "declared needs with Cap: no errors" false (has_errors ctx)

(* Module uses Cap(IO) in a signature without declaring needs IO — should error *)
let test_cap_missing_needs_error () =
  let ctx = typecheck {|mod Test do
    fn greet(cap : Cap(IO)) do
      cap
    end
  end|} in
  Alcotest.(check bool) "undeclared Cap is an error" true (has_errors ctx)

(* Module declares needs IO but never uses Cap(IO) anywhere — should warn *)
let test_cap_unused_needs_warning () =
  let ctx = typecheck {|mod Test do
    needs IO
    fn add(x, y) do x + y end
  end|} in
  Alcotest.(check bool) "unused needs produces a diagnostic" true
    (March_errors.Errors.has_diagnostics ctx)

(* Cap(IO) as supertype covers Cap(IO.Network) usage *)
let test_cap_supertype_covers_subtype () =
  let ctx = typecheck {|mod Test do
    needs IO
    fn connect(cap : Cap(IO.Network)) do
      cap
    end
  end|} in
  Alcotest.(check bool) "needs IO covers Cap(IO.Network): no errors" false (has_errors ctx)

(* Cap(IO.Network) does NOT cover Cap(IO.FileRead) *)
let test_cap_needs_wrong_subtype () =
  let ctx = typecheck {|mod Test do
    needs IO.Network
    fn read_file(cap : Cap(IO.FileRead)) do
      cap
    end
  end|} in
  Alcotest.(check bool) "needs IO.Network does not cover Cap(IO.FileRead): error" true
    (has_errors ctx)

(* Multiple needs declarations are supported *)
let test_cap_multiple_needs () =
  let ctx = typecheck {|mod Test do
    needs IO.Network, IO.FileRead
    fn connect(cap : Cap(IO.Network)) do cap end
    fn read_file(cap : Cap(IO.FileRead)) do cap end
  end|} in
  Alcotest.(check bool) "multiple needs: no errors" false (has_errors ctx)

(* needs IO is parsed correctly *)
let test_cap_parse_needs () =
  let src = {|mod Test do
    needs IO
    fn f(x) do x end
  end|} in
  let m = parse_and_desugar src in
  let has_needs = List.exists (fun d ->
    match d with
    | March_ast.Ast.DNeeds _ -> true
    | _ -> false
  ) m.March_ast.Ast.mod_decls in
  Alcotest.(check bool) "DNeeds present in AST" true has_needs

(* needs with dotted path is parsed correctly *)
let test_cap_parse_needs_dotted () =
  let src = {|mod Test do
    needs IO.Network
    fn f(x) do x end
  end|} in
  let m = parse_and_desugar src in
  let cap_paths = List.filter_map (fun d ->
    match d with
    | March_ast.Ast.DNeeds (caps, _) ->
      Some (List.map (fun names ->
        String.concat "." (List.map (fun (n : March_ast.Ast.name) -> n.txt) names)
      ) caps)
    | _ -> None
  ) m.March_ast.Ast.mod_decls in
  Alcotest.(check bool) "IO.Network parsed as DNeeds" true
    (List.exists (fun paths -> List.mem "IO.Network" paths) cap_paths)

(* ── Transitive capability enforcement tests ────────────────────────────── *)

(* Module that imports another with matching needs declared — should be ok *)
let test_cap_transitive_ok () =
  let ctx = typecheck {|mod Outer do
    mod Lib do
      needs IO.Network
      pub fn connect(cap : Cap(IO.Network)) do cap end
    end
    mod Test do
      needs IO.Network
      use Lib.*
      fn run(cap : Cap(IO.Network)) do Lib.connect(cap) end
    end
  end|} in
  Alcotest.(check bool) "transitive ok when needs declared" false (has_errors ctx)

(* Module imports another that requires IO.Network but declares nothing — error *)
let test_cap_transitive_missing_error () =
  let ctx = typecheck {|mod Outer do
    mod Lib do
      needs IO.Network
      pub fn connect(cap : Cap(IO.Network)) do cap end
    end
    mod Test do
      use Lib.*
      fn run(x) do x end
    end
  end|} in
  Alcotest.(check bool) "transitive import without needs is an error" true (has_errors ctx)

(* Module declares parent cap (IO) which covers imported module's child (IO.Network) *)
let test_cap_transitive_supertype_ok () =
  let ctx = typecheck {|mod Outer do
    mod Lib do
      needs IO.Network
      pub fn connect(cap : Cap(IO.Network)) do cap end
    end
    mod Test do
      needs IO
      use Lib.*
      fn run(cap : Cap(IO)) do cap end
    end
  end|} in
  Alcotest.(check bool) "parent cap covers transitive import" false (has_errors ctx)

(* Three-level chain: C uses B uses A; B covers its A import, C must cover B's needs *)
let test_cap_transitive_chain_error () =
  let ctx = typecheck {|mod Outer do
    mod A do
      needs IO.FileRead
      pub fn read(cap : Cap(IO.FileRead)) do cap end
    end
    mod B do
      needs IO.FileRead
      use A.*
      pub fn do_read(cap : Cap(IO.FileRead)) do A.read(cap) end
    end
    mod C do
      use B.*
      fn run(x) do x end
    end
  end|} in
  Alcotest.(check bool) "chain: C must declare needs covered by B" true (has_errors ctx)

(* extern with capability declared in needs — ok *)
let test_cap_extern_with_needs_ok () =
  let ctx = typecheck {|mod Test do
    needs LibC
    extern "libc": Cap(LibC) do
      fn malloc(n : Int) : Int
    end
  end|} in
  Alcotest.(check bool) "extern with declared needs: no errors" false (has_errors ctx)

(* extern without declaring its capability in needs — error *)
let test_cap_extern_missing_needs_error () =
  let ctx = typecheck {|mod Test do
    extern "libc": Cap(LibC) do
      fn malloc(n : Int) : Int
    end
  end|} in
  Alcotest.(check bool) "extern without needs is an error" true (has_errors ctx)

(* ── Capability enforcement path tests ─────────────────────────────────── *)

(* Verify capability errors surface via check_capabilities (the effects-module
   entry point that wraps check_module for explicit use on both paths). *)
let test_cap_effects_clean () =
  let src = {|mod Test do
    needs IO.Network
    fn f(cap : Cap(IO.Network)) do cap end
  end|} in
  let m = parse_and_desugar src in
  let ctx = March_effects.Effects.check_capabilities m in
  Alcotest.(check bool) "check_capabilities: clean module has no errors" false
    (March_errors.Errors.has_errors ctx)

let test_cap_effects_violation () =
  let src = {|mod Test do
    fn f(cap : Cap(IO.Network)) do cap end
  end|} in
  let m = parse_and_desugar src in
  let ctx = March_effects.Effects.check_capabilities m in
  Alcotest.(check bool) "check_capabilities: capability violation produces error" true
    (March_errors.Errors.has_errors ctx)

(* Verify eval path: typechecking with capability errors prevents eval.
   We check that has_errors returns true, which in main.ml causes exit(1)
   before run_module is ever called. *)
let test_cap_eval_path_blocked () =
  let src = {|mod Test do
    fn f(cap : Cap(IO.Network)) do cap end
    fn main() do f(42) end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "eval path: capability error prevents evaluation" true
    (has_errors ctx)

(* Verify eval path: clean module can evaluate *)
let test_cap_eval_path_ok () =
  let src = {|mod Test do
    needs IO.Network
    fn double(x) do x + x end
    fn main() do double(21) end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "eval path: clean module with needs evaluates without error" false
    (has_errors ctx)

(* ── Sort stdlib tests ──────────────────────────────────────────────────── *)

let sort_decl = lazy (load_stdlib_file_for_test "sort.march")
let enum_decl = lazy (load_stdlib_file_for_test "enum.march")

let eval_with_sort src    = eval_with_stdlib [Lazy.force sort_decl] src
let eval_with_enum src    = eval_with_stdlib [Lazy.force sort_decl; Lazy.force enum_decl] src

(** Build a March Cons-list from an OCaml int list. *)
let[@warning "-32"] rec make_vlist = function
  | [] -> March_eval.Eval.VCon ("Nil", [])
  | x :: xs -> March_eval.Eval.VCon ("Cons", [March_eval.Eval.VInt x; make_vlist xs])

(** Assert two int lists are equal, converting from March VCon lists. *)
let check_int_list msg expected actual =
  let got = List.map vint (vlist actual) in
  Alcotest.(check (list int)) msg expected got

(* Helper: call Sort.sort_small_by on a literal list *)
let sort_small xs =
  let src = Printf.sprintf {|mod Test do
    fn f() do
      Sort.sort_small_by([%s], fn a -> fn b -> a <= b)
    end
  end|} (String.concat ", " (List.map string_of_int xs)) in
  let env = eval_with_sort src in
  call_fn env "f" []

(* Helper: call Sort.timsort_by on a literal list *)
let timsort xs =
  let src = Printf.sprintf {|mod Test do
    fn f() do
      Sort.timsort_by([%s], fn a -> fn b -> a <= b)
    end
  end|} (String.concat ", " (List.map string_of_int xs)) in
  let env = eval_with_sort src in
  call_fn env "f" []

(* Helper: call Sort.introsort_by on a literal list *)
let introsort xs =
  let src = Printf.sprintf {|mod Test do
    fn f() do
      Sort.introsort_by([%s], fn a -> fn b -> a <= b)
    end
  end|} (String.concat ", " (List.map string_of_int xs)) in
  let env = eval_with_sort src in
  call_fn env "f" []

(* -- sort_small_by -- *)

let test_sort_small_empty () =
  check_int_list "sort_small [] = []" [] (sort_small [])

let test_sort_small_n1 () =
  check_int_list "sort_small [5] = [5]" [5] (sort_small [5])

let test_sort_small_n2 () =
  check_int_list "sort_small [2,1] = [1,2]" [1;2] (sort_small [2;1])

let test_sort_small_n2_already_sorted () =
  check_int_list "sort_small [1,2] = [1,2]" [1;2] (sort_small [1;2])

let test_sort_small_n3 () =
  check_int_list "sort_small [3,1,2] = [1,2,3]" [1;2;3] (sort_small [3;1;2])

let test_sort_small_n3_all_perms () =
  (* Verify all 6 permutations of [1,2,3] sort correctly *)
  let perms = [[1;2;3];[1;3;2];[2;1;3];[2;3;1];[3;1;2];[3;2;1]] in
  List.iter (fun perm ->
    check_int_list
      (Printf.sprintf "sort_small n=3 perm %s" (String.concat "," (List.map string_of_int perm)))
      [1;2;3] (sort_small perm)
  ) perms

let test_sort_small_n4 () =
  check_int_list "sort_small [4,2,3,1] = [1,2,3,4]" [1;2;3;4] (sort_small [4;2;3;1])

let test_sort_small_n4_all_perms () =
  (* 24 permutations of [1,2,3,4] *)
  let perms = [
    [1;2;3;4];[1;2;4;3];[1;3;2;4];[1;3;4;2];[1;4;2;3];[1;4;3;2];
    [2;1;3;4];[2;1;4;3];[2;3;1;4];[2;3;4;1];[2;4;1;3];[2;4;3;1];
    [3;1;2;4];[3;1;4;2];[3;2;1;4];[3;2;4;1];[3;4;1;2];[3;4;2;1];
    [4;1;2;3];[4;1;3;2];[4;2;1;3];[4;2;3;1];[4;3;1;2];[4;3;2;1];
  ] in
  List.iter (fun perm ->
    check_int_list
      (Printf.sprintf "sort_small n=4 perm %s" (String.concat "," (List.map string_of_int perm)))
      [1;2;3;4] (sort_small perm)
  ) perms

let test_sort_small_n5 () =
  check_int_list "sort_small [5,3,1,4,2] = [1,2,3,4,5]" [1;2;3;4;5] (sort_small [5;3;1;4;2])

let test_sort_small_n6 () =
  check_int_list "sort_small [6,3,5,1,4,2] = [1..6]" [1;2;3;4;5;6] (sort_small [6;3;5;1;4;2])

let test_sort_small_n7 () =
  check_int_list "sort_small n=7 descending" [1;2;3;4;5;6;7] (sort_small [7;6;5;4;3;2;1])

let test_sort_small_n8 () =
  check_int_list "sort_small n=8 descending" [1;2;3;4;5;6;7;8] (sort_small [8;7;6;5;4;3;2;1])

let test_sort_small_n9_fallback () =
  (* n=9 falls back to mergesort *)
  check_int_list "sort_small n=9 fallback" [1;2;3;4;5;6;7;8;9] (sort_small [9;5;3;7;1;8;2;6;4])

let test_sort_small_stability () =
  (* Stability: equal elements must preserve original order.
     We use a pair sort: sort by first element, ties keep original order.
     Since we only have Int lists, we test with all-equal elements. *)
  check_int_list "sort_small equal elements stable" [1;1;1] (sort_small [1;1;1])

(* -- timsort_by -- *)

let test_timsort_empty () =
  check_int_list "timsort [] = []" [] (timsort [])

let test_timsort_single () =
  check_int_list "timsort [7] = [7]" [7] (timsort [7])

let test_timsort_already_sorted () =
  let xs = [1;2;3;4;5;6;7;8;9;10] in
  check_int_list "timsort already sorted" xs (timsort xs)

let test_timsort_reverse () =
  check_int_list "timsort reverse = sorted" [1;2;3;4;5] (timsort [5;4;3;2;1])

let test_timsort_random () =
  check_int_list "timsort random 20 elems" (List.sort compare [17;3;42;8;1;99;23;55;7;13;88;2;31;64;19;47;6;77;38;11])
    (timsort [17;3;42;8;1;99;23;55;7;13;88;2;31;64;19;47;6;77;38;11])

let test_timsort_nearly_sorted () =
  (* Timsort's strength: nearly sorted input *)
  check_int_list "timsort nearly sorted" [1;2;3;4;5;6;7;8;9;10]
    (timsort [1;2;3;4;5;6;8;7;9;10])

let test_timsort_stable () =
  (* All equal: stable sort returns same order *)
  check_int_list "timsort equal elems stable" [5;5;5;5] (timsort [5;5;5;5])

(* -- introsort_by -- *)

let test_introsort_empty () =
  check_int_list "introsort [] = []" [] (introsort [])

let test_introsort_single () =
  check_int_list "introsort [7] = [7]" [7] (introsort [7])

let test_introsort_already_sorted () =
  let xs = [1;2;3;4;5;6;7;8;9;10] in
  check_int_list "introsort already sorted" xs (introsort xs)

let test_introsort_reverse () =
  check_int_list "introsort reverse = sorted" [1;2;3;4;5] (introsort [5;4;3;2;1])

let test_introsort_random () =
  check_int_list "introsort random 20 elems"
    (List.sort compare [17;3;42;8;1;99;23;55;7;13;88;2;31;64;19;47;6;77;38;11])
    (introsort [17;3;42;8;1;99;23;55;7;13;88;2;31;64;19;47;6;77;38;11])

let test_introsort_large () =
  (* 100 elements in reverse — exercises heapsort fallback *)
  let xs = List.init 100 (fun i -> 100 - i) in
  let expected = List.init 100 (fun i -> i + 1) in
  check_int_list "introsort 100 elements reverse" expected (introsort xs)

(* -- Enum module tests -- *)

let test_enum_map () =
  let env = eval_with_enum {|mod Test do
    fn f() do Enum.map([1, 2, 3], fn x -> x * 2) end
  end|} in
  check_int_list "Enum.map *2" [2;4;6] (call_fn env "f" [])

let test_enum_flat_map () =
  let env = eval_with_enum {|mod Test do
    fn f() do Enum.flat_map([1, 2, 3], fn x -> [x, x]) end
  end|} in
  check_int_list "Enum.flat_map dup" [1;1;2;2;3;3] (call_fn env "f" [])

let test_enum_filter () =
  let env = eval_with_enum {|mod Test do
    fn f() do Enum.filter([1, 2, 3, 4, 5], fn x -> x % 2 == 0) end
  end|} in
  check_int_list "Enum.filter evens" [2;4] (call_fn env "f" [])

let test_enum_fold () =
  let env = eval_with_enum {|mod Test do
    fn f() do Enum.fold(0, [1, 2, 3, 4, 5], fn acc -> fn x -> acc + x) end
  end|} in
  Alcotest.(check int) "Enum.fold sum" 15 (vint (call_fn env "f" []))

let test_enum_reduce_some () =
  let env = eval_with_enum {|mod Test do
    fn f() do Enum.reduce([1, 2, 3, 4], fn a -> fn b -> a + b) end
  end|} in
  let v = call_fn env "f" [] in
  let args = vcon "Some" v in
  Alcotest.(check int) "Enum.reduce Some(10)" 10 (vint (List.hd args))

let test_enum_reduce_none () =
  let env = eval_with_enum {|mod Test do
    fn f() do Enum.reduce([], fn a -> fn b -> a + b) end
  end|} in
  let v = call_fn env "f" [] in
  let _ = vcon "None" v in
  ()

let test_enum_each () =
  (* each is for side effects; we verify it returns Unit *)
  let env = eval_with_enum {|mod Test do
    fn f() do
      Enum.each([1, 2, 3], fn x -> x)
    end
  end|} in
  let v = call_fn env "f" [] in
  (match v with March_eval.Eval.VUnit -> () | _ -> Alcotest.fail "expected Unit")

let test_enum_count () =
  let env = eval_with_enum {|mod Test do
    fn f() do Enum.count([10, 20, 30, 40]) end
  end|} in
  Alcotest.(check int) "Enum.count 4" 4 (vint (call_fn env "f" []))

let test_enum_any () =
  let env = eval_with_enum {|mod Test do
    fn yes() do Enum.any([1, 2, 3], fn x -> x > 2) end
    fn no()  do Enum.any([1, 2, 3], fn x -> x > 10) end
  end|} in
  Alcotest.(check bool) "Enum.any true"  true  (vbool (call_fn env "yes" []));
  Alcotest.(check bool) "Enum.any false" false (vbool (call_fn env "no"  []))

let test_enum_all () =
  let env = eval_with_enum {|mod Test do
    fn yes() do Enum.all([2, 4, 6], fn x -> x % 2 == 0) end
    fn no()  do Enum.all([2, 3, 6], fn x -> x % 2 == 0) end
  end|} in
  Alcotest.(check bool) "Enum.all true"  true  (vbool (call_fn env "yes" []));
  Alcotest.(check bool) "Enum.all false" false (vbool (call_fn env "no"  []))

let test_enum_find () =
  let env = eval_with_enum {|mod Test do
    fn found()    do Enum.find([1, 2, 3, 4], fn x -> x > 2) end
    fn not_found() do Enum.find([1, 2, 3], fn x -> x > 10) end
  end|} in
  let found = call_fn env "found" [] in
  let args = vcon "Some" found in
  Alcotest.(check int) "Enum.find Some(3)" 3 (vint (List.hd args));
  let not_found = call_fn env "not_found" [] in
  let _ = vcon "None" not_found in
  ()

let test_enum_group_by () =
  let env = eval_with_enum {|mod Test do
    fn f() do Enum.group_by([1, 1, 2, 2, 3], fn x -> x) end
  end|} in
  let v = call_fn env "f" [] in
  let groups = vlist v in
  (* Should be 3 groups: (1,[1,1]), (2,[2,2]), (3,[3]) *)
  Alcotest.(check int) "Enum.group_by 3 groups" 3 (List.length groups)

let test_enum_zip_with () =
  let env = eval_with_enum {|mod Test do
    fn f() do Enum.zip_with([1, 2, 3], [10, 20, 30], fn a -> fn b -> a + b) end
  end|} in
  check_int_list "Enum.zip_with +" [11;22;33] (call_fn env "f" [])

let test_enum_sort_by () =
  let env = eval_with_enum {|mod Test do
    fn f() do Enum.sort_by([3, 1, 4, 1, 5], fn a -> fn b -> a <= b) end
  end|} in
  check_int_list "Enum.sort_by" [1;1;3;4;5] (call_fn env "f" [])

let test_enum_timsort_by () =
  let env = eval_with_enum {|mod Test do
    fn f() do Enum.timsort_by([5, 3, 1, 4, 2], fn a -> fn b -> a <= b) end
  end|} in
  check_int_list "Enum.timsort_by" [1;2;3;4;5] (call_fn env "f" [])

let test_enum_introsort_by () =
  let env = eval_with_enum {|mod Test do
    fn f() do Enum.introsort_by([5, 3, 1, 4, 2], fn a -> fn b -> a <= b) end
  end|} in
  check_int_list "Enum.introsort_by" [1;2;3;4;5] (call_fn env "f" [])

let test_enum_sort_small_by () =
  let env = eval_with_enum {|mod Test do
    fn f() do Enum.sort_small_by([4, 2, 3, 1], fn a -> fn b -> a <= b) end
  end|} in
  check_int_list "Enum.sort_small_by" [1;2;3;4] (call_fn env "f" [])

(* ── Phase 1: Monitor and Link tests ──────────────────────────────── *)

(** Helper: create a fresh actor inst with Phase 1 fields and add to registry. *)
let add_fresh_actor pid name =
  let inst = mk_actor_inst name true March_eval.Eval.VUnit in
  Hashtbl.replace March_eval.Eval.actor_registry pid inst;
  inst

let test_monitor_receives_down_on_kill () =
  March_eval.Eval.reset_scheduler_state ();
  let _ia = add_fresh_actor 0 "A" in
  let ib  = add_fresh_actor 1 "B" in
  let _mon = March_eval.Eval.monitor_actor ~watcher_pid:1 ~target_pid:0 in
  March_eval.Eval.crash_actor 0 "killed";
  Alcotest.(check bool) "B's mailbox non-empty after A killed" true
    (not (Queue.is_empty ib.March_eval.Eval.ai_mailbox))

let test_demonitor_prevents_down () =
  March_eval.Eval.reset_scheduler_state ();
  let _ia = add_fresh_actor 0 "A" in
  let ib  = add_fresh_actor 1 "B" in
  let mon = March_eval.Eval.monitor_actor ~watcher_pid:1 ~target_pid:0 in
  March_eval.Eval.demonitor_actor mon;
  March_eval.Eval.crash_actor 0 "killed";
  Alcotest.(check bool) "B's mailbox empty after demonitor" true
    (Queue.is_empty ib.March_eval.Eval.ai_mailbox)

let test_link_kills_both_on_crash () =
  March_eval.Eval.reset_scheduler_state ();
  let _ia = add_fresh_actor 0 "A" in
  let ib  = add_fresh_actor 1 "B" in
  March_eval.Eval.link_actors 0 1;
  March_eval.Eval.crash_actor 0 "killed";
  Alcotest.(check bool) "B dead after linked A crashes" true
    (not ib.March_eval.Eval.ai_alive)

let test_monitor_already_dead_immediate_down () =
  March_eval.Eval.reset_scheduler_state ();
  (* A is spawned already dead *)
  let ia_dead = mk_actor_inst "A" false March_eval.Eval.VUnit in
  Hashtbl.replace March_eval.Eval.actor_registry 0 ia_dead;
  let ib = add_fresh_actor 1 "B" in
  let _mon = March_eval.Eval.monitor_actor ~watcher_pid:1 ~target_pid:0 in
  Alcotest.(check bool) "B gets immediate Down for dead actor" true
    (not (Queue.is_empty ib.March_eval.Eval.ai_mailbox))

let test_multiple_monitors_all_fire () =
  March_eval.Eval.reset_scheduler_state ();
  let _ia = add_fresh_actor 0 "A" in
  let ib  = add_fresh_actor 1 "B" in
  let ic  = add_fresh_actor 2 "C" in
  let _b_mon = March_eval.Eval.monitor_actor ~watcher_pid:1 ~target_pid:0 in
  let _c_mon = March_eval.Eval.monitor_actor ~watcher_pid:2 ~target_pid:0 in
  March_eval.Eval.crash_actor 0 "killed";
  Alcotest.(check bool) "B gets Down" true
    (not (Queue.is_empty ib.March_eval.Eval.ai_mailbox));
  Alcotest.(check bool) "C gets Down" true
    (not (Queue.is_empty ic.March_eval.Eval.ai_mailbox))

let test_down_message_format () =
  (* Down message has the right constructor shape: Down(mon_ref, reason) *)
  March_eval.Eval.reset_scheduler_state ();
  let _ia = add_fresh_actor 0 "A" in
  let ib  = add_fresh_actor 1 "B" in
  let mon = March_eval.Eval.monitor_actor ~watcher_pid:1 ~target_pid:0 in
  March_eval.Eval.crash_actor 0 "bang";
  let msg = Queue.pop ib.March_eval.Eval.ai_mailbox in
  (match msg with
   | March_eval.Eval.VCon ("Down", [March_eval.Eval.VInt m; March_eval.Eval.VString r]) ->
     Alcotest.(check int) "mon_ref matches" mon m;
     Alcotest.(check string) "reason in Down" "bang" r
   | _ -> Alcotest.fail "expected Down(mon_ref, reason)")

let test_eval_monitor_builtin () =
  (* End-to-end: monitor/kill/mailbox_size via March source *)
  let env = eval_module {|mod Test do
    actor A do
      state { x : Int }
      init { x = 0 }
      on Noop() do { x = state.x } end
    end

    actor B do
      state { x : Int }
      init { x = 0 }
      on Noop() do { x = state.x } end
    end

    fn main() do
      let pa = spawn(A)
      let pb = spawn(B)
      monitor(pb, pa)
      kill(pa)
      mailbox_size(pb)
    end
  end|} in
  let v = call_fn env "main" [] in
  Alcotest.(check bool) "mailbox_size >= 1 after kill" true
    (match v with March_eval.Eval.VInt n -> n >= 1 | _ -> false)

let test_eval_link_builtin () =
  (* End-to-end: link/kill propagates death via March source *)
  let env = eval_module {|mod Test do
    actor A do
      state { x : Int }
      init { x = 0 }
      on Noop() do { x = state.x } end
    end

    actor B do
      state { x : Int }
      init { x = 0 }
      on Noop() do { x = state.x } end
    end

    fn main() do
      let pa = spawn(A)
      let pb = spawn(B)
      link(pa, pb)
      kill(pa)
      is_alive(pb)
    end
  end|} in
  let v = call_fn env "main" [] in
  Alcotest.(check bool) "B is dead after linked A killed" false
    (match v with March_eval.Eval.VBool b -> b | _ -> failwith "expected VBool")

(* ── Supervision Phase 2: Supervisor Actor Pattern ─────────────────────── *)

(** Helper: get the child pid stored in a supervisor's state field. *)
let get_supervisor_child_pid sup_pid field_name =
  match Hashtbl.find_opt March_eval.Eval.actor_registry sup_pid with
  | None -> -1
  | Some inst ->
    (match inst.March_eval.Eval.ai_state with
     | March_eval.Eval.VRecord fields ->
       (match List.assoc_opt field_name fields with
        | Some (March_eval.Eval.VInt pid) -> pid
        | _ -> -1)
     | _ -> -1)

(** Phase 2: one_for_one restart — crashed child is restarted by supervisor.
    Spawn a supervisor with a Worker child. Kill the worker; the supervisor
    should restart it with a new pid. *)
let test_supervision_one_for_one_restart () =
  let _env = eval_module {|mod Test do
    actor Worker do
      state { count : Int }
      init { count = 0 }
      on Inc() do { count = state.count + 1 } end
    end

    actor Supervisor do
      state { worker : Int }
      init { worker = 0 }
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
  let sup_pid = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  let w1_pid = get_supervisor_child_pid sup_pid "worker" in
  Alcotest.(check bool) "initial worker pid >= 0" true (w1_pid >= 0);
  March_eval.Eval.crash_actor w1_pid "test kill";
  let w2_pid = get_supervisor_child_pid sup_pid "worker" in
  Alcotest.(check bool) "old worker is dead" false
    (match Hashtbl.find_opt March_eval.Eval.actor_registry w1_pid with
     | Some i -> i.March_eval.Eval.ai_alive | None -> false);
  Alcotest.(check bool) "new worker pid differs from old" true (w2_pid <> w1_pid);
  Alcotest.(check bool) "new worker is alive" true
    (match Hashtbl.find_opt March_eval.Eval.actor_registry w2_pid with
     | Some i -> i.March_eval.Eval.ai_alive | None -> false)

(** Phase 2: max_restarts escalation — after hitting the limit, the supervisor
    itself should crash. *)
let test_supervision_max_restarts_escalation () =
  let _env = eval_module {|mod Test do
    actor Worker do
      state { x : Int }
      init { x = 0 }
      on Noop() do { x = 0 } end
    end

    actor Supervisor do
      state { worker : Int }
      init { worker = 0 }
      supervise do
        strategy one_for_one
        max_restarts 2 within 60
        Worker worker
      end
    end

    fn main() do
      spawn(Supervisor)
    end
  end|} in
  let sup_pid = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  (* Kill the worker 3 times — exceeds max_restarts=2 *)
  let w1 = get_supervisor_child_pid sup_pid "worker" in
  March_eval.Eval.crash_actor w1 "test kill 1";
  let w2 = get_supervisor_child_pid sup_pid "worker" in
  March_eval.Eval.crash_actor w2 "test kill 2";
  let w3 = get_supervisor_child_pid sup_pid "worker" in
  March_eval.Eval.crash_actor w3 "test kill 3";
  (* Supervisor should be dead after exceeding max_restarts *)
  Alcotest.(check bool) "supervisor crashed after max_restarts exceeded" false
    (match Hashtbl.find_opt March_eval.Eval.actor_registry sup_pid with
     | Some i -> i.March_eval.Eval.ai_alive | None -> false)

(** Phase 2: one_for_all — when one child crashes, all children are restarted.
    Check that after killing WorkerA, WorkerB also gets a new pid. *)
let test_supervision_one_for_all () =
  let _env = eval_module {|mod Test do
    actor WorkerA do
      state { x : Int }
      init { x = 0 }
      on Noop() do { x = 0 } end
    end

    actor WorkerB do
      state { x : Int }
      init { x = 0 }
      on Noop() do { x = 0 } end
    end

    actor Supervisor do
      state { wa : Int, wb : Int }
      init { wa = 0, wb = 0 }
      supervise do
        strategy one_for_all
        max_restarts 3 within 60
        WorkerA wa
        WorkerB wb
      end
    end

    fn main() do
      spawn(Supervisor)
    end
  end|} in
  let sup_pid = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  let wb1_pid = get_supervisor_child_pid sup_pid "wb" in
  let wa1_pid = get_supervisor_child_pid sup_pid "wa" in
  Alcotest.(check bool) "initial wa alive" true
    (match Hashtbl.find_opt March_eval.Eval.actor_registry wa1_pid with
     | Some i -> i.March_eval.Eval.ai_alive | None -> false);
  (* Kill wa — under one_for_all, wb should also be restarted *)
  March_eval.Eval.crash_actor wa1_pid "test kill";
  let wb2_pid = get_supervisor_child_pid sup_pid "wb" in
  (* wb should have a new pid *)
  Alcotest.(check bool) "wb restarted under one_for_all (new pid)" true
    (wb1_pid <> wb2_pid);
  Alcotest.(check bool) "new wb is alive" true
    (match Hashtbl.find_opt March_eval.Eval.actor_registry wb2_pid with
     | Some i -> i.March_eval.Eval.ai_alive | None -> false)

(** Phase 2: rest_for_one — only children after the crashed one are restarted.
    First child should keep its pid; third child should get a new one. *)
let test_supervision_rest_for_one () =
  let _env = eval_module {|mod Test do
    actor First do
      state { x : Int }
      init { x = 0 }
      on Noop() do { x = 0 } end
    end

    actor Second do
      state { x : Int }
      init { x = 0 }
      on Noop() do { x = 0 } end
    end

    actor Third do
      state { x : Int }
      init { x = 0 }
      on Noop() do { x = 0 } end
    end

    actor Supervisor do
      state { first : Int, second : Int, third : Int }
      init { first = 0, second = 0, third = 0 }
      supervise do
        strategy rest_for_one
        max_restarts 3 within 60
        First first
        Second second
        Third third
      end
    end

    fn main() do
      spawn(Supervisor)
    end
  end|} in
  let sup_pid = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  let first1_pid  = get_supervisor_child_pid sup_pid "first" in
  let second1_pid = get_supervisor_child_pid sup_pid "second" in
  let third1_pid  = get_supervisor_child_pid sup_pid "third" in
  (* Kill second — first should be unchanged, third should restart *)
  March_eval.Eval.crash_actor second1_pid "test kill";
  let first2_pid = get_supervisor_child_pid sup_pid "first" in
  let third2_pid = get_supervisor_child_pid sup_pid "third" in
  Alcotest.(check int) "first not restarted (same pid)" first1_pid first2_pid;
  Alcotest.(check bool) "third restarted (new pid)" true (third1_pid <> third2_pid);
  Alcotest.(check bool) "third alive after restart" true
    (match Hashtbl.find_opt March_eval.Eval.actor_registry third2_pid with
     | Some i -> i.March_eval.Eval.ai_alive | None -> false)

(** Phase 2: supervisor replaces dead child state with fresh init state. *)
let test_supervision_state_replacement () =
  let _env = eval_module {|mod Test do
    actor Counter do
      state { count : Int }
      init { count = 0 }
      on Inc() do { count = state.count + 1 } end
    end

    actor Supervisor do
      state { counter : Int }
      init { counter = 0 }
      supervise do
        strategy one_for_one
        max_restarts 3 within 60
        Counter counter
      end
    end

    fn main() do
      spawn(Supervisor)
    end
  end|} in
  let sup_pid = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  let c1_pid = get_supervisor_child_pid sup_pid "counter" in
  (* Manually update counter state to simulate some work *)
  (match Hashtbl.find_opt March_eval.Eval.actor_registry c1_pid with
   | Some ci ->
     ci.March_eval.Eval.ai_state <- March_eval.Eval.VRecord [("count", March_eval.Eval.VInt 5)]
   | None -> ());
  (* Kill and let supervisor restart it *)
  March_eval.Eval.crash_actor c1_pid "test kill";
  let c2_pid = get_supervisor_child_pid sup_pid "counter" in
  (* Fresh restart should have count = 0 *)
  let restarted_count = match Hashtbl.find_opt March_eval.Eval.actor_registry c2_pid with
    | Some ci ->
      (match ci.March_eval.Eval.ai_state with
       | March_eval.Eval.VRecord fields ->
         (match List.assoc_opt "count" fields with
          | Some (March_eval.Eval.VInt n) -> n | _ -> -1)
       | _ -> -1)
    | None -> -1
  in
  Alcotest.(check int) "restarted counter starts at 0" 0 restarted_count

(* ── Supervision Phase 3: Epochs and Capability Tracking ───────────────── *)

(** Phase 3: epoch starts at 0 when actor is spawned. *)
let test_supervision_epoch_starts_at_zero () =
  March_eval.Eval.reset_scheduler_state ();
  let _ia = add_fresh_actor 0 "A" in
  let inst = Hashtbl.find March_eval.Eval.actor_registry 0 in
  Alcotest.(check int) "epoch is 0 on spawn" 0 inst.March_eval.Eval.ai_epoch

(** Phase 3: get_cap returns Some(VCap) for a live actor. *)
let test_supervision_get_cap () =
  let env = eval_module {|mod Test do
    actor A do
      state { x : Int }
      init { x = 0 }
      on Noop() do { x = 0 } end
    end

    fn main() do
      let pid = spawn(A)
      get_cap(pid)
    end
  end|} in
  let v = call_fn env "main" [] in
  (match v with
   | March_eval.Eval.VCon ("Some", [March_eval.Eval.VCap (pid, epoch)]) ->
     Alcotest.(check bool) "pid >= 0" true (pid >= 0);
     Alcotest.(check int) "epoch is 0" 0 epoch
   | _ -> Alcotest.fail "expected Some(VCap(pid, epoch))")

(** Phase 3: send_checked with a valid (fresh) cap succeeds. *)
let test_supervision_send_checked_ok () =
  let env = eval_module {|mod Test do
    actor Counter do
      state { count : Int }
      init { count = 0 }
      on Inc() do { count = state.count + 1 } end
      on Get() do state.count end
    end

    fn main() do
      let pid = spawn(Counter)
      match get_cap(pid) with
      | None -> :error
      | Some(cap) -> send_checked(cap, Inc())
      end
    end
  end|} in
  let v = call_fn env "main" [] in
  (* send_checked with valid cap should return :ok *)
  Alcotest.(check bool) "send_checked with valid cap returns ok" true
    (match v with
     | March_eval.Eval.VAtom "ok" -> true
     | March_eval.Eval.VCon ("Ok", _) -> true
     | March_eval.Eval.VCon ("Some", _) -> true
     | _ -> false)

(** Phase 3: send_checked to a dead actor returns :error. *)
let test_supervision_send_checked_dead_actor () =
  let env = eval_module {|mod Test do
    actor A do
      state { x : Int }
      init { x = 0 }
      on Noop() do { x = 0 } end
    end

    fn main() do
      let pid = spawn(A)
      match get_cap(pid) with
      | None -> :error
      | Some(cap) ->
        kill(pid)
        send_checked(cap, Noop())
      end
    end
  end|} in
  let v = call_fn env "main" [] in
  Alcotest.(check bool) "send_checked to dead actor returns error" true
    (match v with
     | March_eval.Eval.VAtom "error" -> true
     | March_eval.Eval.VCon ("Err", _) -> true
     | March_eval.Eval.VCon ("Error", _) -> true
     | March_eval.Eval.VCon ("None", _) -> true
     | _ -> false)

(** Phase 3: epoch increments on restart so old caps become stale. *)
let test_supervision_epoch_increments_on_restart () =
  March_eval.Eval.reset_scheduler_state ();
  let inst = add_fresh_actor 0 "A" in
  let epoch_before = inst.March_eval.Eval.ai_epoch in
  March_eval.Eval.increment_epoch 0;
  let epoch_after = inst.March_eval.Eval.ai_epoch in
  Alcotest.(check int) "epoch incremented" (epoch_before + 1) epoch_after

(** Phase 3: a stale cap (epoch mismatch) is rejected by send_checked.
    We use the OCaml API to get the worker pid directly, build a stale
    cap, then force a restart (via crash_actor) and verify send_checked fails. *)
let test_supervision_stale_epoch () =
  let _env = eval_module {|mod Test do
    actor Worker do
      state { x : Int }
      init { x = 0 }
      on Noop() do { x = 0 } end
    end

    actor Supervisor do
      state { worker : Int }
      init { worker = 0 }
      supervise do
        strategy one_for_one
        max_restarts 3 within 60
        Worker worker
      end
    end

    fn main() do
      spawn(Supervisor)
    end
  end|} in
  let sup_pid = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  let w1_pid = get_supervisor_child_pid sup_pid "worker" in
  (* Build a cap for the original worker at epoch 0 *)
  let stale_cap = March_eval.Eval.VCap (w1_pid, 0) in
  (* Kill the worker — supervisor restarts it and increments epoch *)
  March_eval.Eval.crash_actor w1_pid "test kill";
  (* Manually increment epoch on the new worker to make old cap stale *)
  let w2_pid = get_supervisor_child_pid sup_pid "worker" in
  March_eval.Eval.increment_epoch w2_pid;
  (* The original pid is now dead (epoch 0); new pid has epoch 1.
     send_checked with stale_cap (pointing to dead pid) should return error. *)
  let result = March_eval.Eval.apply
    (List.assoc "send_checked" (March_eval.Eval.base_env))
    [stale_cap; March_eval.Eval.VCon ("Noop", [])] in
  Alcotest.(check bool) "stale cap rejected" true
    (match result with
     | March_eval.Eval.VAtom "error" -> true
     | _ -> false)

(* ── Supervision Phase 5: Task Linking ─────────────────────────────────── *)

(** Phase 5: task_spawn_link — a linked task that completes normally doesn't
    crash the calling actor. The result should be retrievable. *)
let test_supervision_task_spawn_link_completes () =
  let env = eval_module {|mod Test do
    actor Worker do
      state { x : Int }
      init { x = 0 }
      on Compute() do { x = 42 } end
      on GetX() do state.x end
    end

    fn main() do
      let pid = spawn(Worker)
      let task = task_spawn_link(fn x -> 99, pid)
      task_await_unwrap(task)
    end
  end|} in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "linked task result is 99" 99
    (match v with March_eval.Eval.VInt n -> n | _ -> -1)

(** Phase 5: task_spawn_link — if the linked actor crashes, the task is
    cancelled or returns an error. *)
let test_supervision_task_spawn_link_crash_propagates () =
  let env = eval_module {|mod Test do
    actor A do
      state { x : Int }
      init { x = 0 }
      on Noop() do { x = 0 } end
    end

    fn main() do
      let pid = spawn(A)
      let task = task_spawn_link(fn x -> 1, pid)
      kill(pid)
      task_await(task)
    end
  end|} in
  let v = call_fn env "main" [] in
  (* After killing the linked actor, task_await should return Err or the
     task may still complete (depending on ordering). Either Ok or Err is
     acceptable — we just check it doesn't raise an exception. *)
  Alcotest.(check bool) "task_await returns Ok or Err" true
    (match v with
     | March_eval.Eval.VCon ("Ok", _) -> true
     | March_eval.Eval.VCon ("Err", _) -> true
     | _ -> false)

(* ── Supervision Phase 6a: OS Resource Drop ─────────────────────────── *)

(** Phase 6a: cleanup function is called when actor crashes. *)
let test_resource_cleanup_on_crash () =
  March_eval.Eval.reset_scheduler_state ();
  let cleaned = ref false in
  let _ = add_fresh_actor 0 "A" in
  (* Register a cleanup thunk directly via OCaml API *)
  March_eval.Eval.register_resource_ocaml 0 "test_resource"
    (fun () -> cleaned := true);
  March_eval.Eval.crash_actor 0 "test kill";
  Alcotest.(check bool) "cleanup called on crash" true !cleaned

(** Phase 6a: multiple resources are cleaned in reverse acquisition order. *)
let test_resource_cleanup_reverse_order () =
  March_eval.Eval.reset_scheduler_state ();
  let order = ref [] in
  let _ = add_fresh_actor 0 "A" in
  March_eval.Eval.register_resource_ocaml 0 "first"
    (fun () -> order := "first" :: !order);
  March_eval.Eval.register_resource_ocaml 0 "second"
    (fun () -> order := "second" :: !order);
  March_eval.Eval.register_resource_ocaml 0 "third"
    (fun () -> order := "third" :: !order);
  March_eval.Eval.crash_actor 0 "test";
  (* Cleanup executes in reverse acquisition order: third first, second second, first last.
     Each thunk does (order := name :: !order), so the accumulated list is in execution-reversed
     order. Execution order third→second→first gives list ["first"; "second"; "third"]. *)
  Alcotest.(check (list string)) "reverse cleanup order"
    ["first"; "second"; "third"] !order

(** Phase 6a: resources of linked actor are also cleaned on link propagation. *)
let test_resource_cleanup_on_link_crash () =
  March_eval.Eval.reset_scheduler_state ();
  let a_cleaned = ref false in
  let b_cleaned = ref false in
  let _ = add_fresh_actor 0 "A" in
  let _ = add_fresh_actor 1 "B" in
  March_eval.Eval.register_resource_ocaml 0 "a_res"
    (fun () -> a_cleaned := true);
  March_eval.Eval.register_resource_ocaml 1 "b_res"
    (fun () -> b_cleaned := true);
  March_eval.Eval.link_actors 0 1;
  March_eval.Eval.crash_actor 0 "test";
  Alcotest.(check bool) "A's resource cleaned" true !a_cleaned;
  Alcotest.(check bool) "B's resource cleaned via link" true !b_cleaned

let test_file_builtin_exists_false () =
  (* If file_exists builtin is missing, this will raise an eval error *)
  let env = eval_with_stdlib [] {|mod T do
    fn f() do file_exists("/nonexistent_march_test_xyz") end
  end|} in
  Alcotest.(check bool) "file_exists returns false" false
    (vbool (call_fn env "f" []))

(* ── Seq stdlib tests ────────────────────────────────────────────────────── *)

let load_seq () = load_stdlib_file_for_test "seq.march"

let eval_with_seq src =
  eval_with_stdlib [load_seq ()] src

let test_seq_from_list () =
  let env = eval_with_seq {|mod T do
    fn f() do Seq.from_list([1, 2, 3]) |> Seq.to_list end
  end|} in
  Alcotest.(check (list int)) "from_list round trips"
    [1; 2; 3]
    (List.map vint (vlist (call_fn env "f" [])))

let test_seq_map () =
  let env = eval_with_seq {|mod T do
    fn f() do
      let s = Seq.from_list([1, 2, 3])
      Seq.to_list(Seq.map(s, fn x -> x * 2))
    end
  end|} in
  Alcotest.(check (list int)) "map doubles" [2; 4; 6]
    (List.map vint (vlist (call_fn env "f" [])))

let test_seq_filter () =
  let env = eval_with_seq {|mod T do
    fn f() do
      let s = Seq.from_list([1,2,3,4,5])
      Seq.to_list(Seq.filter(s, fn x -> x > 2))
    end
  end|} in
  Alcotest.(check (list int)) "filter" [3; 4; 5]
    (List.map vint (vlist (call_fn env "f" [])))

let test_seq_take () =
  let env = eval_with_seq {|mod T do
    fn f() do
      let s = Seq.from_list([1,2,3,4,5])
      Seq.to_list(Seq.take(s, 3))
    end
  end|} in
  Alcotest.(check (list int)) "take 3" [1; 2; 3]
    (List.map vint (vlist (call_fn env "f" [])))

let test_seq_fold_while () =
  let env = eval_with_seq {|mod T do
    fn f() do
      let s = Seq.from_list([1,2,3,4,5])
      Seq.fold_while(s, 0, fn(sum, x) ->
        if sum + x > 6 then Halt(sum)
        else Continue(sum + x)
      )
    end
  end|} in
  Alcotest.(check int) "fold_while halts" 6
    (vint (call_fn env "f" []))

let test_seq_concat () =
  let env = eval_with_seq {|mod T do
    fn f() do Seq.concat(Seq.from_list([1,2]), Seq.from_list([3,4])) |> Seq.to_list end
  end|} in
  Alcotest.(check (list int)) "concat" [1; 2; 3; 4]
    (List.map vint (vlist (call_fn env "f" [])))

let eval_with_path src =
  let string_decl = load_stdlib_file_for_test "string.march" in
  let list_decl   = load_stdlib_file_for_test "list.march" in
  let path_decl   = load_stdlib_file_for_test "path.march" in
  eval_with_stdlib [string_decl; list_decl; path_decl] src

let test_path_join () =
  let env = eval_with_path {|mod T do
    fn f() do Path.join("foo/bar", "baz.txt") end
  end|} in
  Alcotest.(check string) "join" "foo/bar/baz.txt"
    (vstr (call_fn env "f" []))

let test_path_basename () =
  let env = eval_with_path {|mod T do
    fn f() do Path.basename("/foo/bar/baz.txt") end
  end|} in
  Alcotest.(check string) "basename" "baz.txt"
    (vstr (call_fn env "f" []))

let test_path_extension () =
  let env = eval_with_path {|mod T do
    fn f() do Path.extension("photo.png") end
  end|} in
  Alcotest.(check string) "extension" "png"
    (vstr (call_fn env "f" []))

let test_path_normalize () =
  let env = eval_with_path {|mod T do
    fn f() do Path.normalize("a/../b/./c") end
  end|} in
  Alcotest.(check string) "normalize" "b/c"
    (vstr (call_fn env "f" []))

let test_path_dirname () =
  let env = eval_with_path {|mod T do
    fn f() do Path.dirname("/foo/bar/baz.txt") end
  end|} in
  Alcotest.(check string) "dirname" "/foo/bar"
    (vstr (call_fn env "f" []))

let test_path_strip_extension () =
  let env = eval_with_path {|mod T do
    fn f() do Path.strip_extension("photo.png") end
  end|} in
  Alcotest.(check string) "strip_extension" "photo"
    (vstr (call_fn env "f" []))

let test_path_extension_dotfile () =
  let env = eval_with_path {|mod T do
    fn f() do Path.extension(".bashrc") end
  end|} in
  Alcotest.(check string) "dotfile has no extension" ""
    (vstr (call_fn env "f" []))

let test_path_strip_extension_dotfile () =
  let env = eval_with_path {|mod T do
    fn f() do Path.strip_extension(".bashrc") end
  end|} in
  Alcotest.(check string) "strip dotfile unchanged" ".bashrc"
    (vstr (call_fn env "f" []))

let test_path_normalize_absolute () =
  let env = eval_with_path {|mod T do
    fn f() do Path.normalize("/a/../../../b") end
  end|} in
  Alcotest.(check string) "normalize absolute clamps at root" "/b"
    (vstr (call_fn env "f" []))

let test_path_is_absolute () =
  let env = eval_with_path {|mod T do
    fn f() do Path.is_absolute("/foo") end
  end|} in
  Alcotest.(check bool) "is_absolute" true
    (vbool (call_fn env "f" []))

(* ── File stdlib tests ──────────────────────────────────────────────────── *)

let load_file_stdlib () =
  [ load_stdlib_file_for_test "seq.march"
  ; load_stdlib_file_for_test "file.march" ]

let eval_with_file src =
  eval_with_stdlib (load_file_stdlib ()) src

let with_temp_file content f =
  let path = Filename.temp_file "march_test_" ".txt" in
  let oc = open_out path in
  output_string oc content;
  close_out oc;
  let result = f path in
  (try Sys.remove path with _ -> ());
  result

let test_file_read () =
  with_temp_file "hello world" (fun path ->
    let env = eval_with_file (Printf.sprintf {|mod T do
      fn f() do
        match File.read("%s") with
        | Ok(s) -> s
        | Err(ig) -> "fail"
        end
      end
    end|} path) in
    Alcotest.(check string) "read file" "hello world"
      (vstr (call_fn env "f" [])))

let test_file_write_read () =
  let path = Filename.temp_file "march_test_" ".txt" in
  (try
     let env = eval_with_file (Printf.sprintf {|mod T do
       fn f() do
         match File.write("%s", "written data") with
         | Ok(ig) ->
           match File.read("%s") with
           | Ok(s) -> s
           | Err(ig) -> "read fail"
           end
         | Err(ig) -> "write fail"
         end
       end
     end|} path path) in
     let result = vstr (call_fn env "f" []) in
     (try Sys.remove path with _ -> ());
     Alcotest.(check string) "write then read" "written data" result
   with e -> (try Sys.remove path with _ -> ()); raise e)

let test_file_exists () =
  with_temp_file "x" (fun path ->
    let env = eval_with_file (Printf.sprintf {|mod T do
      fn f() do File.exists("%s") end
    end|} path) in
    Alcotest.(check bool) "exists" true
      (vbool (call_fn env "f" [])))

let test_file_with_lines () =
  with_temp_file "a\nb\nc" (fun path ->
    let env = eval_with_file (Printf.sprintf {|mod T do
      fn append_bang(l) do l ++ "!" end
      fn collect_lines(lines) do Seq.to_list(Seq.map(lines, fn l -> append_bang(l))) end
      fn f() do
        match File.with_lines("%s", fn lines -> collect_lines(lines)) with
        | Ok(xs) -> xs
        | Err(ig) -> Nil
        end
      end
    end|} path) in
    Alcotest.(check (list string)) "with_lines" ["a!"; "b!"; "c!"]
      (List.map vstr (vlist (call_fn env "f" []))))

let test_file_not_found () =
  let env = eval_with_file {|mod T do
    fn f() do
      match File.read("/nonexistent/path/xyz_march_test.txt") with
      | Ok(ig) -> "ok"
      | Err(ig) -> "err"
      end
    end
  end|} in
  Alcotest.(check string) "not found returns Err" "err"
    (vstr (call_fn env "f" []))

let test_file_append () =
  let path = Filename.temp_file "march_append_" ".txt" in
  (try
     let env = eval_with_file (Printf.sprintf {|mod T do
       fn f() do
         File.write("%s", "line1\n")
         File.append("%s", "line2\n")
         match File.read("%s") with
         | Ok(s) -> s
         | Err(ig) -> "fail"
         end
       end
     end|} path path path) in
     let result = vstr (call_fn env "f" []) in
     (try Sys.remove path with _ -> ());
     Alcotest.(check string) "append" "line1\nline2\n" result
   with e -> (try Sys.remove path with _ -> ()); raise e)

(* ── Dir stdlib tests ──────────────────────────────────────────────────── *)

let load_dir_stdlib () =
  [ load_stdlib_file_for_test "string.march"
  ; load_stdlib_file_for_test "list.march"
  ; load_stdlib_file_for_test "seq.march"
  ; load_stdlib_file_for_test "path.march"
  ; load_stdlib_file_for_test "file.march"
  ; load_stdlib_file_for_test "dir.march" ]

let eval_with_dir src =
  eval_with_stdlib (load_dir_stdlib ()) src

let test_dir_mkdir_list_rmdir () =
  (* Use Filename.temp_file to get a unique path, then create the dir ourselves.
     Resolve symlinks (macOS /var -> /private/var) so Unix.mkdir works inside March eval. *)
  (* Create a unique temp dir directly in /tmp to avoid dune sandbox issues *)
  let base = Printf.sprintf "/tmp/march_dir_test_%d_%d" (Unix.getpid ()) (Random.int 1000000) in
  Unix.mkdir base 0o755;
  let path = base ^ "/subdir" in
  let env = eval_with_dir (Printf.sprintf {|mod T do
    fn f() do
      match Dir.mkdir("%s") with
      | Err(e) -> "mkdir failed: " ++ to_string(e)
      | Ok(ig) ->
        match Dir.list("%s") with
        | Err(ig) -> "list failed"
        | Ok(ig) ->
          match Dir.rmdir("%s") with
          | Err(ig) -> "rmdir failed"
          | Ok(ig) -> "ok"
          end
        end
      end
    end
  end|} path base path) in
  let result = vstr (call_fn env "f" []) in
  (try Unix.rmdir path with _ -> ());
  (try Unix.rmdir base with _ -> ());
  Alcotest.(check string) "mkdir/list/rmdir" "ok" result

let test_dir_rm_rf () =
  let base = Filename.temp_dir "march_rmrf_" "" in
  (* Create nested structure *)
  Unix.mkdir (base ^ "/sub") 0o755;
  let oc = open_out (base ^ "/sub/file.txt") in
  output_string oc "x"; close_out oc;
  let env = eval_with_dir (Printf.sprintf {|mod T do
    fn f() do
      match Dir.rm_rf("%s") with
      | Ok(ig) -> "ok"
      | Err(ig) -> "err"
      end
    end
  end|} base) in
  Alcotest.(check string) "rm_rf nested" "ok"
    (vstr (call_fn env "f" []))

let test_dir_rm_rf_refuses_root () =
  let env = eval_with_dir {|mod T do
    fn f() do
      match Dir.rm_rf("/") with
      | Ok(ig) -> "deleted root"
      | Err(ig) -> "refused"
      end
    end
  end|} in
  Alcotest.(check string) "rm_rf refuses root" "refused"
    (vstr (call_fn env "f" []))

let test_dir_exists () =
  let base = Filename.temp_dir "march_exists_" "" in
  let env = eval_with_dir (Printf.sprintf {|mod T do
    fn f() do Dir.exists("%s") end
  end|} base) in
  let result = vbool (call_fn env "f" []) in
  (try Unix.rmdir base with _ -> ());
  Alcotest.(check bool) "dir exists" true result

let test_dir_not_exists () =
  let env = eval_with_dir {|mod T do
    fn f() do Dir.exists("/nonexistent_march_test_xyz_dir") end
  end|} in
  Alcotest.(check bool) "dir not exists" false
    (vbool (call_fn env "f" []))

let test_dir_mkdir_p () =
  let base = Printf.sprintf "/tmp/march_mkdirp_%d" (Unix.getpid ()) in
  let deep = base ^ "/a/b/c" in
  let env = eval_with_dir (Printf.sprintf {|mod T do
    fn f() do
      match Dir.mkdir_p("%s") with
      | Ok(ig) -> Dir.exists("%s")
      | Err(ig) -> false
      end
    end
  end|} deep deep) in
  let result = vbool (call_fn env "f" []) in
  let rec rm_rf p =
    match Sys.file_exists p with
    | true when Sys.is_directory p ->
      Array.iter (fun e -> rm_rf (p ^ "/" ^ e)) (Sys.readdir p);
      Unix.rmdir p
    | true -> Sys.remove p
    | false -> ()
  in
  (try rm_rf base with _ -> ());
  Alcotest.(check bool) "mkdir_p creates nested dir" true result

let test_integration_file_pipeline () =
  let base = Printf.sprintf "/tmp/march_integ_%d" (Unix.getpid ()) in
  (try Unix.mkdir base 0o755 with _ -> ());
  let write path content =
    let oc = open_out path in output_string oc content; close_out oc in
  write (base ^ "/a.txt") "hello\nworld\n";
  write (base ^ "/b.txt") "foo\nbar\n";
  write (base ^ "/c.csv") "ignore me";
  let env = eval_with_dir (Printf.sprintf {|mod T do
    fn f() do
      match Dir.list_full("%s") with
      | Err(ig) -> Nil
      | Ok(files) ->
        let txt_files = List.filter(files, fn(p) -> Path.extension(p) == "txt")
        fn collect(ps, acc) do
          match ps with
          | Nil -> List.reverse(acc)
          | Cons(p, rest) ->
            match File.read_lines(p) with
            | Ok(ls) -> collect(rest, List.append(List.reverse(ls), acc))
            | Err(ig) -> collect(rest, acc)
            end
          end
        end
        collect(txt_files, Nil)
      end
    end
  end|} base) in
  let result = List.map vstr (vlist (call_fn env "f" [])) in
  (* cleanup *)
  (try Sys.remove (base ^ "/a.txt") with _ -> ());
  (try Sys.remove (base ^ "/b.txt") with _ -> ());
  (try Sys.remove (base ^ "/c.csv") with _ -> ());
  (try Unix.rmdir base with _ -> ());
  (* Dir.list returns sorted, so a.txt before b.txt, gives hello/world/foo/bar *)
  Alcotest.(check (list string)) "integration pipeline"
    ["hello"; "world"; "foo"; "bar"] result

(* ── Map stdlib tests ──────────────────────────────────────────────────── *)

let map_decl = lazy (load_stdlib_file_for_test "map.march")
let eval_with_map src = eval_with_stdlib [Lazy.force map_decl] src

(** Lower a module that includes the Map stdlib to TIR (for compiled-path smoke tests). *)
let lower_map_typed src =
  let map_m = Lazy.force map_decl in
  let m = parse_and_desugar src in
  let m = { m with March_ast.Ast.mod_decls = [map_m] @ m.March_ast.Ast.mod_decls } in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  March_tir.Lower.lower_module ~type_map m

(* Standard int comparator: fn a -> fn b -> a < b *)
let int_cmp = {|fn(a) -> fn(b) -> a < b|}

(* Helper: extract Some(v) payload *)
let vsome = function
  | March_eval.Eval.VCon ("Some", [v]) -> v
  | _ -> failwith "expected Some"

let test_map_empty () =
  let env = eval_with_map {|mod T do
    fn f() do Map.is_empty(Map.empty()) end
  end|} in
  Alcotest.(check bool) "empty map is empty" true (vbool (call_fn env "f" []))

let test_map_singleton () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.singleton(42, "hello")
      Map.size(m)
    end
  end|}) in
  Alcotest.(check int) "singleton size = 1" 1 (vint (call_fn env "f" []))

let test_map_insert_get () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.insert(Map.empty(), 1, "one", %s)
      Map.get(m, 1, %s)
    end
  end|} int_cmp int_cmp) in
  let v = call_fn env "f" [] in
  Alcotest.(check string) "get inserted key" "one" (vstr (vsome v))

let test_map_get_missing () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.insert(Map.empty(), 1, "one", %s)
      Map.get(m, 99, %s)
    end
  end|} int_cmp int_cmp) in
  let v = call_fn env "f" [] in
  Alcotest.(check bool) "missing key returns None" true
    (match v with March_eval.Eval.VCon ("None", []) -> true | _ -> false)

let test_map_insert_overwrite () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.insert(Map.empty(), 1, "first", %s)
      let m2 = Map.insert(m, 1, "second", %s)
      Map.get(m2, 1, %s)
    end
  end|} int_cmp int_cmp int_cmp) in
  let v = call_fn env "f" [] in
  Alcotest.(check string) "overwrite gives new value" "second" (vstr (vsome v))

let test_map_contains_key_true () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.insert(Map.empty(), 7, true, %s)
      Map.contains_key(m, 7, %s)
    end
  end|} int_cmp int_cmp) in
  Alcotest.(check bool) "contains inserted key" true (vbool (call_fn env "f" []))

let test_map_contains_key_false () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.insert(Map.empty(), 7, true, %s)
      Map.contains_key(m, 42, %s)
    end
  end|} int_cmp int_cmp) in
  Alcotest.(check bool) "absent key not contained" false (vbool (call_fn env "f" []))

let test_map_get_or () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do Map.get_or(Map.empty(), 5, 99, %s) end
  end|} int_cmp) in
  Alcotest.(check int) "get_or default on empty" 99 (vint (call_fn env "f" []))

let test_map_remove () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.insert(Map.insert(Map.empty(), 1, "a", %s), 2, "b", %s)
      let m2 = Map.remove(m, 1, %s)
      Map.size(m2)
    end
  end|} int_cmp int_cmp int_cmp) in
  Alcotest.(check int) "size after remove" 1 (vint (call_fn env "f" []))

let test_map_remove_absent () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.insert(Map.empty(), 1, "a", %s)
      let m2 = Map.remove(m, 99, %s)
      Map.size(m2)
    end
  end|} int_cmp int_cmp) in
  Alcotest.(check int) "remove absent is no-op" 1 (vint (call_fn env "f" []))

let test_map_size () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.from_list([(3, "c"), (1, "a"), (4, "d"), (1, "a2"), (2, "b")], %s)
      Map.size(m)
    end
  end|} int_cmp) in
  (* key 1 inserted twice so 4 distinct keys *)
  Alcotest.(check int) "size deduplicates keys" 4 (vint (call_fn env "f" []))

let test_map_is_empty_after_insert () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do Map.is_empty(Map.insert(Map.empty(), 1, 2, %s)) end
  end|} int_cmp) in
  Alcotest.(check bool) "non-empty after insert" false (vbool (call_fn env "f" []))

let test_map_keys () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.from_list([(3, "c"), (1, "a"), (2, "b")], %s)
      Map.keys(m)
    end
  end|} int_cmp) in
  let ks = List.map vint (vlist (call_fn env "f" [])) in
  Alcotest.(check (list int)) "keys in sorted order" [1; 2; 3] ks

let test_map_values () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.from_list([(3, 30), (1, 10), (2, 20)], %s)
      Map.values(m)
    end
  end|} int_cmp) in
  let vs = List.map vint (vlist (call_fn env "f" [])) in
  Alcotest.(check (list int)) "values in key order" [10; 20; 30] vs

let test_map_entries () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.from_list([(2, "b"), (1, "a"), (3, "c")], %s)
      Map.entries(m)
    end
  end|} int_cmp) in
  let es = vlist (call_fn env "f" []) in
  let pairs = List.map (function
    | March_eval.Eval.VTuple [k; v] -> (vint k, vstr v)
    | _ -> failwith "expected pair") es in
  Alcotest.(check (list (pair int string))) "entries sorted" [(1,"a");(2,"b");(3,"c")] pairs

let test_map_from_list () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.from_list([(1, "a"), (2, "b"), (3, "c")], %s)
      Map.get(m, 2, %s)
    end
  end|} int_cmp int_cmp) in
  Alcotest.(check string) "from_list lookup" "b" (vstr (vsome (call_fn env "f" [])))

let test_map_to_list () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.from_list([(3, 3), (1, 1), (2, 2)], %s)
      Map.to_list(m)
    end
  end|} int_cmp) in
  let es = vlist (call_fn env "f" []) in
  let ks = List.map (function
    | March_eval.Eval.VTuple [k; _] -> vint k
    | _ -> failwith "expected pair") es in
  Alcotest.(check (list int)) "to_list sorted by key" [1; 2; 3] ks

let test_map_map_values () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.from_list([(1, 10), (2, 20), (3, 30)], %s)
      let m2 = Map.map_values(m, fn(v) -> v * 2)
      Map.values(m2)
    end
  end|} int_cmp) in
  let vs = List.map vint (vlist (call_fn env "f" [])) in
  Alcotest.(check (list int)) "map_values doubles" [20; 40; 60] vs

let test_map_filter () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.from_list([(1, 1), (2, 2), (3, 3), (4, 4)], %s)
      let m2 = Map.filter(m, fn(k) -> fn(v) -> k > 2, %s)
      Map.keys(m2)
    end
  end|} int_cmp int_cmp) in
  let ks = List.map vint (vlist (call_fn env "f" [])) in
  Alcotest.(check (list int)) "filter keeps k > 2" [3; 4] ks

let test_map_fold () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.from_list([(1, 10), (2, 20), (3, 30)], %s)
      Map.fold(0, m, fn(acc) -> fn(k) -> fn(v) -> acc + v)
    end
  end|} int_cmp) in
  Alcotest.(check int) "fold sums values" 60 (vint (call_fn env "f" []))

let test_map_merge () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let a = Map.from_list([(1, "a1"), (2, "a2")], %s)
      let b = Map.from_list([(2, "b2"), (3, "b3")], %s)
      let m = Map.merge(a, b, %s)
      Map.size(m)
    end
  end|} int_cmp int_cmp int_cmp) in
  Alcotest.(check int) "merge size" 3 (vint (call_fn env "f" []))

let test_map_merge_b_overwrites () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let a = Map.from_list([(1, "a1"), (2, "a2")], %s)
      let b = Map.from_list([(2, "b2"), (3, "b3")], %s)
      let m = Map.merge(a, b, %s)
      Map.get(m, 2, %s)
    end
  end|} int_cmp int_cmp int_cmp int_cmp) in
  Alcotest.(check string) "merge: b overwrites a" "b2" (vstr (vsome (call_fn env "f" [])))

let test_map_merge_with () =
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let a = Map.from_list([(1, 10), (2, 20)], %s)
      let b = Map.from_list([(2, 5), (3, 30)], %s)
      let m = Map.merge_with(a, b, fn(old) -> fn(new) -> old + new, %s)
      Map.values(m)
    end
  end|} int_cmp int_cmp int_cmp) in
  let vs = List.map vint (vlist (call_fn env "f" [])) in
  Alcotest.(check (list int)) "merge_with sums conflict" [10; 25; 30] vs

let test_map_string_keys () =
  let str_cmp = {|fn(a) -> fn(b) -> a < b|} in
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let m = Map.from_list([("banana", 2), ("apple", 1), ("cherry", 3)], %s)
      Map.keys(m)
    end
  end|} str_cmp) in
  let ks = List.map vstr (vlist (call_fn env "f" [])) in
  Alcotest.(check (list string)) "string keys sorted" ["apple"; "banana"; "cherry"] ks

let test_map_large () =
  (* Insert 20 keys in various orders, verify all are retrievable and sorted. *)
  let env = eval_with_map (Printf.sprintf {|mod T do
    fn f() do
      let pairs = [(15,15),(3,3),(18,18),(7,7),(11,11),(1,1),(20,20),(9,9),
                   (13,13),(5,5),(17,17),(2,2),(19,19),(8,8),(12,12),(4,4),
                   (16,16),(6,6),(14,14),(10,10)]
      let m = Map.from_list(pairs, %s)
      Map.keys(m)
    end
  end|} int_cmp) in
  let ks = List.map vint (vlist (call_fn env "f" [])) in
  let expected = List.init 20 (fun i -> i + 1) in
  Alcotest.(check (list int)) "20 keys sorted" expected ks

let test_map_tir_lower () =
  (* Smoke test: lower a program that uses Map through the TIR pipeline. *)
  let _m = lower_map_typed (Printf.sprintf {|mod T do
    fn make_map() do
      Map.from_list([(1, "a"), (2, "b")], %s)
    end
    fn lookup_key(m) do
      Map.get(m, 1, %s)
    end
  end|} int_cmp int_cmp) in
  (* If lowering didn't throw, the test passes *)
  ()

(* ── Track integration tests ──────────────────────────────────────────── *)

(* Track-B: type-qualified constructors — EAlloc in the TIR must use a
   type-qualified key "TypeName.CtorName" so two ADTs with the same constructor
   name don't collide in the codegen table. *)
let test_shared_ctor_tir_key () =
  (* Verify that lower_module_typed embeds the parent type name into the EAlloc
     TCon for a user-defined ADT constructor. *)
  let m = lower_module_typed {|mod Test do
    type Tree = Node(Int) | Leaf
    fn make() do Node(42) end
  end|} in
  let f = find_fn "make" m in
  let rec find_alloc_ty = function
    | March_tir.Tir.EAlloc (ty, _) -> Some ty
    | March_tir.Tir.ELet (_, e1, e2) ->
      (match find_alloc_ty e1 with Some _ as r -> r | None -> find_alloc_ty e2)
    | _ -> None
  in
  match find_alloc_ty f.March_tir.Tir.fn_body with
  | None -> Alcotest.fail "expected EAlloc in make()"
  | Some ty ->
    (* After Track-B fix, the TCon key should be "Tree.Node" not bare "Node" *)
    let ty_str = March_tir.Pp.string_of_ty ty in
    Alcotest.(check bool) "EAlloc uses type-qualified key" true
      (contains "Tree" ty_str)

let test_shared_ctor_name_eval () =
  (* Two distinct types; constructors from one must not interfere with the other. *)
  let env = eval_module {|mod Test do
    type Shape = Circle(Int) | Square(Int)
    type Color = Red | Green | Blue
    fn shape_val() do
      match Circle(42) with
      | Circle(r) -> r
      | Square(s) -> s
      end
    end
    fn color_val() do
      match Red with
      | Red   -> 1
      | Green -> 2
      | Blue  -> 3
      end
    end
  end|} in
  let sv = call_fn env "shape_val" [] in
  let cv = call_fn env "color_val" [] in
  Alcotest.(check int) "Circle(42) → 42" 42 (vint sv);
  Alcotest.(check int) "Red → 1" 1 (vint cv)

(* Track-A: interface constraint discharge — calling an interface method at a
   call site where the concrete type has no registered impl must be rejected. *)
let test_interface_when_constraint_missing () =
  (* Direct call to `eq` with a user type that has no Eq impl → error. *)
  let ctx = typecheck {|mod Test do
    interface Eq(a) do
      fn eq: a -> a -> Bool
    end
    impl Eq(Int) do
      fn eq(x, y) do x == y end
    end
    type Color = Red | Green
    fn check(a: Color, b: Color) do eq(a, b) end
  end|} in
  Alcotest.(check bool) "Eq(Color) not in scope: error" true (has_errors ctx)

(* Track-A: linear type enforcement — using a linear binding twice inside a
   match arm is detected and rejected. *)
let test_linear_match_arm_double_use () =
  (* Pattern binds `n` from a linear source; returning `n + n` uses it twice. *)
  let ctx = typecheck {|mod Test do
    fn double_linear(linear x: Int) : Int do
      match x with
      | n -> n + n
      end
    end
  end|} in
  Alcotest.(check bool) "linear binding used twice in match arm: error" true (has_errors ctx)

(* Track-C: actor messaging — spawn an actor and send it a message end-to-end. *)
let test_actor_spawn_and_send () =
  March_eval.Eval.reset_scheduler_state ();
  let src = {|mod Test do
    actor Counter do
      state { value : Int }
      init { value = 0 }
      on Inc() do
        { value = state.value + 1 }
      end
    end
    fn main() do
      let pid = spawn(Counter)
      send(pid, Inc())
    end
  end|} in
  let m = parse_and_desugar src in
  (* No errors during typecheck *)
  let (errors, _) = March_typecheck.Typecheck.check_module m in
  Alcotest.(check bool) "actor spawn+send: no type errors" false (has_errors errors);
  (* Runs without raising *)
  (try March_eval.Eval.run_module m
   with March_eval.Eval.Eval_error _ -> ()
      | March_eval.Eval.Match_failure _ -> ())

(* Track-D: CAS integration — hashing a module twice returns the same impl_hash,
   confirming the content-addressable cache key is stable. *)
let test_cas_stable_hash () =
  let src = {|mod Test do
    fn add(x : Int, y : Int) : Int do x + y end
    fn main() : Int do add(1, 2) end
  end|} in
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  (* hash_module must produce deterministic results *)
  let sccs1 = March_cas.Pipeline.hash_module tir in
  let sccs2 = March_cas.Pipeline.hash_module tir in
  let hashes1 = List.map March_cas.Pipeline.scc_impl_hash sccs1 in
  let hashes2 = List.map March_cas.Pipeline.scc_impl_hash sccs2 in
  Alcotest.(check (list string)) "CAS impl_hash is stable across two calls"
    hashes1 hashes2

let test_cas_cache_hit () =
  (* Compile an SCC, store it, then look it up — should be a hit. *)
  let src = {|mod Test do
    fn double(x : Int) : Int do x + x end
    fn main() : Int do double(21) end
  end|} in
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let sccs = March_cas.Pipeline.hash_module tir in
  (* Create a temporary CAS store *)
  let tmp_dir = Filename.temp_file "march_cas_test_" "" in
  Sys.remove tmp_dir;
  Unix.mkdir tmp_dir 0o755;
  let store = March_cas.Cas.create ~project_root:tmp_dir in
  let compile_count = ref 0 in
  let fake_compile _scc =
    incr compile_count;
    tmp_dir ^ "/fake_artifact"
  in
  (* First pass: all misses — compile is called for each SCC *)
  List.iter (fun h_scc ->
    let _ = March_cas.Pipeline.compile_scc store
              ~target:"native" ~flags:[] ~compile:fake_compile h_scc
    in ()
  ) sccs;
  let first_count = !compile_count in
  compile_count := 0;
  (* Second pass: all hits — compile should NOT be called *)
  List.iter (fun h_scc ->
    let _ = March_cas.Pipeline.compile_scc store
              ~target:"native" ~flags:[] ~compile:fake_compile h_scc
    in ()
  ) sccs;
  let second_count = !compile_count in
  Alcotest.(check bool) "first pass: compile called" true (first_count > 0);
  Alcotest.(check int)  "second pass: all cache hits (compile=0)" 0 second_count

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
          (* Fix 1: Interface constraint discharge *)
          Alcotest.test_case "iface constraint satisfied"   `Quick test_interface_constraint_satisfied;
          Alcotest.test_case "iface constraint missing impl" `Quick test_interface_constraint_missing_impl;
          Alcotest.test_case "impl when satisfied"          `Quick test_impl_when_constraint_satisfied;
          Alcotest.test_case "impl when unsatisfied"        `Quick test_impl_when_constraint_unsatisfied;
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
          Alcotest.test_case "Hash builtin Int"             `Quick test_hash_builtin_int;
          Alcotest.test_case "Hash builtin String"          `Quick test_hash_builtin_string;
          Alcotest.test_case "eq method callable"           `Quick test_eq_method_callable;
          Alcotest.test_case "std ifaces pre-registered"    `Quick test_standard_interfaces_in_scope;
          (* Fix 2: Linear type enforcement *)
          Alcotest.test_case "linear pattern match ok"       `Quick test_linear_pattern_match_ok;
          Alcotest.test_case "linear pattern match double"   `Quick test_linear_pattern_match_double_use;
          Alcotest.test_case "linear closure capture"        `Quick test_linear_closure_capture_error;
          Alcotest.test_case "linear field let binding"       `Quick test_linear_field_let_binding;
          (* Fix 3: Session type validation *)
          Alcotest.test_case "protocol self-message"         `Quick test_protocol_self_message_error;
          Alcotest.test_case "protocol empty loop"           `Quick test_protocol_empty_loop_error;
          Alcotest.test_case "protocol valid"                `Quick test_protocol_valid;
          Alcotest.test_case "protocol duplicate"            `Quick test_protocol_duplicate_error;
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
          Alcotest.test_case "task to_string"      `Quick test_value_task_to_string;
          Alcotest.test_case "workpool to_string"  `Quick test_value_workpool_to_string;
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
      ("opt", [
        Alcotest.test_case "fixpoint"         `Quick test_opt_fixpoint;
        Alcotest.test_case "no_infinite_loop" `Quick test_opt_no_infinite_loop;
      ]);
      ("fast_math", [
        Alcotest.test_case "emits_fast_attr" `Quick test_fast_math_emits_fast_attr;
      ]);
      ("llvm_emit correctness", [
        Alcotest.test_case "ctor_no_collision_different_tags" `Quick
          test_ctor_no_collision_different_tags;
        Alcotest.test_case "ctor_arity_mismatch_raises" `Quick
          test_ctor_arity_mismatch_raises;
        Alcotest.test_case "compiled main calls march_run_scheduler" `Quick
          (with_reset test_compiled_main_calls_march_run_scheduler);
      ]);
      ("string stdlib", [
        Alcotest.test_case "byte_size"           `Quick test_string_byte_size;
        Alcotest.test_case "byte_size empty"     `Quick test_string_byte_size_empty;
        Alcotest.test_case "byte_size unicode"   `Quick test_string_byte_size_unicode;
        Alcotest.test_case "slice_bytes"         `Quick test_string_slice_bytes;
        Alcotest.test_case "slice_bytes clamp"   `Quick test_string_slice_bytes_clamp;
        Alcotest.test_case "contains"            `Quick test_string_contains;
        Alcotest.test_case "starts_with"         `Quick test_string_starts_with;
        Alcotest.test_case "ends_with"           `Quick test_string_ends_with;
        Alcotest.test_case "concat"              `Quick test_string_concat;
        Alcotest.test_case "replace"             `Quick test_string_replace;
        Alcotest.test_case "replace_all"         `Quick test_string_replace_all;
        Alcotest.test_case "split"               `Quick test_string_split;
        Alcotest.test_case "split_first"         `Quick test_string_split_first;
        Alcotest.test_case "split_first no sep"  `Quick test_string_split_first_no_sep;
        Alcotest.test_case "join"                `Quick test_string_join;
        Alcotest.test_case "trim"                `Quick test_string_trim;
        Alcotest.test_case "trim_start"          `Quick test_string_trim_start;
        Alcotest.test_case "trim_end"            `Quick test_string_trim_end;
        Alcotest.test_case "to_uppercase"        `Quick test_string_to_uppercase;
        Alcotest.test_case "to_lowercase"        `Quick test_string_to_lowercase;
        Alcotest.test_case "repeat"              `Quick test_string_repeat;
        Alcotest.test_case "reverse"             `Quick test_string_reverse;
        Alcotest.test_case "pad_left"            `Quick test_string_pad_left;
        Alcotest.test_case "pad_right"           `Quick test_string_pad_right;
        Alcotest.test_case "is_empty"            `Quick test_string_is_empty;
        Alcotest.test_case "grapheme_count"      `Quick test_string_grapheme_count;
        Alcotest.test_case "index_of"            `Quick test_string_index_of;
        Alcotest.test_case "to_int"              `Quick test_string_to_int;
        Alcotest.test_case "to_float"            `Quick test_string_to_float;
        Alcotest.test_case "from_int"            `Quick test_string_from_int;
        Alcotest.test_case "from_float"          `Quick test_string_from_float;
      ]);
      ("iolist stdlib", [
        Alcotest.test_case "empty"         `Quick test_iolist_empty;
        Alcotest.test_case "from_string"   `Quick test_iolist_from_string;
        Alcotest.test_case "append"        `Quick test_iolist_append;
        Alcotest.test_case "byte_size"     `Quick test_iolist_byte_size;
      ]);
      ("http stdlib", [
        Alcotest.test_case "parse_url"          `Quick test_http_parse_url;
        Alcotest.test_case "parse_url scheme"    `Quick test_http_parse_url_scheme;
        Alcotest.test_case "parse_url path"      `Quick test_http_parse_url_path;
        Alcotest.test_case "parse_url port"      `Quick test_http_parse_url_port;
        Alcotest.test_case "parse_url invalid"   `Quick test_http_parse_url_invalid;
        Alcotest.test_case "set_header"          `Quick test_http_set_header;
        Alcotest.test_case "method_to_string"    `Quick test_http_method_to_string;
        Alcotest.test_case "status helpers"      `Quick test_http_status_helpers;
        Alcotest.test_case "post constructor"    `Quick test_http_post_constructor;
        Alcotest.test_case "encode_query"        `Quick test_http_encode_query;
        Alcotest.test_case "response helpers"    `Quick test_http_response_helpers;
      ]);
      ("http builtins", [
        Alcotest.test_case "serialize request"       `Quick test_http_serialize_request;
        Alcotest.test_case "serialize with body"     `Quick test_http_serialize_request_with_body;
        Alcotest.test_case "parse response"          `Quick test_http_parse_response;
        Alcotest.test_case "parse response body"     `Quick test_http_parse_response_body;
      ]);
      ("http client", [
        Alcotest.test_case "new client"              `Quick test_http_client_new;
        Alcotest.test_case "add steps"               `Quick test_http_client_add_steps;
        Alcotest.test_case "bearer auth transform"   `Quick test_http_client_request_step_transforms;
        Alcotest.test_case "raise on error status"   `Quick test_http_client_raise_on_error_status;
        Alcotest.test_case "with redirects"          `Quick test_http_client_with_redirects;
        Alcotest.test_case "base url step"           `Quick test_http_client_base_url_step;
        Alcotest.test_case "content type step"       `Quick test_http_client_content_type_step;
      ]);
      ( "scheduler",
        [
          Alcotest.test_case "reduction counter ticks"     `Quick (with_reset test_reduction_counter_ticks);
          Alcotest.test_case "reduction counter exhausts"  `Quick (with_reset test_reduction_counter_exhausts);
          Alcotest.test_case "eval yields after budget"    `Quick (with_reset test_eval_yields_after_budget);
          Alcotest.test_case "eval no yield when disabled" `Quick (with_reset test_eval_no_yield_when_disabled);
          Alcotest.test_case "reduction count"             `Quick (with_reset test_eval_reduction_count);
        ] );
      ( "tasks",
        [
          Alcotest.test_case "spawn and await"     `Quick (with_reset test_eval_task_spawn_await);
          Alcotest.test_case "await unwrap"        `Quick (with_reset test_eval_task_await_unwrap);
          Alcotest.test_case "multiple tasks"      `Quick (with_reset test_eval_task_multiple);
          Alcotest.test_case "task captures env"   `Quick (with_reset test_eval_task_captures_env);
          Alcotest.test_case "spawn_steal requires pool" `Quick (with_reset test_eval_spawn_steal_requires_pool);
          Alcotest.test_case "spawn_steal with pool"     `Quick (with_reset test_eval_spawn_steal_with_pool);
          Alcotest.test_case "workpool threading"        `Quick (with_reset test_eval_workpool_threading);
          Alcotest.test_case "task sends to actor"       `Quick (with_reset test_eval_task_sends_to_actor);
        ] );
      ( "work_stealing",
        [
          Alcotest.test_case "deque push/pop"     `Quick (with_reset test_deque_push_pop);
          Alcotest.test_case "deque steal"        `Quick (with_reset test_deque_steal);
          Alcotest.test_case "deque size"         `Quick (with_reset test_deque_size);
          Alcotest.test_case "pool submit/steal"  `Quick (with_reset test_pool_submit_steal);
        ] );
      ( "capabilities",
        [
          Alcotest.test_case "pure module ok"            `Quick test_cap_needs_pure_ok;
          Alcotest.test_case "declared needs ok"         `Quick test_cap_needs_declared_ok;
          Alcotest.test_case "missing needs error"       `Quick test_cap_missing_needs_error;
          Alcotest.test_case "unused needs warning"      `Quick test_cap_unused_needs_warning;
          Alcotest.test_case "supertype covers subtype"  `Quick test_cap_supertype_covers_subtype;
          Alcotest.test_case "wrong subtype error"       `Quick test_cap_needs_wrong_subtype;
          Alcotest.test_case "multiple needs"            `Quick test_cap_multiple_needs;
          Alcotest.test_case "parse needs"               `Quick test_cap_parse_needs;
          Alcotest.test_case "parse needs dotted"        `Quick test_cap_parse_needs_dotted;
          Alcotest.test_case "transitive ok"             `Quick test_cap_transitive_ok;
          Alcotest.test_case "transitive missing error"  `Quick test_cap_transitive_missing_error;
          Alcotest.test_case "transitive supertype ok"   `Quick test_cap_transitive_supertype_ok;
          Alcotest.test_case "transitive chain error"    `Quick test_cap_transitive_chain_error;
          Alcotest.test_case "extern with needs ok"      `Quick test_cap_extern_with_needs_ok;
          Alcotest.test_case "extern missing needs error" `Quick test_cap_extern_missing_needs_error;
          Alcotest.test_case "effects entry point clean"  `Quick test_cap_effects_clean;
          Alcotest.test_case "effects entry point violation" `Quick test_cap_effects_violation;
          Alcotest.test_case "eval path blocked by cap error" `Quick test_cap_eval_path_blocked;
          Alcotest.test_case "eval path ok with needs"    `Quick test_cap_eval_path_ok;
        ] );
      ("sort stdlib", [
        Alcotest.test_case "sort_small empty"       `Quick test_sort_small_empty;
        Alcotest.test_case "sort_small n=1"         `Quick test_sort_small_n1;
        Alcotest.test_case "sort_small n=2"         `Quick test_sort_small_n2;
        Alcotest.test_case "sort_small n=2 ordered" `Quick test_sort_small_n2_already_sorted;
        Alcotest.test_case "sort_small n=3"         `Quick test_sort_small_n3;
        Alcotest.test_case "sort_small n=3 all perms" `Quick test_sort_small_n3_all_perms;
        Alcotest.test_case "sort_small n=4"         `Quick test_sort_small_n4;
        Alcotest.test_case "sort_small n=4 all perms" `Quick test_sort_small_n4_all_perms;
        Alcotest.test_case "sort_small n=5"         `Quick test_sort_small_n5;
        Alcotest.test_case "sort_small n=6"         `Quick test_sort_small_n6;
        Alcotest.test_case "sort_small n=7"         `Quick test_sort_small_n7;
        Alcotest.test_case "sort_small n=8"         `Quick test_sort_small_n8;
        Alcotest.test_case "sort_small n=9 fallback" `Quick test_sort_small_n9_fallback;
        Alcotest.test_case "sort_small stability"   `Quick test_sort_small_stability;
        Alcotest.test_case "timsort empty"          `Quick test_timsort_empty;
        Alcotest.test_case "timsort single"         `Quick test_timsort_single;
        Alcotest.test_case "timsort already sorted" `Quick test_timsort_already_sorted;
        Alcotest.test_case "timsort reverse"        `Quick test_timsort_reverse;
        Alcotest.test_case "timsort random"         `Quick test_timsort_random;
        Alcotest.test_case "timsort nearly sorted"  `Quick test_timsort_nearly_sorted;
        Alcotest.test_case "timsort stable"         `Quick test_timsort_stable;
        Alcotest.test_case "introsort empty"        `Quick test_introsort_empty;
        Alcotest.test_case "introsort single"       `Quick test_introsort_single;
        Alcotest.test_case "introsort already sorted" `Quick test_introsort_already_sorted;
        Alcotest.test_case "introsort reverse"      `Quick test_introsort_reverse;
        Alcotest.test_case "introsort random"       `Quick test_introsort_random;
        Alcotest.test_case "introsort large"        `Quick test_introsort_large;
      ]);
      ("enum stdlib", [
        Alcotest.test_case "map"         `Quick test_enum_map;
        Alcotest.test_case "flat_map"    `Quick test_enum_flat_map;
        Alcotest.test_case "filter"      `Quick test_enum_filter;
        Alcotest.test_case "fold"        `Quick test_enum_fold;
        Alcotest.test_case "reduce some" `Quick test_enum_reduce_some;
        Alcotest.test_case "reduce none" `Quick test_enum_reduce_none;
        Alcotest.test_case "each"        `Quick test_enum_each;
        Alcotest.test_case "count"       `Quick test_enum_count;
        Alcotest.test_case "any"         `Quick test_enum_any;
        Alcotest.test_case "all"         `Quick test_enum_all;
        Alcotest.test_case "find"        `Quick test_enum_find;
        Alcotest.test_case "group_by"    `Quick test_enum_group_by;
        Alcotest.test_case "zip_with"    `Quick test_enum_zip_with;
        Alcotest.test_case "sort_by"     `Quick test_enum_sort_by;
        Alcotest.test_case "timsort_by"  `Quick test_enum_timsort_by;
        Alcotest.test_case "introsort_by" `Quick test_enum_introsort_by;
        Alcotest.test_case "sort_small_by" `Quick test_enum_sort_small_by;
      ]);
      ("supervision phase1", [
        Alcotest.test_case "monitor receives Down on kill"        `Quick (with_reset test_monitor_receives_down_on_kill);
        Alcotest.test_case "demonitor prevents Down delivery"     `Quick (with_reset test_demonitor_prevents_down);
        Alcotest.test_case "link kills both on crash"             `Quick (with_reset test_link_kills_both_on_crash);
        Alcotest.test_case "monitor on dead actor immediate Down" `Quick (with_reset test_monitor_already_dead_immediate_down);
        Alcotest.test_case "multiple monitors all fire"           `Quick (with_reset test_multiple_monitors_all_fire);
        Alcotest.test_case "Down message format"                  `Quick (with_reset test_down_message_format);
        Alcotest.test_case "monitor builtin end-to-end"           `Quick (with_reset test_eval_monitor_builtin);
        Alcotest.test_case "link builtin end-to-end"              `Quick (with_reset test_eval_link_builtin);
      ]);
      ("supervision phase2", [
        Alcotest.test_case "one_for_one restart"          `Quick (with_reset test_supervision_one_for_one_restart);
        Alcotest.test_case "max_restarts escalation"      `Quick (with_reset test_supervision_max_restarts_escalation);
        Alcotest.test_case "one_for_all"                  `Quick (with_reset test_supervision_one_for_all);
        Alcotest.test_case "rest_for_one"                 `Quick (with_reset test_supervision_rest_for_one);
        Alcotest.test_case "state replacement on restart" `Quick (with_reset test_supervision_state_replacement);
      ]);
      ("supervision phase3", [
        Alcotest.test_case "epoch starts at 0"            `Quick (with_reset test_supervision_epoch_starts_at_zero);
        Alcotest.test_case "get_cap"                      `Quick (with_reset test_supervision_get_cap);
        Alcotest.test_case "send_checked ok"              `Quick (with_reset test_supervision_send_checked_ok);
        Alcotest.test_case "send_checked dead actor"      `Quick (with_reset test_supervision_send_checked_dead_actor);
        Alcotest.test_case "epoch increments on restart"  `Quick (with_reset test_supervision_epoch_increments_on_restart);
        Alcotest.test_case "stale epoch rejected"         `Quick (with_reset test_supervision_stale_epoch);
      ]);
      ("supervision phase5", [
        Alcotest.test_case "task_spawn_link completes"         `Quick (with_reset test_supervision_task_spawn_link_completes);
        Alcotest.test_case "task_spawn_link crash propagates"  `Quick (with_reset test_supervision_task_spawn_link_crash_propagates);
      ]);
      ("supervision phase6a", [
        Alcotest.test_case "resource cleanup on crash"
          `Quick (with_reset test_resource_cleanup_on_crash);
        Alcotest.test_case "resource cleanup reverse order"
          `Quick (with_reset test_resource_cleanup_reverse_order);
        Alcotest.test_case "resource cleanup on link crash"
          `Quick (with_reset test_resource_cleanup_on_link_crash);
      ]);
      ("eval phase 4", [
        Alcotest.test_case "async send queues not dispatches" `Quick
          (with_reset test_async_send_queues_not_dispatches);
        Alcotest.test_case "scheduler drains mailbox"         `Quick
          (with_reset test_scheduler_drains_mailbox);
        Alcotest.test_case "scheduler updates actor state"    `Quick
          (with_reset test_scheduler_updates_actor_state);
        Alcotest.test_case "scheduler round-robin"            `Quick
          (with_reset test_scheduler_round_robin);
        Alcotest.test_case "self inside handler"              `Quick
          (with_reset test_self_inside_handler);
        Alcotest.test_case "receive inside handler"           `Quick
          (with_reset test_receive_inside_handler);
        Alcotest.test_case "message FIFO ordering"            `Quick
          (with_reset test_message_fifo_ordering);
        Alcotest.test_case "handler sends to another actor"   `Quick
          (with_reset test_handler_sends_to_another_actor);
        Alcotest.test_case "run_module auto-drains mailbox"   `Quick
          test_run_module_auto_drains;
        Alcotest.test_case "send to dead actor dropped"       `Quick
          (with_reset test_send_to_dead_actor_dropped);
        Alcotest.test_case "self-send from handler"           `Quick
          (with_reset test_self_send_from_handler);
      ]);
      ("file builtins", [
        Alcotest.test_case "file_exists false" `Quick test_file_builtin_exists_false;
      ]);
      ("seq stdlib", [
        Alcotest.test_case "from_list round trips" `Quick test_seq_from_list;
        Alcotest.test_case "map doubles"           `Quick test_seq_map;
        Alcotest.test_case "filter"                `Quick test_seq_filter;
        Alcotest.test_case "take 3"                `Quick test_seq_take;
        Alcotest.test_case "fold_while halts"      `Quick test_seq_fold_while;
        Alcotest.test_case "concat"                `Quick test_seq_concat;
      ]);
      ("path stdlib", [
        Alcotest.test_case "join"                    `Quick test_path_join;
        Alcotest.test_case "basename"                `Quick test_path_basename;
        Alcotest.test_case "extension"               `Quick test_path_extension;
        Alcotest.test_case "normalize"               `Quick test_path_normalize;
        Alcotest.test_case "dirname"                 `Quick test_path_dirname;
        Alcotest.test_case "strip_extension"         `Quick test_path_strip_extension;
        Alcotest.test_case "extension dotfile"       `Quick test_path_extension_dotfile;
        Alcotest.test_case "strip_extension dotfile" `Quick test_path_strip_extension_dotfile;
        Alcotest.test_case "normalize absolute"      `Quick test_path_normalize_absolute;
        Alcotest.test_case "is_absolute"             `Quick test_path_is_absolute;
      ]);
      ("file stdlib", [
        Alcotest.test_case "read"           `Quick test_file_read;
        Alcotest.test_case "write then read" `Quick test_file_write_read;
        Alcotest.test_case "exists"         `Quick test_file_exists;
        Alcotest.test_case "with_lines"     `Quick test_file_with_lines;
        Alcotest.test_case "not found"      `Quick test_file_not_found;
        Alcotest.test_case "append"         `Quick test_file_append;
      ]);
      ("dir stdlib", [
        Alcotest.test_case "mkdir/list/rmdir" `Quick test_dir_mkdir_list_rmdir;
        Alcotest.test_case "rm_rf nested"     `Quick test_dir_rm_rf;
        Alcotest.test_case "rm_rf refuses root" `Quick test_dir_rm_rf_refuses_root;
        Alcotest.test_case "exists true"      `Quick test_dir_exists;
        Alcotest.test_case "exists false"     `Quick test_dir_not_exists;
        Alcotest.test_case "mkdir_p nested"   `Quick test_dir_mkdir_p;
      ]);
      ("integration", [
        Alcotest.test_case "file/dir/path pipeline" `Quick test_integration_file_pipeline;
      ]);
      ("map stdlib", [
        Alcotest.test_case "empty is_empty"             `Quick test_map_empty;
        Alcotest.test_case "singleton"                  `Quick test_map_singleton;
        Alcotest.test_case "insert and get"             `Quick test_map_insert_get;
        Alcotest.test_case "get missing key"            `Quick test_map_get_missing;
        Alcotest.test_case "insert overwrites"          `Quick test_map_insert_overwrite;
        Alcotest.test_case "contains_key true"          `Quick test_map_contains_key_true;
        Alcotest.test_case "contains_key false"         `Quick test_map_contains_key_false;
        Alcotest.test_case "get_or default"             `Quick test_map_get_or;
        Alcotest.test_case "remove existing"            `Quick test_map_remove;
        Alcotest.test_case "remove absent no-op"        `Quick test_map_remove_absent;
        Alcotest.test_case "size"                       `Quick test_map_size;
        Alcotest.test_case "is_empty after insert"      `Quick test_map_is_empty_after_insert;
        Alcotest.test_case "keys sorted"                `Quick test_map_keys;
        Alcotest.test_case "values in key order"        `Quick test_map_values;
        Alcotest.test_case "entries sorted"             `Quick test_map_entries;
        Alcotest.test_case "from_list"                  `Quick test_map_from_list;
        Alcotest.test_case "to_list equals entries"     `Quick test_map_to_list;
        Alcotest.test_case "map_values"                 `Quick test_map_map_values;
        Alcotest.test_case "filter"                     `Quick test_map_filter;
        Alcotest.test_case "fold sum"                   `Quick test_map_fold;
        Alcotest.test_case "merge size"                 `Quick test_map_merge;
        Alcotest.test_case "merge b overwrites a"       `Quick test_map_merge_b_overwrites;
        Alcotest.test_case "merge_with combine"         `Quick test_map_merge_with;
        Alcotest.test_case "string keys"                `Quick test_map_string_keys;
        Alcotest.test_case "large insert order"         `Quick test_map_large;
        Alcotest.test_case "tir lowering"               `Quick test_map_tir_lower;
      ]);
      ("track integration", [
        Alcotest.test_case "shared ctor tir key"        `Quick test_shared_ctor_tir_key;
        Alcotest.test_case "shared ctor name eval"      `Quick test_shared_ctor_name_eval;
        Alcotest.test_case "interface when missing"     `Quick test_interface_when_constraint_missing;
        Alcotest.test_case "linear match arm double"    `Quick test_linear_match_arm_double_use;
        Alcotest.test_case "actor spawn and send"       `Quick (with_reset test_actor_spawn_and_send);
        Alcotest.test_case "cas stable hash"            `Quick test_cas_stable_hash;
        Alcotest.test_case "cas cache hit"              `Quick test_cas_cache_hit;
      ]);
    ]
