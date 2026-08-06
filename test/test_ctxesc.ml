(* Tests for the contextual-escaping table parser (lib/ctxesc).

   The .tbl file at specs/security/html-contexts.tbl is the source of truth for
   ~H's escaping decisions; these tests pin the parser that reads it. See
   specs/security/README.md for the format and
   specs/plans/2026-08-05-contextual-autoescaping.md for the plan. *)

module C = March_ctxesc.Context
module P = March_ctxesc.Tbl_parse
module A = March_ctxesc.Automaton

(* The repo has no `astring`; substring checks use a local helper, matching the
   convention in test_compiler.ml. *)
let contains_sub s sub =
  let n = String.length s and m = String.length sub in
  let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
  m = 0 || go 0

let with_tbl body contents =
  let tmp = Filename.temp_file "ctxesc" ".tbl" in
  let oc = open_out tmp in
  output_string oc contents;
  close_out oc;
  let r = body tmp in
  Sys.remove tmp;
  r

let parse_ok contents =
  with_tbl (fun f -> P.parse_file f) contents |> function
  | Ok t -> t
  | Error e -> Alcotest.failf "expected parse to succeed, got: %s" e

let parse_err contents =
  with_tbl (fun f -> P.parse_file f) contents |> function
  | Ok _ -> Alcotest.fail "expected parse to fail, but it succeeded"
  | Error e -> e

(* ── Basic shape ──────────────────────────────────────────────────────── *)

let test_parses_a_minimal_transition () =
  let t =
    parse_ok
      "# a comment\n\n[transitions]\npcdata,*,*,* | lit:\"<\" |  | tagname,=,=,= |\n"
  in
  Alcotest.(check int) "one row" 1 (List.length t.P.transitions);
  let r = List.hd t.P.transitions in
  Alcotest.(check bool) "literal pattern" true (r.P.pat = P.PLit "<")

let test_parses_classification_sections () =
  let t =
    parse_ok
      "[tags]\nscript | script\n* | normal\n\n\
       [attrs]\non* | script\nhref | url\n* | normal\n\n[transitions]\n"
  in
  Alcotest.(check int) "two tag rules" 2 (List.length t.P.tags);
  Alcotest.(check int) "three attr rules" 3 (List.length t.P.attrs)

(* ── Patterns ─────────────────────────────────────────────────────────── *)

let pat_of src =
  let t = parse_ok ("[transitions]\npcdata,*,*,* | " ^ src ^ " |  | =,=,=,= |\n") in
  (List.hd t.P.transitions).P.pat

let test_pattern_vocabulary () =
  Alcotest.(check bool) "lit"   true (pat_of "lit:\"<!--\"" = P.PLit "<!--");
  Alcotest.(check bool) "ilit"  true (pat_of "ilit:\"</SCRIPT\"" = P.PILit "</script");
  Alcotest.(check bool) "interp" true (pat_of "interp" = P.PInterp);
  Alcotest.(check bool) "any"   true (pat_of "any" = P.PAny);
  Alcotest.(check bool) "name"  true (pat_of "name" = P.PName);
  Alcotest.(check bool) "tag"   true (pat_of "tag" = P.PTag);
  Alcotest.(check bool) "until" true (pat_of "until:\"-->\"" = P.PUntil "-->");
  (match pat_of "cls:[a-c]" with
   | P.PClass cs -> Alcotest.(check (list char)) "cls range" ['a'; 'b'; 'c'] cs
   | _ -> Alcotest.fail "expected PClass");
  (match pat_of "cls+:[ \\t]" with
   | P.PClassPlus cs -> Alcotest.(check (list char)) "cls+ escapes" [' '; '\t'] cs
   | _ -> Alcotest.fail "expected PClassPlus")

(* ── Context patterns ─────────────────────────────────────────────────── *)

let test_wildcard_and_unchanged_contexts () =
  let t =
    parse_ok
      "[transitions]\npcdata,*,*,* | any |  | tagname,=,=,double |\n"
  in
  let r = List.hd t.P.transitions in
  Alcotest.(check bool) "from state is concrete" true
    (r.P.from_pat.P.f_state = Some C.Pcdata);
  Alcotest.(check bool) "from element is wildcard" true
    (r.P.from_pat.P.f_element = None);
  Alcotest.(check bool) "succ state is set" true
    (r.P.succ.P.s_state = Some C.Tagname);
  Alcotest.(check bool) "succ element is unchanged" true
    (r.P.succ.P.s_element = None);
  Alcotest.(check bool) "succ delim is set" true
    (r.P.succ.P.s_delim = Some C.DlDouble)

let test_substitution_and_diagnostic_are_read () =
  let t =
    parse_ok
      "[transitions]\n\
       beforeattrvalue,*,*,* | interp | \"\\\"\" | attrvalue,=,=,doublesubst |\n\
       beforeattrname,*,*,* | interp |  | =,=,=,= | Cannot interpolate an attribute name\n"
  in
  match t.P.transitions with
  | [ subst_row; diag_row ] ->
    Alcotest.(check (option string)) "substitution" (Some "\"") subst_row.P.subst;
    Alcotest.(check (option string)) "no diagnostic" None subst_row.P.diag;
    Alcotest.(check (option string)) "diagnostic"
      (Some "Cannot interpolate an attribute name") diag_row.P.diag
  | _ -> Alcotest.fail "expected exactly two rows"

(* ── Rejection: a typo must never be silently dropped ─────────────────── *)

let test_rejects_unknown_state () =
  let e =
    parse_err "[transitions]\nnotastate,*,*,* | any |  | pcdata,=,=,= |\n"
  in
  Alcotest.(check bool) "names the bad token" true (contains_sub e "notastate");
  Alcotest.(check bool) "names the line" true (contains_sub e "line 2")

let test_rejects_unknown_pattern () =
  let e = parse_err "[transitions]\npcdata,*,*,* | regex:\".*\" |  | =,=,=,= |\n" in
  Alcotest.(check bool) "names the bad pattern" true (contains_sub e "regex")

let test_rejects_unknown_class_name () =
  let e = parse_err "[attrs]\nhref | notaclass\n" in
  Alcotest.(check bool) "names the bad class" true (contains_sub e "notaclass")

let test_rejects_wrong_field_count () =
  let e = parse_err "[transitions]\npcdata,*,*,* | any |  | =,=,=,=\n" in
  Alcotest.(check bool) "explains the arity" true (contains_sub e "5 fields")

let test_rejects_row_outside_a_section () =
  let e = parse_err "pcdata,*,*,* | any |  | =,=,=,= |\n" in
  Alcotest.(check bool) "mentions the section" true (contains_sub e "section")

(* ── The real table must load ─────────────────────────────────────────── *)

let test_shipped_table_parses () =
  (* Runners are invoked both from the repo root (scripts/run-tests.sh) and
     from _build/default/test (dune runtest), so try both. *)
  let candidates =
    [ "specs/security/html-contexts.tbl";
      "../../specs/security/html-contexts.tbl";
      "../../../specs/security/html-contexts.tbl" ] in
  let path =
    match List.find_opt Sys.file_exists candidates with
    | Some p -> p
    | None ->
      Alcotest.failf "shipped table not found (cwd %s; tried %s)" (Sys.getcwd ())
        (String.concat ", " candidates)
  in
  match P.parse_file path with
  | Error e -> Alcotest.failf "shipped table failed to parse: %s" e
  | Ok t ->
    Alcotest.(check bool) "has transitions" true (List.length t.P.transitions > 20);
    Alcotest.(check bool) "has tag rules" true (t.P.tags <> []);
    Alcotest.(check bool) "has attr rules" true (t.P.attrs <> []);
    (* Every state must be reachable as a source, or a row is dead. *)
    let sources =
      List.filter_map (fun r -> r.P.from_pat.P.f_state) t.P.transitions in
    List.iter
      (fun st ->
         Alcotest.(check bool)
           (Printf.sprintf "state %s appears as a source" (C.state_name st))
           true
           (List.mem st sources))
      C.all_states


(* ── The automaton ────────────────────────────────────────────────────────
   These exercise the SHIPPED table, not a fixture: Task 1 only proved the
   table parses, and a table that parses can still be wrong. *)

let table = lazy (
  let candidates =
    [ "specs/security/html-contexts.tbl";
      "../../specs/security/html-contexts.tbl";
      "../../../specs/security/html-contexts.tbl" ] in
  match List.find_opt Sys.file_exists candidates with
  | None -> Alcotest.failf "shipped table not found (cwd %s)" (Sys.getcwd ())
  | Some p ->
    (match P.parse_file p with
     | Ok t -> A.compile t
     | Error e -> Alcotest.failf "shipped table failed to parse: %s" e))

let walk src =
  match A.consume_literal (Lazy.force table) C.initial src with
  | Ok o -> o
  | Error (m, off) -> Alcotest.failf "unexpected error at byte %d: %s" off m

let ctx_after src = (walk src).A.ctx

let esc_after src =
  match A.consume_interp (Lazy.force table) (ctx_after src) with
  | Ok (e, _, _) -> e
  | Error d -> Alcotest.failf "unexpected reject: %s" d

let reject_after src =
  match A.consume_interp (Lazy.force table) (ctx_after src) with
  | Ok _ -> Alcotest.failf "expected a rejection after %S" src
  | Error d -> d

let escaper = Alcotest.testable
    (fun ppf e -> Format.pp_print_string ppf (C.escaper_name e)) ( = )

let test_pcdata_stays_pcdata () =
  Alcotest.(check bool) "plain text" true ((ctx_after "hello world").C.state = C.Pcdata);
  Alcotest.check escaper "html escaper" C.EscHtml (esc_after "<p>")

let test_enters_double_quoted_url_attr () =
  let c = ctx_after "<a href=\"" in
  Alcotest.(check bool) "in attr value" true (c.C.state = C.Attrvalue);
  Alcotest.(check bool) "double delim" true (c.C.delim = C.DlDouble);
  Alcotest.(check bool) "url attr" true (c.C.attr = C.AtUrl)

let test_url_start_vs_mid () =
  (* href="${u}" is the WHOLE url -> scheme allowlist *)
  Alcotest.check escaper "whole-url at start" C.EscUrlWhole (esc_after "<a href=\"");
  (* href="/x?q=${q}" is a component -> percent-encode *)
  Alcotest.check escaper "component mid-value" C.EscUrlComponent
    (esc_after "<a href=\"/search?q=")

let test_script_body_is_js () =
  let c = ctx_after "<script>" in
  Alcotest.(check bool) "script element" true (c.C.element = C.ElScript);
  Alcotest.(check bool) "rcdata" true (c.C.state = C.Rcdata);
  Alcotest.check escaper "js escaper" C.EscJsString (esc_after "<script>var x = ")

let test_style_body_is_css () =
  Alcotest.check escaper "css escaper" C.EscCssDecl (esc_after "<style>a{color:")

let test_textarea_body_is_html () =
  Alcotest.check escaper "html in textarea" C.EscHtml (esc_after "<textarea>")

let test_close_tag_leaves_raw_text () =
  let c = ctx_after "<script>var x = 1;</script>" in
  Alcotest.(check bool) "back to pcdata" true (c.C.state = C.Pcdata);
  Alcotest.(check bool) "element cleared" true (c.C.element = C.ElNormal)

let test_close_tag_is_case_insensitive () =
  let c = ctx_after "<script>x</SCRIPT>" in
  Alcotest.(check bool) "uppercase close still exits" true (c.C.element = C.ElNormal)

let test_unrelated_close_tag_stays_in_script () =
  let c = ctx_after "<script>var s = \"</b>\";" in
  Alcotest.(check bool) "still in script" true (c.C.element = C.ElScript)

let test_event_handler_attr_is_js () =
  Alcotest.check escaper "onclick is js" C.EscJsString (esc_after "<a onclick=\"")

let test_style_attr_is_css () =
  (* A style attribute alternates between two positions and the escapers differ:
     at the start (or after a `;`) a hole is a DECLARATION list; after a `:` it
     is a VALUE. Both shapes occur in forgepm, which is what forced the split --
     an escaper that rejected `var()` and destroyed `a:b;c:d` broke real
     templates. *)
  Alcotest.check escaper "start of style attr is a declaration list"
    C.EscCssDecl (esc_after "<div style=\"");
  Alcotest.check escaper "after a colon is a value"
    C.EscCssValue (esc_after "<div style=\"color:");
  Alcotest.check escaper "after a semicolon is a declaration list again"
    C.EscCssDecl (esc_after "<div style=\"color:red;")

let test_plain_attr_is_attr_escaper () =
  Alcotest.check escaper "class is attr" C.EscAttr (esc_after "<div class=\"")

let test_unquoted_attr_gets_substituted_quote () =
  match A.consume_interp (Lazy.force table) (ctx_after "<div class=") with
  | Error d -> Alcotest.failf "unexpected reject: %s" d
  | Ok (_, subst, c') ->
    Alcotest.(check string) "opening quote substituted" "\"" subst;
    Alcotest.(check bool) "delim marked substituted" true (c'.C.delim = C.DlDoubleSubst)

let test_substituted_quote_is_closed () =
  (* the automaton emits the closing quote the source text never had *)
  let o = walk "<div class=" in
  let after_hole =
    match A.consume_interp (Lazy.force table) o.A.ctx with
    | Ok (_, _, c) -> c
    | Error d -> Alcotest.failf "unexpected reject: %s" d in
  match A.consume_literal (Lazy.force table) after_hole ">x" with
  | Error (m, _) -> Alcotest.failf "unexpected error: %s" m
  | Ok o2 ->
    Alcotest.(check string) "closing quote emitted" "\">x" o2.A.emit

let test_rejected_positions () =
  (* Positions where no escaping can make an interpolation safe. Each must
     reject, and each must say something useful -- a bare "not allowed" would
     leave the author with nowhere to go. *)
  List.iter
    (fun src ->
       let d = reject_after src in
       Alcotest.(check bool)
         (Printf.sprintf "rejection after %S is explained" src) true
         (String.length d > 20))
    [ "<div "; "<"; "<!-- " ]

let test_terminal_validity () =
  Alcotest.(check bool) "balanced template is a valid end state" true
    (A.is_valid_terminal (ctx_after "<p>hello</p>"));
  Alcotest.(check bool) "open tag is not" false
    (A.is_valid_terminal (ctx_after "<div"));
  Alcotest.(check bool) "open attribute is not" false
    (A.is_valid_terminal (ctx_after "<div class=\"x"));
  Alcotest.(check bool) "unclosed script is not" false
    (A.is_valid_terminal (ctx_after "<script>var x = 1;"));
  Alcotest.(check bool) "unclosed comment is not" false
    (A.is_valid_terminal (ctx_after "<!-- hi"))

let test_literal_is_emitted_unchanged_when_no_substitution () =
  let o = walk "<p>hello &amp; goodbye</p>" in
  Alcotest.(check string) "emit is verbatim" "<p>hello &amp; goodbye</p>" o.A.emit

let automaton_tests =
  [ Alcotest.test_case "pcdata" `Quick test_pcdata_stays_pcdata;
    Alcotest.test_case "enters url attr" `Quick test_enters_double_quoted_url_attr;
    Alcotest.test_case "url start vs mid" `Quick test_url_start_vs_mid;
    Alcotest.test_case "script body is js" `Quick test_script_body_is_js;
    Alcotest.test_case "style body is css" `Quick test_style_body_is_css;
    Alcotest.test_case "textarea body is html" `Quick test_textarea_body_is_html;
    Alcotest.test_case "close tag leaves raw text" `Quick test_close_tag_leaves_raw_text;
    Alcotest.test_case "close tag case-insensitive" `Quick test_close_tag_is_case_insensitive;
    Alcotest.test_case "unrelated close tag stays" `Quick test_unrelated_close_tag_stays_in_script;
    Alcotest.test_case "event handler attr is js" `Quick test_event_handler_attr_is_js;
    Alcotest.test_case "style attr is css" `Quick test_style_attr_is_css;
    Alcotest.test_case "plain attr" `Quick test_plain_attr_is_attr_escaper;
    Alcotest.test_case "unquoted attr substitution" `Quick test_unquoted_attr_gets_substituted_quote;
    Alcotest.test_case "substituted quote closed" `Quick test_substituted_quote_is_closed;
    Alcotest.test_case "rejected positions" `Quick test_rejected_positions;
    Alcotest.test_case "terminal validity" `Quick test_terminal_validity;
    Alcotest.test_case "literal emitted verbatim" `Quick test_literal_is_emitted_unchanged_when_no_substitution ]

let tests =
  [ ("ctxesc table parser",
     [ Alcotest.test_case "minimal transition" `Quick test_parses_a_minimal_transition;
       Alcotest.test_case "tags/attrs sections" `Quick test_parses_classification_sections;
       Alcotest.test_case "pattern vocabulary" `Quick test_pattern_vocabulary;
       Alcotest.test_case "wildcard and unchanged" `Quick test_wildcard_and_unchanged_contexts;
       Alcotest.test_case "substitution + diagnostic" `Quick test_substitution_and_diagnostic_are_read;
       Alcotest.test_case "rejects unknown state" `Quick test_rejects_unknown_state;
       Alcotest.test_case "rejects unknown pattern" `Quick test_rejects_unknown_pattern;
       Alcotest.test_case "rejects unknown class" `Quick test_rejects_unknown_class_name;
       Alcotest.test_case "rejects wrong field count" `Quick test_rejects_wrong_field_count;
       Alcotest.test_case "rejects row outside section" `Quick test_rejects_row_outside_a_section;
       Alcotest.test_case "shipped table parses" `Quick test_shipped_table_parses ]);
    ("ctxesc automaton", automaton_tests) ]
