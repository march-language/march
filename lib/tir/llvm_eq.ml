(** LLVM emission: ADT structural-equality generation ([==]/[!=] on
    non-primitive types) plus the type-variable-substitution and
    equality-name-mangling helpers it needs.

    Wave 3 Task 5 (chunk 2) split: moved verbatim out of [llvm_emit.ml] —
    same discipline as the Wave 3 Task 3 [Llvm_ctx] split: whole-definition
    moves, no behavior change, fully-qualified references (no [open]).
    [apply_ty_subst] has no [ctx] dependency at all (pure [Tir.ty] rewrite)
    but is co-located here because [ensure_adt_eq_fn] is its only in-module
    caller; [llvm_data.ml]'s [resolve_ctor_fields] also needs it and calls
    [Llvm_eq.apply_ty_subst] (a forward reference from llvm_data → llvm_eq,
    not a cycle: llvm_eq never depends on llvm_data). *)

(** Apply a type-variable substitution to a TIR type. *)
let rec apply_ty_subst (subst : (string * Tir.ty) list) : Tir.ty -> Tir.ty = function
  | Tir.TVar n ->
    (match List.assoc_opt n subst with Some t -> t | None -> Tir.TVar n)
  | Tir.TCon (n, args) -> Tir.TCon (n, List.map (apply_ty_subst subst) args)
  | Tir.TFn (ps, r)    -> Tir.TFn (List.map (apply_ty_subst subst) ps, apply_ty_subst subst r)
  | Tir.TTuple ts      -> Tir.TTuple (List.map (apply_ty_subst subst) ts)
  | Tir.TPtr t         -> Tir.TPtr (apply_ty_subst subst t)
  | t -> t

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
let rec ensure_adt_eq_fn (ctx : Llvm_ctx.ctx) (ty : Tir.ty) : string option =
  match ty with
  | Tir.TCon ("Atom", []) -> None  (* Atoms stored as i64, not heap ptrs *)
  | Tir.TCon (type_name, ty_args) ->
    let fn_name = "__march_eq_" ^ mangle_ty_for_eq ty in
    if Hashtbl.mem ctx.Llvm_ctx.emitted_eq_fns fn_name then Some fn_name
    else begin
      (* Newtype-repr types (exactly one ctor with exactly one non-Float field)
         have NO wrapper cell: the value IS its raw payload — a heap pointer for
         String/Boxed-ADT/tuple/record payloads, a tagged immediate for Int/Bool.
         The generic Boxed strategy's tag load at [payload+8] and field load at
         [payload+16] would read INTO the payload's own heap layout (garbage),
         so [==] silently returned wrong answers (a String-payload Newtype
         compared unequal to itself; a Boxed-ADT-payload Newtype compared two
         distinct values equal).  Mirror the Niche arm: compare the operands
         directly per the payload's own repr.  Checked before niche detection —
         the shapes are mutually exclusive (Newtype = 1 ctor, Niche = 2 ctors) —
         and [repr_of_ty] already routes Float-payload single-ctor types to
         Boxed (float bits can't be tagged), so those still take the Boxed arm,
         which is correct for them (they DO carry a real heap header). *)
      let newtype_payload_opt =
        match Repr.repr_of_ty ~collision_set:ctx.Llvm_ctx.collision_set ctx.Llvm_ctx.type_defs ty with
        | Repr.Newtype raw_payload ->
          (* [raw_payload] is the field type as written in the typedef — a
             [TVar] for a generic newtype (e.g. [Wrap(a)] applied to [Int]).
             Substitute the concrete type args, exactly as the Boxed arm does. *)
          let subst =
            match Hashtbl.find_opt ctx.Llvm_ctx.type_params type_name with
            | Some ps when List.length ps = List.length ty_args ->
              List.combine ps ty_args
            | _ -> []
          in
          Some (apply_ty_subst subst raw_payload)
        | _ -> None
      in
      (* Niche-encoded Option types (None=null, Some(x)=x in a ptr slot) must NOT
         use the normal tag-at-offset-8 strategy — there is no heap header.
         Detect niche shape early and emit a null-check equality instead. *)
      let niche_payload_opt =
        if Repr.is_niche_shaped ~collision_set:ctx.Llvm_ctx.collision_set ctx.Llvm_ctx.type_defs type_name then
          match ty_args with
          | [p] when Repr.niche_payload_ok ~collision_set:ctx.Llvm_ctx.collision_set ctx.Llvm_ctx.type_defs p -> Some p
          | [p] when (match p with Tir.TVar _ -> true | _ -> false) ->
            (* Abstract (erased) payload — e.g. Option(Any) from record_get.
               EAlloc and emit_case both niche-encode a niche-shaped type applied
               to a type variable (None=null, Some(x)=x; see emit_case's
               "abstract-arg niche path"), so the eq fn MUST use the null-check
               strategy too.  The boxed path would load a ctor tag at offset 8 and
               dereference the null None value (or a tagged-scalar Some) → SIGSEGV
               (crash observed as __march_eq_Option_Any @ 0x8).  The both-Some arm
               below falls back to a raw pointer compare for the un-eq-able
               erased payload — safe, though only pointer-identity precise. *)
            Some p
          | _ -> None
        else None
      in
      (* Repr audit hook — the equality function is a third commitment site
         (after alloc and match); record which strategy it picks. *)
      Llvm_ctx.repr_audit_record ~ty:type_name
        ~payload:(match ty_args with
          | [] -> "?"
          | _ -> String.concat "," (List.map mangle_ty_for_eq ty_args))
        ~family:(if newtype_payload_opt <> None then "Newtype"
                 else if niche_payload_opt <> None then "Niche" else "Boxed")
        ~site:("eq:" ^ fn_name);
      match newtype_payload_opt with
      | Some payload_ty ->
        (* The operands ARE the raw payloads (no unwrapping cell).  Compare them
           directly per the payload's repr — no tag/field offset loads. *)
        Hashtbl.add ctx.Llvm_ctx.emitted_eq_fns fn_name ();
        let buf = Buffer.create 256 in
        let ctr = ref 0 in
        let frsh pfx = incr ctr; Printf.sprintf "%%%s%d" pfx !ctr in
        let e ln = Buffer.add_string buf ("  " ^ ln ^ "\n") in
        Buffer.add_string buf
          (Printf.sprintf "\ndefine i64 @%s(ptr %%a, ptr %%b) {\n" fn_name);
        Buffer.add_string buf "entry:\n";
        let ok = frsh "ok" in
        (match payload_ty with
         | Tir.TString ->
           e (Printf.sprintf "%s = call i64 @march_string_eq(ptr %%a, ptr %%b)" ok)
         | Tir.TFloat ->
           (* A Newtype-over-Float only reaches here via a generic newtype
              instantiated at Float (non-generic Float newtypes are Boxed).  The
              raw double bits live in the ptr slot — reinterpret and compare. *)
           let pa = frsh "pa" in let pb = frsh "pb" in
           e (Printf.sprintf "%s = ptrtoint ptr %%a to i64" pa);
           e (Printf.sprintf "%s = ptrtoint ptr %%b to i64" pb);
           let da = frsh "da" in let db = frsh "db" in
           e (Printf.sprintf "%s = bitcast i64 %s to double" da pa);
           e (Printf.sprintf "%s = bitcast i64 %s to double" db pb);
           let c = frsh "c" in
           e (Printf.sprintf "%s = fcmp oeq double %s, %s" c da db);
           e (Printf.sprintf "%s = zext i1 %s to i64" ok c)
         | _ when Repr.payload_needs_tag ~collision_set:ctx.Llvm_ctx.collision_set ctx.Llvm_ctx.type_defs payload_ty ->
           (* Tagged scalar (Int/Bool, or a newtype over one) in a ptr slot:
              compare the raw tagged bits. *)
           let pa = frsh "pa" in let pb = frsh "pb" in
           e (Printf.sprintf "%s = ptrtoint ptr %%a to i64" pa);
           e (Printf.sprintf "%s = ptrtoint ptr %%b to i64" pb);
           let c = frsh "c" in
           e (Printf.sprintf "%s = icmp eq i64 %s, %s" c pa pb);
           e (Printf.sprintf "%s = zext i1 %s to i64" ok c)
         | _ ->
           (* Heap payload (Boxed ADT / tuple / record, or a nested Newtype):
              the operands are the payload's own heap pointers, so recurse into
              its structural equality and call it on them directly.  If no eq
              fn is derivable (an erased [TVar] payload), fall back to
              [march_poly_eq] — the runtime-shape-dispatched comparison the
              top-level [==] site uses for polymorphic operands (strings by
              content, immediates by value) — not a pointer-identity compare. *)
           (match ensure_adt_eq_fn ctx payload_ty with
            | Some fn ->
              e (Printf.sprintf "%s = call i64 @%s(ptr %%a, ptr %%b)" ok fn)
            | None ->
              e (Printf.sprintf "%s = call i64 @march_poly_eq(ptr %%a, ptr %%b)" ok)));
        e (Printf.sprintf "ret i64 %s" ok);
        Buffer.add_string buf "}\n";
        Buffer.add_buffer ctx.Llvm_ctx.extra_fns buf;
        Some fn_name
      | None ->
      match niche_payload_opt with
      | Some payload_ty ->
        Hashtbl.add ctx.Llvm_ctx.emitted_eq_fns fn_name ();
        let buf = Buffer.create 256 in
        let ctr = ref 0 in let blk = ref 0 in
        let frsh pfx = incr ctr; Printf.sprintf "%%%s%d" pfx !ctr in
        let flbl pfx = incr blk; Printf.sprintf "%s%d" pfx !blk in
        let e ln  = Buffer.add_string buf ("  " ^ ln ^ "\n") in
        let lbl l = Buffer.add_string buf (l ^ ":\n") in
        let lbl_anull        = flbl "nq_anull" in
        let lbl_anonnull     = flbl "nq_asome" in
        let lbl_both_nonnull = flbl "nq_both" in
        let lbl_not_eq       = flbl "nq_neq" in
        let lbl_eq           = flbl "nq_eq" in
        Buffer.add_string buf (Printf.sprintf "\ndefine i64 @%s(ptr %%a, ptr %%b) {\n" fn_name);
        Buffer.add_string buf "entry:\n";
        let anc = frsh "anc" in
        e (Printf.sprintf "%s = icmp eq ptr %%a, null" anc);
        e (Printf.sprintf "br i1 %s, label %%%s, label %%%s" anc lbl_anull lbl_anonnull);
        (* a == null (None): equal iff b is also null *)
        lbl lbl_anull;
        let bnc1 = frsh "bnc" in
        e (Printf.sprintf "%s = icmp eq ptr %%b, null" bnc1);
        e (Printf.sprintf "br i1 %s, label %%%s, label %%%s" bnc1 lbl_eq lbl_not_eq);
        (* a != null (Some): not equal if b == null *)
        lbl lbl_anonnull;
        let bnc2 = frsh "bnc" in
        e (Printf.sprintf "%s = icmp eq ptr %%b, null" bnc2);
        e (Printf.sprintf "br i1 %s, label %%%s, label %%%s" bnc2 lbl_not_eq lbl_both_nonnull);
        (* Both non-null (both Some): compare payloads *)
        lbl lbl_both_nonnull;
        let ok = frsh "ok" in
        (match payload_ty with
         | Tir.TString ->
           e (Printf.sprintf "%s = call i64 @march_string_eq(ptr %%a, ptr %%b)" ok)
         | _ when Repr.payload_needs_tag ~collision_set:ctx.Llvm_ctx.collision_set ctx.Llvm_ctx.type_defs payload_ty ->
           (* Tagged scalar (Int/Bool) in ptr slot: compare raw tagged bits *)
           let pa = frsh "pa" in let pb = frsh "pb" in
           e (Printf.sprintf "%s = ptrtoint ptr %%a to i64" pa);
           e (Printf.sprintf "%s = ptrtoint ptr %%b to i64" pb);
           let c = frsh "c" in
           e (Printf.sprintf "%s = icmp eq i64 %s, %s" c pa pb);
           e (Printf.sprintf "%s = zext i1 %s to i64" ok c)
         | _ ->
           (match ensure_adt_eq_fn ctx payload_ty with
            | Some fn ->
              e (Printf.sprintf "%s = call i64 @%s(ptr %%a, ptr %%b)" ok fn)
            | None ->
              let pa = frsh "pa" in let pb = frsh "pb" in
              e (Printf.sprintf "%s = ptrtoint ptr %%a to i64" pa);
              e (Printf.sprintf "%s = ptrtoint ptr %%b to i64" pb);
              let c = frsh "c" in
              e (Printf.sprintf "%s = icmp eq i64 %s, %s" c pa pb);
              e (Printf.sprintf "%s = zext i1 %s to i64" ok c)));
        let oki = frsh "oki" in
        e (Printf.sprintf "%s = icmp ne i64 %s, 0" oki ok);
        e (Printf.sprintf "br i1 %s, label %%%s, label %%%s" oki lbl_eq lbl_not_eq);
        lbl lbl_eq;     e "ret i64 1";
        lbl lbl_not_eq; e "ret i64 0";
        Buffer.add_string buf "}\n";
        Buffer.add_buffer ctx.Llvm_ctx.extra_fns buf;
        Some fn_name
      | None ->
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
        ) ctx.Llvm_ctx.ctor_info []
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
            (entry.Llvm_ctx.ce_tag, cn, entry.Llvm_ctx.ce_fields) :: acc
          else acc
        ) ctx.Llvm_ctx.ctor_info []
      in
      let resolved =
        match candidate_paths with
        | [] -> None
        | [tp] -> Some (tp, ctors_of tp)
        | tps ->
          (* Multiple candidate declaring paths for one short name means this
             short name is in the collision set (>=2 distinct qualified
             TDVariant names share it — see [Collision_set.compute]): a
             single-declaration type can never produce more than one match
             here. Since [Llvm_toplevel.build_ctor_info]'s collision arm
             gives every colliding type's constructors a GLOBALLY-unique
             [ce_tag] (a dedicated counter, never reused across candidates),
             no two candidates' tags can ever coincide — so it is always safe
             to union every candidate's ctors into one switch table: each
             tag uniquely identifies both the declaring type and the
             constructor.
             Before Task 1 this used to pick only the largest candidate and
             required every other candidate's ctors to match its layout on
             common TAG NUMBERS (tags were per-type 0-based, so two
             candidates' tags could coincidentally collide, e.g. both
             declaring a nullary ctor at tag 0) — that subsumption check was
             a safety net against tag-number aliasing across candidates. With
             tags now globally unique the aliasing risk that check guarded
             against no longer exists, and the check instead incorrectly
             rejected same-ctor-name colliders whose tags (correctly) no
             longer overlap (e.g. two same-short-name types both declaring
             `AeNorth`), silently falling back to pointer-identity-ish
             [march_poly_compare] (which treats any two distinct non-string/
             float heap cells as equal — a real `==` miscompile). *)
          let all = List.map (fun tp -> (tp, ctors_of tp)) tps in
          let union_ctors = List.concat_map snd all in
          (* Representative type name = the first candidate (order is not
             semantically load-bearing).  This assumes all colliding candidates
             share the same type-parameter arity — true for every current
             colliding fixture (all monomorphic ADTs); a set mixing e.g. a
             nullary and a unary same-short-name type would need rep_tp chosen
             per the use-site's instantiation instead. *)
          let rep_tp = fst (List.hd all) in
          Some (rep_tp, union_ctors)
      in
      match resolved with
      | None -> None
      | Some (_, []) -> None
      | Some (resolved_name, ctors) ->
      Hashtbl.add ctx.Llvm_ctx.emitted_eq_fns fn_name ();
      let subst =
        match Hashtbl.find_opt ctx.Llvm_ctx.type_params resolved_name with
        | Some ps when List.length ps = List.length ty_args -> List.combine ps ty_args
        | _ ->
          (match Hashtbl.find_opt ctx.Llvm_ctx.type_params type_name with
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
        (* Degenerate-value guard.  A value of this type may arrive in the
           ERASED niche encoding (None = null, Some(x) = x raw / low-bit
           tagged) when it crossed an erased boundary — record_get,
           record_entries, a generic helper — even though the CONCRETE type is
           boxed (e.g. Option(Float)).  The boxed strategy's unconditional
           tag load at [v+8] then derefs null / a tagged immediate → SIGSEGV
           (__march_eq_Option_Float @ 0x8, depot "Float type default in
           blank").  Guard: pointer-equal → eq; null vs heap-cell → compare
           the cell's tag against the NULLARY ctor (null IS the niche nullary);
           any low-bit-tagged immediate (≠ per ptr-eq) → not_eq.  Residual
           (documented): a niche Some carrying EVEN non-ptr float bits still
           tag-loads garbage — fixed only by a uniform Option encoding. *)
        let nullary_tag =
          List.fold_left (fun acc (tag, _, flds) ->
            match acc, flds with None, [] -> Some tag | _ -> acc) None ctors
        in
        let lbl_boxed  = flbl "eq_boxed" in
        let lbl_chka   = flbl "eq_chka" in
        let lbl_chkb   = flbl "eq_chkb" in
        let lbl_chkodd = flbl "eq_chkodd" in
        let peq = frsh "peq" in
        e (Printf.sprintf "%s = icmp eq ptr %%a, %%b" peq);
        e (Printf.sprintf "br i1 %s, label %%%s, label %%%s" peq lbl_eq lbl_chka);
        lbl lbl_chka;
        let ai = frsh "ai" in let bi = frsh "bi" in
        e (Printf.sprintf "%s = ptrtoint ptr %%a to i64" ai);
        e (Printf.sprintf "%s = ptrtoint ptr %%b to i64" bi);
        let emit_null_arm ~null_lbl ~other_i ~other_ptr ~next_lbl =
          let anull = frsh "isnull" in
          e (Printf.sprintf "%s = icmp eq i64 %s, 0"
               anull (if other_ptr = "%b" then ai else bi));
          e (Printf.sprintf "br i1 %s, label %%%s, label %%%s" anull null_lbl next_lbl);
          lbl null_lbl;
          (match nullary_tag with
           | None -> e (Printf.sprintf "br label %%%s" lbl_not_eq)
           | Some ntag ->
             let odd = frsh "odd" in
             e (Printf.sprintf "%s = trunc i64 %s to i1" odd other_i);
             let tagl = flbl "eq_nulltag" in
             e (Printf.sprintf "br i1 %s, label %%%s, label %%%s" odd lbl_not_eq tagl);
             lbl tagl;
             let tp = frsh "ntp" in let tv = frsh "ntv" in
             e (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 8" tp other_ptr);
             e (Printf.sprintf "%s = load i32, ptr %s, align 4" tv tp);
             let c = frsh "ntc" in
             e (Printf.sprintf "%s = icmp eq i32 %s, %d" c tv ntag);
             e (Printf.sprintf "br i1 %s, label %%%s, label %%%s" c lbl_eq lbl_not_eq))
        in
        let anull_lbl = flbl "eq_anull" in
        emit_null_arm ~null_lbl:anull_lbl ~other_i:bi ~other_ptr:"%b" ~next_lbl:lbl_chkb;
        lbl lbl_chkb;
        let bnull_lbl = flbl "eq_bnull" in
        emit_null_arm ~null_lbl:bnull_lbl ~other_i:ai ~other_ptr:"%a" ~next_lbl:lbl_chkodd;
        lbl lbl_chkodd;
        let aodd = frsh "aodd" in let bodd = frsh "bodd" in
        e (Printf.sprintf "%s = trunc i64 %s to i1" aodd ai);
        e (Printf.sprintf "%s = trunc i64 %s to i1" bodd bi);
        let anyodd = frsh "anyodd" in
        e (Printf.sprintf "%s = or i1 %s, %s" anyodd aodd bodd);
        e (Printf.sprintf "br i1 %s, label %%%s, label %%%s" anyodd lbl_not_eq lbl_boxed);
        lbl lbl_boxed;
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
        Buffer.add_buffer ctx.Llvm_ctx.extra_fns buf;
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
    if Hashtbl.mem ctx.Llvm_ctx.emitted_eq_fns fn_name then Some fn_name
    else begin
      Hashtbl.add ctx.Llvm_ctx.emitted_eq_fns fn_name ();
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
      Buffer.add_buffer ctx.Llvm_ctx.extra_fns buf;
      Some fn_name
    end
  | _ -> None
