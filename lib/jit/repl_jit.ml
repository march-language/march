(* lib/jit/repl_jit.ml *)

(* Detect macOS without forking a subprocess — check for a macOS-only path. *)
let is_macos () =
  Sys.os_type = "Unix" &&
  Sys.file_exists "/System/Library/CoreServices/SystemVersion.plist"

type t = {
  runtime_so   : string;
  clang        : string;
  tmp_dir      : string;
  undef_flag   : string;  (* "-undefined dynamic_lookup" on macOS, "" elsewhere *)
  mutable counter : int;
  mutable globals : (string * string) list;  (* (llvm_name, llvm_ty) *)
  mutable handles : Jit.dl_handle list;      (* open dl handles *)
  compiled_fns : (string, unit) Hashtbl.t;  (* fns already compiled in prior fragments *)
}

let create ~runtime_so ?(clang="clang") () =
  let tmp_dir = Filename.concat
    (Filename.get_temp_dir_name ()) "march_jit" in
  (try Unix.mkdir tmp_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  (* Load the runtime .so first so its symbols are globally available *)
  let rt_handle = Jit.dlopen runtime_so in
  let undef_flag = if is_macos () then " -undefined dynamic_lookup" else "" in
  { runtime_so; clang; tmp_dir; undef_flag;
    counter = 0; globals = []; handles = [rt_handle];
    compiled_fns = Hashtbl.create 256 }

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
  (* dlopen the .so *)
  let handle = Jit.dlopen so_path in
  ctx.handles <- handle :: ctx.handles;
  handle

(** True if a TIR function name resolves to a C runtime symbol (i.e. mangle
    changes its name). Such functions are already in the runtime .so and must
    not be re-defined in a JIT fragment or LLVM will reject the double-define. *)
let is_c_runtime_fn name =
  March_tir.Llvm_emit.mangle_extern name <> name

(** Partition functions into (new_fns, extern_fns):
    - new_fns: not yet compiled → will be defined in this fragment, recorded
      in compiled_fns.
    - extern_fns: already compiled in a prior fragment or stdlib prelude →
      need `declare` in the IR so LLVM IR is valid.
    C-runtime functions (already declared in emit_preamble) are excluded
    from both lists. *)
let partition_fns ctx (fns : March_tir.Tir.fn_def list)
    : March_tir.Tir.fn_def list * March_tir.Tir.fn_def list =
  let new_fns = ref [] and extern_fns = ref [] in
  List.iter (fun (f : March_tir.Tir.fn_def) ->
    if is_c_runtime_fn f.fn_name then ()
    else if Hashtbl.mem ctx.compiled_fns f.fn_name then
      extern_fns := f :: !extern_fns
    else begin
      Hashtbl.replace ctx.compiled_fns f.fn_name ();
      new_fns := f :: !new_fns
    end
  ) fns;
  (List.rev !new_fns, List.rev !extern_fns)

(** Strip the "repl_" prefix from a global name to recover the bare variable
    name as it appears in TIR. *)
let bare_of_global (gname : string) : string =
  if String.length gname > 5 && String.sub gname 0 5 = "repl_"
  then String.sub gname 5 (String.length gname - 5)
  else gname

(** Lower a single-expression module through the TIR pipeline.
    [repl_vars] are bare variable names of REPL globals that should be
    treated as borrowed by Perceus so they are never freed mid-session. *)
let lower_module ~type_map ?(repl_vars : string list = []) (m : March_ast.Ast.module_) =
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus ~repl_vars tir in
  let tir = March_tir.Escape.escape_analysis tir in
  tir

let run_expr ctx ~type_map m =
  let n = next_id ctx in
  let repl_vars = List.map (fun (gname, _) -> bare_of_global gname) ctx.globals in
  let tir = lower_module ~type_map ~repl_vars m in
  (* The last function in the module is the expression wrapper.
     Extract its body and return type. *)
  let main_fn = List.find (fun (f : March_tir.Tir.fn_def) ->
    f.fn_name = "main") tir.March_tir.Tir.tm_fns in
  let ret_ty = main_fn.fn_ret_ty in
  let support_fns = List.filter (fun (f : March_tir.Tir.fn_def) ->
    f.fn_name <> "main") tir.March_tir.Tir.tm_fns in
  (* Partition into new (to define) and extern (already compiled, need declare). *)
  let (new_fns, extern_fns) = partition_fns ctx support_fns in
  let ir = March_tir.Llvm_emit.emit_repl_expr
    ~n ~ret_ty
    ~prev_globals:ctx.globals
    ~fns:new_fns
    ~extern_fns
    ~types:tir.March_tir.Tir.tm_types
    main_fn.fn_body in
  let handle = compile_fragment ctx ir in
  let sym_name = Printf.sprintf "repl_%d" n in
  let fptr = Jit.dlsym handle sym_name in
  (* Call based on return type *)
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
      (* Unresolved type variable — the LLVM function returns ptr, but the
         actual value is almost always a scalar stored via inttoptr (e.g.,
         a large integer from List.length, fold, etc.).  On ARM64/x86-64
         both ptr and i64 occupy the same register, so call_void_to_int
         reads the raw bits correctly regardless of the declared return type.
         This avoids the old 4096 heuristic which broke for any integer > 4095. *)
      let v = Jit.call_void_to_int fptr in
      Int64.to_string v
    | _ ->
      (* Heap-allocated value: use the pointer path.
         Values below 4 GiB are almost certainly scalars stored via inttoptr
         (small counts, flags, etc.) rather than real heap addresses. *)
      let ptr = Jit.call_void_to_ptr fptr in
      let raw = Int64.of_nativeint ptr in
      if Int64.compare raw 0x100000000L < 0 && Int64.compare raw 0L >= 0 then
        Int64.to_string raw
      else
        Printf.sprintf "#<value at 0x%Lx>" raw
  in
  (ret_ty, result_str)

(** Distinguish fn vs let at the AST level, not TIR.
    [is_fn_decl] is true when the original REPL input was a DFn. *)
let run_decl ctx ~type_map ~is_fn_decl ~bind_name m =
  let n = next_id ctx in
  let repl_vars = List.map (fun (gname, _) -> bare_of_global gname) ctx.globals in
  let tir = lower_module ~type_map ~repl_vars m in
  let all_support_fns = List.filter (fun (f : March_tir.Tir.fn_def) ->
    f.fn_name <> "main") tir.March_tir.Tir.tm_fns in
  (* Partition into new (to define) and extern (already compiled, need declare). *)
  let (user_fns, extern_fns) = partition_fns ctx all_support_fns in
  if is_fn_decl then begin
    (* Function declaration: emit the function at top level.
       After defunctionalization a single user-defined function may produce
       multiple lifted functions (primary + closure helpers).  Find the primary
       by bind_name, emit helpers first (so their symbols are available via
       RTLD_GLOBAL), then emit the primary. *)
    let primary_fn =
      match List.find_opt (fun (f : March_tir.Tir.fn_def) ->
        f.fn_name = bind_name) user_fns with
      | Some f -> f
      | None ->
        (match user_fns with
         | f :: _ -> f
         | [] -> failwith ("run_decl: no functions produced for " ^ bind_name))
    in
    let helper_fns = List.filter
      (fun (f : March_tir.Tir.fn_def) -> f.fn_name <> primary_fn.fn_name)
      user_fns in
    (* Emit helpers first so the primary can reference them at link time *)
    List.iter (fun helper ->
      let hn = next_id ctx in
      let ir = March_tir.Llvm_emit.emit_repl_fn
        ~n:hn ~prev_globals:ctx.globals ~extern_fns ~types:tir.March_tir.Tir.tm_types
        helper in
      let _h = compile_fragment ctx ir in
      ()
    ) helper_fns;
    (* Emit primary function WITH a closure global so later fragments can
       reference bind_name as a first-class value via the global-bridge path. *)
    let pn = next_id ctx in
    let ir = March_tir.Llvm_emit.emit_repl_fn_with_closure_global
      ~n:pn ~bind_name ~prev_globals:ctx.globals ~extern_fns ~types:tir.March_tir.Tir.tm_types
      primary_fn in
    let handle = compile_fragment ctx ir in
    (* Call the init function to allocate the closure and fill @repl_<bind_name> *)
    let init_name = Printf.sprintf "repl_%d_init" pn in
    let fptr = Jit.dlsym handle init_name in
    Jit.call_void_to_void fptr;
    (* Register as a global so emit_prev_global_bridges creates the bridge alloca *)
    ctx.globals <- ("repl_" ^ bind_name, "ptr") :: ctx.globals
  end else begin
    (* Let binding: find main, extract body, store in global *)
    let main_fn = List.find (fun (f : March_tir.Tir.fn_def) ->
      f.fn_name = "main") tir.March_tir.Tir.tm_fns in
    let ir = March_tir.Llvm_emit.emit_repl_decl
      ~n ~name:bind_name
      ~val_ty:main_fn.fn_ret_ty
      ~prev_globals:ctx.globals
      ~fns:user_fns
      ~extern_fns
      ~types:tir.March_tir.Tir.tm_types
      main_fn.fn_body in
    let handle = compile_fragment ctx ir in
    let init_name = Printf.sprintf "repl_%d_init" n in
    let fptr = Jit.dlsym handle init_name in
    Jit.call_void_to_void fptr;
    let global_name = "repl_" ^ bind_name in
    let llty = March_tir.Llvm_emit.llvm_ty_of_tir main_fn.fn_ret_ty in
    ctx.globals <- (global_name, llty) :: ctx.globals
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
         already-compiled externs and link the wrong implementation. *)
      let ic = open_in names_path in
      (try while true do
        let line = String.trim (input_line ic) in
        if String.length line > 15 && String.sub line 0 15 = "lambda_counter=" then begin
          let n = int_of_string (String.sub line 15 (String.length line - 15)) in
          March_tir.Defun.set_lambda_counter n
        end else if line <> "" then
          Hashtbl.replace ctx.compiled_fns line ()
      done with End_of_file -> ());
      close_in ic
    with _ -> ())  (* Non-fatal: fall through to lazy JIT *)
  end else begin
    (* ── Cache miss: lower stdlib to TIR, compile, cache ─────────────────── *)
    let s = March_ast.Ast.dummy_span in
    let stdlib_mod : March_ast.Ast.module_ =
      { March_ast.Ast.mod_name = { txt = "StdlibPrelude"; span = s };
        mod_decls = stdlib_decls } in
    (try
      let tir = lower_module ~type_map stdlib_mod in
      let stdlib_fns = List.filter
        (fun (f : March_tir.Tir.fn_def) ->
          not (is_c_runtime_fn f.fn_name) &&
          not (Hashtbl.mem ctx.compiled_fns f.fn_name))
        tir.March_tir.Tir.tm_fns in
      if stdlib_fns <> [] then begin
        let ir = March_tir.Llvm_emit.emit_fns_fragment
          ~types:tir.March_tir.Tir.tm_types ~fns:stdlib_fns in
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
           (* Write companion names file: one function name per line, then
              a "lambda_counter=N" sentinel so cache-hit runs can restore
              the counter and avoid UID collisions with prelude functions. *)
           (try
             let nc = open_out names_path in
             List.iter (fun (f : March_tir.Tir.fn_def) ->
               output_string nc (f.fn_name ^ "\n")) stdlib_fns;
             output_string nc
               (Printf.sprintf "lambda_counter=%d\n"
                  (March_tir.Defun.get_lambda_counter ()));
             close_out nc
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
           with _ -> ())
         | _ ->
           (try Sys.remove so_path with _ -> ());
           let _ = Buffer.contents errbuf in ())
      end
    with _ -> ())  (* Non-fatal *)
  end

let cleanup ctx =
  List.iter (fun h -> try Jit.dlclose h with _ -> ()) ctx.handles;
  (* Remove tmp_dir contents *)
  let entries = Sys.readdir ctx.tmp_dir in
  Array.iter (fun f ->
    try Sys.remove (Filename.concat ctx.tmp_dir f) with _ -> ()
  ) entries;
  (try Unix.rmdir ctx.tmp_dir with _ -> ())
