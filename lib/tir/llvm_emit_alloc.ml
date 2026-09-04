(** Allocation codegen: the bodies of [Llvm_emit.emit_expr]'s [EAlloc],
    [EAllocHole], [EStackAlloc] and [EReuse] arms.

    Phase 2b of specs/plans/2026-08-19-compiler-file-decomposition.md, the
    per-arm delegation Phase 2 deferred.  Every arm keeps its exact position,
    guard and order in [emit_expr]'s match -- match order there is
    load-bearing (non-builtin arms interleave with builtin ones, and the TCO
    arms sit below several builtin arms), so nothing is grouped or reordered.
    Only the arm BODIES live here, byte-identical to the text they replaced.
    [emit_atom] is threaded in as a labelled callback, the convention
    [Llvm_emit_simd] and [Llvm_emit_nmap] established; none of these bodies
    recurses into [emit_expr], so no [~emit_expr] is needed.

    The three tiny non-constructor fallbacks ([EAllocHole] of a non-TCon type,
    [ESetField], and the [EIncRC]-family arms) stay inline in [emit_expr]:
    they are shorter than the call that would replace them. *)

open Llvm_ctx

let emit_store_field = Llvm_data.emit_store_field
let emit_store_tag = Llvm_data.emit_store_tag
let emit_heap_alloc = Llvm_data.emit_heap_alloc
let emit_stack_alloc = Llvm_data.emit_stack_alloc
let ctor_entry = Llvm_data.ctor_entry
let get_record_fields = Llvm_data.get_record_fields
let emit_set_shape = Llvm_data.emit_set_shape
let mangle_ty_for_eq = Llvm_eq.mangle_ty_for_eq

(** Body of the capture-free-lambda arm: a static, immortal global closure
    instead of a heap allocation. *)
let emit_static_closure ctx (tcon_name : string) (fn_ptr_atom : Tir.atom)
  : string * string =
    let apply_tir_name =
      match fn_ptr_atom with
      | Tir.AVar v    -> v.Tir.v_name
      | Tir.ADefRef d -> d.Tir.did_name
      | Tir.ALit _    -> assert false
    in
    let apply_sym =
      match fn_ptr_atom with
      | Tir.AVar v    -> llvm_name v.Tir.v_name
      | Tir.ADefRef d -> llvm_name d.Tir.did_name
      | Tir.ALit _    ->
        (* Excluded by the match guard above — defun.ml always builds
           fn_ptr_atom as an AVar naming the lifted apply function, never a
           literal. Kept as a hard failure (not a silent fallback) so a
           future defun.ml change that violates the invariant is caught
           here rather than miscompiling silently. *)
        assert false
    in
    ("ptr", Llvm_ctx.intern_static_closure
              ~pad:(Clo_flags.pad_for apply_tir_name)
              ctx (llvm_name tcon_name) apply_sym)

(** Body of the [EAlloc] constructor arm: the general heap allocation. *)
let emit_alloc_ctor ~emit_atom ctx (ctor : string)
  (alloc_params : Tir.ty list) (args : Tir.atom list) : string * string =
    (* EAlloc ctor key is "TypeName.CtorName"; repr_of_ty needs the TypeName. *)
    let alloc_type_name = match String.rindex_opt ctor '.' with
      | Some i -> String.sub ctor 0 i
      | None -> ctor
    in
    (* Repr audit hook — records the encoding this alloc site commits to. *)
    let audit fam site =
      repr_audit_record ~ty:alloc_type_name
        ~payload:(match alloc_params with
          | [] -> "?"
          | ps -> String.concat "," (List.map mangle_ty_for_eq ps))
        ~family:fam ~site:(site ^ ":" ^ ctor ^ " in " ^ ctx.cur_emit_fn)
    in
    let alloc_result =
     (match Repr.repr_of_ty ~collision_set:ctx.collision_set ctx.type_defs (Tir.TCon (alloc_type_name, [])) with
     | Repr.Unboxed { ctor = _; fields } ->
       audit "Unboxed" "alloc";
       (* Milestone 3: no cell.  Build the LLVM struct value directly with an
          [insertvalue] chain; the fields are scalars by construction (see
          [Repr.set_unboxed_types]) so each one is already in its own register.
          A consumer that needs the boxed form gets it from [Llvm_ctx.coerce],
          which reconstructs exactly the cell this arm used to allocate. *)
       let sty = Llvm_ctx.llvm_ty (Tir.TCon (alloc_type_name, [])) in
       if List.length args <> List.length fields then
         failwith (Printf.sprintf
           "LLVM emit: unboxed constructor %s expects %d arg(s), got %d \
            (arity mismatch — malformed TIR)"
           ctor (List.length fields) (List.length args));
       let acc = ref "poison" in
       List.iteri (fun i atom ->
           let fty = Llvm_ctx.llvm_ty (List.nth fields i) in
           let (v_ty, v_val) = emit_atom ctx atom in
           let fv = coerce ctx v_ty v_val fty in
           let nx = fresh ctx "ubmk" in
           emit ctx (Printf.sprintf "%s = insertvalue %s %s, %s %s, %d"
                       nx sty !acc fty fv i);
           acc := nx)
         args;
       (sty, !acc)
     | Repr.Newtype payload ->
       audit "Newtype" "alloc";
       (* Newtype: no allocation. Emit the single payload atom directly. *)
       if List.length args <> 1 then
         failwith (Printf.sprintf
           "LLVM emit: newtype constructor %s expects 1 arg, got %d \
            (arity mismatch — malformed TIR)"
           ctor (List.length args));
       let (v_ty, v_val) = emit_atom ctx (List.hd args) in
       if Repr.payload_needs_tag ~collision_set:ctx.collision_set ctx.type_defs payload then begin
         (* Scalar payload: tag (v<<1)|1 so it's odd → IS_HEAP_PTR = false *)
         let i64v = coerce ctx v_ty v_val "i64" in
         let as_ptr = emit_tag_scalar ctx ~sh:"nt_sh" ~tag:"nt_tag" ~ptr:"nt_ptr" i64v in
         ("ptr", as_ptr)
       end else
         (* Pointer payload: pass through raw *)
         ("ptr", coerce ctx v_ty v_val "ptr")
     | _ when Repr.is_niche_shaped ~collision_set:ctx.collision_set ctx.type_defs alloc_type_name ->
       (* Niche (Option-shaped): None=0, Some(x)=x.
          repr_of_ty returns Boxed here because EAlloc's ctor key carries no type
          params; we use the actual arg TIR type to determine tagging. *)
       let emit_niche_payload arg =
         let arg_tir_ty = match arg with
           | Tir.AVar v -> v.Tir.v_ty
           | Tir.ALit (March_ast.Ast.LitInt _) -> Tir.TInt
           | Tir.ALit (March_ast.Ast.LitBool _) -> Tir.TBool
           | Tir.ALit (March_ast.Ast.LitFloat _) -> Tir.TFloat
           | Tir.ALit (March_ast.Ast.LitString _) -> Tir.TString
           | _ -> Tir.TUnit
         in
         let arg_niche_ok =
           Repr.niche_payload_ok ~collision_set:ctx.collision_set ctx.type_defs arg_tir_ty
           (* Erased (TVar) payload: the rest of the erased convention —
              emit_case's abstract-arg niche path, ensure_adt_eq_fn, and the
              nullary-None alloc — treats Option(TVar) as NICHE, and a TVar
              slot value is already uniform (heap ptr raw / scalar tagged), so
              pass it through raw.  Boxing here made e.g. alist_get's
              Some(field) a heap cell that its niche-matching callers read as
              the payload itself (caught by MARCH_REPR_AUDIT:
              alloc-some-boxed(?) vs case=Niche(Any)). *)
           || (match arg_tir_ty with Tir.TVar _ -> true | _ -> false)
         in
         if not arg_niche_ok then None
         else begin
           let (v_ty, v_val) = emit_atom ctx arg in
           if Repr.payload_needs_tag ~collision_set:ctx.collision_set ctx.type_defs arg_tir_ty then begin
             let i64v = coerce ctx v_ty v_val "i64" in
             let as_ptr = emit_tag_scalar ctx ~sh:"niche_sh" ~tag:"niche_tag" ~ptr:"niche_ptr" i64v in
             Some ("ptr", as_ptr)
           end else
             Some ("ptr", coerce ctx v_ty v_val "ptr")
         end
       in
       (match args with
        | [] ->
          (* Nullary ctor (None).  For a niche-SAFE payload it is raw 0 (null).
             But when the payload is niche-UNSAFE (e.g. Option(Option(_)) or
             Option(Float)), the Some case above is emitted BOXED (its
             emit_niche_payload returns None → the boxed-Some fallthrough), so
             None must ALSO be boxed — otherwise the value is inconsistently
             encoded (Some=heap cell, None=null) and the match, which uses the
             concrete Boxed repr, loads a ctor tag from the null None → SIGSEGV
             (Preload.extract_values_at over Option(Option(String)) rows). The
             EAlloc ctor key has no payload, so use the TCon type params. *)
          let payload_niche_safe = match alloc_params with
            | [p] ->
              Repr.niche_payload_ok ~collision_set:ctx.collision_set ctx.type_defs p
              (* Abstract (erased) payload: emit_case's abstract-arg niche path
                 and ensure_adt_eq_fn both treat Option(TVar) as NICHE, so the
                 alloc must too — boxing None here would make a niche match read
                 the non-null cell as Some (caught by MARCH_REPR_AUDIT:
                 case=Niche(Any) vs alloc-none-boxed=Boxed(Any)). *)
              || (match p with Tir.TVar _ -> true | _ -> false)
            | _ ->
              (* Non-generic type (no params on the ctor key): the variant DEF
                 carries the concrete payload type — key the encode on the same
                 classification the decode (emit_case) uses, so None and Some
                 stay consistently encoded (both niche, or both boxed). *)
              (match Repr.niche_repr_of_concrete ~collision_set:ctx.collision_set ctx.type_defs alloc_type_name with
               | Some _ -> true
               | None   -> false)
          in
          if payload_niche_safe then begin
            audit "Niche" "alloc-none";
            (* Distinct prefix from the niche-None BLOCK label (fresh_block ctx
               "niche_none").  fresh/fresh_block use independent counters, so a
               shared prefix can mint an SSA value and a block label with the same
               name (e.g. %niche_none10 and block niche_none10) — LLVM shares the
               value/label namespace, so the branch target then resolves to the
               value: "'%niche_none10' is not a basic block". *)
            let z = fresh ctx "niche_nullval" in
            emit ctx (Printf.sprintf "%s = inttoptr i64 0 to ptr" z);
            ("ptr", z)
          end else begin
            audit "Boxed" "alloc-none-boxed";
            (* Boxed None: a tag-0 heap cell with no fields, matching the boxed
               Some encoding for this niche-unsafe Option. *)
            let entry = ctor_entry ctx ctor 0 in
            let ptr = emit_heap_alloc ctx entry.ce_tag 0 in
            ("ptr", ptr)
          end
        | [arg] ->
          (* Key the audit by the ARG's type — for a single-field ctor that IS
             the payload, and far more attributable than the "?" the paramless
             EAlloc key would give. *)
          let audit_arg fam site =
            let arg_key = mangle_ty_for_eq (match arg with
              | Tir.AVar v -> v.Tir.v_ty
              | Tir.ALit (March_ast.Ast.LitInt _) -> Tir.TInt
              | Tir.ALit (March_ast.Ast.LitBool _) -> Tir.TBool
              | Tir.ALit (March_ast.Ast.LitFloat _) -> Tir.TFloat
              | Tir.ALit (March_ast.Ast.LitString _) -> Tir.TString
              | _ -> Tir.TUnit) in
            repr_audit_record ~ty:alloc_type_name ~payload:arg_key
              ~family:fam ~site:(site ^ ":" ^ ctor ^ " in " ^ ctx.cur_emit_fn)
          in
          (match emit_niche_payload arg with
           | Some result -> audit_arg "Niche" "alloc-some"; result
           | None ->
             audit_arg "Boxed" "alloc-some-boxed";
             (* Payload not niche-safe (Float/Unit/Bool) — fall through to boxed *)
             let entry = ctor_entry ctx ctor (List.length args) in
             let ptr = emit_heap_alloc ctx entry.ce_tag (List.length args) in
             let field_ty = match List.nth_opt entry.ce_fields 0 with
               | Some t -> llvm_field_ty t | None -> "ptr" in
             let (v_ty, v_val) = emit_atom ctx arg in
             emit_store_field ctx ptr 0 field_ty (coerce ctx v_ty v_val field_ty);
             ("ptr", ptr))
        | _ ->
          audit "Boxed" "alloc-multi";
          (* Multi-arg ctor that happens to share the type name — boxed *)
          let entry = ctor_entry ctx ctor (List.length args) in
          let ptr = emit_heap_alloc ctx entry.ce_tag (List.length args) in
          List.iteri (fun i atom ->
            let field_ty = match List.nth_opt entry.ce_fields i with
              | Some t -> llvm_field_ty t | None -> "ptr" in
            let (v_ty, v_val) = emit_atom ctx atom in
            emit_store_field ctx ptr i field_ty (coerce ctx v_ty v_val field_ty)
          ) args;
          ("ptr", ptr))
     | _ ->
       audit "Boxed" "alloc";
       let entry = ctor_entry ctx ctor (List.length args) in
       let ptr = emit_heap_alloc ctx entry.ce_tag (List.length args) in
       List.iteri (fun i atom ->
         let field_ty = match List.nth_opt entry.ce_fields i with
           | Some t -> llvm_field_ty t
           | None ->
             failwith (Printf.sprintf
               "LLVM emit: constructor %s has %d field(s) but field index %d \
                was requested (arity mismatch — cascading from a ctor_info collision?)"
               ctor (List.length entry.ce_fields) i)
         in
         let (v_ty, v_val) = emit_atom ctx atom in
         let v_coerced = coerce ctx v_ty v_val field_ty in
         emit_store_field ctx ptr i field_ty v_coerced
       ) args;
       (* Actor structs get a runtime shape id stamped into the header pad
          word so get_actor_field's C implementation (march_get_actor_field,
          runtime/march_extras.c) can look up a named state field by the
          actor's own shape at runtime, regardless of whether the caller's
          static Pid(a) type is concrete at that call site (it usually is
          NOT — a call routed through a small generic helper like
          child_int(sup, field) never resolves `a` past an abstract type
          variable, since nothing in get_actor_field's own signature forces
          monomorphization on it). Scoped to actor structs only via
          is_actor_struct_name — not a general shape-stamping change for
          every Boxed EAlloc/ctor-application site. *)
       if Tir_names.is_actor_struct_name alloc_type_name then
         emit_set_shape ctx ptr (get_record_fields ctx (Tir.TCon (alloc_type_name, [])));
       (* HCR: if this is a known actor type, wire the dispatch slot ID immediately
          after allocation so the actor green thread uses the hot-reload table.
          Counter_spawn() is inlined+DCE'd by mono, so we can't rely on a spawn
          wrapper; injecting here survives all IR transformations.
          Actor types are named <Base>_Actor; dispatch functions are <Base>_dispatch. *)
       let actor_sfx = Tir_names.actor_struct_suffix in
       let atn_len = String.length alloc_type_name in
       let sfx_len = String.length actor_sfx in
       if ctx.hr_config <> None
          && Tir_names.is_actor_struct_name alloc_type_name
       then begin
         let actor_base = String.sub alloc_type_name 0 (atn_len - sfx_len) in
         let dispatch_fn = actor_base ^ Tir_names.actor_dispatch_suffix in
         match Hot_reload.Name_table.id_of ctx.hr_names dispatch_fn with
         | Some id0 ->
           let slot_id = id0 + 1 in  (* 1-based; 0 = "not set" sentinel *)
           emit ctx (Printf.sprintf
             "call void @march_actor_set_dispatch_id(ptr %s, i32 %d)" ptr slot_id)
         | None -> ()
       end;
       (* Actor.call tag-base registration. F19 (build_ctor_info) gives actor
          _Msg ctors GLOBALLY-unique tags (base 0x0100_0000 + declaration
          index) so cross-actor sends can't misroute — but march_actor_call
          stamps the augmented call message with the SENTINEL's per-type
          0-based tag (= handler index). Register this actor's first-msg-ctor
          global tag so the runtime can translate index → global tag; without
          it every compiled Actor.call falls to the dispatch default arm and
          is dropped (the caller blocks forever / times out). Emitted at the
          alloc (like the shape stamp above) so supervisor respawns, which
          re-run the March-level spawn closure, re-register the fresh record. *)
       if Tir_names.is_actor_struct_name alloc_type_name then begin
         let actor_base = String.sub alloc_type_name 0 (atn_len - sfx_len) in
         let msg_ty_name = actor_base ^ Tir_names.actor_msg_suffix in
         let first_ctor = List.find_map (function
           | Tir.TDVariant (n, (c, _) :: _) when n = msg_ty_name -> Some c
           | _ -> None) ctx.type_defs
         in
         match first_ctor with
         | Some c ->
           (match Hashtbl.find_opt ctx.ctor_info (msg_ty_name ^ "." ^ c) with
            | Some e ->
              emit ctx (Printf.sprintf
                "call void @march_actor_set_call_base(ptr %s, i64 %d)"
                ptr e.ce_tag)
            | None -> ())
         | None -> ()
       end;
       ("ptr", ptr))
    in
    (* Closure objects carry ONE bit of borrow information about the function
       they dispatch to, stamped into the header pad word (offset 12, the same
       otherwise-unused slot the actor-shape stamp above uses): whether the
       callee leaves its first user argument BORROWED.  The C runtime's fold
       helpers read it back (MARCH_CLO_ARG0_BORROWED, runtime/march_runtime.h)
       to decide whether they still own the accumulator they passed in — a
       question no dynamic test can answer; see [Clo_flags] for the full
       argument.  Scoped to closure structs only ("$Clo_..."), like the actor
       stamp above, and emitted only when the bit is SET, so the common
       no-information case costs nothing. *)
    (match alloc_result with
     (* "ptr" specifically: a closure struct is always Boxed, and a
        non-pointer result would mean the repr classification changed under
        us — GEPing into it would be nonsense, so fall through instead. *)
     | ("ptr", clo_ptr) when Tir_names.is_clo_struct ctor ->
       let pad =
         match args with
         | Tir.AVar v :: _    -> Clo_flags.pad_for v.Tir.v_name
         | Tir.ADefRef d :: _ -> Clo_flags.pad_for d.Tir.did_name
         | _ -> 0
       in
       if pad <> 0 then begin
         let pp = fresh ctx "clopad" in
         emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 12" pp clo_ptr);
         emit ctx (Printf.sprintf "store i32 %d, ptr %s, align 4" pad pp)
       end
     | _ -> ());
    alloc_result


(** Body of the non-constructor [EAlloc] arm. *)
let emit_alloc_uniform ~emit_atom ctx (args : Tir.atom list) : string * string =
    (* Non-TCon allocation (tuples / erased cells): UNIFORM slots — readers
       go through ctor_entry fallbacks that load ptr and untag conditionally. *)
    let n = List.length args in
    let ptr = emit_heap_alloc ctx 0 n in
    List.iteri (fun i atom ->
      let (ty, v) = emit_atom ctx atom in
      let vp = coerce ctx ty v "ptr" in
      emit_store_field ctx ptr i "ptr" vp
    ) args;
    ("ptr", ptr)

(** Body of the [EAllocHole] constructor arm (TRMC hole allocation). *)
let emit_alloc_hole ~emit_atom ctx (tok : Tir.atom option)
  (ctor : string) (args : Tir.atom list) (hole : int) : string * string =
    (* Same repr guard as EStackAlloc: this arm builds a BOXED cell
       unconditionally, so a Newtype-/Niche-repr type would be constructed
       boxed and decoded erased.  TRMC must never select such a type. *)
    let ah_type_name = match String.rindex_opt ctor '.' with
      | Some i -> String.sub ctor 0 i
      | None -> ctor
    in
    (match Repr.repr_of_ty ~collision_set:ctx.collision_set ctx.type_defs (Tir.TCon (ah_type_name, [])) with
     | Repr.Newtype _ | Repr.Niche _ | Repr.Unboxed _ ->
       failwith (Printf.sprintf
         "LLVM emit: EAllocHole of erased-repr type %s (ctor %s) — a hole needs \
          a real heap cell; TRMC must not select an erased-repr constructor"
         ah_type_name ctor)
     | Repr.Boxed ->
       if Repr.is_niche_shaped ~collision_set:ctx.collision_set ctx.type_defs ah_type_name then
         failwith (Printf.sprintf
           "LLVM emit: EAllocHole of niche-shaped type %s (ctor %s) — same \
            erased-vs-boxed split as Newtype"
           ah_type_name ctor));
    let arity = List.length args + 1 in
    if hole < 0 || hole >= arity then
      failwith (Printf.sprintf
        "LLVM emit: EAllocHole of %s has hole index %d outside arity %d"
        ctor hole arity);
    let entry = ctor_entry ctx ctor arity in
    (* [args] carries only the FILLED fields, in order, with the hole's slot
       skipped.  Pair each with its destination index and LLVM field type, and
       evaluate the operands ONCE here — before any branch — so the reuse and
       fresh paths below store already-materialised SSA values (same discipline
       as EReuse; evaluating inside a branch would define values in one block
       and use them in another). *)
    let slot_vals =
      let rest = ref args in
      List.filter_map (fun i ->
        if i = hole then None
        else match !rest with
          | atom :: tl ->
            rest := tl;
            let field_ty = match List.nth_opt entry.ce_fields i with
              | Some t -> llvm_field_ty t | None -> "ptr" in
            let (v_ty, v_val) = emit_atom ctx atom in
            Some (i, field_ty, coerce ctx v_ty v_val field_ty)
          | [] ->
            failwith (Printf.sprintf
              "LLVM emit: EAllocHole of %s supplies %d filled field(s) for arity %d"
              ctor (List.length args) arity)
      ) (List.init arity (fun i -> i))
    in
    let store_slots p =
      List.iter (fun (i, field_ty, v) -> emit_store_field ctx p i field_ty v)
        slot_vals
    in
    (match tok with
     | None ->
       let ptr = emit_heap_alloc ctx entry.ce_tag arity in
       store_slots ptr;
       ("ptr", ptr)
     | Some reuse_atom ->
       (* Same discipline as EReuse: take the cell over when it is unique at
          runtime, otherwise release it and allocate fresh. *)
       let (_, rv) = emit_atom ctx reuse_atom in
       let rc = fresh ctx "rhrc" in
       emit ctx (Printf.sprintf
                   "%s = load atomic i64, ptr %s monotonic, align 8" rc rv);
       let uniq = fresh ctx "rhuniq" in
       emit ctx (Printf.sprintf "%s = icmp eq i64 %s, 1" uniq rc);
       let reuse_lbl = fresh_block ctx "rhole_reuse" in
       let fresh_lbl = fresh_block ctx "rhole_fresh" in
       let merge_lbl = fresh_block ctx "rhole_merge" in
       emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
                        uniq reuse_lbl fresh_lbl);
       emit_label ctx reuse_lbl;
       emit_store_tag ctx rv entry.ce_tag;
       store_slots rv;
       (* A fresh cell comes from calloc and is already zero.  A REUSED cell is
          not: its hole slot still holds the old child pointer, whose ownership
          has already moved to the match's branch variables.  Leaving it there
          would let any drop in the window before the fill walk into a child
          someone else now owns — so clear it explicitly. *)
       emit_store_field ctx rv hole "ptr" "null";
       emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl);
       emit_label ctx fresh_lbl;
       emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" rv);
       let hp = emit_heap_alloc ctx entry.ce_tag arity in
       store_slots hp;
       emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl);
       emit_label ctx merge_lbl;
       let result = fresh ctx "rhole_r" in
       emit ctx (Printf.sprintf "%s = phi ptr [ %s, %%%s ], [ %s, %%%s ]"
                   result rv reuse_lbl hp fresh_lbl);
       ("ptr", result))

(** Body of the [EStackAlloc] constructor arm. *)
let emit_stack_alloc_ctor ~emit_atom ctx (ctor : string)
  (args : Tir.atom list) : string * string =
    (* Repr guard (slice-7 L7): this arm builds a BOXED stack cell
       unconditionally, so it must never receive a Newtype- or Niche-repr
       type — those "allocs" are erased immediates, and every consumer
       decodes them under the erased convention (an ECase would untag the
       stack POINTER → garbage). Escape.alloc_emits_heap_cell keeps such
       allocs out of stack promotion; fail loudly if one slips through. *)
    let sa_type_name = match String.rindex_opt ctor '.' with
      | Some i -> String.sub ctor 0 i
      | None -> ctor
    in
    (match Repr.repr_of_ty ~collision_set:ctx.collision_set ctx.type_defs (Tir.TCon (sa_type_name, [])) with
     | Repr.Newtype _ | Repr.Niche _ | Repr.Unboxed _ ->
       failwith (Printf.sprintf
         "LLVM emit: EStackAlloc of erased-repr type %s (ctor %s) — \
          construction would be boxed but consumers decode erased; \
          escape analysis must not promote this alloc (finding L7)"
         sa_type_name ctor)
     | Repr.Boxed ->
       if Repr.is_niche_shaped ~collision_set:ctx.collision_set ctx.type_defs sa_type_name then
         failwith (Printf.sprintf
           "LLVM emit: EStackAlloc of niche-shaped type %s (ctor %s) — \
            same erased-vs-boxed split as Newtype (finding L7)"
           sa_type_name ctor));
    let entry = ctor_entry ctx ctor (List.length args) in
    let ptr = emit_stack_alloc ctx (List.length args) in
    emit_store_tag ctx ptr entry.ce_tag;
    List.iteri (fun i atom ->
      let field_ty = match List.nth_opt entry.ce_fields i with
        | Some t -> llvm_field_ty t
        | None ->
          failwith (Printf.sprintf
            "LLVM emit: constructor %s has %d field(s) but field index %d \
             was requested (arity mismatch — cascading from a ctor_info collision?)"
            ctor (List.length entry.ce_fields) i)
      in
      let (v_ty, v_val) = emit_atom ctx atom in
      let v_coerced = coerce ctx v_ty v_val field_ty in
      emit_store_field ctx ptr i field_ty v_coerced
    ) args;
    ("ptr", ptr)

(** Body of the non-constructor [EStackAlloc] arm. *)
let emit_stack_alloc_uniform ~emit_atom ctx (args : Tir.atom list)
  : string * string =
    (* Non-TCon stack allocation: UNIFORM slots, mirroring EAlloc above. *)
    let n = List.length args in
    let ptr = emit_stack_alloc ctx n in
    List.iteri (fun i atom ->
      let (ty, v) = emit_atom ctx atom in
      let vp = coerce ctx ty v "ptr" in
      emit_store_field ctx ptr i "ptr" vp
    ) args;
    ("ptr", ptr)

(** Body of the [EReuse] constructor arm: FBIP in-place reuse guarded on
    RC=1, falling back to a fresh allocation. *)
let emit_reuse_ctor ~emit_atom ctx (reuse_atom : Tir.atom) (ctor : string)
  (args : Tir.atom list) : string * string =
    (* Newtype fast path: no heap cell to reuse. Emit new payload directly.
       The old reuse_atom is a tagged scalar or pointer; release it via
       march_decrc (IS_HEAP_PTR guards make it a no-op on tagged scalars). *)
    let reuse_type_name = match String.rindex_opt ctor '.' with
      | Some i -> String.sub ctor 0 i
      | None -> ctor
    in
    (match Repr.repr_of_ty ~collision_set:ctx.collision_set ctx.type_defs (Tir.TCon (reuse_type_name, [])) with
     | Repr.Newtype payload ->
       let (_, rv) = emit_atom ctx reuse_atom in
       emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" rv);
       let (v_ty, v_val) = emit_atom ctx (List.hd args) in
       if Repr.payload_needs_tag ~collision_set:ctx.collision_set ctx.type_defs payload then begin
         let i64v = coerce ctx v_ty v_val "i64" in
         let as_ptr = emit_tag_scalar ctx ~sh:"nt_sh" ~tag:"nt_tag" ~ptr:"nt_ptr" i64v in
         ("ptr", as_ptr)
       end else
         ("ptr", coerce ctx v_ty v_val "ptr")
     | _ when Repr.is_niche_shaped ~collision_set:ctx.collision_set ctx.type_defs reuse_type_name ->
       (* Niche reuse: old value is itself a niche value (0, tagged-int, or ptr).
          march_decrc's IS_HEAP_PTR guard makes it a no-op on 0 and tagged ints. *)
       let (_, old_v) = emit_atom ctx reuse_atom in
       emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" old_v);
       let emit_niche_payload arg =
         let arg_tir_ty = match arg with
           | Tir.AVar v -> v.Tir.v_ty
           | Tir.ALit (March_ast.Ast.LitInt _) -> Tir.TInt
           | Tir.ALit (March_ast.Ast.LitBool _) -> Tir.TBool
           | Tir.ALit (March_ast.Ast.LitFloat _) -> Tir.TFloat
           | Tir.ALit (March_ast.Ast.LitString _) -> Tir.TString
           | _ -> Tir.TUnit
         in
         let arg_niche_ok =
           Repr.niche_payload_ok ~collision_set:ctx.collision_set ctx.type_defs arg_tir_ty
           (* Erased (TVar) payload: the rest of the erased convention —
              emit_case's abstract-arg niche path, ensure_adt_eq_fn, and the
              nullary-None alloc — treats Option(TVar) as NICHE, and a TVar
              slot value is already uniform (heap ptr raw / scalar tagged), so
              pass it through raw.  Boxing here made e.g. alist_get's
              Some(field) a heap cell that its niche-matching callers read as
              the payload itself (caught by MARCH_REPR_AUDIT:
              alloc-some-boxed(?) vs case=Niche(Any)). *)
           || (match arg_tir_ty with Tir.TVar _ -> true | _ -> false)
         in
         if not arg_niche_ok then None
         else begin
           let (v_ty, v_val) = emit_atom ctx arg in
           if Repr.payload_needs_tag ~collision_set:ctx.collision_set ctx.type_defs arg_tir_ty then begin
             let i64v = coerce ctx v_ty v_val "i64" in
             let as_ptr = emit_tag_scalar ctx ~sh:"niche_sh" ~tag:"niche_tag" ~ptr:"niche_ptr" i64v in
             Some ("ptr", as_ptr)
           end else
             Some ("ptr", coerce ctx v_ty v_val "ptr")
         end
       in
       (match args with
        | [] when (match Repr.niche_repr_of_concrete ~collision_set:ctx.collision_set ctx.type_defs reuse_type_name with
                   | Some _ -> true
                   (* Payload not niche-safe (e.g. Float): the Some side is
                      encoded BOXED (emit_niche_payload returns None), so None
                      must be boxed too — fall through to the boxed path below,
                      mirroring EAlloc's alloc-none-boxed. *)
                   | None -> false) ->
          (* Distinct prefix from the niche-None BLOCK label (fresh_block ctx
             "niche_none").  fresh/fresh_block use independent counters, so a
             shared prefix can mint an SSA value and a block label with the same
             name (e.g. %niche_none10 and block niche_none10) — LLVM shares the
             value/label namespace, so the branch target then resolves to the
             value: "'%niche_none10' is not a basic block". *)
          let z = fresh ctx "niche_nullval" in
          emit ctx (Printf.sprintf "%s = inttoptr i64 0 to ptr" z);
          ("ptr", z)
        | [arg] ->
          (match emit_niche_payload arg with
           | Some result -> result
           | None ->
             let entry = ctor_entry ctx ctor (List.length args) in
             let ptr = emit_heap_alloc ctx entry.ce_tag (List.length args) in
             let field_ty = match List.nth_opt entry.ce_fields 0 with
               | Some t -> llvm_field_ty t | None -> "ptr" in
             let (v_ty, v_val) = emit_atom ctx arg in
             emit_store_field ctx ptr 0 field_ty (coerce ctx v_ty v_val field_ty);
             ("ptr", ptr))
        | _ ->
          let entry = ctor_entry ctx ctor (List.length args) in
          let ptr = emit_heap_alloc ctx entry.ce_tag (List.length args) in
          List.iteri (fun i atom ->
            let field_ty = match List.nth_opt entry.ce_fields i with
              | Some t -> llvm_field_ty t | None -> "ptr" in
            let (v_ty, v_val) = emit_atom ctx atom in
            emit_store_field ctx ptr i field_ty (coerce ctx v_ty v_val field_ty)
          ) args;
          ("ptr", ptr))
     | _ ->
    (* Guard: if the reuse_atom's own type is niche-shaped (e.g. Option.Some),
       the scrutinee IS the payload — no wrapper object was allocated.
       FBIP reuse would overwrite the payload's own memory with the new
       object's tag/fields, corrupting whatever type the payload holds.
       Additionally, for patterns like [Some(result) -> Ok(result)], the
       branch variable 'result' and dec_v are the same runtime pointer, so
       calling march_decrc(dec_v) in the fresh branch would decrement the
       very value we're about to store as Ok's field (use-after-free).
       Skip FBIP: allocate fresh without touching reuse_atom's RC. *)
    let reuse_atom_parent_type = match reuse_atom with
      | Tir.AVar v ->
        (match v.Tir.v_ty with
         | Tir.TCon (name, _) ->
           (match String.rindex_opt name '.' with
            | Some i -> String.sub name 0 i
            | None -> name)
         | _ -> "")
      | _ -> ""
    in
    if reuse_atom_parent_type <> ""
       && Repr.is_niche_shaped ~collision_set:ctx.collision_set ctx.type_defs reuse_atom_parent_type
    then begin
      let entry = ctor_entry ctx ctor (List.length args) in
      let ptr = emit_heap_alloc ctx entry.ce_tag (List.length args) in
      List.iteri (fun i atom ->
        let field_ty = match List.nth_opt entry.ce_fields i with
          | Some t -> llvm_field_ty t
          | None -> failwith (Printf.sprintf
              "LLVM emit: constructor %s has %d field(s) but field index %d \
               was requested (arity mismatch)"
              ctor (List.length entry.ce_fields) i)
        in
        let (v_ty, v_val) = emit_atom ctx atom in
        emit_store_field ctx ptr i field_ty (coerce ctx v_ty v_val field_ty)
      ) args;
      ("ptr", ptr)
    end
    else if Repr.is_actor_struct_type ctx.type_defs reuse_type_name then begin
      (* Actor-state update (finding 20): an actor's message handler writes its
         new state back into the actor struct via EReuse (see
         lib/tir/lower_actor.ml).  The actor object is a stable, long-lived
         singleton mutated SOLELY by its own daemon green thread — the RC of the
         actor *handle* (how many `Pid` references exist) has nothing to do with
         whether an in-place state write is safe.  The generic RC-conditional
         FBIP path below is actively WRONG here: the main thread legitimately
         does atomic incrc/decrc on the actor handle as it passes the Pid to
         successive `send`s, so the handler's `rc == 1` check races that and can
         observe rc > 1, taking the "fresh" branch — which allocates a COPY,
         writes the new state into the copy, and DISCARDS it (the handler's
         result is unit), silently LOSING the state update (memory-safe: no
         crash, just a wrong-but-valid count).  actor_green_thread's
         `a[0]=1` force to defeat the check is itself racy against that concurrent
         incrc and cannot be made safe.  The fix: for an actor struct, ALWAYS
         mutate in place — no RC load, no branch, no decrc, no fresh alloc.

         Gate MUST be structural, not name-based: an adversarial review found
         that a name-suffix check (the type con name ending in "_Actor") false-
         positive-matched a user type coincidentally named e.g. `Tree_Actor`,
         silently corrupting it under a shared (RC>1) FBIP reuse by skipping the
         refcount check that shared-value safety depends on. [Repr.is_actor_struct_type]
         instead confirms the type's field 0 is literally named "$d_dispatch" —
         a name only [lower_actor.ml] can ever construct (user identifiers can
         never start with `$`), so this cannot false-positive on user code. *)
      let (_, rv) = emit_atom ctx reuse_atom in
      let entry = ctor_entry ctx ctor (List.length args) in
      emit_store_tag ctx rv entry.ce_tag;
      List.iteri (fun i atom ->
        let field_ty = match List.nth_opt entry.ce_fields i with
          | Some t -> llvm_field_ty t
          | None -> failwith (Printf.sprintf
              "LLVM emit: actor-struct reuse %s has %d field(s) but field index \
               %d was requested (arity mismatch)"
              ctor (List.length entry.ce_fields) i)
        in
        let (v_ty, v_val) = emit_atom ctx atom in
        emit_store_field ctx rv i field_ty (coerce ctx v_ty v_val field_ty)
      ) args;
      ("ptr", rv)
    end
    else begin
    let (_, rv) = emit_atom ctx reuse_atom in
    let entry = ctor_entry ctx ctor (List.length args) in
    (* FULL-OVERWRITE invariant (fail-loudly): the reuse's arg count must
       equal the resolved constructor's declared field count.  The
       reuse-preserves-semantics rule (core-march.md §4.16) rests on the
       reuse branch overwriting the ENTIRE payload — tag + every field — so
       the reused cell is observationally identical to a fresh allocation.
       An UNDER-write (fewer args than ce_fields) would silently leave the
       OLD cell's trailing fields visible through the new value; the
       per-index nth_opt failwith below only catches the OVER-index
       direction, and [ctor_entry]'s suffix-fallback can genuinely resolve
       to an entry of a different arity when two types share a ctor name
       and no arity-exact candidate exists.  Perceus_fbip's [same_arity]
       ($fbip$-encoded freed-cell arity = new arg count) makes the SIZES
       match; this check pins the remaining leg (arg count = resolved
       ctor's field count) at emission time. *)
    if List.length args <> List.length entry.ce_fields then
      failwith (Printf.sprintf
        "LLVM emit: EReuse of constructor %s supplies %d arg(s) but the \
         resolved ctor_info entry declares %d field(s) — an under-write \
         would leak the reused cell's stale fields (type-incorrect TIR or \
         a ctor_info suffix-fallback collision reached codegen)"
        ctor (List.length args) (List.length entry.ce_fields));
    (* Pre-compute all arg values before branching *)
    let arg_vals = List.mapi (fun i atom ->
      let field_ty = match List.nth_opt entry.ce_fields i with
        | Some t -> llvm_field_ty t
        | None ->
          failwith (Printf.sprintf
            "LLVM emit: constructor %s has %d field(s) but field index %d \
             was requested (arity mismatch — cascading from a ctor_info collision?)"
            ctor (List.length entry.ce_fields) i)
      in
      let (v_ty, v_val) = emit_atom ctx atom in
      let v_coerced = coerce ctx v_ty v_val field_ty in
      (field_ty, v_coerced)
    ) args in
    (* Load RC and check if uniquely owned.  Use atomic monotonic load so
       this is data-race-free even if borrow inference's "process-local" proof
       is later weakened — the cost of a relaxed atomic load is negligible
       relative to the march_decrc on the fresh-branch path. *)
    let rc = fresh ctx "rc" in
    emit ctx (Printf.sprintf "%s = load atomic i64, ptr %s monotonic, align 8" rc rv);
    let is_unique = fresh ctx "uniq" in
    emit ctx (Printf.sprintf "%s = icmp eq i64 %s, 1" is_unique rc);
    let reuse_lbl = fresh_block ctx "fbip_reuse" in
    let fresh_lbl = fresh_block ctx "fbip_fresh" in
    let merge_lbl = fresh_block ctx "fbip_merge" in
    emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
                     is_unique reuse_lbl fresh_lbl);
    (* Reuse branch: write tag/fields to original pointer.  Neither
       emit_store_tag nor emit_store_field nor emit_heap_alloc emit a label,
       so reuse_lbl / fresh_lbl ARE the immediate predecessors of merge_lbl
       — safe to use as phi source labels.  Audit L6: phi instead of
       alloca/store/load slot. *)
    emit_label ctx reuse_lbl;
    emit_store_tag ctx rv entry.ce_tag;
    List.iteri (fun i (field_ty, v_coerced) ->
      emit_store_field ctx rv i field_ty v_coerced
    ) arg_vals;
    emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl);
    (* Fresh branch: DecRC original, alloc fresh, write tag/fields *)
    emit_label ctx fresh_lbl;
    emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" rv);
    let hp = emit_heap_alloc ctx entry.ce_tag (List.length args) in
    List.iteri (fun i (field_ty, v_coerced) ->
      emit_store_field ctx hp i field_ty v_coerced
    ) arg_vals;
    emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl);
    (* Merge via phi *)
    emit_label ctx merge_lbl;
    let result = fresh ctx "fbip_r" in
    emit ctx (Printf.sprintf "%s = phi ptr [ %s, %%%s ], [ %s, %%%s ]"
                result rv reuse_lbl hp fresh_lbl);
    ("ptr", result)
    end)

(** Body of the non-constructor [EReuse] arm. *)
let emit_reuse_uniform ~emit_atom ctx (reuse_atom : Tir.atom)
  (reuse_ty : Tir.ty) (args : Tir.atom list) : string * string =
    (* Non-TCon reuse (e.g. reusing a dead cell as a join-point closure): same
       conditional logic without ctor-specific fields. *)
    let arg_vals_of () = List.map (fun atom ->
      let (ty, v) = emit_atom ctx atom in
      (* Records keep NATURAL slot repr (shape descriptors record the kind);
         tuples / erased cells use the UNIFORM convention (scalars tagged),
         matching ETuple and the ptr-typed destructure fallbacks. *)
      (match reuse_ty with
       | Tir.TRecord _ -> (ty, v)
       | _ -> ("ptr", coerce ctx ty v "ptr"))
    ) args in
    (* Guard (mirrors the TCon branch above): if reuse_atom's own type is
       niche-shaped (e.g. Option.Some over a pointer), the scrutinee IS its
       payload — no wrapper cell exists.  FBIP-reusing that memory for a
       different object (here a closure) overwrites the payload, so a later
       use of the payload (or its fields) reads corrupted/freed memory.
       This is exactly the `Some((a, b)) -> ... reuse Option as $Clo ...`
       pattern emitted for join points: reusing the Option cell would clobber
       the tuple it points to.  Skip FBIP and allocate fresh, without touching
       reuse_atom's RC (the payload stays live for its own consumers). *)
    let reuse_atom_parent_type = match reuse_atom with
      | Tir.AVar v ->
        (match v.Tir.v_ty with
         | Tir.TCon (name, _) ->
           (match String.rindex_opt name '.' with
            | Some i -> String.sub name 0 i
            | None -> name)
         | _ -> "")
      | _ -> ""
    in
    if reuse_atom_parent_type <> ""
       && Repr.is_niche_shaped ~collision_set:ctx.collision_set ctx.type_defs reuse_atom_parent_type
    then begin
      let arg_vals = arg_vals_of () in
      let hp = emit_heap_alloc ctx 0 (List.length args) in
      List.iteri (fun i (ty, v) -> emit_store_field ctx hp i ty v) arg_vals;
      (match reuse_ty with
       | Tir.TRecord fields -> emit_set_shape ctx hp fields
       | _ -> ());
      ("ptr", hp)
    end else begin
    let (_, rv) = emit_atom ctx reuse_atom in
    let arg_vals = arg_vals_of () in
    let rc = fresh ctx "rc" in
    emit ctx (Printf.sprintf "%s = load atomic i64, ptr %s monotonic, align 8" rc rv);
    let is_unique = fresh ctx "uniq" in
    emit ctx (Printf.sprintf "%s = icmp eq i64 %s, 1" is_unique rc);
    let reuse_lbl = fresh_block ctx "fbip_reuse" in
    let fresh_lbl = fresh_block ctx "fbip_fresh" in
    let merge_lbl = fresh_block ctx "fbip_merge" in
    emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
                     is_unique reuse_lbl fresh_lbl);
    emit_label ctx reuse_lbl;
    (* Write tag=0 to match the fresh-branch allocation (emit_heap_alloc below
       passes tag_int=0).  Without this, the reused cell would carry whatever
       tag was previously stored — semantically inconsistent with the
       same-shape value the fresh branch produces. *)
    emit_store_tag ctx rv 0;
    List.iteri (fun i (ty, v) ->
      emit_store_field ctx rv i ty v
    ) arg_vals;
    emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl);
    emit_label ctx fresh_lbl;
    emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" rv);
    let hp = emit_heap_alloc ctx 0 (List.length args) in
    List.iteri (fun i (ty, v) ->
      emit_store_field ctx hp i ty v
    ) arg_vals;
    emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl);
    emit_label ctx merge_lbl;
    let result = fresh ctx "fbip_r" in
    emit ctx (Printf.sprintf "%s = phi ptr [ %s, %%%s ], [ %s, %%%s ]"
                result rv reuse_lbl hp fresh_lbl);
    (* Records: stamp the shape id on the result (the fresh-branch cell has
       pad=0; the reuse-branch cell may have been a different record shape). *)
    (match reuse_ty with
     | Tir.TRecord fields -> emit_set_shape ctx result fields
     | _ -> ());
    ("ptr", result)
    end

  (* ── RC ops ────────────────────────────────────────────────────────── *)
  (* Skip RC ops on builtins AND on top-level function references.
     Function addresses live in the code segment, not the heap, so calling
     march_incrc_local/decrc_local/free on them would corrupt memory or crash.
     EIncRC/EDecRC use non-atomic local RC (fast path, single-owner values).
     EAtomicIncRC/EAtomicDecRC use C11-atomic RC for actor-shared values.
     A LOCAL binding of the same name (var_slot entry) shadows the builtin
     or top-level fn — mirrors emit_atom's two analogous guards (:1422-1424
     top-fns arm, :1499-1500 builtin arm, whose comment cites heap
     corruption).  Without this check a local heap value named e.g. `link`
     (also the actor-linking builtin) silently gets ZERO RC ops: it is
     never inc/dec'd or freed, leaking or (worse, if the same name is later
     reused for a different shape) corrupting memory the same way the
     emit_atom bug did. *)

