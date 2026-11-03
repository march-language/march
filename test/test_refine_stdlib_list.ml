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
            "take_onto_drop"; "take_drop" ]
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
