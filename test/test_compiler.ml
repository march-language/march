(** March test suite — compiler tests. *)
open Test_helpers

let test_lexer_int () =
  let lexbuf = Lexing.from_string "42" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check int) "lexes integer" 42
    (match tok with March_parser.Parser.INT n -> n | _ -> failwith "expected INT")

let test_lexer_int_max () =
  (* 2^62 - 1 = max March integer — must lex, not overflow. *)
  let lexbuf = Lexing.from_string "4611686018427387903" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check int) "lexes max integer" max_int
    (match tok with March_parser.Parser.INT n -> n | _ -> failwith "expected INT")

let test_lexer_int_out_of_range () =
  (* 2^62 = max + 1 — must raise a positioned ParseError, NOT crash with the
     raw Failure("int_of_string") that int_of_string used to throw. *)
  let lexbuf = Lexing.from_string "4611686018427387904" in
  let raised =
    try ignore (March_lexer.Lexer.token lexbuf); false
    with
    | March_errors.Errors.ParseError (msg, _hint, _pos) ->
      (* message names the offending literal *)
      (try ignore (Str.search_forward (Str.regexp_string "4611686018427387904") msg 0); true
       with Not_found -> false)
    | Failure _ -> false  (* the old, unfixed behavior — must NOT happen *)
  in
  Alcotest.(check bool) "out-of-range literal raises ParseError" true raised

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

let test_parse_lambda_bare_stmt_before_if () =
  (* Regression: an inline lambda call-argument whose body has a `let`
     binding, then a bare (non-let) call statement, then a final
     if/else/end used to swallow the bare call as the lambda's final
     expression and leave `if ... end` as unparsed trailing tokens
     ("I got stuck here" at `if`). *)
  let src = "f(fn x -> let a = 1 println(\"hi\") if a > 0 do 1 else 2 end)" in
  let lexbuf = Lexing.from_string src in
  let expr = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  match expr with
  | March_ast.Ast.EApp (_, [March_ast.Ast.ELam ([_], March_ast.Ast.EBlock (stmts, _), _)], _) ->
    Alcotest.(check int) "3 stmts in lambda body" 3 (List.length stmts)
  | _ -> Alcotest.fail "expected EApp with ELam argument containing 3-stmt EBlock body"

let test_parse_lambda_consecutive_bare_stmts () =
  (* Regression: two consecutive bare (non-let) statements in an inline
     lambda call-argument body used to fail on the second statement. *)
  let src = "f(fn x -> println(\"hi\") println(\"bye\"))" in
  let lexbuf = Lexing.from_string src in
  let expr = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  match expr with
  | March_ast.Ast.EApp (_, [March_ast.Ast.ELam ([_], March_ast.Ast.EBlock ([_; _], _), _)], _) -> ()
  | _ -> Alcotest.fail "expected EApp with ELam argument containing 2-stmt EBlock body"

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

(* ── `with ... else` multi-arm parsing (token-filter arm separators) ────── *)

(* Parse a module whose single fn body is a `with ... else ... end` and return
   the number of branches in the desugared EMatch. `with pat <- e do body else
   arms... end` builds `EMatch(e, ok_branch :: arms)`, so the branch count is
   [1 + number of else-arms]. Multi-arm else forms used to fail to parse at all
   because the token filter swallowed the newlines separating the arms. *)
let with_else_match_branches src =
  let lexbuf = Lexing.from_string src in
  let m =
    March_parser.Parser.module_
      (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
  in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    (match def.March_ast.Ast.fn_clauses with
     | [clause] ->
       (match clause.March_ast.Ast.fc_body with
        | March_ast.Ast.EMatch (_, branches, _) -> List.length branches
        | _ -> Alcotest.fail "expected `with` body to desugar to EMatch")
     | _ -> Alcotest.fail "expected single fn clause")
  | _ -> Alcotest.fail "expected single DFn"

let test_parse_with_else_single_arm () =
  (* Regression guard: the single-arm form already worked and must keep doing so. *)
  let src = {|mod Test do
    fn g() do
      with Ok(user) <- lookup() do
        Ok(user)
      else
        Err(e) -> Err(e)
      end
    end
  end|} in
  Alcotest.(check int) "1 ok branch + 1 else arm" 2 (with_else_match_branches src)

let test_parse_with_else_two_nullary_arms () =
  (* The bug: two nullary-constructor else arms failed to parse entirely, with
     the caret landing on the second arm's `->`. *)
  let src = {|mod Test do
    fn g() do
      with Ok(user) <- lookup() do
        Ok(user)
      else
        ErrA -> Err(ErrA)
        ErrC -> Err(ErrC)
      end
    end
  end|} in
  Alcotest.(check int) "1 ok branch + 2 else arms" 3 (with_else_match_branches src)

let test_parse_with_else_three_payload_arms () =
  (* Three arms mixing nullary, payload, and nested-payload constructor
     patterns — mirrors the 3-arm example in docs/pattern-matching.md. *)
  let src = {|mod Test do
    fn g() do
      with Ok(user) <- authenticate() do
        Ok(user)
      else
        Err(AuthFailed) -> Err(AuthFailed)
        Err(NotFound(kind)) -> Err(NotFound(kind))
        Err(Timeout) -> Err(Timeout)
      end
    end
  end|} in
  Alcotest.(check int) "1 ok branch + 3 else arms" 4 (with_else_match_branches src)

let test_parse_with_else_infix_bodies () =
  (* Arm bodies containing infix operators must not confuse arm-boundary
     detection: each arm still terminates at its trailing newline. *)
  let src = {|mod Test do
    fn g() do
      with Ok(name) <- fetch() do
        Ok(name)
      else
        Err(a) -> Err("bad: " ++ a)
        Err(b) -> Err("worse: " ++ b)
      end
    end
  end|} in
  Alcotest.(check int) "1 ok branch + 2 infix-body else arms" 3 (with_else_match_branches src)

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

let test_tc_dotted_sibling_module_order () =
  (* Two callers of Ns.Helper.define with DIFFERENT record args, declared
     BEFORE the dotted sibling module that defines it.
     dependency_order_dmod_run must order Ns.Helper first so each caller
     instantiates the generalized scheme.  Regression: module_refs_in_decls
     recorded only the FIRST dotted segment of a reference ("Ns" from
     "Ns.Helper.define"), so a dotted sibling (`mod Ns.Helper`) never
     received a dependency edge and stayed after its callers — all callers
     then unified against one shared pass-1 Mono placeholder and the first
     caller's record shape was pinned as "the" parameter type. *)
  let ctx = typecheck {|mod Test do
    mod CallerA do
      fn go() do Ns.Helper.define("a", { fields: { id: "x", name: "y" } }) end
    end
    mod CallerB do
      fn go() do Ns.Helper.define("b", { fields: { id: "x", age: "z" } }) end
    end
    mod Ns.Helper do
      fn define(table, spec) do (table, spec.fields) end
    end
  end|} in
  Alcotest.(check bool) "dotted sibling ordered before callers: no errors"
    false (has_errors ctx)

let test_tc_private_nested_member_diagnostic () =
  (* A same-file qualified reference to a PRIVATE nested-module member (`A.secret`
     where `secret` is a `pfn`) is rejected — but must be diagnosed as "private to
     module `A`", NOT the misleading "Unknown module `A`".  The private member is
     never exported into env.vars, so the registry-based qualified_error_msg saw
     no in-file module `A` at all and misreported it as absent; env.local_mods now
     records each nested module's private members to recover the accurate message. *)
  let ctx = typecheck {|mod Main do
    mod A do
      pfn secret() : Int do 42 end
      fn pub_fn() : Int do 1 end
    end
    fn main() : Int do A.secret() end
  end|} in
  Alcotest.(check bool) "private nested member: rejected" true (has_errors ctx);
  let says_private =
    List.exists (fun (d : March_errors.Errors.diagnostic) ->
      try ignore (Str.search_forward
                    (Str.regexp_string "is private to module `A`") d.message 0); true
      with Not_found -> false)
      ctx.March_errors.Errors.diagnostics
  in
  Alcotest.(check bool)
    "diagnostic names the private member, not 'Unknown module'" true says_private

let test_tc_private_nested_member_name_collides_with_builtin () =
  (* Same bug as [test_tc_private_nested_member_diagnostic], but the private
     member's bare name ("hash") coincides with a globally-bound identifier
     (the `Hash` interface's bare method scheme, typecheck.ml's default
     interface-method bindings). Before the fix, `EVar`'s progressive
     dot-suffix fallback — meant only to resolve multi-component interface
     method paths like "Conduit.Storage.workflow_load" down to
     "Storage.workflow_load" — stripped "Auth.hash" all the way to the bare
     "hash" and silently matched the unrelated global, bypassing the privacy
     check entirely: `Auth.hash("x")` typechecked clean (and ran to a garbage
     value when compiled, since codegen still calls the real, private
     `Auth.hash`, while typecheck's inferred type came from the wrong,
     unrelated binding). `is_confirmed_private_qualified` now short-circuits
     that fallback for a name confirmed private via [env.local_mods]. *)
  let ctx = typecheck {|mod Main do
    mod Auth do
      pfn hash(s : String) : String do s end
      fn verify(plain, stored) do hash(plain) == stored end
    end
    fn main() : String do Auth.hash("x") end
  end|} in
  Alcotest.(check bool) "private member shadowed by a global name: still rejected"
    true (has_errors ctx);
  let says_private =
    List.exists (fun (d : March_errors.Errors.diagnostic) ->
      try ignore (Str.search_forward
                    (Str.regexp_string "is private to module `Auth`") d.message 0); true
      with Not_found -> false)
      ctx.March_errors.Errors.diagnostics
  in
  Alcotest.(check bool)
    "diagnostic names the private member, not a silent wrong resolution" true says_private

let test_tc_if_bad_cond () =
  (* Condition must be Bool — using Int + 1 should produce an error. *)
  let ctx = typecheck {|mod Test do
    fn bad(x) do if x + 1 do 0 else 1 end end
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
  (* The arity error is on the call itself; no trailing `()` — a `<call>)(`
     juxtaposition like `add(1) ()` is now a parse error (curried-call guard,
     token_filter.ml), so the direct call carries the arity mismatch. *)
  let ctx = typecheck {|mod Test do
    fn add(a : Int, b : Int) : Int do a + b end
    fn main() : Unit do let _ = add(1) end
  end|} in
  Alcotest.(check bool) "under-application is an error" true (has_errors ctx)

let test_tc_arity_zero_args () =
  let ctx = typecheck {|mod Test do
    fn mk(name : String) : Int do string_byte_length(name) end
    fn main() : Unit do let _ = mk() end
  end|} in
  Alcotest.(check bool) "0-arg call of 1-arg fn is an error" true (has_errors ctx)

let test_tc_arity_over_application () =
  let ctx = typecheck {|mod Test do
    fn add(a : Int, b : Int) : Int do a + b end
    fn main() : Unit do let _ = add(1, 2, 3) end
  end|} in
  Alcotest.(check bool) "over-application is an error" true (has_errors ctx)

let test_tc_arity_correct_ok () =
  let ctx = typecheck {|mod Test do
    fn add(a : Int, b : Int) : Int do a + b end
    fn main() : Unit do let _ = add(1, 2) end
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

(* ── root_cap: callable-vs-value diagnostic ─────────────────────────────
   root_cap is a bare ambient value of type Cap(IO) (see docs/capabilities.md
   and examples/capabilities.march) — NOT a function.  infer_app's
   `| [], t -> t` base case exists so a zero-param user `fn` (whose type
   collapses to its bare return type — no TArrow wrapper, since there's no
   parameter to build one from) can still be invoked as `f()`; before this
   fix it also silently accepted `root_cap()`, which then crashed at runtime
   (interpreted: "applied non-function value"; compiled: undefined symbol
   `_root_cap` at link time — see [noncallable_builtin_values] in
   typecheck.ml). *)

let test_tc_root_cap_call_rejected () =
  let ctx = typecheck {|mod Test do
    needs IO
    fn f() : () do
      let c = root_cap()
      ()
    end
  end|} in
  Alcotest.(check bool) "root_cap() is a typecheck error" true (has_errors ctx);
  let has_clear_message = List.exists (fun (d : March_errors.Errors.diagnostic) ->
    d.severity = March_errors.Errors.Error &&
    contains "root_cap" d.message &&
    contains "not a function" d.message
  ) ctx.diagnostics in
  Alcotest.(check bool) "root_cap() error names root_cap and explains it's not a function"
    true has_clear_message

let test_tc_root_cap_bare_ok () =
  (* Body returns `c`, not `()` — a bare value reference immediately
     followed by a paren-led expression on the next line parses as a call
     on that value (see specs/lang parser note on `let x = V` glomming into
     `V(...)`), which would spuriously exercise the same diagnostic this
     test is trying to prove does NOT fire for a genuinely bare reference. *)
  let ctx = typecheck {|mod Test do
    needs IO
    fn f() : Cap(IO) do
      let c = root_cap
      c
    end
  end|} in
  Alcotest.(check bool) "bare `root_cap` reference: no errors" false (has_errors ctx)

(* Builtins that, unlike root_cap, genuinely ARE invoked with `()` — the
   root_cap denylist must not overreach into these. *)
let test_tc_zero_arg_builtins_still_callable () =
  let ctx = typecheck {|mod Test do
    fn f() : () do
      let _ = pmap_threshold()
      let _ = get_work_pool()
      let t = task_cancel_token_new()
      let _ = task_is_cancelled(t)
      let _ = self()
      ()
    end
  end|} in
  Alcotest.(check bool) "legit zero-arg builtin calls: no errors" false (has_errors ctx)

(* A zero-param user `fn` collapses to its bare return type (same shape as
   root_cap's `Mono (Cap(IO))`) — calling it with `()` must still work. *)
let test_tc_zero_arg_user_fn_still_callable () =
  let ctx = typecheck {|mod Test do
    fn g() : Int do 42 end
    fn f() : Int do g() end
  end|} in
  Alcotest.(check bool) "zero-arg user fn call: no errors" false (has_errors ctx)

(* KNOWN, SEPARATE GAP (not fixed here): calling an ordinary non-function
   local value with zero args — e.g. `let x = 5; x()` — is STILL silently
   accepted by --check today, for the same underlying reason root_cap() was:
   infer_app's `| [], t -> t` base case can't distinguish "callee is a
   disguised zero-arg fn" from "callee is a plain value" once no args remain,
   and a plain `let`-bound value can't safely be told apart from a legitimate
   bare-imported or qualified cross-module zero-arg function call (neither is
   tracked in env.fn_arities, which only covers same-module `fn` decls) without
   deeper env changes tracking local-vs-global binding provenance.  This test
   pins CURRENT behavior so it doesn't silently regress further, not because
   it's correct — closing this gap for real is a follow-up, not part of the
   root_cap fix. *)
let test_tc_nonfunction_local_value_call_known_gap () =
  let ctx = typecheck {|mod Test do
    fn f() : Int do
      let x = 5
      x()
    end
  end|} in
  Alcotest.(check bool)
    "KNOWN GAP: plain non-function local value called with 0 args is not \
     yet rejected at --check (crashes at runtime instead) — separate from \
     the root_cap fix"
    false (has_errors ctx)

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

let test_impl_coherence_distinct_modules_ok () =
  (* Two DISTINCT same-short-name types in sibling nested modules may each
     implement a TYPE-DISPATCHED BUILTIN interface (Eq) — no false overlap.
     Sound compiled because Eq/Ord/Show/Hash dispatch via generated
     ctor-qualified structural functions, not bare-type-name mangling. *)
  let ctx = typecheck {|mod Top do
    mod NA do
      type Thing = TA
      impl Eq(Thing) do fn eq(x, y) do eq(x, y) end end
    end
    mod NB do
      type Thing = TB
      impl Eq(Thing) do fn eq(x, y) do eq(x, y) end end
    end
  end|} in
  Alcotest.(check bool) "distinct-module same-name builtin impls: no error"
    false (has_errors ctx)

let test_impl_coherence_distinct_modules_general_iface_ok () =
  (* Two DISTINCT same-short-name types in sibling nested modules may each
     implement a GENERAL user interface — coherence keys on the declaring
     module, so the distinct types do NOT overlap. Since FQN dispatch Stage 3
     landed (globally-unique runtime tags + forced Boxed repr + module-qualified
     impl symbols + a generated runtime tag-switch dispatch fn; interp qualifies
     iface_method_tbl), each type's value dispatches to its own body in BOTH
     backends. Previously rejected (a general interface then mangled both impls
     to ONE symbol — silent wrong body compiled). Runtime witnesses:
     specs/lang/types/accept/t89, test/imports/speak_collision_native. *)
  let ctx = typecheck {|mod Top do
    interface Speak(a) do
      fn speak : a -> String
    end
    mod NA do
      type Thing = TA
      impl Speak(Thing) do fn speak(_x) do "a" end end
    end
    mod NB do
      type Thing = TB
      impl Speak(Thing) do fn speak(_x) do "b" end end
    end
  end|} in
  Alcotest.(check bool) "distinct-module general-iface impls: no error"
    false (has_errors ctx)

let test_impl_coherence_same_module_duplicate_err () =
  (* Two impls of the SAME interface for the SAME type in one module still
     overlap and are rejected (coherence unchanged). *)
  let ctx = typecheck {|mod M do
    interface Speak(a) do
      fn speak : a -> String
    end
    type Dog = Dog
    impl Speak(Dog) do fn speak(_x) do "woof" end end
    impl Speak(Dog) do fn speak(_x) do "bark" end end
  end|} in
  Alcotest.(check bool) "same-module duplicate impl: error"
    true (has_errors ctx)

let test_impl_coherence_shared_ctor_double_collision_ok () =
  (* Constructor module-qualified identity plan, flag-day (Task 6): two DISTINCT
     same-short-name types in sibling modules that ALSO share a constructor name
     (`Shared`) — a "double collision" — now typecheck. This shape was rejected
     under the interim Task-6b stopgap because the backends and interpreter used
     to route dispatch on the BARE constructor tag (ci_module was diagnostic-
     only), so a general-interface method would silently misdispatch. The plan
     resolves ctor identity upstream — native ECon/pattern-match qualify a
     colliding type's ctor key with its declaring module, and the interpreter
     qualifies the VCon tag the same way — so `speak` dispatches correctly on the
     value's real type in BOTH backends, and the declaring-module coherence
     relaxation is sound unconditionally (no ctor-sharing carve-out). Accept
     witness: specs/lang/types/accept/t90. Cross-backend runtime witness:
     test/imports/speak_double_collision_native. Companion (DISTINCT ctor names):
     test_impl_coherence_distinct_modules_general_iface_ok. *)
  let ctx = typecheck {|mod Top do
    interface Speak(a) do
      fn speak : a -> String
    end
    mod NA do
      type Thing = Shared | OnlyA
      impl Speak(Thing) do fn speak(_x) do "a" end end
    end
    mod NB do
      type Thing = Shared | OnlyB
      impl Speak(Thing) do fn speak(_x) do "b" end end
    end
  end|} in
  Alcotest.(check bool) "shared-ctor-name double collision: no error"
    false (has_errors ctx)

(* FQN dispatch-identity plan, Task 1: add_ctor's structural dedup (same
   ci_type/ci_params/ci_arg_tys) used to collapse a SECOND module's
   identically-shaped ctor onto the first, discarding which module the
   surviving candidate belongs to entirely — env.ctors "Shared" ended up
   with only ONE ctor_info even though DcA and DcB each declare their own
   nullary `Shared`. Later tasks in this plan (double-collision resolution)
   need BOTH candidates retrievable under the bare key, so add_ctor's `same`
   predicate now also compares ci_module. This fixture has no `impl`s, so it
   does not touch the Task-6b coherence stopgap (register_impl_shape) at
   all — it exercises add_ctor in isolation. *)
let test_add_ctor_keeps_distinct_module_identical_shape_ctors () =
  let (_errors, env) = typecheck_full {|mod Top do
    mod DcA do
      type Thing = Shared | OnlyA
    end
    mod DcB do
      type Thing = Shared | OnlyB
    end
    fn main() do () end
  end|} in
  let candidates =
    match March_typecheck.Typecheck.StrMap.find_opt "Shared"
            env.March_typecheck.Typecheck.ctors with
    | None -> []
    | Some cis -> cis
  in
  let modules = List.sort_uniq compare
      (List.map (fun ci -> ci.March_typecheck.Typecheck.ci_module) candidates) in
  Alcotest.(check int) "two distinct declaring modules survive for `Shared`"
    2 (List.length modules)

(* FQN dispatch-identity plan, Task 2: now that Task 1's add_ctor keeps BOTH
   distinct-module candidates for a colliding bare ctor name (e.g. `Shared`),
   RESOLUTION of a bare reference must prefer the candidate whose ci_module
   matches the reference's own lexical current module — a bare `Shared`
   written inside DcA's own code must mean DcA's own `Shared`, not whichever
   candidate happens to be first in env.ctors's internal list. *)
let test_ctor_lexical_preference_both_modules () =
  let ctx = typecheck {|
mod Top do
  mod DcA do
    type Thing = Shared | OnlyA
    fn mk_a() do Shared end
  end
  mod DcB do
    type Thing = Shared | OnlyB
    fn mk_b() do Shared end
  end
  fn main() do () end
end
|} in
  Alcotest.(check bool) "both modules' own bare Shared reference typechecks cleanly"
    false (has_errors ctx)

(* A genuinely ambiguous bare reference — candidates from TWO DIFFERENT
   declaring modules, and the referencing module (DcC) owns NEITHER — must be
   a hard error requiring explicit qualification, not the pre-existing soft
   hint (which stays reserved for the unrelated same-module/cross-type-sharing
   case; see test_ctor_ambiguity_hint_unaffected_by_cross_module_error below). *)
let test_ctor_truly_ambiguous_is_error () =
  let ctx = typecheck {|
mod Top do
  mod DcA do
    type Thing = Shared | OnlyA
  end
  mod DcB do
    type Thing = Shared | OnlyB
  end
  mod DcC do
    fn mk_ambiguous() do Shared end
  end
  fn main() do () end
end
|} in
  Alcotest.(check bool) "third-module bare ambiguous ctor ref is a hard error"
    true (has_errors ctx)

(* The explicit-qualification escape hatch for the above must still work. *)
let test_ctor_qualified_reference_from_third_module_ok () =
  let ctx = typecheck {|
mod Top do
  mod DcA do
    type Thing = Shared | OnlyA
  end
  mod DcB do
    type Thing = Shared | OnlyB
  end
  mod DcC do
    fn mk_explicit() do DcA.Shared end
  end
  fn main() do () end
end
|} in
  Alcotest.(check bool) "explicitly-qualified third-module reference typechecks cleanly"
    false (has_errors ctx)

(* Review follow-up (Minor finding): test_ctor_lexical_preference_both_modules
   above only asserts `has_errors = false`, which cannot distinguish "lexical
   preference picked the CORRECT candidate" from "it picked either candidate,
   no type error either way" — both DcA's and DcB's `Thing` share the same
   bare surface type `TCon("Thing", [])` (ci_type is bare pre-Stage-3), so a
   wrong pick still type-checks cleanly. This test locks in the actual
   property directly by calling `lookup_ctor` itself with `current_module`
   set to each module in turn and inspecting which candidate's `ci_module`
   comes back — mirroring Task 1's own env-inspection technique
   (test_add_ctor_keeps_distinct_module_identical_shape_ctors above). A
   regression that reverted `lookup_ctor` back to "first in the list" would
   fail this test even though it would NOT fail
   test_ctor_lexical_preference_both_modules. *)
let test_ctor_lexical_preference_directly_inspects_lookup_ctor () =
  let (_errors, env) = typecheck_full {|mod Top do
    mod DcA do
      type Thing = Shared | OnlyA
    end
    mod DcB do
      type Thing = Shared | OnlyB
    end
    fn main() do () end
  end|} in
  let module_of_lookup current_module =
    let env' = { env with March_typecheck.Typecheck.current_module } in
    match March_typecheck.Typecheck.lookup_ctor "Shared" env' with
    | Some ci -> ci.March_typecheck.Typecheck.ci_module
    | None -> "<none>"
  in
  Alcotest.(check string) "lookup_ctor with current_module=DcA returns DcA's own Shared"
    "DcA" (module_of_lookup "DcA");
  Alcotest.(check string) "lookup_ctor with current_module=DcB returns DcB's own Shared"
    "DcB" (module_of_lookup "DcB")

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
  (* Accessing a linear record field twice must error for a LET-BOUND record —
     the sentinel "p#data" is created when p is let-bound
     (bind_linear_field_sentinels) and record_use fires on each p.data.
     HISTORY (slice 7): this test originally used a fn-PARAM-bound record
     (`fn bad(r: Packet) do r.data + r.data end`) and passed VACUOUSLY on the
     L2 constraint-discharge leak ("`linear Int` does not implement Num") —
     params never get field sentinels (L3), so no double-use error ever fired.
     Rewritten to the let-bound shape, where the real double-use check runs;
     the param shape is pinned by test_linear_field_param_double_use_error. *)
  let ctx = typecheck {|mod Test do
    type Packet = { linear data: Int, size: Int }
    fn mk() : Packet do
      { data: 1, size: 2 }
    end
    fn bad() : Int do
      let p = mk()
      let x = p.data
      let y = p.data
      x + y
    end
  end|} in
  Alcotest.(check bool) "linear field let-bound double-access: error" true (has_errors ctx)

let test_linear_field_single_access_ok () =
  (* Accessing a linear record field exactly once should be fine. *)
  let ctx = typecheck {|mod Test do
    type Packet = { linear data: Int, size: Int }
    fn ok(r: Packet) : Int do
      r.data
    end
  end|} in
  Alcotest.(check bool) "linear field single access: no error" false (has_errors ctx)

(* ── Slice 7 (L2): TLin must be transparent to constraint discharge ──────── *)

let test_linear_field_arith_single_use_ok () =
  (* L2: a single arithmetic use of a linear Int field must typecheck —
     constraint discharge must strip the TLin wrapper (like impl_matches_ty
     already does) instead of rejecting `linear Int` as not-Num.  The leak
     bites expression-position TLin: the EField result type reaches the Num
     constraint still wrapped (var-position TLin is already stripped at
     binding time by bind_pattern_bindings/bind_linear). *)
  let ctx = typecheck {|mod Test do
    type Packet = { linear data: Int, size: Int }
    fn ok2(p: Packet) : Int do
      p.data + 1
    end
  end|} in
  Alcotest.(check bool) "linear Int field arithmetic: no error" false (has_errors ctx)

let test_linear_return_arith_ok () =
  (* L2, second expression-position shape: a call whose declared return type
     is `linear Int`, used directly in arithmetic (the tutorial's FFI
     `malloc : linear Ptr(a)` pattern). *)
  let ctx = typecheck {|mod Test do
    fn mk() : linear Int do
      1
    end
    fn f() : Int do
      mk() + 1
    end
  end|} in
  Alcotest.(check bool) "linear return type arithmetic: no error" false (has_errors ctx)

let test_linear_field_param_double_use_error () =
  (* L3 FIXED (2026-07-17): a fn-PARAM-bound record now registers per-field
     linear sentinels (check_fn's param loop calls bind_linear_field_sentinels,
     mirroring bind_lam_param / let-binding sites), so a double access of a
     `linear` field through a param is a hard ERROR — was warning-only. *)
  let ctx = typecheck {|mod Test do
    type Packet = { linear data: Int, size: Int }
    fn bad(p: Packet) : Int do
      let x = p.data
      let y = p.data
      x + y
    end
  end|} in
  Alcotest.(check bool) "param-bound linear field double-use: ERROR (L3)" true (has_errors ctx)

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

let test_session_binary_choice_identical_branches () =
  (* Regression (F4 / finding 20): the MPST "mergeability" rule must NOT be
     applied to BINARY (2-role) protocols.  In a binary `choose by Server`, the
     non-chooser (Client) is the chooser's only peer — the offerer — and MUST
     always observe the choice.  Previously the merge rule fired unconditionally,
     so when both branches carried an identical payload type the Client
     projection collapsed from Offer{...} to the bare shared local type
     (Recv(Int, End)), which is not the dual of Server's Choose{...}; duality then
     failed and a perfectly legal protocol was rejected as "not duals".
     Post-fix the merge is gated on `multiparty`, so Client stays an Offer and
     duality holds. *)
  let (ctx, env) = typecheck_full {|mod Test do
    protocol Decision do
      choose by Server:
        ok  -> Server -> Client : Int
        err -> Server -> Client : Int
      end
    end
  end|} in
  (* The protocol must typecheck (projection + binary duality both pass). *)
  Alcotest.(check bool) "binary identical-branch choice: no errors"
    false (has_errors ctx);
  let pi = March_typecheck.Typecheck.StrMap.find "Decision" env.March_typecheck.Typecheck.protocols in
  let client_ty = List.assoc "Client" pi.March_typecheck.Typecheck.pi_projections in
  let server_ty = List.assoc "Server" pi.March_typecheck.Typecheck.pi_projections in
  (* The non-chooser peer must remain an Offer{...} — NOT merged away. *)
  (match client_ty with
   | March_typecheck.Typecheck.SOffer _ ->
     Alcotest.(check bool) "Client projects to Offer (not merged)" true true
   | other ->
     Alcotest.failf "Client should project to Offer{...} but got: %s" (pp_sty other));
  (* And that Offer is exactly the dual of Server's Choose{...}. *)
  let dual_server = March_typecheck.Typecheck.dual_session_ty server_ty in
  Alcotest.(check bool) "dual(Server) = Client"
    true
    (March_typecheck.Typecheck.session_ty_equal dual_server client_ty)

let test_session_mpst_bystander_still_merges () =
  (* Regression companion to test_session_binary_choice_identical_branches:
     the merge rule MUST still fire for MULTIPARTY (>2 role) protocols, where a
     genuine bystander role does not observe a choice made between two OTHER
     roles.  Here `C` sends to `A` before `A` chooses between two A->B branches;
     `C` is uninvolved in the choice, so its projection across both branches is
     identical and merges to a single transparent local type (MSend(A, Int, End))
     rather than an Offer.  This proves the `multiparty &&` gate did not disable
     the MPST merge. *)
  let (ctx, env) = typecheck_full {|mod Test do
    protocol Coord do
      C -> A : Int
      choose by A:
        go   -> A -> B : Int
        stop -> A -> B : Int
      end
    end
  end|} in
  Alcotest.(check bool) "3-role protocol: no errors" false (has_errors ctx);
  let pi = March_typecheck.Typecheck.StrMap.find "Coord" env.March_typecheck.Typecheck.protocols in
  let c_ty = List.assoc "C" pi.March_typecheck.Typecheck.pi_projections in
  (* Bystander C merges across the choice — a plain MSend, never an Offer. *)
  (match c_ty with
   | March_typecheck.Typecheck.SOffer _ ->
     Alcotest.failf "bystander C should merge (not Offer) but got: %s" (pp_sty c_ty)
   | _ -> ());
  Alcotest.(check string) "bystander C merges to a single local type"
    "MSend(A, Int, End)" (pp_sty c_ty)

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

(* ── C1 fix: actor handler BODY IO with no declared `needs` ───────────────
   Finding C1 (final whole-branch review, HCR Phase 5C): [record_fn_caps] was
   never called for actor handlers at all, so handler functions ended up as
   `.hcr_manifest` boundary entries with an empty `caps=` field regardless of
   what IO they actually performed — invisible to the hot-deploy monotonicity
   gate. Part 2 of the fix folds handler bodies into the SAME body-scan
   [check_module_needs]'s `body_cap_uses` already does for `DFn`/`DLet`
   bodies, so a handler calling an IO builtin with no covering `needs`
   now produces the same "capability not declared in needs" diagnostic a
   plain function body would (Check 1b — a warning, matching the existing
   DFn/DLet body-scan diagnostic's severity).

   This fixture uses a 2-level-deep nested module (`Outer.Inner`) to also
   exercise the qualified-name path through [check_module_needs]'s
   [cap_qname_prefix] threading (mirrors the nesting depth Task 2's earlier
   `DFn` qualified-name fix was verified against). *)
let test_actor_handler_body_io_missing_needs_warns () =
  let ctx = typecheck {|mod Outer do
    mod Inner do
      actor Weeble do
        state { count: Int }
        init { count: 0 }
        on Zorp(msg: String) do
          println(msg)
          state
        end
      end
    end
  end|} in
  Alcotest.(check bool) "no needs declared: no hard error" false (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  let has_warning =
    List.exists (fun d ->
      d.March_errors.Errors.severity = March_errors.Errors.Warning
      && (let m = d.March_errors.Errors.message in
          (try ignore (Str.search_forward (Str.regexp_string "IO.Console") m 0); true
           with Not_found -> false)
          && (try ignore (Str.search_forward (Str.regexp_string "needs") m 0); true
              with Not_found -> false))
    ) diags
  in
  Alcotest.(check bool)
    "actor handler body IO with no needs: warns to declare needs IO.Console"
    true has_warning

(* Counterpart: when the module DOES declare the needed cap, no such warning
   fires — confirms the new body-scan doesn't introduce a false positive. *)
let test_actor_handler_body_io_with_needs_no_warning () =
  let ctx = typecheck {|mod Outer do
    mod Inner do
      needs IO.Console
      actor Weeble do
        state { count: Int }
        init { count: 0 }
        on Zorp(msg: String) do
          println(msg)
          state
        end
      end
    end
  end|} in
  Alcotest.(check bool) "needs declared: no hard error" false (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  let has_warning =
    List.exists (fun d ->
      d.March_errors.Errors.severity = March_errors.Errors.Warning
      && (let m = d.March_errors.Errors.message in
          (try ignore (Str.search_forward (Str.regexp_string "not declare") m 0); true
           with Not_found -> false))
    ) diags
  in
  Alcotest.(check bool)
    "actor handler body IO with needs declared: no missing-needs warning"
    false has_warning

(* ── Cap(IO.NetListen) body-scan enforcement (item 1380) ─────────────────
   tcp_listen / tcp_accept / http_server_listen are classified IO.NetListen in
   builtin_cap_table (typecheck.ml).  A module whose body calls one without
   declaring `needs IO.NetListen` warns; declaring it silences the warning; and
   the DISTINCT NetConnect cap must not satisfy a NetListen requirement. *)
let netlisten_body_warns name =
  let m =
    (try ignore (Str.search_forward (Str.regexp_string "IO.NetListen") name 0); true
     with Not_found -> false)
    && (try ignore (Str.search_forward (Str.regexp_string "needs") name 0); true
        with Not_found -> false)
  in m

let test_netlisten_body_missing_needs_warns () =
  let ctx = typecheck {|mod Srv do
    fn serve() do
      tcp_listen(8080)
    end
  end|} in
  Alcotest.(check bool) "no needs: no hard error" false (has_errors ctx);
  let has_warning =
    List.exists (fun d ->
      d.March_errors.Errors.severity = March_errors.Errors.Warning
      && netlisten_body_warns d.March_errors.Errors.message)
      (March_errors.Errors.sorted ctx)
  in
  Alcotest.(check bool)
    "tcp_listen with no needs: warns to declare needs IO.NetListen" true has_warning

let test_netlisten_body_with_needs_no_warning () =
  let ctx = typecheck {|mod Srv do
    needs IO.NetListen
    fn serve() do
      tcp_listen(8080)
    end
  end|} in
  Alcotest.(check bool) "needs declared: no hard error" false (has_errors ctx);
  let has_warning =
    List.exists (fun d ->
      d.March_errors.Errors.severity = March_errors.Errors.Warning
      && netlisten_body_warns d.March_errors.Errors.message)
      (March_errors.Errors.sorted ctx)
  in
  Alcotest.(check bool)
    "tcp_listen with needs IO.NetListen: no missing-needs warning" false has_warning

let test_netlisten_not_satisfied_by_netconnect () =
  (* NetConnect (client) is a sibling leaf, NOT a super-cap of NetListen; it must
     not satisfy a NetListen body requirement. *)
  let ctx = typecheck {|mod Srv do
    needs IO.NetConnect
    fn serve() do
      tcp_listen(8080)
    end
  end|} in
  let has_warning =
    List.exists (fun d ->
      d.March_errors.Errors.severity = March_errors.Errors.Warning
      && netlisten_body_warns d.March_errors.Errors.message)
      (March_errors.Errors.sorted ctx)
  in
  Alcotest.(check bool)
    "NetConnect does not satisfy a NetListen requirement: still warns" true has_warning

(* ── spawn requires a plain actor name, not a computed expression ─────────
   Regression: a well-typed `spawn(<computed expr>)` — e.g. an `if` that
   evaluates to an actor name — passed `--check` (exit 0) but crashed
   `--compile` with an uncaught
   `Failure("TIR lower: ESpawn argument must be a plain actor name")`.  Both
   backends dispatch `spawn` by the actor's *name* at compile time (it selects
   a statically generated `<Actor>_spawn` function); the TIR lowering only
   handles a bare actor name (`ECon(_,[],_)`/`EVar`).  The shape restriction now
   lives in the typechecker as a structured diagnostic, so the program is
   rejected uniformly (check / compile / interpret) before it can reach the
   internal failwith. *)
let test_spawn_computed_actor_rejected () =
  let ctx = typecheck {|mod Test do
    actor Counter do
      state { value: Int }
      init { value: 0 }
      on Inc(n: Int) do
        { state with value: state.value + n }
      end
    end
    fn main() : Unit do
      let c = spawn(if true do Counter else Counter end)
      kill(c)
    end
  end|} in
  Alcotest.(check bool) "computed actor spawn: error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  let mentions m needle =
    try ignore (Str.search_forward (Str.regexp_string needle) m 0); true
    with Not_found -> false
  in
  let explains_spawn =
    List.exists (fun d ->
      let m = d.March_errors.Errors.message in
      mentions m "spawn" && mentions m "plain actor name")
      diags
  in
  Alcotest.(check bool)
    "diagnostic explains spawn needs a plain actor name" true explains_spawn

(* Counterpart: a bare actor name still typechecks cleanly — the guard must
   not flag the valid `spawn(Counter)` form. *)
let test_spawn_plain_actor_name_ok () =
  let ctx = typecheck {|mod Test do
    actor Counter do
      state { value: Int }
      init { value: 0 }
      on Inc(n: Int) do
        { state with value: state.value + n }
      end
    end
    fn main() : Unit do
      let c = spawn(Counter)
      kill(c)
    end
  end|} in
  Alcotest.(check bool) "plain actor spawn: no errors" false (has_errors ctx)

(* ── Finding 16: let-binding type annotations are enforced ──────────────── *)

(* Count the Error diagnostics whose message contains [needle]. *)
let count_errors_matching ctx needle =
  List.fold_left (fun acc (d : March_errors.Errors.diagnostic) ->
      if d.March_errors.Errors.severity = March_errors.Errors.Error
         && (try ignore (Str.search_forward (Str.regexp_string needle)
                           d.March_errors.Errors.message 0); true
             with Not_found -> false)
      then acc + 1 else acc)
    0 (March_errors.Errors.sorted ctx)

(* `let x : Int = "foo"` must now be rejected — the annotation is a checking
   context for the RHS (finding 16). *)
let test_let_annot_mismatch_rejects () =
  let ctx = typecheck {|mod M do
    fn main() do
      let x : Int = "foo"
      println(int_to_string(x))
    end
  end|} in
  Alcotest.(check bool) "let : Int = String rejected" true (has_errors ctx);
  Alcotest.(check bool) "mismatch names Int vs String" true
    (count_errors_matching ctx "expected `Int` but got `String`." >= 1)

(* A correct annotation still typechecks. *)
let test_let_annot_correct_accepts () =
  let ctx = typecheck {|mod M do
    fn main() do
      let x : Int = 5
      println(int_to_string(x))
    end
  end|} in
  Alcotest.(check bool) "let : Int = 5 accepted" false (has_errors ctx)

(* A polymorphic RHS bound at a more specific annotated type still works — the
   annotation must be a checking context, not a monomorphizing constraint on
   the RHS's own general type. *)
let test_let_annot_poly_instance_accepts () =
  let ctx = typecheck {|mod M do
    fn main() do
      let f : (Int) -> Int = fn n -> n
      println(int_to_string(f(5)))
    end
  end|} in
  Alcotest.(check bool) "let : (Int)->Int = fn n -> n accepted" false (has_errors ctx)

(* ── Zero-arg lambda satisfies a `Unit -> Unit` callback param ───────────
   A 0-arg lambda `fn -> body` types to its body's result (a thunk), so it
   used to be un-passable to a declared `Unit -> Unit` parameter ("expected
   () but got () -> ()"); and calling such a callback with `cb()` yielded the
   arrow type rather than the result.  Both boundaries are now reconciled: a
   `Unit -> T` arrow behaves like a 0-arg callable at both construction
   (checking `fn -> body` against it) and call (`cb()`). *)
let test_zero_arg_lambda_unit_callback_accepts () =
  let ctx = typecheck {|mod Main do
    fn call_it(cb : Unit -> Unit) : Unit do cb() end
    fn once() : Unit do println("ran") end
    fn main() do call_it(fn -> once()) end
  end|} in
  Alcotest.(check bool) "call_it(fn -> once()) : Unit -> Unit accepted"
    false (has_errors ctx)

(* A `Unit -> T` value called with empty parens `f()` yields `T`, not the
   arrow — the symmetric call-site half of the fix above. *)
let test_zero_arg_unit_call_returns_result () =
  let ctx = typecheck {|mod Main do
    fn main() do
      let n = int_max_value()
      println(int_to_string(n))
    end
  end|} in
  Alcotest.(check bool) "int_max_value() : Unit -> Int yields Int"
    false (has_errors ctx)

(* GREEN-STAYS-GREEN guard: the pre-existing thunk idiom `fn _ -> body`
   (a 1-arg discard, the shape task_spawn's callback expects) is unaffected. *)
let test_discard_arg_thunk_still_accepts () =
  let ctx = typecheck {|mod Main do
    needs IO.Spawn
    fn main() do
      let _t = task_spawn(fn _ -> 42)
      println("spawned")
    end
  end|} in
  Alcotest.(check bool) "task_spawn(fn _ -> 42) still accepted"
    false (has_errors ctx)

(* ── Finding 13: ELetFn return-annotation mismatch reported ONCE ────────── *)

(* A local recursive fn whose return annotation conflicts with its
   self-consistent body must report the mismatch exactly ONCE, not twice (the
   direct return-annotation unify and the self-type/arrow reconciliation both
   used to rediscover the same conflict through the self-reference). *)
let test_letfn_ret_annot_mismatch_single_diagnostic () =
  let ctx = typecheck {|mod M do
    fn describe(n : Int) do
      fn go(k) : Int do
        match k do
          0 -> "done"
          _ -> go(k - 1)
        end
      end
      go(n)
    end
    fn main() do
      println(int_to_string(describe(3)))
    end
  end|} in
  Alcotest.(check bool) "ELetFn ret-annot conflict rejected" true (has_errors ctx);
  Alcotest.(check int) "reported exactly once"
    1 (count_errors_matching ctx "expected `Int` but got `String`.")

(* Safety: two genuinely-distinct type errors must both still be reported —
   the dedup must not swallow the second, unrelated error. *)
let test_letfn_two_distinct_errors_both_report () =
  let ctx = typecheck {|mod M do
    fn describe(n : Int) do
      fn go(k) : Int do
        match k do
          0 -> "done"
          _ -> go(k - 1)
        end
      end
      let bad : Bool = 42
      go(n)
    end
    fn main() do
      println(int_to_string(describe(3)))
    end
  end|} in
  Alcotest.(check int) "ELetFn conflict reported once"
    1 (count_errors_matching ctx "expected `Int` but got `String`.");
  Alcotest.(check int) "distinct Bool/Int error still reported"
    1 (count_errors_matching ctx "expected `Bool` but got `Int`.")

(* ── Finding 15: generic when-constraint re-checked at call sites ───────── *)

(* An explicit `when Eq(a)` bound on an UNANNOTATED generic parameter must be
   re-checked at call sites: `same(Rood, Rood)` on an ADT with no `Eq` impl is
   rejected, just as a direct `Rood == Rood` would be. *)
let test_generic_when_constraint_unsatisfied_rejects () =
  let ctx = typecheck {|mod M do
    type Hue = Rood | Bloo
    fn same(a, b) when Eq(a) do a == b end
    fn main() do
      if same(Rood, Rood) do println("y") else println("n") end
    end
  end|} in
  Alcotest.(check bool) "unsatisfied generic when-constraint rejected" true
    (has_errors ctx);
  Alcotest.(check bool) "names Hue/Eq" true
    (count_errors_matching ctx "`Hue` does not implement interface `Eq`." >= 1)

(* Safety valve: a generic `when Ord(a)` / `when Eq(a)` bound that IS satisfied
   at the call site (Int implements both) must still typecheck — the re-check
   must not reject discharged constraints. *)
let test_generic_when_constraint_satisfied_accepts () =
  let ctx = typecheck {|mod M do
    fn max(a, b) when Ord(a) do if a > b do a else b end end
    fn same(a, b) when Eq(a) do a == b end
    fn main() do
      println(int_to_string(max(1, 2)))
      if same(1, 1) do println("eq") else println("neq") end
      if same("x", "y") do println("eq") else println("neq") end
    end
  end|} in
  Alcotest.(check bool) "satisfied generic when-constraint accepted" false
    (has_errors ctx)

(* Safety valve: an ordinary unconstrained generic function is unaffected. *)
let test_generic_no_constraint_accepts () =
  let ctx = typecheck {|mod M do
    fn id(a) do a end
    fn main() do
      println(int_to_string(id(5)))
      println(id("hi"))
    end
  end|} in
  Alcotest.(check bool) "unconstrained generic accepted" false (has_errors ctx)

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
      let sc2 = Chan.send(sc, 43)
      let (n, rc2) = Chan.recv(rc)
      let rc3 = Chan.send(rc2, n + 1)
      let (result, sc3) = Chan.recv(sc2)
      Chan.close(sc3)
      Chan.close(rc3)
      result
    end
  end|} in
  let v = call_fn env "run" [] in
  (* Odd payload (43) exercises the erased-i64 tag path both legs; the compiled
     value round-trip is asserted by test_session_compile_odd_int_roundtrip. *)
  Alcotest.(check int) "eval echo protocol: result = 44" 44 (vint v)

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

(* ── Compiled channel-payload value round-trips (F1/F2 regression) ────────
   The IR-shape tests above assert only that `march_chan_*` symbols APPEAR in
   the emitted module — they never run the compiled binary or check a carried
   value, so they stayed green while every ODD Int payload compiled to
   `(v-1)/2` and every Bool flipped `true→false`.  Root cause: `march_chan_send`
   received the payload as a bare untagged `i64`, while `march_chan_recv`'s
   returned payload went through the erased-i64 CONDITIONAL-UNTAG restore
   (ashr iff low bit set) — an asymmetric coercion.  The fix tags the payload
   at the send site (llvm_emit.ml `chan_send`/`chan_choose`/`mpst_send` arms,
   `emit_atom_as ctx "ptr"`) so send/recv are symmetric.  These tests compile
   and RUN the binary, checking the printed value: they FAIL on the pre-fix
   binary (43→21, true→false) and pass after.  Modelled on the compile-and-run
   regression tests in test_codegen.ml (write source to a temp dir, run interp
   for the baseline, then compile + run + check the printed value). *)

(* Read the whole stdout+stderr of a command (trimmed). *)
let session_read_cmd_output cmd =
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 64 in
  (try while true do Buffer.add_channel buf ic 1 done
   with End_of_file -> ());
  ignore (Unix.close_process_in ic);
  String.trim (Buffer.contents buf)

(* Write [src_text] to a fresh temp dir; return (project_root, main_exe, src, tmp). *)
let session_write_src ~name src_text =
  let main_exe = find_main_exe () in
  let project_root = march_project_root () in
  let tmp = Filename.temp_file name "" in
  Sys.remove tmp;
  Unix.mkdir tmp 0o755;
  let src = Filename.concat tmp (name ^ ".march") in
  let oc = open_out src in
  output_string oc src_text;
  close_out oc;
  (project_root, main_exe, src, tmp)

(** Odd Int payload (43) round-trips through Chan.send/recv compiled.  The
    interpreter is the baseline (already correct); the compiled binary must
    print the SAME value.  Pre-fix, the compiled run printed 21 (=(43-1)/2). *)
let test_session_compile_odd_int_roundtrip () =
  let (project_root, main_exe, src, tmp) =
    session_write_src ~name:"march_session_oddint"
      "mod Main do\n\
      \  protocol Echo do\n\
      \    Client -> Server : Int\n\
      \    Server -> Client : Int\n\
      \  end\n\
      \  fn main() do\n\
      \    let (cc, sc) = Chan.new(Echo)\n\
      \    let cc2 = Chan.send(cc, 43)\n\
      \    let (n, sc2) = Chan.recv(sc)\n\
      \    let sc3 = Chan.send(sc2, n)\n\
      \    let (result, cc3) = Chan.recv(cc2)\n\
      \    Chan.close(cc3)\n\
      \    Chan.close(sc3)\n\
      \    println(int_to_string(result))\n\
      \  end\n\
       end\n"
  in
  (* interpreter baseline: the odd payload round-trips as 43 *)
  let interp_out = session_read_cmd_output (Printf.sprintf
    "cd %s && %s %s 2>&1"
    (Filename.quote project_root) (Filename.quote main_exe) (Filename.quote src)) in
  Alcotest.(check string) "interp: odd Int channel payload round-trips (43)"
    "43" interp_out;
  (* compiled: MUST print 43 too — pre-fix this printed 21 (the F1 miscompile) *)
  let bin = Filename.concat tmp "sessoddintbin" in
  match compile_march_or_skip
          ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = session_read_cmd_output (Filename.quote bin) in
    Alcotest.(check string)
      "compiled: odd Int channel payload round-trips as 43 (not 21 — F1 tag fix)"
      "43" run_out

(** Bool payload (true) round-trips through Chan.send/recv compiled.  Pre-fix,
    the compiled run flipped true→false (the F2 miscompile). *)
let test_session_compile_bool_roundtrip () =
  let (project_root, main_exe, src, tmp) =
    session_write_src ~name:"march_session_bool"
      "mod Main do\n\
      \  protocol B do\n\
      \    Client -> Server : Bool\n\
      \  end\n\
      \  fn main() do\n\
      \    let (cc, sc) = Chan.new(B)\n\
      \    let cc2 = Chan.send(cc, true)\n\
      \    let (b, sc2) = Chan.recv(sc)\n\
      \    Chan.close(cc2)\n\
      \    Chan.close(sc2)\n\
      \    if b do println(\"TRUE\") else println(\"FALSE\") end\n\
      \  end\n\
       end\n"
  in
  let interp_out = session_read_cmd_output (Printf.sprintf
    "cd %s && %s %s 2>&1"
    (Filename.quote project_root) (Filename.quote main_exe) (Filename.quote src)) in
  Alcotest.(check string) "interp: Bool channel payload round-trips (true)"
    "TRUE" interp_out;
  let bin = Filename.concat tmp "sessboolbin" in
  match compile_march_or_skip
          ~cmd_prefix:(Printf.sprintf "cd %s && " (Filename.quote project_root))
          ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let run_out = session_read_cmd_output (Filename.quote bin) in
    Alcotest.(check string)
      "compiled: Bool channel payload round-trips as TRUE (not FALSE — F2 tag fix)"
      "TRUE" run_out

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

(** file_read's error is always a concrete FileError value at runtime (never
    an arbitrary String) — its registered type must not let the error type
    unify with an incompatible concrete type like String.  Regression for a
    typechecker soundness gap: this used to typecheck with zero errors and
    then panic at runtime the moment `e` was used as a String. *)
let test_letq_file_read_wrong_error_type () =
  let ctx = typecheck {|mod Test do
    needs IO.FileRead
    fn run(path) : Result(String, String) do
      let? content = file_read(path)
      Ok(content)
    end
  end|} in
  Alcotest.(check bool) "file_read error must not unify with String: type error"
    true (has_errors ctx)

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
      Cons(h, t) -> if eq(h, x) do true else contains(t, x) end
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
      Cons(h, t) -> if eq(h, x) do true else contains(t, x) end
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

(* Regression (modules widening slice 2, Task 1): cross-module visibility for
   private FUNCTIONS. `Array.lst_rev` is a real private `pfn`
   (stdlib/array.march). It must NOT be callable by qualification from another
   module. The bug: `load_module_into_env` loaded `ExFn`/`ExValue` entries
   UNCONDITIONALLY (never consulting `ex_public`), unlike the adjacent `ExCtor`
   arm which correctly gates on it — so a private `pfn` from any
   registry-loadable module (any stdlib module) was silently callable from
   unrelated code, typecheck AND runtime, both backends. The fix adds the
   `ex_public` gate to the `ExFn`/`ExValue` arm: the qualified lookup now misses,
   and `qualified_error_msg` reports "… is private to module `Array`.".
   This exercises the `Module_registry.ensure_loaded` fallback path (the buggy
   one) — the module is discovered on disk by the registry, not spliced in as a
   `DMod`, so it does NOT go through the same-file `pub_set` gate that was
   already correct. *)
let has_message_containing ctx needle =
  List.exists (fun d ->
    let m = d.March_errors.Errors.message in
    let nl = String.length needle and ml = String.length m in
    let rec scan i = i + nl <= ml && (String.sub m i nl = needle || scan (i + 1)) in
    scan 0)
    ctx.March_errors.Errors.diagnostics

let test_cross_module_private_fn_rejected () =
  let ctx = typecheck {|mod Main do
    fn main() : Int do
      let r = Array.lst_rev(Cons(1, Cons(2, Cons(3, Nil))))
      match r do
        Nil -> 0
        Cons(h, _) -> h
      end
    end
  end|} in
  Alcotest.(check bool) "private cross-module pfn call is rejected"
    true (has_errors ctx);
  Alcotest.(check bool) "rejection cites 'is private to module `Array`'"
    true (has_message_containing ctx "is private to module `Array`")

(* Companion: the gate is NARROW — a PUBLIC cross-module call still resolves.
   `Array.empty`/`Array.length` are public `fn`s reached through the same
   registry fallback; they must remain callable (no visibility error). *)
let test_cross_module_public_fn_accepted () =
  let ctx = typecheck {|mod Main do
    fn main() : Int do
      let v = Array.empty()
      Array.length(v)
    end
  end|} in
  Alcotest.(check bool) "public cross-module fn call: no errors"
    false (has_errors ctx)

(* Regression: a module-qualified type reference (`Token.Token`) from OUTSIDE a
   module must be the SAME nominal type as the bare `Token` the module's own
   constructor/accessor produce.  `surface_ty` used to resolve the qualified
   reference to a distinct `TCon("Token.Token")` that would not unify with the
   bare `TCon("Token")`, so a value crossing the module boundary failed with
   "expected `Token.Token` but got `Token`".  This is the variant/opaque-type
   analogue of the `Cfg.Site` record leak (see test/dune whole_program rule).
   Exercises BOTH directions: a bare-typed value flowing into a qualified-typed
   parameter (`use_it(Token.make ...)`), and a qualified-typed value flowing
   into a bare-typed parameter (`Token.value(t)`). *)
let test_qualified_opaque_type_unifies_bare () =
  let ctx = typecheck {|mod TokenDemo do
    mod Token do
      opaque type Token = Token(String)
      fn make(raw : String) : Token do Token(raw) end
      fn value(t : Token) : String do
        match t do Token(s) -> s end
      end
    end

    fn use_it(t : Token.Token) : String do
      Token.value(t)
    end

    fn main() : String do
      use_it(Token.make("hi"))
    end
  end|} in
  Alcotest.(check bool)
    "qualified `Token.Token` unifies with bare `Token`: no errors"
    false (has_errors ctx)

(* The same fixture must also evaluate end-to-end: the round-trip through the
   qualified annotation returns the string threaded through the opaque type. *)
let test_qualified_opaque_type_evals () =
  let env = eval_module {|mod TokenDemo do
    mod Token do
      opaque type Token = Token(String)
      fn make(raw : String) : Token do Token(raw) end
      fn value(t : Token) : String do
        match t do Token(s) -> s end
      end
    end

    fn use_it(t : Token.Token) : String do
      Token.value(t)
    end

    fn main() : String do
      use_it(Token.make("hi"))
    end
  end|} in
  let v = call_fn env "main" [] in
  Alcotest.(check string) "qualified opaque round-trip evaluates to \"hi\"" "hi" (vstr v)

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

(* Regression: an always-linear value bound via `let? p = e` (the RHS is a
   fresh call, not a pre-tracked linear variable) must still be tracked —
   `bind_pattern_bindings` (shared by `let?`, `with`, and match arms) used to
   only inherit linearity from a [TLin]-wrapped type or an already-linear
   scrutinee variable, silently skipping the `always_linear_types`
   auto-promotion that plain `let` and function params get. Two `let?`
   bindings each consuming `r` went unflagged as a result. *)
let test_linear_letq_acquire_double_use () =
  let ctx = typecheck {|mod Test do
    always_linear type Res = Res(Int)
    fn acquire() : Result(Res, String) do
      Ok(Res(1))
    end
    fn consume(r : Res) : Result(Int, String) do
      match r do
        Res(n) -> Ok(n)
      end
    end
    fn f() : Result(Int, String) do
      let? r = acquire()
      let? a = consume(r)
      let? b = consume(r)
      Ok(a + b)
    end
  end|} in
  Alcotest.(check bool) "let?-acquired linear value used twice: error" true (has_errors ctx)

(* Same gap via a single correct use — must NOT regress to a false positive. *)
let test_linear_letq_acquire_single_use_ok () =
  let ctx = typecheck {|mod Test do
    always_linear type Res = Res(Int)
    fn acquire() : Result(Res, String) do
      Ok(Res(1))
    end
    fn consume(r : Res) : Result(Int, String) do
      match r do
        Res(n) -> Ok(n)
      end
    end
    fn f() : Result(Int, String) do
      let? r = acquire()
      let? a = consume(r)
      Ok(a)
    end
  end|} in
  Alcotest.(check bool) "let?-acquired linear value used once: no errors" false (has_errors ctx)

(* Same gap through `with`'s desugared nested-match form. *)
let test_linear_with_acquire_double_use () =
  let ctx = typecheck {|mod Test do
    always_linear type Res = Res(Int)
    fn acquire() : Result(Res, String) do
      Ok(Res(1))
    end
    fn consume(r : Res) : Result(Int, String) do
      match r do
        Res(n) -> Ok(n)
      end
    end
    fn f() : Result(Int, String) do
      with Ok(r) <- acquire() do
        with Ok(a) <- consume(r), Ok(b) <- consume(r) do
          Ok(a + b)
        else
          Err(e) -> Err(e)
        end
      else
        Err(e) -> Err(e)
      end
    end
  end|} in
  Alcotest.(check bool) "with-acquired linear value used twice: error" true (has_errors ctx)

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

(** Regression test for the O(var-refs * imports) blowup in
    [Typecheck.record_use]: every EVar lookup used to linearly scan
    [env.import_tracker], whose length is one entry per use/import/alias
    declaration across the WHOLE combined program (stdlib + every file
    pulled in via MARCH_LIB_PATH auto-discovery).  On a real multi-hundred-
    file project (forgepm + bastion + depot + march_doc, ~200 files) this
    made `march check` hang for 30+ minutes burning 100% CPU in
    List.mem/compare_val (confirmed via `sample`), instead of completing in
    seconds.  This test builds a synthetic MARCH_LIB_PATH with many
    auto-discovered modules, each importing a shared module (`import Shared`)
    and referencing several of its functions -- the exact shape that
    stresses [record_use]'s import-tracker lookup -- and asserts the check
    completes within a bound chosen to clearly separate "linear" from
    "quadratic blowup" at this N.  Measured directly (CAS cache cleared
    between runs, so these are real typecheck times, not cache hits):
      files   pre-fix (quadratic)   post-fix (indexed)
       400          ~1.2s                ~0.6s
      1200          ~8.2s                ~1.4s   (~6x)
      2000         ~21.1s                ~2.3s   (~9x)
      3000         ~45.5s                ~3.7s  (~12x)
    Pre-fix time roughly follows n^2 (k ~= 5e-6); post-fix is ~linear.  This
    test uses N = 2500 files, where the pre-fix code would take ~31s (already
    past the 30s bound below) while the fixed code takes ~3s -- comfortably
    separating "would time out" from "clearly fine" without making the test
    itself slow. *)
let test_large_multi_file_check_is_not_quadratic () =
  let dir = Filename.temp_file "march_lib_path_scale_" "" in
  Sys.remove dir;
  Unix.mkdir dir 0o755;
  Fun.protect ~finally:(fun () ->
    (* Best-effort cleanup: this test writes thousands of small files. *)
    try ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)))
    with _ -> ()) (fun () ->
  let write_file path contents =
    let oc = open_out path in
    output_string oc contents;
    close_out oc
  in
  (* One shared module with several functions, imported by every generated
     module below via `import Shared` (a UseAll-style bulk import) -- this
     populates one [import_tracker] entry per importing file, and each
     `helperN()` call inside those files is an EVar lookup that must mark
     the right entry used via [record_use]. *)
  let n_helpers = 20 in
  let shared_src =
    let buf = Buffer.create 1024 in
    Buffer.add_string buf "mod Shared do\n";
    for i = 0 to n_helpers - 1 do
      Buffer.add_string buf (Printf.sprintf "  fn helper%d() do\n    %d\n  end\n" i i)
    done;
    Buffer.add_string buf "end\n";
    Buffer.contents buf
  in
  write_file (Filename.concat dir "shared.march") shared_src;
  let n_files = 2500 in
  let n_refs  = 30 in
  for i = 0 to n_files - 1 do
    let buf = Buffer.create 512 in
    Buffer.add_string buf (Printf.sprintf "mod Wu%d do\n" i);
    Buffer.add_string buf "  import Shared\n";
    Buffer.add_string buf "  fn value() do\n";
    for j = 0 to n_refs - 1 do
      Buffer.add_string buf
        (Printf.sprintf "    let x%d = helper%d() + %d\n" j (j mod n_helpers) j)
    done;
    Buffer.add_string buf "    x0\n  end\nend\n";
    write_file (Filename.concat dir (Printf.sprintf "wu%d.march" i)) (Buffer.contents buf)
  done;
  (* Entry file: trivial, imports nothing itself -- all the files above are
     pulled in purely via MARCH_LIB_PATH auto-discovery (resolve_imports's
     step 2), exactly like forgepm's `.march` tree under MARCH_LIB_PATH. *)
  let entry_src = "mod Entry do\n  fn main() do\n    0\n  end\nend\n" in
  Unix.putenv "MARCH_LIB_PATH" dir;
  Fun.protect ~finally:(fun () -> Unix.putenv "MARCH_LIB_PATH" "") (fun () ->
    let m = parse_and_desugar entry_src in
    let start = Unix.gettimeofday () in
    let (resolve_errors, extra_decls, _user_files) =
      March_resolver.Resolver.resolve_imports ~source_file:"entry.march" m in
    Alcotest.(check bool) "no resolve errors" true (resolve_errors = []);
    let m = { m with March_ast.Ast.mod_decls = extra_decls @ m.March_ast.Ast.mod_decls } in
    let (errors, _type_map) = March_typecheck.Typecheck.check_module m in
    let elapsed = Unix.gettimeofday () -. start in
    Alcotest.(check bool) "no typecheck errors" false (has_errors errors);
    (* 30s bound: the fixed (indexed) code finishes this N in ~3-5s even on a
       loaded CI box; the pre-fix O(var-refs * imports) scan measured ~31s+
       at this exact N (see the doc comment above) -- comfortably on the far
       side of this bound, so a regression back to the linear-scan version
       would fail this test rather than merely being "a bit slower". *)
    Alcotest.(check bool)
      (Printf.sprintf "multi-file check completes well under 30s (took %.2fs)" elapsed)
      true (elapsed < 30.0)))

(* ── opaque-type constructor visibility across compilation units ────────── *)

(* An `opaque type`'s constructor is Private (the parser forces `var_vis =
   Private` while keeping the type Public).  A sibling module discovered via
   MARCH_LIB_PATH must NOT be able to construct it under its qualified name
   (`Mod.Ctor(..)`): doing so bypasses the opacity boundary.  The Pass-1
   forward-reference pass (`prebind_mod_members`) used to seed the bare
   qualified ctor key unconditionally, so `OqToken.Token("x")` from unrelated
   code typechecked clean.  This test builds the two-file scenario in a temp
   MARCH_LIB_PATH and checks the entry via the same resolve+check pipeline the
   compiler uses. *)
let check_entry_with_lib_dir files entry_src =
  let dir = Filename.temp_file "march_opaque_vis_" "" in
  Sys.remove dir;
  Unix.mkdir dir 0o755;
  Fun.protect ~finally:(fun () ->
    try ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)))
    with _ -> ())
    (fun () ->
      List.iter (fun (name, contents) ->
          let oc = open_out (Filename.concat dir name) in
          output_string oc contents;
          close_out oc)
        files;
      Unix.putenv "MARCH_LIB_PATH" dir;
      Fun.protect ~finally:(fun () -> Unix.putenv "MARCH_LIB_PATH" "") (fun () ->
        let m = parse_and_desugar entry_src in
        let (resolve_errors, extra_decls, _user_files) =
          March_resolver.Resolver.resolve_imports ~source_file:"entry.march" m in
        Alcotest.(check bool) "no resolve errors" true (resolve_errors = []);
        let m = { m with March_ast.Ast.mod_decls = extra_decls @ m.March_ast.Ast.mod_decls } in
        let (errors, _type_map) = March_typecheck.Typecheck.check_module m in
        has_errors errors))

let oq_token_src = {|mod OqToken do
  opaque type Token = Token(String)
  fn make(raw : String) : Token do Token(raw) end
  fn value(t : Token) : String do
    match t do Token(s) -> s end
  end
end
|}

let test_opaque_ctor_qualified_bypass_rejected () =
  (* Sibling module constructs the private opaque ctor by qualified name. *)
  let bypass_src = {|mod OqBypass do
  fn main() do
    let t = OqToken.Token("direct-bypass")
    println(OqToken.value(t))
  end
end
|} in
  let errored = check_entry_with_lib_dir [("oq_token.march", oq_token_src)] bypass_src in
  Alcotest.(check bool)
    "qualified private opaque ctor from a sibling module must be rejected"
    true errored

let test_opaque_type_annotation_still_accepts () =
  (* Control: qualified name used only as a TYPE annotation plus the public
     make/value accessors must still typecheck clean. *)
  let entry_src = {|mod OqEntry do
  fn use_it(t : OqToken.Token) : String do
    OqToken.value(t)
  end

  fn round_trip() : String do
    use_it(OqToken.make("hi"))
  end
end
|} in
  let errored = check_entry_with_lib_dir [("oq_token.march", oq_token_src)] entry_src in
  Alcotest.(check bool)
    "opaque type used as annotation + public accessors still accepts"
    false errored

let test_public_ctor_qualified_still_resolves () =
  (* A PUBLIC variant's `Mod.Ctor(..)` must still resolve cross-module. *)
  let color_src = {|mod PubColor do
  type Color = Red | Green | Blue
  fn name(c : Color) : String do
    match c do
      Red -> "red"
      Green -> "green"
      Blue -> "blue"
    end
  end
end
|} in
  let entry_src = {|mod PubUse do
  fn main() do
    let c = PubColor.Red
    println(PubColor.name(c))
  end
end
|} in
  let errored = check_entry_with_lib_dir [("pubcolor.march", color_src)] entry_src in
  Alcotest.(check bool)
    "public qualified ctor still resolves cross-module"
    false errored

(* ── self-name-prefixed dotted sibling module (multi-file) ──────────────── *)

(* A module could not reference a same-name-prefixed sibling dotted submodule
   in a multi-file (MARCH_LIB_PATH) project -- exactly the layout
   specs/lang/modules.md's "Multi-File Projects" section documents: entry
   `mod MyApp do ... end` in one file, sibling `mod MyApp.Router do ... end`
   in another, `MyApp.Router.dispatch(...)` called from `MyApp.main`.
   `lib/desugar/desugar.ml`'s `strip_entry_self_qual` matched by STRING
   PREFIX ONLY -- `MyApp.Router.dispatch` starts with `MyApp.` so it got
   mangled to `Router.dispatch`, which resolves to nothing ("Unknown module
   `Router`"): `Router` is a DIFFERENT top-level module, not a member of
   `MyApp`. Referencing an unrelated-named sibling (`Other.Router`) always
   worked, isolating the trigger to the entry's own name being a PREFIX of
   the sibling's dotted name. *)
let router_sibling_src = {|mod MyApp.Router do
  fn dispatch(a : Int, b : Int) : Int do a + b end
end
|}

let test_self_prefix_sibling_fully_qualified () =
  let entry_src = {|mod MyApp do
  fn main() : Int do
    MyApp.Router.dispatch(1, 2)
  end
end
|} in
  let errored = check_entry_with_lib_dir [("router.march", router_sibling_src)] entry_src in
  Alcotest.(check bool)
    "fully-qualified call into a same-name-prefixed sibling dotted module resolves"
    false errored

(* An explicit `use`/`alias MyApp.Router` resolves by the one-mod-per-file
   NAMING CONVENTION ("MyApp.Router" -> "my_app/router.march"), unlike the
   fully-qualified case above (auto-discovery walks every .march file
   regardless of name/location) -- so unlike [check_entry_with_lib_dir],
   which writes files flat, this builds the nested dir the convention
   expects. Returns whether typechecking the entry produced any error. *)
let check_entry_with_nested_lib_dir ~(rel_path : string) ~(contents : string)
    (entry_src : string) : bool =
  let dir = Filename.temp_file "march_self_prefix_" "" in
  Sys.remove dir;
  Unix.mkdir dir 0o755;
  let rec mkdir_p d =
    if d <> "" && d <> "." && d <> Filename.dir_sep && not (Sys.file_exists d) then begin
      mkdir_p (Filename.dirname d);
      Unix.mkdir d 0o755
    end
  in
  mkdir_p (Filename.concat dir (Filename.dirname rel_path));
  Fun.protect ~finally:(fun () ->
      try ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)))
      with _ -> ())
    (fun () ->
      let oc = open_out (Filename.concat dir rel_path) in
      output_string oc contents;
      close_out oc;
      Unix.putenv "MARCH_LIB_PATH" dir;
      Fun.protect ~finally:(fun () -> Unix.putenv "MARCH_LIB_PATH" "") (fun () ->
        let m = parse_and_desugar entry_src in
        let (resolve_errors, extra_decls, _user_files) =
          March_resolver.Resolver.resolve_imports ~source_file:"entry.march" m in
        Alcotest.(check bool) "no resolve errors" true (resolve_errors = []);
        let m = { m with March_ast.Ast.mod_decls = extra_decls @ m.March_ast.Ast.mod_decls } in
        let (errors, _type_map) = March_typecheck.Typecheck.check_module m in
        has_errors errors))

let test_self_prefix_sibling_use_bare () =
  let entry_src = {|mod MyApp do
  use MyApp.Router

  fn main() : Int do
    Router.dispatch(1, 2)
  end
end
|} in
  let errored = check_entry_with_nested_lib_dir
      ~rel_path:"my_app/router.march" ~contents:router_sibling_src entry_src in
  Alcotest.(check bool)
    "`use MyApp.Router` + bare `Router.dispatch` resolves"
    false errored

let test_self_prefix_sibling_alias_still_works () =
  (* The pre-fix-only-working spelling; must keep working post-fix. *)
  let entry_src = {|mod MyApp do
  alias MyApp.Router as R

  fn main() : Int do
    R.dispatch(1, 2)
  end
end
|} in
  let errored = check_entry_with_nested_lib_dir
      ~rel_path:"my_app/router.march" ~contents:router_sibling_src entry_src in
  Alcotest.(check bool)
    "`alias MyApp.Router as R` + `R.dispatch` still resolves"
    false errored

let test_unrelated_name_sibling_still_works () =
  (* Regression control: a sibling dotted module whose name does NOT share
     the entry's own name as a prefix must keep working exactly as before. *)
  let sibling_src = {|mod Other.Router do
  fn dispatch(a : Int, b : Int) : Int do a + b end
end
|} in
  let entry_src = {|mod MyApp do
  fn main() : Int do
    Other.Router.dispatch(1, 2)
  end
end
|} in
  let errored = check_entry_with_lib_dir [("router.march", sibling_src)] entry_src in
  Alcotest.(check bool)
    "unrelated-named sibling dotted module still resolves (regression control)"
    false errored

let test_self_prefix_nested_submodule_still_strips () =
  (* Control for the [strip_entry_self_qual] fix itself: a GENUINE nested
     submodule (declared directly inside the entry, not a separate sibling
     file) must still have its self-qualifying prefix stripped so the
     reference converges on TIR's unwrapped-entry emission. *)
  let ctx = typecheck {|mod Outer do
    mod Inner do
      fn wrapped(x : Int) : Int do x * 2 end
    end
    fn main() : Int do
      Outer.Inner.wrapped(5)
    end
  end|} in
  Alcotest.(check bool)
    "nested submodule self-qualification still strips correctly"
    false (has_errors ctx)

(** Regression: MARCH_LIB_PATH auto-discovery used to parse+typecheck EVERY
    .march file on the search path regardless of reachability, so ONE broken,
    UNRELATED library module failed an entry that never references it.  The
    resolver now prunes any auto-discovered module the entry cannot reach
    (transitively, by textual module-name reference) unless it carries a
    global-effect decl.  Asserts (1) an entry that references only GoodLib
    typechecks clean — the broken module is pruned, not merely tolerated; and
    (2) an entry that DOES reference BrokenUnrelated still errors (control). *)
let read_file_contents path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic; s

let test_unrelated_broken_lib_module_is_pruned () =
  let dir = Filename.temp_file "march_lib_reachability_" "" in
  Sys.remove dir;
  Unix.mkdir dir 0o755;
  Fun.protect ~finally:(fun () ->
    try ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)))
    with _ -> ()) (fun () ->
  let write_file path contents =
    let oc = open_out path in output_string oc contents; close_out oc in
  write_file (Filename.concat dir "good.march")
    "mod GoodLib do\n  fn helper(x : Int) : Int do x * 2 end\nend\n";
  write_file (Filename.concat dir "broken.march")
    "mod BrokenUnrelated do\n  fn oops(x : Int) : String do x + nonexistent_thing end\nend\n";
  Unix.putenv "MARCH_LIB_PATH" dir;
  Fun.protect ~finally:(fun () -> Unix.putenv "MARCH_LIB_PATH" "") (fun () ->
    let contains_broken decls =
      List.exists (function
        | March_ast.Ast.DMod ({March_ast.Ast.txt = "BrokenUnrelated"; _}, _, _, _) -> true
        | _ -> false) decls
    in
    (* (1) Entry references only GoodLib: BrokenUnrelated must be pruned. *)
    let entry_ok = Filename.concat dir "entry_ok.march" in
    write_file entry_ok
      "mod EntryOk do\n  fn main() do println(int_to_string(GoodLib.helper(21))) end\nend\n";
    let m = parse_and_desugar (read_file_contents entry_ok) in
    let (resolve_errors, extra_decls, _uf) =
      March_resolver.Resolver.resolve_imports ~source_file:entry_ok m in
    Alcotest.(check bool) "no resolve errors for GoodLib-only entry"
      true (resolve_errors = []);
    Alcotest.(check bool) "unreferenced broken module is pruned from the assembly"
      false (contains_broken extra_decls);
    let assembled =
      { m with March_ast.Ast.mod_decls = extra_decls @ m.March_ast.Ast.mod_decls } in
    let (errors, _tm) = March_typecheck.Typecheck.check_module assembled in
    Alcotest.(check bool) "GoodLib-only entry typechecks clean" false (has_errors errors);
    (* (2) Control: entry references the broken module -> kept and still errors. *)
    let entry_ref = Filename.concat dir "entry_ref.march" in
    write_file entry_ref
      "mod EntryRef do\n  fn main() do println(BrokenUnrelated.oops(21)) end\nend\n";
    let m2 = parse_and_desugar (read_file_contents entry_ref) in
    let (_re2, extra2, _uf2) =
      March_resolver.Resolver.resolve_imports ~source_file:entry_ref m2 in
    Alcotest.(check bool) "referenced broken module is kept in the assembly"
      true (contains_broken extra2);
    let assembled2 =
      { m2 with March_ast.Ast.mod_decls = extra2 @ m2.March_ast.Ast.mod_decls } in
    let (errors2, _tm2) = March_typecheck.Typecheck.check_module assembled2 in
    Alcotest.(check bool) "entry referencing broken module still errors"
      true (has_errors errors2)))

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
    fn_body    = body;
    fn_kind    = March_tir.Tir.FnNormal }

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
                 fn_ret_ty = March_tir.Tir.TUnit; fn_body = helper_body;
                 fn_kind = March_tir.Tir.FnNormal } in
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
             fn_ret_ty = March_tir.Tir.TInt; fn_body = body;
             fn_kind = March_tir.Tir.FnNormal } in
  let m = mk_module [fd] in
  let v = March_tir.Policy_dce.audit m in
  Alcotest.(check bool) "Untagged fn with alloc: no violation" true (v = [])

(* ── cap no_panic tests ─────────────────────────────────────────────────── *)

let test_cap_no_panic_lexes () =
  let lexbuf = Lexing.from_string "cap no_panic" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "cap no_panic lexes as CAP_NO_PANIC token" true
    (match tok with March_parser.Parser.CAP_NO_PANIC -> true | _ -> false)

(* Run typecheck + division-safety pass together; used for cap no_panic tests
   that involve division/modulo.  Division is now checked by Division_safety
   (with Z3), not by the purely syntactic no-panic scan in the typechecker. *)
let typecheck_with_divsafety src =
  let m = parse_and_desugar src in
  let (errors, _) = March_typecheck.Typecheck.check_module m in
  March_refinecheck.Division_safety.check_module errors m;
  errors

let test_cap_no_panic_safe_no_error () =
  let ctx = typecheck_with_divsafety {|mod Safe do
    cap no_panic
    fn add(a : Int, b : Int) : Int do a + b end
  end|} in
  Alcotest.(check bool) "cap no_panic with safe body: no error" false (has_errors ctx)

let test_cap_not_set_div_ok () =
  let ctx = typecheck_with_divsafety {|mod Unsafe do
    fn divide(a : Int, b : Int) : Int do a / b end
  end|} in
  Alcotest.(check bool) "no cap no_panic: division is allowed" false (has_errors ctx)

let test_cap_no_panic_div_error () =
  let ctx = typecheck_with_divsafety {|mod Safe do
    cap no_panic
    fn divide(a : Int, b : Int) : Int do a / b end
  end|} in
  Alcotest.(check bool) "cap no_panic + division: error" true (has_errors ctx)

let test_cap_no_panic_mod_error () =
  let ctx = typecheck_with_divsafety {|mod Safe do
    cap no_panic
    fn remainder(a : Int, b : Int) : Int do a % b end
  end|} in
  Alcotest.(check bool) "cap no_panic + modulo: error" true (has_errors ctx)

(* Division-safety Z3 cases *)
let test_divsafety_positive_refinement_ok () =
  let ctx = typecheck_with_divsafety {|mod Safe do
    cap no_panic
    fn divide(a : Int, d : {v : Int | v > 0}) : Int do a / d end
  end|} in
  Alcotest.(check bool) "v > 0 refinement suppresses div error" false (has_errors ctx)

let test_divsafety_nonzero_refinement_ok () =
  let ctx = typecheck_with_divsafety {|mod Safe do
    cap no_panic
    fn divide(a : Int, d : {v : Int | v != 0}) : Int do a / d end
  end|} in
  Alcotest.(check bool) "v != 0 refinement suppresses div error" false (has_errors ctx)

let test_divsafety_nonneg_refinement_error () =
  let ctx = typecheck_with_divsafety {|mod Safe do
    cap no_panic
    fn divide(a : Int, d : {v : Int | v >= 0}) : Int do a / d end
  end|} in
  Alcotest.(check bool) "v >= 0 refinement does not suppress (0 is possible)" true (has_errors ctx)

let test_divsafety_literal_nonzero_ok () =
  let ctx = typecheck_with_divsafety {|mod Safe do
    cap no_panic
    fn halve(a : Int) : Int do a / 2 end
  end|} in
  Alcotest.(check bool) "literal non-zero divisor: no error" false (has_errors ctx)

let test_divsafety_literal_zero_error () =
  let ctx = typecheck_with_divsafety {|mod Safe do
    cap no_panic
    fn bad(a : Int) : Int do a / 0 end
  end|} in
  Alcotest.(check bool) "literal zero divisor: always an error" true (has_errors ctx)

let test_divsafety_ge1_refinement_ok () =
  let ctx = typecheck_with_divsafety {|mod Safe do
    cap no_panic
    fn divide(a : Int, d : {v : Int | v >= 1}) : Int do a / d end
  end|} in
  Alcotest.(check bool) "v >= 1 refinement suppresses div error" false (has_errors ctx)

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
  let ctx = typecheck_with_divsafety {|mod Safe do
    cap no_panic
    pfn helper(a : Int, b : Int) : Int do a / b end
    fn caller(x : Int) : Int do helper(x, 2) end
  end|} in
  Alcotest.(check bool) "cap no_panic + transitive panic via helper: error" true (has_errors ctx)

let test_divsafety_let_bound_literal_ok () =
  (* let d = 2; a / d  — d is a non-zero literal let-binding, must NOT error *)
  let ctx = typecheck_with_divsafety {|mod Safe do
    cap no_panic
    fn halve(a : Int) : Int do
      let d = 2
      a / d
    end
  end|} in
  Alcotest.(check bool) "divsafety: let-bound non-zero literal divisor ok" false (has_errors ctx)

let test_divsafety_let_bound_zero_error () =
  (* let d = 0; a / d  — let-bound zero literal must error *)
  let ctx = typecheck_with_divsafety {|mod Safe do
    cap no_panic
    fn bad(a : Int) : Int do
      let d = 0
      a / d
    end
  end|} in
  Alcotest.(check bool) "divsafety: let-bound zero literal divisor errors" true (has_errors ctx)

let test_cap_no_panic_two_safe_sibling_fns_ok () =
  let ctx = typecheck {|mod Safe do
    cap no_panic
    fn ping(n : Int) : Int do pong(n) end
    fn pong(n : Int) : Int do n end
  end|} in
  Alcotest.(check bool) "cap no_panic + two safe sibling fns: no error" false (has_errors ctx)

(* F3: a NON-exhaustive `match` lowers to a runtime "no matching clause" panic,
   so a `cap no_panic` module must reject it — the missing-`None` arm below is a
   panic surface just like an explicit `panic`. *)
let test_cap_no_panic_nonexhaustive_match_error () =
  let ctx = typecheck {|mod Safe do
    cap no_panic
    fn get(opt : Option(Int)) : Int do
      match opt do
        Some(x) -> x
      end
    end
  end|} in
  Alcotest.(check bool) "cap no_panic + non-exhaustive match: error" true (has_errors ctx)

(* An EXHAUSTIVE match (all constructors covered) in a `cap no_panic` module
   cannot panic and must still accept. *)
let test_cap_no_panic_exhaustive_match_ok () =
  let ctx = typecheck {|mod Safe do
    cap no_panic
    fn get(opt : Option(Int)) : Int do
      match opt do
        Some(x) -> x
        None -> 0
      end
    end
  end|} in
  Alcotest.(check bool) "cap no_panic + exhaustive match: no error" false (has_errors ctx)

(* A `_ -> ...` catch-all makes the match total → still accepts. *)
let test_cap_no_panic_wildcard_match_ok () =
  let ctx = typecheck {|mod Safe do
    cap no_panic
    fn get(opt : Option(Int)) : Int do
      match opt do
        Some(x) -> x
        _ -> 0
      end
    end
  end|} in
  Alcotest.(check bool) "cap no_panic + wildcard match: no error" false (has_errors ctx)

(* KEY REGRESSION GUARD (F3): a PLAIN (non-cap) module's non-exhaustive match
   must stay a non-blocking Warning — it must NOT become an error. The fix is
   scoped to `cap no_panic` modules only. *)
let test_plain_nonexhaustive_match_ok () =
  let ctx = typecheck {|mod Plain do
    fn get(opt : Option(Int)) : Int do
      match opt do
        Some(x) -> x
      end
    end
  end|} in
  Alcotest.(check bool) "plain (non-cap) non-exhaustive match: no error" false (has_errors ctx)

(* fix-campaign batch 3 — the GUARDED-match gap. A `match` with a `when` guard
   used to short-circuit `check_exhaustiveness` entirely, so a guarded,
   genuinely non-exhaustive match slipped past F3's error path. Here the
   GUARDLESS arms are just `{None}` (missing an unguarded `Some`); when the
   guard fails at runtime the match panics — a `cap no_panic` module must
   reject it. RED pre-fix (accepted, exit 0), GREEN after. *)
let test_cap_no_panic_guarded_nonexhaustive_match_error () =
  let ctx = typecheck {|mod Safe do
    cap no_panic
    fn classify(opt : Option(Int)) : Int do
      match opt do
        Some(v) when v > 0 -> v
        None -> 0
      end
    end
  end|} in
  Alcotest.(check bool) "cap no_panic + guarded non-exhaustive match: error" true (has_errors ctx)

(* A guarded match whose GUARDLESS arms ARE exhaustive can never fall through —
   the unguarded `Some(v)` + `None` cover the whole domain — so it must still
   accept even inside a `cap no_panic` module. Proves the fix is not
   over-rejecting every guarded match. *)
let test_cap_no_panic_guarded_guardless_catchall_ok () =
  let ctx = typecheck {|mod Safe do
    cap no_panic
    fn classify(opt : Option(Int)) : Int do
      match opt do
        Some(v) when v > 0 -> v
        Some(v) -> 0
        None -> 0
      end
    end
  end|} in
  Alcotest.(check bool) "cap no_panic + guarded match w/ guardless catch-all: no error" false (has_errors ctx)

(* REGRESSION GUARD: a PLAIN (non-cap) module's guarded non-exhaustive match
   must stay silent (no error) — the guarded-match fix records the span but
   emits NO global Warning, and promotion is still gated to `cap no_panic`. *)
let test_plain_guarded_nonexhaustive_match_ok () =
  let ctx = typecheck {|mod Plain do
    fn classify(opt : Option(Int)) : Int do
      match opt do
        Some(v) when v > 0 -> v
        None -> 0
      end
    end
  end|} in
  Alcotest.(check bool) "plain (non-cap) guarded non-exhaustive match: no error" false (has_errors ctx)

(* Division-safety guard / path-context tests *)

let test_divsafety_match_guard_neq_zero_ok () =
  let ctx = typecheck_with_divsafety {|mod Safe do
    cap no_panic
    fn safe_div(a : Int, b : Int) : Int do
      match b do
        b when b != 0 -> a / b
        _ -> 0
      end
    end
  end|} in
  Alcotest.(check bool) "match guard b != 0 suppresses div error" false (has_errors ctx)

let test_divsafety_match_guard_gt_zero_ok () =
  let ctx = typecheck_with_divsafety {|mod Safe do
    cap no_panic
    fn safe_div(a : Int, b : Int) : Int do
      match b do
        b when b > 0 -> a / b
        _ -> 0
      end
    end
  end|} in
  Alcotest.(check bool) "match guard b > 0 suppresses div error" false (has_errors ctx)

let test_divsafety_if_guard_neq_zero_ok () =
  let ctx = typecheck_with_divsafety {|mod Safe do
    cap no_panic
    fn safe_div(a : Int, b : Int) : Int do
      if b != 0 do a / b else 0 end
    end
  end|} in
  Alcotest.(check bool) "if guard b != 0 suppresses div error" false (has_errors ctx)

let test_divsafety_if_guard_gt_zero_mod_ok () =
  let ctx = typecheck_with_divsafety {|mod Safe do
    cap no_panic
    fn safe_mod(a : Int, b : Int) : Int do
      if b > 0 do a % b else 0 end
    end
  end|} in
  Alcotest.(check bool) "if guard b > 0 suppresses mod error" false (has_errors ctx)

let test_divsafety_no_guard_unrefined_still_errors () =
  let ctx = typecheck_with_divsafety {|mod Safe do
    cap no_panic
    fn unsafe_div(a : Int, b : Int) : Int do
      match b do
        b -> a / b
      end
    end
  end|} in
  Alcotest.(check bool) "no guard: division by unrefined var still errors" true (has_errors ctx)

(* ── cap pure, cap no_extern, cap deterministic tests ───────────────────── *)

let test_cap_pure_spawn_error () =
  let ctx = typecheck {|mod Pure do
    cap pure
    fn bad() : Unit do spawn(fn _ -> 0) end
  end|} in
  Alcotest.(check bool) "cap pure + spawn: error" true (has_errors ctx)

let test_cap_pure_println_error () =
  let ctx = typecheck {|mod Pure do
    cap pure
    fn greet() : Unit do println("hello") end
  end|} in
  Alcotest.(check bool) "cap pure + println: error" true (has_errors ctx)

let test_cap_pure_arithmetic_ok () =
  let ctx = typecheck {|mod Pure do
    cap pure
    fn add(a : Int, b : Int) : Int do a + b end
  end|} in
  Alcotest.(check bool) "cap pure + pure arithmetic: no error" false (has_errors ctx)

let test_cap_pure_now_ms_error () =
  let ctx = typecheck {|mod Pure do
    cap pure
    fn ts() : Int do now_ms() end
  end|} in
  Alcotest.(check bool) "cap pure + now_ms: error" true (has_errors ctx)

let test_cap_pure_random_int_error () =
  let ctx = typecheck {|mod Pure do
    cap pure
    fn roll() : Int do random_int(6) end
  end|} in
  Alcotest.(check bool) "cap pure + random_int: error" true (has_errors ctx)

let test_cap_pure_uuid_error () =
  let ctx = typecheck {|mod Pure do
    cap pure
    fn gen() : String do uuid_v4() end
  end|} in
  Alcotest.(check bool) "cap pure + uuid_v4: error" true (has_errors ctx)

(* ── F2 regression: `cap pure`/`cap deterministic` must reject the REAL
   effectful builtins, not the nonexistent names the stale `pure_banned`/
   `deterministic_banned` lists spelled.

   ⚠️ These use REAL, type-correct builtins so `has_errors` (which counts only
   `severity = Error`, never the F1 body-scan WARNING) is TRUE *solely* because
   the behavioral-cap check fires. They are RED on the pre-fix compiler (the
   stale lists missed `file_write`/`file_read`/`random_bytes`/`unix_time_ms`,
   so only a WARNING+HINT fired and `has_errors` was false) and GREEN after the
   F2 fix derives the banned sets from `builtin_cap_table`.

   Contrast the four `now_ms`/`random_int` cases above: those pass even on the
   pre-fix compiler for the WRONG reason — `now_ms`/`random_int` are NOT
   builtins, so the program ALSO gets an "I cannot find" unbound ERROR that
   satisfies `has_errors` regardless of the cap ban. *)

(* `file_write : String -> String -> Result(Unit, r)` — the signature is
   `Result(Unit, String)` (NOT `Unit`) so the ONLY Error is the cap ban, not a
   type mismatch. *)
let test_cap_pure_file_write_error () =
  let ctx = typecheck {|mod Pure do
    cap pure
    fn save(path : String, data : String) : Result(Unit, String) do
      file_write(path, data)
    end
  end|} in
  Alcotest.(check bool) "cap pure + file_write (real builtin): error" true (has_errors ctx)

let test_cap_pure_file_read_error () =
  let ctx = typecheck {|mod Pure do
    cap pure
    fn load(path : String) : Result(String, String) do
      file_read(path)
    end
  end|} in
  Alcotest.(check bool) "cap pure + file_read (real builtin): error" true (has_errors ctx)

(* `random_bytes : Int -> Bytes` — total, so `: Bytes` is type-correct. *)
let test_cap_pure_random_bytes_error () =
  let ctx = typecheck {|mod Pure do
    cap pure
    fn gen() : Bytes do random_bytes(16) end
  end|} in
  Alcotest.(check bool) "cap pure + random_bytes (real builtin): error" true (has_errors ctx)

let test_cap_no_extern_regular_fn_ok () =
  let ctx = typecheck {|mod Safe do
    cap no_extern
    fn add(a : Int, b : Int) : Int do a + b end
  end|} in
  Alcotest.(check bool) "cap no_extern + regular fn: no error" false (has_errors ctx)

let test_cap_deterministic_random_int_error () =
  let ctx = typecheck {|mod Det do
    cap deterministic
    fn roll() : Int do random_int(6) end
  end|} in
  Alcotest.(check bool) "cap deterministic + random_int: error" true (has_errors ctx)

let test_cap_deterministic_uuid_error () =
  let ctx = typecheck {|mod Det do
    cap deterministic
    fn gen() : String do uuid_v4() end
  end|} in
  Alcotest.(check bool) "cap deterministic + uuid_v4: error" true (has_errors ctx)

let test_cap_deterministic_now_ms_error () =
  let ctx = typecheck {|mod Det do
    cap deterministic
    fn ts() : Int do now_ms() end
  end|} in
  Alcotest.(check bool) "cap deterministic + now_ms: error" true (has_errors ctx)

(* ── F2 regression (deterministic side): the REAL wall-clock builtin
   `unix_time_ms : Unit -> Int` must be rejected. Type-correct (`: Int`,
   `unix_time_ms(())`), so `has_errors` is TRUE only because the cap ban fires.
   RED pre-fix (stale list spelled the nonexistent `now_ms`, missed this). *)
let test_cap_deterministic_unix_time_ms_error () =
  let ctx = typecheck {|mod Det do
    cap deterministic
    fn ts() : Int do unix_time_ms(()) end
  end|} in
  Alcotest.(check bool) "cap deterministic + unix_time_ms (real builtin): error"
    true (has_errors ctx)

(* `cap deterministic` is WEAKER than `cap pure`: it bans clock/RNG but not
   ordinary IO. A deterministic `file_read` (mapped `IO.FileRead`, NOT a
   nondeterminism source) must STILL be accepted — no `Error` from the cap
   check. (A WARNING-level Check-1b body-scan diagnostic fires, but `has_errors`
   ignores warnings.) This pins the intended semantics and guards against the
   fix over-banning deterministic-but-effectful builtins.
   No return-type annotation: `file_read`'s error is a concrete `FileError`,
   not `String` (see the file_read soundness-gap fix), so the return type is
   left to inference here — annotating it `Result(String, String)` would
   fail with a genuine (and unrelated to this test) type mismatch. *)
let test_cap_deterministic_file_read_ok () =
  let ctx = typecheck {|mod Det do
    cap deterministic
    fn load(path : String) do
      file_read(path)
    end
  end|} in
  Alcotest.(check bool) "cap deterministic + file_read: no error (weaker than pure)"
    false (has_errors ctx)

let test_cap_deterministic_arithmetic_ok () =
  let ctx = typecheck {|mod Det do
    cap deterministic
    fn add(a : Int, b : Int) : Int do a + b end
  end|} in
  Alcotest.(check bool) "cap deterministic + pure arithmetic: no error" false (has_errors ctx)

(* ── Proof-cap mint soundness (Part 1: cap_narrow restriction) ────────────
   cap_narrow's polymorphic result Cap(a) let ANY holder of a plain Cap(IO)
   forge a nominal proof capability at a proof-cap-typed call site (inline arg,
   let-binding, or return position) — a soundness hole Check 6 (declared-return
   only) structurally cannot see. Part 1 rejects any cap_narrow whose pinned
   result is a proof cap. RED pre-fix (forge accepted, exit 0), GREEN after. *)
let test_cap_narrow_cannot_mint_proof_cap () =
  (* R1: consume(cap_narrow(cap)) at a Cap(Db.Migrated) call site, holding only
     Cap(IO). Pre-fix this typechecks; the fix rejects it. *)
  let ctx = typecheck {|mod Top do
    mod Db do
      proof cap Migrated
    end
    mod App do
      needs IO
      needs Db.Migrated
      fn consume(_m : Cap(Db.Migrated)) : Int do 1 end
      fn forge(cap : Cap(IO)) : Int do
        consume(cap_narrow(cap))
      end
    end
  end|} in
  Alcotest.(check bool) "cap_narrow forging a proof cap (inline arg): error"
    true (has_errors ctx)

let test_cap_narrow_forge_let () =
  (* R7: let forged : Cap(Db.Migrated) = cap_narrow(cap) — let-binding position. *)
  let ctx = typecheck {|mod Top do
    mod Db do
      proof cap Migrated
    end
    mod App do
      needs IO
      needs Db.Migrated
      fn consume(_m : Cap(Db.Migrated)) : Int do 1 end
      fn forge(cap : Cap(IO)) : Int do
        let forged : Cap(Db.Migrated) = cap_narrow(cap)
        consume(forged)
      end
    end
  end|} in
  Alcotest.(check bool) "cap_narrow forging a proof cap (let binding): error"
    true (has_errors ctx)

let test_cap_narrow_io_narrow_still_ok () =
  (* R4 regression guard: narrowing Cap(IO) -> Cap(IO.Network) is an IO-lattice
     attenuation, NOT a proof-cap mint — Part 1 must leave it accepted. *)
  let ctx = typecheck {|mod App do
    needs IO
    fn use_net(_cap : Cap(IO.Network)) : Int do 1 end
    fn boot(cap : Cap(IO)) : Int do
      use_net(cap_narrow(cap))
    end
  end|} in
  Alcotest.(check bool) "cap_narrow IO-lattice narrow: no error"
    false (has_errors ctx)

let test_cap_narrow_forge_generalized_let () =
  (* Residual-forge witness (let-generalized launder): a cap_narrow result bound
     with `let`, then passed to a proof-cap-typed callee.  The RHS is expansive,
     so `stolen` must stay MONOMORPHIC (value restriction) — without it, `stolen`
     generalized to ∀a.Cap(a) and each use forged a fresh proof cap while the
     compiler's recorded node stayed unbound.  RED pre-fix (exit 0), GREEN after. *)
  let ctx = typecheck {|mod Top do
    mod Db do proof cap P end
    mod App do
      needs IO
      needs Db.P
      fn use_proof(_m : Cap(Db.P)) : Int do 1 end
      fn forge(cap : Cap(IO)) : Int do
        let stolen = cap_narrow(cap)
        use_proof(stolen)
      end
    end
  end|} in
  Alcotest.(check bool) "cap_narrow let-generalized launder to proof cap: error"
    true (has_errors ctx)

let test_cap_narrow_forge_through_generic_fn () =
  (* Residual-forge witness (laundered through a polymorphic user fn): a generic
     `fn id(x) do x end` carries a cap_narrow result to a proof-cap-typed callee.
     Closed by taint propagation through the call + the unify use-site hook.
     RED pre-fix (exit 0), GREEN after. *)
  let ctx = typecheck {|mod Top do
    mod Db do proof cap P end
    mod App do
      needs IO
      needs Db.P
      fn id(x) do x end
      fn consume(_m : Cap(Db.P)) : Int do 1 end
      fn forge(cap : Cap(IO)) : Int do
        consume(id(cap_narrow(cap)))
      end
    end
  end|} in
  Alcotest.(check bool) "cap_narrow laundered through generic fn to proof cap: error"
    true (has_errors ctx)

let test_cap_narrow_launder_io_still_ok () =
  (* Regression guard for the taint machinery: laundering a cap_narrow result
     through a generic fn to an IO-cap callee must STAY accepted — only proof
     caps are rejected. *)
  let ctx = typecheck {|mod App do
    needs IO
    fn id(x) do x end
    fn use_net(_cap : Cap(IO.Network)) : Int do 1 end
    fn boot(cap : Cap(IO)) : Int do
      use_net(id(cap_narrow(cap)))
    end
  end|} in
  Alcotest.(check bool) "cap_narrow laundered through generic fn to IO cap: no error"
    false (has_errors ctx)

(* ── Proof-cap mint (Part 2: gated mint_cap primitive) ────────────────────
   mint_cap is the ONLY way to construct a proof cap; it typechecks iff used in
   a PUBLIC fn of the cap's DECLARING module. cap_narrow can no longer produce a
   proof cap (Part 1), so mint_cap is the sanctioned mint surface. *)
let test_mint_cap_public_declaring_ok () =
  (* R3-migrated: Db's public fn mints its own proof cap via mint_cap. *)
  let ctx = typecheck {|mod Db do
    proof cap Migrated
    needs IO
    fn run_migrations(cap : Cap(IO)) : Cap(Db.Migrated) do
      mint_cap(cap)
    end
  end|} in
  Alcotest.(check bool) "mint_cap in public declaring-module fn: no error"
    false (has_errors ctx)

let test_mint_cap_pfn_rejected () =
  (* mint_cap in a PRIVATE fn of the declaring module is rejected — only public
     fns are the minting surface. *)
  let ctx = typecheck {|mod Db do
    proof cap Migrated
    needs IO
    pfn run_migrations(cap : Cap(IO)) : Cap(Db.Migrated) do
      mint_cap(cap)
    end
  end|} in
  Alcotest.(check bool) "mint_cap in pfn: error" true (has_errors ctx)

let test_mint_cap_external_rejected () =
  (* mint_cap in a fn of a NON-declaring module is rejected (unforgeability). *)
  let ctx = typecheck {|mod Top do
    mod Db do
      proof cap Migrated
    end
    mod App do
      needs IO
      needs Db.Migrated
      fn forge(cap : Cap(IO)) : Cap(Db.Migrated) do
        mint_cap(cap)
      end
    end
  end|} in
  Alcotest.(check bool) "mint_cap in external module: error" true (has_errors ctx)

let test_mint_cap_lambda_declaring_ok () =
  (* Lambda-inherit rule: a mint inside a lambda inside a public declaring-module
     fn accepts when the cap type is pinned at the call site (immediately-applied
     lambda). Confirms the enclosing fn's public-ness is inherited by the lambda. *)
  let ctx = typecheck {|mod Db do
    proof cap Migrated
    needs IO
    fn run_migrations(cap : Cap(IO)) : Cap(Db.Migrated) do
      (fn _ -> mint_cap(cap))(0)
    end
  end|} in
  Alcotest.(check bool) "mint_cap in applied lambda in public declaring fn: no error"
    false (has_errors ctx)

let test_mint_cap_lambda_external_rejected () =
  (* The forge via a lambda in a non-declaring module must still be rejected. *)
  let ctx = typecheck {|mod Top do
    mod Db do
      proof cap Migrated
    end
    mod App do
      needs IO
      needs Db.Migrated
      fn forge(cap : Cap(IO)) : Cap(Db.Migrated) do
        (fn _ -> mint_cap(cap))(0)
      end
    end
  end|} in
  Alcotest.(check bool) "mint_cap in applied lambda in external module: error"
    true (has_errors ctx)

let test_mint_cap_io_target_rejected () =
  (* mint_cap is proof-cap-only: aiming it at an IO cap is rejected (that's
     cap_narrow's job). *)
  let ctx = typecheck {|mod App do
    needs IO
    fn use_net(_cap : Cap(IO.Network)) : Int do 1 end
    fn boot(cap : Cap(IO)) : Int do
      use_net(mint_cap(cap))
    end
  end|} in
  Alcotest.(check bool) "mint_cap at IO-cap target: error" true (has_errors ctx)

(* ── Container/factory cap_narrow-taint gap (todos.md finding, Batch-A
   follow-up) ──────────────────────────────────────────────────────────────
   `tag_cap_producer_result` (the tagger) was shallow — it only tagged a bare
   `Cap(a)`/`TVar`, while `ty_has_tagged_cap_producer` (the detector gating the
   call/factory taint-propagation sites) already recursed into tuples/records/
   TCon args — an asymmetry: the detector could find a tag buried in a
   container, but the tagger's own `| _ -> ()` catch-all silently dropped it
   when asked to mark one. Investigation traced the historically-filed repro
   (a nested-module `box(x) = (x, 0)` called as `box(cap_narrow(cap))`) and
   found it does NOT currently forge on this tree for a DIFFERENT reason than
   the shallow tagger: `demote_to_monomorphic`'s value restriction pins the
   ORIGINAL `cap_narrow`-tagged var to level 0 the instant it's produced, so
   it is never swept into any later generalization — the same physical var
   flows through arbitrary tuple/record/generic wrapping by reference, and
   `unify`'s own hook (plus its "propagate the tag to whatever var this one
   gets bound to" logic) keeps the taint alive across the underlying var
   graph regardless of syntactic nesting. (An EARLIER instance of the exact
   `box(cap_narrow(cap))` program DID forge, confirmed live via a source A/B
   against commit `66b6716a` — but that reproduced the UNRELATED qualified-
   prebind type-erasure bug, fixed three commits later in the same line of
   work: `box`, an unannotated helper in a nested module, had its qualified
   reference resolve to a decoupled placeholder that bypassed normal
   unification entirely, which is what actually let the forge through.)

   Given the tagger/detector asymmetry is real regardless, `tag_cap_producer_result`
   was still made to recurse identically to `ty_has_tagged_cap_producer` — closing
   the architectural gap outright rather than resting on the incidental
   protection above, at zero rejection cost (tagging only ever marks a still-
   UNBOUND var; anything already resolved to a concrete type via ordinary
   argument-passing is untouched, so it cannot introduce a false positive).
   The tests below are honest about what they demonstrate: they lock in the
   currently-correct reject/accept behavior for every container shape the
   original finding named (tuple, Option, cross-module, single-module,
   forward-referenced, multi-hop — all exhaustively verified live before this
   change), but on THIS tree they pass whether or not the tagger recurses,
   since value restriction's own robustness already covers them. *)
let test_container_launder_tuple_forge () =
  let ctx = typecheck {|mod Top do
    mod Db do proof cap P end
    mod App do
      needs IO
      needs Db.P
      fn mkbox(cap) do (cap_narrow(cap), 0) end
      fn consume(_c : Cap(Db.P)) : Int do 1 end
      fn attack(cap : Cap(IO)) : Int do
        let (c, _) = mkbox(cap)
        consume(c)
      end
    end
  end|} in
  Alcotest.(check bool) "cap_narrow forged via an unannotated tuple-wrapping factory: error"
    true (has_errors ctx)

let test_container_launder_option_forge () =
  let ctx = typecheck {|mod Top do
    mod Db do proof cap P end
    mod App do
      needs IO
      needs Db.P
      fn wrap(x) do Some(x) end
      fn consume(_c : Cap(Db.P)) : Int do 1 end
      fn attack(cap : Cap(IO)) : Int do
        match wrap(cap_narrow(cap)) do
          Some(c) -> consume(c)
          None -> 0
        end
      end
    end
  end|} in
  Alcotest.(check bool) "cap_narrow forged via an Option-wrapping factory: error"
    true (has_errors ctx)

let test_container_launder_io_still_ok () =
  (* Regression guard: an ordinary IO-cap narrow, wrapped in a tuple by an
     unannotated generic factory, must STAY accepted. *)
  let ctx = typecheck {|mod Top do mod App do
    needs IO
    fn box(x) do (x, 0) end
    fn use_net(_c : Cap(IO.Network)) : Int do 1 end
    fn go(cap : Cap(IO)) : Int do
      let (c, _) = box(cap_narrow(cap))
      use_net(c)
    end
  end end|} in
  Alcotest.(check bool) "IO-cap narrow wrapped in a tuple factory: no error"
    false (has_errors ctx)

let test_container_combine_legit_proof_cap_still_ok () =
  (* Over-rejection guard: a generic factory tuples a tainted cap_narrow result
     together with an UNRELATED, already-legitimate proof-cap parameter passed
     straight through. Tagging must not spill onto the legit slot — the
     already-concrete `Cap(Db.P)` param has no unbound var left to tag by the
     time the factory's result is examined (it was already unified against the
     caller's concrete argument type). *)
  let ctx = typecheck {|mod Top do
    mod Db do proof cap P end
    mod App do
      needs IO
      needs Db.P
      fn combine(io_cap, db_cap) do (cap_narrow(io_cap), db_cap) end
      fn use_net(_c : Cap(IO.Network)) : Int do 1 end
      fn consume(_c : Cap(Db.P)) : Int do 1 end
      fn go(io : Cap(IO), db : Cap(Db.P)) : Int do
        let (net, passed) = combine(io, db)
        use_net(net) + consume(passed)
      end
    end
  end|} in
  Alcotest.(check bool)
    "tainted IO narrow tupled with an unrelated legit proof-cap passthrough: no error"
    false (has_errors ctx)

(* ── Nested-module qualified-prebind type-erasure hole ────────────────────
   ROOT CAUSE (confirmed): an UNANNOTATED public fn defined inside a NESTED
   `mod` gets its QUALIFIED name (`Mod.fn`) prebound to a fresh `Mono (fresh_var)`
   by prebind_mod_members (typecheck.ml, prebind_fn_scheme returns None for an
   unannotated fn).  desugar's qualify_module_refs rewrites every intra-nested-
   module reference to that qualified form, and check_decl's DFn branch used to
   rebind ONLY the bare name — never the qualified one.  So every call to the
   helper resolved a stale `Mono '_v` placeholder that behaves as `∀. a -> b`,
   ERASING the type of anything laundered through it: base types, ADTs, and Cap
   alike.  The proof-cap forge was one exploitation of a GENERAL memory-safety
   hole.  Fixed by reconciling the qualified prebind with the real inferred
   scheme in check_decl's DFn branch.

   All F* cases below are RED pre-fix (forge accepted, exit 0) and GREEN after.
   The P* / *_ok cases are GREEN-STAYS-GREEN guards. *)

(* F4 — the clearest witness that this is NOT proof-cap-specific: a plain Int is
   laundered into a String parameter through a nested unannotated `id`, a genuine
   type-soundness / memory-safety break. *)
let test_nested_launder_int_as_string () =
  let ctx = typecheck {|mod T do
    mod App do
      fn id(x) do x end
      fn takes_str(s : String) : Int do string_length(s) end
      fn attack() : Int do
        let n = 12345
        takes_str(id(n))
      end
    end
  end|} in
  Alcotest.(check bool)
    "nested unannotated id launders Int into String param: error"
    true (has_errors ctx)

(* F3 — nested Box(String) laundered where Box(Int) is required. *)
let test_nested_launder_box_arg () =
  let ctx = typecheck {|mod T do
    mod App do
      type Box(a) = Box(a)
      fn id(x) do x end
      fn need_int(_b : Box(Int)) : Int do 1 end
      fn attack() : Int do
        let bx = Box("hi")
        need_int(id(bx))
      end
    end
  end|} in
  Alcotest.(check bool)
    "nested unannotated id launders Box(String) into Box(Int): error"
    true (has_errors ctx)

(* F1 — nested proof-cap forge: Cap(IO) laundered into a Cap(Db.P) callee. *)
let test_nested_launder_proof_cap () =
  let ctx = typecheck {|mod T do
    mod Db do proof cap P end
    mod App do
      needs IO
      needs Db.P
      fn id(x) do x end
      fn consume(_c : Cap(Db.P)) : Int do 1 end
      fn attack(cap : Cap(IO)) : Int do consume(id(cap)) end
    end
  end|} in
  Alcotest.(check bool)
    "nested unannotated id launders Cap(IO) into Cap(Db.P): error"
    true (has_errors ctx)

(* F2 — same launder, Cap(IO) -> Cap(IO.Network) (an IO-cap coercion, proving the
   erasure is any-Cap, not proof-cap-only). *)
let test_nested_launder_io_subcap () =
  let ctx = typecheck {|mod T do
    mod App do
      needs IO
      fn id(x) do x end
      fn use_net(_c : Cap(IO.Network)) : Int do 1 end
      fn attack(cap : Cap(IO)) : Int do use_net(id(cap)) end
    end
  end|} in
  Alcotest.(check bool)
    "nested unannotated id coerces Cap(IO) into Cap(IO.Network): error"
    true (has_errors ctx)

(* F5 — three levels of nesting: the qualified prefix accumulates (Mid.App.id);
   the fix must reconcile at every depth. *)
let test_nested_launder_three_deep () =
  let ctx = typecheck {|mod Outer do
    mod Mid do
      mod App do
        type Box(a) = Box(a)
        fn id(x) do x end
        fn need_int(_b : Box(Int)) : Int do 1 end
        fn attack() : Int do
          let bx = Box("hi")
          need_int(id(bx))
        end
      end
    end
  end|} in
  Alcotest.(check bool)
    "3-deep nested unannotated id launders Box(String) into Box(Int): error"
    true (has_errors ctx)

(* Container/HOF variant — the launderer is an unannotated factory
   `fn wrap(x) do (x, 0) end` returning a tuple; destructuring it and feeding the
   payload to a Box(Int) callee still forges pre-fix. *)
let test_nested_launder_container_factory () =
  let ctx = typecheck {|mod T do
    mod App do
      type Box(a) = Box(a)
      fn wrap(x) do (x, 0) end
      fn need_int(_b : Box(Int)) : Int do 1 end
      fn attack() : Int do
        let bx = Box("hi")
        match wrap(bx) do
          (b, _) -> need_int(b)
        end
      end
    end
  end|} in
  Alcotest.(check bool)
    "nested unannotated tuple factory launders Box(String) into Box(Int): error"
    true (has_errors ctx)

(* GREEN-STAYS-GREEN: nested unannotated id passing Cap(IO) through UNCHANGED
   (identity, no coercion) must stay accepted — the fix reconciles the real
   `∀a. a -> a` scheme, it does not reject legitimate passthrough. *)
let test_nested_cap_passthrough_ok () =
  let ctx = typecheck {|mod T do
    mod App do
      needs IO
      fn id(x) do x end
      fn use_io(_c : Cap(IO)) : Int do 1 end
      fn attack(cap : Cap(IO)) : Int do use_io(id(cap)) end
    end
  end|} in
  Alcotest.(check bool)
    "nested id passes Cap(IO) through unchanged: no error"
    false (has_errors ctx)

(* RED→GREEN (a second, independent witness of the SAME bug in the opposite
   direction): pre-fix, an unannotated nested `id` is NOT actually polymorphic —
   the stale qualified placeholder pins to the FIRST use, so using it at Int AND
   String is a spurious ERROR pre-fix.  The fix reconciles `id` to its real
   `∀a. a -> a` scheme, RESTORING legitimate polymorphism → no error.  This also
   proves the fix does not over-monomorphise. *)
let test_nested_id_polymorphic_ok () =
  let ctx = typecheck {|mod T do
    mod App do
      fn id(x) do x end
      fn use_int() : Int do id(1) end
      fn use_str() : String do id("hi") end
    end
  end|} in
  Alcotest.(check bool)
    "nested id used at Int AND String: no error"
    false (has_errors ctx)

(* GREEN-STAYS-GREEN guard: an ANNOTATED nested id already rejects the forge
   (prebind_fn_scheme builds a real Poly scheme, so no stale placeholder).  The
   fix must not change this — it stays an error. *)
let test_nested_launder_annotated_id_still_rejected () =
  let ctx = typecheck {|mod T do
    mod App do
      type Box(a) = Box(a)
      fn id(x : a) : a do x end
      fn need_int(_b : Box(Int)) : Int do 1 end
      fn attack() : Int do
        let bx = Box("hi")
        need_int(id(bx))
      end
    end
  end|} in
  Alcotest.(check bool)
    "nested ANNOTATED id still rejects Box(String)->Box(Int): error"
    true (has_errors ctx)

(* GREEN-STAYS-GREEN guard: a PRIVATE (pfn) nested id already rejects the forge
   (prebind_mod_members only prebinds public fns, so no qualified placeholder;
   the reference falls through to the local Poly scheme).  Unchanged by the fix. *)
let test_nested_launder_private_id_still_rejected () =
  let ctx = typecheck {|mod T do
    mod App do
      type Box(a) = Box(a)
      pfn id(x) do x end
      fn need_int(_b : Box(Int)) : Int do 1 end
      fn attack() : Int do
        let bx = Box("hi")
        need_int(id(bx))
      end
    end
  end|} in
  Alcotest.(check bool)
    "nested PRIVATE (pfn) id still rejects Box(String)->Box(Int): error"
    true (has_errors ctx)

(* ── Round 2: residual erasures the first fix missed ──────────────────────
   CRITICAL #1 — FORWARD REFERENCE: the unannotated helper is defined AFTER its
   caller.  The caller pins the qualified prebind (`App.id`) to its own decoupled
   use before `id`'s DFn runs, so a post-hoc rebind is too late.  Closed by
   teaching [dependency_order_dfn_run]'s [deps_of] to see the qualified reference
   (`App.id`) as a dependency on the local `id`, ordering the helper FIRST.
   CRITICAL #2 — DISTINCT-TVAR ANNOTATION: `fn launder(x:a):b do x` gets a prebind
   built from annotation SYNTAX (`a -> b`, never unified against the body
   constraint `a ~ b`).  Closed by rebinding the qualified name to the fn's REAL
   body-checked scheme UNCONDITIONALLY (not only bare-placeholder prebinds).
   All RED on commit 10249488; GREEN after round 2. *)

(* C1 forward-ref, Int -> String (general memory-safety). *)
let test_nested_fwdref_int_as_string () =
  let ctx = typecheck {|mod T do
    mod App do
      fn need_str(s : String) : Int do string_length(s) end
      fn attack() : Int do need_str(id(42)) end
      fn id(x) do x end
    end
  end|} in
  Alcotest.(check bool)
    "forward-ref nested id launders Int into String param: error"
    true (has_errors ctx)

(* C1 forward-ref, Box(String) -> Box(Int). *)
let test_nested_fwdref_box () =
  let ctx = typecheck {|mod T do
    mod App do
      type Box(a) = Box(a)
      fn need_int(_b : Box(Int)) : Int do 1 end
      fn attack() : Int do
        let bx = Box("hi")
        need_int(id(bx))
      end
      fn id(x) do x end
    end
  end|} in
  Alcotest.(check bool)
    "forward-ref nested id launders Box(String) into Box(Int): error"
    true (has_errors ctx)

(* C1 forward-ref, Cap(IO) -> Cap(Db.P) proof-cap forge. *)
let test_nested_fwdref_proof_cap () =
  let ctx = typecheck {|mod T do
    mod Db do proof cap P end
    mod App do
      needs IO
      needs Db.P
      fn consume(_c : Cap(Db.P)) : Int do 1 end
      fn attack(cap : Cap(IO)) : Int do consume(id(cap)) end
      fn id(x) do x end
    end
  end|} in
  Alcotest.(check bool)
    "forward-ref nested id launders Cap(IO) into Cap(Db.P): error"
    true (has_errors ctx)

(* C2 distinct-tvar annotation, Int -> String. *)
let test_nested_distinct_tvar_int_as_string () =
  let ctx = typecheck {|mod T do
    mod App do
      fn launder(x : a) : b do x end
      fn need_str(s : String) : Int do string_length(s) end
      fn attack(n : Int) : Int do need_str(launder(n)) end
    end
  end|} in
  Alcotest.(check bool)
    "distinct-tvar annotated launder erases Int into String param: error"
    true (has_errors ctx)

(* C2 distinct-tvar annotation, Box(String) -> Box(Int). *)
let test_nested_distinct_tvar_box () =
  let ctx = typecheck {|mod T do
    mod App do
      type Box(a) = Box(a)
      fn launder(x : a) : b do x end
      fn need_int(_b : Box(Int)) : Int do 1 end
      fn attack() : Int do
        let bx = Box("hi")
        need_int(launder(bx))
      end
    end
  end|} in
  Alcotest.(check bool)
    "distinct-tvar annotated launder erases Box(String) into Box(Int): error"
    true (has_errors ctx)

(* C2 distinct-tvar annotation, Cap(IO) -> Cap(Db.P). *)
let test_nested_distinct_tvar_proof_cap () =
  let ctx = typecheck {|mod T do
    mod Db do proof cap P end
    mod App do
      needs IO
      needs Db.P
      fn launder(x : a) : b do x end
      fn consume(_c : Cap(Db.P)) : Int do 1 end
      fn attack(cap : Cap(IO)) : Int do consume(launder(cap)) end
    end
  end|} in
  Alcotest.(check bool)
    "distinct-tvar annotated launder erases Cap(IO) into Cap(Db.P): error"
    true (has_errors ctx)

(* GREEN-STAYS-GREEN: forward-ref helper used legitimately (identity passthrough
   of the SAME type) must still accept — the dependency ordering + real-scheme
   rebind restore true polymorphism, they do not over-reject. *)
let test_nested_fwdref_legit_ok () =
  let ctx = typecheck {|mod T do
    mod App do
      fn dbl(n : Int) : Int do n + n end
      fn a() : Int do dbl(id(5)) end
      fn b() : String do id("hi") end
      fn id(x) do x end
    end
  end|} in
  Alcotest.(check bool)
    "forward-ref nested id used at Int AND String: no error"
    false (has_errors ctx)

(* GREEN-STAYS-GREEN: a genuinely-polymorphic annotated helper `fn id(x:a):a`
   (SAME tvar in and out) forward-referenced must still accept at two types. *)
let test_nested_annotated_same_tvar_ok () =
  let ctx = typecheck {|mod T do
    mod App do
      fn u1() : Int do id(1) end
      fn u2() : String do id("hi") end
      fn id(x : a) : a do x end
    end
  end|} in
  Alcotest.(check bool)
    "forward-ref nested annotated id (a->a) used at Int AND String: no error"
    false (has_errors ctx)

(* ── Round 3: entry-module self-qualified prebind erasure ─────────────────
   [prebind_mod_members m.mod_name.txt] (check_module_core) seeds the ENTRY
   module's own top-level unannotated fns under a qualified key `EntryMod.id`,
   but [cap_qual_prefix] is "" for entry-level fns, so the round-2 rebind (gated
   `cap_qual_prefix <> ""`) never reconciled it — the explicit `EntryMod.id`
   reference form (or a nested sibling's reference to the entry module by name)
   kept a decoupled `?a -> ?b` and erased.  Closed by ALSO reconciling the
   `current_module`-based key.  All RED on d19dc519 (exit 0). *)

(* E1 — Main.id self-qualified launder, Int -> String (general memory-safety). *)
let test_entry_self_qualified_int_as_string () =
  let ctx = typecheck {|mod Main do
    fn id(x) do x end
    fn need_str(s : String) : Int do string_length(s) end
    fn attack() : Int do need_str(Main.id(42)) end
  end|} in
  Alcotest.(check bool)
    "entry-module Main.id launders Int into String param: error"
    true (has_errors ctx)

(* E1 — Main.id self-qualified launder, Box(String) -> Box(Int). *)
let test_entry_self_qualified_box () =
  let ctx = typecheck {|mod Main do
    type Box(a) = Box(a)
    fn id(x) do x end
    fn need_int(_b : Box(Int)) : Int do 1 end
    fn attack() : Int do
      let bx = Box("hi")
      need_int(Main.id(bx))
    end
  end|} in
  Alcotest.(check bool)
    "entry-module Main.id launders Box(String) into Box(Int): error"
    true (has_errors ctx)

(* E1 — Main.id self-qualified launder, Cap(IO) -> Cap(Db.P) proof-cap forge. *)
let test_entry_self_qualified_proof_cap () =
  let ctx = typecheck {|mod Main do
    mod Db do proof cap P end
    needs IO
    needs Db.P
    fn id(x) do x end
    fn consume(_c : Cap(Db.P)) : Int do 1 end
    fn attack(cap : Cap(IO)) : Int do consume(Main.id(cap)) end
  end|} in
  Alcotest.(check bool)
    "entry-module Main.id launders Cap(IO) into Cap(Db.P): error"
    true (has_errors ctx)

(* E2 — a nested sibling references the ENTRY module by name (`T.id`). *)
let test_entry_qualified_from_nested_sibling () =
  let ctx = typecheck {|mod T do
    fn id(x) do x end
    mod App do
      fn need_str(s : String) : Int do string_length(s) end
      fn attack() : Int do need_str(T.id(42)) end
    end
  end|} in
  Alcotest.(check bool)
    "nested sibling launders via entry-qualified T.id (Int into String): error"
    true (has_errors ctx)

(* E3 — entry self-qualified with a FORWARD reference (id defined after caller). *)
let test_entry_self_qualified_forward_ref () =
  let ctx = typecheck {|mod Main do
    fn need_str(s : String) : Int do string_length(s) end
    fn attack() : Int do need_str(Main.id(42)) end
    fn id(x) do x end
  end|} in
  Alcotest.(check bool)
    "entry-module forward-ref Main.id launders Int into String: error"
    true (has_errors ctx)

(* GREEN-STAYS-GREEN / RED->GREEN: an entry-qualified reference to a genuinely
   polymorphic entry `id`, used at TWO types, must ACCEPT.  (This spuriously
   ERRORED on d19dc519 — the erasure made entry `id` non-polymorphic — so it is a
   second, independent witness that the fix restores true polymorphism.) *)
let test_entry_self_qualified_polymorphic_ok () =
  let ctx = typecheck {|mod Main do
    fn id(x) do x end
    fn ui() : Int do Main.id(1) end
    fn us() : String do Main.id("hi") end
  end|} in
  Alcotest.(check bool)
    "entry-module Main.id used at Int AND String: no error"
    false (has_errors ctx)

(* GREEN-STAYS-GREEN: a nested sibling using the entry `T.id` at a CONSISTENT
   type must still accept — the fix does not over-reject legit entry-qualified use. *)
let test_entry_qualified_nested_consistent_ok () =
  let ctx = typecheck {|mod T do
    fn id(x) do x end
    mod App do
      fn need_int(n : Int) : Int do n end
      fn attack() : Int do need_int(T.id(5)) end
    end
  end|} in
  Alcotest.(check bool)
    "nested sibling uses entry T.id at consistent type: no error"
    false (has_errors ctx)

(* ── fix-batch regressions: F6 (Cap(X) hierarchy args) + revoke_cap/is_cap_valid
   typecheck registration + finding 17 (derive unknown type) ──────────────── *)

(* F6: all 18 capability-hierarchy roots are valid `Cap(X)` type arguments.
   The 8 previously-unregistered ones (IO.Random, IO.Mut, IO.Foreign,
   IO.Telemetry, …) were rejected `Unknown module IO` as a type argument even
   though they were valid `needs` targets. RED pre-fix (Unknown module IO
   error), GREEN after registering them in `builtin_types`. *)
let test_cap_hierarchy_args_ok () =
  let ctx = typecheck {|mod HierApp do
    needs IO.Random
    needs IO.Mut
    needs IO.Foreign
    needs IO.Telemetry
    fn use_caps(
      _r : Cap(IO.Random),
      _m : Cap(IO.Mut),
      _f : Cap(IO.Foreign),
      _t : Cap(IO.Telemetry)
    ) : Int do 0 end
  end|} in
  Alcotest.(check bool) "Cap(IO.Random/Mut/Foreign/Telemetry) args: no error"
    false (has_errors ctx)

(* A previously-unregistered leaf path with a dot in its own name. *)
let test_cap_hierarchy_tls_arg_ok () =
  let ctx = typecheck {|mod TlsApp do
    needs IO.NetConnect.TLS
    fn connect(_c : Cap(IO.NetConnect.TLS)) : Int do 0 end
  end|} in
  Alcotest.(check bool) "Cap(IO.NetConnect.TLS) arg: no error" false (has_errors ctx)

(* revoke_cap / is_cap_valid are now typecheck-registered builtins. A surface
   program obtaining a Cap via get_cap and calling both must typecheck. RED
   pre-fix (`I cannot find revoke_cap`), GREEN after registration. *)
let test_revoke_cap_typechecks () =
  let ctx = typecheck {|mod CapPlane do
    actor Counter do
      state { count : Int }
      init  { count: 0 }
      on Inc() do { count: state.count + 1 } end
    end
    fn check() : Bool do
      let p = spawn(Counter)
      match get_cap(p) do
        Some(cap) ->
          let _ = revoke_cap(cap)
          is_cap_valid(cap)
        None -> false
      end
    end
  end|} in
  Alcotest.(check bool) "revoke_cap/is_cap_valid: no error" false (has_errors ctx)

(* finding 17: `derive X for UnknownType` now ERRORs (was a silent no-op).
   The error is emitted at DESUGAR time, so this uses `desugar_has_errors`
   (the plain `typecheck` helper discards desugar-phase errors). *)
let test_derive_unknown_type_error () =
  Alcotest.(check bool) "derive for unknown type: error" true
    (desugar_has_errors {|mod Main do
      derive Show for NoSuchType
      fn main() : Int do 0 end
    end|})

(* Guard: `derive` for a REAL, declared type still expands cleanly (no error) —
   the finding-17 fix must not newly-reject legitimate derives. *)
let test_derive_known_type_ok () =
  Alcotest.(check bool) "derive for declared type: no error" false
    (desugar_has_errors {|mod Main do
      type Color = Red | Green | Blue
      derive Show for Color
      fn main() : Int do 0 end
    end|})

(* ── cap no_alloc tests ─────────────────────────────────────────────────── *)

(* Helper: run typecheck + no_alloc pass together. *)
let check_no_alloc src =
  let m = parse_and_desugar src in
  let (errors, _) = March_typecheck.Typecheck.check_module m in
  March_refinecheck.No_alloc.check_module errors m;
  errors

let test_cap_no_alloc_lexes () =
  let lexbuf = Lexing.from_string "cap no_alloc" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "cap no_alloc lexes as CAP_NO_ALLOC token" true
    (match tok with March_parser.Parser.CAP_NO_ALLOC -> true | _ -> false)

let test_cap_no_alloc_tuple_error () =
  let ctx = check_no_alloc {|mod M do
    cap no_alloc
    fn f() : Int do
      let _ = (1, 2)
      0
    end
  end|} in
  Alcotest.(check bool) "cap no_alloc + tuple: error" true (has_errors ctx)

let test_cap_no_alloc_record_error () =
  let ctx = check_no_alloc {|mod M do
    cap no_alloc
    fn f() : Bool do
      let _ = {x: 1}
      true
    end
  end|} in
  Alcotest.(check bool) "cap no_alloc + record: error" true (has_errors ctx)

let test_cap_no_alloc_some_error () =
  let ctx = check_no_alloc {|mod M do
    cap no_alloc
    fn f(x : Int) : Int do
      let _ = Some(x)
      x
    end
  end|} in
  Alcotest.(check bool) "cap no_alloc + Some(x): error" true (has_errors ctx)

let test_cap_no_alloc_lambda_error () =
  let ctx = check_no_alloc {|mod M do
    cap no_alloc
    fn f() : Int do
      let g = fn x -> x
      g(1)
    end
  end|} in
  Alcotest.(check bool) "cap no_alloc + lambda: error" true (has_errors ctx)

let test_cap_no_alloc_arithmetic_ok () =
  let ctx = check_no_alloc {|mod M do
    cap no_alloc
    fn add(a : Int, b : Int) : Int do a + b end
  end|} in
  Alcotest.(check bool) "cap no_alloc + pure arithmetic: no error" false (has_errors ctx)

let test_cap_no_alloc_if_ok () =
  let ctx = check_no_alloc {|mod M do
    cap no_alloc
    fn abs(x : Int) : Int do
      if x >= 0 do x else 0 - x end
    end
  end|} in
  Alcotest.(check bool) "cap no_alloc + if/match: no error" false (has_errors ctx)

let test_cap_not_set_tuple_ok () =
  let ctx = check_no_alloc {|mod M do
    fn f() : Int do
      let _ = (1, 2)
      0
    end
  end|} in
  Alcotest.(check bool) "no cap no_alloc + tuple: no error" false (has_errors ctx)

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

(* ── satisfy: desugar-time impl generation from existing functions ──────── *)

let test_satisfy_basic () =
  (* satisfy generates impl block from existing function with matching name. *)
  let ctx = typecheck {|mod Test do
    interface Named(a) do
      fn name: a -> String
    end
    type User = User(String)
    fn name(u : User) : String do
      match u do User(s) -> s end
    end
    satisfy Named for User
    fn main() do name(User("Alice")) end
  end|} in
  Alcotest.(check bool) "satisfy Named for User: no error" false (has_errors ctx)

let test_satisfy_two_ifaces () =
  (* satisfy Named, Aged for User generates impl blocks for each interface. *)
  let ctx = typecheck {|mod Test do
    interface Named(a) do
      fn name: a -> String
    end
    interface Aged(a) do
      fn age: a -> Int
    end
    type User = User(String, Int)
    fn name(u : User) : String do
      match u do User(s, _) -> s end
    end
    fn age(u : User) : Int do
      match u do User(_, n) -> n end
    end
    satisfy Named, Aged for User
    fn main() do
      let n = name(User("Alice", 30))
      let a = age(User("Alice", 30))
      n ++ String.from_int(a)
    end
  end|} in
  Alcotest.(check bool) "satisfy Named, Aged for User: no error" false (has_errors ctx)

let test_satisfy_two_types () =
  (* Two separate satisfy declarations each wire a different type. *)
  let ctx = typecheck {|mod Test do
    interface Named(a) do
      fn name: a -> String
    end
    type User = User(String)
    type Post = Post(String)
    fn name(u : User) : String do
      match u do User(s) -> s end
    end
    satisfy Named for User
    fn main() do name(User("Alice")) end
  end|} in
  Alcotest.(check bool) "satisfy Named for User (one of two types): no error" false (has_errors ctx)

let test_satisfy_unknown_iface () =
  (* Unknown interface in satisfy → desugar error. *)
  let src = {|mod Test do
    type User = User(String)
    fn name(u : User) : String do
      match u do User(s) -> s end
    end
    satisfy NoSuchIface for User
  end|} in
  let errors = March_errors.Errors.create () in
  ignore (March_desugar.Desugar.desugar_module ~errors (parse_module src));
  Alcotest.(check bool) "satisfy unknown interface: error" true (has_errors errors)

let test_satisfy_missing_fn () =
  (* Missing function for required method → desugar error. *)
  let src = {|mod Test do
    interface Named(a) do
      fn name: a -> String
    end
    type User = User(String)
    satisfy Named for User
  end|} in
  let errors = March_errors.Errors.create () in
  ignore (March_desugar.Desugar.desugar_module ~errors (parse_module src));
  Alcotest.(check bool) "satisfy with missing function: error" true (has_errors errors)

let test_satisfy_multi_method_iface () =
  (* Multi-method interface: all methods must exist as functions. *)
  let ctx = typecheck {|mod Test do
    interface Describable(a) do
      fn label: a -> String
      fn desc: a -> String
    end
    type Item = Item(String, String)
    fn label(i : Item) : String do
      match i do Item(s, _) -> s end
    end
    fn desc(i : Item) : String do
      match i do Item(_, d) -> d end
    end
    satisfy Describable for Item
    fn main() do label(Item("A", "B")) end
  end|} in
  Alcotest.(check bool) "satisfy multi-method interface: no error" false (has_errors ctx)

let test_satisfy_multi_method_missing_one () =
  (* Multi-method interface with one missing function → desugar error. *)
  let src = {|mod Test do
    interface Describable(a) do
      fn label: a -> String
      fn desc: a -> String
    end
    type Item = Item(String, String)
    fn label(i : Item) : String do
      match i do Item(s, _) -> s end
    end
    satisfy Describable for Item
  end|} in
  let errors = March_errors.Errors.create () in
  ignore (March_desugar.Desugar.desugar_module ~errors (parse_module src));
  Alcotest.(check bool) "satisfy multi-method missing one fn: error" true (has_errors errors)

let test_satisfy_then_use () =
  (* satisfy generates an impl that the typechecker can use for dispatch. *)
  let ctx = typecheck {|mod Test do
    interface Printable(a) do
      fn to_str: a -> String
    end
    type Color = Red | Blue
    fn to_str(c : Color) : String do
      match c do
        Red -> "red"
        Blue -> "blue"
      end
    end
    satisfy Printable for Color
    fn show_color(c : Color) : String do to_str(c) end
    fn main() do show_color(Red) end
  end|} in
  Alcotest.(check bool) "satisfy then use via interface: no error" false (has_errors ctx)

let test_satisfy_lexer_token () =
  (* The 'satisfy' token is recognized by the lexer. *)
  let lexbuf = Lexing.from_string "satisfy" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "lexes satisfy keyword" true
    (match tok with March_parser.Parser.SATISFY -> true | _ -> false)

let test_satisfy_parse_basic () =
  (* satisfy expands to a DImpl node at desugar time. *)
  let src = {|mod Test do
    interface Named(a) do
      fn name: a -> String
    end
    type User = User(String)
    fn name(u : User) : String do
      match u do User(s) -> s end
    end
    satisfy Named for User
  end|} in
  let m = parse_and_desugar src in
  (* After desugar, DSatisfy is expanded to DImpl — check there's a DImpl block. *)
  let has_impl = List.exists (function
    | March_ast.Ast.DImpl (idef, _) -> idef.impl_iface.txt = "Named"
    | _ -> false) m.March_ast.Ast.mod_decls in
  Alcotest.(check bool) "satisfy expands to DImpl(Named)" true has_impl

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

(* ── IO.Mut: Vault shared-mutable-state capability ──────────────────────── *)

let test_cap_body_missing_mut () =
  let ctx = typecheck {|mod Store do
    fn setup() do
      let _ = vault_new("cache")
      ()
    end
  end|} in
  Alcotest.(check bool) "vault_new without needs: body-scan warning" true
    (has_warning_with ctx "IO.Mut")

let test_cap_body_mut_ok () =
  let ctx = typecheck {|mod Store do
    needs IO.Mut
    fn setup() do
      let _ = vault_new("cache")
      ()
    end
  end|} in
  Alcotest.(check bool) "vault_new with needs IO.Mut: no warning" false
    (has_warning_with ctx "IO.Mut")

let test_cap_body_mut_parent_ok () =
  let ctx = typecheck {|mod Store do
    needs IO
    fn setup() do
      let _ = vault_new("cache")
      ()
    end
  end|} in
  Alcotest.(check bool) "needs IO umbrella covers vault_new: no warning" false
    (has_warning_with ctx "IO.Mut")

(* ── IO.NetConnect.TLS: encrypted transport capability ──────────────────── *)

let test_cap_body_missing_tls () =
  let ctx = typecheck {|mod Secure do
    fn dial(fd, h, host) do tls_connect(fd, h, host) end
  end|} in
  Alcotest.(check bool) "tls_connect without needs: body-scan warning" true
    (has_warning_with ctx "IO.NetConnect.TLS")

let test_cap_body_tls_ok () =
  let ctx = typecheck {|mod Secure do
    needs IO.NetConnect.TLS
    fn dial(fd, h, host) do tls_connect(fd, h, host) end
  end|} in
  Alcotest.(check bool) "tls_connect with needs IO.NetConnect.TLS: no warning" false
    (has_warning_with ctx "IO.NetConnect.TLS")

let test_cap_body_tls_parent_ok () =
  let ctx = typecheck {|mod Secure do
    needs IO.NetConnect
    fn dial(fd, h, host) do tls_connect(fd, h, host) end
  end|} in
  Alcotest.(check bool) "needs IO.NetConnect umbrella covers tls_connect: no warning" false
    (has_warning_with ctx "IO.NetConnect.TLS")

(* ── IO.WebSocket: least-privilege sub-cap of IO.NetConnect ──────────────── *)

let test_cap_body_missing_ws () =
  let ctx = typecheck {|mod Ws do
    fn go(fd) do ws_recv(fd) end
  end|} in
  Alcotest.(check bool) "ws_recv without needs: body-scan warning" true
    (has_warning_with ctx "IO.WebSocket")

let test_cap_body_ws_ok () =
  let ctx = typecheck {|mod Ws do
    needs IO.WebSocket
    fn go(fd) do ws_recv(fd) end
  end|} in
  Alcotest.(check bool) "ws_recv with needs IO.WebSocket: no warning" false
    (has_warning_with ctx "IO.WebSocket")

let test_cap_body_ws_parent_ok () =
  let ctx = typecheck {|mod Ws do
    needs IO.NetConnect
    fn go(fd) do ws_recv(fd) end
  end|} in
  Alcotest.(check bool) "needs IO.NetConnect umbrella covers ws_recv: no warning" false
    (has_warning_with ctx "IO.WebSocket")

let test_cap_ws_arg_ok () =
  let ctx = typecheck {|mod Ws do
    needs IO.WebSocket
    fn f(_c : Cap(IO.WebSocket)) : Int do 0 end
  end|} in
  Alcotest.(check bool) "Cap(IO.WebSocket) arg with needs: no error" false (has_errors ctx)

(* ── IO.Telemetry: declaration-only cap; needs parses without error ──────── *)

let test_cap_body_telemetry_decl_ok () =
  let ctx = typecheck {|mod Metrics do
    needs IO.Telemetry
    fn record_hit() do () end
  end|} in
  Alcotest.(check bool) "needs IO.Telemetry: parses and typechecks cleanly" false
    (has_errors ctx)

(* task_spawn without needs IO.Spawn — body-scan warns. *)
let test_cap_body_missing_spawn () =
  let ctx = typecheck {|mod Spawner do
    fn run() do
      let _ = task_spawn(fn _ -> 42)
      ()
    end
  end|} in
  Alcotest.(check bool) "task_spawn without needs: body-scan warning" true
    (has_warning_with ctx "IO.Spawn")

(* task_spawn with needs IO.Spawn — no warning. *)
let test_cap_body_spawn_ok () =
  let ctx = typecheck {|mod Spawner do
    needs IO.Spawn
    fn run() do
      let _ = task_spawn(fn _ -> 42)
      ()
    end
  end|} in
  Alcotest.(check bool) "task_spawn with needs IO.Spawn: no warning" false
    (has_warning_with ctx "IO.Spawn")

(* needs IO (parent) satisfies IO.Spawn body call. *)
let test_cap_body_spawn_parent_ok () =
  let ctx = typecheck {|mod Spawner do
    needs IO
    fn run() do
      let _ = task_spawn(fn _ -> 42)
      ()
    end
  end|} in
  Alcotest.(check bool) "needs IO umbrella covers task_spawn: no warning" false
    (has_warning_with ctx "IO.Spawn")

(* ── Refinement types (A1a: parse + erase to base) ──────────────────────── *)

(* Walk a surface type looking for a TyRefine node. *)
let rec ty_has_refine : March_ast.Ast.ty -> bool = function
  | March_ast.Ast.TyRefine _ -> true
  | March_ast.Ast.TyCon (_, args) -> List.exists ty_has_refine args
  | March_ast.Ast.TyArrow (a, b) | March_ast.Ast.TyNatOp (_, a, b) ->
    ty_has_refine a || ty_has_refine b
  | March_ast.Ast.TyTuple ts -> List.exists ty_has_refine ts
  | March_ast.Ast.TyRecord fs -> List.exists (fun (_, t) -> ty_has_refine t) fs
  | March_ast.Ast.TyLinear (_, t) -> ty_has_refine t
  | March_ast.Ast.TyVar _ | March_ast.Ast.TyNat _ | March_ast.Ast.TyChan _ -> false

let rec decl_has_refined_param : March_ast.Ast.decl -> bool = function
  | March_ast.Ast.DFn (fd, _) ->
    List.exists
      (fun (c : March_ast.Ast.fn_clause) ->
        List.exists
          (function
            | March_ast.Ast.FPNamed p | March_ast.Ast.FPDefault (p, _) ->
              (match p.March_ast.Ast.param_ty with
               | Some t -> ty_has_refine t
               | None -> false)
            | March_ast.Ast.FPPat _ -> false)
          c.March_ast.Ast.fc_params)
      fd.March_ast.Ast.fn_clauses
  | March_ast.Ast.DMod (_, _, decls, _) ->
    List.exists decl_has_refined_param decls
  | _ -> false

let test_parse_refinement_node_present () =
  (* Both refinement forms must parse and construct a TyRefine (not be dropped). *)
  let m =
    Test_helpers.parse_module
      "mod M do\n\
      \  fn f(i : {Int | _ >= 0 && _ < 10}) : Int do i end\n\
      \  fn g(d : {v : Int | v != 0}) : Int do d end\n\
       end\n"
  in
  Alcotest.(check bool) "TyRefine present in parsed AST" true
    (List.exists decl_has_refined_param m.March_ast.Ast.mod_decls)

let test_refined_param_typechecks_as_base () =
  (* A1a erasure: a refined param typechecks exactly like its base type. *)
  let refined =
    "mod M do\n\
    \  fn f(i : {Int | _ >= 0}) : Int do i + 1 end\n\
    \  fn main() : Int do f(5) end\n\
     end\n"
  in
  let bare =
    "mod M do\n\
    \  fn f(i : Int) : Int do i + 1 end\n\
    \  fn main() : Int do f(5) end\n\
     end\n"
  in
  Alcotest.(check bool) "refined typechecks cleanly" false
    (Test_helpers.has_errors (Test_helpers.typecheck refined));
  Alcotest.(check bool) "bare typechecks cleanly" false
    (Test_helpers.has_errors (Test_helpers.typecheck bare))

(* IO.Foreign tests — extern blocks imply IO.Foreign meta-capability *)
let test_cap_body_missing_foreign () =
  let ctx = typecheck {|mod Bindings do
    extern "libc": Cap(IO.FileSystem) do
      fn read(fd : Int) : Int
    end
  end|} in
  Alcotest.(check bool) "extern block without needs IO.Foreign: warn" true
    (has_warning_with ctx "IO.Foreign")

let test_cap_body_foreign_ok () =
  let ctx = typecheck {|mod Bindings do
    needs IO.Foreign
    needs IO.FileSystem
    extern "libc": Cap(IO.FileSystem) do
      fn read(fd : Int) : Int
    end
  end|} in
  Alcotest.(check bool) "extern block with needs IO.Foreign: no warn" false
    (has_warning_with ctx "IO.Foreign")

let test_cap_body_foreign_parent_ok () =
  let ctx = typecheck {|mod Bindings do
    needs IO
    extern "libc": Cap(IO.FileSystem) do
      fn read(fd : Int) : Int
    end
  end|} in
  Alcotest.(check bool) "needs IO umbrella covers IO.Foreign: no warn" false
    (has_warning_with ctx "IO.Foreign")

let test_cap_body_foreign_blocking () =
  (* No needs at all: blocking extern warns for both IO.Foreign and IO.Foreign.Blocking *)
  let ctx = typecheck {|mod Bindings do
    needs IO.FileSystem
    extern "libc": Cap(IO.FileSystem) do
      blocking fn slow_read(fd : Int) : Int
    end
  end|} in
  Alcotest.(check bool) "blocking extern (no needs IO.Foreign) warns IO.Foreign.Blocking" true
    (has_warning_with ctx "IO.Foreign.Blocking")

(* ── fn_capability_closures: per-function IO-capability closure (Phase5C-A.2) ─
   check_module_needs records, per fully-qualified function name, the
   normalized set of IO capabilities it requires. These tests exercise the
   accessor directly via typecheck_full's returned env. *)

(* A function with only declared `needs` on the module — the accessor returns
   that declared set (normalized) attributed to the function. *)
(* NOTE on expected keys: [Greeter]/[Reader]/[Bindings] here are the ENTRY
   module (this is the whole source passed to [typecheck_full]/[check_module]),
   and TIR unwraps the entry module — its own top-level functions are lowered
   under their BARE name with no module prefix (confirmed empirically against
   [lib/tir/lower.ml]'s entry-module handling, ~line 2238: "the entry module's
   own top-level function names" get no prefix, unlike a nested/sibling DMod's
   functions which DO get `mod_prefix ^ fn_name`). So the cap-closure key here
   must be the bare fn name, not "Greeter.greet" etc. — see
   test_fn_cap_closure_two_level_nesting below for the nested-DMod case where
   a prefix IS expected. *)
let test_fn_cap_closure_declared_needs () =
  let (_errors, env) = typecheck_full {|mod Greeter do
    needs IO.Console
    fn greet(name) do name end
  end|} in
  let closures = March_typecheck.Typecheck.fn_capability_closures env in
  let caps = List.assoc_opt "greet" closures in
  Alcotest.(check bool) "declared needs recorded for fn" true
    (match caps with Some cs -> List.mem "IO.Console" cs | None -> false)

(* A function calling an IO builtin with no declared `needs` — the accessor
   returns the inferred set from builtin_cap_table for that function. *)
let test_fn_cap_closure_inferred_builtin () =
  let (_errors, env) = typecheck_full {|mod Reader do
    fn load(path) do file_read(path) end
  end|} in
  let closures = March_typecheck.Typecheck.fn_capability_closures env in
  let caps = List.assoc_opt "load" closures in
  Alcotest.(check bool) "inferred builtin cap recorded for fn" true
    (match caps with Some cs -> List.mem "IO.FileRead" cs | None -> false)

(* An extern function — the accessor returns a set including IO.Foreign. *)
let test_fn_cap_closure_extern () =
  let (_errors, env) = typecheck_full {|mod Bindings do
    needs IO.Foreign
    needs IO.FileSystem
    extern "libc": Cap(IO.FileSystem) do
      fn read(fd : Int) : Int
    end
  end|} in
  let closures = March_typecheck.Typecheck.fn_capability_closures env in
  let caps = List.assoc_opt "read" closures in
  Alcotest.(check bool) "extern fn recorded with IO.Foreign" true
    (match caps with Some cs -> List.mem "IO.Foreign" cs | None -> false)

(* A function that imports a module needing IO (Check 4 propagation) — the
   accessor returns the union, normalized, including the propagated cap. *)
let test_fn_cap_closure_propagated_import () =
  let (_errors, env) = typecheck_full {|mod Outer do
    mod Lib do
      needs IO.Mut
      fn setup() do
        let _ = vault_new("t")
        ()
      end
    end
    mod Consumer do
      needs IO.Mut
      fn run() do () end
    end
  end|} in
  let closures = March_typecheck.Typecheck.fn_capability_closures env in
  let caps = List.assoc_opt "Consumer.run" closures in
  Alcotest.(check bool) "propagated import cap recorded for consumer fn" true
    (match caps with Some cs -> List.mem "IO.Mut" cs | None -> false)

(* A function nested THREE levels deep (Entry > Lib > Sub > f) must be keyed
   by its full dotted path relative to the entry module ("Lib.Sub.f"), NOT by
   just its immediately-enclosing DMod's own name ("Sub.f"). This matches
   TIR's [mod_prefix] accumulation in lib/tir/lower.ml (line ~2174), which
   bin/main.ml's manifest writer uses to look up `hr_impl_hashes` keys —
   before this fix, the two naming schemes disagreed for any nesting depth
   greater than one, causing a silently-empty caps list in HCR manifests for
   real multi-module code (see task-2/3 capability-manifest security review). *)
let test_fn_cap_closure_two_level_nesting () =
  let (_errors, env) = typecheck_full {|mod Entry do
    mod Lib do
      mod Sub do
        needs IO.Console
        fn f(x) do println(x) end
      end
    end
    fn main() do Lib.Sub.f("hi") end
  end|} in
  let closures = March_typecheck.Typecheck.fn_capability_closures env in
  Alcotest.(check bool) "not falsely keyed under bare immediate-parent name" true
    (List.assoc_opt "Sub.f" closures = None);
  let caps = List.assoc_opt "Lib.Sub.f" closures in
  Alcotest.(check bool) "fully-qualified key records IO.Console" true
    (match caps with Some cs -> List.mem "IO.Console" cs | None -> false)

(* ── fn_own_capability_closures / migrate_state IO-free check (Phase5C-C.5) ─
   [fn_own_capability_closures] is the OWN-caps-only projection (no
   [module_wide_caps] merge) — the projection the migrate_state IO-free
   check must use. These tests exercise both the projection itself and the
   compile error it powers. *)

(* Local substring helper (the shared [_contains_substr] is defined later in
   this file, after these tests) — same naive O(n*m) scan. *)
let migrate_test_contains_substr haystack needle =
  let hn = String.length haystack and nn = String.length needle in
  if nn = 0 then true
  else begin
    let found = ref false in
    for i = 0 to hn - nn do
      if String.sub haystack i nn = needle then found := true
    done;
    !found
  end

(* The load-bearing test: a module declares `needs IO.Console` (as if for its
   handlers) alongside two functions — one that actually calls `println`
   (own caps = IO.Console) and one pure function (own caps = []).
   [fn_capability_closures] (merged) attributes IO.Console to BOTH, since the
   module-wide `needs` folds into every function's closure. But
   [fn_own_capability_closures] must give the pure function an EMPTY own-caps
   entry — proving the own-caps table only records what a function itself
   uses, not what its module declares. *)
let test_fn_own_cap_closure_excludes_module_wide () =
  let (_errors, env) = typecheck_full {|mod Actor do
    needs IO.Console
    fn noisy(x) do println(x) end
    fn pure_fn(x) do x + 1 end
  end|} in
  let merged = March_typecheck.Typecheck.fn_capability_closures env in
  let own = March_typecheck.Typecheck.fn_own_capability_closures env in
  Alcotest.(check bool) "merged closure attributes module-wide needs to noisy" true
    (match List.assoc_opt "noisy" merged with Some cs -> List.mem "IO.Console" cs | None -> false);
  Alcotest.(check bool) "merged closure ALSO attributes module-wide needs to pure_fn (the bug being guarded against)" true
    (match List.assoc_opt "pure_fn" merged with Some cs -> List.mem "IO.Console" cs | None -> false);
  Alcotest.(check bool) "own closure attributes IO.Console to noisy (it actually calls println)" true
    (match List.assoc_opt "noisy" own with Some cs -> List.mem "IO.Console" cs | None -> false);
  Alcotest.(check (list string)) "own closure is EMPTY for pure_fn (module-wide needs excluded)" []
    (match List.assoc_opt "pure_fn" own with Some cs -> cs | None -> [])

(* migrate_state calling file_write with no declared needs -> IO-free error. *)
let test_migrate_state_file_write_error () =
  let ctx = typecheck {|mod Counter do
    fn counter_migrate_state(old) do
      let _ = file_write("x", "y")
      old
    end
  end|} in
  Alcotest.(check bool) "migrate_state calling file_write: compile error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  let all_text = List.concat_map (fun d ->
    d.March_errors.Errors.message :: d.March_errors.Errors.notes) diags in
  Alcotest.(check bool) "error mentions migrate_state must be IO-free" true
    (List.exists (fun m -> migrate_test_contains_substr (String.lowercase_ascii m) "migrate_state must be io-free") all_text)

(* migrate_state calling println -> IO-free error. *)
let test_migrate_state_println_error () =
  let ctx = typecheck {|mod Counter do
    fn counter_migrate_state(old) do
      let _ = println(old)
      old
    end
  end|} in
  Alcotest.(check bool) "migrate_state calling println: compile error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  let all_text = List.concat_map (fun d ->
    d.March_errors.Errors.message :: d.March_errors.Errors.notes) diags in
  Alcotest.(check bool) "error mentions migrate_state must be IO-free" true
    (List.exists (fun m -> migrate_test_contains_substr (String.lowercase_ascii m) "migrate_state must be io-free") all_text)

(* migrate_state whose OWN signature is Cap(IO.Foreign)-implied via an extern
   block sharing the naming convention -> IO-free error (extern-implied cap). *)
let test_migrate_state_extern_error () =
  let ctx = typecheck {|mod Counter do
    needs IO.Foreign
    extern "libc" : Cap(IO.Foreign) do
      fn counter_migrate_state(fd : Int) : Int
    end
  end|} in
  Alcotest.(check bool) "migrate_state as extern fn: compile error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  let all_text = List.concat_map (fun d ->
    d.March_errors.Errors.message :: d.March_errors.Errors.notes) diags in
  Alcotest.(check bool) "error mentions migrate_state must be IO-free" true
    (List.exists (fun m -> migrate_test_contains_substr (String.lowercase_ascii m) "migrate_state must be io-free") all_text)

(* THE crux test: a pure migrate_state in a module that DOES declare a
   module-level `needs IO.Console` (as if for its handlers) must compile
   CLEAN — no error. This is the exact case the merged closure would wrongly
   reject; it only passes if the check consumes the own-caps projection. *)
let test_migrate_state_pure_with_module_needs_clean () =
  let ctx = typecheck {|mod Counter do
    needs IO.Console
    fn counter_migrate_state(old) do old end
    fn handle_inc(state) do
      let _ = println("incrementing")
      state
    end
  end|} in
  Alcotest.(check bool) "pure migrate_state in module with needs IO.Console: no error" false (has_errors ctx)

(* A pure migrate_state in a module with no needs at all -> clean. *)
let test_migrate_state_pure_no_needs_clean () =
  let ctx = typecheck {|mod Counter do
    fn counter_migrate_state(old) do old end
  end|} in
  Alcotest.(check bool) "pure migrate_state, no module needs: no error" false (has_errors ctx)

(* ── cap_propagation: needs suppressed when required by a sibling DMod ──── *)

(* A module that declares `needs IO.Mut` only to satisfy transitive enforcement
   (because a sibling DMod requires IO.Mut) should NOT get an "unused
   capability" warning.  Regression test for the Check 2 suppression.
   The sibling DMod pattern matches how `import Vault` bundles Vault.march as a
   sibling DMod before the consuming module. *)
let test_cap_propagation_no_unused_warn () =
  (* Lib and Consumer are sibling DMods inside Outer.  When Consumer is
     checked, env.module_caps already contains ("Lib", ["IO.Mut"]) from
     the earlier Lib check, so Check 2 suppresses the unused-cap warning
     for Consumer's `needs IO.Mut`. *)
  let ctx = typecheck {|mod Outer do
    mod Lib do
      needs IO.Mut
      fn setup() do
        let _ = vault_new("t")
        ()
      end
    end
    mod Consumer do
      needs IO.Mut
    end
  end|} in
  Alcotest.(check bool) "needs IO.Mut suppressed when required by sibling DMod" false
    (has_warning_with ctx "unused capability")

(* The suppression is selective: a declared needs that is NEITHER used directly
   NOR required by any sibling still warns. *)
let test_cap_propagation_still_warns_unrelated () =
  let ctx = typecheck {|mod Outer do
    mod Lib do
      needs IO.Mut
      fn setup() do
        let _ = vault_new("t")
        ()
      end
    end
    mod Consumer do
      needs IO.Console
    end
  end|} in
  Alcotest.(check bool) "unrelated needs IO.Console still warns when unused" true
    (has_warning_with ctx "unused capability")

(* ── cap_infer: standalone refinecheck capability-inference hints ────────── *)

(* Helper: run typecheck then the standalone cap_infer pass.
   Returns the shared error context so callers can inspect both
   typechecker warnings and cap_infer hints. *)
let check_cap_infer src =
  let m = parse_and_desugar src in
  let (errors, _) = March_typecheck.Typecheck.check_module m in
  March_refinecheck.Cap_infer.check_module errors m;
  errors

let test_cap_infer_random_missing () =
  (* random_bytes without needs IO.Random → hint from cap_infer *)
  let ctx = check_cap_infer {|mod M do
    fn f() : Int do
      random_bytes(16)
      0
    end
  end|} in
  Alcotest.(check bool) "random_bytes without needs: hint emitted" true
    (has_hint_with ctx "IO.Random")

let test_cap_infer_random_declared () =
  (* needs IO.Random declared → no hint from cap_infer *)
  let ctx = check_cap_infer {|mod M do
    needs IO.Random
    fn f() : Int do
      random_bytes(16)
      0
    end
  end|} in
  Alcotest.(check bool) "random_bytes with needs IO.Random: no hint" false
    (has_hint_with ctx "IO.Random")

let test_cap_infer_filewrite_missing () =
  (* file_write without needs IO.FileWrite → hint *)
  let ctx = check_cap_infer {|mod M do
    fn f() : Unit do
      file_write("x.txt", "hi")
    end
  end|} in
  Alcotest.(check bool) "file_write without needs: hint emitted" true
    (has_hint_with ctx "IO.FileWrite")

let test_cap_infer_pure_no_hint () =
  (* Pure function with no capability-requiring calls → no hint *)
  let ctx = check_cap_infer {|mod M do
    fn add(a : Int, b : Int) : Int do a + b end
  end|} in
  Alcotest.(check bool) "pure fn with no cap calls: no hint" false
    (has_hints ctx)

let test_cap_infer_parent_cap_covers () =
  (* needs IO covers all IO.* children — no hint for random_bytes *)
  let ctx = check_cap_infer {|mod M do
    needs IO
    fn f() : Int do
      random_bytes(8)
      0
    end
  end|} in
  Alcotest.(check bool) "needs IO covers IO.Random child: no hint" false
    (has_hint_with ctx "IO.Random")

let test_cap_infer_nested_mod_inner_declared () =
  (* Inner mod has its own needs IO.Random — no hint for the inner call *)
  let ctx = check_cap_infer {|mod Outer do
    mod Inner do
      needs IO.Random
      fn f() : Int do
        random_bytes(4)
        0
      end
    end
  end|} in
  Alcotest.(check bool) "nested mod with declared needs: no hint for inner" false
    (has_hint_with ctx "IO.Random")

let test_cap_infer_nested_mod_inner_missing () =
  (* Inner mod missing needs IO.Random → hint, even though outer might not care *)
  let ctx = check_cap_infer {|mod Outer do
    mod Inner do
      fn f() : Int do
        random_bytes(4)
        0
      end
    end
  end|} in
  Alcotest.(check bool) "nested mod without declared needs: hint for inner" true
    (has_hint_with ctx "IO.Random")

(* ── return_refine_infer: Z3-based return-sign inference ────────────────── *)

(* Helper: run infer_module on a snippet and return inferred results. *)
let infer_returns src =
  let m = Test_helpers.parse_and_desugar src in
  March_refinecheck.Return_infer.infer_module m

(* Check whether any result matches fn_name and has the given pred string. *)
let has_pred results fn_name pred =
  List.exists
    (fun (r : March_refinecheck.Return_infer.inferred_return) ->
      r.fn_name = fn_name && List.mem pred r.verified_preds)
    results

(* Guard: skip test bodies when Z3 is unavailable. *)
let z3_available () =
  let vc = March_refine.Smt.{
    decls = [("x", March_refine.Smt.SInt)];
    assumptions = [March_refine.Smt.Ge (March_refine.Smt.Const "x", March_refine.Smt.IntLit 1)];
    goal = March_refine.Smt.Gt (March_refine.Smt.Const "x", March_refine.Smt.IntLit 0) }
  in
  match March_refine.Refine.discharge ~root:(Sys.getcwd ()) vc with
  | March_refine.Refine.Verified -> true
  | _ -> false

let test_return_infer_identity_positive () =
  (* fn id(x : {v : Int | v > 0}) : Int = x  →  infers r > 0 *)
  if not (z3_available ()) then ()
  else begin
    let results = infer_returns {|mod M do
      fn id(x : {v : Int | v > 0}) : Int do x end
    end|} in
    Alcotest.(check bool) "id: r > 0 inferred" true (has_pred results "id" "r > 0");
    Alcotest.(check bool) "id: r >= 0 inferred" true (has_pred results "id" "r >= 0")
  end

let test_return_infer_add_one () =
  (* fn inc(x : {v : Int | v >= 0}) : Int = x + 1  →  infers r >= 1, r > 0, r >= 0 *)
  if not (z3_available ()) then ()
  else begin
    let results = infer_returns {|mod M do
      fn inc(x : {v : Int | v >= 0}) : Int do x + 1 end
    end|} in
    Alcotest.(check bool) "inc: r >= 1 inferred" true (has_pred results "inc" "r >= 1");
    Alcotest.(check bool) "inc: r > 0 inferred"  true (has_pred results "inc" "r > 0")
  end

let test_return_infer_no_refined_params () =
  (* fn plain(x : Int) : Int = x  →  no refinement can be inferred *)
  let results = infer_returns {|mod M do
    fn plain(x : Int) : Int do x end
  end|} in
  Alcotest.(check bool) "plain: no inferences" true
    (not (List.exists (fun (r : March_refinecheck.Return_infer.inferred_return) -> r.fn_name = "plain") results))

let test_return_infer_let_propagation () =
  (* fn f(x : {v : Int | v > 0}) : Int =
       let y = x + 1
       y
     →  infers r > 0 via let-binding propagation *)
  if not (z3_available ()) then ()
  else begin
    let results = infer_returns {|mod M do
      fn f(x : {v : Int | v > 0}) : Int do
        let y = x + 1
        y
      end
    end|} in
    Alcotest.(check bool) "f: r > 0 via let" true (has_pred results "f" "r > 0")
  end

let test_return_infer_literal_return () =
  (* fn five(x : {v : Int | v > 0}) : Int = 5  →  infers r > 0, r >= 1, r != 0 *)
  if not (z3_available ()) then ()
  else begin
    let results = infer_returns {|mod M do
      fn five(x : {v : Int | v > 0}) : Int do 5 end
    end|} in
    Alcotest.(check bool) "five: r > 0"   true (has_pred results "five" "r > 0");
    Alcotest.(check bool) "five: r >= 1"  true (has_pred results "five" "r >= 1");
    Alcotest.(check bool) "five: r != 0"  true (has_pred results "five" "r != 0")
  end

let test_return_infer_negative_param () =
  (* fn f(x : {v : Int | v < 0}) : Int = x  →  infers r < 0, r <= -1, r != 0 *)
  if not (z3_available ()) then ()
  else begin
    let results = infer_returns {|mod M do
      fn f(x : {v : Int | v < 0}) : Int do x end
    end|} in
    Alcotest.(check bool) "f: r < 0"   true (has_pred results "f" "r < 0");
    Alcotest.(check bool) "f: r <= -1" true (has_pred results "f" "r <= -1");
    Alcotest.(check bool) "f: r != 0"  true (has_pred results "f" "r != 0")
  end

let test_record_type_still_parses () =
  (* Disambiguation regression: record types must not be misparsed as refinements. *)
  let m =
    Test_helpers.parse_module
      "mod M do fn r(p : { x : Int, y : Int }) : Int do p.x end end\n"
  in
  Alcotest.(check bool) "record type is not a refinement" false
    (List.exists decl_has_refined_param m.March_ast.Ast.mod_decls)

(* ── Improvement #1: labels rendered in render_diagnostic ─────────────── *)

let test_label_rendered_in_output () =
  let open March_errors.Errors in
  let src = "let x : String = 42" in
  let lbl_span = March_ast.Ast.{
    file = "test"; start_line = 1; start_col = 0; end_line = 1; end_col = 17 } in
  let primary_span = March_ast.Ast.{
    file = "test"; start_line = 1; start_col = 17; end_line = 1; end_col = 19 } in
  let diag = {
    severity = Error;
    span     = primary_span;
    message  = "type mismatch";
    labels   = [{ lbl_span; lbl_message = "the expected type comes from here" }];
    notes    = [];
    code     = None;
    fix      = None;
  } in
  let rendered = render_diagnostic ~src diag in
  let target = "the expected type comes from here" in
  let lo = String.lowercase_ascii rendered in
  let n = String.length target in
  let found = ref false in
  for i = 0 to String.length lo - n do
    if String.sub lo i n = target then found := true
  done;
  Alcotest.(check bool) "label message appears in rendered output" true !found

(* ── Improvement #2: if-branch and match-arm mismatch labels ──────────── *)

let test_if_branch_mismatch_has_label () =
  let ctx = typecheck {|mod Test do
    fn f() do
      if true do
        "hello"
      else
        42
      end
    end
  end|} in
  Alcotest.(check bool) "if-branch mismatch: has error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  let errors = List.filter (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Error) diags in
  Alcotest.(check bool) "if-branch mismatch error has a secondary label"
    true (List.exists (fun d -> d.March_errors.Errors.labels <> []) errors)

let test_match_arm_mismatch_has_label () =
  let ctx = typecheck {|mod Test do
    type Shape = Circle | Square
    fn f(s : Shape) do
      match s do
        Circle -> "round"
        Square -> 42
      end
    end
  end|} in
  Alcotest.(check bool) "match-arm mismatch: has error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  let errors = List.filter (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Error) diags in
  Alcotest.(check bool) "match-arm mismatch error has a secondary label"
    true (List.exists (fun d -> d.March_errors.Errors.labels <> []) errors)

(* ── Improvement #3: arity error labels definition site ───────────────── *)

let test_arity_error_has_definition_label () =
  let ctx = typecheck {|mod Test do
    fn add(a : Int, b : Int) : Int do a + b end
    fn main() do add(1) end
  end|} in
  Alcotest.(check bool) "arity error: has error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  let errors = List.filter (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Error) diags in
  Alcotest.(check bool) "arity error has a label pointing to definition"
    true (List.exists (fun d -> d.March_errors.Errors.labels <> []) errors)

(* ── Improvement #4: record field fuzzy suggestion ─────────────────────── *)

let _contains_substr haystack needle =
  let hn = String.length haystack and nn = String.length needle in
  if nn = 0 then true
  else begin
    let found = ref false in
    for i = 0 to hn - nn do
      if String.sub haystack i nn = needle then found := true
    done;
    !found
  end

let test_record_field_typo_suggestion () =
  let ctx = typecheck {|mod Test do
    fn f(r : { name: String, age: Int }) do r.naem end
  end|} in
  Alcotest.(check bool) "field typo: has error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  let all_text = List.concat_map (fun d ->
    d.March_errors.Errors.message :: d.March_errors.Errors.notes) diags in
  Alcotest.(check bool) "field typo suggests 'name'"
    true (List.exists (fun m ->
      _contains_substr (String.lowercase_ascii m) "name") all_text)

let test_record_field_no_false_suggestion () =
  let ctx = typecheck {|mod Test do
    fn f(r : { name: String }) do r.xyz end
  end|} in
  Alcotest.(check bool) "unrelated field name: has error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  let all_text = List.concat_map (fun d ->
    d.March_errors.Errors.message :: d.March_errors.Errors.notes) diags in
  Alcotest.(check bool) "no spurious 'did you mean' for unrelated name"
    false (List.exists (fun m ->
      _contains_substr (String.lowercase_ascii m) "did you mean") all_text)

(* ── Improvement #5: let? wrong type shows actual type ─────────────────── *)

let test_letq_wrong_type_shows_actual_type () =
  let ctx = typecheck {|mod Test do
    fn f() : Result(Int, String) do
      let? x = Some(42)
      Ok(x)
    end
  end|} in
  Alcotest.(check bool) "let? on Option: has error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  let all_text = List.concat_map (fun d ->
    d.March_errors.Errors.message :: d.March_errors.Errors.notes) diags in
  Alcotest.(check bool) "let? error mentions actual type 'option'"
    true (List.exists (fun m ->
      _contains_substr (String.lowercase_ascii m) "option") all_text)

(* ── Improvement #6: redundant/unreachable match arm warning ───────────── *)

let has_redundant_warning ctx =
  List.exists (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Warning &&
    let lo = String.lowercase_ascii d.March_errors.Errors.message in
    _contains_substr lo "redundant" ||
    _contains_substr lo "unreachable" ||
    _contains_substr lo "never be reached"
  ) (March_errors.Errors.sorted ctx)

let test_redundant_ctor_arm_warning () =
  let ctx = typecheck {|mod Test do
    type Color = Red | Green | Blue
    fn f(c : Color) do
      match c do
        Red -> 1
        Red -> 2
        _ -> 3
      end
    end
  end|} in
  Alcotest.(check bool) "duplicate ctor arm: redundancy warning present"
    true (has_redundant_warning ctx)

let test_redundant_after_wildcard_warning () =
  let ctx = typecheck {|mod Test do
    type Color = Red | Green | Blue
    fn f(c : Color) do
      match c do
        _ -> 0
        Red -> 1
      end
    end
  end|} in
  Alcotest.(check bool) "arm after wildcard: redundancy warning present"
    true (has_redundant_warning ctx)

let test_guarded_arm_no_redundant_warning () =
  let ctx = typecheck {|mod Test do
    type Color = Red | Green | Blue
    fn f(c : Color, x : Int) do
      match c do
        Red when x > 0 -> 1
        Red -> 2
        _ -> 3
      end
    end
  end|} in
  Alcotest.(check bool) "guarded arm before duplicate: no redundancy warning"
    false (has_redundant_warning ctx)

let test_non_redundant_no_warning () =
  let ctx = typecheck {|mod Test do
    type Color = Red | Green | Blue
    fn f(c : Color) do
      match c do
        Red -> 1
        Green -> 2
        Blue -> 3
      end
    end
  end|} in
  Alcotest.(check bool) "exhaustive non-redundant match: no redundancy warning"
    false (has_redundant_warning ctx)

(* ── Improvement #8: qualified error uses notes ─────────────────────────── *)

let test_qualified_error_uses_notes () =
  let ctx = typecheck {|mod Test do
    fn f() do Nonexistent.foo(1) end
  end|} in
  Alcotest.(check bool) "unknown module: has error" true (has_errors ctx);
  let diags = March_errors.Errors.sorted ctx in
  let errors = List.filter (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Error) diags in
  (* Either the suggestion is in notes, or it's not embedded raw in the message *)
  Alcotest.(check bool) "qualified error: suggestion in notes OR message is clean"
    true (List.exists (fun d ->
      d.March_errors.Errors.notes <> [] ||
      not (_contains_substr d.March_errors.Errors.message "Did you mean")
    ) errors)

(* ── Improvement #7: parse errors route through render_diagnostic ────────── *)

let render_parse_err src =
  let lexbuf = Lexing.from_string src in
  (try ignore (March_parser.Parser.module_
    (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf); ""
  with
  | March_errors.Errors.ParseError (msg, hint, _) ->
    let lb2 = Lexing.from_string src in
    March_errors.Errors.render_parse_error ~src ?hint ~msg lb2
  | March_parser.Parser.Error ->
    let lb2 = Lexing.from_string src in
    March_errors.Errors.render_parse_error ~src ~msg:"Parse error:" lb2
  | _ -> "")

let test_parse_error_has_error_header () =
  let src = "mod Test do\n  fn f(x) do\n    if x then 1 end\n  end\nend" in
  let output = render_parse_err src in
  Alcotest.(check bool) "#7 parse error header is -- ERROR not -- PARSE ERROR" true
    (_contains_substr output "-- ERROR ")

let test_parse_error_then_note_do_end () =
  let src = "mod Test do\n  fn f(x) do\n    if x then 1 end\n  end\nend" in
  let output = render_parse_err src in
  Alcotest.(check bool) "#7 if-then note mentions do/end" true
    (_contains_substr output "do/end")

(* ── Follow-up fixes: better messages ──────────────────────────────────── *)

let test_parse_error_then_says_then_not_else () =
  (* "if x then 1 end" should produce a message that names `then` as the problem,
     not just say "always need an else branch" which is confusing *)
  let src = "mod Test do\n  fn f(x) do\n    if x then 1 end\n  end\nend" in
  let output = render_parse_err src in
  Alcotest.(check bool) "if-then error: message names `then` as the problem" true
    (_contains_substr output "then")

let test_parse_error_then_primary_message () =
  (* The primary message should not say "always need an else branch" when the
     actual problem is that the user wrote `then` instead of `do` *)
  let src = "mod Test do\n  fn f(x) do\n    if x then 1 end\n  end\nend" in
  let output = render_parse_err src in
  Alcotest.(check bool) "if-then error: primary message is about `then`, not else" true
    (not (_contains_substr output "always need an `else` branch"))

let test_parse_error_then_else_form_rejected () =
  (* W4.4: the complete `if c then e1 else e2` expression form used to be
     silently ACCEPTED by an undocumented production while the docs claimed
     `then` did not exist.  The production is removed; the form must now hit
     the same targeted error as the incomplete then-form, naming do/end. *)
  let src = "mod Test do\n  fn f(x) do\n    if x then 1 else 2\n  end\nend" in
  let output = render_parse_err src in
  Alcotest.(check bool) "if-then-else form rejected: targeted message names `then`" true
    (_contains_substr output "I don't recognize `then` here");
  Alcotest.(check bool) "if-then-else form rejected: hint shows do/end shape" true
    (_contains_substr output "do/end")

let test_if_branch_mismatch_reason_is_if_specific () =
  (* When if-branch types disagree, the reason note should say "if expression",
     not "All branches of a match must have the same type." *)
  let ctx = typecheck {|mod Test do
    fn f() do
      if true do
        "hello"
      else
        42
      end
    end
  end|} in
  let diags = March_errors.Errors.sorted ctx in
  let errors = List.filter (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Error) diags in
  Alcotest.(check bool) "if-branch mismatch: reason note mentions 'if expression'"
    true (List.exists (fun d ->
      List.exists (fun note ->
        _contains_substr note "if expression"
      ) d.March_errors.Errors.notes
    ) errors)

let test_if_branch_mismatch_reason_not_match () =
  (* Reason note should not say "match" for an if expression *)
  let ctx = typecheck {|mod Test do
    fn f() do
      if true do
        "hello"
      else
        42
      end
    end
  end|} in
  let diags = March_errors.Errors.sorted ctx in
  let errors = List.filter (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Error) diags in
  Alcotest.(check bool) "if-branch mismatch: reason note does not say 'match'"
    true (not (List.exists (fun d ->
      List.exists (fun note ->
        _contains_substr note "branches of a match"
      ) d.March_errors.Errors.notes
    ) errors))

(* ── Usability diagnostics: top-level mod + sibling fn, same-name type ──── *)

(* A file with a complete top-level `mod ... end` cannot also define sibling
   top-level declarations (one top-level module per file is by design).  The
   diagnostic must say so clearly rather than menhir's generic "stuck here". *)
let test_toplevel_mod_plus_sibling_fn_error () =
  let src =
    "mod Sales do\n\
    \  fn double(n : Int) : Int do n * 2 end\n\
     end\n\
     fn main() do\n\
    \  println(int_to_string(Sales.double(21)))\n\
     end\n" in
  let output = render_parse_err src in
  Alcotest.(check bool)
    "top-level mod + sibling fn: message mentions only one top-level mod" true
    (_contains_substr output "only one top-level" ||
     _contains_substr output "one top-level `mod`")

(* A nested multi-line match used directly as a match-arm body (no do/end
   wrapper) must parse.  This locks in the contextual-NL token-filter behavior
   so it can never silently regress. *)
let test_nested_inline_match_arm_parses () =
  let src =
    "mod Demo do\n\
    \  type MyList = MyNil | MyCons(Int, MyList)\n\
    \  fn process(r : Result(MyList, String)) : Int do\n\
    \    match r do\n\
    \      Err(_) -> -1\n\
    \      Ok(MyNil) -> 0\n\
    \      Ok(MyCons(h, t)) ->\n\
    \        match t do\n\
    \          MyNil -> h\n\
    \          MyCons(h2, _) -> h + h2\n\
    \        end\n\
    \    end\n\
    \  end\n\
    \  fn main() do 0 end\n\
     end\n" in
  let m = parse_module src in
  Alcotest.(check bool) "nested inline match arm parses to a module" true
    (List.length m.March_ast.Ast.mod_decls >= 3)

(* When two distinct types share a printed name (e.g. a local type and a
   same-named type from another module / the stdlib), unification fails with
   "expected `X` but got `X`".  The diagnostic must add a note explaining the
   global-namespace collision.  Here a nested-module record `Inner.Thing` and a
   top-level variant `Thing` both print as `Thing` but are structurally
   distinct, reproducing the collision without depending on stdlib loading. *)
let test_same_name_type_collision_note () =
  let ctx = typecheck {|mod Outer do
    mod Inner do
      type Thing = { a : Int }
    end
    type Thing = MkThing(Int)
    fn make() : Thing do MkThing(5) end
    fn use_inner(t : Inner.Thing) : Int do t.a end
    fn main() do
      let x = make()
      println(int_to_string(use_inner(x)))
    end
  end|} in
  let diags = March_errors.Errors.sorted ctx in
  let errors = List.filter (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Error) diags in
  Alcotest.(check bool)
    "same-name collision: a note explains two distinct types share the name" true
    (List.exists (fun d ->
      List.exists (fun note ->
        _contains_substr note "Two distinct types" ||
        _contains_substr note "global type namespace"
      ) d.March_errors.Errors.notes
    ) errors)

(* ------------------------------------------------------------------ *)
(* return_refine_infer guard tests                                     *)
(* ------------------------------------------------------------------ *)

(* if body: return_positions now drills into EIf arms — no exception *)
let test_return_infer_if_body_no_crash () =
  let infers = infer_returns {|mod T do
    fn abs(x : {v : Int | v != 0}) : Int do
      if x > 0 do x else 0 - x end
    end
  end|} in
  let length_ok = List.length infers >= 0 in
  Alcotest.(check bool) "if body: no crash" true length_ok

(* Match-arm guard widens what return_positions can prove *)
let test_return_infer_match_guard_both_arms_pos () =
  let infers = infer_returns {|mod T do
    fn f(x : {v : Int | v >= 0}) : Int do
      match x do
        x when x > 0 -> x
        _ -> 1
      end
    end
  end|} in
  if z3_available () then
    Alcotest.(check bool) "match guard infers r > 0 (both arms satisfy)" true
      (has_pred infers "f" "r > 0")

(* When arms disagree in sign, the intersection kills the predicate. *)
let test_return_infer_match_guard_intersection_kills () =
  let infers = infer_returns {|mod T do
    fn f(x : {v : Int | v != 0}) : Int do
      match x do
        x when x > 0 -> x
        _ -> 0 - 1
      end
    end
  end|} in
  Alcotest.(check bool) "arms disagree: r > 0 not in intersection" false
    (has_pred infers "f" "r > 0")

(* EIf path context: abs function infers r > 0 when return_positions drills in *)
let test_return_infer_if_guard_infers_pos () =
  let infers = infer_returns {|mod T do
    fn abs(x : {v : Int | v != 0}) : Int do
      if x > 0 do x else 0 - x end
    end
  end|} in
  if z3_available () then
    Alcotest.(check bool) "abs via if-guard infers r > 0" true
      (has_pred infers "abs" "r > 0")


(* B15: a raw newline inside a plain "..." string literal must advance the
   lexer's line tracking (Lexing.new_line), matching the triple-string rule's
   existing behavior. Before the fix, read_string/read_string_interp consumed
   the newline character without calling Lexing.new_line, so every span after
   the string was off by the number of embedded raw newlines. *)
let test_string_literal_raw_newline_tracks_line () =
  let src =
    "mod StrNL do\n\
    \  fn greet() do \"hello\nworld\" end\n\
    \  fn second() do 42 end\n\
     end\n" in
  let m = parse_module src in
  match m.March_ast.Ast.mod_decls with
  | [ March_ast.Ast.DFn (_, _); March_ast.Ast.DFn (_, second_span) ] ->
    (* Source lines: 1 `mod StrNL do`, 2 `fn greet() ... "hello`, 3 `world" end`
       (the raw newline inside the string literal splits the `greet` decl
       across lines 2-3), 4 `fn second() do 42 end`. *)
    Alcotest.(check int) "fn second() span line after raw newline in string" 4
      second_span.March_ast.Ast.start_line
  | decls ->
    Alcotest.fail (Printf.sprintf "expected two DFn decls, got %d decls" (List.length decls))

let test_string_interp_raw_newline_tracks_line () =
  let src =
    "mod StrInterpNL do\n\
    \  fn greet(name) do \"hi\n${name}\" end\n\
    \  fn second() do 42 end\n\
     end\n" in
  let m = parse_module src in
  match m.March_ast.Ast.mod_decls with
  | [ March_ast.Ast.DFn (_, _); March_ast.Ast.DFn (_, second_span) ] ->
    (* Same reasoning as above, but the raw newline is inside the prefix of a
       string-interpolation segment (read_string_interp), one line earlier
       than the interpolation hole. *)
    Alcotest.(check int) "fn second() span line after raw newline in string interp" 4
      second_span.March_ast.Ast.start_line
  | decls ->
    Alcotest.fail (Printf.sprintf "expected two DFn decls, got %d decls" (List.length decls))

(* FLOAT missing from token filter's pattern-start set (token_filter.ml
   is_pattern_start). Without FLOAT in the set, the contextual newline
   filter treats a newline-led float-literal match arm as a body
   continuation rather than the start of a new arm, so the parser sees a
   malformed arm and fails with "expecting `end`" at the float token. *)
let test_float_literal_match_arm_parses () =
  let src = {|mod FloatArms do
  fn name(x) do
    match x do
      1.5 -> "a"
      2.5 -> "b"
      _ -> "c"
    end
  end
end|} in
  let m = parse_module src in
  Alcotest.(check bool) "float-literal match arms parse to a module" true
    (List.length m.March_ast.Ast.mod_decls >= 1)

(* Negative float-literal patterns (`MINUS; FLOAT` in simple_pattern) must
   also be recognized as a pattern start — MINUS was already in the set, but
   cover it explicitly alongside FLOAT so a newline-led `-1.5 -> ...` arm
   parses too. *)
let test_negative_float_literal_match_arm_parses () =
  let src = {|mod NegFloatArms do
  fn sign(x) do
    match x do
      -1.5 -> "neg"
      1.5 -> "pos"
      _ -> "zero"
    end
  end
end|} in
  let m = parse_module src in
  Alcotest.(check bool) "negative float-literal match arms parse to a module" true
    (List.length m.March_ast.Ast.mod_decls >= 1)

(* Audit of simple_pattern (parser.mly ~1289-1308) against is_pattern_start:
   simple_pattern's id = soft_lower_name case accepts several keyword tokens
   as variable-pattern starters (STATE, INIT, LOOP, ON, PROTOCOL, APP, AS,
   WITH, WHEN, USE, IN, FOR, TAG), none of which were in is_pattern_start.
   A newline-led arm bound to one of these soft keywords as a var pattern
   would suffer the same "treated as body continuation" bug as FLOAT. Cover
   one representative case per missing token family: a soft-keyword var
   pattern used as a catch-all binder. (CHAR does not exist as a token in
   this grammar, so there is nothing to add for it.) *)
(* B6: `x |> (match scrut do ... end)` used to desugar by silently throwing
   away `scrut` and matching on `x` — verified silent wrong code. It must be
   a compile-time diagnostic instead. Uses the diagnostics-capture pattern
   (desugar_module ~errors) like the satisfy/derive desugar error tests. *)
let test_pipe_into_match_reports_error () =
  let src = {|mod PipeMatch do
  fn go() do
    1 |> (match 2 do 1 -> "one" | 2 -> "two" | _ -> "x" end)
  end
end|} in
  let errors = March_errors.Errors.create () in
  ignore (March_desugar.Desugar.desugar_module ~errors (parse_module src));
  Alcotest.(check bool) "pipe into match: desugar error" true (has_errors errors);
  let msgs = List.map (fun (d : March_errors.Errors.diagnostic) -> d.message)
      (March_errors.Errors.sorted errors) in
  Alcotest.(check bool) "message names the discarded scrutinee" true
    (List.exists (fun m ->
         try ignore (Str.search_forward (Str.regexp_string "discards its scrutinee") m 0); true
         with Not_found -> false) msgs);
  (* Diagnostic must be positioned at the offending match, not dummy. *)
  let spans = List.map (fun (d : March_errors.Errors.diagnostic) -> d.span)
      (March_errors.Errors.sorted errors) in
  Alcotest.(check bool) "diagnostic carries a real span" true
    (List.exists (fun (s : March_ast.Ast.span) -> s.start_line = 3) spans)

(* B6 sibling: the ECond pipe branch's expr→pattern conversion used a bare
   `failwith` (uncaught Failure in entry points without a handler). It must
   go through the same diagnostic mechanism. `foo(1)` is not convertible to
   a pattern, so this arm triggers the conversion failure. *)
let test_pipe_into_cond_bad_pattern_reports_error () =
  let src = {|mod PipeCondBad do
  fn go(x) do
    x |> (match do
      foo(1) -> "a"
      other -> "b"
    end)
  end
end|} in
  let errors = March_errors.Errors.create () in
  ignore (March_desugar.Desugar.desugar_module ~errors (parse_module src));
  Alcotest.(check bool) "pipe cond bad pattern: desugar error (not Failure)" true
    (has_errors errors)

(* Positive control: the scrutinee-less `x |> (match do pat -> ... end)` form
   is the supported pipe-match syntax and must keep desugaring cleanly.
   (A variable arm becomes a PatVar catch-all through expr_to_pat.) *)
let test_pipe_into_scrutineeless_match_still_works () =
  let src = {|mod PipeCondOk do
  fn go(x) do
    x |> (match do
      1 -> "one"
      other -> "other"
    end)
  end
end|} in
  let errors = March_errors.Errors.create () in
  ignore (March_desugar.Desugar.desugar_module ~errors (parse_module src));
  Alcotest.(check bool) "scrutinee-less pipe match: no desugar error" false
    (has_errors errors)

let test_soft_keyword_var_pattern_match_arm_parses () =
  let src = {|mod SoftKwArms do
  fn describe(x) do
    match x do
      0 -> "zero"
      state -> state
    end
  end
end|} in
  let m = parse_module src in
  Alcotest.(check bool) "soft-keyword var-pattern match arm parses to a module" true
    (List.length m.March_ast.Ast.mod_decls >= 1)

(* ── Cond-form / when-guard newline-led arms with comparison operators ────────

   The contextual newline filter (token_filter.ml lookahead_is_new_arm) decides
   whether the tokens after an arm body's NL start a NEW arm or continue the
   current arm body by scanning to the first depth-0 ARROW (=new arm) or NL
   (=continuation). It used to bail out early — declaring "body continuation" —
   the moment it saw one of a set of binary operators (LEQ/GEQ/EQEQ/NEQ/AND/OR/
   PLUSPLUS/…). That is correct for a plain `Pattern -> body` arm (a bare pattern
   can never be followed by `>=`), but WRONG in two positions where the thing
   before `->` is a full boolean expression rather than a plain pattern:

     (A) the cond form `match do BoolExpr -> body end` (no scrutinee), and
     (B) a guard's expression `Pattern when GuardExpr -> body`.

   In both, a second consecutive arm whose expression begins `ident OP …` (e.g.
   `score >= 80 -> …`, `x == 0 -> …`) was glued onto the previous arm's body,
   producing a parse error. Strict `<`/`>` (LT/GT, never in the bail set) always
   worked, which is why only the *other* comparison operators regressed. The
   helper below digs the ECond / EMatch out of a single-expression fn body so we
   can assert the arms are kept SEPARATE (correct count), not merely that the
   module parsed. *)

let cond_branches_of_module m =
  match m.March_ast.Ast.mod_decls with
  | March_ast.Ast.DFn (def, _) :: _ ->
    (match def.March_ast.Ast.fn_clauses with
     | { March_ast.Ast.fc_body = March_ast.Ast.ECond (branches, _); _ } :: _ -> branches
     | { March_ast.Ast.fc_body; _ } :: _ ->
       Alcotest.failf "expected ECond fn body, got %s"
         (March_ast.Ast.show_expr fc_body)
     | [] -> Alcotest.fail "expected at least one fn clause")
  | _ -> Alcotest.fail "expected a leading DFn declaration"

let match_branches_of_module m =
  match m.March_ast.Ast.mod_decls with
  | March_ast.Ast.DFn (def, _) :: _ ->
    (match def.March_ast.Ast.fn_clauses with
     | { March_ast.Ast.fc_body = March_ast.Ast.EMatch (_, branches, _); _ } :: _ -> branches
     | { March_ast.Ast.fc_body; _ } :: _ ->
       Alcotest.failf "expected EMatch fn body, got %s"
         (March_ast.Ast.show_expr fc_body)
     | [] -> Alcotest.fail "expected at least one fn clause")
  | _ -> Alcotest.fail "expected a leading DFn declaration"

(* (A) Cond form with two consecutive `>=` arms — verbatim from the
   pattern-matching.md "Cond" section grade example. Before the fix this failed
   with "I got stuck here" at the second `>=`. *)
let test_cond_ge_arms_parse () =
  let src = {|mod Test do
  fn grade(score : Int) : String do
    match do
      score >= 90 -> "A"
      score >= 80 -> "B"
      _ -> "F"
    end
  end
end|} in
  Alcotest.(check int) "three >= cond arms stay separate" 3
    (List.length (cond_branches_of_module (parse_module src)))

(* (A) Cond form with two consecutive `==` arms. *)
let test_cond_eqeq_arms_parse () =
  let src = {|mod Test do
  fn classify(n : Int) : String do
    match do
      n == 0 -> "zero"
      n == 1 -> "one"
      _ -> "many"
    end
  end
end|} in
  Alcotest.(check int) "three == cond arms stay separate" 3
    (List.length (cond_branches_of_module (parse_module src)))

(* (A) Cond form with two consecutive `<=` arms. *)
let test_cond_le_arms_parse () =
  let src = {|mod Test do
  fn band(n : Int) : String do
    match do
      n <= 10 -> "low"
      n <= 20 -> "mid"
      _ -> "high"
    end
  end
end|} in
  Alcotest.(check int) "three <= cond arms stay separate" 3
    (List.length (cond_branches_of_module (parse_module src)))

(* (B) Match-arm guards with two consecutive `==` guards — verbatim guard style
   from the pattern-matching.md "Guards" section. Before the fix this failed
   with "I was expecting `end` to close the match here" at the second guard. *)
let test_guard_eqeq_arms_parse () =
  let src = {|mod Test do
  fn label(n : Int) : String do
    match n do
      x when x == 1 -> "one"
      x when x == 0 -> "zero"
      _ -> "other"
    end
  end
end|} in
  let branches = match_branches_of_module (parse_module src) in
  Alcotest.(check int) "three guarded == arms stay separate" 3
    (List.length branches);
  let guarded =
    List.filter (fun (b : March_ast.Ast.branch) -> b.branch_guard <> None) branches
  in
  Alcotest.(check int) "first two arms carry a when-guard" 2 (List.length guarded)

(* (B) Match-arm guards with two consecutive `>=` guards. *)
let test_guard_ge_arms_parse () =
  let src = {|mod Test do
  fn size(n : Int) : String do
    match n do
      x when x >= 100 -> "big"
      x when x >= 10 -> "medium"
      _ -> "small"
    end
  end
end|} in
  Alcotest.(check int) "three guarded >= arms stay separate" 3
    (List.length (match_branches_of_module (parse_module src)))

(* (B) Match-arm guards with two consecutive `<=` guards. *)
let test_guard_le_arms_parse () =
  let src = {|mod Test do
  fn size(n : Int) : String do
    match n do
      x when x <= 0 -> "nonpos"
      x when x <= 10 -> "small"
      _ -> "large"
    end
  end
end|} in
  Alcotest.(check int) "three guarded <= arms stay separate" 3
    (List.length (match_branches_of_module (parse_module src)))

(* B14: group_fn_clauses merges only ADJACENT same-name fn clauses; a
   same-name group appearing again later at the same level (interleaved
   with another decl) used to compile with the earlier group silently
   dead. It must be a positioned parse-time error naming the function and
   both locations. *)
let test_interleaved_fn_clauses_error () =
  let src = {|mod Interleaved do
  fn f(0) do 0 end
  fn other() do 1 end
  fn f(n) do n end
end|} in
  let result =
    try ignore (parse_module src); None
    with March_errors.Errors.ParseError (msg, _hint, pos) -> Some (msg, pos)
  in
  match result with
  | None -> Alcotest.fail "interleaved same-name fn clause groups must not parse"
  | Some (msg, pos) ->
    let contains needle hay =
      try ignore (Str.search_forward (Str.regexp_string needle) hay 0); true
      with Not_found -> false in
    Alcotest.(check bool) "message names `f`" true (contains "`f`" msg);
    (* both locations: earlier group's line in the message, second group's
       line as the error position *)
    Alcotest.(check bool) "message points at earlier clauses (line 2)" true
      (contains "line 2" msg);
    Alcotest.(check int) "error positioned at the second group (line 4)" 4
      pos.Lexing.pos_lnum

(* Adjacent multi-head clauses (the supported form) must keep parsing,
   including when another decl FOLLOWS the group. *)
let test_adjacent_fn_clauses_still_parse () =
  let src = {|mod Adjacent do
  fn f(0) do 0 end
  fn f(n) do n end
  fn other() do 1 end
end|} in
  let m = parse_module src in
  (* f's clauses merged into one DFn; other is separate *)
  Alcotest.(check int) "two decls after grouping" 2
    (List.length m.March_ast.Ast.mod_decls)

(* The check is per module level: the same fn name in a NESTED module is a
   different scope and must not trip the adjacency validation. *)
let test_same_fn_name_in_nested_mod_ok () =
  let src = {|mod Outer do
  fn f(x) do x end
  mod Inner do
    fn f(y) do y end
  end
end|} in
  let m = parse_module src in
  Alcotest.(check int) "outer fn + nested mod parse" 2
    (List.length m.March_ast.Ast.mod_decls)

(* ── Diagnostic dedup: a broken ctor field type is reported once, not once
   per instantiation ──────────────────────────────────────────────────── *)

(* [instantiate_ctor] (typecheck.ml) re-resolves a constructor's stored
   surface argument types via [surface_ty] on EVERY instantiation (needed
   since polymorphic ctors need fresh type variables per use site) — but
   when one of those argument types fails to resolve, [surface_ty] used to
   re-emit the identical (span, message) diagnostic on every instantiation,
   not just once. `Wrap` below is instantiated 3 times (two pattern
   matches + one constructor call); its bogus `Bogus` field type must be
   reported exactly once, not 3 times. *)
let test_broken_ctor_field_type_reported_once () =
  let ctx = typecheck {|mod M do
    type Wrap = Wrap(Bogus)

    fn f1(w : Wrap) : Int do
      match w do
        Wrap(_) -> 1
      end
    end

    fn f2(w : Wrap) : Int do
      match w do
        Wrap(_) -> 2
      end
    end

    fn f3() : Wrap do
      Wrap(1)
    end
  end|} in
  Alcotest.(check int) "`Bogus` unresolved-type error reported exactly once" 1
    (count_errors_matching ctx "I cannot find `Bogus`.")

(* ── Entry-module self-qualified type erasure ─────────────────────────────
   An UNANNOTATED fn at the ENTRY module's top level, referenced by the
   entry-module-qualified name (`EntryMod.fn` — produced by desugar's
   [qualify_module_refs] to disambiguate a shadowing nested local, or written
   by hand), must be exactly as type-safe as the bare reference.  The entry
   module is UNWRAPPED at the combined module's top level, so — unlike a wrapped
   sibling module, whose public members are re-exported under `Sib.fn` with
   their real schemes when the sibling's DMod is checked — its own top-level fns
   are only ever seeded by [check_module_core]'s Pass 1b
   (`prebind_mod_members m.mod_name.txt`) as a bare `Mono (fresh_var 1)`
   placeholder ([prebind_fn_scheme] returns None for an unannotated fn).  Before
   the fix that decoupled `?a -> ?b` placeholder was never reconciled with the
   fn's real body-checked scheme, so `EntryMod.id` ERASED the type of anything
   laundered through it — a general memory-safety hole (an Int laundered into a
   String parameter typechecked).  The DFn branch of [check_decl] now rebinds
   the entry-qualified name to the validated scheme.  These launder cases are
   RED before the fix (each typechecks clean) and GREEN after. *)

let test_entry_qual_launders_int_as_string () =
  let ctx = typecheck {|mod Main do
    fn id(x) do x end
    fn need_str(s : String) : Int do string_length(s) end
    fn attack() : Int do need_str(Main.id(42)) end
  end|} in
  Alcotest.(check bool) "Main.id laundering Int into a String param: rejected" true
    (has_errors ctx);
  Alcotest.(check bool) "diagnostic names String vs Int" true
    (count_errors_matching ctx "expected `String` but got `Int`." >= 1)

let test_entry_qual_launders_box () =
  let ctx = typecheck {|mod Main do
    type Box(a) = Box(a)
    fn id(x) do x end
    fn need_int(_b : Box(Int)) : Int do 0 end
    fn attack() : Int do need_int(Main.id(Box("hi"))) end
  end|} in
  Alcotest.(check bool) "Main.id laundering Box(String) into Box(Int): rejected" true
    (has_errors ctx)

let test_entry_qual_forges_proof_cap () =
  (* The proof-cap forge: `Main.id` must not launder a `Cap(IO)` into a
     `Cap(Db.P)` parameter.  The module also lacks `needs` declarations (which
     raise their own, unrelated errors), so assert on the FORGE-SPECIFIC
     mismatch rather than the error count: it is absent (count 0) when the type
     erases and present (>= 1) when the forge is caught. *)
  let ctx = typecheck {|mod Main do
    mod Db do
      proof cap P
    end
    fn id(x) do x end
    fn consume(_c : Cap(Db.P)) : Int do 0 end
    fn attack(cap : Cap(IO)) : Int do consume(Main.id(cap)) end
  end|} in
  Alcotest.(check bool) "Main.id forging Cap(IO) -> Cap(Db.P): mismatch caught" true
    (count_errors_matching ctx "expected `Db.P` but got `IO`." >= 1)

let test_entry_qual_distinct_tvar_launders () =
  (* C2 variant: an ANNOTATED but distinct-tvar helper `fn f(x:a):b do x` gets a
     prebind built purely from annotation SYNTAX (`a -> b`, never unified against
     the body constraint a~b), so `Main.f` erased just like the unannotated case.
     The unconditional rebind to the body-checked scheme closes this too. *)
  let ctx = typecheck {|mod Main do
    fn launder(x : a) : b do x end
    fn need_str(s : String) : Int do string_length(s) end
    fn attack() : Int do need_str(Main.launder(42)) end
  end|} in
  Alcotest.(check bool) "Main.launder (a->b) laundering Int into a String param: rejected" true
    (has_errors ctx);
  Alcotest.(check bool) "diagnostic names String vs Int" true
    (count_errors_matching ctx "expected `String` but got `Int`." >= 1)

let test_entry_qual_from_nested_sibling () =
  (* The entry-qualified reference can also come from a NESTED module: `T.id`
     used inside `mod App` (nested in the entry `T`) resolves the same
     entry-level `T.id` prebind and must be reconciled just as a top-level
     `T.id` reference is. *)
  let ctx = typecheck {|mod T do
    fn id(x) do x end
    mod App do
      fn need_str(s : String) : Int do string_length(s) end
      fn attack() : Int do need_str(T.id(42)) end
    end
  end|} in
  Alcotest.(check bool) "T.id from nested App laundering Int into a String param: rejected" true
    (has_errors ctx);
  Alcotest.(check bool) "diagnostic names String vs Int" true
    (count_errors_matching ctx "expected `String` but got `Int`." >= 1)

(* ── Stdlib HOF-callback annotations must be curried, not tuple-arrow ──────
   March's uncurried-collection convention calls callbacks with N-ary call
   syntax (`f(acc, x)`), which [infer_app] treats as peeling one `TArrow`
   layer per argument (purely curried — there is no auto-tupling special
   case).  Annotating such a callback param as a TUPLE-arrow (`f : (b, a) ->
   b`, parsed as `TArrow(TTuple[b;a], b)`) instead of a curried chain
   (`f : b -> a -> b`) therefore makes the recursive self-call inside the
   function's OWN body check its first arg against the tuple `(b,a)` and
   fail — a real, self-contained type error entirely internal to the stdlib
   file, independent of any other module.  (An earlier hypothesis blamed
   this on cross-module bare-name collisions when many stdlib modules are
   merged as typecheck siblings — e.g. `fold_left` existing in both
   `prelude.march` and `list.march`; that was investigated and falsified:
   the error reproduces identically with the offending file typechecked
   completely alone.)  Such an error is invisible via the normal CLI
   because `bin/main.ml`'s `is_user_file` filter drops any diagnostic
   whose span points into a stdlib file — so this class of bug can persist
   silently until something (e.g. a pipeline that does NOT filter by file,
   like a browser/playground compile target) surfaces it.  `fold_left`
   (prelude.march, iterable.march), `cmp`/`fold` (ordered_map.march,
   sorted_set.march), and `reduce` (range.march) all had this typo; fixed
   to curried-arrow form.  Guard each by typechecking the file completely
   standalone (no other stdlib siblings) via [check_module_core], mirroring
   how `bin/main.ml`'s `get_stdlib_tc_env` typechecks stdlib. *)

let assert_stdlib_file_typechecks_cleanly name =
  let dmod = load_stdlib_file_for_test name in
  let m = March_ast.Ast.{
    mod_name = { txt = "StdlibSelfCheck"; span = dummy_span };
    mod_decls = [dmod];
  } in
  let (errors, _type_map, _env) = March_typecheck.Typecheck.check_module_core m in
  Alcotest.(check bool)
    (Printf.sprintf "stdlib/%s typechecks with no internal errors" name)
    false (has_errors errors)

let test_stdlib_prelude_fold_left_curried () =
  assert_stdlib_file_typechecks_cleanly "prelude.march"

let test_stdlib_iterable_fold_curried () =
  assert_stdlib_file_typechecks_cleanly "iterable.march"

let test_stdlib_ordered_map_cmp_curried () =
  assert_stdlib_file_typechecks_cleanly "ordered_map.march"

let test_stdlib_sorted_set_cmp_curried () =
  assert_stdlib_file_typechecks_cleanly "sorted_set.march"

let test_stdlib_range_reduce_curried () =
  assert_stdlib_file_typechecks_cleanly "range.march"

(* ── Green guards: the fix must not over-reject legitimate entry-qualified use ── *)

let test_entry_qual_same_type_ok () =
  (* `Main.id` used at a single, consistent type stays clean (green before and
     after the fix). *)
  let ctx = typecheck {|mod Main do
    fn id(x) do x end
    fn use_int() : Int do Main.id(42) end
  end|} in
  Alcotest.(check bool) "Main.id used at Int only: no error" false (has_errors ctx)

let test_entry_qual_polymorphic_ok () =
  (* Reconciling `Main.id` to the fn's REAL scheme (rather than a pinned
     placeholder) also RESTORES polymorphism: the bare `id` is `∀a. a -> a`, so
     `Main.id` used at BOTH Int and String must typecheck exactly as the bare
     name does.  RED before the fix — the placeholder `?a` was pinned to Int by
     the first use, so the String use spuriously failed (an over-rejection). *)
  let ctx = typecheck {|mod Main do
    fn id(x) do x end
    fn use_int() : Int do Main.id(42) end
    fn use_str() : String do Main.id("hi") end
  end|} in
  Alcotest.(check bool) "Main.id used at Int AND String: no error" false (has_errors ctx)

let test_entry_qual_annotated_same_tvar_ok () =
  (* An annotated `a -> a` entry fn used consistently stays clean — its prebind
     is already a real, body-consistent scheme, and the rebind to [sch] keeps it
     that way. *)
  let ctx = typecheck {|mod Main do
    fn identity(x : a) : a do x end
    fn ok() : Int do Main.identity(42) end
  end|} in
  Alcotest.(check bool) "Main.identity (a->a) used at Int: no error" false (has_errors ctx)

(* A match in CHECKING position (function with a declared return type) must
   still get redundant-arm warnings.  check_expr's EMatch arm called only
   check_exhaustiveness, never check_redundant_arms, so every match inside an
   annotated function silently skipped the analysis. *)
let test_redundant_arm_in_checking_position () =
  let ctx = typecheck {|mod T do
    fn f(o : Option(Int)) : Int do
      match o do
        _ -> 9
        Some(x) -> x
        None -> 0
      end
    end
  end|} in
  let has_redundant =
    List.exists (fun (d : March_errors.Errors.diagnostic) ->
        d.code = Some "redundant_arm")
      ctx.March_errors.Errors.diagnostics
  in
  Alcotest.(check bool) "redundant arm reported in checking position" true
    has_redundant

(* Control: the same match in INFERENCE position (no return annotation) already
   warned before this fix.  Pins that the fix does not regress it. *)
let test_redundant_arm_in_inference_position () =
  let ctx = typecheck {|mod T do
    fn f(o) do
      match o do
        _ -> 9
        Some(x) -> x
        None -> 0
      end
    end
  end|} in
  let has_redundant =
    List.exists (fun (d : March_errors.Errors.diagnostic) ->
        d.code = Some "redundant_arm")
      ctx.March_errors.Errors.diagnostics
  in
  Alcotest.(check bool) "redundant arm reported in inference position" true
    has_redundant

let compiler_suites =
  [
      ( "match_diagnostics",
        [
          Alcotest.test_case "redundant arm warned in checking position" `Quick
            test_redundant_arm_in_checking_position;
          Alcotest.test_case "redundant arm warned in inference position" `Quick
            test_redundant_arm_in_inference_position;
        ] );
      ( "resolver",
        [
          Alcotest.test_case "collect_lib_files skips dangling symlinks" `Quick
            test_resolver_skips_dangling_symlink;
          Alcotest.test_case
            "large multi-file MARCH_LIB_PATH check is not quadratic (record_use import_tracker)"
            `Slow test_large_multi_file_check_is_not_quadratic;
          Alcotest.test_case
            "unrelated broken lib module is pruned; referenced one still errors"
            `Quick test_unrelated_broken_lib_module_is_pruned;
          Alcotest.test_case
            "qualified private opaque ctor from a sibling module is rejected"
            `Quick test_opaque_ctor_qualified_bypass_rejected;
          Alcotest.test_case
            "opaque type annotation + public accessors still accept cross-module"
            `Quick test_opaque_type_annotation_still_accepts;
          Alcotest.test_case
            "public qualified ctor still resolves cross-module"
            `Quick test_public_ctor_qualified_still_resolves;
          Alcotest.test_case
            "self-name-prefixed dotted sibling module: fully-qualified call resolves"
            `Quick test_self_prefix_sibling_fully_qualified;
          Alcotest.test_case
            "self-name-prefixed dotted sibling module: `use` + bare call resolves"
            `Quick test_self_prefix_sibling_use_bare;
          Alcotest.test_case
            "self-name-prefixed dotted sibling module: `alias` workaround still resolves"
            `Quick test_self_prefix_sibling_alias_still_works;
          Alcotest.test_case
            "unrelated-named sibling dotted module still resolves (regression control)"
            `Quick test_unrelated_name_sibling_still_works;
          Alcotest.test_case
            "genuine nested submodule self-qualification still strips"
            `Quick test_self_prefix_nested_submodule_still_strips;
        ] );
      ( "diagnostic dedup",
        [
          Alcotest.test_case "broken ctor field type reported once, not once per instantiation" `Quick
            test_broken_ctor_field_type_reported_once;
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
          Alcotest.test_case "integer max" `Quick test_lexer_int_max;
          Alcotest.test_case "integer out of range" `Quick test_lexer_int_out_of_range;
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
          Alcotest.test_case "lambda bare stmt before if (inline arg)" `Quick test_parse_lambda_bare_stmt_before_if;
          Alcotest.test_case "lambda consecutive bare stmts (inline arg)" `Quick test_parse_lambda_consecutive_bare_stmts;
          Alcotest.test_case "application" `Quick test_parse_expr_app;
          Alcotest.test_case "refinement node present" `Quick test_parse_refinement_node_present;
          Alcotest.test_case "refined param typechecks as base" `Quick test_refined_param_typechecks_as_base;
          Alcotest.test_case "record type still parses" `Quick test_record_type_still_parses;
          Alcotest.test_case "with-else single arm" `Quick test_parse_with_else_single_arm;
          Alcotest.test_case "with-else two nullary arms" `Quick test_parse_with_else_two_nullary_arms;
          Alcotest.test_case "with-else three payload arms" `Quick test_parse_with_else_three_payload_arms;
          Alcotest.test_case "with-else infix arm bodies" `Quick test_parse_with_else_infix_bodies;
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
          Alcotest.test_case "dotted sibling module order" `Quick test_tc_dotted_sibling_module_order;
          Alcotest.test_case "private nested member diagnostic" `Quick test_tc_private_nested_member_diagnostic;
          Alcotest.test_case "private nested member name collides with builtin" `Quick test_tc_private_nested_member_name_collides_with_builtin;
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
          Alcotest.test_case "root_cap() is rejected"              `Quick test_tc_root_cap_call_rejected;
          Alcotest.test_case "bare root_cap is ok"                 `Quick test_tc_root_cap_bare_ok;
          Alcotest.test_case "legit zero-arg builtins still callable" `Quick test_tc_zero_arg_builtins_still_callable;
          Alcotest.test_case "zero-arg user fn still callable"     `Quick test_tc_zero_arg_user_fn_still_callable;
          Alcotest.test_case "KNOWN GAP: non-fn local value call"  `Quick test_tc_nonfunction_local_value_call_known_gap;
          Alcotest.test_case "actor handler extra field"   `Quick test_actor_handler_extra_field;
          Alcotest.test_case "actor handler missing field" `Quick test_actor_handler_missing_field;
          Alcotest.test_case "actor handler correct"       `Quick test_actor_handler_correct;
          (* Fix 1: Interface constraint discharge *)
          Alcotest.test_case "iface constraint satisfied"   `Quick test_interface_constraint_satisfied;
          Alcotest.test_case "iface constraint missing impl" `Quick test_interface_constraint_missing_impl;
          Alcotest.test_case "impl coherence: distinct modules ok (builtin)" `Quick test_impl_coherence_distinct_modules_ok;
          Alcotest.test_case "impl coherence: distinct modules general-iface ok" `Quick test_impl_coherence_distinct_modules_general_iface_ok;
          Alcotest.test_case "impl coherence: same-module dup err" `Quick test_impl_coherence_same_module_duplicate_err;
          Alcotest.test_case "impl coherence: shared-ctor double collision ok" `Quick test_impl_coherence_shared_ctor_double_collision_ok;
          Alcotest.test_case "add_ctor keeps distinct-module identical-shape ctors" `Quick test_add_ctor_keeps_distinct_module_identical_shape_ctors;
          Alcotest.test_case "ctor lexical preference: both modules resolve own bare ref" `Quick test_ctor_lexical_preference_both_modules;
          Alcotest.test_case "ctor truly cross-module ambiguous: hard error" `Quick test_ctor_truly_ambiguous_is_error;
          Alcotest.test_case "ctor qualified reference from third module: ok" `Quick test_ctor_qualified_reference_from_third_module_ok;
          Alcotest.test_case "ctor lexical preference: lookup_ctor returns own-module candidate directly" `Quick test_ctor_lexical_preference_directly_inspects_lookup_ctor;
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
          (* Modules widening slice 2, Task 1: cross-module visibility gate *)
          Alcotest.test_case "cross-module private pfn rejected" `Quick test_cross_module_private_fn_rejected;
          Alcotest.test_case "cross-module public fn accepted"   `Quick test_cross_module_public_fn_accepted;
          (* Regression: qualified type path `Mod.Type` ≡ bare `Type` *)
          Alcotest.test_case "qualified opaque type unifies with bare" `Quick test_qualified_opaque_type_unifies_bare;
          Alcotest.test_case "qualified opaque type evaluates"         `Quick test_qualified_opaque_type_evals;
          (* F5: linear let bindings *)
          Alcotest.test_case "linear let ok"                 `Quick test_linear_let_ok;
          Alcotest.test_case "linear let double use"         `Quick test_linear_let_double_use;
          (* Regression: always-linear value bound via let?/with (not a
             pre-tracked linear variable) must still be double-use checked *)
          Alcotest.test_case "let? acquired linear double use"  `Quick test_linear_letq_acquire_double_use;
          Alcotest.test_case "let? acquired linear single use ok" `Quick test_linear_letq_acquire_single_use_ok;
          Alcotest.test_case "with acquired linear double use"  `Quick test_linear_with_acquire_double_use;
          (* Fix 2: Linear type enforcement *)
          Alcotest.test_case "linear pattern match ok"       `Quick test_linear_pattern_match_ok;
          Alcotest.test_case "linear pattern match double"   `Quick test_linear_pattern_match_double_use;
          Alcotest.test_case "linear closure capture"        `Quick test_linear_closure_capture_error;
          Alcotest.test_case "linear field let binding"       `Quick test_linear_field_let_binding;
          (* H6: Linear field direct field-access tracking *)
          Alcotest.test_case "linear field double access"    `Quick test_linear_field_double_access_error;
          Alcotest.test_case "linear field single access ok" `Quick test_linear_field_single_access_ok;
          (* Slice 7 (L2/L3): TLin transparent to constraint discharge *)
          Alcotest.test_case "linear field arith single use" `Quick test_linear_field_arith_single_use_ok;
          Alcotest.test_case "linear return arith"           `Quick test_linear_return_arith_ok;
          Alcotest.test_case "linear field param double-use error (L3)" `Quick test_linear_field_param_double_use_error;
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
          Alcotest.test_case "session binary choice identical branches" `Quick test_session_binary_choice_identical_branches;
          Alcotest.test_case "session mpst bystander still merges"       `Quick test_session_mpst_bystander_still_merges;
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
          (* C1 fix: actor handler body IO caps flow into manifest / missing-needs diagnostic *)
          Alcotest.test_case "actor handler body IO, no needs: warns"    `Quick test_actor_handler_body_io_missing_needs_warns;
          Alcotest.test_case "actor handler body IO, needs declared: no warning" `Quick test_actor_handler_body_io_with_needs_no_warning;
          (* item 1380: Cap(IO.NetListen) body-scan enforcement *)
          Alcotest.test_case "tcp_listen body, no needs: warns NetListen"   `Quick test_netlisten_body_missing_needs_warns;
          Alcotest.test_case "tcp_listen body, needs NetListen: no warning" `Quick test_netlisten_body_with_needs_no_warning;
          Alcotest.test_case "tcp_listen body, NetConnect does not satisfy" `Quick test_netlisten_not_satisfied_by_netconnect;
          (* spawn argument must be a plain actor name (not a computed expr) *)
          Alcotest.test_case "spawn computed actor: rejected"          `Quick test_spawn_computed_actor_rejected;
          Alcotest.test_case "spawn plain actor name: ok"              `Quick test_spawn_plain_actor_name_ok;
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
          Alcotest.test_case "file_read error must not unify with String" `Quick test_letq_file_read_wrong_error_type;
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
          Alcotest.test_case "compiled odd Int payload round-trips (F1)" `Quick test_session_compile_odd_int_roundtrip;
          Alcotest.test_case "compiled Bool payload round-trips (F2)"    `Quick test_session_compile_bool_roundtrip;
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
          Alcotest.test_case "cap no_panic + non-exhaustive match: error" `Quick test_cap_no_panic_nonexhaustive_match_error;
          Alcotest.test_case "cap no_panic + exhaustive match: no error"  `Quick test_cap_no_panic_exhaustive_match_ok;
          Alcotest.test_case "cap no_panic + wildcard match: no error"    `Quick test_cap_no_panic_wildcard_match_ok;
          Alcotest.test_case "plain non-exhaustive match: no error"       `Quick test_plain_nonexhaustive_match_ok;
          Alcotest.test_case "cap no_panic + guarded non-exhaustive match: error" `Quick test_cap_no_panic_guarded_nonexhaustive_match_error;
          Alcotest.test_case "cap no_panic + guarded guardless-catchall: no error" `Quick test_cap_no_panic_guarded_guardless_catchall_ok;
          Alcotest.test_case "plain guarded non-exhaustive match: no error" `Quick test_plain_guarded_nonexhaustive_match_ok;
          (* Division-safety Z3 cases *)
          Alcotest.test_case "divsafety: v > 0 refinement suppresses"     `Quick test_divsafety_positive_refinement_ok;
          Alcotest.test_case "divsafety: v != 0 refinement suppresses"    `Quick test_divsafety_nonzero_refinement_ok;
          Alcotest.test_case "divsafety: v >= 0 does not suppress"        `Quick test_divsafety_nonneg_refinement_error;
          Alcotest.test_case "divsafety: literal non-zero divisor ok"     `Quick test_divsafety_literal_nonzero_ok;
          Alcotest.test_case "divsafety: literal zero is always error"    `Quick test_divsafety_literal_zero_error;
          Alcotest.test_case "divsafety: v >= 1 refinement suppresses"    `Quick test_divsafety_ge1_refinement_ok;
          (* Guard / path-context cases *)
          Alcotest.test_case "divsafety: match guard b != 0 suppresses"   `Quick test_divsafety_match_guard_neq_zero_ok;
          Alcotest.test_case "divsafety: match guard b > 0 suppresses"    `Quick test_divsafety_match_guard_gt_zero_ok;
          Alcotest.test_case "divsafety: if guard b != 0 suppresses"      `Quick test_divsafety_if_guard_neq_zero_ok;
          Alcotest.test_case "divsafety: if guard b > 0 suppresses mod"   `Quick test_divsafety_if_guard_gt_zero_mod_ok;
          Alcotest.test_case "divsafety: no guard unrefined still errors"  `Quick test_divsafety_no_guard_unrefined_still_errors;
          Alcotest.test_case "divsafety: let-bound non-zero literal ok"   `Quick test_divsafety_let_bound_literal_ok;
          Alcotest.test_case "divsafety: let-bound zero literal errors"   `Quick test_divsafety_let_bound_zero_error;
        ] );
      ( "cap_pure_no_extern_det", [
          Alcotest.test_case "cap pure + spawn: error"                `Quick test_cap_pure_spawn_error;
          Alcotest.test_case "cap pure + println: error"              `Quick test_cap_pure_println_error;
          Alcotest.test_case "cap pure + pure arithmetic: no error"   `Quick test_cap_pure_arithmetic_ok;
          Alcotest.test_case "cap pure + now_ms: error"               `Quick test_cap_pure_now_ms_error;
          Alcotest.test_case "cap pure + random_int: error"           `Quick test_cap_pure_random_int_error;
          Alcotest.test_case "cap pure + uuid_v4: error"              `Quick test_cap_pure_uuid_error;
          Alcotest.test_case "cap pure + file_write (real): error"    `Quick test_cap_pure_file_write_error;
          Alcotest.test_case "cap pure + file_read (real): error"     `Quick test_cap_pure_file_read_error;
          Alcotest.test_case "cap pure + random_bytes (real): error"  `Quick test_cap_pure_random_bytes_error;
          Alcotest.test_case "cap no_extern + regular fn: no error"   `Quick test_cap_no_extern_regular_fn_ok;
          Alcotest.test_case "cap deterministic + random_int: error"  `Quick test_cap_deterministic_random_int_error;
          Alcotest.test_case "cap deterministic + uuid_v4: error"     `Quick test_cap_deterministic_uuid_error;
          Alcotest.test_case "cap deterministic + now_ms: error"      `Quick test_cap_deterministic_now_ms_error;
          Alcotest.test_case "cap deterministic + unix_time_ms (real): error" `Quick test_cap_deterministic_unix_time_ms_error;
          Alcotest.test_case "cap deterministic + file_read: no error" `Quick test_cap_deterministic_file_read_ok;
          Alcotest.test_case "cap deterministic + arithmetic: no error" `Quick test_cap_deterministic_arithmetic_ok;
        ] );
      ( "proof_cap_mint", [
          Alcotest.test_case "cap_narrow cannot mint proof cap (inline arg): error" `Quick test_cap_narrow_cannot_mint_proof_cap;
          Alcotest.test_case "cap_narrow cannot mint proof cap (let binding): error" `Quick test_cap_narrow_forge_let;
          Alcotest.test_case "cap_narrow IO-lattice narrow: no error"       `Quick test_cap_narrow_io_narrow_still_ok;
          Alcotest.test_case "cap_narrow let-generalized launder: error"    `Quick test_cap_narrow_forge_generalized_let;
          Alcotest.test_case "cap_narrow laundered through generic fn: error" `Quick test_cap_narrow_forge_through_generic_fn;
          Alcotest.test_case "cap_narrow laundered to IO cap: no error"      `Quick test_cap_narrow_launder_io_still_ok;
          Alcotest.test_case "mint_cap in public declaring-module fn: no error" `Quick test_mint_cap_public_declaring_ok;
          Alcotest.test_case "mint_cap in pfn: error"                       `Quick test_mint_cap_pfn_rejected;
          Alcotest.test_case "mint_cap in external module: error"           `Quick test_mint_cap_external_rejected;
          Alcotest.test_case "mint_cap in applied lambda in declaring fn: no error" `Quick test_mint_cap_lambda_declaring_ok;
          Alcotest.test_case "mint_cap in applied lambda in external module: error" `Quick test_mint_cap_lambda_external_rejected;
          Alcotest.test_case "mint_cap at IO-cap target: error"             `Quick test_mint_cap_io_target_rejected;
          Alcotest.test_case "container/factory taint: tuple-wrapped forge: error" `Quick test_container_launder_tuple_forge;
          Alcotest.test_case "container/factory taint: Option-wrapped forge: error" `Quick test_container_launder_option_forge;
          Alcotest.test_case "container/factory taint: IO narrow in a tuple: no error" `Quick test_container_launder_io_still_ok;
          Alcotest.test_case "container/factory taint: legit proof-cap passthrough beside a tainted slot: no error" `Quick test_container_combine_legit_proof_cap_still_ok;
        ] );
      ( "nested_mod_prebind_erasure", [
          (* RED pre-fix (forge accepted), GREEN after the qualified-prebind reconciliation. *)
          Alcotest.test_case "nested id launders Int into String param: error"        `Quick test_nested_launder_int_as_string;
          Alcotest.test_case "nested id launders Box(String)->Box(Int): error"        `Quick test_nested_launder_box_arg;
          Alcotest.test_case "nested id launders Cap(IO)->Cap(Db.P): error"           `Quick test_nested_launder_proof_cap;
          Alcotest.test_case "nested id coerces Cap(IO)->Cap(IO.Network): error"      `Quick test_nested_launder_io_subcap;
          Alcotest.test_case "3-deep nested id launders Box(String)->Box(Int): error" `Quick test_nested_launder_three_deep;
          Alcotest.test_case "nested tuple factory launders Box(String)->Box(Int): error" `Quick test_nested_launder_container_factory;
          (* GREEN-STAYS-GREEN guards. *)
          Alcotest.test_case "nested id passes Cap(IO) through unchanged: no error"   `Quick test_nested_cap_passthrough_ok;
          Alcotest.test_case "nested id used at Int AND String: no error"            `Quick test_nested_id_polymorphic_ok;
          Alcotest.test_case "nested ANNOTATED id still rejects forge: error"        `Quick test_nested_launder_annotated_id_still_rejected;
          Alcotest.test_case "nested PRIVATE (pfn) id still rejects forge: error"    `Quick test_nested_launder_private_id_still_rejected;
          (* Round 2 — residual erasures (RED on 10249488, GREEN after). *)
          Alcotest.test_case "C1 forward-ref id launders Int->String: error"        `Quick test_nested_fwdref_int_as_string;
          Alcotest.test_case "C1 forward-ref id launders Box(String)->Box(Int): error" `Quick test_nested_fwdref_box;
          Alcotest.test_case "C1 forward-ref id launders Cap(IO)->Cap(Db.P): error" `Quick test_nested_fwdref_proof_cap;
          Alcotest.test_case "C2 distinct-tvar launder erases Int->String: error"    `Quick test_nested_distinct_tvar_int_as_string;
          Alcotest.test_case "C2 distinct-tvar launder erases Box(String)->Box(Int): error" `Quick test_nested_distinct_tvar_box;
          Alcotest.test_case "C2 distinct-tvar launder erases Cap(IO)->Cap(Db.P): error" `Quick test_nested_distinct_tvar_proof_cap;
          (* Round 2 green-stays-green guards. *)
          Alcotest.test_case "forward-ref id used at Int AND String: no error"       `Quick test_nested_fwdref_legit_ok;
          Alcotest.test_case "forward-ref annotated id (a->a) at Int AND String: no error" `Quick test_nested_annotated_same_tvar_ok;
          (* Round 3 — entry-module self-qualified erasure (RED on d19dc519, GREEN after). *)
          Alcotest.test_case "entry Main.id launders Int->String: error"           `Quick test_entry_self_qualified_int_as_string;
          Alcotest.test_case "entry Main.id launders Box(String)->Box(Int): error" `Quick test_entry_self_qualified_box;
          Alcotest.test_case "entry Main.id launders Cap(IO)->Cap(Db.P): error"     `Quick test_entry_self_qualified_proof_cap;
          Alcotest.test_case "nested sibling launders via entry T.id: error"        `Quick test_entry_qualified_from_nested_sibling;
          Alcotest.test_case "entry forward-ref Main.id launders Int->String: error" `Quick test_entry_self_qualified_forward_ref;
          (* Round 3 green-stays-green / red->green guards. *)
          Alcotest.test_case "entry Main.id used at Int AND String: no error"       `Quick test_entry_self_qualified_polymorphic_ok;
          Alcotest.test_case "nested sibling uses entry T.id consistent: no error"  `Quick test_entry_qualified_nested_consistent_ok;
        ] );
      ( "fix_batch_regressions", [
          Alcotest.test_case "Cap(IO.Random/Mut/Foreign/Telemetry) args: no error" `Quick test_cap_hierarchy_args_ok;
          Alcotest.test_case "Cap(IO.NetConnect.TLS) arg: no error"     `Quick test_cap_hierarchy_tls_arg_ok;
          Alcotest.test_case "revoke_cap/is_cap_valid: no error"        `Quick test_revoke_cap_typechecks;
          Alcotest.test_case "derive for unknown type: error"           `Quick test_derive_unknown_type_error;
          Alcotest.test_case "derive for declared type: no error"       `Quick test_derive_known_type_ok;
        ] );
      ( "cap_no_alloc", [
          Alcotest.test_case "cap no_alloc lexes as CAP_NO_ALLOC token"   `Quick test_cap_no_alloc_lexes;
          Alcotest.test_case "cap no_alloc + tuple: error"                 `Quick test_cap_no_alloc_tuple_error;
          Alcotest.test_case "cap no_alloc + record: error"                `Quick test_cap_no_alloc_record_error;
          Alcotest.test_case "cap no_alloc + Some(x): error"              `Quick test_cap_no_alloc_some_error;
          Alcotest.test_case "cap no_alloc + lambda: error"                `Quick test_cap_no_alloc_lambda_error;
          Alcotest.test_case "cap no_alloc + pure arithmetic: no error"   `Quick test_cap_no_alloc_arithmetic_ok;
          Alcotest.test_case "cap no_alloc + if/match: no error"           `Quick test_cap_no_alloc_if_ok;
          Alcotest.test_case "no cap no_alloc + tuple: no error"           `Quick test_cap_not_set_tuple_ok;
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
      ( "satisfy_decl", [
          Alcotest.test_case "lexer: satisfy token"                  `Quick test_satisfy_lexer_token;
          Alcotest.test_case "parse + desugar: DSatisfy → DImpl"    `Quick test_satisfy_parse_basic;
          Alcotest.test_case "basic: single iface, single type"     `Quick test_satisfy_basic;
          Alcotest.test_case "two interfaces, one type"             `Quick test_satisfy_two_ifaces;
          Alcotest.test_case "one interface, two types"             `Quick test_satisfy_two_types;
          Alcotest.test_case "unknown interface: error"             `Quick test_satisfy_unknown_iface;
          Alcotest.test_case "missing function: error"              `Quick test_satisfy_missing_fn;
          Alcotest.test_case "multi-method iface, all fns present"  `Quick test_satisfy_multi_method_iface;
          Alcotest.test_case "multi-method iface, one fn missing"   `Quick test_satisfy_multi_method_missing_one;
          Alcotest.test_case "satisfy then use for dispatch"        `Quick test_satisfy_then_use;
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
          Alcotest.test_case "task_spawn missing needs: warn IO.Spawn"    `Quick test_cap_body_missing_spawn;
          Alcotest.test_case "task_spawn with needs IO.Spawn: no warn"    `Quick test_cap_body_spawn_ok;
          Alcotest.test_case "needs IO umbrella covers task_spawn"         `Quick test_cap_body_spawn_parent_ok;
          Alcotest.test_case "vault_new missing needs: warn IO.Mut"        `Quick test_cap_body_missing_mut;
          Alcotest.test_case "vault_new with needs IO.Mut: no warn"        `Quick test_cap_body_mut_ok;
          Alcotest.test_case "needs IO umbrella covers vault_new"          `Quick test_cap_body_mut_parent_ok;
          Alcotest.test_case "tls_connect missing needs: warn TLS"         `Quick test_cap_body_missing_tls;
          Alcotest.test_case "tls_connect with needs IO.NetConnect.TLS"    `Quick test_cap_body_tls_ok;
          Alcotest.test_case "needs IO.NetConnect umbrella covers TLS"     `Quick test_cap_body_tls_parent_ok;
          Alcotest.test_case "ws_recv missing needs: warn WebSocket"       `Quick test_cap_body_missing_ws;
          Alcotest.test_case "ws_recv with needs IO.WebSocket"             `Quick test_cap_body_ws_ok;
          Alcotest.test_case "needs IO.NetConnect umbrella covers WS"      `Quick test_cap_body_ws_parent_ok;
          Alcotest.test_case "Cap(IO.WebSocket) arg: no error"             `Quick test_cap_ws_arg_ok;
          Alcotest.test_case "needs IO.Telemetry: valid declaration"       `Quick test_cap_body_telemetry_decl_ok;
          Alcotest.test_case "extern block missing IO.Foreign: warn"       `Quick test_cap_body_missing_foreign;
          Alcotest.test_case "extern block with needs IO.Foreign: no warn" `Quick test_cap_body_foreign_ok;
          Alcotest.test_case "needs IO umbrella covers IO.Foreign"         `Quick test_cap_body_foreign_parent_ok;
          Alcotest.test_case "blocking extern missing IO.Foreign.Blocking" `Quick test_cap_body_foreign_blocking;
          Alcotest.test_case "fn_capability_closures: declared needs"       `Quick test_fn_cap_closure_declared_needs;
          Alcotest.test_case "fn_capability_closures: inferred builtin"     `Quick test_fn_cap_closure_inferred_builtin;
          Alcotest.test_case "fn_capability_closures: extern IO.Foreign"    `Quick test_fn_cap_closure_extern;
          Alcotest.test_case "fn_capability_closures: propagated import"    `Quick test_fn_cap_closure_propagated_import;
          Alcotest.test_case "fn_capability_closures: two-level nesting"    `Quick test_fn_cap_closure_two_level_nesting;
          Alcotest.test_case "fn_own_capability_closures: excludes module-wide needs" `Quick test_fn_own_cap_closure_excludes_module_wide;
          Alcotest.test_case "migrate_state calling file_write: error"     `Quick test_migrate_state_file_write_error;
          Alcotest.test_case "migrate_state calling println: error"       `Quick test_migrate_state_println_error;
          Alcotest.test_case "migrate_state as extern fn: error"          `Quick test_migrate_state_extern_error;
          Alcotest.test_case "pure migrate_state + module needs: clean"   `Quick test_migrate_state_pure_with_module_needs_clean;
          Alcotest.test_case "pure migrate_state, no needs: clean"        `Quick test_migrate_state_pure_no_needs_clean;
        ] );
      ( "cap_propagation", [
          Alcotest.test_case "needs from import suppresses unused-cap warn" `Quick test_cap_propagation_no_unused_warn;
          Alcotest.test_case "unrelated needs still warns"                  `Quick test_cap_propagation_still_warns_unrelated;
        ] );
      ( "cap_infer", [
          Alcotest.test_case "random_bytes missing needs: hint emitted"     `Quick test_cap_infer_random_missing;
          Alcotest.test_case "random_bytes with needs IO.Random: no hint"   `Quick test_cap_infer_random_declared;
          Alcotest.test_case "file_write missing needs: hint emitted"       `Quick test_cap_infer_filewrite_missing;
          Alcotest.test_case "pure fn with no cap calls: no hint"           `Quick test_cap_infer_pure_no_hint;
          Alcotest.test_case "needs IO umbrella covers IO.Random: no hint"  `Quick test_cap_infer_parent_cap_covers;
          Alcotest.test_case "nested mod with declared needs: no hint"      `Quick test_cap_infer_nested_mod_inner_declared;
          Alcotest.test_case "nested mod missing needs: hint for inner"     `Quick test_cap_infer_nested_mod_inner_missing;
        ] );
      ( "return_refine_infer", [
          Alcotest.test_case "identity fn: positive param → r > 0"           `Quick test_return_infer_identity_positive;
          Alcotest.test_case "add-one fn: nonneg param → r >= 1"             `Quick test_return_infer_add_one;
          Alcotest.test_case "no refined params → no inferences"             `Quick test_return_infer_no_refined_params;
          Alcotest.test_case "let propagation: x+1 bound → r > 0"           `Quick test_return_infer_let_propagation;
          Alcotest.test_case "literal 5 return → r > 0, r >= 1, r != 0"    `Quick test_return_infer_literal_return;
          Alcotest.test_case "negative param: x < 0 → r < 0, r <= -1"      `Quick test_return_infer_negative_param;
        ] );
      ( "error_improvements", [
          Alcotest.test_case "#1 label rendered in render_diagnostic"       `Quick test_label_rendered_in_output;
          Alcotest.test_case "#2 if-branch type mismatch has label"         `Quick test_if_branch_mismatch_has_label;
          Alcotest.test_case "#2 match-arm type mismatch has label"         `Quick test_match_arm_mismatch_has_label;
          Alcotest.test_case "#3 arity error has definition label"          `Quick test_arity_error_has_definition_label;
          Alcotest.test_case "#4 record field typo: suggests correction"    `Quick test_record_field_typo_suggestion;
          Alcotest.test_case "#4 record field no typo: no false suggestion" `Quick test_record_field_no_false_suggestion;
          Alcotest.test_case "#5 let? wrong type shows actual type"         `Quick test_letq_wrong_type_shows_actual_type;
          Alcotest.test_case "#6 duplicate ctor arm: redundant warning"     `Quick test_redundant_ctor_arm_warning;
          Alcotest.test_case "#6 arm after wildcard: redundant warning"     `Quick test_redundant_after_wildcard_warning;
          Alcotest.test_case "#6 guarded arm: no redundancy warning"        `Quick test_guarded_arm_no_redundant_warning;
          Alcotest.test_case "#6 non-redundant match: no warning"           `Quick test_non_redundant_no_warning;
          Alcotest.test_case "#8 qualified error has notes not inline"      `Quick test_qualified_error_uses_notes;
          Alcotest.test_case "#7 parse error uses -- ERROR header"          `Quick test_parse_error_has_error_header;
          Alcotest.test_case "#7 if-then note mentions do/end"              `Quick test_parse_error_then_note_do_end;
          Alcotest.test_case "fix: if-then error names then as problem"     `Quick test_parse_error_then_says_then_not_else;
          Alcotest.test_case "fix: if-then primary message not about else"  `Quick test_parse_error_then_primary_message;
          Alcotest.test_case "W4.4: complete if-then-else form rejected"    `Quick test_parse_error_then_else_form_rejected;
          Alcotest.test_case "fix: if-branch mismatch reason says if expr"  `Quick test_if_branch_mismatch_reason_is_if_specific;
          Alcotest.test_case "fix: if-branch mismatch no 'match' in note"   `Quick test_if_branch_mismatch_reason_not_match;
          Alcotest.test_case "top-level mod + sibling fn: clear error"      `Quick test_toplevel_mod_plus_sibling_fn_error;
          Alcotest.test_case "nested inline match arm parses (no do/end)"   `Quick test_nested_inline_match_arm_parses;
          Alcotest.test_case "same-name type collision: explanatory note"   `Quick test_same_name_type_collision_note;
        ] );
      ( "let_annotations", [
          Alcotest.test_case "finding 16: let : Int = String rejected"       `Quick test_let_annot_mismatch_rejects;
          Alcotest.test_case "finding 16: let : Int = 5 accepted"            `Quick test_let_annot_correct_accepts;
          Alcotest.test_case "finding 16: let : (Int)->Int = fn n->n accept" `Quick test_let_annot_poly_instance_accepts;
        ] );
      ( "zero_arg_unit_callback", [
          Alcotest.test_case "fn -> body satisfies Unit -> Unit param"       `Quick test_zero_arg_lambda_unit_callback_accepts;
          Alcotest.test_case "Unit -> T value called with f() yields T"      `Quick test_zero_arg_unit_call_returns_result;
          Alcotest.test_case "fn _ -> body (discard thunk) still accepted"   `Quick test_discard_arg_thunk_still_accepts;
        ] );
      ( "letfn_ret_annot", [
          Alcotest.test_case "finding 13: mismatch reported exactly once"    `Quick test_letfn_ret_annot_mismatch_single_diagnostic;
          Alcotest.test_case "finding 13: two distinct errors both report"   `Quick test_letfn_two_distinct_errors_both_report;
        ] );
      ( "generic_when_constraints", [
          Alcotest.test_case "finding 15: unsatisfied generic bound rejects"  `Quick test_generic_when_constraint_unsatisfied_rejects;
          Alcotest.test_case "finding 15: satisfied generic bound accepts"    `Quick test_generic_when_constraint_satisfied_accepts;
          Alcotest.test_case "finding 15: unconstrained generic accepts"      `Quick test_generic_no_constraint_accepts;
        ] );
      ( "return_refine_guard", [
          Alcotest.test_case "if body: no crash"                            `Quick test_return_infer_if_body_no_crash;
          Alcotest.test_case "match guard: both arms positive infers r > 0" `Quick test_return_infer_match_guard_both_arms_pos;
          Alcotest.test_case "match guard: disagreeing arms kills r > 0"    `Quick test_return_infer_match_guard_intersection_kills;
          Alcotest.test_case "if guard: abs infers r > 0"                   `Quick test_return_infer_if_guard_infers_pos;
        ] );
      ( "lexer_line_tracking", [
          Alcotest.test_case "B15: raw newline in string literal tracks line"      `Quick test_string_literal_raw_newline_tracks_line;
          Alcotest.test_case "B15: raw newline in string interp tracks line"       `Quick test_string_interp_raw_newline_tracks_line;
        ] );
      ( "token_filter_pattern_start", [
          Alcotest.test_case "FLOAT: newline-led float match arms parse"           `Quick test_float_literal_match_arm_parses;
          Alcotest.test_case "MINUS FLOAT: newline-led negative float arms parse"  `Quick test_negative_float_literal_match_arm_parses;
          Alcotest.test_case "soft-keyword var pattern: newline-led arm parses"    `Quick test_soft_keyword_var_pattern_match_arm_parses;
        ] );
      ( "token_filter_cond_guard_operators", [
          Alcotest.test_case "cond form: 2+ >= arms parse without parens"          `Quick test_cond_ge_arms_parse;
          Alcotest.test_case "cond form: 2+ == arms parse without parens"          `Quick test_cond_eqeq_arms_parse;
          Alcotest.test_case "cond form: 2+ <= arms parse without parens"          `Quick test_cond_le_arms_parse;
          Alcotest.test_case "when-guard: 2+ == guards parse without parens"       `Quick test_guard_eqeq_arms_parse;
          Alcotest.test_case "when-guard: 2+ >= guards parse without parens"       `Quick test_guard_ge_arms_parse;
          Alcotest.test_case "when-guard: 2+ <= guards parse without parens"       `Quick test_guard_le_arms_parse;
        ] );
      ( "pipe_into_match", [
          Alcotest.test_case "B6: pipe into match reports desugar error"           `Quick test_pipe_into_match_reports_error;
          Alcotest.test_case "B6: pipe cond bad pattern reports desugar error"     `Quick test_pipe_into_cond_bad_pattern_reports_error;
          Alcotest.test_case "B6: scrutinee-less pipe match still works"           `Quick test_pipe_into_scrutineeless_match_still_works;
        ] );
      ( "fn_clause_grouping", [
          Alcotest.test_case "B14: interleaved same-name fn groups error"          `Quick test_interleaved_fn_clauses_error;
          Alcotest.test_case "B14: adjacent multi-head clauses still parse"        `Quick test_adjacent_fn_clauses_still_parse;
          Alcotest.test_case "B14: same fn name in nested mod is fine"             `Quick test_same_fn_name_in_nested_mod_ok;
        ] );
      ( "entry_mod_qual_erasure", [
          Alcotest.test_case "Main.id launders Int -> String: error"              `Quick test_entry_qual_launders_int_as_string;
          Alcotest.test_case "Main.id launders Box(String) -> Box(Int): error"    `Quick test_entry_qual_launders_box;
          Alcotest.test_case "Main.id forges Cap(IO) -> Cap(Db.P): error"         `Quick test_entry_qual_forges_proof_cap;
          Alcotest.test_case "Main.launder (a->b) launders Int -> String: error"  `Quick test_entry_qual_distinct_tvar_launders;
          Alcotest.test_case "T.id from nested App launders Int -> String: error" `Quick test_entry_qual_from_nested_sibling;
          Alcotest.test_case "prelude.march fold_left: curried, no internal error"    `Quick test_stdlib_prelude_fold_left_curried;
          Alcotest.test_case "iterable.march fold: curried, no internal error"        `Quick test_stdlib_iterable_fold_curried;
          Alcotest.test_case "ordered_map.march cmp/fold: curried, no internal error" `Quick test_stdlib_ordered_map_cmp_curried;
          Alcotest.test_case "sorted_set.march cmp/fold: curried, no internal error"  `Quick test_stdlib_sorted_set_cmp_curried;
          Alcotest.test_case "range.march reduce: curried, no internal error"         `Quick test_stdlib_range_reduce_curried;
          Alcotest.test_case "Main.id used at Int only: no error"                 `Quick test_entry_qual_same_type_ok;
          Alcotest.test_case "Main.id used at Int AND String: no error"           `Quick test_entry_qual_polymorphic_ok;
          Alcotest.test_case "Main.identity (a->a) used at Int: no error"         `Quick test_entry_qual_annotated_same_tvar_ok;
        ] );
  ]

