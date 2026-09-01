(** Defunctionalization pass for the March TIR.

    Eliminates lambdas (ELetRec-as-value) by:
    1. Computing free variables of each lambda
    2. Creating TDClosure structs for each lambda's captured environment
    3. Lifting lambda bodies to top-level functions with free vars as leading params
    4. Replacing lambda creation sites with EAlloc of the closure struct
    5. Replacing indirect calls (EApp of TFn-typed non-top-level vars) with ECallPtr *)

module StringSet = Set.Make(String)

(** Names that are globally known and should never be treated as free
    variables: built-in operators, primitives, and list helpers. *)
let builtin_names : StringSet.t =
  List.fold_left (fun s n -> StringSet.add n s) StringSet.empty
    [ "+"; "-"; "*"; "/"; "%"; "negate";
      "+."; "-."; "*."; "/.";
      "<"; ">"; "<="; ">="; "&&"; "||";
      "=="; "!="; "++";
      "print"; "println"; "print_line"; "print_stderr"; "print_int"; "print_float";
      "int_to_string"; "float_to_string"; "bool_to_string"; "atom_to_string";
      "string_to_int"; "string_length"; "string_concat";
      "string_byte_length"; "string_byte_at"; "string_is_empty";
      "string_join"; "string_concat3";
      "read_line"; "io_read_line"; "read_byte"; "io_read_byte"; "not";
      "panic";
      "head"; "tail"; "is_nil";
      "to_string"; "respond"; "kill"; "is_alive";
      "send"; "spawn"; "actor_get_int";
      "task_spawn"; "task_await"; "task_await_unwrap";
      "task_yield"; "task_spawn_steal"; "task_reductions";
      (* Cancellation/race builtins — each has a dedicated codegen arm in
         llvm_emit (task_cancel_by_id/task_cancel/task_is_cancelled/
         task_cancel_token_new/task_spawn_with_cancel).  Without a builtin_names
         entry, defun treats a reference to one (e.g. `List.each(rest, fn t ->
         task_cancel_by_id(t))` in Task.race/any) as a first-class function and
         emits a `@task_cancel_by_id$clo_wrap` trampoline whose body calls the
         non-existent `@task_cancel_by_id` (only the C symbol
         `@march_task_cancel_by_id` exists) → `use of undefined value`. *)
      "task_cancel_by_id"; "task_cancel"; "task_is_cancelled";
      "task_cancel_token_new"; "task_spawn_with_cancel";
      "get_work_pool";
      (* Signal.watch builtins — keep as EApp for dedicated codegen *)
      "signal_watch"; "signal_unwatch"; "signal_raise_self";
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
      (* Extended string builtins *)
      "string_contains"; "string_starts_with"; "string_ends_with";
      "string_slice"; "string_split"; "string_split_first";
      "string_replace"; "string_replace_all";
      "string_to_lowercase"; "string_to_uppercase";
      "string_trim"; "string_trim_start"; "string_trim_end";
      "string_repeat"; "string_reverse";
      "string_pad_left"; "string_pad_right";
      "string_grapheme_count"; "string_index_of"; "string_index_of_from";
      "string_last_index_of";
      "string_to_float";
      (* List builtins *)
      "list_append"; "list_concat";
      (* File/Dir builtins *)
      "file_exists"; "dir_exists";
      "file_open"; "file_close"; "file_read"; "file_read_line"; "file_read_chunk";
      "file_write"; "file_append"; "file_delete"; "file_copy"; "file_rename"; "file_stat";
      "file_create_dir"; "file_create_dir_all";
      "dir_mkdir"; "dir_mkdir_p"; "dir_rmdir"; "dir_rm_rf"; "dir_list"; "dir_list_full";
      "process_argv";
      "process_env"; "process_set_env"; "process_cwd"; "process_exit";
      "process_pid"; "process_spawn_sync"; "process_spawn_lines";
      "process_spawn_async"; "process_read_line"; "process_write"; "process_kill_proc"; "process_wait_proc";
      (* TCP/network builtins *)
      "tcp_connect"; "tcp_close"; "tcp_listen"; "tcp_accept"; "tcp_local_port";
      "tcp_send_all"; "tcp_recv_all"; "tcp_recv_exact"; "tcp_recv_http"; "tcp_recv_http_headers";
      "tcp_recv_chunk"; "tcp_recv_chunked_frame";
      "tcp_recv_chunk_timeout"; "tcp_set_recv_timeout"; "tcp_recv_timeout";
      (* HTTP builtins *)
      "http_parse_request"; "http_serialize_response"; "http_server_listen";
      "http_serialize_request"; "http_parse_response";
      (* WebSocket builtins *)
      "ws_handshake"; "ws_recv"; "ws_send"; "ws_select";
      (* CSV builtins *)
      "csv_open"; "csv_next_row"; "csv_close";
      (* Resource ownership *)
      "own";
      (* Capability builtins *)
      "cap_narrow"; "root_cap"; "mint_cap"; "cap_impl"; "cap_dict";
      (* Monitor/supervision builtins *)
      "demonitor"; "monitor"; "mailbox_size"; "sched_stat"; "actor_set_mailbox_limit";
      "run_until_idle"; "register_resource"; "get_cap";
      (* Named registry (Task 4) *)
      "actor_register"; "actor_unregister"; "actor_whereis"; "actor_registered";
      "send_checked"; "revoke_cap"; "is_cap_valid";
      "pid_of_int"; "get_actor_field";
      (* Comparison builtins used by derived Ord instances *)
      "march_compare_int"; "march_compare_float"; "march_compare_string";
      (* Hash builtins used by derived Hash instances *)
      "march_hash_int"; "march_hash_float"; "march_hash_string"; "march_hash_bool";
      (* Type-erased formatter — Show$String.show's body (lib/tir/lower.ml).
         Without this entry Defun treats the call as a closure application and
         emits `march_value_to_string._0(march_value_to_string, x)`, which on the
         JS backend is a reference to a symbol that does not exist. *)
      "march_value_to_string";
      (* Bitwise integer builtins *)
      "int_and"; "int_or"; "int_xor"; "int_not"; "int_shl"; "int_shr"; "int_popcount";
      (* IOList builtins *)
      "iolist_hash_fnv1a";
      (* HTTP server spawn/wait builtins *)
      "http_server_spawn_n"; "http_server_wait";
      (* Char/byte conversion builtins *)
      "byte_to_char"; "char_is_alphanumeric"; "char_is_whitespace";
      (* Char builtins *)
      "char_from_int"; "char_to_int"; "char_is_alpha"; "char_is_digit";
      "char_is_lowercase"; "char_is_uppercase"; "char_to_lowercase"; "char_to_uppercase";
      (* Logger builtins *)
      "logger_set_level"; "logger_get_level"; "logger_add_context";
      "logger_clear_context"; "logger_get_context"; "logger_write";
      (* Integer builtins *)
      "int_abs"; "int_pow"; "int_max_value"; "int_min_value";
      "int_div"; "int_mod"; "int_div_euclid"; "int_mod_euclid";
      (* Float builtins *)
      "float_to_int"; "float_from_string"; "float_is_nan"; "float_is_infinite";
      "float_infinity"; "float_neg_infinity"; "float_nan"; "float_epsilon";
      (* TLS builtins *)
      "tls_connect"; "tls_accept"; "tls_close"; "tls_read"; "tls_read_timeout"; "tls_write";
      "tls_client_ctx"; "tls_server_ctx"; "tls_ctx_free";
      "tls_negotiated_alpn"; "tls_peer_cn";
      (* Actor builtins *)
      "actor_call"; "actor_cast"; "actor_reply"; "self"; "receive";
      (* actor_send_after/actor_cancel_timer (specs/progress/2026-08-12-
         language-level-timers.md) *)
      "actor_send_after"; "actor_cancel_timer";
      (* String conversion builtins *)
      "string_chars"; "string_from_chars";
      "string_to_codepoints"; "string_from_codepoint";
      (* Unix/time builtins *)
      "unix_time"; "unix_time_ms";
      (* Process self-inspection builtins *)
      "peak_rss_bytes"; "live_allocs";
      (* Comparison / hash builtins *)
      "compare"; "compare_int"; "compare_float"; "compare_string";
      (* Record builtins *)
      "record_get"; "record_put"; "record_has_key"; "record_keys";
      "record_values"; "record_entries"; "record_from_list";
      (* JSON builtins *)
      "to_json"; "from_json";
      (* HTML builtins *)
      "html_auto_escape";
      "html_escape_ctx";
      (* Show builtins *)
      "show"; "to_string";
      (* Native array builtins *)
      "native_int_arr_make"; "native_int_arr_get"; "native_int_arr_set";
      "native_int_arr_length"; "native_int_arr_from_list"; "native_int_arr_to_list";
      "native_int_arr_map"; "native_int_arr_map2"; "native_int_arr_to_float_arr";
      "native_int_arr_fold"; "native_int_arr_sum";
      "native_int_arr_min"; "native_int_arr_max"; "native_int_arr_sumsq_dev";
      "native_float_arr_make"; "native_float_arr_get"; "native_float_arr_set";
      "native_float_arr_length"; "native_float_arr_from_list"; "native_float_arr_to_list";
      "native_float_arr_map"; "native_float_arr_map2"; "native_float_arr_fold"; "native_float_arr_sum";
      "native_float_arr_min"; "native_float_arr_max"; "native_float_arr_sumsq_dev";
      (* Narrow-width native array builtins — f32/i32/u8 (P10 narrow types) *)
      "native_f32_arr_make"; "native_f32_arr_get"; "native_f32_arr_set";
      "native_f32_arr_length"; "native_f32_arr_from_list"; "native_f32_arr_to_list";
      "native_f32_arr_map"; "native_f32_arr_map2"; "native_f32_arr_sum"; "native_f32_arr_fold";
      "native_i32_arr_make"; "native_i32_arr_get"; "native_i32_arr_set";
      "native_i32_arr_length"; "native_i32_arr_from_list"; "native_i32_arr_to_list";
      "native_i32_arr_map"; "native_i32_arr_map2"; "native_i32_arr_sum"; "native_i32_arr_fold";
      "native_u8_arr_make"; "native_u8_arr_get"; "native_u8_arr_set";
      "native_u8_arr_length"; "native_u8_arr_from_list"; "native_u8_arr_to_list";
      "native_u8_arr_map"; "native_u8_arr_map2"; "native_u8_arr_sum"; "native_u8_arr_fold";
      "native_float_to_f32_arr"; "native_f32_to_float_arr";
      "native_int_to_i32_arr"; "native_i32_to_int_arr";
      "native_int_to_u8_arr"; "native_u8_to_int_arr";
      "native_i32_to_f32_arr"; "native_u8_to_f32_arr";
      (* Simd builtins — explicit 128-bit SIMD vector types
         (F32x4/F64x2/I32x4/I64x2/U8x16). 127 names per the op grid in
         docs/superpowers/plans/2026-08-10-simd-vector-types.md. *)
      (* f32x4 *)
      "simd_f32x4_splat"; "simd_f32x4_make"; "simd_f32x4_extract";
      "simd_f32x4_replace"; "simd_f32x4_load"; "simd_f32x4_store";
      "simd_f32x4_eq"; "simd_f32x4_lt"; "simd_f32x4_gt";
      "simd_f32x4_and"; "simd_f32x4_or"; "simd_f32x4_xor";
      "simd_f32x4_not"; "simd_f32x4_select"; "simd_f32x4_any";
      "simd_f32x4_all"; "simd_f32x4_first_set"; "simd_f32x4_add";
      "simd_f32x4_sub"; "simd_f32x4_mul"; "simd_f32x4_div";
      "simd_f32x4_min"; "simd_f32x4_max"; "simd_f32x4_fma";
      "simd_f32x4_sqrt"; "simd_f32x4_sum"; "simd_f32x4_hmin";
      "simd_f32x4_hmax";
      (* f64x2 *)
      "simd_f64x2_splat"; "simd_f64x2_make"; "simd_f64x2_extract";
      "simd_f64x2_replace"; "simd_f64x2_load"; "simd_f64x2_store";
      "simd_f64x2_eq"; "simd_f64x2_lt"; "simd_f64x2_gt";
      "simd_f64x2_and"; "simd_f64x2_or"; "simd_f64x2_xor";
      "simd_f64x2_not"; "simd_f64x2_select"; "simd_f64x2_any";
      "simd_f64x2_all"; "simd_f64x2_first_set"; "simd_f64x2_add";
      "simd_f64x2_sub"; "simd_f64x2_mul"; "simd_f64x2_div";
      "simd_f64x2_min"; "simd_f64x2_max"; "simd_f64x2_fma";
      "simd_f64x2_sqrt"; "simd_f64x2_sum"; "simd_f64x2_hmin";
      "simd_f64x2_hmax";
      (* i32x4 *)
      "simd_i32x4_splat"; "simd_i32x4_make"; "simd_i32x4_extract";
      "simd_i32x4_replace"; "simd_i32x4_load"; "simd_i32x4_store";
      "simd_i32x4_eq"; "simd_i32x4_lt"; "simd_i32x4_gt";
      "simd_i32x4_and"; "simd_i32x4_or"; "simd_i32x4_xor";
      "simd_i32x4_not"; "simd_i32x4_select"; "simd_i32x4_any";
      "simd_i32x4_all"; "simd_i32x4_first_set"; "simd_i32x4_add";
      "simd_i32x4_sub"; "simd_i32x4_mul"; "simd_i32x4_min";
      "simd_i32x4_max"; "simd_i32x4_shl"; "simd_i32x4_shr";
      "simd_i32x4_sum"; "simd_i32x4_hmin"; "simd_i32x4_hmax";
      (* i64x2 *)
      "simd_i64x2_splat"; "simd_i64x2_make"; "simd_i64x2_extract";
      "simd_i64x2_replace"; "simd_i64x2_load"; "simd_i64x2_store";
      "simd_i64x2_eq"; "simd_i64x2_lt"; "simd_i64x2_gt";
      "simd_i64x2_and"; "simd_i64x2_or"; "simd_i64x2_xor";
      "simd_i64x2_not"; "simd_i64x2_select"; "simd_i64x2_any";
      "simd_i64x2_all"; "simd_i64x2_first_set"; "simd_i64x2_add";
      "simd_i64x2_sub"; "simd_i64x2_mul"; "simd_i64x2_min";
      "simd_i64x2_max"; "simd_i64x2_shl"; "simd_i64x2_shr";
      "simd_i64x2_sum"; "simd_i64x2_hmin"; "simd_i64x2_hmax";
      (* u8x16 *)
      "simd_u8x16_splat"; "simd_u8x16_make"; "simd_u8x16_extract";
      "simd_u8x16_replace"; "simd_u8x16_load"; "simd_u8x16_store";
      "simd_u8x16_eq"; "simd_u8x16_lt"; "simd_u8x16_gt";
      "simd_u8x16_and"; "simd_u8x16_or"; "simd_u8x16_xor";
      "simd_u8x16_not"; "simd_u8x16_select"; "simd_u8x16_any";
      "simd_u8x16_all"; "simd_u8x16_first_set";
      (* RingBuf builtins — mutable fixed-capacity circular buffer *)
      "ring_buf_make"; "ring_buf_push"; "ring_buf_pop"; "ring_buf_get";
      "ring_buf_peek_oldest"; "ring_buf_peek_newest"; "ring_buf_size";
      "ring_buf_cap"; "ring_buf_clear"; "ring_buf_to_list";
      (* Typed array builtins *)
      "typed_array_create"; "typed_array_get"; "typed_array_set";
      "typed_array_length"; "typed_array_from_list"; "typed_array_to_list";
      "typed_array_map"; "typed_array_filter"; "typed_array_fold"; "typed_array_slice";
      (* Misc builtins *)
      "tap"; "panic_"; "todo_"; "unreachable_";
      (* Crypto / hash builtins — C-level functions callable without a module qualifier.
         These appear unqualified in stdlib code (session.march, csrf.march, etc.)
         and must be treated as top-level to avoid ECallPtr generation. *)
      "hmac_sha256"; "pbkdf2_sha256";
      "sha256"; "sha512";
      "base64_encode"; "base64_decode";
      "random_bytes";
      "bytes_to_u8_arr"; "u8_arr_to_bytes";
      "stdlib_sha256"; "stdlib_sha512";
      "stdlib_base64_encode"; "stdlib_base64_decode";
      "stdlib_random_bytes";
      (* System introspection builtins — eval-only in interpreter; in compiled mode
         these map to C stub functions that return sensible defaults. *)
      "sys_uptime_ms"; "sys_heap_bytes"; "sys_word_size";
      "sys_minor_gcs"; "sys_major_gcs";
      "sys_actor_count"; "sys_cpu_count";
      "sys_cpu_load_milli"; "sys_mem_total_bytes"; "sys_mem_available_bytes";
      "sys_os"; "sys_arch";
      "march_version";
      (* UUID / identity builtins *)
      "uuid_v4";
      (* Session-typed channel builtins *)
      "chan_new"; "chan_send"; "chan_recv"; "chan_close";
      "chan_choose"; "chan_offer";
      (* Multi-party session type builtins *)
      "mpst_new"; "mpst_send"; "mpst_recv"; "mpst_close";
      (* Distributed OTP L4 — function-by-identity remote registry *)
      "remote_ref_hashes"; "remote_register_stub"; "remote_count" ]

(* ── Phase 0: collect top-level names ────────────────────────────── *)

let collect_top_level_names (m : Tir.tir_module) : StringSet.t =
  let user_fns = List.fold_left (fun s fn ->
      StringSet.add fn.Tir.fn_name s
    ) StringSet.empty m.Tir.tm_fns in
  StringSet.union user_fns builtin_names

(* ── Phase 1: free variable analysis ─────────────────────────────── *)

(** Collect free variables of an expression.
    [bound] is the set of locally-bound names.
    [tl] is the set of top-level function names.
    Returns an association list of (name, ty) with no duplicates, sorted by name. *)
let free_vars_of_expr (top_level : StringSet.t) (body : Tir.expr) (params : Tir.var list) :
    Tir.var list =
  (* Result stored as a name→var map to preserve linearity and avoid duplicates *)
  let result : (string, Tir.var) Hashtbl.t = Hashtbl.create 8 in

  let add_fv (v : Tir.var) =
    if not (Hashtbl.mem result v.Tir.v_name) then
      Hashtbl.add result v.Tir.v_name v
  in

  let fv_var (v : Tir.var) (bound : StringSet.t) =
    if StringSet.mem v.Tir.v_name bound || StringSet.mem v.Tir.v_name top_level
       (* Collision-dispatch sentinels ([Mono] → [Llvm_dispatch]) are globally
          known callees resolved directly at LLVM emission — never free
          variables to capture into a closure. *)
       || Dispatch_registry.is_sentinel v.Tir.v_name then ()
    else add_fv v
  in

  let fv_atom (a : Tir.atom) (bound : StringSet.t) =
    match a with
    | Tir.AVar v -> fv_var v bound
    | Tir.ADefRef _ -> ()  (* global/top-level ref, not a local free var *)
    | Tir.ALit _ -> ()
  in

  let rec fv_expr (e : Tir.expr) (bound : StringSet.t) =
    match e with
    | Tir.EAtom a -> fv_atom a bound
    | Tir.EApp (f, args) ->
      fv_var f bound;
      List.iter (fun a -> fv_atom a bound) args
    | Tir.ECallPtr (f, args) ->
      fv_atom f bound;
      List.iter (fun a -> fv_atom a bound) args
    | Tir.ELet (v, e1, e2) ->
      fv_expr e1 bound;
      fv_expr e2 (StringSet.add v.Tir.v_name bound)
    | Tir.ELetRec (fns, body) ->
      let fn_names = List.fold_left (fun s fn -> StringSet.add fn.Tir.fn_name s)
          StringSet.empty fns in
      let inner = StringSet.union bound fn_names in
      List.iter (fun fn ->
        let inner_params = List.fold_left (fun s p -> StringSet.add p.Tir.v_name s)
            inner fn.Tir.fn_params in
        fv_expr fn.Tir.fn_body inner_params
      ) fns;
      fv_expr body inner
    | Tir.ECase (a, brs, def) ->
      fv_atom a bound;
      List.iter (fun (br : Tir.branch) ->
        let bound' = List.fold_left (fun s v -> StringSet.add v.Tir.v_name s)
            bound br.Tir.br_vars in
        fv_expr br.Tir.br_body bound'
      ) brs;
      (match def with Some e -> fv_expr e bound | None -> ())
    | Tir.ETuple atoms ->
      List.iter (fun a -> fv_atom a bound) atoms
    | Tir.ERecord fields ->
      List.iter (fun (_, a) -> fv_atom a bound) fields
    | Tir.EField (a, _) -> fv_atom a bound
    | Tir.EUpdate (a, fields) ->
      fv_atom a bound;
      List.iter (fun (_, a) -> fv_atom a bound) fields
    | Tir.EAlloc (_, args) | Tir.EStackAlloc (_, args) ->
      List.iter (fun a -> fv_atom a bound) args
    | Tir.EAllocHole (tok, _, args, _) ->
      Option.iter (fun a -> fv_atom a bound) tok;
      List.iter (fun a -> fv_atom a bound) args
    | Tir.ESetField (o, _, v) -> fv_atom o bound; fv_atom v bound
    | Tir.EFree a -> fv_atom a bound
    | Tir.EIncRC a | Tir.EAtomicIncRC a -> fv_atom a bound
    | Tir.EDecRC a | Tir.EAtomicDecRC a -> fv_atom a bound
    | Tir.EReuse (a, _, args) ->
      fv_atom a bound;
      List.iter (fun a -> fv_atom a bound) args
    | Tir.ESeq (e1, e2) ->
      fv_expr e1 bound;
      fv_expr e2 bound
  in

  (* Initial bound = the lambda's own params *)
  let initial_bound = List.fold_left (fun s p -> StringSet.add p.Tir.v_name s)
      StringSet.empty params in
  fv_expr body initial_bound;
  (* Return sorted by name for determinism *)
  let pairs = Hashtbl.fold (fun k v acc -> (k, v) :: acc) result [] in
  let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) pairs in
  List.map snd sorted

(** A detected lambda with its free variables. *)
type lambda_info = {
  lam_fn           : Tir.fn_def;           (* the original fn_def inside ELetRec *)
  lam_fvs          : Tir.var list;             (* free variables, sorted by name, with linearity preserved *)
  lam_is_recursive : bool;                 (* body refers to fn's own name *)
  lam_uid          : int;                  (* globally unique id — used to disambiguate
                                              multiple lambdas with the same fn_name *)
}

let lambda_counter : int ref = ref 0
let fresh_lambda_uid () = let n = !lambda_counter in incr lambda_counter; n

(** Read the current lambda counter value (for persisting to cache). *)
let get_lambda_counter () = !lambda_counter

(** Restore the lambda counter (when loading from cache, set it above all
    prelude-compiled UIDs so fresh REPL fragments never reuse a prelude UID). *)
let set_lambda_counter n = lambda_counter := n

(** Collect all lambdas from all top-level fn bodies.

    [bound] tracks every name bound in the ENCLOSING lexical scope at the
    current point (the host fn's params, lets, case-arm vars, outer lambda
    names/params).  A lambda's free-var analysis must treat such a name as
    capturable even when a top-level fn shares it: local binders shadow
    top-level fns.  Before this, a stdlib HOF param captured by an inner
    lambda (e.g. `List.map`'s `f`, closed over by its `go` accumulator) was
    silently NOT captured whenever the user program defined a top-level fn
    of the same name — phase 3 then left the call as a direct `@f`, linking
    to the user's unrelated function (segfault when compiled; undefined
    `_f` at REPL-JIT dlopen).  Sibling of the phase-3 case-B shadowing fix
    below — this is the capture-side half. *)
let collect_lambdas (m : Tir.tir_module) (top_level : StringSet.t) : lambda_info list =
  let lambdas = ref [] in

  let add_bound bound (vs : Tir.var list) =
    List.fold_left (fun s (v : Tir.var) -> StringSet.add v.Tir.v_name s) bound vs
  in

  let rec collect_expr (bound : StringSet.t) (e : Tir.expr) =
    match e with
    | Tir.ELetRec ([fn], Tir.EAtom (Tir.AVar ref_var))
      when fn.Tir.fn_name = ref_var.Tir.v_name ->
      (* Names bound in the enclosing scope shadow same-named top-level fns,
         so they must stay eligible for capture. *)
      let top_level_eff = StringSet.diff top_level bound in
      (* Check for self-recursion before excluding self from free vars.
         Detect recursion with fn.fn_name REMOVED from the top-level exclusion
         set: a local fn whose name collides with a top-level fn (e.g. a stdlib
         helper `go` and a user top-level `go`) would otherwise have its own
         self-reference dropped as a "top-level global", so recursion goes
         undetected — the lifted apply then never binds `self = $clo` and the
         self-call links to the SAME-NAMED top-level function (silently calling
         the wrong code). The capture set [fvs_raw] still uses the full
         [top_level_eff] so genuine top-level refs are not captured. *)
      let rec_fvs = free_vars_of_expr (StringSet.remove fn.Tir.fn_name top_level_eff)
                      fn.Tir.fn_body fn.Tir.fn_params in
      let is_recursive = List.exists (fun (v : Tir.var) -> v.Tir.v_name = fn.Tir.fn_name) rec_fvs in
      let fvs_raw = free_vars_of_expr top_level_eff fn.Tir.fn_body fn.Tir.fn_params in
      (* Exclude the function's own name from free variables: recursive
         calls use $clo in the lifted apply fn, so self-capture would
         create a circular allocation. *)
      let self_var : Tir.var = { Tir.v_name = fn.Tir.fn_name;
                                  v_ty = Tir.TPtr Tir.TUnit;
                                  v_lin = Tir.Unr } in
      let fvs = if is_recursive
                then free_vars_of_expr top_level_eff fn.Tir.fn_body
                       (self_var :: fn.Tir.fn_params)
                else fvs_raw in
      lambdas := { lam_fn = fn; lam_fvs = fvs; lam_is_recursive = is_recursive;
                   lam_uid = fresh_lambda_uid () } :: !lambdas;
      (* Recurse into the lambda body too — its own name and params are in
         scope there, on top of everything the enclosing scope bound. *)
      collect_expr (add_bound (StringSet.add fn.Tir.fn_name bound) fn.Tir.fn_params)
        fn.Tir.fn_body
    | Tir.ELetRec (fns, body) ->
      let bound' = List.fold_left (fun s fn -> StringSet.add fn.Tir.fn_name s)
          bound fns in
      List.iter (fun fn ->
        collect_expr (add_bound bound' fn.Tir.fn_params) fn.Tir.fn_body) fns;
      collect_expr bound' body
    | Tir.ELet (v, e1, e2) ->
      collect_expr bound e1;
      collect_expr (StringSet.add v.Tir.v_name bound) e2
    | Tir.ECase (_, brs, def) ->
      List.iter (fun (br : Tir.branch) ->
        collect_expr (add_bound bound br.Tir.br_vars) br.Tir.br_body) brs;
      (match def with Some e -> collect_expr bound e | None -> ())
    | Tir.ESeq (e1, e2) ->
      collect_expr bound e1; collect_expr bound e2
    | _ -> ()
  in

  List.iter (fun fn ->
    collect_expr (add_bound StringSet.empty fn.Tir.fn_params) fn.Tir.fn_body)
    m.Tir.tm_fns;
  List.rev !lambdas

(* ── Phase 2: closure struct + lifted fn generation ──────────────── *)

(** Build the new top-level lifted fn and TDClosure type def for a lambda.

    Closure convention: field 0 of every closure struct is the apply fn ptr
    (typed TPtr TUnit).  The apply fn takes (ptr $clo, original_params) and
    loads its own free variables from $clo at entry.  This lets ECallPtr call
    uniformly through field 0 without knowing the specific lambda statically. *)
let lift_lambda (lam : lambda_info) : Tir.type_def * Tir.fn_def =
  let fn = lam.lam_fn in
  let fvs = lam.lam_fvs in
  let clo_name = Tir_names.clo_struct_name ~fn_name:fn.Tir.fn_name ~lam_uid:lam.lam_uid in
  let apply_name = Tir_names.apply_fn_name ~fn_name:fn.Tir.fn_name ~lam_uid:lam.lam_uid in
  (* TDClosure struct: [fn_ptr: TPtr(TUnit), fv0_ty, fv1_ty, ...] *)
  let td = Tir.TDClosure (clo_name, Tir.TPtr Tir.TUnit :: List.map (fun v -> v.Tir.v_ty) fvs) in
  (* $clo parameter — opaque pointer to the closure struct itself *)
  let clo_param = { Tir.v_name = Tir_names.clo_param_name; v_ty = Tir.TPtr Tir.TUnit; v_lin = Tir.Unr } in
  (* Wrap the original body with ELet bindings that load each free variable
     from the closure struct.  Field indices: fn_ptr=0, fv[i]=i+1.
     Prepend a binding [let fn_name = $clo] so that recursive self-calls
     inside the body (rewritten to ECallPtr by phase 3) dispatch correctly
     through the closure pointer without capturing self as a free variable. *)
  (* For recursive lambdas, bind fn_name = $clo so that self-calls in the
     body (converted to ECallPtr by phase 3) dispatch through the closure. *)
  let add_self_binding body =
    if lam.lam_is_recursive then
      let self_var = { Tir.v_name = fn.Tir.fn_name;
                       v_ty = Tir.TFn (List.map (fun v -> v.Tir.v_ty) fn.Tir.fn_params,
                                       fn.Tir.fn_ret_ty);
                       v_lin = Tir.Unr } in
      Tir.ELet (self_var, Tir.EAtom (Tir.AVar clo_param), body)
    else body
  in
  let wrapped_body =
    add_self_binding (
      List.fold_right (fun (i, (fv : Tir.var)) acc ->
          let field_name = Tir_names.fv_field (i + 1) in
          let load_expr  = Tir.EField (Tir.AVar clo_param, field_name) in
          Tir.ELet (fv, load_expr, acc)
        ) (List.mapi (fun i fv -> (i, fv)) fvs) fn.Tir.fn_body)
  in
  let apply_fn : Tir.fn_def = {
    fn_name   = apply_name;
    fn_params = clo_param :: fn.Tir.fn_params;
    fn_ret_ty = fn.Tir.fn_ret_ty;
    fn_body   = wrapped_body;
    (* This IS the synthesis site Tir_names.is_apply_fn / the former
       perceus.ml + llvm_emit.ml name-sniffing copies were detecting. *)
    fn_kind   = Tir.FnApply;
  } in
  (td, apply_fn)

(* ── Phase 3: expression rewriting ───────────────────────────────── *)

(** Rewrite expressions:
    - Lambda creation sites → EAlloc of closure struct
    - Indirect calls (EApp of TFn-typed non-top-level var) → ECallPtr *)
let rewrite_expr (known_lambdas : (string * lambda_info) list)
    (top_level : StringSet.t) (init_bound : StringSet.t) (e : Tir.expr) : Tir.expr =
  (* [bound] tracks the names of locally-bound variables (params, let bindings,
     case-arm pattern vars, recursive-fn names) in scope at the current point.
     A call whose callee is locally bound must dispatch through a closure
     pointer — see case B. *)
  let add_params bound params =
    List.fold_left (fun s (p : Tir.var) -> StringSet.add p.Tir.v_name s) bound params
  in
  let rec rw bound = function
    (* A. Lambda creation site *)
    | Tir.ELetRec ([fn], Tir.EAtom (Tir.AVar ref_var))
      when fn.Tir.fn_name = ref_var.Tir.v_name ->
      (* Use physical equality to match the exact fn_def collected during phase 1.
         This avoids confusing two inner functions with the same user-visible name
         (e.g. multiple modules defining [fn go] — one in stdlib/list.march and
         another in a user file).  The collect phase stores lam_fn = fn (the
         actual OCaml value from the ELetRec), so [lam.lam_fn == fn] is true
         only for the lambda that was collected from THIS exact ELetRec node. *)
      (match List.find_opt (fun (_, lam) -> lam.lam_fn == fn) known_lambdas with
       | Some (_, lam) ->
         let apply_name = Tir_names.apply_fn_name ~fn_name:fn.Tir.fn_name ~lam_uid:lam.lam_uid in
         let fn_ptr_atom = Tir.AVar { Tir.v_name = apply_name;
                                       v_ty = Tir.TPtr Tir.TUnit;
                                       v_lin = Tir.Unr } in
         let fv_atoms = List.map (fun (v : Tir.var) -> Tir.AVar v) lam.lam_fvs in
         let clo_name = Tir_names.clo_struct_name ~fn_name:fn.Tir.fn_name ~lam_uid:lam.lam_uid in
         Tir.EAlloc (Tir.TCon (clo_name, []), fn_ptr_atom :: fv_atoms)
       | None ->
         (* Not a known lambda — rewrite children *)
         let inner = add_params (StringSet.add fn.Tir.fn_name bound) fn.Tir.fn_params in
         Tir.ELetRec ([{ fn with Tir.fn_body = rw inner fn.Tir.fn_body }],
                      Tir.EAtom (Tir.AVar ref_var)))

    (* B. Indirect call: EApp of a non-top-level var that is either function-typed
       (TFn / TVar — TVar "_" occurs when type_map is empty, e.g. stdlib precompile)
       OR a locally-bound value (a closure whose function type was erased to a
       concrete type — e.g. a closure threaded through a tuple field, which the
       checker may have typed as String).  Without this conversion the call stays
       as a direct @go invocation — an undefined symbol — and, crucially, Perceus's
       EApp liveness ignores the callee, so the closure variable is dropped before
       the call (use-after-free).  Converting to ECallPtr is always safe for
       non-top-level vars: they must be closure pointers allocated by an earlier
       ELetRec, and locally-bound names that are called are necessarily callable
       (closures), never operators/builtins (which are never let/param-bound). *)
    | Tir.EApp (f_var, args)
      when (not (Dispatch_registry.is_sentinel f_var.Tir.v_name))
        && (StringSet.mem f_var.Tir.v_name bound
        || (not (StringSet.mem f_var.Tir.v_name top_level)
            && (match f_var.Tir.v_ty with Tir.TFn _ | Tir.TVar _ -> true | _ -> false))) ->
      (* A locally-bound name (ELetRec/let/param) is a closure pointer and MUST
         dispatch through ECallPtr — even when a top-level function shares the
         name.  Otherwise a stdlib helper's local `go` (the canonical accumulator
         idiom) compiles to a direct `@go` call that links to a USER top-level
         `go` of the same name, silently calling the wrong function (e.g.
         List.length returning 0).  Locally-bound names shadow top-level, so the
         `bound` check must take priority over the top-level check. *)
      Tir.ECallPtr (Tir.AVar f_var, args)

    (* Recurse into all other forms *)
    | Tir.ELetRec (fns, body) ->
      let bound' =
        List.fold_left (fun s fn -> StringSet.add fn.Tir.fn_name s) bound fns in
      let fns' = List.map (fun fn ->
          { fn with Tir.fn_body = rw (add_params bound' fn.Tir.fn_params) fn.Tir.fn_body })
          fns in
      Tir.ELetRec (fns', rw bound' body)
    | Tir.ELet (v, e1, e2) ->
      Tir.ELet (v, rw bound e1, rw (StringSet.add v.Tir.v_name bound) e2)
    | Tir.ECase (a, brs, def) ->
      let brs' = List.map (fun (br : Tir.branch) ->
          { br with Tir.br_body = rw (add_params bound br.Tir.br_vars) br.Tir.br_body }
        ) brs in
      Tir.ECase (a, brs', Option.map (rw bound) def)
    | Tir.ESeq (e1, e2) ->
      Tir.ESeq (rw bound e1, rw bound e2)
    | e -> e
  in
  rw init_bound e

(* ── Entry point ─────────────────────────────────────────────────── *)

let defunctionalize (m : Tir.tir_module) : Tir.tir_module =
  (* Phase 0: top-level names *)
  let top_level = collect_top_level_names m in

  (* Phase 1: collect all lambdas and their free variables *)
  let lambdas = collect_lambdas m top_level in
  let known_lambdas = List.map (fun lam -> (lam.lam_fn.Tir.fn_name, lam)) lambdas in

  (* Phase 2: generate closure structs and lifted fns *)
  let (new_types, new_fns) = List.split (List.map lift_lambda lambdas) in

  (* Phase 3: rewrite all top-level fn bodies.  The initial bound set is the
     function's own parameters, so a call to a function-typed parameter whose
     type was erased still dispatches indirectly. *)
  let params_set fn =
    List.fold_left (fun s (p : Tir.var) -> StringSet.add p.Tir.v_name s)
      StringSet.empty fn.Tir.fn_params
  in
  let rewritten_fns = List.map (fun fn ->
      { fn with Tir.fn_body =
          rewrite_expr known_lambdas top_level (params_set fn) fn.Tir.fn_body }
    ) m.Tir.tm_fns in
  (* Also rewrite lifted apply fns (to handle nested lambdas) *)
  let rewritten_new_fns = List.map (fun fn ->
      { fn with Tir.fn_body =
          rewrite_expr known_lambdas top_level (params_set fn) fn.Tir.fn_body }
    ) new_fns in

  {
    m with
    Tir.tm_fns   = rewritten_fns @ rewritten_new_fns;
    Tir.tm_types = m.Tir.tm_types @ new_types;
  }
