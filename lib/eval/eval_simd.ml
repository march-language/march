(** Simd 128-bit vector ops and NativeArray narrow-width (f32/i32/u8)
    helpers.  Extracted verbatim from eval.ml:3917-4069 — no behavior
    change.  See specs/plans/2026-08-19-compiler-file-decomposition.md *)

open Eval_prim

(* ------------------------------------------------------------------ *)
(* NativeArray narrow-width helpers (f32/i32/u8) — P10 narrow types.
   Boundary rule: integer stores wrap mod 2^w two's-complement; float
   stores round to nearest-even binary32.  Never trap. *)
(* ------------------------------------------------------------------ *)

let f32_round (v : float) : float = Int32.float_of_bits (Int32.bits_of_float v)

(* Single-rounded binary32 fused multiply-add, emulated in binary64 via the
   round-to-odd technique (Boldo-Melquiond). [a], [b], [c] must already be
   binary32-representable (every f32 lane store goes through [f32_round], so
   the SIMD f32x4 lanes are); the result is bit-identical to hardware [fmaf] /
   [llvm.fma.f32], i.e. RN32(a*b + c) with ONE rounding.

   Why not [f32_round (Float.fma a b c)]: that is a binary64 fused multiply-add
   NARROWED to binary32 -- two roundings -- and it really does differ in the
   last ulp. Witness: a = 24929, b = 673 (a*b = 2^24+1 exactly, a binary32
   midpoint), c = 1e-30. The exact value sits just above the midpoint, so one
   rounding gives 2^24+2, but the binary64 intermediate swallows c, lands back
   on the midpoint, and ties-to-even then gives 2^24. Random binary32 triples
   diverge about 1 in 20M.

   How this works: [a *. b] is EXACT in binary64 (24+24 = 48 <= 53 significand
   bits), so the only rounding is the final add. TwoSum recovers that add's
   exact residual; when the binary64 sum is inexact and has an even significand,
   stepping one ulp toward the residual makes it odd, which is round-to-odd of
   the exact value -- and rounding an odd binary64 to nearest binary32 is
   equivalent to rounding the exact value once (53 >= 24+2).

   Oracle: llvm.fma.v4f32 on the compiled path. Validated against hardware
   [fmaf] over >100M binary32 triples (full range, subnormal operands with 3.8M
   subnormal results, overflow zone, and 20M midpoint-product constructions) with
   zero mismatches; the compiled-vs-interpreted fuzz witness lives in
   test/native/simd_fma_fuzz.march. *)
let fma32_single_round (a : float) (b : float) (c : float) : float =
  let p = a *. b in                                   (* exact *)
  let s = p +. c in
  if Float.is_nan s || s = Float.infinity || s = Float.neg_infinity then
    f32_round s
  else begin
    let bv = s -. p in
    let err = (p -. (s -. bv)) +. (c -. bv) in        (* TwoSum residual *)
    let s' =
      if err = 0.0 then s                             (* the add was exact *)
      else if s = 0.0 then err   (* unreachable here: p+c cannot underflow to
                                    zero for binary32 operands -- kept so the
                                    helper is total if it is ever reused *)
      else
        let bits = Int64.bits_of_float s in
        if Int64.logand bits 1L = 0L then
          (* even significand: step one ulp toward the exact value (increasing
             |s| when the residual has the same sign as s), giving round-to-odd *)
          let away_from_zero = (err > 0.0) = (s >= 0.0) in
          Int64.float_of_bits
            (if away_from_zero then Int64.add bits 1L else Int64.sub bits 1L)
        else s
    in
    f32_round s'
  end

let i32_wrap (v : int) : int = Int32.to_int (Int32.of_int v)
let u8_wrap (v : int) : int = v land 0xff

(* ------------------------------------------------------------------ *)
(* Simd — explicit 128-bit SIMD vector types (F32x4/F64x2/I32x4/I64x2/U8x16).
   Fixed-width lane vectors; the interpreter emulates every op bit-exactly
   against the eventual LLVM lowering (Task 2 of
   docs/superpowers/plans/2026-08-10-simd-vector-types.md). f32/i32/u8 lane
   narrowing reuses f32_round/i32_wrap/u8_wrap above; f64x2 lanes are native
   double (no narrowing). i64x2 lanes are stored as a true [int64 array] --
   OCaml's native [int] is only 63-bit, so 64-bit two's-complement wrap must
   go through the [Int64] module, not native [+]/[-]/[*]. KNOWN PARITY EDGE:
   [extract_i64x2]/[sum_i64x2]/[hmin_i64x2]/[hmax_i64x2] narrow the int64
   lane back to March's interpreter [VInt] (native 63-bit) via
   [Int64.to_int], which loses the top bit outside +/-2^62 -- tests for
   i64x2 stay within that range by construction. *)
(* ------------------------------------------------------------------ *)

let simd_minnum_f (a : float) (b : float) : float =
  if a <> a then b else if b <> b then a else Stdlib.min a b
let simd_maxnum_f (a : float) (b : float) : float =
  if a <> a then b else if b <> b then a else Stdlib.max a b

let simd_f32_allones : float = Int32.float_of_bits 0xFFFFFFFFl
let simd_f32_zero : float = 0.0
let simd_f64_allones : float = Int64.float_of_bits 0xFFFFFFFFFFFFFFFFL
let simd_f64_zero : float = 0.0

(* Mask predicate — HIGH BIT, uniformly across select/any/all/first_set and
   across both backends. See [simd_select]'s doc comment below. *)
let simd_f32_is_highbit (v : float) : bool = Int32.bits_of_float v < 0l
let simd_f64_is_highbit (v : float) : bool = Int64.bits_of_float v < 0L

let simd_f32_and (a : float) (b : float) : float =
  Int32.float_of_bits (Int32.logand (Int32.bits_of_float a) (Int32.bits_of_float b))
let simd_f32_or (a : float) (b : float) : float =
  Int32.float_of_bits (Int32.logor (Int32.bits_of_float a) (Int32.bits_of_float b))
let simd_f32_xor (a : float) (b : float) : float =
  Int32.float_of_bits (Int32.logxor (Int32.bits_of_float a) (Int32.bits_of_float b))
let simd_f32_not (a : float) : float =
  Int32.float_of_bits (Int32.lognot (Int32.bits_of_float a))

let simd_f64_and (a : float) (b : float) : float =
  Int64.float_of_bits (Int64.logand (Int64.bits_of_float a) (Int64.bits_of_float b))
let simd_f64_or (a : float) (b : float) : float =
  Int64.float_of_bits (Int64.logor (Int64.bits_of_float a) (Int64.bits_of_float b))
let simd_f64_xor (a : float) (b : float) : float =
  Int64.float_of_bits (Int64.logxor (Int64.bits_of_float a) (Int64.bits_of_float b))
let simd_f64_not (a : float) : float =
  Int64.float_of_bits (Int64.lognot (Int64.bits_of_float a))

let simd_i32_is_highbit (v : int) : bool = v < 0
let simd_i64_is_highbit (v : int64) : bool = Int64.compare v 0L < 0
let simd_u8_is_highbit (v : int) : bool = v >= 128

(** Generic mask-driven ops, shared across all five element types
    (['a] is [float] for f32/f64 lanes, [int] for i32/u8 lanes, [int64] for
    i64 lanes). *)
let simd_first_set (is_highbit : 'a -> bool) (arr : 'a array) : int =
  let n = Array.length arr in
  let rec go i = if i >= n then -1 else if is_highbit arr.(i) then i else go (i + 1) in
  go 0
let simd_any (is_highbit : 'a -> bool) (arr : 'a array) : bool = Array.exists is_highbit arr
let simd_all (is_highbit : 'a -> bool) (arr : 'a array) : bool = Array.for_all is_highbit arr
(* [select] uses the SAME high-bit predicate as [any]/[all]/[first_set],
    which is also what the compiled path does (llvm_emit.ml's [mask_cond]:
    bitcast to the integer vector, then `icmp slt ... zeroinitializer`) and
    what every SIMD ISA's blend instruction does. A canonical mask — the
    all-ones/all-zero lanes produced by [eq]/[lt]/[gt] — reads identically
    under either convention; a hand-rolled NON-canonical mask lane (e.g.
    0xFFFFFFFE) only agrees if both sides test the high bit, so interpreted
    and compiled would diverge if this tested all-ones. Pinned by the
    non-canonical-mask leg of test/native/simd_vector_core.march. *)
let simd_select (is_highbit : 'a -> bool) (mask : 'a array) (a : 'a array) (b : 'a array) : 'a array =
  Array.init (Array.length mask) (fun i -> if is_highbit mask.(i) then a.(i) else b.(i))

(** Sequential (ordered) horizontal fold over lanes 1..n-1, seeded with
    lane 0 -- matches the compiled side's ordered [llvm.vector.reduce.*]
    lowering (Task 2), never a tree/associative reduction. *)
let simd_hfold (op : 'a -> 'a -> 'a) (arr : 'a array) : 'a =
  let n = Array.length arr in
  let acc = ref arr.(0) in
  for i = 1 to n - 1 do acc := op !acc arr.(i) done;
  !acc

(** Bounds rule (Global Constraints): [0 <= i && i + lanes <= len].
    Message text mirrors the compiled runtime's
    [march_simd_bounds_panic] (Task 2/3) minus the "march: runtime error:"
    process-exit prefix the interpreter doesn't use elsewhere. *)
let simd_bounds_check (op : string) (i : int) (lanes : int) (len : int) : unit =
  if i < 0 || i + lanes > len then
    eval_error "%s: simd load/store out of bounds (index %d, lanes %d, length %d)" op i lanes len

