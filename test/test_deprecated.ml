(* `@[deprecated("use X instead")]` on a function
   (specs/lang/compatibility.md, "How something is deprecated").

   The attribute's message rides in [fn_attr_args] as its one string literal.
   The typechecker warns, with the code `deprecated` and the message, at every
   use of the function from outside the module that declares it.  A warning
   never becomes an error. *)

open Test_helpers
module A = March_ast.Ast
module E = March_errors.Errors

let case name f = Alcotest.test_case name `Quick f

(* ── parser ───────────────────────────────────────────────────────────── *)

let attr_payload src =
  match (parse_module src).A.mod_decls with
  | [ A.DMod (_, _, A.DFn (fd, _) :: _, _) ] | A.DFn (fd, _) :: _ ->
    (fd.A.fn_attrs,
     match List.assoc_opt "deprecated" fd.A.fn_attr_args with
     | Some [ A.ELit (A.LitString s, _) ] -> Some s
     | _ -> None)
  | _ -> ([ "<shape>" ], None)

let parse_error src =
  match parse_module src with
  | _ -> "<parsed>"
  | exception E.ParseError (msg, _, _) -> msg

let contains hay needle =
  let n = String.length needle and h = String.length hay in
  let rec go i = i + n <= h && (String.sub hay i n = needle || go (i + 1)) in
  go 0

let parser_tests =
  [ case "the message is the attribute's string payload" (fun () ->
        let attrs, msg = attr_payload {|mod M do
  @[deprecated("use `new_f` instead")]
  fn old_f(n : Int) : Int do n end
end|} in
        Alcotest.(check (list string)) "attrs" [ "deprecated" ] attrs;
        Alcotest.(check (option string)) "message" (Some "use `new_f` instead") msg);
    case "after a doc string, and beside another attribute" (fun () ->
        let attrs, msg = attr_payload {|mod M do
  doc "Old."
  @[no_warn_recursion]
  @[deprecated("gone in 2.0")]
  pfn old_f(n : Int) : Int do n end
end|} in
        Alcotest.(check (list string)) "attrs" [ "no_warn_recursion"; "deprecated" ] attrs;
        Alcotest.(check (option string)) "message" (Some "gone in 2.0") msg);
    case "a bare @[deprecated] is rejected: the message is required" (fun () ->
        let e = parse_error {|mod M do
  @[deprecated]
  fn old_f(n : Int) : Int do n end
end|} in
        Alcotest.(check bool) ("names the form: " ^ e) true (contains e "needs a message"));
    case "a non-string payload is rejected" (fun () ->
        let e = parse_error {|mod M do
  @[deprecated(new_f)]
  fn old_f(n : Int) : Int do n end
end|} in
        Alcotest.(check bool) ("names the form: " ^ e) true (contains e "needs a message"));
    case "another attribute still refuses a string payload" (fun () ->
        let e = parse_error {|mod M do
  @[no_alloc("x")]
  fn f(n : Int) : Int do n end
end|} in
        Alcotest.(check bool) ("still an error: " ^ e) true (e <> "<parsed>"));
    case "the formatter keeps the attribute and its message" (fun () ->
        let src = {|mod M do
  @[deprecated("use `new_f` instead")]
  fn old_f(n : Int) : Int do
    n
  end
end
|} in
        let out = March_format.Format.format_source ~filename:"t.march" src in
        Alcotest.(check bool) ("kept: " ^ out) true
          (contains out {|@[deprecated("use `new_f` instead")]|}));
  ]

(* ── typechecker ──────────────────────────────────────────────────────── *)

let deprecations src =
  let ctx = typecheck src in
  Alcotest.(check bool) "a deprecation is never an error" false (has_errors ctx);
  List.filter (fun (d : E.diagnostic) -> d.E.code = E.Code.deprecated) ctx.E.diagnostics
  |> List.sort (fun (a : E.diagnostic) b -> compare a.E.span.A.start_line b.E.span.A.start_line)

let lib = {|  mod Legacy do
    @[deprecated("use `Legacy.add` instead")]
    fn old_add(a : Int, b : Int) : Int do add(a, b) end

    fn add(a : Int, b : Int) : Int do a + b end

    fn inside() : Int do old_add(1, 2) end

    mod Deep do
      fn nested() : Int do Legacy.old_add(1, 2) end
    end
  end
|}

let with_lib body = "mod Main do\n" ^ lib ^ body ^ "\nend"

let count name n src =
  case name (fun () ->
      Alcotest.(check int) name n (List.length (deprecations (with_lib src))))

let typecheck_tests =
  [ case "a qualified call warns, with the message, as a warning" (fun () ->
        match deprecations (with_lib "  fn main() : Int do Legacy.old_add(1, 2) end") with
        | [ d ] ->
          Alcotest.(check bool) "severity" true (d.E.severity = E.Warning);
          Alcotest.(check string) "message"
            "`Legacy.old_add` is deprecated: use `Legacy.add` instead." d.E.message;
          Alcotest.(check int) "at the use" 14 d.E.span.A.start_line
        | ds -> Alcotest.failf "expected one deprecation, got %d" (List.length ds));
    count "uses inside the declaring module (and modules nested in it) do not warn" 0
      "  fn main() : Int do Legacy.inside() + Legacy.Deep.nested() end";
    count "one warning per use" 2
      "  fn main() : Int do\n    let a = Legacy.old_add(1, 2)\n    Legacy.old_add(a, 3)\n  end";
    count "a reference that is not a call warns too" 1
      "  fn main() : Int do\n    let f = Legacy.old_add\n    f(1, 2)\n  end";
    count "a pipe into it warns" 1 "  fn main() : Int do 1 |> Legacy.old_add(2) end";
    count "the replacement does not warn" 0 "  fn main() : Int do Legacy.add(1, 2) end";
    count "a user function of the same name does not warn" 0
      "  fn old_add(a : Int, b : Int) : Int do a - b end\n  fn main() : Int do old_add(1, 2) end";
    case "an imported name warns at its use" (fun () ->
        let src = {|mod Main do
  mod Legacy do
    @[deprecated("use `add` instead")]
    fn old_add(a : Int, b : Int) : Int do a + b end
  end
  mod App do
    use Legacy.{old_add}
    fn run() : Int do old_add(1, 2) end
  end
end|} in
        match deprecations src with
        | [ d ] -> Alcotest.(check int) "at the call, not the import" 8 d.E.span.A.start_line
        | ds -> Alcotest.failf "expected one deprecation, got %d" (List.length ds));
    case "an alias and a wildcard import warn at each use" (fun () ->
        let src = {|mod Main do
  mod Legacy do
    @[deprecated("use `add` instead")]
    fn old_add(a : Int, b : Int) : Int do a + b end
  end
  mod App do
    alias Legacy, as: L
    use Legacy.*
    fn run() : Int do
      L.old_add(1, 2) +
      old_add(3, 4)
    end
  end
end|} in
        Alcotest.(check (list int)) "lines" [ 10; 11 ]
          (List.map (fun (d : E.diagnostic) -> d.E.span.A.start_line) (deprecations src)));
    case "`deprecated` is a registered code" (fun () ->
        Alcotest.(check bool) "registered" true (List.mem E.Code.deprecated E.Code.all));
  ]

let tests = parser_tests @ typecheck_tests
