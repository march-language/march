(* Proof hints (todos 2026-11-06-proof-assert-by, -proof-reveal-and-local-fuel,
   -proof-calc-blocks): scoped proof steps that the refinement checker uses and
   erasure removes.  Group `proof-hints`.  Every case drives the real compiler
   through [Test_refine_unfold]'s helpers. *)

module U = Test_refine_unfold

let gated = U.gated
let run = U.run
let expect = U.expect
let contains = U.contains

(* Lines 1-9; a test's first function starts at line 10. *)
let header =
  {|mod H do
  fn need_eq(a : Int, b : {Int | _ == a}) : Int do 0 end
  fn need4(x : {Int | _ == 4}) : Int do x end
  fn need3(x : {Int | _ == 3}) : Int do x end
  @[opaque]
  fn dbl(x : Int) : Int do x + x end
  @[decreases(n)]
  fn cnt(n : {Int | _ >= 0}) : Int do if n == 0 do 0 else cnt(n - 1) + 1 end end
  fn unit() : Int do 0 end
|}

let prog body = header ^ body ^ "end\n"

(* The sum law callers cannot get by unfolding (stdlib lemma sweep S2). *)
let sum_goal = "List.sum_int(List.append(xs, ys)) == List.sum_int(xs) + List.sum_int(ys)"

let need_sum = "    need_eq(List.sum_int(xs) + List.sum_int(ys), List.sum_int(List.append(xs, ys)))\n"

let assert_by =
  [ gated "assert P by a lemma call: P is proved, then assumed" (fun () ->
        let out =
          run
            (prog
               ("  fn go(xs : List(Int), ys : List(Int)) : Int do\n    assert " ^ sum_goal
              ^ " by List.sum_int_append(xs, ys)\n" ^ need_sum ^ "  end\n"))
        in
        expect out ~line:11 ~callee:"assert" "proved";
        expect out ~line:12 ~callee:"need_eq" "proved");
    gated "assert P by do … end: the block's facts prove P" (fun () ->
        let out =
          run
            (prog
               ("  fn go(xs : List(Int), ys : List(Int)) : Int do\n    assert " ^ sum_goal
              ^ " by do\n      List.sum_int_append(xs, ys)\n    end\n" ^ need_sum ^ "  end\n"))
        in
        expect out ~line:11 ~callee:"assert" "proved";
        expect out ~line:14 ~callee:"need_eq" "proved");
    gated "a hint's facts do not leak past the assert" (fun () ->
        (* The hint proves the sum law, but P is unrelated: afterwards only P
           is assumed, so the later call that needs the law is not proved. *)
        let out =
          run
            (prog
               ("  fn go(xs : List(Int), ys : List(Int)) : Int do\n\
                \    assert 1 == 1 by List.sum_int_append(xs, ys)\n" ^ need_sum ^ "  end\n"))
        in
        U.not_proved out ~line:12 ~callee:"need_eq");
    gated "an assert by that does not follow is not proved, and is not assumed" (fun () ->
        let out =
          run
            (prog
               "  fn go(xs : List(Int)) : Int do\n\
               \    assert List.sum_int(xs) == 7 by List.sum_int_append(xs, xs)\n\
               \    need_eq(7, List.sum_int(xs))\n\
               \  end\n")
        in
        U.not_proved out ~line:11 ~callee:"assert";
        U.not_proved out ~line:12 ~callee:"need_eq");
    gated "assert by is erased: the program runs without evaluating the hint" (fun () ->
        let out =
          run ~args:""
            ("mod H do\n  needs IO.Console\n  @[lemma]\n  fn boom(x : Int) : {Unit | x == x} do\n    ()\n  end\n\
             \  fn main(_c : Cap(IO.Console)) : Unit do\n    assert 1 == 1 by boom(3)\n    println(\"ran\")\n  end\nend\n")
        in
        if not (List.mem "ran" (List.map String.trim (U.lines out))) then Alcotest.failf "did not run:\n%s" out) ]

let reveal_fuel =
  [ gated "reveal f: an @[opaque] function's definition is used after it" (fun () ->
        let out =
          run
            (prog
               "  fn hidden() : Int do need4(dbl(2)) end\n\
               \  fn shown() : Int do\n\
               \    reveal dbl\n\
               \    need4(dbl(2))\n\
               \  end\n")
        in
        U.not_proved out ~line:10 ~callee:"need4";
        expect out ~line:13 ~callee:"need4" "proved");
    gated "reveal is scoped to its block" (fun () ->
        let out =
          run
            (prog
               "  fn shown() : Int do\n\
               \    let a = do\n\
               \      reveal dbl\n\
               \      need4(dbl(2))\n\
               \    end\n\
               \    a + need4(dbl(2))\n\
               \  end\n")
        in
        expect out ~line:13 ~callee:"need4" "proved";
        U.not_proved out ~line:15 ~callee:"need4");
    gated "with fuel(f, N): a deeper unfolding inside, the default outside" (fun () ->
        let out =
          run
            (prog
               "  fn shallow() : Int do need3(cnt(3)) end\n\
               \  fn deep() : Int do\n\
               \    with fuel(cnt, 5) do\n\
               \      need3(cnt(3))\n\
               \    end\n\
               \  end\n")
        in
        U.not_proved out ~line:10 ~callee:"need3";
        expect out ~line:13 ~callee:"need3" "proved");
    gated "with fuel keeps its body: the program still runs it" (fun () ->
        let out =
          run ~args:""
            "mod H do\n  needs IO.Console\n  fn main(_c : Cap(IO.Console)) : Unit do\n    with fuel(main, 3) do\n      println(\"body ran\")\n    end\n  end\nend\n"
        in
        if not (List.mem "body ran" (List.map String.trim (U.lines out))) then Alcotest.failf "body did not run:\n%s" out) ]

let calc =
  [ gated "calc: every step proved, the chain's conclusion assumed" (fun () ->
        let out =
          run
            (prog
               "  fn go(xs : List(Int), ys : List(Int)) : Int do\n\
               \    calc do\n\
               \      List.sum_int(List.append(xs, ys))\n\
               \      == List.sum_int(xs) + List.sum_int(ys) by List.sum_int_append(xs, ys)\n\
               \      == List.sum_int(ys) + List.sum_int(xs)\n\
               \    end\n\
               \    need_eq(List.sum_int(ys) + List.sum_int(xs), List.sum_int(List.append(xs, ys)))\n\
               \  end\n")
        in
        expect out ~line:13 ~callee:"calc step 1" "proved";
        expect out ~line:14 ~callee:"calc step 2" "proved";
        expect out ~line:16 ~callee:"need_eq" "proved");
    gated "calc: a step that does not follow is reported by its number, and nothing is assumed" (fun () ->
        let out =
          run
            (prog
               "  fn go(xs : List(Int), ys : List(Int)) : Int do\n\
               \    calc do\n\
               \      List.sum_int(List.append(xs, ys))\n\
               \      == List.sum_int(xs) + List.sum_int(ys) by List.sum_int_append(xs, ys)\n\
               \      == List.sum_int(xs) + List.sum_int(ys) + 1\n\
               \    end\n\
               \    need_eq(List.sum_int(xs) + List.sum_int(ys) + 1, List.sum_int(List.append(xs, ys)))\n\
               \  end\n")
        in
        expect out ~line:13 ~callee:"calc step 1" "proved";
        U.not_proved out ~line:14 ~callee:"calc step 2";
        U.not_proved out ~line:16 ~callee:"need_eq");
    gated "calc: <= after == gives <=, and the step's hint stays in its step" (fun () ->
        let out =
          run
            (prog
               "  fn go(n : {Int | _ >= 0}) : Int do\n\
               \    calc do\n\
               \      n + 1\n\
               \      == 1 + n\n\
               \      <= 1 + n + n\n\
               \    end\n\
               \    need_eq(1, 1)\n\
               \  end\n")
        in
        expect out ~line:13 ~callee:"calc step 1" "proved";
        expect out ~line:14 ~callee:"calc step 2" "proved") ]

let suite = assert_by @ reveal_fuel @ calc
