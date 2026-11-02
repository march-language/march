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

(* ── Phase 2: interface method bounds ─────────────────────────────────── *)

let iface_src = {|mod M do
  interface Store(a) do
    fn get : a -> Int needs IO.FileRead
    fn put : a -> Unit needs ()
    fn name : a -> String
  end
end|}

let iface_methods src =
  let m = Test_helpers.parse_module src in
  List.concat_map
    (function
      | March_ast.Ast.DInterface (idef, _) -> idef.March_ast.Ast.iface_methods
      | _ -> [])
    m.March_ast.Ast.mod_decls

let needs_paths (md : March_ast.Ast.method_decl) =
  Option.map
    (fun (paths, _) ->
      List.map (fun p -> String.concat "." (List.map (fun (n : March_ast.Ast.name) -> n.txt) p)) paths)
    md.March_ast.Ast.md_needs

let test_iface_bound_parses () =
  let got = List.map needs_paths (iface_methods iface_src) in
  Alcotest.(check (list (option (list string)))) "bounds per method"
    [ Some [ "IO.FileRead" ]; Some []; None ] got

let test_iface_bound_with_default_parses () =
  let src = {|mod M do
  interface Label(a) do
    fn label : a -> String needs () do fn (_) -> "x" end
  end
end|} in
  match iface_methods src with
  | [ md ] ->
    Alcotest.(check (option (list string))) "empty bound" (Some []) (needs_paths md);
    Alcotest.(check bool) "default kept" true (md.March_ast.Ast.md_default <> None)
  | l -> Alcotest.failf "expected one method, got %d" (List.length l)

let test_iface_formatter_keeps_the_bound () =
  let out = March_format.Format.format_source ~filename:"t.march" iface_src in
  Alcotest.(check bool) "list bound kept" true (contains out "fn get : a -> Int needs IO.FileRead");
  Alcotest.(check bool) "empty bound kept" true (contains out "fn put : a -> Unit needs ()");
  Alcotest.(check string) "idempotent" out
    (March_format.Format.format_source ~filename:"t.march" out)

(* An interface bound is checked on every impl, and on the default body.  It is
   never part of the method's type: callers and [when] constraints see nothing
   new, which is the "no capability threading" rule. *)
let shows ?(iface_needs = "needs ()") ?(module_needs = "IO.Console") impl_body =
  Printf.sprintf {|mod M do
  needs %s
  interface Show(a) do
    fn show : a -> String %s
  end
  type T = T(Int)
  pfn log(s : String) : Unit do println(s) end
  impl Show(T) do
    fn show(_t) do
%s
    end
  end
end|} module_needs iface_needs impl_body

let test_impl_inherits_iface_bound () =
  clean "a pure impl under `needs ()`" (shows {|      "t"|});
  rejects "cap_bound" "an impl that prints under `needs ()`"
    (shows {|      println("x")
      "t"|})

let test_iface_bound_message_names_the_interface () =
  let msgs = messages (shows {|      println("x")
      "t"|}) in
  Alcotest.(check bool) "names the interface" true
    (List.exists (fun msg -> contains msg "interface `Show`") msgs);
  Alcotest.(check bool) "names the impl" true
    (List.exists (fun msg -> contains msg "impl Show(T)") msgs)

let test_iface_bound_transitive_chain () =
  let src = shows {|      log("x")
      "t"|} in
  rejects "cap_bound" "reach through a helper" src;
  Alcotest.(check bool) "the chain names the helper" true
    (List.exists (fun msg -> contains msg "via log") (messages src))

let test_iface_default_body_checked () =
  let src default = Printf.sprintf {|mod M do
  needs IO.Console
  interface Label(a) do
    fn label : a -> String needs () do fn (_) -> %s end
  end
end|} default in
  clean "a pure default" (src {|"x"|});
  rejects "cap_bound" "a default that prints"
    (src {|do
      println("x")
      "x"
    end|})

let test_iface_unbounded_method_unchecked () =
  clean "no bound on the method constrains nothing"
    (shows ~iface_needs:"" {|      println("x")
      "t"|})

let test_iface_bound_outside_module_needs () =
  (* The bound limits other modules' impls, so it need not lie within the
     declaring module's needs; it must still name real capabilities. *)
  let src bound = Printf.sprintf {|mod M do
  interface Sink(a) do
    fn emit : a -> Unit needs %s
  end
end|} bound in
  clean "a bound the module does not itself need" (src "IO.Console");
  rejects "unknown_capability" "a misspelt capability" (src "IO.Consol")

let test_iface_bound_cross_module () =
  let src body = Printf.sprintf {|mod M do
  mod A do
    interface Sink(a) do
      fn emit : a -> Unit needs ()
    end
  end
  mod B do
    needs IO.Console
    type T = T(Int)
    impl A.Sink(T) do
      fn emit(_t) do
%s
      end
    end
  end
end|} body in
  clean "a pure impl in another module" (src "        ()");
  rejects "cap_bound" "an impl in another module that prints"
    (src {|        println("x")|})

let test_iface_bound_no_threading () =
  (* A generic caller of a bounded method declares nothing and gets no new
     diagnostic; the call is still charged the impls' own reach (the
     dispatch node), which a bounded generic caller exposes. *)
  let src sync_bound = Printf.sprintf {|mod M do
  needs IO.Console
  interface Store(a) do
    fn put : a -> Unit needs IO.Console
  end
  type T = T(Int)
  impl Store(T) do
    fn put(_t) do println("x") end
  end
  fn sync(s : a) : Unit %s when Store(a) do put(s) end
  fn run() : Unit do sync(T(1)) end
end|} sync_bound in
  clean "an unbounded generic caller and its caller" (src "");
  rejects "cap_bound" "a generic caller bounded by `needs ()` is still charged the impl"
    (src "needs ()")

let test_iface_bound_untraceable_invocation () =
  let src = {|mod M do
  needs IO.Console
  interface Run(a) do
    fn run : a -> Int needs ()
  end
  type T = T(List((Int -> Int)))
  impl Run(T) do
    fn run(t) do
      match t do
        T(fs) -> match fs do
          Cons(f, _) -> f(1)
          Nil -> 0
        end
      end
    end
  end
end|} in
  rejects "cap_bound" "an untraceable call under a narrow interface bound" src;
  Alcotest.(check bool) "the message says why" true
    (List.exists (fun msg -> contains msg "cannot trace") (messages src))

(* An impl method's capability key is [<scope>.<Iface>$<Ty>.<m>], so "the part
   before the last dot" is [<scope>.<Iface>$<Ty>], not the module.  Resolving a
   local helper against that missed it in a nested module (the bare-name
   fallback only rescues the entry module), so the impl was charged nothing
   for what the helper does.  Each case reaches IO.Console only via [log]. *)
let nested_impl ~iface_needs ~impl_needs =
  Printf.sprintf {|mod X do
  mod B do
    needs IO.Console
    interface Sink(a) do
      fn emit : a -> Unit %s
    end
    type T = T(Int)
    pfn log(s : String) : Unit do println(s) end
    impl Sink(T) do
      fn emit(_t) %s do log("x") end
    end
  end
end|} iface_needs impl_needs

let test_nested_impl_helper_reach () =
  rejects "cap_bound" "an impl's own bound, in a nested module"
    (nested_impl ~iface_needs:"" ~impl_needs:"needs ()");
  rejects "cap_bound" "an inherited bound, in a nested module"
    (nested_impl ~iface_needs:"needs ()" ~impl_needs:"");
  clean "a bound covering the helper's reach"
    (nested_impl ~iface_needs:"needs IO.Console" ~impl_needs:"");
  Alcotest.(check bool) "the chain names the helper" true
    (List.exists (fun msg -> contains msg "log)")
       (messages (nested_impl ~iface_needs:"needs ()" ~impl_needs:"")))

let test_nested_default_helper_reach () =
  rejects "cap_bound" "a default body reaching IO through a helper, in a nested module"
    {|mod X do
  mod B do
    needs IO.Console
    pfn log(s : String) : String do
      println(s)
      s
    end
    interface Label(a) do
      fn label : a -> String needs () do fn (_) -> log("x") end
    end
  end
end|}

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
  ; Alcotest.test_case "interface bound parses" `Quick test_iface_bound_parses
  ; Alcotest.test_case "interface bound with default parses" `Quick test_iface_bound_with_default_parses
  ; Alcotest.test_case "interface formatter keeps the bound" `Quick test_iface_formatter_keeps_the_bound
  ; Alcotest.test_case "impl inherits interface bound" `Quick test_impl_inherits_iface_bound
  ; Alcotest.test_case "interface bound message names the interface" `Quick test_iface_bound_message_names_the_interface
  ; Alcotest.test_case "interface bound transitive chain" `Quick test_iface_bound_transitive_chain
  ; Alcotest.test_case "interface default body checked" `Quick test_iface_default_body_checked
  ; Alcotest.test_case "unbounded interface method unchecked" `Quick test_iface_unbounded_method_unchecked
  ; Alcotest.test_case "interface bound outside module needs" `Quick test_iface_bound_outside_module_needs
  ; Alcotest.test_case "interface bound cross-module" `Quick test_iface_bound_cross_module
  ; Alcotest.test_case "interface bound adds no threading" `Quick test_iface_bound_no_threading
  ; Alcotest.test_case "interface bound untraceable invocation" `Quick test_iface_bound_untraceable_invocation
  ; Alcotest.test_case "nested impl helper reach" `Quick test_nested_impl_helper_reach
  ; Alcotest.test_case "nested default helper reach" `Quick test_nested_default_helper_reach
  ]
