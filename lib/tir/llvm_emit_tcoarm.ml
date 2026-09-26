(** TCO back-edge codegen: the bodies of [Llvm_emit.emit_expr]'s four
    Perceus-wrapped tail-call interception arms, plus the closure free-variable
    load arm that sits with them at the top of the match.

    Phase 2b of specs/plans/2026-08-19-compiler-file-decomposition.md, the
    per-arm delegation Phase 2 deferred.  Every arm keeps its exact position,
    guard and order in [emit_expr]'s match.  That matters more here than
    anywhere else in the function: these arms sit ABOVE most builtin arms, so a
    user function whose name collides with a builtin dispatched below them wins
    the TCO arm today, and no corpus program exercises that -- the IR oracle
    cannot see a reordering break.  Only the arm BODIES moved.

    [emit_atom] and [emit_expr] are both threaded in as labelled callbacks (all
    five bodies recurse), the convention [Llvm_emit_simd] and [Llvm_emit_nmap]
    established.  [Llvm_tco] remains the home of the tail-call ANALYSIS these
    arms' guards run; this module holds only the emission that follows it. *)

open Llvm_ctx

type emit_atom_fn = Llvm_ctx.ctx -> Tir.atom -> string * string
type emit_expr_fn = Llvm_ctx.ctx -> Tir.expr -> string * string

let emit_load_field = Llvm_data.emit_load_field
let atom_tir_ty = Llvm_data.atom_tir_ty

(** Body of the closure free-variable load arm:
    [ELet (v, EField (clo, "$fvN"), body)] loads field N off the closure. *)
let emit_fv_load ~emit_atom ~emit_expr ctx (v : Tir.var) (rhs : Tir.expr)
  (body : Tir.expr) : string * string =
    (* Emit any leading ESeq (IncRC) ops, then extract the inner EField. *)
    let rec peel_seqs e = match e with
      | Tir.EField (obj_atom, field_name) -> (obj_atom, field_name)
      | Tir.ESeq (e1, rest) ->
        ignore (emit_expr ctx e1);
        peel_seqs rest
      | _ -> assert false
    in
    let (obj_atom, field_name) = peel_seqs rhs in
    let field_idx =
      int_of_string (String.sub field_name 3 (String.length field_name - 3)) in
    let (_, obj_val) = emit_atom ctx obj_atom in
    let field_ty = llvm_ty ctx v.Tir.v_ty in
    (* Tuple fields are stored low-bit tagged (the unified slot convention): a
       direct native-typed load (e.g. `load i64`) reads the tagged value
       verbatim — Int 5 -> 11.  When the object is a tuple, load the slot as ptr
       and conditionally untag to the field's concrete type via `coerce`.
       Closure free-vars (the other `$fv` producer) keep the direct native load,
       so this is inert for defun-generated apply fns. *)
    (* A heap slot is 8 bytes, so an unboxed aggregate lives there BOXED
       ([Llvm_ctx.llvm_field_ty]).  Load the slot as ptr and let [coerce]
       rebuild the struct value the binder's type calls for — the same
       slot-vs-value split the tuple arm above makes for a tagged scalar. *)
    let slot_ty = Llvm_ctx.llvm_field_ty ctx v.Tir.v_ty in
    let fv = match atom_tir_ty obj_atom with
      | Tir.TTuple _ ->
        let raw = emit_load_field ctx obj_val field_idx "ptr" in
        coerce ctx "ptr" raw field_ty
      | _ when slot_ty <> field_ty ->
        let raw = emit_load_field ctx obj_val field_idx slot_ty in
        coerce ctx slot_ty raw field_ty
      | _ -> emit_load_field ctx obj_val field_idx field_ty
    in
    let slot = alloca_name ctx (llvm_name v.Tir.v_name) in
    emit ctx (Printf.sprintf "%%%s.addr = alloca %s" slot field_ty);
    emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" field_ty fv slot);
    Hashtbl.replace ctx.var_llvm_ty slot field_ty;
    emit_expr ctx body

(** Record a RELEASE of a forwarded argument on the loop's pending-drop list
    instead of running it.  Returns [false] when [op] is not a release this
    function knows how to defer, and the caller decides.

    The release a Perceus chain runs after a tail call that forwarded an owned
    value to a borrowed parameter belongs AFTER the nested call returns.  A
    flattened loop has no such point short of its own exit, so the back edge
    pushes (the release's runtime function, the value) onto the list held in
    [ctx.tco_defer_slot], and every return of the loop function drains it
    ([Llvm_tco.emit_defer_drain]), newest first.  That is exactly when, and in exactly
    the order, the recursion's frames would have run the releases, so the
    loop keeps recursion's ownership semantics without its stack.

    Each release is a one-pointer-argument void function: [march_decrc_local]
    for [EDecRC], [march_decrc] for [EAtomicDecRC], [march_free] for [EFree],
    and the synthesized [__drop$T] for a deep drop -- the same callees the
    ops' own [emit_expr] arms call, with the same no-op cases (a non-pointer
    value, a top-level function or builtin name that is not a local). *)
let emit_defer_release ~emit_atom ctx (op : Tir.expr) : bool =
  let release_fn = match op with
    | Tir.EDecRC _ -> Some "@march_decrc_local"
    | Tir.EAtomicDecRC _ -> Some "@march_decrc"
    | Tir.EFree _ -> Some "@march_free"
    | Tir.EApp (f, [_]) when Tir_names.is_drop_fn f.Tir.v_name ->
      Some ("@" ^ Llvm_builtins.mangle_extern f.Tir.v_name)
    | _ -> None
  in
  let target = match op with
    | Tir.EDecRC a | Tir.EAtomicDecRC a | Tir.EFree a -> Some a
    | Tir.EApp (_, [a]) -> Some a
    | _ -> None
  in
  match release_fn, target with
  | Some fn_sym, Some (Tir.AVar v as a) ->
    let is_rc_op = match op with Tir.EApp _ -> false | _ -> true in
    let inert_name =
      (Llvm_builtins.is_builtin_fn v.Tir.v_name
       || Hashtbl.mem ctx.top_fns v.Tir.v_name)
      && not (Hashtbl.mem ctx.var_slot (llvm_name v.Tir.v_name))
    in
    if is_rc_op && inert_name then true   (* the op's own arm emits nothing *)
    else begin
      let (ty, value) = emit_atom ctx a in
      if is_rc_op && ty <> "ptr" then true  (* likewise: RC arms act on ptr only *)
      else begin
        if ctx.tco_defer_slot = "" then
          failwith (Printf.sprintf
            "internal: TCO back edge in %s defers a release of %s but the loop \
             function has no pending-drop list (Llvm_tco.needs_defer_list \
             disagrees with the arm)" ctx.cur_emit_fn v.Tir.v_name);
        let pv = coerce ctx ty value "ptr" in
        let old_buf = fresh ctx "tco_defer_old" in
        let new_buf = fresh ctx "tco_defer_new" in
        emit ctx (Printf.sprintf "%s = load ptr, ptr %%%s.addr" old_buf ctx.tco_defer_slot);
        emit ctx (Printf.sprintf
          "%s = call ptr @march_tco_defer_push(ptr %s, ptr %s, ptr %s)"
          new_buf old_buf fn_sym pv);
        emit ctx (Printf.sprintf "store ptr %s, ptr %%%s.addr" new_buf ctx.tco_defer_slot);
        true
      end
    end
  | _ -> false

(** Emit a TCO back edge's Perceus cleanup chain, the ops that must run before
    the parameter slots are overwritten.  An op whose target is not a
    forwarded argument (an old container being released, a dup-bound
    argument's balancing DecRC -- see [Llvm_tco.dup_bound_vars]) is emitted
    as is.  A RELEASE of a forwarded, non-dup-bound argument is deferred to
    the loop's exit ([emit_defer_release]): emitting it here freed the value
    the next iteration reads (eafbd71a, and the mutual-TCO use-after-free of
    specs/progress/2026-09-26-mutual-tco-forwarded-arg.md), and skipping it,
    which the self arms used to do, leaked it.  An INCREMENT of a forwarded
    argument is skipped on a self back edge (unchanged) and emitted on a
    mutual one, where [Llvm_tco.group_back_edges_safe] already refused any
    group that has one. *)
let emit_back_edge_chain ~emit_atom ~emit_expr ctx ~(self : bool)
    (args : Tir.atom list) (chain : Tir.expr) : unit =
  let forwarded = Llvm_tco.forwarded_args ~dup_bound:ctx.tco_dup_bound args in
  let on_forwarded op =
    match Llvm_tco.cleanup_target op with
    | Some n -> List.mem n forwarded
    | None -> false
  in
  let emit_op op =
    if not (on_forwarded op) then ignore (emit_expr ctx op)
    else if Llvm_tco.is_release_op op && emit_defer_release ~emit_atom ctx op then ()
    else if self then ()
    else ignore (emit_expr ctx op)
  in
  let saved_tail = ctx.tco_in_tail in
  ctx.tco_in_tail <- false;
  let rec walk = function
    | Tir.ESeq (op, rest) when Llvm_tco.is_cleanup_op op -> emit_op op; walk rest
    | op when Llvm_tco.is_cleanup_op op -> emit_op op
    | _ -> ()   (* EAtom(AVar tmp_v) -- trailing return value, nothing to emit *)
  in
  walk chain;
  ctx.tco_in_tail <- saved_tail

(** Body of the Perceus-wrapped self-TCO arm, [ELet] shape. *)
let emit_self_tco_let ~emit_atom ~emit_expr ctx (args : Tir.atom list)
  (body : Tir.expr) : string * string =
    (* 1. Evaluate every new argument value while old parameter slots are valid. *)
    let new_vals = List.map2 (fun (_vname, _slot, param_ty) a ->
        let (arg_ty, arg_val) = emit_atom ctx a in
        coerce ctx arg_ty arg_val param_ty
      ) ctx.tco_param_info args in
    (* 2. Emit the DecRC/Free chain before overwriting slots: these ops reference
          old slot values (the consumed container wrappers) which are still
          valid.  A release of a forwarded argument is deferred to the loop's
          exit, not run here and not skipped; see [emit_back_edge_chain]. *)
    emit_back_edge_chain ~emit_atom ~emit_expr ctx ~self:true args body;
    (* 3. Store each new argument into the corresponding parameter alloca slot. *)
    List.iter2 (fun (_vname, slot, param_ty) new_v ->
        emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" param_ty new_v slot)
      ) ctx.tco_param_info new_vals;
    (* 4. Free any per-iteration `alloca` stack space before looping back —
          see tco_stack_save's doc comment for why this is required. *)
    if ctx.tco_stack_save <> "" then
      emit ctx (Printf.sprintf "call void @llvm.stackrestore(ptr %s)" ctx.tco_stack_save);
    (* 5. Back-edge to the TCO loop header. *)
    emit_term ctx (Printf.sprintf "br label %%%s" ctx.tco_loop_label);
    emit_label ctx (fresh_block ctx "tco_perceus_cont");
    let dummy_ty = llvm_ret_ty ctx ctx.ret_ty in
    (match dummy_ty with
     | "double" -> ("double", "0x0000000000000000")
     | "void"   -> ("i64",    "0")
     | _        -> ("i64",    "0"))

(** Body of the Perceus-wrapped self-TCO arm, no-temp [ESeq] shape. *)
let emit_self_tco_seq ~emit_atom ~emit_expr ctx (args : Tir.atom list)
  (dec_chain : Tir.expr) : string * string =
    (* 1. Evaluate every new argument value while old parameter slots are valid. *)
    let new_vals = List.map2 (fun (_vname, _slot, param_ty) a ->
        let (arg_ty, arg_val) = emit_atom ctx a in
        coerce ctx arg_ty arg_val param_ty
      ) ctx.tco_param_info args in
    (* 2. Emit the dec/inc-RC chain before overwriting slots — same
          ordering rationale as the ELet-wrapped case above. *)
    emit_back_edge_chain ~emit_atom ~emit_expr ctx ~self:true args dec_chain;
    (* 3. Store each new argument into the corresponding parameter alloca slot. *)
    List.iter2 (fun (_vname, slot, param_ty) new_v ->
        emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" param_ty new_v slot)
      ) ctx.tco_param_info new_vals;
    (* 4. Free any per-iteration `alloca` stack space before looping back. *)
    if ctx.tco_stack_save <> "" then
      emit ctx (Printf.sprintf "call void @llvm.stackrestore(ptr %s)" ctx.tco_stack_save);
    (* 5. Back-edge to the TCO loop header. *)
    emit_term ctx (Printf.sprintf "br label %%%s" ctx.tco_loop_label);
    emit_label ctx (fresh_block ctx "tco_seq_cont");
    let dummy_ty = llvm_ret_ty ctx ctx.ret_ty in
    (match dummy_ty with
     | "double" -> ("double", "0x0000000000000000")
     | "void"   -> ("i64",    "0")
     | _        -> ("i64",    "0"))

(** Body of the Perceus-wrapped mutual-TCO arm, [ELet] shape. *)
let emit_mutual_tco_let ~emit_atom ~emit_expr ctx (f : Tir.var)
  (args : Tir.atom list) (body : Tir.expr) : string * string =
    let target     = f.Tir.v_name in
    let target_tag = List.assoc target ctx.mutual_tco_fn_tags in
    let target_slots =
      try List.assoc target ctx.mutual_tco_fn_params
      with Not_found -> [] in
    (* 1. Evaluate every new argument value while old parameter slots are valid. *)
    let new_vals = List.map2 (fun (_vname, _slot, param_ty) a ->
        let (arg_ty, arg_val) = emit_atom ctx a in
        coerce ctx arg_ty arg_val param_ty
      ) target_slots args in
    (* 2. Emit the DecRC/Free chain before overwriting slots — same ordering
          rationale as the self-TCO ELet-wrapped case, including the deferred
          release of a forwarded argument. *)
    emit_back_edge_chain ~emit_atom ~emit_expr ctx ~self:false args body;
    (* 3. Update the dispatch tag. *)
    emit ctx (Printf.sprintf "store i64 %d, ptr %%%s.addr"
      target_tag ctx.mutual_tco_tag_slot);
    (* 4. Store new argument values into the target function's param slots. *)
    List.iter2 (fun (_vname, slot, param_ty) new_v ->
        emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr"
          param_ty new_v slot)
      ) target_slots new_vals;
    (* 5. Free any per-iteration `alloca` stack space before looping back. *)
    if ctx.mutual_tco_stack_save <> "" then
      emit ctx (Printf.sprintf "call void @llvm.stackrestore(ptr %s)" ctx.mutual_tco_stack_save);
    (* 6. Back-edge to the shared mutual-TCO loop header. *)
    emit_term ctx (Printf.sprintf "br label %%%s" ctx.mutual_tco_loop_label);
    emit_label ctx (fresh_block ctx "mutco_perceus_cont");
    let dummy_ty = llvm_ret_ty ctx ctx.ret_ty in
    (match dummy_ty with
     | "double" -> ("double", "0x0000000000000000")
     | "void"   -> ("i64",    "0")
     | _        -> ("i64",    "0"))

(** Body of the Perceus-wrapped mutual-TCO arm, no-temp [ESeq] shape. *)
let emit_mutual_tco_seq ~emit_atom ~emit_expr ctx (f : Tir.var)
  (args : Tir.atom list) (dec_chain : Tir.expr) : string * string =
    let target     = f.Tir.v_name in
    let target_tag = List.assoc target ctx.mutual_tco_fn_tags in
    let target_slots =
      try List.assoc target ctx.mutual_tco_fn_params
      with Not_found -> [] in
    (* 1. Evaluate every new argument value while old parameter slots are valid. *)
    let new_vals = List.map2 (fun (_vname, _slot, param_ty) a ->
        let (arg_ty, arg_val) = emit_atom ctx a in
        coerce ctx arg_ty arg_val param_ty
      ) target_slots args in
    (* 2. Emit the dec/inc-RC chain before overwriting slots — same ordering
          rationale as the ELet-wrapped case above. *)
    emit_back_edge_chain ~emit_atom ~emit_expr ctx ~self:false args dec_chain;
    (* 3. Update the dispatch tag. *)
    emit ctx (Printf.sprintf "store i64 %d, ptr %%%s.addr"
      target_tag ctx.mutual_tco_tag_slot);
    (* 4. Store new argument values into the target function's param slots. *)
    List.iter2 (fun (_vname, slot, param_ty) new_v ->
        emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr"
          param_ty new_v slot)
      ) target_slots new_vals;
    (* 5. Free any per-iteration `alloca` stack space before looping back. *)
    if ctx.mutual_tco_stack_save <> "" then
      emit ctx (Printf.sprintf "call void @llvm.stackrestore(ptr %s)" ctx.mutual_tco_stack_save);
    (* 6. Back-edge to the shared mutual-TCO loop header. *)
    emit_term ctx (Printf.sprintf "br label %%%s" ctx.mutual_tco_loop_label);
    emit_label ctx (fresh_block ctx "mutco_seq_cont");
    let dummy_ty = llvm_ret_ty ctx ctx.ret_ty in
    (match dummy_ty with
     | "double" -> ("double", "0x0000000000000000")
     | "void"   -> ("i64",    "0")
     | _        -> ("i64",    "0"))

