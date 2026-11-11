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
    gated "known_overflow, flipped on purpose (phase 6): `inc(n) > n` proves, and is sound by the trap" (fun () ->
        (* Phase 6 (D8) ruled the logic's Int stays mathematical: since 0.7.0
           `+` panics on overflow, so `inc` never RETURNS a value that breaks
           the lemma.  Until phase 6 this was pinned as a known gap; now the
           test also shows the program stops at the largest Int instead of
           returning (the interpreter here; the compiled trap has its own
           parity tests, specs/progress/2026-10-30-int-overflow-trap.md). *)
        let out =
          run
            "mod N do\n  fn inc(n : Int) : Int do n + 1 end\n  @[lemma]\n  fn l(n : Int) : {Unit | inc(n) > n} do\n    ()\n  end\nend\n"
        in
        U.expect out ~line:5 ~callee:"l" "proved" ~uses:"inc";
        let ran =
          run ~args:""
            ("mod N do\n" ^ console
           ^ "  fn inc(n : Int) : Int do n + 1 end\n\
             \  fn main(_c : Cap(IO.Console)) do\n    println(int_to_string(inc(4611686018427387903)))\n  end\nend\n")
        in
        if not (contains ran "attempt to add with overflow") then
          Alcotest.failf "inc at the largest Int must panic, not return:\n%s" ran;
        if contains ran "-4611686018427387904" then Alcotest.failf "inc wrapped:\n%s" ran);
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
  Test_helpers.seed_vc_cache dir;
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
        (* The program's own line, not the last one: dynamic supervisors are
           interpreter-only, so every mode now also warns [cap_unchecked]
           (ocap phase 3) after it. *)
        let printed_zero s = List.exists (fun l -> String.trim l = "0") (lines s) in
        if not (printed_zero a) || not (printed_zero b) || contains a "panic" then
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
      ()
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
        (* `Tree(k, v)` is also `OrderedMap.Tree(k, v)`, at the same arity: the
           typechecker conflates the two, so the logic cannot tell them apart,
           `k` cannot be used, and the warning says why (it used to say "not a
           measure or known predicate").  At ANOTHER arity (`type Tree`, no
           parameter) the two are told apart since 2026-11-06, so it proves. *)
        let src ~decl ~ty =
          Printf.sprintf
            "mod N do\n  type %s = Leaf | Node(%s, Int, %s)\n  fn k(t : %s) : Int do\n    match t do\n      Leaf -> 0\n      Node(_, _, _) -> 1\n    end\n  end\n  @[lemma]\n  fn l(t : %s) : {Unit | k(t) >= 0} do\n    ()\n  end\nend\n"
            decl ty ty ty ty
        in
        let out = run ~args:"--check --reflect-deps" (src ~decl:"Tree(a, b)" ~ty:"Tree(Int, Int)") in
        if not (contains out "its parameter type `Tree` has the same name as a type declared in" && contains out "`OrderedMap`") then
          Alcotest.failf "expected the name-clash warning:\n%s" out;
        if contains out "is not a measure or known predicate" then Alcotest.failf "not the generic warning:\n%s" out;
        (* Another arity, and renamed: the same lemma proves. *)
        expect_status (run ~args:"--check --reflect-deps" (src ~decl:"Tree" ~ty:"Tree")) "l" "admitted";
        let out = run ~args:"--check --reflect-deps" (src ~decl:"Bush" ~ty:"Bush") in
        expect_status out "l" "admitted");
    gated "iface_law_syntax: a body-less interface `fn` must be a `@[lemma]`" (fun () ->
        let out =
          run ~args:"--check"
            "mod N do\n  interface I(a) do\n    @[opaque]\n    fn l(x : a) : {Unit | x == x}\n  end\nend\n"
        in
        if not (contains out "An interface can declare laws") then
          Alcotest.failf "expected the law-syntax error:\n%s" out) ]

(* A refined parameter whose predicate calls a reflected function is the
   lemma's hypothesis (todo 2026-11-04-lemma-hypothesis-reflected-call-not-assumed):
   `fn h(g : {G | okz(_)}) : {Unit | okz(g)}` used to be `lemma_unproved`
   (skip reflect-fuel), its hypothesis never assumed. *)
let hyp_defs =
  {|  type G = GEnd | GMsg(Int, G)
  fn okz(g : G) : Bool do
    match g do
      GEnd -> true
      GMsg(s, k) -> s == 0 && okz(k)
    end
  end
  fn cnt(g : G) : Int do
    match g do
      GEnd -> 0
      GMsg(s, k) -> s + cnt(k)
    end
  end
|}

(* The design's P1 probe.  Its names carry a `p1_`/`P1` prefix: the stdlib's
   Session.Theory declares `project`, `dual`, `binary`, `Local` and `Global`,
   and a user declaration named like a stdlib one is not yet resolved inside
   a predicate (lemmas design §6, G2). *)
let project_dual_src =
  {|  type P1Local = LEnd | LSend(Int, P1Local) | LRecv(Int, P1Local) | LChoose(Int, P1Local, Int, P1Local) | LOffer(Int, P1Local, Int, P1Local) | LRec(P1Local) | LVar(Int)

  fn p1_dual(l : P1Local) : P1Local do
    match l do
      LEnd -> LEnd
      LSend(t, k) -> LRecv(t, p1_dual(k))
      LRecv(t, k) -> LSend(t, p1_dual(k))
      LChoose(a, x, b, y) -> LOffer(a, p1_dual(x), b, p1_dual(y))
      LOffer(a, x, b, y) -> LChoose(a, p1_dual(x), b, p1_dual(y))
      LRec(k) -> LRec(p1_dual(k))
      LVar(i) -> LVar(i)
    end
  end

  @[lemma]
  fn p1_dual_dual(l : P1Local) : {Unit | p1_dual(p1_dual(l)) == l} do
    match l do
      LEnd -> ()
      LSend(_, k) -> p1_dual_dual(k)
      LRecv(_, k) -> p1_dual_dual(k)
      LChoose(_, x, _, y) ->
        p1_dual_dual(x)
        p1_dual_dual(y)
      LOffer(_, x, _, y) ->
        p1_dual_dual(x)
        p1_dual_dual(y)
      LRec(k) -> p1_dual_dual(k)
      LVar(_) -> ()
    end
  end

  -- P1Global protocol, roles as Int
  type P1Global = GEnd | GMsg(Int, Int, Int, P1Global) | GChoice(Int, Int, P1Global, Int, P1Global) | GLoop(P1Global) | GVar(Int)

  fn p1_project(g : P1Global, r : Int) : P1Local do
    match g do
      GEnd -> LEnd
      GMsg(s, d, t, k) ->
        if s == r do LSend(t, p1_project(k, r))
        else if d == r do LRecv(t, p1_project(k, r))
        else p1_project(k, r) end end
      GChoice(c, a, x, b, y) ->
        if c == r do LChoose(a, p1_project(x, r), b, p1_project(y, r))
        else LOffer(a, p1_project(x, r), b, p1_project(y, r)) end
      GLoop(k) -> LRec(p1_project(k, r))
      GVar(i) -> LVar(i)
    end
  end

  -- every message and choice is between a and b
  fn p1_binary(g : P1Global, a : Int, b : Int) : Bool do
    match g do
      GEnd -> true
      GMsg(s, d, _, k) -> ((s == a && d == b) || (s == b && d == a)) && p1_binary(k, a, b)
      GChoice(c, _, x, _, y) -> (c == a || c == b) && p1_binary(x, a, b) && p1_binary(y, a, b)
      GLoop(k) -> p1_binary(k, a, b)
      GVar(_) -> true
    end
  end

  @[lemma]
  fn p1_project_dual(a : Int, b : {Int | _ != a}, g : {P1Global | p1_binary(_, a, b)}) : {Unit | p1_project(g, b) == p1_dual(p1_project(g, a))} do
    match g do
      GEnd -> ()
      GMsg(_, _, _, k) -> p1_project_dual(a, b, k)
      GChoice(_, _, x, _, y) ->
        p1_project_dual(a, b, x)
        p1_project_dual(a, b, y)
      GLoop(k) -> p1_project_dual(a, b, k)
      GVar(_) -> ()
    end
  end

|}

let hyp_mod body = "mod H do\n" ^ hyp_defs ^ body ^ "end\n"

let hypotheses =
  [ gated "hyp_reflected_call: a hypothesis that calls a reflected function is assumed" (fun () ->
        let out = run (hyp_mod "  @[lemma]\n  fn h4(g : {G | okz(_)}) : {Unit | okz(g)} do () end\n") in
        expect_admitted out "h4");
    gated "hyp_red_control: without the hypothesis the same theorem is not proved" (fun () ->
        let out = run (hyp_mod "  @[lemma]\n  fn h4n(g : G) : {Unit | okz(g)} do () end\n") in
        if not (unproved out "h4n" || refuted out "h4n") then
          Alcotest.failf "with no hypothesis okz(g) does not follow:\n%s" out);
    gated "hyp_spellings: the binder and the parameter's own name are the same hypothesis" (fun () ->
        let out =
          run
            (hyp_mod
               "  @[lemma]\n  fn hv(g : {v : G | okz(v)}) : {Unit | okz(g)} do () end\n  @[lemma]\n  fn hg(g : {G | okz(g)}) : {Unit | okz(g)} do () end\n")
        in
        expect_admitted out "hv";
        expect_admitted out "hg");
    gated "hyp_negated: a negated call is a hypothesis too" (fun () ->
        let out = run (hyp_mod "  @[lemma]\n  fn hn(g : {G | !okz(_)}) : {Unit | !okz(g)} do () end\n") in
        expect_admitted out "hn");
    gated "hyp_inductive: the hypothesis proves the recursive call's precondition and the step" (fun () ->
        let out =
          run
            (hyp_mod
               {|  @[lemma]
  fn okz_cnt(g : {G | okz(_)}) : {Unit | cnt(g) == 0} do
    match g do
      GEnd -> ()
      GMsg(_, k) -> okz_cnt(k)
    end
  end
|})
        in
        expect_admitted out "okz_cnt");
    gated "hyp_callee_spellings: a callee's `okz(_)`, `okz(v)` and `okz(g)` are one precondition in stage 2" (fun () ->
        let out =
          run
            (hyp_mod
               {|  fn need_u(g : {G | okz(_)}) : Int do 0 end
  fn need_v(g : {v : G | okz(v)}) : Int do 0 end
  fn need_g(g : {G | okz(g)}) : Int do 0 end
  @[lemma]
  fn lem(g : {G | okz(_)}) : {Unit | okz(g)} do
    match g do
      GEnd -> ()
      GMsg(s, k) ->
        let _ = need_u(k)
        let _ = need_v(k)
        let _ = need_g(k)
        ()
    end
  end
|})
        in
        List.iter
          (fun callee ->
            if
              not
                (List.exists
                   (fun l ->
                     match String.split_on_char '\t' l with
                     | "proved" :: "user" :: _ :: "precondition" :: c :: _ -> c = callee
                     | _ -> false)
                   (lines out))
            then Alcotest.failf "the precondition of %s at k is proved:\n%s" callee out)
          [ "need_u"; "need_v"; "need_g" ]);
    gated "hyp_project_dual: a binary protocol's projections are duals, from the hypothesis (design §2 P1)" (fun () ->
        let out = run ("mod P do\n" ^ project_dual_src ^ "end\n") in
        expect_admitted out "p1_project_dual";
        (* RED control: without `p1_binary(_, a, b)` the law is false (a third role's message). *)
        let weak = Str.global_replace (Str.regexp_string "g : {P1Global | p1_binary(_, a, b)})") "g : P1Global)" project_dual_src in
        let out2 = run ("mod P do\n" ^ weak ^ "end\n") in
        if not (unproved out2 "p1_project_dual" || refuted out2 "p1_project_dual") then
          Alcotest.failf "without the hypothesis project_dual is not proved:\n%s" out2);
    gated "hyp_caller_obliged: a caller must still establish the hypothesis" (fun () ->
        let out =
          run
            (hyp_mod
               {|  @[lemma]
  fn h4(g : {G | okz(_)}) : {Unit | okz(g)} do () end
  fn use_bad() : Int do
    h4(GMsg(1, GEnd))
    0
  end
|})
        in
        expect_admitted out "h4";
        if not (contains out "[refinement_violated]" || contains out "[lemma_unproved_call]") then
          Alcotest.failf "calling h4 on a value that breaks okz is reported:\n%s" out) ]

(* ── A lemma call gives its fact from any always-evaluated position ────────
   todo 2026-11-02-lemma-facts-from-non-statement-calls
   ([Refine_check.inner_lemma_facts]).  `cnt(l) >= 0` needs induction, so
   only the lemma's fact proves `need(cnt(l), _)`. *)
let pos_mod body =
  {|mod P do
  type L = Nil0 | C(Int, L)
  fn cnt(l : L) : Int do
    match l do
      Nil0 -> 0
      C(_, k) -> 1 + cnt(k)
    end
  end
  fn need(k : {Int | _ >= 0}, n : Int) : Int do k end
  @[lemma]
  fn cnt_nn(l : L) : {Unit | cnt(l) >= 0} do
    match l do
      Nil0 -> ()
      C(_, k) -> cnt_nn(k)
    end
  end
|}
  ^ body ^ "end\n"

(* The verdicts of the `need` preconditions in [out]. *)
let need_rows out =
  List.filter_map
    (fun l ->
      if contains l "\tprecondition\tneed\t" || contains l "\tprecondition\tneed" then
        match String.split_on_char '\t' l with s :: _ -> Some s | [] -> None
      else None)
    (lines out)

let lemma_positions =
  [ gated "pos_proved: a named `let`, a nested block, a tuple element and an `if` condition" (fun () ->
        let out =
          run
            (pos_mod
               {|  fn named_let(l : L) : Int do
    let u = cnt_nn(l)
    need(cnt(l), 0)
  end
  fn in_block(l : L) : Int do
    let x = do
      cnt_nn(l)
      1
    end
    need(cnt(l), x)
  end
  fn in_arg(l : L) : Int do
    let p = (cnt_nn(l), 3)
    need(cnt(l), 0)
  end
  fn in_cond(l : L) : Int do
    if do cnt_nn(l) true end do need(cnt(l), 0) else 0 end
  end
|})
        in
        let rows = need_rows out in
        if List.length rows <> 4 || List.exists (( <> ) "proved") rows then
          Alcotest.failf "want 4 proved `need` rows:\n%s" out);
    gated "pos_red: no fact from a branch, a lambda, a rebound name, `&&`'s right side, or no lemma" (fun () ->
        let out =
          run
            (pos_mod
               {|  fn base(l : L) : Int do
    need(cnt(l), 0)
  end
  fn in_branch(l : L, b : Bool) : Int do
    let y = if b do cnt_nn(l) else () end
    need(cnt(l), 0)
  end
  fn in_lambda(l : L) : Int do
    let f = fn x -> cnt_nn(l)
    need(cnt(l), 0)
  end
  fn rebound(l : L) : Int do
    let l2 = l
    let z = do
      let l = Nil0
      cnt_nn(l)
      1
    end
    need(cnt(l2), z)
  end
  fn short(l : L, b : Bool) : Int do
    let q = b && do cnt_nn(l) true end
    need(cnt(l), 0)
  end
|})
        in
        let rows = need_rows out in
        if List.length rows <> 5 || List.mem "proved" rows then
          Alcotest.failf "want 5 unproved `need` rows:\n%s" out) ]

(* ── A user name the stdlib also declares ─────────────────────────────────
   todo 2026-11-04-unreflectable-predicate-hides-name-clash: a user `fn
   unwrap` beside the prelude's resolves to the file's own (the typechecker's
   rule, [Refine_term]'s own-file preference); a user `Reply` beside
   `Channel.HandleResult`'s resolves by the reflected parameter's datatype. *)
let clash_mod body = "mod CL do\n" ^ body ^ "end\n"

let clash_unwrap = "  fn unwrap(x : Int) : Int do x + 1 end\n"

let clash_msg =
  "  type Msg = Reply(Int, Int) | Other\n  fn tag(m : Msg) : Int do\n    match m do\n      Reply(_, _) -> 1\n      Other -> 0\n    end\n  end\n"

let name_clashes =
  [ gated "clash_fn: a user `unwrap` is its own, not the prelude's" (fun () ->
        let out =
          run (clash_mod (clash_unwrap ^ "  @[lemma]\n  fn unwrap_gt(x : Int) : {Unit | unwrap(x) > x} do () end\n"))
        in
        expect_admitted out "unwrap_gt");
    gated "clash_fn_red: a false theorem about the user `unwrap` is not proved" (fun () ->
        let out =
          run (clash_mod (clash_unwrap ^ "  @[lemma]\n  fn unwrap_big(x : Int) : {Unit | unwrap(x) > x + 1} do () end\n"))
        in
        if not (unproved out "unwrap_big" || refuted out "unwrap_big") then
          Alcotest.failf "unwrap(x) > x + 1 is false:\n%s" out);
    gated "clash_ctor: a user `Reply` resolves by the parameter's datatype" (fun () ->
        let out =
          run (clash_mod (clash_msg ^ "  @[lemma]\n  fn tag_reply(c : Int, v : Int) : {Unit | tag(Reply(c, v)) == 1} do () end\n"))
        in
        expect_admitted out "tag_reply");
    gated "clash_ctor_red: a false theorem over the user `Reply` is not proved" (fun () ->
        let out =
          run (clash_mod (clash_msg ^ "  @[lemma]\n  fn tag_zero(c : Int, v : Int) : {Unit | tag(Reply(c, v)) == 0} do () end\n"))
        in
        if not (unproved out "tag_zero" || refuted out "tag_zero") then
          Alcotest.failf "tag(Reply(c, v)) == 0 is false:\n%s" out) ]

(* ── A `match` or `if` in a `let`'s right-hand side unfolds ───────────────
   todo 2026-10-31-reflection-encoder-gaps ("a `match` in a non-tail value
   position"): the block is translated once per case of the right-hand side
   ([Refine_reflect.tr_case]). *)
let let_match_src =
  {|mod LM do
  type Lq = Ez | Cz(Int, Lq)
  fn depth2(l : Lq) : Int do
    let a = if l == Ez do 0 else 1 end
    let b = match l do
      Ez -> 10
      Cz(x, _) -> x
    end
    a + b
  end
|}

let let_match =
  [ gated "let_match: a body whose `let`s branch unfolds per case" (fun () ->
        let out =
          run
            (let_match_src
           ^ "  @[lemma]\n  fn d_ez(u : Int) : {Unit | depth2(Ez) == 10} do () end\n  @[lemma]\n  fn d_cz(x : Int) : {Unit | depth2(Cz(x, Ez)) == x + 1} do () end\nend\n")
        in
        expect_admitted out "d_ez";
        expect_admitted out "d_cz");
    gated "let_match_red: a false theorem about it is not proved" (fun () ->
        let out = run (let_match_src ^ "  @[lemma]\n  fn d_bad(x : Int) : {Unit | depth2(Cz(x, Ez)) == x} do () end\nend\n") in
        if not (unproved out "d_bad" || refuted out "d_bad") then Alcotest.failf "d_bad is false:\n%s" out) ]

(* Reflection R4: a body dividing by a non-literal is reflected when the
   function's own parameter refinements and branch conditions show the
   divisor non-zero. *)
let div_src =
  {|mod DV do
  fn ratio(a : Int, b : {Int | _ != 0}) : Int do a / b end
  fn md(a : Int, b : {Int | _ > 0}) : Int do a % b end
  fn safe_div(a : Int, b : Int) : Int do
    if b == 0 do 0 else a / b end
  end
  fn bare(a : Int, b : Int) : Int do a / b end
|}

let div_nonliteral =
  [ gated "div_param: a divisor refined non-zero reflects" (fun () ->
        let out =
          run
            (div_src
           ^ "  @[lemma]\n  fn r6(u : Int) : {Unit | ratio(6, 2) == 3 && ratio(-7, 2) == -3} do () end\n  @[lemma]\n  fn m7(u : Int) : {Unit | md(-7, 2) == -1} do () end\nend\n")
        in
        expect_admitted out "r6";
        expect_admitted out "m7");
    gated "div_guard: a divisor guarded by `b == 0` reflects" (fun () ->
        let out =
          run
            (div_src
           ^ "  @[lemma]\n  fn s0(x : Int) : {Unit | safe_div(x, 0) == 0} do () end\n  @[lemma]\n  fn s7(u : Int) : {Unit | safe_div(7, -2) == -3} do () end\nend\n")
        in
        expect_admitted out "s0";
        expect_admitted out "s7");
    gated "div_red: an unguarded divisor and a false theorem do not prove" (fun () ->
        let out =
          run
            (div_src
           ^ "  @[lemma]\n  fn b6(u : Int) : {Unit | bare(6, 2) == 3} do () end\n  @[lemma]\n  fn s_bad(u : Int) : {Unit | safe_div(7, 2) == 4} do () end\nend\n")
        in
        if not (unproved out "b6" || refuted out "b6") then Alcotest.failf "bare divides by an unguarded b:\n%s" out;
        if not (unproved out "s_bad" || refuted out "s_bad") then Alcotest.failf "s_bad is false:\n%s" out) ]

(* `--lemma-test` decides a theorem over the logic's `len`, in the
   interpreter and in the compiled harness. *)
let lemma_test_len =
  [ gated "lemma_test_len: a `len` theorem is decided in both backends" (fun () ->
        let out =
          run ~args:"--check --lemma-test"
            ("mod N do\n" ^ defs4_6
           ^ "  @[lemma]\n  fn len_nil(ys : List(Int)) : {Unit | len(cat(Nil, ys)) == len(ys)} do () end\n  @[lemma]\n  fn len_cat(xs : List(Int), ys : List(Int)) : {Unit | len(cat(xs, ys)) == len(xs) + len(ys)} do () end\nend\n")
        in
        expect_row out "len_nil" ~status:"holds" ~detail:" compiled";
        (match lemma_test_row out "len_cat" with
         | Some (("tested" | "holds"), _) -> ()
         | _ -> Alcotest.failf "len_cat is decided:\n%s" out);
        if red out then Alcotest.failf "true lemmas are not RED:\n%s" out);
    gated "lemma_test_len_red: a false `len` theorem gets a counterexample" (fun () ->
        let out =
          run ~args:"--check --lemma-test"
            ("mod N do\n  @[lemma]\n  fn short(xs : List(Int)) : {Unit | len(xs) <= 2} do () end\nend\n")
        in
        expect_row out "short" ~status:"COUNTEREXAMPLE" ~detail:"xs = ";
        if not (red out) then Alcotest.failf "a counterexample makes the run RED:\n%s" out) ]

(* Reflection R2: a function certified by a metric (`@[decreases]`), which
   the walk decides after the encoder is built, is reflected. *)
let metric_src =
  {|mod MT do
  @[decreases(n)]
  @[reflect(fuel: 4)]
  fn down(n : {Int | _ >= 0}) : Int do
    if n == 0 do 0 else down(n - 1) + 1 end
  end
|}

let metric_cert =
  [ gated "metric_cert: a metric-certified function unfolds" (fun () ->
        let out = run (metric_src ^ "  @[lemma]\n  fn d3(u : Int) : {Unit | down(3) == 3} do () end\nend\n") in
        expect_admitted out "d3");
    gated "metric_cert_red: a false theorem about it, and one with no certificate, do not prove" (fun () ->
        let out = run (metric_src ^ "  @[lemma]\n  fn d_bad(u : Int) : {Unit | down(3) == 4} do () end\nend\n") in
        if not (unproved out "d_bad" || refuted out "d_bad") then Alcotest.failf "d_bad is false:\n%s" out;
        let spin =
          "mod SP do\n  @[decreases(n)]\n  fn spin(n : Int) : Int do\n    if n == 0 do 0 else spin(n - 1) + 1 end\n  end\n  @[lemma]\n  fn s1(u : Int) : {Unit | spin(1) == 1} do () end\nend\n"
        in
        let out = run spin in
        if not (unproved out "s1" || refuted out "s1") then Alcotest.failf "spin has no proved metric (n may be negative):\n%s" out) ]

(* A `match` in value position (an argument, an operand) unfolds as an
   if-then-else chain over its cases. *)
let match_value_src =
  {|mod MV do
  type Lq = Ez | Cz(Int, Lq)
  fn plus1(n : Int) : Int do n + 1 end
  fn sz(l : Lq) : Int do
    plus1(match l do
      Ez -> 0
      Cz(x, _) -> x
    end)
  end
  fn tw(l : Lq) : Int do
    2 * (match l do
      Ez -> 1
      Cz(_, Ez) -> 2
      Cz(_, _) -> 3
    end)
  end
|}

let match_value =
  [ gated "match_value: a `match` as an argument or operand unfolds" (fun () ->
        let out =
          run
            (match_value_src
           ^ "  @[lemma]\n  fn sz5(u : Int) : {Unit | sz(Cz(5, Ez)) == 6 && sz(Ez) == 1} do () end\n  @[lemma]\n  fn tw3(u : Int) : {Unit | tw(Ez) == 2 && tw(Cz(0, Ez)) == 4 && tw(Cz(0, Cz(1, Ez))) == 6} do () end\nend\n")
        in
        expect_admitted out "sz5";
        expect_admitted out "tw3");
    gated "match_value_red: a false theorem about it is not proved" (fun () ->
        let out = run (match_value_src ^ "  @[lemma]\n  fn tw_bad(u : Int) : {Unit | tw(Cz(0, Ez)) == 6} do () end\nend\n") in
        if not (unproved out "tw_bad" || refuted out "tw_bad") then Alcotest.failf "tw_bad is false:\n%s" out) ]

(* R4 by the solver: a divisor refinement the structural check cannot read
   (`b * b > 0` is `b != 0`) is decided by z3. *)
let div_solver =
  [ gated "div_solver: a nonlinear divisor refinement reflects through the solver" (fun () ->
        let out =
          run
            "mod DS do\n  fn sq(a : Int, b : {Int | b * b > 0}) : Int do a / b end\n  @[lemma]\n  fn sq6(u : Int) : {Unit | sq(6, 2) == 3} do () end\nend\n"
        in
        expect_admitted out "sq6");
    gated "div_solver_red: a refinement that allows zero does not" (fun () ->
        let out =
          run
            "mod DS do\n  fn sq(a : Int, b : {Int | b * b >= 0}) : Int do a / b end\n  @[lemma]\n  fn sq6(u : Int) : {Unit | sq(6, 2) == 3} do () end\nend\n"
        in
        if not (unproved out "sq6" || refuted out "sq6") then Alcotest.failf "b may be zero:\n%s" out) ]

(* A guard that calls a reflected function is unfolded so the call it
   guards can be decided. *)
let guard_call_src =
  {|mod GC do
  fn pos(n : Int) : Bool do n > 0 end
  fn sgn(n : Int) : Int do if pos(n) do 1 else 0 end end
  fn wrap(n : Int) : Int do sgn(n) + 1 end
|}

let guard_call =
  [ gated "guard_call: a guard's own call is unfolded to decide it" (fun () ->
        let out =
          run
            (guard_call_src
           ^ "  @[lemma]\n  fn w3(u : Int) : {Unit | wrap(3) == 2} do () end\n  @[lemma]\n  fn wv(x : {Int | _ > 0}) : {Unit | wrap(x) == 2} do () end\nend\n")
        in
        expect_admitted out "w3";
        expect_admitted out "wv");
    gated "guard_call_red: an undecided guard stays undecided" (fun () ->
        let out = run (guard_call_src ^ "  @[lemma]\n  fn wn(x : Int) : {Unit | wrap(x) == 2} do () end\nend\n") in
        if not (unproved out "wn" || refuted out "wn") then Alcotest.failf "wrap(0) is 1:\n%s" out) ]

(* Float (D9): a function over Floats reflects, every Float operation an
   opaque symbol.  What does not depend on a Float operation's value
   proves; what does (`f < 1.0` at 0.5) and IEEE equality (NaN) never do. *)
let float_body_src =
  {|mod FB do
  fn hk(f : Float) : Int do 3 end
  fn cls(f : Float, n : Int) : Int do if f < 0.0 do n else n end end
  fn twice(f : Float) : Float do f +. f end
  fn tk(f : Float) : Int do if twice(f) < 1.0 do 1 else 1 end end
  fn hk2(f : Float) : Int do if f < 1.0 do 1 else 2 end end
  fn same(a : Float, b : Float) : Bool do a == b end
|}

let float_body =
  [ gated "float_body: a function over Floats reflects" (fun () ->
        let out =
          run
            (float_body_src
           ^ "  @[lemma]\n  fn l_hk(u : Int) : {Unit | hk(1.0) == 3} do () end\n  @[lemma]\n  fn l_cls(f : Float) : {Unit | cls(f, 2) == 2} do () end\n  @[lemma]\n  fn l_tk(f : Float) : {Unit | tk(f) == 1} do () end\nend\n")
        in
        expect_admitted out "l_hk";
        expect_admitted out "l_cls";
        expect_admitted out "l_tk");
    gated "float_body_red: Float operations stay opaque, Float == is IEEE" (fun () ->
        let out =
          run
            (float_body_src
           ^ "  @[lemma]\n  fn l_hk2(u : Int) : {Unit | hk2(0.5) == 1} do () end\n  @[lemma]\n  fn l_same(f : Float) : {Unit | same(f, f)} do () end\n  @[lemma]\n  fn l_tw(f : Float) : {Unit | twice(f) == twice(f)} do () end\nend\n")
        in
        List.iter
          (fun l -> if not (unproved out l || refuted out l) then Alcotest.failf "%s must not prove:\n%s" l out)
          [ "l_hk2"; "l_same"; "l_tw" ]) ]

(* String (D9): the opaque `$Str` with its byte length; a literal is one
   constant per content, distinct from every other and shared with the
   predicate's own spelling of it. *)
let string_body_src =
  {|mod SB do
  fn greet(s : String) : Int do string_byte_length(s) + 1 end
  fn lit(n : Int) : String do if n > 0 do "pos" else "negative" end end
  fn tag(n : Int) : String do if n > 0 do "a" else "b" end end
  fn same(a : String, b : String) : Bool do a == b end
|}

let string_body =
  [ gated "string_body: a function over Strings reflects" (fun () ->
        let out =
          run
            (string_body_src
           ^ "  @[lemma]\n  fn l_greet(s : String) : {Unit | greet(s) > 0} do () end\n  @[lemma]\n  fn l_lit(u : Int) : {Unit | lit(1) != lit(0) && len(lit(0)) == 8} do () end\n  @[lemma]\n  fn l_tag(u : Int) : {Unit | tag(1) != tag(0) && tag(1) == \"a\"} do () end\n  @[lemma]\n  fn l_same(s : String) : {Unit | same(s, s)} do () end\nend\n")
        in
        expect_admitted out "l_greet";
        expect_admitted out "l_lit";
        expect_admitted out "l_tag";
        expect_admitted out "l_same");
    gated "string_body_red: a false theorem about a literal is not proved" (fun () ->
        let out =
          run
            (string_body_src
           ^ "  @[lemma]\n  fn l_bad(u : Int) : {Unit | tag(1) == tag(0)} do () end\n  @[lemma]\n  fn l_bad2(u : Int) : {Unit | tag(1) == \"b\"} do () end\n  @[lemma]\n  fn l_bad3(u : Int) : {Unit | len(lit(1)) == 8} do () end\nend\n")
        in
        List.iter
          (fun l -> if not (unproved out l || refuted out l) then Alcotest.failf "%s must not prove:\n%s" l out)
          [ "l_bad"; "l_bad2"; "l_bad3" ]) ]

(* Records (§3.2): the declared record sort.  Field access is its selector,
   a literal and an update its one constructor, a record pattern (in a
   `match` or a `let`) its selectors. *)
let record_body_src =
  {|mod RB do
  type Pt = { x : Int, y : Int }
  fn px(p : Pt) : Int do p.x + p.y end
  fn mk(n : Int) : Pt do { x: n, y: n + 1 } end
  fn bump(p : Pt) : Pt do { p with x: p.x + 10 } end
  fn sx(p : Pt) : Int do
    let { x, y } = p
    x - y
  end
  fn mx(p : Pt) : Int do match p do { x, y } -> x * 2 + y end end
|}

let record_body =
  [ gated "record_body: functions over a record reflect" (fun () ->
        let out =
          run
            (record_body_src
           ^ "  @[lemma]\n  fn l_px(u : Int) : {Unit | px(mk(2)) == 5 && px({ x: 1, y: 2 }) == 3} do () end\n  @[lemma]\n  fn l_bump(n : Int) : {Unit | px(bump(mk(n))) == 2 * n + 11} do () end\n  @[lemma]\n  fn l_sx(n : Int) : {Unit | sx(mk(n)) == 0 - 1} do () end\n  @[lemma]\n  fn l_mx(u : Int) : {Unit | mx(mk(1)) == 4} do () end\nend\n")
        in
        List.iter (expect_admitted out) [ "l_px"; "l_bump"; "l_sx"; "l_mx" ]);
    gated "record_body_red: an update that drops a field's value is not proved" (fun () ->
        let out = run (record_body_src ^ "  @[lemma]\n  fn l_bad(n : Int) : {Unit | px(bump(mk(n))) == 2 * n + 1} do () end\nend\n") in
        if not (unproved out "l_bad" || refuted out "l_bad") then Alcotest.failf "l_bad is false:\n%s" out) ]

(* A record or variant with a String or Float field (todo
   2026-11-08-reflect-records-with-string-fields).  Such fields were declared
   at the opaque `Elem` sort while reflection encodes a String at `$Str` and a
   Float at the FloatingPoint sort, so building one (`N(x, "v2")`) was a sort
   conflict and every lemma over the record an `unreflectable-predicate`
   skip; an actor whose state held a String could not prove its rollback round
   trip. *)
let scalar_fields_src =
  {|mod SF do
  type N = { a : Int, s : String }
  type F = { b : Int, f : Float }
  type Tag = Named(String, Int) | Anon(Int)
  fn mk(x : Int) : N do { a: x, s: "v2" } end
  fn un(n : N) : Int do n.a end
  fn label(n : N) : String do n.s end
  fn mkf(x : Int) : F do { b: x, f: 2.5 } end
  fn unf(r : F) : Int do r.b end
  fn named(x : Int) : Tag do Named("k", x) end
  fn num(t : Tag) : Int do
    match t do
      Named(_, n) -> n
      Anon(n) -> 0 - n
    end
  end
  fn rename(n : N, t : String) : N do { n with s: t } end
|}

let scalar_fields =
  [ gated "scalar_fields: records and variants with String and Float fields reflect" (fun () ->
        let out =
          run
            (scalar_fields_src
           ^ "  @[lemma]\n  fn l_un(x : Int) : {Unit | un(mk(x)) == x} do () end\n  @[lemma]\n  fn l_label(x : Int) : {Unit | label(mk(x)) == \"v2\"} do () end\n  @[lemma]\n  fn l_unf(x : Int) : {Unit | unf(mkf(x)) == x} do () end\n  @[lemma]\n  fn l_num(x : Int) : {Unit | num(named(x)) == x} do () end\n  @[lemma]\n  fn l_rename(x : Int, t : String) : {Unit | label(rename(mk(x), t)) == t && un(rename(mk(x), t)) == x} do () end\nend\n")
        in
        List.iter (expect_admitted out) [ "l_un"; "l_label"; "l_unf"; "l_num"; "l_rename" ]);
    gated "scalar_fields_red: false theorems over String and Float fields are not proved" (fun () ->
        let out =
          run
            (scalar_fields_src
           ^ "  @[lemma]\n  fn l_bad(x : Int) : {Unit | un(mk(x)) == x + 1} do () end\n  @[lemma]\n  fn l_bad2(x : Int) : {Unit | label(mk(x)) == \"v3\"} do () end\n  @[lemma]\n  fn l_bad3(x : Int) : {Unit | unf(mkf(x)) == 0} do () end\n  @[lemma]\n  fn l_bad4(x : Int, t : String) : {Unit | label(rename(mk(x), t)) == \"v2\"} do () end\nend\n")
        in
        List.iter
          (fun l -> if not (unproved out l || refuted out l) then Alcotest.failf "%s must not prove:\n%s" l out)
          [ "l_bad"; "l_bad2"; "l_bad3"; "l_bad4" ]);
    gated "scalar_fields_callsite: a call passing a record with a Float field is still checked" (fun () ->
        (* A Float at the record's Float field must not trip the float sort
           gate (it did once the field stopped being `Elem`). *)
        let out =
          run
            "mod SC do\n  type F = { b : Int, f : Float }\n  fn needf(r : {F | _.b > 0}) : Int do r.b end\n  fn go() : Int do needf({ b: 2, f: 1.5 }) end\n  fn bad() : Int do needf({ b: 0, f: 1.5 }) end\nend\n"
        in
        let row v line =
          List.exists
            (fun l -> String.starts_with ~prefix:(v ^ "\tuser\tm.march:" ^ line ^ ":") l && contains l "\tprecondition\t")
            (lines out)
        in
        if not (row "proved" "4" && row "violated" "5") then
          Alcotest.failf "expected proved at line 4 and violated at line 5:\n%s" out);
    gated "scalar_fields_order: no query declares a String-field datatype before `$Str`" (fun () ->
        (* A datatype with a String field names `$Str`; a query that declares
           it before `(declare-sort $Str 0)` is rejected by z3 (16 such
           queries in this program, stdlib ones included, before
           [Smt.hoist_string_decls]).  A cold cache, so every query is sent. *)
        let dir = Filename.temp_dir "scalar_fields" "" in
        Fun.protect ~finally:(fun () -> ignore (Sys.command ("rm -rf " ^ Filename.quote dir))) (fun () ->
            Out_channel.with_open_bin (Filename.concat dir "m.march") (fun oc ->
                output_string oc
                  (scalar_fields_src
                 ^ "  @[lemma]\n  fn l_un(x : Int) : {Unit | un(mk(x)) == x} do () end\n  fn need(u : {v : N | member(v.s, singleton(v.s))}) : Int do 0 end\n  fn ok() : Int do need({ a: 1, s: \"a\" }) end\nend\n"));
            let lg = Filename.concat dir "z3.log" in
            let out = U.run_in ~env:("MARCH_REFINE_Z3_LOG=" ^ Filename.quote lg) ~dir "--check --refine-report-sites=all" "m.march" in
            expect_admitted out "l_un";
            let log = In_channel.with_open_bin lg In_channel.input_all in
            if contains log "verdict: rejected" then
              Alcotest.failf "z3 rejected a query:\n%s"
                (String.concat "\n"
                   (List.filter (fun l -> contains l "declare-sort" || contains l "rejected") (String.split_on_char '\n' log)))) ) ]

(* Tuples (§3.2): one datatype per arity, its constructor and selectors; a
   tuple literal in a predicate at a tuple parameter is that constructor. *)
let tuple_body_src =
  {|mod TB do
  fn sw(t : (Int, Int)) : Int do match t do (a, b) -> a - b end end
  fn tl(n : Int) : Int do
    let (a, b) = (n, n + 1)
    a + b
  end
  fn pair(n : Int) : (Int, Int) do (n, n * 2) end
  fn fst2(t : (Int, Int)) : Int do
    let (a, _) = t
    a
  end
  fn mixed(t : (Int, Bool)) : Int do
    match t do
      (n, true) -> n
      (n, false) -> 0 - n
    end
  end
|}

let tuple_body =
  [ gated "tuple_body: functions over tuples reflect" (fun () ->
        let out =
          run
            (tuple_body_src
           ^ "  @[lemma]\n  fn l_sw(u : Int) : {Unit | sw((5, 2)) == 3} do () end\n  @[lemma]\n  fn l_tl(n : Int) : {Unit | tl(n) == 2 * n + 1} do () end\n  @[lemma]\n  fn l_pair(n : Int) : {Unit | sw(pair(n)) == 0 - n && fst2(pair(n)) == n} do () end\n  @[lemma]\n  fn l_mixed(u : Int) : {Unit | mixed((3, false)) == 0 - 3} do () end\nend\n")
        in
        List.iter (expect_admitted out) [ "l_sw"; "l_tl"; "l_pair"; "l_mixed" ]);
    gated "tuple_body_red: a false theorem about a tuple is not proved" (fun () ->
        let out =
          run
            (tuple_body_src
           ^ "  @[lemma]\n  fn l_bad(n : Int) : {Unit | sw(pair(n)) == n} do () end\n  @[lemma]\n  fn l_bad2(u : Int) : {Unit | mixed((3, true)) == 0 - 3} do () end\nend\n")
        in
        List.iter
          (fun l -> if not (unproved out l || refuted out l) then Alcotest.failf "%s must not prove:\n%s" l out)
          [ "l_bad"; "l_bad2" ]) ]

(* A derived `Eq` on a recursive type (todo 2026-11-06-derived-eq-recursive-type-unreflected):
   the derived `eq` recurses through `match (a, b) do (B(_, x), B(_, y)) -> x == y`, and a
   component bound through a tuple of parameters did not count as structurally smaller, so
   no function using `==` on the type was reflected.  (The todo's example names its type
   `T`, which `Crdt.T` also declares at the same arity: that clash is
   2026-11-03-reflect-type-name-clash-with-stdlib, so the test uses `Chain`.) *)
let reflect_row out name =
  List.find_map
    (fun l ->
      match String.split_on_char '\t' l with
      | "reflect" :: _ :: n :: verdict :: _ when n = name -> Some verdict
      | _ -> None)
    (lines out)

let expect_reflected out name want =
  match reflect_row out name with
  | Some v when v = want -> ()
  | v -> Alcotest.failf "reflect `%s`: expected %s, got %s:\n%s" name want (Option.value ~default:"no row" v) out

let derived_eq =
  [ gated "derived_eq: == on a recursive type with derive Eq is usable in a lemma" (fun () ->
        let out =
          run ~args:"--check --reflect-report --reflect-deps"
            "mod D do\n\
             \  type Chain = A | B(Int, Chain)\n\
             \  derive Eq for Chain\n\
             \  fn same(x : Chain, y : Chain) : Bool do x == y end\n\
             \  @[lemma]\n\
             \  fn refl(x : Chain) : {Unit | same(x, x)} do () end\n\
             end\n"
        in
        expect_reflected out "same" "reflected";
        expect_status out "refl" "admitted");
    gated "derived_eq: a recursion on components of a tuple of parameters is structural" (fun () ->
        let out =
          run ~args:"--check --reflect-report"
            "mod Z do\n\
             \  fn zlen(xs : List(Int), ys : List(Int)) : Int do\n\
             \    match (xs, ys) do\n\
             \      (Cons(_, xt), Cons(_, yt)) -> 1 + zlen(xt, yt)\n\
             \      _ -> 0\n\
             \    end\n\
             \  end\n\
             end\n"
        in
        expect_reflected out "zlen" "reflected");
    gated "derived_eq control: a component passed in another parameter's position is not structural" (fun () ->
        (* `xt` is smaller than `xs`, but it is passed where `ys` goes, and `ys`
           itself is passed where `xs` goes: neither position decreases. *)
        let out =
          run ~args:"--check --reflect-report"
            "mod Z do\n\
             \  fn swp(xs : List(Int), ys : List(Int)) : Int do\n\
             \    match (xs, ys) do\n\
             \      (Cons(_, xt), _) -> swp(ys, xt)\n\
             \      _ -> 0\n\
             \    end\n\
             \  end\n\
             end\n"
        in
        expect_reflected out "swp" "no") ]


let scoped_asserts =
  [ gated "assert by: proves and exports its goal" (fun () ->
        let out = run {|mod N do
  fn positive(x : {Int | _ > 0}) : Int do x end
  fn consume(x : {Int | _ > 0}) : Int do
    assert x > 0 by do () end
    positive(x)
  end
end
|} in
        if contains out "error" || not (contains out "proved\tuser") then
          Alcotest.failf "scoped assertion should prove:\n%s" out);
    gated "assert by: false goal never escapes" (fun () ->
        let out = run {|mod N do
  fn positive(x : {Int | _ > 0}) : Int do x end
  fn consume(x : Int) : Int do
    assert x > 0 by do () end
    positive(x)
  end
end
|} in
        if not (contains out "assert" && not (contains out "proved\tuser")) then
          Alcotest.failf "false scoped assertion must be refuted:\n%s" out); gated "assert by: only the goal escapes, in functions and lemmas" (fun () ->
      let out = run ("mod N do\n" ^ defs4_6 ^ cat_nil ^ {|
  fn isolated(xs : List(Int)) : Int do
    assert true by do cat_nil(xs) end
    need_eq(xs, cat(xs, Nil))
  end
  fn exported(xs : List(Int)) : Int do
    assert cat(xs, Nil) == xs by do cat_nil(xs) end
    need_eq(xs, cat(xs, Nil))
  end
  fn plain(xs : List(Int)) : Int do
    cat_nil(xs)
    need_eq(xs, cat(xs, Nil))
  end
  @[lemma]
  fn isolated_lemma(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do
    assert true by do cat_nil(xs) end
  end
  @[lemma]
  fn exported_lemma(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do
    assert cat(xs, Nil) == xs by do cat_nil(xs) end
  end
end
|}) in
      expect_unproved out "isolated_lemma";
      expect_admitted out "exported_lemma";
      let rows = List.filter (fun l -> contains l "\tprecondition\tneed_eq\t") (lines out) in
      Alcotest.(check int) "three function call obligations" 3 (List.length rows);
      Alcotest.(check int) "only exported and plain prove" 2
        (List.length (List.filter (fun l -> String.starts_with ~prefix:"proved\t" l) rows)));
    gated "assert by: nested scopes preserve local facts without exporting helpers" (fun () ->
      let out = run ("mod N do\n" ^ defs4_6 ^ cat_nil ^ {|
  @[lemma]
  fn nested(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do
    assert cat(xs, Nil) == xs by do
      let y = 1
      assert y == 1
      assert cat(xs, Nil) == xs by do cat_nil(xs) end
    end
  end
end
|}) in expect_admitted out "nested");
    gated "assert by: false hints cannot prove a false goal" (fun () ->
      let out = run {|mod N do
  @[lemma]
  fn bad(n : Int) : {Unit | n > 0} do
    assert n > 0 by do assert false end
  end
end
|} in
      if lemma_line out "bad" = Some "proved" then Alcotest.failf "false proof admitted:\n%s" out;
      if not (contains out "\tassert\t") then Alcotest.failf "missing assertion obligation:\n%s" out);
    gated "assert by: rejects effects and nonreflectable calls" (fun () ->
      List.iter (fun hint ->
        let out = run ("mod N do\n  needs IO.Console\n  fn f(n : Int) : Int do\n    assert true by do " ^ hint ^ " end\n    n\n  end\nend\n") in
        if not (contains out "[invalid_lemma]") then Alcotest.failf "invalid proof accepted:\n%s" out)
        ["println(\"erased effect\")"; "panic(\"bad\")"]);
    gated "assert by: rejects shadowing of a goal variable" (fun () ->
      let out = run {|mod N do
  fn f(n : Int) : Int do
    assert n == 0 by do
      let n = 0
      ()
    end
    n
  end
end
|} in
      if not (contains out "rename the hint-local binding") then Alcotest.failf "goal was captured:\n%s" out);
    gated "assert by: strict verification rejects an unknown goal" (fun () ->
      let out = run {|mod N do
  cap verified
  fn f(n : Int) : Int do
    assert n > 0 by do () end
    n
  end
end
|} in
      if not (contains out "[lemma_unproved]") then
        Alcotest.failf "strict proof accepted:\n%s" out); gated "assert by: erasure without lemma declarations" (fun () ->
      let src proof = String.concat "\n" [
        "mod Main do"; "  needs IO.Console";
        "  fn main(_cap : Cap(IO.Console)) do";
        (if proof then "    assert 1 == 1 by do let x = 40 + 2 end" else "");
        "    println(\"42\")"; "  end"; "end"; ""] in
      List.iter (fun mode -> Alcotest.(check string) "runtime output" "42\n" (output mode (src true)))
        [`Interp; `Compiled; `Jit];
      Alcotest.(check string) "proof-free LLVM" (ll (src false)) (ll (src true)));
    gated "assert by: unverified proof is erased with reflection disabled" (fun () ->
      let src = {|mod Main do
  needs IO.Console
  fn unchecked(n : Int) : Unit do
    assert n > 0 by do () end
  end
  fn main(_cap : Cap(IO.Console)) do
    unchecked(0)
    println("alive")
  end
end
|} in
      List.iter (fun mode ->
        let out = output ~env:"MARCH_REFLECT=0" mode src in
        if not (contains out "alive") || contains out "Assertion failed" then
          Alcotest.failf "erased assertion executed:\n%s" out) [`Interp; `Compiled; `Jit]); gated "assert by: failed helper precondition withholds the goal" (fun () ->
      let out = run {|mod N do
  @[lemma]
  fn positive(n : {Int | _ > 0}) : {Unit | n > 0} do () end
  @[lemma]
  fn bad(n : Int) : {Unit | n > 0} do
    assert n > 0 by do positive(n) end
  end
end
|} in
      if not (unproved out "bad" || refuted out "bad") then
        Alcotest.failf "failed helper admitted a theorem:\n%s" out;
      if not (contains out "[lemma_unproved_call]") then Alcotest.failf "helper precondition unchecked:\n%s" out);
    gated "assert by: hint branch facts do not escape" (fun () ->
      let out = run ("mod N do\n" ^ defs4_6 ^ cat_nil ^ {|
  @[lemma]
  fn bad(xs : List(Int), b : Bool) : {Unit | cat(xs, Nil) == xs} do
    assert cat(xs, Nil) == xs by do
      if b do cat_nil(xs) else () end
    end
  end
end
|}) in expect_unproved out "bad");
    gated "assert by: a proved block in a let RHS exports only its goal" (fun () ->
      let out = run ("mod N do\n" ^ defs4_6 ^ cat_nil ^ {|
  @[lemma]
  fn good(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do
    let _ = assert cat(xs, Nil) == xs by do cat_nil(xs) end
    ()
  end
end
|}) in expect_admitted out "good");
    gated "assert by: divergence and opaque callees rejected" (fun () ->
      List.iter (fun definition ->
        let out = run ("mod N do\n" ^ definition ^ "\n  fn f(n : Int) : Int do\n    assert true by do hidden(n) end\n    n\n  end\nend\n") in
        if not (contains out "[invalid_lemma]") then Alcotest.failf "invalid callee accepted:\n%s" out)
        ["  fn hidden(n : Int) : Int do hidden(n) end";
         "  @[opaque]\n  fn hidden(n : Int) : Int do n end"]);
    gated "assert by: disabled reflection still rejects erased effects" (fun () ->
      let out = run ~env:"MARCH_REFLECT=0" {|mod N do
  needs IO.Console
  fn f() : Unit do assert true by do println("effect") end end
end
|} in
      if not (contains out "[invalid_lemma]") then Alcotest.failf "effectful proof accepted:\n%s" out);
    gated "assert by: branch-tail assertions remain static obligations" (fun () ->
      let out = run {|mod N do
  fn f(b : Bool) : Unit do
    assert true by do
      if b do assert false else () end
    end
  end
end
|} in
      if not (contains out "[refinement_violated]") then Alcotest.failf "branch assert was not checked:\n%s" out);
    gated "assert by: ordinary hint equality checks custom Eq totality" (fun () ->
      let out = run {|mod N do
  type P = P(Int)
  impl Eq(P) do
    fn eq(_a, _b) : Bool do panic("bad") end
  end
  fn check(x : P) : Unit do
    assert true by do
      let b = x == x
      ()
    end
  end
end
|} in
      if not (contains out "[invalid_lemma]") then
        Alcotest.failf "partial Eq in proof hint accepted:\n%s" out);
    gated "assert by: static hint assertions preserve reflection" (fun () ->
      let out = run {|mod N do
  @[reflect]
  fn ident(x : Int) : Int do
    assert x == x by do assert x == x end
    x
  end
  @[lemma]
  fn identity(x : Int) : {Unit | ident(x) == x} do () end
end
|} in
      if contains out "[invalid_reflect]" then Alcotest.failf "proof blocked reflection:\n%s" out;
      expect_admitted out "identity");
    gated "assert by: case-splitting hints prove the goal on every exit" (fun () ->
      let out = run ("mod N do\n" ^ defs4_6 ^ cat_nil ^ {|
  @[lemma]
  fn scoped(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do
    assert cat(xs, Nil) == xs by do
      match xs do
        Nil -> ()
        Cons(_, t) -> cat_nil(t)
      end
    end
  end
end
|}) in expect_admitted out "scoped") ]

let scoped_hint_bindings =
  [ gated "assert by: sequential hint bindings retain lexical scope" (fun () ->
        let out = run {|mod N do
  fn checked() : Unit do
    assert true by do
      let y = 1
      fn same(x : Int) : Int do x end
      assert same(y) == 1
    end
  end
end
|} in
        if contains out "[invalid_lemma]" || contains out "[lemma_unproved]"
           || not (contains out "proved\tuser") then
          Alcotest.failf "hint-local bindings must remain in scope:\n%s" out) ]

let scoped_directives =
  [ gated "assert by: reveal inside and before the hint remains scoped" (fun () ->
        let out = run {|mod N do
  @[opaque]
  fn dbl(n : Int) : Int do n + n end
  fn inside() : Unit do assert dbl(2) == 4 by do reveal dbl end end
  fn outside() : Unit do
    reveal dbl
    assert dbl(2) == 4 by do () end
  end
end
|} in
        U.expect out ~line:4 ~callee:"assert" "proved";
        U.expect out ~line:7 ~callee:"assert" "proved";
        if contains out "[invalid_lemma]" || contains out "[lemma_unproved]" then
          Alcotest.failf "explicit reveal must remain available:\n%s" out);
    gated "assert by: trailing fuel covers the goal and restores afterwards" (fun () ->
        let out = run {|mod N do
  @[decreases(n)]
  fn cnt(n : {Int | _ >= 0}) : Int do if n == 0 do 0 else cnt(n - 1) + 1 end end
  fn checked() : Unit do
    assert cnt(3) == 3 by do with fuel(cnt, 5) do () end end
    assert cnt(7) == 7 by do () end
  end
end
|} in
        U.expect out ~line:5 ~callee:"assert" "proved";
        U.not_proved out ~line:6 ~callee:"assert") ]
