(** March AST — the core abstract syntax tree.

    Every node carries a [span] for error reporting provenance.
    This is a foundational design decision: source location metadata
    is attached from day one so error messages always have context. *)

type span = {
  file : string;
  start_line : int;
  start_col : int;
  end_line : int;
  end_col : int;
}

let dummy_span =
  { file = "<none>"; start_line = 0; start_col = 0; end_line = 0; end_col = 0 }

type name = { txt : string; span : span }

(** Linearity qualifiers for the linear/affine type system. *)
type linearity =
  | Unrestricted  (** Normal value, can be used any number of times *)
  | Linear        (** Must be used exactly once *)
  | Affine        (** Must be used at most once *)

(** Visibility qualifiers for module system. *)
type visibility =
  | Private       (** Only visible within the defining module (default) *)
  | Public        (** Exported from the module *)

(** Literals. *)
type literal =
  | LitInt of int
  | LitFloat of float
  | LitString of string
  | LitBool of bool
  | LitAtom of string                (** Atom literal: :ok, :error *)

(** Patterns for match expressions and let bindings. *)
type pattern =
  | PatWild of span                   (** Wildcard: _ *)
  | PatVar of name                    (** Variable binding *)
  | PatCon of name * pattern list     (** Constructor pattern: Some(x) *)
  | PatAtom of string * pattern list * span  (** Atom pattern: :ok(x), :error *)
  | PatTuple of pattern list * span   (** Tuple pattern: (a, b) *)
  | PatLit of literal * span          (** Literal pattern *)
  | PatRecord of (name * pattern) list * span (** Record pattern: { x, y = p } *)
  | PatAs of pattern * name * span    (** As pattern: pat as name *)
  | PatOr of pattern list * span      (** Or pattern: p1 | p2 | p3 *)

(** Expressions — the heart of the language. *)
type expr =
  | ELit of literal * span
  | EVar of name
  | EApp of expr * expr list * span        (** Function application: f(x, y) *)
  | ECon of name * expr list * span        (** Constructor application: Some(42) *)
  | ELam of param list * expr * span       (** Lambda: fn x -> x + 1 *)
  | EBlock of expr list * span             (** do ... end block *)
  | ELet of binding * span                 (** let x = expr (block-scoped) *)
  | EMatch of expr * branch list * span    (** match expr with | ... end *)
  | ETuple of expr list * span             (** Tuple construction *)
  | ERecord of (name * expr) list * span   (** Record literal: { x = 1, y = 2 } *)
  | ERecordUpdate of expr * (name * expr) list * span
      (** Record update: { state with count = state.count + 1 } *)
  | EField of expr * name * span           (** Field access: x.name *)
  | EIf of expr * expr * expr * span       (** if/do/else/end *)
  | ECond of (expr * expr) list * span     (** match do cond_arm* end — boolean chain *)
  | EPipe of expr * expr * span            (** x |> f *)
  | EAnnot of expr * ty * span             (** Type annotation *)
  | EHole of name option * span            (** Typed hole: ?name or ? *)
  | EAtom of string * expr list * span     (** Atom expression: :ok(x), :error *)
  | ESend of expr * expr * span            (** send(cap, msg) *)
  | ESpawn of expr * span                  (** spawn(Actor) *)
  | EResultRef of int option               (** REPL magic: v or v(N) — last/Nth result *)
  | EDbg of expr option * span
      (** Debugger: dbg() pauses unconditionally; dbg(bool_expr) pauses when true;
          dbg(val_expr) logs the value and returns it. *)
  | ELetFn of name * param list * ty option * expr * span
      (** Local named recursive function: fn go(params) : ret_ty do body end *)
  | ELetQ of pattern * expr * expr * span
      (** Result-propagating binding: [let? p = e1; e2].
          The third field is the continuation (everything after the binding);
          [fold_letq] in the parser nests continuations at parse time. *)
  | ELetStar of pattern * expr * expr * span
      (** Generalized monadic-bind sugar: [let* p = e1; e2] desugars to
          [M.flat_map(e1, fn p -> e2 end)], where [M] is the head type
          constructor of [e1]'s inferred type (e.g. [Option], [Result],
          [List]) -- resolved by convention: [M]'s `flat_map` is looked up
          in the module of the SAME name as [M]. Unlike [ELetQ], not
          hardwired to any one type. The third field is the continuation;
          [fold_letq] in the parser nests continuations for both [ELetQ]
          and [ELetStar] at parse time. See
          specs/lang/let-star-generalized-bind.md. *)
  | EAssert of expr * span
      (** Test assertion: assert expr.
          When the inner expr is a binary comparison (==, !=, <, >, <=, >=),
          the eval pass evaluates both sides separately for rich error messages. *)
  | ESigil of string * expr * span
      (** Sigil expression: ~H"...", ~xml"...", ~toml"...", etc.
          The string is the sigil name (e.g. "H", "xml", "toml").
          The expr is the string content (may include interpolation).
          Desugared to Sigil.x(content) call by the desugar pass. *)

and param = {
  param_name : name;
  param_ty : ty option;
  param_lin : linearity;
}

and binding = {
  bind_pat : pattern;
  bind_ty : ty option;      (** Optional type annotation *)
  bind_lin : linearity;
  bind_expr : expr;
}

and branch = {
  branch_pat : pattern;
  branch_guard : expr option;
  branch_body : expr;
}

(** Type expressions as written by the user (surface syntax).
    In the same recursive group as [expr] so that [TyRefine] can carry a
    predicate expression. *)
and ty =
  | TyCon of name * ty list          (** Type constructor: List(Int) *)
  | TyVar of name                    (** Type variable: a *)
  | TyArrow of ty * ty               (** Function type: a -> b *)
  | TyTuple of ty list               (** Tuple type: (a, b, c) *)
  | TyRecord of (name * ty) list     (** Record type: { x : Int, y : Float } *)
  | TyLinear of linearity * ty       (** Linearity-annotated type *)
  | TyNat of int                     (** Type-level natural literal: 3 *)
  | TyNatOp of nat_op * ty * ty      (** Type-level arithmetic: n + m, n * m *)
  | TyChan of name * name            (** Session-typed channel endpoint: Chan(Role, Protocol) *)
  | TyRefine of ty * name option * expr
    (** Refinement type: [{ T | predicate }] or [{ v : T | predicate }].
        The second field is the binder name ([None] means the implicit [_]).
        The predicate reuses the expression grammar; it is validated against
        the decidable fragment in the typechecker, not the parser. *)

(** Type-level natural number operations. *)
and nat_op =
  | NatAdd  (** + *)
  | NatMul  (** * *)

(** One arm of a [transitions] block: [ResourceTag: FromState -> ToState via fn_name] *)
type transition = {
  tr_resource : name;   (** The phantom resource tag, e.g. [ConnTag] *)
  tr_from     : name;   (** Source state, e.g. [Closed] *)
  tr_to       : name;   (** Target state, e.g. [Open] *)
  tr_via      : name;   (** The function that performs this transition *)
  tr_span     : span;   (** Span of the whole transition line *)
}

(** Top-level declarations. *)
type decl =
  | DFn of fn_def * span                                        (** fn name(args) do ... end *)
  | DLet of visibility * binding * span                         (** Top-level let binding *)
  | DType of visibility * name * name list * type_def * span    (** Type definition *)
  | DActor of visibility * name * actor_def * span              (** Actor definition *)
  | DProtocol of name * protocol_def * span        (** Protocol (session type) definition *)
  | DMod of name * visibility * decl list * span   (** Nested module *)
  | DSig of name * sig_def * span                  (** Module signature *)
  | DInterface of interface_def * span             (** Interface (typeclass) definition *)
  | DImpl of impl_def * span                       (** Interface implementation *)
  | DExtern of extern_def * span                   (** FFI extern block *)
  | DUse of use_decl * span                        (** Import: use Mod.* or use Mod.{f} *)
  | DAlias of alias_decl * span                    (** alias Long.Name, as: Short *)
  | DNeeds of (name list * string option) list * span
  (** Capability manifest: [needs IO.Network, IO.Clock]
      Each entry is one capability path, e.g. [["IO";"Network"]], paired with an
      optional PATH SCOPE from [needs IO.FileRead("/etc/myapp")].
      [None] means unscoped — any path — which is what every capability
      declared without a scope means, so existing source keeps its meaning.
      Only filesystem capabilities accept a scope; see [March_caps.Cap_scope]. *)
  | DProofCap of name * name option * span
  (** Proof capability declaration: [proof cap Migrated], optionally with a
      runtime DICTIONARY type: [proof cap Live with SessionOps].
      Registers an unforgeable capability that can only be minted inside the
      declaring module.  The optional second component names a record type
      declared in the same module: the type of the dictionary [cap_impl] may
      attach to this capability and [cap_dict] reads back.  [None] — every
      capability written before dictionaries existed — means the capability is
      runtime-erased exactly as before. *)
  | DOpts of string list * span
  (** Module-level capability directives: [`"no_panic"`] from `cap no_panic`.
      The list allows multiple future directives; Phase 3c only uses `"no_panic"`. *)
  | DAlwaysLinearType of visibility * name * name list * type_def * span
  (** Always-linear type definition: [always_linear type Handle(r, s) = Handle(r)]
      Identical to DType at the value level, but every binding of this type is
      automatically tracked as linear by the typechecker — no per-site [linear] annotation needed. *)
  | DTransitions of name * transition list * span
  (** Compiler-enforced state-machine transitions for an always-linear handle type.
      [transitions Handle do R: S1 -> S2 via fn_name ... end]
      The compiler verifies each [via] function has the expected type, and warns
      about functions in the same module that perform undeclared transitions. *)
  | DApp of app_def * span             (** Application entry point: app Name do ... end *)
  | DDeriving of name * name list * span
  (** Derive declaration: [derive Eq, Show for Color]
      name = type name; name list = interface names to derive.
      Expanded to [DImpl] blocks by the desugar pass. *)
  | DSatisfy of name list * name list * span
  (** Satisfy declaration: [satisfy Named, Eq for User, Post]
      first name list = interface names; second = type names.
      Expanded to [DImpl] blocks by the desugar pass using existing functions. *)
  | DTest of test_def * span           (** Test case: test "name" do ... end *)
  | DDescribe of string * decl list * span (** describe "name" do tests end *)
  | DSetup of expr * span              (** Per-test setup: setup do ... end *)
  | DSetupAll of expr * span           (** One-time setup: setup_all do ... end *)

and test_def = {
  test_name : string;    (** Test name string — used for display and filtering *)
  test_body : expr;      (** Test body (block expression, should produce Unit) *)
}

and app_def = {
  app_name     : name;
  app_body     : expr;               (** Returns Supervisor.Spec *)
  app_on_start : expr option;        (** Runs after tree is up *)
  app_on_stop  : expr option;        (** Runs after tree is down *)
}

and use_decl = {
  use_path : name list;        (** Module path, e.g. [Collections] *)
  use_sel  : use_selector;
}

and alias_decl = {
  alias_path : name list;      (** Original module path, e.g. [Collections; HashMap] *)
  alias_name : name;           (** Short name (defaults to last path segment) *)
}

and use_selector =
  | UseAll                     (** .* — import all public names *)
  | UseNames of name list      (** .{f, g} — import named items *)
  | UseSingle                  (** no selector — import the module itself *)
  | UseExcept of name list     (** except: [f, g] — import all except listed *)

(** A function is one or more clauses with the same name.
    Each clause has its own argument patterns and body.
    The compiler groups consecutive fn clauses with the same name.
    After desugaring, multi-clause fns become a single-clause fn with match. *)
and fn_def = {
  fn_name : name;
  fn_vis : visibility;
  fn_doc : string option;       (** Optional doc comment: doc "..." or doc """...""" *)
  fn_attrs : string list;       (** Compiler attributes: @[no_warn_recursion] etc. *)
  fn_ret_ty : ty option;        (** Return type (need only appear on one clause) *)
  fn_clauses : fn_clause list;  (** One or more pattern-matching heads *)
  fn_bounds : (name * ty) list; (** Explicit type-variable bounds: [s : ConnState, ...] *)
}

and fn_clause = {
  fc_params : fn_param list;    (** Patterns for this clause's arguments *)
  fc_guard : expr option;       (** Optional guard: when expr *)
  fc_body : expr;
  fc_span : span;
  fc_params_span : span;
  (** The parameter list INCLUDING its parentheses — `()` for a nullary
      clause, `(a, b)` otherwise.

      Exists so a diagnostic can offer a mechanical fix that REWRITES the
      parameter list. R1 stage D needs exactly this: it tells a program which
      capabilities its `main` must be granted, and the fix has to turn `()`
      into `(_cap_console : Cap(IO.Console))`. No pre-existing span could
      express that — [fc_span] covers the whole clause (body included) and
      [fn_name.span] covers only the name, so replacing the latter would
      produce `fn main(…)() : ()`.

      For a clause SYNTHESIZED by desugar (default-argument expansion,
      derive, multi-head merging) there are no source parentheses to point
      at, and this is set to the clause's own [fc_span]. Such a clause is
      never the target of a parameter-list fix — the fix is only ever offered
      for a `main` the user wrote. *)
}

(** Function parameters can be patterns (for head matching) or named params. *)
and fn_param =
  | FPPat of pattern              (** Pattern parameter: fn fib(0) *)
  | FPNamed of param              (** Named parameter: fn greet(name : String) *)
  | FPDefault of param * expr     (** Default value: fn greet(name, greeting \\ "Hello") *)

and type_def =
  | TDAlias of ty                              (** Type alias *)
  | TDVariant of variant list                  (** Sum type / ADT *)
  | TDRecord of field list                     (** Record type *)

and variant = { var_name : name; var_args : ty list; var_vis : visibility }
and field = { fld_name : name; fld_ty : ty; fld_lin : linearity }

and restart_strategy =
  | OneForOne    (** Only restart the crashed child *)
  | OneForAll    (** Kill and restart all children *)
  | RestForOne   (** Kill and restart children after the crashed one in order *)

(** Per-child restart policy on a supervise block.

    NOTE [Permanent] and [Transient] are behaviourally IDENTICAL in the local
    plane today: both restart on Killed and Crash, neither on Normal. In OTP the
    only difference between them is restart-on-normal-exit, and March's
    [Permanent] deliberately does not restart on a normal exit (do_actor_death
    already guards the supervisor notify with [reason != MARCH_DEATH_NORMAL],
    and changing that would alter every supervise block already written).

    [Transient] exists so a child spec reads the same locally and under
    [stdlib/dist_supervisor.march]'s RestartStrategy, and it will diverge if
    March ever adopts OTP's restart-on-normal Permanent. See
    specs/2026-08-17-supervisor-restart-types-design.md. *)
and restart_type = Permanent | Transient | Temporary

and supervise_field = {
  sf_name    : name;
  sf_ty      : ty;
  sf_restart : restart_type;   (** [Permanent] when the modifier is omitted *)
}

and supervise_config = {
  sc_fields       : supervise_field list;
  sc_strategy     : restart_strategy;
  sc_max_restarts : int;
  sc_window_secs  : int;
  sc_order        : name list;   (** declared field order for rest_for_one *)
}

and actor_def = {
  actor_state    : field list;
  actor_init     : expr;
  actor_handlers : actor_handler list;
  actor_supervise : supervise_config option;   (** Some = supervisor actor *)
  actor_compat   : string;                     (** @compat policy: "full" | "forward" | "any" *)
  actor_invariant : expr option;               (** @invariant predicate, if any *)
}

and actor_handler = {
  ah_msg    : name;
  ah_params : param list;
  ah_body   : expr;
}

and protocol_def = {
  proto_steps : protocol_step list;
}

and protocol_step =
  | ProtoMsg of name * name * ty                          (** Sender -> Receiver : MsgType *)
  | ProtoLoop of protocol_step list                       (** loop do ... end *)
  | ProtoChoice of name * (name * protocol_step list) list  (** choose by Role: label -> steps *)
  | ProtoStop of span                                     (** stop — exits an enclosing loop *)

(** Interface (typeclass) definition:
    interface Eq(a) do ... end *)
and interface_def = {
  iface_name : name;
  iface_param : name;                    (** The type parameter: a in Eq(a) *)
  iface_superclasses : (name * ty list) list;  (** Superclass constraints *)
  iface_assoc_types : assoc_type_decl list;    (** Associated type declarations *)
  iface_methods : method_decl list;
}

and assoc_type_decl = {
  at_name : name;
  at_constraints : ty list;              (** Constraints on the associated type *)
}

and method_decl = {
  md_name : name;
  md_ty : ty;                            (** Method type signature *)
  md_default : expr option;              (** Optional default implementation *)
}

(** Interface implementation:
    impl Eq(Int) do ... end
    impl Eq(a) for List(a) when Eq(a) do ... end *)
and impl_def = {
  impl_iface : name;                    (** Which interface *)
  impl_ty : ty;                         (** For which type *)
  impl_constraints : (name * ty list) list;  (** when clauses *)
  impl_assoc_types : (name * ty) list;       (** Associated type assignments *)
  impl_methods : (name * fn_def) list;       (** Method implementations *)
}

(** Module signature:
    sig Name do ... end *)
and sig_def = {
  sig_types : (name * name list) list;   (** Opaque type declarations: type Tree(a) *)
  sig_fns : (name * ty) list;            (** Function signatures: fn insert : ... *)
}

(** FFI extern block:
    extern "libc" : Cap(LibC) do ... end *)
and extern_def = {
  ext_lib_name : string;                 (** C library name *)
  ext_cap_ty : ty;                       (** Capability type for this library *)
  ext_fns : extern_fn list;              (** Foreign function declarations *)
}

and extern_fn = {
  ef_name : name;
  ef_params : (name * ty) list;          (** Parameter names and types *)
  ef_param_consumed : bool list;         (** Per-param: true if `consume` (ownership transferred to the binding) *)
  ef_blocking : bool;                    (** `blocking fn`: dispatch on an OS thread, yield the green thread *)
  ef_raises : bool;                      (** `raises fn`: env-routed errors — binding takes march_env*, returns bare Ok payload, calls march_raise for Err *)
  ef_ret_ty : ty;                        (** Return type *)
  ef_symbol : string option;             (** Explicit C symbol; default <lib>_<fn> *)
}

(** A module is a list of declarations. *)
type module_ = { mod_name : name; mod_decls : decl list }

(** Input to the REPL: a declaration, a bare expression, or EOF. *)
type repl_input =
  | ReplDecl of decl
  | ReplExpr of expr
  | ReplLetQ of pattern * expr
  | ReplLetStar of pattern * expr
      (** [let* p = e] at the prompt.  Unlike [ReplLetQ], which is hardwired
          to [Result], this binds through the value's own [flat_map] -- see
          [specs/lang/let-star-generalized-bind.md] and the REPL semantics
          note in [lib/repl/repl.ml]. *)
  | ReplEOF

(** Literal formatter matching ppx_deriving.show output — used by tir.ml's [@@deriving show]. *)
let pp_literal fmt = function
  | LitInt n    -> Format.fprintf fmt "(@[<hov2>Ast.LitInt@ %d@])" n
  | LitFloat f  -> Format.fprintf fmt "(@[<hov2>Ast.LitFloat@ %g@])" f
  | LitString s -> Format.fprintf fmt "(@[<hov2>Ast.LitString@ %S@])" s
  | LitBool b   -> Format.fprintf fmt "(@[<hov2>Ast.LitBool@ %b@])" b
  | LitAtom a   -> Format.fprintf fmt "(@[<hov2>Ast.LitAtom@ %S@])" a

let show_literal x = Format.asprintf "%a" pp_literal x

(** Surface type expression renderer — used in LSP hover and error messages. *)
let rec show_ty = function
  | TyCon (n, []) -> n.txt
  | TyCon (n, args) ->
    Printf.sprintf "%s(%s)" n.txt (String.concat ", " (List.map show_ty args))
  | TyVar n -> n.txt
  | TyArrow (a, b) -> Printf.sprintf "%s -> %s" (show_ty a) (show_ty b)
  | TyTuple ts -> Printf.sprintf "(%s)" (String.concat ", " (List.map show_ty ts))
  | TyRecord flds ->
    let fs = List.map (fun (n, t) -> Printf.sprintf "%s : %s" n.txt (show_ty t)) flds in
    Printf.sprintf "{ %s }" (String.concat ", " fs)
  | TyLinear (Linear, t) -> "linear " ^ show_ty t
  | TyLinear (Affine, t) -> "affine " ^ show_ty t
  | TyLinear (Unrestricted, t) -> show_ty t
  | TyNat n -> string_of_int n
  | TyNatOp (NatAdd, a, b) -> Printf.sprintf "%s + %s" (show_ty a) (show_ty b)
  | TyNatOp (NatMul, a, b) -> Printf.sprintf "%s * %s" (show_ty a) (show_ty b)
  | TyChan (role, proto) -> Printf.sprintf "Chan(%s, %s)" role.txt proto.txt
  | TyRefine (base, None, _) -> Printf.sprintf "{ %s | ... }" (show_ty base)
  | TyRefine (base, Some v, _) ->
    Printf.sprintf "{ %s : %s | ... }" v.txt (show_ty base)

(** Compact expression summary — used in test failure messages. *)
let show_expr = function
  | ELit (LitInt n, _) -> string_of_int n
  | ELit (LitFloat f, _) -> string_of_float f
  | ELit (LitString s, _) -> Printf.sprintf "%S" s
  | ELit (LitBool b, _) -> if b then "true" else "false"
  | ELit (LitAtom a, _) -> ":" ^ a
  | EVar n -> "EVar(" ^ n.txt ^ ")"
  | EApp _ -> "EApp(...)"
  | ECon (n, args, _) ->
    Printf.sprintf "ECon(%s, [%d args])" n.txt (List.length args)
  | ELam _ -> "ELam(...)"
  | EBlock _ -> "EBlock(...)"
  | ELet _ -> "ELet(...)"
  | EMatch _ -> "EMatch(...)"
  | ETuple _ -> "ETuple(...)"
  | ERecord _ -> "ERecord(...)"
  | ERecordUpdate _ -> "ERecordUpdate(...)"
  | EField (_, n, _) -> Printf.sprintf "EField(_, %s, _)" n.txt
  | EIf _ -> "EIf(...)"
  | ECond _ -> "ECond(...)"
  | EPipe _ -> "EPipe(...)"
  | EAnnot _ -> "EAnnot(...)"
  | EHole _ -> "EHole(...)"
  | EAtom (a, _, _) -> "EAtom(:" ^ a ^ ")"
  | ESend _ -> "ESend(...)"
  | ESpawn _ -> "ESpawn(...)"
  | EResultRef _ -> "EResultRef(...)"
  | EDbg _ -> "EDbg(...)"
  | ELetFn _ -> "ELetFn(...)"
  | ELetQ _ -> "ELetQ(...)"
  | ELetStar _ -> "ELetStar(...)"
  | EAssert _ -> "EAssert(...)"
  | ESigil _ -> "ESigil(...)"
