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
