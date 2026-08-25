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
    to native LLVM instructions.

    Wave 3 Task 7 (chunk 2) reduced this file to an orchestrator: the
    [emit_expr]/[emit_atom] core recursive emitters stay here (the one
    piece every split explicitly leaves in place — see each split's module
    doc); everything else has moved out over Tasks 3-7. This file's public
    API is: [target_config] (+ [Native]/[Wasm64Wasi]/[Wasm32Wasi]/
    [Wasm32Unknown]/[Js]), [target_triple], [is_wasm_target], [is_wasm32],
    [target_ptr_size]/[target_ptr_ty]/[target_int_ty], [emit_preamble],
    [emit_module], and the REPL/fragment entry points ([emit_repl_expr],
    [emit_repl_decl], [emit_repl_fn], [emit_repl_fn_with_closure_slot],
    [emit_fns_fragment], [repl_slot_info], [fn_declare_str],
    [build_ctor_info], [mangle_extern]). Below are pointers to where the
    rest of the value-representation machinery now lives (prose, not
    code — Wave 4 owns the real architecture doc):

    - Object layout / tagging law (odd-tag scalar convention, conditional
      ptr<->i64 untag, [emit_tag_scalar]/[emit_untag_scalar]/
      [emit_untag_known_scalar]), the [ctx] record, fresh-name/emit
      primitives, core type mapping ([llvm_ty]/[llvm_param_ty]/
      [llvm_ret_ty]), [coerce], string interning, the repr-consistency
      audit: [Llvm_ctx] (Wave 3 Task 3).
    - Builtin-function table (the single source for [is_builtin_fn] /
      [builtin_ret_ty] / [mangle_extern] / the preamble declare blob):
      [Llvm_builtins] (Wave 3 Task 4).
    - ADT structural equality ([ensure_adt_eq_fn] family): [Llvm_eq]
      (Wave 3 Task 5).
    - Data-constructor emission (EAlloc/EStackAlloc/EReuse/ETuple/ERecord/
      EField/EUpdate helpers, ctor lookup, record shape metadata): [Llvm_data]
      (Wave 3 Task 5).
    - [emit_case] + niche/newtype match-compilation strategies: [Llvm_case]
      (Wave 3 Task 5).
    - EApp/ECallPtr helpers, the `raises`-wrapper and closure-apply-wrapper
      ABI ([clo_wrap_define] — the canonical generic-ptr apply-fn ABI every
      closure dispatch site shares), interface-method-resolution failure:
      [Llvm_calls] (Wave 3 Task 6).
    - Self- and mutual-tail-call analysis/emission (Tarjan SCC, the combined
      mutual-TCO dispatch function): [Llvm_tco] (Wave 3 Task 6).
    - [emit_fn] (including the self-TCO loop transform), [build_ctor_info],
      [emit_module] (module-level assembly: HCR name-table setup, extern/
      main/test/WASM entry emission), [target_config] and its consumers,
      [emit_preamble]: [Llvm_toplevel] (Wave 3 Task 7).
    - The five REPL/JIT-fragment emitters, [repl_slot_info], the slot/global
      bridge builders: [Llvm_repl] (Wave 3 Task 7). *)

(** Compilation target. Wave 3 Task 7 (chunk 2): definition moved to
    [Llvm_toplevel] (its one real cross-module consumer, via [emit_module] /
    [emit_preamble]) — re-exported bare here so external callers
    (bin/main.ml, lib/jit/repl_jit.ml, test/) keep referencing
    [Llvm_emit.target_config] / [Llvm_emit.Native] / etc. unchanged. See
    [Llvm_toplevel]'s module doc for the promotion rationale (same
    criterion Task 6 used for [llvm_ret_ty]/[emit_reduction_check]). *)
type arch = Llvm_toplevel.arch = X86_64 | Arm64
type target_config = Llvm_toplevel.target_config =
  | Native
  | LinuxGnu of { arch : arch; glibc_min : string }
  | Wasm64Wasi
  | Wasm32Wasi
  | Wasm32Unknown
  | Js

let is_wasm_target = Llvm_toplevel.is_wasm_target
let is_wasm32 = Llvm_toplevel.is_wasm32
let target_triple = Llvm_toplevel.target_triple
let target_arch = Llvm_toplevel.target_arch
let target_is_linux = Llvm_toplevel.target_is_linux
let zig_target = Llvm_toplevel.zig_target
let target_ptr_size = Llvm_toplevel.target_ptr_size
let target_ptr_ty = Llvm_toplevel.target_ptr_ty
let target_int_ty = Llvm_toplevel.target_int_ty

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
  top_fn_param_tys : (string, Tir.ty list) Hashtbl.t;
  native_vec_params : (string, int list) Hashtbl.t;
  zero_arg_fns  : (string, bool) Hashtbl.t;
  field_map : (string, (string * Tir.ty) list) Hashtbl.t;
  mutable ret_ty  : Tir.ty;
  fast_math : bool;
  pmap_threshold : int;
  type_defs : Tir.type_def list;
  collision_set : (string, string list) Hashtbl.t;
  poly_ctors  : (string * string, Tir.ty list) Hashtbl.t;
  type_params : (string, string list) Hashtbl.t;
  var_slot  : (string, string) Hashtbl.t;
  local_names : (string, int) Hashtbl.t;
  emitted_wraps : (string, unit) Hashtbl.t;
  static_clos : (string, string) Hashtbl.t;
  extra_fns : Buffer.t;
  emitted_eq_fns : (string, unit) Hashtbl.t;
  emitted_dispatch_fns : (string, unit) Hashtbl.t;
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
  mutable tco_dup_bound : string list;
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
  atom_names : (int64, string) Hashtbl.t;
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
let is_vec_ty = Llvm_ctx.is_vec_ty

(** Release the call-scoped SIMD vector temp boxes collected for one call site.

    Emitted in the SAME basic block as the call, immediately after it (and
    after the result register is captured), so there is no control flow between
    the call and the release and every path that reached the call reaches the
    release.  Only ever non-empty for callees listed in
    [ctx.native_vec_params] — see the invariant comment in the EApp arm for why
    that restriction is load-bearing. *)
let release_temp_boxes (ctx : Llvm_ctx.ctx) (boxes : string list ref) : unit =
  List.iter
    (fun b -> Llvm_ctx.emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" b))
    !boxes;
  boxes := []
let simd_kind_of_vec = Llvm_ctx.simd_kind_of_vec
let llvm_escape_string = Llvm_ctx.llvm_escape_string
let intern_string = Llvm_ctx.intern_string

(* llvm_ret_ty moved to [Llvm_ctx] (Wave 3 Task 6, chunk 2): [Llvm_calls] and
   [Llvm_tco] both need it too; re-exported bare since ~20 call sites in this
   file still use it unqualified. *)
let llvm_ret_ty = Llvm_ctx.llvm_ret_ty

(* ok_payload_ty moved to [Llvm_calls] (Wave 3 Task 6, chunk 2): its only
   caller besides emit_module's one use below is [emit_raises_wrapper].
   Re-exported bare for that one remaining call site (in emit_module,
   Task 7's territory). *)
let ok_payload_ty = Llvm_calls.ok_payload_ty

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

(* clo_wrap_define moved to [Llvm_calls] (Wave 3 Task 6, chunk 2): a pure
   string-building helper (no ctx dependency) called from emit_atom's two
   first-class-function-reference arms below and from emit_repl_fn_with_
   closure_slot further down — both stay in this file, so re-export bare. *)
let clo_wrap_define = Llvm_calls.clo_wrap_define

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

(* is_leaf_callee / expr_has_call moved to [Llvm_toplevel] (Wave 3 Task 7,
   chunk 2): their only consumer, emit_fn's Phase 4 leaf-function detection,
   moved there too — no re-export needed since nothing in this file
   (emit_expr's core) calls them. *)

(* emit_reduction_check moved to [Llvm_ctx] (Wave 3 Task 6, chunk 2):
   [emit_mutual_tco_group] (now in [Llvm_tco]) needed it alongside [emit_fn]
   here — re-export bare since emit_fn calls it unqualified below. *)
let emit_reduction_check = Llvm_ctx.emit_reduction_check

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

(* A static closure bakes in one compiled version of the function and one
   pointer identity for the whole module, which is correct for a whole-module
   compile but not for:
     - the REPL/JIT, whose fragments are separate modules with their own ctx
       (a per-fragment global would give the same fn different pointers across
       fragments, and can collide in the ORC backend's shared JITDylib);
     - hot-reload boundary functions, which must keep a per-materialization
       object rather than a module-lifetime one.
   Both fall back to the original fresh-march_alloc path. *)
let static_closure_ok ctx (march_name : string) : bool =
  (not ctx.repl)
  && (match ctx.hr_config with
      | None     -> true
      | Some cfg ->
        not (Hot_reload.is_reloadable cfg (Hot_reload.module_of_name march_name)))

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
    (* Record hash -> name so `Show$Atom.show` (emitted at end-of-module) can
       reverse this otherwise-nameless value back to `:name`. *)
    Hashtbl.replace ctx.atom_names h name;
    ("i64", Int64.to_string h)
  | Tir.ALit (March_ast.Ast.LitString s) ->
    (* One immortal string per literal SITE, not one per evaluation: a
       literal is RC-free in TIR (see [intern_string_site]), so a fresh
       rc=1 cell here would be owned by nobody and leak every time the
       site is evaluated. *)
    let (gname, cell) = Llvm_ctx.intern_string_site ctx s in
    let tmp = fresh ctx "sl" in
    emit ctx (Printf.sprintf
                "%s = call ptr @march_string_lit_static(ptr %s, i64 %d, ptr %s)"
                tmp gname (String.length s) cell);
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
      let _ = nparams in
      (* clo_wrap_define builds the wrapper's uniform-ptr ABI signature and the
         concrete forwarding call (boxing/unboxing Float params + return). *)
      let param_tys = List.map llvm_ty ps_tirs in
      Buffer.add_string ctx.extra_fns
        (clo_wrap_define ~drop_clo:ctx.repl wrap_name param_tys target_ret fn_name)
    end;
    (* Allocate closure: header(16) + fn_ptr(8) = 24 bytes *)
    if static_closure_ok ctx v.Tir.v_name then
      ("ptr", Llvm_ctx.intern_static_closure
                ~pad:(Clo_flags.pad_for v.Tir.v_name) ctx fn_name wrap_name)
    else begin
      let hp = fresh ctx "cwrap" in
      emit ctx (Printf.sprintf "%s = call ptr @march_alloc(i64 24)" hp);
      let tgp = fresh ctx "cwt" in
      emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 8" tgp hp);
      emit ctx (Printf.sprintf "store i32 0, ptr %s, align 4" tgp);
      let fp = fresh ctx "cwf" in
      emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" fp hp);
      emit ctx (Printf.sprintf "store ptr @%s, ptr %s, align 8" wrap_name fp);
      ("ptr", hp)
    end
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
    (* Builtin function used as a first-class value (e.g. iolist_hash_fnv1a
       passed to a HOF, or `apply1(file_read, path)` binding the builtin to a
       local that is later invoked via call_ptr).  A builtin is a C-runtime
       extern with its own concrete ABI (raw ptr/i64/double args per
       declare_sig, never the closure-dispatch calling convention) — so,
       exactly like the top_fns TFn arm above, this MUST allocate a real
       closure {header, fn_ptr} whose fn_ptr is a $clo_wrap trampoline
       presenting the uniform-ptr ABI ECallPtr dispatch expects, coercing
       to/from the builtin's real signature internally.  Emitting the bare
       extern address here (as before) let a downstream call_ptr on the
       let-bound local dispatch as a closure — loading a "field" off the
       *code* address as if it were a heap closure header and jumping to
       the garbage result — which SIGBUSed on
       `apply1(file_read, "/etc/hosts")` (first-class builtin regression).
       A LOCAL binding whose name happens to collide with a builtin (e.g. a
       user variable named `kill`, which is also the actor-kill builtin)
       lives in var_slot and must shadow the builtin — fall through to the
       local-load path so we load the local value instead of emitting the
       runtime global @march_kill. *)
    let fn_name = llvm_name (mangle_extern v.Tir.v_name) in
    let wrap_name = fn_name ^ "$clo_wrap" in
    if not (Hashtbl.mem ctx.emitted_wraps wrap_name) then begin
      Hashtbl.add ctx.emitted_wraps wrap_name ();
      let param_ltys =
        match Llvm_builtins.builtin_param_llvm_tys v.Tir.v_name with
        | Some ps -> ps
        | None ->
          (match v.Tir.v_ty with
           | Tir.TFn (ps, _) -> List.map llvm_ty ps
           | _ -> [])
      in
      let target_ret =
        match builtin_ret_ty v.Tir.v_name with
        | Some t -> llvm_ret_ty t
        | None -> llvm_ret_ty (fn_ret_tir v.Tir.v_ty)
      in
      Buffer.add_string ctx.extra_fns
        (clo_wrap_define ~drop_clo:ctx.repl wrap_name param_ltys target_ret fn_name)
    end;
    if static_closure_ok ctx v.Tir.v_name then
      ("ptr", Llvm_ctx.intern_static_closure
                ~pad:(Clo_flags.pad_for v.Tir.v_name) ctx fn_name wrap_name)
    else begin
      let hp = fresh ctx "cwrap" in
      emit ctx (Printf.sprintf "%s = call ptr @march_alloc(i64 24)" hp);
      let tgp = fresh ctx "cwt" in
      emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 8" tgp hp);
      emit ctx (Printf.sprintf "store i32 0, ptr %s, align 4" tgp);
      let fp = fresh ctx "cwf" in
      emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" fp hp);
      emit ctx (Printf.sprintf "store ptr @%s, ptr %s, align 8" wrap_name fp);
      ("ptr", hp)
    end
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
         let ret_tir     = fn_ret_tir v.Tir.v_ty in
         let target_ret  = llvm_ret_ty ret_tir in
         let param_tys   = List.map llvm_ty ps in
         Buffer.add_string ctx.extra_fns
           (clo_wrap_define ~drop_clo:ctx.repl wrap_name param_tys target_ret fn_name)
       end;
       if static_closure_ok ctx resolved then
         ("ptr", Llvm_ctx.intern_static_closure
                   ~pad:(Clo_flags.pad_for resolved) ctx fn_name wrap_name)
       else begin
         let hp  = fresh ctx "cwrap" in
         emit ctx (Printf.sprintf "%s = call ptr @march_alloc(i64 24)" hp);
         let tgp = fresh ctx "cwt" in
         emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 8" tgp hp);
         emit ctx (Printf.sprintf "store i32 0, ptr %s, align 4" tgp);
         let fp  = fresh ctx "cwf" in
         emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" fp hp);
         emit ctx (Printf.sprintf "store ptr @%s, ptr %s, align 8" wrap_name fp);
         ("ptr", hp)
       end
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

(* emit_raises_wrapper moved to [Llvm_calls] (Wave 3 Task 6, chunk 2): the
   EApp/ECallPtr `raises`-extern call sites below (both stay in this file's
   [emit_expr]) call it unqualified — re-export bare. *)
let emit_raises_wrapper = Llvm_calls.emit_raises_wrapper

(* is_trivial_dec_chain_returning / is_trivial_dec_chain moved to [Llvm_tco]
   (Wave 3 Task 6, chunk 2), alongside the mutual-TCO analysis section that
   names them in the brief as moving "as ONE" with the tail-call predicates.
   [emit_expr]'s own Perceus-wrapped-TCO match-arm guards below (self-TCO and
   mutual-TCO ELet/ESeq interception, B7/B8) still call them unqualified —
   this is a one-directional forward reference ([llvm_emit.ml] depending on
   [Llvm_tco]): the predicates are pure structural recursion over [Tir.expr]
   with no dependency back on [emit_expr], so no cycle. Re-exported bare. *)
let is_trivial_dec_chain_returning = Llvm_tco.is_trivial_dec_chain_returning
let is_trivial_dec_chain = Llvm_tco.is_trivial_dec_chain

(* fail_if_unresolved_iface_method moved to [Llvm_calls] (Wave 3 Task 6,
   chunk 2): called from BOTH unqualified_fns consumers in [emit_expr] below
   (the general EApp call path and the ECallPtr no-var-slot catch-all) —
   re-export bare. *)
let fail_if_unresolved_iface_method = Llvm_calls.fail_if_unresolved_iface_method

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
let emit_native_map_inline_loop ctx ~(width : nmap_width) ~unboxed ~arr_atom ~apply_name ~clo_reg
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
let emit_native_map2_inline_loop ctx ~(width : nmap_width) ~unboxed ~arr1_atom ~arr2_atom ~apply_name ~clo_reg
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

(** [march_vault_get] / [march_vault_ns_get] return the NICHE encoding of
    [Option] UNCONDITIONALLY — [None] is a raw null, [Some v] is [v] itself (see
    [make_some]/[make_none] in runtime/march_extras.c).  The C side has no way to
    do better: a vault handle's element type is a phantom, erased before the
    runtime sees anything.

    The compiled call site, however, decodes by the STATIC type, and
    [Repr.repr_of_ty (Option p)] is [Boxed] whenever [p] is niche-UNSAFE.  Three
    element types hit that in practice and all three were broken compiled-only,
    with the interpreter correct:

      Vault(Option(_))  the filed bug — `Vault.get` returns Option(Option(b)),
                        the tag load at [v+8] lands inside the payload's own
                        march_string header, matches no arm, and falls through
                        to the match's default arm ("panic: non-exhaustive
                        pattern match").
      Vault(Float)      same tag load, same panic.
      Vault(Unit)       same shape; SIGSEGV instead (the tag load is off a
                        tagged Unit, not a heap cell).

    So re-encode here, at the one point that knows both halves.  [v] is the
    runtime's niche word; the result is whatever [Option ret_p] decodes as.
    Left untouched (returned as-is) when the call site decodes Niche too — the
    overwhelmingly common case, and the ONLY case before this existed.

    A [TVar] payload is deliberately Niche, not Boxed: [niche_payload_ok] says
    false for it, but the erased convention elsewhere (EAlloc's niche path,
    llvm_case's abstract-arg niche path, ensure_adt_eq_fn) all treat
    [Option(TVar)] as niche, so boxing here would break the agreement in the
    other direction.  See specs/progress/2026-08-20-nested-option-vault-boxed-
    niche-mismatch.md. *)
let emit_vault_opt_reencode ctx (v : string) (ret_ty : Tir.ty) : string =
  (* A literal mirror of [Llvm_case]'s [effective_repr] for this scrutinee type:
     [repr_of_ty], plus its abstract-arg override (a niche-shaped type applied to
     a TVar argument decodes Niche even though [niche_payload_ok] says false for
     a TVar).  Mirrored rather than re-derived from [niche_payload_ok] alone so
     the two cannot drift: [repr_of_ty] also forces Boxed for a collision-set
     type name, and [is_niche_shaped] returns false for one, so a program that
     declares its own `Option` stays consistent on both sides. *)
  let boxed_at_call_site = match ret_ty with
    | Tir.TCon ("Option", ([_] as args)) ->
      (match Repr.repr_of_ty ~collision_set:ctx.collision_set ctx.type_defs ret_ty with
       | Repr.Niche _ | Repr.Newtype _ -> false
       | Repr.Boxed ->
         not (List.exists (function Tir.TVar _ -> true | _ -> false) args
              && Repr.is_niche_shaped ~collision_set:ctx.collision_set
                   ctx.type_defs "Option"))
    | _ -> false
  in
  if not boxed_at_call_site then v
  else begin
    let slot   = fresh ctx "vopt_slot" in
    let l_none = fresh_block ctx "vopt_none" in
    let l_some = fresh_block ctx "vopt_some" in
    let l_join = fresh_block ctx "vopt_join" in
    let isnull = fresh ctx "vopt_isnull" in
    emit ctx (Printf.sprintf "%s = alloca ptr" slot);
    emit ctx (Printf.sprintf "%s = icmp eq ptr %s, null" isnull v);
    emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
                     isnull l_none l_some);
    (* Boxed None: a tag-0 heap cell with no fields — the same shape EAlloc's
       alloc-none-boxed fallthrough emits for a niche-unsafe Option. *)
    emit_label ctx l_none;
    let none_entry = ctor_entry ctx "Option.None" 0 in
    let none_ptr = emit_heap_alloc ctx none_entry.Llvm_ctx.ce_tag 0 in
    emit ctx (Printf.sprintf "store ptr %s, ptr %s" none_ptr slot);
    emit_term ctx (Printf.sprintf "br label %%%s" l_join);
    (* Boxed Some: tag-1 cell, payload in field 0 at the ctor's DECLARED field
       type (Some(a) → TVar → "ptr"), which is exactly what llvm_case's branch
       extraction loads.  The payload word from the runtime is already uniform
       (vault_set coerced it to ptr on the way in: Int tagged, Float boxed via
       march_alloc_float), so it is stored through unchanged. *)
    emit_label ctx l_some;
    let some_entry = ctor_entry ctx "Option.Some" 1 in
    let some_ptr = emit_heap_alloc ctx some_entry.Llvm_ctx.ce_tag 1 in
    let field_ty = match List.nth_opt some_entry.Llvm_ctx.ce_fields 0 with
      | Some t -> llvm_ty t | None -> "ptr" in
    emit_store_field ctx some_ptr 0 field_ty (coerce ctx "ptr" v field_ty);
    emit ctx (Printf.sprintf "store ptr %s, ptr %s" some_ptr slot);
    emit_term ctx (Printf.sprintf "br label %%%s" l_join);
    emit_label ctx l_join;
    let r = fresh ctx "vopt" in
    emit ctx (Printf.sprintf "%s = load ptr, ptr %s" r slot);
    r
  end

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

  (* ── Let binding ───────────────────────────────────────────────────── *)
  | Tir.ELet (v, rhs, body) ->
    (* The rhs is in non-tail position: a self-call here must be an ordinary
       call, not a TCO back-edge (else the let body would be dropped). *)
    let saved_tail = ctx.tco_in_tail in
    ctx.tco_in_tail <- false;
    let (rhs_ty, rhs_val) = emit_expr ctx rhs in
    ctx.tco_in_tail <- saved_tail;
    if is_vec_ty rhs_ty then begin
      (* SIMD vector RHS: keep the slot register-resident (the vector LLVM
         type itself, 16-aligned) instead of routing through the default
         llvm_ty/coerce path — which for these ADT-shaped types resolves to
         "ptr" and would box on every let. Boxing still happens, via the
         coerce vector arms above, at genuine erasure boundaries (calls,
         returns, aggregate fields) — never for a plain local binding. The
         AVar load path (var_llvm_ty-driven) already reads back the native
         vector type once recorded here. *)
      let slot = alloca_name ctx (llvm_name v.Tir.v_name) in
      emit ctx (Printf.sprintf "%%%s.addr = alloca %s, align 16" slot rhs_ty);
      emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr, align 16" rhs_ty rhs_val slot);
      Hashtbl.replace ctx.var_llvm_ty slot rhs_ty;
      emit_expr ctx body
    end else begin
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
    end

  (* ── Sequence ──────────────────────────────────────────────────────── *)
  | Tir.ESeq (e1, e2) ->
    (* e1 is evaluated for effect (non-tail); only e2 is in tail position. *)
    let saved_tail = ctx.tco_in_tail in
    ctx.tco_in_tail <- false;
    let result1 = emit_expr ctx e1 in
    ctx.tco_in_tail <- saved_tail;
    if Llvm_tco.is_trivial_dec_chain e2 then begin
      (* e2 is purely RC bookkeeping (a single Dec/IncRC/Free/drop-fn call, OR
         a whole CHAIN of them, e.g. ESeq(dec_rc a, dec_rc b) — Perceus emits
         multi-op chains whenever a tail call's args require releasing more
         than one now-dead local). Using is_trivial_dec_chain here (rather than
         matching e2 against a single cleanup-op shape) is required: the old
         single-op check only matched when e2 itself was exactly one
         Dec/IncRC/drop-fn call, so a 2+-op chain fell through to the `else`
         branch below, discarding e1's value (e.g. a call's real return value)
         and substituting the last cleanup op's dummy ("i64","0") placeholder
         instead — corrupting the seq's value into a bogus tagged-int and
         crashing (or worse, silently misbehaving) any consumer of it. See
         is_trivial_dec_chain's doc comment for the concrete Perceus shape
         this recognises. *)
      ignore (emit_expr ctx e2);
      result1
    end else begin
      ignore result1;
      emit_expr ctx e2
    end

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
    if (is_vec_ty ty_a || is_vec_ty ty_b) && (f.Tir.v_name = "==" || f.Tir.v_name = "!=") then begin
      (* SIMD vector `==`/`!=`: [ensure_adt_eq_fn] below synthesizes structural
         equality by walking a `type_def`'s fields, but the 5 SIMD vector
         types are opaque compiler primitives (TCon with no type_def/fields —
         their "fields" are vector lanes, invisible to that walk), so the
         general ADT path can't handle them and would otherwise fall through
         to the raw i64/ptr fallback below and reinterpret the vector
         register as a scalar (an LLVM type-mismatch, not just a wrong
         answer). Lower directly: per-lane compare (`fcmp oeq` for the float
         families — NaN-sensitive, a NaN lane always compares unequal, the
         same semantics [impl Eq(F32x4)]'s hand-written per-lane `==` chain
         gives interpreted) then AND all lanes together. *)
      let vv_ty = if is_vec_ty ty_a then ty_a else ty_b in
      let sty = snd (List.find (fun (_, s) -> s.s_vec = vv_ty) simd_tys) in
      let av = coerce ctx ty_a va vv_ty and bv = coerce ctx ty_b vb vv_ty in
      let cmp = fresh ctx "veq" in
      (if sty.s_boundary_float then
         emit ctx (Printf.sprintf "%s = fcmp oeq %s %s, %s" cmp vv_ty av bv)
       else
         emit ctx (Printf.sprintf "%s = icmp eq %s %s, %s" cmp vv_ty av bv));
      let packed = fresh ctx "veq" in
      emit ctx (Printf.sprintf "%s = bitcast <%d x i1> %s to i%d" packed sty.s_lanes cmp sty.s_lanes);
      let alleq = fresh ctx "veq" in
      emit ctx (Printf.sprintf "%s = icmp eq i%d %s, -1" alleq sty.s_lanes packed);
      let r64 = coerce ctx "i1" alleq "i64" in
      let final =
        if f.Tir.v_name = "!=" then begin
          let nr = fresh ctx "veq" in
          emit ctx (Printf.sprintf "%s = xor i64 %s, 1" nr r64); nr
        end else r64
      in
      ("i64", final)
    end else
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
            (* "!=" must match IEEE `<>` semantics used by the interpreter
               (OCaml's polymorphic `<>` on floats is true whenever either
               operand is NaN), i.e. "unordered or not equal" ("une"), not
               "one" (ordered and not equal, which is false for any NaN
               operand). See eval.ml's cmp_op float branch. *)
            | "==" -> "oeq" | "!=" -> "une"
            | "<"  -> "olt" | "<=" -> "ole"
            | ">"  -> "ogt" | ">=" -> "oge"
            | s -> failwith ("unknown cmp: " ^ s)
          in
          let va_f = coerce ctx ty_a va "double" in
          let vb_f = coerce ctx ty_b vb "double" in
          emit ctx (Printf.sprintf "%s = fcmp %s double %s, %s" cmp fpred va_f vb_f);
        end else if ty_a = "ptr" || ty_b = "ptr" then begin
          (* Erased operand(s): the static type is TVar, so the runtime value may
             be a tagged int, a boxed Float (tag -3), or a string.  A raw
             ptr→i64 + icmp mis-orders boxed floats (float-boxing, Stage 2 —
             and, pre-boxing, negative-float bits: mechanism 2).  Dispatch on the
             runtime tag via march_poly_compare (returns -1/0/1) and apply the
             requested ordering vs 0.  A concrete i64 operand coerces to a tagged
             immediate ptr, which march_poly_compare's odd→int arm handles. *)
          let va_p = coerce ctx ty_a va "ptr" in
          let vb_p = coerce ctx ty_b vb "ptr" in
          let c = fresh ctx "pcmp" in
          emit ctx (Printf.sprintf "%s = call i64 @march_poly_compare(ptr %s, ptr %s)" c va_p vb_p);
          emit ctx (Printf.sprintf "%s = icmp %s i64 %s, 0" cmp (int_cmp_pred f.Tir.v_name) c)
        end else begin
          (* Both concrete i64: fast integer compare. *)
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
     fires correctly.

     Html.Safe special case: `Html.Safe(s)` (from `Html.raw`) is a single-ctor
     ADT with one field, so `Repr.repr_of_ty` puts it on the Boxed path (its
     lone ctor's tag is 0). IOList's `Empty` ctor is ALSO tag 0 — every Boxed
     ADT's constructor tags are numbered independently starting at 0, so the
     runtime has no way to tell a bare tag-0 heap cell apart from the other.
     `march_html_auto_escape`'s fallback ("Constructor with tag >= 0: treat as
     IOList") reads a `Safe("...")` value as an empty IOList and silently
     drops the wrapped string instead of inserting it verbatim. Resolve this
     here, while the argument's static TIR type is still known (mono has
     already run): for a statically-known `Html.Safe` atom (and only when
     "Safe" is not a same-short-name collision with some other module's type
     — that ambiguous case must fall through to the generic runtime path
     below), load the wrapped String directly out of the Boxed cell's field 0
     (offset +16, the standard Boxed-ADT single-field layout) and pass it
     through unescaped — verbatim insertion is exactly `Html.Safe`'s
     contract, so no runtime call is needed at all. *)
  | Tir.EApp (f, [a]) when f.Tir.v_name = "html_auto_escape"
                            && (match atom_tir_ty a with
                                | Tir.TCon ("Safe", _) ->
                                  not (Collision_set.is_colliding ctx.collision_set "Safe")
                                | _ -> false) ->
    let vp = emit_atom_as ctx "ptr" a in
    let fp = fresh ctx "safe_fp" in
    emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" fp vp);
    let r = fresh ctx "safe_s" in
    emit ctx (Printf.sprintf "%s = load ptr, ptr %s" r fp);
    ("ptr", r)

  (* Every OTHER type: the runtime's polymorphic dispatch is only safe for the
     three representations it can actually recognise — a low-bit-tagged
     immediate, a MARCH_STRING_TAG string, and a genuine IOList.  Its final
     arm ("Constructor with tag >= 0: treat as IOList") is a guess, and it is
     wrong for every user ADT: constructor tags are numbered per type from 0,
     so `B(String)` (tag 1) was read as `IOList.Str` and its field emitted RAW
     AND UNESCAPED, and `C(_, _)` (tag 2) was read as `IOList.Segments` and
     its field walked as a cons list — a segfault.  Decide it here instead,
     where the static TIR type is still known, and only route to the runtime
     the cases it genuinely handles.  Anything else — user ADTs, records,
     tuples, and the `Safe`-name-collision case that falls through the arm
     above — goes through `march_value_to_string` first, then escapes the
     resulting real String. *)
  | Tir.EApp (f, [a]) when f.Tir.v_name = "html_auto_escape" ->
    let runtime_safe =
      match atom_tir_ty a with
      | Tir.TString | Tir.TInt | Tir.TFloat | Tir.TBool -> true
      | Tir.TCon ("IOList", _) -> true
      (* An unresolved type variable is the genuinely undecidable case, and it
         is NOT hypothetical: a value reaching this hole through a closure
         stored in a container (defunctionalized dispatch, e.g.
         `Bx(Cons(fn x -> ~H"<p>${x}</p>", Nil))`) is not specialised by mono
         and arrives as TVar.  Neither answer is right for it — an IOList
         wants flattening, an ADT must not be flattened, and nothing at
         runtime can tell them apart, which is the whole defect.

         So choose the failure that is not a vulnerability: stringify.  A
         genuine IOList partial reaching a polymorphic hole renders as
         `#<tag:2>` instead of its markup — visibly wrong, and a real
         regression for that (rare) pattern.  Routing it to the runtime
         instead would leave a tag-1 ADT emitting its String field raw and
         unescaped, and a tag-2 ADT segfaulting.  A wrong-looking page beats
         an XSS and a crash.

         Fixing this properly means giving the runtime a way to identify the
         type — march_hdr.pad is free for non-record ADTs and could carry a
         type id — which is out of scope here; see
         specs/todos/2026-08-05-boxed-adt-type-id.md. *)
      | Tir.TVar _ -> false
      | _ -> false
    in
    let v = emit_atom_as ctx "ptr" a in
    let v =
      if runtime_safe then v
      else begin
        let s = fresh ctx "hae_str" in
        emit ctx
          (Printf.sprintf "%s = call ptr @march_value_to_string(ptr %s)" s v);
        s
      end
    in
    let r = fresh ctx "hae" in
    emit ctx (Printf.sprintf "%s = call ptr @march_html_auto_escape(ptr %s)" r v);
    ("ptr", r)

  (* ── ~H sigil: html_escape_ctx(id, v) ─────────────────────────────────
     The contextual successor to html_auto_escape. The escaper id is chosen at
     COMPILE time from the parse context (lib/ctxesc/automaton.ml) and arrives
     as a literal, so both decisions this arm makes are static.

     CARRIED OVER FROM THE ADT-misread fix (see
     specs/progress/2026-08-05-h-sigil-adt-misread.md): the runtime must NEVER
     dispatch on a heap tag. Constructor tags are numbered per type, so a
     tag-1 user ADT is indistinguishable from IOList.Str, which is how that bug
     emitted unescaped output and segfaulted. `march_html_escape_ctx` therefore
     takes a real String and aborts on anything else; normalising is this arm's
     job.

     One case must NOT be escaped: a nested `~H` partial is an IOList of
     already-safe HTML, and escaping it would double-escape the markup. That is
     only sound when the surrounding context is HTML too — an IOList spliced
     into an href is a context mismatch, so it is flattened and then escaped
     for whatever context it actually landed in. Type-indexed trust
     (Html.Trusted) makes this precise in a later task; until then the rule is
     "verbatim only when the escaper is EscHtml". *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt id); a])
    when f.Tir.v_name = "html_escape_ctx" ->
    let is_html_ctx = id = 0 (* Context.escaper_id EscHtml *) in
    (* Html.Safe and IOList are both already-safe HTML, but they are UNWRAPPED
       differently. march_html_auto_escape's C body does not understand Safe at
       all — Task 0 fixed that case in the emitter, by loading field 0 — so
       handing it a Safe returns the empty string. Keep the two apart. *)
    (* Context-indexed trust. Each Trusted* type names the ONE context its
       string may be inserted into verbatim; anywhere else it is escaped like
       any other value. `Safe` is the legacy context-free form and is treated
       as HTML trust.

       This is resolved entirely here, at compile time: the type is static and
       the escaper id was folded by the desugar, so a mismatch costs nothing at
       runtime -- it just takes the escaping path. That is why these are
       separate types rather than one type carrying a context tag; a tag would
       be runtime data and could not be resolved statically.

       All are single-field ADTs, so unwrapping is the same field-0 load the
       Safe path already used.

       Escaper ids are Context.escaper_id / MARCH_ESC_* (see
       runtime/march_ctx_escape.h). A url trust covers both the whole-URL and
       component escapers, and a css trust both the value and declaration
       ones, because those pairs differ in POSITION within one language, not in
       which language the string is. *)
    let trusted_for name =
      if Collision_set.is_colliding ctx.collision_set name then None
      else
        match name with
        | "Safe" | "TrustedHtml" -> Some [ 0 ]
        | "TrustedAttr" -> Some [ 1 ]
        | "TrustedUrl" -> Some [ 2; 3 ]
        | "TrustedCss" -> Some [ 4; 7 ]
        (* A js trust covers BOTH JS escapers. 5 is a hole inside a string
           literal, 9 a hole at an expression position; they differ in
           POSITION within one language, exactly as the url and css pairs
           above do, and trusting a string as JS trusts it as JS wherever JS
           is being written. This is also what keeps `Html.trust_js` usable at
           all after the 2026-08-20 fix: expression position is the only place
           trusted JS is ever worth inserting, and it is precisely the place
           an untrusted value now gets quoted into inertness. *)
        | "TrustedJs" -> Some [ 5; 9 ]
        | _ -> None
    in
    let trusted_ids =
      match atom_tir_ty a with
      | Tir.TCon (n, _) -> trusted_for n
      | _ -> None
    in
    let is_safe = trusted_ids <> None in
    let is_iolist =
      match atom_tir_ty a with Tir.TCon ("IOList", _) -> true | _ -> false in
    let v = emit_atom_as ctx "ptr" a in
    (* Normalise to a real String first, by whichever route actually works for
       this type. `march_value_to_string` CANNOT flatten an IOList — it renders
       the constructor spine as `#<tag:2>` — so a known IOList/Safe must go
       through `march_html_auto_escape`, whose IOList path flattens verbatim.
       Everything else, including TVar (the undecidable case), takes
       to_string. *)
    let v =
      match atom_tir_ty a with
      | Tir.TString -> v
      | _ when is_safe ->
        (* Boxed single-field ADT: the wrapped String is at offset +16. *)
        let fp = fresh ctx "hec_safe_fp" in
        emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" fp v);
        let sv = fresh ctx "hec_safe_s" in
        emit ctx (Printf.sprintf "%s = load ptr, ptr %s" sv fp);
        sv
      | _ when is_iolist ->
        let fv = fresh ctx "hec_flat" in
        emit ctx
          (Printf.sprintf "%s = call ptr @march_html_auto_escape(ptr %s)" fv v);
        fv
      | _ ->
        let sv = fresh ctx "hec_str" in
        emit ctx
          (Printf.sprintf "%s = call ptr @march_value_to_string(ptr %s)" sv v);
        sv
    in
    let trust_covers_this_context =
      match trusted_ids with
      | Some ids -> List.mem id ids
      | None -> is_html_ctx && is_iolist
    in
    if trust_covers_this_context then
      (* The value is trusted for exactly this context: insert verbatim. *)
      ("ptr", v)
    else begin
      let r = fresh ctx "hec" in
      emit ctx
        (Printf.sprintf
           "%s = call ptr @march_html_escape_ctx(i64 %d, ptr %s)" r id v);
      ("ptr", r)
    end

  (* A RUNTIME escaper id.
     
     This used to be a hard failure, on the premise that only the ~H desugar
     calls html_escape_ctx and it always folds the context statically. That
     premise was wrong: Html.tag (stdlib/html.march) classifies an attribute
     NAME at runtime and picks the escaper from it, because it composes markup
     outside the sigil and has no compile-time context to fold. A dynamic id is
     correct there, not a bug.

     The ~H path is unaffected — it always emits a literal and takes the arm
     above, which is also where the already-safe-HTML specialisation lives.
     That specialisation needs a literal id and is simply not available here;
     a dynamic caller passes a String, so it does not apply.

     Safety is unchanged: march_html_escape_ctx validates the id and aborts on
     one it does not know, so a wrong id fails loudly rather than silently
     skipping an escaper. *)
  | Tir.EApp (f, [idx; a]) when f.Tir.v_name = "html_escape_ctx" ->
    let id_v = emit_atom_as ctx "i64" idx in
    let v = emit_atom_as ctx "ptr" a in
    let v =
      match atom_tir_ty a with
      | Tir.TString -> v
      | _ ->
        let sv = fresh ctx "hecd_str" in
        emit ctx
          (Printf.sprintf "%s = call ptr @march_value_to_string(ptr %s)" sv v);
        sv
    in
    let r = fresh ctx "hecd" in
    emit ctx
      (Printf.sprintf "%s = call ptr @march_html_escape_ctx(i64 %s, ptr %s)"
         r id_v v);
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

  (* ── {int,bool,float}_to_string: explicit coerce before the C call ──── *
     These have no dedicated arg-coercion in the general EApp path (that path
     only coerces args for user-defined fns registered in top_fn_param_tys —
     builtins fall through with each arg's NATURAL emitted type). Normally the
     argument already IS the declared scalar type (Int/Bool/Float locals emit
     as i64/i64/double directly), so this goes unnoticed — but a value that
     crossed an erased/generic boundary (e.g. an Actor.call reply, whose Ok
     payload stays a TVar so the case-match binds it as "ptr") arrives here
     STILL "ptr"-typed, and the fallback path emits e.g.
     `call ptr @march_int_to_string(ptr %v)` — a declared-signature mismatch
     that happens to "work" at the ABI level (ptr and i64 share a register)
     and so prints the raw tagged bits verbatim (5 -> "11") instead of
     coercing. Coerce explicitly here, matching every other scalar builtin
     (int_not, is_int_bitwise, …) in this file. *)
  | Tir.EApp (f, [a]) when f.Tir.v_name = "int_to_string" ->
    let va = emit_atom_as ctx "i64" a in
    let r  = fresh ctx "its" in
    emit ctx (Printf.sprintf "%s = call ptr @march_int_to_string(i64 %s)" r va);
    ("ptr", r)

  | Tir.EApp (f, [a]) when f.Tir.v_name = "bool_to_string" ->
    let va = emit_atom_as ctx "i64" a in
    let r  = fresh ctx "bts" in
    emit ctx (Printf.sprintf "%s = call ptr @march_bool_to_string(i64 %s)" r va);
    ("ptr", r)

  | Tir.EApp (f, [a]) when f.Tir.v_name = "float_to_string" ->
    let va = emit_atom_as ctx "double" a in
    let r  = fresh ctx "fts" in
    emit ctx (Printf.sprintf "%s = call ptr @march_float_to_string(double %s)" r va);
    ("ptr", r)

  (* ── Task builtins (Phase 1: inline LLVM IR, no C runtime) ────────── *)
  (* Thunks are fn x -> expr (Int -> a).  task_spawn calls the closure
     with dummy arg 0, boxes result into a Task heap object.
     task_await_unwrap unboxes field 0 from the Task. *)

  (* task_spawn(thunk_closure) → spawn as async green thread via runtime.
     A Float-returning thunk's apply fn already boxes its result through the
     generic "double"->"ptr" coerce (march_alloc_float — float-boxing stage
     2), so the closure hands the trampoline a genuine heap pointer here; no
     dedicated spawn variant is needed. See task_await_unwrap's "double"
     branch for the matching unbox. *)
  | Tir.EApp (f, [clo_atom]) when f.Tir.v_name = "task_spawn" ->
    let (_, clo_ptr) = emit_atom ctx clo_atom in
    let result = fresh ctx "tsres" in
    emit ctx (Printf.sprintf "%s = call ptr @march_task_spawn_thunk(ptr %s)"
                result clo_ptr);
    ("ptr", result)

  (* Signal.watch (stdlib/signal.march): register/remove a deferred OS-signal
     watcher, or raise a signal to self.  The `code` is an Int (untag to raw
     i64); the watcher closure is passed OWNED (borrow.ml marks the arg
     consuming) so the runtime keeps its reference across drains. *)
  | Tir.EApp (f, [code_atom; clo_atom]) when f.Tir.v_name = "signal_watch" ->
    let (code_ty, code_v) = emit_atom ctx code_atom in
    let code_i64 = coerce ctx code_ty code_v "i64" in
    let (clo_ty, clo_v) = emit_atom ctx clo_atom in
    let clo_ptr = coerce ctx clo_ty clo_v "ptr" in
    emit ctx (Printf.sprintf "call void @march_signal_watch(i64 %s, ptr %s)"
                code_i64 clo_ptr);
    ("ptr", "null")
  | Tir.EApp (f, [code_atom]) when f.Tir.v_name = "signal_unwatch" ->
    let (code_ty, code_v) = emit_atom ctx code_atom in
    let code_i64 = coerce ctx code_ty code_v "i64" in
    emit ctx (Printf.sprintf "call void @march_signal_unwatch(i64 %s)" code_i64);
    ("ptr", "null")
  | Tir.EApp (f, [code_atom]) when f.Tir.v_name = "signal_raise_self" ->
    let (code_ty, code_v) = emit_atom ctx code_atom in
    let code_i64 = coerce ctx code_ty code_v "i64" in
    emit ctx (Printf.sprintf "call void @march_signal_raise_self(i64 %s)" code_i64);
    ("ptr", "null")

  (* task_await_unwrap(task_ptr) → spin-wait then untag result directly.

     There is deliberately NO @march_task_await call here.  One used to be
     emitted, its result never read: march_task_await allocates an Ok wrapper
     (mk_ok, 24 B) that the unwrap path has no use for, and nothing released
     it — one leaked Result cell per await, on top of the leaked Task below.
     @march_task_await_value performs the same task_wait_done and returns
     task[3] directly, which is the whole point of the _value variant. *)
  | Tir.EApp (f, [a]) when f.Tir.v_name = "task_await_unwrap" ->
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
  | Tir.EApp (f, [a]) when f.Tir.v_name = "task_await" ->
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
      || f.Tir.v_name = "int_mod_euclid" || f.Tir.v_name = "int_div_euclid" ->
    let va = emit_atom_as ctx "i64" a in
    let vb = emit_atom_as ctx "i64" b in
    let r  = fresh ctx "ar" in
    (* Route through a checked runtime helper so a zero divisor traps via
       march_panic (matching the interpreter) instead of executing a raw
       sdiv/srem/urem, which is undefined for a 0 divisor. *)
    let helper = match f.Tir.v_name with
      | "int_mod"        -> "march_checked_imod"
      | "int_div"        -> "march_checked_idiv"
      | "int_mod_euclid" -> "march_checked_emod"
      | "int_div_euclid" -> "march_checked_ediv"
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

  (* ── actor_register: March-level arg order is (pid, name) — matching
     monitor/kill — but the C entry point is march_actor_register(name,
     actor): NAME FIRST.  The general EApp path below passes args in TIR
     order unchanged, which would swap the two pointers at the C ABI
     boundary (the runtime would read the Pid as the name string and vice
     versa). Swap explicitly here, same shape as the vault_set arm above. *)
  | Tir.EApp (f, [pid; name])
    when f.Tir.v_name = "actor_register" ->
    let vp = emit_atom_as ctx "ptr" pid in
    let vn = emit_atom_as ctx "ptr" name in
    let r  = fresh ctx "ar" in
    emit ctx (Printf.sprintf
      "%s = call i64 @march_actor_register(ptr %s, ptr %s)" r vn vp);
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

  (* ── Vault READS/deletes: the KEY needs the same ptr coercion the write
     arms above already apply.  Only the writers were special-cased, so a
     read fell through to the general EApp path and passed the key with its
     NATURAL llvm type — an Int key reached march_vault_get as a raw i64
     while march_vault_set had stored it tagged ((n<<1)|1).  The two then
     stringified to different vault keys, so a value stored under an Int key
     could never be read back (and, before vault_key_cstr learned to
     classify the uniform representation, the raw i64 was dereferenced as a
     march_string* → SIGSEGV).  Table/namespace/fn args are already ptr;
     trailing scalar args (delta) stay i64.
     See specs/progress/2026-08-20-vault-non-string-key-native-crash.md. *)
  | Tir.EApp (f, [tbl; key])
    when f.Tir.v_name = "vault_get" ->
    let vt = emit_atom_as ctx "ptr" tbl in
    let vk = emit_atom_as ctx "ptr" key in
    let r  = fresh ctx "vg" in
    emit ctx (Printf.sprintf
      "%s = call ptr @march_vault_get(ptr %s, ptr %s)" r vt vk);
    ("ptr", emit_vault_opt_reencode ctx r (fn_ret_tir f.Tir.v_ty))

  | Tir.EApp (f, [tbl; key])
    when f.Tir.v_name = "vault_drop" ->
    let vt = emit_atom_as ctx "ptr" tbl in
    let vk = emit_atom_as ctx "ptr" key in
    emit ctx (Printf.sprintf
      "call ptr @march_vault_drop(ptr %s, ptr %s)" vt vk);
    ("i64", "0")

  | Tir.EApp (f, [tbl; key; fn_atom])
    when f.Tir.v_name = "vault_update" ->
    let vt = emit_atom_as ctx "ptr" tbl in
    let vk = emit_atom_as ctx "ptr" key in
    let vf = emit_atom_as ctx "ptr" fn_atom in
    emit ctx (Printf.sprintf
      "call ptr @march_vault_update(ptr %s, ptr %s, ptr %s)" vt vk vf);
    ("i64", "0")

  | Tir.EApp (f, [tbl; key; delta])
    when f.Tir.v_name = "vault_incr" ->
    let vt = emit_atom_as ctx "ptr" tbl in
    let vk = emit_atom_as ctx "ptr" key in
    let vd = emit_atom_as ctx "i64" delta in
    let r  = fresh ctx "vi" in
    emit ctx (Printf.sprintf
      "%s = call i64 @march_vault_incr(ptr %s, ptr %s, i64 %s)" r vt vk vd);
    ("i64", r)

  | Tir.EApp (f, [ns; key; value])
    when f.Tir.v_name = "vault_ns_set" ->
    let vn = emit_atom_as ctx "ptr" ns in
    let vk = emit_atom_as ctx "ptr" key in
    let vv = emit_atom_as ctx "ptr" value in
    emit ctx (Printf.sprintf
      "call ptr @march_vault_ns_set(ptr %s, ptr %s, ptr %s)" vn vk vv);
    ("i64", "0")

  | Tir.EApp (f, [ns; key])
    when f.Tir.v_name = "vault_ns_get" ->
    let vn = emit_atom_as ctx "ptr" ns in
    let vk = emit_atom_as ctx "ptr" key in
    let r  = fresh ctx "vng" in
    emit ctx (Printf.sprintf
      "%s = call ptr @march_vault_ns_get(ptr %s, ptr %s)" r vn vk);
    ("ptr", emit_vault_opt_reencode ctx r (fn_ret_tir f.Tir.v_ty))

  | Tir.EApp (f, [ns; key])
    when f.Tir.v_name = "vault_ns_drop" ->
    let vn = emit_atom_as ctx "ptr" ns in
    let vk = emit_atom_as ctx "ptr" key in
    emit ctx (Printf.sprintf
      "call ptr @march_vault_ns_drop(ptr %s, ptr %s)" vn vk);
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

  (* ── Channel/MPST payload sends: coerce the carried value/label to the
     uniform tagged ptr rep so it survives the void* round-trip through the
     C channel queue and matches the ptr→i64 CONDITIONAL-UNTAG that
     Chan.recv / MPST.recv apply on the receive side (llvm_ctx.coerce
     "ptr"→"i64", which ashr's iff the low bit is set).

     march_chan_send / march_chan_choose / march_mpst_send are all declared
     with a `ptr` payload/label/value slot (llvm_builtins.ml).  The general
     EApp path below emits each arg with its NATURAL llvm type, so an Int
     payload would arrive as a raw i64 (e.g. 43) instead of the tagged form
     ((43<<1)|1 = 87); recv then sees low-bit-set and ashr's it → 21.  Every
     odd Int corrupts as (v-1)/2 and Bool (odd-tagged immediate) flips
     true→false; heap payloads (String/record/ADT) already arrive as `ptr`
     and pass through emit_atom_as unchanged (coerce short-circuits ptr→ptr).
     Coerce ONLY the value/label arg — the endpoint/role args are already ptr.
     Return type mirrors the general path: these builtins return `Chan`
     (TCon("Chan",[]) → "ptr"). *)
  | Tir.EApp (f, [ep; value])
    when f.Tir.v_name = "chan_send" ->
    let vep = emit_atom_as ctx "ptr" ep in
    let vv  = emit_atom_as ctx "ptr" value in
    let r = fresh ctx "cr" in
    emit ctx (Printf.sprintf
      "%s = call ptr @march_chan_send(ptr %s, ptr %s)" r vep vv);
    ("ptr", r)

  | Tir.EApp (f, [ep; label])
    when f.Tir.v_name = "chan_choose" ->
    let vep = emit_atom_as ctx "ptr" ep in
    let vl  = emit_atom_as ctx "ptr" label in
    let r = fresh ctx "cr" in
    emit ctx (Printf.sprintf
      "%s = call ptr @march_chan_choose(ptr %s, ptr %s)" r vep vl);
    ("ptr", r)

  | Tir.EApp (f, [ep; role; value])
    when f.Tir.v_name = "mpst_send" ->
    let vep   = emit_atom_as ctx "ptr" ep in
    let vrole = emit_atom_as ctx "ptr" role in
    let vv    = emit_atom_as ctx "ptr" value in
    let r = fresh ctx "cr" in
    emit ctx (Printf.sprintf
      "%s = call ptr @march_mpst_send(ptr %s, ptr %s, ptr %s)" r vep vrole vv);
    ("ptr", r)

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

  (* ── Colliding general-interface runtime dispatch ──────────────────── *)
  (* Mono rewrote a call whose static (bare) argument type is declared by >=2
     modules into a call to this sentinel; generate (once, memoized in
     ctx.emitted_dispatch_fns) a function that switches on the callee's
     runtime ctor tag and tail-calls the correct module-qualified impl —
     lazily, exactly as [==] generates [ensure_adt_eq_fn].  The exact impl
     symbols (with Mono's per-call specialization suffix) come from
     [Dispatch_registry], keyed by this sentinel name. *)
  | Tir.EApp (f, args) when Dispatch_registry.is_sentinel f.Tir.v_name ->
    let arg_pairs = List.map (fun a -> emit_atom ctx a) args in
    (* arg0 is the dispatched value; force to ptr so the Boxed-header tag load
       is well-typed (Task 2 forces colliding types Boxed → this is a no-op in
       practice). Remaining args forward verbatim. *)
    let param_tys, arg_vals =
      List.split (List.mapi (fun i (ty, v) ->
          if i = 0 then ("ptr", coerce ctx ty v "ptr") else (ty, v)) arg_pairs) in
    let rows = match Dispatch_registry.lookup f.Tir.v_name with
      | Some r -> r | None -> [] in
    (* Return type = the impls' actual return (they all share it); fall back to
       the call-site annotation if the impl isn't registered. *)
    let ret_tir = match rows with
      | (_, sym) :: _ ->
        (match Hashtbl.find_opt ctx.top_fn_ret_ty sym with
         | Some t -> t | None -> fn_ret_tir f.Tir.v_ty)
      | [] -> fn_ret_tir f.Tir.v_ty in
    let ret_ty = llvm_ret_ty ret_tir in
    (match Llvm_dispatch.ensure_dispatch_fn ctx ~fn_name:f.Tir.v_name
             ~param_tys ~ret_ty ~rows with
     | None ->
       failwith (Printf.sprintf
         "interface dispatch fn %s has no runtime-tag rows" f.Tir.v_name)
     | Some fn_name ->
       let args_str = String.concat ", "
           (List.map2 (fun ty v -> ty ^ " " ^ v) param_tys arg_vals) in
       if ret_ty = "void" then begin
         emit ctx (Printf.sprintf "call void @%s(%s)" fn_name args_str);
         ("i64", "0")
       end else begin
         let r = fresh ctx "ifd" in
         emit ctx (Printf.sprintf "%s = call %s @%s(%s)" r ret_ty fn_name args_str);
         (ret_ty, r)
       end)

  (* ── Native array map inline loop, non-capturing closure (P10 Phase 2) ──
     native_map_inline.ml rewrites EApp(native_int_arr_map/native_float_arr_map,
     [arr; clo]) into this synthetic call whenever the closure is a fresh,
     non-capturing lambda used nowhere else: the 2nd arg becomes a direct
     reference to the lifted apply fn instead of a heap closure, so there is
     no closure to allocate or dispatch through indirectly.
     Every March closure (including this one) uses the tagged/boxed generic
     ptr ABI (see [is_apply_fn]) — Int wire-tags (n<<1)|1, Float wire-boxes
     via march_alloc_float/march_unbox_float — so this loop still pays that
     per-element tag/box cost.  What changes is that the call to the apply fn
     is now a DIRECT call to a function defined in this same LLVM module
     (not an indirect call through an opaque C-runtime function pointer,
     which cannot be inlined across the runtime/generated-IR translation-
     unit boundary): LLVM's own inliner can fold simple apply-fn bodies in,
     and for Int, instcombine can then cancel the tag/untag round-trip
     entirely, leaving a plain scalar loop the vectorizer can pack into SIMD.
     Float keeps the alloc/unbox calls (real heap allocations) in the loop
     body, which blocks vectorization — see specs/optimizations.md P10.
     $clo is `null`: the apply body never reads it (no free vars to load).
     "..._unboxed" (Float/f32 only — Stage 4 Option B) calls an unboxed
     clone of the apply fn instead, see
     [Native_map_inline.try_unboxed_variant] and
     [emit_native_map_inline_loop]'s [~unboxed] doc.

     Narrow-widths task (2026-08): the per-name if/else that used to pick
     `~is_float`/`len_fn`/`alloc_fn` here is replaced by
     [decode_nmap_inline_name] + [nmap_width_of_prefix] — same synthetic-name
     recognition, generalized to f32/i32/u8 without new arms. The [when]
     guard matches any name [Native_map_inline.inline_name_of] can produce;
     anything else falls through to the general EApp arm below. *)
  | Tir.EApp (f, [arr_atom; Tir.AVar apply_v])
    when (match decode_nmap_inline_call f.Tir.v_name with Some (_, false, _) -> true | _ -> false) ->
    let (width, _, unboxed) = Option.get (decode_nmap_inline_call f.Tir.v_name) in
    let apply_name = llvm_name (mangle_extern apply_v.Tir.v_name) in
    emit_native_map_inline_loop ctx ~width ~unboxed ~arr_atom ~apply_name ~clo_reg:"null"

  (* ── Native array map inline loop, capturing closure (P10 Phase 2c) ──
     Same rewrite/codegen as Phase 2 above, but for a closure that DOES
     capture free variables: native_map_inline.ml leaves the closure
     allocation (and any alias-copy lets / Perceus RC ops around it)
     completely untouched — the struct is a real, live value now, not
     something safe to drop — and only rewrites the terminal call site to
     this 3-arg form, adding the closure pointer as a genuine 3rd argument.
     The call below passes it as the apply fn's real $clo, instead of the
     `null` Phase 2 uses: the apply body loads its free variables from it
     via ordinary EField (GEP+load), and since $clo is loop-invariant, LLVM
     can hoist that load above the loop once the call is inlined — e.g. a
     DataFrame `col +. scalar` (`fn x -> x +. f`, capturing `f`) reduces to
     one hoisted load of `f` plus a per-element fadd, same vectorization
     story as Phase 2's non-capturing case. *)
  | Tir.EApp (f, [arr_atom; Tir.AVar apply_v; clo_atom])
    when (match decode_nmap_inline_call f.Tir.v_name with Some (_, false, _) -> true | _ -> false) ->
    let (width, _, unboxed) = Option.get (decode_nmap_inline_call f.Tir.v_name) in
    let apply_name = llvm_name (mangle_extern apply_v.Tir.v_name) in
    let (clo_ty0, clo_v0) = emit_atom ctx clo_atom in
    let clo_reg = coerce ctx clo_ty0 clo_v0 "ptr" in
    emit_native_map_inline_loop ctx ~width ~unboxed ~arr_atom ~apply_name ~clo_reg

  (* ── Native array map2 inline loop, non-capturing closure ────────────
     [Native_map_inline]'s two-array counterpart of the non-capturing arm
     above — same rewrite, same reasoning, just [__native_*_map2_inline]
     names and two leading array atoms instead of one. See
     [emit_native_map2_inline_loop]. *)
  | Tir.EApp (f, [arr1_atom; arr2_atom; Tir.AVar apply_v])
    when (match decode_nmap_inline_call f.Tir.v_name with Some (_, true, _) -> true | _ -> false) ->
    let (width, _, unboxed) = Option.get (decode_nmap_inline_call f.Tir.v_name) in
    let apply_name = llvm_name (mangle_extern apply_v.Tir.v_name) in
    emit_native_map2_inline_loop ctx ~width ~unboxed ~arr1_atom ~arr2_atom ~apply_name ~clo_reg:"null"

  (* ── Native array map2 inline loop, capturing closure ──────────────── *)
  | Tir.EApp (f, [arr1_atom; arr2_atom; Tir.AVar apply_v; clo_atom])
    when (match decode_nmap_inline_call f.Tir.v_name with Some (_, true, _) -> true | _ -> false) ->
    let (width, _, unboxed) = Option.get (decode_nmap_inline_call f.Tir.v_name) in
    let apply_name = llvm_name (mangle_extern apply_v.Tir.v_name) in
    let (clo_ty0, clo_v0) = emit_atom ctx clo_atom in
    let clo_reg = coerce ctx clo_ty0 clo_v0 "ptr" in
    emit_native_map2_inline_loop ctx ~width ~unboxed ~arr1_atom ~arr2_atom ~apply_name ~clo_reg

  (* ── SIMD vector ops (Task 2) — inline register-resident lowering ────
     Every `simd_<t>_<op>` builtin, including `load`/`store` (bounds-checked
     GEP+load / FBIP-COW store — originally scoped to Task 3, pulled forward
     here because a whole-stdlib compile unconditionally compiles
     stdlib/simd.march's load/store wrapper bodies, so a "fail if reached"
     placeholder faulted on every such compile regardless of whether the
     calling program itself used load/store), lowers here directly to
     native LLVM vector instructions/intrinsics instead of a runtime call
     — see the per-op recipe table in
     .superpowers/sdd/2026-08-10-simd-vector-types/task-2-brief.md (and
     task-3-brief.md's Step 2 for the load/store recipe specifically). Args
     arrive either already vector/boundary-typed (register-resident, from
     the ELet vector-slot fast path or a prior SIMD op's result) or boxed
     `ptr` (a function parameter or a value that crossed an erasure
     boundary) — [coerce]'s vector arms (llvm_ctx.ml, ahead of its
     "(ptr, scalar)"/"(scalar, ptr)" generic catch-alls) handle both
     uniformly. *)
  | Tir.EApp (f, args) when decode_simd_call f.Tir.v_name <> None ->
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

  (* ── General function call ─────────────────────────────────────────── *)
  | Tir.EApp (f, args) ->
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

  (* ── ECallPtr to a `blocking` extern: OS-thread dispatch ─────────────── *)
  (* Exactly the same situation as the `raises` arm above: defun may emit
     extern calls as ECallPtr, so `blocking` externs must be caught here —
     before the generic global-call arms — or they fall through to a plain
     direct call and lose their blocking dispatch entirely.

     That is not merely a missed optimization.  The C call then runs INLINE on
     the green thread's stack, blocking the whole scheduler OS thread; once
     every scheduler thread is parked inside one, runnable green threads can
     never be dispatched and the program deadlocks. *)
  | Tir.ECallPtr (Tir.AVar f, args)
    when (not (Hashtbl.mem ctx.var_slot (llvm_name f.Tir.v_name)))
      && (let rn =
            if Hashtbl.mem ctx.top_fns f.Tir.v_name then f.Tir.v_name
            else match Hashtbl.find_opt ctx.unqualified_fns f.Tir.v_name with
              | Some q -> q | None -> f.Tir.v_name in
          Hashtbl.mem ctx.blocking_externs rn) ->
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

  | Tir.ECallPtr (Tir.AVar f, [a; b])
    when f.Tir.v_name = "int_mod" || f.Tir.v_name = "int_div"
      || f.Tir.v_name = "int_mod_euclid" || f.Tir.v_name = "int_div_euclid" ->
    let va = emit_atom_as ctx "i64" a in
    let vb = emit_atom_as ctx "i64" b in
    let r  = fresh ctx "ar" in
    (* Same checked-helper routing as the EApp form above. *)
    let helper = match f.Tir.v_name with
      | "int_mod"        -> "march_checked_imod"
      | "int_div"        -> "march_checked_idiv"
      | "int_mod_euclid" -> "march_checked_emod"
      | "int_div_euclid" -> "march_checked_ediv"
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

  (* ── Capture-free lambda closure: static immortal global ────────────
     defun.ml:441 lifts EVERY lambda to
       EAlloc (TCon (clo_name, []), fn_ptr_atom :: fv_atoms)
     so a lambda that captures nothing leaves fv_atoms = [] — EXACTLY ONE
     argument, the lifted apply function's address.  Everything the object
     would hold is then a compile-time constant, so — exactly like a
     top-level fn used as a first-class value (the [AVar v when ...] arm
     in [emit_atom] above) — it can be one immortal global instead of a
     fresh march_alloc at every materialization (which additionally
     leaked: nothing ever dropped it).

     A closure struct with two or more arguments captures at least one
     free variable, and its contents differ per instance — it MUST keep
     allocating.  Sharing one global there would silently share one
     captured environment across every instance: a correctness bug, not a
     missed optimization.  Hence the exact single-argument match below,
     tried before the generic boxed-allocation arm so it takes priority.

     Unlike the top-level-function case, no $clo_wrap trampoline is
     generated: the lifted apply function already takes
     (clo_ptr, params...), which IS the closure-dispatch ABI, so field 0
     can point straight at it.

     Eligibility mirrors [static_closure_ok] (REPL/JIT fragments and hot-
     reload boundaries both need per-materialization objects) EXCEPT for
     hot-reload: [static_closure_ok] expects a March-level dotted name to
     resolve the owning module, but [tcon_name] here is
     "$Clo_" ^ fn_name ^ "$" ^ uid, and fn_name cannot always be recovered
     unambiguously (it may itself contain "$", e.g. an interface-impl
     mangled name).  Conservatively: static lambdas are disabled outright
     whenever hot-reload is configured at all, rather than risk resolving
     the wrong module. *)
  | Tir.EAlloc (Tir.TCon (tcon_name, _), [fn_ptr_atom])
    when Tir_names.is_clo_struct tcon_name
         && (not ctx.repl)
         && (match ctx.hr_config with None -> true | Some _ -> false)
         && (match fn_ptr_atom with
             | Tir.AVar _ | Tir.ADefRef _ -> true
             | Tir.ALit _ -> false) ->
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
    let alloc_result =
     (match Repr.repr_of_ty ~collision_set:ctx.collision_set ctx.type_defs (Tir.TCon (alloc_type_name, [])) with
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

  (* ── TRMC hole allocation / hole fill ──────────────────────────────── *)
  (* [EAllocHole (ty, filled, hole)] is [EAlloc] with field [hole] left
     UNWRITTEN.  [march_alloc] is a calloc, so the hole reads as 0 until
     [ESetField] fills it, and IS_HEAP_PTR(0) is false — an RC op or deep-drop
     that reaches an unfilled hole is a no-op rather than a wild dereference.
     That is the property the whole TRMC scheme leans on for the window between
     allocation and fill. *)
  | Tir.EAllocHole (tok, Tir.TCon (ctor, _), args, hole) ->
    (* Same repr guard as EStackAlloc: this arm builds a BOXED cell
       unconditionally, so a Newtype-/Niche-repr type would be constructed
       boxed and decoded erased.  TRMC must never select such a type. *)
    let ah_type_name = match String.rindex_opt ctor '.' with
      | Some i -> String.sub ctor 0 i
      | None -> ctor
    in
    (match Repr.repr_of_ty ~collision_set:ctx.collision_set ctx.type_defs (Tir.TCon (ah_type_name, [])) with
     | Repr.Newtype _ | Repr.Niche _ ->
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
              | Some t -> llvm_ty t | None -> "ptr" in
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

  (* TRMC only ever selects a data constructor, so a non-TCon hole allocation
     is a bug in the transformation rather than a shape to support. *)
  | Tir.EAllocHole (_, ty, _, _) ->
    failwith (Printf.sprintf
      "LLVM emit: EAllocHole of non-constructor type %s — TRMC selects data \
       constructors only" (Tir.show_ty ty))

  (* Hole fill.  Ownership MOVES into the object: no incref here, and Perceus
     does not drop the stored value afterwards (see its ESetField case).

     v1 stores through a "ptr" slot.  That is correct because the hole is by
     construction the RECURSIVE field of the constructor being built, which is
     the ADT's own Boxed representation — always pointer-typed.  Phase 3 must
     not select a hole whose field type is an unboxed Int/Float slot without
     revisiting this store. *)
  | Tir.ESetField (obj, i, value) ->
    let (o_ty, o_val) = emit_atom ctx obj in
    let op = coerce ctx o_ty o_val "ptr" in
    let (v_ty, v_val) = emit_atom ctx value in
    let vp = coerce ctx v_ty v_val "ptr" in
    emit_store_field ctx op i "ptr" vp;
    ("ptr", "null")

  (* ── Stack allocation ──────────────────────────────────────────────── *)
  | Tir.EStackAlloc (Tir.TCon (ctor, _), args) ->
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
     | Repr.Newtype _ | Repr.Niche _ ->
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
       && Repr.is_niche_shaped ~collision_set:ctx.collision_set ctx.type_defs reuse_atom_parent_type
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
          | Some t -> llvm_ty t
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
        (match field_ty with
         | Tir.TVar _ when ctx.shape_meta ->
           (* The record's shape is statically known but THIS field's type is
              still an unresolved type variable — monomorphisation did not
              reach it (e.g. a record rebuilt inside a generic `List.map`
              lambda and consumed by a separate function).  A TVar says
              nothing about the field's representation, so a direct typed load
              is unsound: emitting one loads the slot as `ptr` and the ptr->i64
              coercion then untags it, which silently HALVES any odd integer
              (35 read back as 17) while leaving even ones intact.

              Fall back to the by-name shape lookup used for wholly-unknown
              records.  It consults the runtime shape recorded at construction
              and returns ints low-bit tagged, which is exactly the generic
              ADT-slot convention the consuming coercion expects. *)
           let (_, obj_val) = emit_atom ctx obj_atom in
           let ng = intern_string ctx field_name in
           let res = fresh ctx "cr" in
           emit ctx (Printf.sprintf
             "%s = call ptr @march_record_field_dyn(ptr %s, ptr %s, i64 %d)"
             res obj_val ng (String.length field_name));
           ("ptr", res)
         | _ ->
           let (_, obj_val) = emit_atom ctx obj_atom in
           let fv = emit_load_field ctx obj_val idx (llvm_ty field_ty) in
           (llvm_ty field_ty, fv))
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

(* tail_calls_in / has_non_tail_group_call / tarjan_sccs /
   find_mutual_tco_groups / mutual_tco_combined_name / has_self_tail_call —
   and is_trivial_dec_chain_returning / is_trivial_dec_chain themselves —
   moved to [Llvm_tco] (Wave 3 Task 6, chunk 2).  None of these are called
   from this file: [Llvm_toplevel.emit_fn] calls has_self_tail_call (see
   Llvm_tco.has_self_tail_call at its one call site), and
   [Llvm_toplevel.emit_module] (Wave 3 Task 7, chunk 2) calls
   find_mutual_tco_groups / mutual_tco_combined_name / emit_mutual_tco_group
   to decide per-group dispatch — all referenced qualified, no re-export
   needed for these (only is_trivial_dec_chain_returning/is_trivial_dec_chain
   are re-exported bare, above, for emit_expr's own Perceus-wrapped-TCO
   guards). *)

(* ── Function/module emitters, REPL fragment emitters ─────────────────────
   [emit_fn] / [fn_declare_str] / [build_ctor_info] / [emit_module] moved to
   [Llvm_toplevel] (Wave 3 Task 7, chunk 2); the five REPL/fragment emitters
   ([emit_repl_expr] / [emit_repl_decl] / [emit_repl_fn] /
   [emit_repl_fn_with_closure_slot] / [emit_fns_fragment]) plus
   [repl_slot_info] moved to [Llvm_repl].  Both new modules need
   [emit_expr] (this file's core, immediately above) to descend into
   function/fragment bodies; since this file in turn calls
   [Llvm_toplevel.emit_module] / [Llvm_repl.emit_repl_*] below (the
   orchestrator's public API), a direct reference the other way would
   cycle — both modules take [~emit_expr] as a labeled callback parameter
   instead (the same de-cycling pattern [Llvm_case]/[Llvm_tco] already
   established in Tasks 5/6). All public names are re-exported bare below,
   pre-applying the [~emit_expr] callback, so existing external call sites
   (bin/main.ml, lib/jit/repl_jit.ml, test/) see the exact same signatures
   as before this split. *)

let emit_fn ctx fn = Llvm_toplevel.emit_fn ~emit_expr ctx fn
let fn_declare_str = Llvm_toplevel.fn_declare_str
let build_ctor_info = Llvm_toplevel.build_ctor_info
let emit_main_wrapper = Llvm_toplevel.emit_main_wrapper
let emit_preamble = Llvm_toplevel.emit_preamble

let emit_module ?fast_math ?pmap_threshold ?target ?hot_reload ?impl_hashes
    ?remote_impl_hashes ?remote_sig_hashes ?emit_main ?cap_attrib ?cap_decls
    (m : Tir.tir_module) : string =
  Llvm_toplevel.emit_module ~emit_expr
    ?fast_math ?pmap_threshold ?target ?hot_reload ?impl_hashes
    ?remote_impl_hashes ?remote_sig_hashes ?emit_main ?cap_attrib ?cap_decls m

type repl_globals = Llvm_repl.repl_globals
let emit_repl_globals_decl = Llvm_repl.emit_repl_globals_decl

type repl_slot_info = Llvm_repl.repl_slot_info = {
  rs_bare : string;
  rs_slot : int;
  rs_ty : Tir.ty;
}

let emit_prev_slot_bridges = Llvm_repl.emit_prev_slot_bridges
let emit_store_to_slot = Llvm_repl.emit_store_to_slot
let emit_slot_loader_fns = Llvm_repl.emit_slot_loader_fns
let emit_prev_global_bridges = Llvm_repl.emit_prev_global_bridges

let emit_repl_expr ?fast_math ~n ~ret_ty ~prev_slots ~fns ?extern_fns
    ?store_as_slot ~types (body : Tir.expr) : string =
  Llvm_repl.emit_repl_expr ~emit_expr
    ?fast_math ~n ~ret_ty ~prev_slots ~fns ?extern_fns ?store_as_slot ~types body

let emit_repl_decl ?fast_math ~n ~name ~val_ty ~dest_slot ~prev_slots ~fns
    ?extern_fns ~types (body : Tir.expr) : string =
  Llvm_repl.emit_repl_decl ~emit_expr
    ?fast_math ~n ~name ~val_ty ~dest_slot ~prev_slots ~fns ?extern_fns ~types body

let emit_repl_fn ?fast_math ~n ~prev_slots ?extern_fns ~types (fn : Tir.fn_def) : string =
  Llvm_repl.emit_repl_fn ~emit_expr ?fast_math ~n ~prev_slots ?extern_fns ~types fn

let emit_repl_fn_with_closure_slot ?fast_math ~n ~bind_name ~dest_slot
    ~prev_slots ?helper_fns ?extern_fns ~types (fn : Tir.fn_def) : string =
  Llvm_repl.emit_repl_fn_with_closure_slot ~emit_expr
    ?fast_math ~n ~bind_name ~dest_slot ~prev_slots ?helper_fns ?extern_fns ~types fn

let emit_fns_fragment ~types ~fns ?extern_fns ~repl () : string =
  Llvm_repl.emit_fns_fragment ~emit_expr ~types ~fns ?extern_fns ~repl ()

let llvm_ty_of_tir = Llvm_repl.llvm_ty_of_tir
