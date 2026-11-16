(* Two-state specs: handler guarantees (`on Msg(…) ensures P do … end`,
   specs/lang/actors.md "Handler guarantees"; Refine_check's DActor arm,
   step (5); lib/desugar/two_state.ml).

   - A guarantee is proved per handler: `state` and the bare fields read the
     returned state, `old(e)` the incoming one, the message's parameters are
     in scope, and the `@invariant` is assumed of the incoming state.
   - A wrong handler is refused with the incoming state, the arguments and
     the state the handler returns.
   - `--guarantees` lists each guarantee beside the invariant.
   - `old` is refused outside a guarantee's refinements, and `ensures` stays
     an ordinary name everywhere but a handler header. *)

module U = Test_refine_unfold

(* Columns in `--guarantees` are padded, so compare with runs of spaces
   squeezed to one. *)
let squeeze s =
  let b = Buffer.create (String.length s) in
  String.iteri (fun i c -> if not (c = ' ' && i > 0 && s.[i - 1] = ' ') then Buffer.add_char b c) s;
  Buffer.contents b

let has_all out frags = List.for_all (fun f -> U.contains (squeeze out) (squeeze f)) frags

let reports name ~frags ?(args = "--check") src =
  U.gated name (fun () ->
      let out = U.run ~args src in
      if not (has_all out frags) then
        Alcotest.failf "expected %s:\n%s" (String.concat " and " (List.map (Printf.sprintf "%S") frags)) out)

(* [src] checks clean: no diagnostic at all, and every fragment of [frags]
   in its `--guarantees` report. *)
let proves name ~frags src =
  U.gated name (fun () ->
      let out = U.run ~args:"--check" src in
      if String.trim out <> "" then Alcotest.failf "expected a clean check:\n%s" out;
      let g = U.run ~args:"--guarantees" src in
      if not (has_all g frags) then
        Alcotest.failf "expected %s in --guarantees:\n%s"
          (String.concat " and " (List.map (Printf.sprintf "%S") frags)) g)

let rejected name ~what src =
  Alcotest.test_case name `Quick (fun () ->
      let out = U.run ~args:"--check" src in
      if not (U.contains out "[old_misuse]" && U.contains out what) then
        Alcotest.failf "expected [old_misuse] saying %S:\n%s" what out)

let account extra =
  "mod Bank do\n\
  \  @invariant(balance >= 0)\n\
  \  actor Account do\n\
  \    state { balance : Int }\n\
  \    init { balance: 0 }\n\
  \    on Deposit(n : {Int | _ > 0}) ensures state.balance == old(state.balance) + n do\n\
  \      { balance: state.balance + n }\n\
  \    end\n\
  \    on Withdraw(n : Int) ensures state.balance <= old(state.balance) do\n\
  \      if n > 0 && n <= state.balance do { balance: state.balance - n } else state end\n\
  \    end\n" ^ extra ^ "\
  \  end\n\
  \  fn main() : Unit do\n\
  \    let a = spawn(Account)\n\
  \    let _ = send(a, Deposit(5))\n\
  \    ()\n\
  \  end\n\
  end\n"

let counter extra =
  "mod M do\n\
  \  actor Counter do\n\
  \    state { count : Int, limit : Int }\n\
  \    init { count: 0, limit: 10 }\n" ^ extra ^ "  end\nend\n"

let proved =
  [ proves "deposit and withdraw are proved, and listed"
      ~frags:[ "@invariant"; "ensures on Deposit   proved"; "ensures on Withdraw  proved" ]
      (account "");
    proves "a call handler keeps its state"
      ~frags:[ "ensures on Get  proved" ]
      (counter
         "    on Get(reply_to : Pid(Int)) ensures state == old(state) do\n\
         \      Actor.reply(reply_to, state.count)\n\
         \      state\n\
         \    end\n");
    proves "bare fields, and a parameter that shadows a field"
      ~frags:[ "ensures on Set  proved"; "ensures on Bump  proved" ]
      (counter
         "    on Set(count : Int) ensures state.count == count && limit == old(limit) do\n\
         \      { count: count, limit: state.limit }\n\
         \    end\n\
         \    on Bump() ensures count == old(count) + 1 do\n\
         \      { count: state.count + 1, limit: state.limit }\n\
         \    end\n");
    proves "the invariant is assumed of the incoming state"
      ~frags:[ "ensures on Zero  proved" ]
      "mod M do\n\
      \  @invariant(n >= 0)\n\
      \  actor C do\n\
      \    state { n : Int }\n\
      \    init { n: 0 }\n\
      \    on Zero() ensures n <= old(n) do { n: 0 } end\n\
      \  end\n\
      end\n";
    Alcotest.test_case "the guarantee is erased: the program runs" `Quick (fun () ->
        let src =
          "mod M do\n\
          \  needs IO.Console\n\
          \  actor C do\n\
          \    state { n : Int }\n\
          \    init { n: 0 }\n\
          \    on Inc(k : Int) ensures n == old(n) + k do\n\
          \      { n: state.n + k }\n\
          \    end\n\
          \  end\n\
          \  fn main(_c : Cap(IO.Console)) : Unit do\n\
          \    let c = spawn(C)\n\
          \    Actor.cast(c, Inc(2))\n\
          \    run_until_idle()\n\
          \    println(\"ran\")\n\
          \  end\n\
          end\n"
        in
        let out = U.run ~args:"" src in
        if not (U.contains out "ran") then Alcotest.failf "expected it to run:\n%s" out) ]

let violated =
  [ reports "a wrong handler shows both states"
      ~frags:
        [ "`Account`'s handler `Steal` does not guarantee its `ensures`.";
          "[return_refinement_violated]"; "balance <= old(balance)"; "state = { balance: 0 }"; "n = 1";
          "and the handler returns:"; "{ balance: 1 }" ]
      (account
         "    on Steal(n : {Int | _ > 0}) ensures balance <= old(balance) do\n\
         \      { balance: state.balance + n }\n\
         \    end\n");
    reports "without the invariant, the incoming state is any state"
      ~frags:[ "`C`'s handler `Zero` does not guarantee its `ensures`." ]
      "mod M do\n\
      \  actor C do\n\
      \    state { n : Int }\n\
      \    init { n: 0 }\n\
      \    on Zero() ensures n <= old(n) do { n: 0 } end\n\
      \  end\n\
      end\n";
    reports "a call handler that changes its state"
      ~frags:[ "`Counter`'s handler `Get` does not guarantee its `ensures`."; "state == old(state)" ]
      (counter
         "    on Get(reply_to : Pid(Int)) ensures state == old(state) do\n\
         \      Actor.reply(reply_to, state.count)\n\
         \      { count: state.count + 1, limit: state.limit }\n\
         \    end\n");
    reports "the parameter, not the field, when they share a name"
      ~frags:[ "`Counter`'s handler `Set` does not guarantee its `ensures`." ]
      (counter
         "    on Set(count : Int) ensures count == 0 do\n\
         \      { count: 0, limit: state.limit }\n\
         \    end\n") ]

let misuse =
  [ rejected "`old` in an @invariant" ~what:"cannot be used in an `@invariant`"
      "mod M do\n  @invariant(n >= old(n))\n  actor C do\n    state { n : Int }\n    init { n: 0 }\n  end\nend\n";
    rejected "`old` in a function's type" ~what:"cannot be used in a function's type"
      "mod M do\n  fn f(x : Int) : {Int | _ >= old(x)} do x end\nend\n";
    rejected "`old` in a message parameter's type" ~what:"cannot be used in a message parameter's type"
      "mod M do\n  actor C do\n    state { n : Int }\n    init { n: 0 }\n    on Set(k : {Int | _ > old(0)}) do state end\n  end\nend\n";
    rejected "`old` on its own in a guarantee" ~what:"`old` on its own does not name a value"
      "mod M do\n  actor C do\n    state { n : Int }\n    init { n: 0 }\n    on Inc() ensures n >= old do state end\n  end\nend\n";
    rejected "`old` with two arguments" ~what:"takes exactly one expression, but this passes 2"
      "mod M do\n  actor C do\n    state { n : Int }\n    init { n: 0 }\n    on Inc() ensures n >= old(n, n) do state end\n  end\nend\n";
    Alcotest.test_case "a program's own `old` is still a name" `Quick (fun () ->
        let out =
          U.run ~args:"--check"
            "mod M do\n  fn old(x : Int) : Int do x end\n  fn f(x : {Int | _ >= old(0)}) : Int do x end\nend\n"
        in
        if U.contains out "[old_misuse]" then Alcotest.failf "a user `old` was refused:\n%s" out);
    Alcotest.test_case "`ensures` stays an ordinary name" `Quick (fun () ->
        let out =
          U.run ~args:"--check"
            "mod M do\n\
            \  fn ensures(x : Int) : Int do x end\n\
            \  fn g() : Int do\n\
            \    let e = ensures(3)\n\
            \    e\n\
            \  end\n\
            end\n"
        in
        if U.contains out "error" || U.contains out "[syntax_error]" then
          Alcotest.failf "`ensures` as a name was refused:\n%s" out) ]

let tooling =
  [ Alcotest.test_case "formatter keeps the guarantee" `Quick (fun () ->
        let dir = Filename.temp_dir "ensfmt" "" in
        let src =
          "mod M do\n  actor C do\n    state { n : Int }\n    init { n: 0 }\n    on Inc(k : Int) ensures state.n == old(state.n) + k do\n      { n: state.n + k }\n    end\n  end\nend\n"
        in
        Fun.protect ~finally:(fun () -> try U.remove_tree dir with _ -> ()) (fun () ->
            let f = Filename.concat dir "m.march" in
            Out_channel.with_open_bin f (fun oc -> output_string oc src);
            ignore (U.run_in ~dir "--fmt --check" "m.march");
            let once = In_channel.with_open_bin f In_channel.input_all in
            ignore (U.run_in ~dir "--fmt --check" "m.march");
            let twice = In_channel.with_open_bin f In_channel.input_all in
            if once <> twice then Alcotest.failf "--fmt is not idempotent:\n%s\n---\n%s" once twice;
            if not (U.contains once "on Inc(k : Int) ensures state.n == old(state.n) + k do") then
              Alcotest.failf "--fmt lost the guarantee:\n%s" once)) ]

let tests = proved @ violated @ misuse @ tooling
