(** REPL / JIT-fragment LLVM emission: the five per-fragment emitters
    ([emit_repl_expr], [emit_repl_decl], [emit_repl_fn],
    [emit_repl_fn_with_closure_slot], [emit_fns_fragment]) plus their shared
    helpers ([repl_slot_info] and the slot/global bridge builders).

    Wave 3 Task 7 (chunk 2) split: moved verbatim out of [llvm_emit.ml] —
    same discipline as the Wave 3 Task 5/6 splits.

    De-cycling: every emitter here needs [Llvm_emit.emit_expr] (the core
    recursive expression emitter, which — per the task brief — stays in
    [llvm_emit.ml], the one piece excluded from this split) to compute its
    fragment body, so [~emit_expr] is threaded through as a labeled callback,
    same pattern as [Llvm_toplevel.emit_fn]/[emit_module] (this task) and
    [Llvm_case.emit_case] (Task 5) / [Llvm_tco.emit_mutual_tco_group]
    (Task 6). Each emitter also calls [Llvm_toplevel.emit_fn] (to compile its
    helper/extern fn list before the fragment body) and threads the SAME
    [~emit_expr] through to it — a plain forward qualified reference, not a
    second callback, since the dependency direction is llvm_repl.ml →
    llvm_toplevel.ml (one-directional: [emit_module] never calls any REPL
    emitter, confirmed by grep at move time) and [Llvm_toplevel] does not
    depend on this module. [Llvm_toplevel.build_ctor_info] /
    [Llvm_toplevel.fn_declare_str] / [Llvm_toplevel.emit_preamble] are
    likewise forward qualified references, not callbacks.

    B12 PINNED BEHAVIOR: every emitter builds its own [ctx] via
    [Llvm_ctx.make_ctx ~type_defs:types ()] scoped to the fragment's own
    [types] argument — never a shared/global type-def table — so each REPL
    fragment sees exactly the type representations known at ITS compile
    time, not a later or earlier fragment's. Preserved verbatim; the
    per-fragment [make_ctx] calls below are unchanged from before the move.

    B11 PINNED BEHAVIOR: [emit_repl_expr]/[emit_repl_decl] append
    [ctx.extra_fns] to their output (the closure-wrapper buffer) — dropping
    it would silently omit `$clo_wrap` definitions referenced by the
    fragment. Preserved verbatim (see each emitter's own comment). *)

(** Tracks REPL globals across fragments. Each entry:
    (llvm_name, llvm_type_string).  Example: ("repl_x", "ptr")
    Dead code, carried verbatim from [llvm_emit.ml] (Wave 3 Task 7 move):
    grepped at move time, no caller anywhere in the tree — see
    specs/todos.md filing. *)
type repl_globals = (string * string) list ref

let emit_repl_globals_decl (buf : Buffer.t) (globals : (string * string) list) =
  List.iter (fun (name, ty) ->
    Printf.bprintf buf "@%s = external global %s\n" name ty
  ) globals

(** A REPL variable slot: the persistent index into [march_repl_slots].
    [rs_bare] is the bare variable name (e.g. "x", "fib").
    [rs_slot] is the slot index passed to @march_repl_get / @march_repl_set.
    [rs_ty]   is the TIR type, used to pick the right bit-conversion. *)
type repl_slot_info = { rs_bare : string; rs_slot : int; rs_ty : Tir.ty }

(** Emit bridge alloca+call pairs for each prev_slot into the current function
    entry block, and register the alloca in [ctx.var_slot].
    Uses @march_repl_get(i64 slot) so no LLVM external globals are needed —
    values live in a single persistent C array that survives .so reloads. *)
let emit_prev_slot_bridges ctx (prev_slots : repl_slot_info list) =
  List.iter (fun si ->
    let llty = Llvm_ctx.llvm_ty si.rs_ty in
    let raw  = Llvm_ctx.fresh ctx "slot" in
    Printf.bprintf ctx.Llvm_ctx.buf "  %%%s.addr = alloca %s\n" si.rs_bare llty;
    Printf.bprintf ctx.Llvm_ctx.buf "  %s = call i64 @march_repl_get(i64 %d)\n" raw si.rs_slot;
    let converted = match si.rs_ty with
      | Tir.TInt | Tir.TBool | Tir.TUnit -> raw
      | Tir.TFloat ->
        let ft = Llvm_ctx.fresh ctx "fv" in
        Printf.bprintf ctx.Llvm_ctx.buf "  %s = bitcast i64 %s to double\n" ft raw;
        ft
      | _ ->
        let pt = Llvm_ctx.fresh ctx "pv" in
        Printf.bprintf ctx.Llvm_ctx.buf "  %s = inttoptr i64 %s to ptr\n" pt raw;
        pt
    in
    Printf.bprintf ctx.Llvm_ctx.buf "  store %s %s, ptr %%%s.addr\n" llty converted si.rs_bare;
    Hashtbl.replace ctx.Llvm_ctx.var_slot si.rs_bare si.rs_bare
  ) prev_slots

(** Emit a store of [result] (LLVM value of type [llty]) into slot [slot_idx]
    via @march_repl_set.  Converts non-i64 values to i64 bits first. *)
let emit_store_to_slot ctx (slot_idx : int) (result : string) (tir_ty : Tir.ty) =
  let bits = match tir_ty with
    | Tir.TInt | Tir.TBool | Tir.TUnit -> result
    | Tir.TFloat ->
      let bt = Llvm_ctx.fresh ctx "fb" in
      Printf.bprintf ctx.Llvm_ctx.buf "  %s = bitcast double %s to i64\n" bt result;
      bt
    | _ ->
      let pt = Llvm_ctx.fresh ctx "pb" in
      Printf.bprintf ctx.Llvm_ctx.buf "  %s = ptrtoint ptr %s to i64\n" pt result;
      pt
  in
  Printf.bprintf ctx.Llvm_ctx.buf "  call void @march_repl_set(i64 %d, i64 %s)\n" slot_idx bits

(** Emit thin module-level loader functions for each prior REPL slot so that
    named function bodies compiled via [emit_repl_fn] /
    [emit_repl_fn_with_closure_slot] can reference prior let-bindings as
    zero-arg calls "@<name>()".  Each loader calls @march_repl_get and returns
    the value in the correct LLVM type.  [ctx.top_fn_ret_ty] is updated so the
    AVar handler at the call site uses the matching return type.
    Writing to [ctx.buf] (not [ctx.extra_fns]) so the definitions appear even
    in [emit_repl_fn] which does not include extra_fns in its output. *)
let emit_slot_loader_fns ctx (prev_slots : repl_slot_info list) =
  List.iter (fun (si : repl_slot_info) ->
    match si.rs_ty with
    | Tir.TUnit -> ()  (* unit slots carry no meaningful value; skip *)
    | ty ->
      let fname  = Llvm_ctx.llvm_name si.rs_bare in
      let ret_ty = Llvm_ctx.llvm_ret_ty ty in
      Hashtbl.replace ctx.Llvm_ctx.top_fn_ret_ty si.rs_bare ty;
      let (conv_instr, retval) = match ty with
        | Tir.TInt | Tir.TBool -> ("", "%raw")
        | Tir.TFloat -> ("  %fv = bitcast i64 %raw to double\n", "%fv")
        | _ -> ("  %pv = inttoptr i64 %raw to ptr\n", "%pv")
      in
      Printf.bprintf ctx.Llvm_ctx.buf
        "\ndefine %s @%s() {\nentry:\n  %%raw = call i64 @march_repl_get(i64 %d)\n%s  ret %s %s\n}\n"
        ret_ty fname si.rs_slot conv_instr ret_ty retval
  ) prev_slots

(** Emit bridge alloca+load+store pairs for each prev_global into the current
    function entry block, and register the slot in [ctx.var_slot].
    This lets the body refer to REPL globals via the normal alloca load path.
    LLVM's mem2reg/SROA eliminates the extra instructions. *)
let emit_prev_global_bridges ctx (prev_globals : (string * string) list) =
  List.iter (fun (gname, llty) ->
    (* gname is "repl_N_<bare>" by construction in repl_jit (N = fragment number).
       Strip the "repl_N_" prefix to recover the bare variable name. *)
    let bare =
      let len = String.length gname in
      if len > 5 && String.sub gname 0 5 = "repl_" then begin
        let i = ref 5 in
        while !i < len && gname.[!i] >= '0' && gname.[!i] <= '9' do incr i done;
        if !i < len && gname.[!i] = '_' then
          String.sub gname (!i + 1) (len - !i - 1)
        else
          String.sub gname 5 (len - 5)  (* fallback: old "repl_<bare>" format *)
      end else gname
    in
    let tmp = Llvm_ctx.fresh ctx "br" in
    Printf.bprintf ctx.Llvm_ctx.buf "  %%%s.addr = alloca %s\n" bare llty;
    Printf.bprintf ctx.Llvm_ctx.buf "  %s = load %s, ptr @%s\n" tmp llty gname;
    Printf.bprintf ctx.Llvm_ctx.buf "  store %s %s, ptr %%%s.addr\n" llty tmp bare;
    Hashtbl.replace ctx.Llvm_ctx.var_slot bare bare
  ) prev_globals

(** Emit a REPL expression as a standalone .ll fragment.
    Returns textual LLVM IR with a function [@repl_<n>] that computes
    and returns the expression result.
    [prev_slots] are the persistent variable slots from earlier REPL inputs.
    [fns] are any helper functions the expression depends on.
    [store_as_slot] if Some k, also stores the result to slot k via
    @march_repl_set so later fragments can read it as "v". *)
let emit_repl_expr ~emit_expr ?(fast_math=false) ~(n : int) ~(ret_ty : Tir.ty)
    ~(prev_slots : repl_slot_info list)
    ~(fns : Tir.fn_def list)
    ?(extern_fns : Tir.fn_def list = [])
    ?(store_as_slot : int option = None)
    ~(types : Tir.type_def list)
    (body : Tir.expr) : string =
  let ctx = Llvm_ctx.make_ctx ~fast_math ~repl:true ~type_defs:types () in
  let pseudo_mod : Tir.tir_module = { tm_name = "repl"; tm_types = types; tm_fns = fns; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  Llvm_toplevel.build_ctor_info ctx pseudo_mod;
  List.iter (fun fn ->
      Hashtbl.replace ctx.Llvm_ctx.top_fns fn.Tir.fn_name true;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_ret_ty fn.Tir.fn_name fn.Tir.fn_ret_ty;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_nparams fn.Tir.fn_name (List.length fn.Tir.fn_params);
      if fn.Tir.fn_params = [] then Hashtbl.replace ctx.Llvm_ctx.zero_arg_fns fn.Tir.fn_name true) fns;
  (* Register pre-compiled extern functions so EApp generates direct calls *)
  List.iter (fun fn ->
      Hashtbl.replace ctx.Llvm_ctx.top_fns fn.Tir.fn_name true;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_ret_ty fn.Tir.fn_name fn.Tir.fn_ret_ty;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_nparams fn.Tir.fn_name (List.length fn.Tir.fn_params);
      if fn.Tir.fn_params = [] then Hashtbl.replace ctx.Llvm_ctx.zero_arg_fns fn.Tir.fn_name true) extern_fns;
  List.iter (Llvm_toplevel.emit_fn ~emit_expr ctx) fns;
  let ret_llty = Llvm_ctx.llvm_ty ret_ty in
  let fname = Printf.sprintf "repl_%d" n in
  Printf.bprintf ctx.Llvm_ctx.buf "\ndefine %s @%s() {\nentry:\n" ret_llty fname;
  emit_prev_slot_bridges ctx prev_slots;
  let (actual_ty, result) = emit_expr ctx body in
  let result' = Llvm_ctx.coerce ctx actual_ty result ret_llty in
  (* Store result to the persistent "v" slot so later fragments can read it. *)
  (match store_as_slot with
   | None -> ()
   | Some k -> emit_store_to_slot ctx k result' ret_ty);
  Printf.bprintf ctx.Llvm_ctx.buf "  ret %s %s\n}\n" ret_llty result';
  let out = Buffer.create 4096 in
  Llvm_toplevel.emit_preamble ~repl:true out;
  (* Declare pre-compiled functions so LLVM IR is valid even without definitions *)
  List.iter (fun fn -> Buffer.add_string out (Llvm_toplevel.fn_declare_str fn ^ "\n")) extern_fns;
  Buffer.add_buffer out ctx.Llvm_ctx.preamble;
  Buffer.add_buffer out ctx.Llvm_ctx.buf;
  Llvm_toplevel.emit_atom_show_table ctx;
  Buffer.add_buffer out ctx.Llvm_ctx.extra_fns;
  Buffer.contents out

(* Emit a REPL let-binding as a .ll fragment.
   Creates a global [@repl_<name>] and an init function [@repl_<n>_init]
   that computes the value and stores it in the global. *)
(** Emit a REPL let-binding as a .ll fragment.
    Creates an init function [@repl_<n>_init] that computes the value and
    stores it in slot [dest_slot] via @march_repl_set.  No LLVM global is
    needed — the slot table in march_extras.c persists across .so reloads. *)
let emit_repl_decl ~emit_expr ?(fast_math=false) ~(n : int) ~(name : string)
    ~(val_ty : Tir.ty)
    ~(dest_slot : int)
    ~(prev_slots : repl_slot_info list)
    ~(fns : Tir.fn_def list)
    ?(extern_fns : Tir.fn_def list = [])
    ~(types : Tir.type_def list)
    (body : Tir.expr) : string =
  ignore name;
  let ctx = Llvm_ctx.make_ctx ~fast_math ~repl:true ~type_defs:types () in
  let pseudo_mod : Tir.tir_module = { tm_name = "repl"; tm_types = types; tm_fns = fns; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  Llvm_toplevel.build_ctor_info ctx pseudo_mod;
  List.iter (fun fn ->
      Hashtbl.replace ctx.Llvm_ctx.top_fns fn.Tir.fn_name true;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_ret_ty fn.Tir.fn_name fn.Tir.fn_ret_ty;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_nparams fn.Tir.fn_name (List.length fn.Tir.fn_params);
      if fn.Tir.fn_params = [] then Hashtbl.replace ctx.Llvm_ctx.zero_arg_fns fn.Tir.fn_name true) fns;
  List.iter (fun fn ->
      Hashtbl.replace ctx.Llvm_ctx.top_fns fn.Tir.fn_name true;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_ret_ty fn.Tir.fn_name fn.Tir.fn_ret_ty;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_nparams fn.Tir.fn_name (List.length fn.Tir.fn_params);
      if fn.Tir.fn_params = [] then Hashtbl.replace ctx.Llvm_ctx.zero_arg_fns fn.Tir.fn_name true) extern_fns;
  List.iter (Llvm_toplevel.emit_fn ~emit_expr ctx) fns;
  let llty = Llvm_ctx.llvm_ty val_ty in
  let init_name = Printf.sprintf "repl_%d_init" n in
  Printf.bprintf ctx.Llvm_ctx.buf "\ndefine void @%s() {\nentry:\n" init_name;
  emit_prev_slot_bridges ctx prev_slots;
  let (actual_ty, result) = emit_expr ctx body in
  let result' = Llvm_ctx.coerce ctx actual_ty result llty in
  emit_store_to_slot ctx dest_slot result' val_ty;
  Printf.bprintf ctx.Llvm_ctx.buf "  ret void\n}\n";
  let out = Buffer.create 4096 in
  Llvm_toplevel.emit_preamble ~repl:true out;
  List.iter (fun fn -> Buffer.add_string out (Llvm_toplevel.fn_declare_str fn ^ "\n")) extern_fns;
  Buffer.add_buffer out ctx.Llvm_ctx.preamble;
  Buffer.add_buffer out ctx.Llvm_ctx.buf;
  Llvm_toplevel.emit_atom_show_table ctx;
  Buffer.add_buffer out ctx.Llvm_ctx.extra_fns;
  Buffer.contents out

(** Emit a REPL function declaration as a .ll fragment.
    The function is emitted at top level (callable by later fragments).
    A no-op [@repl_<n>_init] is emitted so the REPL runner can call it uniformly. *)
let emit_repl_fn ~emit_expr ?(fast_math=false) ~(n : int)
    ~(prev_slots : repl_slot_info list)
    ?(extern_fns : Tir.fn_def list = [])
    ~(types : Tir.type_def list)
    (fn : Tir.fn_def) : string =
  let ctx = Llvm_ctx.make_ctx ~fast_math ~repl:true ~type_defs:types () in
  let pseudo_mod : Tir.tir_module = { tm_name = "repl"; tm_types = types; tm_fns = [fn]; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  Llvm_toplevel.build_ctor_info ctx pseudo_mod;
  Hashtbl.replace ctx.Llvm_ctx.top_fns fn.Tir.fn_name true;
  Hashtbl.replace ctx.Llvm_ctx.top_fn_ret_ty fn.Tir.fn_name fn.Tir.fn_ret_ty;
  Hashtbl.replace ctx.Llvm_ctx.top_fn_nparams fn.Tir.fn_name (List.length fn.Tir.fn_params);
  if fn.Tir.fn_params = [] then Hashtbl.replace ctx.Llvm_ctx.zero_arg_fns fn.Tir.fn_name true;
  List.iter (fun f ->
      Hashtbl.replace ctx.Llvm_ctx.top_fns f.Tir.fn_name true;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_ret_ty f.Tir.fn_name f.Tir.fn_ret_ty;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_nparams f.Tir.fn_name (List.length f.Tir.fn_params);
      if f.Tir.fn_params = [] then Hashtbl.replace ctx.Llvm_ctx.zero_arg_fns f.Tir.fn_name true) extern_fns;
  emit_slot_loader_fns ctx prev_slots;
  Llvm_toplevel.emit_fn ~emit_expr ctx fn;
  let init_name = Printf.sprintf "repl_%d_init" n in
  Printf.bprintf ctx.Llvm_ctx.buf "\ndefine void @%s() {\nentry:\n  ret void\n}\n" init_name;
  let out = Buffer.create 4096 in
  Llvm_toplevel.emit_preamble ~repl:true out;
  List.iter (fun f -> Buffer.add_string out (Llvm_toplevel.fn_declare_str f ^ "\n")) extern_fns;
  Buffer.add_buffer out ctx.Llvm_ctx.preamble;
  Buffer.add_buffer out ctx.Llvm_ctx.buf;
  Llvm_toplevel.emit_atom_show_table ctx;
  Buffer.add_buffer out ctx.Llvm_ctx.extra_fns;
  Buffer.contents out

(** Emit a REPL function declaration as a .ll fragment, and also store a
    first-class closure value in slot [dest_slot] via @march_repl_set.
    The init function [@repl_<n>_init] allocates the closure and writes it
    to the slot so later fragments can load it via @march_repl_get. *)
let emit_repl_fn_with_closure_slot ~emit_expr ?(fast_math=false) ~(n : int)
    ~(bind_name : string)
    ~(dest_slot : int)
    ~(prev_slots : repl_slot_info list)
    ?(extern_fns : Tir.fn_def list = [])
    ~(types : Tir.type_def list)
    (fn : Tir.fn_def) : string =
  ignore bind_name;
  let ctx = Llvm_ctx.make_ctx ~fast_math ~repl:true ~type_defs:types () in
  let pseudo_mod : Tir.tir_module = { tm_name = "repl"; tm_types = types; tm_fns = [fn]; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  Llvm_toplevel.build_ctor_info ctx pseudo_mod;
  Hashtbl.replace ctx.Llvm_ctx.top_fns fn.Tir.fn_name true;
  Hashtbl.replace ctx.Llvm_ctx.top_fn_ret_ty fn.Tir.fn_name fn.Tir.fn_ret_ty;
  Hashtbl.replace ctx.Llvm_ctx.top_fn_nparams fn.Tir.fn_name (List.length fn.Tir.fn_params);
  if fn.Tir.fn_params = [] then Hashtbl.replace ctx.Llvm_ctx.zero_arg_fns fn.Tir.fn_name true;
  List.iter (fun f ->
      Hashtbl.replace ctx.Llvm_ctx.top_fns f.Tir.fn_name true;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_ret_ty f.Tir.fn_name f.Tir.fn_ret_ty;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_nparams f.Tir.fn_name (List.length f.Tir.fn_params);
      if f.Tir.fn_params = [] then Hashtbl.replace ctx.Llvm_ctx.zero_arg_fns f.Tir.fn_name true) extern_fns;
  emit_slot_loader_fns ctx prev_slots;
  Llvm_toplevel.emit_fn ~emit_expr ctx fn;
  (* Build a thin closure wrapper: @<fn>$clo_wrap(ptr %_clo, <concrete args>)
     via the canonical [clo_wrap_define] (see its doc comment) so this
     wrapper honors the SAME generic ptr ABI as every other closure-dispatch
     wrapper in this file: scalars tagged `(n<<1)|1`, doubles bitcast into
     the ptr slot, heap ptrs passed through.  ECallPtr call sites always
     read the result as `ptr` (see is_apply_fn) regardless of the callee's
     concrete return type — a wrapper that instead returned the raw
     concrete type (as this one used to) would declare a mismatched LLVM
     signature against that `call ptr` site, and the caller's conditional
     untag would reinterpret raw bits as tagged, corrupting odd Int
     results (B11). *)
  let fn_llvm_name = Llvm_ctx.llvm_name (Llvm_builtins.mangle_extern fn.Tir.fn_name) in
  let wrap_name = fn_llvm_name ^ "$clo_wrap" in
  let target_ret = Llvm_ctx.llvm_ret_ty fn.Tir.fn_ret_ty in
  let param_tys = List.map (fun v -> Llvm_ctx.llvm_ty v.Tir.v_ty) fn.Tir.fn_params in
  (* Same check-then-add emitted_wraps guard as the other two clo_wrap_define
     call sites: the fn is registered in ctx.top_fns BEFORE emit_fn above, so
     a body that references ITSELF as a first-class value (e.g.
     `let g = selfref`) already emitted this exact wrapper via emit_atom's
     top-fns wrap path — an unconditional second emission would define the
     same symbol twice in one fragment and clang rejects the module. *)
  if not (Hashtbl.mem ctx.Llvm_ctx.emitted_wraps wrap_name) then begin
    Hashtbl.add ctx.Llvm_ctx.emitted_wraps wrap_name ();
    Buffer.add_string ctx.Llvm_ctx.extra_fns
      (Llvm_calls.clo_wrap_define wrap_name param_tys target_ret fn_llvm_name)
  end;
  (* Init function: allocate closure {header(16), fn_ptr} and store in the slot *)
  let init_name = Printf.sprintf "repl_%d_init" n in
  Printf.bprintf ctx.Llvm_ctx.buf "\ndefine void @%s() {\nentry:\n" init_name;
  Printf.bprintf ctx.Llvm_ctx.buf "  %%hp = call ptr @march_alloc(i64 24)\n";
  Printf.bprintf ctx.Llvm_ctx.buf "  %%tgp = getelementptr i8, ptr %%hp, i64 8\n";
  Printf.bprintf ctx.Llvm_ctx.buf "  store i32 0, ptr %%tgp, align 4\n";
  Printf.bprintf ctx.Llvm_ctx.buf "  %%fp = getelementptr i8, ptr %%hp, i64 16\n";
  Printf.bprintf ctx.Llvm_ctx.buf "  store ptr @%s, ptr %%fp, align 8\n" wrap_name;
  Printf.bprintf ctx.Llvm_ctx.buf "  %%cp = ptrtoint ptr %%hp to i64\n";
  Printf.bprintf ctx.Llvm_ctx.buf "  call void @march_repl_set(i64 %d, i64 %%cp)\n" dest_slot;
  Printf.bprintf ctx.Llvm_ctx.buf "  ret void\n}\n";
  let out = Buffer.create 4096 in
  Llvm_toplevel.emit_preamble ~repl:true out;
  List.iter (fun f -> Buffer.add_string out (Llvm_toplevel.fn_declare_str f ^ "\n")) extern_fns;
  Buffer.add_buffer out ctx.Llvm_ctx.preamble;
  Buffer.add_buffer out ctx.Llvm_ctx.buf;
  (* clo_wrap_define's output above lands in ctx.extra_fns (the same buffer
     every other closure-wrap call site appends to) — include it here or the
     wrapper text is silently dropped and @<fn>$clo_wrap becomes an undefined
     symbol at link/dlopen time (B11 sibling bug: this emitter used to omit
     extra_fns entirely). *)
  Llvm_toplevel.emit_atom_show_table ctx;
  Buffer.add_buffer out ctx.Llvm_ctx.extra_fns;
  Buffer.contents out

(** Emit a collection of functions as a standalone LLVM IR module.
    Used for precompiling the stdlib to a cacheable .so fragment.
    No expression wrapper is emitted — just the function definitions. *)
let emit_fns_fragment
    ~emit_expr
    ~(types : Tir.type_def list)
    ~(fns : Tir.fn_def list)
    ?(extern_fns : Tir.fn_def list = [])
    ~(repl : bool)
    () : string =
  let ctx = Llvm_ctx.make_ctx ~repl ~type_defs:types () in
  let pseudo_mod : Tir.tir_module =
    { tm_name = "stdlib_prelude"; tm_types = types; tm_fns = fns; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  Llvm_toplevel.build_ctor_info ctx pseudo_mod;
  (* Register externals first so intra-fragment references resolve correctly. *)
  List.iter (fun f ->
      Hashtbl.replace ctx.Llvm_ctx.top_fns f.Tir.fn_name true;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_ret_ty f.Tir.fn_name f.Tir.fn_ret_ty;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_nparams f.Tir.fn_name (List.length f.Tir.fn_params);
      if f.Tir.fn_params = [] then Hashtbl.replace ctx.Llvm_ctx.zero_arg_fns f.Tir.fn_name true) extern_fns;
  List.iter (fun fn ->
      Hashtbl.replace ctx.Llvm_ctx.top_fns fn.Tir.fn_name true;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_ret_ty fn.Tir.fn_name fn.Tir.fn_ret_ty;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_nparams fn.Tir.fn_name (List.length fn.Tir.fn_params);
      if fn.Tir.fn_params = [] then Hashtbl.replace ctx.Llvm_ctx.zero_arg_fns fn.Tir.fn_name true) fns;
  List.iter (Llvm_toplevel.emit_fn ~emit_expr ctx) fns;
  let out = Buffer.create 8192 in
  Llvm_toplevel.emit_preamble ~repl out;
  List.iter (fun f -> Buffer.add_string out (Llvm_toplevel.fn_declare_str f ^ "\n")) extern_fns;
  Buffer.add_buffer out ctx.Llvm_ctx.preamble;
  Buffer.add_buffer out ctx.Llvm_ctx.buf;
  Llvm_toplevel.emit_atom_show_table ctx;
  Buffer.add_buffer out ctx.Llvm_ctx.extra_fns;
  Buffer.contents out

(** Dead code, carried verbatim from [llvm_emit.ml] (Wave 3 Task 7 move):
    no caller exists anywhere in the tree (grepped at move time) — see
    specs/todos.md filing. *)
let llvm_ty_of_tir = Llvm_ctx.llvm_ty
