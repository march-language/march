(* Refinement reflection, phase 7: `--refine-infer` proposes lemma calls
   (specs/2026-10-29-refinement-reflection-design.md §10 "Phase 7"; the plan
   is specs/plans/2026-11-04-reflection-phase7-infer-lemmas-plan.md).

   Group `reflect-infer-lemma`.  Every case drives the REAL compiler through
   [Test_refine_unfold]'s helpers. *)

module U = Test_refine_unfold

let gated = U.gated
let contains = U.contains

let infer ?(args = "") src = U.run ~args:("--check --refine-infer " ^ args) src

let has out s = if not (contains out s) then Alcotest.failf "expected %S in:\n%s" s out
let lacks out s = if contains out s then Alcotest.failf "did not expect %S in:\n%s" s out

let cat =
  {|  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end
|}

let need_same = "  fn need_same(a : List(Int), b : {List(Int) | b == a}) : Int do 0 end\n"

let cat_nil =
  {|  @[lemma]
  fn cat_nil(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do
    match xs do
      Nil -> ()
      Cons(h, t) -> cat_nil(t)
    end
  end
|}

let len_cat =
  {|  @[lemma]
  fn len_cat(xs : List(Int), ys : List(Int)) : {Unit | len(cat(xs, ys)) == len(xs) + len(ys)} do
    match xs do
      Nil -> ()
      Cons(h, t) -> len_cat(t, ys)
    end
  end
|}

let m body = "mod M do\n" ^ body ^ "end\n"

let stdlib_rr =
  m
    (need_same
   ^ {|  fn use_it(xs : List(Int)) : Int do
    need_same(xs, List.reverse(List.reverse(xs)))
  end
|})

let tests =
  [ gated "stdlib lemma: List.reverse_reverse(xs) is proposed for reverse twice" (fun () ->
        let out = infer stdlib_rr in
        has out "inferred lemma calls: 1 proposed, 0 not inferred";
        has out "use_it (m.march:4)  List.reverse_reverse(xs)  [closes the precondition `b == a` on `need_same`");
    gated "user lemma: cat_nil(xs) is proposed, and not the lemma that does not help" (fun () ->
        let out =
          infer (m (cat ^ need_same ^ len_cat ^ cat_nil ^ "  fn f(xs : List(Int)) : Int do\n    need_same(xs, cat(xs, Nil))\n  end\n"))
        in
        has out "f (m.march:24)  cat_nil(xs)  [closes the precondition `b == a` on `need_same`";
        lacks out "len_cat(xs, Nil)  [");
    gated "a lemma that does not help is checked and not proposed; the skeleton is offered" (fun () ->
        let out = infer (m (cat ^ need_same ^ len_cat ^ "  fn f(xs : List(Int)) : Int do\n    need_same(xs, cat(xs, Nil))\n  end\n")) in
        has out "inferred lemma calls: 0 proposed, 1 not inferred";
        has out "f (m.march:17): no lemma call inferred for the precondition `b == a` on `need_same` (1 of 1 candidate checked)";
        has out "called as `f_lemma(xs)` before line 17";
        has out "fn f_lemma(xs : List(Int)) : {Unit | cat(xs, []) == xs} do");
    (* Two layers refuse this: [Infer_lemma.rebind]/[once], and the `assert`
       re-check (a goal built across the rebinding does not prove the target).
       With the first switched off the second still holds, so this pins the
       behaviour, not the first layer. *)
    gated "a shadowed name gives no skeleton (no `let` is substituted across its own rebinding)" (fun () ->
        let out =
          infer
            (m (cat ^ need_same ^ "  fn f(xs : List(Int)) : Int do\n    let xs = cat(xs, Nil)\n    need_same(xs, cat(xs, Nil))\n  end\n"))
        in
        has out "no lemma call inferred for the precondition `b == a` on `need_same`";
        lacks out "a lemma stating this");
    gated "two skeletons in one function get different names" (fun () ->
        let out =
          infer
            (m
               (cat ^ need_same
              ^ "  fn f(xs : List(Int), ys : List(Int)) : Int do\n    need_same(xs, cat(xs, Nil))\n    need_same(ys, cat(ys, Nil))\n  end\n"))
        in
        has out "called as `f_lemma(xs)`";
        has out "called as `f_lemma_2(ys)`");
    gated "REJECT control: a lemma whose precondition the call cannot prove is not proposed" (fun () ->
        let src pre =
          m
            (Printf.sprintf
               {|  fn need2(ys : {List(Int) | len(_) == 2}) : Int do 0 end
  fn f(xs : %s) : Int do
    need2(List.take(xs, 2))
  end
|}
               pre)
        in
        let out = infer (src "List(Int)") in
        lacks out "List.len_take(xs, 2)  [";
        let out = infer (src "{List(Int) | len(_) >= 2}") in
        has out "f (m.march:4)  List.len_take(xs, 2)  [closes the precondition `len(_) == 2` on `need2`");
    gated "postcondition: not a target (its check does not see the body's lemma facts)" (fun () ->
        let out =
          infer (m "  fn f(xs : List(Int)) : {List(Int) | len(_) == len(xs)} do\n    List.reverse(xs)\n  end\n")
        in
        lacks out "inferred lemma calls");
    gated "a let-bound term is in the pool" (fun () ->
        let out =
          infer
            (m (cat ^ need_same ^ cat_nil ^ "  fn f(xs : List(Int)) : Int do\n    let ys = cat(xs, Nil)\n    need_same(xs, ys)\n  end\n"))
        in
        has out "f (m.march:18)  cat_nil(xs)  [closes");
    gated "an arm body on the arrow's line: proposed, apply by hand" (fun () ->
        let out =
          infer
            (m
               (cat ^ need_same ^ cat_nil
              ^ {|  fn f(o : Option(List(Int))) : Int do
    match o do
      Some(xs) -> need_same(xs, cat(xs, Nil))
      None -> 0
    end
  end
|}))
        in
        has out "cat_nil(xs)  [closes";
        has out "(apply by hand: the statement does not start its own line)");
    gated "no reflection skip: no lemma block, and kinds without `lemma` turn it off" (fun () ->
        let out = infer (m (need_same ^ "  fn f(xs : List(Int)) : Int do need_same(xs, xs) end\n")) in
        lacks out "inferred lemma calls";
        let out = infer ~args:"--refine-infer-kinds=k1" stdlib_rr in
        lacks out "inferred lemma calls");
    gated "json: the call with its edit, the skeleton with none" (fun () ->
        let out = infer ~args:"--refine-infer-json" stdlib_rr in
        has out "\"lemma_calls\": [{\"kind\": \"lemma\", \"fn\": \"use_it\"";
        has out "\"call\": \"List.reverse_reverse(xs)\"";
        has out "\"text\": \"List.reverse_reverse(xs)\\n    \"";
        let out = infer ~args:"--refine-infer-json" (m (cat ^ need_same ^ "  fn f(xs : List(Int)) : Int do\n    need_same(xs, cat(xs, Nil))\n  end\n")) in
        has out "\"lemma_calls\": []";
        has out "\"skeleton\": {\"lemma\": \"@[lemma]\\nfn f_lemma(xs : List(Int)) : {Unit | cat(xs, []) == xs} do\\n  ()\\nend\", \"call\": \"f_lemma(xs)\"}");
    gated "apply: the call is written and the re-check matches the prediction" (fun () ->
        let dir = Filename.temp_dir "infer_lemma" "" in
        Fun.protect ~finally:(fun () -> try U.remove_tree dir with _ -> ()) @@ fun () ->
        let f = Filename.concat dir "m.march" in
        Out_channel.with_open_bin f (fun oc -> output_string oc stdlib_rr);
        let out = U.run_in ~dir "--check --refine-infer --refine-infer-apply" "m.march" in
        has out "applied 1 proposal(s) to 1 file(s); the re-check matches the prediction";
        let src = In_channel.with_open_bin f In_channel.input_all in
        has src "    List.reverse_reverse(xs)\n    need_same(xs, List.reverse(List.reverse(xs)))";
        let out = U.run_in ~dir "--check --refine-report-sites=all" "m.march" in
        U.expect out ~line:5 ~callee:"need_same" "proved") ]
