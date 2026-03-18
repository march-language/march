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
  mutable ret_ty  : Tir.ty;
}

let make_ctx () = {
  buf      = Buffer.create 4096;
  preamble = Buffer.create 1024;
  ctr      = 0; blk = 0; str_ctr = 0;
  ctor_info = Hashtbl.create 64;
  ret_ty   = Tir.TUnit;
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

(** TIR return type for known builtin/extern functions, overriding type info. *)
let builtin_ret_ty : string -> Tir.ty option = function
  | "println" | "print"           -> Some Tir.TUnit
  | "int_to_string"               -> Some Tir.TString
  | "float_to_string"             -> Some Tir.TString
  | "bool_to_string"              -> Some Tir.TString
  | "string_concat" | "++"        -> Some Tir.TString
  | "string_eq"                   -> Some Tir.TInt
  | _ -> None

(** Mangle a March builtin name to the C runtime function name. *)
let mangle_extern : string -> string = function
  | "println"       -> "march_println"
  | "print"         -> "march_print"
  | "int_to_string" -> "march_int_to_string"
  | "float_to_string" -> "march_float_to_string"
  | "bool_to_string"  -> "march_bool_to_string"
  | "string_concat" | "++" -> "march_string_concat"
  | "string_eq"     -> "march_string_eq"
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
  | Tir.AVar v ->
    let ty = llvm_ty v.Tir.v_ty in
    let tmp = fresh ctx "ld" in
    emit ctx (Printf.sprintf "%s = load %s, ptr %%%s.addr" tmp ty v.Tir.v_name);
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

(* ── Core expression emitter ─────────────────────────────────────────── *)

(** Emit [e] and return (llvm_type, llvm_value). Unit → ("i64","0"). *)
let rec emit_expr ctx (e : Tir.expr) : string * string =
  match e with

  (* ── Atoms ─────────────────────────────────────────────────────────── *)
  | Tir.EAtom atom -> emit_atom ctx atom

  (* ── Let binding ───────────────────────────────────────────────────── *)
  | Tir.ELet (v, rhs, body) ->
    let (rhs_ty, rhs_val) = emit_expr ctx rhs in
    let slot_ty  = llvm_ty v.Tir.v_ty in
    let final_val = coerce ctx rhs_ty rhs_val slot_ty in
    emit ctx (Printf.sprintf "%%%s.addr = alloca %s" v.Tir.v_name slot_ty);
    emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" slot_ty final_val v.Tir.v_name);
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
    emit ctx (Printf.sprintf "%s = %s double %s, %s" r (float_arith_op f.Tir.v_name) va vb);
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

  (* ── Indirect call ─────────────────────────────────────────────────── *)
  | Tir.ECallPtr (fn_atom, args) ->
    let (_, fval) = emit_atom ctx fn_atom in
    let arg_strs = List.map (fun a ->
        let (ty, v) = emit_atom ctx a in ty ^ " " ^ v
      ) args in
    let r = fresh ctx "cr" in
    emit ctx (Printf.sprintf "%s = call ptr %s(%s)" r fval (String.concat ", " arg_strs));
    ("ptr", r)

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
  | Tir.EIncRC atom ->
    let (_, v) = emit_atom ctx atom in
    emit ctx (Printf.sprintf "call void @march_incrc(ptr %s)" v);
    ("i64", "0")

  | Tir.EDecRC atom ->
    let (_, v) = emit_atom ctx atom in
    emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" v);
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
    let n = List.length fields in
    let ptr = emit_heap_alloc ctx 0 n in
    List.iteri (fun i (_, atom) ->
      let (ty, v) = emit_atom ctx atom in
      emit_store_field ctx ptr i ty v
    ) fields;
    ("ptr", ptr)

  (* ── Field access ──────────────────────────────────────────────────── *)
  | Tir.EField (obj_atom, _field_name) ->
    (* Without a field-offset map we default to field 0.
       Proper record lowering requires the field-index map from the type checker. *)
    let (_, obj_val) = emit_atom ctx obj_atom in
    let fv = emit_load_field ctx obj_val 0 "ptr" in
    ("ptr", fv)

  (* ── Record update ─────────────────────────────────────────────────── *)
  | Tir.EUpdate (base_atom, _updates) ->
    (* Simplified: return the base for now. *)
    let (ty, v) = emit_atom ctx base_atom in
    (ty, v)

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
        emit ctx (Printf.sprintf "%%%s.addr = alloca %s" v.Tir.v_name field_ty);
        emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" field_ty fv v.Tir.v_name)
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
  (* March's user-facing "main" → emitted as @march_main *)
  let llvm_name = mangle_extern fn.Tir.fn_name in
  let ret_ty    = llvm_ret_ty fn.Tir.fn_ret_ty in

  let params_str = String.concat ", " (List.map (fun (v : Tir.var) ->
      llvm_ty v.Tir.v_ty ^ " %" ^ v.Tir.v_name ^ ".arg"
    ) fn.Tir.fn_params) in

  Buffer.add_string ctx.buf
    (Printf.sprintf "\ndefine %s @%s(%s) {\nentry:\n" ret_ty llvm_name params_str);

  (* Alloca + store for each parameter *)
  List.iter (fun (v : Tir.var) ->
    let ty = llvm_ty v.Tir.v_ty in
    emit ctx (Printf.sprintf "%%%s.addr = alloca %s" v.Tir.v_name ty);
    emit ctx (Printf.sprintf "store %s %%%s.arg, ptr %%%s.addr" ty v.Tir.v_name v.Tir.v_name)
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
        { ce_tag = 0; ce_fields = List.map snd fields }
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

|}

let emit_main_wrapper (buf : Buffer.t) =
  Buffer.add_string buf
    "\ndefine i32 @main() {\nentry:\n  call void @march_main()\n  ret i32 0\n}\n"

let emit_module (m : Tir.tir_module) : string =
  let ctx = make_ctx () in
  build_ctor_info ctx m;
  List.iter (emit_fn ctx) m.Tir.tm_fns;

  let out = Buffer.create 8192 in
  emit_preamble out;
  Buffer.add_buffer out ctx.preamble;
  Buffer.add_buffer out ctx.buf;

  let has_main = List.exists (fun (fn : Tir.fn_def) -> fn.Tir.fn_name = "main")
                   m.Tir.tm_fns in
  if has_main then emit_main_wrapper out;

  Buffer.contents out
