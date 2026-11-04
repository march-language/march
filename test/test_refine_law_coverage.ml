(* Law coverage and law strength (specs/2026-11-04-law-coverage-design.md; the plan is
   specs/plans/2026-11-04-law-coverage-plan.md).

   Group `law-coverage`.  Every case drives the REAL compiler through
   [Test_refine_unfold]'s helpers (a private HOME and a fresh project directory per
   run) and asserts the printed report lines. *)

module U = Test_refine_unfold
module L = Test_refine_lemma

let gated = U.gated
let contains = U.contains
let lines = U.lines

let coverage ?(env = "") ?(args = "--check --law-coverage") src = U.run ~env ~args src

let m body = "mod M do\n" ^ body ^ "end\n"

let has out l = List.exists (fun x -> x = l || String.starts_with ~prefix:l x) (lines out)

let expect out l =
  if not (has out l) then Alcotest.failf "expected a line starting %S in:\n%s" l out

let expect_no out l = if has out l then Alcotest.failf "expected no line starting %S in:\n%s" l out

let line_of out prefix = List.find_opt (String.starts_with ~prefix) (lines out)

let ends_with out prefix suffix =
  match line_of out prefix with
  | Some l when String.ends_with ~suffix l -> ()
  | Some l -> Alcotest.failf "line %S should end %S" l suffix
  | None -> Alcotest.failf "no line starting %S in:\n%s" prefix out

let rev_only_bad =
  {|  @[lemma]
  fn bad(xs : List(a)) : {Unit | rev(xs) == xs} do () end
|}

let tests =
  [ gated "covered_uncovered: a law's theorem covers what it calls" (fun () ->
        let out = coverage (m (L.defs4_6 ^ L.cat_nil)) in
        ends_with out "  covered  cat  " "(cat_nil)";
        expect out "  uncovered (public)  rev  ";
        expect out "law coverage: M: ");
    gated "unproved_only: a law the checker does not admit covers nothing" (fun () ->
        let out = coverage (m (L.defs4_6 ^ L.cat_nil ^ rev_only_bad)) in
        ends_with out "  unproved only  rev  " "(bad)";
        if not (contains out "(1 more only by unproved laws)") then
          Alcotest.failf "the summary counts the unproved-only function apart:\n%s" out);
    gated "private_fn: a pfn with no law is uncovered (private)" (fun () ->
        let out = coverage (m ("  pfn helper(n : Int) : Int do n + 1 end\n" ^ L.defs4_6 ^ L.cat_nil)) in
        expect out "  uncovered (private)  helper  ");
    gated "proof_only_call: a call in the proof body does not cover" (fun () ->
        let src =
          m
            (L.defs4_6
            ^ {|  pfn helper(xs : List(a)) : List(a) do xs end
  @[lemma]
  fn cat_nil(xs : List(a)) : {Unit | cat(xs, Nil) == xs} do
    match xs do
      Nil -> ()
      Cons(_, t) ->
        assert helper(t) == t
        cat_nil(t)
    end
  end
|})
        in
        let out = coverage src in
        expect out "  uncovered (private)  helper  ");
    gated "lemmas_not_listed: a lemma is not a function to cover" (fun () ->
        let out = coverage (m (L.defs4_6 ^ L.cat_nil)) in
        List.iter
          (fun l ->
            if String.starts_with ~prefix:"  " l && contains l "  cat_nil  " then
              Alcotest.failf "a lemma was listed as a function: %S" l)
          (lines out));
    gated "no_lemmas: every pure function is uncovered" (fun () ->
        let out =
          coverage (m "  fn f(n : Int) : Int do n + 1 end\n  fn g(n : Int) : Int do n * 2 end\n")
        in
        expect out "law coverage: M: 0 of 2 pure functions have a law";
        expect out "  uncovered (public)  f  ";
        expect out "  uncovered (public)  g  ");
    gated "qualified_stdlib_call: a stdlib function in a theorem is not listed" (fun () ->
        let src =
          m
            {|  fn f(xs : List(Int)) : List(Int) do xs end
  @[lemma]
  fn f_id(xs : List(Int)) : {Unit | List.append(f(xs), Nil) == List.append(xs, Nil)} do () end
|}
        in
        let out = coverage src in
        ends_with out "  covered  f  " "(f_id)";
        expect_no out "  covered  append";
        expect_no out "  uncovered (public)  append");
    gated "warm_cache: a second run still prints the report" (fun () ->
        let dir = Filename.temp_dir "lawcov" "" in
        let f = Filename.concat dir "m.march" in
        Out_channel.with_open_bin f (fun oc -> output_string oc (m (L.defs4_6 ^ L.cat_nil)));
        let a = U.run_in ~dir "--check --law-coverage" "m.march" in
        let b = U.run_in ~dir "--check --law-coverage" "m.march" in
        expect a "law coverage: M: ";
        expect b "law coverage: M: ");
    gated "absent_without_flag: plain --check prints no report" (fun () ->
        let out = coverage ~args:"--check" (m (L.defs4_6 ^ L.cat_nil)) in
        if contains out "law coverage" then Alcotest.failf "no report without the flag:\n%s" out) ]
