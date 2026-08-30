(** March LSP tests: DAP inline values, semantic-token deltas, call hierarchy, auto-import, selection/linked-editing ranges, doc-comment and introduce-parameter-object refactors, project diagnostics

    Moved verbatim out of [test_lsp.ml]; see [Test_lsp_harness]. *)

open Test_lsp_harness

(* ------------------------------------------------------------------ *)
(* DAP inline values (textDocument/inlineValue)                        *)
(* ------------------------------------------------------------------ *)

(* Extract the (variableName, range) of every InlineValueVariableLookup. *)
let inline_lookups (vs : Lsp.Types.InlineValue.t list) =
  List.filter_map (function
    | `InlineValueVariableLookup (l : Lsp.Types.InlineValueVariableLookup.t) ->
      Some (Option.value ~default:"" l.Lsp.Types.InlineValueVariableLookup.variableName, l)
    | _ -> None) vs

let test_inline_values_locals_in_range () =
  let src = {|mod M do
  fn f() : Int do
    let a = 1
    let b = 2
    a + b
  end
end|} in
  let a = analyse src in
  (* Stopped on the `a + b` line; range covers the whole body. *)
  let (stopped_line, _) = pos_of src "a + b" in
  let vs = An.query_inline_values a
      ~range_start_line:1 ~range_end_line:5 ~stopped_line in
  let names = List.map fst (inline_lookups vs) |> List.sort compare in
  Alcotest.(check (list string)) "reports both locals a and b"
    ["a"; "b"] names

let test_inline_values_lookup_names_and_positions () =
  let src = {|mod M do
  fn f() : Int do
    let a = 1
    let b = 2
    a + b
  end
end|} in
  let a = analyse src in
  let (stopped_line, _) = pos_of src "a + b" in
  let vs = An.query_inline_values a
      ~range_start_line:1 ~range_end_line:5 ~stopped_line in
  let lookups = inline_lookups vs in
  let find n = List.assoc_opt n lookups in
  (* `a`'s nearest-to-stopped occurrence is the use on the `a + b` line. *)
  (match find "a" with
   | Some l ->
     Alcotest.(check bool) "a lookup is case-sensitive" true
       l.Lsp.Types.InlineValueVariableLookup.caseSensitiveLookup;
     Alcotest.(check int) "a lookup sits on the stopped line" stopped_line
       l.Lsp.Types.InlineValueVariableLookup.range.Lsp.Types.Range.start.Lsp.Types.Position.line
   | None -> Alcotest.fail "expected a lookup for a");
  (match find "b" with
   | Some _ -> ()
   | None -> Alcotest.fail "expected a lookup for b")

let test_inline_values_excludes_below_stopped_line () =
  let src = {|mod M do
  fn f() : Int do
    let a = 1
    let b = 2
    a + b
  end
end|} in
  let a = analyse src in
  (* Stopped on the `let a = 1` line: b (defined below) must be excluded. *)
  let (stopped_line, _) = pos_of src "let a = 1" in
  let vs = An.query_inline_values a
      ~range_start_line:1 ~range_end_line:5 ~stopped_line in
  let names = List.map fst (inline_lookups vs) in
  Alcotest.(check bool) "a (at/above stopped line) included" true
    (List.mem "a" names);
  Alcotest.(check bool) "b (below stopped line) excluded" false
    (List.mem "b" names)

let test_inline_values_dedup_by_name () =
  (* `x` is used twice on the stopped line; only one lookup should be emitted. *)
  let src = {|mod M do
  fn f() : Int do
    let x = 1
    x + x
  end
end|} in
  let a = analyse src in
  let (stopped_line, _) = pos_of src "x + x" in
  let vs = An.query_inline_values a
      ~range_start_line:1 ~range_end_line:4 ~stopped_line in
  let xs = List.filter (fun (n, _) -> n = "x") (inline_lookups vs) in
  Alcotest.(check int) "exactly one lookup for x" 1 (List.length xs)

let test_inline_values_no_crash_on_error_buffer () =
  let src = "mod M do\n  fn f( : Int do\n    let a =\n" in
  let a = analyse src in
  let vs = An.query_inline_values a
      ~range_start_line:0 ~range_end_line:3 ~stopped_line:3 in
  Alcotest.(check bool) "error buffer yields a (possibly empty) list, no crash"
    true (List.length vs >= 0)

(* ------------------------------------------------------------------ *)
(* Semantic tokens delta                                               *)
(* ------------------------------------------------------------------ *)

let test_semantic_tokens_delta_middle () =
  let (start, del, data) =
    March_lsp_lib.Server.token_delta [|1;2;3;4|] [|1;9;3;4|] in
  Alcotest.(check int) "start after common prefix" 1 start;
  Alcotest.(check int) "deleteCount of changed span" 1 del;
  Alcotest.(check (list int)) "replacement data" [9] (Array.to_list data)

let test_semantic_tokens_delta_append () =
  let (start, del, data) =
    March_lsp_lib.Server.token_delta [|1;2|] [|1;2;5;6|] in
  Alcotest.(check int) "start at end of old" 2 start;
  Alcotest.(check int) "nothing deleted" 0 del;
  Alcotest.(check (list int)) "appended data" [5;6] (Array.to_list data)

let test_semantic_tokens_delta_identical () =
  let (_, del, data) =
    March_lsp_lib.Server.token_delta [|1;2;3|] [|1;2;3|] in
  Alcotest.(check int) "no deletion for identical" 0 del;
  Alcotest.(check int) "no replacement for identical" 0 (Array.length data)

(* ------------------------------------------------------------------ *)
(* Call hierarchy                                                      *)
(* ------------------------------------------------------------------ *)

let ch_src = {|mod M do
  fn leaf(x) do x end
  fn middle(x) do leaf(x) end
  fn top(x) do middle(middle(x)) end
end|}

let test_call_hierarchy_prepare () =
  let a = analyse ch_src in
  let (l, c) = pos_of ch_src "middle(x) do" in
  match An.query_prepare_call_hierarchy_at a ~line:l ~utf16_char:c with
  | Some (name, _, _) -> Alcotest.(check string) "prepares the fn under cursor" "middle" name
  | None -> Alcotest.fail "expected a call-hierarchy item for middle"

let test_call_hierarchy_incoming () =
  let a = analyse ch_src in
  (* who calls `middle`? top, twice. *)
  let calls = An.query_incoming_calls a "middle" in
  let callers = List.map (fun ((n, _, _), _) -> n) calls in
  Alcotest.(check bool) "top is an incoming caller of middle" true (List.mem "top" callers);
  let top_ranges =
    List.concat_map (fun ((n, _, _), rs) -> if n = "top" then rs else []) calls in
  Alcotest.(check int) "top calls middle twice" 2 (List.length top_ranges)

let test_call_hierarchy_outgoing () =
  let a = analyse ch_src in
  (* what does `middle` call? leaf. *)
  let calls = An.query_outgoing_calls a "middle" in
  let callees = List.map (fun ((n, _, _), _) -> n) calls in
  Alcotest.(check bool) "middle calls leaf" true (List.mem "leaf" callees)

(* ------------------------------------------------------------------ *)
(* Auto-import on completion                                           *)
(* ------------------------------------------------------------------ *)

let test_prefix_at () =
  let src = "mod M do\n  fn f() do hel end\nend" in
  let a = analyse src in
  let (l, c) = pos_of src "hel" in
  Alcotest.(check string) "trailing identifier before cursor" "hel"
    (An.prefix_at a ~line:l ~character:(c + 3))

let test_prefix_at_qualified_is_empty () =
  let src = "mod M do\n  fn f() do Map.g end\nend" in
  let a = analyse src in
  let (l, c) = pos_of src "Map.g" in
  (* cursor right after `Map.` (before g): char before run is '.' → empty *)
  Alcotest.(check string) "qualified access yields no bare prefix" ""
    (An.prefix_at a ~line:l ~character:(c + 4))

(* The candidate logic is pure over (module_index, imports, prefix) so it is
   testable without a loaded stdlib. *)
let idx = [("Map", ["empty"; "entries"]); ("Set", ["empty"; "union"])]

let test_auto_import_offers_unimported () =
  let cands = An.auto_import_candidates ~module_index:idx ~imports:[] ~prefix:"emp" in
  Alcotest.(check bool) "offers Map.empty" true (List.mem ("empty", "Map") cands);
  Alcotest.(check bool) "offers Set.empty (collision → both)" true
    (List.mem ("empty", "Set") cands);
  Alcotest.(check bool) "does not offer prefix-mismatched entries" false
    (List.mem ("entries", "Map") cands)

let test_auto_import_skips_imported () =
  let imports = [ { An.ii_module = "Map"; ii_sel = An.ISAll;
                    ii_span = mk_span 1 0 1 9 } ] in
  let cands = An.auto_import_candidates ~module_index:idx ~imports ~prefix:"emp" in
  Alcotest.(check bool) "Map.empty already imported (UseAll) → not offered" false
    (List.mem ("empty", "Map") cands);
  Alcotest.(check bool) "Set.empty still offered" true (List.mem ("empty", "Set") cands)

let test_auto_import_short_prefix_empty () =
  Alcotest.(check int) "prefix under 2 chars yields nothing" 0
    (List.length (An.auto_import_candidates ~module_index:idx ~imports:[] ~prefix:"e"))

let mk_name txt sl sc el ec = { Ast.txt; span = mk_span sl sc el ec }

let test_import_edit_merge () =
  (* `use Foo.{a, b}` on line 2 → merging `c` appends after `b`. *)
  let imports = [ { An.ii_module = "Foo";
                    ii_sel = An.ISNames [ mk_name "a" 2 11 2 12; mk_name "b" 2 14 2 15 ];
                    ii_span = mk_span 2 2 2 16 } ] in
  match An.compute_import_edit ~imports ~fallback_line:3 ~module_:"Foo" ~name:"c" with
  | None -> Alcotest.fail "expected a merge edit for an existing use list"
  | Some e ->
    Alcotest.(check string) "merge appends ', c'" ", c" e.Lsp.Types.TextEdit.newText

let test_import_edit_insert_after_existing () =
  (* A `use Bar.*` exists but no `use Baz` → insert a fresh line after it. *)
  let imports = [ { An.ii_module = "Bar"; ii_sel = An.ISAll; ii_span = mk_span 2 2 2 10 } ] in
  match An.compute_import_edit ~imports ~fallback_line:3 ~module_:"Baz" ~name:"a" with
  | None -> Alcotest.fail "expected a fresh import insert"
  | Some e ->
    Alcotest.(check bool) "inserts `use Baz.{a}`" true
      (str_contains ~sub:"use Baz.{a}" e.Lsp.Types.TextEdit.newText)

let test_import_edit_insert_no_imports () =
  (* No imports at all → insert at the fallback line. *)
  match An.compute_import_edit ~imports:[] ~fallback_line:2 ~module_:"Baz" ~name:"a" with
  | None -> Alcotest.fail "expected a fresh import insert"
  | Some e ->
    Alcotest.(check bool) "inserts `use Baz.{a}`" true
      (str_contains ~sub:"use Baz.{a}" e.Lsp.Types.TextEdit.newText)

(* ------------------------------------------------------------------ *)
(* Inlay perf-annotations config toggle                                *)
(* ------------------------------------------------------------------ *)

let test_config_perf_toggle_parse () =
  let parse = March_lsp_lib.Server.perf_annotations_from_settings in
  let nested =
    `Assoc [("march", `Assoc [("inlayHints",
      `Assoc [("performanceAnnotations", `Bool false)])])] in
  Alcotest.(check (option bool)) "reads fully-qualified setting" (Some false)
    (parse nested);
  let stripped =
    `Assoc [("inlayHints", `Assoc [("performanceAnnotations", `Bool true)])] in
  Alcotest.(check (option bool)) "reads prefix-stripped setting" (Some true)
    (parse stripped);
  Alcotest.(check (option bool)) "absent setting is None" None
    (parse (`Assoc [("other", `Int 1)]))

(* ------------------------------------------------------------------ *)
(* selectionRange + linkedEditingRange                                 *)
(* ------------------------------------------------------------------ *)

let range_contains (o : Lsp.Types.Range.t) (i : Lsp.Types.Range.t) =
  (o.start.line < i.start.line ||
     (o.start.line = i.start.line && o.start.character <= i.start.character))
  && (o.end_.line > i.end_.line ||
     (o.end_.line = i.end_.line && o.end_.character >= i.end_.character))

let test_selection_range_widens_outward () =
  let src = {|mod M do
  fn f() : Int do
    let x = 1 + 2
    x
  end
end|} in
  let a = analyse src in
  let (l, c) = pos_of src "1 + 2" in
  let ranges = An.query_selection_range_at a ~line:l ~utf16_char:c in
  Alcotest.(check bool) "selection chain has at least two levels" true
    (List.length ranges >= 2);
  (* each successive range must strictly contain the previous one *)
  let rec widening = function
    | r1 :: (r2 :: _ as rest) -> range_contains r2 r1 && widening rest
    | _ -> true
  in
  Alcotest.(check bool) "ranges widen outward" true (widening ranges)

let test_selection_range_empty_off_token () =
  let src = "mod M do\n  fn f() : Int do 1 end\nend" in
  let a = analyse src in
  (* line 99 is past the file → no containing spans *)
  let ranges = An.query_selection_range_at a ~line:99 ~utf16_char:0 in
  Alcotest.(check int) "no ranges off the document" 0 (List.length ranges)

let test_linked_editing_ranges () =
  let src = {|mod M do
  fn f() : Int do
    let x = 1
    x + x
  end
end|} in
  let a = analyse src in
  let (l, c) = pos_of src "x + x" in
  let ranges = An.query_linked_editing_ranges_at a ~line:l ~utf16_char:c in
  Alcotest.(check int) "links the binding and both uses of x" 3 (List.length ranges)

let test_tag_pair_linked_edit () =
  let src = {|mod M do
  fn page() : IOList do
    ~H"<div><span>x</span></div>"
  end
end|} in
  let a = analyse src in
  let (l, c) = pos_of src "<div>" in
  let spans = An.linked_editing_ranges_at a ~line:l ~character:(c + 1) in  (* on 'd' of open <div> *)
  Alcotest.(check int) "open + close div linked" 2 (List.length spans)

(* Phase 2+ AST-driven code actions                                    *)
(* ------------------------------------------------------------------ *)

(** Lower-cased substring test. *)
let actions_at ?(off = 0) src sub =
  let a = analyse src in
  let (line, c0) = pos_of src sub in
  An.code_actions_at a ~line ~character:(c0 + off) ~diagnostics:a.An.diagnostics ()

let has_title acts title =
  List.exists (fun (c : Lsp.Types.CodeAction.t) -> contains_sub c.title title) acts

(** First edit text of the first action whose title contains [title]. *)
let edit_text_of acts title =
  match List.find_opt (fun (c : Lsp.Types.CodeAction.t) -> contains_sub c.title title) acts with
  | None -> None
  | Some c ->
    (match c.edit with
     | None -> None
     | Some e ->
       (match e.changes with
        | Some ((_, (te :: _)) :: _) -> Some te.Lsp.Types.TextEdit.newText
        | _ -> None))

(** Concatenation of all edit newTexts of the matching action. *)
let test_introduce_pipe_offered () =
  let src = {|mod M do
  fn f(x) do x end
  fn g(x) do x end
  fn main() do f(g(3)) end
end
|} in
  let acts = actions_at src "f(g(3))" in
  Alcotest.(check bool) "introduce pipe offered" true (has_title acts "introduce pipe");
  Alcotest.(check string) "introduce pipe edit"
    "g(3) |> f()" (Option.value ~default:"" (edit_text_of acts "introduce pipe"))

let test_remove_pipe_offered () =
  let src = {|mod M do
  fn f(x) do x end
  fn g(x) do x end
  fn main() do 3 |> g() |> f() end
end
|} in
  let acts = actions_at src "3 |>" in
  Alcotest.(check bool) "remove pipe offered" true (has_title acts "remove pipe");
  Alcotest.(check string) "remove pipe collapses chain"
    "f(g(3))" (Option.value ~default:"" (edit_text_of acts "remove pipe"))

let test_extract_variable_offered () =
  let src = {|mod M do
  fn sqr(a) do a * a end
  fn main() do
    let d = sqr(3 + 4)
    d
  end
end
|} in
  let acts = actions_at src "sqr(3" in
  Alcotest.(check bool) "extract variable offered" true (has_title acts "extract variable");
  let txt = all_edit_texts acts "extract variable" in
  Alcotest.(check bool) "extract inserts let binding" true (contains_sub txt "let ")

let test_inline_variable_offered () =
  let src = {|mod M do
  fn main() do
    let g = 99
    g + g
  end
end
|} in
  let acts = actions_at src "g = " in
  Alcotest.(check bool) "inline variable offered" true (has_title acts "inline variable");
  let txt = all_edit_texts acts "inline variable" in
  Alcotest.(check bool) "inline substitutes value" true (contains_sub txt "99")

let test_collapse_capture_offered () =
  let src = {|mod M do
  fn trim(x) do x end
  fn main() do map(items, fn (x) -> trim(x)) end
end
|} in
  let acts = actions_at src "fn (x) -> trim" in
  Alcotest.(check bool) "collapse to function offered" true (has_title acts "collapse to")

let test_expand_capture_offered () =
  let src = {|mod M do
  fn trim(x) do x end
  fn use_it(f) do f end
  fn main() do use_it(trim) end
end
|} in
  let acts = actions_at src "use_it(trim)" ~off:7 in
  Alcotest.(check bool) "expand to lambda offered" true (has_title acts "expand to lambda")

let test_hole_fill_variant () =
  let src = {|mod M do
  type Col = Red | Grn | Blu
  fn pick() : Col do ? end
end
|} in
  let acts = actions_at src "? end" in
  Alcotest.(check bool) "fill hole offered" true (has_title acts "fill hole");
  Alcotest.(check bool) "fills with Red" true (has_title acts "Red")

let test_hole_fill_bool () =
  let src = {|mod M do
  fn pick() : Bool do ? end
end
|} in
  let acts = actions_at src "? end" in
  Alcotest.(check bool) "fills with true" true (has_title acts "true");
  Alcotest.(check bool) "fills with false" true (has_title acts "false")

let test_impl_scaffold_offered () =
  let src = {|mod T do
  interface Greet(a) do
    fn hello: a -> String
  end
  type P = P(Int)
  impl Greet(P) do
  end
end
|} in
  let acts = actions_at src "impl Greet" in
  Alcotest.(check bool) "impl scaffold offered" true (has_title acts "missing method");
  let txt = all_edit_texts acts "missing method" in
  Alcotest.(check bool) "scaffold stubs hello" true (contains_sub txt "fn hello")

let test_auto_import_offered () =
  let src = {|mod M do
  mod Helper do
    fn special() do 1 end
  end
  fn main() do special() end
end
|} in
  let acts = actions_at src "do special()" ~off:3 in
  Alcotest.(check bool) "auto-import offered" true (has_title acts "import `special`");
  let txt = all_edit_texts acts "import `special`" in
  Alcotest.(check bool) "inserts use Helper" true (contains_sub txt "use Helper")

let test_actor_boilerplate_offered () =
  let src = {|mod M do
  actor Counter do
    state { count: Int }
    init { count: 0 }
    on Inc() do
      count
    end
  end
end
|} in
  let acts = actions_at src "actor Counter" in
  Alcotest.(check bool) "actor client offered" true (has_title acts "CounterClient");
  let txt = all_edit_texts acts "CounterClient" in
  Alcotest.(check bool) "client has inc wrapper" true (contains_sub txt "fn inc")

let test_session_scaffold_offered () =
  let src = {|mod M do
  protocol Ping do
    Client -> Server : Int
    Server -> Client : Int
  end
end
|} in
  let acts = actions_at src "protocol Ping" in
  Alcotest.(check bool) "session handler offered" true (has_title acts "session handler");
  let txt = all_edit_texts acts "session handler" in
  Alcotest.(check bool) "handler uses receive" true (contains_sub txt "receive")

let test_if_to_match_offered () =
  let src = {|mod M do
  fn main() do
    let x = 1
    if x == 1 do 10 else 20 end
  end
end
|} in
  let acts = actions_at src "if x ==" in
  Alcotest.(check bool) "convert if to match offered" true (has_title acts "convert if to match");
  let txt = all_edit_texts acts "convert if to match" in
  Alcotest.(check bool) "produces match" true (contains_sub txt "match x")

let test_linear_audit_offered () =
  let src = {|mod M do
  fn consume(linear x : Int) : Int do x end
end
|} in
  let acts = actions_at src "linear x" ~off:7 in
  Alcotest.(check bool) "linear audit offered" true (has_title acts "linear `x`")

let test_batch_fix_all_offered () =
  let src = {|mod M do
  fn f(aa, bb) do 0 end
end
|} in
  let acts = actions_at src "fn f" in
  Alcotest.(check bool) "batch fix-all offered" true (has_title acts "fix all")

let test_ast_actions_no_crash_on_error () =
  (* Unparseable / partially-typed source must not crash the action pass. *)
  let src = "mod M do\n  fn main() do f(g( end\nend\n" in
  let acts = actions_at src "main" in
  Alcotest.(check bool) "no crash on malformed source" true (List.length acts >= 0)

let test_destruct_offered () =
  let src = {|mod M do
  type Shape = Circle(Int) | Square(Int) | Point
  fn area(s: Shape) do
    s
  end
end
|} in
  let acts = actions_at src "    s\n" ~off:4 in
  Alcotest.(check bool) "destruct offered" true (has_title acts "destruct");
  let txt = all_edit_texts acts "destruct" in
  Alcotest.(check bool) "match over s"       true (contains_sub txt "match s do");
  Alcotest.(check bool) "covers Circle"      true (contains_sub txt "Circle");
  Alcotest.(check bool) "covers Square"      true (contains_sub txt "Square");
  Alcotest.(check bool) "covers Point"       true (contains_sub txt "Point");
  Alcotest.(check bool) "binds ctor fields"  true (contains_sub txt "Circle(x0)")

let test_destruct_not_offered_when_type_unknown () =
  (* Polymorphic param: no concrete variant type -> no destruct. *)
  let src = {|mod M do
  fn area(s) do
    s
  end
end
|} in
  let acts = actions_at src "    s\n" ~off:4 in
  Alcotest.(check bool) "no destruct without a known type" false (has_title acts "destruct")

let test_extract_function_offered () =
  let src = {|mod M do
  fn dist(x: Int, y: Int) do
    sqrt(x * x + y * y)
  end
end
|} in
  let acts = actions_at src "+ y" in           (* cursor on the + spans the whole sum *)
  Alcotest.(check bool) "extract function offered" true (has_title acts "extract function");
  let txt = all_edit_texts acts "extract function" in
  Alcotest.(check bool) "captures free locals x and y with types" true
    (contains_sub txt "fn extracted(x: Int, y: Int)");
  Alcotest.(check bool) "call passes the captured args" true (contains_sub txt "extracted(x, y)");
  Alcotest.(check bool) "global sqrt not captured as a param" false
    (contains_sub txt "sqrt:")

let test_organize_imports_offered () =
  let src = {|mod M do
  use Zebra.{a}
  use Apple.{b}
  use Apple.{b}
  use Mango
  fn main() do 0 end
end
|} in
  let acts = actions_at src "use Zebra" in
  Alcotest.(check bool) "organize imports offered" true (has_title acts "organize imports");
  let txt = all_edit_texts acts "organize imports" in
  Alcotest.(check bool) "keeps Apple" true (contains_sub txt "use Apple.{b}");
  Alcotest.(check bool) "keeps Mango" true (contains_sub txt "use Mango");
  (* Sorted: Apple appears before Zebra in the organized block. *)
  let block = (match List.find_opt (fun (c : Lsp.Types.CodeAction.t) ->
      contains_sub c.title "organize imports") acts with
      | Some c -> (match c.edit with
          | Some e -> (match e.changes with
              | Some ((_, (te :: _)) :: _) -> te.Lsp.Types.TextEdit.newText | _ -> "")
          | None -> "")
      | None -> "") in
  let idx s sub = (* first index of sub in s, or -1 *)
    let sl = String.length s and nl = String.length sub in
    let rec f i = if i + nl > sl then -1
                  else if String.sub s i nl = sub then i else f (i + 1) in f 0 in
  Alcotest.(check bool) "Apple sorted before Zebra" true (idx block "Apple" < idx block "Zebra" && idx block "Apple" >= 0)

let test_organize_imports_not_offered_when_sorted () =
  let src = {|mod M do
  use Apple.{b}
  use Zebra.{a}
  fn main() do 0 end
end
|} in
  let acts = actions_at src "use Apple" in
  Alcotest.(check bool) "no action when already sorted+unique" false
    (has_title acts "organize imports")

(* ------------------------------------------------------------------ *)
(* Generate doc comment + inline function (Phase 3/6)                  *)
(* ------------------------------------------------------------------ *)

let test_generate_doc_comment () =
  let src = {|mod M do
  fn process(input, limit) : Int do
    input
  end
end|} in
  let acts = actions_at src "process" in
  Alcotest.(check bool) "offers Generate doc comment" true
    (has_title acts "Generate doc comment");
  let edit = Option.value ~default:"" (edit_text_of acts "Generate doc comment") in
  Alcotest.(check bool) "scaffold has doc string + param names" true
    (contains_sub edit "doc \"" && contains_sub edit "input" && contains_sub edit "limit")

let test_no_doc_comment_when_documented () =
  let src = {|mod M do
  doc "already documented"
  fn process(x) : Int do x end
end|} in
  let acts = actions_at src "process" in
  Alcotest.(check bool) "no action for an already-documented fn" false
    (has_title acts "Generate doc comment")

let test_inline_function () =
  let src = {|mod M do
  fn double(x) : Int do x + x end
  fn f() : Int do double(21) end
end|} in
  let acts = actions_at src "double(21)" in
  Alcotest.(check bool) "offers Inline function" true (has_title acts "Inline function");
  let edit = Option.value ~default:"" (edit_text_of acts "Inline function") in
  Alcotest.(check bool) "substitutes the argument into the body" true
    (contains_sub edit "21 + 21")

let test_no_inline_recursive_function () =
  let src = {|mod M do
  fn recur(n) : Int do recur(n) end
  fn f() : Int do recur(3) end
end|} in
  let acts = actions_at src "recur(3)" in
  Alcotest.(check bool) "no inline for a recursive function" false
    (has_title acts "Inline function")

let test_auto_alias_repeated_prefix () =
  let src = {|mod App do
  fn a() : Int do Collections.HashMap.empty() end
  fn b() : Int do Collections.HashMap.insert() end
  fn c() : Int do Collections.HashMap.get() end
end|} in
  let acts = actions_at src "Collections.HashMap.empty" in
  Alcotest.(check bool) "offers auto-alias for a 3x-repeated prefix" true
    (has_title acts "alias Collections.HashMap");
  let edits = all_edit_texts acts "alias Collections.HashMap" in
  Alcotest.(check bool) "inserts the alias declaration" true
    (contains_sub edits "alias Collections.HashMap");
  Alcotest.(check bool) "rewrites uses to the short name" true
    (contains_sub edits "HashMap.empty")

let test_no_auto_alias_below_threshold () =
  let src = {|mod App do
  fn a() : Int do Collections.HashMap.empty() end
end|} in
  let acts = actions_at src "Collections.HashMap.empty" in
  Alcotest.(check bool) "no alias for a single use" false
    (has_title acts "alias Collections.HashMap")

let test_remove_unused_function () =
  let src = {|mod M do
  pfn helper() : Int do 2 end
  fn main() : Int do 1 end
end|} in
  (* helper is private and never called → dead; cursor on its name *)
  let acts = actions_at src "helper" in
  Alcotest.(check bool) "offers Remove unused function" true
    (has_title acts "Remove unused function");
  Alcotest.(check (option string)) "deletes the declaration (empty newText)"
    (Some "") (edit_text_of acts "Remove unused function")

let test_no_remove_used_function () =
  let src = {|mod M do
  pfn helper() : Int do 2 end
  fn main() : Int do helper() end
end|} in
  let acts = actions_at src "helper" in
  Alcotest.(check bool) "no remove action for a used function" false
    (has_title acts "Remove unused function")

let test_remove_unreachable_code () =
  let src = {|mod M do
  fn f() : Int do
    panic("boom")
    42
  end
end|} in
  (* `42` is unreachable after the diverging panic → diagnostic-driven quickfix *)
  let acts = actions_at src "panic" in
  Alcotest.(check bool) "offers Remove unreachable code" true
    (has_title acts "Remove unreachable code");
  Alcotest.(check (option string)) "deletes the dead line (empty newText)"
    (Some "") (edit_text_of acts "Remove unreachable code")

(* ------------------------------------------------------------------ *)
(* Bug fixes: annotation record-type guard + missing-case arm syntax   *)
(* ------------------------------------------------------------------ *)

let test_add_missing_case_no_leading_pipe () =
  (* March match arms have no leading `|`; the generated arm must not add one
     (a `|` after the existing newline is a double separator → parse error). *)
  let src = {|mod M do
  type Dir = North | South
  fn label(d : Dir) : Int do
    match d do
      North -> 1
    end
  end
end|} in
  let a = analyse src in
  let (line, col) = pos_of src "match d" in
  let acts = An.code_actions_at a ~line ~character:col ~diagnostics:a.An.diagnostics () in
  let arm =
    match List.find_opt (fun (c : Lsp.Types.CodeAction.t) ->
        contains_sub c.title "missing case") acts with
    | Some c -> all_edit_texts [c] "missing case"
    | None -> Alcotest.fail "expected an Add-missing-case action"
  in
  Alcotest.(check bool) "arm mentions the missing constructor" true
    (contains_sub arm "South");
  Alcotest.(check bool) "arm has NO leading pipe" false
    (String.contains arm '|')

let test_annotation_for_named_record_return () =
  (* A function returning a *named* record now recovers the declared name in
     pp_ty (renders as `R`, not `{ … }`), so the action IS offered and inserts a
     valid surface annotation. (March has no anonymous-record annotation syntax,
     so the only records that flow here are named; truly unnameable records still
     render with braces and are skipped by the annotatable_ty_str guard.) *)
  let src = {|mod M do
  type R = { a : Int, b : Int }
  fn mk(x : Int) do
    { a: x, b: x }
  end
end|} in
  let acts = actions_at src "mk" in
  Alcotest.(check bool) "return annotation offered for a named-record return" true
    (has_title acts "Add return type annotation")

let test_annotation_offered_for_scalar_return () =
  (* Sanity: a normal Int-returning fn gets `: Int` (March return syntax). *)
  let src = {|mod M do
  fn compute(x : Int) do x + 1 end
end|} in
  let acts = actions_at src "compute" in
  Alcotest.(check bool) "return annotation offered for Int" true
    (has_title acts "Add return type annotation");
  let edit = all_edit_texts acts "return type" in
  Alcotest.(check bool) "suggests `: Int` (colon form)" true (contains_sub edit ": Int");
  Alcotest.(check bool) "does not use invalid `->`" false (contains_sub edit "->")

(* ------------------------------------------------------------------ *)
(* Introduce parameter object (data clump → record) detection          *)
(* ------------------------------------------------------------------ *)

let test_extract_captures_action () =
  (* Two closures share {a, b}; extract builds ONE shared record + rewrites both. *)
  let src = {|mod M do
  fn helper(x : Int) : Int do x end
  fn make() do
    let a = 1
    let b = 2
    let f = fn _ -> a + b + helper(0)
    let g = fn _ -> a + b + helper(0)
    f
  end
end|} in
  let a = analyse src in
  let (l, c) = pos_of src "fn _ ->" in
  let acts = An.code_actions_at a ~line:l ~character:c ~diagnostics:a.An.diagnostics () in
  Alcotest.(check bool) "offers extract-captures action" true (has_title acts "captured values");
  let edit = all_edit_texts acts "captured values" in
  Alcotest.(check bool) "record groups the local captures a, b" true
    (contains_sub edit "a = a" && contains_sub edit "b = b");
  Alcotest.(check bool) "excludes the global function helper" false
    (contains_sub edit "helper = helper");
  Alcotest.(check bool) "rewrites the body to captured.a" true
    (contains_sub edit "captured.a")

let test_no_extract_captures_for_single_site () =
  (* A lone closure (one site) no longer warns, and offers no extract. *)
  let src = {|mod M do
  fn make() do
    let a = 1
    let b = 2
    let f = fn _ -> a + b
    f
  end
end|} in
  let a = analyse src in
  let (l, c) = pos_of src "fn _ ->" in
  let acts = An.code_actions_at a ~line:l ~character:c ~diagnostics:a.An.diagnostics () in
  Alcotest.(check bool) "no extract action for a single closure" false
    (has_title acts "captured values")

let test_no_extract_captures_for_globals_only () =
  (* lambda only references globals + its own param → no genuine captures *)
  let src = {|mod M do
  fn helper(x : Int) : Int do x end
  fn make() do
    let f = fn y -> helper(y)
    let g = fn z -> helper(z)
    f
  end
end|} in
  let a = analyse src in
  let (l, c) = pos_of src "fn y ->" in
  let acts = An.code_actions_at a ~line:l ~character:c ~diagnostics:a.An.diagnostics () in
  Alcotest.(check bool) "no extract action when nothing genuine is captured" false
    (has_title acts "captured values")

let test_bundleable_fn_detected () =
  let src = {|mod M do
  fn area(width : Int, height : Int) : Int do width * height end
end|} in
  let a = analyse src in
  let (l, c) = pos_of src "area" in
  Alcotest.(check (option string)) "fn with >=2 annotated params is bundleable"
    (Some "area") (An.bundleable_fn_at a ~line:l ~character:c)

let test_single_param_not_bundleable () =
  let src = {|mod M do
  fn neg(x : Int) : Int do 0 - x end
end|} in
  let a = analyse src in
  let (l, c) = pos_of src "neg" in
  Alcotest.(check (option string)) "single-param fn is not bundleable"
    None (An.bundleable_fn_at a ~line:l ~character:c)

let test_unannotated_params_not_bundleable () =
  let src = {|mod M do
  fn add(x, y) do x + y end
end|} in
  let a = analyse src in
  let (l, c) = pos_of src "add" in
  Alcotest.(check (option string)) "unannotated params are not bundleable"
    None (An.bundleable_fn_at a ~line:l ~character:c)

(* ------------------------------------------------------------------ *)
(* Project-level diagnostics (Feature 17)                              *)
(* ------------------------------------------------------------------ *)

(* ── `cap no_panic` and the EDITOR ───────────────────────────────────────
   The LSP links march_typecheck and never march_refinecheck, so it has no
   verdict index and cannot run the proof-based panic-surface pass Task 3
   (2026-08-05) introduced for the contracted names (`List.tail`, `unwrap`,
   `Stats.mean`, …).  The worry is that those names lost their editor squiggle
   with nothing replacing them.

   Whether they could depends on where the module sits, which is why every
   fixture below is NESTED:

   - a TOP-LEVEL module gets no panic-surface diagnostic from the LSP at all.
     `analysis.ml` goes through [Typecheck.check_module_with_env], which — unlike
     [check_module_core], the path `march --check`/`march check` use — never
     calls [check_no_panic_module] for the entry module.  `panic_` produces
     nothing there either, so a top-level fixture asserts nothing: the equality
     below would hold `false = false` no matter what the ban lists said.
   - a NESTED `mod` DOES get one: [check_decl]'s [A.DMod] branch calls
     [check_no_panic_module] on the inner decls (typecheck.ml, search
     `if inner_env.no_panic_mod`).  So nested modules really did lose these
     diagnostics when the contracted names left the syntactic ban, and really do
     get them back from [Typecheck.proof_based_panic_surface] defaulting to
     false.  That is the only path where this test can fail, so it is the only
     path worth testing.

   Asserted as an EQUALITY against the unconditionally-banned `panic_` rather
   than as "reports something": if the LSP is ever wired to the proof-based
   pass, or the entry module ever starts being checked, the right answer is
   still "whatever `panic_` gets, a contracted name gets", and leaving a
   contracted name out would make the editor silently more permissive than the
   compiler. *)
let no_panic_diags src =
  let a = analyse src in
  let has hay needle =
    let n = String.length needle and h = String.length hay in
    let rec at i = i + n <= h && (String.sub hay i n = needle || at (i + 1)) in
    n = 0 || at 0
  in
  List.filter
    (fun (d : Lsp.Types.Diagnostic.t) ->
      match d.message with
      | `String m -> has m "which can panic"
      | `MarkupContent mc -> has mc.Lsp.Types.MarkupContent.value "which can panic")
    a.An.diagnostics

let nested_np name body =
  Printf.sprintf
    "mod Outer do\n\
    \  mod %s do\n\
    \    cap no_panic\n\
    \    %s\n\
    \  end\n\
    \  fn main() : Int do 0 end\n\
     end" name body

let np_panic_src = nested_np "NPa" "fn f(a : Int) : Int do panic_(\"x\") end"

let np_qualified_src =
  nested_np "NPb" "fn f(xs : List(Int)) : List(Int) do List.tail(xs) end"

let np_bare_src = nested_np "NPc" "fn f(o : Option(Int)) : Int do unwrap(o) end"

let test_lsp_no_panic_contracted_matches_panic () =
  let reports src = no_panic_diags src <> [] in
  (* NOT VACUOUS: the reference side must actually fire, or the two equalities
     below hold trivially.  This is the assertion the previous revision of this
     group was missing — its fixtures were top-level, so nothing ever fired and
     `false = false` passed regardless of the ban lists. *)
  Alcotest.(check bool)
    "the reference case fires: a nested `panic_` IS reported by the LSP"
    true (reports np_panic_src);
  Alcotest.(check bool)
    "a qualified contracted name is reported exactly when `panic_` is"
    (reports np_panic_src) (reports np_qualified_src);
  Alcotest.(check bool)
    "a bare contracted name is reported exactly when `panic_` is"
    (reports np_panic_src) (reports np_bare_src)

let test_lsp_no_panic_clean_module_silent () =
  (* REJECT control: the filter is not matching every nested `cap no_panic`
     module regardless of content. *)
  Alcotest.(check bool) "a safe nested cap no_panic module is silent" true
    (no_panic_diags (nested_np "NPOk" "fn f(a : Int) : Int do a + 1 end") = [])

let test_project_diagnostics () =
  let good = "mod A do\n  fn f() : Int do 1 end\nend" in
  let bad  = "mod B do\n  fn g() : Int do \"oops\" end\nend" in
  let reports = An.project_diagnostics [("a.march", good); ("b.march", bad)] in
  let diags_of f =
    match List.assoc_opt f reports with Some ds -> ds | None -> [] in
  Alcotest.(check int) "clean file has no diagnostics" 0 (List.length (diags_of "a.march"));
  Alcotest.(check bool) "broken file reports a diagnostic" true (diags_of "b.march" <> [])

