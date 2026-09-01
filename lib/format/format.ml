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

let fmt_lit = function
  | LitInt n    -> string_of_int n
  | LitFloat f  ->
    let s = string_of_float f in
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
    if String.contains s '\n' && String.length s > 10 then
      let triple = "\"\"\"" in
      triple ^ s ^ triple
    else
      "\"" ^ String.escaped s ^ "\""
  | LitBool b   -> if b then "true" else "false"
  | LitAtom s   -> ":" ^ s

(* ------------------------------------------------------------------ *)
(* Types                                                               *)
(* ------------------------------------------------------------------ *)

(* Forward reference to the inline expression formatter, used to render
   refinement predicates faithfully (so reformatting never drops the predicate).
   Assigned once [expr_inline] is in scope, at the bottom of this module. *)
let fmt_pred_ref : (expr -> string) ref = ref (fun _ -> "...")

let rec fmt_ty = function
  | TyCon ({ txt; _ }, [])   -> txt
  | TyCon ({ txt; _ }, args) -> Printf.sprintf "%s(%s)" txt (fmt_tys args)
  | TyVar { txt; _ }         -> txt
  | TyArrow (a, b)           -> Printf.sprintf "%s -> %s" (fmt_ty_atom a) (fmt_ty b)
  | TyTuple tys              -> Printf.sprintf "(%s)" (fmt_tys tys)
  | TyRecord flds            ->
    let f (n, t) = Printf.sprintf "%s : %s" n.txt (fmt_ty t) in
    Printf.sprintf "{ %s }" (String.concat ", " (List.map f flds))
  | TyLinear (lin, t)        ->
    (match lin with Unrestricted -> "" | Linear -> "linear " | Affine -> "affine ") ^ fmt_ty t
  | TyNat n                  -> string_of_int n
  | TyNatOp (op, a, b)       ->
    let s = match op with NatAdd -> "+" | NatMul -> "*" in
    Printf.sprintf "%s %s %s" (fmt_ty a) s (fmt_ty b)
  | TyChan (r, p)            -> Printf.sprintf "Chan(%s, %s)" r.txt p.txt
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
  | PatAs (p, n, _)               -> Printf.sprintf "%s as %s" (fmt_pat p) n.txt
  | PatOr (ps, _)                 -> String.concat " | " (List.map fmt_pat ps)

and fmt_pats ps = String.concat ", " (List.map fmt_pat ps)

(* ------------------------------------------------------------------ *)
(* Parameters                                                          *)
(* ------------------------------------------------------------------ *)

let fmt_lin = function
  | Unrestricted -> "" | Linear -> "linear " | Affine -> "affine "

let fmt_param p =
  let l = fmt_lin p.param_lin in
  match p.param_ty with
  | None    -> l ^ p.param_name.txt
  | Some ty -> Printf.sprintf "%s%s : %s" l p.param_name.txt (fmt_ty ty)

let fmt_fn_param = function
  | FPPat  p -> fmt_pat p
  | FPNamed p -> fmt_param p
  | FPDefault (p, _default_e) -> fmt_param p ^ " \\\\ _"

(** Render a lambda's parameter list, e.g. [x], [(a, b)], [()]. *)
let fmt_lam_params = function
  | []  -> "()"
  | [p] when p.param_ty = None -> p.param_name.txt
  | ps  -> Printf.sprintf "(%s)" (String.concat ", " (List.map fmt_param ps))

(* ------------------------------------------------------------------ *)
(* Infix operator handling                                            *)
(* ------------------------------------------------------------------ *)

(** Returns the precedence of a binary infix operator, or None if the
    operator name is not a known infix operator. *)
let infix_prec = function
  | "||"          -> Some 1
  | "&&"          -> Some 2
  | "==" | "!=" | "<" | ">" | "<=" | ">=" -> Some 3
  | "+" | "-" | "++" | "+." | "-."        -> Some 4
  | "*" | "/" | "%" | "*." | "/."         -> Some 5
  | _             -> None

(** True if this expression is a binary infix application. *)
let is_infix_app = function
  | EApp (EVar { txt; _ }, [_; _], _) -> infix_prec txt <> None
  | _ -> false

(** Get the infix precedence of an expression (for parenthesisation). *)
let expr_infix_prec = function
  | EApp (EVar { txt; _ }, [_; _], _) -> infix_prec txt
  | _ -> None

(* ------------------------------------------------------------------ *)
(* Expressions — inline (single-line) renderer                        *)
(* ------------------------------------------------------------------ *)

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
    the [string_concat3] folding that desugar applies afterwards.

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


(** Render an expression as a single line.  Used to measure width and
    decide whether to emit inline or break across multiple lines. *)
let rec expr_inline = function
  | ELit (lit, _)               -> fmt_lit lit
  | EVar { txt; _ }             -> txt
  (* Reconstruct list literals: Cons(a, Cons(b, Nil)) → [a, b] *)
  | ECon ({ txt = "Cons"; _ }, [_; _], _) as e ->
    (match try_collect_list [] e with
     | Some elems ->
       Printf.sprintf "[%s]" (String.concat ", " (List.map expr_inline elems))
     | None ->
       let[@warning "-8"] ECon ({ txt; _ }, args, _) = e in
       Printf.sprintf "%s(%s)" txt (String.concat ", " (List.map expr_inline args)))
  | ECon ({ txt = "Nil"; _ }, [], _) -> "[]"
  (* Reconstruct string interpolation: ++ chain → "${expr}" *)
  | EApp (EVar { txt = "++"; _ }, [_; _], _) as e
    when try_collect_interp e <> None ->
    let[@warning "-8"] Some (prefix, parts) = try_collect_interp e in
    let needs_triple = String.contains prefix '\n' ||
      List.exists (fun (_, s) -> String.contains s '\n') parts in
    let buf = Buffer.create 64 in
    if needs_triple then begin
      let triple = "\"\"\"" in
      Buffer.add_string buf triple;
      Buffer.add_string buf prefix;
      List.iter (fun (e, seg) ->
        Buffer.add_string buf "${";
        Buffer.add_string buf (expr_inline e);
        Buffer.add_char buf '}';
        Buffer.add_string buf seg
      ) parts;
      Buffer.add_string buf triple
    end else begin
      Buffer.add_char buf '"';
      Buffer.add_string buf (String.escaped prefix);
      List.iter (fun (e, seg) ->
        Buffer.add_string buf "${";
        Buffer.add_string buf (expr_inline e);
        Buffer.add_char buf '}';
        Buffer.add_string buf (String.escaped seg)
      ) parts;
      Buffer.add_char buf '"'
    end;
    Buffer.contents buf
  | EApp (EVar { txt = op; _ }, [a; b], _) when infix_prec op <> None ->
    (* Binary infix operator — render as  a op b  with precedence-correct parens *)
    let p    = Option.get (infix_prec op) in
    let la   = match expr_infix_prec a with Some pa -> pa < p  | None -> false in
    let rb   = match expr_infix_prec b with Some pb -> pb <= p | None -> false in
    let left = if la then Printf.sprintf "(%s)" (expr_inline a) else expr_inline a in
    let right= if rb then Printf.sprintf "(%s)" (expr_inline b) else expr_inline b in
    Printf.sprintf "%s %s %s" left op right
  | EApp (EVar { txt = "negate"; _ }, [e], _) ->
    (* Unary negation: -e *)
    if is_infix_app e then Printf.sprintf "-(%s)" (expr_inline e)
    else Printf.sprintf "-%s" (expr_inline e)
  | EApp (EVar { txt = "not"; _ }, [e], _) ->
    (* Logical not: !e *)
    if is_infix_app e then Printf.sprintf "!(%s)" (expr_inline e)
    else Printf.sprintf "!%s" (expr_inline e)
  | EApp (f, args, _)           ->
    Printf.sprintf "%s(%s)" (expr_inline f)
      (String.concat ", " (List.map expr_inline args))
  | ECon ({ txt; _ }, [], _)    -> txt
  | ECon ({ txt; _ }, args, _)  ->
    Printf.sprintf "%s(%s)" txt (String.concat ", " (List.map expr_inline args))
  | ELam (params, body, _)      ->
    Printf.sprintf "fn %s -> %s" (fmt_lam_params params) (expr_inline body)
  | EBlock ([], _)              -> ""
  | EBlock ([e], _)             -> expr_inline e
  | EBlock _                    -> "..."
  | ELet (b, _)                 ->
    let ty = match b.bind_ty with
      | None   -> ""
      | Some t -> Printf.sprintf " : %s" (fmt_ty t)
    in
    Printf.sprintf "let %s%s%s = %s"
      (fmt_lin b.bind_lin) (fmt_pat b.bind_pat) ty (expr_inline b.bind_expr)
  | EMatch _                    -> "match ..."
  | ETuple (es, _)              ->
    Printf.sprintf "(%s)" (String.concat ", " (List.map expr_inline es))
  | ERecord (flds, _)           ->
    let f (n, e) = Printf.sprintf "%s: %s" n.txt (expr_inline e) in
    Printf.sprintf "{ %s }" (String.concat ", " (List.map f flds))
  | ERecordUpdate (e, flds, _)  ->
    let f (n, v) = Printf.sprintf "%s: %s" n.txt (expr_inline v) in
    Printf.sprintf "{ %s with %s }" (expr_inline e)
      (String.concat ", " (List.map f flds))
  | EField (e, n, _)            -> Printf.sprintf "%s.%s" (expr_inline e) n.txt
  | EIf (c, t, e, _)           ->
    Printf.sprintf "if %s do %s else %s end"
      (expr_inline c) (expr_inline t) (expr_inline e)
  | EPipe (a, b, _)             ->
    Printf.sprintf "%s |> %s" (expr_inline a) (expr_inline b)
  | EAnnot (e, t, _)            ->
    Printf.sprintf "(%s : %s)" (expr_inline e) (fmt_ty t)
  | EHole (None, _)             -> "?"
  | EHole (Some n, _)           -> "?" ^ n.txt
  | EAtom (name, [], _)         -> ":" ^ name
  | EAtom (name, args, _)       ->
    Printf.sprintf ":%s(%s)" name (String.concat ", " (List.map expr_inline args))
  | ESend (cap, msg, _)         ->
    Printf.sprintf "send(%s, %s)" (expr_inline cap) (expr_inline msg)
  | ESpawn (a, _)               -> Printf.sprintf "spawn(%s)" (expr_inline a)
  | EResultRef None             -> "v"
  | EResultRef (Some n)         -> Printf.sprintf "v(%d)" n
  | EDbg (None, _)              -> "dbg()"
  | EDbg (Some e, _)            -> Printf.sprintf "dbg(%s)" (expr_inline e)
  | ELetFn (n, ps, ret, _, _)   ->
    let ty = match ret with None -> "" | Some t -> Printf.sprintf " : %s" (fmt_ty t) in
    Printf.sprintf "fn %s(%s)%s do ... end"
      n.txt (String.concat ", " (List.map fmt_param ps)) ty
  | ELetQ (p, r, _, _)          ->
    Printf.sprintf "let? %s = %s; ..." (fmt_pat p) (expr_inline r)
  | ELetStar (p, r, _, _)       ->
    Printf.sprintf "let* %s = %s; ..." (fmt_pat p) (expr_inline r)
  | EAssert (e, _)              -> Printf.sprintf "assert %s" (expr_inline e)
  | ESigil (name, content, _)     ->
    let inner = expr_inline content in
    Printf.sprintf "~%s%s" name inner
  | ECond _                     -> "match do ... end"

(** Returns true if the expression must be rendered on multiple lines
    (match, multi-statement block, local fn definition). *)
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

(** True when the last argument, followed through any chain of wrapper
    calls/constructors in tail position (e.g. [Thunk(fn _ -> ...)] passed
    as the last arg of [GenTree(...)]), bottoms out in a lambda whose body
    needs multi-line rendering — the "trailing block" call shape, e.g.
    [List.map(xs, fn x -> <multi-statement body> )]. *)
let rec is_multiline = function
  | EMatch _ | ELetFn _ | ELetQ _ | ELetStar _ -> true
  | EBlock (_ :: _ :: _, _) -> true
  | ESigil (_, content, _) -> sigil_is_multiline content
  | ELam (_, body, _) -> is_multiline body
  | EApp (_, args, _) | ECon (_, args, _) -> trailing_multiline args
  | _ -> false

and trailing_multiline args =
  match List.rev args with
  | ELam (_, body, _) :: _ -> is_multiline body
  | (EApp (_, a, _) | ECon (_, a, _)) :: _ -> trailing_multiline a
  | _ -> false

(** Returns true if we should break this expression across lines,
    considering the current indentation level. *)
let should_break indent_lvl expr =
  is_multiline expr ||
  String.length (expr_inline expr) + indent_lvl * 2 > 80

(* ------------------------------------------------------------------ *)
(* Expressions — block (multi-line) renderer                          *)
(* ------------------------------------------------------------------ *)

(** Emit expression [e] as one or more statements at current indentation. *)
let rec emit_stmt ctx e =
  match e with
  | EBlock (es, _) ->
    List.iter (emit_stmt ctx) es

  | ELet (b, _) ->
    let ty  = match b.bind_ty with
      | None   -> ""
      | Some t -> Printf.sprintf " : %s" (fmt_ty t)
    in
    let lhs = Printf.sprintf "let %s%s%s" (fmt_lin b.bind_lin) (fmt_pat b.bind_pat) ty in
    if should_break (ctx.indent + 1) b.bind_expr then begin
      line ctx (lhs ^ " =");
      indented ctx (fun () -> emit_stmt ctx b.bind_expr)
    end else
      line ctx (Printf.sprintf "%s = %s" lhs (expr_inline b.bind_expr))

  | EMatch (subj, arms, _) ->
    emit_match ctx subj arms

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
    if should_break (ctx.indent + 1) r then begin
      line ctx (Printf.sprintf "let? %s =" (fmt_pat p));
      indented ctx (fun () -> emit_stmt ctx r)
    end else
      line ctx (Printf.sprintf "let? %s = %s" (fmt_pat p) (expr_inline r));
    emit_stmt ctx cont

  | ELetStar (p, r, cont, _) ->
    if should_break (ctx.indent + 1) r then begin
      line ctx (Printf.sprintf "let* %s =" (fmt_pat p));
      indented ctx (fun () -> emit_stmt ctx r)
    end else
      line ctx (Printf.sprintf "let* %s = %s" (fmt_pat p) (expr_inline r));
    emit_stmt ctx cont

  | ESigil (name, content, _) when sigil_is_multiline content ->
    emit_sigil_multiline ctx name content

  | ELam (params, body, _) when is_multiline body ->
    line ctx (Printf.sprintf "fn %s ->" (fmt_lam_params params));
    indented ctx (fun () -> emit_body ctx body)

  | EApp (f, args, _) when trailing_multiline args ->
    emit_call_multiline ctx ~prefix:"" ~head:(expr_inline f) args

  | ECon (n, args, _) when trailing_multiline args ->
    emit_call_multiline ctx ~prefix:"" ~head:n.txt args

  | _ ->
    line ctx (expr_inline e)

(** Emit a call whose last argument, possibly through a chain of wrapper
    calls/constructors in tail position (e.g. [Thunk(fn _ -> ...)] as the
    last arg of [GenTree(...)]), bottoms out in a lambda needing a
    multi-line body:
      [Head(arg1, ..., Wrapper(fn params ->]
        <indented body>
      [))]
    [prefix] is prepended to the head line (e.g. ["|> "] inside a pipe
    chain); [head] is the already-rendered outermost callee. *)
and emit_call_multiline ctx ~prefix ~head args =
  let buf = Buffer.create 64 in
  Buffer.add_string buf prefix;
  let rec walk head args =
    let init_args, last = match List.rev args with
      | last :: rest -> (List.rev rest, last)
      | [] -> assert false
    in
    let sep = if init_args = [] then "" else ", " in
    let args_s = String.concat ", " (List.map expr_inline init_args) in
    match last with
    | ELam (params, body, _) ->
      Buffer.add_string buf
        (Printf.sprintf "%s(%s%sfn %s ->" head args_s sep (fmt_lam_params params));
      (body, 1)
    | EApp (f, nested_args, _) ->
      Buffer.add_string buf (Printf.sprintf "%s(%s%s" head args_s sep);
      let (body, depth) = walk (expr_inline f) nested_args in
      (body, depth + 1)
    | ECon (n, nested_args, _) ->
      Buffer.add_string buf (Printf.sprintf "%s(%s%s" head args_s sep);
      let (body, depth) = walk n.txt nested_args in
      (body, depth + 1)
    | _ -> assert false
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

and emit_match ctx subj arms =
  line ctx (Printf.sprintf "match %s do" (expr_inline subj));
  List.iter (fun arm ->
    let guard = match arm.branch_guard with
      | None   -> ""
      | Some g -> " when " ^ expr_inline g
    in
    let pat_s = fmt_pat arm.branch_pat ^ guard in
    let body  = arm.branch_body in
    if should_break (ctx.indent + 1) body then begin
      line ctx (Printf.sprintf "%s -> do" pat_s);
      indented ctx (fun () -> emit_body ctx body);
      line ctx "end"
    end else
      line ctx (Printf.sprintf "%s -> %s" pat_s (expr_inline body))
  ) arms;
  line ctx "end"

and emit_if ctx cond then_ else_ =
  let cs = expr_inline cond  in
  let ts = expr_inline then_ in
  let es = expr_inline else_ in
  let inline_len =
    ctx.indent * 2 + 3 + String.length cs + 4 + String.length ts + 6 + String.length es + 4
  in
  if not (is_multiline then_) && not (is_multiline else_) && inline_len <= 80 then
    line ctx (Printf.sprintf "if %s do %s else %s end" cs ts es)
  else begin
    line ctx (Printf.sprintf "if %s do" cs);
    emit_if_branch ctx then_;
    line ctx "else";
    emit_if_branch ctx else_;
    line ctx "end"
  end

(** Emit an if/then/else branch.  Multi-statement blocks must be wrapped in
    [do...end] because if-branches are [expr], not [block_body]. *)
and emit_if_branch ctx e =
  match e with
  | EBlock (_ :: _ :: _, _) ->
    (* Multi-statement: wrap in do...end *)
    indented ctx (fun () ->
      line ctx "do";
      indented ctx (fun () -> emit_body ctx e);
      line ctx "end")
  | EIf _ ->
    (* Nested if — emit directly at same indent (chained else-if) *)
    indented ctx (fun () -> emit_stmt ctx e)
  | _ ->
    indented ctx (fun () -> emit_stmt ctx e)

and emit_sigil_multiline ctx name content =
  (* Reconstruct the raw string with interpolation preserved *)
  let raw = match content with
    | ELit (LitString s, _) -> s
    | _ ->
      match try_collect_interp content with
      | Some (prefix, parts) ->
        let buf = Buffer.create 256 in
        Buffer.add_string buf prefix;
        List.iter (fun (e, seg) ->
          Buffer.add_string buf "${";
          Buffer.add_string buf (expr_inline e);
          Buffer.add_char buf '}';
          Buffer.add_string buf seg
        ) parts;
        Buffer.contents buf
      | None -> expr_inline content
  in
  let triple = "\"\"\"" in
  line ctx (Printf.sprintf "~%s%s" name triple);
  (* Output content lines at base_indent + 2.
     Strip common leading whitespace from the original, then re-indent. *)
  (* Strip leading newline (implicit from triple-quote on own line)
     and trailing newline+whitespace (from closing triple-quote on own line) *)
  let raw =
    let len = String.length raw in
    let start = if len > 0 && raw.[0] = '\n' then 1 else 0 in
    let stop = ref len in
    while !stop > start && (raw.[!stop - 1] = ' ' || raw.[!stop - 1] = '\n' || raw.[!stop - 1] = '\t') do
      decr stop
    done;
    if start = 0 && !stop = len then raw
    else String.sub raw start (!stop - start)
  in
  let content_lines = String.split_on_char '\n' raw in
  let base = (ctx.indent + 1) * 2 in
  let base_indent = String.make base ' ' in
  (* Find minimum leading spaces among non-empty lines *)
  let min_indent = List.fold_left (fun acc l ->
    if String.length l = 0 then acc
    else
      let spaces = ref 0 in
      while !spaces < String.length l && l.[!spaces] = ' ' do incr spaces done;
      min acc !spaces
  ) max_int content_lines in
  let min_indent = if min_indent = max_int then 0 else min_indent in
  List.iter (fun l ->
    if String.length l = 0 then
      Buffer.add_char ctx.buf '\n'
    else begin
      let stripped = if min_indent > 0 && String.length l >= min_indent
        then String.sub l min_indent (String.length l - min_indent)
        else l in
      Buffer.add_string ctx.buf base_indent;
      Buffer.add_string ctx.buf stripped;
      Buffer.add_char ctx.buf '\n'
    end
  ) content_lines;
  line ctx triple

and emit_pipe_chain ctx expr =
  (* Collect the pipe chain from left to right. *)
  let rec collect acc = function
    | EPipe (lhs, rhs, _) -> collect (rhs :: acc) lhs
    | e -> (e, acc)
  in
  let (head, stages) = collect [] expr in
  let any_multiline = is_multiline head || List.exists is_multiline stages in
  let head_s   = expr_inline head in
  let stage_ss = List.map expr_inline stages in
  let inline   =
    head_s ^ String.concat "" (List.map (fun s -> " |> " ^ s) stage_ss)
  in
  if not any_multiline && ctx.indent * 2 + String.length inline <= 80 then
    line ctx inline
  else begin
    (match head with
     | EApp (f, args, _) when trailing_multiline args ->
       emit_call_multiline ctx ~prefix:"" ~head:(expr_inline f) args
     | ECon (n, args, _) when trailing_multiline args ->
       emit_call_multiline ctx ~prefix:"" ~head:n.txt args
     | _ -> line ctx head_s);
    indented ctx (fun () ->
      List.iter (fun stage ->
        match stage with
        | EApp (f, args, _) when trailing_multiline args ->
          emit_call_multiline ctx ~prefix:"|> " ~head:(expr_inline f) args
        | ECon (n, args, _) when trailing_multiline args ->
          emit_call_multiline ctx ~prefix:"|> " ~head:n.txt args
        | _ -> line ctx ("|> " ^ expr_inline stage)
      ) stages)
  end

(* ------------------------------------------------------------------ *)
(* Declarations                                                        *)
(* ------------------------------------------------------------------ *)

(** Extract the span from any declaration (for comment flushing). *)
let get_span = function
  | DFn (_, s) | DLet (_, _, s) | DType (_, _, _, _, s) | DAlwaysLinearType (_, _, _, _, s)
  | DMod (_, _, _, s) | DProtocol (_, _, s) | DActor (_, _, _, s)
  | DSig (_, _, s) | DInterface (_, s) | DImpl (_, s) | DExtern (_, s)
  | DUse (_, s) | DAlias (_, s) | DNeeds (_, s) | DProofCap (_, s) | DApp (_, s)
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
      line ctx (Printf.sprintf "%s = %s" lhs (expr_inline b.bind_expr))

  | DAlwaysLinearType (_, name, params, tdef, _) ->
    (* Format as `always_linear type Name(params) = ...` — always public *)
    let tkw = "always_linear type" in
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

  | DType (vis, name, params, tdef, _) ->
    let tkw = match vis with Public -> "type" | Private -> "ptype" in
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
        " when " ^ String.concat ", "
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
          line ctx (Printf.sprintf "fn %s : %s" m.md_name.txt (fmt_ty m.md_ty))
        | Some def ->
          line ctx (Printf.sprintf "fn %s : %s do" m.md_name.txt (fmt_ty m.md_ty));
          indented ctx (fun () -> emit_body ctx def);
          line ctx "end"
      ) iface.iface_methods
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
    line ctx (Printf.sprintf "extern \"%s\" : %s do"
      ext.ext_lib_name (fmt_ty ext.ext_cap_ty));
    indented ctx (fun () ->
      List.iter (fun ef ->
        let consumed i =
          match List.nth_opt ef.ef_param_consumed i with Some true -> "consume " | _ -> "" in
        let ps = String.concat ", "
          (List.mapi (fun i (n, t) ->
             Printf.sprintf "%s%s : %s" (consumed i) n.txt (fmt_ty t)) ef.ef_params) in
        let sym = match ef.ef_symbol with
          | Some s -> Printf.sprintf " = %S" s
          | None -> "" in
        line ctx (Printf.sprintf "fn %s(%s) : %s%s"
          ef.ef_name.txt ps (fmt_ty ef.ef_ret_ty) sym)
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
       line ctx (Printf.sprintf "import %s" path)
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
         | Some sc -> Printf.sprintf "%s(%S)" path sc) caps in
    line ctx (Printf.sprintf "needs %s" (String.concat ", " cs))

  | DProofCap (name, _) ->
    line ctx (Printf.sprintf "proof cap %s" name.txt)

  | DOpts (opts, _) ->
    (* The only surface spelling is `cap no_panic` and friends; there is no
       `opts` keyword, so emitting one produced a file that no longer parsed. *)
    List.iter (fun opt -> line ctx (Printf.sprintf "cap %s" opt)) opts

  | DProtocol (name, proto, _) ->
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
      line ctx "init do";
      indented ctx (fun () -> emit_body ctx actor.actor_init);
      line ctx "end";
      List.iter (fun h ->
        nl ctx;
        let ps = String.concat ", " (List.map fmt_param h.ah_params) in
        line ctx (Printf.sprintf "on %s(%s) do" h.ah_msg.txt ps);
        indented ctx (fun () -> emit_body ctx h.ah_body);
        line ctx "end"
      ) actor.actor_handlers
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
    line ctx (Printf.sprintf "test \"%s\" do" tdef.test_name);
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
    line ctx (Printf.sprintf "describe %S do" name);
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
  let ret = match fn.fn_ret_ty with
    | None   -> ""
    | Some t -> Printf.sprintf " : %s" (fmt_ty t)
  in
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
  match fn.fn_clauses with
  | [] -> ()
  | [clause] ->
    let ps    = String.concat ", " (List.map fmt_fn_param clause.fc_params) in
    let guard = match clause.fc_guard with
      | None   -> ""
      | Some g -> " when " ^ expr_inline g
    in
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
        | Some g -> " when " ^ expr_inline g
      in
      line ctx (Printf.sprintf "%s %s(%s)%s%s do" kw fn.fn_name.txt ps ret guard);
      indented ctx (fun () -> emit_body ctx clause.fc_body);
      line ctx "end";
      if i < n - 1 then nl ctx
    ) clauses

and emit_proto_step ctx = function
  | ProtoMsg (s, r, t) ->
    line ctx (Printf.sprintf "%s -> %s : %s" s.txt r.txt (fmt_ty t))
  | ProtoLoop steps ->
    line ctx "loop do";
    indented ctx (fun () -> List.iter (emit_proto_step ctx) steps);
    line ctx "end"
  | ProtoStop _ ->
    line ctx "stop"
  | ProtoChoice (role, choices) ->
    line ctx (Printf.sprintf "choose by %s:" role.txt);
    indented ctx (fun () ->
      List.iter (fun (label, steps) ->
        line ctx (Printf.sprintf "%s ->" label.txt);
        indented ctx (fun () -> List.iter (emit_proto_step ctx) steps)
      ) choices
    )

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

(** Parse [src] (from [filename]) and format it.
    Raises [March_parser.Parser.Error] on parse failure. *)
let format_source ~filename src =
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
  let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  format_module ~src m

(* Wire the refinement-predicate formatter now that [expr_inline] is in scope. *)
let () = fmt_pred_ref := expr_inline
