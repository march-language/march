(** March parser — menhir specification.

    Syntax: ML/Elixir hybrid with do/end blocks, fn definitions
    with multi-head pattern matching, pipe operators, atoms,
    and block-scoped let bindings. *)

%{
  open March_ast.Ast
  let mk_span (s, e) =
    let open Lexing in
    { file = s.pos_fname;
      start_line = s.pos_lnum;
      start_col = s.pos_cnum - s.pos_bol;
      end_line = e.pos_lnum;
      end_col = e.pos_cnum - e.pos_bol }

  let mk_name id loc = { txt = id; span = mk_span loc }

  (** Group consecutive fn clauses with the same name into a single DFn.
      Clauses must be adjacent — interleaving with other decls is an error
      that we can catch later in a validation pass. *)
  let group_fn_clauses (decls : decl list) : decl list =
    let rec go acc = function
      | [] -> List.rev acc
      | DFn (def, span) :: rest ->
        let name = def.fn_name.txt in
        let ret = def.fn_ret_ty in
        let vis = def.fn_vis in
        let clauses = def.fn_clauses in
        let rec collect_same ret_acc clauses_acc = function
          | DFn (d, _) :: rest' when d.fn_name.txt = name ->
            let r = match ret_acc with Some _ -> ret_acc | None -> d.fn_ret_ty in
            collect_same r (clauses_acc @ d.fn_clauses) rest'
          | rest' -> (ret_acc, clauses_acc, rest')
        in
        let (final_ret, all_clauses, rest') = collect_same ret clauses rest in
        go (DFn ({ fn_name = def.fn_name; fn_vis = vis; fn_ret_ty = final_ret; fn_clauses = all_clauses }, span) :: acc) rest'
      | d :: rest -> go (d :: acc) rest
    in
    go [] decls
%}

%token <int> INT
%token <float> FLOAT
%token <string> STRING
%token <bool> BOOL
%token <string> ATOM
%token <string> LOWER_IDENT
%token <string> UPPER_IDENT
%token FN LET DO END IF THEN ELSE MATCH WITH WHEN
%token TYPE MOD ACTOR ON SEND SPAWN
%token STATE INIT RESPOND PROTOCOL LOOP
%token LINEAR AFFINE
%token PUB INTERFACE IMPL SIG EXTERN UNSAFE AS
%token LPAREN RPAREN LBRACE RBRACE LBRACKET RBRACKET
%token ARROW PIPE_ARROW
%token EQUALS COLON COMMA PIPE DOT
%token PLUSPLUS PLUS MINUS STAR SLASH PERCENT
%token LT GT EQEQ NEQ LEQ GEQ
%token AND OR BANG
%token UNDERSCORE QUESTION
%token EOF

%start <March_ast.Ast.module_> module_
%start <March_ast.Ast.expr> expr_eof
%start <March_ast.Ast.repl_input> repl_input

%%

(* ---- Module ---- *)

module_:
  | MOD; name = upper_name; DO; decls = list(decl); END; EOF
    { { mod_name = name; mod_decls = group_fn_clauses decls } }

(* ---- Declarations ---- *)

decl:
  | d = fn_decl    { d }
  | d = let_decl   { d }
  | d = type_decl  { d }
  | d = actor_decl { d }

(** Each fn clause is parsed as its own DFn with a single clause.
    The group_fn_clauses pass merges consecutive same-name clauses. *)
fn_decl:
  | FN; name = lower_name; LPAREN; params = separated_list(COMMA, fn_param); RPAREN;
    ret = option(ret_annot); guard = option(when_guard); DO; body = block_body; END
    { DFn ({ fn_name = name;
             fn_vis = Private;
             fn_ret_ty = ret;
             fn_clauses = [{ fc_params = params;
                             fc_guard = guard;
                             fc_body = body;
                             fc_span = mk_span ($loc) }] },
           mk_span ($loc)) }
  | PUB; FN; name = lower_name; LPAREN; params = separated_list(COMMA, fn_param); RPAREN;
    ret = option(ret_annot); guard = option(when_guard); DO; body = block_body; END
    { DFn ({ fn_name = name;
             fn_vis = Public;
             fn_ret_ty = ret;
             fn_clauses = [{ fc_params = params;
                             fc_guard = guard;
                             fc_body = body;
                             fc_span = mk_span ($loc) }] },
           mk_span ($loc)) }

when_guard:
  | WHEN; e = expr { e }

(** Function parameters: can be patterns (for head matching) or named params. *)
fn_param:
  | p = simple_pattern { FPPat p }
  | name = lower_name; COLON; t = ty
    { FPNamed { param_name = name; param_ty = Some t; param_lin = Unrestricted } }
  | LINEAR; name = lower_name; COLON; t = ty
    { FPNamed { param_name = name; param_ty = Some t; param_lin = Linear } }

let_decl:
  | LET; p = simple_pattern; ty = option(type_annot); EQUALS; e = expr
    { DLet ({ bind_pat = p; bind_ty = ty; bind_lin = Unrestricted; bind_expr = e },
            mk_span ($loc)) }

type_decl:
  | TYPE; name = upper_name; tparams = option(type_params); EQUALS;
    variants = separated_nonempty_list(PIPE, variant)
    { let tps = match tparams with Some ps -> ps | None -> [] in
      DType (name, tps, TDVariant variants, mk_span ($loc)) }
  | TYPE; name = upper_name; tparams = option(type_params); EQUALS;
    LBRACE; fields = separated_list(COMMA, field); RBRACE
    { let tps = match tparams with Some ps -> ps | None -> [] in
      DType (name, tps, TDRecord fields, mk_span ($loc)) }

actor_decl:
  | ACTOR; name = upper_name; DO;
    STATE; LBRACE; fields = separated_list(COMMA, field); RBRACE;
    INIT; init_expr = expr;
    handlers = list(actor_handler);
    END
    { DActor (name,
              { actor_state = fields; actor_init = init_expr; actor_handlers = handlers },
              mk_span ($loc)) }

actor_handler:
  | ON; msg = upper_name; LPAREN; params = separated_list(COMMA, param); RPAREN;
    DO; body = block_body; END
    { { ah_msg = msg; ah_params = params; ah_body = body } }

(* ---- Types ---- *)

type_annot:
  | COLON; t = ty { t }

ret_annot:
  | COLON; t = ty { t }

type_params:
  | LPAREN; ps = separated_nonempty_list(COMMA, lower_name); RPAREN { ps }

ty:
  | t = ty_app ARROW u = ty { TyArrow (t, u) }
  | t = ty_app { t }

ty_app:
  | id = upper_name; LPAREN; args = separated_nonempty_list(COMMA, ty); RPAREN
    { TyCon (id, args) }
  | t = ty_atom { t }

ty_atom:
  | id = LOWER_IDENT { TyVar (mk_name id $loc) }
  | id = upper_name { TyCon (id, []) }
  | LINEAR; t = ty_atom { TyLinear (Linear, t) }
  | AFFINE; t = ty_atom { TyLinear (Affine, t) }
  | LPAREN; t = ty; RPAREN { t }
  | LPAREN; t = ty; COMMA; ts = separated_nonempty_list(COMMA, ty); RPAREN
    { TyTuple (t :: ts) }

variant:
  | name = upper_name; LPAREN; args = separated_nonempty_list(COMMA, ty); RPAREN
    { { var_name = name; var_args = args } }
  | name = upper_name
    { { var_name = name; var_args = [] } }
  | a = ATOM; LPAREN; args = separated_nonempty_list(COMMA, ty); RPAREN
    { { var_name = mk_name a $loc; var_args = args } }
  | a = ATOM
    { { var_name = mk_name a $loc; var_args = [] } }

field:
  | name = lower_name; COLON; t = ty
    { { fld_name = name; fld_ty = t; fld_lin = Unrestricted } }
  | LINEAR; name = lower_name; COLON; t = ty
    { { fld_name = name; fld_ty = t; fld_lin = Linear } }

param:
  | name = lower_name; COLON; t = ty
    { { param_name = name; param_ty = Some t; param_lin = Unrestricted } }
  | name = lower_name
    { { param_name = name; param_ty = None; param_lin = Unrestricted } }
  | LINEAR; name = lower_name; COLON; t = ty
    { { param_name = name; param_ty = Some t; param_lin = Linear } }

(* ---- Expressions ---- *)

block_body:
  | es = nonempty_list(block_expr)
    { match es with [e] -> e | _ -> EBlock (es, mk_span ($loc)) }

block_expr:
  | LET; p = simple_pattern; ty = option(type_annot); EQUALS; e = expr
    { ELet ({ bind_pat = p; bind_ty = ty; bind_lin = Unrestricted; bind_expr = e },
            mk_span ($loc)) }
  | e = expr { e }

expr:
  | e = expr_pipe { e }
  | FN; ps = lambda_params; ARROW; body = expr
    { ELam (ps, body, mk_span ($loc)) }
  | IF; cond = expr; THEN; t = expr; ELSE; f = expr
    { EIf (cond, t, f, mk_span ($loc)) }
  | MATCH; e = expr; WITH; option(PIPE); bs = separated_nonempty_list(PIPE, branch); END
    { EMatch (e, bs, mk_span ($loc)) }

lambda_params:
  | name = lower_name { [{ param_name = name; param_ty = None; param_lin = Unrestricted }] }
  | LPAREN; ps = separated_list(COMMA, param); RPAREN
    { ps }

expr_pipe:
  | l = expr_pipe; PIPE_ARROW; r = expr_or
    { EPipe (l, r, mk_span ($loc)) }
  | e = expr_or { e }

expr_or:
  | a = expr_or; OR; b = expr_and { EApp (EVar (mk_name "||" $loc), [a; b], mk_span ($loc)) }
  | e = expr_and { e }

expr_and:
  | a = expr_and; AND; b = expr_cmp { EApp (EVar (mk_name "&&" $loc), [a; b], mk_span ($loc)) }
  | e = expr_cmp { e }

expr_cmp:
  | a = expr_add; EQEQ; b = expr_add { EApp (EVar (mk_name "==" $loc), [a; b], mk_span ($loc)) }
  | a = expr_add; NEQ; b = expr_add { EApp (EVar (mk_name "!=" $loc), [a; b], mk_span ($loc)) }
  | a = expr_add; LT; b = expr_add { EApp (EVar (mk_name "<" $loc), [a; b], mk_span ($loc)) }
  | a = expr_add; GT; b = expr_add { EApp (EVar (mk_name ">" $loc), [a; b], mk_span ($loc)) }
  | a = expr_add; LEQ; b = expr_add { EApp (EVar (mk_name "<=" $loc), [a; b], mk_span ($loc)) }
  | a = expr_add; GEQ; b = expr_add { EApp (EVar (mk_name ">=" $loc), [a; b], mk_span ($loc)) }
  | e = expr_add { e }

expr_add:
  | a = expr_add; PLUS; b = expr_mul { EApp (EVar (mk_name "+" $loc), [a; b], mk_span ($loc)) }
  | a = expr_add; MINUS; b = expr_mul { EApp (EVar (mk_name "-" $loc), [a; b], mk_span ($loc)) }
  | a = expr_add; PLUSPLUS; b = expr_mul { EApp (EVar (mk_name "++" $loc), [a; b], mk_span ($loc)) }
  | e = expr_mul { e }

expr_mul:
  | a = expr_mul; STAR;    b = expr_unary { EApp (EVar (mk_name "*"   $loc), [a; b], mk_span ($loc)) }
  | a = expr_mul; SLASH;   b = expr_unary { EApp (EVar (mk_name "/"   $loc), [a; b], mk_span ($loc)) }
  | a = expr_mul; PERCENT; b = expr_unary { EApp (EVar (mk_name "%"   $loc), [a; b], mk_span ($loc)) }
  | e = expr_unary { e }

(** Unary operators: -expr, !expr *)
expr_unary:
  | MINUS; e = expr_unary
    { EApp (EVar (mk_name "negate" $loc), [e], mk_span ($loc)) }
  | BANG; e = expr_unary
    { EApp (EVar (mk_name "not" $loc), [e], mk_span ($loc)) }
  | e = expr_app { e }

expr_app:
  | f = expr_field; LPAREN; args = separated_list(COMMA, expr); RPAREN
    { EApp (f, args, mk_span ($loc)) }
  | con = UPPER_IDENT; LPAREN; args = separated_nonempty_list(COMMA, expr); RPAREN
    { ECon (mk_name con $loc, args, mk_span ($loc)) }
  | e = expr_field { e }

(** Field access: x.name — left-recursive for chained access: x.y.z *)
expr_field:
  | e = expr_field; DOT; name = lower_name
    { EField (e, name, mk_span ($loc)) }
  | e = expr_atom { e }

expr_atom:
  | n = INT { ELit (LitInt n, mk_span ($loc)) }
  | f = FLOAT { ELit (LitFloat f, mk_span ($loc)) }
  | s = STRING { ELit (LitString s, mk_span ($loc)) }
  | b = BOOL { ELit (LitBool b, mk_span ($loc)) }
  | a = ATOM; LPAREN; args = separated_list(COMMA, expr); RPAREN
    { EAtom (a, args, mk_span ($loc)) }
  | a = ATOM
    { EAtom (a, [], mk_span ($loc)) }
  | id = LOWER_IDENT { EVar (mk_name id $loc) }
  | con = UPPER_IDENT { ECon (mk_name con $loc, [], mk_span ($loc)) }
  | QUESTION; id = option(LOWER_IDENT)
    { EHole (Option.map (fun i -> mk_name i $loc) id, mk_span ($loc)) }
  | LPAREN; e = expr; RPAREN { e }
  | LPAREN; e = expr; COMMA; es = separated_nonempty_list(COMMA, expr); RPAREN
    { ETuple (e :: es, mk_span ($loc)) }
  | LPAREN; RPAREN { ETuple ([], mk_span ($loc)) }
  | DO; body = block_body; END { body }
  (* List literals: [1, 2, 3]  →  Cons(1, Cons(2, Cons(3, Nil))) *)
  | LBRACKET; RBRACKET
    { ECon (mk_name "Nil" $loc, [], mk_span ($loc)) }
  | LBRACKET; elems = separated_nonempty_list(COMMA, expr); RBRACKET
    { let sp = mk_span ($loc) in
      List.fold_right
        (fun e acc -> ECon (mk_name "Cons" $loc, [e; acc], sp))
        elems
        (ECon (mk_name "Nil" $loc, [], sp)) }
  (* Record literal: { x = 1, y = 2 } *)
  | LBRACE; fields = separated_nonempty_list(COMMA, record_field_expr); RBRACE
    { ERecord (fields, mk_span ($loc)) }
  (* Record update: { state with count = state.count + 1 } *)
  | LBRACE; base = expr; WITH; updates = separated_nonempty_list(COMMA, record_field_expr); RBRACE
    { ERecordUpdate (base, updates, mk_span ($loc)) }

record_field_expr:
  | name = lower_name; EQUALS; e = expr { (name, e) }

branch:
  | p = pattern; guard = option(when_guard); ARROW; e = block_body
    { { branch_pat = p; branch_guard = guard; branch_body = e } }

(* ---- Patterns ---- *)

pattern:
  | con = upper_name; LPAREN; ps = separated_nonempty_list(COMMA, pattern); RPAREN
    { PatCon (con, ps) }
  | con = upper_name
    { PatCon (con, []) }
  | a = ATOM; LPAREN; ps = separated_nonempty_list(COMMA, pattern); RPAREN
    { PatAtom (a, ps, mk_span ($loc)) }
  | a = ATOM
    { PatAtom (a, [], mk_span ($loc)) }
  | p = simple_pattern { p }

simple_pattern:
  | UNDERSCORE { PatWild (mk_span ($loc)) }
  | id = lower_name { PatVar id }
  | n = INT { PatLit (LitInt n, mk_span ($loc)) }
  | MINUS; n = INT { PatLit (LitInt (-n), mk_span ($loc)) }
  | f = FLOAT { PatLit (LitFloat f, mk_span ($loc)) }
  | MINUS; f = FLOAT { PatLit (LitFloat (-.f), mk_span ($loc)) }
  | s = STRING { PatLit (LitString s, mk_span ($loc)) }
  | b = BOOL { PatLit (LitBool b, mk_span ($loc)) }
  | LPAREN; p = pattern; RPAREN { p }
  | LPAREN; p = pattern; COMMA; ps = separated_nonempty_list(COMMA, pattern); RPAREN
    { PatTuple (p :: ps, mk_span ($loc)) }

(* ---- Names ---- *)

lower_name:
  | id = LOWER_IDENT { mk_name id $loc }

upper_name:
  | id = UPPER_IDENT { mk_name id $loc }

expr_eof:
  | e = expr; EOF { e }

repl_input:
  | d = decl; EOF { March_ast.Ast.ReplDecl d }
  | e = expr; EOF { March_ast.Ast.ReplExpr e }
  | EOF           { March_ast.Ast.ReplEOF }
