(** Perceus — Phase 0.5 whole-scrutinee-escape rewrite (Wave 3 Task 5 file
    split).  Moved verbatim from [perceus.ml]; the only edits are module
    qualifications for the two helpers this phase depends on:
    [Perceus_liveness.name_free_in] (self-contained liveness group) and
    [Rc_types.needs_rc] directly (NOT [Perceus.needs_rc], which is itself
    just a re-export of the same function — going through [Perceus] would
    make [Perceus_scrut] depend on [Perceus], while [Perceus] must depend on
    [Perceus_scrut] to call [preprocess_fn] from the [perceus] orchestrator;
    a real dune dependency cycle, rejected by the build the first time this
    split was tried.  Calling [Rc_types.needs_rc] directly keeps the
    dependency one-directional: [Perceus_scrut] depends only on
    [Perceus_liveness] and [Rc_types], never on [Perceus] itself).

    Problem: when a pattern-match arm returns the scrutinee verbatim in one
    path while consuming its fields in sibling paths, e.g.

      match ls do
        Nil -> Nil
        Cons(l, rest) ->
          if String.is_empty(trim(l)) do drop_blank(rest)
          else ls
          end
      end

    Perceus sees the scrutinee `ls` as free in the Cons arm body (used in the
    `else ls` branch) and therefore SKIPS emitting `dec_rc ls` at the arm
    start.  But on the `drop_blank(rest)` sub-path, `rest` and `l` are still
    treated as independent owning vars — including a post-call `dec_rc l`
    after the `trim(l)` borrow — yet no ownership was ever transferred from
    the scrutinee to them.  The `dec_rc l` then underflows the string's RC
    and corrupts the heap (see commit 6065f30 for the fields-escape sibling
    issue).

    Fix: BEFORE Perceus, rewrite every tail-position occurrence of the
    scrutinee inside a matched arm into a reconstruction of the matched
    constructor.  E.g. `Cons(l, rest) -> ... ls` becomes
    `Cons(l, rest) -> ... Cons(l, rest)`.  After rewriting:
    - The arm body no longer mentions the scrutinee → the existing
      `add_scrutinee_free_for` emits the usual `dec_rc ls` at arm start.
    - `llvm_emit`'s `strip_scrut_decrc` converts that into the
      `march_decrc_freed` + conditional field-IncRC pattern, which correctly
      transfers ownership of the extracted fields into the arm.
    - The trailing EAlloc re-packs those owned fields into a fresh cell,
      which FBIP can collapse to an EReuse of the scrutinee's storage.

    Only SYNTACTIC tail positions are rewritten: an EAtom(AVar scrut) that
    is the arm's result, or the result of a tail sub-expression (ECase arm,
    ELet body, ESeq tail, ELetRec body).  Non-tail occurrences (scrut used
    inside a call argument that is not itself a tail call) stay untouched;
    if those patterns turn out to matter in practice they can be handled
    separately. *)

(** Scan the straight-line ELet prefix of [e] for the user-level rebinds
    of each [br_var] (e.g. `let l = $f1` after pattern decomposition).  If
    a rebind is found its typed var replaces the anonymous br_var; this
    lets the reconstructed EAlloc store atoms that already carry their
    concrete types, so downstream Perceus/FBIP RC analysis sees the right
    shape.  Falls back to the raw br_var when no rebind is present. *)
let scrut_escape_field_atoms (br_vars : Tir.var list) (body : Tir.expr)
    : Tir.atom list =
  let rec gather acc e =
    match e with
    | Tir.ELet (v, Tir.EAtom (Tir.AVar src), rest) ->
      gather ((src.Tir.v_name, v) :: acc) rest
    | Tir.ELet (_, _, rest) -> gather acc rest
    | _ -> List.rev acc
  in
  let rebinds = gather [] body in
  List.map (fun bv ->
    match List.assoc_opt bv.Tir.v_name rebinds with
    | Some v -> Tir.AVar v
    | None -> Tir.AVar bv
  ) br_vars

(** Replace every tail-position occurrence of [EAtom (AVar scrut_name)] in
    [e] with an EAlloc reconstructing the matched constructor.  Stops
    recursing through binders that shadow [scrut_name]. *)
let rec rewrite_scrut_tail (scrut_name : string) (alloc_ty : Tir.ty)
    (field_atoms : Tir.atom list) (e : Tir.expr) : Tir.expr =
  match e with
  | Tir.EAtom (Tir.AVar v) when String.equal v.Tir.v_name scrut_name ->
    Tir.EAlloc (alloc_ty, field_atoms)
  | Tir.ELet (v, e1, e2) ->
    if String.equal v.Tir.v_name scrut_name then e
    else Tir.ELet (v, e1, rewrite_scrut_tail scrut_name alloc_ty field_atoms e2)
  | Tir.ELetRec (fns, body) ->
    let shadows =
      List.exists (fun fn -> String.equal fn.Tir.fn_name scrut_name) fns
    in
    if shadows then e
    else Tir.ELetRec (fns, rewrite_scrut_tail scrut_name alloc_ty field_atoms body)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (e1, rewrite_scrut_tail scrut_name alloc_ty field_atoms e2)
  | Tir.ECase (a, branches, default) ->
    let branches' = List.map (fun br ->
      let shadows =
        List.exists (fun bv -> String.equal bv.Tir.v_name scrut_name) br.Tir.br_vars
      in
      if shadows then br
      else { br with Tir.br_body =
        rewrite_scrut_tail scrut_name alloc_ty field_atoms br.Tir.br_body }
    ) branches in
    let default' =
      Option.map (rewrite_scrut_tail scrut_name alloc_ty field_atoms) default
    in
    Tir.ECase (a, branches', default')
  | _ -> e

(** The constructor key ("Type.Ctor") the reconstructing EAlloc names, from
    the scrutinee's type and the branch's tag.

    A branch tag is not always the bare constructor name: a pattern written
    qualified keeps a qualifier ([Lower_match.pat_tag_and_subs]), as a type
    (`Shape.Square`), as the exact "Mod.Type.Ctor" key of a type whose short
    name collides, or as something that is neither a type nor a module (an
    actor's name on its message constructor, `Counter.Bump` on a
    `Counter_Msg`).  [Llvm_case.qualified_br_key] resolves all of those for
    the `case`; an EAlloc has no such resolver.  Prefixing the scrutinee's
    type to a tag that already had a qualifier ("Shape.Shape.Square",
    "Counter_Msg.Counter.Bump") named no constructor at all, and
    [Llvm_data.ctor_entry] then fell back to tag 0: the arm silently returned
    the type's FIRST constructor, and a caller matching on it panicked or
    took the wrong arm
    (specs/progress/2026-11-05-nested-match-qualified-actor-msg-pattern-miscompile.md).

    So: a tag of three or more segments whose type segment is the
    scrutinee's type is already the exact key and is kept; any other
    qualifier is dropped and the scrutinee's own type names the constructor,
    as for a bare tag. *)
let scrut_alloc_key (scrut_ty : Tir.ty) (br_tag : string) : string =
  let last_seg s = match String.rindex_opt s '.' with
    | Some j -> String.sub s (j + 1) (String.length s - j - 1)
    | None -> s
  in
  match scrut_ty with
  | Tir.TCon (type_name, _) ->
    (match String.rindex_opt br_tag '.' with
     | None -> type_name ^ "." ^ br_tag
     | Some i ->
       let qual = String.sub br_tag 0 i in
       if String.contains qual '.' && String.equal (last_seg qual) (last_seg type_name)
       then br_tag
       else type_name ^ "." ^ last_seg br_tag)
  | _ -> br_tag

(** Walk the function body, applying the scrut-escape rewrite inside every
    ECase arm whose scrutinee is a heap-valued AVar and whose branch binds
    at least one field. *)
let rec preprocess_scrut_escape (k_table : Kind.table) (e : Tir.expr) : Tir.expr =
  match e with
  | Tir.ECase (a, branches, default) ->
    let branches' = List.map (fun br ->
      let body' = preprocess_scrut_escape k_table br.Tir.br_body in
      let body'' =
        match a with
        | Tir.AVar sv
          when Kind.needs_rc_of k_table sv.Tir.v_ty
               && br.Tir.br_vars <> []
               && not (List.exists
                         (fun bv -> String.equal bv.Tir.v_name sv.Tir.v_name)
                         br.Tir.br_vars)
               && Perceus_liveness.name_free_in sv.Tir.v_name body' ->
          let qualified_tag = scrut_alloc_key sv.Tir.v_ty br.Tir.br_tag in
          let alloc_ty = Tir.TCon (qualified_tag, []) in
          let field_atoms = scrut_escape_field_atoms br.Tir.br_vars body' in
          rewrite_scrut_tail sv.Tir.v_name alloc_ty field_atoms body'
        | _ -> body'
      in
      { br with Tir.br_body = body'' }
    ) branches in
    let default' = Option.map (preprocess_scrut_escape k_table) default in
    Tir.ECase (a, branches', default')
  | Tir.ELet (v, e1, e2) ->
    Tir.ELet (v, preprocess_scrut_escape k_table e1, preprocess_scrut_escape k_table e2)
  | Tir.ELetRec (fns, body) ->
    let fns' = List.map (fun fn ->
      { fn with Tir.fn_body = preprocess_scrut_escape k_table fn.Tir.fn_body }
    ) fns in
    Tir.ELetRec (fns', preprocess_scrut_escape k_table body)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (preprocess_scrut_escape k_table e1, preprocess_scrut_escape k_table e2)
  | _ -> e

let preprocess_fn ~(k_table : Kind.table) (fn : Tir.fn_def) : Tir.fn_def =
  { fn with Tir.fn_body = preprocess_scrut_escape k_table fn.Tir.fn_body }
