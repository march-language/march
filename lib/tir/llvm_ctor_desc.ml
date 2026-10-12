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

(** How the renderer must read a value of type [name], or [None] if the table
    cannot describe it (the value then keeps the generic renderer).

    - ['V']: a heap cell whose tag is its own constructor tag (a record is
      described the same way; [build_desc] writes it as an ['R'] row set).
      [Unboxed] qualifies even though it is an LLVM struct value in registers:
      every call site coerces to ["ptr"] before rendering, and
      [Llvm_ctx.coerce] reconstructs exactly the cell the boxed allocator would
      have built (16-byte header carrying the type's own ctor tag, fields at
      16 + 8i).
    - ['N']: a [Newtype].  The value IS its payload, with no cell and no tag
      of its own, so the renderer must not read a header: it prints the one
      constructor's name around the payload, read by the payload token
      ([payload_token]).
    - ['X']: a non-generic niche.  The nullary constructor IS raw 0 and the
      other one IS its payload, so the renderer decides the constructor from
      the word itself.

    A niche-shaped type whose payload is a TYPE VARIABLE is not described: its
    encoding depends on the instance ([Option(Float)] is boxed,
    [Option(String)] is a niche), and the type name alone does not say which.
    A niche-shaped type whose payload is not niche-safe is a plain boxed cell
    ([Kind.niche_repr_of_concrete] answers [None], which is the predicate the
    allocator and [Llvm_case] both key on), so it is described as ['V'].

    [repr_of] on a BARE [TCon (name, [])] answers [Boxed] for an Option-shaped
    type, because the niche decision needs the type arguments this key does not
    carry -- the same trap [Llvm_emit_alloc]'s niche arm documents -- so the
    niche question is asked first and directly. *)
let desc_kind ctx (name : string) : char option =
  let tbl = ctx.Llvm_ctx.k_table in
  if Kind.is_niche_shaped tbl name then
    match Kind.niche_repr_of_concrete tbl name with
    | Some (Kind.Niche { payload = Tir.TVar _; _ }) -> None
    | Some (Kind.Niche _) -> Some 'X'
    | Some _ -> None
    | None -> Some 'V'
  else
    match Kind.repr_of tbl (Tir.TCon (name, [])) with
    | Kind.Boxed | Kind.Unboxed _ -> Some 'V'
    | Kind.Newtype _ -> Some 'N'
    | Kind.Niche _ -> None

let describable ctx (name : string) : bool = desc_kind ctx name <> None

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

(** The next free local id: base ids are 1..n, instances follow. *)
let next_local_id ctx : int =
  Hashtbl.length ctx.Llvm_ctx.ctor_desc_ids
  + Hashtbl.length ctx.Llvm_ctx.ctor_desc_insts + 1

(** Bound on instance rows per unit.  A polymorphically recursive type
    ([type N(a) = Z | S(N(List(a)))]) names a new instance at every level, so
    without a bound the walk would not terminate; past it a slot keeps the
    declaration's own row, which is the pre-instance output. *)
let max_instances = 512

let rec ty_is_ground : Tir.ty -> bool = function
  | Tir.TVar _ -> false
  | Tir.TCon (_, ts) | Tir.TTuple ts -> List.for_all ty_is_ground ts
  | Tir.TRecord fs -> List.for_all (fun (_, t) -> ty_is_ground t) fs
  | Tir.TFn (ps, r) -> List.for_all ty_is_ground ps && ty_is_ground r
  | Tir.TPtr t -> ty_is_ground t
  | Tir.TInt | Tir.TFloat | Tir.TBool | Tir.TString | Tir.TUnit -> true

let find_variant_decl ctx (name : string) =
  List.find_map (function
      | Tir.TDVariant (n, ctors) when n = name -> Some ctors
      | _ -> None)
    ctx.Llvm_ctx.type_defs

(** Write one [C] row per constructor of [name].  Tags come from [ctor_info],
    never from the declaration index: actor-message and colliding-short-name
    types are given globally-unique tags, and a table keyed on the index would
    misname every one of their constructors. *)
let add_ctor_rows ctx buf (name : string) ctors (token : Tir.ty -> string) : unit =
  List.iteri (fun idx (cname, field_tys) ->
      let tag =
        match Hashtbl.find_opt ctx.Llvm_ctx.ctor_info (name ^ "." ^ cname) with
        | Some e -> e.Llvm_ctx.ce_tag
        | None -> idx
      in
      Printf.bprintf buf "C\t%d\t%s\t%s\n" tag cname
        (String.concat "," (List.map token field_tys)))
    ctors

(** Field token for a constructor/record slot of type [ty].  A named type
    resolves through [id_for_ty] to its local descriptor id; one the table
    does not describe (a generic niche reached without arguments, or a type
    not declared here) falls back to the generic 'p' renderer, which is
    exactly the untyped behaviour for it. *)
let rec field_token ctx (ty : Tir.ty) : string =
  match ty with
  | Tir.TInt -> "i"
  | Tir.TBool -> "b"
  | Tir.TUnit | Tir.TTuple [] | Tir.TCon ("Unit", []) -> "u"
  | Tir.TFloat -> "f"
  | Tir.TString -> "s"
  (* An Atom is a raw i64 hash in its slot and the runtime keeps no
     hash -> name registry, so its name is simply not recoverable at run time.
     'p' (generic) is what it already got; making that worse is not this
     change's business. *)
  | Tir.TCon ("Atom", []) -> "p"
  | Tir.TCon _ | Tir.TRecord _ ->
    (match id_for_ty ctx ty with Some id -> Printf.sprintf "A%d" id | None -> "p")
  (* A tuple in a field.  Only here, not at a top-level [id_for]: a top-level
     tuple is rendered by its Show impl before this table is consulted. *)
  | Tir.TTuple (_ :: _ as ts) ->
    (match tuple_instance_id ctx ts with
     | Some id -> Printf.sprintf "A%d" id
     | None -> "p")
  | _ -> "p"

(** Token for the payload of an ['N'] or ['X'] type.  Unlike a heap-cell slot
    ([field_token]), the payload word is what the allocator handed out for
    the WRAPPER: a scalar payload is TAGGED [(v<<1)|1]
    ([Kind.payload_needs_tag], [Llvm_emit_alloc]'s newtype and niche arms),
    so Int and Bool get their own tagged tokens ['I'] / ['B'].  A payload
    whose type is itself an ['N'] newtype over a scalar carries the same
    tagged word, which that type's own row reads. *)
and payload_token ctx (ty : Tir.ty) : string =
  match ty with
  | Tir.TInt -> "I"
  | Tir.TBool -> "B"
  | _ -> field_token ctx ty

(** Token for a slot whose DECLARED type is a type variable, holding a value
    of the instance's type [ty].  Such a slot holds the erased word: a scalar
    is tagged (Int, Bool: the same 'I'/'B' as a wrapper payload), a Float is
    a boxed cell the generic renderer recognises, and Unit needs no read at
    all.  Anything else is the value's own word, read by its own row. *)
and erased_token ctx (ty : Tir.ty) : string =
  match ty with
  | Tir.TInt -> "I"
  | Tir.TBool -> "B"
  | Tir.TFloat -> "p"
  (* Unit reaches here under all three spellings the typechecker and lowering
     use for it. *)
  | Tir.TUnit | Tir.TTuple [] | Tir.TCon ("Unit", []) -> "u"
  | _ -> field_token ctx ty

(** The local id for a value of static type [ty], or [None] when the table
    does not describe it.

    A generic type applied to GROUND arguments gets an instance entry of its
    own, its rows written with the arguments substituted.  The declaration's
    row can only say 'p' for a type-variable slot, and the generic renderer
    has nothing to go on for a value with no cell (a newtype's payload, a
    niche's word) or for a tagged Bool, which reads as an Int.  That is how
    [Box(Meters(9))] printed [Box(9)].  [List]/[Option]/[Result] never needed
    this at the top level because their Show impls monomorphise to an element
    `to_string` with the element's static type; a user generic type has no
    such impl. *)
and id_for_ty ctx (ty : Tir.ty) : int option =
  assign_ids ctx;
  match ty with
  | Tir.TCon (name, (_ :: _ as args)) when List.for_all ty_is_ground args ->
    (match instance_id ctx name args with
     | Some _ as r -> r
     | None -> Hashtbl.find_opt ctx.Llvm_ctx.ctor_desc_ids name)
  | Tir.TCon (name, _) -> Hashtbl.find_opt ctx.Llvm_ctx.ctor_desc_ids name
  | Tir.TRecord fs ->
    (match declared_record_id ctx fs with
     | Some _ as r -> r
     | None -> record_instance_id ctx fs)
  | _ -> None

(* A `ptype` alias reaches call sites as a STRUCTURAL record, not as the
   nominal [TCon] its declaration produced, so a name lookup misses it.  Match
   it back to a declared record by its field names and slot kinds — the same
   identity [Llvm_data.shape_desc] gives a record cell. *)
and declared_record_id ctx (fs : (string * Tir.ty) list) : int option =
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

(* A record literal whose shape matches no declared record (`{ a: 1, b: "x" }`
   with no `type R = { ... }`): describe the structural type itself.  The
   field names and types are all in [fs], and a record row prints no type
   name, so nothing is lost by having no declaration.  Without this the call
   site fell back to the untyped renderer, which printed `#<tag:0>`. *)
and record_instance_id ctx (fs : (string * Tir.ty) list) : int option =
  let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) fs in
  let key = Tir.show_ty (Tir.TRecord sorted) in
  match Hashtbl.find_opt ctx.Llvm_ctx.ctor_desc_insts key with
  | Some id -> Some id
  | None when Hashtbl.length ctx.Llvm_ctx.ctor_desc_insts >= max_instances -> None
  | None ->
    let id = next_local_id ctx in
    Hashtbl.replace ctx.Llvm_ctx.ctor_desc_insts key id;
    let buf = Buffer.create 128 in
    (* The name is for diagnostics only (an 'R' row prints none); it must not
       contain a tab or newline. *)
    Printf.bprintf buf "T\t%d\tR*\t{%s}\n" id
      (String.concat "," (List.map fst sorted));
    List.iter (fun (fname, fty) ->
        Printf.bprintf buf "F\t%s\t%s\n" fname (field_token ctx fty))
      sorted;
    Buffer.add_buffer ctx.Llvm_ctx.ctor_desc_inst_rows buf;
    Some id

(* A tuple in a field of a described type.  A tuple cell has no declaration
   to name it either, so it printed `#<tag:0>` (`T((1, "a"))`).  Kind 'U' has
   one row, read whatever the cell's tag. *)
and tuple_instance_id ctx (ts : Tir.ty list) : int option =
  let key = Tir.show_ty (Tir.TTuple ts) in
  match Hashtbl.find_opt ctx.Llvm_ctx.ctor_desc_insts key with
  | Some id -> Some id
  | None when Hashtbl.length ctx.Llvm_ctx.ctor_desc_insts >= max_instances -> None
  | None ->
    let id = next_local_id ctx in
    Hashtbl.replace ctx.Llvm_ctx.ctor_desc_insts key id;
    let toks = List.map (erased_token ctx) ts in
    let buf = Buffer.create 64 in
    Printf.bprintf buf "T\t%d\tU*\t$Tuple%d\n" id (List.length ts);
    Printf.bprintf buf "C\t0\t\t%s\n" (String.concat "," toks);
    Buffer.add_buffer ctx.Llvm_ctx.ctor_desc_inst_rows buf;
    Some id

and instance_id ctx (name : string) (args : Tir.ty list) : int option =
  let key = Tir.show_ty (Tir.TCon (name, args)) in
  match Hashtbl.find_opt ctx.Llvm_ctx.ctor_desc_insts key with
  | Some id -> Some id
  | None ->
    let tbl = ctx.Llvm_ctx.k_table in
    match find_variant_decl ctx name,
          Hashtbl.find_opt ctx.Llvm_ctx.type_params name with
    | Some ctors, Some params
      when List.length params = List.length args
        && Hashtbl.length ctx.Llvm_ctx.ctor_desc_insts < max_instances ->
      (* The instance's representation.  A niche-shaped type is a niche or a
         boxed cell depending on its argument, and [Kind.repr_of] WITH the
         arguments is the predicate the allocator keys on; anything else is
         decided by its declaration, as for the base row. *)
      let kind =
        if Kind.is_niche_shaped tbl name then
          (match Kind.repr_of tbl (Tir.TCon (name, args)) with
           | Kind.Niche _ -> Some 'X'
           | _ -> Some 'V')
        else desc_kind ctx name
      in
      (match kind with
       | None -> None
       | Some kind ->
         let id = next_local_id ctx in
         (* Registered before the rows are built: a recursive type's row names
            this same instance ([Tree(Meters)] inside [Node]). *)
         Hashtbl.replace ctx.Llvm_ctx.ctor_desc_insts key id;
         let subst = List.combine params args in
         let token gf =
           let t = Llvm_eq.apply_ty_subst subst gf in
           match gf with
           | Tir.TVar _ -> erased_token ctx t
           | _ -> if kind = 'V' then field_token ctx t else payload_token ctx t
         in
         let buf = Buffer.create 128 in
         (* '*' marks an instance: the runtime must not register it under the
            type's header id, which names the declaration, not this instance. *)
         Printf.bprintf buf "T\t%d\t%c*\t%s\n" id kind name;
         add_ctor_rows ctx buf name ctors token;
         Buffer.add_buffer ctx.Llvm_ctx.ctor_desc_inst_rows buf;
         Some id)
    | _ -> None

(** Build the descriptor rows for the ids [assign_ids] handed out. *)
let build_desc ctx : string =
  let buf = Buffer.create 1024 in
  let emitted = Hashtbl.create 64 in
  List.iter (fun td ->
      match td with
      | Tir.TDVariant (name, ctors) when not (Hashtbl.mem emitted name) ->
        (match Hashtbl.find_opt ctx.Llvm_ctx.ctor_desc_ids name with
         | None -> ()
         | Some id ->
           Hashtbl.replace emitted name ();
           let kind = match desc_kind ctx name with Some k -> k | None -> 'V' in
           let token = if kind = 'V' then field_token ctx
             else payload_token ctx in
           Printf.bprintf buf "T\t%d\t%c\t%s\n" id kind name;
           add_ctor_rows ctx buf name ctors token)
      | Tir.TDRecord (name, fields) when not (Hashtbl.mem emitted name) ->
        (match Hashtbl.find_opt ctx.Llvm_ctx.ctor_desc_ids name with
         | None -> ()
         | Some id ->
           Hashtbl.replace emitted name ();
           Printf.bprintf buf "T\t%d\tR\t%s\n" id name;
           (* Record slots are laid out with fields sorted by name (see
              [Llvm_data.shape_desc]); the descriptor is read positionally, so
              it must use that order and not the declaration order. *)
           let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) fields in
           List.iter (fun (fname, fty) ->
               Printf.bprintf buf "F\t%s\t%s\n" fname (field_token ctx fty))
             sorted)
      | _ -> ())
    ctx.Llvm_ctx.type_defs;
  Buffer.contents buf

(** Reserve the descriptor and base-cache globals if this is the first call
    site to need them, and return them.  The cache global is defined now; the
    descriptor STRING is only named here and is defined by [flush] once the
    whole unit has been emitted, because a later call site can still add
    instance rows ([instance_id]) and all of them must be in the one string. *)
let ensure_globals ctx : string * string =
  match ctx.Llvm_ctx.ctor_desc_globals with
  | Some pair -> pair
  | None ->
    assign_ids ctx;
    ctx.Llvm_ctx.str_ctr <- ctx.Llvm_ctx.str_ctr + 1;
    let dg = Printf.sprintf "@.ctordescstr%d" ctx.Llvm_ctx.str_ctr in
    ctx.Llvm_ctx.str_ctr <- ctx.Llvm_ctx.str_ctr + 1;
    let cg = Printf.sprintf "@.ctordesc%d" ctx.Llvm_ctx.str_ctr in
    Buffer.add_string ctx.Llvm_ctx.preamble
      (Printf.sprintf "%s = internal global i32 0\n" cg);
    ctx.Llvm_ctx.ctor_desc_globals <- Some (dg, cg);
    (dg, cg)

(** Define the descriptor string [ensure_globals] named, if any site asked
    for it.  Every module finaliser calls this after the last function body
    has been emitted ([Llvm_toplevel.emit_module] and the [Llvm_repl]
    fragment finalisers); LLVM IR lets a global be defined after its uses. *)
let flush ctx (out : Buffer.t) : unit =
  match ctx.Llvm_ctx.ctor_desc_globals with
  | None -> ()
  | Some (dg, _) ->
    (* Base rows first: building them can still add instances (a declared
       field of type [List(Meters)]), which land in the instance buffer. *)
    let base = build_desc ctx in
    let s = base ^ Buffer.contents ctx.Llvm_ctx.ctor_desc_inst_rows in
    Printf.bprintf out
      "%s = private unnamed_addr constant [%d x i8] c\"%s\\00\"\n"
      dg (String.length s + 1) (Llvm_ctx.llvm_escape_string s)

(** The local descriptor id for [ty], or [None] if it is not a type this table
    describes.  Deliberately EMITS NOTHING: it is called as a match guard at
    sites that mostly answer [None] (a tuple, a `TVar`), and forcing
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
  | Tir.TCon _ | Tir.TRecord _ -> id_for_ty ctx ty
  | _ -> None

(** Register this unit's descriptor (a cached load after the first call)
    without rendering anything.  The runtime's ERASED renders -- the generic
    `march_value_to_string` hook and `march_html_auto_escape_dyn` -- resolve
    a cell's header type id (runtime/march_runtime.h, march_hdr) through the
    table, so a site that hands the runtime an erased value must make sure
    the table exists first; nothing on the runtime side can find the
    descriptor by itself. *)
let emit_ensure ctx : unit =
  let (dg, cg) = ensure_globals ctx in
  let base = Llvm_ctx.fresh ctx "ctbase" in
  Llvm_ctx.emit ctx (Printf.sprintf
    "%s = call i32 @march_ctor_table_ensure(ptr %s, ptr %s)" base dg cg)

(** [emit_ensure] iff a value of [ty] could reach the runtime as a heap cell
    the table might identify — an erased component a boxed ADT hides in, or a
    named type at all.

    A bare [TCon] counts even though it looks fully static, because the name
    the call site carries is not always the name the type LOWERED under: a
    `ptype` inside `mod File` lowers to `File.FileError` while every
    annotation denotes the canonical bare `FileError`, so [id_for] answers
    [None] and the site falls back to the untyped renderer.  That renderer can
    still name the value from its header type id, but only once some
    descriptor has been registered — and nothing on the runtime side can find
    one by itself.  Registering here is what makes the dynamic path available;
    it does not decide anything, so a value whose header says nothing (a
    C-built cell that predates stamping, a niche value with no cell at all)
    renders exactly as it did before.

    Gated like [id_for]: the runtime half lives in march_extras.c, which the
    WASM runtime does not build. *)
let emit_ensure_if_erased ctx (ty : Tir.ty) : unit =
  let rec renderable = function
    | Tir.TVar _ -> true
    | Tir.TCon (("Int"|"Float"|"Bool"|"Unit"|"String"|"Atom"), _) -> false
    | Tir.TCon (_, _) -> true
    | Tir.TTuple ts -> List.exists renderable ts
    | Tir.TRecord fs -> List.exists (fun (_, t) -> renderable t) fs
    | _ -> false
  in
  if ctx.Llvm_ctx.shape_meta && renderable ty then emit_ensure ctx

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
