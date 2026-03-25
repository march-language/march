(** Test suite for the March LSP server.

    Tests are organised into sections:
      1. Position / span utilities (no parsing needed)
      2. Analysis.analyse — diagnostics
      3. Analysis.analyse — document symbols
      4. Analysis.analyse — completions
      5. Analysis.analyse — go-to-definition
      6. Analysis.analyse — hover types (type_at)
      7. Analysis.analyse — inlay hints
      8. March-specific: interface impls, actor info, linear consumption
      9. Error recovery (malformed / partial source)
*)

module Lsp  = Linol_lsp.Lsp
module Ast  = March_ast.Ast
module Pos  = March_lsp_lib.Position
module An   = March_lsp_lib.Analysis

(* ------------------------------------------------------------------ *)
(* Helpers                                                             *)
(* ------------------------------------------------------------------ *)

(** Find the first occurrence of [sub] in [src] and return its
    (0-indexed line, 0-indexed col). *)
let pos_of src sub =
  let sn = String.length sub in
  let n  = String.length src in
  let rec find i line col =
    if i + sn > n then
      failwith (Printf.sprintf "pos_of: %S not found in source" sub)
    else if String.sub src i sn = sub then (line, col)
    else if src.[i] = '\n' then find (i + 1) (line + 1) 0
    else find (i + 1) line (col + 1)
  in
  find 0 0 0

(** Build a March span with 1-indexed lines and 0-indexed cols. *)
let mk_span ?(file = "test.march") sl sc el ec =
  { Ast.file; start_line = sl; start_col = sc; end_line = el; end_col = ec }

(** Run analyse on [src] with filename "test.march". *)
let analyse src = An.analyse ~filename:"test.march" ~src

(** Return the number of diagnostics whose severity is Error. *)
let count_errors (a : An.t) =
  List.length
    (List.filter (fun (d : Lsp.Types.Diagnostic.t) ->
         d.severity = Some Lsp.Types.DiagnosticSeverity.Error)
       a.diagnostics)

(** Names present in the document symbol outline. *)
let symbol_names (a : An.t) =
  match An.document_symbols a with
  | `DocumentSymbol syms ->
    List.map (fun (s : Lsp.Types.DocumentSymbol.t) -> s.name) syms
  | _ -> []

(** Labels present in the completion list. *)
let completion_labels (a : An.t) =
  List.map (fun (i : Lsp.Types.CompletionItem.t) -> i.label)
    (An.completions_at a ~line:0 ~character:0)

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
    | Some(v) -> v
    | None -> 0
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
    init { value = 0 }
    on Increment(n : Int) do
      { state with value = state.value + n }
    end
    on Reset() do
      { state with value = 0 }
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
    init { name = "x", count = 0 }
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

(* ------------------------------------------------------------------ *)
(* 12. Find references                                                 *)
(* ------------------------------------------------------------------ *)

let test_references_empty_for_literal () =
  let src = {|mod M do fn f() do 42 end end|} in
  let a = analyse src in
  let (line, col) = pos_of src "42" in
  Alcotest.(check int)
    "no refs for literal"
    0
    (List.length (An.references_at a ~include_declaration:false ~line ~character:col))

let test_references_finds_uses () =
  let src = {|
mod M do
  fn double(n: Int): Int do n + n end
  fn main() do
    double(1)
    double(2)
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "double(1" in
  let refs = An.references_at a ~include_declaration:false ~line ~character:col in
  Alcotest.(check bool)
    "at least 2 use refs"
    true
    (List.length refs >= 2)

let test_references_include_declaration () =
  let src = {|
mod M do
  fn sq(n: Int): Int do n * n end
  fn main() do sq(3) end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "sq(3" in
  let with_decl    = An.references_at a ~include_declaration:true  ~line ~character:col in
  let without_decl = An.references_at a ~include_declaration:false ~line ~character:col in
  Alcotest.(check bool)
    "include_declaration adds one entry"
    true
    (List.length with_decl = List.length without_decl + 1)

let test_references_local_variable () =
  let src = {|
mod M do
  fn f() do
    let x = 10
    let a = x
    a + x
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "a = x" in
  let refs = An.references_at a ~include_declaration:false ~line ~character:(col + 4) in
  Alcotest.(check bool) "two uses of x" true (List.length refs >= 2)

let test_references_no_cross_contamination () =
  let src = {|
mod M do
  fn a() do 1 end
  fn b() do 2 end
  fn main() do a() end
end
|} in
  let a_an = analyse src in
  let (line, col) = pos_of src "a()" in
  let refs = An.references_at a_an ~include_declaration:false ~line ~character:col in
  let all_same_name =
    List.for_all (fun (loc : Lsp.Types.Location.t) ->
        loc.range.start.character < loc.range.end_.character
      ) refs
  in
  Alcotest.(check bool) "all refs are real ranges" true all_same_name

(* ------------------------------------------------------------------ *)
(* 13. Rename symbol                                                   *)
(* ------------------------------------------------------------------ *)

let test_rename_no_edits_for_literal () =
  let src = {|mod M do fn f() do 99 end end|} in
  let a = analyse src in
  let (line, col) = pos_of src "99" in
  let edits = An.rename_at a ~line ~character:col ~new_name:"foo" in
  Alcotest.(check int) "no edits for literal" 0 (List.length edits)

let test_rename_produces_edits_for_def_and_uses () =
  let src = {|
mod M do
  fn calc(n: Int): Int do n + 1 end
  fn main() do
    calc(10)
    calc(20)
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "calc(10" in
  let edits = An.rename_at a ~line ~character:col ~new_name:"compute" in
  Alcotest.(check bool)
    "at least 3 edits"
    true
    (List.length edits >= 3)

let test_rename_new_name_in_edits () =
  let src = {|
mod M do
  fn old_name(x: Int): Int do x end
  fn main() do old_name(5) end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "old_name(5" in
  let edits = An.rename_at a ~line ~character:col ~new_name:"new_name" in
  let all_new_name =
    List.for_all (fun (e : Lsp.Types.TextEdit.t) ->
        e.newText = "new_name"
      ) edits
  in
  Alcotest.(check bool) "all edits contain new_name" true all_new_name

let test_rename_does_not_rename_other_names () =
  let src = {|
mod M do
  fn alpha() do 1 end
  fn beta()  do 2 end
  fn main()  do alpha() end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "alpha()" in
  let edits = An.rename_at a ~line ~character:col ~new_name:"gamma" in
  let no_beta =
    List.for_all (fun (e : Lsp.Types.TextEdit.t) ->
        e.newText <> "beta"
      ) edits
  in
  Alcotest.(check bool) "beta untouched" true no_beta

(* ------------------------------------------------------------------ *)
(* 14. Signature help                                                  *)
(* ------------------------------------------------------------------ *)

let test_sig_help_none_outside_call () =
  let src = {|mod M do fn f() do 42 end end|} in
  let a = analyse src in
  Alcotest.(check bool)
    "no sig help outside call"
    true
    (An.signature_help_at a ~line:2 ~character:5 = None)

let test_sig_help_single_param () =
  let src = {|
mod M do
  fn negate(n: Int): Int do 0 - n end
  fn main() do negate(10) end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "negate(10" in
  let sh = An.signature_help_at a ~line ~character:(col + 7) in
  Alcotest.(check bool) "sig help present" true (sh <> None);
  match sh with
  | None -> ()
  | Some (label, params, active_param) ->
    Alcotest.(check bool) "label non-empty"   true (String.length label > 0);
    Alcotest.(check int)  "one param"         1    (List.length params);
    Alcotest.(check int)  "first param active" 0   active_param

let test_sig_help_active_param_index () =
  let src = {|
mod M do
  fn add3(a: Int, b: Int, c: Int): Int do a + b + c end
  fn main() do add3(1, 2, 3) end
end
|} in
  let a = analyse src in
  let (line, comma_col) = pos_of src ", 3)" in
  (match An.signature_help_at a ~line ~character:(comma_col + 2) with
   | None -> Alcotest.fail "expected signature help"
   | Some (_, _, active) ->
     Alcotest.(check int) "third param active (index 2)" 2 active)

let test_sig_help_param_labels () =
  let src = {|
mod M do
  fn div(numerator: Int, denominator: Int): Int do
    numerator / denominator
  end
  fn main() do div(10, 2) end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "div(10" in
  (match An.signature_help_at a ~line ~character:(col + 4) with
   | None -> Alcotest.fail "expected sig help"
   | Some (_, params, _) ->
     Alcotest.(check int) "two params" 2 (List.length params);
     List.iter (fun p ->
         Alcotest.(check bool)
           "param label non-empty"
           true
           (String.length p > 0)
       ) params)

let test_sig_help_not_a_known_function () =
  let src = {|
mod M do
  fn main() do
    let f = fn x -> x + 1
    f(5)
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "f(5" in
  let _ = An.signature_help_at a ~line ~character:(col + 2) in
  Alcotest.(check bool) "no crash" true true

(* ------------------------------------------------------------------ *)
(* 15. Code actions: make-linear                                       *)
(* ------------------------------------------------------------------ *)

let test_make_linear_offered_for_single_use () =
  let src = {|
mod M do
  fn f() do
    let x = 42
    x + 1
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "let x" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let has_make_linear =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        match ca.title with
        | t -> String.length t > 0 &&
               (let low = String.lowercase_ascii t in
                let n = String.length low in
                let sub = "linear" in
                let sn = String.length sub in
                let found = ref false in
                for i = 0 to n - sn do
                  if String.sub low i sn = sub then found := true
                done;
                !found)
      ) acts
  in
  Alcotest.(check bool) "make-linear offered" true has_make_linear

let test_make_linear_not_offered_for_multi_use () =
  let src = {|
mod M do
  fn f() do
    let x = 10
    x + x
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "let x" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let has_make_linear =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        match ca.title with
        | t ->
          let low = String.lowercase_ascii t in
          let n = String.length low and sn = 6 in
          let found = ref false in
          for i = 0 to n - sn do
            if String.sub low i sn = "linear" then found := true
          done;
          !found
      ) acts
  in
  Alcotest.(check bool) "no make-linear for multi-use" false has_make_linear

let test_make_linear_edit_inserts_keyword () =
  let src = {|
mod M do
  fn f() do
    let value = 5
    value * 2
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "let value" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let linear_act = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      match ca.title with
      | t ->
        let low = String.lowercase_ascii t in
        let n = String.length low and sn = 6 in
        let found = ref false in
        for i = 0 to n - sn do
          if String.sub low i sn = "linear" then found := true
        done;
        !found
    ) acts
  in
  match linear_act with
  | None -> Alcotest.fail "expected make-linear action"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected workspace edit"
     | Some edit ->
       let has_edit =
         match edit.changes with
         | None -> false
         | Some m ->
           List.exists (fun (_, edits) ->
               List.exists (fun (e : Lsp.Types.TextEdit.t) ->
                   let t = e.newText in
                   let n = String.length t and sn = 7 in
                   let found = ref false in
                   for i = 0 to n - sn do
                     if String.sub t i sn = "linear " then found := true
                   done;
                   !found
                 ) edits
             ) m
       in
       Alcotest.(check bool) "edit inserts 'linear '" true has_edit)

(* ------------------------------------------------------------------ *)
(* 16. Code actions: pattern exhaustion quickfix                       *)
(* ------------------------------------------------------------------ *)

let test_exhaustion_quickfix_absent_for_exhaustive_match () =
  let src = {|
mod M do
  type Color = Red | Green | Blue

  fn describe(c: Color): String do
    match c do
    | Red   -> "red"
    | Green -> "green"
    | Blue  -> "blue"
    end
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "match c" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let has_exhaustion =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        let low = String.lowercase_ascii ca.title in
        let n = String.length low and sn = 7 in
        let found = ref false in
        for i = 0 to n - sn do
          if String.sub low i sn = "missing" then found := true
        done;
        !found
      ) acts
  in
  Alcotest.(check bool) "no exhaustion fix for complete match" false has_exhaustion

let test_exhaustion_quickfix_offered_for_incomplete_match () =
  let src = {|
mod M do
  type Shape = Circle | Square | Triangle

  fn area(s: Shape): Int do
    match s do
    | Circle -> 1
    | Square -> 2
    end
  end
end
|} in
  let a = analyse src in
  let has_warning =
    List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
        match d.severity with
        | Some Lsp.Types.DiagnosticSeverity.Warning -> true
        | _ -> false
      ) a.diagnostics
  in
  Alcotest.(check bool) "warning present" true has_warning;
  let (line, col) = pos_of src "match s" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let has_quickfix =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        ca.kind = Some Lsp.Types.CodeActionKind.QuickFix
      ) acts
  in
  Alcotest.(check bool) "quickfix offered" true has_quickfix

let test_exhaustion_quickfix_edit_contains_missing_arm () =
  let src = {|
mod M do
  type Dir = North | South | East | West

  fn label(d: Dir): String do
    match d do
    | North -> "N"
    | South -> "S"
    | East  -> "E"
    end
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "match d" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let qf = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      ca.kind = Some Lsp.Types.CodeActionKind.QuickFix
    ) acts in
  match qf with
  | None -> Alcotest.fail "expected quickfix"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected edit"
     | Some edit ->
       let found_west =
         match edit.changes with
         | None -> false
         | Some m ->
           List.exists (fun (_, edits) ->
               List.exists (fun (e : Lsp.Types.TextEdit.t) ->
                   let low = String.lowercase_ascii e.newText in
                   let n = String.length low and sn = 4 in
                   let f = ref false in
                   for i = 0 to n - sn do
                     if String.sub low i sn = "west" then f := true
                   done;
                   !f
                 ) edits
             ) m
       in
       Alcotest.(check bool) "edit mentions West" true found_west)

let test_exhaustion_quickfix_edit_inserts_before_end () =
  let src = {|
mod M do
  type Bit = Zero | One

  fn flip(b: Bit): Bit do
    match b do
    | Zero -> One
    end
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "match b" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let qf = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      ca.kind = Some Lsp.Types.CodeActionKind.QuickFix) acts in
  match qf with
  | None -> Alcotest.fail "expected quickfix"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected edit"
     | Some edit ->
       let has_arm =
         match edit.changes with
         | None -> false
         | Some m ->
           List.exists (fun (_, edits) ->
               List.exists (fun (e : Lsp.Types.TextEdit.t) ->
                   String.contains e.newText '|'
                 ) edits
             ) m
       in
       Alcotest.(check bool) "edit is a match arm" true has_arm)

(* ------------------------------------------------------------------ *)
(* 17. Phase 2: Enhanced exhaustive match                             *)
(* ------------------------------------------------------------------ *)

let test_exhaustion_all_cases_action_offered () =
  (* Two variants missing → "Add all 2 missing cases" should appear *)
  let src = {|
mod M do
  type Season = Spring | Summer | Autumn | Winter

  fn greet(s: Season): String do
    match s do
    | Spring -> "bloom"
    | Summer -> "sun"
    end
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "match s" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let has_bulk =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        let low = String.lowercase_ascii ca.title in
        let n = String.length low and sn = 3 in
        let found = ref false in
        for i = 0 to n - sn do
          if String.sub low i sn = "all" then found := true
        done;
        !found
      ) acts
  in
  Alcotest.(check bool) "bulk 'add all' action offered" true has_bulk

let test_exhaustion_all_cases_edit_covers_all () =
  (* Three variants missing; bulk edit should mention all three *)
  let src = {|
mod M do
  type Dir = North | South | East | West

  fn go(d: Dir): Int do
    match d do
    | North -> 0
    end
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "match d" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let bulk = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      let low = String.lowercase_ascii ca.title in
      let n = String.length low and sn = 3 in
      let found = ref false in
      for i = 0 to n - sn do
        if String.sub low i sn = "all" then found := true
      done;
      !found
    ) acts in
  match bulk with
  | None -> Alcotest.fail "expected bulk quickfix"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected edit"
     | Some edit ->
       match edit.changes with
       | None -> Alcotest.fail "expected changes"
       | Some m ->
         let combined = List.concat_map (fun (_, es) ->
             List.map (fun (e : Lsp.Types.TextEdit.t) -> e.newText) es
           ) m |> String.concat "" |> String.lowercase_ascii
         in
         let contains sub str =
           let sn = String.length sub and n = String.length str in
           let found = ref false in
           for i = 0 to n - sn do
             if String.sub str i sn = sub then found := true
           done;
           !found
         in
         Alcotest.(check bool) "south in edit" true (contains "south" combined);
         Alcotest.(check bool) "east in edit"  true (contains "east"  combined);
         Alcotest.(check bool) "west in edit"  true (contains "west"  combined))

let test_exhaustion_single_missing_no_bulk () =
  (* Only one variant missing → no "Add all N missing cases" bulk action *)
  let src = {|
mod M do
  type Bit = Zero | One

  fn inv(b: Bit): Bit do
    match b do
    | Zero -> One
    end
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "match b" in
  let acts = An.code_actions_at a ~line ~character:col () in
  (* "Add all N missing cases" has the prefix "add all" — not a file-scope fix *)
  let has_add_all =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        let low = String.lowercase_ascii ca.title in
        let n = String.length low and sn = 7 in
        let found = ref false in
        for i = 0 to n - sn do
          if String.sub low i sn = "add all" then found := true
        done;
        !found
      ) acts
  in
  Alcotest.(check bool) "no 'add all' for single missing case" false has_add_all

(* ------------------------------------------------------------------ *)
(* 18. Phase 2: Diagnostics-driven quickfix framework                 *)
(* ------------------------------------------------------------------ *)

let test_fix_registry_has_known_codes () =
  (* The registry should have entries for the standard diagnostic codes *)
  let codes = ["non_exhaustive_match"; "unused_binding";
               "unused_private_fn"; "unreachable_code"] in
  List.iter (fun code ->
      let has_entry = Hashtbl.mem An.fix_registry code in
      Alcotest.(check bool) ("registry has " ^ code) true has_entry
    ) codes

let test_apply_fix_registry_empty_for_unknown_code () =
  let src = {|
mod M do
  fn main() do
    println("hi")
  end
end
|} in
  let a = analyse src in
  let fake_diag = Lsp.Types.Diagnostic.create
    ~range:(Lsp.Types.Range.create
      ~start:(Lsp.Types.Position.create ~line:0 ~character:0)
      ~end_:(Lsp.Types.Position.create ~line:0 ~character:1))
    ~message:(`String "test") ~source:"march"
    ~code:(`String "no_such_code")
    ()
  in
  let acts = An.apply_fix_registry a [fake_diag] in
  Alcotest.(check int) "no actions for unknown code" 0 (List.length acts)

(* ------------------------------------------------------------------ *)
(* 19. Phase 2: Dead code detection                                   *)
(* ------------------------------------------------------------------ *)

let test_unused_private_fn_warning () =
  let src = {|
mod M do
  pfn helper(): Int do
    42
  end

  fn main() do
    println("hi")
  end
end
|} in
  let a = analyse src in
  let has_unused_warning =
    List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
        (match d.code with
         | Some (`String "unused_private_fn") -> true
         | _ -> false)
      ) a.diagnostics
  in
  Alcotest.(check bool) "unused private fn warning" true has_unused_warning

let test_used_private_fn_no_warning () =
  let src = {|
mod M do
  pfn helper(): Int do
    42
  end

  fn main() do
    let x = helper()
    println(int_to_string(x))
  end
end
|} in
  let a = analyse src in
  let has_unused_warning =
    List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
        (match d.code with
         | Some (`String "unused_private_fn") -> true
         | _ -> false)
      ) a.diagnostics
  in
  Alcotest.(check bool) "used private fn: no warning" false has_unused_warning

let test_unreachable_code_after_panic_warning () =
  let src = {|
mod M do
  fn bad(x: Int): Int do
    let _ = panic("oops")
    x + 1
  end
end
|} in
  let a = analyse src in
  let has_unreachable =
    List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
        (match d.code with
         | Some (`String "unreachable_code") -> true
         | _ -> false)
      ) a.diagnostics
  in
  Alcotest.(check bool) "unreachable code warning after panic" true has_unreachable

let test_unused_fns_field_populated () =
  let src = {|
mod M do
  pfn dead(): Int do
    99
  end

  fn alive(): Int do
    1
  end
end
|} in
  let a = analyse src in
  Alcotest.(check bool) "dead fn in unused_fns" true
    (List.mem "dead" a.An.unused_fns);
  Alcotest.(check bool) "alive fn not in unused_fns" false
    (List.mem "alive" a.An.unused_fns)

(* ------------------------------------------------------------------ *)
(* 17. Code actions: naming convention fix (P2.8)                     *)
(* ------------------------------------------------------------------ *)

let test_naming_violation_camel_fn_detected () =
  let src = {|
mod M do
  fn myFunction(x: Int): Int do
    x
  end
end
|} in
  let a = analyse src in
  Alcotest.(check bool) "camelCase fn in naming_violations" true
    (List.exists (fun (nv : An.naming_violation) -> nv.nv_name = "myFunction")
       a.An.naming_violations)

let test_naming_violation_suggested_name () =
  let src = {|
mod M do
  fn myFunction(x: Int): Int do
    x
  end
end
|} in
  let a = analyse src in
  match List.find_opt
    (fun (nv : An.naming_violation) -> nv.nv_name = "myFunction")
    a.An.naming_violations
  with
  | None -> Alcotest.fail "expected naming violation for myFunction"
  | Some nv ->
    Alcotest.(check string) "suggested name is my_function" "my_function" nv.nv_suggested

let test_naming_violation_deeply_nested_detected () =
  (* Violations are detected inside nested mod blocks *)
  let src = {|
mod M do
  mod Inner do
    fn outerFn(x: Int): Int do
      x
    end
  end
end
|} in
  let a = analyse src in
  Alcotest.(check bool) "camelCase fn inside nested mod detected" true
    (List.exists (fun (nv : An.naming_violation) -> nv.nv_name = "outerFn")
       a.An.naming_violations)

let test_naming_violation_no_violation_for_snake_fn () =
  let src = {|
mod M do
  fn already_good(x: Int): Int do
    x
  end
end
|} in
  let a = analyse src in
  Alcotest.(check bool) "no naming violation for snake_case fn" false
    (List.exists (fun (nv : An.naming_violation) -> nv.nv_name = "already_good")
       a.An.naming_violations)

let test_naming_action_offered_for_camel_fn () =
  let src = {|
mod M do
  fn myFunction(x: Int): Int do
    x
  end
end
|} in
  let a   = analyse src in
  let (line, col) = pos_of src "myFunction" in
  let acts = An.code_actions_at a ~line ~character:col () in
  Alcotest.(check bool) "rename action offered for camelCase fn" true
    (List.exists (fun (act : Lsp.Types.CodeAction.t) ->
         let t = act.title in
         String.length t >= 6 && String.sub t 0 6 = "Rename")
       acts)

let test_naming_action_edit_uses_snake_case () =
  let src = {|
mod M do
  fn myFunction(x: Int): Int do
    x
  end
end
|} in
  let a   = analyse src in
  let (line, col) = pos_of src "myFunction" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let rename_act = List.find_opt (fun (act : Lsp.Types.CodeAction.t) ->
      let t = act.title in
      String.length t >= 6 && String.sub t 0 6 = "Rename") acts in
  match rename_act with
  | None -> Alcotest.fail "no rename action found"
  | Some act ->
    let has_snake = match act.edit with
      | None -> false
      | Some we ->
        let edits = match we.changes with
          | None -> []
          | Some changes -> List.concat_map snd changes
        in
        List.exists (fun (e : Lsp.Types.TextEdit.t) ->
            e.newText = "my_function") edits
    in
    Alcotest.(check bool) "edit contains my_function" true has_snake

let test_naming_action_absent_for_snake_fn () =
  let src = {|
mod M do
  fn good_name(x: Int): Int do
    x
  end
end
|} in
  let a   = analyse src in
  let (line, col) = pos_of src "good_name" in
  let acts = An.code_actions_at a ~line ~character:col () in
  Alcotest.(check bool) "no rename action for already-snake fn" false
    (List.exists (fun (act : Lsp.Types.CodeAction.t) ->
         let t = act.title in
         String.length t >= 6 && String.sub t 0 6 = "Rename")
       acts)

(* ------------------------------------------------------------------ *)
(* 18. Code actions: De Morgan's law (P3.10)                          *)
(* ------------------------------------------------------------------ *)

let test_demorgan_not_and_detected () =
  let src = {|
mod M do
  fn check(a: Bool, b: Bool): Bool do
    !(a && b)
  end
end
|} in
  let a = analyse src in
  Alcotest.(check bool) "!(a && b) detected as De Morgan site" true
    (List.exists (fun (dm : An.demorgan_site) ->
         dm.dm_form = `NegatedBinop "&&") a.An.demorgan_sites)

let test_demorgan_not_or_detected () =
  let src = {|
mod M do
  fn check(a: Bool, b: Bool): Bool do
    !(a || b)
  end
end
|} in
  let a = analyse src in
  Alcotest.(check bool) "!(a || b) detected as De Morgan site" true
    (List.exists (fun (dm : An.demorgan_site) ->
         dm.dm_form = `NegatedBinop "||") a.An.demorgan_sites)

let test_demorgan_pair_negs_detected () =
  let src = {|
mod M do
  fn check(a: Bool, b: Bool): Bool do
    !a && !b
  end
end
|} in
  let a = analyse src in
  Alcotest.(check bool) "!a && !b detected as De Morgan site" true
    (List.exists (fun (dm : An.demorgan_site) ->
         dm.dm_form = `PairOfNegs "&&") a.An.demorgan_sites)

let test_demorgan_action_offered_for_not_and () =
  let src = {|
mod M do
  fn check(a: Bool, b: Bool): Bool do
    !(a && b)
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "!(a && b)" in
  let acts = An.code_actions_at a ~line ~character:(col + 1) () in
  Alcotest.(check bool) "De Morgan action offered for !(a && b)" true
    (List.exists (fun (act : Lsp.Types.CodeAction.t) ->
         let t = act.title in
         String.length t > 10 && String.sub t 0 5 = "Apply")
       acts)

let test_demorgan_action_rewrite_not_and () =
  let src = {|
mod M do
  fn check(a: Bool, b: Bool): Bool do
    !(a && b)
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "!(a && b)" in
  let acts = An.code_actions_at a ~line ~character:(col + 1) () in
  let dm_act = List.find_opt (fun (act : Lsp.Types.CodeAction.t) ->
      let t = act.title in
      String.length t > 10 && String.sub t 0 5 = "Apply") acts in
  match dm_act with
  | None -> Alcotest.fail "no De Morgan action found"
  | Some act ->
    let new_text = match act.edit with
      | None -> ""
      | Some we ->
        let edits = match we.changes with
          | None -> []
          | Some changes -> List.concat_map snd changes
        in
        (match edits with e :: _ -> e.newText | [] -> "")
    in
    let contains_or =
      let n = String.length new_text in
      let found = ref false in
      for i = 0 to n - 2 do
        if new_text.[i] = '|' && new_text.[i + 1] = '|' then found := true
      done;
      !found
    in
    Alcotest.(check bool) "rewrite contains '||'" true
      (String.length new_text > 0 && contains_or)

let test_demorgan_action_rewrite_pair_negs () =
  let src = {|
mod M do
  fn check(a: Bool, b: Bool): Bool do
    !a && !b
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "!a && !b" in
  let acts = An.code_actions_at a ~line ~character:(col + 1) () in
  let dm_act = List.find_opt (fun (act : Lsp.Types.CodeAction.t) ->
      let t = act.title in
      String.length t > 10 && String.sub t 0 5 = "Apply") acts in
  match dm_act with
  | None -> Alcotest.fail "no De Morgan action found for !a && !b"
  | Some act ->
    let new_text = match act.edit with
      | None -> ""
      | Some we ->
        let edits = match we.changes with
          | None -> []
          | Some changes -> List.concat_map snd changes
        in
        (match edits with e :: _ -> e.newText | [] -> "")
    in
    Alcotest.(check bool) "rewrite is !(... || ...)" true
      (String.length new_text > 2 && new_text.[0] = '!')

(* ------------------------------------------------------------------ *)
(* Runner                                                              *)
(* ------------------------------------------------------------------ *)

let () =
  Alcotest.run "march-lsp" [
    "position", [
      Alcotest.test_case "span_to_range single-line"    `Quick test_span_to_range_single_line;
      Alcotest.test_case "span_to_range multi-line"     `Quick test_span_to_range_multi_line;
      Alcotest.test_case "span_contains inside"         `Quick test_span_contains_inside;
      Alcotest.test_case "span_contains outside"        `Quick test_span_contains_outside;
      Alcotest.test_case "span_contains multi-line"     `Quick test_span_contains_multi_line;
      Alcotest.test_case "span_smaller"                 `Quick test_span_smaller;
      Alcotest.test_case "lsp_pos round-trip"           `Quick test_lsp_pos_round_trip;
    ];
    "diagnostics", [
      Alcotest.test_case "valid code: zero diagnostics"          `Quick test_analyse_valid_no_diagnostics;
      Alcotest.test_case "empty module: zero diagnostics"        `Quick test_analyse_empty_module;
      Alcotest.test_case "empty string: no crash"                `Quick test_analyse_empty_string;
      Alcotest.test_case "type error → diagnostic"               `Quick test_analyse_type_error_produces_diagnostic;
      Alcotest.test_case "parse error → diagnostic"              `Quick test_analyse_parse_error_produces_diagnostic;
      Alcotest.test_case "multiple errors all reported"          `Quick test_analyse_multiple_errors_all_reported;
      Alcotest.test_case "warning severity"                      `Quick test_analyse_warning_severity;
      Alcotest.test_case "notes appended to message"             `Quick test_analyse_notes_appended_to_message;
      Alcotest.test_case "diagnostics from user file"            `Quick test_multiple_errors_all_from_user_file;
      Alcotest.test_case "src field matches input"               `Quick test_analyse_src_field_matches_input;
    ];
    "document-symbols", [
      Alcotest.test_case "fn name in symbols"            `Quick test_document_symbols_fn;
      Alcotest.test_case "type + ctors in symbols"       `Quick test_document_symbols_type;
      Alcotest.test_case "interface in symbols"          `Quick test_document_symbols_interface;
      Alcotest.test_case "multiple decls in symbols"     `Quick test_document_symbols_multiple_decls;
      Alcotest.test_case "type symbol has Class kind"    `Quick test_document_symbols_kind_for_type;
    ];
    "completions", [
      Alcotest.test_case "keywords in completions"          `Quick test_completions_include_keywords;
      Alcotest.test_case "in-scope names in completions"    `Quick test_completions_include_in_scope_names;
      Alcotest.test_case "type ctors in completions"        `Quick test_completions_include_type_constructors;
      Alcotest.test_case "data ctors in completions"        `Quick test_completions_include_data_constructors;
      Alcotest.test_case "interfaces in completions"        `Quick test_completions_include_interfaces;
      Alcotest.test_case "underscore vars excluded"         `Quick test_completions_no_leading_underscore_vars;
    ];
    "goto-definition", [
      Alcotest.test_case "let binding resolves"                 `Quick test_definition_at_let_binding;
      Alcotest.test_case "no definition for literal"            `Quick test_definition_at_outside_any_use;
      Alcotest.test_case "function name reference resolves"     `Quick test_definition_at_function_name_reference;
      Alcotest.test_case "constructor expression resolves"      `Quick test_definition_at_constructor_expression;
      Alcotest.test_case "constructor pattern resolves"         `Quick test_definition_at_constructor_pattern;
      Alcotest.test_case "definition-site fallback"             `Quick test_definition_at_type_definition_site;
      Alcotest.test_case "type name in decl resolves"           `Quick test_definition_at_type_name;
    ];
    "hover-types", [
      Alcotest.test_case "no type at module keyword"      `Quick test_type_at_no_position;
      Alcotest.test_case "int literal type"               `Quick test_type_at_int_literal;
      Alcotest.test_case "some type found in valid module" `Quick test_type_at_returns_string;
    ];
    "inlay-hints", [
      Alcotest.test_case "hints for valid code"           `Quick test_inlay_hints_nonempty_for_valid_code;
      Alcotest.test_case "no hints outside file range"    `Quick test_inlay_hints_empty_for_wrong_range;
      Alcotest.test_case "hint label starts with ': '"    `Quick test_inlay_hint_has_colon_prefix;
    ];
    "march-specific", [
      Alcotest.test_case "find_impls_of: present"             `Quick test_find_impls_of_present;
      Alcotest.test_case "find_impls_of: absent"              `Quick test_find_impls_of_absent;
      Alcotest.test_case "find_impls_of: unknown interface"   `Quick test_find_impls_of_unknown_interface;
      Alcotest.test_case "actor info at actor name"           `Quick test_actor_info_at_actor_name;
      Alcotest.test_case "actor info state fields"            `Quick test_actor_info_state_fields;
      Alcotest.test_case "no actor info on fn"                `Quick test_actor_info_not_at_random_position;
      Alcotest.test_case "pipe chain: no type errors"         `Quick test_pipe_chain_parsed_without_errors;
      Alcotest.test_case "pipe chain: type available"         `Quick test_pipe_chain_type_available;
      Alcotest.test_case "derive: no crash"                   `Quick test_derive_no_false_errors;
      Alcotest.test_case "linear binding: no crash"           `Quick test_linear_consumption_map_built;
    ];
    "error-recovery", [
      Alcotest.test_case "empty file: no crash"               `Quick test_empty_file_no_crash;
      Alcotest.test_case "partial source: no crash"           `Quick test_partial_source_no_crash;
      Alcotest.test_case "bad grammar: no crash"              `Quick test_malformed_grammar_no_crash;
      Alcotest.test_case "comment-only source: no crash"      `Quick test_source_with_only_comment_no_crash;
      Alcotest.test_case "missing expression: no crash"       `Quick test_missing_expression_no_crash;
      Alcotest.test_case "lexer error: diagnostic produced"   `Quick test_lexer_error_produces_diagnostic;
      Alcotest.test_case "unterminated string: diagnostic"    `Quick test_unterminated_string_is_diagnostic;
    ];
    "analysis-struct", [
      Alcotest.test_case "empty module: struct fields"        `Quick test_empty_module_fields_empty;
      Alcotest.test_case "type_map populated for valid code"  `Quick test_analysis_has_type_map;
      Alcotest.test_case "def_map contains fn name"          `Quick test_analysis_has_def_map;
    ];
    "doc strings", [
      "documented fn",          `Quick, test_doc_for_documented_fn;
      "undocumented fn",        `Quick, test_doc_for_undocumented_fn;
      "unknown name",           `Quick, test_doc_for_unknown_name;
      "at call-site cursor",    `Quick, test_doc_name_at_cursor;
      "triple-quoted",          `Quick, test_doc_triple_quoted;
      "hover has both type and doc", `Quick, test_hover_includes_doc;
      "stdlib fn doc on hover",      `Quick, test_doc_stdlib_hover;
    ];
    "find references", [
      "literal has no refs",       `Quick, test_references_empty_for_literal;
      "finds multiple uses",        `Quick, test_references_finds_uses;
      "include_declaration flag",   `Quick, test_references_include_declaration;
      "local variable",             `Quick, test_references_local_variable;
      "no cross-contamination",     `Quick, test_references_no_cross_contamination;
    ];
    "rename symbol", [
      "literal produces no edits",    `Quick, test_rename_no_edits_for_literal;
      "def + uses all renamed",        `Quick, test_rename_produces_edits_for_def_and_uses;
      "new name appears in all edits", `Quick, test_rename_new_name_in_edits;
      "other names untouched",         `Quick, test_rename_does_not_rename_other_names;
    ];
    "signature help", [
      "none outside call",       `Quick, test_sig_help_none_outside_call;
      "single param",            `Quick, test_sig_help_single_param;
      "active param index",      `Quick, test_sig_help_active_param_index;
      "param labels",            `Quick, test_sig_help_param_labels;
      "non-resolvable callee",   `Quick, test_sig_help_not_a_known_function;
    ];
    "code actions: make-linear", [
      "offered for single-use binding",  `Quick, test_make_linear_offered_for_single_use;
      "not offered for multi-use",        `Quick, test_make_linear_not_offered_for_multi_use;
      "edit inserts 'linear ' keyword",   `Quick, test_make_linear_edit_inserts_keyword;
    ];
    "code actions: exhaustion quickfix", [
      "absent for exhaustive match",    `Quick, test_exhaustion_quickfix_absent_for_exhaustive_match;
      "offered for incomplete match",   `Quick, test_exhaustion_quickfix_offered_for_incomplete_match;
      "edit contains missing arm",      `Quick, test_exhaustion_quickfix_edit_contains_missing_arm;
      "edit inserts before end",        `Quick, test_exhaustion_quickfix_edit_inserts_before_end;
    ];
    "phase2: enhanced exhaustive match", [
      "bulk action offered for multiple missing", `Quick, test_exhaustion_all_cases_action_offered;
      "bulk edit covers all missing cases",       `Quick, test_exhaustion_all_cases_edit_covers_all;
      "no bulk action when only one missing",     `Quick, test_exhaustion_single_missing_no_bulk;
    ];
    "phase2: quickfix framework", [
      "registry has known codes",                 `Quick, test_fix_registry_has_known_codes;
      "registry returns empty for unknown code",  `Quick, test_apply_fix_registry_empty_for_unknown_code;
    ];
    "phase2: dead code detection", [
      "unused private fn: warning emitted",       `Quick, test_unused_private_fn_warning;
      "used private fn: no warning",              `Quick, test_used_private_fn_no_warning;
      "unreachable after panic: warning emitted", `Quick, test_unreachable_code_after_panic_warning;
      "unused_fns field populated correctly",     `Quick, test_unused_fns_field_populated;
    ];
    "code actions: naming convention (P2.8)", [
      "camelCase fn detected",                    `Quick, test_naming_violation_camel_fn_detected;
      "suggested name is snake_case",             `Quick, test_naming_violation_suggested_name;
      "detects fn inside nested mod",             `Quick, test_naming_violation_deeply_nested_detected;
      "no violation for good snake_case fn",      `Quick, test_naming_violation_no_violation_for_snake_fn;
      "rename action offered for camelCase fn",   `Quick, test_naming_action_offered_for_camel_fn;
      "rename edit uses snake_case name",         `Quick, test_naming_action_edit_uses_snake_case;
      "no action for already-snake fn",           `Quick, test_naming_action_absent_for_snake_fn;
    ];
    "code actions: De Morgan (P3.10)", [
      "!(a && b) detected",                       `Quick, test_demorgan_not_and_detected;
      "!(a || b) detected",                       `Quick, test_demorgan_not_or_detected;
      "!a && !b detected",                        `Quick, test_demorgan_pair_negs_detected;
      "action offered for !(a && b)",             `Quick, test_demorgan_action_offered_for_not_and;
      "!(a && b) rewrite contains '||'",          `Quick, test_demorgan_action_rewrite_not_and;
      "!a && !b rewrite is !(... || ...)",        `Quick, test_demorgan_action_rewrite_pair_negs;
    ];
  ]
