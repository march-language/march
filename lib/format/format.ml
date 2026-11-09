(** March source code formatter.

    Formats a March [module_] AST back to idiomatic, consistently-styled
    source text.  Rules (opinionated, gofmt-style):
      - 2-space indentation
      - 80-character soft line-width target
      - One blank line between top-level declarations, except that a run of
        imports, or a run of capability declarations, stays tight
      - Match arms each on their own line
      - Inline form when expression fits within 80 columns

    Comment preservation: comments are extracted from the original source text
    with their line numbers and re-inserted at declaration boundaries.  Comments
    that appear between declarations (section headers, separators) are faithfully
    reproduced.  Comments embedded deep inside expressions are a known limitation
    of AST-based formatting and are not preserved in this implementation. *)

open March_ast.Ast

(* ------------------------------------------------------------------ *)
(* Comment extraction                                                  *)
(* ------------------------------------------------------------------ *)

type comment = {
  com_line : int;    (** 1-based start line *)
  com_text : string; (** raw comment text (including -- / {- -}) *)
}

(** Scan [src] for [-- line comments] and [{- block comments -}],
    returning them in order with their 1-based start line numbers.
    String literals are skipped so that [--] inside a string is not
    mistaken for a comment. *)
let extract_comments src =
  let n = String.length src in
  let comments = ref [] in
  let i = ref 0 in
  let line = ref 1 in
  while !i < n do
    let c = src.[!i] in
    if c = '"' then begin
      (* Skip over a string literal — handles backslash escapes. *)
      incr i;
      let in_triple =
        !i + 1 < n && src.[!i] = '"' && src.[!i+1] = '"'
      in
      if in_triple then begin
        (* Triple-quoted string: skip until closing triple-quote *)
        i := !i + 2;
        let stop = ref false in
        while !i < n && not !stop do
          if !i + 2 < n && src.[!i] = '"' && src.[!i+1] = '"' && src.[!i+2] = '"' then begin
            i := !i + 3; stop := true
          end else begin
            if src.[!i] = '\n' then incr line;
            incr i
          end
        done
      end else begin
        (* Regular string: skip until closing unescaped quote *)
        while !i < n && src.[!i] <> '"' do
          if src.[!i] = '\\' && !i + 1 < n then i := !i + 2
          else begin
            if src.[!i] = '\n' then incr line;
            incr i
          end
        done;
        if !i < n then incr i (* skip closing quote *)
      end
    end else if c = '-' && !i + 1 < n && src.[!i+1] = '-' then begin
      let start_line = !line in
      let j = ref (!i + 2) in
      while !j < n && src.[!j] <> '\n' do incr j done;
      comments := { com_line = start_line; com_text = String.sub src !i (!j - !i) } :: !comments;
      i := !j
    end else if c = '{' && !i + 1 < n && src.[!i+1] = '-' then begin
      let start_line = !line in
      let depth = ref 1 in
      let j = ref (!i + 2) in
      while !j < n && !depth > 0 do
        if !j + 1 < n && src.[!j] = '{' && src.[!j+1] = '-' then begin
          incr depth; j := !j + 2
        end else if !j + 1 < n && src.[!j] = '-' && src.[!j+1] = '}' then begin
          decr depth; j := !j + 2
        end else begin
          if src.[!j] = '\n' then incr line;
          incr j
        end
      done;
      comments := { com_line = start_line; com_text = String.sub src !i (!j - !i) } :: !comments;
      i := !j
    end else begin
      if c = '\n' then incr line;
      incr i
    end
  done;
  List.rev !comments

(* ------------------------------------------------------------------ *)
(* Formatting context                                                  *)
(* ------------------------------------------------------------------ *)

type ctx = {
  buf      : Buffer.t;
  mutable indent  : int;
  comments : comment array;
  mutable com_idx : int;
}

let make_ctx comments = {
  buf      = Buffer.create 4096;
  indent   = 0;
  comments = Array.of_list comments;
  com_idx  = 0;
}

let ind ctx    = String.make (ctx.indent * 2) ' '
let put ctx s  = Buffer.add_string ctx.buf s
let nl  ctx    = Buffer.add_char   ctx.buf '\n'

(** Emit [ind ctx ^ s ^ "\n"]. *)
let line ctx s =
  put ctx (ind ctx);
  put ctx s;
  nl ctx

(** Run [f()] with indentation increased by one level. *)
let indented ctx f =
  ctx.indent <- ctx.indent + 1;
  (try f () with e -> ctx.indent <- ctx.indent - 1; raise e);
  ctx.indent <- ctx.indent - 1

(** Flush all comments whose line number is strictly less than [node_line]
    (i.e. the comment appeared before the node starts). *)
let flush_comments_before ctx node_line =
  while ctx.com_idx < Array.length ctx.comments &&
        ctx.comments.(ctx.com_idx).com_line < node_line do
    let c = ctx.comments.(ctx.com_idx) in
    line ctx c.com_text;
    ctx.com_idx <- ctx.com_idx + 1
  done

(* ------------------------------------------------------------------ *)
(* Literals                                                            *)
(* ------------------------------------------------------------------ *)

(* The March lexer's float literal only matches [digit+ '.' digit+] — it has
   no exponent form. OCaml's [string_of_float] switches to scientific
   notation (e.g. "9.537e-07") for small/large magnitudes, which the lexer
   then can't re-parse. Expand any scientific-notation output back into plain
   decimal digits by shifting the decimal point, so `--fmt` output is always
   re-parseable (idempotent). *)
let expand_scientific s =
  match String.index_opt s 'e' with
  | None -> s
  | Some ei ->
    let mantissa = String.sub s 0 ei in
    let exp = int_of_string (String.sub s (ei + 1) (String.length s - ei - 1)) in
    let neg, mantissa =
      if mantissa.[0] = '-' then true, String.sub mantissa 1 (String.length mantissa - 1)
      else false, mantissa
    in
    let int_part, frac_part =
      match String.index_opt mantissa '.' with
      | Some di -> String.sub mantissa 0 di, String.sub mantissa (di + 1) (String.length mantissa - di - 1)
      | None -> mantissa, ""
    in
    let digits = int_part ^ frac_part in
    let point_pos = String.length int_part + exp in
    let body =
      if point_pos <= 0 then
        "0." ^ String.make (-point_pos) '0' ^ digits
      else if point_pos >= String.length digits then
        digits ^ String.make (point_pos - String.length digits) '0' ^ ".0"
      else
        String.sub digits 0 point_pos ^ "." ^ String.sub digits point_pos (String.length digits - point_pos)
    in
    if neg then "-" ^ body else body

(* String literal escaping, matching the lexer's own escapes
   (lib/lexer/lexer.mll [read_string]).  OCaml's [String.escaped] is not that:
   it writes each UTF-8 byte as a decimal escape (\226) that the lexer
   rejects, and it leaves `${` alone, which then re-lexes as an
   interpolation. *)
let escape_string s =
  let b = Buffer.create (String.length s + 8) in
  let n = String.length s in
  String.iteri (fun i c ->
    match c with
    | '\\' -> Buffer.add_string b {|\\|}
    | '"' -> Buffer.add_string b {|\"|}
    | '\n' -> Buffer.add_string b {|\n|}
    | '\t' -> Buffer.add_string b {|\t|}
    | '\r' -> Buffer.add_string b {|\r|}
    | '\b' -> Buffer.add_string b {|\b|}
    | '\012' -> Buffer.add_string b {|\f|}
    | '\000' -> Buffer.add_string b {|\0|}
    | '$' when i + 1 < n && s.[i + 1] = '{' -> Buffer.add_string b {|\$|}
    | c when Char.code c < 0x20 || Char.code c = 0x7f ->
      Buffer.add_string b (Printf.sprintf {|\x%02x|} (Char.code c))
    | c -> Buffer.add_char b c) s;
  Buffer.contents b

(** [s] as an ordinary double-quoted March string literal. *)
let quote_string s = "\"" ^ escape_string s ^ "\""

let contains_sub s sub =
  let n = String.length s and m = String.length sub in
  let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
  go 0

(* A triple-quoted string has one escape (backslash-dollar), so its content
   is printed raw except for an interpolation opener.  Content holding three
   double quotes in a row or a literal backslash-dollar, or ending in a double
   quote, cannot be spelled that way and takes the ordinary escaped form; so
   does a carriage return, which the lexer folds into the newline after it. *)
let triple_safe s =
  not (contains_sub s {|"""|}) && not (contains_sub s {|\$|})
  && not (String.contains s '\r')
  && not (String.length s > 0 && s.[String.length s - 1] = '"')

let escape_triple s =
  let b = Buffer.create (String.length s + 8) in
  let n = String.length s in
  String.iteri (fun i c ->
    if c = '$' && i + 1 < n && s.[i + 1] = '{' then Buffer.add_string b {|\$|}
    else Buffer.add_char b c) s;
  Buffer.contents b

let fmt_lit = function
  | LitInt n    -> string_of_int n
  | LitFloat f  ->
    (* The shortest %g form that reads back as the same float.
       [string_of_float] keeps only 12 significant digits, so formatting
       used to change a literal's value (3.14159265358979 -> 3.14159265359). *)
    let s =
      let rec go p =
        let s = Printf.sprintf "%.*g" p f in
        if p >= 17 || float_of_string s = f then s else go (p + 1)
      in
      go 1
    in
    let s = if String.contains s 'e' then expand_scientific s else s in
    (* March requires digit+ '.' digit+ — ensure at least one digit after decimal *)
    if not (String.contains s '.') then s ^ ".0"
    else begin
      (* If the string ends with '.', append '0' *)
      if s.[String.length s - 1] = '.' then s ^ "0"
      else s
    end
  | LitString s ->
    (* Use triple quotes for multi-line strings that are actual content blocks,
       not short strings that just contain a \n *)
    if String.contains s '\n' && String.length s > 10 && triple_safe s then
      let triple = "\"\"\"" in
      triple ^ escape_triple s ^ triple
    else
      "\"" ^ escape_string s ^ "\""
  | LitBool b   -> if b then "true" else "false"
  | LitAtom s   -> ":" ^ s

(* ------------------------------------------------------------------ *)
(* Types                                                               *)
(* ------------------------------------------------------------------ *)

(* Forward reference to the inline expression formatter, used to render
   refinement predicates faithfully (so reformatting never drops the predicate).
   Assigned once [expr_inline] is in scope, at the bottom of this module. *)
let fmt_pred_ref : (expr -> string) ref =
  ref (fun _ -> invalid_arg "Format.fmt_pred_ref: used before initialisation")

(* The abstract-refinement DEFINER `D1 -> … -> Dn -> Bool[p]`, as the parser
   rewrites it (Parser.abstract_definer_arrow): each domain carries a binder
   (a synthetic `$x…` when the user wrote none), and the codomain is `{Bool |
   _ == p(x1, …, xn)}` over exactly those binders, MARKED with the binder `_`.
   Returns the domains and `p`.  An unmarked codomain is a user's spelled-out
   long form and is printed as written: printed as the shorthand under an
   outer arrow (`Int -> ({x : a | true}) -> {Bool | _ == p(x)}`) it would
   re-parse as a definer of two arguments. *)
let definer_chain (t : ty) : (ty list * string) option =
  let rec go doms t =
    match t with
    | TyArrow (dom, cod) -> go (dom :: doms) cod
    | TyRefine (TyCon ({ txt = "Bool"; _ }, []), m,
                EApp (EVar { txt = "=="; _ }, [ EVar { txt = "_"; _ }; EApp (EVar p, args, _) ], _)) ->
      let doms = List.rev doms in
      let marked = match m with Some { txt = "_"; _ } -> true | _ -> false in
      let binder d = match d with TyRefine (_, Some { txt; _ }, _) -> Some txt | _ -> None in
      let arg a = match a with EVar { txt; _ } -> Some txt | _ -> None in
      if doms <> [] && marked
         && List.length args = List.length doms
         && List.map binder doms = List.map arg args
      then Some (doms, p.txt)
      else None
    | _ -> None
  in
  match t with TyArrow _ -> go [] t | _ -> None

let rec fmt_ty = function
  | TyCon ({ txt; _ }, [])   -> txt
  | TyCon ({ txt; _ }, args) -> Printf.sprintf "%s(%s)" txt (fmt_tys args)
  | TyVar { txt; _ }         -> txt
  (* The abstract-refinement DEFINER (see [definer_chain]): print the
     shorthand back, which re-parses to the same tree, whereas the expanded
     form with `$x` cannot even be lexed. *)
  | TyArrow _ as t when definer_chain t <> None ->
    let doms, p = Option.get (definer_chain t) in
    let dom_s d = match d with
      | TyRefine (d, Some { txt; _ }, ELit (LitBool true, _))
        when String.length txt >= 2 && String.sub txt 0 2 = "$x" -> fmt_ty_atom d
      | d -> Printf.sprintf "(%s)" (fmt_ty d) in
    Printf.sprintf "%s -> Bool[%s]" (String.concat " -> " (List.map dom_s doms)) p
  | TyArrow (a, b)           -> Printf.sprintf "%s -> %s" (fmt_ty_atom a) (fmt_ty b)
  | TyTuple tys              -> Printf.sprintf "(%s)" (fmt_tys tys)
  | TyRecord flds            ->
    let f (n, t) = Printf.sprintf "%s : %s" n.txt (fmt_ty t) in
    Printf.sprintf "{ %s }" (String.concat ", " (List.map f flds))
  | TyLinear (lin, t)        ->
    (match lin with Unrestricted | Ghost -> "" | Linear -> "linear " | Affine -> "affine ") ^ fmt_ty t
  | TyNat n                  -> string_of_int n
  | TyNatOp (op, a, b)       ->
    let s = match op with NatAdd -> "+" | NatMul -> "*" in
    Printf.sprintf "%s %s %s" (fmt_ty a) s (fmt_ty b)
  | TyChan (r, p)            -> Printf.sprintf "Chan(%s, %s)" r.txt p.txt
  (* The abstract-refinement shorthand `T[p]`: the parser marks it with the
     binder `_`, which a user cannot write, so it prints back as written. *)
  | TyRefine (base, Some { txt = "_"; _ }, EApp (EVar p, [ EVar { txt = "_"; _ } ], _)) ->
    Printf.sprintf "%s[%s]" (fmt_ty_atom base) p.txt
  | TyRefine (base, None, pred) ->
    Printf.sprintf "{ %s | %s }" (fmt_ty base) (!fmt_pred_ref pred)
  | TyRefine (base, Some n, pred) ->
    Printf.sprintf "{ %s : %s | %s }" n.txt (fmt_ty base) (!fmt_pred_ref pred)

and fmt_ty_atom t = match t with TyArrow _ -> Printf.sprintf "(%s)" (fmt_ty t) | _ -> fmt_ty t

and fmt_tys tys = String.concat ", " (List.map fmt_ty tys)

(* ------------------------------------------------------------------ *)
(* Patterns                                                            *)
(* ------------------------------------------------------------------ *)

let rec fmt_pat = function
  | PatWild _                     -> "_"
  | PatVar { txt; _ }             -> txt
  | PatCon ({ txt; _ }, [])       -> txt
  | PatCon ({ txt; _ }, args)     -> Printf.sprintf "%s(%s)" txt (fmt_pats args)
  | PatAtom (name, [], _)         -> ":" ^ name
  | PatAtom (name, args, _)       -> Printf.sprintf ":%s(%s)" name (fmt_pats args)
  | PatTuple (ps, _)              -> Printf.sprintf "(%s)" (fmt_pats ps)
  | PatLit (lit, _)               -> fmt_lit lit
  | PatRecord (flds, _)           ->
    let f (n, p) =
      let ps = fmt_pat p in
      if ps = n.txt then n.txt else Printf.sprintf "%s: %s" n.txt ps
    in
    Printf.sprintf "{ %s }" (String.concat ", " (List.map f flds))
  (* [p as a as b] does not parse: the inner as-pattern keeps its parens. *)
  | PatAs ((PatAs _ as p), n, _)  -> Printf.sprintf "(%s) as %s" (fmt_pat p) n.txt
  | PatAs (p, n, _)               -> Printf.sprintf "%s as %s" (fmt_pat p) n.txt
  | PatOr (ps, _)               -> String.concat " | " (List.map fmt_pat ps)

and fmt_pats ps = String.concat ", " (List.map fmt_pat ps)

(* ------------------------------------------------------------------ *)
(* Parameters                                                          *)
(* ------------------------------------------------------------------ *)

let fmt_lin = function
  | Unrestricted -> "" | Linear -> "linear " | Affine -> "affine " | Ghost -> "ghost "

let fmt_param p =
  let l = fmt_lin p.param_lin in
  match p.param_ty with
  | None    -> l ^ p.param_name.txt
  | Some ty -> Printf.sprintf "%s%s : %s" l p.param_name.txt (fmt_ty ty)

(** Render a lambda's parameter list, e.g. [x], [(a, b)], [()]. *)
let fmt_lam_params = function
  | []  -> "()"
  | [p] when p.param_ty = None -> p.param_name.txt
  | ps  -> Printf.sprintf "(%s)" (String.concat ", " (List.map fmt_param ps))

(* ------------------------------------------------------------------ *)
(* Binding levels: where an operand needs parentheses                 *)
(* ------------------------------------------------------------------ *)

(* The parser drops parentheses ([LPAREN e RPAREN] yields plain [e]), so the
   formatter has to put back every pair the grammar needs (#1175).  Each
   expression gets a binding level from the grammar's own layering in
   lib/parser/parser.mly (expr > expr_pipe > expr_or > expr_and > expr_cmp >
   expr_add > expr_mul > expr_unary > expr_app > expr_field/expr_atom), and
   each operand position asks for a minimum level: an operand that binds
   looser than its position allows is wrapped in parentheses. *)
let lv_expr  = 0   (* a full [expr]: if / match / fn / assert *)
let lv_pipe  = 10  (* expr_pipe: [a |> f] *)
let lv_or    = 20
let lv_and   = 30
let lv_cmp   = 40  (* non-associative: both operands need lv_cmp + 1 *)
let lv_add   = 50
let lv_mul   = 60
let lv_unary = 70  (* [-e], [!e] *)
let lv_app   = 80  (* expr_app: [f(x)], [Con(x)] *)
let lv_atom  = 90  (* expr_field / expr_atom: what a callee or field base must be *)

(** Binding level of a binary infix operator, or [None]. *)
let infix_level = function
  | "||"          -> Some lv_or
  | "&&"          -> Some lv_and
  | "==" | "!=" | "<" | ">" | "<=" | ">=" -> Some lv_cmp
  | "+" | "-" | "++" | "+." | "-."        -> Some lv_add
  | "*" | "/" | "%" | "*." | "/."         -> Some lv_mul
  | _             -> None

(** Precedence rank of a binary infix operator (1 = loosest), or [None]. *)
let infix_prec op = Option.map (fun l -> l / 10 - 1) (infix_level op)

(** True if this expression is a binary infix application. *)
let is_infix_app = function
  | EApp (EVar { txt; _ }, [_; _], _) -> infix_level txt <> None
  | _ -> false

(** Get the infix precedence of an expression (for parenthesisation). *)
let expr_infix_prec = function
  | EApp (EVar { txt; _ }, [_; _], _) -> infix_prec txt
  | _ -> None

(** Try to reconstruct a list literal from Cons(a, Cons(b, Nil)) *)
let rec try_collect_list acc = function
  | ECon ({ txt = "Nil"; _ }, [], _) -> Some (List.rev acc)
  | ECon ({ txt = "Cons"; _ }, [hd; tl], _) -> try_collect_list (hd :: acc) tl
  | _ -> None

(** Try to reconstruct string interpolation from its desugared form:
      prefix ++ to_string(e1) ++ s1 ++ to_string(e2) ++ s2 ++ ...
    which is what [desugar_interp] in [lib/parser/parser.mly] emits, and which
    user code can also write by hand.

    The formatter runs on the PARSED module, before desugar, so it never sees
    the concat folding that desugar applies afterwards ([string_concat3] at
    three operands, [string_concat_n] at four or more).

    Returns Some (prefix_str, [(expr, suffix_str); ...]) if the pattern matches,
    where the original source was "prefix${e1}s1${e2}s2". *)
let try_collect_interp expr =
  (* Flatten left-associated ++ chain into a list of segments *)
  let rec flatten acc = function
    | EApp (EVar { txt = "++"; _ }, [lhs; rhs], _) ->
      flatten (rhs :: acc) lhs
    | e -> e :: acc
  in
  let segments = flatten [] expr in
  (* Pattern: LitString, to_string(e), LitString, to_string(e), LitString, ...
     The first segment must be a LitString (the prefix).
     Then alternating to_string(expr) and LitString pairs.
     The chain always ends with a LitString or to_string(expr). *)
  match segments with
  | ELit (LitString prefix, _) :: rest ->
    let rec collect_pairs acc = function
      | [] -> Some (prefix, List.rev acc)
      | EApp (EVar { txt = "to_string"; _ }, [e], _) :: ELit (LitString s, _) :: rest ->
        collect_pairs ((e, s) :: acc) rest
      | [EApp (EVar { txt = "to_string"; _ }, [e], _)] ->
        collect_pairs ((e, "") :: acc) []
      | _ -> None
    in
    collect_pairs [] rest
  | _ -> None

(** A statement form: it only means something as a line of a block body, so
    in an expression position it is printed as a [do ... end] block. *)
let is_stmt_form = function
  | ELet _ | ELetFn _ | ELetQ _ | ELetStar _ -> true
  | EBlock (_ :: _ :: _, _) -> true
  | _ -> false

(** The binding level of [e] as the renderer prints it. *)
let rec level_of e =
  if March_ast.Bounded_pred.view e <> None then lv_expr else
  match e with
  | EIf _ | EMatch _ | ECond _ | ELam _ | EAssert _ | EProof _ -> lv_expr
  | EPipe _ -> lv_pipe
  | EBlock ([x], _) -> level_of x
  | EApp (EVar { txt = "++"; _ }, [_; _], _) when try_collect_interp e <> None -> lv_atom
  | EApp (EVar { txt = op; _ }, [_; _], _) when infix_level op <> None ->
    Option.get (infix_level op)
  | EApp (EVar { txt = ("negate" | "not"); _ }, [_], _) -> lv_unary
  | EApp _ -> lv_app
  | ECon ({ txt = "Cons"; _ }, [_; _], _) when try_collect_list [] e <> None -> lv_atom
  | ECon (_, _ :: _, _) -> lv_app
  | _ -> lv_atom

(** A call the renderer prints as [head(args)], as opposed to an operator
    application or a list literal, which are also [EApp] / [ECon] nodes. *)
let plain_call e =
  if March_ast.Bounded_pred.view e <> None then None else
  match e with
  | EApp (EVar { txt = "++"; _ }, [_; _], _) when try_collect_interp e <> None -> None
  | EApp (EVar { txt; _ }, [_; _], _) when infix_level txt <> None -> None
  | EApp (EVar { txt = ("negate" | "not"); _ }, [_], _) -> None
  | EApp (f, (_ :: _ as args), _) -> Some (`Fn f, args)
  | ECon ({ txt = "Cons"; _ }, [_; _], _) when try_collect_list [] e <> None -> None
  | ECon (n, (_ :: _ as args), _) -> Some (`Con n, args)
  | _ -> None

(** The direct subexpressions of [e]. *)
let children e =
  match e with
  | ELit _ | EVar _ | EHole _ | EResultRef _ | EDbg (None, _) -> []
  | EApp (f, args, _) -> f :: args
  | ECon (_, xs, _) | ETuple (xs, _) | EAtom (_, xs, _) | EBlock (xs, _) -> xs
  | ELam (_, b, _) | ELetFn (_, _, _, b, _) -> [b]
  | ELet (b, _) -> [b.bind_expr]
  | EMatch (s, arms, _) ->
    s :: List.concat_map
           (fun a -> Option.to_list a.branch_guard @ [a.branch_body]) arms
  | ERecord (fs, _) -> List.map snd fs
  | ERecordUpdate (b, fs, _) -> b :: List.map snd fs
  | EField (x, _, _) | EAnnot (x, _, _) | ESpawn (x, _) | EDbg (Some x, _)
  | EAssert (x, _) | ESigil (_, x, _) | ERefineMsg (x, _, _) -> [x]
  | EProof (p, _) -> proof_children p
  | EIf (c, t, f, _) -> [c; t; f]
  | ECond (arms, _) -> List.concat_map (fun (c, b) -> [c; b]) arms
  | EPipe (a, b, _) | ESend (a, b, _) -> [a; b]
  | ELetQ (_, r, c, _) | ELetStar (_, r, c, _) -> [r; c]

(** True when [e] contains, anywhere inside it, a construct that can only be
    printed across lines (a match, a cond, a statement or a block of them).
    Every layout decision consults this, so a construct is never squeezed
    onto one line by a container that did not look inside it (#1174: lists,
    tuples, records, call arguments, operands and if branches all used to
    skip the check). *)
let rec needs_break e =
  match e with
  | EMatch _ | ECond _ | ELet _ | ELetFn _ | ELetQ _ | ELetStar _ | EProof _ -> true
  | EBlock (_ :: _ :: _, _) -> true
  | _ -> List.exists needs_break (children e)

let sigil_is_multiline content =
  match content with
  | ELit (LitString s, _) -> String.contains s '\n'
  | _ ->
    (* Check if it's an interpolation chain with multiline content *)
    match try_collect_interp content with
    | Some (prefix, parts) ->
      String.contains prefix '\n' ||
      List.exists (fun (_, s) -> String.contains s '\n') parts
    | None -> false

(** True if [e] is printed on multiple lines: it [needs_break], or it is (or
    its trailing lambda body is) a multi-line sigil, which reads better on
    lines of its own. *)
let rec is_multiline e =
  needs_break e ||
  (match e with
   | ESigil (_, content, _) -> sigil_is_multiline content
   | ELam (_, body, _) -> is_multiline body
   | EApp _ | ECon _ ->
     (match plain_call e with Some (_, args) -> trailing_multiline args | None -> false)
   | _ -> false)

(** True when the last argument, followed through any chain of wrapper
    calls/constructors in tail position (e.g. [Thunk(fn _ -> ...)] passed
    as the last arg of [GenTree(...)]), bottoms out in a lambda whose body
    needs multi-line rendering — the "trailing block" call shape, e.g.
    [List.map(xs, fn x -> <multi-statement body> )]. *)
and trailing_multiline args =
  match List.rev args with
  | ELam (_, body, _) :: _ -> is_multiline body
  | last :: _ ->
    (match plain_call last with Some (_, a) -> trailing_multiline a | None -> false)
  | [] -> false

(** A lambda body made only of [let] bindings ahead of a final expression:
    the only shape [fn x ->] may continue with on the following lines outside
    a call argument (parser.mly [lambda_body]).  Anything else is wrapped in
    [do ... end], or a bare statement would end the lambda and change the
    program. *)
let rec lets_only_body e =
  match e with
  | EBlock ((_ :: _ :: _ as es), _) ->
    let rec go = function
      | [last] -> lets_only_body last
      | ELet _ :: rest -> go rest
      | _ -> false
    in
    go es
  | ELetQ (_, _, c, _) | ELetStar (_, _, c, _) -> lets_only_body c
  | ELet _ | ELetFn _ | EBlock ([], _) -> false
  | _ -> true

(* ------------------------------------------------------------------ *)
(* Expressions                                                         *)
(* ------------------------------------------------------------------ *)

(* One renderer serves every position.  [render ind lvl e] is [e]'s text for
   a position that needs binding level [lvl], parenthesised when [e] binds
   looser.  The text begins on a line indented [ind] levels; a construct that
   must span lines is emitted by the block emitters below into a scratch
   buffer at that indentation ([sub_block]), so its continuation lines carry
   their absolute indentation and the text can be dropped into any line.
   There is no placeholder: every construct prints in full (#1174). *)
let rec render ind lvl e =
  let s = render_raw ind e in
  if level_of e < lvl then "(" ^ s ^ ")" else s

(** The text the block emitter [f] writes when started at indentation [ind],
    minus the first line's indentation and the final newline. *)
and sub_block ind f =
  let c = { buf = Buffer.create 256; indent = ind; comments = [||]; com_idx = 0 } in
  f c;
  let s = Buffer.contents c.buf in
  let pre = 2 * ind in
  let n = String.length s in
  let s = if n >= pre then String.sub s pre (n - pre) else s in
  let n = String.length s in
  if n > 0 && s.[n - 1] = '\n' then String.sub s 0 (n - 1) else s

(** [e] (a statement form) as a [do ... end] block. *)
and do_block ind e =
  sub_block ind (fun c ->
    line c "do";
    indented c (fun () -> emit_body c e);
    line c "end")

(** A callee: [f] in [f(args)].  A bare constructor is parenthesised too, or
    [(Foo)(x)] would come back as the constructor application [Foo(x)]. *)
and callee ind f =
  match f with
  | ECon (n, [], _) -> "(" ^ n.txt ^ ")"
  | _ -> render ind lv_atom f

and call_head ind = function
  | `Fn f -> callee ind f
  | `Con (n : name) -> n.txt

and render_raw ind e =
  let r lvl x = render ind lvl x in
  let args xs = String.concat ", " (List.map (r lv_expr) xs) in
  match March_ast.Bounded_pred.view e with
  | Some q ->
    let domain = match q.domain with
      | March_ast.Bounded_pred.Range (lo, hi) -> r lv_add lo ^ ".." ^ r lv_add hi
      | March_ast.Bounded_pred.Elements set -> r lv_expr set in
    (if q.kind = March_ast.Bounded_pred.Forall then "forall " else "exists ")
    ^ q.binder.txt ^ " in " ^ domain ^ ", " ^ r lv_expr q.body
  | None -> match e with
  | ELit (lit, _)               -> fmt_lit lit
  | EVar { txt; _ }             -> txt
  (* Reconstruct list literals: Cons(a, Cons(b, Nil)) → [a, b] *)
  | ECon ({ txt = "Cons"; _ }, [_; _], _) when try_collect_list [] e <> None ->
    Printf.sprintf "[%s]" (args (Option.get (try_collect_list [] e)))
  | ECon ({ txt = "Nil"; _ }, [], _) -> "[]"
  | ECon ({ txt; _ }, [], _)    -> txt
  | ECon ({ txt; _ }, xs, _)    -> Printf.sprintf "%s(%s)" txt (args xs)
  (* Reconstruct string interpolation: ++ chain → "${expr}" *)
  | EApp (EVar { txt = "++"; _ }, [_; _], _) when try_collect_interp e <> None ->
    let prefix, parts = Option.get (try_collect_interp e) in
    let segs = prefix :: List.map snd parts in
    let last = List.nth segs (List.length segs - 1) in
    let needs_triple =
      List.exists (fun s -> String.contains s '\n') segs
      && List.for_all (fun s -> not (contains_sub s {|"""|} || contains_sub s {|\$|})) segs
      && not (String.length last > 0 && last.[String.length last - 1] = '"')
    in
    let esc s = if needs_triple then escape_triple s else escape_string s in
    let buf = Buffer.create 64 in
    let quote = if needs_triple then "\"\"\"" else "\"" in
    Buffer.add_string buf quote;
    Buffer.add_string buf (esc prefix);
    List.iter (fun (x, seg) ->
      Buffer.add_string buf "${";
      Buffer.add_string buf (r lv_expr x);
      Buffer.add_char buf '}';
      Buffer.add_string buf (esc seg)
    ) parts;
    Buffer.add_string buf quote;
    Buffer.contents buf
  | EApp (EVar { txt = op; _ }, [a; b], _) when infix_level op <> None ->
    (* Left-associative operators take an equal-level left operand; a
       comparison is non-associative, so [(a == b) == c] keeps its parens. *)
    let p = Option.get (infix_level op) in
    let lp = if p = lv_cmp then p + 1 else p in
    Printf.sprintf "%s %s %s" (r lp a) op (r (p + 1) b)
  | EApp (EVar { txt = "negate"; _ }, [x], _) ->
    (* [-(-x)] must not print as [--x], which lexes as a comment. *)
    let s = r lv_unary x in
    if String.length s > 0 && s.[0] = '-' then "-(" ^ s ^ ")" else "-" ^ s
  | EApp (EVar { txt = "not"; _ }, [x], _) -> "!" ^ r lv_unary x
  | EApp (f, xs, _)             -> Printf.sprintf "%s(%s)" (callee ind f) (args xs)
  | ELam (params, body, _)      ->
    let ps = fmt_lam_params params in
    if is_stmt_form body then Printf.sprintf "fn %s -> %s" ps (do_block ind body)
    else Printf.sprintf "fn %s -> %s" ps (r lv_expr body)
  | EBlock ([], _)              -> ""
  | EBlock ([x], _)             -> render_raw ind x
  | EBlock _ | ELet _ | ELetFn _ | ELetQ _ | ELetStar _ -> do_block ind e
  | EMatch (subj, arms, _)      -> sub_block ind (fun c -> emit_match c subj arms)
  | ECond (arms, _)             -> sub_block ind (fun c -> emit_cond c arms)
  | ETuple (xs, _)              -> Printf.sprintf "(%s)" (args xs)
  | ERecord (flds, _)           ->
    let f (n, x) = Printf.sprintf "%s: %s" n.txt (r lv_expr x) in
    Printf.sprintf "{ %s }" (String.concat ", " (List.map f flds))
  | ERecordUpdate (b, flds, _)  ->
    let f (n, v) = Printf.sprintf "%s: %s" n.txt (r lv_expr v) in
    Printf.sprintf "{ %s with %s }" (r lv_pipe b) (String.concat ", " (List.map f flds))
  | EField (x, n, _)            -> Printf.sprintf "%s.%s" (r lv_atom x) n.txt
  | EIf (c, t, f, _)            ->
    if needs_break c || needs_break t || needs_break f then
      sub_block ind (fun cx -> emit_if_lines cx c t f)
    else
      Printf.sprintf "if %s do %s else %s end" (r lv_pipe c) (r lv_expr t) (r lv_expr f)
  | EPipe (a, b, _)             -> Printf.sprintf "%s |> %s" (r lv_pipe a) (r lv_or b)
  | EAnnot (x, t, _)            -> Printf.sprintf "(%s : %s)" (r lv_pipe x) (fmt_ty t)
  | EHole (None, _)             -> "?"
  | EHole (Some n, _)           -> "?" ^ n.txt
  | EAtom (name, [], _)         -> ":" ^ name
  | EAtom (name, xs, _)         -> Printf.sprintf ":%s(%s)" name (args xs)
  | ESend (cap, msg, _)         -> Printf.sprintf "send(%s, %s)" (r lv_expr cap) (r lv_expr msg)
  | ESpawn (a, _)               -> Printf.sprintf "spawn(%s)" (r lv_expr a)
  | EResultRef None             -> "v"
  | EResultRef (Some n)         -> Printf.sprintf "v(%d)" n
  | EDbg (None, _)              -> "dbg()"
  | EDbg (Some x, _)            -> Printf.sprintf "dbg(%s)" (r lv_expr x)
  | EAssert (x, _)              -> Printf.sprintf "assert %s" (r lv_expr x)
  (* A proof statement is always written one construct per line. *)
  | EProof _                    -> sub_block ind (fun c -> emit_stmt c e)
  | ESigil (name, content, _)   -> Printf.sprintf "~%s%s" name (r lv_atom content)
  | ERefineMsg (inner, msg, sp) ->
    Printf.sprintf "%s else %s" (r lv_expr inner) (render_raw ind (ELit (LitString msg, sp)))

(** Returns true if we should break this expression across lines,
    considering the current indentation level. *)
and should_break indent_lvl expr =
  is_multiline expr ||
  String.length (render indent_lvl lv_expr expr) + indent_lvl * 2 > 80

(* ------------------------------------------------------------------ *)
(* Expressions — block (multi-line) renderer                          *)
(* ------------------------------------------------------------------ *)

(** Emit expression [e] as one or more statements at current indentation. *)
and emit_stmt ctx e =
  let ex x = render ctx.indent lv_expr x in
  match e with
  | EBlock ([], _) -> ()
  | EBlock ([x], _) -> emit_stmt ctx x
  | EBlock _ ->
    (* A block nested inside a block keeps its own scope: printed as
       [do ... end], never spliced into the enclosing statements. *)
    line ctx "do";
    indented ctx (fun () -> emit_body ctx e);
    line ctx "end"

  | ELet (b, _) ->
    let ty  = match b.bind_ty with
      | None   -> ""
      | Some t -> Printf.sprintf " : %s" (fmt_ty t)
    in
    (* `linear let x`, not `let linear x`, which does not parse. *)
    let lhs = Printf.sprintf "%slet %s%s" (fmt_lin b.bind_lin) (fmt_pat b.bind_pat) ty in
    if is_stmt_form b.bind_expr then begin
      line ctx (lhs ^ " = do");
      indented ctx (fun () -> emit_body ctx b.bind_expr);
      line ctx "end"
    end else if should_break (ctx.indent + 1) b.bind_expr then begin
      line ctx (lhs ^ " =");
      indented ctx (fun () -> emit_stmt ctx b.bind_expr)
    end else
      line ctx (Printf.sprintf "%s = %s" lhs (ex b.bind_expr))

  | EMatch (subj, arms, _) ->
    emit_match ctx subj arms

  | ECond (arms, _) ->
    emit_cond ctx arms

  | EIf (c, t, e, _) ->
    emit_if ctx c t e

  | EPipe _ ->
    emit_pipe_chain ctx e

  | ELetFn (name, ps, ret, body, _) ->
    let ty = match ret with None -> "" | Some t -> Printf.sprintf " : %s" (fmt_ty t) in
    line ctx (Printf.sprintf "fn %s(%s)%s do"
      name.txt (String.concat ", " (List.map fmt_param ps)) ty);
    indented ctx (fun () -> emit_body ctx body);
    line ctx "end"

  | ELetQ (p, r, cont, _) ->
    emit_bind_line ctx (Printf.sprintf "let? %s" (fmt_pat p)) r;
    emit_body ctx cont

  | ELetStar (p, r, cont, _) ->
    emit_bind_line ctx (Printf.sprintf "let* %s" (fmt_pat p)) r;
    emit_body ctx cont

  | ESigil (name, content, _) when sigil_is_multiline content ->
    emit_sigil_multiline ctx name content

  | ELam (params, body, _) when is_multiline body ->
    if lets_only_body body then begin
      line ctx (Printf.sprintf "fn %s ->" (fmt_lam_params params));
      indented ctx (fun () -> emit_body ctx body)
    end else
      line ctx (ex e)

  | (EApp _ | ECon _) when (match plain_call e with
                            | Some (_, args) -> trailing_multiline args
                            | None -> false) ->
    let head, args = Option.get (plain_call e) in
    emit_call_multiline ctx ~prefix:"" ~head:(call_head ctx.indent head) args

  (* A list or record literal too wide for the 80-column budget breaks one
     element (field) per line. Until 2026-09-11 literals had NO multi-line
     renderer at all, so a 19,509-character list of records came out on one
     line (specs/todos/2026-08-03-formatter-collapses-multiline-literals.md);
     the width budget existed but was never consulted for them. A literal
     that fits stays inline byte for byte. An element that is itself a single
     over-wide atom (one long string, one `++` chain) still yields an
     over-width line: nothing here splits atoms. *)
  | ECon ({ txt = "Cons"; _ }, [_; _], _)
    when try_collect_list [] e <> None && should_break ctx.indent e ->
    emit_literal_multiline ctx ~suffix:"" e

  | ERecord ((_ :: _), _) when should_break ctx.indent e ->
    emit_literal_multiline ctx ~suffix:"" e

  | EProof (p, _) -> emit_proof ctx p

  | _ ->
    line ctx (ex e)

(** [kw = r] for a [let?] / [let*] binding, breaking after [=] when [r]
    does not fit. *)
and emit_bind_line ctx kw r =
  if should_break (ctx.indent + 1) r then begin
    line ctx (kw ^ " =");
    indented ctx (fun () -> emit_stmt ctx r)
  end else
    line ctx (Printf.sprintf "%s = %s" kw (render ctx.indent lv_expr r))

(** A proof statement, one construct per line so it re-parses: a hint that is
    one call stays on the `by` line; anything else is a `do … end` block, as is
    a `with fuel` body.  A calc term that is a comparison or a Boolean
    connective gets parentheses (steps are read at the additive level). *)
and emit_proof ctx p =
  let is_call = function EApp _ | ECon _ | EVar _ -> true | _ -> false in
  let operand e =
    match e with
    | EApp (EVar { txt = ("==" | "!=" | "<" | "<=" | ">" | ">=" | "&&" | "||"); _ }, [ _; _ ], _) ->
      "(" ^ (render ctx.indent lv_expr) e ^ ")"
    | _ -> (render ctx.indent lv_expr) e
  in
  let with_hint prefix hs =
    match hs with
    | [] -> line ctx prefix
    | [ h ] when is_call h && not (is_multiline h) -> line ctx (prefix ^ " by " ^ (render ctx.indent lv_expr) h)
    | hs ->
      line ctx (prefix ^ " by do");
      indented ctx (fun () -> List.iter (emit_stmt ctx) hs);
      line ctx "end"
  in
  match p with
  | PAssertBy (e, hs) -> with_hint ("assert " ^ (render ctx.indent lv_expr) e) hs
  | PReveal f -> line ctx ("reveal " ^ (render ctx.indent lv_expr) f)
  | PWithFuel (f, n, body) ->
    line ctx (Printf.sprintf "with fuel(%s, %d) do" ((render ctx.indent lv_expr) f) n);
    indented ctx (fun () -> List.iter (emit_stmt ctx) body);
    line ctx "end"
  | PCalc (e0, steps) ->
    line ctx "calc do";
    indented ctx (fun () ->
        line ctx (operand e0);
        List.iter (fun s -> with_hint (s.cs_op ^ " " ^ operand s.cs_rhs) s.cs_hint) steps);
    line ctx "end"

(** Emit a too-wide list or record literal across lines, with [suffix]
    (a trailing "," when this literal is itself an element of an enclosing
    broken literal) appended to the closing bracket. Elements recurse: a
    record that fits on one line inside a broken list stays inline; one that
    does not breaks at the next indent level. *)
and emit_literal_multiline ctx ~suffix e =
  let ex x = render ctx.indent lv_expr x in
  let emit_elem el is_last =
    let sfx = if is_last then "" else "," in
    match el with
    | ECon ({ txt = "Cons"; _ }, [_; _], _)
      when try_collect_list [] el <> None && should_break ctx.indent el ->
      emit_literal_multiline ctx ~suffix:sfx el
    | ERecord ((_ :: _), _) when should_break ctx.indent el ->
      emit_literal_multiline ctx ~suffix:sfx el
    | _ -> line ctx (ex el ^ sfx)
  in
  let emit_elems elems =
    let n = List.length elems in
    List.iteri (fun i el -> emit_elem el (i = n - 1)) elems
  in
  match e with
  | ERecord (flds, _) ->
    line ctx "{";
    indented ctx (fun () ->
      let n = List.length flds in
      List.iteri (fun i (name, v) ->
        let sfx = if i = n - 1 then "" else "," in
        let head = name.txt ^ ": " in
        match v with
        | (ECon ({ txt = "Cons"; _ }, [_; _], _) | ERecord ((_ :: _), _))
          when should_break (ctx.indent + 1) v
               && not (is_multiline v)
               && String.length head + String.length (ex v) + ctx.indent * 2 > 80 ->
          line ctx (head ^ (match v with ERecord _ -> "{" | _ -> "["));
          (* Re-enter through the element path so nested literals break at
             the next level; the opener was emitted with the field name. *)
          (match v with
           | ERecord (inner, _) ->
             indented ctx (fun () ->
               let m = List.length inner in
               List.iteri (fun j (nm, iv) ->
                 line ctx (Printf.sprintf "%s: %s%s" nm.txt (ex iv)
                             (if j = m - 1 then "" else ","))) inner);
             line ctx ("}" ^ sfx)
           | _ ->
             let elems = match try_collect_list [] v with Some es -> es | None -> [] in
             indented ctx (fun () -> emit_elems elems);
             line ctx ("]" ^ sfx))
        | _ -> line ctx (Printf.sprintf "%s%s%s" head (ex v) sfx)) flds);
    line ctx ("}" ^ suffix)
  | _ ->
    let elems = match try_collect_list [] e with Some es -> es | None -> [] in
    line ctx "[";
    indented ctx (fun () -> emit_elems elems);
    line ctx ("]" ^ suffix)

(** Emit a call whose last argument, possibly through a chain of wrapper
    calls/constructors in tail position (e.g. [Thunk(fn _ -> ...)] as the
    last arg of [GenTree(...)]), bottoms out in a lambda needing a
    multi-line body:
      [Head(arg1, ..., Wrapper(fn params ->]
        <indented body>
      [))]
    The body is a call argument's lambda body (parser.mly
    [call_arg_lambda_body]), which may hold any statements.
    [prefix] is prepended to the head line (e.g. ["|> "] inside a pipe
    chain); [head] is the already-rendered outermost callee. *)
and emit_call_multiline ctx ~prefix ~head args =
  let ind = ctx.indent in
  let buf = Buffer.create 64 in
  Buffer.add_string buf prefix;
  let rec walk head args =
    let init_args, last = match List.rev args with
      | last :: rest -> (List.rev rest, last)
      | [] -> invalid_arg "emit_call_multiline: no arguments"
    in
    let sep = if init_args = [] then "" else ", " in
    let args_s = String.concat ", " (List.map (render ind lv_expr) init_args) in
    match last, plain_call last with
    | ELam (params, body, _), _ ->
      Buffer.add_string buf
        (Printf.sprintf "%s(%s%sfn %s ->" head args_s sep (fmt_lam_params params));
      (body, 1)
    | _, Some (h, nested_args) ->
      Buffer.add_string buf (Printf.sprintf "%s(%s%s" head args_s sep);
      let (body, depth) = walk (call_head ind h) nested_args in
      (body, depth + 1)
    | _ -> invalid_arg "emit_call_multiline: no trailing lambda"
  in
  let (body, depth) = walk head args in
  line ctx (Buffer.contents buf);
  indented ctx (fun () -> emit_body ctx body);
  line ctx (String.make depth ')')

(** Emit the body of a fn / match arm — unwraps a single EBlock. *)
and emit_body ctx body =
  match body with
  | EBlock (es, _) -> List.iter (emit_stmt ctx) es
  | _ -> emit_stmt ctx body

(** One match (or cond) arm: [head -> body], or [head -> do ... end] when
    the body does not fit on the line. *)
and emit_arm ctx head body =
  if should_break (ctx.indent + 1) body then begin
    line ctx (Printf.sprintf "%s -> do" head);
    indented ctx (fun () -> emit_body ctx body);
    line ctx "end"
  end else
    line ctx (Printf.sprintf "%s -> %s" head (render ctx.indent lv_expr body))

and emit_match ctx subj arms =
  line ctx (Printf.sprintf "match %s do" (render ctx.indent lv_pipe subj));
  List.iter (fun arm ->
    let guard = match arm.branch_guard with
      | None   -> ""
      | Some g -> " when " ^ render ctx.indent lv_pipe g
    in
    emit_arm ctx (fmt_pat arm.branch_pat ^ guard) arm.branch_body
  ) arms;
  line ctx "end"

(** The subject-less [match do cond -> body ... end] (it had no emitter, and
    its inline form was the placeholder [match do ... end], #1174). *)
and emit_cond ctx arms =
  line ctx "match do";
  List.iter (fun (c, body) ->
    emit_arm ctx (render ctx.indent lv_pipe c) body) arms;
  line ctx "end"

and emit_if ctx cond then_ else_ =
  if is_multiline cond || is_multiline then_ || is_multiline else_ then
    emit_if_lines ctx cond then_ else_
  else begin
    let cs = render ctx.indent lv_pipe cond in
    let ts = render ctx.indent lv_expr then_ in
    let es = render ctx.indent lv_expr else_ in
    let inline_len =
      ctx.indent * 2 + 3 + String.length cs + 4 + String.length ts + 6 + String.length es + 4
    in
    if inline_len <= 80 then
      line ctx (Printf.sprintf "if %s do %s else %s end" cs ts es)
    else
      emit_if_lines ctx cond then_ else_
  end

and emit_if_lines ctx cond then_ else_ =
  line ctx (Printf.sprintf "if %s do" (render ctx.indent lv_pipe cond));
  emit_if_branch ctx then_;
  line ctx "else";
  emit_if_branch ctx else_;
  line ctx "end"

(** Emit an if/then/else branch.  A multi-statement branch is wrapped in
    [do...end] (the branch is a [block_body], so this is the same tree). *)
and emit_if_branch ctx e =
  match e with
  | EBlock (_ :: _ :: _, _) ->
    indented ctx (fun () ->
      line ctx "do";
      indented ctx (fun () -> emit_body ctx e);
      line ctx "end")
  | _ ->
    indented ctx (fun () -> emit_stmt ctx e)

and emit_sigil_multiline ctx name content =
  (* The content is printed exactly as written, newlines and leading
     whitespace included.  It used to be re-indented (common indentation
     stripped, the first newline and trailing blanks dropped), which changed
     the string the sigil receives: a ~H template's output bytes, or the
     structure of a ~yaml block.  Content a triple-quoted string cannot spell
     falls back to an ordinary escaped string. *)
  let segs = match content with
    | ELit (LitString s, _) -> Some (s, [])
    | _ -> try_collect_interp content
  in
  let spellable (prefix, parts) =
    let all = prefix :: List.map snd parts in
    let last = List.nth all (List.length all - 1) in
    List.for_all (fun s ->
        not (contains_sub s {|"""|} || contains_sub s {|\$|} || String.contains s '\r'))
      all
    && not (String.length last > 0 && last.[String.length last - 1] = '"')
  in
  match segs with
  | Some ((prefix, parts) as sp) when spellable sp ->
    let buf = Buffer.create 256 in
    Buffer.add_string buf (Printf.sprintf "~%s\"\"\"" name);
    Buffer.add_string buf (escape_triple prefix);
    List.iter (fun (e, seg) ->
      Buffer.add_string buf "${";
      Buffer.add_string buf (render ctx.indent lv_expr e);
      Buffer.add_char buf '}';
      Buffer.add_string buf (escape_triple seg)
    ) parts;
    Buffer.add_string buf "\"\"\"";
    line ctx (Buffer.contents buf)
  | _ ->
    line ctx (Printf.sprintf "~%s%s" name (render ctx.indent lv_atom content))

and emit_pipe_chain ctx expr =
  (* Collect the pipe chain from left to right.  The head is a pipe's left
     operand (expr_pipe) and each stage a right operand (expr_or), so an
     if / match / fn / pipe there keeps its parentheses. *)
  let rec collect acc = function
    | EPipe (lhs, rhs, _) -> collect (rhs :: acc) lhs
    | e -> (e, acc)
  in
  let (head, stages) = collect [] expr in
  let any_multiline = is_multiline head || List.exists is_multiline stages in
  let head_s () = render ctx.indent lv_pipe head in
  let stage_s s = render ctx.indent lv_or s in
  let trailing e =
    match plain_call e with
    | Some (h, args) when trailing_multiline args -> Some (h, args)
    | _ -> None
  in
  let inline () =
    head_s () ^ String.concat "" (List.map (fun s -> " |> " ^ stage_s s) stages)
  in
  if not any_multiline && ctx.indent * 2 + String.length (inline ()) <= 80 then
    line ctx (inline ())
  else begin
    (match trailing head with
     | Some (h, args) ->
       emit_call_multiline ctx ~prefix:"" ~head:(call_head ctx.indent h) args
     | None -> line ctx (head_s ()));
    indented ctx (fun () ->
      List.iter (fun stage ->
        match trailing stage with
        | Some (h, args) ->
          emit_call_multiline ctx ~prefix:"|> " ~head:(call_head ctx.indent h) args
        | None -> line ctx ("|> " ^ stage_s stage)
      ) stages)
  end

(** Render an expression with no enclosing context (a full [expr] position
    at indentation 0).  Constructs that need several lines come back with
    embedded newlines; nothing is ever summarised. *)
let expr_inline e = render 0 lv_expr e

let fmt_fn_param = function
  | FPPat  p -> fmt_pat p
  | FPNamed p -> fmt_param p
  | FPDefault (p, default_e) ->
    (* The default value is part of the program: it used to print as `_`. *)
    fmt_param p ^ " \\\\ " ^ render 0 lv_pipe default_e


(* ------------------------------------------------------------------ *)
(* Declarations                                                        *)
(* ------------------------------------------------------------------ *)

(** Extract the span from any declaration (for comment flushing). *)
let get_span = function
  | DFn (_, s) | DLet (_, _, s) | DType (_, _, _, _, s) | DAlwaysLinearType (_, _, _, _, s)
  | DMod (_, _, _, s) | DProtocol (_, _, s) | DActor (_, _, _, s)
  | DSig (_, _, s) | DInterface (_, s) | DImpl (_, s) | DExtern (_, s)
  | DUse (_, s) | DAlias (_, s) | DNeeds (_, s) | DProofCap (_, _, s) | DApp (_, s)
  | DDeriving (_, _, s) | DSatisfy (_, _, s) | DTest (_, s) | DDescribe (_, _, s) | DSetup (_, s) | DSetupAll (_, s)
  | DTransitions (_, _, s) | DOpts (_, s) -> s

(** Declarations that read as a list rather than as separate paragraphs: a run
    of imports or a run of capability declarations stays tight, with blank lines
    only at the boundaries of the run.  Everything else keeps one blank line
    between declarations. *)
let compact_group = function
  | DUse _ | DAlias _ -> Some `Imports
  | DNeeds _ | DProofCap _ | DOpts _ -> Some `Caps
  | _ -> None

(** Two adjacent declarations belong to the same run only if both are compact
    and of the same kind. *)
let same_compact_run a b =
  match compact_group a, compact_group b with
  | Some x, Some y -> x = y
  | _ -> false

(** A `needs` bound as printed after a function's return type or an interface
    method's type: [" needs ()"], [" needs A.B, C"], or [""] for none.
    Dropping it would silently widen the function (or every impl) to the
    module's needs. *)
let fmt_needs (needs : (name list list * span) option) : string =
  match needs with
  | None -> ""
  | Some ([], _) -> " needs ()"
  | Some (paths, _) ->
    " needs "
    ^ String.concat ", "
        (List.map (fun p -> String.concat "." (List.map (fun (n : name) -> n.txt) p)) paths)

(** Emit a list of declarations separated by blank lines,
    flushing comments before each one. *)
let rec emit_decls ctx decls =
  let arr = Array.of_list decls in
  let n = Array.length arr in
  Array.iteri (fun i decl ->
    let span = get_span decl in
    flush_comments_before ctx span.start_line;
    emit_decl ctx decl;
    if i < n - 1 && not (same_compact_run decl arr.(i + 1)) then nl ctx
  ) arr

and emit_decl ctx = function
  | DFn (fn, _) ->
    emit_fn ctx fn

  | DLet (_vis, b, _) ->
    let ty  = match b.bind_ty with None -> "" | Some t -> Printf.sprintf " : %s" (fmt_ty t) in
    let lhs = Printf.sprintf "let %s%s%s" (fmt_lin b.bind_lin) (fmt_pat b.bind_pat) ty in
    if should_break (ctx.indent + 1) b.bind_expr then begin
      line ctx (lhs ^ " =");
      indented ctx (fun () -> emit_stmt ctx b.bind_expr)
    end else
      line ctx (Printf.sprintf "%s = %s" lhs (render ctx.indent lv_expr b.bind_expr))

  | DAlwaysLinearType (_, name, params, tdef, _) ->
    (* Format as `always_linear type Name(params) = ...` — always public;
       private variants are the `always_linear opaque type` spelling. *)
    let tkw = match tdef with
      | TDVariant (_ :: _ as vs) when List.for_all (fun v -> v.var_vis = Private) vs ->
        "always_linear opaque type"
      | _ -> "always_linear type" in
    let ps = match params with
      | []  -> ""
      | ps' -> Printf.sprintf "(%s)" (String.concat ", " (List.map (fun n -> n.txt) ps'))
    in
    (match tdef with
     | TDAlias ty ->
       line ctx (Printf.sprintf "%s %s%s = %s" tkw name.txt ps (fmt_ty ty))
     | TDVariant variants ->
       let var_str { var_name; var_args; var_vis = _ } =
         match var_args with
         | []  -> var_name.txt
         | tys -> Printf.sprintf "%s(%s)" var_name.txt (fmt_tys tys)
       in
       line ctx (Printf.sprintf "%s %s%s = %s" tkw name.txt ps
         (String.concat " | " (List.map var_str variants)))
     | TDRecord fields ->
       let fstrs = List.map (fun f ->
           Printf.sprintf "%s%s : %s" (fmt_lin f.fld_lin) f.fld_name.txt (fmt_ty f.fld_ty)
         ) fields in
       line ctx (Printf.sprintf "%s %s%s = { %s }" tkw name.txt ps (String.concat ", " fstrs))
    )

  (* `resource Name` parses to a variant type with no constructors; printed
     as `type Name = ` it no longer parsed. *)
  | DType (Public, name, [], TDVariant [], _) ->
    line ctx (Printf.sprintf "resource %s" name.txt)

  | DType (vis, name, params, tdef, _) ->
    (* `opaque type` is the only spelling of a public type whose variants are
       private; printed as `type` it silently exported the constructors. *)
    let opaque = match vis, tdef with
      | Public, TDVariant (_ :: _ as vs) -> List.for_all (fun v -> v.var_vis = Private) vs
      | _ -> false
    in
    let tkw = match vis with
      | Public -> if opaque then "opaque type" else "type"
      | Private -> "ptype" in
    let ps = match params with
      | []  -> ""
      | ps' -> Printf.sprintf "(%s)" (String.concat ", " (List.map (fun n -> n.txt) ps'))
    in
    (match tdef with
     | TDAlias ty ->
       line ctx (Printf.sprintf "%s %s%s = %s" tkw name.txt ps (fmt_ty ty))

     | TDVariant variants ->
       let var_str { var_name; var_args; var_vis = _ } =
         match var_args with
         | []  -> var_name.txt
         | tys -> Printf.sprintf "%s(%s)" var_name.txt (fmt_tys tys)
       in
       let all  = String.concat " | " (List.map var_str variants) in
       let full = Printf.sprintf "%s %s%s = %s" tkw name.txt ps all in
       if String.length full <= 80 then
         line ctx full
       else begin
         line ctx (Printf.sprintf "%s %s%s =" tkw name.txt ps);
         indented ctx (fun () ->
           List.iteri (fun i var ->
             let s = var_str var in
             if i = 0 then line ctx s
             else line ctx ("| " ^ s)
           ) variants
         )
       end

     | TDRecord fields ->
       (* Fields are comma-separated: { x : T, y : T } *)
       let fstrs = List.map (fun f ->
           Printf.sprintf "%s%s : %s" (fmt_lin f.fld_lin) f.fld_name.txt (fmt_ty f.fld_ty)
         ) fields in
       let inline = Printf.sprintf "%s %s%s = { %s }" tkw name.txt ps
           (String.concat ", " fstrs) in
       if String.length inline <= 80 then
         line ctx inline
       else begin
         line ctx (Printf.sprintf "%s %s%s = {" tkw name.txt ps);
         indented ctx (fun () ->
           let n = List.length fstrs in
           List.iteri (fun i s ->
             if i < n - 1 then line ctx (s ^ ",")
             else line ctx s
           ) fstrs
         );
         line ctx "}"
       end
    )

  | DMod (name, _vis, decls, _) ->
    line ctx (Printf.sprintf "mod %s do" name.txt);
    nl ctx;
    indented ctx (fun () -> emit_decls ctx decls);
    nl ctx;
    line ctx "end"

  | DInterface (iface, _) ->
    let supers = match iface.iface_superclasses with
      | [] -> ""
      | cs ->
        (* An interface's superclasses follow `requires` (an impl's
           constraints follow `when`). *)
        " requires " ^ String.concat ", "
          (List.map (fun (n, tys) ->
             if tys = [] then n.txt
             else Printf.sprintf "%s(%s)" n.txt (fmt_tys tys)) cs)
    in
    line ctx (Printf.sprintf "interface %s(%s)%s do"
      iface.iface_name.txt iface.iface_param.txt supers);
    indented ctx (fun () ->
      List.iter (fun m ->
        match m.md_default with
        | None ->
          line ctx (Printf.sprintf "fn %s : %s%s" m.md_name.txt (fmt_ty m.md_ty)
                      (fmt_needs m.md_needs))
        | Some def ->
          line ctx (Printf.sprintf "fn %s : %s%s do" m.md_name.txt (fmt_ty m.md_ty)
                      (fmt_needs m.md_needs));
          indented ctx (fun () -> emit_body ctx def);
          line ctx "end"
      ) iface.iface_methods;
      (* Laws: `@[lemma] fn name(params) : {Unit | P}`, no body. *)
      List.iter (fun (law : fn_def) ->
        List.iter (fun a -> line ctx (Printf.sprintf "@[%s]" a)) law.fn_attrs;
        let ps = match law.fn_clauses with
          | c :: _ -> String.concat ", " (List.map fmt_fn_param c.fc_params)
          | [] -> "" in
        let ret = match law.fn_ret_ty with Some t -> " : " ^ fmt_ty t | None -> "" in
        line ctx (Printf.sprintf "fn %s(%s)%s" law.fn_name.txt ps ret)
      ) iface.iface_laws
    );
    line ctx "end"

  | DImpl (impl, _) ->
    let cs = match impl.impl_constraints with
      | [] -> ""
      | cs ->
        " when " ^ String.concat ", "
          (List.map (fun (n, tys) ->
             if tys = [] then n.txt
             else Printf.sprintf "%s(%s)" n.txt (fmt_tys tys)) cs)
    in
    line ctx (Printf.sprintf "impl %s(%s)%s do"
      impl.impl_iface.txt (fmt_ty impl.impl_ty) cs);
    indented ctx (fun () ->
      let n = List.length impl.impl_methods in
      List.iteri (fun i (_, fn) ->
        emit_fn ctx fn;
        if i < n - 1 then nl ctx
      ) impl.impl_methods
    );
    line ctx "end"

  | DExtern (ext, _) ->
    line ctx (Printf.sprintf "extern %s : %s do"
      (quote_string ext.ext_lib_name) (fmt_ty ext.ext_cap_ty));
    indented ctx (fun () ->
      List.iter (fun ef ->
        let consumed i =
          match List.nth_opt ef.ef_param_consumed i with Some true -> "consume " | _ -> "" in
        let ps = String.concat ", "
          (List.mapi (fun i (n, t) ->
             Printf.sprintf "%s%s : %s" (consumed i) n.txt (fmt_ty t)) ef.ef_params) in
        let sym = match ef.ef_symbol with
          | Some s -> " = " ^ quote_string s
          | None -> "" in
        (* `blocking` / `raises` change how the binding is called; dropping
           them changed the program. *)
        let mods =
          (if ef.ef_blocking then "blocking " else "")
          ^ (if ef.ef_raises then "raises " else "") in
        line ctx (Printf.sprintf "%sfn %s(%s) : %s%s"
          mods ef.ef_name.txt ps (fmt_ty ef.ef_ret_ty) sym)
      ) ext.ext_fns
    );
    line ctx "end"

  | DUse (u, _) ->
    let path = String.concat "." (List.map (fun n -> n.txt) u.use_path) in
    (match u.use_sel with
     | UseAll      ->
       line ctx (Printf.sprintf "import %s" path)
     | UseNames ns ->
       line ctx (Printf.sprintf "import %s, only: [%s]" path
         (String.concat ", " (List.map (fun n -> n.txt) ns)))
     | UseSingle   ->
       (* `use A` brings in the module name only; `import A` is [UseAll]. *)
       line ctx (Printf.sprintf "use %s" path)
     | UseExcept ns ->
       line ctx (Printf.sprintf "import %s, except: [%s]" path
         (String.concat ", " (List.map (fun n -> n.txt) ns))))

  | DAlias (a, _) ->
    let path = String.concat "." (List.map (fun n -> n.txt) a.alias_path) in
    line ctx (Printf.sprintf "alias %s, as: %s" path a.alias_name.txt)

  | DNeeds (caps, _) ->
    (* The scope must round-trip: dropping it here would make `forge format`
       silently widen a capability. *)
    let cs = List.map
      (fun (cap, scope) ->
         let path = String.concat "." (List.map (fun n -> n.txt) cap) in
         match scope with
         | None -> path
         | Some sc -> Printf.sprintf "%s(%s)" path (quote_string sc)) caps in
    line ctx (Printf.sprintf "needs %s" (String.concat ", " cs))

  | DProofCap (name, dict, _) ->
    (* The `with <DictType>` clause must round-trip: dropping it here would
       silently erase a capability's dictionary type on every `--fmt`. *)
    line ctx
      (match dict with
       | None -> Printf.sprintf "proof cap %s" name.txt
       | Some d -> Printf.sprintf "proof cap %s with %s" name.txt d.txt)

  | DOpts (opts, _) ->
    (* The only surface spelling is `cap no_panic` and friends; there is no
       `opts` keyword, so emitting one produced a file that no longer parsed. *)
    List.iter (fun opt -> line ctx (Printf.sprintf "cap %s" opt)) opts

  | DProtocol (name, proto, _) ->
    List.iter (fun a -> line ctx (Printf.sprintf "@[%s]" a)) proto.proto_attrs;
    line ctx (Printf.sprintf "protocol %s do" name.txt);
    indented ctx (fun () ->
      List.iter (emit_proto_step ctx) proto.proto_steps);
    line ctx "end"

  | DActor (_vis, name, actor, _) ->
    line ctx (Printf.sprintf "actor %s do" name.txt);
    indented ctx (fun () ->
      if actor.actor_state <> [] then begin
        let fstrs = List.map (fun f ->
            Printf.sprintf "%s%s : %s" (fmt_lin f.fld_lin) f.fld_name.txt (fmt_ty f.fld_ty)
          ) actor.actor_state in
        line ctx (Printf.sprintf "state { %s }" (String.concat ", " fstrs))
      end;
      nl ctx;
      (if actor.actor_init_params = [] then line ctx "init do"
       else
         line ctx (Printf.sprintf "init(%s) do"
                     (String.concat ", " (List.map fmt_param actor.actor_init_params))));
      indented ctx (fun () -> emit_body ctx actor.actor_init);
      line ctx "end";
      List.iter (fun h ->
        nl ctx;
        let ps = String.concat ", " (List.map fmt_param h.ah_params) in
        line ctx (Printf.sprintf "on %s(%s) do" h.ah_msg.txt ps);
        indented ctx (fun () -> emit_body ctx h.ah_body);
        line ctx "end"
      ) actor.actor_handlers;
      Option.iter (fun h ->
        nl ctx;
        line ctx "on_stop do";
        indented ctx (fun () -> emit_body ctx h.ah_body);
        line ctx "end"
      ) actor.actor_on_stop
    );
    line ctx "end"

  | DSig (name, sig_, _) ->
    line ctx (Printf.sprintf "sig %s do" name.txt);
    indented ctx (fun () ->
      List.iter (fun (n, ps) ->
        let pstr = match ps with
          | [] -> ""
          | ps' -> Printf.sprintf "(%s)" (String.concat ", " (List.map (fun p -> p.txt) ps'))
        in
        line ctx (Printf.sprintf "type %s%s" n.txt pstr)
      ) sig_.sig_types;
      List.iter (fun (n, ty) ->
        line ctx (Printf.sprintf "fn %s : %s" n.txt (fmt_ty ty))
      ) sig_.sig_fns
    );
    line ctx "end"

  | DApp (app, _) ->
    line ctx (Printf.sprintf "app %s do" app.app_name.txt);
    indented ctx (fun () ->
      emit_body ctx app.app_body;
      (match app.app_on_start with
       | None -> ()
       | Some e ->
         nl ctx;
         line ctx "on_start do";
         indented ctx (fun () -> emit_body ctx e);
         line ctx "end");
      (match app.app_on_stop with
       | None -> ()
       | Some e ->
         nl ctx;
         line ctx "on_stop do";
         indented ctx (fun () -> emit_body ctx e);
         line ctx "end")
    );
    line ctx "end"

  | DDeriving (type_name, ifaces, _) ->
    line ctx (Printf.sprintf "derive %s for %s"
      (String.concat ", " (List.map (fun n -> n.txt) ifaces))
      type_name.txt)

  | DSatisfy (ifaces, types, _) ->
    line ctx (Printf.sprintf "satisfy %s for %s"
      (String.concat ", " (List.map (fun n -> n.txt) ifaces))
      (String.concat ", " (List.map (fun n -> n.txt) types)))

  | DTest (tdef, _) ->
    line ctx (Printf.sprintf "test %s do" (quote_string tdef.test_name));
    indented ctx (fun () -> emit_body ctx tdef.test_body);
    line ctx "end"

  | DSetup (body, _) ->
    line ctx "setup do";
    indented ctx (fun () -> emit_body ctx body);
    line ctx "end"

  | DSetupAll (body, _) ->
    line ctx "setup_all do";
    indented ctx (fun () -> emit_body ctx body);
    line ctx "end"

  | DDescribe (name, decls, _) ->
    line ctx (Printf.sprintf "describe %s do" (quote_string name));
    indented ctx (fun () -> List.iter (emit_decl ctx) decls);
    line ctx "end"

  | DTransitions (handle_ty, arms, _) ->
    line ctx (Printf.sprintf "transitions %s do" handle_ty.txt);
    indented ctx (fun () ->
      List.iter (fun (a : transition) ->
        line ctx (Printf.sprintf "%s: %s -> %s via %s"
          a.tr_resource.txt a.tr_from.txt a.tr_to.txt a.tr_via.txt)
      ) arms);
    line ctx "end"

and emit_fn ctx fn =
  let kw  = match fn.fn_vis with Public -> "fn" | Private -> "pfn" in
  (* `ghost fn` is written as a keyword, stored as the attribute "ghost". *)
  let kw  = if List.mem "ghost" fn.fn_attrs then "ghost " ^ kw else kw in
  let ret = match fn.fn_ret_ty with
    | None   -> ""
    | Some t -> Printf.sprintf " : %s" (fmt_ty t)
  in
  (* A per-function `needs` bound rides on the return annotation: printed on
     every clause of a multi-head function, like the return type, which the
     parser's clause merge accepts because the bounds are identical.
     Dropping it would silently widen the function to its module's needs. *)
  let ret = ret ^ fmt_needs fn.fn_needs in
  (match fn.fn_doc with
   | None -> ()
   | Some doc ->
     (* Always use triple-quoted strings for doc comments.
        Re-escape any `${` sequences so they are not lexed as string
        interpolation when the formatted output is re-parsed.
        Known limitation: doc strings containing triple-quotes will produce
        broken output — acceptable edge case for now. *)
     let escaped =
       let buf = Buffer.create (String.length doc) in
       let n = String.length doc in
       let i = ref 0 in
       while !i < n do
         if !i + 1 < n && doc.[!i] = '$' && doc.[!i+1] = '{' then begin
           Buffer.add_string buf "\\${";
           i := !i + 2
         end else begin
           Buffer.add_char buf doc.[!i];
           incr i
         end
       done;
       Buffer.contents buf
     in
     line ctx (Printf.sprintf "doc \"\"\"%s\"\"\"" escaped)
  );
  (* Compiler attributes (`@[no_warn_recursion]`, …). Dropping these is not a
     cosmetic loss: `@[no_warn_recursion]` suppresses a HARD ERROR, so a
     format-on-save that ate it turned a compiling file into one that no longer
     builds. Emitted for every clause because a multi-head function is printed
     as one `fn` declaration per clause, and the attribute binds to the
     declaration in the grammar (`nonempty_list(fn_attr); fn_decl`). *)
  let emit_attrs () =
    List.iter
      (fun a ->
        let text =
          match List.assoc_opt a fn.fn_attr_args with
          (* `@[decreases(e, ...)]`: the payload is expressions, kept apart
             from the name (termination design §2.1). *)
          | Some args ->
            Printf.sprintf "%s(%s)" a
              (String.concat ", " (List.map (render ctx.indent lv_expr) args))
          | None -> (
            (* A one-identifier payload is stored `name:value`; it is
               written `name(value)`. *)
            match String.index_opt a ':' with
            | Some i -> Printf.sprintf "%s(%s)" (String.sub a 0 i) (String.sub a (i + 1) (String.length a - i - 1))
            | None -> a)
        in
        line ctx (Printf.sprintf "@[%s]" text))
      (List.filter (fun a -> a <> "ghost") fn.fn_attrs)
  in
  match fn.fn_clauses with
  | [] -> ()
  | [clause] ->
    let ps    = String.concat ", " (List.map fmt_fn_param clause.fc_params) in
    let guard = match clause.fc_guard with
      | None   -> ""
      | Some g -> " when " ^ render ctx.indent lv_pipe g
    in
    emit_attrs ();
    line ctx (Printf.sprintf "%s %s(%s)%s%s do" kw fn.fn_name.txt ps ret guard);
    indented ctx (fun () -> emit_body ctx clause.fc_body);
    line ctx "end"
  | clauses ->
    (* Multi-clause function: emit each clause as its own fn declaration. *)
    let n = List.length clauses in
    List.iteri (fun i clause ->
      let ps    = String.concat ", " (List.map fmt_fn_param clause.fc_params) in
      let guard = match clause.fc_guard with
        | None   -> ""
        | Some g -> " when " ^ render ctx.indent lv_pipe g
      in
      emit_attrs ();
      line ctx (Printf.sprintf "%s %s(%s)%s%s do" kw fn.fn_name.txt ps ret guard);
      indented ctx (fun () -> emit_body ctx clause.fc_body);
      line ctx "end";
      if i < n - 1 then nl ctx
    ) clauses

and emit_proto_step ctx = function
  | ProtoMsg (s, r, t, label) ->
    let prefix = match label with Some l -> l.txt ^ ": " | None -> "" in
    line ctx (Printf.sprintf "%s%s -> %s : %s" prefix s.txt r.txt (fmt_ty t))
  | ProtoLoop (steps, atomic) ->
    line ctx (if atomic then "loop atomic do" else "loop do");
    indented ctx (fun () -> List.iter (emit_proto_step ctx) steps);
    line ctx "end"
  | ProtoStop _ ->
    line ctx "stop"
  | ProtoMayCrash (roles, _) ->
    line ctx (Printf.sprintf "may crash %s" (String.concat ", " (List.map (fun r -> r.txt) roles)))
  | ProtoRoleNeeds (role, caps, _) ->
    line ctx (Printf.sprintf "role %s needs %s" role.txt (String.concat ", " (List.map (fun c -> c.txt) caps)))
  | ProtoCrashOr (inner, crash, _) ->
    (match inner with
     | ProtoMsg (s, r, t, label) ->
       let prefix = match label with Some l -> l.txt ^ ": " | None -> "" in
       line ctx (Printf.sprintf "%s%s -> %s : %s or crash do" prefix s.txt r.txt (fmt_ty t))
     | _ -> emit_proto_step ctx inner; line ctx "or crash do");
    indented ctx (fun () -> List.iter (emit_proto_step ctx) crash);
    line ctx "end"
  | ProtoChoice (role, choices) ->
    line ctx (Printf.sprintf "choose by %s:" role.txt);
    indented ctx (fun () ->
      List.iter (fun (label, steps) ->
        line ctx (Printf.sprintf "%s ->" label.txt);
        indented ctx (fun () -> List.iter (emit_proto_step ctx) steps)
      ) choices
    );
    (* The block's own `end`.  Without it the enclosing loop's `end` closed
       the choice and the protocol's `end` closed the loop, so formatting any
       protocol with a choice produced a program that no longer parsed
       (witness: `--fmt` on specs/lang/types/accept/t105, 2026-09-11). *)
    line ctx "end"

(* ------------------------------------------------------------------ *)
(* Public entry points                                                 *)
(* ------------------------------------------------------------------ *)

(** Format a complete module.
    [src] is the original source text used to extract and re-insert comments. *)
let format_module ?(src = "") m =
  let comments = extract_comments src in
  let ctx = make_ctx comments in
  line ctx (Printf.sprintf "mod %s do" m.mod_name.txt);
  nl ctx;
  indented ctx (fun () -> emit_decls ctx m.mod_decls);
  nl ctx;
  line ctx "end";
  (* Ensure trailing newline *)
  let result = Buffer.contents ctx.buf in
  if result <> "" && result.[String.length result - 1] <> '\n' then
    result ^ "\n"
  else
    result

(* ------------------------------------------------------------------ *)
(* Round-trip safety net                                               *)
(* ------------------------------------------------------------------ *)

(** Structural equality of two parsed values (modules, exprs, …) that
    ignores source spans.

    The AST is plain immutable data (variants, records, lists, strings,
    ints, floats), so this walks the two representations in parallel.  A
    [March_ast.Ast.span] is the only five-field record in it whose first field
    is a string and whose other four are immediate ints; two such blocks
    always compare equal, which is what "the same AST shape" means after a
    reformat moves everything around.  Comments are not in the AST, so
    dropping one is not a difference this can see. *)
let equal_modulo_spans (a : 'a) (b : 'a) : bool =
  let is_span o =
    Obj.is_block o && Obj.tag o = 0 && Obj.size o = 5
    && (let f0 = Obj.field o 0 in Obj.is_block f0 && Obj.tag f0 = Obj.string_tag)
    && Obj.is_int (Obj.field o 1) && Obj.is_int (Obj.field o 2)
    && Obj.is_int (Obj.field o 3) && Obj.is_int (Obj.field o 4)
  in
  let rec eq a b =
    if Obj.is_int a || Obj.is_int b then a == b
    else if is_span a && is_span b then true
    else
      let ta = Obj.tag a in
      if ta <> Obj.tag b then false
      else if ta = Obj.string_tag then (Obj.obj a : string) = (Obj.obj b : string)
      else if ta = Obj.double_tag then
        Float.equal (Obj.obj a : float) (Obj.obj b : float)
      else if ta >= Obj.no_scan_tag then compare a b = 0
      else begin
        let n = Obj.size a in
        n = Obj.size b
        && (let rec go i = i >= n || (eq (Obj.field a i) (Obj.field b i) && go (i + 1)) in
            go 0)
      end
  in
  eq (Obj.repr a) (Obj.repr b)

(** Parse [src] (from [filename]) and format it.
    Raises the parser's exception on parse failure; see
    [format_source_result] for the reporting form. *)
let format_source ~filename src =
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
  let m = March_parser.Parse.module_of_lexbuf lexbuf in
  format_module ~src m

(** [format_source] with a round-trip check, for every caller that writes
    the result over the user's file: [Error msg] when [src] does not parse,
    or when the formatted text does not parse back to the same AST
    ([equal_modulo_spans]).  A formatter bug then refuses to format instead
    of destroying code (#1174, #1175). *)
let rec format_source_checked ~filename src : (string, string) result =
  match March_parser.Parse.module_ ~filename src with
  | Error diags ->
    Error
      (String.concat "\n"
         (List.map (fun d -> March_errors.Errors.render_diagnostic ~src ~filename d) diags))
  | Ok m ->
    let formatted = format_module ~src m in
    Result.map (fun () -> formatted) (verify_format_of ~filename m formatted)

(** [Ok ()] when [formatted], the formatter's output for the source [src],
    parses back to the same AST as [src]; otherwise [Error why], a sentence
    for the user.  Callers that already hold the formatted text (from
    [format_source_result]) use this before writing it anywhere. *)
and verify_format ~filename ~src formatted : (unit, string) result =
  match March_parser.Parse.module_ ~filename src with
  | Error _ -> Error "the input does not parse"
  | Ok m -> verify_format_of ~filename m formatted

and verify_format_of ~filename m formatted =
  match March_parser.Parse.module_ ~filename formatted with
  | Error diags ->
    let first = match diags with
      | d :: _ -> Printf.sprintf " (%s at line %d)" d.March_errors.Errors.message d.span.start_line
      | [] -> ""
    in
    Error (Printf.sprintf "the formatted output does not parse%s" first)
  | Ok m2 ->
    if equal_modulo_spans m m2 then Ok ()
    else Error "the formatted output parses to a different program"

(** [format_source] for callers that report the failure: a source that does
    not parse yields its diagnostics instead of an exception.  [stuck] is
    passed to {!March_parser.Parse.module_}. *)
let format_source_result ~filename ?stuck src =
  Result.map (format_module ~src)
    (March_parser.Parse.module_ ~filename ?stuck src)

(* Wire the refinement-predicate formatter now that [expr_inline] is in scope. *)
let () = fmt_pred_ref := expr_inline
