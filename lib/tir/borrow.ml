(** Borrow Inference — Pre-Perceus Analysis Pass.

    Determines which function parameters are "borrowed" — only read within
    the callee and never stored, returned, or passed to an owning position.
    Borrowed parameters need no reference-counting:
    - At call sites: no EIncRC before passing a borrowed arg that is still live
    - In callees: no EDecRC when a borrowed param goes out of scope

    The analysis uses an optimistic fixpoint iteration over the module's
    functions, starting with all RC-needing parameters marked as borrowed and
    refining until no further parameters are found to be owned.

    Runs after Defun so that closures are already explicit EAlloc nodes —
    free-variable captures are visible as constructor arguments, making them
    conservatively owning.

    The key rule:
      A use is OWNING  if the value is stored (EAlloc / ETuple / ERecord /
                         EUpdate field), returned (EAtom(AVar)), or passed to
                         an unknown callee (ECallPtr) or an owned parameter of
                         a known callee.
      A use is BORROWING if the value is used as an ECase scrutinee, an EField
                         source, or passed to a borrowed parameter of a known
                         callee.

    After convergence, [is_borrowed m fn_name idx] returns true iff parameter
    [idx] of function [fn_name] is safe to borrow. *)

module StringMap = Map.Make (String)

(** Per-function borrow modes, indexed by parameter position.
    [true] = borrowed, [false] = owned. *)
type param_modes = bool array

(** Module-level borrow map: function name → per-parameter modes. *)
type borrow_map = param_modes StringMap.t

let empty : borrow_map = StringMap.empty

(** Hardcoded borrow table for C extern functions that borrow (read-only) their
    string/heap parameters without taking ownership.  Indexed by C name *or*
    TIR builtin name (the same name appears in EApp before LLVM mangling).

    Format: (function_name, bool list) where each bool indicates whether the
    corresponding positional parameter is borrowed. *)
let extern_borrow_table : (string * bool list) list = [
  (* ── IO ─────────────────────────────────────────────────────────────────── *)
  ("march_print",   [true]);
  ("march_println", [true]);
  ("print",         [true]);   (* TIR builtin name before LLVM mangling *)
  ("println",       [true]);
  ("print_line",    [true]);
  ("dist_monitor_register", [false; true; false; false]);
  ("march_dist_monitor_register_pid", [false; true; false; false]);
  ("dist_monitor_forget_node", [true]);
  ("march_dist_monitor_forget_node_str", [true]);
  (* ── Actors: the pid is a HANDLE, read but never stored or released by
     these runtime functions (audited 2026-09-14: march_send, march_kill,
     march_actor_stop, march_is_alive, march_actor_is_draining,
     march_mailbox_size, march_get_cap contain no decrc of the actor).
     Borrowing them was tried 2026-09-13 and backed out because a live actor
     then had NO reference of its own and the drop at the pid's last use freed
     it; since specs/progress/2026-09-14-live-actor-freed-by-dropping-its-last-pid.md
     the running actor holds one, so releasing the program's pids is safe.
     `send`'s MESSAGE stays owned (the runtime enqueues it). *)
  ("send",              [true; false]);
    (* the ref is read, incrc'd, and returned as a NEW owned reference *)
    ("actor_reply_retain", [true]);
  ("actor_cast",        [true; false]);
  ("march_send",        [true; false]);
  ("kill",              [true]);
  ("march_kill",        [true]);
  ("actor_stop",        [true; false]);
  ("march_actor_stop",  [true; false]);
  ("is_alive",          [true]);
  ("march_is_alive",    [true]);
  ("actor_is_draining", [true]);
  ("march_actor_is_draining", [true]);
  ("mailbox_size",      [true]);
  ("march_mailbox_size", [true]);
  ("get_cap",           [true]);
  ("march_get_cap",     [true]);
  (* ── Core string operations ─────────────────────────────────────────────── *)
  ("march_string_eq",          [true; true]);
  ("march_string_concat",      [true; true]);
  ("march_string_byte_length", [true]);
  ("march_string_byte_at",     [true; false]);
  ("march_string_grapheme_count", [true]);
  ("march_string_is_empty",    [true]);
  ("march_string_to_int",      [true]);
  ("march_string_to_float",    [true]);
  ("march_string_to_lowercase",[true]);
  ("march_string_to_uppercase",[true]);
  ("march_string_trim",        [true]);
  ("march_string_trim_start",  [true]);
  ("march_string_trim_end",    [true]);
  ("march_string_reverse",     [true]);
  (* ── 2-arg string × string ──────────────────────────────────────────────── *)
  ("march_string_contains",      [true; true]);
  ("march_string_starts_with",   [true; true]);
  ("march_string_ends_with",     [true; true]);
  ("march_string_split",         [true; true]);
  ("march_string_split_first",   [true; true]);
  ("march_string_index_of",      [true; true]);
  ("march_string_last_index_of", [true; true]);
  ("march_string_to_codepoints", [true]);
  (* ── 3-arg string × string × string ────────────────────────────────────── *)
  ("march_string_replace",     [true; true; true]);
  ("march_string_replace_all", [true; true; true]);
  (* ── mixed-arity: string param(s) only ─────────────────────────────────── *)
  (* slice(s, int_start, int_len)  — only s is a string *)
  ("march_string_slice",     [true; false; false]);
  (* repeat(s, int_n)  — only s is a string *)
  ("march_string_repeat",    [true; false]);
  (* join(list, sep): BOTH borrowed.  march_string_join only walks the list and
     copies bytes out of each element; it neither stores nor frees anything.
     The list was marked owned from this table's first version (724adae3, no
     recorded reason), so every list passed to string_join -- including the
     mapped list inside prelude's `impl Show(List(a))` -- leaked with its
     elements: 5 objects per `to_string` of a 2-element list.
     Guard: test/native/show_list_leak_probe.march. *)
  ("march_string_join",      [true; true]);
  (* pad_left/right(s, int_width, fill)  — s and fill are strings *)
  ("march_string_pad_left",  [true; false; true]);
  ("march_string_pad_right", [true; false; true]);
  (* ── Comparison operators ─────────────────────────────────────────────────
     Every emit path for these only READS its operands (llvm_emit_arith.ml):
     march_string_eq / march_compare_string, the inline field compare of an
     unboxed aggregate, the generated structural equality from Llvm_eq (which
     calls only other generated eq fns and those two C helpers), and
     march_poly_eq / march_poly_compare for an erased operand.  Absent from
     this table they defaulted to OWNED, so a fresh String or List compared
     once was handed over and never released: one leaked object per `==` on a
     fresh string, six per `==` on a two-element list.  Scalars are unaffected
     (no RC op is emitted for them either way).
     Guard: test/native/builtin_borrow_leak_probe.march. *)
  ("==",                   [true; true]);
  ("!=",                   [true; true]);
  ("<",                    [true; true]);
  ("<=",                   [true; true]);
  (">",                    [true; true]);
  (">=",                   [true; true]);
  (* ── TIR builtin names (pre-mangling) ───────────────────────────────────── *)
  (* [is_borrowed] is keyed by the EApp callee's TIR name, never by the C
     name, so a builtin whose TIR name differs from its C symbol must be
     listed under the TIR name.  These two were listed only as
     march_string_byte_length / march_value_to_string and leaked the argument
     of every call.  march_value_to_string takes its own +1 when it returns a
     String argument unchanged, so borrowed is correct for it too. *)
  ("string_length",        [true]);
  ("compare_string",       [true; true]);   (* march_compare_string only reads *)
  ("to_string",            [true]);
  ("string_eq",            [true; true]);
  ("string_concat",        [true; true]);
  ("++",                   [true; true]);
  ("string_concat3",       [true; true; true]);
  ("string_byte_length",   [true]);
  ("string_byte_at",       [true; false]);
  ("string_grapheme_count",[true]);
  ("string_is_empty",      [true]);
  ("string_to_int",        [true]);
  ("string_to_float",      [true]);
  ("string_to_lowercase",  [true]);
  ("string_to_uppercase",  [true]);
  ("string_trim",          [true]);
  ("string_trim_start",    [true]);
  ("string_trim_end",      [true]);
  ("string_reverse",       [true]);
  ("string_contains",      [true; true]);
  ("string_starts_with",   [true; true]);
  ("string_ends_with",     [true; true]);
  ("string_split",         [true; true]);
  ("string_split_first",   [true; true]);
  ("string_index_of",      [true; true]);
  ("string_index_of_from", [true; true; true]);
  ("string_last_index_of", [true; true]);
  ("string_to_codepoints", [true]);
  ("string_replace",       [true; true; true]);
  ("string_replace_all",   [true; true; true]);
  ("string_slice",         [true; false; false]);
  ("string_repeat",        [true; false]);
  ("string_join",          [true; true]);    (* see march_string_join above *)
  ("string_pad_left",      [true; false; true]);
  ("string_pad_right",     [true; false; true]);
  (* ── Record introspection builtins ───────────────────────────────────────
     All args are borrowed reads: the C implementations take +1 references
     (march_incrc) on any field values they alias into freshly built results
     and never consume the record/key/value arguments. *)
  ("record_keys",      [true]);
  ("record_values",    [true]);
  ("record_entries",   [true]);
  ("record_get",       [true; true]);
  ("record_has_key",   [true; true]);
  ("record_put",       [true; true; true]);
  ("record_from_list", [true]);
  (* ── RingBuf builtins ───────────────────────────────────────────────────
     The buffer [rb] is borrowed by every op: RingBuf mutates in place through
     the pointer and returns Unit/Option/List, never consuming the buffer, so
     the caller retains ownership and drops it when it goes dead.  push's second
     param [x] is NOT borrowed — it is transferred (owned) into the ring, which
     stores it without an incref and releases it on overwrite/pop/clear/drop.
     get's Int index is not a heap value. *)
  ("ring_buf_make",        [false]);
  ("ring_buf_push",        [true; false]);
  ("ring_buf_pop",         [true]);
  ("ring_buf_get",         [true; false]);
  ("ring_buf_peek_oldest", [true]);
  ("ring_buf_peek_newest", [true]);
  ("ring_buf_size",        [true]);
  ("ring_buf_cap",         [true]);
  ("ring_buf_clear",       [true]);
  ("ring_buf_to_list",     [true]);
  (* ── NativeArray: reads borrow their array, `set` consumes it (in-place) ── *)
  ("native_u8_arr_get",    [true; false]);
  ("native_u8_arr_length", [true]);
  ("native_u8_arr_sum",    [true]);
  ("native_u8_arr_to_list",[true]);
  ("native_i32_arr_get",    [true; false]);
  ("native_i32_arr_length", [true]);
  ("native_i32_arr_sum",    [true]);
  ("native_i32_arr_to_list",[true]);
  ("native_f32_arr_get",    [true; false]);
  ("native_f32_arr_length", [true]);
  ("native_f32_arr_sum",    [true]);
  ("native_f32_arr_to_list",[true]);
  ("native_int_arr_get",    [true; false]);
  ("native_int_arr_length", [true]);
  ("native_int_arr_sum",    [true]);
  ("native_int_arr_to_list",[true]);
  ("native_float_arr_get",    [true; false]);
  ("native_float_arr_length", [true]);
  ("native_float_arr_sum",    [true]);
  ("native_float_arr_to_list",[true]);
  (* ── Synthetic C names used directly in lower.ml wrappers ──────────────── *)
  ("march_compare_string", [true; true]);
  ("march_hash_string",    [true]);
  (* Show$String.show's body.  march_value_to_string BORROWS: on a genuine
     String it takes its own +1 (march_incrc) before aliasing the input into the
     result, and every other representation it builds a fresh string.  It never
     consumes the argument, so the caller keeps ownership. *)
  ("march_value_to_string", [true]);
]

(** Builtins that borrow EVERY argument, at any arity.

    [extern_borrow_table] is a fixed-length list per name, which cannot say
    "all of them" for a variadic builtin: [List.nth_opt] past the end answers
    [None], i.e. NOT borrowed, so Perceus would treat the call as consuming
    those arguments and emit no drop for them.  For [string_concat_n], whose C
    implementation borrows all its parts, that leaks every operand past the
    third. *)
let all_args_borrowed_builtins = [ "string_concat_n" ]

let ends_with ~(suffix : string) (s : string) : bool =
  let sl = String.length suffix and n = String.length s in
  n >= sl && String.sub s (n - sl) sl = suffix

(** True for a SIMD vector builtin ([simd_f32x4_add], [simd_u8x16_sum], …).

    Every one of them READS its vector operands: they lower to LLVM vector
    instructions in [Llvm_emit_simd], not to a C call that could store or free
    anything, and the only heap object in sight is the [march_simd_alloc] box a
    call site makes when a vector crosses a [ptr] slot.  Classifying them owned
    — the pre-2026-09-16 default — made every function that merely reads its
    vector parameter own it, so nobody released that box: one leaked 32-byte
    cell per call to any non-TCO callee with a vector parameter
    (specs/todos/2026-08-12-simd-nontco-vector-param-leak.md).

    Matched by name rather than listed: the grid is 127 names across five lane
    types, and a list would rot the moment a lane type gains an operation.  The
    prefix is minted by [Defun]'s builtin table, which is the same source the
    arity grid comes from. *)
let is_simd_builtin (fn_name : string) : bool =
  let p = "simd_" in
  String.length fn_name > String.length p
  && String.sub fn_name 0 (String.length p) = p
  (* …except the two that touch a NativeArray rather than only vectors.
     [simd_<lane>_load] reads lanes out of an array and [_store] writes them
     back; their FIRST parameter is that array, and the array's ownership is
     the array builtins' story, not this one.  Classifying it borrowed moved
     the release of a live array to its last syntactic use and broke
     simd_vector_mem ("native_f32_arr_get: index 2 out of bounds (len=0)"),
     simd_vector_core and native_arr_map_inline_vectorize.  The vector operand
     they also take is the one this rule is about, and it is not the leak this
     closes: a vector reaching an array builtin is stored lane-wise, never
     boxed. *)
  && not (ends_with ~suffix:"_load" fn_name)
  && not (ends_with ~suffix:"_store" fn_name)

(** Builtins with a heap ([ptr]) parameter that are deliberately OWNED: each
    either consumes its argument (it stores or frees it -- e.g. [send]'s
    message, [vault_set]'s value) or has not been audited yet and keeps the
    pre-2026-09-13 default.

    Every [in_is_builtin] row of [Llvm_builtins.builtins] with a [ptr]
    parameter must appear in exactly one of [extern_borrow_table],
    [all_args_borrowed_builtins] or this list; test_builtin_borrow_classification
    fails otherwise.  Before that guard, an unlisted builtin silently defaulted
    to owned, and every read-only one (`==`, `string_length`) leaked the
    argument of each call.

    Moving a name from here to [extern_borrow_table] needs two checks, not
    one: that its C implementation neither stores nor frees the argument, AND
    that nothing hands it a reference it does not own.  The second is not
    hypothetical: [typed_array_get] returned array elements without a
    reference, which only stayed balanced while `==` consumed them.  Actor pids
    were that case until 2026-09-14: every pid-producing builtin now returns an
    OWNED reference (pid_of_int, self, actor_whereis, spawn) and the running
    actor holds one of its own, so the read-only actor family moved to
    [extern_borrow_table] — see
    specs/progress/2026-09-14-pid-ownership-settled-send-borrows-self-owned.md. *)
let extern_owned_builtins : string list = [
    "panic_"; "unreachable_"; "todo_"; "print_stderr"; "char_to_int";
    "char_is_digit"; "char_is_alphanumeric"; "char_is_whitespace";
    "string_chars"; "string_from_chars"; "list_append"; "list_concat";
    "iolist_hash_fnv1a"; "vault_new"; "vault_whereis"; "vault_set";
    "vault_set_ttl"; "vault_put_new"; "vault_incr"; "vault_push_capped";
    "vault_get"; "vault_drop"; "vault_update"; "vault_size"; "vault_keys";
    "vault_ns_set"; "vault_ns_get"; "vault_ns_drop"; "md5"; "sha256";
    "stdlib_sha256"; "sha512"; "stdlib_sha512"; "hmac_sha256";
    "stdlib_hmac_sha256"; "hmac_sha256_bytes"; "pbkdf2_sha256";
    "base64_encode"; "stdlib_base64_encode"; "base64_decode";
    "stdlib_base64_decode"; "bytes_to_u8_arr"; "u8_arr_to_bytes";
    "remote_register_stub"; "remote_check"; "remote_invoke";
    "logger_add_context"; "logger_write"; "spawn";
    "spawn_supervised"; "actor_get_int"; "actor_call"; "actor_reply";
    "actor_send_after"; "actor_cancel_timer"; "http_server_spawn_n";
    "file_exists"; "dir_exists"; "file_open"; "file_close"; "file_read";
    "file_read_line"; "file_read_chunk"; "file_write"; "file_append";
    "file_delete"; "file_copy"; "file_rename"; "file_stat"; "dir_mkdir";
    "dir_mkdir_p"; "dir_rmdir"; "dir_rm_rf"; "dir_list"; "dir_list_full";
    "process_env"; "process_set_env"; "process_spawn_sync";
    "process_spawn_lines"; "process_spawn_async"; "process_read_line";
    "process_write"; "process_kill_proc"; "process_wait_proc";
    "tls_client_ctx"; "tls_server_ctx"; "tls_connect"; "tls_write";
    "typed_array_create"; "typed_array_from_list"; "typed_array_to_list";
    "typed_array_length"; "typed_array_get"; "typed_array_set";
    "typed_array_map"; "typed_array_filter"; "typed_array_fold";
    "native_int_arr_set"; "native_int_arr_sort";
    "native_int_arr_min"; "native_int_arr_max";
    "native_int_arr_sumsq_dev"; "native_int_arr_map"; "native_int_arr_map2";
    "native_int_arr_to_float_arr"; "native_int_arr_fold";
    "native_int_arr_from_list"; "native_int_arr_filter_mask";
    "native_float_arr_set"; "native_float_arr_min"; "native_float_arr_max";
    "native_float_arr_sumsq_dev"; "native_float_arr_map";
    "native_float_arr_map2"; "native_float_arr_fold";
    "native_float_arr_from_list"; "native_float_arr_filter_mask";
    "native_f32_arr_set"; "native_f32_arr_map"; "native_f32_arr_map2";
    "native_f32_arr_fold"; "native_f32_arr_from_list"; "native_i32_arr_set";
    "native_i32_arr_map"; "native_i32_arr_map2"; "native_i32_arr_fold";
    "native_i32_arr_from_list"; "native_u8_arr_set"; "native_u8_arr_map";
    "native_u8_arr_map2"; "native_u8_arr_fold"; "native_u8_arr_from_list";
    "native_float_to_f32_arr"; "native_f32_to_float_arr";
    "native_int_to_i32_arr"; "native_i32_to_int_arr"; "native_int_to_u8_arr";
    "native_u8_to_int_arr"; "native_i32_to_f32_arr"; "native_u8_to_f32_arr";
    "tcp_connect"; "tcp_connect_timeout"; "http_serialize_request"; "http_parse_response";
    "csv_open"; "csv_next_row"; "csv_close"; "own"; "cap_narrow"; "mint_cap";
    "cap_impl"; "cap_dict"; "set_actor_caps"; "actor_caps"; "monitor";
    "actor_set_mailbox_limit"; "register_resource";
    "actor_register"; "actor_unregister"; "actor_whereis";
    "send_checked"; "revoke_cap"; "is_cap_valid"; "get_actor_field";
    "register_supervisor"; "register_supervisor_child"; "pid_index_of";
    "pid_to_int";
]

(** True iff parameter [idx] of C extern / TIR builtin [fn_name] is borrowed
    according to the hardcoded ABI table.  Used as a fallback in [is_borrowed]
    when the function is not a March-defined function. *)
let is_extern_borrowed (fn_name : string) (param_idx : int) : bool =
  if List.mem fn_name all_args_borrowed_builtins || is_simd_builtin fn_name then true
  else
  match List.assoc_opt fn_name extern_borrow_table with
  | Some borrows ->
    (match List.nth_opt borrows param_idx with Some b -> b | None -> false)
  | None -> false

(** True iff parameter [idx] of [fn_name] is marked borrowed in [m].
    Falls back to [is_extern_borrowed] for C externs / TIR builtins not
    present in the March borrow map. *)
let is_borrowed (m : borrow_map) (fn_name : string) (idx : int) : bool =
  match StringMap.find_opt fn_name m with
  | Some modes -> idx < Array.length modes && modes.(idx)
  | None -> is_extern_borrowed fn_name idx

(* Borrow-inference eligibility is [Rc_types.borrow_eligible] — NOT the same
   predicate as [Rc_types.needs_rc] (Perceus's RC-op emission question):
   they deliberately diverge on TFn / bare TVar / TTuple / TRecord. See
   Rc_types's module doc for the contract and fix history. *)

(* ── Scalar-only variant types ───────────────────────────────────────────

   [field_escape_owns] below marks a parameter OWNED as soon as any field
   extracted from it is used in an owning position.  Its rationale is entirely
   about HEAP fields: pattern-match extraction hands out a field's value
   without incrementing its refcount, so if that field then escapes, the
   caller holds an aliased pointer it does not own, and the next read of the
   parent double-frees or use-after-frees the child.

   For a variant type whose EVERY constructor's EVERY declared field is a
   scalar — Int, Float, Bool, Unit, or the interned-i64 Atom — no extracted
   field can be a pointer, and the hazard cannot arise: `a + b` on two Int
   fields is not an aliasing question at all.  Before this table such a type
   (`Big(Int, Int, Int, Int, Int)`, `Hit(Bool, Int, Int)`, an enum with
   payloads) was inferred `own` the moment its fields met any builtin, since
   [is_borrowed] has no entry for `+`.  That is not merely a missed
   optimisation: being owned is what makes [Perceus] emit a `dec_rc` on the
   parameter inside the callee, which is what stops [Escape] from ever
   stack-promoting such a value at a call site (a stack cell has rc = 0).

   Kept as a module-level table set once per [infer_module] rather than
   threaded through [owned_in]'s fifteen recursive call sites — the same
   shape, and the same trade, as [Repr]'s unboxed registry.  Empty by
   default, so a caller that never runs [infer_module] gets the previous
   behaviour. *)
let _scalar_only : (string, unit) Hashtbl.t = Hashtbl.create 16

let is_scalar_field_ty : Tir.ty -> bool = function
  | Tir.TInt | Tir.TFloat | Tir.TBool | Tir.TUnit -> true
  | Tir.TCon ("Atom", []) -> true
  | _ -> false

let set_scalar_only_types (type_defs : Tir.type_def list) : unit =
  Hashtbl.reset _scalar_only;
  List.iter (function
      | Tir.TDVariant (name, ctors)
        when List.for_all (fun (_, fields) ->
            List.for_all is_scalar_field_ty fields) ctors ->
        Hashtbl.replace _scalar_only name ()
      | _ -> ()) type_defs

(** True iff [ty] is a variant every one of whose constructor fields is a
    scalar — see the section comment. *)
let is_scalar_only_ty : Tir.ty -> bool = function
  | Tir.TCon (name, _) -> Hashtbl.mem _scalar_only name
  | _ -> false

(** True iff atom [a] is a reference to the variable named [name]. *)
let atom_is (name : string) : Tir.atom -> bool = function
  | Tir.AVar v -> String.equal v.Tir.v_name name
  | _ -> false

(** [list_any_idx f xs] — true iff [f i xs[i]] holds for some index [i]. *)
let list_any_idx (f : int -> 'a -> bool) (xs : 'a list) : bool =
  let rec go i = function
    | []     -> false
    | x :: t -> if f i x then true else go (i + 1) t
  in
  go 0 xs

(** Returns true iff [e] contains an [EAlloc(TCon(ctor_name, _), _)] where
    [ctor_name] starts with [base_type ^ "."]. This detects "reconstruct"
    patterns where a case branch allocates a same-type constructor, indicating
    an FBIP reuse opportunity that requires ownership of the scrutinee.
    This deliberately does NOT compare constructor arities: it only gates an
    OWNERSHIP decision (own the scrutinee so FBIP *may* reuse it), never a
    memory-reuse size — [Perceus.same_arity] performs the size-safety check
    on the $fbip$-encoded field count at the actual reuse site.  A false
    positive here costs an extra inc/dec pair, not memory safety. *)
let rec has_matching_alloc (base_type : string) (e : Tir.expr) : bool =
  let prefix = base_type ^ "." in
  let prefix_len = String.length prefix in
  let matches_type name =
    String.length name >= prefix_len
    && String.sub name 0 prefix_len = prefix
  in
  match e with
  | Tir.EAlloc (Tir.TCon (name, _), _) -> matches_type name
  | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) ->
    has_matching_alloc base_type e1 || has_matching_alloc base_type e2
  | Tir.ECase (_, branches, default) ->
    List.exists (fun br -> has_matching_alloc base_type br.Tir.br_body) branches
    || Option.fold ~none:false ~some:(has_matching_alloc base_type) default
  | Tir.ELetRec (fns, body) ->
    has_matching_alloc base_type body
    || List.exists (fun fn -> has_matching_alloc base_type fn.Tir.fn_body) fns
  | _ -> false

(** True iff [ty] is a defunctionalised closure environment struct (its ctor
    name is minted as ["$Clo_…"] by defun.ml).  Used to distinguish a closure
    allocation from an ordinary data allocation.

    Wave 3 Task 3 scoping note: [fn_kind] lives on [Tir.fn_def], but this
    predicate checks a [Tir.ty] (a [TCon] struct-type name from an EAlloc) —
    there is no fn_def in play here at all, so there is no flag to assert
    this against. defun.ml's [lift_lambda] mints the closure struct's TCon
    name (["$Clo_" ^ fn_name ^ "$" ^ uid]) and the [FnApply]-tagged apply
    fn_def's name (["fn_name$apply$uid"]) together from the same [lam_uid],
    so the two ARE correlated in principle — but asserting that correlation
    here would mean re-deriving and parsing the uid back out of the type
    name, which is exactly the kind of fragile re-derivation this task
    exists to eliminate, not add. Left unconverted; see the task report. *)
let is_clo_struct_ty : Tir.ty -> bool = function
  | Tir.TCon (n, _) -> Tir_names.is_clo_struct n
  | _ -> false

(** True iff the closure variable [clo] ESCAPES the current function in [e] —
    i.e. it is returned, stored in another allocation/record, or passed as a
    DATA argument to a call.  It does NOT escape when it is only:
    - the CALLEE of an indirect call ([ECallPtr(clo, …)]) — a local invocation
      (join points, immediately-applied lambdas), or
    - the thunk argument of [__try_call] / [__try_call_val], which invoke it and
      free it within the call (march_decrc, march_runtime.c) without retaining it.
    A non-escaping closure does not transfer ownership of its captured free
    variables to any longer-lived value — so those captures are borrowing dups
    (Perceus IncRC's them for the closure's owned ref, perceus.ml:425), not
    ownership transfers of the caller's reference.

    Wave 3 Task 3 scoping note on [is_try]: [__try_call]/[__try_call_val] are
    typecheck/eval BUILTINS (typecheck.ml's builtin type table, eval.ml's
    VBuiltin registrations) — they are never lowered to a TIR [fn_def], so no
    [fn_kind] flag exists for them to be checked against (a lookup by this
    name in any fn_def table would always miss). This check is call-target
    dispatch on a hardcoded builtin name, the same shape as the
    "task_spawn_steal"/"actor_reply" name checks elsewhere in this pipeline
    — not a synthesis-role classification — so there is nothing to convert
    or assert here; left as name-checking, unconverted. *)
let rec closure_escapes (clo : string) (e : Tir.expr) : bool =
  let is_try = Tir_names.is_try_call in
  match e with
  | Tir.EAtom a -> atom_is clo a                              (* returned *)
  | Tir.EAlloc (_, args) | Tir.EStackAlloc (_, args) | Tir.ETuple args ->
    List.exists (atom_is clo) args                           (* stored in a structure *)
  | Tir.ERecord fields -> List.exists (fun (_, a) -> atom_is clo a) fields
  | Tir.EUpdate (_, fields) -> List.exists (fun (_, a) -> atom_is clo a) fields
  | Tir.ECallPtr (fn_a, args) ->
    (match fn_a with
     (* __try_call / __try_call_val lower to an ECallPtr whose thunk is the
        ARGUMENT; they invoke it and free it within the call (march_decrc) without
        retaining it — so passing [clo] there is NOT an escape. *)
     | Tir.AVar v when is_try v.Tir.v_name -> false
     (* Otherwise: [clo] as the CALLEE ([fn_a]) is a local invocation (join
        points, immediately-applied lambdas) — not an escape; [clo] as a DATA
        ARGUMENT escapes. *)
     | _ -> List.exists (atom_is clo) args)
  | Tir.EApp (callee, args) ->
    (* __try_call* consume-and-free the thunk locally → not an escape. Any other
       call receiving [clo] as a data argument is treated as an escape. *)
    if is_try callee.Tir.v_name then false else List.exists (atom_is clo) args
  | Tir.ELet (v, e1, e2) ->
    closure_escapes clo e1
    || (not (String.equal v.Tir.v_name clo) && closure_escapes clo e2)
  | Tir.ELetRec (fns, body) ->
    closure_escapes clo body
    || List.exists (fun fn -> closure_escapes clo fn.Tir.fn_body) fns
  | Tir.ECase (_, branches, default) ->
    List.exists (fun br -> closure_escapes clo br.Tir.br_body) branches
    || Option.fold ~none:false ~some:(closure_escapes clo) default
  | Tir.ESeq (e1, e2) -> closure_escapes clo e1 || closure_escapes clo e2
  | _ -> false

(** Returns true iff [name] has at least one *owning* use in [e].

    An owning use is any position where the value is stored, returned, or
    passed to a callee that is itself not known to borrow that parameter.
    Uses that only read the value (ECase scrutinee, EField source, EApp at a
    borrowed position, EReuse source) are considered borrowing.

    [bm] is the current (possibly incomplete) borrow map used for inter-
    procedural queries; it improves across fixpoint iterations. *)
let rec owned_in (name : string) (bm : borrow_map) (e : Tir.expr) : bool =
  match e with

  (* ── Atoms ────────────────────────────────────────────────────────────── *)
  | Tir.EAtom (Tir.AVar v) ->
    (* Value is returned directly — owning *)
    String.equal v.Tir.v_name name
  | Tir.EAtom _ -> false

  (* ── Storage ──────────────────────────────────────────────────────────── *)
  | Tir.EAlloc (_, args) | Tir.EStackAlloc (_, args) | Tir.ETuple args ->
    List.exists (atom_is name) args

  | Tir.ERecord fields ->
    List.exists (fun (_, a) -> atom_is name a) fields

  | Tir.EUpdate (_, fields) ->
    (* The base record is a borrow use; new field values being stored are owning *)
    List.exists (fun (_, a) -> atom_is name a) fields

  (* ── Calls ────────────────────────────────────────────────────────────── *)
  | Tir.ECallPtr (fn_a, args) ->
    (* Unknown callee — conservative: any arg use is owning *)
    atom_is name fn_a || List.exists (atom_is name) args

  | Tir.EApp (callee, args) ->
    (* Known callee — owning iff the corresponding parameter is NOT borrowed *)
    list_any_idx (fun i a ->
      atom_is name a && not (is_borrowed bm callee.Tir.v_name i)
    ) args
    (* Note: using [name] as the callee function itself is not a data-owning
       use — it is just an indirect reference, treated as borrowing. *)

  (* ── Binding forms ────────────────────────────────────────────────────── *)
  (* Pure alias [let v = name in e2]: [v] carries [name]'s value forward with
     no refcount change.  Whether [name] is *owned* therefore depends solely on
     whether the alias [v] escapes in [e2] — NOT on the alias binding itself.
     Treating the rhs [EAtom(AVar name)] as an owning use (the generic [ELet]
     case below would, via the [EAtom(AVar)]="returned" rule) falsely marks the
     source owned.  Lower emits exactly this for destructured fields
     (`let p = $f1 in …`, often behind sibling field/join-point bindings), which
     over-owned linear-search helpers (table_get/tget) — making them consume the
     list and corrupt callers that reuse it after the search (Toml
     set_nested/table_has).  Honour shadowing: if [v] shadows [name], [name] is
     no longer in scope in [e2]. *)
  | Tir.ELet (v, Tir.EAtom (Tir.AVar src), e2)
    when String.equal src.Tir.v_name name
         && not (String.equal v.Tir.v_name name) ->
    owned_in v.Tir.v_name bm e2

  (* [name] is captured (as a free variable) by a CLOSURE [v = EAlloc($Clo_…,
     [fn_ptr; …captures…])] that does NOT escape the current function — it is
     only invoked locally ([ECallPtr(v, …)]: join points minted by join_points,
     immediately-applied lambdas) or consumed by [__try_call*].  A non-escaping
     closure never transfers ownership of its captured FVs to a longer-lived
     value, so the capture is a borrowing dup (Perceus IncRC's the FV for the
     closure's owned ref — perceus.ml:425), NOT a transfer of the caller's
     reference.  Classify [name] by its remaining uses in [e2] only — do NOT let
     the EAlloc capture (the generic case below) mark it owned.  Without this, a
     resource captured by a shared match continuation or a transaction/property
     guard (`__try_call_val(fn _ -> cb(conn))`, `match d do … Db.query(conn,…) …`
     whose branches share a conn-capturing join point) is wrongly inferred :own,
     so the whole call chain frees it while the caller still holds and uses it —
     a use-after-free (Depot Transaction.run/tx_begin → Migration.run →
     Db.close(conn)). *)
  | Tir.ELet (v, Tir.EAlloc (ty, args), e2)
    when is_clo_struct_ty ty
         && List.exists (atom_is name) args
         && not (String.equal v.Tir.v_name name)
         && not (closure_escapes v.Tir.v_name e2) ->
    owned_in name bm e2

  | Tir.ELet (v, e1, e2) ->
    owned_in name bm e1
    || (not (String.equal v.Tir.v_name name) && owned_in name bm e2)

  | Tir.ELetRec (fns, body) ->
    owned_in name bm body
    || List.exists (fun fn ->
         let shadowed =
           List.exists (fun p -> String.equal p.Tir.v_name name) fn.Tir.fn_params
         in
         not shadowed && owned_in name bm fn.Tir.fn_body
       ) fns

  (* ── Pattern matching ─────────────────────────────────────────────────── *)
  | Tir.ECase (scrutinee, branches, default) ->
    (* FBIP-aware: if the scrutinee IS our variable and any branch allocates
       a constructor of the same base type, this is a "reconstruct" pattern
       (e.g. match t { Leaf(n) -> Leaf(n+1) }).  FBIP needs ownership of the
       scrutinee to reuse its memory, so treat this as an owning use. *)
    let fbip_owns =
      atom_is name scrutinee &&
      (match scrutinee with
       | Tir.AVar v ->
         (match v.Tir.v_ty with
          | Tir.TCon (base_type, _) ->
            List.exists (fun br ->
              has_matching_alloc base_type br.Tir.br_body
            ) branches
          | _ -> false)
       | _ -> false)
    in
    (* Field-escape: if the scrutinee IS our variable (and its type is a heap
       constructor) and any branch uses any [br_var] in an owning position in
       the body, the scrutinee itself is an owning use.
       Pattern-match extraction gives the field's value without incrementing
       its refcount — the RC stays on the parent.  If the field then escapes
       (returned, stored, passed to an owning position), the caller receives
       an aliased pointer without ownership: the parent still holds the same
       rc, so the next read of the parent would double-free or
       use-after-free the child (this is the "second read returns None" /
       local RC underflow class of bug).
       Note we intentionally do NOT gate on the [br_var]'s own [v_ty]:
       [Lower] creates [br_vars] with a placeholder [TVar "_"] type even
       when the concrete constructor field is heap-carrying (e.g.
       [List(String)] inside [Box(...)]) and [Rc_types.borrow_eligible]
       returns false for [TVar _].
       For the same reason we also do NOT gate on the scrutinee's own type:
       closure-generated helpers (e.g. the [go] accumulator loop inside
       [List.map]) have their parameters typed as [TVar "_"] by Lower even
       after monomorphisation, so [borrow_eligible scrutinee.v_ty] would also be
       false for them — causing field-escape to be missed entirely. Since
       ECase is only generated for variant/tuple types that are always
       heap-allocated in March, any [AVar] scrutinee is conservatively safe
       to treat as potentially RC-carrying.
       We follow through simple let-aliasing ([let v = x in ...] where [x] is
       the name we are tracking): such lets merely rename the alias without
       escaping it.  This avoids over-promotion for the common pattern
       [match conn do | Conn(s) -> println(s) end] which compiles to
       [case conn of Conn($f) -> let s = $f in println(s)] — [$f] is
       assigned to [s] but [s] is then only borrowed, so no escape
       actually occurs. *)
    (* Note: [escapes_through] only follows DIRECT aliasing (`let v = src
       in ...`).  An optimisation pass that introduces an indirect alias
       (e.g. `let v = identity(src) in ...` where [identity] returns its
       argument unchanged) would not be tracked here.  The fallback to
       [owned_in name bm e] keeps that case safe: [owned_in] treats the call
       as owning iff its borrow map says so, so the worst case is a
       parameter being conservatively marked owned (perf hit, not a
       correctness bug).  If a future pass starts producing such patterns,
       extend this matcher with an [EApp] case that recognises identity-like
       wrappers (e.g. via a hard-coded set, or by inspecting the callee's
       borrow modes + return shape). *)
    let rec escapes_through (name : string) (e : Tir.expr) : bool =
      match e with
      | Tir.ELet (v, Tir.EAtom (Tir.AVar src), body)
        when String.equal src.Tir.v_name name ->
        (* [let v = name in body]: the alias [v] carries [name]'s rc forward.
           Check whether [v] (or any further alias) escapes in [body]; also
           honour shadowing of [name]. *)
        escapes_through v.Tir.v_name body
        || (not (String.equal v.Tir.v_name name)
            && owned_in name bm body)
      | _ -> owned_in name bm e
    in
    let field_escape_owns =
      atom_is name scrutinee &&
      (match scrutinee with
       | Tir.AVar v ->
         (* TTuple and TRecord: Perceus's scrutinee_borrowed mechanism already
            handles field escapes correctly via ECase — when the scrutinee is
            in live_after (borrowed), br_vars are added to live_after and
            EIncRC is emitted for any extracted field used at a non-last
            position.  Marking tuple/record params as "owned" here causes
            borrow inference to flip them to cfg:own, which prevents
            scrutinee_borrowed from firing and lets Perceus emit EDecRC on
            the extracted field string without a matching EIncRC — RC
            underflow when the same tuple is passed to the function in a loop.
            ADT (TCon) scrutinees keep the existing field_escape_owns check
            because FBIP reuse and ADT-specific ownership patterns need it. *)
         (match v.Tir.v_ty with
          | Tir.TTuple _ | Tir.TRecord _ -> false
          (* A variant with no heap-carrying field anywhere: an extracted
             field is a scalar, so the aliasing hazard this rule guards
             against cannot arise.  See [_scalar_only]. *)
          | t when is_scalar_only_ty t -> false
          | _ -> true)
       | _ -> false) &&
      List.exists (fun br ->
        List.exists (fun bv ->
          escapes_through bv.Tir.v_name br.Tir.br_body
        ) br.Tir.br_vars
      ) branches
    in
    let third = List.exists (fun br ->
      let shadowed =
        List.exists (fun v -> String.equal v.Tir.v_name name) br.Tir.br_vars
      in
      not shadowed && owned_in name bm br.Tir.br_body
    ) branches in
    let fourth = Option.fold ~none:false ~some:(owned_in name bm) default in
    fbip_owns || field_escape_owns || third || fourth

  (* ── Sequencing ───────────────────────────────────────────────────────── *)
  | Tir.ESeq (e1, e2) ->
    owned_in name bm e1 || owned_in name bm e2

  (* ── Read-only / RC management ────────────────────────────────────────── *)
  (* EField is a struct field read — not a storing use. *)
  (* EReuse is FBIP cell reuse — not treated as owning for the source value. *)
  | Tir.EField _ | Tir.EReuse _ | Tir.EFree _
  | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _ ->
    false

  (* TRMC.  EAllocHole STORES its operands into a fresh cell, exactly like
     EAlloc — an owning use.  ESetField likewise moves the stored value into
     the object; the TARGET is only mutated, which is not an owning use of
     the target itself. *)
  | Tir.EAllocHole (_, _, args, _) ->
    List.exists (fun a -> atom_is name a) args
  | Tir.ESetField (_, _, v) -> atom_is name v

(* ── Fixpoint inference ───────────────────────────────────────────────────── *)

(** Infer the borrow map for all functions in [m].

    Algorithm:
    1. Initialise all RC-needing parameters as borrowed (optimistic).
    2. For each function, for each currently-borrowed parameter, check whether
       any owning use exists in the function body using the current borrow_map.
       If so, flip the parameter to owned.
    3. Repeat until the map reaches a fixpoint (no more flips occur).

    Termination: parameters only transition borrowed → owned, never back.
    The iteration is bounded by the total number of RC-needing parameters.

    Params whose types are not [Rc_types.borrow_eligible] are left as
    [false] (owned / not relevant); the RC pass will not attempt to
    increment/decrement them regardless. *)
let _borrow_debug : bool Lazy.t =
  lazy (Sys.getenv_opt "MARCH_DEBUG_BORROW" <> None)

let print_borrow_map (m : Tir.tir_module) (bm : borrow_map) =
  Printf.eprintf "[borrow] %s\n" m.Tir.tm_name;
  List.iter (fun fn ->
    match StringMap.find_opt fn.Tir.fn_name bm with
    | None -> ()
    | Some modes ->
      let n = Array.length modes in
      if n = 0 then ()
      else begin
        let param_names = List.map (fun p -> p.Tir.v_name) fn.Tir.fn_params in
        let pairs = List.mapi (fun i p ->
          let borrowed = i < n && modes.(i) in
          if borrowed then Printf.sprintf "%s:borrow" p
          else Printf.sprintf "%s:own" p
        ) param_names in
        Printf.eprintf "  %s(%s)\n" fn.Tir.fn_name (String.concat ", " pairs)
      end
  ) m.Tir.tm_fns;
  Printf.eprintf "%!"

let infer_module ?(k_table : Kind.table option) (m : Tir.tir_module) : borrow_map =
  let k_table = match k_table with Some t -> t | None -> Kind.of_module m in
  (* Per-module: which variant types carry no heap field anywhere.  Consulted
     by [field_escape_owns] — see [_scalar_only]. *)
  set_scalar_only_types m.Tir.tm_types;
  (* Initialise: borrow-eligible params start as borrowed; others are false. *)
  let init =
    List.fold_left (fun acc fn ->
      let n = List.length fn.Tir.fn_params in
      let modes = Array.init n (fun i ->
        (* Param 0 of an apply function is [$clo], and it is OWNED by the
           callee per the closure-apply ABI — pinned here rather than left to
           the fixpoint, which cannot discover it: an apply function's only
           use of $clo is [EField] extraction of captured variables, and
           [owned_in]'s EField case is defined as non-owning, so $clo would
           stay borrow-classified forever.

           This pin is what makes [Perceus.insert_apply_fn_clo_drop] sound.
           There are TWO independent notions of "$clo is borrowed" and they
           must agree: this map (what CALLERS consult in Perceus's [EApp]
           case) and the per-function [borrowed] set (what suppresses the
           callee's own drop).  Flipping only the latter makes the caller
           filter $clo out of [non_borrowed_args] — emitting NO [EIncRC] even
           when the closure is live after the call — while the callee starts
           decrementing, so the callee releases the caller's only reference.
           A prior attempt did exactly that and produced 3 double-frees plus 8
           stdlib crashes.  With this pin [find_inc_vars] increments a
           live-after closure and transfers the reference when it is not.

           It must live in [init], NOT in the post-fixpoint extern seeding
           below: [owned_in] consults [is_borrowed] during iteration, so a
           late seed would leave callers-of-callers classified against the
           stale answer.

           The same pin covers every USER parameter of an apply function, for
           the same reason from the other side: every caller of a closure
           transfers a reference to each argument (Perceus's [ECallPtr] case,
           the C runtime's higher-order helpers), so a callee that left a
           read-only parameter borrowed never released it — one leaked
           argument per call, and an immortal one when the caller kept it.
           An owned parameter the body never uses is released at entry by
           [Perceus.insert_dead_apply_param_drops].  See [Clo_flags] for the
           whole convention. *)
        if Tir_names.is_apply_fn fn.Tir.fn_name then false
        else Kind.borrowable_of k_table (List.nth fn.Tir.fn_params i).Tir.v_ty
      ) in
      StringMap.add fn.Tir.fn_name modes acc
    ) StringMap.empty m.Tir.tm_fns
  in
  (* Fixpoint loop *)
  let rec iterate (bm : borrow_map) : borrow_map =
    let changed = ref false in
    let bm' =
      List.fold_left (fun acc fn ->
        let modes =
          match StringMap.find_opt fn.Tir.fn_name acc with
          | Some m -> Array.copy m
          | None   -> Array.make 0 false
        in
        List.iteri (fun i p ->
          if modes.(i) then begin
            (* Currently borrowed — check whether any owning use exists.
               Flip to owned if so. *)
            if owned_in p.Tir.v_name acc fn.Tir.fn_body then begin
              modes.(i) <- false;
              changed := true
            end
          end
        ) fn.Tir.fn_params;
        StringMap.add fn.Tir.fn_name modes acc
      ) bm m.Tir.tm_fns
    in
    if !changed then iterate bm' else bm'
  in
  let result = iterate init in
  (* Seed user-defined extern (FFI) functions: their heap arguments are
     borrowed by default (Phase 2 FFI ownership convention), so Perceus drops
     them caller-side after the call.  Without this seeding they fall through to
     the empty hardcoded [extern_borrow_table] → owned → the caller never frees
     the arg and a borrow-style binding leaks. *)
  let result =
    List.fold_left (fun acc (ed : Tir.extern_decl) ->
      (* A heap param is borrowed by default (caller frees after the call),
         EXCEPT when declared `consume`: ownership transfers to the binding,
         so it is NOT borrowed and Perceus does not emit a caller-side drop. *)
      let modes = Array.of_list (List.mapi (fun i pty ->
        let consumed = match List.nth_opt ed.Tir.ed_consumed i with
          | Some c -> c | None -> false in
        Kind.borrowable_of k_table pty && not consumed
      ) ed.Tir.ed_params) in
      StringMap.add ed.Tir.ed_march_name modes acc
    ) result m.Tir.tm_externs
  in
  if Lazy.force _borrow_debug then print_borrow_map m result;
  result
