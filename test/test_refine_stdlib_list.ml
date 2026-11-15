(* Refinement reflection, phase 3: the stdlib `List` set
   (specs/2026-10-29-refinement-reflection-design.md §10 "Phase 3", D18).

   Group `reflect-stdlib-list`: user code calling the lemmas shipped in
   stdlib/list.march, the `filter` length contract, and the stdlib lemma
   manifest (stdlib/lemmas.verified).  Every case drives the REAL compiler
   through [Test_refine_unfold]'s helpers. *)

module U = Test_refine_unfold

let gated = U.gated
let run = U.run
let expect = U.expect
let contains = U.contains
let lines = U.lines

let needs =
  {|  fn need3(xs : {List(Int) | len(_) == 3}) : Int do 0 end
  fn need_eq(a : List(Int), b : {List(Int) | _ == a}) : Int do 0 end
  fn need_n(n : Int, ys : {List(Int) | len(_) == n}) : Int do 0 end
  fn need_le(xs : List(Int), ys : {List(Int) | len(_) <= len(xs)}) : Int do 0 end
|}

(* `mod U do` + [needs] is lines 1-5; a test's first function starts at 6. *)
let prog body = "mod U do\n" ^ needs ^ body ^ "end\n"

(* The stdlib lemma rows of a check: (verdict, lemma) for each postcondition
   row in stdlib/list.march. *)
let stdlib_lemma_rows out =
  List.filter_map
    (fun l ->
      match String.split_on_char '\t' l with
      | v :: "stdlib" :: loc :: rest when contains loc "list.march" -> (
        match v, rest with
        | "skip", _ :: "postcondition" :: c :: _ -> Some ("skip", c)
        | _, "postcondition" :: c :: _ -> Some (v, c)
        | _ -> None)
      | _ -> None)
    (lines out)

(* The 2026-11-15 laws pass: List accessors, Option, Result and Math.  A
   second header with its own needs, lines 1-6, so a test's first function
   starts at 7.  Each case checks the caller gets the fact with the lemma call
   and does not without it, so the lemma is what proves it. *)
let needs2 =
  {|  fn need3(xs : {List(Int) | len(_) == 3}) : Int do 0 end
  fn need_eq(a : List(Int), b : {List(Int) | _ == a}) : Int do 0 end
  fn need_eqi(a : Int, b : {Int | _ == a}) : Int do 0 end
  fn need_le1(xs : {List(Int) | len(_) <= 1}) : Int do 0 end
  fn need_some(o : {Option((Int, Int)) | is_Some(_)}) : Int do 0 end
|}

let prog2 body = "mod U do\n" ^ needs2 ^ body ^ "end\n"

(* [fn_head] at line 7, [setup] lines next, then the optional lemma call, then
   the need.  Returns the need's line with and without the lemma call. *)
let with_and_without ?(setup = []) ~fn_head ~lemma ~need ~callee () =
  let src calls = prog2 (String.concat "\n    " ((fn_head :: calls) @ setup @ [ need ]) ^ "\n  end\n") in
  let need_line with_lemma = 7 + (if with_lemma then 1 else 0) + List.length setup + 1 in
  let out = run (src [ lemma ]) in
  expect out ~line:(need_line true) ~callee "proved";
  let out = run (src []) in
  U.not_proved out ~line:(need_line false) ~callee

let laws_pass_tests =
  [ gated "std_drop_last_snoc: drop_last(append(xs, [x])) == xs" (fun () ->
        with_and_without ~fn_head:"  fn a(xs : List(Int), x : Int) : Int do"
          ~setup:[ "let ys = List.append(xs, Cons(x, Nil))" ]
          ~lemma:"List.drop_last_snoc(xs, x)" ~need:"need_eq(xs, List.drop_last(ys))" ~callee:"need_eq" ());
    gated "std_len_drop_last: drop_last of a non-empty list is one shorter" (fun () ->
        with_and_without ~fn_head:"  fn b(xs : {List(Int) | len(_) == 4}) : Int do"
          ~lemma:"List.len_drop_last(xs)" ~need:"need3(List.drop_last(xs))" ~callee:"need3" ());
    gated "std_option_zip_is_some: zip of two Somes is Some" (fun () ->
        with_and_without
          ~fn_head:"  fn c(oa : {Option(Int) | is_Some(_)}, ob : {Option(Int) | is_Some(_)}) : Int do"
          ~lemma:"Option.zip_is_some(oa, ob)" ~need:"need_some(Option.zip(oa, ob))" ~callee:"need_some" ());
    (* The next two hold by unfolding alone at a caller; the lemma states them as
       laws (forge doc, --law-coverage) and its call must still be accepted. *)
    gated "std_option_len_to_list: to_list has at most one element" (fun () ->
        let out =
          run (prog2 "  fn d(o : Option(Int)) : Int do\n    Option.len_to_list(o)\n    need_le1(Option.to_list(o))\n  end\n")
        in
        expect out ~line:9 ~callee:"need_le1" "proved");
    gated "std_math_clamp_int_idem: clamping twice is clamping once" (fun () ->
        let out =
          run
            (prog2
               "  fn e(x : Int, lo : Int, hi : {Int | _ >= lo}) : Int do\n    Math.clamp_int_idem(x, lo, hi)\n    need_eqi(Math.clamp_int(x, lo, hi), Math.clamp_int(Math.clamp_int(x, lo, hi), lo, hi))\n  end\n")
        in
        expect out ~line:8 ~callee:"Math.clamp_int_idem" "proved";
        expect out ~line:9 ~callee:"need_eqi" "proved") ]

let manifest_path () =
  Filename.concat (Filename.dirname (U.exe ())) "../stdlib/lemmas.verified"

let tests =
  [ gated "std_len_append: List.len_append gives the caller len(append) (without it: a skip)" (fun () ->
        let body call =
          "  fn a(xs : {List(Int) | len(_) == 1}, ys : {List(Int) | len(_) == 2}) : Int do\n" ^ call
          ^ "    need3(List.append(xs, ys))\n  end\n"
        in
        let out = run (prog (body "    List.len_append(xs, ys)\n")) in
        expect out ~line:8 ~callee:"need3" "proved";
        let out = run (prog (body "")) in
        U.not_proved out ~line:7 ~callee:"need3");
    gated "std_reverse_reverse: reverse(reverse(xs)) == xs from the accumulator lemma chain" (fun () ->
        let out =
          run (prog "  fn b(xs : List(Int)) : Int do\n    List.reverse_reverse(xs)\n    need_eq(xs, List.reverse(List.reverse(xs)))\n  end\n")
        in
        expect out ~line:8 ~callee:"need_eq" "proved");
    gated "std_take_drop: append(take(xs, n), drop(xs, n)) == xs" (fun () ->
        let out =
          run
            (prog
               "  fn c(xs : List(Int), n : Int) : Int do\n    List.take_drop(xs, n)\n    need_eq(xs, List.append(List.take(xs, n), List.drop(xs, n)))\n  end\n")
        in
        expect out ~line:8 ~callee:"need_eq" "proved");
    gated "std_len_take: len(take(xs, n)) == n for 0 <= n <= len(xs)" (fun () ->
        let out =
          run
            (prog
               "  fn d(xs : List(Int), n : {Int | _ >= 0 && _ <= len(xs)}) : Int do\n    List.len_take(xs, n)\n    need_n(n, List.take(xs, n))\n  end\n")
        in
        expect out ~line:7 ~callee:"List.len_take" "proved";
        expect out ~line:8 ~callee:"need_n" "proved");
    gated "std_len_take: an out-of-range n gives no fact (lemma_unproved_call)" (fun () ->
        let out =
          run
            (prog
               "  fn d(xs : List(Int), n : Int) : Int do\n    List.len_take(xs, n)\n    need_n(n, List.take(xs, n))\n  end\n")
        in
        if not (List.exists (fun l -> contains l "[lemma_unproved_call]") (lines out)) then
          Alcotest.failf "expected lemma_unproved_call:\n%s" out;
        U.not_proved out ~line:8 ~callee:"need_n");
    gated "std_filter_len: filter's proved length contract, len(_) <= len(xs)" (fun () ->
        let out = run (prog "  fn e(xs : List(Int)) : Int do need_le(xs, List.filter(xs, fn x -> x > 0)) end\n") in
        expect out ~line:6 ~callee:"need_le" "proved");
    gated "stdlib lemmas: every shipped lemma is admitted from the manifest (trusted, not re-proved)" (fun () ->
        let out = run "mod U do\n  fn f(n : Int) : Int do n end\nend\n" in
        let rows = stdlib_lemma_rows out in
        let lemmas =
          [ "append_nil"; "append_assoc"; "len_append"; "reverse_onto_append"; "reverse_append";
            "reverse_reverse"; "len_reverse_onto"; "len_reverse"; "len_take_onto"; "len_take"; "len_drop";
            "take_onto_drop"; "take_drop"; "is_empty_len"; "head_opt_nth_opt"; "head_opt_append";
            "reverse_onto_single"; "drop_last_snoc"; "len_drop_last" ]
        in
        List.iter
          (fun l ->
            if not (List.mem ("trusted", l) rows) then Alcotest.failf "%s is not admitted from the manifest:\n%s" l out;
            if List.exists (fun (v, c) -> c = l && v <> "trusted") rows then
              Alcotest.failf "%s was re-proved although the manifest matches" l)
          lemmas);
    gated "stdlib_lemma_manifest: a stale manifest entry makes the lemma prove again" (fun () ->
        let entries = In_channel.with_open_bin (manifest_path ()) In_channel.input_all in
        let wrong =
          String.split_on_char '\n' entries
          |> List.map (fun l ->
                 match String.split_on_char '\t' l with
                 | [ "List.len_append"; _ ] -> "List.len_append\t00000000000000000000000000000000"
                 | _ -> l)
          |> String.concat "\n"
        in
        let f = Filename.temp_file "lemmas" ".verified" in
        Out_channel.with_open_bin f (fun oc -> output_string oc wrong);
        Fun.protect ~finally:(fun () -> Sys.remove f) (fun () ->
            let out = run ~env:("MARCH_LEMMA_MANIFEST=" ^ Filename.quote f) "mod U do\n  fn f(n : Int) : Int do n end\nend\n" in
            let rows = stdlib_lemma_rows out in
            if not (List.mem ("proved", "len_append") rows) then
              Alcotest.failf "len_append must be proved again with a stale entry:\n%s" out;
            if not (List.mem ("trusted", "append_nil") rows) then
              Alcotest.failf "the other entries still admit their lemmas:\n%s" out));
    Alcotest.test_case "stdlib_lemma_manifest: stdlib/lemmas.verified is fresh" `Slow (fun () ->
        if not (U.z3_available ()) then Alcotest.skip ();
        let root = Test_helpers.march_project_root () in
        let out = Filename.temp_file "manifest" ".out" in
        let rc =
          Test_helpers.Sys.command
            (Printf.sprintf "cd %s && MARCH_BIN=%s scripts/gen-lemma-manifest.sh --check > %s 2>&1"
               (Filename.quote root) (Filename.quote (U.exe ())) (Filename.quote out))
        in
        let text = In_channel.with_open_bin out In_channel.input_all in
        Sys.remove out;
        if rc <> 0 then Alcotest.failf "stdlib/lemmas.verified is stale (run scripts/gen-lemma-manifest.sh):\n%s" text) ]
