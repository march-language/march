(** Rc_types — canonical home for the two RC-relevance predicates.

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
    are plain heap values: RC'd and borrowable. *)

(** Perceus's predicate: true iff this type needs reference counting —
    Perceus must emit EIncRC/EDecRC ops for values of this type. Diverges
    from [borrow_eligible] on TFn / bare TVar (true here) and
    TTuple / TRecord (false here) — see the module doc before changing
    ANY arm. *)
let needs_rc : Tir.ty -> bool = function
  | Tir.TCon ("Atom", []) -> false  (* atoms are i64 scalars, not heap-allocated *)
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
    [needs_rc] on TTuple / TRecord (true here: 0b52510d record-liveness
    fix) and TFn / bare TVar (false here: closure-FV ownership contract) —
    see the module doc before changing ANY arm. *)
let borrow_eligible : Tir.ty -> bool = function
  | Tir.TCon ("Atom", []) -> false  (* atoms are i64 scalars, not heap-allocated *)
  | Tir.TCon _ | Tir.TString | Tir.TPtr _ -> true
  | Tir.TVar "_" -> true  (* lower.ml placeholder: conservatively heap-carrying *)
  | Tir.TRecord _ | Tir.TTuple _ -> true
    (* Records and tuples are heap-allocated (via march_alloc) and hold
       heap-carrying fields (Strings, ADT values, etc.). Making them
       borrow-eligible lets the fixpoint infer "cfg:borrowed" for functions
       that only read fields via EField, preventing Perceus from emitting
       dec_rc on the extracted field values when the owning caller still
       holds the record across multiple calls. *)
  | Tir.TVar _ | Tir.TInt | Tir.TFloat | Tir.TBool | Tir.TUnit
  | Tir.TFn _ -> false
    (* Closures / type-erased values never enter borrow inference: their
       ownership is managed by Perceus at capture/apply sites (closure-FV
       fix lineage — module doc). *)
