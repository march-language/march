(** Constructor-name metadata: the compile-time half of compiled `to_string`
    on a user ADT.

    A boxed constructor cell carries a tag but no name, arity or field types,
    so the type-erased [march_value_to_string] could only print "#<tag:N>" for
    a user ADT.  This module emits, once per compilation unit and only if some
    call site needs it, a descriptor string naming every variant/record type
    the module lowered, and gives call sites the id to pass alongside a value
    whose STATIC TIR type names one of them.

    Static, not dynamic, on purpose.  The alternative on file
    (specs/todos/2026-08-05-boxed-adt-type-id.md) stamps a type id into every
    boxed cell's header pad word, which answers the same question at a
    genuinely erased site but charges a store to EVERY boxed allocation.  This
    route charges nothing at allocation and covers every site where the static
    type is known — which is where `to_string`, `println` and `~H` actually
    render ADTs.  A truly erased slot still renders "#<tag:N>"; that residual
    is what the pad-stamping todo remains open for.

    The descriptor grammar and the field-token alphabet are documented at the
    consumer, [march_ctor_table_ensure] in runtime/march_extras.c.  The two
    files must be edited together: a token means whatever the C parser thinks
    it means, and the field kinds below are exactly [Llvm_ctx.llvm_field_ty]'s
    slot representations, so a divergence is a MISREAD field rather than a
    missing name. *)

(** Field token for a constructor/record slot of type [ty].  [id_of] resolves
    a type name to its local descriptor id, or [None] if that type is not
    described (unboxed/newtype/niche repr, or not declared here) — in which
    case the slot falls back to the generic 'p' renderer, which is exactly
    today's behaviour for it. *)
let field_token ~(id_of : string -> int option) (ty : Tir.ty) : string =
  match ty with
  | Tir.TInt -> "i"
  | Tir.TBool -> "b"
  | Tir.TUnit -> "u"
  | Tir.TFloat -> "f"
  | Tir.TString -> "s"
  (* An Atom is a raw i64 hash in its slot and the runtime keeps no
     hash -> name registry, so its name is simply not recoverable at run time.
     'p' (generic) is what it already got; making that worse is not this
     change's business. *)
  | Tir.TCon ("Atom", []) -> "p"
  | Tir.TCon (name, _) ->
    (match id_of name with Some id -> Printf.sprintf "A%d" id | None -> "p")
  | _ -> "p"

(** True if a value of type [name] presents to the renderer as a heap cell
    whose tag is its own constructor tag — the only shape the table can walk.

    [Unboxed] qualifies even though it is an LLVM struct value in registers:
    every call site coerces to ["ptr"] before rendering, and [Llvm_ctx.coerce]
    reconstructs exactly the cell the boxed allocator would have built (16-byte
    header carrying the type's own ctor tag, fields at 16 + 8i).

    [Newtype] and [Niche] do NOT.  A newtype IS its payload with no cell of its
    own, and a niche-encoded [Some x] IS [x], so there is no header to read and
    no tag to look up — the renderer would walk the PAYLOAD's cell and print
    the payload's constructor under the wrapper's name.  Those keep the generic
    renderer; that residual is recorded in
    specs/todos/2026-08-05-boxed-adt-type-id.md. *)
let describable ctx (name : string) : bool =
  (* [repr_of_ty] on a BARE [TCon (name, [])] answers [Boxed] for an
     Option-shaped type, because the niche decision needs the type arguments
     this key does not carry — the same trap [Llvm_emit_alloc]'s niche arm
     documents.  Ask [is_niche_shaped] directly rather than trusting that
     answer: without this a niche type is described, and since [Some x] IS [x]
     the renderer reads the PAYLOAD's header as the wrapper's tag and prints a
     confidently wrong constructor. *)
  if Repr.is_niche_shaped ~collision_set:ctx.Llvm_ctx.collision_set
       ctx.Llvm_ctx.type_defs name then false
  else
    match Repr.repr_of_ty ~collision_set:ctx.Llvm_ctx.collision_set
            ctx.Llvm_ctx.type_defs (Tir.TCon (name, [])) with
    | Repr.Boxed | Repr.Unboxed _ -> true
    | Repr.Newtype _ | Repr.Niche _ -> false

(** Assign local ids to every describable variant/record type, first-wins on
    the short name — the same rule [Llvm_toplevel.build_ctor_info] uses to
    populate [ctor_info], so an id and the tags it is looked up with always
    come from the same declaration. *)
let assign_ids ctx : unit =
  if Hashtbl.length ctx.Llvm_ctx.ctor_desc_ids > 0 then () else begin
  let next = ref 0 in
  List.iter (fun td ->
      let name = match td with
        | Tir.TDVariant (n, _) -> Some n
        | Tir.TDRecord (n, _) -> Some n
        | Tir.TDClosure _ -> None
      in
      match name with
      | Some n when not (Hashtbl.mem ctx.Llvm_ctx.ctor_desc_ids n)
                 && describable ctx n ->
        incr next;
        Hashtbl.replace ctx.Llvm_ctx.ctor_desc_ids n !next
      | _ -> ())
    ctx.Llvm_ctx.type_defs
  end

(** Build the descriptor string for the ids [assign_ids] handed out.  Tags
    come from [ctor_info], never from the declaration index: actor-message and
    colliding-short-name types are given globally-unique tags, and a table
    keyed on the index would misname every one of their constructors. *)
let build_desc ctx : string =
  let id_of n = Hashtbl.find_opt ctx.Llvm_ctx.ctor_desc_ids n in
  let buf = Buffer.create 1024 in
  let emitted = Hashtbl.create 64 in
  List.iter (fun td ->
      match td with
      | Tir.TDVariant (name, ctors) when not (Hashtbl.mem emitted name) ->
        (match id_of name with
         | None -> ()
         | Some id ->
           Hashtbl.replace emitted name ();
           Printf.bprintf buf "T\t%d\tV\t%s\n" id name;
           List.iteri (fun idx (cname, field_tys) ->
               let tag =
                 match Hashtbl.find_opt ctx.Llvm_ctx.ctor_info (name ^ "." ^ cname) with
                 | Some e -> e.Llvm_ctx.ce_tag
                 | None -> idx
               in
               Printf.bprintf buf "C\t%d\t%s\t%s\n" tag cname
                 (String.concat "," (List.map (field_token ~id_of) field_tys)))
             ctors)
      | Tir.TDRecord (name, fields) when not (Hashtbl.mem emitted name) ->
        (match id_of name with
         | None -> ()
         | Some id ->
           Hashtbl.replace emitted name ();
           Printf.bprintf buf "T\t%d\tR\t%s\n" id name;
           (* Record slots are laid out with fields sorted by name (see
              [Llvm_data.shape_desc]); the descriptor is read positionally, so
              it must use that order and not the declaration order. *)
           let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) fields in
           List.iter (fun (fname, fty) ->
               Printf.bprintf buf "F\t%s\t%s\n" fname (field_token ~id_of fty))
             sorted)
      | _ -> ())
    ctx.Llvm_ctx.type_defs;
  Buffer.contents buf

(** Emit the descriptor and base-cache globals if this is the first call site
    to need them, and return them. *)
let ensure_globals ctx : string * string =
  match ctx.Llvm_ctx.ctor_desc_globals with
  | Some pair -> pair
  | None ->
    assign_ids ctx;
    let dg = Llvm_ctx.intern_string ctx (build_desc ctx) in
    ctx.Llvm_ctx.str_ctr <- ctx.Llvm_ctx.str_ctr + 1;
    let cg = Printf.sprintf "@.ctordesc%d" ctx.Llvm_ctx.str_ctr in
    Buffer.add_string ctx.Llvm_ctx.preamble
      (Printf.sprintf "%s = internal global i32 0\n" cg);
    ctx.Llvm_ctx.ctor_desc_globals <- Some (dg, cg);
    (dg, cg)

(** The local descriptor id for [ty], or [None] if it is not a type this table
    describes.  Deliberately EMITS NOTHING: it is called as a match guard at
    sites that mostly answer [None] (a tuple, a `TVar`, a newtype), and forcing
    the descriptor here put ~13KB of unreferenced string constant into the
    .rodata of every binary that merely called `to_string` on a non-primitive.
    [emit_to_string] is what emits, so the descriptor exists exactly when some
    site reads it. *)
let id_for ctx (ty : Tir.ty) : int option =
  (* Both runtime entry points live in march_extras.c, which the WASM runtime
     does not build — the same reason [shape_meta] gates
     `march_record_set_shape`.  Answering [None] here keeps every call site on
     the generic renderer for WASM instead of emitting a call to a symbol that
     does not exist at link time. *)
  if not ctx.Llvm_ctx.shape_meta then None
  else
  match ty with
  | Tir.TCon (name, _) ->
    assign_ids ctx;
    Hashtbl.find_opt ctx.Llvm_ctx.ctor_desc_ids name
  (* A `ptype` alias reaches call sites as a STRUCTURAL record, not as the
     nominal [TCon] its declaration produced, so a name lookup misses it and a
     record printed `#<tag:0>` where a variant printed its constructor.  Match
     it back to a declared record by its field names and slot kinds — the same
     identity [Llvm_data.shape_desc] gives a record cell — rather than adding a
     second notion of record identity. *)
  | Tir.TRecord fs ->
    assign_ids ctx;
    let key fields =
      List.sort (fun (a, _) (b, _) -> String.compare a b) fields
      |> List.map (fun (n, t) -> (n, Llvm_data.shape_kind_char t))
    in
    let want = key fs in
    Hashtbl.fold (fun tname id acc ->
        match acc with
        | Some _ -> acc
        | None ->
          (match List.find_opt (function
               | Tir.TDRecord (n, _) -> n = tname
               | _ -> false) ctx.Llvm_ctx.type_defs with
           | Some (Tir.TDRecord (_, fields)) when key fields = want -> Some id
           | _ -> None))
      ctx.Llvm_ctx.ctor_desc_ids None
  | _ -> None

(** Emit `march_value_to_string_typed(v, base + local_id)`, registering the
    table on first use.  Returns the ("ptr", ssa) pair of the result string. *)
let emit_to_string ctx (v : string) (local_id : int) : string * string =
  let (dg, cg) = ensure_globals ctx in
  let base = Llvm_ctx.fresh ctx "ctbase" in
  Llvm_ctx.emit ctx (Printf.sprintf
    "%s = call i32 @march_ctor_table_ensure(ptr %s, ptr %s)" base dg cg);
  let tid = Llvm_ctx.fresh ctx "ctid" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = add i32 %s, %d" tid base local_id);
  let r = Llvm_ctx.fresh ctx "ctstr" in
  Llvm_ctx.emit ctx (Printf.sprintf
    "%s = call ptr @march_value_to_string_typed(ptr %s, i32 %s)" r v tid);
  ("ptr", r)
