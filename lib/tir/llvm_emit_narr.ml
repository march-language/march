(** Inline NativeArray element access: [native_<w>_arr_get] / [_set].

    Every `NativeArray.get_int(a, i)` (and the float, f32, i32 and u8
    variants) used to be an out-of-line call into the C runtime, so a tight
    loop over a flat array paid a call, a length reload and a bounds check
    LLVM could not see through on every element.  Strata's fluid step spent
    a visible share of its time in those calls.

    Here the common case is emitted inline, and the runtime function is
    called only on the branch that leaves it:

    - [get]: `i <u len` (one unsigned compare covers `i < 0` too, since a
      length is never negative), then a load at `arr + 32 + i * elem_size`,
      widened exactly as the C helper does (i32 sign-extends, u8
      zero-extends, f32 extends to double).  On the failing branch the
      original [native_<w>_arr_get] is called with the same arguments: it
      prints the same "<fn>: index N out of bounds (len=M)" message and
      exits, so the error text cannot drift from the runtime's.  The block
      ends in `unreachable` (the C check calls [exit]), which lets LLVM keep
      the `0 <= i < len` fact for the code after it.

    - [set]: the inline path is taken only when the C helper's own in-place
      path would be: index in bounds AND [IS_HEAP_PTR(arr)] AND an acquire
      load of the refcount reads 1 ([march_rc_is_unique]).  It stores the
      narrowed value and returns [arr] itself, exactly as the helper's FBIP
      branch does.  Every other case (out of bounds, or a shared array that
      needs copy-on-write) calls the original [native_<w>_arr_set], which
      owns the reference it is handed just as before, so the ownership
      contract seen by Perceus is unchanged: the argument is consumed, the
      result is owned.

    Layout (runtime/march_runtime.c [native_arr_alloc], march_runtime.h
    [NATIVE_ARR_HDR]): refcount at +0, length (int64) at +16, kind byte at
    +24, elements from +32.  The length of an array never changes after
    allocation, so a plain load of it is sound. *)

open Llvm_ctx

let emit   = Llvm_ctx.emit
let emit_label = Llvm_ctx.emit_label
let emit_term  = Llvm_ctx.emit_term
let fresh  = Llvm_ctx.fresh
let coerce = Llvm_ctx.coerce

(** One element width: the LLVM type of a stored element, its size, and the
    register type March sees ("i64" for the int widths, "double" for the
    float ones). *)
type width = {
  w_prefix : string;   (* runtime prefix, e.g. "native_int_arr" *)
  w_elem   : string;   (* LLVM element type in memory *)
  w_size   : int;      (* bytes per element *)
  w_reg    : string;   (* March-side register type *)
}

let widths = [
  { w_prefix = "native_int_arr";   w_elem = "i64";    w_size = 8; w_reg = "i64" };
  { w_prefix = "native_float_arr"; w_elem = "double"; w_size = 8; w_reg = "double" };
  { w_prefix = "native_f32_arr";   w_elem = "float";  w_size = 4; w_reg = "double" };
  { w_prefix = "native_i32_arr";   w_elem = "i32";    w_size = 4; w_reg = "i64" };
  { w_prefix = "native_u8_arr";    w_elem = "i8";     w_size = 1; w_reg = "i64" };
]

type op = Get | Set

(** [decode "native_u8_arr_get"] = [Some (u8 width, Get)]. *)
let decode (name : string) : (width * op) option =
  List.find_map (fun w ->
      if name = w.w_prefix ^ "_get" then Some (w, Get)
      else if name = w.w_prefix ^ "_set" then Some (w, Set)
      else None) widths

(** Widen a loaded element to its March register type. *)
let widen ctx (w : width) (v : string) : string =
  match w.w_elem with
  | "i64" | "double" -> v
  | "float" ->
    let r = fresh ctx "naw" in
    emit ctx (Printf.sprintf "%s = fpext float %s to double" r v); r
  | "i32" ->
    let r = fresh ctx "naw" in
    emit ctx (Printf.sprintf "%s = sext i32 %s to i64" r v); r
  | "i8" ->
    let r = fresh ctx "naw" in
    emit ctx (Printf.sprintf "%s = zext i8 %s to i64" r v); r
  | other -> failwith ("native array widen: unexpected elem " ^ other)

(** Narrow a March register value to the stored element type, as the C
    helper's `(CTYPE)val` cast does (trunc for ints, round-to-nearest for
    f32, which is LLVM's default [fptrunc]). *)
let narrow ctx (w : width) (v : string) : string =
  match w.w_elem with
  | "i64" | "double" -> v
  | "float" ->
    let r = fresh ctx "nan" in
    emit ctx (Printf.sprintf "%s = fptrunc double %s to float" r v); r
  | "i32" | "i8" ->
    let r = fresh ctx "nan" in
    emit ctx (Printf.sprintf "%s = trunc i64 %s to %s" r v w.w_elem); r
  | other -> failwith ("native array narrow: unexpected elem " ^ other)

(** `icmp ult i, len`, with len loaded from +16. *)
let emit_in_bounds ctx (arr : string) (iv : string) : string =
  let lenp = fresh ctx "nalenp" in
  emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" lenp arr);
  let len = fresh ctx "nalen" in
  emit ctx (Printf.sprintf "%s = load i64, ptr %s, align 8" len lenp);
  let ok = fresh ctx "naok" in
  emit ctx (Printf.sprintf "%s = icmp ult i64 %s, %s" ok iv len);
  ok

(** Address of element [iv]: arr + 32 + iv * size. *)
let emit_elem_ptr ctx (w : width) (arr : string) (iv : string) : string =
  let base = fresh ctx "nabase" in
  emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 32" base arr);
  let p = fresh ctx "naelp" in
  emit ctx (Printf.sprintf "%s = getelementptr inbounds %s, ptr %s, i64 %s"
              p w.w_elem base iv);
  p

let emit_call
    ~(emit_atom : Llvm_ctx.ctx -> Tir.atom -> string * string)
    (ctx : Llvm_ctx.ctx) (f : Tir.var) (args : Tir.atom list)
  : string * string =
  let (w, op) = Option.get (decode f.Tir.v_name) in
  let arg_pairs = List.map (fun a -> emit_atom ctx a) args in
  let arg i to_ty = let (ty, v) = List.nth arg_pairs i in coerce ctx ty v to_ty in
  let arr = arg 0 "ptr" in
  let iv = arg 1 "i64" in
  match op with
  | Get ->
    let ok = emit_in_bounds ctx arr iv in
    let ok_lbl = fresh_block ctx "naget_ok" in
    let oob_lbl = fresh_block ctx "naget_oob" in
    emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
                     ok ok_lbl oob_lbl);
    emit_label ctx oob_lbl;
    (* The runtime helper re-checks, prints its message and exits. *)
    let dead = fresh ctx "naoob" in
    emit ctx (Printf.sprintf "%s = call %s @%s_get(ptr %s, i64 %s)"
                dead w.w_reg w.w_prefix arr iv);
    emit_term ctx "unreachable";
    emit_label ctx ok_lbl;
    let p = emit_elem_ptr ctx w arr iv in
    let v = fresh ctx "naget" in
    emit ctx (Printf.sprintf "%s = load %s, ptr %s, align %d" v w.w_elem p w.w_size);
    (w.w_reg, widen ctx w v)
  | Set ->
    let vv = arg 2 w.w_reg in
    let ok = emit_in_bounds ctx arr iv in
    (* IS_HEAP_PTR(arr): untagged, >= one page, sign bit clear -- reproduced
       from the C helper rather than assumed, as the SIMD store does. *)
    let ai = fresh ctx "naai" in
    emit ctx (Printf.sprintf "%s = ptrtoint ptr %s to i64" ai arr);
    let tagbit = fresh ctx "natag" in
    emit ctx (Printf.sprintf "%s = and i64 %s, 1" tagbit ai);
    let untagged = fresh ctx "nant" in
    emit ctx (Printf.sprintf "%s = icmp eq i64 %s, 0" untagged tagbit);
    let page = fresh ctx "napg" in
    emit ctx (Printf.sprintf "%s = icmp uge i64 %s, 4096" page ai);
    let pos = fresh ctx "napos" in
    emit ctx (Printf.sprintf "%s = icmp sgt i64 %s, 0" pos ai);
    let h1 = fresh ctx "naheap" in
    emit ctx (Printf.sprintf "%s = and i1 %s, %s" h1 untagged page);
    let heap = fresh ctx "naheap" in
    emit ctx (Printf.sprintf "%s = and i1 %s, %s" heap h1 pos);
    let pre = fresh ctx "napre" in
    emit ctx (Printf.sprintf "%s = and i1 %s, %s" pre ok heap);
    (* The refcount is read only once the pointer is known to be a heap
       cell, as the C `&&` does. *)
    let rc_lbl = fresh_block ctx "naset_rc" in
    let inl_lbl = fresh_block ctx "naset_inl" in
    let slow_lbl = fresh_block ctx "naset_slow" in
    let merge_lbl = fresh_block ctx "naset_merge" in
    emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s" pre rc_lbl slow_lbl);
    emit_label ctx rc_lbl;
    let rc = fresh ctx "narc" in
    emit ctx (Printf.sprintf "%s = load atomic i64, ptr %s acquire, align 8" rc arr);
    let uniq = fresh ctx "nauniq" in
    emit ctx (Printf.sprintf "%s = icmp eq i64 %s, 1" uniq rc);
    emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s" uniq inl_lbl slow_lbl);
    emit_label ctx inl_lbl;
    let p = emit_elem_ptr ctx w arr iv in
    let nv = narrow ctx w vv in
    emit ctx (Printf.sprintf "store %s %s, ptr %s, align %d" w.w_elem nv p w.w_size);
    emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl);
    emit_label ctx slow_lbl;
    (* Out of bounds (the helper panics) or shared (it copies, writes and
       releases our reference). *)
    let slow = fresh ctx "naslow" in
    emit ctx (Printf.sprintf "%s = call ptr @%s_set(ptr %s, i64 %s, %s %s)"
                slow w.w_prefix arr iv w.w_reg vv);
    emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl);
    emit_label ctx merge_lbl;
    let r = fresh ctx "naset" in
    emit ctx (Printf.sprintf "%s = phi ptr [ %s, %%%s ], [ %s, %%%s ]"
                r arr inl_lbl slow slow_lbl);
    ("ptr", r)
