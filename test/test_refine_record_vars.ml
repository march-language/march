(* Record-typed variables in predicates (todo 2026-10-31-reflection-encoder-gaps,
   "A tuple- or record-typed variable in a predicate", record half).

   Since 2026-11-06 a function over a record reflects (its body's `p.x`, record
   literals and updates).  What these cases pin is a record-typed VARIABLE in a
   predicate: a lemma parameter whose fields the theorem reads, a caller's
   record passed where the callee refines a record, a callee predicate reading
   a sibling parameter's field, and return refinements over a record.

   Group `reflect-record-vars`.  Every case drives the REAL compiler through
   [Test_refine_unfold]'s helpers.  Each obligation is found by a marker
   comment on its line, so the program can grow without renumbering. *)

module U = Test_refine_unfold

let gated = U.gated
let run = U.run
let contains = U.contains
let lines = U.lines

let src_head =
  {|mod RV do
  type Pt = { x : Int, y : Int }
  fn px(p : Pt) : Int do p.x + p.y end
  fn bump(p : Pt) : Pt do { p with x: p.x + 10 } end
  fn swp(p : Pt) : Pt do { x: p.y, y: p.x } end
  fn need(a : Int, b : {Int | _ == a}) : Int do 0 end
  fn need_pt(a : Pt, b : {Pt | _ == a}) : Int do 0 end
  fn need_x(q : {Pt | _.x > 0}) : Int do 0 end
  fn need_gt(p : Pt, n : {Int | _ > p.x}) : Int do 0 end
|}

let prog body = src_head ^ body ^ "end\n"

(* The 1-based line of the first line of [src] containing [marker]. *)
let line_of src marker =
  let rec go i = function
    | [] -> Alcotest.failf "marker %s not in program" marker
    | l :: rest -> if contains l marker then i else go (i + 1) rest
  in
  go 1 (String.split_on_char '\n' src)

let at body marker ~callee verdict =
  let src = prog body in
  let out = run src in
  U.expect out ~line:(line_of src marker) ~callee verdict

let not_at body marker ~callee =
  let src = prog body in
  let out = run src in
  U.not_proved out ~line:(line_of src marker) ~callee

let admitted body name =
  let out = run (prog body) in
  let rows =
    List.filter_map
      (fun l ->
        match String.split_on_char '\t' l with
        | v :: "user" :: _ :: "postcondition" :: c :: _ when c = name -> Some v
        | "skip" :: "user" :: _ :: _ :: "postcondition" :: c :: _ when c = name -> Some "skip"
        | _ -> None)
      (lines out)
  in
  if rows = [] || List.exists (( <> ) "proved") rows
     || List.exists (fun l -> contains l "[lemma_unproved]" && contains l ("`" ^ name ^ "`")) (lines out)
  then Alcotest.failf "expected lemma `%s` admitted:\n%s" name out

let not_admitted body name =
  let out = run (prog body) in
  if not (List.exists (fun l -> (contains l "[lemma_unproved]" || contains l "[refinement_violated]")
                                && contains l ("`" ^ name ^ "`")) (lines out))
  then Alcotest.failf "lemma `%s` must not be admitted:\n%s" name out

let tests =
  [ (* G7: a lemma's theorem reads its record parameter's fields. *)
    gated "lemma: a theorem reads a record parameter's fields" (fun () ->
        admitted "  @[lemma]\n  fn l_px(p : Pt) : {Unit | px(p) == p.x + p.y} do () end\n" "l_px");
    gated "REJECT: a false theorem over a record parameter's fields is not admitted" (fun () ->
        not_admitted "  @[lemma]\n  fn l_bad(p : Pt) : {Unit | px(p) == p.x} do () end\n" "l_bad");
    (* G1: the caller's record variable at a record-refined parameter. *)
    gated "call: a record variable at {Pt | _ == a}" (fun () ->
        at "  fn c1(p : Pt) : Int do need_pt(p, p) end -- M\n" "-- M" ~callee:"need_pt" "proved");
    (* G2: a record-valued reflected call as the argument. *)
    gated "call: a reflected record-valued call at {Pt | _ == a}" (fun () ->
        at "  fn c3(p : Pt) : Int do need_pt(p, swp(swp(p))) end -- M\n" "-- M" ~callee:"need_pt" "proved");
    gated "REJECT: a reflected record-valued call that differs is not proved" (fun () ->
        not_at "  fn c3(p : Pt) : Int do need_pt(p, swp(p)) end -- M\n" "-- M" ~callee:"need_pt");
    (* G3: a field predicate over a reflected call's result. *)
    gated "call: a field predicate over a reflected call (_.x > 0 of bump(p))" (fun () ->
        at "  fn c4(p : {Pt | _.x >= 0}) : Int do need_x(bump(p)) end -- M\n" "-- M" ~callee:"need_x" "proved");
    (* G4: a callee predicate reads a sibling record parameter's field. *)
    gated "call: a callee predicate over a sibling parameter's field (_ > p.x)" (fun () ->
        at "  fn c5(p : Pt) : Int do need_gt(p, p.x + 1) end -- M\n" "-- M" ~callee:"need_gt" "proved");
    gated "REJECT: _ > p.x with p.x itself is not proved" (fun () ->
        not_at "  fn c5(p : Pt) : Int do need_gt(p, p.x) end -- M\n" "-- M" ~callee:"need_gt");
    (* G5: an Int return refinement over a record parameter. *)
    gated "return: {Int | _ == p.x} returning p.x" (fun () ->
        at "  fn r1(p : Pt) : {Int | _ == p.x} do p.x end -- M\n" "-- M" ~callee:"r1" "proved");
    gated "return: {Int | _ == p.x + p.y} returning px(p)" (fun () ->
        at "  fn r2(p : Pt) : {Int | _ == p.x + p.y} do px(p) end -- M\n" "-- M" ~callee:"r2" "proved");
    gated "REJECT: {Int | _ == p.y} returning p.x is not proved" (fun () ->
        not_at "  fn r1(p : Pt) : {Int | _ == p.y} do p.x end -- M\n" "-- M" ~callee:"r1");
    (* G6: a record return refinement. *)
    gated "return: {Pt | _.x == p.y} returning swp(p)" (fun () ->
        at "  fn r4(p : Pt) : {Pt | _.x == p.y} do swp(p) end -- M\n" "-- M" ~callee:"r4" "proved");
    gated "return: {Pt | _ == swp(swp(p))} returning p" (fun () ->
        at "  fn r3(p : Pt) : {Pt | _ == swp(swp(p))} do p end -- M\n" "-- M" ~callee:"r3" "proved");
    gated "REJECT: {Pt | _.x == p.x} returning swp(p) is not proved" (fun () ->
        not_at "  fn r4(p : Pt) : {Pt | _.x == p.x} do swp(p) end -- M\n" "-- M" ~callee:"r4");
    (* G8: record literals in a predicate, and their rendering. *)
    gated "lemma: record literals in a theorem" (fun () ->
        admitted "  @[lemma]\n  fn l_lit(n : Int) : {Unit | swp({ x: n, y: 1 }) == { x: 1, y: n }} do () end\n" "l_lit");
    gated "REJECT: a false theorem over record literals is not admitted" (fun () ->
        not_admitted "  @[lemma]\n  fn l_lit_bad(n : Int) : {Unit | swp({ x: n, y: 1 }) == { x: n, y: 1 }} do () end\n" "l_lit_bad");
    gated "REJECT: a literal whose field names two records declare is not guessed" (fun () ->
        (* `Qt` has Pt's field names, so the literal on the right names no one
           record: it must not reflect (the lemma stays unproved), never pick
           one of the two. *)
        let out =
          run
            ("mod RA do\n  type Pt = { x : Int, y : Int }\n  type Qt = { x : Int, y : Int }\n"
           ^ "  @[lemma]\n  fn l_amb(n : Int) : {Unit | { x: n, y: 1 } == { x: n, y: 1 }} do () end\nend\n")
        in
        if List.exists (fun l -> contains l "proved\tuser" && contains l "l_amb") (lines out) then
          Alcotest.failf "an ambiguous record literal was reflected:\n%s" out);
    gated "a record literal prints as itself in the report, not <predicate>" (fun () ->
        let out =
          run (prog "  @[lemma]\n  fn l_lit2(n : Int) : {Unit | px({ x: n, y: 1 }) == n} do () end\n")
        in
        if contains out "<predicate>" then Alcotest.failf "a record literal printed as <predicate>:\n%s" out;
        if not (contains out "{ x: n, y: 1 }") then Alcotest.failf "the literal is not rendered:\n%s" out) ]
