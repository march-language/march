(* lib/jit/repl_jit.ml *)

let is_macos () =
  Sys.os_type = "Unix" &&
  (try let ic = Unix.open_process_in "uname -s" in
       let s = input_line ic in ignore (Unix.close_process_in ic); s = "Darwin"
   with _ -> false)

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
  let cmd = Printf.sprintf "%s -shared -fPIC -O0%s -o %s %s 2>&1"
    ctx.clang ctx.undef_flag so_path ll_path in
  let ic = Unix.open_process_in cmd in
  let output = Buffer.create 256 in
  (try while true do Buffer.add_char output (input_char ic) done
   with End_of_file -> ());
  let status = Unix.close_process_in ic in
  (match status with
   | Unix.WEXITED 0 -> ()
   | _ ->
     (* Clean up temp files before raising so we don't leak on failure *)
     (try Sys.remove ll_path with _ -> ());
     (try Sys.remove so_path with _ -> ());
     failwith (Printf.sprintf "clang failed: %s"
       (Buffer.contents output)));
  (* dlopen the .so *)
  let handle = Jit.dlopen so_path in
  ctx.handles <- handle :: ctx.handles;
  handle

(** Filter a function list to only those not yet compiled, and record the new ones. *)
let filter_new_fns ctx (fns : March_tir.Tir.fn_def list) : March_tir.Tir.fn_def list =
  let new_fns = List.filter (fun (f : March_tir.Tir.fn_def) ->
    not (Hashtbl.mem ctx.compiled_fns f.fn_name)) fns in
  List.iter (fun (f : March_tir.Tir.fn_def) ->
    Hashtbl.replace ctx.compiled_fns f.fn_name ()) new_fns;
  new_fns

(** Lower a single-expression module through the TIR pipeline. *)
let lower_module ~type_map (m : March_ast.Ast.module_) =
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus tir in
  let tir = March_tir.Escape.escape_analysis tir in
  tir

let run_expr ctx ~type_map m =
  let n = next_id ctx in
  let tir = lower_module ~type_map m in
  (* The last function in the module is the expression wrapper.
     Extract its body and return type. *)
  let main_fn = List.find (fun (f : March_tir.Tir.fn_def) ->
    f.fn_name = "main") tir.March_tir.Tir.tm_fns in
  let ret_ty = main_fn.fn_ret_ty in
  let support_fns = List.filter (fun (f : March_tir.Tir.fn_def) ->
    f.fn_name <> "main") tir.March_tir.Tir.tm_fns in
  (* Only emit functions not already compiled in a previous fragment.
     The rest are already in the global symbol table via RTLD_GLOBAL. *)
  let new_fns = filter_new_fns ctx support_fns in
  let ir = March_tir.Llvm_emit.emit_repl_expr
    ~n ~ret_ty
    ~prev_globals:ctx.globals
    ~fns:new_fns
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
    | _ ->
      (* Heap-allocated value.
         TODO: call march_value_to_string (via call_ptr_to_ptr) and read the
         resulting march_string bytes back into OCaml for pretty-printing. *)
      let ptr = Jit.call_void_to_ptr fptr in
      Printf.sprintf "#<value at 0x%Lx>" (Int64.of_nativeint ptr)
  in
  (ret_ty, result_str)

(** Distinguish fn vs let at the AST level, not TIR.
    [is_fn_decl] is true when the original REPL input was a DFn. *)
let run_decl ctx ~type_map ~is_fn_decl ~bind_name m =
  let n = next_id ctx in
  let tir = lower_module ~type_map m in
  let all_support_fns = List.filter (fun (f : March_tir.Tir.fn_def) ->
    f.fn_name <> "main") tir.March_tir.Tir.tm_fns in
  (* Split into new (to define) and previously compiled (already in global symbol table) *)
  let user_fns = filter_new_fns ctx all_support_fns in
  if is_fn_decl then begin
    (* Function declaration: emit the function at top level.
       After defunctionalization a single user-defined function may produce
       multiple lifted functions (primary + closure helpers).  Find the primary
       by bind_name, emit helpers first (so their symbols are available via
       RTLD_GLOBAL), then emit the primary.
       NOTE: calling REPL-defined functions from later REPL expressions requires
       proper LLVM `declare` infrastructure in emit_repl_fn/emit_repl_expr
       (tracking fn signatures in ctx, not just data globals).  This is a known
       v1 limitation — function-to-function calls across REPL fragments are
       future work. *)
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
        ~n:hn ~prev_globals:ctx.globals ~types:tir.March_tir.Tir.tm_types
        helper in
      let _h = compile_fragment ctx ir in
      ()
    ) helper_fns;
    (* Emit primary function *)
    let pn = next_id ctx in
    let ir = March_tir.Llvm_emit.emit_repl_fn
      ~n:pn ~prev_globals:ctx.globals ~types:tir.March_tir.Tir.tm_types
      primary_fn in
    let _handle = compile_fragment ctx ir in
    ()
  end else begin
    (* Let binding: find main, extract body, store in global *)
    let main_fn = List.find (fun (f : March_tir.Tir.fn_def) ->
      f.fn_name = "main") tir.March_tir.Tir.tm_fns in
    let ir = March_tir.Llvm_emit.emit_repl_decl
      ~n ~name:bind_name
      ~val_ty:main_fn.fn_ret_ty
      ~prev_globals:ctx.globals
      ~fns:user_fns
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

let cleanup ctx =
  List.iter (fun h -> try Jit.dlclose h with _ -> ()) ctx.handles;
  (* Remove tmp_dir contents *)
  let entries = Sys.readdir ctx.tmp_dir in
  Array.iter (fun f ->
    try Sys.remove (Filename.concat ctx.tmp_dir f) with _ -> ()
  ) entries;
  (try Unix.rmdir ctx.tmp_dir with _ -> ())
