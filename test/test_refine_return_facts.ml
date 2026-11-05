(* A function's own refined result type sees the facts of its body
   (todo 2026-11-03-return-contract-ignores-block-facts): earlier `let`s, the
   lemma calls and `assert`s before the result, and a reflected call as the
   result.  When the tail engine ([Refine_post.check_post]) leaves an `Int`
   result unproved, the body is walked again quietly and the predicate is
   checked at each tail as a call's precondition is, under the walk's facts.

   Group `return-block-facts`.  Every case drives the REAL compiler through
   [Test_refine_unfold]'s helpers. *)

module U = Test_refine_unfold

let gated = U.gated

(* Every postcondition row of [callee] at [line] has [verdict]: the walk's
   proof must replace the tail engine's skip, not sit beside it. *)
let only out ~line ~callee verdict =
  U.expect out ~line ~callee verdict;
  let rows = U.rows out ~line ~callee in
  if List.exists (fun (v, _) -> v <> verdict) rows then
    Alcotest.failf "%s at line %d: expected only %s, got [%s]\n%s" callee line verdict
      (String.concat "; " (List.map fst rows)) out

let twice =
  {|  @[reflect]
  fn twice(n : Int) : Int do n + n end

  @[lemma]
  fn twice_grows(n : {Int | _ >= 0}) : {Unit | twice(n) >= n} do () end
|}

let m body = "mod M do\n" ^ twice ^ body ^ "end\n"

(* Line 7 is the first line after [twice]. *)
let tests =
  [ gated "a let-bound result proves" (fun () ->
        let out = U.run (m "  fn grow(n : {Int | _ >= 0}) : {Int | _ >= n} do\n    let r = n + n\n    r\n  end\n") in
        only out ~line:7 ~callee:"grow" "proved");
    gated "a lemma call before a reflected result proves" (fun () ->
        let out =
          U.run (m "  fn grow(n : {Int | _ >= 0}) : {Int | _ >= n} do\n    twice_grows(n)\n    twice(n)\n  end\n")
        in
        only out ~line:7 ~callee:"grow" "proved");
    gated "a reflected call as the whole result proves" (fun () ->
        let out = U.run (m "  fn grow(n : {Int | _ >= 0}) : {Int | _ >= n} do\n    twice(n)\n  end\n") in
        only out ~line:7 ~callee:"grow" "proved");
    gated "an assert before the result proves" (fun () ->
        let out = U.run (m "  fn grow(n : Int) : {Int | _ >= n} do\n    assert n >= 0\n    n + n\n  end\n") in
        only out ~line:7 ~callee:"grow" "proved");
    gated "a result in each branch, after a let in one of them" (fun () ->
        let out =
          U.run
            (m
               "  fn grow(n : {Int | _ >= 0}, b : Bool) : {Int | _ >= n} do\n    if b do\n      let r = n + 1\n      r\n    else\n      n\n    end\n  end\n")
        in
        only out ~line:7 ~callee:"grow" "proved");
    gated "REJECT control: a false result contract is not proved" (fun () ->
        let out = U.run (m "  fn bad(n : {Int | _ >= 0}) : {Int | _ > n} do\n    let r = n + n\n    r\n  end\n") in
        U.not_proved out ~line:7 ~callee:"bad");
    gated "REJECT control: a parameter rebound in the body is not read as the parameter" (fun () ->
        let out = U.run (m "  fn bad(n : {Int | _ >= 0}) : {Int | _ >= n} do\n    let n = n - 5\n    n\n  end\n") in
        U.not_proved out ~line:7 ~callee:"bad");
    gated "REJECT control: an unproved lemma's call gives the result no fact" (fun () ->
        let out =
          U.run
            (m
               "  @[lemma]\n  fn bogus(n : Int) : {Unit | twice(n) >= n} do () end\n\n  fn g(n : Int) : {Int | _ >= n} do\n    bogus(n)\n    twice(n)\n  end\n")
        in
        U.not_proved out ~line:10 ~callee:"g");
    gated "REJECT control: a block-local fn calling a sibling local is not walked at module level" (fun () ->
        (* The sibling `uor` returns -5; read as the module's `uor` (which
           returns its default, 1) the local's `> 0` would prove. *)
        let out =
          U.run
            (m
               "  fn uor(o : Option(Int), d : {Int | _ > 0}) : {Int | _ > 0} do\n    match o do\n      Some(_) -> d\n      None -> d\n    end\n  end\n\n  fn go(o : Option(Int)) : Int do\n    fn uor(q : Option(Int), d : Int) : Int do 0 - 5 end\n    fn f(p : Option(Int)) : {Int | _ > 0} do uor(p, 1) end\n    f(o)\n  end\n")
        in
        U.not_proved out ~line:16 ~callee:"f");
    (* `@[opaque]`: no unfolding of `grow` at the caller, so only its proved
       contract can serve it. *)
    gated "a result proved this way is a fact at its callers" (fun () ->
        let out =
          U.run
            (m
               "  @[opaque]\n  fn grow(n : {Int | _ >= 0}) : {Int | _ >= n} do\n    let r = n + n\n    r\n  end\n\n  fn need_ge(a : Int, b : {Int | _ >= a}) : Int do 0 end\n\n  fn use_it(n : {Int | _ >= 0}) : Int do\n    need_ge(n, grow(n))\n  end\n")
        in
        only out ~line:8 ~callee:"grow" "proved";
        U.expect out ~line:16 ~callee:"need_ge" "proved") ]
