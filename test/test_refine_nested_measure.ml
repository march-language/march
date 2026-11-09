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

(* ── Stage B: the checker rules a trie insert needs (2026-11-08) ──────────
   Each rule below closed a proof the Set insert depends on; each case has a
   control that must stay unproved. *)

(* Every user row of [callee] at [marker]'s line; a function's postcondition
   files one row per return path, and it is proved only when all are. *)
let all_rows ~marker ~callee src =
  let out = U.run src in
  if has_measure_error out then Alcotest.failf "unexpected measure error:\n%s" out;
  match U.rows out ~line:(line_of src marker) ~callee with
  | [] -> Alcotest.failf "no %s row:\n%s" callee out
  | rs -> (List.map fst rs, out)

let proves ~marker ~callee src =
  let vs, out = all_rows ~marker ~callee src in
  if not (List.for_all (fun v -> v = "proved") vs) then
    Alcotest.failf "%s: expected every path proved, got [%s]\n%s" callee (String.concat "; " vs) out

let refutes_or_skips ~marker ~callee src =
  let vs, out = all_rows ~marker ~callee src in
  if List.for_all (fun v -> v = "proved") vs then
    Alcotest.failf "%s: a false contract was proved\n%s" callee out

(* (1) A constructor result in an `if` branch reflects for an `elts`
   contract, whatever its tail is (here a parameter). *)
let branch_cons body =
  Printf.sprintf
    {|mod M do
  pfn f(xs : List(Int), x : Int, b : Bool) : {List(Int) | elts(_) == union(elts(xs), singleton(x))} do -- F
    %s
  end
end
|}
    body

(* (2) `if f(args) do`: the guard's `Bool` contract reaches both branches. *)
let guard_call body =
  Printf.sprintf
    {|mod M do
  @[assume]
  pfn has(xs : List(Int), x : Int) : {Bool | _ == member(x, elts(xs))} do false end

  pfn ins(xs : List(Int), x : Int) : {List(Int) | elts(_) == union(elts(xs), singleton(x))} do -- F
    %s
  end
end
|}
    body

(* (3) A `Nil` / `Cons(h, t)` arm states `elts` of the scrutinee. *)
let list_member nil_arm =
  Printf.sprintf
    {|mod M do
  pfn mem(xs : List(Int), x : Int) : {Bool | _ == member(x, elts(xs))} do -- F
    match xs do
    Nil -> %s
    Cons(h, t) -> if h == x do true else mem(t, x) end
    end
  end
end
|}
    nil_arm

(* (4) A `panic(..)` arm never returns, so it satisfies a return contract. *)
let panic_arm other =
  Printf.sprintf
    {|mod M do
  pfn first(xs : List(Int)) : {List(Int) | elts(_) == elts(xs)} do -- F
    match xs do
    Nil -> panic("empty")
    Cons(h, t) -> %s
    end
  end
end
|}
    other

(* (5) The trie: a node's insert and its child-list insert call each other
   across two types, the child insert in a list ELEMENT position.  A copy of
   the Set HAMT's insert path (collision split, branch building, child
   insert), proved against the stage A measure pair. *)
let trie = {|mod SB do
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

  @[assume]
  pfn cmp_eq(cmp : a -> a -> Bool, x : a, y : a) : {Bool | _ == (x == y)} do
    let lt_ab = cmp(x)
    let lt_ba = cmp(y)
    if lt_ab(y) do false
    else if lt_ba(x) do false
    else true end end
  end

  pfn hash_slot(h : Int, level : Int) : Int do
    int_and(int_shr(h, level * 5), 31)
  end
  pfn bitmap_has(bitmap : Int, idx : Int) : Bool do
    int_and(int_shr(bitmap, idx), 1) == 1
  end
  pfn bitmap_rank(bitmap : Int, idx : Int) : Int do
    int_popcount(int_and(bitmap, int_shl(1, idx) - 1))
  end
  pfn bitmap_set(bitmap : Int, idx : Int) : Int do
    int_or(bitmap, int_shl(1, idx))
  end

  pfn coll_has(elems : List(a), x : a, cmp : a -> a -> Bool) : {Bool | _ == member(x, elts(elems))} do -- CHAS
    match elems do
    Nil -> false
    Cons(e, rest) -> if cmp_eq(cmp, e, x) do true else coll_has(rest, x, cmp) end
    end
  end

  pfn coll_insert(elems : List(a), x : a, cmp : a -> a -> Bool) : {List(a) | elts(_) == union(elts(elems), singleton(x))} do -- CINS
    if coll_has(elems, x, cmp) do elems else Cons(x, elems) end
  end

  pfn insert_at(lst : List(SE(a)), idx : Int, e : SE(a)) : {List(SE(a)) | ces(_) == union(ces(lst), ne(e))} do -- INSAT
    match lst do
    Nil -> Cons(e, Nil)
    Cons(h, t) -> if idx == 0 do Cons(e, lst) else Cons(h, insert_at(t, idx - 1, e)) end
    end
  end

  pfn wrap_slots(nd : SE(a), slots : List(Int)) : {SE(a) | ne(_) == ne(nd)} do -- WRAP
    match slots do
    Nil -> nd
    Cons(s, rest) -> wrap_slots(SBr(bitmap_set(0, s), Cons(nd, Nil)), rest)
    end
  end

  pfn wrap_pair(bm : Int, first : SE(a), second : SE(a), slots : List(Int)) : {SE(a) | ne(_) == union(ne(first), ne(second))} do -- WP
    wrap_slots(SBr(bm, Cons(first, Cons(second, Nil))), slots)
  end

  @[decreases(7 - lvl)]
  pfn branch_nodes(h1 : Int, n1 : SE(a), h2 : Int, n2 : SE(a), lvl : Int, acc : List(Int)) : {SE(a) | ne(_) == union(ne(n1), ne(n2))} do -- BN
    if lvl > 6 do panic("Set: two distinct hashes share every slot")
    else do
      let s1 = hash_slot(h1, lvl)
      let s2 = hash_slot(h2, lvl)
      if s1 == s2 do
        branch_nodes(h1, n1, h2, n2, lvl + 1, Cons(s1, acc))
      else do
        let bm = bitmap_set(bitmap_set(0, s1), s2)
        if s1 < s2 do wrap_pair(bm, n1, n2, acc) else wrap_pair(bm, n2, n1, acc) end
      end end
    end end
  end

  pfn insert_child(cs : List(SE(a)), idx : Int, x : a, h : Int, cmp : a -> a -> Bool, level : Int) : {List(SE(a)) | ces(_) == union(ces(cs), singleton(x))} do -- ICH
    match cs do
    Nil -> panic("Set: HAMT node index out of range")
    Cons(c, rest) ->
      if idx == 0 do Cons(node_insert(c, x, h, cmp, level), rest)
      else Cons(c, insert_child(rest, idx - 1, x, h, cmp, level)) end
    end
  end

  pfn node_insert(node : SE(a), x : a, h : Int, cmp : a -> a -> Bool, level : Int) : {SE(a) | ne(_) == union(ne(node), singleton(x))} do -- NINS
    match node do
    SEm -> SLf(h, x)
    SLf(lh, lx) ->
      if lh == h do
        if cmp_eq(cmp, lx, x) do node else SCo(h, Cons(lx, Cons(x, Nil))) end
      else branch_nodes(lh, node, h, SLf(h, x), level, Nil) end
    SCo(ch, elems) ->
      if ch == h do SCo(ch, coll_insert(elems, x, cmp))
      else branch_nodes(ch, node, h, SLf(h, x), level, Nil) end
    SBr(bm, children) ->
      let slot = hash_slot(h, level)
      let idx = bitmap_rank(bm, slot)
      if bitmap_has(bm, slot) do SBr(bm, insert_child(children, idx, x, h, cmp, level + 1))
      else SBr(bitmap_set(bm, slot), insert_at(children, idx, SLf(h, x))) end
    end
  end
end
|}

let trie_bug (a, b) =
  if not (contains trie a) then Alcotest.failf "trie fixture lost %s" a;
  let i = ref 0 and n = String.length a in
  while String.sub trie !i n <> a do incr i done;
  String.sub trie 0 !i ^ b ^ String.sub trie (!i + n) (String.length trie - !i - n)

let stage_b =
  [ U.gated "a Cons result in an if branch reflects for elts" (fun () ->
        proves ~marker:"-- F" ~callee:"f" (branch_cons "if b do Cons(x, xs) else Cons(x, Cons(x, xs)) end"));
    U.gated "REJECT: a branch that drops the tail is not proved" (fun () ->
        refutes_or_skips ~marker:"-- F" ~callee:"f" (branch_cons "if b do Cons(x, xs) else Cons(x, Nil) end"));
    U.gated "an if on a call reads the call's Bool contract" (fun () ->
        proves ~marker:"-- F" ~callee:"ins" (guard_call "if has(xs, x) do xs else Cons(x, xs) end"));
    U.gated "REJECT: the guard's contract does not make a wrong branch right" (fun () ->
        refutes_or_skips ~marker:"-- F" ~callee:"ins" (guard_call "if has(xs, x) do Nil else Cons(x, xs) end"));
    U.gated "list match arms give elts of the scrutinee" (fun () ->
        proves ~marker:"-- F" ~callee:"mem" (list_member "false"));
    U.gated "REJECT: true on Nil is not membership" (fun () ->
        refutes_or_skips ~marker:"-- F" ~callee:"mem" (list_member "true"));
    U.gated "a panic arm satisfies a return contract" (fun () ->
        proves ~marker:"-- F" ~callee:"first" (panic_arm "xs"));
    U.gated "REJECT: a panic arm does not excuse a wrong arm" (fun () ->
        refutes_or_skips ~marker:"-- F" ~callee:"first" (panic_arm "t"));
    U.gated "the trie insert proves through its mutual child insert" (fun () ->
        List.iter
          (fun (m, c) -> proves ~marker:m ~callee:c trie)
          [ ("-- CHAS", "coll_has"); ("-- CINS", "coll_insert"); ("-- BN", "branch_nodes");
            ("-- ICH", "insert_child"); ("-- NINS", "node_insert") ]);
    U.gated "REJECT: a child insert that drops the new element" (fun () ->
        refutes_or_skips ~marker:"-- NINS" ~callee:"node_insert"
          (trie_bug ("if idx == 0 do Cons(node_insert(c, x, h, cmp, level), rest)", "if idx == 0 do Cons(c, rest)")));
    U.gated "REJECT: a leaf that ignores the comparator" (fun () ->
        refutes_or_skips ~marker:"-- NINS" ~callee:"node_insert"
          (trie_bug ("if cmp_eq(cmp, lx, x) do node else", "if true do node else")));
    U.gated "REJECT: a branch built from one node twice" (fun () ->
        refutes_or_skips ~marker:"-- BN" ~callee:"branch_nodes"
          (trie_bug ("wrap_pair(bm, n1, n2, acc)", "wrap_pair(bm, n1, n1, acc)"))) ]

(* ── `@[abstraction(elts)]` (2026-11-08) ─────────────────────────────────
   Inside the module declaring it, `elts(b)` of the module's datatype is the
   abstraction measure; outside, `elts` stays opaque and a caller proves only
   through the contracts. *)
let bag body =
  Printf.sprintf
    {|mod Outer do
  mod Bag do
    type B(a) = Bg(Int, List(a))

    @[measure]
    @[abstraction(elts)]
    pfn bag_elts(b : B(a)) : Set(a) do
      match b do
      Bg(_, xs) -> elts(xs)
      end
    end

    fn add(b : B(a), x : a) : {B(a) | elts(_) == union(elts(b), singleton(x))} do -- ADD
      %s
    end
  end
end
|}
    body

let bad_abstraction attr =
  Printf.sprintf
    {|mod M do
  type B = Bg(List(Int))
  %s
  pfn bag_elts(b : B) : Set(Int) do
    match b do
    Bg(xs) -> elts(xs)
    end
  end
end
|}
    attr

(* Set's own contracts, proved against the trie (stage B). *)
let set_proved callee =
  let out = U.run {|mod M do
  fn f() : Int do 0 end
end
|} in
  let rows =
    List.filter
      (fun l ->
        contains l "set.march" && contains l ("\tpostcondition\t" ^ callee ^ "\t"))
      (String.split_on_char '\n' out)
  in
  match rows with
  | [] -> Alcotest.failf "no Set.%s postcondition row:\n%s" callee out
  | rs ->
    if not (List.for_all (fun l -> String.starts_with ~prefix:"proved\t" l) rs) then
      Alcotest.failf "Set.%s not proved: [%s]" callee (String.concat "; " rs)

let abstraction =
  [ U.gated "an abstraction measure proves its module's elts contract" (fun () ->
        proves ~marker:"-- ADD" ~callee:"add" (bag "match b do\n      Bg(n, xs) -> Bg(n + 1, Cons(x, xs))\n      end"));
    U.gated "REJECT: an add that keeps the old list is not proved" (fun () ->
        refutes_or_skips ~marker:"-- ADD" ~callee:"add" (bag "match b do\n      Bg(n, xs) -> Bg(n + 1, xs)\n      end"));
    U.gated "a caller of Set.insert still proves through its contract" (fun () ->
        proves ~marker:"-- USE" ~callee:"need"
          {|mod M do
  fn need(s : Set(Int), x : {Int | member(_, elts(s))}) : Int do 0 end
  fn caller(x : Int) : Int do
    let s = Set.insert(Set.insert(Set.empty(), 2, fn a -> fn b -> a < b), x, fn a -> fn b -> a < b)
    need(s, x) -- USE
  end
end
|});
    no_measure_error "an abstraction on an axiomatised measure is accepted"
      (bad_abstraction "@[measure]\n  @[abstraction(elts)]");
    Alcotest.test_case "an abstraction without @[measure] is an error" `Quick (fun () ->
        let out = U.run ~args:"--check" (bad_abstraction "@[abstraction(elts)]") in
        if not (contains out "needs @[measure]") then Alcotest.failf "no error:\n%s" out);
    Alcotest.test_case "an abstraction must name elts or keys" `Quick (fun () ->
        let out = U.run ~args:"--check" (bad_abstraction "@[measure]\n  @[abstraction(card)]") in
        if not (contains out "names no built-in set measure") then Alcotest.failf "no error:\n%s" out) ]
  @ List.map
      (fun c -> U.gated (Printf.sprintf "Set.%s is proved against the trie" c) (fun () -> set_proved c))
      [ "empty"; "singleton"; "insert"; "union"; "to_list"; "from_list" ]

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
  @ stage_b @ abstraction
