(* Predicate names: how a name inside a refinement predicate is printed,
   resolved and warned about (specs/plans/2026-11-06-predicate-names-plan.md).

   Group `pred-names`.  Cases that run the compiler use [Test_refine_unfold]'s
   helpers. *)

module A = March_ast.Ast
module RS = March_refinecheck.Refine_scope
module IV = March_refinecheck.Infer_vocab
module PI = March_refinecheck.Precond_infer
module U = Test_refine_unfold

let test name f = Alcotest.test_case name `Quick f
let gated = U.gated

(* The predicate of a return refinement `{base | src}`, as the parser builds
   it (undesugared, as `pred_str` meets it in a signature). *)
let pred_on ~base src =
  let m =
    Printf.sprintf
      "mod P do\n  fn f(a : Int, b : Int, c : Int, low : Int, high : Int, m : Map(Int, Int)) : {%s | %s} do 0 end\nend\n"
      base src
  in
  match (March_parser.Parse.module_of_lexbuf (Lexing.from_string m)).A.mod_decls with
  | [ A.DFn ({ A.fn_ret_ty = Some (A.TyRefine (_, _, p)); _ }, _) ] -> p
  | _ -> Alcotest.failf "no refinement parsed from %s" src

let pred_of = pred_on ~base:"Int"
let pred_of_bool = pred_on ~base:"Bool"

(* #18: `pred_str` keeps the parentheses a reparse needs. *)
let parens =
  let rows =
    [ ("_ <= a && _ <= b && (_ == a || _ == b)", "_ <= a && _ <= b && (_ == a || _ == b)");
      ("high < low || (_ >= low && _ <= high)", "high < low || _ >= low && _ <= high");
      ("_ == (a + b) * 2", "_ == (a + b) * 2");
      ("_ == a - (b - c)", "_ == a - (b - c)");
      ("_ == a - b - c", "_ == a - b - c");
      ("_ == a * (b / c)", "_ == a * (b / c)");
      ("!(_ > 0 && _ < 9)", "!(_ > 0 && _ < 9)");
      ("_ == -(a + b)", "_ == -(a + b)") ]
  in
  let bool_rows = [ "(_ || a > 0) && b > 0"; "_ == (a == b)"; "_ == (keys(m) == empty)" ] in
  [ test "pred_str prints the parentheses a reparse needs" (fun () ->
        List.iter (fun (src, want) -> Alcotest.(check string) src want (RS.pred_str (pred_of src))) rows);
    test "a Boolean equality of a comparison keeps its parentheses (Map.is_empty)" (fun () ->
        Alcotest.(check string) "is_empty" "_ == (keys(m) == empty)"
          (RS.pred_str (pred_of_bool "_ == (keys(m) == empty)")));
    test "every printed predicate re-parses to the same text" (fun () ->
        let again base s = RS.pred_str (pred_on ~base (RS.pred_str (pred_on ~base s))) in
        List.iter
          (fun s -> Alcotest.(check string) s (RS.pred_str (pred_of s)) (again "Int" s))
          (List.map fst rows @ [ "_ == a - b + c"; "_ == a - (b + c)" ]);
        List.iter (fun s -> Alcotest.(check string) s (RS.pred_str (pred_of_bool s)) (again "Bool" s)) bool_rows;
        List.iter (fun s -> Alcotest.(check string) ("kept: " ^ s) s (RS.pred_str (pred_of_bool s))) bool_rows);
    test "an inference candidate read back from the text keeps its grouping" (fun () ->
        match IV.candidate_of_text (RS.pred_str (pred_of "_ == (a + b) * 2")) with
        | Some c -> Alcotest.(check string) "round trip" "_ == (a + b) * 2" c.PI.c_text
        | None -> Alcotest.fail "not a candidate");
    gated "min_int's report row prints its disjunction in parentheses" (fun () ->
        let dir = Filename.concat (Filename.dirname Sys.executable_name) ".." in
        let out = U.run_in ~dir "--check --stdlib-source --refine-report-sites=all" "stdlib/math.march" in
        let rows = List.filter (fun l -> U.contains l "\tmin_int\t") (U.lines out) in
        if rows = [] then Alcotest.failf "no min_int row:\n%s" out;
        List.iter
          (fun l ->
            if not (U.contains l "_ <= a && _ <= b && (_ == a || _ == b)") then
              Alcotest.failf "min_int row lost its parentheses: %s" l)
          rows) ]

(* #20 (closed by 71f112f4a, resolution by call site): a bare predicate call
   resolves in its own module, in the postcondition pre-pass too; and a
   qualified call that resolved is not reported as unchecked. *)
let inner ~post =
  Printf.sprintf
    {|  mod Inner do
    needs IO.Console
    fn dbl(x : Int) : Int do x + x end
    fn twice(c : Cap(IO.Console), n : Int) : {Int | _ == %s(n)} do
      println("hi")
      dbl(n)
    end
  end
|} post

let resolution =
  [ gated "a bare predicate call resolves in its own module, also in the postcondition pre-pass" (fun () ->
        let src =
          "mod G do\n  needs IO.Console\n  fn dbl(x : Int) : Int do x + 1 end\n" ^ inner ~post:"dbl"
          ^ "  fn need6(x : {Int | _ == 6}) : Int do x end\n\
            \  fn need4(x : {Int | _ == 4}) : Int do x end\n\
            \  fn a(c : Cap(IO.Console)) : Int do need6(Inner.twice(c, 3)) end\n\
            \  fn b(c : Cap(IO.Console)) : Int do need4(Inner.twice(c, 3)) end\n\
            \  fn main(c : Cap(IO.Console)) do println(int_to_string(a(c) + b(c))) end\nend\n"
        in
        let out = U.run src in
        U.expect out ~line:7 ~callee:"twice" "proved";
        U.expect ~uses:"Inner.dbl" out ~line:14 ~callee:"need6" "proved";
        U.expect out ~line:15 ~callee:"need4" "violated");
    gated "a qualified predicate call that resolved gets no unchecked warning" (fun () ->
        let src =
          "mod G do\n  needs IO.Console\n" ^ inner ~post:"Inner.dbl"
          ^ "  fn need6(x : {Int | _ == 6}) : Int do x end\n\
            \  fn a(c : Cap(IO.Console)) : Int do need6(Inner.twice(c, 3)) end\n\
            \  fn main(c : Cap(IO.Console)) do println(int_to_string(a(c))) end\nend\n"
        in
        let out = U.run src in
        U.expect out ~line:12 ~callee:"need6" "proved";
        Alcotest.(check int) ("no refinement_unchecked:\n" ^ out) 0 (U.count_code out "refinement_unchecked"));
    gated "a qualified predicate call that does not resolve still warns" (fun () ->
        let src =
          "mod G do\n  needs IO.Console\n" ^ inner ~post:"Nowhere.dbl"
          ^ "  fn main(c : Cap(IO.Console)) do println(int_to_string(Inner.twice(c, 3))) end\nend\n"
        in
        let out = U.run src in
        Alcotest.(check bool) ("refinement_unchecked:\n" ^ out) true (U.count_code out "refinement_unchecked" >= 1)) ]

(* #2: a predicate's built-in vocabulary shadows the user's function of the
   same name (reflection design F21).  The verdict is unchanged (the built-in
   meaning is kept); the program now says so. *)
let shadow_code = "predicate_vocabulary_shadowed"

let shadowing =
  let count src = U.count_code (U.run src) shadow_code in
  [ gated "r3: a user len shadowed by the predicate's built-in len is warned" (fun () ->
        let src =
          "mod Shadow do\n  needs IO\n  fn len(xs : List(Int)) : Int do 7 end\n\n\
          \  fn need(xs : {List(Int) | len(_) == 1}) : Int do 0 end\n\n\
          \  fn main(cap : Cap(IO)) : Unit do\n    println(int_to_string(len(Cons(1, Nil))))\n\
          \    let _ = need(Cons(1, Nil))\n    ()\n  end\nend\n"
        in
        let out = U.run src in
        Alcotest.(check int) ("one warning:\n" ^ out) 1 (U.count_code out shadow_code);
        List.iter
          (fun frag -> Alcotest.(check bool) ("mentions " ^ frag ^ ":\n" ^ out) true (U.contains out frag))
          [ "means the built-in length measure"; "`Shadow.len`"; "(line 3)"; "5 |" ];
        U.expect out ~line:9 ~callee:"need" "proved");
    gated "a len declared in an enclosing module warns inside a nested one" (fun () ->
        Alcotest.(check int) "one" 1
          (count
             "mod O do\n  fn len(xs : List(Int)) : Int do 7 end\n  mod Inner do\n\
             \    fn need(xs : {List(Int) | len(_) == 1}) : Int do 0 end\n  end\nend\n"));
    gated "a len in a sibling module does not warn" (fun () ->
        Alcotest.(check int) "none" 0
          (count
             "mod O do\n  mod Other do\n    fn len(xs : List(Int)) : Int do 7 end\n  end\n  mod Inner do\n\
             \    fn need(xs : {List(Int) | len(_) == 1}) : Int do 0 end\n  end\nend\n"));
    gated "an elts, keys or is_<Ctor> function warns too" (fun () ->
        List.iter
          (fun (what, src) -> Alcotest.(check int) what 1 (count src))
          [ ("elts", "mod E do\n  fn elts(xs : List(Int)) : Int do 0 end\n  fn need(xs : {List(Int) | member(1, elts(_))}) : Int do 0 end\nend\n");
            ("keys", "mod K do\n  fn keys(m : Map(Int, Int)) : Int do 0 end\n  fn need(m : {Map(Int, Int) | member(1, keys(_))}) : Int do 0 end\nend\n");
            ("is_A", "mod T do\n  type T = A | B\n  fn is_A(t : T) : Bool do false end\n  fn need(t : {T | is_A(_)}) : Int do 0 end\nend\n") ]);
    gated "a set operator the user also declares does not warn when well-formed" (fun () ->
        Alcotest.(check int) "none" 0
          (count
             "mod M do\n  fn member(x : Int, xs : List(Int)) : Bool do false end\n\
             \  fn need(xs : {List(Int) | member(1, elts(_))}) : Int do 0 end\nend\n"));
    gated "the stdlib's deliberate uses get no warning" (fun () ->
        let dir = Filename.concat (Filename.dirname Sys.executable_name) ".." in
        List.iter
          (fun f ->
            let out = U.run_in ~dir "--check --stdlib-source" f in
            Alcotest.(check int) (f ^ ":\n" ^ out) 0 (U.count_code out shadow_code))
          [ "stdlib/map.march"; "stdlib/list.march"; "stdlib/set.march" ]) ]

(* #8: a user type that shares its short name with a stdlib type (OrderedMap's
   `Tree(k, v)`) at ANOTHER arity is a different type to the typechecker, so
   the logic may use it.  At the SAME arity the typechecker conflates the two
   (todo 2026-10-13-same-short-name-nested-types-unify): a stdlib value can
   reach the user's function, so those stay a skip, never a proof. *)
let tree_prog ?(ty = "Tree") ?(leaf = "Leaf") ?(node = "Node") ~arg () =
  Printf.sprintf
    "mod TreeUser do\n\
    \  type %s = %s | %s(%s, Int, %s)\n\
    \  fn size(t : %s) : Int do\n\
    \    match t do\n\
    \      %s -> 0\n\
    \      %s(l, _, r) -> size(l) + 1 + size(r)\n\
    \    end\n\
    \  end\n\
    \  fn need_one(t : {%s | size(_) == 1}) : Int do 0 end\n\
    \  fn main() : Int do need_one(%s) end\n\
    end\n"
    ty leaf node ty ty ty leaf node ty arg

let leak3 =
  "mod TreeUser do\n\
  \  type Tree(a, b) = Leaf | Node(Tree(a, b), a, Tree(a, b))\n\
  \  fn size(t : Tree(a, b)) : Int do\n\
  \    match t do\n\
  \      Leaf -> 0\n\
  \      Node(l, _, r) -> size(l) + 1 + size(r)\n\
  \    end\n\
  \  end\n\
  \  fn need_one(t : {Tree(Int, Int) | size(_) == 1}) : Int do 0 end\n\
  \  fn main() : Int do\n\
  \    let m = OrderedMap.put(OrderedMap.new(fn (a, b) -> a - b), 1, 2)\n\
  \    println(int_to_string(size(m.tree)))\n\
  \    need_one(m.tree)\n\
  \  end\n\
  end\n"

let arity =
  [ gated "a user Tree beside OrderedMap's Tree(k, v) is usable in a predicate" (fun () ->
        U.expect ~uses:"size" (U.run (tree_prog ~arg:"Node(Leaf, 5, Leaf)" ())) ~line:10 ~callee:"need_one" "proved");
    gated "the same with constructors no stdlib type declares" (fun () ->
        U.expect (U.run (tree_prog ~leaf:"Lf" ~node:"Nd" ~arg:"Nd(Lf, 5, Lf)" ())) ~line:10 ~callee:"need_one" "proved");
    gated "a wrong size of a user Tree is a violation" (fun () ->
        U.expect (U.run (tree_prog ~arg:"Node(Node(Leaf, 1, Leaf), 5, Leaf)" ())) ~line:10 ~callee:"need_one" "violated");
    gated "a user type Array (arity 0) beside the built-in Array(a)" (fun () ->
        U.expect (U.run (tree_prog ~ty:"Array" ~leaf:"Lf" ~node:"Nd" ~arg:"Nd(Lf, 5, Lf)" ())) ~line:10 ~callee:"need_one" "proved");
    gated "a user type Option (arity 0) beside the built-in Option(a)" (fun () ->
        U.expect (U.run (tree_prog ~ty:"Option" ~leaf:"Lf" ~node:"Nd" ~arg:"Nd(Lf, 5, Lf)" ())) ~line:10 ~callee:"need_one" "proved");
    gated "same arity as OrderedMap's Tree: an OrderedMap value is never proved" (fun () ->
        U.not_proved (U.run leak3) ~line:13 ~callee:"need_one");
    gated "same arity as the built-in DownReason: never proved" (fun () ->
        U.not_proved (U.run (tree_prog ~ty:"DownReason" ~leaf:"Lf" ~node:"Nd" ~arg:"Normal" ())) ~line:10 ~callee:"need_one");
    gated "same arity as the built-in Option(a): never proved" (fun () ->
        let src =
          "mod TreeUser do\n  type Option(a) = Nope | Yep(a)\n\
          \  fn cnt(t : Option(Int)) : Int do\n    match t do\n      Nope -> 0\n      Yep(_) -> 1\n    end\n  end\n\
          \  fn need_one(t : {Option(Int) | cnt(_) == 1}) : Int do 0 end\n\
          \  fn main() : Int do need_one(List.head_opt([1])) + need_one(Yep(3)) end\nend\n"
        in
        let out = U.run src in
        if List.exists (fun l -> U.contains l "\tproved\t" && U.contains l "\tneed_one\t" && U.contains l "m.march:10:") (U.lines out)
        then Alcotest.failf "a same-arity Option row was proved:\n%s" out);
    gated "a nested user Tree(a) never takes OrderedMap's Tree field roles (review C1)" (fun () ->
        (* No declarant at the top level, so an arity-less lookup's preferred
           declarant is the stdlib's `Tree(k, v)`: its `Node` keeps the
           element fact in field 1, here the user's plain `Int` `k`.  `k` must
           not be proved positive; `v` (the real element) may. *)
        let src field =
          Printf.sprintf
            "mod P1 do\n  mod A do\n    type Tree(a) = Leaf | Node(Tree(a), Int, a, Tree(a), Int)\n\
            \    fn need(x : {Int | _ > 0}) : Int do x end\n\
            \    fn f(t : Tree({Int | _ > 0})) : Int do\n      match t do\n\
            \        Node(_, k, v, _, _) -> need(%s)\n        Leaf -> 1\n      end\n    end\n  end\nend\n"
            field
        in
        U.not_proved (U.run (src "k")) ~line:7 ~callee:"A.need");
    gated "a user arity-0 Tree given an OrderedMap tree is still a type error" (fun () ->
        let src =
          "mod TreeUser do\n  type Tree = Leaf | Node(Tree, Int, Tree)\n\
          \  fn size(t : Tree) : Int do 0 end\n\
          \  fn main() : Int do\n    let m = OrderedMap.put(OrderedMap.new(fn (a, b) -> a - b), 1, 2)\n    size(m.tree)\n  end\nend\n"
        in
        let out = U.run ~args:"--check" src in
        Alcotest.(check bool) ("type error:\n" ^ out) true (U.contains out "expected `Tree`"));
    gated "the rename message names the user's own function" (fun () ->
        let out = U.run leak3 in
        Alcotest.(check bool) ("rename message:\n" ^ out) true (U.contains out "has the same name as a type declared in")) ]

let suite : unit Alcotest.test_case list = parens @ resolution @ shadowing @ arity
