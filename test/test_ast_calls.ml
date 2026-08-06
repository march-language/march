(* Direct coverage for the shared AST call-walker. Until this file existed the
   walker had three copies and no test of its own: every consumer exercised it
   only indirectly, so a missing expression form showed up as a silently
   uncollected call rather than a failure. *)

(* Desugar after parsing: every real caller (typecheck's capability/no_panic
   scans, the proof-based pass) walks a DESUGARED module, where
   [desugar_expr]'s [EField] case has already flattened a module-qualified
   call like `List.map(...)` from `EApp(EField(ECon "List", "map", _), ...)`
   into a plain `EApp(EVar "List.map", ...)`. Parsing without desugaring
   would exercise this test against a shape the walker never actually sees in
   production. *)
let parse src =
  let lexbuf = Lexing.from_string src in
  let m =
    March_parser.Parser.module_
      (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
  in
  March_desugar.Desugar.desugar_module m

(* Pull the body of the first top-level fn out of a parsed module. *)
let first_fn_body (m : March_ast.Ast.module_) : March_ast.Ast.expr =
  let rec go decls =
    match decls with
    | March_ast.Ast.DFn (d, _) :: _ ->
      (match d.March_ast.Ast.fn_clauses with
       | c :: _ -> c.March_ast.Ast.fc_body
       | [] -> Alcotest.fail "fn has no clauses")
    | _ :: rest -> go rest
    | [] -> Alcotest.fail "no DFn in module"
  in
  go m.March_ast.Ast.mod_decls

let names_of src =
  first_fn_body (parse src)
  |> March_ast.Calls.names_and_name_spans
  |> List.map fst
  |> List.sort compare

let walker_suite =
  [ Alcotest.test_case "collects a bare call" `Quick (fun () ->
        Alcotest.(check (list string)) "helper"
          [ "helper" ]
          (names_of "mod T do\n  fn f(x : Int) : Int do helper(x) end\nend\n"));

    Alcotest.test_case "collects a qualified call as Mod.fn" `Quick (fun () ->
        Alcotest.(check (list string)) "List.map"
          [ "List.map" ]
          (names_of
             "mod T do\n\
             \  fn f(xs : List(Int)) : List(Int) do List.map(xs, fn y -> y) end\n\
              end\n"));

    (* The nested forms are the whole reason this test exists: a call buried in
       a match arm, an if branch, or a lambda body is exactly what a missing
       expression form would silently drop. *)
    Alcotest.test_case "descends into match arms and if branches" `Quick
      (fun () ->
        Alcotest.(check (list string)) "arm, then and else all found"
          [ "in_arm"; "in_else"; "in_then" ]
          (names_of
             "mod T do\n\
             \  fn f(o : Option(Int), b : Bool) : Int do\n\
             \    match o do\n\
             \      Some(v) -> in_arm(v)\n\
             \      None -> if b do in_then(1) else in_else(2) end\n\
             \    end\n\
             \  end\n\
              end\n"));

    Alcotest.test_case "descends into a lambda body" `Quick (fun () ->
        Alcotest.(check (list string)) "the lambda's call is found"
          [ "List.map"; "in_lambda" ]
          (names_of
             "mod T do\n\
             \  fn g(xs : List(Int)) : List(Int) do\n\
             \    List.map(xs, fn y -> in_lambda(y))\n\
             \  end\n\
              end\n"));

    (* app_span is what Obligation.record keys preconditions under; keying on
       the callee name's span instead would silently never match. Pin that the
       two spans are genuinely different objects for a call with arguments. *)
    Alcotest.test_case "name_span and app_span differ for a call with args" `Quick
      (fun () ->
        let body =
          first_fn_body
            (parse "mod T do\n  fn f(x : Int) : Int do helper(x) end\nend\n")
        in
        match March_ast.Calls.calls_in_expr [] body with
        | [ (_, name_span, app_span) ] ->
          Alcotest.(check bool) "app_span ends later than name_span" true
            (app_span.March_ast.Ast.end_col > name_span.March_ast.Ast.end_col)
        | other ->
          Alcotest.failf "expected exactly one call, got %d" (List.length other));
  ]

let () = Alcotest.run "march_ast_calls" [ "walker", walker_suite ]
