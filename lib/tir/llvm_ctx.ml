(** LLVM emission context: the [ctx] record, its constructor, fresh-name /
    emit primitives, name sanitization, atom-hash interning, core type
    mapping, the scalar/pointer [coerce] helper, and string-literal
    interning.

    Wave 3 Task 3 (chunk 2) split: moved verbatim out of [llvm_emit.ml] —
    same discipline as the Wave 3 Task 5 [Perceus] split (perceus_liveness.ml
    etc.): whole-definition moves, no behavior change, fully-qualified
    references (this file, like llvm_emit.ml, uses no [open]).  Consumers
    (bin/main.ml, lib/jit/repl_jit.ml, test/ files) never referenced these items
    directly — only [Llvm_emit.emit_module] / [emit_repl_*] / [target_config]
    / [mangle_extern] / [repl_slot_info] — so no PUBLIC-API re-export shim is
    needed for external callers; but [llvm_emit.ml] itself DOES re-export every
    moved name bare (`let fresh = Llvm_ctx.fresh`, etc., ~25 bindings) so its
    own ~600 pre-existing unqualified in-file call sites keep compiling
    unchanged — the same in-file-shim pattern the [Perceus]/[Llvm_builtins]
    splits use, not a qualify-at-call-site rewrite.

    HAZARD H1 (this task): the two audited helpers below,
    [emit_tag_scalar] / [emit_untag_scalar] / [emit_untag_known_scalar],
    consolidate ~9 previously-inline instruction sequences duplicated across
    llvm_emit.ml's emit arms.  Every converted call site passes its
    historical register-name prefix(es) so the emitted IR — register names
    included — is byte-identical to before this refactor. See each helper's
    doc comment for the exact law and citation. *)

(* ── Context ─────────────────────────────────────────────────────────── *)

(** Constructor info: ctor_name → (tag_index, field_tir_types) *)
type ctor_entry = { ce_tag : int; ce_fields : Tir.ty list }

(** REPL/JIT cross-FRAGMENT bookkeeping for `$clo_wrap` trampolines.

    [emitted_wraps] on the ctx is scoped to ONE fragment, which is exactly right
    natively (one module) but wrong under the JIT, where every fragment of a
    session is materialized into a SINGLE symbol namespace: a second fragment
    that also uses `double` as a first-class value would re-define
    `@double$clo_wrap`, which ORC's shared JITDylib rejects outright ("duplicate
    definition of symbol") and clang's per-.so flat namespace merely tolerated.

    Two tables, for the same reason [Repl_jit.partition_fns] and
    [Repl_jit.mark_compiled_fns] are two separate steps:

    - [sw_defined] — wrappers a PREVIOUSLY SUCCEEDED fragment actually
      materialized. Read-only here; a hit means "emit a `declare`".
    - [sw_pending] — the [`Define] decisions THIS fragment just made. Emission
      writes only here; [Repl_jit] promotes them into [sw_defined] only after
      [compile_fragment] + dlopen succeed, and drops them otherwise.

    Committing at emission time instead would be a real bug, not a nicety: a
    fragment can emit a define and then FAIL to compile (the REPL prints the
    error and continues). A session table already claiming the wrapper exists
    would make the next fragment emit a `declare` against a symbol that was
    never materialized — an unresolved symbol, where the pre-change code
    recovered by simply redefining it. *)
type session_wraps = {
  sw_defined : (string, unit) Hashtbl.t;
  sw_pending : (string, unit) Hashtbl.t;
}

type ctx = {
  buf       : Buffer.t;
  preamble  : Buffer.t;
  mutable ctr     : int;
  mutable blk     : int;
  mutable str_ctr : int;
  ctor_info : (string, ctor_entry) Hashtbl.t;
  top_fns   : (string, bool) Hashtbl.t;
  (* Maps fn_name → fn_ret_ty for functions registered in top_fns.
     Used in EApp to resolve concrete return types when call-site TVar is "_". *)
  top_fn_ret_ty : (string, Tir.ty) Hashtbl.t;
  (* Maps fn_name → number of parameters for top-level functions.
     Used when emitting a top-level function as a first-class value (closure
     trampoline) but the AVar's v_ty is TVar _ rather than TFn. *)
  top_fn_nparams : (string, int) Hashtbl.t;
  (* Maps fn_name → declared parameter types for top-level functions.
     Used in EApp to coerce each argument's ACTUAL emitted representation
     (e.g. "ptr" for a value extracted from a generic/polymorphic ADT field
     under the uniform-slot convention) to the callee's concrete, monomorphic
     parameter representation (e.g. "double" for a Float param) — without
     this, a Float value flowing from a generic container field straight
     into a monomorphic function call is passed as a raw boxed pointer while
     the callee reads it as a native double, silently corrupting the value
     (the Array.from_list$..$Float compiled-wrong-value bug). *)
  top_fn_param_tys : (string, Tir.ty list) Hashtbl.t;
  (* Per-callee list of parameter INDICES that [Llvm_toplevel.emit_fn] gives a
     NATIVE `<N x T>` SIMD-vector TCO slot (the `native_vec_slot` arm).  Filled
     by a pre-pass in [emit_module] before ANY function body is emitted, so a
     call site is never asked about a callee that has not been emitted yet.

     Consumed by llvm_emit's EApp arm to decide whether a vector argument box
     the CALL SITE just created may be released after the call: a native-slot
     callee provably uses the incoming pointer for exactly one GEP + load in
     its entry prologue and never stores it anywhere, so the temp box cannot
     escape into the callee.  Any other callee shape (a `ptr` vector param)
     may store the pointer into a heap aggregate that then owns it — releasing
     there is a use-after-free.  See the invariant comment at the EApp arm. *)
  native_vec_params : (string, int list) Hashtbl.t;
  (* Set of zero-argument top-level functions (module-level `let` constants
     compiled as zero-arg functions).  When emit_atom encounters an AVar
     referencing one of these, it calls the function to obtain the value
     rather than emitting a function pointer.  Populated alongside top_fns. *)
  zero_arg_fns  : (string, bool) Hashtbl.t;
  field_map : (string, (string * Tir.ty) list) Hashtbl.t;
  mutable ret_ty  : Tir.ty;
  fast_math : bool;
  pmap_threshold : int;  (* --pmap-threshold: List.pmap sequential-fallback cutoff *)
  (* The full type_def table for the module/fragment currently being emitted.
     Consulted by EAlloc, EReuse, emit_case, and ensure_adt_eq_fn (via
     Repr.is_niche_shaped / niche_payload_ok / repr_of_ty / payload_needs_tag)
     to decide niche/newtype/boxed representation. Populated at ctx
     construction (make_ctx) from the `types` parameter every entry point
     (emit_module, emit_repl_expr, emit_repl_decl, emit_repl_fn,
     emit_repl_fn_with_closure_slot, emit_fns_fragment) already receives.
     Previously this was a single module-level ref (`cur_type_defs`) set only
     by emit_module — REPL/JIT fragment emitters never set it, so every
     fragment's representation decisions ran against a stale or empty table,
     causing niche-vs-boxed ABI mismatches across JIT fragments (B12). *)
  type_defs : Tir.type_def list;
  (* Same-short-name type collision set, derived from [type_defs] (see
     [Collision_set.compute]'s doc comment): short type name -> full
     declaring names, present ONLY for short names declared by >=2 modules.
     Consulted by [Llvm_toplevel.build_ctor_info] to decide whether a
     TDVariant's constructors need a globally-unique runtime tag instead of
     the ordinary per-type 0-based tag. Always derived from the same
     [type_defs] this ctx was constructed with, so it can never drift out of
     sync with the types build_ctor_info actually sees. *)
  collision_set : (string, string list) Hashtbl.t;
  (* For resolving concrete field types from polymorphic type definitions.
     poly_ctors: (type_name, ctor_name) -> generic field types (may contain TVar)
     type_params: type_name -> ordered list of type-variable parameter names *)
  poly_ctors  : (string * string, Tir.ty list) Hashtbl.t;
  type_params : (string, string list) Hashtbl.t;
  (* Maps each TIR variable name to its current LLVM alloca slot name.
     Updated when a new ELet binding is created; loads look up the current
     slot here.  When a name is shadowed (let x = ...; let x = ...), the
     second alloca is given a unique suffix (x_1, x_2, ...) and the map is
     updated so loads in the inner body use the right slot. *)
  var_slot  : (string, string) Hashtbl.t;
  (* Counts alloca name uses for uniquification. *)
  local_names : (string, int) Hashtbl.t;
  (* Tracks which closure wrappers have been generated for top-level fns *)
  emitted_wraps : (string, unit) Hashtbl.t;
  (* REPL/JIT cross-fragment `$clo_wrap` bookkeeping — see the [session_wraps]
     type above and [wrap_emit_kind] below.  [None] on the AOT path
     ([emit_module]), which therefore behaves exactly as it did before. *)
  mutable session_wraps : session_wraps option;
  (* Memo: mangled fn name -> emitted static-closure global symbol.
     One immortal closure object per top-level function used as a value,
     replacing a fresh march_alloc(24) at every materialization site. *)
  static_clos : (string, string) Hashtbl.t;
  (* Buffer for extra wrapper functions emitted at the end *)
  extra_fns : Buffer.t;
  (* Tracks which ADT structural equality functions have been generated.
     Registered before body generation to handle recursive types (e.g. List). *)
  emitted_eq_fns : (string, unit) Hashtbl.t;
  (* Tracks which generated runtime interface-dispatch functions
     ([__march_ifdispatch$...]) have been emitted — a same-short-name
     colliding type's general-interface method routes through one of these,
     which switches on the callee's runtime ctor tag (Task 1's global tags)
     and tail-calls the correct module-qualified impl (Task 3's symbols).
     Sibling of [emitted_eq_fns]; see [Llvm_dispatch.ensure_dispatch_fn]. *)
  emitted_dispatch_fns : (string, unit) Hashtbl.t;
  (* User-defined extern function name mapping: march_name → c_name *)
  extern_map : (string, string) Hashtbl.t;
  (* Extern march_names declared `blocking` — dispatched on an OS thread. *)
  blocking_externs : (string, unit) Hashtbl.t;
  (* Extern march_names declared `raises` — env-routed error protocol: the C
     binding takes a march_env* + returns the bare Ok payload, and the call site
     wraps the result into Ok/Err. *)
  raises_externs : (string, unit) Hashtbl.t;
  (* Tracks forward declarations emitted for unknown functions (interface dispatch
     calls that are not resolved at compile time due to type erasure). Maps
     function LLVM name → declare string to avoid duplicate declarations. *)
  unknown_decls : (string, unit) Hashtbl.t;
  (* REPL fn-fragment prev-slot loaders (bare binding name → ()).  Populated by
     Llvm_repl.emit_slot_loader_fns for each `define @<name>()` loader it emits.
     The EApp/ECallPtr paths consult this so a call to a prior REPL binding
     dispatches through the loader's closure value instead of falling into the
     unknown-function fallback — which would `declare @<name>` the very symbol
     the loader defines in the same module (invalid redefinition), and would
     also pin the callee version compiled at definition time rather than
     following the slot. *)
  repl_slot_fns : (string, unit) Hashtbl.t;
  (* Unqualified suffix → qualified TIR name for cross-module function refs
     that lower.ml emits without the module prefix (e.g. "base64_encode" →
     "Crypto.base64_encode").  Populated during emit_module init. *)
  unqualified_fns : (string, string) Hashtbl.t;
  (* Hot Code Reload (Phase 2). When [hr_config] is [Some], a boundary→boundary
     call is emitted as a versioned-dispatch indirect call instead of a direct
     one. [hr_names] interns reloadable fn names → NAME_ID; [hr_cur_module] is
     the module of the function currently being emitted (the caller). *)
  hr_config : Hot_reload.config option;
  hr_names  : Hot_reload.Name_table.t;
  mutable hr_cur_module : string;
  (* Tracks the actual LLVM type stored in each alloca slot, keyed by slot name.
     Used to emit correct load types even when TIR var has unresolved TVar. *)
  var_llvm_ty : (string, string) Hashtbl.t;
  (* TCO state — set by emit_fn when emitting a self-tail-recursive function.
     tco_fn_name: the TIR name of the function being TCO'd (None = no TCO active).
     tco_loop_label: the LLVM block label to branch to for loop back-edge.
     tco_param_info: (tir_var_name, alloca_slot, llvm_ty) for each parameter,
       in declaration order — used to store new argument values before looping. *)
  mutable tco_fn_name   : string option;
  (* TIR name of the function currently being emitted — for diagnostics
     (e.g. the shape-mismatch match-failure panic message). *)
  mutable cur_emit_fn   : string;
  mutable tco_loop_label : string;
  mutable tco_param_info : (string * string * string) list;
  (* SSA value (e.g. "%sp.save42") holding the llvm.stacksave() result taken at
     the top of the TCO loop body.  Every back-edge must call
     llvm.stackrestore on this value before branching back to the loop header
     — otherwise any `alloca` textually inside the loop body (case-branch
     bindings, struct/closure construction, etc.) allocates a NEW stack slot
     on every iteration that is never freed until the function returns,
     since LLVM only auto-pops alloca-from-loop stack growth at `ret`, not at
     back-edges. With large iteration counts (e.g. a 10k-element list fold)
     this silently exhausts the stack and crashes with SIGBUS/SIGSEGV even
     though the loop itself is O(1) stack via the back-edge. *)
  mutable tco_stack_save : string;
  (* True while emitting an expression in TAIL position of the current TCO
     function.  A self-EApp only becomes a loop back-edge when this holds;
     a self-call in non-tail position (an ELet rhs / ESeq prefix, e.g. the
     recursive call inside `Cons(x, f(t))`) must emit an ordinary call so the
     surrounding construction is not discarded.  Cleared by emit_expr around
     non-tail sub-expressions and restored afterwards. *)
  mutable tco_in_tail   : bool;
  (* Names of locals in the function being emitted whose binding RHS is a
     "dup" — [ESeq (EIncRC x, EAtom x)], the shape Perceus uses to
     materialise an owned local from a borrowed field (e.g. the `t` of a
     `Cons(_, t)` pattern).  Such a local carries a +1 that its post-call
     DecRC is the matching half of, which is what distinguishes it from a
     freshly-allocated, uncompensated value.  The TCO back-edge emitters
     consult this to decide whether a dec-chain op on a FORWARDED argument
     must still execute (dup-bound: yes, or the +1 leaks every iteration)
     or be skipped (uncompensated: skipping avoids a use-after-free — see
     commit eafbd71a).  Populated by [emit_fn] per function. *)
  mutable tco_dup_bound : string list;
  (* Mutual TCO state — set by emit_mutual_tco_group for the combined function.
     mutual_tco_group: names of all functions in the current mutual group (empty = not active).
     mutual_tco_tag_slot: alloca slot name for the dispatch tag.
     mutual_tco_loop_label: label of the shared loop header.
     mutual_tco_fn_params: fn_name -> [(tir_var_name, alloca_slot, llvm_ty)] for each function's params.
     mutual_tco_fn_tags: fn_name -> dispatch integer tag. *)
  mutable mutual_tco_group      : string list;
  mutable mutual_tco_tag_slot   : string;
  mutable mutual_tco_loop_label : string;
  mutable mutual_tco_fn_params  : (string * (string * string * string) list) list;
  mutable mutual_tco_fn_tags    : (string * int) list;
  (* Same purpose as tco_stack_save but for the combined mutual-TCO loop. *)
  mutable mutual_tco_stack_save : string;
  (* When true, skip the reduction-budget check (march_tls_reductions load/store).
     ORC JIT on macOS cannot resolve TLS variables via emutls; the REPL is
     always single-threaded so the check is unnecessary there anyway. *)
  repl : bool;
  (* Native record shape metadata: when true (non-WASM targets), record
     allocations call march_record_set_shape to stamp the interned shape id
     into the header pad word so the record introspection builtins
     (record_keys/values/entries/get/put/has_key/from_list) and dynamic
     field reads can recover field names at runtime.  See the
     "Record shape registry" section in runtime/march_extras.c. *)
  mutable shape_meta : bool;
  (* Record shape descriptor → (descriptor string global, i32 id-cache global). *)
  rec_shape_globals : (string, string * string) Hashtbl.t;
  (* Distributed OTP L4: CAS-derived hash maps for remote_ref_hashes constant folding.
     Maps qualified fn name ("Math.add") → hex hash string. *)
  remote_impl_hashes : (string, string) Hashtbl.t;
  remote_sig_hashes  : (string, string) Hashtbl.t;
  (* When true, non-exported function definitions in the patch .so get hidden
     ELF visibility so intra-.so PLT calls resolve to the .so's own definitions
     instead of looking up the global symbol table.  Without this, a v2 patch's
     Counter_dispatch calling Counter_PrintHistory$Counter_Actor$V__ would find
     the v1 symbol from the already-loaded server binary (same symbol name,
     loaded first).  On Linux this combines with RTLD_DEEPBIND; on macOS it is
     the only mechanism because RTLD_DEEPBIND is unavailable. *)
  compile_so : bool;
  (* Reverse table for showing atoms: interned FNV-1a hash -> the atom's
     source name (WITHOUT the leading ':').  Atoms compile to nameless i64
     hashes (see [atom_hash]), so `Show$Atom.show` cannot reconstruct `:name`
     from the runtime value alone.  Every atom literal seen during codegen
     (emit_atom's LitAtom arm and emit_case's atom-tag arm) records its
     (hash, name) here; at module finalization [emit_atom_show_table] emits a
     generated `@march_atom_to_string` switch over this table.  Keyed by hash so
     a repeated atom is registered once and colliding hashes can't produce a
     duplicate LLVM switch case. *)
  atom_names : (int64, string) Hashtbl.t;
}

(** LLVM scalar type for an unboxed aggregate's field.  A deliberate
    three-case duplicate of [llvm_ty] (defined below, after this function)
    rather than a forward reference: [Repr.set_unboxed_types] admits only
    Int/Float/Bool fields, so these three cases are the whole domain, and
    keeping [make_ctx] able to emit the struct declarations itself means the
    declaration and the registration happen in one place — no entry point
    (compiler, REPL, JIT) can register the types and forget to declare them. *)
let unboxed_field_llvm_ty : Tir.ty -> string = function
  | Tir.TFloat -> "double"
  | Tir.TInt | Tir.TBool -> "i64"
  | other ->
    failwith (Printf.sprintf
                "LLVM emit: unboxed aggregate has non-scalar field type %s \
                 (Repr.set_unboxed_types should have rejected the type)"
                (Tir.show_ty other))

let make_ctx ?(fast_math=false) ?(pmap_threshold=1024) ?(repl=false)
    ?(hot_reload=None) ?(hr_names=Hot_reload.Name_table.build [])
    ?(type_defs=[]) () =
  let collision_set = Collision_set.compute type_defs in
  (* Milestone 3: decide the unboxed-aggregate set for THIS module before any
     emission reads [llvm_ty].  Doing it here rather than only in
     [Contract_pipeline.run] is what covers the REPL and the JIT, which build a
     ctx directly; the derivation is a pure function of [type_defs] so the two
     registrations agree by construction. *)
  if repl then begin
    Repr.force_disable ();
    Repr.set_unboxed_types ~collision_set ~enabled:false type_defs
  end else Repr.ensure_unboxed_types ~collision_set type_defs;
  let preamble = Buffer.create 1024 in
  List.iter (fun (_tname, lname, fields) ->
      Buffer.add_string preamble
        (Printf.sprintf "%s = type { %s }\n" lname
           (String.concat ", " (List.map unboxed_field_llvm_ty fields))))
    (Repr.unboxed_types ());
  {
  buf      = Buffer.create 4096;
  preamble;
  ctr      = 0; blk = 0; str_ctr = 0;
  ctor_info = Hashtbl.create 64;
  top_fns   = Hashtbl.create 64;
  top_fn_ret_ty = Hashtbl.create 64;
  top_fn_nparams = Hashtbl.create 64;
  top_fn_param_tys = Hashtbl.create 64;
  native_vec_params = Hashtbl.create 8;
  zero_arg_fns  = Hashtbl.create 16;
  field_map = Hashtbl.create 16;
  ret_ty   = Tir.TUnit;
  fast_math;
  pmap_threshold;
  type_defs;
  collision_set;
  var_slot    = Hashtbl.create 32;
  local_names = Hashtbl.create 32;
  poly_ctors  = Hashtbl.create 64;
  type_params = Hashtbl.create 16;
  emitted_wraps = Hashtbl.create 8;
  session_wraps = None;
  static_clos = Hashtbl.create 16;
  extra_fns = Buffer.create 1024;
  emitted_eq_fns = Hashtbl.create 16;
  emitted_dispatch_fns = Hashtbl.create 8;
  extern_map = Hashtbl.create 8;
  blocking_externs = Hashtbl.create 4;
  raises_externs = Hashtbl.create 4;
  unknown_decls = Hashtbl.create 8;
  repl_slot_fns = Hashtbl.create 8;
  unqualified_fns = Hashtbl.create 32;
  hr_config = hot_reload;
  hr_names;
  hr_cur_module = "";
  var_llvm_ty = Hashtbl.create 32;
  tco_fn_name    = None;
  cur_emit_fn    = "";
  tco_loop_label = "";
  tco_param_info = [];
  tco_in_tail    = true;
  tco_stack_save = "";
  tco_dup_bound  = [];
  mutual_tco_group      = [];
  mutual_tco_tag_slot   = "";
  mutual_tco_loop_label = "";
  mutual_tco_fn_params  = [];
  mutual_tco_fn_tags    = [];
  mutual_tco_stack_save = "";
  repl;
  shape_meta = true;
  rec_shape_globals = Hashtbl.create 16;
  remote_impl_hashes = Hashtbl.create 0;
  remote_sig_hashes  = Hashtbl.create 0;
  compile_so = false;
  atom_names = Hashtbl.create 16;
}

(* Shared with the inliner; single source of truth in Hot_reload. *)
let module_of_name = Hot_reload.module_of_name

(* ── Helpers ─────────────────────────────────────────────────────────── *)

let fresh ctx pfx =
  ctx.ctr <- ctx.ctr + 1;
  Printf.sprintf "%%%s%d" pfx ctx.ctr

let fresh_block ctx pfx =
  ctx.blk <- ctx.blk + 1;
  Printf.sprintf "%s%d" pfx ctx.blk

let emit ctx line =
  Buffer.add_string ctx.buf "  ";
  Buffer.add_string ctx.buf line;
  Buffer.add_char   ctx.buf '\n'

let emit_label ctx label =
  Buffer.add_string ctx.buf label;
  Buffer.add_string ctx.buf ":\n"

let emit_term ctx line = emit ctx line

(** Sanitize a variable name for use as a bare LLVM identifier.
    Replaces any char not in [a-zA-Z0-9_.$] with '_'. *)
let llvm_name (name : string) : string =
  String.map (fun c ->
    if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
       (c >= '0' && c <= '9') || c = '_' || c = '.' || c = '$'
    then c
    else '_'
  ) name

(** Return a unique alloca slot name for TIR variable [base] and update
    var_slot so subsequent loads of [base] use this slot.
    First use returns [base] unchanged; shadowing gives [base_1], [base_2], ...

    Wave 3 Task 5 (chunk 2) split: moved verbatim from [llvm_emit.ml].  Left
    in place by Task 3 (not named in that brief; only pure ctx-hashtable
    helper without a standalone external consumer yet) — now moves because
    [emit_case] (Task 5, now in [Llvm_case]) is one of its call sites, and
    [Llvm_case] must not depend back on [llvm_emit.ml] (the module it was
    extracted from) to reach it. *)
let alloca_name ctx (base : string) : string =
  let slot = match Hashtbl.find_opt ctx.local_names base with
    | None ->
      Hashtbl.replace ctx.local_names base 1;
      base
    | Some n ->
      Hashtbl.replace ctx.local_names base (n + 1);
      base ^ "_" ^ string_of_int n
  in
  Hashtbl.replace ctx.var_slot base slot;
  slot

(** FNV-1a 64-bit hash — used for stable atom → i64 mapping.
    Must match the C runtime implementation in march_runtime.c. *)
let fnv1a_64 (s : string) : int64 =
  let fnv_offset = 0xcbf29ce484222325L in
  let fnv_prime  = 0x100000001b3L in
  String.fold_left (fun h c ->
    Int64.mul (Int64.logxor h (Int64.of_int (Char.code c))) fnv_prime
  ) fnv_offset s

(** Atom interning value: FNV-1a 64-bit of the name, then forced so bit63 ==
    bit62.  Atoms are i64 immediates that may flow through GENERIC (ptr)
    constructor slots, where they are tag-encoded as (n<<1)|1 and decoded with
    an ARITHMETIC shift-right (see emit_conv ptr<->i64).  That round-trip is
    lossless only when bit63 == bit62 (a sign-extended 63-bit integer); a raw
    64-bit hash with bit63 <> bit62 is corrupted on extract — e.g. :put / :post
    came back as garbage, breaking Router method matching.  Forcing
    bit63 := bit62 makes every atom survive generic-slot transit while keeping
    63 bits of entropy.  BOTH atom-emission sites (literal + switch-arm tag)
    must use this. *)
let atom_hash (name : string) : int64 =
  let h = fnv1a_64 name in
  let bit62 = Int64.logand (Int64.shift_right_logical h 62) 1L in
  Int64.logor
    (Int64.logand h 0x7FFFFFFFFFFFFFFFL)   (* clear bit63 *)
    (Int64.shift_left bit62 63)            (* set bit63 := bit62 *)

(* ── Type mapping ─────────────────────────────────────────────────────── *)

let llvm_ty : Tir.ty -> string = function
  | Tir.TInt    -> "i64"
  | Tir.TFloat  -> "double"
  | Tir.TBool   -> "i64"   (* booleans as i64 for uniform field layout *)
  | Tir.TUnit   -> "i64"   (* unit = i64 0 *)
  | Tir.TString -> "ptr"
  | Tir.TCon ("Atom", []) -> "i64"  (* atoms are interned i64 hashes, not heap ptrs *)
  (* Milestone 3: a small scalar-only single-ctor variant is an LLVM struct
     VALUE — [{ double, double, double }] for [Vec3(Float, Float, Float)] —
     passed and returned in registers, never a cell.  The identified struct
     type is declared once per module by [Llvm_toplevel.emit_module]; the
     registry it is read from is [Repr]'s, the same one [Llvm_emit_alloc],
     [Llvm_case] and [Rc_types] read, so this mapping can never disagree with
     the construction, destructuring or RC treatment of the same type. *)
  | Tir.TCon (name, _) when Repr.unboxed_of_type_name name <> None ->
    Repr.unboxed_llvm_name name
  | Tir.TCon _  -> "ptr"
  | Tir.TTuple _ -> "ptr"
  | Tir.TRecord _ -> "ptr"
  | Tir.TFn _   -> "ptr"
  | Tir.TPtr _  -> "ptr"
  | Tir.TVar _  -> "ptr"   (* pre-mono fallback *)

(** LLVM type for a HEAP-CELL SLOT holding a value of type [ty].

    Every March heap cell — variant, record, tuple, closure struct — lays its
    fields out as 8-byte slots at [16 + i*8] ([alloc_size]).  An unboxed
    aggregate's value type is WIDER than a slot ([{double,double,double}] is
    24 bytes), so storing one at a slot type would write over the following
    fields: use ["ptr"] and let [coerce] box it, exactly as a [Float] crossing
    into an erased slot is boxed.

    Use this — never [llvm_ty] — for any type that names a field of a heap
    cell ([ce_fields], record fields, tuple elements).  [llvm_ty] is for a
    value in a register, a parameter, a return type or a local alloca.
    [Llvm_data.emit_store_field]/[emit_load_field] fail loudly on a struct
    slot type, so a site that forgets is a build error, not silent
    corruption. *)
let llvm_field_ty (ty : Tir.ty) : string =
  match ty with
  | Tir.TCon (name, _) when Repr.unboxed_of_type_name name <> None -> "ptr"
  | _ -> llvm_ty ty

(* llvm_ret_ty moved here (Wave 3 Task 6, chunk 2): a pure ctx-independent
   wrapper around [llvm_ty] (Unit -> "void", else llvm_ty) with no home
   outside this file's already-depended-on base once [Llvm_calls] and
   [Llvm_tco] (both split out of [llvm_emit.ml] in that task) needed it too —
   same criterion as the Wave 3 Task 5 [alloca_name]/[repr_audit_record]
   moves ("pure primitive, real non-[llvm_emit.ml] consumer exists").
   Re-exported bare in [llvm_emit.ml], which still calls it unqualified at
   ~20 sites in [emit_expr]/[emit_fn]. *)
let llvm_ret_ty : Tir.ty -> string = function
  | Tir.TUnit -> "void"
  | t -> llvm_ty t

(** LLVM type string for a function *parameter*, augmented with alias-analysis
    attributes for pointer types.
    - [nonnull]: March allocators call exit(1) on OOM, so heap pointers are
      never null; this lets LLVM elide null checks in alias analysis.
    - [dereferenceable(16)]: every March heap object has at least a 16-byte
      header (rc:i64 + tag:i32 + pad:i32), so the pointer can always be
      safely dereferenced for 16 bytes.
    EXCEPTION: niche-encoded Option-shaped types can carry None=0 (null), so
    [nonnull] and [dereferenceable] must be suppressed for them. *)
let llvm_param_ty ?(type_defs : Tir.type_def list = [])
    ?(collision_set : (string, string list) Hashtbl.t = Hashtbl.create 0)
    (ty : Tir.ty) : string =
  match ty with
  | Tir.TCon ("Atom", []) -> "i64"
  (* Unboxed aggregate: a struct value, so none of the pointer alias
     attributes below apply.  Delegate to [llvm_ty]. *)
  | Tir.TCon (name, _) when Repr.unboxed_of_type_name name <> None -> llvm_ty ty
  | Tir.TCon (name, _) when Repr.is_niche_shaped ~collision_set type_defs name -> "ptr"
  | Tir.TString | Tir.TCon _ | Tir.TTuple _ | Tir.TRecord _ | Tir.TFn _
  | Tir.TPtr _ | Tir.TVar _ ->
    "ptr nonnull dereferenceable(16)"
  | other -> llvm_ty other

(* ── Object layout constants ──────────────────────────────────────────── *)

(** Allocation size in bytes for [n] fields.

    Cross-reference: [march_hdr] in runtime/march_runtime.h —
    [typedef struct { int64_t rc; int32_t tag; int32_t pad; } march_hdr;]
    i.e. offset 0 = rc (i64, 8 bytes), offset 8 = tag (i32), offset 12 = pad
    (i32) — a 16-byte header — followed by [n] 8-byte fields starting at
    offset 16.  Verified against runtime/march_runtime.h:11 on this task
    (2026-07-03): the header size (16) and per-field stride (8) below match
    the C struct exactly. Every literal offset used across llvm_emit.ml's
    emit arms (getelementptr ... i64 8 for tag, i64 12 for pad/shape-id,
    16 + i*8 for field i) is this same layout restated at each call site —
    those inline literals stay in llvm_emit.ml (heavy back-references into
    the emit_load_tag/emit_store_tag/emit_load_field/emit_store_field/
    emit_heap_alloc/emit_stack_alloc family); only this pure size formula
    moves, since it has no such back-references. *)
let alloc_size n = 16 + n * 8

(* ── Type coercion ───────────────────────────────────────────────────── *)

(** Emit an unconditional integer tag: [(v << 1) | 1], the ADDRESS of which
    is then produced via [inttoptr] into a generic ptr slot.  Low bit 1
    marks the value as an immediate scalar; heap pointers (from
    [march_alloc]) are always 16-byte-aligned and therefore always even, so
    an odd bit pattern can never collide with a real heap address (see the
    erased-i64 convention: ptr slots holding a tagged scalar are always odd;
    an even bit pattern in the same slot is a genuine heap pointer, restored
    with a BARE [inttoptr] — never re-tag it, see [emit_untag_scalar]).

    [~sh]/[~tag]/[~ptr] name the three intermediate SSA registers (shl / or /
    inttoptr, in that order) — HAZARD H1: every call site MUST pass its
    historical prefix triple so the fresh-counter registers it allocates,
    and therefore the emitted IR, are byte-identical to the pre-consolidation
    inline code. Returns the final `ptr` register. *)
let emit_tag_scalar ctx ~sh ~tag ~ptr (i64v : string) : string =
  let shifted = fresh ctx sh in
  (* nsw is a deliberate optimization enabler, not decoration: it asserts the
     shift cannot signed-overflow, which is exactly the existing tagging
     convention (values must survive the (v<<1)|1 / ashr-1 round trip, i.e.
     fit in 63 bits — the same assumption the trampoline and every erased
     slot already make).  With nsw, InstCombine folds the whole
     tag-then-conditionally-untag round trip away (ashr(or(shl nsw x,1),1)
     -> x); without it, a sign-truncating sbfx survives on every scalar
     round trip and, worse, blocks LLVM's accumulator TRE on recursive
     functions whose result feeds the tag.  Measured: bench/fib.march
     465 -> 385 ms.  Trade-off, documented deliberately: an Int outside
     [-2^62, 2^62) passed through an erased slot was ALREADY silently
     corrupted by the round trip; under nsw that same out-of-convention
     value is poison instead of a deterministic wrong value. *)
  emit ctx (Printf.sprintf "%s = shl nsw i64 %s, 1" shifted i64v);
  let tagged = fresh ctx tag in
  emit ctx (Printf.sprintf "%s = or i64 %s, 1" tagged shifted);
  let as_ptr = fresh ctx ptr in
  emit ctx (Printf.sprintf "%s = inttoptr i64 %s to ptr" as_ptr tagged);
  as_ptr

(** Emit a CONDITIONAL untag of an i64 value that may be either a tagged
    scalar ([(n << 1) | 1], always odd) or a heap pointer flowing through a
    scalar-typed view (always even — e.g. dynamically-typed record/alist
    code whose static type lies about the runtime value).  The law (erased-
    i64 convention, see [project_erased_i64_convention] / commit history on
    top of 20e53f2, bug_todos #40): an ODD value is untagged with an
    arithmetic right-shift; an EVEN value is preserved VERBATIM (it is a
    real, full pointer bit pattern, not `p >> 1`) — this makes tag→untag a
    lossless roundtrip for every bit pattern. NEVER apply this to a value
    already known to be a plain heap pointer with no scalar view — restore
    those with a bare [inttoptr] (no shift), not this helper and not
    [emit_tag_scalar]'s inverse.

    [~and_pfx]/[~ashr_pfx]/[~icmp_pfx]/[~sel_pfx] name the four intermediate
    registers in the exact historical fresh-allocation order (and, ashr,
    icmp, select) — HAZARD H1: this order (not textual emission order, which
    is and/icmp/ashr/select) is what the register numbers depend on; every
    call site must pass its historical prefixes to reproduce byte-identical
    IR. Takes the ALREADY-i64 value (a caller converting from [ptr] must
    [ptrtoint] first — see [coerce]'s ("ptr","i64") case, which does exactly
    that). Returns the final i64 register. *)
let emit_untag_scalar ctx ~and_pfx ~ashr_pfx ~icmp_pfx ~sel_pfx (i64v : string) : string =
  let b = fresh ctx and_pfx in
  let s = fresh ctx ashr_pfx in
  let o = fresh ctx icmp_pfx in
  let r = fresh ctx sel_pfx in
  emit ctx (Printf.sprintf "%s = and i64 %s, 1" b i64v);
  emit ctx (Printf.sprintf "%s = icmp ne i64 %s, 0" o b);
  emit ctx (Printf.sprintf "%s = ashr i64 %s, 1" s i64v);
  emit ctx (Printf.sprintf "%s = select i1 %s, i64 %s, i64 %s" r o s i64v);
  r

(** Emit an UNCONDITIONAL untag of a `ptr` value KNOWN — by construction, not
    by runtime check — to hold a tagged scalar (a newtype or niche payload
    that [emit_tag_scalar] tagged on the way in, so [payload_needs_tag] /
    [Repr.payload_needs_tag] already proved it is always odd at this program
    point).  Plain [ptrtoint] then an unconditional [ashr 1] — no [and]/
    [icmp]/[select] — because there is no other bit pattern to guard against
    here, unlike the general [emit_untag_scalar] case (which reads a
    caller-supplied, less-constrained value). Do not use this on a value
    that might be an ordinary heap pointer; that is a correctness bug this
    helper cannot catch (it always shifts).

    [~raw]/[~unt] name the two intermediate registers (ptrtoint, ashr) —
    HAZARD H1: pass each call site's historical prefix pair. Returns the
    final i64 register. *)
let emit_untag_known_scalar ctx ~raw ~unt (ptr_v : string) : string =
  let r = fresh ctx raw in
  emit ctx (Printf.sprintf "%s = ptrtoint ptr %s to i64" r ptr_v);
  let u = fresh ctx unt in
  emit ctx (Printf.sprintf "%s = ashr i64 %s, 1" u r);
  u

(** The 5 SIMD vector LLVM type strings and their runtime `kind` tags (must
    match `march_simd_alloc`'s kind switch / MARCH_SIMD_TAG's pad-slot
    convention in runtime/march_runtime.{h,c}: 0=f32x4 1=f64x2 2=i32x4
    3=i64x2 4=u8x16). *)
let vec_tys = [ "<4 x float>", 0; "<2 x double>", 1; "<4 x i32>", 2;
                "<2 x i64>", 3; "<16 x i8>", 4 ]
let is_vec_ty t = List.mem_assoc t vec_tys
let simd_kind_of_vec t = List.assoc t vec_tys

(** March-level type-constructor name → LLVM vector type, for the 5 SIMD
    vector types declared in `stdlib/simd.march` and registered in
    typecheck.ml's builtin env as [TCon ("F32x4", [])] &c.

    [llvm_ty] deliberately maps these to "ptr" (the feature's "boxed at rest"
    half of the two-form convention), so this table is the ONLY way a pass
    that starts from a [Tir.ty] — rather than from an already-emitted vector
    SSA value — can tell that a slot COULD hold a native vector. Used by
    [Llvm_toplevel.emit_fn] to give a self-tail-recursive function's
    vector-typed parameter a native (register-resident) TCO slot; see the
    "boxed at rest, native in kernels" note there.

    Matched on the SHORT name (after the last '.') so that both the bare
    `F32x4` spelling and a qualified `Simd.F32x4` resolve — mirroring
    [Repr]'s short-name classification discipline (see the Bytes/newtype
    ABI note in memory: classifying by long name silently misses the
    qualified spelling). *)
let simd_vec_tcons = [ "F32x4", "<4 x float>"; "F64x2", "<2 x double>";
                       "I32x4", "<4 x i32>";   "I64x2", "<2 x i64>";
                       "U8x16", "<16 x i8>" ]

let vec_ty_of_tir (t : Tir.ty) : string option =
  match t with
  | Tir.TCon (name, []) ->
    let short = match String.rindex_opt name '.' with
      | Some i -> String.sub name (i + 1) (String.length name - i - 1)
      | None   -> name
    in
    List.assoc_opt short simd_vec_tcons
  | _ -> None

(** Coerce value [v] from [from_ty] to [to_ty] if they differ.
    Returns the (possibly new) value string. *)
let coerce ctx from_ty v to_ty =
  if from_ty = to_ty then v
  else match (from_ty, to_ty) with
  | (vt, "ptr") when is_vec_ty vt ->
    (* Vector → erased slot: box into a march_simd_alloc leaf cell (payload at
       +16, 16-aligned) so RC ops on the erased ptr stay sound — same pattern
       as the ("double","ptr") float-boxing arm above. *)
    let b = fresh ctx "vbox" in
    emit ctx (Printf.sprintf "%s = call ptr @march_simd_alloc(i64 %d)" b (simd_kind_of_vec vt));
    let pp = fresh ctx "vpay" in
    emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" pp b);
    emit ctx (Printf.sprintf "store %s %s, ptr %s, align 16" vt v pp);
    b
  | ("ptr", vt) when is_vec_ty vt ->
    (* Erased slot → vector: unbox the payload back into a register value. *)
    let pp = fresh ctx "vpay" in
    emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" pp v);
    let r = fresh ctx "vunbox" in
    emit ctx (Printf.sprintf "%s = load %s, ptr %s, align 16" r vt pp);
    r
  (* ── Unboxed aggregates ↔ erased slots (Milestone 3) ─────────────────
     An inline aggregate crossing into a ptr slot (a tuple/record/closure
     field, a generic ADT payload, a task trampoline, an apply wrapper) is
     BOXED into exactly the heap cell it would have been under the Boxed
     representation: [march_alloc(16 + n*8)], the type's own constructor tag,
     one field per slot stored at its own LLVM type.  That is what makes the
     boundary invisible to everything downstream — generic equality, `show`,
     the interpreter-parity oracle and the runtime's own field readers all see
     the layout they saw before Milestone 3.  Pairs with the unbox arm below;
     the two must stay in lockstep, exactly like the Float box/unbox pair.

     Ownership: the box is a fresh rc=1 cell that Perceus does not track
     ([Rc_types.needs_rc] is false for the aggregate — see its module doc),
     the same position a boxed Float is in.  [Alloc_contract] therefore
     reports crossing this boundary as an allocation, so a [@[no_alloc]]
     function cannot silently pay for one. *)
  | (sty, "ptr") when Repr.unboxed_of_llvm_ty sty <> None ->
    (match Repr.unboxed_of_llvm_ty sty with
     | None -> assert false (* guard checked <> None *)
     | Some (tname, ctor, fields) ->
       let entry = Hashtbl.find_opt ctx.ctor_info (tname ^ "." ^ ctor) in
       let tag = match entry with Some e -> e.ce_tag | None -> 0 in
       let n = List.length fields in
       let box = fresh ctx "ubbox" in
       emit ctx (Printf.sprintf "%s = call ptr @march_alloc(i64 %d)" box (alloc_size n));
       let tp = fresh ctx "ubtag" in
       emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 8" tp box);
       emit ctx (Printf.sprintf "store i32 %d, ptr %s, align 4" tag tp);
       List.iteri (fun i fty ->
           let l = llvm_ty fty in
           let fv = fresh ctx "ubf" in
           emit ctx (Printf.sprintf "%s = extractvalue %s %s, %d" fv sty v i);
           let fp = fresh ctx "ubfp" in
           emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 %d" fp box (16 + i * 8));
           emit ctx (Printf.sprintf "store %s %s, ptr %s, align 8" l fv fp))
         fields;
       box)
  | ("ptr", sty) when Repr.unboxed_of_llvm_ty sty <> None ->
    (* Erased slot → inline aggregate: read the cell's fields back into a
       struct value.  The box itself is left alone; whoever owns it releases
       it, exactly as for [march_unbox_float]. *)
    (match Repr.unboxed_of_llvm_ty sty with
     | None -> assert false (* guard checked <> None *)
     | Some (_tname, _ctor, fields) ->
       let acc = ref "poison" in
       List.iteri (fun i fty ->
           let l = llvm_ty fty in
           let fp = fresh ctx "ubfp" in
           emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 %d" fp v (16 + i * 8));
           let fv = fresh ctx "ubf" in
           emit ctx (Printf.sprintf "%s = load %s, ptr %s, align 8" fv l fp);
           let nx = fresh ctx "ubi" in
           emit ctx (Printf.sprintf "%s = insertvalue %s %s, %s %s, %d"
                       nx sty !acc l fv i);
           acc := nx)
         fields;
       !acc)
  | ("ptr", "double") ->
    (* Erased slot → Float: UNBOX the heap float cell (float-boxing, Stage 2).
       A Float crossing an erasure boundary is stored as a `march_float_box`
       (tag -3), never raw bits — so RC ops on the erased ptr are sound and
       generic compare/eq dispatch on the box tag.  Concrete Float↔Float never
       hits this arm (both sides are `double`); the raw-bits REPL-slot path is
       the separate `("i64","double")` arm below. *)
    let r = fresh ctx "cv" in
    emit ctx (Printf.sprintf "%s = call double @march_unbox_float(ptr %s)" r v);
    r
  | ("double", "ptr") ->
    (* Float → erased slot: BOX into a heap float cell (float-boxing, Stage 2).
       Pairs with the unbox arm above; must stay in lockstep with every other
       erased-Float encode site (clo_wrap double-return, Ok-Float wrapper). *)
    let r = fresh ctx "cv" in
    emit ctx (Printf.sprintf "%s = call ptr @march_alloc_float(double %s)" r v);
    r
  | ("ptr", "i64") ->
    (* Untag a low-bit-tagged integer — CONDITIONALLY.  Producers store
       integers as (n<<1)|1 (always odd), so an odd value is untagged with an
       arithmetic right-shift.  An EVEN value cannot be a tagged scalar: it is
       a heap pointer flowing through a scalar-typed view (dynamically-typed
       record/alist code whose static type lies about the runtime value, e.g.
       depot's heterogeneous schema opts).  Preserving even bits verbatim
       makes tag→untag a lossless roundtrip for ALL bit patterns, so such
       values survive scalar-typed transit unscathed. *)
    let i = fresh ctx "cv" in
    emit ctx (Printf.sprintf "%s = ptrtoint ptr %s to i64" i v);
    emit_untag_scalar ctx ~and_pfx:"cv" ~ashr_pfx:"cv" ~icmp_pfx:"cv" ~sel_pfx:"cv" i
  | ("i64", "ptr") ->
    (* Tag an integer for polymorphic storage: (n << 1) | 1.
       Low bit 1 marks this as an immediate; heap pointers are always even. *)
    emit_tag_scalar ctx ~sh:"cv" ~tag:"cv" ~ptr:"cv" v
  | ("ptr", scalar) ->
    let r = fresh ctx "cv" in
    emit ctx (Printf.sprintf "%s = ptrtoint ptr %s to %s" r v scalar);
    r
  | (scalar, "ptr") ->
    let r = fresh ctx "cv" in
    emit ctx (Printf.sprintf "%s = inttoptr %s %s to ptr" r scalar v);
    r
  | ("i1", "i64") ->
    let r = fresh ctx "cv" in
    emit ctx (Printf.sprintf "%s = zext i1 %s to i64" r v);
    r
  | ("i64", "i1") ->
    let r = fresh ctx "cv" in
    emit ctx (Printf.sprintf "%s = trunc i64 %s to i1" r v);
    r
  | ("i64", "double") ->
    (* Float stored as raw bits in an i64 — reinterpret to double *)
    let r = fresh ctx "cv" in
    emit ctx (Printf.sprintf "%s = bitcast i64 %s to double" r v);
    r
  | _ -> v  (* other combos: leave as-is; LLVM will catch mismatches *)

(* ── String literals ─────────────────────────────────────────────────── *)

let llvm_escape_string s =
  let b = Buffer.create (String.length s) in
  String.iter (fun c ->
    let n = Char.code c in
    if n >= 32 && n < 127 && c <> '"' && c <> '\\' then Buffer.add_char b c
    else Buffer.add_string b (Printf.sprintf "\\%02X" n)
  ) s;
  Buffer.contents b

let intern_string ctx s =
  ctx.str_ctr <- ctx.str_ctr + 1;
  let name = Printf.sprintf "@.str%d" ctx.str_ctr in
  let len  = String.length s in
  Buffer.add_string ctx.preamble
    (Printf.sprintf "%s = private unnamed_addr constant [%d x i8] c\"%s\\00\"\n"
       name (len + 1) (llvm_escape_string s));
  name

(** Intern [s] as a literal SITE: the raw bytes (as [intern_string]) plus a
    per-site cell — a null-initialised global that
    [@march_string_lit_static] fills, once, with the immortal march_string
    for this literal.  Every later evaluation of the site loads the same
    pointer instead of allocating.

    A string literal carries no RC obligation in TIR — Perceus's
    [EAtom (ALit _)] arm treats it exactly like a global [ADefRef] — so
    codegen must not return a fresh rc=1 cell per evaluation: no binding
    owns that cell and no pass ever drops it.  It leaked once per
    evaluation, which only showed up when a literal was evaluated
    repeatedly *without* being let-bound (a let-bound literal gets an
    ordinary Perceus dec, and a literal argument to a non-allocating call is
    usually hoisted out of the loop) — canonically as a direct operand of
    `++`, as in the extremely common `acc ++ ", "` / `s ++ "\n"`.

    The cell is `internal global`, not `constant`: it is written on first
    use, and keeping the string itself out of read-only memory means a stray
    RC op on it can never fault. *)
let intern_string_site ctx s =
  let bytes = intern_string ctx s in
  ctx.str_ctr <- ctx.str_ctr + 1;
  let cell = Printf.sprintf "@.strcell%d" ctx.str_ctr in
  Buffer.add_string ctx.preamble
    (Printf.sprintf "%s = internal global ptr null\n" cell);
  (bytes, cell)

(* One immortal, statically-initialised closure object per top-level function
   used as a first-class value.  The object march_alloc would build here is
   entirely compile-time constant — march_hdr {rc; tag; pad} (16 bytes, see
   runtime/march_runtime.h) followed by the apply-fn pointer at offset 16,
   with tag = pad = 0 — so it needs no runtime construction at all: no
   fill-once helper and no atomic CAS, unlike march_string_lit_static whose
   bytes only exist at runtime.

   [rc] is MARCH_RC_IMMORTAL (1 << 40, runtime/march_runtime.h:304), which by
   construction (a) keeps march_decrc/_local's free-on-zero path unreachable
   and (b) makes the FBIP `rc == 1` uniqueness test always false, so no RC
   path needs a new immortality guard; march_free, which bypasses the count,
   already carries one (march_runtime.c:392).

   Emitted as `internal global`, NOT `constant`: a function value still has
   RC ops emitted against it (needs_rc (TFn _) = true), and a constant may be
   placed in read-only memory where a stray increment would fault.  Same
   reasoning, same choice as the string-literal cell. *)
(* [pad] is the header pad word (offset 12) — [Clo_flags.pad_for] of the
   function this closure dispatches to, i.e. 0 or MARCH_CLO_ARG0_BORROWED.
   It is a pure function of [fn_name], so memoizing on [fn_name] alone stays
   correct: the same closure never wants two different pads. *)
let intern_static_closure ?(pad = 0) ctx fn_name wrap_name =
  match Hashtbl.find_opt ctx.static_clos fn_name with
  | Some g -> g
  | None ->
    let g = Printf.sprintf "@%s$static_clo" fn_name in
    Buffer.add_string ctx.preamble
      (Printf.sprintf
         "%s = internal global { i64, i32, i32, ptr } { i64 1099511627776, i32 0, i32 %d, ptr @%s }\n"
         g pad wrap_name);
    Hashtbl.replace ctx.static_clos fn_name g;
    g

(** Decide how this fragment should provide [wrap_name] (a `$clo_wrap`
    trampoline), and record the decision.  Replaces the bare
    check-then-add-[emitted_wraps] guard that every `$clo_wrap` call site used
    to inline:

    - [`Skip]    — this fragment already emitted it; nothing more to do.
    - [`Define]  — emit the body ([Llvm_calls.clo_wrap_define]).
    - [`Declare] — an EARLIER fragment of this REPL/JIT session already defined
                   it, so emit only [Llvm_calls.clo_wrap_declare] and let the
                   linker/JITDylib bind the reference.  Only ever returned when
                   a session table is installed (see [session_wraps]); the AOT
                   path never sees it.

    A [`Define] is recorded in [sw_pending], NOT [sw_defined]: this fragment has
    only decided to emit the wrapper, and may still fail to compile.  Promotion
    to [sw_defined] belongs to [Repl_jit], next to [mark_compiled_fns], once the
    fragment actually materialized.

    Repeats within ONE fragment are caught by [emitted_wraps] before either
    session table is consulted, so a fragment can never define the same wrapper
    twice regardless of what the session tables hold. *)
let wrap_emit_kind ctx (wrap_name : string) : [ `Skip | `Define | `Declare ] =
  if Hashtbl.mem ctx.emitted_wraps wrap_name then `Skip
  else begin
    Hashtbl.add ctx.emitted_wraps wrap_name ();
    match ctx.session_wraps with
    | Some sw when Hashtbl.mem sw.sw_defined wrap_name -> `Declare
    | Some sw -> Hashtbl.replace sw.sw_pending wrap_name (); `Define
    | None -> `Define
  end

(* ── Repr-consistency audit (MARCH_REPR_AUDIT=1) ─────────────────────────
   Every site that COMMITS to a value representation (EAlloc, EReuse,
   emit_case, ensure_adt_eq_fn) records its decision here, keyed by
   "TypeName(payload)" — payload "?" when the site has no type params (the
   dangerous case: it guessed).  At end of emit_module, any type whose
   recorded encodings mix families (Boxed vs Niche vs Newtype) is reported:
   * same payload key, different families  → definite inconsistency;
   * a "?"-payload site disagreeing with a concrete one → the exact shape of
     the Option(Option(_)) None-null-vs-boxed bug (86c62b98).
   Records the ACTUAL decisions as they are made (not a re-derivation), so it
   cannot diverge from codegen.  Diagnostic only — no behavior change.

   Wave 3 Task 5 (chunk 2) split: moved verbatim from [llvm_emit.ml] to
   [llvm_ctx.ml] — [ensure_adt_eq_fn] (now in [Llvm_eq]), the EAlloc/EReuse
   arms (now calling into [Llvm_data]), and [emit_case] (now in [Llvm_case])
   all record into this table, and none of those three modules may depend on
   [llvm_emit.ml] (that would cycle back through the module they were
   extracted from) — so the shared audit state moves to the common
   already-depended-on base instead.  [emit_module] (which stays in
   llvm_emit.ml) still resets the table per module and prints the report;
   both are re-exported bare there, same pattern as the ctx primitives
   above. *)
let repr_audit_on = lazy (Sys.getenv_opt "MARCH_REPR_AUDIT" <> None)
(* type_name -> (payload_key, family, site) list, deduped *)
let _repr_audit : (string, (string * string * string) list ref) Hashtbl.t =
  Hashtbl.create 64
let repr_audit_record ~(ty : string) ~(payload : string) ~(family : string)
    ~(site : string) : unit =
  if Lazy.force repr_audit_on then begin
    let l = match Hashtbl.find_opt _repr_audit ty with
      | Some l -> l
      | None -> let l = ref [] in Hashtbl.add _repr_audit ty l; l
    in
    let entry = (payload, family, site) in
    if not (List.mem entry !l) then l := entry :: !l
  end
let repr_audit_report () =
  if Lazy.force repr_audit_on then begin
    let flagged = ref 0 in
    Hashtbl.iter (fun ty entries ->
      let es = !entries in
      let families = List.sort_uniq compare (List.map (fun (_, f, _) -> f) es) in
      if List.length families > 1 then begin
        (* Mixed families for this type: definite if within one concrete
           payload key; suspicious if via a "?" site. Legitimate when two
           DIFFERENT concrete payloads pick different reprs (Option(Int) niche
           vs Option(Float) boxed) — only flag same-key or ?-key conflicts. *)
        let same_key_conflict =
          List.exists (fun (p1, f1, _) ->
            List.exists (fun (p2, f2, _) -> p1 = p2 && f1 <> f2) es) es in
        let unknown_conflict =
          List.exists (fun (p, _, _) -> p = "?") es in
        if same_key_conflict || unknown_conflict then begin
          incr flagged;
          Printf.eprintf "[repr-audit] %s: MIXED %s%s\n" ty
            (String.concat "/" families)
            (if same_key_conflict then " (same-payload conflict)"
             else " (unknown-payload site disagrees)");
          List.iter (fun (p, f, s) ->
            Printf.eprintf "    %-8s payload=%-24s %s\n" f p s) es
        end
      end
    ) _repr_audit;
    Printf.eprintf "[repr-audit] %d type(s) flagged\n%!" !flagged
  end

(* ── Reduction-check helper ───────────────────────────────────────────── *)

(* emit_reduction_check moved here (Wave 3 Task 6, chunk 2): a pure
   ctx-primitive (no dependency on emit_expr/emit_case/anything else split
   out of llvm_emit.ml) needed by BOTH [emit_fn] (stays in llvm_emit.ml) and
   [emit_mutual_tco_group] (moves to Llvm_tco) — same criterion as the
   [alloca_name]/[repr_audit_record]/[llvm_ret_ty] moves above: a real
   non-llvm_emit.ml consumer now exists. Re-exported bare in llvm_emit.ml,
   which still calls it unqualified from emit_fn. *)

(** Emit an inline preemption check at the current position in [ctx.buf].
    Tests [@march_preempt_request] (set by the SIGUSR1 preemption handler
    once per quantum) and, when set, calls [@march_yield_from_compiled()]
    (which clears the request, refills the budget, and yields).
    Leaves the IR positioned at the start of a fresh basic block so the
    caller can continue emitting the function body. *)
let emit_reduction_check ctx =
  (* In REPL mode, skip the check entirely: the REPL is single-threaded, so
     the scheduler yield is a no-op, and skipping keeps the ORC JIT from
     having to resolve the scheduler globals at all. *)
  if not ctx.repl then begin
  let yield_blk = fresh_block ctx "sched_yield" in
  let cont_blk  = fresh_block ctx "sched_cont"  in
  let red       = fresh ctx "red" in
  let need_yield = fresh ctx "need_yield" in
  (* A single load of a PLAIN global, then a predictable not-taken branch.
     This used to load/decrement/store the _Thread_local march_tls_reductions
     instead, which is not a plain load on either supported platform: on
     Darwin/arm64 a TLS symbol access compiles to `adrp; ldr; blr` — an
     indirect call into the TLV resolver — and on Linux/arm64 PIE it goes
     through a TLSDESC call.  A non-inlinable call on every function entry
     also forced a stack frame and register spills.  Measured on
     bench/fib.march (~330M calls): 0.63s -> 0.36s.  Keeping the hot path
     READ-ONLY also matters: a per-call store to a shared global would
     ping-pong its cache line across scheduler threads. *)
  (* VOLATILE is load-bearing, not decoration.  A plain load of a global that
     nothing in the loop writes is loop-invariant, so LLVM hoists it out of a
     TCO loop body entirely and the loop then never re-reads the flag —
     preemption silently stops working for exactly the tail-recursive loops
     that need it most.  (Caught by the starvation test: a CPU-bound TCO loop
     starved a sibling green thread on a single scheduler thread, while the
     old load/decrement/STORE sequence could not be hoisted and so kept
     working.)  Volatile matches the C declaration and forces a re-read on
     every iteration. *)
  emit ctx (Printf.sprintf "%s = load volatile i64, ptr @march_preempt_request" red);
  emit ctx (Printf.sprintf "%s = icmp ne i64 %s, 0" need_yield red);
  emit_term ctx
    (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
       need_yield yield_blk cont_blk);
  emit_label ctx yield_blk;
  emit ctx "call void @march_yield_from_compiled()";
  emit_term ctx (Printf.sprintf "br label %%%s" cont_blk);
  emit_label ctx cont_blk
  end
