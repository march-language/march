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
  (* `$clo_wrap` trampolines DEFINED by a prior fragment of this session that
     ACTUALLY COMPILED.  Sibling of [compiled_fns] in every respect, including
     its commit discipline (see [commit_wraps]): every fragment of one session
     is materialized into a single symbol namespace, so a symbol emitted twice
     is a duplicate definition.  Codegen's own [emitted_wraps] table is
     per-FRAGMENT and cannot see across that boundary, so a second fragment
     using the same top-level fn as a first-class value re-defined
     `@<fn>$clo_wrap` — ORC's shared JITDylib rejects that outright
     ("duplicate definition of symbol"), while clang's per-.so flat namespace
     happened to tolerate it.  Reached by the emitters through
     [~session_wraps]: the first fragment to need a wrapper defines it, later
     ones emit a `declare`.  Lives on [t] (never global) because a NEW session
     gets a new dylib namespace in which none of these symbols exist. *)
  wrap_defined : (string, unit) Hashtbl.t;
  (* bind_name -> Digest of the declaration's marshaled AST, recorded when a
     REPL-typed `fn` compiles successfully (run_decl ~is_fn_decl:true only —
     stdlib-prelude and :load fns are compiled elsewhere and have no entry).
     Distinguishes a :reset scroll-replay of the identical cell (same digest
     → skip, closure slot still valid) from a genuine REDEFINITION (digest
     differs → recompile and rebind the slot).  Each REPL input is parsed
     from its own fresh [Lexing.from_string], so identical source text
     yields a byte-identical marshaled AST. *)
  fn_fingerprints : (string, string) Hashtbl.t;
  global_tir_tys : (string, March_tir.Tir.ty) Hashtbl.t;  (* bare_name -> TIR type, for display *)
  global_type_defs : (string, March_tir.Tir.type_def) Hashtbl.t;  (* type name -> TDVariant/TDRecord for display *)
  mutable stdlib_decls : March_ast.Ast.decl list;  (* cached for incremental lowering context *)
  mutable loaded_tir_types : March_tir.Tir.type_def list;  (* TIR type_defs from :load-ed modules, for ctor_info in expression fragments *)
  (* Per-session LLJIT (ORC backend only; [None] under clang, or before the
     first fragment if pre-warm failed).  This is deliberately NOT a
     module-level global: a process that creates several sessions (the test
     suites do; an embedder would) would otherwise share one JITDylib, and the
     second session's stdlib fragment would collide with the first's
     ("duplicate definition of symbol '_Eq$Int.eq'"), or — worse — silently
     resolve a stale definition left behind by a torn-down session.  One LLJIT
     per session mirrors the clang backend's natural per-session semantics
     (per-fragment .so + per-session dl handles closed by [cleanup]). *)
  mutable orc : Jit_orc.t option;
}

(* Backend selector — see the plan file for the motivation.
   Resolution order: MARCH_JIT_BACKEND=clang|orc wins; otherwise ORC if
   libLLVM is present (measured 2026-08-23: 0.4-1 ms/fragment vs 210-290 ms
   for clang + dlopen), else clang.

   Resolution is LAZY (computed on first use, not at module init) so that
   non-JIT entry points (e.g. `march --compile`) never call [Jit_orc.available]
   and never dlopen libLLVM. Cached after the first call; tests can override
   via [set_backend_for_tests].

   Defined ABOVE [create] (moved from its original position further down this
   file) so that [create] can pre-warm the LLJIT at the end of construction —
   see the call to [get_orc t] there. *)
type backend = [ `Clang | `Orc ]

let backend : backend option ref = ref None

let resolve_backend () =
  match !backend with
  | Some b -> b
  | None ->
    let b =
      match Sys.getenv_opt "MARCH_JIT_BACKEND" with
      | Some "orc" -> `Orc
      | Some "clang" -> `Clang
      | Some _ -> `Clang (* unrecognized value: fall back to clang, as before *)
      | None -> if Jit_orc.available () then `Orc else `Clang
    in
    backend := Some b;
    b

let current_backend () = resolve_backend ()
let set_backend_for_tests b = backend := Some b
let backend_is_orc () = resolve_backend () = `Orc

(* Lazy-initialised, PER-SESSION LLJIT.  Only touched when backend_is_orc ()
   is true; libLLVM.dylib is loaded (process-wide, RTLD_GLOBAL) on the first
   Jit_orc.create in the process, so non-ORC builds pay no startup cost.
   Cached on the session record so each [t] owns exactly one LLJIT, disposed
   by [cleanup]. *)
let get_orc ctx =
  match ctx.orc with
  | Some j -> j
  | None ->
    let j = Jit_orc.create () in
    ctx.orc <- Some j; j

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
  let t = { runtime_so; clang; tmp_dir; undef_flag; rt_link;
    counter = 0; var_slots = []; next_slot = 0;
    handles = [rt_handle];
    compiled_fns = Hashtbl.create 256;
    wrap_defined = Hashtbl.create 64;
    fn_fingerprints = Hashtbl.create 64;
    global_tir_tys = Hashtbl.create 16;
    global_type_defs = Hashtbl.create 16;
    stdlib_decls = [];
    loaded_tir_types = [];
    orc = None } in
  (* Pre-warm this session's LLJIT so its one-time libLLVM-load + JIT-target-machine
     setup cost (~80-90 ms, previously paid on the FIRST REPL fragment) happens
     here at startup instead, overlapping with the rest of [create]'s work.
     Only touches [backend_is_orc ()] — defined below, referencing this
     module's [resolve_backend] — which is safe here because [create] is only
     reached from REPL/JIT entry points (bin/main.ml's `repl`/`warm-cache`/
     no-args-REPL branches and test helpers), never from `march --compile`,
     so lazily dlopen-ing libLLVM at this point never affects the compile path.

     Best-effort: [Jit_orc.create] can still raise even when [available ()]
     returned true (e.g. an ABI-mismatched or partially-broken libLLVM whose
     dlopen succeeds but whose LLJIT construction fails). Before pre-warm
     existed, that failure surfaced lazily on the FIRST fragment, inside
     repl.ml's per-expression `try ... with _ -> eval_via_interp ()`
     fallback — a graceful degrade to the interpreter, not a crash. Swallow
     the exception here so [create] can't kill REPL startup; on failure
     [t.orc] stays [None] and the first fragment's own [get_orc ctx]
     call retries construction and hits that same pre-existing fallback,
     preserving the pre-change failure surface exactly. *)
  if backend_is_orc () then (try ignore (get_orc t) with _ -> ());
  t

let alloc_slot ctx =
  let n = ctx.next_slot in
  ctx.next_slot <- n + 1;
  n

let next_id ctx =
  let n = ctx.counter in
  ctx.counter <- n + 1;
  n

(* See the .mli — test-only observability for the replay skip fast path. *)
let fragment_count ctx = ctx.counter

let profile_enabled = Sys.getenv_opt "MARCH_JIT_PROFILE" <> None
let time_phase name f =
  if profile_enabled then begin
    let t0 = Unix.gettimeofday () in
    let r = f () in
    let dt = Unix.gettimeofday () -. t0 in
    Printf.eprintf "[jit-prof] %-20s %6.1fms\n%!" name (dt *. 1000.);
    r
  end else f ()

(* Opaque per-fragment handle used by run_expr / run_decl to look up the
   fragment's exported init / main symbol.  Carries the clang dl_handle
   when the clang backend emitted a fresh .so; in ORC mode there is no
   per-fragment handle — symbols are resolved against the shared LLJIT. *)
type fragment_handle =
  | HClang of Jit.dl_handle
  | HOrc

(* Takes [ctx] because the ORC branch resolves against THIS session's LLJIT
   (see the [orc] field on [t]) — there is no process-wide instance. *)
let lookup_sym ctx (fh : fragment_handle) (sym : string) : nativeint =
  match fh with
  | HClang h -> Jit.dlsym h sym
  | HOrc     -> Jit_orc.lookup (get_orc ctx) sym

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

(* Backend dispatcher. In ORC mode we parse the IR straight into the session's
   LLJIT — no shared object, no dlopen, no per-fragment handle. The counter
   is assumed to already have been advanced (next_id called) by the caller,
   matching the clang path's invariant. *)
let compile_fragment ctx (ir : string) : fragment_handle =
  if backend_is_orc () then begin
    let n = ctx.counter - 1 in
    let name = Printf.sprintf "repl_%d" n in
    let t0 = if profile_enabled then Unix.gettimeofday () else 0. in
    Jit_orc.add_ir (get_orc ctx) ~ir ~name;
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

(** Fresh per-fragment `$clo_wrap` bookkeeping to hand to an emit entry point:
    the session's committed definitions to read, plus an empty pending set for
    this fragment's own [`Define] decisions.  Pure — nothing on [ctx] changes
    until [commit_wraps]. *)
let fresh_wrap_state ctx : March_tir.Llvm_emit.session_wraps =
  { sw_defined = ctx.wrap_defined; sw_pending = Hashtbl.create 8 }

(** Promote a fragment's pending `$clo_wrap` definitions into the session.

    EXACTLY the same discipline as [mark_compiled_fns], and it must be called in
    exactly the same places: AFTER [compile_fragment] + dlopen succeed.  A
    fragment that emitted a wrapper and then failed to compile materialized
    NOTHING, and the REPL keeps going (the failure is printed, not fatal) — so
    recording it at emission time would make the NEXT fragment emit a `declare`
    against a symbol that does not exist, turning a recoverable compile error
    into an unresolved-symbol failure, in a spot where the pre-dedupe code
    recovered by simply redefining the wrapper.  On the failure path the caller
    drops the state: it is a local value, so there is nothing to roll back. *)
let commit_wraps ctx (sw : March_tir.Llvm_emit.session_wraps) =
  Hashtbl.iter (fun k () -> Hashtbl.replace ctx.wrap_defined k ()) sw.sw_pending
module SS = Set.Make (String)

(** Rename every reference to the top-level fn [old_name] to [new_name]
    across a fragment's fn_defs (used when REDEFINING a REPL fn: the new
    version must be emitted under a session-unique symbol so it can't
    collide with the earlier fragment's definition — a hard duplicate-
    definition error in the ORC backend's single JITDylib, and a latent
    flat-namespace shadowing hazard under clang+dlopen).

    Capture-avoiding: a locally bound [old_name] (param, let, case binder,
    letrec) shadows the top-level fn, so references under such a binder are
    left alone.  Both [EApp] heads (direct calls, incl. self-recursion) and
    [AVar] atoms (the fn taken as a first-class value — emit_atom's top-fns
    wrap path) are renamed; [ADefRef]/literals are untouched.  Runs post-
    defun, so helper lambdas are separate fn_defs in the same list and get
    the same treatment. *)
let rename_top_fn_refs ~old_name ~new_name
    (fns : March_tir.Tir.fn_def list) : March_tir.Tir.fn_def list =
  let open March_tir.Tir in
  let rename_var bound (v : var) =
    if v.v_name = old_name && not (SS.mem old_name bound)
    then { v with v_name = new_name } else v
  in
  let rename_atom bound = function
    | AVar v -> AVar (rename_var bound v)
    | (ADefRef _ | ALit _) as a -> a
  in
  let bind bound (v : var) = SS.add v.v_name bound in
  let rec go bound e =
    let ra = rename_atom bound in
    match e with
    | EAtom a -> EAtom (ra a)
    | EApp (v, args) -> EApp (rename_var bound v, List.map ra args)
    | ECallPtr (f, args) -> ECallPtr (ra f, List.map ra args)
    | ELet (v, e1, e2) -> ELet (v, go bound e1, go (bind bound v) e2)
    | ELetRec (lfns, e2) ->
      (* The letrec's own names shadow throughout (bodies and continuation). *)
      let bound' = List.fold_left (fun b (f : fn_def) ->
        SS.add f.fn_name b) bound lfns in
      let lfns' = List.map (fun (f : fn_def) ->
        let fb = List.fold_left bind bound' f.fn_params in
        { f with fn_body = go fb f.fn_body }) lfns in
      ELetRec (lfns', go bound' e2)
    | ECase (scrut, branches, dflt) ->
      let branches' = List.map (fun (b : branch) ->
        let bb = List.fold_left bind bound b.br_vars in
        { b with br_body = go bb b.br_body }) branches in
      ECase (ra scrut, branches', Option.map (go bound) dflt)
    | ETuple atoms -> ETuple (List.map ra atoms)
    | ERecord fields -> ERecord (List.map (fun (n, a) -> (n, ra a)) fields)
    | EField (a, n) -> EField (ra a, n)
    | EUpdate (a, fields) ->
      EUpdate (ra a, List.map (fun (n, x) -> (n, ra x)) fields)
    | EAlloc (ty, atoms) -> EAlloc (ty, List.map ra atoms)
    | EStackAlloc (ty, atoms) -> EStackAlloc (ty, List.map ra atoms)
    | EFree a -> EFree (ra a)
    | EIncRC a -> EIncRC (ra a)
    | EDecRC a -> EDecRC (ra a)
    | EAtomicIncRC a -> EAtomicIncRC (ra a)
    | EAtomicDecRC a -> EAtomicDecRC (ra a)
    | EReuse (a, ty, atoms) -> EReuse (ra a, ty, List.map ra atoms)
    | ESeq (e1, e2) -> ESeq (go bound e1, go bound e2)
    | EAllocHole (tok, ty, atoms, hole) ->
      EAllocHole (Option.map ra tok, ty, List.map ra atoms, hole)
    | ESetField (obj, i, v) -> ESetField (ra obj, i, ra v)
  in
  List.map (fun (f : fn_def) ->
    let bound = List.fold_left bind SS.empty f.fn_params in
    { f with
      fn_name = (if f.fn_name = old_name then new_name else f.fn_name);
      fn_body = go bound f.fn_body }) fns

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
  (* The REPL never unboxes aggregates: a fragment's result thunk is called as
     [void -> ptr] and its value printed by walking a heap cell, so a struct
     returned in registers would be read as a pointer.  Forced off process-wide
     (see [Repr.force_disable]) so no later registration can re-enable it for a
     subsequent fragment. *)
  March_tir.Repr.force_disable ();
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

(** Resolve a TIR type-constructor name to the key [type_defs] is actually
    stored under.

    A type declared inside a module is registered by [Lower] under its
    module-qualified name ("Logger.Level"), but a TIR type referring to it —
    the `fn_ret_ty` of a REPL expression fragment, or a constructor's declared
    field type — is spelled with the BARE name ("Level").  Every printer
    lookup is by exact name, so before stdlib type_defs were registered at all
    this mismatch was invisible: the lookup missed either way.  With them
    registered it is the whole difference between `Warn` and `#<tag:2>` — and
    worse for a niche/enum type, where a missed lookup means [is_raw_word_ty]
    says "heap cell" about a raw word and the printer dereferences an integer.

    Exact match wins.  Otherwise accept a suffix match only when it is
    UNIQUE: stdlib has several modules declaring a `Level` or an `Error`, and
    guessing between them would print a confidently wrong constructor name.
    Ambiguous (or absent) resolves to the original name, which lands on the
    pre-existing `#<tag:N>` rendering — uninformative, but not a lie.

    Display only.  Codegen's own numbering is keyed by the type-qualified
    ctor name that [Lower] emits and never goes through here. *)
let canonical_type_name ~type_defs (name : string) : string =
  (* Never re-point a name the printer special-cases: `TCon ("Option", _)` has
     its own arm, and a stdlib module that happened to declare its own
     `Foo.Option` would otherwise steal the builtin's rendering. *)
  if List.mem name [ "List"; "Option"; "Result"; "Map"; "Set"; "Array" ] then name
  else if Hashtbl.mem type_defs name then name
  else begin
    let suffix = "." ^ name in
    let sl = String.length suffix in
    let matches =
      Hashtbl.fold (fun k _ acc ->
        let kl = String.length k in
        if kl > sl && String.sub k (kl - sl) sl = suffix then k :: acc else acc)
        type_defs [] in
    match matches with [ k ] -> k | _ -> name
  end

(** [canonical_type_name] lifted over a whole type, so nested field types
    ([Option(Level)], a record field, a tuple element) resolve too. *)
let rec qualify_ty ~type_defs (t : March_tir.Tir.ty) : March_tir.Tir.ty =
  let open March_tir.Tir in
  let q = qualify_ty ~type_defs in
  match t with
  | TCon (n, args) -> TCon (canonical_type_name ~type_defs n, List.map q args)
  | TTuple args -> TTuple (List.map q args)
  | TFn (args, r) -> TFn (List.map q args, q r)
  | TPtr t -> TPtr (q t)
  | TRecord fs -> TRecord (List.map (fun (n, t) -> (n, q t)) fs)
  | TVar _ | TInt | TFloat | TBool | TString | TUnit -> t

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

(** Which constructor of [name] carries heap tag [tag]?

    NOT simply [tag] itself.  Ordinary variants are numbered 0..n-1, so the
    tag is the index — but an actor-message type, or a type whose SHORT name
    is declared by two or more modules, is numbered from a global counter
    (0x0100_0000 / 0x0200_0000 upward) precisely so its constructors cannot
    be confused with another type's.  [ctor_tags] is that numbering, obtained
    from the same [Llvm_toplevel.variant_ctor_tags] the fragment was compiled
    through, so the two cannot disagree.

    This only started biting the REPL when stdlib's type_defs became visible
    to expression fragments: stdlib declares both a `Color` and a
    `Plot.Color`, so a prompt-declared `type Color = Red | Green | Blue` lands
    in a collision set the moment stdlib is in the list, so its tags jump into the global range and "tag = index" silently
    became false.  A type absent from [ctor_tags] keeps the ordinary reading. *)
let ctor_index_of_tag ~ctor_tags (name : string) (tag : int) : int option =
  match Hashtbl.find_opt ctor_tags name with
  | None -> Some tag
  | Some tags ->
    let rec go i = function
      | [] -> None
      | t :: rest -> if t = tag then Some i else go (i + 1) rest in
    go 0 tags

(** Pretty-print a March heap value given its TIR type.
    [type_defs] provides user-declared TDVariant/TDRecord lookups for
    non-builtin TCon names.  Recursion is bounded to depth 64. *)
let rec pp_heap_value ?(depth=0) ~type_defs ~ctor_tags (ty : March_tir.Tir.ty) (ptr : nativeint) : string =
  if depth > 64 then "#<...>"
  else
  let open March_tir.Tir in
  (* Resolve bare module-type names to their registered keys before ANY
     lookup below, including [variant_repr]'s — a missed lookup here decides
     heap-cell-vs-raw-word, not just which name gets printed.  Idempotent, so
     the recursive calls re-entering here cost only a hash hit. *)
  let ty = qualify_ty ~type_defs ty in
  match ty with
  (* Niche / newtype types are NOT heap cells: [ptr] is the raw payload word
     (or 0 for a niche's nullary ctor), so these must be decoded before the
     null guard and before any tag read. *)
  | TCon (name, args) when (match Hashtbl.find_opt type_defs name with
                            | Some (TDVariant _) -> true | _ -> false)
                        && (match variant_repr ~type_defs name args with
                            (* [Repr.Unboxed] never reaches the REPL: the REPL
                               registers the empty unboxed table (see
                               [Repr.set_unboxed_types]), so its aggregates
                               stay Boxed heap cells.  Grouped with Boxed so
                               the printer stays correct if that changes. *)
                            | March_tir.Repr.Boxed
                            | March_tir.Repr.Unboxed _ -> false | _ -> true) ->
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
                 (pp_word ~depth ~type_defs ~ctor_tags ~tagged (subst_ty bindings payload) ptr))
     | March_tir.Repr.Newtype payload ->
       (match ctors with
        | [ (ctor, [ declared ]) ] ->
          Printf.sprintf "%s(%s)" ctor
            (pp_word ~depth ~type_defs ~ctor_tags ~tagged:(field_is_tagged declared)
               (subst_ty bindings payload) ptr)
        | _ -> Printf.sprintf "#<newtype:%nd>" ptr)
     (* Unreachable: the guard above already excluded Boxed and Unboxed.
        Rendered rather than asserted — a printer must never take the REPL
        down. *)
     | March_tir.Repr.Boxed | March_tir.Repr.Unboxed _ ->
       Printf.sprintf "#<%s:%nd>" name ptr)
  | _ ->
  if ptr = Nativeint.zero then "#<null>"
  else
  match ty with
  | TString ->
    (* march_string layout: {rc:i64, tag:i32, pad:i32, len:i64, data:char[]} *)
    Printf.sprintf "%S" (Jit.read_march_string ptr)
  | TCon ("List", [elem_ty]) ->
    pp_list ~depth ~type_defs ~ctor_tags elem_ty ptr
  | TCon ("Option", [inner_ty]) ->
    let tag = heap_tag ptr in
    if tag = 0 then "None"
    else
      let v = pp_field ~depth ~type_defs ~ctor_tags ~tagged:true inner_ty ptr 0 in
      Printf.sprintf "Some(%s)" v
  | TCon ("Result", [ok_ty; err_ty]) ->
    let tag = heap_tag ptr in
    if tag = 0 then Printf.sprintf "Ok(%s)" (pp_field ~depth ~type_defs ~ctor_tags ~tagged:true ok_ty ptr 0)
    else         Printf.sprintf "Err(%s)" (pp_field ~depth ~type_defs ~ctor_tags ~tagged:true err_ty ptr 0)
  | TTuple tys ->
    (* Tuple fields use the uniform slot convention: scalars are low-bit
       tagged (matching ETuple's coerce-to-ptr store), so untag scalar views. *)
    let fields = List.mapi (fun i ty -> pp_field ~depth ~type_defs ~ctor_tags ~tagged:true ty ptr i) tys in
    Printf.sprintf "(%s)" (String.concat ", " fields)
  | TCon (name, args) when Hashtbl.mem type_defs name ->
    let td = Hashtbl.find type_defs name in
    (match td with
     | TDVariant (_, ctors) ->
       let tag = heap_tag ptr in
       (match Option.bind (ctor_index_of_tag ~ctor_tags name tag)
                (List.nth_opt ctors) with
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
              pp_field ~depth ~type_defs ~ctor_tags ~tagged:(field_is_tagged declared)
                (subst_ty bindings declared) ptr i
            ) payload_tys in
            Printf.sprintf "%s(%s)" ctor_name (String.concat ", " fields))
     | TDRecord (_, fs) ->
       let fields = List.mapi (fun i (fname, fty) ->
         (* Record scalar fields are stored UNTAGGED (same layout as tuples),
            not payload-tagged like ADT constructor args. *)
         Printf.sprintf "%s: %s" fname
           (pp_field ~depth ~type_defs ~ctor_tags ~tagged:false fty ptr i)
       ) fs in
       Printf.sprintf "{%s}" (String.concat ", " fields)
     | TDClosure _ -> Printf.sprintf "#<tag:%d>" (heap_tag ptr))
  | TRecord fs ->
    (* Structural record — sorted alphabetically by Lower.convert_ty/lower_ty.
       Scalar fields are stored UNTAGGED (like tuple slots), not as
       payload-tagged ADT fields. *)
    let fields = List.mapi (fun i (fname, fty) ->
      Printf.sprintf "%s: %s" fname
        (pp_field ~depth ~type_defs ~ctor_tags ~tagged:false fty ptr i)
    ) fs in
    Printf.sprintf "{%s}" (String.concat ", " fields)
  | _ ->
    (* Unknown heap type: show tag for basic orientation; guard null *)
    if ptr = Nativeint.zero then "#<null>"
    else Printf.sprintf "#<tag:%d>" (heap_tag ptr)

and pp_list ?(depth=0) ~type_defs ~ctor_tags elem_ty (ptr : nativeint) : string =
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
    Buffer.add_string buf (pp_field ~depth ~type_defs ~ctor_tags ~tagged:true elem_ty !cur 0);
    cur := field_ptr !cur 1;  (* tail is field 1 of Cons *)
    incr count
  done;
  if !count = max_elems then Buffer.add_string buf ", ...";
  Buffer.add_char buf ']';
  Buffer.contents buf

and pp_field ?(depth=0) ~type_defs ~ctor_tags ~tagged (ty : March_tir.Tir.ty) (ptr : nativeint) (i : int) : string =
  let open March_tir.Tir in
  match ty with
  | TFloat ->
    (* Floats are stored as raw double bits via bitcast — no tag bit, and the
       bit pattern is not a meaningful nativeint, so read the slot directly. *)
    Printf.sprintf "%g" (Int64.float_of_bits (field_i64 ptr i))
  | TInt | TBool | TUnit ->
    pp_word ~depth ~type_defs ~ctor_tags ~tagged ty (Int64.to_nativeint (field_i64 ptr i))
  | _ -> pp_word ~depth ~type_defs ~ctor_tags ~tagged ty (field_ptr ptr i)

(** Render a value held in a single machine word — a constructor field just
    read out of a cell, or the whole value of a niche/newtype type.
    [tagged] says the word holds a low-bit-tagged scalar (value<<1)|1. *)
and pp_word ?(depth=0) ~type_defs ~ctor_tags ~tagged (ty : March_tir.Tir.ty) (w : nativeint) : string =
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
    else pp_heap_value ~depth:(depth + 1) ~type_defs ~ctor_tags ty w

(** True when a value of [ty] is NOT a heap pointer but the raw payload word
    of a niche/newtype representation — the two cases where the "small word =
    plain integer" fallback in [run_expr] would print `15` instead of `X(7)`,
    and where a raw 0 means the nullary constructor rather than a null value. *)
let is_raw_word_ty ~type_defs (ty : March_tir.Tir.ty) =
  (* Same resolution [pp_heap_value] applies: a bare `Level` that fails to
     find `Logger.Level` reports Boxed, and the caller then dereferences an
     enum's raw word as a pointer. *)
  match qualify_ty ~type_defs ty with
  | March_tir.Tir.TCon (name, args) ->
    (match Hashtbl.find_opt type_defs name with
     | Some (March_tir.Tir.TDVariant _) ->
       (match variant_repr ~type_defs name args with
        | March_tir.Repr.Boxed -> false
        | _ -> true)
     | _ -> false)
  | _ -> false

(** The constructor numbering the next expression fragment will be compiled
    with — [ctx.loaded_tir_types] is exactly the `~types` prefix handed to it,
    and the numbering is order-sensitive, so it is derived from that list
    rather than from the (unordered) [global_type_defs] table.

    Recomputed per printed value: it is a walk over a few hundred type_defs,
    once, against a REPL round-trip that has already paid a clang invocation. *)
let ctor_tags_of ctx =
  let types = ctx.loaded_tir_types in
  March_tir.Llvm_toplevel.variant_ctor_tags
    ~collision_set:(March_tir.Collision_set.compute types) types

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
        let sw = fresh_wrap_state ctx in
        let ir = March_tir.Llvm_emit.emit_fns_fragment
          ~types:tir.March_tir.Tir.tm_types ~fns:new_fns ~extern_fns
          ~session_wraps:sw ~repl:true () in
        (try
          ignore (compile_fragment ctx ir);
          mark_compiled_fns ctx new_fns;
          commit_wraps ctx sw
        with Failure msg ->
          Printf.eprintf "jit: module compile failed: %s\n%!" msg)
      end
    with exn ->
      Printf.eprintf "jit: module registration failed: %s\n%!" (Printexc.to_string exn))
  | _ -> ()

(* ── Whole-program JIT (`march --jit file.march`) ───────────────────────── *)

(** Substring test (no Str dependency in this library).  Iterative on purpose:
    the haystack is a whole IR fragment (hundreds of KB), so a recursive
    scan would be a stack-depth hazard. *)
let contains_sub (hay : string) (needle : string) : bool =
  let n = String.length needle and h = String.length hay in
  if n = 0 then true
  else begin
    let found = ref false and i = ref 0 in
    while (not !found) && !i + n <= h do
      if String.sub hay !i n = needle then found := true else incr i
    done;
    !found
  end

(** LLVM rejects a duplicate `declare` of a symbol, and the REPL preamble
    declares [march_run_scheduler] / [march_remote_init] only CONDITIONALLY
    (see [Llvm_builtins]'s PDeclare table — the set emitted depends on which
    builtins the fragment actually uses).  So each entry-thunk declare is
    emitted only when the fragment does not already carry it. *)
let declare_if_absent (ir : string) (decl : string) : string =
  if contains_sub ir decl then "" else decl ^ "\n"

(** Whole-program JIT: lower [m] (the user module only — the stdlib prelude is
    already compiled and recorded in [ctx.stdlib_decls] / [ctx.compiled_fns] by
    [precompile_stdlib]) and run its [main].

    Entry shape mirrors the NATIVE build's `@main` (lib/tir/llvm_toplevel.ml),
    not a bare call into the mangled `main`:

      march_remote_init(); march_spawn_main(thunk); march_run_scheduler()

    That matters for two independent reasons.  (1) [march_spawn_main]'s ABI is
    a 0-arg void function pointer, while a March `main` may take any number of
    capability parameters; the thunk supplies one ERASED capability per
    parameter — a null pointer, the same value [Llvm_emit]'s `root_cap` atom
    and llvm_toplevel's `march_main_entry_thunk` use (Cap(_) compiles to a null
    ptr; see specs/lang/capabilities.md "Runtime behaviour").  (2) a compiled
    `main` IS a green thread: running it on the host thread instead would leave
    the scheduler unstarted, so anything that spawns a task or blocks would
    deadlock rather than run.

    Like the native build, the process exit code does not carry `main`'s
    result: [march_spawn_main]'s void ABI drops it and native `@main` returns
    a hard 0. *)
let run_program ctx ~tc_env (m : March_ast.Ast.module_) : unit =
  let errors = March_errors.Errors.create () in
  let env = { tc_env with March_typecheck.Typecheck.errors;
    (* Same per-call reset as [register_module_decl]/[run_expr]: [tc_env] is a
       long-lived, reused environment. *)
    refs = ref []; current_decl = ref "" } in
  let (_, type_map) = March_typecheck.Typecheck.check_module_with_env env m in
  let tir = lower_module ~type_map ~stdlib_context:ctx.stdlib_decls m in
  (* Prune functions unreachable from `main`, exactly as the ahead-of-time
     pipeline does immediately before LLVM emit (see [Dce.prune_unreachable]'s
     call in bin/main.ml).  This is a LINKABILITY requirement here, not an
     optimization, and it is what makes a whole-program --jit run link the same
     set of symbols the native build does.

     [Lower.lower_module] pulls in stdlib modules at MODULE granularity: the
     first qualified reference to `JsonStream.feed` lowers EVERY function in
     `stdlib/json_stream.march`, including `typed_events`, whose body calls the
     bare `from_json` that a `derive Json` is supposed to supply at the call
     site.  With no user `derive Json` in the program, `from_json` has no
     definition anywhere — the AOT build never noticed because DCE dropped
     `typed_events` before emit, while --jit emitted it and the JIT linker
     failed to materialize `_from_json`, taking down the whole module.

     Safe ONLY on this whole-program path: a `main` is present, so
     [root_names] roots reachability at it. The REPL's per-fragment paths
     ([run_expr]/[run_decl]) must NOT prune — a fragment has no `main`, and
     anything it defines may be called by a LATER fragment. *)
  let tir = March_tir.Dce.prune_unreachable tir in
  register_type_defs ctx tir.March_tir.Tir.tm_types;
  let all_types = ctx.loaded_tir_types @ tir.March_tir.Tir.tm_types in
  (* Same entry-point rule as [Llvm_toplevel.emit_module]: a bare `main` or a
     module-qualified `Mod.main`. *)
  let is_main (f : March_tir.Tir.fn_def) =
    f.March_tir.Tir.fn_name = "main"
    || String.ends_with ~suffix:".main" f.March_tir.Tir.fn_name in
  let main_fn =
    match List.find_opt (fun f -> f.March_tir.Tir.fn_name = "main")
            tir.March_tir.Tir.tm_fns with
    | Some f -> Some f
    | None -> List.find_opt is_main tir.March_tir.Tir.tm_fns in
  match main_fn with
  | None ->
    (* A library module with no entry point: there is nothing to run.  Mirrors
       BOTH [Llvm_toplevel.emit_module]'s `| None ->` branch (which no-ops into
       a stub `@main` returning 0) and, decisively, the tree-walking
       interpreter, which prints nothing and exits 0 for such a file — a --jit
       run must not differ.  Deliberately detected HERE, before any IR
       emission, dlopen, or [march_spawn_main], so the no-main path costs
       nothing and can never half-start a scheduler. *)
    ()
  | Some main_fn ->
  let n = next_id ctx in
  (* A bare `main` MUST be renamed before it reaches [partition_fns].
     [mangle_extern "main"] is "march_main" — the native entry symbol — so
     [is_c_runtime_fn] classifies it as a C-runtime function and drops it from
     BOTH the define list and the declare list, leaving the entry thunk calling
     an undefined @march_main.  Renaming to a fragment-unique symbol also keeps
     the definition out of the way of the runtime .so's own symbols. *)
  let jit_main = Printf.sprintf "march_jit_user_main_%d" n in
  let all_fns =
    rename_top_fn_refs ~old_name:main_fn.March_tir.Tir.fn_name
      ~new_name:jit_main tir.March_tir.Tir.tm_fns in
  let (new_fns, extern_fns) = partition_fns ctx all_fns in
  let sw = fresh_wrap_state ctx in
  let ir = March_tir.Llvm_emit.emit_fns_fragment
      ~types:all_types ~fns:new_fns ~extern_fns ~session_wraps:sw ~repl:true () in
  let mangled = March_tir.Llvm_emit.mangle_extern jit_main in
  let ret_ty = March_tir.Llvm_ctx.llvm_ret_ty main_fn.March_tir.Tir.fn_ret_ty in
  let erased_args =
    String.concat ", "
      (List.map (fun (v : March_tir.Tir.var) ->
           let ty = March_tir.Llvm_ctx.llvm_ty v.March_tir.Tir.v_ty in
           (* Capability parameters are pointer-shaped; keep the fallback
              honest for any non-ptr parameter rather than emitting `null`
              against an integer type (an LLVM verifier error). *)
           if ty = "ptr" then ty ^ " null" else ty ^ " 0")
         main_fn.March_tir.Tir.fn_params) in
  let thunk = Printf.sprintf "march_jit_main_thunk_%d" n in
  let entry = Printf.sprintf "march_jit_program_%d" n in
  let ir =
    ir
    ^ "\n" ^ declare_if_absent ir "declare void @march_remote_init()"
    ^ declare_if_absent ir "declare void @march_run_scheduler()"
    ^ "declare void @march_spawn_main(ptr)\n"
    ^ Printf.sprintf
        "\ndefine private void @%s() {\nentry:\n  %scall %s @%s(%s)\n  ret void\n}\n"
        thunk
        (if ret_ty = "void" then "" else "%_r = ")
        ret_ty mangled erased_args
    ^ Printf.sprintf
        "\ndefine void @%s() {\nentry:\n\
        \  call void @march_remote_init()\n\
        \  call void @march_spawn_main(ptr @%s)\n\
        \  call void @march_run_scheduler()\n\
        \  ret void\n}\n" entry thunk in
  let handle = compile_fragment ctx ir in
  mark_compiled_fns ctx new_fns;
  commit_wraps ctx sw;
  ctx.loaded_tir_types <- all_types;
  let fptr = lookup_sym ctx handle entry in
  Jit.call_void_to_void fptr

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
  let sw = fresh_wrap_state ctx in
  let ir = time_phase "emit_ir" (fun () ->
    March_tir.Llvm_emit.emit_repl_expr
      ~n ~ret_ty
      ~prev_slots:(prev_slots_of ctx)
      ~fns:new_fns
      ~extern_fns
      ~store_as_slot:(Some v_slot)
      ~session_wraps:sw
      ~types:(ctx.loaded_tir_types @ tir.March_tir.Tir.tm_types)
      main_fn.fn_body) in
  let handle = time_phase "clang+dlopen"
    (fun () -> compile_fragment ctx ir) in
  mark_compiled_fns ctx new_fns;
  commit_wraps ctx sw;
  let sym_name = Printf.sprintf "repl_%d" n in
  let fptr = lookup_sym ctx handle sym_name in
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
           pp_heap_value ~type_defs:ctx.global_type_defs ~ctor_tags:(ctor_tags_of ctx) ty ptr
         else if ptr = Nativeint.zero then "null"
         else pp_heap_value ~type_defs:ctx.global_type_defs ~ctor_tags:(ctor_tags_of ctx) ty ptr
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
      pp_heap_value ~type_defs:ctx.global_type_defs ~ctor_tags:(ctor_tags_of ctx) ty
        (Jit.call_void_to_ptr fptr)
    | ty ->
      let ptr = Jit.call_void_to_ptr fptr in
      if ptr = Nativeint.zero then "null"
      else
        let raw = Int64.of_nativeint ptr in
        if Int64.compare raw 0x100000000L < 0 && Int64.compare raw 0L >= 0 then
          Int64.to_string raw
        else
          pp_heap_value ~type_defs:ctx.global_type_defs ~ctor_tags:(ctor_tags_of ctx) ty ptr
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
    (* JIT context persists across :reset.  When the scroll system resends
       prior cells, the function is already compiled and its closure slot is
       still valid — skip recompilation entirely (helper lambdas may have new
       defun UIDs but the compiled closure is unchanged).  A REPLAY is
       recognized by its AST fingerprint matching the recorded one; a genuine
       REDEFINITION (same name, different body) has a different fingerprint
       and must recompile and rebind the closure slot, matching interpreter-
       mode's Elixir-style rebinding.  A compiled name with NO fingerprint on
       record was compiled outside run_decl (stdlib prelude, :load): calls to
       those resolve as direct extern calls, not through a slot, so a
       redefinition could never take effect — keep the historical skip. *)
    let fingerprint = Digest.to_hex (Digest.string (Marshal.to_string m [])) in
    let already_compiled = Hashtbl.mem ctx.compiled_fns bind_name in
    let is_replay =
      already_compiled &&
      (match Hashtbl.find_opt ctx.fn_fingerprints bind_name with
       | Some fp -> fp = fingerprint
       | None -> true)
    in
    if is_replay then ()
    else begin
    let is_redefinition = already_compiled in
    (* partition_fns classified the freshly lowered [bind_name] as extern
       (its OLD version is in compiled_fns); pull it back so the new body is
       defined in this fragment rather than declared. *)
    let (user_fns, extern_fns) =
      if is_redefinition then
        let (redef, ext) = List.partition
          (fun (f : March_tir.Tir.fn_def) -> f.fn_name = bind_name)
          extern_fns in
        (user_fns @ redef, ext)
      else (user_fns, extern_fns)
    in
    (* Emit a redefinition under a session-unique symbol: the earlier
       fragment already defined [bind_name], and the ORC backend's single
       JITDylib hard-errors on a duplicate definition (clang+dlopen would
       merely shadow ambiguously in the flat namespace).  Calls resolve
       through the closure SLOT, not the symbol, so only the slot binding
       below needs the bare name.  [ctx.counter] is monotonic and the
       primary emit below advances it, so successive redefinitions get
       distinct names. *)
    let emit_name =
      if is_redefinition then
        Printf.sprintf "%s$redef$%d" bind_name ctx.counter
      else bind_name
    in
    let user_fns =
      if is_redefinition then
        rename_top_fn_refs ~old_name:bind_name ~new_name:emit_name user_fns
      else user_fns
    in
    (* On redefinition, drop the OLD binding's slot from prev_slots: the
       emitter would otherwise emit a slot-loader `define @<bind_name>()`
       that collides with the original fragment's definition under ORC, and
       the new body must not silently resolve its own name to the old
       closure anyway (self-recursion was renamed to [emit_name] above). *)
    let prev_slots =
      List.filter (fun (si : March_tir.Llvm_emit.repl_slot_info) ->
        not (is_redefinition && si.rs_bare = bind_name))
        (prev_slots_of ctx)
    in
    let primary_fn =
      match List.find_opt (fun (f : March_tir.Tir.fn_def) ->
        f.fn_name = emit_name) user_fns with
      | Some f -> f
      | None -> List.hd user_fns
    in
    let helper_fns = List.filter
      (fun (f : March_tir.Tir.fn_def) -> f.fn_name <> primary_fn.fn_name)
      user_fns in
    (* Emit the primary function, its helper lambdas, AND the closure-slot
       init in ONE fragment.  Helpers must share a module with each other
       (outer lambda creates inner lambda's closure) and with the PRIMARY:
       a lambda body may call the fn being defined (self-recursion through
       a lambda), so a helpers-only fragment loaded first carries a dangling
       reference to the primary's symbol — macOS dlopen binds eagerly and
       fails with "symbol not found in flat namespace" even though the
       primary's fragment would have been loaded right after.  ORC fails the
       same way: its single JITDylib cannot resolve a not-yet-defined symbol.
       One fragment therefore means one wrap state, committed once below. *)
    let pn = next_id ctx in
    let slot = alloc_slot ctx in
    let sw = fresh_wrap_state ctx in
    let ir = March_tir.Llvm_emit.emit_repl_fn_with_closure_slot
      ~n:pn ~bind_name ~dest_slot:slot ~prev_slots
      ~helper_fns ~extern_fns ~session_wraps:sw
      ~types:(ctx.loaded_tir_types @ tir.March_tir.Tir.tm_types)
      primary_fn in
    let handle = compile_fragment ctx ir in
    mark_compiled_fns ctx (primary_fn :: helper_fns);
    commit_wraps ctx sw;
    (* Record the declaration's fingerprint only after the fragment compiled
       and loaded — a failed compile must leave the previous state (and its
       fingerprint) intact so the user's retry recompiles cleanly, mirroring
       the mark_compiled_fns discipline. *)
    Hashtbl.replace ctx.fn_fingerprints bind_name fingerprint;
    let init_name = Printf.sprintf "repl_%d_init" pn in
    let fptr = lookup_sym ctx handle init_name in
    Jit.call_void_to_void fptr;
    (* Register the slot so future fragments can load the closure as a value.
       The type is TFn (closures are heap pointers), which causes emit_prev_slot_bridges
       to emit inttoptr when loading the closure from the slot.  On a
       redefinition this REBINDS the bare name to the fresh slot holding the
       new closure — later fragments resolve calls through this binding, so
       they pick up the new body.  (The old slot keeps the old closure alive;
       one abandoned closure per redefinition, same shape as `let` rebinding.) *)
    ctx.var_slots <- (bind_name, slot, March_tir.Tir.TFn ([], March_tir.Tir.TUnit)) ::
      List.filter (fun (b, _, _) -> b <> bind_name) ctx.var_slots
    end (* not is_replay *)
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
    let sw = fresh_wrap_state ctx in
    let ir = March_tir.Llvm_emit.emit_repl_decl
      ~n ~name:bind_name
      ~val_ty:main_fn.fn_ret_ty
      ~dest_slot:slot
      ~prev_slots:(prev_slots_of ctx)
      ~fns:user_fns
      ~extern_fns
      ~session_wraps:sw
      ~types:(ctx.loaded_tir_types @ tir.March_tir.Tir.tm_types)
      main_fn.fn_body in
    let handle = compile_fragment ctx ir in
    mark_compiled_fns ctx user_fns;
    commit_wraps ctx sw;
    let init_name = Printf.sprintf "repl_%d_init" n in
    let fptr = lookup_sym ctx handle init_name in
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
      stdlib_prelude_<hash>.types — Marshal'd [Tir.type_def list], the exact
                                    `~types` list the .so was compiled with

    On cache hit: dlopen the .so, read function names from the .names file and
      type_defs from the .types file, mark all functions as compiled — NO TIR
      lowering needed.
    On cache miss: lower [stdlib_decls] to TIR, compile to a .so, write the
      .names and .types files, then dlopen.

    All three files are required for a hit; a missing or unreadable one falls
    through to the recompile branch.

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
  (* Key the prelude cache on the COMPILER as well as the stdlib source.
     [content_hash] digests only stdlib_decls, so a compiler whose codegen
     changed while the stdlib text did not reuses the previous build's .so —
     and the prelude is ordinary compiled code, not data, so that is a
     mismatched-codegen hazard rather than a stale-but-valid cache.  Hit
     twice while fixing the mutual-TCO gap below: a compiler that emitted the
     combined dispatch function happily loaded a cached prelude that did NOT,
     and json_stream went on dying at exit 138 as if the fix had not landed.

     Identity comes from the executable's size + mtime, not [Digest.file]:
     the binary is ~15 MB and this runs on every --jit/REPL startup, so
     hashing it would put a file read of that size on the warm path to save
     nothing this cheaper key does not already catch (any rebuild rewrites
     the file and moves its mtime). *)
  let compiler_id =
    (try
       let st = Unix.stat Sys.executable_name in
       Printf.sprintf "%d:%.0f" st.Unix.st_size st.Unix.st_mtime
     with _ -> "unknown") in
  let short_hash =
    String.sub
      (Digest.to_hex (Digest.string (content_hash ^ "|" ^ compiler_id))) 0 16 in
  (* The `ty1` generation tag marks "this cache entry has a .types companion".
     [compiler_id] above already makes a pre-change compiler's blobs
     unreachable to this one (any rebuild moves the executable's size/mtime),
     but the generation tag states the format dependency explicitly rather
     than leaving it to that side effect — the .types file is Marshal'd
     [Tir.type_def list], and reading an old blob under a new shape is the
     failure mode this repo has been bitten by before.  Bump it whenever the
     companion-file set or its encoding changes. *)
  let prefix = "stdlib_prelude_O1_tln2_ty1_" in
  let so_path    = Filename.concat cache_dir (prefix ^ short_hash ^ ".so") in
  let names_path = Filename.concat cache_dir (prefix ^ short_hash ^ ".names") in
  (* Marshal'd [March_tir.Tir.type_def list] — exactly the `~types` list the
     .so was compiled with.  Constructor tags are numbered from this list by
     [Llvm_emit]'s [build_ctor_info] (first-wins, order-sensitive), so every
     later expression fragment must be handed the SAME list in the SAME order
     or its constructors get tags that disagree with the compiled prelude. *)
  let types_path = Filename.concat cache_dir (prefix ^ short_hash ^ ".types") in
  (* ── Cache hit path ───────────────────────────────────────────────────── *)
  (* [loaded] records whether the cached .so was ACTUALLY adopted.  A failed
     load must fall through to the compile branch below, which is what this
     function's own "recompiling" message has always promised.

     It used to promise it without doing it: the load lived in the `then` arm
     of an if/else, so an exception was caught, reported, and then simply fell
     out of the whole conditional with [ctx.compiled_fns] still EMPTY.  That
     is not a slow path, it is a miscompiling one.  With no prelude adopted,
     every stdlib module reaches the fragment through [Lower]'s lazy
     [_ensure_module_lowered] hook, which re-reads the module WITHOUT a
     type_map and so gives every function all-`TVar "_"` signatures.  Callers
     and callees then disagree about representation — measured on
     `JsonStream.is_ws`, emitted as `ptr -> ptr` returning a TAGGED immediate
     while its call site in `JsonStream.free_byte` loaded a heap tag from the
     result — i.e. a load from address 0x9, tagged `false` plus the 8-byte tag
     offset.  Exit 139 out of the scheduler's fault handler, no diagnostic.

     This path is reached routinely, not rarely: on macOS the cached runtime
     .so is built at a `<name>.<pid>.tmp` path and renamed into place, so its
     LC_ID_DYLIB still names the temp file, and the prelude .so linked against
     it records that now-nonexistent path.  Every session after the one that
     built it therefore fails to dlopen the prelude.  Fixing THAT belongs with
     the runtime-.so builder (bin/main.ml) and only costs the cache hit;
     falling through correctly is what keeps the miss safe. *)
  let loaded = ref false in
  if Sys.file_exists so_path && Sys.file_exists names_path
     && Sys.file_exists types_path then begin
    (try
      (* Read the type_defs BEFORE adopting anything: a missing or unreadable
         .types file must fall through to the recompile branch, not leave us
         with a prelude whose constructor numbering nothing else can see. *)
      let cached_types : March_tir.Tir.type_def list =
        let ic = open_in_bin types_path in
        Fun.protect ~finally:(fun () -> close_in_noerr ic)
          (fun () -> Marshal.from_channel ic) in
      let handle = Jit.dlopen so_path in
      loaded := true;
      (* Hand stdlib's type_defs to both consumers of constructor numbering:
         [ctx.loaded_tir_types] is the `~types` prefix of every subsequent
         expression fragment (codegen), and [ctx.global_type_defs] is what the
         heap pretty-printer reads to turn a tag back into a ctor name.
         Without this the warm-cache path — the common one — never lowers
         stdlib to TIR at all, so a fragment mentioning `Http.Post` misses in
         [ctor_entry] and takes its `ce_tag = 0` default: every stdlib
         constructor is BUILT with tag 0 and every [match] arm COMPARED
         against 0, so the first arm always wins.  A wrong answer, not just a
         wrong rendering. *)
      register_type_defs ctx cached_types;
      ctx.loaded_tir_types <- cached_types @ ctx.loaded_tir_types;
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
      (* Drop anything a partial load recorded, so the recompile below starts
         from a clean slate rather than a half-populated compiled_fns that
         would send some prelude functions to `extern` with no definition. *)
      loaded := false;
      Hashtbl.reset ctx.compiled_fns;
      (* Same reasoning for the type_defs a partial load may have registered:
         the recompile below installs its own list, and two copies would make
         [build_ctor_info]'s first-wins numbering depend on which came first. *)
      ctx.loaded_tir_types <- [];
      Hashtbl.reset ctx.global_type_defs;
      Printf.eprintf "march JIT: stdlib cache load failed (%s), recompiling\n%!"
        (Printexc.to_string exn))
  end;
  if not !loaded then begin
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
        let sw = fresh_wrap_state ctx in
        let ir = March_tir.Llvm_emit.emit_fns_fragment
          ~types:tir.March_tir.Tir.tm_types ~fns:stdlib_fns
          ~session_wraps:sw ~repl:true () in
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
        (* -install_name: clang otherwise stamps LC_ID_DYLIB with so_tmp — the
           pid-suffixed path this is BUILT at, which ceases to exist the moment
           the rename below publishes the .so.  Harmless for our own dlopen
           (we pass an absolute path), but it is exactly the bug that made the
           RUNTIME .so unusable as a link dependency across sessions; don't
           reintroduce it here. *)
        (* -Xlinker rather than -Wl,: clang splits -Wl, arguments on commas,
           which would tear a cache path containing one into bogus flags. *)
        let install_name =
          if is_macos ()
          then Printf.sprintf " -Xlinker -install_name -Xlinker %s"
                 (Filename.quote so_path)
          else "" in
        let cmd = Printf.sprintf "%s -shared -fPIC -O1%s%s%s -o %s %s 2>&1"
          ctx.clang ctx.undef_flag ctx.rt_link install_name so_tmp ll_path in
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
           (* Companion .types: the `~types` list this .so was compiled with,
              so a warm-cache session can hand the identical list (identical
              ORDER — [build_ctor_info] is first-wins) to its expression
              fragments and to the pretty-printer.  Published before the .so
              for the same reason .names is: the hit path requires all three
              files, so renaming the .so last means no reader ever pairs it
              with a partial companion. *)
           (try
             let types_tmp =
               Printf.sprintf "%s.%d.tmp" types_path (Unix.getpid ()) in
             let tc = open_out_bin types_tmp in
             Fun.protect ~finally:(fun () -> close_out_noerr tc) (fun () ->
               Marshal.to_channel tc tir.March_tir.Tir.tm_types []);
             Sys.rename types_tmp types_path
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
             ) stdlib_fns;
             (* Mirror of the cache-hit path: the cold path lowered stdlib to
                TIR but was dropping [tm_types] on the floor once the fragment
                was emitted, so a COLD session mis-tagged stdlib constructors
                exactly like a warm one.  Register the same list the .so was
                compiled with, in the same order. *)
             register_type_defs ctx tir.March_tir.Tir.tm_types;
             ctx.loaded_tir_types <-
               tir.March_tir.Tir.tm_types @ ctx.loaded_tir_types;
             commit_wraps ctx sw
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
  (* Dispose this session's LLJIT (if it ever created one — clang mode and
     JIT-less tests leave it [None]) BEFORE closing the dl handles, so JIT'd
     code is torn down while the runtime/prelude .sos it references are still
     mapped.  LLVMOrcDisposeLLJIT frees all code produced by [add_ir]; that is
     exactly the right lifetime here, since a session's fragments must die with
     the session — the same contract dlclose gives the clang path.  [cleanup]
     is terminal for a ctx (all callers drop it immediately: bin/main.ml's
     Fun.protect finallys, test/test_codegen.ml's protect-and-reraise pairs,
     test/test_helpers.ml), so the disposed handle can never be reused; clear
     it anyway to make a double [cleanup] a no-op rather than a double free. *)
  (match ctx.orc with
   | Some j -> (try Jit_orc.dispose j with _ -> ())
   | None -> ());
  ctx.orc <- None;
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
