(** Repr — TRANSITIONAL holder of the process-global [Kind.table].

    Every classifier that used to live here is now in [Kind]
    (specs/2026-09-10-type-kinds-design.md).  What remains is the one thing
    [Kind] deliberately does not have: process-global state.  Until Phase 3
    of the type-kinds plan threads a [Kind.table] through
    [Contract_pipeline] and [Llvm_ctx.ctx], the pipeline registers a table
    here and the ~230 call sites that still take [(?collision_set, type_defs)]
    read through the wrappers below.

    The wrappers preserve the pre-Kind semantics EXACTLY: the call-site
    [type_defs] and [collision_set] decide shape and collision questions; the
    registered table decides the unboxed set.  [table_for] is what glues the
    two together.

    [_forced_off] is the process-wide latch the design document describes.
    It is kept here, unchanged, until Phase 3 replaces it with an argument;
    do not "fix" it in isolation, the tests that pin its removal are part of
    that phase. *)

type repr = Kind.repr =
  | Boxed
  | Newtype of Tir.ty
  | Niche   of { payload : Tir.ty; tagged : bool }
  | Unboxed of { ctor : string; fields : Tir.ty list }

let max_unboxed_arity = Kind.max_unboxed_arity
let is_scalar_field = Kind.is_scalar_field
let unboxed_llvm_name = Kind.unboxed_llvm_name

(* ── The registry: one table, its key, and the latch ─────────────────── *)

let _current : Kind.table option ref = ref None

(* The [type_defs] the current registration was derived from, so a later
   caller that knows LESS than the pipeline did (no extern list) can inherit
   the pipeline's answer instead of recomputing a different one.  See
   [ensure_unboxed_types]. *)
let _registered_from : Tir.type_def list option ref = ref None

(** Process-wide hard off switch.  The REPL/JIT sets it once ([Repl_jit],
    [Llvm_ctx.make_ctx ~repl:true]) so that no registration anywhere in the
    process — including the [ensure_unboxed_types] calls inside [Perceus] and
    [Escape], which cannot see who their caller is — can turn unboxing back on
    for a fragment.  Never cleared: a process either drives the REPL or it
    does not.  (Removed in Phase 3 of the type-kinds plan.) *)
let _forced_off = ref false

let force_disable () = _forced_off := true

(** Escape hatch: [MARCH_NO_UNBOX=1] classifies every type Boxed, restoring the
    pre-Milestone-3 representation for bisection. *)
let unboxing_disabled : bool Lazy.t =
  lazy (match Sys.getenv_opt "MARCH_NO_UNBOX" with
      | Some ("1" | "true" | "yes") -> true
      | _ -> false)

(* Transient tables built for call sites whose [(type_defs, collision_set)]
   differ from the registered table's, so their memo survives across calls.
   Keyed on PHYSICAL identity: two calls with the same list value get the same
   table.  Cleared whenever the registration changes, because every entry was
   derived from the registration's unboxed set. *)
let _cache : (Tir.type_def list * (string, string list) Hashtbl.t * Kind.table) list ref =
  ref []

let no_collisions : (string, string list) Hashtbl.t = Hashtbl.create 0

let current_or_empty () : Kind.table =
  match !_current with Some t -> t | None -> Kind.empty

let same_cs a b = a == b || (Hashtbl.length a = 0 && Hashtbl.length b = 0)

(** The table a call site with its own [type_defs] / [collision_set] should
    read.  Shares the registered unboxed set; uses the CALL-SITE type list and
    collision set for every shape / collision question, exactly as the old
    per-call functions did. *)
let table_for ~(collision_set : (string, string list) Hashtbl.t)
    (type_defs : Tir.type_def list) : Kind.table =
  match !_current with
  | Some t when Kind.type_defs t == type_defs && same_cs (Kind.collision_set t) collision_set -> t
  | _ ->
    (match List.find_opt (fun (td, cs, _) -> td == type_defs && same_cs cs collision_set) !_cache with
     | Some (_, _, t) -> t
     | None ->
       let t = Kind.rebind ~collision_set (current_or_empty ()) type_defs in
       let keep = match !_cache with a :: b :: c :: _ -> [a; b; c] | l -> l in
       _cache := (type_defs, collision_set, t) :: keep;
       t)

let unboxed_of_type_name (name : string) =
  Kind.unboxed_of_type_name (current_or_empty ()) name

let unboxed_of_llvm_ty (lty : string) =
  Kind.unboxed_of_llvm_ty (current_or_empty ()) lty

let unboxed_types () = Kind.unboxed_types (current_or_empty ())

let clear_unboxed_types () =
  _current := None; _registered_from := None; _cache := []

(** Recompute the registered table from [type_defs].  See [Kind.build] for
    the exclusions.  [enabled:false], the latch, and [MARCH_NO_UNBOX] all
    collapse into [Kind.build ~unboxing:false]. *)
let set_unboxed_types
    ?(collision_set : (string, string list) Hashtbl.t = no_collisions)
    ?(externs : Tir.extern_decl list = [])
    ?(enabled = true)
    (type_defs : Tir.type_def list) : unit =
  clear_unboxed_types ();
  _registered_from := Some type_defs;
  let unboxing = enabled && not !_forced_off && not (Lazy.force unboxing_disabled) in
  _current := Some (Kind.build ~externs ~unboxing ~collision_set type_defs)

(** Re-key the current registration to [type_defs] WITHOUT recomputing it —
    the pipeline decides the unboxed set once (after Defun) and later passes
    may still ADD type definitions; a type that appeared after the decision
    stays Boxed everywhere, which is conservative and consistent. *)
let rebind_registration (type_defs : Tir.type_def list) : unit =
  match !_current, !_registered_from with
  | Some t, Some _ ->
    _registered_from := Some type_defs;
    _current := Some (Kind.rebind t type_defs);
    _cache := []
  | _ -> ()

(** Register only if nothing has registered from these same [type_defs]. *)
let ensure_unboxed_types
    ?(collision_set : (string, string list) Hashtbl.t = no_collisions)
    (type_defs : Tir.type_def list) : unit =
  if !_forced_off then clear_unboxed_types ()
  else
    match !_registered_from with
    | Some tds when tds == type_defs || tds = type_defs -> ()
    | _ -> set_unboxed_types ~collision_set type_defs

(* ── Wrappers: the old signatures, answered by [Kind] ────────────────── *)

let find_variant (type_defs : Tir.type_def list) (name : string) =
  Kind.find_variant (table_for ~collision_set:no_collisions type_defs) name

let is_actor_struct_type (type_defs : Tir.type_def list) (name : string) : bool =
  Kind.is_actor_struct_type (table_for ~collision_set:no_collisions type_defs) name

let is_niche_shaped ?(collision_set = no_collisions)
    (type_defs : Tir.type_def list) (name : string) : bool =
  Kind.is_niche_shaped (table_for ~collision_set type_defs) name

let niche_payload_ok ?(collision_set = no_collisions)
    (type_defs : Tir.type_def list) (ty : Tir.ty) : bool =
  Kind.niche_payload_ok (table_for ~collision_set type_defs) ty

let repr_of_ty ?(collision_set = no_collisions)
    (type_defs : Tir.type_def list) (ty : Tir.ty) : repr =
  Kind.repr_of (table_for ~collision_set type_defs) ty

let payload_needs_tag ?(collision_set = no_collisions)
    (type_defs : Tir.type_def list) (ty : Tir.ty) : bool =
  Kind.payload_needs_tag (table_for ~collision_set type_defs) ty

let niche_repr_of_concrete ?(collision_set = no_collisions)
    (type_defs : Tir.type_def list) (name : string) : repr option =
  Kind.niche_repr_of_concrete (table_for ~collision_set type_defs) name
