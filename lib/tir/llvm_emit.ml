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
let target_triple = Llvm_toplevel.target_triple
let target_is_linux = Llvm_toplevel.target_is_linux
let zig_target = Llvm_toplevel.zig_target

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
type session_wraps = Llvm_ctx.session_wraps = {
  sw_defined : (string, unit) Hashtbl.t;
  sw_pending : (string, unit) Hashtbl.t;
}
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
  mutable session_wraps : Llvm_ctx.session_wraps option;
  static_clos : (string, string) Hashtbl.t;
  extra_fns : Buffer.t;
  emitted_eq_fns : (string, unit) Hashtbl.t;
  emitted_dispatch_fns : (string, unit) Hashtbl.t;
  extern_map : (string, string) Hashtbl.t;
  blocking_externs : (string, unit) Hashtbl.t;
  raises_externs : (string, unit) Hashtbl.t;
  unknown_decls : (string, unit) Hashtbl.t;
  repl_slot_fns : (string, unit) Hashtbl.t;
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

let fresh = Llvm_ctx.fresh
let fresh_block = Llvm_ctx.fresh_block
let emit = Llvm_ctx.emit
let emit_label = Llvm_ctx.emit_label
let emit_term = Llvm_ctx.emit_term
let llvm_name = Llvm_ctx.llvm_name
let atom_hash = Llvm_ctx.atom_hash
let llvm_ty = Llvm_ctx.llvm_ty
let coerce = Llvm_ctx.coerce
let is_vec_ty = Llvm_ctx.is_vec_ty

(* [release_temp_boxes] (the call-scoped SIMD vector temp-box release) moved to
   [Llvm_emit_call] with the general EApp arm body, its only caller. *)


(* llvm_ret_ty moved to [Llvm_ctx] (Wave 3 Task 6, chunk 2): [Llvm_calls] and
   [Llvm_tco] both need it too; re-exported bare since ~20 call sites in this
   file still use it unqualified. *)
let llvm_ret_ty = Llvm_ctx.llvm_ret_ty

(* ok_payload_ty moved to [Llvm_calls] (Wave 3 Task 6, chunk 2): its only
   caller besides emit_module's one use below is [emit_raises_wrapper].
   Re-exported bare for that one remaining call site (in emit_module,
   Task 7's territory). *)

(* [fn_ret_tir] moved to [Llvm_emit_call] with the call-arm bodies that were
   most of its callers; [emit_atom] below still uses it, re-exported bare. *)
let fn_ret_tir = Llvm_emit_call.fn_ret_tir

(* [is_apply_fn] ([Tir_names]) is no longer named in this file: its call sites
   were the call-arm bodies, now in [Llvm_emit_call].  The convention it
   encodes is still what those bodies depend on, so the note stays here.

   True for defunctionalized closure apply wrappers ("<fn>$apply$<uid>").

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

(* The three operator-string tables these guards feed ([int_arith_op],
   [int_cmp_pred], [float_arith_op]) moved to [Llvm_emit_arith] with the arm
   bodies that were their only callers.  The guards stay here: they are
   evaluated in [emit_expr]'s `when` clauses, whose order is load-bearing. *)

let is_int_bitwise name = List.mem name ["int_and"; "int_or"; "int_xor"; "int_shl"; "int_shr"]

(* True when [name] is a user-defined top-level function whose bare name also
   names one of [emit_expr]'s codegen-dispatched builtins.  See the
   "User top-level fn shadowing a codegen-dispatched builtin name" arm. *)
let shadows_dispatched_builtin (ctx : ctx) (name : string) : bool =
  Hashtbl.mem ctx.top_fns name
  && (Builtin_name.of_string name <> None || is_int_bitwise name)

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
    (match Llvm_ctx.wrap_emit_kind ctx wrap_name with
     | `Skip -> ()
     | (`Define | `Declare) as wrap_kind ->
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
        (match wrap_kind with
         | `Declare -> Llvm_calls.clo_wrap_declare wrap_name param_tys
         | `Define  ->
           clo_wrap_define ~drop_clo:ctx.repl wrap_name param_tys target_ret fn_name));
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
  | Tir.AVar v when Hashtbl.mem ctx.repl_slot_fns v.Tir.v_name
                 && not (Hashtbl.mem ctx.top_fns v.Tir.v_name)
                 && not (Hashtbl.mem ctx.var_slot (llvm_name v.Tir.v_name)) ->
    (* Prior REPL binding exposed to this fn fragment through a prev-slot
       loader (see Llvm_repl.emit_slot_loader_fns).  Call the loader to
       materialise the slot's CURRENT value — for fn/lambda bindings that is
       the closure ptr, ready for ECallPtr dispatch.  Without this arm, a
       TFn-typed reference falls into the first-class-function paths below,
       which wrap the loader symbol itself in a $clo_wrap trampoline as if it
       were the real n-ary function.  Placed above the runtime-prefix/builtin
       arms so a REPL binding shadows a same-named builtin, exactly as the
       var_slot bridge does in expression fragments. *)
    let ret_tir = match Hashtbl.find_opt ctx.top_fn_ret_ty v.Tir.v_name with
      | Some t -> t
      | None   -> v.Tir.v_ty
    in
    let ret_ty = llvm_ret_ty ret_tir in
    let r = fresh ctx "slotld" in
    emit ctx (Printf.sprintf "%s = call %s @%s()" r ret_ty (llvm_name v.Tir.v_name));
    (ret_ty, r)
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
    (match Llvm_ctx.wrap_emit_kind ctx wrap_name with
     | `Skip -> ()
     | (`Define | `Declare) as wrap_kind ->
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
        (match wrap_kind with
         | `Declare -> Llvm_calls.clo_wrap_declare wrap_name param_ltys
         | `Define  ->
           clo_wrap_define ~drop_clo:ctx.repl wrap_name param_ltys target_ret fn_name));
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
       (match Llvm_ctx.wrap_emit_kind ctx wrap_name with
        | `Skip -> ()
        | (`Define | `Declare) as wrap_kind ->
          let ret_tir     = fn_ret_tir v.Tir.v_ty in
          let target_ret  = llvm_ret_ty ret_tir in
          let param_tys   = List.map llvm_ty ps in
          Buffer.add_string ctx.extra_fns
            (match wrap_kind with
             | `Declare -> Llvm_calls.clo_wrap_declare wrap_name param_tys
             | `Define  ->
               clo_wrap_define ~drop_clo:ctx.repl wrap_name param_tys target_ret fn_name));
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
   remaining arms (and emit_case, now in [Llvm_case]) call them unqualified —
   same re-export pattern as [Llvm_ctx]'s Wave 3 Task 3 split.  The
   EAlloc/EStackAlloc/EReuse bodies now live in [Llvm_emit_alloc] and the
   ETuple/ERecord/EField/EUpdate bodies in [Llvm_emit_data]; both reach for
   [Llvm_data] directly, which is why only five re-exports are left. *)
let emit_store_field = Llvm_data.emit_store_field
let emit_heap_alloc = Llvm_data.emit_heap_alloc
let ctor_entry = Llvm_data.ctor_entry
let atom_tir_ty = Llvm_data.atom_tir_ty

(* ── ADT structural equality generation ───────────────────────────────
   Moved to [Llvm_eq] (Wave 3 Task 5, chunk 2): apply_ty_subst,
   mangle_ty_for_eq, field_load_llty, ensure_adt_eq_fn.  Re-exported bare
   here for the same reason as above.  Nothing in this file names them any
   more: [ensure_adt_eq_fn]'s caller was the `==`/`!=` arm body, now in
   [Llvm_emit_arith], and [mangle_ty_for_eq]'s were the [EAlloc]/[EReuse] arm
   bodies, now in [Llvm_emit_alloc].  Both modules reach for [Llvm_eq]
   directly. *)

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

(* ── SIMD vector types: see [Llvm_emit_simd] ─────────────────────────
   The decoder, the per-type shape table, the lane widen/narrow helpers and
   the intercept arm's body moved verbatim to llvm_emit_simd.ml.  The one
   re-export below is what the REST of this file still needs: the decoder,
   for the intercept arm's guard and the general EApp arm's unresolved-builtin
   check.  The shape record's field names went with the vector-equality
   lowering into [Llvm_emit_arith]. *)
let decode_simd_call = Llvm_emit_simd.decode_simd_call

(* ── NativeArray map inline loops: see [Llvm_emit_nmap] ──────────────
   The per-width descriptor, the synthetic-name decoder and the two loop
   emitters moved verbatim to llvm_emit_nmap.ml.  The re-exports below are
   what the four driving arms in [emit_expr] still name directly.  The
   [nmap_width] record itself stays private to [Llvm_emit_nmap]: the arms
   only pass it through, never read a field. *)
let decode_nmap_inline_call = Llvm_emit_nmap.decode_nmap_inline_call

let emit_native_map_inline_loop ctx ~width ~unboxed ~arr_atom ~apply_name ~clo_reg =
  Llvm_emit_nmap.emit_native_map_inline_loop ~emit_atom ctx ~width ~unboxed
    ~arr_atom ~apply_name ~clo_reg

let emit_native_map2_inline_loop ctx ~width ~unboxed ~arr1_atom ~arr2_atom ~apply_name ~clo_reg =
  Llvm_emit_nmap.emit_native_map2_inline_loop ~emit_atom ctx ~width ~unboxed
    ~arr1_atom ~arr2_atom ~apply_name ~clo_reg

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
(* ── Builtin dispatch: exhaustiveness surface ──────────────────────────────
   [emit_expr] selects a builtin's emit arm with a per-arm
   [when Builtin_name.is Builtin_name.Task_await f.Tir.v_name] guard.  Guards
   are opaque to the compiler: nothing checks that every constructor of
   [Builtin_name.t] actually HAS an arm, which is the failure mode the variant
   exists to catch.

   This match closes that gap.  It has no wildcard, so adding a constructor to
   [Builtin_name.t] without classifying it here is a non-exhaustive-match
   error (warning 8 is an error under the dev profile).  The classification is
   the topic grouping the arms are organised by, so it also documents where in
   this file a given builtin is emitted. *)
type builtin_group =
  | Bg_arith   (* integer/float/bool scalar ops and the to_string family *)
  | Bg_task    (* tasks, actors, signals, channels, MPST, work pools *)
  | Bg_record  (* records, vaults, HTML escaping *)

let builtin_group : Builtin_name.t -> builtin_group = function
  | Builtin_name.Bool_to_string | Builtin_name.Float_to_string
  | Builtin_name.Int_abs | Builtin_name.Int_div
  | Builtin_name.Int_div_euclid | Builtin_name.Int_max_value
  | Builtin_name.Int_min_value | Builtin_name.Int_mod
  | Builtin_name.Int_mod_euclid | Builtin_name.Int_not
  | Builtin_name.Int_popcount | Builtin_name.Int_pow
  | Builtin_name.Int_to_string | Builtin_name.Negate | Builtin_name.Not
  | Builtin_name.To_string ->
    Bg_arith
  | Builtin_name.Actor_register | Builtin_name.Actor_reply
  | Builtin_name.Chan_choose | Builtin_name.Chan_send
  | Builtin_name.Get_work_pool | Builtin_name.Mpst_send
  | Builtin_name.Pmap_threshold | Builtin_name.Receive
  | Builtin_name.Remote_ref_hashes | Builtin_name.Send
  | Builtin_name.Signal_raise_self | Builtin_name.Signal_unwatch
  | Builtin_name.Signal_watch | Builtin_name.Task_await
  | Builtin_name.Task_await_unwrap | Builtin_name.Task_cancel
  | Builtin_name.Task_cancel_by_id | Builtin_name.Task_cancel_token_new
  | Builtin_name.Task_is_cancelled | Builtin_name.Task_reductions
  | Builtin_name.Task_spawn | Builtin_name.Task_spawn_steal
  | Builtin_name.Task_spawn_with_cancel | Builtin_name.Task_yield ->
    Bg_task
  | Builtin_name.Html_auto_escape | Builtin_name.Html_escape_ctx
  | Builtin_name.Record_from_list | Builtin_name.Record_get
  | Builtin_name.Record_has_key | Builtin_name.Record_put
  | Builtin_name.Vault_drop | Builtin_name.Vault_get
  | Builtin_name.Vault_incr | Builtin_name.Vault_ns_drop
  | Builtin_name.Vault_ns_get | Builtin_name.Vault_ns_set
  | Builtin_name.Vault_push_capped | Builtin_name.Vault_put_new
  | Builtin_name.Vault_set | Builtin_name.Vault_set_ttl
  | Builtin_name.Vault_update ->
    Bg_record

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
    Llvm_emit_tcoarm.emit_fv_load ~emit_atom ~emit_expr ctx v rhs body

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
    Llvm_emit_tcoarm.emit_self_tco_let ~emit_atom ~emit_expr ctx args body

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
    Llvm_emit_tcoarm.emit_self_tco_seq ~emit_atom ~emit_expr ctx args dec_chain

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
    Llvm_emit_tcoarm.emit_mutual_tco_let ~emit_atom ~emit_expr ctx f args body

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
    Llvm_emit_tcoarm.emit_mutual_tco_seq ~emit_atom ~emit_expr ctx f args dec_chain

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

  (* ── User top-level fn shadowing a codegen-dispatched builtin name ──── *)
  (* Every arm below dispatches on the callee's BARE name.  Shadowing a
     builtin name with an entry-module top-level `fn` is a supported,
     regression-tested feature (see [March_modules.Prelude_collision]'s
     header: only the names Prelude's own bodies call unqualified are
     rejected, everything else must resolve to the user's definition) — so
     without this arm a program defining e.g. `fn int_mod(a, b)` compiles
     its CALL SITES into @march_checked_imod and never reaches the emitted
     @int_mod at all, while the interpreter runs the user's function.  That
     was a real, silent wrong-answer miscompile (test/native/
     shadowed_builtin_name.march is the witness).

     Builtins are never registered in [top_fns] (they have no March
     definition — see the ECallPtr arm's "Builtins (e.g. vault_update) are
     not in top_fns" note), so membership there is a sound discriminator:
     true means a user function of that name exists and owns the name.

     PRECEDENCE, chosen deliberately (specs/progress/2026-08-26-builtin-arm-
     order-vs-tco-arms-is-accidental.md) — do not reorder these three tiers:
       1. the TCO arms above (they only ever fire for the user function
          currently being emitted, so they are always about a user fn);
       2. this arm — a user top-level fn owns its name;
       3. the builtin name arms below.
     The two bare-EApp TCO arms were moved above the builtin arms for
     exactly this reason; previously roughly half the builtin arms sat
     above them and half below, so which one won was append order. *)
  | Tir.EApp (f, args) when shadows_dispatched_builtin ctx f.Tir.v_name ->
    Llvm_emit_call.emit_generic_app ~emit_atom ctx f args

  (* ── Arithmetic builtins ───────────────────────────────────────────── *)
  | Tir.EApp (f, [a; b]) when is_int_arith f.Tir.v_name ->
    Llvm_emit_arith.emit_int_arith ~emit_atom ctx f a b

  | Tir.EApp (f, [a; b]) when is_int_cmp f.Tir.v_name ->
    Llvm_emit_arith.emit_int_cmp ~emit_atom ctx f a b

  | Tir.EApp (f, [a; b]) when is_float_arith f.Tir.v_name ->
    Llvm_emit_arith.emit_float_arith ~emit_atom ctx f a b

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

  | Tir.EApp (f, [a]) when Builtin_name.is Builtin_name.Not f.Tir.v_name ->
    let va = emit_atom_as ctx "i64" a in
    let r  = fresh ctx "ar" in
    emit ctx (Printf.sprintf "%s = xor i64 %s, 1" r va);
    ("i64", r)

  | Tir.EApp (f, [a]) when Builtin_name.is Builtin_name.Negate f.Tir.v_name ->
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
  | Tir.EApp (f, [a]) when Builtin_name.is Builtin_name.Html_auto_escape f.Tir.v_name
                            && (match atom_tir_ty a with
                                | Tir.TCon ("Safe", _) ->
                                  not (Collision_set.is_colliding ctx.collision_set "Safe")
                                | _ -> false) ->
    Llvm_emit_html.emit_html_auto_escape_safe ~emit_atom ctx a

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
  | Tir.EApp (f, [a]) when Builtin_name.is Builtin_name.Html_auto_escape f.Tir.v_name ->
    Llvm_emit_html.emit_html_auto_escape ~emit_atom ctx a

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
    when Builtin_name.is Builtin_name.Html_escape_ctx f.Tir.v_name ->
    Llvm_emit_html.emit_html_escape_ctx_static ~emit_atom ctx id a

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
  | Tir.EApp (f, [idx; a]) when Builtin_name.is Builtin_name.Html_escape_ctx f.Tir.v_name ->
    Llvm_emit_html.emit_html_escape_ctx_dynamic ~emit_atom ctx idx a

  (* ── Bitwise integer builtins ─────────────────────────────────────── *)
  | Tir.EApp (f, [a; b]) when is_int_bitwise f.Tir.v_name ->
    let va = emit_atom_as ctx "i64" a in
    let vb = emit_atom_as ctx "i64" b in
    let r  = fresh ctx "bw" in
    emit ctx (Printf.sprintf "%s = %s i64 %s, %s" r (int_bitwise_op f.Tir.v_name) va vb);
    ("i64", r)

  | Tir.EApp (f, [a]) when Builtin_name.is Builtin_name.Int_not f.Tir.v_name ->
    let va = emit_atom_as ctx "i64" a in
    let r  = fresh ctx "bw" in
    emit ctx (Printf.sprintf "%s = xor i64 %s, -1" r va);
    ("i64", r)

  | Tir.EApp (f, [a]) when Builtin_name.is Builtin_name.Int_popcount f.Tir.v_name ->
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
  | Tir.EApp (f, [a]) when Builtin_name.is Builtin_name.Int_to_string f.Tir.v_name ->
    let va = emit_atom_as ctx "i64" a in
    let r  = fresh ctx "its" in
    emit ctx (Printf.sprintf "%s = call ptr @march_int_to_string(i64 %s)" r va);
    ("ptr", r)

  | Tir.EApp (f, [a]) when Builtin_name.is Builtin_name.Bool_to_string f.Tir.v_name ->
    let va = emit_atom_as ctx "i64" a in
    let r  = fresh ctx "bts" in
    emit ctx (Printf.sprintf "%s = call ptr @march_bool_to_string(i64 %s)" r va);
    ("ptr", r)

  | Tir.EApp (f, [a]) when Builtin_name.is Builtin_name.Float_to_string f.Tir.v_name ->
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
  | Tir.EApp (f, [clo_atom]) when Builtin_name.is Builtin_name.Task_spawn f.Tir.v_name ->
    let (_, clo_ptr) = emit_atom ctx clo_atom in
    let result = fresh ctx "tsres" in
    emit ctx (Printf.sprintf "%s = call ptr @march_task_spawn_thunk(ptr %s)"
                result clo_ptr);
    ("ptr", result)

  (* Signal.watch (stdlib/signal.march): register/remove a deferred OS-signal
     watcher, or raise a signal to self.  The `code` is an Int (untag to raw
     i64); the watcher closure is passed OWNED (borrow.ml marks the arg
     consuming) so the runtime keeps its reference across drains. *)
  | Tir.EApp (f, [code_atom; clo_atom]) when Builtin_name.is Builtin_name.Signal_watch f.Tir.v_name ->
    let (code_ty, code_v) = emit_atom ctx code_atom in
    let code_i64 = coerce ctx code_ty code_v "i64" in
    let (clo_ty, clo_v) = emit_atom ctx clo_atom in
    let clo_ptr = coerce ctx clo_ty clo_v "ptr" in
    emit ctx (Printf.sprintf "call void @march_signal_watch(i64 %s, ptr %s)"
                code_i64 clo_ptr);
    ("ptr", "null")
  | Tir.EApp (f, [code_atom]) when Builtin_name.is Builtin_name.Signal_unwatch f.Tir.v_name ->
    let (code_ty, code_v) = emit_atom ctx code_atom in
    let code_i64 = coerce ctx code_ty code_v "i64" in
    emit ctx (Printf.sprintf "call void @march_signal_unwatch(i64 %s)" code_i64);
    ("ptr", "null")
  | Tir.EApp (f, [code_atom]) when Builtin_name.is Builtin_name.Signal_raise_self f.Tir.v_name ->
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
  | Tir.EApp (f, [a]) when Builtin_name.is Builtin_name.Task_await_unwrap f.Tir.v_name ->
    Llvm_emit_task.emit_task_await_unwrap ~emit_atom ctx a
  | Tir.EApp (f, [a]) when Builtin_name.is Builtin_name.Task_await f.Tir.v_name ->
    Llvm_emit_task.emit_task_await ~emit_atom ctx a

  (* task_yield() → cooperative yield via march_sched_yield *)
  | Tir.EApp (f, []) when Builtin_name.is Builtin_name.Task_yield f.Tir.v_name ->
    emit ctx "call void @march_sched_yield()";
    ("i64", "0")

  (* receive() → cooperative blocking mailbox pop via march_sched_recv *)
  | Tir.EApp (f, []) when Builtin_name.is Builtin_name.Receive f.Tir.v_name ->
    let r = fresh ctx "recv_msg" in
    emit ctx (Printf.sprintf "%s = call ptr @march_sched_recv()" r);
    ("ptr", r)

  (* task_spawn_steal(pool, thunk_closure) → spawn as async green thread *)
  | Tir.EApp (f, [_pool; clo_atom]) when Builtin_name.is Builtin_name.Task_spawn_steal f.Tir.v_name ->
    let (_, clo_ptr) = emit_atom ctx clo_atom in
    let result = fresh ctx "tsres" in
    emit ctx (Printf.sprintf "%s = call ptr @march_task_spawn_thunk(ptr %s)"
                result clo_ptr);
    ("ptr", result)

  (* pmap_threshold() → compile-time constant i64 from --pmap-threshold *)
  | Tir.EApp (f, []) when Builtin_name.is Builtin_name.Pmap_threshold f.Tir.v_name ->
    ("i64", string_of_int ctx.pmap_threshold)

  (* remote_ref_hashes(module, fn) → constant-fold to (sig_hash, impl_hash) pair.
     Looks up the CAS-derived hashes baked into the binary at compile time.
     Returns a heap-allocated (String, String) tuple; both strings are empty
     when the function name was not found in the hash maps (non-CAS builds).
     Key lookup strategy: top-level user module functions are stored without
     the module prefix (fn_name = "fib"), while stdlib/nested module functions
     are stored with it (fn_name = "String.from_int").  Try both forms. *)
  | Tir.EApp (f, [mod_atom; fn_atom]) when Builtin_name.is Builtin_name.Remote_ref_hashes f.Tir.v_name ->
    Llvm_emit_task.emit_remote_ref_hashes ctx mod_atom fn_atom

  (* task_reductions() → read TLS reduction counter (no-op 0 in REPL mode) *)
  | Tir.EApp (f, []) when Builtin_name.is Builtin_name.Task_reductions f.Tir.v_name ->
    if ctx.repl then ("i64", "0")
    else begin
      let r = fresh ctx "reds" in
      emit ctx (Printf.sprintf "%s = load i64, ptr @march_tls_reductions" r);
      ("i64", r)
    end

  (* task_cancel_token_new() → allocate a new cancel token *)
  | Tir.EApp (f, []) when Builtin_name.is Builtin_name.Task_cancel_token_new f.Tir.v_name ->
    let r = fresh ctx "ctok" in
    emit ctx (Printf.sprintf "%s = call ptr @march_cancel_token_new()" r);
    ("ptr", r)

  (* task_cancel(tok) → cancel the token *)
  | Tir.EApp (f, [tok]) when Builtin_name.is Builtin_name.Task_cancel f.Tir.v_name ->
    let (_, tp) = emit_atom ctx tok in
    emit ctx (Printf.sprintf "call void @march_cancel_token_cancel(ptr %s)" tp);
    ("i64", "0")

  (* task_is_cancelled(tok) → check if token is cancelled *)
  | Tir.EApp (f, [tok]) when Builtin_name.is Builtin_name.Task_is_cancelled f.Tir.v_name ->
    let (_, tp) = emit_atom ctx tok in
    let r = fresh ctx "isc" in
    emit ctx (Printf.sprintf "%s = call i64 @march_cancel_token_is_cancelled(ptr %s)" r tp);
    ("i64", r)

  (* task_spawn_with_cancel(clo, tok) → spawn with cancel token *)
  | Tir.EApp (f, [clo; tok]) when Builtin_name.is Builtin_name.Task_spawn_with_cancel f.Tir.v_name ->
    let (_, cp) = emit_atom ctx clo in
    let (_, tp) = emit_atom ctx tok in
    let r = fresh ctx "tswc" in
    emit ctx (Printf.sprintf "%s = call ptr @march_task_spawn_with_cancel_thunk(ptr %s, ptr %s)" r cp tp);
    ("ptr", r)

  (* task_cancel_by_id(task) → mark task's proc as DEAD *)
  | Tir.EApp (f, [t]) when Builtin_name.is Builtin_name.Task_cancel_by_id f.Tir.v_name ->
    let (_, tp) = emit_atom ctx t in
    emit ctx (Printf.sprintf "call void @march_task_cancel_by_id(ptr %s)" tp);
    ("i64", "0")

  (* get_work_pool() → null sentinel in Phase 1 *)
  | Tir.EApp (f, []) when Builtin_name.is Builtin_name.Get_work_pool f.Tir.v_name ->
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
    Llvm_emit_data.emit_record_walk ~emit_atom ctx f r

  | Tir.EApp (f, [r; k]) when Builtin_name.is Builtin_name.Record_get f.Tir.v_name ->
    Llvm_emit_data.emit_record_get ~emit_atom ctx f r k

  | Tir.EApp (f, [r; k]) when Builtin_name.is Builtin_name.Record_has_key f.Tir.v_name ->
    Llvm_emit_data.emit_record_has_key ~emit_atom ctx r k

  | Tir.EApp (f, [r; k; v]) when Builtin_name.is Builtin_name.Record_put f.Tir.v_name ->
    Llvm_emit_data.emit_record_put ~emit_atom ctx r k v

  | Tir.EApp (f, [l]) when Builtin_name.is Builtin_name.Record_from_list f.Tir.v_name ->
    Llvm_emit_data.emit_record_from_list ~emit_atom ctx l

  (* ── to_string: dispatch on argument TIR type ──────────────────────── *)
  | Tir.EApp (f, [a]) when Builtin_name.is Builtin_name.To_string f.Tir.v_name ->
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

  (* ── Send with linear message: emit march_send_linear (zero-copy move) ─ *)
  (* When the message argument is a linear value (v_lin = Lin), the compiler
     can guarantee that no other reference to the message exists after the
     send.  We emit march_send_linear (which will call march_msg_move) rather
     than the default march_send (which copies for non-linear messages).
     This is the Phase 5 linear-type optimization: zero-copy inter-process
     message passing for linearly-typed messages. *)
  | Tir.EApp (f, [actor_atom; msg_atom])
    when Builtin_name.is Builtin_name.Send f.Tir.v_name
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
    when Builtin_name.(is Int_mod f.Tir.v_name || is Int_div f.Tir.v_name
                       || is Int_mod_euclid f.Tir.v_name
                       || is Int_div_euclid f.Tir.v_name) ->
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
    when Builtin_name.is Builtin_name.Int_pow f.Tir.v_name ->
    let va = emit_atom_as ctx "i64" a in
    let vb = emit_atom_as ctx "i64" b in
    let r  = fresh ctx "ar" in
    emit ctx (Printf.sprintf "%s = call i64 @march_int_pow(i64 %s, i64 %s)" r va vb);
    ("i64", r)

  | Tir.EApp (f, [a])
    when Builtin_name.is Builtin_name.Int_abs f.Tir.v_name ->
    let va = emit_atom_as ctx "i64" a in
    let r  = fresh ctx "ar" in
    emit ctx (Printf.sprintf "%s = call i64 @llvm.abs.i64(i64 %s, i1 false)" r va);
    ("i64", r)

  | Tir.EApp (f, _)
    when Builtin_name.is Builtin_name.Int_max_value f.Tir.v_name ->
    ("i64", "9223372036854775807")

  | Tir.EApp (f, _)
    when Builtin_name.is Builtin_name.Int_min_value f.Tir.v_name ->
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
    when Builtin_name.is Builtin_name.Vault_set f.Tir.v_name ->
    let vt = emit_atom_as ctx "ptr" tbl in
    let vk = emit_atom_as ctx "ptr" key in
    let vv = emit_atom_as ctx "ptr" value in
    emit ctx (Printf.sprintf
      "call ptr @march_vault_set(ptr %s, ptr %s, ptr %s)" vt vk vv);
    ("i64", "0")

  | Tir.EApp (f, [tbl; key; value; ttl])
    when Builtin_name.is Builtin_name.Vault_set_ttl f.Tir.v_name ->
    let vt = emit_atom_as ctx "ptr" tbl in
    let vk = emit_atom_as ctx "ptr" key in
    let vv = emit_atom_as ctx "ptr" value in
    let vttl = emit_atom_as ctx "i64" ttl in
    emit ctx (Printf.sprintf
      "call ptr @march_vault_set_ttl(ptr %s, ptr %s, ptr %s, i64 %s)" vt vk vv vttl);
    ("i64", "0")

  | Tir.EApp (f, [tbl; key; value; ttl])
    when Builtin_name.is Builtin_name.Vault_put_new f.Tir.v_name ->
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
    when Builtin_name.is Builtin_name.Actor_register f.Tir.v_name ->
    let vp = emit_atom_as ctx "ptr" pid in
    let vn = emit_atom_as ctx "ptr" name in
    let r  = fresh ctx "ar" in
    emit ctx (Printf.sprintf
      "%s = call i64 @march_actor_register(ptr %s, ptr %s)" r vn vp);
    ("i64", r)

  | Tir.EApp (f, [tbl; key; value; maxn])
    when Builtin_name.is Builtin_name.Vault_push_capped f.Tir.v_name ->
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
    when Builtin_name.is Builtin_name.Vault_get f.Tir.v_name ->
    let vt = emit_atom_as ctx "ptr" tbl in
    let vk = emit_atom_as ctx "ptr" key in
    let r  = fresh ctx "vg" in
    emit ctx (Printf.sprintf
      "%s = call ptr @march_vault_get(ptr %s, ptr %s)" r vt vk);
    ("ptr", emit_vault_opt_reencode ctx r (fn_ret_tir f.Tir.v_ty))

  | Tir.EApp (f, [tbl; key])
    when Builtin_name.is Builtin_name.Vault_drop f.Tir.v_name ->
    let vt = emit_atom_as ctx "ptr" tbl in
    let vk = emit_atom_as ctx "ptr" key in
    emit ctx (Printf.sprintf
      "call ptr @march_vault_drop(ptr %s, ptr %s)" vt vk);
    ("i64", "0")

  | Tir.EApp (f, [tbl; key; fn_atom])
    when Builtin_name.is Builtin_name.Vault_update f.Tir.v_name ->
    let vt = emit_atom_as ctx "ptr" tbl in
    let vk = emit_atom_as ctx "ptr" key in
    let vf = emit_atom_as ctx "ptr" fn_atom in
    emit ctx (Printf.sprintf
      "call ptr @march_vault_update(ptr %s, ptr %s, ptr %s)" vt vk vf);
    ("i64", "0")

  | Tir.EApp (f, [tbl; key; delta])
    when Builtin_name.is Builtin_name.Vault_incr f.Tir.v_name ->
    let vt = emit_atom_as ctx "ptr" tbl in
    let vk = emit_atom_as ctx "ptr" key in
    let vd = emit_atom_as ctx "i64" delta in
    let r  = fresh ctx "vi" in
    emit ctx (Printf.sprintf
      "%s = call i64 @march_vault_incr(ptr %s, ptr %s, i64 %s)" r vt vk vd);
    ("i64", r)

  | Tir.EApp (f, [ns; key; value])
    when Builtin_name.is Builtin_name.Vault_ns_set f.Tir.v_name ->
    let vn = emit_atom_as ctx "ptr" ns in
    let vk = emit_atom_as ctx "ptr" key in
    let vv = emit_atom_as ctx "ptr" value in
    emit ctx (Printf.sprintf
      "call ptr @march_vault_ns_set(ptr %s, ptr %s, ptr %s)" vn vk vv);
    ("i64", "0")

  | Tir.EApp (f, [ns; key])
    when Builtin_name.is Builtin_name.Vault_ns_get f.Tir.v_name ->
    let vn = emit_atom_as ctx "ptr" ns in
    let vk = emit_atom_as ctx "ptr" key in
    let r  = fresh ctx "vng" in
    emit ctx (Printf.sprintf
      "%s = call ptr @march_vault_ns_get(ptr %s, ptr %s)" r vn vk);
    ("ptr", emit_vault_opt_reencode ctx r (fn_ret_tir f.Tir.v_ty))

  | Tir.EApp (f, [ns; key])
    when Builtin_name.is Builtin_name.Vault_ns_drop f.Tir.v_name ->
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
    when Builtin_name.is Builtin_name.Actor_reply f.Tir.v_name ->
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
    when Builtin_name.is Builtin_name.Chan_send f.Tir.v_name ->
    let vep = emit_atom_as ctx "ptr" ep in
    let vv  = emit_atom_as ctx "ptr" value in
    let r = fresh ctx "cr" in
    emit ctx (Printf.sprintf
      "%s = call ptr @march_chan_send(ptr %s, ptr %s)" r vep vv);
    ("ptr", r)

  | Tir.EApp (f, [ep; label])
    when Builtin_name.is Builtin_name.Chan_choose f.Tir.v_name ->
    let vep = emit_atom_as ctx "ptr" ep in
    let vl  = emit_atom_as ctx "ptr" label in
    let r = fresh ctx "cr" in
    emit ctx (Printf.sprintf
      "%s = call ptr @march_chan_choose(ptr %s, ptr %s)" r vep vl);
    ("ptr", r)

  | Tir.EApp (f, [ep; role; value])
    when Builtin_name.is Builtin_name.Mpst_send f.Tir.v_name ->
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

  (* ── EApp of a prior REPL binding exposed via a prev-slot loader ─── *)
  (* Fn-defining REPL fragments have no var_slot bridge for prior bindings;
     they get module-level slot loaders instead (Llvm_repl.emit_slot_loader_fns).
     Route the call through ECallPtr dispatch — emit_atom's repl_slot_fns arm
     turns the callee into `call ptr @<name>()` (the loader) and the generic
     closure-dispatch arm calls through it.  Without this arm the call falls
     into the general path's unknown-function fallback, which `declare`s the
     very symbol the loader defines in this module — an invalid redefinition
     ("fn f ... end" then "fn g(x) do f(x) end" broke the whole fragment) —
     and a direct extern call would also pin the callee version compiled at
     this fn's definition time instead of following the slot. *)
  | Tir.EApp (f, args)
    when Hashtbl.mem ctx.repl_slot_fns f.Tir.v_name
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
    Llvm_emit_simd.emit_simd_call ~emit_atom ctx f args

  (* ── General function call ─────────────────────────────────────────── *)
  | Tir.EApp (f, args) ->
    Llvm_emit_call.emit_generic_app ~emit_atom ctx f args

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
    Llvm_emit_call.emit_callptr_raises ~emit_atom ctx f args

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
    Llvm_emit_call.emit_callptr_blocking ~emit_atom ctx f args

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
    Llvm_emit_call.emit_callptr_unqualified ~emit_atom ctx f args

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
    when not (Hashtbl.mem ctx.var_slot (llvm_name f.Tir.v_name))
      (* Prior REPL bindings with a prev-slot loader are NOT direct-callable
         globals — fall through to the generic closure-dispatch arm below,
         whose emit_atom of the callee calls the loader (see repl_slot_fns). *)
      && not (Hashtbl.mem ctx.repl_slot_fns f.Tir.v_name
              && not (Hashtbl.mem ctx.top_fns f.Tir.v_name)) ->
    Llvm_emit_call.emit_callptr_global ~emit_atom ctx f args

  | Tir.ECallPtr (Tir.AVar f, [a; b])
    when Builtin_name.(is Int_mod f.Tir.v_name || is Int_div f.Tir.v_name
                       || is Int_mod_euclid f.Tir.v_name
                       || is Int_div_euclid f.Tir.v_name) ->
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
    Llvm_emit_call.emit_callptr_closure ~emit_atom ctx fn_atom args

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
    Llvm_emit_alloc.emit_static_closure ctx tcon_name fn_ptr_atom

  (* ── Heap allocation ───────────────────────────────────────────────── *)
  | Tir.EAlloc (Tir.TCon (ctor, alloc_params), args) ->
    Llvm_emit_alloc.emit_alloc_ctor ~emit_atom ctx ctor alloc_params args
  | Tir.EAlloc (_, args) ->
    Llvm_emit_alloc.emit_alloc_uniform ~emit_atom ctx args

  (* ── TRMC hole allocation / hole fill ──────────────────────────────── *)
  (* [EAllocHole (ty, filled, hole)] is [EAlloc] with field [hole] left
     UNWRITTEN.  [march_alloc] is a calloc, so the hole reads as 0 until
     [ESetField] fills it, and IS_HEAP_PTR(0) is false — an RC op or deep-drop
     that reaches an unfilled hole is a no-op rather than a wild dereference.
     That is the property the whole TRMC scheme leans on for the window between
     allocation and fill. *)
  | Tir.EAllocHole (tok, Tir.TCon (ctor, _), args, hole) ->
    Llvm_emit_alloc.emit_alloc_hole ~emit_atom ctx tok ctor args hole

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
    Llvm_emit_alloc.emit_stack_alloc_ctor ~emit_atom ctx ctor args

  | Tir.EStackAlloc (_, args) ->
    Llvm_emit_alloc.emit_stack_alloc_uniform ~emit_atom ctx args

  (* ── FBIP reuse (conditional: check RC=1 before reusing in-place) ──── *)
  (* EReuse semantics: if RC=1, reuse in-place; else DecRC + alloc fresh.
     This is critical for correctness when the caller holds extra references
     (e.g. after IncRC before passing to a function). *)
  | Tir.EReuse (reuse_atom, Tir.TCon (ctor, _), args) ->
    Llvm_emit_alloc.emit_reuse_ctor ~emit_atom ctx reuse_atom ctor args

  | Tir.EReuse (reuse_atom, reuse_ty, args) ->
    Llvm_emit_alloc.emit_reuse_uniform ~emit_atom ctx reuse_atom reuse_ty args
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
    Llvm_emit_data.emit_tuple ~emit_atom ctx atoms

  (* ── Records ───────────────────────────────────────────────────────── *)
  | Tir.ERecord fields ->
    Llvm_emit_data.emit_record ~emit_atom ctx fields

  (* ── Field access ──────────────────────────────────────────────────── *)
  | Tir.EField (obj_atom, field_name) ->
    Llvm_emit_data.emit_field ~emit_atom ctx obj_atom field_name

  (* ── Record update ─────────────────────────────────────────────────── *)
  | Tir.EUpdate (base_atom, updates) ->
    Llvm_emit_data.emit_update ~emit_atom ctx base_atom updates

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

let emit_preamble = Llvm_toplevel.emit_preamble

let emit_module ?fast_math ?pmap_threshold ?target ?hot_reload ?impl_hashes
    ?remote_impl_hashes ?remote_sig_hashes ?emit_main ?cap_attrib ?cap_decls
    (m : Tir.tir_module) : string =
  Llvm_toplevel.emit_module ~emit_expr
    ?fast_math ?pmap_threshold ?target ?hot_reload ?impl_hashes
    ?remote_impl_hashes ?remote_sig_hashes ?emit_main ?cap_attrib ?cap_decls m


type repl_slot_info = Llvm_repl.repl_slot_info = {
  rs_bare : string;
  rs_slot : int;
  rs_ty : Tir.ty;
}

let emit_repl_expr ?fast_math ~n ~ret_ty ~prev_slots ~fns ?extern_fns
    ?store_as_slot ?session_wraps ~types (body : Tir.expr) : string =
  Llvm_repl.emit_repl_expr ~emit_expr
    ?fast_math ~n ~ret_ty ~prev_slots ~fns ?extern_fns ?store_as_slot
    ?session_wraps ~types body

let emit_repl_decl ?fast_math ~n ~name ~val_ty ~dest_slot ~prev_slots ~fns
    ?extern_fns ?session_wraps ~types (body : Tir.expr) : string =
  Llvm_repl.emit_repl_decl ~emit_expr
    ?fast_math ~n ~name ~val_ty ~dest_slot ~prev_slots ~fns ?extern_fns
    ?session_wraps ~types body

let emit_repl_fn_with_closure_slot ?fast_math ~n ~bind_name ~dest_slot
    ~prev_slots ?helper_fns ?extern_fns ?session_wraps ~types (fn : Tir.fn_def) : string =
  Llvm_repl.emit_repl_fn_with_closure_slot ~emit_expr
    ?fast_math ~n ~bind_name ~dest_slot ~prev_slots ?helper_fns ?extern_fns
    ?session_wraps ~types fn

let emit_fns_fragment ~types ~fns ?extern_fns ?session_wraps ~repl () : string =
  Llvm_repl.emit_fns_fragment ~emit_expr ~types ~fns ?extern_fns ?session_wraps
    ~repl ()
