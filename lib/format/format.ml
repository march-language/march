(** March source code formatter.

    Formats a March [module_] AST back to idiomatic, consistently-styled
    source text.  Rules (opinionated, gofmt-style):
      - 2-space indentation
      - 80-character soft line-width target
      - One blank line between top-level declarations
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

let fmt_lit = function
  | LitInt n    -> string_of_int n
  | LitFloat f  ->
    let s = string_of_float f in
    (* March requires digit+ '.' digit+ — ensure at least one digit after decimal *)
    if String.contains s 'e' then s  (* scientific notation: leave as-is *)
    else if not (String.contains s '.') then s ^ ".0"
    else begin
      (* If the string ends with '.', append '0' *)
      if s.[String.length s - 1] = '.' then s ^ "0"
      else s
    end
  | LitString s -> "\"" ^ String.escaped s ^ "\""
  | LitBool b   -> if b then "true" else "false"
  | LitAtom s   -> ":" ^ s

(* ------------------------------------------------------------------ *)
(* Types                                                               *)
(* ------------------------------------------------------------------ *)

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
      if ps = n.txt then n.txt else Printf.sprintf "%s = %s" n.txt ps
    in
    Printf.sprintf "{ %s }" (String.concat ", " (List.map f flds))
  | PatAs (p, n, _)               -> Printf.sprintf "%s as %s" (fmt_pat p) n.txt

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

(** Render an expression as a single line.  Used to measure width and
    decide whether to emit inline or break across multiple lines. *)
let rec expr_inline = function
  | ELit (lit, _)               -> fmt_lit lit
  | EVar { txt; _ }             -> txt
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
    let ps = match params with
      | []  -> "()"
      | [p] when p.param_ty = None -> p.param_name.txt
      | ps  -> Printf.sprintf "(%s)" (String.concat ", " (List.map fmt_param ps))
    in
    Printf.sprintf "fn %s -> %s" ps (expr_inline body)
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
    let f (n, e) = Printf.sprintf "%s = %s" n.txt (expr_inline e) in
    Printf.sprintf "{ %s }" (String.concat ", " (List.map f flds))
  | ERecordUpdate (e, flds, _)  ->
    let f (n, v) = Printf.sprintf "%s = %s" n.txt (expr_inline v) in
    Printf.sprintf "{ %s with %s }" (expr_inline e)
      (String.concat ", " (List.map f flds))
  | EField (e, n, _)            -> Printf.sprintf "%s.%s" (expr_inline e) n.txt
  | EIf (c, t, e, _)           ->
    Printf.sprintf "if %s then %s else %s"
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
  | EAssert (e, _)              -> Printf.sprintf "assert %s" (expr_inline e)

(** Returns true if the expression must be rendered on multiple lines
    (match, multi-statement block, local fn definition). *)
let is_multiline = function
  | EMatch _ | ELetFn _ -> true
  | EBlock (_ :: _ :: _, _) -> true
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

  | _ ->
    line ctx (expr_inline e)

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
      line ctx (Printf.sprintf "| %s ->" pat_s);
      indented ctx (fun () -> emit_body ctx body)
    end else
      line ctx (Printf.sprintf "| %s -> %s" pat_s (expr_inline body))
  ) arms;
  line ctx "end"

and emit_if ctx cond then_ else_ =
  let cs = expr_inline cond  in
  let ts = expr_inline then_ in
  let es = expr_inline else_ in
  let inline_len =
    ctx.indent * 2 + 3 + String.length cs + 6 + String.length ts + 6 + String.length es
  in
  if not (is_multiline then_) && not (is_multiline else_) && inline_len <= 80 then
    line ctx (Printf.sprintf "if %s then %s else %s" cs ts es)
  else begin
    line ctx (Printf.sprintf "if %s then" cs);
    emit_if_branch ctx then_;
    line ctx "else";
    emit_if_branch ctx else_
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

and emit_pipe_chain ctx expr =
  (* Collect the pipe chain from left to right. *)
  let rec collect acc = function
    | EPipe (lhs, rhs, _) -> collect (rhs :: acc) lhs
    | e -> (e, acc)
  in
  let (head, stages) = collect [] expr in
  let head_s   = expr_inline head in
  let stage_ss = List.map expr_inline stages in
  let inline   =
    head_s ^ String.concat "" (List.map (fun s -> " |> " ^ s) stage_ss)
  in
  if ctx.indent * 2 + String.length inline <= 80 then
    line ctx inline
  else begin
    line ctx head_s;
    indented ctx (fun () ->
      List.iter (fun s -> line ctx ("|> " ^ s)) stage_ss)
  end

(* ------------------------------------------------------------------ *)
(* Declarations                                                        *)
(* ------------------------------------------------------------------ *)

(** Extract the span from any declaration (for comment flushing). *)
let get_span = function
  | DFn (_, s) | DLet (_, _, s) | DType (_, _, _, _, s)
  | DMod (_, _, _, s) | DProtocol (_, _, s) | DActor (_, _, _, s)
  | DSig (_, _, s) | DInterface (_, s) | DImpl (_, s) | DExtern (_, s)
  | DUse (_, s) | DAlias (_, s) | DNeeds (_, s) | DApp (_, s)
  | DDeriving (_, _, s) | DTest (_, s) | DSetup (_, s) | DSetupAll (_, s) -> s

(** Emit a list of declarations separated by blank lines,
    flushing comments before each one. *)
let rec emit_decls ctx decls =
  let n = List.length decls in
  List.iteri (fun i decl ->
    let span = get_span decl in
    flush_comments_before ctx span.start_line;
    emit_decl ctx decl;
    if i < n - 1 then nl ctx
  ) decls

and emit_decl ctx = function
  | DFn (fn, _) ->
    emit_fn ctx fn

  | DLet (vis, b, _) ->
    let v   = match vis with Public -> "pub " | Private -> "" in
    let ty  = match b.bind_ty with None -> "" | Some t -> Printf.sprintf " : %s" (fmt_ty t) in
    let lhs = Printf.sprintf "%slet %s%s%s" v (fmt_lin b.bind_lin) (fmt_pat b.bind_pat) ty in
    if should_break (ctx.indent + 1) b.bind_expr then begin
      line ctx (lhs ^ " =");
      indented ctx (fun () -> emit_stmt ctx b.bind_expr)
    end else
      line ctx (Printf.sprintf "%s = %s" lhs (expr_inline b.bind_expr))

  | DType (vis, name, params, tdef, _) ->
    let v  = match vis with Public -> "pub " | Private -> "" in
    let ps = match params with
      | []  -> ""
      | ps' -> Printf.sprintf "(%s)" (String.concat ", " (List.map (fun n -> n.txt) ps'))
    in
    (match tdef with
     | TDAlias ty ->
       line ctx (Printf.sprintf "%stype %s%s = %s" v name.txt ps (fmt_ty ty))

     | TDVariant variants ->
       let var_str { var_name; var_args; var_vis } =
         let vis = match var_vis with Public -> "pub " | Private -> "" in
         match var_args with
         | []  -> vis ^ var_name.txt
         | tys -> Printf.sprintf "%s%s(%s)" vis var_name.txt (fmt_tys tys)
       in
       let all  = String.concat " | " (List.map var_str variants) in
       let full = Printf.sprintf "%stype %s%s = %s" v name.txt ps all in
       if String.length full <= 80 then
         line ctx full
       else begin
         line ctx (Printf.sprintf "%stype %s%s =" v name.txt ps);
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
       let inline = Printf.sprintf "%stype %s%s = { %s }" v name.txt ps
           (String.concat ", " fstrs) in
       if String.length inline <= 80 then
         line ctx inline
       else begin
         line ctx (Printf.sprintf "%stype %s%s = {" v name.txt ps);
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

  | DMod (name, vis, decls, _) ->
    let v = match vis with Public -> "pub " | Private -> "" in
    line ctx (Printf.sprintf "%smod %s do" v name.txt);
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
        let ps = String.concat ", "
          (List.map (fun (n, t) ->
             Printf.sprintf "%s : %s" n.txt (fmt_ty t)) ef.ef_params) in
        line ctx (Printf.sprintf "fn %s(%s) : %s"
          ef.ef_name.txt ps (fmt_ty ef.ef_ret_ty))
      ) ext.ext_fns
    );
    line ctx "end"

  | DUse (u, _) ->
    let path = String.concat "." (List.map (fun n -> n.txt) u.use_path) in
    (match u.use_sel with
     | UseAll      ->
       line ctx (Printf.sprintf "use %s.*" path)
     | UseNames ns ->
       line ctx (Printf.sprintf "use %s.{%s}" path
         (String.concat ", " (List.map (fun n -> n.txt) ns)))
     | UseSingle   ->
       line ctx (Printf.sprintf "use %s" path)
     | UseExcept ns ->
       line ctx (Printf.sprintf "use %s except: [%s]" path
         (String.concat ", " (List.map (fun n -> n.txt) ns))))

  | DAlias (a, _) ->
    let path = String.concat "." (List.map (fun n -> n.txt) a.alias_path) in
    line ctx (Printf.sprintf "alias %s, as: %s" path a.alias_name.txt)

  | DNeeds (caps, _) ->
    let cs = List.map
      (fun cap -> String.concat "." (List.map (fun n -> n.txt) cap)) caps in
    line ctx (Printf.sprintf "needs %s" (String.concat ", " cs))

  | DProtocol (name, proto, _) ->
    line ctx (Printf.sprintf "protocol %s do" name.txt);
    indented ctx (fun () ->
      List.iter (emit_proto_step ctx) proto.proto_steps);
    line ctx "end"

  | DActor (vis, name, actor, _) ->
    let v = match vis with Public -> "pub " | Private -> "" in
    line ctx (Printf.sprintf "%sactor %s do" v name.txt);
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

and emit_fn ctx fn =
  let v   = match fn.fn_vis with Public -> "pub " | Private -> "" in
  let ret = match fn.fn_ret_ty with
    | None   -> ""
    | Some t -> Printf.sprintf " : %s" (fmt_ty t)
  in
  (match fn.fn_doc with
   | None -> ()
   | Some doc ->
     (* Always use triple-quoted strings for doc comments.
        This preserves non-ASCII bytes verbatim and avoids the dollar-brace
        sequence being lexed as string interpolation.
        Known limitation: doc strings containing triple-quotes will produce
        broken output — acceptable edge case for now. *)
     line ctx (Printf.sprintf "doc \"\"\"%s\"\"\"" doc)
  );
  match fn.fn_clauses with
  | [] -> ()
  | [clause] ->
    let ps    = String.concat ", " (List.map fmt_fn_param clause.fc_params) in
    let guard = match clause.fc_guard with
      | None   -> ""
      | Some g -> " when " ^ expr_inline g
    in
    line ctx (Printf.sprintf "%sfn %s(%s)%s%s do" v fn.fn_name.txt ps ret guard);
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
      line ctx (Printf.sprintf "%sfn %s(%s)%s%s do" v fn.fn_name.txt ps ret guard);
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
  let m = March_parser.Parser.module_ March_lexer.Lexer.token lexbuf in
  format_module ~src m
