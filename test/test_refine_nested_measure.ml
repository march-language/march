(* Set measures over a node type and its List of children: stage A of
   specs/todos/2026-11-06-prove-map-set-contracts.md.

   `Set` and `Map` are HAMTs: a branch holds a `List` of child nodes, so the
   measure of a node's elements and the measure of a child list call each
   other across two types.  These cases drive the REAL compiler (with the
   stdlib prelude, which declares functions named like the set vocabulary)
   through [Test_refine_unfold]'s helpers.

   Group `nested-measure`. *)

module U = Test_refine_unfold

let contains = U.contains

let has_measure_error out = contains out "invalid_measure" || contains out "unbound_variable"

let no_measure_error name src =
  Alcotest.test_case name `Quick (fun () ->
      let out = U.run ~args:"--check" src in
      if has_measure_error out then Alcotest.failf "unexpected measure error:\n%s" out)

(* `empty` inside a set measure is the empty set: the typechecker binds the
   set vocabulary over the measure's body, shadowing any global of the same
   name.  The prelude (and this module) declares a function `empty`. *)
let empty_shadowed =
  {|mod M do
  type T(a) = Lf | Nd(T(a), a, T(a))

  fn empty() : Int do 0 end

  @[measure]
  fn telts(t : T(a)) : Set(a) do
    match t do
    Lf -> empty
    Nd(l, x, r) -> union(telts(l), union(singleton(x), telts(r)))
    end
  end
end
|}

(* The HAMT shape: a node's elements and its children's elements. *)
let hamt_head =
  {|mod HS do
  type SE(a) = SEm | SLf(Int, a) | SBr(Int, List(SE(a))) | SCo(Int, List(a))

  @[measure]
  pfn ne(n : SE(a)) : Set(a) do
    match n do
    SEm -> empty
    SLf(_, x) -> singleton(x)
    SBr(_, cs) -> ces(cs)
    SCo(_, xs) -> elts(xs)
    end
  end

  @[measure]
  pfn ces(cs : List(SE(a))) : Set(a) do
    match cs do
    Nil -> empty
    Cons(c, rest) -> union(ne(c), ces(rest))
    end
  end
|}

let hamt body = hamt_head ^ body ^ "end\n"

let ins_at contract =
  hamt
    (Printf.sprintf
       {|
  pfn ins_at(lst : List(SE(a)), idx : Int, e : SE(a)) : {List(SE(a)) | %s} do -- INS
    match lst do
    Nil -> Cons(e, Nil)
    Cons(h, t) -> if idx <= 0 do Cons(e, lst) else Cons(h, ins_at(t, idx - 1, e)) end
    end
  end
|}
       contract)

let line_of src marker =
  let rec go i = function
    | [] -> Alcotest.failf "marker %s not in program" marker
    | l :: rest -> if contains l marker then i else go (i + 1) rest
  in
  go 1 (String.split_on_char '\n' src)

let verdict ?(marker = "-- INS") ?(callee = "ins_at") src =
  let out = U.run src in
  if has_measure_error out then Alcotest.failf "unexpected measure error:\n%s" out;
  match U.rows out ~line:(line_of src marker) ~callee with
  | (v, _) :: _ -> v
  | [] -> Alcotest.failf "no %s row:\n%s" callee out

(* The collision arm's `elts(xs)` and a contract's `elts(xs)` are one symbol. *)
let bucket contract =
  hamt
    (Printf.sprintf
       {|
  pfn bucket(h : Int, xs : List(a)) : {SE(a) | %s} do -- BKT
    SCo(h, xs)
  end
|}
       contract)

let suite =
  [ no_measure_error "empty in a set measure is the empty set, not a global named empty" empty_shadowed;
    no_measure_error "a node measure and its child-list measure call each other" (hamt "");
    U.gated "a List insert keeps the children's elements plus the new node's" (fun () ->
        Alcotest.(check string) "verdict" "proved"
          (verdict (ins_at "ces(_) == union(ces(lst), ne(e))")));
    U.gated "REJECT: dropping the new node's elements is not proved" (fun () ->
        let v = verdict (ins_at "ces(_) == ces(lst)") in
        if v = "proved" then Alcotest.fail "a false contract was proved");
    U.gated "a collision bucket's elements are the list's elts" (fun () ->
        Alcotest.(check string) "verdict" "proved"
          (verdict ~marker:"-- BKT" ~callee:"bucket" (bucket "ne(_) == elts(xs)")));
    U.gated "REJECT: a collision bucket is not empty for every list" (fun () ->
        let v = verdict ~marker:"-- BKT" ~callee:"bucket" (bucket "ne(_) == empty") in
        if v = "proved" then Alcotest.fail "a false contract was proved") ]
