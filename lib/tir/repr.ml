(** P6 — derived representation table.

    A pure function of the MONOMORPHIC type: after monomorphization every type
    is concrete, so representation can be decided per type with no threading of
    state.  Leaving [Tir.ty] unchanged keeps the blast radius to the three
    consultation sites in [llvm_emit.ml].

    Milestone 1: [Boxed] and [Newtype].
    Milestone 2: [Niche] for Option-shaped types (one nullary + one single-field
    ctor).  None = raw 0, Some(x) = x (tagged when payload is a scalar). *)

type repr =
  | Boxed                                           (* heap cell with RC header + tag *)
  | Newtype of Tir.ty                               (* represented as raw payload *)
  | Niche   of { payload : Tir.ty; tagged : bool } (* None=0, Some(x)=x *)

(* Look up a variant type definition by name. *)
let find_variant (type_defs : Tir.type_def list) (name : string)
    : (string * Tir.ty list) list option =
  List.find_map (function
    | Tir.TDVariant (n, variants) when n = name -> Some variants
    | _ -> None) type_defs

(** True if [name] has the Option-shaped pattern: exactly one nullary ctor and
    exactly one single-field ctor (in either order).  Does NOT check whether the
    payload is niche-safe; use [niche_payload_ok] for that. *)
let is_niche_shaped (type_defs : Tir.type_def list) (name : string) : bool =
  match find_variant type_defs name with
  | Some [ (_nullary, []); (_single, [_]) ]
  | Some [ (_single, [_]); (_nullary, []) ] -> true
  | _ -> false

(** True when [ty] is safe for the raw-0 niche: its representation in a ptr slot
    is never raw 0, so [None=0] is unambiguous.
    Conservative: TVar/unknown types return false.

    Niche soundness:
    - Int/Bool: always stored as (v<<1)|1 (low-bit tagged), always odd → never 0.
    - String/TPtr/TCon(Boxed): heap pointers, march_alloc never returns 0.
    - TPtr values in ptr slots are EITHER tagged scalars (from i64→ptr coerce)
      or heap ptrs — never raw 0. (e.g., Bool false → (0<<1)|1 = 1, not 0.)
    - Float: 0.0 bitcasts to 0 — not safe.
    - Unit: represented as i64 0 → not safe.
    - TVar: unknown → conservative false. *)
let rec niche_payload_ok (type_defs : Tir.type_def list) (ty : Tir.ty) : bool =
  match ty with
  | Tir.TFloat | Tir.TUnit | Tir.TVar _ -> false
  | Tir.TCon _ ->
    (match repr_of_ty type_defs ty with
     | Niche _  -> false  (* nested niche: Some(None)=0=None *)
     | Newtype inner -> niche_payload_ok type_defs inner
     | Boxed -> true)     (* boxed heap ptr, march_alloc never returns 0 *)
  | _ -> true  (* TInt, TBool, TString, TPtr, TFn — never raw 0 in ptr slot *)

(** Classify a monomorphic type's runtime representation.
    [params] are the concrete type arguments of the TCon (e.g. [TInt] for
    Option(Int)).  When [params] is empty (as in EAlloc's ctor key), Option-shaped
    types fall back to [Boxed]; callers that have the concrete payload use
    [is_niche_shaped] + [niche_payload_ok] directly instead. *)
and repr_of_ty (type_defs : Tir.type_def list) (ty : Tir.ty) : repr =
  match ty with
  | Tir.TCon (name, params) ->
    (match find_variant type_defs name with
     (* Float-payload newtype: stay boxed (can't tag float bits safely). *)
     | Some [ (_ctor, [ Tir.TFloat ]) ] -> Boxed
     (* Newtype: exactly one variant with exactly one field. *)
     | Some [ (_ctor, [ payload ]) ] -> Newtype payload
     (* Option-shaped niche: one nullary + one single-field ctor.
        Concrete payload comes from the TCon's type params; if not present
        (params=[]) we cannot classify safely and return Boxed. *)
     | Some [ (_nullary, []); (_single, [_]) ]
     | Some [ (_single, [_]); (_nullary, []) ] ->
       (match params with
        | [p] when niche_payload_ok type_defs p ->
          Niche { payload = p; tagged = payload_needs_tag type_defs p }
        | _ -> Boxed)
     | _ -> Boxed)
  | _ -> Boxed

(** True when a payload value must be tagged [(v<<1)|1] before being stored in a
    ptr slot, to prevent IS_HEAP_PTR from treating the raw bits as a heap pointer.
    Applies to Int and Bool (and recursively to newtypes-over-scalars). *)
and payload_needs_tag (type_defs : Tir.type_def list) (ty : Tir.ty) : bool =
  match ty with
  | Tir.TInt | Tir.TBool -> true
  | Tir.TCon _ ->
    (match repr_of_ty type_defs ty with
     | Newtype inner -> payload_needs_tag type_defs inner
     | _ -> false)
  | _ -> false
