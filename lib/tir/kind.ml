(* See kind.mli for the overview and specs/2026-09-10-type-kinds-design.md for
   the design.  Every classifier below is a VERBATIM port of the function it
   replaces in repr.ml / rc_types.ml / llvm_ctx.ml, with the process-global
   registry read replaced by a lookup in the table.  The doc comments came
   with them: they are the fix history and must stay with the arms. *)

type repr =
  | Boxed
  | Newtype of Tir.ty
  | Niche   of { payload : Tir.ty; tagged : bool }
  | Unboxed of { ctor : string; fields : Tir.ty list }

type layout = Imm | Flt | Vec of int | Agg of string | Heap | Cell | Erased

type kind = {
  layout       : layout;
  repr         : repr;
  llvm_ty      : string;
  needs_rc     : bool;
  borrowable   : bool;
  niche_ok     : bool;
  needs_tag    : bool;
  closure_free : bool;
  float_free   : bool;
}

type table = {
  k_type_defs       : Tir.type_def list;
  k_collision       : (string, string list) Hashtbl.t;
  (* type name → (constructor short name, field types) *)
  k_unboxed         : (string, string * Tir.ty list) Hashtbl.t;
  (* LLVM struct type name ("%ub.Vec3") → March type name *)
  k_unboxed_by_llvm : (string, string) Hashtbl.t;
  k_memo            : (Tir.ty, kind) Hashtbl.t;
}

let type_defs t = t.k_type_defs
let collision_set t = t.k_collision

(* ── Unboxed aggregates (Milestone 3) — ported from repr.ml ──────────── *)

let max_unboxed_arity = 4

let is_scalar_field : Tir.ty -> bool = function
  | Tir.TInt | Tir.TFloat | Tir.TBool -> true
  | _ -> false

(** The LLVM identified-struct name for an unboxed type.  Dots (module
    qualification) become underscores; the ["%ub."] prefix cannot collide with
    a mangled March symbol, which [Llvm_ctx.llvm_name] never prefixes. *)
let unboxed_llvm_name (type_name : string) : string =
  "%ub." ^ String.map (fun c -> if c = '.' then '_' else c) type_name

(** Exclusions, each mirroring one that existed before this table:
    - types crossing an [extern] signature ([externs]): the C side sees the
      BOXED cell (that is what [Llvm_ctx.coerce] hands it, and it is the
      layout every existing extern was written against), but the box is a
      fresh rc=1 cell that no one owns — [needs_rc] is false for the
      aggregate, so Perceus emits no caller-side drop and the box would leak
      once per call.  Keeping such a type Boxed end to end costs one
      representation and removes the whole question;
    - actor message types: need a runtime tag for foreign-message dispatch;
    - same-short-name colliding types: their globally-unique ctor tag must stay
      readable at a dispatch site that only knows the short name;
    - closure structs and actor state records: not [TDVariant] at all, so they
      cannot reach the shape test, but named here so the intent is on record. *)
let build ?(externs : Tir.extern_decl list = []) ?(unboxing = true)
    ~(collision_set : (string, string list) Hashtbl.t)
    (type_defs : Tir.type_def list) : table =
  let k_unboxed = Hashtbl.create 16 in
  let k_unboxed_by_llvm = Hashtbl.create 16 in
  if unboxing then begin
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
          Hashtbl.replace k_unboxed name (ctor, fields);
          Hashtbl.replace k_unboxed_by_llvm (unboxed_llvm_name name) name
        | _ -> ()) type_defs
  end;
  { k_type_defs = type_defs; k_collision = collision_set;
    k_unboxed; k_unboxed_by_llvm; k_memo = Hashtbl.create 64 }

let rebind ?collision_set (t : table) (type_defs : Tir.type_def list) : table =
  let k_collision = match collision_set with Some cs -> cs | None -> t.k_collision in
  { t with k_type_defs = type_defs; k_collision; k_memo = Hashtbl.create 64 }

let empty : table = build ~unboxing:false ~collision_set:(Hashtbl.create 0) []

let unboxed_of_type_name (t : table) (name : string) =
  Hashtbl.find_opt t.k_unboxed name

let unboxed_of_llvm_ty (t : table) (lty : string) =
  match Hashtbl.find_opt t.k_unboxed_by_llvm lty with
  | None -> None
  | Some tname ->
    (match Hashtbl.find_opt t.k_unboxed tname with
     | Some (ctor, fields) -> Some (tname, ctor, fields)
     | None -> None)

let unboxed_types (t : table) : (string * string * Tir.ty list) list =
  Hashtbl.fold (fun tname (_ctor, fields) acc ->
      (tname, unboxed_llvm_name tname, fields) :: acc) t.k_unboxed []
  |> List.sort compare

(* ── Shape helpers — ported from repr.ml ─────────────────────────────── *)

let find_variant (t : table) (name : string)
  : (string * Tir.ty list) list option =
  List.find_map (function
    | Tir.TDVariant (n, variants) when n = name -> Some variants
    | _ -> None) t.k_type_defs

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
let is_actor_struct_type (t : table) (name : string) : bool =
  List.exists (function
    | Tir.TDRecord (n, (fname, _) :: _) -> n = name && fname = "$d_dispatch"
    | _ -> false) t.k_type_defs

(** True if [name] has the Option-shaped pattern: exactly one nullary ctor and
    exactly one single-field ctor (in either order).  Does NOT check whether the
    payload is niche-safe; use [niche_ok] for that.

    Finding-19: actor message types (<Actor>_Msg) are excluded — they are FORCED
    Boxed (see [repr_of]) so a foreign message can be told apart at dispatch by
    its globally-unique heap tag.  This predicate gates the EAlloc niche ENCODE
    path (llvm_emit.ml) and the llvm_case niche DECODE path; returning false here
    keeps BOTH on the Boxed path in lock-step, so a two-handler-one-nullary
    message shape is encoded and decoded as a tagged heap cell (no crash from an
    encode/decode repr split). *)
let is_niche_shaped (t : table) (name : string) : bool =
  if Tir_names.is_actor_msg_name name then false
  else if Collision_set.is_colliding t.k_collision name then false
  else
  match find_variant t name with
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
let rec niche_payload_ok (t : table) (ty : Tir.ty) : bool =
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
    (match repr_of t ty with
     | Niche _  -> false  (* nested niche: Some(None)=0=None *)
     | Newtype inner -> niche_payload_ok t inner
     | Unboxed _ -> true  (* boxed by [Llvm_ctx.coerce] on entry to a ptr slot,
                             so what the niche slot holds is a heap ptr *)
     | Boxed -> true)     (* boxed heap ptr, march_alloc never returns 0 *)
  | _ -> true  (* TInt, TBool, TString, TPtr, TFn — never raw 0 in ptr slot *)

(** Classify a monomorphic type's runtime representation.
    [params] are the concrete type arguments of the TCon (e.g. [TInt] for
    Option(Int)).  When [params] is empty (as in EAlloc's ctor key), Option-shaped
    types fall back to [Boxed]; callers that have the concrete payload use
    [is_niche_shaped] + [niche_ok] directly instead.

    [collision_set]: a same-short-name type declared by >=2 modules is forced
    [Boxed] regardless of its ctor shape — same rationale as the actor-msg-name
    exclusion just below: a niche (unboxed/null) or newtype (no-tag)
    representation has no runtime tag slot, so a colliding type's
    globally-unique ctor tag ([Llvm_toplevel.build_ctor_info]) would be
    unreadable at a dispatch site that only knows the short name. *)
and repr_of (t : table) (ty : Tir.ty) : repr =
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
  (* Same-short-name colliding type — force Boxed (see doc comment above)
     BEFORE the ctor-shape match, mirroring the actor-msg exclusion. *)
  | Tir.TCon (name, _) when Collision_set.is_colliding t.k_collision name -> Boxed
  (* Milestone 3: small scalar-only single-ctor variant.  [build] ALREADY
     applied the actor-msg and collision exclusions; the two arms above are
     kept ahead of this one so the ordering reads the same as the reasoning. *)
  | Tir.TCon (name, _) when Hashtbl.mem t.k_unboxed name ->
    (match Hashtbl.find_opt t.k_unboxed name with
     | Some (ctor, fields) -> Unboxed { ctor; fields }
     | None -> Boxed (* unreachable: guard checked mem *))
  | Tir.TCon (name, params) ->
    (match find_variant t name with
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
        | [p] when niche_payload_ok t p ->
          Niche { payload = p; tagged = payload_needs_tag t p }
        | _ -> Boxed)
     | _ -> Boxed)
  | _ -> Boxed

(** True when a payload value must be tagged [(v<<1)|1] before being stored in a
    ptr slot, to prevent IS_HEAP_PTR from treating the raw bits as a heap pointer.
    Applies to Int and Bool (and recursively to newtypes-over-scalars). *)
and payload_needs_tag (t : table) (ty : Tir.ty) : bool =
  match ty with
  | Tir.TInt | Tir.TBool -> true
  | Tir.TCon _ ->
    (match repr_of t ty with
     | Newtype inner -> payload_needs_tag t inner
     (* Unboxed: what reaches a ptr slot is the BOX [Llvm_ctx.coerce] built,
        a real heap pointer — never a tagged immediate. *)
     | _ -> false)
  | _ -> false

(** Niche classification for a NON-GENERIC Option-shaped ADT (a [TCon] with no
    type params, e.g. an actor message type [Inc(Int) | Probe]).  [repr_of]
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
let niche_repr_of_concrete (t : table) (name : string) : repr option =
  (* Finding-19: actor message types are Boxed (see [repr_of]) — never niche. *)
  if Tir_names.is_actor_msg_name name then None
  (* Same-short-name colliding type — never niche, same rationale as
     [repr_of]/[is_niche_shaped].  This function independently re-derives the
     ctor-shape classification for a NON-GENERIC TCon rather than delegating
     to [is_niche_shaped], so it needs its own exclusion — without it, a
     colliding type reached via a params-less TCon (e.g. an ECase scrutinee
     typed [TCon(name, [])]) would decode Niche here while the EAlloc encode
     side (gated on [is_niche_shaped]) encodes Boxed: an encode/decode repr
     split, the exact class of memory-unsafety bug these exclusions guard
     against. *)
  else if Collision_set.is_colliding t.k_collision name then None
  else
  match find_variant t name with
  | Some [ (_nullary, []); (_single, [ p ]) ]
  | Some [ (_single, [ p ]); (_nullary, []) ] ->
    (match p with
     (* Erased payload in the def (generic type reached without params):
        keep the erased convention — values are uniform (heap ptr raw /
        scalar tagged), untagged at their concrete use sites. *)
     | Tir.TVar _ -> Some (Niche { payload = p; tagged = false })
     | _ ->
       if niche_payload_ok t p
       then Some (Niche { payload = p; tagged = payload_needs_tag t p })
       else None)
  | _ -> None

(* ── Reference counting — ported from rc_types.ml ────────────────────── *)

(* ── The following module doc is moved VERBATIM from rc_types.ml (retired by the
   type-kinds plan).  It is the fix history for needs_rc / borrowable; the only
   edits are the module name in its first line and nothing else. ── *)

(* (formerly Rc_types) — canonical home for the two RC-relevance predicates.

    [needs_rc] (Perceus's question) and [borrow_eligible] (Borrow's
    question) were historically two independently-maintained copies both
    named [needs_rc] — one in perceus.ml, one in borrow.ml, the latter
    tagged "duplicated to avoid a cyclic module dependency". They are NOT
    the same predicate: they deliberately disagree on FOUR constructor
    patterns, and each disagreement is load-bearing with its own fix
    history. Before Wave 3 Task 2 only the TFn/TVar half of that divergence
    was written down anywhere; this module is the named, documented,
    unit-tested contract for all of it (the pinning test lives in
    test/test_codegen.ml, "rc_types" group). Both functions are
    byte-identical moves of the copies they replace — no behavior change.

    The two questions:
    - [needs_rc ty] — "must Perceus emit EIncRC/EDecRC to track the
      lifetime of a value of this type?" (RC-op emission).
    - [borrow_eligible ty] — "may Borrow's fixpoint consider a parameter of
      this type for the borrowed (non-owning) calling convention?"
      (inference eligibility).

    Truth table over all 11 [Tir.ty] constructors (★ = divergent):

    {v
      constructor          needs_rc   borrow_eligible
      TCon ("Atom", [])    false      false            (atoms are i64 scalars)
      TCon <unboxed>       false      false            (inline struct, no cell)
      TCon _               true       true
      TString              true       true
      TPtr _               true       true
      TVar "_"             true       true             (lower.ml placeholder)
      TVar _             ★ true       false
      TFn _              ★ true       false
      TTuple _             true       true
      TRecord _            true       true
      TInt TFloat
      TBool TUnit          false      false
    v}

    ── Why TFn / bare TVar diverge (needs_rc TRUE, borrow_eligible FALSE) ──

    Perceus side (true): after defun, any AVar with a TFn type is a
    heap-allocated closure struct — never a raw code pointer (those are
    ADefRef and never appear in AVar liveness). llvm_ty (TFn _) = "ptr" and
    llvm_emit guards every RC op with [if ty = "ptr" then …], so emitting
    EIncRC/EDecRC for TFn variables is both necessary (to track the
    closure's lifetime) and safe. needs_rc (TFn _) = false was the root
    cause of the Map.fold crash: the closure parameter f in Map.node_fold
    was invisible to Perceus, so (a) no EIncRC before storing f in the go
    closure, (b) no EDecRC in the HEmpty branch where f is unused, (c) no
    EIncRC in apply functions before lending f to recursive calls.
    Similarly a bare TVar (an unresolved user type-var that leaks into
    monomorphic TIR when a concrete type is not propagated across a module
    boundary, e.g. an opaque [Gate.cast] result staying ['_NNNN]) is a heap
    pointer at runtime (llvm_ty (TVar _) = "ptr"); needs_rc (TVar _) =
    false made such values invisible to Perceus — no EIncRC before a
    consuming call, so consuming the same binding twice double-freed it
    (the bastion Gate.cast RC-underflow UAF).

    Borrow side (false): closures and type-erased values must NOT enter
    borrow inference — the closure-FV ownership fix history (a705cc95,
    d2cf09e "closure FVs stay owned by their closure struct", fd520110
    "closure FVs captured for __try_call* are borrowed, not owned", and the
    generalization in 78e31ff7) all landed exactly on this boundary:
    ownership of a closure and of the FVs reachable through it is managed
    by Perceus at capture/apply sites, and letting the fixpoint reclassify
    TFn/TVar params as "borrowed" changes who is responsible for the dec —
    the callee stops dec'ing but Perceus's capture-site accounting still
    assumes ownership transfer, leaking or double-freeing the closure box.
    If you flip borrow_eligible (TFn _) to true, expect the __try_call /
    join-point closure-capture regressions those commits fixed to return.
    If you flip needs_rc (TFn _ | TVar _) to false, expect the Map.fold
    crash and the Gate.cast UAF class to return.

    ── TTuple / TRecord: both TRUE (they no longer diverge) ──

    Aggregates own their fields and are DEEP-dropped at death, exactly like
    variants: Drop.aggregate_fields gives them a synthesized __drop$R/__drop$T
    that projects each field with EField and releases it behind the
    march_decrc_freed guard.

    needs_rc was FALSE here until the aggregate-RC change, on the reasoning
    that "the aggregate is never RC-freed and its fields belong to it".  The
    second half is true; the first half was the bug.  Nothing ever decided an
    aggregate was dead, so every record and tuple cell leaked, and so did every
    heap value it owned — measured at ~200k leaked strings plus ~200k leaked
    cells for a 200k-iteration loop rebuilding a { n : Int, s : String }, where
    the equivalent two-field variant leaked nothing.

    The READ path is unchanged and still does the work its bug history
    describes: [borrowed_field_vars] (perceus_core.ml) tracks variables
    extracted from a live aggregate via EField and suppresses RC ops on them,
    dup'ing instead at any consuming position so an escaping field outlives the
    aggregate (390dff00 bug #4, the Toml get_str pair-list corruption: fields
    of a borrowed-derived aggregate were freed while the aggregate lived).

    That 390dff00 warning used to be stated as "flipping needs_rc to true gives
    double-frees on tuple/record fields".  It constrains the READ path, not the
    death path, and the two are orthogonal — an aggregate's drop releases only
    the references the aggregate itself still holds.  What the warning does
    still forbid is releasing a field that [borrowed_field_vars] has already
    handed to someone else; keep that mechanism intact.

    Two adjacent invariants the death path depends on, both easy to break:
      - EField must NOT run its source through [find_inc_vars]: projection is a
        BORROW, not a consuming position, and dup'ing the aggregate there leaks
        one reference per field read.
      - the scope-end drop in insert_rc_expr's ELet case must fire only when the
        aggregate's every use is an EField source ([used_only_as_field_source]).
        At a consuming position ownership has already transferred; dropping as
        well frees the consumer's cell (seen as a SIGBUS on
        `alloc Box.Box(n, r); dec_rc r`).

    Borrow side (true): record/tuple params must be ELIGIBLE for borrow
    inference so the fixpoint can mark functions that only read fields via
    EField as "cfg:borrowed" (0b52510d). With borrow_eligible (TRecord _) =
    false, such functions were inferred cfg:own, Perceus dec'd the
    extracted string field at last-use inside the callee, and a second call
    in the same loop arm read a freed string — "local RC underflow" (the
    record-liveness multi-call bug). If you flip borrow_eligible
    (TTuple/TRecord) to false, that class returns.

    ── Shared arms (kept in sync by construction now) ──

    TCon ("Atom", []): atoms are i64 scalars, not heap-allocated — no RC,
    no borrow. TVar "_": lower.ml's placeholder for ECase br_vars / closure
    params; conservatively heap-carrying. llvm_emit guards all RC calls
    with [if ty = "ptr" then …], so emitting EIncRC/EDecRC for a scalar
    TVar "_" is safe — the guard prevents the actual C call from firing.
    Scalars (TInt/TFloat/TBool/TUnit) are unboxed; TString/TPtr/other TCon
    are plain heap values: RC'd and borrowable.

    ── The [Repr.Unboxed] row (both FALSE, added with Milestone 3) ──

    A small scalar-only single-constructor variant ([Vec3(Float, Float,
    Float)]) is represented as an LLVM struct VALUE, not a heap cell: there is
    no header to hold a refcount and [Llvm_ctx.llvm_ty] gives it a struct type
    rather than ["ptr"].  Both predicates must say false, for two different
    reasons.

    needs_rc false: there is nothing to count.  Leaving it true would be
    *nearly* harmless — [llvm_emit] guards every RC call with
    [if ty = "ptr"], and a struct-typed value fails that guard — but only
    nearly: Perceus's liveness would still treat such a value as an owned
    resource, and [Drop.run] would synthesize a [__drop$T] helper for a type
    with no cell to free.  Answering the question honestly is cheaper than
    relying on a downstream guard, and it is what makes the [@[no_alloc]]
    verdict for a [Vec3]-returning function come out as "no allocation".

    borrow_eligible false: borrowing is a statement about who releases a
    reference.  An inline aggregate is COPIED at every call boundary (the
    struct is passed in registers), so there is no reference and no releasing
    party; admitting it to the fixpoint would let [Borrow.is_borrowed] answer
    "borrowed" for a parameter whose ownership question is meaningless, and
    Milestone-3's stack-promotion extension (which reads exactly that answer
    to decide a value does not escape through a call) would then be reasoning
    about a value that was never on the heap.

    Both arms read [Repr.unboxed_of_type_name], the SAME registry
    [Llvm_ctx.llvm_ty], [Llvm_emit_alloc] and [Llvm_case] read — see the
    registry's own comment in [repr.ml] for why one shared table rather than
    two derivations. *)

(** True iff [ty] is a [Repr.Unboxed] aggregate: an inline struct value with
    no heap cell, no header and therefore no refcount. *)



(** Perceus's predicate: true iff this type needs reference counting —
    Perceus must emit EIncRC/EDecRC ops for values of this type. Diverges
    from [borrowable] on TFn / bare TVar (true here) and on TTuple / TRecord
    — see the module doc before changing ANY arm. *)
let needs_rc_of (t : table) : Tir.ty -> bool = function
  | Tir.TCon ("Atom", []) -> false  (* atoms are i64 scalars, not heap-allocated *)
  | Tir.TCon (n, _) when Hashtbl.mem t.k_unboxed n -> false
    (* inline struct value: no cell, no header, nothing to count — module doc *)
  | Tir.TCon _ | Tir.TString | Tir.TPtr _ -> true
  | Tir.TVar "_" -> true  (* lower.ml placeholder: conservatively heap-carrying *)
  | Tir.TVar _ -> true    (* unresolved cross-module type-var: heap ptr at runtime
                             (Gate.cast RC-underflow UAF — module doc) *)
  | Tir.TFn _ -> true     (* defunctionalized closure struct (Map.fold crash —
                             module doc) *)
  | Tir.TTuple _ | Tir.TRecord _ -> true
    (* Aggregates own their fields and are DEEP-dropped at death, exactly like
       variants (see the module doc's TTuple/TRecord section).  Was false, which
       meant Perceus never decided an aggregate was dead: every record and tuple
       cell leaked, and so did every heap value it owned. *)
  | Tir.TInt | Tir.TFloat | Tir.TBool | Tir.TUnit -> false

(** Borrow's predicate: true iff a parameter of this type may enter borrow
    inference (the borrowed-calling-convention fixpoint). Diverges from
    [needs_rc] on TTuple / TRecord and TFn / bare TVar — see the module doc
    before changing ANY arm. *)
let borrowable_of (t : table) : Tir.ty -> bool = function
  | Tir.TCon ("Atom", []) -> false  (* atoms are i64 scalars, not heap-allocated *)
  | Tir.TCon (n, _) when Hashtbl.mem t.k_unboxed n -> false
    (* copied at every boundary; no reference, so no ownership — module doc *)
  | Tir.TCon _ | Tir.TString | Tir.TPtr _ -> true
  | Tir.TVar "_" -> true  (* lower.ml placeholder: conservatively heap-carrying *)
  | Tir.TRecord _ | Tir.TTuple _ -> false
    (* Aggregates are OWNED parameters, not borrowed ones.  A borrowed
       aggregate parameter leaves the caller responsible for the release, and
       in a SELF-TAIL-RECURSIVE loop that release is unreachable: it sits after
       the tail call, llvm_tco folds the call into a back-edge, and the dec is
       discarded (llvm_tco.ml's has_self_tail_call says so outright -- "the
       EDecRC lands in dead code after TCO emits the back-edge").  Every
       iteration then leaks its aggregate.  It cannot simply be emitted before
       the back-edge either: that would free the cell the next iteration reads.

       Ownership fixes it uniformly -- each iteration releases the aggregate it
       was handed before jumping with a new one, so the loop runs in constant
       space -- and it is what makes the parameter drop site in
       [Perceus.insert_owned_aggregate_param_drops] reachable at all.

       The historical reason this was true (0b52510d, the record-liveness
       multi-call bug) was about a field EXTRACTED from the record being dec'd
       at its last use inside the callee.  That is the [borrowed_field_vars]
       mechanism's job and it still does it; what changes here is only who
       releases the AGGREGATE.  The two tests that pinned the old behaviour
       asserted "no EDecRC anywhere in the callee" as a proxy for "no dec of
       the extracted field" -- see their updated forms in test_eval.ml. *)
  | Tir.TVar _ | Tir.TInt | Tir.TFloat | Tir.TBool | Tir.TUnit
  | Tir.TFn _ -> false
    (* Closures / type-erased values never enter borrow inference: their
       ownership is managed by Perceus at capture/apply sites (closure-FV
       fix lineage — module doc). *)

(* ── LLVM spelling — ported from llvm_ctx.ml ─────────────────────────── *)

let llvm_ty_of (t : table) : Tir.ty -> string = function
  | Tir.TInt    -> "i64"
  | Tir.TFloat  -> "double"
  | Tir.TBool   -> "i64"   (* booleans as i64 for uniform field layout *)
  | Tir.TUnit   -> "i64"   (* unit = i64 0 *)
  | Tir.TString -> "ptr"
  | Tir.TCon ("Atom", []) -> "i64"  (* atoms are interned i64 hashes, not heap ptrs *)
  (* Milestone 3: a small scalar-only single-ctor variant is an LLVM struct
     VALUE — [{ double, double, double }] for [Vec3(Float, Float, Float)] —
     passed and returned in registers, never a cell.  The identified struct
     type is declared once per module by [Llvm_toplevel.emit_module] from
     [unboxed_types]; this mapping, the construction, the destructuring and
     the RC treatment all read the SAME table so they can never disagree. *)
  | Tir.TCon (name, _) when Hashtbl.mem t.k_unboxed name -> unboxed_llvm_name name
  | Tir.TCon _  -> "ptr"
  | Tir.TTuple _ -> "ptr"
  | Tir.TRecord _ -> "ptr"
  | Tir.TFn _   -> "ptr"
  | Tir.TPtr _  -> "ptr"
  | Tir.TVar _  -> "ptr"   (* pre-mono fallback *)

(* ── Layout (informational; unread) ──────────────────────────────────── *)

(* March-level SIMD vector TCon names and their runtime kind tags, in the
   order [Llvm_ctx.vec_tys] assigns them (0=f32x4 1=f64x2 2=i32x4 3=i64x2
   4=u8x16).  These types are "boxed at rest, native in kernels": [llvm_ty]
   deliberately says "ptr" for them, so [Vec] is a statement about what the
   value IS, not about the slot it sits in. *)
let simd_tag_of_name (name : string) : int option =
  let short = match String.rindex_opt name '.' with
    | Some i -> String.sub name (i + 1) (String.length name - i - 1)
    | None -> name in
  match short with
  | "F32x4" -> Some 0 | "F64x2" -> Some 1 | "I32x4" -> Some 2
  | "I64x2" -> Some 3 | "U8x16" -> Some 4 | _ -> None

let layout_of (t : table) : Tir.ty -> layout = function
  | Tir.TInt | Tir.TBool | Tir.TUnit -> Imm
  | Tir.TCon ("Atom", []) -> Imm
  | Tir.TFloat -> Flt
  | Tir.TCon (name, _) when Hashtbl.mem t.k_unboxed name -> Agg (unboxed_llvm_name name)
  | Tir.TCon (name, _) when simd_tag_of_name name <> None ->
    (match simd_tag_of_name name with Some n -> Vec n | None -> Heap)
  | Tir.TTuple _ | Tir.TRecord _ -> Cell
  | Tir.TVar _ -> Erased
  | Tir.TCon _ | Tir.TString | Tir.TFn _ | Tir.TPtr _ -> Heap

(* ── Deep crossing facts (informational; unread) ─────────────────────── *)

(* Walk everything reachable from [ty] through constructor arguments and
   record fields.  [visited] is keyed by TCon name so recursive and mutually
   recursive types terminate; a visited name contributes nothing further,
   which is the right fixpoint for a "no X reachable" predicate. *)
let rec reachable_has (t : table) (visited : (string, unit) Hashtbl.t)
    (pred : Tir.ty -> bool) (ty : Tir.ty) : bool =
  pred ty ||
  match ty with
  | Tir.TTuple ts -> List.exists (reachable_has t visited pred) ts
  | Tir.TRecord fs -> List.exists (fun (_, f) -> reachable_has t visited pred f) fs
  | Tir.TFn (args, ret) -> List.exists (reachable_has t visited pred) (ret :: args)
  | Tir.TPtr inner -> reachable_has t visited pred inner
  | Tir.TCon (name, params) ->
    List.exists (reachable_has t visited pred) params
    || (if Hashtbl.mem visited name then false
        else begin
          Hashtbl.replace visited name ();
          List.exists (function
              | Tir.TDVariant (n, ctors) when n = name ->
                List.exists (fun (_, fields) ->
                    List.exists (reachable_has t visited pred) fields) ctors
              | Tir.TDRecord (n, fields) when n = name ->
                List.exists (fun (_, f) -> reachable_has t visited pred f) fields
              | Tir.TDClosure (n, fields) when n = name ->
                (* a closure struct IS a closure for [closure_free]'s purposes,
                   and its captures may carry anything for [float_free]'s *)
                pred (Tir.TFn ([], Tir.TUnit))
                || List.exists (reachable_has t visited pred) fields
              | _ -> false) t.k_type_defs
        end)
  | Tir.TInt | Tir.TFloat | Tir.TBool | Tir.TString | Tir.TUnit | Tir.TVar _ -> false

let closure_free_of (t : table) (ty : Tir.ty) : bool =
  not (reachable_has t (Hashtbl.create 8)
         (function Tir.TFn _ -> true
                 | Tir.TCon (n, _) -> Tir_names.is_clo_struct n
                 | _ -> false) ty)

let float_free_of (t : table) (ty : Tir.ty) : bool =
  not (reachable_has t (Hashtbl.create 8)
         (function Tir.TFloat -> true | _ -> false) ty)

(* ── The record ──────────────────────────────────────────────────────── *)

let of_ty (t : table) (ty : Tir.ty) : kind =
  match Hashtbl.find_opt t.k_memo ty with
  | Some k -> k
  | None ->
    let k = {
      layout       = layout_of t ty;
      repr         = repr_of t ty;
      llvm_ty      = llvm_ty_of t ty;
      needs_rc     = needs_rc_of t ty;
      borrowable   = borrowable_of t ty;
      niche_ok     = niche_payload_ok t ty;
      needs_tag    = payload_needs_tag t ty;
      closure_free = closure_free_of t ty;
      float_free   = float_free_of t ty;
    } in
    Hashtbl.replace t.k_memo ty k;
    k
