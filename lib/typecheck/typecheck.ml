(** March type checker — bidirectional Hindley-Milner with provenance.

    Architecture:
      §1   Provenance (reason chains for error messages)
      §2   Internal type representation (ty, tvar, scheme)
      §3   Fresh variable generation + level management
      §4   Type utilities (repr, occurs, free_ids)
      §5   Pretty-printing
      §6   Elm-style error message parts
      §7   Type environment
      §8   Generalization and instantiation
      §9   Built-in types + base environment
      §10  Unification
      §11  Surface-type → internal-type conversion
      §12  Linearity tracking
      §13  Pattern inference
      §14  Expression checking (bidirectional: infer / check)
      §15  Declaration checking
      §16  Module entry point

    Key design choices:
    - Bidirectional: [infer_expr] synthesises a type; [check_expr] verifies
      against a known expected type.  Annotations and fn return types drive
      the "checking" direction; everything else is inferred.
    - Provenance: every [unify] call carries a [reason] that explains *why*
      the expected type was expected.  Errors say "I expected X because Y".
    - Error recovery: unification failures record a diagnostic and return;
      the [TError] sentinel unifies with anything so checking continues.
    - Linearity: linear/affine vars are tracked via mutable [bool ref]
      "used" flags in the environment. *)

module Ast  = March_ast.Ast
module Err  = March_errors.Errors

(* =================================================================
   §1  Provenance — why was this type expected?
   ================================================================= *)

(** A [reason] explains why an expected type was expected.
    Carried through [unify] calls so errors can say more than
    "I expected X but found Y". *)
type reason =
  | RAnnotation of Ast.span            (** User wrote `: T` *)
  | RFnReturn   of string * Ast.span   (** Declared return of fn `name` *)
  | RFnArg      of Ast.span * int      (** Argument #i at a call site *)
  | RMatchArm   of Ast.span            (** All match arms must agree *)
  | RLetBind    of Ast.span            (** Rhs of a let binding *)
  | RBuiltin    of string              (** Invariant baked into the language *)
  | RBecause    of reason * string     (** Chain: A because "..." *)

let rec span_of_reason = function
  | RAnnotation sp       -> Some sp
  | RFnReturn (_, sp)    -> Some sp
  | RFnArg (sp, _)       -> Some sp
  | RMatchArm sp         -> Some sp
  | RLetBind sp          -> Some sp
  | RBuiltin _           -> None
  | RBecause (r, _)      -> span_of_reason r

let string_of_reason = function
  | RAnnotation _        -> "I got this expectation from the type annotation."
  | RFnReturn (name, _)  ->
    Printf.sprintf "This is the declared return type of `%s`." name
  | RFnArg (_, i)        ->
    Printf.sprintf "This is argument #%d of a function call." (i + 1)
  | RMatchArm _          -> "All branches of a match must have the same type."
  | RLetBind _           -> "This is the right-hand side of a let binding."
  | RBuiltin s           -> s
  | RBecause (_, s)      -> s

(* =================================================================
   §2  Internal type representation
   ================================================================= *)

(** Internal (elaborated) type.  Richer than the surface [Ast.ty]:
    carries unification variables with level information, and a [TError]
    sentinel that unifies with anything for graceful error recovery. *)
type ty =
  | TCon    of string * ty list          (** Int, List(a), Map(k,v) *)
  | TVar    of tvar ref                  (** Unification variable *)
  | TArrow  of ty * ty                   (** a -> b *)
  | TTuple  of ty list                   (** (a, b, c) — unit when empty *)
  | TRecord of (string * ty) list        (** { x : Int, y : Float } (sorted) *)
  | TLin    of Ast.linearity * ty        (** linear / affine wrapper *)
  | TNat    of int                       (** Type-level natural literal *)
  | TNatOp  of Ast.nat_op * ty * ty      (** n + m, n * m *)
  | TError                               (** Error sentinel *)

and tvar =
  | Unbound of int * int   (** id, generalization level *)
  | Link    of ty          (** Solved: points to this type *)

(** Lightweight type-class constraints.
    [CNum t] asserts t must be Int or Float (arithmetic).
    [COrd t] asserts t must be Int, Float, or String (ordered). *)
type constraint_ =
  | CNum of ty
  | COrd of ty

(** A type scheme encodes Hindley-Milner polymorphism.
    [Poly(ids, cs, ty)] represents ∀(α₁ … αₙ). τ where the αᵢ are the
    [Unbound] variable ids that are quantified, and [cs] are class
    constraints that must be discharged at each use site. *)
type scheme =
  | Mono of ty
  | Poly of int list * constraint_ list * ty

(* =================================================================
   §3  Fresh variable generation + level management
   ================================================================= *)

let _counter = ref 0
let fresh_id () = incr _counter; !_counter

(** Create a fresh unification variable at [level]. *)
let fresh_var level = TVar (ref (Unbound (fresh_id (), level)))

(* =================================================================
   §4  Type utilities
   ================================================================= *)

(** Follow a chain of [Link]s, applying path compression. *)
let rec repr = function
  | TVar r as t ->
    (match !r with
     | Link t' ->
       let t'' = repr t' in
       r := Link t'';     (* path compression *)
       t''
     | Unbound _ -> t)
  | t -> t

(** Does unification variable [id] at [level] appear free in [t]?
    Also adjusts levels of encountered unbound vars (for correct
    generalization — this is the standard Rémy/Damas-Milner trick). *)
let rec occurs id level = function
  | TVar r ->
    (match !r with
     | Unbound (id', l) ->
       if id = id' then true
       else (if l > level then r := Unbound (id', level); false)
     | Link t -> occurs id level t)
  | TCon   (_, args)    -> List.exists (occurs id level) args
  | TArrow (a, b)       -> occurs id level a || occurs id level b
  | TTuple ts           -> List.exists (occurs id level) ts
  | TRecord flds        -> List.exists (fun (_, t) -> occurs id level t) flds
  | TLin   (_, t)       -> occurs id level t
  | TNatOp (_, a, b)    -> occurs id level a || occurs id level b
  | TNat _ | TError     -> false

(* =================================================================
   §5  Pretty-printing (used in error messages)
   ================================================================= *)

(** Cache of tvar id → display name ("a", "b", … "z", "a1", …) *)
let _tvar_names : (int, string) Hashtbl.t = Hashtbl.create 16
let _tvar_ctr    = ref 0

let tvar_display_name id =
  match Hashtbl.find_opt _tvar_names id with
  | Some n -> n
  | None   ->
    let i = !_tvar_ctr in
    incr _tvar_ctr;
    let n =
      let base = String.make 1 (Char.chr (Char.code 'a' + i mod 26)) in
      if i < 26 then base else base ^ string_of_int (i / 26)
    in
    Hashtbl.add _tvar_names id n; n

let rec pp_ty ?(parens = false) t =
  let t = repr t in
  let s = match t with
    | TError -> "<error>"
    | TCon (name, []) -> name
    | TCon (name, args) ->
      Printf.sprintf "%s(%s)" name
        (String.concat ", " (List.map (pp_ty ~parens:false) args))
    | TVar r ->
      (match !r with
       | Unbound (id, _) -> tvar_display_name id
       | Link t'         -> pp_ty t')
    | TArrow (a, b) ->
      let inner =
        Printf.sprintf "%s -> %s" (pp_ty ~parens:true a) (pp_ty b)
      in
      if parens then Printf.sprintf "(%s)" inner else inner
    | TTuple []  -> "()"
    | TTuple ts  ->
      Printf.sprintf "(%s)" (String.concat ", " (List.map (pp_ty ~parens:false) ts))
    | TRecord [] -> "{}"
    | TRecord flds ->
      let fs = List.map (fun (n, t) -> n ^ " : " ^ pp_ty t) flds in
      "{ " ^ String.concat ", " fs ^ " }"
    | TLin (Ast.Linear,        t) -> "linear " ^ pp_ty ~parens:true t
    | TLin (Ast.Affine,        t) -> "affine " ^ pp_ty ~parens:true t
    | TLin (Ast.Unrestricted,  t) -> pp_ty t
    | TNat n                      -> string_of_int n
    | TNatOp (Ast.NatAdd, a, b)   ->
      Printf.sprintf "%s + %s" (pp_ty a) (pp_ty b)
    | TNatOp (Ast.NatMul, a, b)   ->
      Printf.sprintf "%s * %s" (pp_ty a) (pp_ty b)
  in s

(* =================================================================
   §6  Elm-style error message parts
   ================================================================= *)

(** Structured pieces of an error message.  The terminal / LSP renderer
    decides how to colour each variant.  Compose them to build
    conversational messages like Elm's. *)
type message_part =
  | MPText   of string          (** Prose text *)
  | MPCode   of string          (** Inline code — rendered monospace *)
  | MPType   of ty              (** A type — rendered via [pp_ty] *)
  | MPBreak                     (** Paragraph break *)
  | MPBullet of message_part list

let render_parts parts =
  let buf = Buffer.create 64 in
  let rec go = function
    | MPText s  -> Buffer.add_string buf s
    | MPCode s  -> Buffer.add_char buf '`'; Buffer.add_string buf s;
                   Buffer.add_char buf '`'
    | MPType t  -> Buffer.add_char buf '`'; Buffer.add_string buf (pp_ty t);
                   Buffer.add_char buf '`'
    | MPBreak   -> Buffer.add_char buf '\n'
    | MPBullet ps ->
      Buffer.add_string buf "\n  - ";
      List.iter go ps
  in
  List.iter go parts;
  Buffer.contents buf

(* =================================================================
   §7  Type environment
   ================================================================= *)

(** Linear-use record: name, qualifier, "has been used" flag. *)
type lin_entry = {
  le_name : string;
  le_lin  : Ast.linearity;
  le_used : bool ref;
}

(** Constructor info — populated from [DType] declarations.
    Describes one variant of a sum type so we can give [ECon] and
    [PatCon] real types instead of fresh variables. *)
type ctor_info = {
  ci_type    : string;        (** Parent type name, e.g. "Result" *)
  ci_params  : string list;   (** Type param names in declaration order *)
  ci_arg_tys : Ast.ty list;   (** Surface arg types of this constructor *)
}

type env = {
  vars    : (string * scheme) list;        (** Term variable → scheme *)
  types   : (string * int) list;           (** Type constructor name → arity *)
  ctors   : (string * ctor_info) list;     (** Data constructor name → info *)
  records : (string * (string list * (string * Ast.ty) list)) list;
    (** Named record type definitions: name → (type_params, [(field, surface_ty)]) *)
  level   : int;                           (** Current generalization level *)
  lin     : lin_entry list;                (** Linear/affine use tracking *)
  errors  : Err.ctx;
  pending_constraints : constraint_ list ref; (** Accumulated use-site constraints *)
  type_map : (Ast.span, ty) Hashtbl.t;
  interfaces : (string * Ast.interface_def) list; (** Registered interfaces *)
  sigs       : (string * Ast.sig_def) list;       (** Registered module signatures *)
  mod_needs  : string list;
  (** Capabilities declared via [needs] in the current module scope, as dot-joined paths *)
  protocols  : (string * Ast.protocol_def) list; (** Registered session-type protocols *)
}

let make_env errors type_map = {
  vars = []; types = []; ctors = []; records = []; level = 0; lin = [];
  errors; pending_constraints = ref []; type_map;
  interfaces = []; sigs = [];
  mod_needs = []; protocols = [];
}

let enter_level env = { env with level = env.level + 1 }
let leave_level env = { env with level = env.level - 1 }

let lookup_var  name env = List.assoc_opt name env.vars
let lookup_type name env = List.assoc_opt name env.types
let lookup_ctor name env = List.assoc_opt name env.ctors

let bind_var name sch env =
  { env with vars = (name, sch) :: env.vars }

let bind_vars bindings env =
  List.fold_left (fun e (n, s) -> bind_var n s e) env bindings

(** Extend env with a new linear/affine variable. *)
let bind_linear name lin ty env =
  let le = { le_name = name; le_lin = lin; le_used = ref false } in
  { env with
    vars = (name, Mono ty) :: env.vars;
    lin  = le :: env.lin }

(* =================================================================
   §8  Generalization and instantiation
   ================================================================= *)

(** [generalize level ty] quantifies all [Unbound] vars at a level
    strictly greater than [level].  Called after leaving a let-binding
    level to achieve let-polymorphism. *)
let generalize level ty =
  let ids = ref [] in
  let rec collect t = match repr t with
    | TVar r ->
      (match !r with
       | Unbound (id, l) when l > level ->
         if not (List.mem id !ids) then ids := id :: !ids
       | _ -> ())
    | TCon   (_, args)   -> List.iter collect args
    | TArrow (a, b)      -> collect a; collect b
    | TTuple ts          -> List.iter collect ts
    | TRecord flds       -> List.iter (fun (_, t) -> collect t) flds
    | TLin   (_, t)      -> collect t
    | TNatOp (_, a, b)   -> collect a; collect b
    | TNat _ | TError    -> ()
  in
  collect ty;
  if !ids = [] then Mono ty else Poly (!ids, [], ty)

(** [instantiate level env sch] replaces each quantified variable in [sch]
    with a fresh unification variable at [level].  Any class constraints
    carried by [sch] are instantiated and appended to [env.pending_constraints]
    so they can be discharged at the enclosing declaration boundary. *)
let instantiate level env = function
  | Mono ty -> ty
  | Poly (ids, cs, ty) ->
    let subst = List.map (fun id -> (id, fresh_var level)) ids in
    let rec inst t = match repr t with
      | TVar r ->
        (match !r with
         | Unbound (id, _) ->
           (match List.assoc_opt id subst with
            | Some t' -> t'
            | None    -> t)
         | Link t' -> inst t')
      | TCon   (n, args)   -> TCon   (n, List.map inst args)
      | TArrow (a, b)      -> TArrow (inst a, inst b)
      | TTuple ts          -> TTuple (List.map inst ts)
      | TRecord flds       -> TRecord (List.map (fun (n, t) -> (n, inst t)) flds)
      | TLin   (l, t)      -> TLin   (l, inst t)
      | TNatOp (op, a, b)  -> TNatOp (op, inst a, inst b)
      | TNat _ | TError    -> t
    in
    let inst_cs = List.map (function
        | CNum t -> CNum (inst t)
        | COrd t -> COrd (inst t)) cs
    in
    env.pending_constraints := inst_cs @ !(env.pending_constraints);
    inst ty

(* =================================================================
   §9  Built-in types + base environment
   ================================================================= *)

let t_int    = TCon ("Int",    [])
let t_float  = TCon ("Float",  [])
let t_bool   = TCon ("Bool",   [])
let t_string = TCon ("String", [])
let t_unit   = TTuple []
let t_atom   = TCon ("Atom",   [])

let t_list   a     = TCon ("List",   [a])
let t_option a     = TCon ("Option", [a])
let t_result a e   = TCon ("Result", [a; e])
let t_pid    a     = TCon ("Pid",    [a])

let _t_list   = t_list
let _t_option = t_option
let _t_result = t_result
let _t_pid    = t_pid

(* =================================================================
   Capability hierarchy for needs / Cap checking.
   Each entry: (cap_path, parent_path option).
   Paths are dot-joined strings, e.g. "IO.FileRead".
   FFI caps like "LibC" are valid but not in this table — they are
   their own roots and have no subtyping relationship.
   ================================================================= *)

let io_cap_hierarchy : (string * string option) list = [
  ("IO",            None);
  ("IO.Console",    Some "IO");
  ("IO.FileSystem", Some "IO");
  ("IO.FileRead",   Some "IO.FileSystem");
  ("IO.FileWrite",  Some "IO.FileSystem");
  ("IO.Network",    Some "IO");
  ("IO.NetConnect", Some "IO.Network");
  ("IO.NetListen",  Some "IO.Network");
  ("IO.Process",    Some "IO");
  ("IO.Clock",      Some "IO");
]

(** [cap_ancestors cap] returns [cap] and all its ancestors, most-specific first.
    E.g., "IO.FileRead" → ["IO.FileRead"; "IO.FileSystem"; "IO"].
    FFI caps not in the table return just themselves. *)
let cap_ancestors cap =
  let rec go c acc =
    let acc' = c :: acc in
    match List.assoc_opt c io_cap_hierarchy with
    | Some (Some parent) -> go parent acc'
    | _ -> acc'
  in
  List.rev (go cap [])

(** [cap_subsumes parent child] — true if [parent] is an ancestor of (or equal to) [child].
    E.g., cap_subsumes "IO" "IO.FileRead" = true. *)
let cap_subsumes parent child =
  List.mem parent (cap_ancestors child)

(** [cap_path_of_names names] joins AST name list to dot-string. *)
let cap_path_of_names names =
  String.concat "." (List.map (fun (n : Ast.name) -> n.txt) names)

(** [cap_paths_in_surface_ty ty] returns all Cap(X) paths referenced in [ty]. *)
let rec cap_paths_in_surface_ty (ty : Ast.ty) : string list =
  match ty with
  | Ast.TyCon (con, [arg]) when con.txt = "Cap" ->
    (match arg with
     | Ast.TyCon (name, []) -> [name.txt]
     | _ -> [])
  | Ast.TyCon (_, args) -> List.concat_map cap_paths_in_surface_ty args
  | Ast.TyArrow (a, b) ->
    cap_paths_in_surface_ty a @ cap_paths_in_surface_ty b
  | Ast.TyTuple ts -> List.concat_map cap_paths_in_surface_ty ts
  | Ast.TyRecord fields ->
    List.concat_map (fun (_, t) -> cap_paths_in_surface_ty t) fields
  | Ast.TyLinear (_, t) -> cap_paths_in_surface_ty t
  | _ -> []

(** Built-in binary operator schemes.
    We use level-0 fresh vars for polymorphic ops — they will be
    properly instantiated each time [instantiate] is called. *)
let builtin_bindings : (string * scheme) list =
  (* Extract the id from a fresh TVar (always succeeds for fresh vars) *)
  let get_id = function
    | TVar r -> (match !r with Unbound (id, _) -> id | _ -> 0)
    | _ -> 0
  in
  (* ∀a. f(a) — unconstrained polymorphism *)
  let poly1 f =
    let a = fresh_var 0 in
    Poly ([get_id a], [], f a)
  in
  (* ∀a:Num. f(a) — a must be Int or Float *)
  let poly1_num f =
    let a = fresh_var 0 in
    Poly ([get_id a], [CNum a], f a)
  in
  (* ∀a:Ord. f(a) — a must be Int, Float, or String *)
  let poly1_ord f =
    let a = fresh_var 0 in
    Poly ([get_id a], [COrd a], f a)
  in
  (* ∀a b. f(a, b) — two unconstrained type variables *)
  let poly2 f =
    let a = fresh_var 0 in
    let b = fresh_var 0 in
    Poly ([get_id a; get_id b], [], f a b)
  in
  [
    (* Arithmetic: Num-constrained so they work on Int and Float *)
    ("+",  poly1_num (fun a -> TArrow (a, TArrow (a, a))));
    ("-",  poly1_num (fun a -> TArrow (a, TArrow (a, a))));
    ("*",  poly1_num (fun a -> TArrow (a, TArrow (a, a))));
    ("/",  poly1_num (fun a -> TArrow (a, TArrow (a, a))));
    ("%",  Mono (TArrow (t_int,    TArrow (t_int,    t_int))));
    ("negate", poly1_num (fun a -> TArrow (a, a)));
    (* Float-specific operators — always monomorphic *)
    ("+.", Mono (TArrow (t_float, TArrow (t_float, t_float))));
    ("-.", Mono (TArrow (t_float, TArrow (t_float, t_float))));
    ("*.", Mono (TArrow (t_float, TArrow (t_float, t_float))));
    ("/.", Mono (TArrow (t_float, TArrow (t_float, t_float))));
    (* Comparisons: Ord-constrained so they work on Int, Float, and String *)
    ("<",  poly1_ord (fun a -> TArrow (a, TArrow (a, t_bool))));
    (">",  poly1_ord (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("<=", poly1_ord (fun a -> TArrow (a, TArrow (a, t_bool))));
    (">=", poly1_ord (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("&&", Mono (TArrow (t_bool,   TArrow (t_bool,   t_bool))));
    ("||", Mono (TArrow (t_bool,   TArrow (t_bool,   t_bool))));
    (* Polymorphic equality: ==, != : ∀a. a -> a -> Bool *)
    ("==", poly1 (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("!=", poly1 (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("++",             Mono (TArrow (t_string, TArrow (t_string, t_string))));
    ("print",          Mono (TArrow (t_string, t_unit)));
    ("println",        Mono (TArrow (t_string, t_unit)));
    ("print_int",      Mono (TArrow (t_int,    t_unit)));
    ("print_float",    Mono (TArrow (t_float,  t_unit)));
    ("int_to_string",  Mono (TArrow (t_int,    t_string)));
    ("float_to_string",Mono (TArrow (t_float,  t_string)));
    ("bool_to_string", Mono (TArrow (t_bool,   t_string)));
    ("string_to_int",   Mono (TArrow (t_string, t_option t_int)));
    ("string_to_float", Mono (TArrow (t_string, t_option t_float)));
    ("string_length",   Mono (TArrow (t_string, t_int)));
    ("string_concat",  Mono (TArrow (t_string, TArrow (t_string, t_string))));
    ("read_line",      Mono (TArrow (t_unit,   t_string)));
    ("not",            Mono (TArrow (t_bool,   t_bool)));
    (* List helpers: ∀a. ... *)
    ("head",   poly1 (fun a -> TArrow (t_list a, a)));
    ("tail",   poly1 (fun a -> TArrow (t_list a, t_list a)));
    ("is_nil", poly1 (fun a -> TArrow (t_list a, t_bool)));
    (* Generic to_string: ∀a. a -> String *)
    ("to_string", poly1 (fun a -> TArrow (a, t_string)));
    (* Actor/respond: ∀a. a -> Unit *)
    ("respond", poly1 (fun a -> TArrow (a, t_unit)));
    (* Actor builtins *)
    ("kill",     poly1 (fun a -> TArrow (TCon ("Pid", [a]), t_unit)));
    ("is_alive", poly1 (fun a -> TArrow (TCon ("Pid", [a]), t_bool)));
    ("actor_get_int", poly1 (fun a -> TArrow (TCon ("Pid", [a]), TArrow (t_int, t_int))));
    (* Int primitives *)
    ("int_abs",         Mono (TArrow (t_int,   t_int)));
    ("int_pow",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_div",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_mod",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_div_euclid",  Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_mod_euclid",  Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_to_float",    Mono (TArrow (t_int,   t_float)));
    ("int_max_value",   Mono (TArrow (t_unit,  t_int)));
    ("int_min_value",   Mono (TArrow (t_unit,  t_int)));
    (* Float primitives *)
    ("float_abs",       Mono (TArrow (t_float, t_float)));
    ("float_floor",     Mono (TArrow (t_float, t_int)));
    ("float_ceil",      Mono (TArrow (t_float, t_int)));
    ("float_round",     Mono (TArrow (t_float, t_int)));
    ("float_truncate",  Mono (TArrow (t_float, t_int)));
    ("float_to_int",    Mono (TArrow (t_float, t_int)));
    ("float_is_nan",    Mono (TArrow (t_float, t_bool)));
    ("float_is_infinite",Mono (TArrow (t_float, t_bool)));
    ("float_infinity",  Mono (TArrow (t_unit,  t_float)));
    ("float_neg_infinity",Mono (TArrow (t_unit, t_float)));
    ("float_nan",       Mono (TArrow (t_unit,  t_float)));
    ("float_epsilon",   Mono (TArrow (t_unit,  t_float)));
    ("float_from_string",Mono (TArrow (t_string, t_option t_float)));
    ("float_to_string", Mono (TArrow (t_float,  t_string)));
    (* Math primitives *)
    ("math_sqrt",   Mono (TArrow (t_float, t_float)));
    ("math_cbrt",   Mono (TArrow (t_float, t_float)));
    ("math_pow",    Mono (TArrow (t_float, TArrow (t_float, t_float))));
    ("math_exp",    Mono (TArrow (t_float, t_float)));
    ("math_exp2",   Mono (TArrow (t_float, t_float)));
    ("math_log",    Mono (TArrow (t_float, t_float)));
    ("math_log2",   Mono (TArrow (t_float, t_float)));
    ("math_log10",  Mono (TArrow (t_float, t_float)));
    ("math_sin",    Mono (TArrow (t_float, t_float)));
    ("math_cos",    Mono (TArrow (t_float, t_float)));
    ("math_tan",    Mono (TArrow (t_float, t_float)));
    ("math_asin",   Mono (TArrow (t_float, t_float)));
    ("math_acos",   Mono (TArrow (t_float, t_float)));
    ("math_atan",   Mono (TArrow (t_float, t_float)));
    ("math_atan2",  Mono (TArrow (t_float, TArrow (t_float, t_float))));
    ("math_sinh",   Mono (TArrow (t_float, t_float)));
    ("math_cosh",   Mono (TArrow (t_float, t_float)));
    ("math_tanh",   Mono (TArrow (t_float, t_float)));
    (* String primitives *)
    ("string_is_empty",     Mono (TArrow (t_string, t_bool)));
    ("string_slice",        Mono (TArrow (t_string, TArrow (t_int, TArrow (t_int, t_string)))));
    ("string_contains",     Mono (TArrow (t_string, TArrow (t_string, t_bool))));
    ("string_starts_with",  Mono (TArrow (t_string, TArrow (t_string, t_bool))));
    ("string_ends_with",    Mono (TArrow (t_string, TArrow (t_string, t_bool))));
    ("string_index_of",     Mono (TArrow (t_string, TArrow (t_string, t_option t_int))));
    ("string_replace",      Mono (TArrow (t_string, TArrow (t_string, TArrow (t_string, t_string)))));
    ("string_replace_all",  Mono (TArrow (t_string, TArrow (t_string, TArrow (t_string, t_string)))));
    ("string_split",        Mono (TArrow (t_string, TArrow (t_string, t_list t_string))));
    ("string_join",         Mono (TArrow (t_list t_string, TArrow (t_string, t_string))));
    ("string_trim",         Mono (TArrow (t_string, t_string)));
    ("string_trim_start",   Mono (TArrow (t_string, t_string)));
    ("string_trim_end",     Mono (TArrow (t_string, t_string)));
    ("string_to_uppercase", Mono (TArrow (t_string, t_string)));
    ("string_to_lowercase", Mono (TArrow (t_string, t_string)));
    ("string_chars",        Mono (TArrow (t_string, t_list (TCon ("Char", [])))));
    ("string_from_chars",   Mono (TArrow (t_list (TCon ("Char", [])), t_string)));
    ("string_repeat",       Mono (TArrow (t_string, TArrow (t_int, t_string))));
    ("string_reverse",      Mono (TArrow (t_string, t_string)));
    ("string_pad_left",     Mono (TArrow (t_string, TArrow (t_int, TArrow (t_string, t_string)))));
    ("string_pad_right",    Mono (TArrow (t_string, TArrow (t_int, TArrow (t_string, t_string)))));
    ("string_byte_length",  Mono (TArrow (t_string, t_int)));
    ("string_split_first",   Mono (TArrow (t_string, TArrow (t_string, t_option (TTuple [t_string; t_string])))));
    ("string_grapheme_count",Mono (TArrow (t_string, t_int)));
    (* Char primitives *)
    ("char_is_alpha",        Mono (TArrow (TCon ("Char", []), t_bool)));
    ("char_is_digit",        Mono (TArrow (TCon ("Char", []), t_bool)));
    ("char_is_alphanumeric", Mono (TArrow (TCon ("Char", []), t_bool)));
    ("char_is_whitespace",   Mono (TArrow (TCon ("Char", []), t_bool)));
    ("char_is_uppercase",    Mono (TArrow (TCon ("Char", []), t_bool)));
    ("char_is_lowercase",    Mono (TArrow (TCon ("Char", []), t_bool)));
    ("char_to_uppercase",    Mono (TArrow (TCon ("Char", []), TCon ("Char", []))));
    ("char_to_lowercase",    Mono (TArrow (TCon ("Char", []), TCon ("Char", []))));
    ("char_to_int",          Mono (TArrow (TCon ("Char", []), t_int)));
    ("char_from_int",        Mono (TArrow (t_int, TCon ("Char", []))));
    (* Comparison primitives *)
    ("compare_int",    Mono (TArrow (t_int,    TArrow (t_int,    t_int))));
    ("compare_float",  Mono (TArrow (t_float,  TArrow (t_float,  t_int))));
    ("compare_string", Mono (TArrow (t_string, TArrow (t_string, t_int))));
    (* Diverging primitives *)
    ("panic",       poly1 (fun a -> TArrow (t_string, a)));
    ("todo_",       poly1 (fun a -> TArrow (t_string, a)));
    ("unreachable_",poly1 (fun a -> TArrow (t_unit,   a)));
    (* Task builtins — thunks use fn x -> expr (single Int param, ignored).
       task_spawn calls the thunk with 0, wraps result in Task(a). *)
    ("task_spawn",         poly1 (fun a -> TArrow (TArrow (t_int, a), TCon ("Task", [a]))));
    ("task_await",         poly1 (fun a -> TArrow (TCon ("Task", [a]), t_result a t_string)));
    ("task_await_unwrap",  poly1 (fun a -> TArrow (TCon ("Task", [a]), a)));
    ("task_yield",         Mono (TArrow (t_unit, t_unit)));
    ("task_spawn_steal",   poly1 (fun a -> TArrow (TCon ("WorkPool", []), TArrow (TArrow (t_int, a), TCon ("Task", [a])))));
    ("task_reductions",    Mono (TArrow (t_unit, t_int)));
    ("get_work_pool",      Mono (TCon ("WorkPool", [])));
    (* Capability builtins *)
    ("root_cap",   Mono (TCon ("Cap", [TCon ("IO", [])])));
    ("cap_narrow", poly1 (fun a -> TArrow (TCon ("Cap", [TCon ("IO", [])]), TCon ("Cap", [a]))));
    (* Phase 1: Monitor/link builtins *)
    ("monitor",      poly2 (fun a b -> TArrow (TCon ("Pid", [a]), TArrow (TCon ("Pid", [b]), t_int))));
    ("demonitor",    Mono (TArrow (t_int, t_unit)));
    ("mailbox_size", poly1 (fun a -> TArrow (TCon ("Pid", [a]), t_int)));
    (* Phase 4: Actor state introspection — reads a named field from actor state *)
    ("get_actor_field", poly2 (fun a b -> TArrow (TCon ("Pid", [a]), TArrow (t_string, t_option b))));
    (* Phase 4: Flush the async message queue — runs all pending handlers *)
    ("run_until_idle", Mono (TArrow (t_unit, t_unit)));
    (* Phase 6a: Register a cleanup resource with an actor — called on kill/crash *)
    ("register_resource", poly1 (fun a -> TArrow (TCon ("Pid", [a]),
        TArrow (t_string, TArrow (TArrow (t_unit, t_unit), t_unit)))));
    (* Phase 3: Epoch-based capability builtins *)
    ("get_cap",      poly1 (fun a -> TArrow (TCon ("Pid", [a]), TCon ("Option", [TCon ("Cap", [a])]))));
    ("send_checked", poly1 (fun a -> TArrow (TCon ("Cap", [a]), TArrow (a, t_atom))));
    (* Utility: convert Int to Pid (unsafe but needed for supervisor state fields) *)
    ("pid_of_int",   poly1 (fun a -> TArrow (t_int, TCon ("Pid", [a]))));
    (* Phase 5: task_spawn_link — like task_spawn but links to spawner *)
    ("task_spawn_link", poly1 (fun a -> TArrow (TArrow (t_int, a), TCon ("Task", [a]))));
    (* File I/O builtins *)
    ("file_exists",     Mono (TArrow (t_string, t_bool)));
    ("file_read",       poly1 (fun e -> TArrow (t_string, t_result t_string e)));
    ("file_write",      poly1 (fun e -> TArrow (t_string, TArrow (t_string, t_result t_unit e))));
    ("file_append",     poly1 (fun e -> TArrow (t_string, TArrow (t_string, t_result t_unit e))));
    ("file_delete",     poly1 (fun e -> TArrow (t_string, t_result t_unit e)));
    ("file_copy",       poly1 (fun e -> TArrow (t_string, TArrow (t_string, t_result t_unit e))));
    ("file_rename",     poly1 (fun e -> TArrow (t_string, TArrow (t_string, t_result t_unit e))));
    ("file_stat",       poly1 (fun e -> TArrow (t_string, t_result (TCon ("FileStat", [])) e)));
    ("file_open",       poly1 (fun e -> TArrow (t_string, t_result t_int e)));
    ("file_read_line",  Mono (TArrow (t_int, t_option t_string)));
    ("file_read_chunk", Mono (TArrow (t_int, TArrow (t_int, t_option t_string))));
    ("file_close",      Mono (TArrow (t_int, t_unit)));
    (* Dir I/O builtins *)
    ("dir_exists",      Mono (TArrow (t_string, t_bool)));
    ("dir_list",        poly1 (fun e -> TArrow (t_string, t_result (t_list t_string) e)));
    ("dir_mkdir",       poly1 (fun e -> TArrow (t_string, t_result t_unit e)));
    ("dir_mkdir_p",     poly1 (fun e -> TArrow (t_string, t_result t_unit e)));
    ("dir_rmdir",       poly1 (fun e -> TArrow (t_string, t_result t_unit e)));
    ("dir_rm_rf",       poly1 (fun e -> TArrow (t_string, t_result t_unit e)));
    (* String extra builtins *)
    ("string_last_index_of", Mono (TArrow (t_string, TArrow (t_string, t_option t_int))));
  ]

let builtin_types : (string * int) list =
  [ ("Int",    0); ("Float",  0); ("Bool",  0); ("String", 0);
    ("Char",   0); ("Byte",   0); ("Atom",  0); ("Unit",   0);
    ("List",   1); ("Option", 1); ("Array", 1); ("Set",    1);
    ("Result", 2); ("Map",    2);
    ("Pid",    1); ("Cap",    1); ("Future",1); ("Stream", 1);
    ("Task",   1); ("WorkPool", 0); ("Node",   0);
    ("Vector", 2); ("Matrix", 3); ("NDArray", 2);
    (* Capability token types — used as arguments to Cap(X) *)
    ("IO",            0); ("IO.Console",    0); ("IO.FileSystem", 0);
    ("IO.FileRead",   0); ("IO.FileWrite",  0); ("IO.Network",    0);
    ("IO.NetConnect", 0); ("IO.NetListen",  0); ("IO.Process",    0);
    ("IO.Clock",      0); ]

(** Built-in constructor table for Option, Result, and List, which are
    pre-registered types.  User-declared types are added via [DType]. *)
let builtin_ctors : (string * ctor_info) list =
  let mk_var s = Ast.TyVar { txt = s; span = Ast.dummy_span } in
  let mk_list_ty s = Ast.TyCon ({ txt = "List"; span = Ast.dummy_span }, [mk_var s]) in
  [ ("Some", { ci_type = "Option"; ci_params = ["a"];      ci_arg_tys = [mk_var "a"] });
    ("None", { ci_type = "Option"; ci_params = ["a"];      ci_arg_tys = [] });
    ("Ok",   { ci_type = "Result"; ci_params = ["a"; "e"]; ci_arg_tys = [mk_var "a"] });
    ("Err",  { ci_type = "Result"; ci_params = ["a"; "e"]; ci_arg_tys = [mk_var "e"] });
    ("Nil",  { ci_type = "List";   ci_params = ["a"];      ci_arg_tys = [] });
    ("Cons", { ci_type = "List";   ci_params = ["a"];
               ci_arg_tys = [mk_var "a"; mk_list_ty "a"] });
  ]

let base_env errors type_map =
  let env = make_env errors type_map in
  let env = bind_vars builtin_bindings env in
  { env with types = builtin_types; ctors = builtin_ctors }

(* =================================================================
   §10  Unification
   ================================================================= *)

(** Report a type mismatch with a conversational Elm-style message. *)
let report_mismatch env ~span ~reason expected found =
  let headline =
    render_parts
      [ MPText "I expected "; MPType expected;
        MPText " but found "; MPType found; MPText "." ]
  in
  let why_note =
    match reason with
    | None   -> []
    | Some r -> [ string_of_reason r ]
  in
  let labels =
    match reason with
    | Some r ->
      (match span_of_reason r with
       | Some rsp when rsp <> span ->
         [ { Err.lbl_span = rsp;
             lbl_message  = "the expected type comes from here" } ]
       | _ -> [])
    | None -> []
  in
  Err.report env.errors
    { Err.severity = Error; span; message = headline;
      labels; notes = why_note }

(** Unify [t1] and [t2], reporting any mismatch to [env.errors].
    Uses [TError] as a recovery sentinel — if either side is [TError]
    the constraint is silently satisfied (the error was already reported). *)
let rec unify env ~span ?(reason = None) t1 t2 =
  let t1 = repr t1 and t2 = repr t2 in
  match t1, t2 with
  (* Error sentinel absorbs everything *)
  | TError, _ | _, TError -> ()

  (* Same variable — trivially unified *)
  | TVar r1, TVar r2 when r1 == r2 -> ()

  (* Bind a variable *)
  | TVar r, t | t, TVar r ->
    (match !r with
     | Unbound (id, level) ->
       if occurs id level t then begin
         report_mismatch env ~span ~reason t1 t2;
         r := Link TError
       end else
         r := Link t
     | Link _ -> assert false)  (* repr should have resolved links *)

  | TCon (n1, a1), TCon (n2, a2) ->
    if n1 = n2 && List.length a1 = List.length a2 then
      List.iter2 (unify env ~span ~reason) a1 a2
    else
      (report_mismatch env ~span ~reason t1 t2)

  | TArrow (a1, b1), TArrow (a2, b2) ->
    unify env ~span ~reason a1 a2;
    unify env ~span ~reason b1 b2

  | TTuple ts1, TTuple ts2 when List.length ts1 = List.length ts2 ->
    List.iter2 (unify env ~span ~reason) ts1 ts2

  | TRecord f1, TRecord f2 ->
    let ns1 = List.map fst f1 and ns2 = List.map fst f2 in
    if ns1 <> ns2 then
      report_mismatch env ~span ~reason t1 t2
    else
      List.iter2
        (fun (_, t1) (_, t2) -> unify env ~span ~reason t1 t2)
        f1 f2

  | TLin (l1, inner1), TLin (l2, inner2) when l1 = l2 ->
    unify env ~span ~reason inner1 inner2

  | TNat n1, TNat n2 when n1 = n2 -> ()

  | TNatOp (op1, a1, b1), TNatOp (op2, a2, b2) when op1 = op2 ->
    unify env ~span ~reason a1 a2;
    unify env ~span ~reason b1 b2

  | _ ->
    report_mismatch env ~span ~reason t1 t2

(* =================================================================
   §11  Surface-type → internal-type conversion
   ================================================================= *)

(** Convert a surface [Ast.ty] to an internal [ty].
    [tvars] accumulates a mapping from type-variable *names* to fresh
    unification-variable ids (so that two mentions of [a] in the same
    annotation get the same variable). *)
let rec surface_ty env ~(tvars : (string * ty) list ref) (s : Ast.ty) : ty =
  match s with
  | Ast.TyCon (name, args) ->
    let arity = match lookup_type name.txt env with
      | Some a -> a
      | None   ->
        Err.error env.errors ~span:name.span
          (Printf.sprintf "I don't know a type called `%s`." name.txt);
        0
    in
    let args' = List.map (surface_ty env ~tvars) args in
    if List.length args' <> arity then
      Err.error env.errors ~span:name.span
        (Printf.sprintf "`%s` expects %d type argument(s) but got %d."
           name.txt arity (List.length args'));
    (* If this is a named record type, expand it structurally so that
       type annotations like `: Point` unify correctly with record literals. *)
    (match List.assoc_opt name.txt env.records with
     | Some (params, field_decls) when List.length params = List.length args' ->
       let saved = !tvars in
       List.iter2 (fun pname arg -> tvars := (pname, arg) :: !tvars) params args';
       let flds = List.map (fun (fn, fty) -> (fn, surface_ty env ~tvars fty)) field_decls in
       tvars := saved;
       TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) flds)
     | _ ->
       (* Normalize built-in unit/bool so surface annotations unify with internal reps *)
       match name.txt with
       | "Unit" -> t_unit
       | _ -> TCon (name.txt, args'))

  | Ast.TyVar name ->
    (match List.assoc_opt name.txt !tvars with
     | Some t -> t
     | None   ->
       let t = fresh_var env.level in
       tvars := (name.txt, t) :: !tvars;
       t)

  | Ast.TyArrow (a, b) ->
    TArrow (surface_ty env ~tvars a, surface_ty env ~tvars b)

  | Ast.TyTuple ts ->
    TTuple (List.map (surface_ty env ~tvars) ts)

  | Ast.TyRecord flds ->
    let flds' = List.map (fun (n, t) -> (n.Ast.txt, surface_ty env ~tvars t)) flds in
    TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) flds')

  | Ast.TyLinear (lin, t) ->
    TLin (lin, surface_ty env ~tvars t)

  | Ast.TyNat n  -> TNat n
  | Ast.TyNatOp (op, a, b) ->
    TNatOp (op, surface_ty env ~tvars a, surface_ty env ~tvars b)

(** Instantiate a constructor's type at the current level.
    Creates fresh unification variables for each type parameter of the
    parent type, then converts the constructor's argument surface-types
    using those variables.  Returns [(arg_tys, result_ty)]:
    - [arg_tys]   : the expected type of each constructor argument
    - [result_ty] : the type the fully-applied constructor produces *)
let instantiate_ctor env (ci : ctor_info) : ty list * ty =
  (* One fresh unification variable per type parameter *)
  let fresh_pairs = List.map (fun name -> (name, fresh_var env.level)) ci.ci_params in
  let tvars = ref fresh_pairs in
  (* Convert each argument's surface type, substituting the fresh vars *)
  let arg_tys = List.map (surface_ty env ~tvars) ci.ci_arg_tys in
  (* Build TCon(ParentType, [fresh_a; fresh_b; …]) *)
  let result_ty = TCon (ci.ci_type, List.map snd fresh_pairs) in
  (arg_tys, result_ty)

(** Try to expand a [TCon] of a named record type to [TRecord].
    Returns the [TRecord] type if the name is a known record def, else [None]. *)
let expand_record env ty =
  match repr ty with
  | TRecord _ as t -> Some t
  | TCon (name, args) ->
    (match List.assoc_opt name env.records with
     | Some (params, field_decls) when List.length params = List.length args ->
       let tvars = ref (List.combine params args) in
       let flds = List.map (fun (fn, fty) -> (fn, surface_ty env ~tvars fty)) field_decls in
       Some (TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) flds))
     | _ -> None)
  | _ -> None

(* =================================================================
   §12  Linearity tracking
   ================================================================= *)

(** Record a use of variable [name].  Errors if a linear var is used
    more than once. *)
let record_use name span env =
  match List.find_opt (fun e -> e.le_name = name) env.lin with
  | None -> ()   (* unrestricted — no tracking needed *)
  | Some le ->
    (match le.le_lin with
     | Ast.Linear when !(le.le_used) ->
       Err.error env.errors ~span
         (Printf.sprintf
            "The linear value `%s` is used more than once here.\n\
             Linear values must be consumed exactly once — they cannot \
             be copied or ignored." name)
     | Ast.Affine when !(le.le_used) ->
       Err.error env.errors ~span
         (Printf.sprintf
            "The affine value `%s` is used more than once here.\n\
             Affine values may be used at most once." name)
     | (Ast.Linear | Ast.Affine) ->
       le.le_used := true
     | Ast.Unrestricted -> ())

(** After a scope closes, check that every in-scope linear var was used. *)
let check_linear_all_consumed env ~scope_span in_scope_names =
  List.iter (fun le ->
      if List.mem le.le_name in_scope_names
      && le.le_lin = Ast.Linear
      && not !(le.le_used) then
        Err.error env.errors ~span:scope_span
          (Printf.sprintf
             "The linear value `%s` was never used.\n\
              Linear values must be consumed exactly once — did you \
              mean to pass it somewhere?" le.le_name)
    ) env.lin

(* =================================================================
   §13  Pattern inference
   ================================================================= *)

(** Infer the type that a pattern *expects*, and return the list of
    (name, scheme) bindings it introduces.

    We don't yet resolve constructor types through a type registry —
    ADT patterns produce fresh type variables.  That will be fixed
    when [DType] declarations populate the type registry. *)
let rec infer_pattern env (pat : Ast.pattern)
    : (string * scheme) list * ty =
  match pat with
  | Ast.PatWild _ ->
    [], fresh_var env.level

  | Ast.PatVar name ->
    let t = fresh_var env.level in
    [(name.txt, Mono t)], t

  | Ast.PatLit (lit, _) ->
    [], ty_of_lit lit

  | Ast.PatTuple (ps, _) ->
    let bs_tys  = List.map (infer_pattern env) ps in
    let bindings = List.concat_map fst bs_tys in
    let tys      = List.map snd bs_tys in
    bindings, TTuple tys

  | Ast.PatCon (name, ps) ->
    (match lookup_ctor name.txt env with
     | None ->
       Err.error env.errors ~span:name.span
         (Printf.sprintf
            "I don't know a constructor called `%s`.\n\
             Is this a typo, or did you forget to declare the type?" name.txt);
       let bindings = List.concat_map fst (List.map (infer_pattern env) ps) in
       bindings, TError
     | Some ci ->
       let arg_tys, result_ty = instantiate_ctor env ci in
       let n_expected = List.length arg_tys in
       let n_got      = List.length ps in
       if n_expected <> n_got then begin
         Err.error env.errors ~span:name.span
           (Printf.sprintf
              "Constructor `%s` expects %d argument(s) in a pattern but I got %d."
              name.txt n_expected n_got);
         let bindings = List.concat_map fst (List.map (infer_pattern env) ps) in
         bindings, TError
       end else begin
         let all_bindings = ref [] in
         List.iter2 (fun pat arg_ty ->
             let bindings, pat_ty = infer_pattern env pat in
             all_bindings := bindings @ !all_bindings;
             unify env ~span:name.span
               ~reason:(Some (RBuiltin
                 (Printf.sprintf "I'm checking the pattern for constructor `%s`."
                    name.txt)))
               pat_ty arg_ty
           ) ps arg_tys;
         !all_bindings, result_ty
       end)

  | Ast.PatAtom (_, ps, _) ->
    let bs_tys   = List.map (infer_pattern env) ps in
    let bindings  = List.concat_map fst bs_tys in
    bindings, t_atom

  | Ast.PatRecord (flds, _) ->
    let bindings = ref [] in
    let fld_tys = List.map (fun (name, pat) ->
        let bs, t = infer_pattern env pat in
        bindings := bs @ !bindings;
        (name.Ast.txt, t)
      ) flds
    in
    let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) fld_tys in
    !bindings, TRecord sorted

  | Ast.PatAs (inner, name, _) ->
    let bindings, t = infer_pattern env inner in
    (name.txt, Mono t) :: bindings, t

and ty_of_lit = function
  | Ast.LitInt    _ -> t_int
  | Ast.LitFloat  _ -> t_float
  | Ast.LitBool   _ -> t_bool
  | Ast.LitString _ -> t_string
  | Ast.LitAtom   _ -> t_atom

(* =================================================================
   §14  Expression checking — bidirectional
   ================================================================= *)

(** Extract a source span from an expression (outermost node). *)
let span_of_expr : Ast.expr -> Ast.span = function
  | Ast.ELit  (_, sp)           -> sp
  | Ast.EVar  name              -> name.span
  | Ast.EApp  (_, _, sp)        -> sp
  | Ast.ECon  (_, _, sp)        -> sp
  | Ast.ELam  (_, _, sp)        -> sp
  | Ast.EBlock (_, sp)          -> sp
  | Ast.ELet  (_, sp)           -> sp
  | Ast.EMatch (_, _, sp)       -> sp
  | Ast.ETuple (_, sp)          -> sp
  | Ast.ERecord (_, sp)         -> sp
  | Ast.ERecordUpdate (_, _, sp) -> sp
  | Ast.EField (_, _, sp)       -> sp
  | Ast.EIf   (_, _, _, sp)     -> sp
  | Ast.EPipe (_, _, sp)        -> sp
  | Ast.EAnnot (_, _, sp)       -> sp
  | Ast.EHole (_, sp)           -> sp
  | Ast.EAtom (_, _, sp)        -> sp
  | Ast.ESend (_, _, sp)        -> sp
  | Ast.ESpawn (_, sp)          -> sp
  | Ast.EResultRef _            -> Ast.dummy_span
  | Ast.EDbg (_, sp)            -> sp
  | Ast.ELetFn (_, _, _, _, sp) -> sp

(** [infer_expr env e] synthesises the type of [e], accumulating any
    errors into [env.errors]. *)
let rec infer_expr env (e : Ast.expr) : ty =
  let result =
    match e with
    (* ── Literals ─────────────────────────────────────────────────── *)
    | Ast.ELit (lit, _) ->
      ty_of_lit lit

    (* ── Variables ────────────────────────────────────────────────── *)
    | Ast.EVar name ->
      record_use name.txt name.span env;
      (match lookup_var name.txt env with
       | Some sch -> instantiate env.level env sch
       | None     ->
         Err.error env.errors ~span:name.span
           (Printf.sprintf
              "I cannot find a variable named `%s`.\n\
               Is it defined above this point, or perhaps misspelled?"
              name.txt);
         TError)

    (* ── Type annotations ─────────────────────────────────────────── *)
    | Ast.EAnnot (e, ann, sp) ->
      let tvars = ref [] in
      let expected = surface_ty env ~tvars ann in
      check_expr env e expected ~reason:(Some (RAnnotation sp));
      expected

    (* ── Typed holes ──────────────────────────────────────────────── *)
    | Ast.EHole (name, sp) ->
      let t = fresh_var env.level in
      let label = match name with Some n -> "?" ^ n.txt | None -> "?" in
      Err.report env.errors
        { Err.severity = Hint; span = sp;
          message = Printf.sprintf "Typed hole %s has type `%s`" label (pp_ty t);
          labels  = [];
          notes   = [ "Fill this hole with an expression of the type shown above." ] };
      t

    (* ── Function application ─────────────────────────────────────── *)
    | Ast.EApp (f, args, sp) ->
      let f_ty = infer_expr env f in
      infer_app env sp f_ty args 0

    (* ── Constructor application ──────────────────────────────────── *)
    | Ast.ECon (name, args, sp) ->
      (match lookup_ctor name.txt env with
       | None ->
         Err.error env.errors ~span:name.span
           (Printf.sprintf
              "I don't know a constructor called `%s`.\n\
               Is this a typo, or did you forget to declare the type?" name.txt);
         List.iter (fun a -> ignore (infer_expr env a)) args;
         TError
       | Some ci ->
         let arg_tys, result_ty = instantiate_ctor env ci in
         let n_expected = List.length arg_tys in
         let n_got      = List.length args in
         if n_expected <> n_got then begin
           Err.error env.errors ~span:sp
             (Printf.sprintf
                "Constructor `%s` expects %d argument(s) but I got %d."
                name.txt n_expected n_got);
           List.iter (fun a -> ignore (infer_expr env a)) args;
           TError
         end else begin
           List.iter2 (fun arg arg_ty ->
               check_expr env arg arg_ty
                 ~reason:(Some (RBuiltin
                   (Printf.sprintf "Argument to constructor `%s`." name.txt)))
             ) args arg_tys;
           result_ty
         end)

    (* ── Lambdas ──────────────────────────────────────────────────── *)
    | Ast.ELam (params, body, _) ->
      let param_tys, env' = bind_lam_params env params in
      let body_ty = infer_expr env' body in
      List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys body_ty

    (* ── do/end block ─────────────────────────────────────────────── *)
    | Ast.EBlock (exprs, _) ->
      infer_block env exprs

    (* ── let binding (block-scoped) ───────────────────────────────── *)
    | Ast.ELet (b, sp) ->
      (* When ELet appears as the last expression in a block it's a
         programmer error, but we give it type Unit and move on. *)
      let rhs_ty = infer_expr env b.bind_expr in
      let bindings, pat_ty = infer_pattern env b.bind_pat in
      let reason = Some (RLetBind sp) in
      unify env ~span:sp ~reason rhs_ty pat_ty;
      ignore bindings;
      t_unit

    (* ── match ────────────────────────────────────────────────────── *)
    | Ast.EMatch (scrut, branches, sp) ->
      let scrut_ty = infer_expr env scrut in
      infer_match env sp scrut_ty branches

    (* ── Tuples ───────────────────────────────────────────────────── *)
    | Ast.ETuple ([], _)  -> t_unit
    | Ast.ETuple (es, _)  -> TTuple (List.map (infer_expr env) es)

    (* ── Record literals ──────────────────────────────────────────── *)
    | Ast.ERecord (flds, _) ->
      let fld_tys = List.map (fun (n, e) -> (n.Ast.txt, infer_expr env e)) flds in
      TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) fld_tys)

    (* ── Record update: { base with f = e, … } ───────────────────── *)
    | Ast.ERecordUpdate (base, updates, sp) ->
      let base_ty   = infer_expr env base in
      let update_tys =
        List.map (fun (n, e) -> (n.Ast.txt, infer_expr env e)) updates
      in
      (match expand_record env (repr base_ty) with
       | Some (TRecord all_flds) ->
         List.iter (fun (fname, uty) ->
             match List.assoc_opt fname all_flds with
             | Some fty ->
               unify env ~span:sp
                 ~reason:(Some (RBuiltin
                   (Printf.sprintf "field `%s` must keep its original type" fname)))
                 fty uty
             | None ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf
                    "This record does not have a field called `%s`.\n\
                     The fields I know about are: %s"
                    fname
                    (String.concat ", " (List.map fst all_flds)))
           ) update_tys;
         base_ty
       | _ ->
       (match repr base_ty with
       | TVar _ ->
         (* Base type not yet known — build a partial record constraint *)
         let partial =
           TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b)
                      update_tys) in
         unify env ~span:sp base_ty partial;
         base_ty
       | other ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "I can only use `{ … with … }` on a record, but this \
               expression has type `%s`." (pp_ty other));
         TError))

    (* ── Field access: e.name ─────────────────────────────────────── *)
    | Ast.EField (e, name, sp) ->
      (* Module member access: if e is a bare uppercase identifier (module name),
         try looking up "ModName.field" in env.vars before falling back to
         record field access. *)
      let mod_access =
        match e with
        | Ast.ECon (modname, [], _) ->
          let qualified = modname.txt ^ "." ^ name.txt in
          (match lookup_var qualified env with
           | Some sch -> Some (instantiate env.level env sch)
           | None     -> None)
        | _ -> None
      in
      (match mod_access with
       | Some ty -> ty
       | None ->
      let e_ty = infer_expr env e in
      (match expand_record env (repr e_ty) with
       | Some (TRecord flds) ->
         (match List.assoc_opt name.txt flds with
          | Some t -> t
          | None   ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "This record does not have a field called `%s`.\n\
                  The fields I see are: %s"
                 name.txt
                 (String.concat ", " (List.map fst flds)));
            TError)
       | _ ->
         (match repr e_ty with
          | TVar _ ->
            (* Field-access on an unknown record type — return a fresh var for now.
               A row-polymorphism extension would constrain this properly. *)
            fresh_var env.level
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "I cannot access field `%s` because this expression has \
                  type `%s`, which is not a record." name.txt (pp_ty other));
            TError))
      (* close the None branch of mod_access match *)
      )

    (* ── if/then/else ─────────────────────────────────────────────── *)
    | Ast.EIf (cond, then_, else_, sp) ->
      check_expr env cond t_bool
        ~reason:(Some (RBuiltin "The condition of an if expression must be Bool."));
      let t_ty = infer_expr env then_ in
      let e_ty = infer_expr env else_ in
      unify env ~span:sp ~reason:(Some (RMatchArm sp)) t_ty e_ty;
      t_ty

    (* ── Pipes — must be desugared before reaching us ─────────────── *)
    | Ast.EPipe _ ->
      failwith
        "March type checker: encountered EPipe — \
         the desugaring pass must run before type checking."

    (* ── Atoms ────────────────────────────────────────────────────── *)
    | Ast.EAtom (_, args, _) ->
      List.iter (fun a -> ignore (infer_expr env a)) args;
      t_atom

    (* ── Actor messaging ──────────────────────────────────────────── *)
    | Ast.ESend (cap, msg, _) ->
      ignore (infer_expr env cap);
      ignore (infer_expr env msg);
      (* send() returns the handler's result — unconstrained so callers can
         match on Option(a) (drop semantics) or access record fields (state). *)
      fresh_var env.level

    | Ast.ESpawn (actor, _) ->
      ignore (infer_expr env actor);
      TCon ("Pid", [fresh_var env.level])

    (* ── REPL result reference ─────────────────────────────────────── *)
    | Ast.EResultRef _ ->
      (* Return a fresh unification variable — EResultRef is substituted
         by the REPL loop before typechecking, so this is a fallback. *)
      fresh_var env.level

    (* ── Debugger breakpoint / value trace ────────────────────────── *)
    | Ast.EDbg (None, _) -> t_unit
    | Ast.EDbg (Some inner, _) -> infer_expr env inner

    (* ── Local recursive named function (block-scoped) ─────────────── *)
    | Ast.ELetFn (name, params, ret_ann, body, sp) ->
      (* Typecheck the local fn and return the type of its closure.
         When appearing as a standalone expression (last in block), return
         the function type; the binding is only in effect for block context. *)
      let fn_ty = fresh_var env.level in
      let env_with_self = bind_var name.txt (Mono fn_ty) env in
      let param_tys, env_inner = bind_lam_params env_with_self params in
      let body_ty = infer_block env_inner [body] in
      let ret_ty  = match ret_ann with
        | None -> body_ty
        | Some ann ->
          let tvars = ref [] in
          let expected = surface_ty env ~tvars ann in
          unify env ~span:sp ~reason:None body_ty expected;
          expected
      in
      let arrow_ty = List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys ret_ty in
      unify env ~span:sp ~reason:None fn_ty arrow_ty;
      arrow_ty
  in
  Hashtbl.replace env.type_map (span_of_expr e) (repr result);
  result

(** [check_expr env e expected ~reason] verifies [e] has type [expected].
    Uses the "checking" direction for lambdas (peels off arrows) and for
    match expressions (checks each arm against [expected]).  Falls back
    to infer + unify for everything else. *)
and check_expr env (e : Ast.expr) (expected : ty) ~reason =
  let sp = span_of_expr e in
  Hashtbl.replace env.type_map sp (repr expected);
  match e, repr expected with

  (* Lambda in check mode: peel arrow types one-by-one *)
  | Ast.ELam (params, body, lsp), _ ->
    let rec peel ps ty env =
      match ps, repr ty with
      | [], body_ty ->
        check_expr env body body_ty ~reason
      | p :: rest, TArrow (arg_ty, ret_ty) ->
        let env' = bind_lam_param env lsp p (Some arg_ty) in
        peel rest ret_ty env'
      | _, _ ->
        let inferred = infer_expr env (Ast.ELam (params, body, lsp)) in
        unify env ~span:lsp ~reason inferred expected
    in
    peel params expected env

  (* Match in check mode: check each arm against expected *)
  | Ast.EMatch (scrut, branches, msp), _ ->
    let scrut_ty = infer_expr env scrut in
    List.iter (fun (br : Ast.branch) ->
        let bindings, pat_ty = infer_pattern env br.branch_pat in
        unify env ~span:msp ~reason:(Some (RMatchArm msp)) scrut_ty pat_ty;
        let env' = bind_vars bindings env in
        (match br.branch_guard with
         | Some g ->
           check_expr env' g t_bool
             ~reason:(Some (RBuiltin "Match guards must be Bool."))
         | None -> ());
        check_expr env' br.branch_body expected ~reason
      ) branches

  (* All other expressions: infer then unify *)
  | _ ->
    let inferred = infer_expr env e in
    unify env ~span:sp ~reason inferred expected

(** Thread function application through argument list, tracking arg index. *)
and infer_app env span f_ty args idx =
  match args, repr f_ty with
  | [], t -> t
  | arg :: rest, TArrow (param_ty, ret_ty) ->
    check_expr env arg param_ty
      ~reason:(Some (RFnArg (span, idx)));
    infer_app env span ret_ty rest (idx + 1)
  | arg :: rest, TVar _ ->
    (* f_ty not yet known — constrain it *)
    let arg_ty = infer_expr env arg in
    let ret_ty = fresh_var env.level in
    unify env ~span
      ~reason:(Some (RBuiltin "A value being applied like a function must have a function type."))
      f_ty (TArrow (arg_ty, ret_ty));
    infer_app env span ret_ty rest (idx + 1)
  | _, TError ->
    List.iter (fun a -> ignore (infer_expr env a)) args;
    TError
  | _, other ->
    Err.error env.errors ~span
      (Printf.sprintf
         "This is not a function — it has type `%s`.\n\
          I cannot apply it to arguments." (pp_ty other));
    List.iter (fun a -> ignore (infer_expr env a)) args;
    TError

(** Infer the result type of a match expression. *)
and infer_match env span scrut_ty branches =
  let result_ty = fresh_var env.level in
  List.iter (fun (br : Ast.branch) ->
      let bindings, pat_ty = infer_pattern env br.branch_pat in
      unify env ~span ~reason:(Some (RMatchArm span)) scrut_ty pat_ty;
      let env' = bind_vars bindings env in
      (match br.branch_guard with
       | Some g ->
         check_expr env' g t_bool
           ~reason:(Some (RBuiltin "Match guards must be Bool."))
       | None -> ());
      check_expr env' br.branch_body result_ty
        ~reason:(Some (RMatchArm span))
    ) branches;
  result_ty

(** Infer types of all expressions in a block, threading [ELet] bindings. *)
and infer_block env exprs =
  match exprs with
  | [] -> t_unit
  | [ e ] -> infer_expr env e
  | Ast.ELet (b, sp) :: rest ->
    let rhs_ty  = infer_expr env b.bind_expr in
    let bindings, pat_ty = infer_pattern env b.bind_pat in
    unify env ~span:sp ~reason:(Some (RLetBind sp)) rhs_ty pat_ty;
    (* Generalise the binding if it's a simple variable — let-polymorphism *)
    let gen_binding bnd = match bnd with
      | (name, Mono t) -> (name, generalize (env.level - 1) t)
      | other          -> other
    in
    let bindings' = match b.bind_pat with
      | Ast.PatVar _ -> List.map gen_binding bindings
      | _            -> bindings
    in
    let env' = bind_vars bindings' env in
    infer_block env' rest
  (* Local named recursive function: fn go(params) : ret_ty do body end *)
  | Ast.ELetFn (name, params, ret_ann, body, sp) :: rest ->
    (* Introduce a fresh type for the function, check recursively *)
    let fn_ty = fresh_var env.level in
    let env_with_self = bind_var name.txt (Mono fn_ty) env in
    let param_tys, env_inner = bind_lam_params env_with_self params in
    let body_ty = infer_block env_inner [body] in
    let ret_ty  = match ret_ann with
      | None -> body_ty
      | Some ann ->
        let tvars = ref [] in
        let expected = surface_ty env ~tvars ann in
        unify env ~span:sp ~reason:None body_ty expected;
        expected
    in
    let arrow_ty = List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys ret_ty in
    unify env ~span:sp ~reason:None fn_ty arrow_ty;
    let gen_ty = generalize (env.level - 1) arrow_ty in
    let env' = bind_var name.txt gen_ty env in
    infer_block env' rest
  | e :: rest ->
    ignore (infer_expr env e);
    infer_block env rest

(** Bind lambda parameters into the environment, returning (types, env). *)
and bind_lam_params env params =
  List.fold_right
    (fun p (tys, env) ->
       let t = fresh_var env.level in
       let env' = bind_lam_param env Ast.dummy_span p (Some t) in
       (t :: tys, env'))
    params ([], env)

and bind_lam_param env _sp (p : Ast.param) ann_ty =
  let t = match p.param_ty, ann_ty with
    | Some ann, _ ->
      let tvars = ref [] in
      surface_ty env ~tvars ann
    | None, Some t -> t
    | None, None   -> fresh_var env.level
  in
  match p.param_lin with
  | Ast.Unrestricted -> bind_var p.param_name.txt (Mono t) env
  | lin              -> bind_linear p.param_name.txt lin t env

(* =================================================================
   §15  Declaration checking
   ================================================================= *)

(** Check a function definition.

    Strategy:
    1. Enter a fresh generalization level.
    2. Add a monomorphic self-reference (allows recursion).
    3. Bind each parameter into the env.
    4. Infer/check the body.
    5. Leave level and generalize the function type.
    6. Return the scheme so the caller can update the env. *)
let check_fn env (def : Ast.fn_def) fn_span : scheme =
  let env'    = enter_level env in
  (* Self-reference for recursion — a fresh var that will get unified
     with the actual type as the body is checked. *)
  let self_ty = fresh_var env'.level in
  let env_rec = bind_var def.fn_name.txt (Mono self_ty) env' in

  let sch = match def.fn_clauses with
    | [] ->
      Err.error env.errors ~span:fn_span
        (Printf.sprintf "Function `%s` has no clauses." def.fn_name.txt);
      Mono TError

    | [clause] ->
      (* Bind parameters *)
      let param_tys, body_env =
        List.fold_right (fun fp (tys, env) ->
            match fp with
            | Ast.FPNamed p ->
              let t = match p.param_ty with
                | Some ann ->
                  let tvars = ref [] in
                  surface_ty env' ~tvars ann
                | None -> fresh_var env'.level
              in
              let env' = match p.param_lin with
                | Ast.Unrestricted -> bind_var p.param_name.txt (Mono t) env
                | lin              -> bind_linear p.param_name.txt lin t env
              in
              (t :: tys, env')
            | Ast.FPPat (Ast.PatVar name) ->
              (* Single variable pattern — trivially named; bind it directly *)
              let t = fresh_var env'.level in
              let env' = bind_var name.txt (Mono t) env in
              (t :: tys, env')
            | Ast.FPPat pat ->
              (* Complex pattern parameter: should have been desugared into a
                 match, but handle gracefully by binding inferred pattern vars *)
              let t = fresh_var env'.level in
              let pat_bindings, _ = infer_pattern env pat in
              let env' = bind_vars pat_bindings env in
              (t :: tys, env')
          ) clause.fc_params ([], env_rec)
      in

      (* Record each named parameter's type in the type map *)
      List.iter2 (fun fp pty ->
          match fp with
          | Ast.FPNamed p ->
            Hashtbl.replace env.type_map p.param_name.span (repr pty)
          | Ast.FPPat (Ast.PatVar name) ->
            Hashtbl.replace env.type_map name.span (repr pty)
          | Ast.FPPat _ -> ()
        ) clause.fc_params param_tys;

      (* Check the guard if present *)
      (match clause.fc_guard with
       | Some g ->
         check_expr body_env g t_bool
           ~reason:(Some (RBuiltin "Function guards must be Bool."))
       | None -> ());

      (* Check or infer the body *)
      let body_ty = match def.fn_ret_ty with
        | Some ann ->
          let tvars = ref [] in
          let expected = surface_ty env' ~tvars ann in
          check_expr body_env clause.fc_body expected
            ~reason:(Some (RFnReturn (def.fn_name.txt, fn_span)));
          expected
        | None ->
          infer_expr body_env clause.fc_body
      in

      (* Check linear params were all consumed *)
      let param_names = List.filter_map (function
          | Ast.FPNamed p -> Some p.param_name.txt
          | Ast.FPPat _ -> None) clause.fc_params in
      check_linear_all_consumed body_env ~scope_span:fn_span param_names;

      let fn_ty =
        List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys body_ty
      in
      (* Record the function's overall type at the function name's span *)
      Hashtbl.replace env.type_map def.fn_name.span (repr fn_ty);
      (* Unify self_ty so recursive calls get the correct type *)
      unify env' ~span:fn_span self_ty fn_ty;

      generalize env.level fn_ty

    | _ ->
      (* Multi-clause fn — desugar pass should have eliminated these *)
      Err.error env.errors ~span:fn_span
        (Printf.sprintf
           "Internal error: fn `%s` has multiple clauses after desugaring."
           def.fn_name.txt);
      Mono TError
  in

  ignore (leave_level env');
  sch

(** Discharge all pending Num/Ord constraints accumulated during inference.
    Called at each declaration boundary (DFn, DLet) to verify that constrained
    type variables were unified with a compatible concrete type. *)
let discharge_constraints env span =
  List.iter (fun c ->
      let ty, kind = match c with
        | CNum t -> (repr t, "Num")
        | COrd t -> (repr t, "Ord")
      in
      match ty with
      | TCon ("Int",   []) | TCon ("Float", []) -> ()   (* Num + Ord *)
      | TCon ("String",[]) ->
        (match c with
         | COrd _ -> ()   (* String is Ord *)
         | CNum _ ->
           Err.error env.errors ~span
             "String does not implement Num (only Int and Float do).")
      | TVar _ -> ()   (* Unresolved — will be polymorphic, constraint preserved *)
      | _ ->
        Err.error env.errors ~span
          (Printf.sprintf "`%s` does not implement %s." (pp_ty ty) kind)
    ) !(env.pending_constraints);
  env.pending_constraints := []

(** Structural equality after repr — works for concrete types; may give
    false-positive wrong-type hints when two distinct unresolved TVars
    happen not to be linked yet (acceptable in actor handler context). *)
let types_equal a b = repr a = repr b

(** Build hint strings explaining why an actor handler body has the wrong type.
    state_ty and inferred_ty should both be repr-ed before calling. *)
let actor_handler_hints state_ty inferred_ty =
  match inferred_ty with
  | TRecord inferred_fields ->
    (match state_ty with
     | TRecord [] ->
       ["the state has no fields — return an empty record {}"]
     | TRecord state_fields ->
       let state_names    = List.map fst state_fields in
       let inferred_names = List.map fst inferred_fields in
       let extra   = List.filter (fun n -> not (List.mem n state_names)) inferred_names in
       let missing = List.filter (fun n -> not (List.mem n inferred_names)) state_names in
       let wrong_type = List.filter_map (fun (fname, st) ->
           match List.assoc_opt fname inferred_fields with
           | Some it when not (types_equal st it) ->
             Some (Printf.sprintf
               "field '%s' has type %s but state declares it as %s"
               fname (pp_ty (repr it)) (pp_ty (repr st)))
           | _ -> None) state_fields in
       List.map (fun n -> Printf.sprintf
         "field '%s' is not part of the actor state \
          — remove it, or add it to the state declaration" n) extra
       @ List.map (fun n -> Printf.sprintf
         "field '%s' is missing from the returned record" n) missing
       @ wrong_type
     | _ -> [])
  | t ->
    [Printf.sprintf "handler must return a record matching the state, not %s" (pp_ty t)]

(** [check_module_needs env mod_name decls] validates capability declarations for a module:
    1. Every Cap(X) in any function signature must be covered by a [needs] declaration.
    2. Every [needs X] must be used by at least one function.
    3. Hint when Cap(IO) (root) is used — narrower caps may be more appropriate. *)
let check_module_needs (env : env) (mod_name : Ast.name) (decls : Ast.decl list) =
  let declared_needs = List.concat_map (function
    | Ast.DNeeds (caps, _) -> List.map cap_path_of_names caps
    | _ -> []
  ) decls in
  let used_caps : (string * Ast.span) list = List.concat_map (function
    | Ast.DFn (def, sp) ->
      let param_tys = List.filter_map (fun p ->
        match p with
        | Ast.FPNamed { param_ty = Some t; _ } -> Some t
        | _ -> None
      ) (List.concat_map (fun c -> c.Ast.fc_params) def.fn_clauses) in
      let ret_tys = Option.to_list def.fn_ret_ty in
      List.concat_map (fun t ->
        List.map (fun cap -> (cap, sp)) (cap_paths_in_surface_ty t)
      ) (param_tys @ ret_tys)
    | _ -> []
  ) decls in
  (* Check 1: every Cap(X) must be covered by a declared need *)
  List.iter (fun (cap_path, sp) ->
    let covered = List.exists (fun need -> cap_subsumes need cap_path) declared_needs in
    if not covered then
      Err.error env.errors ~span:sp
        (Printf.sprintf
           "capability `Cap(%s)` used in module `%s` but `%s` is not declared in `needs`.\n\
            help: add `needs %s` to the module body."
           cap_path mod_name.txt cap_path cap_path)
  ) used_caps;
  (* Check 2: every needs declaration must be used *)
  List.iter (fun need ->
    let need_sp =
      let rec find_span = function
        | [] -> mod_name.span
        | Ast.DNeeds (caps, s) :: _
          when List.exists (fun names -> cap_path_of_names names = need) caps -> s
        | _ :: rest -> find_span rest
      in
      find_span decls
    in
    let used = List.exists (fun (cap_path, _) -> cap_subsumes need cap_path) used_caps in
    if not used then
      Err.warning env.errors ~span:need_sp
        (Printf.sprintf
           "module `%s` declares `needs %s` but no function requires `Cap(%s)` or a sub-capability.\n\
            help: remove the unused capability declaration."
           mod_name.txt need need)
  ) declared_needs;
  (* Check 3 (hint): Cap(IO) root — suggest narrowing *)
  List.iter (fun (cap_path, sp) ->
    if cap_path = "IO" then
      Err.hint env.errors ~span:sp
        "this function takes `Cap(IO)` (the root capability); \
         consider narrowing to e.g. `Cap(IO.FileRead)` or `Cap(IO.Console)` for least-privilege."
  ) used_caps

let rec check_decl env (d : Ast.decl) : env =
  match d with
  | Ast.DFn (def, sp) ->
    let sch = check_fn env def sp in
    discharge_constraints env sp;
    bind_var def.fn_name.txt sch env

  | Ast.DLet (b, sp) ->
    let env' = enter_level env in
    let rhs_ty = infer_expr env' b.bind_expr in
    Hashtbl.replace env.type_map sp (repr rhs_ty);
    let bindings, pat_ty = infer_pattern env' b.bind_pat in
    unify env' ~span:sp ~reason:(Some (RLetBind sp)) rhs_ty pat_ty;
    discharge_constraints env sp;
    ignore (leave_level env');
    (* Generalise simple variable bindings at module level *)
    let gen_bnd bnd = match bnd with
      | (name, Mono t) -> (name, generalize env.level t)
      | other          -> other
    in
    let bindings' = match b.bind_pat with
      | Ast.PatVar _ -> List.map gen_bnd bindings
      | _            -> bindings
    in
    bind_vars bindings' env

  | Ast.DType (name, params, typedef, _sp) ->
    let env1 = { env with types = (name.txt, List.length params) :: env.types } in
    (match typedef with
     | Ast.TDVariant variants ->
       let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
       List.fold_left (fun e (v : Ast.variant) ->
           let ci = { ci_type    = name.txt
                    ; ci_params  = param_names
                    ; ci_arg_tys = v.var_args } in
           { e with ctors = (v.var_name.txt, ci) :: e.ctors }
         ) env1 variants
     | Ast.TDRecord fields ->
       let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
       let field_pairs = List.map (fun (f : Ast.field) -> (f.fld_name.txt, f.fld_ty)) fields in
       { env1 with records = (name.txt, (param_names, field_pairs)) :: env1.records }
     | Ast.TDAlias _ -> env1)

  | Ast.DActor (name, actor, _sp) ->
    (* Build the state record type from field declarations *)
    let state_ty =
      let tvars = ref [] in
      let flds = List.map (fun (f : Ast.field) ->
          (f.fld_name.txt, surface_ty env ~tvars f.fld_ty)) actor.actor_state in
      TRecord (List.sort (fun (a,_)(b,_) -> String.compare a b) flds)
    in
    (* Register actor name as a zero-arg constructor (so spawn(ActorName) typechecks)
       and message constructors so ECon lookups succeed *)
    let env_with_actor_ctor = { env with ctors =
      (name.txt, { ci_type = name.txt; ci_params = []; ci_arg_tys = [] })
      :: env.ctors } in
    let env_with_ctors = List.fold_left (fun acc_env (h : Ast.actor_handler) ->
        let arg_tys = List.filter_map (fun (p : Ast.param) -> p.param_ty) h.ah_params in
        let ci = { ci_type = name.txt ^ "_Msg"; ci_params = [];
                   ci_arg_tys = arg_tys } in
        { acc_env with ctors = (h.ah_msg.txt, ci) :: acc_env.ctors }
      ) env_with_actor_ctor actor.actor_handlers in
    (* Check init expression — must return the state record type *)
    check_expr env_with_ctors actor.actor_init state_ty
      ~reason:(Some (RBuiltin "actor init must return the initial state record"));
    (* Check handlers with state and message params in scope *)
    List.iter (fun (h : Ast.actor_handler) ->
        let handler_env = bind_var "state" (Mono state_ty) env_with_ctors in
        let handler_env =
          List.fold_left (fun e p ->
              bind_var p.Ast.param_name.txt
                (Mono (match p.param_ty with
                   | Some ann -> let tvars = ref [] in surface_ty env ~tvars ann
                   | None     -> fresh_var env.level))
                e
            ) handler_env h.ah_params
        in
        (* Handler body must return the state record type — emit rich diagnostic *)
        let inferred = infer_expr handler_env h.ah_body in
        let shadow_env = { handler_env with errors = Err.create () } in
        (* Note: pending_constraints and type_map are shared (shallow copy) —
           intentional; only error reporting is isolated. *)
        unify shadow_env ~span:h.ah_msg.span ~reason:None
          (repr inferred) (repr state_ty);
        if Err.has_errors shadow_env.errors then
          Err.report handler_env.errors
            { severity = Error;
              span = h.ah_msg.span;
              message = Printf.sprintf
                "handler '%s' in actor '%s' must return the state type\
                 \n  expected: %s\
                 \n  got:      %s"
                h.ah_msg.txt name.txt
                (pp_ty (repr state_ty)) (pp_ty (repr inferred));
              labels = [];
              notes = actor_handler_hints (repr state_ty) (repr inferred) }
      ) actor.actor_handlers;
    bind_var name.txt (Mono (TCon ("Pid", [state_ty]))) env_with_ctors

  | Ast.DMod (name, _vis, decls, _sp) ->
    (* Pass 1: pre-bind all inner DFn names as mono forward refs so that
       functions within the module can reference each other regardless of
       declaration order (same logic as check_module's pass 1).
       Unlike check_module's pass 1, we always pre-bind here — outer-scope
       names with the same identifier should not block intra-module refs. *)
    let pre_env = List.fold_left (fun e d ->
        match d with
        | Ast.DFn (def, _) ->
          bind_var def.fn_name.txt (Mono (fresh_var 0)) e
        | _ -> e
      ) env decls in
    let inner_env = List.fold_left check_decl pre_env decls in
    (* Collect the names that are explicitly public within this module.
       DFn respects fn_vis; DLet/DType/DActor have no visibility field and are
       treated as public by default (visibility annotations for them are future work). *)
    let pub_set =
      List.filter_map (function
        | Ast.DFn (def, _) when def.fn_vis = Ast.Public -> Some def.fn_name.txt
        | Ast.DFn _ -> None
        | Ast.DLet (b, _) ->
          (match b.bind_pat with Ast.PatVar n -> Some n.txt | _ -> None)
        | Ast.DType (n, _, _, _) -> Some n.txt
        | Ast.DActor (n, _, _) -> Some n.txt
        | Ast.DMod (n, Ast.Public, _, _) -> Some n.txt
        | Ast.DMod _ -> None
        | _ -> None
      ) decls
    in
    (* Check conformance against any matching sig declaration *)
    (match List.assoc_opt name.txt env.sigs with
     | None -> ()
     | Some sdef ->
       (* Verify all sig_fns are present in the module *)
       List.iter (fun ((fname : Ast.name), _sig_ty) ->
           if not (List.mem_assoc fname.txt inner_env.vars) then
             Err.error env.errors ~span:name.span
               (Printf.sprintf
                  "Module `%s` does not implement `%s` required by `sig %s`."
                  name.txt fname.txt name.txt)
         ) sdef.sig_fns;
       (* Verify all sig_types are declared in the module *)
       List.iter (fun ((tname : Ast.name), _params) ->
           if not (List.mem_assoc tname.txt inner_env.types) then
             Err.error env.errors ~span:name.span
               (Printf.sprintf
                  "Module `%s` does not declare type `%s` required by `sig %s`."
                  name.txt tname.txt name.txt)
         ) sdef.sig_types
    );
    (* Validate capability declarations for this module *)
    check_module_needs env name decls;
    (* Expose only public names as "ModName.name" in the outer env *)
    let new_names = List.filter_map (fun (k, sch) ->
        if List.mem k pub_set
        then Some (name.txt ^ "." ^ k, sch)
        else None
      ) inner_env.vars in
    (* Also export type names and constructors from public DMod into outer scope.
       Types defined in a module (e.g. IOList, Option) are referred to by their
       bare name throughout user code, not prefixed. *)
    let new_types = List.filter (fun (k, _) -> List.mem k pub_set) inner_env.types in
    let new_ctors = List.filter (fun (k, _) -> List.mem k pub_set) inner_env.ctors in
    let env' = bind_vars new_names env in
    { env' with types = new_types @ env'.types; ctors = new_ctors @ env'.ctors }

  | Ast.DProtocol (name, pdef, sp) ->
    (* Register the protocol and validate basic well-formedness. *)
    if List.mem_assoc name.txt env.protocols then
      Err.error env.errors ~span:sp
        (Printf.sprintf "duplicate protocol definition: %s" name.txt);
    if pdef.proto_steps = [] then
      Err.warning env.errors ~span:sp
        (Printf.sprintf "protocol %s has no steps" name.txt);
    { env with protocols = (name.txt, pdef) :: env.protocols }

  | Ast.DSig (name, sdef, _sp) ->
    (* Store the signature so DMod can check conformance later. *)
    { env with sigs = (name.txt, sdef) :: env.sigs }

  | Ast.DInterface (idef, _sp) ->
    (* Register the interface definition for impl validation, and register
       each method as a polymorphic function binding in scope. *)
    let env' = { env with interfaces = (idef.iface_name.txt, idef) :: env.interfaces } in
    List.fold_left (fun env (m : Ast.method_decl) ->
        let tvars = ref [(idef.iface_param.txt, fresh_var env.level)] in
        let ty = surface_ty env ~tvars m.md_ty in
        bind_var m.md_name.txt (generalize env.level ty) env
      ) env' idef.iface_methods

  | Ast.DImpl (idef, _sp) ->
    (* Validate each method against the interface declaration. *)
    (match List.assoc_opt idef.impl_iface.txt env.interfaces with
     | None ->
       Err.error env.errors ~span:idef.impl_iface.span
         (Printf.sprintf "Unknown interface `%s` — is it declared above this impl?"
            idef.impl_iface.txt)
     | Some interface ->
       (* Instantiate the interface's type parameter with the concrete impl type *)
       let inst_ty =
         let tvars = ref [] in surface_ty env ~tvars idef.impl_ty
       in
       List.iter (fun ((mname : Ast.name), (def : Ast.fn_def)) ->
           match List.find_opt
                   (fun (m : Ast.method_decl) -> m.md_name.txt = mname.txt)
                   interface.iface_methods with
           | None ->
             Err.error env.errors ~span:mname.span
               (Printf.sprintf "Interface `%s` does not declare a method `%s`."
                  idef.impl_iface.txt mname.txt)
           | Some iface_method ->
             (* Expected type: substitute interface param → concrete type *)
             let expected_ty =
               surface_ty env
                 ~tvars:(ref [(interface.iface_param.txt, inst_ty)])
                 iface_method.md_ty
             in
             (* Infer the method body's actual type *)
             let actual_sch = check_fn env def _sp in
             let actual_ty = instantiate env.level env actual_sch in
             unify env ~span:mname.span actual_ty expected_ty
               ~reason:(Some (RBuiltin
                  (Printf.sprintf "`%s` in `impl %s` must match the interface signature"
                     mname.txt idef.impl_iface.txt)))
         ) idef.impl_methods);
    env

  | Ast.DExtern (edef, _sp) ->
    (* Register each foreign function as a monomorphic binding. *)
    List.fold_left (fun env (ef : Ast.extern_fn) ->
        let tvars = ref [] in
        let param_tys = List.map (fun (_, t) -> surface_ty env ~tvars t) ef.ef_params in
        let ret_ty = surface_ty env ~tvars ef.ef_ret_ty in
        let ty = List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys ret_ty in
        bind_var ef.ef_name.txt (Mono ty) env
      ) env edef.ext_fns

  | Ast.DUse (ud, _sp) ->
    let prefix = String.concat "." (List.map (fun n -> n.Ast.txt) ud.use_path) ^ "." in
    (match ud.use_sel with
     | Ast.UseSingle ->
       (* Import the module path as an accessible prefix — no new bindings needed *)
       env
     | Ast.UseAll ->
       (* Find all vars with "Prefix.name" and rebind them as plain "name" *)
       let matching = List.filter_map (fun (k, sch) ->
           let plen = String.length prefix in
           if String.length k > plen
              && String.sub k 0 plen = prefix
           then Some (String.sub k plen (String.length k - plen), sch)
           else None) env.vars in
       bind_vars matching env
     | Ast.UseNames names ->
       List.fold_left (fun env n ->
           match List.assoc_opt (prefix ^ n.Ast.txt) env.vars with
           | Some sch -> bind_var n.Ast.txt sch env
           | None ->
             Err.error env.errors ~span:n.Ast.span
               (Printf.sprintf "Module `%s` does not export `%s`."
                  (String.concat "." (List.map (fun n -> n.Ast.txt) ud.use_path))
                  n.Ast.txt);
             env) env names)

  | Ast.DNeeds (caps, _sp) ->
    (* Record declared capability paths in env for DMod validation.
       Each path is a list of names e.g. ["IO"; "Network"] → "IO.Network" *)
    let paths = List.map (fun names ->
        String.concat "." (List.map (fun (n : Ast.name) -> n.txt) names)
      ) caps in
    { env with mod_needs = paths @ env.mod_needs }

(* =================================================================
   §16  Module entry point
   ================================================================= *)

(** Type-check a whole module.

    Pass 1: collect all top-level function names into the environment
            as monomorphic placeholders.  This allows forward references
            and simple mutual recursion (the placeholder is unified with
            the actual type as the body is inferred).

    Pass 2: check declarations in order, updating the environment.

    Returns the [Err.ctx] containing all diagnostics. *)
let check_module ?(errors = Err.create ()) (m : Ast.module_) : Err.ctx * (Ast.span, ty) Hashtbl.t =
  let type_map = Hashtbl.create 256 in
  (* Pass 1: forward-reference placeholders for functions and type/ctor names *)
  let pre_env = List.fold_left (fun env d ->
      match d with
      | Ast.DFn (def, _) ->
        (* Don't shadow existing bindings (e.g., builtins) with mono forward refs *)
        if List.mem_assoc def.fn_name.txt env.vars then env
        else bind_var def.fn_name.txt (Mono (fresh_var 0)) env
      | Ast.DType (name, params, typedef, _) ->
        let env1 = { env with types = (name.txt, List.length params) :: env.types } in
        (match typedef with
         | Ast.TDVariant variants ->
           let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
           List.fold_left (fun e (v : Ast.variant) ->
               let ci = { ci_type    = name.txt
                        ; ci_params  = param_names
                        ; ci_arg_tys = v.var_args } in
               { e with ctors = (v.var_name.txt, ci) :: e.ctors }
             ) env1 variants
         | Ast.TDRecord fields ->
           let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
           let field_pairs = List.map (fun (f : Ast.field) -> (f.fld_name.txt, f.fld_ty)) fields in
           { env1 with records = (name.txt, (param_names, field_pairs)) :: env1.records }
         | _ -> env1)
      | Ast.DActor (name, actor, _) ->
        (* Register actor name as a zero-arg constructor and message ctors *)
        let env1 = { env with ctors =
          (name.txt, { ci_type = name.txt; ci_params = []; ci_arg_tys = [] })
          :: env.ctors } in
        List.fold_left (fun acc_env (h : Ast.actor_handler) ->
            let arg_tys = List.filter_map (fun (p : Ast.param) -> p.param_ty) h.ah_params in
            let ci = { ci_type = name.txt ^ "_Msg"; ci_params = [];
                       ci_arg_tys = arg_tys } in
            { acc_env with ctors = (h.ah_msg.txt, ci) :: acc_env.ctors }
          ) env1 actor.actor_handlers
      | Ast.DSig (name, sdef, _) ->
        { env with sigs = (name.txt, sdef) :: env.sigs }
      | Ast.DInterface (idef, _) ->
        { env with interfaces = (idef.iface_name.txt, idef) :: env.interfaces }
      | _ -> env
    ) (base_env errors type_map) m.Ast.mod_decls
  in
  (* Pass 2: full checking *)
  let final_env = List.fold_left check_decl pre_env m.Ast.mod_decls in
  (* Validate capability declarations for the top-level module *)
  check_module_needs final_env m.Ast.mod_name m.Ast.mod_decls;
  (errors, type_map)
