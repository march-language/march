(** Smoke tests for [March_dump.Ast_json] — the core-AST -> JSON serializer
    (Task 1 of the emit-core-ast plan, specs/plans/2026-07-20-emit-core-ast-a0.md).

    These are substring "contains the right `"kind":"..."`  markers" checks,
    not a byte-for-byte golden test (that's Task 3, against the real CLI
    binary). The goal here is just to prove the serializer produces sane,
    tagged JSON for a representative sample of AST shapes: a literal, a
    pattern (from a match), a record type/expr, an ADT decl, and a function
    decl. *)

let parse_and_desugar src =
  let lexbuf = Lexing.from_string src in
  let m =
    March_parser.Parser.module_
      (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
  in
  March_desugar.Desugar.desugar_module m

let json_of src = March_dump.Ast_json.module_to_json (parse_and_desugar src)

let contains ~needle haystack =
  let nlen = String.length needle and hlen = String.length haystack in
  let rec go i = i + nlen <= hlen && (String.sub haystack i nlen = needle || go (i + 1)) in
  go 0

let check_contains json needle =
  Alcotest.(check bool)
    (Printf.sprintf "JSON contains %S" needle)
    true (contains ~needle json)

(* ── literal ─────────────────────────────────────────────────────────── *)

let test_literal () =
  let src = {|mod M do
    fn f() : Int do 42 end
  end|} in
  let json = json_of src in
  check_contains json {|"kind":"LitInt"|};
  check_contains json {|"value":42|};
  check_contains json {|"kind":"DFn"|}

(* ── pattern (from a match) ─────────────────────────────────────────── *)

let test_pattern_match () =
  let src = {|mod M do
    type Shape = Circle(Int) | Square(Int)

    fn area(s : Shape) : Int do
      match s do
        Circle(r) -> r
        Square(x) -> x
      end
    end
  end|} in
  let json = json_of src in
  check_contains json {|"kind":"EMatch"|};
  check_contains json {|"kind":"PatCon"|};
  check_contains json {|"kind":"TDVariant"|}

(* ── record type / expr ─────────────────────────────────────────────── *)

let test_record_type_and_expr () =
  let src = {|mod M do
    type Point = { x : Int, y : Int }

    fn origin() : Point do { x: 0, y: 0 } end
  end|} in
  let json = json_of src in
  check_contains json {|"kind":"TDRecord"|};
  check_contains json {|"kind":"ERecord"|};
  check_contains json {|"txt":"x"|}

(* ── ADT decl ────────────────────────────────────────────────────────── *)

let test_adt_decl () =
  let src = {|mod M do
    type Hue = Rood | Bloo

    fn name(c : Hue) : String do
      match c do
        Rood -> "red"
        Bloo -> "blue"
      end
    end
  end|} in
  let json = json_of src in
  check_contains json {|"kind":"DType"|};
  check_contains json {|"kind":"TDVariant"|};
  check_contains json {|"txt":"Rood"|};
  check_contains json {|"txt":"Bloo"|}

(* ── function decl ──────────────────────────────────────────────────── *)

let test_function_decl () =
  let src = {|mod M do
    fn add(x : Int, y : Int) : Int do x + y end
  end|} in
  let json = json_of src in
  check_contains json {|"kind":"DFn"|};
  check_contains json {|"txt":"add"|};
  check_contains json {|"kind":"FPNamed"|}

(* ── module-level shape: top-level span present everywhere expected ───── *)

let test_module_has_span_fields () =
  let src = {|mod M do
    fn f() : Int do 1 end
  end|} in
  let json = json_of src in
  check_contains json {|"span":{"file"|};
  check_contains json {|"start_line"|};
  check_contains json {|"end_col"|}

let suite =
  [
    Alcotest.test_case "literal (LitInt) appears tagged" `Quick test_literal;
    Alcotest.test_case "pattern from match (PatCon) appears tagged" `Quick test_pattern_match;
    Alcotest.test_case "record type/expr appear tagged" `Quick test_record_type_and_expr;
    Alcotest.test_case "ADT decl (TDVariant) appears tagged" `Quick test_adt_decl;
    Alcotest.test_case "function decl (DFn) appears tagged" `Quick test_function_decl;
    Alcotest.test_case "span fields present" `Quick test_module_has_span_fields;
  ]

let () = Alcotest.run "march-ast-json" [ ("ast_json", suite) ]
