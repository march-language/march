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
    let field_ty = llvm_ty v.Tir.v_ty in
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
    let slot_ty = Llvm_ctx.llvm_field_ty v.Tir.v_ty in
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

(** Body of the Perceus-wrapped self-TCO arm, [ELet] shape. *)
let emit_self_tco_let ~emit_atom ~emit_expr ctx (args : Tir.atom list)
  (body : Tir.expr) : string * string =
    (* 1. Evaluate every new argument value while old parameter slots are valid. *)
    let new_vals = List.map2 (fun (_vname, _slot, param_ty) a ->
        let (arg_ty, arg_val) = emit_atom ctx a in
        coerce ctx arg_ty arg_val param_ty
      ) ctx.tco_param_info args in
    (* 2. Emit the DecRC/Free chain before overwriting slots: these ops reference
          old slot values (the consumed container wrappers) which are still valid.
          Suppress tco_in_tail so nested EDecRC/EFree calls don't misfire.
          EXCEPTION: a Dec/IncRC target that is itself one of [args] is not an
          "old container being released" — it is the SAME value being forwarded
          into the next iteration's parameter slot. Under real (non-TCO)
          recursion this DecRC only fires once the whole nested call has fully
          returned, by which point nothing below still needs that reference; in
          the flattened loop there is no such delay, so executing it here would
          drop a freshly-owned, uncompensated value (no matching prior IncRC) to
          refcount 0 immediately before it is reused as the next iteration's
          value — a use-after-free. Skip RC ops on these variables; ownership is
          transferred into the new slot instead.
          EXCEPTION TO THE EXCEPTION: a forwarded argument that is DUP-BOUND
          (its binding RHS is `inc_rc x; x` — see Llvm_tco.dup_bound_vars) does
          have a matching prior IncRC, so its DecRC is the closing half of a
          balanced pair rather than an early release. Skipping it strands the
          +1 and leaks one cell per iteration (a `Cons(_, t)` list walk leaks
          the entire list). Emit those. *)
    let arg_var_names =
      List.filter_map (fun a -> match a with
        | Tir.AVar v when not (List.mem v.Tir.v_name ctx.tco_dup_bound) ->
          Some v.Tir.v_name
        | _ -> None) args
    in
    let saved_tail = ctx.tco_in_tail in
    ctx.tco_in_tail <- false;
    let skip op =
      match Llvm_tco.cleanup_target op with
      | Some n -> List.mem n arg_var_names
      | None -> false
    in
    let rec emit_dec_chain = function
      | Tir.ESeq (op, rest) when Llvm_tco.is_cleanup_op op ->
        if not (skip op) then ignore (emit_expr ctx op);
        emit_dec_chain rest
      | _ -> ()   (* EAtom(AVar tmp_v) — trailing return value, nothing to emit *)
    in
    emit_dec_chain body;
    ctx.tco_in_tail <- saved_tail;
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
    let dummy_ty = llvm_ret_ty ctx.ret_ty in
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
          ordering rationale as the ELet-wrapped case above.
          EXCEPTION: a Dec/IncRC target that is itself one of [args] is the
          SAME value being forwarded into the next iteration's parameter slot,
          not an old container being released — see the matching guard and
          explanation in the ELet-wrapped case above. Skip RC ops on these
          variables so a freshly-owned, uncompensated argument (e.g. the
          result of a fresh allocation with no prior IncRC, as opposed to a
          borrowed field promoted via IncRC) isn't dropped to refcount 0 and
          freed immediately before being reused as the next iteration's value.
          The "as opposed to" half of that sentence is the DUP-BOUND case, and
          it must NOT be skipped: there the DecRC balances the IncRC that
          materialised the local, so dropping it leaks one cell per iteration
          (see Llvm_tco.dup_bound_vars — this is the `Cons(_, t)` walk that
          leaked its whole list). *)
    let arg_var_names =
      List.filter_map (fun a -> match a with
        | Tir.AVar v when not (List.mem v.Tir.v_name ctx.tco_dup_bound) ->
          Some v.Tir.v_name
        | _ -> None) args
    in
    let saved_tail = ctx.tco_in_tail in
    ctx.tco_in_tail <- false;
    let skip op =
      match Llvm_tco.cleanup_target op with
      | Some n -> List.mem n arg_var_names
      | None -> false
    in
    let rec emit_dec_chain = function
      | Tir.ESeq (op, rest) when Llvm_tco.is_cleanup_op op ->
        if not (skip op) then ignore (emit_expr ctx op);
        emit_dec_chain rest
      | op when Llvm_tco.is_cleanup_op op ->
        if not (skip op) then ignore (emit_expr ctx op)
      | _ -> ()
    in
    emit_dec_chain dec_chain;
    ctx.tco_in_tail <- saved_tail;
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
    let dummy_ty = llvm_ret_ty ctx.ret_ty in
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
          rationale as the self-TCO ELet-wrapped case. *)
    let saved_tail = ctx.tco_in_tail in
    ctx.tco_in_tail <- false;
    let rec emit_dec_chain = function
      | Tir.ESeq (op, rest) when Llvm_tco.is_cleanup_op op ->
        ignore (emit_expr ctx op);
        emit_dec_chain rest
      | _ -> ()   (* EAtom(AVar tmp_v) — trailing return value, nothing to emit *)
    in
    emit_dec_chain body;
    ctx.tco_in_tail <- saved_tail;
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
    let dummy_ty = llvm_ret_ty ctx.ret_ty in
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
    let saved_tail = ctx.tco_in_tail in
    ctx.tco_in_tail <- false;
    let rec emit_dec_chain = function
      | Tir.ESeq (op, rest) when Llvm_tco.is_cleanup_op op ->
        ignore (emit_expr ctx op);
        emit_dec_chain rest
      | op when Llvm_tco.is_cleanup_op op -> ignore (emit_expr ctx op)
      | _ -> ()
    in
    emit_dec_chain dec_chain;
    ctx.tco_in_tail <- saved_tail;
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
    let dummy_ty = llvm_ret_ty ctx.ret_ty in
    (match dummy_ty with
     | "double" -> ("double", "0x0000000000000000")
     | "void"   -> ("i64",    "0")
     | _        -> ("i64",    "0"))

