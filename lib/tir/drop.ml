(** Drop — deep-drop synthesis for aggregates released without destructuring.

    {1 The gap this closes}

    March frees an aggregate by DESTRUCTURING it.  When a [case] arm owns its
    scrutinee, [llvm_case.ml] emits [march_decrc_freed] on the box and, on the
    shared (RC > 1) path, dups each extracted heap field — so the box's
    references to its children are either inherited by the extracted locals
    (unique path) or compensated (shared path).  That path is correct and is
    the only one that reclaims a whole structure.

    A BARE [EDecRC] on a container that is never destructured had no such
    treatment.  It lowers to [march_decrc_local], which is [free(p)] with no
    child decrements ([runtime/march_runtime.c]) — so the container's children
    are orphaned.  Perceus emits exactly this shape whenever the consumer only
    BORROWS the container and the owner is left to drop it:

    {v
      let parts = String.split(buf, ",")   -- owner
      sum_lens(parts, 0)                   -- borrows
      dec_rc parts                         -- frees ONE cons cell; rest leaks
    v}

    Measured on a 60-iteration split/consume loop: 9,000,126 string allocations
    against 3 frees, RSS growing ~9.3 MB per iteration.  It is not specific to
    traversal — a consumer that ignores its list argument entirely leaks
    identically, because the leak is in the OWNER's drop, not the consumer.

    {1 The approach}

    For each variant type [T] that owns heap children, synthesize

    {v
      fn __drop$T(x : T) : Unit =
        case x of
        | Nil()       -> dec_rc x
        | Cons(h, t)  -> dec_rc x ; __drop$String(h) ; __drop$T(t)
    v}

    and rewrite every bare [EDecRC v] whose type is such a [T] into
    [__drop$T(v)].

    Synthesizing in TIR rather than emitting LLVM by hand buys three things:

    - {b The RC protocol is inherited, not reimplemented.}  The leading
      [dec_rc x] is the arm's scrutinee dec, so [llvm_case.ml]'s
      [strip_scrut_decrc] path applies verbatim: it becomes
      [march_decrc_freed(x)] plus shared-path field dups.  When the box is
      shared the fields are dup'd and the arm's own drops undo that (net
      zero, box merely decremented); when it is unique the box is freed and
      the arm's drops release the children it owned.  Both cases fall out of
      machinery that is already covered by tests — this pass does not decide
      when it is safe to free anything.

    - {b No stack overflow on long spines.}  The recursive field's drop is in
      TAIL position, so [__drop$T] is self-tail-recursive and [llvm_tco.ml]
      turns it into a loop.  A hand-written LLVM drop would recurse once per
      cons cell and die on a 150K-element list.

    - {b Representation is handled once.}  An [ECase] already lowers correctly
      for Boxed, Niche and Newtype scrutinees; hand-rolled IR would duplicate
      that decision table (the class of bug [llvm_eq.ml]'s Newtype/Niche arms
      exist to fix).

    {1 What is deliberately NOT dropped}

    - {b Newtype- and Niche-repr types} (see [needs_deep_drop]).  A newtype has
      no wrapper cell — the value IS its payload — and several stdlib types in
      that shape ([Bytes]) are built by the C runtime to a layout this pass
      must not assume it can destructure.  Conservative for now; widening to
      Niche (so a dropped [Option(String)] releases its payload) is a separate,
      independently-testable step.
    - {b Actor message types.}  [Repr] forces these to Boxed for DISPATCH
      reasons (so a foreign message carries a discriminant), not because of
      their own layout, and their cells are handled by the actor plane rather
      than by ordinary ownership — so this pass keeps its hands off them.

      Same-short-name COLLIDING types are deliberately NOT excluded, even
      though [Repr] force-Boxes them for the same dispatch-flavoured reason.
      Excluding them left a large hole: a user type as ordinarily named as
      [Tree] collides with [OrderedMap.Tree]/[SortedSet.Tree], and discarding
      one leaked its whole spine (467 MB over 160 build-and-discard
      iterations, versus 90 MB — allocator high-water, zero live objects —
      once included).  The generated [ECase] resolves its branch tags exactly
      as a hand-written [match] on the same type does, including the
      globally-unique tags a colliding type's constructors get, so nothing
      about the collision changes what this pass emits.
    - {b Tuples and records.}  [Rc_types.needs_rc] is FALSE for [TTuple] and
      [TRecord] by design — Perceus never emits inc/dec on those aggregates at
      all, reconciling at the field level instead — so there is no bare
      [EDecRC] on them for this pass to rewrite.  Their drop story is a
      separate question, untouched here. *)

(* Type parameters of a variant, in order of first appearance in its
   constructor field types.  Mirrors llvm_toplevel.ml's build_ctor_info, which
   derives ctx.type_params the same way: TDVariant carries no explicit
   parameter list, so the ordering convention has to be reproduced rather than
   read off. *)
let type_params_of (ctors : (string * Tir.ty list) list) : string list =
  let seen = Hashtbl.create 4 in
  let acc = ref [] in
  let rec collect = function
    | Tir.TVar n ->
      if not (Hashtbl.mem seen n) then begin
        Hashtbl.add seen n (); acc := n :: !acc
      end
    | Tir.TCon (_, args) -> List.iter collect args
    | Tir.TFn (ps, r) -> List.iter collect ps; collect r
    | Tir.TTuple ts -> List.iter collect ts
    | Tir.TPtr t -> collect t
    | _ -> ()
  in
  List.iter (fun (_, ftys) -> List.iter collect ftys) ctors;
  List.rev !acc

let rec apply_subst (subst : (string * Tir.ty) list) (ty : Tir.ty) : Tir.ty =
  match ty with
  | Tir.TVar n -> (match List.assoc_opt n subst with Some t -> t | None -> ty)
  | Tir.TCon (n, args) -> Tir.TCon (n, List.map (apply_subst subst) args)
  | Tir.TFn (ps, r) -> Tir.TFn (List.map (apply_subst subst) ps, apply_subst subst r)
  | Tir.TTuple ts -> Tir.TTuple (List.map (apply_subst subst) ts)
  | Tir.TPtr t -> Tir.TPtr (apply_subst subst t)
  | _ -> ty

(* A name-safe key for a monomorphic type.  Only needs to be injective over
   the types that reach it, and stable within one compilation. *)
let rec mangle (ty : Tir.ty) : string =
  match ty with
  | Tir.TInt -> "Int" | Tir.TFloat -> "Float" | Tir.TBool -> "Bool"
  | Tir.TString -> "String" | Tir.TUnit -> "Unit"
  | Tir.TTuple ts -> "T" ^ string_of_int (List.length ts)
                     ^ "_" ^ String.concat "_" (List.map mangle ts)
  | Tir.TRecord fs ->
    (* Field names AND types, sorted, not merely the arity.  This key is the
       memo key in [env.names] and the suffix of the synthesized function's
       name, so a bare "R<n>" made every n-field record collide: the first
       2-field record to be asked about decided the answer for all of them, and
       a memoized negative (no heap children) then suppressed the drop for a
       later { n : Int, s : String }, silently leaking its string.  Harmless
       while aggregates never got drop functions; a correctness bug now.
       Names are part of the identity because the drop projects fields by name
       and TRecord's layout is name-sorted. *)
    let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) fs in
    "R" ^ string_of_int (List.length fs)
    ^ "_" ^ String.concat "_"
              (List.map (fun (n, t) -> n ^ "$" ^ mangle t) sorted)
  | Tir.TCon (n, []) -> String.map (fun c -> if c = '.' then '_' else c) n
  | Tir.TCon (n, args) ->
    String.map (fun c -> if c = '.' then '_' else c) n
    ^ "_" ^ String.concat "_" (List.map mangle args)
  | Tir.TFn _ -> "Fn"
  | Tir.TPtr _ -> "Ptr"
  | Tir.TVar n -> "V" ^ n

type env = {
  type_defs     : Tir.type_def list;
  collision_set : (string, string list) Hashtbl.t;
  (* mangled type -> synthesized fn name.  Populated BEFORE the body is built
     so a recursive type's own drop call resolves instead of recursing
     forever during synthesis. *)
  names         : (string, string) Hashtbl.t;
  mutable fns   : Tir.fn_def list;
  mutable ctr   : int;
}

let fresh env pfx = env.ctr <- env.ctr + 1; Printf.sprintf "$%s%d" pfx env.ctr

(* The variant's constructors, with type arguments substituted in, when [ty] is
   a type this pass may synthesize a drop for.  See the "What is deliberately
   NOT dropped" section of the module doc for each exclusion. *)
let droppable_ctors (env : env) (ty : Tir.ty)
  : (string * Tir.ty list) list option =
  match ty with
  | Tir.TCon (name, ty_args)
    when not (Tir_names.is_actor_msg_name name) ->
    (* [repr_of_ty] alone is NOT enough here.  For an Option-shaped type it
       classifies from the TCon's type PARAMS, and a NON-GENERIC one
       (`type Wrap = W(String) | Z`) has none — so it falls back to Boxed:

         | Some [ (_nullary, []); (_single, [_]) ] ->
           (match params with
            | [p] when niche_payload_ok .. -> Niche ..
            | _ -> Boxed)                        <- params = [] lands here

       Codegen does not agree: it classifies such a type through
       [niche_repr_of_concrete], which exists precisely for "a NON-GENERIC
       Option-shaped ADT", and emits the niche encoding (null / non-null, no
       tag).  Under that encoding `W(x)` IS `x` — one cell, not two — so the
       drop this function would synthesize,

         case x of W(f) -> let freed = march_decrc_freed(x) in
                           case freed of True -> drop f

       releases the SAME pointer twice: once as the box, then again as the
       payload.  Measured on `type Wrap = W(String) | Z` in a 1000-iteration
       loop: 6/6 crashes, split across libsystem_malloc's freelist-corruption
       detector (SIGTRAP), this runtime's own RC-underflow guard reporting a
       garbage refcount, and SIGBUS.

       Generic Option-shaped types were never affected — `Option(String)`
       carries its payload in ty_args, so repr_of_ty sees `[p]` and correctly
       says Niche — which is why this survived: it needs a user-declared
       non-generic one.

       Consult BOTH predicates and decline if EITHER says the payload shares
       the box's storage. *)
    let concrete_niche =
      match ty with
      | Tir.TCon (n, []) ->
        (match Repr.niche_repr_of_concrete ~collision_set:env.collision_set
                 env.type_defs n with
         | Some (Repr.Niche _) -> true
         | _ -> false)
      | _ -> false
    in
    if concrete_niche then None else
    (match Repr.repr_of_ty ~collision_set:env.collision_set env.type_defs ty with
     | Repr.Boxed ->
       (match Repr.find_variant env.type_defs name with
        | Some ctors ->
          let params = type_params_of ctors in
          let subst =
            if List.length params = List.length ty_args
            then List.combine params ty_args else []
          in
          Some (List.map (fun (cn, ftys) ->
              (cn, List.map (apply_subst subst) ftys)) ctors)
        | None -> None)
     (* Unboxed: an inline struct of scalars.  No cell to free and no heap
        field to recurse into, so there is nothing for a [__drop$T] helper to
        do — the same answer as the erased reprs, for a different reason. *)
     | Repr.Newtype _ | Repr.Niche _ | Repr.Unboxed _ -> None)
  | _ -> None

(* A field still carrying an unsubstituted TVar means the type-parameter
   ordering convention did not line up (a shape this pass has no concrete
   layout for).  Bail rather than synthesize a drop against a guess. *)
let rec has_tvar = function
  | Tir.TVar _ -> true
  | Tir.TCon (_, args) -> List.exists has_tvar args
  | Tir.TFn (ps, r) -> List.exists has_tvar ps || has_tvar r
  | Tir.TTuple ts -> List.exists has_tvar ts
  | Tir.TPtr t -> has_tvar t
  | _ -> false

(** The (accessor, type) pairs of a record or tuple, in layout order, or
    [None] for any other type.  Records are keyed by field name and sorted, as
    [TRecord] itself is and as [Llvm_emit_data.emit_record] lays them out;
    tuples are keyed by the [$fvN] accessor that tuple destructuring lowers to.
    These are the aggregates that own their fields and are read exclusively
    through [EField] — see [build_aggregate_drop_fn]. *)
let aggregate_fields (ty : Tir.ty) : (string * Tir.ty) list option =
  match ty with
  | Tir.TRecord fs ->
    Some (List.sort (fun (a, _) (b, _) -> String.compare a b) fs)
  | Tir.TTuple ts -> Some (List.mapi (fun i t -> (Tir_names.fv_field i, t)) ts)
  | _ -> None

(** True when a value of [ty] may NOT be a heap pointer at runtime: a niche
    [None] is the raw word 0, and a newtype over a scalar is a tagged integer.

    Such a value must never be handed to a synthesized deep drop.  Those
    functions gate their children on [march_decrc_freed], which returns
    "freed" (1) for anything that is not a heap pointer — so the children
    branch fires and dereferences the word.  Observed as an EXC_BAD_ACCESS at
    address 0x8 (the tag slot) inside __drop$R3_... for
    test/native/ffi_codec2.march, whose `flag : Option(Unit)` field is a niche
    None built on the C side.

    Falling back to a bare [EDecRC] for these is safe — [march_decrc] is
    IS_HEAP_PTR-guarded, so it is a no-op on a non-heap word and an ordinary
    release otherwise.  It is also shallow, so a niche-typed field's own heap
    children are not reclaimed by this path; that is the conservative
    direction (leak, never crash) and it is the same treatment such a field
    got before aggregates were dropped at all. *)
let may_be_non_heap (env : env) (ty : Tir.ty) : bool =
  match ty with
  | Tir.TCon (name, _) ->
    (match Repr.repr_of_ty ~collision_set:env.collision_set env.type_defs ty with
     (* Unboxed: a scalar-only variant packed into a word -- never a heap
        pointer, so it belongs here too. *)
     | Repr.Niche _ | Repr.Newtype _ | Repr.Unboxed _ -> true
     | Repr.Boxed ->
       (* repr_of_ty answers Boxed for an Option-shaped type reached without
          type params; niche_repr_of_concrete is the predicate codegen uses
          there.  Same split that caused the double release fixed above. *)
       (match Repr.niche_repr_of_concrete ~collision_set:env.collision_set
                env.type_defs name with
        | Some (Repr.Niche _) -> true
        | _ -> false))
  | _ -> false

(** The synthesized drop function for [ty], or [None] if a bare [EDecRC] on
    [ty] is already correct (no heap children to release). *)
let rec drop_fn_for (env : env) (ty : Tir.ty) : string option =
  let key = mangle ty in
  match Hashtbl.find_opt env.names key with
  | Some "" -> None            (* memoized negative *)
  | Some fname -> Some fname
  | None ->
    match aggregate_fields ty with
    | Some fields ->
      (* Records and tuples: one implicit "constructor" over the fields, and no
         ECase to destructure it -- see [build_aggregate_drop_fn].  Without
         this branch a bare [EDecRC] on an aggregate stayed SHALLOW
         (march_decrc_local frees the cell and decrements nothing), so every
         heap value the aggregate owned was orphaned: a
         { n : Int, s : String } rebuilt 200k times leaked ~200k strings on
         top of ~200k cells. *)
      let owns_heap_child =
        List.exists (fun (_, fty) ->
            (not (has_tvar fty)) && Rc_types.needs_rc fty) fields
      in
      if not owns_heap_child then begin
        Hashtbl.replace env.names key ""; None
      end else begin
        let fname = Tir_names.drop_fn_prefix ^ key in
        Hashtbl.replace env.names key fname;
        let fn = build_aggregate_drop_fn env fname ty fields in
        env.fns <- fn :: env.fns;
        Some fname
      end
    | None ->
    match droppable_ctors env ty with
    | None -> Hashtbl.replace env.names key ""; None
    | Some ctors ->
      let owns_heap_child =
        List.exists (fun (_, ftys) ->
            List.exists (fun fty -> (not (has_tvar fty)) && Rc_types.needs_rc fty)
              ftys)
          ctors
      in
      if not owns_heap_child then begin
        Hashtbl.replace env.names key ""; None
      end else begin
        let fname = Tir_names.drop_fn_prefix ^ key in
        (* Register before building the body: Cons's tail field is this very
           type, and its drop call must resolve to this name. *)
        Hashtbl.replace env.names key fname;
        (* Bind the result FIRST.  [build_drop_fn] recurses into field types
           and appends THEIR drop functions to [env.fns]; writing
           [env.fns <- build_drop_fn … :: env.fns] would read [env.fns]
           before that recursion runs (OCaml evaluates constructor arguments
           right-to-left) and then overwrite it, silently discarding every
           nested drop function — emitting calls to definitions that were
           never kept, which the linker catches as an undefined
           [___drop$Inner]. *)
        let fn = build_drop_fn env fname ty ctors in
        env.fns <- fn :: env.fns;
        Some fname
      end

and build_aggregate_drop_fn env fname ty (fields : (string * Tir.ty) list)
  : Tir.fn_def =
  (* Mirrors [build_drop_fn]'s body exactly, with EField projections standing in
     for the ECase destructuring a variant gets:

       fn __drop$R(x) = let f1 = x.a in let f2 = x.b in
                        let freed = march_decrc_freed(x) in
                        case freed of True -> drop f1; drop f2 | _ -> ()

     Field loads are emitted BEFORE march_decrc_freed, so they read the cell
     while it is still alive; the free is shallow and does not disturb the
     children, so the loaded references stay valid for the drops below.  The
     freed-guard is what keeps a SHARED aggregate from having its children
     released out from under the surviving reference. *)
  let x = { Tir.v_name = fresh env "dx"; v_ty = ty; v_lin = Tir.Unr } in
  let unit_expr = Tir.ETuple [] in
  let droppable =
    List.filter (fun (_, fty) ->
        (not (has_tvar fty)) && Rc_types.needs_rc fty) fields
  in
  let binders =
    List.map (fun (accessor, fty) ->
        (accessor, { Tir.v_name = fresh env "df"; v_ty = fty; v_lin = Tir.Unr }))
      droppable
  in
  let ops =
    List.map (fun (_, v) ->
        if may_be_non_heap env v.Tir.v_ty then Tir.EDecRC (Tir.AVar v) else
        match drop_fn_for env v.Tir.v_ty with
        | Some callee ->
          let f = { Tir.v_name = callee;
                    v_ty = Tir.TFn ([v.Tir.v_ty], Tir.TUnit);
                    v_lin = Tir.Unr } in
          Tir.EApp (f, [Tir.AVar v])
        | None -> Tir.EDecRC (Tir.AVar v))
      binders
  in
  let rec chain = function
    | [] -> unit_expr
    | [last] -> last
    | op :: rest -> Tir.ESeq (op, chain rest)
  in
  let freed = { Tir.v_name = fresh env "dfree"; v_ty = Tir.TBool;
                v_lin = Tir.Unr } in
  let decrc_freed =
    { Tir.v_name = "march_decrc_freed";
      v_ty = Tir.TFn ([ty], Tir.TBool); v_lin = Tir.Unr } in
  let guarded =
    Tir.ELet (freed, Tir.EApp (decrc_freed, [Tir.AVar x]),
      Tir.ECase (Tir.AVar freed,
        [ { Tir.br_tag = "True"; br_vars = []; br_body = chain ops } ],
        Some unit_expr))
  in
  let body =
    List.fold_right (fun (accessor, v) acc ->
        Tir.ELet (v, Tir.EField (Tir.AVar x, accessor), acc))
      binders guarded
  in
  { Tir.fn_name = fname;
    fn_params = [x];
    fn_ret_ty = Tir.TUnit;
    fn_body = body;
    fn_kind = Tir.FnNormal }

and build_drop_fn env fname ty ctors : Tir.fn_def =
  let x = { Tir.v_name = fresh env "dx"; v_ty = ty; v_lin = Tir.Unr } in
  let unit_expr = Tir.ETuple [] in
  let branches =
    List.map (fun (cname, ftys) ->
        let vars =
          List.map (fun fty ->
              { Tir.v_name = fresh env "df"; v_ty = fty; v_lin = Tir.Unr }) ftys
        in
        (* One drop op per field that actually needs releasing. *)
        let ops =
          List.filter_map (fun v ->
              if has_tvar v.Tir.v_ty || not (Rc_types.needs_rc v.Tir.v_ty) then None
              else if may_be_non_heap env v.Tir.v_ty then
                Some (Tir.EDecRC (Tir.AVar v))
              else match drop_fn_for env v.Tir.v_ty with
                | Some callee ->
                  let f = { Tir.v_name = callee;
                            v_ty = Tir.TFn ([v.Tir.v_ty], Tir.TUnit);
                            v_lin = Tir.Unr } in
                  Some (Tir.EApp (f, [Tir.AVar v]))
                | None -> Some (Tir.EDecRC (Tir.AVar v)))
            vars
        in
        let body =
          match ops with
          | [] ->
            (* No heap children: releasing the box is the whole drop. *)
            Tir.EDecRC (Tir.AVar x)
          | _ ->
            (* Release the box and branch on whether that actually freed it.
               Descending unconditionally would be quadratic: dropping a
               SHARED cell must stop at the box, because the children are
               still owned by whoever holds the surviving reference.  Only
               when this was the last reference do we own — and must release
               — what the box pointed at.

               The branch reads the fields loaded at branch ENTRY, i.e.
               before the box is freed; the freed box's children are
               untouched by [free] (it is a shallow free), so those
               references stay valid for the drops below.

               The last drop is left in TAIL position, so a spine drop
               ([Cons]'s tail field, same type) is a self-tail-call that
               llvm_tco turns into a loop — no C-stack recursion per cell. *)
            let rec chain = function
              | [] -> unit_expr
              | [last] -> last
              | op :: rest -> Tir.ESeq (op, chain rest)
            in
            let freed = { Tir.v_name = fresh env "dfree"; v_ty = Tir.TBool;
                          v_lin = Tir.Unr } in
            let decrc_freed =
              { Tir.v_name = "march_decrc_freed";
                v_ty = Tir.TFn ([ty], Tir.TBool); v_lin = Tir.Unr } in
            Tir.ELet (freed, Tir.EApp (decrc_freed, [Tir.AVar x]),
              Tir.ECase (Tir.AVar freed,
                [ { Tir.br_tag = "True"; br_vars = []; br_body = chain ops } ],
                Some unit_expr))
        in
        { Tir.br_tag = cname; br_vars = vars; br_body = body })
      ctors
  in
  { Tir.fn_name = fname;
    fn_params = [x];
    fn_ret_ty = Tir.TUnit;
    fn_body = Tir.ECase (Tir.AVar x, branches, None);
    fn_kind = Tir.FnNormal }

(* ── Rewriting bare drops at their use sites ───────────────────────────── *)

let rewrite_dec env (atom : Tir.atom) (orig : Tir.expr) : Tir.expr =
  match atom with
  | Tir.AVar v ->
    (match drop_fn_for env v.Tir.v_ty with
     | Some fname ->
       let f = { Tir.v_name = fname;
                 v_ty = Tir.TFn ([v.Tir.v_ty], Tir.TUnit);
                 v_lin = Tir.Unr } in
       Tir.EApp (f, [Tir.AVar v])
     | None -> orig)
  | _ -> orig

let rec rewrite env (e : Tir.expr) : Tir.expr =
  match e with
  | Tir.EDecRC a -> rewrite_dec env a e
  (* EAtomicDecRC is left alone: it marks a value that may be shared across
     actors, where the box's own release must stay a single atomic op and the
     children's ownership is not this site's to reason about. *)
  | Tir.ELet (v, e1, e2) -> Tir.ELet (v, rewrite env e1, rewrite env e2)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (rewrite env e1, rewrite env e2)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (List.map (fun f ->
        { f with Tir.fn_body = rewrite env f.Tir.fn_body }) fns,
      rewrite env body)
  | Tir.ECase (scrut, brs, def) ->
    (* A branch's leading dec of the SCRUTINEE is the destructuring drop that
       llvm_case.ml's strip_scrut_decrc consumes — the arm has already taken
       over the extracted children, so rewriting it into a deep drop would
       release them twice.  Leave it; rewrite everything else, including other
       variables' decs that add_cross_decrcs prepends into the same leading
       run. *)
    let sn = match scrut with Tir.AVar v -> Some v.Tir.v_name | _ -> None in
    let is_scrut_dec op =
      match sn, op with
      | Some n, (Tir.EDecRC (Tir.AVar v) | Tir.EAtomicDecRC (Tir.AVar v)) ->
        String.equal v.Tir.v_name n
      | _ -> false
    in
    let rec rewrite_body body =
      match body with
      | Tir.ESeq (((Tir.EDecRC _ | Tir.EAtomicDecRC _ | Tir.EFree _) as op), rest) ->
        let op' = if is_scrut_dec op then op else rewrite env op in
        Tir.ESeq (op', rewrite_body rest)
      | op when is_scrut_dec op -> op
      | _ -> rewrite env body
    in
    Tir.ECase (scrut,
      List.map (fun br -> { br with Tir.br_body = rewrite_body br.Tir.br_body }) brs,
      Option.map (rewrite env) def)
  | _ -> e

(** Synthesize deep-drop functions and route bare aggregate drops through them.

    Runs AFTER Perceus (it rewrites the [EDecRC]s Perceus inserts) and BEFORE
    Escape (so a value flowing into a drop call is seen as escaping and is not
    stack-allocated behind the drop's back). *)
let run (m : Tir.tir_module) : Tir.tir_module =
  let collision_set = Collision_set.compute m.Tir.tm_types in
  let env = { type_defs = m.Tir.tm_types; collision_set;
              names = Hashtbl.create 32; fns = []; ctr = 0 } in
  let fns = List.map (fun f ->
      { f with Tir.fn_body = rewrite env f.Tir.fn_body }) m.Tir.tm_fns in
  (* Synthesized bodies are built already-rewritten (drop_fn_for is called
     directly when emitting each field op), so they are appended as-is. *)
  { m with Tir.tm_fns = fns @ List.rev env.fns }
