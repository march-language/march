module U = Test_refine_unfold

let lemma predicate =
  "mod Q do\n  @[lemma]\n  fn law() : {Unit | " ^ predicate ^ "} do () end\nend\n"

let proved name predicate = U.gated name (fun () ->
  let out = U.run ~args:"--check --refine-report-sites=all" (lemma predicate) in
  if U.contains out "[syntax_error]" || U.contains out "[lemma_unproved]"
     || U.contains out "[refinement_unchecked]" || U.contains out "[invalid_lemma]"
     || not (U.contains out "proved\tuser\t") then
    Alcotest.failf "expected proved bounded predicate:\n%s" out)

let unproved name predicate = U.gated name (fun () ->
  let out = U.run ~args:"--check" (lemma predicate) in
  if not (U.contains out "[lemma_unproved]") then
    Alcotest.failf "expected unproved bounded predicate:\n%s" out)

let prepend = {|mod Q do
  @[lemma]
  fn prepend(h : Int, t : {List(Int) | (forall i in 0..len(_) - 1, nth(_, i) <= nth(_, i + 1)) && (forall i in 0..len(_), h <= nth(_, i))}) : {Unit | forall i in 0..len(Cons(h, t)) - 1, nth(Cons(h, t), i) <= nth(Cons(h, t), i + 1)} do
    ()
  end
end
|}

let tests = [
  U.gated "quantified insertion sort contracts" (fun () ->
    let file = Filename.concat (Filename.dirname Sys.executable_name) "refine/quantifiers/insertion_sort.march" in
    let file = if Sys.file_exists file then file else "test/refine/quantifiers/insertion_sort.march" in
    let out = U.run (In_channel.with_open_bin file In_channel.input_all) in
    let rows = String.split_on_char '\n' out |> List.filter (fun l -> U.contains l "\tuser\t") in
    if List.length rows <> 7 || List.exists (fun l -> not (String.starts_with ~prefix:"proved\t" l)) rows
      || U.contains out "[refinement_unverified]" then
      Alcotest.failf "expected all insertion-sort contracts proved:\n%s" out);
  U.gated "Boolean map keys retain their sort" (fun () ->
    let out = U.run "mod Q do @[lemma] fn law(m : Map(Bool, Int)) : {Unit | forall k in keys(m), k || !k} do () end end" in
    if U.contains out "[lemma_unproved]" || not (U.contains out "proved\tuser\t") then
      Alcotest.failf "expected Boolean key domain:\n%s" out);
  U.gated "Boolean keys cannot become integers" (fun () ->
    let out = U.run "mod Q do @[lemma] fn law(m : Map(Bool, Int)) : {Unit | forall k in keys(m), k + 0 == k} do () end end" in
    if not (U.contains out "[lemma_unproved]") then Alcotest.failf "ill-sorted quantified keys proved:\n%s" out);
  U.gated "unsupported Float list cannot become integer" (fun () ->
    let out = U.run "mod Q do @[lemma] fn law(xs : List(Float)) : {Unit | forall x in elts(xs), x == x} do () end end" in
    if not (U.contains out "[lemma_unproved]") then Alcotest.failf "Float reflexivity must not prove for NaN:\n%s" out);
  U.gated "witness named inside proof hints" (fun () ->
    let out = U.run "mod Q do fn law() do assert (exists i in -3..3, i * i == 4) by do let k = 2 assert k >= -3 && k < 3 assert k * k == 4 end end end" in
    if U.contains out "[proof_unproved]" || U.contains out "[syntax_error]" || not (U.contains out "proved\tuser\t") then
      Alcotest.failf "expected checked explicit witness:\n%s" out);
  proved "Boolean indexed value" "forall i in 0..1, nth([true], i)";
  (* A measure over a call whose argument is the binder must not collapse
     every instance into one constant (contradictory -> vacuous proof). *)
  U.gated "binder-dependent call cannot become one constant" (fun () ->
    let out = U.run ~args:"--check --refine-report-sites=all" {|mod Q do
  fn mk(x : Int) : {List(Int) | elts(_) == elts([x])} do [x] end
  fn g(u : {Int | forall k in 0..3, member(k, elts(mk(k)))}) : {Int | _ == 99} do u end
  fn h(u : {Int | forall k in 0..3, len(mk(k)) == k}) : {Int | _ == 99} do u end
end
|} in
    let rows = String.split_on_char '\n' out
      |> List.filter (fun l -> U.contains l "\tuser\t" && U.contains l "_ == 99") in
    if List.length rows <> 2 || List.exists (fun l -> String.starts_with ~prefix:"proved\t" l) rows then
      Alcotest.failf "binder-dependent call must not prove a false postcondition:\n%s" out);

  Alcotest.test_case "synthetic binder spans cannot capture" `Quick (fun () ->
    let module A = March_ast.Ast in
    let module B = March_ast.Bounded_pred in
    let module S = March_refine.Smt in
    let sp = A.dummy_span in
    let name txt = {A.txt; span = sp} in
    let v txt = A.EVar (name txt) in
    let q binder body = B.make {kind = B.Forall; binder = name binder;
      domain = B.Range (A.ELit (A.LitInt 0, sp), A.ELit (A.LitInt 2, sp)); body; span = sp} in
    let expr = q "i" (q "j" (A.EApp (v "==", [v "i"; v "j"], sp))) in
    match March_refinecheck.Refine_scope.smt_of ~resolve_var:(fun _ -> None)
      ~resolve_measure:(fun _ _ -> None) expr with
    | Some (S.Quant (_, outer, _, _, S.Quant (_, inner, _, _, S.Eq (S.Const a, S.Const b))))
      when outer <> inner && a = outer && b = inner -> ()
    | _ -> Alcotest.fail "nested synthetic binders captured one another");

  U.gated "sorted prepend from quantified assumptions" (fun () ->
    let out = U.run prepend in
    if not (U.contains out "proved\tuser\t") || U.contains out "[lemma_unproved]" then
      Alcotest.failf "expected sorted prepend proof:\n%s" out);

  proved "boolean membership binder" "forall x in elts([true]), x";
  unproved "false boolean membership binder" "forall x in elts([true, false]), x";
  proved "short circuit guards indexing" "forall i in -1..3, i < 0 || i >= 2 || nth([1, 2], i) > 0";
  unproved "short circuit cannot guard earlier indexing" "forall i in -1..3, nth([1, 2], i) > 0 || i < 0";
  proved "negated empty existential" "not (exists i in 0..0, true)";
  unproved "existential hidden in equality needs witness" "(exists i in -3..3, i * i == 4) == true";

  unproved "existential needs a candidate witness" "exists i in -3..3, i * i == 4";
  U.gated "runtime quantifier rejected clearly" (fun () ->
    let out = U.run ~args:"--check" "mod Q do fn bad() do forall i in 0..2, i >= 0 end end" in
    if not (U.contains out "predicate-only") then Alcotest.failf "expected logical-only diagnostic:\n%s" out);
  U.gated "quantified proof assertion" (fun () ->
    let out = U.run ~args:"--check" {|mod Q do
      fn law() do assert (forall i in 0..3, i >= 0) by do () end end
    end|} in
    if U.contains out "[" then Alcotest.failf "expected clean proof assertion:\n%s" out);

  proved "indexed literal" "forall i in 0..2, nth([1, 2], i) >= 1";
  unproved "invalid indexed universal" "forall i in 0..3, nth([1, 2], i) >= 1";
  unproved "invalid indexed existential" "exists i in 0..2, nth([7], i) == 7";
  unproved "negation cannot hide invalid indexing" "not (nth([7], 1) == 0)";
  proved "literal membership" "forall x in elts([1, 2]), x >= 1";
  unproved "false literal membership" "forall x in elts([1, 2]), x > 1";

  proved "bounded range proves arithmetic" "forall i in 0..4, i >= 0";
  unproved "false universal is not proved" "forall i in 0..4, i > 0";
  proved "empty universal" "forall i in 0..0, false";
  proved "reversed universal" "forall i in 4..0, false";
  proved "negative bounds" "forall i in -3..0, i < 0";
  proved "nested shadowing" "forall i in 0..2, (forall i in i..2, i >= 0)";
  proved "existential concrete witness" "exists i in 0..4, i == 2";
  unproved "empty existential" "exists i in 0..0, true";
  unproved "false existential" "exists i in 0..4, i == 5";
]
