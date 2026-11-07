(** Session-type projection and duality.

    [project_steps_at], [subst_svar], [dual_session_ty] and [project_protocol] —
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

(** The place of each state [project_steps_at] builds in the protocol's
    steps ([March_ast.Protocol_states.pos], for the diagram), and of each
    `SEnd` it reaches ([None] where not tracked); `SEnd` is one value
    however many times it is reached, so its place is known only when the
    role's conversation ends in exactly one. *)
type tags = {
  mutable nodes : (session_ty * int list) list;
  mutable ends  : int list option list;
}

(** [project_steps_at env ~proto_name ~multiparty ~tags ~at ~i steps role cont]
    projects a list of protocol steps onto [role], appending [cont] as the
    continuation.  When [multiparty] is true (N>2 roles), produces
    [SMSend]/[SMRecv] with explicit role annotations; otherwise produces
    [SSend]/[SRecv].

    [at] is the path to the step list being projected, innermost index
    first ([None]: not tracked), [i] the index of [steps]'s head in it among
    the steps [March_ast.Protocol_states.visible] counts.  Only the end of
    the top-level list is the conversation's end. *)
let rec project_steps_at env ~proto_name ~multiparty ~(tags : tags) ~(at : int list option) ~i steps role cont =
  let here () = Option.map (fun p -> List.rev (i :: p)) at in
  let tag node = (match here () with Some p -> tags.nodes <- (node, p) :: tags.nodes | None -> ()); node in
  let inside ~branch = match at with
    | Some p -> Some (match branch with Some b -> b :: i :: p | None -> i :: p)
    | None -> None in
  let untag prefix =
    let rec has_prefix p q = match p, q with
      | [], _ -> true
      | x :: xs, y :: ys -> x = y && has_prefix xs ys
      | _, [] -> false in
    tags.nodes <- List.filter (fun (_, p) -> not (has_prefix prefix p)) tags.nodes;
    tags.ends <- List.map (function Some p when has_prefix prefix p -> None | e -> e) tags.ends in
  match steps with
  | [] -> (if at = Some [] then tags.ends <- Some [ i ] :: tags.ends); cont
  | step :: rest ->
    let rest_ty () = project_steps_at env ~proto_name ~multiparty ~tags ~at ~i:(i + 1) rest role cont in
    (match step with
     | Ast.ProtoMsg (sender, receiver, msg_ty, _) ->
       let tvars = ref [] in
       let t = surface_ty env ~tvars msg_ty in
       if sender.Ast.txt = role then
         tag (if multiparty then SMSend (receiver.Ast.txt, t, rest_ty ())
              else SSend (t, rest_ty ()))
       else if receiver.Ast.txt = role then
         tag (if multiparty then SMRecv (sender.Ast.txt, t, rest_ty ())
              else SRecv (t, rest_ty ()))
       else
         rest_ty ()   (* This role doesn't participate in this step *)
     | Ast.ProtoLoop (inner_steps, _) ->
       (* `loop do S end` is the µ-type `Rec X. S[X]` — the body's continuation
          IS the binder's back-reference, so the loop repeats indefinitely.
          (Substituting the post-loop continuation into the back-reference, as
          this arm used to do, produced a vacuous SRec with no SVar in it: one
          unrolled iteration.  Steps after a `loop` are unreachable and are
          rejected at protocol-declaration time.) *)
       let rec_var = proto_name ^ "_loop" in
       let inner = project_steps_at env ~proto_name ~multiparty ~tags ~at:(inside ~branch:None) ~i:0
           inner_steps role (SVar rec_var) in
       (match inner with
        | SVar _ ->
          (* Role not involved in the loop at all — skip the binder entirely. *)
          rest_ty ()
        | _ ->
          let r = SRec (rec_var, inner) in
          (* The loop head is its body's first state, and a channel that has
             gone round once is at the body unfolded: the same places. *)
          (match List.assq_opt inner tags.nodes with
           | Some p -> tags.nodes <- (r, p) :: tags.nodes
           | None -> ());
          let rec copy orig unf =
            (match List.assq_opt orig tags.nodes with
             | Some p -> tags.nodes <- (unf, p) :: tags.nodes
             | None -> ());
            match orig, unf with
            | (SSend (_, a) | SRecv (_, a) | SMSend (_, _, a) | SMRecv (_, _, a)),
              (SSend (_, b) | SRecv (_, b) | SMSend (_, _, b) | SMRecv (_, _, b)) -> copy a b
            | (SChoose xs | SOffer xs), (SChoose ys | SOffer ys)
              when List.length xs = List.length ys ->
              List.iter2 (fun (_, a) (_, b) -> copy a b) xs ys
            | SRec (_, a), SRec (_, b) when orig != r -> copy a b
            | _ -> () in
          copy inner (match unfold_srec r with SRec (_, u) -> u | u -> u);
          r)
     | Ast.ProtoChoice (chooser, branches) ->
       (* Every branch rejoins the protocol tail, so each arm is projected with
          the steps that FOLLOW this choice block as its continuation — not the
          outer [cont], which at top level is just SEnd and silently truncates
          the protocol. *)
       let after_choice = rest_ty () in
       let branch_tys = List.mapi (fun b (lbl, arm_steps) ->
           let arm_ty = project_steps_at env ~proto_name ~multiparty ~tags ~at:(inside ~branch:(Some b)) ~i:0
               arm_steps role after_choice in
           (lbl.Ast.txt, arm_ty)
         ) branches in
       if chooser.Ast.txt = role then
         tag (SChoose branch_tys)
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
           if multiparty && List.for_all (fun (_, ty) -> session_ty_exact_equal ty first_ty) rest then begin
             (* A bystander never learns which branch was taken: the states
                inside have no one place in the conversation. *)
             (match here () with Some p -> untag p | None -> ());
             first_ty   (* role not involved — merged/transparent *)
           end else
             tag (SOffer branch_tys)
       end
     | Ast.ProtoStop _ ->
       (* `stop` exits the enclosing `loop` for every role: it projects to
          `SEnd` unconditionally, discarding both the surrounding [cont] and
          any steps that follow it (those are rejected as unreachable at
          protocol-declaration time — see [check_unreachable_after_loop]). *)
       tags.ends <- here () :: tags.ends;
       SEnd
     | Ast.ProtoMayCrash _ | Ast.ProtoRoleNeeds _ ->
       project_steps_at env ~proto_name ~multiparty ~tags ~at ~i rest role cont
     | Ast.ProtoCrashOr (inner, _crash, _) ->
       (* This projection serves the `Chan(Role, Proto)` API, which refuses a
          protocol with crash branches ([has_crash_branches]); the
          `@[endpoints]` generator projects them itself.  Here the message
          projects as if it had no crash branch, so the usual duality and
          consistency checks still cover the normal path. *)
       project_steps_at env ~proto_name ~multiparty ~tags ~at ~i (inner :: rest) role cont)

(** The states of [role]'s projection with their places (see [tags]). *)
let positions_of (tags : tags) : (session_ty * int list) list =
  (match tags.ends with [ Some p ] -> [ (SEnd, p) ] | _ -> []) @ tags.nodes

(** Substitute occurrences of [SVar x] with [replacement] inside [s]. *)
let rec subst_svar x replacement s =
  match s with
  | SVar y when y = x -> replacement
  | SSend (t, s')  -> SSend (t, subst_svar x replacement s')
  | SRecv (t, s')  -> SRecv (t, subst_svar x replacement s')
  | SChoose bs     -> SChoose (List.map (fun (l, s') -> (l, subst_svar x replacement s')) bs)
  | SOffer bs      -> SOffer  (List.map (fun (l, s') -> (l, subst_svar x replacement s')) bs)
  | SOfferPending bs -> SOfferPending (List.map (fun (l, s') -> (l, subst_svar x replacement s')) bs)
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
  | SOfferPending bs -> SChoose (List.map (fun (l, s) -> (l, dual_session_ty s)) bs)
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
    | Ast.ProtoMsg (s, r, _, _) :: rest ->
      s.Ast.txt :: r.Ast.txt :: roles_of_steps rest
    | Ast.ProtoLoop (steps, _) :: rest ->
      roles_of_steps steps @ roles_of_steps rest
    | Ast.ProtoChoice (chooser, branches) :: rest ->
      chooser.Ast.txt ::
      List.concat_map (fun (_, steps) -> roles_of_steps steps) branches @
      roles_of_steps rest
    | Ast.ProtoStop _ :: rest -> roles_of_steps rest
    | Ast.ProtoMayCrash (_, _) :: rest | Ast.ProtoRoleNeeds _ :: rest -> roles_of_steps rest
    | Ast.ProtoCrashOr (inner, crash, _) :: rest -> roles_of_steps (inner :: crash @ rest)
  in
  let roles = List.sort_uniq String.compare (roles_of_steps pdef.proto_steps) in
  let multiparty = List.length roles > 2 in
  (* Project each role *)
  let tagged = List.map (fun role ->
      let tags = { nodes = []; ends = [] } in
      let ty = project_steps_at env ~proto_name ~multiparty ~tags ~at:(Some []) ~i:0
          pdef.proto_steps role SEnd in
      (role, ty, positions_of tags)
    ) roles in
  let projections = List.map (fun (role, ty, _) -> (role, ty)) tagged in
  let positions = List.map (fun (role, _, ps) -> (role, ps)) tagged in
  (match roles with
   | [a; b] ->
     (* Binary protocol: verify duality *)
     let proj_a = List.assoc a projections in
     let proj_b = List.assoc b projections in
     let dual_a = dual_session_ty proj_a in
     if not (session_ty_equal dual_a proj_b) then
       Err.error ~code:Err.Code.protocol_projection env.errors ~span
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
       | Ast.ProtoMsg (s, r, t, _) :: rest ->
         let tvars = ref [] in
         let ty = surface_ty env ~tvars t in
         gather_msgs ((s.Ast.txt, r.Ast.txt, ty) :: acc) rest
       | Ast.ProtoLoop (inner, _) :: rest ->
         gather_msgs (gather_msgs acc inner) rest
       | Ast.ProtoChoice (_, branches) :: rest ->
         let branch_msgs = List.concat_map (fun (_, steps) ->
             gather_msgs [] steps) branches in
         gather_msgs (branch_msgs @ acc) rest
       | Ast.ProtoStop _ :: rest -> gather_msgs acc rest
       | Ast.ProtoMayCrash _ :: rest | Ast.ProtoRoleNeeds _ :: rest -> gather_msgs acc rest
       (* The crash branch is not projected here (see [project_steps_at]), so
          its messages are not gathered either: they are the generator's. *)
       | Ast.ProtoCrashOr (inner, _crash, _) :: rest -> gather_msgs acc (inner :: rest)
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
           | SChoose bs | SOffer bs | SOfferPending bs ->
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
           | SChoose bs | SOffer bs | SOfferPending bs ->
             List.exists (fun (_, s') -> has_mrecv s') bs
           | SRec (_, s') -> has_mrecv s'
           | _ -> false
         in
         (match List.assoc_opt sender projections with
          | Some proj when not (has_msend proj) ->
            Err.error ~code:Err.Code.protocol_projection env.errors ~span
              (Printf.sprintf
                 "Protocol `%s`: role `%s` should send to `%s` but \
                  its projected type does not include MSend(%s, ...)."
                 proto_name sender receiver receiver)
          | _ -> ());
         (match List.assoc_opt receiver projections with
          | Some proj when not (has_mrecv proj) ->
            Err.error ~code:Err.Code.protocol_projection env.errors ~span
              (Printf.sprintf
                 "Protocol `%s`: role `%s` should receive from `%s` but \
                  its projected type does not include MRecv(%s, ...)."
                 proto_name receiver sender sender)
          | _ -> ())
       ) msgs
   | _ -> ());  (* 0 or 1 role: already warned in caller *)
  (projections, positions)

(** This projector's view of [pdef] for translation validation against
    [Session.Theory.project] (lemmas design §5.2, M6; [March_ast.Session_term]).
    Payload ids come from the same [surface_ty] the projection uses, so a
    payload is the type the projector saw.  A binary projection's
    [SSend]/[SRecv] carry no peer: the peer is the other role. *)
let theory_view env ~proto_name (pdef : Ast.protocol_def) (projections : (string * session_ty) list) =
  let module T = March_ast.Session_term in
  let roles = T.ids () and labels = T.ids () and payloads = T.ids () in
  (* Roles numbered in the order the projections list them (sorted). *)
  List.iter (fun (r, _) -> ignore (T.id roles r)) projections;
  let role_ids = List.map (fun (r, _) -> (r, T.id roles r)) projections in
  let pay t = T.id payloads (pp_ty t) in
  try
    let global =
      T.global_of_steps ~role:(T.id roles) ~label:(T.id labels)
        ~payload:(fun t -> pay (surface_ty env ~tvars:(ref []) t))
        pdef.Ast.proto_steps
    in
    let multiparty = List.length projections > 2 in
    let local_of role (s : session_ty) =
      let other =
        match List.filter (fun (r, _) -> r <> role) role_ids with
        | [ (_, i) ] -> Some i
        | _ -> None
      in
      let binary_peer () =
        match other with Some i -> i | None -> raise (T.Outside "a peerless send in a multiparty projection")
      in
      let rec go env = function
        | SSend (t, k) -> T.LSend (binary_peer (), pay t, go env k)
        | SRecv (t, k) -> T.LRecv (binary_peer (), pay t, go env k)
        | SMSend (r, t, k) -> T.LSend (T.id roles r, pay t, go env k)
        | SMRecv (r, t, k) -> T.LRecv (T.id roles r, pay t, go env k)
        | SChoose bs -> T.LChoose (List.map (fun (l, k) -> (T.id labels l, go env k)) bs)
        | SOffer bs -> T.LOffer (List.map (fun (l, k) -> (T.id labels l, go env k)) bs)
        | SOfferPending _ -> raise (T.Outside "a pending offer")
        | SEnd -> T.LEnd
        | SRec (x, k) -> T.LRec (go (x :: env) k)
        | SVar x -> T.LVar (T.var_index env x)
        | SError -> raise (T.Outside "a projection error")
      in
      try Ok (go [] s) with T.Outside why -> Error why
    in
    Hashtbl.replace T.typecheck_views proto_name
      (Ok { T.v_global = global; v_multiparty = multiparty; v_roles = role_ids;
            v_locals = List.map (fun (r, s) -> (r, local_of r s)) projections })
  with T.Outside why -> Hashtbl.replace T.typecheck_views proto_name (Error why)
