(** LLVM emission: call-related helpers used by [emit_expr]'s EApp/ECallPtr
    match arms — the `raises`-extern env-routed wrapper, the unresolved-
    interface-method diagnostic guard, and the closure-dispatch trampoline
    generator.

    Wave 3 Task 6 (chunk 2) split: moved verbatim out of [llvm_emit.ml] — same
    discipline as the Wave 3 Task 5 [Llvm_eq]/[Llvm_data]/[Llvm_case] split:
    whole-definition moves, no behavior change, fully-qualified references
    (no [open]).  The EApp/ECallPtr match arms themselves — the general
    call path, the blocking/HCR dispatch, the indirect closure-struct call —
    stay in [llvm_emit.ml]'s [emit_expr] (they are cases of a match, not
    standalone functions; per the brief, "the emit_expr arms stay").  They
    call the helpers below by their qualified names. *)

(* For a `raises` extern declared `: Result(T, E)`, the C binding returns the
   bare Ok payload of type T (not a march_value Result).  This is T. *)
let ok_payload_ty : Tir.ty -> Tir.ty = function
  | Tir.TCon ("Result", [t_ok; _]) -> t_ok
  | t -> t

(** Emit the call-site wrapper for a `raises` extern (env-routed error protocol).
    The C binding [fname] takes a hidden march_env* first param and returns the
    bare Ok payload (T of Result(T,E) = [ret_tir]); to fail it calls
    march_raise(env, e).  We pass a stack { i64 raised; i64 err }, call, then
    materialize Ok(payload) / Err(env.err).  Result is boxed → returns ("ptr",_).
    [arg_pairs] are the (llty, value) pairs for the binding's own (non-env) args. *)
let emit_raises_wrapper ctx ~fname ~ret_tir ~arg_pairs : string * string =
  let env = Llvm_ctx.fresh ctx "env" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = alloca { i64, i64 }" env);
  let rslot = Llvm_ctx.fresh ctx "envraised" in
  Llvm_ctx.emit ctx (Printf.sprintf
    "%s = getelementptr { i64, i64 }, ptr %s, i64 0, i32 0" rslot env);
  Llvm_ctx.emit ctx (Printf.sprintf "store i64 0, ptr %s" rslot);
  let t_ok = ok_payload_ty ret_tir in
  let payload_llty = Llvm_ctx.llvm_ret_ty t_ok in
  let call_args =
    String.concat ", "
      (Printf.sprintf "ptr %s" env
       :: List.map (fun (ty, v) -> Printf.sprintf "%s %s" ty v) arg_pairs) in
  let payload =
    if payload_llty = "void" then begin
      Llvm_ctx.emit ctx (Printf.sprintf "call void @%s(%s)" fname call_args); "0"
    end else begin
      let p = Llvm_ctx.fresh ctx "okpay" in
      Llvm_ctx.emit ctx (Printf.sprintf "%s = call %s @%s(%s)" p payload_llty fname call_args); p
    end in
  let raisedv = Llvm_ctx.fresh ctx "raised" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = load i64, ptr %s" raisedv rslot);
  let cond = Llvm_ctx.fresh ctx "rcond" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = icmp ne i64 %s, 0" cond raisedv);
  let err_lbl = Llvm_ctx.fresh_block ctx "raise_err" in
  let ok_lbl  = Llvm_ctx.fresh_block ctx "raise_ok" in
  let mrg_lbl = Llvm_ctx.fresh_block ctx "raise_merge" in
  Llvm_ctx.emit_term ctx (Printf.sprintf "br i1 %s, label %%%s, label %%%s" cond err_lbl ok_lbl);
  (* Err: materialize Err(env.err) *)
  Llvm_ctx.emit_label ctx err_lbl;
  let errslot = Llvm_ctx.fresh ctx "enverr" in
  Llvm_ctx.emit ctx (Printf.sprintf
    "%s = getelementptr { i64, i64 }, ptr %s, i64 0, i32 1" errslot env);
  let errv = Llvm_ctx.fresh ctx "errv" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = load i64, ptr %s" errv errslot);
  let eres = Llvm_ctx.fresh ctx "eres" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = call ptr @march_err(i64 %s)" eres errv);
  Llvm_ctx.emit_term ctx (Printf.sprintf "br label %%%s" mrg_lbl);
  (* Ok: convert the bare payload to a march_value, then Ok(payload) *)
  Llvm_ctx.emit_label ctx ok_lbl;
  let okval = (match t_ok with
    | Tir.TInt | Tir.TBool | Tir.TUnit | Tir.TCon ("Atom", []) ->
      (* tag a raw scalar into a march_value: (v << 1) | 1 *)
      let sh = Llvm_ctx.fresh ctx "oksh" in
      Llvm_ctx.emit ctx (Printf.sprintf "%s = shl i64 %s, 1" sh payload);
      let tg = Llvm_ctx.fresh ctx "oktag" in
      Llvm_ctx.emit ctx (Printf.sprintf "%s = or i64 %s, 1" tg sh); tg
    | Tir.TFloat ->
      (* the bare payload is a double; the Result Ok slot holds the raw IEEE
         bits (Result is a plain boxed ADT — no extra boxing for Float). *)
      let bits = Llvm_ctx.fresh ctx "okfbits" in
      Llvm_ctx.emit ctx (Printf.sprintf "%s = call i64 @march_make_float(double %s)" bits payload); bits
    | _ ->
      (* heap/String/record/variant: the payload word is already a value *)
      let pi = Llvm_ctx.fresh ctx "okp2i" in
      Llvm_ctx.emit ctx (Printf.sprintf "%s = ptrtoint ptr %s to i64" pi payload); pi) in
  let ores = Llvm_ctx.fresh ctx "ores" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = call ptr @march_ok(i64 %s)" ores okval);
  Llvm_ctx.emit_term ctx (Printf.sprintf "br label %%%s" mrg_lbl);
  Llvm_ctx.emit_label ctx mrg_lbl;
  let result = Llvm_ctx.fresh ctx "raise_r" in
  Llvm_ctx.emit ctx (Printf.sprintf "%s = phi ptr [ %s, %%%s ], [ %s, %%%s ]"
              result eres err_lbl ores ok_lbl);
  ("ptr", result)

(* Wave 2 Task 1 defense-in-depth: a bare (unqualified, unresolved) callee
   name that exactly matches the dot-suffix of one or more registered
   interface-impl-mangled names ("Iface$Type.method") is the exact
   recurrence signature of the println-of-list miscompile — mono.ml failed
   to resolve a nested interface-method call (e.g. the `show(x)` inside
   `impl Show(List(a)) when Show(a)`), and it survived to codegen as a bare
   call.  unqualified_fns deliberately excludes these mangled names (see
   the population site in emit_module), so such a call would otherwise
   silently fall through to an unresolved `declare` that either fails at
   link time with a cryptic "undefined symbol" or — worse — coincidentally
   resolves against some unrelated same-named top-level fn.  Fail LOUDLY
   instead, naming the unresolved symbol and the candidate impls, so this
   can never again silently mis-bind to the wrong impl.

   Called from BOTH unqualified_fns consumers — the general EApp call path
   and the ECallPtr no-var-slot catch-all — with the same message, so any
   future refinement of this check lands in both. *)
let fail_if_unresolved_iface_method ctx (bare_name : string) : unit =
  let candidates =
    Hashtbl.fold (fun name _ acc ->
        if Tir_names.is_iface_mangled name then
          match String.rindex_opt name '.' with
          | Some i ->
            let suffix = String.sub name (i + 1) (String.length name - i - 1) in
            if suffix = bare_name then name :: acc else acc
          | None -> acc
        else acc)
      ctx.Llvm_ctx.top_fns []
  in
  if candidates <> [] then
    failwith (Printf.sprintf
      "llvm_emit: unresolved interface-method call to `%s` reached codegen \
       unspecialized (mono.ml should have rewritten this to a concrete impl). \
       Candidate impls found (dispatch is ambiguous / was never resolved): %s. \
       This is a monomorphization bug, not a linker issue — refusing to \
       silently bind to an arbitrary one of these impls."
      bare_name (String.concat ", " candidates))

(** Emit a `$clo_wrap` trampoline that forwards to [fn_name] and returns the
    result in the generic ptr ABI shared by all closure dispatch (see
    [is_apply_fn]).  A closure struct's fn-pointer is type-erased, so a thin
    closure wrapping a named function MUST present the same ptr ABI as a lambda
    apply wrapper — otherwise the ECallPtr dispatch (which reads ptr) would
    misread a concrete `i64`/`double` return (e.g. a Bool-returning predicate
    passed to List.filter, read back tagged and inverted).  Scalars are tagged
    `(n<<1)|1` and floats bitcast into the ptr slot; the consumer untags via the
    usual ptr->scalar coerce.  void wrappers carry no value (ret ptr null). *)
let clo_wrap_define wrap_name (param_ltys : string list) target_ret fn_name =
  let arg_names = List.mapi (fun i _ -> Printf.sprintf "%%a%d" i) param_ltys in
  (* Closure dispatch uses a uniform ptr ABI (see is_apply_fn / the ECallPtr
     call site).  A `double` param would land in an FP register while the
     dispatch reads a GP register — integer scalars coincide across the two
     classes, floats do NOT — so a Float param crosses BOXED as a ptr
     (float-boxing, Stage 2).  The wrapper takes ptr and UNBOXES to double
     before forwarding to the concrete target; likewise a Float return is BOXED
     before entering the erased ptr ABI. *)
  let wrapper_tys =
    List.map (fun t -> if t = "double" then "ptr" else t) param_ltys in
  let decl_str =
    String.concat ", "
      ("ptr %_clo" :: List.map2 (fun t n -> t ^ " " ^ n) wrapper_tys arg_names) in
  let prologue = Buffer.create 64 in
  let call_arg_strs =
    List.map2 (fun target_ty name ->
        if target_ty = "double" then begin
          let d = name ^ "d" in
          Buffer.add_string prologue
            (Printf.sprintf "  %s = call double @march_unbox_float(ptr %s)\n" d name);
          "double " ^ d
        end else target_ty ^ " " ^ name)
      param_ltys arg_names in
  let call_args = String.concat ", " call_arg_strs in
  let pro = Buffer.contents prologue in
  if target_ret = "void" then
    Printf.sprintf
      "define ptr @%s(%s) {\nentry:\n%s  call void @%s(%s)\n  ret ptr null\n}\n\n"
      wrap_name decl_str pro fn_name call_args
  else if target_ret = "ptr" then
    Printf.sprintf
      "define ptr @%s(%s) {\nentry:\n%s  %%r = call ptr @%s(%s)\n  ret ptr %%r\n}\n\n"
      wrap_name decl_str pro fn_name call_args
  else if target_ret = "double" then
    Printf.sprintf
      "define ptr @%s(%s) {\nentry:\n%s  %%r = call double @%s(%s)\n  \
       %%rp = call ptr @march_alloc_float(double %%r)\n  \
       ret ptr %%rp\n}\n\n"
      wrap_name decl_str pro fn_name call_args
  else
    (* scalar (i64): tag as (n<<1)|1 so the dispatch's conditional untag recovers it *)
    Printf.sprintf
      "define ptr @%s(%s) {\nentry:\n%s  %%r = call %s @%s(%s)\n  \
       %%rs = shl i64 %%r, 1\n  %%rt = or i64 %%rs, 1\n  \
       %%rp = inttoptr i64 %%rt to ptr\n  ret ptr %%rp\n}\n\n"
      wrap_name decl_str pro target_ret fn_name call_args
