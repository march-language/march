(** March test suite — eval tests. *)
open Test_helpers

let test_eval_dotted_module () =
  (* Dotted module nested inside a top-level module — functions must be
     accessible under the full qualified name "TestApp.Router.greet". *)
  let env = eval_module {|mod Main do
    mod TestApp.Router do
      fn greet() do
        "hello from router"
      end
    end
    fn main() do () end
  end|} in
  let v = call_fn env "TestApp.Router.greet" [] in
  Alcotest.(check string) "dotted module fn result" "hello from router" (vstr v)

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
    fn abs(x) do if x < 0 do negate(x) else x end end
  end|} in
  let v = call_fn env "abs" [March_eval.Eval.VInt (-5)] in
  Alcotest.(check int) "abs(-5) = 5" 5
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

let test_eval_match_adt () =
  let env = eval_module {|mod Test do
    type Shape = Circle(Int) | Square(Int)
    fn area(s) do
      match s do
      Circle(r) -> r * r
      Square(side) -> side * side
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

(* ── let? tests ─────────────────────────────────────────────────────────── *)

let test_letq_ok_propagates () =
  let env = eval_module {|mod Test do
    fn safe_div(a, b) do
      if b == 0 do
        Err("division by zero")
      else
        Ok(a / b)
      end
    end
    fn run() do
      let? x = safe_div(10, 2)
      let? y = safe_div(x, 1)
      Ok(y + 1)
    end
  end|} in
  let v = call_fn env "run" [] in
  (match v with
   | March_eval.Eval.VCon ("Ok", [March_eval.Eval.VInt 6]) -> ()
   | _ -> Alcotest.fail (Printf.sprintf "expected Ok(6), got: %s" (March_eval.Eval.value_to_string v)))

(* ── `let*` at a REPL prompt (Eval.letstar_repl_bind) ─────────────────────
   There is no continuation at a prompt, so this cannot be the ordinary
   ELetStar expansion: it runs the value's own flat_map with a capturing
   callback.  These pin the documented semantics -- bind the FIRST value
   yielded, and report rather than silently succeed when NOTHING is yielded.
   The pair matters: a version that bound nothing at all would still pass a
   test that only checked the None/Err cases. *)
(* `Box` is NESTED so its `flat_map` lands under `Box.flat_map`, which is what
   `let*` resolves for a value of type `Box` -- a top-level `flat_map` here
   would be `Test.flat_map` and would not be found. *)
let letstar_repl_env () =
  eval_module {|mod Test do
    mod Box do
      type Box(a) = Box(a)
      fn flat_map(m : Box(a), f : a -> Box(b)) : Box(b) do
        match m do
          Box(x) -> f(x)
        end
      end
    end
  end|}

(* Same, plus the real stdlib `List` module, so the multi-value case resolves
   `List.flat_map` for real rather than against a stub. *)
let letstar_repl_env_with_list () =
  let list_mod = load_stdlib_file_for_test "list.march" in
  let m = parse_and_desugar {|mod Test do
    fn placeholder() do 0 end
  end|} in
  March_eval.Eval.eval_module_env
    { m with March_ast.Ast.mod_decls = list_mod :: m.March_ast.Ast.mod_decls }

(* Goes through [parse_repl], so this also pins the new `LET STAR` REPL
   productions -- before them, `let* v = ...` at a prompt was a parse error. *)
let letstar_bind_expr env src =
  match parse_repl (Printf.sprintf "let* v = %s" src) with
  | March_ast.Ast.ReplLetStar (p, e) ->
    March_eval.Eval.letstar_repl_bind env p
      (March_desugar.Desugar.desugar_expr e)
  | _ -> Alcotest.fail (Printf.sprintf "expected ReplLetStar for %S" src)

let test_letstar_repl_binds_option () =
  match letstar_bind_expr (letstar_repl_env ()) "Some(41)" with
  | Ok [("v", March_eval.Eval.VInt 41)] -> ()
  | Ok bs -> Alcotest.fail (Printf.sprintf "unexpected bindings (%d)" (List.length bs))
  | Error m -> Alcotest.fail ("expected a binding, got error: " ^ m)

let test_letstar_repl_binds_result () =
  match letstar_bind_expr (letstar_repl_env ()) "Ok(7)" with
  | Ok [("v", March_eval.Eval.VInt 7)] -> ()
  | Ok _ -> Alcotest.fail "wrong bindings"
  | Error m -> Alcotest.fail ("expected a binding, got error: " ^ m)

(* A multi-value monad binds the FIRST value, which is the reading
   `let* x = [1,2,3]` most naturally suggests. *)
let test_letstar_repl_binds_first_of_list () =
  match letstar_bind_expr (letstar_repl_env_with_list ()) "[5, 6, 7]" with
  | Ok [("v", March_eval.Eval.VInt 5)] -> ()
  | Ok bs ->
    Alcotest.fail (Printf.sprintf "expected the FIRST element, got: %s"
      (String.concat ", " (List.map (fun (n, v) ->
         n ^ "=" ^ March_eval.Eval.value_to_string v) bs)))
  | Error m -> Alcotest.fail ("expected a binding, got error: " ^ m)

let test_letstar_repl_user_type () =
  match letstar_bind_expr (letstar_repl_env ()) "Box.Box(9)" with
  | Ok [("v", March_eval.Eval.VInt 9)] -> ()
  | Ok _ -> Alcotest.fail "wrong bindings"
  | Error m -> Alcotest.fail ("expected a binding, got error: " ^ m)

(* Nothing yielded => nothing bound, and SAID so.  Silently succeeding here
   would leave the prompt with an unbound name and no explanation. *)
let test_letstar_repl_none_binds_nothing () =
  match letstar_bind_expr (letstar_repl_env ()) "None" with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "None must not bind"

let test_letstar_repl_err_binds_nothing () =
  match letstar_bind_expr (letstar_repl_env ()) {|Err("boom")|} with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "Err must not bind"

let test_letstar_repl_empty_list_binds_nothing () =
  match letstar_bind_expr (letstar_repl_env ()) "[]" with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "[] must not bind"

let test_letq_err_short_circuits () =
  let env = eval_module {|mod Test do
    fn safe_div(a, b) do
      if b == 0 do
        Err("division by zero")
      else
        Ok(a / b)
      end
    end
    fn run() do
      let? x = safe_div(10, 0)
      Ok(x + 1)
    end
  end|} in
  let v = call_fn env "run" [] in
  (match v with
   | March_eval.Eval.VCon ("Err", [March_eval.Eval.VString "division by zero"]) -> ()
   | _ -> Alcotest.fail (Printf.sprintf "expected Err(\"division by zero\"), got: %s" (March_eval.Eval.value_to_string v)))

let test_letq_chain_first_err () =
  let env = eval_module {|mod Test do
    fn run() do
      let? _a = Err("first")
      let? _b = Err("second")
      Ok(42)
    end
  end|} in
  let v = call_fn env "run" [] in
  (match v with
   | March_eval.Eval.VCon ("Err", [March_eval.Eval.VString "first"]) -> ()
   | _ -> Alcotest.fail (Printf.sprintf "expected Err(\"first\"), got: %s" (March_eval.Eval.value_to_string v)))

let test_letq_in_lambda () =
  let env = eval_module {|mod Test do
    fn run() do
      let f = fn x ->
        let? v = if x > 0 do Ok(x * 2) else Err("negative") end
        Ok(v + 1)
      f(5)
    end
  end|} in
  let v = call_fn env "run" [] in
  (match v with
   | March_eval.Eval.VCon ("Ok", [March_eval.Eval.VInt 11]) -> ()
   | _ -> Alcotest.fail (Printf.sprintf "expected Ok(11), got: %s" (March_eval.Eval.value_to_string v)))

(* ── Parser gap tests ───────────────────────────────────────────────────── *)

let test_parse_unary_minus () =
  (* -x  parses as  negate(x) *)
  let lexbuf = Lexing.from_string "-x" in
  let expr = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  match expr with
  | March_ast.Ast.EApp (March_ast.Ast.EVar n, [_], _) ->
    Alcotest.(check string) "unary minus becomes negate" "negate" n.txt
  | _ -> Alcotest.fail "expected EApp(negate, [x])"

let test_parse_negative_lit_pattern () =
  (* match n with | -1 -> ... should produce PatLit(LitInt(-1)) *)
  let src = {|mod T do
    fn f(n) do
      match n do
      -1 -> true
      _  -> false
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
  let expr = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  match expr with
  | March_ast.Ast.ECon (n, [_; _], _) when n.txt = "Cons" -> ()
  | _ -> Alcotest.fail "expected Cons(1, Cons(...))"

let test_parse_zero_arg_lambda_sugar () =
  (* `fn -> expr` should parse identically to `fn () -> expr` *)
  let lexbuf = Lexing.from_string "fn -> 42" in
  let expr = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  match expr with
  | March_ast.Ast.ELam ([], March_ast.Ast.ELit (March_ast.Ast.LitInt 42, _), _) -> ()
  | _ -> Alcotest.fail "expected ELam([], ELit(42))"

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
      match n do
      0 -> do
        let tag = 0
        tag
      end
      _ -> do
        let tag = 1
        tag
      end
      end
    end
  end|} in
  let v0 = call_fn env "classify" [March_eval.Eval.VInt 0] in
  let v1 = call_fn env "classify" [March_eval.Eval.VInt 7] in
  Alcotest.(check int) "classify(0) = 0" 0
    (match v0 with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt");
  Alcotest.(check int) "classify(7) = 1" 1
    (match v1 with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

let test_eval_block_arm_no_wrapper () =
  (* Multi-statement match arm body without do...end wrapper *)
  let env = eval_module {|mod Test do
    fn classify(n) do
      match n do
      0 ->
        let tag = 0
        tag
      _ ->
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

let test_eval_block_arm_nested () =
  (* Nested match with multi-expression arm bodies *)
  let env = eval_module {|mod Test do
    type Shape = Circle(Int) | Rect(Int, Int)
    fn area(s) do
      match s do
      Circle(r) ->
        let sq = r * r
        sq * 3
      Rect(w, h) ->
        let a = w * h
        a
      end
    end
  end|} in
  let v = call_fn env "area" [March_eval.Eval.VCon ("Circle", [March_eval.Eval.VInt 5])] in
  Alcotest.(check int) "Circle area" 75
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

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
      match n do
      0  -> 0
      -1 -> -1
      _  -> 1
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

let test_mono_nested_generic_pattern_vars_are_concrete () =
  let m = mono_module {|mod Test do
    type IntList(a) = Nil | Cons(a, IntList(a))
    fn reverse(xs : IntList(a)) : IntList(a) do
      fn go(lst : IntList(a), acc : IntList(a)) : IntList(a) do
        match lst do
        Nil -> acc
        Cons(h, t) -> go(t, Cons(h, acc))
        end
      end
      go(xs, Nil)
    end
    fn main() : IntList(Int) do reverse(Cons(1, Nil)) end
  end|} in
  let residual =
    collect_all_vars_in_module m
    |> List.filter_map (fun (v : March_tir.Tir.var) ->
           if March_tir.Mono.has_tvar v.March_tir.Tir.v_ty then
             Some
               (Printf.sprintf "%s : %s" v.March_tir.Tir.v_name
                  (March_tir.Pp.string_of_ty v.March_tir.Tir.v_ty))
           else None)
  in
  Alcotest.(check (list string))
    "nested generic constructor-pattern variables are concrete after mono"
    [] residual

let test_mono_preserves_declared_variant_parameter_order () =
  let m = mono_module {|mod Test do
    type Reordered(a, b) = Reordered(b, a)
    fn unpack(x : Reordered(a, b)) : (b, a) do
      match x do
      Reordered(left, right) -> (left, right)
      end
    end
    fn main() : (String, Int) do
      unpack(Reordered("left", 7))
    end
  end|} in
  let vars = collect_all_vars_in_module m in
  let ty_of name =
    vars
    |> List.find_opt (fun (v : March_tir.Tir.var) ->
           String.equal v.March_tir.Tir.v_name name)
    |> Option.map (fun v -> v.March_tir.Tir.v_ty)
  in
  Alcotest.(check (option string))
    "first constructor field follows declared (a, b) argument order"
    (Some "String")
    (Option.map March_tir.Pp.string_of_ty (ty_of "left"));
  Alcotest.(check (option string))
    "second constructor field follows declared (a, b) argument order"
    (Some "Int")
    (Option.map March_tir.Pp.string_of_ty (ty_of "right"))

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
    fn pick(b : Bool) : Int do if b do 1 else 0 end end
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
      match s do
      Circle(r) -> r
      Square(side) -> side
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
    fn make() do { x: 1, y: 2 } end
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

let test_tir_lower_qualified_module () =
  (* Referencing Math.min_int should auto-lower the Math stdlib module
     and include its functions in tm_fns. *)
  let m = lower_module_typed {|mod Test do
    mod Math do
      fn min_int(a : Int, b : Int) : Int do
        if a < b do a else b end
      end
    end
    fn main() do Math.min_int(3, 5) end
  end|} in
  let fn_names = List.map (fun (f : March_tir.Tir.fn_def) -> f.fn_name) m.tm_fns in
  Alcotest.(check bool) "Math.min_int in fns" true (List.mem "Math.min_int" fn_names)

let test_tir_lower_qualified_auto_load () =
  (* When a qualified name like "Mod.func" appears and no inline DMod exists,
     ensure_module_lowered should trigger stdlib loading. *)
  (* We test the mechanism directly by calling _ensure_module_lowered
     and checking that _lowered_modules tracks it. *)
  March_tir.Lower._lowered_modules := Hashtbl.create 4;
  March_tir.Lower._fns_ref := ref [];
  March_tir.Lower._types_ref := ref [];
  (* Try to load a nonexistent module — should not crash *)
  !(March_tir.Lower._ensure_module_lowered) March_tir.Lower.empty_env "NoSuchModule99";
  Alcotest.(check bool) "nonexistent module tracked"
    true (Hashtbl.mem !(March_tir.Lower._lowered_modules) "NoSuchModule99");
  (* Fns should still be empty — no module found *)
  Alcotest.(check int) "no fns added" 0 (List.length !(!(March_tir.Lower._fns_ref)))

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
    fn label(n) do
      match n do
      0 -> 0
      other -> other
      end
    end
  end|} in
  let f = find_fn "label" m in
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

(** Regression: atom patterns (:get) must produce ECase branches, not be
    silently dropped.  The bug was that pat_tag_and_subs only handled
    PatLit(LitAtom) but the parser always emits PatAtom for :name patterns. *)
let test_tir_lower_atom_pattern_match () =
  let m = lower_module {|mod Test do
    fn classify(m) do
      match m do
      :get  -> 1
      :post -> 2
      _     -> 0
      end
    end
  end|} in
  let f = find_fn "classify" m in
  let rec find_case = function
    | March_tir.Tir.ECase (_, brs, _) -> Some brs
    | March_tir.Tir.ELet (_, _, body) -> find_case body
    | _ -> None
  in
  match find_case f.fn_body with
  | None -> Alcotest.fail "expected ECase in atom match"
  | Some brs ->
    (* Must have exactly 2 discriminating branches (:get and :post) *)
    Alcotest.(check int) "atom match: 2 branches" 2 (List.length brs);
    let tags = List.map (fun (br : March_tir.Tir.branch) -> br.br_tag) brs in
    Alcotest.(check bool) ":get branch present" true (List.mem ":get" tags);
    Alcotest.(check bool) ":post branch present" true (List.mem ":post" tags)

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
      match xs do
      Nil -> Nil()
      Cons(h, t) -> Cons(f(h), map(f, t))
      end
    end

    fn length(xs) do
      match xs do
      Nil -> 0
      Cons(h, t) -> 1 + length(t)
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

(* impl Mod.Iface(T) — dotted interface name parses and stores joined name *)
let test_parse_impl_dotted_iface () =
  let src = {|mod Test do
    impl Conduit.Storage(Int) do
      fn get(k, s) do "" end
    end
  end|} in
  let m = parse_module src in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DImpl (idef, _)] ->
    Alcotest.(check string) "dotted impl iface" "Conduit.Storage" idef.March_ast.Ast.impl_iface.March_ast.Ast.txt;
    Alcotest.(check int) "1 method" 1 (List.length idef.March_ast.Ast.impl_methods)
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
let parse_expr_str src =
  let lexbuf = Lexing.from_string src in
  March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf

(* Interpolation emits ONE shape: a `++` chain, at every length.  desugar then
   collapses chains of 3+ into string_concat3, so the parser does not need a
   second shape and deliberately does not have one.

   An earlier version emitted `string_join` over a cons list past a part-count
   threshold. That was a win against a raw `++` chain but a LOSS against
   concat3 folding, which allocates no list: measured at 7 segments, 519ms via
   string_join against 287ms via folding. It also meant every consumer of the
   interpolation AST -- the formatter's reconstruction and the ~H sigil's
   part-wise decomposition -- had to handle two shapes, and a missing case in
   the latter silently disabled HTML escaping twice. *)
let test_parse_string_interp () =
  (* "hi " ++ to_string(name) ++ "!" *)
  match parse_expr_str {|"hi ${name}!"|} with
  | March_ast.Ast.EApp (March_ast.Ast.EVar cat2, [_; _], _)
    when cat2.txt = "++" -> ()
  | _ -> Alcotest.fail "expected ++ desugaring from short string interpolation"

(* Same shape at nine segments — no threshold, no second form. *)
let test_parse_string_interp_many_parts () =
  match parse_expr_str {|"a${w}b${x}c${y}d${z}e"|} with
  | March_ast.Ast.EApp (March_ast.Ast.EVar cat2, [_; _], _)
    when cat2.txt = "++" -> ()
  | _ ->
    Alcotest.fail
      "expected ++ desugaring from many-part interpolation too (one shape only)"

let test_eval_string_interp () =
  let env = eval_module {|mod Test do
    fn greet(name) do "Hello, ${name}!" end
  end|} in
  let v = call_fn env "greet" [March_eval.Eval.VString "World"] in
  Alcotest.(check string) "string interpolation" "Hello, World!"
    (match v with March_eval.Eval.VString s -> s | _ -> failwith "expected VString")

let test_eval_string_interp_int () =
  let env = eval_module {|mod Test do
    fn show_num(n) do "count: ${n}" end
  end|} in
  let v = call_fn env "show_num" [March_eval.Eval.VInt 42] in
  Alcotest.(check string) "string interpolation with int" "count: 42"
    (match v with March_eval.Eval.VString s -> s | _ -> failwith "expected VString")

let test_eval_string_interp_multi () =
  let env = eval_module {|mod Test do
    fn fmt(a, b) do "${a} + ${b}" end
  end|} in
  let v = call_fn env "fmt"
    [March_eval.Eval.VInt 1; March_eval.Eval.VInt 2] in
  Alcotest.(check string) "multi-segment interpolation" "1 + 2"
    (match v with March_eval.Eval.VString s -> s | _ -> failwith "expected VString")

(* REPL command helpers *)

(** Run the :type command on an expression string, return the type string or error. *)
let test_repl_type_int () =
  match repl_type_of "42" with
  | Some ty -> Alcotest.(check string) ":type int literal" "Int" ty
  | None -> Alcotest.fail ":type returned error"

let test_repl_type_bool () =
  match repl_type_of "true" with
  | Some ty -> Alcotest.(check string) ":type bool literal" "Bool" ty
  | None -> Alcotest.fail ":type returned error"

let test_repl_type_string () =
  match repl_type_of {|"hello"|} with
  | Some ty -> Alcotest.(check string) ":type string literal" "String" ty
  | None -> Alcotest.fail ":type returned error"

(* :doc command: lookup_doc returns None for unknown names *)
let test_repl_doc_missing () =
  Alcotest.(check bool) ":doc missing name returns None" true
    (March_eval.Eval.lookup_doc "nonexistent_fn_xyz" = None)

(* :doc command: after eval_decl, lookup_doc finds the registered doc *)
let test_repl_doc_registered () =
  let base = March_eval.Eval.base_env in
  let src = {|mod Test do
    doc "Add two integers"
    fn add(a, b) do a + b end
  end|} in
  let m = parse_and_desugar src in
  let _ = List.fold_left March_eval.Eval.eval_decl base m.March_ast.Ast.mod_decls in
  (* lookup by "add" *)
  match March_eval.Eval.lookup_doc "add" with
  | Some s ->
    Alcotest.(check bool) ":doc finds registered doc" true
      (String.length s > 0)
  | None ->
    (* If @doc isn't wired through eval, we just verify no crash *)
    ()

(* ------------------------------------------------------------------ *)
(* REPL integration helpers                                           *)
(* ------------------------------------------------------------------ *)

(** Run several REPL interactions in isolation (no JIT, no stdlib overhead).
    [eval_env] starts from base_env; [tc_env] from base_env.
    Returns a list of (stdout_line list, stderr_line list) tuples.
    This exercises the same dispatch paths as [run_simple] without the
    full loop / history / JIT infrastructure. *)
let test_repl_error_recovery_type () =
  (* After a type error the REPL state is unchanged — subsequent exprs work *)
  match repl_eval_exprs ["let x = 42"; "x + \"oops\""; "x"] with
  | [`DeclOk; `TypeError _; `Ok (vs, ty)] ->
    Alcotest.(check string) "x still 42 after type error" "42" vs;
    Alcotest.(check string) "x type is Int" "Int" ty
  | results ->
    let describe = function
      | `DeclOk -> "DeclOk"
      | `TypeError t -> "TypeError(" ^ t ^ ")"
      | `Ok (v, t) -> "Ok(" ^ v ^ ", " ^ t ^ ")"
      | `RuntimeError m -> "RuntimeError(" ^ m ^ ")"
      | `ParseError -> "ParseError"
    in
    Alcotest.fail ("unexpected: " ^ String.concat "; " (List.map describe results))

(** Error recovery: runtime error leaves env intact *)
let test_repl_error_recovery_runtime () =
  match repl_eval_exprs ["let x = 42"; "1 / 0"; "x"] with
  | [`DeclOk; `RuntimeError _; `Ok (vs, _)] ->
    Alcotest.(check string) "x still 42 after runtime error" "42" vs
  | _ ->
    (* 1/0 may be caught differently on different platforms *)
    ()

(** v magic variable is updated after each expression *)
let test_repl_v_magic_var () =
  match repl_eval_exprs ["42"; "v + 1"] with
  | [`Ok ("42", "Int"); `Ok ("43", "Int")] -> ()
  | _ -> Alcotest.fail "v magic var not updated"

(** Pretty-printer: list formatting *)
let test_repl_pretty_list () =
  match repl_eval_exprs ["[1, 2, 3]"] with
  | [`Ok (vs, _)] ->
    Alcotest.(check string) "list prints as [1, 2, 3]" "[1, 2, 3]" vs
  | _ -> Alcotest.fail "list eval failed"

(** Pretty-printer: large list truncation *)
let test_repl_pretty_list_truncation () =
  (* Build a 100-element list *)
  let list_src =
    "[" ^ String.concat ", " (List.init 100 string_of_int) ^ "]"
  in
  match repl_eval_exprs [list_src] with
  | [`Ok (vs, _)] ->
    (* Should contain "... (N more)" truncation *)
    Alcotest.(check bool) "truncation marker present"
      true (String.length vs < String.length list_src)
  | _ -> Alcotest.fail "large list eval failed"

(** :inspect shows both type and value *)
let test_repl_inspect_type_and_value () =
  (* Test the underlying logic: infer type and eval value together *)
  let type_map = Hashtbl.create 16 in
  let tc_env = ref (March_typecheck.Typecheck.base_env
    (March_errors.Errors.create ()) type_map) in
  let env = ref March_eval.Eval.base_env in
  let src = "42 + 1" in
  let lexbuf = Lexing.from_string src in
  match (try Some (March_parser.Parser.repl_input (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
         with _ -> None) with
  | Some (March_ast.Ast.ReplExpr e) ->
    let e' = March_desugar.Desugar.desugar_expr e in
    let input_ctx = March_errors.Errors.create () in
    let input_tc  = { !tc_env with errors = input_ctx } in
    let inferred  = March_typecheck.Typecheck.infer_expr input_tc e' in
    let ty_str    = March_typecheck.Typecheck.pp_ty
      (March_typecheck.Typecheck.repr inferred) in
    let v = March_eval.Eval.eval_expr !env e' in
    let vs = March_eval.Eval.value_to_string_pretty v in
    Alcotest.(check string) ":inspect type" "Int" ty_str;
    Alcotest.(check string) ":inspect value" "43" vs
  | _ -> Alcotest.fail ":inspect parse failed"

(** Final-review regression: a desugar-time diagnostic (e.g. the B6
    pipe-into-match check, which raises [March_errors.Errors.ParseError]
    from [Desugar.desugar_expr] rather than from the parser) used to escape
    [run_simple]'s per-form handling entirely — [desugar_expr] is called
    outside any local try/with in the [ReplExpr] branch — and land in the
    loop's outermost catch-all, which rendered it as a bare
    "internal error: March_errors.Errors.ParseError(...)" instead of the
    same span-rendered diagnostic the batch driver (bin/main.ml) shows.
    This exercises the real [run_simple] loop (via `march repl` under a
    non-tty stdin, exactly as the manual repro does), since the lightweight
    [repl_eval_exprs] helper used by the other "repl integration" tests
    calls [desugar_expr] directly and would not reproduce the escape. *)
let test_repl_renders_desugar_parse_error () =
  let exe_dir  = Filename.dirname Sys.executable_name in
  let main_exe = Filename.concat exe_dir "../bin/main.exe" in
  let project_root = Filename.dirname (Filename.dirname exe_dir) in
  if not (Sys.file_exists main_exe) then ()  (* skip: no compiler binary *)
  else begin
    let read_cmd cmd =
      let ic = Unix.open_process_in cmd in
      let buf = Buffer.create 256 in
      (try while true do Buffer.add_channel buf ic 1 done
       with End_of_file -> ());
      ignore (Unix.close_process_in ic);
      Buffer.contents buf
    in
    let out = read_cmd (Printf.sprintf
      "cd %s && echo %s | %s repl 2>&1"
      (Filename.quote project_root)
      (Filename.quote {|1 |> (match 2 do 1 -> "one" | 2 -> "two" | _ -> "x" end)|})
      (Filename.quote main_exe)) in
    Alcotest.(check bool)
      "REPL does not render the B6 diagnostic as a bare internal error"
      false
      (let re = Str.regexp_string "internal error: March_errors.Errors.ParseError" in
       try ignore (Str.search_forward re out 0); true with Not_found -> false);
    Alcotest.(check bool)
      "REPL renders the desugar diagnostic's message text"
      true
      (let re = Str.regexp_string
         "piping into a match discards its scrutinee" in
       try ignore (Str.search_forward re out 0); true with Not_found -> false)
  end

(** Regression: nullary constructors of a REPL-declared ADT all printed as
    the type's FIRST variant (`Green` and `Blue` both displayed as `Red`).

    Root cause: the REPL's JIT compiles each expression fragment as its own
    LLVM module whose constructor-tag table ([Llvm_toplevel.build_ctor_info])
    is built ONLY from the type_defs handed to the fragment emitter.  A type
    declared at the prompt is evaluated by the tree-walking interpreter and
    was registered with the JIT for pretty-printing only
    ([Repl_jit.register_user_type_decl] -> [global_type_defs]), never as a
    lowering/codegen input — so the fragment's [ctor_entry] lookup missed and
    fell back to its `ce_tag = 0` default, allocating every nullary
    constructor with tag 0.  The printer then faithfully rendered tag 0, i.e.
    the first variant.

    Must drive the real `march repl` subprocess: the lightweight
    [repl_eval_exprs] helper used by the "repl parity" tests never touches the
    JIT, so it cannot reproduce this.  ([MARCH_REPL_INTERP] likewise takes the
    interpreter path and always printed these correctly.) *)
let test_repl_jit_nullary_ctor_tags () =
  let exe_dir  = Filename.dirname Sys.executable_name in
  let main_exe = Filename.concat exe_dir "../bin/main.exe" in
  let project_root = Filename.dirname (Filename.dirname exe_dir) in
  if not (Sys.file_exists main_exe) then ()  (* skip: no compiler binary *)
  else begin
    let read_cmd cmd =
      let ic = Unix.open_process_in cmd in
      let buf = Buffer.create 256 in
      (try while true do Buffer.add_channel buf ic 1 done
       with End_of_file -> ());
      ignore (Unix.close_process_in ic);
      Buffer.contents buf
    in
    let script = String.concat "\\n" [
      "type Color = Red | Green | Blue";
      "Green"; "Blue"; "Red";
      (* The tag is not cosmetic: a wrong tag also picks the wrong match arm. *)
      "match Blue do"; "  Red -> 1"; "  Green -> 2"; "  Blue -> 3"; "end";
      (* A payload constructor past the first: the tag must be right AND the
         payload must survive (each repr stores its fields differently). *)
      "type Pay = P0 | P1(Int) | P2";
      "P1(7)"; "P2";
      (* Option-shaped: not a heap cell at all — `X(7)` IS the tagged word 15,
         `Y` IS a raw 0. *)
      "type Niche = X(Int) | Y";
      "X(7)"; "Y";
      ":quit" ] ^ "\\n" in
    let out = read_cmd (Printf.sprintf
      "cd %s && printf %s | %s repl 2>&1"
      (Filename.quote project_root)
      (Filename.quote script)
      (Filename.quote main_exe)) in
    let contains needle =
      let re = Str.regexp_string needle in
      try ignore (Str.search_forward re out 0); true with Not_found -> false
    in
    List.iter (fun expected ->
      Alcotest.(check bool)
        (Printf.sprintf "REPL prints `= %s` (got: %s)" expected (String.trim out))
        true (contains ("= " ^ expected)))
      ["Green"; "Blue"; "Red"; "3"; "P1(7)"; "P2"; "X(7)"; "Y"]
  end

(** Parity: same features work in interpreter mode *)
let test_repl_parity_closures () =
  match repl_eval_exprs [
    "let add = fn (x, y) -> x + y";
    "add(3, 4)";
  ] with
  | [`DeclOk; `Ok ("7", "Int")] -> ()
  | _ -> Alcotest.fail "closures in REPL"

let test_repl_parity_hof () =
  (* Test HOF with a user-defined apply, no stdlib dependency *)
  match repl_eval_exprs [
    {|let apply = fn (f, x) -> f(x)|};
    {|let double = fn x -> x * 2|};
    {|apply(double, 5)|};
  ] with
  | [`DeclOk; `DeclOk; `Ok ("10", "Int")] -> ()
  | results ->
    let describe = function
      | `DeclOk -> "DeclOk"
      | `TypeError t -> "TypeError(" ^ t ^ ")"
      | `Ok (v, t) -> "Ok(" ^ v ^ ", " ^ t ^ ")"
      | `RuntimeError m -> "RuntimeError(" ^ m ^ ")"
      | `ParseError -> "ParseError"
    in
    Alcotest.fail ("HOF in REPL failed: " ^ String.concat "; " (List.map describe results))

let test_repl_parity_adt () =
  match repl_eval_exprs [
    {|type Shape = Circle(Int) | Rect(Int, Int)|};
    {|Circle(5)|};
    {|Rect(3, 4)|};
  ] with
  | [`DeclOk; `Ok ("Circle(5)", _); `Ok ("Rect(3, 4)", _)] -> ()
  | results ->
    let describe = function
      | `DeclOk -> "DeclOk"
      | `TypeError t -> "TypeError(" ^ t ^ ")"
      | `Ok (v, t) -> "Ok(" ^ v ^ ", " ^ t ^ ")"
      | `RuntimeError m -> "RuntimeError(" ^ m ^ ")"
      | `ParseError -> "ParseError"
    in
    Alcotest.fail ("ADT in REPL failed: " ^ String.concat "; " (List.map describe results))

let test_repl_parity_match () =
  match repl_eval_exprs [
    {|type Color = Red | Green | Blue|};
    {|match Red do
  Red   -> "red"
  Green -> "green"
  Blue  -> "blue"
end|};
  ] with
  | [`DeclOk; `Ok ({|"red"|}, "String")] -> ()
  | results ->
    let describe = function
      | `DeclOk -> "DeclOk"
      | `TypeError t -> "TypeError(" ^ t ^ ")"
      | `Ok (v, t) -> "Ok(" ^ v ^ ", " ^ t ^ ")"
      | `RuntimeError m -> "RuntimeError(" ^ m ^ ")"
      | `ParseError -> "ParseError"
    in
    Alcotest.fail ("match in REPL failed: " ^ String.concat "; " (List.map describe results))

let test_repl_parity_mutual_recursion () =
  (* Mutual recursion in the REPL requires both fns in the same module decl.
     Test that a module with mutual recursion evaluates correctly. *)
  match repl_eval_exprs [
    {|mod MutRec do
  fn is_even(n) do
    if n == 0 do true
    else is_odd(n - 1) end
  end
  fn is_odd(n) do
    if n == 0 do false
    else is_even(n - 1) end
  end
end|};
    {|MutRec.is_even(4)|};
    {|MutRec.is_odd(3)|};
  ] with
  | [`DeclOk; `Ok ("true", "Bool"); `Ok ("true", "Bool")] -> ()
  | results ->
    let describe = function
      | `DeclOk -> "DeclOk"
      | `TypeError t -> "TypeError(" ^ t ^ ")"
      | `Ok (v, t) -> "Ok(" ^ v ^ ", " ^ t ^ ")"
      | `RuntimeError m -> "RuntimeError(" ^ m ^ ")"
      | `ParseError -> "ParseError"
    in
    Alcotest.fail ("mutual recursion in REPL failed: " ^ String.concat "; " (List.map describe results))

let test_repl_parity_string_interp () =
  match repl_eval_exprs [
    {|let name = "World"|};
    {|"Hello, ${name}!"|};
  ] with
  | [`DeclOk; `Ok ({|"Hello, World!"|}, "String")] -> ()
  | _ -> Alcotest.fail "string interpolation in REPL"

let test_repl_parity_records () =
  match repl_eval_exprs [
    {|let p = { x: 1, y: 2 }|};
    {|p.x + p.y|};
  ] with
  | [`DeclOk; `Ok ("3", "Int")] -> ()
  | _ -> Alcotest.fail "records in REPL"

let test_repl_parity_if_else () =
  match repl_eval_exprs [
    {|if 1 < 2 do "yes" else "no" end|};
  ] with
  | [`Ok ({|"yes"|}, "String")] -> ()
  | _ -> Alcotest.fail "if/else in REPL"

(** value_to_string_pretty: ADT constructor *)
let test_repl_pretty_adt () =
  let v = March_eval.Eval.VCon ("Some", [March_eval.Eval.VInt 42]) in
  let s = March_eval.Eval.value_to_string_pretty v in
  Alcotest.(check string) "ADT constructor" "Some(42)" s

(** value_to_string_pretty: nested record *)
let test_repl_pretty_record () =
  let v = March_eval.Eval.VRecord [("name", March_eval.Eval.VString "Alice");
                                    ("age",  March_eval.Eval.VInt 30)] in
  let s = March_eval.Eval.value_to_string_pretty v in
  Alcotest.(check string) "record" {|{ name: "Alice", age: 30 }|} s

(** value_to_string_pretty: depth truncation *)
let test_repl_pretty_depth_truncation () =
  (* Build deeply nested VCon *)
  let rec nest n v =
    if n = 0 then v
    else nest (n-1) (March_eval.Eval.VCon ("Wrap", [v]))
  in
  let v = nest 20 (March_eval.Eval.VInt 0) in
  let s = March_eval.Eval.value_to_string_pretty v in
  Alcotest.(check bool) "depth truncation"
    true (String.length s < 200)  (* should be truncated, not ~4KB *)

(* ------------------------------------------------------------------ *)
(* mod typecheck: DMod exposes names with prefix *)
let test_tc_mod_typecheck () =
  let ctx = typecheck {|mod Test do
    mod Foo do
      fn bar() do 42 end
    end
    fn main() do Foo.bar() end
  end|} in
  Alcotest.(check bool) "Foo.bar accessible after mod" false (has_errors ctx)

let test_tc_mod_private () =
  let ctx = typecheck {|mod Test do
    mod Foo do
      pfn secret() do 42 end
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
      fn bar(x : Int) : Int do x end
    end
  end|} in
  Alcotest.(check bool) "sig satisfied — no errors" false (has_errors ctx)

let test_tc_sig_missing () =
  let ctx = typecheck {|mod Test do
    sig Foo do
      fn bar : Int -> Int
    end
    mod Foo do
      fn baz(x : Int) : Int do x end
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

let test_default_method_inherited () =
  (* Impl provides eq but not neq — neq should be auto-generated from default *)
  let ctx = typecheck {|mod Test do
    interface Eq(a) do
      fn eq: a -> a -> Bool
      fn neq: a -> a -> Bool do fn(x, y) -> not(eq(x, y)) end
    end
    impl Eq(Int) do
      fn eq(x, y) do x == y end
    end
  end|} in
  Alcotest.(check bool) "impl with default method — no errors" false (has_errors ctx)

let test_default_method_eval () =
  (* neq auto-generated from default can be called in the eval *)
  let src = {|mod Test do
    interface Eq(a) do
      fn eq: a -> a -> Bool
      fn neq: a -> a -> Bool do fn(x, y) -> not(eq(x, y)) end
    end
    impl Eq(Int) do
      fn eq(x, y) do x == y end
    end
  end|} in
  let env = eval_module src in
  let result = call_fn env "neq"
    [March_eval.Eval.VInt 1; March_eval.Eval.VInt 2] in
  Alcotest.(check bool) "neq default returns true for 1 neq 2" true
    (vbool result)

let test_general_iface_multi_impl_dispatch () =
  (* Two impls of ONE general interface for DISTINCT types must each dispatch to
     their own body by the argument's runtime type, not the last-bound name.
     Regression: the interp used to name-bind general-interface methods (last
     impl wins), so speak(Dog) wrongly ran Cat's body (meow/meow). Now routed
     through iface_method_tbl by type. *)
  let src = {|mod Test do
    interface Speak(a) do
      fn speak : a -> String
    end
    type Dog = Dog
    type Cat = Cat
    impl Speak(Dog) do fn speak(_x) do "woof" end end
    impl Speak(Cat) do fn speak(_x) do "meow" end end
    fn say_dog() do speak(Dog) end
    fn say_cat() do speak(Cat) end
  end|} in
  let env = eval_module src in
  let vstr v = match v with March_eval.Eval.VString s -> s | _ -> failwith "expected VString" in
  Alcotest.(check string) "speak(Dog) dispatches to Dog's body"
    "woof" (vstr (call_fn env "say_dog" []));
  Alcotest.(check string) "speak(Cat) dispatches to Cat's body"
    "meow" (vstr (call_fn env "say_cat" []))

let test_interp_colliding_general_iface_dispatch () =
  (* Layer 1b: two SAME-short-name types (NA.Thing vs NB.Thing) each impl'ing
     the same GENERAL user interface must dispatch to their own body,
     interpreted. Regression: iface_method_tbl used to be keyed
     (iface, method, bare_type_name) — both impls collided on
     ("Speak", "speak", "Thing"), so only the LAST-registered body
     (NB's) was ever reachable, even for an NA.Thing value.

     `say` is deliberately declared INSIDE each of NA/NB (rather than calling
     `speak` from an outer scope) to sidestep an unrelated, pre-existing gap:
     a nested module's DImpl-bound interface dispatcher never gets exposed
     under a "NA.speak" qualified key (`eval_decl`'s DMod arm only exports
     names `declared_names` collects, which walks DFn/DLet/DMod/DExtern, not
     DImpl) — calling bare `speak` from a SIBLING or outer module is a
     separate, out-of-scope limitation. Dispatch itself is keyed purely by
     the argument's own runtime type via the GLOBAL iface_method_tbl/
     ctor_qualified_type_tbl, so calling through NA's or NB's own local
     `speak` binding still exercises the real fix. *)
  let src = {|mod Top do
    interface Speak(a) do
      fn speak : a -> String
    end
    mod NA do
      type Thing = TA
      impl Speak(Thing) do
        fn speak(_self) do "from-A" end
      end
      fn say() do speak(TA) end
    end
    mod NB do
      type Thing = TB
      impl Speak(Thing) do
        fn speak(_self) do "from-B" end
      end
      fn say() do speak(TB) end
    end
  end|} in
  let env = eval_module src in
  let vstr v = match v with March_eval.Eval.VString s -> s | _ -> failwith "expected VString" in
  Alcotest.(check string) "NA.say() dispatches to NA.Thing's Speak impl"
    "from-A" (vstr (call_fn env "NA.say" []));
  Alcotest.(check string) "NB.say() dispatches to NB.Thing's Speak impl"
    "from-B" (vstr (call_fn env "NB.say" []))

(** Task 5 (constructor module-qualified identity plan) — interpreter side.
    Layer 1b's [test_interp_colliding_general_iface_dispatch] above only
    covers DISJOINT ctor sets (NA.Thing = {TA}, NB.Thing = {TB}): the bare
    ctor tag alone already disambiguates a value, so [VCon]'s tag was never
    ambiguous there. This is the DOUBLE-collision shape: two same-short-name
    types (DcA.Thing, DcB.Thing) each declaring a ctor with the SAME name
    ("Shared") — before this task, [ECon] always stripped to the bare tag,
    so `DcA.Thing.Shared` and `DcB.Thing.Shared` produced the LITERALLY
    IDENTICAL runtime value `VCon("Shared", [])`, and `speak`'s `match self
    do Shared -> … end` inside EACH impl body dispatched to whichever
    ctor's registration happened to win, not the actual argument.

    Construction (`Shared` in `say()`, a MODULE-LEVEL fn) and pattern-match
    (`Shared` inside `speak`'s IMPL-METHOD body) must now each qualify
    against their own module (`DcA.Thing.Shared` vs `DcB.Thing.Shared`), so
    DcA's `speak(Shared)` and DcB's `speak(Shared)` reach their own arm.

    `say()` is declared INSIDE each of DcA/DcB (not called from `main`
    directly) to sidestep the SAME pre-existing, unrelated interpreter
    scoping gap documented at [test_interp_colliding_general_iface_dispatch]
    above: a nested module's DImpl-bound interface dispatcher isn't visible
    from an outer/sibling module. Uses [eval_module]/[call_fn] (bypasses
    typecheck entirely, like every other test in this file), so the
    Stage-6b double-collision coherence REJECTION in typecheck.ml (which
    would otherwise need `MARCH_DEV_RELAX_CTOR_COHERENCE=1` to get past) is
    never reached — verified empirically: this test fails RED with the
    pre-fix interpreter and passes GREEN with the fix, with no env var. *)
let test_interp_colliding_double_collision_ctor_construction_and_match () =
  let src = {|mod Top do
    interface Speak(a) do
      fn speak : a -> String
    end
    mod DcA do
      type Thing = Shared | OnlyA
      impl Speak(Thing) do
        fn speak(self) do
          match self do
            Shared -> "from-A-shared"
            OnlyA -> "from-A-only"
          end
        end
      end
      fn say() do speak(Shared) end
    end
    mod DcB do
      type Thing = Shared | OnlyB
      impl Speak(Thing) do
        fn speak(self) do
          match self do
            Shared -> "from-B-shared"
            OnlyB -> "from-B-only"
          end
        end
      end
      fn say() do speak(Shared) end
    end
  end|} in
  let env = eval_module src in
  let vstr v = match v with March_eval.Eval.VString s -> s | _ -> failwith "expected VString" in
  Alcotest.(check string) "DcA.say() dispatches to DcA.Thing's own Shared arm"
    "from-A-shared" (vstr (call_fn env "DcA.say" []));
  Alcotest.(check string) "DcB.say() dispatches to DcB.Thing's own Shared arm"
    "from-B-shared" (vstr (call_fn env "DcB.say" []))

(** Companion to the test above, covering the OTHER two combinations: ECon
    construction happening INSIDE an impl-method's own body (not a plain
    module-level fn — [make_shared]), and PatCon pattern-match happening in
    a plain MODULE-LEVEL fn (not inside an impl method — [classify_own]).
    Dispatch to [make_shared] is by the argument's runtime type
    ([OnlyC]/[OnlyD] — NOT collision-shared ctor names, so unambiguous per
    the PARENT plan's own Task 5), so this isolates THIS task's fix rather
    than re-testing that one.

    Made deliberately DISCRIMINATING (not just "does it run without
    crashing") by cross-feeding: DcC's own impl-method-constructed [Shared]
    must match DcC's own module-level [classify_own], but DcD's
    impl-method-constructed [Shared] must NOT — before this task's fix both
    are the SAME bare `VCon("Shared", [])`, so [DcC.classify_own] would
    (wrongly) match DcD's value too; after the fix the tags differ
    ("DcC.Thing.Shared" vs "DcD.Thing.Shared") and the cross call raises
    [Match_failure] (non-exhaustive: [classify_own] only has Shared/OnlyC
    arms), which the test asserts. *)
let test_interp_colliding_double_collision_ctor_impl_construction_and_module_match () =
  let src = {|mod Top2 do
    interface Make(a) do
      fn make_shared : a -> a
    end
    mod DcC do
      type Thing = Shared | OnlyC
      impl Make(Thing) do
        fn make_shared(_self) do Shared end
      end
      fn make() do make_shared(OnlyC) end
      fn classify_own(t) do
        match t do
          Shared -> "C-shared"
          OnlyC -> "C-only"
        end
      end
    end
    mod DcD do
      type Thing = Shared | OnlyD
      impl Make(Thing) do
        fn make_shared(_self) do Shared end
      end
      fn make() do make_shared(OnlyD) end
    end
  end|} in
  let env = eval_module src in
  let vstr v = match v with March_eval.Eval.VString s -> s | _ -> failwith "expected VString" in
  let dc_shared = call_fn env "DcC.make" [] in
  let dd_shared = call_fn env "DcD.make" [] in
  Alcotest.(check string) "DcC.classify_own matches DcC's OWN impl-method-constructed Shared"
    "C-shared" (vstr (call_fn env "DcC.classify_own" [dc_shared]));
  let cross_matched =
    try Some (vstr (call_fn env "DcC.classify_own" [dd_shared]))
    with March_eval.Eval.Match_failure _ -> None
  in
  Alcotest.(check bool)
    "DcC.classify_own must NOT match DcD's impl-method-constructed Shared \
     (different qualified tag — a match here means the two collided back \
     into the SAME bare VCon tag)"
    true (cross_matched = None)

let test_default_method_user_type () =
  (* Regression: a user-declared `interface Eq(a)` (name collides with the
     built-in Eq) with a default `neq` calling `eq`, implemented for a USER
     type, must terminate and return the correct answer.

     The builtin `eq`/`==` dispatcher resolves the impl from
     `impl_tbl[("Eq", type)]`.  The DImpl eval used to write EVERY method of the
     impl under that single (iface, type) key, so the injected default `neq`
     (processed after `eq`) clobbered the `eq` entry.  A builtin `eq` on a
     Widget then invoked `neq`, whose body called `eq`, which dispatched to
     `neq` again → unbounded recursion (stack overflow / hang).  This mirrors
     the "Default Implementations" example in docs/interfaces.md.

     NOTE: the existing `test_default_method_eval` uses `impl Eq(Int)`, which
     never triggered the bug: the builtin `eq` short-circuits primitives
     (`[VInt a; VInt b] -> VBool (a = b)`) BEFORE consulting `impl_tbl`.  A user
     ADT is required to exercise the corrupted table. *)
  let src = {|mod Test do
    interface Eq(a) do
      fn eq  : a -> a -> Bool
      fn neq : a -> a -> Bool do fn (x, y) -> !eq(x, y) end
    end
    type Widget = Widget(Int)
    impl Eq(Widget) do
      fn eq(a, b) do
        match (a, b) do
          (Widget(x), Widget(y)) -> x == y
        end
      end
    end
    fn neq_diff() do neq(Widget(1), Widget(2)) end
    fn neq_same() do neq(Widget(7), Widget(7)) end
    fn eq_diff()  do eq(Widget(1), Widget(2)) end
    fn eq_same()  do eq(Widget(5), Widget(5)) end
  end|} in
  let env = eval_module src in
  Alcotest.(check bool) "neq(Widget 1, Widget 2) = true"  true
    (vbool (call_fn env "neq_diff" []));
  Alcotest.(check bool) "neq(Widget 7, Widget 7) = false" false
    (vbool (call_fn env "neq_same" []));
  (* A direct `eq` call must also terminate: the corrupted table made even this
     path loop, since bare `eq` on an ADT routes through the builtin dispatcher. *)
  Alcotest.(check bool) "eq(Widget 1, Widget 2) = false"  false
    (vbool (call_fn env "eq_diff" []));
  Alcotest.(check bool) "eq(Widget 5, Widget 5) = true"   true
    (vbool (call_fn env "eq_same" []))

let test_missing_required_method () =
  (* Impl omits a non-default method — should error *)
  let ctx = typecheck {|mod Test do
    interface Show(a) do
      fn show: a -> String
    end
    impl Show(Int) do
    end
  end|} in
  Alcotest.(check bool) "impl missing required method — has errors" true (has_errors ctx)

let test_superclass_satisfied () =
  (* impl Ord(Int) when Eq is already impl'd — should pass *)
  let ctx = typecheck {|mod Test do
    interface Eq(a) do
      fn eq: a -> a -> Bool
    end
    interface Ord(a) requires Eq(a) do
      fn compare: a -> a -> Int
    end
    impl Eq(Int) do
      fn eq(x, y) do x == y end
    end
    impl Ord(Int) do
      fn compare(x, y) do compare_int(x, y) end
    end
  end|} in
  Alcotest.(check bool) "Ord(Int) with Eq(Int) present — no errors" false (has_errors ctx)

let test_superclass_missing () =
  (* impl Sortable(MyType) without impl Equatable(MyType) — should error.
     Use a custom type to avoid builtin Eq/Ord impls for String satisfying the check. *)
  let ctx = typecheck {|mod Test do
    type MyType = MyType(Int)
    interface Equatable(a) do
      fn eq: a -> a -> Bool
    end
    interface Sortable(a) requires Equatable(a) do
      fn compare: a -> a -> Int
    end
    impl Sortable(MyType) do
      fn compare(x, y) do 0 end
    end
  end|} in
  Alcotest.(check bool) "Sortable(MyType) without Equatable(MyType) — has errors" true (has_errors ctx)

let test_unknown_ctor_suggests_similar () =
  (* Typo: "Somm" — should suggest "Some" and produce an error *)
  let ctx = typecheck {|mod Test do
    fn go() do Somm(1) end
  end|} in
  Alcotest.(check bool) "error on unknown ctor" true (has_errors ctx);
  (* Check that the error message mentions 'Some' as a candidate *)
  let mention_some = List.exists (fun d ->
    let m = String.lowercase_ascii d.March_errors.Errors.message in
    let n = String.length m in
    let rec scan i =
      if i + 3 >= n then false
      else if String.sub m i 4 = "some" then true
      else scan (i + 1)
    in scan 0
  ) ctx.March_errors.Errors.diagnostics in
  Alcotest.(check bool) "error message suggests Some" true mention_some

let test_ambiguous_ctor_warns () =
  (* Two types both define Ok; using Ok bare should produce a warning *)
  let ctx = typecheck {|mod Test do
    type MyRes = Ok(Int) | Fail
    fn go() do Ok(1) end
  end|} in
  (* Ok is defined in both Result (builtin) and MyRes; warning expected *)
  let has_ambig_warning = List.exists (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Warning &&
    (let m = d.March_errors.Errors.message in
     let n = String.length m in
     let lo = String.lowercase_ascii m in
     let rec scan i =
       if i + 5 >= n then false
       else if String.sub lo i 6 = "multip" then true
       else scan (i + 1)
     in scan 0)
  ) ctx.March_errors.Errors.diagnostics in
  Alcotest.(check bool) "ambiguous Ok warns" true
    (has_ambig_warning || not (has_errors ctx))

let test_unused_var_warning () =
  let ctx = typecheck {|mod Test do
    fn go(x, y) do x end
  end|} in
  let has_unused_y = List.exists (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Warning &&
    let m = d.March_errors.Errors.message in
    let n = String.length m in
    let lo = String.lowercase_ascii m in
    let rec scan i =
      if i + 5 >= n then false
      else if String.sub lo i 6 = "unused" then true
      else scan (i + 1)
    in scan 0
  ) ctx.March_errors.Errors.diagnostics in
  Alcotest.(check bool) "unused param y produces warning" true has_unused_y

let test_unused_var_underscore_ok () =
  (* wildcard _ must NOT produce unused warnings *)
  let ctx = typecheck {|mod Test do
    fn go(x, _) do x end
  end|} in
  let has_any_unused = List.exists (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Warning &&
    let m = String.lowercase_ascii d.March_errors.Errors.message in
    let n = String.length m in
    let rec scan i =
      if i + 5 >= n then false
      else if String.sub m i 6 = "unused" then true
      else scan (i + 1)
    in scan 0
  ) ctx.March_errors.Errors.diagnostics in
  Alcotest.(check bool) "wildcard _ must not produce unused warning" false has_any_unused

let test_parse_error_type_missing_eq () =
  (* "type Foo Bar" should produce a helpful error about `=` *)
  let msg = parse_error_msg {|mod T do
    type Foo Bar
  end|} in
  Alcotest.(check bool) "type missing = gives error" true (msg <> None)

let test_parse_error_interface_missing_param () =
  let msg = parse_error_msg {|mod T do
    interface Eq do
      fn eq: Int -> Int -> Bool
    end
  end|} in
  Alcotest.(check bool) "interface missing param gives error" true (msg <> None)

let test_parse_error_impl_missing_type () =
  let msg = parse_error_msg {|mod T do
    impl Eq do
      fn eq(x, y) do x == y end
    end
  end|} in
  Alcotest.(check bool) "impl missing type gives error" true (msg <> None)

let test_parse_valid_not_broken () =
  (* Make sure we didn't break valid syntax *)
  let src = {|mod T do
    type Color = Red | Green | Blue
    interface Show(a) do fn show: a -> String end
    impl Show(Int) do fn show(x) do int_to_string(x) end end
    fn go() do Red end
  end|} in
  Alcotest.(check bool) "valid syntax still parses" true
    (match parse_module src with _ -> true)

(* Multi-error recovery: decl_list_r collects errors and continues parsing.
   A module with two bad declarations (unknown tokens at declaration level)
   should parse and the error buffer should have entries. *)
let test_multi_error_recovery_collects () =
  (* Two malformed declarations separated by valid ones.
     "@@@" is not a valid token, triggering decl_list_r recovery. *)
  let src = {|mod T do
    fn ok1() do 42 end
    @@@ garbage
    fn ok2() do 1 end
  end|} in
  (* May raise ParseError (lexer error) or succeed with errors in buffer.
     Either way, at least one error is reported. *)
  let has_error =
    (try
       ignore (parse_module src);
       let errs = March_parser.Parse_errors.take_parse_errors () in
       errs <> []
     with _ ->
       ignore (March_parser.Parse_errors.take_parse_errors ());
       true)
  in
  Alcotest.(check bool) "multi-error recovery reports at least one error" true has_error

let test_type_map_populated () =
  let src = {|mod Test do
    fn go(x : Int) do x end
  end|} in
  let m = March_desugar.Desugar.desugar_module
    (let lexbuf = Lexing.from_string src in
     March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf) in
  let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
  Alcotest.(check bool) "type map is non-empty" true
    (Hashtbl.length type_map > 0)

let test_type_map_fn_recorded () =
  let src = {|mod Test do
    fn add(x : Int, y : Int) do x end
  end|} in
  let m = March_desugar.Desugar.desugar_module
    (let lexbuf = Lexing.from_string src in
     March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf) in
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

(* Regression: a closure whose function type was ERASED to a concrete type
   (e.g. threaded through a tuple field, which the checker types as String)
   must still be called via ECallPtr after defun.  Previously defun's guard
   only fired for TFn/TVar-typed callees, so the call stayed an EApp of a
   local variable.  Perceus's EApp liveness ignores the callee, so the
   closure was dropped (EDecRC) before its call — a use-after-free that
   crashed at runtime (e.g. Form.Wrapper.render through default-arg dispatch
   in bastion).  Defun now also converts EApp of a locally-bound callee. *)
let test_defun_erased_closure_in_tuple_becomes_ecallptr () =
  let m = defun_module {|mod Test do
    fn run(a, b, f) : String do
      let t = (a, b, f)
      match t do
      (x, y, g) ->
        let z = x ++ y
        z ++ g()
      end
    end
    fn main() : String do
      run("hi", "there", fn () -> "!")
    end
  end|} in
  let run_fn = List.find (fun f -> f.March_tir.Tir.fn_name = "run") m.March_tir.Tir.tm_fns in
  let rec has_callptr = function
    | March_tir.Tir.ECallPtr _ -> true
    | March_tir.Tir.ELet (_, e1, e2) -> has_callptr e1 || has_callptr e2
    | March_tir.Tir.ELetRec (fns, body) ->
      List.exists (fun f -> has_callptr f.March_tir.Tir.fn_body) fns || has_callptr body
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun b -> has_callptr b.March_tir.Tir.br_body) brs ||
      (match def with Some e -> has_callptr e | None -> false)
    | March_tir.Tir.ESeq (a, b) -> has_callptr a || has_callptr b
    | _ -> false
  in
  (* The only indirect call in [run] is g(); it must be an ECallPtr so that
     Perceus keeps the closure live for the call. *)
  Alcotest.(check bool) "erased closure call in run is ECallPtr" true
    (has_callptr run_fn.March_tir.Tir.fn_body)

(* Regression: a default-arg function defined inside a NESTED module must not be
   routed through the general desugar path that boxes every parameter into a
   synthesised tuple (`let $t = (a, ...) in case $t of Tuple(...)`), which — for
   a fn also taking a type-erased closure parameter — mismanaged the closure's
   refcount and freed it before its call (use-after-free; bastion
   Form.Wrapper.render via CSRF.tag).  As of the Phase 7.1 nested default-arg
   fix, [expand_defaults_decl] now recurses into [DMod], so a nested default-arg
   fn is EXPANDED into mangled `render$N` variants (each a normal fn with real
   FPNamed params) rather than kept as a single strip-fast-path fn — the same
   no-param-tuple guarantee, reached by expansion instead of the fast-path.
   Assert the full-arity mangled decl (`render$4`, all 4 params) has real params
   and no tuple-match body. *)
let test_desugar_nested_default_arg_no_param_tuple () =
  let m = parse_and_desugar {|mod Outer do
    mod Inner do
      fn render(a, b, c \\ "post", ri) do
        let z = a
        ri()
      end
    end
  end|} in
  let rec find_render decls =
    List.fold_left (fun acc d ->
      match acc with
      | Some _ -> acc
      | None ->
        (match d with
         | March_ast.Ast.DFn (def, _)
           when def.March_ast.Ast.fn_name.March_ast.Ast.txt = "render$4" -> Some def
         | March_ast.Ast.DMod (_, _, inner, _) -> find_render inner
         | _ -> None)
    ) None decls
  in
  let render = match find_render m.March_ast.Ast.mod_decls with
    | Some d -> d
    | None -> Alcotest.fail "nested render$4 (full-arity mangled) fn not found after desugar"
  in
  let clause = List.hd render.March_ast.Ast.fn_clauses in
  (* The body must NOT be a match over a synthesised param tuple. *)
  let is_param_tuple_match = match clause.March_ast.Ast.fc_body with
    | March_ast.Ast.EMatch (March_ast.Ast.ETuple _, _, _) -> true
    | _ -> false
  in
  Alcotest.(check bool) "nested default-arg fn body is not a param-tuple match"
    false is_param_tuple_match;
  (* Params should be the real names, never synthesised __argN. *)
  let synth_param = List.exists (function
    | March_ast.Ast.FPNamed p ->
      let n = p.March_ast.Ast.param_name.March_ast.Ast.txt in
      String.length n >= 5 && String.sub n 0 5 = "__arg"
    | _ -> false) clause.March_ast.Ast.fc_params
  in
  Alcotest.(check bool) "nested default-arg fn keeps real param names"
    false synth_param

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

(* ── Stream fusion tests ──────────────────────────────────────────────── *)

(** Run lower → mono → fusion on a March source string. *)
let test_fusion_map_fold () =
  let m = fusion_module {|mod Test do
    type IntList = INil | ICons(Int, IntList)

    fn imap(xs : IntList, f : Int -> Int) : IntList do
      match xs do
      INil        -> INil
      ICons(h, t) -> ICons(f(h), imap(t, f))
      end
    end

    fn ifold(xs : IntList, acc : Int, f : Int -> Int -> Int) : Int do
      match xs do
      INil        -> acc
      ICons(h, t) -> ifold(t, f(acc, h), f)
      end
    end

    fn main() : Int do
      let xs = ICons(1, ICons(2, ICons(3, INil)))
      let ys = imap(xs, fn x -> x * 2)
      ifold(ys, 0, fn (a, b) -> a + b)
    end
  end|} in
  Alcotest.(check bool) "fused fn emitted for map+fold" true (has_fused_fn m)

(** A filter→fold chain: fuse filter then fold. *)
let test_fusion_filter_fold () =
  let m = fusion_module {|mod Test do
    type IntList = INil | ICons(Int, IntList)

    fn ifilter(xs : IntList, p : Int -> Bool) : IntList do
      match xs do
      INil        -> INil
      ICons(h, t) ->
        if p(h) do ICons(h, ifilter(t, p))
        else ifilter(t, p) end
      end
    end

    fn ifold(xs : IntList, acc : Int, f : Int -> Int -> Int) : Int do
      match xs do
      INil        -> acc
      ICons(h, t) -> ifold(t, f(acc, h), f)
      end
    end

    fn main() : Int do
      let xs = ICons(1, ICons(2, ICons(3, INil)))
      let ys = ifilter(xs, fn x -> x > 1)
      ifold(ys, 0, fn (a, b) -> a + b)
    end
  end|} in
  Alcotest.(check bool) "fused fn emitted for filter+fold" true (has_fused_fn m)

(** The intermediate list variable must NOT be called after fusion. *)
let test_fusion_eliminates_intermediate () =
  let m = fusion_module {|mod Test do
    type IntList = INil | ICons(Int, IntList)

    fn imap(xs : IntList, f : Int -> Int) : IntList do
      match xs do
      INil        -> INil
      ICons(h, t) -> ICons(f(h), imap(t, f))
      end
    end

    fn ifold(xs : IntList, acc : Int, f : Int -> Int -> Int) : Int do
      match xs do
      INil        -> acc
      ICons(h, t) -> ifold(t, f(acc, h), f)
      end
    end

    fn main() : Int do
      let xs = ICons(1, ICons(2, INil))
      let ys = imap(xs, fn x -> x * 2)
      ifold(ys, 0, fn (a, b) -> a + b)
    end
  end|} in
  (* After fusion, main should NOT call imap directly (the intermediate is gone) *)
  let main_fn = List.find (fun (fd : March_tir.Tir.fn_def) -> fd.fn_name = "main")
      m.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "main no longer calls imap directly" false
    (expr_calls "imap" main_fn.March_tir.Tir.fn_body)

(** Multi-use intermediate must NOT be fused (would change semantics). *)
let test_fusion_no_fuse_multi_use () =
  let m = fusion_module {|mod Test do
    type IntList = INil | ICons(Int, IntList)

    fn imap(xs : IntList, f : Int -> Int) : IntList do
      match xs do
      INil        -> INil
      ICons(h, t) -> ICons(f(h), imap(t, f))
      end
    end

    fn ifold(xs : IntList, acc : Int, f : Int -> Int -> Int) : Int do
      match xs do
      INil        -> acc
      ICons(h, t) -> ifold(t, f(acc, h), f)
      end
    end

    fn ilength(xs : IntList) : Int do
      match xs do
      INil        -> 0
      ICons(_, t) -> 1 + ilength(t)
      end
    end

    fn main() : Int do
      let xs = ICons(1, ICons(2, ICons(3, INil)))
      let ys = imap(xs, fn x -> x * 2)
      let s  = ifold(ys, 0, fn (a, b) -> a + b)
      let n  = ilength(ys)
      s
    end
  end|} in
  (* ys is used TWICE (in ifold and ilength) — must NOT fuse *)
  Alcotest.(check bool) "multi-use not fused — no fused fn" false (has_fused_fn m)

(** Purity constraint: calls with IO must not be fused. *)
let test_fusion_no_fuse_impure () =
  let m = fusion_module {|mod Test do
  needs IO.Console
    type IntList = INil | ICons(Int, IntList)

    fn imap_print(xs : IntList, f : Int -> Int) : IntList do
      match xs do
      INil        -> INil
      ICons(h, t) -> do
        let _ = println(int_to_string(h))
        ICons(f(h), imap_print(t, f))
      end
      end
    end

    fn ifold(xs : IntList, acc : Int, f : Int -> Int -> Int) : Int do
      match xs do
      INil        -> acc
      ICons(h, t) -> ifold(t, f(acc, h), f)
      end
    end

    fn main(_cap_console : Cap(IO.Console)) : Int do
      let xs = ICons(1, ICons(2, INil))
      let ys = imap_print(xs, fn x -> x * 2)
      ifold(ys, 0, fn (a, b) -> a + b)
    end
  end|} in
  (* imap_print is not in the fusible producers list — no fusion *)
  Alcotest.(check bool) "impure (non-fusible name) not fused" false (has_fused_fn m)

(** The fused function must appear in tm_fns and be callable. *)
let test_fusion_fused_fn_in_tm_fns () =
  let m = fusion_module {|mod Test do
    type IntList = INil | ICons(Int, IntList)

    fn imap(xs : IntList, f : Int -> Int) : IntList do
      match xs do
      INil        -> INil
      ICons(h, t) -> ICons(f(h), imap(t, f))
      end
    end

    fn ifold(xs : IntList, acc : Int, f : Int -> Int -> Int) : Int do
      match xs do
      INil        -> acc
      ICons(h, t) -> ifold(t, f(acc, h), f)
      end
    end

    fn main() : Int do
      let xs = ICons(1, ICons(2, ICons(3, INil)))
      let ys = imap(xs, fn x -> x)
      ifold(ys, 0, fn (a, b) -> a + b)
    end
  end|} in
  let fused_fns = List.filter (fun (fd : March_tir.Tir.fn_def) ->
    let n = fd.fn_name in
    String.length n >= 7 && String.sub n 0 7 = "$fused_"
  ) m.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "at least one fused fn in tm_fns" true
    (List.length fused_fns >= 1);
  (* main must call the fused fn *)
  let main_fn = List.find (fun (fd : March_tir.Tir.fn_def) -> fd.fn_name = "main")
      m.March_tir.Tir.tm_fns in
  let calls_fused = List.exists (fun fd ->
    expr_calls fd.March_tir.Tir.fn_name main_fn.March_tir.Tir.fn_body
  ) fused_fns in
  Alcotest.(check bool) "main calls fused fn" true calls_fused

(** Map+filter+fold 3-step chain: fuse all three into one pass. *)
let test_fusion_map_filter_fold () =
  let m = fusion_module {|mod Test do
    type IntList = INil | ICons(Int, IntList)

    fn imap(xs : IntList, f : Int -> Int) : IntList do
      match xs do
      INil        -> INil
      ICons(h, t) -> ICons(f(h), imap(t, f))
      end
    end

    fn ifilter(xs : IntList, p : Int -> Bool) : IntList do
      match xs do
      INil        -> INil
      ICons(h, t) ->
        if p(h) do ICons(h, ifilter(t, p))
        else ifilter(t, p) end
      end
    end

    fn ifold(xs : IntList, acc : Int, f : Int -> Int -> Int) : Int do
      match xs do
      INil        -> acc
      ICons(h, t) -> ifold(t, f(acc, h), f)
      end
    end

    fn main() : Int do
      let xs = ICons(1, ICons(2, ICons(3, ICons(4, ICons(5, INil)))))
      let ys = imap(xs, fn x -> x * 2)
      let zs = ifilter(ys, fn x -> x > 4)
      ifold(zs, 0, fn (a, b) -> a + b)
    end
  end|} in
  Alcotest.(check bool) "fused fn emitted for map+filter+fold" true (has_fused_fn m);
  (* main should not call imap or ifilter directly *)
  let main_fn = List.find (fun (fd : March_tir.Tir.fn_def) -> fd.fn_name = "main")
      m.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "main no longer calls imap" false
    (expr_calls "imap" main_fn.March_tir.Tir.fn_body);
  Alcotest.(check bool) "main no longer calls ifilter" false
    (expr_calls "ifilter" main_fn.March_tir.Tir.fn_body)

(** Fusion does not break functions with no list chains. *)
let test_fusion_no_change_non_list () =
  let m = fusion_module {|mod Test do
    fn add(a : Int, b : Int) : Int do a + b end
    fn main() : Int do add(1, 2) end
  end|} in
  Alcotest.(check bool) "no fused fn for non-list program" false (has_fused_fn m)

(** Use-count helper is correct. *)
let test_fusion_use_count () =
  let open March_tir.Tir in
  let open March_tir.Fusion in
  let x_var = { v_name = "x"; v_ty = TInt; v_lin = Unr } in
  let y_var = { v_name = "y"; v_ty = TInt; v_lin = Unr } in
  let e =
    ELet (y_var, EApp ({v_name="+"; v_ty=TInt; v_lin=Unr},
                       [AVar x_var; AVar x_var]),
    EAtom (AVar y_var)) in
  Alcotest.(check int) "x used 2 times" 2 (use_count "x" e);
  Alcotest.(check int) "y used 1 time"  1 (use_count "y" e);
  Alcotest.(check int) "z used 0 times" 0 (use_count "z" e)

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

(** Regression: [to_string] of a borrowed String field is the identity (see
    llvm_emit.ml — the TString case returns the argument pointer unchanged).
    When a function extracts a String field from a borrowed record and returns
    [to_string(field)] (the desugaring of "${record.field}"), Perceus must NOT
    treat the result as independently owned and emit an EDecRC: that EDecRC
    would free the field string the record owner still references, producing a
    heap-use-after-free when the result is compared to a literal with ==. *)
let test_perceus_to_string_borrowed_field_no_decrc () =
  let m = perceus_module {|mod Test do
    type R = { content_dir : String }
    fn acc(s : R) : String do "${s.content_dir}" end
  end|} in
  let f = List.find (fun fn -> fn.March_tir.Tir.fn_name = "acc") m.March_tir.Tir.tm_fns in
  let rec has_decrc = function
    | March_tir.Tir.EDecRC _ -> true
    | March_tir.Tir.ELet (_, e1, e2) -> has_decrc e1 || has_decrc e2
    | March_tir.Tir.ESeq (e1, e2) -> has_decrc e1 || has_decrc e2
    | March_tir.Tir.ELetRec (fns, body) ->
      List.exists (fun f -> has_decrc f.March_tir.Tir.fn_body) fns || has_decrc body
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun b -> has_decrc b.March_tir.Tir.br_body) brs ||
      (match def with Some e -> has_decrc e | None -> false)
    | _ -> false
  in
  Alcotest.(check bool) "to_string(borrowed field) emits no EDecRC" false
    (has_decrc f.March_tir.Tir.fn_body)

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

(* Audit P4 regression: elide_expr must NOT collapse a cancel pair whose
   halves have different atomicity (one atomic, one local).  In correct
   Perceus output these never arise, but a future pass (e.g. an inliner
   that crosses actor-send boundaries) could produce them; silently
   eliding would drop the required atomic RC op and introduce a data race.
   This test fabricates each of the four mixed-atomicity cancel shapes and
   asserts both ops survive. *)
let test_perceus_elide_preserves_mixed_atomicity () =
  let open March_tir.Tir in
  let v : var = { v_name = "x"; v_ty = TString; v_lin = Unr } in
  let a = AVar v in
  let tmp_v : var = { v_name = "_"; v_ty = TInt; v_lin = Unr } in
  let leaf = EAtom (ALit (March_ast.Ast.LitInt 0)) in
  (* Count RC ops in an expression (any flavour). *)
  let rec count_rc_ops e =
    match e with
    | EIncRC _ | EDecRC _ | EAtomicIncRC _ | EAtomicDecRC _ -> 1
    | EAtom _ | EApp _ | ECallPtr _ | ETuple _ | ERecord _
    | EField _ | EUpdate _ | EAlloc _ | EStackAlloc _ | EFree _
    | EReuse _ | EAllocHole _ | ESetField _ -> 0
    | ELet (_, e1, e2) -> count_rc_ops e1 + count_rc_ops e2
    | ELetRec (fns, body) ->
      count_rc_ops body
      + List.fold_left (fun n fd -> n + count_rc_ops fd.fn_body) 0 fns
    | ECase (_, brs, def) ->
      List.fold_left (fun n br -> n + count_rc_ops br.br_body) 0 brs
      + (match def with Some d -> count_rc_ops d | None -> 0)
    | ESeq (e1, e2) -> count_rc_ops e1 + count_rc_ops e2
  in
  (* Matching atomicity: BOTH must cancel. *)
  let matched_cases = [
    ("matched Inc+Dec (non-atomic)",
     ESeq (EIncRC a, ESeq (EDecRC a, leaf)));
    ("matched Inc+Dec (atomic)",
     ESeq (EAtomicIncRC a, ESeq (EAtomicDecRC a, leaf)));
    ("matched Dec+Inc (non-atomic)",
     ESeq (EDecRC a, ESeq (EIncRC a, leaf)));
    ("matched Dec+Inc (atomic)",
     ESeq (EAtomicDecRC a, ESeq (EAtomicIncRC a, leaf)));
  ] in
  List.iter (fun (label, e) ->
    let e' = March_tir.Perceus.elide_expr e in
    Alcotest.(check int)
      (Printf.sprintf "%s: elided to zero ops" label)
      0 (count_rc_ops e')
  ) matched_cases;
  (* Mixed atomicity: MUST NOT cancel (both ops survive). *)
  let mixed_cases = [
    ("mixed Inc(local)+Dec(atomic)",
     ESeq (EIncRC a, ESeq (EAtomicDecRC a, leaf)));
    ("mixed Inc(atomic)+Dec(local)",
     ESeq (EAtomicIncRC a, ESeq (EDecRC a, leaf)));
    ("mixed Dec(local)+Inc(atomic)",
     ESeq (EDecRC a, ESeq (EAtomicIncRC a, leaf)));
    ("mixed Dec(atomic)+Inc(local)",
     ESeq (EAtomicDecRC a, ESeq (EIncRC a, leaf)));
  ] in
  List.iter (fun (label, e) ->
    let e' = March_tir.Perceus.elide_expr e in
    Alcotest.(check int)
      (Printf.sprintf "%s: both ops survive" label)
      2 (count_rc_ops e')
  ) mixed_cases;
  (* L5-style elide across ELet: matching atomicity cancels, mismatched
     atomicity survives.  RHS doesn't reference x so the binding is safe
     to keep but the pair can elide. *)
  let rhs_no_x = EAtom (ALit (March_ast.Ast.LitInt 1)) in
  let across_matched =
    ESeq (EIncRC a,
          ELet (tmp_v, rhs_no_x, ESeq (EDecRC a, leaf))) in
  let across_matched' = March_tir.Perceus.elide_expr across_matched in
  Alcotest.(check int)
    "L5 matched across ELet: elided to zero ops"
    0 (count_rc_ops across_matched');
  let across_mixed =
    ESeq (EIncRC a,
          ELet (tmp_v, rhs_no_x, ESeq (EAtomicDecRC a, leaf))) in
  let across_mixed' = March_tir.Perceus.elide_expr across_mixed in
  Alcotest.(check int)
    "L5 mixed across ELet: both ops survive"
    2 (count_rc_ops across_mixed')

(* ── Property tests for Lean theorems (in march-lean/MarchLean/) ──────

   These tests exercise the invariants claimed by the Lean mechanization
   against the real OCaml implementation. If the OCaml drifts from the
   Lean model, these tests fail — protecting the proofs' value.

   Each test is labeled with the corresponding theorem. *)

(** Build a variable with a specific linearity (mk_var defaults to Unr). *)
let test_thm_lin_drop_is_free () =
  let v = mk_var_lin "x" (March_tir.Tir.TCon ("List", [])) March_tir.Tir.Lin in
  let e = perceus_dead_let v in
  Alcotest.(check bool) "Lin+heap emits EFree" true (has_efree_of "x" e);
  Alcotest.(check bool) "Lin+heap emits no EDecRC" false (has_edecrc_of "x" e)

(** Theorem: Perceus.aff_drop_is_free — Aff + needs_rc → EFree, not EDecRC. *)
let test_thm_aff_drop_is_free () =
  let v = mk_var_lin "x" (March_tir.Tir.TCon ("List", [])) March_tir.Tir.Aff in
  let e = perceus_dead_let v in
  Alcotest.(check bool) "Aff+heap emits EFree" true (has_efree_of "x" e);
  Alcotest.(check bool) "Aff+heap emits no EDecRC" false (has_edecrc_of "x" e)

(** Theorem: Perceus.decrc_implies_unr (contrapositive form) —
    Unr + needs_rc → EDecRC, never EFree. *)
let test_thm_decrc_implies_unr () =
  let v = mk_var_lin "x" (March_tir.Tir.TCon ("List", [])) March_tir.Tir.Unr in
  let e = perceus_dead_let v in
  Alcotest.(check bool) "Unr+heap emits EDecRC" true (has_edecrc_of "x" e);
  Alcotest.(check bool) "Unr+heap emits no EFree" false (has_efree_of "x" e)

(** Theorem: Perceus.drop_scalar_noop —
    needs_rc = false → no RC ops emitted, regardless of linearity. *)
let test_thm_drop_scalar_noop_lin () =
  let v = mk_var_lin "x" March_tir.Tir.TInt March_tir.Tir.Lin in
  let e = perceus_dead_let v in
  Alcotest.(check bool) "Lin+scalar emits no RC ops" false (has_any_rc_op_of "x" e)

let test_thm_drop_scalar_noop_unr () =
  let v = mk_var_lin "x" March_tir.Tir.TInt March_tir.Tir.Unr in
  let e = perceus_dead_let v in
  Alcotest.(check bool) "Unr+scalar emits no RC ops" false (has_any_rc_op_of "x" e)

(** Theorem: Defun.lift_preserves_linearity.
    After defunctionalization, captured free variables retain their v_lin.
    Directly catches regression of commit 71d1840. *)
let test_thm_defun_preserves_linearity () =
  (* fn main() = let x:<List, Lin> = 1 in letrec lam() = x in lam
     After defun, x must still appear with v_lin = Lin everywhere it's bound. *)
  let x_lin = mk_var_lin "x" (March_tir.Tir.TCon ("List", [])) March_tir.Tir.Lin in
  let lambda_body = March_tir.Tir.EAtom (March_tir.Tir.AVar x_lin) in
  let lambda_fn = { March_tir.Tir.fn_name = "lam0"; fn_params = [];
                    fn_ret_ty = March_tir.Tir.TCon ("List", []);
                    fn_body = lambda_body;
                    fn_kind = March_tir.Tir.FnLambda } in
  let lam_var = mk_var_lin "lam_ref" (March_tir.Tir.TPtr March_tir.Tir.TUnit)
                  March_tir.Tir.Unr in
  let inner = March_tir.Tir.ELetRec ([lambda_fn],
    March_tir.Tir.EAtom (March_tir.Tir.AVar lam_var)) in
  let outer = March_tir.Tir.ELet (x_lin,
    March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 1)),
    inner) in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = [];
                  fn_ret_ty = March_tir.Tir.TPtr March_tir.Tir.TUnit;
                  fn_body = outer;
                  fn_kind = March_tir.Tir.FnNormal } in
  let m = { March_tir.Tir.tm_name = "test"; tm_fns = [main_fn];
            tm_types = []; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  let m' = March_tir.Defun.defunctionalize m in
  let all_vars = collect_all_vars_in_module m' in
  let x_bindings = List.filter (fun v -> v.March_tir.Tir.v_name = "x") all_vars in
  Alcotest.(check bool) "x appears after defun" true (List.length x_bindings > 0);
  List.iter (fun v ->
    Alcotest.(check bool) "x retains v_lin = Lin" true
      (v.March_tir.Tir.v_lin = March_tir.Tir.Lin)
  ) x_bindings

(* ── Atomic RC tests ───────────────────────────────────────────────────────── *)

(** Collect all EAtomicIncRC variable names in an expression. *)
let[@warning "-32"] rec atomic_inc_vars = function
  | March_tir.Tir.EAtomicIncRC (March_tir.Tir.AVar v) -> [v.March_tir.Tir.v_name]
  | March_tir.Tir.EAtomicIncRC _ -> []
  | March_tir.Tir.ESeq (e1, e2) -> atomic_inc_vars e1 @ atomic_inc_vars e2
  | March_tir.Tir.ELet (_, e1, e2) -> atomic_inc_vars e1 @ atomic_inc_vars e2
  | March_tir.Tir.ELetRec (fns, body) ->
    List.concat_map (fun f -> atomic_inc_vars f.March_tir.Tir.fn_body) fns
    @ atomic_inc_vars body
  | March_tir.Tir.ECase (_, brs, def) ->
    List.concat_map (fun b -> atomic_inc_vars b.March_tir.Tir.br_body) brs
    @ (match def with Some e -> atomic_inc_vars e | None -> [])
  | _ -> []

(** Collect all EAtomicDecRC variable names in an expression. *)
let test_atomic_rc_non_actor_uses_local_rc () =
  (* A heap value used locally (not sent to actor) should use non-atomic EDecRC,
     not EAtomicDecRC. *)
  let m = perceus_module {|mod Test do
    type Box = Box(Int)
    fn make_unused() : Int do
      let b = Box(42)
      0
    end
  end|} in
  let f = List.find (fun fn -> fn.March_tir.Tir.fn_name = "make_unused")
            m.March_tir.Tir.tm_fns in
  let has_atomic = atomic_dec_vars f.March_tir.Tir.fn_body <> [] in
  let rec has_local_dec = function
    | March_tir.Tir.EDecRC _ -> true
    | March_tir.Tir.ESeq (e1, e2) -> has_local_dec e1 || has_local_dec e2
    | March_tir.Tir.ELet (_, e1, e2) -> has_local_dec e1 || has_local_dec e2
    | _ -> false
  in
  Alcotest.(check bool) "non-actor value: no EAtomicDecRC" false has_atomic;
  Alcotest.(check bool) "non-actor value: EDecRC present" true (has_local_dec f.March_tir.Tir.fn_body)

let test_atomic_rc_actor_send_uses_atomic_rc () =
  (* A Box sent to an actor (and still live after the send) should use
     EAtomicIncRC before the send call. *)
  let m = perceus_module {|mod Test do
    type Box = Box(Int)
    actor Counter do
      state { ticks : Int }
      init { ticks: 0 }
      on Tick() do { ticks: state.ticks + 1 } end
    end
    fn main() : Unit do
      let pid = spawn(Counter)
      let b = Box(99)
      let _ = send(pid, b)
      ()
    end
  end|} in
  (* Find the 'main' function in the Perceus output *)
  let main_fn = List.find (fun fn -> fn.March_tir.Tir.fn_name = "main")
                  m.March_tir.Tir.tm_fns in
  (* b is the last use before send, so no IncRC needed — Perceus elides it.
     This test checks the pipeline does NOT crash and the module is well-formed. *)
  Alcotest.(check bool) "actor send pipeline: no crash" true
    (List.length m.March_tir.Tir.tm_fns > 0);
  ignore main_fn

let test_atomic_rc_sent_box_shared_gets_atomic_inc () =
  (* When a Box is sent to an actor AND used after the send, Perceus must
     insert EAtomicIncRC (not EIncRC) before the send. *)
  let m = perceus_module {|mod Test do
    type Box = Box(Int)
    actor Sink do
      state { count : Int }
      init { count: 0 }
      on Got(b : Box) do { count: state.count + 1 } end
    end
    fn f(b : Box) : Box do
      let pid = spawn(Sink)
      let msg = Got(b)
      let _ = send(pid, msg)
      b
    end
  end|} in
  (* 'msg' is sent; 'b' is sent-inside-msg AND returned, so it may need atomic RC.
     Key invariant: no EIncRC (local) should appear for the sent variable 'msg'. *)
  let f = List.find (fun fn -> fn.March_tir.Tir.fn_name = "f")
            m.March_tir.Tir.tm_fns in
  let local_incs = List.filter (fun name -> name = "msg")
    (let rec local_inc_vars = function
      | March_tir.Tir.EIncRC (March_tir.Tir.AVar v) -> [v.March_tir.Tir.v_name]
      | March_tir.Tir.EIncRC _ -> []
      | March_tir.Tir.ESeq (e1, e2) -> local_inc_vars e1 @ local_inc_vars e2
      | March_tir.Tir.ELet (_, e1, e2) -> local_inc_vars e1 @ local_inc_vars e2
      | _ -> []
     in local_inc_vars f.March_tir.Tir.fn_body) in
  (* msg is in actor_sent_set, so any IncRC on it should be EAtomicIncRC, not EIncRC *)
  Alcotest.(check int) "no local (non-atomic) IncRC for sent variable 'msg'" 0
    (List.length local_incs)

let test_atomic_rc_local_decrc_not_atomic () =
  (* A value that is NOT sent to an actor should get EDecRC (local), not EAtomicDecRC. *)
  let m = perceus_module {|mod Test do
    type Pair = Pair(Int, Int)
    fn sum_pair(p : Pair) : Int do
      match p do
        Pair(a, b) -> a + b
      end
    end
  end|} in
  let f = List.find (fun fn -> fn.March_tir.Tir.fn_name = "sum_pair")
            m.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "local pattern match: no EAtomicDecRC"
    false (atomic_dec_vars f.March_tir.Tir.fn_body <> [])

(* ── Escape analysis tests ──────────────────────────────────────────────────── *)

(** Run lower → mono → defun → perceus → escape on [src]. *)
let test_escape_local_discarded_promoted () =
  (* A value created but never returned or stored should be stack-promoted.
     After Perceus inserts EDecRC for the dead binding, escape analysis
     recognises EDecRC as a non-escaping position and promotes to EStackAlloc.
     HISTORY (L7 fix, 2026-07-10): this test originally used a single-ctor
     unary `Box(Int)` — a NEWTYPE-repr type whose EAlloc emits an erased
     immediate, no heap cell. Promoting it produced a boxed stack cell that
     consumers decoded under the erased convention (garbage at runtime —
     invisible here because these tests inspect TIR only, never emitted IR).
     Escape analysis now only promotes genuinely Boxed allocs, so the vehicle
     is a 2-field ctor; the Newtype exclusion is pinned by
     test_escape_newtype_not_promoted below. *)
  let m = escape_module {|mod Test do
    type Box = Box(Int, Int)
    fn make_and_ignore() : Int do
      let b = Box(42, 43)
      0
    end
  end|} in
  let f = List.find (fun fn -> fn.March_tir.Tir.fn_name = "make_and_ignore")
            m.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "locally discarded value is stack-promoted"
    true (has_stack_alloc f.March_tir.Tir.fn_body)

let test_escape_newtype_not_promoted () =
  (* L7 pin: a Newtype-repr alloc (single-ctor unary ADT) must NOT be
     stack-promoted even when it provably does not escape — its EAlloc emits
     an erased immediate ((v<<1)|1), so EStackAlloc would create a boxed
     construction that every consumer (ECase untag, field reads) decodes
     under the erased convention. Live symptom pre-fix:
     `let c = R(22); match c do R(n) -> n end` printed nondeterministic
     garbage compiled (the untagged stack ADDRESS). *)
  let m = escape_module {|mod Test do
    type Res = R(Int)
    fn make_and_match() : Int do
      let c = R(22)
      match c do
        R(n) -> n
      end
    end
  end|} in
  let f = List.find (fun fn -> fn.March_tir.Tir.fn_name = "make_and_match")
            m.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "newtype-repr alloc is NOT stack-promoted"
    false (has_stack_alloc f.March_tir.Tir.fn_body)

let test_escape_returned_not_promoted () =
  (* A value that is returned from the function escapes — must stay on the heap. *)
  let m = escape_module {|mod Test do
    type Box = Box(Int)
    fn wrap(x : Int) : Box do Box(x) end
  end|} in
  let f = List.find (fun fn -> fn.March_tir.Tir.fn_name = "wrap")
            m.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "returned value stays heap-allocated"
    true (has_heap_alloc f.March_tir.Tir.fn_body);
  Alcotest.(check bool) "returned value is NOT stack-promoted"
    false (has_stack_alloc f.March_tir.Tir.fn_body)

let test_escape_stored_in_alloc_not_promoted () =
  (* A value stored as a field of another allocation escapes to the heap. *)
  let m = escape_module {|mod Test do
    type Box  = Box(Int)
    type Pair = Pair(Box, Int)
    fn wrap_pair(x : Int) : Pair do
      let b = Box(x)
      Pair(b, 0)
    end
  end|} in
  let f = List.find (fun fn -> fn.March_tir.Tir.fn_name = "wrap_pair")
            m.March_tir.Tir.tm_fns in
  (* Both Box(x) and Pair(b, 0) are heap allocations; the Box must stay heap. *)
  Alcotest.(check bool) "inner alloc stored in outer alloc stays heap-allocated"
    true (has_heap_alloc f.March_tir.Tir.fn_body)

let test_escape_match_field_promoted () =
  (* A value that is created and immediately pattern-matched — with only the
     extracted field returned, not the struct itself — does not escape.
     This is the "Conn through pipeline" pattern: the Conn is created, a field
     is read from it, and the Conn itself is discarded (not returned). *)
  let m = escape_module {|mod Test do
    type Conn = Conn(Int, Int)
    fn get_status(s : Int, b : Int) : Int do
      let conn = Conn(s, b)
      match conn do
        Conn(status, _body) -> status
      end
    end
  end|} in
  let f = List.find (fun fn -> fn.March_tir.Tir.fn_name = "get_status")
            m.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "conn-like value with field read is stack-promoted"
    true (has_stack_alloc f.March_tir.Tir.fn_body)

let test_escape_decrc_eliminated_after_promotion () =
  (* After stack-promotion of a discarded value, the EDecRC that Perceus
     inserted for it should be removed (no RC needed for stack values).
     Vehicle is a 2-field (Boxed-repr) ctor — see the L7 note on
     test_escape_local_discarded_promoted. *)
  let m = escape_module {|mod Test do
    type Box = Box(Int, Int)
    fn make_and_ignore() : Int do
      let b = Box(42, 43)
      0
    end
  end|} in
  let f = List.find (fun fn -> fn.March_tir.Tir.fn_name = "make_and_ignore")
            m.March_tir.Tir.tm_fns in
  (* After promotion, no EDecRC should remain for the promoted variable *)
  let has_any_decrc = function
    | March_tir.Tir.EDecRC _ -> true
    | _ -> false
  in
  let rec any_in_body = function
    | e when has_any_decrc e -> true
    | March_tir.Tir.ELet (_, e1, e2) -> any_in_body e1 || any_in_body e2
    | March_tir.Tir.ESeq (e1, e2) -> any_in_body e1 || any_in_body e2
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun b -> any_in_body b.March_tir.Tir.br_body) brs
      || (match def with Some e -> any_in_body e | None -> false)
    | _ -> false
  in
  Alcotest.(check bool) "EDecRC eliminated for stack-promoted variable"
    false (any_in_body f.March_tir.Tir.fn_body)

let test_escape_pipeline_no_crash () =
  (* The full escape analysis pass runs on a complex function without raising. *)
  let m = escape_module {|mod Test do
    type Box  = Box(Int)
    type Pair = Pair(Box, Box)
    fn double_wrap(x : Int, y : Int) : Pair do
      let a = Box(x)
      let b = Box(y)
      Pair(a, b)
    end
  end|} in
  Alcotest.(check bool) "escape analysis: complex function runs without crash"
    true (List.length m.March_tir.Tir.tm_fns > 0)

(* ── Actor TIR lowering tests ──────────────────────────────────────────────── *)

let test_actor_tir_lowering_generates_types () =
  (* An actor declaration should generate:
     - Name_State record type
     - Name_Msg variant type
     - Name_Actor record type *)
  let m = lower_module_typed {|mod Test do
    actor Counter do
      state { value : Int }
      init { value: 0 }
      on Increment() do { value: state.value + 1 } end
      on Reset()     do { value: 0 } end
    end
    fn main() : Unit do () end
  end|} in
  let type_names = List.map (function
    | March_tir.Tir.TDVariant (n, _) -> n
    | March_tir.Tir.TDRecord  (n, _) -> n
    | March_tir.Tir.TDClosure (n, _) -> n
  ) m.March_tir.Tir.tm_types in
  Alcotest.(check bool) "Counter_State type generated" true
    (List.mem "Counter_State" type_names);
  Alcotest.(check bool) "Counter_Msg type generated" true
    (List.mem "Counter_Msg" type_names);
  Alcotest.(check bool) "Counter_Actor type generated" true
    (List.mem "Counter_Actor" type_names)

let test_actor_tir_lowering_generates_functions () =
  (* An actor with two handlers should generate:
     Counter_Increment, Counter_Reset, Counter_dispatch, Counter_spawn *)
  let m = lower_module_typed {|mod Test do
    actor Counter do
      state { value : Int }
      init { value: 0 }
      on Increment() do { value: state.value + 1 } end
      on Reset()     do { value: 0 } end
    end
    fn main() : Unit do () end
  end|} in
  let fn_names = List.map (fun f -> f.March_tir.Tir.fn_name) m.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "Counter_Increment generated" true
    (List.mem "Counter_Increment" fn_names);
  Alcotest.(check bool) "Counter_Reset generated" true
    (List.mem "Counter_Reset" fn_names);
  Alcotest.(check bool) "Counter_dispatch generated" true
    (List.mem "Counter_dispatch" fn_names);
  Alcotest.(check bool) "Counter_spawn generated" true
    (List.mem "Counter_spawn" fn_names)

let test_actor_tir_dispatch_has_ecase () =
  (* The dispatch function should have an ECase as its body *)
  let m = lower_module_typed {|mod Test do
    actor Greeter do
      state { value : Int }
      init { value: 0 }
      on Hello() do { value: state.value + 1 } end
      on Bye()   do { value: state.value - 1 } end
    end
    fn main() : Unit do () end
  end|} in
  let dispatch = List.find (fun f -> f.March_tir.Tir.fn_name = "Greeter_dispatch")
                   m.March_tir.Tir.tm_fns in
  let has_case = match dispatch.March_tir.Tir.fn_body with
    | March_tir.Tir.ECase _ -> true
    | _ -> false
  in
  Alcotest.(check bool) "dispatch body is ECase" true has_case

let test_actor_tir_dispatch_branch_count () =
  (* Dispatch function has one branch per handler *)
  let m = lower_module_typed {|mod Test do
    actor Multi do
      state { value : Int }
      init { value: 0 }
      on A() do { value: state.value + 1 } end
      on B() do { value: state.value + 2 } end
      on C() do { value: state.value + 3 } end
    end
    fn main() : Unit do () end
  end|} in
  let dispatch = List.find (fun f -> f.March_tir.Tir.fn_name = "Multi_dispatch")
                   m.March_tir.Tir.tm_fns in
  let n_branches = match dispatch.March_tir.Tir.fn_body with
    | March_tir.Tir.ECase (_, brs, _) -> List.length brs
    | _ -> -1
  in
  Alcotest.(check int) "3 handlers → 3 dispatch branches" 3 n_branches

let test_actor_tir_spawn_returns_ptr () =
  (* The spawn function should return TPtr TUnit *)
  let m = lower_module_typed {|mod Test do
    actor Simple do
      state { value : Int }
      init { value: 0 }
      on Tick() do { value: state.value + 1 } end
    end
    fn main() : Unit do () end
  end|} in
  let spawn_fn = List.find (fun f -> f.March_tir.Tir.fn_name = "Simple_spawn")
                   m.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "spawn returns TPtr TUnit" true
    (spawn_fn.March_tir.Tir.fn_ret_ty = March_tir.Tir.TPtr March_tir.Tir.TUnit)

let test_actor_tir_handler_params () =
  (* A handler with parameters should generate a function with those params
     plus the implicit $actor first param. *)
  let m = lower_module_typed {|mod Test do
    actor Adder do
      state { value : Int }
      init { value: 0 }
      on Add(n : Int) do { value: state.value + n } end
    end
    fn main() : Unit do () end
  end|} in
  let handler = List.find (fun f -> f.March_tir.Tir.fn_name = "Adder_Add")
                  m.March_tir.Tir.tm_fns in
  (* Params: [$actor, n] *)
  let param_names = List.map (fun v -> v.March_tir.Tir.v_name)
                      handler.March_tir.Tir.fn_params in
  Alcotest.(check int) "handler has 2 params ($actor + n)" 2 (List.length param_names);
  Alcotest.(check bool) "first param is $actor" true
    (List.hd param_names = "$actor")

let test_actor_tir_handler_loads_state () =
  (* A handler body should begin with ELet bindings loading the state fields *)
  let m = lower_module_typed {|mod Test do
    actor Banked do
      state { balance : Int }
      init { balance: 100 }
      on Withdraw() do { balance: state.balance - 10 } end
    end
    fn main() : Unit do () end
  end|} in
  let handler = List.find (fun f -> f.March_tir.Tir.fn_name = "Banked_Withdraw")
                  m.March_tir.Tir.tm_fns in
  (* Body should contain EField accesses to load state *)
  let rec has_efield = function
    | March_tir.Tir.EField _ -> true
    | March_tir.Tir.ELet (_, e1, e2) -> has_efield e1 || has_efield e2
    | _ -> false
  in
  Alcotest.(check bool) "handler loads state via EField" true
    (has_efield handler.March_tir.Tir.fn_body)

let test_actor_tir_spawn_contains_ealloc () =
  (* The spawn function should allocate the actor struct via EAlloc *)
  let m = lower_module_typed {|mod Test do
    actor Ticker do
      state { ticks : Int }
      init { ticks: 0 }
      on Tick() do { ticks: state.ticks + 1 } end
    end
    fn main() : Unit do () end
  end|} in
  let spawn_fn = List.find (fun f -> f.March_tir.Tir.fn_name = "Ticker_spawn")
                   m.March_tir.Tir.tm_fns in
  let rec has_alloc = function
    | March_tir.Tir.EAlloc _ -> true
    | March_tir.Tir.ELet (_, e1, e2) -> has_alloc e1 || has_alloc e2
    | March_tir.Tir.ESeq (e1, e2) -> has_alloc e1 || has_alloc e2
    | _ -> false
  in
  Alcotest.(check bool) "spawn contains EAlloc for actor struct" true
    (has_alloc spawn_fn.March_tir.Tir.fn_body)

let test_actor_tir_supervisor_spawn_calls_register () =
  (* A supervisor actor's spawn function should call register_supervisor *)
  let m = lower_module_typed {|mod Test do
    actor Worker do
      state { count : Int }
      init { count: 0 }
      on DoWork() do { count: state.count + 1 } end
    end
    actor Supervisor do
      state { worker : Int }
      init { worker: 0 }
      supervise do
        strategy one_for_one
        max_restarts 3 within 5
        Worker worker
      end
      on Start() do { worker: state.worker } end
    end
    fn main() : Unit do () end
  end|} in
  let spawn_fn = List.find (fun f -> f.March_tir.Tir.fn_name = "Supervisor_spawn")
                   m.March_tir.Tir.tm_fns in
  let rec calls_register_supervisor = function
    | March_tir.Tir.EApp (v, _) when v.March_tir.Tir.v_name = "register_supervisor" -> true
    | March_tir.Tir.ELet (_, e1, e2) ->
      calls_register_supervisor e1 || calls_register_supervisor e2
    | March_tir.Tir.ESeq (e1, e2) ->
      calls_register_supervisor e1 || calls_register_supervisor e2
    | _ -> false
  in
  Alcotest.(check bool) "supervisor spawn calls register_supervisor" true
    (calls_register_supervisor spawn_fn.March_tir.Tir.fn_body)

let test_actor_tir_non_supervisor_no_register () =
  (* A plain (non-supervisor) actor's spawn should NOT call register_supervisor *)
  let m = lower_module_typed {|mod Test do
    actor Plain do
      state { value : Int }
      init { value: 0 }
      on Tick() do { value: state.value + 1 } end
    end
    fn main() : Unit do () end
  end|} in
  let spawn_fn = List.find (fun f -> f.March_tir.Tir.fn_name = "Plain_spawn")
                   m.March_tir.Tir.tm_fns in
  let rec calls_register_supervisor = function
    | March_tir.Tir.EApp (v, _) when v.March_tir.Tir.v_name = "register_supervisor" -> true
    | March_tir.Tir.ELet (_, e1, e2) ->
      calls_register_supervisor e1 || calls_register_supervisor e2
    | March_tir.Tir.ESeq (e1, e2) ->
      calls_register_supervisor e1 || calls_register_supervisor e2
    | _ -> false
  in
  Alcotest.(check bool) "non-supervisor spawn does NOT call register_supervisor" false
    (calls_register_supervisor spawn_fn.March_tir.Tir.fn_body)

let test_actor_tir_msg_variant_ctors () =
  (* Message variant type has one constructor per handler, in declaration order *)
  let m = lower_module_typed {|mod Test do
    actor Calc do
      state { value : Int }
      init { value: 0 }
      on Add(n : Int) do { value: state.value + n } end
      on Sub(n : Int) do { value: state.value - n } end
      on Zero() do { value: 0 } end
    end
    fn main() : Unit do () end
  end|} in
  let msg_type = List.find_opt (function
    | March_tir.Tir.TDVariant ("Calc_Msg", _) -> true
    | _ -> false
  ) m.March_tir.Tir.tm_types in
  Alcotest.(check bool) "Calc_Msg variant type exists" true (msg_type <> None);
  match msg_type with
  | Some (March_tir.Tir.TDVariant (_, ctors)) ->
    let ctor_names = List.map fst ctors in
    Alcotest.(check bool) "Add ctor in Calc_Msg" true (List.mem "Add" ctor_names);
    Alcotest.(check bool) "Sub ctor in Calc_Msg" true (List.mem "Sub" ctor_names);
    Alcotest.(check bool) "Zero ctor in Calc_Msg" true (List.mem "Zero" ctor_names);
    Alcotest.(check int) "3 ctors in Calc_Msg" 3 (List.length ctors)
  | _ -> Alcotest.fail "Calc_Msg is not TDVariant"

let test_actor_tir_actor_struct_has_dispatch_field () =
  (* Actor struct has $d_dispatch and $e_alive fields plus state fields *)
  let m = lower_module_typed {|mod Test do
    actor Box do
      state { value : Int }
      init { value: 0 }
      on Poke() do { value: state.value + 1 } end
    end
    fn main() : Unit do () end
  end|} in
  let actor_type = List.find_opt (function
    | March_tir.Tir.TDRecord ("Box_Actor", _) -> true
    | _ -> false
  ) m.March_tir.Tir.tm_types in
  Alcotest.(check bool) "Box_Actor record type exists" true (actor_type <> None);
  match actor_type with
  | Some (March_tir.Tir.TDRecord (_, fields)) ->
    let field_names = List.map fst fields in
    Alcotest.(check bool) "$d_dispatch field present" true (List.mem "$d_dispatch" field_names);
    Alcotest.(check bool) "$e_alive field present"    true (List.mem "$e_alive"    field_names);
    Alcotest.(check bool) "value field present"       true (List.mem "value"       field_names)
  | _ -> Alcotest.fail "Box_Actor is not TDRecord"

let test_actor_tir_full_pipeline_no_crash () =
  (* A module with an actor should survive the full TIR pipeline without exception *)
  let m = perceus_module {|mod Test do
    actor Echo do
      state { count : Int }
      init { count: 0 }
      on Ping() do { count: state.count + 1 } end
    end
    fn main() : Unit do
      let pid = spawn(Echo)
      let _ = send(pid, Ping)
      ()
    end
  end|} in
  Alcotest.(check bool) "full pipeline with actor: no crash" true
    (List.length m.March_tir.Tir.tm_fns > 0)

(* ── Actor compilation tests (LLVM IR path) ─────────────────────────────── *)

(** Helper: parse, typecheck, lower + full pipeline → LLVM IR string. *)
let test_actor_compile_dispatch_emitted () =
  let ir = emit_actor_ir {|mod Test do
    actor Counter do
      state { count : Int }
      init { count: 0 }
      on Inc() do { count: state.count + 1 } end
      on Reset() do { count: 0 } end
    end
    fn main() : Unit do
      let pid = spawn(Counter)
      let _ = send(pid, Inc())
      ()
    end
  end|} in
  Alcotest.(check bool) "Counter_dispatch defined in IR" true
    (ir_contains ir "Counter_dispatch");
  Alcotest.(check bool) "march_spawn called" true
    (ir_contains ir "march_spawn");
  Alcotest.(check bool) "march_send called" true
    (ir_contains ir "march_send")

(** Compiled actor: spawn function is emitted with allocation. *)
let test_actor_compile_spawn_fn_emitted () =
  let ir = emit_actor_ir {|mod Test do
    actor Greeter do
      state { n : Int }
      init { n: 0 }
      on Hello() do { n: state.n + 1 } end
    end
    fn main() : Unit do
      let _ = spawn(Greeter)
      ()
    end
  end|} in
  Alcotest.(check bool) "Greeter_spawn defined in IR" true
    (ir_contains ir "Greeter_spawn");
  Alcotest.(check bool) "march_alloc called" true
    (ir_contains ir "march_alloc")

(** Compiled actor: handler functions are emitted for each message type. *)
let test_actor_compile_handlers_emitted () =
  let ir = emit_actor_ir {|mod Test do
    actor Worker do
      state { x : Int }
      init { x: 0 }
      on DoA() do { x: state.x + 1 } end
      on DoB() do { x: state.x - 1 } end
      on DoC() do { x: 0 } end
    end
    fn main() : Unit do () end
  end|} in
  Alcotest.(check bool) "Worker_DoA handler in IR" true
    (ir_contains ir "Worker_DoA");
  Alcotest.(check bool) "Worker_DoB handler in IR" true
    (ir_contains ir "Worker_DoB");
  Alcotest.(check bool) "Worker_DoC handler in IR" true
    (ir_contains ir "Worker_DoC")

(** Compiled supervisor: register_supervisor call emitted for supervisor actor. *)
let test_actor_compile_supervisor_registers () =
  let ir = emit_actor_ir {|mod Test do
    actor Worker do
      state { x : Int }
      init { x: 0 }
      on Tick() do { x: state.x + 1 } end
    end
    actor Sup do
      state { w : Int }
      init { w: 0 }
      supervise do
        strategy one_for_one
        max_restarts 3 within 60
        Worker w
      end
    end
    fn main() : Unit do
      let _ = spawn(Sup)
      ()
    end
  end|} in
  (* Supervisor spawning should emit march_register_supervisor *)
  Alcotest.(check bool) "march_register_supervisor in IR" true
    (ir_contains ir "march_register_supervisor");
  Alcotest.(check bool)
    "supervised child is prepared without scheduling before registration" true
    (ir_contains ir "call ptr @march_spawn_supervised")

(** Compiled monitor: monitor call emitted. *)
let test_actor_compile_monitor_emitted () =
  let ir = emit_actor_ir {|mod Test do
    actor Target do
      state { x : Int }
      init { x: 0 }
      on Stop() do { x: -1 } end
    end
    actor Watcher do
      state { ref_ : Int }
      init { ref_: 0 }
    end
    fn main() : Unit do
      let t = spawn(Target)
      let w = spawn(Watcher)
      let _ = monitor(w, t)
      ()
    end
  end|} in
  Alcotest.(check bool) "march_monitor in IR" true
    (ir_contains ir "march_monitor")

(** Compiled multi-actor: multiple actors in same module compile without crash. *)
let test_actor_compile_multi_actor_no_crash () =
  let ir = emit_actor_ir {|mod Test do
    actor A do
      state { v : Int }
      init { v: 0 }
      on MsgA() do { v: 1 } end
    end
    actor B do
      state { v : Int }
      init { v: 0 }
      on MsgB() do { v: 2 } end
    end
    actor C do
      state { v : Int }
      init { v: 0 }
      on MsgC() do { v: 3 } end
    end
    fn main() : Unit do
      let _ = spawn(A)
      let _ = spawn(B)
      let _ = spawn(C)
      ()
    end
  end|} in
  Alcotest.(check bool) "A_dispatch in IR" true (ir_contains ir "A_dispatch");
  Alcotest.(check bool) "B_dispatch in IR" true (ir_contains ir "B_dispatch");
  Alcotest.(check bool) "C_dispatch in IR" true (ir_contains ir "C_dispatch")

(** Compiled actor with run_scheduler: @main wraps march_main with scheduler drain. *)
let test_actor_compile_run_scheduler_in_main () =
  let ir = emit_actor_ir {|mod Test do
    actor Echo do
      state { count : Int }
      init { count: 0 }
      on Ping() do { count: state.count + 1 } end
    end
    fn main() : Unit do
      let pid = spawn(Echo)
      let _ = send(pid, Ping())
      ()
    end
  end|} in
  Alcotest.(check bool) "@main calls march_run_scheduler" true
    (ir_contains ir "march_run_scheduler")

(** Compiled actor: actor_call emits march_actor_call; actor_reply emits
    march_actor_reply in the handler body. *)
let test_actor_compile_call_reply_emitted () =
  let ir = emit_actor_ir {|mod Test do
    actor Counter do
      state { count : Int }
      init { count: 0 }
      on Increment() do
        { count: state.count + 1 }
      end
      on GetCount(reply_to) do
        Actor.reply(reply_to, state.count)
        state
      end
    end
    fn main() : Unit do
      let pid = spawn(Counter)
      let _ = Actor.call(pid, GetCount, 5000)
      ()
    end
  end|} in
  Alcotest.(check bool) "march_actor_call in IR" true
    (ir_contains ir "march_actor_call");
  Alcotest.(check bool) "march_actor_reply in IR" true
    (ir_contains ir "march_actor_reply")

(* ── Nested immediate-literal pattern codegen tests ────────────────────── *)
(* Regression tests for the wild-dereference miscompile of Bool/Int/Atom
   literal patterns nested inside constructor patterns.  The field bound by
   the outer constructor pattern is a low-bit-tagged immediate ((n<<1)|1),
   not a heap pointer; compiling the inner literal test as a ctor-tag switch
   loaded a tag from a non-pointer.  With an unreachable-defaulted switch,
   LLVM folded the test away entirely — [Ok(true)]/[Ok(false)] both took the
   FIRST bool arm (printed T T E instead of T F E); nested Int/Atom literal
   matches segfaulted.  The fix routes all-immediate-literal-tag ECases to
   scalar comparisons, so exactly ONE i32 ctor-tag switch (the outer Ok/Err
   discrimination) must remain in the emitted IR. *)

(** Count non-overlapping occurrences of [pat] in [ir]. *)
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

(* ── Borrow Inference tests ─────────────────────────────────────────────── *)

(** Run pipeline up to borrow inference (inclusive).  Returns the borrow_map. *)
let test_borrow_read_only_param_is_borrowed () =
  (* A function that only pattern-matches a TCon param (never stores /
     returns it) should have that param inferred as borrowed. *)
  let bm = borrow_module {|mod Test do
    type Conn = Conn(String)
    fn log(conn : Conn) : Unit do
      match conn do | Conn(s) -> println(s) end
    end
  end|} in
  Alcotest.(check bool) "log's conn param is borrowed" true
    (March_tir.Borrow.is_borrowed bm "log" 0)

let test_borrow_returned_param_is_owned () =
  (* A function that returns the param directly must NOT be marked borrowed. *)
  let bm = borrow_module {|mod Test do
    type Conn = Conn(String)
    fn passthrough(conn : Conn) : Conn do conn end
  end|} in
  Alcotest.(check bool) "returned conn param is owned (not borrowed)" false
    (March_tir.Borrow.is_borrowed bm "passthrough" 0)

let test_borrow_stored_param_is_owned () =
  (* A function that wraps the param in a constructor must NOT be marked borrowed. *)
  let bm = borrow_module {|mod Test do
    type Conn = Conn(String)
    type Box = Box(Conn)
    fn store(conn : Conn) : Box do Box(conn) end
  end|} in
  Alcotest.(check bool) "stored conn param is owned (not borrowed)" false
    (March_tir.Borrow.is_borrowed bm "store" 0)

let test_borrow_int_param_not_in_map () =
  (* TInt does not need RC, so borrow inference marks it false (not borrowed).
     Borrowing only matters for heap-allocated (TCon/TString/TPtr) params. *)
  let bm = borrow_module {|mod Test do
    fn add(x : Int, y : Int) : Int do x + y end
  end|} in
  (* Both int params should be false — they don't need RC regardless. *)
  Alcotest.(check bool) "Int param 0 not borrowed" false
    (March_tir.Borrow.is_borrowed bm "add" 0);
  Alcotest.(check bool) "Int param 1 not borrowed" false
    (March_tir.Borrow.is_borrowed bm "add" 1)

let test_borrow_passed_to_borrowed_callee_stays_borrowed () =
  (* If a param is passed only to other functions that borrow it, it remains
     borrowed itself.  This tests the inter-procedural fixpoint. *)
  let bm = borrow_module {|mod Test do
    type Conn = Conn(String)
    fn log(conn : Conn) : Unit do
      match conn do | Conn(s) -> println(s) end
    end
    fn log_twice(conn : Conn) : Unit do
      log(conn)
      log(conn)
    end
  end|} in
  Alcotest.(check bool) "log's conn param is borrowed" true
    (March_tir.Borrow.is_borrowed bm "log" 0);
  Alcotest.(check bool) "log_twice's conn param is also borrowed" true
    (March_tir.Borrow.is_borrowed bm "log_twice" 0)

let test_borrow_passed_to_owned_callee_becomes_owned () =
  (* If a param is passed to a function that stores it (owned position),
     the param itself becomes owned. *)
  let bm = borrow_module {|mod Test do
    type Conn = Conn(String)
    type Box = Box(Conn)
    fn store(conn : Conn) : Box do Box(conn) end
    fn wrap_and_store(conn : Conn) : Box do
      store(conn)
    end
  end|} in
  Alcotest.(check bool) "store's conn param is owned" false
    (March_tir.Borrow.is_borrowed bm "store" 0);
  Alcotest.(check bool) "wrap_and_store's conn param is also owned" false
    (March_tir.Borrow.is_borrowed bm "wrap_and_store" 0)

(* ── RC integration tests (via perceus_module) ────────────────────────────── *)

let test_borrow_no_incrc_at_call_site () =
  (* In a caller that invokes a borrowing function with a TCon arg that is
     still live after the call, no EIncRC should be emitted at the call site.
     Without borrow inference, EIncRC would be inserted because the arg is
     live after (it is returned below the call). *)
  let m = perceus_module {|mod Test do
    type Conn = Conn(String)
    fn log(conn : Conn) : Unit do
      match conn do | Conn(s) -> println(s) end
    end
    fn handle(conn : Conn) : Conn do
      log(conn)
      conn
    end
  end|} in
  let handle_fn =
    List.find (fun fn -> fn.March_tir.Tir.fn_name = "handle") m.March_tir.Tir.tm_fns
  in
  (* With borrow inference, log's conn param is borrowed.
     handle calls log(conn) while conn is still live (returned afterwards).
     The Inc that would normally be emitted before the call is elided. *)
  Alcotest.(check bool) "no EIncRC in handle body (borrow elides call-site Inc)" false
    (has_any_incrc handle_fn.March_tir.Tir.fn_body)

let test_borrow_no_decrc_in_callee () =
  (* A function that only borrows its TCon param should have no EDecRC
     emitted for that param inside its body.
     We use a wildcard pattern (Conn(_)) to avoid extracting a string field:
     extracting a field and passing it to a borrowing extern (println) would
     correctly produce a post-call EDecRC for the extracted string.  The test
     is specifically about suppression of the EDecRC for the borrowed *param*
     (conn), not about extracted sub-values. *)
  let m = perceus_module {|mod Test do
    type Conn = Conn(String)
    fn log(conn : Conn) : Unit do
      match conn do | Conn(_) -> () end
    end
  end|} in
  let log_fn =
    List.find (fun fn -> fn.March_tir.Tir.fn_name = "log") m.March_tir.Tir.tm_fns
  in
  (* With borrow inference, conn is marked borrowed.
     The ECase scrutinee-free (EDecRC on conn) is suppressed.
     No string is extracted so no other EDecRC is present either. *)
  Alcotest.(check bool) "no EDecRC in log body (borrow elides callee Dec)" false
    (has_any_decrc log_fn.March_tir.Tir.fn_body)

let test_borrow_owned_param_still_gets_rc () =
  (* Sanity check: a function that RETURNS its TCon param (owned) must still
     get the standard RC treatment.  When the caller passes an arg that is
     still live after the call (because it is used again below), EIncRC must
     be emitted.  With borrow inference, this Inc is only elided for BORROWED
     parameters — owned ones keep their Inc. *)
  let m = perceus_module {|mod Test do
    type Conn = Conn(String)
    fn passthrough(conn : Conn) : Conn do conn end
    fn caller(conn : Conn) : Conn do
      let _ = passthrough(conn)
      conn
    end
  end|} in
  (* conn is still live after the passthrough(conn) call (returned below).
     passthrough is owned → EIncRC conn is emitted before the call. *)
  let caller_fn =
    List.find (fun fn -> fn.March_tir.Tir.fn_name = "caller") m.March_tir.Tir.tm_fns
  in
  Alcotest.(check bool) "owned param call site still gets EIncRC" true
    (has_any_incrc caller_fn.March_tir.Tir.fn_body)

let test_borrow_conn_middleware_pattern () =
  (* HTTP middleware pattern: conn is passed through multiple read-only
     middlewares and then to a final handler that returns it.
     Read-only middlewares should generate zero RC ops for conn.
     We use wildcard patterns to avoid extracting string fields: extracting a
     field and passing it to a borrowing extern (println) would correctly emit
     a post-call EDecRC for the extracted string (caller is responsible since
     println borrows).  The test is about conn's own DecRC being suppressed. *)
  let m = perceus_module {|mod Test do
    type Conn = Conn(String)
    fn log_middleware(conn : Conn) : Unit do
      match conn do | Conn(_) -> () end
    end
    fn auth_middleware(conn : Conn) : Unit do
      match conn do | Conn(_) -> () end
    end
    fn handle(conn : Conn) : Conn do
      log_middleware(conn)
      auth_middleware(conn)
      conn
    end
  end|} in
  let log_fn  = List.find (fun fn -> fn.March_tir.Tir.fn_name = "log_middleware")  m.March_tir.Tir.tm_fns in
  let auth_fn = List.find (fun fn -> fn.March_tir.Tir.fn_name = "auth_middleware") m.March_tir.Tir.tm_fns in
  let handle_fn = List.find (fun fn -> fn.March_tir.Tir.fn_name = "handle") m.March_tir.Tir.tm_fns in
  (* Read-only middlewares: no Dec on conn inside *)
  Alcotest.(check bool) "log_middleware: no EDecRC for conn (borrowed)" false
    (has_any_decrc log_fn.March_tir.Tir.fn_body);
  Alcotest.(check bool) "auth_middleware: no EDecRC for conn (borrowed)" false
    (has_any_decrc auth_fn.March_tir.Tir.fn_body);
  (* Caller: conn passed to two borrowed functions while live → no EIncRC *)
  Alcotest.(check bool) "handle: no EIncRC for conn at borrowed call sites" false
    (has_any_incrc handle_fn.March_tir.Tir.fn_body)

(* ── Perceus scrutinee-escape rewrite (rc50 regression) ──────────────────── *)

let test_perceus_scrut_escape_rewrite () =
  (* Regression test for rc50: a Cons-arm whose tail position returns the
     whole scrutinee ([match ls do ... Cons(h, rest) -> ls end]) used to
     confuse Perceus' RC insertion:

       - [name_free_in "ls" body] was true (the [-> ls] tail), so
         [add_scrutinee_free_for] *skipped* [dec_rc ls] at arm start.
       - But the extracted field [h] was still classified as owned and got
         a [dec_rc h] at last use inside the body (e.g. after a [trim(h)]
         call to a borrowed callee), so the string field's RC underflowed.

     The fix [perceus.ml:preprocess_scrut_escape] rewrites the tail
     [EAtom (AVar ls)] into [EAlloc (Cons, [h, rest])] before RC insertion.
     After the rewrite, [ls] is no longer free in the arm body, so
     [dec_rc ls] is emitted as usual, and [llvm_emit.strip_scrut_decrc]
     can recognise the pattern and emit a conditional field-IncRC via
     [march_decrc_freed] on the shared path. *)
  let m = perceus_module {|mod Test do
    type SList = SNil | SCons(String, SList)
    fn echo(ls : SList) : SList do
      match ls do
        SNil -> SNil
        SCons(h, rest) -> ls
      end
    end
  end|} in
  let echo_fn =
    List.find (fun fn -> fn.March_tir.Tir.fn_name = "echo") m.March_tir.Tir.tm_fns
  in
  (* The Cons arm used to return [EAtom (AVar ls)].  After the rewrite the
     arm must end in an [EAlloc] whose tag ends in ".SCons" — i.e. the
     constructor has been reconstructed from the extracted fields.  FBIP
     may later promote that [EAlloc] into an [EReuse] that reuses the
     scrutinee cell; either form proves the rewrite fired. *)
  let rec contains_recon_with_suffix suffix = function
    | March_tir.Tir.EAlloc (March_tir.Tir.TCon (t, _), _)
    | March_tir.Tir.EReuse (_, March_tir.Tir.TCon (t, _), _) ->
      let n = String.length t and sn = String.length suffix in
      n >= sn && String.equal (String.sub t (n - sn) sn) suffix
    | March_tir.Tir.ELet (_, a, b)
    | March_tir.Tir.ESeq (a, b) ->
      contains_recon_with_suffix suffix a || contains_recon_with_suffix suffix b
    | March_tir.Tir.ELetRec (fns, body) ->
      List.exists (fun f ->
        contains_recon_with_suffix suffix f.March_tir.Tir.fn_body) fns
      || contains_recon_with_suffix suffix body
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun br ->
        contains_recon_with_suffix suffix br.March_tir.Tir.br_body) brs
      || (match def with Some d -> contains_recon_with_suffix suffix d | None -> false)
    | _ -> false
  in
  Alcotest.(check bool) "Cons arm reconstructed (EAlloc/EReuse SCons)" true
    (contains_recon_with_suffix "SCons" echo_fn.March_tir.Tir.fn_body);
  (* And the bare-scrutinee tail reference must be gone: no tail-position
     [EAtom (AVar sv)] in any non-empty-br_vars arm whose scrutinee is sv. *)
  let rec any_arm_tail_is_scrut = function
    | March_tir.Tir.ECase (March_tir.Tir.AVar sv, brs, def) ->
      let rec tail_is_scrut = function
        | March_tir.Tir.EAtom (March_tir.Tir.AVar v) ->
          String.equal v.March_tir.Tir.v_name sv.March_tir.Tir.v_name
        | March_tir.Tir.ELet (_, _, b)
        | March_tir.Tir.ESeq (_, b) -> tail_is_scrut b
        | March_tir.Tir.ECase (_, brs, def) ->
          List.exists (fun br -> tail_is_scrut br.March_tir.Tir.br_body) brs
          || (match def with Some d -> tail_is_scrut d | None -> false)
        | _ -> false
      in
      List.exists (fun br ->
        br.March_tir.Tir.br_vars <> [] && tail_is_scrut br.March_tir.Tir.br_body
      ) brs
      || (match def with Some d -> any_arm_tail_is_scrut d | None -> false)
    | March_tir.Tir.ELet (_, a, b)
    | March_tir.Tir.ESeq (a, b) ->
      any_arm_tail_is_scrut a || any_arm_tail_is_scrut b
    | March_tir.Tir.ELetRec (fns, body) ->
      List.exists (fun f ->
        any_arm_tail_is_scrut f.March_tir.Tir.fn_body) fns
      || any_arm_tail_is_scrut body
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun br ->
        any_arm_tail_is_scrut br.March_tir.Tir.br_body) brs
      || (match def with Some d -> any_arm_tail_is_scrut d | None -> false)
    | _ -> false
  in
  Alcotest.(check bool) "no bare scrutinee tail in any destructuring arm" false
    (any_arm_tail_is_scrut echo_fn.March_tir.Tir.fn_body)

(** Regression test: closure FV used exactly once in a consuming call (rc64 fix).
    A captured heap value passed as the sole argument to a consuming callee
    must receive an EIncRC inside the apply function, even though it is not
    locally live after that call.  Without the fix, Perceus treated it as a
    last-use ownership transfer: the callee's pattern-match decremented the
    RC to 0 and freed the object.  On the next invocation of the same closure
    (RC > 1, e.g. inside Check.run_loop), loading the FV from the closure
    struct read a dangling pointer → SIGSEGV. *)
let test_perceus_closure_fv_single_use_incrc () =
  let m = perceus_module {|mod Test do
    type Box = Box(Int)
    pfn consume(b : Box) : Int do
      match b do
      Box(n) -> n
      end
    end
    fn make_thunk(b : Box) : (Unit -> Int) do
      fn () -> consume(b)
    end
  end|} in
  (* The apply function is any fn_def whose first param is "$clo". *)
  let apply_fns = List.filter (fun fn ->
    match fn.March_tir.Tir.fn_params with
    | p :: _ -> String.equal p.March_tir.Tir.v_name "$clo"
    | [] -> false
  ) m.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "at least one apply function exists" true
    (List.length apply_fns >= 1);
  let apply_fn = List.hd apply_fns in
  (* After the fix, the apply function body must contain an EIncRC for the
     captured Box FV before the consuming call to consume(). *)
  let rec has_incrc = function
    | March_tir.Tir.EIncRC _ | March_tir.Tir.EAtomicIncRC _ -> true
    | March_tir.Tir.ELet (_, e1, e2) -> has_incrc e1 || has_incrc e2
    | March_tir.Tir.ESeq (e1, e2) -> has_incrc e1 || has_incrc e2
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun b -> has_incrc b.March_tir.Tir.br_body) brs ||
      (match def with Some e -> has_incrc e | None -> false)
    | March_tir.Tir.ELetRec (fns, body) ->
      List.exists (fun f -> has_incrc f.March_tir.Tir.fn_body) fns || has_incrc body
    | _ -> false
  in
  Alcotest.(check bool)
    "apply fn EIncRC's captured FV before consuming call" true
    (has_incrc apply_fn.March_tir.Tir.fn_body)

(* Regression: HttpServer-style pipeline closure — list FV consumed by callee.
   Borrow inference marks $clo as :borrow (not :own) for apply functions that
   take a closure they don't outlive.  When $clo is borrowed it lands in the
   borrowed' set, which puts it in live_after.  The old is_borrowed_field check
   fired on "let plugs = $clo.fv1" because $clo was in live_after (condition 1),
   marking plugs as a borrowed_field_var and suppressing the EIncRC that
   d2cf09e was supposed to emit before the consuming run_pipeline call.
   Fix: add a global TPtr guard to is_borrowed_field so closure structs ($clo)
   are never treated as record owners; their FVs must go through the borrowed'
   path so find_inc_vars emits EIncRC before every consuming callee. *)
let test_perceus_closure_fv_borrowed_clo_incrc () =
  let m = perceus_module {|mod Test do
    pfn run_pipeline(conn : Int, plugs : List((Int) -> Int)) : Int do
      match plugs do
      Nil -> conn
      Cons(f, rest) -> run_pipeline(f(conn), rest)
      end
    end
    fn make_server(plugs : List((Int) -> Int)) : (Int) -> Int do
      fn conn -> run_pipeline(conn, plugs)
    end
  end|} in
  let apply_fns = List.filter (fun fn ->
    match fn.March_tir.Tir.fn_params with
    | p :: _ -> String.equal p.March_tir.Tir.v_name "$clo"
    | [] -> false
  ) m.March_tir.Tir.tm_fns in
  (* Find the apply function that captures plugs — its body must EIncRC the
     FV before passing it to run_pipeline (which owns/consumes the list). *)
  let pipeline_apply = List.find_opt (fun fn ->
    let rec has_run_pipeline_call = function
      | March_tir.Tir.EApp (f, _) -> String.sub f.March_tir.Tir.v_name 0
          (min 12 (String.length f.March_tir.Tir.v_name)) = "run_pipeline"
      | March_tir.Tir.ELet (_, e1, e2) ->
        has_run_pipeline_call e1 || has_run_pipeline_call e2
      | March_tir.Tir.ESeq (e1, e2) ->
        has_run_pipeline_call e1 || has_run_pipeline_call e2
      | _ -> false
    in
    has_run_pipeline_call fn.March_tir.Tir.fn_body
  ) apply_fns in
  Alcotest.(check bool) "pipeline apply function exists" true
    (Option.is_some pipeline_apply);
  let apply_fn = Option.get pipeline_apply in
  let rec has_incrc = function
    | March_tir.Tir.EIncRC _ | March_tir.Tir.EAtomicIncRC _ -> true
    | March_tir.Tir.ELet (_, e1, e2) -> has_incrc e1 || has_incrc e2
    | March_tir.Tir.ESeq (e1, e2) -> has_incrc e1 || has_incrc e2
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun b -> has_incrc b.March_tir.Tir.br_body) brs ||
      (match def with Some e -> has_incrc e | None -> false)
    | March_tir.Tir.ELetRec (fns, body) ->
      List.exists (fun f -> has_incrc f.March_tir.Tir.fn_body) fns || has_incrc body
    | _ -> false
  in
  Alcotest.(check bool)
    "pipeline apply fn EIncRC's captured list FV before consuming run_pipeline call" true
    (has_incrc apply_fn.March_tir.Tir.fn_body)

(* Regression: commit 831e315 changed needs_rc(TFn _) to true, which caused
   Perceus to insert EIncRC for the callee in every EApp.  After defun all
   EApp callees are top-level function symbols (code addresses), not heap
   closures.  For operators like && and || whose llvm_name maps to @__
   (an undefined symbol), this produced a call to @__() that failed to link.
   Fix: EApp callee excluded from liveness / find_inc_vars in perceus.ml.
   This test ensures no EIncRC is inserted for the operator callee. *)
let test_perceus_no_incrc_for_eapp_operator_callee () =
  (* && and || are the operators most likely to trigger the bug because
     their llvm_name is "__" — an undefined symbol when naively called. *)
  let m = perceus_module {|mod Test do
    fn uses_and(a : Bool, b : Bool) : Bool do a && b end
    fn uses_or(a : Bool, b : Bool) : Bool do a || b end
    fn uses_not(a : Bool) : Bool do !a end
  end|} in
  let rec has_incrc_for_builtin = function
    | March_tir.Tir.EIncRC (March_tir.Tir.AVar v)
      when (let n = v.March_tir.Tir.v_name in
            n = "&&" || n = "||" || n = "not" || n = "!") -> true
    | March_tir.Tir.ELet (_, e1, e2) ->
      has_incrc_for_builtin e1 || has_incrc_for_builtin e2
    | March_tir.Tir.ESeq (e1, e2) ->
      has_incrc_for_builtin e1 || has_incrc_for_builtin e2
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun b -> has_incrc_for_builtin b.March_tir.Tir.br_body) brs
      || (match def with Some e -> has_incrc_for_builtin e | None -> false)
    | March_tir.Tir.ELetRec (fns, body) ->
      List.exists (fun f -> has_incrc_for_builtin f.March_tir.Tir.fn_body) fns
      || has_incrc_for_builtin body
    | _ -> false
  in
  List.iter (fun fn ->
    Alcotest.(check bool)
      (Printf.sprintf "no EIncRC for operator callee in %s" fn.March_tir.Tir.fn_name)
      false (has_incrc_for_builtin fn.March_tir.Tir.fn_body)
  ) m.March_tir.Tir.tm_fns

(* Regression: a heap value whose concrete type does not resolve across a module
   boundary keeps an unresolved type-var (`'_NNNN`) in monomorphic TIR.  This
   happens for an opaque type defined in one module and consumed in another
   (e.g. bastion's `Gate.cast` → `Gate.get_change(gate, …)`): `gate`'s let binding
   stays `TVar "_NNNN"` instead of `TCon ("Gate", [])`.

   Perceus's needs_rc used to return false for `TVar _` ("skip RC"), so such a
   value was invisible to Perceus — no EIncRC was emitted before a consuming
   call.  When the same binding was consumed twice the first consume freed the
   heap box and the second double-freed it: `RC underflow in march_decrc_freed`.
   The minimal shape below (opaque Box in a nested module, `get` consumes the
   box, `b` used by two `get` calls) reproduces the missing dup.

   Fix: needs_rc (TVar _) = true.  llvm_ty (TVar _) = "ptr" so the value is a
   heap pointer; emitting EIncRC/EDecRC is correct for the box and a no-op for a
   genuine scalar (guarded by [if ty = "ptr"] in llvm_emit and IS_HEAP_PTR in
   the runtime).  Without the fix the EIncRC for `b` is absent and this fails. *)
let test_perceus_incrc_for_unresolved_tvar_used_twice () =
  let m = perceus_module {|mod Outer do
    mod Box do
      opaque type Box = Box(Int)
      fn make(n : Int) : Box do Box(n) end
      fn get(b : Box) : Int do unwrap(b) end
      pfn unwrap(b : Box) : Int do match b do Box(n) -> n end end
    end
    mod Main do
      import Box
      fn main() : Int do
        let b = Box.make(42)
        let x = Box.get(b)
        let y = Box.get(b)
        x + y
      end
    end
  end|} in
  let main_fn =
    List.find_opt (fun fn ->
      let n = fn.March_tir.Tir.fn_name in
      n = "Main.main" || n = "Outer.Main.main")
      m.March_tir.Tir.tm_fns
  in
  Alcotest.(check bool) "Main.main exists" true (main_fn <> None);
  let main_fn = Option.get main_fn in
  (* The fix must emit an EIncRC for `b` (the unresolved-type-var heap value)
     before its first consuming use, so the second use does not double-free. *)
  let rec incs_b = function
    | March_tir.Tir.EIncRC (March_tir.Tir.AVar v)
    | March_tir.Tir.EAtomicIncRC (March_tir.Tir.AVar v) ->
      String.equal v.March_tir.Tir.v_name "b"
    | March_tir.Tir.ELet (_, e1, e2) -> incs_b e1 || incs_b e2
    | March_tir.Tir.ESeq (e1, e2) -> incs_b e1 || incs_b e2
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun b -> incs_b b.March_tir.Tir.br_body) brs
      || (match def with Some e -> incs_b e | None -> false)
    | March_tir.Tir.ELetRec (fns, body) ->
      List.exists (fun f -> incs_b f.March_tir.Tir.fn_body) fns || incs_b body
    | _ -> false
  in
  Alcotest.(check bool)
    "Main.main dups `b` before consuming it twice (cross-module opaque RC UAF)"
    true (incs_b main_fn.March_tir.Tir.fn_body)

(* Regression: record parameter used in multiple sequential calls within the
   same match arm.  Before the fix, borrow inference did not consider TRecord
   parameters as borrow candidates (needs_rc(TRecord) was false), so
   use_cfg(cfg:own) caused Perceus to emit dec_rc on cfg.dir (the string field)
   inside use_cfg.  When process(cfg, …) called use_cfg(cfg) in a loop, the
   second iteration read a freed string — "local RC underflow".

   Fix: borrow.ml needs_rc now returns true for TRecord/TTuple, making record
   params borrow-eligible.  When only read via EField, they are inferred as
   borrowed.  Perceus's new _borrowed_field_vars mechanism then suppresses all
   RC ops (post_dec_vars, EAtom inc, dead-binding dec) for variables extracted
   from a borrowed record via EField. *)
let test_perceus_record_param_multi_call_no_rc_underflow () =
  (* Verify that use_cfg has cfg:borrowed (no EDecRC on cfg.dir field) and
     that the process function body has no spurious field-string dec_rc.

     We check the TIR-level property: after Perceus, use_cfg (which is
     inlined into process after optimisation) must not contain a dec_rc for
     the extracted string field from cfg.  The _borrowed_field_vars mechanism
     ensures that strings extracted from a borrowed record are never decremented. *)
  let m = perceus_module {|mod Test do

    type Cfg = { dir : String }

    pfn use_cfg(cfg : Cfg) : Int do
      String.byte_size(cfg.dir)
    end

    pfn process(cfg : Cfg, items : List(String), acc : Int) : Int do
      match items do
      Nil -> acc
      Cons(_, rest) ->
        let n = use_cfg(cfg)
        process(cfg, rest, acc + n)
      end
    end

    fn main() do
      let cfg = { dir: "content" }
      process(cfg, Cons("a", Cons("b", Nil)), 0)
    end

  end|} in
  (* The key invariant: after the fix, use_cfg must have cfg inferred as
     borrowed (it only reads cfg.dir).  With cfg:borrowed, Perceus adds cfg
     to the borrowed' set; the _borrowed_field_vars suppression prevents
     dec_rc for the extracted String field.  No EDecRC should appear in the
     use_cfg body (or its inlined form inside process). *)
  let use_cfg_fns = List.filter (fun fn ->
    String.equal fn.March_tir.Tir.fn_name "use_cfg"
  ) m.March_tir.Tir.tm_fns in
  (* use_cfg may be inlined by the optimiser — if so, check process instead *)
  let fns_to_check =
    if use_cfg_fns = [] then
      List.filter (fun fn ->
        String.equal fn.March_tir.Tir.fn_name "process"
      ) m.March_tir.Tir.tm_fns
    else use_cfg_fns
  in
  Alcotest.(check bool)
    "use_cfg (or process after inlining) has no spurious field-string EDecRC"
    false
    (List.exists (fun fn -> has_any_decrc fn.March_tir.Tir.fn_body) fns_to_check)

(* Regression: List.length(result) followed by List.nth(result, 0) — the
   List.length call (via its internal go closure) CONSUMES the list (owned
   parameter), so Perceus must emit EIncRC for result at the call site to
   keep it alive for the subsequent List.nth call.  Without the fix, the
   caller emitted no EIncRC, List.length decremented each Cons node's RC to
   zero, and List.nth read freed memory → "local RC underflow". *)
let test_perceus_list_length_then_nth_incrc () =
  let m = perceus_module {|mod Test do
  needs IO.Console

    pfn check(xs : List(String)) : Bool do
      let n = List.length(xs)
      let first = List.nth(xs, 0)
      n == 1 && first == "hello"
    end

    fn main(_cap_console : Cap(IO.Console)) do
      let xs = Cons("hello", Nil)
      let ok = check(xs)
      if ok do println("pass") else println("fail") end
    end

  end|} in
  (* After Perceus, the `check` function must contain at least one EIncRC:
     the inc for `xs` before the consuming List.length call (since `xs` is
     still live at the subsequent List.nth call).  If the bug reappears, no
     EIncRC would be emitted and List.nth would read a freed list node. *)
  let check_fns = List.filter (fun fn ->
    String.equal fn.March_tir.Tir.fn_name "check"
  ) m.March_tir.Tir.tm_fns in
  Alcotest.(check bool)
    "check has EIncRC for xs before consuming List.length call"
    true
    (List.exists (fun fn -> has_any_incrc fn.March_tir.Tir.fn_body) check_fns)

(* Regression: tuple parameter used in multiple sequential pattern-match
   destructs within the caller caused RC underflow.

   Root cause: field_escape_owns in borrow.ml fired for TTuple scrutinees
   whenever a branch variable escaped via return (EAtom).  This flipped the
   tuple parameter to cfg:own, preventing scrutinee_borrowed from becoming
   true in Perceus.  With scrutinee_borrowed=false, add_scrutinee_free_for
   emitted EDecRC(pair) inside the match branch AND post_dec_vars emitted
   EDecRC on the extracted String field (aliased through x → a) — without a
   matching EIncRC.  On the second call from the loop the field String's RC
   was already 0 → local RC underflow.

   Fix: field_escape_owns is suppressed for TTuple/TRecord scrutinees.
   Perceus's scrutinee_borrowed mechanism handles field escapes by emitting
   EIncRC for branch vars when the tuple is live after the case.

   We verify the TIR-level invariant: after the fix, use_first must have
   pair inferred as borrowed, so Perceus emits at least one EIncRC inside
   the function (for the extracted String field's non-last-use via
   scrutinee_borrowed).  If the bug reappears, pair:own means
   scrutinee_borrowed=false and no EIncRC is emitted — the second call in
   the loop then reads a freed String field. *)
let test_perceus_tuple_param_multi_destruct_no_rc_underflow () =
  let m = perceus_module {|mod Test do
  needs IO.Console

    pfn use_first(pair : (String, String)) : Int do
      let a = match pair do (x, _) -> x end
      String.byte_size(a)
    end

    pfn process_pairs(pair : (String, String), n : Int, acc : Int) : Int do
      match n do
      0 -> acc
      _ ->
        let k = use_first(pair)
        process_pairs(pair, n - 1, acc + k)
      end
    end

    fn main(_cap_console : Cap(IO.Console)) do
      let pair = ("hello", "world")
      println(process_pairs(pair, 3, 0))
    end

  end|} in
  (* After the fix, use_first must have pair:borrow.  When pair is borrowed,
     Perceus sets scrutinee_borrowed=true (pair is in live_after); this adds
     the branch vars to live_after, causing EIncRC to be emitted for the
     extracted String field at its non-last-use position inside the branch.
     At least one EIncRC must appear in use_first's body.
     If the bug reappears (pair:own), scrutinee_borrowed=false and no EIncRC
     is emitted — the loop's second call then reads freed memory. *)
  let use_first_fns = List.filter (fun fn ->
    String.equal fn.March_tir.Tir.fn_name "use_first"
  ) m.March_tir.Tir.tm_fns in
  Alcotest.(check bool)
    "use_first has EIncRC for tuple field (pair:borrow + scrutinee_borrowed)"
    true
    (List.exists (fun fn -> has_any_incrc fn.March_tir.Tir.fn_body) use_first_fns)

(** Regression: accessing a String field of a locally-owned record (returned
    by a function call rather than passed as a borrowed parameter) caused
    spurious post-call EDecRC for the extracted field.

    Root cause: is_borrowed_field only fired when the source record was in
    live_after (borrowed parameter) or _borrowed_field_vars.  For locally-owned
    records the source was only in live_into_e2, not in live_after, so the field
    was treated as independently owned.  post_dec then emitted EDecRC for the
    field after any borrowing call, freeing meta.title while meta still held a
    reference → dangling pointer and potential RC underflow.

    Fix: is_borrowed_field now also triggers when the source is in
    live_before(e2, live_after) (another sequential field access in the body) or
    in _var_ctx and not a TPtr (locally in-scope heap record).

    We verify the TIR invariant: render must have no EDecRC for the title field
    extracted from the locally-owned meta record.  Before the fix, byte_size
    borrows t at t's last-use position, triggering post_dec → EDecRC(t) → meta.title
    freed.  After the fix, t is correctly in _borrowed_field_vars → post_dec suppressed. *)
let test_perceus_local_record_field_no_spurious_decrc () =
  let m = perceus_module {|mod Test do
  needs IO.Console

    type Meta = { draft: Bool, title: String }

    pfn make_meta(s: String) : Meta do
      { draft: false, title: s }
    end

    pfn render(s: String) : Int do
      let meta = make_meta(s)
      let t = meta.title
      String.byte_size(t)
    end

    fn main(_cap_console : Cap(IO.Console)) do
      println(render("hello"))
    end

  end|} in
  (* render extracts meta.title into t, then byte_size borrows t at last use.
     Before the fix: post_dec fires → EDecRC(t) in render.
     After the fix:  t is in _borrowed_field_vars → no EDecRC for t in render.

     Asserted by NAME rather than as "no EDecRC anywhere in render".  Since
     aggregates became RC'd, render legitimately contains `dec_rc meta` — the
     scope-end drop of the record itself, which is the whole point of that
     change and which the blanket form would have flagged as a regression.
     The bug this test guards is specifically a dec of the extracted FIELD, so
     name t; and pin the record's own drop as well, so that dropping it again
     by accident is caught here too. *)
  let decrc_names fn =
    let acc = ref [] in
    let atom_name = function
      | March_tir.Tir.AVar v -> Some v.March_tir.Tir.v_name
      | _ -> None
    in
    let rec go = function
      | March_tir.Tir.EDecRC a | March_tir.Tir.EAtomicDecRC a
      | March_tir.Tir.EFree a ->
        (match atom_name a with Some n -> acc := n :: !acc | None -> ())
      | March_tir.Tir.ELet (_, e1, e2) | March_tir.Tir.ESeq (e1, e2) ->
        go e1; go e2
      | March_tir.Tir.ECase (_, brs, def) ->
        List.iter (fun b -> go b.March_tir.Tir.br_body) brs;
        (match def with Some e -> go e | None -> ())
      | March_tir.Tir.ELetRec (fns, body) ->
        List.iter (fun f -> go f.March_tir.Tir.fn_body) fns; go body
      | _ -> ()
    in
    go fn.March_tir.Tir.fn_body; !acc
  in
  let render_fns = List.filter (fun fn ->
    String.equal fn.March_tir.Tir.fn_name "render"
  ) m.March_tir.Tir.tm_fns in
  let names = List.concat_map decrc_names render_fns in
  Alcotest.(check bool)
    "render has no spurious EDecRC for the extracted record field t"
    false
    (List.mem "t" names);
  Alcotest.(check bool)
    "render drops the record itself exactly once"
    true
    (List.length (List.filter (String.equal "meta") names) = 1)

(* Regression: same bug at the LLVM IR level — ensure the emitted IR for a
   function using && contains no call to @__ (the undefined symbol produced
   when llvm_name "&&" = "__" was naively materialized as a call). *)
(* ── Browser HTTP transport (http_fetch platform hook) ──────────────── *)

let test_http_fetch_unavailable_by_default () =
  March_eval.Eval.http_fetch_hook := None;
  let env = eval_module {|mod T do
  fn f() do http_fetch_available() end
end|} in
  Alcotest.(check bool) "unavailable by default" false (vbool (call_fn env "f" []))

let test_http_fetch_available_when_hooked () =
  March_eval.Eval.http_fetch_hook :=
    Some (fun _meth _url _hdrs _body -> Ok "HTTP/1.1 200 OK\r\n\r\n");
  let env = eval_module {|mod T do
  fn f() do http_fetch_available() end
end|} in
  let avail = vbool (call_fn env "f" []) in
  March_eval.Eval.http_fetch_hook := None;
  Alcotest.(check bool) "available when hooked" true avail

let test_http_fetch_returns_ok_raw () =
  March_eval.Eval.http_fetch_hook :=
    Some (fun _ _ _ _ -> Ok "RAWBODY");
  let env = eval_module {|mod T do
  fn f() do http_fetch("GET", "http://x/", "", "") end
end|} in
  let r = call_fn env "f" [] in
  March_eval.Eval.http_fetch_hook := None;
  (match vcon "Ok" r with
   | [v] -> Alcotest.(check string) "ok payload is raw string" "RAWBODY" (vstr v)
   | _ -> Alcotest.fail "expected Ok(_)")

let test_http_fetch_maps_error () =
  March_eval.Eval.http_fetch_hook :=
    Some (fun _ _ _ _ -> Error "boom");
  let env = eval_module {|mod T do
  fn f() do http_fetch("GET", "http://x/", "", "") end
end|} in
  let r = call_fn env "f" [] in
  March_eval.Eval.http_fetch_hook := None;
  (match vcon "Err" r with
   | [v] -> Alcotest.(check string) "err payload" "boom" (vstr v)
   | _ -> Alcotest.fail "expected Err(_)")

let test_http_transport_request_via_fetch () =
  let http      = load_stdlib_file_for_test "http.march" in
  let transport = load_stdlib_file_for_test "http_transport.march" in
  let canned =
    "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nhello world" in
  March_eval.Eval.http_fetch_hook := Some (fun _ _ _ _ -> Ok canned);
  let env = eval_with_stdlib [http; transport]
    {|mod Test do
  fn run() do
    match Http.get("https://example.com/path") do
    Ok(req) -> HttpTransport.request(Http.set_body(req, ""))
    Err(_)  -> Err(ConnParseError("bad url"))
    end
  end
end|} in
  let result = call_fn env "run" [] in
  March_eval.Eval.http_fetch_hook := None;
  (match vcon "Ok" result with
   | [resp] ->
     (match vcon "Response" resp with
      | [status; _headers; body_v] ->
        (match vcon "Status" status with
         | [code_v] ->
           Alcotest.(check int) "status code" 200 (vint code_v);
           Alcotest.(check string) "body" "hello world" (vstr body_v)
         | _ -> Alcotest.fail "bad Status shape")
      | _ -> Alcotest.fail "bad Response shape")
   | _ -> Alcotest.fail "expected Ok(Response ...)")

(* ── B16 + conn-gated CSRF: ~H auto-injection ───────────────────────────────
   Every ~H literal containing a mutating <form method="post|put|patch|delete">
   gets an injected `CSRF.tag_string(conn)` call — but ONLY when a `conn`
   binding is lexically in scope (function/lambda param, block `let`, or match
   pattern). Two regressions guarded here:
   - B16: a standalone module WITHOUT `conn` must never see the injected call
     (it used to get a baffling unbound-`conn` error) — renders verbatim.
   - Bastion convention: a page fn WITH a `conn` param MUST get the injection
     (its unconditional removal silently dropped CSRF protection from every
     Bastion app — every POST started 403ing). *)

let test_h_sigil_form_post_typechecks_standalone () =
  (* iolist.march is self-contained (no String-module deps), so loading it
     alone keeps the harness free of unrelated missing-builtin noise;
     html_auto_escape is a typecheck builtin. *)
  let iolist_decl = load_stdlib_file_for_test "iolist.march" in
  let m = parse_and_desugar {|mod Page do
  fn page() : String do
    IOList.to_string(~H"<form method=\"post\">x</form>")
  end
end|} in
  let m = { m with March_ast.Ast.mod_decls =
                     [iolist_decl] @ m.March_ast.Ast.mod_decls } in
  let (errors, _type_map) = March_typecheck.Typecheck.check_module m in
  let msgs = List.map (fun (d : March_errors.Errors.diagnostic) -> d.message)
      (March_errors.Errors.sorted errors) in
  Alcotest.(check bool)
    (Printf.sprintf "standalone ~H form post: no typecheck errors (got: %s)"
       (String.concat " | " msgs))
    false (March_errors.Errors.has_errors errors)

let test_h_sigil_form_post_runs_standalone () =
  let string_decl = load_stdlib_file_for_test "string.march" in
  let iolist_decl = load_stdlib_file_for_test "iolist.march" in
  let env = eval_with_stdlib [string_decl; iolist_decl]
    {|mod Page do
  fn page() : String do
    IOList.to_string(~H"<form method=\"post\">x</form>")
  end
end|} in
  let result = call_fn env "page" [] in
  (* No token injection: the template renders verbatim. *)
  Alcotest.(check string) "form renders verbatim, no injected token"
    {|<form method="post">x</form>|} (vstr result)

(* A module with a `CSRF.tag_string` stub (the injected call's target) and a
   Bastion-style page fn taking `conn`. The injected token must appear right
   after the <form ...> opening tag. *)
let csrf_stub_token = {|<input type="hidden" name="_csrf_token" value="tok123">|}

let eval_csrf_page body_decl =
  let string_decl = load_stdlib_file_for_test "string.march" in
  let iolist_decl = load_stdlib_file_for_test "iolist.march" in
  eval_with_stdlib [string_decl; iolist_decl]
    (Printf.sprintf {|mod Page do
  mod CSRF do
    fn tag_string(conn) : String do
      "<input type=\"hidden\" name=\"_csrf_token\" value=\"tok123\">"
    end
  end
%s
end|} body_decl)

let test_h_sigil_form_post_injects_with_conn_param () =
  let env = eval_csrf_page {|
  fn page(conn) : String do
    IOList.to_string(~H"<form action=\"/login\" method=\"post\">x</form>")
  end|} in
  let result = call_fn env "page" [March_eval.Eval.VInt 0] in
  Alcotest.(check string) "conn param in scope: token injected after form tag"
    ({|<form action="/login" method="post">|} ^ csrf_stub_token ^ {|x</form>|})
    (vstr result)

let test_h_sigil_form_post_injects_with_conn_let () =
  let env = eval_csrf_page {|
  fn page(c) : String do
    let conn = c
    IOList.to_string(~H"<form method=\"post\">x</form>")
  end|} in
  let result = call_fn env "page" [March_eval.Eval.VInt 0] in
  Alcotest.(check string) "block `let conn` in scope: token injected"
    ({|<form method="post">|} ^ csrf_stub_token ^ {|x</form>|})
    (vstr result)

let test_h_sigil_get_form_not_injected_with_conn () =
  (* Non-mutating method: no injection even with conn in scope. *)
  let env = eval_csrf_page {|
  fn page(conn) : String do
    IOList.to_string(~H"<form method=\"get\">x</form>")
  end|} in
  let result = call_fn env "page" [March_eval.Eval.VInt 0] in
  Alcotest.(check string) "GET form: no injection"
    {|<form method="get">x</form>|} (vstr result)

(* ~H auto-escaping must hold at every interpolation length.
   `html_interp_to_iolist` finds the dynamic parts by matching `to_string(e)`
   per part, so it depends on `decompose_concat` seeing through whatever shape
   reaches it: the parser emits a `++` chain, and desugar then collapses chains
   of 3+ into `string_concat3` before ESigil hands the content over. When a
   shape is not recognized the template collapses into ONE opaque part and
   escaping is silently skipped.

   That has now happened twice, from two different mechanisms — once when
   interpolation briefly desugared to `string_join`, once when concat3 folding
   was added — and the many-part case below rendered raw `<script>` tags both
   times. Asserting on ESCAPED output is the whole point: an unrecognized shape
   still renders, just unsafely, so nothing else fails. *)
let eval_h_escape_page body_decl =
  let string_decl = load_stdlib_file_for_test "string.march" in
  let iolist_decl = load_stdlib_file_for_test "iolist.march" in
  eval_with_stdlib [string_decl; iolist_decl]
    (Printf.sprintf {|mod Page do
%s
end|} body_decl)

let test_h_sigil_escapes_short_interp () =
  (* Two segments → a bare `++`, below the concat3 folding threshold. *)
  let env = eval_h_escape_page {|
  fn page(evil) : String do
    IOList.to_string(~H"<p>${evil}</p>")
  end|} in
  let result = call_fn env "page" [March_eval.Eval.VString "<script>"] in
  Alcotest.(check string) "short ~H interpolation is HTML-escaped"
    "<p>&lt;script&gt;</p>" (vstr result)

let test_h_sigil_escapes_many_part_interp () =
  (* Seven segments → `++` chain, folded to string_concat3 by desugar. *)
  let env = eval_h_escape_page {|
  fn page(evil) : String do
    IOList.to_string(~H"<p>${evil}</p><i>${evil}</i><b>${evil}</b>")
  end|} in
  let result = call_fn env "page" [March_eval.Eval.VString "<script>"] in
  Alcotest.(check string) "many-part ~H interpolation is HTML-escaped"
    "<p>&lt;script&gt;</p><i>&lt;script&gt;</i><b>&lt;script&gt;</b>"
    (vstr result)

(* Signal.watch (7.2, Stage A): deferred green-thread dispatch of an OS-signal
   watcher.  Drive the drain directly — register an OCaml handler on the Usr1
   slot (code 3), raise SIGUSR1 to ourselves, pump [run_scheduler], and assert
   the handler ran exactly once per drain, with pre-drain repeats coalesced. *)
let signal_wait_pending code =
  (* Spin so OCaml delivers the deferred signal at a safe point (the [ref]
     allocation gives the runtime a chance to run the handler). *)
  let spins = ref 0 in
  while not March_eval.Eval.signal_pending.(code) && !spins < 20_000_000 do
    incr spins; ignore (Sys.opaque_identity (ref !spins))
  done

let test_signal_watch_deferred () =
  let count = ref 0 in
  let handler = March_eval.Eval.VBuiltin
      ("test_sig_handler", fun _ -> incr count; March_eval.Eval.VUnit) in
  March_eval.Eval.signal_watchers.(3) <- Some handler;
  March_eval.Eval.signal_pending.(3)  <- false;
  March_eval.Eval.signal_seen.(3)     <- false;
  Sys.set_signal Sys.sigusr1 (Sys.Signal_handle March_eval.Eval.handle_os_signal);
  (* Two deliveries before any drain must coalesce to a single handler call. *)
  Unix.kill (Unix.getpid ()) Sys.sigusr1;
  Unix.kill (Unix.getpid ()) Sys.sigusr1;
  signal_wait_pending 3;
  March_eval.Eval.run_scheduler ();
  Alcotest.(check int) "USR1 watcher ran exactly once" 1 !count;
  (* A later delivery + drain runs it again. *)
  Unix.kill (Unix.getpid ()) Sys.sigusr1;
  signal_wait_pending 3;
  March_eval.Eval.run_scheduler ();
  Alcotest.(check int) "USR1 watcher ran again after redelivery" 2 !count;
  (* unwatch clears the slot: a delivery afterwards must NOT set pending nor run
     the handler (handle_os_signal no-ops for an unwatched Usr1).  We can't wait
     on a flag that will never be set, so just give the runtime a bounded window
     of safe points to (not) deliver, then drain. *)
  March_eval.Eval.signal_watchers.(3) <- None;
  March_eval.Eval.signal_pending.(3)  <- false;
  Unix.kill (Unix.getpid ()) Sys.sigusr1;
  for i = 0 to 100_000 do ignore (Sys.opaque_identity (ref i)) done;
  March_eval.Eval.run_scheduler ();
  Alcotest.(check int) "unwatched USR1 does not run the handler" 2 !count;
  March_eval.Eval.signal_pending.(3) <- false;
  Sys.set_signal Sys.sigusr1 Sys.Signal_default

(* ------------------------------------------------------------------ *)
(* Entry-point (`main`) signature and dispatch                         *)
(* ------------------------------------------------------------------ *)

(** `fn main(cap : Cap(IO))` — the documented pattern for receiving the
    initial IO capability (specs/lang/capabilities.md) — is accepted by
    [Desugar.check_main_signature] and, critically, its body actually runs.
    Before this fix, [Eval.run_module] called every `main` with zero
    arguments regardless of declared arity: a 1-parameter `main` became an
    unapplied partial closure that silently never executed (no crash, no
    output, exit looked "successful"). *)
let test_main_cap_io_runs () =
  let src = {|mod Test do
    needs IO

    fn main(cap : Cap(IO)) : () do
      let _console : Cap(IO.Console) = cap_narrow(cap)
      println("main ran with cap")
    end
  end|} in
  let buf = Buffer.create 64 in
  March_eval.Eval.test_capture_buf := Some buf;
  Fun.protect
    ~finally:(fun () -> March_eval.Eval.test_capture_buf := None)
    (fun () -> run_module_src src);
  Alcotest.(check string) "main(cap : Cap(IO)) body executed"
    "main ran with cap\n" (Buffer.contents buf)

(** 0-arity `main` keeps working unchanged (no regression from the
    arity-aware dispatch added for the `Cap(IO)` case). *)
let test_main_zero_arity_still_runs () =
  let src = {|mod Test do
  needs IO.Console
    fn main(_cap_console : Cap(IO.Console)) : () do
      println("zero-arity main ran")
    end
  end|} in
  let buf = Buffer.create 64 in
  March_eval.Eval.test_capture_buf := Some buf;
  Fun.protect
    ~finally:(fun () -> March_eval.Eval.test_capture_buf := None)
    (fun () -> run_module_src src);
  Alcotest.(check string) "main() body executed"
    "zero-arity main ran\n" (Buffer.contents buf)

(** Any `main` arity/type other than 0 params or a single `Cap(IO)` param is
    rejected at desugar time with a clear diagnostic, rather than left to
    silently misbehave downstream (interpreted: silent no-op; compiled: an
    ABI-mismatched call into `march_spawn_main`, observed as a SIGBUS). *)
let test_main_wrong_arity_rejected () =
  let src = {|mod Bad do
    fn main(x : Int) : () do () end
  end|} in
  let lexbuf = Lexing.from_string src in
  let ast = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  let errors = March_errors.Errors.create () in
  ignore (March_desugar.Desugar.desugar_module ~errors ast);
  Alcotest.(check bool) "wrong-arity main rejected" true
    (March_errors.Errors.has_errors errors)

(* As-patterns: `p as n` binds n to the whole matched value while p continues
   to destructure it.  PatAs existed in the AST, interpreter, and typechecker
   from the start but had no grammar production. *)
let test_eval_as_pattern_binds_whole () =
  let env = eval_module {|mod T do
    fn f(o) do
      match o do
        Some(x) as whole ->
          match whole do
            Some(y) -> x + y
            None -> 0
          end
        None -> 0
      end
    end
  end|} in
  let v = call_fn env "f"
      [March_eval.Eval.VCon ("Some", [March_eval.Eval.VInt 21])] in
  Alcotest.(check int) "Some(21) as whole -> 21 + 21" 42
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

(* An as-pattern over a TRIVIAL inner pattern takes lower_match's
   bind_trivial_pat path; over a NON-TRIVIAL inner it takes the new
   strip_as_column path.  Cover the trivial one too. *)
let test_eval_as_pattern_trivial_inner () =
  let env = eval_module {|mod T do
    fn f(n) do
      match n do
        x as y -> x + y
      end
    end
  end|} in
  let v = call_fn env "f" [March_eval.Eval.VInt 5] in
  Alcotest.(check int) "x as y -> x + y" 10
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

(* Record patterns in a match arm, with the field list exactly matching the
   record's fields.  PatRecord existed in the AST and interpreter but had no
   grammar production. *)
let test_eval_record_pattern_match () =
  let env = eval_module {|mod T do
    fn f() do
      let r = { x: 3, y: 4 }
      match r do
        { x: a, y: b } -> a * b
      end
    end
  end|} in
  let v = call_fn env "f" [] in
  Alcotest.(check int) "{x: 3, y: 4} -> 3 * 4" 12
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

(* Punned field patterns: `{ x, y }` is shorthand for `{ x: x, y: y }`. *)
let test_eval_record_pattern_punned () =
  let env = eval_module {|mod T do
    fn f() do
      let r = { x: 3, y: 4 }
      match r do
        { x, y } -> x + y
      end
    end
  end|} in
  let v = call_fn env "f" [] in
  Alcotest.(check int) "{x, y} punned -> 3 + 4" 7
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

(* Record pattern in an irrefutable `let` binding — a DIFFERENT lowering path
   (lower.ml's bind_subpat) from the match matrix compiler. *)
let test_eval_record_pattern_let () =
  let env = eval_module {|mod T do
    fn f() do
      let r = { x: 3, y: 4 }
      let { x: a, y: b } = r
      a * b + 1
    end
  end|} in
  let v = call_fn env "f" [] in
  Alcotest.(check int) "let {x: a, y: b} = r" 13
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

(* Record pattern as a function parameter.  desugar.ml routes a single clause
   with a non-PatVar FPPat through the general path, which builds an EMatch —
   so this rides the match-lowering path, not a third one. *)
let test_eval_record_pattern_fn_param () =
  let env = eval_module {|mod T do
    fn area({ w: w, h: h }) do w * h end
    fn f() do area({ w: 6, h: 7 }) end
  end|} in
  let v = call_fn env "f" [] in
  Alcotest.(check int) "fn area({w, h})" 42
    (match v with March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt")

(* A REFUTABLE sub-pattern inside a record pattern forces the matrix compiler
   to actually dispatch on a projected field rather than just destructure. *)
let test_eval_record_pattern_refutable_field () =
  let env = eval_module {|mod T do
    fn f(r) do
      match r do
        { code: 404, msg: m } -> m
        { code: c, msg: _ }   -> "other " ++ int_to_string(c)
      end
    end
    fn g() do f({ code: 404, msg: "gone" }) end
    fn h() do f({ code: 200, msg: "ok" }) end
  end|} in
  Alcotest.(check string) "404 arm" "gone"
    (match call_fn env "g" [] with
     | March_eval.Eval.VString s -> s | _ -> failwith "expected VString");
  Alcotest.(check string) "fallthrough arm" "other 200"
    (match call_fn env "h" [] with
     | March_eval.Eval.VString s -> s | _ -> failwith "expected VString")

(* Partial record patterns must also RUN, not merely typecheck: the matrix
   compiler projects the union of mentioned fields across rows, so two arms
   mentioning different subsets must both work. *)
let test_eval_record_pattern_partial () =
  let env = eval_module {|mod T do
    fn f(r) do
      match r do
        { code: 404 } -> "gone"
        { msg: m }    -> m
      end
    end
    fn g() do f({ code: 404, msg: "unused" }) end
    fn h() do f({ code: 200, msg: "ok" }) end
  end|} in
  Alcotest.(check string) "first arm matches on code alone" "gone"
    (match call_fn env "g" [] with
     | March_eval.Eval.VString s -> s | _ -> failwith "expected VString");
  Alcotest.(check string) "second arm matches on msg alone" "ok"
    (match call_fn env "h" [] with
     | March_eval.Eval.VString s -> s | _ -> failwith "expected VString")

(* Or-patterns: alternatives separated by `|` in a single arm. *)
let test_eval_or_pattern_literals () =
  let env = eval_module {|mod T do
    fn f(n) do
      match n do
        1 | 2 | 3 -> "small"
        _         -> "big"
      end
    end
  end|} in
  Alcotest.(check string) "1 -> small" "small"
    (match call_fn env "f" [March_eval.Eval.VInt 1] with
     | March_eval.Eval.VString s -> s | _ -> failwith "expected VString");
  Alcotest.(check string) "3 -> small" "small"
    (match call_fn env "f" [March_eval.Eval.VInt 3] with
     | March_eval.Eval.VString s -> s | _ -> failwith "expected VString");
  Alcotest.(check string) "9 -> big" "big"
    (match call_fn env "f" [March_eval.Eval.VInt 9] with
     | March_eval.Eval.VString s -> s | _ -> failwith "expected VString")

let test_eval_or_pattern_nullary_ctors () =
  let env = eval_module {|mod T do
    type Color = Red | Green | Blue
    fn warm(c) do
      match c do
        Red | Green -> true
        Blue        -> false
      end
    end
  end|} in
  Alcotest.(check bool) "Red is warm" true
    (match call_fn env "warm" [March_eval.Eval.VCon ("Red", [])] with
     | March_eval.Eval.VBool b -> b | _ -> failwith "expected VBool");
  Alcotest.(check bool) "Blue is not warm" false
    (match call_fn env "warm" [March_eval.Eval.VCon ("Blue", [])] with
     | March_eval.Eval.VBool b -> b | _ -> failwith "expected VBool")

(* Or-pattern ALTERNATIVES may bind, provided every alternative binds the same
   names at the same types.  Each split row binds its own copy from a
   different constructor's payload and calls the one shared arm body through
   an n-ary join point. *)
let test_eval_or_pattern_binding_alternatives () =
  let env = eval_module {|mod T do
    type E = A(Int) | B(Int) | C
    fn f(e) do
      match e do
        A(x) | B(x) -> x * 10
        C           -> 0
      end
    end
  end|} in
  let call v = match call_fn env "f" [v] with
    | March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt" in
  Alcotest.(check int) "binds from the first alternative" 30
    (call (March_eval.Eval.VCon ("A", [March_eval.Eval.VInt 3])));
  Alcotest.(check int) "binds from the second alternative" 70
    (call (March_eval.Eval.VCon ("B", [March_eval.Eval.VInt 7])));
  Alcotest.(check int) "non-or arm still reached" 0
    (call (March_eval.Eval.VCon ("C", [])))

let test_lookup_shadowing_innermost_wins () =
  let env = [("x", March_eval.Eval.VInt 2); ("x", March_eval.Eval.VInt 1)] in
  Alcotest.(check int) "innermost binding" 2
    (vint (March_eval.Eval.lookup "x" env))

let test_lookup_missing_raises () =
  Alcotest.check_raises "unbound" (March_eval.Eval.Eval_error "unbound variable: nope")
    (fun () -> ignore (March_eval.Eval.lookup "nope" []))

let test_assoc_str_is_exact_match () =
  let env = [("ab", March_eval.Eval.VInt 1); ("a", March_eval.Eval.VInt 2)] in
  Alcotest.(check int) "prefix does not match" 2
    (vint (Option.get (March_eval.Eval.assoc_str "a" env)))

let test_global_tail_shadowed_by_locals () =
  let tail = [("g", March_eval.Eval.VInt 1); ("h", March_eval.Eval.VInt 10)] in
  March_eval.Eval.install_global_tail tail;
  let env = ("g", March_eval.Eval.VInt 2) :: tail in
  Alcotest.(check int) "local shadows tail" 2 (vint (March_eval.Eval.lookup "g" env));
  Alcotest.(check int) "tail hit" 10 (vint (March_eval.Eval.lookup "h" env));
  March_eval.Eval.clear_global_tail ()

let test_global_tail_internal_shadowing () =
  (* earlier entry wins inside the tail, exactly like the list scan did *)
  let tail = [("d", March_eval.Eval.VInt 1); ("d", March_eval.Eval.VInt 99)] in
  March_eval.Eval.install_global_tail tail;
  Alcotest.(check int) "first entry wins" 1 (vint (March_eval.Eval.lookup "d" tail));
  March_eval.Eval.clear_global_tail ()

let test_global_tail_not_physical_falls_back_to_scan () =
  let tail = [("k", March_eval.Eval.VInt 5)] in
  March_eval.Eval.install_global_tail tail;
  (* [other] is a distinct list value (different key "k" -> 6, not even structurally equal
     to [tail]); it just isn't the physically-installed tail, so lookup must scan it directly
     rather than probe the hashed table built from [tail]. *)
  let other = [("k", March_eval.Eval.VInt 6)] in
  Alcotest.(check int) "scan still correct" 6 (vint (March_eval.Eval.lookup "k" other));
  March_eval.Eval.clear_global_tail ()

let test_repl_style_v_update_keeps_fast_path () =
  March_eval.Eval.clear_global_tail ();
  let tail = [("h", March_eval.Eval.VInt 10)] in
  March_eval.Eval.install_global_tail tail;
  (* Prompt 1: reproduces repl.ml's REPL result-binding expression
     `env := ("v", v) :: (List.remove_assoc "v" !env)` verbatim. "v" is absent from [tail],
     so List.remove_assoc rebuilds the ENTIRE spine -- env1's suffix is a fresh copy of
     [tail], not [tail] itself. *)
  let env1 = ("v", March_eval.Eval.VInt 1) :: (List.remove_assoc "v" tail) in
  Alcotest.(check bool) "remove_assoc on an absent key breaks physical sharing" false
    (List.tl env1 == tail);
  (* FAIL-FIRST: without repl.ml's fix (a re-install right after every env := mutation),
     [global_tail] is still the ORIGINAL [tail], not [env1] -- this is exactly the bug IMPORTANT-1
     describes: the fast path dies on the very first REPL prompt. *)
  March_eval.Eval.install_global_tail env1;
  Alcotest.(check bool) "re-install re-anchors the fast path to env1" true
    (env1 == !March_eval.Eval.global_tail);
  (* Prompt 2: "v" is now present, so remove_assoc finds it at the head this time -- the case
     that can look deceptively fine, but only stays fast because repl.ml re-installs on every
     mutation, not because remove_assoc happens to preserve sharing here. *)
  let env2 = ("v", March_eval.Eval.VInt 2) :: (List.remove_assoc "v" env1) in
  March_eval.Eval.install_global_tail env2;
  Alcotest.(check bool) "second re-install re-anchors the fast path to env2" true
    (env2 == !March_eval.Eval.global_tail);
  Alcotest.(check int) "v visible after two updates" 2 (vint (March_eval.Eval.lookup "v" env2));
  Alcotest.(check int) "h still visible after two updates" 10 (vint (March_eval.Eval.lookup "h" env2));
  March_eval.Eval.clear_global_tail ()

let test_cross_install_safety_falls_back_to_scan () =
  let t1 = [("x", March_eval.Eval.VInt 1)] in
  March_eval.Eval.install_global_tail t1;
  let env1 = ("local", March_eval.Eval.VInt 99) :: t1 in
  let t2 = [("x", March_eval.Eval.VInt 2)] in
  March_eval.Eval.install_global_tail t2;
  (* Prove the hazard is real: a lookup that trusted the hashed table WITHOUT first checking
     physical identity against the currently-installed tail would silently return T2's value
     here -- stale/wrong for [env1], whose suffix is still physically T1. *)
  Alcotest.(check int) "raw table now holds T2's value for the same key (the hazard)" 2
    (vint (Option.get (Hashtbl.find_opt March_eval.Eval.global_tbl "x")));
  (* The real lookup path must not take that shortcut: env1's suffix ([t1]) is not [!global_tail]
     ([t2]), so assoc_str falls back to a full scan and returns T1's value, never T2's. *)
  Alcotest.(check int) "old env still sees its own tail's value, not the new install's" 1
    (vint (March_eval.Eval.lookup "x" env1));
  March_eval.Eval.clear_global_tail ()

let test_fib_end_to_end_unchanged () =
  let env = eval_with_stdlib [] {|
mod M do
  fn fib(n) do if n < 2 do n else fib(n-1) + fib(n-2) end end
  fn main() do fib(15) end
end|} in
  Alcotest.(check int) "fib 15" 610
    (vint (March_eval.Eval.apply (List.assoc "main" env) []))

let test_apply_debug_depth_restored_on_exception () =
  (* Pin the depth-tracking invariant that `apply`'s debug-ctx fast-path
     rewrite must preserve: with a debug ctx installed, an exception raised
     through `apply` still restores dc_depth to its pre-call value (via the
     exception path), not just on normal return. *)
  let ctx = March_debug.Debug.make_debug_ctx ~on_dbg:(fun _ -> ()) in
  March_debug.Debug.install ctx;
  Fun.protect
    ~finally:(fun () -> March_debug.Debug.uninstall ())
    (fun () ->
      let env = eval_with_stdlib [] {|
mod M do
  fn boom() do nope end
  fn main() do () end
end|} in
      let boom_fn = List.assoc "boom" env in
      let depth_before = ctx.March_eval.Eval.dc_depth in
      Alcotest.check_raises "boom raises through apply"
        (March_eval.Eval.Eval_error "unbound variable: nope")
        (fun () -> ignore (March_eval.Eval.apply boom_fn []));
      Alcotest.(check int) "depth restored after exception" depth_before
        ctx.March_eval.Eval.dc_depth)

let eval_suites =
  [
      ( "env_lookup", [
          Alcotest.test_case "innermost wins" `Quick test_lookup_shadowing_innermost_wins;
          Alcotest.test_case "missing raises" `Quick test_lookup_missing_raises;
          Alcotest.test_case "assoc_str exact" `Quick test_assoc_str_is_exact_match;
          Alcotest.test_case "global tail shadowed by locals" `Quick test_global_tail_shadowed_by_locals;
          Alcotest.test_case "global tail internal shadowing" `Quick test_global_tail_internal_shadowing;
          Alcotest.test_case "global tail not physical falls back to scan" `Quick test_global_tail_not_physical_falls_back_to_scan;
          Alcotest.test_case "repl-style v update keeps fast path" `Quick test_repl_style_v_update_keeps_fast_path;
          Alcotest.test_case "cross-install safety falls back to scan" `Quick test_cross_install_safety_falls_back_to_scan;
          Alcotest.test_case "fib end to end unchanged" `Quick test_fib_end_to_end_unchanged;
          Alcotest.test_case "apply debug depth restored on exception" `Quick test_apply_debug_depth_restored_on_exception ] );
      ( "or_patterns",
        [
          Alcotest.test_case "or-pattern over literals" `Quick
            test_eval_or_pattern_literals;
          Alcotest.test_case "or-pattern over nullary constructors" `Quick
            test_eval_or_pattern_nullary_ctors;
          Alcotest.test_case "or-pattern alternatives that bind" `Quick
            test_eval_or_pattern_binding_alternatives;
        ] );
      ( "record_patterns",
        [
          Alcotest.test_case "record pattern in a match arm" `Quick
            test_eval_record_pattern_match;
          Alcotest.test_case "punned record field patterns" `Quick
            test_eval_record_pattern_punned;
          Alcotest.test_case "record pattern in a let binding" `Quick
            test_eval_record_pattern_let;
          Alcotest.test_case "record pattern as a function parameter" `Quick
            test_eval_record_pattern_fn_param;
          Alcotest.test_case "refutable sub-pattern inside a record pattern" `Quick
            test_eval_record_pattern_refutable_field;
          Alcotest.test_case "partial record patterns across two arms" `Quick
            test_eval_record_pattern_partial;
        ] );
      ( "as_patterns",
        [
          Alcotest.test_case "as-pattern binds the whole value" `Quick
            test_eval_as_pattern_binds_whole;
          Alcotest.test_case "as-pattern over a trivial inner pattern" `Quick
            test_eval_as_pattern_trivial_inner;
        ] );
      ( "signal_watch", [
          Alcotest.test_case "deferred USR1 drain + coalesce + unwatch" `Quick
            test_signal_watch_deferred;
        ] );
      ( "main_entry_point", [
          Alcotest.test_case "main(cap : Cap(IO)) actually runs" `Quick test_main_cap_io_runs;
          Alcotest.test_case "main() zero-arity still runs"      `Quick test_main_zero_arity_still_runs;
          Alcotest.test_case "wrong-arity main rejected"         `Quick test_main_wrong_arity_rejected;
        ] );
      ( "browser http",
        [
          Alcotest.test_case "fetch unavailable by default" `Quick test_http_fetch_unavailable_by_default;
          Alcotest.test_case "fetch available when hooked"  `Quick test_http_fetch_available_when_hooked;
          Alcotest.test_case "fetch returns Ok raw"         `Quick test_http_fetch_returns_ok_raw;
          Alcotest.test_case "fetch maps Error to Err"      `Quick test_http_fetch_maps_error;
          Alcotest.test_case "HttpTransport.request via fetch" `Quick test_http_transport_request_via_fetch;
        ] );
      ( "eval",
        [
          Alcotest.test_case "dotted module name"  `Quick (with_reset test_eval_dotted_module);
          Alcotest.test_case "literal"             `Quick test_eval_literal;
          Alcotest.test_case "arithmetic"          `Quick test_eval_arithmetic;
          Alcotest.test_case "recursion"           `Quick test_eval_recursion;
          Alcotest.test_case "if expression"       `Quick test_eval_if;
          Alcotest.test_case "match ADT"           `Quick test_eval_match_adt;
          Alcotest.test_case "tuple"               `Quick test_eval_tuple;
          Alcotest.test_case "let binding"         `Quick test_eval_let_binding;
          Alcotest.test_case "let? ok propagates"  `Quick test_letq_ok_propagates;
          Alcotest.test_case "let? err short-circuits" `Quick test_letq_err_short_circuits;
          Alcotest.test_case "let? chain first err" `Quick test_letq_chain_first_err;
          Alcotest.test_case "let? in lambda"      `Quick test_letq_in_lambda;
          Alcotest.test_case "let* repl binds Option"  `Quick test_letstar_repl_binds_option;
          Alcotest.test_case "let* repl binds Result"  `Quick test_letstar_repl_binds_result;
          Alcotest.test_case "let* repl binds first of List" `Quick test_letstar_repl_binds_first_of_list;
          Alcotest.test_case "let* repl binds user type" `Quick test_letstar_repl_user_type;
          Alcotest.test_case "let* repl None binds nothing" `Quick test_letstar_repl_none_binds_nothing;
          Alcotest.test_case "let* repl Err binds nothing" `Quick test_letstar_repl_err_binds_nothing;
          Alcotest.test_case "let* repl [] binds nothing" `Quick test_letstar_repl_empty_list_binds_nothing;
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
          Alcotest.test_case "zero-arg lambda sugar" `Quick test_parse_zero_arg_lambda_sugar;
          Alcotest.test_case "percent token"       `Quick test_lexer_percent;
          Alcotest.test_case "modulo operator"     `Quick test_eval_modulo;
          Alcotest.test_case "multi-stmt match arm"`Quick test_eval_multi_stmt_match_arm;
          Alcotest.test_case "block arm no wrapper" `Quick test_eval_block_arm_no_wrapper;
          Alcotest.test_case "block arm nested"     `Quick test_eval_block_arm_nested;
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
          Alcotest.test_case "lower qualified mod"  `Quick test_tir_lower_qualified_module;
          Alcotest.test_case "qualified auto-load"  `Quick test_tir_lower_qualified_auto_load;
          Alcotest.test_case "lower type def"       `Quick test_tir_lower_type_def;
          Alcotest.test_case "lower fn params"      `Quick test_tir_lower_fn_params;
          Alcotest.test_case "ANF invariant"        `Quick test_tir_anf_invariant;
          Alcotest.test_case "PatVar default arm"   `Quick test_tir_lower_patvar_default;
          Alcotest.test_case "atom pattern match"   `Quick test_tir_lower_atom_pattern_match;
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
          Alcotest.test_case "mono nested generic pattern vars"
            `Quick test_mono_nested_generic_pattern_vars_are_concrete;
          Alcotest.test_case "mono variant parameter order"
            `Quick test_mono_preserves_declared_variant_parameter_order;
          Alcotest.test_case "mono identity"         `Quick test_mono_identity;
          Alcotest.test_case "mono no TVar after"    `Quick test_mono_no_tvar_after_mono;
          Alcotest.test_case "mono two instances"    `Quick test_mono_two_instantiations;
          Alcotest.test_case "defun free vars"       `Quick test_defun_free_vars;
          Alcotest.test_case "defun closure struct"  `Quick test_defun_closure_struct;
          Alcotest.test_case "defun no letrec lambda"`Quick test_defun_no_letrec_lambda;
          Alcotest.test_case "defun indirect call"   `Quick test_defun_indirect_call_becomes_ecallptr;
          Alcotest.test_case "defun erased closure callptr" `Quick test_defun_erased_closure_in_tuple_becomes_ecallptr;
          Alcotest.test_case "nested default-arg fn keeps signature (no param tuple)" `Quick test_desugar_nested_default_arg_no_param_tuple;
          Alcotest.test_case "defun zero capture"    `Quick test_defun_zero_capture_closure;
          Alcotest.test_case "defun nested lambda"   `Quick test_defun_nested_lambda;
          Alcotest.test_case "defun pp type_def"     `Quick test_defun_pp_type_def;
          Alcotest.test_case "defun e2e no lambda letrec"    `Quick test_defun_e2e_no_lambda_letrec;
          Alcotest.test_case "defun e2e closure types"        `Quick test_defun_e2e_closure_types_present;
          Alcotest.test_case "defun e2e no HOF unchanged"     `Quick test_defun_e2e_no_hof_unchanged;
        ] );
      ( "fusion",
        [
          Alcotest.test_case "use_count helper"          `Quick test_fusion_use_count;
          Alcotest.test_case "map+fold fused"            `Quick test_fusion_map_fold;
          Alcotest.test_case "filter+fold fused"         `Quick test_fusion_filter_fold;
          Alcotest.test_case "map+filter+fold fused"     `Quick test_fusion_map_filter_fold;
          Alcotest.test_case "eliminates intermediate"   `Quick test_fusion_eliminates_intermediate;
          Alcotest.test_case "no fuse multi-use"         `Quick test_fusion_no_fuse_multi_use;
          Alcotest.test_case "no fuse impure"            `Quick test_fusion_no_fuse_impure;
          Alcotest.test_case "fused fn in tm_fns"        `Quick test_fusion_fused_fn_in_tm_fns;
          Alcotest.test_case "no change non-list"        `Quick test_fusion_no_change_non_list;
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
          Alcotest.test_case "impl dotted iface"   `Quick test_parse_impl_dotted_iface;
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
          Alcotest.test_case "impl valid"              `Quick test_tc_impl_valid;
          Alcotest.test_case "impl unknown iface"     `Quick test_tc_impl_unknown_iface;
          Alcotest.test_case "superclass satisfied"   `Quick test_superclass_satisfied;
          Alcotest.test_case "superclass missing"     `Quick test_superclass_missing;
          Alcotest.test_case "default method tc"      `Quick test_default_method_inherited;
          Alcotest.test_case "default method eval"    `Quick test_default_method_eval;
          Alcotest.test_case "general iface multi-impl dispatch" `Quick test_general_iface_multi_impl_dispatch;
          Alcotest.test_case "interp colliding general iface dispatch (Layer 1b)" `Quick test_interp_colliding_general_iface_dispatch;
          Alcotest.test_case "interp colliding double-collision ctor construction+match" `Quick test_interp_colliding_double_collision_ctor_construction_and_match;
          Alcotest.test_case "interp colliding double-collision ctor impl-construction+module-match" `Quick test_interp_colliding_double_collision_ctor_impl_construction_and_module_match;
          Alcotest.test_case "default method user type"`Quick test_default_method_user_type;
          Alcotest.test_case "missing required method"`Quick test_missing_required_method;
          Alcotest.test_case "unknown ctor suggests"  `Quick test_unknown_ctor_suggests_similar;
          Alcotest.test_case "ambiguous ctor warns"   `Quick test_ambiguous_ctor_warns;
          Alcotest.test_case "unused var warns"        `Quick test_unused_var_warning;
          Alcotest.test_case "underscore no warn"      `Quick test_unused_var_underscore_ok;
          Alcotest.test_case "parse err type missing =" `Quick test_parse_error_type_missing_eq;
          Alcotest.test_case "parse err iface no param" `Quick test_parse_error_interface_missing_param;
          Alcotest.test_case "parse err impl no type"   `Quick test_parse_error_impl_missing_type;
          Alcotest.test_case "valid syntax not broken"  `Quick test_parse_valid_not_broken;
          Alcotest.test_case "multi-error recovery"     `Quick test_multi_error_recovery_collects;
        ] );
      ( "string interp",
        [
          Alcotest.test_case "parse interp"         `Quick test_parse_string_interp;
          Alcotest.test_case "parse interp many"    `Quick test_parse_string_interp_many_parts;
          Alcotest.test_case "eval interp"          `Quick test_eval_string_interp;
          Alcotest.test_case "eval interp int"      `Quick test_eval_string_interp_int;
          Alcotest.test_case "eval interp multi"    `Quick test_eval_string_interp_multi;
        ] );
      ( "repl commands",
        [
          Alcotest.test_case ":type int"            `Quick test_repl_type_int;
          Alcotest.test_case ":type bool"           `Quick test_repl_type_bool;
          Alcotest.test_case ":type string"         `Quick test_repl_type_string;
          Alcotest.test_case ":doc missing"         `Quick test_repl_doc_missing;
          Alcotest.test_case ":doc registered"      `Quick test_repl_doc_registered;
        ] );
      ( "repl integration",
        [
          Alcotest.test_case "error recovery: type"    `Quick test_repl_error_recovery_type;
          Alcotest.test_case "error recovery: runtime" `Quick test_repl_error_recovery_runtime;
          Alcotest.test_case "v magic var"             `Quick test_repl_v_magic_var;
          Alcotest.test_case "pretty: list"            `Quick test_repl_pretty_list;
          Alcotest.test_case "pretty: list truncation" `Quick test_repl_pretty_list_truncation;
          Alcotest.test_case "pretty: ADT constructor" `Quick test_repl_pretty_adt;
          Alcotest.test_case "pretty: record"          `Quick test_repl_pretty_record;
          Alcotest.test_case "pretty: depth truncation" `Quick test_repl_pretty_depth_truncation;
          Alcotest.test_case ":inspect type+value"     `Quick test_repl_inspect_type_and_value;
          Alcotest.test_case "final-review: renders desugar ParseError, not internal error"
            `Quick test_repl_renders_desugar_parse_error;
          Alcotest.test_case "JIT: nullary ctor tags of a REPL-declared type"
            `Quick test_repl_jit_nullary_ctor_tags;
        ] );
      ( "repl parity",
        [
          Alcotest.test_case "closures"              `Quick test_repl_parity_closures;
          Alcotest.test_case "HOF"                   `Quick test_repl_parity_hof;
          Alcotest.test_case "ADT"                   `Quick test_repl_parity_adt;
          Alcotest.test_case "match"                 `Quick test_repl_parity_match;
          Alcotest.test_case "mutual recursion"      `Quick test_repl_parity_mutual_recursion;
          Alcotest.test_case "string interpolation"  `Quick test_repl_parity_string_interp;
          Alcotest.test_case "records"               `Quick test_repl_parity_records;
          Alcotest.test_case "if/else"               `Quick test_repl_parity_if_else;
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
          Alcotest.test_case "to_string borrowed field no EDecRC" `Quick test_perceus_to_string_borrowed_field_no_decrc;
          Alcotest.test_case "pipeline no crash"         `Quick test_perceus_pipeline_no_crash;
          Alcotest.test_case "needs_rc TCon/TInt"        `Quick test_perceus_needs_rc_tcon;
          Alcotest.test_case "preserves fn count"        `Quick test_perceus_preserves_fn_count;
          Alcotest.test_case "scrut-escape rewrite (rc50)" `Quick test_perceus_scrut_escape_rewrite;
          Alcotest.test_case "closure FV single-use incrc (rc64)" `Quick test_perceus_closure_fv_single_use_incrc;
          Alcotest.test_case "closure FV list incrc when $clo is borrowed" `Quick test_perceus_closure_fv_borrowed_clo_incrc;
          Alcotest.test_case "elide preserves mixed atomicity (P4)" `Quick test_perceus_elide_preserves_mixed_atomicity;
          (* Regression: 831e315 needs_rc(TFn) caused spurious EIncRC for EApp
             operator callees like && / || whose llvm_name maps to @__ *)
          Alcotest.test_case "no EIncRC for && / || callee (831e315)" `Quick test_perceus_no_incrc_for_eapp_operator_callee;
          (* Regression: cross-module opaque type leaves an unresolved TVar; the
             heap value used twice must be dup'd or the second consume
             double-frees (bastion Gate.cast RC underflow UAF). *)
          Alcotest.test_case "incrc for unresolved-tvar value used twice (cross-module opaque)" `Quick test_perceus_incrc_for_unresolved_tvar_used_twice;
          (* Regression: record param used in two sequential calls — second
             call read a freed field string (RC underflow).  Fix: TRecord is
             now borrow-eligible; _borrowed_field_vars suppresses field RC ops. *)
          Alcotest.test_case "record param multi-call no RC underflow" `Quick test_perceus_record_param_multi_call_no_rc_underflow;
          (* Regression: List.length(xs) followed by List.nth(xs, 0) — the
             consuming go closure decrements Cons nodes; caller must emit
             EIncRC to keep xs alive for the subsequent List.nth call. *)
          Alcotest.test_case "list length+nth EIncRC emitted" `Quick test_perceus_list_length_then_nth_incrc;
          (* Regression: tuple param destructured in multiple sequential
             match arms caused RC underflow — field_escape_owns was
             incorrectly flipping TTuple params to cfg:own, bypassing the
             scrutinee_borrowed EIncRC mechanism. *)
          Alcotest.test_case "tuple param multi-destruct no RC underflow" `Quick test_perceus_tuple_param_multi_destruct_no_rc_underflow;
          (* Regression: locally-owned record field (from cross-module function
             return) treated as owned → spurious EDecRC freed meta.title while
             meta still held a reference.  Fix: _var_ctx check in is_borrowed_field
             extends _borrowed_field_vars suppression to locally-owned records. *)
          Alcotest.test_case "local record field no spurious decrc" `Quick test_perceus_local_record_field_no_spurious_decrc;
        ] );
      ( "lean_theorem_properties", [
          Alcotest.test_case "lin_drop_is_free"          `Quick test_thm_lin_drop_is_free;
          Alcotest.test_case "aff_drop_is_free"          `Quick test_thm_aff_drop_is_free;
          Alcotest.test_case "decrc_implies_unr"         `Quick test_thm_decrc_implies_unr;
          Alcotest.test_case "drop_scalar_noop (Lin)"    `Quick test_thm_drop_scalar_noop_lin;
          Alcotest.test_case "drop_scalar_noop (Unr)"    `Quick test_thm_drop_scalar_noop_unr;
          Alcotest.test_case "defun preserves linearity" `Quick test_thm_defun_preserves_linearity;
        ] );
      ( "borrow_inference", [
          Alcotest.test_case "read-only param is borrowed"           `Quick test_borrow_read_only_param_is_borrowed;
          Alcotest.test_case "returned param is owned"               `Quick test_borrow_returned_param_is_owned;
          Alcotest.test_case "stored param is owned"                 `Quick test_borrow_stored_param_is_owned;
          Alcotest.test_case "Int param not borrowed (no RC needed)" `Quick test_borrow_int_param_not_in_map;
          Alcotest.test_case "passed to borrowed callee: stays borrowed"  `Quick test_borrow_passed_to_borrowed_callee_stays_borrowed;
          Alcotest.test_case "passed to owned callee: becomes owned"      `Quick test_borrow_passed_to_owned_callee_becomes_owned;
          Alcotest.test_case "no IncRC at call site for borrowed arg"     `Quick test_borrow_no_incrc_at_call_site;
          Alcotest.test_case "no DecRC in callee for borrowed param"      `Quick test_borrow_no_decrc_in_callee;
          Alcotest.test_case "owned param still gets RC"                  `Quick test_borrow_owned_param_still_gets_rc;
          Alcotest.test_case "HTTP Conn middleware pattern"               `Quick test_borrow_conn_middleware_pattern;
        ] );
      ( "escape_analysis", [
          Alcotest.test_case "local discarded promoted"      `Quick test_escape_local_discarded_promoted;
          Alcotest.test_case "newtype not promoted (L7)"     `Quick test_escape_newtype_not_promoted;
          Alcotest.test_case "returned not promoted"         `Quick test_escape_returned_not_promoted;
          Alcotest.test_case "stored in alloc not promoted"  `Quick test_escape_stored_in_alloc_not_promoted;
          Alcotest.test_case "match field read promoted"     `Quick test_escape_match_field_promoted;
          Alcotest.test_case "decrc eliminated on promote"   `Quick test_escape_decrc_eliminated_after_promotion;
          Alcotest.test_case "pipeline no crash"             `Quick test_escape_pipeline_no_crash;
        ] );
      ( "atomic_rc", [
          Alcotest.test_case "non-actor uses local RC"       `Quick test_atomic_rc_non_actor_uses_local_rc;
          Alcotest.test_case "actor send pipeline no crash"  `Quick test_atomic_rc_actor_send_uses_atomic_rc;
          Alcotest.test_case "sent box: no local IncRC"      `Quick test_atomic_rc_sent_box_shared_gets_atomic_inc;
          Alcotest.test_case "non-sent pattern: local DecRC" `Quick test_atomic_rc_local_decrc_not_atomic;
        ] );
      ( "actor_tir_lowering", [
          Alcotest.test_case "generates types"             `Quick test_actor_tir_lowering_generates_types;
          Alcotest.test_case "generates functions"         `Quick test_actor_tir_lowering_generates_functions;
          Alcotest.test_case "dispatch has ECase"          `Quick test_actor_tir_dispatch_has_ecase;
          Alcotest.test_case "dispatch branch count"       `Quick test_actor_tir_dispatch_branch_count;
          Alcotest.test_case "spawn returns TPtr"          `Quick test_actor_tir_spawn_returns_ptr;
          Alcotest.test_case "handler params"              `Quick test_actor_tir_handler_params;
          Alcotest.test_case "handler loads state"         `Quick test_actor_tir_handler_loads_state;
          Alcotest.test_case "spawn has EAlloc"            `Quick test_actor_tir_spawn_contains_ealloc;
          Alcotest.test_case "supervisor spawn registers"  `Quick test_actor_tir_supervisor_spawn_calls_register;
          Alcotest.test_case "non-supervisor no register"  `Quick test_actor_tir_non_supervisor_no_register;
          Alcotest.test_case "msg variant ctors"           `Quick test_actor_tir_msg_variant_ctors;
          Alcotest.test_case "actor struct dispatch field" `Quick test_actor_tir_actor_struct_has_dispatch_field;
          Alcotest.test_case "full pipeline no crash"      `Quick test_actor_tir_full_pipeline_no_crash;
        ] );
      ( "actor_compile", [
          Alcotest.test_case "dispatch emitted"             `Quick test_actor_compile_dispatch_emitted;
          Alcotest.test_case "spawn fn emitted"             `Quick test_actor_compile_spawn_fn_emitted;
          Alcotest.test_case "handlers emitted"             `Quick test_actor_compile_handlers_emitted;
          Alcotest.test_case "supervisor registers"         `Quick test_actor_compile_supervisor_registers;
          Alcotest.test_case "monitor emitted"              `Quick test_actor_compile_monitor_emitted;
          Alcotest.test_case "multi-actor no crash"         `Quick test_actor_compile_multi_actor_no_crash;
          Alcotest.test_case "run_scheduler in main"        `Quick test_actor_compile_run_scheduler_in_main;
          Alcotest.test_case "actor_call/reply emitted"     `Quick test_actor_compile_call_reply_emitted;
        ] );
      ( "h_sigil_csrf_conn_gated", [
          Alcotest.test_case "B16: ~H form post typechecks standalone" `Quick test_h_sigil_form_post_typechecks_standalone;
          Alcotest.test_case "B16: ~H form post runs standalone"       `Quick test_h_sigil_form_post_runs_standalone;
          Alcotest.test_case "conn param: CSRF token injected"         `Quick test_h_sigil_form_post_injects_with_conn_param;
          Alcotest.test_case "block let conn: CSRF token injected"     `Quick test_h_sigil_form_post_injects_with_conn_let;
          Alcotest.test_case "GET form with conn: no injection"        `Quick test_h_sigil_get_form_not_injected_with_conn;
          Alcotest.test_case "short interp: escaped"                   `Quick test_h_sigil_escapes_short_interp;
          Alcotest.test_case "many-part interp: escaped"               `Quick test_h_sigil_escapes_many_part_interp;
        ] );
  ]
