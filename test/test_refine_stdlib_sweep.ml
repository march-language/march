(* The stdlib lemma sweep, phase S1 (specs/2026-11-04-stdlib-lemma-sweep-design.md):
   the `List` laws over `append` that a caller cannot get by unfolding, and the
   refined result types of `Math.min_int`, `max_int` and `clamp_int`.

   Group `reflect-stdlib-sweep`.  Each lemma case checks the call proves a
   precondition that does not prove without it.  Every case drives the REAL
   compiler through [Test_refine_unfold]'s helpers. *)

module U = Test_refine_unfold

let gated = U.gated
let run = U.run
let expect = U.expect
let contains = U.contains
let lines = U.lines

let needs =
  {|  fn need_leq(a : List(Int), b : {List(Int) | _ == a}) : Int do 0 end
  fn need_oeq(a : Option(Int), b : {Option(Int) | _ == a}) : Int do 0 end
  fn need_ge(lo : Int, v : {Int | _ >= lo}) : Int do 0 end
|}

(* Phase S2's programs: [needs] plus two more, so lines 1-6 and a test's first
   function starts at 7. *)
let prog2 body =
  "mod U do\n" ^ needs ^ "  fn need_ieq(a : Int, b : {Int | _ == a}) : Int do 0 end\n"
  ^ "  fn need_len(a : List(Int), n : {Int | _ == len(a)}) : Int do 0 end\n" ^ body ^ "end\n"

let with_and_without2 ~line ~callee ~lemma body =
  let out = run (prog2 (body ("    " ^ lemma ^ "\n"))) in
  expect out ~line:(line + 1) ~callee "proved";
  let out = run (prog2 (body "")) in
  U.not_proved out ~line ~callee

(* `mod U do` + [needs] is lines 1-4; a test's first function starts at 5. *)
let prog body = "mod U do\n" ^ needs ^ body ^ "end\n"

(* [call] is a lemma call on its own line, or "" for the control. *)
let with_and_without ~line ~callee ~lemma body =
  let out = run (prog (body ("    " ^ lemma ^ "\n"))) in
  expect out ~line:(line + 1) ~callee "proved";
  let out = run (prog (body "")) in
  U.not_proved out ~line ~callee

(* (verdict, fn) of each postcondition row in stdlib/<file>. *)
let stdlib_post_rows file out =
  List.filter_map
    (fun l ->
      match String.split_on_char '\t' l with
      | v :: "stdlib" :: loc :: rest when contains loc file -> (
        match v, rest with
        | "skip", _ :: "postcondition" :: c :: _ -> Some ("skip", c)
        | _, "postcondition" :: c :: _ -> Some (v, c)
        | _ -> None)
      | _ -> None)
    (lines out)

(* Compare parsed structure independently of the printer, ignoring source spans. *)
let rec predicate_tree expr =
  let open March_ast.Ast in
  match expr with
  | EVar n -> "var:" ^ n.txt
  | ELit (LitInt n, _) -> "int:" ^ string_of_int n
  | EApp (f, args, _) ->
    "app(" ^ predicate_tree f ^ "," ^ String.concat "," (List.map predicate_tree args) ^ ")"
  | EField (recv, n, _) -> "field(" ^ predicate_tree recv ^ "," ^ n.txt ^ ")"
  | _ -> Alcotest.fail "unexpected predicate fixture node"

let predicate_roundtrip source expected () =
  let parse s = March_parser.Parse.expr_of_lexbuf (Lexing.from_string s) in
  let original = parse source in
  let builtin = March_refinecheck.Reflect_state.negate_builtin_at in
  let saved = !builtin in
  let printed =
    Fun.protect ~finally:(fun () -> builtin := saved) (fun () ->
        builtin := (fun _ -> true);
        March_refinecheck.Refine_scope.pred_str original)
  in
  Alcotest.(check string) "rendered predicate" expected printed;
  Alcotest.(check string) "same parsed tree" (predicate_tree original) (predicate_tree (parse printed))

let predicate_tests =
  List.map
    (fun (source, expected) ->
      Alcotest.test_case ("predicate grouping: " ^ source) `Quick (predicate_roundtrip source expected))
    [ "_ <= a && _ <= b && (_ == a || _ == b)", "_ <= a && _ <= b && (_ == a || _ == b)";
      "high < low || (_ >= low && _ <= high)", "high < low || _ >= low && _ <= high";
      "(a + b) * c", "(a + b) * c";
      "a - (b - c)", "a - (b - c)";
      "a / (b * c)", "a / (b * c)";
      "a + (b + c)", "a + (b + c)";
      "a && (b && c)", "a && (b && c)";
      "(a == b) == c", "(a == b) == c";
      "a == (b == c)", "a == (b == c)";
      "!(a || b)", "!(a || b)";
      "!(a +. b)", "!(a +. b)";
      "-(a + b)", "-(a + b)";
      "-(-a)", "-(-a)";
      "(a + b).value", "(a + b).value";
      "(-a).value", "(-a).value";
      "(f(a)).value", "(f(a)).value";
      "a /. (b *. c)", "a /. (b *. c)";
      "a + b * c - d", "a + b * c - d" ]

let tests =
  predicate_tests @ [ gated "List.drop_append: drop(append(xs, ys), len(xs)) == ys (without it: a fuel skip)" (fun () ->
        with_and_without ~line:6 ~callee:"need_leq" ~lemma:"List.drop_append(xs, ys)" (fun call ->
            "  fn a(xs : List(Int), ys : List(Int)) : Int do\n" ^ call
            ^ "    need_leq(ys, List.drop(List.append(xs, ys), List.length(xs)))\n  end\n"));
    gated "List.take_append: take(append(xs, ys), len(xs)) == xs" (fun () ->
        with_and_without ~line:6 ~callee:"need_leq" ~lemma:"List.take_append(xs, ys)" (fun call ->
            "  fn a(xs : List(Int), ys : List(Int)) : Int do\n" ^ call
            ^ "    need_leq(xs, List.take(List.append(xs, ys), List.length(xs)))\n  end\n"));
    gated "List.nth_opt_append: an index inside xs reads the same from append(xs, ys)" (fun () ->
        let body call =
          "  fn a(xs : List(Int), ys : List(Int), i : {Int | _ >= 0 && _ < len(xs)}) : Int do\n" ^ call
          ^ "    need_oeq(List.nth_opt(xs, i), List.nth_opt(List.append(xs, ys), i))\n  end\n"
        in
        with_and_without ~line:6 ~callee:"need_oeq" ~lemma:"List.nth_opt_append(xs, ys, i)" body);
    gated "REJECT control: List.nth_opt_append with an index not known to be inside xs gives no fact" (fun () ->
        let out =
          run
            (prog
               "  fn a(xs : List(Int), ys : List(Int), i : {Int | _ >= 0}) : Int do\n    List.nth_opt_append(xs, ys, i)\n    need_oeq(List.nth_opt(xs, i), List.nth_opt(List.append(xs, ys), i))\n  end\n")
        in
        if not (List.exists (fun l -> contains l "[lemma_unproved_call]") (lines out)) then
          Alcotest.failf "expected lemma_unproved_call:\n%s" out;
        U.not_proved out ~line:7 ~callee:"need_oeq");
    gated "stdlib: the three List lemmas are admitted from the manifest" (fun () ->
        let out = run "mod U do\n  fn f(n : Int) : Int do n end\nend\n" in
        let rows = stdlib_post_rows "list.march" out in
        List.iter
          (fun l ->
            if not (List.mem ("trusted", l) rows) then Alcotest.failf "%s is not admitted from the manifest:\n%s" l out)
          [ "take_onto_append"; "take_append"; "drop_append"; "nth_opt_append" ]);
    gated "Math: min_int, max_int and clamp_int prove their result types" (fun () ->
        let out = run "mod U do\n  fn f(n : Int) : Int do n end\nend\n" in
        let min_rows =
          List.filter (fun row -> contains row "\tpostcondition\tmin_int\t") (lines out)
        in
        if min_rows = [] then Alcotest.failf "missing min_int report row:\n%s" out;
        List.iter
          (fun row ->
            if not (contains row "_ <= a && _ <= b && (_ == a || _ == b)") then
              Alcotest.failf "min_int report lost predicate grouping:\n%s" row)
          min_rows;
        let rows = stdlib_post_rows "math.march" out in
        List.iter
          (fun f ->
            if not (List.mem ("proved", f) rows) then Alcotest.failf "%s's result type is not proved:\n%s" f out;
            if List.exists (fun (v, c) -> c = f && v <> "proved") rows then
              Alcotest.failf "%s has a row that is not proved:\n%s" f out)
          [ "min_int"; "max_int"; "clamp_int" ]);
    gated "Math.clamp_int: a caller with low <= high gets the range" (fun () ->
        let out =
          run (prog "  fn a(x : Int, lo : Int, hi : {Int | _ >= lo}) : Int do\n    need_ge(lo, Math.clamp_int(x, lo, hi))\n  end\n")
        in
        expect out ~line:6 ~callee:"need_ge" "proved");
    gated "REJECT control: Math.clamp_int with high below low gives no range" (fun () ->
        let out = run (prog "  fn a(x : Int, lo : Int, hi : Int) : Int do\n    need_ge(lo, Math.clamp_int(x, lo, hi))\n  end\n") in
        U.not_proved out ~line:6 ~callee:"need_ge") ]

(* Phase S2: the accumulator loops of `length`, `sum_int` and `product_int`
   lifted to `pfn`s, so their laws can be stated and proved. *)
let s2 =
  let law ~lemma ~lhs ~rhs =
    with_and_without2 ~line:8 ~callee:"need_ieq" ~lemma (fun call ->
        "  fn a(xs : List(Int), ys : List(Int)) : Int do\n" ^ call ^ "    need_ieq(" ^ lhs ^ ", " ^ rhs ^ ")\n  end\n")
  in
  [ gated "List.length's result type: a caller learns List.length(xs) == len(xs)" (fun () ->
        let out =
          run (prog2 "  fn a(xs : List(Int)) : Int do\n    need_len(xs, List.length(xs))\n  end\n")
        in
        expect out ~line:8 ~callee:"need_len" "proved");
    gated "List.sum_int_append: sum_int(append(xs, ys)) == sum_int(xs) + sum_int(ys)" (fun () ->
        law ~lemma:"List.sum_int_append(xs, ys)" ~lhs:"List.sum_int(xs) + List.sum_int(ys)"
          ~rhs:"List.sum_int(List.append(xs, ys))");
    gated "List.sum_int_reverse: sum_int(reverse(xs)) == sum_int(xs)" (fun () ->
        law ~lemma:"List.sum_int_reverse(xs)" ~lhs:"List.sum_int(xs)" ~rhs:"List.sum_int(List.reverse(xs))");
    gated "List.product_int_append: product_int(append(xs, ys)) == product_int(xs) * product_int(ys)" (fun () ->
        law ~lemma:"List.product_int_append(xs, ys)" ~lhs:"List.product_int(xs) * List.product_int(ys)"
          ~rhs:"List.product_int(List.append(xs, ys))");
    gated "List.product_int_reverse: product_int(reverse(xs)) == product_int(xs)" (fun () ->
        law ~lemma:"List.product_int_reverse(xs)" ~lhs:"List.product_int(xs)"
          ~rhs:"List.product_int(List.reverse(xs))");
    gated "REJECT control: List.sum_int_append does not give a false sum" (fun () ->
        let out =
          run
            (prog2
               "  fn a(xs : List(Int), ys : List(Int)) : Int do\n    List.sum_int_append(xs, ys)\n    need_ieq(List.sum_int(xs), List.sum_int(List.append(xs, ys)))\n  end\n")
        in
        U.not_proved out ~line:9 ~callee:"need_ieq");
    gated "stdlib: the S2 List lemmas are admitted from the manifest" (fun () ->
        let out = run "mod U do\n  fn f(n : Int) : Int do n end\nend\n" in
        let rows = stdlib_post_rows "list.march" out in
        List.iter
          (fun l ->
            if not (List.mem ("trusted", l) rows) then Alcotest.failf "%s is not admitted from the manifest:\n%s" l out)
          [ "len_length_onto"; "sum_onto_shift"; "sum_onto_append"; "sum_int_append"; "sum_onto_reverse_onto";
            "sum_int_reverse"; "product_onto_shift"; "product_onto_append"; "product_int_append";
            "product_onto_reverse_onto"; "product_int_reverse" ]) ]

(* `cap verified` stdlib modules (2026-11-07 pass): every module that declares it
   must check clean as its own entry, the way its `cap verified` claim was
   measured; nothing else enforced a stdlib module's claim (stdlib diagnostics are
   filtered from user builds).  List is not among them yet: checked as its own
   entry, its `reverse` collides with `Prelude.reverse` (todo
   2026-11-07-stdlib-list-cap-verified). *)
let cap_verified =
  let stdlib = Filename.concat (Filename.dirname Sys.executable_name) "../stdlib" in
  let declares f =
    let src = In_channel.with_open_bin (Filename.concat stdlib f) In_channel.input_all in
    List.exists (fun l -> String.trim l = "cap verified") (String.split_on_char '\n' src)
  in
  let verified () =
    Sys.readdir stdlib |> Array.to_list
    |> List.filter (fun f -> Filename.check_suffix f ".march" && declares f)
    |> List.sort compare
  in
  [ Alcotest.test_case "the cap verified stdlib modules are the ones expected" `Quick (fun () ->
        let got = verified () in
        List.iter
          (fun f -> if not (List.mem f got) then Alcotest.failf "%s does not declare `cap verified` (got %s)" f (String.concat ", " got))
          [ "math.march"; "option.march"; "result.march"; "udp.march" ]);
    gated "every cap verified stdlib module checks clean as its own entry" (fun () ->
        let dir = Filename.concat (Filename.dirname Sys.executable_name) ".." in
        List.iter
          (fun f ->
            let out = U.run_in ~dir "--check --stdlib-source --refine-report" ("stdlib/" ^ f) in
            (* The module's own obligations: none violated, none skipped. *)
            let summary =
              List.find_opt (fun l -> U.contains l "refinement obligations (user code):") (lines out)
            in
            let clean =
              match summary with
              | Some l -> U.contains l " 0 violated" && U.contains l " 0 skipped"
              | None -> false
            in
            let bad_code =
              List.exists (fun c -> U.contains out ("[" ^ c ^ "]"))
                [ "refinement_violated"; "return_refinement_violated"; "refinement_unverified"; "lemma_unproved";
                  "invalid_lemma"; "termination_unproved" ]
            in
            if (not clean) || bad_code then
              Alcotest.failf "stdlib/%s declares `cap verified` but does not check clean:\n%s" f out)
          (verified ())) ]
