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
                 "kill"; "is_alive"; "send";
                 "task_spawn"; "task_await"; "task_await_unwrap";
                 "task_yield"; "task_spawn_steal"; "task_reductions";
                 "get_work_pool"]

let atom_is_builtin (atom : Tir.atom) =
  match atom with
  | Tir.AVar v -> is_builtin_fn v.Tir.v_name
  | _ -> false

(** TIR return type for known builtin/extern functions, overriding type info. *)
let builtin_ret_ty : string -> Tir.ty option = function
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
  | _ -> None

(** Mangle a March builtin name to the C runtime function name. *)
let mangle_extern : string -> string = function
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
  | Tir.ALit (March_ast.Ast.LitFloat f) -> ("double", Printf.sprintf "%h" f)
  | Tir.ALit (March_ast.Ast.LitBool b)  -> ("i64",    if b then "1" else "0")
  | Tir.ALit (March_ast.Ast.LitAtom _)  -> ("i64",    "0")
  | Tir.ALit (March_ast.Ast.LitString s) ->
    let gname = intern_string ctx s in
    let tmp = fresh ctx "sl" in
    emit ctx (Printf.sprintf "%s = call ptr @march_string_lit(ptr %s, i64 %d)"
                tmp gname (String.length s));
    ("ptr", tmp)
  | Tir.AVar v when v.Tir.v_name = "get_work_pool" ->
    (* Phase 1: work pool is a null sentinel *)
    ("ptr", "null")
  | Tir.AVar v when Hashtbl.mem ctx.top_fns v.Tir.v_name ->
    (* Top-level function reference — emit its address directly *)
    ("ptr", "@" ^ llvm_name (mangle_extern v.Tir.v_name))
  | Tir.AVar v ->
    let ty = llvm_ty v.Tir.v_ty in
    let tmp = fresh ctx "ld" in
    let base = llvm_name v.Tir.v_name in
    let slot = match Hashtbl.find_opt ctx.var_slot base with
      | Some s -> s
      | None   -> base
    in
    emit ctx (Printf.sprintf "%s = load %s, ptr %%%s.addr" tmp ty slot);
    (ty, tmp)

let emit_atom_val ctx a = snd (emit_atom ctx a)

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
    let slot_ty  = llvm_ty v.Tir.v_ty in
    let final_val = coerce ctx rhs_ty rhs_val slot_ty in
    let slot = alloca_name ctx (llvm_name v.Tir.v_name) in
    emit ctx (Printf.sprintf "%%%s.addr = alloca %s" slot slot_ty);
    emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" slot_ty final_val slot);
    emit_expr ctx body

  (* ── Sequence ──────────────────────────────────────────────────────── *)
  | Tir.ESeq (e1, e2) ->
    ignore (emit_expr ctx e1);
    emit_expr ctx e2

  (* ── Arithmetic builtins ───────────────────────────────────────────── *)
  | Tir.EApp (f, [a; b]) when is_int_arith f.Tir.v_name ->
    let va = emit_atom_val ctx a in
    let vb = emit_atom_val ctx b in
    let r  = fresh ctx "ar" in
    emit ctx (Printf.sprintf "%s = %s i64 %s, %s" r (int_arith_op f.Tir.v_name) va vb);
    ("i64", r)

  | Tir.EApp (f, [a; b]) when is_int_cmp f.Tir.v_name ->
    let va  = emit_atom_val ctx a in
    let vb  = emit_atom_val ctx b in
    let cmp = fresh ctx "cmp" in
    let r   = fresh ctx "ar" in
    emit ctx (Printf.sprintf "%s = icmp %s i64 %s, %s" cmp (int_cmp_pred f.Tir.v_name) va vb);
    emit ctx (Printf.sprintf "%s = zext i1 %s to i64" r cmp);
    ("i64", r)

  | Tir.EApp (f, [a; b]) when is_float_arith f.Tir.v_name ->
    let va = emit_atom_val ctx a in
    let vb = emit_atom_val ctx b in
    let r  = fresh ctx "ar" in
    let op = float_arith_op f.Tir.v_name in
    let op_str = if ctx.fast_math then op ^ " fast" else op in
    emit ctx (Printf.sprintf "%s = %s double %s, %s" r op_str va vb);
    ("double", r)

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
    let fname    = mangle_extern f.Tir.v_name in
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
    let ret_tir = match fn_atom with
      | Tir.AVar v -> fn_ret_tir v.Tir.v_ty
      | _ -> Tir.TVar "_"
    in
    let ret_ty = llvm_ret_ty ret_tir in
    let orig_param_llvm_tys = match fn_atom with
      | Tir.AVar v ->
        (match v.Tir.v_ty with
         | Tir.TFn (ps, _) -> List.map llvm_ty ps
         | _ -> List.map (fun _ -> "ptr") args)
      | _ -> List.map (fun _ -> "ptr") args
    in
    let fn_ty_str = Printf.sprintf "%s (%s)" ret_ty
        (String.concat ", " ("ptr" :: orig_param_llvm_tys)) in
    let orig_arg_strs = List.map2 (fun pty a ->
        let (_, v) = emit_atom ctx a in pty ^ " " ^ v
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
        | Some t -> llvm_ty t | None -> "ptr" in
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
        | Some t -> llvm_ty t | None -> "ptr" in
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
        | Some t -> llvm_ty t | None -> "ptr" in
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
    let (_, v) = emit_atom ctx atom in
    emit ctx (Printf.sprintf "call void @march_incrc(ptr %s)" v);
    ("i64", "0")

  | Tir.EDecRC atom
    when atom_is_builtin atom ||
         (match atom with Tir.AVar v -> Hashtbl.mem ctx.top_fns v.Tir.v_name | _ -> false) ->
    ("i64", "0")
  | Tir.EDecRC atom ->
    let (_, v) = emit_atom ctx atom in
    emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" v);
    ("i64", "0")

  | Tir.EFree atom
    when atom_is_builtin atom ||
         (match atom with Tir.AVar v -> Hashtbl.mem ctx.top_fns v.Tir.v_name | _ -> false) ->
    ("i64", "0")
  | Tir.EFree atom ->
    let (_, v) = emit_atom ctx atom in
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
      | Tir.AVar v -> v.Tir.v_ty
      | Tir.ALit _ -> Tir.TVar "_"
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
      | Tir.AVar v -> v.Tir.v_ty
      | Tir.ALit _ -> Tir.TVar "_"
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

  (* Determine switch discriminant (tag or scalar) *)
  let (sw_ty, sw_val) =
    if is_ptr_scrut then ("i32", emit_load_tag ctx scrut_val)
    else ("i64", scrut_val)
  in

  (* Build switch arms *)
  let cases_str = List.map2 (fun br lbl ->
      let tag_str =
        if is_ptr_scrut then
          let e = ctor_entry ctx br.Tir.br_tag 0 in
          string_of_int e.ce_tag
        else begin
          match int_of_string_opt br.Tir.br_tag with
          | Some n -> string_of_int n
          | None ->
            if br.Tir.br_tag = "true"  || br.Tir.br_tag = "True"  then "1"
            else if br.Tir.br_tag = "false" || br.Tir.br_tag = "False" then "0"
            else "0"
        end
      in
      Printf.sprintf "%s %s, label %%%s" sw_ty tag_str lbl
    ) branches branch_lbls in
  let cases_part = String.concat "\n      " cases_str in
  emit_term ctx (Printf.sprintf "switch %s %s, label %%%s [\n      %s\n  ]"
                   sw_ty sw_val default_lbl cases_part);

  (* Helper: if body = ESeq(EDecRC(v), rest) where v.v_name = scrut_name,
     return (v, rest). Used to handle shared-value field IncRC below. *)
  let strip_scrut_decrc scrut_name body =
    match body with
    | Tir.ESeq (Tir.EDecRC (Tir.AVar v), rest)
      when String.equal v.Tir.v_name scrut_name -> Some (v, rest)
    | _ -> None
  in

  (* The scrutinee's TIR type — used to resolve concrete field types for
     polymorphic constructors (e.g. List(Int): field 0 is Int, not TVar "a"). *)
  let scrut_tir_ty =
    match scrut_atom with Tir.AVar v -> v.Tir.v_ty | _ -> Tir.TUnit
  in

  (* Emit branch blocks *)
  List.iter2 (fun br lbl ->
    emit_label ctx lbl;
    (* Bind branch variables from scrutinee fields *)
    let heap_field_vals = ref [] in
    if is_ptr_scrut then begin
      let entry = ctor_entry ctx br.Tir.br_tag (List.length br.Tir.br_vars) in
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
    emit ctx (Printf.sprintf "store %s %%%s.arg, ptr %%%s.addr" ty (llvm_name v.Tir.v_name) slot)
  ) fn.Tir.fn_params;

  let (body_ty, body_val) = emit_expr ctx fn.Tir.fn_body in

  if ret_ty = "void" then
    emit_term ctx "ret void"
  else begin
    let final_val = coerce ctx body_ty body_val ret_ty in
    emit_term ctx (Printf.sprintf "ret %s %s" ret_ty final_val)
  end;

  Buffer.add_string ctx.buf "}\n"

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
        Hashtbl.replace ctx.ctor_info ctor_name
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
declare void @march_println(ptr %s)
declare ptr  @march_string_lit(ptr %s, i64 %len)
declare ptr  @march_int_to_string(i64 %n)
declare ptr  @march_float_to_string(double %f)
declare ptr  @march_bool_to_string(i64 %b)
declare ptr  @march_string_concat(ptr %a, ptr %b)
declare i64  @march_string_eq(ptr %a, ptr %b)
declare i64  @march_string_byte_length(ptr %s)
declare i64  @march_string_is_empty(ptr %s)
declare ptr  @march_string_to_int(ptr %s)
declare ptr  @march_string_join(ptr %list, ptr %sep)
declare void @march_kill(ptr %actor)
declare i64  @march_is_alive(ptr %actor)
declare ptr  @march_send(ptr %actor, ptr %msg)

|}

let emit_main_wrapper (buf : Buffer.t) =
  Buffer.add_string buf
    "\ndefine i32 @main() {\nentry:\n  call void @march_main()\n  ret i32 0\n}\n"

let emit_module ?(fast_math=false) (m : Tir.tir_module) : string =
  let ctx = make_ctx ~fast_math () in
  build_ctor_info ctx m;
  List.iter (fun fn -> Hashtbl.replace ctx.top_fns fn.Tir.fn_name true)
    m.Tir.tm_fns;
  List.iter (emit_fn ctx) m.Tir.tm_fns;

  let out = Buffer.create 8192 in
  emit_preamble out;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;

  let has_main = List.exists (fun (fn : Tir.fn_def) -> fn.Tir.fn_name = "main")
                   m.Tir.tm_fns in
  if has_main then emit_main_wrapper out;

  Buffer.contents out

(* ── REPL emission helpers ──────────────────────────────────────────────── *)

(** Tracks REPL globals across fragments. Each entry:
    (llvm_name, llvm_type_string).  Example: ("repl_x", "ptr") *)
type repl_globals = (string * string) list ref

let emit_repl_globals_decl (buf : Buffer.t) (globals : (string * string) list) =
  List.iter (fun (name, ty) ->
    Printf.bprintf buf "@%s = external global %s\n" name ty
  ) globals

(** Emit a REPL expression as a standalone .ll fragment.
    Returns textual LLVM IR with a function [@repl_<n>] that computes
    and returns the expression result.
    [prev_globals] are (name, llvm_ty) pairs from earlier REPL inputs.
    [fns] are any helper functions the expression depends on. *)
let emit_repl_expr ?(fast_math=false) ~(n : int) ~(ret_ty : Tir.ty)
    ~(prev_globals : (string * string) list)
    ~(fns : Tir.fn_def list)
    ~(types : Tir.type_def list)
    (body : Tir.expr) : string =
  let ctx = make_ctx ~fast_math () in
  let pseudo_mod : Tir.tir_module = { tm_name = "repl"; tm_types = types; tm_fns = fns } in
  build_ctor_info ctx pseudo_mod;
  List.iter (fun fn -> Hashtbl.replace ctx.top_fns fn.Tir.fn_name true) fns;
  List.iter (emit_fn ctx) fns;
  let ret_llty = llvm_ty ret_ty in
  let fname = Printf.sprintf "repl_%d" n in
  Printf.bprintf ctx.buf "\ndefine %s @%s() {\nentry:\n" ret_llty fname;
  let (_ty, result) = emit_expr ctx body in
  Printf.bprintf ctx.buf "  ret %s %s\n}\n" ret_llty result;
  let out = Buffer.create 4096 in
  emit_preamble out;
  emit_repl_globals_decl out prev_globals;
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
    ~(types : Tir.type_def list)
    (body : Tir.expr) : string =
  let ctx = make_ctx ~fast_math () in
  let pseudo_mod : Tir.tir_module = { tm_name = "repl"; tm_types = types; tm_fns = fns } in
  build_ctor_info ctx pseudo_mod;
  List.iter (fun fn -> Hashtbl.replace ctx.top_fns fn.Tir.fn_name true) fns;
  List.iter (emit_fn ctx) fns;
  let llty = llvm_ty val_ty in
  let global_name = "repl_" ^ name in
  let init_name = Printf.sprintf "repl_%d_init" n in
  Printf.bprintf ctx.preamble "@%s = global %s zeroinitializer\n" global_name llty;
  Printf.bprintf ctx.buf "\ndefine void @%s() {\nentry:\n" init_name;
  let (_ty, result) = emit_expr ctx body in
  Printf.bprintf ctx.buf "  store %s %s, ptr @%s\n" llty result global_name;
  Printf.bprintf ctx.buf "  ret void\n}\n";
  let out = Buffer.create 4096 in
  emit_preamble out;
  emit_repl_globals_decl out prev_globals;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;
  Buffer.contents out

(** Emit a REPL function declaration as a .ll fragment.
    The function is emitted at top level (callable by later fragments).
    A no-op [@repl_<n>_init] is emitted so the REPL runner can call it uniformly. *)
let emit_repl_fn ?(fast_math=false) ~(n : int)
    ~(prev_globals : (string * string) list)
    ~(types : Tir.type_def list)
    (fn : Tir.fn_def) : string =
  let ctx = make_ctx ~fast_math () in
  let pseudo_mod : Tir.tir_module = { tm_name = "repl"; tm_types = types; tm_fns = [fn] } in
  build_ctor_info ctx pseudo_mod;
  Hashtbl.replace ctx.top_fns fn.Tir.fn_name true;
  emit_fn ctx fn;
  let init_name = Printf.sprintf "repl_%d_init" n in
  Printf.bprintf ctx.buf "\ndefine void @%s() {\nentry:\n  ret void\n}\n" init_name;
  let out = Buffer.create 4096 in
  emit_preamble out;
  emit_repl_globals_decl out prev_globals;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;
  Buffer.contents out

let llvm_ty_of_tir = llvm_ty
