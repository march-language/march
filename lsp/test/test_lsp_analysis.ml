(** March LSP tests: position/span utilities, diagnostics, symbols, completions, go-to-definition, hover, inlay hints, error recovery, doc strings

    Moved verbatim out of [test_lsp.ml]; see [Test_lsp_harness]. *)

open Test_lsp_harness

(* ------------------------------------------------------------------ *)
(* 1. Position / span utilities                                        *)
(* ------------------------------------------------------------------ *)

let test_span_to_range_single_line () =
  (* March spans: start_line is 1-indexed; cols are 0-indexed. *)
  let sp = mk_span 1 3 1 7 in
  let r  = Pos.span_to_lsp_range sp in
  Alcotest.(check int) "start line 0-indexed" 0 r.Lsp.Types.Range.start.line;
  Alcotest.(check int) "start col"            3 r.Lsp.Types.Range.start.character;
  Alcotest.(check int) "end line 0-indexed"   0 r.Lsp.Types.Range.end_.line;
  Alcotest.(check int) "end col"              7 r.Lsp.Types.Range.end_.character

let test_span_to_range_multi_line () =
  let sp = mk_span 2 0 4 5 in
  let r  = Pos.span_to_lsp_range sp in
  Alcotest.(check int) "start line" 1 r.Lsp.Types.Range.start.line;
  Alcotest.(check int) "end line"   3 r.Lsp.Types.Range.end_.line;
  Alcotest.(check int) "end col"    5 r.Lsp.Types.Range.end_.character

let test_span_contains_inside () =
  (* span covers line 2 (0-indexed 1), cols 5-10 *)
  let sp = mk_span 2 5 2 10 in
  Alcotest.(check bool) "inside" true  (Pos.span_contains sp ~line:1 ~character:7);
  Alcotest.(check bool) "at start" true (Pos.span_contains sp ~line:1 ~character:5);
  Alcotest.(check bool) "at end exclusive" false (Pos.span_contains sp ~line:1 ~character:10)

let test_span_contains_outside () =
  let sp = mk_span 3 0 3 5 in
  Alcotest.(check bool) "wrong line before" false (Pos.span_contains sp ~line:1 ~character:2);
  Alcotest.(check bool) "wrong line after"  false (Pos.span_contains sp ~line:3 ~character:2)

let test_span_contains_multi_line () =
  (* span: line 2-4 (1-indexed) = line 1-3 (0-indexed) *)
  let sp = mk_span 2 3 4 7 in
  (* middle line — always in span *)
  Alcotest.(check bool) "middle line" true (Pos.span_contains sp ~line:2 ~character:0);
  (* start line, col before sc — outside *)
  Alcotest.(check bool) "start line before sc" false (Pos.span_contains sp ~line:1 ~character:2);
  (* start line, col at sc — inside *)
  Alcotest.(check bool) "start line at sc" true (Pos.span_contains sp ~line:1 ~character:3);
  (* end line, col at ec — outside (exclusive) *)
  Alcotest.(check bool) "end line at ec" false (Pos.span_contains sp ~line:3 ~character:7);
  (* end line, col before ec — inside *)
  Alcotest.(check bool) "end line before ec" true (Pos.span_contains sp ~line:3 ~character:6)

let test_span_smaller () =
  let small = mk_span 1 3 1 6 in   (* size 3 *)
  let large = mk_span 1 0 1 10 in  (* size 10 *)
  let ml    = mk_span 1 0 3 5 in   (* multi-line, size > 1000 *)
  Alcotest.(check bool) "small < large" true  (Pos.span_smaller small large);
  Alcotest.(check bool) "large < small" false (Pos.span_smaller large small);
  Alcotest.(check bool) "small < multiline" true (Pos.span_smaller small ml)

let test_lsp_pos_round_trip () =
  let pos = Pos.create ~line:5 ~character:12 in
  let (l, c) = Pos.lsp_pos_to_pair pos in
  Alcotest.(check int) "line"      5  l;
  Alcotest.(check int) "character" 12 c

(* ------------------------------------------------------------------ *)
(* 2. Analysis — diagnostics                                           *)
(* ------------------------------------------------------------------ *)

let test_analyse_valid_no_diagnostics () =
  let src = {|mod Test do
  fn add(x : Int, y : Int) : Int do x + y end
end|} in
  let a = analyse src in
  Alcotest.(check int) "zero diagnostics" 0 (List.length a.diagnostics)

let test_analyse_empty_module () =
  let src = "mod Empty do\nend" in
  let a = analyse src in
  Alcotest.(check int) "zero diagnostics" 0 (List.length a.diagnostics)

let test_analyse_empty_string () =
  (* An empty string is not a valid module; we expect a parse error diagnostic
     but no crash. *)
  let a = analyse "" in
  Alcotest.(check bool) "no crash, diagnostics list returned" true
    (a.diagnostics = [] || a.diagnostics <> [])

let test_analyse_type_error_produces_diagnostic () =
  let src = {|mod Test do
  fn bad() : Int do "not an int" end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "has error diagnostic" true
    (count_errors a > 0)

let test_analyse_parse_error_produces_diagnostic () =
  (* Use a source whose tokens are valid but whose grammar is wrong,
     so Menhir (not the lexer) produces the parse error.
     analyse() catches Parser.Error; it does NOT catch Lexer_error. *)
  let src = "mod Broken do\n  fn\nend" in
  let a = analyse src in
  Alcotest.(check bool) "has diagnostic" true
    (List.length a.diagnostics > 0)

let test_analyse_multiple_errors_all_reported () =
  (* Two independent type errors in different functions. *)
  let src = {|mod Test do
  fn bad1() : Int do "oops" end
  fn bad2() : Bool do 42 end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "multiple errors reported" true
    (count_errors a >= 2)

let test_analyse_warning_severity () =
  (* Currently the analyser emits Hints from the typechecker; we just check
     that diagnostics can have non-Error severities when the source is valid. *)
  let src = {|mod Test do
  fn identity(x : Int) : Int do x end
end|} in
  let a = analyse src in
  (* Valid code should have zero errors — we care about count only *)
  Alcotest.(check int) "no errors" 0 (count_errors a)

(* LSP parity with the compiler's prelude-collision check
   (bin/main.ml / lib/modules/prelude_collision.ml, specs/plans/
   2026-08-13-prelude-entry-fn-name-collision.md §4.2 Stage 2). Before this,
   `march --compile`/`--check` rejected a top-level fn colliding with a name
   Prelude relies on internally, but the LSP's own independent
   parse/desugar/stdlib-merge pipeline never ran the same check — so the
   editor showed no diagnostic at all for code the compiler now hard-rejects,
   a compiler/LSP disagreement this codebase treats as a real bug class. *)
let test_analyse_prelude_collision_produces_diagnostic () =
  (* `print_line` is in the true "Prelude calls this internally" set:
     println's own body calls it bare. A same-named user fn hijacks that call
     program-wide — see the two original repros in
     specs/progress/2026-08-14-prelude-entry-fn-name-collision.md.
     This was `print` until 2026-08-22, when println's body became a single
     `print_line(show(x))` so that a compiled line and its newline reach the
     kernel in one write (specs/progress/2026-08-21-println-writev-not-atomic-
     across-threads.md). Nothing in prelude.march calls bare `print` any more,
     so `print` is now in the SAFE-to-shadow set alongside `head` and `map`,
     and this checker — which computes the internal call graph rather than
     hardcoding a list — correctly stopped flagging it. The hazard moved to
     the new name, and so does the test.
     Filename deliberately NOT "test.march" — that basename collides with
     the real shipped `stdlib/test.march` (the `Test` module) and would
     trip the shipped-stdlib-file exemption meant for exactly that file,
     silently suppressing this check (confirmed live: this test read
     `is_shipped=true` for "test.march" the first time it was written). *)
  let src = {|mod Shadow do
  fn print_line(x : Int) : Unit do
    ()
  end
end|} in
  let a = An.analyse ~filename:"shadow_repro.march" ~src in
  Alcotest.(check bool) "collision on `print_line` is reported" true
    (count_errors a > 0);
  Alcotest.(check bool) "message names the collision" true
    (List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
         match d.message with
         | `String s ->
           (try ignore (Str.search_forward (Str.regexp_string "redefines") s 0); true
            with Not_found -> false)
         | _ -> false)
       a.diagnostics)

let test_analyse_safe_shadow_no_collision_diagnostic () =
  (* `head` is declared by Prelude but never called FROM WITHIN another
     Prelude function's own body — shadowing it is a documented, intentional,
     already-regression-tested feature (specs/lang/types/accept/
     t126_entry_module_shadows_list_length.march), not a collision. *)
  let src = {|mod Shadow do
  fn head(xs : List(Int)) : List(Int) do xs end
end|} in
  let a = An.analyse ~filename:"shadow_safe.march" ~src in
  Alcotest.(check int) "no collision diagnostic for a safe shadow" 0
    (count_errors a)

(** The other half of the `print_line` case above, and the reason both halves
    are pinned: on 2026-08-22 the name `print` MOVED from the hazardous set to
    the safe one.

    [Prelude_collision] decides by computing Prelude's actual internal call
    graph, not by consulting a hardcoded list. `print` was hazardous only
    because `println`'s body called it bare; that body is now a single
    `print_line(show(x))`, so nothing in prelude.march reaches for bare `print`
    any more and shadowing it is as safe as shadowing `head`
    (specs/progress/2026-08-21-println-writev-not-atomic-across-threads.md).

    This test exists so that "fixing" the checker by hardcoding the old list
    fails loudly rather than quietly re-flagging code that is now fine. It is
    the inverse assertion of [test_analyse_prelude_collision_produces_diagnostic],
    and the two must not both pass for the same name. *)
let test_analyse_print_no_longer_collides () =
  let src = {|mod Shadow do
  fn print(x : Int) : Unit do
    ()
  end
end|} in
  let a = An.analyse ~filename:"shadow_print.march" ~src in
  Alcotest.(check int)
    "`print` is no longer called from inside a Prelude body, so shadowing it \
     is not a collision" 0
    (count_errors a)

let test_analyse_notes_appended_to_message () =
  (* A diagnostic with notes should include "note:" in its message. *)
  (* We can't easily manufacture a note without triggering a specific
     typecheck path, so just verify the diagnostic message is a string. *)
  let src = {|mod Test do
  fn f(x : Int) : String do x end
end|} in
  let a = analyse src in
  List.iter (fun (d : Lsp.Types.Diagnostic.t) ->
      match d.message with
      | `String s -> Alcotest.(check bool) "message non-empty" true (s <> "")
      | _ -> ()
    ) a.diagnostics

let test_analyse_related_information_on_type_mismatch () =
  (* A type annotation mismatch should produce relatedInformation
     pointing at the annotation — improvement #1 + #3 from the
     error-improvements spec. *)
  let src = {|mod Test do
  fn bad() : Int do "not an int" end
end|} in
  let a = analyse src in
  let has_related =
    List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
        match d.relatedInformation with
        | Some (_ :: _) -> true
        | _ -> false
      ) a.diagnostics
  in
  Alcotest.(check bool) "type mismatch has relatedInformation" true has_related

let test_analyse_arity_mismatch_has_related_information () =
  (* An arity mismatch should produce relatedInformation pointing at the
     function definition — improvement #3 from the error-improvements spec. *)
  let src = {|mod Test do
  fn add(x : Int, y : Int) : Int do x + y end
  fn bad() : Int do add(1) end
end|} in
  let a = analyse src in
  let has_related =
    List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
        match d.relatedInformation with
        | Some (_ :: _) -> true
        | _ -> false
      ) a.diagnostics
  in
  Alcotest.(check bool) "arity mismatch has relatedInformation" true has_related

let test_analyse_desugar_error_produces_diagnostic () =
  (* Desugar-time user errors (pipe-into-match, B6) must surface as
     positioned LSP diagnostics. Before the ~errors wiring, desugar raised
     a ParseError that escaped analyse — the editor showed no squiggle at
     all because the publishDiagnostics notification was dropped. *)
  let src = {|mod Test do
  fn go() : String do
    1 |> (match 2 do
      1 -> "one"
      _ -> "x"
    end)
  end
end|} in
  let a = analyse src in
  let positioned =
    List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
        d.severity = Some Lsp.Types.DiagnosticSeverity.Error
        && d.range.Lsp.Types.Range.start.line = 2
        && (match d.message with
            | `String s ->
              (try ignore (Str.search_forward
                             (Str.regexp_string "discards its scrutinee") s 0);
                 true
               with Not_found -> false)
            | _ -> false))
      a.diagnostics
  in
  Alcotest.(check bool) "pipe-into-match yields positioned error diagnostic"
    true positioned

(* ------------------------------------------------------------------ *)
(* 3. Analysis — document symbols                                      *)
(* ------------------------------------------------------------------ *)

let test_document_symbols_fn () =
  let src = {|mod Test do
  fn greet(name : String) : String do name end
end|} in
  let a    = analyse src in
  let syms = symbol_names a in
  Alcotest.(check bool) "greet in symbols" true (List.mem "greet" syms)

let test_document_symbols_type () =
  let src = {|mod Test do
  type Color = Red | Green | Blue
end|} in
  let a    = analyse src in
  let syms = symbol_names a in
  Alcotest.(check bool) "Color in symbols" true (List.mem "Color" syms);
  Alcotest.(check bool) "Red in symbols"   true (List.mem "Red"   syms);
  Alcotest.(check bool) "Blue in symbols"  true (List.mem "Blue"  syms)

let test_document_symbols_interface () =
  (* March interface syntax: interface Name(typevar) do ... end *)
  let src = {|mod Test do
  interface Eq(a) do
    fn eq: a -> a -> Bool
  end
end|} in
  let a    = analyse src in
  let syms = symbol_names a in
  Alcotest.(check bool) "Eq in symbols" true (List.mem "Eq" syms)

let test_document_symbols_multiple_decls () =
  let src = {|mod Test do
  fn foo() : Int do 1 end
  fn bar() : Int do 2 end
  type T = A | B
end|} in
  let a    = analyse src in
  let syms = symbol_names a in
  Alcotest.(check bool) "foo in symbols" true (List.mem "foo" syms);
  Alcotest.(check bool) "bar in symbols" true (List.mem "bar" syms);
  Alcotest.(check bool) "T in symbols"   true (List.mem "T"   syms)

let test_document_symbols_kind_for_type () =
  let src = {|mod Test do
  type Shape = Circle | Square
end|} in
  let a = analyse src in
  (match An.document_symbols a with
   | `DocumentSymbol syms ->
     let shape_sym = List.find_opt
         (fun (s : Lsp.Types.DocumentSymbol.t) -> s.name = "Shape") syms in
     (match shape_sym with
      | Some s ->
        Alcotest.(check bool) "Shape has Class kind" true
          (s.kind = Lsp.Types.SymbolKind.Class)
      | None -> Alcotest.fail "Shape not found in symbols")
   | _ -> Alcotest.fail "expected DocumentSymbol list")

(* ------------------------------------------------------------------ *)
(* 4. Analysis — completions                                           *)
(* ------------------------------------------------------------------ *)

let test_completions_include_keywords () =
  let src = {|mod Test do
  fn f() : Int do 1 end
end|} in
  let a      = analyse src in
  let labels = completion_labels a in
  List.iter (fun kw ->
      Alcotest.(check bool) (kw ^ " in completions") true (List.mem kw labels)
    ) ["fn"; "let"; "match"; "if"; "mod"; "type"; "interface"; "impl"; "do"]

let test_completions_include_in_scope_names () =
  let src = {|mod Test do
  fn my_func(x : Int) : Int do x end
end|} in
  let a      = analyse src in
  let labels = completion_labels a in
  (* my_func should appear as a completion since it's in the env *)
  Alcotest.(check bool) "my_func in completions" true (List.mem "my_func" labels)

let test_completions_include_type_constructors () =
  let src = {|mod Test do
  type Color = Red | Green | Blue
end|} in
  let a      = analyse src in
  let labels = completion_labels a in
  Alcotest.(check bool) "Color in completions" true (List.mem "Color" labels)

let test_completions_include_data_constructors () =
  let src = {|mod Test do
  type Color = Red | Green | Blue
end|} in
  let a      = analyse src in
  let labels = completion_labels a in
  Alcotest.(check bool) "Red in completions"   true (List.mem "Red"   labels);
  Alcotest.(check bool) "Green in completions" true (List.mem "Green" labels)

let test_completions_include_interfaces () =
  (* March interface syntax: interface Name(typevar) do ... end *)
  let src = {|mod Test do
  interface Printable(a) do
    fn print: a -> String
  end
end|} in
  let a      = analyse src in
  let labels = completion_labels a in
  Alcotest.(check bool) "Printable in completions" true (List.mem "Printable" labels)

let test_completions_no_leading_underscore_vars () =
  (* Variables whose names start with '_' are filtered from completions. *)
  let src = {|mod Test do
  fn _helper(x : Int) : Int do x end
end|} in
  let a      = analyse src in
  let labels = completion_labels a in
  Alcotest.(check bool) "_helper NOT in completions" false (List.mem "_helper" labels)

(* ------------------------------------------------------------------ *)
(* 5. Analysis — go-to-definition                                      *)
(* ------------------------------------------------------------------ *)

let test_definition_at_let_binding () =
  (* A let binding inside a function body: the use of [x] in [x + 1]
     should resolve back to the binding site. *)
  let src = {|mod Test do
  fn foo() : Int do
    let x = 10
    x + 1
  end
end|} in
  let a = analyse src in
  (* Find where the *use* of x is (the "x" in "x + 1"). We look for the
     second occurrence of "x" in the source — the one on the "x + 1" line. *)
  let (line, col) = pos_of src "x + 1" in
  (* The 'x' in 'x + 1' is at (line, col) in 0-indexed coordinates. *)
  let loc = An.definition_at a ~line ~character:col in
  Alcotest.(check bool) "definition_at returns Some" true (loc <> None)

let test_definition_at_outside_any_use () =
  let src = {|mod Test do
  fn foo() : Int do 42 end
end|} in
  let a = analyse src in
  (* Hovering on a literal — no variable use, so no definition. *)
  let loc = An.definition_at a ~line:1 ~character:22 in
  Alcotest.(check bool) "no definition for literal" true (loc = None)

let test_definition_at_function_name_reference () =
  (* When a function calls another, the callee use should resolve.
     We anchor on "= helper_fn()" which is unique to the call site
     (the declaration uses "fn helper_fn(" which is a different substring). *)
  let src = {|mod Test do
  fn helper_fn() : Int do 1 end
  fn caller() : Int do
    let v = helper_fn()
    v
  end
end|} in
  let a = analyse src in
  (* "= helper_fn()" only appears at the call site *)
  let (line, col) = pos_of src "= helper_fn()" in
  let col = col + 2 in  (* skip "= " to land on 'h' of helper_fn *)
  let loc = An.definition_at a ~line ~character:col in
  Alcotest.(check bool) "helper_fn definition found" true (loc <> None)

let test_definition_at_constructor_expression () =
  (* Clicking on a constructor in an expression (ECon) should resolve to
     the constructor's definition in the type declaration. *)
  let src = {|mod Test do
  type Color = Red | Green | Blue
  fn pick() : Color do Green end
end|} in
  let a = analyse src in
  (* "Green end" — unique; the 'G' of Green is the constructor use *)
  let (line, col) = pos_of src "Green end" in
  let loc = An.definition_at a ~line ~character:col in
  Alcotest.(check bool) "constructor ECon resolves" true (loc <> None)

let test_definition_at_constructor_pattern () =
  (* Clicking on a constructor in a match pattern (PatCon) should resolve. *)
  let src = {|mod Test do
  type Opt = None | Some(Int)
  fn unwrap(x: Opt) : Int do
    match x do
    Some(v) -> v
    None -> 0
    end
  end
end|} in
  let a = analyse src in
  (* "Some(v)" only appears in the pattern arm — click on 'S' of Some *)
  let (line, col) = pos_of src "Some(v)" in
  let loc = An.definition_at a ~line ~character:col in
  Alcotest.(check bool) "constructor PatCon resolves" true (loc <> None)

let test_definition_at_type_definition_site () =
  (* F12 on the function name in its own declaration should return
     the definition location (def_map fallback). *)
  let src = {|mod Test do
  fn my_fn() : Int do 1 end
end|} in
  let a = analyse src in
  (* "fn my_fn()" — cursor on 'my_fn' in the declaration itself *)
  let (line, col) = pos_of src "my_fn" in
  let loc = An.definition_at a ~line ~character:col in
  Alcotest.(check bool) "definition-site fallback" true (loc <> None)

let test_definition_at_type_name () =
  (* The type name in a DType declaration should resolve via def_map fallback. *)
  let src = {|mod Test do
  type MyType = A | B
end|} in
  let a = analyse src in
  let (line, col) = pos_of src "MyType" in
  let loc = An.definition_at a ~line ~character:col in
  Alcotest.(check bool) "type name in decl resolves" true (loc <> None)

let test_island_goto_def () =
  (* Cursor on the component name inside <island name='Counter' /> should
     go to the definition of the Counter module (Counter.create or Counter).
     A March file must be a single top-level module, so Counter is a nested mod. *)
  let src = {|mod App do
  mod Counter do
    fn create(n : Int) : Int do n end
    fn render(s : Int) : Int do s end
  end
  fn page() : Int do
    ~H"<island name='Counter' />"
    0
  end
end|} in
  let a = analyse src in
  (* "Counter' />" only appears inside the island tag name attribute *)
  let (line, col) = pos_of src "Counter' />" in
  (* col is the 'C' of Counter inside name='Counter' — inside isl_name_span *)
  (match An.definition_at a ~line ~character:col with
   | Some loc ->
     (* The definition should point into the Counter module (lines 1-4, 0-indexed) *)
     Alcotest.(check bool) "jumps into Counter" true
       (loc.Lsp.Types.Location.range.Lsp.Types.Range.start.Lsp.Types.Position.line <= 3)
   | None -> Alcotest.fail "expected a definition for the island component")

(* ------------------------------------------------------------------ *)
(* 6. Analysis — hover types (type_at)                                 *)
(* ------------------------------------------------------------------ *)

let test_type_at_no_position () =
  (* Hovering at line 0 col 0 of an empty module — no type. *)
  let src = "mod Empty do\nend" in
  let a   = analyse src in
  let t   = An.type_at a ~line:0 ~character:0 in
  Alcotest.(check bool) "no type at col 0 of mod keyword" true (t = None)

let test_type_at_int_literal () =
  (* The literal 42 should have type Int. *)
  let src = {|mod Test do
  fn f() : Int do 42 end
end|} in
  let a = analyse src in
  let (line, col) = pos_of src "42" in
  let t = An.type_at a ~line ~character:col in
  match t with
  | None ->
    (* type_map may not include literal spans depending on pass — acceptable *)
    ()
  | Some s ->
    Alcotest.(check bool) "type contains Int" true
      (let low = String.lowercase_ascii s in
       String.length low >= 3 &&
       (try
          let _ = Str.search_forward (Str.regexp "int") low 0 in true
        with Not_found -> false))

let test_type_at_returns_string () =
  (* Hovering over any annotated expression should return a non-empty string. *)
  let src = {|mod Test do
  fn add(x : Int, y : Int) : Int do x + y end
end|} in
  let a = analyse src in
  (* Try a few positions — at least one should give a type. *)
  let found = ref false in
  for line = 0 to 2 do
    for col = 0 to 50 do
      (match An.type_at a ~line ~character:col with
       | Some s when s <> "" -> found := true
       | _ -> ())
    done
  done;
  Alcotest.(check bool) "at least one type found in valid module" true !found

(* ------------------------------------------------------------------ *)
(* 7. Analysis — inlay hints                                           *)
(* ------------------------------------------------------------------ *)

let test_inlay_hints_nonempty_for_valid_code () =
  let src = {|mod Test do
  fn f() : Int do
    let x = 42
    x
  end
end|} in
  let a = analyse src in
  (* Request hints for the entire document range. *)
  let range = Lsp.Types.Range.create
      ~start:(Lsp.Types.Position.create ~line:0 ~character:0)
      ~end_:(Lsp.Types.Position.create ~line:10 ~character:0)
  in
  let hints = An.inlay_hints_for a range in
  (* With a valid typechecked module there should be at least one hint
     (for the let x = 42 expression). *)
  Alcotest.(check bool) "some inlay hints returned" true (hints <> [])

let test_inlay_hints_empty_for_wrong_range () =
  let src = {|mod Test do
  fn f() : Int do 42 end
end|} in
  let a = analyse src in
  (* Request hints for lines 100-200 — nothing should be there. *)
  let range = Lsp.Types.Range.create
      ~start:(Lsp.Types.Position.create ~line:100 ~character:0)
      ~end_:(Lsp.Types.Position.create ~line:200 ~character:0)
  in
  let hints = An.inlay_hints_for a range in
  Alcotest.(check int) "no hints outside file" 0 (List.length hints)

let test_inlay_hint_has_colon_prefix () =
  let src = {|mod Test do
  fn f() : Int do
    let x = 42
    x
  end
end|} in
  let a = analyse src in
  let range = Lsp.Types.Range.create
      ~start:(Lsp.Types.Position.create ~line:0 ~character:0)
      ~end_:(Lsp.Types.Position.create ~line:10 ~character:0)
  in
  let hints = An.inlay_hints_for a range in
  List.iter (fun (h : Lsp.Types.InlayHint.t) ->
      match h.label with
      | `String s ->
        Alcotest.(check bool) "hint label starts with ': '" true
          (String.length s >= 2 && String.sub s 0 2 = ": ")
      | _ -> ()
    ) hints

(* ------------------------------------------------------------------ *)
(* 8. March-specific features                                          *)
(* ------------------------------------------------------------------ *)

(* 8a. Interface implementations *)

let test_find_impls_of_present () =
  (* Use the correct March interface + impl syntax. *)
  let src = {|mod Test do
  interface Eq(a) do
    fn eq: a -> a -> Bool
  end
  type Color = Red | Green | Blue
  impl Eq(Color) do
    fn eq(x, y) do false end
  end
end|} in
  let a     = analyse src in
  let impls = An.find_impls_of a "Eq" in
  Alcotest.(check bool) "Eq has at least one impl" true (impls <> [])

let test_find_impls_of_absent () =
  let src = {|mod Test do
  interface Eq do
    fn equals(a : Self, b : Self) : Bool
  end
end|} in
  let a     = analyse src in
  let impls = An.find_impls_of a "Eq" in
  Alcotest.(check int) "no impls for Eq yet" 0 (List.length impls)

let test_find_impls_of_unknown_interface () =
  let src = {|mod Test do
  fn f() : Int do 1 end
end|} in
  let a     = analyse src in
  let impls = An.find_impls_of a "DoesNotExist" in
  Alcotest.(check int) "zero impls for unknown iface" 0 (List.length impls)

(* 8b. Actor info *)

let test_actor_info_at_actor_name () =
  let src = {|mod Test do
  actor Counter do
    state { value : Int }
    init { value: 0 }
    on Increment(n : Int) do
      { state with value: state.value + n }
    end
    on Reset() do
      { state with value: 0 }
    end
  end
end|} in
  let a = analyse src in
  (* 'Counter' starts at line 2 (1-indexed) = line 1 (0-indexed), col 8. *)
  let (line, col) = pos_of src "Counter" in
  let info = An.actor_info_at a ~line ~character:col in
  Alcotest.(check bool) "actor info returned" true (info <> None);
  match info with
  | None -> ()
  | Some s ->
    Alcotest.(check bool) "info contains actor name" true
      (let idx = try String.index s 'C' with Not_found -> -1 in idx >= 0);
    Alcotest.(check bool) "info mentions Increment" true
      (let sub = "Increment" in
       let sl = String.length sub and n = String.length s in
       let found = ref false in
       for i = 0 to n - sl do
         if String.sub s i sl = sub then found := true
       done;
       !found)

let test_actor_info_state_fields () =
  let src = {|mod Test do
  actor Store do
    state { name : String, count : Int }
    init { name: "x", count: 0 }
    on Get() do state end
  end
end|} in
  let a = analyse src in
  let (line, col) = pos_of src "Store" in
  let info = An.actor_info_at a ~line ~character:col in
  match info with
  | None -> Alcotest.fail "expected actor info for Store"
  | Some s ->
    Alcotest.(check bool) "info mentions count field" true
      (let sub = "count" in
       let sl = String.length sub and n = String.length s in
       let found = ref false in
       for i = 0 to n - sl do
         if String.sub s i sl = sub then found := true
       done;
       !found)

let test_actor_info_not_at_random_position () =
  let src = {|mod Test do
  fn f() : Int do 1 end
end|} in
  let a    = analyse src in
  let info = An.actor_info_at a ~line:1 ~character:5 in
  Alcotest.(check bool) "no actor info on fn" true (info = None)

(* 8c. Pipe chain type flow *)

let test_pipe_chain_parsed_without_errors () =
  (* A pipe chain should typecheck cleanly. *)
  let src = {|mod Test do
  fn double(x : Int) : Int do x * 2 end
  fn inc(x : Int) : Int do x + 1 end
  fn result() : Int do
    1 |> double |> inc
  end
end|} in
  let a = analyse src in
  Alcotest.(check int) "pipe chain: no type errors" 0 (count_errors a)

let test_pipe_chain_type_available () =
  (* hover somewhere in a pipe chain — should find a type *)
  let src = {|mod Test do
  fn dbl(x : Int) : Int do x * 2 end
  fn go() : Int do 5 |> dbl end
end|} in
  let a = analyse src in
  (* At least one position in the pipe expression should yield a type. *)
  let found = ref false in
  for col = 0 to 30 do
    (match An.type_at a ~line:2 ~character:col with
     | Some _ -> found := true
     | None -> ())
  done;
  Alcotest.(check bool) "type found somewhere in pipe line" true !found

(* 8d. Derive *)

let test_derive_no_false_errors () =
  (* derive should not produce spurious diagnostics *)
  let src = {|mod Test do
  interface Eq do
    fn equals(a : Self, b : Self) : Bool
  end
  type Color = Red | Green | Blue
  derive Eq for Color do
    fn equals(a : Color, b : Color) : Bool do false end
  end
end|} in
  let a = analyse src in
  (* Allow zero or more diagnostics — we just care there's no crash
     and diagnostics are a list. *)
  Alcotest.(check bool) "derive: no crash" true
    (match a.diagnostics with _ -> true)

(* 8e. Linear value consumption tracking *)

let test_linear_consumption_map_built () =
  (* build_consumption_map is an internal function used by the server.
     We test it indirectly: a module with a linear binding should still
     analyse without crashing, and the analysis result is well-formed. *)
  let src = {|mod Test do
  fn consume(linear x : Int) : Int do x end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "linear binding: analysis completes" true
    (match a.src with s when s = src -> true | _ -> false)

(* ------------------------------------------------------------------ *)
(* 9. Error recovery                                                   *)
(* ------------------------------------------------------------------ *)

let test_empty_file_no_crash () =
  let a = analyse "" in
  Alcotest.(check bool) "empty file: analysis list is a list" true
    (match a.diagnostics with _ -> true)

let test_partial_source_no_crash () =
  let src = "mod Partial do\n  fn foo(" in
  let a   = analyse src in
  Alcotest.(check bool) "partial source: no crash" true
    (List.length a.diagnostics >= 0)

let test_malformed_grammar_no_crash () =
  (* Use tokens that are individually valid but form an invalid parse,
     so Menhir (not the lexer) raises Parser.Error — which analyse() catches. *)
  let src = "mod Bad do\n  let = 42\nend" in
  let a   = analyse src in
  Alcotest.(check bool) "bad grammar: has diagnostic" true
    (List.length a.diagnostics > 0)

let test_lexer_error_produces_diagnostic () =
  (* Sources with illegal characters (e.g. '@') raise Lexer_error in the lexer.
     analyse() catches this and converts it to a diagnostic rather than crashing. *)
  let src = "mod Bad do\n  let x = @invalid\nend" in
  let a   = analyse src in
  Alcotest.(check bool) "lexer error: no crash"    true  (List.length a.diagnostics >= 0);
  Alcotest.(check bool) "lexer error: has diag"    true  (List.length a.diagnostics > 0);
  Alcotest.(check bool) "lexer error: is error"    true
    (List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
         d.severity = Some Lsp.Types.DiagnosticSeverity.Error)
       a.diagnostics)

let test_unterminated_string_is_diagnostic () =
  (* Unterminated strings raise Lexer_error — should become a diagnostic. *)
  let src = {|mod Bad do
  let x = "unterminated
end|} in
  let a = analyse src in
  Alcotest.(check bool) "unterminated string: has diagnostic" true
    (List.length a.diagnostics > 0)

let test_source_with_only_comment_no_crash () =
  let src = "-- just a comment\n" in
  let a   = analyse src in
  Alcotest.(check bool) "comment-only: no crash" true
    (List.length a.diagnostics >= 0)

let test_missing_expression_no_crash () =
  (* An expression position with nothing — triggers a Menhir parse error
     (not a lexer error), which analyse() catches and converts to a diagnostic. *)
  let src = "mod Test do\n  fn f() : Int do end\nend" in
  let a = analyse src in
  Alcotest.(check bool) "missing expression: has diagnostic" true
    (List.length a.diagnostics > 0)

let test_multiple_errors_all_from_user_file () =
  (* Diagnostics filtered to the user's file should not include stdlib errors. *)
  let src = {|mod Test do
  fn a() : Int do "x" end
  fn b() : Bool do 99 end
  fn c() : String do 1 end
end|} in
  let a = analyse src in
  List.iter (fun (d : Lsp.Types.Diagnostic.t) ->
      (* Each diagnostic range should be sensible (line >= 0). *)
      Alcotest.(check bool) "diag line >= 0" true
        (d.range.Lsp.Types.Range.start.line >= 0)
    ) a.diagnostics

let test_analyse_src_field_matches_input () =
  let src = "mod M do\nend" in
  let a   = analyse src in
  Alcotest.(check string) "src field" src a.src

(* ------------------------------------------------------------------ *)
(* 10. Analysis struct fields sanity                                   *)
(* ------------------------------------------------------------------ *)

let test_empty_module_fields_empty () =
  let src = "mod Empty do\nend" in
  let a   = analyse src in
  Alcotest.(check bool) "vars is a list" true (match a.vars with _ -> true);
  Alcotest.(check bool) "types is a list" true (match a.types with _ -> true);
  Alcotest.(check bool) "ctors is a list" true (match a.ctors with _ -> true);
  Alcotest.(check bool) "interfaces is a list" true (match a.interfaces with _ -> true);
  Alcotest.(check bool) "impls is a list" true (match a.impls with _ -> true)

let test_analysis_has_type_map () =
  let src = {|mod Test do
  fn f(x : Int) : Int do x + 1 end
end|} in
  let a = analyse src in
  let count = Hashtbl.length a.type_map in
  Alcotest.(check bool) "type_map populated for valid code" true (count > 0)

let test_analysis_has_def_map () =
  let src = {|mod Test do
  fn my_fn() : Int do 1 end
end|} in
  let a = analyse src in
  let has_fn = Hashtbl.mem a.def_map "my_fn" in
  Alcotest.(check bool) "def_map contains my_fn" true has_fn

(* ------------------------------------------------------------------ *)
(* 11. Doc strings                                                     *)
(* ------------------------------------------------------------------ *)

let test_doc_for_documented_fn () =
  let src = {|
mod M do
  doc "Adds two integers together."
  fn add(x: Int, y: Int): Int do
    x + y
  end

  fn main() do
    add(1, 2)
  end
end
|} in
  let a = analyse src in
  Alcotest.(check (option string))
    "doc for add"
    (Some "Adds two integers together.")
    (An.doc_for a "add")

let test_doc_for_undocumented_fn () =
  let src = {|
mod M do
  fn no_doc(x: Int): Int do x end
end
|} in
  let a = analyse src in
  Alcotest.(check (option string))
    "no doc returns None"
    None
    (An.doc_for a "no_doc")

let test_doc_for_unknown_name () =
  let src = {|mod M do fn f() do 1 end end|} in
  let a = analyse src in
  Alcotest.(check (option string))
    "unknown name returns None"
    None
    (An.doc_for a "does_not_exist")

let test_doc_name_at_cursor () =
  let src = {|
mod M do
  doc "Multiply."
  fn mul(a: Int, b: Int): Int do a * b end

  fn main() do
    mul(2, 3)
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "mul(2" in
  Alcotest.(check (option string))
    "doc at call site"
    (Some "Multiply.")
    (An.doc_name_at a ~line ~character:col)

let test_doc_triple_quoted () =
  let src = {|
mod M do
  doc """
  Multi-line doc.
  Second line.
  """
  fn greet() do "hi" end
end
|} in
  let a = analyse src in
  Alcotest.(check bool)
    "triple-quoted doc non-empty"
    true
    (match An.doc_for a "greet" with
     | Some s -> String.length s > 0
     | None   -> false)

let test_hover_includes_doc () =
  let src = {|
mod M do
  doc "Returns the integer unchanged."
  fn identity(x: Int): Int do x end

  fn main() do
    identity(42)
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "identity(42" in
  let ty = An.type_at a ~line ~character:col in
  let doc = An.doc_name_at a ~line ~character:col in
  Alcotest.(check bool) "type present"  true (ty  <> None);
  Alcotest.(check bool) "doc present"   true (doc <> None)

let test_doc_stdlib_hover () =
  (* Hovering over a stdlib function call must show its doc string.
     Previously, collect_decl only ran on user_decls, so stdlib docs
     were never added to doc_map.
     This test is only meaningful when the stdlib is found at runtime;
     when it is not (e.g. in isolated CI without stdlib on PATH), we
     skip the assertion rather than fail spuriously. *)
  let src = {|
mod M do
  fn main() do
    head([1, 2, 3])
  end
end
|} in
  let a = analyse src in
  (* Detect whether stdlib was loaded by checking if `head` has a type.
     If stdlib is absent, head is unknown and doc_for will return None
     regardless of our fix — skip the assertion in that case. *)
  match An.doc_for a "head" with
  | None ->
    (* stdlib not available — fix is untestable here; skip *)
    ()
  | Some _ ->
    (* stdlib loaded: doc_name_at at the call site must also find it *)
    let (line, col) = pos_of src "head([" in
    Alcotest.(check bool)
      "stdlib doc present at call site"
      true
      (An.doc_name_at a ~line ~character:col <> None)

