(* Refinement reflection, phase 1a (specs/2026-10-29-refinement-reflection-design.md
   §10 phase 1, group `reflect-unfold`; the 1a/1b split is a ruling of
   specs/progress/2026-10-30-reflection-phase1a.md): single unfolding of
   automatically reflected first-order functions, the two-stage discharge, the
   two equalities, the measure merge and `@[opaque]`.

   Every case drives the REAL compiler (`--check --refine-report-sites=all`)
   under one private HOME and a fresh project directory (so the VC cache in
   `.march/cas/vc` starts cold), and asserts the printed obligation rows or
   diagnostics, never an exit code. *)

let z3_available () =
  match March_refine.Solver.create () with
  | None -> false
  | Some s -> March_refine.Solver.close s; true

let gated name f =
  Alcotest.test_case name `Quick (fun () -> if z3_available () then f () else Alcotest.skip ())

let exe () = Filename.concat (Filename.dirname Sys.executable_name) "../bin/main.exe"

let rec remove_tree path =
  if Sys.is_directory path then begin
    Array.iter (fun n -> remove_tree (Filename.concat path n)) (Sys.readdir path);
    Unix.rmdir path
  end
  else Sys.remove path

let home =
  lazy
    (let d = Filename.temp_dir "unfold_home" "" in
     at_exit (fun () -> try remove_tree d with _ -> ());
     d)

let run_in ?(env = "") ~dir args file =
  let out = Filename.temp_file "unfold" ".out" in
  let cmd =
    Printf.sprintf "cd %s && HOME=%s %s %s %s %s > %s 2>&1" (Filename.quote dir)
      (Filename.quote (Lazy.force home)) env (Filename.quote (exe ())) args (Filename.quote file)
      (Filename.quote out)
  in
  ignore (Test_helpers.Sys.command cmd);
  let s = In_channel.with_open_bin out In_channel.input_all in
  Sys.remove out;
  s

(* Check [src] in a fresh directory: stdout and stderr together. *)
let run ?(env = "") ?(args = "--check --refine-report-sites=all") src =
  let dir = Filename.temp_dir "unfold" "" in
  Fun.protect ~finally:(fun () -> try remove_tree dir with _ -> ()) (fun () ->
      let f = Filename.concat dir "m.march" in
      Out_channel.with_open_bin f (fun oc -> output_string oc src);
      run_in ~env ~dir args "m.march")

(* Check [src] with library modules: each (file, text) is written to a lib/
   directory passed as MARCH_LIB_PATH. *)
let run_lib ?(env = "") ?(args = "--check --refine-report-sites=all") ~(lib : (string * string) list) src =
  let dir = Filename.temp_dir "unfold_lib" "" in
  Fun.protect ~finally:(fun () -> try remove_tree dir with _ -> ()) (fun () ->
      let ld = Filename.concat dir "lib" in
      Unix.mkdir ld 0o755;
      List.iter (fun (f, t) -> Out_channel.with_open_bin (Filename.concat ld f) (fun oc -> output_string oc t)) lib;
      let f = Filename.concat dir "m.march" in
      Out_channel.with_open_bin f (fun oc -> output_string oc src);
      run_in ~env:(env ^ " MARCH_LIB_PATH=" ^ Filename.quote ld) ~dir args "m.march")

let lines s = String.split_on_char '\n' s |> List.filter (( <> ) "")

let contains hay needle =
  let n = String.length needle and h = String.length hay in
  let rec go i = i + n <= h && (String.sub hay i n = needle || go (i + 1)) in
  go 0

(* The user obligation rows at source line [line] whose callee is [callee]:
   (verdict-or-"skip:<reason>", uses). *)
let rows ?pred ?(file = "") out ~line ~callee =
  let keep l = match pred with None -> true | Some p -> contains l p in
  List.filter keep (lines out) |> fun ls ->
  List.filter_map
    (fun l ->
      match String.split_on_char '\t' l with
      | "skip" :: ("user" | "stdlib") :: loc :: reason :: _kind :: c :: _ when c = callee ->
        (match String.split_on_char ':' loc with
         | [ f; ln; _ ] when int_of_string_opt ln = Some line && contains f file -> Some ("skip:" ^ reason, "")
         | _ -> None)
      | v :: ("user" | "stdlib") :: loc :: _kind :: c :: rest when c = callee && v <> "skip" ->
        (match String.split_on_char ':' loc with
         | [ f; ln; _ ] when int_of_string_opt ln = Some line && contains f file ->
           let uses = match List.rev rest with u :: _ when String.starts_with ~prefix:"uses: " u -> u | _ -> "" in
           Some (v, uses)
         | _ -> None)
      | _ -> None)
    ls

let expect ?uses ?file out ~line ~callee verdict =
  match rows ?file out ~line ~callee with
  | [] -> Alcotest.failf "no %s row at line %d in:\n%s" callee line out
  | rs ->
    if not (List.exists (fun (v, _) -> v = verdict) rs) then
      Alcotest.failf "%s at line %d: expected %s, got [%s]\n%s" callee line verdict
        (String.concat "; " (List.map fst rs)) out;
    match uses with
    | Some u ->
      if not (List.exists (fun (v, us) -> v = verdict && contains us u) rs) then
        Alcotest.failf "%s at line %d: `uses:` does not contain %s: [%s]" callee line u
          (String.concat "; " (List.map snd rs))
    | None -> ()

let not_proved ?pred ?file out ~line ~callee =
  match rows ?pred ?file out ~line ~callee with
  | [] -> Alcotest.failf "no %s row at line %d in:\n%s" callee line out
  | rs ->
    if List.exists (fun (v, _) -> v = "proved") rs then
      Alcotest.failf "%s at line %d must NOT be proved:\n%s" callee line out

let has_code out code = contains out ("[" ^ code ^ "]")

let count_code out code =
  List.length (List.filter (fun l -> contains l ("[" ^ code ^ "]")) (lines out))

let cat =
  {|  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end
|}

let suite =
  [ gated "guard_pred: a path fact unfolds (uses: is_small)" (fun () ->
        let out =
          run
            {|mod G do
  fn is_small(n : Int) : Bool do n < 10 end
  fn need_small(n : {Int | _ < 10}) : Int do n end
  fn f(n : Int) : Int do
    if is_small(n) do need_small(n) else 0 end
  end
end
|}
        in
        expect out ~line:5 ~callee:"need_small" "proved" ~uses:"is_small";
        if contains out "is not a measure or known predicate" then
          Alcotest.fail "a reflected function must not draw the vocabulary warning");
    gated "pred_call: a reflected call in a predicate; idx2(3) proved, idx2(4) violated" (fun () ->
        let out =
          run
            {|mod P do
  fn inc(n : Int) : Int do n + 1 end
  fn idx2(i : {Int | _ < inc(3)}) : Int do i end
  fn a() : Int do idx2(3) end
  fn b() : Int do idx2(4) end
end
|}
        in
        expect out ~line:4 ~callee:"idx2" "proved" ~uses:"inc";
        expect out ~line:5 ~callee:"idx2" "violated");
    gated "subject_call: need(inc(1)) is proved" (fun () ->
        let out =
          run
            {|mod S do
  fn inc(n : Int) : Int do n + 1 end
  fn need(x : {Int | _ == 2}) : Int do x end
  fn a() : Int do need(inc(1)) end
end
|}
        in
        expect out ~line:4 ~callee:"need" "proved" ~uses:"inc");
    gated "let_result: let r = inc(1) then need(r) is proved" (fun () ->
        let out =
          run
            {|mod R do
  fn inc(n : Int) : Int do n + 1 end
  fn need(x : {Int | _ == 2}) : Int do x end
  fn a() : Int do
    let r = inc(1)
    need(r)
  end
end
|}
        in
        expect out ~line:6 ~callee:"need" "proved" ~uses:"inc");
    gated "one_step: need_eq(ys, cat(Nil, ys)) is proved by one unfolding" (fun () ->
        let out =
          run
            ("mod O do\n" ^ cat
           ^ {|  fn need_eq(a : List(Int), b : {List(Int) | _ == a}) : Int do 0 end
  fn go(ys : List(Int)) : Int do need_eq(ys, cat(Nil, ys)) end
end
|})
        in
        expect out ~line:9 ~callee:"need_eq" "proved" ~uses:"cat");
    gated "no_second_step: need2(cat([1], [2])) needs depth 1: reflect-fuel" (fun () ->
        let out =
          run
            ("mod N do\n" ^ cat
           ^ {|  fn need2(xs : {List(Int) | len(_) == 2}) : Int do 0 end
  fn go() : Int do need2(cat(Cons(1, Nil), Cons(2, Nil))) end
end
|})
        in
        expect out ~line:9 ~callee:"need2" "skip:reflect-fuel");
    gated "two_arg: count_ge reflected with two parameters" (fun () ->
        let out =
          run
            {|mod T do
  fn count_ge(xs : List(Int), k : Int) : Int do
    match xs do
      Nil -> 0
      Cons(h, t) -> if h >= k do 1 + count_ge(t, k) else count_ge(t, k) end
    end
  end
  fn need_small(n : {Int | _ < 1}) : Int do n end
  fn need_zero(n : {Int | _ == 0}) : Int do n end
  fn a() : Int do need_small(count_ge(Cons(5, Nil), 3)) end
  fn b() : Int do need_zero(count_ge(Nil, 3)) end
end
|}
        in
        expect out ~line:10 ~callee:"need_small" "skip:reflect-fuel";
        expect out ~line:11 ~callee:"need_zero" "proved" ~uses:"count_ge");
    gated "list_result: rev1(Nil) == Nil, a datatype result sort" (fun () ->
        let out =
          run
            ("mod LR do\n" ^ cat
           ^ {|  fn rev1(xs : List(Int)) : List(Int) do
    match xs do
      Nil -> Nil
      Cons(h, t) -> cat(rev1(t), Cons(h, Nil))
    end
  end
  fn need_nil(xs : {List(Int) | _ == Nil}) : Int do 0 end
  fn go() : Int do need_nil(rev1(Nil)) end
end
|})
        in
        expect out ~line:15 ~callee:"need_nil" "proved" ~uses:"rev1");
    gated "bool_measure: a Bool @[measure] discharges (F5): needp(S(Z)) proved, needp(Z) violated" (fun () ->
        let out =
          run
            {|mod BM do
  type Nat = Z | S(Nat)
  @[measure]
  fn pos_nat(n : Nat) : Bool do
    match n do
      Z -> false
      S(_) -> true
    end
  end
  fn needp(n : {Nat | pos_nat(_)}) : Int do 0 end
  fn a() : Int do needp(S(Z)) end
  fn b() : Int do needp(Z) end
end
|}
        in
        expect out ~line:11 ~callee:"needp" "proved";
        expect out ~line:12 ~callee:"needp" "violated";
        if has_code out "invalid_measure" then Alcotest.fail "a Bool measure is accepted");
    gated "measure_alias_ok: two-argument and list-returning @[measure]s are accepted (F2, F6)" (fun () ->
        let out =
          run
            {|mod MA do
  @[measure]
  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end
  @[measure]
  fn count_ge(xs : List(Int), k : Int) : Int do
    match xs do
      Nil -> 0
      Cons(h, t) -> if h >= k do 1 + count_ge(t, k) else count_ge(t, k) end
    end
  end
  fn need_eq(a : List(Int), b : {List(Int) | _ == a}) : Int do 0 end
  fn go(ys : List(Int)) : Int do need_eq(ys, cat(Nil, ys)) end
end
|}
        in
        if has_code out "invalid_measure" then Alcotest.failf "unexpected invalid_measure:\n%s" out;
        expect out ~line:17 ~callee:"need_eq" "proved");
    gated "measure_alias_err: the gate follows callees (c3b, h2)" (fun () ->
        let out =
          run
            {|mod ME do
  needs IO.Console
  type T = T(Int)
  impl Show(T) do
    fn show(t : T) : String do "t" end
  end
  fn noisy(n : Int) : Int do
    println("hi")
    n
  end
  fn boom(n : Int) : Int do panic("x") end
  fn spin(n : Int) : Int do spin(n) end
  @[measure]
  fn m1(xs : List(Int)) : Int do
    match xs do
      Nil -> noisy(0)
      Cons(_, t) -> 1 + m1(t)
    end
  end
  @[measure]
  fn m2(xs : List(Int)) : Int do
    match xs do
      Nil -> boom(0)
      Cons(_, t) -> 1 + m2(t)
    end
  end
  @[measure]
  fn m3(xs : List(Int)) : Int do
    match xs do
      Nil -> spin(0)
      Cons(_, t) -> 1 + m3(t)
    end
  end
  @[measure]
  fn m4(xs : List(T)) : Int do
    match xs do
      Nil -> 0
      Cons(h, t) -> string_byte_length(show(h)) + m4(t)
    end
  end
  @[measure]
  fn m5(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(h, t) -> string_byte_length("${h}") + m5(t)
    end
  end
end
|}
        in
        List.iter
          (fun (m, callee) ->
            if
              not
                (List.exists
                   (fun l -> contains l (Printf.sprintf "@[measure] `%s`" m) && contains l callee)
                   (lines out))
            then Alcotest.failf "no invalid_measure for %s naming %s in:\n%s" m callee out)
          [ ("m1", "noisy"); ("m2", "boom"); ("m3", "spin"); ("m4", "show"); ("m5", "to_string") ]);
    gated "measure_tier: c4's sz keeps the axiom tier; its calls run no stage 2 (I10)" (fun () ->
        let out =
          run ~env:"MARCH_REFLECT_DEBUG=2"
            {|mod MT do
  @[measure]
  fn sz(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(_, t) -> 1 + sz(t)
    end
  end
  fn need(xs : {List(Int) | sz(_) == 2}) : Int do 0 end
  fn a() : Int do need(Cons(1, Cons(2, Nil))) end
  fn b() : Int do need(Cons(1, Nil)) end
end
|}
        in
        expect out ~line:10 ~callee:"need" "proved";
        expect out ~line:11 ~callee:"need" "violated";
        if List.exists (fun l -> String.starts_with ~prefix:"reflect-stage:" l && (contains l "[m.march:" || contains l "; m.march:")) (lines out)
        then Alcotest.failf "a stage-2 run was issued for an axiom-tier call:\n%s" out);
    gated "eq_handwritten: g3 stays violated and gains predicate_eq_structural" (fun () ->
        let out =
          run
            {|mod G3 do
  type P = P(Int, Int)
  impl Eq(P) do
    fn eq(a : P, b : P) : Bool do
      match (a, b) do
        (P(x, _), P(y, _)) -> x == y
      end
    end
  end
  fn need(p : {P | _ == P(1, 2)}) : Int do 0 end
  fn a() : Int do need(P(1, 3)) end
end
|}
        in
        expect out ~line:11 ~callee:"need" "violated";
        if not (has_code out "predicate_eq_structural") then Alcotest.failf "no predicate_eq_structural:\n%s" out);
    gated "eq_derived: g2 is unchanged (1 proved, 1 violated, no warning)" (fun () ->
        let out =
          run
            {|mod G2 do
  type P = P(Int, Int)
  derive Eq for P
  fn need(p : {P | _ == P(1, 2)}) : Int do 0 end
  fn a() : Int do need(P(1, 2)) end
  fn b() : Int do need(P(1, 3)) end
end
|}
        in
        expect out ~line:5 ~callee:"need" "proved";
        expect out ~line:6 ~callee:"need" "violated";
        if has_code out "predicate_eq_structural" then Alcotest.fail "a derived Eq draws no warning");
    gated "opaque: @[opaque] keeps inc out of the logic" (fun () ->
        let out =
          run
            {|mod Op do
  @[opaque]
  fn inc(n : Int) : Int do n + 1 end
  fn need(x : {Int | _ == 2}) : Int do x end
  fn a() : Int do need(inc(1)) end
end
|}
        in
        expect out ~line:5 ~callee:"need" "skip:unreflectable-subject";
        if has_code out "unknown_attribute" then Alcotest.fail "@[opaque] is a known attribute");
    gated "opaque_no_effect: @[opaque] on a function that is not reflected warns" (fun () ->
        let out =
          run
            {|mod On do
  needs IO.Console
  @[opaque]
  fn noisy(n : Int) : Int do
    println("x")
    n
  end
end
|}
        in
        if not (has_code out "attribute_no_effect" && contains out "would not be reflected anyway") then
          Alcotest.failf "expected attribute_no_effect:\n%s" out);
    gated "opaque_conflict: @[opaque] @[measure] is reflect_conflict" (fun () ->
        let out =
          run
            {|mod Oc do
  @[opaque]
  @[measure]
  fn sz(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(_, t) -> 1 + sz(t)
    end
  end
end
|}
        in
        if not (has_code out "reflect_conflict") then Alcotest.failf "expected reflect_conflict:\n%s" out);
    gated "spurious_refutation: a stage-1 violation stage 2 would prove is kept in 1a" (fun () ->
        let out =
          run
            {|mod Sp do
  fn is_small(n : Int) : Bool do n < 10 end
  fn need_small(n : {Int | _ < 10}) : Int do n end
  fn f(n : Int) : Int do
    if n > 20 do
      if is_small(n) do need_small(n) else 0 end
    else 0 end
  end
end
|}
        in
        (* Phase 1a never withdraws a stage-1 violation (third review I1):
           the call sits on a path the definition of `is_small` rules out, so
           stage 2 proves it, but the violation and its error stay. *)
        expect out ~line:6 ~callee:"need_small" "violated";
        if not (has_code out "refinement_violated") then Alcotest.fail "the stage-1 error must stay";
        if has_code out "reflect_inconsistent" then Alcotest.fail "the stage-1 model was never confirmed");
    gated "budget: 40 reflected calls exceed the cap of 32 (reflect-budget); 20 prove" (fun () ->
        let fs = String.concat "" (List.init 40 (fun i -> Printf.sprintf "  fn f%d(n : Int) : Int do n end\n" (i + 1))) in
        let sum k = String.concat " + " (List.init k (fun i -> Printf.sprintf "f%d(n)" (i + 1))) in
        let out =
          run
            (Printf.sprintf
               "mod Bu do\n%s  fn need40(n : Int, x : {Int | _ == %s}) : Int do x end\n  fn need20(n : Int, x : {Int | _ == %s}) : Int do x end\n  fn a() : Int do need40(0, 0) end\n  fn b() : Int do need20(0, 0) end\nend\n"
               fs (sum 40) (sum 20))
        in
        expect out ~line:44 ~callee:"need40" "skip:reflect-budget";
        expect out ~line:45 ~callee:"need20" "proved");
    gated "stage2_timeout: an undecided stage-2 query is not re-asked in the same process (I10)" (fun () ->
        let out =
          run ~env:"MARCH_REFLECT_DEBUG=1"
            {|mod To do
  fn cube(x : Int) : Int do x * x * x end
  fn need(a : {Int | _ > 0}, b : {Int | _ > 0}, c : {Int | cube(a) + cube(b) != cube(_)}) : Int do 0 end
  fn f(a : {Int | _ > 0}, b : {Int | _ > 0}, c : {Int | _ > 0}) : Int do need(a, b, c) end
  fn g(a : {Int | _ > 0}, b : {Int | _ > 0}, c : {Int | _ > 0}) : Int do need(a, b, c) end
end
|}
        in
        not_proved ~pred:"cube" out ~line:4 ~callee:"need";
        not_proved ~pred:"cube" out ~line:5 ~callee:"need";
        let hits =
          List.find_map
            (fun l -> try Scanf.sscanf l "reflect-debug: stage2_runs=%d stage2_queries=%d stage2_unknown_hits=%d" (fun _ _ h -> Some h) with _ -> None)
            (lines out)
        in
        match hits with
        | Some h when h >= 1 -> ()
        | _ -> Alcotest.failf "the second identical stage-2 query must hit the in-process negative cache:\n%s" out);
  ]

(* §9.1, the rows phase 1 closes. *)
let soundness =
  [ gated "sound_diverge: spin is not reflected; need_false(0) is never proved; @[measure] spin errors" (fun () ->
        let out =
          run ~args:"--check --refine-report-sites=all --reflect-report"
            {|mod Sd do
  fn spin(n : Int) : Int do spin(n) + 1 end
  fn need_false(x : {Int | spin(0) == spin(0) + 1}) : Int do x end
  fn a() : Int do need_false(0) end
end
|}
        in
        not_proved out ~line:4 ~callee:"need_false";
        let out2 = run "mod Sd2 do\n  @[measure]\n  fn spin(xs : List(Int)) : Int do spin(xs) + 1 end\nend\n" in
        if not (has_code out2 "invalid_measure") then Alcotest.failf "@[measure] spin must be invalid:\n%s" out2);
    gated "sound_partial: hd without Nil and safe with panic are not reflected" (fun () ->
        let out =
          run
            {|mod Spa do
  fn hd(xs : List(Int)) : Int do
    match xs do
      Cons(h, _) -> h
    end
  end
  fn safe(n : Int) : Int do if n > 0 do n else panic("") end end
  fn need0(x : {Int | hd(Nil) == 0}) : Int do x end
  fn need1(x : {Int | safe(0) == 0}) : Int do x end
  fn a() : Int do need0(0) + need1(0) end
end
|}
        in
        not_proved out ~line:10 ~callee:"need0";
        not_proved out ~line:10 ~callee:"need1";
        if not (contains out "`hd` is not reflected" && contains out "`safe` is not reflected") then
          Alcotest.failf "the predicate warning names the blocker:\n%s" out);
    gated "sound_eq: a hand-written Eq is opaque in a body; derived proves; transitive through Q" (fun () ->
        let hand =
          {|  type P = P(Int, Int)
  impl Eq(P) do
    fn eq(a : P, b : P) : Bool do
      match (a, b) do
        (P(x, _), P(y, _)) -> x == y
      end
    end
  end
|}
        in
        let body =
          {|  type Q = Q(P)
  derive Eq for Q
  fn same(a : P, b : P) : Bool do a == b end
  fn same_q(a : Q, b : Q) : Bool do a == b end
  fn need_false(b : {Bool | _ == false}) : Int do 0 end
  fn a() : Int do need_false(same(P(1, 3), P(1, 2))) end
  fn b() : Int do need_false(same_q(Q(P(1, 3)), Q(P(1, 2)))) end
end
|}
        in
        let out = run ("mod Se do\n" ^ hand ^ body) in
        not_proved out ~line:15 ~callee:"need_false";
        not_proved out ~line:16 ~callee:"need_false";
        let ctl = run ("mod Se2 do\n  type P = P(Int, Int)\n  derive Eq for P\n" ^ body) in
        expect ctl ~line:9 ~callee:"need_false" "proved";
        expect ctl ~line:10 ~callee:"need_false" "proved");
    gated "sound_eq_float (control only in 1a): no Float function is reflected, so same(x, x) at Float is never proved" (fun () ->
        (* Phase 1a gives no Float-typed function a logic symbol (progress
           note, ruling 5), so this row exercises the CONTROL, not the
           opaque-`eq$Float` rule: it pins that NaN cannot be reasoned about
           wrongly because nothing Float-shaped reaches the logic. *)
        let src =
          {|mod Sf do
  fn same(a : Float, b : Float) : Bool do a == b end
  fn need_true(b : {Bool | _ == true}) : Int do 0 end
  fn a(x : Float) : Int do need_true(same(x, x)) end
  fn ident(x : Int) : Int do x end
  fn need_eq(a : Int, b : {Int | _ == a}) : Int do 0 end
  fn b(n : Int) : Int do need_eq(ident(n), n) end
end
|}
        in
        let out = run src in
        (* `same(x, x)` is false at run time for x = NaN. *)
        not_proved out ~line:4 ~callee:"need_true";
        (* positive control: Int identity unfolds. *)
        expect out ~line:7 ~callee:"need_eq" "proved" ~uses:"ident");
    gated "sound_eq_effect: == over an effectful, partial or looping eq blocks reflection (C4)" (fun () ->
        let out =
          run ~args:"--check --reflect-report"
            {|mod Sef do
  needs IO.Console
  type P = P(Int)
  type Q = Q(Int)
  type R = R(Int)
  impl Eq(P) do
    fn eq(a : P, b : P) : Bool do
      println("eq")
      true
    end
  end
  impl Eq(Q) do
    fn eq(a : Q, b : Q) : Bool do panic("eq") end
  end
  impl Eq(R) do
    fn eq(a : R, b : R) : Bool do a == b end
  end
  fn same_p(a : P, b : P) : Bool do a == b end
  fn same_q(a : Q, b : Q) : Bool do a == b end
  fn same_r(a : R, b : R) : Bool do a == b end
end
|}
        in
        List.iter
          (fun f ->
            if not (List.exists (fun l -> contains l ("\t" ^ f ^ "\tno\tR6:")) (lines out)) then
              Alcotest.failf "%s must be blocked by R6:\n%s" f out)
          [ "same_p"; "same_q"; "same_r" ]);
    gated "sound_fnvalue: function values in a body block reflection (R7)" (fun () ->
        let out =
          run ~args:"--check --reflect-report"
            {|mod Sfv do
  fn apply(f : Int -> Int, x : Int) : Int do f(x) end
  fn twice(x : Int) : List(Int) do List.map(Cons(x, Nil), fn y -> y + 1) end
end
|}
        in
        List.iter
          (fun f ->
            if not (List.exists (fun l -> contains l ("\t" ^ f ^ "\tno\tR7:")) (lines out)) then
              Alcotest.failf "%s must be blocked by R7:\n%s" f out)
          [ "apply" ];
        (* `twice`'s first blocker in R-order is R6 (`List.map` takes a
           function value, so it is itself not reflected); R7 is its lambda. *)
        List.iter
          (fun f ->
            if not (List.exists (fun l -> contains l ("\t" ^ f ^ "\tno\tR")) (lines out)) then
              Alcotest.failf "%s must not be reflected:\n%s" f out)
          [ "twice" ]);
    gated "sound_dispatch: show, interpolation and compare on a user impl block reflection" (fun () ->
        let out =
          run ~args:"--check --reflect-report"
            {|mod Sdi do
  type T = T(Int)
  impl Show(T) do
    fn show(t : T) : String do "t" end
  end
  impl Ord(T) do
    fn compare(a : T, b : T) : Int do 0 end
  end
  fn f(x : T) : Int do string_byte_length("${x}") end
  fn g(x : T) : Int do string_byte_length(show(x)) end
  fn h(a : T, b : T) : Int do compare(a, b) end
end
|}
        in
        List.iter
          (fun f ->
            if not (List.exists (fun l -> contains l ("\t" ^ f ^ "\tno\t")) (lines out)) then
              Alcotest.failf "%s must not be reflected:\n%s" f out)
          [ "f"; "g"; "h" ]);
    gated "sound_domain: an unfolding is guarded by the callee's parameter refinements (C1)" (fun () ->
        let out =
          run
            {|mod Sdo do
  fn pos(n : {Int | _ >= 0}) : Int do n end
  fn need_neg(x : {Int | _ < 0}) : Int do x end
  fn need_one(x : {Int | _ == 1}) : Int do x end
  fn p(n : {Int | _ >= 0}) : Bool do if n >= 0 do true else not(p(n)) end end
  fn need_t(x : {Int | p(0 - 1) || x == x + 1}) : Int do x end
  fn a() : Int do need_neg(pos(0 - 1)) end
  fn b() : Int do need_one(pos(1)) end
  fn c() : Int do need_t(0) end
end
|}
        in
        not_proved out ~line:7 ~callee:"need_neg";
        expect out ~line:8 ~callee:"need_one" "proved" ~uses:"pos";
        (* `p` is metric-certified, which the 1a encoder does not unfold
           (ruling 2): this row passes because `p` is not reflected, not
           because of the guard.  The guard itself is exercised by `pos`. *)
        not_proved out ~line:9 ~callee:"need_t");
    gated "sound_guarded: a guarded match that can fall through is not reflected (C2)" (fun () ->
        let out =
          run
            {|mod Sg do
  fn guarded(xs : List(Int)) : Int do
    match xs do
      Cons(h, _) when h > 0 -> h
      Nil -> 0
    end
  end
  fn guarded2(xs : List(Int)) : Int do
    match xs do
      Cons(h, _) when h > 0 -> h
      Nil -> 0
      _ -> 0
    end
  end
  fn need_eq(a : Int, b : {Int | _ == a}) : Int do 0 end
  fn a() : Int do need_eq(0, guarded(Cons(0 - 1, Nil))) end
  fn b() : Int do need_eq(0, guarded2(Cons(0 - 1, Nil))) end
end
|}
        in
        not_proved out ~line:16 ~callee:"need_eq";
        expect out ~line:17 ~callee:"need_eq" "proved" ~uses:"guarded2");
    gated "sound_shadow: a user len is not $len; g(xs) = len(xs) is not reflected (I3)" (fun () ->
        let out =
          run
            {|mod Ssh do
  fn len(xs : List(Int)) : Int do 7 end
  fn g(xs : List(Int)) : Int do len(xs) end
  fn need_eq(a : Int, b : {Int | _ == a}) : Int do 0 end
  fn need1(xs : {List(Int) | len(_) == 1}) : Int do 0 end
  fn a() : Int do need_eq(1, g(Cons(1, Nil))) end
  fn b() : Int do need1(Cons(1, Nil)) end
end
|}
        in
        not_proved out ~line:6 ~callee:"need_eq";
        expect out ~line:7 ~callee:"need1" "proved");
    gated "sound_mangle: two local `go`s never share a symbol (I4)" (fun () ->
        (* `f(0)` unfolds to `f/go(0)`, a depth-1 call, so the values are not
           proved in phase 1a (single unfolding): what is checked is that the
           two locals, and two `go`s declared in sequence in one function,
           are four different logic symbols, so no proof can mix them. *)
        let src =
          {|mod Sm do
  fn f(n : Int) : Int do
    fn go(k : Int) : Int do k + 1 end
    go(n)
  end
  fn g(n : Int) : Int do
    fn go(k : Int) : Int do k + 2 end
    go(n)
  end
  fn h(n : Int) : Int do
    fn go(k : Int) : Int do k + 3 end
    let a = go(n)
    fn go(k : Int) : Int do k + 4 end
    a + go(n)
  end
  fn need_eq(a : Int, b : {Int | _ == a}) : Int do 0 end
  fn c() : Int do need_eq(f(0), g(0)) end
  fn d() : Int do need_eq(h(0), h(0) + 1) end
end
|}
        in
        let dir = Filename.temp_dir "unfold_mangle" "" in
        Fun.protect ~finally:(fun () -> try remove_tree dir with _ -> ()) (fun () ->
            Out_channel.with_open_bin (Filename.concat dir "m.march") (fun oc -> output_string oc src);
            let lg = Filename.concat dir "z3.log" in
            let out = run_in ~env:("MARCH_REFINE_Z3_LOG=" ^ Filename.quote lg) ~dir "--check --refine-report-sites=all" "m.march" in
            (* These two are not proved because `f/go` etc. are depth-1
               calls (reflect-fuel), not because of the mangling; the
               mangling is checked by the symbol names below. *)
            not_proved out ~line:17 ~callee:"need_eq";
            not_proved out ~line:18 ~callee:"need_eq";
            let log = In_channel.with_open_bin lg In_channel.input_all in
            List.iter
              (fun sym -> if not (contains log sym) then Alcotest.failf "no symbol %s in the queries" sym)
              [ "|r:user:f/go#m.march:3:"; "|r:user:g/go#m.march:7:"; "|r:user:h/go#m.march:11:"; "|r:user:h/go#m.march:13:" ]));
    gated "sound_mangle: a user mod List never meets std List.append, and is not unfolded (I4, review C-A)" (fun () ->
        let out =
          run
            {|mod Um do
  mod List do
    fn append(xs : List(Int), ys : List(Int)) : List(Int) do xs end
    fn need_eq(a : List(Int), b : {List(Int) | _ == a}) : Int do 0 end
    fn u(xs : List(Int), ys : List(Int)) : Int do need_eq(xs, append(xs, ys)) end
  end
end
|}
        in
        (* Review C-A: inside the entry module, `List.append` could be this
           nested module's or the stdlib's (the interpreter and the compiled
           build disagree on such names: specs/todos/2026-10-30-interpreter-
           compiler-name-resolution-diverge.md), so it is ambiguous and never
           unfolded.  Either way no stdlib fact is read for it. *)
        not_proved out ~line:5 ~callee:"List.need_eq");
    gated "sound_inconsistent: a broken encoding against a confirmed violation is reflect_inconsistent (I7)" (fun () ->
        let src =
          {|mod Si do
  fn zero(n : Int) : Int do 0 end
  fn need_small(n : {Int | _ < 10}) : Int do n end
  fn f(n : Int) : Int do
    if n >= 0 && n < 5 do
      let r = zero(n)
      need_small(n + 20)
    else 0 end
  end
end
|}
        in
        let ok = run src in
        expect ok ~line:7 ~callee:"need_small" "violated";
        if has_code ok "reflect_inconsistent" then Alcotest.fail "no internal error without the perturbation";
        let broken = run ~env:"MARCH_REFLECT_PERTURB=false-unfold" src in
        expect broken ~line:7 ~callee:"need_small" "violated";
        if not (has_code broken "reflect_inconsistent") then
          Alcotest.failf "a confirmed violation proved by stage 2 must be reflect_inconsistent:\n%s" broken);
    gated "sound_uses_warm: uses: is the same cold and warm; a congruence proof lists f (I8)" (fun () ->
        let src =
          {|mod Su do
  fn f(n : Int) : Int do n * 3 end
  fn need_eq(a : Int, b : {Int | _ == a}) : Int do 0 end
  fn g(x : Int) : Int do
    let a = f(x)
    let b = f(x)
    need_eq(a, b)
  end
end
|}
        in
        let dir = Filename.temp_dir "unfold_warm" "" in
        Fun.protect ~finally:(fun () -> try remove_tree dir with _ -> ()) (fun () ->
            Out_channel.with_open_bin (Filename.concat dir "m.march") (fun oc -> output_string oc src);
            let cold = run_in ~dir "--check --refine-report-sites=all" "m.march" in
            let warm = run_in ~dir "--check --refine-report-sites=all" "m.march" in
            expect cold ~line:7 ~callee:"need_eq" "proved" ~uses:"f";
            expect warm ~line:7 ~callee:"need_eq" "proved" ~uses:"f";
            Alcotest.(check (list (pair string string))) "cold = warm" (rows cold ~line:7 ~callee:"need_eq")
              (rows warm ~line:7 ~callee:"need_eq")));
    gated "sound_cache: a body edit with a warm project cache changes the verdict" (fun () ->
        let src k =
          Printf.sprintf
            "mod Sc do\n  fn inc(n : Int) : Int do n + %d end\n  fn need(x : {Int | _ == 2}) : Int do x end\n  fn a() : Int do need(inc(1)) end\nend\n"
            k
        in
        let dir = Filename.temp_dir "unfold_cache" "" in
        Fun.protect ~finally:(fun () -> try remove_tree dir with _ -> ()) (fun () ->
            let f = Filename.concat dir "m.march" in
            Out_channel.with_open_bin f (fun oc -> output_string oc (src 1));
            let before = run_in ~dir "--check --refine-report-sites=all" "m.march" in
            Out_channel.with_open_bin f (fun oc -> output_string oc (src 2));
            let after = run_in ~dir "--check --refine-report-sites=all" "m.march" in
            expect before ~line:4 ~callee:"need" "proved";
            expect after ~line:4 ~callee:"need" "violated"));
  ]

(* The phase-1a review's REJECT rows (specs/progress/2026-10-30-reflection-
   phase1a.md, "Review fixes"): each program's obligation is false at run time
   (the interpreter output is in the comment), so it must never be proved. *)
let review =
  [ gated "review C-1: a parameter or local named like a reflected function is not that function" (fun () ->
        (* Interpreted: `51 51 51 11`. *)
        let out = run {|mod CL do
  needs IO.Console
  fn inc(n : Int) : Int do n + 1 end
  fn need2(x : {Int | _ == 2}) : Int do x end
  fn a(inc : Int -> Int) : Int do
    let r = inc(1)
    need2(r)
  end
  fn b(inc : Int -> Int) : Int do need2(inc(1)) end
  fn c() : Int do
    let inc = fn x -> x + 50
    let r = inc(1)
    need2(r)
  end
  fn d(inc : Int -> Int, y : Int) : Int do
    if inc(y) == 2 do need2(y + 1) else 0 end
  end
  fn main(_c : Cap(IO.Console)) do
    println("${a(fn x -> x + 50)} ${b(fn x -> x + 50)} ${c()} ${d(fn x -> 2, 10)}")
  end
end
|} in
        not_proved out ~line:7 ~callee:"need2";
        not_proved out ~line:9 ~callee:"need2";
        not_proved out ~line:13 ~callee:"need2";
        not_proved out ~line:16 ~callee:"need2");
    gated "review C-2: a qualified call in a nested module is the innermost module's function" (fun () ->
        (* Interpreted: `3 3 0 3`: inside `B`, `A.f` is `Top.B.A.f`, n + 2. *)
        let out = run {|mod Top do
  needs IO.Console
  mod A do
    fn f(n : Int) : Int do n + 1 end
  end
  mod B do
    mod A do
      fn f(n : Int) : Int do n + 2 end
    end
    fn need2(x : {Int | _ == 2}) : Int do x end
    fn a() : Int do
      let r = A.f(1)
      need2(r)
    end
    fn b() : Int do need2(A.f(1)) end
    fn c(x : Int) : Int do
      if A.f(x) == 2 do need2(x + 1) else 0 end
    end
    fn val() : Int do A.f(1) end
  end
  fn main(_c : Cap(IO.Console)) do
    println("${B.a()} ${B.b()} ${B.c(1)} ${B.val()}")
  end
end
|} in
        not_proved out ~line:13 ~callee:"B.need2";
        not_proved out ~line:15 ~callee:"B.need2";
        not_proved out ~line:17 ~callee:"B.need2");
    gated "review C-2: a predicate in a nested module names that module's function" (fun () ->
        (* Inside `Inner`, `f` is `Inner.f`, n + 2: `needf(2)` is false,
           `needf(3)` holds. *)
        let out = run {|mod Top do
  needs IO.Console
  fn f(n : Int) : Int do n + 1 end
  mod Inner do
    fn f(n : Int) : Int do n + 2 end
    fn needf(x : {Int | _ == f(1)}) : Int do x end
    fn a() : Int do needf(2) end
    fn b() : Int do needf(3) end
  end
end
|} in
        not_proved out ~line:7 ~callee:"Inner.needf";
        expect out ~line:8 ~callee:"Inner.needf" "proved");
    gated "review C-3: a user negate captures a literal -2 and negate(2)" (fun () ->
        (* Interpreted: `2 3 12`. *)
        let out = run {|mod NG do
  needs IO.Console
  fn negate(n : Int) : Int do n + 10 end
  fn h(n : Int) : Int do n / negate(2) end
  fn k(n : Int) : Int do n / -2 end
  fn needm12(x : {Int | _ == -12}) : Int do x end
  fn a() : Int do needm12(h(24)) end
  fn b() : Int do needm12(k(24)) end
  fn main(_c : Cap(IO.Console)) do
    println("${h(24)} ${k(24)} ${negate(2)}")
  end
end
|} in
        not_proved out ~line:7 ~callee:"needm12";
        not_proved out ~line:8 ~callee:"needm12");
    gated "review C-3: under a user negate, `-12` is not -12 and `n / -2` can divide by zero" (fun () ->
        (* Interpreted: `c()` prints 0, then `h(24)` panics dividing by zero.
           The predicate-side half predates reflection: `need_neg(-12)` was
           proved with `-12` read as the builtin.  In the predicate, `-12` is
           the user's `negate(12)` too (a predicate's names resolve where it
           is written), so `needm12(-12)` (0 == 0) may prove, but only
           through the user's function. *)
        let out = run ~args:"--check --refine-report-sites=all --reflect-report" {|mod NG do
  needs IO.Console
  fn negate(n : Int) : Int do 0 * n end
  fn h(n : Int) : Int do n / -2 end
  fn needm12(x : {Int | _ == -12}) : Int do x end
  fn c() : Int do needm12(-12) end
  fn need_neg(x : {Int | _ < 0}) : Int do x end
  fn d() : Int do need_neg(-12) end
  fn main(_c : Cap(IO.Console)) do
    println("${c()}")
    println("${h(24)}")
  end
end
|} in
        not_proved out ~line:8 ~callee:"need_neg";
        (match rows out ~line:6 ~callee:"needm12" with
         | rs when List.exists (fun (v, _) -> v = "proved") rs ->
           expect out ~line:6 ~callee:"needm12" "proved" ~uses:"negate"
         | _ -> ());
        if not (List.exists (fun l -> contains l "\th\tno\t") (lines out)) then
          Alcotest.failf "h divides by a user negate: it must not be reflected:\n%s" out) ]

(* The second review's REJECT rows: a name two declarations could denote. *)
let review2 =
  [ gated "review C-A: a nested `mod List` and the stdlib `List` are ambiguous; neither is unfolded" (fun () ->
        (* sl/: both backends print `3 3` for the library's call; slist2:
           interpreted 42, compiled 3 for the entry's own. *)
        let out = run_lib ~lib:[ ("y.march", {|mod Y do
  fn need42(x : {Int | _ == 42}) : Int do x end
  fn h() : Int do
    let r = List.sum_int([1, 2])
    need42(r)
  end
end
|}) ] {|mod M do
  needs IO.Console
  mod List do
    fn sum_int(xs : List(Int)) : Int do 42 end
  end
  fn need42(x : {Int | _ == 42}) : Int do x end
  fn need3(x : {Int | _ == 3}) : Int do x end
  fn a() : Int do
    let r = List.sum_int([1, 2])
    need42(r)
  end
  fn main(_c : Cap(IO.Console)) do
    println("${List.sum_int([1, 2])} ${Y.h()}")
  end
end
|} in
        not_proved ~file:"y.march" out ~line:5 ~callee:"need42";
        not_proved ~file:"m.march" out ~line:10 ~callee:"need42";
        let out2 = run {|mod M do
  needs IO.Console
  mod List do
    fn sum_int(xs : List(Int)) : Int do 42 end
  end
  fn need42(x : {Int | _ == 42}) : Int do x end
  fn need3(x : {Int | _ == 3}) : Int do x end
  fn a() : Int do
    let r = List.sum_int([1, 2])
    need42(r)
  end
  fn main(_c : Cap(IO.Console)) do
    println("${List.sum_int([1, 2])}")
  end
end
|} in
        not_proved out2 ~line:10 ~callee:"need42");
    gated "review C-A: a library `X` and a nested `M.X` are ambiguous; neither is unfolded" (fun () ->
        (* ml/: both backends give `X.g(1) = 2` in the library. *)
        let out = run_lib ~lib:[ ("x.march", {|mod X do
  @[opaque]
  fn g(n : Int) : Int do n + 1 end
end
|}); ("y.march", {|mod Y do
  fn need51(x : {Int | _ == 51}) : Int do x end
  fn h() : Int do
    let r = X.g(1)
    need51(r)
  end
end
|}) ] {|mod M do
  needs IO.Console
  mod X do
    fn g(n : Int) : Int do n + 50 end
  end
  fn need51(x : {Int | _ == 51}) : Int do x end
  fn need2(x : {Int | _ == 2}) : Int do x end
  fn a() : Int do
    let r = X.g(1)
    need51(r)
  end
  fn main(_c : Cap(IO.Console)) do
    println("a() = ${a()}, X.g(1) = ${X.g(1)}, Y.h() = ${Y.h()}")
  end
end
|} in
        not_proved ~file:"y.march" out ~line:5 ~callee:"need51");
    gated "review C-A: both `X.g`s reflectable: the program checks, no internal error" (fun () ->
        let out = run_lib ~lib:[ ("x.march", {|mod X do
  fn g(n : Int) : Int do n + 1 end
end
|}); ("y.march", {|mod Y do
  fn need51(x : {Int | _ == 51}) : Int do x end
  fn h() : Int do
    let r = X.g(1)
    need51(r)
  end
end
|}) ] {|mod M do
  needs IO.Console
  mod X do
    fn g(n : Int) : Int do n + 50 end
  end
  fn need51(x : {Int | _ == 51}) : Int do x end
  fn need2(x : {Int | _ == 2}) : Int do x end
  fn a() : Int do
    let r = X.g(1)
    need51(r)
  end
  fn main(_c : Cap(IO.Console)) do
    println("a() = ${a()}, X.g(1) = ${X.g(1)}, Y.h() = ${Y.h()}")
  end
end
|} in
        if contains out "internal error" || has_code out "internal_error" then
          Alcotest.failf "reflection must never fail a valid program:\n%s" out;
        not_proved ~file:"y.march" out ~line:5 ~callee:"need51";
        not_proved ~file:"m.march" out ~line:10 ~callee:"need51");
    gated "review C-B: an alias that a nested module of the same name also supplies is not unfolded" (fun () ->
        (* al1/m and m2: both backends give B.g(1) = 2 with `alias A as B`
           after `mod B` (the second places it before; compiled 2,
           interpreted 51). *)
        let out = run_lib ~lib:[ ("a.march", {|mod A do
  fn g(n : Int) : Int do n + 1 end
end
|}) ] {|mod M do
  needs IO.Console
  mod B do
    fn g(n : Int) : Int do n + 50 end
  end
  alias A as B
  fn need51(x : {Int | _ == 51}) : Int do x end
  fn a() : Int do
    let r = B.g(1)
    need51(r)
  end
  fn main(_c : Cap(IO.Console)) do
    println("a() = ${a()}, B.g(1) = ${B.g(1)}")
  end
end
|} in
        not_proved ~file:"m.march" out ~line:10 ~callee:"need51";
        let out2 = run_lib ~lib:[ ("a.march", {|mod A do
  fn g(n : Int) : Int do n + 1 end
end
|}) ] {|mod M do
  needs IO.Console
  alias A as B
  mod B do
    fn g(n : Int) : Int do n + 50 end
  end
  fn need51(x : {Int | _ == 51}) : Int do x end
  fn a() : Int do
    let r = B.g(1)
    need51(r)
  end
  fn main(_c : Cap(IO.Console)) do
    println("a() = ${a()}, B.g(1) = ${B.g(1)}")
  end
end
|} in
        not_proved ~file:"m.march" out2 ~line:10 ~callee:"need51") ]

(* The third review's REJECT rows: a reflected WRAPPER around an ambiguous
   name. *)
let review3 =
  [ gated "review3 C1: a wrapper around an ambiguous `X.g` is not reflected" (fun () ->
        (* Interpreted: `Y.w(1) = 2, k(1) = 51`. *)
        let out = run_lib ~lib:[ ("x.march", {|mod X do
  fn g(n : Int) : Int do n + 1 end
end
|}); ("y.march", {|mod Y do
  fn w(n : Int) : Int do X.g(n) end
end
|}) ] {|mod M do
  needs IO.Console
  mod X do
    fn g(n : Int) : Int do n + 50 end
  end
  fn k(n : Int) : Int do M.X.g(n) end
  fn need0(x : {Int | _ == 0}) : Int do x end
  fn a() : Int do
    let p = Y.w(1)
    let q = k(1)
    need0(p - q)
  end
  fn main(_c : Cap(IO.Console)) do
    println("Y.w(1) = ${Y.w(1)}, k(1) = ${k(1)}, M.X.g(1) = ${M.X.g(1)}")
  end
end
|} in
        not_proved ~file:"m.march" out ~line:11 ~callee:"need0");
    gated "review3 C1: a wrapper around an ambiguous `List.length` is not reflected" (fun () ->
        (* Interpreted: `2`.  The graph's guess for this ambiguous
           `List.length` happens to be the stdlib's, so the value proved
           before the fix agreed with the run; what was wrong is that `Y.w`
           was reflected at all.  The report row is the RED half. *)
        let out = run_lib ~args:"--check --refine-report-sites=all --reflect-report" ~lib:[ ("y.march", {|mod Y do
  fn w(xs : List(Int)) : Int do List.length(xs) end
end
|}) ] {|mod M do
  needs IO.Console
  mod List do
    fn length(xs : List(Int)) : Int do 42 end
  end
  fn need2(x : {Int | _ == 2}) : Int do x end
  fn need42(x : {Int | _ == 42}) : Int do x end
  fn a() : Int do
    let r = Y.w([1, 2])
    need42(r)
  end
  fn main(_c : Cap(IO.Console)) do
    println("${Y.w([1, 2])}")
  end
end
|} in
        not_proved ~file:"m.march" out ~line:10 ~callee:"need42";
        if not (List.exists (fun l -> contains l "\tY.w\tno\tR6:calls List.length, a name more than one declaration could denote") (lines out))
        then Alcotest.failf "Y.w must not be reflected (an ambiguous callee):\n%s" out);
    gated "review3 C1/I1: a stage-1 violation stays violated, and an error" (fun () ->
        (* Interpreted: `a(1) = 0` only because the else branch is not taken;
           `need0(1)` is a definite violation wherever it runs. *)
        let out = run_lib ~lib:[ ("x.march", {|mod X do
  fn g(n : Int) : Int do n + 1 end
end
|}); ("y.march", {|mod Y do
  fn w(n : Int) : Int do X.g(n) end
end
|}) ] {|mod M do
  needs IO.Console
  mod X do
    fn g(n : Int) : Int do n + 50 end
  end
  fn k(n : Int) : Int do M.X.g(n) end
  fn need0(x : {Int | _ == 0}) : Int do x end
  fn a(z : Int) : Int do
    if Y.w(z) == k(z) do 0 else need0(1) end
  end
  fn main(_c : Cap(IO.Console)) do
    println("a(1) = ${a(1)}")
  end
end
|} in
        expect ~file:"m.march" out ~line:9 ~callee:"need0" "violated";
        if not (has_code out "refinement_violated") then Alcotest.failf "the error must stay:\n%s" out) ]

(* `two_stage_identical` (§4.4, F9): stage 1 is today's query, byte for byte.
   Every query a reflection-off run sends to z3 is sent by a reflection-on run
   too, with the same text (a stage-2 query carries assumption literals and
   is the only kind that may be new). *)
let fixtures_dir () =
  let rec up d n =
    if n = 0 then None
    else
      let c = Filename.concat d "test/refine/reflect" in
      if Sys.file_exists c && Sys.is_directory c then Some c else up (Filename.dirname d) (n - 1)
  in
  up (Sys.getcwd ()) 8

let queries_of_log (path : string) : string list =
  if not (Sys.file_exists path) then []
  else
    let s = In_channel.with_open_bin path In_channel.input_all in
    let parts = String.split_on_char '\n' s in
    let blocks = ref [] and cur = Buffer.create 256 and inside = ref false in
    List.iter
      (fun l ->
        if l = ";; ==== sent" then begin
          if !inside then blocks := Buffer.contents cur :: !blocks;
          Buffer.clear cur;
          inside := true
        end
        else if String.starts_with ~prefix:";; ==== verdict" l then begin
          if !inside then blocks := Buffer.contents cur :: !blocks;
          Buffer.clear cur;
          inside := false
        end
        else if !inside then (Buffer.add_string cur l; Buffer.add_char cur '\n'))
      parts;
    List.sort_uniq compare !blocks

let identical =
  [ gated "two_stage_identical: every a1-c4 fixture's stage-1 queries are today's" (fun () ->
        match fixtures_dir () with
        | None -> Alcotest.skip ()
        | Some d ->
          let fs =
            Sys.readdir d |> Array.to_list
            |> List.filter (fun f ->
                   Filename.check_suffix f ".march" && List.mem f.[0] [ 'a'; 'b'; 'c' ])
            |> List.sort compare
          in
          List.iter
            (fun f ->
              let src = In_channel.with_open_bin (Filename.concat d f) In_channel.input_all in
              let log env =
                let dir = Filename.temp_dir "unfold_id" "" in
                Fun.protect ~finally:(fun () -> try remove_tree dir with _ -> ()) (fun () ->
                    Out_channel.with_open_bin (Filename.concat dir f) (fun oc -> output_string oc src);
                    let lg = Filename.concat dir "z3.log" in
                    ignore (run_in ~env:(env ^ " MARCH_REFINE_Z3_LOG=" ^ Filename.quote lg) ~dir "--check" f);
                    queries_of_log lg)
              in
              let off = log "MARCH_REFLECT=0" and on = log "" in
              let on1 = List.filter (fun q -> not (contains q "|$ru_")) on in
              (* A stage-2 rerun may also send queries with no reflected term
                 left in them (its sorts can differ); those are new, not
                 changed.  What must hold is that every query of today's run
                 is still sent, with the same text. *)
              let missing = List.filter (fun q -> not (List.mem q on1)) off in
              if off = [] then Alcotest.failf "%s: the reflection-off run sent no query (vacuous)" f;
              if missing <> [] then
                Alcotest.failf "%s: %d of today's %d queries are no longer sent byte for byte:\n%s" f
                  (List.length missing) (List.length off) (List.hd missing))
            fs) ]
