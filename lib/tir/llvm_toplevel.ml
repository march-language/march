(** Top-level (whole-function / whole-module) LLVM emission: [emit_fn],
    constructor-table setup ([build_ctor_info]), and [emit_module] — the
    module-level assembly pass (HCR name-table setup, extern/main/test/WASM
    entry emission).

    Wave 3 Task 7 (chunk 2) split: moved verbatim out of [llvm_emit.ml] —
    same discipline as the Wave 3 Task 5/6 splits ([Llvm_eq]/[Llvm_data]/
    [Llvm_case]/[Llvm_calls]/[Llvm_tco]): whole-definition moves, no
    behavior change, fully-qualified references (this file, like
    llvm_emit.ml, uses no [open]).

    De-cycling: [emit_fn] and [emit_module] both need [Llvm_emit.emit_expr]
    (the core recursive expression emitter, which stays in [llvm_emit.ml] —
    it is the one piece explicitly excluded from this split per the task
    brief). Since [llvm_emit.ml] is the orchestrator that in turn calls
    [emit_module] from this module, a direct reference the other way would
    cycle; both functions instead take [~emit_expr] as a labeled callback
    parameter, exactly the pattern [Llvm_case.emit_case] (Task 5) and
    [Llvm_tco.emit_mutual_tco_group] (Task 6) already established.

    [target_config] (the compilation-target variant) and its two small
    consumers [is_wasm_target]/[target_triple], plus the thin [emit_preamble]
    wrapper over [Llvm_builtins.emit_preamble], move here too: [emit_module]
    is their one real consumer with a cross-module reference (the only other
    reader, [emit_preamble] itself, moves alongside them) — same "pure
    primitive, real non-llvm_emit.ml consumer" promotion criterion Task 6
    used for [llvm_ret_ty]/[emit_reduction_check]. [llvm_emit.ml] re-exports
    the type and all of these bare, preserving the "target_config /
    target_triple / is_wasm_target / emit_preamble are part of llvm_emit.ml's
    public API" contract from the outside — external callers
    (bin/main.ml, lib/jit/repl_jit.ml, test/) reference them only as
    [Llvm_emit.target_config] / [Llvm_emit.Native] / etc., never
    [Llvm_toplevel.*], so the re-export is the only thing that matters for
    API stability. *)

(** Target architecture for native/cross builds. *)
type arch = X86_64 | Arm64

(** Compilation target. *)
type target_config =
  | Native          (** Host-native binary (arm64-apple-macosx, x86_64-linux, etc.) *)
  | LinuxGnu of { arch : arch; glibc_min : string }
      (** Cross target: dynamic glibc Linux, e.g. x86_64-unknown-linux-gnu *)
  | Wasm64Wasi      (** wasm64-wasi — 8-byte pointers, WASI preview *)
  | Wasm32Wasi      (** wasm32-wasi — 4-byte pointers, WASI preview *)
  | Wasm32Unknown   (** wasm32-unknown-unknown — browser, no WASI *)
  | Js              (** ES module output — no LLVM, no clang *)

let is_wasm_target = function
  | Native | LinuxGnu _ | Js -> false
  | Wasm64Wasi | Wasm32Wasi | Wasm32Unknown -> true

let is_wasm32 = function
  | Wasm32Wasi | Wasm32Unknown -> true
  | _ -> false

external get_native_triple : unit -> string = "march_tir_native_triple"
let native_triple = lazy (get_native_triple ())

let target_triple = function
  | Native          -> Lazy.force native_triple
  | LinuxGnu { arch = X86_64; _ } -> "x86_64-unknown-linux-gnu"
  | LinuxGnu { arch = Arm64;  _ } -> "aarch64-unknown-linux-gnu"
  | Wasm64Wasi      -> "wasm64-wasi"
  | Wasm32Wasi      -> "wasm32-wasi"
  | Wasm32Unknown   -> "wasm32-unknown-unknown"
  | Js              -> "js"

(** Architecture, when meaningful (native's arch is the host, decided by clang). *)
let target_arch = function
  | LinuxGnu { arch; _ } -> Some arch
  | Native | Wasm64Wasi | Wasm32Wasi | Wasm32Unknown | Js -> None

let target_is_linux = function
  | LinuxGnu _ -> true
  | Native | Wasm64Wasi | Wasm32Wasi | Wasm32Unknown | Js -> false

(** zig cc -target string for a cross target, or None for host/wasm/js. *)
let zig_target = function
  | LinuxGnu { arch = X86_64; glibc_min } -> Some ("x86_64-linux-gnu." ^ glibc_min)
  | LinuxGnu { arch = Arm64;  glibc_min } -> Some ("aarch64-linux-gnu." ^ glibc_min)
  | Native | Wasm64Wasi | Wasm32Wasi | Wasm32Unknown | Js -> None

(** Pointer size in bytes for the target. Dead code, carried verbatim from
    [llvm_emit.ml] (Wave 3 Task 7 move): grepped at move time, no caller
    anywhere in the tree — see specs/todos.md filing. *)
let target_ptr_size = function
  | Native | LinuxGnu _ | Wasm64Wasi | Js -> 8
  | Wasm32Wasi | Wasm32Unknown -> 4

(** LLVM pointer type name for the target. Dead code, same as above. *)
let target_ptr_ty = function
  | Native | LinuxGnu _ | Wasm64Wasi | Js -> "ptr"
  | Wasm32Wasi | Wasm32Unknown -> "ptr"

(** LLVM integer type matching pointer width. Dead code, same as above. *)
let target_int_ty = function
  | Native | LinuxGnu _ | Wasm64Wasi | Js -> "i64"
  | Wasm32Wasi | Wasm32Unknown -> "i32"

(** Emit the LLVM preamble (`declare`d externs for the C runtime / every
    builtin). Wave 3 Task 4 (chunk 2): the ~400-line hand-written declare
    blob moved to [Llvm_builtins.emit_preamble] (generated from the same
    table that drives [is_builtin_fn]/[builtin_ret_ty]/[mangle_extern]).
    This wrapper preserves the public signature (default [~target:Native],
    optional [~repl]) and translates [target_config] to the plain
    [is_wasm]/[triple] values Llvm_builtins needs — Llvm_builtins does not
    depend on [target_config] to avoid a module cycle. *)
let emit_preamble ?(target=Native) ?(repl=false) (buf : Buffer.t) =
  Llvm_builtins.emit_preamble ~is_wasm:(is_wasm_target target) ~triple:(target_triple target) ~repl buf

(* ── Leaf-call detection (emit_fn's reduction-check gate) ────────────────
   [is_leaf_callee] / [expr_has_call] have exactly one consumer each,
   forming a chain whose only use is inside [emit_fn] below (Phase 4
   leaf-function detection) — moved together as a unit. *)

(** True if [name] refers to a provably-terminating call site that does not
    need a reduction check: either a March builtin operator or a C-runtime
    function injected by lower_module (identified by the "march_" prefix, e.g.
    march_compare_int, march_hash_int — see [Tir_names.has_runtime_prefix]). *)
let is_leaf_callee (name : string) : bool =
  Llvm_builtins.is_builtin_fn name || Tir_names.has_runtime_prefix name

(** Returns [true] if [e] contains any non-leaf function call (EApp with a
    non-leaf callee, or any ECallPtr indirect call).  Used to decide whether
    to insert a reduction check: functions whose bodies contain no such calls
    are provably-terminating leaf functions and can skip the check. *)
let rec expr_has_call (e : Tir.expr) : bool =
  match e with
  | Tir.EApp (f, _)      -> not (is_leaf_callee f.Tir.v_name)
  | Tir.ECallPtr _       -> true   (* indirect call — always non-trivial *)
  | Tir.ELet (_, e1, e2) -> expr_has_call e1 || expr_has_call e2
  | Tir.ELetRec (fns, e2) ->
      List.exists (fun fn -> expr_has_call fn.Tir.fn_body) fns
      || expr_has_call e2
  | Tir.ECase (_, arms, def) ->
      List.exists (fun (br : Tir.branch) -> expr_has_call br.Tir.br_body) arms
      || (match def with Some d -> expr_has_call d | None -> false)
  | Tir.ESeq (e1, e2)    -> expr_has_call e1 || expr_has_call e2
  | _                    -> false

(* ── Function emitter ────────────────────────────────────────────────── *)

let emit_fn ~emit_expr ctx (fn : Tir.fn_def) =
  Hashtbl.clear ctx.Llvm_ctx.local_names;
  Hashtbl.clear ctx.Llvm_ctx.var_slot;
  Hashtbl.clear ctx.Llvm_ctx.var_llvm_ty;
  ctx.Llvm_ctx.ret_ty <- fn.Tir.fn_ret_ty;
  ctx.Llvm_ctx.cur_emit_fn <- fn.Tir.fn_name;
  ctx.Llvm_ctx.hr_cur_module <- Llvm_ctx.module_of_name fn.Tir.fn_name;
  let fn_llvm_name = Llvm_builtins.mangle_extern fn.Tir.fn_name in
  (* Closure apply wrappers use the generic ptr ABI (see [is_apply_fn]) so a
     single calling convention works regardless of whether the lambda's return
     type was inferred concretely or left polymorphic.  The body result is
     coerced to ptr below (tagging scalars), matching what every call site
     reads.  void wrappers keep void — there is no value to carry. *)
  let ret_ty =
    let base = Llvm_ctx.llvm_ret_ty fn.Tir.fn_ret_ty in
    if Tir_names.is_apply_fn fn.Tir.fn_name && base <> "void" then "ptr" else base
  in

  (* Detect self-tail-recursion: only do TCO when the function calls itself
     in tail position and is not a closure apply fn (those have a clo arg).
     TCO is enabled whenever ANY self-call is in tail position; the back-edge
     transform in emit_expr is gated on [ctx.tco_in_tail] so that NON-tail
     self-calls (which also occur in mixed functions, e.g. the recursive call
     inside `Cons(x, f(t))`) emit an ordinary call instead of a loop back-edge.
     Without that gate the non-tail call would be turned into a back-edge and
     the surrounding construction silently dropped — a miscompile. *)
  let is_tco =
    Llvm_tco.has_self_tail_call fn.Tir.fn_name fn.Tir.fn_body
    && not (Llvm_builtins.is_builtin_fn fn.Tir.fn_name)
  in

  let params_str = String.concat ", " (List.map (fun (v : Tir.var) ->
      let vn = Llvm_ctx.llvm_name v.Tir.v_name in
      Llvm_ctx.llvm_param_ty ~type_defs:ctx.Llvm_ctx.type_defs v.Tir.v_ty ^ " %" ^ vn ^ ".arg"
    ) fn.Tir.fn_params) in

  (* In --compile-so mode, give every non-exported function hidden ELF
     visibility so intra-.so PLT calls resolve to the .so's own definitions
     without going through the process global symbol table (where v1 symbols
     from the server binary would otherwise win).
     Exported symbols that must stay default-visible:
       *_dispatch      — the reload server finds these with dlsym(ACTIVATE)
       *_migrate_state — the __migrate_* alias points to this function; a
                         hidden aliasee with a default-visibility alias is not
                         valid LLVM IR, so keep the migrate_state fn visible
       hr_names members — reloadable boundary functions (e.g. `Server.handle`)
                         must be dlsym-able themselves: any one of them can be
                         the function that changed in a given deploy, and
                         [do_activate] resolves the patch by name. Leaving them
                         default-visible does NOT reopen the "v1 wins" hazard
                         above: every boundary→boundary call in the emitted IR
                         (see [needs_dispatch] in llvm_emit.ml) is rewritten to
                         an indirect call through march_dispatch_enter/_gen,
                         which looks the callee up in the versioned dispatch
                         table by NAME_ID rather than emitting a direct
                         `call @Server.handle` — so there is no direct
                         intra-.so PLT relocation for these names that process
                         symbol resolution order could hijack. hr_names is the
                         app's own boundary set (module_of_name under the
                         --hot-reload prefix), not the whole linked stdlib, so
                         the exemption's blast radius stays small. *)
  let vis_prefix =
    let fname = fn.Tir.fn_name in
    let flen  = String.length fname in
    let ends_with sfx =
      let sl = String.length sfx in
      flen > sl && String.sub fname (flen - sl) sl = sfx
    in
    if ctx.Llvm_ctx.compile_so
       && not (Tir_names.is_actor_dispatch_fn fname)
       && not (ends_with "_migrate_state")
       && Hot_reload.Name_table.id_of ctx.Llvm_ctx.hr_names fname = None
    then "hidden "
    else ""
  in
  Buffer.add_string ctx.Llvm_ctx.buf
    (Printf.sprintf "\ndefine %s%s @%s(%s) {\nentry:\n" vis_prefix ret_ty fn_llvm_name params_str);

  (* Alloca + store for each parameter; collect slot info for TCO. *)
  let param_slots = List.map (fun (v : Tir.var) ->
    let ty = Llvm_ctx.llvm_ty v.Tir.v_ty in
    let slot = Llvm_ctx.alloca_name ctx (Llvm_ctx.llvm_name v.Tir.v_name) in
    Llvm_ctx.emit ctx (Printf.sprintf "%%%s.addr = alloca %s" slot ty);
    Llvm_ctx.emit ctx (Printf.sprintf "store %s %%%s.arg, ptr %%%s.addr" ty (Llvm_ctx.llvm_name v.Tir.v_name) slot);
    Hashtbl.replace ctx.Llvm_ctx.var_llvm_ty slot ty;
    (v.Tir.v_name, slot, ty)
  ) fn.Tir.fn_params in

  (* Phase 4: leaf-function detection.  A function is a leaf if its body
     contains no non-builtin calls and no indirect calls (ECallPtr).  Leaf
     functions are provably-terminating (they finish in O(1) time per call)
     and therefore do not need a reduction check. *)
  let is_leaf = not (expr_has_call fn.Tir.fn_body) in

  if is_tco then begin
    (* Emit: entry → loop.  The loop block header is the back-edge target. *)
    let loop_lbl = Llvm_ctx.fresh_block ctx "tco_loop" in
    Llvm_ctx.emit_term ctx (Printf.sprintf "br label %%%s" loop_lbl);
    Llvm_ctx.emit_label ctx loop_lbl;
    (* Phase 4: decrement the reduction budget at every loop iteration.
       TCO functions are never leaf (they call themselves), so the check is
       always needed here. *)
    Llvm_ctx.emit_reduction_check ctx;
    (* Snapshot the stack pointer at the top of each iteration so that any
       `alloca` textually inside the loop body (case-branch bindings, struct
       construction, etc.) — which LLVM must treat as a fresh dynamic
       allocation on every dynamic execution of the alloca instruction, since
       it cannot prove the loop runs once — gets freed before the next
       iteration via llvm.stackrestore at each back-edge. Without this, stack
       space accumulates unboundedly across iterations and large loops
       (e.g. folding a 10k-element list) crash with a stack overflow despite
       the loop itself being O(1) stack via the back-edge. *)
    let stack_save = Llvm_ctx.fresh ctx "sp.save" in
    Llvm_ctx.emit ctx (Printf.sprintf "%s = call ptr @llvm.stacksave()" stack_save);
    (* Install TCO context so EApp to self emits a back-edge instead of a call. *)
    ctx.Llvm_ctx.tco_fn_name    <- Some fn.Tir.fn_name;
    ctx.Llvm_ctx.tco_loop_label <- loop_lbl;
    ctx.Llvm_ctx.tco_param_info <- param_slots;
    ctx.Llvm_ctx.tco_in_tail    <- true;
    ctx.Llvm_ctx.tco_stack_save <- stack_save;
    let (body_ty, body_val) = emit_expr ctx fn.Tir.fn_body in
    (* Clear TCO state before emitting any other function. *)
    ctx.Llvm_ctx.tco_fn_name <- None;
    ctx.Llvm_ctx.tco_stack_save <- "";
    if ret_ty = "void" then
      Llvm_ctx.emit_term ctx "ret void"
    else begin
      let final_val = Llvm_ctx.coerce ctx body_ty body_val ret_ty in
      Llvm_ctx.emit_term ctx (Printf.sprintf "ret %s %s" ret_ty final_val)
    end
  end else begin
    (* Phase 4: insert the reduction check at function entry for non-leaf
       non-TCO functions.  This fires once per call, counting every function
       invocation against the budget. *)
    if not is_leaf then Llvm_ctx.emit_reduction_check ctx;
    let (body_ty, body_val) = emit_expr ctx fn.Tir.fn_body in
    if ret_ty = "void" then
      Llvm_ctx.emit_term ctx "ret void"
    else begin
      let final_val = Llvm_ctx.coerce ctx body_ty body_val ret_ty in
      Llvm_ctx.emit_term ctx (Printf.sprintf "ret %s %s" ret_ty final_val)
    end
  end;

  Buffer.add_string ctx.Llvm_ctx.buf "}\n"

(** Return the LLVM `declare` string for a function, for use as a forward
    declaration in subsequent JIT fragments that reference it without redefining it. *)
let fn_declare_str (fn : Tir.fn_def) : string =
  let fn_llvm_name = Llvm_builtins.mangle_extern fn.Tir.fn_name in
  let ret_ty = Llvm_ctx.llvm_ret_ty fn.Tir.fn_ret_ty in
  let param_tys = String.concat ", " (List.map (fun (v : Tir.var) ->
      Llvm_ctx.llvm_param_ty v.Tir.v_ty) fn.Tir.fn_params) in
  Printf.sprintf "declare %s @%s(%s)" ret_ty fn_llvm_name param_tys

(* Does [b]'s current contents contain [needle]?  Allocation-free inner
   comparison so a scan over a whole module's IR text stays cheap.  Used only
   by [emit_atom_show_table] to detect a @march_atom_to_string call site. *)
let buffer_contains (b : Buffer.t) (needle : string) : bool =
  let hay = Buffer.contents b in
  let hlen = String.length hay and nlen = String.length needle in
  if nlen = 0 || nlen > hlen then false
  else begin
    let found = ref false and i = ref 0 and last = hlen - nlen in
    while (not !found) && !i <= last do
      let j = ref 0 in
      while !j < nlen && hay.[!i + !j] = needle.[!j] do incr j done;
      if !j = nlen then found := true else incr i
    done;
    !found
  end

(** Show$Atom.show backing: generated hash→name reverse table.

    Atoms compile to nameless FNV-1a i64 hashes (Llvm_ctx.atom_hash), so
    `Show$Atom.show` (registered in lower.ml, body = atom_to_string(x)) can't
    reconstruct `:name` from the runtime value alone.  Rather than a C-side
    registry populated at startup, we emit the whole mapping as one generated
    function — a switch over every atom (hash, name) collected during body
    emission (ctx.atom_names, filled by emit_atom + emit_case).  Returning
    `march_string_lit(":name")` mirrors `march_int_to_string` exactly, so RC
    bookkeeping in the caller is identical to the Int/Float/Bool Show impls.

    Emitted into ctx.extra_fns — which BOTH the AOT finalizer (emit_module) and
    every JIT/REPL emitter flush — so the definition is always co-located with
    the call in the SAME LLVM module (JIT fragments are compiled standalone; a
    call with no in-module definition is a clang error).

    Gated on the CALL actually appearing in this module's emitted code, not on
    Show$Atom.show being emitted as a function: the tiny `atom_to_string(x)`
    body is routinely inlined into its caller, so the wrapper vanishes while the
    call to @march_atom_to_string remains.  Scanning the emitted IR is the
    ground truth.  The `not already-defined` guard makes a second call on the
    same ctx a no-op (can't double-define the symbol or its globals). *)
let emit_atom_show_table ctx =
  let call_site = "call ptr @march_atom_to_string" in
  let referenced =
    buffer_contains ctx.Llvm_ctx.buf call_site
    || buffer_contains ctx.Llvm_ctx.extra_fns call_site
  in
  let already_defined =
    buffer_contains ctx.Llvm_ctx.extra_fns "define ptr @march_atom_to_string"
  in
  if referenced && not already_defined then begin
    (* Sort by hash for deterministic IR (Hashtbl.fold order is unspecified),
       keeping the CAS content hash stable across identical inputs. *)
    let atoms =
      Hashtbl.fold (fun h name acc -> (h, name) :: acc) ctx.Llvm_ctx.atom_names []
      |> List.sort (fun (a, _) (b, _) -> Int64.compare a b)
    in
    let b = ctx.Llvm_ctx.extra_fns in
    List.iteri (fun i (_, name) ->
        let s = ":" ^ name in
        Printf.bprintf b
          "@.atomname_%d = private unnamed_addr constant [%d x i8] c\"%s\\00\"\n"
          i (String.length s + 1) (Llvm_ctx.llvm_escape_string s)
      ) atoms;
    (* Fallback for any hash not statically known (e.g. a runtime-produced atom
       whose name never appears in source, or a cross-fragment REPL atom). *)
    Buffer.add_string b
      "@.atomname_unknown = private unnamed_addr constant [8 x i8] c\":<atom>\\00\"\n";
    Buffer.add_string b "define ptr @march_atom_to_string(i64 %h) {\nentry:\n";
    Buffer.add_string b "  switch i64 %h, label %atom_unknown [\n";
    List.iteri (fun i (h, _) ->
        Printf.bprintf b "    i64 %Ld, label %%atom_%d\n" h i
      ) atoms;
    Buffer.add_string b "  ]\n";
    List.iteri (fun i (_, name) ->
        let s = ":" ^ name in
        Printf.bprintf b
          "atom_%d:\n\
          \  %%s%d = call ptr @march_string_lit(ptr @.atomname_%d, i64 %d)\n\
          \  ret ptr %%s%d\n"
          i i i (String.length s) i
      ) atoms;
    Buffer.add_string b
      "atom_unknown:\n\
      \  %su = call ptr @march_string_lit(ptr @.atomname_unknown, i64 7)\n\
      \  ret ptr %su\n";
    Buffer.add_string b "}\n"
  end

(* emit_mutual_tco_group moved to [Llvm_tco] (Wave 3 Task 6, chunk 2).
   Its single call site (emit_module, below) passes emit_expr as a labeled
   callback and qualifies the reference: see Llvm_tco.emit_mutual_tco_group. *)

(* ── Module emitter ──────────────────────────────────────────────────── *)

let build_ctor_info ctx (m : Tir.tir_module) =
  (* Finding-19 memory-safety fix: actor message variant constructors
     (<Actor>_Msg) get GLOBALLY-unique heap tags across all actors, not the
     per-variant 0-based tag ordinary ADTs use.  Rationale: a message meant for
     actor B may be delivered to actor A's mailbox (send does not gate by
     target actor — a separate, deferred type-system gap).  With per-actor
     0-based tags, B's first message ctor and A's first message ctor both carry
     tag 0, so A's dispatch ECase reads tag 0 and MISROUTES B's payload into A's
     first handler at the wrong type (memory-unsafe).  A global tag makes B's
     ctor tag distinct from every one of A's, so it falls to A's dispatch
     default arm and is dropped (parity with the interpreter's silent drop).
     Base is well clear of small-ADT tags and of MARCH_MIGRATE_TAG
     (0x4D494752); i32 header field, so ~0x60000000 headroom remains. *)
  let actor_msg_tag = ref 0x0100_0000 in
  List.iter (fun td ->
    match td with
    | Tir.TDVariant (_name, ctors) when Tir_names.is_actor_msg_name _name ->
      (* Actor message type: assign global tags, but otherwise identical to the
         generic TDVariant arm (type_params + qualified ctor_info key +
         poly_ctors), so send-site EAlloc and dispatch ECase resolve the same
         ce_tag from the same key. *)
      let seen = Hashtbl.create 4 in
      let params = ref [] in
      let rec collect_tvars = function
        | Tir.TVar n ->
          if not (Hashtbl.mem seen n) then begin
            Hashtbl.add seen n (); params := n :: !params
          end
        | Tir.TCon (_, args) -> List.iter collect_tvars args
        | Tir.TFn (ps, r)   -> List.iter collect_tvars ps; collect_tvars r
        | Tir.TTuple ts     -> List.iter collect_tvars ts
        | Tir.TPtr t        -> collect_tvars t
        | _                 -> ()
      in
      List.iter (fun (_, field_tys) -> List.iter collect_tvars field_tys) ctors;
      Hashtbl.replace ctx.Llvm_ctx.type_params _name (List.rev !params);
      List.iter (fun (ctor_name, field_tys) ->
        let g = !actor_msg_tag in
        incr actor_msg_tag;
        let key = _name ^ "." ^ ctor_name in
        if not (Hashtbl.mem ctx.Llvm_ctx.ctor_info key) then
          Hashtbl.replace ctx.Llvm_ctx.ctor_info key { Llvm_ctx.ce_tag = g; ce_fields = field_tys };
        if not (Hashtbl.mem ctx.Llvm_ctx.poly_ctors (_name, ctor_name)) then
          Hashtbl.replace ctx.Llvm_ctx.poly_ctors (_name, ctor_name) field_tys
      ) ctors
    | Tir.TDVariant (_name, ctors) ->
      (* Collect free type-variable names in declaration order for poly resolution *)
      let seen = Hashtbl.create 4 in
      let params = ref [] in
      let rec collect_tvars = function
        | Tir.TVar n ->
          if not (Hashtbl.mem seen n) then begin
            Hashtbl.add seen n ();
            params := n :: !params
          end
        | Tir.TCon (_, args) -> List.iter collect_tvars args
        | Tir.TFn (ps, r)   -> List.iter collect_tvars ps; collect_tvars r
        | Tir.TTuple ts     -> List.iter collect_tvars ts
        | Tir.TPtr t        -> collect_tvars t
        | _                 -> ()
      in
      List.iter (fun (_, field_tys) -> List.iter collect_tvars field_tys) ctors;
      let param_names = List.rev !params in
      Hashtbl.replace ctx.Llvm_ctx.type_params _name param_names;
      List.iteri (fun tag_idx (ctor_name, field_tys) ->
        (* Use a type-qualified key "TypeName.CtorName" so that two different
           ADTs with the same constructor name (e.g. List.Cons and Tree.Cons)
           never collide in ctor_info.  lower.ml embeds the same qualified key
           in EAlloc (TCon ("TypeName.CtorName", [])), and emit_case qualifies
           br_tag with scrut_tir_ty before the lookup.
           Use first-wins semantics to avoid collisions when two types from
           different modules share the same short name (e.g. Depot.Query.Query
           and Ast.Query both lower to TDVariant("Query", ...)). *)
        let key = _name ^ "." ^ ctor_name in
        if not (Hashtbl.mem ctx.Llvm_ctx.ctor_info key) then
          Hashtbl.replace ctx.Llvm_ctx.ctor_info key { Llvm_ctx.ce_tag = tag_idx; ce_fields = field_tys };
        if not (Hashtbl.mem ctx.Llvm_ctx.poly_ctors (_name, ctor_name)) then
          Hashtbl.replace ctx.Llvm_ctx.poly_ctors (_name, ctor_name) field_tys
      ) ctors
    | Tir.TDRecord (_name, fields) ->
      Hashtbl.replace ctx.Llvm_ctx.ctor_info _name
        { Llvm_ctx.ce_tag = 0; ce_fields = List.map snd fields };
      Hashtbl.replace ctx.Llvm_ctx.field_map _name fields
    | Tir.TDClosure (_name, field_tys) ->
      Hashtbl.replace ctx.Llvm_ctx.ctor_info _name
        { Llvm_ctx.ce_tag = 0; ce_fields = field_tys }
  ) m.Tir.tm_types

(** Dead code, carried verbatim from [llvm_emit.ml] (Wave 3 Task 7 move):
    no caller exists anywhere in the tree (grepped at move time). Not a
    behavior change to leave in place — see specs/todos.md filing. *)
let emit_main_wrapper (buf : Buffer.t) =
  Buffer.add_string buf
    "\ndeclare void @march_process_argv_init(i32 %argc, ptr %argv)\n\
     declare void @march_spawn_main(ptr %fn)\n\
     define i32 @main(i32 %argc, ptr %argv) {\nentry:\n\
       call void @march_process_argv_init(i32 %argc, ptr %argv)\n\
       call void @march_spawn_main(ptr @march_main)\n\
       call void @march_run_scheduler()\n\
       ret i32 0\n}\n"

let emit_module ~emit_expr
    ?(fast_math=false) ?(pmap_threshold=1024) ?(target=Native)
    ?(hot_reload=None) ?(impl_hashes=(Hashtbl.create 0 : (string, string) Hashtbl.t))
    ?(remote_impl_hashes=(Hashtbl.create 0 : (string, string) Hashtbl.t))
    ?(remote_sig_hashes=(Hashtbl.create 0 : (string, string) Hashtbl.t))
    ?(emit_main=true)
    (m : Tir.tir_module) : string =
  (* type defs are threaded via ctx.type_defs (set below); reset the
     repr-consistency audit per module emission. *)
  Hashtbl.reset Llvm_ctx._repr_audit;
  (* Hot Code Reload: intern the names of every reloadable (boundary) function
     into NAME_IDs for the dispatch table.
     Actor dispatch functions (e.g. Counter_dispatch) have no module prefix in
     TIR because lower.ml strips the top-level file-module name from all
     declarations (only nested submodule functions retain their prefix).
     We include any *_dispatch function unconditionally so that actor hot-reload
     works when the --hot-reload boundary is the file-level module. *)
  let is_actor_dispatch_fn = Tir_names.is_actor_dispatch_fn in
  (* Program-entry functions must NEVER be reloadable slots.  The running green
     thread's root frame is the chosen entry (`main`/`ModName.main`, emitted as
     @march_main); swapping it while live corrupts the runtime allocator (OOM).
     But in the standard hot-reload layout the real entry is a shim
     (HotEntry.main → App.main), so App.main — the app's own `main` that runs the
     never-returning accept loop — is permanently on the call stack too.  Both
     are named `main` (bare or `.main`-suffixed), so we exclude EVERY such
     function from the boundary, not just the single compiler-chosen entry. *)
  let is_entry_fn (n : string) =
    String.equal n "main"
    || (String.length n > 5
        && String.equal (String.sub n (String.length n - 5) 5) ".main")
  in
  let hr_names =
    match hot_reload with
    | None -> Hot_reload.Name_table.build []
    | Some cfg ->
      m.Tir.tm_fns
      |> List.filter_map (fun fn ->
           let n = fn.Tir.fn_name in
           if is_entry_fn n then None
           else if Hot_reload.is_reloadable cfg (Llvm_ctx.module_of_name n)
              || is_actor_dispatch_fn n
           then Some n else None)
      |> Hot_reload.Name_table.build
  in
  let ctx = Llvm_ctx.make_ctx ~fast_math ~pmap_threshold ~hot_reload ~hr_names
      ~type_defs:m.Tir.tm_types () in
  (* Patch .so: hide all non-exported symbols so intra-.so PLT calls prefer the
     .so's own definitions over same-named symbols in the server binary.  This
     is the compile-time complement to RTLD_DEEPBIND (which is Linux-only). *)
  let ctx = { ctx with Llvm_ctx.compile_so = not emit_main } in
  (* Phase 9: in .so patch mode WITH hot-reload enabled, emit the file-static
     epoch cell into the preamble.  Static (private) linkage keeps it out of
     the global symbol table so multiple deployed .so files don't collide.
     @__march_init (exported) lets the reload server stamp the epoch after
     dlopen via dlsym(handle,"__march_init").
     Guard on hr_config <> None: a --compile-so build without --hot-reload
     must not export a spurious epoch entry point. *)
  if ctx.Llvm_ctx.compile_so && hot_reload <> None then
    Buffer.add_string ctx.Llvm_ctx.preamble
      "@__march_hcr_epoch = private global i32 0\n";
  (* Distributed OTP L4: populate CAS hash maps for remote_ref_hashes constant folding. *)
  Hashtbl.iter (Hashtbl.replace ctx.Llvm_ctx.remote_impl_hashes) remote_impl_hashes;
  Hashtbl.iter (Hashtbl.replace ctx.Llvm_ctx.remote_sig_hashes)  remote_sig_hashes;
  (* Hot Code Reload: IR run in @main (before user main spawns) that sizes the
     dispatch table and publishes each boundary function as its NATIVE baseline
     version. Each boundary fn's per-definition impl_hash (a Merkle root over its
     call graph + type usage, from the CAS) is emitted as a private NUL-terminated
     string global and passed to march_dispatch_publish so the runtime can match a
     hot-swap candidate against the running baseline. When no hash is known (e.g.
     a non-CAS build path) the baseline is published with a null impl_hash and the
     reload server stamps the real hash on activation; see runtime/march_dispatch.c. *)
  let hr_setup =
    match hot_reload with
    | None -> ""
    | Some _cfg ->
      let n = Hot_reload.Name_table.count hr_names in
      if n = 0 then "" else begin
        let b = Buffer.create 256 in
        (* Dispatch slot IDs are 1-based: slot 0 is reserved as the "not set"
           sentinel in march_actor_meta.dispatch_name_id (0 = no HCR dispatch). *)
        Printf.bprintf b "  call void @march_dispatch_init(i32 %d)\n" (n + 1);
        List.iter (fun (fn : Tir.fn_def) ->
          match Hot_reload.Name_table.id_of hr_names fn.Tir.fn_name with
          | None -> ()
          | Some id0 ->
              let id = id0 + 1 in  (* shift to 1-based *)
              (* Emit the impl_hash (if known) as a private string global and
                 pass its ptr; otherwise fall back to a null baseline hash. *)
              let hash_arg =
                match Hashtbl.find_opt impl_hashes fn.Tir.fn_name with
                | Some h when String.length h > 0 ->
                  let g = Printf.sprintf "@.hr_hash%d" id in
                  Buffer.add_string ctx.Llvm_ctx.preamble
                    (Printf.sprintf
                       "%s = private unnamed_addr constant [%d x i8] c\"%s\\00\"\n"
                       g (String.length h + 1) (Llvm_ctx.llvm_escape_string h));
                  Printf.sprintf "ptr %s" g
                | _ -> "ptr null"
              in
              let sig_arg =
                match Hashtbl.find_opt ctx.Llvm_ctx.remote_sig_hashes fn.Tir.fn_name with
                | Some h when String.length h > 0 ->
                  let sg = Printf.sprintf "@.hr_sighash%d" id in
                  Buffer.add_string ctx.Llvm_ctx.preamble
                    (Printf.sprintf
                       "%s = private unnamed_addr constant [%d x i8] c\"%s\\00\"\n"
                       sg (String.length h + 1) (Llvm_ctx.llvm_escape_string h));
                  Printf.sprintf "ptr %s" sg
                | _ -> "ptr null"
              in
              Printf.bprintf b
                "  call i32 @march_dispatch_publish(i32 %d, ptr @%s, %s, %s, i8 0)\n"
                id (Llvm_builtins.mangle_extern fn.Tir.fn_name) hash_arg sig_arg;
              (* Register name→ID mapping for the reload server. *)
              let name_g = Printf.sprintf "@.hr_name%d" id in
              Buffer.add_string ctx.Llvm_ctx.preamble
                (Printf.sprintf
                   "%s = private unnamed_addr constant [%d x i8] c\"%s\\00\"\n"
                   name_g (String.length fn.Tir.fn_name + 1)
                   (Llvm_ctx.llvm_escape_string fn.Tir.fn_name));
              Printf.bprintf b
                "  call void @march_dispatch_register_name(i32 %d, ptr %s)\n"
                id name_g
        ) m.Tir.tm_fns;
        (* Start the reload server if MARCH_HOT_RELOAD_SOCKET is set. *)
        Buffer.add_string ctx.Llvm_ctx.preamble
          "@.hr_sock_env = private unnamed_addr constant [24 x i8] c\"MARCH_HOT_RELOAD_SOCKET\\00\"\n";
        Buffer.add_string b
          "  %hr_sock_ptr = call ptr @getenv(ptr @.hr_sock_env)\n\
          \  call void @march_reload_server_start(ptr %hr_sock_ptr)\n";
        Buffer.contents b
      end
  in
  (* Record shape metadata requires the native runtime (march_extras.c);
     the WASM runtime does not provide march_record_set_shape. *)
  ctx.Llvm_ctx.shape_meta <- not (is_wasm_target target);
  build_ctor_info ctx m;
  (* Register user-defined extern functions *)
  List.iter (fun (ed : Tir.extern_decl) ->
      Hashtbl.replace ctx.Llvm_ctx.extern_map ed.ed_march_name ed.ed_c_name;
      if ed.ed_blocking then Hashtbl.replace ctx.Llvm_ctx.blocking_externs ed.ed_march_name ();
      if ed.ed_raises then Hashtbl.replace ctx.Llvm_ctx.raises_externs ed.ed_march_name ();
      Hashtbl.replace ctx.Llvm_ctx.top_fns ed.ed_march_name true;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_ret_ty ed.ed_march_name ed.ed_ret;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_nparams ed.ed_march_name (List.length ed.ed_params)
    ) m.Tir.tm_externs;
  List.iter (fun fn ->
      Hashtbl.replace ctx.Llvm_ctx.top_fns fn.Tir.fn_name true;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_ret_ty fn.Tir.fn_name fn.Tir.fn_ret_ty;
      Hashtbl.replace ctx.Llvm_ctx.top_fn_nparams fn.Tir.fn_name (List.length fn.Tir.fn_params);
      if fn.Tir.fn_params = [] then
        Hashtbl.replace ctx.Llvm_ctx.zero_arg_fns fn.Tir.fn_name true;
      (* Populate unqualified_fns: maps the unqualified suffix (e.g.
         "base64_encode") to the fully qualified name ("Crypto.base64_encode").
         Used to fix up cross-module ECallPtr calls where lower.ml left the
         function name unqualified.  First registration wins to avoid
         collisions between modules sharing an unqualified name.
         NOTE: we do NOT add the unqualified name to top_fns — that would
         shadow local variables with the same name (e.g. a boolean variable
         named "abs" would incorrectly resolve to @Math.abs).

         EXCLUDE interface-impl-mangled names ("Iface$Type.method", e.g.
         "Show$List.show" or a further-specialized "Show$List.show$List_Int")
         from this map (Wave 2 Task 1 — defense in depth for the
         println-of-list miscompile).  mono.ml now propagates the
         substitution when it enqueues a resolved impl, so a nested
         `show(x)` call inside `impl Show(List(a)) when Show(a)` should
         ALWAYS be resolved to the concrete impl (e.g. Show$Int.show) by
         mono before reaching llvm_emit.  If mono ever regresses and leaves
         a bare interface-method call unresolved again, this map must NOT
         silently rebind it to an arbitrary same-named impl (that was the
         actual bug — a bare `show` got hijacked to `Show$List.show`,
         the LIST impl applied to a raw element).  Detected by checking for
         a '$' before the LAST '.' — ordinary qualified names ("Crypto.
         base64_encode", "App.Core.b") never contain '$', so they are
         unaffected. *)
      (match String.rindex_opt fn.Tir.fn_name '.' with
       | Some i ->
         if not (Tir_names.is_iface_mangled fn.Tir.fn_name) then begin
           let unq = String.sub fn.Tir.fn_name (i+1)
                       (String.length fn.Tir.fn_name - i - 1) in
           if not (Hashtbl.mem ctx.Llvm_ctx.unqualified_fns unq) then begin
             Hashtbl.replace ctx.Llvm_ctx.unqualified_fns unq fn.Tir.fn_name
           end
         end
       | None -> ()))
    m.Tir.tm_fns;
  (* Identify mutual-TCO groups.  Functions in these groups are emitted as
     combined dispatch functions + thin wrappers — they must NOT also be
     emitted individually via emit_fn. *)
  let mutual_groups = Llvm_tco.find_mutual_tco_groups m.Tir.tm_fns in
  let mutual_fn_names =
    List.concat_map (fun g -> List.map (fun fn -> fn.Tir.fn_name) g)
      mutual_groups
  in
  (* Emit the combined function + wrappers for each mutual-TCO group.
     emit_expr is passed as a labeled callback (de-cycling move, Wave 3
     Task 6, chunk 2 — same pattern as Llvm_case.emit_case in Task 5). *)
  List.iter (Llvm_tco.emit_mutual_tco_group ~emit_expr ctx) mutual_groups;

  (* Skip emitting prelude wrapper functions whose runtime name is already
     declared in the preamble.  Only filter short unqualified names that map
     to march_* builtins — not user-defined qualified names like "CapDemo.main".
     Also skip functions that are members of a mutual-TCO group — those were
     already emitted (as wrappers) by emit_mutual_tco_group above. *)
  let preamble_declared = ["panic"; "panic_"; "todo_"; "unreachable_";
                           "println"; "print"; "print_stderr"; "io_read_line"; "read_line";
                           "io_read_byte"; "read_byte"] in
  let migrate_suffix = "_migrate_state" in
  let migrate_suffix_len = String.length migrate_suffix in
  List.iter (fun fn ->
      if List.mem fn.Tir.fn_name preamble_declared then ()
      else if List.mem fn.Tir.fn_name mutual_fn_names then ()
      else begin
        let fname = fn.Tir.fn_name in
        let flen = String.length fname in
        emit_fn ~emit_expr ctx fn;
        (* Phase 5: for migrate_state functions, export a __migrate_<Actor>
           alias so march_reload.c can dlsym it without knowing the full
           mangled March name.
           Convention: fn counter_migrate_state inside mod MyApp →
             TIR name "MyApp.counter_migrate_state"
             → strip "_migrate_state" → "MyApp.counter"
             → last dot-component → "counter"
             → capitalize first letter → "Counter"
             → alias "@__migrate_Counter"
           The march_reload.c runtime forms the same name by stripping
           "_dispatch" from the ACTIVATE name "Counter_dispatch". *)
        if flen > migrate_suffix_len
           && String.sub fname (flen - migrate_suffix_len) migrate_suffix_len = migrate_suffix
        then begin
          (* Take the part before _migrate_state, then extract the last
             dot-separated component (strips module prefix), then capitalize
             the first letter to recover the actor name. *)
          let before_suffix = String.sub fname 0 (flen - migrate_suffix_len) in
          let last_component =
            match String.rindex_opt before_suffix '.' with
            | None   -> before_suffix
            | Some i -> String.sub before_suffix (i + 1)
                          (String.length before_suffix - i - 1)
          in
          if last_component <> "" then begin
            let actor_name =
              (String.uppercase_ascii (String.sub last_component 0 1))
              ^ (String.sub last_component 1 (String.length last_component - 1))
            in
            let alias_name   = "__migrate_" ^ actor_name in
            let llvm_fn_name = Llvm_builtins.mangle_extern fname in
            (* LLVM alias: same signature as migrate_state (ptr → ptr) *)
            Buffer.add_string ctx.Llvm_ctx.buf (Printf.sprintf
              "@%s = alias ptr (ptr), ptr @%s\n" alias_name llvm_fn_name)
          end
        end
      end
    ) m.Tir.tm_fns;

  let out = Buffer.create 8192 in
  emit_preamble ~target out;
  (* Emit user-defined extern function declarations *)
  List.iter (fun (ed : Tir.extern_decl) ->
      (* A `raises` binding takes a hidden march_env* first param and returns the
         bare Ok payload (T of Result(T,E)); the call site wraps it into Ok/Err. *)
      let ret_llty =
        if ed.ed_raises then Llvm_ctx.llvm_ret_ty (Llvm_calls.ok_payload_ty ed.ed_ret)
        else Llvm_ctx.llvm_ret_ty ed.ed_ret in
      let param_lltys = List.map (fun _t -> "ptr") ed.ed_params in
      let param_lltys = if ed.ed_raises then "ptr" :: param_lltys else param_lltys in
      let params_str = String.concat ", " (List.mapi (fun i ty ->
          Printf.sprintf "%s %%%d" ty i) param_lltys) in
      Buffer.add_string out
        (Printf.sprintf "declare %s @%s(%s)\n" ret_llty ed.ed_c_name params_str)
    ) m.Tir.tm_externs;
  (* Blocking-dispatch helpers, if any extern is `blocking`. *)
  if List.exists (fun (ed : Tir.extern_decl) -> ed.ed_blocking) m.Tir.tm_externs then
    Buffer.add_string out
      "declare i64 @march_run_blocking_i(ptr, ptr, i32)\n\
       declare double @march_run_blocking_d(ptr, ptr, i32)\n";
  (* Error-protocol Ok/Err constructors, if any extern is `raises` (the call-site
     wrapper calls them; march_raise itself is called only from the C binding). *)
  if List.exists (fun (ed : Tir.extern_decl) -> ed.ed_raises) m.Tir.tm_externs then
    Buffer.add_string out
      "declare ptr @march_ok(i64)\n\
       declare ptr @march_err(i64)\n\
       declare i64 @march_make_float(double)\n";
  Buffer.add_buffer out ctx.Llvm_ctx.preamble;
  Buffer.add_buffer out ctx.Llvm_ctx.buf;

  (* Distributed OTP L4 — Compiler-emitted enroll/stub.
     Scan for functions whose name ends in "__rpc_stub".  For each one, emit
     string constants for the base function's impl_hash / sig_hash (if known
     from the CAS pipeline) and collect a march_remote_register call that goes
     inside @main, between march_remote_init() and march_spawn_main(). *)
  let stub_suffix = "__rpc_stub" in
  let stub_suffix_len = String.length stub_suffix in
  let stub_setup =
    let b = Buffer.create 256 in
    List.iteri (fun i (fn : Tir.fn_def) ->
      let name = fn.Tir.fn_name in
      let nlen = String.length name in
      if nlen > stub_suffix_len &&
         String.sub name (nlen - stub_suffix_len) stub_suffix_len = stub_suffix
      then begin
        let base = String.sub name 0 (nlen - stub_suffix_len) in
        match Hashtbl.find_opt ctx.Llvm_ctx.remote_impl_hashes base,
              Hashtbl.find_opt ctx.Llvm_ctx.remote_sig_hashes base with
        | Some impl_h, Some sig_h when String.length impl_h > 0 ->
          let mangled_stub = Llvm_ctx.llvm_name (Llvm_builtins.mangle_extern name) in
          let impl_esc = Llvm_ctx.llvm_escape_string impl_h in
          let sig_esc  = Llvm_ctx.llvm_escape_string sig_h in
          Printf.bprintf out
            "@.rpc_impl_%d = private unnamed_addr constant [%d x i8] c\"%s\\00\"\n"
            i (String.length impl_h + 1) impl_esc;
          Printf.bprintf out
            "@.rpc_sig_%d = private unnamed_addr constant [%d x i8] c\"%s\\00\"\n"
            i (String.length sig_h + 1) sig_esc;
          Printf.bprintf b
            "  call i32 @march_remote_register(ptr @.rpc_impl_%d, ptr @.rpc_sig_%d, ptr @%s)\n"
            i i mangled_stub
        | _ -> ()
      end
    ) m.Tir.tm_fns;
    Buffer.contents b
  in

  (* Find a main function: either top-level "main" or "ModName.main".
     Use fold_left (last match wins) so that when multiple modules define
     fn main(), the entry file's module takes precedence.  The entry file's
     declarations are injected last into mod_decls, so its functions appear
     last in tm_fns — fold_left keeps the last match. *)
  let main_fn_name = List.fold_left (fun acc (fn : Tir.fn_def) ->
      if fn.Tir.fn_name = "main" then Some "main"
      else if String.length fn.Tir.fn_name > 5 &&
              String.sub fn.Tir.fn_name
                (String.length fn.Tir.fn_name - 5) 5 = ".main"
      then Some fn.Tir.fn_name
      else acc
    ) None m.Tir.tm_fns in

  (* Entry point: for native targets emit @main calling march_main + scheduler;
     for WASM browser target (Wasm32Unknown), emit exported island entry points
     that the JS runtime can call. *)
  (match target with
   | Wasm32Unknown ->
     (* For WASM islands, export the render/update functions.
        The island name is derived from the module name.
        The user's module must define render(state) and update(state, msg). *)
     (* Find a function by base name, handling mono suffixes like render$String.
        Only matches the user's own module (tm_name.suffix) or bare names —
        NOT functions from other modules like Vault.update. *)
     let find_fn suffix =
       List.find_opt (fun (fn : Tir.fn_def) ->
         let n = fn.Tir.fn_name in
         (* Strip monomorphization suffix (e.g. render$String → render) *)
         let base = match String.index_opt n '$' with
           | Some i -> String.sub n 0 i
           | None -> n
         in
         base = suffix ||
         base = m.Tir.tm_name ^ "." ^ suffix
       ) m.Tir.tm_fns
     in
     let emit_island_export export_name march_fn_name params ret_ty =
       let mangled = Llvm_ctx.llvm_name (Llvm_builtins.mangle_extern march_fn_name) in
       let param_decls = String.concat ", " (List.mapi (fun i ty ->
           Printf.sprintf "%s %%%d" ty i) params) in
       let param_refs = String.concat ", " (List.mapi (fun i ty ->
           Printf.sprintf "%s %%%d" ty i) params) in
       Buffer.add_string out
         (Printf.sprintf "\ndefine dllexport %s @%s(%s) {\nentry:\n  %%r = call %s @%s(%s)\n  ret %s %%r\n}\n"
            ret_ty export_name param_decls ret_ty mangled param_refs ret_ty)
     in
     (match find_fn "render" with
      | Some fn ->
        emit_island_export "march_island_render" fn.Tir.fn_name ["ptr"] "ptr"
      | None -> ());
     (match find_fn "update" with
      | Some fn ->
        emit_island_export "march_island_update" fn.Tir.fn_name ["ptr"; "ptr"] "ptr"
      | None -> ());
     (* march_island_init: if there's an init() function, export it;
        otherwise generate a stub that returns null (use SSR state). *)
     (match find_fn "init" with
      | Some fn ->
        let mangled = Llvm_ctx.llvm_name (Llvm_builtins.mangle_extern fn.Tir.fn_name) in
        Buffer.add_string out
          (Printf.sprintf "\ndefine dllexport ptr @march_island_init() {\nentry:\n  %%r = call ptr @%s()\n  ret ptr %%r\n}\n" mangled)
      | None ->
        Buffer.add_string out
          "\ndefine dllexport ptr @march_island_init() {\nentry:\n  ret ptr null\n}\n");
     (* Re-export march_alloc and march_free for JS glue *)
     Buffer.add_string out
       "\ndefine dllexport void @march_dealloc(ptr %p) {\nentry:\n  call void @march_free(ptr %p)\n  ret void\n}\n";
     Buffer.add_string out
       "\ndefine dllexport ptr @march_alloc_export(i64 %sz) {\nentry:\n  %r = call ptr @march_alloc(i64 %sz)\n  ret ptr %r\n}\n";
     Buffer.add_string out
       "\ndefine dllexport ptr @march_string_lit_export(ptr %s, i64 %len) {\nentry:\n  %r = call ptr @march_string_lit(ptr %s, i64 %len)\n  ret ptr %r\n}\n";
     (* march_island_render_html: calls render + iolist_flatten, returns a flat String *)
     (match find_fn "render" with
      | Some fn ->
        let mangled = Llvm_ctx.llvm_name (Llvm_builtins.mangle_extern fn.Tir.fn_name) in
        Buffer.add_string out
          (Printf.sprintf "\ndeclare ptr @march_iolist_flatten(ptr)\ndeclare i32 @march_string_length_i32(ptr)\ndeclare ptr @march_string_data_ptr(ptr)\n\ndefine dllexport ptr @march_island_render_html(ptr %%state) {\nentry:\n  %%iolist = call ptr @%s(ptr %%state)\n  %%str = call ptr @march_iolist_flatten(ptr %%iolist)\n  ret ptr %%str\n}\n\ndefine dllexport i32 @march_island_string_length(ptr %%str) {\nentry:\n  %%r = call i32 @march_string_length_i32(ptr %%str)\n  ret i32 %%r\n}\n\ndefine dllexport ptr @march_island_string_data(ptr %%str) {\nentry:\n  %%r = call ptr @march_string_data_ptr(ptr %%str)\n  ret ptr %%r\n}\n" mangled)
      | None -> ());
     (* march_island_msg_from_name: construct a Msg variant from its name string.
        Emits a chain of string comparisons for all zero-field (enum) Msg constructors.
        Variants with fields are not supported here — use JSON wire format instead. *)
     let msg_type_opt = List.find_opt (fun td ->
       match td with
       | Tir.TDVariant (name, _) ->
         (* Strip module prefix, e.g. "Counter.Msg" -> "Msg" *)
         let base = match String.rindex_opt name '.' with
           | Some i -> String.sub name (i+1) (String.length name - i - 1)
           | None -> name
         in
         (* Strip mono suffix like Msg$0 *)
         let base2 = match String.index_opt base '$' with
           | Some i -> String.sub base 0 i
           | None -> base
         in
         base2 = "Msg"
       | _ -> false
     ) m.Tir.tm_types in
     (match msg_type_opt with
      | Some (Tir.TDVariant (_, ctors)) ->
        (* Filter to enum constructors (no fields) *)
        let enum_ctors = List.filter (fun (_, fields) -> fields = []) ctors in
        if enum_ctors <> [] then begin
          let buf2 = Buffer.create 512 in
          (* Emit string constants for each constructor name *)
          List.iter (fun (name, _) ->
            (* Strip module prefix from ctor name *)
            let base_name = match String.rindex_opt name '.' with
              | Some i -> String.sub name (i+1) (String.length name - i - 1)
              | None -> name
            in
            Buffer.add_string buf2
              (Printf.sprintf "@.msg_name_%s = private constant [%d x i8] c\"%s\\00\"\n"
                 base_name (String.length base_name + 1) base_name)
          ) enum_ctors;
          Buffer.add_string buf2
            "\ndeclare i64 @march_string_eq(ptr, ptr)\n";
          Buffer.add_string buf2
            "\ndeclare i64 @march_poly_eq(ptr, ptr)\n";
          Buffer.add_string buf2
            "\ndefine dllexport ptr @march_island_msg_from_name(ptr %data, i32 %len) {\nentry:\n";
          (* Allocate a temporary string for the input *)
          Buffer.add_string buf2
            "  %ilen = sext i32 %len to i64\n  %tmp = call ptr @march_string_lit(ptr %data, i64 %ilen)\n";
          List.iteri (fun i (name, _) ->
            let base_name = match String.rindex_opt name '.' with
              | Some j -> String.sub name (j+1) (String.length name - j - 1)
              | None -> name
            in
            let nlen = String.length base_name in
            Buffer.add_string buf2
              (Printf.sprintf "  %%slit%d = call ptr @march_string_lit(ptr @.msg_name_%s, i64 %d)\n"
                 i base_name nlen);
            Buffer.add_string buf2
              (Printf.sprintf "  %%eq%d = call i64 @march_string_eq(ptr %%slit%d, ptr %%tmp)\n" i i);
            Buffer.add_string buf2
              (Printf.sprintf "  %%b%d = icmp ne i64 %%eq%d, 0\n" i i);
            Buffer.add_string buf2
              (Printf.sprintf "  br i1 %%b%d, label %%match%d, label %%next%d\n" i i i);
            Buffer.add_string buf2
              (Printf.sprintf "match%d:\n  %%cell%d = call ptr @march_alloc(i64 16)\n" i i);
            Buffer.add_string buf2
              (Printf.sprintf "  %%tp%d = getelementptr i8, ptr %%cell%d, i64 8\n" i i);
            Buffer.add_string buf2
              (Printf.sprintf "  store i32 %d, ptr %%tp%d\n  ret ptr %%cell%d\nnext%d:\n" i i i i)
          ) enum_ctors;
          (* Default: return null (unknown message) *)
          Buffer.add_string buf2 "  ret ptr null\n}\n";
          Buffer.add_string out (Buffer.contents buf2)
        end
      | _ -> ());
     (* If there's a main function, still call it for module-level init *)
     (match main_fn_name with
      | Some name ->
        let mangled = Llvm_ctx.llvm_name (Llvm_builtins.mangle_extern name) in
        Buffer.add_string out
          (Printf.sprintf "\ndefine dllexport void @_start() {\nentry:\n  call void @%s()\n  ret void\n}\n" mangled)
      | None -> ())
   | _ ->
     (* Native / WASI: test-runner @main (when tm_tests populated) or standard @main.
        Suppressed when emit_main=false (--compile-so: patch shared library). *)
     if not emit_main && hot_reload <> None then begin
       (* Phase 9: exported init function so the reload server can stamp the epoch.
          Only emitted when --hot-reload is active; a plain --compile-so build
          without --hot-reload must not export a spurious epoch entry point. *)
       Buffer.add_string out
         "\ndefine void @__march_init(i32 %epoch) {\nentry:\n\
          \  store i32 %epoch, ptr @__march_hcr_epoch\n\
          \  ret void\n}\n"
     end else
     if m.Tir.tm_tests <> [] then begin
       (* --test mode: emit a @main that calls the test harness.
          For each test fn we emit a string constant for its display name and
          call march_test_run(fn_ptr, name_ptr, setup_or_null).
          setup_all and per-test setup are optional and may not exist. *)
       let has_setup_all = List.exists (fun (fn : Tir.fn_def) ->
           fn.Tir.fn_name = Tir_names.setup_all_fn_name) m.Tir.tm_fns in
       let has_setup = List.exists (fun (fn : Tir.fn_def) ->
           fn.Tir.fn_name = Tir_names.setup_fn_name) m.Tir.tm_fns in
       (* Emit test name string constants directly to out (preamble was already
          flushed to out above, so ctx.preamble writes would be lost). *)
       List.iteri (fun i (_fn_name, display_name) ->
         (* Use the same escaper as intern_string (llvm_escape_string): percent-
            encodes every byte outside printable ASCII and encodes " as \22 and
            \ as \5C.  LLVM parses these three-byte forms back to one byte, so
            String.length display_name + 1 remains the correct array size.
            The previous ad-hoc escaper only handled '\n' → \0A, leaving literal
            " and \ in place; LLVM's C-string parser then interpreted them as
            escape sequences, collapsing two-byte sequences to one byte so the
            actual payload was shorter than nbytes, and clang rejected the IR
            with "constant expression type mismatch". *)
         let escaped = Llvm_ctx.llvm_escape_string display_name in
         let nbytes = String.length display_name + 1 in
         Printf.bprintf out
           "@.test_name_%d = private constant [%d x i8] c\"%s\\00\"\n"
           i nbytes escaped
       ) m.Tir.tm_tests;
       let buf2 = Buffer.create 1024 in
       Buffer.add_string buf2
         "\ndeclare void @march_process_argv_init(i32 %argc, ptr %argv_ptr)\n";
       Buffer.add_string buf2
         "define i32 @main(i32 %argc, ptr %argv_ptr) {\nentry:\n";
       Buffer.add_string buf2
         "  call void @march_process_argv_init(i32 %argc, ptr %argv_ptr)\n";
       Buffer.add_string buf2
         "  call void @march_test_init(i32 %argc, ptr %argv_ptr)\n";
       if has_setup_all then
         Buffer.add_string buf2
           (Printf.sprintf "  call void @march_test_setup_all(ptr @%s)\n"
              (Llvm_ctx.llvm_name (Llvm_builtins.mangle_extern Tir_names.setup_all_fn_name)));
       let setup_arg = if has_setup then
         Printf.sprintf "ptr @%s" (Llvm_ctx.llvm_name (Llvm_builtins.mangle_extern Tir_names.setup_fn_name))
       else "ptr null" in
       List.iteri (fun i (fn_name, _display_name) ->
         let mangled = Llvm_ctx.llvm_name (Llvm_builtins.mangle_extern fn_name) in
         Printf.bprintf buf2
           "  call void @march_test_run(ptr @%s, ptr @.test_name_%d, %s)\n"
           mangled i setup_arg
       ) m.Tir.tm_tests;
       Buffer.add_string buf2 "  %rc = call i32 @march_test_report()\n";
       Buffer.add_string buf2 "  ret i32 %rc\n}\n";
       Buffer.add_buffer out buf2
     end else begin
       (match main_fn_name with
        | Some name ->
          let mangled = Llvm_ctx.llvm_name (Llvm_builtins.mangle_extern name) in
          Buffer.add_string out
            (Printf.sprintf "\ndeclare void @march_process_argv_init(i32 %%argc, ptr %%argv_ptr)\n\
             declare void @march_spawn_main(ptr %%fn)\n\
             define i32 @main(i32 %%argc, ptr %%argv_ptr) {\nentry:\n\
               call void @march_process_argv_init(i32 %%argc, ptr %%argv_ptr)\n\
               call void @march_remote_init()\n\
             %s%s\
               call void @march_spawn_main(ptr @%s)\n\
               call void @march_run_scheduler()\n\
               ret i32 0\n}\n" hr_setup stub_setup mangled)
        | None ->
          (* Library module with no user-defined main: emit a stub @main so
             clang can link a valid binary (forge build type-checks libraries). *)
          Buffer.add_string out
            "\ndefine i32 @main(i32 %argc, ptr %argv_ptr) {\nentry:\n  ret i32 0\n}\n")
     end);

  (* Generate the @march_atom_to_string reverse table into extra_fns (no-op
     unless a Show$Atom.show was emitted above).  Must precede the extra_fns
     flush; ctx.atom_names is complete now (all fn bodies emitted). *)
  emit_atom_show_table ctx;
  (* Append closure wrapper functions generated for top-level fn-as-value *)
  Buffer.add_buffer out ctx.Llvm_ctx.extra_fns;

  Llvm_ctx.repr_audit_report ();
  Buffer.contents out
