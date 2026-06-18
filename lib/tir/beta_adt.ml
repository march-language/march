(** Beta-ADT reduction — case-of-known-constructor.

    Recognises the pattern

        let r = EAlloc(Tag, [a0, …, an]) in
        ECase(AVar r, [{br_tag = Tag; br_vars = [v0,…,vn]; br_body}], default)

    and reduces it to

        let v0 = a0 in … let vn = an in br_body

    The ELet binding for [r] is left in place (now dead) and removed by the
    subsequent DCE pass.  The default branch (which typically contains
    [EFree(r)] inserted by Perceus for the non-matching case) is simply
    dropped — since the allocation is DCE'd, there is nothing to free.

    Safety:
    - Pre-Perceus: no RC operations exist; the transformation is trivially safe.
    - Post-Perceus: Perceus emits RC operations that reference [br_vars] (not [r])
      inside the matching branch.  Those operations remain valid after the
      transformation: [vi] is now bound to [ai] and the RC semantics carry
      through the new ELet bindings.  Any [EFree(r)] in the dropped branches
      is harmless because the EAlloc is DCE'd and never executes.

    Sets [~changed] on any reduction. *)

(** Return the short (unqualified) constructor name: the suffix after the last
    dot, or the whole string if there is no dot.
    ["Result.Ok"] → ["Ok"];  ["Ok"] → ["Ok"]. *)
let short_name s =
  match String.rindex_opt s '.' with
  | Some i -> String.sub s (i + 1) (String.length s - i - 1)
  | None   -> s

(** True when the EAlloc constructor name and a branch tag refer to the same
    constructor (either both fully qualified or just by short name). *)
let tags_match alloc_tcon_name br_tag =
  alloc_tcon_name = br_tag
  || short_name alloc_tcon_name = short_name br_tag

let rec beta_adt_expr ~changed : Tir.expr -> Tir.expr = function
  (* Reducible: let r = EAlloc(tag, args) in ECase(AVar r, branches, default) *)
  | Tir.ELet (r, Tir.EAlloc (Tir.TCon (alloc_name, _), alloc_args),
              Tir.ECase (Tir.AVar r', branches, default))
    when r.Tir.v_name = r'.Tir.v_name ->
    (match List.find_opt (fun b -> tags_match alloc_name b.Tir.br_tag) branches with
     | None ->
       (* No matching branch — well-typed code should not reach here; recurse. *)
       Tir.ELet (r, Tir.EAlloc (Tir.TCon (alloc_name, []), alloc_args),
         beta_adt_expr ~changed (Tir.ECase (Tir.AVar r', branches, default)))
     | Some branch when List.length branch.Tir.br_vars <> List.length alloc_args ->
       (* Arity mismatch — skip conservatively. *)
       Tir.ELet (r, Tir.EAlloc (Tir.TCon (alloc_name, []), alloc_args),
         beta_adt_expr ~changed (Tir.ECase (Tir.AVar r', branches, default)))
     | Some branch ->
       changed := true;
       (* Build let-chain binding each branch variable to the corresponding arg,
          then run the branch body (recurse into it for further reductions). *)
       let body = beta_adt_expr ~changed branch.Tir.br_body in
       List.fold_right2
         (fun v arg acc -> Tir.ELet (v, Tir.EAtom arg, acc))
         branch.Tir.br_vars alloc_args body)

  (* Recurse into all other forms. *)
  | Tir.ELet (v, rhs, body) ->
    Tir.ELet (v, beta_adt_expr ~changed rhs, beta_adt_expr ~changed body)
  | Tir.ECase (a, branches, default) ->
    Tir.ECase (a,
      List.map (fun b -> { b with Tir.br_body = beta_adt_expr ~changed b.Tir.br_body }) branches,
      Option.map (beta_adt_expr ~changed) default)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (
      List.map (fun fd -> { fd with Tir.fn_body = beta_adt_expr ~changed fd.Tir.fn_body }) fns,
      beta_adt_expr ~changed body)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (beta_adt_expr ~changed e1, beta_adt_expr ~changed e2)
  | other -> other

let run_fn ~changed (fd : Tir.fn_def) : Tir.fn_def =
  { fd with Tir.fn_body = beta_adt_expr ~changed fd.Tir.fn_body }

let run ~changed (m : Tir.tir_module) : Tir.tir_module =
  { m with Tir.tm_fns = List.map (run_fn ~changed) m.Tir.tm_fns }
