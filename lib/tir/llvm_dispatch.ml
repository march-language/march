(** LLVM emission: generated runtime dispatch functions for a GENERAL
    (non-type-dispatched-builtin) interface method on a same-short-name
    colliding type. Mirrors [Llvm_eq.ensure_adt_eq_fn] exactly: a
    self-contained function body built into a LOCAL [Buffer.t] (NOT
    [Llvm_ctx.emit]/[Llvm_ctx.fresh], which write into whichever function is
    CURRENTLY being emitted), then appended whole to [ctx.extra_fns] and
    memoized in [ctx.emitted_dispatch_fns].

    Why a generated function per (iface, method, short-name) rather than an
    inline switch at every call site: a colliding short name may be called
    from many sites (mirrors why [ensure_adt_eq_fn] generates one [==] fn per
    type rather than inlining a comparison at every use).

    The function switches on the callee's runtime constructor tag — read at
    the fixed Boxed-header offset 8 (Task 2 forces colliding types to the
    uniform Boxed representation, so arg0 is always a heap cell whose tag is
    readable there; Task 1 gives each colliding type's constructors a
    GLOBALLY-unique tag) — and tail-calls the module-qualified impl symbol
    (Task 3) for the declaring type that owns that tag.

    Signature is taken from the actual call site rather than assumed
    [ptr -> ptr]: [param_tys] is the LLVM type of each forwarded argument
    (arg0 is the dispatched Boxed value = "ptr"; any further args pass through
    verbatim) and [ret_ty] the LLVM return type. All impls of one interface
    method for the colliding short name share this signature (same interface
    method type, same Boxed arg0), and the dispatch fn forwards every argument
    unchanged, so define/tail-call/call-site signatures agree by construction. *)

(** Enumerate the (global) constructor tags declared by [qualified_type_name],
    read from [ctx.ctor_info]'s "TypeName.CtorName" keys. *)
let tags_of_type (ctx : Llvm_ctx.ctx) (qualified_type_name : string) : int list =
  let prefix = qualified_type_name ^ "." in
  let plen = String.length prefix in
  Hashtbl.fold (fun key entry acc ->
      if String.length key > plen && String.sub key 0 plen = prefix
      (* direct constructor of this type, not a nested-type key *)
      && not (String.contains
                (String.sub key plen (String.length key - plen)) '.')
      then entry.Llvm_ctx.ce_tag :: acc
      else acc)
    ctx.Llvm_ctx.ctor_info []

let emit_dispatch_fn (ctx : Llvm_ctx.ctx) ~(fn_name : string)
    ~(param_tys : string list) ~(ret_ty : string)
    ~(rows : (string * string) list) : unit =
  Hashtbl.replace ctx.Llvm_ctx.emitted_dispatch_fns fn_name ();
  let buf = Buffer.create 256 in
  let ctr = ref 0 in
  let frsh pfx = incr ctr; Printf.sprintf "%%%s%d" pfx !ctr in
  let e ln = Buffer.add_string buf ("  " ^ ln ^ "\n") in
  (* Parameter list: arg0 (the dispatched Boxed value) plus any pass-through
     args. Names are %arg0..%argN-1; the same names are forwarded to each
     impl's tail call. *)
  let params =
    List.mapi (fun i ty -> (ty, Printf.sprintf "%%arg%d" i)) param_tys in
  let params_decl =
    String.concat ", " (List.map (fun (ty, nm) -> ty ^ " " ^ nm) params) in
  let params_fwd = params_decl in
  Buffer.add_string buf
    (Printf.sprintf "\ndefine %s @%s(%s) {\n" ret_ty fn_name params_decl);
  Buffer.add_string buf "entry:\n";
  (* Read the runtime ctor tag from the Boxed header (offset 8). arg0 is
     guaranteed ptr for a colliding (forced-Boxed) type. *)
  let tagp = frsh "tgp" in
  let tag = frsh "tag" in
  e (Printf.sprintf "%s = getelementptr i8, ptr %%arg0, i64 8" tagp);
  e (Printf.sprintf "%s = load i32, ptr %s, align 4" tag tagp);
  (* One destination block per row (declaring type / impl symbol); every tag
     that type owns routes to it.  A row whose type contributes no tags (never
     expected for a colliding type) simply adds no switch arm. *)
  let row_blocks =
    List.filter_map (fun (qtype, sym) ->
        match tags_of_type ctx qtype with
        | [] -> None
        | tags -> Some (sym, tags, frsh "row"))
      rows
  in
  let default_lbl = frsh "default" in
  let arms =
    List.concat_map (fun (_, tags, lbl) ->
        List.map (fun t ->
            Printf.sprintf "i32 %d, label %s" t lbl) tags)
      row_blocks
  in
  e (Printf.sprintf "switch i32 %s, label %s [\n    %s\n  ]"
       tag default_lbl (String.concat "\n    " arms));
  List.iter (fun (sym, _, lbl) ->
      (* [lbl] is "%rowN"; a block label is written without the leading %. *)
      Buffer.add_string buf
        (Printf.sprintf "%s:\n" (String.sub lbl 1 (String.length lbl - 1)));
      if ret_ty = "void" then begin
        e (Printf.sprintf "tail call void @%s(%s)" sym params_fwd);
        e "ret void"
      end else begin
        let r = frsh "r" in
        e (Printf.sprintf "%s = tail call %s @%s(%s)" r ret_ty sym params_fwd);
        e (Printf.sprintf "ret %s %s" ret_ty r)
      end)
    row_blocks;
  Buffer.add_string buf
    (Printf.sprintf "%s:\n" (String.sub default_lbl 1 (String.length default_lbl - 1)));
  e "unreachable";
  Buffer.add_string buf "}\n";
  Buffer.add_buffer ctx.Llvm_ctx.extra_fns buf

(** Ensure the dispatch function [fn_name] exists in [ctx.extra_fns]; returns
    [Some fn_name] (memoized like [ensure_adt_eq_fn]) or [None] when there is
    nothing to dispatch on (no rows, or no row contributes a runtime tag). *)
let ensure_dispatch_fn (ctx : Llvm_ctx.ctx) ~(fn_name : string)
    ~(param_tys : string list) ~(ret_ty : string)
    ~(rows : (string * string) list) : string option =
  if Hashtbl.mem ctx.Llvm_ctx.emitted_dispatch_fns fn_name then Some fn_name
  else if rows = [] || param_tys = [] then None
  else if List.for_all (fun (qt, _) -> tags_of_type ctx qt = []) rows then None
  else begin
    emit_dispatch_fn ctx ~fn_name ~param_tys ~ret_ty ~rows;
    Some fn_name
  end
