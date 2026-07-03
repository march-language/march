(** March TIR → textual LLVM IR emission.

    Object layout (all heap values are opaque [ptr]):
      offset  0 : i64   rc  (reference count, initialized to 1)
      offset  8 : i32   tag (constructor tag, 0-based index in variant)
      offset 12 : i32   pad (alignment padding)
      offset 16 + i*8 : field[i] (i64 for Int/Bool/Unit, double for Float, ptr for others)
    Allocation size = 16 + arity * 8 bytes.

    All functions use alloca+store+load for let-bound variables; LLVM's
    mem2reg + SROA promotes them to registers.

    ECase branches use a per-case alloca slot for the result, typed ptr,
    with narrowing conversions for scalar result types.

    The March function [main] is emitted as [@march_main].  A C-ABI
    [@main] wrapper is appended that calls @march_main and returns 0.

    Arithmetic / comparison builtins are recognized by name and lowered
    to native LLVM instructions. *)

(** Compilation target. *)
type target_config =
  | Native          (** Host-native binary (arm64-apple-macosx, x86_64-linux, etc.) *)
  | Wasm64Wasi      (** wasm64-wasi — 8-byte pointers, WASI preview *)
  | Wasm32Wasi      (** wasm32-wasi — 4-byte pointers, WASI preview *)
  | Wasm32Unknown   (** wasm32-unknown-unknown — browser, no WASI *)
  | Js              (** ES module output — no LLVM, no clang *)

let is_wasm_target = function
  | Native | Js -> false
  | Wasm64Wasi | Wasm32Wasi | Wasm32Unknown -> true

let is_wasm32 = function
  | Wasm32Wasi | Wasm32Unknown -> true
  | _ -> false

external get_native_triple : unit -> string = "march_tir_native_triple"
let native_triple = lazy (get_native_triple ())

let target_triple = function
  | Native          -> Lazy.force native_triple
  | Wasm64Wasi      -> "wasm64-wasi"
  | Wasm32Wasi      -> "wasm32-wasi"
  | Wasm32Unknown   -> "wasm32-unknown-unknown"
  | Js              -> "js"

(** Pointer size in bytes for the target. *)
let target_ptr_size = function
  | Native | Wasm64Wasi | Js -> 8
  | Wasm32Wasi | Wasm32Unknown -> 4

(** LLVM pointer type name for the target. *)
let target_ptr_ty = function
  | Native | Wasm64Wasi | Js -> "ptr"
  | Wasm32Wasi | Wasm32Unknown -> "ptr"

(** LLVM integer type matching pointer width. *)
let target_int_ty = function
  | Native | Wasm64Wasi | Js -> "i64"
  | Wasm32Wasi | Wasm32Unknown -> "i32"

(* Type defs live on ctx (ctx.type_defs) — threaded per emission context so
   REPL/JIT fragments never see stale representations (B12). *)

(* ── Repr-consistency audit (MARCH_REPR_AUDIT=1) ─────────────────────────
   [repr_audit_on] / [_repr_audit] / [repr_audit_record] / [repr_audit_report]
   moved to [Llvm_ctx] (Wave 3 Task 5, chunk 2): every emit-arm consumer
   ([ensure_adt_eq_fn] now in [Llvm_eq], the EAlloc/EReuse arms now calling
   into [Llvm_data], [emit_case] now in [Llvm_case], plus the arms that stay
   here) records into the same shared table, so it lives at the common base
   all four modules already depend on.  Re-exported bare here — [emit_module]
   below resets the table per module and prints the report. *)
let repr_audit_record = Llvm_ctx.repr_audit_record
let repr_audit_report = Llvm_ctx.repr_audit_report
let _repr_audit = Llvm_ctx._repr_audit

(* ── Context ─────────────────────────────────────────────────────────── *)
(* ctx record, make_ctx, fresh/fresh_block/emit/emit_label/emit_term,
   llvm_name, atom-hash interning (fnv1a_64/atom_hash), llvm_ty/
   llvm_param_ty, alloc_size, coerce, and string-literal interning
   (llvm_escape_string/intern_string) moved to [Llvm_ctx] (Wave 3 Task 3,
   chunk 2) — re-exported here unqualified since every emit arm below (and
   test/test_codegen.ml, which reaches them only through emit_module and the
   emit_repl_ family) uses these names bare.  Same re-export pattern as
   [Perceus]'s Wave 3 Task 5 split (Perceus_liveness / _elide / _fbip /
   _scrut). The two audited tag/untag helpers ([Llvm_ctx.emit_tag_scalar] /
   [emit_untag_scalar] / [emit_untag_known_scalar]) are also re-exported
   here; the ~9-site consolidation below calls them by their bare names. *)

type ctor_entry = Llvm_ctx.ctor_entry = { ce_tag : int; ce_fields : Tir.ty list }
type ctx = Llvm_ctx.ctx = {
  buf       : Buffer.t;
  preamble  : Buffer.t;
  mutable ctr     : int;
  mutable blk     : int;
  mutable str_ctr : int;
  ctor_info : (string, ctor_entry) Hashtbl.t;
  top_fns   : (string, bool) Hashtbl.t;
  top_fn_ret_ty : (string, Tir.ty) Hashtbl.t;
  top_fn_nparams : (string, int) Hashtbl.t;
  zero_arg_fns  : (string, bool) Hashtbl.t;
  field_map : (string, (string * Tir.ty) list) Hashtbl.t;
  mutable ret_ty  : Tir.ty;
  fast_math : bool;
  pmap_threshold : int;
  type_defs : Tir.type_def list;
  poly_ctors  : (string * string, Tir.ty list) Hashtbl.t;
  type_params : (string, string list) Hashtbl.t;
  var_slot  : (string, string) Hashtbl.t;
  local_names : (string, int) Hashtbl.t;
  emitted_wraps : (string, unit) Hashtbl.t;
  extra_fns : Buffer.t;
  emitted_eq_fns : (string, unit) Hashtbl.t;
  extern_map : (string, string) Hashtbl.t;
  blocking_externs : (string, unit) Hashtbl.t;
  raises_externs : (string, unit) Hashtbl.t;
  unknown_decls : (string, unit) Hashtbl.t;
  unqualified_fns : (string, string) Hashtbl.t;
  hr_config : Hot_reload.config option;
  hr_names  : Hot_reload.Name_table.t;
  mutable hr_cur_module : string;
  var_llvm_ty : (string, string) Hashtbl.t;
  mutable tco_fn_name   : string option;
  mutable cur_emit_fn   : string;
  mutable tco_loop_label : string;
  mutable tco_param_info : (string * string * string) list;
  mutable tco_stack_save : string;
  mutable tco_in_tail   : bool;
  mutable mutual_tco_group      : string list;
  mutable mutual_tco_tag_slot   : string;
  mutable mutual_tco_loop_label : string;
  mutable mutual_tco_fn_params  : (string * (string * string * string) list) list;
  mutable mutual_tco_fn_tags    : (string * int) list;
  mutable mutual_tco_stack_save : string;
  repl : bool;
  mutable shape_meta : bool;
  rec_shape_globals : (string, string * string) Hashtbl.t;
  remote_impl_hashes : (string, string) Hashtbl.t;
  remote_sig_hashes  : (string, string) Hashtbl.t;
  compile_so : bool;
}

let make_ctx = Llvm_ctx.make_ctx
let module_of_name = Llvm_ctx.module_of_name
let fresh = Llvm_ctx.fresh
let fresh_block = Llvm_ctx.fresh_block
let emit = Llvm_ctx.emit
let emit_label = Llvm_ctx.emit_label
let emit_term = Llvm_ctx.emit_term
let llvm_name = Llvm_ctx.llvm_name
let fnv1a_64 = Llvm_ctx.fnv1a_64
let atom_hash = Llvm_ctx.atom_hash
let llvm_ty = Llvm_ctx.llvm_ty
let llvm_param_ty = Llvm_ctx.llvm_param_ty
let alloc_size = Llvm_ctx.alloc_size
let emit_tag_scalar = Llvm_ctx.emit_tag_scalar
let emit_untag_scalar = Llvm_ctx.emit_untag_scalar
let emit_untag_known_scalar = Llvm_ctx.emit_untag_known_scalar
let coerce = Llvm_ctx.coerce
let llvm_escape_string = Llvm_ctx.llvm_escape_string
let intern_string = Llvm_ctx.intern_string

let llvm_ret_ty : Tir.ty -> string = function
  | Tir.TUnit -> "void"
  | t -> llvm_ty t

(* For a `raises` extern declared `: Result(T, E)`, the C binding returns the
   bare Ok payload of type T (not a march_value Result).  This is T. *)
let ok_payload_ty : Tir.ty -> Tir.ty = function
  | Tir.TCon ("Result", [t_ok; _]) -> t_ok
  | t -> t

(** Return type of a function variable's type. *)
let fn_ret_tir (ty : Tir.ty) : Tir.ty =
  match ty with
  | Tir.TFn (_, ret) -> ret
  | other -> other

(** True for defunctionalized closure apply wrappers ("<fn>$apply$<uid>").

    These are dispatched indirectly through a closure struct whose fn-pointer
    is type-erased, so all wrappers for a given source `(a) -> b` MUST share one
    calling convention.  We pin that convention to the generic ptr ABI:

      - The wrapper RETURNS its result in the ptr slot (scalar values tagged via
        the i64->ptr coercion; heap pointers pass through unchanged).
      - Every call site reads the result as ptr and lets the consumer untag
        through the usual ptr->scalar `coerce`.

    Without this, inference gives a concrete-return lambda (e.g. `fn x -> x > 0`)
    an `i64` ABI but leaves a polymorphic-return lambda (e.g. `fn r -> r.active`,
    a dynamic field read that yields a *tagged* generic value) a `ptr` ABI.
    Stored in the same list and called through one variable typed `(_) -> Bool`,
    the dispatch picks `call i64` for both and reinterprets the polymorphic
    wrapper's tagged `3`/`1` as a raw scalar — inverting Bool field predicates.
    Void wrappers keep the `void` ABI (no value to carry).  Defined in
    [Tir_names] (Wave 3 Task 1 — was a byte-identical duplicate of
    [Perceus.is_apply_fn] before this move; see [Tir_names.is_apply_fn] for
    the diff verdict). *)
let is_apply_fn = Tir_names.is_apply_fn

(** Emit a `$clo_wrap` trampoline that forwards to [fn_name] and returns the
    result in the generic ptr ABI shared by all closure dispatch (see
    [is_apply_fn]).  A closure struct's fn-pointer is type-erased, so a thin
    closure wrapping a named function MUST present the same ptr ABI as a lambda
    apply wrapper — otherwise the ECallPtr dispatch (which reads ptr) would
    misread a concrete `i64`/`double` return (e.g. a Bool-returning predicate
    passed to List.filter, read back tagged and inverted).  Scalars are tagged
    `(n<<1)|1` and floats bitcast into the ptr slot; the consumer untags via the
    usual ptr->scalar coerce.  void wrappers carry no value (ret ptr null). *)
let clo_wrap_define wrap_name decl_str target_ret fn_name call_args =
  if target_ret = "void" then
    Printf.sprintf
      "define ptr @%s(%s) {\nentry:\n  call void @%s(%s)\n  ret ptr null\n}\n\n"
      wrap_name decl_str fn_name call_args
  else if target_ret = "ptr" then
    Printf.sprintf
      "define ptr @%s(%s) {\nentry:\n  %%r = call ptr @%s(%s)\n  ret ptr %%r\n}\n\n"
      wrap_name decl_str fn_name call_args
  else if target_ret = "double" then
    Printf.sprintf
      "define ptr @%s(%s) {\nentry:\n  %%r = call double @%s(%s)\n  \
       %%ri = bitcast double %%r to i64\n  %%rp = inttoptr i64 %%ri to ptr\n  \
       ret ptr %%rp\n}\n\n"
      wrap_name decl_str fn_name call_args
  else
    (* scalar (i64): tag as (n<<1)|1 so the dispatch's conditional untag recovers it *)
    Printf.sprintf
      "define ptr @%s(%s) {\nentry:\n  %%r = call %s @%s(%s)\n  \
       %%rs = shl i64 %%r, 1\n  %%rt = or i64 %%rs, 1\n  \
       %%rp = inttoptr i64 %%rt to ptr\n  ret ptr %%rp\n}\n\n"
      wrap_name decl_str target_ret fn_name call_args

(* ── Known builtins ──────────────────────────────────────────────────── *)

(** True for operator/function names that are builtin — not heap values.
    RC operations on these should be no-ops.

    Wave 3 Task 4 (chunk 2): moved to [Llvm_builtins] as part of the one
    declarative table replacing this, [builtin_ret_ty], [mangle_extern], and
    the hand-written preamble declare blob. See Llvm_builtins's module doc
    for the table schema and the membership-drift filing. *)
let is_builtin_fn = Llvm_builtins.is_builtin_fn

let atom_is_builtin (atom : Tir.atom) =
  match atom with
  | Tir.AVar v -> is_builtin_fn v.Tir.v_name
  | _ -> false

(** True if [name] refers to a provably-terminating call site that does not
    need a reduction check: either a March builtin operator or a C-runtime
    function injected by lower_module (identified by the "march_" prefix, e.g.
    march_compare_int, march_hash_int — see [Tir_names.has_runtime_prefix]). *)
let is_leaf_callee (name : string) : bool =
  is_builtin_fn name || Tir_names.has_runtime_prefix name

(** Returns [true] if [e] contains any non-leaf function call (EApp with a
    non-leaf callee, or any ECallPtr indirect call).  Used to decide whether
    to insert a reduction check: functions whose bodies contain no such calls
    are provably-terminating leaf functions and can skip the check. *)
let rec expr_has_call (e : Tir.expr) : bool =
  match e with
  | Tir.EApp (f, _)      -> not (is_leaf_callee f.Tir.v_name)
  | Tir.ECallPtr _       -> true   (* indirect call — always non-trivial *)
  | Tir.ELet (_, e1, e2) -> expr_has_call e1 || expr_has_call e2
  | Tir.ELetRec (fns, e2) ->
      List.exists (fun fn -> expr_has_call fn.Tir.fn_body) fns
      || expr_has_call e2
  | Tir.ECase (_, arms, def) ->
      List.exists (fun (br : Tir.branch) -> expr_has_call br.Tir.br_body) arms
      || (match def with Some d -> expr_has_call d | None -> false)
  | Tir.ESeq (e1, e2)    -> expr_has_call e1 || expr_has_call e2
  | _                    -> false

(** Emit an inline reduction-count check at the current position in [ctx.buf].
    Decrements [@march_tls_reductions]; when it reaches zero calls
    [@march_yield_from_compiled()] (which resets the budget and yields).
    Leaves the IR positioned at the start of a fresh basic block so the
    caller can continue emitting the function body. *)
let emit_reduction_check ctx =
  (* In REPL mode, skip the reduction check: ORC JIT cannot resolve
     march_tls_reductions (a TLS var) on macOS via emutls, and the REPL is
     always single-threaded so the scheduler yield is a no-op anyway. *)
  if not ctx.repl then begin
  let yield_blk = fresh_block ctx "sched_yield" in
  let cont_blk  = fresh_block ctx "sched_cont"  in
  let red       = fresh ctx "red" in
  let red_dec   = fresh ctx "red_dec" in
  let need_yield = fresh ctx "need_yield" in
  emit ctx (Printf.sprintf "%s = load i64, ptr @march_tls_reductions" red);
  emit ctx (Printf.sprintf "%s = sub i64 %s, 1" red_dec red);
  emit ctx (Printf.sprintf "store i64 %s, ptr @march_tls_reductions" red_dec);
  emit ctx (Printf.sprintf "%s = icmp sle i64 %s, 0" need_yield red_dec);
  emit_term ctx
    (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
       need_yield yield_blk cont_blk);
  emit_label ctx yield_blk;
  emit ctx "call void @march_yield_from_compiled()";
  emit_term ctx (Printf.sprintf "br label %%%s" cont_blk);
  emit_label ctx cont_blk
  end

(** TIR return type for known builtin/extern functions, overriding type info.

    Wave 3 Task 4 (chunk 2): moved to [Llvm_builtins] — see its module doc. *)
let builtin_ret_ty = Llvm_builtins.builtin_ret_ty

(** Mangle a March builtin name to the C runtime function name.

    Wave 3 Task 4 (chunk 2): moved to [Llvm_builtins] — see its module doc.
    Re-exported here (rather than only from Llvm_builtins) because
    lib/jit/repl_jit.ml references it as [March_tir.Llvm_emit.mangle_extern]. *)
let mangle_extern = Llvm_builtins.mangle_extern

(* ── Arithmetic builtins ─────────────────────────────────────────────── *)

let is_int_arith name   = List.mem name ["+"; "-"; "*"; "/"; "%"]
let is_int_cmp name     = List.mem name ["=="; "!="; "<"; "<="; ">"; ">="]
let is_float_arith name = List.mem name ["+."; "-."; "*."; "/."]

let int_arith_op = function
  | "+" -> "add" | "-" -> "sub" | "*" -> "mul"
  | "/" -> "sdiv" | "%" -> "srem" | s -> failwith ("unknown int op: " ^ s)

let int_cmp_pred = function
  | "==" -> "eq"  | "!=" -> "ne"
  | "<"  -> "slt" | "<=" -> "sle"
  | ">"  -> "sgt" | ">=" -> "sge"
  | s -> failwith ("unknown cmp: " ^ s)

let float_arith_op = function
  | "+." -> "fadd" | "-." -> "fsub"
  | "*." -> "fmul" | "/." -> "fdiv" | s -> failwith ("unknown float op: " ^ s)

let is_int_bitwise name = List.mem name ["int_and"; "int_or"; "int_xor"; "int_shl"; "int_shr"]

let int_bitwise_op = function
  | "int_and" -> "and" | "int_or" -> "or" | "int_xor" -> "xor"
  | "int_shl" -> "shl" | "int_shr" -> "ashr"
  | s -> failwith ("unknown bitwise op: " ^ s)

(* ── Alloca slot uniquification ──────────────────────────────────────── *)
(* alloca_name moved to [Llvm_ctx] (Wave 3 Task 5, chunk 2 — [emit_case], one
   of its callers, now lives in [Llvm_case] and cannot depend back on this
   file). Re-exported bare: still called unqualified throughout emit_expr. *)
let alloca_name = Llvm_ctx.alloca_name

(* ── Atom emission ───────────────────────────────────────────────────── *)

(** Emit code for [atom], returning (llvm_type, llvm_value). *)
let emit_atom ctx (atom : Tir.atom) : string * string =
  match atom with
  | Tir.ALit (March_ast.Ast.LitInt n)   -> ("i64",    string_of_int n)
  | Tir.ALit (March_ast.Ast.LitFloat f) ->
    (* LLVM requires IEEE 754 hex: 0x followed by 16 hex digits of the
       raw 64-bit double representation.  OCaml's %h gives C hex floats
       which LLVM cannot parse. *)
    let bits = Int64.bits_of_float f in
    ("double", Printf.sprintf "0x%016LX" bits)
  | Tir.ALit (March_ast.Ast.LitBool b)  -> ("i64",    if b then "1" else "0")
  | Tir.ALit (March_ast.Ast.LitAtom name) ->
    (* Atoms are interned as FNV-1a 64-bit hashes (bit63 forced == bit62 so
       they survive generic-slot tag round-trips — see atom_hash). *)
    let h = atom_hash name in
    ("i64", Int64.to_string h)
  | Tir.ALit (March_ast.Ast.LitString s) ->
    let gname = intern_string ctx s in
    let tmp = fresh ctx "sl" in
    emit ctx (Printf.sprintf "%s = call ptr @march_string_lit(ptr %s, i64 %d)"
                tmp gname (String.length s));
    ("ptr", tmp)
  | Tir.ADefRef did ->
    (* Reference to a top-level def by content hash — emit as a function pointer *)
    ("ptr", "@" ^ llvm_name (mangle_extern did.Tir.did_name))
  | Tir.AVar v when v.Tir.v_name = "root_cap" ->
    (* Capability token: represented as null ptr at runtime *)
    ("ptr", "null")
  | Tir.AVar v when v.Tir.v_name = "get_work_pool" ->
    (* Phase 1: work pool is a null sentinel *)
    ("ptr", "null")
  | Tir.AVar v when Hashtbl.mem ctx.top_fns v.Tir.v_name
                 && (match v.Tir.v_ty with Tir.TFn _ -> true | _ -> false)
                 && not (Hashtbl.mem ctx.var_slot (llvm_name v.Tir.v_name)) ->
    (* A LOCAL binding of the same name (var_slot entry) shadows the top-level
       function — fall through to the local-load path below.  Without this guard
       a recursive closure's self-reference (`let go = $clo`) whose name collides
       with a user top-level `go` would be wrapped in a $clo_wrap trampoline that
       calls the WRONG (top-level) @go instead of dispatching through $clo. *)
    (* Top-level function used as a first-class value — wrap in a closure.
       Closure layout: header(16) + field0(fn_ptr).
       The apply wrapper expects (clo, args…) and just forwards to the
       raw function, ignoring the clo argument. We reuse the raw function
       directly as the apply fn since it has compatible calling convention
       ONLY if it doesn't need the closure pointer. Instead, allocate a
       thin closure: {header, fn_ptr} where fn_ptr points to a generated
       wrapper that ignores its first arg, or just to the function directly.
       For now: store the raw fn_ptr; ECallPtr dispatch loads field 0 and
       calls fn(clo, args). For top-level fns that don't expect a clo arg,
       we need a trampoline. Simplest: alloc closure with fn ptr = raw fn,
       and make the raw fn accept an extra leading ptr arg that it ignores.
       Actually, all top-level fn_defs DON'T take a clo arg. So we need
       a wrapper. Let's create one inline. *)
    let fn_name = llvm_name (mangle_extern v.Tir.v_name) in
    (* Determine the wrapper name *)
    let wrap_name = fn_name ^ "$clo_wrap" in
    (* Register wrapper if not already generated *)
    if not (Hashtbl.mem ctx.emitted_wraps wrap_name) then begin
      Hashtbl.add ctx.emitted_wraps wrap_name ();
      (* We'll generate the wrapper function at the end.  For now, declare it.
         When the AVar's type is erased (TVar "_"), fall back to the param-count
         registered in top_fn_nparams at function-definition time. *)
      let (ps_tirs, nparams) = match v.Tir.v_ty with
        | Tir.TFn (ps, _) -> (ps, List.length ps)
        | _ ->
          let n = Option.value ~default:0 (Hashtbl.find_opt ctx.top_fn_nparams v.Tir.v_name) in
          (List.init n (fun _ -> Tir.TVar "_"), n)
      in
      let ret_tir = fn_ret_tir v.Tir.v_ty in
      let target_ret = llvm_ret_ty ret_tir in
      (* Use concrete param types so the wrapper signature matches ECallPtr's
         call-site type annotation (which uses llvm_ty for each param). *)
      let param_tys = List.map llvm_ty ps_tirs in
      let all_params = "ptr" :: param_tys in  (* clo + original params *)
      let arg_names = List.init nparams (fun i -> Printf.sprintf "%%a%d" i) in
      let all_arg_decls = "%_clo" :: arg_names in
      let decl_str = String.concat ", " (List.map2 (fun t n -> t ^ " " ^ n) all_params all_arg_decls) in
      let call_args = String.concat ", " (List.map2 (fun t n -> t ^ " " ^ n) param_tys arg_names) in
      Buffer.add_string ctx.extra_fns
        (clo_wrap_define wrap_name decl_str target_ret fn_name call_args)
    end;
    (* Allocate closure: header(16) + fn_ptr(8) = 24 bytes *)
    let hp = fresh ctx "cwrap" in
    emit ctx (Printf.sprintf "%s = call ptr @march_alloc(i64 24)" hp);
    let tgp = fresh ctx "cwt" in
    emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 8" tgp hp);
    emit ctx (Printf.sprintf "store i32 0, ptr %s, align 4" tgp);
    let fp = fresh ctx "cwf" in
    emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" fp hp);
    emit ctx (Printf.sprintf "store ptr @%s, ptr %s, align 8" wrap_name fp);
    ("ptr", hp)
  | Tir.AVar v when Hashtbl.mem ctx.top_fns v.Tir.v_name
                 && not (Hashtbl.mem ctx.zero_arg_fns v.Tir.v_name)
                 && not (Hashtbl.mem ctx.var_slot (llvm_name v.Tir.v_name)) ->
    (* Top-level function reference — emit its address directly (for EApp callee).
       Zero-arg functions (module-level `let` constants) are excluded here so
       they fall through to the 0-arg call path below, which calls the function
       to materialise the value rather than returning a function pointer.
       A local binding of the same name (in var_slot) shadows the top-level
       function — fall through to the local-load path in that case. *)
    ("ptr", "@" ^ llvm_name (mangle_extern v.Tir.v_name))
  | Tir.AVar v when Tir_names.has_runtime_prefix v.Tir.v_name
                 && not (Hashtbl.mem ctx.var_slot (llvm_name v.Tir.v_name)) ->
    (* C-runtime extern used as a first-class value (e.g. march_compare_int passed
       to a HOF).  These are declared in emit_preamble — never in var_slot or
       compiled_fns — so the alloca-bridge path would generate an invalid
       "%march_*.addr" load.  Emit the global address directly instead.

       var_slot guard (regression fix, 2026-07-02): a USER local named with
       the march_ prefix (`let march_bin = ...` — a legal identifier) is in
       var_slot and must take the normal local-load path; without this guard
       the arm emitted `@march_bin`, an undefined global, breaking any
       program with a march_*-named local (first hit: bastion
       forge/console.march). The "never in var_slot" claim above holds only
       for compiler-internal extern names.

       Guard length note (B9, fixed 2026-07-01): was `>= 7 && sub n 0 7`, a
       7-char substring compared to the 6-char literal "march_" — always
       false, so this arm was permanently dead and every march_*-named AVar
       fell through to later arms (in the worst case the 0-arg call-to-
       materialise path, which CALLS the extern with 0 args). Fixed to `>= 6
       && sub n 0 6`, matching the three sibling checks (see :575, :3243,
       :3481 in this file).

       Reachability status: NOT reachable from current surface March syntax
       as of this fix. march_* extern names (march_compare_int/float/string,
       march_hash_int/float/string/bool) are compiler-internal — injected
       only as direct EApp callees inside lower.ml's synthesized
       Ord$T.compare / Hash$T.hash wrapper bodies. mono.ml's interface
       dispatch (rewrite_calls) only rewrites direct calls to an interface
       method name; it never rewrites a bare AVar reference to the method,
       so a march_* name can never escape as a first-class value through
       legitimate resolution, and there is no global binding exposing
       march_compare_int etc. by name to user code (confirmed: referencing
       `march_compare_int` from surface syntax is an unresolved-identifier
       type error). This arm is therefore currently untested by any
       surface-syntax program; it guards against a future lowering change
       (e.g. Ord/Hash impls passed as first-class dictionary values) that
       would make march_* atoms reachable as values. If such a change lands,
       add an ir_contains regression test alongside it exercising this arm
       specifically (not just the EApp direct-call path already covered by
       test_string_ord_uses_compare_string in test/test_stdlib_suite.ml). *)
    ("ptr", "@" ^ llvm_name v.Tir.v_name)
  | Tir.AVar v when is_builtin_fn v.Tir.v_name
                 && not (Hashtbl.mem ctx.var_slot (llvm_name v.Tir.v_name)) ->
    (* Builtin function used as a first-class value (e.g. iolist_hash_fnv1a passed
       to a HOF).  These map to C-runtime externs via mangle_extern — never in
       var_slot or compiled_fns — so the alloca-bridge path would generate an
       invalid "%builtin.addr" load.  Emit the mangled global address directly.
       A LOCAL binding whose name happens to collide with a builtin (e.g. a
       user variable named `link`, which is also the actor-linking builtin)
       lives in var_slot and must shadow the builtin — fall through to the
       local-load path so we load the local value instead of emitting the
       runtime global @march_link.  (Without this guard the local `link` was
       compiled as the global function pointer @march_link, then read as a
       string → heap corruption / use-after-free.) *)
    ("ptr", "@" ^ llvm_name (mangle_extern v.Tir.v_name))
  (* ── AVar with no registered alloca slot ────────────────────────── *)
  (* If var_slot has no entry for this name, there is no alloca in the
     current function — it cannot be a locally-bound variable.  This
     arises for cross-module references (e.g. module-level `let`
     constants like "pw_iterations" that survive the lower pass as AVar
     atoms) and for external function references used as first-class
     values.  Distinguish by type:
       • TFn with ≥1 params  → wrap in a closure trampoline (same as the
         top_fns TFn path above, but for functions not yet in top_fns).
       • Anything else (0-arg function / concrete value / TVar) → call
         the function with 0 arguments to materialise the value.
     Name resolution follows the same qualified→unqualified→extern chain
     used by the ECallPtr handlers. *)
  | Tir.AVar v when not (Hashtbl.mem ctx.var_slot (llvm_name v.Tir.v_name)) ->
    let resolved =
      if Hashtbl.mem ctx.top_fns v.Tir.v_name then v.Tir.v_name
      else match Hashtbl.find_opt ctx.unqualified_fns v.Tir.v_name with
        | Some q -> q
        | None   -> v.Tir.v_name
    in
    let fname = match Hashtbl.find_opt ctx.extern_map resolved with
      | Some c -> c
      | None   -> mangle_extern resolved
    in
    (match v.Tir.v_ty with
     | Tir.TFn (ps, _) when ps <> [] ->
       (* Multi-arg function used as a first-class value from a module
          not in top_fns — wrap in a closure trampoline so that ECallPtr
          dispatch can call it uniformly.  Mirrors lines 972–1030. *)
       let fn_name   = llvm_name fname in
       let wrap_name = fn_name ^ "$clo_wrap" in
       if not (Hashtbl.mem ctx.emitted_wraps wrap_name) then begin
         Hashtbl.add ctx.emitted_wraps wrap_name ();
         let nparams     = List.length ps in
         let ret_tir     = fn_ret_tir v.Tir.v_ty in
         let target_ret  = llvm_ret_ty ret_tir in
         let param_tys   = List.map llvm_ty ps in
         let all_params  = "ptr" :: param_tys in
         let arg_names   = List.init nparams (fun i -> Printf.sprintf "%%a%d" i) in
         let all_decls   = "%_clo" :: arg_names in
         let decl_str    = String.concat ", " (List.map2 (fun t n -> t ^ " " ^ n) all_params all_decls) in
         let call_args   = String.concat ", " (List.map2 (fun t n -> t ^ " " ^ n) param_tys arg_names) in
         Buffer.add_string ctx.extra_fns
           (clo_wrap_define wrap_name decl_str target_ret fn_name call_args)
       end;
       let hp  = fresh ctx "cwrap" in
       emit ctx (Printf.sprintf "%s = call ptr @march_alloc(i64 24)" hp);
       let tgp = fresh ctx "cwt" in
       emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 8" tgp hp);
       emit ctx (Printf.sprintf "store i32 0, ptr %s, align 4" tgp);
       let fp  = fresh ctx "cwf" in
       emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" fp hp);
       emit ctx (Printf.sprintf "store ptr @%s, ptr %s, align 8" wrap_name fp);
       ("ptr", hp)
     | _ ->
       (* 0-arg function (module-level constant) or unknown type:
          call with no arguments to obtain the value. *)
       let ret_tir = match Hashtbl.find_opt ctx.top_fn_ret_ty resolved with
         | Some (Tir.TVar _) | None -> Tir.TVar "_"
         | Some t -> t
       in
       let ret_ty = llvm_ret_ty ret_tir in
       let r = fresh ctx "gl" in
       emit ctx (Printf.sprintf "%s = call %s @%s()" r ret_ty (llvm_name fname));
       (ret_ty, r))

  | Tir.AVar v ->
    let base = llvm_name v.Tir.v_name in
    let slot = match Hashtbl.find_opt ctx.var_slot base with
      | Some s -> s
      | None   -> base
    in
    (* Use the recorded LLVM type for this slot if available, so that
       variables with unresolved TVar types load with the correct type. *)
    let ty = match Hashtbl.find_opt ctx.var_llvm_ty slot with
      | Some t -> t
      | None   -> llvm_ty v.Tir.v_ty
    in
    let tmp = fresh ctx "ld" in
    emit ctx (Printf.sprintf "%s = load %s, ptr %%%s.addr" tmp ty slot);
    (ty, tmp)

let emit_atom_val ctx a = snd (emit_atom ctx a)

(** Emit atom and coerce result to [ty]. Handles TVar→ptr mismatches. *)
let emit_atom_as ctx ty a =
  let (actual_ty, v) = emit_atom ctx a in
  coerce ctx actual_ty v ty

(* ── Data-representation helpers (GEP/alloc/ctor-lookup/record-shape) ───
   Moved to [Llvm_data] (Wave 3 Task 5, chunk 2): emit_load_tag/emit_store_tag/
   emit_store_field/emit_load_field, emit_heap_alloc/emit_stack_alloc,
   ctor_entry, resolve_ctor_fields/get_record_fields/field_index_for, and the
   record-shape-metadata family (atom_tir_ty/shape_kind_char/shape_desc/
   ensure_shape_globals/emit_set_shape).  Re-exported bare here since the
   EAlloc/EStackAlloc/EReuse/ETuple/ERecord/EField/EUpdate arms below (and
   emit_case, now in [Llvm_case]) call them unqualified — same re-export
   pattern as [Llvm_ctx]'s Wave 3 Task 3 split. *)
let emit_load_tag = Llvm_data.emit_load_tag
let emit_store_tag = Llvm_data.emit_store_tag
let emit_store_field = Llvm_data.emit_store_field
let emit_load_field = Llvm_data.emit_load_field
let emit_heap_alloc = Llvm_data.emit_heap_alloc
let emit_stack_alloc = Llvm_data.emit_stack_alloc
let ctor_entry = Llvm_data.ctor_entry
let resolve_ctor_fields = Llvm_data.resolve_ctor_fields
let get_record_fields = Llvm_data.get_record_fields
let field_index_for = Llvm_data.field_index_for
let atom_tir_ty = Llvm_data.atom_tir_ty
let shape_kind_char = Llvm_data.shape_kind_char
let shape_desc = Llvm_data.shape_desc
let ensure_shape_globals = Llvm_data.ensure_shape_globals
let emit_set_shape = Llvm_data.emit_set_shape

(* ── ADT structural equality generation ───────────────────────────────
   Moved to [Llvm_eq] (Wave 3 Task 5, chunk 2): apply_ty_subst,
   mangle_ty_for_eq, field_load_llty, ensure_adt_eq_fn.  Re-exported bare
   here for the same reason as above. *)
let apply_ty_subst = Llvm_eq.apply_ty_subst
let mangle_ty_for_eq = Llvm_eq.mangle_ty_for_eq
let field_load_llty = Llvm_eq.field_load_llty
let ensure_adt_eq_fn = Llvm_eq.ensure_adt_eq_fn

(** Emit the call-site wrapper for a `raises` extern (env-routed error protocol).
    The C binding [fname] takes a hidden march_env* first param and returns the
    bare Ok payload (T of Result(T,E) = [ret_tir]); to fail it calls
    march_raise(env, e).  We pass a stack { i64 raised; i64 err }, call, then
    materialize Ok(payload) / Err(env.err).  Result is boxed → returns ("ptr",_).
    [arg_pairs] are the (llty, value) pairs for the binding's own (non-env) args. *)
let emit_raises_wrapper ctx ~fname ~ret_tir ~arg_pairs : string * string =
  let env = fresh ctx "env" in
  emit ctx (Printf.sprintf "%s = alloca { i64, i64 }" env);
  let rslot = fresh ctx "envraised" in
  emit ctx (Printf.sprintf
    "%s = getelementptr { i64, i64 }, ptr %s, i64 0, i32 0" rslot env);
  emit ctx (Printf.sprintf "store i64 0, ptr %s" rslot);
  let t_ok = ok_payload_ty ret_tir in
  let payload_llty = llvm_ret_ty t_ok in
  let call_args =
    String.concat ", "
      (Printf.sprintf "ptr %s" env
       :: List.map (fun (ty, v) -> Printf.sprintf "%s %s" ty v) arg_pairs) in
  let payload =
    if payload_llty = "void" then begin
      emit ctx (Printf.sprintf "call void @%s(%s)" fname call_args); "0"
    end else begin
      let p = fresh ctx "okpay" in
      emit ctx (Printf.sprintf "%s = call %s @%s(%s)" p payload_llty fname call_args); p
    end in
  let raisedv = fresh ctx "raised" in
  emit ctx (Printf.sprintf "%s = load i64, ptr %s" raisedv rslot);
  let cond = fresh ctx "rcond" in
  emit ctx (Printf.sprintf "%s = icmp ne i64 %s, 0" cond raisedv);
  let err_lbl = fresh_block ctx "raise_err" in
  let ok_lbl  = fresh_block ctx "raise_ok" in
  let mrg_lbl = fresh_block ctx "raise_merge" in
  emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s" cond err_lbl ok_lbl);
  (* Err: materialize Err(env.err) *)
  emit_label ctx err_lbl;
  let errslot = fresh ctx "enverr" in
  emit ctx (Printf.sprintf
    "%s = getelementptr { i64, i64 }, ptr %s, i64 0, i32 1" errslot env);
  let errv = fresh ctx "errv" in
  emit ctx (Printf.sprintf "%s = load i64, ptr %s" errv errslot);
  let eres = fresh ctx "eres" in
  emit ctx (Printf.sprintf "%s = call ptr @march_err(i64 %s)" eres errv);
  emit_term ctx (Printf.sprintf "br label %%%s" mrg_lbl);
  (* Ok: convert the bare payload to a march_value, then Ok(payload) *)
  emit_label ctx ok_lbl;
  let okval = (match t_ok with
    | Tir.TInt | Tir.TBool | Tir.TUnit | Tir.TCon ("Atom", []) ->
      (* tag a raw scalar into a march_value: (v << 1) | 1 *)
      let sh = fresh ctx "oksh" in
      emit ctx (Printf.sprintf "%s = shl i64 %s, 1" sh payload);
      let tg = fresh ctx "oktag" in
      emit ctx (Printf.sprintf "%s = or i64 %s, 1" tg sh); tg
    | Tir.TFloat ->
      (* the bare payload is a double; the Result Ok slot holds the raw IEEE
         bits (Result is a plain boxed ADT — no extra boxing for Float). *)
      let bits = fresh ctx "okfbits" in
      emit ctx (Printf.sprintf "%s = call i64 @march_make_float(double %s)" bits payload); bits
    | _ ->
      (* heap/String/record/variant: the payload word is already a value *)
      let pi = fresh ctx "okp2i" in
      emit ctx (Printf.sprintf "%s = ptrtoint ptr %s to i64" pi payload); pi) in
  let ores = fresh ctx "ores" in
  emit ctx (Printf.sprintf "%s = call ptr @march_ok(i64 %s)" ores okval);
  emit_term ctx (Printf.sprintf "br label %%%s" mrg_lbl);
  emit_label ctx mrg_lbl;
  let result = fresh ctx "raise_r" in
  emit ctx (Printf.sprintf "%s = phi ptr [ %s, %%%s ], [ %s, %%%s ]"
              result eres err_lbl ores ok_lbl);
  ("ptr", result)

(** True iff [body] is a "trivial cleanup chain" that performs only
    [EDecRC] / [EAtomicDecRC] / [EFree] operations and finally returns
    the binding named [tmp_name].

    Used to recognise the
        [ELet (tmp, EApp (f, args), ESeq (dec_v1, ESeq (dec_v2, EAtom tmp)))]
    shape that Perceus emits in the EApp case when wrapping a borrowed-arg
    last-use post-call DecRC around a NON-self call (see [perceus.ml] EApp
    handling).  Without this recognition the wrapped call is invisible to
    the tail-call analyses in the mutual-TCO section below — silently
    dropping mutual TCO and producing real stack overflows on long inputs.

    Single definition (Wave 3 Task 5, chunk 2): this predicate was
    previously duplicated — this copy (needed by emit_expr's Perceus-wrapped
    TCO cases) plus a byte-identical one at the top of the mutual-TCO
    analysis section, an OCaml forward-reference workaround carrying a
    "must stay identical" comment.  Both sets of callers live after this
    point in the file, so the duplicate was deleted and this is now the
    only copy. *)
let rec is_trivial_dec_chain_returning (tmp_name : string) (body : Tir.expr) : bool =
  match body with
  | Tir.EAtom (Tir.AVar v) -> String.equal v.Tir.v_name tmp_name
  | Tir.ESeq ((Tir.EDecRC _ | Tir.EAtomicDecRC _ | Tir.EFree _), rest) ->
    is_trivial_dec_chain_returning tmp_name rest
  | _ -> false

(* Sibling of is_trivial_dec_chain_returning for the no-temp ESeq shape:
   Perceus emits ESeq(EApp(self,args), dec_chain) — WITHOUT an ELet binding
   the call's result — when the tail call's result needs no further
   post-call field-level bookkeeping beyond decrementing/incrementing
   already-materialised local values (e.g. a wildcarded `Cons(_, t)` pattern
   decrements the local `t` after passing it on, since March's calling
   convention borrows arguments and the caller is responsible for releasing
   its own reference once the call returns). emit_expr's generic ESeq case
   relies on the "e2 is Dec/IncRC → propagate e1's value" rule (see ESeq
   below) to make e1's result the seq's value, but it also unconditionally
   clears tco_in_tail before emitting e1 — so a self-call here compiles as
   an ordinary (non-tail) call even though it is semantically a tail call.
   This predicate recognises that dec_chain consists solely of trivial
   RC bookkeeping, so the dedicated ESeq-TCO case below can intercept it
   and emit a back-edge instead. *)
let rec is_trivial_dec_chain (e : Tir.expr) : bool =
  match e with
  | Tir.EDecRC _ | Tir.EAtomicDecRC _ | Tir.EFree _
  | Tir.EIncRC _ | Tir.EAtomicIncRC _ -> true
  | Tir.ESeq ((Tir.EDecRC _ | Tir.EAtomicDecRC _ | Tir.EFree _
              | Tir.EIncRC _ | Tir.EAtomicIncRC _), rest) ->
    is_trivial_dec_chain rest
  | _ -> false

(* Wave 2 Task 1 defense-in-depth: a bare (unqualified, unresolved) callee
   name that exactly matches the dot-suffix of one or more registered
   interface-impl-mangled names ("Iface$Type.method") is the exact
   recurrence signature of the println-of-list miscompile — mono.ml failed
   to resolve a nested interface-method call (e.g. the `show(x)` inside
   `impl Show(List(a)) when Show(a)`), and it survived to codegen as a bare
   call.  unqualified_fns deliberately excludes these mangled names (see
   the population site in emit_module), so such a call would otherwise
   silently fall through to an unresolved `declare` that either fails at
   link time with a cryptic "undefined symbol" or — worse — coincidentally
   resolves against some unrelated same-named top-level fn.  Fail LOUDLY
   instead, naming the unresolved symbol and the candidate impls, so this
   can never again silently mis-bind to the wrong impl.

   Called from BOTH unqualified_fns consumers — the general EApp call path
   and the ECallPtr no-var-slot catch-all — with the same message, so any
   future refinement of this check lands in both. *)
let fail_if_unresolved_iface_method ctx (bare_name : string) : unit =
  let candidates =
    Hashtbl.fold (fun name _ acc ->
        if Tir_names.is_iface_mangled name then
          match String.rindex_opt name '.' with
          | Some i ->
            let suffix = String.sub name (i + 1) (String.length name - i - 1) in
            if suffix = bare_name then name :: acc else acc
          | None -> acc
        else acc)
      ctx.top_fns []
  in
  if candidates <> [] then
    failwith (Printf.sprintf
      "llvm_emit: unresolved interface-method call to `%s` reached codegen \
       unspecialized (mono.ml should have rewritten this to a concrete impl). \
       Candidate impls found (dispatch is ambiguous / was never resolved): %s. \
       This is a monomorphization bug, not a linker issue — refusing to \
       silently bind to an arbitrary one of these impls."
      bare_name (String.concat ", " candidates))

(* ── Core expression emitter ─────────────────────────────────────────── *)

(** Emit [e] and return (llvm_type, llvm_value). Unit → ("i64","0"). *)
let rec emit_expr ctx (e : Tir.expr) : string * string =
  match e with

  (* ── Atoms ─────────────────────────────────────────────────────────── *)
  | Tir.EAtom atom -> emit_atom ctx atom

  (* ── Free-variable load from closure struct ────────────────────────── *)
  (* ELet(v, EField(clo, "$fvN"), body): load field N from the closure ptr.
     Generated by defun for apply fns using the closure-ptr convention.
     Perceus may wrap the EField in ESeq(EIncRC(clo), EField(...)) when the
     closure is still live after the field access — we handle both forms. *)
  | Tir.ELet (v, rhs, body)
    when (let rec has_fv_field e = match e with
            | Tir.EField (_, n) -> Tir_names.is_fv_field n
            | Tir.ESeq (_, rest) -> has_fv_field rest
            | _ -> false
          in has_fv_field rhs) ->
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
    let fv = match atom_tir_ty obj_atom with
      | Tir.TTuple _ ->
        let raw = emit_load_field ctx obj_val field_idx "ptr" in
        coerce ctx "ptr" raw field_ty
      | _ -> emit_load_field ctx obj_val field_idx field_ty
    in
    let slot = alloca_name ctx (llvm_name v.Tir.v_name) in
    emit ctx (Printf.sprintf "%%%s.addr = alloca %s" slot field_ty);
    emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" field_ty fv slot);
    Hashtbl.replace ctx.var_llvm_ty slot field_ty;
    emit_expr ctx body

  (* ── Perceus-wrapped TCO self-call ────────────────────────────────── *)
  (* Perceus may wrap a self-tail-call as ELet(tmp, EApp(self, args), decrcs→tmp)
     to emit post-call RC decrements after consuming pattern-matched containers.
     has_self_tail_call recognises this as a self-tail-call and sets is_tco=true,
     but the general ELet handler below sets tco_in_tail=false for the RHS, so
     the EApp never reaches the TCO back-edge emitter.
     We intercept it here: emit the DecRC/Free side-effects from the body BEFORE
     overwriting the parameter slots, then issue the back-edge. This is correct
     because Perceus only inserts an EDecRC for the consumed container wrapper
     (e.g. the Cons cell) — not for its fields, which were moved out as the new
     argument values.  The fields are therefore still valid when we store them
     into the parameter slots after the decrement. *)
  | Tir.ELet (tmp_v, Tir.EApp (f, args), body)
    when ctx.tco_in_tail
         && (match ctx.tco_fn_name with Some n -> String.equal n f.Tir.v_name | None -> false)
         && List.length args = List.length ctx.tco_param_info
         && is_trivial_dec_chain_returning tmp_v.Tir.v_name body ->
    (* 1. Evaluate every new argument value while old parameter slots are valid. *)
    let new_vals = List.map2 (fun (_vname, _slot, param_ty) a ->
        let (arg_ty, arg_val) = emit_atom ctx a in
        coerce ctx arg_ty arg_val param_ty
      ) ctx.tco_param_info args in
    (* 2. Emit the DecRC/Free chain before overwriting slots: these ops reference
          old slot values (the consumed container wrappers) which are still valid.
          Suppress tco_in_tail so nested EDecRC/EFree calls don't misfire. *)
    let saved_tail = ctx.tco_in_tail in
    ctx.tco_in_tail <- false;
    let rec emit_dec_chain = function
      | Tir.ESeq ((Tir.EDecRC _ | Tir.EAtomicDecRC _ | Tir.EFree _ as op), rest) ->
        ignore (emit_expr ctx op);
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

  (* ── Perceus-wrapped TCO self-call, no-temp ESeq shape ──────────────── *)
  (* Sibling of the ELet-wrapped case above: when the consumed pattern only
     needs to release already-materialised local values (no field-level
     decrements requiring the call's result to be re-examined), Perceus
     emits ESeq(EApp(self,args), dec_chain) directly instead of wrapping
     the call in an ELet. See is_trivial_dec_chain's doc comment for the
     concrete example (a wildcarded `Cons(_, t)` pattern). Without this
     case, the call falls through to the generic ESeq handler below, which
     unconditionally treats e1 as non-tail — silently downgrading what is
     semantically a tail call into real (stack-growing) recursion. *)
  | Tir.ESeq (Tir.EApp (f, args), dec_chain)
    when ctx.tco_in_tail
         && (match ctx.tco_fn_name with Some n -> String.equal n f.Tir.v_name | None -> false)
         && List.length args = List.length ctx.tco_param_info
         && is_trivial_dec_chain dec_chain ->
    (* 1. Evaluate every new argument value while old parameter slots are valid. *)
    let new_vals = List.map2 (fun (_vname, _slot, param_ty) a ->
        let (arg_ty, arg_val) = emit_atom ctx a in
        coerce ctx arg_ty arg_val param_ty
      ) ctx.tco_param_info args in
    (* 2. Emit the dec/inc-RC chain before overwriting slots — same
          ordering rationale as the ELet-wrapped case above. *)
    let saved_tail = ctx.tco_in_tail in
    ctx.tco_in_tail <- false;
    let rec emit_dec_chain = function
      | Tir.ESeq ((Tir.EDecRC _ | Tir.EAtomicDecRC _ | Tir.EFree _
                  | Tir.EIncRC _ | Tir.EAtomicIncRC _) as op, rest) ->
        ignore (emit_expr ctx op);
        emit_dec_chain rest
      | (Tir.EDecRC _ | Tir.EAtomicDecRC _ | Tir.EFree _
        | Tir.EIncRC _ | Tir.EAtomicIncRC _) as op ->
        ignore (emit_expr ctx op)
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

  (* ── Perceus-wrapped mutual-TCO tail call ───────────────────────────── *)
  (* Mutual-group twin of the self-TCO ELet-wrapped case above (B7). Perceus
     does not distinguish "self" from "mutual group member" when deciding how
     to wrap a tail call's post-call DecRC/Free chain: is_self_call in
     perceus.ml only checks f.v_name = _current_fn_name, so a tail call from
     one group member to ANOTHER (e.g. build_loop -> consume_loop) takes the
     same ELet(tmp, EApp(f,args), dec_chain) wrapping as a genuine self-call
     whenever a borrowed argument's last use is this call (see
     is_trivial_dec_chain_returning's doc comment and perceus.ml's EApp case).
     Without this arm, the shape falls through to the mutual-TCO EApp
     interception below via the generic ELet handler — which clears
     tco_in_tail/emits the back-edge for the EApp, then opens a dead
     continuation block for the ELet's own body — stranding the dec-chain in
     unreachable code and leaking one heap cell every loop iteration.
     Mirrors the self-TCO arm's ordering exactly (dec-chain BEFORE the
     back-edge, including stacksave handling), redirecting to the mutual
     group's shared loop header instead of the self tco_loop_label. *)
  | Tir.ELet (tmp_v, Tir.EApp (f, args), body)
    when ctx.mutual_tco_group <> []
         && List.mem f.Tir.v_name ctx.mutual_tco_group
         && is_trivial_dec_chain_returning tmp_v.Tir.v_name body ->
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
      | Tir.ESeq ((Tir.EDecRC _ | Tir.EAtomicDecRC _ | Tir.EFree _ as op), rest) ->
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

  (* ── Perceus-wrapped mutual-TCO tail call, no-temp ESeq shape ───────── *)
  (* Mutual-group twin of the self-TCO no-temp ESeq case above (B7): sibling
     of the ELet-wrapped mutual case, for the shape Perceus uses when the
     dec-chain needs no re-examination of the call's result (see
     is_trivial_dec_chain's doc comment). Without this arm the call falls
     through to the generic ESeq handler, which unconditionally treats e1 as
     non-tail — silently downgrading a mutual tail call into real recursion. *)
  | Tir.ESeq (Tir.EApp (f, args), dec_chain)
    when ctx.mutual_tco_group <> []
         && List.mem f.Tir.v_name ctx.mutual_tco_group
         && is_trivial_dec_chain dec_chain ->
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
      | Tir.ESeq ((Tir.EDecRC _ | Tir.EAtomicDecRC _ | Tir.EFree _
                  | Tir.EIncRC _ | Tir.EAtomicIncRC _) as op, rest) ->
        ignore (emit_expr ctx op);
        emit_dec_chain rest
      | (Tir.EDecRC _ | Tir.EAtomicDecRC _ | Tir.EFree _
        | Tir.EIncRC _ | Tir.EAtomicIncRC _) as op ->
        ignore (emit_expr ctx op)
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

  (* ── Let binding ───────────────────────────────────────────────────── *)
  | Tir.ELet (v, rhs, body) ->
    (* The rhs is in non-tail position: a self-call here must be an ordinary
       call, not a TCO back-edge (else the let body would be dropped). *)
    let saved_tail = ctx.tco_in_tail in
    ctx.tco_in_tail <- false;
    let (rhs_ty, rhs_val) = emit_expr ctx rhs in
    ctx.tco_in_tail <- saved_tail;
    (* When the variable has an unresolved type (TVar), trust the actual
       LLVM type produced by the rhs expression.  This prevents type confusion
       where e.g. an Int field loaded as i64 gets coerced to ptr. *)
    let slot_ty  = match v.Tir.v_ty with
      | Tir.TVar _ -> rhs_ty
      | _ -> llvm_ty v.Tir.v_ty
    in
    let final_val = coerce ctx rhs_ty rhs_val slot_ty in
    let slot = alloca_name ctx (llvm_name v.Tir.v_name) in
    emit ctx (Printf.sprintf "%%%s.addr = alloca %s" slot slot_ty);
    emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" slot_ty final_val slot);
    Hashtbl.replace ctx.var_llvm_ty slot slot_ty;
    emit_expr ctx body

  (* ── Sequence ──────────────────────────────────────────────────────── *)
  | Tir.ESeq (e1, e2) ->
    (* e1 is evaluated for effect (non-tail); only e2 is in tail position. *)
    let saved_tail = ctx.tco_in_tail in
    ctx.tco_in_tail <- false;
    let result1 = emit_expr ctx e1 in
    ctx.tco_in_tail <- saved_tail;
    (match e2 with
     | Tir.EDecRC _ | Tir.EIncRC _
     | Tir.EAtomicDecRC _ | Tir.EAtomicIncRC _ ->
       (* e2 is a pure side-effect (no meaningful value). Return e1's value so
          that ELet(v, ESeq(call, dec_rc), body) binds the call result, not 0.
          Perceus emits this pattern for borrowed-arg post-call decrements. *)
       ignore (emit_expr ctx e2);
       result1
     | _ ->
       ignore result1;
       emit_expr ctx e2)

  (* ── Arithmetic builtins ───────────────────────────────────────────── *)
  | Tir.EApp (f, [a; b]) when is_int_arith f.Tir.v_name ->
    (* +, -, *, /, % are polymorphic over Int and Float in March.
       Detect float operands by checking the actual LLVM type of the first arg;
       if double, use floating-point ops instead of integer ops. *)
    let (ty_a, va) = emit_atom ctx a in
    if ty_a = "double" then begin
      let vb = emit_atom_as ctx "double" b in
      let r  = fresh ctx "ar" in
      (* Division uses march_checked_fdiv so that x / 0.0 aborts with an error
         rather than silently returning infinity (IEEE 754 default for fdiv).
         All other float ops use native LLVM instructions directly. *)
      if f.Tir.v_name = "/" then begin
        emit ctx (Printf.sprintf "%s = call double @march_checked_fdiv(double %s, double %s)" r va vb)
      end else begin
        let fop = match f.Tir.v_name with
          | "+" -> "fadd" | "-" -> "fsub" | "*" -> "fmul"
          | _ -> "fmul"
        in
        let op_str = if ctx.fast_math then fop ^ " fast" else fop in
        emit ctx (Printf.sprintf "%s = %s double %s, %s" r op_str va vb)
      end;
      ("double", r)
    end else begin
      let va' = coerce ctx ty_a va "i64" in
      let vb = emit_atom_as ctx "i64" b in
      let r  = fresh ctx "ar" in
      (* / and % on Int route through checked helpers so a zero divisor traps
         (matching the interpreter) instead of emitting a raw sdiv/srem that
         returns garbage.  The helpers use the bare operator messages
         ("division by zero" / "modulo by zero"); other ops stay native. *)
      (match f.Tir.v_name with
       | "/" -> emit ctx (Printf.sprintf "%s = call i64 @march_checked_div_op(i64 %s, i64 %s)" r va' vb)
       | "%" -> emit ctx (Printf.sprintf "%s = call i64 @march_checked_mod_op(i64 %s, i64 %s)" r va' vb)
       | _   -> emit ctx (Printf.sprintf "%s = %s i64 %s, %s" r (int_arith_op f.Tir.v_name) va' vb));
      ("i64", r)
    end

  | Tir.EApp (f, [a; b]) when is_int_cmp f.Tir.v_name ->
    let (ty_a, va) = emit_atom ctx a in
    let (ty_b, vb) = emit_atom ctx b in
    (* Only route through march_string_eq when we are sure the operand is an
       actual String.  ty_a = "ptr" may also occur for polymorphic values
       (TVar "_" after mono leaks) that happen to carry an Int via inttoptr —
       calling march_string_eq on such a value dereferences it as a march_string
       struct and crashes.  Check the TIR type of either operand instead. *)
    let atom_is_string = function
      | Tir.AVar v    -> (match v.Tir.v_ty with Tir.TString -> true | _ -> false)
      | Tir.ALit (March_ast.Ast.LitString _) -> true
      | _             -> false
    in
    let is_string_eq =
      ty_a = "ptr"
      && (f.Tir.v_name = "==" || f.Tir.v_name = "!=")
      && (atom_is_string a || atom_is_string b)
    in
    (* String ordering (<, <=, >, >=): the inline icmp fallback would compare
       the string struct POINTERS as integers, which has nothing to do with
       lexicographic order.  Route through march_compare_string (returns
       -1/0/1) and compare the result against 0 with the same predicate. *)
    let is_string_ord =
      ty_a = "ptr"
      && List.mem f.Tir.v_name ["<"; "<="; ">"; ">="]
      && (atom_is_string a || atom_is_string b)
    in
    if is_string_eq then begin
      (* String equality: call march_string_eq which returns i64 (0 or 1).
         Coerce both operands to ptr — vb may be an i64 literal (e.g. "0" for
         false/unit) which is invalid as a bare ptr argument in LLVM IR. *)
      let va_ptr = coerce ctx ty_a va "ptr" in
      let vb_ptr = coerce ctx ty_b vb "ptr" in
      let r = fresh ctx "cr" in
      emit ctx (Printf.sprintf "%s = call i64 @march_string_eq(ptr %s, ptr %s)" r va_ptr vb_ptr);
      if f.Tir.v_name = "!=" then begin
        let nr = fresh ctx "ar" in
        emit ctx (Printf.sprintf "%s = xor i64 %s, 1" nr r);
        ("i64", nr)
      end else
        ("i64", r)
    end else if is_string_ord then begin
      (* String ordering: compare(a, b) <pred> 0. *)
      let va_ptr = coerce ctx ty_a va "ptr" in
      let vb_ptr = coerce ctx ty_b vb "ptr" in
      let c   = fresh ctx "scmp" in
      let cmp = fresh ctx "cmp" in
      let r   = fresh ctx "ar" in
      emit ctx (Printf.sprintf "%s = call i64 @march_compare_string(ptr %s, ptr %s)" c va_ptr vb_ptr);
      emit ctx (Printf.sprintf "%s = icmp %s i64 %s, 0" cmp (int_cmp_pred f.Tir.v_name) c);
      emit ctx (Printf.sprintf "%s = zext i1 %s to i64" r cmp);
      ("i64", r)
    end else begin
      (* Fallback comparison: float or i64 (pointer coercion). *)
      let fallback_cmp () =
        let cmp = fresh ctx "cmp" in
        let r   = fresh ctx "ar" in
        if ty_a = "double" || ty_b = "double" then begin
          (* Float comparison: use fcmp ordered predicates.
             Coerce both sides to double in case one came from a boxed ptr. *)
          let fpred = match f.Tir.v_name with
            | "==" -> "oeq" | "!=" -> "one"
            | "<"  -> "olt" | "<=" -> "ole"
            | ">"  -> "ogt" | ">=" -> "oge"
            | s -> failwith ("unknown cmp: " ^ s)
          in
          let va_f = coerce ctx ty_a va "double" in
          let vb_f = coerce ctx ty_b vb "double" in
          emit ctx (Printf.sprintf "%s = fcmp %s double %s, %s" cmp fpred va_f vb_f);
        end else begin
          (* Coerce to i64 in case variables were loaded as ptr due to TVar type *)
          let va' = coerce ctx ty_a va "i64" in
          let vb' = coerce ctx ty_b vb "i64" in
          emit ctx (Printf.sprintf "%s = icmp %s i64 %s, %s" cmp (int_cmp_pred f.Tir.v_name) va' vb')
        end;
        emit ctx (Printf.sprintf "%s = zext i1 %s to i64" r cmp);
        ("i64", r)
      in
      (* ADT structural equality: when both operands are heap-allocated ADT values
         (ty_a = "ptr", TCon type, not String) generate a structural comparison
         instead of the pointer comparison that icmp eq i64 would produce. *)
      let atom_adt_ty = function
        | Tir.AVar v -> (match v.Tir.v_ty with
          | Tir.TCon ("Atom", []) -> None
          | Tir.TCon _ as t -> Some t
          | (Tir.TTuple _ | Tir.TRecord _) as t -> Some t
          | _ -> None)
        | _ -> None
      in
      if ty_a = "ptr" && (f.Tir.v_name = "==" || f.Tir.v_name = "!=") then
        let adt_ty_opt = match atom_adt_ty a with
          | Some _ as t -> t
          | None -> atom_adt_ty b
        in
        (match adt_ty_opt with
         | Some adt_ty ->
           (match ensure_adt_eq_fn ctx adt_ty with
            | Some eq_fn ->
              let r = fresh ctx "ar" in
              let va_ptr = coerce ctx ty_a va "ptr" in
              let vb_ptr = coerce ctx ty_b vb "ptr" in
              emit ctx (Printf.sprintf "%s = call i64 @%s(ptr %s, ptr %s)" r eq_fn va_ptr vb_ptr);
              if f.Tir.v_name = "!=" then begin
                let nr = fresh ctx "nr" in
                emit ctx (Printf.sprintf "%s = xor i64 %s, 1" nr r);
                ("i64", nr)
              end else
                ("i64", r)
            | None -> fallback_cmp ())
         | None ->
           (* Polymorphic ptr comparison: the TIR type is TVar (e.g. the result
              of a polymorphic function like root_hash).  Pointer identity
              (fallback_cmp) compares addresses, not content — always false for
              two distinct string allocations with equal content.  Use
              march_poly_eq which checks string tags at runtime and delegates to
              march_string_eq for strings, giving correct content equality. *)
           let r = fresh ctx "ar" in
           let va_ptr = coerce ctx ty_a va "ptr" in
           let vb_ptr = coerce ctx ty_b vb "ptr" in
           emit ctx (Printf.sprintf "%s = call i64 @march_poly_eq(ptr %s, ptr %s)" r va_ptr vb_ptr);
           if f.Tir.v_name = "!=" then begin
             let nr = fresh ctx "nr" in
             emit ctx (Printf.sprintf "%s = xor i64 %s, 1" nr r);
             ("i64", nr)
           end else
             ("i64", r))
      else fallback_cmp ()
    end

  | Tir.EApp (f, [a; b]) when is_float_arith f.Tir.v_name ->
    let va = emit_atom_as ctx "double" a in
    let vb = emit_atom_as ctx "double" b in
    let r  = fresh ctx "ar" in
    (* /. uses march_checked_fdiv for the same reason as / above. *)
    if f.Tir.v_name = "/." then
      emit ctx (Printf.sprintf "%s = call double @march_checked_fdiv(double %s, double %s)" r va vb)
    else begin
      let op = float_arith_op f.Tir.v_name in
      let op_str = if ctx.fast_math then op ^ " fast" else op in
      emit ctx (Printf.sprintf "%s = %s double %s, %s" r op_str va vb)
    end;
    ("double", r)

  (* ── Boolean operators ───────────────────────────────────────────── *)
  | Tir.EApp (f, [a; b]) when f.Tir.v_name = "&&" ->
    let va = emit_atom_as ctx "i64" a in
    let vb = emit_atom_as ctx "i64" b in
    let r  = fresh ctx "ar" in
    emit ctx (Printf.sprintf "%s = and i64 %s, %s" r va vb);
    ("i64", r)

  | Tir.EApp (f, [a; b]) when f.Tir.v_name = "||" ->
    let va = emit_atom_as ctx "i64" a in
    let vb = emit_atom_as ctx "i64" b in
    let r  = fresh ctx "ar" in
    emit ctx (Printf.sprintf "%s = or i64 %s, %s" r va vb);
    ("i64", r)

  | Tir.EApp (f, [a]) when f.Tir.v_name = "not" ->
    let va = emit_atom_as ctx "i64" a in
    let r  = fresh ctx "ar" in
    emit ctx (Printf.sprintf "%s = xor i64 %s, 1" r va);
    ("i64", r)

  | Tir.EApp (f, [a]) when f.Tir.v_name = "negate" ->
    let (ty, va) = emit_atom ctx a in
    let r = fresh ctx "ar" in
    if ty = "double" then
      emit ctx (Printf.sprintf "%s = fneg double %s" r va)
    else
      emit ctx (Printf.sprintf "%s = sub i64 0, %s" r va);
    (ty, r)

  (* ── ~H sigil: html_auto_escape(v) ────────────────────────────────────
     The runtime `march_html_auto_escape` takes a single generic `ptr` and
     dispatches on its representation (low-bit-tagged immediate int, String,
     or IOList constructor).  The argument is polymorphic (`∀a. a -> String`)
     so it may arrive as a raw scalar — an Int interpolation `${n}` lowers to
     `html_auto_escape(n)` with `n : i64`.  The general call path would emit
     `call ptr @march_html_auto_escape(i64 42)`, passing the untagged scalar
     where the runtime expects a tagged ptr; the runtime then treats `42` as a
     heap address and segfaults.  Coerce the argument to a tagged `ptr` first
     (i64→ptr applies the `(n<<1)|1` immediate tag) so the runtime's int path
     fires correctly. *)
  | Tir.EApp (f, [a]) when f.Tir.v_name = "html_auto_escape" ->
    let v = emit_atom_as ctx "ptr" a in
    let r = fresh ctx "hae" in
    emit ctx (Printf.sprintf "%s = call ptr @march_html_auto_escape(ptr %s)" r v);
    ("ptr", r)

  (* ── Bitwise integer builtins ─────────────────────────────────────── *)
  | Tir.EApp (f, [a; b]) when is_int_bitwise f.Tir.v_name ->
    let va = emit_atom_as ctx "i64" a in
    let vb = emit_atom_as ctx "i64" b in
    let r  = fresh ctx "bw" in
    emit ctx (Printf.sprintf "%s = %s i64 %s, %s" r (int_bitwise_op f.Tir.v_name) va vb);
    ("i64", r)

  | Tir.EApp (f, [a]) when f.Tir.v_name = "int_not" ->
    let va = emit_atom_as ctx "i64" a in
    let r  = fresh ctx "bw" in
    emit ctx (Printf.sprintf "%s = xor i64 %s, -1" r va);
    ("i64", r)

  | Tir.EApp (f, [a]) when f.Tir.v_name = "int_popcount" ->
    let va = emit_atom_as ctx "i64" a in
    let r  = fresh ctx "bw" in
    emit ctx (Printf.sprintf "%s = call i64 @llvm.ctpop.i64(i64 %s)" r va);
    ("i64", r)

  (* ── Task builtins (Phase 1: inline LLVM IR, no C runtime) ────────── *)
  (* Thunks are fn x -> expr (Int -> a).  task_spawn calls the closure
     with dummy arg 0, boxes result into a Task heap object.
     task_await_unwrap unboxes field 0 from the Task. *)

  (* task_spawn(thunk_closure) → spawn as async green thread via runtime *)
  | Tir.EApp (f, [clo_atom]) when f.Tir.v_name = "task_spawn" ->
    let (_, clo_ptr) = emit_atom ctx clo_atom in
    let result = fresh ctx "tsres" in
    emit ctx (Printf.sprintf "%s = call ptr @march_task_spawn_thunk(ptr %s)"
                result clo_ptr);
    ("ptr", result)

  (* task_await_unwrap(task_ptr) → spin-wait then untag result directly *)
  | Tir.EApp (f, [a]) when f.Tir.v_name = "task_await_unwrap" ->
    let (_, task_ptr) = emit_atom ctx a in
    let res = fresh ctx "tawait_res" in
    emit ctx (Printf.sprintf "%s = call ptr @march_task_await(ptr %s)" res task_ptr);
    (* march_task_await returns Ok(inner); unwrap by loading field 0 of Result. *)
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
    else r_i64 in
    (inner_ty, r)

  (* task_await(task_ptr) → delegate to march_task_await C runtime *)
  | Tir.EApp (f, [a]) when f.Tir.v_name = "task_await" ->
    let (_, tp) = emit_atom ctx a in
    let r = fresh ctx "tawait" in
    emit ctx (Printf.sprintf "%s = call ptr @march_task_await(ptr %s)" r tp);
    ("ptr", r)

  (* task_yield() → cooperative yield via march_sched_yield *)
  | Tir.EApp (f, []) when f.Tir.v_name = "task_yield" ->
    emit ctx "call void @march_sched_yield()";
    ("i64", "0")

  (* receive() → cooperative blocking mailbox pop via march_sched_recv *)
  | Tir.EApp (f, []) when f.Tir.v_name = "receive" ->
    let r = fresh ctx "recv_msg" in
    emit ctx (Printf.sprintf "%s = call ptr @march_sched_recv()" r);
    ("ptr", r)

  (* task_spawn_steal(pool, thunk_closure) → spawn as async green thread *)
  | Tir.EApp (f, [_pool; clo_atom]) when f.Tir.v_name = "task_spawn_steal" ->
    let (_, clo_ptr) = emit_atom ctx clo_atom in
    let result = fresh ctx "tsres" in
    emit ctx (Printf.sprintf "%s = call ptr @march_task_spawn_thunk(ptr %s)"
                result clo_ptr);
    ("ptr", result)

  (* pmap_threshold() → compile-time constant i64 from --pmap-threshold *)
  | Tir.EApp (f, []) when f.Tir.v_name = "pmap_threshold" ->
    ("i64", string_of_int ctx.pmap_threshold)

  (* remote_ref_hashes(module, fn) → constant-fold to (sig_hash, impl_hash) pair.
     Looks up the CAS-derived hashes baked into the binary at compile time.
     Returns a heap-allocated (String, String) tuple; both strings are empty
     when the function name was not found in the hash maps (non-CAS builds).
     Key lookup strategy: top-level user module functions are stored without
     the module prefix (fn_name = "fib"), while stdlib/nested module functions
     are stored with it (fn_name = "String.from_int").  Try both forms. *)
  | Tir.EApp (f, [mod_atom; fn_atom]) when f.Tir.v_name = "remote_ref_hashes" ->
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

  (* task_reductions() → read TLS reduction counter (no-op 0 in REPL mode) *)
  | Tir.EApp (f, []) when f.Tir.v_name = "task_reductions" ->
    if ctx.repl then ("i64", "0")
    else begin
      let r = fresh ctx "reds" in
      emit ctx (Printf.sprintf "%s = load i64, ptr @march_tls_reductions" r);
      ("i64", r)
    end

  (* task_cancel_token_new() → allocate a new cancel token *)
  | Tir.EApp (f, []) when f.Tir.v_name = "task_cancel_token_new" ->
    let r = fresh ctx "ctok" in
    emit ctx (Printf.sprintf "%s = call ptr @march_cancel_token_new()" r);
    ("ptr", r)

  (* task_cancel(tok) → cancel the token *)
  | Tir.EApp (f, [tok]) when f.Tir.v_name = "task_cancel" ->
    let (_, tp) = emit_atom ctx tok in
    emit ctx (Printf.sprintf "call void @march_cancel_token_cancel(ptr %s)" tp);
    ("i64", "0")

  (* task_is_cancelled(tok) → check if token is cancelled *)
  | Tir.EApp (f, [tok]) when f.Tir.v_name = "task_is_cancelled" ->
    let (_, tp) = emit_atom ctx tok in
    let r = fresh ctx "isc" in
    emit ctx (Printf.sprintf "%s = call i64 @march_cancel_token_is_cancelled(ptr %s)" r tp);
    ("i64", r)

  (* task_spawn_with_cancel(clo, tok) → spawn with cancel token *)
  | Tir.EApp (f, [clo; tok]) when f.Tir.v_name = "task_spawn_with_cancel" ->
    let (_, cp) = emit_atom ctx clo in
    let (_, tp) = emit_atom ctx tok in
    let r = fresh ctx "tswc" in
    emit ctx (Printf.sprintf "%s = call ptr @march_task_spawn_with_cancel_thunk(ptr %s, ptr %s)" r cp tp);
    ("ptr", r)

  (* task_cancel_by_id(task) → mark task's proc as DEAD *)
  | Tir.EApp (f, [t]) when f.Tir.v_name = "task_cancel_by_id" ->
    let (_, tp) = emit_atom ctx t in
    emit ctx (Printf.sprintf "call void @march_task_cancel_by_id(ptr %s)" tp);
    ("i64", "0")

  (* get_work_pool() → null sentinel in Phase 1 *)
  | Tir.EApp (f, []) when f.Tir.v_name = "get_work_pool" ->
    ("ptr", "null")

  (* ── Record introspection builtins (native lowering) ───────────────── *)
  (* These cannot be plain C externs because record values carry no field
     names; they rely on the shape id stamped into the header pad word by
     emit_set_shape and pass call-site value-kind hints where the C side
     needs to know a value's natural representation.  See the "Record shape
     registry" section in runtime/march_extras.c for the conventions. *)
  | Tir.EApp (f, [r])
    when (match f.Tir.v_name with
          | "record_keys" | "record_values" | "record_entries" -> true
          | _ -> false) ->
    let (rt, rv) = emit_atom ctx r in
    let rp = coerce ctx rt rv "ptr" in
    let res = fresh ctx "cr" in
    emit ctx (Printf.sprintf "%s = call ptr @march_%s(ptr %s)"
                res f.Tir.v_name rp);
    ("ptr", res)

  | Tir.EApp (f, [r; k]) when f.Tir.v_name = "record_get" ->
    let (rt, rv) = emit_atom ctx r in
    let rp = coerce ctx rt rv "ptr" in
    let (kt, kv) = emit_atom ctx k in
    let kp = coerce ctx kt kv "ptr" in
    let res = fresh ctx "cr" in
    (* Pass the payload kind so march_record_get returns the right None encoding
       (niche null for scalar/ptr kinds; boxed heap cell for Float/generic). *)
    let payload_kind = match f.Tir.v_ty with
      | Tir.TFn (_, Tir.TCon ("Option", [p])) ->
        Char.code (shape_kind_char p)
      | _ -> Char.code 'g'
    in
    emit ctx (Printf.sprintf "%s = call ptr @march_record_get(ptr %s, ptr %s, i64 %d)"
                res rp kp payload_kind);
    ("ptr", res)

  | Tir.EApp (f, [r; k]) when f.Tir.v_name = "record_has_key" ->
    let (rt, rv) = emit_atom ctx r in
    let rp = coerce ctx rt rv "ptr" in
    let (kt, kv) = emit_atom ctx k in
    let kp = coerce ctx kt kv "ptr" in
    let res = fresh ctx "cr" in
    emit ctx (Printf.sprintf "%s = call i64 @march_record_has_key(ptr %s, ptr %s)"
                res rp kp);
    ("i64", res)

  | Tir.EApp (f, [r; k; v]) when f.Tir.v_name = "record_put" ->
    let (rt, rv) = emit_atom ctx r in
    let rp = coerce ctx rt rv "ptr" in
    let (kt, kv) = emit_atom ctx k in
    let kp = coerce ctx kt kv "ptr" in
    let (vt, vv) = emit_atom ctx v in
    (* Pass the value in UNIFORM representation as a ptr-sized word: scalars
       low-bit tagged (coerce i64→ptr), raw bits for floats, ptr as-is.
       Natural repr is ambiguous — an even Int >= 4096 is bit-identical to a
       heap pointer, so the runtime's plausible-heap sniff would incrc
       (dereference) the integer's value.  Tagged scalars are always odd and
       untag unambiguously in rec_field_norm_uniform. *)
    let vp = (match vt with
      | "i64" -> coerce ctx "i64" vv "ptr"
      | "double" ->
        let b = fresh ctx "cv" in
        let t = fresh ctx "cv" in
        emit ctx (Printf.sprintf "%s = bitcast double %s to i64" b vv);
        emit ctx (Printf.sprintf "%s = inttoptr i64 %s to ptr" t b);
        t
      | _ -> vv) in
    let kind = shape_kind_char (atom_tir_ty v) in
    let res = fresh ctx "cr" in
    emit ctx (Printf.sprintf
      "%s = call ptr @march_record_put(ptr %s, ptr %s, ptr %s, i64 %d)"
      res rp kp vp (Char.code kind));
    ("ptr", res)

  | Tir.EApp (f, [l]) when f.Tir.v_name = "record_from_list" ->
    let (lt, lv) = emit_atom ctx l in
    let lp = coerce ctx lt lv "ptr" in
    (* Kind hint for the pair values, from the list's element tuple type. *)
    let kind = (match atom_tir_ty l with
      | Tir.TCon ("List", [Tir.TTuple [_; b]]) -> shape_kind_char b
      | _ -> 'g') in
    let res = fresh ctx "cr" in
    emit ctx (Printf.sprintf
      "%s = call ptr @march_record_from_list_k(ptr %s, i64 %d)"
      res lp (Char.code kind));
    ("ptr", res)

  (* ── to_string: dispatch on argument TIR type ──────────────────────── *)
  | Tir.EApp (f, [a]) when f.Tir.v_name = "to_string" ->
    let (arg_ty, arg_val) = emit_atom ctx a in
    let tir_ty = (match a with
      | Tir.AVar v -> v.Tir.v_ty
      | Tir.ALit (March_ast.Ast.LitInt _) -> Tir.TInt
      | Tir.ALit (March_ast.Ast.LitFloat _) -> Tir.TFloat
      | Tir.ALit (March_ast.Ast.LitBool _) -> Tir.TBool
      | Tir.ALit (March_ast.Ast.LitString _) -> Tir.TString
      | _ -> Tir.TVar "_") in
    (match tir_ty with
     | Tir.TString ->
       (* Already a string, identity *)
       let v = coerce ctx arg_ty arg_val "ptr" in
       ("ptr", v)
     | Tir.TInt ->
       let v = coerce ctx arg_ty arg_val "i64" in
       let r = fresh ctx "cr" in
       emit ctx (Printf.sprintf "%s = call ptr @march_int_to_string(i64 %s)" r v);
       ("ptr", r)
     | Tir.TFloat ->
       let v = coerce ctx arg_ty arg_val "double" in
       let r = fresh ctx "cr" in
       emit ctx (Printf.sprintf "%s = call ptr @march_float_to_string(double %s)" r v);
       ("ptr", r)
     | Tir.TBool ->
       let v = coerce ctx arg_ty arg_val "i64" in
       let r = fresh ctx "cr" in
       emit ctx (Printf.sprintf "%s = call ptr @march_bool_to_string(i64 %s)" r v);
       ("ptr", r)
     | _ ->
       let v = coerce ctx arg_ty arg_val "ptr" in
       let r = fresh ctx "cr" in
       emit ctx (Printf.sprintf "%s = call ptr @march_value_to_string(ptr %s)" r v);
       ("ptr", r))

  (* ── Mutual TCO: tail call to another member of the current group ──── *)
  (* When we are inside emit_mutual_tco_group and the call target is any
     function in the mutual group (including self), we redirect it to the
     shared loop header by: updating the dispatch tag + the target's param
     slots, then branching back to mutual_loop. *)
  | Tir.EApp (f, args)
    when ctx.mutual_tco_group <> []
         && List.mem f.Tir.v_name ctx.mutual_tco_group ->
    let target     = f.Tir.v_name in
    let target_tag = List.assoc target ctx.mutual_tco_fn_tags in
    let target_slots =
      try List.assoc target ctx.mutual_tco_fn_params
      with Not_found -> [] in
    (* 1. Evaluate all new argument values first (read before write). *)
    let new_vals = List.map2 (fun (_vname, _slot, param_ty) a ->
        let (arg_ty, arg_val) = emit_atom ctx a in
        coerce ctx arg_ty arg_val param_ty
      ) target_slots args in
    (* 2. Update the dispatch tag. *)
    emit ctx (Printf.sprintf "store i64 %d, ptr %%%s.addr"
      target_tag ctx.mutual_tco_tag_slot);
    (* 3. Store new argument values into the target function's param slots. *)
    List.iter2 (fun (_vname, slot, param_ty) new_v ->
        emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr"
          param_ty new_v slot)
      ) target_slots new_vals;
    (* 4. Free any per-iteration `alloca` stack space before looping back —
          see tco_stack_save's doc comment for why this is required. *)
    if ctx.mutual_tco_stack_save <> "" then
      emit ctx (Printf.sprintf "call void @llvm.stackrestore(ptr %s)" ctx.mutual_tco_stack_save);
    (* 5. Branch back to the shared loop header. *)
    emit_term ctx (Printf.sprintf "br label %%%s" ctx.mutual_tco_loop_label);
    (* 6. Open a dead continuation block for syntactic validity. *)
    emit_label ctx (fresh_block ctx "mutco_cont");
    let dummy_ty = llvm_ret_ty ctx.ret_ty in
    (match dummy_ty with
     | "double" -> ("double", "0x0000000000000000")
     | "void"   -> ("i64",    "0")
     | _        -> ("i64",    "0"))

  (* ── TCO self-call: back-edge instead of a call instruction ────────── *)
  (* When TCO is active for the current function and this EApp targets it,
     store the new argument values into the parameter alloca slots and
     jump to the loop header.  The instructions emitted after the br
     (from the calling emit_case / emit_fn context) land in a dead block —
     valid LLVM IR but never executed; the optimizer removes them. *)
  | Tir.EApp (f, args)
    when ctx.tco_in_tail
         && (match ctx.tco_fn_name with
          | Some n -> String.equal n f.Tir.v_name
          | None   -> false)
         && List.length args = List.length ctx.tco_param_info ->
    (* 1. Evaluate every new argument while the old parameter slots are
          still live — read all inputs before writing any outputs. *)
    let new_vals = List.map2 (fun (_vname, _slot, param_ty) a ->
        let (arg_ty, arg_val) = emit_atom ctx a in
        coerce ctx arg_ty arg_val param_ty
      ) ctx.tco_param_info args in
    (* 2. Store each new value into the corresponding parameter slot. *)
    List.iter2 (fun (_vname, slot, param_ty) new_v ->
        emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" param_ty new_v slot)
      ) ctx.tco_param_info new_vals;
    (* 3. Free any per-iteration `alloca` stack space before looping back —
          see tco_stack_save's doc comment for why this is required. *)
    if ctx.tco_stack_save <> "" then
      emit ctx (Printf.sprintf "call void @llvm.stackrestore(ptr %s)" ctx.tco_stack_save);
    (* 4. Loop back — this is the terminator for the current basic block. *)
    emit_term ctx (Printf.sprintf "br label %%%s" ctx.tco_loop_label);
    (* 5. Open a dead block so that any instructions the caller emits after
          us (e.g., emit_case's store-to-result-slot + br-to-merge) are
          syntactically valid LLVM IR even though they are unreachable. *)
    emit_label ctx (fresh_block ctx "tco_cont");
    (* 5. Return a dummy value.  The caller may coerce / store it, but since
          we are in a dead block the value is never observed. *)
    let dummy_ty = llvm_ret_ty ctx.ret_ty in
    let dummy = match dummy_ty with
      | "double" -> ("double", "0x0000000000000000")
      | "void"   -> ("i64",    "0")
      | _        -> ("i64",    "0")
    in
    dummy

  (* ── Send with linear message: emit march_send_linear (zero-copy move) ─ *)
  (* When the message argument is a linear value (v_lin = Lin), the compiler
     can guarantee that no other reference to the message exists after the
     send.  We emit march_send_linear (which will call march_msg_move) rather
     than the default march_send (which copies for non-linear messages).
     This is the Phase 5 linear-type optimization: zero-copy inter-process
     message passing for linearly-typed messages. *)
  | Tir.EApp (f, [actor_atom; msg_atom])
    when f.Tir.v_name = "send"
      && (match msg_atom with
          | Tir.AVar v -> v.Tir.v_lin = Tir.Lin
          | _ -> false) ->
    let (actor_ty, actor_v) = emit_atom ctx actor_atom in
    let (msg_ty,   msg_v)   = emit_atom ctx msg_atom in
    let r = fresh ctx "cr" in
    emit ctx (Printf.sprintf "%s = call ptr @march_send_linear(%s %s, %s %s)"
                r actor_ty actor_v msg_ty msg_v);
    ("ptr", r)

  (* ── Integer arithmetic builtins called via EApp ─────────────────── *)
  (* int_mod / int_div / int_mod_euclid / int_abs / int_pow /
     int_max_value / int_min_value are in builtin_names in defun.ml
     so they stay as EApp (not converted to ECallPtr).  Handle them here
     BEFORE the var_slot guard so the specific match takes priority. *)
  | Tir.EApp (f, [a; b])
    when f.Tir.v_name = "int_mod" || f.Tir.v_name = "int_div"
      || f.Tir.v_name = "int_mod_euclid" ->
    let va = emit_atom_as ctx "i64" a in
    let vb = emit_atom_as ctx "i64" b in
    let r  = fresh ctx "ar" in
    (* Route through a checked runtime helper so a zero divisor traps via
       march_panic (matching the interpreter) instead of executing a raw
       sdiv/srem/urem, which is undefined for a 0 divisor. *)
    let helper = match f.Tir.v_name with
      | "int_mod"        -> "march_checked_imod"
      | "int_div"        -> "march_checked_idiv"
      | "int_mod_euclid" -> "march_checked_umod"
      | _                -> assert false
    in
    emit ctx (Printf.sprintf "%s = call i64 @%s(i64 %s, i64 %s)" r helper va vb);
    ("i64", r)

  | Tir.EApp (f, [a; b])
    when f.Tir.v_name = "int_pow" ->
    let va = emit_atom_as ctx "i64" a in
    let vb = emit_atom_as ctx "i64" b in
    let r  = fresh ctx "ar" in
    emit ctx (Printf.sprintf "%s = call i64 @march_int_pow(i64 %s, i64 %s)" r va vb);
    ("i64", r)

  | Tir.EApp (f, [a])
    when f.Tir.v_name = "int_abs" ->
    let va = emit_atom_as ctx "i64" a in
    let r  = fresh ctx "ar" in
    emit ctx (Printf.sprintf "%s = call i64 @llvm.abs.i64(i64 %s, i1 false)" r va);
    ("i64", r)

  | Tir.EApp (f, _)
    when f.Tir.v_name = "int_max_value" ->
    ("i64", "9223372036854775807")

  | Tir.EApp (f, _)
    when f.Tir.v_name = "int_min_value" ->
    ("i64", "-9223372036854775808")

  (* ── Vault stores: the value is a heterogeneous void pointer and MUST be the
     uniform tagged representation so it round-trips through Vault.get →
     Some(v) → unwrap_or, which conditional-untags.  The general EApp path
     below passes each arg with its NATURAL llvm type, so a Bool/Int value
     would reach march_vault_set as a raw i64 (e.g. true→0x1) and be read back
     untagged (0x1 ashr→0 = false).  Coerce the value arg to ptr (tags scalars
     via (n<<1)|1, leaves heap pointers unchanged); table/key are already ptr,
     trailing ttl/max stay i64. *)
  | Tir.EApp (f, [tbl; key; value])
    when f.Tir.v_name = "vault_set" ->
    let vt = emit_atom_as ctx "ptr" tbl in
    let vk = emit_atom_as ctx "ptr" key in
    let vv = emit_atom_as ctx "ptr" value in
    emit ctx (Printf.sprintf
      "call ptr @march_vault_set(ptr %s, ptr %s, ptr %s)" vt vk vv);
    ("i64", "0")

  | Tir.EApp (f, [tbl; key; value; ttl])
    when f.Tir.v_name = "vault_set_ttl" ->
    let vt = emit_atom_as ctx "ptr" tbl in
    let vk = emit_atom_as ctx "ptr" key in
    let vv = emit_atom_as ctx "ptr" value in
    let vttl = emit_atom_as ctx "i64" ttl in
    emit ctx (Printf.sprintf
      "call ptr @march_vault_set_ttl(ptr %s, ptr %s, ptr %s, i64 %s)" vt vk vv vttl);
    ("i64", "0")

  | Tir.EApp (f, [tbl; key; value; ttl])
    when f.Tir.v_name = "vault_put_new" ->
    let vt = emit_atom_as ctx "ptr" tbl in
    let vk = emit_atom_as ctx "ptr" key in
    let vv = emit_atom_as ctx "ptr" value in
    let vttl = emit_atom_as ctx "i64" ttl in
    let r = fresh ctx "ar" in
    emit ctx (Printf.sprintf
      "%s = call i64 @march_vault_put_new(ptr %s, ptr %s, ptr %s, i64 %s)" r vt vk vv vttl);
    ("i64", r)

  | Tir.EApp (f, [tbl; key; value; maxn])
    when f.Tir.v_name = "vault_push_capped" ->
    let vt = emit_atom_as ctx "ptr" tbl in
    let vk = emit_atom_as ctx "ptr" key in
    let vv = emit_atom_as ctx "ptr" value in
    let vmax = emit_atom_as ctx "i64" maxn in
    emit ctx (Printf.sprintf
      "call ptr @march_vault_push_capped(ptr %s, ptr %s, ptr %s, i64 %s)" vt vk vv vmax);
    ("i64", "0")

  (* ── actor_reply: coerce result to tagged ptr so integers survive the
     void* round-trip through march_actor_reply / march_sched_send / recv ── *)
  (* actor_reply is declared as (ptr, ptr) → void.  The general EApp path emits
     each arg with its natural LLVM type, so an Int result arrives as a raw i64
     (e.g. 5) instead of the tagged form ((5<<1)|1 = 11) that the caller's
     Result-unboxing code expects.  Coerce result to ptr here so integers are
     tagged before being enqueued, matching the ptr→i64 conditional-untag on the
     receive side. *)
  | Tir.EApp (f, [ref_atom; result_atom])
    when f.Tir.v_name = "actor_reply" ->
    let vref = emit_atom_as ctx "ptr" ref_atom in
    let vres = emit_atom_as ctx "ptr" result_atom in
    emit ctx (Printf.sprintf "call void @march_actor_reply(ptr %s, ptr %s)" vref vres);
    ("i64", "0")

  (* ── EApp of a locally-bound closure variable ────────────────────── *)
  (* If f has a var_slot alloca AND is not a top-level function, it is a
     local closure — redirect to ECallPtr dispatch.
     Top-level functions (registered in top_fns via extern_fns) must use the
     direct-call path even when they also have a var_slot entry from the
     REPL global bridge: the bridge closure uses a different calling convention
     ($clo_wrap) that does not match the direct i64/ptr return the call-site
     type expects.  Letting top_fns functions fall through to the general EApp
     case generates the correct `call i64 @fn(...)` instruction directly. *)
  | Tir.EApp (f, args)
    when Hashtbl.mem ctx.var_slot (llvm_name f.Tir.v_name)
      && not (Hashtbl.mem ctx.top_fns f.Tir.v_name) ->
    emit_expr ctx (Tir.ECallPtr (Tir.AVar f, args))

  (* ── General function call ─────────────────────────────────────────── *)
  | Tir.EApp (f, args) ->
    (* Emit each arg once, collecting both type and value strings. *)
    let arg_pairs = List.map (fun a -> emit_atom ctx a) args in
    let arg_strs  = List.map (fun (ty, v) -> ty ^ " " ^ v) arg_pairs in
    let args_str  = String.concat ", " arg_strs in
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
          | "print" | "print_stderr" | "io_read_line" | "read_line" -> true
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
    else if Hashtbl.mem ctx.blocking_externs resolved_name then begin
      (* Blocking dispatch: marshal args into a stack i64 array and run the C
         call on an OS thread via march_run_blocking_*, while the green thread
         cooperatively yields.  Int/ptr args only (GP-register trampoline). *)
      let n   = List.length arg_pairs in
      let cap = if n = 0 then 1 else n in
      let arr = fresh ctx "blkargs" in
      emit ctx (Printf.sprintf "%s = alloca [%d x i64]" arr cap);
      List.iteri (fun i (ty, v) ->
        let iv = match ty with
          | "i64" -> v
          | "ptr" -> let t = fresh ctx "blki" in
                     emit ctx (Printf.sprintf "%s = ptrtoint ptr %s to i64" t v); t
          | other ->
            failwith (Printf.sprintf
              "blocking extern `%s`: argument type %s is not supported \
               (Int/Bool/pointer args only)" resolved_name other)
        in
        let slot = fresh ctx "blkslot" in
        emit ctx (Printf.sprintf
          "%s = getelementptr [%d x i64], ptr %s, i64 0, i64 %d" slot cap arr i);
        emit ctx (Printf.sprintf "store i64 %s, ptr %s" iv slot)
      ) arg_pairs;
      let helper, hret =
        if ret_ty = "double" then "march_run_blocking_d", "double"
        else "march_run_blocking_i", "i64" in
      let r = fresh ctx "blkr" in
      emit ctx (Printf.sprintf "%s = call %s @%s(ptr @%s, ptr %s, i32 %d)"
                  r hret helper fname arr n);
      (match ret_ty with
       | "void" -> ("i64", "0")
       | "ptr"  -> let p = fresh ctx "blkp" in
                   emit ctx (Printf.sprintf "%s = inttoptr i64 %s to ptr" p r); ("ptr", p)
       | _      -> (ret_ty, r))
    end
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
      let result =
        if ret_ty = "void" then begin
          emit ctx (Printf.sprintf "call void %s(%s)" fp args_str);
          ("i64", "0")
        end else begin
          let r = fresh ctx "cr" in
          emit ctx (Printf.sprintf "%s = call %s %s(%s)" r ret_ty fp args_str);
          (ret_ty, r)
        end
      in
      let v = fresh ctx "hrv" in
      emit ctx (Printf.sprintf "%s = load i32, ptr %s" v vslot);
      emit ctx (Printf.sprintf
        "call void @march_dispatch_leave(i32 %d, i32 %s)" name_id v);
      result
    end
    else if ret_ty = "void" then begin
      emit ctx (Printf.sprintf "call void @%s(%s)" fname args_str);
      ("i64", "0")
    end else begin
      let r = fresh ctx "cr" in
      emit ctx (Printf.sprintf "%s = call %s @%s(%s)" r ret_ty fname args_str);
      (ret_ty, r)
    end

  (* ── ECallPtr to a `raises` extern: env-routed error wrapper ─────────── *)
  (* defun may emit extern calls as ECallPtr.  Catch `raises` externs here —
     before the generic global-call arms — so they get the march_env* wrapper
     (the EApp path handles the same via emit_raises_wrapper). *)
  | Tir.ECallPtr (Tir.AVar f, args)
    when (not (Hashtbl.mem ctx.var_slot (llvm_name f.Tir.v_name)))
      && (let rn =
            if Hashtbl.mem ctx.top_fns f.Tir.v_name then f.Tir.v_name
            else match Hashtbl.find_opt ctx.unqualified_fns f.Tir.v_name with
              | Some q -> q | None -> f.Tir.v_name in
          Hashtbl.mem ctx.raises_externs rn) ->
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

  (* ── ECallPtr where callee is an unqualified cross-module user function ── *)
  (* lower.ml may emit function references without their module prefix (e.g.
     "base64_encode" for "Crypto.base64_encode").  defun converts EApp of
     non-top-level names to ECallPtr.  If the name has an entry in
     unqualified_fns AND no local alloca slot exists (meaning it's not a
     locally-bound closure variable), emit a direct call to the qualified fn.
     The var_slot guard is critical: a local variable named "abs" must not be
     confused with Math.abs — it would have a slot from its ELet binding. *)
  | Tir.ECallPtr (Tir.AVar f, args)
    when (let base = llvm_name f.Tir.v_name in
          not (Hashtbl.mem ctx.var_slot base))
      && (not (Hashtbl.mem ctx.top_fns f.Tir.v_name))
      && Hashtbl.mem ctx.unqualified_fns f.Tir.v_name ->
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

  (* ── ECallPtr to a record introspection builtin: redirect to the EApp
     special cases above so kind hints and signatures stay correct. *)
  | Tir.ECallPtr (Tir.AVar f, args)
    when (match f.Tir.v_name with
          | "record_keys" | "record_values" | "record_entries"
          | "record_get" | "record_has_key" | "record_put"
          | "record_from_list" -> true
          | _ -> false)
      && not (Hashtbl.mem ctx.var_slot (llvm_name f.Tir.v_name)) ->
    emit_expr ctx (Tir.EApp (f, args))

  (* ── ECallPtr where callee is a known builtin ─────────────────────── *)
  (* Builtins (e.g. vault_update) are not in top_fns, so TIR lowering
     emits them as call_ptr.  Detect this here and emit a direct call
     instead of trying to dispatch through a closure pointer. *)
  | Tir.ECallPtr (Tir.AVar f, args)
    when is_builtin_fn f.Tir.v_name
      && not (Hashtbl.mem ctx.var_slot (llvm_name f.Tir.v_name)) ->
    (* Redirect to the EApp path so builtins get consistent per-argument
       coercion — in particular the vault store builtins (vault_set etc.)
       coerce their heterogeneous value arg to a tagged ptr there.  Emitting
       the call directly here with each arg's natural llvm type would pass a
       Bool/Int value as a raw i64 to march_vault_set(ptr value), storing it
       untagged so Vault.get reads it back wrong. *)
    emit_expr ctx (Tir.EApp (f, args))


  (* ── ECallPtr where callee AVar has no local alloca slot ─────────── *)
  (* The TIR lower pass may emit ECallPtr for cross-module function calls
     when it cannot confirm at lower time that the callee is a top-level
     definition.  If the callee AVar has NO entry in var_slot — meaning
     no alloca was registered for it in the current function — it cannot
     be a locally-bound closure variable, so dispatching through a closure
     struct would read from an undefined "%%name.addr" alloca and produce
     invalid LLVM IR (e.g. "use of undefined value
     '%%Depot.Form.get_errors.addr'").
     In this case emit a direct call to the global function instead.
     This is a safe catch-all: local closure variables (let-bindings,
     parameters) always have a var_slot entry from alloca_name/emit_fn. *)
  | Tir.ECallPtr (Tir.AVar f, args)
    when not (Hashtbl.mem ctx.var_slot (llvm_name f.Tir.v_name)) ->
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
          | "print" | "print_stderr" | "io_read_line" | "read_line" -> true
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

  | Tir.ECallPtr (Tir.AVar f, [a; b])
    when f.Tir.v_name = "int_mod" || f.Tir.v_name = "int_div"
      || f.Tir.v_name = "int_mod_euclid" ->
    let va = emit_atom_as ctx "i64" a in
    let vb = emit_atom_as ctx "i64" b in
    let r  = fresh ctx "ar" in
    (* Same checked-helper routing as the EApp form above. *)
    let helper = match f.Tir.v_name with
      | "int_mod"        -> "march_checked_imod"
      | "int_div"        -> "march_checked_idiv"
      | "int_mod_euclid" -> "march_checked_umod"
      | _                -> assert false
    in
    emit ctx (Printf.sprintf "%s = call i64 @%s(i64 %s, i64 %s)" r helper va vb);
    ("i64", r)

  (* ── Indirect call through closure ────────────────────────────────── *)
  (* fn_atom is a local var holding a ptr to a closure struct.
     Field 0 of the closure is the apply fn ptr.
     Convention: apply fn takes (ptr $clo, original_params…). *)
  | Tir.ECallPtr (fn_atom, args) ->
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
    let fn_ty_str = Printf.sprintf "%s (%s)" ret_ty
        (String.concat ", " ("ptr" :: orig_param_llvm_tys)) in
    let orig_arg_strs = List.map2 (fun pty a ->
        let (actual_ty, v) = emit_atom ctx a in
        let v' = coerce ctx actual_ty v pty in
        pty ^ " " ^ v'
      ) orig_param_llvm_tys args in
    let all_arg_strs = Printf.sprintf "ptr %s" clo_ptr :: orig_arg_strs in
    if ret_ty = "void" then begin
      emit ctx (Printf.sprintf "call %s %s(%s)"
                  fn_ty_str fn_ptr (String.concat ", " all_arg_strs));
      ("i64", "0")
    end else begin
      let r = fresh ctx "cr" in
      emit ctx (Printf.sprintf "%s = call %s %s(%s)"
                  r fn_ty_str fn_ptr (String.concat ", " all_arg_strs));
      (ret_ty, r)
    end

  (* ── Heap allocation ───────────────────────────────────────────────── *)
  | Tir.EAlloc (Tir.TCon (ctor, alloc_params), args) ->
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
    (match Repr.repr_of_ty ctx.type_defs (Tir.TCon (alloc_type_name, [])) with
     | Repr.Newtype payload ->
       audit "Newtype" "alloc";
       (* Newtype: no allocation. Emit the single payload atom directly. *)
       if List.length args <> 1 then
         failwith (Printf.sprintf
           "LLVM emit: newtype constructor %s expects 1 arg, got %d \
            (arity mismatch — malformed TIR)"
           ctor (List.length args));
       let (v_ty, v_val) = emit_atom ctx (List.hd args) in
       if Repr.payload_needs_tag ctx.type_defs payload then begin
         (* Scalar payload: tag (v<<1)|1 so it's odd → IS_HEAP_PTR = false *)
         let i64v = coerce ctx v_ty v_val "i64" in
         let as_ptr = emit_tag_scalar ctx ~sh:"nt_sh" ~tag:"nt_tag" ~ptr:"nt_ptr" i64v in
         ("ptr", as_ptr)
       end else
         (* Pointer payload: pass through raw *)
         ("ptr", coerce ctx v_ty v_val "ptr")
     | _ when Repr.is_niche_shaped ctx.type_defs alloc_type_name ->
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
           Repr.niche_payload_ok ctx.type_defs arg_tir_ty
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
           if Repr.payload_needs_tag ctx.type_defs arg_tir_ty then begin
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
              Repr.niche_payload_ok ctx.type_defs p
              (* Abstract (erased) payload: emit_case's abstract-arg niche path
                 and ensure_adt_eq_fn both treat Option(TVar) as NICHE, so the
                 alloc must too — boxing None here would make a niche match read
                 the non-null cell as Some (caught by MARCH_REPR_AUDIT:
                 case=Niche(Any) vs alloc-none-boxed=Boxed(Any)). *)
              || (match p with Tir.TVar _ -> true | _ -> false)
            | _   -> true  (* no payload info — keep the historical null encoding *)
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
               | Some t -> llvm_ty t | None -> "ptr" in
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
              | Some t -> llvm_ty t | None -> "ptr" in
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
           | Some t -> llvm_ty t
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
       ("ptr", ptr))

  | Tir.EAlloc (_, args) ->
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

  (* ── Stack allocation ──────────────────────────────────────────────── *)
  | Tir.EStackAlloc (Tir.TCon (ctor, _), args) ->
    let entry = ctor_entry ctx ctor (List.length args) in
    let ptr = emit_stack_alloc ctx (List.length args) in
    emit_store_tag ctx ptr entry.ce_tag;
    List.iteri (fun i atom ->
      let field_ty = match List.nth_opt entry.ce_fields i with
        | Some t -> llvm_ty t
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

  | Tir.EStackAlloc (_, args) ->
    (* Non-TCon stack allocation: UNIFORM slots, mirroring EAlloc above. *)
    let n = List.length args in
    let ptr = emit_stack_alloc ctx n in
    List.iteri (fun i atom ->
      let (ty, v) = emit_atom ctx atom in
      let vp = coerce ctx ty v "ptr" in
      emit_store_field ctx ptr i "ptr" vp
    ) args;
    ("ptr", ptr)

  (* ── FBIP reuse (conditional: check RC=1 before reusing in-place) ──── *)
  (* EReuse semantics: if RC=1, reuse in-place; else DecRC + alloc fresh.
     This is critical for correctness when the caller holds extra references
     (e.g. after IncRC before passing to a function). *)
  | Tir.EReuse (reuse_atom, Tir.TCon (ctor, _), args) ->
    (* Newtype fast path: no heap cell to reuse. Emit new payload directly.
       The old reuse_atom is a tagged scalar or pointer; release it via
       march_decrc (IS_HEAP_PTR guards make it a no-op on tagged scalars). *)
    let reuse_type_name = match String.rindex_opt ctor '.' with
      | Some i -> String.sub ctor 0 i
      | None -> ctor
    in
    (match Repr.repr_of_ty ctx.type_defs (Tir.TCon (reuse_type_name, [])) with
     | Repr.Newtype payload ->
       let (_, rv) = emit_atom ctx reuse_atom in
       emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" rv);
       let (v_ty, v_val) = emit_atom ctx (List.hd args) in
       if Repr.payload_needs_tag ctx.type_defs payload then begin
         let i64v = coerce ctx v_ty v_val "i64" in
         let as_ptr = emit_tag_scalar ctx ~sh:"nt_sh" ~tag:"nt_tag" ~ptr:"nt_ptr" i64v in
         ("ptr", as_ptr)
       end else
         ("ptr", coerce ctx v_ty v_val "ptr")
     | _ when Repr.is_niche_shaped ctx.type_defs reuse_type_name ->
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
           Repr.niche_payload_ok ctx.type_defs arg_tir_ty
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
           if Repr.payload_needs_tag ctx.type_defs arg_tir_ty then begin
             let i64v = coerce ctx v_ty v_val "i64" in
             let as_ptr = emit_tag_scalar ctx ~sh:"niche_sh" ~tag:"niche_tag" ~ptr:"niche_ptr" i64v in
             Some ("ptr", as_ptr)
           end else
             Some ("ptr", coerce ctx v_ty v_val "ptr")
         end
       in
       (match args with
        | [] ->
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
               | Some t -> llvm_ty t | None -> "ptr" in
             let (v_ty, v_val) = emit_atom ctx arg in
             emit_store_field ctx ptr 0 field_ty (coerce ctx v_ty v_val field_ty);
             ("ptr", ptr))
        | _ ->
          let entry = ctor_entry ctx ctor (List.length args) in
          let ptr = emit_heap_alloc ctx entry.ce_tag (List.length args) in
          List.iteri (fun i atom ->
            let field_ty = match List.nth_opt entry.ce_fields i with
              | Some t -> llvm_ty t | None -> "ptr" in
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
       && Repr.is_niche_shaped ctx.type_defs reuse_atom_parent_type
    then begin
      let entry = ctor_entry ctx ctor (List.length args) in
      let ptr = emit_heap_alloc ctx entry.ce_tag (List.length args) in
      List.iteri (fun i atom ->
        let field_ty = match List.nth_opt entry.ce_fields i with
          | Some t -> llvm_ty t
          | None -> failwith (Printf.sprintf
              "LLVM emit: constructor %s has %d field(s) but field index %d \
               was requested (arity mismatch)"
              ctor (List.length entry.ce_fields) i)
        in
        let (v_ty, v_val) = emit_atom ctx atom in
        emit_store_field ctx ptr i field_ty (coerce ctx v_ty v_val field_ty)
      ) args;
      ("ptr", ptr)
    end else begin
    let (_, rv) = emit_atom ctx reuse_atom in
    let entry = ctor_entry ctx ctor (List.length args) in
    (* Pre-compute all arg values before branching *)
    let arg_vals = List.mapi (fun i atom ->
      let field_ty = match List.nth_opt entry.ce_fields i with
        | Some t -> llvm_ty t
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

  | Tir.EReuse (reuse_atom, reuse_ty, args) ->
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
       && Repr.is_niche_shaped ctx.type_defs reuse_atom_parent_type
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
  | Tir.EIncRC atom
    when (atom_is_builtin atom ||
          (match atom with Tir.AVar v -> Hashtbl.mem ctx.top_fns v.Tir.v_name | _ -> false)) &&
         (match atom with Tir.AVar v -> not (Hashtbl.mem ctx.var_slot (llvm_name v.Tir.v_name)) | _ -> true) ->
    ("i64", "0")
  | Tir.EIncRC atom ->
    let (ty, v) = emit_atom ctx atom in
    if ty = "ptr" then
      emit ctx (Printf.sprintf "call void @march_incrc_local(ptr %s)" v);
    ("i64", "0")

  | Tir.EDecRC atom
    when (atom_is_builtin atom ||
          (match atom with Tir.AVar v -> Hashtbl.mem ctx.top_fns v.Tir.v_name | _ -> false)) &&
         (match atom with Tir.AVar v -> not (Hashtbl.mem ctx.var_slot (llvm_name v.Tir.v_name)) | _ -> true) ->
    ("i64", "0")
  | Tir.EDecRC atom ->
    let (ty, v) = emit_atom ctx atom in
    if ty = "ptr" then
      emit ctx (Printf.sprintf "call void @march_decrc_local(ptr %s)" v);
    ("i64", "0")

  | Tir.EAtomicIncRC atom
    when (atom_is_builtin atom ||
          (match atom with Tir.AVar v -> Hashtbl.mem ctx.top_fns v.Tir.v_name | _ -> false)) &&
         (match atom with Tir.AVar v -> not (Hashtbl.mem ctx.var_slot (llvm_name v.Tir.v_name)) | _ -> true) ->
    ("i64", "0")
  | Tir.EAtomicIncRC atom ->
    let (ty, v) = emit_atom ctx atom in
    if ty = "ptr" then
      emit ctx (Printf.sprintf "call void @march_incrc(ptr %s)" v);
    ("i64", "0")

  | Tir.EAtomicDecRC atom
    when (atom_is_builtin atom ||
          (match atom with Tir.AVar v -> Hashtbl.mem ctx.top_fns v.Tir.v_name | _ -> false)) &&
         (match atom with Tir.AVar v -> not (Hashtbl.mem ctx.var_slot (llvm_name v.Tir.v_name)) | _ -> true) ->
    ("i64", "0")
  | Tir.EAtomicDecRC atom ->
    let (ty, v) = emit_atom ctx atom in
    if ty = "ptr" then
      emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" v);
    ("i64", "0")

  | Tir.EFree atom
    when (atom_is_builtin atom ||
          (match atom with Tir.AVar v -> Hashtbl.mem ctx.top_fns v.Tir.v_name | _ -> false)) &&
         (match atom with Tir.AVar v -> not (Hashtbl.mem ctx.var_slot (llvm_name v.Tir.v_name)) | _ -> true) ->
    ("i64", "0")
  | Tir.EFree atom ->
    let (ty, v) = emit_atom ctx atom in
    if ty = "ptr" then
      emit ctx (Printf.sprintf "call void @march_free(ptr %s)" v);
    ("i64", "0")

  (* ── Tuples ────────────────────────────────────────────────────────── *)
  | Tir.ETuple [] -> ("i64", "0")

  | Tir.ETuple atoms ->
    (* Tuple slots use the UNIFORM convention: scalars low-bit tagged via
       coerce i64→ptr, heap values raw.  Every destructure path reads tuple
       fields as ptr (ctor_entry "$TupleN" is never registered, so its
       fallback yields TVar fields) and untags scalar views conditionally —
       storing naturals here silently halved odd ints / flipped true→false
       the moment a tuple passed through any pattern match. *)
    let n = List.length atoms in
    let ptr = emit_heap_alloc ctx 0 n in
    List.iteri (fun i atom ->
      let (ty, v) = emit_atom ctx atom in
      let vp = coerce ctx ty v "ptr" in
      emit_store_field ctx ptr i "ptr" vp
    ) atoms;
    ("ptr", ptr)

  (* ── Records ───────────────────────────────────────────────────────── *)
  | Tir.ERecord fields ->
    (* Sort by field name so layout matches TRecord (sorted by name) *)
    let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) fields in
    let n = List.length sorted in
    let ptr = emit_heap_alloc ctx 0 n in
    List.iteri (fun i (_, atom) ->
      let (ty, v) = emit_atom ctx atom in
      emit_store_field ctx ptr i ty v
    ) sorted;
    (* Stamp the shape id so record introspection builtins can recover the
       field names at runtime. *)
    emit_set_shape ctx ptr
      (List.map (fun (nm, atom) -> (nm, atom_tir_ty atom)) sorted);
    ("ptr", ptr)

  (* ── Field access ──────────────────────────────────────────────────── *)
  | Tir.EField (obj_atom, field_name) ->
    let obj_ty = match obj_atom with
      | Tir.AVar v    -> v.Tir.v_ty
      | Tir.ADefRef _ -> Tir.TVar "_"
      | Tir.ALit _    -> Tir.TVar "_"
    in
    (* Closure free-variable fields: "$fvN" — parse index from name directly
       since the closure pointer is opaque (TPtr TUnit) with no field_map. *)
    if Tir_names.is_fv_field field_name then begin
      let i = Tir_names.fv_field_index field_name in
      let (_, obj_val) = emit_atom ctx obj_atom in
      let fv = emit_load_field ctx obj_val i (llvm_ty (Tir.TPtr Tir.TUnit)) in
      (llvm_ty (Tir.TPtr Tir.TUnit), fv)
    end else begin
      match get_record_fields ctx obj_ty with
      | [] when ctx.shape_meta ->
        (* Statically-unknown record shape (type-erased generic flow, or a
           record extended at runtime by record_put): look the field up by
           name via the shape id.  Result follows the generic ADT-slot
           convention (ints low-bit tagged) — consumers coerce ptr→i64 with
           an untagging ashr.  Cells without shape metadata fall back to the
           legacy raw slot-0 read inside the C helper. *)
        let (_, obj_val) = emit_atom ctx obj_atom in
        let ng = intern_string ctx field_name in
        let res = fresh ctx "cr" in
        emit ctx (Printf.sprintf
          "%s = call ptr @march_record_field_dyn(ptr %s, ptr %s, i64 %d)"
          res obj_val ng (String.length field_name));
        ("ptr", res)
      | _ ->
        let (idx, field_ty) = field_index_for ctx obj_ty field_name in
        let (_, obj_val) = emit_atom ctx obj_atom in
        let fv = emit_load_field ctx obj_val idx (llvm_ty field_ty) in
        (llvm_ty field_ty, fv)
    end

  (* ── Record update ─────────────────────────────────────────────────── *)
  | Tir.EUpdate (base_atom, updates) ->
    let base_ty = match base_atom with
      | Tir.AVar v    -> v.Tir.v_ty
      | Tir.ADefRef _ -> Tir.TVar "_"
      | Tir.ALit _    -> Tir.TVar "_"
    in
    let all_fields = get_record_fields ctx base_ty in
    let (_, base_val) = emit_atom ctx base_atom in
    if all_fields = [] && updates <> [] then begin
      (* Statically-unknown record shape (type-erased generic flow, e.g. the
         result of record_put/record_from_list): field offsets can't be
         computed at compile time, so [field_index_for]'s "(0, TVar _)"
         fallback would make every update write field 0 of a header-only
         cell (n=0 from emit_heap_alloc) — corrupting memory past the
         allocation.  Mirror the EField dyn fallback above: a single call
         to march_record_update_dyn (by-name, shape-registry-aware), which
         copies the base cell ONCE and overwrites the named fields — no
         per-field intermediate allocations.  NOTE: unlike the
         statically-known case, the typechecker CANNOT validate the update
         names here (its TVar branch builds a partial record constraint
         from the update's own names — it never sees the base's actual
         fields), so the runtime panics on a missing name (mirroring
         march_record_field_dyn) instead of silently fabricating a new
         field (march_record_put's new-key behavior) or writing out of
         bounds. *)
      let args = List.concat_map (fun (fname, atom) ->
        let ng = intern_string ctx fname in
        let (vt, vv) = emit_atom ctx atom in
        (* Pass the value in UNIFORM representation, matching record_put's
           EApp call convention: scalars low-bit tagged (coerce i64→ptr),
           raw bits for floats, ptr as-is.  Natural repr is ambiguous — an
           even Int >= 4096 is bit-identical to a heap pointer, so
           rec_field_norm_in's plausible-heap sniff would incrc
           (dereference) the integer's value. *)
        let vp = (match vt with
          | "i64" -> coerce ctx "i64" vv "ptr"
          | "double" ->
            let b = fresh ctx "ruv" in
            let t = fresh ctx "ruv" in
            emit ctx (Printf.sprintf "%s = bitcast double %s to i64" b vv);
            emit ctx (Printf.sprintf "%s = inttoptr i64 %s to ptr" t b);
            t
          | _ -> vv) in
        let kind = shape_kind_char (atom_tir_ty atom) in
        [ Printf.sprintf "ptr %s" ng;
          Printf.sprintf "i64 %d" (String.length fname);
          Printf.sprintf "ptr %s" vp;
          Printf.sprintf "i64 %d" (Char.code kind) ]
      ) updates in
      let res = fresh ctx "ru" in
      emit ctx (Printf.sprintf
        "%s = call ptr (ptr, i64, ...) @march_record_update_dyn(ptr %s, i64 %d, %s)"
        res base_val (List.length updates) (String.concat ", " args));
      ("ptr", res)
    end else begin
    let n = List.length all_fields in
    (* Allocate new record of same size *)
    let ptr = emit_heap_alloc ctx 0 n in
    (* Copy all fields from base *)
    List.iteri (fun i (_, fty) ->
      let fv = emit_load_field ctx base_val i (llvm_ty fty) in
      emit_store_field ctx ptr i (llvm_ty fty) fv
    ) all_fields;
    (* Overwrite updated fields *)
    List.iter (fun (fname, atom) ->
      let (idx, _) = field_index_for ctx base_ty fname in
      let (aty, av) = emit_atom ctx atom in
      emit_store_field ctx ptr idx aty av
    ) updates;
    (* Stamp the shape id on the copy.  When the static shape is known, use
       it; otherwise copy the base record's shape id (header pad word). *)
    if ctx.shape_meta then begin
      if all_fields <> [] then
        emit_set_shape ctx ptr all_fields
      else begin
        let sp = fresh ctx "shp" in
        let sv = fresh ctx "shv" in
        let dp = fresh ctx "shp" in
        emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 12" sp base_val);
        emit ctx (Printf.sprintf "%s = load i32, ptr %s, align 4" sv sp);
        emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 12" dp ptr);
        emit ctx (Printf.sprintf "store i32 %s, ptr %s, align 4" sv dp)
      end
    end;
    ("ptr", ptr)
    end

  (* ── Case expression ───────────────────────────────────────────────── *)
  | Tir.ECase (scrut_atom, branches, default_opt) ->
    (* emit_case moved to [Llvm_case] (Wave 3 Task 5, chunk 2): it was
       mutually recursive with emit_expr via [and]; emit_expr/emit_atom are
       now passed as callback parameters (the standard de-cycling move) so
       Llvm_case need not depend back on this file. Same call graph, same
       behavior — see Llvm_case's header comment. *)
    Llvm_case.emit_case ~emit_expr ~emit_atom ctx scrut_atom branches default_opt

  (* ── LetRec (inner lambdas after defun — just emit the body) ───────── *)
  | Tir.ELetRec (_fns, body) ->
    emit_expr ctx body

(* emit_case's definition (formerly here, joined to emit_expr via [and]) now
   lives in [Llvm_case.emit_case]; see the ECase arm above. *)

(* ── Mutual TCO: call graph analysis ────────────────────────────────── *)

(* The is_trivial_dec_chain_returning predicate used throughout this section
   is defined ONCE, earlier in this file (just after emit_raises_wrapper) —
   a byte-identical duplicate that used to sit here as an OCaml
   forward-reference workaround was deleted in the Wave 3 Task 5 (chunk 2)
   split; see the single definition's doc comment. *)

(** Collect all function names that are called in TAIL position in [expr].
    Only traverses tail-position sub-expressions. *)
let rec tail_calls_in (expr : Tir.expr) : string list =
  match expr with
  | Tir.EApp (f, _) -> [f.Tir.v_name]
  | Tir.ELet (tmp_v, Tir.EApp (f, _), body)
    when is_trivial_dec_chain_returning tmp_v.Tir.v_name body ->
    (* Borrow-induced post-DecRC wrapper: the EApp is semantically the tail. *)
    [f.Tir.v_name]
  | Tir.ELet (_, _, body) -> tail_calls_in body
  | Tir.ESeq (_, e2) -> tail_calls_in e2
  | Tir.ECase (_, branches, default_opt) ->
    List.concat_map (fun br -> tail_calls_in br.Tir.br_body) branches
    @ (match default_opt with Some d -> tail_calls_in d | None -> [])
  | Tir.ELetRec (_, body) -> tail_calls_in body
  | _ -> []

(** True if [expr] contains a call to any member of [group] that is NOT in
    tail position.  [in_tail] tracks whether we are currently on a tail path.
    - ELet rhs is non-tail; body inherits [in_tail].
    - ESeq e1 is non-tail; e2 inherits [in_tail].
    - ECase arm bodies inherit [in_tail].
    - ELetRec inner fn bodies: calls there are relative to those fns, not the
      outer function, so we treat them as non-tail for outer-group purposes. *)
let rec has_non_tail_group_call (group : string list) ~(in_tail : bool)
    (expr : Tir.expr) : bool =
  match expr with
  | Tir.EApp (f, _) -> List.mem f.Tir.v_name group && not in_tail
  | Tir.ELet (tmp_v, Tir.EApp (f, _), body)
    when is_trivial_dec_chain_returning tmp_v.Tir.v_name body ->
    (* Borrow-induced post-DecRC wrapper: the EApp is semantically the tail
       call IFF this whole ELet is itself in tail position.  Body contains
       only DecRC/Free ops + the trailing EAtom — no further calls that
       could be non-tail on their own, so once we know the wrapped call is
       disqualifying we don't need to recurse into body.  Mirror the bare
       EApp arm above: a wrapped call to a group member is a non-tail group
       call whenever [in_tail] is false here (e.g. this ELet is the rhs of
       an outer ELet/ESeq).  Before this guard, the wrapped call was always
       treated as the tail call regardless of [in_tail], so a non-tail
       Perceus-wrapped group call could slip a mutual SCC through group
       formation, and the mutual-TCO emission then stranded the
       continuation in a dead block. *)
    (List.mem f.Tir.v_name group && not in_tail)
    || has_non_tail_group_call group ~in_tail body
  | Tir.ELet (_, rhs, body) ->
    has_non_tail_group_call group ~in_tail:false rhs
    || has_non_tail_group_call group ~in_tail body
  | Tir.ESeq (e1, e2) ->
    has_non_tail_group_call group ~in_tail:false e1
    || has_non_tail_group_call group ~in_tail e2
  | Tir.ECase (_, branches, default_opt) ->
    List.exists (fun br -> has_non_tail_group_call group ~in_tail br.Tir.br_body)
      branches
    || (match default_opt with
        | Some d -> has_non_tail_group_call group ~in_tail d
        | None -> false)
  | Tir.ELetRec (fns, body) ->
    (* Calls inside inner local functions are in those functions' own tail
       positions, not the outer function's.  Conservatively block mutual TCO
       if any inner fn non-tail-calls a group member (inner bodies are not the
       outer tail position regardless). *)
    List.exists (fun fn ->
      has_non_tail_group_call group ~in_tail:true fn.Tir.fn_body) fns
    || has_non_tail_group_call group ~in_tail body
  | _ -> false

(** Tarjan's SCC algorithm over the tail-call graph of [fns].
    Returns a list of SCCs, each SCC being a list of fn_names. *)
let tarjan_sccs (fns : Tir.fn_def list) : string list list =
  let fn_names = List.map (fun fn -> fn.Tir.fn_name) fns in
  (* tail-call adjacency: name -> [names tail-called within the module] *)
  let tail_adj = List.map (fun fn ->
    let tcs = tail_calls_in fn.Tir.fn_body in
    let within = List.sort_uniq String.compare
      (List.filter (fun n -> List.mem n fn_names) tcs) in
    (fn.Tir.fn_name, within)
  ) fns in
  let index_ctr = ref 0 in
  let stack     = ref [] in
  let on_stack  = Hashtbl.create 16 in
  let indices   = Hashtbl.create 16 in
  let lowlinks  = Hashtbl.create 16 in
  let sccs      = ref [] in
  let rec strongconnect v =
    let idx = !index_ctr in
    Hashtbl.replace indices  v idx;
    Hashtbl.replace lowlinks v idx;
    incr index_ctr;
    stack := v :: !stack;
    Hashtbl.replace on_stack v true;
    let neighbors = try List.assoc v tail_adj with Not_found -> [] in
    List.iter (fun w ->
      if not (Hashtbl.mem indices w) then begin
        strongconnect w;
        let vll = Hashtbl.find lowlinks v in
        let wll = Hashtbl.find lowlinks w in
        Hashtbl.replace lowlinks v (min vll wll)
      end else if Hashtbl.mem on_stack w then begin
        let vll = Hashtbl.find lowlinks v in
        let widx = Hashtbl.find indices w in
        Hashtbl.replace lowlinks v (min vll widx)
      end
    ) neighbors;
    if Hashtbl.find lowlinks v = Hashtbl.find indices v then begin
      let scc = ref [] in
      let go  = ref true in
      while !go do
        let w = List.hd !stack in
        stack := List.tl !stack;
        Hashtbl.remove on_stack w;
        scc := w :: !scc;
        if String.equal w v then go := false
      done;
      sccs := !scc :: !sccs
    end
  in
  List.iter (fun name ->
    if not (Hashtbl.mem indices name) then strongconnect name
  ) fn_names;
  !sccs

(** Given the full list of top-level functions, return groups of ≥ 2 functions
    that qualify for mutual TCO.  A group qualifies when:
    1. Its functions form a non-trivial SCC in the tail-call graph (size ≥ 2).
    2. No function in the group makes a non-tail call to any other group member.
    3. All functions in the group have the same LLVM return type (required for
       the shared loop to produce one result type). *)
let find_mutual_tco_groups (fns : Tir.fn_def list) : Tir.fn_def list list =
  let fn_map = List.map (fun fn -> (fn.Tir.fn_name, fn)) fns in
  let sccs = tarjan_sccs fns in
  List.filter_map (fun scc ->
    if List.length scc < 2 then None
    else begin
      let group_fns = List.filter_map (fun name ->
        try Some (List.assoc name fn_map) with Not_found -> None) scc in
      let group_names = List.map (fun fn -> fn.Tir.fn_name) group_fns in
      (* All cross-group calls must be tail calls *)
      let all_tail =
        List.for_all (fun fn ->
          not (has_non_tail_group_call group_names ~in_tail:true fn.Tir.fn_body)
        ) group_fns
      in
      (* All functions must have the same LLVM return type *)
      let ret_tys = List.map (fun fn -> llvm_ret_ty fn.Tir.fn_ret_ty) group_fns in
      let all_same_ret = match ret_tys with
        | [] | [_] -> true
        | h :: t   -> List.for_all (String.equal h) t
      in
      if all_tail && all_same_ret then Some group_fns
      else None
    end
  ) sccs

(* ── Mutual TCO: combined function name ─────────────────────────────── *)

(** Stable mangled name for the combined function of a mutual-TCO group. *)
let mutual_tco_combined_name (group : Tir.fn_def list) : string =
  "__mutco_" ^
  String.concat "_" (List.map (fun fn -> llvm_name fn.Tir.fn_name) group) ^
  "__"

(* ── TCO helper ──────────────────────────────────────────────────────── *)

(** Return true if [expr] contains a tail-position call to [fn_name].
    Only traverses sub-expressions that are in tail position:
    - ELet body (not rhs)
    - ESeq: second operand, or first operand when the first is a self-call
      followed only by RC cleanup (borrow inference may emit
      ESeq(EApp(self,...), EDecRC(arg)) — the EDecRC lands in dead code
      after TCO emits the back-edge, so it is safe to treat e1 as a tail call)
    - ECase branch bodies and default
    - ELetRec body
    A bare EApp whose callee name matches is a tail call. *)
let rec has_self_tail_call (fn_name : string) (expr : Tir.expr) : bool =
  match expr with
  | Tir.EApp (f, _) -> String.equal f.Tir.v_name fn_name
  | Tir.ELet (tmp_v, Tir.EApp (f, _), body)
    when String.equal f.Tir.v_name fn_name
         && is_trivial_dec_chain_returning tmp_v.Tir.v_name body ->
    (* Borrow-induced post-DecRC wrapper around a self call.  Recognise it
       so TCO sees the call.  (Self calls usually keep ESeq form via the
       is_self_call branch in perceus.ml, but the ELet form arises when the
       call is via an indirect alias.) *)
    true
  | Tir.ELet (_, _, body) -> has_self_tail_call fn_name body
  | Tir.ESeq (e1, e2) ->
    has_self_tail_call fn_name e2 ||
    has_self_tail_call fn_name e1
  | Tir.ECase (_, branches, default_opt) ->
    List.exists (fun br -> has_self_tail_call fn_name br.Tir.br_body) branches ||
    (match default_opt with Some d -> has_self_tail_call fn_name d | None -> false)
  | Tir.ELetRec (_, body) -> has_self_tail_call fn_name body
  | _ -> false

(* ── Function emitter ────────────────────────────────────────────────── *)

let emit_fn ctx (fn : Tir.fn_def) =
  Hashtbl.clear ctx.local_names;
  Hashtbl.clear ctx.var_slot;
  Hashtbl.clear ctx.var_llvm_ty;
  ctx.ret_ty <- fn.Tir.fn_ret_ty;
  ctx.cur_emit_fn <- fn.Tir.fn_name;
  ctx.hr_cur_module <- module_of_name fn.Tir.fn_name;
  let fn_llvm_name = mangle_extern fn.Tir.fn_name in
  (* Closure apply wrappers use the generic ptr ABI (see [is_apply_fn]) so a
     single calling convention works regardless of whether the lambda's return
     type was inferred concretely or left polymorphic.  The body result is
     coerced to ptr below (tagging scalars), matching what every call site
     reads.  void wrappers keep void — there is no value to carry. *)
  let ret_ty =
    let base = llvm_ret_ty fn.Tir.fn_ret_ty in
    if is_apply_fn fn.Tir.fn_name && base <> "void" then "ptr" else base
  in

  (* Detect self-tail-recursion: only do TCO when the function calls itself
     in tail position and is not a closure apply fn (those have a clo arg).
     TCO is enabled whenever ANY self-call is in tail position; the back-edge
     transform in emit_expr is gated on [ctx.tco_in_tail] so that NON-tail
     self-calls (which also occur in mixed functions, e.g. the recursive call
     inside `Cons(x, f(t))`) emit an ordinary call instead of a loop back-edge.
     Without that gate the non-tail call would be turned into a back-edge and
     the surrounding construction silently dropped — a miscompile. *)
  let is_tco =
    has_self_tail_call fn.Tir.fn_name fn.Tir.fn_body
    && not (is_builtin_fn fn.Tir.fn_name)
  in

  let params_str = String.concat ", " (List.map (fun (v : Tir.var) ->
      let vn = llvm_name v.Tir.v_name in
      llvm_param_ty ~type_defs:ctx.type_defs v.Tir.v_ty ^ " %" ^ vn ^ ".arg"
    ) fn.Tir.fn_params) in

  (* In --compile-so mode, give every non-exported function hidden ELF
     visibility so intra-.so PLT calls resolve to the .so's own definitions
     without going through the process global symbol table (where v1 symbols
     from the server binary would otherwise win).
     Exported symbols that must stay default-visible:
       *_dispatch      — the reload server finds these with dlsym(ACTIVATE)
       *_migrate_state — the __migrate_* alias points to this function; a
                         hidden aliasee with a default-visibility alias is not
                         valid LLVM IR, so keep the migrate_state fn visible *)
  let vis_prefix =
    let fname = fn.Tir.fn_name in
    let flen  = String.length fname in
    let ends_with sfx =
      let sl = String.length sfx in
      flen > sl && String.sub fname (flen - sl) sl = sfx
    in
    if ctx.compile_so
       && not (Tir_names.is_actor_dispatch_fn fname)
       && not (ends_with "_migrate_state")
    then "hidden "
    else ""
  in
  Buffer.add_string ctx.buf
    (Printf.sprintf "\ndefine %s%s @%s(%s) {\nentry:\n" vis_prefix ret_ty fn_llvm_name params_str);

  (* Alloca + store for each parameter; collect slot info for TCO. *)
  let param_slots = List.map (fun (v : Tir.var) ->
    let ty = llvm_ty v.Tir.v_ty in
    let slot = alloca_name ctx (llvm_name v.Tir.v_name) in
    emit ctx (Printf.sprintf "%%%s.addr = alloca %s" slot ty);
    emit ctx (Printf.sprintf "store %s %%%s.arg, ptr %%%s.addr" ty (llvm_name v.Tir.v_name) slot);
    Hashtbl.replace ctx.var_llvm_ty slot ty;
    (v.Tir.v_name, slot, ty)
  ) fn.Tir.fn_params in

  (* Phase 4: leaf-function detection.  A function is a leaf if its body
     contains no non-builtin calls and no indirect calls (ECallPtr).  Leaf
     functions are provably-terminating (they finish in O(1) time per call)
     and therefore do not need a reduction check. *)
  let is_leaf = not (expr_has_call fn.Tir.fn_body) in

  if is_tco then begin
    (* Emit: entry → loop.  The loop block header is the back-edge target. *)
    let loop_lbl = fresh_block ctx "tco_loop" in
    emit_term ctx (Printf.sprintf "br label %%%s" loop_lbl);
    emit_label ctx loop_lbl;
    (* Phase 4: decrement the reduction budget at every loop iteration.
       TCO functions are never leaf (they call themselves), so the check is
       always needed here. *)
    emit_reduction_check ctx;
    (* Snapshot the stack pointer at the top of each iteration so that any
       `alloca` textually inside the loop body (case-branch bindings, struct
       construction, etc.) — which LLVM must treat as a fresh dynamic
       allocation on every dynamic execution of the alloca instruction, since
       it cannot prove the loop runs once — gets freed before the next
       iteration via llvm.stackrestore at each back-edge. Without this, stack
       space accumulates unboundedly across iterations and large loops
       (e.g. folding a 10k-element list) crash with a stack overflow despite
       the loop itself being O(1) stack via the back-edge. *)
    let stack_save = fresh ctx "sp.save" in
    emit ctx (Printf.sprintf "%s = call ptr @llvm.stacksave()" stack_save);
    (* Install TCO context so EApp to self emits a back-edge instead of a call. *)
    ctx.tco_fn_name    <- Some fn.Tir.fn_name;
    ctx.tco_loop_label <- loop_lbl;
    ctx.tco_param_info <- param_slots;
    ctx.tco_in_tail    <- true;
    ctx.tco_stack_save <- stack_save;
    let (body_ty, body_val) = emit_expr ctx fn.Tir.fn_body in
    (* Clear TCO state before emitting any other function. *)
    ctx.tco_fn_name <- None;
    ctx.tco_stack_save <- "";
    if ret_ty = "void" then
      emit_term ctx "ret void"
    else begin
      let final_val = coerce ctx body_ty body_val ret_ty in
      emit_term ctx (Printf.sprintf "ret %s %s" ret_ty final_val)
    end
  end else begin
    (* Phase 4: insert the reduction check at function entry for non-leaf
       non-TCO functions.  This fires once per call, counting every function
       invocation against the budget. *)
    if not is_leaf then emit_reduction_check ctx;
    let (body_ty, body_val) = emit_expr ctx fn.Tir.fn_body in
    if ret_ty = "void" then
      emit_term ctx "ret void"
    else begin
      let final_val = coerce ctx body_ty body_val ret_ty in
      emit_term ctx (Printf.sprintf "ret %s %s" ret_ty final_val)
    end
  end;

  Buffer.add_string ctx.buf "}\n"

(** Return the LLVM `declare` string for a function, for use as a forward
    declaration in subsequent JIT fragments that reference it without redefining it. *)
let fn_declare_str (fn : Tir.fn_def) : string =
  let fn_llvm_name = mangle_extern fn.Tir.fn_name in
  let ret_ty = llvm_ret_ty fn.Tir.fn_ret_ty in
  let param_tys = String.concat ", " (List.map (fun (v : Tir.var) ->
      llvm_param_ty v.Tir.v_ty) fn.Tir.fn_params) in
  Printf.sprintf "declare %s @%s(%s)" ret_ty fn_llvm_name param_tys

(* ── Mutual TCO: combined function emitter ───────────────────────────── *)

(** Emit the combined dispatch function and per-function wrapper stubs for
    [group].  After this call the caller must NOT emit any of the original
    [group] functions via [emit_fn] — the wrappers have been emitted here.

    Combined function layout:
      define RET @__mutco_f_g__(i64 %__tag__.arg,
                                Tf1 %f__p1.arg, ...,
                                Tg1 %g__p1.arg, ...) {
      entry:
        alloca tag_slot, param_slots ...
        br %mutual_loop
      mutual_loop:
        %tag = load tag_slot
        switch tag [ 0 -> case_f, 1 -> case_g, ... ]
      case_f:   ; f's body, mutual calls become: store tag+args → br loop
      case_g:   ; g's body, mutual calls become: store tag+args → br loop
      dead:
        unreachable
      }

    Wrapper for f:
      define RET @f(Tf1 %p1, ...) {
        %r = call RET @__mutco__(0, p1, ..., undef, ...)
        ret RET %r
      }
*)
let emit_mutual_tco_group ctx (group : Tir.fn_def list) =
  (* Reset naming state for this combined function — same as emit_fn does at
     the top of each function, but here we do it once for the whole group so
     that local_names accumulates across all case bodies and never resets mid-
     function, which would produce duplicate %name.addr alloca definitions. *)
  Hashtbl.clear ctx.local_names;
  Hashtbl.clear ctx.var_slot;
  Hashtbl.clear ctx.var_llvm_ty;
  let group_names = List.map (fun fn -> fn.Tir.fn_name) group in
  let combined    = mutual_tco_combined_name group in
  let ret_ty      = llvm_ret_ty (List.hd group).Tir.fn_ret_ty in

  (* Assign integer dispatch tags in list order. *)
  let fn_tags = List.mapi (fun i fn -> (fn.Tir.fn_name, i)) group in

  (* Build a flat list of (fn_name, var, combined_slot_base) for ALL params.
     Each param slot is prefixed with the owning function's mangled name to
     avoid collisions between functions with identically-named parameters. *)
  let all_params : (string * Tir.var * string) list =
    List.concat_map (fun fn ->
      List.map (fun (v : Tir.var) ->
        let base = llvm_name fn.Tir.fn_name ^ "__" ^ llvm_name v.Tir.v_name in
        (fn.Tir.fn_name, v, base)
      ) fn.Tir.fn_params
    ) group
  in

  (* ── Emit the combined function definition ───────────────────────── *)
  let tag_param_str = "i64 %__tag__.arg" in
  let rest_params_str =
    if all_params = [] then ""
    else ", " ^ String.concat ", "
      (List.map (fun (_, (v : Tir.var), base) ->
        Printf.sprintf "%s %%%s.arg" (llvm_param_ty ~type_defs:ctx.type_defs v.Tir.v_ty) base
      ) all_params)
  in
  let mutco_vis = if ctx.compile_so then "hidden " else "" in
  Buffer.add_string ctx.buf
    (Printf.sprintf "\ndefine %s%s @%s(%s%s) {\nentry:\n"
       mutco_vis ret_ty (llvm_name combined) tag_param_str rest_params_str);

  (* Alloca the dispatch tag slot. *)
  let tag_slot = "mutco_tag" in
  emit ctx (Printf.sprintf "%%%s.addr = alloca i64" tag_slot);
  emit ctx (Printf.sprintf "store i64 %%__tag__.arg, ptr %%%s.addr" tag_slot);

  (* Alloca each parameter slot and store the incoming arg. *)
  let fn_param_slots : (string * (string * string * string) list) list =
    List.map (fun fn ->
      let slots = List.map (fun (v : Tir.var) ->
        let base = llvm_name fn.Tir.fn_name ^ "__" ^ llvm_name v.Tir.v_name in
        let ty   = llvm_ty v.Tir.v_ty in
        emit ctx (Printf.sprintf "%%%s.addr = alloca %s" base ty);
        emit ctx (Printf.sprintf "store %s %%%s.arg, ptr %%%s.addr" ty base base);
        Hashtbl.replace ctx.var_llvm_ty base ty;
        (v.Tir.v_name, base, ty)
      ) fn.Tir.fn_params in
      (fn.Tir.fn_name, slots)
    ) group
  in

  (* Jump to loop header. *)
  let loop_lbl = fresh_block ctx "mutual_loop" in
  emit_term ctx (Printf.sprintf "br label %%%s" loop_lbl);
  emit_label ctx loop_lbl;

  (* Phase 4: decrement the reduction budget at every loop iteration, exactly
     as emit_fn's self-TCO path does at the top of tco_loop. A mutual-TCO
     group is never leaf (each member tail-calls another group member), so a
     pure mutually-recursive loop (e.g. is_even/is_odd) would otherwise never
     yield back to the scheduler and would monopolize its worker forever. *)
  emit_reduction_check ctx;

  (* Snapshot the stack pointer at the top of each iteration — see
     tco_stack_save's doc comment for why this is required. Every case body's
     back-edge restores to this point before re-entering the loop header. *)
  let mutual_stack_save = fresh ctx "mutco_sp.save" in
  emit ctx (Printf.sprintf "%s = call ptr @llvm.stacksave()" mutual_stack_save);

  (* Load the dispatch tag and emit a switch. *)
  let tag_v    = fresh ctx "mutco_tag_v" in
  let dead_lbl = fresh_block ctx "mutco_dead" in
  emit ctx (Printf.sprintf "%s = load i64, ptr %%%s.addr" tag_v tag_slot);

  let case_labels = List.map (fun fn ->
    let lbl = fresh_block ctx ("mutco_case_" ^ llvm_name fn.Tir.fn_name) in
    (fn, lbl)
  ) group in

  let switch_entries = String.concat " "
    (List.map2 (fun (fn, lbl) (_, tag_int) ->
      Printf.sprintf "i64 %d, label %%%s" tag_int lbl
      |> (fun s -> ignore fn; s)
    ) case_labels fn_tags)
  in
  emit ctx (Printf.sprintf "switch i64 %s, label %%%s [ %s ]"
    tag_v dead_lbl switch_entries);

  (* Install mutual TCO context.  The EApp handler uses this to redirect
     tail calls to group members back to the loop header. *)
  ctx.mutual_tco_group      <- group_names;
  ctx.mutual_tco_tag_slot   <- tag_slot;
  ctx.mutual_tco_loop_label <- loop_lbl;
  ctx.mutual_tco_fn_params  <- fn_param_slots;
  ctx.mutual_tco_fn_tags    <- fn_tags;
  ctx.mutual_tco_stack_save <- mutual_stack_save;

  (* Emit each case body. *)
  List.iter (fun (fn, case_lbl) ->
    emit_label ctx case_lbl;
    (* Reset per-case variable environment but NOT local_names: all case bodies
       live inside the same LLVM function, so alloca name uniquification must
       persist across case bodies to prevent duplicate %name.addr definitions. *)
    Hashtbl.clear ctx.var_slot;
    Hashtbl.clear ctx.var_llvm_ty;
    let fn_slots = List.assoc fn.Tir.fn_name fn_param_slots in
    List.iter (fun (vname, slot, ty) ->
      Hashtbl.replace ctx.var_slot    vname slot;
      Hashtbl.replace ctx.var_llvm_ty slot   ty
    ) fn_slots;
    (* Re-populate var_llvm_ty for all group slots (needed if a case body
       loads another group member's slot via a phi / load path). *)
    List.iter (fun (_, slots) ->
      List.iter (fun (_, slot, ty) ->
        Hashtbl.replace ctx.var_llvm_ty slot ty
      ) slots
    ) fn_param_slots;
    ctx.ret_ty <- fn.Tir.fn_ret_ty;
    let (body_ty, body_val) = emit_expr ctx fn.Tir.fn_body in
    if ret_ty = "void" then
      emit_term ctx "ret void"
    else begin
      let final_val = coerce ctx body_ty body_val ret_ty in
      emit_term ctx (Printf.sprintf "ret %s %s" ret_ty final_val)
    end
  ) case_labels;

  (* Dead / unreachable default arm. *)
  emit_label ctx dead_lbl;
  emit ctx "unreachable";

  Buffer.add_string ctx.buf "}\n";

  (* Clear mutual TCO context. *)
  ctx.mutual_tco_group <- [];
  ctx.mutual_tco_stack_save <- "";

  (* ── Emit wrapper functions ──────────────────────────────────────── *)
  (* Each original function name becomes a thin wrapper that sets the
     dispatch tag and calls the combined function. *)
  List.iter (fun fn ->
    let tag_int     = List.assoc fn.Tir.fn_name fn_tags in
    let fn_llvm     = mangle_extern fn.Tir.fn_name in
    let params_str  = String.concat ", "
      (List.map (fun (v : Tir.var) ->
        Printf.sprintf "%s %%%s.arg" (llvm_param_ty ~type_defs:ctx.type_defs v.Tir.v_ty) (llvm_name v.Tir.v_name)
      ) fn.Tir.fn_params)
    in
    let wrap_vis =
      let fname = fn.Tir.fn_name in
      let flen  = String.length fname in
      let ends_with sfx =
        let sl = String.length sfx in
        flen > sl && String.sub fname (flen - sl) sl = sfx
      in
      if ctx.compile_so
         && not (Tir_names.is_actor_dispatch_fn fname)
         && not (ends_with "_migrate_state")
      then "hidden " else ""
    in
    Buffer.add_string ctx.buf
      (Printf.sprintf "\ndefine %s%s @%s(%s) {\nentry:\n" wrap_vis ret_ty fn_llvm params_str);

    (* Build the call arguments: tag first, then ALL params of ALL group fns.
       For this function's own params, pass the incoming arg.
       For other functions' params, pass undef (they will not be read). *)
    let call_args =
      Printf.sprintf "i64 %d" tag_int ^
      (if all_params = [] then ""
       else ", " ^ String.concat ", "
         (List.map (fun (owner_fn, (v : Tir.var), base) ->
           let ty = llvm_ty v.Tir.v_ty in
           if String.equal owner_fn fn.Tir.fn_name then
             Printf.sprintf "%s %%%s.arg" ty (llvm_name v.Tir.v_name)
           else
             Printf.sprintf "%s undef" ty
           |> (fun s -> ignore base; s)
         ) all_params))
    in
    let result_v = fresh ctx "mutco_wr" in
    if ret_ty = "void" then begin
      emit ctx (Printf.sprintf "call void @%s(%s)" (llvm_name combined) call_args);
      emit_term ctx "ret void"
    end else begin
      emit ctx (Printf.sprintf "%s = call %s @%s(%s)"
        result_v ret_ty (llvm_name combined) call_args);
      emit_term ctx (Printf.sprintf "ret %s %s" ret_ty result_v)
    end;
    Buffer.add_string ctx.buf "}\n"
  ) group

(* ── Module emitter ──────────────────────────────────────────────────── *)

let build_ctor_info ctx (m : Tir.tir_module) =
  List.iter (fun td ->
    match td with
    | Tir.TDVariant (_name, ctors) ->
      (* Collect free type-variable names in declaration order for poly resolution *)
      let seen = Hashtbl.create 4 in
      let params = ref [] in
      let rec collect_tvars = function
        | Tir.TVar n ->
          if not (Hashtbl.mem seen n) then begin
            Hashtbl.add seen n ();
            params := n :: !params
          end
        | Tir.TCon (_, args) -> List.iter collect_tvars args
        | Tir.TFn (ps, r)   -> List.iter collect_tvars ps; collect_tvars r
        | Tir.TTuple ts     -> List.iter collect_tvars ts
        | Tir.TPtr t        -> collect_tvars t
        | _                 -> ()
      in
      List.iter (fun (_, field_tys) -> List.iter collect_tvars field_tys) ctors;
      let param_names = List.rev !params in
      Hashtbl.replace ctx.type_params _name param_names;
      List.iteri (fun tag_idx (ctor_name, field_tys) ->
        (* Use a type-qualified key "TypeName.CtorName" so that two different
           ADTs with the same constructor name (e.g. List.Cons and Tree.Cons)
           never collide in ctor_info.  lower.ml embeds the same qualified key
           in EAlloc (TCon ("TypeName.CtorName", [])), and emit_case qualifies
           br_tag with scrut_tir_ty before the lookup.
           Use first-wins semantics to avoid collisions when two types from
           different modules share the same short name (e.g. Depot.Query.Query
           and Ast.Query both lower to TDVariant("Query", ...)). *)
        let key = _name ^ "." ^ ctor_name in
        if not (Hashtbl.mem ctx.ctor_info key) then
          Hashtbl.replace ctx.ctor_info key { ce_tag = tag_idx; ce_fields = field_tys };
        if not (Hashtbl.mem ctx.poly_ctors (_name, ctor_name)) then
          Hashtbl.replace ctx.poly_ctors (_name, ctor_name) field_tys
      ) ctors
    | Tir.TDRecord (_name, fields) ->
      Hashtbl.replace ctx.ctor_info _name
        { ce_tag = 0; ce_fields = List.map snd fields };
      Hashtbl.replace ctx.field_map _name fields
    | Tir.TDClosure (_name, field_tys) ->
      Hashtbl.replace ctx.ctor_info _name
        { ce_tag = 0; ce_fields = field_tys }
  ) m.Tir.tm_types

(** Emit the LLVM preamble (`declare`d externs for the C runtime / every
    builtin). Wave 3 Task 4 (chunk 2): the ~400-line hand-written declare
    blob moved to [Llvm_builtins.emit_preamble] (generated from the same
    table that drives [is_builtin_fn]/[builtin_ret_ty]/[mangle_extern]
    above) — see its module doc for the byte-identical-reproduction
    guarantee (HAZARD H2) and test/test_codegen.ml's preamble byte-diff
    test for the enforcement. This wrapper preserves the public signature
    (default [~target:Native], optional [~repl]) and translates
    [target_config] to the plain [is_wasm]/[triple] values Llvm_builtins
    needs — Llvm_builtins does not depend on [target_config] to avoid a
    module cycle. *)
let emit_preamble ?(target=Native) ?(repl=false) (buf : Buffer.t) =
  Llvm_builtins.emit_preamble ~is_wasm:(is_wasm_target target) ~triple:(target_triple target) ~repl buf

let emit_main_wrapper (buf : Buffer.t) =
  Buffer.add_string buf
    "\ndeclare void @march_process_argv_init(i32 %argc, ptr %argv)\n\
     declare void @march_spawn_main(ptr %fn)\n\
     define i32 @main(i32 %argc, ptr %argv) {\nentry:\n\
       call void @march_process_argv_init(i32 %argc, ptr %argv)\n\
       call void @march_spawn_main(ptr @march_main)\n\
       call void @march_run_scheduler()\n\
       ret i32 0\n}\n"

let emit_module ?(fast_math=false) ?(pmap_threshold=1024) ?(target=Native)
    ?(hot_reload=None) ?(impl_hashes=(Hashtbl.create 0 : (string, string) Hashtbl.t))
    ?(remote_impl_hashes=(Hashtbl.create 0 : (string, string) Hashtbl.t))
    ?(remote_sig_hashes=(Hashtbl.create 0 : (string, string) Hashtbl.t))
    ?(emit_main=true)
    (m : Tir.tir_module) : string =
  (* type defs are threaded via ctx.type_defs (set below); reset the
     repr-consistency audit per module emission. *)
  Hashtbl.reset _repr_audit;
  (* Hot Code Reload: intern the names of every reloadable (boundary) function
     into NAME_IDs for the dispatch table.
     Actor dispatch functions (e.g. Counter_dispatch) have no module prefix in
     TIR because lower.ml strips the top-level file-module name from all
     declarations (only nested submodule functions retain their prefix).
     We include any *_dispatch function unconditionally so that actor hot-reload
     works when the --hot-reload boundary is the file-level module. *)
  let is_actor_dispatch_fn = Tir_names.is_actor_dispatch_fn in
  let hr_names =
    match hot_reload with
    | None -> Hot_reload.Name_table.build []
    | Some cfg ->
      m.Tir.tm_fns
      |> List.filter_map (fun fn ->
           let n = fn.Tir.fn_name in
           if Hot_reload.is_reloadable cfg (module_of_name n)
              || is_actor_dispatch_fn n
           then Some n else None)
      |> Hot_reload.Name_table.build
  in
  let ctx = make_ctx ~fast_math ~pmap_threshold ~hot_reload ~hr_names
      ~type_defs:m.Tir.tm_types () in
  (* Patch .so: hide all non-exported symbols so intra-.so PLT calls prefer the
     .so's own definitions over same-named symbols in the server binary.  This
     is the compile-time complement to RTLD_DEEPBIND (which is Linux-only). *)
  let ctx = { ctx with compile_so = not emit_main } in
  (* Phase 9: in .so patch mode WITH hot-reload enabled, emit the file-static
     epoch cell into the preamble.  Static (private) linkage keeps it out of
     the global symbol table so multiple deployed .so files don't collide.
     @__march_init (exported) lets the reload server stamp the epoch after
     dlopen via dlsym(handle,"__march_init").
     Guard on hr_config <> None: a --compile-so build without --hot-reload
     must not export a spurious epoch entry point. *)
  if ctx.compile_so && hot_reload <> None then
    Buffer.add_string ctx.preamble
      "@__march_hcr_epoch = private global i32 0\n";
  (* Distributed OTP L4: populate CAS hash maps for remote_ref_hashes constant folding. *)
  Hashtbl.iter (Hashtbl.replace ctx.remote_impl_hashes) remote_impl_hashes;
  Hashtbl.iter (Hashtbl.replace ctx.remote_sig_hashes)  remote_sig_hashes;
  (* Hot Code Reload: IR run in @main (before user main spawns) that sizes the
     dispatch table and publishes each boundary function as its NATIVE baseline
     version. Each boundary fn's per-definition impl_hash (a Merkle root over its
     call graph + type usage, from the CAS) is emitted as a private NUL-terminated
     string global and passed to march_dispatch_publish so the runtime can match a
     hot-swap candidate against the running baseline. When no hash is known (e.g.
     a non-CAS build path) the baseline is published with a null impl_hash and the
     reload server stamps the real hash on activation; see runtime/march_dispatch.c. *)
  let hr_setup =
    match hot_reload with
    | None -> ""
    | Some _cfg ->
      let n = Hot_reload.Name_table.count hr_names in
      if n = 0 then "" else begin
        let b = Buffer.create 256 in
        (* Dispatch slot IDs are 1-based: slot 0 is reserved as the "not set"
           sentinel in march_actor_meta.dispatch_name_id (0 = no HCR dispatch). *)
        Printf.bprintf b "  call void @march_dispatch_init(i32 %d)\n" (n + 1);
        List.iter (fun (fn : Tir.fn_def) ->
          match Hot_reload.Name_table.id_of hr_names fn.Tir.fn_name with
          | None -> ()
          | Some id0 ->
              let id = id0 + 1 in  (* shift to 1-based *)
              (* Emit the impl_hash (if known) as a private string global and
                 pass its ptr; otherwise fall back to a null baseline hash. *)
              let hash_arg =
                match Hashtbl.find_opt impl_hashes fn.Tir.fn_name with
                | Some h when String.length h > 0 ->
                  let g = Printf.sprintf "@.hr_hash%d" id in
                  Buffer.add_string ctx.preamble
                    (Printf.sprintf
                       "%s = private unnamed_addr constant [%d x i8] c\"%s\\00\"\n"
                       g (String.length h + 1) (llvm_escape_string h));
                  Printf.sprintf "ptr %s" g
                | _ -> "ptr null"
              in
              let sig_arg =
                match Hashtbl.find_opt ctx.remote_sig_hashes fn.Tir.fn_name with
                | Some h when String.length h > 0 ->
                  let sg = Printf.sprintf "@.hr_sighash%d" id in
                  Buffer.add_string ctx.preamble
                    (Printf.sprintf
                       "%s = private unnamed_addr constant [%d x i8] c\"%s\\00\"\n"
                       sg (String.length h + 1) (llvm_escape_string h));
                  Printf.sprintf "ptr %s" sg
                | _ -> "ptr null"
              in
              Printf.bprintf b
                "  call i32 @march_dispatch_publish(i32 %d, ptr @%s, %s, %s, i8 0)\n"
                id (mangle_extern fn.Tir.fn_name) hash_arg sig_arg;
              (* Register name→ID mapping for the reload server. *)
              let name_g = Printf.sprintf "@.hr_name%d" id in
              Buffer.add_string ctx.preamble
                (Printf.sprintf
                   "%s = private unnamed_addr constant [%d x i8] c\"%s\\00\"\n"
                   name_g (String.length fn.Tir.fn_name + 1)
                   (llvm_escape_string fn.Tir.fn_name));
              Printf.bprintf b
                "  call void @march_dispatch_register_name(i32 %d, ptr %s)\n"
                id name_g
        ) m.Tir.tm_fns;
        (* Start the reload server if MARCH_HOT_RELOAD_SOCKET is set. *)
        Buffer.add_string ctx.preamble
          "@.hr_sock_env = private unnamed_addr constant [24 x i8] c\"MARCH_HOT_RELOAD_SOCKET\\00\"\n";
        Buffer.add_string b
          "  %hr_sock_ptr = call ptr @getenv(ptr @.hr_sock_env)\n\
          \  call void @march_reload_server_start(ptr %hr_sock_ptr)\n";
        Buffer.contents b
      end
  in
  (* Record shape metadata requires the native runtime (march_extras.c);
     the WASM runtime does not provide march_record_set_shape. *)
  ctx.shape_meta <- not (is_wasm_target target);
  build_ctor_info ctx m;
  (* Register user-defined extern functions *)
  List.iter (fun (ed : Tir.extern_decl) ->
      Hashtbl.replace ctx.extern_map ed.ed_march_name ed.ed_c_name;
      if ed.ed_blocking then Hashtbl.replace ctx.blocking_externs ed.ed_march_name ();
      if ed.ed_raises then Hashtbl.replace ctx.raises_externs ed.ed_march_name ();
      Hashtbl.replace ctx.top_fns ed.ed_march_name true;
      Hashtbl.replace ctx.top_fn_ret_ty ed.ed_march_name ed.ed_ret;
      Hashtbl.replace ctx.top_fn_nparams ed.ed_march_name (List.length ed.ed_params)
    ) m.Tir.tm_externs;
  List.iter (fun fn ->
      Hashtbl.replace ctx.top_fns fn.Tir.fn_name true;
      Hashtbl.replace ctx.top_fn_ret_ty fn.Tir.fn_name fn.Tir.fn_ret_ty;
      Hashtbl.replace ctx.top_fn_nparams fn.Tir.fn_name (List.length fn.Tir.fn_params);
      if fn.Tir.fn_params = [] then
        Hashtbl.replace ctx.zero_arg_fns fn.Tir.fn_name true;
      (* Populate unqualified_fns: maps the unqualified suffix (e.g.
         "base64_encode") to the fully qualified name ("Crypto.base64_encode").
         Used to fix up cross-module ECallPtr calls where lower.ml left the
         function name unqualified.  First registration wins to avoid
         collisions between modules sharing an unqualified name.
         NOTE: we do NOT add the unqualified name to top_fns — that would
         shadow local variables with the same name (e.g. a boolean variable
         named "abs" would incorrectly resolve to @Math.abs).

         EXCLUDE interface-impl-mangled names ("Iface$Type.method", e.g.
         "Show$List.show" or a further-specialized "Show$List.show$List_Int")
         from this map (Wave 2 Task 1 — defense in depth for the
         println-of-list miscompile).  mono.ml now propagates the
         substitution when it enqueues a resolved impl, so a nested
         `show(x)` call inside `impl Show(List(a)) when Show(a)` should
         ALWAYS be resolved to the concrete impl (e.g. Show$Int.show) by
         mono before reaching llvm_emit.  If mono ever regresses and leaves
         a bare interface-method call unresolved again, this map must NOT
         silently rebind it to an arbitrary same-named impl (that was the
         actual bug — a bare `show` got hijacked to `Show$List.show`,
         the LIST impl applied to a raw element).  Detected by checking for
         a '$' before the LAST '.' — ordinary qualified names ("Crypto.
         base64_encode", "App.Core.b") never contain '$', so they are
         unaffected. *)
      (match String.rindex_opt fn.Tir.fn_name '.' with
       | Some i ->
         if not (Tir_names.is_iface_mangled fn.Tir.fn_name) then begin
           let unq = String.sub fn.Tir.fn_name (i+1)
                       (String.length fn.Tir.fn_name - i - 1) in
           if not (Hashtbl.mem ctx.unqualified_fns unq) then begin
             Hashtbl.replace ctx.unqualified_fns unq fn.Tir.fn_name
           end
         end
       | None -> ()))
    m.Tir.tm_fns;
  (* Identify mutual-TCO groups.  Functions in these groups are emitted as
     combined dispatch functions + thin wrappers — they must NOT also be
     emitted individually via emit_fn. *)
  let mutual_groups = find_mutual_tco_groups m.Tir.tm_fns in
  let mutual_fn_names =
    List.concat_map (fun g -> List.map (fun fn -> fn.Tir.fn_name) g)
      mutual_groups
  in
  (* Emit the combined function + wrappers for each mutual-TCO group. *)
  List.iter (emit_mutual_tco_group ctx) mutual_groups;

  (* Skip emitting prelude wrapper functions whose runtime name is already
     declared in the preamble.  Only filter short unqualified names that map
     to march_* builtins — not user-defined qualified names like "CapDemo.main".
     Also skip functions that are members of a mutual-TCO group — those were
     already emitted (as wrappers) by emit_mutual_tco_group above. *)
  let preamble_declared = ["panic"; "panic_"; "todo_"; "unreachable_";
                           "println"; "print"; "print_stderr"; "io_read_line"; "read_line"] in
  let migrate_suffix = "_migrate_state" in
  let migrate_suffix_len = String.length migrate_suffix in
  List.iter (fun fn ->
      if List.mem fn.Tir.fn_name preamble_declared then ()
      else if List.mem fn.Tir.fn_name mutual_fn_names then ()
      else begin
        let fname = fn.Tir.fn_name in
        let flen = String.length fname in
        emit_fn ctx fn;
        (* Phase 5: for migrate_state functions, export a __migrate_<Actor>
           alias so march_reload.c can dlsym it without knowing the full
           mangled March name.
           Convention: fn counter_migrate_state inside mod MyApp →
             TIR name "MyApp.counter_migrate_state"
             → strip "_migrate_state" → "MyApp.counter"
             → last dot-component → "counter"
             → capitalize first letter → "Counter"
             → alias "@__migrate_Counter"
           The march_reload.c runtime forms the same name by stripping
           "_dispatch" from the ACTIVATE name "Counter_dispatch". *)
        if flen > migrate_suffix_len
           && String.sub fname (flen - migrate_suffix_len) migrate_suffix_len = migrate_suffix
        then begin
          (* Take the part before _migrate_state, then extract the last
             dot-separated component (strips module prefix), then capitalize
             the first letter to recover the actor name. *)
          let before_suffix = String.sub fname 0 (flen - migrate_suffix_len) in
          let last_component =
            match String.rindex_opt before_suffix '.' with
            | None   -> before_suffix
            | Some i -> String.sub before_suffix (i + 1)
                          (String.length before_suffix - i - 1)
          in
          if last_component <> "" then begin
            let actor_name =
              (String.uppercase_ascii (String.sub last_component 0 1))
              ^ (String.sub last_component 1 (String.length last_component - 1))
            in
            let alias_name   = "__migrate_" ^ actor_name in
            let llvm_fn_name = mangle_extern fname in
            (* LLVM alias: same signature as migrate_state (ptr → ptr) *)
            Buffer.add_string ctx.buf (Printf.sprintf
              "@%s = alias ptr (ptr), ptr @%s\n" alias_name llvm_fn_name)
          end
        end
      end
    ) m.Tir.tm_fns;

  let out = Buffer.create 8192 in
  emit_preamble ~target out;
  (* Emit user-defined extern function declarations *)
  List.iter (fun (ed : Tir.extern_decl) ->
      (* A `raises` binding takes a hidden march_env* first param and returns the
         bare Ok payload (T of Result(T,E)); the call site wraps it into Ok/Err. *)
      let ret_llty =
        if ed.ed_raises then llvm_ret_ty (ok_payload_ty ed.ed_ret)
        else llvm_ret_ty ed.ed_ret in
      let param_lltys = List.map (fun _t -> "ptr") ed.ed_params in
      let param_lltys = if ed.ed_raises then "ptr" :: param_lltys else param_lltys in
      let params_str = String.concat ", " (List.mapi (fun i ty ->
          Printf.sprintf "%s %%%d" ty i) param_lltys) in
      Buffer.add_string out
        (Printf.sprintf "declare %s @%s(%s)\n" ret_llty ed.ed_c_name params_str)
    ) m.Tir.tm_externs;
  (* Blocking-dispatch helpers, if any extern is `blocking`. *)
  if List.exists (fun (ed : Tir.extern_decl) -> ed.ed_blocking) m.Tir.tm_externs then
    Buffer.add_string out
      "declare i64 @march_run_blocking_i(ptr, ptr, i32)\n\
       declare double @march_run_blocking_d(ptr, ptr, i32)\n";
  (* Error-protocol Ok/Err constructors, if any extern is `raises` (the call-site
     wrapper calls them; march_raise itself is called only from the C binding). *)
  if List.exists (fun (ed : Tir.extern_decl) -> ed.ed_raises) m.Tir.tm_externs then
    Buffer.add_string out
      "declare ptr @march_ok(i64)\n\
       declare ptr @march_err(i64)\n\
       declare i64 @march_make_float(double)\n";
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;

  (* Distributed OTP L4 — Compiler-emitted enroll/stub.
     Scan for functions whose name ends in "__rpc_stub".  For each one, emit
     string constants for the base function's impl_hash / sig_hash (if known
     from the CAS pipeline) and collect a march_remote_register call that goes
     inside @main, between march_remote_init() and march_spawn_main(). *)
  let stub_suffix = "__rpc_stub" in
  let stub_suffix_len = String.length stub_suffix in
  let stub_setup =
    let b = Buffer.create 256 in
    List.iteri (fun i (fn : Tir.fn_def) ->
      let name = fn.Tir.fn_name in
      let nlen = String.length name in
      if nlen > stub_suffix_len &&
         String.sub name (nlen - stub_suffix_len) stub_suffix_len = stub_suffix
      then begin
        let base = String.sub name 0 (nlen - stub_suffix_len) in
        match Hashtbl.find_opt ctx.remote_impl_hashes base,
              Hashtbl.find_opt ctx.remote_sig_hashes base with
        | Some impl_h, Some sig_h when String.length impl_h > 0 ->
          let mangled_stub = llvm_name (mangle_extern name) in
          let impl_esc = llvm_escape_string impl_h in
          let sig_esc  = llvm_escape_string sig_h in
          Printf.bprintf out
            "@.rpc_impl_%d = private unnamed_addr constant [%d x i8] c\"%s\\00\"\n"
            i (String.length impl_h + 1) impl_esc;
          Printf.bprintf out
            "@.rpc_sig_%d = private unnamed_addr constant [%d x i8] c\"%s\\00\"\n"
            i (String.length sig_h + 1) sig_esc;
          Printf.bprintf b
            "  call i32 @march_remote_register(ptr @.rpc_impl_%d, ptr @.rpc_sig_%d, ptr @%s)\n"
            i i mangled_stub
        | _ -> ()
      end
    ) m.Tir.tm_fns;
    Buffer.contents b
  in

  (* Find a main function: either top-level "main" or "ModName.main".
     Use fold_left (last match wins) so that when multiple modules define
     fn main(), the entry file's module takes precedence.  The entry file's
     declarations are injected last into mod_decls, so its functions appear
     last in tm_fns — fold_left keeps the last match. *)
  let main_fn_name = List.fold_left (fun acc (fn : Tir.fn_def) ->
      if fn.Tir.fn_name = "main" then Some "main"
      else if String.length fn.Tir.fn_name > 5 &&
              String.sub fn.Tir.fn_name
                (String.length fn.Tir.fn_name - 5) 5 = ".main"
      then Some fn.Tir.fn_name
      else acc
    ) None m.Tir.tm_fns in

  (* Entry point: for native targets emit @main calling march_main + scheduler;
     for WASM browser target (Wasm32Unknown), emit exported island entry points
     that the JS runtime can call. *)
  (match target with
   | Wasm32Unknown ->
     (* For WASM islands, export the render/update functions.
        The island name is derived from the module name.
        The user's module must define render(state) and update(state, msg). *)
     (* Find a function by base name, handling mono suffixes like render$String.
        Only matches the user's own module (tm_name.suffix) or bare names —
        NOT functions from other modules like Vault.update. *)
     let find_fn suffix =
       List.find_opt (fun (fn : Tir.fn_def) ->
         let n = fn.Tir.fn_name in
         (* Strip monomorphization suffix (e.g. render$String → render) *)
         let base = match String.index_opt n '$' with
           | Some i -> String.sub n 0 i
           | None -> n
         in
         base = suffix ||
         base = m.Tir.tm_name ^ "." ^ suffix
       ) m.Tir.tm_fns
     in
     let emit_island_export export_name march_fn_name params ret_ty =
       let mangled = llvm_name (mangle_extern march_fn_name) in
       let param_decls = String.concat ", " (List.mapi (fun i ty ->
           Printf.sprintf "%s %%%d" ty i) params) in
       let param_refs = String.concat ", " (List.mapi (fun i ty ->
           Printf.sprintf "%s %%%d" ty i) params) in
       Buffer.add_string out
         (Printf.sprintf "\ndefine dllexport %s @%s(%s) {\nentry:\n  %%r = call %s @%s(%s)\n  ret %s %%r\n}\n"
            ret_ty export_name param_decls ret_ty mangled param_refs ret_ty)
     in
     (match find_fn "render" with
      | Some fn ->
        emit_island_export "march_island_render" fn.Tir.fn_name ["ptr"] "ptr"
      | None -> ());
     (match find_fn "update" with
      | Some fn ->
        emit_island_export "march_island_update" fn.Tir.fn_name ["ptr"; "ptr"] "ptr"
      | None -> ());
     (* march_island_init: if there's an init() function, export it;
        otherwise generate a stub that returns null (use SSR state). *)
     (match find_fn "init" with
      | Some fn ->
        let mangled = llvm_name (mangle_extern fn.Tir.fn_name) in
        Buffer.add_string out
          (Printf.sprintf "\ndefine dllexport ptr @march_island_init() {\nentry:\n  %%r = call ptr @%s()\n  ret ptr %%r\n}\n" mangled)
      | None ->
        Buffer.add_string out
          "\ndefine dllexport ptr @march_island_init() {\nentry:\n  ret ptr null\n}\n");
     (* Re-export march_alloc and march_free for JS glue *)
     Buffer.add_string out
       "\ndefine dllexport void @march_dealloc(ptr %p) {\nentry:\n  call void @march_free(ptr %p)\n  ret void\n}\n";
     Buffer.add_string out
       "\ndefine dllexport ptr @march_alloc_export(i64 %sz) {\nentry:\n  %r = call ptr @march_alloc(i64 %sz)\n  ret ptr %r\n}\n";
     Buffer.add_string out
       "\ndefine dllexport ptr @march_string_lit_export(ptr %s, i64 %len) {\nentry:\n  %r = call ptr @march_string_lit(ptr %s, i64 %len)\n  ret ptr %r\n}\n";
     (* march_island_render_html: calls render + iolist_flatten, returns a flat String *)
     (match find_fn "render" with
      | Some fn ->
        let mangled = llvm_name (mangle_extern fn.Tir.fn_name) in
        Buffer.add_string out
          (Printf.sprintf "\ndeclare ptr @march_iolist_flatten(ptr)\ndeclare i32 @march_string_length_i32(ptr)\ndeclare ptr @march_string_data_ptr(ptr)\n\ndefine dllexport ptr @march_island_render_html(ptr %%state) {\nentry:\n  %%iolist = call ptr @%s(ptr %%state)\n  %%str = call ptr @march_iolist_flatten(ptr %%iolist)\n  ret ptr %%str\n}\n\ndefine dllexport i32 @march_island_string_length(ptr %%str) {\nentry:\n  %%r = call i32 @march_string_length_i32(ptr %%str)\n  ret i32 %%r\n}\n\ndefine dllexport ptr @march_island_string_data(ptr %%str) {\nentry:\n  %%r = call ptr @march_string_data_ptr(ptr %%str)\n  ret ptr %%r\n}\n" mangled)
      | None -> ());
     (* march_island_msg_from_name: construct a Msg variant from its name string.
        Emits a chain of string comparisons for all zero-field (enum) Msg constructors.
        Variants with fields are not supported here — use JSON wire format instead. *)
     let msg_type_opt = List.find_opt (fun td ->
       match td with
       | Tir.TDVariant (name, _) ->
         (* Strip module prefix, e.g. "Counter.Msg" -> "Msg" *)
         let base = match String.rindex_opt name '.' with
           | Some i -> String.sub name (i+1) (String.length name - i - 1)
           | None -> name
         in
         (* Strip mono suffix like Msg$0 *)
         let base2 = match String.index_opt base '$' with
           | Some i -> String.sub base 0 i
           | None -> base
         in
         base2 = "Msg"
       | _ -> false
     ) m.Tir.tm_types in
     (match msg_type_opt with
      | Some (Tir.TDVariant (_, ctors)) ->
        (* Filter to enum constructors (no fields) *)
        let enum_ctors = List.filter (fun (_, fields) -> fields = []) ctors in
        if enum_ctors <> [] then begin
          let buf2 = Buffer.create 512 in
          (* Emit string constants for each constructor name *)
          List.iter (fun (name, _) ->
            (* Strip module prefix from ctor name *)
            let base_name = match String.rindex_opt name '.' with
              | Some i -> String.sub name (i+1) (String.length name - i - 1)
              | None -> name
            in
            Buffer.add_string buf2
              (Printf.sprintf "@.msg_name_%s = private constant [%d x i8] c\"%s\\00\"\n"
                 base_name (String.length base_name + 1) base_name)
          ) enum_ctors;
          Buffer.add_string buf2
            "\ndeclare i64 @march_string_eq(ptr, ptr)\n";
          Buffer.add_string buf2
            "\ndeclare i64 @march_poly_eq(ptr, ptr)\n";
          Buffer.add_string buf2
            "\ndefine dllexport ptr @march_island_msg_from_name(ptr %data, i32 %len) {\nentry:\n";
          (* Allocate a temporary string for the input *)
          Buffer.add_string buf2
            "  %ilen = sext i32 %len to i64\n  %tmp = call ptr @march_string_lit(ptr %data, i64 %ilen)\n";
          List.iteri (fun i (name, _) ->
            let base_name = match String.rindex_opt name '.' with
              | Some j -> String.sub name (j+1) (String.length name - j - 1)
              | None -> name
            in
            let nlen = String.length base_name in
            Buffer.add_string buf2
              (Printf.sprintf "  %%slit%d = call ptr @march_string_lit(ptr @.msg_name_%s, i64 %d)\n"
                 i base_name nlen);
            Buffer.add_string buf2
              (Printf.sprintf "  %%eq%d = call i64 @march_string_eq(ptr %%slit%d, ptr %%tmp)\n" i i);
            Buffer.add_string buf2
              (Printf.sprintf "  %%b%d = icmp ne i64 %%eq%d, 0\n" i i);
            Buffer.add_string buf2
              (Printf.sprintf "  br i1 %%b%d, label %%match%d, label %%next%d\n" i i i);
            Buffer.add_string buf2
              (Printf.sprintf "match%d:\n  %%cell%d = call ptr @march_alloc(i64 16)\n" i i);
            Buffer.add_string buf2
              (Printf.sprintf "  %%tp%d = getelementptr i8, ptr %%cell%d, i64 8\n" i i);
            Buffer.add_string buf2
              (Printf.sprintf "  store i32 %d, ptr %%tp%d\n  ret ptr %%cell%d\nnext%d:\n" i i i i)
          ) enum_ctors;
          (* Default: return null (unknown message) *)
          Buffer.add_string buf2 "  ret ptr null\n}\n";
          Buffer.add_string out (Buffer.contents buf2)
        end
      | _ -> ());
     (* If there's a main function, still call it for module-level init *)
     (match main_fn_name with
      | Some name ->
        let mangled = llvm_name (mangle_extern name) in
        Buffer.add_string out
          (Printf.sprintf "\ndefine dllexport void @_start() {\nentry:\n  call void @%s()\n  ret void\n}\n" mangled)
      | None -> ())
   | _ ->
     (* Native / WASI: test-runner @main (when tm_tests populated) or standard @main.
        Suppressed when emit_main=false (--compile-so: patch shared library). *)
     if not emit_main && hot_reload <> None then begin
       (* Phase 9: exported init function so the reload server can stamp the epoch.
          Only emitted when --hot-reload is active; a plain --compile-so build
          without --hot-reload must not export a spurious epoch entry point. *)
       Buffer.add_string out
         "\ndefine void @__march_init(i32 %epoch) {\nentry:\n\
          \  store i32 %epoch, ptr @__march_hcr_epoch\n\
          \  ret void\n}\n"
     end else
     if m.Tir.tm_tests <> [] then begin
       (* --test mode: emit a @main that calls the test harness.
          For each test fn we emit a string constant for its display name and
          call march_test_run(fn_ptr, name_ptr, setup_or_null).
          setup_all and per-test setup are optional and may not exist. *)
       let has_setup_all = List.exists (fun (fn : Tir.fn_def) ->
           fn.Tir.fn_name = Tir_names.setup_all_fn_name) m.Tir.tm_fns in
       let has_setup = List.exists (fun (fn : Tir.fn_def) ->
           fn.Tir.fn_name = Tir_names.setup_fn_name) m.Tir.tm_fns in
       (* Emit test name string constants directly to out (preamble was already
          flushed to out above, so ctx.preamble writes would be lost). *)
       List.iteri (fun i (_fn_name, display_name) ->
         (* Use the same escaper as intern_string (llvm_escape_string): percent-
            encodes every byte outside printable ASCII and encodes " as \22 and
            \ as \5C.  LLVM parses these three-byte forms back to one byte, so
            String.length display_name + 1 remains the correct array size.
            The previous ad-hoc escaper only handled '\n' → \0A, leaving literal
            " and \ in place; LLVM's C-string parser then interpreted them as
            escape sequences, collapsing two-byte sequences to one byte so the
            actual payload was shorter than nbytes, and clang rejected the IR
            with "constant expression type mismatch". *)
         let escaped = llvm_escape_string display_name in
         let nbytes = String.length display_name + 1 in
         Printf.bprintf out
           "@.test_name_%d = private constant [%d x i8] c\"%s\\00\"\n"
           i nbytes escaped
       ) m.Tir.tm_tests;
       let buf2 = Buffer.create 1024 in
       Buffer.add_string buf2
         "\ndeclare void @march_process_argv_init(i32 %argc, ptr %argv_ptr)\n";
       Buffer.add_string buf2
         "define i32 @main(i32 %argc, ptr %argv_ptr) {\nentry:\n";
       Buffer.add_string buf2
         "  call void @march_process_argv_init(i32 %argc, ptr %argv_ptr)\n";
       Buffer.add_string buf2
         "  call void @march_test_init(i32 %argc, ptr %argv_ptr)\n";
       if has_setup_all then
         Buffer.add_string buf2
           (Printf.sprintf "  call void @march_test_setup_all(ptr @%s)\n"
              (llvm_name (mangle_extern Tir_names.setup_all_fn_name)));
       let setup_arg = if has_setup then
         Printf.sprintf "ptr @%s" (llvm_name (mangle_extern Tir_names.setup_fn_name))
       else "ptr null" in
       List.iteri (fun i (fn_name, _display_name) ->
         let mangled = llvm_name (mangle_extern fn_name) in
         Printf.bprintf buf2
           "  call void @march_test_run(ptr @%s, ptr @.test_name_%d, %s)\n"
           mangled i setup_arg
       ) m.Tir.tm_tests;
       Buffer.add_string buf2 "  %rc = call i32 @march_test_report()\n";
       Buffer.add_string buf2 "  ret i32 %rc\n}\n";
       Buffer.add_buffer out buf2
     end else begin
       (match main_fn_name with
        | Some name ->
          let mangled = llvm_name (mangle_extern name) in
          Buffer.add_string out
            (Printf.sprintf "\ndeclare void @march_process_argv_init(i32 %%argc, ptr %%argv_ptr)\n\
             declare void @march_spawn_main(ptr %%fn)\n\
             define i32 @main(i32 %%argc, ptr %%argv_ptr) {\nentry:\n\
               call void @march_process_argv_init(i32 %%argc, ptr %%argv_ptr)\n\
               call void @march_remote_init()\n\
             %s%s\
               call void @march_spawn_main(ptr @%s)\n\
               call void @march_run_scheduler()\n\
               ret i32 0\n}\n" hr_setup stub_setup mangled)
        | None ->
          (* Library module with no user-defined main: emit a stub @main so
             clang can link a valid binary (forge build type-checks libraries). *)
          Buffer.add_string out
            "\ndefine i32 @main(i32 %argc, ptr %argv_ptr) {\nentry:\n  ret i32 0\n}\n")
     end);

  (* Append closure wrapper functions generated for top-level fn-as-value *)
  Buffer.add_buffer out ctx.extra_fns;

  repr_audit_report ();
  Buffer.contents out

(* ── REPL emission helpers ──────────────────────────────────────────────── *)

(** Tracks REPL globals across fragments. Each entry:
    (llvm_name, llvm_type_string).  Example: ("repl_x", "ptr") *)
type repl_globals = (string * string) list ref

let emit_repl_globals_decl (buf : Buffer.t) (globals : (string * string) list) =
  List.iter (fun (name, ty) ->
    Printf.bprintf buf "@%s = external global %s\n" name ty
  ) globals

(** A REPL variable slot: the persistent index into [march_repl_slots].
    [rs_bare] is the bare variable name (e.g. "x", "fib").
    [rs_slot] is the slot index passed to @march_repl_get / @march_repl_set.
    [rs_ty]   is the TIR type, used to pick the right bit-conversion. *)
type repl_slot_info = { rs_bare : string; rs_slot : int; rs_ty : Tir.ty }

(** Emit bridge alloca+call pairs for each prev_slot into the current function
    entry block, and register the alloca in [ctx.var_slot].
    Uses @march_repl_get(i64 slot) so no LLVM external globals are needed —
    values live in a single persistent C array that survives .so reloads. *)
let emit_prev_slot_bridges ctx (prev_slots : repl_slot_info list) =
  List.iter (fun si ->
    let llty = llvm_ty si.rs_ty in
    let raw  = fresh ctx "slot" in
    Printf.bprintf ctx.buf "  %%%s.addr = alloca %s\n" si.rs_bare llty;
    Printf.bprintf ctx.buf "  %s = call i64 @march_repl_get(i64 %d)\n" raw si.rs_slot;
    let converted = match si.rs_ty with
      | Tir.TInt | Tir.TBool | Tir.TUnit -> raw
      | Tir.TFloat ->
        let ft = fresh ctx "fv" in
        Printf.bprintf ctx.buf "  %s = bitcast i64 %s to double\n" ft raw;
        ft
      | _ ->
        let pt = fresh ctx "pv" in
        Printf.bprintf ctx.buf "  %s = inttoptr i64 %s to ptr\n" pt raw;
        pt
    in
    Printf.bprintf ctx.buf "  store %s %s, ptr %%%s.addr\n" llty converted si.rs_bare;
    Hashtbl.replace ctx.var_slot si.rs_bare si.rs_bare
  ) prev_slots

(** Emit a store of [result] (LLVM value of type [llty]) into slot [slot_idx]
    via @march_repl_set.  Converts non-i64 values to i64 bits first. *)
let emit_store_to_slot ctx (slot_idx : int) (result : string) (tir_ty : Tir.ty) =
  let bits = match tir_ty with
    | Tir.TInt | Tir.TBool | Tir.TUnit -> result
    | Tir.TFloat ->
      let bt = fresh ctx "fb" in
      Printf.bprintf ctx.buf "  %s = bitcast double %s to i64\n" bt result;
      bt
    | _ ->
      let pt = fresh ctx "pb" in
      Printf.bprintf ctx.buf "  %s = ptrtoint ptr %s to i64\n" pt result;
      pt
  in
  Printf.bprintf ctx.buf "  call void @march_repl_set(i64 %d, i64 %s)\n" slot_idx bits

(** Emit thin module-level loader functions for each prior REPL slot so that
    named function bodies compiled via [emit_repl_fn] /
    [emit_repl_fn_with_closure_slot] can reference prior let-bindings as
    zero-arg calls "@<name>()".  Each loader calls @march_repl_get and returns
    the value in the correct LLVM type.  [ctx.top_fn_ret_ty] is updated so the
    AVar handler at the call site uses the matching return type.
    Writing to [ctx.buf] (not [ctx.extra_fns]) so the definitions appear even
    in [emit_repl_fn] which does not include extra_fns in its output. *)
let emit_slot_loader_fns ctx (prev_slots : repl_slot_info list) =
  List.iter (fun (si : repl_slot_info) ->
    match si.rs_ty with
    | Tir.TUnit -> ()  (* unit slots carry no meaningful value; skip *)
    | ty ->
      let fname  = llvm_name si.rs_bare in
      let ret_ty = llvm_ret_ty ty in
      Hashtbl.replace ctx.top_fn_ret_ty si.rs_bare ty;
      let (conv_instr, retval) = match ty with
        | Tir.TInt | Tir.TBool -> ("", "%raw")
        | Tir.TFloat -> ("  %fv = bitcast i64 %raw to double\n", "%fv")
        | _ -> ("  %pv = inttoptr i64 %raw to ptr\n", "%pv")
      in
      Printf.bprintf ctx.buf
        "\ndefine %s @%s() {\nentry:\n  %%raw = call i64 @march_repl_get(i64 %d)\n%s  ret %s %s\n}\n"
        ret_ty fname si.rs_slot conv_instr ret_ty retval
  ) prev_slots

(** Emit bridge alloca+load+store pairs for each prev_global into the current
    function entry block, and register the slot in [ctx.var_slot].
    This lets the body refer to REPL globals via the normal alloca load path.
    LLVM's mem2reg/SROA eliminates the extra instructions. *)
let emit_prev_global_bridges ctx (prev_globals : (string * string) list) =
  List.iter (fun (gname, llty) ->
    (* gname is "repl_N_<bare>" by construction in repl_jit (N = fragment number).
       Strip the "repl_N_" prefix to recover the bare variable name. *)
    let bare =
      let len = String.length gname in
      if len > 5 && String.sub gname 0 5 = "repl_" then begin
        let i = ref 5 in
        while !i < len && gname.[!i] >= '0' && gname.[!i] <= '9' do incr i done;
        if !i < len && gname.[!i] = '_' then
          String.sub gname (!i + 1) (len - !i - 1)
        else
          String.sub gname 5 (len - 5)  (* fallback: old "repl_<bare>" format *)
      end else gname
    in
    let tmp = fresh ctx "br" in
    Printf.bprintf ctx.buf "  %%%s.addr = alloca %s\n" bare llty;
    Printf.bprintf ctx.buf "  %s = load %s, ptr @%s\n" tmp llty gname;
    Printf.bprintf ctx.buf "  store %s %s, ptr %%%s.addr\n" llty tmp bare;
    Hashtbl.replace ctx.var_slot bare bare
  ) prev_globals

(** Emit a REPL expression as a standalone .ll fragment.
    Returns textual LLVM IR with a function [@repl_<n>] that computes
    and returns the expression result.
    [prev_slots] are the persistent variable slots from earlier REPL inputs.
    [fns] are any helper functions the expression depends on.
    [store_as_slot] if Some k, also stores the result to slot k via
    @march_repl_set so later fragments can read it as "v". *)
let emit_repl_expr ?(fast_math=false) ~(n : int) ~(ret_ty : Tir.ty)
    ~(prev_slots : repl_slot_info list)
    ~(fns : Tir.fn_def list)
    ?(extern_fns : Tir.fn_def list = [])
    ?(store_as_slot : int option = None)
    ~(types : Tir.type_def list)
    (body : Tir.expr) : string =
  let ctx = make_ctx ~fast_math ~repl:true ~type_defs:types () in
  let pseudo_mod : Tir.tir_module = { tm_name = "repl"; tm_types = types; tm_fns = fns; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  build_ctor_info ctx pseudo_mod;
  List.iter (fun fn ->
      Hashtbl.replace ctx.top_fns fn.Tir.fn_name true;
      Hashtbl.replace ctx.top_fn_ret_ty fn.Tir.fn_name fn.Tir.fn_ret_ty;
      Hashtbl.replace ctx.top_fn_nparams fn.Tir.fn_name (List.length fn.Tir.fn_params);
      if fn.Tir.fn_params = [] then Hashtbl.replace ctx.zero_arg_fns fn.Tir.fn_name true) fns;
  (* Register pre-compiled extern functions so EApp generates direct calls *)
  List.iter (fun fn ->
      Hashtbl.replace ctx.top_fns fn.Tir.fn_name true;
      Hashtbl.replace ctx.top_fn_ret_ty fn.Tir.fn_name fn.Tir.fn_ret_ty;
      Hashtbl.replace ctx.top_fn_nparams fn.Tir.fn_name (List.length fn.Tir.fn_params);
      if fn.Tir.fn_params = [] then Hashtbl.replace ctx.zero_arg_fns fn.Tir.fn_name true) extern_fns;
  List.iter (emit_fn ctx) fns;
  let ret_llty = llvm_ty ret_ty in
  let fname = Printf.sprintf "repl_%d" n in
  Printf.bprintf ctx.buf "\ndefine %s @%s() {\nentry:\n" ret_llty fname;
  emit_prev_slot_bridges ctx prev_slots;
  let (actual_ty, result) = emit_expr ctx body in
  let result' = coerce ctx actual_ty result ret_llty in
  (* Store result to the persistent "v" slot so later fragments can read it. *)
  (match store_as_slot with
   | None -> ()
   | Some k -> emit_store_to_slot ctx k result' ret_ty);
  Printf.bprintf ctx.buf "  ret %s %s\n}\n" ret_llty result';
  let out = Buffer.create 4096 in
  emit_preamble ~repl:true out;
  (* Declare pre-compiled functions so LLVM IR is valid even without definitions *)
  List.iter (fun fn -> Buffer.add_string out (fn_declare_str fn ^ "\n")) extern_fns;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;
  Buffer.add_buffer out ctx.extra_fns;
  Buffer.contents out

(* Emit a REPL let-binding as a .ll fragment.
   Creates a global [@repl_<name>] and an init function [@repl_<n>_init]
   that computes the value and stores it in the global. *)
(** Emit a REPL let-binding as a .ll fragment.
    Creates an init function [@repl_<n>_init] that computes the value and
    stores it in slot [dest_slot] via @march_repl_set.  No LLVM global is
    needed — the slot table in march_extras.c persists across .so reloads. *)
let emit_repl_decl ?(fast_math=false) ~(n : int) ~(name : string)
    ~(val_ty : Tir.ty)
    ~(dest_slot : int)
    ~(prev_slots : repl_slot_info list)
    ~(fns : Tir.fn_def list)
    ?(extern_fns : Tir.fn_def list = [])
    ~(types : Tir.type_def list)
    (body : Tir.expr) : string =
  ignore name;
  let ctx = make_ctx ~fast_math ~repl:true ~type_defs:types () in
  let pseudo_mod : Tir.tir_module = { tm_name = "repl"; tm_types = types; tm_fns = fns; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  build_ctor_info ctx pseudo_mod;
  List.iter (fun fn ->
      Hashtbl.replace ctx.top_fns fn.Tir.fn_name true;
      Hashtbl.replace ctx.top_fn_ret_ty fn.Tir.fn_name fn.Tir.fn_ret_ty;
      Hashtbl.replace ctx.top_fn_nparams fn.Tir.fn_name (List.length fn.Tir.fn_params);
      if fn.Tir.fn_params = [] then Hashtbl.replace ctx.zero_arg_fns fn.Tir.fn_name true) fns;
  List.iter (fun fn ->
      Hashtbl.replace ctx.top_fns fn.Tir.fn_name true;
      Hashtbl.replace ctx.top_fn_ret_ty fn.Tir.fn_name fn.Tir.fn_ret_ty;
      Hashtbl.replace ctx.top_fn_nparams fn.Tir.fn_name (List.length fn.Tir.fn_params);
      if fn.Tir.fn_params = [] then Hashtbl.replace ctx.zero_arg_fns fn.Tir.fn_name true) extern_fns;
  List.iter (emit_fn ctx) fns;
  let llty = llvm_ty val_ty in
  let init_name = Printf.sprintf "repl_%d_init" n in
  Printf.bprintf ctx.buf "\ndefine void @%s() {\nentry:\n" init_name;
  emit_prev_slot_bridges ctx prev_slots;
  let (actual_ty, result) = emit_expr ctx body in
  let result' = coerce ctx actual_ty result llty in
  emit_store_to_slot ctx dest_slot result' val_ty;
  Printf.bprintf ctx.buf "  ret void\n}\n";
  let out = Buffer.create 4096 in
  emit_preamble ~repl:true out;
  List.iter (fun fn -> Buffer.add_string out (fn_declare_str fn ^ "\n")) extern_fns;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;
  Buffer.add_buffer out ctx.extra_fns;
  Buffer.contents out

(** Emit a REPL function declaration as a .ll fragment.
    The function is emitted at top level (callable by later fragments).
    A no-op [@repl_<n>_init] is emitted so the REPL runner can call it uniformly. *)
let emit_repl_fn ?(fast_math=false) ~(n : int)
    ~(prev_slots : repl_slot_info list)
    ?(extern_fns : Tir.fn_def list = [])
    ~(types : Tir.type_def list)
    (fn : Tir.fn_def) : string =
  let ctx = make_ctx ~fast_math ~repl:true ~type_defs:types () in
  let pseudo_mod : Tir.tir_module = { tm_name = "repl"; tm_types = types; tm_fns = [fn]; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  build_ctor_info ctx pseudo_mod;
  Hashtbl.replace ctx.top_fns fn.Tir.fn_name true;
  Hashtbl.replace ctx.top_fn_ret_ty fn.Tir.fn_name fn.Tir.fn_ret_ty;
  Hashtbl.replace ctx.top_fn_nparams fn.Tir.fn_name (List.length fn.Tir.fn_params);
  if fn.Tir.fn_params = [] then Hashtbl.replace ctx.zero_arg_fns fn.Tir.fn_name true;
  List.iter (fun f ->
      Hashtbl.replace ctx.top_fns f.Tir.fn_name true;
      Hashtbl.replace ctx.top_fn_ret_ty f.Tir.fn_name f.Tir.fn_ret_ty;
      Hashtbl.replace ctx.top_fn_nparams f.Tir.fn_name (List.length f.Tir.fn_params);
      if f.Tir.fn_params = [] then Hashtbl.replace ctx.zero_arg_fns f.Tir.fn_name true) extern_fns;
  emit_slot_loader_fns ctx prev_slots;
  emit_fn ctx fn;
  let init_name = Printf.sprintf "repl_%d_init" n in
  Printf.bprintf ctx.buf "\ndefine void @%s() {\nentry:\n  ret void\n}\n" init_name;
  let out = Buffer.create 4096 in
  emit_preamble ~repl:true out;
  List.iter (fun f -> Buffer.add_string out (fn_declare_str f ^ "\n")) extern_fns;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;
  Buffer.add_buffer out ctx.extra_fns;
  Buffer.contents out

(** Emit a REPL function declaration as a .ll fragment, and also store a
    first-class closure value in slot [dest_slot] via @march_repl_set.
    The init function [@repl_<n>_init] allocates the closure and writes it
    to the slot so later fragments can load it via @march_repl_get. *)
let emit_repl_fn_with_closure_slot ?(fast_math=false) ~(n : int)
    ~(bind_name : string)
    ~(dest_slot : int)
    ~(prev_slots : repl_slot_info list)
    ?(extern_fns : Tir.fn_def list = [])
    ~(types : Tir.type_def list)
    (fn : Tir.fn_def) : string =
  ignore bind_name;
  let ctx = make_ctx ~fast_math ~repl:true ~type_defs:types () in
  let pseudo_mod : Tir.tir_module = { tm_name = "repl"; tm_types = types; tm_fns = [fn]; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  build_ctor_info ctx pseudo_mod;
  Hashtbl.replace ctx.top_fns fn.Tir.fn_name true;
  Hashtbl.replace ctx.top_fn_ret_ty fn.Tir.fn_name fn.Tir.fn_ret_ty;
  Hashtbl.replace ctx.top_fn_nparams fn.Tir.fn_name (List.length fn.Tir.fn_params);
  if fn.Tir.fn_params = [] then Hashtbl.replace ctx.zero_arg_fns fn.Tir.fn_name true;
  List.iter (fun f ->
      Hashtbl.replace ctx.top_fns f.Tir.fn_name true;
      Hashtbl.replace ctx.top_fn_ret_ty f.Tir.fn_name f.Tir.fn_ret_ty;
      Hashtbl.replace ctx.top_fn_nparams f.Tir.fn_name (List.length f.Tir.fn_params);
      if f.Tir.fn_params = [] then Hashtbl.replace ctx.zero_arg_fns f.Tir.fn_name true) extern_fns;
  emit_slot_loader_fns ctx prev_slots;
  emit_fn ctx fn;
  (* Build a thin closure wrapper: @<fn>$clo_wrap(ptr %_clo, <concrete args>)
     via the canonical [clo_wrap_define] (see its doc comment) so this
     wrapper honors the SAME generic ptr ABI as every other closure-dispatch
     wrapper in this file: scalars tagged `(n<<1)|1`, doubles bitcast into
     the ptr slot, heap ptrs passed through.  ECallPtr call sites always
     read the result as `ptr` (see is_apply_fn) regardless of the callee's
     concrete return type — a wrapper that instead returned the raw
     concrete type (as this one used to) would declare a mismatched LLVM
     signature against that `call ptr` site, and the caller's conditional
     untag would reinterpret raw bits as tagged, corrupting odd Int
     results (B11). *)
  let fn_llvm_name = llvm_name (mangle_extern fn.Tir.fn_name) in
  let wrap_name = fn_llvm_name ^ "$clo_wrap" in
  let nparams = List.length fn.Tir.fn_params in
  let target_ret = llvm_ret_ty fn.Tir.fn_ret_ty in
  let param_tys = List.map (fun v -> llvm_ty v.Tir.v_ty) fn.Tir.fn_params in
  let all_params = "ptr" :: param_tys in
  let arg_names = List.init nparams (fun i -> Printf.sprintf "%%a%d" i) in
  let all_arg_decls = "%_clo" :: arg_names in
  let decl_str = String.concat ", " (List.map2 (fun t n -> t ^ " " ^ n) all_params all_arg_decls) in
  let call_args = String.concat ", " (List.map2 (fun t n -> t ^ " " ^ n) param_tys arg_names) in
  (* Same check-then-add emitted_wraps guard as the other two clo_wrap_define
     call sites: the fn is registered in ctx.top_fns BEFORE emit_fn above, so
     a body that references ITSELF as a first-class value (e.g.
     `let g = selfref`) already emitted this exact wrapper via emit_atom's
     top-fns wrap path — an unconditional second emission would define the
     same symbol twice in one fragment and clang rejects the module. *)
  if not (Hashtbl.mem ctx.emitted_wraps wrap_name) then begin
    Hashtbl.add ctx.emitted_wraps wrap_name ();
    Buffer.add_string ctx.extra_fns
      (clo_wrap_define wrap_name decl_str target_ret fn_llvm_name call_args)
  end;
  (* Init function: allocate closure {header(16), fn_ptr} and store in the slot *)
  let init_name = Printf.sprintf "repl_%d_init" n in
  Printf.bprintf ctx.buf "\ndefine void @%s() {\nentry:\n" init_name;
  Printf.bprintf ctx.buf "  %%hp = call ptr @march_alloc(i64 24)\n";
  Printf.bprintf ctx.buf "  %%tgp = getelementptr i8, ptr %%hp, i64 8\n";
  Printf.bprintf ctx.buf "  store i32 0, ptr %%tgp, align 4\n";
  Printf.bprintf ctx.buf "  %%fp = getelementptr i8, ptr %%hp, i64 16\n";
  Printf.bprintf ctx.buf "  store ptr @%s, ptr %%fp, align 8\n" wrap_name;
  Printf.bprintf ctx.buf "  %%cp = ptrtoint ptr %%hp to i64\n";
  Printf.bprintf ctx.buf "  call void @march_repl_set(i64 %d, i64 %%cp)\n" dest_slot;
  Printf.bprintf ctx.buf "  ret void\n}\n";
  let out = Buffer.create 4096 in
  emit_preamble ~repl:true out;
  List.iter (fun f -> Buffer.add_string out (fn_declare_str f ^ "\n")) extern_fns;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;
  (* clo_wrap_define's output above lands in ctx.extra_fns (the same buffer
     every other closure-wrap call site appends to) — include it here or the
     wrapper text is silently dropped and @<fn>$clo_wrap becomes an undefined
     symbol at link/dlopen time (B11 sibling bug: this emitter used to omit
     extra_fns entirely). *)
  Buffer.add_buffer out ctx.extra_fns;
  Buffer.contents out

(** Emit a collection of functions as a standalone LLVM IR module.
    Used for precompiling the stdlib to a cacheable .so fragment.
    No expression wrapper is emitted — just the function definitions. *)
let emit_fns_fragment
    ~(types : Tir.type_def list)
    ~(fns : Tir.fn_def list)
    ?(extern_fns : Tir.fn_def list = [])
    ?(repl : bool = false)
    () : string =
  let ctx = make_ctx ~repl ~type_defs:types () in
  let pseudo_mod : Tir.tir_module =
    { tm_name = "stdlib_prelude"; tm_types = types; tm_fns = fns; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  build_ctor_info ctx pseudo_mod;
  (* Register externals first so intra-fragment references resolve correctly. *)
  List.iter (fun f ->
      Hashtbl.replace ctx.top_fns f.Tir.fn_name true;
      Hashtbl.replace ctx.top_fn_ret_ty f.Tir.fn_name f.Tir.fn_ret_ty;
      Hashtbl.replace ctx.top_fn_nparams f.Tir.fn_name (List.length f.Tir.fn_params);
      if f.Tir.fn_params = [] then Hashtbl.replace ctx.zero_arg_fns f.Tir.fn_name true) extern_fns;
  List.iter (fun fn ->
      Hashtbl.replace ctx.top_fns fn.Tir.fn_name true;
      Hashtbl.replace ctx.top_fn_ret_ty fn.Tir.fn_name fn.Tir.fn_ret_ty;
      Hashtbl.replace ctx.top_fn_nparams fn.Tir.fn_name (List.length fn.Tir.fn_params);
      if fn.Tir.fn_params = [] then Hashtbl.replace ctx.zero_arg_fns fn.Tir.fn_name true) fns;
  List.iter (emit_fn ctx) fns;
  let out = Buffer.create 8192 in
  emit_preamble ~repl out;
  List.iter (fun f -> Buffer.add_string out (fn_declare_str f ^ "\n")) extern_fns;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;
  Buffer.add_buffer out ctx.extra_fns;
  Buffer.contents out

let llvm_ty_of_tir = llvm_ty
