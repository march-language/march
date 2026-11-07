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

(* The whole-branch review's findings (2026-11-06). *)
let review =
  [ gated "C1: an assert inside a hint is proved, never assumed" (fun () ->
        let out =
          run
            (prog
               "  fn c1(x : Int) : Int do\n\
               \    assert x == 3 by do\n\
               \      assert x == 3\n\
               \    end\n\
               \    need3(x)\n\
               \  end\n")
        in
        U.not_proved out ~line:11 ~callee:"assert";
        U.not_proved out ~line:14 ~callee:"need3");
    gated "C2: a let inside a hint shadows; a fact about the inner name is not about the outer" (fun () ->
        let out =
          run
            (prog
               "  @[lemma]\n\
               \  fn is3(n : {Int | _ == 3}) : {Unit | n == 3} do () end\n\
               \  fn c2(x : Int) : Int do\n\
               \    assert x == 3 by do\n\
               \      let x = 3\n\
               \      is3(x)\n\
               \    end\n\
               \    need3(x)\n\
               \  end\n")
        in
        U.not_proved out ~line:13 ~callee:"assert";
        U.not_proved out ~line:17 ~callee:"need3");
    gated "I2: an assert by that is a whole body, or in a branch, is still checked" (fun () ->
        let out =
          run
            (prog
               ("  fn whole(xs : List(Int), ys : List(Int)) : Unit do assert " ^ sum_goal
              ^ " by List.sum_int_append(xs, ys) end\n\
                 \  fn branch(x : Int) : Int do\n\
                 \    if x > 0 do assert x == 7 by unit() else () end\n\
                 \    0\n\
                 \  end\n"))
        in
        expect out ~line:10 ~callee:"assert" "proved";
        U.not_proved out ~line:12 ~callee:"assert");
    gated "I3: a recursive call in a with-fuel body keeps its tail position" (fun () ->
        let out =
          run
            (prog
               "  @[decreases(n)]\n\
               \  fn spin(n : {Int | _ >= 0}) : Int do\n\
               \    if n == 0 do 0 else\n\
               \      with fuel(cnt, 2) do\n\
               \        spin(n - 1)\n\
               \      end\n\
               \    end\n\
               \  end\n")
        in
        if contains out "Function `spin`" then Alcotest.failf "spin flagged as non-tail:\n%s" out);
    gated "reveal and with fuel take a qualified name" (fun () ->
        let out =
          run
            "mod Q do\n\
             \  fn need4(x : {Int | _ == 4}) : Int do x end\n\
             \  mod Inner do\n\
             \    @[opaque]\n\
             \    fn dbl(x : Int) : Int do x + x end\n\
             \  end\n\
             \  fn shown() : Int do\n\
             \    reveal Inner.dbl\n\
             \    need4(Inner.dbl(2))\n\
             \  end\n\
             end\n"
        in
        expect out ~line:9 ~callee:"need4" "proved");
    gated "I1: march fmt keeps every proof statement and its output parses" (fun () ->
        let src =
          "mod F do\n\
           \  @[opaque]\n\
           \  fn dbl(x : Int) : Int do x + x end\n\
           \  fn go(xs : List(Int), ys : List(Int)) : Int do\n\
           \    assert 1 == 1 by do\n\
           \      let n = 2\n\
           \      assert n == 2\n\
           \    end\n\
           \    assert 2 == 2 by do\n\
           \      assert 1 == 1\n\
           \    end\n\
           \    reveal dbl\n\
           \    with fuel(dbl, 4) do\n\
           \      let y = dbl(2)\n\
           \      y\n\
           \    end\n\
           \    with fuel(dbl, 3) do\n\
           \      dbl(1)\n\
           \    end\n\
           \    calc do\n\
           \      List.sum_int(List.append(xs, ys))\n\
           \      == List.sum_int(xs) + List.sum_int(ys) by List.sum_int_append(xs, ys)\n\
           \      <= List.sum_int(xs) + List.sum_int(ys) + 0 by do\n\
           \        assert 0 == 0\n\
           \      end\n\
           \    end\n\
           \    0\n\
           \  end\n\
           end\n"
        in
        let dir = Filename.temp_dir "fmtproof" "" in
        let f = Filename.concat dir "m.march" in
        Out_channel.with_open_bin f (fun oc -> output_string oc src);
        ignore (U.run_in ~dir "fmt" "m.march");
        let formatted = In_channel.with_open_bin f In_channel.input_all in
        List.iter
          (fun frag -> if not (contains formatted frag) then Alcotest.failf "lost %S:\n%s" frag formatted)
          [ "let n = 2"; "assert n == 2"; "reveal dbl"; "with fuel(dbl, 4) do"; "let y = dbl(2)";
            "with fuel(dbl, 3) do"; "calc do"; "by List.sum_int_append(xs, ys)"; "assert 0 == 0" ];
        if contains formatted "..." then Alcotest.failf "elided code:\n%s" formatted;
        let out = U.run_in ~dir "--check" "m.march" in
        if U.has_code out "syntax_error" then Alcotest.failf "formatted output does not parse:\n%s\n%s" formatted out) ]

let suite = assert_by @ reveal_fuel @ calc @ review
