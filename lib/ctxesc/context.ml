(** Parse contexts for contextual auto-escaping.

    A [t] summarises everything the HTML parser knows at a template hole. Per
    Samuel et al. (arXiv:2605.16561v1), the context ALONE decides which escaper
    an interpolation gets — the interpolated value never influences it. That is
    what lets the whole walk be constant-folded at compile time.

    The declarative table these names come from is
    [specs/security/html-contexts.tbl]; the format is documented in
    [specs/security/README.md]. *)

type state =
  | Pcdata           (** element content *)
  | Rcdata           (** inside script/style/textarea/title, where the body is not HTML *)
  | Tagname          (** reading an opening tag's name *)
  | Closetagname     (** reading a closing tag's name *)
  | Beforeattrname   (** inside a tag, between attributes *)
  | Afterattrname    (** attribute name read, before `=` or the next attribute *)
  | Beforeattrvalue  (** after `=`, before the value's opening delimiter *)
  | Attrvalue        (** inside an attribute value *)
  | Comment          (** inside `<!-- ... -->` *)

type element = ElNormal | ElScript | ElStyle | ElTextarea | ElTitle

type attr =
  | AtNormal
  | AtUrl
      (** a URL attribute value, at the START of the value — an interpolation
          here is the whole URL, so it needs a scheme allowlist *)
  | AtUrlMid
      (** a URL attribute value with literal content already before the hole —
          the interpolation is a component, so it needs percent-encoding *)
  | AtStyle
      (** a `style` attribute at a DECLARATION position — the start of the
          value, or just after a `;`. A hole here is a declaration list
          (`color:red;background:blue`), so `:` and `;` are structural. *)
  | AtStyleValue
      (** a `style` attribute at a VALUE position — after a `:`. A hole here is
          a single value (`#fff`, `var(--x)`), so `:` and `;` are NOT allowed:
          either would let the value start a new declaration. *)
  | AtCssUrl
      (** inside a CSS `url(...)`, whether in a `style` attribute or a `<style>`
          body. A hole here is a URL, not a CSS value: escaping it as CSS
          mangles the slashes and breaks the reference, while escaping it as a
          plain URL would not stop it closing the `url(`. This is the one place
          the paper's subsidiary automata genuinely earn their keep — see
          [EscCssUrl]. *)
  | AtScript
      (** JS at an EXPRESSION position — a `<script>` body outside any string
          literal, or an `on*` handler attribute at the same. A hole here is a
          whole JS expression, NOT a string body: see [EscJsExpr]. *)
  | AtJsString
      (** JS inside a quote-delimited string literal (`'…'` or `"…"`). This is
          the ONLY JS position [EscJsString] is correct for, and until
          2026-08-20 it was not distinguished from [AtScript] at all — every
          script context got [EscJsString], so `<script>var x = ${p}</script>`
          rendered `p` as bare code. See
          specs/progress/2026-08-20-h-sigil-js-and-url-attr-xss.md. *)
  | AtJsComment
      (** inside a `//` or `/* */` JS comment. A hole here is always a mistake,
          exactly as in an HTML comment, so the table rejects it. Tracking
          comments is not a nicety: an apostrophe in one (`// don't`) would
          otherwise desynchronise the string tracker and make the NEXT hole
          look like it sat inside a string literal. *)
  | AtJsRegex
      (** inside a JS regular-expression literal. Rejected: a hole cannot be
          escaped safely here (an unescaped `/` ends the literal and everything
          after it is code), and `/` is also where the table gives up on telling
          a regex apart from division — which is why this class is entered by
          ANY `/` in expression position. Misreading division as a regex costs a
          compile error; misreading a regex as division would cost a quote
          desynchronisation, so the bias is deliberate. *)
  | AtJsTemplate
      (** inside a backtick-delimited JS template literal. Rejected: neither
          the backtick nor `${` is escaped by [EscJsString], so a hole could
          close the literal or open a substitution — and a substitution is
          arbitrary code. *)
  | AtSrcset
      (** an `srcset` attribute value. Rejected: the value is a comma-separated
          list of candidates, so the whole-URL escaper's contract ("this hole
          IS the URL") does not hold — it would validate the first candidate's
          scheme and wave the rest through. *)
  | AtHtmlDoc
      (** an `srcdoc` attribute value. Rejected: the browser HTML-DECODES the
          attribute and then parses the result as a whole document, so entity
          escaping — correct for every other attribute — is undone before the
          markup is parsed and `&lt;img onerror=…&gt;` fires. *)

type delim =
  | DlNone
  | DlSingle
  | DlDouble
  | DlUnquoted
  | DlDoubleSubst
  (** An unquoted attribute value that the automaton quoted ITSELF, so a hole
      could be placed in it safely. The paper's epsilon-transition-with-
      substitution (§4.6): rather than escape a value into a context where a
      space ends the attribute, add the delimiter and remember to close it. *)

type t = { state : state; element : element; attr : attr; delim : delim }

let initial = { state = Pcdata; element = ElNormal; attr = AtNormal; delim = DlNone }

(* ── Names, shared with the .tbl parser and the generated tables ───────── *)

let all_states =
  [ Pcdata; Rcdata; Tagname; Closetagname; Beforeattrname; Afterattrname;
    Beforeattrvalue; Attrvalue; Comment ]

let all_elements = [ ElNormal; ElScript; ElStyle; ElTextarea; ElTitle ]
let all_attrs =
  [ AtNormal; AtUrl; AtUrlMid; AtStyle; AtStyleValue; AtCssUrl; AtScript;
    AtJsString; AtJsComment; AtJsRegex; AtJsTemplate; AtSrcset; AtHtmlDoc ]
let all_delims = [ DlNone; DlSingle; DlDouble; DlUnquoted; DlDoubleSubst ]

let state_name = function
  | Pcdata -> "pcdata"
  | Rcdata -> "rcdata"
  | Tagname -> "tagname"
  | Closetagname -> "closetagname"
  | Beforeattrname -> "beforeattrname"
  | Afterattrname -> "afterattrname"
  | Beforeattrvalue -> "beforeattrvalue"
  | Attrvalue -> "attrvalue"
  | Comment -> "comment"

let element_name = function
  | ElNormal -> "normal"
  | ElScript -> "script"
  | ElStyle -> "style"
  | ElTextarea -> "textarea"
  | ElTitle -> "title"

let attr_name = function
  | AtNormal -> "normal"
  | AtUrl -> "url"
  | AtUrlMid -> "urlmid"
  | AtStyle -> "style"
  | AtStyleValue -> "stylevalue"
  | AtCssUrl -> "cssurl"
  | AtScript -> "script"
  | AtJsString -> "jsstring"
  | AtJsComment -> "jscomment"
  | AtJsRegex -> "jsregex"
  | AtJsTemplate -> "jstemplate"
  | AtSrcset -> "srcset"
  | AtHtmlDoc -> "htmldoc"

let delim_name = function
  | DlNone -> "none"
  | DlSingle -> "single"
  | DlDouble -> "double"
  | DlUnquoted -> "unquoted"
  | DlDoubleSubst -> "doublesubst"

let lookup names_of name_of s =
  List.find_opt (fun v -> name_of v = s) names_of

let state_of_string = lookup all_states state_name
let element_of_string = lookup all_elements element_name
let attr_of_string = lookup all_attrs attr_name
let delim_of_string = lookup all_delims delim_name

let describe c =
  (* The JS sub-positions are named explicitly rather than folded into "inside
     a <script> element's body", because the whole point of the 2026-08-20 fix
     is that those positions are NOT interchangeable — a diagnostic that says
     only "in a script body" would leave the author unable to tell why the same
     hole is fine two characters to the left. *)
  match c.state, c.attr, c.delim with
  | Pcdata, _, _ -> "in element content"
  | Rcdata, AtJsString, _ -> "inside a JS string literal in a <script> body"
  | Rcdata, AtJsComment, _ -> "inside a JS comment in a <script> body"
  | Rcdata, AtJsRegex, _ ->
    "inside a JS regular-expression literal in a <script> body"
  | Rcdata, AtJsTemplate, _ ->
    "inside a JS template literal in a <script> body"
  | Rcdata, _, _ when c.element = ElScript ->
    "at a JS expression position in a <script> body"
  | Rcdata, _, _ ->
    Printf.sprintf "inside a <%s> element's body" (element_name c.element)
  | Tagname, _, _ | Closetagname, _, _ -> "in an element name"
  | Beforeattrname, _, _ -> "where an attribute name is expected"
  | Afterattrname, _, _ -> "just after an attribute name"
  | Beforeattrvalue, _, _ -> "just before an attribute value"
  | Attrvalue, AtUrl, _ -> "at the start of a URL attribute value"
  | Attrvalue, AtUrlMid, _ -> "inside a URL attribute value"
  | Attrvalue, AtStyle, _ -> "at a declaration position in a style attribute"
  | Attrvalue, AtStyleValue, _ -> "at a value position in a style attribute"
  | Attrvalue, AtCssUrl, _ -> "inside a CSS url() in a style attribute"
  | Attrvalue, AtScript, _ ->
    "at a JS expression position in an event-handler attribute"
  | Attrvalue, AtJsString, _ ->
    "inside a JS string literal in an event-handler attribute"
  | Attrvalue, AtJsComment, _ ->
    "inside a JS comment in an event-handler attribute"
  | Attrvalue, AtJsRegex, _ ->
    "inside a JS regular-expression literal in an event-handler attribute"
  | Attrvalue, AtJsTemplate, _ ->
    "inside a JS template literal in an event-handler attribute"
  | Attrvalue, AtSrcset, _ -> "in a `srcset` attribute value"
  | Attrvalue, AtHtmlDoc, _ -> "in a `srcdoc` attribute value"
  | Attrvalue, _, DlUnquoted -> "in an unquoted attribute value"
  | Attrvalue, _, _ -> "in an attribute value"
  | Comment, _, _ -> "inside an HTML comment"

(* ── Escapers ─────────────────────────────────────────────────────────────
   The escaper ids are shared verbatim with the C runtime's MARCH_ESC_*
   defines. They are NOT covered by the generated-table drift check, so a
   conformance assertion lives alongside the C escaper tests. *)

type escaper =
  | EscHtml
  | EscAttr
  | EscUrlComponent
  | EscUrlWhole
  | EscCssValue
      (** a single CSS value: identifiers, numbers, colours, and calls to an
          allowlisted set of functions (`var`, `rgb`, `calc`, ...) *)
  | EscJsString
      (** a hole INSIDE a JS string literal — the delimiters come from the
          template, this escaper only makes the body unable to end it. Correct
          ONLY at [AtJsString]; using it at [AtScript] is what made
          `<script>var x = ${p}</script>` execute `p`. *)
  | EscNone
  | EscCssDecl
      (** a CSS declaration LIST: as EscCssValue, plus `:` and `;` so a hole can
          carry `color:red;background:blue`. Appended rather than inserted so
          the existing ids stay stable -- they are shared verbatim with the C
          runtime's MARCH_ESC_* defines. *)
  | EscCssUrl
      (** a URL inside a CSS `url(...)`. Must be safe in the INTERSECTION of
          three languages at once: a URL (so the scheme allowlist applies), a
          CSS url-token (so it must not close the paren or the quoting), and —
          when the CSS is in a `style` attribute — an HTML attribute value.
          Neither the CSS nor the URL escaper alone is right: CSS escaping
          mangles the slashes, and URL escaping leaves `)` free to close the
          construct. *)
  | EscJsExpr
      (** a hole at a JS EXPRESSION position. There are no delimiters in the
          template to hide behind, so this escaper supplies its own: it renders
          the value as a complete, single-quoted JS string literal. An
          expression-position hole therefore lands as an inert string rather
          than as code — the same move every other escaper here makes when a
          value cannot be admitted as-is (a disallowed URL becomes
          `about:invalid#zSoyz`, an unrecognised CSS value becomes hex
          escapes), and the same one go's html/template and Closure Templates
          make in this position.

          It escapes BOTH quote characters numerically, so the only raw quotes
          in its output are its own two delimiters. That is what lets ONE
          escaper serve a `<script>` body and a double-quoted `on*` attribute:
          the body can close neither the JS literal nor the HTML attribute. A
          SINGLE-quoted `on*` attribute is the one context whose delimiter
          would collide, and the table rejects a hole there rather than
          emitting something that breaks out.

          A value that must reach JS as CODE rather than as data goes through
          `Html.trust_js`, which bypasses this escaper entirely — see the
          trusted-id tables in lib/tir/llvm_emit.ml and lib/eval/eval.ml.
          Appended rather than inserted so the existing ids stay stable: they
          are shared verbatim with the C runtime's MARCH_ESC_* defines. *)

let escaper_id = function
  | EscHtml -> 0
  | EscAttr -> 1
  | EscUrlComponent -> 2
  | EscUrlWhole -> 3
  | EscCssValue -> 4
  | EscJsString -> 5
  | EscNone -> 6
  | EscCssDecl -> 7
  | EscCssUrl -> 8
  | EscJsExpr -> 9

let escaper_name = function
  | EscHtml -> "html"
  | EscAttr -> "attr"
  | EscUrlComponent -> "url_component"
  | EscUrlWhole -> "url_whole"
  | EscCssValue -> "css_value"
  | EscJsString -> "js_string"
  | EscNone -> "none"
  | EscCssDecl -> "css_decl"
  | EscCssUrl -> "css_url"
  | EscJsExpr -> "js_expr"
