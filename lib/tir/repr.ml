(** P6 — derived representation table.

    A pure function of the MONOMORPHIC type: after monomorphization every type
    is concrete, so representation can be decided per type with no threading of
    state.  Leaving [Tir.ty] unchanged keeps the blast radius to the three
    consultation sites in [llvm_emit.ml].

    Milestone 1: [Boxed] and [Newtype].
    Milestone 2: [Niche] for Option-shaped types (one nullary + one single-field
    ctor).  None = raw 0, Some(x) = x (tagged when payload is a scalar).

    Milestone 3: [Unboxed] for small scalar-only single-constructor variants
    ([Vec3(Float, Float, Float)]).  See the [Unboxed] section below. *)

type repr =
  | Boxed                                           (* heap cell with RC header + tag *)
  | Newtype of Tir.ty                               (* represented as raw payload *)
  | Niche   of { payload : Tir.ty; tagged : bool } (* None=0, Some(x)=x *)
  | Unboxed of { ctor : string; fields : Tir.ty list }
    (* inline LLVM struct value; no cell, no RC.  See [set_unboxed_types]. *)

(* ── Unboxed small scalar aggregates (Milestone 3) ─────────────────────

   A single-constructor variant whose fields are ALL scalars (Int / Float /
   Bool) and whose arity is 2..[max_unboxed_arity] is represented INLINE as an
   LLVM first-class struct value: [Vec3(Float, Float, Float)] is
   [{ double, double, double }] in registers.  No heap cell, no header, no
   reference counting.

   ── Why this table is a mutable registry rather than a pure function ──

   Every other classifier here is a pure function of [type_defs], because
   every consultation site has [type_defs] in scope.  The unboxed decision has
   two consultation sites that do NOT and cannot cheaply get one:

     - [Llvm_ctx.llvm_ty : Tir.ty -> string], the LLVM type mapping, called
       unqualified at ~100 sites across the emitter;
     - [Rc_types.needs_rc] / [Rc_types.borrow_eligible], the RC predicates,
       called from Perceus, Borrow and Drop on a bare [Tir.ty].

   Threading [type_defs] through both would touch every one of those sites.
   Instead the classification is computed ONCE per compilation unit from the
   module's own [tm_types] by [set_unboxed_types], and every site — including
   [repr_of_ty] below — reads the result.  Making [repr_of_ty] read the same
   table rather than re-deriving the predicate is deliberate and is the same
   discipline the actor-msg and collision-set exclusions above exist to
   enforce: encode ([Llvm_emit_alloc]), decode ([Llvm_case]), RC ([Perceus],
   [Borrow], [Drop]), escape analysis and the [@[no_alloc]] checker must never
   disagree about a type's representation.  One table read by all of them
   cannot split; two independent derivations can.

   Callers that must register:
     - [Contract_pipeline.run]  — before the first pass that consults it;
     - [Llvm_ctx.make_ctx]      — covers every other emitter entry point.

   Two consumers register the EMPTY table ([~enabled:false]), because neither
   can honour a struct-value ABI:
     - the JS backend: its runtime is GC'd and [Js_emit] has no arm for an
       inline aggregate;
     - the REPL / JIT: a fragment's result thunk is invoked as [void -> ptr]
       ([Repl_jit]'s [call_void_to_ptr]) and its value printed by walking a
       heap cell, so a fragment returning a struct in registers would be read
       as a pointer.  Fragments within one session all register the same empty
       table, so they stay consistent with each other.
   Both derive it from their module's [tm_types], and the derivation is a pure
   function of those, so repeated registration is idempotent.

   The JS backend registers the EMPTY table ([clear_unboxed_types]): its
   runtime is GC'd, has no struct-value ABI, and [Js_emit] has no arm for an
   inline aggregate. *)

(** Largest field count still represented inline.  Four 8-byte fields is 32
    bytes — two SysV/AAPCS64 register pairs — past which the struct is
    memory-passed by the C ABI and the copy costs more than the cell it
    replaces. *)
let max_unboxed_arity = 4

(* type name → (constructor short name, field types) *)
let _unboxed : (string, string * Tir.ty list) Hashtbl.t = Hashtbl.create 16

(* The [type_defs] the current registration was derived from, so a later
   caller that knows LESS than the pipeline did (no extern list) can inherit
   the pipeline's answer instead of recomputing a different one.  See
   [ensure_unboxed_types]. *)
let _registered_from : Tir.type_def list option ref = ref None

(* LLVM struct type name ("%ub.Vec3") → March type name.  The reverse
   direction, needed by [Llvm_ctx.coerce], which sees only LLVM type STRINGS
   and must recover the constructor tag and field types to box/unbox. *)
let _unboxed_by_llvm : (string, string) Hashtbl.t = Hashtbl.create 16

(** Process-wide hard off switch.  The REPL/JIT sets it once ([Repl_jit],
    [Llvm_ctx.make_ctx ~repl:true]) so that no registration anywhere in the
    process — including the [ensure_unboxed_types] calls inside [Perceus] and
    [Escape], which cannot see who their caller is — can turn unboxing back on
    for a fragment.  Never cleared: a process either drives the REPL or it
    does not. *)
let _forced_off = ref false

let force_disable () = _forced_off := true

(** Escape hatch: [MARCH_NO_UNBOX=1] classifies every type Boxed, restoring the
    pre-Milestone-3 representation for bisection. *)
let unboxing_disabled : bool Lazy.t =
  lazy (match Sys.getenv_opt "MARCH_NO_UNBOX" with
      | Some ("1" | "true" | "yes") -> true
      | _ -> false)

let is_scalar_field : Tir.ty -> bool = function
  | Tir.TInt | Tir.TFloat | Tir.TBool -> true
  | _ -> false

(** The LLVM identified-struct name for an unboxed type.  Dots (module
    qualification) become underscores; the ["%ub."] prefix cannot collide with
    a mangled March symbol, which [Llvm_ctx.llvm_name] never prefixes. *)
let unboxed_llvm_name (type_name : string) : string =
  "%ub." ^ String.map (fun c -> if c = '.' then '_' else c) type_name

(** Is [name] (a bare March TYPE name, never a "Type.Ctor" key) represented
    inline?  Answers from the registry — see the section comment. *)
let unboxed_of_type_name (name : string) : (string * Tir.ty list) option =
  Hashtbl.find_opt _unboxed name

(** March type name behind an LLVM struct type string, or [None] if the string
    is not an unboxed aggregate's type. *)
let unboxed_of_llvm_ty (lty : string) : (string * string * Tir.ty list) option =
  match Hashtbl.find_opt _unboxed_by_llvm lty with
  | None -> None
  | Some tname ->
    (match Hashtbl.find_opt _unboxed tname with
     | Some (ctor, fields) -> Some (tname, ctor, fields)
     | None -> None)

(** Every registered unboxed type, as (March type name, LLVM struct name,
    field types).  Used by [Llvm_toplevel.emit_module] to emit the
    [%ub.X = type { ... }] declarations, and by tests. *)
let unboxed_types () : (string * string * Tir.ty list) list =
  Hashtbl.fold (fun tname (_ctor, fields) acc ->
      (tname, unboxed_llvm_name tname, fields) :: acc) _unboxed []
  |> List.sort compare

let clear_unboxed_types () =
  Hashtbl.reset _unboxed; Hashtbl.reset _unboxed_by_llvm;
  _registered_from := None

(** Recompute the unboxed-type registry from [type_defs].  Idempotent and a
    pure function of its arguments; see the section comment for who calls it
    and why it is a registry at all.

    Exclusions, each mirroring an existing one above:
    - types crossing an [extern] signature ([externs]): the C side sees the
      BOXED cell (that is what [Llvm_ctx.coerce] hands it, and it is the
      layout every existing extern was written against), but the box is a
      fresh rc=1 cell that no one owns — [Rc_types.needs_rc] is false for the
      aggregate, so Perceus emits no caller-side drop and the box would leak
      once per call.  Keeping such a type Boxed end to end costs one
      representation and removes the whole question;
    - actor message types: need a runtime tag for foreign-message dispatch;
    - same-short-name colliding types: their globally-unique ctor tag must stay
      readable at a dispatch site that only knows the short name;
    - closure structs and actor state records: not [TDVariant] at all, so they
      cannot reach the shape test, but named here so the intent is on record. *)
let set_unboxed_types
    ?(collision_set : (string, string list) Hashtbl.t = Hashtbl.create 0)
    ?(externs : Tir.extern_decl list = [])
    ?(enabled = true)
    (type_defs : Tir.type_def list) : unit =
  clear_unboxed_types ();
  _registered_from := Some type_defs;
  if (not enabled) || !_forced_off || Lazy.force unboxing_disabled then ()
  else begin
    let ffi = Hashtbl.create 8 in
    List.iter (fun (ed : Tir.extern_decl) ->
        List.iter (function
            | Tir.TCon (n, _) -> Hashtbl.replace ffi n ()
            | _ -> ())
          (ed.Tir.ed_ret :: ed.Tir.ed_params))
      externs;
    List.iter (function
        | Tir.TDVariant (name, [ (ctor, fields) ])
          when List.length fields >= 2
            && List.length fields <= max_unboxed_arity
            && List.for_all is_scalar_field fields
            && not (Hashtbl.mem ffi name)
            && not (Tir_names.is_actor_msg_name name)
            && not (Tir_names.is_clo_struct name)
            && not (Collision_set.is_colliding collision_set name) ->
          Hashtbl.replace _unboxed name (ctor, fields);
          Hashtbl.replace _unboxed_by_llvm (unboxed_llvm_name name) name
        | _ -> ()) type_defs
  end

(** Re-key the current registration to [type_defs] WITHOUT recomputing it.

    The pipeline decides the unboxed set once, on the TIR shape its passes
    will reason about, and later passes may still ADD type definitions
    ([Defun]'s closure structs, an inliner's specialisations).  Recomputing
    from the final list could then admit a type the passes treated as Boxed —
    a representation split.  Re-keying instead means the emitter's
    [ensure_unboxed_types] recognises the final module as "already
    registered" and inherits the passes' answer verbatim; a type that appeared
    after the decision simply stays Boxed everywhere, which is conservative
    and consistent. *)
let rebind_registration (type_defs : Tir.type_def list) : unit =
  if !_registered_from <> None then _registered_from := Some type_defs

(** Register only if nothing has registered from these same [type_defs].

    [Contract_pipeline.run] registers with the module's extern list; an
    emitter entry point that reaches [Llvm_ctx.make_ctx] afterwards has the
    same [type_defs] but no extern list, and recomputing there would produce a
    LARGER set (no FFI exclusion) — an encode/decode representation split, the
    one failure mode this file's exclusions all exist to prevent.  Inheriting
    the earlier answer is what keeps the two in step; a caller that arrives
    first (a direct [Llvm_emit] call in a test, say) still gets a correct, if
    slightly conservative, registration of its own. *)
let ensure_unboxed_types
    ?(collision_set : (string, string list) Hashtbl.t = Hashtbl.create 0)
    (type_defs : Tir.type_def list) : unit =
  if !_forced_off then clear_unboxed_types ()
  else
    match !_registered_from with
    | Some tds when tds == type_defs || tds = type_defs -> ()
    | _ -> set_unboxed_types ~collision_set type_defs

(* Look up a variant type definition by name. *)
let find_variant (type_defs : Tir.type_def list) (name : string)
    : (string * Tir.ty list) list option =
  List.find_map (function
    | Tir.TDVariant (n, variants) when n = name -> Some variants
    | _ -> None) type_defs

(** True if [name] is a genuine actor struct — STRUCTURAL check, not a name
    heuristic.  [lower_actor.ml] always constructs an actor's state record as
    [TDRecord (name, ("$d_dispatch", TPtr TUnit) :: ("$e_alive", TBool) :: ...)],
    field 0 literally named ["$d_dispatch"].  Surface identifiers can never
    start with [$] (the lexer's [ident] rule is [alpha (alpha|digit|'\'')*]),
    so no user-declared record can ever have a field with this name — this
    predicate cannot false-positive on a user type, unlike a name-suffix check
    (e.g. [Tir_names.is_actor_struct_name] on a literal ["_Actor"] suffix, which
    a user-named type like [Tree_Actor] can coincidentally match).

    Used by [llvm_emit.ml]'s [EReuse] case (finding 20) to gate the actor-struct
    always-in-place mutation: that branch is UNSOUND for a non-actor value (it
    skips the refcount check FBIP relies on for shared-value safety), so the
    gate must never admit a false positive. *)
let is_actor_struct_type (type_defs : Tir.type_def list) (name : string) : bool =
  List.exists (function
    | Tir.TDRecord (n, (fname, _) :: _) -> n = name && fname = "$d_dispatch"
    | _ -> false) type_defs

(** True if [name] has the Option-shaped pattern: exactly one nullary ctor and
    exactly one single-field ctor (in either order).  Does NOT check whether the
    payload is niche-safe; use [niche_payload_ok] for that.

    Finding-19: actor message types (<Actor>_Msg) are excluded — they are FORCED
    Boxed (see repr_of_ty) so a foreign message can be told apart at dispatch by
    its globally-unique heap tag.  This predicate gates the EAlloc niche ENCODE
    path (llvm_emit.ml) and the llvm_case niche DECODE path; returning false here
    keeps BOTH on the Boxed path in lock-step, so a two-handler-one-nullary
    message shape is encoded and decoded as a tagged heap cell (no crash from an
    encode/decode repr split). *)
let is_niche_shaped ?(collision_set : (string, string list) Hashtbl.t = Hashtbl.create 0)
    (type_defs : Tir.type_def list) (name : string) : bool =
  if Tir_names.is_actor_msg_name name then false
  else if Collision_set.is_colliding collision_set name then false
  else
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
let rec niche_payload_ok
    ?(collision_set : (string, string list) Hashtbl.t = Hashtbl.create 0)
    (type_defs : Tir.type_def list) (ty : Tir.ty) : bool =
  match ty with
  | Tir.TFloat | Tir.TUnit | Tir.TVar _ -> false
  (* The empty tuple IS unit (the typechecker's t_unit = TTuple []), and its
     value representation is i64 0 — raw 0 in a ptr slot collides with the
     niche None.  Without this case Option(()) — e.g. `send`'s Option(Unit)
     result — classified Niche while the runtime returns BOXED Option cells:
     the boxed None (non-null) decoded as Some, so `send(dead_pid, M)`
     appeared delivered compiled while the interpreter said None. *)
  | Tir.TTuple [] -> false
  | Tir.TCon _ ->
    (match repr_of_ty ~collision_set type_defs ty with
     | Niche _  -> false  (* nested niche: Some(None)=0=None *)
     | Newtype inner -> niche_payload_ok ~collision_set type_defs inner
     | Unboxed _ -> true  (* boxed by [Llvm_ctx.coerce] on entry to a ptr slot,
                             so what the niche slot holds is a heap ptr *)
     | Boxed -> true)     (* boxed heap ptr, march_alloc never returns 0 *)
  | _ -> true  (* TInt, TBool, TString, TPtr, TFn — never raw 0 in ptr slot *)

(** Classify a monomorphic type's runtime representation.
    [params] are the concrete type arguments of the TCon (e.g. [TInt] for
    Option(Int)).  When [params] is empty (as in EAlloc's ctor key), Option-shaped
    types fall back to [Boxed]; callers that have the concrete payload use
    [is_niche_shaped] + [niche_payload_ok] directly instead.

    [collision_set] (Task 2, [Collision_set.compute]): a same-short-name type
    declared by >=2 modules is forced [Boxed] regardless of its ctor shape —
    same rationale as the actor-msg-name exclusion just below: a niche
    (unboxed/null) or newtype (no-tag) representation has no runtime tag slot,
    so a colliding type's globally-unique ctor tag (Task 1's
    [Llvm_toplevel.build_ctor_info]) would be unreadable at a dispatch site
    that only knows the short name. Defaults to the empty table (nothing
    colliding) so a caller that cannot supply the real collision set — because
    it genuinely has no [ctx]/type_defs-derived table in scope — gets the
    historical behavior unchanged. *)
and repr_of_ty
    ?(collision_set : (string, string list) Hashtbl.t = Hashtbl.create 0)
    (type_defs : Tir.type_def list) (ty : Tir.ty) : repr =
  match ty with
  (* Finding-19 memory-safety fix: force actor message variant types (<Actor>_Msg)
     to Boxed regardless of their ctor shape.  A single-handler actor's message
     would otherwise classify Newtype (raw payload, NO tag) and a two-handler
     one-nullary shape would classify Niche (null/non-null, no real tag) — in
     both cases a foreign message delivered to the wrong actor's mailbox carries
     no discriminant to distinguish it, so the dispatch would misroute its
     payload at the wrong type (memory-unsafe UB).  Boxed gives every message a
     heap-cell constructor tag; combined with globally-unique message tags
     (Llvm_toplevel.build_ctor_info) and the dispatch ECase's dropping default
     arm (lib/tir/lower_actor.ml), a foreign message's tag matches no branch and
     is dropped — parity with the interpreter's silent foreign-message drop.
     Consulted uniformly by EAlloc/ECase/Perceus/borrow, so encode, decode, and
     RC all agree on Boxed for these types. *)
  | Tir.TCon (name, _) when Tir_names.is_actor_msg_name name -> Boxed
  (* Task 2: same-short-name colliding type — force Boxed (see doc comment
     above) BEFORE the ctor-shape match, mirroring the actor-msg exclusion. *)
  | Tir.TCon (name, _) when Collision_set.is_colliding collision_set name -> Boxed
  (* Milestone 3: registered small scalar-only single-ctor variant.  The
     registry ALREADY applied the actor-msg and collision exclusions (see
     [set_unboxed_types]); the two arms above are kept ahead of this one so the
     ordering reads the same as the reasoning. *)
  | Tir.TCon (name, _) when unboxed_of_type_name name <> None ->
    (match unboxed_of_type_name name with
     | Some (ctor, fields) -> Unboxed { ctor; fields }
     | None -> Boxed (* unreachable: guard checked <> None *))
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
        | [p] when niche_payload_ok ~collision_set type_defs p ->
          Niche { payload = p; tagged = payload_needs_tag ~collision_set type_defs p }
        | _ -> Boxed)
     | _ -> Boxed)
  | _ -> Boxed

(** True when a payload value must be tagged [(v<<1)|1] before being stored in a
    ptr slot, to prevent IS_HEAP_PTR from treating the raw bits as a heap pointer.
    Applies to Int and Bool (and recursively to newtypes-over-scalars). *)
and payload_needs_tag
    ?(collision_set : (string, string list) Hashtbl.t = Hashtbl.create 0)
    (type_defs : Tir.type_def list) (ty : Tir.ty) : bool =
  match ty with
  | Tir.TInt | Tir.TBool -> true
  | Tir.TCon _ ->
    (match repr_of_ty ~collision_set type_defs ty with
     | Newtype inner -> payload_needs_tag ~collision_set type_defs inner
     (* Unboxed: what reaches a ptr slot is the BOX [Llvm_ctx.coerce] built,
        a real heap pointer — never a tagged immediate. *)
     | _ -> false)
  | _ -> false

(** Niche classification for a NON-GENERIC Option-shaped ADT (a [TCon] with no
    type params, e.g. an actor message type [Inc(Int) | Probe]).  [repr_of_ty]
    cannot classify these (it reads the payload from the TCon's params, which
    only generic instantiations like Option(Int) carry), but the variant
    definition's single-field ctor carries the concrete payload type directly.

    Returns [Some (Niche ...)] with the SAME payload/tagged classification the
    EAlloc/EReuse encode sites derive from their argument's type, or [None]
    when the payload is not niche-safe (e.g. Float) — in which case the encode
    sites box, and the decode site must fall back to Boxed to match.  Keeping
    encode and decode keyed on the same predicate is what guarantees a tagged
    scalar payload (Inc(10) stored as (10<<1)|1) is untagged again at the
    match binding; decoding it as tagged=false hands the raw tagged word to
    the branch body (observed as count = 21 + 11 instead of 10 + 5). *)
let niche_repr_of_concrete
    ?(collision_set : (string, string list) Hashtbl.t = Hashtbl.create 0)
    (type_defs : Tir.type_def list) (name : string)
    : repr option =
  (* Finding-19: actor message types are Boxed (see repr_of_ty) — never niche.
     Returning None keeps emit_case's concrete-niche recovery path on the Boxed
     heap-tag strategy for a two-handler-one-nullary message shape, matching the
     Boxed EAlloc encode. *)
  if Tir_names.is_actor_msg_name name then None
  (* Task 2: same-short-name colliding type — never niche, same rationale as
     [repr_of_ty]/[is_niche_shaped]. This function independently re-derives
     the ctor-shape classification for a NON-GENERIC TCon (see doc comment
     below) rather than delegating to [is_niche_shaped], so it needs its own
     exclusion — without it, a colliding type reached via a params-less TCon
     (e.g. an ECase scrutinee typed [TCon(name, [])]) would decode Niche here
     while the EAlloc encode side (gated on [is_niche_shaped]) encodes Boxed:
     an encode/decode repr split, the exact class of memory-unsafety bug this
     file's other exclusions guard against. *)
  else if Collision_set.is_colliding collision_set name then None
  else
  match find_variant type_defs name with
  | Some [ (_nullary, []); (_single, [ p ]) ]
  | Some [ (_single, [ p ]); (_nullary, []) ] ->
    (match p with
     (* Erased payload in the def (generic type reached without params):
        keep the erased convention — values are uniform (heap ptr raw /
        scalar tagged), untagged at their concrete use sites. *)
     | Tir.TVar _ -> Some (Niche { payload = p; tagged = false })
     | _ ->
       if niche_payload_ok ~collision_set type_defs p
       then Some (Niche { payload = p; tagged = payload_needs_tag ~collision_set type_defs p })
       else None)
  | _ -> None
