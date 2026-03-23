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
[@@deriving show]

let dummy_span =
  { file = "<none>"; start_line = 0; start_col = 0; end_line = 0; end_col = 0 }

type name = { txt : string; span : span } [@@deriving show]

(** Linearity qualifiers for the linear/affine type system. *)
type linearity =
  | Unrestricted  (** Normal value, can be used any number of times *)
  | Linear        (** Must be used exactly once *)
  | Affine        (** Must be used at most once *)
[@@deriving show]

(** Visibility qualifiers for module system. *)
type visibility =
  | Private       (** Only visible within the defining module (default) *)
  | Public        (** Exported from the module *)
[@@deriving show]

(** Type expressions as written by the user (surface syntax). *)
type ty =
  | TyCon of name * ty list          (** Type constructor: List(Int) *)
  | TyVar of name                    (** Type variable: a *)
  | TyArrow of ty * ty               (** Function type: a -> b *)
  | TyTuple of ty list               (** Tuple type: (a, b, c) *)
  | TyRecord of (name * ty) list     (** Record type: { x : Int, y : Float } *)
  | TyLinear of linearity * ty       (** Linearity-annotated type *)
  | TyNat of int                     (** Type-level natural literal: 3 *)
  | TyNatOp of nat_op * ty * ty      (** Type-level arithmetic: n + m, n * m *)
  | TyChan of name * name            (** Session-typed channel endpoint: Chan(Role, Protocol) *)
[@@deriving show]

(** Type-level natural number operations. *)
and nat_op =
  | NatAdd  (** + *)
  | NatMul  (** * *)
[@@deriving show]

(** Literals. *)
type literal =
  | LitInt of int
  | LitFloat of float
  | LitString of string
  | LitBool of bool
  | LitAtom of string                (** Atom literal: :ok, :error *)
[@@deriving show]

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
[@@deriving show]

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
  | EIf of expr * expr * expr * span       (** if/then/else *)
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
[@@deriving show]

and param = {
  param_name : name;
  param_ty : ty option;
  param_lin : linearity;
}
[@@deriving show]

and binding = {
  bind_pat : pattern;
  bind_ty : ty option;      (** Optional type annotation *)
  bind_lin : linearity;
  bind_expr : expr;
}
[@@deriving show]

and branch = {
  branch_pat : pattern;
  branch_guard : expr option;
  branch_body : expr;
}
[@@deriving show]

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
  | DNeeds of name list list * span
  (** Capability manifest: [needs IO.Network, IO.Clock]
      Each [name list] is one capability path, e.g. [["IO";"Network"]; ["IO";"Clock"]] *)
  | DApp of app_def * span             (** Application entry point: app Name do ... end *)
  | DDeriving of name * name list * span
  (** Derive declaration: [derive Eq, Show for Color]
      name = type name; name list = interface names to derive.
      Expanded to [DImpl] blocks by the desugar pass. *)
[@@deriving show]

and app_def = {
  app_name     : name;
  app_body     : expr;               (** Returns Supervisor.Spec *)
  app_on_start : expr option;        (** Runs after tree is up *)
  app_on_stop  : expr option;        (** Runs after tree is down *)
}
[@@deriving show]

and use_decl = {
  use_path : name list;        (** Module path, e.g. [Collections] *)
  use_sel  : use_selector;
}
[@@deriving show]

and alias_decl = {
  alias_path : name list;      (** Original module path, e.g. [Collections; HashMap] *)
  alias_name : name;           (** Short name (defaults to last path segment) *)
}
[@@deriving show]

and use_selector =
  | UseAll                     (** .* — import all public names *)
  | UseNames of name list      (** .{f, g} — import named items *)
  | UseSingle                  (** no selector — import the module itself *)
  | UseExcept of name list     (** except: [f, g] — import all except listed *)
[@@deriving show]

(** A function is one or more clauses with the same name.
    Each clause has its own argument patterns and body.
    The compiler groups consecutive fn clauses with the same name.
    After desugaring, multi-clause fns become a single-clause fn with match. *)
and fn_def = {
  fn_name : name;
  fn_vis : visibility;
  fn_doc : string option;       (** Optional doc comment: doc "..." or doc """...""" *)
  fn_ret_ty : ty option;        (** Return type (need only appear on one clause) *)
  fn_clauses : fn_clause list;  (** One or more pattern-matching heads *)
}
[@@deriving show]

and fn_clause = {
  fc_params : fn_param list;    (** Patterns for this clause's arguments *)
  fc_guard : expr option;       (** Optional guard: when expr *)
  fc_body : expr;
  fc_span : span;
}
[@@deriving show]

(** Function parameters can be patterns (for head matching) or named params. *)
and fn_param =
  | FPPat of pattern              (** Pattern parameter: fn fib(0) *)
  | FPNamed of param              (** Named parameter: fn greet(name : String) *)
[@@deriving show]

and type_def =
  | TDAlias of ty                              (** Type alias *)
  | TDVariant of variant list                  (** Sum type / ADT *)
  | TDRecord of field list                     (** Record type *)
[@@deriving show]

and variant = { var_name : name; var_args : ty list; var_vis : visibility } [@@deriving show]
and field = { fld_name : name; fld_ty : ty; fld_lin : linearity } [@@deriving show]

and restart_strategy =
  | OneForOne    (** Only restart the crashed child *)
  | OneForAll    (** Kill and restart all children *)
  | RestForOne   (** Kill and restart children after the crashed one in order *)
[@@deriving show]

and supervise_field = {
  sf_name : name;
  sf_ty   : ty;
}
[@@deriving show]

and supervise_config = {
  sc_fields       : supervise_field list;
  sc_strategy     : restart_strategy;
  sc_max_restarts : int;
  sc_window_secs  : int;
  sc_order        : name list;   (** declared field order for rest_for_one *)
}
[@@deriving show]

and actor_def = {
  actor_state    : field list;
  actor_init     : expr;
  actor_handlers : actor_handler list;
  actor_supervise : supervise_config option;   (** Some = supervisor actor *)
}
[@@deriving show]

and actor_handler = {
  ah_msg    : name;
  ah_params : param list;
  ah_body   : expr;
}
[@@deriving show]

and protocol_def = {
  proto_steps : protocol_step list;
}
[@@deriving show]

and protocol_step =
  | ProtoMsg of name * name * ty                          (** Sender -> Receiver : MsgType *)
  | ProtoLoop of protocol_step list                       (** loop do ... end *)
  | ProtoChoice of name * (name * protocol_step list) list  (** choose by Role: label -> steps *)
[@@deriving show]

(** Interface (typeclass) definition:
    interface Eq(a) do ... end *)
and interface_def = {
  iface_name : name;
  iface_param : name;                    (** The type parameter: a in Eq(a) *)
  iface_superclasses : (name * ty list) list;  (** Superclass constraints *)
  iface_assoc_types : assoc_type_decl list;    (** Associated type declarations *)
  iface_methods : method_decl list;
}
[@@deriving show]

and assoc_type_decl = {
  at_name : name;
  at_constraints : ty list;              (** Constraints on the associated type *)
}
[@@deriving show]

and method_decl = {
  md_name : name;
  md_ty : ty;                            (** Method type signature *)
  md_default : expr option;              (** Optional default implementation *)
}
[@@deriving show]

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
[@@deriving show]

(** Module signature:
    sig Name do ... end *)
and sig_def = {
  sig_types : (name * name list) list;   (** Opaque type declarations: type Tree(a) *)
  sig_fns : (name * ty) list;            (** Function signatures: fn insert : ... *)
}
[@@deriving show]

(** FFI extern block:
    extern "libc" : Cap(LibC) do ... end *)
and extern_def = {
  ext_lib_name : string;                 (** C library name *)
  ext_cap_ty : ty;                       (** Capability type for this library *)
  ext_fns : extern_fn list;              (** Foreign function declarations *)
}
[@@deriving show]

and extern_fn = {
  ef_name : name;
  ef_params : (name * ty) list;          (** Parameter names and types *)
  ef_ret_ty : ty;                        (** Return type *)
}
[@@deriving show]

(** A module is a list of declarations. *)
type module_ = { mod_name : name; mod_decls : decl list } [@@deriving show]

(** Input to the REPL: a declaration, a bare expression, or EOF. *)
type repl_input =
  | ReplDecl of decl
  | ReplExpr of expr
  | ReplEOF
[@@deriving show]
