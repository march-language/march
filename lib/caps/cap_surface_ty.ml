(** Capability positions in SURFACE ([Ast.ty]) syntax.

    Shared by the typechecker's [needs]-coverage checks and by the desugarer's
    [derive Json] rejection.  It lives here, rather than as a private helper in
    each, for one reason: a capability walk that exists in two copies drifts,
    and a drifted capability walk is a silent hole rather than a visible bug.
    This codebase has repeatedly paid for wildcard-terminated capability walks
    that were "empirically inert today" — see
    [specs/lang/types/reject/t119_cap_no_panic_impl_body_guarded_division.march]
    and its neighbours for the decl-walk version of the same story.

    Accordingly {b every function here is exhaustive over its constructor set
    with no wildcard arm}.  Adding a constructor to [Ast.ty] must break this
    build.  Do not "fix" such a break with [| _ -> []]. *)

module Ast = March_ast.Ast

(** [caps_in_ty ty] returns every capability path named by a [Cap(X)] anywhere
    in [ty], in left-to-right order, with duplicates retained.

    A [Cap] whose argument is not a bare nullary constructor (a type variable,
    say — [Cap(a)] inside a polymorphic signature) contributes nothing: there
    is no concrete capability to attribute, and reporting a placeholder would
    produce diagnostics naming a capability the programmer never wrote. *)
let rec caps_in_ty (ty : Ast.ty) : string list =
  match ty with
  | Ast.TyCon (con, [arg]) when con.txt = "Cap" ->
    (match arg with
     | Ast.TyCon (name, []) -> [ name.txt ]
     | Ast.TyCon (_, _ :: _)
     | Ast.TyVar _ | Ast.TyArrow _ | Ast.TyTuple _ | Ast.TyRecord _
     | Ast.TyLinear _ | Ast.TyNat _ | Ast.TyNatOp _ | Ast.TyChan _
     | Ast.TyRefine _ -> [])
  | Ast.TyCon (_, args) ->
    (* [Tagged(Marker, T)] deliberately recurses like any other constructor.
       The marker argument is a nullary [TyCon] whose name is not "Cap", so it
       contributes nothing on its own, while a capability nested in [T] is
       still found.  An earlier version skipped [Tagged]'s arguments wholesale
       to avoid a false extraction from the marker; that also blinded the walk
       to [Tagged(R, Cap(IO))], which is a worse trade. *)
    List.concat_map caps_in_ty args
  | Ast.TyArrow (a, b) -> caps_in_ty a @ caps_in_ty b
  | Ast.TyTuple ts -> List.concat_map caps_in_ty ts
  | Ast.TyRecord fields -> List.concat_map (fun (_, t) -> caps_in_ty t) fields
  | Ast.TyLinear (_, t) -> caps_in_ty t
  | Ast.TyNatOp (_, a, b) -> caps_in_ty a @ caps_in_ty b
  | Ast.TyRefine (base, _, _) ->
    (* The refinement predicate is an expression, not a type; a capability
       cannot be introduced by it.  Walk the refined base only. *)
    caps_in_ty base
  | Ast.TyVar _ -> []          (* a bare type variable names no capability *)
  | Ast.TyNat _ -> []          (* type-level natural literal *)
  | Ast.TyChan _ -> []         (* Chan(Role, Protocol): both args are names *)

(** [caps_in_type_def td] returns every capability path named anywhere in a
    type declaration's body — record fields, variant constructor arguments, or
    the right-hand side of an alias.

    This is the reachability question [derive Json] needs answered: "if I
    generate a codec for this declaration, does any position in it hold a
    capability?" *)
let caps_in_type_def (td : Ast.type_def) : string list =
  match td with
  | Ast.TDRecord fields ->
    List.concat_map (fun (f : Ast.field) -> caps_in_ty f.fld_ty) fields
  | Ast.TDVariant variants ->
    List.concat_map (fun (v : Ast.variant) ->
        List.concat_map caps_in_ty v.var_args) variants
  | Ast.TDAlias t -> caps_in_ty t

(** [mentions_tycon name ty] — does a type constructor called [name] occur
    anywhere in [ty]?  Same walk as [caps_in_ty], same exhaustiveness
    discipline (a new [Ast.ty] constructor breaks the build here on purpose).

    First use: [derive Json] refuses a type with a [Pid] anywhere in it.  A
    local pid is an index into THIS node's actor table; on another node it
    names whatever happens to live at that slot, so a codec over it is a
    wrong-delivery route, not a serialization.  The cross-node identity is
    [GlobalPid.Pid], which is a plain record and derives like any other. *)
let rec mentions_tycon (name : string) (ty : Ast.ty) : bool =
  match ty with
  | Ast.TyCon (con, args) ->
    con.txt = name || List.exists (mentions_tycon name) args
  | Ast.TyArrow (a, b) -> mentions_tycon name a || mentions_tycon name b
  | Ast.TyTuple ts -> List.exists (mentions_tycon name) ts
  | Ast.TyRecord fields -> List.exists (fun (_, t) -> mentions_tycon name t) fields
  | Ast.TyLinear (_, t) -> mentions_tycon name t
  | Ast.TyNatOp (_, a, b) -> mentions_tycon name a || mentions_tycon name b
  | Ast.TyRefine (base, _, _) -> mentions_tycon name base
  | Ast.TyVar _ | Ast.TyNat _ | Ast.TyChan _ -> false

(** [type_def_mentions_tycon name td]: [mentions_tycon] over every position
    of a declaration body, the way [caps_in_type_def] lifts [caps_in_ty]. *)
let type_def_mentions_tycon (name : string) (td : Ast.type_def) : bool =
  match td with
  | Ast.TDRecord fields ->
    List.exists (fun (f : Ast.field) -> mentions_tycon name f.fld_ty) fields
  | Ast.TDVariant variants ->
    List.exists (fun (v : Ast.variant) ->
        List.exists (mentions_tycon name) v.var_args) variants
  | Ast.TDAlias t -> mentions_tycon name t
