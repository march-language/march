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
  [ AtNormal; AtUrl; AtUrlMid; AtStyle; AtStyleValue; AtCssUrl; AtScript ]
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
  match c.state, c.attr, c.delim with
  | Pcdata, _, _ -> "in element content"
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
  | Attrvalue, AtScript, _ -> "in an event-handler attribute value"
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
