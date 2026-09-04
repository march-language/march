(** Record/tuple codegen: the bodies of [Llvm_emit.emit_expr]'s record
    introspection builtins and of its [ETuple] / [ERecord] / [EField] /
    [EUpdate] arms.

    Phase 2b of specs/plans/2026-08-19-compiler-file-decomposition.md, the
    per-arm delegation Phase 2 deferred.  Every arm keeps its exact position,
    guard and order in [emit_expr]'s match -- match order there is
    load-bearing (non-builtin arms interleave with builtin ones, and the TCO
    arms sit below several builtin arms), so nothing is grouped or reordered.
    Only the arm BODIES live here, byte-identical to the text they replaced.
    [emit_atom] is threaded in as a labelled callback, the convention
    [Llvm_emit_simd] and [Llvm_emit_nmap] established.

    The record introspection builtins cannot be plain C externs because record
    values carry no field names at runtime; they rely on the shape id stamped
    into the header pad word by [emit_set_shape] and pass call-site value-kind
    hints.  See the "Record shape registry" section in runtime/march_extras.c. *)

open Llvm_ctx

let emit_store_field = Llvm_data.emit_store_field
let emit_load_field = Llvm_data.emit_load_field
let emit_heap_alloc = Llvm_data.emit_heap_alloc
let get_record_fields = Llvm_data.get_record_fields
let field_index_for = Llvm_data.field_index_for
let atom_tir_ty = Llvm_data.atom_tir_ty
let shape_kind_char = Llvm_data.shape_kind_char
let emit_set_shape = Llvm_data.emit_set_shape

(** Body of the `record_keys` / `record_values` / `record_entries` arm. *)
let emit_record_walk ~emit_atom ctx (f : Tir.var) (r : Tir.atom)
  : string * string =
    let (rt, rv) = emit_atom ctx r in
    let rp = coerce ctx rt rv "ptr" in
    let res = fresh ctx "cr" in
    emit ctx (Printf.sprintf "%s = call ptr @march_%s(ptr %s)"
                res f.Tir.v_name rp);
    ("ptr", res)

(** Body of the `record_get` arm. *)
let emit_record_get ~emit_atom ctx (f : Tir.var) (r : Tir.atom) (k : Tir.atom)
  : string * string =
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

(** Body of the `record_has_key` arm. *)
let emit_record_has_key ~emit_atom ctx (r : Tir.atom) (k : Tir.atom)
  : string * string =
    let (rt, rv) = emit_atom ctx r in
    let rp = coerce ctx rt rv "ptr" in
    let (kt, kv) = emit_atom ctx k in
    let kp = coerce ctx kt kv "ptr" in
    let res = fresh ctx "cr" in
    emit ctx (Printf.sprintf "%s = call i64 @march_record_has_key(ptr %s, ptr %s)"
                res rp kp);
    ("i64", res)

(** Body of the `record_put` arm. *)
let emit_record_put ~emit_atom ctx (r : Tir.atom) (k : Tir.atom)
  (v : Tir.atom) : string * string =
    let (rt, rv) = emit_atom ctx r in
    let rp = coerce ctx rt rv "ptr" in
    let (kt, kv) = emit_atom ctx k in
    let kp = coerce ctx kt kv "ptr" in
    let (vt, vv) = emit_atom ctx v in
    (* Pass the value in UNIFORM representation as a ptr-sized word: scalars
       low-bit tagged (coerce i64→ptr), raw bits for floats, ptr as-is.
       Natural repr is ambiguous — an even Int >= 4096 is bit-identical to a
       heap pointer, so the runtime's plausible-heap sniff would incrc
       (dereference) the integer's value.  Tagged scalars are always odd and
       untag unambiguously in rec_field_norm_uniform. *)
    let vp = (match vt with
      | "i64" -> coerce ctx "i64" vv "ptr"
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

(** Body of the `record_from_list` arm. *)
let emit_record_from_list ~emit_atom ctx (l : Tir.atom) : string * string =
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

(** Body of the non-empty [ETuple] arm. *)
let emit_tuple ~emit_atom ctx (atoms : Tir.atom list) : string * string =
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

(** Body of the [ERecord] arm. *)
let emit_record ~emit_atom ctx (fields : (string * Tir.atom) list)
  : string * string =
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

(** Body of the [EField] arm. *)
let emit_field ~emit_atom ctx (obj_atom : Tir.atom) (field_name : string)
  : string * string =
    let obj_ty = match obj_atom with
      | Tir.AVar v    -> v.Tir.v_ty
      | Tir.ADefRef _ -> Tir.TVar "_"
      | Tir.ALit _    -> Tir.TVar "_"
    in
    (* Closure free-variable fields: "$fvN" — parse index from name directly
       since the closure pointer is opaque (TPtr TUnit) with no field_map. *)
    if Tir_names.is_fv_field field_name then begin
      let i = Tir_names.fv_field_index field_name in
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
        (match field_ty with
         | Tir.TVar _ when ctx.shape_meta ->
           (* The record's shape is statically known but THIS field's type is
              still an unresolved type variable — monomorphisation did not
              reach it (e.g. a record rebuilt inside a generic `List.map`
              lambda and consumed by a separate function).  A TVar says
              nothing about the field's representation, so a direct typed load
              is unsound: emitting one loads the slot as `ptr` and the ptr->i64
              coercion then untags it, which silently HALVES any odd integer
              (35 read back as 17) while leaving even ones intact.

              Fall back to the by-name shape lookup used for wholly-unknown
              records.  It consults the runtime shape recorded at construction
              and returns ints low-bit tagged, which is exactly the generic
              ADT-slot convention the consuming coercion expects. *)
           let (_, obj_val) = emit_atom ctx obj_atom in
           let ng = intern_string ctx field_name in
           let res = fresh ctx "cr" in
           emit ctx (Printf.sprintf
             "%s = call ptr @march_record_field_dyn(ptr %s, ptr %s, i64 %d)"
             res obj_val ng (String.length field_name));
           ("ptr", res)
         | _ ->
           let (_, obj_val) = emit_atom ctx obj_atom in
           let fv = emit_load_field ctx obj_val idx (llvm_ty field_ty) in
           (llvm_ty field_ty, fv))
    end

(** Body of the [EUpdate] arm (record update). *)
let emit_update ~emit_atom ctx (base_atom : Tir.atom)
  (updates : (string * Tir.atom) list) : string * string =
    let base_ty = match base_atom with
      | Tir.AVar v    -> v.Tir.v_ty
      | Tir.ADefRef _ -> Tir.TVar "_"
      | Tir.ALit _    -> Tir.TVar "_"
    in
    let all_fields = get_record_fields ctx base_ty in
    let (_, base_val) = emit_atom ctx base_atom in
    if all_fields = [] && updates <> [] then begin
      (* Statically-unknown record shape (type-erased generic flow, e.g. the
         result of record_put/record_from_list): field offsets can't be
         computed at compile time, so [field_index_for]'s "(0, TVar _)"
         fallback would make every update write field 0 of a header-only
         cell (n=0 from emit_heap_alloc) — corrupting memory past the
         allocation.  Mirror the EField dyn fallback above: a single call
         to march_record_update_dyn (by-name, shape-registry-aware), which
         copies the base cell ONCE and overwrites the named fields — no
         per-field intermediate allocations.  NOTE: unlike the
         statically-known case, the typechecker CANNOT validate the update
         names here (its TVar branch builds a partial record constraint
         from the update's own names — it never sees the base's actual
         fields), so the runtime panics on a missing name (mirroring
         march_record_field_dyn) instead of silently fabricating a new
         field (march_record_put's new-key behavior) or writing out of
         bounds. *)
      let args = List.concat_map (fun (fname, atom) ->
        let ng = intern_string ctx fname in
        let (vt, vv) = emit_atom ctx atom in
        (* Pass the value in UNIFORM representation, matching record_put's
           EApp call convention: scalars low-bit tagged (coerce i64→ptr),
           raw bits for floats, ptr as-is.  Natural repr is ambiguous — an
           even Int >= 4096 is bit-identical to a heap pointer, so
           rec_field_norm_in's plausible-heap sniff would incrc
           (dereference) the integer's value. *)
        let vp = (match vt with
          | "i64" -> coerce ctx "i64" vv "ptr"
          | "double" ->
            let b = fresh ctx "ruv" in
            let t = fresh ctx "ruv" in
            emit ctx (Printf.sprintf "%s = bitcast double %s to i64" b vv);
            emit ctx (Printf.sprintf "%s = inttoptr i64 %s to ptr" t b);
            t
          | _ -> vv) in
        let kind = shape_kind_char (atom_tir_ty atom) in
        [ Printf.sprintf "ptr %s" ng;
          Printf.sprintf "i64 %d" (String.length fname);
          Printf.sprintf "ptr %s" vp;
          Printf.sprintf "i64 %d" (Char.code kind) ]
      ) updates in
      let res = fresh ctx "ru" in
      emit ctx (Printf.sprintf
        "%s = call ptr (ptr, i64, ...) @march_record_update_dyn(ptr %s, i64 %d, %s)"
        res base_val (List.length updates) (String.concat ", " args));
      ("ptr", res)
    end else begin
    let n = List.length all_fields in
    (* Allocate new record of same size *)
    let ptr = emit_heap_alloc ctx 0 n in
    (* Copy all fields from base.  Each copied HEAP field is inc'd: the base
       keeps its own reference (an update borrows the base, it does not consume
       it) and the new cell takes a second one, so both can be released
       independently.  Without the inc the two cells share children with a
       single refcount between them, and once aggregates became deep-dropped
       that was a double-free -- masked, until this landed, by a stray inc on
       the base itself that kept its refcount from ever reaching zero.

       Fields whose slot is not a pointer (Int/Float/Bool/Unit) carry no
       reference, so they are copied as before. *)
    List.iteri (fun i (_, fty) ->
      let lty = llvm_ty fty in
      let fv = emit_load_field ctx base_val i lty in
      if Rc_types.needs_rc fty && String.equal lty "ptr" then
        emit ctx (Printf.sprintf "call void @march_incrc(ptr %s)" fv);
      emit_store_field ctx ptr i lty fv
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
    end

