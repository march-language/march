(** P6 — derived representation table.

    A pure, memoized function of the MONOMORPHIC type: after monomorphization
    every type is concrete, so representation can be decided per type with no
    threading of state.  Leaving [Tir.ty] unchanged keeps the blast radius to
    the codegen consultation sites.

    Milestone 1 implements [Boxed] and [Newtype].  [Niche] is defined now so the
    type is stable for the Option-niche follow-on plan, but is never returned
    yet. *)

type repr =
  | Boxed                                       (* today's heap cell *)
  | Newtype of Tir.ty                           (* represented as the raw payload *)
  | Niche   of { payload : Tir.ty; tagged : bool }  (* None=0, Some(x)=x (follow-on) *)

(* Look up a variant type definition by name. *)
let find_variant (type_defs : Tir.type_def list) (name : string)
    : (string * Tir.ty list) list option =
  List.find_map (function
    | Tir.TDVariant (n, variants) when n = name -> Some variants
    | _ -> None) type_defs

let repr_of_ty (type_defs : Tir.type_def list) (ty : Tir.ty) : repr =
  match ty with
  | Tir.TCon (name, _) ->
    (match find_variant type_defs name with
     (* Newtype: exactly one variant with exactly one field.
        Float payload is deferred (can't tag float bits safely); falls through to Boxed. *)
     | Some [ (_ctor, [ Tir.TFloat ]) ] -> Boxed
     | Some [ (_ctor, [ payload ]) ] -> Newtype payload
     | _ -> Boxed)
  | _ -> Boxed

(** True when a newtype payload value must be tagged [(v<<1)|1] before being stored
    in a ptr slot, to prevent IS_HEAP_PTR from treating the raw bits as a heap pointer.
    Applies to Int and Bool (and recursively to newtypes-over-scalars). *)
let rec payload_needs_tag (type_defs : Tir.type_def list) (ty : Tir.ty) : bool =
  match ty with
  | Tir.TInt | Tir.TBool -> true
  | Tir.TCon _ ->
    (match repr_of_ty type_defs ty with
     | Newtype inner -> payload_needs_tag type_defs inner
     | _ -> false)
  | _ -> false
