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
                 "kill"; "is_alive"; "send"]

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
  | Tir.AVar v when Hashtbl.mem ctx.top_fns v.Tir.v_name ->
    (* Top-level function reference — emit its address directly *)
    ("ptr", "@" ^ llvm_name (mangle_extern v.Tir.v_name))
  | Tir.AVar v ->
    let ty = llvm_ty v.Tir.v_ty in
    let tmp = fresh ctx "ld" in
    emit ctx (Printf.sprintf "%s = load %s, ptr %%%s.addr" tmp ty (llvm_name v.Tir.v_name));
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
    let vn = llvm_name v.Tir.v_name in
    emit ctx (Printf.sprintf "%%%s.addr = alloca %s" vn field_ty);
    emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" field_ty fv vn);
    emit_expr ctx body

  (* ── Let binding ───────────────────────────────────────────────────── *)
  | Tir.ELet (v, rhs, body) ->
    let (rhs_ty, rhs_val) = emit_expr ctx rhs in
    let slot_ty  = llvm_ty v.Tir.v_ty in
    let final_val = coerce ctx rhs_ty rhs_val slot_ty in
    let vn = llvm_name v.Tir.v_name in
    emit ctx (Printf.sprintf "%%%s.addr = alloca %s" vn slot_ty);
    emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" slot_ty final_val vn);
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

  (* ── FBIP reuse ────────────────────────────────────────────────────── *)
  | Tir.EReuse (reuse_atom, Tir.TCon (ctor, _), args) ->
    let (_, rv) = emit_atom ctx reuse_atom in
    let entry = ctor_entry ctx ctor (List.length args) in
    emit_store_tag ctx rv entry.ce_tag;
    List.iteri (fun i atom ->
      let field_ty = match List.nth_opt entry.ce_fields i with
        | Some t -> llvm_ty t | None -> "ptr" in
      let (v_ty, v_val) = emit_atom ctx atom in
      let v_coerced = coerce ctx v_ty v_val field_ty in
      emit_store_field ctx rv i field_ty v_coerced
    ) args;
    ("ptr", rv)

  | Tir.EReuse (reuse_atom, _, args) ->
    let (_, rv) = emit_atom ctx reuse_atom in
    List.iteri (fun i atom ->
      let (ty, v) = emit_atom ctx atom in
      emit_store_field ctx rv i ty v
    ) args;
    ("ptr", rv)

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

  (* Emit branch blocks *)
  List.iter2 (fun br lbl ->
    emit_label ctx lbl;
    (* Bind branch variables from scrutinee fields *)
    if is_ptr_scrut then begin
      let entry = ctor_entry ctx br.Tir.br_tag (List.length br.Tir.br_vars) in
      List.iteri (fun i (v : Tir.var) ->
        let field_ty = match List.nth_opt entry.ce_fields i with
          | Some t -> llvm_ty t | None -> llvm_ty v.Tir.v_ty in
        let fv = emit_load_field ctx scrut_val i field_ty in
        let vn = llvm_name v.Tir.v_name in
        emit ctx (Printf.sprintf "%%%s.addr = alloca %s" vn field_ty);
        emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" field_ty fv vn)
      ) br.Tir.br_vars
    end;
    let (br_ty, br_val) = emit_expr ctx br.Tir.br_body in
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
    let vn = llvm_name v.Tir.v_name in
    emit ctx (Printf.sprintf "%%%s.addr = alloca %s" vn ty);
    emit ctx (Printf.sprintf "store %s %%%s.arg, ptr %%%s.addr" ty vn vn)
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
      List.iteri (fun tag_idx (ctor_name, field_tys) ->
        Hashtbl.replace ctx.ctor_info ctor_name
          { ce_tag = tag_idx; ce_fields = field_tys }
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
