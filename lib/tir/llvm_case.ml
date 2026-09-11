(** LLVM emission: [emit_case] — ECase → switch + branch blocks + merge, with
    the newtype/niche/boxed representation strategies (mirroring
    [Repr.repr_of_ty]'s three cases) plus the immediate-literal (atom/int/
    bool/string/float) switch-chain fallbacks for scrutinees that carry no
    heap header.

    Wave 3 Task 5 (chunk 2) split: moved verbatim out of [llvm_emit.ml] —
    same discipline as [Llvm_ctx]/[Llvm_eq]/[Llvm_data].  [emit_case] was
    mutually recursive with [emit_expr] (via [and]) in the original file:
    branch/default bodies are themselves [Tir.expr] and recurse back into
    the top-level expression emitter, which stays in [llvm_emit.ml] (the
    brief keeps the giant [emit_expr] match there).  The standard OCaml
    de-cycling move: [emit_expr] — and, similarly, [emit_atom] (used once,
    for the scrutinee atom) — are passed in as labeled callback parameters
    instead of being called by bare mutual-recursion.  [llvm_emit.ml] passes
    its own [emit_expr]/[emit_atom] at the single call site (the ECase match
    arm), so behavior is unchanged: same functions, same call graph, just
    threaded explicitly across the module boundary rather than implicitly
    via [and]. *)

(** Does this case arm DIVERGE — i.e. can control never actually arrive at the
    arm's merge block through it?

    Both merge paths below ([Repr.Niche]'s and the general boxed one) may
    unbox-and-free the ptr they merged, but only when EVERY arm reaching the
    merge produced a "double" pre-coercion — the proof that the ptr is a
    march_float_box this emit_case's own coerce allocated.  A
    match-compilation fallback default ([Lower_state.nonexhaustive_panic],
    `panic_("non-exhaustive pattern match")`) is emitted as an ordinary arm:
    it calls @march_panic_ext, declared to return ptr, and stores that ptr
    like any other arm.  Its "ptr" spoiled the proof for EVERY match on a
    boxed ADT whose arms are Floats — the `match opt do Some(x) -> x;
    None -> 1.0 end` shape — so the freshly allocated box was handed to the
    caller as an opaque live ptr and never freed.

    Precision matters in one direction only: a FALSE positive here would
    unbox-and-free a ptr some other arm legitimately produced, i.e. a
    use-after-free.  So this recognises exactly the primitives that call
    @march_panic / @march_panic_ext and never return to their caller
    (march_panic aborts, or longjmps to the test runner under
    march_test_in_test) — the same four names llvm_emit's [is_known_fn] table
    lists.  A user-written `panic("…")` routed through a March prelude wrapper
    is NOT recognised (its callee is an ordinary March fn) and keeps the
    pre-existing leak: the safe direction. *)
let rec arm_diverges (e : Tir.expr) : bool =
  match e with
  | Tir.EApp (f, _) ->
    (match f.Tir.v_name with
     | "panic" | "panic_" | "todo_" | "unreachable_" -> true
     | _ -> false)
  | Tir.ESeq (_, e2) | Tir.ELet (_, _, e2) -> arm_diverges e2
  | _ -> false

(** Finish a case/match join whose result slot is a `ptr`.

    Every arm stores through [Llvm_ctx.coerce ... "ptr"], so when all arms that
    reach the merge shared ONE pre-coercion LLVM type that is not itself "ptr",
    the pointer just loaded is a box allocated by this [emit_case]'s own
    coerce-to-ptr calls: never escaped, never aliased, never read by anyone
    else.  Nobody downstream owns it — the arm types are what the caller sees,
    and for both boxable types below [Rc_types.needs_rc] is false for that
    type, so Perceus emits no drop.  This merge is therefore the only place
    that can release it, and must:

    - "double" → a [march_alloc_float] cell (float-boxing Stage 2).  Leaking it
      cost one cell per evaluation
      (specs/progress/2026-08-22-erased-slot-ownership-leaks.md).
    - an unboxed small aggregate's struct type → a [march_alloc] cell built by
      [Llvm_ctx.coerce]'s inline-aggregate boxing arm (Milestone 3).  Same
      leak, same shape: a `Pair(Float, Float)` built inside an `if` leaked one
      cell per construction, 5 001 live objects over 5 000 iterations
      (specs/progress/2026-09-04-unboxed-aggregate-branch-join-leak.md).

    Both frees are [march_decrc_local], which is a SHALLOW free — it does not
    walk the cell's fields.  That matters for the aggregate box: its fields are
    raw scalars ([Repr.is_scalar_field] admits only Int/Float/Bool), so a
    field-walking free would sniff a raw double's bits with IS_HEAP_PTR and
    recurse into garbage.  Unbox BEFORE the release, so the loads read a live
    cell.

    Any other mix of arm types — including plain "ptr" arms, whose value came
    from somewhere else and is owned by someone else — hands the loaded pointer
    back untouched, exactly as before. *)
let finish_ptr_merge ctx ~arm_tys ~loaded =
  match arm_tys with
  | [] -> ("ptr", loaded)
  | t0 :: rest when List.for_all (fun t -> t = t0) rest ->
    if t0 = "double" then begin
      let d = Llvm_ctx.fresh ctx "case_rd" in
      Llvm_ctx.emit ctx
        (Printf.sprintf "%s = call double @march_unbox_float(ptr %s)" d loaded);
      Llvm_ctx.emit ctx (Printf.sprintf "call void @march_decrc_local(ptr %s)" loaded);
      ("double", d)
    end else if Repr.unboxed_of_llvm_ty t0 <> None then begin
      let v = Llvm_ctx.coerce ctx "ptr" loaded t0 in
      Llvm_ctx.emit ctx (Printf.sprintf "call void @march_decrc_local(ptr %s)" loaded);
      (t0, v)
    end else ("ptr", loaded)
  | _ -> ("ptr", loaded)

let emit_case ~emit_expr ~emit_atom ctx scrut_atom branches default_opt =
  let (scrut_ty, scrut_val) = emit_atom ctx scrut_atom in
  let scrut_tir_ty_init =
    match scrut_atom with Tir.AVar v -> v.Tir.v_ty | _ -> Tir.TUnit
  in
  (* Recover a niche match when the scrutinee type is unresolved.  A scrutinee
     typed [TVar "_"] (e.g. a lazily-loaded module body whose expression types
     were never inferred) makes [repr_of_ty] return [Boxed], which lowers the
     match with the heap-tag strategy (load a ctor tag at [scrut+8]).  For a
     niche-encoded type (Option-shaped) the value is a tagged scalar or null —
     not a heap cell — so that load segfaults.  If the branch constructors name
     a niche-shaped type, use the niche strategy with [tagged=false] so the
     payload is taken verbatim; the erased-i64 convention then conditionally
     untags it at its concrete use sites.  The generated niche code is identical
     for every niche type at [tagged=false], so we only need to know *whether*
     the match is niche-shaped, not which type.  Boxed ADTs are unaffected — the
     heap-tag path is already correct for them. *)
  let branches_match_niche_shape () =
    let ctor_tags = List.filter_map (fun br ->
      let t = br.Tir.br_tag in
      if String.length t > 0 && t.[0] >= 'A' && t.[0] <= 'Z' then Some t else None
    ) branches in
    ctor_tags <> [] &&
    (* Candidate owners: EVERY variant typedef whose ctor set contains all the
       branch ctor tags — with the scrutinee type erased, any of them could be
       its true type.  Commit to the niche decode only when they ALL classify
       niche-shaped (mirrors [newtype_recovery_payload]'s all-owners ambiguity
       discipline below; any ambiguity keeps Boxed, the status quo).  The
       previous [List.exists] committed on the FIRST niche-shaped owner: a
       single-ctor branch set like ["Row"] matched Csv's niche-shaped
       `CsvRow = CsvEof | Row(List(String))` even when the value was really a
       BOXED `DataFrame.Row = Row(List((String, Value)))` — the niche identity
       decode then bound the box pointer itself as the payload, whose header
       read as an empty list (tag 0 = Nil): DataFrame group_by/inner_join/
       summarize silently returned 0 rows compiled.  Matches that list a
       DISTINGUISHING ctor set (e.g. both CsvEof and Row) are unaffected:
       their only owner is the genuine niche type. *)
    (let owners = List.filter_map (function
       | Tir.TDVariant (tname, variants)
         when (let ctor_names = List.map fst variants in
               List.for_all (fun t -> List.mem t ctor_names) ctor_tags) ->
         Some tname
       | _ -> None) ctx.Llvm_ctx.type_defs in
     owners <> [] &&
     List.for_all (fun tname ->
       Repr.is_niche_shaped ~collision_set:ctx.Llvm_ctx.collision_set ctx.Llvm_ctx.type_defs tname) owners)
  in
  (* Newtype analogue of the niche recovery: [lower_match] mints destructured
     sub-pattern variables with [unknown_ty], so a nested match on one (e.g.
     the tuple elements of derived Eq's [match (a, b)], or any hand-written
     nested destructure) reaches here typed [TVar] and would take the boxed
     heap-tag strategy — a load at [scrut+8] — but a Newtype-repr value IS its
     raw payload (tagged scalar or payload heap ptr): SIGSEGV on scalars, a
     garbage tag (non-exhaustive panic) on heap payloads.  A single
     Ctor-tagged branch identifies the type by ctor name: when every variant
     typedef owning that ctor classifies as [Newtype] AND they agree on
     payload tagging, the decode is identical whichever of them the scrutinee
     really is, so we can commit to the Newtype strategy with the typedef's
     payload — matching EAlloc's encode side exactly.  Any ambiguity (a boxed
     type sharing the ctor name, or disagreeing tagging) keeps Boxed, the
     status quo. *)
  let newtype_recovery_payload () : Tir.ty option =
    match branches with
    | [br] when (let t = br.Tir.br_tag in
                 String.length t > 0 && t.[0] >= 'A' && t.[0] <= 'Z') ->
      let tag = br.Tir.br_tag in
      (* Classify the owning type by the SAME name construction/EAlloc uses: the
         BARE type name (its ctor key is "TypeName.CtorName").  A type defined in
         a NON-ENTRY module is registered here under its module-qualified name
         (e.g. "Bytes.Bytes"), but EAlloc and top-level patterns resolve it by the
         bare "Bytes" and so classify it [Boxed] (the runtime constructs `Bytes`
         boxed too — [make_bytes_from_raw]).  If the recovery instead looked up
         the qualified [tname] it would see [Newtype] and take the identity path
         for a boxed value — reading a box header as an empty niche payload
         (compiled `Bytes.concat` returned an empty `Bytes`, hanging forgepm's
         Postgres handshake).  Stripping to the bare name keeps the recovery
         consistent with construction: a genuine (entry-module) newtype is
         registered bare so [last_seg] is a no-op and it still classifies
         [Newtype]. *)
      let last_seg s =
        match String.rindex_opt s '.' with
        | Some i -> String.sub s (i + 1) (String.length s - i - 1)
        | None -> s
      in
      let owner_reprs = List.filter_map (function
        | Tir.TDVariant (tname, variants)
          when List.exists (fun (c, _) -> c = tag) variants ->
          Some (Repr.repr_of_ty ~collision_set:ctx.Llvm_ctx.collision_set ctx.Llvm_ctx.type_defs
                  (Tir.TCon (last_seg tname, [])))
        | _ -> None) ctx.Llvm_ctx.type_defs in
      (match owner_reprs with
       | Repr.Newtype p0 :: rest
         when List.for_all (function
             | Repr.Newtype p ->
               Repr.payload_needs_tag ~collision_set:ctx.Llvm_ctx.collision_set ctx.Llvm_ctx.type_defs p
               = Repr.payload_needs_tag ~collision_set:ctx.Llvm_ctx.collision_set ctx.Llvm_ctx.type_defs p0
             | _ -> false) rest ->
         Some p0
       | _ -> None)
    | _ -> None
  in
  let effective_repr =
    match Repr.repr_of_ty ~collision_set:ctx.Llvm_ctx.collision_set ctx.Llvm_ctx.type_defs scrut_tir_ty_init with
    | Repr.Boxed
      when (match scrut_tir_ty_init with Tir.TVar _ -> true | _ -> false)
           && newtype_recovery_payload () <> None ->
      (match newtype_recovery_payload () with
       | Some p -> Repr.Newtype p
       | None -> Repr.Boxed (* unreachable: guard checked <> None *))
    | Repr.Boxed
      when (
        (* TVar path: scrutinee type unknown (unresolved module body), recover
           niche from the branch constructor names. *)
        ((match scrut_tir_ty_init with Tir.TVar _ -> true | _ -> false)
         && branches_match_niche_shape ())
        ||
        (* Abstract-arg niche path: niche-shaped type name applied to abstract
           (TVar) type arguments -- e.g. TCon("Option", [TVar "_1234"]) produced
           when the scrutinee's typemap entry has an unresolved type variable.
           repr_of_ty conservatively returns Boxed because niche_payload_ok(TVar)
           is false, but the concrete callee decided Niche by its return type.
           The ctor shape is determined by the type name alone, so trust
           is_niche_shaped and emit Niche. *)
        (match scrut_tir_ty_init with
         | Tir.TCon (name, args) when args <> [] ->
           (List.exists (function Tir.TVar _ -> true | _ -> false) args)
           && Repr.is_niche_shaped ~collision_set:ctx.Llvm_ctx.collision_set ctx.Llvm_ctx.type_defs name
         | _ -> false)
      ) ->
      Repr.Niche { payload = Tir.TVar "_"; tagged = false }
    | Repr.Boxed
      when (match scrut_tir_ty_init with
            | Tir.TCon (_, []) -> true
            | _ -> false) ->
      (* Concrete niche path: non-generic Option-shaped TCon (e.g. an actor
         message type [Inc(Int) | Probe]) — repr_of_ty returns Boxed because
         the TCon carries no type params, but the variant DEF carries the
         concrete payload type.  Classify from the def so the decode matches
         the EAlloc/EReuse encode exactly:
           - scalar payload  → Niche{tagged=true}: encode stored (v<<1)|1, so
             the match binding must untag.  (Decoding with tagged=false handed
             the raw tagged word to the branch body — an actor handler summed
             tagged payloads: 21 + 11 instead of 10 + 5.)
           - heap payload    → Niche{tagged=false}: value is the payload ptr.
           - niche-UNSAFE payload (e.g. Float) → Boxed, matching the boxed
             encode fallback.
         Non-niche-shaped TCons return None and stay Boxed. *)
      (match scrut_tir_ty_init with
       | Tir.TCon (name, []) ->
         (match Repr.niche_repr_of_concrete ~collision_set:ctx.Llvm_ctx.collision_set ctx.Llvm_ctx.type_defs name with
          | Some r -> r
          | None -> Repr.Boxed)
       | _ -> Repr.Boxed)
    | r -> r
  in
  (* Repr audit hook — record the DECODING this match commits to, so mixed
     encode/decode families for a type surface in the MARCH_REPR_AUDIT report.
     Only TCon scrutinees are attributable to a type name; the TVar niche-
     recovery path has no name and is skipped. *)
  (match scrut_tir_ty_init with
   | Tir.TCon (nm, ps) ->
     Llvm_ctx.repr_audit_record ~ty:nm
       ~payload:(match ps with
         | [] -> "?"
         | _ -> String.concat "," (List.map Llvm_eq.mangle_ty_for_eq ps))
       ~family:(match effective_repr with
         | Repr.Newtype _ -> "Newtype"
         | Repr.Niche _   -> "Niche"
         | Repr.Unboxed _ -> "Unboxed"
         | Repr.Boxed     -> "Boxed")
       ~site:("case in " ^ ctx.Llvm_ctx.cur_emit_fn)
   | _ -> ());
  (* Fast path: unboxed aggregate — the value is an LLVM struct in registers.
     One constructor, so there is no tag to read and no branch to select: bind
     each field with [extractvalue] and emit the single arm.  Perceus emits no
     RC ops for these ([Rc_types.needs_rc] is false), so unlike the Newtype and
     Niche paths below there is no scrutinee DecRC to strip. *)
  match effective_repr with
  | Repr.Unboxed { ctor = _; fields } ->
    let sty = match scrut_tir_ty_init with
      | Tir.TCon (name, _) -> Repr.unboxed_llvm_name name
      | _ ->
        (* Unreachable: [Repr.repr_of_ty] only answers [Unboxed] for a TCon. *)
        failwith "emit_case: unboxed repr for a non-TCon scrutinee"
    in
    let sv = Llvm_ctx.coerce ctx scrut_ty scrut_val sty in
    let bind_fields (br : Tir.branch) =
      List.iteri (fun i (v : Tir.var) ->
          match List.nth_opt fields i with
          | None ->
            failwith (Printf.sprintf
                        "emit_case: unboxed branch binds field %d of a %d-field \
                         aggregate (arity mismatch — malformed TIR)"
                        i (List.length fields))
          | Some fty_tir ->
            let fty = Llvm_ctx.llvm_ty fty_tir in
            let fv = Llvm_ctx.fresh ctx "ubget" in
            Llvm_ctx.emit ctx
              (Printf.sprintf "%s = extractvalue %s %s, %d" fv sty sv i);
            let slot = Llvm_ctx.alloca_name ctx (Llvm_ctx.llvm_name v.Tir.v_name) in
            Llvm_ctx.emit ctx (Printf.sprintf "%%%s.addr = alloca %s" slot fty);
            Llvm_ctx.emit ctx
              (Printf.sprintf "store %s %s, ptr %%%s.addr" fty fv slot);
            Hashtbl.replace ctx.Llvm_ctx.var_llvm_ty slot fty)
        br.Tir.br_vars
    in
    (match branches with
     | [] ->
       (* Wildcard/default-only match *)
       (match default_opt with
        | Some d -> emit_expr ctx d
        | None -> ("ptr", "poison"))
     | [ br ] -> bind_fields br; emit_expr ctx br.Tir.br_body
     | _ ->
       failwith "emit_case: unboxed type has multiple branches (impossible: \
                 the representation is only chosen for single-ctor types)")
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
          let needs_tag = Repr.payload_needs_tag ~collision_set:ctx.Llvm_ctx.collision_set ctx.Llvm_ctx.type_defs payload in
          let (fty, fval) =
            if needs_tag then
              ("i64", Llvm_ctx.emit_untag_known_scalar ctx ~raw:"nt_raw" ~unt:"nt_unt" scrut_val)
            else
              ("ptr", Llvm_ctx.coerce ctx scrut_ty scrut_val "ptr")
          in
          let slot = Llvm_ctx.alloca_name ctx (Llvm_ctx.llvm_name field_var.Tir.v_name) in
          Llvm_ctx.emit ctx (Printf.sprintf "%%%s.addr = alloca %s" slot fty);
          Llvm_ctx.emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" fty fval slot);
          Hashtbl.replace ctx.Llvm_ctx.var_llvm_ty slot fty
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
      if scrut_name = "" then body
      else
        (* The DecRC for the niche scrutinee may appear anywhere in the leading
           ESeq chain (other owned variables in scope get their own DecRCs
           first).  Walk the full chain and remove the first match. *)
        let rec go e =
          match e with
          | Tir.ESeq (Tir.EDecRC (Tir.AVar v), rest)
          | Tir.ESeq (Tir.EAtomicDecRC (Tir.AVar v), rest)
            when String.equal v.Tir.v_name scrut_name -> rest
          | Tir.ESeq (head, rest) -> Tir.ESeq (head, go rest)
          | _ -> e
        in
        go body
    in
    let snapshot_var_slot_n () = Hashtbl.copy ctx.Llvm_ctx.var_slot in
    let restore_var_slot_n snap =
      Hashtbl.reset ctx.Llvm_ctx.var_slot;
      Hashtbl.iter (Hashtbl.add ctx.Llvm_ctx.var_slot) snap
    in
    let result_slot_n = Llvm_ctx.fresh ctx "res_slot" in
    Llvm_ctx.emit ctx (Printf.sprintf "%s = alloca ptr" result_slot_n);
    (* Same bookkeeping, and the same ownership argument, as [arm_result_tys]
       in the boxed path below — this merge simply never had it.  Measured on
       a 20,000-iteration `Option(Option(Float))` loop (the outer Option is
       niche-encoded because its payload is a heap pointer, the inner one is
       boxed because 0.0 collides with the None niche): 20,000 leaked
       march_float_box cells, one per evaluation, entirely from this merge. *)
    let niche_arm_tys = ref [] in
    let record_niche_arm_ty (body : Tir.expr) (ty : string) =
      if not (arm_diverges body) then niche_arm_tys := ty :: !niche_arm_tys
    in
    let merge_lbl_n = Llvm_ctx.fresh_block ctx "niche_merge" in
    let none_lbl    = Llvm_ctx.fresh_block ctx "niche_none" in
    let some_lbl    = Llvm_ctx.fresh_block ctx "niche_some" in
    let scrut_p = Llvm_ctx.coerce ctx scrut_ty scrut_val "ptr" in
    let is_null = Llvm_ctx.fresh ctx "is_null" in
    Llvm_ctx.emit ctx (Printf.sprintf "%s = icmp eq ptr %s, null" is_null scrut_p);
    Llvm_ctx.emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
                     is_null none_lbl some_lbl);
    (* Find the None branch (no br_vars) and Some branch (has br_vars) *)
    let none_branch = List.find_opt (fun br -> br.Tir.br_vars = []) branches in
    let some_branch = List.find_opt (fun br -> br.Tir.br_vars <> []) branches in
    (* None arm *)
    let snap_none = snapshot_var_slot_n () in
    Llvm_ctx.emit_label ctx none_lbl;
    (match none_branch with
     | Some br ->
       let body = strip_decrc_niche br.Tir.br_body in
       let (bty, bval) = emit_expr ctx body in
       record_niche_arm_ty body bty;
       Llvm_ctx.emit ctx (Printf.sprintf "store ptr %s, ptr %s"
                   (Llvm_ctx.coerce ctx bty bval "ptr") result_slot_n);
       Llvm_ctx.emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl_n)
     | None ->
       (* Wildcard/default fallback for None *)
       (match default_opt with
        | Some d ->
          let (dty, dval) = emit_expr ctx d in
          record_niche_arm_ty d dty;
          Llvm_ctx.emit ctx (Printf.sprintf "store ptr %s, ptr %s"
                      (Llvm_ctx.coerce ctx dty dval "ptr") result_slot_n);
          Llvm_ctx.emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl_n)
        | None -> Llvm_ctx.emit_term ctx "unreachable"));
    restore_var_slot_n snap_none;
    (* Some arm *)
    let snap_some = snapshot_var_slot_n () in
    Llvm_ctx.emit_label ctx some_lbl;
    (match some_branch with
     | Some br ->
       (* Bind the field variable to the extracted payload *)
       (match br.Tir.br_vars with
        | [field_var] ->
          let (fty, fval) =
            if niche_tagged then
              ("i64", Llvm_ctx.emit_untag_known_scalar ctx ~raw:"niche_raw" ~unt:"niche_unt" scrut_p)
            else
              ("ptr", scrut_p)
          in
          let slot = Llvm_ctx.alloca_name ctx (Llvm_ctx.llvm_name field_var.Tir.v_name) in
          Llvm_ctx.emit ctx (Printf.sprintf "%%%s.addr = alloca %s" slot fty);
          Llvm_ctx.emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" fty fval slot);
          Hashtbl.replace ctx.Llvm_ctx.var_llvm_ty slot fty
        | _ -> ());
       (* Strip DecRC(scrut) always: niche has no outer box.
          - None=0: IS_HEAP_PTR(0)=false, was a no-op anyway
          - Some(int): IS_HEAP_PTR(odd)=false, was a no-op anyway
          - Some(ptr): stripping is REQUIRED — scrut IS the payload *)
       let body = strip_decrc_niche br.Tir.br_body in
       let (bty, bval) = emit_expr ctx body in
       record_niche_arm_ty body bty;
       Llvm_ctx.emit ctx (Printf.sprintf "store ptr %s, ptr %s"
                   (Llvm_ctx.coerce ctx bty bval "ptr") result_slot_n);
       Llvm_ctx.emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl_n)
     | None ->
       (match default_opt with
        | Some d ->
          let (dty, dval) = emit_expr ctx d in
          record_niche_arm_ty d dty;
          Llvm_ctx.emit ctx (Printf.sprintf "store ptr %s, ptr %s"
                      (Llvm_ctx.coerce ctx dty dval "ptr") result_slot_n);
          Llvm_ctx.emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl_n)
        | None -> Llvm_ctx.emit_term ctx "unreachable"));
    restore_var_slot_n snap_some;
    Llvm_ctx.emit_label ctx merge_lbl_n;
    let r_n = Llvm_ctx.fresh ctx "niche_r" in
    Llvm_ctx.emit ctx (Printf.sprintf "%s = load ptr, ptr %s" r_n result_slot_n);
    (* Release the box this merge's own coerce-to-ptr calls allocated, if any —
       see [finish_ptr_merge].  Identical to the boxed path's merge below; see
       [niche_arm_tys] for the float measurement. *)
    finish_ptr_merge ctx ~arm_tys:!niche_arm_tys ~loaded:r_n
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
       | Tir.TFloat -> false  (* floats are raw `double` scalars, never heap ptrs
                                 at this representation — see the float-chain
                                 branch below (analogous to the string chain),
                                 which fcmp's the coerced-to-double scrutinee
                                 directly rather than loading a ctor tag. *)
       | Tir.TCon ("Atom", []) -> false  (* atoms are i64 scalars *)
       | Tir.TVar _ -> scrut_ty = "ptr"  (* unknown type: trust actual loaded LLVM type.
                                            Pattern-bound vars get TVar "_" from lower.ml;
                                            a Bool/Int field loaded as i64 must not be
                                            treated as a heap pointer. *)
       | _ -> true)
    | Tir.ALit (March_ast.Ast.LitBool _) | Tir.ALit (March_ast.Ast.LitInt _)
    | Tir.ALit (March_ast.Ast.LitAtom _) -> false
    | Tir.ALit (March_ast.Ast.LitFloat _) -> false
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
            "LLVM Llvm_ctx.emit: constructor pattern %s(%s) destructures a non-pointer \
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

  let merge_lbl   = Llvm_ctx.fresh_block ctx "case_merge" in
  let default_lbl = Llvm_ctx.fresh_block ctx "case_default" in
  let branch_lbls = List.map (fun _ -> Llvm_ctx.fresh_block ctx "case_br") branches in

  (* Alloca slot for result — always ptr; Llvm_ctx.coerce scalars via inttoptr *)
  let result_slot = Llvm_ctx.fresh ctx "res_slot" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = alloca ptr" result_slot);

  (* Track each arm's pre-coercion LLVM type.  When every arm that reaches
     [merge_lbl] is "double", the ptr stored in [result_slot] is a
     freshly-allocated [march_float_box] created solely by THIS emit_case
     call's own coerce-to-ptr calls below (float-boxing Stage 2,
     [Llvm_ctx.coerce]'s ("double","ptr") arm) — never escaped, never aliased,
     never read by anyone else. The merge below can safely unbox-and-free it
     instead of handing the still-live box to the caller as a generic "ptr",
     which is what leaked one [march_alloc_float] cell per case/match
     evaluation (specs/todos/2026-08-11-float-boxing-erasure-boundary-per-call-leak.md).
     Arms that don't reach merge — the `unreachable` default, and any arm
     [arm_diverges] recognises — contribute nothing, so they can't spoil the
     uniform-type proof.  Before [arm_diverges] existed only the first of those
     was excluded, and the non-exhaustive-panic default's "ptr" cost 20,000
     leaked boxes on a 20,000-iteration `Option(Float)` loop
     (specs/progress/2026-08-22-erased-slot-ownership-leaks.md).  The same
     argument covers an unboxed small aggregate's struct type; see
     [finish_ptr_merge], which is what acts on this list. *)
  let arm_result_tys = ref [] in

  (* Record an arm's pre-coercion type unless the arm diverges. *)
  let record_arm_ty (body : Tir.expr) (ty : string) =
    if not (arm_diverges body) then arm_result_tys := ty :: !arm_result_tys
  in

  (* Detect string-literal case: br_tag starts with '"' *)
  let is_string_case = List.exists (fun br ->
      String.length br.Tir.br_tag > 0 && br.Tir.br_tag.[0] = '"'
    ) branches in

  (* Detect atom case: br_tag starts with ':' — emit switch on i64 FNV1a hashes *)
  let is_atom_case = List.exists (fun br ->
      String.length br.Tir.br_tag > 0 && br.Tir.br_tag.[0] = ':'
    ) branches in

  (* Detect float-literal case: br_tag starts with '#' (lower.ml's
     pat_tag_and_subs encoding for [Ast.LitFloat], "#<hex-float>" via "%h" —
     see that function's doc comment for why hex rather than decimal).
     Floats cannot participate in an integer `switch` (no total, exact int
     encoding of an arbitrary double — unlike Int/Bool/Atom, which reuse the
     low-bit-tagged immediate representation), so — exactly like the
     string-literal case — this is an if/else fcmp chain, not a switch. *)
  let is_float_case = List.exists (fun br ->
      String.length br.Tir.br_tag > 0 && br.Tir.br_tag.[0] = '#'
    ) branches in

  (* The scrutinee's TIR type — needed both for the switch tag lookup and for
     branch field binding.  Defined early so both uses see it. *)
  let scrut_tir_ty =
    match scrut_atom with Tir.AVar v -> v.Tir.v_ty | _ -> Tir.TUnit
  in

  (* Produce the ctor_info key for a branch tag (keys are "TypeName.CtorName").
     - A BARE tag ("Cons") is qualified with the scrutinee type when known
       ("List.Cons"); otherwise left bare for Llvm_data.ctor_entry's suffix resolver.
     - A QUALIFIED pattern ("Inline.Text", "Md.Inline.Text") carries its own type
       qualifier.  Resolve it to the ctor_info key whose constructor matches AND
       whose type segment matches that qualifier, so a ctor name that collides
       with another type's constructor (e.g. stdlib Xml.XmlNode.Text) is
       disambiguated by the qualifier the user wrote — NOT by Llvm_data.ctor_entry's
       ambiguous last-segment suffix match (which picks by hashtable order and
       was the cause of cross-module first-variant mismatches). *)
  let qualified_br_key br_tag =
    match String.rindex_opt br_tag '.' with
    | None ->
      (match scrut_tir_ty with
       | Tir.TCon (type_name, _) -> type_name ^ "." ^ br_tag
       | _ -> br_tag)
    | Some i ->
      if Hashtbl.mem ctx.Llvm_ctx.ctor_info br_tag then br_tag
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
          ) ctx.Llvm_ctx.ctor_info [] in
        match matched with
        | k :: _ -> k
        | [] -> ctor
      end
  in

  if is_float_case then begin
    (* Float-literal pattern matching: if-else chain of `fcmp oeq double`
       comparisons, analogous to the string chain immediately below (an
       exact-equality if/else cascade rather than a switch).  Unlike the
       string chain, no Llvm_ctx.coerce-to-ptr issue applies here — the scrutinee is
       explicitly coerced to `double` up front (below), so every comparison
       operates on a genuine LLVM `double` value regardless of whether the
       scrutinee arrived as a raw double or (e.g. inside a polymorphic slot)
       a tagged-immediate ptr. *)
    let scrut_dbl = Llvm_ctx.coerce ctx scrut_ty scrut_val "double" in
    let rec emit_chain brs lbls =
      match brs, lbls with
      | [], [] -> Llvm_ctx.emit_term ctx (Printf.sprintf "br label %%%s" default_lbl)
      | br :: rest_brs, lbl :: rest_lbls ->
        let next_lbl = Llvm_ctx.fresh_block ctx "flt_next" in
        (* Decode "#<hex-float>" back to the exact double via the same "%h"
           hex form the encoder used — see pat_tag_and_subs's doc comment. *)
        let hex = String.sub br.Tir.br_tag 1 (String.length br.Tir.br_tag - 1) in
        let f = float_of_string hex in
        let bits = Int64.bits_of_float f in
        let lit = Printf.sprintf "0x%016LX" bits in
        let cmp = Llvm_ctx.fresh ctx "fcmp" in
        Llvm_ctx.emit ctx (Printf.sprintf "%s = fcmp oeq double %s, %s" cmp scrut_dbl lit);
        Llvm_ctx.emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s" cmp lbl next_lbl);
        Llvm_ctx.emit_label ctx next_lbl;
        emit_chain rest_brs rest_lbls
      | _ -> ()
    in
    emit_chain branches branch_lbls
  end else if is_string_case then begin
    (* String pattern matching: emit if-else chain with march_string_eq *)
    let rec emit_chain brs lbls =
      match brs, lbls with
      | [], [] -> Llvm_ctx.emit_term ctx (Printf.sprintf "br label %%%s" default_lbl)
      | br :: rest_brs, lbl :: rest_lbls ->
        let next_lbl = Llvm_ctx.fresh_block ctx "str_next" in
        let s = String.sub br.Tir.br_tag 1 (String.length br.Tir.br_tag - 2) in
        let gname = Llvm_ctx.intern_string ctx s in
        let slit = Llvm_ctx.fresh ctx "sl" in
        Llvm_ctx.emit ctx (Printf.sprintf "%s = call ptr @march_string_lit(ptr %s, i64 %d)"
                    slit gname (String.length s));
        let eq = Llvm_ctx.fresh ctx "seq" in
        Llvm_ctx.emit ctx (Printf.sprintf "%s = call i64 @march_string_eq(ptr %s, ptr %s)"
                    eq scrut_val slit);
        let cmp = Llvm_ctx.fresh ctx "cmp" in
        Llvm_ctx.emit ctx (Printf.sprintf "%s = icmp ne i64 %s, 0" cmp eq);
        Llvm_ctx.emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s" cmp lbl next_lbl);
        Llvm_ctx.emit_label ctx next_lbl;
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
         Booleans stored in struct fields come out as ptr (boxed i64); Llvm_ctx.coerce first. *)
      let scrut_i64 = Llvm_ctx.coerce ctx scrut_ty scrut_val "i64" in
      let i1v = Llvm_ctx.fresh ctx "bi" in
      Llvm_ctx.emit ctx (Printf.sprintf "%s = trunc i64 %s to i1" i1v scrut_i64);
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
      Llvm_ctx.emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s" i1v true_lbl false_lbl)
    end else begin
      (* Determine switch discriminant (tag or scalar) *)
      let (sw_ty, sw_val) =
        if is_ptr_scrut then ("i32", Llvm_data.emit_load_tag ctx scrut_val)
        else if scrut_is_tagged_imm then begin
          (* ptr-typed tagged immediate: switch on the raw bits *)
          let raw = Llvm_ctx.fresh ctx "ti" in
          Llvm_ctx.emit ctx (Printf.sprintf "%s = ptrtoint ptr %s to i64" raw scrut_val);
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
              let e = Llvm_data.ctor_entry ctx (qualified_br_key br.Tir.br_tag) (List.length br.Tir.br_vars) in
              string_of_int e.Llvm_ctx.ce_tag
            else begin
              let v =
                if is_atom_case then begin
                  (* Atom tags are ":NAME" — must match emit_atom's interning. *)
                  let name = String.sub br.Tir.br_tag 1 (String.length br.Tir.br_tag - 1) in
                  let h = Llvm_ctx.atom_hash name in
                  (* Also register match-arm atoms in the show reverse table:
                     an atom named only as a pattern tag (e.g. a `:get` from
                     Http.method matched but never written as a value literal)
                     must still render as `:get` if later shown. *)
                  Hashtbl.replace ctx.Llvm_ctx.atom_names h name;
                  h
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
      Llvm_ctx.emit_term ctx (Printf.sprintf "switch %s %s, label %%%s [\n      %s\n  ]"
                       sw_ty sw_val default_lbl cases_part)
    end
  end;

  (* Helper: find the scrutinee's own EDecRC/EAtomicDecRC within a leading
     run of bare DecRC ops and return (v, rest) with the OTHER leading decs
     preserved in their original order around the extraction point.

     The scrutinee's dec is not always the literal head of the branch body:
     [add_cross_decrcs] in perceus.ml prepends OTHER cross-branch-dead
     variables' EDecRC/EAtomicDecRC ops in front of it whenever the branch
     also has, say, a closure parameter that's unused on this specific arm
     (e.g. Map.node_insert's HLeaf arm: `dec_rc eq; dec_rc node; ...` — the
     scrutinee `node`'s dec is SECOND, not first). A literal head-only match
     here silently falls through to the plain (unprotected) EDecRC codegen
     below, leaving extracted heap fields under-refcounted whenever the
     scrutinee is actually shared at that point — this was finding C1: a
     String map key's refcount under-counted this way, freed prematurely,
     surfacing as a use-after-free in march_hash_string when a later
     Map.keys/get_or traversal read it. Fixed 2026-07-11. *)
  let strip_scrut_decrc scrut_name body =
    let rec go acc e =
      match e with
      | Tir.ESeq (((Tir.EDecRC (Tir.AVar v)) as op), rest)
      | Tir.ESeq (((Tir.EAtomicDecRC (Tir.AVar v)) as op), rest) ->
        if String.equal v.Tir.v_name scrut_name then
          Some (v, List.fold_left (fun inner o -> Tir.ESeq (o, inner)) rest acc)
        else
          go (op :: acc) rest
      | _ -> None
    in
    go [] body
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
     scrutinee is shared (RC > 1) the EReuse takes its dec+alloc-Llvm_ctx.fresh path and
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

     Each ECase branch introduces its own bindings via [Llvm_ctx.alloca_name], which
     mutates [ctx.Llvm_ctx.var_slot].  Without restoring [var_slot] between branches,
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
  let snapshot_var_slot () = Hashtbl.copy ctx.Llvm_ctx.var_slot in
  let restore_var_slot snap =
    Hashtbl.reset ctx.Llvm_ctx.var_slot;
    Hashtbl.iter (Hashtbl.add ctx.Llvm_ctx.var_slot) snap
  in

  (* Emit branch blocks *)
  List.iter2 (fun br lbl ->
    let snap = snapshot_var_slot () in
    Llvm_ctx.emit_label ctx lbl;
    (* Bind branch variables from scrutinee fields *)
    let heap_field_vals = ref [] in
    (* Fields that are physically a march_float_box in an ERASED slot — see the
       [is_boxed_float] comment at the binding site below. *)
    let boxed_float_field_vals = ref [] in
    (* FBIP whole-cell reuse changes the answer for erased Float fields, so it
       has to be known BEFORE the fields are bound.  When the body reuses the
       scrutinee's own storage, binding the field as a raw double means any
       reconstruction re-boxes (coerce double->ptr allocates) and stores a
       FRESH box into the reused cell — orphaning the one already in the slot,
       which is a new leak in exchange for the one this fixes.  Keep the
       pre-existing ptr binding on that path instead: the reuse shape then
       behaves exactly as it did before and keeps its own (pre-existing)
       accounting.  The safe direction, and the same conservatism the reuse
       counterpart of the leading-dec path already applies. *)
    let body_reuses_scrut_here =
      match scrut_atom with
      | Tir.AVar v -> body_reuses_scrut v.Tir.v_name br.Tir.br_body
      | _ -> false
    in
    if is_ptr_scrut then begin
      let entry = Llvm_data.ctor_entry ctx (qualified_br_key br.Tir.br_tag) (List.length br.Tir.br_vars) in
      (* Concrete field types — uses scrutinee type to instantiate type variables.
         For polymorphic ctors like Cons('a, List('a)) with scrutinee List(Int),
         this gives [TInt, TCon("List",[TInt])] instead of [TVar "a", ...]. *)
      let concrete_fields =
        Llvm_data.resolve_ctor_fields ctx scrut_tir_ty br.Tir.br_tag (List.length br.Tir.br_vars)
      in
      (* Tuple AND variant fields both follow the UNIFORM slot convention
         (ee23036): scalars are low-bit tagged at construction (Llvm_ctx.coerce i64→ptr)
         and read back as ptr, then untagged conditionally by `Llvm_ctx.coerce ptr→i64`
         (which ashr's only odd/tagged values).  So load EVERY field via
         ce_fields — "ptr" for the synthetic $TupleN entry and for a ctor's
         generic TVar fields — never the concrete native type.  Loading a tuple
         scalar as raw i64 (49ecfbe, which predated the tagging build) read the
         tagged value verbatim — Int 0 → 1, 5 → 11, Bool true → 3 — the moment a
         tuple flowed through a pattern match.  concrete_fields is still used
         below to decide which fields are genuine heap pointers (for IncRC). *)
      List.iteri (fun i (v : Tir.var) ->
        let field_ty = match List.nth_opt entry.Llvm_ctx.ce_fields i with
          | Some t -> Llvm_ctx.llvm_field_ty t | None -> Llvm_ctx.llvm_ty v.Tir.v_ty in
        let fv = Llvm_data.emit_load_field ctx scrut_val i field_ty in
        (* Concrete field type, with the scrutinee's type arguments resolved.
           Use it (not [field_ty]) to decide which fields are genuine heap
           pointers, so scalar fields (Int, Bool, Float) in polymorphic ctors
           are NOT IncRC'd.  Also guard on field_ty: when the scrutinee's TIR
           type is TVar "_" (unknown — happens for sub-vars from the
           pattern-matrix compiler), Llvm_data.resolve_ctor_fields falls back
           to a TVar "_" placeholder, making concrete_field_ty = "ptr" even for
           primitive fields.  field_ty is always correct (resolved via the
           concrete ctor_info key) so using both as a conjunction prevents
           false positives. *)
        let concrete_field_ty = match List.nth_opt concrete_fields i with
          | Some t -> Llvm_ctx.llvm_ty t | None -> field_ty in
        (* A FLOAT IN AN ERASED SLOT.  The ctor's declared field is generic
           (ce_fields says "ptr") but the scrutinee instantiates it at Float,
           so what the slot physically holds is a march_alloc_float BOX, not
           the double — [Option(Float)] is the everyday instance, and it is
           niche-UNSAFE (0.0 bitcasts to the None niche) so it cannot escape
           into the unboxed representation.

           Bind the raw double, exactly as Llvm_toplevel.emit_fn's
           [is_apply_wrapper && ty = "double"] prologue does for a Float
           parameter arriving through the same uniform-ptr ABI.  Binding the
           BOX instead is what leaked: the box's reference belongs to the
           cell, the destructure transfers it to this binder (the cell's free
           is shallow), and the binder is a Float — [Rc_types.needs_rc TFloat]
           is false, so Perceus emits no drop for it and the transferred
           reference died on the floor.  Copying the double out means the
           binder aliases nothing, which is what makes the release below a
           release of a genuinely unowned box rather than of a live one. *)
        let is_boxed_float =
          concrete_field_ty = "double" && field_ty = "ptr"
          && not body_reuses_scrut_here
        in
        (* AN UNBOXED AGGREGATE IN AN ERASED SLOT — the Milestone-3 analogue of
           the Float case just above, and it needs the same treatment for the
           same reason.  The slot physically holds the BOX [Llvm_ctx.coerce]
           built at construction (a heap slot is 8 bytes, so an inline
           aggregate can never be stored inline in one — see
           [Llvm_ctx.llvm_field_ty]).  Bind a COPY of the struct rather than
           the box: the box's reference belongs to the cell, and the binder's
           type is an aggregate for which [Rc_types.needs_rc] is false, so
           Perceus would emit no drop and a transferred reference would die on
           the floor.  Copying means the binder aliases nothing, which is what
           lets the release below be a release of a genuinely unowned box. *)
        let is_boxed_agg =
          (not is_boxed_float) && field_ty = "ptr"
          && Repr.unboxed_of_llvm_ty concrete_field_ty <> None
          && not body_reuses_scrut_here
        in
        let bind_ty =
          if is_boxed_float then "double"
          else if is_boxed_agg then concrete_field_ty
          else field_ty in
        let bind_val =
          if is_boxed_float then begin
            let d = Llvm_ctx.fresh ctx "fbxf" in
            Llvm_ctx.emit ctx
              (Printf.sprintf "%s = call double @march_unbox_float(ptr %s)" d fv);
            d
          end else if is_boxed_agg then Llvm_ctx.coerce ctx "ptr" fv concrete_field_ty
          else fv
        in
        let slot = Llvm_ctx.alloca_name ctx (Llvm_ctx.llvm_name v.Tir.v_name) in
        Llvm_ctx.emit ctx (Printf.sprintf "%%%s.addr = alloca %s" slot bind_ty);
        Llvm_ctx.emit ctx (Printf.sprintf "store %s %s, ptr %%%s.addr" bind_ty bind_val slot);
        Hashtbl.replace ctx.Llvm_ctx.var_llvm_ty slot bind_ty;
        if concrete_field_ty = "ptr" && field_ty = "ptr" then
          heap_field_vals := fv :: !heap_field_vals
        else if is_boxed_float || is_boxed_agg then
          (* Both bind a copy, so both leave an unowned box behind — the list
             is "boxes the cell owns and the binder does not". *)
          boxed_float_field_vals := fv :: !boxed_float_field_vals
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
        let fboxes = !boxed_float_field_vals in
        (match strip_scrut_decrc sn br.Tir.br_body with
         | Some (_scrut_v, rest) ->
           (* Emit: march_decrc_freed(scrut); if not freed, incrc each heap field *)
           let freed = Llvm_ctx.fresh ctx "freed" in
           Llvm_ctx.emit ctx (Printf.sprintf "%s = call i64 @march_decrc_freed(ptr %s)"
                       freed scrut_val);
           let freed_bool = Llvm_ctx.fresh ctx "freed_b" in
           Llvm_ctx.emit ctx (Printf.sprintf "%s = icmp ne i64 %s, 0" freed_bool freed);
           let unique_lbl = Llvm_ctx.fresh_block ctx "br_unique" in
           let shared_lbl = Llvm_ctx.fresh_block ctx "br_shared" in
           let body_lbl   = Llvm_ctx.fresh_block ctx "br_body" in
           Llvm_ctx.emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
                            freed_bool unique_lbl shared_lbl);
           (* Shared path: IncRC each extracted heap field.  Erased-slot Float
              boxes are deliberately absent: the cell survives and keeps owning
              them, and the binder holds a COPY of the double (see
              [is_boxed_float] above), so it aliases nothing to account for. *)
           Llvm_ctx.emit_label ctx shared_lbl;
           List.iter (fun fv ->
             Llvm_ctx.emit ctx (Printf.sprintf "call void @march_incrc(ptr %s)" fv)
           ) fields;
           Llvm_ctx.emit_term ctx (Printf.sprintf "br label %%%s" body_lbl);
           (* Unique path: the cell has just been freed, so each ordinary heap
              field's reference transfers to its binder and Perceus will drop
              it later — nothing to do for those.  An erased-slot Float box has
              no such successor: its binder is a raw double, [needs_rc TFloat]
              is false, and the cell's free is shallow — so its reference has
              no owner at all from here on and this is the one place that can
              release it.  It is emitted on the FREED path only, which is
              exactly the proof that nobody else still holds the box. *)
           Llvm_ctx.emit_label ctx unique_lbl;
           List.iter (fun fv ->
             Llvm_ctx.emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" fv)
           ) fboxes;
           Llvm_ctx.emit_term ctx (Printf.sprintf "br label %%%s" body_lbl);
           Llvm_ctx.emit_label ctx body_lbl;
           rest   (* emit the rest of the body without the leading dec_rc *)
         | None when body_reuses_scrut sn br.Tir.br_body ->
           (* Reuse counterpart of the leading-dec shared path.  The scrutinee
              box is NOT freed at entry — the tail EReuse consumes it.  So here
              we only READ the RC (non-consuming) and, when shared (RC > 1),
              IncRC the extracted heap fields before the body moves them into a
              consuming callee.  No dec/free at entry: the EReuse performs the
              single box-level dec on its rc>1 path. *)
           let rc = Llvm_ctx.fresh ctx "scrut_rc" in
           Llvm_ctx.emit ctx (Printf.sprintf
             "%s = load atomic i64, ptr %s monotonic, align 8" rc scrut_val);
           let shared = Llvm_ctx.fresh ctx "scrut_shared" in
           Llvm_ctx.emit ctx (Printf.sprintf "%s = icmp sgt i64 %s, 1" shared rc);
           let unique_lbl = Llvm_ctx.fresh_block ctx "rb_unique" in
           let shared_lbl = Llvm_ctx.fresh_block ctx "rb_shared" in
           let body_lbl   = Llvm_ctx.fresh_block ctx "rb_body" in
           Llvm_ctx.emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
                            shared shared_lbl unique_lbl);
           (* Shared path: dup each extracted heap field. *)
           Llvm_ctx.emit_label ctx shared_lbl;
           List.iter (fun fv ->
             Llvm_ctx.emit ctx (Printf.sprintf "call void @march_incrc(ptr %s)" fv)
           ) fields;
           Llvm_ctx.emit_term ctx (Printf.sprintf "br label %%%s" body_lbl);
           (* Unique path: nothing to do. *)
           Llvm_ctx.emit_label ctx unique_lbl;
           Llvm_ctx.emit_term ctx (Printf.sprintf "br label %%%s" body_lbl);
           Llvm_ctx.emit_label ctx body_lbl;
           br.Tir.br_body
         | None -> br.Tir.br_body)
      | Some sn, [] when !boxed_float_field_vals <> [] ->
        (* No ordinary heap fields, but at least one erased-slot Float box.
           Same shape as the arm above, minus the shared-path IncRC (a Float
           binder is a copied double and aliases nothing): split on
           march_decrc_freed purely so the box release lands on the path where
           the cell is provably gone.  The EReuse guard from the [] arm below
           is kept — when the body reuses the scrutinee's storage the leading
           dec must be stripped without a substitute release, or the reused
           cell is torn down under the EReuse. *)
        let fboxes = !boxed_float_field_vals in
        (match strip_scrut_decrc sn br.Tir.br_body with
         | Some (_, rest) when body_reuses_scrut sn rest -> rest
         | Some (_, rest) ->
           let freed = Llvm_ctx.fresh ctx "freed" in
           Llvm_ctx.emit ctx (Printf.sprintf "%s = call i64 @march_decrc_freed(ptr %s)"
                       freed scrut_val);
           let freed_bool = Llvm_ctx.fresh ctx "freed_b" in
           Llvm_ctx.emit ctx (Printf.sprintf "%s = icmp ne i64 %s, 0" freed_bool freed);
           let unique_lbl = Llvm_ctx.fresh_block ctx "fb_unique" in
           let body_lbl   = Llvm_ctx.fresh_block ctx "fb_body" in
           Llvm_ctx.emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s"
                            freed_bool unique_lbl body_lbl);
           Llvm_ctx.emit_label ctx unique_lbl;
           List.iter (fun fv ->
             Llvm_ctx.emit ctx (Printf.sprintf "call void @march_decrc(ptr %s)" fv)
           ) fboxes;
           Llvm_ctx.emit_term ctx (Printf.sprintf "br label %%%s" body_lbl);
           Llvm_ctx.emit_label ctx body_lbl;
           rest
         | None -> br.Tir.br_body)
      | Some sn, [] ->
        (* No heap fields; still need to strip a leading dec_rc(scrut) if the body
           also contains an EReuse(scrut) — otherwise dec_rc and EReuse both
           release the scrutinee, causing RC underflow on the EReuse Llvm_ctx.fresh path. *)
        (match strip_scrut_decrc sn br.Tir.br_body with
         | Some (_, rest) when body_reuses_scrut sn rest -> rest
         | _ -> br.Tir.br_body)
      | _ -> br.Tir.br_body
    in
    let (br_ty, br_val) = emit_expr ctx body_to_emit in
    record_arm_ty body_to_emit br_ty;
    let stored = Llvm_ctx.coerce ctx br_ty br_val "ptr" in
    Llvm_ctx.emit ctx (Printf.sprintf "store ptr %s, ptr %s" stored result_slot);
    Llvm_ctx.emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl);
    restore_var_slot snap
  ) branches branch_lbls;

  (* Default arm *)
  let snap_default = snapshot_var_slot () in
  Llvm_ctx.emit_label ctx default_lbl;
  (match default_opt with
   | None ->
     (* Is the scrutinee's runtime SHAPE statically unproven?  After
        monomorphization a concrete type has been specialized away, so a type
        variable left in the scrutinee type (bare, or as a tuple/record element)
        means the value is GENUINELY erased at runtime — the fingerprint of a
        reflection builtin like [record_entries], whose element values are typed
        as an unconstrained [a] and may not actually be the tuple/record/ctor the
        pattern assumes.  In that case emitting `unreachable` for the switch
        default lets LLVM prove the default dead and fold the tag check away, so
        a wrong-shaped value (a String reaching a tuple pattern) silently falls
        into the field-load arm → destructured as garbage → SIGSEGV downstream.
        Panic cleanly like the interpreter's "Non-exhaustive pattern match"
        instead; the side-effecting call also keeps the tag check live so the
        mismatch is actually caught.  Concrete scrutinees keep `unreachable`
        (LLVM folds the single-arm switch — no runtime cost). *)
     let rec shape_unproven = function
       | Tir.TVar _        -> true
       | Tir.TTuple ts     -> List.exists shape_unproven ts
       | Tir.TRecord fs    -> List.exists (fun (_, t) -> shape_unproven t) fs
       | _                 -> false
     in
     if shape_unproven scrut_tir_ty_init then begin
       (* Include the enclosing function so a suite-wide failure report can be
          clustered by root cause without a debugger (77 identical anonymous
          messages in the first depot inventory run were unattributable). *)
       let msg = Printf.sprintf
         "match failure: value did not match any pattern arm (in %s)"
         (if ctx.Llvm_ctx.cur_emit_fn = "" then "?" else ctx.Llvm_ctx.cur_emit_fn) in
       let gname = Llvm_ctx.intern_string ctx msg in
       let slit = Llvm_ctx.fresh ctx "mfail" in
       Llvm_ctx.emit ctx (Printf.sprintf
         "%s = call ptr @march_string_lit(ptr %s, i64 %d)"
         slit gname (String.length msg));
       Llvm_ctx.emit ctx (Printf.sprintf "call void @march_panic(ptr %s)" slit);
       Llvm_ctx.emit_term ctx "unreachable"
     end else
       Llvm_ctx.emit_term ctx "unreachable"
   | Some d ->
     let (d_ty, d_val) = emit_expr ctx d in
     record_arm_ty d d_ty;
     let stored = Llvm_ctx.coerce ctx d_ty d_val "ptr" in
     Llvm_ctx.emit ctx (Printf.sprintf "store ptr %s, ptr %s" stored result_slot);
     Llvm_ctx.emit_term ctx (Printf.sprintf "br label %%%s" merge_lbl));
  restore_var_slot snap_default;

  Llvm_ctx.emit_label ctx merge_lbl;
  let r = Llvm_ctx.fresh ctx "case_r" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = load ptr, ptr %s" r result_slot);
  (* Uniform arm type → the box is ours alone (see [arm_result_tys]'s doc
     comment above); unbox and free it here instead of leaking it into the
     caller as an opaque live ptr.  See [finish_ptr_merge]. *)
  finish_ptr_merge ctx ~arm_tys:!arm_result_tys ~loaded:r
