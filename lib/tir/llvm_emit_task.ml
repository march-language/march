(** Task codegen: the bodies of [Llvm_emit.emit_expr]'s three non-trivial
    task/distribution builtin arms.

    Phase 2b of specs/plans/2026-08-19-compiler-file-decomposition.md, the
    per-arm delegation Phase 2 deferred.  Every arm keeps its exact position,
    guard and order in [emit_expr]'s match -- match order there is
    load-bearing (non-builtin arms interleave with builtin ones, and the TCO
    arms sit below several builtin arms), so nothing is grouped or reordered.
    Only the arm BODIES live here, byte-identical to the text they replaced.
    [emit_atom] is threaded in as a labelled callback, the convention
    [Llvm_emit_simd] and [Llvm_emit_nmap] established.

    The other ~15 task arms (task_spawn, task_yield, receive, the cancel-token
    family, the Signal.watch trio, pmap_threshold, get_work_pool) stay inline:
    each is three to six lines, shorter than the call that would replace it. *)

open Llvm_ctx

let emit_store_field = Llvm_data.emit_store_field
let emit_heap_alloc = Llvm_data.emit_heap_alloc
let intern_string = Llvm_ctx.intern_string

(** Body of the `task_await_unwrap` arm: spin-wait, then untag the result
    directly.  Deliberately no [@march_task_await] call -- that variant
    allocates an Ok wrapper this path has no use for and nothing released. *)
let emit_task_await_unwrap ~emit_atom ctx (a : Tir.atom) : string * string =
    let (_, task_ptr) = emit_atom ctx a in
    let inner_ty = match a with
      | Tir.AVar v ->
        (match v.Tir.v_ty with
         | Tir.TCon ("Task", [inner]) -> llvm_ty inner
         | _ -> "ptr")
      | _ -> "ptr"
    in
    (* Spin-wait and return tagged raw result from task[3]; no Ok wrapper. *)
    let tv = fresh ctx "tv" in
    emit ctx (Printf.sprintf "%s = call ptr @march_task_await_value(ptr %s)" tv task_ptr);
    (* Untag: task[3] holds (llvm_ret << 1) | 1.  For ptr results llvm_ret is a
       heap address → one conditional ashr restores it; inttoptr recovers the ptr.
       For i64 results llvm_ret is already a tagged scalar (2*n+1), so task[3]
       holds 4*n+3 — double-tagged.  One coerce ptr→i64 yields 2*n+1; a second
       conditional ashr gives the raw n. *)
    let r_i64 = coerce ctx "ptr" tv "i64" in
    let r = if inner_ty = "ptr" then begin
      let p = fresh ctx "r" in
      emit ctx (Printf.sprintf "%s = inttoptr i64 %s to ptr" p r_i64);
      p
    end else if inner_ty = "i64" then
      emit_untag_scalar ctx ~and_pfx:"cv" ~ashr_pfx:"cv" ~icmp_pfx:"cv" ~sel_pfx:"r" r_i64
    else if inner_ty = "double" then begin
      (* r_i64 is a march_float_box pointer: the closure's apply fn already
         boxed its double result via the generic "double"->"ptr" coerce
         (march_alloc_float, float-boxing stage 2) before returning it to the
         trampoline, so — like the "ptr" case above — the tag/untag round
         trip through task[3] is over a genuine heap pointer and lossless.
         Recover the pointer the same way, then unbox with the paired
         march_unbox_float (mirrors coerce's "ptr"->"double" arm). *)
      let p = fresh ctx "r" in
      emit ctx (Printf.sprintf "%s = inttoptr i64 %s to ptr" p r_i64);
      let d = fresh ctx "tfv" in
      emit ctx (Printf.sprintf "%s = call double @march_unbox_float(ptr %s)" d p);
      d
    end else r_i64 in
    (* Release the caller's Task handle.  task_await_unwrap is a CONSUMING
       builtin (it is absent from borrow.ml's extern_borrow_table, whose
       default is "owned"), so Perceus transfers the caller's reference here
       and emits an EIncRC at every earlier use — a double-await dups the
       handle first, so releasing once per await stays balanced.  Nothing else
       ever dropped it: march_task_spawn_thunk hands back RC=2 (caller +
       trampoline) and the trampoline drops only its own hold, leaving the
       48-byte Task immortal.  Atomic march_decrc, not the _local variant: the
       trampoline's own drop runs on a scheduler thread and can race this one.
       The read of task[3] above is complete by now, and the free is shallow,
       so a ptr payload the caller now owns is unaffected.  (A Float payload's
       box is still aliased from task[3] and still leaks — that is the
       remaining half of specs/todos/2026-08-12-float-boxing-task-trampoline-leak.md,
       which needs a tag-guarded release in the task's free path.) *)
    emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" task_ptr);
    (inner_ty, r)

  (* task_await(task_ptr) → delegate to march_task_await C runtime.
     march_task_await returns Ok(task[3]).  The thunk trampoline stored
     task[3] = (apply_ret << 1) | 1 — i.e. the apply-wrapper's uniform-slot
     return value tagged exactly once.  A boxed-ADT (Ok) field must hold that
     uniform value *verbatim*, and the two representations pull in opposite
     directions relative to the raw task[3]:
       • i64 payload — apply_ret is already a tagged scalar (2*n+1), so
         task[3] = 4*n+3 (double-tagged); the Ok(n) destructure untags once
         and would leave 2*n+1 (await(async(6*7)) → Ok(85), not 42).
       • ptr payload — apply_ret is a raw heap address; the Ok(x) destructure
         loads a ptr field *raw* (no untag), but task[3] holds (addr<<1)|1, so
         the field would carry a wild ~2*addr pointer → incrc/decrc misfire and
         the payload deref SIGSEGVs / OOMs.
       • double payload (Float) — apply_ret is a march_float_box pointer, NOT
         the double itself: the closure's apply fn already boxed its result
         through the generic "double"->"ptr" coerce (march_alloc_float,
         float-boxing stage 2) before returning it to the trampoline.  So a
         Float payload is a *heap address* and behaves exactly like the ptr
         case above — the box, not the value, is the uniform representation
         the Ok(v) destructure expects.
     In ALL cases the correct field value is apply_ret == task[3] >> 1, and
     task[3] is always odd (trampoline sets the low bit), so a single
     unconditional ashr-1 of the freshly-allocated Ok payload (field 0, offset
     16) is the exact inverse — for every llvm_ty (i64 / ptr / double are the
     only three it produces).  The i64 half mirrors task_await_unwrap
     (291f6b5f) and the await i64 fix (f89b8711); the ptr half fixes the
     heap-payload crash f89b8711's comment wrongly assumed was already correct.

     Do NOT unbox the double here.  This site normalizes an ADT *field* into
     the uniform representation; it does not produce the scalar.  The paired
     decode is the Ok(v) destructure's own "ptr"->"double" coerce, which loads
     the field raw and calls march_unbox_float — so unboxing here and storing
     the raw double bits back into the field made the destructure unbox a
     second time, dereferencing the IEEE-754 bit pattern as an address (2.5 →
     deref 0x4004000000000000 → SIGSEGV).  That is the whole of the
     "any Float-returning task segfaults" bug; see
     specs/progress/2026-08-21-float-returning-task-compiled.md.  Contrast
     task_await_unwrap's "double" branch, which DOES unbox — correctly, because
     it yields the scalar as its expression value rather than an ADT field. *)

(** Body of the `task_await` arm: delegate to the [march_task_await] C
    runtime and normalise the Ok payload. *)
let emit_task_await ~emit_atom ctx (a : Tir.atom) : string * string =
    let (_, tp) = emit_atom ctx a in
    let r = fresh ctx "tawait" in
    emit ctx (Printf.sprintf "%s = call ptr @march_task_await(ptr %s)" r tp);
    let fp = fresh ctx "tawf" in
    emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" fp r);
    let v  = fresh ctx "tawv" in
    emit ctx (Printf.sprintf "%s = load i64, ptr %s, align 8" v fp);
    let v2 = fresh ctx "tawv" in
    emit ctx (Printf.sprintf "%s = ashr i64 %s, 1" v2 v);
    emit ctx (Printf.sprintf "store i64 %s, ptr %s, align 8" v2 fp);
    (* A Float payload is a march_float_box smuggled through task[3], and
       march_task_await's mk_ok stored that SAME pointer into this fresh Ok
       cell without taking a reference for it.  task[3] keeps aliasing the box
       for the life of the Task — double-await is legal and hands a second Ok
       cell the identical pointer — so the Ok cell must own a reference of its
       own, or whoever releases the field first frees it under the other
       holder.  That "whoever" is now real: the Ok(v) destructure releases an
       erased-slot Float box on its unique path (Llvm_case), and without this
       +1 the second `match task_await(t)` on one Float task read freed memory
       (measured: r2 printed 0, then SIGTRAP).

       Only the "double" arm takes the +1.  A ptr payload's Ok(v) destructure
       binds a heap variable and Perceus drops it, which consumes task[3]'s
       one reference exactly as it does today; adding a +1 there would convert
       today's balance into a per-await leak, so that arm is left alone.  The
       residual here is that task[3]'s own reference to the box is still never
       released — the Task's free is shallow — i.e. the unchanged remainder of
       specs/todos/2026-08-12-float-boxing-task-trampoline-leak.md, which wants
       a tag-guarded release in the task free path.  This +1 does not add to
       that: it is balanced by the destructure's release. *)
    (match a with
     | Tir.AVar av when (match av.Tir.v_ty with
                         | Tir.TCon ("Task", [inner]) -> llvm_ty inner = "double"
                         | _ -> false) ->
       let bp = fresh ctx "tawbox" in
       emit ctx (Printf.sprintf "%s = inttoptr i64 %s to ptr" bp v2);
       emit ctx (Printf.sprintf "call void @march_incrc(ptr %s)" bp)
     | _ -> ());
    (* Release the caller's Task handle — same ownership argument as
       task_await_unwrap above (consuming builtin, Perceus dups for every
       earlier use, nothing else ever dropped the handle).  Emitted after the
       Ok payload has been read and normalised; the free is shallow, so the
       payload the Ok cell now carries is untouched. *)
    emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" tp);
    ("ptr", r)

(** Body of the `remote_ref_hashes` arm: constant-fold (sig_hash,
    impl_hash) for a remote function reference. *)
let emit_remote_ref_hashes ctx (mod_atom : Tir.atom) (fn_atom : Tir.atom)
  : string * string =
    let get_str_lit a = match a with
      | Tir.ALit (March_ast.Ast.LitString s) -> s
      | _ -> "" in
    let mod_name = get_str_lit mod_atom in
    let fn_name  = get_str_lit fn_atom in
    let qualified_key = mod_name ^ "." ^ fn_name in
    let find_h tbl =
      match Hashtbl.find_opt tbl qualified_key with
      | Some h -> h
      | None   -> Option.value ~default:"" (Hashtbl.find_opt tbl fn_name)
    in
    let sig_h  = find_h ctx.remote_sig_hashes in
    let impl_h = find_h ctx.remote_impl_hashes in
    let emit_str_lit s =
      let g = intern_string ctx s in
      let tmp = fresh ctx "rrhsl" in
      emit ctx (Printf.sprintf "%s = call ptr @march_string_lit(ptr %s, i64 %d)"
                  tmp g (String.length s));
      tmp
    in
    let sg_ptr  = emit_str_lit sig_h in
    let im_ptr  = emit_str_lit impl_h in
    let tup = emit_heap_alloc ctx 0 2 in
    emit_store_field ctx tup 0 "ptr" sg_ptr;
    emit_store_field ctx tup 1 "ptr" im_ptr;
    ("ptr", tup)

