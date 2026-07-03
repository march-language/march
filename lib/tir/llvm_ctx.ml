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
    / [mangle_extern] / [repl_slot_info] — so no re-export shim is needed for
    the moved names; [llvm_emit.ml] opens/qualifies through [Llvm_ctx.xxx] at
    its remaining call sites.

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
  (* Buffer for extra wrapper functions emitted at the end *)
  extra_fns : Buffer.t;
  (* Tracks which ADT structural equality functions have been generated.
     Registered before body generation to handle recursive types (e.g. List). *)
  emitted_eq_fns : (string, unit) Hashtbl.t;
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
}

let make_ctx ?(fast_math=false) ?(pmap_threshold=1024) ?(repl=false)
    ?(hot_reload=None) ?(hr_names=Hot_reload.Name_table.build [])
    ?(type_defs=[]) () = {
  buf      = Buffer.create 4096;
  preamble = Buffer.create 1024;
  ctr      = 0; blk = 0; str_ctr = 0;
  ctor_info = Hashtbl.create 64;
  top_fns   = Hashtbl.create 64;
  top_fn_ret_ty = Hashtbl.create 64;
  top_fn_nparams = Hashtbl.create 64;
  zero_arg_fns  = Hashtbl.create 16;
  field_map = Hashtbl.create 16;
  ret_ty   = Tir.TUnit;
  fast_math;
  pmap_threshold;
  type_defs;
  var_slot    = Hashtbl.create 32;
  local_names = Hashtbl.create 32;
  poly_ctors  = Hashtbl.create 64;
  type_params = Hashtbl.create 16;
  emitted_wraps = Hashtbl.create 8;
  extra_fns = Buffer.create 1024;
  emitted_eq_fns = Hashtbl.create 16;
  extern_map = Hashtbl.create 8;
  blocking_externs = Hashtbl.create 4;
  raises_externs = Hashtbl.create 4;
  unknown_decls = Hashtbl.create 8;
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
  | Tir.TCon _  -> "ptr"
  | Tir.TTuple _ -> "ptr"
  | Tir.TRecord _ -> "ptr"
  | Tir.TFn _   -> "ptr"
  | Tir.TPtr _  -> "ptr"
  | Tir.TVar _  -> "ptr"   (* pre-mono fallback *)

(** LLVM type string for a function *parameter*, augmented with alias-analysis
    attributes for pointer types.
    - [nonnull]: March allocators call exit(1) on OOM, so heap pointers are
      never null; this lets LLVM elide null checks in alias analysis.
    - [dereferenceable(16)]: every March heap object has at least a 16-byte
      header (rc:i64 + tag:i32 + pad:i32), so the pointer can always be
      safely dereferenced for 16 bytes.
    EXCEPTION: niche-encoded Option-shaped types can carry None=0 (null), so
    [nonnull] and [dereferenceable] must be suppressed for them. *)
let llvm_param_ty ?(type_defs : Tir.type_def list = []) (ty : Tir.ty) : string =
  match ty with
  | Tir.TCon ("Atom", []) -> "i64"
  | Tir.TCon (name, _) when Repr.is_niche_shaped type_defs name -> "ptr"
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
  emit ctx (Printf.sprintf "%s = shl i64 %s, 1" shifted i64v);
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

(** Coerce value [v] from [from_ty] to [to_ty] if they differ.
    Returns the (possibly new) value string. *)
let coerce ctx from_ty v to_ty =
  if from_ty = to_ty then v
  else match (from_ty, to_ty) with
  | ("ptr", "double") ->
    (* ptr → i64 → double (LLVM can't ptrtoint to double directly) *)
    let i = fresh ctx "cv" in
    let r = fresh ctx "cv" in
    emit ctx (Printf.sprintf "%s = ptrtoint ptr %s to i64" i v);
    emit ctx (Printf.sprintf "%s = bitcast i64 %s to double" r i);
    r
  | ("double", "ptr") ->
    (* double → i64 → ptr *)
    let i = fresh ctx "cv" in
    let r = fresh ctx "cv" in
    emit ctx (Printf.sprintf "%s = bitcast double %s to i64" i v);
    emit ctx (Printf.sprintf "%s = inttoptr i64 %s to ptr" r i);
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
