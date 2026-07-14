(** Perceus — Phase 4: FBIP reuse detection (Wave 3 Task 5 file split).
    Moved verbatim from [perceus.ml]; edits are limited to module
    qualification:
    - [name_free_in] -> [Perceus_liveness.name_free_in] (self-contained
      liveness group).
    - [fbip_arity_marker]/[is_fbip_encoded] moved HERE (rather than staying
      in [perceus.ml] core as originally planned): the marker has one
      PRODUCER — [perceus.ml]'s [insert_rc_expr] / [add_scrutinee_free_for]
      (the $fbip$-encoding of a freed constructor's arity onto the DecRC'd
      variable's type, in the ECase case) — and one CONSUMER, [same_arity]
      below.  [Perceus] (the orchestrator) already calls INTO this module
      ([insert_fbip]), so the marker constant living here and the producer
      referencing it as [Perceus_fbip.fbip_arity_marker] is the
      non-cyclic direction; the reverse (marker in [perceus.ml],
      [same_arity] here referencing [Perceus.is_fbip_encoded]) was tried
      first and rejected by dune as a dependency cycle
      ([Perceus] -> [Perceus_fbip] via [insert_fbip] AND
      [Perceus_fbip] -> [Perceus] via [is_fbip_encoded] simultaneously). *)

(** Marker prefix for the FBIP arity encoding minted by [perceus.ml]'s
    [add_scrutinee_free_for].  '$' cannot start a source-level type name, so
    a [TCon] whose head carries this prefix is unambiguously an encoded
    constructor arity, never a user type applied to type arguments. *)
let fbip_arity_marker = "$fbip$"

let is_fbip_encoded (name : string) : bool =
  let ml = String.length fbip_arity_marker in
  String.length name >= ml && String.sub name 0 ml = fbip_arity_marker

(** Arity check for FBIP reuse — P8 extension.
    [dec_v.v_ty] carries the arity of the consumed (freed) constructor as
    the length of its dummy TUnit type-arg list (see [add_scrutinee_free_for]
    in [perceus.ml]), behind the [fbip_arity_marker] prefix.
    [nfields] is the number of arguments the new EAlloc will produce.
    Two constructors are reuse-compatible iff they have the SAME field count:
    the March GC allocates blocks as [tag + nfields × ptr], so any two
    constructors with the same arity have identical allocation sizes and can
    safely exchange their cells — the new tag is written into the reused block
    by the FBIP branch in llvm_emit.  Cross-ctor reuse (P8) is enabled here
    by NOT requiring the constructor name to match, only the arity.

    Only marker-encoded types are accepted.  A dec of a variable carrying its
    RAW declared type (the dead-binding cleanup path) must NOT be compared:
    [TCon(name, ts)] there gives the type's PARAMETER count, not the field
    count of whichever constructor the value happens to hold — e.g. a dead
    [Ok(7) : Result(Int, String)] is a 1-field cell but has 2 type params, so
    the old [List.length ts = nfields] check approved reusing it for a
    2-field constructor: an 8-byte heap overflow.  The actual constructor of
    a dead binding is statically unknown (any ctor of the type, each with its
    own arity), so reuse is refused rather than guessed. *)
let same_arity (t : Tir.ty) (nfields : int) : bool =
  match t with
  | Tir.TCon (name, ts) -> is_fbip_encoded name && List.length ts = nfields
  | _ -> false

(** True iff [dec_v]'s name appears as an AVar in any of [args].
    Prevents the self-referential FBIP bug: if the reuse atom IS one of the
    constructor args (e.g. Some(result)->Ok(result) with niche-encoding, where
    result = the scrutinee = dec_v), reusing dec_v's memory to build the new
    object would store dec_v's address into its own field, creating a cycle. *)
let args_alias_reuse (dec_v : Tir.var) (args : Tir.atom list) : bool =
  List.exists (function
    | Tir.AVar v -> String.equal v.Tir.v_name dec_v.Tir.v_name
    | _ -> false) args

(** Try to sink [EDecRC(dec_v)] into [body] through a chain of ELet
    bindings, stopping when we find an EAlloc of matching shape.  Safe
    only when [dec_v] does not appear in any RHS along the chain. *)
let rec try_fbip_sink (dec_v : Tir.var) (body : Tir.expr) : Tir.expr option =
  match body with
  (* EAlloc in tail position — reuse directly if arities match and dec_v is
     not one of the constructor args (which would create a self-referential
     object when dec_v's memory is reused to store dec_v itself). *)
  | Tir.EAlloc (ty, args)
    when List.length args > 0
      && same_arity dec_v.Tir.v_ty (List.length args)
      && not (args_alias_reuse dec_v args) ->
    Some (Tir.EReuse (Tir.AVar dec_v, ty, args))
  (* EAlloc bound to a result variable *)
  | Tir.ELet (result, Tir.EAlloc (ty, args), rest)
    when List.length args > 0
      && same_arity dec_v.Tir.v_ty (List.length args)
      && not (args_alias_reuse dec_v args) ->
    Some (Tir.ELet (result, Tir.EReuse (Tir.AVar dec_v, ty, args), rest))
  (* dec_v not used in rhs — safe to sink past this binding *)
  | Tir.ELet (v, rhs, inner)
    when not (Perceus_liveness.name_free_in dec_v.Tir.v_name rhs) ->
    Option.map (fun inner' -> Tir.ELet (v, rhs, inner'))
               (try_fbip_sink dec_v inner)
  | _ -> None

(** Detect DecRC + Alloc of compatible arity and replace with Reuse. *)
let rec fbip_expr (e : Tir.expr) : Tir.expr =
  match e with
  (* Pattern: let _ = decrc(v) in let result = alloc(ty, args) in rest
     where same_arity(v.v_ty, len(args)) and dec_v is not itself one of the
     constructor args (which would create a self-referential object). *)
  | Tir.ELet (_dead_v, Tir.EDecRC (Tir.AVar dec_v),
              Tir.ELet (result, Tir.EAlloc (ty, args), rest))
    when List.length args > 0
      && same_arity dec_v.Tir.v_ty (List.length args)
      && not (args_alias_reuse dec_v args) ->
    let rest' = fbip_expr rest in
    Tir.ELet (result, Tir.EReuse (Tir.AVar dec_v, ty, args), rest')
  (* ESeq(EDecRC v, body): try to sink the decrc to be adjacent to an
     EAlloc of matching shape anywhere down the let-chain. *)
  | Tir.ESeq (Tir.EDecRC (Tir.AVar dec_v), body) ->
    (match try_fbip_sink dec_v body with
     | Some body' -> fbip_expr body'
     | None       -> Tir.ESeq (Tir.EDecRC (Tir.AVar dec_v), fbip_expr body))
  (* Recurse into sub-expressions *)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (fbip_expr e1, fbip_expr e2)
  | Tir.ELet (v, e1, e2) ->
    Tir.ELet (v, fbip_expr e1, fbip_expr e2)
  | Tir.ELetRec (fns, body) ->
    let fns' = List.map (fun fn ->
      { fn with Tir.fn_body = fbip_expr fn.Tir.fn_body }
    ) fns in
    Tir.ELetRec (fns', fbip_expr body)
  | Tir.ECase (a, branches, default) ->
    let branches' = List.map (fun br ->
      { br with Tir.br_body = fbip_expr br.Tir.br_body }
    ) branches in
    let default' = Option.map fbip_expr default in
    Tir.ECase (a, branches', default')
  | Tir.EAtom _ | Tir.EApp _ | Tir.ECallPtr _
  | Tir.ETuple _ | Tir.ERecord _ | Tir.EField _ | Tir.EUpdate _
  | Tir.EAlloc _ | Tir.EStackAlloc _ | Tir.EFree _ | Tir.EIncRC _ | Tir.EDecRC _
  | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _ | Tir.EReuse _ ->
    e

(** Apply FBIP reuse to a function definition. *)
let insert_fbip (fn : Tir.fn_def) : Tir.fn_def =
  { fn with Tir.fn_body = fbip_expr fn.Tir.fn_body }
