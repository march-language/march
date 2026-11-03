(* Refinement reflection, phase 4: repeated unfolding and fuel
   (specs/2026-10-29-refinement-reflection-design.md §3.8, §3.9, §10 "Phase 4";
   the plan is specs/plans/2026-11-03-reflection-phase4-fuel-plan.md).

   Group `reflect-fuel`.  Every case drives the REAL compiler through
   [Test_refine_unfold]'s helpers. *)

module U = Test_refine_unfold

let gated = U.gated
let run = U.run
let expect = U.expect
let contains = U.contains
let lines = U.lines

let cat_with attr =
  attr
  ^ {|  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end
|}

let need_eq = "  fn need_eq(a : List(Int), b : {List(Int) | _ == a}) : Int do 0 end\n"

let l4 = "Cons(1, Cons(2, Cons(3, Cons(4, Nil))))"

let code out c = List.exists (fun l -> contains l ("[" ^ c ^ "]")) (lines out)

let invalid_reflect out name =
  List.exists (fun l -> contains l "[invalid_reflect]" && contains l ("`" ^ name ^ "`")) (lines out)

let tests =
  [ gated "undecided_stays: a produced call on an unknown list is not unfolded (reflect-fuel)" (fun () ->
        let out =
          run
            ("mod N do\n" ^ cat_with ""
           ^ {|  fn need2(xs : {List(Int) | len(_) == 2}) : Int do 0 end
  fn f(xs : List(Int), ys : {List(Int) | len(_) == 2}) : Int do need2(cat(xs, ys)) end
end
|})
        in
        expect out ~line:9 ~callee:"need2" "skip:reflect-fuel");
    gated "fuel_override: a 4-element chain skips at the default fuel and proves at fuel 5" (fun () ->
        let src attr =
          "mod N do\n" ^ cat_with attr ^ need_eq
          ^ Printf.sprintf "  fn f() : Int do need_eq(%s, cat(%s, Nil)) end\nend\n" l4 l4
        in
        let out = run (src "") in
        expect out ~line:9 ~callee:"need_eq" "skip:reflect-fuel";
        let out = run (src "  @[reflect(fuel: 5)]\n") in
        expect out ~line:10 ~callee:"need_eq" "proved" ~uses:"cat");
    gated "fuel_lower: @[reflect(fuel: 1)] brings a6 back to single unfolding" (fun () ->
        let out =
          run
            ("mod N do\n" ^ cat_with "  @[reflect(fuel: 1)]\n"
           ^ {|  fn need2(xs : {List(Int) | len(_) == 2}) : Int do 0 end
  fn go() : Int do need2(cat(Cons(1, Nil), Cons(2, Nil))) end
end
|})
        in
        expect out ~line:10 ~callee:"need2" "skip:reflect-fuel");
    gated "budget_deep: decided chains past 32 unfoldings skip reflect-budget" (fun () ->
        let l8 = "Cons(1, Cons(2, Cons(3, Cons(4, Cons(5, Cons(6, Cons(7, Cons(8, Nil))))))))" in
        let rhs = Printf.sprintf "cat(%s, cat(%s, cat(%s, cat(%s, cat(%s, Nil)))))" l8 l8 l8 l8 l8 in
        (* The true value, so only the budget can stop the proof. *)
        let l40 =
          List.fold_right (fun k acc -> Printf.sprintf "Cons(%d, %s)" k acc)
            (List.concat (List.init 5 (fun _ -> [ 1; 2; 3; 4; 5; 6; 7; 8 ]))) "Nil"
        in
        let out =
          run
            ("mod N do\n" ^ cat_with "  @[reflect(fuel: 8)]\n" ^ need_eq
            ^ Printf.sprintf "  fn f() : Int do need_eq(%s, %s) end\nend\n" l40 rhs)
        in
        expect out ~line:10 ~callee:"need_eq" "skip:reflect-budget");
    gated "sound_domain_depth1: a decided step keeps the callee's domain guard (C1)" (fun () ->
        (* `p(0 - 1)` is a depth-1 term outside `p`'s domain: without the
           guard it would unfold to `-1` and prove the obligation. *)
        let out =
          run
            {|mod N do
  fn p(n : {Int | _ >= 0}) : Int do n end
  fn q(n : Int) : Int do p(n) end
  fn need_m1(x : {Int | _ == 0 - 1}) : Int do x end
  fn f() : Int do need_m1(q(0 - 1)) end
end
|}
        in
        U.not_proved out ~line:5 ~callee:"need_m1");
    gated "sound_definite_stage2: a model of an unfolded-past-fuel call is not a violation (review)" (fun () ->
        (* `cnt` of any 3-element list is 3, so no element can fail; the
           stage-2 model gave the depth-2 `cnt([2])` a free value and the
           element shortcut called that a definite failure. *)
        let out =
          run
            {|mod N do
  fn cnt(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(_, t) -> 1 + cnt(t)
    end
  end
  fn need_all(xs : List({v : Int | cnt(Cons(v, Cons(1, Cons(2, Nil)))) == 3})) : Int do 0 end
  fn go(ys : List({Int | _ > 0})) : Int do need_all(ys) end
end
|}
        in
        if code out "refinement_violated" then Alcotest.failf "no violation: the program cannot fail:\n%s" out);
    gated "sound_dropped_fact: an element fact that does not translate is not a free element (review)" (fun () ->
        (* `_ > 5 && _ == one(0) + 4` with `one` opaque: the fact was dropped
           whole, `$elem` went free, and `elem = 0` was reported. *)
        let out =
          run
            {|mod N do
  @[opaque]
  fn one(x : Int) : Int do 1 end
  fn need_all(xs : List({Int | _ > 0})) : Int do 0 end
  fn go3(ys : List({Int | _ > 5 && _ == one(0) + 4})) : Int do need_all(ys) end
end
|}
        in
        if code out "refinement_violated" then Alcotest.failf "no violation: every element is > 5:\n%s" out);
    gated "fuel_cap: fuel above 8 is invalid_reflect" (fun () ->
        let out = run ~args:"--check" "mod N do\n  @[reflect(fuel: 9)]\n  fn a(n : Int) : Int do n end\nend\n" in
        if not (invalid_reflect out "a") then Alcotest.failf "expected invalid_reflect:\n%s" out);
    gated "fuel_zero: fuel 0 is invalid_reflect (@[opaque] is the opt-out)" (fun () ->
        let out = run ~args:"--check" "mod N do\n  @[reflect(fuel: 0)]\n  fn a(n : Int) : Int do n end\nend\n" in
        if not (invalid_reflect out "a") then Alcotest.failf "expected invalid_reflect:\n%s" out);
    gated "reflect_assert: @[reflect] on a function that is not reflected names the blocker" (fun () ->
        let out =
          run ~args:"--check"
            "mod N do\n  needs IO.Console\n  @[reflect]\n  fn noisy(n : Int) : Int do\n    println(\"x\")\n    n\n  end\nend\n"
        in
        if not (List.exists (fun l -> contains l "[invalid_reflect]" && contains l "println") (lines out)) then
          Alcotest.failf "expected invalid_reflect naming println:\n%s" out);
    gated "reflect_ok: @[reflect] on a reflected function draws nothing" (fun () ->
        let out = run ~args:"--check" ("mod N do\n" ^ cat_with "  @[reflect]\n" ^ "end\n") in
        if code out "invalid_reflect" || code out "unknown_attribute" then Alcotest.failf "no diagnostic expected:\n%s" out);
    gated "reflect_opaque: @[reflect] with @[opaque] is reflect_conflict" (fun () ->
        let out = run ~args:"--check" "mod N do\n  @[reflect] @[opaque]\n  fn a(n : Int) : Int do n end\nend\n" in
        if not (code out "reflect_conflict") then Alcotest.failf "expected reflect_conflict:\n%s" out);
    gated "parser: another labelled attribute payload is a parse error naming it" (fun () ->
        let out = run ~args:"--check" "mod N do\n  @[measure(fuel: 3)]\n  fn a(n : Int) : Int do n end\nend\n" in
        if not (contains out "only `@[reflect(fuel: N)]` takes a labelled argument") then
          Alcotest.failf "expected the labelled-payload parse error:\n%s" out) ]
