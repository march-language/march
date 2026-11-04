(* Refinement reflection, phase 5: function values, specialised per call site
   (specs/2026-10-29-refinement-reflection-design.md §10 "Phase 5", D10; the
   plan is specs/plans/2026-11-03-reflection-phase5-fnvalues-plan.md).

   Group `reflect-spec`.  Every case drives the REAL compiler through
   [Test_refine_unfold]'s helpers.  The soundness rows each have a RED
   control: the test-only perturbation named in the plan's table makes the
   guarded false claim prove (or the rule's effect show), so a green row is
   evidence the rule is what stops it. *)

module U = Test_refine_unfold

let gated = U.gated
let run = U.run
let expect = U.expect
let not_proved = U.not_proved
let contains = U.contains
let lines = U.lines

(* The 1-based line of the first line of [src] containing [needle]. *)
let line_of src needle =
  let ls = String.split_on_char '\n' src in
  let rec go i = function
    | [] -> Alcotest.failf "no line containing %S" needle
    | l :: rest -> if contains l needle then i else go (i + 1) rest
  in
  go 1 ls

(* A user `filter` in the shape the stdlib's has, with room for the chains
   below. *)
let keep =
  {|  @[reflect(fuel: 6)]
  fn keep(xs : List(a), pred : a -> Bool) : List(a) do
    match xs do
    Nil -> Nil
    Cons(h, t) -> if pred(h) do Cons(h, keep(t, pred)) else keep(t, pred) end
    end
  end
|}

let need_eq = "  fn need_eq(a : List(Int), b : {List(Int) | _ == a}) : Int do 0 end\n"

(* The `--reflect-report` row of [f]: (status, detail). *)
let report_row out f =
  List.find_map
    (fun l ->
      match String.split_on_char '\t' l with
      | "reflect" :: _ :: n :: st :: rest when n = f -> Some (st, String.concat "\t" rest)
      | _ -> None)
    (lines out)

let expect_report out f st =
  match report_row out f with
  | Some (s, d) -> if s <> st then Alcotest.failf "%s: expected %s, got %s (%s)\n%s" f st s d out
  | None -> Alcotest.failf "no report row for %s:\n%s" f out

let parity_status out name =
  match
    List.find_map
      (fun l ->
        match String.split_on_char '\t' l with
        | "parity" :: _ :: n :: st :: _ when n = name || String.starts_with ~prefix:(name ^ "[") n -> Some st
        | _ -> None)
      (lines out)
  with
  | Some s -> s
  | None -> Alcotest.failf "no parity row for %s:\n%s" name out

let tests =
  [ gated "spec_filter: a user filter is specialised, and its lambda caller is reflected and proves" (fun () ->
        let src =
          "mod N do\n" ^ keep ^ need_eq
          ^ {|  fn pos(xs : List(Int)) : List(Int) do keep(xs, fn x -> x > 0) end
  fn t() : Int do need_eq(Cons(1, Cons(3, Nil)), pos(Cons(1, Cons(0 - 2, Cons(3, Nil))))) end
end
|}
        in
        let out = run src in
        expect out ~line:(line_of src "fn t()") ~callee:"need_eq" "proved" ~uses:"keep[";
        let out = run ~args:"--check --reflect-report" src in
        expect_report out "keep" "specialised";
        expect_report out "pos" "reflected";
        if not (List.exists (fun l -> contains l "\tkeep\tspecialised\t1 call site") (lines out)) then
          Alcotest.failf "keep has one specialised call site:\n%s" out);
    gated "spec_stdlib: List.filter and List.map calls with a lambda prove" (fun () ->
        let src =
          "mod N do\n" ^ need_eq
          ^ {|  fn t1() : Int do need_eq(Cons(1, Nil), List.filter(Cons(1, Nil), fn x -> x > 0)) end
  fn t2() : Int do need_eq(Cons(2, Nil), List.map(Cons(1, Nil), fn x -> x + 1)) end
  fn t3() : Int do need_eq(Nil, List.filter(Cons(0 - 1, Nil), fn x -> x > 0)) end
  fn twice(x : Int) : List(Int) do List.map(Cons(x, Nil), fn y -> y + 1) end
end
|}
        in
        let out = run src in
        expect out ~line:(line_of src "fn t1") ~callee:"need_eq" "proved" ~uses:"List.filter[";
        expect out ~line:(line_of src "fn t2") ~callee:"need_eq" "proved" ~uses:"List.map[";
        expect out ~line:(line_of src "fn t3") ~callee:"need_eq" "proved";
        expect_report (run ~args:"--check --reflect-report" src) "twice" "reflected");
    gated "spec_named: a top-level function passed by name is specialised" (fun () ->
        let src =
          "mod N do\n" ^ keep ^ need_eq
          ^ {|  fn is_pos(x : Int) : Bool do x > 0 end
  fn t() : Int do need_eq(Cons(1, Nil), keep(Cons(1, Nil), is_pos)) end
end
|}
        in
        expect (run src) ~line:(line_of src "fn t()") ~callee:"need_eq" "proved" ~uses:"is_pos");
    gated "spec_capture: a capture is a parameter of the specialisation (RED: spec-capture-zero)" (fun () ->
        let src =
          "mod N do\n" ^ keep ^ need_eq
          ^ {|  fn above(xs : List(Int), k : Int) : List(Int) do keep(xs, fn x -> x > k) end
  fn t1() : Int do need_eq(Cons(5, Nil), above(Cons(5, Nil), 3)) end
  fn t2() : Int do need_eq(Nil, above(Cons(5, Nil), 7)) end
  fn t3() : Int do need_eq(Cons(5, Nil), above(Cons(5, Nil), 7)) end
end
|}
        in
        let out = run src in
        expect out ~line:(line_of src "fn t1") ~callee:"need_eq" "proved";
        expect out ~line:(line_of src "fn t2") ~callee:"need_eq" "proved";
        not_proved out ~line:(line_of src "fn t3") ~callee:"need_eq";
        let red = run ~env:"MARCH_REFLECT_PERTURB=spec-capture-zero" src in
        expect red ~line:(line_of src "fn t3") ~callee:"need_eq" "proved");
    gated "spec_identity: two lambdas get two definitions (RED: spec-key-by-callee)" (fun () ->
        let src =
          "mod N do\n" ^ keep ^ need_eq
          ^ {|  fn pos(xs : List(Int)) : List(Int) do keep(xs, fn x -> x > 0) end
  fn neg(xs : List(Int)) : List(Int) do keep(xs, fn x -> x < 0) end
  fn t() : Int do need_eq(pos(Cons(1, Nil)), neg(Cons(1, Nil))) end
end
|}
        in
        not_proved (run src) ~line:(line_of src "fn t()") ~callee:"need_eq";
        let red = run ~env:"MARCH_REFLECT_PERTURB=spec-key-by-callee" src in
        expect red ~line:(line_of src "fn t()") ~callee:"need_eq" "proved");
    gated "spec_by_name: a parameter spelled like a top-level function is not that function (RED: spec-by-spelling)"
      (fun () ->
        let src =
          "mod N do\n" ^ keep ^ need_eq
          ^ {|  fn is_pos(x : Int) : Bool do x > 0 end
  fn t(is_pos : Int -> Bool) : Int do need_eq(Cons(1, Nil), keep(Cons(1, Nil), is_pos)) end
end
|}
        in
        not_proved (run src) ~line:(line_of src "fn t(") ~callee:"need_eq";
        let red = run ~env:"MARCH_REFLECT_PERTURB=spec-by-spelling" src in
        expect red ~line:(line_of src "fn t(") ~callee:"need_eq" "proved");
    gated "spec_value_args: a closure from a call, a let-bound lambda or a parameter is not specialised" (fun () ->
        let src =
          "mod N do\n" ^ keep
          ^ {|  fn make(k : Int) : Int -> Bool do fn x -> x > k end
  fn a(xs : List(Int)) : List(Int) do keep(xs, make(3)) end
  fn b(xs : List(Int)) : List(Int) do
    let p = fn x -> x > 0
    keep(xs, p)
  end
  fn c(xs : List(Int), p : Int -> Bool) : List(Int) do List.length(keep(xs, p)) end
end
|}
        in
        let out = run ~args:"--check --reflect-report" src in
        (* `a`'s first blocker is `make` itself (R6: it makes a lambda);
           the call is refused either way. *)
        expect_report out "a" "no";
        expect_report out "b" "no";
        expect_report out "c" "no";
        if not (List.exists (fun l -> contains l "\tkeep\tspecialised\t0 call sites") (lines out)) then
          Alcotest.failf "none of the three calls is specialised:\n%s" out);
    gated "spec_recursion: recursion through a lambda is the caller's (R2) (RED: spec-lambda-own-unit)" (fun () ->
        let src =
          {|mod N do
  fn hd0(xs : List(Int)) : Int do
    match xs do
    Nil -> 0
    Cons(h, _) -> h
    end
  end
  fn bad(n : Int) : Int do hd0(List.map(Cons(n, Nil), fn x -> bad(x) + 1)) end
  fn need(x : {Int | _ == 6 || bad(0) == bad(0) + 1}) : Int do x end
  fn t() : Int do need(5) end
end
|}
        in
        not_proved (run src) ~line:(line_of src "fn t()") ~callee:"need";
        (match report_row (run ~args:"--check --reflect-report" src) "bad" with
         | Some ("no", d) when contains d "R2:" -> ()
         | _ -> Alcotest.fail "bad must be blocked by R2");
        let red = run ~env:"MARCH_REFLECT_PERTURB=spec-lambda-own-unit" src in
        expect red ~line:(line_of src "fn t()") ~callee:"need" "proved");
    gated "spec_swap: function parameters swapped in the recursive call are not specialised (RED: spec-any-position)"
      (fun () ->
        let src =
          "mod N do\n"
          ^ {|  @[reflect(fuel: 6)]
  fn alt(xs : List(Int), f : Int -> Int, g : Int -> Int) : List(Int) do
    match xs do
    Nil -> Nil
    Cons(h, t) -> Cons(f(h), alt(t, g, f))
    end
  end
  fn w(xs : List(Int)) : List(Int) do alt(xs, fn x -> x + 1, fn x -> x * 10) end
|}
          ^ need_eq
          ^ {|  fn t() : Int do need_eq(Cons(2, Cons(2, Nil)), w(Cons(1, Cons(1, Nil)))) end
end
|}
        in
        not_proved (run src) ~line:(line_of src "fn t()") ~callee:"need_eq";
        let rep = run ~args:"--check --reflect-report" src in
        (match report_row rep "alt" with
         | Some ("no", d) when contains d "R7:" -> ()
         | _ -> Alcotest.failf "alt must be blocked by R7:\n%s" rep);
        let red = run ~env:"MARCH_REFLECT_PERTURB=spec-any-position" src in
        expect red ~line:(line_of src "fn t()") ~callee:"need_eq" "proved");
    gated "spec_effect: a lambda with an effect is not specialised at a non-reflected caller (RED: spec-skip-lambda-check)"
      (fun () ->
        let src =
          "mod N do\n" ^ keep
          ^ {|  fn loud(x : Int) : Int do
    let _ = dbg(x)
    x
  end
  fn t(xs : List(Int)) : Int do
    let _ = dbg(0)
    List.length(keep(xs, fn x -> loud(x) > 0))
  end
end
|}
        in
        let out = run ~args:"--check --reflect-report" src in
        if not (List.exists (fun l -> contains l "\tkeep\tspecialised\t0 call sites") (lines out)) then
          Alcotest.failf "the impure lambda's call is not specialised:\n%s" out;
        let red = run ~env:"MARCH_REFLECT_PERTURB=spec-skip-lambda-check" ~args:"--check --reflect-report" src in
        if not (List.exists (fun l -> contains l "\tkeep\tspecialised\t1 call site") (lines red)) then
          Alcotest.failf "RED control: the check is what refuses it:\n%s" red);
    gated "spec_shape: self-application, a refined domain and a function passed on are not specialised" (fun () ->
        let src =
          {|mod N do
  fn apply1(f : Int -> Int, x : Int) : Int do f(f(x)) end
  fn sa(f : (Int -> Int) -> Int) : Int do 0 end
  fn sa2(f : Int -> Int, g : (Int -> Int) -> Int) : Int do g(f) end
  fn dom(xs : List(Int), pred : {Int | _ > 0} -> Bool) : Int do
    match xs do
    Nil -> 0
    Cons(h, _) -> if pred(h) do 1 else 0 end
    end
  end
  fn pass_on(xs : List(Int), f : Int -> Int) : Int do List.length(List.map(xs, f)) end
end
|}
        in
        let out = run ~args:"--check --reflect-report" src in
        expect_report out "apply1" "specialised";
        expect_report out "sa2" "no";
        expect_report out "dom" "no";
        expect_report out "pass_on" "no");
    gated "spec_reflect_attr: @[reflect] on a specialised function is accepted" (fun () ->
        let out = run ~args:"--check" ("mod N do\n" ^ keep ^ "end\n") in
        if U.has_code out "invalid_reflect" then Alcotest.failf "no invalid_reflect on keep:\n%s" out);
    gated "spec_predicate: a predicate cannot name a specialised function" (fun () ->
        let src =
          "mod N do\n" ^ keep
          ^ {|  fn is_pos(x : Int) : Bool do x > 0 end
  fn need(xs : {List(Int) | len(keep(_, is_pos)) == 0}) : Int do 0 end
  fn t() : Int do need(Nil) end
end
|}
        in
        let out = run src in
        not_proved out ~line:(line_of src "fn t()") ~callee:"need";
        if not (contains out "takes a function") then
          Alcotest.failf "the warning names why keep is not predicate vocabulary:\n%s" out;
        if contains out "internal_error" then Alcotest.failf "no internal error:\n%s" out);
    gated "spec_let_rebind: `let k = f(.. k ..)` gives no `k == f(k)` fact (review round 1; RED: let-self-ref)" (fun () ->
        (* At run time `k` is 0 in both: 5 > 7 is false.  The call-result
           fact is read at the obligation, where `k` is the new binding, so
           without the rule the solver saw `k == cnt$k(k)` and `k == gt5(k)`,
           whose only solution is 1.  The plain-call form was already on main. *)
        let src =
          {|mod N do
  @[reflect(fuel: 6)]
  fn cnt(xs : List(Int), p : Int -> Bool) : Int do
    match xs do
    Nil -> 0
    Cons(h, t) -> if p(h) do 1 + cnt(t, p) else cnt(t, p) end
    end
  end
  fn gt5(k : Int) : Int do if 5 > k do 1 else 0 end end
  fn need1(x : {Int | _ == 1}) : Int do x end
  fn t1() : Int do
    let k = 7
    let k = cnt(Cons(5, Nil), fn x -> x > k)
    need1(k)
  end
  fn t2() : Int do
    let k = 7
    let k = gt5(k)
    need1(k)
  end
end
|}
        in
        let out = run src in
        not_proved out ~line:(line_of src "need1(k)") ~callee:"need1";
        not_proved out ~line:(line_of src "need1(k)" + 5) ~callee:"need1";
        let red = run ~env:"MARCH_REFLECT_PERTURB=let-self-ref" src in
        expect red ~line:(line_of src "need1(k)") ~callee:"need1" "proved");
    gated "spec_parity: each specialisation agrees with the interpreter (RED: spec-swap-arms)" (fun () ->
        let src =
          "mod N do\n" ^ keep
          ^ {|  fn is_pos(x : Int) : Bool do x > 0 end
  fn above(xs : List(Int), k : Int) : List(Int) do keep(xs, fn x -> x > k) end
  fn pos2(xs : List(Int)) : List(Int) do keep(xs, is_pos) end
  fn inc_all(xs : List(Int)) : List(Int) do List.map(xs, fn x -> x + 1) end
end
|}
        in
        let out = run ~args:"--check --reflect-parity" src in
        List.iter
          (fun n -> Alcotest.(check string) n "agree" (parity_status out n))
          [ "above"; "pos2"; "inc_all"; "keep"; "List.map" ];
        if List.length (List.filter (fun l -> contains l "\tkeep[") (lines out)) <> 2 then
          Alcotest.failf "two specialisations of keep are compared:\n%s" out;
        let red = run ~env:"MARCH_REFLECT_PERTURB=spec-swap-arms" ~args:"--check --reflect-parity" src in
        Alcotest.(check string) "keep" "MISMATCH" (parity_status red "keep");
        if not (contains red "parity: RED") then Alcotest.failf "the net must report RED:\n%s" red) ]
