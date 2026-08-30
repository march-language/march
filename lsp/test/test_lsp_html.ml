(** March LSP tests: the ~H sigil: unclosed/unknown/duplicate/void tag lints, sigil traversal, island parsing and validation, folding ranges, auto-close, and their regressions

    Moved verbatim out of [test_lsp.ml]; see [Test_lsp_harness]. *)

open Test_lsp_harness

(* ------------------------------------------------------------------ *)
(* ~H sigil: unclosed HTML tag detection + close quickfix              *)
(* ------------------------------------------------------------------ *)

let html_unclosed_diags src =
  let a = analyse src in
  List.filter (fun (d : Lsp.Types.Diagnostic.t) ->
      match d.code with Some (`String "html/unclosed-tag") -> true | _ -> false)
    a.An.diagnostics

let test_html_unclosed_detected () =
  let src = {|mod M do
  fn page() do
    ~H"<div><p>hi"
  end
end|} in
  Alcotest.(check int) "two unclosed tags (div, p)" 2
    (List.length (html_unclosed_diags src))

let test_html_balanced_no_issue () =
  let src = {|mod M do
  fn page() do
    ~H"<div><p>hi</p></div>"
  end
end|} in
  Alcotest.(check int) "balanced html has no unclosed diagnostics" 0
    (List.length (html_unclosed_diags src))

let test_html_void_no_issue () =
  let src = {|mod M do
  fn page() do
    ~H"<br><hr>line"
  end
end|} in
  Alcotest.(check int) "void elements are not unclosed" 0
    (List.length (html_unclosed_diags src))

let test_html_self_closing_no_issue () =
  let src = {|mod M do
  fn page() do
    ~H"<div/>x"
  end
end|} in
  Alcotest.(check int) "self-closing tag is not unclosed" 0
    (List.length (html_unclosed_diags src))

let test_html_close_quickfix () =
  let src = {|mod M do
  fn page() do
    ~H"<div><p>hi"
  end
end|} in
  let a = analyse src in
  let (l, c) = pos_of src "<div" in
  let acts = An.code_actions_at a ~line:l ~character:c ~diagnostics:a.An.diagnostics () in
  Alcotest.(check bool) "offers a Close action" true
    (List.exists (fun (ca : Lsp.Types.CodeAction.t) -> contains_sub ca.title "Close") acts);
  let edit = all_edit_texts acts "Close" in
  Alcotest.(check bool) "inserts </p></div> (innermost first)" true
    (contains_sub edit "</p></div>")

(* ------------------------------------------------------------------ *)
(* ~H sigil traversal: collect_h_sigils                               *)
(* ------------------------------------------------------------------ *)

let test_h_sigils_collected () =
  let src = {|mod M do
  fn page() : IOList do
    ~H"<div>${name}</div>"
  end
end|} in
  let a = An.analyse ~filename:"test.march" ~src in
  Alcotest.(check int) "one ~H sigil found" 1 (List.length a.An.h_sigils);
  let s = List.hd a.An.h_sigils in
  Alcotest.(check bool) "content captured" true
    (contains_sub s.An.hs_content "<div>");
  let (l, _c) = An.ofs_to_pos src (s.An.hs_base_ofs + 0) in
  Alcotest.(check int) "content base maps to the sigil's line" 3 l

(* ------------------------------------------------------------------ *)
(* ~H island tag parser: islands_in_sigil                              *)
(* ------------------------------------------------------------------ *)

let test_island_parse () =
  let src = {|mod M do
  fn page() : IOList do
    ~H"<island name='Counter' />"
  end
end|} in
  let a = An.analyse ~filename:"test.march" ~src in
  let islands = List.concat_map (An.islands_in_sigil ~src) a.An.h_sigils in
  Alcotest.(check int) "one island" 1 (List.length islands);
  let isl = List.hd islands in
  Alcotest.(check string) "module name" "Counter" isl.An.isl_name

let test_island_name_span () =
  (* The name 'Counter' starts on line 3. Verify isl_name_span.start_line = 3
     and that slicing src at the span yields the 7-character string "Counter". *)
  let src = {|mod M do
  fn page() : IOList do
    ~H"<island name='Counter' />"
  end
end|} in
  let a = An.analyse ~filename:"test.march" ~src in
  let islands = List.concat_map (An.islands_in_sigil ~src) a.An.h_sigils in
  let isl = List.hd islands in
  let sp = isl.An.isl_name_span in
  Alcotest.(check int) "name span on line 3" 3 sp.Ast.start_line;
  (* Recover the text the span covers via pos_to_ofs round-trip. *)
  let start_ofs = An.pos_to_ofs src sp.Ast.start_line sp.Ast.start_col in
  let name_len  = String.length isl.An.isl_name in
  Alcotest.(check string) "span text is Counter"
    "Counter" (String.sub src start_ofs name_len)

(* ------------------------------------------------------------------ *)
(* <island> component validation diagnostics                           *)
(* ------------------------------------------------------------------ *)

let test_island_known_but_invalid_flagged () =
  (* A nested module IS visible in module_index by its bare name, so when
     it lacks `create` or `render` we CAN confirm it is a misuse and flag it.
     BadCounter has `create` but no `render` — must emit html/unknown-island. *)
  let src = {|mod App do
  mod BadCounter do
    fn create(n : Int) : Int do n end
  end
  fn page() : Int do
    ~H"<island name='BadCounter' />"
    0
  end
end|} in
  let a = An.analyse ~filename:"test.march" ~src in
  (* Guard: the sigil was seen, so the file parsed and the analysis ran
     (this prevents the test from passing vacuously on a parse failure). *)
  Alcotest.(check bool) "sigil was collected (file parsed)" true
    (a.An.h_sigils <> []);
  let has = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.Lsp.Types.Diagnostic.code with
    | Some (`String "html/unknown-island") -> true | _ -> false)
    a.An.diagnostics in
  Alcotest.(check bool) "known-but-invalid island flagged" true has

let test_island_valid_not_flagged () =
  (* A nested module with both `create` and `render` is a correct island
     component.  Its bare name IS visible in module_index, so we can
     confirm it is correct and must NOT emit a false-positive warning.
     Uses a single top-level `mod` (March only allows one per file). *)
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
  let a = An.analyse ~filename:"test.march" ~src in
  (* Guard: the sigil was seen, so the file parsed and the analysis ran
     (this prevents the test from passing vacuously on a parse failure). *)
  Alcotest.(check bool) "sigil was collected (file parsed)" true
    (a.An.h_sigils <> []);
  let flagged = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.Lsp.Types.Diagnostic.code with
    | Some (`String "html/unknown-island") -> true | _ -> false)
    a.An.diagnostics in
  Alcotest.(check bool) "valid island not flagged" false flagged

(* ------------------------------------------------------------------ *)
(* ~H unknown HTML tag linting                                         *)
(* ------------------------------------------------------------------ *)

let test_html_unknown_tag () =
  let src = {|mod M do
  fn page() : IOList do
    ~H"<dvi></dvi>"
  end
end|} in
  let a = analyse src in
  (* Guard: sigil was collected, file parsed OK. *)
  Alcotest.(check bool) "sigil collected (file parsed)" true (a.An.h_sigils <> []);
  let d = List.find_opt (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.Lsp.Types.Diagnostic.code with
    | Some (`String "html/unknown-tag") -> true | _ -> false) a.An.diagnostics in
  (match d with
   | Some diag ->
     let msg = match diag.Lsp.Types.Diagnostic.message with
               | `String s -> s | `MarkupContent m -> m.Lsp.Types.MarkupContent.value in
     Alcotest.(check bool) "suggests div" true (contains_sub msg "div")
   | None -> Alcotest.fail "expected html/unknown-tag for <dvi>")

let test_html_custom_element_not_flagged () =
  (* Custom elements (name contains '-') must NOT be flagged. *)
  let src = {|mod M do
  fn page() : IOList do
    ~H"<my-widget></my-widget>"
  end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "sigil collected (file parsed)" true (a.An.h_sigils <> []);
  let flagged = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.Lsp.Types.Diagnostic.code with
    | Some (`String "html/unknown-tag") -> true | _ -> false)
    a.An.diagnostics in
  Alcotest.(check bool) "custom element not flagged" false flagged

(* ------------------------------------------------------------------ *)
(* ~H duplicate attribute lint                                         *)
(* ------------------------------------------------------------------ *)

let test_html_duplicate_attr () =
  let src = {|mod M do
  fn page() : IOList do
    ~H"<input type='a' type='b'>"
  end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "sigil collected" true (a.An.h_sigils <> []);
  let has = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.Lsp.Types.Diagnostic.code with
    | Some (`String "html/duplicate-attr") -> true | _ -> false) a.An.diagnostics in
  Alcotest.(check bool) "duplicate attr flagged" true has

let test_html_no_duplicate_attr_for_distinct () =
  (* <input type='a' name='b'> — two DIFFERENT attr names, must NOT be flagged. *)
  let src = {|mod M do
  fn page() : IOList do
    ~H"<input type='a' name='b'>"
  end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "sigil collected" true (a.An.h_sigils <> []);
  let flagged = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.Lsp.Types.Diagnostic.code with
    | Some (`String "html/duplicate-attr") -> true | _ -> false) a.An.diagnostics in
  Alcotest.(check bool) "distinct attrs not flagged" false flagged

(* ------------------------------------------------------------------ *)
(* ~H void / self-closing misuse lint                                  *)
(* ------------------------------------------------------------------ *)

let test_html_void_with_children () =
  let src = {|mod M do
  fn page() : IOList do
    ~H"<br>text</br>"
  end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "sigil collected" true (a.An.h_sigils <> []);
  let has = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.Lsp.Types.Diagnostic.code with
    | Some (`String "html/void-with-children") -> true | _ -> false) a.An.diagnostics in
  Alcotest.(check bool) "void close-tag flagged" true has

let test_html_self_closing_nonvoid () =
  let src = {|mod M do
  fn page() : IOList do
    ~H"<div/>"
  end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "sigil collected" true (a.An.h_sigils <> []);
  let has = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.Lsp.Types.Diagnostic.code with
    | Some (`String "html/self-closing-nonvoid") -> true | _ -> false) a.An.diagnostics in
  Alcotest.(check bool) "self-closing non-void flagged" true has

let test_html_void_self_closing_ok () =
  (* <br/> is void + self-closing — both checks must remain silent. *)
  let src = {|mod M do
  fn page() : IOList do
    ~H"<br/>"
  end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "sigil collected" true (a.An.h_sigils <> []);
  let flagged = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.Lsp.Types.Diagnostic.code with
    | Some (`String "html/void-with-children")
    | Some (`String "html/self-closing-nonvoid") -> true
    | _ -> false) a.An.diagnostics in
  Alcotest.(check bool) "void self-closing not flagged" false flagged

let test_html_normal_pair_ok () =
  (* <div></div> is a normal matched pair — neither check fires. *)
  let src = {|mod M do
  fn page() : IOList do
    ~H"<div></div>"
  end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "sigil collected" true (a.An.h_sigils <> []);
  let flagged = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.Lsp.Types.Diagnostic.code with
    | Some (`String "html/void-with-children")
    | Some (`String "html/self-closing-nonvoid") -> true
    | _ -> false) a.An.diagnostics in
  Alcotest.(check bool) "normal div pair not flagged" false flagged

(* ------------------------------------------------------------------ *)
(* ~H unsafe interpolation inside <script>/<style> lint               *)
(* ------------------------------------------------------------------ *)

let test_html_unsafe_interpolation () =
  let src = {|mod M do
  fn page() : IOList do
    ~H"<script>var x = ${userInput}</script>"
  end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "sigil collected" true (a.An.h_sigils <> []);
  let has = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.Lsp.Types.Diagnostic.code with
    | Some (`String "html/unsafe-interpolation") -> true | _ -> false) a.An.diagnostics in
  Alcotest.(check bool) "interpolation in <script> flagged" true has

let test_html_unsafe_interpolation_style () =
  (* Interpolation inside <style> must also be flagged. *)
  let src = {|mod M do
  fn page() : IOList do
    ~H"<style>body { color: ${color}; }</style>"
  end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "sigil collected" true (a.An.h_sigils <> []);
  let has = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.Lsp.Types.Diagnostic.code with
    | Some (`String "html/unsafe-interpolation") -> true | _ -> false) a.An.diagnostics in
  Alcotest.(check bool) "interpolation in <style> flagged" true has

let test_html_safe_interpolation_in_text () =
  (* Interpolation in normal HTML text is safe (auto-escaped) — must NOT be flagged. *)
  let src = {|mod M do
  fn page() : IOList do
    ~H"<p>${name}</p>"
  end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "sigil collected" true (a.An.h_sigils <> []);
  let flagged = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.Lsp.Types.Diagnostic.code with
    | Some (`String "html/unsafe-interpolation") -> true | _ -> false) a.An.diagnostics in
  Alcotest.(check bool) "interpolation in normal text not flagged" false flagged

(* ------------------------------------------------------------------ *)
(* Island component name completion                                    *)
(* ------------------------------------------------------------------ *)

let test_island_name_completion () =
  (* Cursor immediately after name=' inside an ~H sigil should offer modules
     that are valid island components (have both create and render members).
     pos_of finds the start of "name='" — the cursor is 6 bytes further right,
     just after the opening quote. *)
  let src = {|mod App do
  mod Counter do
    fn create(n : Int) : Int do n end
    fn render(s : Int) : IOList do ~H"<p>${s}</p>" end
  end
  fn page() : IOList do
    ~H"<island name='"
  end
end|} in
  let a = analyse src in
  let (l, c) = pos_of src "name='" in
  (* +6 = length of "name='" — positions cursor just after the opening quote *)
  let items = An.completions_at a ~line:l ~character:(c + 6) in
  let labels = List.map (fun (it : Lsp.Types.CompletionItem.t) -> it.label) items in
  Alcotest.(check bool) "offers Counter as an island component" true
    (List.mem "Counter" labels)

(* ------------------------------------------------------------------ *)
(* Cross-file project analysis                                         *)
(* ------------------------------------------------------------------ *)

(* Build a throwaway forge project on disk and return its root. *)
let mk_forge_project (files : (string * string) list) : string =
  let base = Filename.temp_file "march_lsp_xf_" "" in
  Sys.remove base;
  Sys.mkdir base 0o755;
  let write rel content =
    let path = Filename.concat base rel in
    (try Sys.mkdir (Filename.dirname path) 0o755 with _ -> ());
    let oc = open_out path in
    output_string oc content; close_out oc
  in
  write "forge.toml" "[package]\nname=\"xf\"\nversion=\"0.1.0\"\ntype=\"app\"\n[deps]\n";
  List.iter (fun (rel, content) -> write rel content) files;
  base

let test_cross_file_interface_resolves () =
  (* The interface is declared in one file and the `impl` is in a sibling. The
     LSP's per-file analysis must resolve the cross-file interface. Regression:
     the incremental pre-pass (`check_module_with_env`) silently ignored sibling
     interfaces, so this reported "Unknown interface" while whole-program
     `forge build` was clean. *)
  let model_src =
    "mod Model do\n\
    \  type Widget = { n : Int }\n\
    \  impl Summarize(Widget) do\n\
    \    fn summarize(w) do int_to_string(w.n) end\n\
    \  end\n\
    \  fn use_it() : String do summarize({ n: 5 }) end\n\
     end\n"
  in
  (* Interface in lib/, impl in lib/sub/ — cross-subdir is the realistic layout
     (and the case that regressed: the per-file pre-pass dropped the interface). *)
  let root = mk_forge_project [
    "lib/iface.march",
    "mod Iface do\n  interface Summarize(a) do\n    fn summarize: a -> String\n  end\nend\n";
    "lib/sub/model.march", model_src;
  ] in
  let a = An.analyse ~filename:(Filename.concat root "lib/sub/model.march") ~src:model_src in
  let msgs = List.map (fun (d : Lsp.Types.Diagnostic.t) ->
      match d.message with `String s -> s | `MarkupContent m -> m.value) a.An.diagnostics in
  let has_unknown_iface =
    List.exists (fun m -> contains_sub m "Unknown interface") msgs in
  Alcotest.(check bool) "cross-file impl: no 'Unknown interface'" false has_unknown_iface

let test_unknown_interface_still_errors () =
  (* The fix must not suppress a genuinely-undeclared interface. *)
  let model_src =
    "mod Model do\n\
    \  type Q = { n : Int }\n\
    \  impl NoSuchIface(Q) do\n\
    \    fn f(x) do 1 end\n\
    \  end\n\
     end\n"
  in
  let root = mk_forge_project [ "lib/model.march", model_src ] in
  let a = An.analyse ~filename:(Filename.concat root "lib/model.march") ~src:model_src in
  let msgs = List.map (fun (d : Lsp.Types.Diagnostic.t) ->
      match d.message with `String s -> s | `MarkupContent m -> m.value) a.An.diagnostics in
  Alcotest.(check bool) "unknown interface still flagged" true
    (List.exists (fun m -> contains_sub m "Unknown interface") msgs)

(* ------------------------------------------------------------------ *)
(* ~H element folding ranges                                           *)
(* ------------------------------------------------------------------ *)

let test_h_element_folding () =
  (* Source has:
     line 1: mod M do
     line 2:   fn page() : IOList do
     line 3:     ~H"""
     line 4:     <ul>
     line 5:       <li>a</li>
     line 6:     </ul>
     line 7:     """
     line 8:   end
     line 9: end
     The <ul> open-tag name is on line 4; </ul> close-tag name is on line 6.
     After conversion to 0-indexed: expected H-element fold startLine=3, endLine=5.
     collect_fold_ranges (AST-based) produces fn/mod ranges but NOT H-element
     ranges — those come from tag_pairs_in_sigil, which we wire in separately.
     So before the fix, fold_ranges contains no range with startLine=3, endLine=5. *)
  let src = {|mod M do
  fn page() : IOList do
    ~H"""
    <ul>
      <li>a</li>
    </ul>
    """
  end
end|} in
  let a = analyse src in
  (* Verify the specific <ul> fold is present: startLine=3 (0-indexed line 4),
     endLine=5 (0-indexed line 6). *)
  let has_ul_fold = List.exists (fun (sl, el, _kind) ->
      sl = 3 && el = 5) a.An.fold_ranges in
  Alcotest.(check bool) "a multi-line ~H <ul> element fold (startLine=3 endLine=5)" true has_ul_fold

let test_h_element_no_fold_for_single_line () =
  (* A ~H sigil where all tags are on one line should produce no H-element fold
     (the only fold ranges are function/mod regions from the AST). *)
  let src = {|mod M do
  fn page() : IOList do
    ~H"""<li>a</li>"""
  end
end|} in
  let a = analyse src in
  (* No range should have startLine >= 2 AND endLine = startLine from H tags
     because single-line tags span 0 lines delta. We just verify no crash and
     that the function-level fold is still there. *)
  let has_fn_fold = List.exists (fun (sl, el, _kind) -> el > sl) a.An.fold_ranges in
  Alcotest.(check bool) "single-line ~H still has fn fold range" true has_fn_fold

(* ------------------------------------------------------------------ *)
(* Import / capability run folding                                     *)
(* ------------------------------------------------------------------ *)

(** All fold ranges carrying [kind]. *)
let folds_of_kind a kind =
  List.filter (fun (_, _, k) -> k = kind) a.An.fold_ranges

let test_import_run_folds () =
  (* Lines (1-indexed):
       1 mod M do
       2   import A.B
       3   import C.D
       4   import E.F
       5   fn f() ...
     The run spans lines 2-4, so 0-indexed startLine=1, endLine=3. *)
  let src = {|mod M do
  import A.B
  import C.D
  import E.F
  fn f() : Int do
    1
  end
end|} in
  let a = analyse src in
  let ok = List.exists (fun (sl, el, _) -> sl = 1 && el = 3)
      (folds_of_kind a "imports") in
  Alcotest.(check bool) "the three-import run folds as one range" true ok

let test_cap_run_folds () =
  let src = {|mod M do
  needs IO.Network
  needs IO.Clock
  cap no_panic
  fn f() : Int do
    1
  end
end|} in
  let a = analyse src in
  (* Capability runs use "region"; other constructs use it too, so this asks
     for the exact span rather than merely for some region. *)
  let ok = List.exists (fun (sl, el, _) -> sl = 1 && el = 3)
      (folds_of_kind a "region") in
  Alcotest.(check bool) "the three-cap run folds as one range" true ok

let test_runs_do_not_span_other_decls () =
  (* REJECT witness.  An implementation that folded from the first compact
     declaration to the last one anywhere in the module — rather than per
     maximal *consecutive* run — would pass both tests above while collapsing
     the function between the two blocks.  Here the imports are split by a fn,
     so the correct answer is two short runs and NEVER one range covering the
     function. *)
  let src = {|mod M do
  import A.B
  import C.D
  fn f() : Int do
    1
  end
  import E.F
  import G.H
end|} in
  let a = analyse src in
  let imports = folds_of_kind a "imports" in
  (* Two separate runs: lines 2-3 and lines 7-8 (0-indexed 1-2 and 6-7). *)
  Alcotest.(check bool) "first run folds 1-2" true
    (List.exists (fun (sl, el, _) -> sl = 1 && el = 2) imports);
  Alcotest.(check bool) "second run folds 6-7" true
    (List.exists (fun (sl, el, _) -> sl = 6 && el = 7) imports);
  (* And nothing swallows the function that separates them. *)
  List.iter (fun (sl, el, _) ->
      if sl <= 2 && el >= 5 then
        Alcotest.failf "an import fold (%d-%d) spans the intervening fn" sl el)
    imports

let test_lone_import_does_not_fold () =
  (* A single import has nothing to collapse; offering a fold on it puts a
     useless chevron in the gutter. *)
  let src = {|mod M do
  import A.B
  fn f() : Int do
    1
  end
end|} in
  let a = analyse src in
  Alcotest.(check int) "no import fold for a lone import" 0
    (List.length (folds_of_kind a "imports"))

(* ------------------------------------------------------------------ *)
(* ~H auto-close on typing >                                           *)
(* ------------------------------------------------------------------ *)

let test_autoclose_tag () =
  let src = {|mod M do
  fn page() : IOList do
    ~H"<div>"
  end
end|} in
  let a = analyse src in
  (* cursor right after the '>' of <div>; pos_of gives start of "<div>" *)
  let (l, c) = pos_of src "<div>" in
  let after = c + 5 in   (* past "<div>" -> just after '>' *)
  match An.autoclose_tag_at a ~line:l ~character:after with
  | Some te -> Alcotest.(check string) "inserts </div>" "</div>" te.Lsp.Types.TextEdit.newText
  | None -> Alcotest.fail "expected an auto-close edit for <div>"

let test_autoclose_void_tag () =
  let src = {|mod M do
  fn page() : IOList do
    ~H"<br>"
  end
end|} in
  let a = analyse src in
  let (l, c) = pos_of src "<br>" in
  let after = c + 4 in   (* just after '>' of <br> *)
  match An.autoclose_tag_at a ~line:l ~character:after with
  | None -> ()   (* void element: no auto-close *)
  | Some _ -> Alcotest.fail "should not auto-close void element <br>"

(* ------------------------------------------------------------------ *)
(* Bug 1 regression: autoclose_tag_at with ${} interpolation          *)
(* ------------------------------------------------------------------ *)

(* Typing > after a div whose class attribute contains an interpolation
   that contains a string literal with a less-than sign must auto-close
   the outer div, not a span from inside the interpolation.
   Triple-quoted sigil is used so the inner span string is valid March. *)
let test_autoclose_tag_with_interpolation_lt () =
  (* Triple-quoted sigil: class="${"<span>"}" -- the <span> is inside ${},
     not real HTML. The typed > closes the outer <div>. *)
  let src = "mod M do\n  fn page() : IOList do\n    ~H\"\"\"<div class=\"${\"<span>\"}\">\"\"\"  \n  end\nend" in
  let a = analyse src in
  Alcotest.(check bool) "sigil collected" true (a.An.h_sigils <> []);
  (* pos_of finds the closing angle-bracket of the div open-tag;
     advancing by 2 puts the cursor just after the > character. *)
  let (line, col_of_gt) = pos_of src "\">" in
  let character = col_of_gt + 2 in
  (match An.autoclose_tag_at a ~line ~character with
  | Some te ->
    Alcotest.(check string) "autoclose inserts </div> not </span>"
      "</div>" te.Lsp.Types.TextEdit.newText
  | None ->
    Alcotest.fail "expected auto-close edit for outer <div>")

(* ------------------------------------------------------------------ *)
(* Bug 2 regression: dup_attrs false positive with ${} in quoted val  *)
(* ------------------------------------------------------------------ *)

let test_dup_attr_no_false_positive_with_interp_in_quoted_val () =
  let src = {|mod M do
  fn page() : IOList do
    ~H"""<div class="${"format"}" format="x">"""
  end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "sigil collected" true (a.An.h_sigils <> []);
  let flagged = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
    match d.code with
    | Some (`String "html/duplicate-attr") -> true | _ -> false)
    a.An.diagnostics in
  Alcotest.(check bool)
    "interpolation inside quoted value must not cause false dup-attr" false flagged

(* ------------------------------------------------------------------ *)
(* Bug 3 regression: islands_in_sigil with '>' inside attribute value *)
(* ------------------------------------------------------------------ *)

(* An island tag whose data attribute value contains a closing angle bracket:
   name='Counter' must still be found despite the misleading '>' in data-x. *)
let test_island_gt_in_attr_value () =
  let src = {|mod M do
  fn page() : IOList do
    ~H"<island data-x=\">\" name='Counter' />"
  end
end|} in
  let a = An.analyse ~filename:"test.march" ~src in
  let islands = List.concat_map (An.islands_in_sigil ~src) a.An.h_sigils in
  Alcotest.(check int) "one island found despite '>' in attr value" 1
    (List.length islands);
  let isl = List.hd islands in
  Alcotest.(check string) "island name is Counter" "Counter" isl.An.isl_name

(* ------------------------------------------------------------------ *)
(* Nit A regression: ~h (lowercase) must NOT be treated as ~H sigil   *)
(* ------------------------------------------------------------------ *)

let test_lowercase_h_sigil_not_collected () =
  (* ~h"…" with lowercase h must not be collected as an HTML sigil. *)
  let src = {|mod M do
  fn page() : IOList do
    ~h"<div>"
  end
end|} in
  let a = An.analyse ~filename:"test.march" ~src in
  Alcotest.(check int) "lowercase ~h sigil not collected as H sigil" 0
    (List.length a.An.h_sigils)

