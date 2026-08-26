(** SIMD codegen: the `simd_<type>_<op>` builtin family.

    Split verbatim out of [Llvm_emit] (Phase 2, Task 2.3 of
    specs/plans/2026-08-19-compiler-file-decomposition.md): the shape table
    and decoder, plus the body of [emit_expr]'s SIMD intercept arm. Nothing
    is renamed or reformatted -- this module is code motion only, proven by
    byte-identical LLVM IR across the 240-program oracle corpus.

    The arm keeps its exact position in [emit_expr]'s match; only its body
    lives here, reached through [emit_simd_call]. [emit_atom] is threaded in
    as a labelled callback, the same convention the other sibling emitters
    ([Llvm_calls], [Llvm_case], ...) use for [~emit_expr]. *)

open Llvm_ctx

let emit   = Llvm_ctx.emit
let emit_label = Llvm_ctx.emit_label
let emit_term  = Llvm_ctx.emit_term
let fresh  = Llvm_ctx.fresh
let coerce = Llvm_ctx.coerce

(* ── SIMD vector types (Task 2): name decoder + per-type LLVM shape table.
   127 `simd_<t>_<op>` builtins (Task 1, interpreter path) map onto 5 vector
   types; this table is the compiled side's single source of truth for each
   type's LLVM vector-type string, runtime `kind` tag (see
   runtime/march_runtime.c's [march_simd_alloc]), lane count, LLVM element
   type name, and whether the March-level boundary type for scalar lane
   traffic (splat/extract/replace/shl-count/sum/hmin/hmax) is `double`
   (float families) or `i64` (int families, including u8 — u8 lanes widen
   ZERO-extended, see [simd_widen]). *)
type simd_ty = { s_vec : string; s_kind : int; s_lanes : int;
                 s_elem : string (* "float" "double" "i32" "i64" "i8" *);
                 s_boundary_float : bool;
                 s_arr_prefix : string (* Task 3: runtime native-array fn prefix for load/store *) }

let simd_tys = [
  "f32x4", { s_vec = "<4 x float>";  s_kind = 0; s_lanes = 4;  s_elem = "float";  s_boundary_float = true;  s_arr_prefix = "native_f32_arr" };
  "f64x2", { s_vec = "<2 x double>"; s_kind = 1; s_lanes = 2;  s_elem = "double"; s_boundary_float = true;  s_arr_prefix = "native_float_arr" };
  "i32x4", { s_vec = "<4 x i32>";    s_kind = 2; s_lanes = 4;  s_elem = "i32";    s_boundary_float = false; s_arr_prefix = "native_i32_arr" };
  "i64x2", { s_vec = "<2 x i64>";    s_kind = 3; s_lanes = 2;  s_elem = "i64";    s_boundary_float = false; s_arr_prefix = "native_int_arr" };
  "u8x16", { s_vec = "<16 x i8>";    s_kind = 4; s_lanes = 16; s_elem = "i8";     s_boundary_float = false; s_arr_prefix = "native_u8_arr" };
]

(** Decode a builtin call name like ["simd_f32x4_add"] into (type record,
    "add"). Total: any name that isn't shaped "simd_<known-type>_<op>"
    returns [None] and the general [EApp] arm handles it (this can only
    happen for a genuinely unrelated user- or extern-defined name that
    happens to start with "simd_", never for one of the 127 known builtins). *)
let decode_simd_call (name : string) : (simd_ty * string) option =
  if not (String.length name > 5 && String.sub name 0 5 = "simd_") then None
  else
    let rest = String.sub name 5 (String.length name - 5) in
    match String.index_opt rest '_' with
    | None -> None
    | Some i ->
      let t = String.sub rest 0 i and op = String.sub rest (i + 1) (String.length rest - i - 1) in
      (match List.assoc_opt t simd_tys with Some r -> Some (r, op) | None -> None)

(** Element bit-width, derived from [s_elem] rather than stored redundantly. *)
let simd_elem_bits (sty : simd_ty) : int =
  match sty.s_elem with
  | "float" | "i32" -> 32
  | "double" | "i64" -> 64
  | "i8" -> 8
  | other -> failwith ("simd_elem_bits: unexpected elem ty " ^ other)

(** The all-integer vector type of the same lane count/width as [sty.s_vec] —
    identity for the already-integer families, the bitcast target for the
    float families' bitwise/compare/mask ops (which have no native float
    bitwise instruction). *)
let simd_int_vec_ty (sty : simd_ty) : string =
  match sty.s_elem with
  | "float"  -> Printf.sprintf "<%d x i32>" sty.s_lanes
  | "double" -> Printf.sprintf "<%d x i64>" sty.s_lanes
  | _        -> sty.s_vec

(** `vNeT` intrinsic name suffix (e.g. "v4f32", "v2i64") shared by the
    per-vector intrinsics (minnum/maxnum/smin/smax/fma/sqrt/reduce). *)
let simd_intrinsic_suffix (sty : simd_ty) : string =
  let et = match sty.s_elem with
    | "float" -> "f32" | "double" -> "f64"
    | "i32" -> "i32" | "i64" -> "i64" | "i8" -> "i8"
    | other -> failwith ("simd_intrinsic_suffix: unexpected elem ty " ^ other)
  in
  Printf.sprintf "v%d%s" sty.s_lanes et

(** Narrow a boundary-typed scalar (`double` or `i64`, per [s_boundary_float])
    down to the vector's element type — the inverse of [simd_widen]. f64x2/
    i64x2 are no-ops (element IS the boundary type). *)
let simd_narrow ctx (sty : simd_ty) (b_v : string) : string =
  match sty.s_elem with
  | "float" ->
    let r = fresh ctx "vnrw" in
    emit ctx (Printf.sprintf "%s = fptrunc double %s to float" r b_v); r
  | "double" -> b_v
  | "i32" ->
    let r = fresh ctx "vnrw" in
    emit ctx (Printf.sprintf "%s = trunc i64 %s to i32" r b_v); r
  | "i64" -> b_v
  | "i8" ->
    let r = fresh ctx "vnrw" in
    emit ctx (Printf.sprintf "%s = trunc i64 %s to i8" r b_v); r
  | other -> failwith ("simd_narrow: unexpected elem ty " ^ other)

(** Widen an element-typed scalar back up to the boundary type. u8's widen is
    a ZERO-extend (the interpreter's u8 lanes are unsigned magnitudes 0..255,
    [simd_u8_is_highbit]/comparisons treat them that way) — every other int
    family sign-extends. *)
let simd_widen ctx (sty : simd_ty) (e_v : string) : string =
  match sty.s_elem with
  | "float" ->
    let r = fresh ctx "vwid" in
    emit ctx (Printf.sprintf "%s = fpext float %s to double" r e_v); r
  | "double" -> e_v
  | "i32" ->
    let r = fresh ctx "vwid" in
    emit ctx (Printf.sprintf "%s = sext i32 %s to i64" r e_v); r
  | "i64" -> e_v
  | "i8" ->
    let r = fresh ctx "vwid" in
    emit ctx (Printf.sprintf "%s = zext i8 %s to i64" r e_v); r
  | other -> failwith ("simd_widen: unexpected elem ty " ^ other)

(** Declare an LLVM intrinsic into the module preamble on first use. Reuses
    [ctx.unknown_decls] (the same dedup table the general [EApp] arm's
    auto-declare path uses) so a given intrinsic is declared at most once per
    module regardless of how many call sites in the SIMD intercept arm need
    it. Intrinsic declares are per-module (not part of the fixed hand-written
    preamble string), so they never affect the golden-preamble byte test. *)
let ensure_intrinsic_declared ctx ~(name : string) ~(sig_ : string) : unit =
  if not (Hashtbl.mem ctx.unknown_decls name) then begin
    Hashtbl.replace ctx.unknown_decls name ();
    Buffer.add_string ctx.preamble (Printf.sprintf "declare %s\n" sig_)
  end

(** Body of [emit_expr]'s `when decode_simd_call f.v_name <> None` arm.
    Only reached when [decode_simd_call] already said yes. *)
let emit_simd_call
    ~(emit_atom : Llvm_ctx.ctx -> Tir.atom -> string * string)
    (ctx : Llvm_ctx.ctx) (f : Tir.var) (args : Tir.atom list)
  : string * string =
    let (sty, op) = Option.get (decode_simd_call f.Tir.v_name) in
    let v_ty = sty.s_vec in
    let boundary_ty = if sty.s_boundary_float then "double" else "i64" in
    let arg_pairs = List.map (fun a -> emit_atom ctx a) args in
    let vec_arg i =
      let (ty, v) = List.nth arg_pairs i in coerce ctx ty v v_ty in
    let scalar_arg i =
      let (ty, v) = List.nth arg_pairs i in coerce ctx ty v boundary_ty in
    let idx_arg i =
      let (ty, v) = List.nth arg_pairs i in coerce ctx ty v "i64" in
    (* Lane-index bounds check for extract/replace. A bare
       extractelement/insertelement with an out-of-range index is `poison`
       in LLVM — and for insertelement the poison is the WHOLE result
       vector, not one lane — so an OOB dynamic lane index silently
       produced garbage while the interpreter raised a clean error. The
       refinement checker is NOT a backstop: an obligation it cannot prove
       is silently Skipped. So gate on the same icmp+branch+panic pattern
       load/store use (below), against @march_simd_lane_panic (rule:
       0 <= i < lanes; the load/store triple would misdescribe it).

       A STATICALLY in-range literal index — the refinement-typed common
       case, e.g. `Simd.extract_f32x4(v, 0)` after inlining — skips the
       branch entirely and emits exactly what it did before. *)
    let static_lane_in_range (i : int) : bool =
      match List.nth args i with
      | Tir.ALit (March_ast.Ast.LitInt n) -> n >= 0 && n < sty.s_lanes
      | _ -> false
    in
    let check_lane_idx (argi : int) (iv : string) : unit =
      if not (static_lane_in_range argi) then begin
        let ok1 = fresh ctx "vlok" in
        emit ctx (Printf.sprintf "%s = icmp sge i64 %s, 0" ok1 iv);
        let ok2 = fresh ctx "vlok" in
        emit ctx (Printf.sprintf "%s = icmp slt i64 %s, %d" ok2 iv sty.s_lanes);
        let ok = fresh ctx "vlok" in
        emit ctx (Printf.sprintf "%s = and i1 %s, %s" ok ok1 ok2);
        let panic_lbl = fresh_block ctx "vln_panic" in
        let ok_lbl = fresh_block ctx "vln_ok" in
        emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s" ok ok_lbl panic_lbl);
        emit_label ctx panic_lbl;
        emit ctx (Printf.sprintf "call void @march_simd_lane_panic(i64 %s, i64 %d)" iv sty.s_lanes);
        emit_term ctx "unreachable";
        emit_label ctx ok_lbl
      end
    in
    let emit_splat_from_elem (e_v : string) : string =
      (* insertelement lane 0, then a zero-mask shufflevector broadcasts it
         to every lane — used by both `splat` and the shl/shr count. *)
      let ins = fresh ctx "vspl" in
      emit ctx (Printf.sprintf "%s = insertelement %s poison, %s %s, i32 0" ins v_ty sty.s_elem e_v);
      let r = fresh ctx "vspl" in
      let mask = String.concat ", " (List.init sty.s_lanes (fun _ -> "i32 0")) in
      emit ctx (Printf.sprintf "%s = shufflevector %s %s, %s poison, <%d x i32> <%s>"
                  r v_ty ins v_ty sty.s_lanes mask);
      r
    in
    (* Shared by select/any/all/first_set: bitcast a (possibly float) vector
       to its all-integer counterpart, then per-lane sign-bit test against
       zero — matches the interpreter's is_highbit/is_allones mask
       convention (a compare's all-ones/zero lanes always agree with both
       readings; see eval.ml's simd_f32_is_highbit et al.). *)
    let mask_cond (vv : string) : string * string (* int_vty, <L x i1> reg *) =
      let int_vty = simd_int_vec_ty sty in
      let mi =
        if sty.s_boundary_float then begin
          let r = fresh ctx "vbc" in
          emit ctx (Printf.sprintf "%s = bitcast %s %s to %s" r v_ty vv int_vty); r
        end else vv
      in
      let cond = fresh ctx "vmc" in
      emit ctx (Printf.sprintf "%s = icmp slt %s %s, zeroinitializer" cond int_vty mi);
      (int_vty, cond)
    in
    (match op with
     | "splat" ->
       let ev = simd_narrow ctx sty (scalar_arg 0) in
       (v_ty, emit_splat_from_elem ev)
     | "make" ->
       let cur = ref "poison" in
       List.iteri (fun i _ ->
         let ev = simd_narrow ctx sty (scalar_arg i) in
         let r = fresh ctx "vmk" in
         emit ctx (Printf.sprintf "%s = insertelement %s %s, %s %s, i32 %d" r v_ty !cur sty.s_elem ev i);
         cur := r
       ) args;
       (v_ty, !cur)
     | "extract" ->
       let vv = vec_arg 0 and iv = idx_arg 1 in
       check_lane_idx 1 iv;
       let ev = fresh ctx "vext" in
       emit ctx (Printf.sprintf "%s = extractelement %s %s, i64 %s" ev v_ty vv iv);
       (boundary_ty, simd_widen ctx sty ev)
     | "replace" ->
       let vv = vec_arg 0 and iv = idx_arg 1 in
       check_lane_idx 1 iv;
       let ev = simd_narrow ctx sty (scalar_arg 2) in
       let r = fresh ctx "vrep" in
       emit ctx (Printf.sprintf "%s = insertelement %s %s, %s %s, i64 %s" r v_ty vv sty.s_elem ev iv);
       (v_ty, r)
     | "add" | "sub" | "mul" | "div" ->
       let av = vec_arg 0 and bv = vec_arg 1 in
       let opname = match op, sty.s_boundary_float with
         | "add", true -> "fadd" | "add", false -> "add"
         | "sub", true -> "fsub" | "sub", false -> "sub"
         | "mul", true -> "fmul" | "mul", false -> "mul"
         | "div", true -> "fdiv"
         | "div", false -> failwith "simd: int div not in the op grid"
         | _ -> assert false
       in
       let r = fresh ctx "vop" in
       emit ctx (Printf.sprintf "%s = %s %s %s, %s" r opname v_ty av bv);
       (v_ty, r)
     | "min" | "max" ->
       let av = vec_arg 0 and bv = vec_arg 1 in
       let iname = match op, sty.s_boundary_float with
         | "min", true -> "minnum" | "max", true -> "maxnum"
         | "min", false -> "smin" | "max", false -> "smax"
         | _ -> assert false
       in
       let name = Printf.sprintf "llvm.%s.%s" iname (simd_intrinsic_suffix sty) in
       ensure_intrinsic_declared ctx ~name ~sig_:(Printf.sprintf "%s @%s(%s, %s)" v_ty name v_ty v_ty);
       let r = fresh ctx "vmm" in
       emit ctx (Printf.sprintf "%s = call %s @%s(%s %s, %s %s)" r v_ty name v_ty av v_ty bv);
       (v_ty, r)
     | "fma" ->
       (* f32x4: llvm.fma.v4f32 is a SINGLE binary32-fused rounding. The
          interpreter matches it by construction — eval.ml's
          [fma32_single_round] emulates a single-rounded binary32 fma via
          round-to-odd rather than double-rounding a binary64 Float.fma (which
          it used to do, and which diverged in the last ulp; boundary triples
          are pinned by t15 in test/test_stdlib_suite.ml and fuzzed against
          this lowering by test/native/simd_fma_fuzz.march).
          f64x2 needs no emulation: Float.fma IS binary64-fused. *)
       let av = vec_arg 0 and bv = vec_arg 1 and cv = vec_arg 2 in
       let name = Printf.sprintf "llvm.fma.%s" (simd_intrinsic_suffix sty) in
       ensure_intrinsic_declared ctx ~name ~sig_:(Printf.sprintf "%s @%s(%s, %s, %s)" v_ty name v_ty v_ty v_ty);
       let r = fresh ctx "vfma" in
       emit ctx (Printf.sprintf "%s = call %s @%s(%s %s, %s %s, %s %s)" r v_ty name v_ty av v_ty bv v_ty cv);
       (v_ty, r)
     | "sqrt" ->
       let av = vec_arg 0 in
       let name = Printf.sprintf "llvm.sqrt.%s" (simd_intrinsic_suffix sty) in
       ensure_intrinsic_declared ctx ~name ~sig_:(Printf.sprintf "%s @%s(%s)" v_ty name v_ty);
       let r = fresh ctx "vsqrt" in
       emit ctx (Printf.sprintf "%s = call %s @%s(%s %s)" r v_ty name v_ty av);
       (v_ty, r)
     | "shl" | "shr" ->
       let av = vec_arg 0 in
       let cnt_b = scalar_arg 1 in
       let bits = simd_elem_bits sty in
       let cnt_e = simd_narrow ctx sty cnt_b in
       let masked = fresh ctx "vshm" in
       emit ctx (Printf.sprintf "%s = and %s %s, %d" masked sty.s_elem cnt_e (bits - 1));
       let splatv = emit_splat_from_elem masked in
       let opname = if op = "shl" then "shl" else "ashr" in
       let r = fresh ctx "vsh" in
       emit ctx (Printf.sprintf "%s = %s %s %s, %s" r opname v_ty av splatv);
       (v_ty, r)
     | "eq" | "lt" | "gt" ->
       let av = vec_arg 0 and bv = vec_arg 1 in
       let bits = simd_elem_bits sty in
       let cmp = fresh ctx "vcmp" in
       (if sty.s_boundary_float then
          let pred = match op with "eq" -> "oeq" | "lt" -> "olt" | "gt" -> "ogt" | _ -> assert false in
          emit ctx (Printf.sprintf "%s = fcmp %s %s %s, %s" cmp pred v_ty av bv)
        else
          let pred = match op, sty.s_elem with
            | "eq", _   -> "eq"
            | "lt", "i8" -> "ult" | "gt", "i8" -> "ugt"
            | "lt", _   -> "slt" | "gt", _ -> "sgt"
            | _ -> assert false
          in
          emit ctx (Printf.sprintf "%s = icmp %s %s %s, %s" cmp pred v_ty av bv));
       let int_vty = Printf.sprintf "<%d x i%d>" sty.s_lanes bits in
       let sext_r = fresh ctx "vcmp" in
       emit ctx (Printf.sprintf "%s = sext <%d x i1> %s to %s" sext_r sty.s_lanes cmp int_vty);
       let r =
         if sty.s_boundary_float then begin
           let r = fresh ctx "vcmp" in
           emit ctx (Printf.sprintf "%s = bitcast %s %s to %s" r int_vty sext_r v_ty); r
         end else sext_r
       in
       (v_ty, r)
     | "and" | "or" | "xor" ->
       let av = vec_arg 0 and bv = vec_arg 1 in
       let opname = op in
       if sty.s_boundary_float then begin
         let int_vty = simd_int_vec_ty sty in
         let a_i = fresh ctx "vbc" in
         emit ctx (Printf.sprintf "%s = bitcast %s %s to %s" a_i v_ty av int_vty);
         let b_i = fresh ctx "vbc" in
         emit ctx (Printf.sprintf "%s = bitcast %s %s to %s" b_i v_ty bv int_vty);
         let r_i = fresh ctx "vbop" in
         emit ctx (Printf.sprintf "%s = %s %s %s, %s" r_i opname int_vty a_i b_i);
         let r = fresh ctx "vbc" in
         emit ctx (Printf.sprintf "%s = bitcast %s %s to %s" r int_vty r_i v_ty);
         (v_ty, r)
       end else begin
         let r = fresh ctx "vbop" in
         emit ctx (Printf.sprintf "%s = %s %s %s, %s" r opname v_ty av bv);
         (v_ty, r)
       end
     | "not" ->
       let av = vec_arg 0 in
       if sty.s_boundary_float then begin
         let int_vty = simd_int_vec_ty sty in
         let int_elem = match sty.s_elem with "float" -> "i32" | _ -> "i64" in
         let a_i = fresh ctx "vbc" in
         emit ctx (Printf.sprintf "%s = bitcast %s %s to %s" a_i v_ty av int_vty);
         let allones = String.concat ", " (List.init sty.s_lanes (fun _ -> Printf.sprintf "%s -1" int_elem)) in
         let r_i = fresh ctx "vnot" in
         emit ctx (Printf.sprintf "%s = xor %s %s, <%s>" r_i int_vty a_i allones);
         let r = fresh ctx "vbc" in
         emit ctx (Printf.sprintf "%s = bitcast %s %s to %s" r int_vty r_i v_ty);
         (v_ty, r)
       end else begin
         let allones = String.concat ", " (List.init sty.s_lanes (fun _ -> Printf.sprintf "%s -1" sty.s_elem)) in
         let r = fresh ctx "vnot" in
         emit ctx (Printf.sprintf "%s = xor %s %s, <%s>" r v_ty av allones);
         (v_ty, r)
       end
     | "select" ->
       let mv = vec_arg 0 and av = vec_arg 1 and bv = vec_arg 2 in
       let (_, cond) = mask_cond mv in
       let r = fresh ctx "vsel" in
       emit ctx (Printf.sprintf "%s = select <%d x i1> %s, %s %s, %s %s" r sty.s_lanes cond v_ty av v_ty bv);
       (v_ty, r)
     | "any" | "all" ->
       let av = vec_arg 0 in
       let (_, cond) = mask_cond av in
       let packed = fresh ctx "vaa" in
       emit ctx (Printf.sprintf "%s = bitcast <%d x i1> %s to i%d" packed sty.s_lanes cond sty.s_lanes);
       let r = fresh ctx "vaa" in
       (if op = "any" then
          emit ctx (Printf.sprintf "%s = icmp ne i%d %s, 0" r sty.s_lanes packed)
        else
          emit ctx (Printf.sprintf "%s = icmp eq i%d %s, -1" r sty.s_lanes packed));
       ("i64", coerce ctx "i1" r "i64")
     | "first_set" ->
       let av = vec_arg 0 in
       let (_, cond) = mask_cond av in
       let packed = fresh ctx "vfs" in
       emit ctx (Printf.sprintf "%s = bitcast <%d x i1> %s to i%d" packed sty.s_lanes cond sty.s_lanes);
       let z64 = fresh ctx "vfs" in
       emit ctx (Printf.sprintf "%s = zext i%d %s to i64" z64 sty.s_lanes packed);
       ensure_intrinsic_declared ctx ~name:"llvm.cttz.i64" ~sig_:"i64 @llvm.cttz.i64(i64, i1)";
       let ctz = fresh ctx "vfs" in
       emit ctx (Printf.sprintf "%s = call i64 @llvm.cttz.i64(i64 %s, i1 false)" ctz z64);
       let isz = fresh ctx "vfs" in
       emit ctx (Printf.sprintf "%s = icmp eq i64 %s, 0" isz z64);
       let r = fresh ctx "vfs" in
       emit ctx (Printf.sprintf "%s = select i1 %s, i64 -1, i64 %s" r isz ctz);
       ("i64", r)
     | "sum" ->
       let av = vec_arg 0 in
       if sty.s_boundary_float then begin
         let ext_ty = Printf.sprintf "<%d x double>" sty.s_lanes in
         let ext =
           if sty.s_elem = "double" then av
           else begin
             let r = fresh ctx "vsum" in
             emit ctx (Printf.sprintf "%s = fpext %s %s to %s" r v_ty av ext_ty); r
           end
         in
         (* Ordered (no reassoc flags) reduce.fadd WITH a start operand is
            defined by LangRef as sequential left-to-right — matches
            eval.ml's simd_hfold-free `Array.fold_left (+.) 0.0` for sum. *)
         let name = Printf.sprintf "llvm.vector.reduce.fadd.v%df64" sty.s_lanes in
         ensure_intrinsic_declared ctx ~name ~sig_:(Printf.sprintf "double @%s(double, %s)" name ext_ty);
         let r = fresh ctx "vsum" in
         emit ctx (Printf.sprintf "%s = call double @%s(double 0.0, %s %s)" r name ext_ty ext);
         ("double", r)
       end else begin
         let ext_ty = Printf.sprintf "<%d x i64>" sty.s_lanes in
         let ext =
           if sty.s_elem = "i64" then av
           else begin
             let r = fresh ctx "vsum" in
             emit ctx (Printf.sprintf "%s = sext %s %s to %s" r v_ty av ext_ty); r
           end
         in
         let name = Printf.sprintf "llvm.vector.reduce.add.v%di64" sty.s_lanes in
         ensure_intrinsic_declared ctx ~name ~sig_:(Printf.sprintf "i64 @%s(%s)" name ext_ty);
         let r = fresh ctx "vsum" in
         emit ctx (Printf.sprintf "%s = call i64 @%s(%s %s)" r name ext_ty ext);
         ("i64", r)
       end
     | "hmin" | "hmax" ->
       let av = vec_arg 0 in
       let lane i =
         let r = fresh ctx "vhf" in
         emit ctx (Printf.sprintf "%s = extractelement %s %s, i64 %d" r v_ty av i); r
       in
       let iname = match op, sty.s_boundary_float with
         | "hmin", true -> "minnum" | "hmax", true -> "maxnum"
         | "hmin", false -> "smin" | "hmax", false -> "smax"
         | _ -> assert false
       in
       let scalar_suffix = match sty.s_elem with
         | "float" -> "f32" | "double" -> "f64" | "i32" -> "i32" | "i64" -> "i64"
         | other -> failwith ("simd hmin/hmax: unexpected elem ty " ^ other)
       in
       let name = Printf.sprintf "llvm.%s.%s" iname scalar_suffix in
       ensure_intrinsic_declared ctx ~name ~sig_:(Printf.sprintf "%s @%s(%s, %s)" sty.s_elem name sty.s_elem sty.s_elem);
       let acc = ref (lane 0) in
       for i = 1 to sty.s_lanes - 1 do
         let li = lane i in
         let r = fresh ctx "vhf" in
         emit ctx (Printf.sprintf "%s = call %s @%s(%s %s, %s %s)" r sty.s_elem name sty.s_elem !acc sty.s_elem li);
         acc := r
       done;
       (boundary_ty, simd_widen ctx sty !acc)
     | "load" ->
       (* Bounds check (0 <= i && i + lanes <= len), matching
          [simd_bounds_check] in eval.ml, then a plain GEP+load at
          arr+32+i*elem_size (NATIVE_ARR_HDR=32, #define'd in
          march_runtime.h). Every `native_<w>_arr_length` used here is
          unconditionally declared in the native preamble
          (llvm_builtins.ml's [native_net_io_items]), same as every other
          NativeArray builtin call site. *)
       let (arr_ty0, arr_v0) = List.nth arg_pairs 0 in
       let arr_v = coerce ctx arr_ty0 arr_v0 "ptr" in
       let iv = idx_arg 1 in
       let elem_size = simd_elem_bits sty / 8 in
       let len_fn = sty.s_arr_prefix ^ "_length" in
       let len = fresh ctx "vlen" in
       emit ctx (Printf.sprintf "%s = call i64 @%s(ptr %s)" len len_fn arr_v);
       let endi = fresh ctx "vend" in
       emit ctx (Printf.sprintf "%s = add i64 %s, %d" endi iv sty.s_lanes);
       let ok1 = fresh ctx "vok" in
       emit ctx (Printf.sprintf "%s = icmp sle i64 %s, %s" ok1 endi len);
       let ok2 = fresh ctx "vok" in
       emit ctx (Printf.sprintf "%s = icmp sge i64 %s, 0" ok2 iv);
       let ok = fresh ctx "vok" in
       emit ctx (Printf.sprintf "%s = and i1 %s, %s" ok ok1 ok2);
       let panic_lbl = fresh_block ctx "vld_panic" in
       let ok_lbl = fresh_block ctx "vld_ok" in
       emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s" ok ok_lbl panic_lbl);
       emit_label ctx panic_lbl;
       emit ctx (Printf.sprintf "call void @march_simd_bounds_panic(i64 %s, i64 %d, i64 %s)" iv sty.s_lanes len);
       emit_term ctx "unreachable";
       emit_label ctx ok_lbl;
       let byte_off = fresh ctx "voff" in
       emit ctx (Printf.sprintf "%s = mul i64 %s, %d" byte_off iv elem_size);
       let base = fresh ctx "vbase" in
       emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 32" base arr_v);
       let elemp = fresh ctx "velem" in
       emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 %s" elemp base byte_off);
       let r = fresh ctx "vld" in
       emit ctx (Printf.sprintf "%s = load %s, ptr %s, align %d" r v_ty elemp elem_size);
       (v_ty, r)
     | "store" ->
       (* Same bounds check as `load`, then the FBIP contract exactly as
          `native_f32_arr_set` (march_runtime.c): rc==1 -> in-place vector
          store, return the same array; rc>1 -> alloc a fresh array,
          memcpy the whole payload, vector-store into the copy, decrc the
          original, return the copy. The rc==1 test mirrors EReuse's
          "load atomic i64 ... monotonic" + `icmp eq i64 %rc, 1` pattern
          (see the EAlloc/EReuse FBIP arm above, ~L4496-4499). *)
       let (arr_ty0, arr_v0) = List.nth arg_pairs 0 in
       let arr_v = coerce ctx arr_ty0 arr_v0 "ptr" in
       let iv = idx_arg 1 in
       let vv = vec_arg 2 in
       let elem_size = simd_elem_bits sty / 8 in
       let len_fn = sty.s_arr_prefix ^ "_length" in
       let alloc_fn = sty.s_arr_prefix ^ "_alloc_raw" in
       let len = fresh ctx "vlen" in
       emit ctx (Printf.sprintf "%s = call i64 @%s(ptr %s)" len len_fn arr_v);
       let endi = fresh ctx "vend" in
       emit ctx (Printf.sprintf "%s = add i64 %s, %d" endi iv sty.s_lanes);
       let ok1 = fresh ctx "vok" in
       emit ctx (Printf.sprintf "%s = icmp sle i64 %s, %s" ok1 endi len);
       let ok2 = fresh ctx "vok" in
       emit ctx (Printf.sprintf "%s = icmp sge i64 %s, 0" ok2 iv);
       let ok = fresh ctx "vok" in
       emit ctx (Printf.sprintf "%s = and i1 %s, %s" ok ok1 ok2);
       let panic_lbl = fresh_block ctx "vst_panic" in
       let ok_lbl = fresh_block ctx "vst_ok" in
       emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s" ok ok_lbl panic_lbl);
       emit_label ctx panic_lbl;
       emit ctx (Printf.sprintf "call void @march_simd_bounds_panic(i64 %s, i64 %d, i64 %s)" iv sty.s_lanes len);
       emit_term ctx "unreachable";
       emit_label ctx ok_lbl;
       let byte_off = fresh ctx "voff" in
       emit ctx (Printf.sprintf "%s = mul i64 %s, %d" byte_off iv elem_size);
       (* rc==1 fast path — same FBIP contract as native_f32_arr_set, which
          gates on `IS_HEAP_PTR(arr) && rc == 1`. `arr_v` statically can only
          ever be a genuine heap array (never a tagged scalar — its March
          type is NativeF32Arr/etc), but the check is reproduced verbatim
          (IS_HEAP_PTR = untagged, >= one page, sign bit clear) rather than
          assumed, matching the C helper's own defensiveness exactly. *)
       let arr_i = fresh ctx "varri" in
       emit ctx (Printf.sprintf "%s = ptrtoint ptr %s to i64" arr_i arr_v);
       let tagbit = fresh ctx "vhtag" in
       emit ctx (Printf.sprintf "%s = and i64 %s, 1" tagbit arr_i);
       let not_tagged = fresh ctx "vhnt" in
       emit ctx (Printf.sprintf "%s = icmp eq i64 %s, 0" not_tagged tagbit);
       let above_page = fresh ctx "vhpg" in
       emit ctx (Printf.sprintf "%s = icmp uge i64 %s, 4096" above_page arr_i);
       let positive = fresh ctx "vhpos" in
       emit ctx (Printf.sprintf "%s = icmp sgt i64 %s, 0" positive arr_i);
       let heap1 = fresh ctx "vheap" in
       emit ctx (Printf.sprintf "%s = and i1 %s, %s" heap1 not_tagged above_page);
       let is_heap = fresh ctx "vheap" in
       emit ctx (Printf.sprintf "%s = and i1 %s, %s" is_heap heap1 positive);
       let rc = fresh ctx "vrc" in
       emit ctx (Printf.sprintf "%s = load atomic i64, ptr %s monotonic, align 8" rc arr_v);
       let rc_uniq = fresh ctx "vrcu" in
       emit ctx (Printf.sprintf "%s = icmp eq i64 %s, 1" rc_uniq rc);
       let uniq = fresh ctx "vuniq" in
       emit ctx (Printf.sprintf "%s = and i1 %s, %s" uniq is_heap rc_uniq);
       let reuse_lbl = fresh_block ctx "vst_reuse" in
       let fresh_lbl = fresh_block ctx "vst_fresh" in
       let merge_lbl = fresh_block ctx "vst_merge" in
       emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s" uniq reuse_lbl fresh_lbl);
       emit_label ctx reuse_lbl;
       let base0 = fresh ctx "vbase" in
       emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 32" base0 arr_v);
       let elemp0 = fresh ctx "velem" in
       emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 %s" elemp0 base0 byte_off);
       emit ctx (Printf.sprintf "store %s %s, ptr %s, align %d" v_ty vv elemp0 elem_size);
       emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl);
       emit_label ctx fresh_lbl;
       let newp = fresh ctx "vnew" in
       emit ctx (Printf.sprintf "%s = call ptr @%s(i64 %s)" newp alloc_fn len);
       let src = fresh ctx "vsrc" in
       emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 32" src arr_v);
       let dst = fresh ctx "vdst" in
       emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 32" dst newp);
       let bytelen = fresh ctx "vbytelen" in
       emit ctx (Printf.sprintf "%s = mul i64 %s, %d" bytelen len elem_size);
       ensure_intrinsic_declared ctx ~name:"llvm.memcpy.p0.p0.i64"
         ~sig_:"void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)";
       emit ctx (Printf.sprintf "call void @llvm.memcpy.p0.p0.i64(ptr %s, ptr %s, i64 %s, i1 false)" dst src bytelen);
       let elemp1 = fresh ctx "velem" in
       emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 %s" elemp1 dst byte_off);
       emit ctx (Printf.sprintf "store %s %s, ptr %s, align %d" v_ty vv elemp1 elem_size);
       emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" arr_v);
       emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl);
       emit_label ctx merge_lbl;
       let result = fresh ctx "vst_r" in
       emit ctx (Printf.sprintf "%s = phi ptr [ %s, %%%s ], [ %s, %%%s ]" result arr_v reuse_lbl newp fresh_lbl);
       ("ptr", result)
     | other -> failwith ("simd_intercept: unrecognized op " ^ other))
