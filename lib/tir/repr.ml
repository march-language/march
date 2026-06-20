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

let repr_of_ty (_type_defs : Tir.type_def list) (_ty : Tir.ty) : repr =
  Boxed
