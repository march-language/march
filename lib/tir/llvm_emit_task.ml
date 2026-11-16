(** Task codegen: the bodies of [Llvm_emit.emit_expr]'s four non-trivial
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
         | Tir.TCon ("Task", [inner]) -> llvm_ty ctx inner
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
      (* The Task keeps its own reference to a heap result (runtime
         MARCH_TASK_OWNS_RESULT) and releases it when it dies, which may be
         the march_decrc just below; the caller gets a reference of its own,
         taken first.  A no-op for a scalar in an erased slot. *)
      emit ctx (Printf.sprintf "call void @march_incrc(ptr %s)" p);
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
       The read of task[3] above is complete by now, and a heap payload the
       caller keeps has its own reference (taken above); if this is the last
       handle the Task's destructor releases the Task's reference to the
       result. *)
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
     16) is the exact inverse — for every llvm_ty ctx (i64 / ptr / double are the
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

(** Normalise, in place, the Result cell [r] that [march_task_await] or
    [march_task_poll] built from a Task's result word (see the long comment
    above): under the Ok tag, untag the payload once.  Leaves the builder in a
    fresh block after the normalisation. *)
let normalise_task_result ctx (r : string) : unit =
    (* A cancelled task (a hard drain deadline, or task_cancel) comes back as
       Err("task cancelled"), whose field is a string, not a tagged result:
       normalise the payload only under the Ok tag (i32 at +8). *)
    let tagp = fresh ctx "tawtagp" in
    emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 8" tagp r);
    let tag = fresh ctx "tawtag" in
    emit ctx (Printf.sprintf "%s = load i32, ptr %s, align 4" tag tagp);
    let isok = fresh ctx "tawok" in
    emit ctx (Printf.sprintf "%s = icmp eq i32 %s, 0" isok tag);
    let lbl_ok = fresh_block ctx "tawait_ok" and lbl_done = fresh_block ctx "tawait_done" in
    emit ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s" isok lbl_ok lbl_done);
    emit_label ctx lbl_ok;
    let fp = fresh ctx "tawf" in
    emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" fp r);
    let v  = fresh ctx "tawv" in
    emit ctx (Printf.sprintf "%s = load i64, ptr %s, align 8" v fp);
    let v2 = fresh ctx "tawv" in
    emit ctx (Printf.sprintf "%s = ashr i64 %s, 1" v2 v);
    emit ctx (Printf.sprintf "store i64 %s, ptr %s, align 8" v2 fp);
    (* No reference is taken here: the Ok cell already holds its own.  The
       Task owns its heap result (a Float box, a String, any heap value) and
       march_task_await / march_task_poll take a reference for every Ok cell
       they build (task_result_ok in runtime/march_runtime.c), so any number
       of reads may each release theirs.  This arm used to take the Float
       box's reference itself, while a ptr payload's one reference went to
       the first reader and a second await read freed memory. *)
    emit ctx (Printf.sprintf "br label %%%s" lbl_done);
    emit_label ctx lbl_done

(** Body of the `task_await` arm: delegate to the [march_task_await] C
    runtime and normalise the Ok payload. *)
let emit_task_await ~emit_atom ctx (a : Tir.atom) : string * string =
    let (_, tp) = emit_atom ctx a in
    let r = fresh ctx "tawait" in
    emit ctx (Printf.sprintf "%s = call ptr @march_task_await(ptr %s)" r tp);
    normalise_task_result ctx r;
    (* Release the caller's Task handle — same ownership argument as
       task_await_unwrap above (consuming builtin, Perceus dups for every
       earlier use, nothing else ever dropped the handle).  Emitted after the
       Ok payload has been read and normalised; the free is shallow, so the
       payload the Ok cell now carries is untouched. *)
    emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" tp);
    ("ptr", r)

(** Body of the `task_poll` arm: [march_task_poll] answers NULL while the
    task runs (Option's niche None for an Option(Result(..)), so a pending
    poll allocates nothing) or the same Ok/Err cell [march_task_await] builds,
    normalised the same way.  Unlike the await arms this does NOT release the
    Task: task_poll borrows its argument (lib/tir/borrow.ml), since a frame
    loop polls one handle many times.  The caller re-encodes the answer when
    the call site decodes Option as boxed. *)
let emit_task_poll ~emit_atom ctx (a : Tir.atom) : string =
    let (_, tp) = emit_atom ctx a in
    let r = fresh ctx "tpoll" in
    emit ctx (Printf.sprintf "%s = call ptr @march_task_poll(ptr %s)" r tp);
    let isnull = fresh ctx "tpollnull" in
    emit ctx (Printf.sprintf "%s = icmp eq ptr %s, null" isnull r);
    let lbl_some = fresh_block ctx "tpoll_some" and lbl_done = fresh_block ctx "tpoll_done" in
    emit ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s" isnull lbl_done lbl_some);
    emit_label ctx lbl_some;
    normalise_task_result ctx r;
    emit ctx (Printf.sprintf "br label %%%s" lbl_done);
    emit_label ctx lbl_done;
    r

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
    let tup = emit_heap_alloc ctx 0 2 0 in
    emit_store_field ctx tup 0 "ptr" sg_ptr;
    emit_store_field ctx tup 1 "ptr" im_ptr;
    ("ptr", tup)

