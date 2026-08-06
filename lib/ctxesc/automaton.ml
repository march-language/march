(** The HTML context automaton.

    Walks a template's fixed chunks through the transition table from
    [specs/security/html-contexts.tbl], yielding the parse context at each hole.
    The context alone selects the escaper — see [Context] for why that matters.

    Two entry points mirror the two kinds of template fragment:
    - [consume_literal] for source text, and
    - [consume_interp] for a `${...}` hole.

    Both are pure, which is the precondition the paper states for erasing the
    accumulator at compile time. For `~H` the whole walk is constant-folded in
    the desugarer, so nothing here runs at runtime; the March-side port (a
    later task) reuses the same generated table so the two can be differentially
    tested against each other. *)

module C = Context
module P = Tbl_parse

type t = {
  rows : P.row list;
  tags : P.name_rule list;
  attrs : P.name_rule list;
}

let compile (tbl : P.t) =
  { rows = tbl.P.transitions; tags = tbl.P.tags; attrs = tbl.P.attrs }

type step_out = { emit : string; ctx : C.t }

(* ── Matching ─────────────────────────────────────────────────────────── *)

let ctx_matches (f : P.from_pat) (c : C.t) =
  (match f.P.f_state with None -> true | Some s -> s = c.C.state)
  && (match f.P.f_element with None -> true | Some e -> e = c.C.element)
  && (match f.P.f_attr with None -> true | Some a -> a = c.C.attr)
  && (match f.P.f_delim with None -> true | Some d -> d = c.C.delim)

let apply_succ (s : P.succ_pat) (c : C.t) =
  { C.state = (match s.P.s_state with None -> c.C.state | Some v -> v);
    C.element = (match s.P.s_element with None -> c.C.element | Some v -> v);
    C.attr = (match s.P.s_attr with None -> c.C.attr | Some v -> v);
    C.delim = (match s.P.s_delim with None -> c.C.delim | Some v -> v) }

let starts_with_at s i lit =
  let n = String.length s and m = String.length lit in
  i + m <= n && String.sub s i m = lit

let istarts_with_at s i lit =
  let n = String.length s and m = String.length lit in
  i + m <= n && String.lowercase_ascii (String.sub s i m) = lit

let name_chars =
  let ok c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
    || c = '-' || c = '_' || c = ':'
  in
  ok

(* How many bytes this pattern consumes at [i], and the name it captured (for
   [PName]/[PTag]). [None] means the pattern does not match here. *)
let match_pattern pat s i =
  let n = String.length s in
  match pat with
  | P.PInterp -> None  (* holes never match source text *)
  | P.PAny -> if i < n then Some (1, None) else None
  | P.PLit l -> if starts_with_at s i l then Some (String.length l, None) else None
  | P.PILit l -> if istarts_with_at s i l then Some (String.length l, None) else None
  | P.PUntil l ->
    let rec find j =
      if j + String.length l > n then None
      else if starts_with_at s j l then Some (j + String.length l - i, None)
      else find (j + 1)
    in
    find i
  | P.PClass cs -> if i < n && List.mem s.[i] cs then Some (1, None) else None
  | P.PClassPlus cs ->
    let rec go j = if j < n && List.mem s.[j] cs then go (j + 1) else j in
    let e = go i in
    if e > i then Some (e - i, None) else None
  | P.PName | P.PTag ->
    let rec go j = if j < n && name_chars s.[j] then go (j + 1) else j in
    let e = go i in
    if e > i then Some (e - i, Some (String.sub s i (e - i))) else None

(* ── Consuming source text ────────────────────────────────────────────── *)

let classify_default rules name fallback of_string =
  match P.classify rules name with
  | Some cls -> (match of_string cls with Some v -> v | None -> fallback)
  | None -> fallback

let consume_literal t (start : C.t) (src : string) =
  let n = String.length src in
  let buf = Buffer.create (n + 8) in
  let ctx = ref start in
  let i = ref 0 in
  let err = ref None in
  while !err = None && !i < n do
    let cand =
      List.find_map
        (fun (r : P.row) ->
           if not (ctx_matches r.P.from_pat !ctx) then None
           else match match_pattern r.P.pat src !i with
             | None -> None
             | Some (len, name) -> Some (r, len, name))
        t.rows
    in
    match cand with
    | None ->
      err :=
        Some
          (Printf.sprintf
             "no transition for %C while %s. This is a gap in \
              specs/security/html-contexts.tbl, not a problem with the \
              template -- every state needs an `any` catch-all."
             src.[!i] (C.describe !ctx),
           !i)
    | Some (r, len, name) ->
      (match r.P.subst with Some sub -> Buffer.add_string buf sub | None -> ());
      Buffer.add_string buf (String.sub src !i len);
      let next = apply_succ r.P.succ !ctx in
      (* `tag` / `name` patterns classify what they just consumed. The table's
         successor cannot know the name, so it is applied here on top. *)
      let next =
        match r.P.pat, name with
        | P.PTag, Some nm ->
          { next with
            C.element =
              classify_default t.tags nm C.ElNormal C.element_of_string }
        | P.PName, Some nm ->
          { next with
            C.attr = classify_default t.attrs nm C.AtNormal C.attr_of_string }
        | _ -> next
      in
      ctx := next;
      i := !i + len
  done;
  match !err with
  | Some e -> Error e
  | None -> Ok { emit = Buffer.contents buf; ctx = !ctx }

(* ── Consuming a hole ─────────────────────────────────────────────────── *)

(* The escaper is implied by the SUCCESSOR context rather than named in the
   row, so the table cannot drift out of sync with the escaper set. *)
let escaper_for (c : C.t) =
  match c.C.state with
  | C.Pcdata -> C.EscHtml
  | C.Rcdata ->
    (match c.C.element with
     | C.ElScript -> C.EscJsString
     | C.ElStyle -> C.EscCssDecl
     | _ -> C.EscHtml)
  | C.Attrvalue ->
    (match c.C.attr with
     | C.AtUrl -> C.EscUrlWhole
     | C.AtUrlMid -> C.EscUrlComponent
     | C.AtStyle -> C.EscCssDecl
     | C.AtStyleValue -> C.EscCssValue
     | C.AtScript -> C.EscJsString
     | C.AtNormal -> C.EscAttr)
  | _ -> C.EscAttr  (* unreachable: every other state rejects holes *)

let consume_interp t (c : C.t) =
  let row =
    List.find_opt
      (fun (r : P.row) -> r.P.pat = P.PInterp && ctx_matches r.P.from_pat c)
      t.rows
  in
  match row with
  | None ->
    Error
      (Printf.sprintf
         "No rule allows an interpolation %s. If that position is genuinely \
          safe, add a row to specs/security/html-contexts.tbl; if it is not, \
          the message should say why."
         (C.describe c))
  | Some r ->
    (match r.P.diag with
     | Some d -> Error d
     | None ->
       let next = apply_succ r.P.succ c in
       Ok (escaper_for next, (match r.P.subst with Some s -> s | None -> ""), next))

(* ── End of template ──────────────────────────────────────────────────── *)

(* A template must not end mid-tag, mid-attribute, mid-comment or inside a
   raw-text element: each would splice into whatever the caller concatenates
   next, which is exactly the composition hazard this analysis exists to stop. *)
let is_valid_terminal (c : C.t) =
  c.C.state = C.Pcdata && c.C.element = C.ElNormal

let describe = C.describe
