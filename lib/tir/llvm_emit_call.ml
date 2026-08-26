(** Call codegen: the bodies of [Llvm_emit.emit_expr]'s general [EApp] arm
    and of its [ECallPtr] arms.

    Phase 2b of specs/plans/2026-08-19-compiler-file-decomposition.md, the
    per-arm delegation Phase 2 deferred.  Every arm keeps its exact position,
    guard and order in [emit_expr]'s match -- match order there is
    load-bearing (non-builtin arms interleave with builtin ones, and the TCO
    arms sit below several builtin arms), so nothing is grouped or reordered.
    Only the arm BODIES live here, byte-identical to the text they replaced.
    [emit_atom] is threaded in as a labelled callback, the convention
    [Llvm_emit_simd] and [Llvm_emit_nmap] established.

    Two [ECallPtr] arms are NOT here: the record-introspection redirect and
    the known-builtin redirect are each a single [emit_expr ctx (EApp ...)]
    line, shorter than the call that would replace them, and they are the only
    two arms in this territory that recurse.

    [fn_ret_tir] and [release_temp_boxes] moved with the bodies.
    [release_temp_boxes] had no other caller; [fn_ret_tir] still has three in
    [Llvm_emit.emit_atom], which now reaches for it here. *)

open Llvm_ctx

let llvm_ty = Llvm_ctx.llvm_ty
let llvm_ret_ty = Llvm_ctx.llvm_ret_ty
let is_apply_fn = Tir_names.is_apply_fn
let builtin_ret_ty = Llvm_builtins.builtin_ret_ty
let mangle_extern = Llvm_builtins.mangle_extern
let emit_raises_wrapper = Llvm_calls.emit_raises_wrapper
let fail_if_unresolved_iface_method = Llvm_calls.fail_if_unresolved_iface_method
let decode_simd_call = Llvm_emit_simd.decode_simd_call

(** Drop the temporary boxes a call site created for its native-vector args.
    Emitted straight after the call instruction (and, for a Float return,
    after the result register is captured), so there is no control flow
    between the call and the release and every path that reached the call
    reaches the release. *)
let release_temp_boxes (ctx : Llvm_ctx.ctx) (boxes : string list ref) : unit =
  List.iter
    (fun b -> Llvm_ctx.emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" b))
    !boxes;
  boxes := []

(** Return type of a function variable's type. *)
let fn_ret_tir (ty : Tir.ty) : Tir.ty =
  match ty with
  | Tir.TFn (_, ret) -> ret
  | other -> other

let emit_load_field = Llvm_data.emit_load_field

(** Body of the general [EApp] arm: the direct-call path for everything no
    earlier arm intercepted. *)
let emit_generic_app ~emit_atom ctx (f : Tir.var) (args : Tir.atom list)
  : string * string =
    (* Emit each arg once, collecting both type and value strings. *)
    let arg_pairs = List.map (fun a -> emit_atom ctx a) args in
    let arg_strs  = List.map (fun (ty, v) -> ty ^ " " ^ v) arg_pairs in
    (* Resolve unqualified cross-module references: lower.ml may emit a
       function reference without its module prefix (e.g. "base64_encode"
       for "Crypto.base64_encode").  Look up the qualified name first.
       Guard: if the bare name is already a direct top-level function, use
       it as-is — a same-module function shadows any cross-module match. *)
    let resolved_name =
      if Hashtbl.mem ctx.top_fns f.Tir.v_name then f.Tir.v_name
      else match Hashtbl.find_opt ctx.unqualified_fns f.Tir.v_name with
        | Some q -> q
        | None -> f.Tir.v_name
    in
    (* Guard against the coerce-catch-all class of bug: every simd_<t>_<op>
       builtin, including `load`/`store` (real lowerings now, not a
       deferred failwith — see the intercept arm's header comment above),
       must be caught by the [decode_simd_call] guard on the dedicated SIMD
       arm above and never reach this generic call path — reaching here for
       one means that arm's pattern/guard let it slip through, which would
       otherwise silently degrade to an unresolved
       `call ptr @simd_..._add(...)` auto-declared extern (or worse, corrupt
       via the ("ptr", scalar) coerce catch-all). Cheap insurance, unreachable
       by construction. *)
    if decode_simd_call resolved_name <> None then
      failwith ("simd builtin reached generic call path: " ^ resolved_name);
    (* ── Call-scoped SIMD vector temp boxes ────────────────────────────
       A vector argument whose ACTUAL emitted type is native (`<N x T>` — an
       ELet vector slot or a SIMD builtin result) is boxed here, by [coerce]'s
       (vec, "ptr") arm, into a fresh `march_simd_alloc` cell with rc=1.  That
       box is CALL-SCOPED: it never enters a TIR variable — it exists only
       between this argument coerce and the call — so Perceus accounting never
       sees it and no other party holds a reference to it.

       INVARIANT that makes releasing it after the call sound: the callee must
       provably not RETAIN the pointer.  That is true for, and ONLY for, a
       callee whose parameter got a native vector TCO slot
       ([Llvm_toplevel.emit_fn]'s `native_vec_slot` arm, tabulated in
       [ctx.native_vec_params] by a pre-pass): its entry prologue does one
       GEP + load of the payload and drops the pointer on the floor.  Releasing
       the box after the call therefore closes the per-call leak recorded in
       specs/progress/2026-08-11-simd-tco-entry-box-leak.md.

       It is NOT true in general.  A callee whose vector parameter stays `ptr`
       (any non-TCO fn, an apply fn, a mutual-TCO group member) is free to
       store that exact pointer into a heap aggregate which then owns it —
       `fn wrap(v) = [v]` compiles to `store ptr %v.arg, ptr %cons.field`.
       Releasing there frees a live list element: measured segfault, guarded by
       test/native/simd_vector_escape_arg.march.  Hence the table lookup rather
       than "release every box I created".

       Arguments that were ALREADY `ptr` before the coerce (a vector at rest in
       a variable/field) are never recorded: no box was created, [coerce] was
       the identity, and the box belongs to whoever owns the at-rest value.

       Scope note: this closes the leak for native-slot callees only.  Non-TCO
       vector params still leak one box per call on BOTH sides (neither caller
       nor callee releases) — that needs Perceus-level accounting, tracked in
       specs/todos/2026-08-12-simd-nontco-vector-param-leak.md. *)
    let native_vec_idxs =
      (* ARITY GUARD, not a formality: the indices are positional, so they only
         mean anything if this call site passes exactly the callee's declared
         parameter list.  The top_fn_param_tys coercion branch below already
         refuses to coerce on a length mismatch; the apply-fn (Boundary B)
         branch indexes positionally with no such check, so the guard lives
         here, where BOTH branches inherit it.  On any mismatch we record
         nothing and simply keep leaking — the safe direction. *)
      match Hashtbl.find_opt ctx.native_vec_params resolved_name with
      | Some idxs
        when Hashtbl.find_opt ctx.top_fn_nparams resolved_name
             = Some (List.length arg_pairs) -> idxs
      | Some _ | None -> []
    in
    let temp_boxes : string list ref = ref [] in
    let record_temp_box i ~from_ty ~to_ty boxed =
      if is_vec_ty from_ty && to_ty = "ptr" && List.mem i native_vec_idxs then
        temp_boxes := boxed :: !temp_boxes
    in
    (* Boundary B: a direct call to an apply fn (known_call rewrote a
       non-escaping ECallPtr into EApp(apply_fn, ...)) must pass every scalar
       arg through the uniform ptr closure ABI — tag Int/Bool via (n<<1)|1,
       box Float via march_alloc_float, box a SIMD vector via march_simd_alloc
       — because the apply fn's params are now `ptr` (Task 4).  Ordinary
       top-level direct calls keep their concrete ABI, so guard the remap on
       is_apply_fn.

       The vector case (Task 4b) is the SAME defect the Float case documents,
       one representation later.  A locally-defined recursive `fn` threading a
       SIMD accumulator is reached by TWO call sites that must agree: this
       direct kickoff call (known_call rewrote the first, non-escaping
       ECallPtr into EApp(go$apply$N, ...)) and the closure's own indirect
       self-call through the fn-pointer field.  The indirect path derives its
       argument types from the callee's DECLARED params (all `ptr`) and so
       boxes correctly; this direct path derives them from each argument's
       ACTUAL emitted type, which for a vector-typed accumulator is the native
       `<4 x float>` register value (the register-residency form).  Without
       the remap the call read
         call ptr @go$apply$N(ptr %clo, ptr %i, <4 x float> %acc)
       against a definition taking `ptr %acc.arg`, so the callee dereferenced
       a register vector as a box pointer: SEGFAULT at every --opt level
       (specs/progress/2026-08-11-simd-nested-closure-vector-accumulator-
       segfault.md).  The uniform ptr ABI is not optional here — the same
       compiled body serves both call sites — so vectors box at this boundary
       exactly like Floats do.  Keeping a vector NATIVE across a call would
       require a whole cross-call vector ABI; the fast path for the shape that
       actually matters (a self-tail-recursive accumulator) is instead the
       native TCO slot in [Llvm_toplevel.emit_fn], which never crosses a real
       call at all. *)
    (* Float boxes created at THIS call site for a direct apply-fn call
       (Boundary B) are released right after the call — the Float sibling of
       the SIMD [record_temp_box] machinery above, with the same soundness
       key: the release happens only when the CALLEE DEFINITION's declared
       parameter is genuinely `double`, in which case its entry prologue
       (Llvm_toplevel.emit_fn's is_apply_wrapper arm) unboxes the incoming
       pointer once and never reads it again — the box has no owner but this
       call site.  A param that stayed generic (`ptr` — an erased/polymorphic
       apply fn) may RETAIN the argument, so its index is never listed and
       that box still leaks (the safe direction); same arity guard as
       [native_vec_idxs], since the indices are positional.  Measured before
       this release: one leaked march_float_box per Float param per call,
       unbounded (test/native/native_float_box_abi_leak_probe.march). *)
    let apply_float_param_idxs =
      if is_apply_fn resolved_name
         (* Direct devirtualized SELF-call (known_call rewrote the recursive
            back-edge): post-call instructions would defeat LLVM's tail-call
            elimination and stack-overflow deep recursion — same exemption,
            same rationale, as the ECallPtr arm's is_potential_self_call. *)
         && resolved_name <> ctx.cur_emit_fn
         && Hashtbl.find_opt ctx.top_fn_nparams resolved_name
            = Some (List.length arg_pairs)
      then
        match Hashtbl.find_opt ctx.top_fn_param_tys resolved_name with
        | Some param_tirs ->
          List.mapi (fun i t -> (i, llvm_ty t = "double")) param_tirs
          |> List.filter (fun (_, is_dbl) -> is_dbl)
          |> List.map fst
        | None -> []
      else []
    in
    let float_temp_boxes : string list ref = ref [] in
    let release_float_temp_boxes () =
      List.iter
        (fun b ->
           emit ctx (Printf.sprintf "call void @march_decrc_local(ptr %s)" b))
        !float_temp_boxes;
      float_temp_boxes := []
    in
    let arg_strs =
      if is_apply_fn resolved_name then
        List.mapi (fun i (ty, v) ->
          if ty = "i64" || ty = "double" || is_vec_ty ty then
            let v' = coerce ctx ty v "ptr" in
            record_temp_box i ~from_ty:ty ~to_ty:"ptr" v';
            if ty = "double" && List.mem i apply_float_param_idxs then
              float_temp_boxes := v' :: !float_temp_boxes;
            "ptr " ^ v'
          else ty ^ " " ^ v) arg_pairs
      else
        (* Coerce each argument's ACTUAL emitted representation to the
           callee's declared parameter type when known and arity matches.
           A value whose static var type is a generic/polymorphic ADT field
           (always "ptr" — boxed for scalars — under the uniform-slot
           convention; see Llvm_case's ce_fields-driven field extraction)
           flowing directly into a monomorphic callee's native scalar
           parameter (e.g. Float → "double") otherwise passes through
           un-coerced, producing an LLVM call with mismatched argument
           types that reads garbage at the callee (the
           Array.from_list$..$Float compiled-wrong-value bug: pushing a
           list element extracted from a generic Cons field into a
           concrete Array.push$..$Float always read 0.0 for the element). *)
        match Hashtbl.find_opt ctx.top_fn_param_tys resolved_name with
        | Some param_tirs when List.length param_tirs = List.length arg_pairs ->
          List.mapi (fun i (param_tir, (ty, v)) ->
            let param_ty = llvm_ty param_tir in
            let v' = coerce ctx ty v param_ty in
            record_temp_box i ~from_ty:ty ~to_ty:param_ty v';
            param_ty ^ " " ^ v'
          ) (List.combine param_tirs arg_pairs)
        | _ ->
          (* Compiler builtins (int_to_string, math_sqrt, ...) are never
             registered in top_fn_param_tys — that table only covers
             user-defined fns/externs.  Without this, a builtin whose C
             signature takes a native scalar (i64/double) called with an
             argument bound via the uniform ptr-slot convention (e.g. a
             tuple or ADT field, always "ptr", tagged/boxed) passes through
             un-coerced: the raw tagged bits (e.g. (3<<1)|1 = 7) land in the
             native param verbatim instead of being untagged, so
             `Some((top, _)) -> int_to_string(top)` printed "7" instead of
             "3" compiled-only (interpreter unaffected — no such repr
             split there). Reuse the builtin's own declare_sig (single
             source of truth, already used for the preamble) rather than a
             second hand-maintained param-type table that could drift.

             Only the "ptr" (generic/erased slot) -> "i64"/"double" (native
             scalar) direction is coerced — the one the bug above needs.
             The REVERSE direction ("i64"/"double" arg -> a declared "ptr"
             param) must NOT go through [coerce]: several builtins
             (csv_next_row/csv_close, file_close, ...) declare a "ptr" C
             parameter for an opaque native handle whose March-level type
             is plain Int, purely as a typechecking convention — the value
             already IS a raw pointer, not a generic scalar needing the
             boxed-slot tag.  [coerce]'s ("i64","ptr") case unconditionally
             applies (v<<1)|1 (the boxing convention for a genuine Int
             entering a generic slot), which corrupts such handles: passed
             to their own runtime accessor, the tagged/shifted bit pattern
             no longer resolves to the handle's real heap address (found
             via bisection to this commit — Csv.read_all read every row's
             fields off a bogus tagged "handle", nondeterministically
             misreading it as EOF or as a wild pointer, exit 138/139).
             LLVM's opaque-pointer calls don't require the call-site's
             argument types to match the callee's declared prototype
             (i64 and ptr share the same register/ABI class), so leaving
             the value's own type/representation untouched here reproduces
             the pre-regression, correct behavior exactly. *)
          (match Llvm_builtins.builtin_param_llvm_tys resolved_name with
           | Some param_llvm_tys when List.length param_llvm_tys = List.length arg_pairs ->
             List.mapi (fun i (param_ty, (ty, v)) ->
               if ty = "ptr" && (param_ty = "i64" || param_ty = "double") then
                 let v' = coerce ctx ty v param_ty in
                 param_ty ^ " " ^ v'
               (* Reverse direction — a raw scalar (i64/double) flowing into a
                  declared "ptr" param — is skipped in general (opaque handles),
                  but ENABLED for slots whose March type is a generic TVar: the
                  erased uniform slot needs the BOXED scalar (Int tagged, Float
                  boxed), else an inlined raw literal is stored at the wrong
                  representation. See builtin_boxed_generic_params_tbl. *)
               else if param_ty = "ptr" && (ty = "i64" || ty = "double")
                       && Llvm_builtins.builtin_param_is_boxed_generic resolved_name i then
                 let v' = coerce ctx ty v "ptr" in
                 "ptr " ^ v'
               else ty ^ " " ^ v
             ) (List.combine param_llvm_tys arg_pairs)
           | _ -> arg_strs)
    in
    let args_str = String.concat ", " arg_strs in
    let fname    = match Hashtbl.find_opt ctx.extern_map resolved_name with
      | Some c_name -> c_name
      | None -> mangle_extern resolved_name in
    (* Determine return type: check known builtins first, then the registered
       fn_def return type (if any), then fall back to the call-site TFn annotation.
       The call-site type may be TVar "_" in JIT mode (empty type_map), so
       top_fn_ret_ty gives the concrete type from the function's definition. *)
    let ret_tir  = match builtin_ret_ty f.Tir.v_name with
      | Some t -> t
      | None   ->
        (match Hashtbl.find_opt ctx.top_fn_ret_ty resolved_name with
         (* The function IS registered but with an unresolved TVar return, so
            its definition emits `ret ptr` (the generic representation).  The
            call site MUST therefore read the result as ptr and let the
            consumer coerce/untag to its concrete type — using the call-site
            scalar type here would emit `call i64` against a `ret ptr` body,
            reinterpreting a tagged generic value as a raw scalar (e.g. a
            dynamic record-field read returning `(n<<1)|1` read back as `3`).
            Mirrors the zero-arg AVar path. *)
         | Some (Tir.TVar _) -> Tir.TVar "_"
         (* Unregistered (extern/interface dispatch): the call-site annotation
            is the only type info; the forward declaration uses it too. *)
         | None -> fn_ret_tir f.Tir.v_ty
         | Some t -> t)
    in
    (* Apply wrappers use the generic ptr ABI (see [is_apply_fn]); known_call
       rewrites ECallPtr→EApp(apply_fn, ...) for non-escaping closures, so this
       direct path must read the result as ptr too. *)
    let ret_ty =
      if is_apply_fn resolved_name then "ptr" else llvm_ret_ty ret_tir in
    (* If the function is not known (not in top_fns, not a builtin, not an extern),
       emit a forward declaration into the preamble so LLVM does not reject the IR
       with "use of undefined value".  This covers interface dispatch calls that were
       not resolved at compile time due to type erasure (e.g. Conduit.Storage.X when
       the storage value has type TVar "_").
       NOTE: skip if fname starts with "march_" — those are always pre-declared
       in the hardcoded preamble string (emit_preamble). *)
    let is_runtime_builtin = Tir_names.has_runtime_prefix fname in
    let is_known_fn =
      is_runtime_builtin
      || Hashtbl.mem ctx.top_fns resolved_name
      || Hashtbl.mem ctx.extern_map resolved_name
      || builtin_ret_ty f.Tir.v_name <> None
      || (match f.Tir.v_name with
          | "panic" | "panic_" | "todo_" | "unreachable_" | "println"
          | "print" | "print_stderr" | "io_read_line" | "read_line"
          | "io_read_byte" | "read_byte" -> true
          | _ -> false)
    in
    (* Unresolved bare interface-method guard — see
       [fail_if_unresolved_iface_method]; the ECallPtr no-var-slot catch-all
       applies the identical guard. *)
    if not is_known_fn then
      fail_if_unresolved_iface_method ctx f.Tir.v_name;
    if not is_known_fn && not (Hashtbl.mem ctx.unknown_decls fname) then begin
      Hashtbl.replace ctx.unknown_decls fname ();
      let param_strs = List.mapi (fun i (ty, _) ->
          Printf.sprintf "%s %%arg%d" ty i) arg_pairs in
      Buffer.add_string ctx.preamble
        (Printf.sprintf "declare %s @%s(%s)\n" ret_ty fname (String.concat ", " param_strs))
    end;
    if Hashtbl.mem ctx.raises_externs resolved_name then
      emit_raises_wrapper ctx ~fname ~ret_tir ~arg_pairs
    else if Hashtbl.mem ctx.blocking_externs resolved_name then
      Llvm_calls.emit_blocking_call ctx ~fname ~ret_ty ~arg_pairs ~resolved_name
    else if (match ctx.hr_config with
             | None -> false
             | Some cfg ->
               (* Boundary→boundary call: route through the versioned dispatch
                  table so the callee can be hot-swapped at runtime. *)
               Hashtbl.mem ctx.top_fns resolved_name
               && Hot_reload.needs_dispatch cfg ~caller_module:ctx.hr_cur_module
                    ~callee_module:(module_of_name resolved_name)
               && Hot_reload.Name_table.id_of ctx.hr_names resolved_name <> None)
    then begin
      let name_id =
        match Hot_reload.Name_table.id_of ctx.hr_names resolved_name with
        | Some i -> i + 1 | None -> 0 in  (* 1-based; 0 = sentinel *)
      let vslot = fresh ctx "hrver" in
      emit ctx (Printf.sprintf "%s = alloca i32" vslot);
      let fp = fresh ctx "hrfp" in
      if ctx.compile_so then begin
        (* Phase 9: in a .so patch, read the per-.so epoch cell and use the
           epoch-aware enter so old callers route to the version they were
           deployed with rather than always the newest slot. *)
        let epoch = fresh ctx "hrepoch" in
        emit ctx (Printf.sprintf "%s = load i32, ptr @__march_hcr_epoch" epoch);
        emit ctx (Printf.sprintf
          "%s = call ptr @march_dispatch_enter_gen(i32 %d, i32 %s, ptr %s)"
          fp name_id epoch vslot)
      end else
        emit ctx (Printf.sprintf
          "%s = call ptr @march_dispatch_enter(i32 %d, ptr %s)" fp name_id vslot);
      (* Startup-warmup guard.  march_dispatch_enter returns NULL when the target
         slot has not been published yet (or the publish is not yet visible to
         this thread) — e.g. an HTTP worker thread serving a request during the
         first few seconds while the dispatch table is still being filled in.
         In that window fall back to a DIRECT static call to the baseline symbol
         (the exact fn we would have published), rather than jumping through a
         NULL fn_ptr.  No leave is issued on this path: enter did not pin a
         version when it returned NULL. *)
      let is_null = fresh ctx "hrnull" in
      emit ctx (Printf.sprintf "%s = icmp eq ptr %s, null" is_null fp);
      let blk_direct = fresh_block ctx "hr_direct" in
      let blk_disp   = fresh_block ctx "hr_disp" in
      let blk_cont   = fresh_block ctx "hr_cont" in
      emit ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
                  is_null blk_direct blk_disp);
      (* Direct (baseline) path — table not ready. *)
      emit_label ctx blk_direct;
      let direct_r =
        if ret_ty = "void" then begin
          emit ctx (Printf.sprintf "call void @%s(%s)" fname args_str);
          None
        end else begin
          let r = fresh ctx "crd" in
          emit ctx (Printf.sprintf "%s = call %s @%s(%s)"
                      r ret_ty fname args_str);
          Some r
        end
      in
      emit ctx (Printf.sprintf "br label %%%s" blk_cont);
      (* Dispatched path — pinned to a published version; must leave after. *)
      emit_label ctx blk_disp;
      let disp_r =
        if ret_ty = "void" then begin
          emit ctx (Printf.sprintf "call void %s(%s)" fp args_str);
          None
        end else begin
          let r = fresh ctx "cr" in
          emit ctx (Printf.sprintf "%s = call %s %s(%s)" r ret_ty fp args_str);
          Some r
        end
      in
      let v = fresh ctx "hrv" in
      emit ctx (Printf.sprintf "%s = load i32, ptr %s" v vslot);
      emit ctx (Printf.sprintf
        "call void @march_dispatch_leave(i32 %d, i32 %s)" name_id v);
      emit ctx (Printf.sprintf "br label %%%s" blk_cont);
      (* Continuation — merge the two call results. *)
      emit_label ctx blk_cont;
      let result =
        match direct_r, disp_r with
        | Some rd, Some rs ->
          let phi = fresh ctx "hrphi" in
          emit ctx (Printf.sprintf "%s = phi %s [ %s, %%%s ], [ %s, %%%s ]"
                      phi ret_ty rd blk_direct rs blk_disp);
          (ret_ty, phi)
        | _ -> ("i64", "0")
      in
      result
    end
    else if ret_ty = "void" then begin
      emit ctx (Printf.sprintf "call void @%s(%s)" fname args_str);
      release_temp_boxes ctx temp_boxes;
      release_float_temp_boxes ();
      ("i64", "0")
    end else begin
      let r = fresh ctx "cr" in
      emit ctx (Printf.sprintf "%s = call %s @%s(%s)" r ret_ty fname args_str);
      release_temp_boxes ctx temp_boxes;
      release_float_temp_boxes ();
      (* A Float-returning apply fn ALWAYS hands back a freshly-allocated
         march_float_box: its `double` result has no other route into the
         erased ptr slot than the return-path coerce / clo_wrap's
         double-return arm, and that box goes straight to `ret` without being
         stored anywhere.  This call site is therefore its sole owner: unbox
         here and release the box, yielding the raw double (a consumer that
         needs the erased form re-boxes fresh via coerce — Float is
         immutable, so the copy is unobservable).  Before this release the
         box leaked, one per call, unbounded — the return half of
         test/native/native_float_box_abi_leak_probe.march.  The hot-reload
         dispatch branch above deliberately skips this (and the temp-box
         releases): dispatched apply-fn calls keep the old leak rather than
         risk releasing across a version boundary — the safe direction. *)
      if is_apply_fn resolved_name && llvm_ret_ty ret_tir = "double"
         && resolved_name <> ctx.cur_emit_fn (* self-tail-call exemption *)
      then begin
        let d = fresh ctx "crf" in
        emit ctx (Printf.sprintf "%s = call double @march_unbox_float(ptr %s)" d r);
        emit ctx (Printf.sprintf "call void @march_decrc_local(ptr %s)" r);
        ("double", d)
      end else
        (ret_ty, r)
    end

(** Body of the [ECallPtr]-to-a-`raises`-extern arm. *)
let emit_callptr_raises ~emit_atom ctx (f : Tir.var) (args : Tir.atom list)
  : string * string =
    let arg_pairs = List.map (fun a -> emit_atom ctx a) args in
    let rn =
      if Hashtbl.mem ctx.top_fns f.Tir.v_name then f.Tir.v_name
      else match Hashtbl.find_opt ctx.unqualified_fns f.Tir.v_name with
        | Some q -> q | None -> f.Tir.v_name in
    let fname = match Hashtbl.find_opt ctx.extern_map rn with
      | Some c_name -> c_name | None -> mangle_extern rn in
    let ret_tir = match Hashtbl.find_opt ctx.top_fn_ret_ty rn with
      | Some t -> t | None -> fn_ret_tir f.Tir.v_ty in
    emit_raises_wrapper ctx ~fname ~ret_tir ~arg_pairs

(** Body of the [ECallPtr]-to-a-`blocking`-extern arm. *)
let emit_callptr_blocking ~emit_atom ctx (f : Tir.var) (args : Tir.atom list)
  : string * string =
    let arg_pairs = List.map (fun a -> emit_atom ctx a) args in
    let rn =
      if Hashtbl.mem ctx.top_fns f.Tir.v_name then f.Tir.v_name
      else match Hashtbl.find_opt ctx.unqualified_fns f.Tir.v_name with
        | Some q -> q | None -> f.Tir.v_name in
    let fname = match Hashtbl.find_opt ctx.extern_map rn with
      | Some c_name -> c_name | None -> mangle_extern rn in
    let ret_tir = match Hashtbl.find_opt ctx.top_fn_ret_ty rn with
      | Some t -> t | None -> fn_ret_tir f.Tir.v_ty in
    let ret_ty = llvm_ret_ty ret_tir in
    Llvm_calls.emit_blocking_call ctx ~fname ~ret_ty ~arg_pairs
      ~resolved_name:rn

(** Body of the [ECallPtr]-to-an-unqualified-cross-module-function arm. *)
let emit_callptr_unqualified ~emit_atom ctx (f : Tir.var)
  (args : Tir.atom list) : string * string =
    let qualified = Hashtbl.find ctx.unqualified_fns f.Tir.v_name in
    let arg_strs = List.map (fun a ->
        let (ty, v) = emit_atom ctx a in ty ^ " " ^ v
      ) args in
    let args_str = String.concat ", " arg_strs in
    let fname = match Hashtbl.find_opt ctx.extern_map qualified with
      | Some c_name -> c_name
      | None -> mangle_extern qualified in
    let ret_tir = match Hashtbl.find_opt ctx.top_fn_ret_ty qualified with
      (* TVar-registered fn emits `ret ptr`; call as ptr, consumer coerces. *)
      | Some (Tir.TVar _) -> Tir.TVar "_"
      | None -> fn_ret_tir f.Tir.v_ty
      | Some t -> t
    in
    let ret_ty = llvm_ret_ty ret_tir in
    if ret_ty = "void" then begin
      emit ctx (Printf.sprintf "call void @%s(%s)" fname args_str);
      ("i64", "0")
    end else begin
      let r = fresh ctx "cr" in
      emit ctx (Printf.sprintf "%s = call %s @%s(%s)" r ret_ty fname args_str);
      (ret_ty, r)
    end

(** Body of the [ECallPtr]-with-no-local-alloca-slot arm: a direct call to
    the global function. *)
let emit_callptr_global ~emit_atom ctx (f : Tir.var) (args : Tir.atom list)
  : string * string =
    let arg_pairs = List.map (fun a -> emit_atom ctx a) args in
    let arg_strs  = List.map (fun (ty, v) -> ty ^ " " ^ v) arg_pairs in
    let args_str  = String.concat ", " arg_strs in
    let resolved_name = match Hashtbl.find_opt ctx.unqualified_fns f.Tir.v_name with
      | Some q -> q
      | None -> f.Tir.v_name
    in
    let fname = match Hashtbl.find_opt ctx.extern_map resolved_name with
      | Some c_name -> c_name
      | None -> mangle_extern resolved_name in
    let ret_tir =
      match builtin_ret_ty f.Tir.v_name with
      | Some t -> t
      | None ->
        (match Hashtbl.find_opt ctx.top_fn_ret_ty resolved_name with
         (* TVar-registered fn emits `ret ptr`; call as ptr, consumer coerces. *)
         | Some (Tir.TVar _) -> Tir.TVar "_"
         | None -> fn_ret_tir f.Tir.v_ty
         | Some t -> t)
    in
    let ret_ty = llvm_ret_ty ret_tir in
    (* Emit a forward declare if the function is not known (not in top_fns,
       not a builtin, not an extern).  This covers interface-dispatch calls
       where the storage value has a type-erased type (TVar "_") and march
       did not monomorphize the call — e.g. @Conduit.Storage.checkpoint_load_all
       appears as a call but has no define/declare in the generated IR.
       NOTE: skip if fname starts with "march_" — those are always pre-declared
       in the hardcoded preamble string (emit_preamble). *)
    let is_runtime_builtin = Tir_names.has_runtime_prefix fname in
    let is_known_fn =
      is_runtime_builtin
      || Hashtbl.mem ctx.top_fns resolved_name
      || Hashtbl.mem ctx.extern_map resolved_name
      || builtin_ret_ty f.Tir.v_name <> None
      || (match f.Tir.v_name with
          | "panic" | "panic_" | "todo_" | "unreachable_" | "println"
          | "print" | "print_stderr" | "io_read_line" | "read_line"
          | "io_read_byte" | "read_byte" -> true
          | _ -> false)
    in
    (* Unresolved bare interface-method guard — see
       [fail_if_unresolved_iface_method]; the EApp general-call path applies
       the identical guard. *)
    if not is_known_fn then
      fail_if_unresolved_iface_method ctx f.Tir.v_name;
    if not is_known_fn && not (Hashtbl.mem ctx.unknown_decls fname) then begin
      Hashtbl.replace ctx.unknown_decls fname ();
      let param_strs = List.mapi (fun i (ty, _) ->
          Printf.sprintf "%s %%arg%d" ty i) arg_pairs in
      Buffer.add_string ctx.preamble
        (Printf.sprintf "declare %s @%s(%s)\n" ret_ty fname (String.concat ", " param_strs))
    end;
    if ret_ty = "void" then begin
      emit ctx (Printf.sprintf "call void @%s(%s)" fname args_str);
      ("i64", "0")
    end else begin
      let r = fresh ctx "cr" in
      emit ctx (Printf.sprintf "%s = call %s @%s(%s)" r ret_ty fname args_str);
      (ret_ty, r)
    end

(** Body of the generic [ECallPtr] arm: an indirect call dispatched through
    a closure struct. *)
let emit_callptr_closure ~emit_atom ctx (fn_atom : Tir.atom)
  (args : Tir.atom list) : string * string =
    (* The callee may surface as i64 when its TIR type is an unconstrained
       TVar (e.g. a closure captured through an erased env slot or passed to
       an erased i64 param).  Under the conditional-untag convention
       (coerce ptr→i64 ashr's ONLY odd/tagged values), a heap pointer
       flowing through a scalar-typed view is preserved verbatim — the i64
       holds the full even pointer.  Restore it with a bare inttoptr.
       NEVER use coerce i64→ptr here: its (n<<1)|1 immediate tagging would
       corrupt the pointer and the fn-ptr load below would jump to garbage. *)
    let (clo_ty, clo_val) = emit_atom ctx fn_atom in
    let clo_ptr =
      if clo_ty = "ptr" then clo_val
      else begin
        let v64 = if clo_ty = "i64" then clo_val
                  else coerce ctx clo_ty clo_val "i64" in
        let r = fresh ctx "cv" in
        emit ctx (Printf.sprintf "%s = inttoptr i64 %s to ptr" r v64);
        r
      end
    in
    let fn_ptr = emit_load_field ctx clo_ptr 0 "ptr" in
    let nargs = List.length args in
    let ret_tir = match fn_atom with
      | Tir.AVar v ->
        (match v.Tir.v_ty with
         | Tir.TFn (ps, ret) when List.length ps = nargs -> ret
         | Tir.TFn _ as ty ->
           (* Uncurry the TFn chain: TFn([a], TFn([b], R)) with 2 args → R.
              Defun flattens curried apply functions but keeps the original
              curried type on the variable, so nargs > List.length ps.
              Walk the chain consuming one param per arg until we've matched
              all args or run out of TFn wrappers. *)
           let rec uncurry_ret n t =
             if n = 0 then t
             else match t with
               | Tir.TFn ([_], ret) -> uncurry_ret (n - 1) ret
               | Tir.TFn (ps, ret) when n >= List.length ps ->
                 uncurry_ret (n - List.length ps) ret
               | _ -> Tir.TVar "_"
           in
           (match ty with
            | Tir.TFn (ps, ret) -> uncurry_ret (nargs - List.length ps) ret
            | _ -> Tir.TVar "_")
         | other -> other)
      | _ -> Tir.TVar "_"
    in
    (* Self-recursive closure calls surface as TFn(known_params) -> '_: the
       return type was left as an unresolved tyvar during recursive inference
       in lowering, even though the lifted apply fn has a concrete return type
       (e.g. a local [fn go(mi, acc) -> Int] whose body self-calls [go]).  With
       an erased return we'd emit `call ptr` and read the apply fn's raw scalar
       i64 return as a tagged pointer; the enclosing case-merge / return
       coercion then conditional-untags it (ashr on odd values), corrupting odd
       Int results.  A self-recursive call returns the enclosing function's own
       return type, so fall back to ctx.ret_ty when it is concrete.  Guarded to
       the TFn-with-known-params shape so fully-erased closure values (genuine
       TVar callees that may return heap pointers) keep the ptr ABI. *)
    let callee_is_tfn = match fn_atom with
      | Tir.AVar v -> (match v.Tir.v_ty with Tir.TFn _ -> true | _ -> false)
      | _ -> false
    in
    let ret_tir =
      match ret_tir with
      | Tir.TVar _ when callee_is_tfn ->
        (match ctx.ret_ty with Tir.TVar _ -> ret_tir | concrete -> concrete)
      | _ -> ret_tir
    in
    (* This is the indirect closure-struct dispatch: the fn-pointer always
       targets a closure apply wrapper, which uses the generic ptr ABI (see
       [is_apply_fn]).  Read the result as ptr regardless of the call-site Fn
       annotation (which may say a concrete scalar like Bool) and let the
       consumer untag via coerce.  void wrappers keep void. *)
    let ret_ty =
      let base = llvm_ret_ty ret_tir in
      if base = "void" then "void" else "ptr"
    in
    let orig_param_llvm_tys = match fn_atom with
      | Tir.AVar v ->
        (match v.Tir.v_ty with
         | Tir.TFn (ps, _) when List.length ps = nargs -> List.map llvm_ty ps
         | Tir.TFn _ as ty ->
           (* Uncurry the param type chain for curried calls, collecting
              all parameter types across nested TFn wrappers. *)
           let rec collect_params n t acc =
             if n = 0 then List.rev acc
             else match t with
               | Tir.TFn (ps, ret) ->
                 let take = min n (List.length ps) in
                 let taken = List.filteri (fun i _ -> i < take) ps in
                 collect_params (n - take) ret (List.rev_append (List.map llvm_ty taken) acc)
               | _ -> List.rev acc @ List.init n (fun _ -> "ptr")
           in
           collect_params nargs ty []
         | _ -> List.map (fun _ -> "ptr") args)
      | _ -> List.map (fun _ -> "ptr") args
    in
    (* Closure dispatch uses a uniform ptr ABI (the apply wrapper always takes
       ptr params — see is_apply_fn / clo_wrap).  A `double` param type would
       compile the arg into an FP register while the wrapper reads a GP register
       (integer scalars coincide across the two classes, floats do NOT) — so a
       Float closure argument must cross as a BOXED ptr (float-boxing, Stage 2),
       matching coerce's ("double","ptr") arm.  clo_wrap unboxes on the far side
       for named-fn targets; lambda apply bodies unbox lazily via coerce. *)
    let declared_param_llvm_tys = orig_param_llvm_tys in
    let orig_param_llvm_tys =
      List.map (fun t -> if t = "double" || t = "i64" then "ptr" else t) orig_param_llvm_tys in
    let fn_ty_str = Printf.sprintf "%s (%s)" ret_ty
        (String.concat ", " ("ptr" :: orig_param_llvm_tys)) in
    (* Float ARGUMENT boxes created by this call site's own coerce (declared
       param `double`, argument actually emitted as `double` — so the
       ("double","ptr") arm just allocated a march_float_box) are released
       right after the call.  Sole-ownership argument: a callee whose param
       is genuinely `double` unboxes the pointer in its entry prologue and
       never reads it again; a callee whose param slot stayed generic `ptr`
       treats it as an opaque value and, under the borrowed-param discipline,
       either leaves it alone or IncRCs it before storing it — either way the
       call site's reference is still the box's own.  The one legal way the
       box can come back to us is as the call's RESULT (a borrowed
       flow-through alias, `fn x -> x` at an erased param — the shape that
       made a plain call-site release a measured use-after-free on
       2026-08-20, see specs/progress on this fix), hence the pointer-
       equality guard against the raw returned value below: an aliased box is
       skipped here and released once by the return-path release instead.
       An argument that was ALREADY `ptr` at rest is never recorded — no box
       was created, and the at-rest box belongs to whoever owns the value.
       Measured before: one leaked box per Float arg per indirect call,
       unbounded (test/native/native_float_box_abi_leak_probe.march). *)
    (* SELF-TAIL-CALL EXEMPTION.  Inside an apply fn, a call through the
       recursive self-binding (defun's [let go = $clo]; the callee variable's
       name is exactly the lambda's source name) is the loop back-edge of a
       local recursive fn.  Emitting ANY instruction between that call and
       the merge/return — even the releases below — defeats LLVM's tail-call
       elimination, and the recursion becomes O(n) real stack frames: a
       measured green-thread stack overflow (SIGBUS) at 20,000 iterations on
       a shape that ran 1,000,000 deep before.  So for a (potential)
       self-call, skip every post-call release and hand the raw ptr result
       through unchanged, exactly as before this fix — those per-iteration
       boxes still leak (the pre-existing behavior; a false positive from
       name shadowing also only leaks).  The real fix for that edge is
       march-level TCO for self-recursive apply fns (native double slots, no
       boxes at all) — tracked in specs/todos. *)
    let is_potential_self_call =
      match fn_atom with
      | Tir.AVar v ->
        (match Tir_names.apply_fn_base ctx.cur_emit_fn with
         | Some base -> base = v.Tir.v_name
         | None -> false)
      | _ -> false
    in
    let float_arg_boxes : string list ref = ref [] in
    let orig_arg_strs = List.map2 (fun (decl_ty, pty) a ->
        let (actual_ty, v) = emit_atom ctx a in
        let v' = coerce ctx actual_ty v pty in
        if decl_ty = "double" && actual_ty = "double"
           && not is_potential_self_call then
          float_arg_boxes := v' :: !float_arg_boxes;
        pty ^ " " ^ v'
      ) (List.combine declared_param_llvm_tys orig_param_llvm_tys) args in
    let all_arg_strs = Printf.sprintf "ptr %s" clo_ptr :: orig_arg_strs in
    let release_float_arg_boxes ~(alias_of : string option) : unit =
      List.iter (fun b ->
        match alias_of with
        | None ->
          emit ctx (Printf.sprintf "call void @march_decrc_local(ptr %s)" b)
        | Some r ->
          let eq  = fresh ctx "fbaq" in
          emit ctx (Printf.sprintf "%s = icmp eq ptr %s, %s" eq b r);
          let rel  = fresh_block ctx "fbrel" in
          let cont = fresh_block ctx "fbcont" in
          emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
                           eq cont rel);
          emit_label ctx rel;
          emit ctx (Printf.sprintf "call void @march_decrc_local(ptr %s)" b);
          emit_term ctx (Printf.sprintf "br label %%%s" cont);
          emit_label ctx cont
      ) !float_arg_boxes;
      float_arg_boxes := []
    in
    if ret_ty = "void" then begin
      emit ctx (Printf.sprintf "call %s %s(%s)"
                  fn_ty_str fn_ptr (String.concat ", " all_arg_strs));
      release_float_arg_boxes ~alias_of:None;
      ("i64", "0")
    end else begin
      let r = fresh ctx "cr" in
      emit ctx (Printf.sprintf "%s = call %s %s(%s)"
                  r fn_ty_str fn_ptr (String.concat ", " all_arg_strs));
      release_float_arg_boxes ~alias_of:(Some r);
      (* Float RESULT: the value in the erased ptr slot is a march_float_box
         freshly allocated by the callee's return path — either its body's
         ("double","ptr") coerce or clo_wrap_define's double-return arm; a
         flow-through of an argument box re-boxes too whenever the callee's
         param is a real `double` (unbox at entry, re-box at return), and a
         GENERIC flow-through alias was left un-released by the guard above
         precisely so this release is its single one.  Unbox and release
         here, yielding the raw double; a consumer that needs the erased form
         re-boxes fresh (Float is immutable, the copy is unobservable).
         Before: one leaked box per Float-returning indirect call, unbounded
         (the fret_leg of the probe above). *)
      if llvm_ret_ty ret_tir = "double" && not is_potential_self_call then begin
        let d = fresh ctx "crf" in
        emit ctx (Printf.sprintf "%s = call double @march_unbox_float(ptr %s)" d r);
        emit ctx (Printf.sprintf "call void @march_decrc_local(ptr %s)" r);
        ("double", d)
      end else
        (ret_ty, r)
    end

