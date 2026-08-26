(** `~H` sigil codegen: the bodies of [Llvm_emit.emit_expr]'s
    `html_auto_escape` and `html_escape_ctx` arms.

    Phase 2b of specs/plans/2026-08-19-compiler-file-decomposition.md, the
    per-arm delegation Phase 2 deferred.  Every arm keeps its exact position,
    guard and order in [emit_expr]'s match -- match order there is
    load-bearing (non-builtin arms interleave with builtin ones, and the TCO
    arms sit below several builtin arms), so nothing is grouped or reordered.
    Only the arm BODIES live here, byte-identical to the text they replaced.
    [emit_atom] is threaded in as a labelled callback, the convention
    [Llvm_emit_simd] and [Llvm_emit_nmap] established.

    The ordering of the four arms is the whole design of this family: the
    `Safe` fast path must be tried before the general auto-escape arm, and the
    literal-id `html_escape_ctx` arm before the dynamic-id one, because only
    the literal-id arm can make the already-safe-HTML decision statically.
    That ordering is a property of [emit_expr]'s match, which is exactly why
    only bodies moved. *)

open Llvm_ctx

let atom_tir_ty = Llvm_data.atom_tir_ty

(** Body of the `html_auto_escape` arm for an [Html.Safe] argument: the
    payload passes through unescaped, which is exactly Safe's contract. *)
let emit_html_auto_escape_safe ~emit_atom ctx (a : Tir.atom)
  : string * string =
  let emit_atom_as ctx ty a =
    let (actual_ty, v) = emit_atom ctx a in coerce ctx actual_ty v ty
  in
    let vp = emit_atom_as ctx "ptr" a in
    let fp = fresh ctx "safe_fp" in
    emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" fp vp);
    let r = fresh ctx "safe_s" in
    emit ctx (Printf.sprintf "%s = load ptr, ptr %s" r fp);
    ("ptr", r)

(** Body of the general `html_auto_escape` arm: decide from the static TIR
    type which values the runtime's polymorphic dispatch can be trusted
    with, and normalise everything else to a real String first. *)
let emit_html_auto_escape ~emit_atom ctx (a : Tir.atom) : string * string =
  let emit_atom_as ctx ty a =
    let (actual_ty, v) = emit_atom ctx a in coerce ctx actual_ty v ty
  in
    let runtime_safe =
      match atom_tir_ty a with
      | Tir.TString | Tir.TInt | Tir.TFloat | Tir.TBool -> true
      | Tir.TCon ("IOList", _) -> true
      (* An unresolved type variable is the genuinely undecidable case, and it
         is NOT hypothetical: a value reaching this hole through a closure
         stored in a container (defunctionalized dispatch, e.g.
         `Bx(Cons(fn x -> ~H"<p>${x}</p>", Nil))`) is not specialised by mono
         and arrives as TVar.  Neither answer is right for it — an IOList
         wants flattening, an ADT must not be flattened, and nothing at
         runtime can tell them apart, which is the whole defect.

         So choose the failure that is not a vulnerability: stringify.  A
         genuine IOList partial reaching a polymorphic hole renders as
         `#<tag:2>` instead of its markup — visibly wrong, and a real
         regression for that (rare) pattern.  Routing it to the runtime
         instead would leave a tag-1 ADT emitting its String field raw and
         unescaped, and a tag-2 ADT segfaulting.  A wrong-looking page beats
         an XSS and a crash.

         Fixing this properly means giving the runtime a way to identify the
         type — march_hdr.pad is free for non-record ADTs and could carry a
         type id — which is out of scope here; see
         specs/todos/2026-08-05-boxed-adt-type-id.md. *)
      | Tir.TVar _ -> false
      | _ -> false
    in
    let v = emit_atom_as ctx "ptr" a in
    let v =
      if runtime_safe then v
      else begin
        let s = fresh ctx "hae_str" in
        emit ctx
          (Printf.sprintf "%s = call ptr @march_value_to_string(ptr %s)" s v);
        s
      end
    in
    let r = fresh ctx "hae" in
    emit ctx (Printf.sprintf "%s = call ptr @march_html_auto_escape(ptr %s)" r v);
    ("ptr", r)

(** Body of the `html_escape_ctx` arm for a COMPILE-TIME escaper id. *)
let emit_html_escape_ctx_static ~emit_atom ctx (id : int) (a : Tir.atom)
  : string * string =
  let emit_atom_as ctx ty a =
    let (actual_ty, v) = emit_atom ctx a in coerce ctx actual_ty v ty
  in
    let is_html_ctx = id = 0 (* Context.escaper_id EscHtml *) in
    (* Html.Safe and IOList are both already-safe HTML, but they are UNWRAPPED
       differently. march_html_auto_escape's C body does not understand Safe at
       all — Task 0 fixed that case in the emitter, by loading field 0 — so
       handing it a Safe returns the empty string. Keep the two apart. *)
    (* Context-indexed trust. Each Trusted* type names the ONE context its
       string may be inserted into verbatim; anywhere else it is escaped like
       any other value. `Safe` is the legacy context-free form and is treated
       as HTML trust.

       This is resolved entirely here, at compile time: the type is static and
       the escaper id was folded by the desugar, so a mismatch costs nothing at
       runtime -- it just takes the escaping path. That is why these are
       separate types rather than one type carrying a context tag; a tag would
       be runtime data and could not be resolved statically.

       All are single-field ADTs, so unwrapping is the same field-0 load the
       Safe path already used.

       Escaper ids are Context.escaper_id / MARCH_ESC_* (see
       runtime/march_ctx_escape.h). A url trust covers both the whole-URL and
       component escapers, and a css trust both the value and declaration
       ones, because those pairs differ in POSITION within one language, not in
       which language the string is. *)
    let trusted_for name =
      if Collision_set.is_colliding ctx.collision_set name then None
      else
        match name with
        | "Safe" | "TrustedHtml" -> Some [ 0 ]
        | "TrustedAttr" -> Some [ 1 ]
        | "TrustedUrl" -> Some [ 2; 3 ]
        | "TrustedCss" -> Some [ 4; 7 ]
        (* A js trust covers BOTH JS escapers. 5 is a hole inside a string
           literal, 9 a hole at an expression position; they differ in
           POSITION within one language, exactly as the url and css pairs
           above do, and trusting a string as JS trusts it as JS wherever JS
           is being written. This is also what keeps `Html.trust_js` usable at
           all after the 2026-08-20 fix: expression position is the only place
           trusted JS is ever worth inserting, and it is precisely the place
           an untrusted value now gets quoted into inertness. *)
        | "TrustedJs" -> Some [ 5; 9 ]
        | _ -> None
    in
    let trusted_ids =
      match atom_tir_ty a with
      | Tir.TCon (n, _) -> trusted_for n
      | _ -> None
    in
    let is_safe = trusted_ids <> None in
    let is_iolist =
      match atom_tir_ty a with Tir.TCon ("IOList", _) -> true | _ -> false in
    let v = emit_atom_as ctx "ptr" a in
    (* Normalise to a real String first, by whichever route actually works for
       this type. `march_value_to_string` CANNOT flatten an IOList — it renders
       the constructor spine as `#<tag:2>` — so a known IOList/Safe must go
       through `march_html_auto_escape`, whose IOList path flattens verbatim.
       Everything else, including TVar (the undecidable case), takes
       to_string. *)
    let v =
      match atom_tir_ty a with
      | Tir.TString -> v
      | _ when is_safe ->
        (* Boxed single-field ADT: the wrapped String is at offset +16. *)
        let fp = fresh ctx "hec_safe_fp" in
        emit ctx (Printf.sprintf "%s = getelementptr i8, ptr %s, i64 16" fp v);
        let sv = fresh ctx "hec_safe_s" in
        emit ctx (Printf.sprintf "%s = load ptr, ptr %s" sv fp);
        sv
      | _ when is_iolist ->
        let fv = fresh ctx "hec_flat" in
        emit ctx
          (Printf.sprintf "%s = call ptr @march_html_auto_escape(ptr %s)" fv v);
        fv
      | _ ->
        let sv = fresh ctx "hec_str" in
        emit ctx
          (Printf.sprintf "%s = call ptr @march_value_to_string(ptr %s)" sv v);
        sv
    in
    let trust_covers_this_context =
      match trusted_ids with
      | Some ids -> List.mem id ids
      | None -> is_html_ctx && is_iolist
    in
    if trust_covers_this_context then
      (* The value is trusted for exactly this context: insert verbatim. *)
      ("ptr", v)
    else begin
      let r = fresh ctx "hec" in
      emit ctx
        (Printf.sprintf
           "%s = call ptr @march_html_escape_ctx(i64 %d, ptr %s)" r id v);
      ("ptr", r)
    end

(** Body of the `html_escape_ctx` arm for a RUNTIME escaper id. *)
let emit_html_escape_ctx_dynamic ~emit_atom ctx (idx : Tir.atom)
  (a : Tir.atom) : string * string =
  let emit_atom_as ctx ty a =
    let (actual_ty, v) = emit_atom ctx a in coerce ctx actual_ty v ty
  in
    let id_v = emit_atom_as ctx "i64" idx in
    let v = emit_atom_as ctx "ptr" a in
    let v =
      match atom_tir_ty a with
      | Tir.TString -> v
      | _ ->
        let sv = fresh ctx "hecd_str" in
        emit ctx
          (Printf.sprintf "%s = call ptr @march_value_to_string(ptr %s)" sv v);
        sv
    in
    let r = fresh ctx "hecd" in
    emit ctx
      (Printf.sprintf "%s = call ptr @march_html_escape_ctx(i64 %s, ptr %s)"
         r id_v v);
    ("ptr", r)

