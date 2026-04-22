[@@@warning "-69"]
(* lib/jit/repl_jit.ml
 *
 * REPL JIT compilation engine.
 *
 * ROOT CAUSE FIX (2026-03): The original `partition_fns` function eagerly
 * recorded every "new" function in `compiled_fns` BEFORE calling
 * `compile_fragment`.  If clang or dlopen failed for any reason, the
 * functions were "poisoned" — marked as compiled but not present in any
 * loaded .so.  On the next REPL expression those functions were treated as
 * extern (declared but not defined), causing "undefined symbol" errors that
 * were hard to diagnose and persisted for the entire session.
 *
 * The fix separates classification from recording:
 *   • `partition_fns`     — pure classification, no side effects on compiled_fns
 *   • `mark_compiled_fns` — called ONLY after compile_fragment + dlopen succeed
 *
 * This ensures that if compilation fails, compiled_fns stays consistent with
 * the set of functions actually available in loaded .sos.  On the next REPL
 * expression the same functions are re-classified as "new" and re-emitted,
 * giving the user a clean retry rather than a cryptic undefined-symbol cascade.
 *)

(* Detect macOS without forking a subprocess — check for a macOS-only path. *)
let is_macos () =
  Sys.os_type = "Unix" &&
  Sys.file_exists "/System/Library/CoreServices/SystemVersion.plist"

type t = {
  runtime_so   : string [@warning "-69"];
  clang        : string;
  tmp_dir      : string;
  undef_flag   : string;  (* "-undefined dynamic_lookup" on macOS, "" elsewhere *)
  mutable counter : int;
  (* Persistent variable slots: (bare_name, slot_idx, tir_ty).
     Each REPL variable is assigned a unique slot index; its value is stored in
     the C-level march_repl_slots[] table and retrieved via @march_repl_get.
     This replaces the old LLVM external-global bridge mechanism and eliminates
     cross-.so tagged-integer leaks. *)
  mutable var_slots : (string * int * March_tir.Tir.ty) list;
  mutable next_slot : int;
  mutable handles : Jit.dl_handle list;      (* open dl handles *)
  compiled_fns : (string, unit) Hashtbl.t;  (* fns already compiled in prior fragments *)
  global_tir_tys : (string, March_tir.Tir.ty) Hashtbl.t;  (* bare_name -> TIR type, for display *)
  mutable stdlib_decls : March_ast.Ast.decl list;  (* cached for incremental lowering context *)
}

let create ~runtime_so ?(clang="clang") () =
  let tmp_dir = Filename.concat
    (Filename.get_temp_dir_name ()) "march_jit" in
  (try Unix.mkdir tmp_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  (* Load the runtime .so first so its symbols are globally available *)
  let rt_handle = Jit.dlopen runtime_so in
  let undef_flag = if is_macos () then " -undefined dynamic_lookup" else "" in
  { runtime_so; clang; tmp_dir; undef_flag;
    counter = 0; var_slots = []; next_slot = 0;
    handles = [rt_handle];
    compiled_fns = Hashtbl.create 256;
    global_tir_tys = Hashtbl.create 16;
    stdlib_decls = [] }

let alloc_slot ctx =
  let n = ctx.next_slot in
  ctx.next_slot <- n + 1;
  n

let next_id ctx =
  let n = ctx.counter in
  ctx.counter <- n + 1;
  n

let compile_fragment ctx (ir : string) : Jit.dl_handle =
  let n = ctx.counter - 1 in
  let ll_path = Filename.concat ctx.tmp_dir
    (Printf.sprintf "repl_%d.ll" n) in
  let so_path = Filename.concat ctx.tmp_dir
    (Printf.sprintf "repl_%d.so" n) in
  (* Write .ll *)
  let oc = open_out ll_path in
  output_string oc ir;
  close_out oc;
  (* Compile to .so.
     -undefined dynamic_lookup (macOS): undefined symbols resolve at dlopen time
     from RTLD_GLOBAL, so later fragments can omit stdlib already compiled. *)
  let cmd = Printf.sprintf "%s -shared -fPIC -O1%s -o %s %s 2>&1"
    ctx.clang ctx.undef_flag so_path ll_path in
  let ic = Unix.open_process_in cmd in
  let output = Buffer.create 256 in
  (try while true do Buffer.add_char output (input_char ic) done
   with End_of_file -> ());
  let status = Unix.close_process_in ic in
  (match status with
   | Unix.WEXITED 0 -> ()
   | _ ->
     (* Keep .ll file for debugging; remove only the .so partial artifact *)
     (try Sys.remove so_path with _ -> ());
     failwith (Printf.sprintf "clang failed: %s"
       (Buffer.contents output)));
  (* dlopen the .so; remove .ll artifact now that compilation succeeded *)
  let handle = Jit.dlopen so_path in
  ctx.handles <- handle :: ctx.handles;
  if Sys.getenv_opt "MARCH_KEEP_LL" <> None then ()
  else (try Sys.remove ll_path with _ -> ());
  handle

(** True if a TIR function name resolves to a C runtime symbol (i.e. mangle
    changes its name). Such functions are already in the runtime .so and must
    not be re-defined in a JIT fragment or LLVM will reject the double-define. *)
let is_c_runtime_fn name =
  March_tir.Llvm_emit.mangle_extern name <> name

(** Classify functions into (new_fns, extern_fns) WITHOUT touching compiled_fns.
    - new_fns:    not yet compiled → will be defined in this fragment.
    - extern_fns: already compiled in a prior fragment or stdlib prelude →
                  need `declare` in the IR so LLVM IR is valid.
    C-runtime functions (already declared in emit_preamble) are excluded
    from both lists.

    IMPORTANT: this function is intentionally pure with respect to compiled_fns.
    Call [mark_compiled_fns] after a successful [compile_fragment] + dlopen to
    record new_fns as compiled.  Marking eagerly (before compilation) corrupts
    compiled_fns when compilation fails — see the file-level comment for the
    full explanation. *)
let partition_fns ctx (fns : March_tir.Tir.fn_def list)
    : March_tir.Tir.fn_def list * March_tir.Tir.fn_def list =
  let new_fns = ref [] and extern_fns = ref [] in
  List.iter (fun (f : March_tir.Tir.fn_def) ->
    if is_c_runtime_fn f.fn_name then ()
    else if Hashtbl.mem ctx.compiled_fns f.fn_name then
      extern_fns := f :: !extern_fns
    else
      new_fns := f :: !new_fns   (* no Hashtbl.replace — deferred to mark_compiled_fns *)
  ) fns;
  (List.rev !new_fns, List.rev !extern_fns)

(** Record [fns] as compiled in [ctx.compiled_fns].
    Must be called AFTER [compile_fragment] + dlopen succeed so that a
    failed compilation does not leave phantom entries that turn the next
    attempt's defines into incorrectly-declared externs. *)
let mark_compiled_fns ctx (fns : March_tir.Tir.fn_def list) =
  List.iter (fun (f : March_tir.Tir.fn_def) ->
    Hashtbl.replace ctx.compiled_fns f.fn_name ()
  ) fns

(** Build the [repl_slot_info list] passed to LLVM emit functions from
    the current [ctx.var_slots] list. *)
let prev_slots_of ctx : March_tir.Llvm_emit.repl_slot_info list =
  List.map (fun (bare, slot, ty) ->
    { March_tir.Llvm_emit.rs_bare = bare;
      rs_slot = slot;
      rs_ty   = ty })
    ctx.var_slots

(** Lower a single-expression module through the TIR pipeline.
    [repl_vars] are bare variable names of REPL globals that should be
    treated as borrowed by Perceus so they are never freed mid-session. *)
let lower_module ~type_map ?(stdlib_context : March_ast.Ast.decl list = []) ?(repl_vars : string list = []) (m : March_ast.Ast.module_) =
  let tir = March_tir.Lower.lower_module ~type_map ~stdlib_context m in
  let iface_methods = March_tir.Lower.get_iface_methods () in
  let tir = March_tir.Mono.monomorphize ~iface_methods tir in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus ~repl_vars tir in
  let tir = March_tir.Escape.escape_analysis tir in
  tir

(* ── Heap pretty-printer ───────────────────────────────────────────── *)
(* March heap layout (march_hdr):
     offset  0: int64_t rc
     offset  8: int32_t tag
     offset 12: int32_t pad
   Fields start at offset 16, 8 bytes each.
   TInt/TBool/TUnit fields are stored as int64.
   TFloat fields are stored as double (same 8-byte slot, read bits).
   All other fields (TString, TCon, TTuple, …) are stored as pointers.

   Built-in variant tag assignments (determined by constructor order in lower.ml):
     List:   Nil=0, Cons=1  (Cons fields: [head, tail])
     Option: None=0, Some=1 (Some fields: [value])
     Result: Ok=0,  Err=1   (Ok fields: [value]; Err fields: [value])
*)

(** Read the constructor tag from a heap object (int32 at offset 8). *)
let heap_tag (ptr : nativeint) : int =
  Jit.read_i32_at ptr 8

(** Read field i (0-based) as an int64 (for TInt/TBool/TUnit/TFloat). *)
let field_i64 (ptr : nativeint) (i : int) : int64 =
  Jit.read_i64_at ptr (16 + i * 8)

(** Read field i (0-based) as a pointer (for TString/TCon/TTuple/etc.). *)
let field_ptr (ptr : nativeint) (i : int) : nativeint =
  Jit.read_ptr_at ptr (16 + i * 8)

(** Pretty-print a March heap value given its TIR type.
    Recursion is bounded to depth [max_depth] to guard against unexpected
    structures; beyond that, falls back to the raw-address display. *)
let rec pp_heap_value ?(depth=0) (ty : March_tir.Tir.ty) (ptr : nativeint) : string =
  if depth > 64 then "#<...>"
  else if ptr = Nativeint.zero then "#<null>"
  else
  let open March_tir.Tir in
  match ty with
  | TString ->
    (* march_string layout: {rc:i64, len:i64, data:char[]} *)
    Printf.sprintf "%S" (Jit.read_march_string ptr)
  | TCon ("List", [elem_ty]) ->
    pp_list ~depth elem_ty ptr
  | TCon ("Option", [inner_ty]) ->
    let tag = heap_tag ptr in
    if tag = 0 then "None"
    else
      let v = pp_field ~depth inner_ty ptr 0 in
      Printf.sprintf "Some(%s)" v
  | TCon ("Result", [ok_ty; err_ty]) ->
    let tag = heap_tag ptr in
    if tag = 0 then Printf.sprintf "Ok(%s)" (pp_field ~depth ok_ty ptr 0)
    else         Printf.sprintf "Err(%s)" (pp_field ~depth err_ty ptr 0)
  | TTuple tys ->
    let fields = List.mapi (fun i ty -> pp_field ~depth ty ptr i) tys in
    Printf.sprintf "(%s)" (String.concat ", " fields)
  | _ ->
    (* Unknown heap type: show tag for basic orientation; guard null *)
    if ptr = Nativeint.zero then "#<null>"
    else Printf.sprintf "#<tag:%d>" (heap_tag ptr)

and pp_list ?(depth=0) elem_ty (ptr : nativeint) : string =
  let buf = Buffer.create 32 in
  Buffer.add_char buf '[';
  let cur = ref ptr in
  let first = ref true in
  let count = ref 0 in
  let max_elems = 10000 in
  (* Traverse Cons chain; stop at Nil (tag=0), null, or cap *)
  while !cur <> Nativeint.zero && heap_tag !cur <> 0 && !count < max_elems do
    if not !first then Buffer.add_string buf ", ";
    first := false;
    Buffer.add_string buf (pp_field ~depth elem_ty !cur 0);
    cur := field_ptr !cur 1;  (* tail is field 1 of Cons *)
    incr count
  done;
  if !count = max_elems then Buffer.add_string buf ", ...";
  Buffer.add_char buf ']';
  Buffer.contents buf

and pp_field ?(depth=0) (ty : March_tir.Tir.ty) (ptr : nativeint) (i : int) : string =
  let open March_tir.Tir in
  match ty with
  (* Scalar heap fields are stored tagged: (value << 1) | 1.  Untag before display. *)
  | TInt  -> Int64.to_string (Int64.shift_right_logical (field_i64 ptr i) 1)
  | TBool -> if Int64.shift_right_logical (field_i64 ptr i) 1 = 0L then "false" else "true"
  | TUnit -> "()"
  | TFloat ->
    (* Floats are stored as raw double bits via bitcast — no tag bit. *)
    let bits = field_i64 ptr i in
    Printf.sprintf "%g" (Int64.float_of_bits bits)
  | _ ->
    (* Pointer field: read the child pointer, then recurse *)
    let child = field_ptr ptr i in
    if child = Nativeint.zero then "null"
    else pp_heap_value ~depth:(depth + 1) ty child

(* ── run_expr ──────────────────────────────────────────────────────── *)

let run_expr ctx ~tc_env m =
  (* Typecheck and lower BEFORE advancing the counter so a failure leaves no gap. *)
  let repl_vars = List.map (fun (bare, _, _) -> bare) ctx.var_slots in
  let errors = March_errors.Errors.create () in
  let env = { tc_env with March_typecheck.Typecheck.errors } in
  let (_, type_map) = March_typecheck.Typecheck.check_module_with_env env m in
  let tir = lower_module ~type_map ~stdlib_context:ctx.stdlib_decls ~repl_vars m in
  let main_fn = match List.find_opt (fun (f : March_tir.Tir.fn_def) ->
    f.fn_name = "main") tir.March_tir.Tir.tm_fns with
  | Some f -> f
  | None -> failwith "run_expr: TIR pipeline produced no 'main' function"
  in
  let ret_ty = main_fn.fn_ret_ty in
  let support_fns = List.filter (fun (f : March_tir.Tir.fn_def) ->
    f.fn_name <> "main") tir.March_tir.Tir.tm_fns in
  let (new_fns, extern_fns) = partition_fns ctx support_fns in
  (* Allocate (or reuse) the "v" slot so store_as_slot writes the result there. *)
  let v_slot = match List.find_opt (fun (b, _, _) -> b = "v") ctx.var_slots with
    | Some (_, s, _) -> s
    | None -> alloc_slot ctx
  in
  (* Advance counter only when we are about to emit — keeps counter in sync with artifacts. *)
  let n = next_id ctx in
  let ir = March_tir.Llvm_emit.emit_repl_expr
    ~n ~ret_ty
    ~prev_slots:(prev_slots_of ctx)
    ~fns:new_fns
    ~extern_fns
    ~store_as_slot:(Some v_slot)
    ~types:tir.March_tir.Tir.tm_types
    main_fn.fn_body in
  let handle = compile_fragment ctx ir in
  mark_compiled_fns ctx new_fns;
  let sym_name = Printf.sprintf "repl_%d" n in
  let fptr = Jit.dlsym handle sym_name in
  let result_str = match ret_ty with
    | March_tir.Tir.TInt ->
      let v = Jit.call_void_to_int fptr in
      Int64.to_string v
    | March_tir.Tir.TFloat ->
      let v = Jit.call_void_to_float fptr in
      Printf.sprintf "%g" v
    | March_tir.Tir.TBool ->
      let v = Jit.call_void_to_int fptr in
      if v = 0L then "false" else "true"
    | March_tir.Tir.TUnit ->
      Jit.call_void_to_void fptr;
      "()"
    | March_tir.Tir.TVar _ ->
      (* Unresolved type var — try to recover the actual type from global_tir_tys
         by inspecting the body's return variable.  If we can recover a scalar type
         (Int/Bool), read as int.  For known heap types, call as ptr and pretty-print.
         If completely unknown, call as ptr and display the raw address. *)
      let rec find_retvar body = match body with
        | March_tir.Tir.EAtom (March_tir.Tir.AVar v) -> Some v.March_tir.Tir.v_name
        | March_tir.Tir.ESeq (_, e2) -> find_retvar e2
        | March_tir.Tir.ELet (_, _, e2) -> find_retvar e2
        | _ -> None
      in
      let stored_ty = match find_retvar main_fn.March_tir.Tir.fn_body with
        | Some vname -> Hashtbl.find_opt ctx.global_tir_tys vname
        | None -> None
      in
      (match stored_ty with
       | Some March_tir.Tir.TBool ->
         let v = Jit.call_void_to_int fptr in
         if v = 0L then "false" else "true"
       | Some March_tir.Tir.TInt ->
         Int64.to_string (Jit.call_void_to_int fptr)
       | Some ty ->
         let ptr = Jit.call_void_to_ptr fptr in
         if ptr = Nativeint.zero then "null"
         else pp_heap_value ty ptr
       | None ->
         (* No type information — call as ptr (safer than int for heap objects).
            Small values that fit in a tagged integer are displayed as integers;
            everything else shown as an opaque address. *)
         let ptr = Jit.call_void_to_ptr fptr in
         let raw = Int64.of_nativeint ptr in
         if Int64.compare raw 0x100000000L < 0 && Int64.compare raw 0L >= 0 then
           Int64.to_string raw
         else
           Printf.sprintf "#<0x%Lx>" raw)
    | ty ->
      let ptr = Jit.call_void_to_ptr fptr in
      if ptr = Nativeint.zero then "null"
      else
        let raw = Int64.of_nativeint ptr in
        if Int64.compare raw 0x100000000L < 0 && Int64.compare raw 0L >= 0 then
          Int64.to_string raw
        else
          pp_heap_value ty ptr
  in
  (* Update the "v" slot entry (type may change with each expression). *)
  ctx.var_slots <- ("v", v_slot, ret_ty) ::
    List.filter (fun (b, _, _) -> b <> "v") ctx.var_slots;
  Hashtbl.replace ctx.global_tir_tys "v" ret_ty;
  (ret_ty, result_str)

(** Distinguish fn vs let at the AST level, not TIR.
    [is_fn_decl] is true when the original REPL input was a DFn. *)
let run_decl ctx ~tc_env ~is_fn_decl ~bind_name m =
  (* Typecheck and lower BEFORE advancing the counter — failures leave no gap. *)
  let repl_vars = List.map (fun (bare, _, _) -> bare) ctx.var_slots in
  let errors = March_errors.Errors.create () in
  let env = { tc_env with March_typecheck.Typecheck.errors } in
  let (_, type_map) = March_typecheck.Typecheck.check_module_with_env env m in
  let tir = lower_module ~type_map ~stdlib_context:ctx.stdlib_decls ~repl_vars m in
  let all_support_fns = List.filter (fun (f : March_tir.Tir.fn_def) ->
    f.fn_name <> "main") tir.March_tir.Tir.tm_fns in
  let (user_fns, extern_fns) = partition_fns ctx all_support_fns in
  if is_fn_decl then begin
    (* JIT context persists across :reset.  When the scroll system resends prior
       cells, the function is already compiled and its closure slot is still valid.
       Skip recompilation entirely — helper lambdas may have new defun UIDs but
       the compiled closure is unchanged. *)
    if Hashtbl.mem ctx.compiled_fns bind_name then ()
    else begin
    let primary_fn =
      match List.find_opt (fun (f : March_tir.Tir.fn_def) ->
        f.fn_name = bind_name) user_fns with
      | Some f -> f
      | None -> List.hd user_fns
    in
    let helper_fns = List.filter
      (fun (f : March_tir.Tir.fn_def) -> f.fn_name <> primary_fn.fn_name)
      user_fns in
    (* Compile all helper lambdas in ONE combined fragment so they can freely
       reference each other (e.g., outer lambda creates inner lambda's closure).
       Compiling helpers separately caused cross-reference failures when the
       outer lambda's IR referenced the inner lambda before it was declared. *)
    (if helper_fns <> [] then begin
      ignore (next_id ctx);  (* advance counter so compile_fragment uses right id *)
      let ir = March_tir.Llvm_emit.emit_fns_fragment
        ~types:tir.March_tir.Tir.tm_types ~fns:helper_fns ~extern_fns () in
      (* Wrap in compile_fragment — uses counter (= hn) for the file name. *)
      (try
        ignore (compile_fragment ctx ir);
        mark_compiled_fns ctx helper_fns
      with exn ->
        raise exn)
    end);
    (* Emit primary function AND store closure in a persistent slot. *)
    let pn = next_id ctx in
    let slot = alloc_slot ctx in
    let ir = March_tir.Llvm_emit.emit_repl_fn_with_closure_slot
      ~n:pn ~bind_name ~dest_slot:slot ~prev_slots:(prev_slots_of ctx)
      ~extern_fns:(extern_fns @ helper_fns) ~types:tir.March_tir.Tir.tm_types
      primary_fn in
    let handle = compile_fragment ctx ir in
    mark_compiled_fns ctx [primary_fn];
    let init_name = Printf.sprintf "repl_%d_init" pn in
    let fptr = Jit.dlsym handle init_name in
    Jit.call_void_to_void fptr;
    (* Register the slot so future fragments can load the closure as a value.
       The type is TFn (closures are heap pointers), which causes emit_prev_slot_bridges
       to emit inttoptr when loading the closure from the slot. *)
    ctx.var_slots <- (bind_name, slot, March_tir.Tir.TFn ([], March_tir.Tir.TUnit)) ::
      List.filter (fun (b, _, _) -> b <> bind_name) ctx.var_slots
    end (* if user_fns <> [] *)
  end else begin
    (* Let binding: compute value and store in a fresh slot. *)
    let main_fn = match List.find_opt (fun (f : March_tir.Tir.fn_def) ->
      f.fn_name = "main") tir.March_tir.Tir.tm_fns with
    | Some f -> f
    | None -> failwith "run_decl: TIR pipeline produced no 'main' function"
    in
    let slot = alloc_slot ctx in
    (* Advance counter only when about to emit. *)
    let n = next_id ctx in
    let ir = March_tir.Llvm_emit.emit_repl_decl
      ~n ~name:bind_name
      ~val_ty:main_fn.fn_ret_ty
      ~dest_slot:slot
      ~prev_slots:(prev_slots_of ctx)
      ~fns:user_fns
      ~extern_fns
      ~types:tir.March_tir.Tir.tm_types
      main_fn.fn_body in
    let handle = compile_fragment ctx ir in
    mark_compiled_fns ctx user_fns;
    let init_name = Printf.sprintf "repl_%d_init" n in
    let fptr = Jit.dlsym handle init_name in
    Jit.call_void_to_void fptr;
    (* Register slot for future references to bind_name. *)
    ctx.var_slots <- (bind_name, slot, main_fn.fn_ret_ty) ::
      List.filter (fun (b, _, _) -> b <> bind_name) ctx.var_slots;
    Hashtbl.replace ctx.global_tir_tys bind_name main_fn.fn_ret_ty
  end

(** Pre-compile stdlib functions to a cached .so, keyed by a content hash
    of the stdlib source files.

    Two-tier cache in ~/.cache/march/:
      stdlib_prelude_<hash>.so    — compiled shared library
      stdlib_prelude_<hash>.names — newline-separated list of function names

    On cache hit: dlopen the .so, read function names from the .names file,
      mark all functions as compiled — NO TIR lowering needed.
    On cache miss: lower [stdlib_decls] to TIR, compile to a .so, write the
      .names file, then dlopen.

    [content_hash] must be a hex string derived from the stdlib source content
    (see [stdlib_content_hash] in the caller).  Using source-level hashing
    avoids the expensive TIR-lowering step on every warm-cache startup.

    After this call, every stdlib TIR function is recorded in [ctx.compiled_fns]
    so subsequent [run_expr] / [run_decl] fragments don't re-emit them. *)
let precompile_stdlib ctx
    ~(content_hash : string)
    ~(stdlib_decls : March_ast.Ast.decl list)
    ~(type_map     : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t) =
  ignore type_map;
  ctx.stdlib_decls <- stdlib_decls;
  let home = (try Sys.getenv "HOME" with Not_found -> ".") in
  let cache_dir = Filename.concat home ".cache/march" in
  let short_hash = String.sub content_hash 0 16 in
  let so_path    = Filename.concat cache_dir
    ("stdlib_prelude_O1_" ^ short_hash ^ ".so") in
  let names_path = Filename.concat cache_dir
    ("stdlib_prelude_O1_" ^ short_hash ^ ".names") in
  (* ── Cache hit path ───────────────────────────────────────────────────── *)
  if Sys.file_exists so_path && Sys.file_exists names_path then begin
    (try
      let handle = Jit.dlopen so_path in
      ctx.handles <- handle :: ctx.handles;
      (* Read function names and mark as compiled.
         The last line of the .names file may be "lambda_counter=N" — if so,
         restore the defun lambda counter so that fresh REPL compilations
         always assign UIDs strictly above those used by prelude functions.
         Without this, a cache-hit run starts the counter at 0 and the REPL's
         freshly-generated go$apply$N functions get UIDs that collide with
         prelude-compiled functions, causing partition_fns to treat them as
         already-compiled externs and link the wrong implementation.
         Use Fun.protect to guarantee close_in even on malformed lines. *)
      let ic = open_in names_path in
      Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
        try while true do
          let line = String.trim (input_line ic) in
          if String.length line > 15 && String.sub line 0 15 = "lambda_counter=" then begin
            let n = int_of_string (String.sub line 15 (String.length line - 15)) in
            March_tir.Defun.set_lambda_counter n
          end else if line <> "" then
            Hashtbl.replace ctx.compiled_fns line ()
        done with End_of_file -> ())
    with exn ->
      Printf.eprintf "march JIT: stdlib cache load failed (%s), recompiling\n%!"
        (Printexc.to_string exn))
  end else begin
    (* ── Cache miss: lower stdlib to TIR, compile, cache ─────────────────── *)
    (* Ensure cache directory exists — first run or non-standard XDG layout. *)
    (try Unix.mkdir cache_dir 0o755
     with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
    let s = March_ast.Ast.dummy_span in
    let stdlib_mod : March_ast.Ast.module_ =
      { March_ast.Ast.mod_name = { txt = "StdlibPrelude"; span = s };
        mod_decls = stdlib_decls } in
    (try
      let (_, type_map_stdlib) = March_typecheck.Typecheck.check_module stdlib_mod in
      let tir = lower_module ~type_map:type_map_stdlib stdlib_mod in
      let stdlib_fns = List.filter
        (fun (f : March_tir.Tir.fn_def) ->
          not (is_c_runtime_fn f.fn_name) &&
          not (Hashtbl.mem ctx.compiled_fns f.fn_name))
        tir.March_tir.Tir.tm_fns in
      if stdlib_fns <> [] then begin
        let ir = March_tir.Llvm_emit.emit_fns_fragment
          ~types:tir.March_tir.Tir.tm_types ~fns:stdlib_fns () in
        let n = next_id ctx in
        let ll_path = Filename.concat ctx.tmp_dir
          (Printf.sprintf "stdlib_prelude_%d.ll" n) in
        let oc = open_out ll_path in
        output_string oc ir;
        close_out oc;
        let cmd = Printf.sprintf "%s -shared -fPIC -O1%s -o %s %s 2>&1"
          ctx.clang ctx.undef_flag so_path ll_path in
        let ic = Unix.open_process_in cmd in
        let errbuf = Buffer.create 256 in
        (try while true do Buffer.add_char errbuf (input_char ic) done
         with End_of_file -> ());
        (match Unix.close_process_in ic with
         | Unix.WEXITED 0 ->
           (* .ll no longer needed once clang succeeded. *)
           (try Sys.remove ll_path with _ -> ());
           (* Write companion names file: one function name per line, then
              a "lambda_counter=N" sentinel so cache-hit runs can restore
              the counter and avoid UID collisions with prelude functions. *)
           (try
             let nc = open_out names_path in
             Fun.protect ~finally:(fun () -> close_out_noerr nc) (fun () ->
               List.iter (fun (f : March_tir.Tir.fn_def) ->
                 output_string nc (f.fn_name ^ "\n")) stdlib_fns;
               output_string nc
                 (Printf.sprintf "lambda_counter=%d\n"
                    (March_tir.Defun.get_lambda_counter ())))
           with _ -> ());
           (* Only mark functions as compiled if the .so was actually loaded.
              If we mark them before dlopen, future fragments would declare them
              as extern and then fail at link time with "symbol not found". *)
           (try
             let handle = Jit.dlopen so_path in
             ctx.handles <- handle :: ctx.handles;
             List.iter (fun (f : March_tir.Tir.fn_def) ->
               Hashtbl.replace ctx.compiled_fns f.fn_name ()
             ) stdlib_fns
           with exn ->
             Printf.eprintf "march JIT: stdlib .so dlopen failed (%s)\n%!"
               (Printexc.to_string exn))
         | _ ->
           (try Sys.remove so_path with _ -> ());
           Printf.eprintf "march JIT: stdlib precompile failed:\n%s\n%!"
             (Buffer.contents errbuf))
      end
    with exn ->
      Printf.eprintf "march JIT: stdlib lower/typecheck failed (%s)\n%!"
        (Printexc.to_string exn))
  end

let cleanup ctx =
  List.iter (fun h -> try Jit.dlclose h with _ -> ()) ctx.handles;
  if Sys.getenv_opt "MARCH_KEEP_LL" <> None then ()
  else begin
    (* Remove tmp_dir contents *)
    let entries = Sys.readdir ctx.tmp_dir in
    Array.iter (fun f ->
      try Sys.remove (Filename.concat ctx.tmp_dir f) with _ -> ()
    ) entries;
    (try Unix.rmdir ctx.tmp_dir with _ -> ())
  end
