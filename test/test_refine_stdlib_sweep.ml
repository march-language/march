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

let tests =
  [ gated "List.drop_append: drop(append(xs, ys), len(xs)) == ys (without it: a fuel skip)" (fun () ->
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
