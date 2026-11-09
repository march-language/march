(* Refinement aliases with value parameters (lib/desugar/desugar.ml,
   "Refinement aliases"; specs/lang/refinement-types.md).

   - The worked example, test/refine/aliases/vec.march: `Vec(a, n)` and a
     `Matrix(r, c)` built from it; every obligation proved, and it runs.
   - A violation names the alias as written at the use (`expected
     Vec(Int, n)`), with the value that breaks it.
   - The alias expands wherever a refinement can be written: parameters,
     results, element types, record fields, `let` annotations, actor
     messages; a refinement of an alias is the conjunction.
   - Kinding: a value parameter is not a type, and a use passes each
     parameter the right kind. *)

module U = Test_refine_unfold

let fixture name =
  let f = Filename.concat (Filename.dirname Sys.executable_name) ("refine/aliases/" ^ name) in
  if Sys.file_exists f then f else "test/refine/aliases/" ^ name

let read f = In_channel.with_open_bin f In_channel.input_all

let user_rows out = String.split_on_char '\n' out |> List.filter (fun l -> U.contains l "\tuser\t")

let printed out want = List.exists (fun l -> String.trim l = want) (String.split_on_char '\n' out)

let has_all out frags = List.for_all (U.contains out) frags

(* [src] checks with every fragment of [frags] in its output. *)
let reports name ~frags src =
  U.gated name (fun () ->
      let out = U.run ~args:"--check" src in
      if not (has_all out frags) then
        Alcotest.failf "expected %s:\n%s" (String.concat " and " (List.map (Printf.sprintf "%S") frags)) out)

(* [src] is refused with [code] (no solver needed). *)
let rejected name ~code ~what src =
  Alcotest.test_case name `Quick (fun () ->
      let out = U.run ~args:"--check" src in
      if not (U.contains out ("[" ^ code ^ "]") && U.contains out what) then
        Alcotest.failf "expected [%s] naming %S:\n%s" code what out)

let vec = "  type Vec(a, n : Int) = {List(a) | len(_) == n}\n"
let matrix = "  type Matrix(r : Int, c : Int) = {List(Vec(Int, c)) | len(_) == r}\n"

let worked_example =
  [ U.gated "worked example: every obligation proved" (fun () ->
        let out = U.run (read (fixture "vec.march")) in
        let rows = user_rows out in
        if List.length rows <> 11 || List.exists (fun l -> not (String.starts_with ~prefix:"proved\t" l)) rows
           || U.contains out "[refinement_unverified]" || U.contains out "[alias_kind_mismatch]"
        then Alcotest.failf "expected 11 proved user obligations:\n%s" out);
    Alcotest.test_case "worked example runs" `Quick (fun () ->
        let out = U.run ~args:"" (read (fixture "vec.march")) in
        if not (printed out "30" && printed out "2") then Alcotest.failf "expected 30 and 2:\n%s" out) ]

let violations =
  [ reports "mismatched lengths name the alias and the value"
      ~frags:[ "expected Vec(Int, n)"; "[refinement_violated]"; "`[4, 5]`" ]
      ("mod K do\n" ^ vec
       ^ "  fn dot(n : Int, xs : Vec(Int, n), ys : Vec(Int, n)) : Int do List.length(xs) + List.length(ys) end\n\
          \  fn short() : Int do dot(3, [1, 2, 3], [4, 5]) end\nend\n");
    reports "a literal argument" ~frags:[ "expected Vec(Int, 3)"; "[refinement_violated]" ]
      ("mod K do\n" ^ vec
       ^ "  fn three(xs : Vec(Int, 3)) : Int do List.length(xs) end\n  fn bad() : Int do three([1]) end\nend\n");
    reports "a ragged matrix row" ~frags:[ "expected Vec(Int, c)"; "[refinement_violated]" ]
      ("mod K do\n" ^ vec ^ matrix
       ^ "  fn rows(r : Int, c : Int, m : Matrix(r, c)) : Int do List.length(m) end\n\
          \  fn ragged() : Int do rows(2, 3, [[1, 2, 3], [4, 5]]) end\nend\n");
    U.gated "the result: `Vec(Int, n + 1)`" (fun () ->
        let out =
          U.run
            ("mod K do\n" ^ vec
             ^ "  fn push(n : Int, x : Int, xs : Vec(Int, n)) : Vec(Int, n + 1) do Cons(x, xs) end\n\
                \  fn wrong(n : Int, x : Int, xs : Vec(Int, n)) : Vec(Int, n + 2) do Cons(x, xs) end\nend\n")
        in
        let rows = user_rows out in
        let row f = List.find_opt (fun l -> U.contains l ("\t" ^ f ^ "\t")) rows in
        match row "push", row "wrong" with
        | Some p, Some w when String.starts_with ~prefix:"proved\t" p && not (String.starts_with ~prefix:"proved\t" w) -> ()
        | _ -> Alcotest.failf "expected push proved and wrong refused:\n%s" out);
    reports "a record field" ~frags:[ "expected Pos"; "[refinement_violated]" ]
      "mod K do\n  type Pos = {Int | _ > 0}\n  type Box = { size : Pos }\n  fn mk() : Box do { size: 0 } end\nend\n";
    reports "a `let` annotation" ~frags:[ "expected Pos"; "[refinement_violated]" ]
      "mod K do\n  type Pos = {Int | _ > 0}\n  fn f() : Int do\n    let p : Pos = 0\n    p\n  end\nend\n";
    reports "an actor message" ~frags:[ "expected Pos"; "[refinement_violated]" ]
      "mod K do\n  type Pos = {Int | _ > 0}\n  actor Counter do\n    state { n : Int }\n    init { n: 0 }\n    on Bump(k : Pos) do { n: state.n + k } end\n  end\n  fn f() : Unit do\n    let c = spawn(Counter)\n    let _ = send(c, Bump(0))\n    ()\n  end\nend\n";
    reports "an element type" ~frags:[ "expected Pos"; "[refinement_violated]" ]
      "mod K do\n  type Pos = {Int | _ > 0}\n  fn total(xs : List(Pos)) : Int do List.length(xs) end\n  fn f() : Int do total([1, 0]) end\nend\n";
    reports "a refinement of an alias is both" ~frags:[ "len(_) == 3 && len(_) > 5"; "[refinement_violated]" ]
      ("mod K do\n" ^ vec
       ^ "  fn f(xs : {Vec(Int, 3) | len(_) > 5}) : Int do List.length(xs) end\n  fn g() : Int do f([1, 2, 3]) end\nend\n");
    reports "a named binder" ~frags:[ "expected Pos"; "[refinement_violated]" ]
      "mod K do\n  type Pos = {v : Int | v > 0}\n  fn need(p : Pos) : Int do p end\n  fn bad() : Int do need(0) end\nend\n" ]

let kinds =
  [ rejected "a value parameter used as a type" ~code:"alias_kind_mismatch" ~what:"not as a type"
      "mod K do\n  type Bad(n : Int) = {List(n) | len(_) == 0}\nend\n";
    rejected "a type passed for a value" ~code:"alias_kind_mismatch" ~what:"is a value parameter"
      ("mod K do\n" ^ vec ^ "  fn f(xs : Vec(Int, String)) : Int do List.length(xs) end\nend\n");
    rejected "a value passed for a type" ~code:"alias_kind_mismatch" ~what:"is a type parameter"
      ("mod K do\n" ^ vec ^ "  fn f(xs : Vec(3, 3)) : Int do List.length(xs) end\nend\n");
    rejected "the wrong number of arguments" ~code:"type_arity" ~what:"takes 2 parameters"
      ("mod K do\n" ^ vec ^ "  fn f(xs : Vec(Int)) : Int do List.length(xs) end\nend\n");
    rejected "a value parameter on a variant type" ~code:"parse_error" ~what:"only a refinement alias"
      "mod K do\n  type T(n : Int) = A | B\nend\n";
    Alcotest.test_case "the arity error is reported once" `Quick (fun () ->
        let out = U.run ~args:"--check" ("mod K do\n" ^ vec ^ "  fn f(xs : Vec(Int)) : Int do 0 end\nend\n") in
        let n = List.length (String.split_on_char '\n' out |> List.filter (fun l -> U.contains l "[type_arity]")) in
        if n <> 1 then Alcotest.failf "expected one [type_arity], got %d:\n%s" n out) ]

let tooling =
  [ Alcotest.test_case "formatter keeps value parameters" `Quick (fun () ->
        let dir = Filename.temp_dir "aliasfmt" "" in
        let src = "mod K do\n  type Vec(a, n : Int) = {List(a) | len(_) == n}\n  type Pos = {v : Int | v > 0}\nend\n" in
        let out =
          Fun.protect ~finally:(fun () -> try U.remove_tree dir with _ -> ()) (fun () ->
              let f = Filename.concat dir "m.march" in
              Out_channel.with_open_bin f (fun oc -> output_string oc src);
              ignore (U.run_in ~dir "--fmt --check" "m.march");
              let once = read f in
              ignore (U.run_in ~dir "--fmt --check" "m.march");
              if read f <> once then Alcotest.failf "--fmt is not idempotent:\n%s\n---\n%s" once (read f);
              once)
        in
        List.iter
          (fun frag -> if not (U.contains out frag) then Alcotest.failf "--fmt lost %S:\n%s" frag out)
          [ "type Vec(a, n : Int) = { List(a) | len(_) == n }"; "type Pos = { v : Int | v > 0 }" ]) ]

let tests = worked_example @ violations @ kinds @ tooling
