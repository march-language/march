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
      let _ = nparams in
      (* clo_wrap_define builds the wrapper's uniform-ptr ABI signature and the
         concrete forwarding call (boxing/unboxing Float params + return). *)
      let param_tys = List.map llvm_ty ps_tirs in
      Buffer.add_string ctx.extra_fns
        (clo_wrap_define wrap_name param_tys target_ret fn_name)
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
         let ret_tir     = fn_ret_tir v.Tir.v_ty in
         let target_ret  = llvm_ret_ty ret_tir in
         let param_tys   = List.map llvm_ty ps in
         Buffer.add_string ctx.extra_fns
           (clo_wrap_define wrap_name param_tys target_ret fn_name)
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
     In BOTH cases the correct field value is apply_ret == task[3] >> 1, and
     task[3] is always odd (trampoline sets the low bit), so a single
     unconditional ashr-1 of the freshly-allocated Ok payload (field 0, offset
     16) is the exact inverse.  Keyed on the statically-known Task inner type:
     "double" (Float — ABI-broken through the void*-returning trampoline,
     separate follow-up) and any other repr are left byte-identical.  The i64
     half mirrors task_await_unwrap (291f6b5f) and the await i64 fix
     (f89b8711); the ptr half fixes the heap-payload crash f89b8711's comment
     wrongly assumed was already correct. *)
  | Tir.EApp (f, [a]) when f.Tir.v_name = "task_await" ->
    let (_, tp) = emit_atom ctx a in
    let r = fresh ctx "tawait" in
    emit ctx (Printf.sprintf "%s = call ptr @march_task_await(ptr %s)" r tp);
    let inner_ty = match a with
      | Tir.AVar v ->
        (match v.Tir.v_ty with
         | Tir.TCon ("Task", [inner]) -> llvm_ty inner
         | _ -> "ptr")
      | _ -> "ptr"
    in
    if inner_ty = "i64" || inner_ty = "ptr" then begin
      let fp = fresh ctx "tawf" in
      emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" fp r);
      let v  = fresh ctx "tawv" in
      emit ctx (Printf.sprintf "%s = load i64, ptr %s, align 8" v fp);
      let v2 = fresh ctx "tawv" in
      emit ctx (Printf.sprintf "%s = ashr i64 %s, 1" v2 v);
      emit ctx (Printf.sprintf "store i64 %s, ptr %s, align 8" v2 fp)
    end;
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
      | "int_mod_euclid" -> "march_checked_umod"
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
    (* Boundary B: a direct call to an apply fn (known_call rewrote a
       non-escaping ECallPtr into EApp(apply_fn, ...)) must pass every scalar
       arg through the uniform ptr closure ABI — tag Int/Bool via (n<<1)|1,
       box Float via march_alloc_float — because the apply fn's params are now
       `ptr` (Task 4).  Ordinary top-level direct calls keep their concrete
       ABI, so guard the remap on is_apply_fn. *)
    let arg_strs =
      if is_apply_fn resolved_name then
        List.map (fun (ty, v) ->
          if ty = "i64" || ty = "double" then
            let v' = coerce ctx ty v "ptr" in "ptr " ^ v'
          else ty ^ " " ^ v) arg_pairs
      else arg_strs in
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
      | "int_mod_euclid" -> "march_checked_umod"
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
    let orig_param_llvm_tys =
      List.map (fun t -> if t = "double" || t = "i64" then "ptr" else t) orig_param_llvm_tys in
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
            | _ ->
              (* Non-generic type (no params on the ctor key): the variant DEF
                 carries the concrete payload type — key the encode on the same
                 classification the decode (emit_case) uses, so None and Some
                 stay consistently encoded (both niche, or both boxed). *)
              (match Repr.niche_repr_of_concrete ctx.type_defs alloc_type_name with
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
    (match Repr.repr_of_ty ctx.type_defs (Tir.TCon (sa_type_name, [])) with
     | Repr.Newtype _ | Repr.Niche _ ->
       failwith (Printf.sprintf
         "LLVM emit: EStackAlloc of erased-repr type %s (ctor %s) — \
          construction would be boxed but consumers decode erased; \
          escape analysis must not promote this alloc (finding L7)"
         sa_type_name ctor)
     | Repr.Boxed ->
       if Repr.is_niche_shaped ctx.type_defs sa_type_name then
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
        | [] when (match Repr.niche_repr_of_concrete ctx.type_defs reuse_type_name with
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
    ?remote_impl_hashes ?remote_sig_hashes ?emit_main (m : Tir.tir_module) : string =
  Llvm_toplevel.emit_module ~emit_expr
    ?fast_math ?pmap_threshold ?target ?hot_reload ?impl_hashes
    ?remote_impl_hashes ?remote_sig_hashes ?emit_main m

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
    ~prev_slots ?extern_fns ~types (fn : Tir.fn_def) : string =
  Llvm_repl.emit_repl_fn_with_closure_slot ~emit_expr
    ?fast_math ~n ~bind_name ~dest_slot ~prev_slots ?extern_fns ~types fn

let emit_fns_fragment ~types ~fns ?extern_fns ?repl () : string =
  Llvm_repl.emit_fns_fragment ~emit_expr ~types ~fns ?extern_fns ?repl ()

let llvm_ty_of_tir = Llvm_repl.llvm_ty_of_tir
