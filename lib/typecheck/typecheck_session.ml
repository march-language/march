(** Session-type projection and duality.

    [project_steps], [subst_svar], [dual_session_ty] and [project_protocol] —
    the pass that projects a multiparty protocol onto each role and checks the
    projections are dual.  Lifted verbatim out of [Typecheck] on 2026-08-27
    (Target B, task B4).

    The band depends on no name defined below it in [Typecheck].  It reaches
    upward for [surface_ty], [session_ty_equal] and [session_ty_exact_equal]
    — all three of which moved to [Typecheck_unify] in task B3, which is why
    B4 is sequenced after it — and for [unfold_srec], which the plan's
    dependency scan did not list and which lives in [Typecheck_exhaustive]
    (included by [Typecheck] at a point above this band, so the order is
    unchanged).  Hence the four includes below.

    [include], not [open], at the call site: only [include] re-exports these
    names as part of [Typecheck]'s own surface, and consumers reach them
    through [let open] and through aliases (Tc., TC., T.) that no grep can
    see. *)

include Typecheck_types
include Typecheck_env
include Typecheck_builtins
include Typecheck_unify
include Typecheck_exhaustive

(** [project_steps env ~proto_name ~multiparty steps role cont] projects a
    list of protocol steps onto [role], appending [cont] as the continuation.
    When [multiparty] is true (N>2 roles), produces [SMSend]/[SMRecv] with
    explicit role annotations; otherwise produces [SSend]/[SRecv]. *)
let rec project_steps env ~proto_name ~multiparty steps role cont =
  match steps with
  | [] -> cont
  | step :: rest ->
    let rest_ty () = project_steps env ~proto_name ~multiparty rest role cont in
    (match step with
     | Ast.ProtoMsg (sender, receiver, msg_ty) ->
       let tvars = ref [] in
       let t = surface_ty env ~tvars msg_ty in
       if sender.Ast.txt = role then
         (if multiparty then SMSend (receiver.Ast.txt, t, rest_ty ())
          else SSend (t, rest_ty ()))
       else if receiver.Ast.txt = role then
         (if multiparty then SMRecv (sender.Ast.txt, t, rest_ty ())
          else SRecv (t, rest_ty ()))
       else
         rest_ty ()   (* This role doesn't participate in this step *)
     | Ast.ProtoLoop inner_steps ->
       (* `loop do S end` is the µ-type `Rec X. S[X]` — the body's continuation
          IS the binder's back-reference, so the loop repeats indefinitely.
          (Substituting the post-loop continuation into the back-reference, as
          this arm used to do, produced a vacuous SRec with no SVar in it: one
          unrolled iteration.  Steps after a `loop` are unreachable and are
          rejected at protocol-declaration time.) *)
       let rec_var = proto_name ^ "_loop" in
       let inner = project_steps env ~proto_name ~multiparty inner_steps role (SVar rec_var) in
       (match inner with
        | SVar _ ->
          (* Role not involved in the loop at all — skip the binder entirely. *)
          rest_ty ()
        | _ -> SRec (rec_var, inner))
     | Ast.ProtoChoice (chooser, branches) ->
       (* Every branch rejoins the protocol tail, so each arm is projected with
          the steps that FOLLOW this choice block as its continuation — not the
          outer [cont], which at top level is just SEnd and silently truncates
          the protocol. *)
       let after_choice = rest_ty () in
       let branch_tys = List.map (fun (lbl, arm_steps) ->
           let arm_ty = project_steps env ~proto_name ~multiparty arm_steps role after_choice in
           (lbl.Ast.txt, arm_ty)
         ) branches in
       if chooser.Ast.txt = role then
         SChoose branch_tys
       else begin
         (* Mergeability: if all branches project to the same local type for
            this role, merge them into that type (the role need not observe
            the choice at all).  This is the standard MPST merge rule, and it
            only applies to MULTIPARTY protocols (>2 roles), where a bystander
            role genuinely does not observe a choice made between two OTHER
            roles.  In a BINARY (2-role) protocol the non-chooser is the
            chooser's only peer — the offerer — who MUST always observe the
            choice (it runs [Chan.offer]); so we never merge there, even when
            the branches happen to carry identical payload types. *)
         match branch_tys with
         | [] -> SOffer branch_tys
         | (_, first_ty) :: rest ->
           if multiparty && List.for_all (fun (_, ty) -> session_ty_exact_equal ty first_ty) rest then
             first_ty   (* role not involved — merged/transparent *)
           else
             SOffer branch_tys
       end
     | Ast.ProtoStop _ ->
       (* `stop` exits the enclosing `loop` for every role: it projects to
          `SEnd` unconditionally, discarding both the surrounding [cont] and
          any steps that follow it (those are rejected as unreachable at
          protocol-declaration time — see [check_unreachable_after_loop]). *)
       SEnd)

(** Substitute occurrences of [SVar x] with [replacement] inside [s]. *)
and subst_svar x replacement s =
  match s with
  | SVar y when y = x -> replacement
  | SSend (t, s')  -> SSend (t, subst_svar x replacement s')
  | SRecv (t, s')  -> SRecv (t, subst_svar x replacement s')
  | SChoose bs     -> SChoose (List.map (fun (l, s') -> (l, subst_svar x replacement s')) bs)
  | SOffer bs      -> SOffer  (List.map (fun (l, s') -> (l, subst_svar x replacement s')) bs)
  | SMSend (r, t, s') -> SMSend (r, t, subst_svar x replacement s')
  | SMRecv (r, t, s') -> SMRecv (r, t, subst_svar x replacement s')
  | SRec (y, s') when y <> x -> SRec (y, subst_svar x replacement s')
  | other -> other

(** Compute the dual of a local session type (what the other endpoint must have).
    Only meaningful for binary protocols; MPST types use SMSend/SMRecv directly. *)
let rec dual_session_ty = function
  | SSend (t, s)  -> SRecv (t, dual_session_ty s)
  | SRecv (t, s)  -> SSend (t, dual_session_ty s)
  | SChoose bs    -> SOffer  (List.map (fun (l, s) -> (l, dual_session_ty s)) bs)
  | SOffer  bs    -> SChoose (List.map (fun (l, s) -> (l, dual_session_ty s)) bs)
  | SEnd          -> SEnd
  | SRec (x, s)   -> SRec (x, dual_session_ty s)
  | SVar x        -> SVar x
  | SError        -> SError
  | SMSend (r, t, s) -> SMSend (r, t, dual_session_ty s)
  | SMRecv (r, t, s) -> SMRecv (r, t, dual_session_ty s)

(** Project a global protocol onto all participating roles.
    Returns [(role, local_ty) list].
    - Binary (2 roles): verifies duality of the two projections.
    - Multiparty (N>2 roles): verifies pairwise send/recv consistency using
      role-annotated SMSend/SMRecv constructors. *)
let project_protocol env ~span ~proto_name (pdef : Ast.protocol_def) =
  (* Collect all roles *)
  let rec roles_of_steps = function
    | [] -> []
    | Ast.ProtoMsg (s, r, _) :: rest ->
      s.Ast.txt :: r.Ast.txt :: roles_of_steps rest
    | Ast.ProtoLoop steps :: rest ->
      roles_of_steps steps @ roles_of_steps rest
    | Ast.ProtoChoice (chooser, branches) :: rest ->
      chooser.Ast.txt ::
      List.concat_map (fun (_, steps) -> roles_of_steps steps) branches @
      roles_of_steps rest
    | Ast.ProtoStop _ :: rest -> roles_of_steps rest
  in
  let roles = List.sort_uniq String.compare (roles_of_steps pdef.proto_steps) in
  let multiparty = List.length roles > 2 in
  (* Project each role *)
  let projections = List.map (fun role ->
      let ty = project_steps env ~proto_name ~multiparty pdef.proto_steps role SEnd in
      (role, ty)
    ) roles in
  (match roles with
   | [a; b] ->
     (* Binary protocol: verify duality *)
     let proj_a = List.assoc a projections in
     let proj_b = List.assoc b projections in
     let dual_a = dual_session_ty proj_a in
     if not (session_ty_equal dual_a proj_b) then
       Err.error env.errors ~span
         (Printf.sprintf
            "Protocol `%s`: the projection onto `%s` and the projection onto \
             `%s` are not duals of each other.\n\
             dual(%s) = %s\nbut %s has: %s"
            proto_name a b
            a (pp_session_ty dual_a)
            b (pp_session_ty proj_b))
   | _ when multiparty ->
     (* Multiparty protocol: verify that every SMSend in role A to role B
        corresponds to an SMRecv in role B from role A with the same type.
        We check this by collecting all (sender, receiver, msg_ty) triples
        from the global steps and comparing against the projections. *)
     let rec gather_msgs acc = function
       | [] -> acc
       | Ast.ProtoMsg (s, r, t) :: rest ->
         let tvars = ref [] in
         let ty = surface_ty env ~tvars t in
         gather_msgs ((s.Ast.txt, r.Ast.txt, ty) :: acc) rest
       | Ast.ProtoLoop inner :: rest ->
         gather_msgs (gather_msgs acc inner) rest
       | Ast.ProtoChoice (_, branches) :: rest ->
         let branch_msgs = List.concat_map (fun (_, steps) ->
             gather_msgs [] steps) branches in
         gather_msgs (branch_msgs @ acc) rest
       | Ast.ProtoStop _ :: rest -> gather_msgs acc rest
     in
     let msgs = gather_msgs [] pdef.proto_steps in
     List.iter (fun (sender, receiver, msg_ty) ->
         (* Check sender has SMSend(receiver, msg_ty, ...) somewhere *)
         let rec has_msend s =
           match unfold_srec s with
           | SMSend (r, t, cont) ->
             (r = receiver && session_ty_equal (SSend (t, SEnd)) (SSend (msg_ty, SEnd)))
             || has_msend cont
           | SMRecv (_, _, cont) -> has_msend cont
           | SChoose bs | SOffer bs ->
             List.exists (fun (_, s') -> has_msend s') bs
           | SRec (_, s') -> has_msend s'
           | _ -> false
         in
         let rec has_mrecv s =
           match unfold_srec s with
           | SMRecv (r, t, cont) ->
             (r = sender && session_ty_equal (SSend (t, SEnd)) (SSend (msg_ty, SEnd)))
             || has_mrecv cont
           | SMSend (_, _, cont) -> has_mrecv cont
           | SChoose bs | SOffer bs ->
             List.exists (fun (_, s') -> has_mrecv s') bs
           | SRec (_, s') -> has_mrecv s'
           | _ -> false
         in
         (match List.assoc_opt sender projections with
          | Some proj when not (has_msend proj) ->
            Err.error env.errors ~span
              (Printf.sprintf
                 "Protocol `%s`: role `%s` should send to `%s` but \
                  its projected type does not include MSend(%s, ...)."
                 proto_name sender receiver receiver)
          | _ -> ());
         (match List.assoc_opt receiver projections with
          | Some proj when not (has_mrecv proj) ->
            Err.error env.errors ~span
              (Printf.sprintf
                 "Protocol `%s`: role `%s` should receive from `%s` but \
                  its projected type does not include MRecv(%s, ...)."
                 proto_name receiver sender sender)
          | _ -> ())
       ) msgs
   | _ -> ());  (* 0 or 1 role: already warned in caller *)
  projections
