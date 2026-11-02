(* Per-function `needs` bounds (specs/plans/2026-11-01-per-function-needs-bounds.md).

   `fn f(x) needs IO.Console do` holds [f]'s transitive reach under the bound
   and the bound under the module's `needs`.  Every accept case has a reject
   twin: an accept-only test cannot tell "checked and fine" from "not
   looked at", which is how the impl-method gap in the first draft would have
   shipped. *)

let codes src =
  let errors = Test_helpers.typecheck src in
  List.filter_map
    (fun (d : March_errors.Errors.diagnostic) ->
      if d.March_errors.Errors.severity = March_errors.Errors.Error then
        Some d.March_errors.Errors.code
      else None)
    errors.March_errors.Errors.diagnostics

let messages src =
  let errors = Test_helpers.typecheck src in
  List.map
    (fun (d : March_errors.Errors.diagnostic) -> d.March_errors.Errors.message)
    errors.March_errors.Errors.diagnostics

let m body = Printf.sprintf "mod M do\n  needs IO.Console, IO.Clock\n%s\nend" body

let clean name src = Alcotest.(check (list string)) name [] (codes src)

let rejects code name src =
  Alcotest.(check bool) name true (List.mem code (codes src))

let contains s sub =
  let n = String.length sub and h = String.length s in
  let rec go i = i + n <= h && (String.sub s i n = sub || go (i + 1)) in
  go 0

let test_direct_reach () =
  clean "a bound covering the reach"
    (m "  fn f(s : String) : Unit needs IO.Console do println(s) end");
  rejects "cap_bound" "`needs ()` over a println"
    (m "  fn f(s : String) : Unit needs () do println(s) end")

let test_transitive_reach_names_the_chain () =
  let src =
    m {|  pfn log(s : String) : Unit do println(s) end
  fn f(s : String) : Unit needs IO.Clock do log(s) end|}
  in
  rejects "cap_bound" "reach through a helper" src;
  Alcotest.(check bool) "the chain names the helper" true
    (List.exists (fun msg -> contains msg "via log") (messages src))

let test_bound_within_module_needs () =
  clean "a bound inside the module's needs"
    (m "  fn f() : Unit needs IO.Clock do () end");
  rejects "cap_bound_needs" "a bound wider than the module"
    (m "  fn f() : Unit needs IO.NetConnect do () end")

let test_parent_bound_covers_child () =
  (* The bound is a lattice test: a parent capability covers its children,
     and not the other way round. *)
  clean "IO.FileSystem covers IO.FileRead"
    {|mod M do
  needs IO.FileSystem
  fn f(p : String) needs IO.FileSystem do
    match file_read(p) do
      Ok(_) -> 1
      Err(_) -> 0
    end
  end
end|};
  rejects "cap_bound" "IO.FileRead does not cover a write"
    {|mod M do
  needs IO.FileSystem
  fn f(p : String) needs IO.FileRead do
    match file_write(p, "x") do
      Ok(_) -> 1
      Err(_) -> 0
    end
  end
end|}

let test_unknown_capability () =
  rejects "unknown_capability" "a typo in the bound"
    (m "  fn f() : Unit needs IO.Consle do () end")

let test_callback_not_charged () =
  (* "My own authority, plus whatever you hand me": invoking a parameter is
     charged to whoever supplies it, not to the bounded function. *)
  clean "invoking a parameter"
    (m "  fn apply(f : Int -> Int, x : Int) : Int needs () do f(x) end")

let test_untraceable_invocation_refused () =
  let body bound =
    m (Printf.sprintf {|  fn first(fs : List((Int -> Int))) : Int needs %s do
    match fs do
      Cons(f, _) -> f(1)
      Nil -> 0
    end
  end|} bound)
  in
  rejects "cap_bound" "a narrow bound over a list-held function" (body "IO.Console");
  Alcotest.(check bool) "the message says why" true
    (List.exists (fun msg -> contains msg "cannot trace") (messages (body "()")));
  clean "a bound of all of IO claims nothing to refuse"
    (Printf.sprintf {|mod M do
  needs IO
  fn first(fs : List((Int -> Int))) : Int needs IO do
    match fs do
      Cons(f, _) -> f(1)
      Nil -> 0
    end
  end
end|})

let test_no_effect_on_callers () =
  (* The bound narrows the bounded function only: a caller reaching more
     than the callee's bound is judged by its own module, as before. *)
  clean "an unbounded caller of a bounded function"
    (m {|  fn quiet(x : Int) : Int needs () do x end
  fn loud(x : Int) : Int do
    println(int_to_string(x))
    quiet(x)
  end|})

let test_multi_clause () =
  clean "a bound on one clause"
    (m "  fn f(0) needs () do 0 end\n  fn f(n) do n end");
  rejects "cap_bound" "and it covers every clause"
    (m "  fn f(0) needs () do 0 end\n  fn f(n) do\n    println(\"x\")\n    n\n  end")

let test_multi_clause_conflict () =
  match Test_helpers.parse_module (m "  fn f(0) needs () do 0 end\n  fn f(n) needs IO.Console do n end") with
  | exception _ -> ()
  | _ -> Alcotest.fail "two clauses with different bounds should not parse"

let test_nested_module () =
  rejects "cap_bound" "a nested module's function"
    {|mod M do
  mod Inner do
    needs IO.Console
    fn shout(s : String) : Unit needs () do println(s) end
  end
end|}

let test_impl_method () =
  let src bound =
    Printf.sprintf {|mod M do
  needs IO.Console
  interface Show(a) do
    fn show : a -> String
  end
  type T = T(Int)
  impl Show(T) do
    fn show(_t) needs %s do
      println("x")
      "t"
    end
  end
end|} bound
  in
  clean "an impl method within its bound" (src "IO.Console");
  rejects "cap_bound" "an impl method outside its bound" (src "()")

let test_formatter_keeps_the_bound () =
  (* A formatter that dropped the clause would silently widen the function
     to its module's needs. *)
  let src = m "  fn f(s : String) : Unit needs IO.Console, IO.Clock do println(s) end\n  fn g() needs () do () end" in
  let out = March_format.Format.format_source ~filename:"t.march" src in
  Alcotest.(check bool) "list bound kept" true (contains out "needs IO.Console, IO.Clock do");
  Alcotest.(check bool) "empty bound kept" true (contains out "needs () do")

let tests =
  [ Alcotest.test_case "direct reach" `Quick test_direct_reach
  ; Alcotest.test_case "transitive reach names the chain" `Quick test_transitive_reach_names_the_chain
  ; Alcotest.test_case "bound within module needs" `Quick test_bound_within_module_needs
  ; Alcotest.test_case "parent bound covers child" `Quick test_parent_bound_covers_child
  ; Alcotest.test_case "unknown capability" `Quick test_unknown_capability
  ; Alcotest.test_case "callback not charged" `Quick test_callback_not_charged
  ; Alcotest.test_case "untraceable invocation refused" `Quick test_untraceable_invocation_refused
  ; Alcotest.test_case "no effect on callers" `Quick test_no_effect_on_callers
  ; Alcotest.test_case "multi-clause" `Quick test_multi_clause
  ; Alcotest.test_case "multi-clause conflict" `Quick test_multi_clause_conflict
  ; Alcotest.test_case "nested module" `Quick test_nested_module
  ; Alcotest.test_case "impl method" `Quick test_impl_method
  ; Alcotest.test_case "formatter keeps the bound" `Quick test_formatter_keeps_the_bound
  ]
