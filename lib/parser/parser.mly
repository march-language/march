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
  (* Desugar a string interpolation into concatenation + to_string calls.
     desugar_interp prefix [(e1, s1); (e2, s2); ...] sp  produces:
       prefix ++ to_string(e1) ++ s1 ++ to_string(e2) ++ s2 ++ ...
     where to_string is the polymorphic builtin. *)
  let desugar_interp prefix parts sp =
    let cat a b = EApp (EVar { txt = "++"; span = sp }, [a; b], sp) in
    let to_s e  = EApp (EVar { txt = "to_string"; span = sp }, [e], sp) in
    List.fold_left (fun acc (e, seg) ->
        let with_e = cat acc (to_s e) in
        if seg = "" then with_e
        else cat with_e (ELit (LitString seg, sp))
      ) prefix parts

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
        go (DFn ({ fn_name = def.fn_name; fn_vis = vis; fn_doc = def.fn_doc; fn_ret_ty = final_ret; fn_clauses = all_clauses }, span) :: acc) rest'
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
%token PUB INTERFACE IMPL SIG EXTERN UNSAFE AS USE NEEDS REQUIRES
%token IMPORT ALIAS ONLY EXCEPT P_FN
%token APP ON_START ON_STOP
%token DBG DOC
%token SUPERVISE STRATEGY MAX_RESTARTS WITHIN
%token ONE_FOR_ONE ONE_FOR_ALL REST_FOR_ONE RESTART_KW
%token <string> INTERP_START
%token <string> INTERP_MID
%token <string> INTERP_END
%token LPAREN RPAREN LBRACE RBRACE LBRACKET RBRACKET
%token ARROW PIPE_ARROW
%token EQUALS COLON COMMA PIPE DOT
%token PLUSPLUS PLUS MINUS STAR SLASH PERCENT
%token PLUSDOT MINUSDOT STARDOT SLASHDOT
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
  | MOD; _n = upper_name; error
    { raise (March_errors.Errors.ParseError (
        "I was expecting `do` to start the module body here:",
        Some "mod Name do\n    ...\nend",
        $startpos($3))) }
  | error
    { raise (March_errors.Errors.ParseError (
        "March programs must start with a module declaration:",
        Some "mod Main do\n    fn main() do\n        ...\n    end\nend",
        $startpos($1))) }

(* ---- Declarations ---- *)

decl:
  | DOC; s = STRING; d = fn_decl
    { match d with
      | DFn (def, span) -> DFn ({ def with fn_doc = Some s }, span)
      | d -> d }
  | d = fn_decl        { d }
  | d = let_decl       { d }
  | d = type_decl      { d }
  | d = actor_decl     { d }
  | d = interface_decl { d }
  | d = impl_decl      { d }
  | d = sig_decl       { d }
  | d = extern_decl    { d }
  | d = mod_decl       { d }
  | d = use_decl       { d }
  | d = import_decl    { d }
  | d = alias_decl_rule { d }
  | d = protocol_decl  { d }
  | d = needs_decl     { d }
  | d = app_decl       { d }

(** Each fn clause is parsed as its own DFn with a single clause.
    The group_fn_clauses pass merges consecutive same-name clauses. *)
fn_decl:
  | FN; name = lower_name; LPAREN; params = separated_list(COMMA, fn_param); RPAREN;
    ret = option(ret_annot); guard = option(when_guard); DO; body = block_body; END
    { DFn ({ fn_name = name;
             fn_vis = Public;
             fn_doc = None;
             fn_ret_ty = ret;
             fn_clauses = [{ fc_params = params;
                             fc_guard = guard;
                             fc_body = body;
                             fc_span = mk_span ($loc) }] },
           mk_span ($loc)) }
  | P_FN; name = lower_name; LPAREN; params = separated_list(COMMA, fn_param); RPAREN;
    ret = option(ret_annot); guard = option(when_guard); DO; body = block_body; END
    { DFn ({ fn_name = name;
             fn_vis = Private;
             fn_doc = None;
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
             fn_doc = None;
             fn_ret_ty = ret;
             fn_clauses = [{ fc_params = params;
                             fc_guard = guard;
                             fc_body = body;
                             fc_span = mk_span ($loc) }] },
           mk_span ($loc)) }
  | FN; _n = lower_name; LPAREN; _ps = separated_list(COMMA, fn_param); RPAREN; error
    { raise (March_errors.Errors.ParseError (
        "I was expecting `do` to start the function body here:",
        Some "fn name(params) do\n    body\nend",
        $startpos($6))) }
  | P_FN; _n = lower_name; LPAREN; _ps = separated_list(COMMA, fn_param); RPAREN; error
    { raise (March_errors.Errors.ParseError (
        "I was expecting `do` to start the function body here:",
        Some "p_fn name(params) do\n    body\nend",
        $startpos($6))) }
  | PUB; FN; _n = lower_name; LPAREN; _ps = separated_list(COMMA, fn_param); RPAREN; error
    { raise (March_errors.Errors.ParseError (
        "I was expecting `do` to start the function body here:",
        Some "pub fn name(params) do\n    body\nend",
        $startpos($7))) }

when_guard:
  | WHEN; e = expr { e }

(** Function parameters: can be patterns (for head matching) or named params. *)
fn_param:
  | p = pattern { FPPat p }
  | name = lower_name; COLON; t = ty
    { FPNamed { param_name = name; param_ty = Some t; param_lin = Unrestricted } }
  | LINEAR; name = lower_name; COLON; t = ty
    { FPNamed { param_name = name; param_ty = Some t; param_lin = Linear } }

let_decl:
  | LET; p = simple_pattern; ty = option(type_annot); EQUALS; e = expr
    { DLet ({ bind_pat = p; bind_ty = ty; bind_lin = Unrestricted; bind_expr = e },
            mk_span ($loc)) }
  | LET; _p = simple_pattern; _ty = option(type_annot); error
    { raise (March_errors.Errors.ParseError (
        "I was expecting `=` in the let binding here:",
        Some "let name = expr",
        $startpos($4))) }

type_decl:
  | TYPE; name = upper_name; tparams = option(type_params); EQUALS;
    variants = separated_nonempty_list(PIPE, variant)
    { let tps = match tparams with Some ps -> ps | None -> [] in
      DType (name, tps, TDVariant variants, mk_span ($loc)) }
  | TYPE; name = upper_name; tparams = option(type_params); EQUALS;
    LBRACE; fields = separated_list(COMMA, field); RBRACE
    { let tps = match tparams with Some ps -> ps | None -> [] in
      DType (name, tps, TDRecord fields, mk_span ($loc)) }
  | TYPE; _n = upper_name; error
    { raise (March_errors.Errors.ParseError (
        "I was expecting `=` after the type name here:",
        Some "type Name = Variant1 | Variant2(Int)",
        $startpos($3))) }

actor_decl:
  | ACTOR; _n = upper_name; error
    { raise (March_errors.Errors.ParseError (
        "I was expecting `do` after the actor name here:",
        Some "actor Name do\n    state { field: Type }\n    init ...\n    on Msg(x) do ... end\nend",
        $startpos($3))) }
  | ACTOR; name = upper_name; DO;
    STATE; LBRACE; fields = separated_list(COMMA, field); RBRACE;
    INIT; init_expr = expr;
    sup = option(supervise_block);
    handlers = list(actor_handler);
    END
    { DActor (name,
              { actor_state = fields; actor_init = init_expr; actor_handlers = handlers;
                actor_supervise = sup },
              mk_span ($loc)) }

(** Application entry point:
      app MyApp do
        on_start do ... end   (* optional *)
        on_stop  do ... end   (* optional *)
        Supervisor.spec(:one_for_one, [...])
      end *)
app_decl:
  | APP; _n = upper_name; error
    { raise (March_errors.Errors.ParseError (
        "I was expecting `do` after the app name here:",
        Some "app MyApp do\n    Supervisor.spec(:one_for_one, [...])\nend",
        $startpos($3))) }
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
    { let names = List.map fst children in
      let tyfields = List.map (fun (n, t) ->
        { sf_name = n; sf_ty = t }) children in
      { sc_fields = tyfields;
        sc_strategy = strat;
        sc_max_restarts = max_r;
        sc_window_secs = win;
        sc_order = names } }

supervise_child:
  | actor_type = upper_name; field_name = lower_name
    { (field_name, TyCon (actor_type, [])) }

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
    end *)
protocol_decl:
  | PROTOCOL; name = upper_name; DO; steps = list(protocol_step); END
    { DProtocol (name, { proto_steps = steps }, mk_span ($loc)) }

protocol_step:
  | sender = upper_name; ARROW; receiver = upper_name; COLON; t = ty
    { ProtoMsg (sender, receiver, t) }
  | LOOP; DO; steps = list(protocol_step); END
    { ProtoLoop steps }

(** Nested module: mod Name do ... end *)
mod_decl:
  | MOD; name = upper_name; DO; decls = list(decl); END
    { DMod (name, Public, group_fn_clauses decls, mk_span ($loc)) }
  | PUB; MOD; name = upper_name; DO; decls = list(decl); END
    { DMod (name, Public, group_fn_clauses decls, mk_span ($loc)) }
  | MOD; _n = upper_name; error
    { raise (March_errors.Errors.ParseError (
        "I was expecting `do` after the module name here:",
        Some "mod Name do\n    ...\nend",
        $startpos($3))) }
  | PUB; MOD; _n = upper_name; error
    { raise (March_errors.Errors.ParseError (
        "I was expecting `do` after the module name here:",
        Some "pub mod Name do\n    ...\nend",
        $startpos($4))) }

(** Import declaration: use Mod.* or use Mod.{f, g} or use Mod
    Single-level module paths to avoid shift/reduce conflicts with DOT. *)
use_decl:
  | USE; name = upper_name; DOT; sel = use_selector
    { DUse ({ use_path = [name]; use_sel = sel }, mk_span ($loc)) }
  | USE; name = upper_name
    { DUse ({ use_path = [name]; use_sel = UseSingle }, mk_span ($loc)) }

use_selector:
  | STAR
    { UseAll }
  | LBRACE; names = separated_list(COMMA, lower_name); RBRACE
    { UseNames names }

(** Elixir-style import: import Mod, import Mod, only: [f,g], import Mod, except: [f,g] *)
import_decl:
  | IMPORT; name = upper_name
    { DUse ({ use_path = [name]; use_sel = UseAll }, mk_span ($loc)) }
  | IMPORT; name = upper_name; COMMA; ONLY; COLON; LBRACKET;
    names = separated_list(COMMA, lower_name); RBRACKET
    { DUse ({ use_path = [name]; use_sel = UseNames names }, mk_span ($loc)) }
  | IMPORT; name = upper_name; COMMA; EXCEPT; COLON; LBRACKET;
    names = separated_list(COMMA, lower_name); RBRACKET
    { DUse ({ use_path = [name]; use_sel = UseExcept names }, mk_span ($loc)) }

(** alias Long.Name, as: Short  or  alias Long.Name  (short = last segment) *)
alias_decl_rule:
  | ALIAS; path = upper_dot_path; COMMA; AS; COLON; short = upper_name
    { DAlias ({ alias_path = path; alias_name = short }, mk_span ($loc)) }
  | ALIAS; path = upper_dot_path
    { let last = List.nth path (List.length path - 1) in
      DAlias ({ alias_path = path; alias_name = last }, mk_span ($loc)) }

upper_dot_path:
  | name = upper_name { [name] }
  | name = upper_name; DOT; rest = upper_dot_path { name :: rest }

(** Capability manifest: needs IO.Network, IO.Clock
    Each path is a dot-separated sequence of uppercase names stored as a name list. *)
needs_decl:
  | NEEDS; caps = separated_nonempty_list(COMMA, cap_path)
    { DNeeds (caps, mk_span ($loc)) }

cap_path:
  | id = upper_name { [id] }
  | id = upper_name; DOT; rest = cap_path { id :: rest }

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
    { raise (March_errors.Errors.ParseError (
        "Interfaces need a type parameter in parentheses:",
        Some "interface Name(a) do\n    fn method: a -> a\nend",
        $startpos($3))) }

method_sig:
  | FN; name = lower_name; COLON; t = ty;
    default = option(preceded_by_do_end(expr))
    { { md_name = name; md_ty = t; md_default = default } }

%inline preceded_by_do_end(X):
  | DO; x = X; END { x }

(** Interface implementation: impl Eq(Int) do fn eq(x, y) do x == y end end *)
impl_decl:
  | IMPL; iface = upper_name; LPAREN; t = ty; RPAREN;
    constraints = loption(preceded(WHEN, separated_nonempty_list(COMMA, constraint_expr)));
    DO; methods = list(fn_decl); END
    { DImpl ({
        impl_iface = iface;
        impl_ty = t;
        impl_constraints = constraints;
        impl_assoc_types = [];
        impl_methods =
          List.filter_map (function
            | DFn (def, _) -> Some (def.fn_name, def)
            | _ -> None) methods;
      }, mk_span ($loc)) }
  | IMPL; _iface = upper_name; error
    { raise (March_errors.Errors.ParseError (
        "Implementations need a type argument in parentheses:",
        Some "impl InterfaceName(ConcreteType) do\n    fn method(x) do ... end\nend",
        $startpos($3))) }

constraint_expr:
  | name = upper_name; LPAREN; t = ty; RPAREN { (name, [t]) }

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
  | FN; name = lower_name;
    LPAREN; params = separated_list(COMMA, typed_param); RPAREN;
    COLON; ret = ty
    { { ef_name = name; ef_params = params; ef_ret_ty = ret } }

typed_param:
  | name = lower_name; COLON; t = ty { (name, t) }

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
  | id = upper_name; DOT; rest = dotted_upper_tail; LPAREN; args = separated_nonempty_list(COMMA, ty); RPAREN
    { let joined = id.txt ^ "." ^ String.concat "." (List.map (fun (n : March_ast.Ast.name) -> n.txt) rest) in
      TyCon (mk_name joined $loc, args) }
  | t = ty_atom { t }

ty_atom:
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

dotted_upper_tail:
  | id = upper_name { [id] }
  | id = upper_name; DOT; rest = dotted_upper_tail { id :: rest }

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
  | LINEAR; LET; p = simple_pattern; ty = option(type_annot); EQUALS; e = expr
    { ELet ({ bind_pat = p; bind_ty = ty; bind_lin = Linear; bind_expr = e },
            mk_span ($loc)) }
  | LET; _p = simple_pattern; _ty = option(type_annot); error
    { raise (March_errors.Errors.ParseError (
        "I was expecting `=` in the let binding here:",
        Some "let name = expr",
        $startpos($4))) }
  | FN; name = lower_name; LPAREN; params = separated_list(COMMA, fn_param); RPAREN;
    ret = option(ret_annot); DO; body = block_body; END
    { let simple_params = List.filter_map (function
        | FPNamed fp ->
          Some { param_name = fp.param_name; param_ty = fp.param_ty;
                 param_lin = fp.param_lin }
        | FPPat (PatVar n) ->
          Some { param_name = n; param_ty = None; param_lin = Unrestricted }
        | FPPat _ -> None) params in
      ELetFn (name, simple_params, ret, body, mk_span ($loc)) }
  | FN; _n = lower_name; LPAREN; _ps = separated_list(COMMA, fn_param); RPAREN; error
    { raise (March_errors.Errors.ParseError (
        "I was expecting `do` to start the function body here:",
        Some "fn name(params) do\n    body\nend",
        $startpos($6))) }
  | e = expr { e }

expr:
  | e = expr_pipe { e }
  | FN; ps = lambda_params; ARROW; body = expr
    { ELam (ps, body, mk_span ($loc)) }
  | FN; ps = lambda_params; error
    { let params = String.concat " " (List.map (fun p -> p.param_name.txt) ps) in
      let hint = Printf.sprintf "fn %s -> expr" params in
      raise (March_errors.Errors.ParseError (
        "I was expecting `->` to start the lambda body here:",
        Some hint,
        $startpos($3))) }
  | IF; cond = expr; THEN; t = expr; ELSE; f = expr
    { EIf (cond, t, f, mk_span ($loc)) }
  | IF; _c = expr; THEN; _t = expr; error
    { raise (March_errors.Errors.ParseError (
        "March `if` expressions always need an `else` branch:",
        Some "if cond then\n    expr1\nelse\n    expr2",
        $startpos($5))) }
  | IF; _c = expr; error
    { raise (March_errors.Errors.ParseError (
        "I was expecting `then` after the condition here:",
        Some "if cond then\n    expr1\nelse\n    expr2",
        $startpos($3))) }
  | MATCH; e = expr; WITH; option(PIPE); bs = separated_nonempty_list(PIPE, branch); END
    { EMatch (e, bs, mk_span ($loc)) }
  | MATCH; _e = expr; WITH; option(PIPE); _bs = separated_nonempty_list(PIPE, branch); error
    { raise (March_errors.Errors.ParseError (
        "I was expecting `end` to close the match here:",
        None,
        $startpos($6))) }
  | MATCH; _e = expr; error
    { raise (March_errors.Errors.ParseError (
        "I was expecting `with` after the match expression here:",
        Some "match expr with\n    | Pattern -> result\nend",
        $startpos($3))) }

lambda_params:
  | name = lower_name { [{ param_name = name; param_ty = None; param_lin = Unrestricted }] }
  | UNDERSCORE { [{ param_name = mk_name "_" $loc; param_ty = None; param_lin = Unrestricted }] }
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
  | f = expr_field; LPAREN; args = separated_list(COMMA, expr); RPAREN
    { EApp (f, args, mk_span ($loc)) }
  | con = UPPER_IDENT; LPAREN; RPAREN
    { ECon (mk_name con $loc, [], mk_span ($loc)) }
  | con = UPPER_IDENT; LPAREN; args = separated_nonempty_list(COMMA, expr); RPAREN
    { ECon (mk_name con $loc, args, mk_span ($loc)) }
  | e = expr_field { e }

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
  | e = expr_atom { e }

expr_atom:
  | n = INT { ELit (LitInt n, mk_span ($loc)) }
  | f = FLOAT { ELit (LitFloat f, mk_span ($loc)) }
  | s = STRING { ELit (LitString s, mk_span ($loc)) }
  (* String interpolation: "hello ${name}!" *)
  | prefix = INTERP_START; parts = interp_parts
    { let sp = mk_span ($loc) in
      desugar_interp (ELit (LitString prefix, sp)) parts sp }
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

record_field_expr:
  | name = lower_name; EQUALS; e = expr { (name, e) }

(** Interpolation parts after the opening INTERP_START. *)
interp_parts:
  | e = expr; suffix = INTERP_END         { [(e, suffix)] }
  | e = expr; mid = INTERP_MID; rest = interp_parts { (e, mid) :: rest }

branch:
  | p = pattern; guard = option(when_guard); ARROW; e = block_body
    { { branch_pat = p; branch_guard = guard; branch_body = e } }
  | _p = pattern; _guard = option(when_guard); error
    { raise (March_errors.Errors.ParseError (
        "I was expecting `->` in the match arm here:",
        Some "| Pattern -> result",
        $startpos($3))) }

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

upper_name:
  | id = UPPER_IDENT { mk_name id $loc }

expr_eof:
  | e = expr; EOF { e }

repl_input:
  | d = decl; EOF { March_ast.Ast.ReplDecl d }
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
