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
  field_map : (string, (string * Tir.ty) list) Hashtbl.t;
  mutable ret_ty  : Tir.ty;
  fast_math : bool;
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
  (* User-defined extern function name mapping: march_name → c_name *)
  extern_map : (string, string) Hashtbl.t;
  (* Tracks the actual LLVM type stored in each alloca slot, keyed by slot name.
     Used to emit correct load types even when TIR var has unresolved TVar. *)
  var_llvm_ty : (string, string) Hashtbl.t;
}

let make_ctx ?(fast_math=false) () = {
  buf      = Buffer.create 4096;
  preamble = Buffer.create 1024;
  ctr      = 0; blk = 0; str_ctr = 0;
  ctor_info = Hashtbl.create 64;
  top_fns   = Hashtbl.create 64;
  field_map = Hashtbl.create 16;
  ret_ty   = Tir.TUnit;
  fast_math;
  var_slot    = Hashtbl.create 32;
  local_names = Hashtbl.create 32;
  poly_ctors  = Hashtbl.create 64;
  type_params = Hashtbl.create 16;
  emitted_wraps = Hashtbl.create 8;
  extra_fns = Buffer.create 1024;
  extern_map = Hashtbl.create 8;
  var_llvm_ty = Hashtbl.create 32;
}

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

let llvm_ty : Tir.ty -> string = function
  | Tir.TInt    -> "i64"
  | Tir.TFloat  -> "double"
  | Tir.TBool   -> "i64"   (* booleans as i64 for uniform field layout *)
  | Tir.TUnit   -> "i64"   (* unit = i64 0 *)
  | Tir.TString -> "ptr"
  | Tir.TCon _  -> "ptr"
  | Tir.TTuple _ -> "ptr"
  | Tir.TRecord _ -> "ptr"
  | Tir.TFn _   -> "ptr"
  | Tir.TPtr _  -> "ptr"
  | Tir.TVar _  -> "ptr"   (* pre-mono fallback *)

let llvm_ret_ty : Tir.ty -> string = function
  | Tir.TUnit -> "void"
  | t -> llvm_ty t

(** Return type of a function variable's type. *)
let fn_ret_tir (ty : Tir.ty) : Tir.ty =
  match ty with
  | Tir.TFn (_, ret) -> ret
  | other -> other

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
                 "string_byte_length"; "string_is_empty"; "string_to_int"; "string_join";
                 "println"; "print";
                 "int_to_string"; "float_to_string"; "bool_to_string";
                 "kill"; "is_alive"; "send"; "spawn"; "actor_get_int";
                 "task_spawn"; "task_await"; "task_await_unwrap";
                 "task_yield"; "task_spawn_steal"; "task_reductions";
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
                 (* Extended string builtins *)
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
                 (* Capability builtins *)
                 "cap_narrow";
                 (* Monitor/supervision builtins *)
                 "demonitor"; "monitor"; "mailbox_size";
                 "run_until_idle"; "register_resource"; "get_cap";
                 "send_checked"; "pid_of_int"; "get_actor_field";
                 (* Generic to_string *)
                 "to_string"]

let atom_is_builtin (atom : Tir.atom) =
  match atom with
  | Tir.AVar v -> is_builtin_fn v.Tir.v_name
  | _ -> false

(** TIR return type for known builtin/extern functions, overriding type info. *)
let builtin_ret_ty : string -> Tir.ty option = function
  | "panic"                       -> Some Tir.TUnit
  | "println" | "print"           -> Some Tir.TUnit
  | "int_to_string"               -> Some Tir.TString
  | "float_to_string"             -> Some Tir.TString
  | "bool_to_string"              -> Some Tir.TString
  | "string_concat" | "++"        -> Some Tir.TString
  | "string_eq"                   -> Some Tir.TInt
  | "string_byte_length"          -> Some Tir.TInt
  | "string_is_empty"             -> Some Tir.TBool
  | "string_to_int"               -> Some (Tir.TCon ("Option", [Tir.TInt]))
  | "string_join"                 -> Some Tir.TString
  | "kill"                        -> Some Tir.TUnit
  | "is_alive"                    -> Some Tir.TBool
  | "send"                        -> Some (Tir.TCon ("Option", [Tir.TUnit]))
  | "spawn"                        -> Some (Tir.TPtr Tir.TUnit)
  | "actor_get_int"               -> Some Tir.TInt
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
  (* Generic to_string *)
  | "to_string"                   -> Some Tir.TString
  | _ -> None

(** Mangle a March builtin name to the C runtime function name. *)
let mangle_extern : string -> string = function
  | "panic"         -> "march_panic"
  | "println"       -> "march_println"
  | "print"         -> "march_print"
  | "int_to_string" -> "march_int_to_string"
  | "float_to_string" -> "march_float_to_string"
  | "bool_to_string"  -> "march_bool_to_string"
  | "string_concat" | "++" -> "march_string_concat"
  | "string_eq"          -> "march_string_eq"
  | "string_byte_length" -> "march_string_byte_length"
  | "string_is_empty"    -> "march_string_is_empty"
  | "string_to_int"      -> "march_string_to_int"
  | "string_join"        -> "march_string_join"
  | "kill"               -> "march_kill"
  | "is_alive"      -> "march_is_alive"
  | "send"          -> "march_send"
  | "spawn"         -> "march_spawn"
  | "actor_get_int" -> "march_actor_get_int"
  | "tcp_listen"              -> "march_tcp_listen"
  | "tcp_accept"              -> "march_tcp_accept"
  | "tcp_recv_http"           -> "march_tcp_recv_http"
  | "tcp_send_all"            -> "march_tcp_send_all"
  | "tcp_close"               -> "march_tcp_close"
  | "http_parse_request"      -> "march_http_parse_request"
  | "http_serialize_response" -> "march_http_serialize_response"
  | "http_server_listen"      -> "march_http_server_listen"
  | "ws_handshake"            -> "march_ws_handshake"
  | "ws_recv"                 -> "march_ws_recv"
  | "ws_send"                 -> "march_ws_send"
  | "ws_select"               -> "march_ws_select"
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
  | "file_exists"  -> "march_file_exists"
  | "dir_exists"   -> "march_dir_exists"
  (* Capability builtins *)
  | "cap_narrow"         -> "march_cap_narrow"
  (* Monitor/supervision builtins *)
  | "demonitor"          -> "march_demonitor"
  | "monitor"            -> "march_monitor"
  | "mailbox_size"       -> "march_mailbox_size"
  | "run_until_idle"     -> "march_run_until_idle"
  | "register_resource"  -> "march_register_resource"
  | "get_cap"            -> "march_get_cap"
  | "send_checked"       -> "march_send_checked"
  | "pid_of_int"         -> "march_pid_of_int"
  | "get_actor_field"    -> "march_get_actor_field"
  (* Generic to_string *)
  | "to_string"          -> "march_value_to_string"
  | "main"          -> "march_main"   (* March main → march_main in LLVM *)
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
  | Tir.ALit (March_ast.Ast.LitAtom _)  -> ("i64",    "0")
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
    (* root_cap is a capability constant — represented as null ptr at runtime *)
    ("ptr", "null")
  | Tir.AVar v when v.Tir.v_name = "get_work_pool" ->
    (* Phase 1: work pool is a null sentinel *)
    ("ptr", "null")
  | Tir.AVar v when v.Tir.v_name = "root_cap" ->
    (* Capability token: in compiled mode, capabilities are opaque null pointers *)
    ("ptr", "null")
  | Tir.AVar v when Hashtbl.mem ctx.top_fns v.Tir.v_name
                 && (match v.Tir.v_ty with Tir.TFn _ -> true | _ -> false) ->
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
      (* We'll generate the wrapper function at the end.  For now, declare it. *)
      let nparams = match v.Tir.v_ty with Tir.TFn (ps, _) -> List.length ps | _ -> 0 in
      let ret_tir = fn_ret_tir v.Tir.v_ty in
      let target_ret = llvm_ret_ty ret_tir in
      let param_tys = List.init nparams (fun _ -> "ptr") in
      let all_params = "ptr" :: param_tys in  (* clo + original params *)
      let arg_names = List.init nparams (fun i -> Printf.sprintf "%%a%d" i) in
      let all_arg_decls = "%_clo" :: arg_names in
      let decl_str = String.concat ", " (List.map2 (fun t n -> t ^ " " ^ n) all_params all_arg_decls) in
      let call_args = String.concat ", " (List.map2 (fun t n -> t ^ " " ^ n) param_tys arg_names) in
      if target_ret = "void" then
        Buffer.add_string ctx.extra_fns
          (Printf.sprintf "define ptr @%s(%s) {\nentry:\n  call void @%s(%s)\n  ret ptr null\n}\n\n"
             wrap_name decl_str fn_name call_args)
      else
        Buffer.add_string ctx.extra_fns
          (Printf.sprintf "define ptr @%s(%s) {\nentry:\n  %%r = call %s @%s(%s)\n  ret ptr %%r\n}\n\n"
             wrap_name decl_str target_ret fn_name call_args)
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
  | Tir.AVar v when Hashtbl.mem ctx.top_fns v.Tir.v_name ->
    (* Top-level function reference — emit its address directly (for EApp callee) *)
    ("ptr", "@" ^ llvm_name (mangle_extern v.Tir.v_name))
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
  ptr

(* ── Constructor lookup ──────────────────────────────────────────────── *)

let ctor_entry ctx name n_args_fallback =
  match Hashtbl.find_opt ctx.ctor_info name with
  | Some e -> e
  | None   -> { ce_tag = 0; ce_fields = List.init n_args_fallback (fun _ -> Tir.TVar "_") }

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

(** Look up the sorted field list for a record type. *)
let get_record_fields ctx (ty : Tir.ty) : (string * Tir.ty) list =
  match ty with
  | Tir.TRecord fields -> fields   (* already sorted by name *)
  | Tir.TCon (name, _) ->
    (match Hashtbl.find_opt ctx.field_map name with
     | Some fields -> fields
     | None -> [])
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

(* ── Core expression emitter ─────────────────────────────────────────── *)

(** Emit [e] and return (llvm_type, llvm_value). Unit → ("i64","0"). *)
let rec emit_expr ctx (e : Tir.expr) : string * string =
  match e with

  (* ── Atoms ─────────────────────────────────────────────────────────── *)
  | Tir.EAtom atom -> emit_atom ctx atom

  (* ── Free-variable load from closure struct ────────────────────────── *)
  (* ELet(v, EField(clo, "$fvN"), body): load field N from the closure ptr.
     Generated by defun for apply fns using the closure-ptr convention. *)
  | Tir.ELet (v, Tir.EField (obj_atom, field_name), body)
    when String.length field_name > 3 && String.sub field_name 0 3 = "$fv" ->
    let field_idx =
      int_of_string (String.sub field_name 3 (String.length field_name - 3)) in
    let (_, obj_val) = emit_atom ctx obj_atom in
    let field_ty = llvm_ty v.Tir.v_ty in
    let fv = emit_load_field ctx obj_val field_idx field_ty in
    let slot = alloca_name ctx (llvm_name v.Tir.v_name) in
    emit ctx (Printf.sprintf "%%%s.addr = alloca %s" slot field_ty);
    emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" field_ty fv slot);
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
    ignore (emit_expr ctx e1);
    emit_expr ctx e2

  (* ── Arithmetic builtins ───────────────────────────────────────────── *)
  | Tir.EApp (f, [a; b]) when is_int_arith f.Tir.v_name ->
    let va = emit_atom_as ctx "i64" a in
    let vb = emit_atom_as ctx "i64" b in
    let r  = fresh ctx "ar" in
    emit ctx (Printf.sprintf "%s = %s i64 %s, %s" r (int_arith_op f.Tir.v_name) va vb);
    ("i64", r)

  | Tir.EApp (f, [a; b]) when is_int_cmp f.Tir.v_name ->
    let (ty_a, va) = emit_atom ctx a in
    let (ty_b, vb) = emit_atom ctx b in
    if ty_a = "ptr" && (f.Tir.v_name = "==" || f.Tir.v_name = "!=") then begin
      (* String equality: call march_string_eq which returns i64 (0 or 1) *)
      let r = fresh ctx "cr" in
      emit ctx (Printf.sprintf "%s = call i64 @march_string_eq(ptr %s, ptr %s)" r va vb);
      if f.Tir.v_name = "!=" then begin
        let nr = fresh ctx "ar" in
        emit ctx (Printf.sprintf "%s = xor i64 %s, 1" nr r);
        ("i64", nr)
      end else
        ("i64", r)
    end else begin
      let cmp = fresh ctx "cmp" in
      let r   = fresh ctx "ar" in
      if ty_a = "double" then begin
        (* Float comparison: use fcmp ordered predicates *)
        let fpred = match f.Tir.v_name with
          | "==" -> "oeq" | "!=" -> "one"
          | "<"  -> "olt" | "<=" -> "ole"
          | ">"  -> "ogt" | ">=" -> "oge"
          | s -> failwith ("unknown cmp: " ^ s)
        in
        emit ctx (Printf.sprintf "%s = fcmp %s double %s, %s" cmp fpred va vb);
      end else begin
        (* Coerce to i64 in case variables were loaded as ptr due to TVar type *)
        let va' = coerce ctx ty_a va "i64" in
        let vb' = coerce ctx ty_b vb "i64" in
        emit ctx (Printf.sprintf "%s = icmp %s i64 %s, %s" cmp (int_cmp_pred f.Tir.v_name) va' vb')
      end;
      emit ctx (Printf.sprintf "%s = zext i1 %s to i64" r cmp);
      ("i64", r)
    end

  | Tir.EApp (f, [a; b]) when is_float_arith f.Tir.v_name ->
    let va = emit_atom_as ctx "double" a in
    let vb = emit_atom_as ctx "double" b in
    let r  = fresh ctx "ar" in
    let op = float_arith_op f.Tir.v_name in
    let op_str = if ctx.fast_math then op ^ " fast" else op in
    emit ctx (Printf.sprintf "%s = %s double %s, %s" r op_str va vb);
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

  (* ── Task builtins (Phase 1: inline LLVM IR, no C runtime) ────────── *)
  (* Thunks are fn x -> expr (Int -> a).  task_spawn calls the closure
     with dummy arg 0, boxes result into a Task heap object.
     task_await_unwrap unboxes field 0 from the Task. *)

  (* task_spawn(thunk_closure) → call thunk(0), box result *)
  | Tir.EApp (f, [clo_atom]) when f.Tir.v_name = "task_spawn" ->
    let (_, clo_ptr) = emit_atom ctx clo_atom in
    (* Load apply fn from closure field 0 (offset 16 from header) *)
    let fn_ptr = emit_load_field ctx clo_ptr 0 "ptr" in
    (* Determine result type from thunk signature Int -> a *)
    let ret_ty = (match clo_atom with
      | Tir.AVar v ->
        (match v.Tir.v_ty with
         | Tir.TFn (_, ret) -> llvm_ty ret
         | _ -> "ptr")
      | _ -> "ptr")
    in
    (* Call apply(closure, 0) — defun convention: closure as 1st arg *)
    let result = fresh ctx "tsres" in
    emit ctx (Printf.sprintf "%s = call %s %s(ptr %s, i64 0)"
                result ret_ty fn_ptr clo_ptr);
    (* Box result into Task heap object *)
    let task_ptr = emit_heap_alloc ctx 0 1 in
    emit_store_field ctx task_ptr 0 ret_ty result;
    ("ptr", task_ptr)

  (* task_await_unwrap(task_ptr) → unbox field 0 *)
  | Tir.EApp (f, [a]) when f.Tir.v_name = "task_await_unwrap" ->
    let (_, task_ptr) = emit_atom ctx a in
    let inner_ty = match a with
      | Tir.AVar v ->
        (match v.Tir.v_ty with
         | Tir.TCon ("Task", [inner]) -> llvm_ty inner
         | _ -> "ptr")
      | _ -> "ptr"
    in
    let r = emit_load_field ctx task_ptr 0 inner_ty in
    (inner_ty, r)

  (* task_await(task_ptr) → always Ok in Phase 1; unbox + rebox as Ok *)
  | Tir.EApp (f, [a]) when f.Tir.v_name = "task_await" ->
    let (_, task_ptr) = emit_atom ctx a in
    let inner_ty = match a with
      | Tir.AVar v ->
        (match v.Tir.v_ty with
         | Tir.TCon ("Task", [inner]) -> llvm_ty inner
         | _ -> "ptr")
      | _ -> "ptr"
    in
    let val_v = emit_load_field ctx task_ptr 0 inner_ty in
    let ok_ptr = emit_heap_alloc ctx 1 1 in
    emit_store_field ctx ok_ptr 0 inner_ty val_v;
    ("ptr", ok_ptr)

  (* task_yield() → no-op in Phase 1 *)
  | Tir.EApp (f, []) when f.Tir.v_name = "task_yield" ->
    ("i64", "0")

  (* task_spawn_steal(pool, thunk_closure) → call thunk(0), box result *)
  | Tir.EApp (f, [_pool; clo_atom]) when f.Tir.v_name = "task_spawn_steal" ->
    let (_, clo_ptr) = emit_atom ctx clo_atom in
    let fn_ptr = emit_load_field ctx clo_ptr 0 "ptr" in
    let ret_ty = (match clo_atom with
      | Tir.AVar v ->
        (match v.Tir.v_ty with
         | Tir.TFn (_, ret) -> llvm_ty ret
         | _ -> "ptr")
      | _ -> "ptr")
    in
    let result = fresh ctx "tsres" in
    emit ctx (Printf.sprintf "%s = call %s %s(ptr %s, i64 0)"
                result ret_ty fn_ptr clo_ptr);
    let task_ptr = emit_heap_alloc ctx 0 1 in
    emit_store_field ctx task_ptr 0 ret_ty result;
    ("ptr", task_ptr)

  (* task_reductions() → 0 in Phase 1 *)
  | Tir.EApp (f, []) when f.Tir.v_name = "task_reductions" ->
    ("i64", "0")

  (* get_work_pool() → null sentinel in Phase 1 *)
  | Tir.EApp (f, []) when f.Tir.v_name = "get_work_pool" ->
    ("ptr", "null")

  (* ── General function call ─────────────────────────────────────────── *)
  | Tir.EApp (f, args) ->
    let arg_strs = List.map (fun a ->
        let (ty, v) = emit_atom ctx a in ty ^ " " ^ v
      ) args in
    let args_str = String.concat ", " arg_strs in
    let fname    = match Hashtbl.find_opt ctx.extern_map f.Tir.v_name with
      | Some c_name -> c_name
      | None -> mangle_extern f.Tir.v_name in
    (* Determine return type: check known builtins first, then TFn annotation *)
    let ret_tir  = match builtin_ret_ty f.Tir.v_name with
      | Some t -> t
      | None   -> fn_ret_tir f.Tir.v_ty
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

  (* ── Indirect call through closure ────────────────────────────────── *)
  (* fn_atom is a local var holding a ptr to a closure struct.
     Field 0 of the closure is the apply fn ptr.
     Convention: apply fn takes (ptr $clo, original_params…). *)
  | Tir.ECallPtr (fn_atom, args) ->
    let (_, clo_ptr) = emit_atom ctx fn_atom in
    let fn_ptr = emit_load_field ctx clo_ptr 0 "ptr" in
    let nargs = List.length args in
    let ret_tir = match fn_atom with
      | Tir.AVar v ->
        (match v.Tir.v_ty with
         | Tir.TFn (ps, ret) when List.length ps = nargs -> ret
         | Tir.TFn _ -> Tir.TVar "_"   (* partial application → returns closure (ptr) *)
         | other -> other)
      | _ -> Tir.TVar "_"
    in
    let ret_ty = llvm_ret_ty ret_tir in
    let orig_param_llvm_tys = match fn_atom with
      | Tir.AVar v ->
        (match v.Tir.v_ty with
         | Tir.TFn (ps, _) when List.length ps = nargs -> List.map llvm_ty ps
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
    ("ptr", ptr)

  | Tir.EAlloc (_, args) ->
    let n = List.length args in
    let ptr = emit_heap_alloc ctx 0 n in
    List.iteri (fun i atom ->
      let (ty, v) = emit_atom ctx atom in
      emit_store_field ctx ptr i ty v
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
    let n = List.length args in
    let ptr = emit_stack_alloc ctx n in
    List.iteri (fun i atom ->
      let (ty, v) = emit_atom ctx atom in
      emit_store_field ctx ptr i ty v
    ) args;
    ("ptr", ptr)

  (* ── FBIP reuse (conditional: check RC=1 before reusing in-place) ──── *)
  (* EReuse semantics: if RC=1, reuse in-place; else DecRC + alloc fresh.
     This is critical for correctness when the caller holds extra references
     (e.g. after IncRC before passing to a function). *)
  | Tir.EReuse (reuse_atom, Tir.TCon (ctor, _), args) ->
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
    (* Load RC and check if uniquely owned *)
    let rc = fresh ctx "rc" in
    emit ctx (Printf.sprintf "%s = load i64, ptr %s, align 8" rc rv);
    let is_unique = fresh ctx "uniq" in
    emit ctx (Printf.sprintf "%s = icmp eq i64 %s, 1" is_unique rc);
    let reuse_lbl = fresh_block ctx "fbip_reuse" in
    let fresh_lbl = fresh_block ctx "fbip_fresh" in
    let merge_lbl = fresh_block ctx "fbip_merge" in
    let result_slot = fresh ctx "fbip_slot" in
    emit ctx (Printf.sprintf "%s = alloca ptr" result_slot);
    emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
                     is_unique reuse_lbl fresh_lbl);
    (* Reuse branch: write tag/fields to original pointer *)
    emit_label ctx reuse_lbl;
    emit_store_tag ctx rv entry.ce_tag;
    List.iteri (fun i (field_ty, v_coerced) ->
      emit_store_field ctx rv i field_ty v_coerced
    ) arg_vals;
    emit ctx (Printf.sprintf "store ptr %s, ptr %s" rv result_slot);
    emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl);
    (* Fresh branch: DecRC original, alloc fresh, write tag/fields *)
    emit_label ctx fresh_lbl;
    emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" rv);
    let hp = emit_heap_alloc ctx entry.ce_tag (List.length args) in
    List.iteri (fun i (field_ty, v_coerced) ->
      emit_store_field ctx hp i field_ty v_coerced
    ) arg_vals;
    emit ctx (Printf.sprintf "store ptr %s, ptr %s" hp result_slot);
    emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl);
    (* Merge: load result *)
    emit_label ctx merge_lbl;
    let result = fresh ctx "fbip_r" in
    emit ctx (Printf.sprintf "%s = load ptr, ptr %s" result result_slot);
    ("ptr", result)

  | Tir.EReuse (reuse_atom, _, args) ->
    (* Non-TCon reuse: same conditional logic without ctor-specific fields *)
    let (_, rv) = emit_atom ctx reuse_atom in
    let arg_vals = List.map (fun atom ->
      let (ty, v) = emit_atom ctx atom in (ty, v)
    ) args in
    let rc = fresh ctx "rc" in
    emit ctx (Printf.sprintf "%s = load i64, ptr %s, align 8" rc rv);
    let is_unique = fresh ctx "uniq" in
    emit ctx (Printf.sprintf "%s = icmp eq i64 %s, 1" is_unique rc);
    let reuse_lbl = fresh_block ctx "fbip_reuse" in
    let fresh_lbl = fresh_block ctx "fbip_fresh" in
    let merge_lbl = fresh_block ctx "fbip_merge" in
    let result_slot = fresh ctx "fbip_slot" in
    emit ctx (Printf.sprintf "%s = alloca ptr" result_slot);
    emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
                     is_unique reuse_lbl fresh_lbl);
    emit_label ctx reuse_lbl;
    List.iteri (fun i (ty, v) ->
      emit_store_field ctx rv i ty v
    ) arg_vals;
    emit ctx (Printf.sprintf "store ptr %s, ptr %s" rv result_slot);
    emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl);
    emit_label ctx fresh_lbl;
    emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" rv);
    let hp = emit_heap_alloc ctx 0 (List.length args) in
    List.iteri (fun i (ty, v) ->
      emit_store_field ctx hp i ty v
    ) arg_vals;
    emit ctx (Printf.sprintf "store ptr %s, ptr %s" hp result_slot);
    emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl);
    emit_label ctx merge_lbl;
    let result = fresh ctx "fbip_r" in
    emit ctx (Printf.sprintf "%s = load ptr, ptr %s" result result_slot);
    ("ptr", result)

  (* ── RC ops ────────────────────────────────────────────────────────── *)
  (* Skip RC ops on builtins AND on top-level function references.
     Function addresses live in the code segment, not the heap, so calling
     march_incrc/decrc/free on them would corrupt memory or crash. *)
  | Tir.EIncRC atom
    when atom_is_builtin atom ||
         (match atom with Tir.AVar v -> Hashtbl.mem ctx.top_fns v.Tir.v_name | _ -> false) ->
    ("i64", "0")
  | Tir.EIncRC atom ->
    let (ty, v) = emit_atom ctx atom in
    if ty = "ptr" then
      emit ctx (Printf.sprintf "call void @march_incrc(ptr %s)" v);
    ("i64", "0")

  | Tir.EDecRC atom
    when atom_is_builtin atom ||
         (match atom with Tir.AVar v -> Hashtbl.mem ctx.top_fns v.Tir.v_name | _ -> false) ->
    ("i64", "0")
  | Tir.EDecRC atom ->
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
    let n = List.length atoms in
    let ptr = emit_heap_alloc ctx 0 n in
    List.iteri (fun i atom ->
      let (ty, v) = emit_atom ctx atom in
      emit_store_field ctx ptr i ty v
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
    ("ptr", ptr)

  (* ── Field access ──────────────────────────────────────────────────── *)
  | Tir.EField (obj_atom, field_name) ->
    let obj_ty = match obj_atom with
      | Tir.AVar v    -> v.Tir.v_ty
      | Tir.ADefRef _ -> Tir.TVar "_"
      | Tir.ALit _    -> Tir.TVar "_"
    in
    let (idx, field_ty) =
      (* Closure free-variable fields: "$fvN" — parse index from name directly
         since the closure pointer is opaque (TPtr TUnit) with no field_map. *)
      if String.length field_name > 3 && String.sub field_name 0 3 = "$fv" then
        let i = int_of_string (String.sub field_name 3 (String.length field_name - 3)) in
        (i, Tir.TPtr Tir.TUnit)   (* field type is opaque; let alloca use v_ty *)
      else
        field_index_for ctx obj_ty field_name
    in
    let (_, obj_val) = emit_atom ctx obj_atom in
    let fv = emit_load_field ctx obj_val idx (llvm_ty field_ty) in
    (llvm_ty field_ty, fv)

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

  let is_ptr_scrut =
    match scrut_atom with
    | Tir.AVar v ->
      (match v.Tir.v_ty with Tir.TBool | Tir.TInt -> false | _ -> true)
    | Tir.ALit (March_ast.Ast.LitBool _) | Tir.ALit (March_ast.Ast.LitInt _) -> false
    | _ -> scrut_ty = "ptr"
  in

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

  (* The scrutinee's TIR type — needed both for the switch tag lookup and for
     branch field binding.  Defined early so both uses see it. *)
  let scrut_tir_ty =
    match scrut_atom with Tir.AVar v -> v.Tir.v_ty | _ -> Tir.TUnit
  in

  (* Produce the type-qualified ctor_info key for a branch tag.
     When the scrutinee's type is TCon("List", _) and br_tag is "Cons", the key
     is "List.Cons" — matching the key format used by build_ctor_info and lower.ml. *)
  let qualified_br_key br_tag =
    match scrut_tir_ty with
    | Tir.TCon (type_name, _) -> type_name ^ "." ^ br_tag
    | _ -> br_tag
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
      (* trunc i64 -> i1, then br i1 *)
      let i1v = fresh ctx "bi" in
      emit ctx (Printf.sprintf "%s = trunc i64 %s to i1" i1v scrut_val);
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
        else ("i64", scrut_val)
      in

      (* Build switch arms *)
      let cases_str = List.map2 (fun br lbl ->
          let tag_str =
            if is_ptr_scrut then
              let e = ctor_entry ctx (qualified_br_key br.Tir.br_tag) 0 in
              string_of_int e.ce_tag
            else begin
              match int_of_string_opt br.Tir.br_tag with
              | Some n -> string_of_int n
              | None -> "0"
            end
            in
          Printf.sprintf "%s %s, label %%%s" sw_ty tag_str lbl
        ) branches branch_lbls in
      let cases_part = String.concat "\n      " cases_str in
      emit_term ctx (Printf.sprintf "switch %s %s, label %%%s [\n      %s\n  ]"
                       sw_ty sw_val default_lbl cases_part)
    end
  end;

  (* Helper: if body = ESeq(EDecRC(v), rest) where v.v_name = scrut_name,
     return (v, rest). Used to handle shared-value field IncRC below. *)
  let strip_scrut_decrc scrut_name body =
    match body with
    | Tir.ESeq (Tir.EDecRC (Tir.AVar v), rest)
      when String.equal v.Tir.v_name scrut_name -> Some (v, rest)
    | _ -> None
  in

  (* Emit branch blocks *)
  List.iter2 (fun br lbl ->
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
         | None -> br.Tir.br_body)
      | _ -> br.Tir.br_body
    in
    let (br_ty, br_val) = emit_expr ctx body_to_emit in
    let stored = coerce ctx br_ty br_val "ptr" in
    emit ctx (Printf.sprintf "store ptr %s, ptr %s" stored result_slot);
    emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl)
  ) branches branch_lbls;

  (* Default arm *)
  emit_label ctx default_lbl;
  (match default_opt with
   | None -> emit_term ctx "unreachable"
   | Some d ->
     let (d_ty, d_val) = emit_expr ctx d in
     let stored = coerce ctx d_ty d_val "ptr" in
     emit ctx (Printf.sprintf "store ptr %s, ptr %s" stored result_slot);
     emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl));

  emit_label ctx merge_lbl;
  let r = fresh ctx "case_r" in
  emit ctx (Printf.sprintf "%s = load ptr, ptr %s" r result_slot);
  ("ptr", r)

(* ── Function emitter ────────────────────────────────────────────────── *)

let emit_fn ctx (fn : Tir.fn_def) =
  Hashtbl.clear ctx.local_names;
  Hashtbl.clear ctx.var_slot;
  Hashtbl.clear ctx.var_llvm_ty;
  ctx.ret_ty <- fn.Tir.fn_ret_ty;
  let fn_llvm_name = mangle_extern fn.Tir.fn_name in
  let ret_ty       = llvm_ret_ty fn.Tir.fn_ret_ty in

  let params_str = String.concat ", " (List.map (fun (v : Tir.var) ->
      let vn = llvm_name v.Tir.v_name in
      llvm_ty v.Tir.v_ty ^ " %" ^ vn ^ ".arg"
    ) fn.Tir.fn_params) in

  Buffer.add_string ctx.buf
    (Printf.sprintf "\ndefine %s @%s(%s) {\nentry:\n" ret_ty fn_llvm_name params_str);

  (* Alloca + store for each parameter *)
  List.iter (fun (v : Tir.var) ->
    let ty = llvm_ty v.Tir.v_ty in
    let slot = alloca_name ctx (llvm_name v.Tir.v_name) in
    emit ctx (Printf.sprintf "%%%s.addr = alloca %s" slot ty);
    emit ctx (Printf.sprintf "store %s %%%s.arg, ptr %%%s.addr" ty (llvm_name v.Tir.v_name) slot);
    Hashtbl.replace ctx.var_llvm_ty slot ty
  ) fn.Tir.fn_params;

  let (body_ty, body_val) = emit_expr ctx fn.Tir.fn_body in

  if ret_ty = "void" then
    emit_term ctx "ret void"
  else begin
    let final_val = coerce ctx body_ty body_val ret_ty in
    emit_term ctx (Printf.sprintf "ret %s %s" ret_ty final_val)
  end;

  Buffer.add_string ctx.buf "}\n"

(** Return the LLVM `declare` string for a function, for use as a forward
    declaration in subsequent JIT fragments that reference it without redefining it. *)
let fn_declare_str (fn : Tir.fn_def) : string =
  let fn_llvm_name = mangle_extern fn.Tir.fn_name in
  let ret_ty = llvm_ret_ty fn.Tir.fn_ret_ty in
  let param_tys = String.concat ", " (List.map (fun (v : Tir.var) ->
      llvm_ty v.Tir.v_ty) fn.Tir.fn_params) in
  Printf.sprintf "declare %s @%s(%s)" ret_ty fn_llvm_name param_tys

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
           br_tag with scrut_tir_ty before the lookup. *)
        Hashtbl.replace ctx.ctor_info (_name ^ "." ^ ctor_name)
          { ce_tag = tag_idx; ce_fields = field_tys };
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

let emit_preamble (buf : Buffer.t) =
  Buffer.add_string buf {|; March compiler output
target triple = "arm64-apple-macosx15.0.0"

; Runtime declarations
declare ptr  @march_alloc(i64 %sz)
declare void @march_incrc(ptr %p)
declare void @march_decrc(ptr %p)
declare i64  @march_decrc_freed(ptr %p)
declare void @march_free(ptr %p)
declare void @march_print(ptr %s)
declare void @march_panic(ptr %s)
declare void @march_println(ptr %s)
declare ptr  @march_string_lit(ptr %s, i64 %len)
declare ptr  @march_int_to_string(i64 %n)
declare ptr  @march_float_to_string(double %f)
declare ptr  @march_bool_to_string(i64 %b)
declare ptr  @march_string_concat(ptr %a, ptr %b)
declare i64  @march_string_eq(ptr %a, ptr %b)
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
declare void @march_kill(ptr %actor)
declare i64  @march_is_alive(ptr %actor)
declare ptr  @march_send(ptr %actor, ptr %msg)
declare ptr  @march_spawn(ptr %actor)
declare i64  @march_actor_get_int(ptr %actor, i64 %index)
declare void @march_run_scheduler()
declare i64  @march_tcp_listen(i64 %port)
declare i64  @march_tcp_accept(i64 %fd)
declare ptr  @march_tcp_recv_http(i64 %fd, i64 %max)
declare void @march_tcp_send_all(i64 %fd, ptr %data)
declare void @march_tcp_close(i64 %fd)
declare ptr  @march_http_parse_request(ptr %raw)
declare ptr  @march_http_serialize_response(i64 %status, ptr %headers, ptr %body)
declare void @march_http_server_listen(i64 %port, i64 %max_conns, i64 %idle_timeout, ptr %pipeline)
declare void @march_ws_handshake(i64 %fd, ptr %key)
declare ptr  @march_ws_recv(i64 %fd)
declare void @march_ws_send(i64 %fd, ptr %frame)
declare ptr  @march_ws_select(i64 %fd, ptr %pipe, i64 %timeout)
; Float builtins
declare double @march_float_abs(double %f)
declare i64    @march_float_ceil(double %f)
declare i64    @march_float_floor(double %f)
declare i64    @march_float_round(double %f)
declare i64    @march_float_truncate(double %f)
declare double @march_int_to_float(i64 %n)
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
; File/Dir builtins
declare i64  @march_file_exists(ptr %s)
declare i64  @march_dir_exists(ptr %s)
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
declare ptr  @march_value_to_string(ptr %v)

|}

let emit_main_wrapper (buf : Buffer.t) =
  Buffer.add_string buf
    "\ndefine i32 @main() {\nentry:\n  call void @march_main()\n  call void @march_run_scheduler()\n  ret i32 0\n}\n"

let emit_module ?(fast_math=false) (m : Tir.tir_module) : string =
  let ctx = make_ctx ~fast_math () in
  build_ctor_info ctx m;
  (* Register user-defined extern functions *)
  List.iter (fun (ed : Tir.extern_decl) ->
      Hashtbl.replace ctx.extern_map ed.ed_march_name ed.ed_c_name;
      Hashtbl.replace ctx.top_fns ed.ed_march_name true
    ) m.Tir.tm_externs;
  List.iter (fun fn -> Hashtbl.replace ctx.top_fns fn.Tir.fn_name true)
    m.Tir.tm_fns;
  (* Skip emitting prelude wrapper functions whose runtime name is already
     declared in the preamble.  Only filter short unqualified names that map
     to march_* builtins — not user-defined qualified names like "CapDemo.main". *)
  let preamble_declared = ["panic"; "println"; "print"] in
  List.iter (fun fn ->
      if List.mem fn.Tir.fn_name preamble_declared then ()
      else emit_fn ctx fn
    ) m.Tir.tm_fns;

  let out = Buffer.create 8192 in
  emit_preamble out;
  (* Emit user-defined extern function declarations *)
  List.iter (fun (ed : Tir.extern_decl) ->
      let ret_llty = llvm_ret_ty ed.ed_ret in
      let param_lltys = List.map (fun _t -> "ptr") ed.ed_params in
      let params_str = String.concat ", " (List.mapi (fun i ty ->
          Printf.sprintf "%s %%%d" ty i) param_lltys) in
      Buffer.add_string out
        (Printf.sprintf "declare %s @%s(%s)\n" ret_llty ed.ed_c_name params_str)
    ) m.Tir.tm_externs;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;

  (* Find a main function: either top-level "main" or "ModName.main" *)
  let main_fn_name = List.find_map (fun (fn : Tir.fn_def) ->
      if fn.Tir.fn_name = "main" then Some "main"
      else if String.length fn.Tir.fn_name > 5 &&
              String.sub fn.Tir.fn_name
                (String.length fn.Tir.fn_name - 5) 5 = ".main"
      then Some fn.Tir.fn_name
      else None
    ) m.Tir.tm_fns in
  (match main_fn_name with
   | Some name ->
     let mangled = llvm_name (mangle_extern name) in
     Buffer.add_string out
       (Printf.sprintf "\ndefine i32 @main() {\nentry:\n  call void @%s()\n  call void @march_run_scheduler()\n  ret i32 0\n}\n" mangled)
   | None -> ());

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

(** Emit bridge alloca+load+store pairs for each prev_global into the current
    function entry block, and register the slot in [ctx.var_slot].
    This lets the body refer to REPL globals via the normal alloca load path.
    LLVM's mem2reg/SROA eliminates the extra instructions. *)
let emit_prev_global_bridges ctx (prev_globals : (string * string) list) =
  List.iter (fun (gname, llty) ->
    (* gname is always "repl_<bare>" by construction in repl_jit *)
    let bare = if String.length gname > 5 && String.sub gname 0 5 = "repl_"
               then String.sub gname 5 (String.length gname - 5)
               else gname in
    let tmp = fresh ctx "br" in
    Printf.bprintf ctx.buf "  %%%s.addr = alloca %s\n" bare llty;
    Printf.bprintf ctx.buf "  %s = load %s, ptr @%s\n" tmp llty gname;
    Printf.bprintf ctx.buf "  store %s %s, ptr %%%s.addr\n" llty tmp bare;
    Hashtbl.replace ctx.var_slot bare bare
  ) prev_globals

(** Emit a REPL expression as a standalone .ll fragment.
    Returns textual LLVM IR with a function [@repl_<n>] that computes
    and returns the expression result.
    [prev_globals] are (name, llvm_ty) pairs from earlier REPL inputs.
    [fns] are any helper functions the expression depends on. *)
let emit_repl_expr ?(fast_math=false) ~(n : int) ~(ret_ty : Tir.ty)
    ~(prev_globals : (string * string) list)
    ~(fns : Tir.fn_def list)
    ?(extern_fns : Tir.fn_def list = [])
    ~(types : Tir.type_def list)
    (body : Tir.expr) : string =
  let ctx = make_ctx ~fast_math () in
  let pseudo_mod : Tir.tir_module = { tm_name = "repl"; tm_types = types; tm_fns = fns; tm_externs = [] } in
  build_ctor_info ctx pseudo_mod;
  List.iter (fun fn -> Hashtbl.replace ctx.top_fns fn.Tir.fn_name true) fns;
  (* Register pre-compiled extern functions so EApp generates direct calls *)
  List.iter (fun fn -> Hashtbl.replace ctx.top_fns fn.Tir.fn_name true) extern_fns;
  List.iter (emit_fn ctx) fns;
  let ret_llty = llvm_ty ret_ty in
  let fname = Printf.sprintf "repl_%d" n in
  Printf.bprintf ctx.buf "\ndefine %s @%s() {\nentry:\n" ret_llty fname;
  emit_prev_global_bridges ctx prev_globals;
  let (actual_ty, result) = emit_expr ctx body in
  let result' = coerce ctx actual_ty result ret_llty in
  Printf.bprintf ctx.buf "  ret %s %s\n}\n" ret_llty result';
  let out = Buffer.create 4096 in
  emit_preamble out;
  emit_repl_globals_decl out prev_globals;
  (* Declare pre-compiled functions so LLVM IR is valid even without definitions *)
  List.iter (fun fn -> Buffer.add_string out (fn_declare_str fn ^ "\n")) extern_fns;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;
  Buffer.contents out

(** Emit a REPL let-binding as a .ll fragment.
    Creates a global [@repl_<name>] and an init function [@repl_<n>_init]
    that computes the value and stores it in the global. *)
let emit_repl_decl ?(fast_math=false) ~(n : int) ~(name : string)
    ~(val_ty : Tir.ty)
    ~(prev_globals : (string * string) list)
    ~(fns : Tir.fn_def list)
    ?(extern_fns : Tir.fn_def list = [])
    ~(types : Tir.type_def list)
    (body : Tir.expr) : string =
  let ctx = make_ctx ~fast_math () in
  let pseudo_mod : Tir.tir_module = { tm_name = "repl"; tm_types = types; tm_fns = fns; tm_externs = [] } in
  build_ctor_info ctx pseudo_mod;
  List.iter (fun fn -> Hashtbl.replace ctx.top_fns fn.Tir.fn_name true) fns;
  List.iter (fun fn -> Hashtbl.replace ctx.top_fns fn.Tir.fn_name true) extern_fns;
  List.iter (emit_fn ctx) fns;
  let llty = llvm_ty val_ty in
  let global_name = "repl_" ^ name in
  let init_name = Printf.sprintf "repl_%d_init" n in
  Printf.bprintf ctx.preamble "@%s = global %s zeroinitializer\n" global_name llty;
  Printf.bprintf ctx.buf "\ndefine void @%s() {\nentry:\n" init_name;
  emit_prev_global_bridges ctx prev_globals;
  let (actual_ty, result) = emit_expr ctx body in
  let result' = coerce ctx actual_ty result llty in
  Printf.bprintf ctx.buf "  store %s %s, ptr @%s\n" llty result' global_name;
  Printf.bprintf ctx.buf "  ret void\n}\n";
  let out = Buffer.create 4096 in
  emit_preamble out;
  emit_repl_globals_decl out prev_globals;
  List.iter (fun fn -> Buffer.add_string out (fn_declare_str fn ^ "\n")) extern_fns;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;
  Buffer.contents out

(** Emit a REPL function declaration as a .ll fragment.
    The function is emitted at top level (callable by later fragments).
    A no-op [@repl_<n>_init] is emitted so the REPL runner can call it uniformly. *)
let emit_repl_fn ?(fast_math=false) ~(n : int)
    ~(prev_globals : (string * string) list)
    ?(extern_fns : Tir.fn_def list = [])
    ~(types : Tir.type_def list)
    (fn : Tir.fn_def) : string =
  let ctx = make_ctx ~fast_math () in
  let pseudo_mod : Tir.tir_module = { tm_name = "repl"; tm_types = types; tm_fns = [fn]; tm_externs = [] } in
  build_ctor_info ctx pseudo_mod;
  Hashtbl.replace ctx.top_fns fn.Tir.fn_name true;
  List.iter (fun f -> Hashtbl.replace ctx.top_fns f.Tir.fn_name true) extern_fns;
  emit_fn ctx fn;
  let init_name = Printf.sprintf "repl_%d_init" n in
  Printf.bprintf ctx.buf "\ndefine void @%s() {\nentry:\n  ret void\n}\n" init_name;
  let out = Buffer.create 4096 in
  emit_preamble out;
  emit_repl_globals_decl out prev_globals;
  List.iter (fun f -> Buffer.add_string out (fn_declare_str f ^ "\n")) extern_fns;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;
  Buffer.contents out

(** Emit a REPL function declaration as a .ll fragment, and also create a
    first-class closure value stored in a global [@repl_<bind_name>].
    This lets later REPL fragments reference [bind_name] as a value via the
    normal global-bridge mechanism (same as [emit_repl_decl] for data lets).
    The init function [@repl_<n>_init] allocates the closure and fills the global. *)
let emit_repl_fn_with_closure_global ?(fast_math=false) ~(n : int)
    ~(bind_name : string)
    ~(prev_globals : (string * string) list)
    ?(extern_fns : Tir.fn_def list = [])
    ~(types : Tir.type_def list)
    (fn : Tir.fn_def) : string =
  let ctx = make_ctx ~fast_math () in
  let pseudo_mod : Tir.tir_module = { tm_name = "repl"; tm_types = types; tm_fns = [fn]; tm_externs = [] } in
  build_ctor_info ctx pseudo_mod;
  Hashtbl.replace ctx.top_fns fn.Tir.fn_name true;
  List.iter (fun f -> Hashtbl.replace ctx.top_fns f.Tir.fn_name true) extern_fns;
  emit_fn ctx fn;
  (* Build a thin closure wrapper: @<fn>$clo_wrap(ptr %_clo, ptr %a0, ...) *)
  let fn_llvm_name = llvm_name (mangle_extern fn.Tir.fn_name) in
  let wrap_name = fn_llvm_name ^ "$clo_wrap" in
  let nparams = List.length fn.Tir.fn_params in
  let target_ret = llvm_ret_ty fn.Tir.fn_ret_ty in
  let param_tys = List.init nparams (fun _ -> "ptr") in
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
      Printf.sprintf "\ndefine ptr @%s(%s) {\nentry:\n  %%r = call %s @%s(%s)\n  ret ptr %%r\n}\n"
        wrap_name decl_str target_ret fn_llvm_name call_args
  in
  Buffer.add_string ctx.buf wrap_body;
  (* Global that holds the closure pointer *)
  let global_name = "repl_" ^ bind_name in
  Printf.bprintf ctx.preamble "@%s = global ptr zeroinitializer\n" global_name;
  (* Init function: allocate closure {header(16), fn_ptr} and store in the global *)
  let init_name = Printf.sprintf "repl_%d_init" n in
  Printf.bprintf ctx.buf "\ndefine void @%s() {\nentry:\n" init_name;
  Printf.bprintf ctx.buf "  %%hp = call ptr @march_alloc(i64 24)\n";
  Printf.bprintf ctx.buf "  %%tgp = getelementptr i8, ptr %%hp, i64 8\n";
  Printf.bprintf ctx.buf "  store i32 0, ptr %%tgp, align 4\n";
  Printf.bprintf ctx.buf "  %%fp = getelementptr i8, ptr %%hp, i64 16\n";
  Printf.bprintf ctx.buf "  store ptr @%s, ptr %%fp, align 8\n" wrap_name;
  Printf.bprintf ctx.buf "  store ptr %%hp, ptr @%s\n" global_name;
  Printf.bprintf ctx.buf "  ret void\n}\n";
  let out = Buffer.create 4096 in
  emit_preamble out;
  emit_repl_globals_decl out prev_globals;
  List.iter (fun f -> Buffer.add_string out (fn_declare_str f ^ "\n")) extern_fns;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;
  Buffer.contents out

(** Emit a collection of functions as a standalone LLVM IR module.
    Used for precompiling the stdlib to a cacheable .so fragment.
    No expression wrapper is emitted — just the function definitions. *)
let emit_fns_fragment
    ~(types : Tir.type_def list)
    ~(fns : Tir.fn_def list) : string =
  let ctx = make_ctx () in
  let pseudo_mod : Tir.tir_module =
    { tm_name = "stdlib_prelude"; tm_types = types; tm_fns = fns; tm_externs = [] } in
  build_ctor_info ctx pseudo_mod;
  List.iter (fun fn -> Hashtbl.replace ctx.top_fns fn.Tir.fn_name true) fns;
  List.iter (emit_fn ctx) fns;
  let out = Buffer.create 8192 in
  emit_preamble out;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;
  Buffer.add_buffer out ctx.extra_fns;
  Buffer.contents out

let llvm_ty_of_tir = llvm_ty
