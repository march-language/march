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
  rt_link      : string;  (* macOS: " <runtime.so>" to bind runtime symbols
                             two-level (see compile_fragment_clang); "" on Linux,
                             where flat-namespace resolution is not a problem. *)
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
  global_type_defs : (string, March_tir.Tir.type_def) Hashtbl.t;  (* type name -> TDVariant/TDRecord for display *)
  mutable stdlib_decls : March_ast.Ast.decl list;  (* cached for incremental lowering context *)
  mutable loaded_tir_types : March_tir.Tir.type_def list;  (* TIR type_defs from :load-ed modules, for ctor_info in expression fragments *)
}

let create ~runtime_so ?(clang="clang") () =
  (* Per-process artifact dir.  A single shared "march_jit" dir raced when
     several JIT sessions ran concurrently (dune executes the test runners in
     parallel): one process's cleanup rmdir'd the dir while another's clang
     was still writing repl_<n>.so into it. *)
  let tmp_base = Filename.get_temp_dir_name () in
  let dir_prefix = "march_jit." in
  let tmp_dir = Filename.concat tmp_base
    (dir_prefix ^ string_of_int (Unix.getpid ())) in
  (* Sweep per-pid dirs left by SIGKILL'd sessions (cleanup only runs on
     clean exit): a dir is stale when its pid is no longer alive.
     MARCH_KEEP_LL opts out. *)
  if Sys.getenv_opt "MARCH_KEEP_LL" = None then begin
    try
      Array.iter (fun entry ->
        let plen = String.length dir_prefix in
        if String.length entry > plen && String.sub entry 0 plen = dir_prefix then
          match int_of_string_opt
                  (String.sub entry plen (String.length entry - plen)) with
          | Some pid when pid <> Unix.getpid () ->
            let alive =
              try Unix.kill pid 0; true
              with Unix.Unix_error (Unix.ESRCH, _, _) -> false
                 | Unix.Unix_error _ -> true (* EPERM etc: assume alive *)
            in
            if not alive then begin
              let dir = Filename.concat tmp_base entry in
              (try
                 Array.iter (fun f ->
                   try Sys.remove (Filename.concat dir f) with _ -> ()
                 ) (Sys.readdir dir)
               with _ -> ());
              (try Unix.rmdir dir with _ -> ())
            end
          | _ -> ()
      ) (Sys.readdir tmp_base)
    with _ -> ()
  end;
  (try Unix.mkdir tmp_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  (* Clean artifacts left in our own dir by a prior session in this process
     whose cleanup didn't run (cleanup only runs on clean exit). *)
  if Sys.getenv_opt "MARCH_KEEP_LL" = None then begin
    try
      Array.iter (fun f ->
        try Sys.remove (Filename.concat tmp_dir f) with _ -> ()
      ) (Sys.readdir tmp_dir)
    with _ -> ()
  end;
  (* Load the runtime .so first so its symbols are globally available *)
  let rt_handle = Jit.dlopen runtime_so in
  let undef_flag = if is_macos () then " -undefined dynamic_lookup" else "" in
  (* Only macOS needs the explicit two-level runtime binding; Linux resolves
     RTLD_GLOBAL symbols correctly, so keep its link line unchanged. *)
  let rt_link = if is_macos () then " " ^ Filename.quote runtime_so else "" in
  { runtime_so; clang; tmp_dir; undef_flag; rt_link;
    counter = 0; var_slots = []; next_slot = 0;
    handles = [rt_handle];
    compiled_fns = Hashtbl.create 256;
    global_tir_tys = Hashtbl.create 16;
    global_type_defs = Hashtbl.create 16;
    stdlib_decls = [];
    loaded_tir_types = [] }

let alloc_slot ctx =
  let n = ctx.next_slot in
  ctx.next_slot <- n + 1;
  n

let next_id ctx =
  let n = ctx.counter in
  ctx.counter <- n + 1;
  n

let profile_enabled = Sys.getenv_opt "MARCH_JIT_PROFILE" <> None
let time_phase name f =
  if profile_enabled then begin
    let t0 = Unix.gettimeofday () in
    let r = f () in
    let dt = Unix.gettimeofday () -. t0 in
    Printf.eprintf "[jit-prof] %-20s %6.1fms\n%!" name (dt *. 1000.);
    r
  end else f ()

(* Backend selector — see the plan file for the motivation. Default is
   the clang + dlopen pipeline; set MARCH_JIT_BACKEND=orc to route through
   the in-process LLJIT. Read once at startup so we don't stat env on the
   hot path. *)
let backend_is_orc = Sys.getenv_opt "MARCH_JIT_BACKEND" = Some "orc"

(* Lazy-initialised LLJIT.  Only touched when backend_is_orc is true;
   libLLVM.dylib is loaded on first create(), so non-ORC builds pay no
   startup cost. *)
let orc_instance : Jit_orc.t option ref = ref None
let get_orc () =
  match !orc_instance with
  | Some j -> j
  | None ->
    let j = Jit_orc.create () in
    orc_instance := Some j; j

(* Opaque per-fragment handle used by run_expr / run_decl to look up the
   fragment's exported init / main symbol.  Carries the clang dl_handle
   when the clang backend emitted a fresh .so; in ORC mode there is no
   per-fragment handle — symbols are resolved against the shared LLJIT. *)
type fragment_handle =
  | HClang of Jit.dl_handle
  | HOrc

let lookup_sym (fh : fragment_handle) (sym : string) : nativeint =
  match fh with
  | HClang h -> Jit.dlsym h sym
  | HOrc     -> Jit_orc.lookup (get_orc ()) sym

let compile_fragment_clang ctx (ir : string) : Jit.dl_handle =
  let n = ctx.counter - 1 in
  let ll_path = Filename.concat ctx.tmp_dir
    (Printf.sprintf "repl_%d.ll" n) in
  let so_path = Filename.concat ctx.tmp_dir
    (Printf.sprintf "repl_%d.so" n) in
  let keep_ll = Sys.getenv_opt "MARCH_KEEP_LL" <> None in
  (* When debugging is requested, mirror the IR to disk before compilation so
     the user can inspect the exact bytes we handed clang. The common path
     skips the file I/O entirely and pipes IR directly to clang's stdin. *)
  if keep_ll then begin
    let oc = open_out ll_path in
    output_string oc ir;
    close_out oc
  end;
  (* Compile to .so via stdin.
     -x ir -: read LLVM IR from stdin; avoids the .ll file write round-trip.
     runtime .so as an explicit link input (BEFORE -x ir so it is treated as a
     dylib, not IR): binds the fragment's runtime symbols (march_string_*, …)
     TWO-LEVEL to that exact dylib instead of leaving them to macOS flat-namespace
     -undefined dynamic_lookup resolution — which macOS 15's dyld resolves WRONG
     for the short-string-literal path (see specs/todos JIT miscompile). Prelude
     and prior-fragment symbols are not in the runtime .so, so they still fall to
     dynamic_lookup, preserving incremental compilation.
     -undefined dynamic_lookup (macOS): remaining undefined symbols resolve at
     dlopen time from RTLD_GLOBAL so later fragments can omit already-compiled
     stdlib.  -O0 -fno-lto: fragments are one-shot; no optimization benefit. *)
  let cmd = Printf.sprintf
    "%s -shared -fPIC -O0 -fno-lto%s%s -x ir -o %s - 2>&1"
    ctx.clang ctx.undef_flag ctx.rt_link so_path in
  let t_clang0 = if profile_enabled then Unix.gettimeofday () else 0. in
  let (ic, oc) = Unix.open_process cmd in
  output_string oc ir;
  close_out oc;
  let output = Buffer.create 256 in
  (try while true do Buffer.add_char output (input_char ic) done
   with End_of_file -> ());
  let status = Unix.close_process (ic, oc) in
  if profile_enabled then
    Printf.eprintf "[jit-prof]   clang              %6.1fms\n%!"
      ((Unix.gettimeofday () -. t_clang0) *. 1000.);
  (match status with
   | Unix.WEXITED 0 -> ()
   | _ ->
     (try Sys.remove so_path with _ -> ());
     (* On failure, dump IR to disk so the user can reproduce with clang
        directly. We did not necessarily write it earlier (stdin path). *)
     if not keep_ll then begin
       try
         let oc = open_out ll_path in
         output_string oc ir;
         close_out oc
       with _ -> ()
     end;
     failwith (Printf.sprintf "clang failed (IR preserved at %s): %s"
       ll_path (Buffer.contents output)));
  let t_dlo0 = if profile_enabled then Unix.gettimeofday () else 0. in
  let handle = Jit.dlopen so_path in
  if profile_enabled then
    Printf.eprintf "[jit-prof]   dlopen             %6.1fms\n%!"
      ((Unix.gettimeofday () -. t_dlo0) *. 1000.);
  ctx.handles <- handle :: ctx.handles;
  handle

(* Backend dispatcher. In ORC mode we parse the IR straight into the shared
   LLJIT — no shared object, no dlopen, no per-fragment handle. The counter
   is assumed to already have been advanced (next_id called) by the caller,
   matching the clang path's invariant. *)
let compile_fragment ctx (ir : string) : fragment_handle =
  if backend_is_orc then begin
    let n = ctx.counter - 1 in
    let name = Printf.sprintf "repl_%d" n in
    let t0 = if profile_enabled then Unix.gettimeofday () else 0. in
    Jit_orc.add_ir (get_orc ()) ~ir ~name;
    if profile_enabled then
      Printf.eprintf "[jit-prof]   orc_add_ir         %6.1fms\n%!"
        ((Unix.gettimeofday () -. t0) *. 1000.);
    HOrc
  end else
    HClang (compile_fragment_clang ctx ir)

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
  (* Match the compiled pipeline: bin/main.ml runs Trmc.transform_module
     immediately post-lower (pre-mono), and without it a function behaves
     differently in the REPL than when compiled.  The position matters as much
     as the call — by defun the stdlib's nested `go` helpers are closures
     invoked via ECallPtr, so self-recursion is no longer syntactically visible
     and the transform would silently see nothing.  Gated by the same
     [Trmc.enabled] ref, and idempotent, so re-lowering an already-transformed
     module is a no-op. *)
  let tir = March_tir.Trmc.transform_module tir in
  let iface_methods = March_tir.Lower.get_iface_methods () in
  let tir = March_tir.Mono.monomorphize ~iface_methods tir in
  (* Policy audit — report any Tagged(_, P) violations before defun. *)
  let violations = March_tir.Policy_dce.audit tir in
  List.iter (fun (_fn_name, msg) ->
    Printf.eprintf "Error: %s\n\n" msg
  ) violations;
  let tir = March_tir.Defun.defunctionalize tir in
  (* [~repl:true] must track [Llvm_emit]'s [ctx.repl] exactly (every emission
     path in this file passes [~repl:true]): it is what tells Perceus that a
     capture-free closure is a real per-materialization [march_alloc] here
     rather than the immortal static global [static_closure_ok] gives the
     native build, and therefore needs a callee-side release. *)
  let tir = March_tir.Perceus.perceus ~repl:true ~repl_vars tir in
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

(** Collect free TVars from a type_def's constructor payload signatures,
    preserving first-seen order.  Used to align TCon type-args with TVars
    in payload types for user ADT pretty-printing. *)
let collect_tvars (td : March_tir.Tir.type_def) : string list =
  let open March_tir.Tir in
  let seen = Hashtbl.create 4 in
  let order = ref [] in
  let rec walk = function
    | TVar s ->
      if not (Hashtbl.mem seen s) then begin
        Hashtbl.add seen s ();
        order := s :: !order
      end
    | TCon (_, args) | TTuple args -> List.iter walk args
    | TFn (args, r) -> List.iter walk args; walk r
    | TPtr t -> walk t
    | TRecord fs -> List.iter (fun (_, t) -> walk t) fs
    | TInt | TFloat | TBool | TString | TUnit -> ()
  in
  (match td with
   | TDVariant (_, ctors) ->
     List.iter (fun (_, args) -> List.iter walk args) ctors
   | TDRecord (_, fs) ->
     List.iter (fun (_, t) -> walk t) fs
   | TDClosure _ -> ());
  List.rev !order

let rec subst_ty (bindings : (string * March_tir.Tir.ty) list) (t : March_tir.Tir.ty) : March_tir.Tir.ty =
  let open March_tir.Tir in
  match t with
  | TVar s -> (try List.assoc s bindings with Not_found -> TVar s)
  | TCon (n, args) -> TCon (n, List.map (subst_ty bindings) args)
  | TTuple args -> TTuple (List.map (subst_ty bindings) args)
  | TFn (args, r) -> TFn (List.map (subst_ty bindings) args, subst_ty bindings r)
  | TPtr t -> TPtr (subst_ty bindings t)
  | TRecord fs -> TRecord (List.map (fun (n, t) -> (n, subst_ty bindings t)) fs)
  | TInt | TFloat | TBool | TString | TUnit as t -> t

(** Representation of the variant type [name] as codegen sees it.

    The pretty-printer MUST agree with [Repr] here: an expression fragment is
    emitted with the same type_defs, so a niche/newtype value never reaches
    the printer as a heap cell at all — it arrives as the raw payload word
    (e.g. `X(7)` of `type T = X(Int) | Y` is the tagged integer 15, with no
    cell to read a tag from).  Reading such a word as a pointer prints
    nonsense at best and faults at worst.

    [repr_of_ty] reads a generic type's payload out of the TCon's type args, so
    a NON-generic Option-shaped type (no args) comes back [Boxed]; that is what
    [niche_repr_of_concrete] recovers, exactly as codegen's own decode sites do. *)
let variant_repr ~type_defs (name : string) (args : March_tir.Tir.ty list)
    : March_tir.Repr.repr =
  let defs = Hashtbl.fold (fun _ td acc -> td :: acc) type_defs [] in
  match March_tir.Repr.repr_of_ty defs (March_tir.Tir.TCon (name, args)) with
  | March_tir.Repr.Boxed when args = [] ->
    (match March_tir.Repr.niche_repr_of_concrete defs name with
     | Some r -> r
     | None -> March_tir.Repr.Boxed)
  (* Abstract-arg niche path, mirroring [Llvm_case]'s [effective_repr]: a
     niche-shaped type applied to a still-abstract argument (e.g. a bare
     `Nothing2` whose element type never got resolved) is Boxed by
     [repr_of_ty] — [niche_payload_ok] is false for a TVar — but codegen
     emits Niche anyway, under the erased convention. *)
  | March_tir.Repr.Boxed
    when args <> []
      && List.exists (function March_tir.Tir.TVar _ -> true | _ -> false) args
      && March_tir.Repr.is_niche_shaped defs name ->
    March_tir.Repr.Niche { payload = March_tir.Tir.TVar "_"; tagged = false }
  | r -> r

(** Split an Option-shaped variant's ctors into (nullary name, single name). *)
let niche_ctor_names (ctors : (string * March_tir.Tir.ty list) list) =
  match ctors with
  | [ (n, []); (s, [_]) ] -> Some (n, s)
  | [ (s, [_]); (n, []) ] -> Some (n, s)
  | _ -> None

(** A constructor payload slot is low-bit tagged exactly when the DECLARED
    field type is erased (a TVar): those slots are `ptr`-typed, so a scalar
    stored there is coerced to (v<<1)|1.  A field declared at a concrete
    scalar type gets a real i64/double slot and is stored raw.  The decision
    must be made on the declaration's own type, BEFORE substituting the
    TCon's type args in — the substituted type is what the value means, not
    how it is stored. *)
let field_is_tagged (declared : March_tir.Tir.ty) =
  match declared with March_tir.Tir.TVar _ -> true | _ -> false

(** Pretty-print a March heap value given its TIR type.
    [type_defs] provides user-declared TDVariant/TDRecord lookups for
    non-builtin TCon names.  Recursion is bounded to depth 64. *)
let rec pp_heap_value ?(depth=0) ~type_defs (ty : March_tir.Tir.ty) (ptr : nativeint) : string =
  if depth > 64 then "#<...>"
  else
  let open March_tir.Tir in
  match ty with
  (* Niche / newtype types are NOT heap cells: [ptr] is the raw payload word
     (or 0 for a niche's nullary ctor), so these must be decoded before the
     null guard and before any tag read. *)
  | TCon (name, args) when (match Hashtbl.find_opt type_defs name with
                            | Some (TDVariant _) -> true | _ -> false)
                        && (match variant_repr ~type_defs name args with
                            | March_tir.Repr.Boxed -> false | _ -> true) ->
    let ctors = match Hashtbl.find type_defs name with
      | TDVariant (_, cs) -> cs | _ -> [] in
    let bindings =
      try List.combine (collect_tvars (Hashtbl.find type_defs name)) args
      with Invalid_argument _ -> [] in
    (match variant_repr ~type_defs name args with
     | March_tir.Repr.Niche { payload; tagged } ->
       (match niche_ctor_names ctors with
        | None -> Printf.sprintf "#<niche:%nd>" ptr
        | Some (nullary, single) ->
          if ptr = Nativeint.zero then nullary
          else Printf.sprintf "%s(%s)" single
                 (pp_word ~depth ~type_defs ~tagged (subst_ty bindings payload) ptr))
     | March_tir.Repr.Newtype payload ->
       (match ctors with
        | [ (ctor, [ declared ]) ] ->
          Printf.sprintf "%s(%s)" ctor
            (pp_word ~depth ~type_defs ~tagged:(field_is_tagged declared)
               (subst_ty bindings payload) ptr)
        | _ -> Printf.sprintf "#<newtype:%nd>" ptr)
     (* Unreachable: the guard above already excluded Boxed.  Rendered rather
        than asserted — a printer must never take the REPL down. *)
     | March_tir.Repr.Boxed -> Printf.sprintf "#<%s:%nd>" name ptr)
  | _ ->
  if ptr = Nativeint.zero then "#<null>"
  else
  match ty with
  | TString ->
    (* march_string layout: {rc:i64, tag:i32, pad:i32, len:i64, data:char[]} *)
    Printf.sprintf "%S" (Jit.read_march_string ptr)
  | TCon ("List", [elem_ty]) ->
    pp_list ~depth ~type_defs elem_ty ptr
  | TCon ("Option", [inner_ty]) ->
    let tag = heap_tag ptr in
    if tag = 0 then "None"
    else
      let v = pp_field ~depth ~type_defs ~tagged:true inner_ty ptr 0 in
      Printf.sprintf "Some(%s)" v
  | TCon ("Result", [ok_ty; err_ty]) ->
    let tag = heap_tag ptr in
    if tag = 0 then Printf.sprintf "Ok(%s)" (pp_field ~depth ~type_defs ~tagged:true ok_ty ptr 0)
    else         Printf.sprintf "Err(%s)" (pp_field ~depth ~type_defs ~tagged:true err_ty ptr 0)
  | TTuple tys ->
    (* Tuple fields use the uniform slot convention: scalars are low-bit
       tagged (matching ETuple's coerce-to-ptr store), so untag scalar views. *)
    let fields = List.mapi (fun i ty -> pp_field ~depth ~type_defs ~tagged:true ty ptr i) tys in
    Printf.sprintf "(%s)" (String.concat ", " fields)
  | TCon (name, args) when Hashtbl.mem type_defs name ->
    let td = Hashtbl.find type_defs name in
    (match td with
     | TDVariant (_, ctors) ->
       let tag = heap_tag ptr in
       (match List.nth_opt ctors tag with
        | None -> Printf.sprintf "#<tag:%d>" tag
        | Some (ctor_name, payload_tys) ->
          let tvars = collect_tvars td in
          let bindings =
            try List.combine tvars args
            with Invalid_argument _ -> []
          in
          if payload_tys = [] then ctor_name
          else
            let fields = List.mapi (fun i declared ->
              pp_field ~depth ~type_defs ~tagged:(field_is_tagged declared)
                (subst_ty bindings declared) ptr i
            ) payload_tys in
            Printf.sprintf "%s(%s)" ctor_name (String.concat ", " fields))
     | TDRecord (_, fs) ->
       let fields = List.mapi (fun i (fname, fty) ->
         (* Record scalar fields are stored UNTAGGED (same layout as tuples),
            not payload-tagged like ADT constructor args. *)
         Printf.sprintf "%s: %s" fname
           (pp_field ~depth ~type_defs ~tagged:false fty ptr i)
       ) fs in
       Printf.sprintf "{%s}" (String.concat ", " fields)
     | TDClosure _ -> Printf.sprintf "#<tag:%d>" (heap_tag ptr))
  | TRecord fs ->
    (* Structural record — sorted alphabetically by Lower.convert_ty/lower_ty.
       Scalar fields are stored UNTAGGED (like tuple slots), not as
       payload-tagged ADT fields. *)
    let fields = List.mapi (fun i (fname, fty) ->
      Printf.sprintf "%s: %s" fname
        (pp_field ~depth ~type_defs ~tagged:false fty ptr i)
    ) fs in
    Printf.sprintf "{%s}" (String.concat ", " fields)
  | _ ->
    (* Unknown heap type: show tag for basic orientation; guard null *)
    if ptr = Nativeint.zero then "#<null>"
    else Printf.sprintf "#<tag:%d>" (heap_tag ptr)

and pp_list ?(depth=0) ~type_defs elem_ty (ptr : nativeint) : string =
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
    (* Cons payload scalars ARE tagged — pass tagged:true. *)
    Buffer.add_string buf (pp_field ~depth ~type_defs ~tagged:true elem_ty !cur 0);
    cur := field_ptr !cur 1;  (* tail is field 1 of Cons *)
    incr count
  done;
  if !count = max_elems then Buffer.add_string buf ", ...";
  Buffer.add_char buf ']';
  Buffer.contents buf

and pp_field ?(depth=0) ~type_defs ~tagged (ty : March_tir.Tir.ty) (ptr : nativeint) (i : int) : string =
  let open March_tir.Tir in
  match ty with
  | TFloat ->
    (* Floats are stored as raw double bits via bitcast — no tag bit, and the
       bit pattern is not a meaningful nativeint, so read the slot directly. *)
    Printf.sprintf "%g" (Int64.float_of_bits (field_i64 ptr i))
  | TInt | TBool | TUnit ->
    pp_word ~depth ~type_defs ~tagged ty (Int64.to_nativeint (field_i64 ptr i))
  | _ -> pp_word ~depth ~type_defs ~tagged ty (field_ptr ptr i)

(** Render a value held in a single machine word — a constructor field just
    read out of a cell, or the whole value of a niche/newtype type.
    [tagged] says the word holds a low-bit-tagged scalar (value<<1)|1. *)
and pp_word ?(depth=0) ~type_defs ~tagged (ty : March_tir.Tir.ty) (w : nativeint) : string =
  let open March_tir.Tir in
  let scalar () =
    let v = Int64.of_nativeint w in
    if tagged then Int64.shift_right_logical v 1 else v
  in
  match ty with
  | TInt  -> Int64.to_string (scalar ())
  | TBool -> if scalar () = 0L then "false" else "true"
  | TUnit -> "()"
  | TFloat -> Printf.sprintf "%g" (Int64.float_of_bits (Int64.of_nativeint w))
  | TVar _ ->
    (* Erased slot: a scalar is low-bit tagged, a heap value is an aligned
       pointer.  Decide from the word itself — dereferencing a tagged scalar
       as a cell would read unmapped memory. *)
    if Nativeint.logand w 1n = 1n then
      Int64.to_string (Int64.shift_right_logical (Int64.of_nativeint w) 1)
    else if w = Nativeint.zero then "null"
    else Printf.sprintf "#<tag:%d>" (heap_tag w)
  | _ ->
    if w = Nativeint.zero then "null"
    else pp_heap_value ~depth:(depth + 1) ~type_defs ty w

(** True when a value of [ty] is NOT a heap pointer but the raw payload word
    of a niche/newtype representation — the two cases where the "small word =
    plain integer" fallback in [run_expr] would print `15` instead of `X(7)`,
    and where a raw 0 means the nullary constructor rather than a null value. *)
let is_raw_word_ty ~type_defs (ty : March_tir.Tir.ty) =
  match ty with
  | March_tir.Tir.TCon (name, args) ->
    (match Hashtbl.find_opt type_defs name with
     | Some (March_tir.Tir.TDVariant _) ->
       (match variant_repr ~type_defs name args with
        | March_tir.Repr.Boxed -> false
        | _ -> true)
     | _ -> false)
  | _ -> false

(* ── run_expr ──────────────────────────────────────────────────────── *)

(** Register user-declared types into [ctx.global_type_defs] so the heap
    pretty-printer can render user ADTs / records as [Ctor(...)] / [{f: v}]
    instead of [#<tag:N>]. *)
let register_type_defs ctx (types : March_tir.Tir.type_def list) =
  List.iter (fun td ->
    match td with
    | March_tir.Tir.TDVariant (name, _) ->
      Hashtbl.replace ctx.global_type_defs name td
    | March_tir.Tir.TDRecord (name, _) ->
      Hashtbl.replace ctx.global_type_defs name td
    | March_tir.Tir.TDClosure _ -> ()
  ) types

let type_def_name (td : March_tir.Tir.type_def) =
  match td with
  | March_tir.Tir.TDVariant (n, _) | March_tir.Tir.TDRecord (n, _)
  | March_tir.Tir.TDClosure (n, _) -> n

(** Register a user type declaration from the REPL so subsequent expressions
    can pretty-print values of that type AND construct them with the right
    constructor tags.  DType decls otherwise never reach the JIT — the REPL
    loop evaluates them in the tree-walking interpreter and sends only
    DFn/DLet/ReplExpr through run_decl/run_expr.

    Three registrations, all required:
    - [register_type_defs] feeds [ctx.global_type_defs], which the heap
      pretty-printer reads to turn a tag back into a constructor name.
    - [ctx.loaded_tir_types] is passed as the [~types] of every subsequent
      expression fragment, and codegen's [build_ctor_info] numbers constructor
      tags from exactly that list.  Without it the fragment's [ctor_entry]
      lookup misses and falls back to its `ce_tag = 0` default, so EVERY
      nullary constructor is allocated with tag 0 and prints as the type's
      first variant (`Green` and `Blue` both showing as `Red`).
    - [ctx.stdlib_decls] is the lowering context, so [lower_module] knows
      which type each bare constructor belongs to and emits the type-qualified
      "Color.Green" key that [ctor_info] is keyed by.

    Re-declaring a type at the prompt replaces the previous registration
    rather than appending: [build_ctor_info] is first-wins, so a stale entry
    would keep handing out the OLD variant numbering. *)
let register_user_type_decl ctx (d : March_ast.Ast.decl) =
  match d with
  | March_ast.Ast.DType (_, name, params, td, _)
  | March_ast.Ast.DAlwaysLinearType (_, name, params, td, _) ->
    (match March_tir.Lower.lower_type_def name params td with
     | Some td' ->
       register_type_defs ctx [td'];
       ctx.loaded_tir_types <-
         List.filter (fun t -> type_def_name t <> type_def_name td')
           ctx.loaded_tir_types
         @ [td'];
       ctx.stdlib_decls <-
         List.filter (fun (d0 : March_ast.Ast.decl) ->
           match d0 with
           | March_ast.Ast.DType (_, n, _, _, _)
           | March_ast.Ast.DAlwaysLinearType (_, n, _, _, _) ->
             n.March_ast.Ast.txt <> name.March_ast.Ast.txt
           | _ -> true) ctx.stdlib_decls
         @ [d]
     | None -> ())
  | _ -> ()

(** Compile a :load-ed DMod's functions into the JIT dylib so ORC can resolve
    module-qualified names (e.g. Counter.create) in subsequent fragments.
    [tc_env] must be the type environment *before* the DMod was added (i.e.
    the env passed to check_decl that produced the DMod's type bindings).
    Silently ignores non-DMod decls. *)
let register_module_decl ctx ~tc_env (d : March_ast.Ast.decl) =
  match d with
  | March_ast.Ast.DMod _ ->
    (* Append to stdlib_context so subsequent REPL expression lowerings can
       find this module's type definitions and assign correct variant tags. *)
    ctx.stdlib_decls <- ctx.stdlib_decls @ [d];
    let s = March_ast.Ast.dummy_span in
    let m : March_ast.Ast.module_ = {
      March_ast.Ast.mod_name = { txt = "Repl"; span = s };
      mod_decls = [d]
    } in
    let errors = March_errors.Errors.create () in
    let env = { tc_env with March_typecheck.Typecheck.errors;
      (* Reset per-call — this env is reused across the whole REPL/JIT
         session, so without this [refs] would accumulate unboundedly
         across every fragment typed at the REPL (nothing reads it here);
         see [Typecheck_cache.derive]'s identical reset for the LSP's
         analogous reused env. *)
      refs = ref []; current_decl = ref "" } in
    (try
      let (_, type_map) = March_typecheck.Typecheck.check_module_with_env env m in
      let tir = lower_module ~type_map ~stdlib_context:ctx.stdlib_decls m in
      register_type_defs ctx tir.March_tir.Tir.tm_types;
      ctx.loaded_tir_types <- ctx.loaded_tir_types @ tir.March_tir.Tir.tm_types;
      let (new_fns, extern_fns) = partition_fns ctx tir.March_tir.Tir.tm_fns in
      if new_fns <> [] then begin
        ignore (next_id ctx);
        let ir = March_tir.Llvm_emit.emit_fns_fragment
          ~types:tir.March_tir.Tir.tm_types ~fns:new_fns ~extern_fns ~repl:true () in
        (try
          ignore (compile_fragment ctx ir);
          mark_compiled_fns ctx new_fns
        with Failure msg ->
          Printf.eprintf "jit: module compile failed: %s\n%!" msg)
      end
    with exn ->
      Printf.eprintf "jit: module registration failed: %s\n%!" (Printexc.to_string exn))
  | _ -> ()

let run_expr ctx ~tc_env m =
  (* Typecheck and lower BEFORE advancing the counter so a failure leaves no gap. *)
  let repl_vars = List.map (fun (bare, _, _) -> bare) ctx.var_slots in
  let errors = March_errors.Errors.create () in
  let env = { tc_env with March_typecheck.Typecheck.errors;
      (* Reset per-call — this env is reused across the whole REPL/JIT
         session, so without this [refs] would accumulate unboundedly
         across every fragment typed at the REPL (nothing reads it here);
         see [Typecheck_cache.derive]'s identical reset for the LSP's
         analogous reused env. *)
      refs = ref []; current_decl = ref "" } in
  let (_, type_map) = time_phase "typecheck"
    (fun () -> March_typecheck.Typecheck.check_module_with_env env m) in
  let tir = time_phase "lower+mono+opt"
    (fun () -> lower_module ~type_map ~stdlib_context:ctx.stdlib_decls ~repl_vars m) in
  register_type_defs ctx tir.March_tir.Tir.tm_types;
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
  let ir = time_phase "emit_ir" (fun () ->
    March_tir.Llvm_emit.emit_repl_expr
      ~n ~ret_ty
      ~prev_slots:(prev_slots_of ctx)
      ~fns:new_fns
      ~extern_fns
      ~store_as_slot:(Some v_slot)
      ~types:(ctx.loaded_tir_types @ tir.March_tir.Tir.tm_types)
      main_fn.fn_body) in
  let handle = time_phase "clang+dlopen"
    (fun () -> compile_fragment ctx ir) in
  mark_compiled_fns ctx new_fns;
  let sym_name = Printf.sprintf "repl_%d" n in
  let fptr = lookup_sym handle sym_name in
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
      (* Unresolved type var — try to recover the actual type.  Walk the fn body
         into the tail position, recursing through ELet, ESeq, and ECase branches.
         For an EAtom tail, prefer the variable's own v_ty (already concrete
         post-mono); fall back to global_tir_tys by name.  For scalar types read
         as int; for heap types call as ptr and pretty-print. *)
      let open March_tir.Tir in
      let rec find_retty body = match body with
        | EAtom (AVar v) ->
          (match v.v_ty with
           | TVar _ -> Hashtbl.find_opt ctx.global_tir_tys v.v_name
           | t -> Some t)
        | ESeq (_, e2) -> find_retty e2
        | ELet (_, _, e2) -> find_retty e2
        | ECase (_, branches, default) ->
          let cands = List.filter_map (fun (b : branch) -> find_retty b.br_body) branches in
          let cands = match default with
            | Some d -> (match find_retty d with Some t -> t :: cands | None -> cands)
            | None -> cands
          in
          (match cands with t :: _ -> Some t | [] -> None)
        | _ -> None
      in
      let stored_ty = find_retty main_fn.fn_body in
      (match stored_ty with
       | Some TBool ->
         let v = Jit.call_void_to_int fptr in
         if v = 0L then "false" else "true"
       | Some TInt ->
         Int64.to_string (Jit.call_void_to_int fptr)
       | Some ty ->
         let ptr = Jit.call_void_to_ptr fptr in
         if is_raw_word_ty ~type_defs:ctx.global_type_defs ty then
           pp_heap_value ~type_defs:ctx.global_type_defs ty ptr
         else if ptr = Nativeint.zero then "null"
         else pp_heap_value ~type_defs:ctx.global_type_defs ty ptr
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
    | ty when is_raw_word_ty ~type_defs:ctx.global_type_defs ty ->
      (* Niche/newtype: the returned word IS the value (0 = nullary ctor),
         so neither the null check nor the small-integer fallback applies. *)
      pp_heap_value ~type_defs:ctx.global_type_defs ty
        (Jit.call_void_to_ptr fptr)
    | ty ->
      let ptr = Jit.call_void_to_ptr fptr in
      if ptr = Nativeint.zero then "null"
      else
        let raw = Int64.of_nativeint ptr in
        if Int64.compare raw 0x100000000L < 0 && Int64.compare raw 0L >= 0 then
          Int64.to_string raw
        else
          pp_heap_value ~type_defs:ctx.global_type_defs ty ptr
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
  let env = { tc_env with March_typecheck.Typecheck.errors;
      (* Reset per-call — this env is reused across the whole REPL/JIT
         session, so without this [refs] would accumulate unboundedly
         across every fragment typed at the REPL (nothing reads it here);
         see [Typecheck_cache.derive]'s identical reset for the LSP's
         analogous reused env. *)
      refs = ref []; current_decl = ref "" } in
  let (_, type_map) = March_typecheck.Typecheck.check_module_with_env env m in
  let tir = lower_module ~type_map ~stdlib_context:ctx.stdlib_decls ~repl_vars m in
  register_type_defs ctx tir.March_tir.Tir.tm_types;
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
        ~types:(ctx.loaded_tir_types @ tir.March_tir.Tir.tm_types) ~fns:helper_fns ~extern_fns ~repl:true () in
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
      ~extern_fns:(extern_fns @ helper_fns) ~types:(ctx.loaded_tir_types @ tir.March_tir.Tir.tm_types)
      primary_fn in
    let handle = compile_fragment ctx ir in
    mark_compiled_fns ctx [primary_fn];
    let init_name = Printf.sprintf "repl_%d_init" pn in
    let fptr = lookup_sym handle init_name in
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
      ~types:(ctx.loaded_tir_types @ tir.March_tir.Tir.tm_types)
      main_fn.fn_body in
    let handle = compile_fragment ctx ir in
    mark_compiled_fns ctx user_fns;
    let init_name = Printf.sprintf "repl_%d_init" n in
    let fptr = lookup_sym handle init_name in
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
    ("stdlib_prelude_O1_tln_" ^ short_hash ^ ".so") in
  let names_path = Filename.concat cache_dir
    ("stdlib_prelude_O1_tln_" ^ short_hash ^ ".names") in
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
          ~types:tir.March_tir.Tir.tm_types ~fns:stdlib_fns ~repl:true () in
        let n = next_id ctx in
        let ll_path = Filename.concat ctx.tmp_dir
          (Printf.sprintf "stdlib_prelude_%d.ll" n) in
        let oc = open_out ll_path in
        output_string oc ir;
        close_out oc;
        (* Compile to a pid-suffixed temp and rename into place below: the
           cache dir is shared across concurrent sessions, and dlopen of a
           half-written .so crashes or hangs the reader. *)
        let so_tmp = Printf.sprintf "%s.%d.tmp" so_path (Unix.getpid ()) in
        (* Link the prelude against the runtime .so explicitly so its calls into
           the runtime (e.g. Path.is_absolute -> String.starts_with ->
           march_string_starts_with, and every string-literal construction via
           march_string_lit_static) bind TWO-LEVEL to that dylib rather than via
           macOS flat-namespace -undefined dynamic_lookup, which macOS 15's dyld
           resolves WRONG for the short-literal path (specs/todos JIT miscompile).
           dynamic_lookup stays for any symbol not defined in the runtime .so. *)
        let cmd = Printf.sprintf "%s -shared -fPIC -O1%s%s -o %s %s 2>&1"
          ctx.clang ctx.undef_flag ctx.rt_link so_tmp ll_path in
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
              the counter and avoid UID collisions with prelude functions.
              Written to a temp and renamed BEFORE the .so is renamed: the
              cache-hit check requires both files, so publishing the .so
              last guarantees no reader ever pairs it with a partial
              .names file. *)
           (try
             let names_tmp =
               Printf.sprintf "%s.%d.tmp" names_path (Unix.getpid ()) in
             let nc = open_out names_tmp in
             Fun.protect ~finally:(fun () -> close_out_noerr nc) (fun () ->
               List.iter (fun (f : March_tir.Tir.fn_def) ->
                 output_string nc (f.fn_name ^ "\n")) stdlib_fns;
               output_string nc
                 (Printf.sprintf "lambda_counter=%d\n"
                    (March_tir.Defun.get_lambda_counter ())));
             Sys.rename names_tmp names_path
           with _ -> ());
           (* Publish the .so atomically; fall back to loading the temp
              directly if the rename is refused. *)
           let load_path =
             (try Sys.rename so_tmp so_path; so_path
              with Sys_error _ -> so_tmp) in
           (* Only mark functions as compiled if the .so was actually loaded.
              If we mark them before dlopen, future fragments would declare them
              as extern and then fail at link time with "symbol not found". *)
           (try
             let handle = Jit.dlopen load_path in
             ctx.handles <- handle :: ctx.handles;
             List.iter (fun (f : March_tir.Tir.fn_def) ->
               Hashtbl.replace ctx.compiled_fns f.fn_name ()
             ) stdlib_fns
           with exn ->
             Printf.eprintf "march JIT: stdlib .so dlopen failed (%s)\n%!"
               (Printexc.to_string exn))
         | _ ->
           (try Sys.remove so_tmp with _ -> ());
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
    (* Remove tmp_dir contents.  Never raise: cleanup runs inside exception
       handlers, and a Sys_error here (dir already gone) would mask the
       original exception. *)
    (try
       Array.iter (fun f ->
         try Sys.remove (Filename.concat ctx.tmp_dir f) with _ -> ()
       ) (Sys.readdir ctx.tmp_dir)
     with _ -> ());
    (try Unix.rmdir ctx.tmp_dir with _ -> ())
  end
