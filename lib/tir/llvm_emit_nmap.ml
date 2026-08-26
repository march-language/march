(** NativeArray map/map2 inline-loop codegen (P10 Phase 2/2c/Stage 4).

    Split verbatim out of [Llvm_emit] (Phase 2, Task 2.3 of
    specs/plans/2026-08-19-compiler-file-decomposition.md): the per-width
    descriptor and its name decoder, plus the two loop emitters. Nothing is
    renamed or reformatted -- this module is code motion only, proven by
    byte-identical LLVM IR across the 240-program oracle corpus.

    The four [emit_expr] arms that drive these stay where they are, in their
    exact original order; only the bodies of the loop emitters live here.
    [emit_atom] is threaded in as a labelled callback, the same convention the
    other sibling emitters use for [~emit_expr]. *)

open Llvm_ctx

let emit = Llvm_ctx.emit
let emit_label = Llvm_ctx.emit_label
let emit_term = Llvm_ctx.emit_term
let fresh = Llvm_ctx.fresh
let coerce = Llvm_ctx.coerce

(** Narrow-widths task (2026-08) — per-width descriptor resolved from an
    inline-loop synthetic name's stripped prefix (see
    [Native_map_inline.inline_name_of]/[decode_nmap_inline_name] below).
    [nw_mem_ty]/[nw_elem_size] describe the array's IN-MEMORY element
    representation; the callback ("boundary") ABI the apply fn is called
    at is always either `i64` (tagged immediate, for the three int-shaped
    widths) or `double` (float-boxing family, for float/f32) regardless of
    memory width — see [nw_boundary_float]. When the memory type differs
    from the boundary type, the loop needs a widen after the load (before
    the callback) and a narrow before the store (after the callback); see
    [nmap_widen]/[nmap_narrow] and their use in [emit_native_map_inline_loop]
    / [emit_native_map2_inline_loop]. For the two legacy widths (int/float)
    memory type == boundary type, so widen/narrow are no-ops and the
    emitted IR is byte-identical to before this task. *)
type nmap_width = {
  nw_len_fn : string;
  nw_alloc_fn : string;
  nw_mem_ty : string;
  nw_elem_size : int;
  nw_boundary_float : bool;
}

(** [None] for anything other than the five known width prefixes — the
    caller must treat that as "not one of our synthetic inline names" and
    fall through to the general EApp arm, NOT crash the compiler. This is
    total by construction: [decode_nmap_inline_name] recognizes the
    synthetic-name SHAPE only (prefix/suffix pattern), so a user-defined
    function that happens to match that shape (e.g. a hand-written
    [__my_map_inline]) can reach here with an unknown prefix. *)
let nmap_width_of_prefix = function
  | "native_int_arr"   -> Some { nw_len_fn = "native_int_arr_length";
                                  nw_alloc_fn = "native_int_arr_alloc_raw";
                                  nw_mem_ty = "i64"; nw_elem_size = 8; nw_boundary_float = false }
  | "native_float_arr" -> Some { nw_len_fn = "native_float_arr_length";
                                  nw_alloc_fn = "native_float_arr_alloc_raw";
                                  nw_mem_ty = "double"; nw_elem_size = 8; nw_boundary_float = true }
  | "native_f32_arr"   -> Some { nw_len_fn = "native_f32_arr_length";
                                  nw_alloc_fn = "native_f32_arr_alloc_raw";
                                  nw_mem_ty = "float"; nw_elem_size = 4; nw_boundary_float = true }
  | "native_i32_arr"   -> Some { nw_len_fn = "native_i32_arr_length";
                                  nw_alloc_fn = "native_i32_arr_alloc_raw";
                                  nw_mem_ty = "i32"; nw_elem_size = 4; nw_boundary_float = false }
  | "native_u8_arr"    -> Some { nw_len_fn = "native_u8_arr_length";
                                  nw_alloc_fn = "native_u8_arr_alloc_raw";
                                  nw_mem_ty = "i8"; nw_elem_size = 1; nw_boundary_float = false }
  | _ -> None

(** Widen a just-loaded memory-typed value [v] up to [width]'s callback
    boundary type (`i64` for the int-shaped widths, `double` for the
    float-boxing widths); identity (no instruction emitted) when memory
    type already equals boundary type -- the legacy i64/f64 widths, where
    this must be a true no-op to keep their IR byte-identical. u8 widens
    with `zext` (loads are 0..255, matching [NativeArray.get_u8]'s
    documented zero-extend contract and the runtime's DEF_NARROW_INT_ARR
    `(int64_t)(uint8_t)` cast); i32 widens with `sext`. *)
let nmap_widen ctx (width : nmap_width) (v : string) : string =
  match width.nw_mem_ty with
  | "i64" | "double" -> v
  | "float" ->
    let r = fresh ctx "nmap_w" in
    emit ctx (Printf.sprintf "%s = fpext float %s to double" r v); r
  | "i32" ->
    let r = fresh ctx "nmap_w" in
    emit ctx (Printf.sprintf "%s = sext i32 %s to i64" r v); r
  | "i8" ->
    let r = fresh ctx "nmap_w" in
    emit ctx (Printf.sprintf "%s = zext i8 %s to i64" r v); r
  | other -> failwith ("nmap_widen: unexpected mem type " ^ other)

(** Narrow a boundary-typed callback result [v] down to [width]'s memory
    type before storing it (mirrors the runtime's DEF_NARROW_INT_ARR/f32
    `(CTYPE)`/`(float)` truncating casts: two's-complement wrap for i32/u8,
    round-to-nearest-even for f32); identity for the legacy i64/f64 widths. *)
let nmap_narrow ctx (width : nmap_width) (v : string) : string =
  match width.nw_mem_ty with
  | "i64" | "double" -> v
  | "float" ->
    let r = fresh ctx "nmap_n" in
    emit ctx (Printf.sprintf "%s = fptrunc double %s to float" r v); r
  | "i32" ->
    let r = fresh ctx "nmap_n" in
    emit ctx (Printf.sprintf "%s = trunc i64 %s to i32" r v); r
  | "i8" ->
    let r = fresh ctx "nmap_n" in
    emit ctx (Printf.sprintf "%s = trunc i64 %s to i8" r v); r
  | other -> failwith ("nmap_narrow: unexpected mem type " ^ other)

(** Decompose an inline-loop synthetic name (produced by
    [Native_map_inline.inline_name_of]) back into (width_prefix, is_map2,
    unboxed), e.g. ["__native_f32_arr_map2_inline_unboxed"] ->
    [("native_f32_arr", true, true)]. [None] for anything that isn't one of
    these synthetic names (the general EApp arm's problem). *)
let decode_nmap_inline_name (name : string) : (string * bool * bool) option =
  let has_prefix pre s =
    let lp = String.length pre and ln = String.length s in
    ln >= lp && String.sub s 0 lp = pre
  in
  let has_suffix suf s =
    let ls = String.length suf and ln = String.length s in
    ln >= ls && String.sub s (ln - ls) ls = suf
  in
  let strip_suffix suf s = String.sub s 0 (String.length s - String.length suf) in
  if not (has_prefix "__" name) then None
  else
    let rest = String.sub name 2 (String.length name - 2) in
    let (rest, unboxed) =
      if has_suffix "_unboxed" rest then (strip_suffix "_unboxed" rest, true) else (rest, false)
    in
    if has_suffix "_map2_inline" rest then Some (strip_suffix "_map2_inline" rest, true, unboxed)
    else if has_suffix "_map_inline" rest then Some (strip_suffix "_map_inline" rest, false, unboxed)
    else None

(** Combines [decode_nmap_inline_name] (name-SHAPE recognition) with
    [nmap_width_of_prefix] (prefix-is-a-known-width lookup) into one total
    function: [None] unless BOTH the name shape matches AND the decoded
    prefix is one of the five known widths. The dispatch arms below use
    this (not [decode_nmap_inline_name] alone) as their [when] guard, so a
    name that merely LOOKS like a synthetic inline name but carries an
    unrecognized width prefix falls through to the general EApp arm instead
    of reaching [nmap_width_of_prefix] partial-match failure. *)
let decode_nmap_inline_call (name : string) : (nmap_width * bool * bool) option =
  match decode_nmap_inline_name name with
  | None -> None
  | Some (prefix, is_map2, unboxed) ->
    (match nmap_width_of_prefix prefix with
     | None -> None
     | Some width -> Some (width, is_map2, unboxed))

(** P10 Phase 2/2c — shared codegen for the NativeArray map inline loop.
    Emits: length -> uninitialized alloc -> for-loop (load elem, tag/box to
    the wire ptr ABI, DIRECT call to [apply_name], untag/unbox, store).
    [clo_reg] is the LLVM value to pass as the apply fn's $clo argument —
    the literal ["null"] for a non-capturing closure (Phase 2; the apply
    body never reads $clo), or a real closure-struct pointer register for a
    capturing one (Phase 2c; the apply body loads free vars from it). See
    [Native_map_inline] for which shape produces which.

    [unboxed] (Float only; ignored for Int) selects Stage 4 Option B: call
    an unboxed clone of the apply fn (see [Native_map_inline.try_unboxed_variant])
    that takes/returns a raw `double` directly instead of the generic boxed
    `ptr` ABI — no march_alloc_float/march_unbox_float anywhere, argument
    or return. This is what actually lets the loop vectorize; the
    argument-box-reuse path above (still used when [unboxed] is false,
    e.g. a still-generic signature) only cuts allocation traffic. *)
let emit_native_map_inline_loop
    ~(emit_atom : Llvm_ctx.ctx -> Tir.atom -> string * string)
    ctx ~(width : nmap_width) ~unboxed ~arr_atom ~apply_name ~clo_reg
    : string * string =
  let is_float = width.nw_boundary_float in
  let boundary_ty = if is_float then "double" else "i64" in
  let mem_ty = width.nw_mem_ty in
  let elem_size = width.nw_elem_size in
  let len_fn = width.nw_len_fn in
  let alloc_fn = width.nw_alloc_fn in
  (* Open a dedicated preheader so its label is known for the loop phi,
     regardless of what block was open before this arm ran. *)
  let preheader = fresh_block ctx "nmap_pre" in
  emit_term ctx (Printf.sprintf "br label %%%s" preheader);
  emit_label ctx preheader;
  let (arr_ty0, arr_v0) = emit_atom ctx arr_atom in
  let arr_v = coerce ctx arr_ty0 arr_v0 "ptr" in
  let len = fresh ctx "nmap_len" in
  emit ctx (Printf.sprintf "%s = call i64 @%s(ptr %s)" len len_fn arr_v);
  let new_arr = fresh ctx "nmap_out" in
  emit ctx (Printf.sprintf "%s = call ptr @%s(i64 %s)" new_arr alloc_fn len);
  (* Float, non-unboxed only: allocate ONE reusable wire-argument box before
     the loop, instead of a fresh march_alloc_float per element. Safe
     because every (boxed-ABI) apply function unconditionally unboxes its
     argument as its very first instruction and never touches the pointer
     again — the generated prologue is always `call double
     @march_unbox_float(ptr %x.arg)` before any user code runs (verified
     via -emit-llvm on a compiled lambda), so nothing can observe or retain
     this box's identity across calls. Overwriting its .val field between
     iterations is therefore indistinguishable from fresh-boxing each time,
     at 1/N the allocation cost. march_float_box layout is
     [rc:8][tag:4][pad:4][val:8] (24 bytes, runtime/march_runtime.h) — val
     is at byte offset 16. When [unboxed] is true there is no box at all —
     the callee takes/returns a raw double directly (Stage 4 Option B) —
     so this allocation is skipped entirely rather than merely reused.
     Int has no equivalent box either way — its wire value is a tagged
     immediate (coerce's "i64"/"ptr" arm), not an allocation. *)
  let arg_box = if is_float && not unboxed then begin
      let b = fresh ctx "nmap_argbox" in
      emit ctx (Printf.sprintf "%s = call ptr @march_alloc_float(double 0.000000e+00)" b);
      Some b
    end else None in
  let cond_lbl = fresh_block ctx "nmap_cond" in
  let body_lbl = fresh_block ctx "nmap_body" in
  let exit_lbl = fresh_block ctx "nmap_exit" in
  emit_term ctx (Printf.sprintf "br label %%%s" cond_lbl);

  emit_label ctx cond_lbl;
  let i = fresh ctx "nmap_i" in
  let i_next = fresh ctx "nmap_inext" in
  emit ctx (Printf.sprintf "%s = phi i64 [ 0, %%%s ], [ %s, %%%s ]" i preheader i_next body_lbl);
  let cmp = fresh ctx "nmap_cmp" in
  emit ctx (Printf.sprintf "%s = icmp slt i64 %s, %s" cmp i len);
  emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s" cmp body_lbl exit_lbl);

  emit_label ctx body_lbl;
  (* Both source and dest arrays share the same NATIVE_ARR_HDR=32 layout
     (the #define lives in march_runtime.h), so one offset serves both
     GEPs. The multiplier and the load/store alignment are the width's own
     element size (8 for the legacy i64/f64 widths -- unchanged -- 4 for
     f32/i32, 1 for u8). *)
  let soff = fresh ctx "nmap_soff" in
  emit ctx (Printf.sprintf "%s = mul i64 %s, %d" soff i elem_size);
  let byte_off = fresh ctx "nmap_off" in
  emit ctx (Printf.sprintf "%s = add i64 %s, 32" byte_off soff);
  let sptr = fresh ctx "nmap_sptr" in
  emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 %s" sptr arr_v byte_off);
  let x = fresh ctx "nmap_x" in
  emit ctx (Printf.sprintf "%s = load %s, ptr %s, align %d" x mem_ty sptr elem_size);
  (* Widen the just-loaded memory-typed value up to the callback boundary
     type (no-op for the legacy i64/f64 widths). *)
  let x = nmap_widen ctx width x in
  (* RC contract: [apply_name] is called once per element with the SAME
     [clo_reg] throughout the loop.  For a capturing closure (clo_reg <>
     "null"), lib/tir/perceus.ml's insert_apply_fn_clo_drop makes every one
     of those calls release $clo internally — so without this incrc,
     element 0's call already frees the closure and every later element
     calls through freed memory.  Mirrors the identical fix applied to the
     C-runtime map/fold helpers (native_int_arr_map et al.,
     runtime/march_runtime.c) for the general (non-inlined) path; this is
     the inlined-loop counterpart, since Phase 2c's whole point is to call
     [apply_name] directly and never go through those helpers at all.

     [clo_reg] itself arrives here as ONE transferred reference: per
     [Native_map_inline]'s own doc comment, this rewrite fires ONLY when
     the closure var is single-use with no Perceus-inserted RC op anywhere
     else in the TIR (any other use — e.g. the closure captured AND called
     again elsewhere — makes the pass decline and fall back to the general
     path, which owns the same contract in the C runtime). That single use
     being "last use, no incref" is exactly Perceus's ordinary
     transfer-on-call convention: the callee (originally
     native_int_arr_map/native_float_arr_map; now this inlined loop
     standing in for it) is trusted to consume the one reference. So this
     loop must fully consume it too — [march_decrc] after the loop below,
     matching the C-runtime fix's final decrc exactly, not merely balance
     each call's internal drop.

     "null" (Phase 2, non-capturing) skips both the per-call incrc and the
     final decrc: the apply function never reads $clo, so
     insert_apply_fn_clo_drop's fv-extraction guard means no drop ever
     fires, and there is no reference to release — matching how this
     function was already exempt before the $clo ownership work. *)
  if clo_reg <> "null" then
    emit ctx (Printf.sprintf "call void @march_incrc(ptr %s)" clo_reg);
  let y_boundary =
    if unboxed then begin
      (* No box either side: raw double in, raw double out. This is the
         shape that actually vectorizes — no allocation call anywhere in
         the loop for the vectorizer to trip over. *)
      let y = fresh ctx "nmap_y" in
      emit ctx (Printf.sprintf "%s = call double @%s(ptr %s, double %s)" y apply_name clo_reg x);
      y
    end else begin
      let wire_arg = match arg_box with
        | Some b ->
          let vfield = fresh ctx "nmap_argval" in
          emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" vfield b);
          emit ctx (Printf.sprintf "store double %s, ptr %s, align 8" x vfield);
          b
        | None -> coerce ctx boundary_ty x "ptr"
      in
      let y = fresh ctx "nmap_y" in
      emit ctx (Printf.sprintf "%s = call ptr @%s(ptr %s, ptr %s)" y apply_name clo_reg wire_arg);
      coerce ctx "ptr" y boundary_ty
    end
  in
  (* Narrow the boundary-typed result back down to the memory type before
     storing it (no-op for the legacy i64/f64 widths). *)
  let y_native = nmap_narrow ctx width y_boundary in
  let dptr = fresh ctx "nmap_dptr" in
  emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 %s" dptr new_arr byte_off);
  emit ctx (Printf.sprintf "store %s %s, ptr %s, align %d" mem_ty y_native dptr elem_size);
  emit ctx (Printf.sprintf "%s = add i64 %s, 1" i_next i);
  emit_term ctx (Printf.sprintf "br label %%%s" cond_lbl);

  emit_label ctx exit_lbl;
  (* Release the one transferred reference to [clo_reg] — see the RC
     contract comment above the incrc inside the loop body. *)
  if clo_reg <> "null" then
    emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" clo_reg);
  ("ptr", new_arr)

(** [Native_map_inline]'s two-array counterpart to [emit_native_map_inline_loop]
    above (map2 added 2026-07-27 to unblock [DataFrame.col_add_col]). Same
    trick, same wire ABI, same [~unboxed] Stage 4 Option B path — just two
    source arrays read per iteration and a 2-argument call to [apply_name]
    instead of one. One addition with no equivalent in the single-array
    case: [native_int_arr_map2]/[native_float_arr_map2]'s own length-mismatch
    panic (`NativeArray.map2_*`'s documented contract) has to be reproduced
    here explicitly, since this loop calls the lifted apply fn directly and
    never goes through those functions at all — see
    [native_arr_map2_check_len] (runtime/march_runtime.c). It's emitted once
    in the preheader (not per-iteration), so it costs nothing in the hot
    loop and doesn't touch anything the vectorizer looks at. *)
let emit_native_map2_inline_loop
    ~(emit_atom : Llvm_ctx.ctx -> Tir.atom -> string * string)
    ctx ~(width : nmap_width) ~unboxed ~arr1_atom ~arr2_atom ~apply_name ~clo_reg
    : string * string =
  let is_float = width.nw_boundary_float in
  let boundary_ty = if is_float then "double" else "i64" in
  let mem_ty = width.nw_mem_ty in
  let elem_size = width.nw_elem_size in
  let len_fn = width.nw_len_fn in
  let alloc_fn = width.nw_alloc_fn in
  let preheader = fresh_block ctx "nmap2_pre" in
  emit_term ctx (Printf.sprintf "br label %%%s" preheader);
  emit_label ctx preheader;
  let (arr1_ty0, arr1_v0) = emit_atom ctx arr1_atom in
  let arr1_v = coerce ctx arr1_ty0 arr1_v0 "ptr" in
  let (arr2_ty0, arr2_v0) = emit_atom ctx arr2_atom in
  let arr2_v = coerce ctx arr2_ty0 arr2_v0 "ptr" in
  let len1 = fresh ctx "nmap2_len1" in
  emit ctx (Printf.sprintf "%s = call i64 @%s(ptr %s)" len1 len_fn arr1_v);
  let len2 = fresh ctx "nmap2_len2" in
  emit ctx (Printf.sprintf "%s = call i64 @%s(ptr %s)" len2 len_fn arr2_v);
  emit ctx (Printf.sprintf "call void @native_arr_map2_check_len(i64 %s, i64 %s)" len1 len2);
  let new_arr = fresh ctx "nmap2_out" in
  emit ctx (Printf.sprintf "%s = call ptr @%s(i64 %s)" new_arr alloc_fn len1);
  (* Float, non-unboxed only: reuse two wire-argument boxes (one per source
     array) across iterations instead of a fresh march_alloc_float per
     element per array — same reasoning as [emit_native_map_inline_loop]'s
     single [arg_box]. Skipped entirely when [unboxed] (no box at all, Stage
     4 Option B) or for Int (tagged immediate, no allocation either way). *)
  let arg_boxes = if is_float && not unboxed then begin
      let b1 = fresh ctx "nmap2_argbox1" in
      emit ctx (Printf.sprintf "%s = call ptr @march_alloc_float(double 0.000000e+00)" b1);
      let b2 = fresh ctx "nmap2_argbox2" in
      emit ctx (Printf.sprintf "%s = call ptr @march_alloc_float(double 0.000000e+00)" b2);
      Some (b1, b2)
    end else None in
  let cond_lbl = fresh_block ctx "nmap2_cond" in
  let body_lbl = fresh_block ctx "nmap2_body" in
  let exit_lbl = fresh_block ctx "nmap2_exit" in
  emit_term ctx (Printf.sprintf "br label %%%s" cond_lbl);

  emit_label ctx cond_lbl;
  let i = fresh ctx "nmap2_i" in
  let i_next = fresh ctx "nmap2_inext" in
  emit ctx (Printf.sprintf "%s = phi i64 [ 0, %%%s ], [ %s, %%%s ]" i preheader i_next body_lbl);
  let cmp = fresh ctx "nmap2_cmp" in
  emit ctx (Printf.sprintf "%s = icmp slt i64 %s, %s" cmp i len1);
  emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s" cmp body_lbl exit_lbl);

  emit_label ctx body_lbl;
  (* Both source arrays and the dest array share the same
     NATIVE_ARR_HDR=32 layout (the #define lives in march_runtime.h), so one
     offset serves all three GEPs. The multiplier and the load/store alignment are the
     width's own element size (8 for the legacy i64/f64 widths --
     unchanged -- 4 for f32/i32, 1 for u8). *)
  let soff = fresh ctx "nmap2_soff" in
  emit ctx (Printf.sprintf "%s = mul i64 %s, %d" soff i elem_size);
  let byte_off = fresh ctx "nmap2_off" in
  emit ctx (Printf.sprintf "%s = add i64 %s, 32" byte_off soff);
  let sptr1 = fresh ctx "nmap2_sptr1" in
  emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 %s" sptr1 arr1_v byte_off);
  let x = fresh ctx "nmap2_x" in
  emit ctx (Printf.sprintf "%s = load %s, ptr %s, align %d" x mem_ty sptr1 elem_size);
  let sptr2 = fresh ctx "nmap2_sptr2" in
  emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 %s" sptr2 arr2_v byte_off);
  let y = fresh ctx "nmap2_y" in
  emit ctx (Printf.sprintf "%s = load %s, ptr %s, align %d" y mem_ty sptr2 elem_size);
  (* Widen both just-loaded memory-typed values up to the callback boundary
     type (no-op for the legacy i64/f64 widths). *)
  let x = nmap_widen ctx width x in
  let y = nmap_widen ctx width y in
  (* Same RC contract as [emit_native_map_inline_loop] above: incrc before
     each call to balance that call's internal $clo drop for a capturing
     closure, matched by a final decrc after the loop (below) that
     releases the one transferred reference. *)
  if clo_reg <> "null" then
    emit ctx (Printf.sprintf "call void @march_incrc(ptr %s)" clo_reg);
  let z_boundary =
    if unboxed then begin
      let z = fresh ctx "nmap2_z" in
      emit ctx (Printf.sprintf "%s = call double @%s(ptr %s, double %s, double %s)" z apply_name clo_reg x y);
      z
    end else begin
      let (wire_x, wire_y) = match arg_boxes with
        | Some (b1, b2) ->
          let vfield1 = fresh ctx "nmap2_argval1" in
          emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" vfield1 b1);
          emit ctx (Printf.sprintf "store double %s, ptr %s, align 8" x vfield1);
          let vfield2 = fresh ctx "nmap2_argval2" in
          emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" vfield2 b2);
          emit ctx (Printf.sprintf "store double %s, ptr %s, align 8" y vfield2);
          (b1, b2)
        | None -> (coerce ctx boundary_ty x "ptr", coerce ctx boundary_ty y "ptr")
      in
      let z = fresh ctx "nmap2_z" in
      emit ctx (Printf.sprintf "%s = call ptr @%s(ptr %s, ptr %s, ptr %s)" z apply_name clo_reg wire_x wire_y);
      coerce ctx "ptr" z boundary_ty
    end
  in
  (* Narrow the boundary-typed result back down to the memory type before
     storing it (no-op for the legacy i64/f64 widths). *)
  let z_native = nmap_narrow ctx width z_boundary in
  let dptr = fresh ctx "nmap2_dptr" in
  emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 %s" dptr new_arr byte_off);
  emit ctx (Printf.sprintf "store %s %s, ptr %s, align %d" mem_ty z_native dptr elem_size);
  emit ctx (Printf.sprintf "%s = add i64 %s, 1" i_next i);
  emit_term ctx (Printf.sprintf "br label %%%s" cond_lbl);

  emit_label ctx exit_lbl;
  if clo_reg <> "null" then
    emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" clo_reg);
  ("ptr", new_arr)

(* ── Vault reads: niche → call-site Option encoding ───────────────────── *)
