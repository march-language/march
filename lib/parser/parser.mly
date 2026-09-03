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

  (* ── Multi-error recovery ────────────────────────────────────────────── *)

  (** Delegate to Parse_errors module so callers outside the parser can
      access collected errors via March_parser.Parse_errors.take_parse_errors. *)
  let _collect_parse_error = Parse_errors.collect_parse_error

  (** Collect a parse error into the buffer and then raise [ParseError].
      Use this in sub-production error rules where Menhir requires the action
      to abort (assert false is generated after the action otherwise). *)
  let error_raise msg hint pos =
    Parse_errors.collect_parse_error msg hint pos;
    raise (March_errors.Errors.ParseError (msg, hint, pos))

  (* Desugar a string interpolation into a `++` chain + to_string calls:
       prefix ++ to_string(e1) ++ s1 ++ to_string(e2) ++ s2 ++ ...
     where to_string is the polymorphic builtin.

     A left-deep `++` chain re-copies the growing prefix at every link, which
     would be O(k^2) for k parts — but desugar collapses chains of 3+ into
     three-way concats (lib/desugar/desugar.ml, fold_concat3), so the emitted
     chain costs ceil((k-1)/2) allocations and no intermediate list.

     This deliberately emits ONE shape.  An earlier version emitted
     `string_join` over a cons list past a part-count threshold, which was a
     win against a raw `++` chain but is a LOSS against concat3 folding: the
     list costs a cons cell per part.  Measured on current main, 7 segments at
     2M iterations — `string_join` 519ms (1 string + 8 cons cells per
     iteration) against concat3 folding at 287ms (3 strings, no cons cells).
     Interpolation was 1.8x slower than writing the identical thing with `++`.

     Emitting one shape also removes a standing hazard: the formatter
     reconstructs `"${...}"` source from this AST (lib/format/format.ml,
     try_collect_interp) and the ~H sigil lowering decomposes it part-wise
     (lib/desugar/desugar.ml, decompose_concat).  Every extra shape has to be
     taught to both, and twice now a missing case there silently disabled HTML
     auto-escaping — a failure that fails OPEN. *)
  let desugar_interp prefix parts sp =
    let to_s e = EApp (EVar { txt = "to_string"; span = sp }, [e], sp) in
    let cat a b = EApp (EVar { txt = "++"; span = sp }, [a; b], sp) in
    List.fold_left (fun acc (e, seg) ->
        let with_e = cat acc (to_s e) in
        if seg = "" then with_e
        else cat with_e (ELit (LitString seg, sp))
      ) prefix parts

  (** Join a dotted module path into a single name, e.g. [A; B; C] → "A.B.C".
      Used for `mod A.B.C do ... end` declarations. *)
  let join_mod_path names =
    match names with
    | [] -> assert false
    | [n] -> n
    | first :: _ ->
      let txt = String.concat "." (List.map (fun (n : name) -> n.txt) names) in
      { txt; span = first.span }

  (** Group consecutive fn clauses with the same name into a single DFn.

      Clauses must be adjacent (B14): the merger below keys on the function
      NAME only and merges only ADJACENT same-name clauses, so a same-name
      group reappearing later at the same level (interleaved with another
      decl) would leave the earlier group silently shadowed/unreachable.
      The validation pass after grouping rejects that with a positioned
      error. The check deliberately uses the same name-only key as the
      merger: same-name different-arity fns are not separate functions in
      March — adjacent ones merge into one multi-head def — so a repeated
      name at one level is always an adjacency mistake. *)
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
        go (DFn ({ fn_name = def.fn_name; fn_vis = vis; fn_doc = def.fn_doc; fn_attrs = def.fn_attrs; fn_ret_ty = final_ret; fn_clauses = all_clauses; fn_bounds = def.fn_bounds }, span) :: acc) rest'
      | d :: rest -> go (d :: acc) rest
    in
    let grouped = go [] decls in
    (* Validation: a DFn name occurring twice in the grouped output means
       the clause groups were non-adjacent at this level. *)
    let seen : (string, span) Hashtbl.t = Hashtbl.create 8 in
    List.iter (fun d ->
        match d with
        | DFn (def, span) ->
          let name = def.fn_name.txt in
          (match Hashtbl.find_opt seen name with
           | Some first_span ->
             let pos = { Lexing.pos_fname = span.file;
                         pos_lnum = span.start_line;
                         pos_bol  = 0;
                         pos_cnum = span.start_col } in
             error_raise
               (Printf.sprintf
                  "clauses of `%s` must be adjacent; earlier clauses at line %d \
                   would be silently unreachable"
                  name first_span.start_line)
               (Some (Printf.sprintf
                        "Move the clauses next to each other:\n\
                         fn %s(...) do ... end\n\
                         fn %s(...) do ... end"
                        name name))
               pos
           | None -> Hashtbl.add seen name span)
        | _ -> ()) grouped;
    grouped

  (** Build a lambda from a pattern and body for comprehension desugaring.
      PatVar names become a simple named param.
      All other patterns wrap in a match. *)
  let mk_comp_lambda pat body sp =
    match pat with
    | PatVar name ->
      ELam ([{ param_name = name; param_ty = None; param_lin = Unrestricted }], body, sp)
    | _ ->
      let arg = { txt = "__celem"; span = sp } in
      let br = { branch_pat = pat; branch_guard = None; branch_body = body } in
      ELam (
        [{ param_name = arg; param_ty = None; param_lin = Unrestricted }],
        EMatch (EVar arg, [br], sp),
        sp)

  (** [x * 2 for x in xs]         → List.map(xs, fn x -> x * 2)
      [x * 2 for x in xs, x > 3]  → List.map(List.filter(xs, fn x -> x > 3), fn x -> x * 2) *)
  let desugar_list_comp body pat src pred_opt sp =
    let map_lam    = mk_comp_lambda pat body sp in
    let mk_var txt = EVar { txt; span = sp } in
    let source = match pred_opt with
      | None -> src
      | Some pred ->
        let filter_lam = mk_comp_lambda pat pred sp in
        EApp (mk_var "List.filter", [src; filter_lam], sp)
    in
    EApp (mk_var "List.map", [source; map_lam], sp)

  (** Right-fold a flat block list into nested [ELetQ]/[ELetStar] continuations.
      [let? p = e; rest...] becomes [ELetQ(p, e, fold_letq rest sp, sp)], and
      likewise [let* p = e; rest...] becomes [ELetStar(p, e, fold_letq rest sp, sp)]
      -- both binder forms share this fold since they have the same
      (pattern, rhs, continuation, span) shape and a block may freely mix them.
      Non-binder expressions are collected into [EBlock] as before.
      A binder as the very last expression produces e.g. [ELetQ(p, e, EBlock([], sp), sp)];
      the typechecker flags the empty continuation with a clear error. *)
  let rec fold_letq es sp =
    match es with
    | [] -> EBlock ([], sp)
    | [ e ] -> e
    | ELetQ (p, result, _, lsp) :: rest ->
        ELetQ (p, result, fold_letq rest sp, lsp)
    | ELetStar (p, result, _, lsp) :: rest ->
        ELetStar (p, result, fold_letq rest sp, lsp)
    | e :: rest ->
        (match fold_letq rest sp with
         | EBlock (inner, bsp) -> EBlock (e :: inner, bsp)
         | other               -> EBlock ([e; other], sp))

  (** Build nested EMatch for a `with` expression.
      with Ok(a) <- e1, Ok(b) <- e2 do body else Err(x) -> h end
      → match e1 do Ok(a) -> match e2 do Ok(b) -> body | Err(x) -> h end | Err(x) -> h end *)
  let rec build_with bindings body else_arms sp =
    match bindings with
    | [] -> body
    | (pat, e) :: rest ->
      let inner = build_with rest body else_arms sp in
      let ok_br = { branch_pat = pat; branch_guard = None; branch_body = inner } in
      EMatch (e, ok_br :: else_arms, sp)
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
%token STATE INIT PROTOCOL LOOP
%token LINEAR AFFINE
%token INTERFACE IMPL SIG EXTERN AS USE NEEDS REQUIRES PROOFCAP ALWAYSLINEAR TAG TRANSITIONS VIA CAP_NO_PANIC CAP_PURE CAP_NO_EXTERN CAP_DETERMINISTIC CAP_NO_ALLOC CAP_VERIFIED
%token IMPORT ALIAS ONLY EXCEPT PFN PTYPE DERIVE SATISFY FOR IN OPAQUE GETS DSLASH
%token RESOURCE
%token APP ON_START ON_STOP
%token CHOOSE BY OFFER
%token TEST DESCRIBE ASSERT SETUP SETUP_ALL
%token DBG DOC
%token <string> SIGIL_PREFIX
%token SUPERVISE STRATEGY MAX_RESTARTS WITHIN
%token ONE_FOR_ONE ONE_FOR_ALL REST_FOR_ONE
%token RESTART PERMANENT TRANSIENT TEMPORARY
%token <string> INTERP_START
%token <string> INTERP_MID
%token <string> INTERP_END
%token LPAREN RPAREN LBRACE RBRACE LBRACKET RBRACKET
(* [LPAREN_STMT] is a `(` that opens a NEW statement: the token filter emits it
   in place of [LPAREN] when a newline separates the `(` from a value-ending
   token (grammar §7.3 — `f(1)⏎(g(2))` is two statements, not a curried call).
   It is accepted only by the group/tuple/unit rules in [expr_atom], never by
   the call rule, so a `(`-led line can no longer be glommed onto the previous
   line's trailing expression as an argument list. *)
%token LPAREN_STMT
%token AT INVARIANT
%token ARROW PIPE_ARROW
%token EQUALS COLON COMMA PIPE DOT
%token PLUSPLUS PLUS MINUS STAR SLASH PERCENT
%token PLUSDOT MINUSDOT STARDOT SLASHDOT
%token LT GT EQEQ NEQ LEQ GEQ
%token AND OR BANG
%token UNDERSCORE QUESTION
%token NL
%token EOF

(* Precedence declarations. Listed lowest to highest.
   Virtual tokens (prec_hole, prec_atom, prec_app) are never emitted by
   the lexer; they exist solely to annotate grammar rules with %prec so
   that menhir can resolve shift/reduce conflicts explicitly rather than
   arbitrarily.
     prec_hole: bare ? hole; below LOWER_IDENT so ?foo shifts the ident.
     prec_atom: bare UPPER_IDENT or ATOM; below LPAREN so Foo() shifts (.
     prec_app:  expr_field pass-through; below LPAREN so f() shifts (. *)
%nonassoc prec_hole
%nonassoc LOWER_IDENT
%nonassoc prec_atom
%nonassoc EQEQ NEQ LT GT LEQ GEQ
%left     MINUS
%nonassoc prec_app
%nonassoc LPAREN

%start <March_ast.Ast.module_> module_
%start <March_ast.Ast.expr> expr_eof
%start <March_ast.Ast.repl_input> repl_input
%start <March_ast.Ast.repl_input list> repl_sequence
%start <March_ast.Ast.ty> ty_eof

%%

(* ---- Module ---- *)

module_:
  | MOD; path = upper_dot_path; DO; decls = decl_list_r; END; EOF
    { let name = join_mod_path path in
      { mod_name = name; mod_decls = group_fn_clauses decls } }
  (* A complete top-level `mod ... end` followed by anything other than EOF.
     March files hold exactly one top-level module; sibling top-level
     declarations (functions, types, …) are not allowed — they must live
     inside the module.  Give a precise diagnostic instead of menhir's
     generic "I got stuck here". *)
  | MOD; _path = upper_dot_path; DO; _decls = decl_list_r; END; error
    { raise (March_errors.Errors.ParseError (
        "A file may have only one top-level `mod`; \
         everything else must live inside it.",
        Some "mod Name do\n    fn helper() do ... end\n    fn main() do ... end\nend",
        $startpos($6))) }
  | MOD; _n = upper_dot_path; error
    { raise (March_errors.Errors.ParseError (
        "I was expecting `do` to start the module body here:",
        Some "mod Name do\n    ...\nend",
        $startpos($3))) }
  | error
    { raise (March_errors.Errors.ParseError (
        "March programs must start with a module declaration:",
        Some "mod Main do\n    fn main() do\n        ...\n    end\nend",
        $startpos($1))) }

(** Recoverable declaration list.  On error, collects the diagnostic and
    skips tokens (via Menhir's default error-recovery token-dropping)
    until the parser can shift a sync token that starts a new declaration
    (FN, PFN, TYPE, PTYPE, LET, MOD, etc.) or END/EOF to close the block.
    Capped at 20 errors to suppress cascading noise. *)
decl_list_r:
  | { [] }
  | ds = decl_list_r; d = decl { ds @ [d] }
  | ds = decl_list_r; error
    { ignore ds;
      error_raise "Parse error in declaration" None $startpos($2) }

(* ---- Declarations ---- *)

fn_attr:
  | AT; LBRACKET; name = LOWER_IDENT; RBRACKET { name }
  | AT; name = LOWER_IDENT; LPAREN; value = LOWER_IDENT; RPAREN { name ^ ":" ^ value }
  | AT; LBRACKET; name = LOWER_IDENT; LPAREN; value = LOWER_IDENT; RPAREN; RBRACKET
      { name ^ ":" ^ value }

decl:
  | DOC; s = STRING; d = fn_decl
    { match d with
      | DFn (def, span) -> DFn ({ def with fn_doc = Some s }, span)
      | d -> d }
  | attrs = nonempty_list(fn_attr); d = fn_decl
    { (* @[no_alloc] takes exactly two payloads; anything else is a typo, not
         a silently-ignored attribute (see lib/tir/alloc_contract.ml). *)
      List.iter (fun a ->
          if String.length a > 9 && String.sub a 0 9 = "no_alloc:"
             && a <> "no_alloc:warn" && a <> "no_alloc:assume" then
            error_raise
              (Printf.sprintf
                 "I don't recognize `@[no_alloc(%s)]` \xe2\x80\x94 the forms are `@[no_alloc]`, `@[no_alloc(warn)]`, and `@[no_alloc(assume)]`."
                 (String.sub a 9 (String.length a - 9)))
              None $startpos(attrs)) attrs;
      match d with
      | DFn (def, span) -> DFn ({ def with fn_attrs = attrs }, span)
      | d -> d }
  | attrs = nonempty_list(fn_attr); d = actor_decl
    { if List.exists (fun a -> a = "no_alloc"
                        || (String.length a > 9 && String.sub a 0 9 = "no_alloc:")) attrs then
        error_raise "`@[no_alloc]` only applies to `fn` and `pfn` declarations, not to actors." None $startpos(attrs);
      let compat = List.fold_left (fun acc a ->
          let n = String.length a in
          if n > 7 && String.sub a 0 7 = "compat:" then String.sub a 7 (n - 7) else acc
        ) "full" attrs in
      match d with
      | DActor (vis, name, adef, span) -> DActor (vis, name, { adef with actor_compat = compat }, span)
      | d -> d }
  | AT; INVARIANT; LPAREN; inv = expr; RPAREN; d = actor_decl
    { match d with
      | DActor (vis, name, adef, span) ->
        DActor (vis, name, { adef with actor_invariant = Some inv }, span)
      | d -> d }
  | AT; INVARIANT; LPAREN; inv = expr; RPAREN; attrs = nonempty_list(fn_attr); d = actor_decl
    { if List.exists (fun a -> a = "no_alloc"
                        || (String.length a > 9 && String.sub a 0 9 = "no_alloc:")) attrs then
        error_raise "`@[no_alloc]` only applies to `fn` and `pfn` declarations, not to actors." None $startpos(attrs);
      let compat = List.fold_left (fun acc a ->
          let n = String.length a in
          if n > 7 && String.sub a 0 7 = "compat:" then String.sub a 7 (n - 7) else acc
        ) "full" attrs in
      match d with
      | DActor (vis, name, adef, span) ->
        DActor (vis, name, { adef with actor_invariant = Some inv; actor_compat = compat }, span)
      | d -> d }
  | d = fn_decl        { d }
  | d = let_decl       { d }
  | d = type_decl      { d }
  | d = actor_decl     { d }
  | d = interface_decl { d }
  | d = impl_decl      { d }
  | d = sig_decl       { d }
  | d = extern_decl    { d }
  | d = resource_decl  { d }
  | d = mod_decl       { d }
  | d = use_decl       { d }
  | d = import_decl    { d }
  | d = alias_decl_rule { d }
  | d = protocol_decl  { d }
  | d = needs_decl     { d }
  | d = proof_cap_decl         { d }
  | d = cap_no_panic_decl      { d }
  | d = cap_pure_decl          { d }
  | d = cap_no_extern_decl     { d }
  | d = cap_deterministic_decl { d }
  | d = cap_no_alloc_decl      { d }
  | d = cap_verified_decl      { d }
  | d = transitions_decl       { d }
  | d = app_decl          { d }
  | d = derive_decl    { d }
  | d = satisfy_decl   { d }
  | d = test_decl      { d }
  | d = describe_decl  { d }
  | d = setup_decl     { d }
  | d = setup_all_decl { d }

(** Each fn clause is parsed as its own DFn with a single clause.
    The group_fn_clauses pass merges consecutive same-name clauses. *)
fn_bound_param:
  | name = lower_name; COLON; t = ty { (name, t) }

fn_decl:
  | FN; name = lower_name; _lp = LPAREN; params = separated_list(COMMA, fn_param); _rp = RPAREN;
    ret = option(ret_annot); guard = option(when_guard); DO; body = block_body; END
    { DFn ({ fn_name = name;
             fn_vis = Public;
             fn_doc = None;
             fn_attrs = [];
             fn_ret_ty = ret;
             fn_clauses = [{ fc_params = params;
                             fc_guard = guard;
                             fc_body = body;
                             fc_span = mk_span ($loc);
                             fc_params_span =
                               mk_span ($startpos(_lp), $endpos(_rp)) }];
             fn_bounds = [] },
           mk_span ($loc)) }
  | FN; name = lower_name;
    LBRACKET; bounds = separated_nonempty_list(COMMA, fn_bound_param); RBRACKET;
    _lp = LPAREN; params = separated_list(COMMA, fn_param); _rp = RPAREN;
    ret = option(ret_annot); guard = option(when_guard); DO; body = block_body; END
    { DFn ({ fn_name = name;
             fn_vis = Public;
             fn_doc = None;
             fn_attrs = [];
             fn_ret_ty = ret;
             fn_clauses = [{ fc_params = params;
                             fc_guard = guard;
                             fc_body = body;
                             fc_span = mk_span ($loc);
                             fc_params_span =
                               mk_span ($startpos(_lp), $endpos(_rp)) }];
             fn_bounds = bounds },
           mk_span ($loc)) }
  | PFN; name = lower_name; _lp = LPAREN; params = separated_list(COMMA, fn_param); _rp = RPAREN;
    ret = option(ret_annot); guard = option(when_guard); DO; body = block_body; END
    { DFn ({ fn_name = name;
             fn_vis = Private;
             fn_doc = None;
             fn_attrs = [];
             fn_ret_ty = ret;
             fn_clauses = [{ fc_params = params;
                             fc_guard = guard;
                             fc_body = body;
                             fc_span = mk_span ($loc);
                             fc_params_span =
                               mk_span ($startpos(_lp), $endpos(_rp)) }];
             fn_bounds = [] },
           mk_span ($loc)) }
  | PFN; name = lower_name;
    LBRACKET; bounds = separated_nonempty_list(COMMA, fn_bound_param); RBRACKET;
    _lp = LPAREN; params = separated_list(COMMA, fn_param); _rp = RPAREN;
    ret = option(ret_annot); guard = option(when_guard); DO; body = block_body; END
    { DFn ({ fn_name = name;
             fn_vis = Private;
             fn_doc = None;
             fn_attrs = [];
             fn_ret_ty = ret;
             fn_clauses = [{ fc_params = params;
                             fc_guard = guard;
                             fc_body = body;
                             fc_span = mk_span ($loc);
                             fc_params_span =
                               mk_span ($startpos(_lp), $endpos(_rp)) }];
             fn_bounds = bounds },
           mk_span ($loc)) }
  | FN; _n = lower_name; LPAREN; _ps = separated_list(COMMA, fn_param); RPAREN; error
    { error_raise
        "I was expecting `do` to start the function body here:"
        (Some "fn name(params) do\n    body\nend")
        $startpos($6) }
  | PFN; _n = lower_name; LPAREN; _ps = separated_list(COMMA, fn_param); RPAREN; error
    { error_raise
        "I was expecting `do` to start the function body here:"
        (Some "pfn name(params) do\n    body\nend")
        $startpos($6) }

when_guard:
  | WHEN; e = expr { e }

(** Function parameters: can be patterns (for head matching) or named params. *)
fn_param:
  | p = pattern { FPPat p }
  | name = soft_lower_name; COLON; t = ty
    { FPNamed { param_name = name; param_ty = Some t; param_lin = Unrestricted } }
  | LINEAR; name = soft_lower_name; COLON; t = ty
    { FPNamed { param_name = name; param_ty = Some t; param_lin = Linear } }
  | AFFINE; name = soft_lower_name; COLON; t = ty
    { FPNamed { param_name = name; param_ty = Some t; param_lin = Affine } }
  | name = soft_lower_name; DSLASH; default_e = expr
    { FPDefault ({ param_name = name; param_ty = None; param_lin = Unrestricted }, default_e) }
  | name = soft_lower_name; COLON; t = ty; DSLASH; default_e = expr
    { FPDefault ({ param_name = name; param_ty = Some t; param_lin = Unrestricted }, default_e) }

let_decl:
  | LET; p = simple_pattern; ty = option(type_annot); EQUALS; e = expr
    { DLet (Public, { bind_pat = p; bind_ty = ty; bind_lin = Unrestricted; bind_expr = e },
            mk_span ($loc)) }
  | LET; _p = simple_pattern; _ty = option(type_annot); error
    { error_raise
        "I was expecting `=` in the let binding here:"
        (Some "let name = expr")
        $startpos($4) }

type_decl:
  (* opaque type: type name public, constructors private to module *)
  | OPAQUE; TYPE; name = upper_name; tparams = option(type_params); EQUALS;
    variants = separated_nonempty_list(PIPE, variant)
    { let tps = match tparams with Some ps -> ps | None -> [] in
      let private_variants = List.map (fun v -> { v with var_vis = Private }) variants in
      DType (Public, name, tps, TDVariant private_variants, mk_span ($loc)) }
  | OPAQUE; TYPE; name = upper_name; tparams = option(type_params); EQUALS;
    LBRACE; fields = separated_list(COMMA, field); RBRACE
    { let tps = match tparams with Some ps -> ps | None -> [] in
      DType (Public, name, tps, TDRecord fields, mk_span ($loc)) }
  | TYPE; name = upper_name; tparams = option(type_params); EQUALS;
    variants = separated_nonempty_list(PIPE, variant)
    { let tps = match tparams with Some ps -> ps | None -> [] in
      DType (Public, name, tps, TDVariant variants, mk_span ($loc)) }
  | TYPE; name = upper_name; tparams = option(type_params); EQUALS;
    LBRACE; fields = separated_list(COMMA, field); RBRACE
    { let tps = match tparams with Some ps -> ps | None -> [] in
      DType (Public, name, tps, TDRecord fields, mk_span ($loc)) }
  | PTYPE; name = upper_name; tparams = option(type_params); EQUALS;
    variants = separated_nonempty_list(PIPE, variant)
    { let tps = match tparams with Some ps -> ps | None -> [] in
      DType (Private, name, tps, TDVariant variants, mk_span ($loc)) }
  | PTYPE; name = upper_name; tparams = option(type_params); EQUALS;
    LBRACE; fields = separated_list(COMMA, field); RBRACE
    { let tps = match tparams with Some ps -> ps | None -> [] in
      DType (Private, name, tps, TDRecord fields, mk_span ($loc)) }
  | ALWAYSLINEAR; TYPE; name = upper_name; tparams = option(type_params); EQUALS;
    variants = separated_nonempty_list(PIPE, variant)
    { let tps = match tparams with Some ps -> ps | None -> [] in
      DAlwaysLinearType (Public, name, tps, TDVariant variants, mk_span ($loc)) }
  | ALWAYSLINEAR; TYPE; name = upper_name; tparams = option(type_params); EQUALS;
    LBRACE; fields = separated_list(COMMA, field); RBRACE
    { let tps = match tparams with Some ps -> ps | None -> [] in
      DAlwaysLinearType (Public, name, tps, TDRecord fields, mk_span ($loc)) }
  | TAG; name = upper_name
    (* Sugar: `tag Foo` ≡ `type Foo = Foo`  — a zero-arg phantom label type. *)
    { let sp = mk_span ($loc) in
      let ctor = { var_name = name; var_args = []; var_vis = Public } in
      DType (Public, name, [], TDVariant [ctor], sp) }
  | TYPE; _n = upper_name; error
    { error_raise
        "I was expecting `=` after the type name here:"
        (Some "type Name = Variant1 | Variant2(Int)")
        $startpos($3) }

derive_decl:
  | DERIVE; ifaces = separated_nonempty_list(COMMA, upper_name);
    FOR; type_name = upper_name
    { DDeriving (type_name, ifaces, mk_span ($loc)) }

satisfy_decl:
  | SATISFY; ifaces = separated_nonempty_list(COMMA, upper_name);
    FOR; types = separated_nonempty_list(COMMA, upper_name)
    { DSatisfy (ifaces, types, mk_span ($loc)) }

actor_decl:
  | ACTOR; _n = upper_name; error
    { error_raise
        "I was expecting `do` after the actor name here:"
        (Some "actor Name do\n    state { field: Type }\n    init ...\n    on Msg(x) do ... end\nend")
        $startpos($3) }
  | ACTOR; name = upper_name; DO;
    STATE; LBRACE; fields = separated_list(COMMA, field); RBRACE;
    INIT; init_expr = expr;
    sup = option(supervise_block);
    handlers = list(actor_handler);
    END
    { DActor (Public, name,
              { actor_state = fields; actor_init = init_expr; actor_handlers = handlers;
                actor_supervise = sup; actor_compat = "full"; actor_invariant = None },
              mk_span ($loc)) }

(** Application entry point:
      app MyApp do
        on_start do ... end   (* optional *)
        on_stop  do ... end   (* optional *)
        Supervisor.spec(:one_for_one, [...])
      end *)
app_decl:
  | APP; _n = upper_name; error
    { error_raise
        "I was expecting `do` after the app name here:"
        (Some "app MyApp do\n    Supervisor.spec(:one_for_one, [...])\nend")
        $startpos($3) }
  | APP; name = upper_name; DO;
    on_start = option(on_start_block);
    on_stop  = option(on_stop_block);
    body = block_body;
    END
    { DApp ({ app_name = name; app_body = body;
              app_on_start = on_start; app_on_stop = on_stop },
            mk_span ($loc)) }

on_start_block:
  | ON_START; DO; body = block_body; END
    { body }

on_stop_block:
  | ON_STOP; DO; body = block_body; END
    { body }

(** test "name" do ... end *)
test_decl:
  | TEST; name = STRING; DO; body = block_body; END
    { DTest ({ test_name = name; test_body = body }, mk_span ($loc)) }
  | TEST; _n = STRING; error
    { error_raise
        "I was expecting `do` to start the test body here:"
        (Some "test \"name\" do\n    assert expr\nend")
        $startpos($3) }
  | TEST; error
    { error_raise
        "I was expecting a string name for the test:"
        (Some "test \"my test name\" do\n    assert expr\nend")
        $startpos($2) }

(** describe "name" do test ... end — groups tests under a label *)
describe_decl:
  | DESCRIBE; name = STRING; DO; decls = describe_body; END
    { DDescribe (name, decls, mk_span ($loc)) }

describe_body:
  | { [] }
  | ds = describe_body; d = test_decl    { ds @ [d] }
  | ds = describe_body; d = describe_decl { ds @ [d] }

(** setup do ... end — runs before each test *)
setup_decl:
  | SETUP; DO; body = block_body; END
    { DSetup (body, mk_span ($loc)) }

(** setup_all do ... end — runs once before all tests *)
setup_all_decl:
  | SETUP_ALL; DO; body = block_body; END
    { DSetupAll (body, mk_span ($loc)) }

(** supervise do
      strategy one_for_one
      max_restarts 3 within 60
      WorkerA wa
      WorkerB wb
    end *)
supervise_block:
  | SUPERVISE; DO;
    STRATEGY; strat = restart_strategy_tok;
    MAX_RESTARTS; max_r = INT; WITHIN; win = INT;
    children = list(supervise_child);
    END
    { let names = List.map (fun (n, _, _) -> n) children in
      let tyfields = List.map (fun (n, t, r) ->
        { sf_name = n; sf_ty = t; sf_restart = r }) children in
      { sc_fields = tyfields;
        sc_strategy = strat;
        sc_max_restarts = max_r;
        sc_window_secs = win;
        sc_order = names } }

supervise_child:
  | actor_type = upper_name; field_name = lower_name;
    r = option(child_restart)
    { (field_name, TyCon (actor_type, []),
       (match r with Some t -> t | None -> Permanent)) }

(* Optional per-child restart policy. Placed as a labelled trailing modifier so
   a later `shutdown <ms>` field can be added in the same position without a
   grammar rework. Omitted means Permanent, which is what every supervise block
   written before this feature means. *)
child_restart:
  | RESTART; t = restart_type_tok  { t }

restart_type_tok:
  | PERMANENT  { Permanent }
  | TRANSIENT  { Transient }
  | TEMPORARY  { Temporary }

restart_strategy_tok:
  | ONE_FOR_ONE  { OneForOne }
  | ONE_FOR_ALL  { OneForAll }
  | REST_FOR_ONE { RestForOne }

actor_handler:
  | ON; msg = upper_name; LPAREN; params = separated_list(COMMA, param); RPAREN;
    DO; body = block_body; END
    { { ah_msg = msg; ah_params = params; ah_body = body } }

(** Protocol (binary session type) declaration:
    protocol Transfer do
      Client -> Server : Request(String)
      Server -> Client : Response(Int)
      loop do
        Client -> Server : More(String)
        Server -> Client : Ack()
      end
    end

    A `loop` body (or a `choose` branch nested inside one) may end in `stop`
    to exit the loop instead of repeating it — `stop` is a CONTEXTUAL
    keyword (plain `lower_name`, not reserved elsewhere):
    protocol Stream do
      loop do
        Prod -> Cons : Int
        choose by Cons:
          more -> Cons -> Prod : Bool
          done -> Cons -> Prod : Bool
                  stop
        end
      end
    end *)
protocol_decl:
  | PROTOCOL; name = upper_name; DO; steps = list(protocol_step); END
    { DProtocol (name, { proto_steps = steps }, mk_span ($loc)) }

protocol_step:
  | sender = upper_name; ARROW; receiver = upper_name; COLON; t = ty
    { ProtoMsg (sender, receiver, t) }
  | LOOP; DO; steps = list(protocol_step); END
    { ProtoLoop steps }
  | CHOOSE; BY; chooser = upper_name; COLON; option(arm_sep); branches = separated_nonempty_list(arm_sep, choose_branch); END
    { ProtoChoice (chooser, branches) }
  | id = lower_name
    { if id.txt = "stop" then ProtoStop (mk_span $loc)
      else
        error_raise
          (Printf.sprintf
             "I don't recognize `%s` here — the only protocol step allowed \
              is `stop` (to exit an enclosing `loop`)."
             id.txt)
          None $startpos(id) }

choose_branch:
  | option(PIPE); label = lower_name; ARROW; steps = list(protocol_step)
    { (label, steps) }

(** Nested module: mod Name do ... end  or  mod A.B.C do ... end *)
mod_decl:
  | MOD; path = upper_dot_path; DO; decls = decl_list_r; END
    { let name = join_mod_path path in
      DMod (name, Public, group_fn_clauses decls, mk_span ($loc)) }
  | MOD; _n = upper_dot_path; error
    { error_raise
        "I was expecting `do` after the module name here:"
        (Some "mod Name do\n    ...\nend")
        $startpos($3) }

(** Import declaration: use A.B.* or use A.B.{f,g} or use A.B.foo or use A
    Multi-level module paths are handled via the right-recursive use_path_tail
    nonterminal, which avoids LALR(1) shift/reduce conflicts: after each DOT,
    the lookahead (UPPER_IDENT vs LOWER_IDENT vs STAR vs LBRACE) unambiguously
    selects which branch to take. *)
use_decl:
  | USE; head = upper_name; tail = use_path_tail
    { let (path_rest, sel) = tail in
      DUse ({ use_path = head :: path_rest; use_sel = sel }, mk_span ($loc)) }

(* Right-recursive tail for use paths.  After the leading UPPER_IDENT the
   lookahead determines which alternative applies:
     DOT STAR        -> UseAll       -- use A.STAR
     DOT LBRACE      -> UseNames     -- use A.{f,g}
     DOT UPPER_IDENT -> recurse      -- use A.B....
     DOT LOWER_IDENT -> UseNames[1]  -- use A.foo
     empty           -> UseSingle    -- use A *)
use_path_tail:
  |   { ([], UseSingle) }
  | DOT; sel = use_selector
    { ([], sel) }
  | DOT; seg = upper_name; tail = use_path_tail
    { let (rest, sel) = tail in (seg :: rest, sel) }
  | DOT; name = lower_name
    { ([], UseNames [name]) }

use_selector:
  | STAR
    { UseAll }
  | LBRACE; names = separated_list(COMMA, lower_name); RBRACE
    { UseNames names }

(** Elixir-style import: import Mod, import Mod.Sub, import Mod.Sub.{A, B},
    import Mod.Sub, only: [f,g], import Mod.Sub, except: [f,g]
    Multi-level module paths are handled via the right-recursive import_path_tail
    nonterminal, analogous to use_path_tail: after each DOT, the lookahead
    (UPPER_IDENT vs LBRACE) unambiguously selects which branch to take. *)
import_decl:
  | IMPORT; head = upper_name; tail = import_path_tail
    { let (path_rest, sel) = tail in
      DUse ({ use_path = head :: path_rest; use_sel = sel }, mk_span ($loc)) }

(* Right-recursive tail for import paths.  After the leading UPPER_IDENT the
   lookahead determines which alternative applies:
     empty           -> UseAll          -- import A
     COMMA ONLY      -> UseNames        -- import A, only: [f,g]
     COMMA EXCEPT    -> UseExcept       -- import A, except: [f,g]
     DOT LBRACE      -> UseNames        -- import A.{B, C}
     DOT UPPER_IDENT -> recurse         -- import A.B.... *)
import_path_tail:
  |   { ([], UseAll) }
  | COMMA; ONLY; COLON; LBRACKET; names = separated_list(COMMA, lower_name); RBRACKET
    { ([], UseNames names) }
  | COMMA; EXCEPT; COLON; LBRACKET; names = separated_list(COMMA, lower_name); RBRACKET
    { ([], UseExcept names) }
  | DOT; LBRACE; names = separated_list(COMMA, any_name); RBRACE
    { ([], UseNames names) }
  | DOT; seg = upper_name; tail = import_path_tail
    { let (rest, sel) = tail in (seg :: rest, sel) }

(** alias Long.Name, as: Short  or  alias Long.Name as Short  or  alias Long.Name *)
alias_decl_rule:
  | ALIAS; path = upper_dot_path; COMMA; AS; COLON; short = upper_name
    { DAlias ({ alias_path = path; alias_name = short }, mk_span ($loc)) }
  | ALIAS; path = upper_dot_path; AS; short = upper_name
    { DAlias ({ alias_path = path; alias_name = short }, mk_span ($loc)) }
  | ALIAS; path = upper_dot_path
    { let last = List.nth path (List.length path - 1) in
      DAlias ({ alias_path = path; alias_name = last }, mk_span ($loc)) }

(** Name accepting both uppercase (type/constructor) and lowercase (function) identifiers *)
any_name:
  | n = lower_name { n }
  | n = upper_name { n }

upper_dot_path:
  | name = upper_name { [name] }
  | name = upper_name; DOT; rest = upper_dot_path { name :: rest }

(** Capability manifest: needs IO.Network, IO.Clock
    Each path is a dot-separated sequence of uppercase names stored as a name
    list, optionally followed by a PATH SCOPE:  needs IO.FileRead("/etc/app").
    A scope narrows the capability to that directory subtree; its absence means
    any path.  Only filesystem capabilities accept one — the typechecker
    rejects a scope elsewhere rather than ignoring it. *)
needs_decl:
  | NEEDS; caps = separated_nonempty_list(COMMA, scoped_cap_path)
    { DNeeds (caps, mk_span ($loc)) }

scoped_cap_path:
  | p = cap_path { (p, None) }
  | p = cap_path; LPAREN; s = STRING; RPAREN { (p, Some s) }

cap_path:
  | id = upper_name { [id] }
  | id = upper_name; DOT; rest = cap_path { id :: rest }

proof_cap_decl:
  | PROOFCAP; name = upper_name; dict = proof_cap_dict
    { DProofCap (name, dict, mk_span ($loc)) }

(** Optional runtime-dictionary type on a proof-cap declaration:
    `proof cap Live with SessionOps`.  Absent means the capability stays
    runtime-erased, which is every capability written before this existed.

    KNOWN CONFLICT (verified 2026-08-31: this rule takes the grammar from 10
    shift/reduce conflicts to 11).  After `PROOFCAP upper_name` with `WITH`
    ahead, menhir cannot decide between reducing the empty `proof_cap_dict`
    and shifting, because the REPL entry point's `repl_sequence` can itself
    BEGIN with `WITH`.  Menhir resolves it by shifting, which is the reading
    this rule wants; the only casualty is a REPL session that types
    `proof cap X` and then opens a fresh `with ...` sequence on the next token,
    where the `with` binds to the capability.  Restructuring into two explicit
    productions does not remove it — the ambiguity is in `repl_sequence`'s
    first set, not in this rule's shape. *)
proof_cap_dict:
  |                          { None }
  | WITH; t = upper_name     { Some t }

cap_no_panic_decl:
  | CAP_NO_PANIC
    { DOpts (["no_panic"], mk_span ($loc)) }

cap_pure_decl:
  | CAP_PURE
    { DOpts (["pure"], mk_span ($loc)) }

cap_no_extern_decl:
  | CAP_NO_EXTERN
    { DOpts (["no_extern"], mk_span ($loc)) }

cap_deterministic_decl:
  | CAP_DETERMINISTIC
    { DOpts (["deterministic"], mk_span ($loc)) }

cap_no_alloc_decl:
  | CAP_NO_ALLOC
    { DOpts (["no_alloc"], mk_span ($loc)) }

cap_verified_decl:
  | CAP_VERIFIED
    { DOpts (["verified"], mk_span ($loc)) }

(** Compiler-enforced state-machine transitions:
    transitions Handle do
      ConnTag: Closed -> Open   via open_conn
      ConnTag: Open -> Closed   via close
    end *)
transitions_decl:
  | TRANSITIONS; handle_ty = upper_name; DO; arms = list(transition_arm); END
    { DTransitions (handle_ty, arms, mk_span ($loc)) }

transition_arm:
  | resource = upper_name; COLON; from_st = upper_name; ARROW; to_st = upper_name; VIA; fn_name = lower_name
    { { tr_resource = resource; tr_from = from_st; tr_to = to_st;
        tr_via = fn_name; tr_span = mk_span ($loc) } }

(** Interface (typeclass) definition: interface Eq(a) do fn eq: a -> a -> Bool end
    Optional requires clause: interface Ord(a) requires Eq(a) do ... end *)
interface_decl:
  | INTERFACE; name = upper_name; LPAREN; param = lower_name; RPAREN;
    superclasses = loption(preceded(REQUIRES, separated_nonempty_list(COMMA, constraint_expr)));
    DO; methods = list(method_sig); END
    { DInterface ({
        iface_name = name;
        iface_param = param;
        iface_superclasses = superclasses;
        iface_assoc_types = [];
        iface_methods = methods;
      }, mk_span ($loc)) }
  | INTERFACE; _n = upper_name; error
    { error_raise
        "Interfaces need a type parameter in parentheses:"
        (Some "interface Name(a) do\n    fn method: a -> a\nend")
        $startpos($3) }

method_sig:
  | FN; name = lower_name; COLON; t = ty;
    default = option(preceded_by_do_end(expr))
    { { md_name = name; md_ty = t; md_default = default } }

%inline preceded_by_do_end(X):
  | DO; x = X; END { x }

(** Interface implementation: impl Eq(Int) do fn eq(x, y) do x == y end end
    Also accepts dotted names: impl Conduit.Storage(T) do ... end
    (equivalent to: import Conduit; impl Storage(T) do ... end) *)
impl_decl:
  | IMPL; iface_path = upper_dot_path; LPAREN; t = ty; RPAREN;
    constraints = loption(preceded(WHEN, separated_nonempty_list(COMMA, constraint_expr)));
    DO; methods = list(fn_decl); END
    { let iface = let joined = String.concat "." (List.map (fun n -> n.txt) iface_path) in
                  mk_name joined $loc(iface_path) in
      DImpl ({
        impl_iface = iface;
        impl_ty = t;
        impl_constraints = constraints;
        impl_assoc_types = [];
        impl_methods =
          List.filter_map (function
            | DFn (def, _) -> Some (def.fn_name, def)
            | _ -> None) methods;
      }, mk_span ($loc)) }
  | IMPL; _iface = upper_dot_path; error
    { error_raise
        "Implementations need a type argument in parentheses:"
        (Some "impl InterfaceName(ConcreteType) do\n    fn method(x) do ... end\nend")
        $startpos($3) }

constraint_expr:
  | path = upper_dot_path; LPAREN; t = ty; RPAREN
    { let name = let joined = String.concat "." (List.map (fun n -> n.txt) path) in
                 mk_name joined $loc(path) in
      (name, [t]) }

(** Module signature: sig Collections do fn insert: Int -> List -> Int end *)
sig_decl:
  | SIG; name = upper_name; DO; items = list(sig_item); END
    { let types = List.filter_map fst items in
      let fns   = List.filter_map snd items in
      DSig (name, { sig_types = types; sig_fns = fns }, mk_span ($loc)) }

(* Each sig_item returns (type_entry option, fn_entry option) *)
sig_item:
  | TYPE; name = upper_name; params = list(lower_name)
    { (Some (name, params), None) }
  | FN; name = lower_name; COLON; t = ty
    { (None, Some (name, t)) }

(** FFI resource: `resource Hasher` — an opaque, RC-managed native handle type.
    Desugars to an abstract type (no constructors) so it stays heap-boxed (never
    newtype/niche-unboxed) and Perceus drops it, running the destructor wired in
    by march_resource_new. Only constructible/inspectable via extern functions. *)
resource_decl:
  | RESOURCE; name = upper_name
    { DType (Public, name, [], TDVariant [], mk_span ($loc)) }

(** FFI extern block: extern "libc": Cap(LibC) do fn malloc(n: Int): Int end *)
extern_decl:
  | EXTERN; lib = STRING; COLON; cap = ty; DO;
    fns = list(extern_fn_decl); END
    { DExtern ({
        ext_lib_name = lib;
        ext_cap_ty = cap;
        ext_fns = fns;
      }, mk_span ($loc)) }

extern_fn_decl:
  | mods = list(extern_modifier); FN; name = lower_name;
    LPAREN; params = separated_list(COMMA, ffi_param); RPAREN;
    COLON; ret = ty; sym = option(preceded(EQUALS, STRING))
    { { ef_name = name;
        ef_params = List.map (fun ((n, t), _) -> (n, t)) params;
        ef_param_consumed = List.map snd params;
        ef_blocking = List.mem "blocking" mods;
        ef_raises = List.mem "raises" mods;
        ef_ret_ty = ret; ef_symbol = sym } }

(* Contextual modifier words before an extern `fn` (not reserved keywords):
   `blocking` (dispatch on an OS thread) and `raises` (env-routed errors —
   the binding takes a march_env* and returns the bare Ok payload). *)
extern_modifier:
  | kw = lower_name
    { match kw.txt with
      | "blocking" | "raises" -> kw.txt
      | other ->
        error_raise
          (Printf.sprintf "unexpected `%s` before `fn` in extern block; \
                           the only modifiers are `blocking` and `raises`" other)
          None $startpos }

(* An extern parameter, optionally prefixed with the contextual word `consume`
   (ownership transferred to the binding; the binding must drop or store it —
   March will not).  `consume` is NOT a reserved keyword (it is a common
   identifier in linear-types code) — it is recognized only here, as the leading
   word of an extern parameter, via the two-identifier form. *)
ffi_param:
  | kw = lower_name; name = lower_name; COLON; t = ty
    { if kw.txt <> "consume" then
        error_raise
          (Printf.sprintf "unexpected `%s` before extern parameter `%s`; \
                           the only parameter modifier is `consume`" kw.txt name.txt)
          None $startpos;
      ((name, t), true) }
  | name = lower_name; COLON; t = ty
    { ((name, t), false) }

(* ---- Types ---- *)

type_annot:
  | COLON; t = ty { t }

ret_annot:
  | COLON; t = ty { t }

type_params:
  | LPAREN; ps = separated_nonempty_list(COMMA, lower_name); RPAREN { ps }

ty_eof:
  | t = ty EOF { t }

ty:
  | t = ty_nat_add ARROW u = ty { TyArrow (t, u) }
  | t = ty_nat_add { t }

ty_nat_add:
  | a = ty_nat_add PLUS b = ty_nat_mul { TyNatOp (NatAdd, a, b) }
  | t = ty_nat_mul { t }

ty_nat_mul:
  | a = ty_nat_mul STAR b = ty_app { TyNatOp (NatMul, a, b) }
  | t = ty_app { t }

ty_app:
  | id = upper_name; LPAREN; args = separated_nonempty_list(COMMA, ty); RPAREN
    { TyCon (id, args) }
  | id = upper_name; DOT; rest = dotted_upper_tail; LPAREN; args = separated_nonempty_list(COMMA, ty); RPAREN
    { let joined = id.txt ^ "." ^ String.concat "." (List.map (fun (n : March_ast.Ast.name) -> n.txt) rest) in
      TyCon (mk_name joined $loc, args) }
  | t = ty_atom { t }

ty_atom:
  | n = INT { TyNat n }
  | id = LOWER_IDENT { TyVar (mk_name id $loc) }
  | id = upper_name; DOT; rest = dotted_upper_tail
    { (* Dotted type name: IO.Network → TyCon("IO.Network", []) *)
      let joined = id.txt ^ "." ^ String.concat "." (List.map (fun (n : March_ast.Ast.name) -> n.txt) rest) in
      TyCon (mk_name joined $loc, []) }
  | id = upper_name { TyCon (id, []) }
  | LINEAR; t = ty_atom { TyLinear (Linear, t) }
  | AFFINE; t = ty_atom { TyLinear (Affine, t) }
  | LPAREN; RPAREN { TyTuple [] }
  | LPAREN; t = ty; RPAREN { t }
  | LPAREN; t = ty; COMMA; ts = separated_nonempty_list(COMMA, ty); RPAREN
    { TyTuple (t :: ts) }
  (* Refinement type, no binder: { Int | _ >= 0 }, { List(a) | len(_) > 0 }.
     Base is a [ty_app] (constructor/atom application) — function-arrow and
     nat-arithmetic bases are not refined directly in v1. *)
  | LBRACE; t = ty_app; PIPE; p = expr; RBRACE
    { TyRefine (t, None, p) }
  (* Refinement type with binder: { v : Int | v != 0 }.  Shares the
     `lower_name COLON ty` prefix with a record field; menhir resolves on the
     PIPE (refinement) vs COMMA/RBRACE (record) lookahead. *)
  | LBRACE; name = lower_name; COLON; t = ty; PIPE; p = expr; RBRACE
    { TyRefine (t, Some name, p) }
  | LBRACE; fields = separated_nonempty_list(COMMA, ty_record_field); RBRACE
    { TyRecord fields }

ty_record_field:
  | name = lower_name; COLON; t = ty { (name, t) }

dotted_upper_tail:
  | id = upper_name { [id] }
  | id = upper_name; DOT; rest = dotted_upper_tail { id :: rest }

variant:
  | name = upper_name; LPAREN; args = separated_nonempty_list(COMMA, ty); RPAREN
    { { var_name = name; var_args = args; var_vis = Public } }
  | name = upper_name
    { { var_name = name; var_args = []; var_vis = Public } }
  | a = ATOM; LPAREN; args = separated_nonempty_list(COMMA, ty); RPAREN
    { { var_name = mk_name a $loc; var_args = args; var_vis = Public } }
  | a = ATOM
    { { var_name = mk_name a $loc; var_args = []; var_vis = Public } }

field:
  | name = lower_name; COLON; t = ty
    { { fld_name = name; fld_ty = t; fld_lin = Unrestricted } }
  | LINEAR; name = lower_name; COLON; t = ty
    { { fld_name = name; fld_ty = t; fld_lin = Linear } }
  | AFFINE; name = lower_name; COLON; t = ty
    { { fld_name = name; fld_ty = t; fld_lin = Affine } }

param:
  | name = soft_lower_name; COLON; t = ty
    { { param_name = name; param_ty = Some t; param_lin = Unrestricted } }
  | name = soft_lower_name
    { { param_name = name; param_ty = None; param_lin = Unrestricted } }
  | UNDERSCORE
    { { param_name = mk_name "_" $loc; param_ty = None; param_lin = Unrestricted } }
  | LINEAR; name = soft_lower_name; COLON; t = ty
    { { param_name = name; param_ty = Some t; param_lin = Linear } }
  | AFFINE; name = soft_lower_name; COLON; t = ty
    { { param_name = name; param_ty = Some t; param_lin = Affine } }

(* ---- Expressions ---- *)

block_body:
  | es = nonempty_list(block_expr)
    { fold_letq es (mk_span ($loc)) }

block_expr:
  | LET; p = simple_pattern; ty = option(type_annot); EQUALS; e = expr
    { ELet ({ bind_pat = p; bind_ty = ty; bind_lin = Unrestricted; bind_expr = e },
            mk_span ($loc)) }
  | LINEAR; LET; p = simple_pattern; ty = option(type_annot); EQUALS; e = expr
    { ELet ({ bind_pat = p; bind_ty = ty; bind_lin = Linear; bind_expr = e },
            mk_span ($loc)) }
  | AFFINE; LET; p = simple_pattern; ty = option(type_annot); EQUALS; e = expr
    { ELet ({ bind_pat = p; bind_ty = ty; bind_lin = Affine; bind_expr = e },
            mk_span ($loc)) }
  | LET; QUESTION; p = simple_pattern; EQUALS; e = expr
    { ELetQ (p, e, EBlock ([], mk_span ($loc)), mk_span ($loc)) }
  | LET; QUESTION; _p = simple_pattern; ty = type_annot; _e = preceded(EQUALS, expr)?
    { let _ = ty in
      error_raise
        "A `let?` binding can't have a type annotation — its type is inferred \
         from the `Ok` payload of the `Result` on the right."
        (Some "let? name = result_expr")
        $startpos(ty) }
  | LET; QUESTION; _p = simple_pattern; error
    { error_raise
        "I was expecting `=` in the let? binding here:"
        (Some "let? name = result_expr")
        $startpos($4) }
  | LET; STAR; p = simple_pattern; EQUALS; e = expr
    { ELetStar (p, e, EBlock ([], mk_span ($loc)), mk_span ($loc)) }
  | LET; STAR; _p = simple_pattern; ty = type_annot; _e = preceded(EQUALS, expr)?
    { let _ = ty in
      error_raise
        "A `let*` binding can't have a type annotation — its type is \
         inferred from the right-hand side."
        (Some "let* name = expr")
        $startpos(ty) }
  | LET; STAR; _p = simple_pattern; error
    { error_raise
        "I was expecting `=` in the let* binding here:"
        (Some "let* name = expr")
        $startpos($4) }
  | LET; _p = simple_pattern; _ty = option(type_annot); error
    { error_raise
        "I was expecting `=` in the let binding here:"
        (Some "let name = expr")
        $startpos($4) }
  | FN; name = lower_name; _lp = LPAREN; params = separated_list(COMMA, fn_param); _rp = RPAREN;
    ret = option(ret_annot); DO; body = block_body; END
    { let simple_params = List.filter_map (function
        | FPNamed fp ->
          Some { param_name = fp.param_name; param_ty = fp.param_ty;
                 param_lin = fp.param_lin }
        | FPPat (PatVar n) ->
          Some { param_name = n; param_ty = None; param_lin = Unrestricted }
        | FPDefault (fp, _) ->
          Some { param_name = fp.param_name; param_ty = fp.param_ty;
                 param_lin = fp.param_lin }
        | FPPat _ -> None) params in
      ELetFn (name, simple_params, ret, body, mk_span ($loc)) }
  | FN; _n = lower_name; LPAREN; _ps = separated_list(COMMA, fn_param); RPAREN; error
    { error_raise
        "I was expecting `do` to start the function body here:"
        (Some "fn name(params) do\n    body\nend")
        $startpos($6) }
  | e = expr { e }


expr:
  | e = expr_pipe { e }
  | ASSERT; e = expr
    { EAssert (e, mk_span ($loc)) }
  | FN; ARROW; body = lambda_body
    { ELam ([], body, mk_span ($loc)) }
  | FN; ps = lambda_params; ARROW; body = lambda_body
    { ELam (ps, body, mk_span ($loc)) }
  | FN; ps = lambda_params; error
    { let params = String.concat " " (List.map (fun p -> p.param_name.txt) ps) in
      let hint = Printf.sprintf "fn %s -> expr" params in
      error_raise
        "I was expecting `->` to start the lambda body here:"
        (Some hint)
        $startpos($3) }
  | IF; cond = expr; DO; t = block_body; ELSE; f = block_body; END
    { EIf (cond, t, f, mk_span ($loc)) }
  | IF; _c = expr; DO; _t = block_body; ELSE; _f = block_body; error
    { error_raise
        "I was expecting `end` to close the if expression here:"
        (Some "if cond do\n    expr1\nelse\n    expr2\nend")
        $startpos($7) }
  | IF; _c = expr; DO; _t = block_body; error
    { error_raise
        "March `if` expressions always need an `else` branch:"
        (Some "if cond do\n    expr1\nelse\n    expr2\nend")
        $startpos($5) }
  | IF; _c = expr; THEN; _t = expr; error
    { error_raise
        "I don't recognize `then` here — March uses do/end blocks instead."
        (Some "if cond do\n    expr1\nelse\n    expr2\nend")
        $startpos($3) }
  | IF; _c = expr; error
    { error_raise
        "I was expecting `do` after the condition here:"
        (Some "if cond do\n    expr1\nelse\n    expr2\nend")
        $startpos($3) }
  | MATCH; e = expr; DO; option(arm_sep); bs = separated_nonempty_list(arm_sep, branch); END
    { EMatch (e, bs, mk_span ($loc)) }
  (* Split rather than `MATCH; DO; option(arm_sep); ...`: the shared
     [option(arm_sep)] nonterminal (also used by [branch]'s and
     [choose_branch]'s leading separator) merges, via LALR state sharing, the
     epsilon (no-separator) case here with an unrelated derivation elsewhere
     in the automaton — silently losing the epsilon-reduce to a shift for
     nearly every lookahead token and rejecting the single-line, no-separator
     cond form (`match do expr -> body end`). Spelling out both alternatives
     explicitly keeps this production's states out of that shared automaton
     path. See specs/lang/grammar.md §5.3 for the full trace. *)
  | MATCH; DO; bs = separated_nonempty_list(arm_sep, cond_branch); END
    { ECond (bs, mk_span ($loc)) }
  | MATCH; DO; arm_sep; bs = separated_nonempty_list(arm_sep, cond_branch); END
    { ECond (bs, mk_span ($loc)) }
  | MATCH; _e = expr; DO; option(arm_sep); _bs = separated_nonempty_list(arm_sep, branch); error
    { error_raise
        "I was expecting `end` to close the match here:"
        None
        $startpos(_bs) }
  | MATCH; _e = expr; error
    { error_raise
        "I was expecting `do` after the match expression here:"
        (Some "match expr do\n    Pattern -> result\nend")
        $startpos($3) }
  | WITH; bindings = separated_nonempty_list(COMMA, with_binding);
    DO; body = block_body; END
    { build_with bindings body [] (mk_span ($loc)) }
  | WITH; bindings = separated_nonempty_list(COMMA, with_binding);
    DO; body = block_body;
    ELSE; option(arm_sep); else_arms = separated_nonempty_list(arm_sep, branch); END
    { build_with bindings body else_arms (mk_span ($loc)) }

lambda_params:
  | name = soft_lower_name { [{ param_name = name; param_ty = None; param_lin = Unrestricted }] }
  | UNDERSCORE { [{ param_name = mk_name "_" $loc; param_ty = None; param_lin = Unrestricted }] }
  | LPAREN; ps = separated_list(COMMA, param); RPAREN
    { ps }

(** Lambda body: zero or more leading [let] bindings followed by a final expression.
    This mirrors [block_body] but uses a right-recursive rule so it can appear after
    [->] without requiring [do...end] delimiters.  NL tokens are already suppressed
    outside match contexts, so the token stream is flat; the grammar terminates
    greedily: all leading [let]/[linear let] tokens are consumed as bindings, and the
    first non-[let] token starts the final expression. *)
lambda_body:
  | stmts = lambda_stmts; e = expr
    { fold_letq (stmts @ [e]) (mk_span ($loc)) }

lambda_stmts:
  | (* empty *) { [] }
  | LET; p = simple_pattern; ty = option(type_annot); EQUALS; ev = expr; rest = lambda_stmts
    { ELet ({ bind_pat = p; bind_ty = ty; bind_lin = Unrestricted; bind_expr = ev },
            mk_span ($loc)) :: rest }
  | LINEAR; LET; p = simple_pattern; ty = option(type_annot); EQUALS; ev = expr; rest = lambda_stmts
    { ELet ({ bind_pat = p; bind_ty = ty; bind_lin = Linear; bind_expr = ev },
            mk_span ($loc)) :: rest }
  | AFFINE; LET; p = simple_pattern; ty = option(type_annot); EQUALS; ev = expr; rest = lambda_stmts
    { ELet ({ bind_pat = p; bind_ty = ty; bind_lin = Affine; bind_expr = ev },
            mk_span ($loc)) :: rest }
  | LET; QUESTION; p = simple_pattern; EQUALS; ev = expr; rest = lambda_stmts
    { ELetQ (p, ev, EBlock ([], mk_span ($loc)), mk_span ($loc)) :: rest }
  | LET; STAR; p = simple_pattern; EQUALS; ev = expr; rest = lambda_stmts
    { ELetStar (p, ev, EBlock ([], mk_span ($loc)), mk_span ($loc)) :: rest }

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
  | e = expr_add %prec EQEQ { e }

expr_add:
  | a = expr_add; PLUS;     b = expr_mul { EApp (EVar (mk_name "+"  $loc), [a; b], mk_span ($loc)) }
  | a = expr_add; MINUS;    b = expr_mul { EApp (EVar (mk_name "-"  $loc), [a; b], mk_span ($loc)) }
  | a = expr_add; PLUSPLUS; b = expr_mul { EApp (EVar (mk_name "++" $loc), [a; b], mk_span ($loc)) }
  | a = expr_add; PLUSDOT;  b = expr_mul { EApp (EVar (mk_name "+." $loc), [a; b], mk_span ($loc)) }
  | a = expr_add; MINUSDOT; b = expr_mul { EApp (EVar (mk_name "-." $loc), [a; b], mk_span ($loc)) }
  | e = expr_mul { e }

expr_mul:
  | a = expr_mul; STAR;     b = expr_unary { EApp (EVar (mk_name "*"  $loc), [a; b], mk_span ($loc)) }
  | a = expr_mul; SLASH;    b = expr_unary { EApp (EVar (mk_name "/"  $loc), [a; b], mk_span ($loc)) }
  | a = expr_mul; PERCENT;  b = expr_unary { EApp (EVar (mk_name "%"  $loc), [a; b], mk_span ($loc)) }
  | a = expr_mul; STARDOT;  b = expr_unary { EApp (EVar (mk_name "*." $loc), [a; b], mk_span ($loc)) }
  | a = expr_mul; SLASHDOT; b = expr_unary { EApp (EVar (mk_name "/." $loc), [a; b], mk_span ($loc)) }
  | e = expr_unary { e }

(** Unary operators: -expr, !expr *)
expr_unary:
  | MINUS; e = expr_unary
    { EApp (EVar (mk_name "negate" $loc), [e], mk_span ($loc)) }
  | BANG; e = expr_unary
    { EApp (EVar (mk_name "not" $loc), [e], mk_span ($loc)) }
  | e = expr_app { e }

expr_app:
  | f = expr_field; LPAREN; args = separated_list(COMMA, call_arg); RPAREN
    { EApp (f, args, mk_span ($loc)) }
  | con = UPPER_IDENT; LPAREN; RPAREN
    { ECon (mk_name con $loc, [], mk_span ($loc)) }
  | con = UPPER_IDENT; LPAREN; args = separated_nonempty_list(COMMA, call_arg); RPAREN
    { ECon (mk_name con $loc, args, mk_span ($loc)) }
  | e = expr_field %prec prec_app { e }

(** A call argument. Identical to [expr] except that an inline lambda
    literal (`fn ... -> ...`) gets a body grammar that additionally allows
    bare (non-[let]) statements before the final expression -- like
    [block_body], but without requiring [do...end] delimiters. This is
    safe ONLY in call-argument position because the argument is always
    unambiguously bounded by [,] or [)]; used as the general [expr]
    production (e.g. a [let] RHS embedded in a larger, still-open
    [block_body]), the same relaxation would make the parser unable to
    tell where the lambda's body ends and the enclosing statement sequence
    resumes. *)
call_arg:
  | FN; ps = lambda_params; ARROW; body = call_arg_lambda_body
    { ELam (ps, body, mk_span ($loc)) }
  | FN; ARROW; body = call_arg_lambda_body
    { ELam ([], body, mk_span ($loc)) }
  | e = expr_no_bare_lambda { e }

(** [expr] minus its top-level bare-lambda alternatives (`FN ... ARROW ...`
    with no enclosing delimiter). Used as [call_arg]'s fallback so there is
    exactly one way to parse a bare lambda in call-argument position (via
    [call_arg]'s own alternatives above) -- avoiding a grammar ambiguity
    between this rule and [call_arg]'s dedicated lambda alternatives.
    A parenthesized lambda `(fn ... -> ...)` is unaffected: it still goes
    through [expr] via [expr_atom]'s `LPAREN expr RPAREN`. *)
expr_no_bare_lambda:
  | e = expr_pipe { e }
  | ASSERT; e = expr
    { EAssert (e, mk_span ($loc)) }
  | IF; cond = expr; DO; t = block_body; ELSE; f = block_body; END
    { EIf (cond, t, f, mk_span ($loc)) }
  | IF; cond = expr; THEN; t = expr; ELSE; f = expr
    { EIf (cond, t, f, mk_span ($loc)) }
  | IF; _c = expr; DO; _t = block_body; ELSE; _f = block_body; error
    { error_raise
        "I was expecting `end` to close the if expression here:"
        (Some "if cond do\n    expr1\nelse\n    expr2\nend")
        $startpos($7) }
  | IF; _c = expr; DO; _t = block_body; error
    { error_raise
        "March `if` expressions always need an `else` branch:"
        (Some "if cond do\n    expr1\nelse\n    expr2\nend")
        $startpos($5) }
  | IF; _c = expr; THEN; _t = expr; error
    { error_raise
        "I don't recognize `then` here -- March uses do/end blocks instead."
        (Some "if cond do\n    expr1\nelse\n    expr2\nend")
        $startpos($3) }
  | IF; _c = expr; error
    { error_raise
        "I was expecting `do` after the condition here:"
        (Some "if cond do\n    expr1\nelse\n    expr2\nend")
        $startpos($3) }
  | MATCH; e = expr; DO; option(arm_sep); bs = separated_nonempty_list(arm_sep, branch); END
    { EMatch (e, bs, mk_span ($loc)) }
  (* Split rather than `MATCH; DO; option(arm_sep); ...`: the shared
     [option(arm_sep)] nonterminal (also used by [branch]'s and
     [choose_branch]'s leading separator) merges, via LALR state sharing, the
     epsilon (no-separator) case here with an unrelated derivation elsewhere
     in the automaton — silently losing the epsilon-reduce to a shift for
     nearly every lookahead token and rejecting the single-line, no-separator
     cond form (`match do expr -> body end`). Spelling out both alternatives
     explicitly keeps this production's states out of that shared automaton
     path. See specs/lang/grammar.md §5.3 for the full trace. *)
  | MATCH; DO; bs = separated_nonempty_list(arm_sep, cond_branch); END
    { ECond (bs, mk_span ($loc)) }
  | MATCH; DO; arm_sep; bs = separated_nonempty_list(arm_sep, cond_branch); END
    { ECond (bs, mk_span ($loc)) }
  | MATCH; _e = expr; DO; option(arm_sep); _bs = separated_nonempty_list(arm_sep, branch); error
    { error_raise
        "I was expecting `end` to close the match here:"
        None
        $startpos(_bs) }
  | MATCH; _e = expr; error
    { error_raise
        "I was expecting `do` after the match expression here:"
        (Some "match expr do\n    Pattern -> result\nend")
        $startpos($3) }
  | WITH; bindings = separated_nonempty_list(COMMA, with_binding);
    DO; body = block_body; END
    { build_with bindings body [] (mk_span ($loc)) }
  | WITH; bindings = separated_nonempty_list(COMMA, with_binding);
    DO; body = block_body;
    ELSE; option(arm_sep); else_arms = separated_nonempty_list(arm_sep, branch); END
    { build_with bindings body else_arms (mk_span ($loc)) }

call_arg_lambda_body:
  | stmts = nonempty_list(call_arg_lambda_stmt)
    { fold_letq stmts (mk_span ($loc)) }

call_arg_lambda_stmt:
  | LET; p = simple_pattern; ty = option(type_annot); EQUALS; ev = expr
    { ELet ({ bind_pat = p; bind_ty = ty; bind_lin = Unrestricted; bind_expr = ev },
            mk_span ($loc)) }
  | LINEAR; LET; p = simple_pattern; ty = option(type_annot); EQUALS; ev = expr
    { ELet ({ bind_pat = p; bind_ty = ty; bind_lin = Linear; bind_expr = ev },
            mk_span ($loc)) }
  | LET; QUESTION; p = simple_pattern; EQUALS; ev = expr
    { ELetQ (p, ev, EBlock ([], mk_span ($loc)), mk_span ($loc)) }
  | LET; STAR; p = simple_pattern; EQUALS; ev = expr
    { ELetStar (p, ev, EBlock ([], mk_span ($loc)), mk_span ($loc)) }
  | e = expr { e }

(** Field access: x.name — left-recursive for chained access: x.y.z
    Contextual keywords (send) are allowed as field names to support Chan.send(…). *)
expr_field:
  | e = expr_field; DOT; name = lower_name
    { EField (e, name, mk_span ($loc)) }
  | e = expr_field; DOT; name = upper_name
    (* Module chain access: A.B.c or A.B.C — upper segments are sub-module names *)
    { EField (e, name, mk_span ($loc)) }
  | e = expr_field; DOT; SEND
    (* Allow `send` keyword as a field/method name: Chan.send(…) *)
    { EField (e, mk_name "send" $loc, mk_span ($loc)) }
  | e = expr_field; DOT; CHOOSE
    (* Allow `choose` keyword as a field/method name: Chan.choose(…) *)
    { EField (e, mk_name "choose" $loc, mk_span ($loc)) }
  | e = expr_field; DOT; OFFER
    (* Allow `offer` keyword as a field/method name: Chan.offer(…) *)
    { EField (e, mk_name "offer" $loc, mk_span ($loc)) }
  | e = expr_atom { e }

expr_atom:
  | n = INT { ELit (LitInt n, mk_span ($loc)) }
  | f = FLOAT { ELit (LitFloat f, mk_span ($loc)) }
  | s = STRING { ELit (LitString s, mk_span ($loc)) }
  (* String interpolation: "hello ${name}!" *)
  | prefix = INTERP_START; parts = interp_parts
    { let sp = mk_span ($loc) in
      desugar_interp (ELit (LitString prefix, sp)) parts sp }
  (* Sigil expressions: ~H"...", ~H"""...""", ~H"hello ${name}" *)
  | c = SIGIL_PREFIX; s = STRING
    { ESigil (c, ELit (LitString s, mk_span ($loc)), mk_span ($loc)) }
  | c = SIGIL_PREFIX; prefix = INTERP_START; parts = interp_parts
    { let sp = mk_span ($loc) in
      ESigil (c, desugar_interp (ELit (LitString prefix, sp)) parts sp, sp) }
  | b = BOOL { ELit (LitBool b, mk_span ($loc)) }
  | a = ATOM; LPAREN; args = separated_list(COMMA, expr); RPAREN
    { EAtom (a, args, mk_span ($loc)) }
  | a = ATOM %prec prec_atom
    { EAtom (a, [], mk_span ($loc)) }
  | id = LOWER_IDENT { EVar (mk_name id $loc) }
  (* `_` as an expression: the refinement-value placeholder inside a
     refinement predicate `{ T | _ > 0 }`.  Elsewhere it resolves to an
     unbound variable `_` and is rejected in the typechecker. *)
  | UNDERSCORE       { EVar (mk_name "_" $loc) }
  | TAG              { EVar (mk_name "tag" $loc) }
  | con = UPPER_IDENT %prec prec_atom
    { ECon (mk_name con $loc, [], mk_span ($loc)) }
  | QUESTION; id = LOWER_IDENT
    { EHole (Some (mk_name id $loc), mk_span ($loc)) }
  | QUESTION %prec prec_hole
    { EHole (None, mk_span ($loc)) }
  | LPAREN; e = expr; RPAREN { e }
  | LPAREN; e = expr; COMMA; es = separated_nonempty_list(COMMA, expr); RPAREN
    { ETuple (e :: es, mk_span ($loc)) }
  | LPAREN; RPAREN { ETuple ([], mk_span ($loc)) }
  (* Same three forms opened by a statement-leading `(` (see [LPAREN_STMT]).
     Deliberately absent from the call rule above: that is what stops
     `let _ = a`⏎`()` from parsing as the single binding `let _ = a()`. *)
  | LPAREN_STMT; e = expr; RPAREN { e }
  | LPAREN_STMT; e = expr; COMMA; es = separated_nonempty_list(COMMA, expr); RPAREN
    { ETuple (e :: es, mk_span ($loc)) }
  | LPAREN_STMT; RPAREN { ETuple ([], mk_span ($loc)) }
  | DO; body = block_body; END { body }
  (* List comprehension: [expr for pat in expr] or [expr for pat in expr, pred] *)
  | LBRACKET; body = expr; FOR; pat = pattern; IN; src = expr; RBRACKET
    { let sp = mk_span ($loc) in
      desugar_list_comp body pat src None sp }
  | LBRACKET; body = expr; FOR; pat = pattern; IN; src = expr; COMMA; pred = expr; RBRACKET
    { let sp = mk_span ($loc) in
      desugar_list_comp body pat src (Some pred) sp }
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
  (* Record update: { state with count: state.count + 1 } *)
  | LBRACE; base = expr; WITH; updates = separated_nonempty_list(COMMA, record_field_expr); RBRACE
    { ERecordUpdate (base, updates, mk_span ($loc)) }
  (* Actor primitives *)
  | SPAWN; LPAREN; e = expr; RPAREN
    { ESpawn (e, mk_span ($loc)) }
  | SEND; LPAREN; cap = expr; COMMA; msg = expr; RPAREN
    { ESend (cap, msg, mk_span ($loc)) }
  (* Debugger: dbg() unconditional pause; dbg(expr) conditional/trace *)
  | DBG; LPAREN; RPAREN
    { EDbg (None, mk_span ($loc)) }
  | DBG; LPAREN; e = expr; RPAREN
    { EDbg (Some e, mk_span ($loc)) }
  (* Contextual keywords usable as variable names in expressions *)
  | STATE { EVar (mk_name "state" $loc) }

record_field_pat:
  | name = lower_name; COLON; p = pattern { (name, p) }
  | name = lower_name                     { (name, PatVar name) }

record_field_expr:
  | name = lower_name; COLON; e = expr { (name, e) }

(** Interpolation parts after the opening INTERP_START. *)
interp_parts:
  | e = expr; suffix = INTERP_END         { [(e, suffix)] }
  | e = expr; mid = INTERP_MID; rest = interp_parts { (e, mid) :: rest }

%inline arm_sep:
  | NL { () }
  | PIPE { () }

branch:
  | p = pattern; guard = option(when_guard); ARROW; e = block_body
    { { branch_pat = p; branch_guard = guard; branch_body = e } }
  | _p = pattern; _guard = option(when_guard); error
    { error_raise
        "I was expecting `->` in the match arm here:"
        (Some "Pattern -> result")
        $startpos($3) }

with_binding:
  | pat = pattern; GETS; e = expr
    { (pat, e) }

cond_branch:
  | e = expr; ARROW; body = block_body
    { (e, body) }
  | UNDERSCORE; ARROW; body = block_body
    { (ELit (LitBool true, mk_span ($loc($1))), body) }

(* ---- Patterns ---- *)

(** Qualified constructor name for patterns: either a bare UPPER_IDENT or
    a TypeName.CtorName two-segment form for disambiguation.
    The DOT-lookahead is conflict-free because DOT is not in follow(qualified_upper):
    qualified_upper only appears before LPAREN or at the end of a pattern, so
    seeing DOT after the first UPPER_IDENT always means shift (second alternative). *)
qualified_upper:
  | con = UPPER_IDENT
    { mk_name con $loc }
  | con1 = UPPER_IDENT; DOT; con2 = UPPER_IDENT
    { mk_name (con1 ^ "." ^ con2) $loc }

(* An as-pattern layer wrapping the ordinary pattern forms.  Written as
   `pattern_no_as AS lower_name` rather than left-recursively on `pattern`
   so that `p as a as b` is a parse error rather than a silent nesting, and
   so no precedence declaration is needed for AS.  Uses `lower_name`, not
   `soft_lower_name`: `soft_lower_name` accepts AS itself as an identifier
   (parser.mly:1491), and allowing `x as as` buys nothing. *)
pattern:
  | p = pattern_no_as; AS; n = lower_name
    { PatAs (p, n, mk_span ($loc)) }
  | p = pattern_no_as { p }

(* Or-patterns: `1 | 2 | 3`.  PIPE is also `arm_sep` (parser.mly:1409), but
   an arm separator only ever follows a COMPLETE branch — one that has
   already consumed its ARROW and body — so LR(1) distinguishes the two uses
   without a conflict.  Verified: adding this production leaves menhir's
   conflict count unchanged at 9. *)
pattern_no_as:
  | p = pattern_alt; PIPE; ps = separated_nonempty_list(PIPE, pattern_alt)
    { PatOr (p :: ps, mk_span ($loc)) }
  | p = pattern_alt { p }

pattern_alt:
  | con = qualified_upper; LPAREN; ps = separated_nonempty_list(COMMA, pattern); RPAREN
    { PatCon (con, ps) }
  | con = qualified_upper
    { PatCon (con, []) }
  | a = ATOM; LPAREN; ps = separated_nonempty_list(COMMA, pattern); RPAREN
    { PatAtom (a, ps, mk_span ($loc)) }
  | a = ATOM
    { PatAtom (a, [], mk_span ($loc)) }
  | p = simple_pattern { p }

simple_pattern:
  (* Record pattern: { x, y: p }.  This production places no restriction on
     which fields, or how many, appear.  In a match arm (and, transitively, a
     function parameter that dispatches through one), `infer_pattern`
     (typecheck.ml) drives the pattern's field types from the scrutinee's
     EXPECTED record type when one is known, so the field list is open: `{ x }`
     matches any record with an `x` field, whatever else it has, and naming a
     field the record lacks is an `unknown_record_field` error. Without a known
     expected type (an unannotated `let` pattern, or a bare pattern used
     directly as a function parameter — this grammar position has no
     annotation slot) `infer_pattern` falls back to synthesizing a CLOSED
     `TRecord` from just the fields named here, and since March records
     require exact field-set equality to unify (no width subtyping), such a
     pattern must name every field of the record it matches. Punned `{ x }`
     is shorthand for `{ x: x }`, mirroring the record-literal shorthand. *)
  | LBRACE; fields = separated_nonempty_list(COMMA, record_field_pat); RBRACE
    { PatRecord (fields, mk_span ($loc)) }
  | UNDERSCORE { PatWild (mk_span ($loc)) }
  | id = soft_lower_name { PatVar id }
  | n = INT { PatLit (LitInt n, mk_span ($loc)) }
  | MINUS; n = INT { PatLit (LitInt (-n), mk_span ($loc)) }
  | f = FLOAT { PatLit (LitFloat f, mk_span ($loc)) }
  | MINUS; f = FLOAT { PatLit (LitFloat (-.f), mk_span ($loc)) }
  | s = STRING { PatLit (LitString s, mk_span ($loc)) }
  | b = BOOL { PatLit (LitBool b, mk_span ($loc)) }
  | LPAREN; p = pattern; RPAREN { p }
  | LPAREN; p = pattern; COMMA; ps = separated_nonempty_list(COMMA, pattern); RPAREN
    { PatTuple (p :: ps, mk_span ($loc)) }
  (* A match arm may begin on a fresh line with a parenthesised/tuple pattern,
     in which case the token filter has already retagged the `(` as
     [LPAREN_STMT] (the previous arm's body ended in a value-ending token).
     Patterns have no call form, so accepting both spellings here is
     unambiguous. *)
  | LPAREN_STMT; p = pattern; RPAREN { p }
  | LPAREN_STMT; p = pattern; COMMA; ps = separated_nonempty_list(COMMA, pattern); RPAREN
    { PatTuple (p :: ps, mk_span ($loc)) }
  (* List literal patterns: []  →  Nil,  [a, b]  →  Cons(a, Cons(b, Nil)) *)
  | LBRACKET; RBRACKET
    { PatCon (mk_name "Nil" $loc, []) }
  | LBRACKET; ps = separated_nonempty_list(COMMA, pattern); RBRACKET
    { List.fold_right
        (fun p acc -> PatCon (mk_name "Cons" $loc, [p; acc]))
        ps
        (PatCon (mk_name "Nil" $loc, [])) }

(* ---- Names ---- *)

lower_name:
  | id = LOWER_IDENT { mk_name id $loc }
  | TAG              { mk_name "tag" $loc }

(** Like lower_name but also accepts certain keywords that are commonly
    used as variable / parameter names (e.g. `state` in actor code).
    Use this in binding positions — params, patterns, let bindings — so
    that `fn (state, event, payload) -> …` parses without errors. *)
soft_lower_name:
  | id = LOWER_IDENT  { mk_name id $loc }
  | STATE             { mk_name "state"    $loc }
  | INIT              { mk_name "init"     $loc }
  | LOOP              { mk_name "loop"     $loc }
  | ON                { mk_name "on"       $loc }
  | PROTOCOL          { mk_name "protocol" $loc }
  | APP               { mk_name "app"      $loc }
  | AS                { mk_name "as"       $loc }
  | WITH              { mk_name "with"     $loc }
  | WHEN              { mk_name "when"     $loc }
  | USE               { mk_name "use"      $loc }
  | IN                { mk_name "in"       $loc }
  | FOR               { mk_name "for"      $loc }
  | TAG               { mk_name "tag"      $loc }

upper_name:
  | id = UPPER_IDENT { mk_name id $loc }

expr_eof:
  | e = expr; EOF { e }

repl_input:
  | d = decl; EOF { March_ast.Ast.ReplDecl d }
  | LET; QUESTION; p = simple_pattern; EQUALS; e = expr; EOF
    { March_ast.Ast.ReplLetQ (p, e) }
  | LET; STAR; p = simple_pattern; EQUALS; e = expr; EOF
    { March_ast.Ast.ReplLetStar (p, e) }
  | e = expr; EOF { March_ast.Ast.ReplExpr e }
  | EOF           { March_ast.Ast.ReplEOF }
  (* Hint: `name = expr` looks like an assignment but should be `let name = expr`.
     This rule must come last so that valid decls/exprs are preferred above. *)
  | name = LOWER_IDENT; EQUALS
    { raise (March_errors.Errors.ParseError (
        Printf.sprintf
          "unexpected `%s = ...` — did you mean `let %s = ...`?" name name,
        Some (Printf.sprintf "let %s = expr" name),
        $startpos($2))) }

(** Parse a sequence of zero or more declarations and expressions, then EOF.
    Used by the browser REPL so multi-item inputs work:
        actor Counter do ... end
        let pid = spawn(Counter)
        send(pid, Inc(5))
        send(pid, Get())
        run_until_idle()
    Both declarations and bare expressions may appear in any order. *)
repl_sequence:
  | EOF { [] }
  | d = decl; rest = repl_sequence { March_ast.Ast.ReplDecl d :: rest }
  | LET; QUESTION; p = simple_pattern; EQUALS; e = expr; rest = repl_sequence
    { March_ast.Ast.ReplLetQ (p, e) :: rest }
  | LET; STAR; p = simple_pattern; EQUALS; e = expr; rest = repl_sequence
    { March_ast.Ast.ReplLetStar (p, e) :: rest }
  | e = expr; rest = repl_sequence { March_ast.Ast.ReplExpr e :: rest }
