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
module StringSet = Set.Make(String)

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
  | TChan   of session_ty ref            (** Linear session-typed channel endpoint *)
  | TError                               (** Error sentinel *)

(** Local session type — per-endpoint view of a binary protocol.
    Computed by projecting the global [Ast.protocol_def] onto one role. *)
and session_ty =
  | SSend   of ty * session_ty           (** Send a value of type T, then follow S (binary) *)
  | SRecv   of ty * session_ty           (** Receive a value of type T, then follow S (binary) *)
  | SChoose of (string * session_ty) list (** Actively select a branch label *)
  | SOffer  of (string * session_ty) list (** Passively wait for the other side to pick *)
  | SEnd                                 (** Session complete — channel must be closed *)
  | SRec    of string * session_ty       (** Recursive binding: Rec(X, S) *)
  | SVar    of string                    (** Back-reference to a recursive binder *)
  | SError                               (** Error sentinel *)
  (* MPST: role-annotated send/recv for multi-party protocols (N>2 participants). *)
  | SMSend  of string * ty * session_ty  (** Send to role: MSend(target_role, T, S) *)
  | SMRecv  of string * ty * session_ty  (** Receive from role: MRecv(source_role, T, S) *)

and tvar =
  | Unbound of int * int   (** id, generalization level *)
  | Link    of ty          (** Solved: points to this type *)

(** Lightweight type-class constraints.
    [CNum t] asserts t must be Int or Float (arithmetic).
    [COrd t] asserts t must be Int, Float, or String (ordered).
    [CInterface (name, t)] asserts t must implement interface [name]. *)
type constraint_ =
  | CNum of ty
  | COrd of ty
  | CInterface of string * ty

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
  | TChan  _            -> false  (* session_ty is not polymorphic *)
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
    | TChan r -> "Chan(" ^ pp_session_ty !r ^ ")"
  in s

(** Pretty-print a type with line-wrapping.
    If the flat representation fits within [width] chars, return it unchanged.
    Otherwise indent arguments across multiple lines for readability. *)
and pp_ty_pretty ?(indent = 0) ?(width = 60) t =
  let flat = pp_ty t in
  if String.length flat <= width - indent then flat
  else
    match repr t with
    | TCon (name, (_::_ as args)) ->
      let pad = String.make (indent + 2) ' ' in
      let close_pad = String.make indent ' ' in
      let formatted = List.map (pp_ty_pretty ~indent:(indent + 2) ~width) args in
      name ^ "(\n" ^ pad ^ String.concat (",\n" ^ pad) formatted ^ "\n" ^ close_pad ^ ")"
    | TRecord ((_::_) as flds) ->
      let pad = String.make (indent + 2) ' ' in
      let close_pad = String.make indent ' ' in
      let fs = List.map (fun (n, t) ->
        n ^ " : " ^ pp_ty_pretty ~indent:(indent + String.length n + 3) ~width t) flds in
      "{\n" ^ pad ^ String.concat (",\n" ^ pad) fs ^ "\n" ^ close_pad ^ "}"
    | TTuple ((_::_) as ts) ->
      let pad = String.make (indent + 2) ' ' in
      let close_pad = String.make indent ' ' in
      let formatted = List.map (pp_ty_pretty ~indent:(indent + 2) ~width) ts in
      "(\n" ^ pad ^ String.concat (",\n" ^ pad) formatted ^ "\n" ^ close_pad ^ ")"
    | _ -> flat

(** Find which argument of a type constructor differs between two types
    of the same constructor. Returns (1-based index, expected, found) for
    the first differing argument, or None if no structural difference found. *)
and find_arg_mismatch name args1 args2 =
  let rec aux i = function
    | [], [] -> None
    | t1 :: rest1, t2 :: rest2 ->
      if pp_ty t1 = pp_ty t2 then aux (i + 1) (rest1, rest2)
      else Some (i, name, t1, t2)
    | _ -> None
  in
  aux 1 (args1, args2)

and pp_session_ty = function
  | SSend (t, s)        -> Printf.sprintf "Send(%s, %s)" (pp_ty t) (pp_session_ty s)
  | SRecv (t, s)        -> Printf.sprintf "Recv(%s, %s)" (pp_ty t) (pp_session_ty s)
  | SChoose bs          ->
    let arms = List.map (fun (l, s) -> l ^ ": " ^ pp_session_ty s) bs in
    "Choose{" ^ String.concat ", " arms ^ "}"
  | SOffer bs           ->
    let arms = List.map (fun (l, s) -> l ^ ": " ^ pp_session_ty s) bs in
    "Offer{" ^ String.concat ", " arms ^ "}"
  | SEnd                -> "End"
  | SRec (x, s)         -> Printf.sprintf "Rec(%s, %s)" x (pp_session_ty s)
  | SVar x              -> x
  | SError              -> "<session_error>"
  | SMSend (role, t, s) -> Printf.sprintf "MSend(%s, %s, %s)" role (pp_ty t) (pp_session_ty s)
  | SMRecv (role, t, s) -> Printf.sprintf "MRecv(%s, %s, %s)" role (pp_ty t) (pp_session_ty s)

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
  ci_type    : string;           (** Parent type name, e.g. "Result" *)
  ci_params  : string list;      (** Type param names in declaration order *)
  ci_arg_tys : Ast.ty list;      (** Surface arg types of this constructor *)
  ci_vis     : Ast.visibility;   (** Constructor visibility (Public/Private) *)
}

(** One entry in the import tracker — records an imported name or alias and
    whether it was referenced at least once during typechecking. *)
type import_entry = {
  ie_span    : Ast.span;
  ie_desc    : string;              (** human-readable warning message *)
  ie_matches : string -> bool;      (** does looking up [name] count as "using" this? *)
  ie_used    : bool ref;
}

(** Computed session-type information for a declared [protocol].
    Stored in [env.protocols] after [DProtocol] is checked. *)
type proto_info = {
  pi_def         : Ast.protocol_def;
  pi_projections : (string * session_ty) list;  (** role → local session type *)
  pi_span        : Ast.span;
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
  module_caps : (string * string list) list;
  (** Capabilities required by checked sub-modules: module name → list of cap paths.
      Populated when a [DMod] is fully checked; used for transitive enforcement. *)
  protocols  : (string * proto_info) list; (** Registered session-type protocols *)
  impls      : (string * ty) list; (** Registered interface implementations: (iface_name, impl_ty) *)
  import_tracker : import_entry list ref;
  (** Accumulated import/alias entries for unused-import warning detection.
      Shared (mutable) across all env copies derived from the same root. *)
}

let make_env errors type_map = {
  vars = []; types = []; ctors = []; records = []; level = 0; lin = [];
  errors; pending_constraints = ref []; type_map;
  interfaces = []; sigs = [];
  mod_needs = []; module_caps = []; protocols = []; impls = [];
  import_tracker = ref [];
}

let enter_level env = { env with level = env.level + 1 }
let leave_level env = { env with level = env.level - 1 }

let lookup_var  name env = List.assoc_opt name env.vars
let lookup_type name env = List.assoc_opt name env.types
let lookup_ctor name env = List.assoc_opt name env.ctors

(** All parent types of ctors in [env] that share [name] (multiple types may
    define the same variant). Returns list of type names (deduplicated). *)
let all_ctors_named (name : string) (env : env) : string list =
  let seen = Hashtbl.create 4 in
  List.filter_map (fun (k, ci) ->
    if k = name && not (Hashtbl.mem seen ci.ci_type)
    then begin Hashtbl.add seen ci.ci_type (); Some ci.ci_type end
    else None
  ) env.ctors

(** Suggest constructors close to [name]: case-insensitive match or first-2-char
    prefix match with length difference ≤ 2. Returns [(ctor_name, type_name)]. *)
let suggest_ctors (name : string) (env : env) : (string * string) list =
  let name_lo = String.lowercase_ascii name in
  let seen = Hashtbl.create 8 in
  List.filter_map (fun (k, ci) ->
    let key = k ^ "/" ^ ci.ci_type in
    if Hashtbl.mem seen key then None
    else begin
      let k_lo = String.lowercase_ascii k in
      let close =
        k_lo = name_lo ||
        (String.length name_lo >= 2 && String.length k_lo >= 2 &&
         String.sub k_lo 0 2 = String.sub name_lo 0 2 &&
         abs (String.length k - String.length name) <= 2)
      in
      if close then begin Hashtbl.add seen key (); Some (k, ci.ci_type) end
      else None
    end
  ) env.ctors

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
    | TChan  _           -> ()   (* session_ty has no polymorphic variables *)
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
      | TChan  _           -> t   (* session_ty has no polymorphic variables *)
      | TNat _ | TError    -> t
    in
    let inst_cs = List.map (function
        | CNum t -> CNum (inst t)
        | COrd t -> COrd (inst t)
        | CInterface (n, t) -> CInterface (n, inst t)) cs
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

(* =================================================================
   §9b  Standard interfaces — Eq, Ord, Show, Hash
   These are pre-registered in every module so that builtin types
   (Int, Float, String, Bool) already satisfy the constraints and
   user code can write `impl Eq(MyType)` without re-declaring the
   interface.
   ================================================================= *)

(** Extract the unification-variable id from a fresh TVar. *)
let get_tvar_id = function
  | TVar r -> (match !r with Unbound (id, _) -> id | _ -> 0)
  | _ -> 0

(** Build an [Ast.interface_def] for a builtin interface with a single
    type parameter named "a". [methods] is a list of (method_name, surface_ty). *)
let mk_builtin_iface name methods =
  let mk_n txt = { Ast.txt; span = Ast.dummy_span } in
  let mk_method (mname, mty) =
    { Ast.md_name = mk_n mname; md_ty = mty; md_default = None }
  in
  { Ast.iface_name        = mk_n name;
    iface_param           = mk_n "a";
    iface_superclasses    = [];
    iface_assoc_types     = [];
    iface_methods         = List.map mk_method methods }

let _mk_n txt = { Ast.txt; span = Ast.dummy_span }

(** Pre-declared standard interfaces.  These are injected into every
    module's initial environment so users can write impls for them. *)
let builtin_interfaces : (string * Ast.interface_def) list =
  let av       = Ast.TyVar  { txt = "a";      span = Ast.dummy_span } in
  let bool_t   = Ast.TyCon  ({ txt = "Bool";   span = Ast.dummy_span }, []) in
  let int_t    = Ast.TyCon  ({ txt = "Int";    span = Ast.dummy_span }, []) in
  let string_t = Ast.TyCon  ({ txt = "String"; span = Ast.dummy_span }, []) in
  [
    ("Eq",   mk_builtin_iface "Eq" [
       ("eq",      Ast.TyArrow (av, Ast.TyArrow (av, bool_t)));
     ]);
    ("Ord",  mk_builtin_iface "Ord" [
       ("compare", Ast.TyArrow (av, Ast.TyArrow (av, int_t)));
     ]);
    ("Show", mk_builtin_iface "Show" [
       ("show",    Ast.TyArrow (av, string_t));
     ]);
    ("Hash", mk_builtin_iface "Hash" [
       ("hash",    Ast.TyArrow (av, int_t));
     ]);
  ]

(** Concrete type implementations for the standard interfaces.
    These ensure that Int/Float/String/Bool satisfy Eq, Ord, Show, Hash
    out of the box. *)
let builtin_impls : (string * ty) list =
  [ (* Eq *)
    ("Eq",   t_int);   ("Eq",   t_float); ("Eq",   t_string);
    ("Eq",   t_bool);  ("Eq",   t_unit);
    (* Ord *)
    ("Ord",  t_int);   ("Ord",  t_float); ("Ord",  t_string);
    (* Show *)
    ("Show", t_int);   ("Show", t_float); ("Show", t_string);
    ("Show", t_bool);  ("Show", t_unit);
    (* Hash *)
    ("Hash", t_int);   ("Hash", t_float); ("Hash", t_string);
    ("Hash", t_bool);
  ]

(** Build a scheme [∀a. CInterface(iface, a) => mk_ty(a)] for a builtin
    interface method binding. *)
let mk_iface_method_scheme iface_name mk_ty =
  let a = fresh_var 0 in
  Poly ([get_tvar_id a], [CInterface (iface_name, a)], mk_ty a)

(** Method bindings for the standard interfaces.  These are added to
    every module's initial [vars] so that [eq], [compare], [show],
    and [hash] resolve as polymorphic functions at call sites.
    Both unqualified (eq) and qualified (Eq.eq) forms are registered
    so that [Eq.eq(x, y)] resolves via the EField module-path lookup. *)
let builtin_interface_bindings : (string * scheme) list =
  [ ("eq",      mk_iface_method_scheme "Eq"   (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("compare", mk_iface_method_scheme "Ord"  (fun a -> TArrow (a, TArrow (a, t_int))));
    ("show",    mk_iface_method_scheme "Show" (fun a -> TArrow (a, t_string)));
    ("hash",    mk_iface_method_scheme "Hash" (fun a -> TArrow (a, t_int)));
    (* Qualified forms: Eq.eq, Ord.compare, Show.show, Hash.hash *)
    ("Eq.eq",      mk_iface_method_scheme "Eq"   (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("Ord.compare",mk_iface_method_scheme "Ord"  (fun a -> TArrow (a, TArrow (a, t_int))));
    ("Show.show",  mk_iface_method_scheme "Show" (fun a -> TArrow (a, t_string)));
    ("Hash.hash",  mk_iface_method_scheme "Hash" (fun a -> TArrow (a, t_int)));
  ]

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
  (* ∀a:Ord. f(a) — a must be Int, Float, or String (legacy COrd path) *)
  let _poly1_ord f =
    let a = fresh_var 0 in
    Poly ([get_id a], [COrd a], f a)
  in
  (* ∀a:Iface. f(a) — a must implement the named interface *)
  let poly1_iface iname f =
    let a = fresh_var 0 in
    Poly ([get_id a], [CInterface (iname, a)], f a)
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
    (* Ordering comparisons: Ord interface-constrained (Int, Float, String) *)
    ("<",  poly1_iface "Ord" (fun a -> TArrow (a, TArrow (a, t_bool))));
    (">",  poly1_iface "Ord" (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("<=", poly1_iface "Ord" (fun a -> TArrow (a, TArrow (a, t_bool))));
    (">=", poly1_iface "Ord" (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("&&", Mono (TArrow (t_bool,   TArrow (t_bool,   t_bool))));
    ("||", Mono (TArrow (t_bool,   TArrow (t_bool,   t_bool))));
    (* Equality: Eq interface-constrained *)
    ("==", poly1_iface "Eq" (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("!=", poly1_iface "Eq" (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("++",             Mono (TArrow (t_string, TArrow (t_string, t_string))));
    ("print",          Mono (TArrow (t_string, t_unit)));
    ("println",        Mono (TArrow (t_string, t_unit)));
    ("print_int",      Mono (TArrow (t_int,    t_unit)));
    ("print_float",    Mono (TArrow (t_float,  t_unit)));
    (* Tap bus: ∀a. a -> a  (sends value to tap bus, returns it unchanged) *)
    ("tap",            poly1 (fun a -> TArrow (a, a)));
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
    (* Int bitwise primitives *)
    ("int_and",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_or",          Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_xor",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_not",         Mono (TArrow (t_int,   t_int)));
    ("int_shl",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_shr",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_popcount",    Mono (TArrow (t_int,   t_int)));
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
    ("unix_time",       Mono (TArrow (t_unit,  t_float)));
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
    ("string_chars",        Mono (TArrow (t_string, t_list t_string)));
    ("string_from_chars",   Mono (TArrow (t_list t_string, t_string)));
    ("string_repeat",       Mono (TArrow (t_string, TArrow (t_int, t_string))));
    ("string_reverse",      Mono (TArrow (t_string, t_string)));
    ("string_pad_left",     Mono (TArrow (t_string, TArrow (t_int, TArrow (t_string, t_string)))));
    ("string_pad_right",    Mono (TArrow (t_string, TArrow (t_int, TArrow (t_string, t_string)))));
    ("string_byte_length",  Mono (TArrow (t_string, t_int)));
    ("string_split_first",   Mono (TArrow (t_string, TArrow (t_string, t_option (TTuple [t_string; t_string])))));
    ("string_grapheme_count",Mono (TArrow (t_string, t_int)));
    (* Char primitives — in March, a "char" is a single-char String *)
    ("char_is_alpha",        Mono (TArrow (t_string, t_bool)));
    ("char_is_digit",        Mono (TArrow (t_string, t_bool)));
    ("char_is_alphanumeric", Mono (TArrow (t_string, t_bool)));
    ("char_is_whitespace",   Mono (TArrow (t_string, t_bool)));
    ("char_is_uppercase",    Mono (TArrow (t_string, t_bool)));
    ("char_is_lowercase",    Mono (TArrow (t_string, t_bool)));
    ("char_to_uppercase",    Mono (TArrow (t_string, t_string)));
    ("char_to_lowercase",    Mono (TArrow (t_string, t_string)));
    ("char_to_int",          Mono (TArrow (t_string, t_int)));
    ("char_from_int",        Mono (TArrow (t_int, t_string)));
    (* Comparison primitives *)
    ("compare_int",    Mono (TArrow (t_int,    TArrow (t_int,    t_int))));
    ("compare_float",  Mono (TArrow (t_float,  TArrow (t_float,  t_int))));
    ("compare_string", Mono (TArrow (t_string, TArrow (t_string, t_int))));
    (* Diverging primitives *)
    ("panic",       poly1 (fun a -> TArrow (t_string, a)));
    ("panic_",      poly1 (fun a -> TArrow (t_string, a)));
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
    (* Phase 6b: Register a linear value with an actor; Drop impl resolved at runtime *)
    ("own", poly2 (fun a b -> TArrow (TCon ("Pid", [a]), TArrow (b, t_unit))));
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
    (* CSV builtins — csv_next_row returns CsvRow (declared in csv.march) *)
    ("csv_open",     poly1 (fun e -> TArrow (t_string, TArrow (t_string, TArrow (t_atom, t_result t_int e)))));
    ("csv_next_row", Mono (TArrow (t_int, TCon ("CsvRow", []))));
    ("csv_close",    Mono (TArrow (t_int, t_atom)));
    (* TCP/HTTP transport builtins *)
    ("tcp_connect",             poly1 (fun e -> TArrow (t_string, TArrow (t_int, t_result t_int e))));
    ("tcp_send_all",            poly1 (fun e -> TArrow (t_int, TArrow (t_string, t_result t_unit e))));
    ("tcp_recv_all",            poly1 (fun e -> TArrow (t_int, TArrow (t_int, TArrow (t_int, t_result t_string e)))));
    ("tcp_close",               Mono (TArrow (t_int, t_unit)));
    (* tcp_recv_exact(fd, n): reads exactly n bytes, returns Result(Bytes, String) *)
    ("tcp_recv_exact",          Mono (TArrow (t_int, TArrow (t_int, t_result (TCon ("Bytes", [])) t_string))));
    (* md5(s): returns 32-char lowercase hex digest *)
    ("md5",                     Mono (TArrow (t_string, t_string)));
    ("tcp_recv_http",           poly1 (fun e -> TArrow (t_int, TArrow (t_int, t_result t_string e))));
    ("tcp_recv_http_headers",   poly1 (fun e -> TArrow (t_int, t_result (TTuple [t_string; t_int; t_bool]) e)));
    ("tcp_recv_chunk",          poly1 (fun e -> TArrow (t_int, TArrow (t_int, t_result t_string e))));
    ("tcp_recv_chunked_frame",  poly1 (fun e -> TArrow (t_int, t_result t_string e)));
    (* http_serialize_request(method, host, path, query_opt, headers, body) -> String *)
    ("http_serialize_request",  Mono (TArrow (t_string, TArrow (t_string, TArrow (t_string,
        TArrow (t_option t_string, TArrow (t_list (TCon ("Header", [])), TArrow (t_string, t_string))))))));
    ("http_parse_response",     poly1 (fun e -> TArrow (t_string,
        t_result (TTuple [t_int; t_list (TCon ("Header", [])); t_string]) e)));
    (* http_server_listen(port, max_conns, idle_timeout, pipeline_fn) *)
    ("http_server_listen",      poly1 (fun a -> TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (TArrow (a, a), t_unit))))));
    (* http_server_spawn_n(port, n, max_conns, idle_timeout, pipeline_fn) -> Int (pid) *)
    ("http_server_spawn_n",     poly1 (fun a -> TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (TArrow (a, a), t_int)))))));
    ("http_server_wait",        Mono (TArrow (t_int, t_unit)));
    (* WebSocket builtins — WsFrame and SelectResult declared in websocket.march *)
    ("ws_recv",   Mono (TArrow (t_int, TCon ("WsFrame", []))));
    ("ws_send",   Mono (TArrow (t_int, TArrow (TCon ("WsFrame", []), t_unit))));
    ("ws_select", Mono (TArrow (t_int, TArrow (t_int, TArrow (t_int, TCon ("SelectResult", []))))));
    (* Dir I/O builtins *)
    ("dir_exists",      Mono (TArrow (t_string, t_bool)));
    ("dir_list",        poly1 (fun e -> TArrow (t_string, t_result (t_list t_string) e)));
    ("dir_mkdir",       poly1 (fun e -> TArrow (t_string, t_result t_unit e)));
    ("dir_mkdir_p",     poly1 (fun e -> TArrow (t_string, t_result t_unit e)));
    ("dir_rmdir",       poly1 (fun e -> TArrow (t_string, t_result t_unit e)));
    ("dir_rm_rf",       poly1 (fun e -> TArrow (t_string, t_result t_unit e)));
    (* String extra builtins *)
    ("string_last_index_of", Mono (TArrow (t_string, TArrow (t_string, t_option t_int))));
    (* App/Supervisor builtins *)
    ("worker",          poly1 (fun a -> TArrow (a, TCon ("ChildSpec", []))));
    ("Supervisor.spec", Mono (TArrow (t_atom, TArrow (t_list (TCon ("ChildSpec", [])),
                                                       TCon ("SupervisorSpec", [])))));
    (* Dynamic supervisor builtins *)
    ("dynamic_supervisor", Mono (TArrow (t_atom, TArrow (t_atom, TCon ("ChildSpec", [])))));
    ("Supervisor.start_child",
     poly1 (fun a -> TArrow (t_atom, TArrow (TCon ("ChildSpec", []),
                                             t_result (TCon ("Pid", [a])) t_string))));
    ("Supervisor.stop_child",
     Mono (TArrow (t_atom, TArrow (t_int, t_result t_unit t_string))));
    ("Supervisor.which_children",
     Mono (TArrow (t_atom, t_list t_unit)));   (* simplified; full type is List({pid,...}) *)
    ("Supervisor.count_children",
     Mono (TArrow (t_atom, TCon ("SupervisorSpec", []))));  (* simplified return type *)
    ("App.stop",        Mono (TArrow (t_unit, t_unit)));
    (* Session-typed channel builtins — Chan.send/recv/close are special-cased in
       infer_expr for proper session type advancement. These entries just put the
       names in scope; the real typing is done in the Chan.* EApp branches. *)
    ("Chan.new",    poly2 (fun a b -> TArrow (t_string, TTuple [a; b])));
    ("Chan.send",   poly2 (fun a b -> TArrow (a, TArrow (t_unit, b))));
    ("Chan.recv",   poly1 (fun a -> TArrow (t_unit, a)));
    ("Chan.close",  Mono (TArrow (t_unit, t_unit)));
    ("Chan.choose", poly2 (fun a b -> TArrow (a, TArrow (t_atom, b))));
    ("Chan.offer",  poly1 (fun a -> TArrow (a, TTuple [t_atom; a])));
    (* Byte builtins *)
    ("byte_to_char", Mono (TArrow (t_int, t_string)));
    (* Actor message-passing builtins *)
    ("actor_cast",  poly2 (fun a b -> TArrow (a, TArrow (b, t_unit))));
    ("actor_call",  poly2 (fun a e -> TArrow (a, TArrow (a, TArrow (t_int, t_result a e)))));
    ("actor_reply", poly2 (fun a b -> TArrow (a, TArrow (b, t_unit))));
    (* Logger builtins — 0-arg variants typed as Mono(result) so foo() works *)
    ("logger_set_level",   Mono (TArrow (t_int, t_unit)));
    ("logger_get_level",   Mono t_int);
    ("logger_add_context", Mono (TArrow (t_string, TArrow (t_string, t_unit))));
    ("logger_clear_context", Mono t_unit);
    ("logger_get_context", Mono (t_list (TTuple [t_string; t_string])));
    ("logger_write",       Mono (TArrow (t_string, TArrow (t_string,
        TArrow (t_list (TTuple [t_string; t_string]),
        TArrow (t_list (TTuple [t_string; t_string]), t_unit))))));
    (* Process builtins — 0-arg variants typed as Mono(result) *)
    ("process_env",        Mono (TArrow (t_string, t_option t_string)));
    ("process_set_env",    Mono (TArrow (t_string, TArrow (t_string, t_unit))));
    ("process_cwd",        Mono t_string);
    ("process_exit",       Mono (TArrow (t_int, t_unit)));
    ("process_argv",       Mono (t_list t_string));
    ("process_pid",        Mono t_int);
    ("process_spawn_sync", poly1 (fun e ->
        TArrow (t_string, TArrow (t_list t_string,
          t_result (TCon ("ProcessResult", [])) e))));
    ("process_spawn_lines", poly2 (fun a e ->
        TArrow (t_string, TArrow (t_list t_string,
          t_result (TCon ("Seq", [a])) e))));
    (* Actor self/receive builtins — 0-arg: foo() parses as EApp(f,[])
       so infer_app returns the type directly without unwrapping TArrow *)
    ("self",    poly1 (fun a -> TCon ("Pid", [a])));
    ("receive", poly1 (fun a -> a));
    (* Crypto / encoding builtins *)
    ("sha256",          Mono (TArrow (TCon ("Bytes", []), TCon ("Bytes", []))));
    ("hmac_sha256",     Mono (TArrow (TCon ("Bytes", []), TArrow (TCon ("Bytes", []),
        TCon ("Bytes", [])))));
    ("pbkdf2_sha256",   Mono (TArrow (t_string, TArrow (TCon ("Bytes", []),
        TArrow (t_int, TArrow (t_int,
        TCon ("Bytes", [])))))));
    ("base64_encode",   Mono (TArrow (TCon ("Bytes", []), t_string)));
    ("base64_decode",   Mono (TArrow (t_string, TCon ("Bytes", []))));
    ("random_bytes",    Mono (TArrow (t_int, TCon ("Bytes", []))));
    (* NativeArray builtins — flat OCaml arrays for fast numeric loops (P10).
       NativeIntArr / NativeFloatArr are opaque types (0-arity constructors).
       These builtins are interpreter-path only; compiled mode support is
       tracked in specs/optimizations.md P10 Phase 2. *)
    (* Int array *)
    ("native_int_arr_make",
       Mono (TArrow (t_int, TArrow (t_int, TCon ("NativeIntArr", [])))));
    ("native_int_arr_length",
       Mono (TArrow (TCon ("NativeIntArr", []), t_int)));
    ("native_int_arr_get",
       Mono (TArrow (TCon ("NativeIntArr", []), TArrow (t_int, t_int))));
    ("native_int_arr_set",
       Mono (TArrow (TCon ("NativeIntArr", []),
             TArrow (t_int, TArrow (t_int, TCon ("NativeIntArr", []))))));
    ("native_int_arr_sum",
       Mono (TArrow (TCon ("NativeIntArr", []), t_int)));
    ("native_int_arr_map",
       Mono (TArrow (TCon ("NativeIntArr", []),
             TArrow (TArrow (t_int, t_int), TCon ("NativeIntArr", [])))));
    ("native_int_arr_fold",
       poly1 (fun a ->
         TArrow (a, TArrow (TCon ("NativeIntArr", []),
                   TArrow (TArrow (a, TArrow (t_int, a)), a)))));
    ("native_int_arr_from_list",
       Mono (TArrow (t_list t_int, TCon ("NativeIntArr", []))));
    ("native_int_arr_to_list",
       Mono (TArrow (TCon ("NativeIntArr", []), t_list t_int)));
    (* Float array *)
    ("native_float_arr_make",
       Mono (TArrow (t_int, TArrow (t_float, TCon ("NativeFloatArr", [])))));
    ("native_float_arr_length",
       Mono (TArrow (TCon ("NativeFloatArr", []), t_int)));
    ("native_float_arr_get",
       Mono (TArrow (TCon ("NativeFloatArr", []), TArrow (t_int, t_float))));
    ("native_float_arr_set",
       Mono (TArrow (TCon ("NativeFloatArr", []),
             TArrow (t_int, TArrow (t_float, TCon ("NativeFloatArr", []))))));
    ("native_float_arr_sum",
       Mono (TArrow (TCon ("NativeFloatArr", []), t_float)));
    ("native_float_arr_map",
       Mono (TArrow (TCon ("NativeFloatArr", []),
             TArrow (TArrow (t_float, t_float), TCon ("NativeFloatArr", [])))));
    ("native_float_arr_fold",
       poly1 (fun a ->
         TArrow (a, TArrow (TCon ("NativeFloatArr", []),
                   TArrow (TArrow (a, TArrow (t_float, a)), a)))));
    ("native_float_arr_from_list",
       Mono (TArrow (t_list t_float, TCon ("NativeFloatArr", []))));
    ("native_float_arr_to_list",
       Mono (TArrow (TCon ("NativeFloatArr", []), t_list t_float)));
    (* TypedArray builtins — contiguous native arrays for columnar DataFrame storage *)
    ("typed_array_create",   poly1 (fun a ->
        TArrow (t_int, TArrow (a, TCon ("TypedArray", [a])))));
    ("typed_array_get",      poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), TArrow (t_int, a))));
    ("typed_array_set",      poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), TArrow (t_int, TArrow (a, TCon ("TypedArray", [a]))))));
    ("typed_array_length",   poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), t_int)));
    ("typed_array_slice",    poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), TArrow (t_int, TArrow (t_int, TCon ("TypedArray", [a]))))));
    ("typed_array_map",      poly2 (fun a b ->
        TArrow (TCon ("TypedArray", [a]), TArrow (TArrow (a, b), TCon ("TypedArray", [b])))));
    ("typed_array_filter",   poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), TArrow (TCon ("TypedArray", [t_bool]), TCon ("TypedArray", [a])))));
    ("typed_array_fold",     poly2 (fun a b ->
        TArrow (TCon ("TypedArray", [a]), TArrow (b, TArrow (TArrow (b, TArrow (a, b)), b)))));
    ("typed_array_from_list", poly1 (fun a ->
        TArrow (t_list a, TCon ("TypedArray", [a]))));
    ("typed_array_to_list",  poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), t_list a)));
  ]

let builtin_types : (string * int) list =
  [ ("Int",    0); ("Float",  0); ("Bool",  0); ("String", 0);
    ("Char",   0); ("Byte",   0); ("Atom",  0); ("Unit",   0);
    ("List",   1); ("Option", 1); ("Array", 1); ("Set",    1); ("Seq",    1);
    ("TypedArray", 1);
    ("Result", 2); ("Map",    2);
    ("Pid",    1); ("Cap",    1); ("Future",1); ("Stream", 1);
    ("Task",   1); ("WorkPool", 0); ("Node",   0);
    ("ChildSpec", 0); ("SupervisorSpec", 0);
    ("Vector", 2); ("Matrix", 3); ("NDArray", 2);
    (* Capability token types — used as arguments to Cap(X) *)
    ("IO",            0); ("IO.Console",    0); ("IO.FileSystem", 0);
    ("IO.FileRead",   0); ("IO.FileWrite",  0); ("IO.Network",    0);
    ("IO.NetConnect", 0); ("IO.NetListen",  0); ("IO.Process",    0);
    ("IO.Clock",      0);
    (* NativeArray opaque types — flat numeric arrays (P10) *)
    ("NativeIntArr",   0); ("NativeFloatArr", 0); ]

(** Built-in constructor table for Option, Result, and List, which are
    pre-registered types.  User-declared types are added via [DType].
    Each constructor is registered under both its bare name ("Some") and its
    type-qualified name ("Option.Some") so that users can write either form. *)
let builtin_ctors : (string * ctor_info) list =
  let mk_var s = Ast.TyVar { txt = s; span = Ast.dummy_span } in
  let mk_list_ty s = Ast.TyCon ({ txt = "List"; span = Ast.dummy_span }, [mk_var s]) in
  let some_ci  = { ci_type = "Option"; ci_params = ["a"];      ci_arg_tys = [mk_var "a"]; ci_vis = Ast.Public } in
  let none_ci  = { ci_type = "Option"; ci_params = ["a"];      ci_arg_tys = []; ci_vis = Ast.Public } in
  let ok_ci    = { ci_type = "Result"; ci_params = ["a"; "e"]; ci_arg_tys = [mk_var "a"]; ci_vis = Ast.Public } in
  let err_ci   = { ci_type = "Result"; ci_params = ["a"; "e"]; ci_arg_tys = [mk_var "e"]; ci_vis = Ast.Public } in
  let nil_ci   = { ci_type = "List";   ci_params = ["a"];      ci_arg_tys = []; ci_vis = Ast.Public } in
  let cons_ci  = { ci_type = "List";   ci_params = ["a"];
                   ci_arg_tys = [mk_var "a"; mk_list_ty "a"]; ci_vis = Ast.Public } in
  [ ("Some",        some_ci);  ("Option.Some", some_ci);
    ("None",        none_ci);  ("Option.None", none_ci);
    ("Ok",          ok_ci);    ("Result.Ok",   ok_ci);
    ("Err",         err_ci);   ("Result.Err",  err_ci);
    ("Nil",         nil_ci);   ("List.Nil",    nil_ci);
    ("Cons",        cons_ci);  ("List.Cons",   cons_ci);
  ]

let base_env errors type_map =
  let env = make_env errors type_map in
  let env = bind_vars builtin_bindings env in
  let env = bind_vars builtin_interface_bindings env in
  { env with
    types      = builtin_types;
    ctors      = builtin_ctors;
    interfaces = builtin_interfaces;
    impls      = builtin_impls;
  }

(* =================================================================
   §10  Unification
   ================================================================= *)

(** Format a type for display in an error message.
    Uses pretty-printing with line-wrapping for long types. *)
let format_ty_for_error t =
  let flat = pp_ty t in
  if String.length flat > 50 then
    "\n    " ^ String.concat "\n    " (String.split_on_char '\n' (pp_ty_pretty ~indent:4 ~width:60 t))
  else "`" ^ flat ^ "`"

(** Report a type mismatch with a conversational Elm-style message. *)
let report_mismatch env ~span ~reason expected found =
  (* Build headline, using pretty-printing for long types *)
  let exp_str = format_ty_for_error expected in
  let fnd_str = format_ty_for_error found in
  let headline =
    if String.length (pp_ty expected) > 50 || String.length (pp_ty found) > 50 then
      Printf.sprintf "I expected:\n    %s\nbut found:\n    %s"
        (String.concat "\n    " (String.split_on_char '\n' (pp_ty_pretty ~indent:4 ~width:60 expected)))
        (String.concat "\n    " (String.split_on_char '\n' (pp_ty_pretty ~indent:4 ~width:60 found)))
    else
      render_parts
        [ MPText "I expected "; MPText exp_str;
          MPText " but found "; MPText fnd_str; MPText "." ]
  in
  let why_note =
    match reason with
    | None   -> []
    | Some r -> [ string_of_reason r ]
  in
  (* Contextual hint: when both types share the same constructor but differ
     in one argument, identify which argument mismatches. *)
  let mismatch_note =
    match repr expected, repr found with
    | TCon (name1, args1), TCon (name2, args2)
      when name1 = name2 && List.length args1 = List.length args2 ->
      (match find_arg_mismatch name1 args1 args2 with
       | Some (i, cname, exp_arg, fnd_arg) ->
         let ordinal = match i with 1 -> "1st" | 2 -> "2nd" | 3 -> "3rd"
           | n -> string_of_int n ^ "th" in
         [ Printf.sprintf "The %s argument of `%s` mismatches: expected `%s` but got `%s`."
             ordinal cname (pp_ty exp_arg) (pp_ty fnd_arg) ]
       | None -> [])
    | TRecord flds1, TRecord flds2 ->
      (* Find first field that differs *)
      let notes = List.filter_map (fun (name, t1) ->
        match List.assoc_opt name flds2 with
        | Some t2 when pp_ty t1 <> pp_ty t2 ->
          Some (Printf.sprintf "Field `%s` mismatches: expected `%s` but got `%s`."
            name (pp_ty t1) (pp_ty t2))
        | None ->
          Some (Printf.sprintf "Field `%s` is present in the expected type but missing in the found type." name)
        | _ -> None) flds1
      in
      (match notes with n :: _ -> [n] | [] -> [])
    | _ -> []
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
      labels; notes = why_note @ mismatch_note; code = None }

(** Structural equality for session types (used by [unify] for [TChan] cases).
    Intentionally ignores payload types — only checks session structure shape. *)
let rec session_ty_equal s1 s2 =
  match s1, s2 with
  | SEnd, SEnd -> true
  | SError, SError -> true
  | SSend (_, s1'), SSend (_, s2') -> session_ty_equal s1' s2'
  | SRecv (_, s1'), SRecv (_, s2') -> session_ty_equal s1' s2'
  | SChoose bs1, SChoose bs2 | SOffer bs1, SOffer bs2 ->
    List.length bs1 = List.length bs2 &&
    List.for_all2 (fun (l1, s1') (l2, s2') ->
        l1 = l2 && session_ty_equal s1' s2') bs1 bs2
  | SRec (x1, s1'), SRec (x2, s2') -> x1 = x2 && session_ty_equal s1' s2'
  | SVar x1, SVar x2 -> x1 = x2
  | SMSend (r1, _, s1'), SMSend (r2, _, s2') -> r1 = r2 && session_ty_equal s1' s2'
  | SMRecv (r1, _, s1'), SMRecv (r2, _, s2') -> r1 = r2 && session_ty_equal s1' s2'
  | _ -> false

(** Exact structural equality including payload types.
    Used by MPST mergeability check to determine if branches can be merged.
    Two branches can be merged only if they are completely identical. *)
let rec session_ty_exact_equal s1 s2 =
  match s1, s2 with
  | SEnd, SEnd -> true
  | SError, SError -> true
  | SSend (t1, s1'), SSend (t2, s2') ->
    pp_ty t1 = pp_ty t2 && session_ty_exact_equal s1' s2'
  | SRecv (t1, s1'), SRecv (t2, s2') ->
    pp_ty t1 = pp_ty t2 && session_ty_exact_equal s1' s2'
  | SChoose bs1, SChoose bs2 | SOffer bs1, SOffer bs2 ->
    List.length bs1 = List.length bs2 &&
    List.for_all2 (fun (l1, s1') (l2, s2') ->
        l1 = l2 && session_ty_exact_equal s1' s2') bs1 bs2
  | SRec (x1, s1'), SRec (x2, s2') -> x1 = x2 && session_ty_exact_equal s1' s2'
  | SVar x1, SVar x2 -> x1 = x2
  | SMSend (r1, t1, s1'), SMSend (r2, t2, s2') ->
    r1 = r2 && pp_ty t1 = pp_ty t2 && session_ty_exact_equal s1' s2'
  | SMRecv (r1, t1, s1'), SMRecv (r2, t2, s2') ->
    r1 = r2 && pp_ty t1 = pp_ty t2 && session_ty_exact_equal s1' s2'
  | _ -> false

(** Normalize type-level nat arithmetic.
    Reduces concrete sub-expressions and applies identity / annihilation laws.
    The result is in weak-head normal form: outer-most TNatOp is simplified as
    far as possible, sub-expressions are recursively normalized. *)
let rec normalize_tnat t =
  match repr t with
  | TNatOp (op, a, b) ->
    let a = normalize_tnat a and b = normalize_tnat b in
    (match op, a, b with
     | Ast.NatAdd, TNat m, TNat n  -> TNat (m + n)
     | Ast.NatAdd, t',    TNat 0   -> t'
     | Ast.NatAdd, TNat 0, t'      -> t'
     | Ast.NatMul, TNat m, TNat n  -> TNat (m * n)
     | Ast.NatMul, _,     TNat 0   -> TNat 0
     | Ast.NatMul, TNat 0, _       -> TNat 0
     | Ast.NatMul, t',    TNat 1   -> t'
     | Ast.NatMul, TNat 1, t'      -> t'
     | _                           -> TNatOp (op, a, b))
  | t -> t

(** Unify [t1] and [t2], reporting any mismatch to [env.errors].
    Uses [TError] as a recovery sentinel — if either side is [TError]
    the constraint is silently satisfied (the error was already reported). *)
let rec unify env ~span ?(reason = None) t1 t2 =
  let t1 = normalize_tnat t1 and t2 = normalize_tnat t2 in
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

  (* Transparent coercion: a linear/affine value is structurally the same
     type as its inner (unrestricted) type.  This allows e.g. a field of
     type [linear Int] to unify with an expected [Int] at a use site while
     still preserving the TLin wrapper for linearity tracking in let-bindings. *)
  | TLin (_, inner), other | other, TLin (_, inner) ->
    unify env ~span ~reason inner other

  | TNat n1, TNat n2 when n1 = n2 -> ()

  (* Structural unification for nat ops that could not be fully normalized
     (e.g. both sides have the same un-solved variable structure). *)
  | TNatOp (op1, a1, b1), TNatOp (op2, a2, b2) when op1 = op2 ->
    unify env ~span ~reason a1 a2;
    unify env ~span ~reason b1 b2

  (* Solve: one side is a concrete nat, the other is a partially-known op.
     E.g. TVar a + TNat 2 = TNat 5  →  a = 3. *)
  | TNatOp (op, a, b), TNat n ->
    solve_nat_eq env ~span ~reason op a b n
  | TNat n, TNatOp (op, a, b) ->
    solve_nat_eq env ~span ~reason op a b n

  (* Session-typed channels unify by checking their current session states match. *)
  | TChan r1, TChan r2 ->
    if not (session_ty_equal !r1 !r2) then
      Err.error env.errors ~span
        (Printf.sprintf
           "Session type mismatch: expected channel at `%s` but found `%s`."
           (pp_session_ty !r1) (pp_session_ty !r2))

  | _ ->
    report_mismatch env ~span ~reason t1 t2

(** Solve a type-level nat equation: (op a b) = n.
    Handles exactly the cases where one operand is an unbound TVar and
    the other is a concrete TNat, so we can isolate the variable.
    Falls back to [report_mismatch] for anything more complex. *)
and solve_nat_eq env ~span ~reason op a b n =
  match op, a, b with
  (* a + k = n  →  a = n - k  (when n >= k) *)
  | Ast.NatAdd, TVar _, TNat k when n >= k ->
    unify env ~span ~reason a (TNat (n - k))
  (* k + a = n  →  a = n - k  (when n >= k) *)
  | Ast.NatAdd, TNat k, TVar _ when n >= k ->
    unify env ~span ~reason b (TNat (n - k))
  (* a * k = n  →  a = n / k  (when k divides n) *)
  | Ast.NatMul, TVar _, TNat k when k <> 0 && n mod k = 0 ->
    unify env ~span ~reason a (TNat (n / k))
  (* k * a = n  →  a = n / k  (when k divides n) *)
  | Ast.NatMul, TNat k, TVar _ when k <> 0 && n mod k = 0 ->
    unify env ~span ~reason b (TNat (n / k))
  | _ ->
    report_mismatch env ~span ~reason (TNatOp (op, a, b)) (TNat n)

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
    (* Special case: Chan(Role, Proto) — session-typed channel endpoint.
       Users write Chan(RoleName, ProtoName) in type annotations.
       The parser produces TyCon("Chan", [TyCon("Role",[]), TyCon("Proto",[])]).
       We intercept this before the normal type-lookup path. *)
    (match name.txt, args with
     | "Chan", [Ast.TyCon (role, []); Ast.TyCon (proto, [])] ->
       (match List.assoc_opt proto.txt env.protocols with
        | None ->
          Err.error env.errors ~span:proto.span
            (Printf.sprintf "I don't know a protocol called `%s`." proto.txt);
          TChan (ref SError)
        | Some pi ->
          (match List.assoc_opt role.txt pi.pi_projections with
           | None ->
             Err.error env.errors ~span:role.span
               (Printf.sprintf
                  "Protocol `%s` has no role called `%s`.\n\
                   Known roles: %s"
                  proto.txt role.txt
                  (String.concat ", " (List.map fst pi.pi_projections)));
             TChan (ref SError)
           | Some sty ->
             TLin (Ast.Linear, TChan (ref sty))))
     | "Chan", _ when name.txt = "Chan" ->
       Err.error env.errors ~span:name.span
         "Chan expects exactly two type arguments: Chan(RoleName, ProtocolName)";
       TChan (ref SError)
     | _ ->
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
       | _ -> TCon (name.txt, args')))

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

  | Ast.TyChan (role, proto) ->
    (* Look up the protocol and project onto the given role. *)
    (match List.assoc_opt proto.txt env.protocols with
     | None ->
       Err.error env.errors ~span:proto.span
         (Printf.sprintf "I don't know a protocol called `%s`." proto.txt);
       TChan (ref SError)
     | Some pi ->
       (match List.assoc_opt role.txt pi.pi_projections with
        | None ->
          Err.error env.errors ~span:role.span
            (Printf.sprintf
               "Protocol `%s` has no role called `%s`.\n\
                Known roles: %s"
               proto.txt role.txt
               (String.concat ", " (List.map fst pi.pi_projections)));
          TChan (ref SError)
        | Some sty ->
          TChan (ref sty)))

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

(** Register per-field linear sentinels for a named record variable [varname].
    When [ty] is or expands to a TRecord with linear fields, adds phantom
    ["varname#fieldname"] entries to env.lin so that EField accesses on
    that variable can detect double-use of individual linear fields. *)
let bind_linear_field_sentinels varname ty env =
  match expand_record env (repr ty) with
  | Some (TRecord flds) ->
    List.fold_left (fun acc_env (fname, fty) ->
        match repr fty with
        | TLin (lin, _) when lin <> Ast.Unrestricted ->
          let key = varname ^ "#" ^ fname in
          let le = { le_name = key; le_lin = lin; le_used = ref false } in
          { acc_env with lin = le :: acc_env.lin }
        | _ -> acc_env
      ) env flds
  | _ -> env

(* =================================================================
   §12  Linearity tracking
   ================================================================= *)

(** Record a use of variable [name].  Errors if a linear var is used
    more than once. *)
let record_use name span env =
  (* Mark any import entry that matches this name as used. *)
  if !(env.import_tracker) <> [] then
    List.iter (fun ie -> if ie.ie_matches name then ie.ie_used := true)
      !(env.import_tracker);
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

(** [bind_vars_with_linearity bindings env] is like [bind_vars] except it
    checks the repr'd type of each binding after unification: if the type
    has resolved to a [TLin] wrapper, the variable is registered as a
    linear/affine binding (tracked in [env.lin]) rather than an ordinary one.
    Use this wherever pattern-bound variables inherit linearity from the
    scrutinee, e.g. in match arms. *)
let bind_vars_with_linearity (bindings : (string * scheme) list) env =
  List.fold_left (fun acc_env (name, sch) ->
      match sch with
      | Mono t ->
        (match repr t with
         | TLin (lin, inner) when lin <> Ast.Unrestricted ->
           bind_linear name lin inner acc_env
         | t' ->
           let env1 = bind_var name (Mono t') acc_env in
           bind_linear_field_sentinels name t' env1)
      | _ -> bind_var name sch acc_env
    ) env bindings

(** [bind_pattern_bindings scrut_expr bindings env] adds [bindings] to [env].
    Linearity is propagated in two ways:
    1. If a binding's type (after unification) is [TLin], it is registered as
       linear (catches cases where the type annotation carries linearity).
    2. If [scrut_expr] is a linear/affine variable, ALL top-level bindings
       inherit that linearity — this covers the common pattern of matching
       a linearly-typed variable bound with the [linear x: T] syntax, where
       the internal type is plain [T] without a [TLin] wrapper. *)
let bind_pattern_bindings scrut_expr (bindings : (string * scheme) list) env =
  (* Check whether the scrutinee is itself a tracked linear variable. *)
  let inherited_lin =
    match scrut_expr with
    | Ast.EVar sname ->
      (match List.find_opt (fun le -> le.le_name = sname.txt) env.lin with
       | Some le when le.le_lin <> Ast.Unrestricted -> Some le.le_lin
       | _ -> None)
    | _ -> None
  in
  List.fold_left (fun acc_env (name, sch) ->
      match sch with
      | Mono t ->
        (match repr t with
         | TLin (lin, inner) when lin <> Ast.Unrestricted ->
           (* Binding type carries TLin — use that linearity. *)
           bind_linear name lin inner acc_env
         | t' ->
           (match inherited_lin with
            | Some lin ->
              (* Scrutinee was linear: the bound variable inherits its linearity. *)
              bind_linear name lin t' acc_env
            | None ->
              let env1 = bind_var name (Mono t') acc_env in
              bind_linear_field_sentinels name t' env1))
      | Poly (_, _, t) ->
        (* Generalised binding: bind normally but also add field sentinels for
           any linear fields in the underlying type. *)
        let env1 = bind_var name sch acc_env in
        bind_linear_field_sentinels name (repr t) env1
    ) env bindings

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
       let candidates = suggest_ctors name.txt env in
       let hint =
         if candidates = [] then
           "Is this a typo, or did you forget to declare the type?"
         else
           let lines = List.map (fun (k, ty) ->
               Printf.sprintf "  • `%s` — from type `%s`" k ty
             ) candidates in
           "Did you mean one of:\n" ^ String.concat "\n" lines
       in
       Err.error env.errors ~span:name.span
         (Printf.sprintf "I don't know a constructor called `%s`.\n%s"
            name.txt hint);
       let bindings = List.concat_map fst (List.map (infer_pattern env) ps) in
       bindings, TError
     | Some ci ->
       (* Emit a hint when the bare constructor name is ambiguous across types. *)
       let all_types = all_ctors_named name.txt env in
       (if List.length all_types > 1 && not (String.contains name.txt '.') then
         Err.hint env.errors ~span:name.span
           (Printf.sprintf
              "Constructor `%s` is defined by multiple types (%s). \
               Use a qualified form to disambiguate, e.g. `%s.%s`."
              name.txt
              (String.concat ", " all_types)
              (List.hd all_types)
              name.txt));
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
  | Ast.EAssert (_, sp)         -> sp

(* ══════════════════════════════════════════════════════════════════
   §E  Pattern exhaustiveness checking
   ══════════════════════════════════════════════════════════════════

   Implements a simplified version of Maranget's "Warnings for
   Pattern Matching" algorithm.  We build a pattern matrix (one row
   per branch, one column per nested level of structure) and look for
   a value that no row matches.  Missing values are reported as
   Warning diagnostics.
*)

(** Simplified pattern for exhaustiveness analysis. *)
type spat =
  | SPWild                          (** _ or any variable binding *)
  | SPCon  of string * spat list    (** Constructor: Some(x), None *)
  | SPLit  of Ast.literal           (** Literal: 0, true, "hi" *)
  | SPTup  of spat list             (** Tuple: (a, b) *)

(** Normalize an AST pattern to a [spat]. *)
let rec norm_pat (p : Ast.pattern) : spat =
  match p with
  | Ast.PatWild _            -> SPWild
  | Ast.PatVar  _            -> SPWild
  | Ast.PatAs  (p', _, _)    -> norm_pat p'
  | Ast.PatRecord _          -> SPWild   (* conservative *)
  | Ast.PatCon  (n, args)    -> SPCon (n.txt, List.map norm_pat args)
  | Ast.PatAtom (n, args, _) -> SPCon (":" ^ n, List.map norm_pat args)
  | Ast.PatTuple (ps, _)     -> SPTup (List.map norm_pat ps)
  | Ast.PatLit  (l, _)       -> SPLit l

(** All [(ctor_name, arity)] pairs for a type name, in declaration order.
    Qualified aliases (keys containing '.') are skipped so that exhaustiveness
    analysis only sees each constructor once under its bare name. *)
let ctors_for_type (env : env) type_name =
  List.filter_map (fun (k, (ci : ctor_info)) ->
    if ci.ci_type = type_name && not (String.contains k '.')
    then Some (k, List.length ci.ci_arg_tys)
    else None
  ) env.ctors

(** Instantiate a surface type with a substitution from param names to internal
    types.  Used to reconstruct constructor argument types. *)
let rec inst_ty (subst : (string * ty) list) (surf : Ast.ty) : ty =
  match surf with
  | Ast.TyVar name ->
    (match List.assoc_opt name.txt subst with
     | Some t -> t
     | None   -> TError)  (* unresolved type param — use error sentinel *)
  | Ast.TyCon (name, []) ->
    (match List.assoc_opt name.txt subst with
     | Some t -> t
     | None   -> TCon (name.txt, []))
  | Ast.TyCon (name, args) ->
    TCon (name.txt, List.map (inst_ty subst) args)
  | Ast.TyArrow (a, b) -> TArrow (inst_ty subst a, inst_ty subst b)
  | Ast.TyTuple ts     -> TTuple (List.map (inst_ty subst) ts)
  | _                  -> TError

(** Instantiated argument types for [ctor_name] given the parent type's
    concrete type arguments (e.g. [Int] for Option(Int)). *)
let ctor_arg_tys (env : env) ctor_name parent_args =
  match List.assoc_opt ctor_name env.ctors with
  | None -> []
  | Some ci ->
    let n = List.length ci.ci_params in
    let m = List.length parent_args in
    if n <> m then List.map (fun _ -> TError) ci.ci_arg_tys
    else
      let subst = List.combine ci.ci_params parent_args in
      List.map (inst_ty subst) ci.ci_arg_tys

(** Specialize the pattern matrix for constructor [c] with [a] sub-columns.
    - Wildcard rows → a wildcards prepended to remaining columns.
    - Matching [c] rows → their args prepended to remaining columns.
    - Other constructor rows → dropped. *)
let spec_ctor_mc (c : string) (a : int) (matrix : spat list list)
    : spat list list =
  List.filter_map (fun row ->
    match row with
    | [] -> None
    | p :: rest ->
      match p with
      | SPWild               -> Some (List.init a (fun _ -> SPWild) @ rest)
      | SPCon (d, ps) when d = c -> Some (ps @ rest)
      | SPCon _ | SPLit _ | SPTup _ -> None
  ) matrix

(** Specialize the pattern matrix for a tuple of [a] components. *)
let spec_tup_mc (a : int) (matrix : spat list list) : spat list list =
  List.filter_map (fun row ->
    match row with
    | [] -> None
    | p :: rest ->
      match p with
      | SPWild               -> Some (List.init a (fun _ -> SPWild) @ rest)
      | SPTup ps when List.length ps = a -> Some (ps @ rest)
      | _ -> None
  ) matrix

(** Specialize the pattern matrix for a literal value [lit].
    Wildcard rows and matching literal rows pass through (minus first col). *)
let spec_lit_mc (lit : Ast.literal) (matrix : spat list list)
    : spat list list =
  List.filter_map (fun row ->
    match row with
    | [] -> None
    | p :: rest ->
      match p with
      | SPWild           -> Some rest
      | SPLit l when l = lit -> Some rest
      | _ -> None
  ) matrix

(** Default matrix: rows whose first column is a wildcard, with that
    column removed.  Used for infinite-domain types that need a catch-all. *)
let default_mc (matrix : spat list list) : spat list list =
  List.filter_map (fun row ->
    match row with
    | SPWild :: rest -> Some rest
    | _ -> None
  ) matrix

(** Split a list into the first [n] elements and the remainder. *)
let split_at n lst =
  let rec go acc i = function
    | []       -> (List.rev acc, [])
    | x :: rest ->
      if i >= n then (List.rev acc, x :: rest)
      else go (x :: acc) (i + 1) rest
  in
  go [] 0 lst

(** Produce a concise human-readable example value for [ty].
    Used only to build warning messages, not for type-checking. *)
let rec example_of (ty : ty) : string =
  match repr ty with
  | TCon ("Int",    []) -> "0"
  | TCon ("Float",  []) -> "0.0"
  | TCon ("String", []) -> "\"\""
  | TCon ("Bool",   []) -> "true"
  | TCon ("Char",   []) -> "' '"
  | TCon (n, _)         -> n
  | TTuple []           -> "()"
  | TTuple ts           -> "(" ^ String.concat ", " (List.map example_of ts) ^ ")"
  | TVar _              -> "_"
  | TError              -> "_"
  | TArrow _            -> "<fn>"
  | TRecord _           -> "{ ... }"
  | TChan _             -> "<chan>"
  | TLin (_, t)         -> example_of t
  | TNat n              -> string_of_int n
  | TNatOp _            -> "_"

(** Core exhaustiveness algorithm (Maranget-style).

    [find_missing_mc env tys matrix] tries to find an example value
    (represented as a list of strings, one per column) that is not
    matched by any row in [matrix].

    Returns [None] if the matrix is exhaustive for [tys], or
    [Some examples] (a list of column examples) if non-exhaustive.

    Invariant: when called with k columns, a [Some] result contains
    exactly k strings (for the outermost call, k = 1). *)
let rec find_missing_mc (env : env) (tys : ty list) (matrix : spat list list)
    : string list option =
  match tys with
  | [] ->
    (* No columns left: exhaustive iff matrix has ≥1 row covering this point. *)
    if matrix = [] then Some [] else None
  | ty :: rest_tys ->
    let ty = repr ty in
    (* If any row starts with a wildcard, it covers all values in this column.
       Check the wildcard rows' remaining columns via the default matrix. *)
    let has_first_wild =
      List.exists
        (fun row -> match row with SPWild :: _ -> true | _ -> false)
        matrix
    in
    if has_first_wild then begin
      let def = default_mc matrix in
      match find_missing_mc env rest_tys def with
      | None -> None
      | Some rest_exs ->
        (* First column is covered; use a placeholder for the counterexample. *)
        Some ("_" :: rest_exs)
    end else
    match ty with
    | TError -> None   (* error recovery — skip *)
    | TVar _ ->
      (* Unknown type: treat like infinite domain. *)
      let def = default_mc matrix in
      (match find_missing_mc env rest_tys def with
       | None -> None
       | Some rest_exs -> Some ("_" :: rest_exs))
    | TCon ("Bool", []) ->
      (* Bool has exactly two values: true and false (literal patterns). *)
      let check_lit b =
        let sub = spec_lit_mc (Ast.LitBool b) matrix in
        match find_missing_mc env rest_tys sub with
        | None -> None
        | Some rest_exs ->
          Some ((if b then "true" else "false") :: rest_exs)
      in
      (match check_lit true with
       | Some _ as s -> s
       | None        -> check_lit false)
    | TCon (("Int" | "Float" | "String" | "Char" | "Atom"), _) ->
      (* Infinite domains require a wildcard catch-all.
         (No wildcards exist here — checked above — so report missing.) *)
      let def = default_mc matrix in
      (match find_missing_mc env rest_tys def with
       | None -> None
       | Some rest_exs -> Some ("_" :: rest_exs))
    | TCon (name, parent_args) ->
      let ctors = ctors_for_type env name in
      if ctors = [] then
        (* Opaque / unknown type: conservative skip. *)
        let def = default_mc matrix in
        (match find_missing_mc env rest_tys def with
         | None -> None
         | Some rest_exs -> Some ("_" :: rest_exs))
      else begin
        (* Collect which constructors appear in the first column. *)
        let seen =
          List.filter_map
            (fun row -> match row with SPCon (c, _) :: _ -> Some c | _ -> None)
            matrix
        in
        (* Is the signature complete? (All ctors present — no wildcards since
           those were handled above.) *)
        let is_complete =
          List.for_all (fun (c, _) -> List.mem c seen) ctors
        in
        if is_complete then
          (* Every constructor appears: check each one's sub-matrix. *)
          List.find_map (fun (ctor_name, arity) ->
            let arg_tys = ctor_arg_tys env ctor_name parent_args in
            let sub      = spec_ctor_mc ctor_name arity matrix in
            let full_tys = arg_tys @ rest_tys in
            match find_missing_mc env full_tys sub with
            | None -> None
            | Some exs ->
              let ctor_exs, rest_exs = split_at arity exs in
              let ctor_str =
                if arity = 0 then ctor_name
                else
                  Printf.sprintf "%s(%s)" ctor_name
                    (String.concat ", " ctor_exs)
              in
              Some (ctor_str :: rest_exs)
          ) ctors
        else begin
          (* Some constructor missing from first col and no wildcards:
             find one and report it. *)
          let def = default_mc matrix in
          match find_missing_mc env rest_tys def with
          | None -> None
          | Some rest_exs ->
            let missing_ctor =
              List.find_opt (fun (c, _) -> not (List.mem c seen)) ctors
            in
            let first_ex = match missing_ctor with
              | Some (c, 0) -> c
              | Some (c, _) ->
                let args = ctor_arg_tys env c parent_args in
                Printf.sprintf "%s(%s)" c
                  (String.concat ", " (List.map example_of args))
              | None -> "_"
            in
            Some (first_ex :: rest_exs)
        end
      end
    | TTuple [] -> None   (* unit — always covered *)
    | TTuple inner_tys ->
      let arity = List.length inner_tys in
      let any_tup =
        List.exists
          (fun row -> match row with SPTup _ :: _ -> true | _ -> false)
          matrix
      in
      if any_tup then begin
        (* At least one tuple pattern: specialize and recurse. *)
        let sub      = spec_tup_mc arity matrix in
        let full_tys = inner_tys @ rest_tys in
        match find_missing_mc env full_tys sub with
        | None -> None
        | Some exs ->
          let tup_exs, rest_exs = split_at arity exs in
          let tup_str =
            Printf.sprintf "(%s)" (String.concat ", " tup_exs)
          in
          Some (tup_str :: rest_exs)
      end else begin
        (* No tuple patterns and no wildcards: entirely missing. *)
        let def = default_mc matrix in
        match find_missing_mc env rest_tys def with
        | None -> None
        | Some rest_exs ->
          let tup_ex =
            Printf.sprintf "(%s)"
              (String.concat ", " (List.map example_of inner_tys))
          in
          Some (tup_ex :: rest_exs)
      end
    | TArrow _ | TRecord _ | TChan _ | TLin _ | TNat _ | TNatOp _ ->
      (* Non-enumerable types: treat like infinite domain. *)
      let def = default_mc matrix in
      (match find_missing_mc env rest_tys def with
       | None -> None
       | Some rest_exs -> Some ("_" :: rest_exs))

(** Emit a Warning if the match on [scrut_ty] with [branches] is non-exhaustive.
    Skips the check when any branch has a guard (coverage becomes undecidable). *)
let check_exhaustiveness (env : env) (span : Ast.span) (scrut_ty : ty)
    (branches : Ast.branch list) =
  let has_guards =
    List.exists (fun (br : Ast.branch) -> br.branch_guard <> None) branches
  in
  if has_guards then ()
  else begin
    let matrix =
      List.map (fun (br : Ast.branch) -> [norm_pat br.branch_pat]) branches
    in
    match find_missing_mc env [scrut_ty] matrix with
    | None -> ()
    | Some (ex :: _) ->
      Err.warning env.errors ~span
        (Printf.sprintf "Non-exhaustive pattern match — missing case: %s" ex)
    | Some [] ->
      Err.warning env.errors ~span "Non-exhaustive pattern match"
  end

(** Unfold one step of a recursive session type.
    [SRec(x, body)] becomes [body] with every [SVar x] replaced by [SRec(x, body)].
    Keeps unfolding until the outermost constructor is no longer [SRec],
    so callers can pattern-match directly on [SSend] / [SRecv] / etc. *)
let rec unfold_srec s =
  match s with
  | SRec (x, body) ->
    let rec subst_inner s =
      match s with
      | SVar y when y = x          -> SRec (x, body)
      | SSend (t, s')              -> SSend (t, subst_inner s')
      | SRecv (t, s')              -> SRecv (t, subst_inner s')
      | SChoose bs                 -> SChoose (List.map (fun (l, s') -> (l, subst_inner s')) bs)
      | SOffer  bs                 -> SOffer  (List.map (fun (l, s') -> (l, subst_inner s')) bs)
      | SMSend (r, t, s')          -> SMSend (r, t, subst_inner s')
      | SMRecv (r, t, s')          -> SMRecv (r, t, subst_inner s')
      | SRec (y, s') when y <> x  -> SRec (y, subst_inner s')
      | other                      -> other
    in
    unfold_srec (subst_inner body)
  | _ -> s

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
          notes   = [ "Fill this hole with an expression of the type shown above." ];
          code    = None };
      t

    (* ── Function application ─────────────────────────────────────── *)
    (* ── Session channel operations (special casing for session type advancement) ── *)

    (* Normalize Mod.method(args) → EVar("Mod.method")(args) so that Chan.send etc.
       work whether written as `Chan.send(ch, v)` (field access) or `Chan.send(ch, v)`. *)
    | Ast.EApp (Ast.EField (Ast.ECon ({txt = mod_name; _}, [], _),
                             {txt = meth; _}, _),
                args, sp) ->
      let norm = Ast.EApp (Ast.EVar {txt = mod_name ^ "." ^ meth;
                                     span = Ast.dummy_span}, args, sp) in
      infer_expr env norm

    (* Chan.new(proto_name_string_or_atom) →
         (linear Chan(RoleA, Proto), linear Chan(RoleB, Proto))
       The protocol name is the sole argument; we look it up to generate typed endpoints. *)
    | Ast.EApp (Ast.EVar { txt = "Chan.new"; _ }, [proto_expr], sp) ->
      let proto_name = match proto_expr with
        | Ast.ELit (LitString s, _) | Ast.ELit (LitAtom s, _) -> Some s
        | Ast.EVar n -> Some n.txt
        | Ast.ECon (n, [], _) -> Some n.txt   (* bare Protocol name: Chan.new(MyProto) *)
        | _ -> None
      in
      (match proto_name with
       | None ->
         Err.error env.errors ~span:sp
           "Chan.new: argument must be a protocol name (string, atom, or bare name).";
         TError
       | Some pname ->
         (match List.assoc_opt pname env.protocols with
          | None ->
            Err.error env.errors ~span:sp
              (Printf.sprintf "Chan.new: protocol `%s` is not declared." pname);
            TError
          | Some pi ->
            (match pi.pi_projections with
             | [(_, sty_a); (_, sty_b)] ->
               (* Return (linear Chan(A, Proto), linear Chan(B, Proto)) *)
               let ty_a = TLin (Ast.Linear, TChan (ref sty_a)) in
               let ty_b = TLin (Ast.Linear, TChan (ref sty_b)) in
               TTuple [ty_a; ty_b]
             | [_] ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf "Chan.new: protocol `%s` has only one role." pname);
               TError
             | [] ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf "Chan.new: protocol `%s` has no roles." pname);
               TError
             | _ ->
               (* 3+ roles: just return first two as a pair *)
               (match pi.pi_projections with
                | (_, sty_a) :: (_, sty_b) :: _ ->
                  TTuple [TLin (Ast.Linear, TChan (ref sty_a));
                          TLin (Ast.Linear, TChan (ref sty_b))]
                | _ -> TError))))

    (* Chan.send(ch, value) → linear Chan at continuation session state.
       Pre-condition: ch must be at SSend(T, S). Post: ch is consumed; returns Chan at S. *)
    | Ast.EApp (Ast.EVar { txt = "Chan.send"; _ }, [ch_expr; val_expr], sp) ->
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SSend (payload_ty, cont) ->
            check_expr env val_expr payload_ty
              ~reason:(Some (RBuiltin "Payload type of Chan.send"));
            TLin (Ast.Linear, TChan (ref cont))
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "Chan.send: channel is at `%s` but I expected `Send(T, ...)`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "Chan.send: expected a channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    (* Chan.recv(ch) → (value, linear Chan at continuation).
       Pre-condition: ch must be at SRecv(T, S). Post: ch consumed; returns (T, Chan at S). *)
    | Ast.EApp (Ast.EVar { txt = "Chan.recv"; _ }, [ch_expr], sp) ->
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SRecv (payload_ty, cont) ->
            TTuple [payload_ty; TLin (Ast.Linear, TChan (ref cont))]
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "Chan.recv: channel is at `%s` but I expected `Recv(T, ...)`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "Chan.recv: expected a channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    (* Chan.close(ch) → Unit.
       Pre-condition: ch must be at SEnd. *)
    | Ast.EApp (Ast.EVar { txt = "Chan.close"; _ }, [ch_expr], sp) ->
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SEnd -> t_unit
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "Chan.close: channel is at `%s` but I expected `End`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "Chan.close: expected a channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    (* Chan.choose(ch, :label) → linear Chan at chosen branch continuation.
       Pre-condition: ch must be at SChoose(branches). *)
    | Ast.EApp (Ast.EVar { txt = "Chan.choose"; _ }, [ch_expr; label_expr], sp) ->
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      let label_str = match label_expr with
        | Ast.EAtom (s, [], _) -> Some s
        | Ast.ELit (LitAtom s, _) -> Some s
        | _ -> None
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SChoose branches ->
            (match label_str with
             | None ->
               Err.error env.errors ~span:sp
                 "Chan.choose: label must be an atom literal (e.g. :ok).";
               TError
             | Some lbl ->
               (match List.assoc_opt lbl branches with
                | Some cont -> TLin (Ast.Linear, TChan (ref cont))
                | None ->
                  Err.error env.errors ~span:sp
                    (Printf.sprintf
                       "Chan.choose: label `:%s` is not a valid branch of this protocol." lbl);
                  TError))
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "Chan.choose: channel is at `%s` but I expected `Choose{...}`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "Chan.choose: expected a channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    (* Chan.offer(ch) → (Atom, linear Chan at some continuation).
       Pre-condition: ch must be at SOffer(branches).
       Returns (label_atom, new_chan) where new_chan is at the continuation
       for whichever branch the other side chose.  The exact continuation is
       not known statically without dependent types, so we return the first
       branch's continuation type as a conservative approximation that still
       lets users write match expressions over the returned atom. *)
    | Ast.EApp (Ast.EVar { txt = "Chan.offer"; _ }, [ch_expr], sp) ->
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SOffer branches ->
            let cont_ty = match branches with
              | (_, sty) :: _ -> TLin (Ast.Linear, TChan (ref sty))
              | []             -> TError
            in
            TTuple [t_atom; cont_ty]
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "Chan.offer: channel is at `%s` but I expected `Offer{...}`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "Chan.offer: expected a channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    (* ── MPST multi-party session operations ─────────────────────────
       These mirror Chan.* but work with multi-party protocols (N>2 roles).
       MPST.new(Proto)            → (ep_r1, ep_r2, ..., ep_rN) sorted by role name
       MPST.send(ep, :Role, val)  → new_ep  (must be at SMSend(Role, T, S))
       MPST.recv(ep, :Role)       → (val, new_ep) (must be at SMRecv(Role, T, S))
       MPST.close(ep)             → ()  (must be at SEnd)
    ──────────────────────────────────────────────────────────────────── *)

    | Ast.EApp (Ast.EVar { txt = "MPST.new"; _ }, [proto_expr], sp) ->
      (* Look up the protocol and return a tuple of one TChan per role. *)
      let proto_name = match proto_expr with
        | Ast.ELit (Ast.LitString s, _) -> Some s
        | Ast.EAtom (s, [], _)           -> Some s
        | Ast.ECon (n, [], _)            -> Some n.txt
        | Ast.EVar n                     -> Some n.txt
        | _ -> None
      in
      (match proto_name with
       | None ->
         Err.error env.errors ~span:sp
           "MPST.new: argument must be a protocol name.";
         TError
       | Some pname ->
         (match List.assoc_opt pname env.protocols with
          | None ->
            Err.error env.errors ~span:sp
              (Printf.sprintf "MPST.new: protocol `%s` is not declared." pname);
            TError
          | Some pi ->
            let n = List.length pi.pi_projections in
            if n < 3 then begin
              Err.error env.errors ~span:sp
                (Printf.sprintf
                   "MPST.new: protocol `%s` has %d role(s) but MPST.new \
                    requires at least 3. Use Chan.new for binary protocols."
                   pname n);
              TError
            end else
              (* Return tuple of TChan endpoints, sorted by role (same as projections order) *)
              TTuple (List.map (fun (_, s_ty) ->
                  TLin (Ast.Linear, TChan (ref s_ty))
                ) pi.pi_projections)))

    | Ast.EApp (Ast.EVar { txt = "MPST.send"; _ }, [ch_expr; role_expr; val_expr], sp) ->
      (* MPST.send(ch, Server, value) — ch must be at SMSend(Server, T, S).
         The role can be written as a bare uppercase name (ECon) or atom (:server). *)
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SMSend (target_role, payload_ty, cont) ->
            (* Verify the role argument matches *)
            let actual_role = match role_expr with
              | Ast.ECon (n, [], _) -> Some n.txt
              | Ast.EVar n           -> Some n.txt
              | Ast.EAtom (s, [], _) -> Some s
              | Ast.ELit (Ast.LitAtom s, _) -> Some s
              | _ -> None
            in
            (match actual_role with
             | None ->
               Err.error env.errors ~span:sp
                 "MPST.send: second argument must be a role name (e.g. Server).";
               TError
             | Some ar when ar <> target_role ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf
                    "MPST.send: channel expects to send to `%s` but you said `%s`."
                    target_role ar);
               TError
             | _ ->
               check_expr env val_expr payload_ty
                 ~reason:(Some (RBuiltin "Payload type of MPST.send"));
               TLin (Ast.Linear, TChan (ref cont)))
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "MPST.send: channel is at `%s` but I expected `MSend(Role, T, ...)`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "MPST.send: expected a multi-party channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    | Ast.EApp (Ast.EVar { txt = "MPST.recv"; _ }, [ch_expr; role_expr], sp) ->
      (* MPST.recv(ch, Source) — ch must be at SMRecv(Source, T, S).
         The role can be written as a bare uppercase name or atom.
         Returns (value, new_chan). *)
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SMRecv (source_role, payload_ty, cont) ->
            let actual_role = match role_expr with
              | Ast.ECon (n, [], _) -> Some n.txt
              | Ast.EVar n           -> Some n.txt
              | Ast.EAtom (s, [], _) -> Some s
              | Ast.ELit (Ast.LitAtom s, _) -> Some s
              | _ -> None
            in
            (match actual_role with
             | None ->
               Err.error env.errors ~span:sp
                 "MPST.recv: second argument must be a role name (e.g. Client).";
               TError
             | Some ar when ar <> source_role ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf
                    "MPST.recv: channel expects to receive from `%s` but you said `%s`."
                    source_role ar);
               TError
             | _ ->
               TTuple [payload_ty; TLin (Ast.Linear, TChan (ref cont))])
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "MPST.recv: channel is at `%s` but I expected `MRecv(Role, T, ...)`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "MPST.recv: expected a multi-party channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    | Ast.EApp (Ast.EVar { txt = "MPST.close"; _ }, [ch_expr], sp) ->
      (* MPST.close(ch) — ch must be at SEnd. *)
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SEnd -> t_unit
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "MPST.close: channel is at `%s` but the session must be complete \
                  (End) before closing."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "MPST.close: expected a multi-party channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    | Ast.EApp (f, args, sp) ->
      let f_ty = infer_expr env f in
      infer_app env sp f_ty args 0

    (* ── Constructor application ──────────────────────────────────── *)
    | Ast.ECon (name, args, sp) ->
      (match lookup_ctor name.txt env with
       | None ->
         let candidates = suggest_ctors name.txt env in
         let hint =
           if candidates = [] then
             "Is this a typo, or did you forget to declare the type?"
           else
             let lines = List.map (fun (k, ty) ->
                 Printf.sprintf "  • `%s` — from type `%s`" k ty
               ) candidates in
             "Did you mean one of:\n" ^ String.concat "\n" lines
         in
         Err.error env.errors ~span:name.span
           (Printf.sprintf "I don't know a constructor called `%s`.\n%s"
              name.txt hint);
         List.iter (fun a -> ignore (infer_expr env a)) args;
         TError
       | Some ci ->
         (* Warn if a bare constructor name is ambiguous across multiple types.
            Qualified names (containing '.') are already disambiguated — skip. *)
         (if not (String.contains name.txt '.') then begin
           let all_types = all_ctors_named name.txt env in
           if List.length all_types > 1 then
             Err.hint env.errors ~span:name.span
               (Printf.sprintf
                  "Constructor `%s` is defined by multiple types (%s). \
                   Use a qualified form to disambiguate, e.g. `%s.%s`."
                  name.txt
                  (String.concat ", " all_types)
                  (List.hd all_types)
                  name.txt)
         end);
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
    | Ast.ELam (params, body, lsp) ->
      (* Snapshot which outer linear vars are unused before entering the lambda.
         Any that become used during body checking were captured by the closure.
         Capturing a linear value in a closure is unsound because the closure
         could be called multiple times, violating the exactly-once guarantee. *)
      let outer_lin_snapshot =
        List.map (fun le -> (le.le_name, !(le.le_used))) env.lin
      in
      let param_tys, env' = bind_lam_params env params in
      let body_ty = infer_expr env' body in
      (* Detect captures: outer linear vars that were unused before but used now. *)
      List.iter (fun le ->
          let was_used_before =
            match List.assoc_opt le.le_name outer_lin_snapshot with
            | Some b -> b
            | None   -> true  (* not in snapshot = lambda's own param, skip *)
          in
          if not was_used_before && !(le.le_used)
          && le.le_lin <> Ast.Unrestricted then
            Err.error env.errors ~span:lsp
              (Printf.sprintf
                 "The linear value `%s` cannot be captured by a closure.\n\
                  A closure may be called multiple times, which would violate \
                  the exactly-once guarantee.\n\
                  Pass `%s` as a parameter to the closure instead."
                 le.le_name le.le_name)
        ) env.lin;
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
      infer_match env sp scrut scrut_ty branches

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
      (* Module member access: if e is a module path (ECon or chained EField),
         try looking up "A.B.name" in env.vars before falling back to record field. *)
      let rec module_path = function
        | Ast.ECon (n, [], _) -> Some n.txt
        | Ast.EField (e2, f, _) ->
          (match module_path e2 with
           | Some prefix -> Some (prefix ^ "." ^ f.txt)
           | None -> None)
        | _ -> None
      in
      let mod_access =
        match module_path e with
        | Some prefix ->
          let qualified = prefix ^ "." ^ name.txt in
          (match lookup_var qualified env with
           | Some sch -> Some (instantiate env.level env sch)
           | None     -> None)
        | None -> None
      in
      (match mod_access with
       | Some ty -> ty
       | None ->
      let e_ty = infer_expr env e in
      (match expand_record env (repr e_ty) with
       | Some (TRecord flds) ->
         (match List.assoc_opt name.txt flds with
          | Some t ->
            (* If the field type is linear/affine, accessing it consumes the
               field.  When the record is held in a named variable, a second
               access on the same variable is caught by [record_use].
               For non-variable expressions we emit a diagnostic here. *)
            (match repr t with
             | TLin (lin, _) when lin <> Ast.Unrestricted ->
               (match e with
                | Ast.EVar vname ->
                  (* Record is held in a named variable: check per-field sentinel.
                     Sentinel "varname#fieldname" was registered by bind_lam_param /
                     bind_pattern_bindings when the variable was bound.  If it
                     exists, record_use will catch a second access; if it doesn't
                     (e.g., variable is outer-scope), fall back to checking the
                     whole-record linear entry via record_use on the variable itself. *)
                  let sentinel = vname.txt ^ "#" ^ name.txt in
                  if List.exists (fun le -> le.le_name = sentinel) env.lin then
                    record_use sentinel sp env
                  else begin
                    (* Sentinel not present — warn that we can't track this field. *)
                    ignore lin;
                    Err.warning env.errors ~span:sp
                      (Printf.sprintf
                         "Field `%s` has a linear type but linearity tracking \
                          is not available for `%s` at this binding site.\n\
                          Ensure `%s` is a locally-bound variable."
                         name.txt vname.txt vname.txt)
                  end
                | _ ->
                  Err.error env.errors ~span:sp
                    (Printf.sprintf
                       "Field `%s` has a linear type; accessing it through \
                        a complex expression loses linearity tracking.\n\
                        Bind the record to a variable first."
                       name.txt))
             | _ -> ());
            t
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

    (* ── Test assertion ─────────────────────────────────────────────── *)
    | Ast.EAssert (inner, sp) ->
      (* The inner expression must be Bool. Assert evaluates to Unit. *)
      check_expr env inner t_bool ~reason:(Some (RBuiltin "assert expects a Bool expression"));
      Hashtbl.replace env.type_map sp t_unit;
      t_unit

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
        (* Propagate linearity from scrutinee to pattern-bound variables. *)
        let env' = bind_pattern_bindings scrut bindings env in
        (match br.branch_guard with
         | Some g ->
           check_expr env' g t_bool
             ~reason:(Some (RBuiltin "Match guards must be Bool."))
         | None -> ());
        check_expr env' br.branch_body expected ~reason
      ) branches;
    check_exhaustiveness env msp scrut_ty branches

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
and infer_match env span scrut scrut_ty branches =
  let result_ty = fresh_var env.level in
  List.iter (fun (br : Ast.branch) ->
      let bindings, pat_ty = infer_pattern env br.branch_pat in
      unify env ~span ~reason:(Some (RMatchArm span)) scrut_ty pat_ty;
      (* Propagate linearity from scrutinee to pattern-bound variables. *)
      let env' = bind_pattern_bindings scrut bindings env in
      (match br.branch_guard with
       | Some g ->
         check_expr env' g t_bool
           ~reason:(Some (RBuiltin "Match guards must be Bool."))
       | None -> ());
      check_expr env' br.branch_body result_ty
        ~reason:(Some (RMatchArm span))
    ) branches;
  check_exhaustiveness env span scrut_ty branches;
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
    (* Propagate linearity: if bind_lin is Linear/Affine (written as
       `linear let x = ...` or `affine let x = ...`), override the
       normal binding and register the variable as linear/affine.
       Otherwise, propagate linearity from the RHS expression type. *)
    let env' = match b.bind_lin with
      | Ast.Unrestricted ->
        bind_pattern_bindings b.bind_expr bindings' env
      | lin ->
        (* Explicit linearity annotation on the binding: register each
           pattern variable as linear/affine. *)
        List.fold_left (fun acc_env (name, sch) ->
            match sch with
            | Mono t -> bind_linear name lin t acc_env
            | _      -> bind_var name sch acc_env
          ) env bindings'
    in
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
  | Ast.Unrestricted ->
    let env1 = bind_var p.param_name.txt (Mono t) env in
    bind_linear_field_sentinels p.param_name.txt t env1
  | lin -> bind_linear p.param_name.txt lin t env

(* =================================================================
   §15  Declaration checking
   ================================================================= *)

(** Collect all free variable names referenced in [e].
    Only [EVar] nodes with no dot (non-qualified names) are collected.
    Re-bindings introduced by [ELet]/[EMatch]/[ELam] are accounted for so
    we never report a variable that is shadowed by an inner binding. *)
let rec free_vars_expr (bound : string list) (e : Ast.expr) : string list =
  match e with
  | Ast.EVar n ->
    if List.mem n.txt bound || String.contains n.txt '.' then [] else [n.txt]
  | Ast.ELit _ | Ast.EHole _ | Ast.EResultRef _ | Ast.EDbg (None, _) -> []
  | Ast.EDbg (Some inner, _) -> free_vars_expr bound inner
  | Ast.EApp (f, args, _) ->
    free_vars_expr bound f @ List.concat_map (free_vars_expr bound) args
  | Ast.ECon (_, args, _) -> List.concat_map (free_vars_expr bound) args
  | Ast.ELam (ps, body, _) ->
    let inner_bound = List.filter_map (fun (p : Ast.param) ->
        Some p.param_name.txt) ps @ bound in
    free_vars_expr inner_bound body
  | Ast.EBlock (es, _) -> free_vars_block bound es
  | Ast.ELet (b, _) -> free_vars_expr bound b.Ast.bind_expr
  | Ast.EMatch (scrut, branches, _) ->
    free_vars_expr bound scrut @
    List.concat_map (fun br ->
      let pat_bound = free_vars_pattern br.Ast.branch_pat in
      let inner = pat_bound @ bound in
      Option.fold ~none:[] ~some:(free_vars_expr inner) br.Ast.branch_guard @
      free_vars_expr inner br.Ast.branch_body
    ) branches
  | Ast.ETuple (es, _) -> List.concat_map (free_vars_expr bound) es
  | Ast.ERecord (fields, _) ->
    List.concat_map (fun (_, ex) -> free_vars_expr bound ex) fields
  | Ast.ERecordUpdate (base, fields, _) ->
    free_vars_expr bound base @
    List.concat_map (fun (_, ex) -> free_vars_expr bound ex) fields
  | Ast.EField (ex, _, _) -> free_vars_expr bound ex
  | Ast.EIf (c, t, f, _) ->
    free_vars_expr bound c @ free_vars_expr bound t @ free_vars_expr bound f
  | Ast.EAnnot (ex, _, _) -> free_vars_expr bound ex
  | Ast.EAtom (_, args, _) -> List.concat_map (free_vars_expr bound) args
  | Ast.ESend (a, b, _) ->
    free_vars_expr bound a @ free_vars_expr bound b
  | Ast.ESpawn (e, _) -> free_vars_expr bound e
  | Ast.ELetFn (name, params, _, body, _) ->
    let inner_bound = name.txt :: List.map (fun p -> p.Ast.param_name.txt) params @ bound in
    free_vars_expr inner_bound body
  | Ast.EPipe (l, r, _) ->
    free_vars_expr bound l @ free_vars_expr bound r
  | Ast.EAssert (e, _) -> free_vars_expr bound e

and free_vars_block (bound : string list) (es : Ast.expr list) : string list =
  match es with
  | [] -> []
  | Ast.ELet (b, _) :: rest ->
    let used_in_rhs = free_vars_expr bound b.Ast.bind_expr in
    let pat_bound = free_vars_pattern b.Ast.bind_pat in
    used_in_rhs @ free_vars_block (pat_bound @ bound) rest
  | e :: rest ->
    free_vars_expr bound e @ free_vars_block bound rest

and free_vars_pattern (p : Ast.pattern) : string list =
  match p with
  | Ast.PatVar n -> [n.txt]
  | Ast.PatWild _ -> []
  | Ast.PatLit _ -> []
  | Ast.PatCon (_, ps) -> List.concat_map free_vars_pattern ps
  | Ast.PatTuple (ps, _) -> List.concat_map free_vars_pattern ps
  | Ast.PatRecord (fields, _) -> List.concat_map (fun (_, p) -> free_vars_pattern p) fields
  | Ast.PatAs (p, n, _) -> n.txt :: free_vars_pattern p
  | Ast.PatAtom (_, ps, _) -> List.concat_map free_vars_pattern ps

(** Emit unused-variable warnings for fn params not referenced in the body.
    The wildcard [_] and names starting with [_] are silently ignored. *)
let warn_unused_params env (params : Ast.fn_param list) (body : Ast.expr) _fn_span =
  let used = free_vars_expr [] body in
  let check_name name span =
    if name <> "_" && not (String.length name > 0 && name.[0] = '_')
       && not (List.mem name used) then
      Err.warning_with_code env.errors ~span ~code:"unused_binding"
        (Printf.sprintf "Unused variable `%s`.\n\
                         Use `_` to mark intentionally unused params." name)
  in
  List.iter (fun fp ->
    match fp with
    | Ast.FPNamed p -> check_name p.param_name.txt p.param_name.span
    | Ast.FPPat (Ast.PatVar n) -> check_name n.txt n.span
    | Ast.FPPat _ -> ()
  ) params

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
      (* Shared type variable mapping for this function's signature.
         Using a single ref across all param annotations, return type, and
         class constraints ensures that the same type variable name (e.g. `a`)
         in `fn foo(x : a, y : a) : a when Eq(a)` maps to the same
         unification variable everywhere. *)
      let fn_tvars = ref [] in

      (* Bind parameters *)
      let param_tys, body_env =
        List.fold_right (fun fp (tys, env) ->
            match fp with
            | Ast.FPNamed p ->
              let t = match p.param_ty with
                | Some ann -> surface_ty env' ~tvars:fn_tvars ann
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

      (* Process the when-clause: distinguish class constraints from guards.
         A class constraint looks like `ECon("Eq", [EVar "a"])` where "Eq"
         is a known interface name.  Such guards are treated as type-class
         constraints added to the function scheme rather than checked as Bool
         expressions. *)
      let class_constraints =
        match clause.fc_guard with
        | None -> []
        | Some (Ast.ECon (iface_name, args, _))
          when List.assoc_opt iface_name.txt env.interfaces <> None ->
          (* It's a class constraint: Eq(a), Ord(b), etc. *)
          List.filter_map (fun arg ->
              match arg with
              | Ast.EVar v ->
                let ty = match List.assoc_opt v.txt !fn_tvars with
                  | Some t -> t
                  | None   ->
                    (* Type var not yet in fn_tvars (e.g. declared only in constraint).
                       Create a fresh var and register it. *)
                    let fv = fresh_var env'.level in
                    fn_tvars := (v.txt, fv) :: !fn_tvars;
                    fv
                in
                Some (CInterface (iface_name.txt, ty))
              | _ -> None
            ) args
        | Some g ->
          (* Normal expression guard: type-check it as Bool *)
          check_expr body_env g t_bool
            ~reason:(Some (RBuiltin "Function guards must be Bool."));
          []
      in

      (* Check or infer the body, sharing fn_tvars with the return annotation *)
      let body_ty = match def.fn_ret_ty with
        | Some ann ->
          let expected = surface_ty env' ~tvars:fn_tvars ann in
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

      (* Warn about unrestricted params not referenced in the body *)
      warn_unused_params env clause.fc_params clause.fc_body fn_span;

      let fn_ty =
        List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys body_ty
      in
      (* Record the function's overall type at the function name's span *)
      Hashtbl.replace env.type_map def.fn_name.span (repr fn_ty);
      (* Unify self_ty so recursive calls get the correct type *)
      unify env' ~span:fn_span self_ty fn_ty;

      (* Generalize; attach any class constraints from the when-clause *)
      let base_sch = generalize env.level fn_ty in
      (match class_constraints with
       | [] -> base_sch
       | cs  ->
         match base_sch with
         | Poly (ids, existing_cs, t) -> Poly (ids, cs @ existing_cs, t)
         | Mono t ->
           (* Collect the ids of all quantified vars referenced in constraints *)
           let extra_ids = List.filter_map (fun c ->
               match c with
               | CInterface (_, tv) ->
                 (match repr tv with
                  | TVar r ->
                    (match !r with
                     | Unbound (id, l) when l > env.level -> Some id
                     | _ -> None)
                  | _ -> None)
               | _ -> None
             ) cs in
           Poly (extra_ids, cs, t))

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

(** [impl_matches_ty impl_ty target_ty] returns true if [target_ty] could be
    satisfied by an implementation typed as [impl_ty].  Free unification
    variables in [impl_ty] (from parameterised impls like [List(a)]) are
    treated as wildcards that match any type. *)
let rec impl_matches_ty impl_ty target_ty =
  match repr impl_ty, repr target_ty with
  | TVar _, _ -> true  (* polymorphic impl var — matches anything *)
  | _, TVar _ -> false (* target still unresolved — cannot confirm *)
  | TCon (n1, as1), TCon (n2, as2)
    when n1 = n2 && List.length as1 = List.length as2 ->
    List.for_all2 impl_matches_ty as1 as2
  | TArrow (a1, b1), TArrow (a2, b2) ->
    impl_matches_ty a1 a2 && impl_matches_ty b1 b2
  | TTuple ts1, TTuple ts2 when List.length ts1 = List.length ts2 ->
    List.for_all2 impl_matches_ty ts1 ts2
  | TRecord f1, TRecord f2
    when List.map fst f1 = List.map fst f2 ->
    List.for_all2 (fun (_, t1) (_, t2) -> impl_matches_ty t1 t2) f1 f2
  | TLin (_, t1), TLin (_, t2) -> impl_matches_ty t1 t2
  | TError, _ | _, TError -> true
  | a, b -> a = b

(** Discharge all pending Num/Ord/CInterface constraints accumulated during
    inference.  Called at each declaration boundary (DFn, DLet) to verify
    that constrained type variables were unified with a compatible type. *)
let discharge_constraints env span =
  List.iter (fun c ->
      match c with
      | CNum t | COrd t ->
        let ty   = repr t in
        let kind = match c with CNum _ -> "Num" | COrd _ -> "Ord" | _ -> assert false in
        (match ty with
         | TCon ("Int",   []) | TCon ("Float", []) -> ()   (* Num + Ord *)
         | TCon ("String",[]) ->
           (match c with
            | COrd _ -> ()   (* String is Ord *)
            | _ ->
              Err.error env.errors ~span
                "String does not implement Num (only Int and Float do).")
         | TVar _ -> ()   (* Unresolved — will be polymorphic, constraint preserved *)
         | _ ->
           Err.error env.errors ~span
             (Printf.sprintf "`%s` does not implement %s." (pp_ty ty) kind))
      | CInterface (iface_name, t) ->
        let ty = repr t in
        (match ty with
         | TVar _ -> ()   (* Still polymorphic — cannot check yet *)
         | _ ->
           let satisfied = List.exists (fun (iname, impl_ty) ->
               iname = iface_name && impl_matches_ty (repr impl_ty) ty
             ) env.impls in
           if not satisfied then
             Err.error env.errors ~span
               (Printf.sprintf
                  "`%s` does not implement interface `%s`.\n\
                   Add `impl %s(%s) do ... end` to provide an implementation."
                  (pp_ty ty) iface_name iface_name (pp_ty ty)))
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
    (* H9 gap fix: also check actor handler signatures for Cap usage.
       Actor handlers can receive Cap(X) values as message arguments; those
       must also be covered by module-level [needs] declarations. *)
    | Ast.DActor (_, _, actor, sp) ->
      List.concat_map (fun (h : Ast.actor_handler) ->
          let param_tys = List.filter_map (fun (p : Ast.param) -> p.param_ty) h.ah_params in
          List.concat_map (fun t ->
            List.map (fun cap -> (cap, sp)) (cap_paths_in_surface_ty t)
          ) param_tys
        ) actor.actor_handlers
    | _ -> []
  ) decls in
  let cap s = MPCode ("Cap(" ^ s ^ ")") in
  (* Check 1: every Cap(X) must be covered by a declared need *)
  List.iter (fun (cap_path, sp) ->
    let covered = List.exists (fun need -> cap_subsumes need cap_path) declared_needs in
    if not covered then
      Err.error env.errors ~span:sp
        (render_parts [
          cap cap_path; MPText " used in module "; MPCode mod_name.txt;
          MPText " but "; MPCode cap_path; MPText " is not declared in ";
          MPCode "needs"; MPText ".";
          MPBreak; MPText "help: add "; MPCode ("needs " ^ cap_path);
          MPText " to the module body." ])
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
        (render_parts [
          MPText "module "; MPCode mod_name.txt; MPText " declares ";
          MPCode ("needs " ^ need); MPText " but no function requires ";
          cap need; MPText " or a sub-capability.";
          MPBreak; MPText "help: remove the unused capability declaration." ])
  ) declared_needs;
  (* Check 3 (hint): Cap(IO) root — suggest narrowing *)
  List.iter (fun (cap_path, sp) ->
    if cap_path = "IO" then
      Err.hint env.errors ~span:sp
        (render_parts [
          MPText "this function takes "; cap "IO";
          MPText " (the root capability); consider narrowing to e.g. ";
          cap "IO.FileRead"; MPText " or "; cap "IO.Console";
          MPText " for least-privilege." ])
  ) used_caps;
  (* Check 4: transitive — every module we `use` that declares `needs` must be covered *)
  List.iter (function
    | Ast.DUse (ud, sp) ->
      let imported = String.concat "." (List.map (fun n -> n.Ast.txt) ud.use_path) in
      (match List.assoc_opt imported env.module_caps with
       | None | Some [] -> ()
       | Some req_caps ->
         List.iter (fun req_cap ->
           let covered =
             List.exists (fun need -> cap_subsumes need req_cap) declared_needs
           in
           if not covered then
             Err.error env.errors ~span:sp
               (render_parts [
                 MPText "module "; MPCode mod_name.txt; MPText " imports ";
                 MPCode imported; MPText " which requires "; cap req_cap;
                 MPText ", but "; MPCode req_cap; MPText " is not declared in ";
                 MPCode "needs"; MPText ".";
                 MPBreak; MPText "help: add "; MPCode ("needs " ^ req_cap);
                 MPText " to the module body." ])
         ) req_caps)
    | _ -> ()
  ) decls;
  (* Check 5: extern blocks require the declared capability to be in `needs` *)
  List.iter (function
    | Ast.DExtern (edef, sp) ->
      let cap_paths = cap_paths_in_surface_ty edef.ext_cap_ty in
      List.iter (fun cap_path ->
        let covered =
          List.exists (fun need -> cap_subsumes need cap_path) declared_needs
        in
        if not covered then
          Err.error env.errors ~span:sp
            (render_parts [
              MPText "extern block "; MPCode ("\"" ^ edef.ext_lib_name ^ "\"");
              MPText " uses "; cap cap_path;
              MPText ", but "; MPCode cap_path; MPText " is not declared in ";
              MPCode "needs"; MPText ".";
              MPBreak; MPText "help: add "; MPCode ("needs " ^ cap_path);
              MPText " to the module body." ])
      ) cap_paths
    | _ -> ()
  ) decls

(* =================================================================
   §16a  Session type projection and duality
   ================================================================= *)

(** [project_steps env ~proto_name ~multiparty steps role cont] projects a
    list of protocol steps onto [role], appending [cont] as the continuation.
    When [multiparty] is true (N>2 roles), produces [SMSend]/[SMRecv] with
    explicit role annotations; otherwise produces [SSend]/[SRecv]. *)
let rec project_steps env ~proto_name ~multiparty steps role cont =
  match steps with
  | [] -> cont
  | step :: rest ->
    let rest_ty () = project_steps env ~proto_name ~multiparty rest role cont in
    (match step with
     | Ast.ProtoMsg (sender, receiver, msg_ty) ->
       let tvars = ref [] in
       let t = surface_ty env ~tvars msg_ty in
       if sender.Ast.txt = role then
         (if multiparty then SMSend (receiver.Ast.txt, t, rest_ty ())
          else SSend (t, rest_ty ()))
       else if receiver.Ast.txt = role then
         (if multiparty then SMRecv (sender.Ast.txt, t, rest_ty ())
          else SRecv (t, rest_ty ()))
       else
         rest_ty ()   (* This role doesn't participate in this step *)
     | Ast.ProtoLoop inner_steps ->
       (* Wrap the inner projection in a recursive binder *)
       let rec_var = proto_name ^ "_loop" in
       let inner = project_steps env ~proto_name ~multiparty inner_steps role (SVar rec_var) in
       let after_loop = rest_ty () in
       (match inner with
        | SVar _ ->
          (* Role not involved in the loop at all — skip *)
          after_loop
        | _ ->
          (* Substitute the continuation into the SVar back-reference *)
          let inner_with_cont = subst_svar rec_var after_loop inner in
          SRec (rec_var, inner_with_cont))
     | Ast.ProtoChoice (chooser, branches) ->
       let branch_tys = List.map (fun (lbl, arm_steps) ->
           let arm_ty = project_steps env ~proto_name ~multiparty arm_steps role cont in
           (lbl.Ast.txt, arm_ty)
         ) branches in
       if chooser.Ast.txt = role then
         SChoose branch_tys
       else begin
         (* Mergeability: if all branches project to the same local type for
            this role, merge them into that type (the role need not observe
            the choice at all).  This is the standard MPST merge rule. *)
         match branch_tys with
         | [] -> SOffer branch_tys
         | (_, first_ty) :: rest ->
           if List.for_all (fun (_, ty) -> session_ty_exact_equal ty first_ty) rest then
             first_ty   (* role not involved — merged/transparent *)
           else
             SOffer branch_tys
       end)

(** Substitute occurrences of [SVar x] with [replacement] inside [s]. *)
and subst_svar x replacement s =
  match s with
  | SVar y when y = x -> replacement
  | SSend (t, s')  -> SSend (t, subst_svar x replacement s')
  | SRecv (t, s')  -> SRecv (t, subst_svar x replacement s')
  | SChoose bs     -> SChoose (List.map (fun (l, s') -> (l, subst_svar x replacement s')) bs)
  | SOffer bs      -> SOffer  (List.map (fun (l, s') -> (l, subst_svar x replacement s')) bs)
  | SMSend (r, t, s') -> SMSend (r, t, subst_svar x replacement s')
  | SMRecv (r, t, s') -> SMRecv (r, t, subst_svar x replacement s')
  | SRec (y, s') when y <> x -> SRec (y, subst_svar x replacement s')
  | other -> other

(** Compute the dual of a local session type (what the other endpoint must have).
    Only meaningful for binary protocols; MPST types use SMSend/SMRecv directly. *)
let rec dual_session_ty = function
  | SSend (t, s)  -> SRecv (t, dual_session_ty s)
  | SRecv (t, s)  -> SSend (t, dual_session_ty s)
  | SChoose bs    -> SOffer  (List.map (fun (l, s) -> (l, dual_session_ty s)) bs)
  | SOffer  bs    -> SChoose (List.map (fun (l, s) -> (l, dual_session_ty s)) bs)
  | SEnd          -> SEnd
  | SRec (x, s)   -> SRec (x, dual_session_ty s)
  | SVar x        -> SVar x
  | SError        -> SError
  | SMSend (r, t, s) -> SMSend (r, t, dual_session_ty s)
  | SMRecv (r, t, s) -> SMRecv (r, t, dual_session_ty s)

(** Project a global protocol onto all participating roles.
    Returns [(role, local_ty) list].
    - Binary (2 roles): verifies duality of the two projections.
    - Multiparty (N>2 roles): verifies pairwise send/recv consistency using
      role-annotated SMSend/SMRecv constructors. *)
let project_protocol env ~span ~proto_name (pdef : Ast.protocol_def) =
  (* Collect all roles *)
  let rec roles_of_steps = function
    | [] -> []
    | Ast.ProtoMsg (s, r, _) :: rest ->
      s.Ast.txt :: r.Ast.txt :: roles_of_steps rest
    | Ast.ProtoLoop steps :: rest ->
      roles_of_steps steps @ roles_of_steps rest
    | Ast.ProtoChoice (chooser, branches) :: rest ->
      chooser.Ast.txt ::
      List.concat_map (fun (_, steps) -> roles_of_steps steps) branches @
      roles_of_steps rest
  in
  let roles = List.sort_uniq String.compare (roles_of_steps pdef.proto_steps) in
  let multiparty = List.length roles > 2 in
  (* Project each role *)
  let projections = List.map (fun role ->
      let ty = project_steps env ~proto_name ~multiparty pdef.proto_steps role SEnd in
      (role, ty)
    ) roles in
  (match roles with
   | [a; b] ->
     (* Binary protocol: verify duality *)
     let proj_a = List.assoc a projections in
     let proj_b = List.assoc b projections in
     let dual_a = dual_session_ty proj_a in
     if not (session_ty_equal dual_a proj_b) then
       Err.error env.errors ~span
         (Printf.sprintf
            "Protocol `%s`: the projection onto `%s` and the projection onto \
             `%s` are not duals of each other.\n\
             dual(%s) = %s\nbut %s has: %s"
            proto_name a b
            a (pp_session_ty dual_a)
            b (pp_session_ty proj_b))
   | _ when multiparty ->
     (* Multiparty protocol: verify that every SMSend in role A to role B
        corresponds to an SMRecv in role B from role A with the same type.
        We check this by collecting all (sender, receiver, msg_ty) triples
        from the global steps and comparing against the projections. *)
     let rec gather_msgs acc = function
       | [] -> acc
       | Ast.ProtoMsg (s, r, t) :: rest ->
         let tvars = ref [] in
         let ty = surface_ty env ~tvars t in
         gather_msgs ((s.Ast.txt, r.Ast.txt, ty) :: acc) rest
       | Ast.ProtoLoop inner :: rest ->
         gather_msgs (gather_msgs acc inner) rest
       | Ast.ProtoChoice (_, branches) :: rest ->
         let branch_msgs = List.concat_map (fun (_, steps) ->
             gather_msgs [] steps) branches in
         gather_msgs (branch_msgs @ acc) rest
     in
     let msgs = gather_msgs [] pdef.proto_steps in
     List.iter (fun (sender, receiver, msg_ty) ->
         (* Check sender has SMSend(receiver, msg_ty, ...) somewhere *)
         let rec has_msend s =
           match unfold_srec s with
           | SMSend (r, t, cont) ->
             (r = receiver && session_ty_equal (SSend (t, SEnd)) (SSend (msg_ty, SEnd)))
             || has_msend cont
           | SMRecv (_, _, cont) -> has_msend cont
           | SChoose bs | SOffer bs ->
             List.exists (fun (_, s') -> has_msend s') bs
           | SRec (_, s') -> has_msend s'
           | _ -> false
         in
         let rec has_mrecv s =
           match unfold_srec s with
           | SMRecv (r, t, cont) ->
             (r = sender && session_ty_equal (SSend (t, SEnd)) (SSend (msg_ty, SEnd)))
             || has_mrecv cont
           | SMSend (_, _, cont) -> has_mrecv cont
           | SChoose bs | SOffer bs ->
             List.exists (fun (_, s') -> has_mrecv s') bs
           | SRec (_, s') -> has_mrecv s'
           | _ -> false
         in
         (match List.assoc_opt sender projections with
          | Some proj when not (has_msend proj) ->
            Err.error env.errors ~span
              (Printf.sprintf
                 "Protocol `%s`: role `%s` should send to `%s` but \
                  its projected type does not include MSend(%s, ...)."
                 proto_name sender receiver receiver)
          | _ -> ());
         (match List.assoc_opt receiver projections with
          | Some proj when not (has_mrecv proj) ->
            Err.error env.errors ~span
              (Printf.sprintf
                 "Protocol `%s`: role `%s` should receive from `%s` but \
                  its projected type does not include MRecv(%s, ...)."
                 proto_name receiver sender sender)
          | _ -> ())
       ) msgs
   | _ -> ());  (* 0 or 1 role: already warned in caller *)
  projections

let rec check_decl env (d : Ast.decl) : env =
  match d with
  | Ast.DFn (def, sp) ->
    let sch = check_fn env def sp in
    discharge_constraints env sp;
    bind_var def.fn_name.txt sch env

  | Ast.DLet (_vis, b, sp) ->
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

  | Ast.DType (_vis, name, params, typedef, _sp) ->
    let env1 = { env with types = (name.txt, List.length params) :: env.types } in
    (match typedef with
     | Ast.TDVariant variants ->
       let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
       List.fold_left (fun e (v : Ast.variant) ->
           let ci = { ci_type    = name.txt
                    ; ci_params  = param_names
                    ; ci_arg_tys = v.var_args
                    ; ci_vis     = v.var_vis } in
           (* Register both bare "CtorName" and qualified "TypeName.CtorName"
              so users can write either form for disambiguation. *)
           let qual_key = name.txt ^ "." ^ v.var_name.txt in
           { e with ctors = (qual_key, ci) :: (v.var_name.txt, ci) :: e.ctors }
         ) env1 variants
     | Ast.TDRecord fields ->
       let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
       (* Propagate field-level linearity annotations into the surface type so
          that expand_record returns TLin wrappers for linear fields.  This
          enables both the EField check and let-binding linearity propagation
          (bind_vars_with_linearity) to see the linear field constraint. *)
       let field_pairs = List.map (fun (f : Ast.field) ->
           let fty = match f.fld_lin with
             | Ast.Unrestricted -> f.fld_ty
             | lin -> Ast.TyLinear (lin, f.fld_ty)
           in
           (f.fld_name.txt, fty)
         ) fields in
       { env1 with records = (name.txt, (param_names, field_pairs)) :: env1.records }
     | Ast.TDAlias _ -> env1)

  | Ast.DActor (_vis, name, actor, _sp) ->
    (* Build the state record type from field declarations *)
    let state_ty =
      let tvars = ref [] in
      let flds = List.map (fun (f : Ast.field) ->
          (f.fld_name.txt, surface_ty env ~tvars f.fld_ty)) actor.actor_state in
      TRecord (List.sort (fun (a,_)(b,_) -> String.compare a b) flds)
    in
    (* Check for duplicate handler names — two `on Msg(...)` arms for the
       same message name is always a programmer error. *)
    let _ = List.fold_left (fun seen (h : Ast.actor_handler) ->
        if List.mem h.ah_msg.txt seen then
          Err.error env.errors ~span:h.ah_msg.span
            (Printf.sprintf
               "actor '%s' defines handler '%s' more than once;\
                \nremove the duplicate or rename one of them"
               name.txt h.ah_msg.txt);
        h.ah_msg.txt :: seen
      ) [] actor.actor_handlers in
    (* Register actor name as a zero-arg constructor (so spawn(ActorName) typechecks)
       and message constructors so ECon lookups succeed.
       Include ALL params — annotated and unannotated — so constructor arity
       is always correct.  Unannotated params are given a unique TyVar placeholder
       (named "$p<i>_<Msg>") that resolves to a fresh unification variable during
       instantiation; this ensures `send(pid, Msg(x))` typechecks correctly even
       when the handler omits a type annotation. *)
    let env_with_actor_ctor = { env with ctors =
      (name.txt, { ci_type = name.txt; ci_params = []; ci_arg_tys = []; ci_vis = Ast.Public })
      :: env.ctors } in
    let env_with_ctors = List.fold_left (fun acc_env (h : Ast.actor_handler) ->
        let arg_tys = List.mapi (fun i (p : Ast.param) ->
            match p.param_ty with
            | Some ty -> ty
            | None ->
              (* Unique name per (handler, position) so each instantiation
                 gets an independent fresh variable. *)
              Ast.TyVar { txt = Printf.sprintf "$p%d_%s" i h.ah_msg.txt;
                          span = p.param_name.span }
          ) h.ah_params in
        let ci = { ci_type = name.txt ^ "_Msg"; ci_params = [];
                   ci_arg_tys = arg_tys; ci_vis = Ast.Public } in
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
              notes = actor_handler_hints (repr state_ty) (repr inferred);
              code = None }
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
    (* Collect the names that are explicitly public within this module. *)
    let pub_set =
      List.filter_map (function
        | Ast.DFn (def, _) when def.fn_vis = Ast.Public -> Some def.fn_name.txt
        | Ast.DFn _ -> None
        | Ast.DLet (Ast.Public, b, _) ->
          (match b.bind_pat with Ast.PatVar n -> Some n.txt | _ -> None)
        | Ast.DLet _ -> None
        | Ast.DType (Ast.Public, n, _, _, _) -> Some n.txt
        | Ast.DType _ -> None
        | Ast.DActor (Ast.Public, n, _, _) -> Some n.txt
        | Ast.DActor _ -> None
        | Ast.DMod (n, Ast.Public, _, _) -> Some n.txt
        | Ast.DMod _ -> None
        | _ -> None
      ) decls
    in
    (* Check conformance against any matching sig declaration (Phase 2) *)
    let opaque_types =
      match List.assoc_opt name.txt env.sigs with
      | None -> []
      | Some sdef ->
        (* Verify all sig_fns are present with matching types *)
        List.iter (fun ((fname : Ast.name), sig_ty) ->
            match List.assoc_opt fname.txt inner_env.vars with
            | None ->
              Err.error env.errors ~span:name.span
                (Printf.sprintf
                   "Module `%s` does not implement `%s` required by `sig %s`."
                   name.txt fname.txt name.txt)
            | Some sch ->
              (* Convert sig_ty to internal type and check unification via a
                 temporary error context so we can produce a clean error message. *)
              let tvars = ref [] in
              let expected = surface_ty inner_env ~tvars sig_ty in
              let actual = instantiate env.level inner_env sch in
              let tmp_errors = Err.create () in
              let tmp_env = { inner_env with errors = tmp_errors } in
              unify tmp_env ~span:fname.span expected actual;
              if Err.has_errors tmp_errors then
                Err.error env.errors ~span:fname.span
                  (Printf.sprintf
                     "Module `%s` implements `%s` with wrong type.\n  \
                      Expected: %s  (from sig %s)\n  \
                      Got:      %s"
                     name.txt fname.txt
                     (pp_ty (repr expected)) name.txt
                     (pp_ty (repr actual)))
          ) sdef.sig_fns;
        (* Verify all sig_types are declared in the module *)
        List.iter (fun ((tname : Ast.name), _params) ->
            if not (List.mem_assoc tname.txt inner_env.types) then
              Err.error env.errors ~span:name.span
                (Printf.sprintf
                   "Module `%s` does not declare type `%s` required by `sig %s`."
                   name.txt tname.txt name.txt)
          ) sdef.sig_types;
        (* Return the list of opaque type names for constructor hiding below *)
        List.map (fun ((tname : Ast.name), _) -> tname.txt) sdef.sig_types
    in
    (* Validate capability declarations for this module *)
    check_module_needs env name decls;
    (* Expose only public names as "ModName.name" in the outer env.
       Also export sub-module keys: if "B" is in pub_set, export "B.f" as "A.B.f". *)
    let is_pub_key k =
      List.exists (fun n ->
        k = n ||
        (String.length k > String.length n + 1 &&
         String.sub k 0 (String.length n + 1) = n ^ ".")
      ) pub_set
    in
    (* Collect exported names from inner_env.vars.
       inner_env.vars may contain duplicate entries for a given key because
       the pre-binding pass added a Mono(TVar) forward-ref before check_decl
       added the real Poly scheme.  keep only the FIRST (most recently bound =
       correct) entry per exported key. *)
    let new_names_raw = List.filter_map (fun (k, sch) ->
        if is_pub_key k
        then Some (name.txt ^ "." ^ k, sch)
        else None
      ) inner_env.vars in
    let _seen_export = Hashtbl.create 16 in
    let new_names = List.filter_map (fun (k, v) ->
        if Hashtbl.mem _seen_export k then None
        else (Hashtbl.add _seen_export k (); Some (k, v))
      ) new_names_raw in
    (* Also export type names and constructors from public DMod into outer scope.
       Types defined in a module (e.g. IOList, Option) are referred to by their
       bare name throughout user code, not prefixed.
       Opaque types listed in the sig have their constructors hidden: only the
       type name is exported, not the constructors (encapsulation). *)
    let new_types = List.filter (fun (k, _) -> List.mem k pub_set) inner_env.types in
    let new_ctors = List.filter (fun (_k, ci) ->
        (* Hide constructors for opaque types declared in the sig *)
        if List.mem ci.ci_type opaque_types then false
        (* Export constructor only if its parent type is public AND
           the constructor itself is explicitly marked Public.
           This enforces opaque types: `pub type Foo = A | B` hides A and B
           until they are individually marked `pub A | pub B`. *)
        else List.mem ci.ci_type pub_set && ci.ci_vis = Ast.Public
      ) inner_env.ctors in
    (* Collect this module's declared capabilities for transitive enforcement *)
    let inner_needs = List.concat_map (function
        | Ast.DNeeds (caps, _) -> List.map cap_path_of_names caps
        | _ -> []) decls in
    (* Also export record field layouts for public record types so that
       cross-module field access (e.g. conn.fd) works correctly. *)
    let new_records = List.filter (fun (k, _) -> List.mem k pub_set) inner_env.records in
    let env' = bind_vars new_names env in
    { env' with
      types   = new_types   @ env'.types;
      ctors   = new_ctors   @ env'.ctors;
      records = new_records @ env'.records;
      module_caps = (name.txt, inner_needs) :: env'.module_caps }

  | Ast.DProtocol (name, pdef, sp) ->
    (* Register the protocol and validate structural well-formedness. *)
    if List.mem_assoc name.txt env.protocols then
      Err.error env.errors ~span:sp
        (Printf.sprintf "Duplicate protocol definition `%s`." name.txt);
    if pdef.proto_steps = [] then
      Err.warning env.errors ~span:sp
        (Printf.sprintf "Protocol `%s` has no steps — it describes no communication."
           name.txt);
    (* Validate each step for structural correctness. *)
    let rec validate_step = function
      | Ast.ProtoMsg (sender, receiver, msg_ty) ->
        if sender.txt = receiver.txt then
          Err.error env.errors ~span:sender.span
            (Printf.sprintf
               "Protocol `%s`: participant `%s` cannot send a message to itself."
               name.txt sender.txt);
        let tvars = ref [] in
        ignore (surface_ty env ~tvars msg_ty)
      | Ast.ProtoLoop steps ->
        if steps = [] then
          Err.error env.errors ~span:sp
            (Printf.sprintf "Protocol `%s`: a `loop` block must contain at least one step."
               name.txt);
        List.iter validate_step steps
      | Ast.ProtoChoice (participant, branches) ->
        if List.length branches < 2 then
          Err.error env.errors ~span:participant.span
            (Printf.sprintf
               "Protocol `%s`: `choice` by `%s` must have at least 2 branches."
               name.txt participant.txt);
        List.iter (fun (_, steps) -> List.iter validate_step steps) branches
    in
    List.iter validate_step pdef.proto_steps;
    (* Project the protocol onto each role and verify duality. *)
    let projections = project_protocol env ~span:sp ~proto_name:name.txt pdef in
    let participants = List.map fst projections in
    if participants <> [] && List.length participants < 2 then
      Err.warning env.errors ~span:sp
        (Printf.sprintf
           "Protocol `%s` only names one participant (`%s`). \
            A protocol usually involves at least two parties."
           name.txt (List.hd participants));
    (* Hint if participant names are not known actor/type names. *)
    List.iter (fun p ->
        let is_actor = List.exists (fun (_, ci) -> ci.ci_type = p) env.ctors in
        let is_type  = List.mem_assoc p env.types in
        if not (is_actor || is_type) then
          Err.hint env.errors ~span:sp
            (Printf.sprintf
               "Protocol `%s`: participant `%s` is not a known actor or type. \
                Did you forget to declare `actor %s ...`?"
               name.txt p p)
      ) participants;
    (* Check against previously-declared protocols for cross-protocol conflicts. *)
    let pi = { pi_def = pdef; pi_projections = projections; pi_span = sp } in
    let new_env = { env with protocols = (name.txt, pi) :: env.protocols } in
    (if List.length new_env.protocols > 1 then
       List.iter (fun (other_name, other_pi) ->
           if other_name <> name.txt then begin
             let other_parts = List.map fst other_pi.pi_projections in
             if List.length participants >= 2 && List.length other_parts >= 2
             && List.sort compare participants = List.sort compare other_parts then
               Err.hint env.errors ~span:sp
                 (Printf.sprintf
                    "Protocol `%s` involves the same participants as `%s`. \
                     If these are dual protocols (one for each direction), \
                     this is expected. Otherwise, consider merging them."
                    name.txt other_name)
           end
         ) env.protocols);
    new_env

  | Ast.DSig (name, sdef, _sp) ->
    (* Store the signature so DMod can check conformance later. *)
    { env with sigs = (name.txt, sdef) :: env.sigs }

  | Ast.DInterface (idef, _sp) ->
    (* Register the interface definition for impl validation, and register
       each method as a polymorphic function binding in scope.
       Methods get CInterface constraints so call sites verify the type
       satisfies the interface (discharged in discharge_constraints). *)
    let env' = { env with interfaces = (idef.iface_name.txt, idef) :: env.interfaces } in
    List.fold_left (fun env (m : Ast.method_decl) ->
        (* Use level+1 so the interface type parameter gets quantified by generalize. *)
        let a = fresh_var (env.level + 1) in
        let tvars = ref [(idef.iface_param.txt, a)] in
        let ty = surface_ty env ~tvars m.md_ty in
        let a_id = match a with
          | TVar r -> (match !r with Unbound (id, _) -> id | _ -> 0)
          | _ -> 0
        in
        (* Build scheme: ∀a. [CInterface(iface, a)] => method_ty *)
        let base_sch = generalize env.level ty in
        let sch = match base_sch with
          | Poly (ids, cs, t) ->
            Poly (ids, CInterface (idef.iface_name.txt, a) :: cs, t)
          | Mono t ->
            Poly ([a_id], [CInterface (idef.iface_name.txt, a)], t)
        in
        (* Register both unqualified (eq) and qualified (Eq.eq) names so
           that Eq.eq(x, y) resolves via the EField module-path lookup. *)
        let qualified = idef.iface_name.txt ^ "." ^ m.md_name.txt in
        let env1 = bind_var m.md_name.txt sch env in
        bind_var qualified sch env1
      ) env' idef.iface_methods

  | Ast.DImpl (idef, _sp) ->
    (* Instantiate the impl type, sharing tvars so the 'when' constraints
       can reference the same type variables as the impl type itself. *)
    let tvars = ref [] in
    let inst_ty = surface_ty env ~tvars idef.impl_ty in
    (* Register this implementation so CInterface constraints can be discharged. *)
    let env_with_impl = { env with impls = (idef.impl_iface.txt, inst_ty) :: env.impls } in
    (* Check 'when' constraints: each C(T) must already be implemented. *)
    List.iter (fun ((cname : Ast.name), ctys) ->
        match List.map (surface_ty env ~tvars) ctys with
        | [cty] ->
          let cty = repr cty in
          (match cty with
           | TVar _ -> ()   (* Polymorphic param — checked at use sites *)
           | _ ->
             if not (List.exists (fun (iname, impl_ty) ->
                 iname = cname.txt && impl_matches_ty (repr impl_ty) cty
               ) env.impls) then
               Err.error env.errors ~span:cname.span
                 (Printf.sprintf
                    "Constraint `%s(%s)` in `when` clause is not satisfied.\n\
                     No `impl %s(%s)` is in scope."
                    cname.txt (pp_ty cty) cname.txt (pp_ty cty)))
        | _ -> ()
      ) idef.impl_constraints;
    (* Validate each method against the interface declaration. *)
    (match List.assoc_opt idef.impl_iface.txt env.interfaces with
     | None ->
       Err.error env.errors ~span:idef.impl_iface.span
         (Printf.sprintf "Unknown interface `%s` — is it declared above this impl?"
            idef.impl_iface.txt)
     | Some interface ->
       (* Check superclass constraints: each required superclass must already have an impl *)
       let sc_tvars = ref [(interface.iface_param.txt, inst_ty)] in
       List.iter (fun ((sc_name : Ast.name), sc_tys) ->
           let sc_inst_tys = List.map (surface_ty env ~tvars:sc_tvars) sc_tys in
           (match sc_inst_tys with
            | [sc_inst_ty] ->
              let sc_inst_ty = repr sc_inst_ty in
              (match sc_inst_ty with
               | TVar _ -> ()  (* polymorphic param — checked at use sites *)
               | _ ->
                 if not (List.exists (fun (iname, impl_ty) ->
                     iname = sc_name.txt && impl_matches_ty (repr impl_ty) sc_inst_ty
                   ) env.impls) then
                   Err.error env.errors ~span:idef.impl_iface.span
                     (Printf.sprintf
                        "Cannot implement `%s(%s)`: required superclass `%s(%s)` is not \
                         satisfied.\n\
                         Add `impl %s(%s) do ... end` before this implementation."
                        idef.impl_iface.txt (pp_ty inst_ty)
                        sc_name.txt (pp_ty sc_inst_ty)
                        sc_name.txt (pp_ty sc_inst_ty)))
            | _ -> ()  (* multi-param superclasses not yet supported *)
           )
         ) interface.iface_superclasses;
       (* Check all required methods are provided (error for non-default missing) *)
       List.iter (fun (iface_m : Ast.method_decl) ->
           let provided = List.exists
             (fun ((mname : Ast.name), _) -> mname.txt = iface_m.md_name.txt)
             idef.impl_methods
           in
           if not provided && iface_m.md_default = None then
             Err.error env.errors ~span:idef.impl_iface.span
               (Printf.sprintf
                  "Missing method `%s` in `impl %s(%s)`.\n\
                   Interface `%s` requires this method to be implemented."
                  iface_m.md_name.txt idef.impl_iface.txt (pp_ty inst_ty)
                  idef.impl_iface.txt)
         ) interface.iface_methods;
       List.iter (fun ((mname : Ast.name), (def : Ast.fn_def)) ->
           match List.find_opt
                   (fun (m : Ast.method_decl) -> m.md_name.txt = mname.txt)
                   interface.iface_methods with
           | None ->
             Err.error env.errors ~span:mname.span
               (Printf.sprintf "Interface `%s` does not declare a method `%s`."
                  idef.impl_iface.txt mname.txt)
           | Some iface_method ->
             (* Expected type: substitute interface param → concrete impl type *)
             let expected_ty =
               surface_ty env
                 ~tvars:(ref [(interface.iface_param.txt, inst_ty)])
                 iface_method.md_ty
             in
             (* Infer the method body's actual type.
                For injected default methods (zero params, body = default expr),
                use check_expr directly against the expected type. *)
             (match def.fn_clauses with
              | [{ fc_params = []; fc_body; _ }] when iface_method.md_default <> None ->
                (* Default method injected by desugar — just check the body expr *)
                check_expr env fc_body expected_ty
                  ~reason:(Some (RBuiltin
                    (Printf.sprintf "default `%s` in interface `%s`"
                       mname.txt idef.impl_iface.txt)))
              | _ ->
                let actual_sch = check_fn env def _sp in
                let actual_ty = instantiate env.level env actual_sch in
                unify env ~span:mname.span actual_ty expected_ty
                  ~reason:(Some (RBuiltin
                     (Printf.sprintf "`%s` in `impl %s` must match the interface signature"
                        mname.txt idef.impl_iface.txt))))
         ) idef.impl_methods);
    env_with_impl

  | Ast.DExtern (edef, _sp) ->
    (* Register each foreign function as a monomorphic binding. *)
    List.fold_left (fun env (ef : Ast.extern_fn) ->
        let tvars = ref [] in
        let param_tys = List.map (fun (_, t) -> surface_ty env ~tvars t) ef.ef_params in
        let ret_ty = surface_ty env ~tvars ef.ef_ret_ty in
        let ty = List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys ret_ty in
        bind_var ef.ef_name.txt (Mono ty) env
      ) env edef.ext_fns

  | Ast.DUse (ud, sp) ->
    let mod_str = String.concat "." (List.map (fun n -> n.Ast.txt) ud.use_path) in
    let prefix = mod_str ^ "." in
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
       (* Track for unused-import warning: warn if nothing from this module is used. *)
       if matching <> [] then begin
         let short_names = List.map fst matching in
         let entry = { ie_span = sp
                     ; ie_desc = Printf.sprintf
                         "Unused import: nothing from `%s` is used.\n\
                          Remove this import or use something from it." mod_str
                     ; ie_matches = (fun name -> List.mem name short_names)
                     ; ie_used = ref false } in
         env.import_tracker := entry :: !(env.import_tracker)
       end;
       bind_vars matching env
     | Ast.UseNames names ->
       List.fold_left (fun env n ->
           match List.assoc_opt (prefix ^ n.Ast.txt) env.vars with
           | Some sch ->
             (* Track for unused-import warning: warn if this specific name is unused. *)
             let entry = { ie_span = n.Ast.span
                         ; ie_desc = Printf.sprintf
                             "Unused import `%s` from `%s`.\n\
                              Remove it from the import list or use it." n.Ast.txt mod_str
                         ; ie_matches = (fun name -> name = n.Ast.txt)
                         ; ie_used = ref false } in
             env.import_tracker := entry :: !(env.import_tracker);
             bind_var n.Ast.txt sch env
           | None ->
             Err.error env.errors ~span:n.Ast.span
               (Printf.sprintf "Module `%s` does not export `%s`."
                  mod_str n.Ast.txt);
             env) env names
     | Ast.UseExcept excluded ->
       let excl_set = List.map (fun n -> n.Ast.txt) excluded in
       let matching = List.filter_map (fun (k, sch) ->
           let plen = String.length prefix in
           if String.length k > plen
              && String.sub k 0 plen = prefix
           then
             let short = String.sub k plen (String.length k - plen) in
             if List.mem short excl_set then None
             else Some (short, sch)
           else None) env.vars in
       (* Track for unused-import warning: warn if nothing from this module is used. *)
       if matching <> [] then begin
         let short_names = List.map fst matching in
         let entry = { ie_span = sp
                     ; ie_desc = Printf.sprintf
                         "Unused import: nothing from `%s` is used.\n\
                          Remove this import or use something from it." mod_str
                     ; ie_matches = (fun name -> List.mem name short_names)
                     ; ie_used = ref false } in
         env.import_tracker := entry :: !(env.import_tracker)
       end;
       bind_vars matching env)

  | Ast.DAlias (ad, sp) ->
    let orig_prefix = String.concat "." (List.map (fun n -> n.Ast.txt) ad.alias_path) ^ "." in
    let short_name = ad.alias_name.Ast.txt in
    let short_prefix = short_name ^ "." in
    (* Re-export all "Orig.name" as "Short.name" *)
    let new_bindings = List.filter_map (fun (k, sch) ->
        let plen = String.length orig_prefix in
        if String.length k > plen && String.sub k 0 plen = orig_prefix then
          let rest = String.sub k plen (String.length k - plen) in
          Some (short_prefix ^ rest, sch)
        else None) env.vars in
    (* Track for unused-alias warning: warn if no "Short.*" name is referenced. *)
    if new_bindings <> [] then begin
      let orig_str = String.concat "." (List.map (fun n -> n.Ast.txt) ad.alias_path) in
      let entry = { ie_span = sp
                  ; ie_desc = Printf.sprintf
                      "Unused alias `%s` for `%s`.\n\
                       Remove this alias or use it to qualify a name." short_name orig_str
                  ; ie_matches = (fun name ->
                      let plen = String.length short_prefix in
                      (String.length name >= plen && String.sub name 0 plen = short_prefix)
                      || name = short_name)
                  ; ie_used = ref false } in
      env.import_tracker := entry :: !(env.import_tracker)
    end;
    bind_vars new_bindings env

  | Ast.DNeeds (caps, _sp) ->
    (* Record declared capability paths in env for DMod validation.
       Each path is a list of names e.g. ["IO"; "Network"] → "IO.Network" *)
    let paths = List.map (fun names ->
        String.concat "." (List.map (fun (n : Ast.name) -> n.txt) names)
      ) caps in
    { env with mod_needs = paths @ env.mod_needs }

  | Ast.DApp _ ->
    (* DApp is desugared to DFn(__app_init__) before typecheck; reaching here is a bug. *)
    env

  | Ast.DDeriving _ ->
    (* DDeriving is expanded to DImpl blocks by the desugar pass; should not reach here. *)
    env

  | Ast.DTest (tdef, sp) ->
    (* Typecheck the test body; it must be Unit. *)
    check_expr env tdef.test_body t_unit
      ~reason:(Some (RBuiltin (Printf.sprintf "test body of \"%s\" must produce Unit" tdef.test_name)));
    Hashtbl.replace env.type_map sp t_unit;
    env

  | Ast.DDescribe (_name, decls, sp) ->
    let env' = List.fold_left check_decl env decls in
    Hashtbl.replace env'.type_map sp t_unit;
    env'

  | Ast.DSetup (body, sp) ->
    check_expr env body t_unit ~reason:(Some (RBuiltin "setup body must produce Unit"));
    Hashtbl.replace env.type_map sp t_unit;
    env

  | Ast.DSetupAll (body, sp) ->
    check_expr env body t_unit ~reason:(Some (RBuiltin "setup_all body must produce Unit"));
    Hashtbl.replace env.type_map sp t_unit;
    env

(** Emit warnings for any imports or aliases that were never referenced. *)
let warn_unused_imports env =
  List.iter (fun ie ->
    if not !(ie.ie_used) then
      Err.warning_with_code env.errors ~span:ie.ie_span ~code:"unused_import" ie.ie_desc
  ) !(env.import_tracker)

(* =================================================================
   §16  Tail-call enforcement
   ================================================================= *)

(** Collect all names from [fn_names] that are called directly (not through
    lambdas or local [ELetFn] bodies) in [e].  Used to build the call graph
    for SCC / mutual-recursion detection. *)
let rec collect_direct_fn_calls (fn_names : StringSet.t) (e : Ast.expr) : StringSet.t =
  match e with
  | Ast.EApp (Ast.EVar fn, args, _) ->
    let self = if StringSet.mem fn.txt fn_names then StringSet.singleton fn.txt
               else StringSet.empty in
    List.fold_left (fun acc a ->
      StringSet.union acc (collect_direct_fn_calls fn_names a)
    ) self args
  | Ast.EApp (f, args, _) ->
    List.fold_left (fun acc a ->
      StringSet.union acc (collect_direct_fn_calls fn_names a)
    ) (collect_direct_fn_calls fn_names f) args
  | Ast.ECon (_, args, _) ->
    List.fold_left (fun acc a ->
      StringSet.union acc (collect_direct_fn_calls fn_names a)
    ) StringSet.empty args
  | Ast.EIf (c, t, f, _) ->
    StringSet.union (collect_direct_fn_calls fn_names c)
      (StringSet.union (collect_direct_fn_calls fn_names t)
                       (collect_direct_fn_calls fn_names f))
  | Ast.EMatch (scrut, branches, _) ->
    List.fold_left (fun acc br ->
      let g = Option.fold ~none:StringSet.empty
                ~some:(collect_direct_fn_calls fn_names) br.Ast.branch_guard in
      StringSet.union acc
        (StringSet.union g (collect_direct_fn_calls fn_names br.Ast.branch_body))
    ) (collect_direct_fn_calls fn_names scrut) branches
  | Ast.EBlock (exprs, _) ->
    List.fold_left (fun acc ex ->
      StringSet.union acc (collect_direct_fn_calls fn_names ex)
    ) StringSet.empty exprs
  | Ast.ELet (b, _) -> collect_direct_fn_calls fn_names b.Ast.bind_expr
  | Ast.ELetFn (_, _, _, _, _) -> StringSet.empty   (* new scope *)
  | Ast.ELam (_, _, _)         -> StringSet.empty   (* new scope *)
  | Ast.ETuple (es, _) ->
    List.fold_left (fun acc ex ->
      StringSet.union acc (collect_direct_fn_calls fn_names ex)
    ) StringSet.empty es
  | Ast.ERecord (fields, _) ->
    List.fold_left (fun acc (_, ex) ->
      StringSet.union acc (collect_direct_fn_calls fn_names ex)
    ) StringSet.empty fields
  | Ast.ERecordUpdate (base, fields, _) ->
    List.fold_left (fun acc (_, ex) ->
      StringSet.union acc (collect_direct_fn_calls fn_names ex)
    ) (collect_direct_fn_calls fn_names base) fields
  | Ast.EField (ex, _, _)  -> collect_direct_fn_calls fn_names ex
  | Ast.EAnnot (ex, _, _)  -> collect_direct_fn_calls fn_names ex
  | Ast.EPipe (l, r, _) ->
    StringSet.union (collect_direct_fn_calls fn_names l)
                    (collect_direct_fn_calls fn_names r)
  | Ast.EAtom (_, args, _) ->
    List.fold_left (fun acc a ->
      StringSet.union acc (collect_direct_fn_calls fn_names a)
    ) StringSet.empty args
  | Ast.ESend (a, b, _) ->
    StringSet.union (collect_direct_fn_calls fn_names a)
                    (collect_direct_fn_calls fn_names b)
  | Ast.ESpawn (ex, _)       -> collect_direct_fn_calls fn_names ex
  | Ast.EDbg (Some ex, _)    -> collect_direct_fn_calls fn_names ex
  | Ast.EAssert (ex, _) -> collect_direct_fn_calls fn_names ex
  | Ast.ELit _ | Ast.EVar _ | Ast.EHole _ | Ast.EResultRef _
  | Ast.EDbg (None, _)       -> StringSet.empty

(** Tarjan's SCC algorithm.  [adj] is a list of (name, called-names) pairs.
    Returns each SCC as a list; non-recursive singletons are included. *)
let find_sccs (adj : (string * StringSet.t) list) : string list list =
  let idx_ctr   = ref 0 in
  let stk       = ref [] in
  let on_stk    = Hashtbl.create 16 in
  let idx_map   = Hashtbl.create 16 in
  let lowlink   = Hashtbl.create 16 in
  let sccs      = ref [] in
  let rec sc v =
    let vi = !idx_ctr in
    Hashtbl.replace idx_map  v vi;
    Hashtbl.replace lowlink  v vi;
    incr idx_ctr;
    stk := v :: !stk;
    Hashtbl.replace on_stk v true;
    let neighbors = match List.assoc_opt v adj with
      | Some s -> StringSet.elements s | None -> [] in
    List.iter (fun w ->
      if not (Hashtbl.mem idx_map w) then begin
        sc w;
        let lv = Hashtbl.find lowlink v in
        let lw = Hashtbl.find lowlink w in
        Hashtbl.replace lowlink v (min lv lw)
      end else if Hashtbl.mem on_stk w then begin
        let lv = Hashtbl.find lowlink v in
        let iw = Hashtbl.find idx_map  w in
        Hashtbl.replace lowlink v (min lv iw)
      end
    ) neighbors;
    if Hashtbl.find lowlink v = Hashtbl.find idx_map v then begin
      let scc = ref [] in
      let go  = ref true in
      while !go do
        match !stk with
        | [] -> go := false
        | w :: rest ->
          stk := rest;
          Hashtbl.remove on_stk w;
          scc := w :: !scc;
          if w = v then go := false
      done;
      sccs := !scc :: !sccs
    end
  in
  List.iter (fun (v, _) ->
    if not (Hashtbl.mem idx_map v) then sc v
  ) adj;
  !sccs

let is_infix_op name =
  match name with
  | "+" | "-" | "*" | "/" | "%" | "<" | ">" | "<=" | ">="
  | "==" | "!=" | "&&" | "||" | "+." | "-." | "*." | "/." -> true
  | _ -> false

(** Collect all variable names bound by a pattern (used to find structurally
    smaller variables introduced by pattern matching). *)
let rec collect_pattern_vars (pat : Ast.pattern) : StringSet.t =
  match pat with
  | Ast.PatWild _ | Ast.PatLit _ -> StringSet.empty
  | Ast.PatVar v -> StringSet.singleton v.txt
  | Ast.PatCon (_, pats) ->
    List.fold_left (fun acc p -> StringSet.union acc (collect_pattern_vars p))
      StringSet.empty pats
  | Ast.PatAtom (_, pats, _) ->
    List.fold_left (fun acc p -> StringSet.union acc (collect_pattern_vars p))
      StringSet.empty pats
  | Ast.PatTuple (pats, _) ->
    List.fold_left (fun acc p -> StringSet.union acc (collect_pattern_vars p))
      StringSet.empty pats
  | Ast.PatRecord (fields, _) ->
    List.fold_left (fun acc (_, p) -> StringSet.union acc (collect_pattern_vars p))
      StringSet.empty fields
  | Ast.PatAs (p, v, _) -> StringSet.add v.txt (collect_pattern_vars p)

(** True if [expr] is provably structurally smaller than some function parameter.
    - [params]: the set of function parameter variable names.
    - [smaller]: variables known to be sub-components of a parameter (from pattern matching).
    Recognises:
      1. A pattern-bound sub-component: [EVar v] where [v ∈ smaller].
      2. Arithmetic reduction: [v - k] or [v / k] where [v ∈ params ∪ smaller].
      3. List element access: [list_nth_safe(xs,i)], [List.nth(xs,i)] where xs is smaller.
      4. Nullary constructor (e.g. HEmpty, Nil): structurally minimal. *)
let rec is_structurally_smaller (params : StringSet.t) (smaller : StringSet.t) (expr : Ast.expr) : bool =
  match expr with
  | Ast.EVar v -> StringSet.mem v.txt smaller
  | Ast.EApp (Ast.EVar op, [lhs; _], _) when op.txt = "-" || op.txt = "/" ->
    (match lhs with
     | Ast.EVar v -> StringSet.mem v.txt params || StringSet.mem v.txt smaller
     | _ -> false)
  (* List element accessor: element is structurally smaller than the list *)
  | Ast.EApp (Ast.EVar fn, arg :: _, _)
    when List.mem fn.txt ["list_nth_safe"; "list_nth"; "List.nth"; "List.hd"; "List.head"] ->
    is_structurally_smaller params smaller arg
  (* Nullary constructor (e.g. HEmpty, Nil): always structurally minimal *)
  | Ast.ECon (_, [], _) -> true
  | _ -> false

(** True if [expr] is a function parameter or a known-smaller variable — meaning
    pattern-bound sub-components of this scrutinee can be treated as smaller. *)
let scrutinee_is_param_or_smaller (params : StringSet.t) (smaller : StringSet.t) (expr : Ast.expr) : bool =
  match expr with
  | Ast.EVar v -> StringSet.mem v.txt params || StringSet.mem v.txt smaller
  | _ -> false

(** Verify that every call to any name in [recursive_names] within [body]
    is either in tail position OR is structurally recursive (guaranteed to
    terminate because every argument is provably smaller than a parameter).
    Emits [Error] diagnostics only for truly unbounded non-tail recursion.
    [fn_name] is the enclosing function (for readable error messages).
    [fn_params] is the set of parameter variable names for [fn_name]. *)
let rec check_tail_position
    (errors : Err.ctx)
    (recursive_names : StringSet.t)
    (fn_name : string)
    (fn_params : StringSet.t)
    (body : Ast.expr) : unit =
  (* [smaller] accumulates variables known to be structurally smaller than a
     function parameter (introduced by pattern-matching on a parameter). *)
  let rec chk in_tail (smaller : StringSet.t) ctx expr =
    match expr with
    (* ── Recursive call ── *)
    | Ast.EApp (Ast.EVar fn, args, sp) when StringSet.mem fn.txt recursive_names ->
      if not in_tail then begin
        (* Allow if at least one argument is provably structurally smaller:
           this covers structural recursion on sub-trees/sub-lists and
           arithmetic reductions like n-1, n-2. *)
        let is_structural =
          List.exists (is_structurally_smaller fn_params smaller) args
        in
        if not is_structural then
          Err.error errors ~span:sp
            (Printf.sprintf
               "Function `%s`: recursive call to `%s` is not in tail position \
                (%s).\n\
                Hint: Consider using an accumulator parameter."
               fn_name fn.txt ctx)
        else begin
          (* Structural recursion: warn but allow — distinguish arithmetic
             reductions (n-1, n-2) from pattern-bound sub-components. *)
          let is_arithmetic = List.exists (fun arg ->
            match arg with
            | Ast.EApp (Ast.EVar op, [lhs; _], _) when op.txt = "-" ->
              (match lhs with
               | Ast.EVar v ->
                 StringSet.mem v.txt fn_params || StringSet.mem v.txt smaller
               | _ -> false)
            | _ -> false
          ) args in
          if is_arithmetic then
            Err.warning errors ~span:sp
              (Printf.sprintf
                 "Warning: function `%s` is structurally recursive but not \
                  tail-recursive. Consider using an accumulator parameter \
                  for O(n) performance."
                 fn_name)
          else
            Err.warning errors ~span:sp
              (Printf.sprintf
                 "Warning: function `%s` is structurally recursive but not \
                  tail-recursive. This is safe for bounded input but uses \
                  O(depth) stack space."
                 fn_name)
        end
      end;
      List.iteri (fun i arg ->
        chk false smaller
          (Printf.sprintf "argument #%d in call to `%s`" (i + 1) fn.txt)
          arg
      ) args
    (* ── Regular application ── *)
    | Ast.EApp (f, args, _) ->
      let arg_ctx = match f with
        | Ast.EVar op when is_infix_op op.txt ->
          Printf.sprintf "wrapped in binary operation `%s`" op.txt
        | Ast.EVar fn_n -> Printf.sprintf "passed as argument to `%s`" fn_n.txt
        | _ -> "passed as argument to a function"
      in
      chk false smaller "function part of application" f;
      List.iter (chk false smaller arg_ctx) args
    (* ── Constructor ── *)
    | Ast.ECon (name, args, _) ->
      let arg_ctx = Printf.sprintf "wrapped in constructor `%s`" name.txt in
      List.iter (chk false smaller arg_ctx) args
    (* ── if/then/else: condition not tail; branches inherit ── *)
    | Ast.EIf (cond, then_, else_, _) ->
      chk false smaller "condition of `if`" cond;
      chk in_tail smaller ctx then_;
      chk in_tail smaller ctx else_
    (* ── match: scrutinee not tail; if scrutinee is a parameter or smaller
          variable, extend [smaller] with all vars bound in each arm's pattern ── *)
    | Ast.EMatch (scrut, branches, _) ->
      chk false smaller "scrutinee of `match`" scrut;
      let scrut_is_smaller = scrutinee_is_param_or_smaller fn_params smaller scrut in
      List.iter (fun (br : Ast.branch) ->
        let arm_smaller =
          if scrut_is_smaller
          then StringSet.union smaller (collect_pattern_vars br.branch_pat)
          else smaller
        in
        Option.iter (chk false arm_smaller "match guard") br.branch_guard;
        chk in_tail arm_smaller ctx br.branch_body
      ) branches
    (* ── block: only last expression is in tail position.
          Propagate structural smallness: if a let binding assigns a variable
          to a structurally-smaller expression, that variable is also smaller. ── *)
    | Ast.EBlock (exprs, _) ->
      let rec go s = function
        | [] -> ()
        | [last] -> chk in_tail s ctx last
        | hd :: tl ->
          chk false s "non-final expression in block" hd;
          let s' = match hd with
            | Ast.ELet (b, _) ->
              (match b.Ast.bind_pat with
               | Ast.PatVar v
                 when is_structurally_smaller fn_params s b.Ast.bind_expr ->
                 StringSet.add v.txt s
               | _ -> s)
            | _ -> s
          in
          go s' tl
      in
      go smaller exprs
    (* ── let binding: RHS is never tail ── *)
    | Ast.ELet (b, _) ->
      chk false smaller "right-hand side of `let` binding" b.Ast.bind_expr
    (* ── inner named function: check its own self-recursion in its own scope ── *)
    | Ast.ELetFn (iname, iparams, _, ibody, _) ->
      let iparams_set =
        List.fold_left (fun acc (p : Ast.param) -> StringSet.add p.param_name.txt acc)
          StringSet.empty iparams
      in
      check_tail_position errors (StringSet.singleton iname.txt) iname.txt iparams_set ibody
    (* ── lambda: new scope, skip outer recursive-name check ── *)
    | Ast.ELam _ -> ()
    (* ── transparent ── *)
    | Ast.EAnnot (ex, _, _) -> chk in_tail smaller ctx ex
    (* ── non-tail contexts ── *)
    | Ast.ETuple (es, _) ->
      List.iter (chk false smaller "tuple element") es
    | Ast.ERecord (fields, _) ->
      List.iter (fun ((nm : Ast.name), ex) ->
        chk false smaller (Printf.sprintf "value of record field `%s`" nm.txt) ex
      ) fields
    | Ast.ERecordUpdate (base, fields, _) ->
      chk false smaller "base of record update" base;
      List.iter (fun ((nm : Ast.name), ex) ->
        chk false smaller (Printf.sprintf "value of record field `%s`" nm.txt) ex
      ) fields
    | Ast.EField (ex, _, _)  -> chk false smaller "object of field access" ex
    | Ast.EPipe  (l, r, _)   -> chk false smaller "left side of pipe" l;
                                 chk false smaller "right side of pipe" r
    | Ast.EAtom (_, args, _) -> List.iter (chk false smaller "atom argument") args
    | Ast.ESend (cap, msg, _) ->
      chk false smaller "capability in `send`" cap;
      chk false smaller "message in `send`" msg
    | Ast.ESpawn (ex, _)      -> chk false smaller "argument to `spawn`" ex
    | Ast.EDbg (Some ex, _)   -> chk false smaller "argument to `dbg`" ex
    | Ast.EAssert (ex, _)     -> chk false smaller "assert expression" ex
    (* ── leaves ── *)
    | Ast.EDbg (None, _) | Ast.ELit _ | Ast.EVar _ | Ast.EHole _
    | Ast.EResultRef _ -> ()
  in
  chk true StringSet.empty "" body

(** Run tail-call enforcement for all [DFn] declarations in [decls]
    (at a single scope level).  Recurses into [DMod] sub-modules. *)
let rec enforce_tail_calls_in_decls (errors : Err.ctx) (decls : Ast.decl list) : unit =
  (* Collect function names at this level *)
  let fn_names =
    List.fold_left (fun acc d ->
      match d with
      | Ast.DFn (def, _) -> StringSet.add def.fn_name.txt acc
      | _ -> acc
    ) StringSet.empty decls
  in
  (* Build call graph *)
  let adj = List.filter_map (function
    | Ast.DFn (def, _) ->
      (match def.fn_clauses with
       | [clause] ->
         Some (def.fn_name.txt,
               collect_direct_fn_calls fn_names clause.Ast.fc_body)
       | _ -> None)
    | _ -> None
  ) decls in
  (* Find SCCs *)
  let sccs = find_sccs adj in
  let scc_of = Hashtbl.create 16 in
  List.iter (fun scc ->
    List.iter (fun nm -> Hashtbl.replace scc_of nm scc) scc
  ) sccs;
  (* Check each function that participates in recursion *)
  List.iter (function
    | Ast.DFn (def, _) ->
      (match def.fn_clauses with
       | [clause] ->
         let scc = try Hashtbl.find scc_of def.fn_name.txt
                   with Not_found -> [def.fn_name.txt] in
         let direct = match List.assoc_opt def.fn_name.txt adj with
           | Some s -> s | None -> StringSet.empty in
         let is_recursive =
           List.length scc > 1 ||
           StringSet.mem def.fn_name.txt direct
         in
         if is_recursive && not (List.mem "no_warn_recursion" def.fn_attrs) then begin
           let rec_set = List.fold_right StringSet.add scc StringSet.empty in
           let fn_params =
             List.fold_left (fun acc p ->
               match p with
               | Ast.FPNamed named -> StringSet.add named.param_name.txt acc
               | Ast.FPPat pat -> StringSet.union acc (collect_pattern_vars pat)
             ) StringSet.empty clause.Ast.fc_params
           in
           check_tail_position errors rec_set def.fn_name.txt fn_params clause.Ast.fc_body
         end
       | _ -> ())
    | Ast.DMod (_, _, inner_decls, _) ->
      enforce_tail_calls_in_decls errors inner_decls
    | _ -> ()
  ) decls

(* =================================================================
   §17  Module entry point
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
      | Ast.DType (_, name, params, typedef, _) ->
        let env1 = { env with types = (name.txt, List.length params) :: env.types } in
        (match typedef with
         | Ast.TDVariant variants ->
           let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
           List.fold_left (fun e (v : Ast.variant) ->
               let ci = { ci_type    = name.txt
                        ; ci_params  = param_names
                        ; ci_arg_tys = v.var_args
                        ; ci_vis     = v.var_vis } in
               { e with ctors = (v.var_name.txt, ci) :: e.ctors }
             ) env1 variants
         | Ast.TDRecord fields ->
           let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
           let field_pairs = List.map (fun (f : Ast.field) -> (f.fld_name.txt, f.fld_ty)) fields in
           { env1 with records = (name.txt, (param_names, field_pairs)) :: env1.records }
         | _ -> env1)
      | Ast.DActor (_, name, actor, _) ->
        (* Register actor name as a zero-arg constructor and message ctors.
           Same arity fix as in check_decl: include unannotated params as
           unique TyVar placeholders so constructor arity is always correct. *)
        let env1 = { env with ctors =
          (name.txt, { ci_type = name.txt; ci_params = []; ci_arg_tys = []; ci_vis = Ast.Public })
          :: env.ctors } in
        List.fold_left (fun acc_env (h : Ast.actor_handler) ->
            let arg_tys = List.mapi (fun i (p : Ast.param) ->
                match p.param_ty with
                | Some ty -> ty
                | None ->
                  Ast.TyVar { txt = Printf.sprintf "$p%d_%s" i h.ah_msg.txt;
                              span = p.param_name.span }
              ) h.ah_params in
            let ci = { ci_type = name.txt ^ "_Msg"; ci_params = [];
                       ci_arg_tys = arg_tys; ci_vis = Ast.Public } in
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
  (* Warn about any unused imports or aliases *)
  warn_unused_imports final_env;
  (* Pass 3: tail-call enforcement *)
  enforce_tail_calls_in_decls errors m.Ast.mod_decls;
  (errors, type_map)

(** Like [check_module] but also returns the final type environment.
    Used by tests to inspect protocol projections. *)
let check_module_full ?(errors = Err.create ()) (m : Ast.module_)
    : Err.ctx * (Ast.span, ty) Hashtbl.t * env =
  let type_map = Hashtbl.create 256 in
  (* Same two-pass structure as check_module — uses base_env with builtins. *)
  let pre_env = List.fold_left (fun env d ->
      match d with
      | Ast.DFn (def, _) ->
        if List.mem_assoc def.fn_name.txt env.vars then env
        else bind_var def.fn_name.txt (Mono (fresh_var 0)) env
      | Ast.DType (_vis, name, params, typedef, _) ->
        let env1 = { env with types = (name.txt, List.length params) :: env.types } in
        (match typedef with
         | Ast.TDVariant variants ->
           let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
           List.fold_left (fun e (v : Ast.variant) ->
               let ci = { ci_type    = name.txt
                        ; ci_params  = param_names
                        ; ci_arg_tys = v.var_args
                        ; ci_vis     = v.var_vis } in
               { e with ctors = (v.var_name.txt, ci) :: e.ctors }
             ) env1 variants
         | _ -> env1)
      | _ -> env
    ) (base_env errors type_map) m.Ast.mod_decls in
  let final_env = List.fold_left check_decl pre_env m.Ast.mod_decls in
  check_module_needs final_env m.Ast.mod_name m.Ast.mod_decls;
  warn_unused_imports final_env;
  enforce_tail_calls_in_decls errors m.Ast.mod_decls;
  (errors, type_map, final_env)
