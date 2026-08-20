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

(* A <script> body has TWO positions and they take different escapers.
   This test used to assert `<script>var x = ` -> EscJsString, which is the
   2026-08-20 vulnerability written down as an expectation: the JS STRING
   escaper only makes a value unable to END a string literal, and at an
   expression position there is no literal to end -- so
   `alert(document.cookie)`, which contains not one character that escaper
   touches, rendered as live code. The corpus at the bottom of this file
   asserts what actually comes out. *)
let test_script_body_is_js () =
  let c = ctx_after "<script>" in
  Alcotest.(check bool) "script element" true (c.C.element = C.ElScript);
  Alcotest.(check bool) "rcdata" true (c.C.state = C.Rcdata);
  Alcotest.check escaper "expression position is NOT the string escaper"
    C.EscJsExpr (esc_after "<script>var x = ");
  Alcotest.check escaper "inside a double-quoted JS string"
    C.EscJsString (esc_after "<script>var x = \"");
  Alcotest.check escaper "inside a single-quoted JS string"
    C.EscJsString (esc_after "<script>var x = 'a");
  (* ...and the walk comes back out of the literal again. *)
  Alcotest.check escaper "after the string closes, expression position again"
    C.EscJsExpr (esc_after "<script>var x = \"s\"; var y = ")

(* The JS position tracker exists to keep ONE invariant: the walk must never
   land inside a string literal when the hole is really in open code. Every
   construct below can carry a stray quote, and each would otherwise leave the
   quote count off by one and hand the next hole the string escaper -- the
   exact shape of the original bug, reached by a different route. *)
let test_stray_quotes_do_not_desynchronise_the_js_tracker () =
  let expr what src =
    Alcotest.check escaper what C.EscJsExpr (esc_after src) in
  expr "an apostrophe in a line comment"
    "<script>// don't do this\nvar x = ";
  expr "an apostrophe in a block comment"
    "<script>/* don't do this */ var x = ";
  expr "a quote inside a regex literal"
    "<script>var r = /'/; var x = ";
  expr "an apostrophe inside a template literal"
    "<script>var s = `it's here`; var x = ";
  expr "a quote inside a comment in an event handler"
    "<a onclick=\"// don't\nn = ";
  (* An escaped quote does not close the literal it sits in, so the hole after
     it is still a string position and not expression position. *)
  Alcotest.check escaper "an escaped quote does not end the string"
    C.EscJsString (esc_after "<script>var x = \"a\\\"b")

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
  (* Same two positions as a script body. The JS string delimiter is implied by
     the HTML one: inside a double-quoted attribute a raw double quote ends the
     ATTRIBUTE, so the only JS string it can hold is a single-quoted one. *)
  Alcotest.check escaper "onclick at expression position"
    C.EscJsExpr (esc_after "<a onclick=\"");
  Alcotest.check escaper "onclick inside a JS string"
    C.EscJsString (esc_after "<a onclick=\"f('");
  Alcotest.check escaper "onclick back at expression position"
    C.EscJsExpr (esc_after "<a onclick=\"f('x'); g(")

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
     leave the author with nowhere to go.

     The last six landed with the 2026-08-20 fix. Rejecting is the honest
     answer wherever an escaper would have to guarantee something it cannot:
     `srcdoc` is HTML-decoded and then parsed as a document, so attribute
     escaping is undone before the markup is read; `srcset` is a candidate
     LIST, so a single-URL scheme check validates only the first entry; and the
     three JS sub-positions each contain a character no escaper here escapes
     (`/` ends a regex, a backtick ends a template literal and `${` opens a
     substitution, and a comment hides the value until it stops being a
     comment). The single-quoted handler is different again -- the escaper
     WOULD be safe, but its own delimiters would end the attribute. *)
  List.iter
    (fun src ->
       let d = reject_after src in
       Alcotest.(check bool)
         (Printf.sprintf "rejection after %S is explained" src) true
         (String.length d > 20))
    [ "<div "; "<"; "<!-- ";
      "<iframe srcdoc=\"";
      "<img srcset=\"";
      "<script>// note ";
      "<script>/* note ";
      "<script>var r = /";
      "<script>var s = `";
      "<a onclick='n = " ]

(* Each rejection must name the construct it is refusing, not merely refuse.
   A message that says only "not allowed here" leaves the author guessing which
   of the several JS positions they are in. *)
let test_rejections_name_the_construct () =
  List.iter
    (fun (src, needle) ->
       let d = reject_after src in
       Alcotest.(check bool)
         (Printf.sprintf "rejection after %S mentions %S (got: %s)" src needle d)
         true (contains_sub (String.lowercase_ascii d) needle))
    [ "<iframe srcdoc=\"",  "srcdoc";
      "<img srcset=\"",     "srcset";
      "<script>// note ",   "comment";
      "<script>var r = /",  "regular-expression";
      "<script>var s = `",  "template literal";
      "<a onclick='n = ",   "single-quoted" ]

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

(* ── Rendered-output attack corpus ────────────────────────────────────────
   THE COVERAGE CLASS THIS FILE WAS MISSING, and the reason the 2026-08-20
   `~H` vulnerability shipped past a green suite.

   Everything above asserts which escaper gets CHOSEN. The leaf escapers are
   separately and adversarially tested in test/test_ctx_escape.c (~100 checks
   with real payloads). Both layers were green while
   `<script>var x = ${p}</script>` rendered `alert(document.cookie)` as live
   code, because nothing anywhere put an attack string through a template and
   looked at what came out: the escaper WAS the one the table named, and it DID
   escape exactly what it promised to. The defect was the pairing.

   So these tests render. `render` is the desugar's loop
   (lib/desugar/desugar.ml, the third pass) reduced to one hole: walk the
   literal before it, take the escaper the context implies, apply it, walk the
   literal after. What it returns is what a browser would receive. *)

module E = March_ctxesc.Escape

type rendered = {
  out : string;         (** the whole template as a browser would see it *)
  hole : string;        (** just the escaped value *)
  at : C.t;             (** the context the hole sits in *)
  esc : C.escaper;      (** the escaper the context chose for it *)
}

let render ~before ~after value =
  let tbl = Lazy.force table in
  match A.consume_literal tbl C.initial before with
  | Error (m, off) ->
    Alcotest.failf "prefix %S failed to walk at byte %d: %s" before off m
  | Ok pre ->
    (match A.consume_interp tbl pre.A.ctx with
     | Error d -> Alcotest.failf "template %S${}%S was rejected: %s" before after d
     | Ok (esc, subst, ctx') ->
       let hole = E.apply esc value in
       (match A.consume_literal tbl ctx' after with
        | Error (m, _) -> Alcotest.failf "suffix %S failed to walk: %s" after m
        | Ok post ->
          { out = pre.A.emit ^ subst ^ hole ^ post.A.emit; hole; at = ctx'; esc }))

(* Payloads. The first block is the probe from the P0 report; the rest are the
   styles already proven against the leaf escapers in test_ctx_escape.c, moved
   up a layer so they are exercised through a template rather than against an
   escaper chosen by hand. *)
let attack_payloads =
  [ "alert(document.cookie)";
    "javascript:alert(1)";
    "JaVaScRiPt:alert(1)";
    "java\tscript:alert(1)";
    "\001javascript:alert(1)";
    "  javascript:alert(1)";
    "data:text/html,<script>alert(1)</script>";
    "</script><script>alert(1)</script>";
    "<img src=x onerror=alert(1)>";
    "\" onerror=\"alert(1)";
    "' onerror='alert(1)";
    "` onerror=alert(1) `";
    "\xe2\x80\xa8alert(1)";                     (* U+2028: a JS line break *)
    "\xe2\x80\xa9alert(1)";                     (* U+2029 *)
    "');alert(1);//";
    "\");alert(1);//";
    "-->" ]

(* Every position a hole is ALLOWED in, one per escaper and per sub-position.
   Adding a context here immediately subjects it to every payload above. *)
let accepting_contexts =
  [ "element content",       "<div>",                          "</div>";
    "textarea body",         "<textarea>",                     "</textarea>";
    "title body",            "<title>",                        "</title>";
    "plain attribute",       "<div class=\"",                  "\">x</div>";
    "single-quoted attr",    "<div class='",                   "'>x</div>";
    "unquoted attribute",    "<div class=",                    ">x</div>";
    "start of href",         "<a href=\"",                     "\">x</a>";
    "mid href",              "<a href=\"/s?q=",                "\">x</a>";
    "xlink:href",            "<a xlink:href=\"",               "\">x</a>";
    "object data",           "<object data=\"",                "\"></object>";
    "ping",                  "<a ping=\"",                     "\">x</a>";
    "manifest",              "<html manifest=\"",              "\"></html>";
    "longdesc",              "<img longdesc=\"",               "\">x";
    "style declaration",     "<div style=\"",                  "\">x</div>";
    "style value",           "<div style=\"color:",            "\">x</div>";
    "css url()",             "<div style=\"background:url(",   ")\">x</div>";
    "style body",            "<style>a{color:",                "}</style>";
    "script expression",     "<script>var x = ",               ";</script>";
    "script JS string",      "<script>var x = \"",             "\";</script>";
    "handler expression",    "<button onclick=\"n = ",         "\">x</button>";
    "handler JS string",     "<button onclick=\"f('",          "')\">x</button>" ]

(* INVARIANT 1 -- no escaped value ever emits a byte that could open a tag or
   close an attribute. This holds for EVERY escaper without exception, which is
   what makes it worth asserting as one sweep: `<`/`>` are entity-encoded,
   percent-encoded, hex-escaped or \u-escaped depending on the language, and
   the quote characters likewise. The JS-expression escaper is the one that
   contributes raw quotes, and only its own two delimiters (invariant 4). *)
let test_no_payload_emits_structural_bytes () =
  List.iter
    (fun (name, before, after) ->
       List.iter
         (fun payload ->
            let r = render ~before ~after payload in
            let bad c what =
              if String.contains r.hole c then
                Alcotest.failf
                  "%s: payload %S emitted a raw %s\n  hole: %s\n  full: %s"
                  name payload what r.hole r.out
            in
            bad '<' "left angle bracket";
            bad '>' "right angle bracket";
            bad '"' "double quote";
            (* The JS-expression escaper supplies its own single quotes -- that
               is the whole mechanism, and invariant 4 checks it separately.
               Every other escaper must emit none at all. *)
            if r.esc <> C.EscJsExpr then bad '\'' "single quote")
         attack_payloads)
    accepting_contexts

(* INVARIANT 2 -- the paper's soundness property, checked on real output: an
   interpolated value cannot move the parser out of the context the compiler
   proved it was in. Re-walk the ESCAPED value from the context the automaton
   predicted and require the state, element and delimiter to come back
   unchanged. (The `attr` sub-position may legitimately advance -- `url` demotes
   to `urlmid` after a literal byte, a CSS `:` moves declaration to value
   position -- that is the automaton's own bookkeeping, not an escape.) *)
let test_no_payload_moves_the_parser () =
  List.iter
    (fun (name, before, after) ->
       List.iter
         (fun payload ->
            let r = render ~before ~after payload in
            (* `doublesubst` means "unquoted in the SOURCE, and the automaton
               has already emitted a quote". The hole below is output, not
               source, so it sits in a genuinely double-quoted attribute and
               must be re-walked as one -- otherwise a tab in the value looks
               like the end of an unquoted attribute that no longer exists. *)
            let start =
              if r.at.C.delim = C.DlDoubleSubst then
                { r.at with C.delim = C.DlDouble }
              else r.at in
            match A.consume_literal (Lazy.force table) start r.hole with
            | Error (m, _) ->
              Alcotest.failf "%s: escaped payload %S does not re-parse: %s"
                name payload m
            | Ok o ->
              let same field a b =
                if a <> b then
                  Alcotest.failf
                    "%s: payload %S changed the %s of its context\n  hole: %s"
                    name payload field r.hole
              in
              same "state" o.A.ctx.C.state start.C.state;
              same "element" o.A.ctx.C.element start.C.element;
              same "delimiter" o.A.ctx.C.delim start.C.delim)
         attack_payloads)
    accepting_contexts

(* INVARIANT 3 -- the rendered document is still well-formed. A payload that
   left the template ending mid-tag would splice into whatever the caller
   concatenates next, which is the composition hazard the terminal check
   exists to stop. *)
let test_rendered_output_is_still_well_formed () =
  List.iter
    (fun (name, before, after) ->
       List.iter
         (fun payload ->
            let r = render ~before ~after payload in
            match A.consume_literal (Lazy.force table) C.initial r.out with
            | Error (m, _) ->
              Alcotest.failf "%s: rendered output does not re-parse: %s\n  %s"
                name m r.out
            | Ok o ->
              if not (A.is_valid_terminal o.A.ctx) then
                Alcotest.failf
                  "%s: payload %S left the document in a bad terminal state \
                   (%s)\n  %s"
                  name payload (C.describe o.A.ctx) r.out)
         attack_payloads)
    accepting_contexts

(* INVARIANT 4 -- a hole at a JS EXPRESSION position is rendered as exactly one
   string literal, so it is data and not code. This is the assertion that
   fails against the pre-fix tree: the old escaper returned the payload with
   no delimiters at all, so `alert(document.cookie)` was an expression. *)
let test_js_expression_holes_are_inert_literals () =
  let js_expr_contexts =
    [ "script expression",  "<script>var x = ",       ";</script>";
      "handler expression", "<button onclick=\"n = ", "\">x</button>";
      "unquoted handler",   "<button onclick=",       ">x</button>" ] in
  List.iter
    (fun (name, before, after) ->
       List.iter
         (fun payload ->
            let r = render ~before ~after payload in
            let n = String.length r.hole in
            if n < 2 || r.hole.[0] <> '\'' || r.hole.[n - 1] <> '\'' then
              Alcotest.failf
                "%s: payload %S was not wrapped in a JS string literal\n  %s"
                name payload r.hole;
            (* ...and nothing inside it can end that literal. *)
            let body = String.sub r.hole 1 (n - 2) in
            if String.contains body '\'' then
              Alcotest.failf
                "%s: payload %S left a raw quote inside the literal\n  %s"
                name payload r.hole)
         attack_payloads)
    js_expr_contexts

(* The rows of the P0 report, asserted as exact output. Every one of these was
   a different string before the fix; four of them executed. Exact expectations
   rather than "does not contain" because the useful review artifact is the
   diff -- a regression in either direction shows up as a readable change. *)
let test_reported_rows_render_as_expected () =
  let row what ~before ~after value want =
    let r = render ~before ~after value in
    Alcotest.(check string) what want r.out
  in
  (* 1. was: <script>var x = alert(document.cookie);</script>  -- EXECUTED *)
  row "script expression is a string, not a call"
    ~before:"<script>var x = " ~after:";</script>" "alert(document.cookie)"
    "<script>var x = 'alert(document.cookie)';</script>";
  (* 2. was: onclick="n = alert(document.cookie)"  -- EXECUTED *)
  row "event handler is a string, not a call"
    ~before:"<button onclick=\"n = " ~after:"\">x</button>"
    "alert(document.cookie)"
    "<button onclick=\"n = 'alert(document.cookie)'\">x</button>";
  (* 3. unchanged by the fix, and must stay that way. *)
  row "a hole inside a JS string is still just escaped"
    ~before:"<script>var x = \"" ~after:"\";</script>" "hello"
    "<script>var x = \"hello\";</script>";
  (* 4. unchanged by the fix. *)
  row "href keeps the scheme allowlist"
    ~before:"<a href=\"" ~after:"\">x</a>" "javascript:alert(1)"
    "<a href=\"about:invalid#zSoyz\">x</a>";
  (* 5-7. were: passed through verbatim -- xlink:href and data EXECUTED. *)
  row "xlink:href is a URL attribute"
    ~before:"<a xlink:href=\"" ~after:"\">x</a>" "javascript:alert(1)"
    "<a xlink:href=\"about:invalid#zSoyz\">x</a>";
  row "object data is a URL attribute"
    ~before:"<object data=\"" ~after:"\"></object>" "javascript:alert(1)"
    "<object data=\"about:invalid#zSoyz\"></object>";
  row "ping is a URL attribute"
    ~before:"<a ping=\"" ~after:"\">x</a>" "javascript:alert(1)"
    "<a ping=\"about:invalid#zSoyz\">x</a>";
  (* `data` must be an EXACT match: data-* attributes are not URLs and must
     keep the ordinary attribute escaper. *)
  row "data-* is not a URL attribute"
    ~before:"<div data-x=\"" ~after:"\">y</div>" "javascript:alert(1)"
    "<div data-x=\"javascript:alert(1)\">y</div>";
  (* 9. unchanged by the fix. *)
  row "element content is entity-encoded"
    ~before:"<div>" ~after:"</div>" "<img src=x onerror=alert(1)>"
    "<div>&lt;img src=x onerror=alert(1)&gt;</div>";
  (* 10. the honest-input direction of the same defect: this used to render
     `var y = 1 < 2 ...`, a JS syntax error. It is a string now -- not
     arithmetic, but valid JS carrying the text the author wrote. *)
  row "honest arithmetic renders as valid JS"
    ~before:"<script>var y = " ~after:";</script>" "1 < 2 && 3 > 2"
    "<script>var y = '1 \\u003c 2 \\u0026\\u0026 3 \\u003e 2';</script>"

(* The eight rows of the report that must not compile at all. *)
let test_reported_rows_that_must_not_compile () =
  List.iter
    (fun (what, before) ->
       ignore (reject_after before);
       Alcotest.(check bool) what true true)
    [ "srcdoc is rejected rather than entity-escaped", "<iframe srcdoc=\"";
      "srcset is rejected rather than half-validated", "<img srcset=\"" ]

let corpus_tests =
  [ Alcotest.test_case "no payload emits structural bytes" `Quick
      test_no_payload_emits_structural_bytes;
    Alcotest.test_case "no payload moves the parser" `Quick
      test_no_payload_moves_the_parser;
    Alcotest.test_case "rendered output stays well-formed" `Quick
      test_rendered_output_is_still_well_formed;
    Alcotest.test_case "js expression holes are inert literals" `Quick
      test_js_expression_holes_are_inert_literals;
    Alcotest.test_case "reported rows render as expected" `Quick
      test_reported_rows_render_as_expected;
    Alcotest.test_case "reported rows that must not compile" `Quick
      test_reported_rows_that_must_not_compile ]

let automaton_tests =
  [ Alcotest.test_case "pcdata" `Quick test_pcdata_stays_pcdata;
    Alcotest.test_case "enters url attr" `Quick test_enters_double_quoted_url_attr;
    Alcotest.test_case "url start vs mid" `Quick test_url_start_vs_mid;
    Alcotest.test_case "script body is js" `Quick test_script_body_is_js;
    Alcotest.test_case "stray quotes do not desync the js tracker" `Quick
      test_stray_quotes_do_not_desynchronise_the_js_tracker;
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
    Alcotest.test_case "rejections name the construct" `Quick
      test_rejections_name_the_construct;
    Alcotest.test_case "terminal validity" `Quick test_terminal_validity;
    Alcotest.test_case "literal emitted verbatim" `Quick test_literal_is_emitted_unchanged_when_no_substitution ]

(* ── Attribute classification agrees with the shipped table ───────────────
   stdlib/html.march carries a SECOND copy of the [attrs] rules, because
   Html.tag classifies attribute names at runtime and stdlib is loaded from a
   directory (a generated _build artifact would not be on the shipped path).
   This test is what keeps the copy honest: it pins what the .tbl classifies
   these names as, so editing the table without editing html.march fails here.

   Duplication caught by a test rather than prevented by construction is a
   compromise, and it is only acceptable because Html.tag is deprecated in
   favour of ~H, which needs no runtime classification at all. *)

let test_attr_classification_matches_html_march () =
  let t =
    let candidates =
      [ "specs/security/html-contexts.tbl";
        "../../specs/security/html-contexts.tbl";
        "../../../specs/security/html-contexts.tbl" ] in
    match List.find_opt Sys.file_exists candidates with
    | None -> Alcotest.failf "shipped table not found (cwd %s)" (Sys.getcwd ())
    | Some p ->
      (match P.parse_file p with
       | Ok t -> t
       | Error e -> Alcotest.failf "shipped table failed to parse: %s" e)
  in
  let cls name = P.classify t.P.attrs name in
  let check name expected =
    Alcotest.(check (option string))
      (Printf.sprintf "attr %S classifies as %s" name expected)
      (Some expected) (cls name)
  in
  (* Every url attribute listed in Html.url_attr_names(). The second row
     arrived with the 2026-08-20 fix; each was falling through to `normal`,
     which passes `javascript:` untouched. *)
  List.iter (fun n -> check n "url")
    [ "href"; "src"; "action"; "formaction"; "poster"; "cite"; "background";
      "xlink:href"; "data"; "ping"; "manifest"; "longdesc" ];
  check "style" "style";
  (* Rejected outright -- Html.refused_attr_names(). *)
  List.iter (fun n -> check n "srcset") [ "srcset" ];
  List.iter (fun n -> check n "htmldoc") [ "srcdoc" ];
  (* Event handlers -- Html.tag refuses these outright rather than escaping. *)
  List.iter (fun n -> check n "script") [ "onerror"; "onclick"; "onload"; "on" ];
  (* Everything else falls through to normal. `data` is matched EXACTLY, so the
     whole `data-*` family must NOT be swept into the URL class with it -- a
     `data*` glob there would have changed the escaper on every data attribute
     in every template. *)
  List.iter (fun n -> check n "normal")
    [ "class"; "id"; "data-id"; "data-url"; "datalist"; "title"; "alt";
      "width" ];
  (* Case-insensitivity: HTML attribute names are, and so is the classifier. *)
  check "HREF" "url";
  check "OnClick" "script"

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
    ("ctxesc automaton", automaton_tests);
    ("ctxesc rendered-output attack corpus", corpus_tests);
    ("ctxesc attr classification",
     [ Alcotest.test_case "html.march copy matches the shipped table" `Quick
         test_attr_classification_matches_html_march ]) ]
