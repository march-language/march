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
  mutable tco_loop_label : string;
  mutable tco_param_info : (string * string * string) list;
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
}

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

(* Set at emit_module entry; consulted by EAlloc and emit_case for Repr lookups. *)
let cur_type_defs : Tir.type_def list ref = ref []

let make_ctx ?(fast_math=false) ?(pmap_threshold=1024) ?(repl=false)
    ?(hot_reload=None) ?(hr_names=Hot_reload.Name_table.build []) () = {
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
  tco_loop_label = "";
  tco_param_info = [];
  mutual_tco_group      = [];
  mutual_tco_tag_slot   = "";
  mutual_tco_loop_label = "";
  mutual_tco_fn_params  = [];
  mutual_tco_fn_tags    = [];
  repl;
  shape_meta = true;
  rec_shape_globals = Hashtbl.create 16;
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

(* ── Type mapping ────────────────────────────────────────────────────── *)

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

let llvm_ret_ty : Tir.ty -> string = function
  | Tir.TUnit -> "void"
  | t -> llvm_ty t

(* For a `raises` extern declared `: Result(T, E)`, the C binding returns the
   bare Ok payload of type T (not a march_value Result).  This is T. *)
let ok_payload_ty : Tir.ty -> Tir.ty = function
  | Tir.TCon ("Result", [t_ok; _]) -> t_ok
  | t -> t

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
    Void wrappers keep the `void` ABI (no value to carry). *)
let is_apply_fn (name : string) : bool =
  let marker = "$apply$" in
  let nl = String.length name and ml = String.length marker in
  let rec scan i =
    i + ml <= nl && (String.sub name i ml = marker || scan (i + 1))
  in
  nl >= ml && scan 0

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

(** Allocation size in bytes for [n] fields. *)
let alloc_size n = 16 + n * 8

(* ── Known builtins ──────────────────────────────────────────────────── *)

(** True for operator/function names that are builtin — not heap values.
    RC operations on these should be no-ops. *)
let is_builtin_fn name =
  List.mem name ["+"; "-"; "*"; "/"; "%";
                 "+."; "-."; "*."; "/.";
                 "=="; "!="; "<"; "<="; ">"; ">=";
                 "++"; "string_concat"; "string_eq";
                 "string_length"; "string_byte_length"; "string_is_empty"; "string_to_int"; "string_join";
                 "println"; "print"; "print_stderr";
                 "int_to_string"; "float_to_string"; "bool_to_string";
                 "kill"; "is_alive"; "receive"; "send"; "spawn"; "actor_get_int";
                 "actor_call"; "actor_reply"; "actor_cast";
                 "task_spawn"; "task_await"; "task_await_unwrap";
                 "task_yield"; "task_spawn_steal"; "task_reductions";
                 "pmap_threshold";
                 "get_work_pool";
                 (* Float builtins *)
                 "float_abs"; "float_ceil"; "float_floor"; "float_round";
                 "float_truncate"; "int_to_float";
                 (* Math builtins *)
                 "math_sin"; "math_cos"; "math_tan";
                 "math_asin"; "math_acos"; "math_atan"; "math_atan2";
                 "math_sinh"; "math_cosh"; "math_tanh";
                 "math_sqrt"; "math_cbrt";
                 "math_exp"; "math_exp2";
                 "math_log"; "math_log2"; "math_log10"; "math_pow";
                 (* Char builtins *)
                 "char_from_int"; "char_to_int"; "char_is_digit";
                 "byte_to_char"; "char_is_alphanumeric"; "char_is_whitespace";
                 (* Float/Int conversion builtins *)
                 "float_to_int";
                 (* Extended string builtins *)
                 "string_chars"; "string_from_chars";
                 "string_contains"; "string_starts_with"; "string_ends_with";
                 "string_slice"; "string_split"; "string_split_first";
                 "string_replace"; "string_replace_all";
                 "string_to_lowercase"; "string_to_uppercase";
                 "string_trim"; "string_trim_start"; "string_trim_end";
                 "string_repeat"; "string_reverse";
                 "string_pad_left"; "string_pad_right";
                 "string_grapheme_count"; "string_index_of"; "string_last_index_of";
                 "string_to_float";
                 (* List builtins *)
                 "list_append"; "list_concat";
                 (* File/Dir builtins *)
                 "file_exists"; "dir_exists";
                 "file_open"; "file_close"; "file_read"; "file_read_line"; "file_read_chunk";
                 "file_write"; "file_append"; "file_delete"; "file_copy"; "file_rename"; "file_stat";
                 "dir_mkdir"; "dir_mkdir_p"; "dir_rmdir"; "dir_rm_rf"; "dir_list"; "dir_list_full";
                 (* Process builtins *)
                 "process_argv";
                 "process_env"; "process_set_env"; "process_cwd"; "process_exit";
                 "process_pid"; "process_spawn_sync"; "process_spawn_lines";
                 "process_spawn_async"; "process_read_line"; "process_write"; "process_kill_proc"; "process_wait_proc";
                 (* TCP/network builtins *)
                 "tcp_listen"; "tcp_accept";
                 "tcp_connect"; "tcp_close"; "tcp_peer_addr"; "tcp_recv_exact";
                 "tcp_recv_all"; "tcp_recv_chunk"; "tcp_recv_http_headers";
                 "tcp_recv_chunked_frame";
                 (* TLS builtins *)
                 "tls_client_ctx"; "tls_server_ctx"; "tls_connect"; "tls_accept";
                 "tls_read"; "tls_write"; "tls_close"; "tls_ctx_free";
                 "tls_negotiated_alpn"; "tls_peer_cn";
                 (* TypedArray builtins *)
                 "typed_array_create"; "typed_array_from_list"; "typed_array_to_list";
                 "typed_array_length"; "typed_array_get"; "typed_array_set";
                 "typed_array_map"; "typed_array_filter"; "typed_array_fold";
                 (* NativeIntArr builtins — flat i64 arrays for vectorizable loops *)
                 "native_int_arr_make"; "native_int_arr_length"; "native_int_arr_get";
                 "native_int_arr_set"; "native_int_arr_sum"; "native_int_arr_map";
                 "native_int_arr_from_list"; "native_int_arr_to_list";
                 "native_int_arr_filter_mask";
                 (* NativeFloatArr builtins — flat double arrays for vectorizable loops *)
                 "native_float_arr_make"; "native_float_arr_length"; "native_float_arr_get";
                 "native_float_arr_set"; "native_float_arr_sum"; "native_float_arr_map";
                 "native_float_arr_from_list"; "native_float_arr_to_list";
                 "native_float_arr_filter_mask";
                 (* Time builtins *)
                 "unix_time";
                 (* HTTP builtins *)
                 "http_serialize_request"; "http_parse_response";
                 (* CSV builtins *)
                 "csv_open"; "csv_next_row"; "csv_close";
                 (* Resource ownership *)
                 "own";
                 (* Capability builtins *)
                 "cap_narrow";
                 (* Monitor/supervision builtins *)
                 "demonitor"; "monitor"; "mailbox_size";
                 "run_until_idle"; "register_resource"; "get_cap";
                 "send_checked"; "pid_of_int"; "get_actor_field";
                 "link"; "unlink"; "register_supervisor";
                 (* Generic to_string *)
                 "to_string";
                 (* Bitwise integer builtins *)
                 "int_and"; "int_or"; "int_xor"; "int_not"; "int_shl"; "int_shr"; "int_popcount";
                 (* Vault (key-value store) builtins *)
                 "vault_new"; "vault_whereis"; "vault_set"; "vault_set_ttl";
                 "vault_put_new"; "vault_incr"; "vault_push_capped";
                 "vault_get"; "vault_drop"; "vault_update"; "vault_size"; "vault_keys";
                 "vault_ns_set"; "vault_ns_get"; "vault_ns_drop";
                 (* IOList builtins *)
                 "iolist_hash_fnv1a";
                 (* HTTP server builtins *)
                 "http_server_spawn_n"; "http_server_wait";
                 (* Crypto / hash builtins — see mangle_extern for C name mapping *)
                 "md5";
                 "hmac_sha256"; "stdlib_hmac_sha256"; "hmac_sha256_bytes"; "pbkdf2_sha256";
                 "sha256"; "sha512";
                 "base64_encode"; "base64_decode";
                 "random_bytes";
                 "stdlib_sha256"; "stdlib_sha512";
                 "stdlib_base64_encode"; "stdlib_base64_decode";
                 "stdlib_random_bytes";
                 (* System introspection builtins *)
                 "sys_uptime_ms"; "sys_heap_bytes"; "sys_word_size";
                 "sys_minor_gcs"; "sys_major_gcs";
                 "sys_actor_count"; "sys_cpu_count";
                 "sys_os"; "sys_arch";
                 "march_version";
                 (* UUID / identity builtins *)
                 "uuid_v4";
                 (* Panic/todo/unreachable internal builtins *)
                 "panic_"; "todo_"; "unreachable_";
                 (* IO read builtins *)
                 "io_read_line"; "read_line";
                 (* Logger builtins *)
                 "logger_set_level"; "logger_get_level";
                 "logger_add_context"; "logger_clear_context";
                 "logger_get_context"; "logger_write"]

let atom_is_builtin (atom : Tir.atom) =
  match atom with
  | Tir.AVar v -> is_builtin_fn v.Tir.v_name
  | _ -> false

(** True if [name] refers to a provably-terminating call site that does not
    need a reduction check: either a March builtin operator or a C-runtime
    function injected by lower_module (identified by the "march_" prefix, e.g.
    march_compare_int, march_hash_int). *)
let is_leaf_callee (name : string) : bool =
  is_builtin_fn name ||
  (String.length name >= 6 && String.sub name 0 6 = "march_")

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

(** TIR return type for known builtin/extern functions, overriding type info. *)
let builtin_ret_ty : string -> Tir.ty option = function
  | "panic"                       -> Some Tir.TUnit
  | "panic_" | "todo_" | "unreachable_" -> Some (Tir.TPtr Tir.TUnit)  (* polymorphic `a` → ptr *)
  | "println" | "print" | "print_stderr" -> Some Tir.TUnit
  | "io_read_line" | "read_line"         -> Some Tir.TString
  (* Logger builtins *)
  | "logger_set_level"     -> Some Tir.TUnit
  | "logger_get_level"     -> Some Tir.TInt
  | "logger_add_context"   -> Some Tir.TUnit
  | "logger_clear_context" -> Some Tir.TUnit
  | "logger_get_context"   -> Some (Tir.TCon ("List", [Tir.TTuple [Tir.TString; Tir.TString]]))
  | "logger_write"         -> Some Tir.TUnit
  (* Record introspection builtins *)
  | "record_keys"      -> Some (Tir.TCon ("List", [Tir.TString]))
  | "record_values"    -> Some (Tir.TCon ("List", [Tir.TVar "_"]))
  | "record_entries"   -> Some (Tir.TCon ("List", [Tir.TTuple [Tir.TString; Tir.TVar "_"]]))
  | "record_get"       -> Some (Tir.TCon ("Option", [Tir.TVar "_"]))
  | "record_put"       -> Some (Tir.TVar "_")
  | "record_from_list" -> Some (Tir.TVar "_")
  | "record_has_key"   -> Some Tir.TBool
  | "int_to_string"               -> Some Tir.TString
  | "float_to_string"             -> Some Tir.TString
  | "bool_to_string"              -> Some Tir.TString
  | "string_concat" | "++"        -> Some Tir.TString
  | "string_eq"                   -> Some Tir.TInt
  | "string_length"               -> Some Tir.TInt
  | "string_byte_length"          -> Some Tir.TInt
  | "string_is_empty"             -> Some Tir.TBool
  | "string_to_int"               -> Some (Tir.TCon ("Option", [Tir.TInt]))
  | "string_join"                 -> Some Tir.TString
  | "kill"                        -> Some Tir.TUnit
  | "is_alive"                    -> Some Tir.TBool
  | "send" | "send_linear"        -> Some (Tir.TCon ("Option", [Tir.TUnit]))
  | "spawn"                        -> Some (Tir.TPtr Tir.TUnit)
  | "receive"                      -> Some (Tir.TPtr Tir.TUnit)
  | "actor_get_int"               -> Some Tir.TInt
  | "actor_call"                  -> Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TVar "e"]))
  | "actor_reply"                 -> Some Tir.TUnit
  | "actor_cast"                  -> Some (Tir.TCon ("Option", [Tir.TUnit]))
  (* Char builtins *)
  | "char_from_int" | "byte_to_char" -> Some Tir.TString
  | "char_to_int"                 -> Some Tir.TInt
  | "char_is_digit" | "char_is_alphanumeric" | "char_is_whitespace" -> Some Tir.TBool
  (* Float/Int conversion builtins *)
  | "float_to_int"                -> Some Tir.TInt
  (* Float builtins *)
  | "float_abs"                   -> Some Tir.TFloat
  | "float_ceil"                  -> Some Tir.TInt
  | "float_floor"                 -> Some Tir.TInt
  | "float_round"                 -> Some Tir.TInt
  | "float_truncate"              -> Some Tir.TInt
  | "int_to_float"                -> Some Tir.TFloat
  (* Math builtins — all double→double *)
  | "math_sin" | "math_cos" | "math_tan"
  | "math_asin" | "math_acos" | "math_atan"
  | "math_sinh" | "math_cosh" | "math_tanh"
  | "math_sqrt" | "math_cbrt"
  | "math_exp" | "math_exp2"
  | "math_log" | "math_log2" | "math_log10" -> Some Tir.TFloat
  | "math_atan2" | "math_pow"    -> Some Tir.TFloat
  (* Extended string builtins *)
  | "string_chars"                -> Some (Tir.TCon ("List", [Tir.TString]))
  | "string_from_chars"           -> Some Tir.TString
  | "string_contains"             -> Some Tir.TBool
  | "string_starts_with"          -> Some Tir.TBool
  | "string_ends_with"            -> Some Tir.TBool
  | "string_slice"                -> Some Tir.TString
  | "string_split"                -> Some (Tir.TCon ("List", [Tir.TString]))
  | "string_split_first"          -> Some (Tir.TCon ("Option", [Tir.TTuple [Tir.TString; Tir.TString]]))
  | "string_replace"              -> Some Tir.TString
  | "string_replace_all"          -> Some Tir.TString
  | "string_to_lowercase"         -> Some Tir.TString
  | "string_to_uppercase"         -> Some Tir.TString
  | "string_trim"                 -> Some Tir.TString
  | "string_trim_start"           -> Some Tir.TString
  | "string_trim_end"             -> Some Tir.TString
  | "string_repeat"               -> Some Tir.TString
  | "string_reverse"              -> Some Tir.TString
  | "string_pad_left"             -> Some Tir.TString
  | "string_pad_right"            -> Some Tir.TString
  | "string_grapheme_count"       -> Some Tir.TInt
  | "string_index_of"             -> Some (Tir.TCon ("Option", [Tir.TInt]))
  | "string_last_index_of"        -> Some (Tir.TCon ("Option", [Tir.TInt]))
  | "string_to_float"             -> Some (Tir.TCon ("Option", [Tir.TFloat]))
  (* List builtins *)
  | "list_append"                 -> Some (Tir.TCon ("List", [Tir.TVar "a"]))
  | "list_concat"                 -> Some (Tir.TCon ("List", [Tir.TVar "a"]))
  (* File/Dir builtins *)
  | "file_exists"                 -> Some Tir.TBool
  | "dir_exists"                  -> Some Tir.TBool
  | "file_open"                   -> Some (Tir.TCon ("Result", [Tir.TInt; Tir.TString]))
  | "file_close"                  -> Some (Tir.TPtr Tir.TUnit)
  | "file_read"                   -> Some (Tir.TCon ("Result", [Tir.TString; Tir.TString]))
  | "file_read_line"              -> Some (Tir.TCon ("Option", [Tir.TString]))
  | "file_read_chunk"             -> Some (Tir.TCon ("Option", [Tir.TString]))
  | "file_write"                  -> Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]))
  | "file_append"                 -> Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]))
  | "file_delete"                 -> Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]))
  | "file_copy"                   -> Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]))
  | "file_rename"                 -> Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]))
  | "file_stat"                   -> Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TString]))
  | "dir_mkdir"                   -> Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]))
  | "dir_mkdir_p"                 -> Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]))
  | "dir_rmdir"                   -> Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]))
  | "dir_rm_rf"                   -> Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]))
  | "dir_list"                    -> Some (Tir.TCon ("Result", [Tir.TCon ("List", [Tir.TString]); Tir.TString]))
  | "dir_list_full"               -> Some (Tir.TCon ("Result", [Tir.TCon ("List", [Tir.TString]); Tir.TString]))
  | "process_argv"                -> Some (Tir.TCon ("List", [Tir.TString]))
  | "process_env"                 -> Some (Tir.TCon ("Option", [Tir.TString]))
  | "process_set_env"             -> Some Tir.TUnit
  | "process_cwd"                 -> Some Tir.TString
  | "process_exit"                -> Some Tir.TUnit
  | "process_pid"                 -> Some Tir.TInt
  | "process_spawn_sync"          -> Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TString]))
  | "process_spawn_lines"         -> Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TString]))
  | "process_spawn_async"         -> Some (Tir.TCon ("Result", [Tir.TCon ("LiveProcess", []); Tir.TString]))
  | "process_read_line"           -> Some (Tir.TCon ("Option", [Tir.TString]))
  | "process_write"               -> Some Tir.TUnit
  | "process_kill_proc"           -> Some Tir.TUnit
  | "process_wait_proc"           -> Some Tir.TInt
  (* TCP/network builtins *)
  | "tcp_listen" | "tcp_accept"  -> Some (Tir.TCon ("Result", [Tir.TInt; Tir.TString]))
  | "tcp_connect"                 -> Some (Tir.TCon ("Result", [Tir.TInt; Tir.TString]))
  | "tcp_send_all"                -> Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]))
  | "tcp_close"                   -> Some Tir.TUnit
  | "tcp_peer_addr"               -> Some Tir.TString
  | "tcp_recv_exact"              -> Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]))
  | "tcp_recv_all" | "tcp_recv_chunk" | "tcp_recv_http_headers"
  | "tcp_recv_http" | "tcp_recv_chunked_frame"
                                  -> Some (Tir.TCon ("Result", [Tir.TString; Tir.TString]))
  (* HTTP/WS builtins *)
  | "http_parse_request"          -> Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TString]))
  | "http_serialize_response"     -> Some Tir.TString
  | "http_server_listen"          -> Some Tir.TInt
  | "ws_handshake"                -> Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TString]))
  | "ws_recv"                     -> Some (Tir.TCon ("Result", [Tir.TString; Tir.TString]))
  | "ws_send"                     -> Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]))
  | "ws_select"                   -> Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TString]))
  (* TLS builtins *)
  | "tls_client_ctx" | "tls_server_ctx" | "tls_connect" | "tls_accept" -> Some (Tir.TCon ("Result", [Tir.TInt; Tir.TString]))
  | "tls_read" -> Some (Tir.TCon ("Result", [Tir.TString; Tir.TString]))
  | "tls_write" | "tls_close" | "tls_ctx_free" -> Some Tir.TUnit
  | "tls_negotiated_alpn" | "tls_peer_cn" -> Some (Tir.TCon ("Option", [Tir.TString]))
  (* TypedArray builtins *)
  | "typed_array_create" | "typed_array_from_list" | "typed_array_map" | "typed_array_filter" -> Some (Tir.TVar "a")
  | "typed_array_to_list" -> Some (Tir.TCon ("List", [Tir.TVar "a"]))
  | "typed_array_length"  -> Some Tir.TInt
  | "typed_array_get"     -> Some (Tir.TVar "a")
  | "typed_array_set"     -> Some (Tir.TVar "a")
  | "typed_array_fold"    -> Some (Tir.TVar "a")
  (* NativeIntArr builtins — flat i64 arrays for vectorizable loops *)
  | "native_int_arr_make"      -> Some (Tir.TCon ("NativeIntArr", []))
  | "native_int_arr_length"    -> Some Tir.TInt
  | "native_int_arr_get"       -> Some Tir.TInt
  | "native_int_arr_set"       -> Some (Tir.TCon ("NativeIntArr", []))
  | "native_int_arr_sum"       -> Some Tir.TInt
  | "native_int_arr_map"       -> Some (Tir.TCon ("NativeIntArr", []))
  | "native_int_arr_from_list"   -> Some (Tir.TCon ("NativeIntArr", []))
  | "native_int_arr_to_list"     -> Some (Tir.TCon ("List", [Tir.TInt]))
  | "native_int_arr_filter_mask" -> Some (Tir.TCon ("NativeIntArr", []))
  (* NativeFloatArr builtins — flat double arrays for vectorizable loops *)
  | "native_float_arr_make"        -> Some (Tir.TCon ("NativeFloatArr", []))
  | "native_float_arr_length"      -> Some Tir.TInt
  | "native_float_arr_get"         -> Some Tir.TFloat
  | "native_float_arr_set"         -> Some (Tir.TCon ("NativeFloatArr", []))
  | "native_float_arr_sum"         -> Some Tir.TFloat
  | "native_float_arr_map"         -> Some (Tir.TCon ("NativeFloatArr", []))
  | "native_float_arr_from_list"   -> Some (Tir.TCon ("NativeFloatArr", []))
  | "native_float_arr_to_list"     -> Some (Tir.TCon ("List", [Tir.TFloat]))
  | "native_float_arr_filter_mask" -> Some (Tir.TCon ("NativeFloatArr", []))
  (* Time builtins *)
  | "unix_time" -> Some Tir.TFloat
  (* HTTP builtins *)
  | "http_serialize_request"      -> Some Tir.TString
  | "http_parse_response"         -> Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TString]))
  (* CSV builtins *)
  | "csv_open"                    -> Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TString]))
  | "csv_next_row"                -> Some (Tir.TCon ("Option", [Tir.TCon ("List", [Tir.TString])]))
  | "csv_close"                   -> Some (Tir.TPtr Tir.TUnit)
  (* Resource ownership *)
  | "own"                         -> Some Tir.TUnit
  (* Capability builtins *)
  | "cap_narrow"                  -> Some (Tir.TCon ("Cap", [Tir.TVar "a"]))
  (* Monitor/supervision builtins *)
  | "demonitor"                   -> Some Tir.TUnit
  | "monitor"                     -> Some Tir.TInt
  | "mailbox_size"                -> Some Tir.TInt
  | "run_until_idle"              -> Some Tir.TUnit
  | "register_resource"           -> Some Tir.TUnit
  | "get_cap"                     -> Some (Tir.TCon ("Option", [Tir.TCon ("Cap", [Tir.TVar "a"])]))
  | "send_checked"                -> Some Tir.TUnit
  | "pid_of_int"                  -> Some (Tir.TCon ("Pid", [Tir.TVar "a"]))
  | "get_actor_field"             -> Some (Tir.TCon ("Option", [Tir.TVar "a"]))
  (* Link / supervisor builtins *)
  | "link"                        -> Some Tir.TUnit
  | "unlink"                      -> Some Tir.TUnit
  | "register_supervisor"         -> Some Tir.TUnit
  (* Comparison/hash runtime builtins — return i64, not ptr *)
  | "march_compare_int" | "march_compare_float" | "march_compare_string" -> Some Tir.TInt
  | "march_hash_int" | "march_hash_float" | "march_hash_string" | "march_hash_bool" -> Some Tir.TInt
  (* Generic to_string *)
  | "to_string"                   -> Some Tir.TString
  (* Vault (key-value store) builtins *)
  | "vault_new"          -> Some (Tir.TPtr Tir.TUnit)
  | "vault_whereis"      -> Some (Tir.TCon ("Option", [Tir.TPtr Tir.TUnit]))
  | "vault_set"          -> Some Tir.TUnit
  | "vault_set_ttl"      -> Some Tir.TUnit
  | "vault_put_new"      -> Some Tir.TBool
  | "vault_incr"         -> Some Tir.TInt
  | "vault_push_capped"  -> Some Tir.TUnit
  | "vault_get"          -> Some (Tir.TCon ("Option", [Tir.TPtr Tir.TUnit]))
  | "vault_drop"         -> Some Tir.TUnit
  | "vault_update"       -> Some Tir.TUnit
  | "vault_size"         -> Some Tir.TInt
  | "vault_keys"         -> Some (Tir.TCon ("List", [Tir.TPtr Tir.TUnit]))
  | "vault_ns_set"       -> Some Tir.TUnit
  | "vault_ns_get"       -> Some (Tir.TCon ("Option", [Tir.TPtr Tir.TUnit]))
  | "vault_ns_drop"      -> Some Tir.TUnit
  (* Bitwise integer builtins *)
  | "int_and" | "int_or" | "int_xor"
  | "int_not" | "int_shl" | "int_shr"
  | "int_popcount"                -> Some Tir.TInt
  (* IOList builtins *)
  | "iolist_hash_fnv1a"           -> Some Tir.TString
  (* HTTP server builtins *)
  | "http_server_spawn_n"         -> Some Tir.TInt
  | "http_server_wait"            -> Some Tir.TUnit
  (* Crypto / hash builtins *)
  | "md5"                         -> Some Tir.TString
  | "hmac_sha256" | "stdlib_hmac_sha256"
  | "pbkdf2_sha256"           -> Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]))
  | "sha256" | "stdlib_sha256"
  | "sha512" | "stdlib_sha512" -> Some Tir.TString
  | "sha1_bytes"               -> Some (Tir.TCon ("Bytes", []))
  | "hmac_sha256_bytes"        -> Some (Tir.TCon ("Bytes", []))
  | "random_bytes" | "stdlib_random_bytes" -> Some (Tir.TCon ("Bytes", []))
  | "base64_encode" | "stdlib_base64_encode" -> Some Tir.TString
  | "base64_decode" | "stdlib_base64_decode"
                              -> Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]))
  (* Compression builtins — all return Result(Bytes, String) *)
  | "stdlib_gzip_encode"    | "stdlib_gzip_decode"
  | "stdlib_deflate_encode" | "stdlib_deflate_decode"
  | "stdlib_zstd_encode"    | "stdlib_zstd_decode"
  | "stdlib_brotli_encode"  | "stdlib_brotli_decode"
                              -> Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]))
  (* System introspection builtins *)
  | "sys_uptime_ms" | "sys_heap_bytes" | "sys_word_size"
  | "sys_minor_gcs" | "sys_major_gcs"
  | "sys_actor_count" | "sys_cpu_count" -> Some Tir.TInt
  | "sys_os" | "sys_arch" | "march_version" -> Some Tir.TString
  (* UUID / identity builtins *)
  | "uuid_v4" -> Some Tir.TString
  (* Session-typed channel builtins (binary) *)
  | "chan_new"    -> Some (Tir.TTuple [Tir.TCon ("Chan", []); Tir.TCon ("Chan", [])])
  | "chan_send"   -> Some (Tir.TCon ("Chan", []))
  | "chan_recv"   -> Some (Tir.TTuple [Tir.TPtr Tir.TUnit; Tir.TCon ("Chan", [])])
  | "chan_close"  -> Some Tir.TUnit
  | "chan_choose" -> Some (Tir.TCon ("Chan", []))
  | "chan_offer"  -> Some (Tir.TTuple [Tir.TPtr Tir.TUnit; Tir.TCon ("Chan", [])])
  (* Multi-party session type builtins *)
  | "mpst_new"   -> Some (Tir.TPtr Tir.TUnit)
  | "mpst_send"  -> Some (Tir.TCon ("Chan", []))
  | "mpst_recv"  -> Some (Tir.TTuple [Tir.TPtr Tir.TUnit; Tir.TCon ("Chan", [])])
  | "mpst_close" -> Some Tir.TUnit
  | _ -> None

(** Mangle a March builtin name to the C runtime function name. *)
let mangle_extern : string -> string = function
  | "panic"         -> "march_panic"
  (* Record introspection builtins.  record_put maps to the 3-arg variant
     (kind defaults to generic) for first-class / closure-wrapper call paths;
     the direct EApp path in emit_expr calls the 4-arg march_record_put with
     an explicit kind char instead. *)
  | "record_keys"      -> "march_record_keys"
  | "record_values"    -> "march_record_values"
  | "record_entries"   -> "march_record_entries"
  | "record_get"       -> "march_record_get"
  | "record_has_key"   -> "march_record_has_key"
  | "record_put"       -> "march_record_put3"
  | "record_from_list" -> "march_record_from_list"
  | "println"       -> "march_println"
  | "print"         -> "march_print"
  | "print_stderr"  -> "march_print_stderr"
  | "io_read_line" | "read_line" -> "march_io_read_line"
  | "int_to_string" -> "march_int_to_string"
  | "float_to_string" -> "march_float_to_string"
  | "bool_to_string"  -> "march_bool_to_string"
  | "string_concat" | "++" -> "march_string_concat"
  | "string_eq"          -> "march_string_eq"
  | "string_length"      -> "march_string_byte_length"
  | "string_byte_length" -> "march_string_byte_length"
  | "string_is_empty"    -> "march_string_is_empty"
  | "string_to_int"      -> "march_string_to_int"
  | "string_join"        -> "march_string_join"
  | "kill"               -> "march_kill"
  | "is_alive"      -> "march_is_alive"
  | "receive"       -> "march_sched_recv"
  | "send"          -> "march_send"
  | "send_linear"   -> "march_send_linear"
  | "spawn"         -> "march_spawn"
  | "actor_get_int" -> "march_actor_get_int"
  | "actor_call"    -> "march_actor_call"
  | "actor_reply"   -> "march_actor_reply"
  | "actor_cast"    -> "march_send"
  | "tcp_listen"              -> "march_tcp_listen"
  | "tcp_accept"              -> "march_tcp_accept"
  | "tcp_recv_exact"          -> "march_tcp_recv_exact"
  | "tcp_recv_http"           -> "march_tcp_recv_http"
  | "tcp_send_all"            -> "march_tcp_send_all"
  | "tcp_close"               -> "march_tcp_close"
  | "tcp_peer_addr"           -> "march_tcp_peer_addr"
  | "http_parse_request"      -> "march_http_parse_request"
  | "http_serialize_response" -> "march_http_serialize_response"
  | "http_server_listen"      -> "march_http_server_listen"
  | "http_server_spawn_n"     -> "march_http_server_spawn_n"
  | "http_server_wait"        -> "march_http_server_wait"
  | "ws_handshake"            -> "march_ws_handshake"
  | "ws_recv"                 -> "march_ws_recv"
  | "ws_send"                 -> "march_ws_send"
  | "ws_select"               -> "march_ws_select"
  (* Char builtins *)
  | "char_from_int"   -> "march_char_from_int"
  | "char_to_int"     -> "march_char_to_int"
  | "byte_to_char"    -> "march_char_from_int"   (* same semantics: int → single-char string *)
  | "char_is_alphanumeric" -> "march_char_is_alphanumeric"
  | "char_is_whitespace"   -> "march_char_is_whitespace"
  | "char_is_digit"   -> "march_char_is_digit"
  (* Float/Int conversion builtins *)
  | "float_to_int"    -> "march_float_to_int"
  (* Float builtins *)
  | "float_abs"       -> "march_float_abs"
  | "float_ceil"      -> "march_float_ceil"
  | "float_floor"     -> "march_float_floor"
  | "float_round"     -> "march_float_round"
  | "float_truncate"  -> "march_float_truncate"
  | "int_to_float"    -> "march_int_to_float"
  (* Math builtins *)
  | "math_sin"   -> "march_math_sin"
  | "math_cos"   -> "march_math_cos"
  | "math_tan"   -> "march_math_tan"
  | "math_asin"  -> "march_math_asin"
  | "math_acos"  -> "march_math_acos"
  | "math_atan"  -> "march_math_atan"
  | "math_atan2" -> "march_math_atan2"
  | "math_sinh"  -> "march_math_sinh"
  | "math_cosh"  -> "march_math_cosh"
  | "math_tanh"  -> "march_math_tanh"
  | "math_sqrt"  -> "march_math_sqrt"
  | "math_cbrt"  -> "march_math_cbrt"
  | "math_exp"   -> "march_math_exp"
  | "math_exp2"  -> "march_math_exp2"
  | "math_log"   -> "march_math_log"
  | "math_log2"  -> "march_math_log2"
  | "math_log10" -> "march_math_log10"
  | "math_pow"   -> "march_math_pow"
  (* Extended string builtins *)
  | "string_chars"         -> "march_string_chars"
  | "string_from_chars"    -> "march_string_from_chars"
  | "string_contains"      -> "march_string_contains"
  | "string_starts_with"   -> "march_string_starts_with"
  | "string_ends_with"     -> "march_string_ends_with"
  | "string_slice"         -> "march_string_slice"
  | "string_split"         -> "march_string_split"
  | "string_split_first"   -> "march_string_split_first"
  | "string_replace"       -> "march_string_replace"
  | "string_replace_all"   -> "march_string_replace_all"
  | "string_to_lowercase"  -> "march_string_to_lowercase"
  | "string_to_uppercase"  -> "march_string_to_uppercase"
  | "string_trim"          -> "march_string_trim"
  | "string_trim_start"    -> "march_string_trim_start"
  | "string_trim_end"      -> "march_string_trim_end"
  | "string_repeat"        -> "march_string_repeat"
  | "string_reverse"       -> "march_string_reverse"
  | "string_pad_left"      -> "march_string_pad_left"
  | "string_pad_right"     -> "march_string_pad_right"
  | "string_grapheme_count" -> "march_string_grapheme_count"
  | "string_index_of"      -> "march_string_index_of"
  | "string_last_index_of" -> "march_string_last_index_of"
  | "string_to_float"      -> "march_string_to_float"
  (* List builtins *)
  | "list_append"  -> "march_list_append"
  | "list_concat"  -> "march_list_concat"
  (* File/Dir builtins *)
  | "file_exists"       -> "march_file_exists"
  | "dir_exists"        -> "march_dir_exists"
  | "file_open"         -> "march_file_open"
  | "file_close"        -> "march_file_close"
  | "file_read"         -> "march_file_read"
  | "file_read_line"    -> "march_file_read_line"
  | "file_read_chunk"   -> "march_file_read_chunk"
  | "file_write"        -> "march_file_write"
  | "file_append"       -> "march_file_append"
  | "file_delete"       -> "march_file_delete"
  | "file_copy"         -> "march_file_copy"
  | "file_rename"       -> "march_file_rename"
  | "file_stat"         -> "march_file_stat"
  | "dir_mkdir"         -> "march_dir_mkdir"
  | "dir_mkdir_p"       -> "march_dir_mkdir_p"
  | "dir_rmdir"         -> "march_dir_rmdir"
  | "dir_rm_rf"         -> "march_dir_rm_rf"
  | "dir_list"          -> "march_dir_list"
  | "dir_list_full"     -> "march_dir_list_full"
  | "process_argv"      -> "march_process_argv"
  | "process_env"       -> "march_process_env"
  | "process_set_env"   -> "march_process_set_env"
  | "process_cwd"       -> "march_process_cwd"
  | "process_exit"      -> "march_process_exit"
  | "process_pid"       -> "march_process_pid"
  | "process_spawn_sync"   -> "march_process_spawn_sync"
  | "process_spawn_lines"  -> "march_process_spawn_lines"
  | "process_spawn_async"  -> "march_process_spawn_async"
  | "process_read_line"    -> "march_process_read_line"
  | "process_write"        -> "march_process_write"
  | "process_kill_proc"    -> "march_process_kill_proc"
  | "process_wait_proc"    -> "march_process_wait_proc"
  (* TCP/network builtins *)
  | "tcp_connect"       -> "march_tcp_connect"
  | "tcp_recv_all"      -> "march_tcp_recv_all"
  | "tcp_recv_chunk"    -> "march_tcp_recv_chunk"
  | "tcp_recv_http_headers" -> "march_tcp_recv_http_headers"
  | "tcp_recv_chunked_frame" -> "march_tcp_recv_chunked_frame"
  (* TLS builtins *)
  | "tls_client_ctx"    -> "march_tls_client_ctx"
  | "tls_server_ctx"    -> "march_tls_server_ctx"
  | "tls_connect"       -> "march_tls_connect"
  | "tls_accept"        -> "march_tls_accept"
  | "tls_read"          -> "march_tls_read"
  | "tls_write"         -> "march_tls_write"
  | "tls_close"         -> "march_tls_close"
  | "tls_ctx_free"      -> "march_tls_ctx_free"
  | "tls_negotiated_alpn" -> "march_tls_negotiated_alpn"
  | "tls_peer_cn"       -> "march_tls_peer_cn"
  (* TypedArray builtins *)
  | "typed_array_create"    -> "march_typed_array_create"
  | "typed_array_from_list" -> "march_typed_array_from_list"
  | "typed_array_to_list"   -> "march_typed_array_to_list"
  | "typed_array_length"    -> "march_typed_array_length"
  | "typed_array_get"       -> "march_typed_array_get"
  | "typed_array_set"       -> "march_typed_array_set"
  | "typed_array_map"       -> "march_typed_array_map"
  | "typed_array_filter"    -> "march_typed_array_filter"
  | "typed_array_fold"      -> "march_typed_array_fold"
  (* Time builtins *)
  | "unix_time"         -> "march_unix_time"
  (* HTTP builtins *)
  | "http_serialize_request" -> "march_http_serialize_request"
  | "http_parse_response"    -> "march_http_parse_response"
  (* CSV builtins *)
  | "csv_open"          -> "march_csv_open"
  | "csv_next_row"      -> "march_csv_next_row"
  | "csv_close"         -> "march_csv_close"
  (* Resource ownership *)
  | "own"               -> "march_own"
  (* Capability builtins *)
  | "cap_narrow"         -> "march_cap_narrow"
  (* Monitor/supervision builtins *)
  | "demonitor"          -> "march_demonitor"
  | "monitor"            -> "march_monitor"
  | "mailbox_size"       -> "march_mailbox_size"
  | "run_until_idle"     -> "march_run_until_idle"
  | "register_resource"  -> "march_register_resource"
  | "get_cap"            -> "march_get_cap"
  | "send_checked"         -> "march_send_checked"
  | "pid_of_int"           -> "march_pid_of_int"
  | "get_actor_field"      -> "march_get_actor_field"
  (* Link / supervisor builtins *)
  | "link"                 -> "march_link"
  | "unlink"               -> "march_unlink"
  | "register_supervisor"  -> "march_register_supervisor"
  (* Generic to_string *)
  | "to_string"          -> "march_value_to_string"
  (* Vault (key-value store) builtins *)
  | "vault_new"          -> "march_vault_new"
  | "vault_whereis"      -> "march_vault_whereis"
  | "vault_set"          -> "march_vault_set"
  | "vault_set_ttl"      -> "march_vault_set_ttl"
  | "vault_put_new"      -> "march_vault_put_new"
  | "vault_incr"         -> "march_vault_incr"
  | "vault_push_capped"  -> "march_vault_push_capped"
  | "vault_get"          -> "march_vault_get"
  | "vault_drop"         -> "march_vault_drop"
  | "vault_update"       -> "march_vault_update"
  | "vault_size"         -> "march_vault_size"
  | "vault_keys"         -> "march_vault_keys"
  | "vault_ns_set"       -> "march_vault_ns_set"
  | "vault_ns_get"       -> "march_vault_ns_get"
  | "vault_ns_drop"      -> "march_vault_ns_drop"
  (* IOList builtins *)
  | "iolist_hash_fnv1a"  -> "march_iolist_hash_fnv1a"
  | "main"          -> "march_main"   (* March main → march_main in LLVM *)
  (* Crypto / hash builtins *)
  | "md5"                  -> "march_md5"
  | "hmac_sha256" | "stdlib_hmac_sha256" -> "march_hmac_sha256"
  | "hmac_sha256_bytes"    -> "march_hmac_sha256_bytes"
  | "pbkdf2_sha256"        -> "march_pbkdf2_sha256"
  | "sha256" | "stdlib_sha256"              -> "march_sha256"
  | "sha512" | "stdlib_sha512"              -> "march_sha512"
  | "sha1_bytes"                             -> "march_sha1_bytes"
  | "base64_encode" | "stdlib_base64_encode" -> "march_base64_encode"
  | "base64_decode" | "stdlib_base64_decode" -> "march_base64_decode"
  | "random_bytes"  | "stdlib_random_bytes"  -> "march_random_bytes"
  (* Compression builtins *)
  | "stdlib_gzip_encode"    -> "march_gzip_encode"
  | "stdlib_gzip_decode"    -> "march_gzip_decode"
  | "stdlib_deflate_encode" -> "march_deflate_encode"
  | "stdlib_deflate_decode" -> "march_deflate_decode"
  | "stdlib_zstd_encode"    -> "march_zstd_encode"
  | "stdlib_zstd_decode"    -> "march_zstd_decode"
  | "stdlib_brotli_encode"  -> "march_brotli_encode"
  | "stdlib_brotli_decode"  -> "march_brotli_decode"
  (* System introspection builtins *)
  | "sys_uptime_ms"    -> "march_sys_uptime_ms"
  | "sys_heap_bytes"   -> "march_sys_heap_bytes"
  | "sys_word_size"    -> "march_sys_word_size"
  | "sys_minor_gcs"    -> "march_sys_minor_gcs"
  | "sys_major_gcs"    -> "march_sys_major_gcs"
  | "sys_actor_count"  -> "march_sys_actor_count"
  | "sys_cpu_count"    -> "march_sys_cpu_count"
  | "sys_os"           -> "march_sys_os"
  | "sys_arch"         -> "march_sys_arch"
  | "march_version"    -> "march_get_version"
  (* Session-typed channel builtins *)
  | "chan_new"         -> "march_chan_new"
  | "chan_send"        -> "march_chan_send"
  | "chan_recv"        -> "march_chan_recv"
  | "chan_close"       -> "march_chan_close"
  | "chan_choose"      -> "march_chan_choose"
  | "chan_offer"       -> "march_chan_offer"
  (* Multi-party session type builtins *)
  | "mpst_new"        -> "march_mpst_new"
  | "mpst_send"       -> "march_mpst_send"
  | "mpst_recv"       -> "march_mpst_recv"
  | "mpst_close"      -> "march_mpst_close"
  (* UUID / identity builtins *)
  | "uuid_v4"          -> "march_uuid_v4"
  (* Panic/todo/unreachable internal primitives *)
  | "panic_"       -> "march_panic_ext"
  | "todo_"        -> "march_todo_ext"
  | "unreachable_" -> "march_panic_ext"
  (* Logger builtins *)
  | "logger_set_level"    -> "march_logger_set_level"
  | "logger_get_level"    -> "march_logger_get_level"
  | "logger_add_context"  -> "march_logger_add_context"
  | "logger_clear_context" -> "march_logger_clear_context"
  | "logger_get_context"  -> "march_logger_get_context"
  | "logger_write"        -> "march_logger_write"
  | other           -> other

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

(* ── Type coercion ───────────────────────────────────────────────────── *)

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
    let b = fresh ctx "cv" in
    let s = fresh ctx "cv" in
    let o = fresh ctx "cv" in
    let r = fresh ctx "cv" in
    emit ctx (Printf.sprintf "%s = ptrtoint ptr %s to i64" i v);
    emit ctx (Printf.sprintf "%s = and i64 %s, 1" b i);
    emit ctx (Printf.sprintf "%s = icmp ne i64 %s, 0" o b);
    emit ctx (Printf.sprintf "%s = ashr i64 %s, 1" s i);
    emit ctx (Printf.sprintf "%s = select i1 %s, i64 %s, i64 %s" r o s i);
    r
  | ("i64", "ptr") ->
    (* Tag an integer for polymorphic storage: (n << 1) | 1.
       Low bit 1 marks this as an immediate; heap pointers are always even. *)
    let s = fresh ctx "cv" in
    let t = fresh ctx "cv" in
    let r = fresh ctx "cv" in
    emit ctx (Printf.sprintf "%s = shl i64 %s, 1" s v);
    emit ctx (Printf.sprintf "%s = or i64 %s, 1" t s);
    emit ctx (Printf.sprintf "%s = inttoptr i64 %s to ptr" r t);
    r
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

(* ── Alloca slot uniquification ──────────────────────────────────────── *)

(** Return a unique alloca slot name for TIR variable [base] and update
    var_slot so subsequent loads of [base] use this slot.
    First use returns [base] unchanged; shadowing gives [base_1], [base_2], ... *)
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
  | Tir.AVar v when (let n = v.Tir.v_name in
                     String.length n >= 7 && String.sub n 0 7 = "march_") ->
    (* C-runtime extern used as a first-class value (e.g. march_compare_int passed
       to a HOF).  These are declared in emit_preamble — never in var_slot or
       compiled_fns — so the alloca-bridge path would generate an invalid
       "%march_*.addr" load.  Emit the global address directly instead. *)
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
    let resolved = match Hashtbl.find_opt ctx.unqualified_fns v.Tir.v_name with
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

(* ── GEP helpers ─────────────────────────────────────────────────────── *)

let emit_load_tag ctx obj_val =
  let tp = fresh ctx "tgp" in
  let tv = fresh ctx "tag" in
  emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 8"  tp obj_val);
  emit ctx (Printf.sprintf "%s = load i32, ptr %s, align 4" tv tp);
  tv

let emit_store_tag ctx obj_val tag_int =
  let tp = fresh ctx "tgp" in
  emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 8" tp obj_val);
  emit ctx (Printf.sprintf "store i32 %d, ptr %s, align 4" tag_int tp)

let emit_store_field ctx obj_val i ty_str val_str =
  let offset = 16 + i * 8 in
  let fp = fresh ctx "fp" in
  emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 %d" fp obj_val offset);
  emit ctx (Printf.sprintf "store %s %s, ptr %s, align 8" ty_str val_str fp)

let emit_load_field ctx obj_val i ty_str =
  let offset = 16 + i * 8 in
  let fp = fresh ctx "fp" in
  let fv = fresh ctx "fv" in
  emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 %d" fp obj_val offset);
  emit ctx (Printf.sprintf "%s = load %s, ptr %s, align 8" fv ty_str fp);
  fv

(* ── Alloc helpers ───────────────────────────────────────────────────── *)

let emit_heap_alloc ctx tag_int n_fields =
  let ptr = fresh ctx "hp" in
  emit ctx (Printf.sprintf "%s = call ptr @march_alloc(i64 %d)" ptr (alloc_size n_fields));
  emit_store_tag ctx ptr tag_int;
  ptr

let emit_stack_alloc ctx n_fields =
  let ptr = fresh ctx "sp" in
  emit ctx (Printf.sprintf "%s = alloca [%d x i8], align 8" ptr (alloc_size n_fields));
  (* zero the header *)
  emit ctx (Printf.sprintf "store i64 0, ptr %s, align 8" ptr);
  (* zero the tag+pad word too: alloca memory is garbage, and the pad word
     (offset 12) is read as the record shape id by the native runtime *)
  let hw = fresh ctx "tgp" in
  emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 8" hw ptr);
  emit ctx (Printf.sprintf "store i64 0, ptr %s, align 8" hw);
  ptr

(* ── Constructor lookup ──────────────────────────────────────────────── *)

let ctor_entry ctx name n_args_fallback =
  match Hashtbl.find_opt ctx.ctor_info name with
  | Some e -> e
  | None   ->
    (* Exact key not found: try to find a type-qualified key ending in ".<name>".
       This handles pattern matches on constructors whose scrutinee type is TVar "_"
       (unknown at codegen time) — e.g. nested match arms where the inner value's
       type was not propagated through the pattern-matrix compiler. *)
    let suffix = "." ^ name in
    let suffix_len = String.length suffix in
    (* Collect all entries ending with ".<ctor>" and pick the best match.
       "Best" = arity matches n_args_fallback; otherwise fall back to first found.
       This handles the case where two unrelated types share a constructor name
       (e.g. Heap.HLeaf with 0 fields vs HEntry.HLeaf with 3 fields): the
       call-site arity breaks the tie instead of hashtable iteration order. *)
    let candidates = Hashtbl.fold (fun k v acc ->
        let klen = String.length k in
        if klen > suffix_len &&
           String.equal (String.sub k (klen - suffix_len) suffix_len) suffix
        then v :: acc
        else acc
      ) ctx.ctor_info [] in
    let found = match candidates with
      | [] -> None
      | [single] -> Some single
      | many ->
        (match List.find_opt (fun e -> List.length e.ce_fields = n_args_fallback) many with
         | Some exact -> Some exact
         | None -> Some (List.hd many))
    in
    (match found with
     | Some e -> e
     | None ->
       { ce_tag = 0; ce_fields = List.init n_args_fallback (fun _ -> Tir.TVar "_") })

(** Apply a type-variable substitution to a TIR type. *)
let rec apply_ty_subst (subst : (string * Tir.ty) list) : Tir.ty -> Tir.ty = function
  | Tir.TVar n ->
    (match List.assoc_opt n subst with Some t -> t | None -> Tir.TVar n)
  | Tir.TCon (n, args) -> Tir.TCon (n, List.map (apply_ty_subst subst) args)
  | Tir.TFn (ps, r)    -> Tir.TFn (List.map (apply_ty_subst subst) ps, apply_ty_subst subst r)
  | Tir.TTuple ts      -> Tir.TTuple (List.map (apply_ty_subst subst) ts)
  | Tir.TPtr t         -> Tir.TPtr (apply_ty_subst subst t)
  | t -> t

(** Return concrete field types for [ctor_name] given the scrutinee's TIR type.
    When the scrutinee is a concrete [TCon(name, ty_args)] (e.g. List(Int)),
    substitutes type variable parameters with the concrete arguments so that
    scalar fields (Int, Bool, …) get their real LLVM type instead of "ptr".
    Falls back to [ctor_entry] (which may contain TVar placeholders) otherwise. *)
let resolve_ctor_fields ctx scrut_tir_ty ctor_name n_args =
  match scrut_tir_ty with
  | Tir.TTuple ts -> ts   (* tuple patterns ($TupleN): the element types ARE the field types *)
  | Tir.TCon (type_name, ty_args) ->
    (match Hashtbl.find_opt ctx.type_params type_name,
           Hashtbl.find_opt ctx.poly_ctors (type_name, ctor_name) with
     | Some param_names, Some generic_fields
       when List.length param_names = List.length ty_args ->
       let subst = List.combine param_names ty_args in
       List.map (apply_ty_subst subst) generic_fields
     | _ ->
       (ctor_entry ctx ctor_name n_args).ce_fields)
  | _ ->
    (ctor_entry ctx ctor_name n_args).ce_fields

(** Look up the sorted field list for a record type.
    For TCon types, tries the name as-is then progressively strips leading
    module-path segments ("Conduit.Config" → "Config") so that qualified type
    names produced by the typechecker resolve against the bare-named entries
    stored in field_map by the lowering pass.
    Fields are returned in alphabetical order to match the record construction
    order used by lower.ml (which sorts fields at allocation sites). *)
let get_record_fields ctx (ty : Tir.ty) : (string * Tir.ty) list =
  match ty with
  | Tir.TRecord fields -> fields   (* already sorted alphabetically at construction *)
  | Tir.TCon (name, _) ->
    (* Field definitions are stored under the qualified type name (e.g.
       "Conduit.Config").  Fall back to progressively stripping module
       prefixes for any types that were registered under a bare name. *)
    let rec find n =
      match Hashtbl.find_opt ctx.field_map n with
      | Some fields ->
        (* Sort alphabetically to match the construction order used in lower.ml *)
        List.sort (fun (a, _) (b, _) -> String.compare a b) fields
      | None ->
        (match String.index_opt n '.' with
         | None -> []
         | Some i -> find (String.sub n (i + 1) (String.length n - i - 1)))
    in
    find name
  | _ -> []

(** Find the index and type of [field_name] in the record described by [ty]. *)
let field_index_for ctx (ty : Tir.ty) (field_name : string) : int * Tir.ty =
  let fields = get_record_fields ctx ty in
  let rec find i = function
    | [] -> (0, Tir.TVar "_")   (* fallback: field not found *)
    | (n, ft) :: _ when n = field_name -> (i, ft)
    | _ :: rest -> find (i + 1) rest
  in
  find 0 fields

(* ── Record shape metadata (native record introspection) ─────────────── *)

(** Static TIR type of an atom (used for shape kinds and builtin kind hints). *)
let atom_tir_ty : Tir.atom -> Tir.ty = function
  | Tir.AVar v -> v.Tir.v_ty
  | Tir.ALit (March_ast.Ast.LitInt _)    -> Tir.TInt
  | Tir.ALit (March_ast.Ast.LitFloat _)  -> Tir.TFloat
  | Tir.ALit (March_ast.Ast.LitBool _)   -> Tir.TBool
  | Tir.ALit (March_ast.Ast.LitString _) -> Tir.TString
  | Tir.ALit (March_ast.Ast.LitAtom _)   -> Tir.TCon ("Atom", [])
  | Tir.ADefRef _ -> Tir.TVar "_"

(** Field kind char for the runtime shape descriptor — describes the natural
    in-slot representation (must match runtime/march_extras.c):
    'i' raw i64 scalar, 'f' raw double bits, 'p' heap pointer, 'g' unknown. *)
let shape_kind_char : Tir.ty -> char = function
  | Tir.TInt | Tir.TBool | Tir.TUnit | Tir.TCon ("Atom", []) -> 'i'
  | Tir.TFloat -> 'f'
  | Tir.TVar _ -> 'g'
  | _ -> 'p'

(** Canonical shape descriptor "name:k;name:k;..." with fields sorted by name
    — the same order record slots are laid out in. *)
let shape_desc (fields : (string * Tir.ty) list) : string =
  let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) fields in
  String.concat "" (List.map (fun (n, t) ->
    Printf.sprintf "%s:%c;" n (shape_kind_char t)) sorted)

(** Emit (once per shape) the descriptor string constant and the i32 id-cache
    global; returns (desc_global, cache_global). *)
let ensure_shape_globals ctx (desc : string) : string * string =
  match Hashtbl.find_opt ctx.rec_shape_globals desc with
  | Some pair -> pair
  | None ->
    let dg = intern_string ctx desc in
    ctx.str_ctr <- ctx.str_ctr + 1;
    let cg = Printf.sprintf "@.recshape%d" ctx.str_ctr in
    Buffer.add_string ctx.preamble
      (Printf.sprintf "%s = internal global i32 0\n" cg);
    Hashtbl.replace ctx.rec_shape_globals desc (dg, cg);
    (dg, cg)

(** Stamp the interned shape id of [fields] into record cell [ptr]'s header
    pad word.  No-op on WASM targets (no native runtime registry). *)
let emit_set_shape ctx ptr (fields : (string * Tir.ty) list) =
  if ctx.shape_meta then begin
    let (dg, cg) = ensure_shape_globals ctx (shape_desc fields) in
    emit ctx (Printf.sprintf
      "call void @march_record_set_shape(ptr %s, ptr %s, ptr %s)" ptr dg cg)
  end

(* ── ADT structural equality generation ─────────────────────────────── *)

(** Mangle a TIR type to a valid LLVM identifier fragment for equality function names. *)
let rec mangle_ty_for_eq : Tir.ty -> string = function
  | Tir.TInt    -> "Int"
  | Tir.TFloat  -> "Float"
  | Tir.TBool   -> "Bool"
  | Tir.TString -> "String"
  | Tir.TUnit   -> "Unit"
  | Tir.TCon (n, [])   -> String.concat "_" (String.split_on_char '.' n)
  | Tir.TCon (n, args) ->
    let n' = String.concat "_" (String.split_on_char '.' n) in
    n' ^ "_" ^ String.concat "_" (List.map mangle_ty_for_eq args)
  | Tir.TVar _   -> "Any"
  | Tir.TTuple ts -> "Tup_" ^ String.concat "_x_" (List.map mangle_ty_for_eq ts)
  | _            -> "Ptr"

(** LLVM load type for an ADT field: i64 for scalar types, double for float, ptr for heap. *)
let field_load_llty : Tir.ty -> string = function
  | Tir.TInt | Tir.TBool | Tir.TUnit -> "i64"
  | Tir.TFloat -> "double"
  | _ -> "ptr"

(** Ensure a structural equality function for [ty] exists in [ctx.extra_fns].
    Returns Some llvm_fn_name (without @) or None if generation is not possible.
    Registers the name before generating the body so recursive types (e.g. List)
    terminate: the recursive field simply emits a call to the function being built. *)
let rec ensure_adt_eq_fn (ctx : ctx) (ty : Tir.ty) : string option =
  match ty with
  | Tir.TCon ("Atom", []) -> None  (* Atoms stored as i64, not heap ptrs *)
  | Tir.TCon (type_name, ty_args) ->
    let fn_name = "__march_eq_" ^ mangle_ty_for_eq ty in
    if Hashtbl.mem ctx.emitted_eq_fns fn_name then Some fn_name
    else begin
      (* Resolve [type_name] against ctor_info's type-qualified keys
         ("TypePath.CtorName").  TDVariant names from imported modules are
         module-qualified ("Ast.Expr") while the TCon at a use site may carry
         the short name ("Expr") — or vice versa.  Collect every type path
         matching exactly or by dot-suffix.  When several types share the
         short name (e.g. "SortDir" -> Ast.SortDir and DataFrame.SortDir) we
         can still generate a correct comparison if their per-tag field
         layouts agree on common tags: tags are contiguous from 0, so the
         candidate with the most constructors covers every tag any operand
         can carry.  Genuinely conflicting layouts (e.g. "Query" ->
         Ast.Query(QueryFields) vs Depot.Query.Query's 8-field DQuery)
         return None and the caller falls back.
         NOTE: memoization in emitted_eq_fns must only happen once we commit
         to generating a body — registering before the ctor lookup made later
         requests return Some for a function that was never defined. *)
      let split_type_path key =
        match String.rindex_opt key '.' with
        | None -> None
        | Some i -> Some (String.sub key 0 i)
      in
      let ends_with_seg ~seg s =
        let ls = String.length s and lx = String.length seg in
        ls > lx + 1 && String.sub s (ls - lx - 1) (lx + 1) = "." ^ seg
      in
      let candidate_paths = Hashtbl.fold (fun key _ acc ->
          match split_type_path key with
          | Some tp when tp = type_name || ends_with_seg ~seg:type_name tp ->
            if List.mem tp acc then acc else tp :: acc
          | _ -> acc
        ) ctx.ctor_info []
      in
      let ctors_of tp =
        let prefix = tp ^ "." in
        Hashtbl.fold (fun key entry acc ->
          if String.length key > String.length prefix &&
             String.sub key 0 (String.length prefix) = prefix &&
             not (String.contains
                    (String.sub key (String.length prefix)
                       (String.length key - String.length prefix)) '.')
          then
            let cn = String.sub key (String.length prefix)
                       (String.length key - String.length prefix) in
            (entry.ce_tag, cn, entry.ce_fields) :: acc
          else acc
        ) ctx.ctor_info []
      in
      let resolved =
        match candidate_paths with
        | [] -> None
        | [tp] -> Some (tp, ctors_of tp)
        | tps ->
          (* Multiple candidates: keep the largest ctor set when every other
             candidate's per-tag field layout matches it on common tags. *)
          let sorted = List.sort (fun (_, a) (_, b) ->
              compare (List.length b) (List.length a))
              (List.map (fun tp -> (tp, ctors_of tp)) tps) in
          (match sorted with
           | [] -> None
           | ((_, big_ctors) as biggest) :: rest ->
             let layout_of tag ctors =
               Option.map (fun (_, _, flds) -> List.map field_load_llty flds)
                 (List.find_opt (fun (t, _, _) -> t = tag) ctors)
             in
             let compatible = List.for_all (fun (_, cs) ->
                 List.for_all (fun (tag, _, flds) ->
                     layout_of tag big_ctors
                     = Some (List.map field_load_llty flds)
                   ) cs
               ) rest
             in
             if compatible then Some biggest else None)
      in
      match resolved with
      | None -> None
      | Some (_, []) -> None
      | Some (resolved_name, ctors) ->
      Hashtbl.add ctx.emitted_eq_fns fn_name ();
      let subst =
        match Hashtbl.find_opt ctx.type_params resolved_name with
        | Some ps when List.length ps = List.length ty_args -> List.combine ps ty_args
        | _ ->
          (match Hashtbl.find_opt ctx.type_params type_name with
           | Some ps when List.length ps = List.length ty_args -> List.combine ps ty_args
           | _ -> [])
      in
      begin
        let ctors = List.sort (fun (a,_,_) (b,_,_) -> compare a b) ctors in
        let buf = Buffer.create 512 in
        let ctr = ref 0 in let blk = ref 0 in
        let frsh pfx = incr ctr; Printf.sprintf "%%%s%d" pfx !ctr in
        let flbl pfx = incr blk; Printf.sprintf "%s%d" pfx !blk in
        let e ln  = Buffer.add_string buf ("  " ^ ln ^ "\n") in
        let lbl l = Buffer.add_string buf (l ^ ":\n") in
        let lbl_eq     = flbl "is_eq" in
        let lbl_not_eq = flbl "not_eq" in
        let lbl_same   = flbl "same_tag" in
        Buffer.add_string buf (Printf.sprintf "\ndefine i64 @%s(ptr %%a, ptr %%b) {\n" fn_name);
        Buffer.add_string buf "entry:\n";
        let tgpa = frsh "tgpa" in let tgpb = frsh "tgpb" in
        let taga = frsh "taga" in let tagb = frsh "tagb" in
        e (Printf.sprintf "%s = getelementptr i8, ptr %%a, i64 8" tgpa);
        e (Printf.sprintf "%s = load i32, ptr %s, align 4" taga tgpa);
        e (Printf.sprintf "%s = getelementptr i8, ptr %%b, i64 8" tgpb);
        e (Printf.sprintf "%s = load i32, ptr %s, align 4" tagb tgpb);
        let tc = frsh "tc" in
        e (Printf.sprintf "%s = icmp eq i32 %s, %s" tc taga tagb);
        e (Printf.sprintf "br i1 %s, label %%%s, label %%%s" tc lbl_same lbl_not_eq);
        lbl lbl_same;
        let tag_lbls = List.map (fun (tag, cn, _) ->
          let l = flbl (Printf.sprintf "t%d_%s" tag
                    (String.concat "_" (String.split_on_char '.' cn))) in
          (tag, l)
        ) ctors in
        let sw_cases = List.map2 (fun (tag, tl) _ ->
          Printf.sprintf "i32 %d, label %%%s" tag tl
        ) tag_lbls ctors in
        e (Printf.sprintf "switch i32 %s, label %%%s [\n    %s\n  ]"
             taga lbl_not_eq (String.concat "\n    " sw_cases));
        (* Per-constructor field comparison blocks *)
        List.iter2 (fun (_, tl) (_, _, raw_flds) ->
          lbl tl;
          let flds = List.map (apply_ty_subst subst) raw_flds in
          let nf = List.length flds in
          if nf = 0 then
            e (Printf.sprintf "br label %%%s" lbl_eq)
          else begin
            (* Continuation labels for fields 1..nf-1 (field 0 runs in tag block). *)
            let cont_lbls = Array.init nf (fun i ->
              if i = 0 then tl else flbl (Printf.sprintf "f%d" i)
            ) in
            List.iteri (fun fi fty ->
              if fi > 0 then lbl cont_lbls.(fi);
              let off = 16 + fi * 8 in
              let llt = field_load_llty fty in
              let fgpa = frsh "fgpa" in let fgpb = frsh "fgpb" in
              let fva  = frsh "fva"  in let fvb  = frsh "fvb"  in
              e (Printf.sprintf "%s = getelementptr i8, ptr %%a, i64 %d" fgpa off);
              e (Printf.sprintf "%s = load %s, ptr %s, align 8" fva llt fgpa);
              e (Printf.sprintf "%s = getelementptr i8, ptr %%b, i64 %d" fgpb off);
              e (Printf.sprintf "%s = load %s, ptr %s, align 8" fvb llt fgpb);
              let ok = frsh "ok" in
              (match fty with
               | Tir.TInt | Tir.TBool | Tir.TUnit ->
                 let c = frsh "c" in
                 e (Printf.sprintf "%s = icmp eq i64 %s, %s" c fva fvb);
                 e (Printf.sprintf "%s = zext i1 %s to i64" ok c)
               | Tir.TFloat ->
                 let c = frsh "c" in
                 e (Printf.sprintf "%s = fcmp oeq double %s, %s" c fva fvb);
                 e (Printf.sprintf "%s = zext i1 %s to i64" ok c)
               | Tir.TString ->
                 e (Printf.sprintf "%s = call i64 @march_string_eq(ptr %s, ptr %s)" ok fva fvb)
               | Tir.TCon _ | Tir.TTuple _ | Tir.TRecord _ ->
                 (match ensure_adt_eq_fn ctx fty with
                  | Some fen ->
                    e (Printf.sprintf "%s = call i64 @%s(ptr %s, ptr %s)" ok fen fva fvb)
                  | None ->
                    let pa = frsh "pa" in let pb = frsh "pb" in
                    e (Printf.sprintf "%s = ptrtoint ptr %s to i64" pa fva);
                    e (Printf.sprintf "%s = ptrtoint ptr %s to i64" pb fvb);
                    let c = frsh "c" in
                    e (Printf.sprintf "%s = icmp eq i64 %s, %s" c pa pb);
                    e (Printf.sprintf "%s = zext i1 %s to i64" ok c))
               | _ ->
                 (* Generic (TVar) field: the static type gives no comparison
                    strategy, so dispatch on the runtime shape via march_poly_eq
                    (immediates by value, heap strings by content).  A plain
                    pointer compare here broke structural equality for generic
                    containers of strings, e.g. List(a) where a is a String at
                    runtime — `["10"] == ["10"]` from distinct allocations. *)
                 e (Printf.sprintf "%s = call i64 @march_poly_eq(ptr %s, ptr %s)" ok fva fvb));
              let oki = frsh "oki" in
              e (Printf.sprintf "%s = icmp ne i64 %s, 0" oki ok);
              let nxt = if fi = nf - 1 then lbl_eq else cont_lbls.(fi + 1) in
              e (Printf.sprintf "br i1 %s, label %%%s, label %%%s" oki nxt lbl_not_eq)
            ) flds
          end
        ) tag_lbls ctors;
        lbl lbl_eq;     e "ret i64 1";
        lbl lbl_not_eq; e "ret i64 0";
        Buffer.add_string buf "}\n";
        Buffer.add_buffer ctx.extra_fns buf;
        Some fn_name
      end
    end
  (* Tuples and records: single-layout heap cells (tag 0) — compare fields
     element-wise with short-circuiting.  Without this, == on tuple/record
     operands fell back to pointer comparison, so e.g.
     List.member(record_entries(r), ("age", 30)) was always false natively. *)
  | Tir.TTuple _ | Tir.TRecord _ ->
    let flds = (match ty with
      | Tir.TTuple tys -> tys
      | Tir.TRecord fields -> List.map snd fields   (* sorted by name = slot order *)
      | _ -> []) in
    let fn_name = "__march_eq_" ^ mangle_ty_for_eq ty in
    if Hashtbl.mem ctx.emitted_eq_fns fn_name then Some fn_name
    else begin
      Hashtbl.add ctx.emitted_eq_fns fn_name ();
      let buf = Buffer.create 256 in
      let ctr = ref 0 in let blk = ref 0 in
      let frsh pfx = incr ctr; Printf.sprintf "%%%s%d" pfx !ctr in
      let flbl pfx = incr blk; Printf.sprintf "%s%d" pfx !blk in
      let e ln  = Buffer.add_string buf ("  " ^ ln ^ "\n") in
      let lbl l = Buffer.add_string buf (l ^ ":\n") in
      let lbl_eq     = flbl "is_eq" in
      let lbl_not_eq = flbl "not_eq" in
      Buffer.add_string buf (Printf.sprintf "\ndefine i64 @%s(ptr %%a, ptr %%b) {\n" fn_name);
      Buffer.add_string buf "entry:\n";
      let nf = List.length flds in
      if nf = 0 then
        e (Printf.sprintf "br label %%%s" lbl_eq)
      else begin
        let cont_lbls = Array.init nf (fun i ->
          if i = 0 then "" else flbl (Printf.sprintf "f%d" i)) in
        List.iteri (fun fi fty ->
          if fi > 0 then lbl cont_lbls.(fi);
          let off = 16 + fi * 8 in
          let llt = field_load_llty fty in
          let fgpa = frsh "fgpa" in let fgpb = frsh "fgpb" in
          let fva  = frsh "fva"  in let fvb  = frsh "fvb"  in
          e (Printf.sprintf "%s = getelementptr i8, ptr %%a, i64 %d" fgpa off);
          e (Printf.sprintf "%s = load %s, ptr %s, align 8" fva llt fgpa);
          e (Printf.sprintf "%s = getelementptr i8, ptr %%b, i64 %d" fgpb off);
          e (Printf.sprintf "%s = load %s, ptr %s, align 8" fvb llt fgpb);
          let ok = frsh "ok" in
          (match fty with
           | Tir.TInt | Tir.TBool | Tir.TUnit | Tir.TCon ("Atom", []) ->
             let c = frsh "c" in
             e (Printf.sprintf "%s = icmp eq i64 %s, %s" c fva fvb);
             e (Printf.sprintf "%s = zext i1 %s to i64" ok c)
           | Tir.TFloat ->
             let c = frsh "c" in
             e (Printf.sprintf "%s = fcmp oeq double %s, %s" c fva fvb);
             e (Printf.sprintf "%s = zext i1 %s to i64" ok c)
           | Tir.TString ->
             e (Printf.sprintf "%s = call i64 @march_string_eq(ptr %s, ptr %s)" ok fva fvb)
           | Tir.TCon _ | Tir.TTuple _ | Tir.TRecord _ ->
             (match ensure_adt_eq_fn ctx fty with
              | Some fen ->
                e (Printf.sprintf "%s = call i64 @%s(ptr %s, ptr %s)" ok fen fva fvb)
              | None ->
                let pa = frsh "pa" in let pb = frsh "pb" in
                e (Printf.sprintf "%s = ptrtoint ptr %s to i64" pa fva);
                e (Printf.sprintf "%s = ptrtoint ptr %s to i64" pb fvb);
                let c = frsh "c" in
                e (Printf.sprintf "%s = icmp eq i64 %s, %s" c pa pb);
                e (Printf.sprintf "%s = zext i1 %s to i64" ok c))
           | _ ->
             let pa = frsh "pa" in let pb = frsh "pb" in
             e (Printf.sprintf "%s = ptrtoint ptr %s to i64" pa fva);
             e (Printf.sprintf "%s = ptrtoint ptr %s to i64" pb fvb);
             let c = frsh "c" in
             e (Printf.sprintf "%s = icmp eq i64 %s, %s" c pa pb);
             e (Printf.sprintf "%s = zext i1 %s to i64" ok c));
          let oki = frsh "oki" in
          e (Printf.sprintf "%s = icmp ne i64 %s, 0" oki ok);
          let nxt = if fi = nf - 1 then lbl_eq else cont_lbls.(fi + 1) in
          e (Printf.sprintf "br i1 %s, label %%%s, label %%%s" oki nxt lbl_not_eq)
        ) flds
      end;
      lbl lbl_eq;     e "ret i64 1";
      lbl lbl_not_eq; e "ret i64 0";
      Buffer.add_string buf "}\n";
      Buffer.add_buffer ctx.extra_fns buf;
      Some fn_name
    end
  | _ -> None

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
            | Tir.EField (_, n) ->
              String.length n > 3 && String.sub n 0 3 = "$fv"
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

  (* ── Let binding ───────────────────────────────────────────────────── *)
  | Tir.ELet (v, rhs, body) ->
    let (rhs_ty, rhs_val) = emit_expr ctx rhs in
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
    let result1 = emit_expr ctx e1 in
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
    (* Untag: conditional ashr-1 recovers original scalar or heap-ptr value. *)
    let r_i64 = coerce ctx "ptr" tv "i64" in
    let r = if inner_ty = "ptr" then begin
      let p = fresh ctx "r" in
      emit ctx (Printf.sprintf "%s = inttoptr i64 %s to ptr" p r_i64);
      p
    end else r_i64 in
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
    (* Pass the value in NATURAL representation as a ptr-sized word: raw i64
       for scalars (NOT low-bit tagged), raw bits for floats, ptr as-is. *)
    let vp = (match vt with
      | "i64" ->
        let t = fresh ctx "cv" in
        emit ctx (Printf.sprintf "%s = inttoptr i64 %s to ptr" t vv); t
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
    (* 4. Branch back to the shared loop header. *)
    emit_term ctx (Printf.sprintf "br label %%%s" ctx.mutual_tco_loop_label);
    (* 5. Open a dead continuation block for syntactic validity. *)
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
    when (match ctx.tco_fn_name with
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
    (* 3. Loop back — this is the terminator for the current basic block. *)
    emit_term ctx (Printf.sprintf "br label %%%s" ctx.tco_loop_label);
    (* 4. Open a dead block so that any instructions the caller emits after
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
       for "Crypto.base64_encode").  Look up the qualified name first. *)
    let resolved_name = match Hashtbl.find_opt ctx.unqualified_fns f.Tir.v_name with
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
    let is_runtime_builtin =
      String.length fname >= 6 && String.sub fname 0 6 = "march_"
    in
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
        | Some i -> i | None -> 0 in
      let vslot = fresh ctx "hrver" in
      emit ctx (Printf.sprintf "%s = alloca i32" vslot);
      let fp = fresh ctx "hrfp" in
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
      && (let rn = match Hashtbl.find_opt ctx.unqualified_fns f.Tir.v_name with
            | Some q -> q | None -> f.Tir.v_name in
          Hashtbl.mem ctx.raises_externs rn) ->
    let arg_pairs = List.map (fun a -> emit_atom ctx a) args in
    let rn = match Hashtbl.find_opt ctx.unqualified_fns f.Tir.v_name with
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
    let is_runtime_builtin =
      String.length fname >= 6 && String.sub fname 0 6 = "march_"
    in
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
  | Tir.EAlloc (Tir.TCon (ctor, _), args) ->
    (* EAlloc ctor key is "TypeName.CtorName"; repr_of_ty needs the TypeName. *)
    let alloc_type_name = match String.rindex_opt ctor '.' with
      | Some i -> String.sub ctor 0 i
      | None -> ctor
    in
    (match Repr.repr_of_ty !cur_type_defs (Tir.TCon (alloc_type_name, [])) with
     | Repr.Newtype payload ->
       (* Newtype: no allocation. Emit the single payload atom directly. *)
       if List.length args <> 1 then
         failwith (Printf.sprintf
           "LLVM emit: newtype constructor %s expects 1 arg, got %d \
            (arity mismatch — malformed TIR)"
           ctor (List.length args));
       let (v_ty, v_val) = emit_atom ctx (List.hd args) in
       if Repr.payload_needs_tag !cur_type_defs payload then begin
         (* Scalar payload: tag (v<<1)|1 so it's odd → IS_HEAP_PTR = false *)
         let i64v = coerce ctx v_ty v_val "i64" in
         let shifted = fresh ctx "nt_sh" in
         emit ctx (Printf.sprintf "%s = shl i64 %s, 1" shifted i64v);
         let tagged = fresh ctx "nt_tag" in
         emit ctx (Printf.sprintf "%s = or i64 %s, 1" tagged shifted);
         let as_ptr = fresh ctx "nt_ptr" in
         emit ctx (Printf.sprintf "%s = inttoptr i64 %s to ptr" as_ptr tagged);
         ("ptr", as_ptr)
       end else
         (* Pointer payload: pass through raw *)
         ("ptr", coerce ctx v_ty v_val "ptr")
     | _ when Repr.is_niche_shaped !cur_type_defs alloc_type_name ->
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
         if not (Repr.niche_payload_ok !cur_type_defs arg_tir_ty) then None
         else begin
           let (v_ty, v_val) = emit_atom ctx arg in
           if Repr.payload_needs_tag !cur_type_defs arg_tir_ty then begin
             let i64v = coerce ctx v_ty v_val "i64" in
             let shifted = fresh ctx "niche_sh" in
             emit ctx (Printf.sprintf "%s = shl i64 %s, 1" shifted i64v);
             let tagged_v = fresh ctx "niche_tag" in
             emit ctx (Printf.sprintf "%s = or i64 %s, 1" tagged_v shifted);
             let as_ptr = fresh ctx "niche_ptr" in
             emit ctx (Printf.sprintf "%s = inttoptr i64 %s to ptr" as_ptr tagged_v);
             Some ("ptr", as_ptr)
           end else
             Some ("ptr", coerce ctx v_ty v_val "ptr")
         end
       in
       (match args with
        | [] ->
          (* Nullary ctor (None) = raw 0 *)
          let z = fresh ctx "niche_none" in
          emit ctx (Printf.sprintf "%s = inttoptr i64 0 to ptr" z);
          ("ptr", z)
        | [arg] ->
          (match emit_niche_payload arg with
           | Some result -> result
           | None ->
             (* Payload not niche-safe (Float/Unit/Bool) — fall through to boxed *)
             let entry = ctor_entry ctx ctor (List.length args) in
             let ptr = emit_heap_alloc ctx entry.ce_tag (List.length args) in
             let field_ty = match List.nth_opt entry.ce_fields 0 with
               | Some t -> llvm_ty t | None -> "ptr" in
             let (v_ty, v_val) = emit_atom ctx arg in
             emit_store_field ctx ptr 0 field_ty (coerce ctx v_ty v_val field_ty);
             ("ptr", ptr))
        | _ ->
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
    (match Repr.repr_of_ty !cur_type_defs (Tir.TCon (reuse_type_name, [])) with
     | Repr.Newtype payload ->
       let (_, rv) = emit_atom ctx reuse_atom in
       emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" rv);
       let (v_ty, v_val) = emit_atom ctx (List.hd args) in
       if Repr.payload_needs_tag !cur_type_defs payload then begin
         let i64v = coerce ctx v_ty v_val "i64" in
         let shifted = fresh ctx "nt_sh" in
         emit ctx (Printf.sprintf "%s = shl i64 %s, 1" shifted i64v);
         let tagged = fresh ctx "nt_tag" in
         emit ctx (Printf.sprintf "%s = or i64 %s, 1" tagged shifted);
         let as_ptr = fresh ctx "nt_ptr" in
         emit ctx (Printf.sprintf "%s = inttoptr i64 %s to ptr" as_ptr tagged);
         ("ptr", as_ptr)
       end else
         ("ptr", coerce ctx v_ty v_val "ptr")
     | _ when Repr.is_niche_shaped !cur_type_defs reuse_type_name ->
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
         if not (Repr.niche_payload_ok !cur_type_defs arg_tir_ty) then None
         else begin
           let (v_ty, v_val) = emit_atom ctx arg in
           if Repr.payload_needs_tag !cur_type_defs arg_tir_ty then begin
             let i64v = coerce ctx v_ty v_val "i64" in
             let shifted = fresh ctx "niche_sh" in
             emit ctx (Printf.sprintf "%s = shl i64 %s, 1" shifted i64v);
             let tagged_v = fresh ctx "niche_tag" in
             emit ctx (Printf.sprintf "%s = or i64 %s, 1" tagged_v shifted);
             let as_ptr = fresh ctx "niche_ptr" in
             emit ctx (Printf.sprintf "%s = inttoptr i64 %s to ptr" as_ptr tagged_v);
             Some ("ptr", as_ptr)
           end else
             Some ("ptr", coerce ctx v_ty v_val "ptr")
         end
       in
       (match args with
        | [] ->
          let z = fresh ctx "niche_none" in
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
    ("ptr", result))

  | Tir.EReuse (reuse_atom, reuse_ty, args) ->
    (* Non-TCon reuse: same conditional logic without ctor-specific fields *)
    let (_, rv) = emit_atom ctx reuse_atom in
    let arg_vals = List.map (fun atom ->
      let (ty, v) = emit_atom ctx atom in
      (* Records keep NATURAL slot repr (shape descriptors record the kind);
         tuples / erased cells use the UNIFORM convention (scalars tagged),
         matching ETuple and the ptr-typed destructure fallbacks. *)
      (match reuse_ty with
       | Tir.TRecord _ -> (ty, v)
       | _ -> ("ptr", coerce ctx ty v "ptr"))
    ) args in
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

  (* ── RC ops ────────────────────────────────────────────────────────── *)
  (* Skip RC ops on builtins AND on top-level function references.
     Function addresses live in the code segment, not the heap, so calling
     march_incrc_local/decrc_local/free on them would corrupt memory or crash.
     EIncRC/EDecRC use non-atomic local RC (fast path, single-owner values).
     EAtomicIncRC/EAtomicDecRC use C11-atomic RC for actor-shared values. *)
  | Tir.EIncRC atom
    when atom_is_builtin atom ||
         (match atom with Tir.AVar v -> Hashtbl.mem ctx.top_fns v.Tir.v_name | _ -> false) ->
    ("i64", "0")
  | Tir.EIncRC atom ->
    let (ty, v) = emit_atom ctx atom in
    if ty = "ptr" then
      emit ctx (Printf.sprintf "call void @march_incrc_local(ptr %s)" v);
    ("i64", "0")

  | Tir.EDecRC atom
    when atom_is_builtin atom ||
         (match atom with Tir.AVar v -> Hashtbl.mem ctx.top_fns v.Tir.v_name | _ -> false) ->
    ("i64", "0")
  | Tir.EDecRC atom ->
    let (ty, v) = emit_atom ctx atom in
    if ty = "ptr" then
      emit ctx (Printf.sprintf "call void @march_decrc_local(ptr %s)" v);
    ("i64", "0")

  | Tir.EAtomicIncRC atom
    when atom_is_builtin atom ||
         (match atom with Tir.AVar v -> Hashtbl.mem ctx.top_fns v.Tir.v_name | _ -> false) ->
    ("i64", "0")
  | Tir.EAtomicIncRC atom ->
    let (ty, v) = emit_atom ctx atom in
    if ty = "ptr" then
      emit ctx (Printf.sprintf "call void @march_incrc(ptr %s)" v);
    ("i64", "0")

  | Tir.EAtomicDecRC atom
    when atom_is_builtin atom ||
         (match atom with Tir.AVar v -> Hashtbl.mem ctx.top_fns v.Tir.v_name | _ -> false) ->
    ("i64", "0")
  | Tir.EAtomicDecRC atom ->
    let (ty, v) = emit_atom ctx atom in
    if ty = "ptr" then
      emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" v);
    ("i64", "0")

  | Tir.EFree atom
    when atom_is_builtin atom ||
         (match atom with Tir.AVar v -> Hashtbl.mem ctx.top_fns v.Tir.v_name | _ -> false) ->
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
    if String.length field_name > 3 && String.sub field_name 0 3 = "$fv" then begin
      let i = int_of_string (String.sub field_name 3 (String.length field_name - 3)) in
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
    let n = List.length all_fields in
    let (_, base_val) = emit_atom ctx base_atom in
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

  (* ── Case expression ───────────────────────────────────────────────── *)
  | Tir.ECase (scrut_atom, branches, default_opt) ->
    emit_case ctx scrut_atom branches default_opt

  (* ── LetRec (inner lambdas after defun — just emit the body) ───────── *)
  | Tir.ELetRec (_fns, body) ->
    emit_expr ctx body

(** Emit ECase as switch + branch blocks + merge.
    Result is materialized via ptr alloca slot with ptrtoint/inttoptr coercion. *)
and emit_case ctx scrut_atom branches default_opt =
  let (scrut_ty, scrut_val) = emit_atom ctx scrut_atom in
  let scrut_tir_ty_init =
    match scrut_atom with Tir.AVar v -> v.Tir.v_ty | _ -> Tir.TUnit
  in
  (* Fast path: newtype scrutinee — the value IS the payload; no tag/alloc. *)
  match Repr.repr_of_ty !cur_type_defs scrut_tir_ty_init with
  | Repr.Newtype payload ->
    (* Strip a leading DecRC(scrut) from a branch body.
       Perceus inserts DecRC(box) inside the branch assuming box is a heap cell.
       For a newtype, box IS the payload — DecRC would decrement the payload RC,
       leaving our preds binding dangling.  Since box and preds are the same
       object, consuming box's reference and creating preds is a net-zero RC
       change: just drop the DecRC and emit the rest. *)
    let scrut_name = match scrut_atom with Tir.AVar v -> v.Tir.v_name | _ -> "" in
    let strip_decrc body =
      match body with
      | Tir.ESeq (Tir.EDecRC (Tir.AVar v), rest)
      | Tir.ESeq (Tir.EAtomicDecRC (Tir.AVar v), rest)
        when String.equal v.Tir.v_name scrut_name -> rest
      | _ -> body
    in
    (match branches with
     | [] ->
       (* Wildcard/default-only match *)
       (match default_opt with
        | Some d -> emit_expr ctx d
        | None -> ("ptr", "poison"))
     | [br] ->
       (match br.Tir.br_vars with
        | [field_var] ->
          let needs_tag = Repr.payload_needs_tag !cur_type_defs payload in
          let (fty, fval) =
            if needs_tag then begin
              let raw = fresh ctx "nt_raw" in
              emit ctx (Printf.sprintf "%s = ptrtoint ptr %s to i64" raw scrut_val);
              let untagged = fresh ctx "nt_unt" in
              emit ctx (Printf.sprintf "%s = ashr i64 %s, 1" untagged raw);
              ("i64", untagged)
            end else
              ("ptr", coerce ctx scrut_ty scrut_val "ptr")
          in
          let slot = alloca_name ctx (llvm_name field_var.Tir.v_name) in
          emit ctx (Printf.sprintf "%%%s.addr = alloca %s" slot fty);
          emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" fty fval slot);
          Hashtbl.replace ctx.var_llvm_ty slot fty
        | [] -> ()
        | _ -> failwith "emit_case: newtype branch has multiple field vars (impossible)");
       emit_expr ctx (strip_decrc br.Tir.br_body)
     | _ -> failwith "emit_case: newtype type has multiple branches (impossible)")
  | Repr.Niche { payload = _; tagged = niche_tagged } ->
    (* Niche fast path: None = 0, Some(x) = x.
       Emit an icmp eq null + conditional br.  Branch bodies handle their own
       RC via Perceus, but for the Some(ptr) case the DecRC Perceus inserts on
       scrut would incorrectly decrement the payload's RC (scrut IS the payload
       in niche encoding) — strip it in that case. *)
    let scrut_name = match scrut_atom with
      | Tir.AVar v -> v.Tir.v_name | _ -> ""
    in
    let strip_decrc_niche body =
      match body with
      | Tir.ESeq (Tir.EDecRC (Tir.AVar v), rest)
      | Tir.ESeq (Tir.EAtomicDecRC (Tir.AVar v), rest)
        when String.equal v.Tir.v_name scrut_name -> rest
      | _ -> body
    in
    let snapshot_var_slot_n () = Hashtbl.copy ctx.var_slot in
    let restore_var_slot_n snap =
      Hashtbl.reset ctx.var_slot;
      Hashtbl.iter (Hashtbl.add ctx.var_slot) snap
    in
    let result_slot_n = fresh ctx "res_slot" in
    emit ctx (Printf.sprintf "%s = alloca ptr" result_slot_n);
    let merge_lbl_n = fresh_block ctx "niche_merge" in
    let none_lbl    = fresh_block ctx "niche_none" in
    let some_lbl    = fresh_block ctx "niche_some" in
    let scrut_p = coerce ctx scrut_ty scrut_val "ptr" in
    let is_null = fresh ctx "is_null" in
    emit ctx (Printf.sprintf "%s = icmp eq ptr %s, null" is_null scrut_p);
    emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
                     is_null none_lbl some_lbl);
    (* Find the None branch (no br_vars) and Some branch (has br_vars) *)
    let none_branch = List.find_opt (fun br -> br.Tir.br_vars = []) branches in
    let some_branch = List.find_opt (fun br -> br.Tir.br_vars <> []) branches in
    (* None arm *)
    let snap_none = snapshot_var_slot_n () in
    emit_label ctx none_lbl;
    (match none_branch with
     | Some br ->
       let body = strip_decrc_niche br.Tir.br_body in
       let (bty, bval) = emit_expr ctx body in
       emit ctx (Printf.sprintf "store ptr %s, ptr %s"
                   (coerce ctx bty bval "ptr") result_slot_n);
       emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl_n)
     | None ->
       (* Wildcard/default fallback for None *)
       (match default_opt with
        | Some d ->
          let (dty, dval) = emit_expr ctx d in
          emit ctx (Printf.sprintf "store ptr %s, ptr %s"
                      (coerce ctx dty dval "ptr") result_slot_n);
          emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl_n)
        | None -> emit_term ctx "unreachable"));
    restore_var_slot_n snap_none;
    (* Some arm *)
    let snap_some = snapshot_var_slot_n () in
    emit_label ctx some_lbl;
    (match some_branch with
     | Some br ->
       (* Bind the field variable to the extracted payload *)
       (match br.Tir.br_vars with
        | [field_var] ->
          let (fty, fval) =
            if niche_tagged then begin
              let raw = fresh ctx "niche_raw" in
              emit ctx (Printf.sprintf "%s = ptrtoint ptr %s to i64" raw scrut_p);
              let untagged = fresh ctx "niche_unt" in
              emit ctx (Printf.sprintf "%s = ashr i64 %s, 1" untagged raw);
              ("i64", untagged)
            end else
              ("ptr", scrut_p)
          in
          let slot = alloca_name ctx (llvm_name field_var.Tir.v_name) in
          emit ctx (Printf.sprintf "%%%s.addr = alloca %s" slot fty);
          emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" fty fval slot);
          Hashtbl.replace ctx.var_llvm_ty slot fty
        | _ -> ());
       (* Strip DecRC(scrut) always: niche has no outer box.
          - None=0: IS_HEAP_PTR(0)=false, was a no-op anyway
          - Some(int): IS_HEAP_PTR(odd)=false, was a no-op anyway
          - Some(ptr): stripping is REQUIRED — scrut IS the payload *)
       let body = strip_decrc_niche br.Tir.br_body in
       let (bty, bval) = emit_expr ctx body in
       emit ctx (Printf.sprintf "store ptr %s, ptr %s"
                   (coerce ctx bty bval "ptr") result_slot_n);
       emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl_n)
     | None ->
       (match default_opt with
        | Some d ->
          let (dty, dval) = emit_expr ctx d in
          emit ctx (Printf.sprintf "store ptr %s, ptr %s"
                      (coerce ctx dty dval "ptr") result_slot_n);
          emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl_n)
        | None -> emit_term ctx "unreachable"));
    restore_var_slot_n snap_some;
    emit_label ctx merge_lbl_n;
    let r_n = fresh ctx "niche_r" in
    emit ctx (Printf.sprintf "%s = load ptr, ptr %s" r_n result_slot_n);
    ("ptr", r_n)
  | _ ->

  (* Tags produced by PatLit patterns: lowercase "true"/"false" (Bool),
     integers (Int), ":name" (Atom).  ADT constructor tags are capitalized
     identifiers, so these forms are unambiguous.  A scrutinee matched
     against such tags is an immediate at runtime even when its LLVM value
     is ptr-typed — e.g. an ADT field bound at a TVar type is stored as a
     low-bit-tagged immediate ((n<<1)|1), NOT a heap pointer.  Treating it
     as a heap pointer and loading a ctor tag from it is a wild dereference
     (and LLVM folds the resulting unreachable-defaulted switch into "first
     arm always wins").  See: nested Bool/Int/Atom literal patterns inside
     constructor patterns, e.g. [match r do Ok(true) -> … Ok(false) -> …]. *)
  let is_imm_lit_tag t =
    t = "true" || t = "false"
    || int_of_string_opt t <> None
    || (String.length t > 0 && t.[0] = ':')
  in
  let all_imm_lit_tags =
    branches <> [] &&
    List.for_all (fun br -> is_imm_lit_tag br.Tir.br_tag) branches
  in

  let is_ptr_scrut =
    match scrut_atom with
    | Tir.AVar v ->
      (match v.Tir.v_ty with
       | Tir.TBool | Tir.TInt -> false
       | Tir.TCon ("Atom", []) -> false  (* atoms are i64 scalars *)
       | Tir.TVar _ -> scrut_ty = "ptr"  (* unknown type: trust actual loaded LLVM type.
                                            Pattern-bound vars get TVar "_" from lower.ml;
                                            a Bool/Int field loaded as i64 must not be
                                            treated as a heap pointer. *)
       | _ -> true)
    | Tir.ALit (March_ast.Ast.LitBool _) | Tir.ALit (March_ast.Ast.LitInt _)
    | Tir.ALit (March_ast.Ast.LitAtom _) -> false
    | _ -> scrut_ty = "ptr"
  in
  (* Immediate-literal tags override the repr guess: the value cannot be a
     heap object, so never take the load-ctor-tag path for it. *)
  let is_ptr_scrut = is_ptr_scrut && not all_imm_lit_tags in
  (* The scrutinee is an immediate but its LLVM value is ptr-typed: the raw
     bits are the tagged immediate (n<<1)|1.  Switch labels must be tagged
     the same way (comparing tagged-vs-tagged is exact; untagging via ashr
     would lose bit 63 of 64-bit atom hashes). *)
  let scrut_is_tagged_imm = all_imm_lit_tags && scrut_ty = "ptr" in

  (* Defensive invariant: a branch that binds constructor fields requires the
     heap-pointer path — field loads only happen under [is_ptr_scrut].  An ADT
     ctor branch with binders on a non-ptr scrutinee means type-incorrect TIR
     reached codegen (e.g. an i64 scrutinee matched against Ok(v)/Err(e)); the
     integer switch below would leave [br_vars] unbound, and emit_atom's
     0-arg-global-call fallback turns each use into an undefined symbol that
     only surfaces as a clang link error.  Fail loudly at the source instead. *)
  if not is_ptr_scrut then
    List.iter (fun br ->
        let t = br.Tir.br_tag in
        let is_str_tag = String.length t > 0 && t.[0] = '"' in
        if br.Tir.br_vars <> [] && not (is_imm_lit_tag t) && not is_str_tag then
          failwith (Printf.sprintf
            "LLVM emit: constructor pattern %s(%s) destructures a non-pointer \
             scrutinee%s — type-incorrect TIR reached codegen (the pattern \
             binders can never be bound). This is a compiler bug: the \
             typechecker should have rejected this program."
            t
            (String.concat ", "
               (List.map (fun (v : Tir.var) -> v.Tir.v_name) br.Tir.br_vars))
            (match scrut_atom with
             | Tir.AVar v -> " `" ^ v.Tir.v_name ^ "`"
             | _ -> ""))
      ) branches;

  let merge_lbl   = fresh_block ctx "case_merge" in
  let default_lbl = fresh_block ctx "case_default" in
  let branch_lbls = List.map (fun _ -> fresh_block ctx "case_br") branches in

  (* Alloca slot for result — always ptr; coerce scalars via inttoptr *)
  let result_slot = fresh ctx "res_slot" in
  emit ctx (Printf.sprintf "%s = alloca ptr" result_slot);

  (* Detect string-literal case: br_tag starts with '"' *)
  let is_string_case = List.exists (fun br ->
      String.length br.Tir.br_tag > 0 && br.Tir.br_tag.[0] = '"'
    ) branches in

  (* Detect atom case: br_tag starts with ':' — emit switch on i64 FNV1a hashes *)
  let is_atom_case = List.exists (fun br ->
      String.length br.Tir.br_tag > 0 && br.Tir.br_tag.[0] = ':'
    ) branches in

  (* The scrutinee's TIR type — needed both for the switch tag lookup and for
     branch field binding.  Defined early so both uses see it. *)
  let scrut_tir_ty =
    match scrut_atom with Tir.AVar v -> v.Tir.v_ty | _ -> Tir.TUnit
  in

  (* Produce the ctor_info key for a branch tag (keys are "TypeName.CtorName").
     - A BARE tag ("Cons") is qualified with the scrutinee type when known
       ("List.Cons"); otherwise left bare for ctor_entry's suffix resolver.
     - A QUALIFIED pattern ("Inline.Text", "Md.Inline.Text") carries its own type
       qualifier.  Resolve it to the ctor_info key whose constructor matches AND
       whose type segment matches that qualifier, so a ctor name that collides
       with another type's constructor (e.g. stdlib Xml.XmlNode.Text) is
       disambiguated by the qualifier the user wrote — NOT by ctor_entry's
       ambiguous last-segment suffix match (which picks by hashtable order and
       was the cause of cross-module first-variant mismatches). *)
  let qualified_br_key br_tag =
    match String.rindex_opt br_tag '.' with
    | None ->
      (match scrut_tir_ty with
       | Tir.TCon (type_name, _) -> type_name ^ "." ^ br_tag
       | _ -> br_tag)
    | Some i ->
      if Hashtbl.mem ctx.ctor_info br_tag then br_tag
      else begin
        let ctor = String.sub br_tag (i + 1) (String.length br_tag - i - 1) in
        let qual = String.sub br_tag 0 i in
        let last_seg s = match String.rindex_opt s '.' with
          | Some j -> String.sub s (j + 1) (String.length s - j - 1) | None -> s in
        let qtail = last_seg qual in
        let matched = Hashtbl.fold (fun k _ acc ->
            match String.rindex_opt k '.' with
            | Some kc
              when String.equal (String.sub k (kc + 1) (String.length k - kc - 1)) ctor
                   && (let ktype = String.sub k 0 kc in
                       String.equal ktype qual || String.equal (last_seg ktype) qtail) ->
              k :: acc
            | _ -> acc
          ) ctx.ctor_info [] in
        match matched with
        | k :: _ -> k
        | [] -> ctor
      end
  in

  if is_string_case then begin
    (* String pattern matching: emit if-else chain with march_string_eq *)
    let rec emit_chain brs lbls =
      match brs, lbls with
      | [], [] -> emit_term ctx (Printf.sprintf "br label %%%s" default_lbl)
      | br :: rest_brs, lbl :: rest_lbls ->
        let next_lbl = fresh_block ctx "str_next" in
        let s = String.sub br.Tir.br_tag 1 (String.length br.Tir.br_tag - 2) in
        let gname = intern_string ctx s in
        let slit = fresh ctx "sl" in
        emit ctx (Printf.sprintf "%s = call ptr @march_string_lit(ptr %s, i64 %d)"
                    slit gname (String.length s));
        let eq = fresh ctx "seq" in
        emit ctx (Printf.sprintf "%s = call i64 @march_string_eq(ptr %s, ptr %s)"
                    eq scrut_val slit);
        let cmp = fresh ctx "cmp" in
        emit ctx (Printf.sprintf "%s = icmp ne i64 %s, 0" cmp eq);
        emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s" cmp lbl next_lbl);
        emit_label ctx next_lbl;
        emit_chain rest_brs rest_lbls
      | _ -> ()
    in
    emit_chain branches branch_lbls
  end else begin
    (* Detect boolean case: all branch tags are "true"/"false" — emit br i1 *)
    let is_bool_tag t = t = "true" || t = "True" || t = "false" || t = "False" in
    let is_bool_case =
      not is_ptr_scrut &&
      branches <> [] &&
      List.for_all (fun br -> is_bool_tag br.Tir.br_tag) branches
    in
    if is_bool_case then begin
      (* trunc i64 -> i1, then br i1.
         Booleans stored in struct fields come out as ptr (boxed i64); coerce first. *)
      let scrut_i64 = coerce ctx scrut_ty scrut_val "i64" in
      let i1v = fresh ctx "bi" in
      emit ctx (Printf.sprintf "%s = trunc i64 %s to i1" i1v scrut_i64);
      let find_lbl tag fallback =
        match List.find_opt (fun br -> is_bool_tag br.Tir.br_tag &&
          (br.Tir.br_tag = tag || br.Tir.br_tag = String.capitalize_ascii tag)) branches with
        | Some br ->
          let idx = fst (List.fold_left (fun (i, found) b ->
              if found then (i, true)
              else if b == br then (i, true) else (i+1, false)
            ) (0, false) branches) in
          List.nth branch_lbls idx
        | None -> fallback
      in
      let true_lbl  = find_lbl "true"  default_lbl in
      let false_lbl = find_lbl "false" default_lbl in
      emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s" i1v true_lbl false_lbl)
    end else begin
      (* Determine switch discriminant (tag or scalar) *)
      let (sw_ty, sw_val) =
        if is_ptr_scrut then ("i32", emit_load_tag ctx scrut_val)
        else if scrut_is_tagged_imm then begin
          (* ptr-typed tagged immediate: switch on the raw bits *)
          let raw = fresh ctx "ti" in
          emit ctx (Printf.sprintf "%s = ptrtoint ptr %s to i64" raw scrut_val);
          ("i64", raw)
        end
        else ("i64", scrut_val)
      in

      (* Build switch arms, deduplicating by tag to prevent LLVM IR validation
         errors. Duplicate tags can occur in dead code blocks generated by the
         TCO pass when the scrutinee variable has the wrong TIR type (e.g. typed
         as Auth but matched with Option-like Some/None patterns). *)
      let seen_tags = Hashtbl.create 4 in
      let cases_str = List.filter_map (fun (br, lbl) ->
          let tag_str =
            if is_ptr_scrut then
              let e = ctor_entry ctx (qualified_br_key br.Tir.br_tag) (List.length br.Tir.br_vars) in
              string_of_int e.ce_tag
            else begin
              let v =
                if is_atom_case then begin
                  (* Atom tags are ":NAME" — must match emit_atom's interning. *)
                  let name = String.sub br.Tir.br_tag 1 (String.length br.Tir.br_tag - 1) in
                  atom_hash name
                end else
                  match Int64.of_string_opt br.Tir.br_tag with
                  | Some n -> n
                  | None -> 0L
              in
              (* Tagged-immediate scrutinee: tag the label the same way the
                 store tagged the value — (v << 1) | 1. *)
              let v =
                if scrut_is_tagged_imm
                then Int64.logor (Int64.shift_left v 1) 1L
                else v
              in
              Int64.to_string v
            end
          in
          if Hashtbl.mem seen_tags tag_str then None
          else begin
            Hashtbl.add seen_tags tag_str ();
            Some (Printf.sprintf "%s %s, label %%%s" sw_ty tag_str lbl)
          end
        ) (List.combine branches branch_lbls) in
      let cases_part = String.concat "\n      " cases_str in
      emit_term ctx (Printf.sprintf "switch %s %s, label %%%s [\n      %s\n  ]"
                       sw_ty sw_val default_lbl cases_part)
    end
  end;

  (* Helper: if body = ESeq(EDecRC(v)|EAtomicDecRC(v), rest) where
     v.v_name = scrut_name, return (v, rest).
     Both atomic and non-atomic DecRC qualify — the decrc_freed path handles
     the conditional IncRC of children either way. *)
  let strip_scrut_decrc scrut_name body =
    match body with
    | Tir.ESeq (Tir.EDecRC (Tir.AVar v), rest)
    | Tir.ESeq (Tir.EAtomicDecRC (Tir.AVar v), rest)
      when String.equal v.Tir.v_name scrut_name -> Some (v, rest)
    | _ -> None
  in

  (* True iff [body] reuses the scrutinee's own storage via an
     [EReuse (AVar scrut_name, ...)] anywhere it could execute.

     This is the "reuse" counterpart of [strip_scrut_decrc].  When an arm both
     extracts heap fields (inherited from the scrutinee with NO dup) AND reuses
     the scrutinee box at the tail (the FBIP whole-cell-reuse pattern, e.g.
     [Bytes.slice]: [Bytes(xs) -> ... reuse b as Bytes(...)]), the box-level
     RC check lives at the EReuse site — which is too late.  The extracted
     fields were already moved into a consuming callee (e.g. list_drop, which
     FBIP-reuses xs's cons cells in place) UPSTREAM of the EReuse.  When the
     scrutinee is shared (RC > 1) the EReuse takes its dec+alloc-fresh path and
     the original box survives, still pointing at those now-destroyed children
     → use-after-free in the caller (the [b len = 0] bug).

     The fix mirrors the leading-dec shared path: read the scrutinee RC at
     branch ENTRY (a non-consuming load — the EReuse still owns and consumes the
     box reference at the tail) and, on the shared path, IncRC each extracted
     heap field BEFORE the body consumes them.  RC(scrut box) is invariant
     between entry and the EReuse (the body consumes the CHILDREN, never the box
     header), so the entry check and the EReuse check observe the same value and
     stay consistent. *)
  let rec body_reuses_scrut scrut_name e =
    match e with
    | Tir.EReuse (Tir.AVar v, _, _) -> String.equal v.Tir.v_name scrut_name
    | Tir.ELet (v, e1, e2) ->
      body_reuses_scrut scrut_name e1
      || (not (String.equal v.Tir.v_name scrut_name)
          && body_reuses_scrut scrut_name e2)
    | Tir.ESeq (e1, e2) ->
      body_reuses_scrut scrut_name e1 || body_reuses_scrut scrut_name e2
    | Tir.ECase (_, branches, default) ->
      List.exists (fun br ->
        not (List.exists (fun bv ->
               String.equal bv.Tir.v_name scrut_name) br.Tir.br_vars)
        && body_reuses_scrut scrut_name br.Tir.br_body) branches
      || Option.fold ~none:false
           ~some:(body_reuses_scrut scrut_name) default
    | Tir.ELetRec (fns, body) ->
      not (List.exists (fun fn ->
             String.equal fn.Tir.fn_name scrut_name) fns)
      && body_reuses_scrut scrut_name body
    | _ -> false
  in

  (* Per-branch var_slot snapshot.

     Each ECase branch introduces its own bindings via [alloca_name], which
     mutates [ctx.var_slot].  Without restoring [var_slot] between branches,
     a shadow binding introduced by an earlier branch (e.g. [Between(e,lo,hi)]
     shadowing the function's [e] parameter) leaves [var_slot["e"]] pointing
     at the shadow slot (%e_1.addr) for all subsequent branches — so a short
     branch that references the OUTER [e] (typically the scrutinee-free
     DecRC synthesised by Perceus) loads from the wrong, uninitialised slot
     and crashes inside march_decrc_local.

     Only [var_slot] is snapshotted.  [local_names] must remain monotonic
     (it is the uniquifier for LLVM SSA names across the whole function —
     the same shadow name in two sibling branches must get distinct suffixes
     %e_1.addr / %e_2.addr, else LLVM rejects the duplicate definition).
     [var_llvm_ty] is keyed by the uniquified slot name so has no aliasing
     problem and also stays monotonic. *)
  let snapshot_var_slot () = Hashtbl.copy ctx.var_slot in
  let restore_var_slot snap =
    Hashtbl.reset ctx.var_slot;
    Hashtbl.iter (Hashtbl.add ctx.var_slot) snap
  in

  (* Emit branch blocks *)
  List.iter2 (fun br lbl ->
    let snap = snapshot_var_slot () in
    emit_label ctx lbl;
    (* Bind branch variables from scrutinee fields *)
    let heap_field_vals = ref [] in
    if is_ptr_scrut then begin
      let entry = ctor_entry ctx (qualified_br_key br.Tir.br_tag) (List.length br.Tir.br_vars) in
      (* Concrete field types — uses scrutinee type to instantiate type variables.
         For polymorphic ctors like Cons('a, List('a)) with scrutinee List(Int),
         this gives [TInt, TCon("List",[TInt])] instead of [TVar "a", ...]. *)
      let concrete_fields =
        resolve_ctor_fields ctx scrut_tir_ty br.Tir.br_tag (List.length br.Tir.br_vars)
      in
      (* Tuple AND variant fields both follow the UNIFORM slot convention
         (ee23036): scalars are low-bit tagged at construction (coerce i64→ptr)
         and read back as ptr, then untagged conditionally by `coerce ptr→i64`
         (which ashr's only odd/tagged values).  So load EVERY field via
         ce_fields — "ptr" for the synthetic $TupleN entry and for a ctor's
         generic TVar fields — never the concrete native type.  Loading a tuple
         scalar as raw i64 (49ecfbe, which predated the tagging build) read the
         tagged value verbatim — Int 0 → 1, 5 → 11, Bool true → 3 — the moment a
         tuple flowed through a pattern match.  concrete_fields is still used
         below to decide which fields are genuine heap pointers (for IncRC). *)
      List.iteri (fun i (v : Tir.var) ->
        let field_ty = match List.nth_opt entry.ce_fields i with
          | Some t -> llvm_ty t | None -> llvm_ty v.Tir.v_ty in
        let fv = emit_load_field ctx scrut_val i field_ty in
        let slot = alloca_name ctx (llvm_name v.Tir.v_name) in
        emit ctx (Printf.sprintf "%%%s.addr = alloca %s" slot field_ty);
        emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" field_ty fv slot);
        Hashtbl.replace ctx.var_llvm_ty slot field_ty;
        (* Track heap-type fields for conditional IncRC.
           Use the concrete field type (with type-vars resolved) so scalar
           fields (Int, Bool, Float) in polymorphic ctors are NOT IncRC'd. *)
        let concrete_field_ty = match List.nth_opt concrete_fields i with
          | Some t -> llvm_ty t | None -> field_ty in
        if concrete_field_ty = "ptr" then
          heap_field_vals := fv :: !heap_field_vals
      ) br.Tir.br_vars
    end;
    (* When this branch has heap fields AND the body starts with dec_rc(scrutinee),
       use march_decrc_freed to conditionally IncRC extracted child pointers.
       This is necessary for correctness when the scrutinee is shared (RC > 1):
       dec_rc doesn't free the parent, so children are still owned by parent
       AND by the extracted variables — we need IncRC to resolve the double-ownership. *)
    let scrut_name = match scrut_atom with
      | Tir.AVar v -> Some v.Tir.v_name | _ -> None
    in
    let body_to_emit =
      match scrut_name, !heap_field_vals with
      | Some sn, (_ :: _ as fields) ->
        (match strip_scrut_decrc sn br.Tir.br_body with
         | Some (_scrut_v, rest) ->
           (* Emit: march_decrc_freed(scrut); if not freed, incrc each heap field *)
           let freed = fresh ctx "freed" in
           emit ctx (Printf.sprintf "%s = call i64 @march_decrc_freed(ptr %s)"
                       freed scrut_val);
           let freed_bool = fresh ctx "freed_b" in
           emit ctx (Printf.sprintf "%s = icmp ne i64 %s, 0" freed_bool freed);
           let unique_lbl = fresh_block ctx "br_unique" in
           let shared_lbl = fresh_block ctx "br_shared" in
           let body_lbl   = fresh_block ctx "br_body" in
           emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
                            freed_bool unique_lbl shared_lbl);
           (* Shared path: IncRC each extracted heap field *)
           emit_label ctx shared_lbl;
           List.iter (fun fv ->
             emit ctx (Printf.sprintf "call void @march_incrc(ptr %s)" fv)
           ) fields;
           emit_term ctx (Printf.sprintf "br label %%%s" body_lbl);
           (* Unique path: no IncRC needed *)
           emit_label ctx unique_lbl;
           emit_term ctx (Printf.sprintf "br label %%%s" body_lbl);
           emit_label ctx body_lbl;
           rest   (* emit the rest of the body without the leading dec_rc *)
         | None when body_reuses_scrut sn br.Tir.br_body ->
           (* Reuse counterpart of the leading-dec shared path.  The scrutinee
              box is NOT freed at entry — the tail EReuse consumes it.  So here
              we only READ the RC (non-consuming) and, when shared (RC > 1),
              IncRC the extracted heap fields before the body moves them into a
              consuming callee.  No dec/free at entry: the EReuse performs the
              single box-level dec on its rc>1 path. *)
           let rc = fresh ctx "scrut_rc" in
           emit ctx (Printf.sprintf
             "%s = load atomic i64, ptr %s monotonic, align 8" rc scrut_val);
           let shared = fresh ctx "scrut_shared" in
           emit ctx (Printf.sprintf "%s = icmp sgt i64 %s, 1" shared rc);
           let unique_lbl = fresh_block ctx "rb_unique" in
           let shared_lbl = fresh_block ctx "rb_shared" in
           let body_lbl   = fresh_block ctx "rb_body" in
           emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
                            shared shared_lbl unique_lbl);
           (* Shared path: dup each extracted heap field. *)
           emit_label ctx shared_lbl;
           List.iter (fun fv ->
             emit ctx (Printf.sprintf "call void @march_incrc(ptr %s)" fv)
           ) fields;
           emit_term ctx (Printf.sprintf "br label %%%s" body_lbl);
           (* Unique path: nothing to do. *)
           emit_label ctx unique_lbl;
           emit_term ctx (Printf.sprintf "br label %%%s" body_lbl);
           emit_label ctx body_lbl;
           br.Tir.br_body
         | None -> br.Tir.br_body)
      | _ -> br.Tir.br_body
    in
    let (br_ty, br_val) = emit_expr ctx body_to_emit in
    let stored = coerce ctx br_ty br_val "ptr" in
    emit ctx (Printf.sprintf "store ptr %s, ptr %s" stored result_slot);
    emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl);
    restore_var_slot snap
  ) branches branch_lbls;

  (* Default arm *)
  let snap_default = snapshot_var_slot () in
  emit_label ctx default_lbl;
  (match default_opt with
   | None -> emit_term ctx "unreachable"
   | Some d ->
     let (d_ty, d_val) = emit_expr ctx d in
     let stored = coerce ctx d_ty d_val "ptr" in
     emit ctx (Printf.sprintf "store ptr %s, ptr %s" stored result_slot);
     emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl));
  restore_var_slot snap_default;

  emit_label ctx merge_lbl;
  let r = fresh ctx "case_r" in
  emit ctx (Printf.sprintf "%s = load ptr, ptr %s" r result_slot);
  ("ptr", r)

(* ── Mutual TCO: call graph analysis ────────────────────────────────── *)

(** True iff [body] is a "trivial cleanup chain" that performs only
    [EDecRC] / [EAtomicDecRC] / [EFree] operations and finally returns
    the binding named [tmp_name].

    Used to recognise the
        [ELet (tmp, EApp (f, args), ESeq (dec_v1, ESeq (dec_v2, EAtom tmp)))]
    shape that Perceus emits in the EApp case when wrapping a borrowed-arg
    last-use post-call DecRC around a NON-self call (see [perceus.ml] EApp
    handling).  Without this recognition the wrapped call is invisible to
    the tail-call analyses below — silently dropping mutual TCO and
    producing real stack overflows on long inputs. *)
let rec is_trivial_dec_chain_returning (tmp_name : string) (body : Tir.expr) : bool =
  match body with
  | Tir.EAtom (Tir.AVar v) -> String.equal v.Tir.v_name tmp_name
  | Tir.ESeq ((Tir.EDecRC _ | Tir.EAtomicDecRC _ | Tir.EFree _), rest) ->
    is_trivial_dec_chain_returning tmp_name rest
  | _ -> false

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
  | Tir.ELet (tmp_v, Tir.EApp (_, _), body)
    when is_trivial_dec_chain_returning tmp_v.Tir.v_name body ->
    (* Borrow-induced post-DecRC wrapper: the EApp is the tail call.  Body
       contains only DecRC/Free ops + the trailing EAtom — no further calls
       that could be non-tail.  Returning false here keeps the wrapped call
       eligible for mutual TCO; before this guard the rhs was always treated
       as non-tail and TCO was silently dropped. *)
    has_non_tail_group_call group ~in_tail body
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
     in tail position and is not a closure apply fn (those have a clo arg). *)
  let is_tco =
    has_self_tail_call fn.Tir.fn_name fn.Tir.fn_body
    && not (is_builtin_fn fn.Tir.fn_name)
  in

  let params_str = String.concat ", " (List.map (fun (v : Tir.var) ->
      let vn = llvm_name v.Tir.v_name in
      llvm_param_ty ~type_defs:!cur_type_defs v.Tir.v_ty ^ " %" ^ vn ^ ".arg"
    ) fn.Tir.fn_params) in

  Buffer.add_string ctx.buf
    (Printf.sprintf "\ndefine %s @%s(%s) {\nentry:\n" ret_ty fn_llvm_name params_str);

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
    (* Install TCO context so EApp to self emits a back-edge instead of a call. *)
    ctx.tco_fn_name    <- Some fn.Tir.fn_name;
    ctx.tco_loop_label <- loop_lbl;
    ctx.tco_param_info <- param_slots;
    let (body_ty, body_val) = emit_expr ctx fn.Tir.fn_body in
    (* Clear TCO state before emitting any other function. *)
    ctx.tco_fn_name <- None;
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
        Printf.sprintf "%s %%%s.arg" (llvm_param_ty ~type_defs:!cur_type_defs v.Tir.v_ty) base
      ) all_params)
  in
  Buffer.add_string ctx.buf
    (Printf.sprintf "\ndefine %s @%s(%s%s) {\nentry:\n"
       ret_ty (llvm_name combined) tag_param_str rest_params_str);

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

  (* ── Emit wrapper functions ──────────────────────────────────────── *)
  (* Each original function name becomes a thin wrapper that sets the
     dispatch tag and calls the combined function. *)
  List.iter (fun fn ->
    let tag_int     = List.assoc fn.Tir.fn_name fn_tags in
    let fn_llvm     = mangle_extern fn.Tir.fn_name in
    let params_str  = String.concat ", "
      (List.map (fun (v : Tir.var) ->
        Printf.sprintf "%s %%%s.arg" (llvm_param_ty ~type_defs:!cur_type_defs v.Tir.v_ty) (llvm_name v.Tir.v_name)
      ) fn.Tir.fn_params)
    in
    Buffer.add_string ctx.buf
      (Printf.sprintf "\ndefine %s @%s(%s) {\nentry:\n" ret_ty fn_llvm params_str);

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

let emit_preamble ?(target=Native) ?(repl=false) (buf : Buffer.t) =
  Buffer.add_string buf (Printf.sprintf "; March compiler output\ntarget triple = \"%s\"\n\n" (target_triple target));
  (* Core runtime declarations — needed on all targets *)
  Buffer.add_string buf {|; Runtime declarations
; Hot Code Reload versioned dispatch (runtime/march_dispatch.c)
declare ptr  @march_dispatch_enter(i32 %name_id, ptr %out_version)
declare void @march_dispatch_leave(i32 %name_id, i32 %version)
declare i32  @march_dispatch_publish(i32 %name_id, ptr %fn, ptr %impl_hash, i8 %kind)
declare void @march_dispatch_init(i32 %n_slots)
declare ptr  @march_alloc(i64 %sz)
declare void @march_incrc(ptr %p)
declare void @march_decrc(ptr %p)
declare i64  @march_decrc_freed(ptr %p)
declare void @march_incrc_local(ptr %p)
declare void @march_decrc_local(ptr %p)
declare void @march_free(ptr %p)
declare void @march_print(ptr %s)
declare void @march_panic(ptr %s)
declare ptr  @march_panic_ext(ptr %s)
declare ptr  @march_todo_ext(ptr %s)
declare void @march_test_init(i32 %argc, ptr %argv)
declare void @march_test_run(ptr %fn, ptr %name, ptr %setup_or_null)
declare void @march_test_setup_all(ptr %fn)
declare i32  @march_test_report()
declare void @march_println(ptr %s)
declare void @march_print_stderr(ptr %s)
declare ptr  @march_io_read_line()
declare ptr  @march_string_lit(ptr %s, i64 %len)
declare i32  @march_record_shape_intern(ptr %desc)
declare void @march_record_set_shape(ptr %rec, ptr %desc, ptr %cache)
declare ptr  @march_record_keys(ptr %rec)
declare ptr  @march_record_values(ptr %rec)
declare ptr  @march_record_entries(ptr %rec)
declare ptr  @march_record_get(ptr %rec, ptr %key, i64 %kind)
declare i64  @march_record_has_key(ptr %rec, ptr %key)
declare ptr  @march_record_put(ptr %rec, ptr %key, ptr %val, i64 %kind)
declare ptr  @march_record_put3(ptr %rec, ptr %key, ptr %val)
declare ptr  @march_record_from_list(ptr %list)
declare ptr  @march_record_from_list_k(ptr %list, i64 %kind)
declare ptr  @march_record_field_dyn(ptr %rec, ptr %name, i64 %len)
declare ptr  @march_int_to_string(i64 %n)
declare ptr    @march_float_to_string(double %f)
declare ptr    @march_bool_to_string(i64 %b)
; Checked float division — aborts on divisor == 0.0 instead of returning inf/NaN
declare double @march_checked_fdiv(double %a, double %b)
; Checked integer division/remainder — panic on a zero divisor (matches interpreter)
declare i64    @march_checked_idiv(i64 %a, i64 %b)
declare i64    @march_checked_imod(i64 %a, i64 %b)
declare i64    @march_checked_umod(i64 %a, i64 %b)
; Operator forms of / and % — bare "division by zero" / "modulo by zero" messages
declare i64    @march_checked_div_op(i64 %a, i64 %b)
declare i64    @march_checked_mod_op(i64 %a, i64 %b)
declare ptr  @march_string_concat(ptr %a, ptr %b)
declare i64  @march_string_eq(ptr %a, ptr %b)
declare i64  @march_poly_eq(ptr %a, ptr %b)
; Ord / Hash builtins
declare i64    @march_compare_int(i64 %x, i64 %y)
declare i64    @march_compare_float(double %x, double %y)
declare i64    @march_compare_string(ptr %x, ptr %y)
declare i64    @march_hash_int(i64 %x)
declare i64    @march_hash_float(double %x)
declare i64    @march_hash_string(ptr %x)
declare i64    @march_hash_bool(i64 %x)
declare i64  @march_string_byte_length(ptr %s)
declare i64  @march_string_is_empty(ptr %s)
declare ptr  @march_string_to_int(ptr %s)
declare ptr  @march_string_join(ptr %list, ptr %sep)
; Float builtins
declare double @march_float_abs(double %f)
declare i64    @march_float_ceil(double %f)
declare i64    @march_float_floor(double %f)
declare i64    @march_float_round(double %f)
declare i64    @march_float_truncate(double %f)
declare double @march_int_to_float(i64 %n)
; Char builtins
declare ptr    @march_char_from_int(i64 %n)
declare i64    @march_char_to_int(ptr %c)
declare i64    @march_char_is_digit(ptr %c)
declare i64    @march_char_is_alphanumeric(ptr %c)
declare i64    @march_char_is_whitespace(ptr %c)
; Float/Int conversion builtins
declare i64    @march_float_to_int(double %f)
; Math builtins
declare double @march_math_sin(double %f)
declare double @march_math_cos(double %f)
declare double @march_math_tan(double %f)
declare double @march_math_asin(double %f)
declare double @march_math_acos(double %f)
declare double @march_math_atan(double %f)
declare double @march_math_atan2(double %y, double %x)
declare double @march_math_sinh(double %f)
declare double @march_math_cosh(double %f)
declare double @march_math_tanh(double %f)
declare double @march_math_sqrt(double %f)
declare double @march_math_cbrt(double %f)
declare double @march_math_exp(double %f)
declare double @march_math_exp2(double %f)
declare double @march_math_log(double %f)
declare double @march_math_log2(double %f)
declare double @march_math_log10(double %f)
declare double @march_math_pow(double %b, double %e)
; Extended string builtins
declare ptr  @march_string_chars(ptr %s)
declare ptr  @march_string_from_chars(ptr %list)
declare i64  @march_string_contains(ptr %s, ptr %sub)
declare i64  @march_string_starts_with(ptr %s, ptr %prefix)
declare i64  @march_string_ends_with(ptr %s, ptr %suffix)
declare ptr  @march_string_slice(ptr %s, i64 %start, i64 %len)
declare ptr  @march_string_split(ptr %s, ptr %sep)
declare ptr  @march_string_split_first(ptr %s, ptr %sep)
declare ptr  @march_string_replace(ptr %s, ptr %old, ptr %new)
declare ptr  @march_string_replace_all(ptr %s, ptr %old, ptr %new)
declare ptr  @march_string_to_lowercase(ptr %s)
declare ptr  @march_string_to_uppercase(ptr %s)
declare ptr  @march_string_trim(ptr %s)
declare ptr  @march_string_trim_start(ptr %s)
declare ptr  @march_string_trim_end(ptr %s)
declare ptr  @march_string_repeat(ptr %s, i64 %n)
declare ptr  @march_string_reverse(ptr %s)
declare ptr  @march_string_pad_left(ptr %s, i64 %width, ptr %fill)
declare ptr  @march_string_pad_right(ptr %s, i64 %width, ptr %fill)
declare i64  @march_string_grapheme_count(ptr %s)
declare ptr  @march_string_index_of(ptr %s, ptr %sub)
declare ptr  @march_string_last_index_of(ptr %s, ptr %sub)
declare ptr  @march_string_to_float(ptr %s)
; List builtins
declare ptr  @march_list_append(ptr %a, ptr %b)
declare ptr  @march_list_concat(ptr %lists)
; IOList builtins
declare ptr  @march_iolist_hash_fnv1a(ptr %iol)
; Vault (key-value store) builtins
declare ptr  @march_vault_new(ptr %name)
declare ptr  @march_vault_whereis(ptr %name)
declare ptr  @march_vault_set(ptr %table, ptr %key, ptr %value)
declare ptr  @march_vault_set_ttl(ptr %table, ptr %key, ptr %value, i64 %ttl)
declare i64  @march_vault_put_new(ptr %table, ptr %key, ptr %value, i64 %ttl)
declare i64  @march_vault_incr(ptr %table, ptr %key, i64 %delta)
declare ptr  @march_vault_push_capped(ptr %table, ptr %key, ptr %value, i64 %max)
declare ptr  @march_vault_get(ptr %table, ptr %key)
declare ptr  @march_vault_drop(ptr %table, ptr %key)
declare ptr  @march_vault_update(ptr %table, ptr %key, ptr %f)
declare i64  @march_vault_size(ptr %table)
declare ptr  @march_vault_keys(ptr %table)
declare ptr  @march_vault_ns_set(ptr %ns, ptr %key, ptr %value)
declare ptr  @march_vault_ns_get(ptr %ns, ptr %key)
declare ptr  @march_vault_ns_drop(ptr %ns, ptr %key)
; Crypto / hash builtins
declare ptr  @march_md5(ptr %b)
declare ptr  @march_sha256(ptr %b)
declare ptr  @march_sha512(ptr %b)
declare ptr  @march_sha1_bytes(ptr %b)
declare ptr  @march_hmac_sha256(ptr %key, ptr %msg)
declare ptr  @march_hmac_sha256_bytes(ptr %key, ptr %msg)
declare ptr  @march_pbkdf2_sha256(ptr %pass, ptr %salt, i64 %iters, i64 %len)
declare ptr  @march_base64_encode(ptr %b)
declare ptr  @march_base64_decode(ptr %s)
declare ptr  @march_random_bytes(i64 %n)
; Compression builtins (runtime/march_compress.c)
declare ptr  @march_gzip_encode(ptr %b, i64 %level)
declare ptr  @march_gzip_decode(ptr %b)
declare ptr  @march_deflate_encode(ptr %b)
declare ptr  @march_deflate_decode(ptr %b)
declare ptr  @march_zstd_encode(ptr %b, i64 %level)
declare ptr  @march_zstd_decode(ptr %b)
declare ptr  @march_brotli_encode(ptr %b, i64 %mode, i64 %quality)
declare ptr  @march_brotli_decode(ptr %b)
; System introspection builtins
declare i64  @march_sys_uptime_ms()
declare i64  @march_sys_heap_bytes()
declare i64  @march_sys_word_size()
declare i64  @march_sys_minor_gcs()
declare i64  @march_sys_major_gcs()
declare i64  @march_sys_actor_count()
declare i64  @march_sys_cpu_count()
declare ptr  @march_sys_os()
declare ptr  @march_sys_arch()
declare ptr  @march_get_version()
; UUID / identity builtins
declare ptr  @march_uuid_v4()
; Integer math helpers
declare i64  @march_int_pow(i64 %base, i64 %exp)
; LLVM intrinsics
declare i64  @llvm.ctpop.i64(i64 %val)
declare i64  @llvm.abs.i64(i64 %val, i1 %is_int_min_poison)
; Logger builtins
declare ptr  @march_logger_set_level(i64 %level)
declare i64  @march_logger_get_level()
declare ptr  @march_logger_add_context(ptr %key, ptr %value)
declare ptr  @march_logger_clear_context()
declare ptr  @march_logger_get_context()
declare ptr  @march_logger_write(ptr %level, ptr %msg, ptr %ctx, ptr %extra)
; REPL JIT persistent variable slot table (march_extras.c)
declare i64  @march_repl_get(i64 %slot)
declare void @march_repl_set(i64 %slot, i64 %val)

|};
  (* Native-only declarations: actors, networking, file I/O, scheduler *)
  if not (is_wasm_target target) then begin
    Buffer.add_string buf {|; Actor builtins
declare void @march_kill(ptr %actor)
declare i64  @march_is_alive(ptr %actor)
declare ptr  @march_send(ptr %actor, ptr %msg)
declare ptr  @march_send_linear(ptr %actor, ptr %msg)
declare ptr  @march_msg_copy(ptr %src_heap, ptr %dst_heap, ptr %value)
declare ptr  @march_msg_move(ptr %src_heap, ptr %dst_heap, ptr %value)
declare ptr  @march_process_alloc(ptr %heap, i64 %sz)
declare ptr  @march_spawn(ptr %actor)
declare i64  @march_actor_get_int(ptr %actor, i64 %index)
declare ptr  @march_actor_call(ptr %actor, ptr %msg, i64 %timeout_ms)
declare void @march_actor_reply(ptr %ref, ptr %result)
declare void @march_run_scheduler()
declare ptr  @march_task_spawn_thunk(ptr %clo_ptr)
declare ptr  @march_task_await(ptr %task)
declare ptr  @march_task_await_value(ptr %task)
declare void @march_sched_yield()
declare ptr  @march_sched_recv()
declare ptr  @march_cancel_token_new()
declare void @march_cancel_token_cancel(ptr %tok)
declare i64  @march_cancel_token_is_cancelled(ptr %tok)
declare ptr  @march_task_spawn_with_cancel_thunk(ptr %clo, ptr %tok)
declare void @march_task_cancel_by_id(ptr %task)
|};
    (* In REPL mode the reduction check is skipped, so march_tls_reductions and
       march_yield_from_compiled are never referenced — omitting them avoids
       the emutls symbol-not-found error from ORC JIT on macOS. *)
    if not repl then
      Buffer.add_string buf
        "@march_tls_reductions = external thread_local global i64\n\
         declare void @march_yield_from_compiled()\n";
    Buffer.add_string buf {|
; TCP/network builtins
declare i64  @march_tcp_listen(i64 %port)
declare i64  @march_tcp_accept(i64 %fd)
declare ptr  @march_tcp_recv_exact(i64 %fd, i64 %n)
declare ptr  @march_tcp_recv_http(i64 %fd, i64 %max)
declare void @march_tcp_send_all(i64 %fd, ptr %data)
declare void @march_tcp_close(i64 %fd)
declare ptr  @march_tcp_peer_addr(i64 %fd)
declare ptr  @march_http_parse_request(ptr %raw)
declare ptr  @march_http_serialize_response(i64 %status, ptr %headers, ptr %body)
declare void @march_http_server_listen(i64 %port, i64 %max_conns, i64 %idle_timeout, ptr %pipeline)
declare i64  @march_http_server_spawn_n(i64 %port, i64 %n, i64 %max_conns, i64 %idle_timeout, ptr %pipeline)
declare void @march_http_server_wait(i64 %handle)
declare void @march_ws_handshake(i64 %fd, ptr %key)
declare ptr  @march_ws_recv(i64 %fd)
declare void @march_ws_send(i64 %fd, ptr %frame)
declare ptr  @march_ws_select(i64 %fd, ptr %pipe, i64 %timeout)
; File/Dir builtins
declare i64  @march_file_exists(ptr %s)
declare i64  @march_dir_exists(ptr %s)
declare ptr  @march_file_open(ptr %path)
declare ptr  @march_file_close(ptr %handle)
declare ptr  @march_file_read(ptr %path)
declare ptr  @march_file_read_line(ptr %handle)
declare ptr  @march_file_read_chunk(ptr %handle, i64 %size)
declare ptr  @march_file_write(ptr %path, ptr %data)
declare ptr  @march_file_append(ptr %path, ptr %data)
declare ptr  @march_file_delete(ptr %path)
declare ptr  @march_file_copy(ptr %src, ptr %dst)
declare ptr  @march_file_rename(ptr %src, ptr %dst)
declare ptr  @march_file_stat(ptr %path)
declare ptr  @march_dir_mkdir(ptr %path)
declare ptr  @march_dir_mkdir_p(ptr %path)
declare ptr  @march_dir_rmdir(ptr %path)
declare ptr  @march_dir_rm_rf(ptr %path)
declare ptr  @march_dir_list(ptr %path)
declare ptr  @march_dir_list_full(ptr %path)
declare ptr  @march_process_argv()
declare ptr  @march_process_cwd()
declare ptr  @march_process_env(ptr %name)
declare i64  @march_process_set_env(ptr %name, ptr %value)
declare i64  @march_process_exit(i64 %code)
declare i64  @march_process_pid()
declare ptr  @march_process_spawn_sync(ptr %cmd, ptr %args)
declare ptr  @march_process_spawn_lines(ptr %cmd, ptr %args)
declare ptr  @march_process_spawn_async(ptr %cmd, ptr %args)
declare ptr  @march_process_read_line(ptr %proc)
declare i64  @march_process_write(ptr %proc, ptr %data)
declare i64  @march_process_kill_proc(ptr %proc)
declare i64  @march_process_wait_proc(ptr %proc)
; TCP recv-all
declare ptr  @march_tcp_recv_all(ptr %fd, i64 %max_bytes, i64 %timeout_ms)
declare ptr  @march_tcp_recv_chunk(ptr %fd, i64 %max_bytes, i64 %timeout_ms)
declare ptr  @march_tcp_recv_http_headers(ptr %fd, i64 %max_bytes)
declare ptr  @march_tcp_recv_chunked_frame(ptr %fd)
; TLS builtins
declare ptr  @march_tls_client_ctx(ptr %ca_file, ptr %alpn_list, i64 %verify_peer, i64 %timeout_ms)
declare ptr  @march_tls_server_ctx(ptr %cert_file, ptr %key_file, ptr %ca_file, ptr %alpn_list, i64 %verify_peer)
declare ptr  @march_tls_connect(i64 %fd, i64 %ctx_handle, ptr %hostname)
declare ptr  @march_tls_accept(i64 %fd, i64 %ctx_handle)
declare ptr  @march_tls_read(i64 %ssl_handle, i64 %max_bytes)
declare ptr  @march_tls_write(i64 %ssl_handle, ptr %data)
declare void @march_tls_close(i64 %ssl_handle)
declare void @march_tls_ctx_free(i64 %ctx_handle)
declare ptr  @march_tls_negotiated_alpn(i64 %ssl_handle)
declare ptr  @march_tls_peer_cn(i64 %ssl_handle)
; TypedArray builtins
declare ptr  @march_typed_array_create(i64 %len, ptr %default_val)
declare ptr  @march_typed_array_from_list(ptr %list)
declare ptr  @march_typed_array_to_list(ptr %arr)
declare i64  @march_typed_array_length(ptr %arr)
declare ptr  @march_typed_array_get(ptr %arr, i64 %i)
declare ptr  @march_typed_array_set(ptr %arr, i64 %i, ptr %val)
declare ptr  @march_typed_array_map(ptr %arr, ptr %f)
declare ptr  @march_typed_array_filter(ptr %arr, ptr %f)
declare ptr  @march_typed_array_fold(ptr %arr, ptr %acc, ptr %f)
; NativeIntArr builtins — flat i64 arrays for vectorizable loops
declare ptr    @native_int_arr_make(i64 %len, i64 %def)
declare i64    @native_int_arr_length(ptr %arr)
declare i64    @native_int_arr_get(ptr %arr, i64 %i)
declare ptr    @native_int_arr_set(ptr %arr, i64 %i, i64 %val)
declare i64    @native_int_arr_sum(ptr %arr)
declare ptr    @native_int_arr_map(ptr %arr, ptr %f)
declare ptr    @native_int_arr_from_list(ptr %lst)
declare ptr    @native_int_arr_to_list(ptr %arr)
declare ptr    @native_int_arr_filter_mask(ptr %arr, ptr %mask)
; NativeFloatArr builtins — flat double arrays for vectorizable loops
declare ptr    @native_float_arr_make(i64 %len, double %def)
declare i64    @native_float_arr_length(ptr %arr)
declare double @native_float_arr_get(ptr %arr, i64 %i)
declare ptr    @native_float_arr_set(ptr %arr, i64 %i, double %val)
declare double @native_float_arr_sum(ptr %arr)
declare ptr    @native_float_arr_map(ptr %arr, ptr %f)
declare ptr    @native_float_arr_from_list(ptr %lst)
declare ptr    @native_float_arr_to_list(ptr %arr)
declare ptr    @native_float_arr_filter_mask(ptr %arr, ptr %mask)
; Time builtins
declare double @march_unix_time()
declare ptr  @march_tcp_connect(ptr %host, i64 %port)
; HTTP client builtins
declare ptr  @march_http_serialize_request(ptr %method, ptr %host, ptr %path, ptr %query, ptr %headers, ptr %body)
declare ptr  @march_http_parse_response(ptr %raw)
; CSV builtins
declare ptr  @march_csv_open(ptr %path, ptr %delim, ptr %mode)
declare ptr  @march_csv_next_row(ptr %handle)
declare ptr  @march_csv_close(ptr %handle)
; Resource ownership
declare void @march_own(ptr %pid, ptr %value)
; Capability builtins
declare ptr  @march_cap_narrow(ptr %cap)
; Monitor/supervision builtins
declare void @march_demonitor(i64 %ref)
declare i64  @march_monitor(ptr %watcher, ptr %target)
declare i64  @march_mailbox_size(ptr %pid)
declare void @march_run_until_idle()
declare void @march_register_resource(ptr %pid, ptr %name, ptr %cleanup)
declare ptr  @march_get_cap(ptr %pid)
declare void @march_send_checked(ptr %cap, ptr %msg)
declare ptr  @march_pid_of_int(i64 %n)
declare ptr  @march_get_actor_field(ptr %pid, ptr %name)
declare void @march_link(ptr %actor_a, ptr %actor_b)
declare void @march_unlink(ptr %actor_a, ptr %actor_b)
declare void @march_register_supervisor(ptr %supervisor, i64 %strategy, i64 %max_restarts, i64 %window_secs)
declare ptr  @march_value_to_string(ptr %v)
; Session-typed channel builtins (binary)
declare ptr  @march_chan_new(ptr %proto_name)
declare ptr  @march_chan_send(ptr %ep, ptr %val)
declare ptr  @march_chan_recv(ptr %ep)
declare i64  @march_chan_close(ptr %ep)
declare ptr  @march_chan_choose(ptr %ep, ptr %label)
declare ptr  @march_chan_offer(ptr %ep)
; Multi-party session type (MPST) builtins
declare ptr  @march_mpst_new(ptr %proto_name, i64 %n_roles)
declare ptr  @march_mpst_send(ptr %ep, ptr %target_role, ptr %val)
declare ptr  @march_mpst_recv(ptr %ep, ptr %source_role)
declare i64  @march_mpst_close(ptr %ep)
|}
  end else
    (* WASM targets: plain global instead of thread_local; no-op scheduler *)
    Buffer.add_string buf {|; WASM: plain global (no TLS), no-op scheduler stub
@march_tls_reductions = external global i64
declare void @march_yield_from_compiled()
declare void @march_run_scheduler()
declare ptr  @march_task_spawn_thunk(ptr %clo_ptr)
declare ptr  @march_task_await(ptr %task)
declare ptr  @march_task_await_value(ptr %task)
declare void @march_sched_yield()
declare ptr  @march_sched_recv()
declare ptr  @march_cancel_token_new()
declare void @march_cancel_token_cancel(ptr %tok)
declare i64  @march_cancel_token_is_cancelled(ptr %tok)
declare ptr  @march_task_spawn_with_cancel_thunk(ptr %clo, ptr %tok)
declare void @march_task_cancel_by_id(ptr %task)
|}

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
    (m : Tir.tir_module) : string =
  cur_type_defs := m.Tir.tm_types;
  (* Hot Code Reload: intern the names of every reloadable (boundary) function
     into NAME_IDs for the dispatch table. *)
  let hr_names =
    match hot_reload with
    | None -> Hot_reload.Name_table.build []
    | Some cfg ->
      m.Tir.tm_fns
      |> List.filter_map (fun fn ->
           if Hot_reload.is_reloadable cfg (module_of_name fn.Tir.fn_name)
           then Some fn.Tir.fn_name else None)
      |> Hot_reload.Name_table.build
  in
  let ctx = make_ctx ~fast_math ~pmap_threshold ~hot_reload ~hr_names () in
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
    | Some cfg ->
      let n = Hot_reload.Name_table.count hr_names in
      if n = 0 then "" else begin
        let b = Buffer.create 256 in
        Printf.bprintf b "  call void @march_dispatch_init(i32 %d)\n" n;
        List.iter (fun (fn : Tir.fn_def) ->
          if Hot_reload.is_reloadable cfg (module_of_name fn.Tir.fn_name) then
            match Hot_reload.Name_table.id_of hr_names fn.Tir.fn_name with
            | Some id ->
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
              Printf.bprintf b
                "  call i32 @march_dispatch_publish(i32 %d, ptr @%s, %s, i8 0)\n"
                id (mangle_extern fn.Tir.fn_name) hash_arg
            | None -> ()
        ) m.Tir.tm_fns;
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
         named "abs" would incorrectly resolve to @Math.abs). *)
      (match String.rindex_opt fn.Tir.fn_name '.' with
       | Some i ->
         let unq = String.sub fn.Tir.fn_name (i+1)
                     (String.length fn.Tir.fn_name - i - 1) in
         if not (Hashtbl.mem ctx.unqualified_fns unq) then begin
           Hashtbl.replace ctx.unqualified_fns unq fn.Tir.fn_name
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
  List.iter (fun fn ->
      if List.mem fn.Tir.fn_name preamble_declared then ()
      else if List.mem fn.Tir.fn_name mutual_fn_names then ()
      else emit_fn ctx fn
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
     (* Native / WASI: test-runner @main (when tm_tests populated) or standard @main. *)
     if m.Tir.tm_tests <> [] then begin
       (* --test mode: emit a @main that calls the test harness.
          For each test fn we emit a string constant for its display name and
          call march_test_run(fn_ptr, name_ptr, setup_or_null).
          setup_all and per-test setup are optional and may not exist. *)
       let has_setup_all = List.exists (fun (fn : Tir.fn_def) ->
           fn.Tir.fn_name = "__march_setup_all__") m.Tir.tm_fns in
       let has_setup = List.exists (fun (fn : Tir.fn_def) ->
           fn.Tir.fn_name = "__march_setup__") m.Tir.tm_fns in
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
              (llvm_name (mangle_extern "__march_setup_all__")));
       let setup_arg = if has_setup then
         Printf.sprintf "ptr @%s" (llvm_name (mangle_extern "__march_setup__"))
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
             %s\
               call void @march_spawn_main(ptr @%s)\n\
               call void @march_run_scheduler()\n\
               ret i32 0\n}\n" hr_setup mangled)
        | None ->
          (* Library module with no user-defined main: emit a stub @main so
             clang can link a valid binary (forge build type-checks libraries). *)
          Buffer.add_string out
            "\ndefine i32 @main(i32 %argc, ptr %argv_ptr) {\nentry:\n  ret i32 0\n}\n")
     end);

  (* Append closure wrapper functions generated for top-level fn-as-value *)
  Buffer.add_buffer out ctx.extra_fns;

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
  let ctx = make_ctx ~fast_math ~repl:true () in
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
  let ctx = make_ctx ~fast_math ~repl:true () in
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
  Buffer.contents out

(** Emit a REPL function declaration as a .ll fragment.
    The function is emitted at top level (callable by later fragments).
    A no-op [@repl_<n>_init] is emitted so the REPL runner can call it uniformly. *)
let emit_repl_fn ?(fast_math=false) ~(n : int)
    ~(prev_slots : repl_slot_info list)
    ?(extern_fns : Tir.fn_def list = [])
    ~(types : Tir.type_def list)
    (fn : Tir.fn_def) : string =
  let ctx = make_ctx ~fast_math ~repl:true () in
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
  let ctx = make_ctx ~fast_math ~repl:true () in
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
     Uses the same concrete parameter types and untagged return as the wrapper
     emitted by emit_atom (lines 1095-1112).  This ensures ECallPtr call-sites
     (which declare the concrete return type) get the raw value back, not a
     tagged pointer.  Keeping both wrappers identical also prevents behavioural
     disagreement when the two .so files define the same symbol name. *)
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
  let wrap_body =
    if target_ret = "void" then
      Printf.sprintf "\ndefine ptr @%s(%s) {\nentry:\n  call void @%s(%s)\n  ret ptr null\n}\n"
        wrap_name decl_str fn_llvm_name call_args
    else
      Printf.sprintf "\ndefine %s @%s(%s) {\nentry:\n  %%r = call %s @%s(%s)\n  ret %s %%r\n}\n"
        target_ret wrap_name decl_str target_ret fn_llvm_name call_args target_ret
  in
  Buffer.add_string ctx.buf wrap_body;
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
  let ctx = make_ctx ~repl () in
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
