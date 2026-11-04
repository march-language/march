(* Refinement reflection, phase 2: lemmas (specs/2026-10-29-refinement-reflection-design.md
   §4, §9.1's rows marked (2), §10 "Phase 2"; the plan is
   specs/plans/2026-11-02-reflection-phase2-lemmas-plan.md).

   Group `reflect-lemma`.  Every case drives the REAL compiler through
   [Test_refine_unfold]'s helpers (a private HOME and a fresh project
   directory per run). *)

module U = Test_refine_unfold

let gated = U.gated
let run = U.run
let contains = U.contains
let lines = U.lines

(* The [invalid_lemma] diagnostics of [out] whose text names [rule] ("L1".."L5")
   and [name]. *)
let invalid_lemma out ~name ~rule =
  List.exists
    (fun l -> contains l "[invalid_lemma]" && contains l ("(" ^ rule ^ ")") && contains l ("`" ^ name ^ "`"))
    (lines out)

let expect_invalid out ~name ~rule =
  if not (invalid_lemma out ~name ~rule) then
    Alcotest.failf "expected invalid_lemma (%s) on `%s`:\n%s" rule name out

let cat = U.cat

let console = "  needs IO.Console\n"

let noisy = {|  fn noisy(n : Int) : Int do
    println("x")
    n
  end
|}

let rules =
  [ gated "not_unit: a lemma whose result is not {Unit | P} is L1" (fun () ->
        let out = run ~args:"--check" "mod N do\n  @[lemma]\n  fn l(x : Int) : Int do x end\nend\n" in
        expect_invalid out ~name:"l" ~rule:"L1");
    gated "L1: a plain Unit result (no theorem) is L1" (fun () ->
        let out = run ~args:"--check" "mod N do\n  @[lemma]\n  fn l(x : Int) : Unit do () end\nend\n" in
        expect_invalid out ~name:"l" ~rule:"L1");
    gated "L1: a theorem mentioning the unit value is L1" (fun () ->
        let out =
          run ~args:"--check" "mod N do\n  @[lemma]\n  fn l(x : Int) : {Unit | _ == _} do () end\nend\n"
        in
        expect_invalid out ~name:"l" ~rule:"L1");
    gated "sound_lemma_panic: a lemma proved through panic is L2" (fun () ->
        let out =
          run ~args:"--check"
            "mod N do\n  @[lemma]\n  fn bogus(n : Int) : {Unit | n == n + 1} do panic(\"x\") end\nend\n"
        in
        expect_invalid out ~name:"bogus" ~rule:"L2");
    gated "L2: a lemma with an effect is L2" (fun () ->
        let out =
          run ~args:"--check"
            ("mod N do\n" ^ console
           ^ "  @[lemma]\n  fn l(n : Int) : {Unit | n == n} do\n    println(\"x\")\n    ()\n  end\nend\n")
        in
        expect_invalid out ~name:"l" ~rule:"L2");
    gated "L2: a static assert is allowed in a lemma" (fun () ->
        let out =
          run ~args:"--check"
            "mod N do\n  @[lemma]\n  fn l(n : Int) : {Unit | n == n} do\n    assert n == n\n    ()\n  end\nend\n"
        in
        if contains out "[invalid_lemma]" then Alcotest.failf "assert must not make a lemma invalid:\n%s" out);
    gated "l3_callee: a lemma calling a function that is not reflected is L3" (fun () ->
        let out =
          run ~args:"--check"
            ("mod N do\n" ^ console ^ noisy
           ^ "  @[lemma]\n  fn l(n : Int) : {Unit | n == n} do\n    let _ = noisy(n)\n    ()\n  end\nend\n")
        in
        expect_invalid out ~name:"l" ~rule:"L3");
    gated "lemma_as_value: a lemma named as a value is L5" (fun () ->
        let out =
          run ~args:"--check"
            ("mod N do\n" ^ cat
           ^ {|  @[lemma]
  fn cat_nil_left(ys : List(Int)) : {Unit | cat(Nil, ys) == ys} do () end
  fn g() : Int do
    let f = cat_nil_left
    0
  end
end
|})
        in
        expect_invalid out ~name:"cat_nil_left" ~rule:"L5");
    gated "lemma_attr_conflict: @[lemma] with @[opaque] or @[measure] is L5" (fun () ->
        let out =
          run ~args:"--check"
            "mod N do\n  @[lemma] @[opaque]\n  fn a(n : Int) : {Unit | n == n} do () end\n  @[lemma] @[measure]\n  fn b(n : Int) : {Unit | n == n} do () end\nend\n"
        in
        expect_invalid out ~name:"a" ~rule:"L5";
        expect_invalid out ~name:"b" ~rule:"L5");
    gated "sound_rebind_param: a lemma rebinding a parameter is L2, and its caller gets nothing (review F1)" (fun () ->
        (* `let n = 0` made the theorem `n == 0` read the new `n` at the tail:
           `l` was admitted and `need0(k)` proved, while `f(5)` passes 5. *)
        let out =
          run
            {|mod N do
  @[lemma]
  fn l(n : Int) : {Unit | n == 0} do
    let n = 0
    ()
  end
  fn need0(x : {Int | _ == 0}) : Int do x end
  fn f(k : Int) : Int do
    l(k)
    need0(k)
  end
end
|}
        in
        expect_invalid out ~name:"l" ~rule:"L2";
        U.not_proved out ~line:10 ~callee:"need0");
    gated "sound_rebind_pattern: an inner pattern rebinding a parameter is L2 (review F1)" (fun () ->
        let out =
          run ~args:"--check"
            ("mod N do\n" ^ cat
           ^ {|  @[lemma]
  fn l(xs : List(Int)) : {Unit | cat(xs, Nil) == Nil} do
    match xs do
      Nil -> ()
      Cons(_, xs) ->
        match xs do
          Nil -> ()
          Cons(_, _) -> ()
        end
    end
  end
end
|})
        in
        expect_invalid out ~name:"l" ~rule:"L2");
    gated "lemma_ok: a well-formed lemma is neither invalid nor an unknown attribute" (fun () ->
        let out =
          run ~args:"--check"
            ("mod N do\n" ^ cat
           ^ "  @[lemma]\n  fn cat_nil_left(ys : List(Int)) : {Unit | cat(Nil, ys) == ys} do () end\nend\n")
        in
        if contains out "[invalid_lemma]" || contains out "[unknown_attribute]" then
          Alcotest.failf "cat_nil_left must be accepted:\n%s" out) ]

let unproved out name =
  List.exists (fun l -> contains l "[lemma_unproved]" && contains l ("`" ^ name ^ "`")) (lines out)

let expect_unproved out name =
  if not (unproved out name) then Alcotest.failf "expected lemma_unproved on `%s`:\n%s" name out

(* The lemma is reported false: a confirmed counterexample (the solver's
   model, run in the interpreter), [refinement_violated] at the lemma. *)
let refuted out name =
  List.exists
    (fun l -> contains l "[refinement_violated]" && contains l ("the lemma `" ^ name ^ "` is false"))
    (lines out)

let expect_refuted out name ~at =
  if not (refuted out name && contains out ("does not hold at " ^ at)) then
    Alcotest.failf "expected `%s` refuted at %s:\n%s" name at out;
  if unproved out name then Alcotest.failf "a refuted lemma is not also merely unproved:\n%s" out

(* Admitted: no lemma_unproved or invalid_lemma, at least one theorem row,
   and every theorem row proved (a lemma that was never walked has none). *)
let expect_admitted out name =
  let rows =
    List.filter_map
      (fun l ->
        match String.split_on_char '\t' l with
        | v :: "user" :: _ :: "postcondition" :: c :: _ when c = name -> Some v
        | "skip" :: "user" :: _ :: _ :: "postcondition" :: c :: _ when c = name -> Some "skip"
        | _ -> None)
      (lines out)
  in
  if unproved out name || invalid_lemma out ~name ~rule:"L" || rows = [] || List.exists (( <> ) "proved") rows then
    Alcotest.failf "`%s` must be proved:\n%s" name out

(* Line numbers below count from 1 at `mod N do`; [cat] is lines 2-7. *)
let posts =
  [ gated "cat_nil_left: a non-recursive lemma's closed {Unit | P} post is proved" (fun () ->
        let out =
          run ("mod N do\n" ^ cat
             ^ "  @[lemma]\n  fn cat_nil_left(ys : List(Int)) : {Unit | cat(Nil, ys) == ys} do\n    ()\n  end\nend\n")
        in
        U.expect out ~line:10 ~callee:"cat_nil_left" "proved" ~uses:"cat";
        expect_admitted out "cat_nil_left";
        if contains out "[unused_binding]" then Alcotest.failf "a lemma's parameter is used by its theorem:\n%s" out);
    gated "assert_static: an unprovable static assert is not assumed (I5)" (fun () ->
        let src body =
          "mod N do\n" ^ cat
          ^ "  @[lemma]\n  fn l(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do\n" ^ body ^ "    ()\n  end\nend\n"
        in
        let out = run (src "    assert cat(xs, Nil) == xs\n") in
        U.expect out ~line:10 ~callee:"assert" "skip:reflect-fuel";
        U.not_proved out ~line:11 ~callee:"l";
        expect_unproved out "l";
        let out = run (src "") in
        U.not_proved out ~line:10 ~callee:"l";
        expect_unproved out "l");
    gated "sound_assert_false: `assert false` in a lemma proves nothing" (fun () ->
        let out =
          run "mod N do\n  @[lemma]\n  fn l(n : Int) : {Unit | false} do\n    assert false\n    ()\n  end\nend\n"
        in
        U.not_proved out ~line:5 ~callee:"l";
        expect_unproved out "l");
    gated "sound_domain: an unfolding outside the refined domain proves nothing" (fun () ->
        (* As phase 1's sound_domain (test_refine_unfold.ml): a metric-certified
           `p` is not unfolded, so the guard is exercised by the non-recursive
           `pos`, whose unfolding holds only under `n >= 0`. *)
        let out =
          run
            {|mod N do
  fn pos(n : {Int | _ >= 0}) : Int do n end
  @[lemma]
  fn bad(n : Int) : {Unit | pos(0 - 1) == 0 - 1 || n == n + 1} do
    ()
  end
  @[lemma]
  fn ok() : {Unit | pos(1) == 1} do
    ()
  end
end
|}
        in
        U.not_proved out ~line:5 ~callee:"bad";
        expect_unproved out "bad";
        U.expect out ~line:9 ~callee:"ok" "proved" ~uses:"pos";
        expect_admitted out "ok");
    gated "known_overflow: `inc(n) > n` proves (D8: Int is mathematical; a known gap)" (fun () ->
        (* A KNOWN GAP, pinned on purpose (§9.1): at the maximum Int, `inc`
           overflows at run time.  The Int-overflow phase must flip this test. *)
        let out =
          run
            "mod N do\n  fn inc(n : Int) : Int do n + 1 end\n  @[lemma]\n  fn l(n : Int) : {Unit | inc(n) > n} do\n    ()\n  end\nend\n"
        in
        U.expect out ~line:5 ~callee:"l" "proved" ~uses:"inc");
    gated "assert_runtime: an assert outside a lemma keeps today's meaning" (fun () ->
        let out =
          run
            {|mod N do
  fn need(x : {Int | _ > 0}) : Int do x end
  fn f(k : Int) : Int do
    assert k > 0
    need(k)
  end
end
|}
        in
        U.expect out ~line:5 ~callee:"need" "proved";
        if List.exists (fun l -> contains l "\tassertion\t") (lines out) then
          Alcotest.failf "a runtime assert files no Assertion obligation:\n%s" out);
    gated "unit_post_ordinary: a non-lemma {Unit | P} return keeps today's skip" (fun () ->
        let out = run "mod N do\n  fn f() : {Unit | false} do\n    ()\n  end\nend\n" in
        U.expect out ~line:2 ~callee:"f" "skip:unreflectable-subject") ]

(* §4.6's functions and lemmas, polymorphic.  [defs4_6] is lines 2-14 of a
   module that starts `mod N do`. *)
let defs4_6 =
  {|  fn cat(xs : List(a), ys : List(a)) : List(a) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end
  fn rev(xs : List(a)) : List(a) do
    match xs do
      Nil -> Nil
      Cons(h, t) -> cat(rev(t), Cons(h, Nil))
    end
  end
  fn need_eq(a : List(a), b : {List(a) | _ == a}) : Int do 0 end
|}

let cat_nil =
  {|  @[lemma]
  fn cat_nil(xs : List(a)) : {Unit | cat(xs, Nil) == xs} do
    match xs do
      Nil -> ()
      Cons(_, t) -> cat_nil(t)
    end
  end
|}

let cat_assoc =
  {|  @[lemma]
  fn cat_assoc(xs : List(a), ys : List(a), zs : List(a)) : {Unit | cat(cat(xs, ys), zs) == cat(xs, cat(ys, zs))} do
    match xs do
      Nil -> ()
      Cons(_, t) -> cat_assoc(t, ys, zs)
    end
  end
|}

let rev_cat =
  {|  @[lemma]
  fn rev_cat(xs : List(a), ys : List(a)) : {Unit | rev(cat(xs, ys)) == cat(rev(ys), rev(xs))} do
    match xs do
      Nil ->
        cat_nil(rev(ys))
      Cons(h, t) ->
        rev_cat(t, ys)
        cat_assoc(rev(ys), rev(t), Cons(h, Nil))
    end
  end
|}

let rev_rev ~asserts =
  {|  @[lemma]
  fn rev_rev(xs : List(a)) : {Unit | rev(rev(xs)) == xs} do
    match xs do
      Nil -> ()
      Cons(h, t) ->
        rev_rev(t)
        rev_cat(rev(t), Cons(h, Nil))
|}
  ^ (if asserts then
       {|        assert rev(Nil) == Nil
        assert cat(Nil, Cons(h, Nil)) == Cons(h, Nil)
        assert rev(Cons(h, Nil)) == Cons(h, Nil)
        assert cat(Nil, t) == t
        assert cat(Cons(h, Nil), t) == Cons(h, t)
|}
     else "        ()\n")
  ^ "    end\n  end\n"

let lemma_line out name =
  List.find_map
    (fun l ->
      match String.split_on_char '\t' l with
      | v :: "user" :: _ :: "postcondition" :: c :: _ when c = name -> Some v
      | "skip" :: "user" :: _ :: r :: "postcondition" :: c :: _ when c = name -> Some ("skip:" ^ r)
      | _ -> None)
    (lines out)

let calls =
  [ gated "pre_lemma: an unproved hypothesis withholds the fact (lemma_unproved_call)" (fun () ->
        let out =
          run
            {|mod N do
  fn dbl(n : Int) : Int do n + n end
  @[lemma]
  fn nn(n : {Int | _ >= 0}) : {Unit | dbl(n) >= 0} do
    ()
  end
  fn need_nn(x : {Int | _ >= 0}) : Int do x end
  fn f(k : Int) : Int do
    nn(k)
    need_nn(dbl(k))
  end
  fn g(k : Int) : Int do
    if k >= 0 do
      nn(k)
      need_nn(dbl(k))
    else
      0
    end
  end
end
|}
        in
        expect_admitted out "nn";
        if not (List.exists (fun l -> contains l "[lemma_unproved_call]" && contains l "`nn`") (lines out)) then
          Alcotest.failf "expected lemma_unproved_call at f's call:\n%s" out;
        U.not_proved out ~line:10 ~callee:"need_nn";
        U.expect out ~line:15 ~callee:"need_nn" "proved");
    gated "cat_nil: a structurally recursive lemma is proved through its IH" (fun () ->
        let out = run ("mod N do\n" ^ defs4_6 ^ cat_nil ^ "end\n") in
        expect_admitted out "cat_nil";
        if lemma_line out "cat_nil" = None then Alcotest.failf "no cat_nil row:\n%s" out);
    gated "lemma fact: after cat_nil(xs), cat(xs, Nil) == xs is known; without it, it is not" (fun () ->
        let src call =
          "mod N do\n" ^ defs4_6 ^ cat_nil ^ "  fn f(xs : List(Int)) : Int do\n" ^ call
          ^ "    need_eq(xs, cat(xs, Nil))\n  end\nend\n"
        in
        (* defs4_6: 13 lines (2-14), cat_nil: 7 (15-21), f at 22. *)
        let out = run (src "    cat_nil(xs)\n") in
        U.expect out ~line:24 ~callee:"need_eq" "proved";
        let out = run (src "") in
        U.not_proved out ~line:23 ~callee:"need_eq");
    gated "lemma_scope: a lemma fact does not leak out of its branch" (fun () ->
        let out =
          run
            ("mod N do\n" ^ defs4_6 ^ cat_nil
           ^ {|  fn f(xs : List(Int), c : Bool) : Int do
    let r = if c do
      cat_nil(xs)
      need_eq(xs, cat(xs, Nil))
    else
      0
    end
    need_eq(xs, cat(xs, Nil))
  end
end
|})
        in
        U.expect out ~line:25 ~callee:"need_eq" "proved";
        U.not_proved out ~line:29 ~callee:"need_eq");
    gated "cat_assoc, rev_cat, rev_rev (§4.6): lemmas calling lemmas, with assert steps" (fun () ->
        let out = run ("mod N do\n" ^ defs4_6 ^ cat_nil ^ cat_assoc ^ rev_cat ^ rev_rev ~asserts:true ^ "end\n") in
        List.iter (expect_admitted out) [ "cat_nil"; "cat_assoc"; "rev_cat"; "rev_rev" ]);
    gated "rev_rev_short (phase 4): without the asserts, decided steps finish rev_rev" (fun () ->
        (* Phase 2 needed the five asserts (single unfolding: lemma_unproved);
           phase 4's decided second step supplies them.  `@[reflect(fuel: 1)]`
           on `rev` and `cat` brings back the phase-2 verdict ([fuel_lower]). *)
        let out = run ("mod N do\n" ^ defs4_6 ^ cat_nil ^ cat_assoc ^ rev_cat ^ rev_rev ~asserts:false ^ "end\n") in
        List.iter (expect_admitted out) [ "cat_nil"; "cat_assoc"; "rev_cat"; "rev_rev" ]);
    gated "sound_eq_float: a lemma's logical == does not become program == at Float (C3)" (fun () ->
        let out =
          run
            ("mod N do\n" ^ defs4_6 ^ cat_nil ^ cat_assoc ^ rev_cat ^ rev_rev ~asserts:true
           ^ {|  fn same(a : List(Float), b : List(Float)) : Bool do a == b end
  fn need_true(b : {Bool | _ == true}) : Int do 0 end
  fn f(xs : List(Float)) : Int do
    rev_rev(xs)
    need_true(same(rev(rev(xs)), xs))
  end
  fn g(xs : List(Float)) : Int do
    rev_rev(xs)
    need_eq(xs, rev(rev(xs)))
  end
end
|})
        in
        (* 13 + 7 + 7 + 11 + 14 = 52 lines of definitions after `mod N do`:
           same at 54, f's need_true at 57, g's need_eq at 61. *)
        U.not_proved out ~line:57 ~callee:"need_true";
        U.expect out ~line:61 ~callee:"need_eq" "proved") ]

let l4 =
  [ gated "sound_lemma_ih: a lemma recursing on itself with no metric is L4" (fun () ->
        let out = run ~args:"--check" "mod N do\n  @[lemma]\n  fn bad(n : Int) : {Unit | false} do\n    bad(n)\n  end\nend\n" in
        expect_invalid out ~name:"bad" ~rule:"L4");
    gated "sound_lemma_ih: an exit the metric cannot use is L4; a good exit proves" (fun () ->
        let out =
          run ~args:"--check"
            "mod N do\n  @[lemma]\n  fn bad2(n : Int) : {Unit | n < 0} do\n    if n == 0 do () else bad2(n - 1) end\n  end\nend\n"
        in
        if not (invalid_lemma out ~name:"bad2" ~rule:"L4" || unproved out "bad2" || refuted out "bad2") then
          Alcotest.failf "bad2 must be invalid (L4), unproved or refuted:\n%s" out;
        let out =
          run
            "mod N do\n  @[lemma]\n  fn good(n : Int) : {Unit | n <= 0 || n > 0} do\n    if n <= 0 do () else good(n - 1) end\n  end\nend\n"
        in
        expect_admitted out "good");
    gated "ih_pre_unproved: a recursive call whose precondition fails gives no IH (TERM rule (a))" (fun () ->
        (* The theorem needs induction; the recursive call `l(t)` cannot meet
           `len(_) >= 2` when `len(xs) == 2`, so no hypothesis is available.
           Control: with `len(_) >= 0` the same proof goes through. *)
        let src pre =
          "mod N do\n" ^ cat
          ^ Printf.sprintf
              {|  @[lemma]
  fn l(xs : {List(Int) | len(_) >= %d}) : {Unit | cat(xs, Nil) == xs} do
    match xs do
      Nil -> ()
      Cons(_, t) -> l(t)
    end
  end
end
|}
              pre
        in
        let out = run (src 2) in
        expect_unproved out "l";
        let out = run (src 0) in
        expect_admitted out "l") ]

(* ── Erasure (§4.5) ─────────────────────────────────────────────────────── *)

let in_dir src f =
  let dir = Filename.temp_dir "lemma_erase" "" in
  Fun.protect ~finally:(fun () -> try U.remove_tree dir with _ -> ()) (fun () ->
      Out_channel.with_open_bin (Filename.concat dir "m.march") (fun oc -> output_string oc src);
      f dir)

let sh dir cmd =
  let out = Filename.temp_file "lemma_erase" ".out" in
  let full =
    Printf.sprintf "cd %s && HOME=%s %s > %s 2>&1" (Filename.quote dir) (Filename.quote (Lazy.force U.home)) cmd
      (Filename.quote out)
  in
  ignore (Test_helpers.Sys.command full);
  let s = In_channel.with_open_bin out In_channel.input_all in
  Sys.remove out;
  s

let march () = Filename.quote (U.exe ())

(* The program's stdout under [mode]: the interpreter, `--jit`, or a compiled
   binary.  [env] prefixes the compiler's command. *)
let output ?(env = "") mode src =
  in_dir src (fun dir ->
      match mode with
      | `Interp -> sh dir (Printf.sprintf "%s %s m.march" env (march ()))
      | `Jit -> sh dir (Printf.sprintf "%s %s --jit m.march" env (march ()))
      | `Compiled ->
        let log = sh dir (Printf.sprintf "%s %s --compile -o prog m.march" env (march ())) in
        if not (Sys.file_exists (Filename.concat dir "prog")) then Alcotest.failf "compile failed:\n%s" log;
        sh dir "./prog")

let ll src =
  in_dir src (fun dir ->
      let log = sh dir (Printf.sprintf "%s --emit-llvm m.march" (march ())) in
      let f = Filename.concat dir "m.ll" in
      if not (Sys.file_exists f) then Alcotest.failf "no m.ll:\n%s" log;
      In_channel.with_open_bin f In_channel.input_all)

(* A program with lemmas, and the same program with every lemma line and
   lemma call blanked (line numbers kept, so spans agree). *)
let erase_src ~lemmas =
  let l s = if lemmas then s else "" in
  String.concat "\n"
    [ "mod Main do";
      "  needs IO.Console";
      "  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do";
      "    match xs do";
      "      Nil -> ys";
      "      Cons(h, t) -> Cons(h, cat(t, ys))";
      "    end";
      "  end";
      l "  @[lemma]";
      l "  fn cat_nil(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do";
      l "    match xs do";
      l "      Nil -> ()";
      l "      Cons(_, t) -> cat_nil(t)";
      l "    end";
      l "  end";
      "  fn main(_cap : Cap(IO.Console)) do";
      "    let xs = Cons(1, Cons(2, Nil))";
      l "    cat_nil(xs)";
      "    println(int_to_string(List.length(cat(xs, Nil))))";
      "  end";
      "end";
      "" ]

let erase =
  [ gated "erase_runtime: interpreted, compiled and JIT output equal the lemma-free program's" (fun () ->
        List.iter
          (fun mode ->
            let a = output mode (erase_src ~lemmas:true) and b = output mode (erase_src ~lemmas:false) in
            if a <> b || not (contains a "2") then Alcotest.failf "outputs differ:\n--with--\n%s\n--without--\n%s" a b)
          [ `Interp; `Compiled; `Jit ]);
    gated "sound_erase_ir: --emit-llvm is byte-identical with and without the lemmas" (fun () ->
        let a = ll (erase_src ~lemmas:true) and b = ll (erase_src ~lemmas:false) in
        if a <> b then Alcotest.fail "the .ll differs";
        if contains a "cat_nil" then Alcotest.fail "the lemma's symbol is in the .ll");
    gated "sound_erase_paths: a lemma body never runs, with reflection off and z3 off PATH" (fun () ->
        (* With reflection off the assert below is merely unproved, so the
           program compiles; were the body run, the assert would abort it. *)
        let src =
          {|mod Main do
  needs IO.Console
  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end
  @[lemma]
  fn boom(xs : List(Int)) : {Unit | cat(xs, xs) == xs} do
    assert cat(xs, xs) == xs
    ()
  end
  fn main(_cap : Cap(IO.Console)) do
    boom(Cons(1, Nil))
    println("ran")
  end
end
|}
        in
        List.iter
          (fun mode ->
            let out = output ~env:"MARCH_REFLECT=0 PATH=/usr/bin:/bin" mode src in
            if not (contains out "ran") || contains out "ssert" then
              Alcotest.failf "the lemma body ran or the program failed:\n%s" out)
          [ `Interp; `Compiled; `Jit ]);
    gated "erase_args: an impure lemma argument is lemma_argument_impure" (fun () ->
        let out =
          run ~args:"--check"
            ({|mod N do
  needs IO.Console
|} ^ "  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do\n    match xs do\n      Nil -> ys\n      Cons(h, t) -> Cons(h, cat(t, ys))\n    end\n  end\n"
            ^ {|  @[lemma]
  fn cat_nil(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do
    match xs do
      Nil -> ()
      Cons(_, t) -> cat_nil(t)
    end
  end
  fn noisy_list() : List(Int) do
    println("x")
    Nil
  end
  fn f() : Int do
    cat_nil(noisy_list())
    0
  end
  fn g(xs : List(Int)) : Int do
    cat_nil(cat(xs, Cons(1, Nil)))
    0
  end
end
|})
        in
        if U.count_code out "lemma_argument_impure" <> 1 then
          Alcotest.failf "expected exactly one lemma_argument_impure (f's, not g's):\n%s" out);
    gated "erase_qualified_builtin: a lemma named like a qualified builtin keeps its calls (review F2)" (fun () ->
        let src ~lemma =
          "mod N do\n  needs IO.Console\n"
          ^ (if lemma then "  @[lemma]\n  fn which_children(n : Int) : {Unit | n == n} do () end\n" else "\n\n")
          ^ "  fn main(_cap : Cap(IO.Console)) do\n    let kids = Supervisor.which_children(:nope)\n    println(int_to_string(List.length(kids)))\n  end\nend\n"
        in
        let a = output `Interp (src ~lemma:true) and b = output `Interp (src ~lemma:false) in
        let last s = match List.rev (lines s) with l :: _ -> String.trim l | [] -> "" in
        if last a <> "0" || last b <> "0" || contains a "panic" then
          Alcotest.failf "the builtin call must survive erasure:\n--with--\n%s\n--without--\n%s" a b);
    gated "lemma_shadow: a non-lemma sharing a lemma's name keeps its calls" (fun () ->
        let src =
          {|mod Main do
  needs IO.Console
  mod A do
    @[lemma]
    fn l(n : Int) : {Unit | n + 0 == n} do
      ()
    end
  end
  mod B do
    needs IO.Console
    fn l(n : Int) : Unit do
      println("B.l ran")
    end
  end
  fn main(_cap : Cap(IO.Console)) do
    A.l(1)
    B.l(2)
  end
end
|}
        in
        List.iter
          (fun mode ->
            let out = output mode src in
            if not (contains out "B.l ran") then Alcotest.failf "B.l must still run:\n%s" out)
          [ `Interp; `Compiled ]) ]

(* ── Lemma tests (`--lemma-test`, specs/todos/2026-11-02-lemma-uses-beyond-refinement.md
   ideas 1, 2 and 10) ──────────────────────────────────────────────────── *)

let count_fn =
  {|  fn count(xs : List(a)) : Int do
    match xs do
      Nil -> 0
      Cons(_, t) -> 1 + count(t)
    end
  end
|}

(* True, but needs induction its empty body does not give: unproved. *)
let count_cat =
  {|  @[lemma]
  fn count_cat(xs : List(a), ys : List(a)) : {Unit | count(cat(xs, ys)) == count(xs) + count(ys)} do
    ()
  end
|}

(* The `lemma-test` row of [name]: (status, detail). *)
let lemma_test_row out name =
  List.find_map
    (fun l ->
      match String.split_on_char '\t' l with
      | [ "lemma-test"; _; n; status; detail ] when n = name -> Some (status, detail)
      | _ -> None)
    (lines out)

let expect_row out name ~status ~detail =
  match lemma_test_row out name with
  | Some (s, d) when s = status && contains d detail -> ()
  | _ -> Alcotest.failf "expected lemma-test %s %s (%s):\n%s" name status detail out

let red out = List.exists (fun l -> String.starts_with ~prefix:"lemma-test: RED" l) (lines out)

let lemma_tests =
  [ gated "lemma_test_counterexample: an unproved, false lemma gets a concrete counterexample (idea 1)" (fun () ->
        (* `count(xs) <= 2` needs three unfoldings to refute, so z3 leaves it
           unproved; the generated inputs include a longer list. *)
        let out =
          run ~args:"--check --lemma-test"
            ("mod N do\n" ^ count_fn ^ "  @[lemma]\n  fn short(xs : List(a)) : {Unit | count(xs) <= 2} do\n    ()\n  end\nend\n")
        in
        expect_row out "short" ~status:"COUNTEREXAMPLE" ~detail:"the theorem is false at xs = Cons(";
        if not (red out) then Alcotest.failf "a counterexample makes the run RED:\n%s" out);
    gated "lemma_test_tested: an unproved, true lemma is \"tested, not proved\" (idea 1)" (fun () ->
        let out = run ~args:"--check --lemma-test" ("mod N do\n" ^ defs4_6 ^ count_fn ^ count_cat ^ "end\n") in
        expect_row out "count_cat" ~status:"tested" ~detail:"tested, not proved: ";
        if red out then Alcotest.failf "a true unproved lemma is not RED:\n%s" out);
    gated "lemma_test_refined_param: an input outside a parameter's refinement is no input" (fun () ->
        (* Without the precondition filter, n = -1 would be a counterexample. *)
        let out =
          run ~args:"--check --lemma-test"
            ("mod N do\n" ^ count_fn
           ^ "  fn twice(n : Int) : Int do n + n end\n  @[lemma]\n  fn nn(n : {Int | _ >= 0}, xs : List(Int)) : {Unit | twice(n) >= n + count(xs) - count(xs)} do\n    ()\n  end\nend\n")
        in
        (match lemma_test_row out "nn" with
         | Some (("tested" | "holds"), _) -> ()
         | _ -> Alcotest.failf "nn holds on every input inside its refinement:\n%s" out);
        if red out then Alcotest.failf "no counterexample inside the refinement:\n%s" out);
    gated "lemma_test_admitted: a proved lemma is re-checked in the interpreter and a compiled program (idea 2)" (fun () ->
        let out =
          run ~args:"--check --lemma-test" ("mod N do\n" ^ defs4_6 ^ cat_nil ^ cat_assoc ^ rev_cat ^ "end\n")
        in
        List.iter
          (fun n -> expect_row out n ~status:"holds" ~detail:" compiled")
          [ "cat_nil"; "cat_assoc"; "rev_cat" ];
        if red out then Alcotest.failf "true proved lemmas are not RED:\n%s" out);
    gated "lemma_test_miscompile_red: a proved law false in either backend is RED (perturbed, idea 2)" (fun () ->
        let src = "mod N do\n" ^ defs4_6 ^ cat_nil ^ "end\n" in
        let out = run ~env:"MARCH_LEMMA_TEST_PERTURB=interp" ~args:"--check --lemma-test" src in
        expect_row out "cat_nil" ~status:"FALSE" ~detail:"false in the interpreter";
        if not (red out) then Alcotest.failf "interpreter-false is RED:\n%s" out;
        let out = run ~env:"MARCH_LEMMA_TEST_PERTURB=compiled" ~args:"--check --lemma-test" src in
        expect_row out "cat_nil" ~status:"COMPILED-FALSE" ~detail:"false in the compiled program";
        if not (red out) then Alcotest.failf "compiled-false is RED:\n%s" out);
    gated "lemma_test_erased: a lemma test leaves the compiled program lemma-free" (fun () ->
        (* The harness is a separate program; the user's own build still
           erases every lemma (sound_erase_ir pins the IR). *)
        let out = run ~args:"--check" ("mod N do\n" ^ defs4_6 ^ cat_nil ^ "end\n") in
        if contains out "lemma-test" then Alcotest.failf "no lemma test without the flag:\n%s" out);
    gated "lemma_refuted: a theorem false at some input is refinement_violated, with the input" (fun () ->
        (* Both are false at n = -1 and true at n >= 0, so `¬P` is not valid and
           the definite-failure rule alone skipped them as `lemma_unproved`.
           `twice` is a reflected call: its model comes from stage 2. *)
        let out =
          run
            "mod N do\n  fn twice(n : Int) : Int do n + n end\n  @[lemma]\n  fn nn(n : Int) : {Unit | twice(n) >= n} do\n    ()\n  end\n  @[lemma]\n  fn mm(n : Int) : {Unit | n + n >= n} do\n    ()\n  end\nend\n"
        in
        expect_refuted out "nn" ~at:"n = -";
        expect_refuted out "mm" ~at:"n = -";
        (* A refuted lemma is not admitted: its callers get no fact from it.
           `need_nn(k)` after `mm(k)` must not be proved (k = -1 refutes it). *)
        let out =
          run
            "mod N do\n  fn need_nn(n : {Int | _ + _ >= _}) : Int do n end\n  @[lemma]\n  fn mm(n : Int) : {Unit | n + n >= n} do\n    ()\n  end\n  fn f(k : Int) : Int do\n    mm(k)\n    need_nn(k)\n  end\nend\n"
        in
        expect_refuted out "mm" ~at:"n = -";
        U.not_proved out ~line:9 ~callee:"need_nn";
        (* Control: true but needing induction stays unproved, not refuted. *)
        let out = run ("mod N do\n" ^ defs4_6 ^ count_fn ^ count_cat ^ "end\n") in
        expect_unproved out "count_cat";
        if refuted out "count_cat" then Alcotest.failf "a true lemma is never refuted:\n%s" out;
        (* A refined parameter: the model must satisfy it to count. *)
        let out =
          run
            "mod N do\n  @[lemma]\n  fn pos_ok(n : {Int | _ >= 0}) : {Unit | n + n >= n} do\n    ()\n  end\nend\n"
        in
        if refuted out "pos_ok" then Alcotest.failf "no counterexample inside the refinement:\n%s" out);
    gated "verified_unproved: in a `cap verified` module an unproved lemma is an error (idea 10)" (fun () ->
        let src cap = "mod N do\n" ^ cap ^ defs4_6 ^ count_fn ^ count_cat ^ "end\n" in
        let out = run (src "  cap verified\n") in
        if
          not
            (List.exists
               (fun l -> contains l "[lemma_unproved]" && contains l "`count_cat`")
               (lines out)
            && contains out "-- REFINEMENT ")
        then Alcotest.failf "an unproved lemma in a verified module is an error:\n%s" out;
        let out = run (src "") in
        expect_unproved out "count_cat";
        if contains out "-- REFINEMENT " then Alcotest.failf "outside `cap verified` it is a warning:\n%s" out) ]

(* ── Interface laws (idea 6): an interface's `@[lemma]` signature is one lemma
   per impl, over copies of the impl's methods ([Interface_laws]) ──────── *)

(* The lemma-def status ("admitted" / "unproved") of the generated lemma
   [name], from `--reflect-deps`. *)
let lemma_def_status out name =
  List.find_map
    (fun l ->
      match String.split_on_char '\t' l with
      | [ "lemma-def"; _; q; h ] when q = name || String.ends_with ~suffix:("." ^ name) q -> (
        match List.rev (String.split_on_char ':' h) with s :: _ -> Some s | [] -> None)
      | _ -> None)
    (lines out)

let expect_status out name status =
  match lemma_def_status out name with
  | Some s when s = status -> ()
  | s -> Alcotest.failf "expected `%s` %s, got %s:\n%s" name status (Option.value ~default:"no row" s) out

let monoid =
  {|  interface Monoid(a) do
    fn combine : a -> a -> a
    @[lemma]
    fn combine_assoc(x : a, y : a, z : a) : {Unit | combine(combine(x, y), z) == combine(x, combine(y, z))}
  end
  impl Monoid(Int) do
    fn combine(x, y) do x + y end
  end
|}

let joinable ~proof =
  {|  interface Joinable(a) do
    fn join : a -> a -> a
    fn none : a -> a
    @[lemma]
    fn join_none(x : a) : {Unit | join(x, none(x)) == x}
  end
  impl Joinable(List(a)) do
    fn join(xs, ys) do
      match xs do
        Nil -> ys
        Cons(h, t) -> Cons(h, join(t, ys))
      end
    end
    fn none(_xs) do Nil end
|}
  ^ (if proof then
       {|    @[lemma]
    fn join_none(xs) do
      match xs do
        Nil -> ()
        Cons(_, t) -> join_none(t)
      end
    end
|}
     else "")
  ^ "  end\n"

let iface_laws =
  [ gated "iface_law_proved: a law an impl satisfies is admitted for that impl" (fun () ->
        let out = run ~args:"--check --reflect-deps" ("mod N do\n" ^ monoid ^ "end\n") in
        expect_status out "combine_assoc__Monoid_Int" "admitted";
        if contains out "-- REFINEMENT " || contains out "[lemma_unproved]" then
          Alcotest.failf "a satisfied law draws nothing:\n%s" out);
    gated "iface_law_refuted: an impl that breaks a law is refinement_violated, with an input" (fun () ->
        let out =
          run ~args:"--check --reflect-deps"
            ("mod N do\n" ^ monoid
           ^ "  type Box = Box(Int)\n  impl Monoid(Box) do\n    fn combine(p, q) do\n      match p do\n        Box(a) -> match q do\n          Box(b) -> Box(a - b)\n        end\n      end\n    end\n  end\nend\n")
        in
        expect_refuted out "combine_assoc__Monoid_Box" ~at:"x = Box(";
        (* The message reads the theorem as written, not the generated names. *)
        if not (contains out "its theorem `combine(combine(x, y), z) == combine(x, combine(y, z))`") then
          Alcotest.failf "the theorem prints as written:\n%s" out;
        expect_status out "combine_assoc__Monoid_Box" "unproved";
        expect_status out "combine_assoc__Monoid_Int" "admitted");
    gated "iface_law_proof: an impl's own `@[lemma]` of the law's name is its proof" (fun () ->
        let out = run ~args:"--check --reflect-deps" ("mod N do\n" ^ joinable ~proof:true ^ "end\n") in
        expect_status out "join_none__Joinable_List_a" "admitted";
        (* Without the proof the law needs induction it does not get. *)
        let out = run ~args:"--check --reflect-deps" ("mod N do\n" ^ joinable ~proof:false ^ "end\n") in
        expect_unproved out "join_none__Joinable_List_a";
        expect_status out "join_none__Joinable_List_a" "unproved");
    gated "iface_law_verified: under `cap verified` an unproved law is an error" (fun () ->
        let out = run ~args:"--check" ("mod N do\n  cap verified\n" ^ joinable ~proof:false ^ "end\n") in
        if not (unproved out "join_none__Joinable_List_a" && contains out "-- REFINEMENT ") then
          Alcotest.failf "an unproved law in a verified module is an error:\n%s" out);
    gated "iface_law_lemma_test: `--lemma-test` tests each impl's law" (fun () ->
        let out = run ~args:"--check --lemma-test" ("mod N do\n" ^ joinable ~proof:false ^ "end\n") in
        expect_row out "join_none__Joinable_List_a" ~status:"tested" ~detail:"tested, not proved: ";
        (* A proved law is also run compiled, through the real impl: its
           theorem as written in the interface, at the impl's type. *)
        let src = "mod N do\n" ^ monoid ^ "end\n" in
        let out = run ~args:"--check --lemma-test" src in
        expect_row out "combine_assoc__Monoid_Int" ~status:"holds" ~detail:" compiled";
        let out = run ~env:"MARCH_LEMMA_TEST_PERTURB=compiled" ~args:"--check --lemma-test" src in
        expect_row out "combine_assoc__Monoid_Int" ~status:"COMPILED-FALSE" ~detail:"false in the compiled program");
    gated "iface_law_erased: laws and the method copies never run" (fun () ->
        let src =
          "mod N do\n  needs IO.Console\n" ^ joinable ~proof:true
          ^ "  fn main(_cap : Cap(IO.Console)) do\n    println(int_to_string(List.length(join([1, 2], [3]))))\n  end\nend\n"
        in
        List.iter
          (fun mode ->
            let out = output mode src in
            match List.rev (lines out) with
            | l :: _ when String.trim l = "3" -> ()
            | _ -> Alcotest.failf "the program prints 3:\n%s" out)
          [ `Interp; `Compiled ];
        let ir = ll src in
        if contains ir "__law_" || contains ir "join_none" then Alcotest.fail "the law's code reaches the IR");
    gated "iface_law_cross_file: an impl of an interface declared in another file is checked" (fun () ->
        let algebra =
          "mod Algebra do\n  interface Monoid(a) do\n    fn combine : a -> a -> a\n    @[lemma]\n    fn combine_assoc(x : a, y : a, z : a) : {Unit | combine(combine(x, y), z) == combine(x, combine(y, z))}\n  end\nend\n"
        in
        let out =
          U.run_lib ~args:"--check --reflect-deps" ~lib:[ ("algebra.march", algebra) ]
            "mod Main do\n  use Algebra.*\n  type Box = Box(Int)\n  impl Monoid(Int) do\n    fn combine(x, y) do x + y end\n  end\n  impl Monoid(Box) do\n    fn combine(p, q) do\n      match p do\n        Box(a) -> match q do\n          Box(b) -> Box(a - b)\n        end\n      end\n    end\n  end\nend\n"
        in
        expect_status out "combine_assoc__Monoid_Int" "admitted";
        expect_refuted out "combine_assoc__Monoid_Box" ~at:"x = Box(");
    gated "iface_law_default_unit: a default method, and a method called with `()`" (fun () ->
        let sem =
          "  interface Sem(a) do\n    fn combine : a -> a -> a\n    fn twice : a -> a do\n      fn x -> combine(x, x)\n    end\n    fn unit : Unit -> a\n    @[lemma]\n    fn twice_def(x : a) : {Unit | twice(x) == combine(x, x)}\n    @[lemma]\n    fn unit_left(x : a) : {Unit | combine(unit(()), x) == x}\n  end\n"
        in
        let impl = "  impl Sem(Int) do\n    fn combine(x, y) do x + y end\n    fn unit(_u) do 0 end\n  end\n" in
        let out = run ~args:"--check --reflect-deps" ("mod N do\n" ^ sem ^ impl ^ "end\n") in
        expect_status out "twice_def__Sem_Int" "admitted";
        expect_status out "unit_left__Sem_Int" "admitted";
        (* The impl in another file: the default is not injected there. *)
        let out =
          U.run_lib ~args:"--check --reflect-deps" ~lib:[ ("alg.march", "mod Alg do\n" ^ sem ^ "end\n") ]
            ("mod Main do\n  use Alg.*\n" ^ impl ^ "end\n")
        in
        expect_status out "twice_def__Sem_Int" "admitted";
        expect_status out "unit_left__Sem_Int" "admitted");
    gated "conflated_type: a parameter type that shares a stdlib type's name is named in the warning" (fun () ->
        (* `Tree` is also `OrderedMap.Tree`: the logic cannot tell them apart,
           so `k` cannot be used, and the warning says why (it used to say
           "not a measure or known predicate"). *)
        let src ty =
          Printf.sprintf
            "mod N do\n  type %s = Leaf | Node(%s, Int, %s)\n  fn k(t : %s) : Int do\n    match t do\n      Leaf -> 0\n      Node(_, _, _) -> 1\n    end\n  end\n  @[lemma]\n  fn l(t : %s) : {Unit | k(t) >= 0} do\n    ()\n  end\nend\n"
            ty ty ty ty ty
        in
        let out = run ~args:"--check --reflect-deps" (src "Tree") in
        if not (contains out "its parameter type `Tree` has the same name as a type declared in" && contains out "`OrderedMap`") then
          Alcotest.failf "expected the name-clash warning:\n%s" out;
        if contains out "is not a measure or known predicate" then Alcotest.failf "not the generic warning:\n%s" out;
        (* Renamed, the same lemma proves. *)
        let out = run ~args:"--check --reflect-deps" (src "Bush") in
        expect_status out "l" "admitted");
    gated "iface_law_syntax: a body-less interface `fn` must be a `@[lemma]`" (fun () ->
        let out =
          run ~args:"--check"
            "mod N do\n  interface I(a) do\n    @[opaque]\n    fn l(x : a) : {Unit | x == x}\n  end\nend\n"
        in
        if not (contains out "An interface can declare laws") then
          Alcotest.failf "expected the law-syntax error:\n%s" out) ]
