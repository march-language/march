(** LLVM emission: data-representation helpers for the aggregate emit arms
    (EAlloc / EStackAlloc / EReuse / ETuple / ERecord / EField / EUpdate) —
    GEP-offset load/store primitives, heap/stack allocation, constructor
    lookup, generic-field-type resolution, and record-shape metadata.

    Wave 3 Task 5 (chunk 2) split: moved verbatim out of [llvm_emit.ml] —
    same discipline as the Wave 3 Task 3 [Llvm_ctx] split: whole-definition
    moves, no behavior change, fully-qualified references (no [open]).  The
    EAlloc/EStackAlloc/EReuse/ETuple/ERecord/EField/EUpdate match arms
    themselves stay in [llvm_emit.ml]'s [emit_expr] (they are cases of a
    match, not standalone functions — there is no seam to lift them across
    without duplicating the [Tir.expr] pattern match itself); they call the
    helpers below by their qualified names.  [emit_case] (now in [Llvm_case])
    also calls into this module for constructor/field lookups. *)

(* ── GEP helpers ─────────────────────────────────────────────────────── *)

let emit_load_tag ctx obj_val =
  let tp = Llvm_ctx.fresh ctx "tgp" in
  let tv = Llvm_ctx.fresh ctx "tag" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 8"  tp obj_val);
  Llvm_ctx.emit ctx (Printf.sprintf "%s = load i32, ptr %s, align 4" tv tp);
  tv

let emit_store_tag ctx obj_val tag_int =
  let tp = Llvm_ctx.fresh ctx "tgp" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 8" tp obj_val);
  Llvm_ctx.emit ctx (Printf.sprintf "store i32 %d, ptr %s, align 4" tag_int tp)

(* A heap-cell slot is 8 bytes wide ([Llvm_ctx.alloc_size]).  An unboxed
   aggregate's struct type is wider, so storing or loading one at a slot would
   run over the neighbouring fields.  Fail loudly rather than corrupt: the
   caller wanted [Llvm_ctx.llvm_field_ty], which boxes. *)
let check_slot_ty (where : string) (ty_str : string) =
  match Repr.unboxed_of_llvm_ty ty_str with
  | None -> ()
  | Some (tname, _, _) ->
    failwith (Printf.sprintf
      "LLVM emit: %s with slot type %s (unboxed aggregate `%s`) — a heap slot \
       is 8 bytes; use Llvm_ctx.llvm_field_ty so the value is boxed"
      where ty_str tname)

let emit_store_field ctx obj_val i ty_str val_str =
  check_slot_ty "emit_store_field" ty_str;
  let offset = 16 + i * 8 in
  let fp = Llvm_ctx.fresh ctx "fp" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 %d" fp obj_val offset);
  Llvm_ctx.emit ctx (Printf.sprintf "store %s %s, ptr %s, align 8" ty_str val_str fp)

let emit_load_field ctx obj_val i ty_str =
  check_slot_ty "emit_load_field" ty_str;
  let offset = 16 + i * 8 in
  let fp = Llvm_ctx.fresh ctx "fp" in
  let fv = Llvm_ctx.fresh ctx "fv" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 %d" fp obj_val offset);
  Llvm_ctx.emit ctx (Printf.sprintf "%s = load %s, ptr %s, align 8" fv ty_str fp);
  fv

(* ── Alloc helpers ───────────────────────────────────────────────────── *)

let emit_heap_alloc ctx tag_int n_fields =
  let ptr = Llvm_ctx.fresh ctx "hp" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = call ptr @march_alloc(i64 %d)" ptr (Llvm_ctx.alloc_size n_fields));
  emit_store_tag ctx ptr tag_int;
  ptr

let emit_stack_alloc ctx n_fields =
  let ptr = Llvm_ctx.fresh ctx "sp" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = alloca [%d x i8], align 8" ptr (Llvm_ctx.alloc_size n_fields));
  (* zero the header *)
  Llvm_ctx.emit ctx (Printf.sprintf "store i64 0, ptr %s, align 8" ptr);
  (* zero the tag+pad word too: alloca memory is garbage, and the pad word
     (offset 12) is read as the record shape id by the native runtime *)
  let hw = Llvm_ctx.fresh ctx "tgp" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 8" hw ptr);
  Llvm_ctx.emit ctx (Printf.sprintf "store i64 0, ptr %s, align 8" hw);
  ptr

(* ── Constructor lookup ──────────────────────────────────────────────── *)

let ctor_entry ctx name n_args_fallback =
  match Hashtbl.find_opt ctx.Llvm_ctx.ctor_info name with
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
      ) ctx.Llvm_ctx.ctor_info [] in
    let found = match candidates with
      | [] -> None
      | [single] -> Some single
      | many ->
        (match List.find_opt (fun e -> List.length e.Llvm_ctx.ce_fields = n_args_fallback) many with
         | Some exact -> Some exact
         | None -> Some (List.hd many))
    in
    (match found with
     | Some e -> e
     | None ->
       { Llvm_ctx.ce_tag = 0; ce_fields = List.init n_args_fallback (fun _ -> Tir.TVar "_") })

(** Return concrete field types for [ctor_name] given the scrutinee's TIR type.
    When the scrutinee is a concrete [TCon(name, ty_args)] (e.g. List(Int)),
    substitutes type variable parameters with the concrete arguments so that
    scalar fields (Int, Bool, …) get their real LLVM type instead of "ptr".
    Falls back to [ctor_entry] (which may contain TVar placeholders) otherwise. *)
let resolve_ctor_fields ctx scrut_tir_ty ctor_name n_args =
  match scrut_tir_ty with
  | Tir.TTuple ts -> ts   (* tuple patterns ($TupleN): the element types ARE the field types *)
  | Tir.TCon (type_name, ty_args) ->
    (match Hashtbl.find_opt ctx.Llvm_ctx.type_params type_name,
           Hashtbl.find_opt ctx.Llvm_ctx.poly_ctors (type_name, ctor_name) with
     | Some param_names, Some generic_fields
       when List.length param_names = List.length ty_args ->
       let subst = List.combine param_names ty_args in
       List.map (Llvm_eq.apply_ty_subst subst) generic_fields
     | _ ->
       (ctor_entry ctx ctor_name n_args).Llvm_ctx.ce_fields)
  | _ ->
    (ctor_entry ctx ctor_name n_args).Llvm_ctx.ce_fields

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
      match Hashtbl.find_opt ctx.Llvm_ctx.field_map n with
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
  match Hashtbl.find_opt ctx.Llvm_ctx.rec_shape_globals desc with
  | Some pair -> pair
  | None ->
    let dg = Llvm_ctx.intern_string ctx desc in
    ctx.Llvm_ctx.str_ctr <- ctx.Llvm_ctx.str_ctr + 1;
    let cg = Printf.sprintf "@.recshape%d" ctx.Llvm_ctx.str_ctr in
    Buffer.add_string ctx.Llvm_ctx.preamble
      (Printf.sprintf "%s = internal global i32 0\n" cg);
    Hashtbl.replace ctx.Llvm_ctx.rec_shape_globals desc (dg, cg);
    (dg, cg)

(** Stamp the interned shape id of [fields] into record cell [ptr]'s header
    pad word.  No-op on WASM targets (no native runtime registry). *)
let emit_set_shape ctx ptr (fields : (string * Tir.ty) list) =
  if ctx.Llvm_ctx.shape_meta then begin
    let (dg, cg) = ensure_shape_globals ctx (shape_desc fields) in
    Llvm_ctx.emit ctx (Printf.sprintf
      "call void @march_record_set_shape(ptr %s, ptr %s, ptr %s)" ptr dg cg)
  end
