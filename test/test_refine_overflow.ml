(* Refinement reflection, phase 6: Int overflow
   (specs/2026-10-29-refinement-reflection-design.md §9.1 "Int overflow", §10
   "Phase 6", D8; the plan is
   specs/plans/2026-11-03-reflection-phase6-overflow-plan.md).

   Group `reflect-overflow`.  The logic's Int stays mathematical: `+ - *` and
   negation panic out of range, so they never return a value the logic
   disagrees with.  The one operator the logic knows that still wraps is `/`
   on the smallest Int by -1, which the checker now encodes exactly. *)

module U = Test_refine_unfold

let gated = U.gated
let run = U.run
let expect = U.expect
let not_proved = U.not_proved
let contains = U.contains
let lines = U.lines

let src =
  {|mod E do
  fn negm(x : Int) : Int do x / -1 end
  fn need_pos(y : {Int | _ > 0}) : Int do y end
  fn t1(x : {Int | _ < 0}) : Int do need_pos(negm(x)) end
  fn t2(x : {Int | _ < 0 && _ > -5}) : Int do need_pos(negm(x)) end
  fn t3(x : {Int | _ < 0}) : Int do need_pos(x / -1) end
  fn t4(x : {Int | _ < 0}, d : {Int | _ == -1}) : Int do need_pos(x / d) end
  fn half(x : Int) : Int do x / -2 end
  fn need_nn(y : {Int | _ >= 0}) : Int do y end
  fn t5(x : {Int | _ <= 0}) : Int do need_nn(half(x)) end
end
|}

let tests =
  [ gated "div_min_neg1: `x / -1` at the smallest Int is the smallest Int (RED: div-wrap-off)" (fun () ->
        (* At x = -2^62, `x / -1` returns -2^62 in both backends: `need_pos`
           would get a negative number.  On main `t1` was PROVED. *)
        let out = run src in
        not_proved out ~line:4 ~callee:"need_pos";
        not_proved out ~line:6 ~callee:"need_pos";
        not_proved out ~line:7 ~callee:"need_pos";
        let red = run ~env:"MARCH_REFLECT_PERTURB=div-wrap-off" src in
        expect red ~line:4 ~callee:"need_pos" "proved" ~uses:"negm");
    gated "div_away_from_the_edge: the other divisions prove as before" (fun () ->
        let out = run src in
        expect out ~line:5 ~callee:"need_pos" "proved" ~uses:"negm";
        expect out ~line:10 ~callee:"need_nn" "proved" ~uses:"half");
    gated "div_min_neg1 really wraps: the program returns the smallest Int" (fun () ->
        (* The fact the encoding rests on, pinned: if `/` ever starts to panic
           there instead, the special case can go (and this test says so). *)
        let ran =
          run ~args:""
            {|mod E do
  needs IO.Console
  fn negm(x : Int) : Int do x / -1 end
  fn main(_c : Cap(IO.Console)) do
    println(int_to_string(negm(0 - 4611686018427387903 - 1)))
  end
end
|}
        in
        if not (contains ran "-4611686018427387904") then Alcotest.failf "expected the wrapped value:\n%s" ran);
    gated "const_fold_overflow: a zero-argument function whose arithmetic overflows is no constant (review round 1)" (fun () ->
        (* `k3()` panics (`max * 3`) and `k2()` panics (`-min`).  The folder
           used OCaml's wrapped values (`max - 2`, `min`), so `need_gt(max)`
           and the lemma `k2() < 0` were PROVED. *)
        let src =
          {|mod K do
  fn lo() : Int do 0 - 4611686018427387903 - 1 end
  fn k2() : Int do -lo() end
  fn k3() : Int do 4611686018427387903 * 3 end
  fn need_gt(y : {Int | _ > k3()}) : Int do y end
  @[lemma]
  fn l(u : Int) : {Unit | k2() < 0} do () end
  fn t() : Int do need_gt(4611686018427387903) end
  fn ok() : Int do 4611686018427387903 - 1 end
  fn need_ok(y : {Int | _ > ok()}) : Int do y end
  fn t2() : Int do need_ok(4611686018427387903) end
end
|}
        in
        let out = run src in
        not_proved out ~line:8 ~callee:"need_gt";
        not_proved out ~line:7 ~callee:"l";
        expect out ~line:11 ~callee:"need_ok" "proved");
    gated "parity_div: negm agrees with the interpreter on the boundary inputs" (fun () ->
        let out = run ~args:"--check --reflect-parity" src in
        match
          List.find_map
            (fun l ->
              match String.split_on_char '\t' l with
              | "parity" :: _ :: "negm" :: st :: _ -> Some st
              | _ -> None)
            (lines out)
        with
        | Some st -> Alcotest.(check string) "negm" "agree" st
        | None -> Alcotest.failf "no parity row for negm:\n%s" out) ]
