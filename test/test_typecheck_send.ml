(* test_typecheck_send.ml — the guard for the rule in specs/lang/memory-model.md
   ("Mutable builtins: the rule") and the structural sendability judgement
   [Typecheck_exhaustive.is_send] (Part C, Phase C5 of
   specs/plans/2026-09-25-send-data-race-freedom-plan.md).

   1. [non_sendable_types] must be EMPTY.  A builtin type that writes memory
      another reference could observe is either always_linear (RingBuf) or
      copy-on-write gated on sole ownership (the NativeArray backing types);
      a type that is neither may only be listed once Parts A and B of the plan
      (a general Send check through closures and user types) have landed.
      This case fails the build the moment a name is added before then.

   2. [is_send] follows a primitive root through user ADTs, record fields,
      type arguments, tuples and recursive types.  With the list empty there
      is nothing to find, so the walk is exercised through the test hook
      [send_roots_for_tests], which makes a user type named `Buf` a root for
      the duration of a case; the programs then send it in every shape Part
      A's Phase 1 enumerates. *)

open Test_helpers

let roots = March_typecheck.Typecheck_exhaustive.send_roots_for_tests

let with_root name f () =
  roots := [name];
  Fun.protect ~finally:(fun () -> roots := []) f

let messages ctx =
  List.filter_map (fun (d : March_errors.Errors.diagnostic) ->
      if d.severity = March_errors.Errors.Error then Some d.message else None)
    ctx.March_errors.Errors.diagnostics

let has_substring hay needle =
  let n = String.length needle and h = String.length hay in
  let rec go i = i + n <= h && (String.sub hay i n = needle || go (i + 1)) in
  go 0

let rejects_with src needle () =
  let errs = messages (typecheck src) in
  let found = List.exists (fun m -> has_substring m needle) errs in
  Alcotest.(check bool)
    (Printf.sprintf "rejected with %S (got: %s)" needle (String.concat " | " errs))
    true found

let accepts src () =
  let errs = messages (typecheck src) in
  Alcotest.(check (list string)) "no errors" [] errs

(* The actor every program sends to; `Buf` is the test root. *)
let prelude = {|
  type Buf = Buf(Int)
  type Wrap = Wrap(Buf)
  type Rec = { buf : Buf, n : Int }
  type Box(a) = Box(a)
  type Tree = Leaf | Node(Tree, Buf)
  type Plain = PNil | PCons(Int, Plain)
  type EvenT = EZ | ES(OddT)
  type OddT = OS(EvenT)
|}

let program handler payload =
  Printf.sprintf {|mod Main do
%s
  actor Worker do
    state { n : Int }
    init  { n: 0 }
    on Job(x : %s) do
      { n: 1 }
    end
  end
  fn main() do
    let w = spawn(Worker)
    send(w, Job(%s))
  end
end
|} prelude handler payload

let cannot = "cannot be sent in actor messages"

let () =
  Alcotest.run "typecheck_send"
    [ ("guard", [
          Alcotest.test_case "non_sendable_types is empty" `Quick (fun () ->
              Alcotest.(check (list string))
                "a type that is neither linear nor copy-on-write may not be \
                 listed before the general Send check (plan Parts A and B) lands; \
                 see specs/lang/memory-model.md, Mutable builtins: the rule"
                [] March_typecheck.Typecheck_exhaustive.non_sendable_types);
          Alcotest.test_case "with no roots, a user type sends" `Quick
            (accepts (program "Wrap" "Wrap(Buf(1))"));
        ]);
      ("is_send", [
          Alcotest.test_case "a root at the top of the payload" `Quick
            (with_root "Buf" (rejects_with (program "Buf" "Buf(1)") cannot));
          Alcotest.test_case "a root hidden in a user ADT's field" `Quick
            (with_root "Buf" (rejects_with (program "Wrap" "Wrap(Buf(1))") "Wrap field 1"));
          Alcotest.test_case "a root in a record field" `Quick
            (with_root "Buf" (rejects_with (program "Rec" "{ buf: Buf(1), n: 0 }") "reached through .buf"));
          Alcotest.test_case "a root as a type argument (Option)" `Quick
            (with_root "Buf" (rejects_with (program "Option(Buf)" "Some(Buf(1))") "Some field 1"));
          Alcotest.test_case "a root as a type argument (List)" `Quick
            (with_root "Buf" (rejects_with (program "List(Buf)" "[Buf(1)]") cannot));
          Alcotest.test_case "a parameterised ADT is Send only for Send arguments" `Quick
            (with_root "Buf" (fun () ->
                 rejects_with (program "Box(Buf)" "Box(Buf(1))") "Box field 1" ();
                 accepts (program "Box(Int)" "Box(1)") ()));
          Alcotest.test_case "a recursive type holding a root" `Quick
            (with_root "Buf" (rejects_with (program "Tree" "Node(Leaf, Buf(1))") "Node field 2"));
          Alcotest.test_case "a recursive type without one terminates and sends" `Quick
            (with_root "Buf" (accepts (program "Plain" "PCons(1, PNil)")));
          Alcotest.test_case "a mutually recursive pair terminates and sends" `Quick
            (with_root "Buf" (accepts (program "EvenT" "ES(OS(EZ))")));
          Alcotest.test_case "a tuple component" `Quick
            (with_root "Buf" (rejects_with (program "(Int, Buf)" "(1, Buf(1))") "component 2"));
          Alcotest.test_case "an arrow payload is accepted at the type level" `Quick
            (with_root "Buf" (accepts (program "Int -> Int" "fn x -> x + 1")));
        ]);
    ]
