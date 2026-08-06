(** Contextual escapers, OCaml side.

    A direct mirror of [runtime/march_ctx_escape.c]. The compiled backend calls
    the C version; the interpreter calls this one. They MUST agree — an
    interpreter that escapes differently from compiled code is exactly the class
    of bug that hid the ~H ADT misread for so long (see
    [specs/progress/2026-08-05-h-sigil-adt-misread.md], where the interpreter
    was correct throughout and only compiled output was vulnerable).

    [test/test_ctxesc.ml] runs the same corpus through both via the C test
    binary's `--dump` mode, so a divergence fails the build rather than shipping.

    Read [specs/security/README.md] before changing any of these: the URL and
    CSS escapers are allowlists on purpose. *)

module C = Context

let buf_add_hex2 b c =
  let hexd = "0123456789ABCDEF" in
  Buffer.add_char b hexd.[(Char.code c lsr 4) land 0xF];
  Buffer.add_char b hexd.[Char.code c land 0xF]

let is_unreserved c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
  || c = '-' || c = '_' || c = '.' || c = '~'

(* The backtick is escaped in attribute values only: old IE accepted it as an
   attribute delimiter, so a value containing one could break out of a
   double-quoted attribute. Harmless in PCDATA, but kept minimal there. *)
let html_like ~attr s =
  let b = Buffer.create (String.length s) in
  String.iter
    (fun c ->
       match c with
       | '&' -> Buffer.add_string b "&amp;"
       | '<' -> Buffer.add_string b "&lt;"
       | '>' -> Buffer.add_string b "&gt;"
       | '"' -> Buffer.add_string b "&quot;"
       | '\'' -> Buffer.add_string b "&#39;"
       | '`' when attr -> Buffer.add_string b "&#96;"
       | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let url_component s =
  let b = Buffer.create (String.length s) in
  String.iter
    (fun c ->
       if is_unreserved c then Buffer.add_char b c
       else (Buffer.add_char b '%'; buf_add_hex2 b c))
    s;
  Buffer.contents b

(* Allowlist, not a javascript: denylist. Browsers strip leading whitespace and
   C0 control bytes before parsing a URL and ignore them INSIDE a scheme, so
   `  javascript:` and `java\tscript:` both defeat a prefix check — the scheme
   is extracted by skipping those bytes instead. A colon only introduces a
   scheme if everything before it is scheme-shaped, so `/a/b:c` is a path. *)
let url_scheme_is_allowed s =
  let n = String.length s in
  let sch = Buffer.create 16 in
  let rec go i =
    if i >= n then true  (* no colon at all — a relative reference *)
    else
      let c = s.[i] in
      if Char.code c <= 0x20 || Char.code c = 0x7F then go (i + 1)
      else if c = ':' then
        if Buffer.length sch = 0 then false
        else
          List.mem (Buffer.contents sch)
            [ "http"; "https"; "mailto"; "tel"; "ftp" ]
      else if c = '/' || c = '?' || c = '#' then true
      else if not ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                   || (c >= '0' && c <= '9')
                   || c = '+' || c = '-' || c = '.') then true
      else if Buffer.length sch >= 15 then false
      else (Buffer.add_char sch (Char.lowercase_ascii c); go (i + 1))
  in
  go 0

let url_whole s =
  if not (url_scheme_is_allowed s) then "about:invalid#zSoyz"
  else
    (* An allowed URL still sits in an attribute and must not close it. We must
       NOT percent-encode here, or every legitimate `?a=b&c=d` would break. *)
    html_like ~attr:true s

(* `</script` ends the element even inside a JS string literal, and U+2028 /
   U+2029 are line terminators in JS though legal in a JSON string — so a
   JSON-safe encoder is not JS-safe. *)
let js_string s =
  let n = String.length s in
  let b = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    let c = s.[!i] in
    if Char.code c = 0xE2 && !i + 2 < n
       && Char.code s.[!i + 1] = 0x80
       && (Char.code s.[!i + 2] = 0xA8 || Char.code s.[!i + 2] = 0xA9)
    then begin
      Buffer.add_string b
        (if Char.code s.[!i + 2] = 0xA8 then "\\u2028" else "\\u2029");
      i := !i + 3
    end
    else begin
      (match c with
       | '"' -> Buffer.add_string b "\\\""
       | '\'' -> Buffer.add_string b "\\'"
       | '\\' -> Buffer.add_string b "\\\\"
       | '\n' -> Buffer.add_string b "\\n"
       | '\r' -> Buffer.add_string b "\\r"
       | '\t' -> Buffer.add_string b "\\t"
       | '<' -> Buffer.add_string b "\\u003c"
       | '>' -> Buffer.add_string b "\\u003e"
       | '&' -> Buffer.add_string b "\\u0026"
       | '=' -> Buffer.add_string b "\\u003d"
       | c when Char.code c < 0x20 ->
         Buffer.add_string b "\\u00"; buf_add_hex2 b c
       | c -> Buffer.add_char b c);
      incr i
    end
  done;
  Buffer.contents b

(* Allowlist: CSS has too many routes to a URL or an expression for a denylist
   to be credible. Anything outside the safe set becomes `\XX `, which CSS reads
   as a literal character and which can never re-open a construct. *)
let css s =
  let b = Buffer.create (String.length s) in
  String.iter
    (fun c ->
       if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
          || (c >= '0' && c <= '9')
          || c = '-' || c = '_' || c = '#' || c = '%' || c = '.'
          || c = ',' || c = ' '
       then Buffer.add_char b c
       else (Buffer.add_char b '\\'; buf_add_hex2 b c; Buffer.add_char b ' '))
    s;
  Buffer.contents b

let apply (e : C.escaper) s =
  match e with
  | C.EscHtml -> html_like ~attr:false s
  | C.EscAttr -> html_like ~attr:true s
  | C.EscUrlComponent -> url_component s
  | C.EscUrlWhole -> url_whole s
  | C.EscCss -> css s
  | C.EscJsString -> js_string s
  | C.EscNone -> s

let apply_id id s =
  match List.find_opt (fun e -> C.escaper_id e = id)
          [ C.EscHtml; C.EscAttr; C.EscUrlComponent; C.EscUrlWhole;
            C.EscCss; C.EscJsString; C.EscNone ] with
  | Some e -> apply e s
  | None ->
    invalid_arg
      (Printf.sprintf
         "html_escape_ctx: unknown escaper id %d — the emitter and \
          lib/ctxesc/context.ml have diverged" id)
